! Column fitting and baseline-aligned rows, independent of document syntax.
module fplotlib_grid
    use fplotlib_status
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use fplotlib_style, only: dp
    use fplotlib_render, only: paint_t
    use fplotlib_scene, only: frame_t, recording_renderer_t, IDENTITY
    implicit none
    private
    public :: grid_widths, grid_row

contains

    ! Inputs measure content; the fitted widths include both sides' padding.
    subroutine grid_widths(natural, minimum, available, padding, widths, status)
        real(dp), intent(in) :: natural(:), minimum(:), available, padding
        real(dp), allocatable, intent(out) :: widths(:)
        real(dp), allocatable :: lower(:), fitted(:)
        real(dp) :: preferred_total, minimum_total, fraction
        integer :: n

        type(status_t), intent(out) :: status
        n = size(natural)
        if (size(minimum) /= n) then
            call status%set(ERROR_ARGUMENT, "grid_widths: inconsistent column counts")
            return
        end if
        if (.not. ieee_is_finite(available) .or. .not. ieee_is_finite(padding)) then
            call status%set(ERROR_ARGUMENT, "grid_widths: nonfinite available width or padding")
            return
        end if
        if (available < 0.0_dp .or. padding < 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "grid_widths: negative available width or padding")
            return
        end if
        if (.not. all(ieee_is_finite(natural)) .or. .not. all(ieee_is_finite(minimum))) then
            call status%set(ERROR_ARGUMENT, "grid_widths: nonfinite column width")
            return
        end if
        if (any(natural < 0.0_dp) .or. any(minimum < 0.0_dp)) then
            call status%set(ERROR_ARGUMENT, "grid_widths: negative column width")
            return
        end if
        if (n == 0) then
            allocate (widths(0))
            return
        end if
        allocate (fitted(n), lower(n))
        lower(:) = minimum + 2.0_dp*padding
        fitted(:) = max(natural, minimum) + 2.0_dp*padding
        minimum_total = sum(lower)
        preferred_total = sum(fitted)
        if (.not. ieee_is_finite(minimum_total) .or. .not. ieee_is_finite(preferred_total)) then
            call status%set(ERROR_ARGUMENT, "grid_widths: column widths overflow")
            return
        end if
        if (minimum_total > available) then
            call status%set(ERROR_LAYOUT, "grid_widths: minimum column widths exceed available width")
            return
        end if
        if (preferred_total <= available) then
            fitted(:) = fitted + (available - preferred_total)/real(n, dp)
        else
            fraction = (available - minimum_total)/(preferred_total - minimum_total)
            fitted(:) = lower + fraction*(fitted - lower)
        end if
        call move_alloc(fitted, widths)
    end subroutine grid_widths

    ! Cell baselines are their first baselines. The row's baseline is its bottom.
    subroutine grid_row(cells, widths, padding, frame, background, rule_color, status)
        type(frame_t), intent(in) :: cells(:)
        real(dp), intent(in) :: widths(:), padding
        type(frame_t), intent(out) :: frame
        integer, intent(in), optional :: background(3), rule_color(3)
        type(recording_renderer_t) :: recorder
        type(frame_t) :: rule
        type(paint_t) :: paint
        real(dp) :: ascent, descent, w, h, baseline, row_w, row_h, x, matrix(6), thick
        integer :: i, handle

        type(status_t), intent(out) :: status
        if (size(cells) /= size(widths)) then
            call status%set(ERROR_ARGUMENT, "grid_row: inconsistent column counts")
            return
        end if
        if (.not. ieee_is_finite(padding)) then
            call status%set(ERROR_ARGUMENT, "grid_row: nonfinite padding")
            return
        end if
        if (padding < 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "grid_row: negative padding")
            return
        end if
        if (.not. all(ieee_is_finite(widths))) then
            call status%set(ERROR_ARGUMENT, "grid_row: nonfinite column width")
            return
        end if
        if (any(widths < 2.0_dp*padding)) then
            call status%set(ERROR_ARGUMENT, "grid_row: column narrower than padding")
            return
        end if
        row_w = sum(widths)
        if (.not. ieee_is_finite(row_w)) then
            call status%set(ERROR_ARGUMENT, "grid_row: column widths overflow")
            return
        end if
        ascent = 0.0_dp
        descent = 0.0_dp
        do i = 1, size(cells)
            call cells(i)%metrics(w, h, baseline, status=status)
            if (.not. status%ok()) return
            if (.not. all(ieee_is_finite([w, h, baseline]))) then
                call status%set(ERROR_ARGUMENT, "grid_row: nonfinite cell metrics")
                return
            end if
            if (w > widths(i) - 2.0_dp*padding + 1.0e-10_dp*max(1.0_dp, widths(i))) then
                call status%set(ERROR_ARGUMENT, "grid_row: cell exceeds its content width")
                return
            end if
            ascent = max(ascent, baseline)
            descent = max(descent, h - baseline)
        end do
        row_h = ascent + descent + 2.0_dp*padding
        if (.not. ieee_is_finite(row_h)) then
            call status%set(ERROR_ARGUMENT, "grid_row: cell heights overflow")
            return
        end if
        if (present(background)) then
            call recorder%open_canvas(row_w, row_h, bg_rgb=background, status=status)
            if (.not. status%ok()) return
            call recorder%close_canvas(status=status)
            if (.not. status%ok()) return
            call recorder%take(frame, status=status)
            if (.not. status%ok()) return
        else
            call frame%init(row_w, row_h, status=status)
            if (.not. status%ok()) return
        end if
        x = padding
        do i = 1, size(cells)
            call cells(i)%metrics(w, h, baseline, status=status)
            if (.not. status%ok()) return
            call frame%import_frame(cells(i), handle, status=status)
            if (.not. status%ok()) return
            matrix = IDENTITY
            matrix(5:6) = [x, padding + ascent - baseline]
            call frame%place(handle, matrix, status=status)
            if (.not. status%ok()) return
            x = x + widths(i)
        end do
        if (present(rule_color) .and. row_h > 0.0_dp) then
            thick = min(0.4_dp, row_h)
            paint%filled = .true.
            paint%fill_rgb = rule_color
            call recorder%open_canvas(row_w, row_h, status=status)
            if (.not. status%ok()) return
            call recorder%draw_rect(0.0_dp, row_h - thick, row_w, thick, paint, status=status)
            if (.not. status%ok()) return
            call recorder%close_canvas(status=status)
            if (.not. status%ok()) return
            call recorder%take(rule, status=status)
            if (.not. status%ok()) return
            call frame%import_frame(rule, handle, status=status)
            if (.not. status%ok()) return
            call frame%place(handle, status=status)
            if (.not. status%ok()) return
        end if
        call frame%set_baseline(row_h, status=status)
        if (.not. status%ok()) return
    end subroutine grid_row

end module fplotlib_grid
