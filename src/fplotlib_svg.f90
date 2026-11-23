! SVG string builder for fplotlib.
module fplotlib_svg
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_status, only: contract_error
    implicit none
    private

    public :: svg_builder
    public :: builder_init
    public :: builder_append
    public :: builder_get
    public :: builder_clear
    public :: fmt_num, matrix_decimals
    public :: xml_escape_to

    integer, parameter :: BUILDER_INIT_CAP = 65536

    type :: svg_builder
        character(len=:), allocatable :: buf
        integer :: n = 0
        integer :: cap = 0
    end type svg_builder

contains

    subroutine builder_init(b, initial_cap)
        type(svg_builder), intent(out) :: b
        integer, intent(in), optional :: initial_cap
        integer :: c
        c = BUILDER_INIT_CAP
        if (present(initial_cap)) c = max(1024, initial_cap)
        if (allocated(b%buf)) deallocate (b%buf)
        allocate (character(len=c) :: b%buf)
        b%n = 0
        b%cap = c
    end subroutine builder_init

    subroutine builder_clear(b)
        type(svg_builder), intent(inout) :: b
        b%n = 0
    end subroutine builder_clear

    subroutine builder_grow(b, need)
        type(svg_builder), intent(inout) :: b
        integer, intent(in) :: need
        character(len=:), allocatable :: tmp
        integer :: new_cap, old_n
        if (need <= b%cap) return
        new_cap = max(b%cap * 2, need + 4096)
        old_n = b%n
        allocate (character(len=new_cap) :: tmp)
        if (old_n > 0) tmp(1:old_n) = b%buf(1:old_n)
        call move_alloc(tmp, b%buf)
        b%cap = new_cap
        b%n = old_n
    end subroutine builder_grow

    subroutine builder_append(b, s)
        type(svg_builder), intent(inout) :: b
        character(len=*), intent(in) :: s
        integer :: m
        m = len(s)
        if (m <= 0) return
        if (b%n + m > b%cap) call builder_grow(b, b%n + m)
        b%buf(b%n + 1:b%n + m) = s(1:m)
        b%n = b%n + m
    end subroutine builder_append

    function builder_get(b) result(s)
        type(svg_builder), intent(in) :: b
        character(len=:), allocatable :: s
        if (b%n <= 0) then
            allocate (character(len=0) :: s)
        else
            allocate (character(len=b%n) :: s)
            s = b%buf(1:b%n)
        end if
    end function builder_get

    subroutine fmt_num(x, s, n, decimals)
        ! Format a real into s(1:n) without using trim/adjustl allocators,
        ! to six decimals or as many as given, up to forty.
        real(dp), intent(in) :: x
        character(len=*), intent(out) :: s
        integer, intent(out) :: n
        integer, intent(in), optional :: decimals
        character(len=64) :: tmp
        character(len=12) :: form
        integer :: i, j, k, dot, d, w
        real(dp) :: zero

        if (x /= x) then
            s = "nan"
            n = 3
            return
        end if
        d = 6
        if (present(decimals)) d = max(6, min(40, decimals))
        zero = 1.0e-12_dp
        if (d > 6) zero = 0.5_dp*10.0_dp**(-d)
        if (abs(x) < zero) then
            s = "0"
            n = 1
            return
        end if

        ! The renderer contract keeps every coordinate and size within 1e15
        ! (MAX_COORD), which the field holds. The clamp is a last guard so
        ! that nothing can ever come out as asterisks.
        ! No more than seventeen significant digits, all a double holds:
        ! more would only write out its binary expansion.
        if (d > 6) d = max(6, min(d, 16 - floor(log10(abs(x)))))
        w = 18 + d
        if (d == 6) then
            write (tmp, "(F24.6)") max(-1.0e15_dp, min(1.0e15_dp, x))
        else
            write (form, "(a,i0,a,i0,a)") "(F", w, ".", d, ")"
            write (tmp, form) max(-1.0e15_dp, min(1.0e15_dp, x))
        end if
        ! left-trim spaces
        j = 1
        do while (j < w .and. tmp(j:j) == " ")
            j = j + 1
        end do
        ! copy and strip trailing zeros
        k = 0
        do i = j, w
            k = k + 1
            s(k:k) = tmp(i:i)
        end do
        ! remove trailing spaces
        do while (k > 0 .and. s(k:k) == " ")
            k = k - 1
        end do
        dot = 0
        do i = 1, k
            if (s(i:i) == ".") then
                dot = i
                exit
            end if
        end do
        if (dot > 0) then
            do while (k > dot .and. s(k:k) == "0")
                k = k - 1
            end do
            if (k == dot) k = k - 1
        end if
        if (k <= 0) then
            s = "0"
            n = 1
        else
            n = k
        end if
    end subroutine fmt_num

    ! Decimals that keep fifteen significant digits of x, a factor of a
    ! frame's matrix, at least six: a frame scaled by 4e-7 keeps its
    ! scale, which six decimals would write as 0.
    pure integer function matrix_decimals(x) result(d)
        real(dp), intent(in) :: x
        d = 6
        if (abs(x) > 0.0_dp .and. abs(x) < 1.0e9_dp) &
            d = max(6, min(40, 15 - floor(log10(abs(x)))))
    end function matrix_decimals

    ! s as XML character data or an attribute value, in out(1:n); out needs
    ! up to eight characters for each of s, and writing past its end is a
    ! contract error. Every code point has one written form, so two strings are
    ! written the same exactly when a reader reads them the same: printable
    ! ASCII as itself, & < > " as entities, any other code point XML 1.0
    ! can hold as a decimal reference, as every reader takes it the same
    ! way whatever it believes the encoding to be, and the rest (other
    ! control characters, surrogates, U+FFFE, U+FFFF, and anything past
    ! U+10FFFF) as U+FFFD. Tab, newline and return are references too: in
    ! an attribute a reader would read them raw as spaces. Bytes that
    ! decode to ASCII are written as that character. Trailing blanks are
    ! dropped, unless whole is given and true.
    subroutine xml_escape_to(s, out, n, whole)
        character(len=*), intent(in) :: s
        character(len=*), intent(out) :: out
        integer, intent(out) :: n
        logical, intent(in), optional :: whole
        integer :: i, m, code, nb, lp
        character(len=12) :: piece

        n = 0
        m = len_trim(s)
        if (present(whole)) then
            if (whole) m = len(s)
        end if
        i = 1
        do while (i <= m)
            call utf8_next(s, i, code, nb)
            i = i + max(1, nb)
            select case (code)
            case (38)
                piece = "&amp;"
                lp = 5
            case (60)
                piece = "&lt;"
                lp = 4
            case (62)
                piece = "&gt;"
                lp = 4
            case (34)
                piece = "&quot;"
                lp = 6
            case (32:33, 35:37, 39:59, 61, 63:126)
                piece = achar(code)
                lp = 1
            case default
                if ((code < 32 .and. code /= 9 .and. code /= 10 .and. code /= 13) .or. &
                    (code >= 55296 .and. code <= 57343) .or. &
                    code == 65534 .or. code == 65535 .or. code > 1114111) code = 65533
                write (piece, "(a,i0,a)") "&#", code, ";"
                lp = len_trim(piece)
            end select
            if (n + lp > len(out)) call contract_error("xml_escape_to: output buffer too short")
            out(n + 1:n + lp) = piece(1:lp)
            n = n + lp
        end do
    end subroutine xml_escape_to

end module fplotlib_svg
