! Owned frames and pages: recorded drawing that outlives its inputs, frames
! that keep the source text they were set from, and a plot captured as a
! frame.
module test_frames
    use fplotlib_style, only: dp
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY_MATRIX
    use fplotlib_document, only: document_asset_t, export_document
    use fplotlib_render, only: glyphrun_t, paint_t
    use fplotlib_text, only: text_layout
    use fplotlib_glyphs, only: FACE_REGULAR
    use fplotlib_mathtext, only: math_context_t, math_frame
    use fplotlib_artist, only: append_text, append_annotation, text_ascent, text_descent
    use fplotlib_state, only: ax, text_t, fig_suptitle_size, PT_PER_IN, SUPTITLE_Y, TITLE_PAD
    use fplotlib, only: figure, plot, clf, render_png, render_svg, title, suptitle, &
                        constrained_layout, tight_layout, xticks, xlabel, tick_params
    use fplotlib_draw, only: render_frame, title_gap, decor_top, xtick_label_width, &
                             tick_label_width
    implicit none
    private
    public :: frames_check

contains

    subroutine frames_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call owned_frames(nfail)
        call math_source(nfail)
        call recorded_source(nfail)
        call captured_plot(nfail)
        call negative_formulas(nfail)
        call svg_high_codepoint(nfail)
        call text_bbox_descenders(nfail)
        call suptitle_constrained_gap(nfail)
        call rotated_xtick_layout(nfail)
        call title_fixed_pad(nfail)
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

    ! A formula's frame keeps its own source, apart from others set with
    ! the same context.
    subroutine math_source(nfail)
        integer, intent(inout) :: nfail
        type(math_context_t) :: math
        type(frame_t) :: frame, formula
        character(len=:), allocatable :: source
        call math_frame("\frac{x}{y}", 12.0_dp, .true., formula, context=math)
        call math_frame("z^2", 9.0_dp, .false., frame, context=math)
        source = formula%source_text()
        call check(source == "\frac{x}{y}", "math frame retains its source independently", nfail)
    end subroutine math_source

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

    ! A formula narrower than nothing, of negative space alone, makes an
    ! empty frame rather than stopping.
    subroutine negative_formulas(nfail)
        integer, intent(inout) :: nfail
        type(frame_t) :: frame
        real(dp) :: w, h

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
    end subroutine negative_formulas

    ! Issue #69: SVG escaping must handle code points above U+1869F (6+ digits).
    subroutine svg_high_codepoint(nfail)
        integer, intent(inout) :: nfail
        character(len=*), parameter :: bbA = achar(240)//achar(157)//achar(148)//achar(184)
        character(len=:), allocatable :: svg
        call clf()
        call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
        call title("x "//bbA//" y")
        svg = render_svg()
        call check(index(svg, "&#120120;") > 0, &
                   "svg encodes U+1D538 as decimal reference &#120120;", nfail)
        call clf()
    end subroutine svg_high_codepoint

    ! Issue #70: text bounding box must enclose both ascenders and descenders
    ! across all vertical alignments (single-line and multi-line).
    subroutine text_bbox_descenders(nfail)
        integer, intent(inout) :: nfail
        real(dp), parameter :: fs = 20.0_dp, py = 100.0_dp
        real(dp) :: asc, desc, lh
        asc = text_ascent(fs)
        desc = text_descent(fs)
        lh = 1.2_dp*fs
        ! Use "A" (no descender ink) so ink_bounds(4) measures the box itself.
        call check_box("A", "baseline", py - asc, py + desc)
        call check_box("A", "center", py - 0.5_dp*(asc + desc), py + 0.5_dp*(asc + desc))
        call check_box("A", "top", py, py + asc + desc)
        call check_box("A", "bottom", py - (asc + desc), py)
        call check_box("A"//achar(10)//"B", "bottom", py - lh - (asc + desc), py)
    contains
        subroutine check_box(str, va, want_top, want_bot)
            character(len=*), intent(in) :: str, va
            real(dp), intent(in) :: want_top, want_bot
            type(recording_renderer_t) :: rec
            type(frame_t) :: frame
            type(text_t) :: t
            real(dp) :: bounds(4)
            logical :: ink
            t%s = str
            t%fontsize = fs
            t%va = va
            t%has_box = .true.
            t%box_fc = "#f5deb3"
            t%box_ec = ""
            t%box_pad = 0.0_dp
            t%box_style = "square"
            call rec%open_canvas(200.0_dp, 200.0_dp)
            call append_annotation(rec, t, 40.0_dp, py)
            call rec%close_canvas()
            call rec%take(frame)
            call frame%ink_bounds(bounds, ink)
            call check(ink .and. abs(bounds(2) - want_top) < 1.0e-5_dp .and. &
                       abs(bounds(4) - want_bot) < 1.0e-5_dp, &
                       "text bbox encloses ascent and descent for va="//trim(va), nfail)
        end subroutine check_box
    end subroutine text_bbox_descenders

    ! Issue #71: suptitle must leave a positive gap above the axes title under
    ! constrained_layout and tight_layout.
    subroutine suptitle_constrained_gap(nfail)
        integer, intent(inout) :: nfail
        real(dp) :: H, sup_bot, ax_t, title_top
        character(len=:), allocatable :: svg

        call clf()
        call figure(figsize=[6.4_dp, 4.8_dp])
        call constrained_layout(.true.)
        call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
        call title("Axes title gjpqy")
        call suptitle("Figure suptitle gjpqy")
        svg = render_svg()
        H = 4.8_dp*PT_PER_IN
        sup_bot = (1.0_dp - SUPTITLE_Y)*H + text_ascent(fig_suptitle_size) &
                  + text_descent(fig_suptitle_size)
        ax_t = (1.0_dp - ax(1)%top)*H
        title_top = ax_t - title_gap(ax(1)) - text_ascent(ax(1)%title_size)
        call check(len(svg) > 0 .and. title_top > sup_bot + 1.0_dp, &
                   "constrained_layout keeps suptitle clear of axes title", nfail)

        call clf()
        call figure(figsize=[4.0_dp, 10.0_dp])
        call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
        call title("Axes title gjpqy")
        call suptitle("Figure suptitle gjpqy")
        call tight_layout()
        H = 10.0_dp*PT_PER_IN
        sup_bot = (1.0_dp - SUPTITLE_Y)*H + text_ascent(fig_suptitle_size) &
                  + text_descent(fig_suptitle_size)
        ax_t = (1.0_dp - ax(1)%top)*H
        title_top = ax_t - title_gap(ax(1)) - text_ascent(ax(1)%title_size)
        call check(title_top > sup_bot + 1.0_dp, &
                   "tight_layout keeps suptitle clear of axes title on tall figure", nfail)
        call clf()
    end subroutine suptitle_constrained_gap

    ! Issue #72: rotated x tick labels must reserve bottom margin from x tick
    ! widths, not y tick widths.
    subroutine rotated_xtick_layout(nfail)
        integer, intent(inout) :: nfail
        real(dp) :: H, xw, yw, bot_pt
        character(len=:), allocatable :: svg

        call clf()
        call figure(figsize=[6.4_dp, 4.8_dp])
        call constrained_layout(.true.)
        call plot([0.0_dp, 1.0_dp, 2.0_dp], [0.0_dp, 5.0_dp, 2.0_dp])
        call xticks([0.0_dp, 1.0_dp, 2.0_dp], [character(len=24) :: &
                    "2026-01-01 00:00 UTC", "2026-01-02 00:00 UTC", &
                    "2026-01-03 00:00 UTC"])
        call tick_params(axis="x", rotation=90.0_dp)
        call xlabel("date")
        svg = render_svg()
        H = 4.8_dp*PT_PER_IN
        xw = xtick_label_width(ax(1))
        yw = tick_label_width(ax(1))
        bot_pt = ax(1)%bottom*H
        call check(len(svg) > 0 .and. xw > 5.0_dp*yw .and. bot_pt > xw, &
                   "rotated x ticks reserve bottom margin from x tick width", nfail)
        call clf()
    end subroutine rotated_xtick_layout

    ! Issue #76: axes title pad is matplotlib's fixed 6 pt, not 0.5*fontsize.
    subroutine title_fixed_pad(nfail)
        integer, intent(inout) :: nfail
        call clf()
        call figure(figsize=[4.0_dp, 4.0_dp])
        call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
        call title("Title", fontsize=36.0_dp)
        call check(abs(title_gap(ax(1)) - TITLE_PAD) < 1.0e-9_dp .and. &
                   abs(decor_top(ax(1)) - (TITLE_PAD + text_ascent(36.0_dp))) < 1.0e-9_dp, &
                   "large title uses fixed 6 pt pad", nfail)
        call clf()
    end subroutine title_fixed_pad

end module test_frames
