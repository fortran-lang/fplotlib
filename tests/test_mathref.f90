! The math layout checked against XeTeX's.
!
! tests/math_refs.txt holds where XeTeX, setting each formula with the
! same Lato and Lete Sans Math files, puts every glyph and every rule
! (tools/gen_math_refs.py makes it). fplotlib's layout follows the same
! algorithm with the same MATH constants, so the two have to agree: every
! glyph is the same character at the same size, and it and every rule sit
! within TOL points of where XeTeX puts them.
module test_mathref
    use fplotlib_style, only: dp
    use fplotlib_render, only: glyphrun_t
    use fplotlib_mathtext, only: math_layout, mrules_t
    use fplotlib_glyphs, only: glyph_char
    implicit none
    private

    public :: math_ref_check

    ! How far, in points, a glyph or rule may sit from XeTeX's.
    real(dp), parameter :: TOL = 0.02_dp
    ! The size XeTeX sets the formulas at.
    real(dp), parameter :: SIZE = 10.0_dp
    integer, parameter :: MAXG = 256

contains

    subroutine math_ref_check(path, nfail)
        character(len=*), intent(in) :: path
        integer, intent(out) :: nfail
        character(len=512) :: line, formula
        integer :: u, ios, ng, nr, ncase
        integer :: gcp(MAXG)
        real(dp) :: gsz(MAXG), gx(MAXG), gy(MAXG), rb(4, MAXG)

        nfail = 0
        ncase = 0
        open (newunit=u, file=path, status="old", action="read", iostat=ios)
        if (ios /= 0) then
            print "(a)", "math refs: "//path//" not found"
            nfail = 1
            return
        end if
        formula = ""
        ng = 0
        nr = 0
        do
            read (u, "(a)", iostat=ios) line
            if (ios /= 0) exit
            if (len_trim(line) == 0 .or. line(1:1) == "#") cycle
            select case (line(1:2))
            case ("F ")
                if (len_trim(formula) > 0) then
                    call check_one(trim(formula), ng, gcp, gsz, gx, gy, nr, rb, nfail)
                    ncase = ncase + 1
                end if
                formula = line(3:)
                ng = 0
                nr = 0
            case ("G ")
                ng = ng + 1
                read (line(3:), *) gcp(ng), gsz(ng), gx(ng), gy(ng)
            case ("R ")
                nr = nr + 1
                read (line(3:), *) rb(:, nr)
            end select
        end do
        close (u)
        if (len_trim(formula) > 0) then
            call check_one(trim(formula), ng, gcp, gsz, gx, gy, nr, rb, nfail)
            ncase = ncase + 1
        end if
        print "(a,i0,a,i0,a)", "math refs: ", ncase, " formulas, ", nfail, &
            " differ from XeTeX"
    end subroutine math_ref_check

    subroutine check_one(formula, ng, gcp, gsz, gx, gy, nr, rb, nfail)
        character(len=*), intent(in) :: formula
        integer, intent(in) :: ng, nr, gcp(:)
        real(dp), intent(in) :: gsz(:), gx(:), gy(:), rb(:, :)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        real(dp) :: w, err, worst, r(4)
        integer :: k, c, j
        logical :: bad, used(MAXG)

        call math_layout(formula, SIZE, run, rules, w)
        bad = .false.
        worst = 0.0_dp
        if (run%n /= ng .or. rules%n /= nr) then
            print "(a,i0,a,i0,a,i0,a,i0,a)", "  "//formula//": ", run%n, " glyphs and ", &
                rules%n, " rules, XeTeX ", ng, " and ", nr, ""
            bad = .true.
        end if
        do k = 1, min(run%n, ng)
            c = glyph_char(run%gid(k))
            ! XeTeX names a glyph with no character of its own (a size
            ! variant, a character variant) by a private-use code point.
            if (c /= 0 .and. gcp(k) /= 0 .and. c /= gcp(k) &
                .and. (gcp(k) < 57344 .or. gcp(k) > 63743)) then
                print "(a,i0,a,i0,a,i0)", "  "//formula//": glyph ", k, " is U+", c, &
                    ", XeTeX U+", gcp(k)
                bad = .true.
            end if
            err = max(abs(run%size(k) - gsz(k)), abs(run%x(k) - gx(k)), &
                      abs(-run%y(k) - gy(k)))
            worst = max(worst, err)
            if (err > TOL) then
                print "(a,i0,a,3f9.4,a,3f9.4)", "  "//formula//": glyph ", k, &
                    " size, x, y", run%size(k), run%x(k), -run%y(k), &
                    "; XeTeX", gsz(k), gx(k), gy(k)
                bad = .true.
            end if
        end do
        ! Rules come in no particular order; each is matched to the
        ! nearest of XeTeX's.
        used = .false.
        do k = 1, rules%n
            r = [rules%x(k), -(rules%y(k) + rules%h(k)), rules%x(k) + rules%w(k), &
                 -rules%y(k)]
            err = huge(1.0_dp)
            c = 0
            do j = 1, nr
                if (used(j)) cycle
                if (maxval(abs(r - rb(:, j))) < err) then
                    err = maxval(abs(r - rb(:, j)))
                    c = j
                end if
            end do
            if (c > 0) used(c) = .true.
            worst = max(worst, err)
            if (err > TOL) then
                print "(a,i0,a,4f9.4)", "  "//formula//": rule ", k, " at", r
                if (c > 0) print "(a,4f9.4)", "      XeTeX at", rb(:, c)
                bad = .true.
            end if
        end do
        if (bad) nfail = nfail + 1
    end subroutine check_one

end module test_mathref
