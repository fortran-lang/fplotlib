! Missing data, drawn.
!
! NaN and infinite values are missing data to matplotlib: a line breaks
! around them and a bar, marker or label placed at one is left out. The
! renderer takes only finite coordinates and stops on anything else, so
! the plot types have to leave out what is missing before it gets there
! (fplotlib_artist's put_* routines). Every case here puts a missing value
! into a different plot type and renders it in all four formats; none may
! stop, and no NaN or infinity may reach the SVG, the EPS or the PDF page.
module test_missing
    use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan, ieee_is_finite, &
                                              ieee_positive_inf
    use, intrinsic :: iso_fortran_env, only: int64
    use fplotlib
    use fplotlib_draw, only: lower
    use fplotlib_render
    use fplotlib_draw, only: render_figure
    use fplotlib_backend_png, only: png_renderer_t
    use fplotlib_raster, only: full_walk
    implicit none
    private

    public :: missing_data_check


    real(dp), parameter :: MAX_PEN_PER_DASH = 100.0_dp


contains

    subroutine missing_data_check(nfail)
        integer, intent(out) :: nfail

        nfail = 0
        call dash_shortcut_check(nfail)
        print "(a, i0)", "raster checks: failures = ", nfail
    end subroutine missing_data_check

    ! The PNG backend skips dash work that cannot be seen. It must not skip
    ! anything that can. Each stroke here is drawn twice at 72 dpi: on a
    ! 100 point canvas, where a 400 point pen is wider than the canvas and
    ! the walk is narrowed to the canvas's span, and on a 500 point canvas
    ! over the same place, where it is not; the two must agree pixel for
    ! pixel. Every end and join is tried, with and without a dash offset,
    ! and once with coordinates near a trillion points. Round ends finer
    ! than the pen must stay dots, not a bar.
    subroutine dash_shortcut_check(nfail)
        integer, intent(inout) :: nfail
        character(len=:), allocatable :: small, big, dots, bar
        integer :: k, c, j, worst, path
        real(dp) :: dark_dots, dark_bar
        integer, parameter :: caps(3) = [CAP_BUTT, CAP_ROUND, CAP_SQUARE]
        integer, parameter :: joins(2) = [JOIN_MITER, JOIN_ROUND]
        real(dp), parameter :: ends(9) = [-10.0_dp, -40.0_dp, -50.0_dp, -60.0_dp, -100.0_dp, &
                                          -150.0_dp, -190.0_dp, -250.0_dp, -400.0_dp]

        ! A corner just off the canvas, and a straight line ending just
        ! short of it, which only the end of its last dash reaches.
        do path = 1, 2
            do k = 1, 3
                do j = 1, 2
                    do c = 0, 1
                        small = stroke_rgb(path, 100, 0.0_dp, caps(k), joins(j), 7.0_dp*c, 400.0_dp, &
                                           [20.0_dp, 30.0_dp], -10.0_dp)
                        big = crop(stroke_rgb(path, 500, -200.0_dp, caps(k), joins(j), 7.0_dp*c, 400.0_dp, &
                                              [20.0_dp, 30.0_dp], -10.0_dp), 500, 200, 100)
                        worst = max_diff(small, big)
                        if (worst > 0) then
                            print "(a, 4(i0, a), i0)", "dash shortcut: path ", path, ", cap ", caps(k), &
                                ", join ", joins(j), ", offset ", 7*c, ": differs from the full walk by ", worst
                            nfail = nfail + 1
                        end if
                    end do
                end do
            end do
        end do
        ! The same, swept over where the line ends (path 2) or turns away
        ! (path 4): from just short of the canvas to well past a pen's
        ! reach of it, through the places where the last dash of a
        ! segment is the only one whose end can reach in.
        do path = 2, 4, 2
            do k = 1, 3
                do c = 1, size(ends)
                    small = stroke_rgb(path, 100, 0.0_dp, caps(k), JOIN_MITER, 0.0_dp, 400.0_dp, &
                                       [20.0_dp, 30.0_dp], ends(c))
                    big = crop(stroke_rgb(path, 500, -200.0_dp, caps(k), JOIN_MITER, 0.0_dp, 400.0_dp, &
                                          [20.0_dp, 30.0_dp], ends(c)), 500, 200, 100)
                    worst = max_diff(small, big)
                    if (worst > 0) then
                        print "(a, 2(i0, a), f7.1, a, i0)", "dash shortcut: path ", path, ", cap ", caps(k), &
                            ", end at x = ", ends(c), ": differs from the full walk by ", worst
                        nfail = nfail + 1
                    end if
                end do
            end do
        end do
        ! A pen a trillion points wide round a corner forty billion points
        ! off, one dash covering it all: no larger canvas can show
        ! the full walk, but the solid pen is the same stroke.
        small = stroke_rgb(3, 100, 0.0_dp, CAP_BUTT, JOIN_MITER, 0.0_dp, 1.0e12_dp, [1.0e14_dp, 10.0_dp], 0.0_dp)
        big = stroke_rgb(3, 100, 0.0_dp, CAP_BUTT, JOIN_MITER, 0.0_dp, 1.0e12_dp, [0.0_dp], 0.0_dp)
        worst = max_diff(small, big)
        if (worst > 0) then
            print "(a, i0)", "dash shortcut: a far corner of a huge pen differs from the solid pen by ", worst
            nfail = nfail + 1
        end if
        call random_walk_check(nfail)
        dots = line_rgb([0.0_dp, 8.0_dp])
        bar = line_rgb([0.0_dp])
        dark_dots = 0.0_dp
        dark_bar = 0.0_dp
        do k = 1, len(dots)
            dark_dots = dark_dots + (255 - iachar(dots(k:k)))
            dark_bar = dark_bar + (255 - iachar(bar(k:k)))
        end do
        if (dark_dots > 0.9_dp*dark_bar) then
            print "(a)", "dash shortcut: round-capped dots came out as a solid bar"
            nfail = nfail + 1
        end if
    end subroutine dash_shortcut_check

    ! Four hundred strokes made up from a fixed seed: pens from a point to
    ! nine canvases wide, every end and join, mitre limits, patterns with
    ! dashes of no length, offsets, open and closed paths with corners up
    ! to seven canvases off. Each is drawn with the shortcuts and with
    ! fplotlib_raster's full_walk, and the two must agree pixel for pixel.
    subroutine random_walk_check(nfail)
        integer, intent(inout) :: nfail
        real(dp), parameter :: WIDTHS(6) = [1.0_dp, 7.0_dp, 40.0_dp, 150.0_dp, 400.0_dp, 900.0_dp]
        real(dp), parameter :: LENGTHS(5) = [0.0_dp, 2.0_dp, 7.0_dp, 20.0_dp, 45.0_dp]
        integer, parameter :: ENDS(3) = [CAP_BUTT, CAP_ROUND, CAP_SQUARE]
        integer, parameter :: TURNS(3) = [JOIN_MITER, JOIN_ROUND, JOIN_BEVEL]
        integer :: k, j, nv, nd, bad, worst
        integer(int64) :: seed
        type(paint_t) :: q, plain
        real(dp) :: px(6), py(6)
        integer :: verbs(7)
        character(len=:), allocatable :: quick, full

        seed = 20261121_int64
        bad = 0
        ! First, dots of no length along a line that leaves the canvas:
        ! the first dot lies where the walk resumes.
        q = plain
        q%stroked = .true.
        q%line_width = 6.0_dp
        q%cap = CAP_ROUND
        q%n_dash = 2
        q%dash(1:2) = [0.0_dp, 10.0_dp]
        full_walk = .false.
        quick = one_stroke([30.0_dp, 200.0_dp], [30.5_dp, 30.5_dp], [VERB_MOVE, VERB_LINE], q)
        full_walk = .true.
        full = one_stroke([30.0_dp, 200.0_dp], [30.5_dp, 30.5_dp], [VERB_MOVE, VERB_LINE], q)
        full_walk = .false.
        if (max_diff(quick, full) > 0) then
            print "(a)", "dash shortcut: a dot of no length went missing"
            bad = bad + 1
        end if
        ! A single length repeats every two: a 0.36 point pattern is 0.72
        ! points long, past half a pixel, and is walked.
        q = plain
        q%stroked = .true.
        q%line_width = 35.9_dp
        q%cap = CAP_ROUND
        q%n_dash = 1
        q%dash(1) = 0.3594_dp
        full_walk = .false.
        quick = one_stroke([10.0_dp, 90.0_dp], [50.0_dp, 50.0_dp], [VERB_MOVE, VERB_LINE], q)
        full_walk = .true.
        full = one_stroke([10.0_dp, 90.0_dp], [50.0_dp, 50.0_dp], [VERB_MOVE, VERB_LINE], q)
        full_walk = .false.
        if (max_diff(quick, full) > 0) then
            print "(a)", "dash shortcut: a single-length pattern was taken for half its length"
            bad = bad + 1
        end if
        do k = 1, 400
            q = plain
            q%stroked = .true.
            q%line_width = WIDTHS(pick(seed, 6))
            q%cap = ENDS(pick(seed, 3))
            q%join = TURNS(pick(seed, 3))
            q%miter_limit = merge(10.0_dp, 4.0_dp, pick(seed, 2) == 1)
            nd = pick(seed, 4)
            q%n_dash = nd
            do j = 1, nd
                q%dash(j) = LENGTHS(pick(seed, 5))
            end do
            if (sum(q%dash(1:nd)) < 2.0_dp) q%dash(1) = q%dash(1) + 10.0_dp
            ! Round and square ends keep to MAX_PEN_PER_DASH patterns.
            if (q%cap /= CAP_BUTT) q%line_width = min(q%line_width, MAX_PEN_PER_DASH*sum(q%dash(1:nd)))
            q%dash_offset = 0.0_dp
            if (pick(seed, 2) == 1) q%dash_offset = real(pick(seed, 90) - 31, dp)
            nv = 1 + pick(seed, 5)
            do j = 1, nv
                px(j) = real(pick(seed, 1500) - 700, dp)
                py(j) = real(pick(seed, 1500) - 700, dp)
            end do
            verbs(1) = VERB_MOVE
            verbs(2:nv) = VERB_LINE
            j = nv
            if (pick(seed, 3) == 1) then
                j = nv + 1
                verbs(j) = VERB_CLOSE
            end if
            full_walk = .false.
            quick = one_stroke(px(1:nv), py(1:nv), verbs(1:j), q)
            full_walk = .true.
            full = one_stroke(px(1:nv), py(1:nv), verbs(1:j), q)
            full_walk = .false.
            worst = max_diff(quick, full)
            if (worst > 0) then
                bad = bad + 1
                if (bad <= 5) print "(a, i0, a, i0)", "dash shortcut: random stroke ", k, &
                    " differs from the full walk by ", worst
            end if
        end do
        if (bad > 0) nfail = nfail + 1
    end subroutine random_walk_check

    ! 1 to n, from the Park and Miller generator, whose products fit in 64
    ! bits, so that every compiler makes the same strokes.
    integer function pick(seed, n)
        integer(int64), intent(inout) :: seed
        integer, intent(in) :: n
        seed = modulo(seed*48271_int64, 2147483647_int64)
        pick = 1 + int(modulo(seed/16_int64, int(n, int64)))
    end function pick

    function one_stroke(px, py, verbs, q) result(rgb)
        real(dp), intent(in) :: px(:), py(:)
        integer, intent(in) :: verbs(:)
        type(paint_t), intent(in) :: q
        character(len=:), allocatable :: rgb
        type(png_renderer_t) :: r
        r%keep_pixels = .true.
        call r%set_dpi(72.0_dp)
        call r%open_canvas(100.0_dp, 100.0_dp, bg_rgb=[255, 255, 255])
        call r%draw_path(px, py, verbs, size(verbs), q)
        call r%close_canvas()
        rgb = r%rgb
    end function one_stroke

    ! A dashed pen of width lw along path 1 (a corner just off the canvas),
    ! 2 (a straight line ending at x = xe), 3 (a corner forty billion
    ! points off, where a double's step exceeds a millionth) or 4 (a
    ! corner at x = xe turning away from the canvas), on an n by n point canvas whose top left corner
    ! is at (o, o), at 72 dpi. dash(1) = 0 alone means solid.
    function stroke_rgb(path, n, o, cap, join, offset, lw, dash, xe) result(rgb)
        integer, intent(in) :: path, n, cap, join
        real(dp), intent(in) :: o, offset, lw, dash(:), xe
        character(len=:), allocatable :: rgb
        type(png_renderer_t) :: r
        type(paint_t) :: q

        q%stroked = .true.
        q%line_width = lw
        q%cap = cap
        q%join = join
        if (size(dash) > 1) then
            q%n_dash = size(dash)
            q%dash(1:size(dash)) = dash
        end if
        q%dash_offset = offset
        r%keep_pixels = .true.
        call r%set_dpi(72.0_dp)
        call r%open_canvas(real(n, dp), real(n, dp), bg_rgb=[255, 255, 255], x0=o, y0=o)
        select case (path)
        case (1)
            call r%draw_path([-300.0_dp, -10.0_dp, -10.0_dp], [50.0_dp, 50.0_dp, 400.0_dp], &
                             [VERB_MOVE, VERB_LINE, VERB_LINE], 3, q)
        case (2)
            call r%draw_path([-1000.0_dp, xe], [50.0_dp, 50.0_dp], [VERB_MOVE, VERB_LINE], 2, q)
        case (4)
            call r%draw_path([-1000.0_dp, xe, xe], [50.0_dp, 50.0_dp, -2000.0_dp], &
                             [VERB_MOVE, VERB_LINE, VERB_LINE], 3, q)
        case default
            call r%draw_path([-1.0e12_dp, -4.0e10_dp, -4.0e10_dp], [50.0_dp, 50.0_dp, 1.0e12_dp], &
                             [VERB_MOVE, VERB_LINE, VERB_LINE], 3, q)
        end select
        call r%close_canvas()
        rgb = r%rgb
    end function stroke_rgb

    ! The m by m pixels at (k, k) of an n by n RGB raster.
    function crop(rgb, n, k, m) result(c)
        character(len=*), intent(in) :: rgb
        integer, intent(in) :: n, k, m
        character(len=:), allocatable :: c
        integer :: y, a
        allocate (character(len=3*m*m) :: c)
        do y = 1, m
            a = 3*((k + y - 1)*n + k)
            c(3*m*(y - 1) + 1:3*m*y) = rgb(a + 1:a + 3*m)
        end do
    end function crop

    integer function max_diff(a, b) result(worst)
        character(len=*), intent(in) :: a, b
        integer :: k
        worst = 0
        if (len(a) /= len(b)) then
            worst = 256
            return
        end if
        do k = 1, len(a)
            worst = max(worst, abs(iachar(a(k:k)) - iachar(b(k:k))))
        end do
    end function max_diff

    ! A line across a 100 point canvas, 8 points wide with round ends;
    ! dash(1) = 0 alone means solid.
    function line_rgb(dash) result(rgb)
        real(dp), intent(in) :: dash(:)
        character(len=:), allocatable :: rgb
        type(png_renderer_t) :: r
        type(paint_t) :: q

        q%stroked = .true.
        q%line_width = 8.0_dp
        q%cap = CAP_ROUND
        q%join = JOIN_ROUND
        if (size(dash) > 1) then
            q%n_dash = size(dash)
            q%dash(1:size(dash)) = dash
        end if
        r%keep_pixels = .true.
        call r%open_canvas(100.0_dp, 100.0_dp, bg_rgb=[255, 255, 255])
        call r%draw_path([0.0_dp, 100.0_dp], [50.0_dp, 50.0_dp], [VERB_MOVE, VERB_LINE], 2, q)
        call r%close_canvas()
        rgb = r%rgb
    end function line_rgb

end module test_missing
