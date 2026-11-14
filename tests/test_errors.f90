! Recoverable errors below the plotting facade: every fallible call returns
! a status_t, and the first failure is returned to the caller without the
! call going on to draw or write anything more.
module test_errors
    use fplotlib_status
    use test_status
    use fplotlib_style, only: dp
    use fplotlib_render, only: renderer_t, paint_t, glyphrun_t, FILL_NONZERO
    use fplotlib_backend_svg, only: svg_renderer_t
    use fplotlib_backend_png, only: png_renderer_t
    use fplotlib_glyphs, only: FACE_REGULAR
    use fplotlib_text, only: text_width
    use fplotlib_mathtext, only: math_width
    use fplotlib_draw, only: render_figure
    use fplotlib, only: figure, plot, title, clf
    implicit none
    private
    public :: error_check

    ! A drawing target that encodes nothing: a renderer_t needs no bytes.
    ! It counts the primitives it is asked for and refuses the fail_at-th.
    type, extends(renderer_t) :: counting_renderer_t
        integer :: calls = 0
        integer :: fail_at = 0
    contains
        procedure :: open_canvas => count_open
        procedure :: close_canvas => count_close
        procedure :: draw_path => count_path
        procedure :: draw_rect => count_rect
        procedure :: draw_circle => count_circle
        procedure :: draw_markers => count_markers
        procedure :: draw_glyphs => count_glyphs
        procedure :: draw_image => count_image
    end type counting_renderer_t

contains

    subroutine error_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call renderer_errors(nfail)
        call measurement_errors(nfail)
        call propagation(nfail)
        print "(a,i0)", "error checks: failures = ", nfail
    end subroutine error_check

    subroutine check(ok, message, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: message
        integer, intent(inout) :: nfail
        if (ok) return
        print "(a)", "  "//message
        nfail = nfail + 1
    end subroutine check

    subroutine renderer_errors(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: status
        type(svg_renderer_t) :: svg
        type(png_renderer_t) :: png
        type(paint_t) :: paint
        character(len=:), allocatable :: bytes

        paint%filled = .true.
        call svg%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, paint, status=status)
        call check(status%code == ERROR_STATE, "drawing needs an open canvas", nfail)
        bytes = svg%bytes(status)
        call check(status%code == ERROR_STATE, "bytes needs finished output", nfail)

        call svg%open_canvas(20.0_dp, 10.0_dp, status=status)
        call require_ok(status)
        paint%fill_rule = -1
        call svg%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, paint, status=status)
        call check(status%code == ERROR_UNSUPPORTED, "an unknown fill rule is refused", nfail)
        paint%fill_rule = FILL_NONZERO
        paint%fill_alpha = 2.0_dp
        call svg%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, paint, status=status)
        call check(status%code == ERROR_ARGUMENT, "an alpha outside [0,1] is refused", nfail)
        paint%fill_alpha = 1.0_dp
        call svg%end_group(status)
        call check(status%code == ERROR_STATE, "end_group needs a begin_group", nfail)
        call svg%begin_group("g", status)
        call require_ok(status)
        call svg%close_canvas(status)
        call check(status%code == ERROR_STATE .and. svg%is_open, &
                   "an open group keeps the canvas from closing", nfail)
        call svg%end_group(status)
        call require_ok(status)
        call svg%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, paint, status=status)
        call check(status%ok() .and. .not. allocated(status%message), &
                   "a later successful call clears the status", nfail)
        call svg%close_canvas(status)
        call require_ok(status)
        bytes = svg%bytes(status)
        call require_ok(status)
        call check(index(bytes, "</svg>") > 0, "the canvas is usable after refused calls", nfail)

        call png%open_canvas(huge(1.0_dp), 1.0_dp, status=status)
        call check(status%code == ERROR_ARGUMENT .and. .not. png%is_open, &
                   "an overflowing pixel size is refused before opening", nfail)
    end subroutine renderer_errors

    subroutine measurement_errors(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: status
        real(dp) :: w

        call text_width("abc", -1.0_dp, FACE_REGULAR, w, status)
        call check(status%code == ERROR_ARGUMENT .and. w == 0.0_dp, &
                   "a negative text size is refused", nfail)
        call text_width("abc", 10.0_dp, 0, w, status)
        call check(status%code == ERROR_ARGUMENT, "an unknown face is refused", nfail)
        call math_width("$x^2$", 0.0_dp, w, status=status)
        call check(status%code == ERROR_ARGUMENT, "a zero math size is refused", nfail)
        call text_width("abc", 10.0_dp, FACE_REGULAR, w, status)
        call require_ok(status)
        call check(w > 0.0_dp, "text is measured after refused calls", nfail)
    end subroutine measurement_errors

    ! A figure drawn on a target that fails stops at the first failure and
    ! hands it back, instead of drawing the rest of the figure.
    subroutine propagation(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: status
        type(counting_renderer_t) :: whole, failing

        call figure()
        call plot([0.0_dp, 1.0_dp, 2.0_dp], [0.0_dp, 1.0_dp, 4.0_dp])
        call title("errors")
        call render_figure(whole, status=status)
        call require_ok(status)
        call check(whole%calls > 3, "a figure draws several primitives", nfail)
        failing%fail_at = 3
        call render_figure(failing, status=status)
        call check(status%code == ERROR_UNSUPPORTED .and. failing%calls == 3, &
                   "drawing stops at the first backend error", nfail)
        call clf()
    end subroutine propagation

    subroutine count(self, status)
        class(counting_renderer_t), intent(inout) :: self
        type(status_t), intent(out) :: status
        self%calls = self%calls + 1
        if (self%calls == self%fail_at) &
            call status%set(ERROR_UNSUPPORTED, "counting renderer: refused")
    end subroutine count

    subroutine count_open(self, width, height, bg_rgb, bg_alpha, x0, y0, status)
        class(counting_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha
        real(dp), intent(in), optional :: x0, y0
        type(status_t), intent(out) :: status
        self%width = width
        self%height = height
        self%is_open = .true.
    end subroutine count_open

    subroutine count_close(self, status)
        class(counting_renderer_t), intent(inout) :: self
        type(status_t), intent(out) :: status
        self%is_open = .false.
    end subroutine count_close

    subroutine count_path(self, x, y, verbs, n_verb, paint, status)
        class(counting_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status
        call count(self, status)
    end subroutine count_path

    subroutine count_rect(self, x, y, w, h, paint, radius, status)
        class(counting_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        type(status_t), intent(out) :: status
        call count(self, status)
    end subroutine count_rect

    subroutine count_circle(self, cx, cy, r, paint, status)
        class(counting_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status
        call count(self, status)
    end subroutine count_circle

    subroutine count_markers(self, x, y, mx, my, mverbs, n_mverb, paint, status)
        class(counting_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        real(dp), intent(in) :: mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status
        call count(self, status)
    end subroutine count_markers

    subroutine count_glyphs(self, x, y, run, paint, angle, status)
        class(counting_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
        type(status_t), intent(out) :: status
        call count(self, status)
    end subroutine count_glyphs

    subroutine count_image(self, x, y, w, h, rgba, nx, ny, paint, status)
        class(counting_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status
        call count(self, status)
    end subroutine count_image

end module test_errors
