! The math layout checked against XeTeX's.
!
! tests/math_refs.txt holds where XeTeX, setting each formula with the
! same Lato and Lete Sans Math files, puts every glyph and every rule
! (tools/gen_math_refs.py makes it). fplotlib's layout follows the same
! algorithm with the same MATH constants, so the two have to agree: every
! glyph is the same character at the same size, and it and every rule sit
! within TOL points of where XeTeX puts them.
!
! tests/delim_refs.txt holds the delimiters Typst sets around what they
! enclose (tools/gen_delim_refs.py makes it). fplotlib grows matched
! delimiters by Typst's rule, so it has to choose the same size variants:
! the delimiters, from left to right, have the same advance widths.
module test_mathref
    use fplotlib_status
    use test_status
    use fplotlib_style, only: dp
    use fplotlib_render, only: glyphrun_t
    use fplotlib_mathtext, only: math_layout, mrules_t, math_context_t
    use fplotlib_glyphs, only: glyph_char, glyph_cmap, glyph_face, glyph_inked, &
                               glyph_adv, FACE_BOLD, FACE_MATH
    implicit none
    private

    public :: math_ref_check, delim_ref_check, face_check

    ! How far, in points, a glyph or rule may sit from XeTeX's.
    real(dp), parameter :: TOL = 0.02_dp
    ! The size XeTeX sets the formulas at.
    real(dp), parameter :: SIZE = 10.0_dp
    integer, parameter :: MAXG = 256

    ! One context reused for every formula: it has to give the same layout
    ! as the scratch arenas of a call without one.
    type(math_context_t), save :: shared

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

    logical function same_layout(run, rules, w, run2, rules2, w2) result(same)
        type(glyphrun_t), intent(in) :: run, run2
        type(mrules_t), intent(in) :: rules, rules2
        real(dp), intent(in) :: w, w2
        integer :: n, m
        n = run%n
        m = rules%n
        same = w2 == w .and. run2%n == n .and. rules2%n == m
        if (.not. same) return
        if (n > 0) same = all(run2%gid(1:n) == run%gid(1:n)) .and. all(run2%x(1:n) == run%x(1:n)) &
                          .and. all(run2%y(1:n) == run%y(1:n)) .and. all(run2%size(1:n) == run%size(1:n))
        if (.not. same) return
        if (m > 0) same = all(rules2%x(1:m) == rules%x(1:m)) .and. all(rules2%y(1:m) == rules%y(1:m)) &
                          .and. all(rules2%w(1:m) == rules%w(1:m)) .and. all(rules2%h(1:m) == rules%h(1:m))
    end function same_layout

    subroutine check_one(formula, ng, gcp, gsz, gx, gy, nr, rb, nfail)
        character(len=*), intent(in) :: formula
        integer, intent(in) :: ng, nr
        integer, intent(inout) :: gcp(:)
        real(dp), intent(inout) :: gsz(:), gx(:), gy(:)
        real(dp), intent(in) :: rb(:, :)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run, run2
        type(mrules_t) :: rules, rules2
        real(dp) :: w, w2, err, worst, r(4)
        integer :: k, c, j
        logical :: bad, used(MAXG)
        real(dp) :: ry(MAXG)

        type(status_t) :: status
        call math_layout(formula, SIZE, run, rules, w, status=status)
        call require_ok(status)
        call math_layout(formula, SIZE, run2, rules2, w2, context=shared, status=status)
        call require_ok(status)
        if (.not. same_layout(run, rules, w, run2, rules2, w2)) then
            print "(a)", "  "//formula//": a reused context lays it out differently"
            nfail = nfail + 1
        end if
        ! A space is glue, which XeTeX does not write as a glyph.
        j = 0
        do k = 1, run%n
            if (.not. glyph_inked(run%gid(k))) cycle
            j = j + 1
            run%gid(j) = run%gid(k)
            run%x(j) = run%x(k)
            run%y(j) = run%y(k)
            run%size(j) = run%size(k)
        end do
        run%n = j
        ! XeTeX writes a box's glyphs in its own order (the limits of a
        ! display operator before the operator), so both sides are
        ! compared from left to right.
        ry(1:run%n) = -run%y(1:run%n)
        call sort_glyphs(run%n, run%gid, run%size, run%x, ry)
        run%y(1:run%n) = -ry(1:run%n)
        call sort_glyphs(ng, gcp, gsz, gx, gy)
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
            ! variant, a character variant) by a code point of its own
            ! choosing, so only the glyphs a character maps to are checked.
            if (glyph_cmap(glyph_face(run%gid(k)), c) /= run%gid(k)) c = 0
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

    subroutine delim_ref_check(path, nfail)
        character(len=*), intent(in) :: path
        integer, intent(out) :: nfail
        character(len=512) :: line, formula
        integer :: u, ios, nd, ncase
        integer :: dcp(MAXG)
        real(dp) :: dw(MAXG)

        nfail = 0
        ncase = 0
        open (newunit=u, file=path, status="old", action="read", iostat=ios)
        if (ios /= 0) then
            print "(a)", "delimiter refs: "//path//" not found"
            nfail = 1
            return
        end if
        formula = ""
        nd = 0
        do
            read (u, "(a)", iostat=ios) line
            if (ios /= 0) exit
            if (len_trim(line) == 0 .or. line(1:1) == "#") cycle
            select case (line(1:2))
            case ("F ")
                if (len_trim(formula) > 0) then
                    call check_delims(trim(formula), nd, dcp, dw, nfail)
                    ncase = ncase + 1
                end if
                formula = line(3:)
                nd = 0
            case ("D ")
                nd = nd + 1
                read (line(3:), *) dcp(nd), dw(nd)
            end select
        end do
        close (u)
        if (len_trim(formula) > 0) then
            call check_delims(trim(formula), nd, dcp, dw, nfail)
            ncase = ncase + 1
        end if
        print "(a,i0,a,i0,a)", "delimiter refs: ", ncase, " formulas, ", nfail, &
            " differ from Typst"
    end subroutine delim_ref_check

    subroutine check_delims(formula, nd, dcp, dw, nfail)
        character(len=*), intent(in) :: formula
        integer, intent(in) :: nd, dcp(:)
        real(dp), intent(in) :: dw(:)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        real(dp) :: w, ry(MAXG), sz(MAXG), x(MAXG)
        integer :: g(MAXG), k, n
        logical :: bad

        type(status_t) :: status
        call math_layout(formula, SIZE, run, rules, w, status=status)
        call require_ok(status)
        n = 0
        do k = 1, run%n
            select case (glyph_char(run%gid(k)))
            case (40, 41, 91, 93, 123, 125, 124, 8214, 10216, 10217, 8968:8971)
                n = n + 1
                g(n) = run%gid(k)
                sz(n) = run%size(k)
                x(n) = run%x(k)
                ry(n) = -run%y(k)
            end select
        end do
        call sort_glyphs(n, g, sz, x, ry)
        bad = n /= nd
        do k = 1, min(n, nd)
            if (glyph_char(g(k)) /= dcp(k) .or. &
                abs(glyph_adv(g(k))*sz(k) - dw(k)) > 0.005_dp) bad = .true.
        end do
        if (bad) then
            print "(a)", "  "//formula//": delimiters"
            print "(a,*(1x,i0,':',f0.3))", "    fplotlib", &
                (glyph_char(g(k)), glyph_adv(g(k))*sz(k), k=1, n)
            print "(a,*(1x,i0,':',f0.3))", "    Typst   ", (dcp(k), dw(k), k=1, nd)
            nfail = nfail + 1
        end if
    end subroutine check_delims

    ! The words around a formula are set in the face the label asks for,
    ! and the formula in the math font.
    subroutine face_check(nfail)
        integer, intent(out) :: nfail
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        real(dp) :: w

        type(status_t) :: status
        nfail = 0
        call math_layout("Bold $x$ bold", SIZE, run, rules, w, FACE_BOLD, status=status)
        call require_ok(status)
        if (glyph_face(run%gid(1)) /= FACE_BOLD .or. glyph_face(run%gid(6)) /= FACE_MATH &
            .or. glyph_face(run%gid(run%n)) /= FACE_BOLD) then
            print "(a)", "  text around math does not keep the label's face"
            nfail = 1
        end if
    end subroutine face_check

    ! Sorts glyphs by x, and those within a hundredth of a point of each
    ! other in x from the top down.
    subroutine sort_glyphs(n, g, sz, x, y)
        integer, intent(in) :: n
        integer, intent(inout) :: g(:)
        real(dp), intent(inout) :: sz(:), x(:), y(:)
        integer :: i, j, tg
        real(dp) :: ts, tx, ty

        do i = 2, n
            tg = g(i)
            ts = sz(i)
            tx = x(i)
            ty = y(i)
            j = i - 1
            do while (j >= 1)
                if (.not. after(x(j), y(j), tx, ty)) exit
                g(j + 1) = g(j)
                sz(j + 1) = sz(j)
                x(j + 1) = x(j)
                y(j + 1) = y(j)
                j = j - 1
            end do
            g(j + 1) = tg
            sz(j + 1) = ts
            x(j + 1) = tx
            y(j + 1) = ty
        end do
    contains
        logical function after(xa, ya, xb, yb)
            real(dp), intent(in) :: xa, ya, xb, yb
            if (abs(xa - xb) > 0.01_dp) then
                after = xa > xb
            else
                after = ya < yb
            end if
        end function after
    end subroutine sort_glyphs

end module test_mathref
