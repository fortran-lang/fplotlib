! fplotlib_text -- strings laid out as glyphs.
!
! Every backend draws text from the compiled-in outlines, so the layout is
! done here, once, and handed to the backend as a run of positioned glyphs
! (fplotlib_render's glyphrun_t). What a string becomes:
!
!   * its UTF-8 is read into code points, and a base letter followed by a
!     combining accent is put back together into the precomposed letter,
!     as far as the repertoire has one, so text typed decomposed (NFD)
!     draws the same as text typed composed;
!   * the degree Celsius sign, which Lato has no glyph for, is written as
!     a degree sign and a C;
!   * each code point becomes the face's glyph for it, a space when the
!     face has none, so that an unexpected character cannot crash a plot;
!   * consecutive glyphs are spaced by their advance widths and the face's
!     pair kerning.
!
! The faces are Lato: regular, bold and italic; bold italic is set in
! bold.
module fplotlib_text
    use fplotlib_render_checks
    use fplotlib_resources
    use fplotlib_status
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_render, only: glyphrun_t, WEIGHT_BOLD, SLANT_ITALIC
    use fplotlib_glyphs
    implicit none
    private

    public :: text_face, text_layout, text_width
    public :: run_add, run_shift, run_reset, run_map, run_copy, code_points

contains

    ! The face a weight and a slant ask for.
    pure elemental integer function text_face(weight, slant) result(face)
        integer, intent(in) :: weight, slant
        logical :: b, i
        b = weight == WEIGHT_BOLD
        i = slant == SLANT_ITALIC
        ! There is no bold italic face; bold is the closer of the two.
        if (b) then
            face = FACE_BOLD
        else if (i) then
            face = FACE_ITALIC
        else
            face = FACE_REGULAR
        end if
    end function text_face

    ! Append s, set in face at size, to run, starting with the pen at
    ! (x0, y0). xend is where the pen is left.
    subroutine text_layout(s, size, face, x0, y0, run, xend, status)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size, x0, y0
        integer, intent(in) :: face
        type(glyphrun_t), intent(inout) :: run
        real(dp), intent(out) :: xend
        integer, allocatable :: cps(:), first(:), last(:)
        integer :: n, k, gid, prev, start, offset
        real(dp) :: pen

        type(status_t), intent(out) :: status

        call check_font(face, size, status=status)
        if (.not. status%ok()) return
        call check_finite([x0, y0], status=status)
        if (.not. status%ok()) return
        call check_glyphs(run, status=status)
        if (.not. status%ok()) return
        call code_points(s, cps, n, first, last)
        start = run%n + 1
        if (.not. allocated(run%text)) run%text = ""
        offset = len(run%text)
        pen = x0
        prev = 0
        do k = 1, n
            gid = glyph_cmap(face, cps(k))
            if (gid == 0) gid = glyph_cmap(face, 32)
            if (prev > 0) pen = pen + glyph_kern(face, prev, gid)*size
            call run_add(run, gid, pen, y0, size, status=status)
            if (.not. status%ok()) return
            pen = pen + glyph_adv(gid)*size
            prev = gid
        end do
        run%text = run%text//s
        if (n > 0) then
            run%first(start:run%n) = offset + first(1:n)
            run%last(start:run%n) = offset + last(1:n)
        end if
        xend = pen
    end subroutine text_layout

    ! Width of s in points, laid out exactly as text_layout lays it out.
    function text_width(s, size, face, status) result(w)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size
        integer, intent(in) :: face
        real(dp) :: w
        integer, allocatable :: cps(:)
        integer :: n, k, gid, prev

        type(status_t), intent(out) :: status

        w = 0.0_dp
        call check_font(face, size, status=status)
        if (.not. status%ok()) return
        call code_points(s, cps, n)
        w = 0.0_dp
        prev = 0
        do k = 1, n
            gid = glyph_cmap(face, cps(k))
            if (gid == 0) gid = glyph_cmap(face, 32)
            if (prev > 0) w = w + glyph_kern(face, prev, gid)*size
            w = w + glyph_adv(gid)*size
            prev = gid
        end do
    end function text_width

    ! The code points of s, with combining marks composed onto the letter
    ! before them where the repertoire has the result, and the characters
    ! that are spelled with two glyphs spelled out.
    subroutine code_points(s, cps, n, first, last)
        character(len=*), intent(in) :: s
        integer, allocatable, intent(out) :: cps(:)
        integer, intent(out) :: n
        integer, allocatable, intent(out), optional :: first(:), last(:)
        integer :: i, code, nb, c, start

        allocate (cps(2*len(s) + 1))
        if (present(first)) allocate (first(2*len(s) + 1))
        if (present(last)) allocate (last(2*len(s) + 1))
        n = 0
        i = 1
        do while (i <= len(s))
            start = i
            call utf8_next(s, i, code, nb)
            i = i + nb
            if (n > 0 .and. code >= 768 .and. code <= 879) then
                c = glyph_recompose(cps(n), code)
                if (c > 0) then
                    cps(n) = c
                    if (present(last)) last(n) = i - 1
                    cycle
                end if
            end if
            if (code == 8451) then
                ! Degree Celsius.
                cps(n + 1) = 176
                cps(n + 2) = iachar("C")
                if (present(first)) first(n + 1:n + 2) = start
                if (present(last)) last(n + 1:n + 2) = i - 1
                n = n + 2
                cycle
            end if
            n = n + 1
            cps(n) = code
            if (present(first)) first(n) = start
            if (present(last)) last(n) = i - 1
        end do
    end subroutine code_points

    ! --- runs --------------------------------------------------------

    subroutine run_reset(run)
        type(glyphrun_t), intent(inout) :: run
        run%n = 0
        run%text = ""
        run%source_math = .false.
    end subroutine run_reset

    subroutine run_add(run, gid, x, y, fs, status)
        type(glyphrun_t), intent(inout) :: run
        integer, intent(in) :: gid
        real(dp), intent(in) :: x, y, fs
        integer, allocatable :: ti(:)
        real(dp), allocatable :: t(:)
        integer :: cap

        type(status_t), intent(out) :: status

        call initialize_resources(status=status)
        if (.not. status%ok()) return
        call check_finite([x, y, fs], status=status)
        if (.not. status%ok()) return
        if (gid < 0 .or. gid > NGLYPH .or. fs < 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "run_add: invalid glyph or size")
            return
        end if
        if (.not. allocated(run%gid)) then
            allocate (run%gid(16), run%font(16), run%first(16), run%last(16), &
                      run%x(16), run%y(16), run%size(16))
        else if (run%n >= size(run%gid)) then
            cap = max(16, 2*size(run%gid))
            allocate (ti(cap))
            ti(1:run%n) = run%gid(1:run%n)
            call move_alloc(ti, run%gid)
            allocate (ti(cap))
            ti(1:run%n) = run%font(1:run%n)
            call move_alloc(ti, run%font)
            allocate (ti(cap))
            ti(1:run%n) = run%first(1:run%n)
            call move_alloc(ti, run%first)
            allocate (ti(cap))
            ti(1:run%n) = run%last(1:run%n)
            call move_alloc(ti, run%last)
            allocate (t(cap))
            t(1:run%n) = run%x(1:run%n)
            call move_alloc(t, run%x)
            allocate (t(cap))
            t(1:run%n) = run%y(1:run%n)
            call move_alloc(t, run%y)
            allocate (t(cap))
            t(1:run%n) = run%size(1:run%n)
            call move_alloc(t, run%size)
        end if
        run%n = run%n + 1
        run%gid(run%n) = gid
        run%font(run%n) = glyph_face(gid)
        run%first(run%n) = 0
        run%last(run%n) = 0
        run%x(run%n) = x
        run%y(run%n) = y
        run%size(run%n) = fs
    end subroutine run_add

    ! A cluster may contain several glyphs and several Unicode characters.
    subroutine run_map(run, first_glyph, last_glyph, text, math, status)
        type(glyphrun_t), intent(inout) :: run
        integer, intent(in) :: first_glyph, last_glyph
        character(len=*), intent(in) :: text
        logical, intent(in), optional :: math
        integer :: offset
        type(status_t), intent(out) :: status
        if (first_glyph <= last_glyph) then
            if (first_glyph < 1 .or. last_glyph > run%n) then
                call status%set(ERROR_ARGUMENT, "run_map: invalid glyph range")
                return
            end if
        end if
        if (.not. allocated(run%text)) run%text = ""
        offset = len(run%text)
        run%text = run%text//text
        if (present(math)) run%source_math = run%source_math .or. math
        if (first_glyph > last_glyph) return
        run%first(first_glyph:last_glyph) = offset + 1
        run%last(first_glyph:last_glyph) = len(run%text)
    end subroutine run_map

    subroutine run_copy(source, dest, status)
        type(glyphrun_t), intent(in) :: source
        type(glyphrun_t), intent(out) :: dest
        integer :: n
        type(status_t), intent(out) :: status

        call check_glyphs(source, status=status)
        if (.not. status%ok()) return
        n = source%n
        dest%n = n
        dest%source_math = source%source_math
        allocate (dest%gid(n), dest%font(n), dest%first(n), dest%last(n), &
                  dest%x(n), dest%y(n), dest%size(n))
        if (n > 0) then
            dest%gid = source%gid(1:n)
            dest%x = source%x(1:n)
            dest%y = source%y(1:n)
            dest%size = source%size(1:n)
            dest%font = 0
            dest%first = 0
            dest%last = 0
            if (allocated(source%font)) dest%font = source%font(1:n)
            if (allocated(source%first)) dest%first = source%first(1:n)
            if (allocated(source%last)) dest%last = source%last(1:n)
        end if
        dest%text = ""
        if (allocated(source%text)) dest%text = source%text
    end subroutine run_copy

    ! Move glyphs k0 to the end of the run by (dx, dy).
    subroutine run_shift(run, k0, dx, dy)
        type(glyphrun_t), intent(inout) :: run
        integer, intent(in) :: k0
        real(dp), intent(in) :: dx, dy
        integer :: k
        do k = max(k0, 1), run%n
            run%x(k) = run%x(k) + dx
            run%y(k) = run%y(k) + dy
        end do
    end subroutine run_shift

end module fplotlib_text
