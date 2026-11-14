module test_typeset_core
    use fplotlib_style, only: dp
    use fplotlib_typeset
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY
    use fplotlib_docclass, only: layout_context_t, layout_fragment, layout_markdown, doc_typeset
    use fplotlib_doctree, only: doc_t, doc_add_frame, doc_init
    use fplotlib_markdown, only: md_parse, md_append
    use fplotlib_document, only: document_asset_t, export_document
    use fplotlib_render, only: glyphrun_t, paint_t, clip_t
    use fplotlib_text, only: text_layout
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_BOLD
    use fplotlib_mathtext, only: math_context_t, math_frame
    use fplotlib_artist, only: append_text
    use fplotlib, only: figure, plot, clf, render_png
    use fplotlib_draw, only: render_frame
    implicit none
    private
    public :: typeset_core_check

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
        call ts_reset(state)
        call ts_set_page(state, 240.0_dp, 160.0_dp, 12.0_dp, 12.0_dp, 12.0_dp, 12.0_dp, numbers=.false.)
        call ts_set_font(state, 11.0_dp)
        call ts_begin_par(state, ALIGN_LEFT, 0.0_dp)
        call ts_word(state, "First", FACE_REGULAR, 11.0_dp)
    end subroutine begin_test

    subroutine end_test(state, document)
        type(typeset_context_t), intent(inout) :: state
        type(paged_document_t), intent(out) :: document
        call ts_space(state, FACE_REGULAR, 11.0_dp)
        call ts_word(state, "last.", FACE_REGULAR, 11.0_dp)
        call ts_finish(state, document)
    end subroutine end_test

    subroutine interleaved_layout(nfail)
        integer, intent(inout) :: nfail
        type(typeset_context_t) :: a, b
        type(layout_context_t) :: nested
        type(frame_t) :: annotation
        type(paged_document_t) :: actual, reference, other
        type(document_asset_t), allocatable :: before(:), after(:), expected(:)

        call begin_test(a)
        call layout_fragment(nested, "Nested *text* and $\frac{x}{y}$.", 90.0_dp, annotation, 8.0_dp)
        call begin_test(b)
        call ts_math(b, "x^2", 16.0_dp, display=.true.)
        call end_test(b, other)
        call end_test(a, actual)
        call export_document(actual, "svg", before)

        call begin_test(b)
        call end_test(b, reference)
        call export_document(reference, "svg", expected)
        call check(before(1)%bytes == expected(1)%bytes, "interleaved paragraph contexts", nfail)

        call ts_reset(a)
        call ts_reset(b)
        call layout_markdown(nested, "An unrelated document with $$ E=mc^2 $$.", other)
        call export_document(actual, "svg", after)
        call check(before(1)%bytes == after(1)%bytes, "document outlives reused layout contexts", nfail)
    end subroutine interleaved_layout

    subroutine owned_frames(nfail)
        integer, intent(inout) :: nfail
        type(frame_t) :: child, parent
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: before(:), after(:)
        integer :: handle
        real(dp) :: matrix(6), w, h
        block
            type(recording_renderer_t) :: recorder
            type(glyphrun_t) :: run
            type(paint_t) :: paint
            integer :: image(4, 2, 1)
            real(dp) :: advance
            paint%filled = .true.
            call text_layout("Owned", 12.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance)
            image(:, 1, 1) = [255, 0, 0, 255]
            image(:, 2, 1) = [0, 255, 0, 255]
            call recorder%open_canvas(80.0_dp, 30.0_dp)
            call recorder%draw_glyphs(0.0_dp, 12.0_dp, run, paint, 0.0_dp)
            call recorder%draw_image(0.0_dp, 16.0_dp, 20.0_dp, 10.0_dp, image, 2, 1, paint)
            call recorder%close_canvas()
            call recorder%take(child)
            run%text = "Changed"
            run%gid = 0
            image = 0
        end block

        call parent%init(160.0_dp, 60.0_dp)
        call parent%import_frame(child, handle)
        call parent%place(handle)
        matrix = IDENTITY
        matrix(5:6) = [80.0_dp, 30.0_dp]
        call parent%place(handle, matrix)
        call document%add_page(parent)
        call export_document(document, "svg", before)
        call check(index(parent%source_text(), "OwnedOwned") > 0, "shared child instances retain text", nfail)
        call child%init(1.0_dp, 1.0_dp)
        call parent%init(2.0_dp, 2.0_dp)
        call export_document(document, "svg", after)
        call check(before(1)%bytes == after(1)%bytes, "frames own inputs and imported children", nfail)
        call document%page_size(1, w, h)
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
        source = "A"//achar(204)//achar(138)//achar(226)//achar(132)//achar(131)
        call text_layout(source, 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance)
        call check(run%n == 3, "normalization and Celsius expansion", nfail)
        if (run%n == 3) then
            call check(all(run%first(1:3) == [1, 4, 4]) .and. &
                       all(run%last(1:3) == [3, 6, 6]), "UTF-8 glyph cluster ranges", nfail)
        end if
        call check(run%text == source, "normalization preserves logical source", nfail)

        call ts_reset(state)
        call ts_set_page(state, 200.0_dp, 100.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false.)
        call ts_begin_par(state, ALIGN_LEFT, 0.0_dp)
        call ts_word(state, "one", FACE_REGULAR, 10.0_dp, color=[255, 0, 0])
        call ts_space(state, FACE_REGULAR, 10.0_dp)
        call ts_word(state, "two", FACE_BOLD, 10.0_dp, color=[0, 0, 255])
        call ts_space(state, FACE_REGULAR, 10.0_dp)
        call ts_word(state, "three", FACE_REGULAR, 10.0_dp, color=[255, 0, 0])
        call ts_finish_frame(state, frame)
        call check(frame%source_text() == "one two three", "colours preserve source order and spaces", nfail)
        call math_frame("\frac{x}{y}", 12.0_dp, .true., formula, context=math)
        call math_frame("z^2", 9.0_dp, .false., frame, context=math)
        call check(formula%source_text() == "\frac{x}{y}", "math frame retains its source independently", nfail)
    end subroutine logical_text

    subroutine recorded_source(nfail)
        integer, intent(inout) :: nfail
        type(recording_renderer_t) :: recorder
        type(frame_t) :: frame
        call recorder%open_canvas(200.0_dp, 50.0_dp)
        call append_text(recorder, 0.0_dp, 12.0_dp, "Plain.", "left", 10.0_dp, "#000000")
        call append_text(recorder, 0.0_dp, 26.0_dp, "Cost \$2 and $x^2$.", "left", 10.0_dp, "#000000")
        call recorder%close_canvas()
        call recorder%take(frame)
        call check(frame%source_text() == "Plain.Cost $2 and $x^2$.", &
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
        call layout_fragment(annotation, "A plot annotation with $x^2$.", 120.0_dp, frame)
        call md_parse("Before.", tree)
        node = doc_add_frame(tree, 1, frame)
        call md_append("After.", tree)
        call doc_typeset(report, tree, document)
        call export_document(document, "svg", before)
        call doc_init(tree)
        call frame%init(1.0_dp, 1.0_dp)
        call export_document(document, "svg", after)
        call check(before(1)%bytes == after(1)%bytes, "embedded document owns source graphics", nfail)
        call document%page_frame(1, frame)
        call check(index(frame%source_text(), "A plot annotation") > 0, "embedded frame reaches finished page", nfail)
    end subroutine embedded_document

    subroutine captured_plot(nfail)
        integer, intent(inout) :: nfail
        type(frame_t) :: chart
        type(paged_document_t) :: document
        type(document_asset_t), allocatable :: assets(:)
        character(len=:), allocatable :: direct
        call figure(figsize=[2.0_dp, 1.5_dp], dpi=72.0_dp)
        call plot([0.0_dp, 1.0_dp, 2.0_dp], [0.0_dp, 1.0_dp, 0.0_dp])
        direct = render_png()
        call render_frame(chart)
        call clf()
        call document%add_page(chart)
        call export_document(document, "png", assets, dpi=72.0_dp)
        call check(direct == assets(1)%bytes, "captured vector plot replays after clf", nfail)
    end subroutine captured_plot

end module test_typeset_core
