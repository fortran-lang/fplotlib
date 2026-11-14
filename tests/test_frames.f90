! Owned frames and pages: recorded drawing that outlives its inputs, glyph
! runs that keep the source text they were set from, a plot captured as a
! frame, and the errors of frame and page operations.
module test_frames
    use fplotlib_status
    use test_status
    use fplotlib_style, only: dp
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY
    use fplotlib_document, only: document_asset_t, export_document
    use fplotlib_render, only: glyphrun_t, paint_t
    use fplotlib_text, only: text_layout, run_copy, run_add, run_map
    use fplotlib_glyphs, only: FACE_REGULAR
    use fplotlib_mathtext, only: math_context_t, math_frame
    use fplotlib_artist, only: append_text
    use fplotlib, only: figure, plot, clf, render_png
    use fplotlib_draw, only: render_frame
    use fplotlib_backend_pdf, only: pdf_renderer_t
    implicit none
    private
    public :: frames_check

    type, extends(recording_renderer_t) :: failing_renderer_t
        integer :: calls = 0
    contains
        procedure :: draw_rect => fail_rect
    end type failing_renderer_t

contains

    subroutine frames_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call owned_frames(nfail)
        call logical_text(nfail)
        call recorded_source(nfail)
        call captured_plot(nfail)
        call recoverable_inputs(nfail)
        call recoverable_output(nfail)
        print "(a,i0)", "owned frames: failures = ", nfail
    end subroutine frames_check

    subroutine check(ok, message, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: message
        integer, intent(inout) :: nfail
        if (ok) return
        print "(a)", "  FAIL "//message
        nfail = nfail + 1
    end subroutine check

    subroutine owned_frames(nfail)
        integer, intent(inout) :: nfail
        type(frame_t) :: child, parent
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: before(:), after(:)
        integer :: handle
        real(dp) :: matrix(6), w, h
        type(status_t) :: status
        character(len=:), allocatable :: source
        block
            type(recording_renderer_t) :: recorder
            type(glyphrun_t) :: run
            type(paint_t) :: paint
            integer :: image(4, 2, 1)
            real(dp) :: advance
            paint%filled = .true.
            call text_layout("Owned", 12.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance, status=status)
            call require_ok(status)
            image(:, 1, 1) = [255, 0, 0, 255]
            image(:, 2, 1) = [0, 255, 0, 255]
            call recorder%open_canvas(80.0_dp, 30.0_dp, status=status)
            call require_ok(status)
            call recorder%draw_glyphs(0.0_dp, 12.0_dp, run, paint, 0.0_dp, status=status)
            call require_ok(status)
            call recorder%draw_image(0.0_dp, 16.0_dp, 20.0_dp, 10.0_dp, image, 2, 1, paint, status=status)
            call require_ok(status)
            call recorder%close_canvas(status=status)
            call require_ok(status)
            call recorder%take(child, status=status)
            call require_ok(status)
            run%text = "Changed"
            run%gid = 0
            image = 0
        end block

        call parent%init(160.0_dp, 60.0_dp, status=status)
        call require_ok(status)
        call parent%import_frame(child, handle, status=status)
        call require_ok(status)
        call parent%place(handle, status=status)
        call require_ok(status)
        matrix = IDENTITY
        matrix(5:6) = [80.0_dp, 30.0_dp]
        call parent%place(handle, matrix, status=status)
        call require_ok(status)
        call document%add_page(parent, status=status)
        call require_ok(status)
        call export_document(document, "svg", before, status=status)
        call require_ok(status)
        source = parent%source_text(status=status)
        call require_ok(status)
        call check(index(source, "OwnedOwned") > 0, "shared child instances retain text", nfail)
        call child%init(1.0_dp, 1.0_dp, status=status)
        call require_ok(status)
        call parent%init(2.0_dp, 2.0_dp, status=status)
        call require_ok(status)
        call export_document(document, "svg", after, status=status)
        call require_ok(status)
        call check(before(1)%bytes == after(1)%bytes, "frames own inputs and imported children", nfail)
        call document%page_size(1, w, h, status=status)
        call require_ok(status)
        call check(w == 160.0_dp .and. h == 60.0_dp, "page keeps original frame dimensions", nfail)
    end subroutine owned_frames

    subroutine logical_text(nfail)
        integer, intent(inout) :: nfail
        type(math_context_t) :: math
        type(frame_t) :: frame, formula
        type(glyphrun_t) :: run
        character(len=:), allocatable :: source
        real(dp) :: advance
        type(status_t) :: status
        source = "A"//achar(204)//achar(138)//achar(226)//achar(132)//achar(131)
        call text_layout(source, 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance, status=status)
        call require_ok(status)
        call check(run%n == 3, "normalization and Celsius expansion", nfail)
        if (run%n == 3) then
            call check(all(run%first(1:3) == [1, 4, 4]) .and. &
                       all(run%last(1:3) == [3, 6, 6]), "UTF-8 glyph cluster ranges", nfail)
        end if
        call check(run%text == source, "normalization preserves logical source", nfail)

        call math_frame("\frac{x}{y}", 12.0_dp, .true., formula, context=math, status=status)
        call require_ok(status)
        call math_frame("z^2", 9.0_dp, .false., frame, context=math, status=status)
        call require_ok(status)
        source = formula%source_text(status=status)
        call require_ok(status)
        call check(source == "\frac{x}{y}", "math frame retains its source independently", nfail)
    end subroutine logical_text

    subroutine recorded_source(nfail)
        integer, intent(inout) :: nfail
        type(recording_renderer_t) :: recorder
        type(frame_t) :: frame
        type(status_t) :: status
        character(len=:), allocatable :: source
        call recorder%open_canvas(200.0_dp, 50.0_dp, status=status)
        call require_ok(status)
        call append_text(recorder, 0.0_dp, 12.0_dp, "Plain.", "left", 10.0_dp, "#000000", status=status)
        call require_ok(status)
        call append_text(recorder, 0.0_dp, 26.0_dp, "Cost \$2 and $x^2$.", "left", 10.0_dp, "#000000", status=status)
        call require_ok(status)
        call recorder%close_canvas(status=status)
        call require_ok(status)
        call recorder%take(frame, status=status)
        call require_ok(status)
        source = frame%source_text(status=status)
        call require_ok(status)
        call check(source == "Plain.Cost $2 and $x^2$.", &
                   "recorded labels retain their source once without replacing cluster text", nfail)
    end subroutine recorded_source

    subroutine captured_plot(nfail)
        integer, intent(inout) :: nfail
        type(frame_t) :: chart
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: assets(:)
        character(len=:), allocatable :: direct
        type(status_t) :: status
        call figure(figsize=[2.0_dp, 1.5_dp], dpi=72.0_dp)
        call plot([0.0_dp, 1.0_dp, 2.0_dp], [0.0_dp, 1.0_dp, 0.0_dp])
        direct = render_png()
        call render_frame(chart, status=status)
        call require_ok(status)
        call clf()
        call document%add_page(chart, status=status)
        call require_ok(status)
        call export_document(document, "png", assets, dpi=72.0_dp, status=status)
        call require_ok(status)
        call check(direct == assets(1)%bytes, "captured vector plot replays after clf", nfail)
    end subroutine captured_plot

    subroutine fail_rect(self, x, y, w, h, paint, radius, status)
        class(failing_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        type(status_t), intent(out) :: status
        self%calls = self%calls + 1
        call status%set(ERROR_UNSUPPORTED, "test target cannot draw rectangles")
    end subroutine fail_rect

    subroutine recoverable_inputs(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: status
        type(frame_t) :: frame
        type(recording_renderer_t) :: recorder
        type(failing_renderer_t) :: target
        type(paint_t) :: paint
        type(glyphrun_t) :: empty, run
        real(dp) :: w, h

        call frame%init(20.0_dp, 30.0_dp, status=status)
        call require_ok(status)
        call frame%set_size(-1.0_dp, 30.0_dp, status)
        call check(status%code == ERROR_ARGUMENT, "invalid frame size returns an error", nfail)
        call frame%metrics(w, h, status=status)
        call require_ok(status)
        call check(w == 20.0_dp .and. h == 30.0_dp .and. .not. allocated(status%message), &
                   "failed mutation preserves geometry and a later call resets status", nfail)

        call run_copy(empty, run, status)
        call require_ok(status)
        call run_add(run, 0, 0.0_dp, 0.0_dp, 10.0_dp, status)
        call require_ok(status)
        call run_map(run, 0, 1, "invalid range", status=status)
        call check(status%code == ERROR_ARGUMENT .and. run%text == "", &
                   "invalid glyph mapping does not append source", nfail)

        paint%filled = .true.
        call recorder%open_canvas(20.0_dp, 20.0_dp, status=status)
        call require_ok(status)
        call recorder%end_frame(status)
        call check(status%code == ERROR_STATE, "recorder hides its internal crop scope", nfail)
        call recorder%begin_group("group", status)
        call require_ok(status)
        call recorder%end_frame(status)
        call check(status%code == ERROR_STATE, "recorder rejects mismatched scope endings", nfail)
        call recorder%end_group(status)
        call require_ok(status)
        paint%fill_rule = -1
        call recorder%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, paint, status=status)
        call check(status%code == ERROR_UNSUPPORTED, "unsupported paint is not silently recorded", nfail)
        paint%fill_rule = 0
        call recorder%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, paint, status=status)
        call require_ok(status)
        call recorder%draw_rect(2.0_dp, 2.0_dp, 1.0_dp, 1.0_dp, paint, status=status)
        call require_ok(status)
        call recorder%close_canvas(status)
        call require_ok(status)
        call recorder%take(frame, status)
        call require_ok(status)
        call target%open_canvas(20.0_dp, 20.0_dp, status=status)
        call require_ok(status)
        call frame%draw(target, status=status)
        call check(status%code == ERROR_UNSUPPORTED .and. target%calls == 1, &
                   "frame replay propagates the first backend error without continuing", nfail)
        call target%close_canvas(status)
        call require_ok(status)
    end subroutine recoverable_inputs

    subroutine recoverable_output(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: status
        type(frame_t) :: page
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: assets(:)
        type(pdf_renderer_t) :: pdf
        character(len=:), allocatable :: bytes
        real(dp) :: zero, nan

        zero = 0.0_dp
        nan = zero/zero
        call page%init(100.0_dp, 80.0_dp, status=status)
        call require_ok(status)
        call document%add_page(page, status=status)
        call require_ok(status)
        call export_document(document, "unknown", assets, status=status)
        call check(status%code == ERROR_UNSUPPORTED .and. .not. allocated(assets), &
                   "unsupported export has an explicit error and no assets", nfail)
        call export_document(document, "png", assets, dpi=nan, status=status)
        call check(status%code == ERROR_ARGUMENT .and. .not. allocated(assets), &
                   "nonfinite dpi does not return partial assets", nfail)
        call pdf%open_canvas(100.0_dp, 80.0_dp, status=status)
        call require_ok(status)
        call pdf%new_page(width=-1.0_dp, status=status)
        call check(status%code == ERROR_ARGUMENT, "invalid new page is rejected before finalizing the old page", nfail)
        call pdf%close_canvas(status)
        call require_ok(status)
        bytes = pdf%bytes(status)
        call require_ok(status)
        call check(index(bytes, "/Count 1") > 0 .and. index(bytes, "/MediaBox [0 0 100 80]") > 0, &
                   "PDF remains usable after a failed page change", nfail)
    end subroutine recoverable_output

end module test_frames
