! Advanced composition with explicit frames
! =========================================
!
! The plot, its paragraph annotation and the report share the same finished
! frame representation. No SVG or PDF is imported between layout stages.
! The small Markdown frontend is unchanged: Fortran inserts the plot into
! the document tree, then appends the caption and discussion as Markdown.
!
! The annotation has its own layout context. Clearing the plotting state
! and reusing that context cannot invalidate the captured frames or report.
program plot_frame_composition
    use fplotlib, only: dp, figure, plot, title, xlabel, ylabel, grid, ylim, clf, &
                        render_frame, frame_t, paged_document_t, layout_context_t, &
                        layout_fragment, save_document
    use fplotlib_doctree, only: doc_t, doc_add, doc_add_frame, DOC_DIV
    use fplotlib_markdown, only: md_parse, md_append
    use fplotlib_docclass, only: doc_typeset
    use fplotlib_scene, only: recording_renderer_t, IDENTITY
    use fplotlib_render, only: paint_t, clip_t
    implicit none
    character, parameter :: NL = achar(10)
    type(layout_context_t) :: report_layout, annotation_layout
    type(paged_document_t) :: document
    type(doc_t) :: tree
    type(frame_t) :: chart, note, panel, composed
    type(recording_renderer_t) :: recorder
    type(paint_t) :: border
    type(clip_t) :: clip
    real(dp) :: t(401), y(401), w, h, nw, nh, matrix(6)
    integer :: i, handle, group, node

    do i = 1, size(t)
        t(i) = 20.0_dp*real(i - 1, dp)/real(size(t) - 1, dp)
        y(i) = exp(-0.15_dp*t(i))*cos(2.0_dp*t(i))
    end do
    call figure(figsize=[6.0_dp, 3.8_dp])
    call plot(t, y, "b-")
    call title("Damped oscillator")
    call xlabel("Time $t$")
    call ylabel("Displacement $x(t)$")
    call ylim(-1.1_dp, 1.1_dp)
    call grid(.true.)
    call render_frame(chart, bbox_inches="tight", pad_inches=0.1_dp)
    call chart%metrics(w, h)

    call layout_fragment(annotation_layout, &
        "**Exponential envelope**"//NL//NL// &
        "The oscillations decay while the phase advances uniformly."//NL// &
        "$$ x(t)=e^{-0.15t}\cos(2t) $$", &
        145.0_dp, note, font_size=8.5_dp)
    call note%metrics(nw, nh)
    call recorder%open_canvas(nw + 16.0_dp, nh + 16.0_dp, bg_rgb=[255, 255, 255])
    border%stroked = .true.
    border%stroke_rgb = [170, 180, 195]
    border%line_width = 0.6_dp
    call recorder%draw_rect(0.5_dp, 0.5_dp, nw + 15.0_dp, nh + 15.0_dp, border, radius=4.0_dp)
    matrix = IDENTITY
    matrix(5:6) = [8.0_dp, 8.0_dp]
    call recorder%begin_frame(matrix, clip)
    call note%draw(recorder)
    call recorder%end_frame()
    call recorder%close_canvas()
    call recorder%take(panel)

    call composed%init(w, h)
    call composed%add_frame(chart, handle)
    call composed%place(handle)
    call composed%add_frame(panel, handle)
    matrix = IDENTITY
    matrix(5:6) = [w - nw - 54.0_dp, 38.0_dp]
    clip = clip_t(.true., 0.0_dp, 0.0_dp, nw + 16.0_dp, nh + 16.0_dp)
    call composed%place(handle, matrix, clip)
    call clf()

    call md_parse("---"//NL// &
        "title: A Report Directly from Fortran"//NL// &
        "author: Numerical methods group"//NL// &
        "paper: letter"//NL// &
        "margin: 0.7in"//NL// &
        "---"//NL//NL// &
        "# A damped oscillator"//NL//NL// &
        "The computed trajectory below is a vector plot, not a screenshot. " // &
        "Its annotation is a separately typeset paragraph and equation. " // &
        "All three levels use the same fonts and rendering backends.", tree)
    group = doc_add(tree, 1, DOC_DIV)
    tree%nodes(group)%attr = ".center"
    node = doc_add_frame(tree, group, composed)
    call md_append("\smallskip"//NL//NL// &
                   "*Figure 1.* Oscillatory motion with exponential damping.", tree, group)
    call md_append("## Interpretation"//NL//NL// &
        "For $x(t)=e^{-\alpha t}\cos(\omega t)$, the amplitude halves after"//NL// &
        "$$ t_{1/2}=\frac{\log 2}{\alpha}\approx 4.62. $$"//NL//NL// &
        "The simulation produces the numbers; the plotting layer produces a frame; " // &
        "the report layout places that frame on a page. " // &
        "The finished document owns its contents and can be exported repeatedly.", tree)
    call doc_typeset(report_layout, tree, document)

    call layout_fragment(annotation_layout, "The annotation workspace is reusable.", 100.0_dp, note)
    call save_document(document, "frame_composition.svg")
    call save_document(document, "frame_composition.pdf")
end program plot_frame_composition
