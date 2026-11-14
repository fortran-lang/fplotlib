! Preconditions of the rendering contract.
!
! A call that breaks the contract -- drawing on a canvas that is not open,
! a nonfinite coordinate, an alpha outside [0,1], a path whose verbs need
! more points than it has -- is a bug in the calling code. Nothing at run
! time can make such a call succeed, so it stops the program with a message
! that names the broken rule instead of returning an error for every caller
! to pass along. Recoverable failures, the ones a correct program can still
! meet, such as an unwritable output file, are returned through status_t.
module fplotlib_render_checks
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use, intrinsic :: iso_fortran_env, only: error_unit
    use fplotlib_style, only: dp
    use fplotlib_render
    use fplotlib_glyphs, only: NGLYPH, NFACE
    implicit none
    private
    public :: check_open, check_canvas, check_paint, check_path, check_rect
    public :: check_glyphs, check_image, check_clip, check_transform, check_font, check_rgb
    public :: check_frame_size, check_finite, contract_error

contains

    ! Stops the program: message names the rule the caller broke.
    subroutine contract_error(message)
        character(len=*), intent(in) :: message
        write (error_unit, "(a)") "fplotlib: "//message
        error stop 1
    end subroutine contract_error

    subroutine check_open(renderer)
        class(renderer_t), intent(in) :: renderer
        if (.not. renderer%is_open) call contract_error("renderer: canvas is not open")
    end subroutine check_open

    subroutine check_rgb(rgb)
        integer, intent(in) :: rgb(3)
        if (any(rgb < 0) .or. any(rgb > 255)) call contract_error("color: expected RGB values in [0,255]")
    end subroutine check_rgb

    subroutine check_finite(values)
        real(dp), intent(in) :: values(:)
        if (.not. all(ieee_is_finite(values))) call contract_error("geometry: nonfinite coordinate")
    end subroutine check_finite

    subroutine check_frame_size(width, height, baseline)
        real(dp), intent(in) :: width, height
        real(dp), intent(in), optional :: baseline
        if (.not. all(ieee_is_finite([width, height])) .or. width < 0.0_dp .or. height < 0.0_dp) then
            call contract_error("frame: size must be finite and nonnegative")
        end if
        if (present(baseline)) call check_finite([baseline])
    end subroutine check_frame_size

    subroutine check_canvas(renderer, width, height, bg_rgb, bg_alpha, x0, y0)
        class(renderer_t), intent(in) :: renderer
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha, x0, y0
        if (renderer%is_open) call contract_error("renderer: canvas is already open")
        if (.not. all(ieee_is_finite([width, height])) .or. width < 0.0_dp .or. height < 0.0_dp) then
            call contract_error("renderer: canvas size must be finite and nonnegative")
        end if
        if (present(bg_rgb)) then
            call check_rgb(bg_rgb)
        end if
        if (present(bg_alpha)) then
            if (.not. ieee_is_finite(bg_alpha) .or. bg_alpha < 0.0_dp .or. bg_alpha > 1.0_dp) then
                call contract_error("renderer: background alpha must be in [0,1]")
            end if
        end if
        if (present(x0)) then
            if (.not. ieee_is_finite(x0)) call contract_error("renderer: nonfinite canvas origin")
        end if
        if (present(y0)) then
            if (.not. ieee_is_finite(y0)) call contract_error("renderer: nonfinite canvas origin")
        end if
    end subroutine check_canvas

    subroutine check_clip(clip)
        type(clip_t), intent(in) :: clip
        if (.not. clip%on) return
        if (.not. all(ieee_is_finite([clip%x, clip%y, clip%w, clip%h])) .or. &
            clip%w < 0.0_dp .or. clip%h < 0.0_dp) &
            call contract_error("clip: expected finite coordinates and nonnegative size")
    end subroutine check_clip

    subroutine check_transform(matrix, clip)
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        if (.not. all(ieee_is_finite(matrix))) call contract_error("frame: nonfinite transform")
        call check_clip(clip)
    end subroutine check_transform

    subroutine check_paint(paint)
        type(paint_t), intent(in) :: paint
        call check_clip(paint%clip)
        if (paint%filled) then
            call check_rgb(paint%fill_rgb)
            if (paint%fill_rule /= FILL_NONZERO .and. paint%fill_rule /= FILL_EVENODD) then
                call contract_error("paint: unsupported fill rule")
            end if
            if (.not. ieee_is_finite(paint%fill_alpha) .or. paint%fill_alpha < 0.0_dp .or. paint%fill_alpha > 1.0_dp) then
                call contract_error("paint: fill alpha must be in [0,1]")
            end if
        end if
        if (.not. paint%stroked) return
        call check_rgb(paint%stroke_rgb)
        if (.not. all(ieee_is_finite([paint%stroke_alpha, paint%line_width, paint%miter_limit, paint%dash_offset]))) then
            call contract_error("paint: nonfinite stroke")
        end if
        if (paint%stroke_alpha < 0.0_dp .or. paint%stroke_alpha > 1.0_dp .or. &
            paint%line_width < 0.0_dp .or. paint%miter_limit < 0.0_dp) then
            call contract_error("paint: invalid stroke alpha, width or miter limit")
        end if
        if (paint%cap < CAP_BUTT .or. paint%cap > CAP_SQUARE .or. &
            paint%join < JOIN_MITER .or. paint%join > JOIN_BEVEL) then
            call contract_error("paint: unsupported stroke cap or join")
        end if
        if (paint%n_dash < 0 .or. paint%n_dash > MAX_DASH) then
            call contract_error("paint: invalid dash count")
        end if
        if (paint%n_dash > 0) then
            if (.not. all(ieee_is_finite(paint%dash(1:paint%n_dash))) .or. &
                any(paint%dash(1:paint%n_dash) < 0.0_dp)) then
                call contract_error("paint: invalid dash length")
            end if
            if (sum(paint%dash(1:paint%n_dash)) <= 0.0_dp) &
                call contract_error("paint: dash pattern must have positive length")
        end if
    end subroutine check_paint

    subroutine check_path(x, y, verbs, n_verb, paint)
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        integer :: i, points
        logical :: started
        if (n_verb < 0 .or. n_verb > size(verbs)) call contract_error("path: invalid verb count")
        points = 0
        started = .false.
        do i = 1, n_verb
            select case (verbs(i))
            case (VERB_MOVE)
                started = .true.
                points = points + 1
            case (VERB_LINE, VERB_CUBIC, VERB_CLOSE)
                if (.not. started) call contract_error("path: a contour must begin with MOVE")
                if (verbs(i) == VERB_LINE) points = points + 1
                if (verbs(i) == VERB_CUBIC) points = points + 3
            case default
                call contract_error("path: unsupported verb")
            end select
        end do
        if (points > size(x) .or. points > size(y)) then
            call contract_error("path: not enough coordinates for the verbs")
        end if
        if (.not. all(ieee_is_finite(x(1:points))) .or. .not. all(ieee_is_finite(y(1:points)))) then
            call contract_error("path: nonfinite coordinate")
        end if
        call check_paint(paint)
    end subroutine check_path

    subroutine check_rect(x, y, w, h, paint, radius)
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        if (.not. all(ieee_is_finite([x, y, w, h])) .or. w < 0.0_dp .or. h < 0.0_dp) then
            call contract_error("rectangle: expected finite coordinates and nonnegative size")
        end if
        if (present(radius)) then
            if (.not. ieee_is_finite(radius) .or. radius < 0.0_dp) then
                call contract_error("rectangle: invalid corner radius")
            end if
        end if
        call check_paint(paint)
    end subroutine check_rect

    subroutine check_glyphs(run)
        type(glyphrun_t), intent(in) :: run
        integer :: n
        n = run%n
        if (n < 0) call contract_error("glyph run: negative glyph count")
        if (n == 0) return
        if (.not. allocated(run%gid) .or. .not. allocated(run%x) .or. &
            .not. allocated(run%y) .or. .not. allocated(run%size)) then
            call contract_error("glyph run: missing glyph arrays")
        end if
        if (min(size(run%gid), size(run%x), size(run%y), size(run%size)) < n) then
            call contract_error("glyph run: truncated glyph arrays")
        end if
        if (any(run%gid(1:n) < 0) .or. any(run%gid(1:n) > NGLYPH)) then
            call contract_error("glyph run: invalid built-in glyph ID")
        end if
        if (.not. all(ieee_is_finite(run%x(1:n))) .or. .not. all(ieee_is_finite(run%y(1:n))) .or. &
            .not. all(ieee_is_finite(run%size(1:n))) .or. any(run%size(1:n) < 0.0_dp)) then
            call contract_error("glyph run: invalid position or font size")
        end if
        if (allocated(run%font)) then
            if (size(run%font) < n) call contract_error("glyph run: truncated font array")
        end if
        if (allocated(run%first) .neqv. allocated(run%last)) then
            call contract_error("glyph run: incomplete source mapping")
        end if
        if (allocated(run%first)) then
            if (min(size(run%first), size(run%last)) < n) then
                call contract_error("glyph run: truncated source mapping")
            end if
        end if
    end subroutine check_glyphs

    subroutine check_image(x, y, w, h, rgba, nx, ny, paint)
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: rgba(:, :, :), nx, ny
        type(paint_t), intent(in) :: paint
        if (nx < 1 .or. ny < 1 .or. any(shape(rgba) /= [4, nx, ny])) then
            call contract_error("image: expected a nonempty RGBA array matching nx and ny")
        end if
        if (any(rgba < 0) .or. any(rgba > 255)) then
            call contract_error("image: components must be in [0,255]")
        end if
        call check_rect(x, y, w, h, paint)
    end subroutine check_image

    subroutine check_font(face, size)
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        if (face < 1 .or. face > NFACE .or. .not. ieee_is_finite(size) .or. size <= 0.0_dp) then
            call contract_error("text: expected a built-in font and a finite positive size")
        end if
    end subroutine check_font

end module fplotlib_render_checks
