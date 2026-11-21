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
    use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan, &
                                              ieee_positive_inf
    use fplotlib
    use fplotlib_style, only: lower
    use fplotlib_render
    use fplotlib_draw, only: render_figure
    implicit none
    private

    public :: missing_data_check

    ! Records the furthest any coordinate handed to it lies from zero, so
    ! that the test can check what the plotting layer draws, not only what
    ! a file format makes of it.
    type, extends(renderer_t) :: extent_renderer_t
        real(dp) :: far = 0.0_dp
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

    integer, parameter :: NCASE = 71

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
            png = render_png()
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
        ! canvases wide, however far off the data was.
        call render_figure(r)
        if (r%far > 1.0e5_dp) then
            print "(a, i0, a, es10.3)", "missing data case ", k, ": drew as far out as ", r%far
            nfail = nfail + 1
        end if
        ! A number too large for its field is written as asterisks.
        if (index(svg, "**") > 0 .or. index(eps, "**") > 0 .or. index(pdf_content(pdf), "**") > 0) then
            print "(a, i0, a)", "missing data case ", k, ": a number overflowed its field in the output"
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
