! Common preconditions for concrete drawing targets.
module fplotlib_render_checks
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use fplotlib_style, only: dp
    use fplotlib_status
    use fplotlib_render
    use fplotlib_glyphs, only: NGLYPH, NFACE
    use fplotlib_resources, only: initialize_resources
    implicit none
    private
    public :: check_open, check_canvas, check_paint, check_path, check_rect
    public :: check_glyphs, check_image, check_clip, check_font, check_rgb
    public :: check_finite

contains

    subroutine check_open(renderer, status)
        class(renderer_t), intent(in) :: renderer
        type(status_t), intent(out) :: status
        if (.not. renderer%is_open) call status%set(ERROR_STATE, "renderer: canvas is not open")
    end subroutine check_open

    subroutine check_rgb(rgb, status)
        integer, intent(in) :: rgb(3)
        type(status_t), intent(out) :: status
        if (any(rgb < 0) .or. any(rgb > 255)) call status%set(ERROR_ARGUMENT, "color: expected RGB values in [0,255]")
    end subroutine check_rgb

    subroutine check_finite(values, status)
        real(dp), intent(in) :: values(:)
        type(status_t), intent(out) :: status
        if (.not. all(ieee_is_finite(values))) call status%set(ERROR_ARGUMENT, "geometry: nonfinite coordinate")
    end subroutine check_finite

    subroutine check_canvas(renderer, width, height, bg_rgb, bg_alpha, x0, y0, status)
        class(renderer_t), intent(in) :: renderer
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha, x0, y0
        type(status_t), intent(out) :: status
        if (renderer%is_open) then
            call status%set(ERROR_STATE, "renderer: canvas is already open")
            return
        end if
        if (.not. all(ieee_is_finite([width, height])) .or. width < 0.0_dp .or. height < 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "renderer: canvas size must be finite and nonnegative")
            return
        end if
        if (present(bg_rgb)) then
            call check_rgb(bg_rgb, status)
            if (.not. status%ok()) return
        end if
        if (present(bg_alpha)) then
            if (.not. ieee_is_finite(bg_alpha) .or. bg_alpha < 0.0_dp .or. bg_alpha > 1.0_dp) then
                call status%set(ERROR_ARGUMENT, "renderer: background alpha must be in [0,1]")
                return
            end if
        end if
        if (present(x0)) then
            if (.not. ieee_is_finite(x0)) then
                call status%set(ERROR_ARGUMENT, "renderer: nonfinite canvas origin")
                return
            end if
        end if
        if (present(y0)) then
            if (.not. ieee_is_finite(y0)) then
                call status%set(ERROR_ARGUMENT, "renderer: nonfinite canvas origin")
                return
            end if
        end if
        call initialize_resources(status)
        if (.not. status%ok()) return
    end subroutine check_canvas

    subroutine check_clip(clip, status)
        type(clip_t), intent(in) :: clip
        type(status_t), intent(out) :: status
        if (.not. clip%on) return
        if (.not. all(ieee_is_finite([clip%x, clip%y, clip%w, clip%h])) .or. &
            clip%w < 0.0_dp .or. clip%h < 0.0_dp) &
            call status%set(ERROR_ARGUMENT, "clip: expected finite coordinates and nonnegative size")
    end subroutine check_clip

    subroutine check_paint(paint, status)
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status
        call check_clip(paint%clip, status)
        if (.not. status%ok()) return
        if (paint%filled) then
            call check_rgb(paint%fill_rgb, status)
            if (.not. status%ok()) return
            if (paint%fill_rule /= FILL_NONZERO .and. paint%fill_rule /= FILL_EVENODD) then
                call status%set(ERROR_UNSUPPORTED, "paint: unsupported fill rule")
                return
            end if
            if (.not. ieee_is_finite(paint%fill_alpha) .or. paint%fill_alpha < 0.0_dp .or. paint%fill_alpha > 1.0_dp) then
                call status%set(ERROR_ARGUMENT, "paint: fill alpha must be in [0,1]")
                return
            end if
        end if
        if (.not. paint%stroked) return
        call check_rgb(paint%stroke_rgb, status)
        if (.not. status%ok()) return
        if (.not. all(ieee_is_finite([paint%stroke_alpha, paint%line_width, paint%miter_limit, paint%dash_offset]))) then
            call status%set(ERROR_ARGUMENT, "paint: nonfinite stroke")
            return
        end if
        if (paint%stroke_alpha < 0.0_dp .or. paint%stroke_alpha > 1.0_dp .or. &
            paint%line_width < 0.0_dp .or. paint%miter_limit < 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "paint: invalid stroke alpha, width or miter limit")
            return
        end if
        if (paint%cap < CAP_BUTT .or. paint%cap > CAP_SQUARE .or. &
            paint%join < JOIN_MITER .or. paint%join > JOIN_BEVEL) then
            call status%set(ERROR_UNSUPPORTED, "paint: unsupported stroke cap or join")
            return
        end if
        if (paint%n_dash < 0 .or. paint%n_dash > MAX_DASH) then
            call status%set(ERROR_ARGUMENT, "paint: invalid dash count")
            return
        end if
        if (paint%n_dash > 0) then
            if (.not. all(ieee_is_finite(paint%dash(1:paint%n_dash))) .or. &
                any(paint%dash(1:paint%n_dash) < 0.0_dp)) then
                call status%set(ERROR_ARGUMENT, "paint: invalid dash length")
                return
            end if
            if (sum(paint%dash(1:paint%n_dash)) <= 0.0_dp) &
                call status%set(ERROR_ARGUMENT, "paint: dash pattern must have positive length")
        end if
    end subroutine check_paint

    subroutine check_path(x, y, verbs, n_verb, paint, status)
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status
        integer :: i, points
        logical :: started
        if (n_verb < 0 .or. n_verb > size(verbs)) then
            call status%set(ERROR_ARGUMENT, "path: invalid verb count")
            return
        end if
        points = 0
        started = .false.
        do i = 1, n_verb
            select case (verbs(i))
            case (VERB_MOVE)
                started = .true.
                points = points + 1
            case (VERB_LINE, VERB_CUBIC, VERB_CLOSE)
                if (.not. started) then
                    call status%set(ERROR_ARGUMENT, "path: a contour must begin with MOVE")
                    return
                end if
                if (verbs(i) == VERB_LINE) points = points + 1
                if (verbs(i) == VERB_CUBIC) points = points + 3
            case default
                call status%set(ERROR_UNSUPPORTED, "path: unsupported verb")
                return
            end select
        end do
        if (points > size(x) .or. points > size(y)) then
            call status%set(ERROR_ARGUMENT, "path: not enough coordinates for the verbs")
            return
        end if
        if (.not. all(ieee_is_finite(x(1:points))) .or. .not. all(ieee_is_finite(y(1:points)))) then
            call status%set(ERROR_ARGUMENT, "path: nonfinite coordinate")
            return
        end if
        call check_paint(paint, status)
        if (.not. status%ok()) return
    end subroutine check_path

    subroutine check_rect(x, y, w, h, paint, radius, status)
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        type(status_t), intent(out) :: status
        if (.not. all(ieee_is_finite([x, y, w, h])) .or. w < 0.0_dp .or. h < 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "rectangle: expected finite coordinates and nonnegative size")
            return
        end if
        if (present(radius)) then
            if (.not. ieee_is_finite(radius) .or. radius < 0.0_dp) then
                call status%set(ERROR_ARGUMENT, "rectangle: invalid corner radius")
                return
            end if
        end if
        call check_paint(paint, status)
        if (.not. status%ok()) return
    end subroutine check_rect

    subroutine check_glyphs(run, status)
        type(glyphrun_t), intent(in) :: run
        type(status_t), intent(out) :: status
        integer :: n
        n = run%n
        if (n < 0) then
            call status%set(ERROR_ARGUMENT, "glyph run: negative glyph count")
            return
        end if
        if (n == 0) return
        if (.not. allocated(run%gid) .or. .not. allocated(run%x) .or. &
            .not. allocated(run%y) .or. .not. allocated(run%size)) then
            call status%set(ERROR_ARGUMENT, "glyph run: missing glyph arrays")
            return
        end if
        if (min(size(run%gid), size(run%x), size(run%y), size(run%size)) < n) then
            call status%set(ERROR_ARGUMENT, "glyph run: truncated glyph arrays")
            return
        end if
        if (any(run%gid(1:n) < 0) .or. any(run%gid(1:n) > NGLYPH)) then
            call status%set(ERROR_ARGUMENT, "glyph run: invalid built-in glyph ID")
            return
        end if
        if (.not. all(ieee_is_finite(run%x(1:n))) .or. .not. all(ieee_is_finite(run%y(1:n))) .or. &
            .not. all(ieee_is_finite(run%size(1:n))) .or. any(run%size(1:n) < 0.0_dp)) then
            call status%set(ERROR_ARGUMENT, "glyph run: invalid position or font size")
            return
        end if
    end subroutine check_glyphs

    subroutine check_image(x, y, w, h, rgba, nx, ny, paint, status)
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: rgba(:, :, :), nx, ny
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status
        if (nx < 1 .or. ny < 1 .or. any(shape(rgba) /= [4, nx, ny])) then
            call status%set(ERROR_ARGUMENT, "image: expected a nonempty RGBA array matching nx and ny")
            return
        end if
        if (any(rgba < 0) .or. any(rgba > 255)) then
            call status%set(ERROR_ARGUMENT, "image: components must be in [0,255]")
            return
        end if
        call check_rect(x, y, w, h, paint, status=status)
        if (.not. status%ok()) return
    end subroutine check_image

    subroutine check_font(face, size, status)
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        type(status_t), intent(out) :: status
        if (face < 1 .or. face > NFACE .or. .not. ieee_is_finite(size) .or. size <= 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "text: expected a built-in font and a finite positive size")
            return
        end if
        call initialize_resources(status)
        if (.not. status%ok()) return
    end subroutine check_font

end module fplotlib_render_checks
