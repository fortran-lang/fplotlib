module test_frame_backends
    use fplotlib_style, only: dp
    use fplotlib_render, only: renderer_t, paint_t, clip_t
    use fplotlib_backend_svg, only: svg_renderer_t
    use fplotlib_backend_eps, only: eps_renderer_t
    use fplotlib_backend_pdf, only: pdf_renderer_t
    use fplotlib_render, only: VERB_MOVE, VERB_LINE, VERB_CLOSE, CAP_BUTT, CAP_ROUND, CAP_SQUARE, &
                               JOIN_MITER, JOIN_ROUND, JOIN_BEVEL, FILL_NONZERO, FILL_EVENODD
    use fplotlib_raster, only: full_walk
    use fplotlib_backend_png, only: png_renderer_t
    implicit none
    private

    public :: frame_backend_check

contains

    subroutine frame_backend_check(nfail)
        integer, intent(out) :: nfail

        nfail = 0
        call vector_frame_numbers_check(nfail)
        call png_frames_check(nfail)
        call png_image_check(nfail)
        call png_dash_frames_check(nfail)
        call png_dash_joins_check(nfail)
        call png_far_frame_check(nfail)
        call png_evenodd_check(nfail)
        call pdf_resources_check(nfail)
        call pdf_pages_check(nfail)
        print "(a,i0)", "frame backends: failures = ", nfail
    end subroutine frame_backend_check

    ! SVG, PDF and EPS write a frame's matrix with fifteen significant
    ! digits, so that a scale of 4e-7 is not written as 0, and the numbers
    ! inside a frame with as many more decimals as it magnifies, so that
    ! a frame magnifying a million times still places them to a millionth
    ! of a point on the page.
    subroutine vector_frame_numbers_check(nfail)
        integer, intent(inout) :: nfail
        type(svg_renderer_t) :: svg
        type(pdf_renderer_t) :: pdf
        type(eps_renderer_t) :: eps
        type(paint_t) :: paint
        type(clip_t) :: none
        character(len=:), allocatable :: b
        real(dp), parameter :: small(6) = [4.0e-7_dp, 0.0_dp, 0.0_dp, 4.0e-7_dp, 0.0_dp, 0.0_dp]
        real(dp), parameter :: large(6) = [1.0e6_dp, 0.0_dp, 0.0_dp, 1.0e6_dp, 0.0_dp, 0.0_dp]

        paint%filled = .true.
        call svg%open_canvas(200.0_dp, 150.0_dp)
        call draw(svg)
        call svg%close_canvas()
        b = svg%bytes()
        call expect(index(b, "matrix(0.0000004 0 0 0.0000004 0 0)") > 0 .and. index(b, "0.0000012345") > 0, &
                    "SVG frames keep a small scale and magnified coordinates", nfail)
        call pdf%open_canvas(200.0_dp, 150.0_dp)
        call draw(pdf)
        call pdf%close_canvas()
        b = pdf%bytes()
        call expect(index(b, "0.0000004 0 0 0.0000004 0 0 cm") > 0 .and. index(b, "0.0000012345") > 0, &
                    "PDF frames keep a small scale and magnified coordinates", nfail)
        call eps%open_canvas(200.0_dp, 150.0_dp)
        call draw(eps)
        call eps%close_canvas()
        b = eps%bytes()
        call expect(index(b, "[0.0000004 0 0 0.0000004 0 0 ] concat") > 0 .and. index(b, "0.0000012345") > 0, &
                    "EPS frames keep a small scale and magnified coordinates", nfail)
    contains
        subroutine draw(r)
            class(renderer_t), intent(inout) :: r
            call r%begin_frame(small, none)
            call r%draw_rect(2.5e8_dp, 1.875e8_dp, 1.0e8_dp, 1.0e8_dp, paint)
            call r%end_frame()
            call r%begin_frame(large, none)
            call r%draw_rect(0.0000012345_dp, 0.00001_dp, 0.00001_dp, 0.00001_dp, paint)
            call r%end_frame()
        end subroutine draw
    end subroutine vector_frame_numbers_check

    subroutine expect(ok, label, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: label
        integer, intent(inout) :: nfail

        if (ok) return
        nfail = nfail + 1
        print "(a)", "  FAIL "//label
    end subroutine expect

    subroutine png_frames_check(nfail)
        integer, intent(inout) :: nfail
        type(png_renderer_t) :: png
        type(paint_t) :: paint
        type(clip_t) :: outer_clip, inner_clip, none
        real(dp), parameter :: IDENTITY(6) = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp]
        integer :: i

        png%keep_pixels = .true.
        call png%set_dpi(72.0_dp)
        call png%open_canvas(64.0_dp, 48.0_dp, [255, 255, 255], x0=10.0_dp, y0=20.0_dp)
        outer_clip = clip_t(.true., 2.0_dp, 2.0_dp, 20.0_dp, 12.0_dp)
        call png%begin_frame([2.0_dp, 0.0_dp, 0.0_dp, 3.0_dp, 10.0_dp, 20.0_dp], outer_clip)

        ! After cropping, (u,v) maps to (2u,3v). A two-point pen gives
        ! a six-pixel horizontal band and a four-pixel vertical band.
        paint%stroked = .true.
        paint%line_width = 2.0_dp
        paint%stroke_rgb = [255, 0, 0]
        call png%draw_path([0.0_dp, 24.0_dp], [5.0_dp, 5.0_dp], [VERB_MOVE, VERB_LINE], 2, paint)
        paint%stroke_rgb = [0, 0, 255]
        call png%draw_path([18.0_dp, 18.0_dp], [0.0_dp, 16.0_dp], [VERB_MOVE, VERB_LINE], 2, paint)

        inner_clip = clip_t(.true., 2.0_dp, 2.0_dp, 4.0_dp, 4.0_dp)
        call png%begin_frame([1.0_dp, 1.0_dp, -1.0_dp, 1.0_dp, 16.0_dp, 2.0_dp], inner_clip)
        do i = 1, 20
            call png%begin_frame(IDENTITY, none)
        end do
        paint = paint_t(clip=clip_t())
        paint%filled = .true.
        paint%fill_rgb = [0, 255, 0]
        call png%draw_rect(-5.0_dp, -5.0_dp, 20.0_dp, 20.0_dp, paint)
        do i = 1, 20
            call png%end_frame()
        end do
        call png%end_frame()

        paint%fill_rgb = [255, 128, 0]
        call png%draw_rect(0.0_dp, 10.0_dp, 8.0_dp, 3.0_dp, paint)
        call png%end_frame()
        paint%fill_rgb = [0, 255, 255]
        call png%draw_rect(12.0_dp, 21.0_dp, 4.0_dp, 3.0_dp, paint)
        paint = paint_t(clip=clip_t())
        paint%stroked = .true.
        call png%draw_path([70.2_dp, 70.2_dp], [22.0_dp, 36.0_dp], [VERB_MOVE, VERB_LINE], 2, paint)
        call png%close_canvas()

        call expect_pixel(png, 21, 13, [255, 0, 0], "nonuniform stroke top interior", nfail)
        call expect_pixel(png, 21, 18, [255, 0, 0], "nonuniform stroke bottom interior", nfail)
        call expect_pixel(png, 21, 19, [255, 255, 255], "outside horizontal stroke", nfail)
        call expect_pixel(png, 35, 10, [0, 0, 255], "nonuniform vertical stroke interior", nfail)
        call expect_pixel(png, 39, 10, [255, 255, 255], "vertical pen is not scaled by the y factor", nfail)
        call expect_pixel(png, 3, 16, [255, 255, 255], "outer clip cuts horizontal stroke", nfail)
        call expect_pixel(png, 37, 44, [255, 255, 255], "outer clip cuts vertical stroke", nfail)
        ! The child clip is a diamond with vertices (32,18), (40,30),
        ! (32,42), (24,30). The outside sample is inside its bounding box.
        call expect_pixel(png, 33, 31, [0, 255, 0], "nested rotation and clip after stack growth", nfail)
        call expect_pixel(png, 25, 20, [255, 255, 255], "outside rotated child clip, inside its bounds", nfail)
        call expect_pixel(png, 7, 34, [255, 128, 0], "child exit restores parent transform and clip", nfail)
        call expect_pixel(png, 2, 34, [255, 255, 255], "child exit retains the ancestor clip", nfail)
        call expect_pixel(png, 4, 3, [0, 255, 255], "outer exit restores cropped root coordinates", nfail)
        call expect_pixel(png, 61, 8, [0, 0, 0], "identity stroke keeps legacy pixel snapping", nfail)
        call expect_pixel(png, 60, 8, [255, 255, 255], "snapped stroke does not blur its neighbor", nfail)
    end subroutine png_frames_check

    subroutine png_image_check(nfail)
        integer, intent(inout) :: nfail
        type(png_renderer_t) :: png
        type(paint_t) :: paint
        type(clip_t) :: outer_clip, inner_clip
        integer :: rgba(4, 2, 2)

        rgba(:, 1, 1) = [255, 0, 0, 255]
        rgba(:, 2, 1) = [0, 255, 0, 255]
        rgba(:, 1, 2) = [0, 0, 255, 255]
        rgba(:, 2, 2) = [255, 255, 0, 255]
        png%keep_pixels = .true.
        call png%set_dpi(72.0_dp)
        call png%open_canvas(64.0_dp, 48.0_dp, [255, 255, 255], x0=10.0_dp, y0=20.0_dp)
        outer_clip = clip_t(.true., 0.0_dp, 0.0_dp, 20.0_dp, 16.0_dp)
        call png%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 14.0_dp, 24.0_dp], outer_clip)
        inner_clip = clip_t(.true., 1.0_dp, 1.0_dp, 6.0_dp, 6.0_dp)
        call png%begin_frame([2.0_dp, 1.0_dp, 1.0_dp, 2.0_dp, 4.0_dp, 0.0_dp], inner_clip)
        paint%clip = clip_t(.true., 2.0_dp, 0.0_dp, 6.0_dp, 6.0_dp)
        call png%draw_image(0.0_dp, 0.0_dp, 8.0_dp, 8.0_dp, rgba, 2, 2, paint)
        call png%end_frame()
        call png%end_frame()
        call png%close_canvas()

        ! Device (X,Y)=(2u+v+8,u+2v+4). These sample the four source
        ! quadrants at (2.5,2.5), (5.5,2.5), (2.5,5.5), and (4.5,4.5).
        call expect_pixel(png, 16, 12, [255, 0, 0], "sheared image upper-left sample", nfail)
        call expect_pixel(png, 22, 15, [0, 255, 0], "sheared image upper-right sample", nfail)
        call expect_pixel(png, 19, 18, [0, 0, 255], "sheared image lower-left sample", nfail)
        call expect_pixel(png, 22, 18, [255, 255, 0], "sheared image lower-right sample", nfail)
        call expect_pixel(png, 14, 11, [255, 255, 255], "image paint clip excludes u=1.5", nfail)
        call expect_pixel(png, 20, 20, [255, 255, 255], "image paint clip excludes v=6.5", nfail)
        call expect_pixel(png, 14, 8, [255, 255, 255], "image child clip excludes v=0.5", nfail)
        call expect_pixel(png, 26, 20, [255, 255, 255], "image retains ancestor clip in device space", nfail)
    end subroutine png_image_check

    ! Dashed strokes in transformed frames draw what walking every dash
    ! draws: the rasterizer decides what it may skip on the canvas, not in
    ! the frame's coordinates, which a frame that shrinks, shears or
    ! stretches unevenly would make wrong. The lines run 1e5 points off, a
    ! million canvas pixels in the largest frame. Up to
    ! the documented rounding of where along so long a line the pattern
    ! stands: a level of one in 255. The canvas is opaque, as a picture
    ! is seen, since a pixel the stroke barely misses keeps a trace of
    ! coverage whose colour means nothing.
    subroutine png_dash_frames_check(nfail)
        integer, intent(inout) :: nfail
        real(dp), parameter :: c30 = 0.8660254037844386_dp, s30 = 0.5_dp
        real(dp), parameter :: mats(6, 10) = reshape([ &
            0.1_dp, 0.0_dp, 0.0_dp, 0.1_dp, 10.0_dp, 10.0_dp, &
            10.0_dp, 0.0_dp, 0.0_dp, 10.0_dp, -500.0_dp, -300.0_dp, &
            c30, s30, -s30, c30, 50.0_dp, 0.0_dp, &
            1.0_dp, 0.0_dp, 0.7_dp, 1.0_dp, 0.0_dp, 0.0_dp, &
            5.0_dp, 0.0_dp, 0.0_dp, 0.05_dp, 0.0_dp, 50.0_dp, &
            1.0e-4_dp, 0.0_dp, 0.0_dp, 1.0e-4_dp, 100.0_dp, 75.0_dp, &
            3.0_dp*c30, 3.0_dp*s30, -0.02_dp*s30, 0.02_dp*c30, 100.0_dp, 75.0_dp, &
            ! Turned 45 degrees and stretched 1e4 across the line, which
            ! makes a thin pen a sliver across the canvas; and a plain move.
            0.7071067811865476_dp, 0.7071067811865476_dp, -7071.067811865476_dp, 7071.067811865476_dp, &
            100.0_dp, 75.0_dp, &
            1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 10.0_dp, 0.0_dp, &
            ! Squeezed 5000 times across the line, not turned: a wide pen
            ! a thin band, each dash of which reaches only so far along.
            1.0_dp, 0.0_dp, 0.0_dp, 2.0e-4_dp, 0.0_dp, 75.0_dp], [6, 10])
        real(dp), parameter :: px(4) = [-1.0e5_dp, 1.0e5_dp, 50.0_dp, 80.0_dp]
        real(dp), parameter :: py(4) = [-1.0e4_dp, 2.0e4_dp, 60.0_dp, 20.0_dp]
        real(dp), parameter :: widths(4) = [1.0_dp, 2.0_dp, 500.0_dp, 1.0e4_dp]
        integer, parameter :: caps(3) = [CAP_BUTT, CAP_ROUND, CAP_SQUARE]
        type(paint_t) :: paint
        character(len=:), allocatable :: quick, full
        integer :: m, w, c, d, i, worst
        logical :: same
        ! The PNG backend's resolution, which the rasterizer's rule counts.
        real(dp), parameter :: DPI = 100.0_dp
        real :: t0, t1

        same = .true.
        paint%stroked = .true.
        paint%stroke_rgb = [20, 40, 200]
        do m = 1, size(mats, 2)
            do w = 1, size(widths)
                do c = 1, size(caps)
                    do d = 1, 3
                        paint%line_width = widths(w)
                        paint%cap = caps(c)
                        paint%dash = 0.0_dp
                        select case (d)
                        case (1); paint%n_dash = 2; paint%dash(1:2) = [6.0_dp, 3.0_dp]
                        case (2); paint%n_dash = 3; paint%dash(1:3) = [1.0_dp, 2.0_dp, 3.0_dp]
                        case default; paint%n_dash = 2; paint%dash(1:2) = [0.5_dp, 0.5_dp]
                        end select
                        ! Round and square ends keep to 100 patterns a pen.
                        if (paint%cap /= CAP_BUTT .and. paint%line_width > 100.0_dp*sum(paint%dash(1:paint%n_dash))) cycle
                        full_walk = .false.
                        quick = dashed_frame(mats(:, m), paint)
                        ! A segment whose dashes cross the canvas as stripes
                        ! less than half a pixel apart is drawn solid, a
                        ! documented approximation, which the full walk is
                        ! not; such a path is only drawn, which has to
                        ! finish. The rasterizer's guard on the periods
                        ! walked must never apply to the rest.
                        if (any_solid(mats(:, m), sum(paint%dash(1:paint%n_dash))*DPI/72.0_dp &
                                      *merge(2.0_dp, 1.0_dp, mod(paint%n_dash, 2) == 1))) cycle
                        full_walk = .true.
                        full = dashed_frame(mats(:, m), paint)
                        full_walk = .false.
                        worst = 0
                        do i = 1, min(len(quick), len(full))
                            worst = max(worst, abs(iachar(quick(i:i)) - iachar(full(i:i))))
                        end do
                        if (len(quick) /= len(full) .or. worst > 1) then
                            same = .false.
                            print "(a, 5(i0, 1x))", "  dashed frame differs: matrix, width, cap, dashes, worst ", &
                                m, w, c, d, worst
                        end if
                    end do
                end do
            end do
        end do
        call expect(same, "PNG dashes in transformed frames match the full walk", nfail)
        ! Each of these used to run for minutes or out of memory; together
        ! they take well under a second.
        call cpu_time(t0)
        call degenerate_frames()
        call cpu_time(t1)
        call expect(t1 - t0 < 20.0_dp, "PNG dashes in degenerate frames finish in time", nfail)
    contains
        ! Whether some segment of the path is too fine to walk in a frame
        ! of matrix a, by the rasterizer's rule: its pattern, period canvas
        ! pixels long before the frame (an odd count of lengths doubled),
        ! makes stripes on the canvas under half a pixel apart.
        pure logical function any_solid(a, period) result(r)
            real(dp), intent(in) :: a(6), period
            integer :: i
            real(dp) :: dx, dy
            r = .false.
            do i = 1, size(px) - 1
                dx = px(i + 1) - px(i)
                dy = py(i + 1) - py(i)
                ! Stripes less than half a pixel apart across them.
                if (period*abs(a(1)*a(4) - a(2)*a(3))*hypot(dx, dy) &
                    < 0.5_dp*hypot(a(3)*dx - a(1)*dy, a(4)*dx - a(2)*dy)) r = .true.
            end do
        end function any_solid

        ! Frames that once made a dash walk run for minutes or out of
        ! memory: a stretch of 1e9 along x and 1e-3 along y, with a line
        ! along y a canvas pixel a dash; a shear all but singular, with a
        ! pen of 1e6; a shear of 1e8; and frames nested to 1e300 and past
        ! the largest double, holding a dashed line and an image.
        subroutine degenerate_frames()
            type(png_renderer_t) :: png
            type(clip_t) :: none
            type(paint_t) :: q
            integer :: i, rgba(4, 2, 2)
            character(len=:), allocatable :: b

            q%stroked = .true.
            q%stroke_rgb = [0, 0, 0]
            q%cap = CAP_BUTT
            call png%open_canvas(200.0_dp, 150.0_dp)
            q%line_width = 1.0_dp
            q%n_dash = 2
            q%dash(1:2) = [500.0_dp, 500.0_dp]
            call png%begin_frame([1.0e9_dp, 0.0_dp, 0.0_dp, 1.0e-3_dp, 100.0_dp, 75.0_dp], none)
            call png%draw_path([0.0_dp, 0.0_dp], [-1.0e15_dp, 1.0e15_dp], [VERB_MOVE, VERB_LINE], 2, q)
            call png%end_frame()
            q%line_width = 1.0e6_dp
            q%dash(1:2) = [3.0_dp, 2.0_dp]
            call png%begin_frame([1.0_dp, 1.0_dp, 1.0_dp, 1.0_dp + 1.0e-15_dp, 10.0_dp, 10.0_dp], none)
            call png%draw_path([-1.0e15_dp, 1.0e15_dp], [-1.0e14_dp, 3.0e14_dp], [VERB_MOVE, VERB_LINE], 2, q)
            call png%end_frame()
            ! A shear of 1e8, which stretches a thin pen into a sliver
            ! longer than the canvas by far, across which every dash falls.
            q%line_width = 1.0_dp
            q%dash(1:2) = [6.0_dp, 3.0_dp]
            call png%begin_frame([1.0_dp, 0.0_dp, 1.0e8_dp, 1.0_dp, 0.0_dp, 75.0_dp], none)
            call png%draw_path([-1.0e12_dp, 1.0e12_dp], [0.0_dp, 0.0_dp], [VERB_MOVE, VERB_LINE], 2, q)
            call png%end_frame()
            ! A dashed line in frames that together scale by 1e300.
            do i = 1, 20
                call png%begin_frame([1.0e15_dp, 0.0_dp, 0.0_dp, 1.0e15_dp, 0.0_dp, 0.0_dp], none)
            end do
            call png%draw_path([-1.0e9_dp, 1.0e9_dp], [0.0_dp, 0.0_dp], [VERB_MOVE, VERB_LINE], 2, q)
            do i = 1, 20
                call png%end_frame()
            end do
            rgba = 255
            do i = 1, 25
                call png%begin_frame([1.0e15_dp, 0.0_dp, 0.0_dp, 1.0e15_dp, 0.0_dp, 0.0_dp], none)
            end do
            call png%draw_image(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, rgba, 2, 2, q)
            do i = 1, 25
                call png%end_frame()
            end do
            call png%close_canvas()
            b = png%bytes()
        end subroutine degenerate_frames

        function dashed_frame(matrix, paint) result(bytes)
            real(dp), intent(in) :: matrix(6)
            type(paint_t), intent(in) :: paint
            character(len=:), allocatable :: bytes
            type(png_renderer_t) :: png
            type(clip_t) :: none
            png%keep_pixels = .true.
            call png%open_canvas(200.0_dp, 150.0_dp, bg_rgb=[255, 255, 255])
            call png%begin_frame(matrix, none)
            call png%draw_path(px, py, [VERB_MOVE, VERB_LINE, VERB_LINE, VERB_LINE], 4, paint)
            call png%end_frame()
            call png%close_canvas()
            bytes = png%rgb
        end function dashed_frame
    end subroutine png_dash_frames_check

    ! Where a walked segment meets one drawn solid, the join at their
    ! corner is drawn as the full walk draws it: the frame makes one
    ! segment's pattern sub-pixel and leaves the other's. Compared outside
    ! the solid segment's own pen, which the approximation draws at its
    ! cover. The dash phase at the corner stays clear of a dash ending
    ! exactly there, where rounding decides whether it reaches on. Round
    ! and square ends take a thin pen: with a wide one their dashes
    ! overlap, whose coverage the full walk sums at their edges, so that
    ! it is no exact reference there.
    subroutine png_dash_joins_check(nfail)
        integer, intent(inout) :: nfail
        real(dp), parameter :: m(6) = [1.0_dp, 0.0_dp, 0.0_dp, 0.05_dp, 0.0_dp, 50.0_dp]
        real(dp), parameter :: squeezed(6) = [1.0_dp, 0.0_dp, 0.0_dp, 2.0e-4_dp, 0.0_dp, 75.0_dp]
        integer, parameter :: caps(3) = [CAP_BUTT, CAP_ROUND, CAP_SQUARE]
        integer, parameter :: joins(3) = [JOIN_MITER, JOIN_ROUND, JOIN_BEVEL]
        ! A paint as declared, with every default.
        type(paint_t) :: paint, bare, fresh
        real(dp) :: x(3), y(3), a(6), big, unit
        character(len=:), allocatable :: quick, full, mask
        integer :: order, c, j, k, i, worst
        logical :: same

        same = .true.
        do order = 1, 2
            if (order == 1) then
                x = [10.0_dp, 96.0_dp, 96.0_dp]
                y = [0.0_dp, 0.0_dp, 2000.0_dp]
            else
                x = [96.0_dp, 96.0_dp, 10.0_dp]
                y = [2000.0_dp, 0.0_dp, 0.0_dp]
            end if
            do c = 1, 3
                do j = 1, 3
                    do k = 0, 5
                        paint = fresh
                        paint%stroked = .true.
                        paint%cap = caps(c)
                        paint%join = joins(j)
                        paint%line_width = merge(20.0_dp, 2.0_dp, caps(c) == CAP_BUTT)
                        paint%n_dash = 2
                        paint%dash(1:2) = [4.0_dp, 2.0_dp]
                        paint%dash_offset = k + 0.37_dp
                        bare = paint
                        bare%n_dash = 0
                        bare%cap = CAP_BUTT
                        full_walk = .false.
                        quick = draw_in_frame(m, x, y, 3, paint)
                        ! The solid segment alone: the second, or the first.
                        if (order == 1) then
                            mask = draw_in_frame(m, x(2:3), y(2:3), 2, bare)
                        else
                            mask = draw_in_frame(m, x(1:2), y(1:2), 2, bare)
                        end if
                        full_walk = .true.
                        full = draw_in_frame(m, x, y, 3, paint)
                        full_walk = .false.
                        worst = 0
                        do i = 1, len(quick)
                            if (mask(i:i) == achar(255)) &
                                worst = max(worst, abs(iachar(quick(i:i)) - iachar(full(i:i))))
                        end do
                        if (worst > 1) then
                            same = .false.
                            print "(a, 4(i0, 1x))", "  dash join differs: order, cap, join, phase, worst ", &
                                order, c, j, k, worst
                        end if
                    end do
                end do
            end do
        end do
        call expect(same, "PNG dash joins between walked and solid segments match the full walk", nfail)

        ! A line along a frame squeezed 5000 times across it, with a pen
        ! 10000 points wide: a band 2.8 pixels tall of dashes 4 pixels long,
        ! whose period the frame leaves as it is, however many of them the
        ! pen's width would have reach the canvas before the frame.
        same = .true.
        do c = 1, 3
            paint = fresh
            paint%stroked = .true.
            paint%cap = caps(c)
            paint%line_width = merge(1.0e4_dp, 500.0_dp, caps(c) == CAP_BUTT)
            paint%n_dash = 2
            paint%dash(1:2) = [3.0_dp, 3.0_dp]
            full_walk = .false.
            quick = draw_in_frame(squeezed, [-1.0e5_dp, 1.0e5_dp], [0.0_dp, 0.0_dp], 2, paint)
            full_walk = .true.
            full = draw_in_frame(squeezed, [-1.0e5_dp, 1.0e5_dp], [0.0_dp, 0.0_dp], 2, paint)
            full_walk = .false.
            worst = 0
            do i = 1, len(quick)
                worst = max(worst, abs(iachar(quick(i:i)) - iachar(full(i:i))))
            end do
            if (worst > 1) then
                same = .false.
                print "(a, 2(i0, 1x))", "  squeezed dashes differ: cap, worst ", c, worst
            end if
        end do
        call expect(same, "PNG dashes along a squeezed frame match the full walk", nfail)

        ! A dash running through a corner off the canvas carries its join
        ! there by a stub, which has to stay inside the dash however far a
        ! frame moves or stretches it: here 1e14 points along, and 1e7 times
        ! larger, the dash goes 2 pixels past the corner and 3 before it.
        same = .true.
        do k = 1, 4
            paint = fresh
            paint%stroked = .true.
            paint%cap = CAP_BUTT
            select case (k)
            case (1, 2)
                big = merge(1.0e14_dp, 5.0e14_dp, k == 1)
                a = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 100.0_dp - big, 75.0_dp]
                unit = 1.0_dp
                x = [-1100.0_dp, -108.0_dp, 1000.0_dp] + big
            case default
                big = merge(1.0e7_dp, 1.0e8_dp, k == 3)
                a = [big, 0.0_dp, 0.0_dp, big, 100.0_dp, 75.0_dp]
                unit = 1.0_dp/big
                x = [-1100.0_dp, -108.0_dp, 1000.0_dp]*unit
            end select
            y = [0.0_dp, 0.0_dp, 30.0_dp]*unit
            paint%line_width = 4.0_dp*unit
            paint%n_dash = 2
            paint%dash(1:2) = [5.0_dp, 20.0_dp]*unit
            paint%dash_offset = modulo(5.0_dp - 994.0_dp, 25.0_dp)*unit
            full_walk = .false.
            quick = draw_in_frame(a, x, y, 3, paint)
            full_walk = .true.
            full = draw_in_frame(a, x, y, 3, paint)
            full_walk = .false.
            worst = 0
            do i = 1, len(quick)
                worst = max(worst, abs(iachar(quick(i:i)) - iachar(full(i:i))))
            end do
            if (worst > 1) then
                same = .false.
                print "(a, 2(i0, 1x))", "  join stub differs: case, worst ", k, worst
            end if
        end do
        call expect(same, "PNG dash join stubs in far moved and stretched frames match the full walk", nfail)
    contains
        function draw_in_frame(m, x, y, n, paint) result(rgb)
            real(dp), intent(in) :: m(6), x(:), y(:)
            integer, intent(in) :: n
            type(paint_t), intent(in) :: paint
            character(len=:), allocatable :: rgb
            type(png_renderer_t) :: png
            type(clip_t) :: none
            integer :: verbs(3)

            verbs = [VERB_MOVE, VERB_LINE, VERB_LINE]
            png%keep_pixels = .true.
            call png%open_canvas(200.0_dp, 150.0_dp, bg_rgb=[255, 255, 255])
            call png%begin_frame(m, none)
            call png%draw_path(x(1:n), y(1:n), verbs(1:n), n, paint)
            call png%end_frame()
            call png%close_canvas()
            rgb = png%rgb
        end function draw_in_frame
    end subroutine png_dash_joins_check

    ! A stroke in a frame moved 1e9 points, drawn 1e9 points the other
    ! way, is the same picture as unmoved: each piece of the outline keeps
    ! its orientation, which a signed area summed about the origin, of
    ! terms near 1e18, would leave to rounding, so that pieces cancel
    ! where they overlap into holes in caps and joins.
    subroutine png_far_frame_check(nfail)
        integer, intent(inout) :: nfail
        real(dp), parameter :: x(5) = [20.0_dp, 80.0_dp, 60.0_dp, 140.0_dp, 120.0_dp]
        real(dp), parameter :: y(5) = [20.0_dp, 120.0_dp, 30.0_dp, 130.0_dp, 25.0_dp]
        integer, parameter :: verbs(5) = [VERB_MOVE, VERB_LINE, VERB_LINE, VERB_LINE, VERB_LINE]
        type(paint_t) :: paint
        character(len=:), allocatable :: near, far
        integer :: i, j, worst
        logical :: same

        same = .true.
        paint%stroked = .true.
        paint%line_width = 12.0_dp
        paint%cap = CAP_ROUND
        do j = 1, 2
            paint%join = merge(JOIN_MITER, JOIN_ROUND, j == 1)
            near = moved(0.0_dp)
            far = moved(1.0e9_dp)
            worst = 0
            do i = 1, len(near)
                worst = max(worst, abs(iachar(near(i:i)) - iachar(far(i:i))))
            end do
            if (worst > 2) then
                same = .false.
                print "(a, 2(i0, 1x))", "  far frame differs: join, worst ", j, worst
            end if
        end do
        call expect(same, "PNG strokes in a frame moved far keep their caps and joins", nfail)
    contains
        function moved(t) result(rgb)
            real(dp), intent(in) :: t
            character(len=:), allocatable :: rgb
            type(png_renderer_t) :: png
            type(clip_t) :: none

            png%keep_pixels = .true.
            call png%open_canvas(200.0_dp, 150.0_dp, bg_rgb=[255, 255, 255])
            call png%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, -t, -t], none)
            call png%draw_path(x + t, y + t, verbs, 5, paint)
            call png%end_frame()
            call png%close_canvas()
            rgb = png%rgb
        end function moved
    end subroutine png_far_frame_check

    ! The even-odd rule in PNG, as SVG, PDF and EPS have it: the hole of a
    ! ring whose two contours turn the same way, and the middle of a
    ! pentagram, where the winding is 2, are left empty, and nonzero fills
    ! them. In a frame clipped through the hole, the clip's edge leaves no
    ! line there, as two contours cut along it would give.
    subroutine png_evenodd_check(nfail)
        integer, intent(inout) :: nfail
        ! CLOSE takes no vertex: four corners a contour.
        real(dp), parameter :: ring_x(8) = [10.0_dp, 50.0_dp, 50.0_dp, 10.0_dp, &
                                            20.0_dp, 40.0_dp, 40.0_dp, 20.0_dp]
        real(dp), parameter :: ring_y(8) = [10.0_dp, 10.0_dp, 50.0_dp, 50.0_dp, &
                                            20.0_dp, 20.0_dp, 40.0_dp, 40.0_dp]
        integer, parameter :: ring_v(10) = [VERB_MOVE, VERB_LINE, VERB_LINE, VERB_LINE, VERB_CLOSE, &
                                            VERB_MOVE, VERB_LINE, VERB_LINE, VERB_LINE, VERB_CLOSE]
        real(dp) :: star_x(5), star_y(5), a
        integer :: star_v(6), k, rule, g
        type(paint_t) :: paint
        type(clip_t) :: half
        character(len=16) :: name

        paint%filled = .true.
        paint%fill_rgb = [0, 0, 0]
        ! A pentagram about (30, 30): every second point of a pentagon.
        do k = 1, 5
            a = -0.5_dp*acos(-1.0_dp) + real(2*(k - 1), dp)*0.4_dp*acos(-1.0_dp)
            star_x(k) = 30.0_dp + 25.0_dp*cos(a)
            star_y(k) = 30.0_dp + 25.0_dp*sin(a)
        end do
        star_v = [VERB_MOVE, VERB_LINE, VERB_LINE, VERB_LINE, VERB_LINE, VERB_CLOSE]
        do rule = FILL_NONZERO, FILL_EVENODD
            paint%fill_rule = rule
            name = merge("even-odd", "nonzero ", rule == FILL_EVENODD)
            ! Black where nonzero fills, white where even-odd leaves it.
            k = merge(255, 0, rule == FILL_EVENODD)
            block
                type(png_renderer_t) :: png
                png%keep_pixels = .true.
                call png%set_dpi(72.0_dp)
                call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
                call png%draw_path(ring_x, ring_y, ring_v, 10, paint)
                call png%close_canvas()
                call expect_pixel(png, 30, 30, [k, k, k], trim(name)//" ring hole", nfail)
                call expect_pixel(png, 15, 30, [0, 0, 0], trim(name)//" ring", nfail)
            end block
            block
                type(png_renderer_t) :: png
                png%keep_pixels = .true.
                call png%set_dpi(72.0_dp)
                call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
                call png%draw_path(star_x, star_y, star_v, 6, paint)
                call png%close_canvas()
                call expect_pixel(png, 30, 31, [k, k, k], trim(name)//" pentagram middle", nfail)
            end block
        end do
        ! Clipped at x = 29.5, through the hole, by a frame.
        paint%fill_rule = FILL_EVENODD
        half = clip_t(.true., 0.0_dp, 0.0_dp, 29.5_dp, 60.0_dp)
        block
            type(png_renderer_t) :: png
            png%keep_pixels = .true.
            call png%set_dpi(72.0_dp)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            call png%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp], half)
            call png%draw_path(ring_x, ring_y, ring_v, 10, paint)
            call png%end_frame()
            call png%close_canvas()
            call expect_pixel(png, 30, 30, [255, 255, 255], "even-odd ring hole at a frame's clip", nfail)
            call expect_pixel(png, 15, 30, [0, 0, 0], "even-odd ring in a clipped frame", nfail)
            call expect_pixel(png, 31, 15, [255, 255, 255], "even-odd ring past a frame's clip", nfail)
            ! Half the pixel the clip cuts through the ring.
            g = iachar(png%rgb(3*((15 - 1)*png%pw + 30 - 1) + 1:3*((15 - 1)*png%pw + 30 - 1) + 1))
            call expect(abs(g - 128) <= 1, "even-odd ring half covered at a frame's clip", nfail)
        end block
        ! Ring markers in the clipped frame: the clip runs through the
        ! first one's hole, which keeps no line there, and the second is
        ! past the clip.
        block
            type(png_renderer_t) :: png
            real(dp), parameter :: mx(8) = [-8.0_dp, 8.0_dp, 8.0_dp, -8.0_dp, -3.0_dp, 3.0_dp, 3.0_dp, -3.0_dp]
            real(dp), parameter :: my(8) = [-8.0_dp, -8.0_dp, 8.0_dp, 8.0_dp, -3.0_dp, -3.0_dp, 3.0_dp, 3.0_dp]
            png%keep_pixels = .true.
            call png%set_dpi(72.0_dp)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            call png%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp], half)
            call png%draw_markers([29.5_dp, 50.0_dp], [15.0_dp, 15.0_dp], mx, my, ring_v, 10, paint)
            call png%end_frame()
            call png%close_canvas()
            call expect_pixel(png, 30, 15, [255, 255, 255], "even-odd ring marker hole at a frame's clip", nfail)
            call expect_pixel(png, 24, 15, [0, 0, 0], "even-odd ring marker in a clipped frame", nfail)
            call expect_pixel(png, 50, 10, [255, 255, 255], "even-odd ring marker past a frame's clip", nfail)
        end block
        ! Clips that change between fills on one canvas: a second frame
        ! clipped to the other side, and a paint clip inside a clipped frame.
        block
            type(png_renderer_t) :: png
            type(paint_t) :: low
            png%keep_pixels = .true.
            call png%set_dpi(72.0_dp)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            call png%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp], half)
            call png%draw_path(ring_x, ring_y, ring_v, 10, paint)
            call png%end_frame()
            call png%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp], &
                                 clip_t(.true., 31.0_dp, 0.0_dp, 29.0_dp, 60.0_dp))
            call png%draw_path(ring_x, ring_y, ring_v, 10, paint)
            call png%end_frame()
            call png%close_canvas()
            call expect_pixel(png, 15, 30, [0, 0, 0], "even-odd ring under a first frame's clip", nfail)
            call expect_pixel(png, 45, 30, [0, 0, 0], "even-odd ring under a second frame's clip", nfail)
            call expect_pixel(png, 31, 15, [255, 255, 255], "even-odd ring between two frames' clips", nfail)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            low = paint
            low%clip = clip_t(.true., 0.0_dp, 0.0_dp, 60.0_dp, 20.0_dp)
            call png%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp], half)
            call png%draw_path(ring_x, ring_y, ring_v, 10, low)
            call png%draw_path(ring_x + 1.0_dp, ring_y + 25.0_dp, ring_v, 10, paint)
            call png%end_frame()
            call png%close_canvas()
            call expect_pixel(png, 15, 15, [0, 0, 0], "even-odd ring under a paint clip in a clipped frame", nfail)
            call expect_pixel(png, 15, 25, [255, 255, 255], "even-odd ring past a paint clip in a clipped frame", nfail)
            call expect_pixel(png, 16, 55, [0, 0, 0], "even-odd ring after a paint clip, in a clipped frame", nfail)
        end block
        ! Partial coverage: the hole's edge at x = 20.5, half ring and half
        ! hole, is half covered, which a fold without its mirror would fill;
        ! and in a clipped frame, a square whose top and bottom fall at
        ! y = 10.5 and 49.5 keeps half its first and last rows, which a band
        ! of rows a row short would drop. A square far below the canvas
        ! draws nothing. A frame moved by a quarter point keeps the paths
        ! from being snapped to whole pixels, as unmoved ones are.
        block
            type(png_renderer_t) :: png
            real(dp), parameter :: moved(6) = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.25_dp, 0.25_dp]
            real(dp), parameter :: hx(8) = [10.0_dp, 50.0_dp, 50.0_dp, 10.0_dp, &
                                            20.25_dp, 39.25_dp, 39.25_dp, 20.25_dp]
            real(dp), parameter :: hy(8) = [10.0_dp, 10.0_dp, 50.0_dp, 50.0_dp, &
                                            20.0_dp, 20.0_dp, 40.0_dp, 40.0_dp]
            real(dp), parameter :: sx(4) = [5.0_dp, 25.0_dp, 25.0_dp, 5.0_dp]
            real(dp), parameter :: sy(4) = [10.25_dp, 10.25_dp, 49.25_dp, 49.25_dp]
            integer, parameter :: sv(5) = [VERB_MOVE, VERB_LINE, VERB_LINE, VERB_LINE, VERB_CLOSE]
            png%keep_pixels = .true.
            call png%set_dpi(72.0_dp)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            call png%begin_frame(moved, clip_t(.false., 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp))
            call png%draw_path(hx, hy, ring_v, 10, paint)
            call png%end_frame()
            call png%close_canvas()
            call expect(abs(grey(png, 21, 30) - 128) <= 1, "even-odd ring half covered at its hole's edge", nfail)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            call png%begin_frame(moved, half)
            call png%draw_path(sx, sy, sv, 5, paint)
            call png%draw_path(sx, sy + 1.0e10_dp, sv, 5, paint)
            call png%draw_path(sx, sy - 1.0e10_dp, sv, 5, paint)
            call png%end_frame()
            call png%close_canvas()
            call expect(abs(grey(png, 15, 11) - 128) <= 1 .and. abs(grey(png, 15, 50) - 128) <= 1, &
                        "even-odd fill in a clipped frame keeps its first and last rows", nfail)
            call expect_pixel(png, 15, 30, [0, 0, 0], "even-odd square in a clipped frame", nfail)
        end block
        ! An even-odd ring over the whole canvas in a clipped frame reaches
        ! its first and last rows, which the band of rows must keep; and
        ! with no frame, a paint clip at x = 29.5 cuts it to whole pixels,
        ! as every fill outside a transformed frame is cut.
        block
            type(png_renderer_t) :: png
            type(paint_t) :: clipped
            real(dp), parameter :: moved(6) = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.25_dp, 0.25_dp]
            real(dp), parameter :: bx(8) = [-10.0_dp, 70.0_dp, 70.0_dp, -10.0_dp, &
                                            20.0_dp, 40.0_dp, 40.0_dp, 20.0_dp]
            real(dp), parameter :: by(8) = [-10.0_dp, -10.0_dp, 70.0_dp, 70.0_dp, &
                                            20.0_dp, 20.0_dp, 40.0_dp, 40.0_dp]
            png%keep_pixels = .true.
            call png%set_dpi(72.0_dp)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            ! Clipped at x = 29.5, and past the canvas above and below.
            call png%begin_frame(moved, clip_t(.true., 0.0_dp, -5.0_dp, 29.5_dp, 70.0_dp))
            call png%draw_path(bx, by, ring_v, 10, paint)
            call png%end_frame()
            call png%close_canvas()
            call expect_pixel(png, 10, 1, [0, 0, 0], "even-odd fill in a clipped frame on the canvas's first row", nfail)
            call expect_pixel(png, 10, 60, [0, 0, 0], "even-odd fill in a clipped frame on the canvas's last row", nfail)
            call expect_pixel(png, 30, 30, [255, 255, 255], "even-odd hole in a clipped frame across the canvas", nfail)
            call png%open_canvas(60.0_dp, 60.0_dp, [255, 255, 255])
            clipped = paint
            clipped%clip = clip_t(.true., 0.0_dp, 0.0_dp, 29.5_dp, 60.0_dp)
            call png%draw_path(bx, by, ring_v, 10, clipped)
            call png%close_canvas()
            call expect(grey(png, 30, 10) == 0 .or. grey(png, 30, 10) == 255, &
                        "even-odd fill under a paint clip outside a frame is cut to whole pixels", nfail)
            call expect_pixel(png, 10, 10, [0, 0, 0], "even-odd fill under a paint clip outside a frame", nfail)
        end block
    contains
        integer function grey(png, x, y)
            type(png_renderer_t), intent(in) :: png
            integer, intent(in) :: x, y
            grey = iachar(png%rgb(3*((y - 1)*png%pw + x - 1) + 1:3*((y - 1)*png%pw + x - 1) + 1))
        end function grey
    end subroutine png_evenodd_check

    subroutine expect_pixel(png, x, y, expected, label, nfail)
        type(png_renderer_t), intent(in) :: png
        integer, intent(in) :: x, y, expected(3)
        character(len=*), intent(in) :: label
        integer, intent(inout) :: nfail
        integer :: k, c, actual(3)

        if (.not. allocated(png%rgb)) then
            call expect(.false., label//": no rendered pixels", nfail)
            return
        end if
        if (x < 1 .or. x > png%pw .or. y < 1 .or. y > png%ph) then
            call expect(.false., label//": pixel outside canvas", nfail)
            return
        end if
        k = 3*((y - 1)*png%pw + x - 1)
        if (len(png%rgb) < k + 3) then
            call expect(.false., label//": truncated rendered pixels", nfail)
            return
        end if
        do c = 1, 3
            actual(c) = iachar(png%rgb(k + c:k + c))
        end do
        if (all(actual == expected)) return
        nfail = nfail + 1
        print "(a,a,a,3(i0,1x),a,3(i0,1x))", "  FAIL ", label, ": got ", actual, "expected ", expected
    end subroutine expect_pixel

    subroutine pdf_resources_check(nfail)
        integer, intent(inout) :: nfail
        integer, parameter :: NIMAGE = 20, NALPHA = 80
        type(pdf_renderer_t) :: pdf
        type(paint_t) :: paint
        integer :: i, rgba(4, 1, 1), pos, ios
        real(dp) :: alpha
        character(len=16) :: id
        character(len=:), allocatable :: document, key
        logical :: images_present, alphas_present

        call pdf%open_canvas(100.0_dp, 100.0_dp)
        do i = 1, NIMAGE
            rgba(:, 1, 1) = [7*i, 255 - 5*i, 3*i, 255]
            if (mod(i, 3) == 0) rgba(4, 1, 1) = 128
            call pdf%draw_image(real(4*i, dp), 0.0_dp, 3.0_dp, 3.0_dp, rgba, 1, 1, paint)
        end do
        paint%filled = .true.
        do i = 1, NALPHA
            paint%fill_alpha = real(i, dp)/100.0_dp
            call pdf%draw_rect(real(i, dp), 10.0_dp, 1.0_dp, 20.0_dp, paint)
        end do
        call pdf%close_canvas()
        document = pdf%bytes()

        images_present = .true.
        do i = 1, NIMAGE
            write (id, "(i0)") i
            if (occurrences(document, "/Im"//trim(id)//" Do") /= 1) images_present = .false.
        end do
        call expect(images_present, "PDF retains every image draw past image 16", nfail)
        call expect(occurrences(document, "/ColorSpace /DeviceRGB") == NIMAGE, &
                    "PDF emits every RGB image XObject", nfail)
        call expect(occurrences(document, "/ColorSpace /DeviceGray") == NIMAGE/3, &
                    "PDF retains image soft masks after resource growth", nfail)

        alphas_present = .true.
        do i = 1, NALPHA
            write (id, "(i0)") i
            if (occurrences(document, "/GS"//trim(id)//" gs") /= 1) alphas_present = .false.
            key = "/GS"//trim(id)//" << /Type /ExtGState /ca "
            if (occurrences(document, key) /= 1) alphas_present = .false.
            pos = index(document, key)
            if (pos == 0) cycle
            read (document(pos + len(key):), *, iostat=ios) alpha
            if (ios /= 0) then
                alphas_present = .false.
            else if (abs(alpha - real(i, dp)/100.0_dp) > 1.0e-12_dp) then
                alphas_present = .false.
            end if
        end do
        call expect(alphas_present, "PDF defines and uses every alpha state past state 64", nfail)
    end subroutine pdf_resources_check

    subroutine pdf_pages_check(nfail)
        integer, intent(inout) :: nfail
        type(pdf_renderer_t) :: pdf
        character(len=:), allocatable :: document

        call pdf%open_canvas(100.0_dp, 80.0_dp, [255, 255, 255])
        call pdf%new_page(width=160.0_dp, height=120.0_dp, bg_rgb=[0, 0, 0], bg_alpha=0.5_dp)
        call pdf%new_page()
        call pdf%close_canvas()
        document = pdf%bytes()

        call expect(occurrences(document, "/Type /Page ") == 3, "PDF keeps all three pages", nfail)
        call expect(occurrences(document, "/MediaBox [0 0 100 80]") == 1 .and. &
                    occurrences(document, "/MediaBox [0 0 160 120]") == 2, &
                    "PDF preserves earlier page sizes and inherits the current size", nfail)
        call expect(index(document, "/MediaBox [0 0 100 80]") < index(document, "/MediaBox [0 0 160 120]"), &
                    "PDF preserves page order when sizes change", nfail)
        call expect(occurrences(document, "0 0 100 80 re") == 1 .and. &
                    occurrences(document, "0 0 160 120 re") == 2, &
                    "PDF backgrounds use their own page dimensions", nfail)
        call expect(occurrences(document, "/GS1 gs") == 2 .and. &
                    occurrences(document, "0 0 0 rg") == 2, &
                    "PDF no-argument new_page inherits background color and alpha", nfail)
    end subroutine pdf_pages_check

    integer function occurrences(text, token) result(n)
        character(len=*), intent(in) :: text, token
        integer :: offset, found

        n = 0
        offset = 1
        do while (offset <= len(text))
            found = index(text(offset:), token)
            if (found == 0) exit
            n = n + 1
            offset = offset + found - 1 + len(token)
        end do
    end function occurrences

end module test_frame_backends
