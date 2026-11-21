! Missing data, drawn.
!
! NaN and infinite values are missing data to matplotlib: a line breaks
! around them and a bar, marker or label placed at one is left out. The
! renderer takes only finite coordinates and stops on anything else, so
! the plot types have to leave out what is missing before it gets there
! (fplotlib_artist's put_* routines). Every case here puts a missing value
! into a different plot type and renders it in all four formats; none may
! stop, and no NaN or infinity may reach the vector output.
module test_missing
    use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan, &
                                              ieee_positive_inf
    use fplotlib
    use fplotlib_style, only: lower
    implicit none
    private

    public :: missing_data_check

    integer, parameter :: NCASE = 48

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
        print "(a, i0, a, i0)", "missing data: ", NCASE, " plots, failures = ", nfail
    end subroutine missing_data_check

    subroutine draw_case(k)
        integer, intent(in) :: k
        real(dp) :: nan, inf, x(6), y(6), e(6), t(6), z(5, 5), g(5), m(2, 3)
        real(dp) :: tx(5), ty(5), tz(5)
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
        end select
    end subroutine draw_case

    subroutine check_case(k, nfail)
        integer, intent(in) :: k
        integer, intent(inout) :: nfail
        character(len=:), allocatable :: svg, pdf, eps, png

        svg = render_svg()
        pdf = render_pdf()
        eps = render_eps()
        png = render_png()
        if (len(png) == 0 .or. len(pdf) == 0) then
            print "(a, i0, a)", "missing data case ", k, ": empty output"
            nfail = nfail + 1
        end if
        if (has_nonfinite(svg) .or. has_nonfinite(eps)) then
            print "(a, i0, a)", "missing data case ", k, ": NaN or infinity in the output"
            nfail = nfail + 1
        end if
    end subroutine check_case

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

    pure logical function is_letter(c)
        character, intent(in) :: c
        is_letter = (c >= "a" .and. c <= "z") .or. (c >= "A" .and. c <= "Z")
    end function is_letter

end module test_missing
