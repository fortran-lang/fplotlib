! Column fitting and baseline-aligned rows, independent of document syntax.
module fplotlib_grid
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use fplotlib_style, only: dp
    use fplotlib_render, only: paint_t
    use fplotlib_scene, only: frame_t, recording_renderer_t, IDENTITY
    implicit none
    private
    public :: grid_widths, grid_row

contains

    ! Inputs measure content; the fitted widths include both sides' padding.
    subroutine grid_widths(natural, minimum, available, padding, widths)
        real(dp), intent(in) :: natural(:), minimum(:), available, padding
        real(dp), allocatable, intent(out) :: widths(:)
        real(dp), allocatable :: lower(:)
        real(dp) :: preferred_total, minimum_total, fraction
        integer :: n

        n = size(natural)
        if (size(minimum) /= n) error stop "grid_widths: inconsistent column counts"
        if (.not. ieee_is_finite(available) .or. .not. ieee_is_finite(padding)) &
            error stop "grid_widths: nonfinite available width or padding"
        if (available < 0.0_dp .or. padding < 0.0_dp) &
            error stop "grid_widths: negative available width or padding"
        if (.not. all(ieee_is_finite(natural)) .or. .not. all(ieee_is_finite(minimum))) &
            error stop "grid_widths: nonfinite column width"
        if (any(natural < 0.0_dp) .or. any(minimum < 0.0_dp)) &
            error stop "grid_widths: negative column width"
        allocate (widths(n), lower(n))
        if (n == 0) return
        lower(:) = minimum + 2.0_dp*padding
        widths(:) = max(natural, minimum) + 2.0_dp*padding
        minimum_total = sum(lower)
        preferred_total = sum(widths)
        if (.not. ieee_is_finite(minimum_total) .or. .not. ieee_is_finite(preferred_total)) &
            error stop "grid_widths: column widths overflow"
        if (minimum_total > available) &
            error stop "grid_widths: minimum column widths exceed available width"
        if (preferred_total <= available) then
            widths(:) = widths + (available - preferred_total)/real(n, dp)
        else
            fraction = (available - minimum_total)/(preferred_total - minimum_total)
            widths(:) = lower + fraction*(widths - lower)
        end if
    end subroutine grid_widths

    ! Cell baselines are their first baselines. The row's baseline is its bottom.
    subroutine grid_row(cells, widths, padding, frame, background, rule_color)
        type(frame_t), intent(in) :: cells(:)
        real(dp), intent(in) :: widths(:), padding
        type(frame_t), intent(out) :: frame
        integer, intent(in), optional :: background(3), rule_color(3)
        type(recording_renderer_t) :: recorder
        type(frame_t) :: rule
        type(paint_t) :: paint
        real(dp) :: ascent, descent, w, h, baseline, row_w, row_h, x, matrix(6), thick
        integer :: i, handle

        if (size(cells) /= size(widths)) error stop "grid_row: inconsistent column counts"
        if (.not. ieee_is_finite(padding)) error stop "grid_row: nonfinite padding"
        if (padding < 0.0_dp) error stop "grid_row: negative padding"
        if (.not. all(ieee_is_finite(widths))) error stop "grid_row: nonfinite column width"
        if (any(widths < 2.0_dp*padding)) error stop "grid_row: column narrower than padding"
        row_w = sum(widths)
        if (.not. ieee_is_finite(row_w)) error stop "grid_row: column widths overflow"
        ascent = 0.0_dp
        descent = 0.0_dp
        do i = 1, size(cells)
            call cells(i)%metrics(w, h, baseline)
            if (.not. all(ieee_is_finite([w, h, baseline]))) error stop "grid_row: nonfinite cell metrics"
            if (w > widths(i) - 2.0_dp*padding + 1.0e-10_dp*max(1.0_dp, widths(i))) &
                error stop "grid_row: cell exceeds its content width"
            ascent = max(ascent, baseline)
            descent = max(descent, h - baseline)
        end do
        row_h = ascent + descent + 2.0_dp*padding
        if (.not. ieee_is_finite(row_h)) error stop "grid_row: cell heights overflow"
        if (present(background)) then
            call recorder%open_canvas(row_w, row_h, bg_rgb=background)
            call recorder%close_canvas()
            call recorder%take(frame)
        else
            call frame%init(row_w, row_h)
        end if
        x = padding
        do i = 1, size(cells)
            call cells(i)%metrics(w, h, baseline)
            call frame%add_frame(cells(i), handle)
            matrix = IDENTITY
            matrix(5:6) = [x, padding + ascent - baseline]
            call frame%place(handle, matrix)
            x = x + widths(i)
        end do
        if (present(rule_color) .and. row_h > 0.0_dp) then
            thick = min(0.4_dp, row_h)
            paint%filled = .true.
            paint%fill_rgb = rule_color
            call recorder%open_canvas(row_w, row_h)
            call recorder%draw_rect(0.0_dp, row_h - thick, row_w, thick, paint)
            call recorder%close_canvas()
            call recorder%take(rule)
            call frame%add_frame(rule, handle)
            call frame%place(handle)
        end if
        call frame%set_baseline(row_h)
    end subroutine grid_row

end module fplotlib_grid
