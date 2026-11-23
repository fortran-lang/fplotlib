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
    use fplotlib_style, only: lower
    use fplotlib_render
    use fplotlib_draw, only: render_figure
    use fplotlib_backend_png, only: png_renderer_t, png_pixels
    use fplotlib_raster, only: full_walk
    use fplotlib_ticks, only: multiple_ticks, format_grouped, format_percent, MAX_TICKS, log_ticks, &
                              format_tick_to, linear_ticks
    use fplotlib_dates, only: num_date
    use fplotlib_contour, only: contour_levels
    implicit none
    private

    public :: missing_data_check

    ! Records the furthest any coordinate handed to it lies from zero, so
    ! that the test can check what the plotting layer draws, not only what
    ! a file format makes of it.
    type, extends(renderer_t) :: extent_renderer_t
        real(dp) :: far = 0.0_dp
        real(dp) :: widest = 0.0_dp   ! the widest stroke
    contains
        procedure :: open_canvas_impl => ext_open
        procedure :: close_canvas_impl => ext_close
        procedure :: draw_path_impl => ext_path
        procedure :: draw_rect_impl => ext_rect
        procedure :: draw_circle_impl => ext_circle
        procedure :: draw_markers_impl => ext_markers
        procedure :: draw_glyphs_impl => ext_glyphs
        procedure :: draw_image_impl => ext_image
    end type extent_renderer_t

    integer, parameter :: NCASE = 98

contains

    subroutine missing_data_check(nfail)
        integer, intent(out) :: nfail
        integer :: k

        nfail = 0
        do k = 1, NCASE
            call figure()
            call draw_case(k)
            call check_case(k, nfail)
            call close()
        end do
        call dash_shortcut_check(nfail)
        call size_status_check(nfail)
        call far_ticks_check(nfail)
        print "(a, i0, a, i0)", "missing data: ", NCASE, " plots, failures = ", nfail
    end subroutine missing_data_check

    ! Ticks and labels for values past a default integer: Unix times in
    ! steps of half a second, and counts in the billions.
    subroutine far_ticks_check(nfail)
        integer, intent(inout) :: nfail
        real(dp) :: t(MAX_TICKS)
        integer :: n, y, mo, dd, hh, mi, sec, i, ios
        character(len=64) :: s
        real(dp) :: lv(64), back, lo, hi
        character(len=8) :: lab
        real(dp), parameter :: near(4) = [3.0e-308_dp, 5.0e-309_dp, 2.0e-310_dp, 8.0e-310_dp]
        real(dp), parameter :: thr(4) = [1.0e-300_dp, 1.0e-200_dp, 1.0e-3_dp, 1.0_dp]
        real(dp) :: yy(2)
        integer :: j
        real(dp), parameter :: far(6) = [2.5e20_dp, -4.5e100_dp, 1.2e300_dp, 1.2e308_dp, &
                                         3.0e20_dp, -1.7976e308_dp]

        call multiple_ticks(1.7e9_dp, 1.7e9_dp + 5.0_dp, 0.5_dp, t, n)
        if (n /= 11 .or. abs(t(1) - 1.7e9_dp) > 0.0_dp) then
            print "(a, i0)", "far ticks: multiple_ticks gave ", n
            nfail = nfail + 1
        end if
        call format_grouped(2.5e9_dp, 0, s, n)
        if (s(1:n) /= "2,500,000,000") then
            print "(a)", "far ticks: format_grouped wrote "//s(1:n)
            nfail = nfail + 1
        end if
        call format_percent(3.0e7_dp, 1.0_dp, 0, s, n)
        if (s(1:n) /= "3000000000%") then
            print "(a)", "far ticks: format_percent wrote "//s(1:n)
            nfail = nfail + 1
        end if
        ! A log axis of three hundred decades is ticked from end to end, not
        ! for its first thirty-two decades only.
        call log_ticks(1.0_dp, 1.0e300_dp, t, n)
        if (n < 5 .or. n > 12 .or. t(n) < 1.0e250_dp) then
            print "(a, i0, a, es10.3)", "far ticks: log_ticks of 300 decades gave ", n, " up to ", t(n)
            nfail = nfail + 1
        end if
        ! A tick past a fixed field is written in exponent form, and reads
        ! back as the value it labels, exponents ending in zero included.
        do i = 1, size(far)
            call format_tick_to(far(i), .false., s, n)
            read (s(1:n), *, iostat=ios) back
            if (ios /= 0 .or. abs(back - far(i)) > 1.0e-4_dp*abs(far(i))) then
                print "(a, es10.3, a)", "far ticks: format_tick_to wrote ", far(i), " as "//s(1:n)
                nfail = nfail + 1
            end if
        end do
        ! A narrow range far from zero is ticked across, not in a heap of
        ! MAX_TICKS steps of one at its low end.
        call linear_ticks(1.7e18_dp, 1.7e18_dp + 1.0e6_dp, 8, t, n)
        if (n < 3 .or. n > 12 .or. t(n) - t(1) < 5.0e5_dp) then
            print "(a, i0)", "far ticks: a range of 1e6 at 1.7e18 had ticks ", n
            nfail = nfail + 1
        end if
        ! A percentage past the largest double, and a log decade below
        ! 1e-30, are labelled with their values.
        call format_percent(1.0e307_dp, 1.0_dp, 0, s, n)
        if (s(1:n) /= "1e309%") then
            print "(a)", "far ticks: format_percent wrote "//s(1:n)
            nfail = nfail + 1
        end if
        call format_tick_to(1.0e-69_dp, .true., s, n)
        if (index(s(1:n), "-69") == 0) then
            print "(a)", "far ticks: a log tick of 1e-69 was written "//s(1:n)
            nfail = nfail + 1
        end if
        ! Values near and below the least normal double that are no decade
        ! are not labelled as one.
        do i = 1, size(near)
            call format_tick_to(near(i), .true., s, n)
            if (index(s(1:n), "10^") > 0) then
                print "(a, es10.3, a)", "far ticks: ", near(i), " was labelled the decade "//s(1:n)
                nfail = nfail + 1
            end if
        end do
        ! Equal limits near the largest double stay finite, and limits near
        ! zero on a log axis stay positive.
        call figure()
        call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
        call ylim(1.75e308_dp, 1.75e308_dp)
        call get_ylim(lo, hi)
        if (.not. (ieee_is_finite(lo) .and. ieee_is_finite(hi) .and. hi > lo)) then
            print "(a, 2es12.4)", "far ticks: equal limits of 1.75e308 became ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        call figure()
        call semilogy([0.0_dp, 1.0_dp], [2.0e-303_dp, 8.0e-303_dp])
        call ylim(1.0e-303_dp, 1.0e-302_dp)
        call get_ylim(lo, hi)
        if (lo /= 1.0e-303_dp .or. hi /= 1.0e-302_dp) then
            print "(a, 2es12.4)", "far ticks: log limits 1e-303 to 1e-302 became ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        ! A symlog axis with a small threshold takes its margin from the data,
        ! not from a unit its own units are far smaller than.
        call figure()
        call plot([1.0_dp, 2.0_dp, 3.0_dp], [-1.0_dp, 0.5_dp, 1.0e200_dp])
        call set_yscale("symlog", linthresh=1.0e-200_dp)
        call get_ylim(lo, hi)
        if (lo < -1.0e40_dp .or. lo > -1.0_dp .or. hi < 1.0e200_dp .or. hi > 1.0e240_dp) then
            print "(a, 2es12.4)", "far ticks: symlog with linthresh 1e-200 autoscaled to ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        ! Data the axis can tell apart is not widened, however small its
        ! threshold: a step of 1e-7 at 1e300, at linthresh 1e-300.
        call figure()
        call plot([1.0_dp, 2.0_dp, 3.0_dp, 4.0_dp], 1.0e300_dp*(1.0_dp + 1.0e-7_dp*[0.0_dp, 1.0_dp, 3.0_dp, 2.0_dp]))
        call set_yscale("symlog", linthresh=1.0e-300_dp)
        call get_ylim(lo, hi)
        if (lo < 0.99999e300_dp .or. hi > 1.00001e300_dp) then
            print "(a, 2es24.16)", "far ticks: data 1e-7 apart at 1e300 on symlog 1e-300 widened to ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        ! Hand-set limits on a symlog axis that it cannot tell apart are
        ! widened as autoscaled ones are, and so are limits with no margin.
        call figure()
        call plot([1.0_dp, 2.0_dp], [1.0_dp, 2.0_dp])
        call set_yscale("symlog", linthresh=1.0e-3_dp)
        call ylim(1.0e300_dp, 1.0e300_dp*(1.0_dp + 5.0e-14_dp))
        call get_ylim(lo, hi)
        if (hi - lo < 1.0e297_dp) then
            print "(a, 2es24.16)", "far ticks: hand-set symlog limits it cannot part stayed ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        call figure()
        call plot([1.0_dp, 2.0_dp], [1.0e300_dp, 1.0e300_dp*(1.0_dp + 5.0e-14_dp)])
        call set_yscale("symlog", linthresh=1.0e-3_dp)
        call margins(0.0_dp)
        call get_ylim(lo, hi)
        if (hi - lo < 1.0e297_dp) then
            print "(a, 2es24.16)", "far ticks: near-constant symlog data with no margin has limits ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        ! Data a few subnormal steps apart, which the transform rounds to
        ! whole steps, is widened rather than drawn bent.
        call figure()
        call plot([1.0_dp, 2.0_dp, 3.0_dp], [1.0_dp, 2.0_dp, 3.0_dp]*5.0e-324_dp)
        call set_yscale("symlog")
        call get_ylim(lo, hi)
        if (hi < 1.0e-310_dp) then
            print "(a, 2es24.16)", "far ticks: subnormal data on symlog has limits ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        ! A constant series on a symlog axis, whatever its threshold, gets
        ! limits about it, not a margin of the whole range of a double; so
        ! does a series a few roundings apart, which the transform cannot
        ! tell apart either, and one far out, where it rounds more coarsely.
        do i = 1, size(thr)
            do j = 0, 3
                call figure()
                select case (j)
                case (0); yy = [5.0_dp, 5.0_dp]
                case (1); yy = [1.0_dp, 1.0_dp + 5.0_dp*epsilon(1.0_dp)]
                case (2); yy = [1.0_dp, 1.0_dp + 5.0e-14_dp]
                case (3); yy = [1.0e300_dp, 1.0e300_dp*(1.0_dp + 5.0e-14_dp)]
                end select
                call plot([1.0_dp, 2.0_dp], yy)
                call set_yscale("symlog", linthresh=thr(i))
                call get_ylim(lo, hi)
                if (.not. (lo > 0.2_dp*yy(1) .and. lo < yy(1) .and. hi > yy(2) .and. hi < 5.0_dp*yy(2))) then
                    print "(a, es9.2, a, es9.2, a, 2es12.4)", "far ticks: near-constant ", yy(1), &
                        " on symlog, linthresh ", thr(i), ", has limits ", lo, hi
                    nfail = nfail + 1
                end if
                call close()
            end do
        end do
        ! A constant series near the largest double has finite log limits.
        call figure()
        call semilogy([0.0_dp, 1.0_dp], [1.0e308_dp, 1.0e308_dp])
        call get_ylim(lo, hi)
        if (.not. (ieee_is_finite(lo) .and. ieee_is_finite(hi) .and. lo > 0.0_dp .and. hi > lo)) then
            print "(a, 2es12.4)", "far ticks: log limits of a constant 1e308 series are ", lo, hi
            nfail = nfail + 1
        end if
        call close()
        ! Subnormal decades too, where 10**expn underflows.
        do i = 309, 323, 7
            call format_tick_to(10.0_dp**real(-i, dp), .true., s, n)
            write (lab, "(I0)") -i
            if (index(s(1:n), trim(lab)) == 0) then
                print "(a)", "far ticks: a log tick of 1e"//trim(lab)//" was written "//s(1:n)
                nfail = nfail + 1
            end if
        end do
        ! Contour levels of data far from zero in small steps cover it.
        call contour_levels(1.0e9_dp, 1.0e9_dp + 0.5_dp, 7, lv, n)
        if (n < 2 .or. lv(1) > 1.0e9_dp .or. lv(n) < 1.0e9_dp + 0.5_dp .or. lv(1) < 1.0e9_dp - 1.0_dp) then
            print "(a, i0)", "far ticks: contour levels of offset data, count ", n
            nfail = nfail + 1
        end if
        ! Fixed decimals that would not fit go to exponent form, not stars.
        call format_grouped(1.0e15_dp, 17, s, n)
        if (index(s(1:n), "*") > 0) then
            print "(a)", "far ticks: format_grouped wrote "//s(1:n)
            nfail = nfail + 1
        end if
        ! Two billion days out, a date still has its time of day; further
        ! out, the calendar stops at its edge rather than overflowing.
        call num_date(2.0e9_dp + 0.5_dp, y, mo, dd, hh, mi, sec)
        if (hh /= 12 .or. mi /= 0) then
            print "(a, i0)", "far ticks: a date two billion days out has hour ", hh
            nfail = nfail + 1
        end if
        call num_date(1.0e15_dp + 0.25_dp, y, mo, dd, hh, mi, sec)
        if (hh /= 6) then
            print "(a, i0)", "far ticks: a date past the calendar has hour ", hh
            nfail = nfail + 1
        end if
    end subroutine far_ticks_check

    ! A label placed a million points off makes a tight crop too large for
    ! a PNG: a failure at run time, which savefig returns in its status.
    subroutine size_status_check(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: st
        character(len=:), allocatable :: png
        type(png_renderer_t) :: r
        real(dp) :: w, h, d
        integer :: k

        ! Every check of a PNG's size counts its pixels as the canvas comes
        ! out, rounding included.
        do k = 1, 6
            w = 10.0_dp + 37.3_dp*k
            h = 5.0_dp + 11.7_dp*k
            d = 50.0_dp + 23.9_dp*k
            r%keep_pixels = .true.
            call r%set_dpi(d)
            call r%open_canvas(w, h)
            call r%close_canvas()
            if (png_pixels(w, h, d) /= real(r%pw, dp)*real(r%ph, dp)) then
                print "(a, i0)", "size status: png_pixels miscounts a canvas, case ", k
                nfail = nfail + 1
            end if
            deallocate (r%rgb)
        end do

        ! A figure too large for a PNG whole, cropped tight to the little
        ! that is drawn in it, saves.
        call figure(figsize=[150.0_dp, 150.0_dp], dpi=100.0_dp)
        call subplots_adjust(left=0.45_dp, right=0.55_dp, bottom=0.45_dp, top=0.55_dp)
        call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
        call savefig("tests/out/missing_size.png", bbox_inches="tight", status=st)
        if (.not. st%ok()) then
            print "(a, i0)", "size status: a tight crop that fits did not save, code ", st%code
            nfail = nfail + 1
        end if
        call close()

        call figure()
        call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
        call ylabel("y", labelpad=1.0e6_dp)
        call savefig("tests/out/missing_size.png", bbox_inches="tight", status=st)
        if (st%code /= ERROR_SIZE) then
            print "(a, i0)", "size status: expected ERROR_SIZE from a tight PNG too large, got ", st%code
            nfail = nfail + 1
        end if
        png = render_png(bbox_inches="tight", status=st)
        if (st%code /= ERROR_SIZE .or. len(png) /= 0) then
            print "(a, i0)", "size status: expected ERROR_SIZE and nothing from render_png, got ", st%code
            nfail = nfail + 1
        end if
        call close()
    end subroutine size_status_check

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

    subroutine draw_case(k)
        integer, intent(in) :: k
        real(dp) :: nan, inf, x(6), y(6), e(6), t(6), z(5, 5), g(5), m(2, 3)
        real(dp) :: tx(5), ty(5), tz(5)
        type(axes) :: sec
        integer :: i, j

        nan = ieee_value(nan, ieee_quiet_nan)
        inf = ieee_value(inf, ieee_positive_inf)
        x = [1.0_dp, 2.0_dp, 3.0_dp, 4.0_dp, 5.0_dp, 6.0_dp]
        y = [1.0_dp, nan, 3.0_dp, inf, 2.0_dp, 4.0_dp]
        e = [0.1_dp, 0.2_dp, nan, 0.1_dp, 0.3_dp, 0.1_dp]
        t = x - 1.0_dp
        g = x(1:5)
        do j = 1, 5
            do i = 1, 5
                z(i, j) = real(i*j, dp)
            end do
        end do
        z(2, 3) = nan
        z(4, 4) = inf
        tx = [0.0_dp, 1.0_dp, 0.0_dp, 1.0_dp, 0.5_dp]
        ty = [0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, 0.5_dp]
        tz = [1.0_dp, 2.0_dp, nan, 3.0_dp, 2.0_dp]
        m = reshape([1.0_dp, nan, 2.0_dp, 1.0_dp, 1.0_dp, 1.0_dp], [2, 3])

        select case (k)
        case (1); call plot(x, y, "o-")
        case (2); call bar(x, y)
        case (3); call barh(x, y)
        case (4); call bar(x, y, yerr=e)
        case (5); call errorbar(x, y, yerr=e)
        case (6); call errorbar(x, x, xerr=e)
        case (7); call boxplot(y)
        case (8); call violinplot(y)
        case (9); call contour(z)
        case (10); call contourf(z)
        case (11); call contour(z); call clabel()
        case (12); call imshow(z); call colorbar()
        case (13); call pcolormesh(t, t, z)
        case (14); call scatter(x, y, sizes=y)
        case (15); call scatter(x, x, cvals=y); call colorbar()
        case (16); call hist(y)
        case (17); call hist2d(x, y)
        case (18); call hexbin(x, y)
        case (19); call pie([1.0_dp, nan, 2.0_dp])
        case (20); call fill_between(x, y)
        case (21); call step(x, y)
        case (22); call stem(x, y)
        case (23); call stackplot([1.0_dp, 2.0_dp, 3.0_dp], m)
        case (24); call quiver(x, x, y, x)
        case (25); call streamplot(g, g, z, z)
        case (26); call plot(x, x); call axvline(nan); call axhline(inf)
        case (27); call plot(x, x); call axhspan(nan, 1.0_dp)
        case (28); call hlines(y, 0.0_dp, 1.0_dp)
        case (29); call eventplot(y)
        case (30); call broken_barh(reshape([nan, 1.0_dp, 3.0_dp, 1.0_dp], [2, 2]), &
                                    [0.0_dp, 1.0_dp])
        case (31); call plot(x, x); call text(nan, 1.0_dp, "missing")
        case (32); call plot(x, x); call annotate("a", nan, 1.0_dp, 2.0_dp, 2.0_dp)
        case (33); call polar(t, y)
        case (34); call tricontourf(tx, ty, tz)
        case (35); call tripcolor(tx, ty, tz)
        case (36); call plot_surface(g, g, z)
        case (37); call plot_wireframe(g, g, z)
        case (38); call contour3d(g, g, z)
        case (39); call plot3d(x, y, x)
        case (40); call scatter3d(x, y, x)
        case (41); call bar3d(x, x, x, 0.5_dp, 0.5_dp, y)
        case (42); call quiver3d(x, x, x, y, x, x)
        case (43); call plot_trisurf(tx, ty, tz)
        ! Limits too close to tell apart are widened, not divided by.
        case (44); call plot(x, x); call xlim(2.0_dp, 2.0_dp); call ylim(0.0_dp, 1.0e-320_dp)
        ! Nothing but missing data: no extent, and a colorbar with no range.
        case (45); call boxplot([nan, nan, nan])
        case (46); call scatter(x, x, cvals=[nan, nan, nan, nan, nan, nan]); call colorbar()
        case (47); call pcolormesh(t(1:3), t(1:3), reshape([nan, nan, nan, inf], [2, 2])); call colorbar()
        case (48); call scatter3d(y, y, y)
        ! A missing first vertex must not let the polygon close across the gap.
        case (49); call add_polygon([nan, 1.0_dp, 1.0_dp, 0.0_dp], [0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp])
        ! Layouts that leave the axes or the colorbar no room are not drawn.
        case (50); call close(); call figure(figsize=[1.5_dp, 1.0_dp]); call plot(x, x)
            call title("Title"); call xlabel("x"); call ylabel("y"); call tight_layout()
        case (51); call imshow(z); call colorbar(fraction=0.99_dp, pad=0.5_dp)
        case (52); call plot(y, x)
        ! A negative pad, which matplotlib takes, shrinks the box past nothing.
        case (53); call plot(x, x); call text(2.0_dp, 2.0_dp, "t", bbox_facecolor="red", bbox_pad=-2.0_dp)
        ! Finite data far outside the view, and data spanning every double.
        case (54); call bar([0.0_dp, 1.0_dp], [1.0_dp, 1.0e15_dp]); call ylim(0.0_dp, 2.0_dp)
        case (55); call fill_between(t(1:3), [0.0_dp, 1.0e20_dp, 0.0_dp]); call ylim(0.0_dp, 1.0_dp)
        case (56); call plot(x, x, lw=1.0e300_dp)
        case (57); call hist2d([-huge(1.0_dp), huge(1.0_dp), 0.0_dp], [0.0_dp, 1.0_dp, 2.0_dp])
        case (58); call plot(x, x); sec = secondary_xaxis("top", scale=2.0_dp)
        ! Far off the view: a fill value of 1e30, a dashed line far longer
        ! than the canvas, text and a marker out of all proportion.
        case (59); call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0e30_dp]); call ylim(0.0_dp, 1.0_dp)
        case (60); call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0e7_dp], linestyle="--"); call ylim(0.0_dp, 1.0_dp)
        case (61); call plot(x, x); call text(1.0e300_dp, 1.0_dp, "far")
        case (62); call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], "o", markersize=1.0e300_dp)
        case (63); call plot(x, x); call xlim(0.0_dp, 1.0e-300_dp)
        case (64); call scatter([0.0_dp, 1.0e30_dp], [0.0_dp, 1.0_dp]); call xlim(0.0_dp, 1.0_dp)
        ! Lines and fills crossing the view between ends as far as a double goes.
        case (65); call plot(t(1:3), [0.0_dp, 1.0e300_dp, 0.5_dp], linestyle="--"); call ylim(0.0_dp, 1.0_dp)
        case (66); call plot(t(1:2), [-1.0e300_dp, 1.0e300_dp]); call ylim(0.0_dp, 1.0_dp)
        case (67); call fill_between(t(1:3), [-1.0e300_dp, 1.0e300_dp, -1.0e300_dp]); call ylim(0.0_dp, 1.0_dp)
        ! An image reaching far past the view, a closed outline with a far
        ! corner, a pad that crops past the middle, and text larger than
        ! the canvas.
        case (68); call imshow(reshape([1.0_dp, 2.0_dp, 3.0_dp, 4.0_dp], [1, 4]), &
                               extent=[-1.0e20_dp, 1.0e20_dp, 0.0_dp, 1.0_dp]); call xlim(0.0_dp, 1.0_dp)
        case (69); call plot(x, x); call add_polygon([1.0_dp, 1.0e7_dp, 3.0_dp], [1.0_dp, 2.0_dp, 5.0_dp], &
                                                     edgecolor="k", lw=8.0_dp)
        case (70); call plot(x, x)
        case (71); call plot(x, x); call text(2.0_dp, 2.0_dp, "big", fontsize=800.0_dp)
        ! A stroke wider than the clip margin, a figure of a hundred million
        ! inches with far data, and a dashed line leaving the view and back.
        case (72); call pie([1.0_dp, 1.0_dp, 1.0_dp, 1.0_dp], startangle=45.0_dp, radius=1.0e4_dp, &
                            linewidth=2.0e4_dp, edgecolor="k")
            call xlim(5000.0_dp, 5001.0_dp); call ylim(1.0_dp, 2.0_dp)
        case (73); call close(); call figure(figsize=[1.0e8_dp, 1.0_dp])
            call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0e30_dp]); call ylim(0.0_dp, 1.0_dp)
        case (74); call plot(t(1:3), [0.0_dp, 1.0e7_dp, 0.5_dp], linestyle="--"); call ylim(0.0_dp, 1.0_dp)
        ! Data near the largest double, and spanning more than it: hexbin,
        ! whose grid and margins reach past it, a mesh whose outer cells
        ! do, a line across the whole range, and a circle too large to place.
        case (75); call hexbin([0.0_dp, 1.0_dp, 1.75e308_dp], [0.0_dp, 0.5_dp, 1.0_dp], gridsize=5)
        case (76); call hexbin([-huge(1.0_dp), 0.0_dp, huge(1.0_dp)], [-huge(1.0_dp), 0.0_dp, huge(1.0_dp)])
        case (77); call pcolormesh([-huge(1.0_dp), 0.0_dp, huge(1.0_dp)], [-huge(1.0_dp), 0.0_dp, huge(1.0_dp)], &
                                   reshape([(real(i, dp), i=1, 9)], [3, 3]))
        case (78); call plot([-huge(1.0_dp), 0.0_dp, huge(1.0_dp)], t(1:3))
        case (79); call plot(x, x); call add_circle([0.5_dp, 0.5_dp], 1.0e308_dp)
        ! hexbin with every point at the lowest double, an image over the
        ! whole range of a double, and contours of data far from zero.
        case (80); call hexbin([-huge(1.0_dp)], [-huge(1.0_dp)])
        case (81); call imshow(z, extent=[-huge(1.0_dp), huge(1.0_dp), -huge(1.0_dp), huge(1.0_dp)])
        case (82); call contourf(1.0e9_dp + z); call colorbar()
        ! A log axis whose margin is past the largest double, contours over
        ! the whole range of a double and near its lowest end, text turned
        ! many times over, and a colorbar of values too long for a fixed
        ! field.
        case (83); call semilogy(t(1:3), [1.0_dp, 1.0e100_dp, 1.0e300_dp])
        case (84); call contourf(reshape([-huge(1.0_dp), 0.0_dp, huge(1.0_dp), 0.0_dp], [2, 2])); call colorbar()
        case (85); call contourf(reshape([-huge(1.0_dp), -0.9_dp*huge(1.0_dp), -0.95_dp*huge(1.0_dp), &
                                          -huge(1.0_dp)], [2, 2])); call colorbar()
        case (86); call plot(x, x); call text(1.0_dp, 1.0_dp, "turned", rotation=1.0e16_dp)
        case (87); call scatter(t(1:3), t(1:3), cvals=[0.0_dp, 3.0e20_dp, 1.0e20_dp]); call colorbar()
        ! Ticks every half near the lowest double, a range a millionth of a
        ! millionth of its size, as nanosecond times are, and percentages
        ! past the largest double.
        case (88); call plot([0.0_dp, 1.0_dp], [-1.7e308_dp, 1.0_dp]); call tick_locator("y", base=0.5_dp)
        case (89); call plot([0.0_dp, 1.0_dp], [1.7e18_dp, 1.7e18_dp + 1.0e6_dp])
        case (90); call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0e307_dp])
            call tick_format("y", style="percent", whole=1.0_dp)
        ! Subnormal data on a log axis.
        case (91); call semilogy(t(1:3), [1.0e-320_dp, 1.0e-310_dp, 1.0e-300_dp])
        ! Bars of subnormal height on a log axis, and a constant series near
        ! the largest double.
        case (92); call bar(t(1:3), [1.0e-320_dp, 1.0e-300_dp, 1.0e-310_dp]); call set_yscale("log")
        case (93); call semilogy(t(1:2), [1.0e308_dp, 1.0e308_dp])
        ! Equal limits near the largest double, limits near zero on a log
        ! axis, and symlog with a small threshold and data up to 1e300.
        case (94); call plot(x, x); call ylim(1.75e308_dp, 1.75e308_dp)
        case (95); call semilogy(t(1:2), [2.0e-303_dp, 8.0e-303_dp]); call ylim(1.0e-303_dp, 1.0e-302_dp)
        case (96); call plot(t(1:3), [-1.0e300_dp, 0.0_dp, 1.0e300_dp])
            call set_yscale("symlog", linthresh=1.0e-10_dp)
        case (97); call imshow(reshape([0.0_dp, 1.0_dp, 1.0e300_dp, -1.0e300_dp], [2, 2]), &
                               norm="symlog", linthresh=1.0e-10_dp); call colorbar()
        ! A band of 8 points seen through a tiny window: its outline, far
        ! off the canvas, closes with exactly as many points as were made
        ! room for, and closing it grows the buffer the first point is in.
        case (98); call fill_between([(real(i, dp), i = 1, 8)], [(real(i, dp), i = 1, 8)], [(0.0_dp, i = 1, 8)])
            call xlim(0.0_dp, 1.0e-3_dp)
        end select
    end subroutine draw_case

    subroutine check_case(k, nfail)
        integer, intent(in) :: k
        integer, intent(inout) :: nfail
        character(len=:), allocatable :: svg, pdf, eps, png
        type(extent_renderer_t) :: r

        if (k == 70) then
            svg = render_svg(bbox_inches="tight", pad_inches=-100.0_dp)
            pdf = render_pdf(bbox_inches="tight", pad_inches=-100.0_dp)
            eps = render_eps(bbox_inches="tight", pad_inches=-100.0_dp)
            png = render_png(bbox_inches="tight", pad_inches=-100.0_dp)
        else
            svg = render_svg()
            pdf = render_pdf()
            eps = render_eps()
            ! A figure a hundred million inches wide has no PNG.
            png = "-"
            if (k /= 73) png = render_png()
        end if
        if (len(png) == 0 .or. len(pdf) == 0) then
            print "(a, i0, a)", "missing data case ", k, ": empty output"
            nfail = nfail + 1
        end if
        if (has_nonfinite(svg) .or. has_nonfinite(eps) .or. has_nonfinite(pdf_content(pdf))) then
            print "(a, i0, a)", "missing data case ", k, ": NaN or infinity in the output"
            nfail = nfail + 1
        end if
        ! Everything drawn lies within the clip box around the canvas, ten
        ! canvases out and widened by what a stroke reaches (at most twenty
        ! half widths, at a mitred corner), however far off the data was.
        call render_figure(r)
        if (r%far > 11.0_dp*max(r%width, r%height, 72.0_dp) + 10.0_dp*r%widest + 10.0_dp) then
            print "(a, i0, a, es10.3)", "missing data case ", k, ": drew as far out as ", r%far
            nfail = nfail + 1
        end if
        ! A number too large for its field is written as asterisks.
        if (index(svg, "**") > 0 .or. index(eps, "**") > 0 .or. index(pdf_content(pdf), "**") > 0) then
            print "(a, i0, a)", "missing data case ", k, ": a number overflowed its field in the output"
            nfail = nfail + 1
        end if
        ! An integer that overflowed shows as a negative size.
        if (.not. eps_box_ok(eps)) then
            print "(a, i0, a)", "missing data case ", k, ": the EPS BoundingBox is not a box"
            nfail = nfail + 1
        end if
    end subroutine check_case

    ! Whether the EPS %%BoundingBox line has four integers, the last two
    ! no smaller than the first two.
    logical function eps_box_ok(eps) result(good)
        character(len=*), intent(in) :: eps
        integer :: i, j, ios
        integer(int64) :: b(4)
        good = .false.
        i = index(eps, "%%BoundingBox:")
        if (i == 0) return
        j = index(eps(i:), new_line("a"))
        if (j == 0) return
        read (eps(i + 14:i + j - 2), *, iostat=ios) b
        if (ios /= 0) return
        good = b(3) >= b(1) .and. b(4) >= b(2)
    end function eps_box_ok

    ! Whether s spells a NaN or an infinity as a word of its own, the way
    ! a number formatter writes one.
    logical function has_nonfinite(s) result(r)
        character(len=*), intent(in) :: s
        integer :: i, j
        r = .false.
        i = 1
        do while (i <= len(s))
            if (.not. is_letter(s(i:i))) then
                i = i + 1
                cycle
            end if
            j = i
            do while (j < len(s))
                if (.not. is_letter(s(j + 1:j + 1))) exit
                j = j + 1
            end do
            select case (lower(s(i:j)))
            case ("nan", "inf", "infinity")
                r = .true.
                return
            end select
            i = j + 1
        end do
    end function has_nonfinite

    ! The page's content stream, the first stream in the file, which is
    ! the one written as text; the images after it are compressed.
    function pdf_content(pdf) result(c)
        character(len=*), intent(in) :: pdf
        character(len=:), allocatable :: c
        integer :: i, j
        i = index(pdf, "stream"//new_line("a"))
        j = index(pdf, "endstream")
        if (i == 0 .or. j <= i) then
            c = "missing content stream: nan"
        else
            c = pdf(i + 7:j - 1)
        end if
    end function pdf_content

    subroutine ext_open(self, width, height, bg_rgb, bg_alpha, x0, y0)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha, x0, y0
        self%far = 0.0_dp
        self%widest = 0.0_dp
    end subroutine ext_open

    subroutine ext_close(self)
        class(extent_renderer_t), intent(inout) :: self
    end subroutine ext_close

    subroutine see(self, v)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: v(:)
        if (size(v) > 0) self%far = max(self%far, maxval(abs(v)))
    end subroutine see

    subroutine ext_path(self, x, y, verbs, n_verb, paint)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        call see(self, x)
        call see(self, y)
        ! A fill clipped apart from its stroke still carries the width
        ! the clip box was widened by.
        self%widest = max(self%widest, paint%line_width)
    end subroutine ext_path

    subroutine ext_rect(self, x, y, w, h, paint, radius)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        call see(self, [x, y, x + w, y + h])
    end subroutine ext_rect

    subroutine ext_circle(self, cx, cy, r, paint)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
        call see(self, [cx - r, cx + r, cy - r, cy + r])
    end subroutine ext_circle

    subroutine ext_markers(self, x, y, mx, my, mverbs, n_mverb, paint)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:), mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
        call see(self, x)
        call see(self, y)
    end subroutine ext_markers

    subroutine ext_glyphs(self, x, y, run, paint, angle)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
        call see(self, [x, y])
    end subroutine ext_glyphs

    subroutine ext_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(extent_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint
        call see(self, [x, y, x + w, y + h])
    end subroutine ext_image

    pure logical function is_letter(c)
        character, intent(in) :: c
        is_letter = (c >= "a" .and. c <= "z") .or. (c >= "A" .and. c <= "Z")
    end function is_letter

end module test_missing
