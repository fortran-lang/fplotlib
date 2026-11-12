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
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_render, only: glyphrun_t, WEIGHT_BOLD, SLANT_ITALIC
    use fplotlib_glyphs, only: glyph_cmap, glyph_adv, glyph_kern, &
                               glyph_recompose, FACE_REGULAR, FACE_BOLD, &
                               FACE_ITALIC
    implicit none
    private

    public :: text_face, text_layout, text_width
    public :: run_add, run_shift, run_reset, code_points

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
    subroutine text_layout(s, size, face, x0, y0, run, xend)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size, x0, y0
        integer, intent(in) :: face
        type(glyphrun_t), intent(inout) :: run
        real(dp), intent(out) :: xend
        integer, allocatable :: cps(:)
        integer :: n, k, gid, prev
        real(dp) :: pen

        call code_points(s, cps, n)
        pen = x0
        prev = 0
        do k = 1, n
            gid = glyph_cmap(face, cps(k))
            if (gid == 0) gid = glyph_cmap(face, 32)
            if (prev > 0) pen = pen + glyph_kern(face, prev, gid)*size
            call run_add(run, gid, pen, y0, size)
            pen = pen + glyph_adv(gid)*size
            prev = gid
        end do
        xend = pen
    end subroutine text_layout

    ! Width of s in points, laid out exactly as text_layout lays it out.
    function text_width(s, size, face) result(w)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size
        integer, intent(in) :: face
        real(dp) :: w
        integer, allocatable :: cps(:)
        integer :: n, k, gid, prev

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
    subroutine code_points(s, cps, n)
        character(len=*), intent(in) :: s
        integer, allocatable, intent(out) :: cps(:)
        integer, intent(out) :: n
        integer :: i, code, nb, c

        allocate (cps(2*len(s) + 1))
        n = 0
        i = 1
        do while (i <= len(s))
            call utf8_next(s, i, code, nb)
            i = i + nb
            if (n > 0 .and. code >= 768 .and. code <= 879) then
                c = glyph_recompose(cps(n), code)
                if (c > 0) then
                    cps(n) = c
                    cycle
                end if
            end if
            if (code == 8451) then
                ! Degree Celsius.
                cps(n + 1) = 176
                cps(n + 2) = iachar("C")
                n = n + 2
                cycle
            end if
            n = n + 1
            cps(n) = code
        end do
    end subroutine code_points

    ! --- runs --------------------------------------------------------

    subroutine run_reset(run)
        type(glyphrun_t), intent(inout) :: run
        run%n = 0
    end subroutine run_reset

    subroutine run_add(run, gid, x, y, fs)
        type(glyphrun_t), intent(inout) :: run
        integer, intent(in) :: gid
        real(dp), intent(in) :: x, y, fs
        integer, allocatable :: ti(:)
        real(dp), allocatable :: t(:)
        integer :: cap

        if (.not. allocated(run%gid)) then
            allocate (run%gid(16), run%x(16), run%y(16), run%size(16))
        else if (run%n >= size(run%gid)) then
            cap = 2*size(run%gid)
            allocate (ti(cap))
            ti(1:run%n) = run%gid(1:run%n)
            call move_alloc(ti, run%gid)
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
        run%x(run%n) = x
        run%y(run%n) = y
        run%size(run%n) = fs
    end subroutine run_add

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
