module test_frame_backends
    use fplotlib_style, only: dp
    use fplotlib_render, only: paint_t, clip_t, glyphrun_t, VERB_MOVE, VERB_LINE, VERB_CLOSE, &
                               CAP_BUTT, CAP_ROUND, CAP_SQUARE
    use fplotlib_raster, only: full_walk
    use fplotlib_backend_pdf, only: pdf_renderer_t
    use fplotlib_backend_png, only: png_renderer_t
    use fplotlib_glyphs, only: glyph_cmap, FACE_REGULAR
    implicit none
    private

    public :: frame_backend_check

contains

    subroutine frame_backend_check(nfail)
        integer, intent(out) :: nfail

        nfail = 0
        call pdf_resources_check(nfail)
        call pdf_pages_check(nfail)
        call pdf_text_check(nfail)
        call png_frames_check(nfail)
        call png_image_check(nfail)
        call png_dash_frames_check(nfail)
        print "(a,i0)", "frame backends: failures = ", nfail
    end subroutine frame_backend_check

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

    subroutine pdf_text_check(nfail)
        integer, intent(inout) :: nfail
        type(pdf_renderer_t) :: pdf
        type(paint_t) :: paint
        type(glyphrun_t) :: run
        character(len=:), allocatable :: document

        run%n = 3
        allocate (run%gid(3), run%font(3), run%first(3), run%last(3))
        allocate (run%x(3), run%y(3), run%size(3))
        run%gid = [glyph_cmap(FACE_REGULAR, 65), glyph_cmap(FACE_REGULAR, 233), glyph_cmap(FACE_REGULAR, 63)]
        run%font = FACE_REGULAR
        run%x = [0.0_dp, 12.0_dp, 24.0_dp]
        run%y = 0.0_dp
        run%size = 12.0_dp
        run%first = [1, 2, 4]
        run%last = [1, 3, 7]
        ! The emoji has a fallback outline, but extraction must retain its source.
        run%text = "Aé😀"
        paint%filled = .true.
        call pdf%open_canvas(100.0_dp, 80.0_dp)
        call pdf%draw_glyphs(5.0_dp, 15.0_dp, run, paint, 0.0_dp)

        run%text = "$A^2$"
        run%source_math = .true.
        run%first = 0
        run%last = 0
        call pdf%draw_glyphs(5.0_dp, 35.0_dp, run, paint, 0.0_dp)
        deallocate (run%text)
        run%source_math = .false.
        call pdf%draw_glyphs(5.0_dp, 55.0_dp, run, paint, 0.0_dp)
        call pdf%close_canvas()
        document = pdf%bytes()

        call expect(index(document, "/ActualText <FEFF004100E9D83DDE00>") > 0, &
                    "PDF ActualText retains BMP and supplementary Unicode", nfail)
        call expect(occurrences(document, "/ActualText") == 1 .and. occurrences(document, "EMC") == 1, &
                    "PDF excludes TeX source and unmapped runs from ActualText", nfail)
        call expect(occurrences(document, "BT"//new_line("a")) == 3 .and. &
                    occurrences(document, "ET"//new_line("a")) == 3 .and. &
                    index(document, "/ToUnicode") > 0 .and. index(document, "beginbfchar") > 0, &
                    "PDF still paints and maps text without ActualText", nfail)
    end subroutine pdf_text_check

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
        real(dp), parameter :: mats(6, 9) = reshape([ &
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
            1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 10.0_dp, 0.0_dp], [6, 9])
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
                        ! A segment whose pattern is finer than half a pixel
                        ! on the canvas is drawn solid, the one documented
                        ! approximation, which the full walk is not; such a
                        ! path is only drawn, which has to finish.
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
        ! under half a pixel on the canvas.
        pure logical function any_solid(a, period) result(r)
            real(dp), intent(in) :: a(6), period
            integer :: i
            real(dp) :: dx, dy
            r = .false.
            do i = 1, size(px) - 1
                dx = px(i + 1) - px(i)
                dy = py(i + 1) - py(i)
                if (period*hypot(a(1)*dx + a(3)*dy, a(2)*dx + a(4)*dy)/hypot(dx, dy) < 0.5_dp) r = .true.
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

    subroutine expect(ok, label, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: label
        integer, intent(inout) :: nfail

        if (ok) return
        nfail = nfail + 1
        print "(a)", "  FAIL "//label
    end subroutine expect

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
