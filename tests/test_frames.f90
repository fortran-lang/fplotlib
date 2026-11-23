! Owned frames and pages: recorded drawing that outlives its inputs, glyph
! runs that keep the source text they were set from, and a plot captured as
! a frame.
module test_frames
    use fplotlib_style, only: dp
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY_MATRIX
    use fplotlib_document, only: document_asset_t, export_document
    use fplotlib_render, only: glyphrun_t, paint_t
    use fplotlib_text, only: text_layout
    use fplotlib_glyphs, only: FACE_REGULAR
    use fplotlib_mathtext, only: math_context_t, math_frame
    use fplotlib_artist, only: append_text
    use fplotlib, only: figure, plot, clf, render_png
    use fplotlib_draw, only: render_frame
    implicit none
    private
    public :: frames_check

contains

    subroutine frames_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call owned_frames(nfail)
        call logical_text(nfail)
        call recorded_source(nfail)
        call captured_plot(nfail)
        call bare_runs_and_formulas(nfail)
        print "(a,i0)", "owned frames: failures = ", nfail
    end subroutine frames_check

    ! A glyph run built by hand without each glyph's font and source,
    ! which the renderer contract takes as optional, can still be added to
    ! by text_layout; and a formula narrower than nothing, of negative
    ! space alone, makes an empty frame rather than stopping.
    subroutine bare_runs_and_formulas(nfail)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run
        type(frame_t) :: frame
        real(dp) :: advance, w, h

        allocate (run%gid(1), run%x(1), run%y(1), run%size(1))
        run%gid = 1
        run%x = 0.0_dp
        run%y = 0.0_dp
        run%size = 10.0_dp
        run%n = 1
        call text_layout("BC", 10.0_dp, FACE_REGULAR, 5.0_dp, 0.0_dp, run, advance)
        call check(run%n == 3, "text_layout adds to a run without fonts or source ranges", nfail)
        if (run%n == 3) then
            call check(run%first(1) == 0 .and. run%last(1) == 0 .and. &
                       all(run%first(2:3) == [1, 2]), "the hand-built glyph keeps no source", nfail)
        end if
        call math_frame("x\!\!\!\!\!\!\!", 10.0_dp, .false., frame)
        call frame%metrics(w, h)
        call check(w == 0.0_dp, "a formula of negative width makes a frame of no width", nfail)
        call math_frame("\!", 10.0_dp, .false., frame)
        call frame%metrics(w, h)
        call check(w == 0.0_dp .and. h >= 0.0_dp, "negative space alone makes an empty frame", nfail)
        ! Rules narrower than nothing, which a label draws, are drawn too:
        ! each of these frames holds ink, its rule if nothing else.
        call rule_inked("\frac{\!}{\!}", .false.)
        call rule_inked("\cfrac{\!}{\!}", .true.)
        call rule_inked("\sqrt{\!\!\!\!\!\!}", .false.)
        call rule_inked("\overline{\!\!\!\!}", .false.)
        call rule_inked("\underline{\!\!\!\!}", .false.)

        ! A run built by hand with gid longer than x, y and size grows by
        ! its shortest array, not by gid.
        deallocate (run%gid, run%x, run%y, run%size, run%font, run%first, run%last)
        allocate (run%gid(8), run%x(1), run%y(1), run%size(1))
        run%gid = 1
        run%x = 0.0_dp
        run%y = 0.0_dp
        run%size = 10.0_dp
        run%n = 1
        call text_layout("BCDEFG", 10.0_dp, FACE_REGULAR, 5.0_dp, 0.0_dp, run, advance)
        call check(run%n == 7 .and. size(run%x) >= 7 .and. size(run%size) >= 7, &
                   "a run with arrays of different lengths grows by the shortest", nfail)
    contains
        subroutine rule_inked(tex, display)
            character(len=*), intent(in) :: tex
            logical, intent(in) :: display
            type(frame_t) :: f
            real(dp) :: bounds(4)
            logical :: ink
            call math_frame(tex, 10.0_dp, display, f)
            call f%ink_bounds(bounds, ink)
            call check(ink .and. bounds(3) > bounds(1) .and. bounds(4) > bounds(2), &
                       "the frame of "//tex//" holds its rules", nfail)
        end subroutine rule_inked
    end subroutine bare_runs_and_formulas

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
        character(len=:), allocatable :: source
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
        matrix = IDENTITY_MATRIX
        matrix(5:6) = [80.0_dp, 30.0_dp]
        call parent%place(handle, matrix)
        call document%add_page(parent)
        call export_document(document, "svg", before)
        source = parent%source_text()
        call check(index(source, "OwnedOwned") > 0, "shared child instances retain text", nfail)
        call child%init(1.0_dp, 1.0_dp)
        call parent%init(2.0_dp, 2.0_dp)
        call export_document(document, "svg", after)
        call check(before(1)%bytes == after(1)%bytes, "frames own inputs and imported children", nfail)
        call document%page_size(1, w, h)
        call check(w == 160.0_dp .and. h == 60.0_dp, "page keeps original frame dimensions", nfail)
    end subroutine owned_frames

    subroutine logical_text(nfail)
        integer, intent(inout) :: nfail
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

        call math_frame("\frac{x}{y}", 12.0_dp, .true., formula, context=math)
        call math_frame("z^2", 9.0_dp, .false., frame, context=math)
        source = formula%source_text()
        call check(source == "\frac{x}{y}", "math frame retains its source independently", nfail)
    end subroutine logical_text

    subroutine recorded_source(nfail)
        integer, intent(inout) :: nfail
        type(recording_renderer_t) :: recorder
        type(frame_t) :: frame
        character(len=:), allocatable :: source
        call recorder%open_canvas(200.0_dp, 50.0_dp)
        call append_text(recorder, 0.0_dp, 12.0_dp, "Plain.", "left", 10.0_dp, "#000000")
        call append_text(recorder, 0.0_dp, 26.0_dp, "Cost \$2 and $x^2$.", "left", 10.0_dp, "#000000")
        call recorder%close_canvas()
        call recorder%take(frame)
        source = frame%source_text()
        call check(source == "Plain.Cost $2 and $x^2$.", &
                   "recorded labels retain their source once without replacing cluster text", nfail)
    end subroutine recorded_source

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

end module test_frames
