! Layout of the report frontend's resolved content. Syntax and semantic
! preparation live outside this module; only typed settings and nodes enter
! the paragraph, page and frame algorithms below.
module fplotlib_docclass
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_BOLD, FACE_ITALIC, face_xheight, &
                               face_capheight
    use fplotlib_text, only: text_width
    use fplotlib_doctree
    use fplotlib_doctemplate
    use fplotlib_docresolve, only: resolve_document, resolved_document_t, document_settings_t, &
                                   resolved_node_t, resolved_part_t
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY
    use fplotlib_render, only: clip_t
    use fplotlib_grid, only: grid_widths, grid_row
    use fplotlib_typeset
    implicit none
    private

    public :: layout_context_t

    public :: doc_typeset, doc_fragment

    character, parameter :: NL = achar(10)
    character(len=2), parameter :: NBSP = achar(194)//achar(160)

    ! The style of inline text.
    type :: style_t
        logical :: bold = .false., italic = .false.
        real(dp) :: size = 10.0_dp
        integer :: color(3) = 0
    end type style_t

    ! Where blocks are being set: their margins, alignment, size and
    ! colour, and how deep in lists they are.
    type :: ctx_t
        real(dp) :: left = 0.0_dp, right = 0.0_dp
        integer :: align = ALIGN_JUSTIFY
        real(dp) :: size = 10.0_dp
        integer :: color(3) = 0
        logical :: bold = .false., italic = .false.
        integer :: depth = 0
        ! How deep in bullet lists and in numbered lists, which LaTeX
        ! counts apart for their labels.
        integer :: ilev = 0, elev = 0
        logical :: inlist = .false.
        ! Paragraphs are indented (at the top level of the document).
        logical :: indent = .true.
    end type ctx_t

    ! The document's settings.
    integer, parameter :: LINK_COL(3) = [26, 95, 180], CODE_COL(3) = [80, 80, 80]

    type :: layout_context_t
        private
        type(typeset_context_t) :: engine
        integer :: graphics_base = 0
        type(document_settings_t) :: settings
        type(template_t) :: template
        type(resolved_node_t), allocatable :: node_info(:)
        type(resolved_part_t), allocatable :: parts(:)

        ! Paragraph indentation and a pending list-item label.
        logical :: NOINDENT = .false.
        character(len=:), allocatable :: PENDING_LABEL
        real(dp) :: LABEL_SEP = 5.0_dp

        ! Inline text being set: the word so far, and a space before it in the
        ! type the space was in.
        character(len=:), allocatable :: W
        logical :: SPACE = .false.
        integer :: SP_FACE = FACE_REGULAR
        real(dp) :: SP_SIZE = 10.0_dp
    end type layout_context_t

contains

    ! ------------------------------------------------------------------
    ! The document.
    ! ------------------------------------------------------------------

    ! Set doc into fplotlib_typeset's pages.
    subroutine doc_typeset(state, doc, document, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(paged_document_t), intent(out) :: document
        type(ctx_t) :: ctx
        type(resolved_document_t) :: resolved
        type(status_t), intent(out) :: status
        call resolve_document(doc, resolved, status)
        if (.not. status%ok()) return
        call prepare_layout(state, resolved, status)
        if (.not. status%ok()) return
        ctx%size = state%settings%BASE
        ctx%color = state%settings%TEXT_COL
        ctx%align = state%settings%DOC_ALIGN
        call template_document(state, resolved%content, ctx, status)
        if (.not. status%ok()) return
        call ts_finish(state%engine, document, status=status)
        if (.not. status%ok()) return
    end subroutine doc_typeset

    subroutine doc_fragment(state, doc, width, frame, font_size, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        real(dp), intent(in) :: width
        type(frame_t), intent(out) :: frame
        real(dp), intent(in), optional :: font_size
        type(status_t), intent(out) :: status
        type(resolved_document_t) :: resolved
        type(ctx_t) :: ctx
        integer :: i
        if (width <= 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "doc_fragment: width must be positive")
            return
        end if
        call doc_validate(doc, status)
        if (.not. status%ok()) return
        if (doc%nmeta > 0) then
            call status%set(ERROR_UNSUPPORTED, "doc_fragment: document metadata requires a report")
            return
        end if
        do i = 1, doc%n
            if (doc%nodes(i)%kind == DOC_PART .or. doc%nodes(i)%break_before /= 0) then
                call status%set(ERROR_UNSUPPORTED, "doc_fragment: document parts and page breaks require a report")
                return
            end if
        end do
        call resolve_document(doc, resolved, status)
        if (.not. status%ok()) return
        if (present(font_size)) resolved%settings%BASE = font_size
        if (resolved%settings%BASE <= 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "doc_fragment: font size must be positive")
            return
        end if
        resolved%settings%page_width = width
        resolved%settings%page_height = 1.0e6_dp
        resolved%settings%margins = 0.0_dp
        resolved%settings%page_numbers = .false.
        resolved%settings%PARINDENT = 0.0_dp
        call prepare_layout(state, resolved, status)
        if (.not. status%ok()) return
        ctx%size = state%settings%BASE
        ctx%indent = .false.
        call set_blocks(state, resolved%content, 1, ctx, status)
        if (.not. status%ok()) return
        call ts_finish_frame(state%engine, frame, status)
    end subroutine doc_fragment

    subroutine reset_workspace(state)
        type(layout_context_t), intent(inout) :: state
        state%NOINDENT = .false.
        state%graphics_base = 0
        state%PENDING_LABEL = ""
        state%W = ""
        state%SPACE = .false.
    end subroutine reset_workspace

    subroutine prepare_layout(state, resolved, status)
        type(layout_context_t), intent(inout) :: state
        type(resolved_document_t), intent(in) :: resolved
        type(status_t), intent(out) :: status
        call ts_reset(state%engine, status)
        if (.not. status%ok()) return
        call reset_workspace(state)
        state%settings = resolved%settings
        state%template = resolved%template
        if (allocated(state%node_info)) deallocate (state%node_info)
        if (allocated(state%parts)) deallocate (state%parts)
        allocate (state%node_info(size(resolved%nodes)), state%parts(size(resolved%parts)))
        state%node_info = resolved%nodes
        state%parts = resolved%parts
        if (resolved%content%ngraphics > 0) then
            call ts_import_frame(state%engine, resolved%content%graphics, state%graphics_base, status)
            if (.not. status%ok()) return
        end if
        call ts_set_page(state%engine, state%settings%page_width, state%settings%page_height, &
                         state%settings%margins(1), state%settings%margins(2), state%settings%margins(3), &
                         state%settings%margins(4), state%settings%page_numbers, state%settings%BOOK, &
                         state%settings%BOOK, status)
        if (.not. status%ok()) return
        call ts_set_font(state%engine, state%settings%BASE, state%settings%LEAD*state%settings%BASE, status)
        if (.not. status%ok()) return
        call ts_set_parskip(state%engine, state%settings%PARSKIP_G)
        call ts_set_colors(state%engine, state%settings%TEXT_COL, state%settings%PAGE_COL, status)
    end subroutine prepare_layout

    recursive subroutine template_document(state, doc, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(ctx_t), intent(in) :: ctx
        type(status_t), intent(out) :: status
        type(style_t) :: title_style
        type(ctx_t) :: title_context
        integer :: i, part
        do i = 1, size(state%template%steps)
            part = state%template%steps(i)%part
            select case (state%template%steps(i)%kind)
            case (STEP_BODY)
                call set_blocks(state, doc, 1, ctx, status)
            case (STEP_PART)
                call named_part(state, doc, part, ctx, status)
            case (STEP_TITLE_BLOCK)
                call title_block(state, doc, ctx, part, status)
            case (STEP_TITLE)
                if (state%settings%TITLE == 0) cycle
                title_context = part_context(state%template%title, ctx)
                title_style = base_style(title_context)
                call ts_begin_par(state%engine, title_context%align, 0.0_dp, size=title_style%size, &
                                  leading=state%settings%LEAD*title_style%size, status=status)
                if (.not. status%ok()) return
                call set_inlines(state, doc, state%settings%TITLE, title_style, status)
                if (.not. status%ok()) return
                call ts_end_par(state%engine, status)
            case (STEP_FILL)
                call ts_vkeep(state%engine, ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0), status)
            end select
            if (.not. status%ok()) return
        end do
    end subroutine template_document

    pure function part_context(style, ctx) result(sub)
        type(part_style_t), intent(in) :: style
        type(ctx_t), intent(in) :: ctx
        type(ctx_t) :: sub
        sub = ctx
        sub%size = style%font_scale*ctx%size
        sub%bold = sub%bold .or. style%bold
        sub%italic = sub%italic .or. style%italic
        if (style%align >= 0) sub%align = style%align
        if (style%indent >= 0) sub%indent = style%indent == 1
        if (style%has_color) sub%color = style%color
    end function part_context

    recursive subroutine named_part(state, doc, part, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: part
        type(ctx_t), intent(in) :: ctx
        type(status_t), intent(out) :: status
        type(ctx_t) :: sub
        type(part_style_t) :: style
        integer :: i, node
        real(dp) :: before, after
        if (size(state%parts(part)%nodes) == 0) return
        style = state%template%parts(part)%style
        sub = part_context(style, ctx)
        before = style%before_fixed + style%before_base*state%settings%BASE
        after = style%after_fixed + style%after_base*state%settings%BASE
        if (before > 0.0_dp) then
            call ts_vskip(state%engine, ts_glue_t(before, 0.0_dp, 0.0_dp, 0, 0), status)
            if (.not. status%ok()) return
        end if
        do i = 1, size(state%parts(part)%nodes)
            node = state%parts(part)%nodes(i)
            call block_page_break(state, doc%nodes(node)%break_before, status)
            if (.not. status%ok()) return
            call set_blocks(state, doc, node, sub, status)
            if (.not. status%ok()) return
        end do
        if (after > 0.0_dp) call ts_vskip(state%engine, ts_glue_t(after, 0.0_dp, 0.0_dp, 0, 0), status)
    end subroutine named_part

    ! LaTeX's \maketitle and abstract, for the article class.
    subroutine title_block(state, doc, ctx, abstract_part, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(ctx_t), intent(in) :: ctx
        integer, intent(in) :: abstract_part
        type(style_t) :: st
        integer :: i
        type(status_t), intent(out) :: status
        if (state%settings%TITLE == 0) then
            call abstract_block(state, doc, ctx, abstract_part, status)
            return
        end if
        st = base_style(ctx)
        call ts_vkeep(state%engine, ts_glue_t(2.0_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
        st%size = 1.728_dp*state%settings%BASE
        call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, leading=22.0_dp*state%settings%BASE/10.0_dp, &
                          skip=.false., status=status)
        if (.not. status%ok()) return
        call set_inlines(state, doc, state%settings%TITLE, st, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        if (state%settings%SUBTITLE > 0) then
            st%size = 1.2_dp*state%settings%BASE
            call ts_vskip(state%engine, ts_glue_t(0.5_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
            call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*state%settings%BASE/10.0_dp, skip=.false., status=status)
            if (.not. status%ok()) return
            call set_inlines(state, doc, state%settings%SUBTITLE, st, status=status)
            if (.not. status%ok()) return
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
        end if
        st%size = 1.2_dp*state%settings%BASE
        if (state%settings%NAUTHOR > 0) then
            call ts_vskip(state%engine, ts_glue_t(1.5_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
            do i = 1, state%settings%NAUTHOR
                call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                                  leading=14.0_dp*state%settings%BASE/10.0_dp, skip=.false., status=status)
                if (.not. status%ok()) return
                call set_inlines(state, doc, state%settings%AUTHORS(i), st, status=status)
                if (.not. status%ok()) return
                call ts_end_par(state%engine, status=status)
                if (.not. status%ok()) return
            end do
        end if
        if (state%settings%DATE > 0) then
            call ts_vskip(state%engine, ts_glue_t(state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
            call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*state%settings%BASE/10.0_dp, skip=.false., status=status)
            if (.not. status%ok()) return
            call set_inlines(state, doc, state%settings%DATE, st, status=status)
            if (.not. status%ok()) return
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
        end if
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
        call ts_vskip(state%engine, ts_glue_t(1.5_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        call abstract_block(state, doc, ctx, abstract_part, status)
        if (.not. status%ok()) return
        state%NOINDENT = .false.
    end subroutine title_block

    subroutine abstract_block(state, doc, ctx, part, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(ctx_t), intent(in) :: ctx
        integer, intent(in) :: part
        type(status_t), intent(out) :: status
        type(style_t) :: heading_style
        type(ctx_t) :: sub
        real(dp) :: saved_indent, saved_leading
        if (state%settings%ABSTRACT == 0) return
        heading_style = base_style(ctx)
        heading_style%size = 0.9_dp*state%settings%BASE
        heading_style%bold = .true.
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status)
        if (.not. status%ok()) return
        call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=heading_style%size, &
                          leading=1.1_dp*state%settings%BASE, skip=.false., status=status)
        if (.not. status%ok()) return
        call set_words(state, "Abstract", heading_style, status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status)
        if (.not. status%ok()) return
        call ts_vskip(state%engine, ts_glue_t(0.05_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status)
        if (.not. status%ok()) return
        sub = ctx
        sub%size = 0.9_dp*state%settings%BASE
        sub%left = 2.5_dp*state%settings%BASE
        sub%right = sub%left
        sub%align = ALIGN_JUSTIFY
        sub%indent = .true.
        saved_indent = state%settings%PARINDENT
        saved_leading = state%settings%LEAD
        state%settings%PARINDENT = 1.5_dp*sub%size
        state%settings%LEAD = 11.0_dp/9.0_dp
        call named_part(state, doc, part, sub, status)
        state%settings%PARINDENT = saved_indent
        state%settings%LEAD = saved_leading
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status)
    end subroutine abstract_block

    ! ------------------------------------------------------------------
    ! Blocks.
    ! ------------------------------------------------------------------

    ! The blocks that are the children of node parent.
    recursive subroutine set_blocks(state, doc, parent, ctx, status, start)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(ctx_t), intent(in) :: ctx
        integer :: c
        character(len=:), allocatable :: tag
        type(status_t), intent(out) :: status
        integer, intent(in), optional :: start
        c = doc%nodes(parent)%first
        if (present(start)) c = start
        do while (c > 0)
            if (doc%nodes(c)%kind == DOC_PART) then
                c = doc%nodes(c)%next
                cycle
            end if
            call block_page_break(state, doc%nodes(c)%break_before, status)
            if (.not. status%ok()) return
            select case (doc%nodes(c)%kind)
            case (DOC_PARA)
                call paragraph(state, doc, c, ctx, status=status)
                if (.not. status%ok()) return
            case (DOC_HEADING)
                call heading(state, doc, c, ctx, status=status)
                if (.not. status%ok()) return
            case (DOC_CODE)
                call code_block(state, doc%nodes(c)%text, ctx, status=status)
                if (.not. status%ok()) return
            case (DOC_DIV)
                call set_blocks(state, doc, c, ctx, status=status)
                if (.not. status%ok()) return
                call ts_end_par(state%engine, status=status)
                if (.not. status%ok()) return
            case (DOC_QUOTE)
                call quote_block(state, doc, c, ctx, status=status)
                if (.not. status%ok()) return
            case (DOC_LIST)
                call list_block(state, doc, c, ctx, status=status)
                if (.not. status%ok()) return
            case (DOC_RULE)
                call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
                if (.not. status%ok()) return
                call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, left=ctx%left, right=ctx%right, status=status)
                if (.not. status%ok()) return
                call ts_end_par(state%engine, status=status)
                if (.not. status%ok()) return
                call ts_rule(state%engine, 0.5_dp*(ts_hsize(state%engine) - ctx%left - ctx%right), 0.5_dp, ctx%color, status=status)
                if (.not. status%ok()) return
                call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
                if (.not. status%ok()) return
            case (DOC_MATH)
                call ts_begin_par(state%engine, ctx%align, 0.0_dp, left=ctx%left, right=ctx%right, &
                                  size=ctx%size, skip=.false., status=status)
                if (.not. status%ok()) return
                tag = target_number(state, c)
                call ts_math(state%engine, doc%nodes(c)%text, ctx%size, ctx%color, &
                             display=.true., tag=tag, status=status)
                if (.not. status%ok()) return
                call ts_end_par(state%engine, status)
                if (.not. status%ok()) return
                state%NOINDENT = .true.
            case (DOC_FRAME)
                if (state%graphics_base == 0) then
                    call status%set(ERROR_ARGUMENT, "document: missing frame resources")
                    return
                end if
                call ts_place_frame(state%engine, state%graphics_base + doc%nodes(c)%num - 1, &
                                    left=ctx%left, right=ctx%right, &
                                    align=merge(ALIGN_CENTER, ctx%align, ctx%align == ALIGN_JUSTIFY), status=status)
                if (.not. status%ok()) return
            case (DOC_FIGURE)
                call figure_block(state, doc, c, ctx, status=status)
                if (.not. status%ok()) return
            case (DOC_TABLE)
                call table_block(state, doc, c, ctx, status=status)
                if (.not. status%ok()) return
            end select
            c = doc%nodes(c)%next
        end do
    end subroutine set_blocks

    subroutine block_page_break(state, mode, status)
        type(layout_context_t), intent(inout) :: state
        integer, intent(in) :: mode
        type(status_t), intent(out) :: status
        if (mode == 1) then
            call ts_page_break(state%engine, status)
        else if (mode == 2) then
            call ts_end_par(state%engine, status)
            if (.not. status%ok()) return
            call ts_addpenalty(state%engine, -10000, status)
        end if
    end subroutine block_page_break

    ! Captions get their own workspace, but share the resolved reference
    ! values. They cannot disturb a report that is being laid out.
    recursive subroutine caption_frame(state, doc, node, width, ctx, frame, status, prefix)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        real(dp), intent(in) :: width
        type(ctx_t), intent(in) :: ctx
        type(frame_t), intent(out) :: frame
        type(layout_context_t) :: nested
        type(ctx_t) :: sub
        type(status_t), intent(out) :: status
        character(len=*), intent(in), optional :: prefix
        integer :: first
        call ts_reset(nested%engine, status=status)
        if (.not. status%ok()) return
        call reset_workspace(nested)
        nested%settings = state%settings
        nested%settings%PARINDENT = 0.0_dp
        allocate (nested%node_info(size(state%node_info)))
        nested%node_info = state%node_info
        sub = ctx
        sub%left = 0.0_dp
        sub%right = 0.0_dp
        sub%indent = .false.
        sub%align = ALIGN_CENTER
        sub%size = 0.9_dp*ctx%size
        call ts_set_page(nested%engine, width, 1.0e6_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false., status=status)
        if (.not. status%ok()) return
        call ts_set_font(nested%engine, sub%size, nested%settings%LEAD*sub%size, status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(nested%engine, ts_glue_t())
        first = doc%nodes(node)%first
        if (present(prefix)) then
            if (len(prefix) > 0 .and. first > 0) then
                if (doc%nodes(first)%kind == DOC_PARA) then
                    call paragraph(nested, doc, first, sub, status, prefix)
                    if (.not. status%ok()) return
                    first = doc%nodes(first)%next
                end if
            end if
        end if
        call set_blocks(nested, doc, node, sub, status=status, start=first)
        if (.not. status%ok()) return
        call ts_finish_frame(nested%engine, frame, status=status)
        if (.not. status%ok()) return
    end subroutine caption_frame

    recursive subroutine figure_block(state, doc, node, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        type(frame_t) :: caption, frame
        type(recording_renderer_t) :: recorder
        type(clip_t) :: clip
        real(dp) :: w, h, width, scale_, cw, ch, gap, available, matrix(6), left
        integer :: graphic, cap, handle
        character(len=:), allocatable :: prefix
        type(status_t), intent(out) :: status
        graphic = doc%nodes(node)%first
        if (graphic == 0) then
            call status%set(ERROR_ARGUMENT, "document figure: missing graphics")
            return
        end if
        if (doc%nodes(graphic)%kind /= DOC_FRAME) then
            call status%set(ERROR_ARGUMENT, "document figure: expected a frame")
            return
        end if
        call doc%graphics%metrics(w, h, handle=doc%nodes(graphic)%num, status=status)
        if (.not. status%ok()) return
        if (w <= 0.0_dp .or. h <= 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "document figure: empty graphics")
            return
        end if
        available = ts_hsize(state%engine) - ctx%left - ctx%right
        width = min(w, available)
        if (doc%nodes(node)%width > 0) width = min(doc%nodes(node)%width, available)
        if (width <= 0.0_dp) then
            call status%set(ERROR_LAYOUT, "document figure: no horizontal space")
            return
        end if
        cap = doc%nodes(graphic)%next
        ch = 0.0_dp
        gap = 0.0_dp
        if (cap > 0) then
            prefix = target_number(state, node)
            if (len(prefix) > 0) prefix = "Figure "//prefix//"."
            call caption_frame(state, doc, cap, width, ctx, caption, status=status, prefix=prefix)
            if (.not. status%ok()) return
            call caption%metrics(cw, ch, status=status)
            if (.not. status%ok()) return
            gap = 0.5_dp*state%settings%BASE
        end if
        if (ch + gap >= ts_vsize(state%engine)) then
            call status%set(ERROR_LAYOUT, "document figure: caption exceeds page height")
            return
        end if
        scale_ = min(width/w, (ts_vsize(state%engine) - ch - gap)/h)
        left = 0.5_dp*(width - scale_*w)
        call recorder%open_canvas(width, scale_*h + gap + ch, status=status)
        if (.not. status%ok()) return
        matrix = [scale_, 0.0_dp, 0.0_dp, scale_, left, 0.0_dp]
        call recorder%begin_frame(matrix, clip, status=status)
        if (.not. status%ok()) return
        call doc%graphics%draw(recorder, doc%nodes(graphic)%num, status=status)
        if (.not. status%ok()) return
        call recorder%end_frame(status=status)
        if (.not. status%ok()) return
        if (cap > 0) then
            matrix = IDENTITY
            matrix(6) = scale_*h + gap
            call recorder%begin_frame(matrix, clip, status=status)
            if (.not. status%ok()) return
            call caption%draw(recorder, status=status)
            if (.not. status%ok()) return
            call recorder%end_frame(status=status)
            if (.not. status%ok()) return
        end if
        call recorder%close_canvas(status=status)
        if (.not. status%ok()) return
        call recorder%take(frame, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        call ts_import_frame(state%engine, frame, handle, status=status)
        if (.not. status%ok()) return
        call ts_place_frame(state%engine, handle, left=ctx%left, right=ctx%right, &
                            align=ALIGN_CENTER, interline=.false., status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        state%NOINDENT = .true.
    end subroutine figure_block

    ! Plain data cells are measured before choosing column widths, then
    ! paragraphs are laid out to those widths. The core packs rows and
    ! paginates them, reserving repeated headers on continuation pages.
    recursive subroutine table_block(state, doc, node, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        type(typeset_context_t) :: cell_state
        type(frame_t), allocatable :: cells(:)
        type(frame_t) :: row, caption
        real(dp), allocatable :: natural(:), minimum(:), widths(:)
        real(dp) :: available, fs, padding, nw, mw
        integer :: t, nc, nr, i, j, header, handle, align
        character(len=:), allocatable :: prefix
        type(status_t), intent(out) :: status
        t = doc%nodes(node)%num
        if (t < 1 .or. t > doc%ntables) then
            call status%set(ERROR_ARGUMENT, "document table: invalid table")
            return
        end if
        nc = size(doc%tables(t)%cells, 2)
        nr = size(doc%tables(t)%cells, 1)
        available = ts_hsize(state%engine) - ctx%left - ctx%right
        fs = 0.9_dp*ctx%size
        padding = 0.35_dp*fs
        allocate (natural(nc), minimum(nc), cells(nc))
        natural = 0.0_dp
        minimum = 0.0_dp
        do j = 1, nc
            if (allocated(doc%tables(t)%headers)) then
                call cell_widths(trim(doc%tables(t)%headers(j)), FACE_BOLD, fs, nw, mw, status=status)
                if (.not. status%ok()) return
                natural(j) = nw
                minimum(j) = mw
            end if
            do i = 1, nr
                call cell_widths(trim(doc%tables(t)%cells(i, j)), FACE_REGULAR, fs, nw, mw, status=status)
                if (.not. status%ok()) return
                natural(j) = max(natural(j), nw)
                minimum(j) = max(minimum(j), mw)
            end do
        end do
        call grid_widths(natural, minimum, available, padding, widths, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        if (doc%nodes(node)%first > 0) then
            prefix = target_number(state, node)
            if (len(prefix) > 0) prefix = "Table "//prefix//"."
            call caption_frame(state, doc, doc%nodes(node)%first, available, ctx, caption, status=status, prefix=prefix)
            if (.not. status%ok()) return
            call ts_import_frame(state%engine, caption, handle, status=status)
            if (.not. status%ok()) return
            call ts_place_frame(state%engine, handle, left=ctx%left, interline=.false., status=status)
            if (.not. status%ok()) return
            call ts_penalty(state%engine, 10000)
            call ts_vskip(state%engine, ts_glue_t(0.4_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
        end if
        header = 0
        if (allocated(doc%tables(t)%headers)) then
            do j = 1, nc
                align = table_alignment(doc%tables(t), j, .true.)
                call cell_frame(cell_state, trim(doc%tables(t)%headers(j)), &
                                widths(j) - 2*padding, FACE_BOLD, fs, align, cells(j), status=status)
                if (.not. status%ok()) return
            end do
            call grid_row(cells, widths, padding, row, background=[238, 242, 247], status=status)
            if (.not. status%ok()) return
            call ts_import_frame(state%engine, row, header, status=status)
            if (.not. status%ok()) return
            call ts_place_frame(state%engine, header, left=ctx%left, interline=.false., status=status)
            if (.not. status%ok()) return
            if (nr > 0) call ts_penalty(state%engine, 10000)
        end if
        do i = 1, nr
            do j = 1, nc
                align = table_alignment(doc%tables(t), j, .false.)
                call cell_frame(cell_state, trim(doc%tables(t)%cells(i, j)), &
                                widths(j) - 2*padding, FACE_REGULAR, fs, align, cells(j), status=status)
                if (.not. status%ok()) return
            end do
            call grid_row(cells, widths, padding, row, status=status)
            if (.not. status%ok()) return
            call ts_import_frame(state%engine, row, handle, status=status)
            if (.not. status%ok()) return
            call ts_place_frame(state%engine, handle, left=ctx%left, interline=.false., repeat_before=header, status=status)
            if (.not. status%ok()) return
            call ts_penalty(state%engine, 0)
        end do
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%settings%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        state%NOINDENT = .true.
    end subroutine table_block

    integer function table_alignment(table, column, header) result(align)
        type(doc_table_t), intent(in) :: table
        integer, intent(in) :: column
        logical, intent(in) :: header
        align = ALIGN_LEFT
        if (table%numeric .and. .not. header) align = ALIGN_RIGHT
        if (allocated(table%alignment)) then
            select case (table%alignment(column))
            case ("l"); align = ALIGN_LEFT
            case ("c"); align = ALIGN_CENTER
            case ("r"); align = ALIGN_RIGHT
            end select
        end if
    end function table_alignment

    subroutine cell_frame(state, text, width, face, fs, align, frame, status)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width, fs
        integer, intent(in) :: face, align
        type(frame_t), intent(out) :: frame
        type(status_t), intent(out) :: status
        call ts_reset(state, status=status)
        if (.not. status%ok()) return
        call ts_set_page(state, width, 1.0e6_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false., status=status)
        if (.not. status%ok()) return
        call ts_set_font(state, fs, 1.2_dp*fs, status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(state, ts_glue_t())
        call ts_begin_par(state, align, 0.0_dp, size=fs, status=status)
        if (.not. status%ok()) return
        call ts_strut(state, 0.7_dp*fs, 0.3_dp*fs)
        call ts_text(state, text, face, fs, status=status)
        if (.not. status%ok()) return
        call ts_finish_frame(state, frame, status=status)
        if (.not. status%ok()) return
    end subroutine cell_frame

    subroutine cell_widths(text, face, fs, natural, minimum, status)
        character(len=*), intent(in) :: text
        integer, intent(in) :: face
        real(dp), intent(in) :: fs
        real(dp), intent(out) :: natural, minimum
        character(len=:), allocatable :: line
        integer :: a, b, i, j, k
        type(status_t), intent(out) :: status
        real(dp) :: ts_word_width_value1
        real(dp) :: ts_word_width_value2
        natural = 0.0_dp
        minimum = 0.0_dp
        a = 1
        do while (a <= len(text))
            b = index(text(a:), NL)
            if (b == 0) b = len(text) - a + 2
            line = text(a:a + b - 2)
            do k = 1, len(line)
                if (line(k:k) == achar(9) .or. line(k:k) == achar(13)) line(k:k) = " "
            end do
            call ts_word_width(line, face, fs, ts_word_width_value1, status=status)
            if (.not. status%ok()) return
            natural = max(natural, ts_word_width_value1)
            i = 1
            do while (i <= len(line))
                j = index(line(i:), " ")
                if (j == 0) j = len(line) - i + 2
                call ts_word_width(line(i:i + j - 2), face, fs, ts_word_width_value2, status=status)
                if (.not. status%ok()) return
                minimum = max(minimum, ts_word_width_value2)
                i = i + j
            end do
            a = a + b
        end do
    end subroutine cell_widths

    ! A paragraph of inline text in the context's settings.
    subroutine paragraph(state, doc, k, ctx, status, prefix)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        type(ctx_t), intent(in) :: ctx
        real(dp) :: ind
        integer :: c
        type(status_t), intent(out) :: status
        character(len=*), intent(in), optional :: prefix
        ind = 0.0_dp
        if (ctx%indent .and. .not. state%NOINDENT .and. ctx%align == ALIGN_JUSTIFY) ind = state%settings%PARINDENT
        state%NOINDENT = .false.
        call ts_begin_par(state%engine, ctx%align, ind, left=ctx%left, right=ctx%right, size=ctx%size, &
                          leading=state%settings%LEAD*ctx%size, status=status)
        if (.not. status%ok()) return
        if (present(prefix)) then
            call ts_text(state%engine, prefix, FACE_BOLD, ctx%size, ctx%color, status)
            if (.not. status%ok()) return
            call ts_space(state%engine, FACE_REGULAR, ctx%size, status)
            if (.not. status%ok()) return
        end if
        if (len(state%PENDING_LABEL) > 0) then
            call ts_label(state%engine, state%PENDING_LABEL, label_face(ctx), ctx%size, state%LABEL_SEP, ctx%color, status=status)
            if (.not. status%ok()) return
            state%PENDING_LABEL = ""
        end if
        call set_inlines(state, doc, k, base_style(ctx), status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
    end subroutine paragraph

    integer function label_face(ctx)
        type(ctx_t), intent(in) :: ctx
        label_face = FACE_REGULAR
        if (ctx%bold) label_face = FACE_BOLD
    end function label_face

    ! Headings: LaTeX's \section, \subsection and \subsubsection (and,
    ! for a book, \chapter for #).
    subroutine heading(state, doc, node, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: text, num
        type(style_t) :: st
        real(dp) :: ex, size, lead, hang
        type(ts_glue_t) :: before, after
        integer :: lv

        type(status_t), intent(out) :: status
        real(dp) :: text_width_value1
        text = doc_plain(doc, node, status=status)
        if (.not. status%ok()) return
        ex = face_xheight(FACE_REGULAR)*state%settings%BASE
        lv = state%node_info(node)%level
        num = target_number(state, node)
        if (state%settings%BOOK .and. lv == 0) then
            call chapter_heading(state, doc, node, text, ctx, status=status)
            if (.not. status%ok()) return
            return
        end if
        if (.not. state%settings%NUMBER_SECTIONS .or. lv > 3) num = ""
        select case (lv)
        case (1)
            size = 1.44_dp*state%settings%BASE
            lead = 18.0_dp*state%settings%BASE/10.0_dp
            before = ts_glue_t(3.5_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(2.3_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case (2)
            size = 1.2_dp*state%settings%BASE
            lead = 14.0_dp*state%settings%BASE/10.0_dp
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case default
            size = state%settings%BASE
            lead = state%settings%LEAD*state%settings%BASE
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        end select
        call ts_addpenalty(state%engine, -300, status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, before, status=status)
        if (.not. status%ok()) return
        if (state%settings%BOOK .and. lv == 1) then
            if (len(num) > 0) then
                call ts_mark(state%engine, upper(num//".  "//text), .false., section=.true.)
            else
                call ts_mark(state%engine, upper(text), .false., section=.true.)
            end if
        end if
        st = base_style(ctx)
        st%bold = .true.
        st%size = size
        hang = 0.0_dp
        if (len(num) > 0) then
            call text_width(num, size, FACE_BOLD, text_width_value1, status=status)
            if (.not. status%ok()) return
            hang = text_width_value1 + size
        end if
        call ts_begin_par(state%engine, ALIGN_JUSTIFY, 0.0_dp, left=ctx%left, right=ctx%right, size=size, &
                          leading=lead, hang=hang, nobreak=.true., status=status)
        if (.not. status%ok()) return
        if (len(num) > 0) then
            call ts_word(state%engine, num, FACE_BOLD, size, ctx%color, status=status)
            if (.not. status%ok()) return
            call ts_kern(state%engine, size)
        end if
        call set_inlines(state, doc, node, st, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_penalty(state%engine, 10000)
        call ts_vskip(state%engine, after, status=status)
        if (.not. status%ok()) return
        call ts_nobreak_next(state%engine)
        state%NOINDENT = .true.
    end subroutine heading

    ! LaTeX's \chapter in the book class: a new page, "Chapter n" and the
    ! title below it in large bold, and the chapter as the running head.
    subroutine chapter_heading(state, doc, node, text, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        type(status_t), intent(out) :: status
        call ts_page_break(state%engine, status=status)
        if (.not. status%ok()) return
        ! The running heads are the book class's: in capitals,
        ! "CHAPTER 1. TITLE" and "1.2. SECTION".
        if (state%settings%NUMBER_SECTIONS) then
            call ts_mark(state%engine, upper("Chapter "//itoa(state%node_info(node)%chapter)//".  "//text), .true.)
        else
            call ts_mark(state%engine, upper(text), .true.)
        end if
        call ts_vkeep(state%engine, ts_glue_t(50.0_dp*state%settings%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        st = base_style(ctx)
        st%bold = .true.
        if (state%settings%NUMBER_SECTIONS) then
            st%size = 2.074_dp*state%settings%BASE
            call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, size=st%size, leading=25.0_dp*state%settings%BASE/10.0_dp, &
                              skip=.false., nobreak=.true., status=status)
            if (.not. status%ok()) return
            call set_words(state, "Chapter "//itoa(state%node_info(node)%chapter), st, status=status)
            if (.not. status%ok()) return
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
            call ts_penalty(state%engine, 10000)
            call ts_vskip(state%engine, ts_glue_t(20.0_dp*state%settings%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
        end if
        st%size = 2.488_dp*state%settings%BASE
        call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, size=st%size, leading=30.0_dp*state%settings%BASE/10.0_dp, &
                          skip=.false., nobreak=.true., status=status)
        if (.not. status%ok()) return
        call set_inlines(state, doc, node, st, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_penalty(state%engine, 10000)
        call ts_vskip(state%engine, ts_glue_t(40.0_dp*state%settings%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        call ts_nobreak_next(state%engine)
        state%NOINDENT = .true.
    end subroutine chapter_heading

    ! A list: LaTeX's itemize or enumerate, with its spacing at the depth
    ! it is at. A tight list (no blank lines between its items) is set as
    ! Pandoc's \tightlist sets it, without \itemsep and \parsep.
    recursive subroutine list_block(state, doc, list, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: list
        type(ctx_t), intent(in) :: ctx
        integer :: lev, kind, num, nitem, it
        type(ctx_t) :: sub
        type(ts_glue_t) :: topsep, partopsep, itemsep, parsep
        real(dp) :: lm, f

        type(status_t), intent(out) :: status
        f = state%settings%BASE/10.0_dp
        lev = min(ctx%depth + 1, 4)
        select case (lev)
        case (1)
            topsep = ts_glue_t(8.0_dp*f, 2.0_dp*f, 4.0_dp*f, 0, 0)
            parsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.5_dp*state%settings%BASE
        case (2)
            topsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.2_dp*state%settings%BASE
        case (3)
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.87_dp*state%settings%BASE
        case default
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.7_dp*state%settings%BASE
        end select
        partopsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)

        if (doc%nodes(list)%tight) then
            itemsep = ts_glue_t()
            parsep = ts_glue_t()
        end if
        kind = merge(1, 0, doc%nodes(list)%ordered)
        sub = ctx
        sub%depth = ctx%depth + 1
        sub%left = ctx%left + lm
        sub%indent = .false.
        sub%inlist = .true.
        sub%align = ctx%align
        if (kind == 0) then
            sub%ilev = ctx%ilev + 1
        else
            sub%elev = ctx%elev + 1
        end if
        ! After a blank line, the list starts a paragraph, and \partopsep
        ! comes too.
        if (doc%nodes(list)%spaced .and. .not. ts_in_par(state%engine)) then
            call ts_addpenalty(state%engine, -51, status=status)
            if (.not. status%ok()) return
            call ts_addvspace(state%engine, add_glue(topsep, partopsep), status=status)
            if (.not. status%ok()) return
        else
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
            call ts_addpenalty(state%engine, -51, status=status)
            if (.not. status%ok()) return
            call ts_addvspace(state%engine, topsep, status=status)
            if (.not. status%ok()) return
        end if

        num = doc%nodes(list)%num
        nitem = 0
        it = doc%nodes(list)%first
        do while (it > 0)
            nitem = nitem + 1
            if (nitem > 1) then
                call ts_addpenalty(state%engine, -51, status=status)
                if (.not. status%ok()) return
                call ts_addvspace(state%engine, itemsep, status=status)
                if (.not. status%ok()) return
            end if
            state%PENDING_LABEL = list_label(kind, merge(sub%ilev, sub%elev, kind == 0), num)
            state%LABEL_SEP = 0.5_dp*state%settings%BASE
            call ts_set_parskip(state%engine, parsep)
            call set_blocks(state, doc, it, sub, status=status)
            if (.not. status%ok()) return
            if (len(state%PENDING_LABEL) > 0) then
                ! An item with no paragraph of its own still has its label.
                call ts_begin_par(state%engine, sub%align, 0.0_dp, left=sub%left, right=sub%right, &
                                  size=sub%size, status=status)
                if (.not. status%ok()) return
                call ts_label(state%engine, state%PENDING_LABEL, FACE_REGULAR, sub%size, state%LABEL_SEP, sub%color, status=status)
                if (.not. status%ok()) return
                call ts_strut(state%engine, 0.7_dp*sub%size, 0.3_dp*sub%size)
                call ts_end_par(state%engine, status=status)
                if (.not. status%ok()) return
                state%PENDING_LABEL = ""
            end if
            num = num + 1
            it = doc%nodes(it)%next
        end do
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(state%engine, state%settings%PARSKIP_G)
        if (ctx%depth > 0) call ts_set_parskip(state%engine, parsep_of(state, ctx%depth))
        call ts_addpenalty(state%engine, -51, status=status)
        if (.not. status%ok()) return
        if (ctx%depth == 0) then
            call ts_addvspace(state%engine, add_glue(topsep, partopsep), status=status)
            if (.not. status%ok()) return
        else
            call ts_addvspace(state%engine, topsep, status=status)
            if (.not. status%ok()) return
        end if
    end subroutine list_block

    ! A block quote: LaTeX's quote environment, a list with no label and
    ! equal margins.
    recursive subroutine quote_block(state, doc, node, ctx, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        type(ctx_t) :: sub
        type(status_t), intent(out) :: status
        sub = ctx
        sub%depth = ctx%depth + 1
        sub%left = ctx%left + 2.5_dp*state%settings%BASE
        sub%right = ctx%right + 2.5_dp*state%settings%BASE
        sub%indent = .false.
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_addpenalty(state%engine, -51, status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(state%engine, parsep_of(state, sub%depth))
        call set_blocks(state, doc, node, sub, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(state%engine, state%settings%PARSKIP_G)
        if (ctx%depth > 0) call ts_set_parskip(state%engine, parsep_of(state, ctx%depth))
        call ts_addpenalty(state%engine, -51, status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
    end subroutine quote_block

    ! Code: each line (each ending with a newline) as it is, unbroken, its
    ! spaces kept.
    subroutine code_block(state, text, ctx, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        integer :: a, b, i, j
        real(dp) :: sp
        character(len=:), allocatable :: s
        type(status_t), intent(out) :: status
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(state%engine, ts_glue_t())
        call text_width(" ", 0.9_dp*ctx%size, FACE_REGULAR, sp, status=status)
        if (.not. status%ok()) return
        a = 1
        do while (a <= len(text))
            b = index(text(a:), NL)
            if (b == 0) b = len(text) - a + 2
            s = text(a:a + b - 2)
            a = a + b
            call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, left=ctx%left + 1.5_dp*state%settings%BASE, &
                              right=ctx%right, size=0.9_dp*ctx%size, leading=state%settings%LEAD*ctx%size, status=status)
            if (.not. status%ok()) return
            call ts_strut(state%engine, 0.7_dp*ctx%size, 0.3_dp*ctx%size)
            i = 1
            do while (i <= len(s))
                if (s(i:i) == " ") then
                    call ts_kern(state%engine, sp, text=" ")
                    i = i + 1
                    cycle
                end if
                j = i
                do while (j <= len(s))
                    if (s(j:j) == " ") exit
                    j = j + 1
                end do
                call ts_word(state%engine, s(i:j - 1), FACE_REGULAR, 0.9_dp*ctx%size, CODE_COL, status=status)
                if (.not. status%ok()) return
                i = j
            end do
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
        end do
        call ts_set_parskip(state%engine, state%settings%PARSKIP_G)
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
    end subroutine code_block

    function parsep_of(state, depth) result(g)
        type(layout_context_t), intent(inout) :: state
        integer, intent(in) :: depth
        type(ts_glue_t) :: g
        real(dp) :: f
        f = state%settings%BASE/10.0_dp
        select case (depth)
        case (1)
            g = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
        case (2)
            g = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
        case default
            g = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
        end select
    end function parsep_of

    ! The label of item num of a list of the kind (0 bullets, 1 numbers)
    ! at depth lev: LaTeX's \labelitemi... and \labelenumi...
    function list_label(kind, lev, num) result(s)
        integer, intent(in) :: kind, lev, num
        character(len=:), allocatable :: s
        if (kind == 0) then
            select case (lev)
            case (1)
                s = achar(226)//achar(128)//achar(162)
            case (2)
                s = achar(226)//achar(128)//achar(147)
            case (3)
                s = achar(226)//achar(136)//achar(151)
            case default
                s = achar(194)//achar(183)
            end select
        else
            select case (lev)
            case (1)
                s = itoa(num)//"."
            case (2)
                s = "("//achar(96 + modulo(num - 1, 26) + 1)//")"
            case (3)
                s = roman(num)//"."
            case default
                s = achar(64 + modulo(num - 1, 26) + 1)//"."
            end select
        end if
    end function list_label

    ! ------------------------------------------------------------------
    ! Inline text.
    ! ------------------------------------------------------------------

    function base_style(ctx) result(st)
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        st%size = ctx%size
        st%color = ctx%color
        st%bold = ctx%bold
        st%italic = ctx%italic
    end function base_style

    pure integer function face_of(st)
        type(style_t), intent(in) :: st
        if (st%bold) then
            face_of = FACE_BOLD
        else if (st%italic) then
            face_of = FACE_ITALIC
        else
            face_of = FACE_REGULAR
        end if
    end function face_of

    ! Set the inlines of node k, in style st, into the current paragraph.
    subroutine set_inlines(state, doc, k, st, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        type(style_t), intent(in) :: st
        type(status_t), intent(out) :: status
        state%W = ""
        state%SPACE = .false.
        call walk(state, doc, k, st, status=status)
        if (.not. status%ok()) return
        call flush(state, st, status=status)
        if (.not. status%ok()) return
    end subroutine set_inlines

    ! Words in style st, a space between each two.
    subroutine set_words(state, s, st, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: s
        type(style_t), intent(in) :: st
        integer :: i, j
        type(status_t), intent(out) :: status
        i = 1
        do while (i <= len(s))
            j = index(s(i:), " ")
            if (j == 0) then
                j = len(s) + 1
            else
                j = i + j - 1
            end if
            if (i > 1) then
                call ts_space(state%engine, face_of(st), st%size, status=status)
                if (.not. status%ok()) return
            end if
            call ts_word(state%engine, s(i:j - 1), face_of(st), st%size, st%color, status=status)
            if (.not. status%ok()) return
            i = j + 1
        end do
    end subroutine set_words

    ! The children of node parent, in style st. A word goes out when
    ! something else than text comes, after the space before it.
    recursive subroutine walk(state, doc, parent, st, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(style_t), intent(in) :: st
        type(style_t) :: sx
        character(len=:), allocatable :: tag
        integer :: c

        type(status_t), intent(out) :: status
        c = doc%nodes(parent)%first
        do while (c > 0)
            associate (nd => doc%nodes(c))
                select case (nd%kind)
                case (IN_STR)
                    call add_text(state, nd%text, st, status=status)
                    if (.not. status%ok()) return
                case (IN_SPACE)
                    call flush(state, st, status=status)
                    if (.not. status%ok()) return
                    if (.not. state%SPACE) then
                        state%SP_FACE = face_of(st)
                        state%SP_SIZE = st%size
                    end if
                    state%SPACE = .true.
                case (IN_BREAK)
                    call flush(state, st, status=status)
                    if (.not. status%ok()) return
                    call ts_hard_break(state%engine, status=status)
                    if (.not. status%ok()) return
                    state%SPACE = .false.
                case (IN_EMPH, IN_STRONG, IN_LINK)
                    call flush(state, st, status=status)
                    if (.not. status%ok()) return
                    sx = st
                    select case (nd%kind)
                    case (IN_EMPH)
                        sx%italic = .not. st%italic
                    case (IN_STRONG)
                        sx%bold = .true.
                    case (IN_LINK)
                        sx%color = LINK_COL
                    end select
                    call walk(state, doc, c, sx, status=status)
                    if (.not. status%ok()) return
                    call flush(state, sx, status=status)
                    if (.not. status%ok()) return
                case (IN_CODE)
                    call flush(state, st, status=status)
                    if (.not. status%ok()) return
                    call flush_space(state, status=status)
                    if (.not. status%ok()) return
                    call set_code(state, nd%text, st%size, status=status)
                    if (.not. status%ok()) return
                case (IN_MATH)
                    call flush(state, st, status=status)
                    if (.not. status%ok()) return
                    if (nd%display) then
                        tag = target_number(state, c)
                        call ts_math(state%engine, nd%text, st%size, st%color, &
                                     display=.true., tag=tag, status=status)
                        if (.not. status%ok()) return
                        state%SPACE = .false.
                    else
                        call flush_space(state, status=status)
                        if (.not. status%ok()) return
                        call ts_math(state%engine, nd%text, st%size, st%color, status=status)
                        if (.not. status%ok()) return
                    end if
                case (DOC_INLINES)
                    call flush(state, st, status)
                    if (.not. status%ok()) return
                    call walk(state, doc, c, st, status)
                    if (.not. status%ok()) return
                case (IN_REF)
                    call status%set(ERROR_STATE, "layout: unresolved reference reached the layout pass")
                    return
                end select
            end associate
            c = doc%nodes(c)%next
        end do
    end subroutine walk

    ! Text onto the word; a no-break space is glue that does not break.
    subroutine add_text(state, s, st, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: s
        type(style_t), intent(in) :: st
        integer :: i, j
        type(status_t), intent(out) :: status
        i = 1
        do
            j = index(s(i:), NBSP)
            if (j == 0) exit
            state%W = state%W//s(i:i + j - 2)
            call flush(state, st, status=status)
            if (.not. status%ok()) return
            call ts_nbsp(state%engine, face_of(st), st%size, status=status)
            if (.not. status%ok()) return
            state%SPACE = .false.
            i = i + j + 1
        end do
        state%W = state%W//s(i:)
    end subroutine add_text

    ! The word so far goes out, after a space if one came before it.
    subroutine flush(state, st, status)
        type(layout_context_t), intent(inout) :: state
        type(style_t), intent(in) :: st
        type(status_t), intent(out) :: status
        if (len(state%W) == 0) return
        call flush_space(state, status=status)
        if (.not. status%ok()) return
        call ts_word(state%engine, state%W, face_of(st), st%size, st%color, status=status)
        if (.not. status%ok()) return
        state%W = ""
    end subroutine flush

    subroutine flush_space(state, status)
        type(layout_context_t), intent(inout) :: state
        type(status_t), intent(out) :: status
        if (state%SPACE) then
            call ts_space(state%engine, state%SP_FACE, state%SP_SIZE, status=status)
            if (.not. status%ok()) return
        end if
        state%SPACE = .false.
    end subroutine flush_space

    ! Code, as it is: its words upright, its spaces glue.
    subroutine set_code(state, t, size, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: t
        real(dp), intent(in) :: size
        integer :: i, j
        type(status_t), intent(out) :: status
        i = 1
        do while (i <= len(t))
            if (t(i:i) == " ") then
                call ts_space(state%engine, FACE_REGULAR, size, status=status)
                if (.not. status%ok()) return
                i = i + 1
                cycle
            end if
            j = i
            do while (j <= len(t))
                if (t(j:j) == " ") exit
                j = j + 1
            end do
            call ts_word(state%engine, t(i:j - 1), FACE_REGULAR, size, CODE_COL, status=status)
            if (.not. status%ok()) return
            i = j
        end do
    end subroutine set_code

    ! The TeX and LaTeX logos, as plain TeX and LaTeX draw them.

    ! The formula without \label{...}, \tag{...}, \notag and \nonumber,
    ! which are for the numbering.

    ! ------------------------------------------------------------------
    ! Numbers and cross references.
    ! ------------------------------------------------------------------

    ! The number of the next heading of the level: lv is its depth among
    ! sections (0 for a chapter of a book), num its number, 1.2.3 (empty
    ! below \subsubsection's level).

    ! ------------------------------------------------------------------
    ! Small things.
    ! ------------------------------------------------------------------

    function target_number(state, node) result(number)
        type(layout_context_t), intent(in) :: state
        integer, intent(in) :: node
        character(len=:), allocatable :: number
        number = ""
        if (node < 1 .or. node > size(state%node_info)) return
        if (allocated(state%node_info(node)%number)) number = state%node_info(node)%number
    end function target_number

    ! Capitals, for the running heads: the ASCII and Latin-1 letters.
    function upper(s) result(t)
        character(len=*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: k, c
        t = s
        k = 1
        do while (k <= len(s))
            c = iachar(t(k:k))
            if (c >= 97 .and. c <= 122) then
                t(k:k) = achar(c - 32)
            else if (c == 195 .and. k < len(s)) then
                ! U+00E0 to U+00FE, but not the division sign.
                c = iachar(t(k + 1:k + 1))
                if (c >= 160 .and. c <= 190 .and. c /= 183) t(k + 1:k + 1) = achar(c - 32)
                k = k + 1
            end if
            k = k + 1
        end do
    end function upper

    ! LaTeX's glue scaled from its 10pt values to the body size.
    function scale(state, g) result(r)
        type(layout_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: g
        type(ts_glue_t) :: r
        real(dp) :: f
        f = state%settings%BASE/10.0_dp
        r = ts_glue_t(g%w*f, g%st*f, g%sh*f, g%sto, g%sho)
    end function scale

    pure function add_glue(a, b) result(r)
        type(ts_glue_t), intent(in) :: a, b
        type(ts_glue_t) :: r
        r = ts_glue_t(a%w + b%w, a%st + b%st, a%sh + b%sh, max(a%sto, b%sto), &
                      max(a%sho, b%sho))
    end function add_glue

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: b
        write (b, "(I0)") i
        s = trim(b)
    end function itoa

    function roman(n) result(s)
        integer, intent(in) :: n
        character(len=:), allocatable :: s
        integer, parameter :: v(13) = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        character(len=2), parameter :: r(13) = ["m ", "cm", "d ", "cd", "c ", "xc", "l ", &
                                                "xl", "x ", "ix", "v ", "iv", "i "]
        integer :: k, m
        s = ""
        m = n
        do k = 1, 13
            do while (m >= v(k))
                s = s//trim(r(k))
                m = m - v(k)
            end do
        end do
    end function roman

end module fplotlib_docclass
