module test_typeset_core
    use fplotlib_status
    use test_status
    use fplotlib_style, only: dp
    use fplotlib_typeset
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY
    use fplotlib_docclass, only: layout_context_t, layout_fragment, layout_markdown, doc_typeset
    use fplotlib_doctree, only: doc_t, doc_add_frame, doc_init
    use fplotlib_markdown, only: md_parse, md_append
    use fplotlib_document, only: document_asset_t, export_document
    use fplotlib_render, only: glyphrun_t, paint_t, clip_t
    use fplotlib_text, only: text_layout, run_copy, run_add, run_map
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_BOLD
    use fplotlib_mathtext, only: math_context_t, math_frame
    use fplotlib_artist, only: append_text
    use fplotlib, only: figure, plot, clf, render_png
    use fplotlib_draw, only: render_frame
    use fplotlib_report, only: report_t
    use fplotlib_grid, only: grid_widths
    use fplotlib_hyph, only: hyph_points
    use fplotlib_backend_png, only: png_renderer_t
    use fplotlib_backend_pdf, only: pdf_renderer_t
    implicit none
    private
    public :: typeset_core_check

    type, extends(recording_renderer_t) :: failing_renderer_t
        integer :: calls = 0
    contains
        procedure :: draw_rect => fail_rect
    end type failing_renderer_t

contains

    subroutine typeset_core_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call interleaved_layout(nfail)
        call owned_frames(nfail)
        call logical_text(nfail)
        call recorded_source(nfail)
        call embedded_document(nfail)
        call captured_plot(nfail)
        call recoverable_inputs(nfail)
        call recoverable_layout(nfail)
        call recoverable_output(nfail)
        print "(a,i0)", "typesetting core failures: ", nfail
    end subroutine typeset_core_check

    subroutine check(ok, message, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: message
        integer, intent(inout) :: nfail
        if (ok) return
        print "(a)", "  FAIL "//message
        nfail = nfail + 1
    end subroutine check

    subroutine begin_test(state)
        type(typeset_context_t), intent(inout) :: state
        type(status_t) :: status
        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, 240.0_dp, 160.0_dp, 12.0_dp, 12.0_dp, 12.0_dp, 12.0_dp, numbers=.false., status=status)
        call require_ok(status)
        call ts_set_font(state, 11.0_dp, status=status)
        call require_ok(status)
        call ts_begin_par(state, ALIGN_LEFT, 0.0_dp, status=status)
        call require_ok(status)
        call ts_word(state, "First", FACE_REGULAR, 11.0_dp, status=status)
        call require_ok(status)
    end subroutine begin_test

    subroutine end_test(state, document)
        type(typeset_context_t), intent(inout) :: state
        type(paged_document_t), intent(out) :: document
        type(status_t) :: status
        call ts_space(state, FACE_REGULAR, 11.0_dp, status=status)
        call require_ok(status)
        call ts_word(state, "last.", FACE_REGULAR, 11.0_dp, status=status)
        call require_ok(status)
        call ts_finish(state, document, status=status)
        call require_ok(status)
    end subroutine end_test

    subroutine interleaved_layout(nfail)
        integer, intent(inout) :: nfail
        type(typeset_context_t) :: a, b
        type(layout_context_t) :: nested
        type(frame_t) :: annotation
        type(paged_document_t) :: actual, reference, other
        type(document_asset_t), allocatable :: before(:), after(:), expected(:)

        type(status_t) :: status
        call begin_test(a)
        call layout_fragment(nested, "Nested *text* and $\frac{x}{y}$.", 90.0_dp, annotation, 8.0_dp, status=status)
        call require_ok(status)
        call begin_test(b)
        call ts_math(b, "x^2", 16.0_dp, display=.true., status=status)
        call require_ok(status)
        call end_test(b, other)
        call end_test(a, actual)
        call export_document(actual, "svg", before, status=status)
        call require_ok(status)

        call begin_test(b)
        call end_test(b, reference)
        call export_document(reference, "svg", expected, status=status)
        call require_ok(status)
        call check(before(1)%bytes == expected(1)%bytes, "interleaved paragraph contexts", nfail)

        call ts_reset(a, status=status)
        call require_ok(status)
        call ts_reset(b, status=status)
        call require_ok(status)
        call layout_markdown(nested, "An unrelated document."//achar(10)//achar(10)//"$$ E=mc^2 $$", &
                             other, status=status)
        call require_ok(status)
        call export_document(actual, "svg", after, status=status)
        call require_ok(status)
        call check(before(1)%bytes == after(1)%bytes, "document outlives reused layout contexts", nfail)
    end subroutine interleaved_layout

    subroutine owned_frames(nfail)
        integer, intent(inout) :: nfail
        type(frame_t) :: child, parent
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: before(:), after(:)
        integer :: handle
        real(dp) :: matrix(6), w, h
        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
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
        source_text_value1 = parent%source_text(status=status)
        call require_ok(status)
        call check(index(source_text_value1, "OwnedOwned") > 0, "shared child instances retain text", nfail)
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
        type(typeset_context_t) :: state
        type(math_context_t) :: math
        type(frame_t) :: frame, formula
        type(glyphrun_t) :: run
        character(len=:), allocatable :: source
        real(dp) :: advance
        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
        character(len=:), allocatable :: source_text_value2
        source = "A"//achar(204)//achar(138)//achar(226)//achar(132)//achar(131)
        call text_layout(source, 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance, status=status)
        call require_ok(status)
        call check(run%n == 3, "normalization and Celsius expansion", nfail)
        if (run%n == 3) then
            call check(all(run%first(1:3) == [1, 4, 4]) .and. &
                       all(run%last(1:3) == [3, 6, 6]), "UTF-8 glyph cluster ranges", nfail)
        end if
        call check(run%text == source, "normalization preserves logical source", nfail)

        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, 200.0_dp, 100.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false., status=status)
        call require_ok(status)
        call ts_begin_par(state, ALIGN_LEFT, 0.0_dp, status=status)
        call require_ok(status)
        call ts_word(state, "one", FACE_REGULAR, 10.0_dp, color=[255, 0, 0], status=status)
        call require_ok(status)
        call ts_space(state, FACE_REGULAR, 10.0_dp, status=status)
        call require_ok(status)
        call ts_word(state, "two", FACE_BOLD, 10.0_dp, color=[0, 0, 255], status=status)
        call require_ok(status)
        call ts_space(state, FACE_REGULAR, 10.0_dp, status=status)
        call require_ok(status)
        call ts_word(state, "three", FACE_REGULAR, 10.0_dp, color=[255, 0, 0], status=status)
        call require_ok(status)
        call ts_finish_frame(state, frame, status=status)
        call require_ok(status)
        source_text_value1 = frame%source_text(status=status)
        call require_ok(status)
        call check(source_text_value1 == "one two three", "colours preserve source order and spaces", nfail)
        call math_frame("\frac{x}{y}", 12.0_dp, .true., formula, context=math, status=status)
        call require_ok(status)
        call math_frame("z^2", 9.0_dp, .false., frame, context=math, status=status)
        call require_ok(status)
        source_text_value2 = formula%source_text(status=status)
        call require_ok(status)
        call check(source_text_value2 == "\frac{x}{y}", "math frame retains its source independently", nfail)
    end subroutine logical_text

    subroutine recorded_source(nfail)
        integer, intent(inout) :: nfail
        type(recording_renderer_t) :: recorder
        type(frame_t) :: frame
        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
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
        source_text_value1 = frame%source_text(status=status)
        call require_ok(status)
        call check(source_text_value1 == "Plain.Cost $2 and $x^2$.", &
                   "recorded labels retain their source once without replacing cluster text", nfail)
    end subroutine recorded_source

    subroutine embedded_document(nfail)
        integer, intent(inout) :: nfail
        type(layout_context_t) :: report, annotation
        type(doc_t) :: tree
        type(frame_t) :: frame
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: before(:), after(:)
        integer :: node
        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
        call layout_fragment(annotation, "A plot annotation with $x^2$.", 120.0_dp, frame, status=status)
        call require_ok(status)
        call md_parse("Before.", tree, status=status)
        call require_ok(status)
        node = doc_add_frame(tree, 1, frame, status=status)
        call require_ok(status)
        call md_append("After.", tree, status=status)
        call require_ok(status)
        call doc_typeset(report, tree, document, status=status)
        call require_ok(status)
        call export_document(document, "svg", before, status=status)
        call require_ok(status)
        call doc_init(tree, status=status)
        call require_ok(status)
        call frame%init(1.0_dp, 1.0_dp, status=status)
        call require_ok(status)
        call export_document(document, "svg", after, status=status)
        call require_ok(status)
        call check(before(1)%bytes == after(1)%bytes, "embedded document owns source graphics", nfail)
        call document%page_frame(1, frame, status=status)
        call require_ok(status)
        source_text_value1 = frame%source_text(status=status)
        call require_ok(status)
        call check(index(source_text_value1, "A plot annotation") > 0, "embedded frame reaches finished page", nfail)
    end subroutine embedded_document

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
        real(dp), allocatable :: widths(:)
        real(dp) :: w, h
        integer :: pos(0), n

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
        call grid_widths([20.0_dp], [20.0_dp], 10.0_dp, 0.0_dp, widths, status)
        call check(status%code == ERROR_LAYOUT .and. .not. allocated(widths), &
                   "an unfittable grid returns no partial widths", nfail)
        call hyph_points("hyphenation", 2, 3, pos, n, status)
        call check(status%code == ERROR_ARGUMENT, "hyphenation reports a truncated output buffer", nfail)

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

    subroutine recoverable_layout(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: status
        type(layout_context_t) :: context
        type(typeset_context_t) :: engine
        type(report_t) :: report
        type(doc_t) :: tree
        type(paged_document_t) :: document
        type(frame_t) :: frame
        type(document_asset_t), allocatable :: assets(:)
        real(dp) :: values(1, 2)
        integer :: handle, first, second
        character(len=:), allocatable :: text

        call layout_markdown(context, "(duplicate)="//achar(10)//"# First"//achar(10)//achar(10)// &
                             "(duplicate)="//achar(10)//"# Second", document, status)
        call check(status%code == ERROR_LAYOUT, "duplicate labels propagate through layout", nfail)
        call layout_markdown(context, "A fresh document.", document, status)
        call require_ok(status)
        call check(document%page_count() == 1, "layout context is reusable after failure", nfail)
        call md_parse("First."//achar(10)//achar(10)//"Second.", tree, status)
        call require_ok(status)
        first = tree%nodes(1)%first
        second = tree%nodes(first)%next
        tree%nodes(second)%next = first
        tree%nodes(first)%next = 0
        tree%nodes(1)%first = second
        tree%nodes(1)%last = first
        call doc_typeset(context, tree, document, status)
        call require_ok(status)
        call document%page_frame(1, frame, status)
        call require_ok(status)
        text = frame%source_text(status)
        call require_ok(status)
        call check(index(text, "Second.") < index(text, "First."), "valid tree reordering is supported", nfail)
        tree%nodes(first)%next = second
        call doc_typeset(context, tree, document, status)
        call check(status%code == ERROR_ARGUMENT, "cyclic frontend input returns an error", nfail)
        call frame%init(10.0_dp, 100.0_dp, status=status)
        call require_ok(status)
        call ts_reset(engine, status)
        call require_ok(status)
        call ts_set_page(engine, 100.0_dp, 50.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, status=status)
        call require_ok(status)
        call ts_import_frame(engine, frame, handle, status)
        call require_ok(status)
        call ts_place_frame(engine, handle, interline=.false., status=status)
        call require_ok(status)
        call ts_finish(engine, document, status)
        call check(status%code == ERROR_LAYOUT, "oversized unbreakable content returns a layout error", nfail)

        values(1, :) = [1.0_dp, 2.0_dp]
        call report%include_table(values, columns=["wrong"], status=status)
        call check(status%code == ERROR_ARGUMENT, "report propagates invalid table columns", nfail)
        call report%include_table(values, columns=["A", "B"], caption="Valid table.", status=status)
        call require_ok(status)
        call report%layout(document, status)
        call require_ok(status)
        call document%page_frame(1, frame, status)
        call require_ok(status)
        text = frame%source_text(status)
        call require_ok(status)
        call check(index(text, "Table 1.") > 0, "failed inclusion does not consume a table number", nfail)
        call report%save("tests/out", status=status)
        call check(status%code == ERROR_IO .and. allocated(status%message), "file errors reach the explicit caller", nfail)
        call report%export("pdf", assets, status=status)
        call require_ok(status)
        call check(size(assets) == 1, "a failed save does not poison the report", nfail)
    end subroutine recoverable_layout

    subroutine recoverable_output(nfail)
        integer, intent(inout) :: nfail
        type(status_t) :: status
        type(layout_context_t) :: context
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: assets(:)
        type(png_renderer_t) :: png
        type(pdf_renderer_t) :: pdf
        character(len=:), allocatable :: bytes
        real(dp) :: zero, nan

        zero = 0.0_dp
        nan = zero/zero
        call layout_markdown(context, "Export errors.", document, status)
        call require_ok(status)
        call export_document(document, "unknown", assets, status=status)
        call check(status%code == ERROR_UNSUPPORTED .and. .not. allocated(assets), &
                   "unsupported export has an explicit error and no assets", nfail)
        call export_document(document, "png", assets, dpi=nan, status=status)
        call check(status%code == ERROR_ARGUMENT .and. .not. allocated(assets), &
                   "nonfinite dpi does not return partial assets", nfail)
        bytes = png%bytes(status)
        call check(status%code == ERROR_STATE, "bytes requires finished encoded output", nfail)
        call png%open_canvas(huge(1.0_dp), 1.0_dp, status=status)
        call check(status%code == ERROR_ARGUMENT .and. .not. png%is_open, &
                   "pixel size overflow is rejected before opening a canvas", nfail)
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

end module test_typeset_core
