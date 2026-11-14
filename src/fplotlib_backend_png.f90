! fplotlib_backend_png — raster output.
!
! The odd one out among the backends: the other three write a description of
! the drawing and let something else decide what it looks like, while this one
! has to decide. That work lives in fplotlib_raster and fplotlib_png; what is left
! here is only the translation from the rendering API's calls into fills.
!
! Because the API is purely additive and in painter's order, every call is
! rasterized the moment it arrives and nothing is buffered. The pixels are the
! display list. Only close_canvas has anything left to do, and that is
! compression rather than drawing.
!
! Text arrives as glyphs already laid out, and each glyph's outline (see
! fplotlib_glyphs) is filled with exactly the code that fills any other path.
! The vector backends draw the same outlines, as embedded fonts or defined
! paths, so all four formats show the same text.

module fplotlib_backend_png
    use fplotlib_style, only: dp
    use fplotlib_render
    use fplotlib_raster
    use fplotlib_png, only: png_encode
    use fplotlib_glyphs, only: glyph_outline
    implicit none
    private

    public :: png_renderer_t

    ! Matplotlib's default figure dpi. Points are the API's unit, so this is
    ! the only place a pixel size is decided.
    real(dp), parameter :: DEFAULT_DPI = 100.0_dp

    type, extends(encoded_renderer_t) :: png_renderer_t
        type(canvas_t) :: cv
        type(pathbuf_t) :: pb
        real(dp) :: dpi = DEFAULT_DPI
        real(dp) :: ox = 0.0_dp, oy = 0.0_dp     ! canvas origin, in points
        character(len=:), allocatable :: out
        ! An animation wants the pixels, not a PNG of them. Off by default
        ! so that an ordinary savefig does not carry a second copy of the
        ! frame around.
        logical :: keep_pixels = .false.
        integer :: pw = 0, ph = 0
        character(len=:), allocatable :: rgb
    contains
        procedure :: open_canvas => png_open_canvas
        procedure :: close_canvas => png_close_canvas
        procedure :: bytes => png_bytes
        procedure :: draw_path => png_draw_path
        procedure :: draw_rect => png_draw_rect
        procedure :: draw_circle => png_draw_circle
        procedure :: draw_markers => png_draw_markers
        procedure :: draw_glyphs => png_draw_glyphs
        procedure :: draw_image => png_draw_image
        procedure :: begin_frame => png_begin_frame
        procedure :: end_frame => png_end_frame
        procedure :: set_dpi => png_set_dpi
    end type png_renderer_t

contains

    ! Has to be called before open_canvas, since the canvas is allocated at
    ! its final pixel size and never resampled.
    subroutine png_set_dpi(self, dpi)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: dpi

        self%dpi = dpi
    end subroutine png_set_dpi

    subroutine png_open_canvas(self, width, height, bg_rgb, bg_alpha, x0, y0)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha
        real(dp), intent(in), optional :: x0, y0
        integer :: rgb(3), wpx, hpx
        real(dp) :: alpha, s

        if (self%cv%n_frame /= 0) error stop "png: unclosed frame at open_canvas"
        ! No background colour means no figure patch at all, which is how
        ! transparent=True reaches the backend. The vector formats express
        ! that by drawing nothing; a raster has to say it, as alpha zero.
        rgb = [255, 255, 255]
        alpha = 0.0_dp
        if (present(bg_rgb)) then
            rgb = bg_rgb
            alpha = 1.0_dp
        end if
        if (present(bg_alpha)) alpha = bg_alpha
        self%ox = 0.0_dp
        self%oy = 0.0_dp
        if (present(x0)) self%ox = x0
        if (present(y0)) self%oy = y0

        self%width = width
        self%height = height
        s = self%dpi/72.0_dp
        wpx = max(1, nint(width*s))
        hpx = max(1, nint(height*s))
        call canvas_init(self%cv, wpx, hpx, s, rgb, alpha)
        self%pb%curve_scale = self%cv%curve_scale
        self%is_open = .true.
    end subroutine png_open_canvas

    subroutine png_close_canvas(self)
        class(png_renderer_t), intent(inout) :: self
        integer, allocatable :: rgba(:, :, :)

        if (self%cv%n_frame /= 0) error stop "png: unclosed frame at close_canvas"
        if (.not. self%is_open) return
        allocate (rgba(4, self%cv%w, self%cv%h))
        rgba = canvas_rgba(self%cv)
        if (self%keep_pixels) then
            call pack_rgb(self, rgba)
        else
            self%out = png_encode(self%cv%w, self%cv%h, rgba)
        end if
        call canvas_free(self%cv)
        self%is_open = .false.
    end subroutine png_close_canvas

    subroutine png_begin_frame(self, matrix, clip)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        real(dp) :: m(6)

        if (.not. self%is_open) error stop "png: begin_frame outside canvas"
        ! Conjugate the point transform by the existing crop/scale map,
        ! leaving all legacy path construction in origin-shifted pixels.
        m = matrix
        m(5) = (matrix(5) + (matrix(1) - 1.0_dp)*self%ox + matrix(3)*self%oy)*self%cv%scale
        m(6) = (matrix(6) + matrix(2)*self%ox + (matrix(4) - 1.0_dp)*self%oy)*self%cv%scale
        call canvas_begin_frame(self%cv, m, shifted_clip(self, clip))
        self%pb%curve_scale = self%cv%curve_scale
    end subroutine png_begin_frame

    subroutine png_end_frame(self)
        class(png_renderer_t), intent(inout) :: self

        call canvas_end_frame(self%cv)
        self%pb%curve_scale = self%cv%curve_scale
    end subroutine png_end_frame

    ! GIF has no alpha to speak of, so the frame is flattened onto white
    ! here, which is what a viewer would do with it anyway.
    subroutine pack_rgb(self, rgba)
        class(png_renderer_t), intent(inout) :: self
        integer, intent(in) :: rgba(:, :, :)
        integer :: x, y, c, k, a, v

        self%pw = self%cv%w
        self%ph = self%cv%h
        if (allocated(self%rgb)) deallocate (self%rgb)
        allocate (character(len=3*self%pw*self%ph) :: self%rgb)
        k = 0
        do y = 1, self%ph
            do x = 1, self%pw
                a = rgba(4, x, y)
                do c = 1, 3
                    v = (rgba(c, x, y)*a + 255*(255 - a))/255
                    k = k + 1
                    self%rgb(k:k) = achar(min(255, max(0, v)))
                end do
            end do
        end do
    end subroutine pack_rgb

    function png_bytes(self) result(b)
        class(png_renderer_t), intent(in) :: self
        character(len=:), allocatable :: b

        if (allocated(self%out)) then
            b = self%out
        else
            b = ""
        end if
    end function png_bytes

    ! ------------------------------------------------------------------
    ! Points to pixels. The canvas origin shifts the window onto the drawing
    ! rather than the drawing itself, which is how a tight bounding box works.
    ! ------------------------------------------------------------------

    pure function tx(self, x) result(v)
        class(png_renderer_t), intent(in) :: self
        real(dp), intent(in) :: x
        real(dp) :: v

        v = (x - self%ox)*self%cv%scale
    end function tx

    pure function ty(self, y) result(v)
        class(png_renderer_t), intent(in) :: self
        real(dp), intent(in) :: y
        real(dp) :: v

        v = (y - self%oy)*self%cv%scale
    end function ty

    ! The clip travels in the paint in points; the rasterizer wants it in the
    ! same shifted frame as everything else.
    function shifted_clip(self, c) result(r)
        class(png_renderer_t), intent(in) :: self
        type(clip_t), intent(in) :: c
        type(clip_t) :: r

        r = c
        r%x = c%x - self%ox
        r%y = c%y - self%oy
    end function shifted_clip

    ! Snap where matplotlib would. The width that decides the offset is the
    ! stroke width in pixels, or zero for a path that is only filled.
    subroutine maybe_snap(self, paint)
        class(png_renderer_t), intent(inout) :: self
        type(paint_t), intent(in) :: paint
        real(dp) :: lw

        if (.not. self%cv%identity_transform) return
        if (.not. pb_should_snap(self%pb)) return
        lw = 0.0_dp
        if (paint%stroked) lw = paint%line_width*self%cv%scale
        call pb_snap(self%pb, lw)
    end subroutine maybe_snap

    ! Fill then stroke, which is the order every one of these formats paints
    ! in and the order the SVG backend's attributes imply.
    subroutine paint_buf(self, paint)
        class(png_renderer_t), intent(inout) :: self
        type(paint_t), intent(in) :: paint
        type(paint_t) :: p

        p = paint
        p%clip = shifted_clip(self, paint%clip)
        if (paint%filled) then
            call fill_path_buf(self%cv, self%pb, paint%fill_rgb, paint%fill_alpha, p%clip)
        end if
        if (paint%stroked) call stroke_path_buf(self%cv, self%pb, p)
    end subroutine paint_buf

    ! ------------------------------------------------------------------
    ! Primitives
    ! ------------------------------------------------------------------

    subroutine build_path(self, x, y, verbs, n_verb)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        integer :: i, p

        call pb_reset(self%pb)
        p = 0
        do i = 1, n_verb
            select case (verbs(i))
            case (VERB_MOVE)
                p = p + 1
                call pb_move(self%pb, tx(self, x(p)), ty(self, y(p)))
            case (VERB_LINE)
                p = p + 1
                call pb_line(self%pb, tx(self, x(p)), ty(self, y(p)))
            case (VERB_CUBIC)
                call pb_cubic(self%pb, &
                              tx(self, x(p + 1)), ty(self, y(p + 1)), &
                              tx(self, x(p + 2)), ty(self, y(p + 2)), &
                              tx(self, x(p + 3)), ty(self, y(p + 3)))
                p = p + 3
            case (VERB_CLOSE)
                call pb_close(self%pb)
            end select
        end do
    end subroutine build_path

    subroutine png_draw_path(self, x, y, verbs, n_verb, paint)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint

        call build_path(self, x, y, verbs, n_verb)
        call maybe_snap(self, paint)
        call paint_buf(self, paint)
    end subroutine png_draw_path

    subroutine png_draw_rect(self, x, y, w, h, paint, radius)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        real(dp) :: r, k, x0, y0, x1, y1

        r = 0.0_dp
        if (present(radius)) r = min(radius, 0.5_dp*min(w, h))
        x0 = tx(self, x); y0 = ty(self, y)
        x1 = tx(self, x + w); y1 = ty(self, y + h)

        call pb_reset(self%pb)
        if (r <= 0.0_dp) then
            call pb_move(self%pb, x0, y0)
            call pb_line(self%pb, x1, y0)
            call pb_line(self%pb, x1, y1)
            call pb_line(self%pb, x0, y1)
        else
            r = r*self%cv%scale
            k = r*0.5522847498307933_dp
            call pb_move(self%pb, x0 + r, y0)
            call pb_line(self%pb, x1 - r, y0)
            call pb_cubic(self%pb, x1 - r + k, y0, x1, y0 + r - k, x1, y0 + r)
            call pb_line(self%pb, x1, y1 - r)
            call pb_cubic(self%pb, x1, y1 - r + k, x1 - r + k, y1, x1 - r, y1)
            call pb_line(self%pb, x0 + r, y1)
            call pb_cubic(self%pb, x0 + r - k, y1, x0, y1 - r + k, x0, y1 - r)
            call pb_line(self%pb, x0, y0 + r)
            call pb_cubic(self%pb, x0, y0 + r - k, x0 + r - k, y0, x0 + r, y0)
        end if
        call pb_close(self%pb)
        call maybe_snap(self, paint)
        call paint_buf(self, paint)
    end subroutine png_draw_rect

    ! Straight to a polygon rather than through four cubics: the rasterizer
    ! would flatten the cubics anyway, and going direct gives an exact circle
    ! instead of the 0.02% error the cubic approximation carries.
    subroutine png_draw_circle(self, cx, cy, r, paint)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
        real(dp), parameter :: TWOPI = 6.283185307179586_dp
        real(dp) :: rp, a
        integer :: i, n

        rp = r*self%cv%scale
        n = max(12, min(256, ceiling(rp*self%cv%curve_scale*3.0_dp)))
        call pb_reset(self%pb)
        do i = 1, n
            a = TWOPI*real(i - 1, dp)/real(n, dp)
            if (i == 1) then
                call pb_move(self%pb, tx(self, cx) + rp*cos(a), ty(self, cy) + rp*sin(a))
            else
                call pb_line(self%pb, tx(self, cx) + rp*cos(a), ty(self, cy) + rp*sin(a))
            end if
        end do
        call pb_close(self%pb)
        call paint_buf(self, paint)
    end subroutine png_draw_circle

    ! The vector backends define the marker once and reference it; a raster
    ! backend has to draw it every time, so the saving here is only in not
    ! rebuilding the shape description. Stamping is still one fill per point
    ! because overlapping markers must composite, not union.
    subroutine png_draw_markers(self, x, y, mx, my, mverbs, n_mverb, paint)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        real(dp), intent(in) :: mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
        integer :: i, j, p
        real(dp), allocatable :: sx(:), sy(:)

        allocate (sx(size(mx)), sy(size(my)))
        do i = 1, size(x)
            call pb_reset(self%pb)
            p = 0
            do j = 1, n_mverb
                select case (mverbs(j))
                case (VERB_MOVE)
                    p = p + 1
                    call pb_move(self%pb, tx(self, x(i) + mx(p)), ty(self, y(i) + my(p)))
                case (VERB_LINE)
                    p = p + 1
                    call pb_line(self%pb, tx(self, x(i) + mx(p)), ty(self, y(i) + my(p)))
                case (VERB_CUBIC)
                    call pb_cubic(self%pb, &
                                  tx(self, x(i) + mx(p + 1)), ty(self, y(i) + my(p + 1)), &
                                  tx(self, x(i) + mx(p + 2)), ty(self, y(i) + my(p + 2)), &
                                  tx(self, x(i) + mx(p + 3)), ty(self, y(i) + my(p + 3)))
                    p = p + 3
                case (VERB_CLOSE)
                    call pb_close(self%pb)
                end select
            end do
            call paint_buf(self, paint)
        end do
    end subroutine png_draw_markers

    ! ------------------------------------------------------------------
    ! Text
    ! ------------------------------------------------------------------

    ! All the glyphs of a run go into one path and are filled together,
    ! so that two glyphs that touch do not double their antialiased edge.
    subroutine png_draw_glyphs(self, x, y, run, paint, angle)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
        real(dp) :: ca, sa, ax, ay, ox_, oy_, fs, c1x, c1y, c2x, c2y, ex, ey
        real(dp), allocatable :: px(:), py(:)
        integer, allocatable :: gv(:)
        integer :: i, j, p, nv, np
        type(paint_t) :: pp

        if (run%n == 0) return
        ca = cos(angle*3.141592653589793_dp/180.0_dp)
        sa = sin(angle*3.141592653589793_dp/180.0_dp)
        ax = tx(self, x)
        ay = ty(self, y)

        pp = paint
        pp%stroked = .false.
        pp%filled = .true.
        pp%clip = shifted_clip(self, paint%clip)

        call pb_reset(self%pb)
        do i = 1, run%n
            call glyph_outline(run%gid(i), gv, nv, px, py, np)
            if (nv == 0) cycle
            ox_ = run%x(i)
            oy_ = run%y(i)
            fs = run%size(i)
            p = 0
            do j = 1, nv
                select case (gv(j))
                case (VERB_MOVE)
                    p = p + 1
                    call gpt(px(p), py(p), ex, ey)
                    call pb_move(self%pb, ex, ey)
                case (VERB_LINE)
                    p = p + 1
                    call gpt(px(p), py(p), ex, ey)
                    call pb_line(self%pb, ex, ey)
                case (VERB_CUBIC)
                    call gpt(px(p + 1), py(p + 1), c1x, c1y)
                    call gpt(px(p + 2), py(p + 2), c2x, c2y)
                    call gpt(px(p + 3), py(p + 3), ex, ey)
                    p = p + 3
                    call pb_cubic(self%pb, c1x, c1y, c2x, c2y, ex, ey)
                case (VERB_CLOSE)
                    call pb_close(self%pb)
                end select
            end do
        end do

        call fill_path_buf(self%cv, self%pb, paint%fill_rgb, paint%fill_alpha, pp%clip)

    contains

        ! Glyph space is ems with y up and the canvas is points with y
        ! down, so the glyph is scaled and flipped as it is placed. The
        ! run turns about its origin, which is what makes a rotated y axis
        ! label pivot where it should.
        subroutine gpt(fx, fy, cx, cy)
            real(dp), intent(in) :: fx, fy
            real(dp), intent(out) :: cx, cy
            real(dp) :: lx, ly

            lx = (ox_ + fx*fs)*self%cv%scale
            ly = (oy_ - fy*fs)*self%cv%scale
            cx = ax + lx*ca - ly*sa
            cy = ay + lx*sa + ly*ca
        end subroutine gpt

    end subroutine png_draw_glyphs

    subroutine png_draw_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(png_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(4, nx, ny)
        type(paint_t), intent(in) :: paint

        call blit_image(self%cv, x - self%ox, y - self%oy, w, h, rgba, nx, ny, &
                        paint%fill_alpha, shifted_clip(self, paint%clip))
    end subroutine png_draw_image

end module fplotlib_backend_png
