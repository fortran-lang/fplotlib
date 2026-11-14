! fplotlib_docclass -- set a document tree as LaTeX's classes do.
!
! The document class: it sets an fplotlib_doctree tree with fplotlib_typeset,
! with the spacing and the styles of LaTeX's article class (or book, with
! class: book), so that a document comes out the way the same source does
! through Pandoc and LaTeX. It numbers sections and equations, and resolves
! references to them, from a first pass over the tree, as LaTeX does from
! its .aux file.
!
! The front matter's keys: title, subtitle, author (once per author), date,
! abstract, class (article or book), fontsize, linestretch, paper (a4, a5,
! a6, letter, legal, b5 or "W x H"), margin and margin-left, -right, -top
! and -bottom, indent, parskip, align, numbersections, numberequations,
! pagenumbers, color and pagecolor.
!
! Divs and spans take classes (.center, .right, .left, .justify, .bold,
! .italic, .upright, and LaTeX's size names .tiny to .Huge) and key=value
! pairs (size, color, align).
!
! Lengths are in points (1/72 in, as in PostScript and Typst), or in bp,
! in, cm, mm, em or ex.
module fplotlib_docclass
    use fplotlib_style, only: dp
    use fplotlib_colors, only: color_from_name
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_BOLD, FACE_ITALIC, face_xheight, &
                               face_capheight
    use fplotlib_doctree
    use fplotlib_markdown, only: md_parse
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY
    use fplotlib_render, only: clip_t
    use fplotlib_grid, only: grid_widths, grid_row
    use fplotlib_typeset
    implicit none
    private

    public :: layout_context_t

    public :: doc_typeset, layout_markdown, layout_fragment

    character, parameter :: BS = achar(92), NL = achar(10)
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

    type :: label_t
        character(len=:), allocatable :: name, text
    end type label_t

    ! The document's settings.
    integer, parameter :: LINK_COL(3) = [26, 95, 180], CODE_COL(3) = [80, 80, 80]

    type :: layout_context_t
        private
        type(typeset_context_t) :: engine
        integer :: graphics_base = 0
        real(dp) :: BASE = 10.0_dp, LEAD = 1.2_dp
        real(dp) :: PARINDENT = 15.0_dp
        type(ts_glue_t) :: PARSKIP_G
        integer :: DOC_ALIGN = ALIGN_JUSTIFY
        logical :: NUMBER_SECTIONS = .false., BOOK = .false., NUMBER_EQS = .false.
        ! The title block's inlines: nodes of the front matter, 0 for none.
        integer :: TITLE = 0, SUBTITLE = 0, DATE = 0, ABSTRACT = 0
        integer :: NAUTHOR = 0, AUTHORS(16)
        integer :: TEXT_COL(3) = 0, PAGE_COL(3) = 255

        ! Counters and cross references.
        integer :: SEC(4) = 0, CHAPTER = 0, EQNO = 0
        integer :: NLAB = 0
        type(label_t), allocatable :: label(:)

        ! The next paragraph is not indented (after a heading, a display, or
        ! \noindent), and the label the next paragraph of a list item starts
        ! with.
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
    subroutine doc_typeset(state, doc, document)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(paged_document_t), intent(out) :: document
        type(ctx_t) :: ctx

        call ts_reset(state%engine)
        call defaults(state)
        if (doc%ngraphics > 0) call ts_import_frame(state%engine, doc%graphics, state%graphics_base)
        call settings(state, doc)
        call ts_set_font(state%engine, state%BASE, state%LEAD*state%BASE)
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        call ts_set_colors(state%engine, state%TEXT_COL, state%PAGE_COL)
        call labels(state, doc, 1)
        state%SEC = 0
        state%CHAPTER = 0
        state%EQNO = 0
        ctx%size = state%BASE
        ctx%color = state%TEXT_COL
        ctx%align = state%DOC_ALIGN
        call title_block(state, doc, ctx)
        call set_blocks(state, doc, 1, ctx)
        call ts_finish(state%engine, document)
    end subroutine doc_typeset

    subroutine layout_markdown(state, text, document)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        type(paged_document_t), intent(out) :: document
        type(doc_t) :: tree
        call md_parse(text, tree)
        call doc_typeset(state, tree, document)
    end subroutine layout_markdown

    ! A width-constrained fragment for an annotation or another layout engine.
    ! It uses the same block/inline layout without title or page furniture.
    subroutine layout_fragment(state, text, width, frame, font_size)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width
        type(frame_t), intent(out) :: frame
        real(dp), intent(in), optional :: font_size
        type(doc_t) :: tree
        type(ctx_t) :: ctx
        if (width <= 0.0_dp) error stop "layout_fragment: width must be positive"
        call md_parse(text, tree)
        call ts_reset(state%engine)
        call defaults(state)
        if (present(font_size)) state%BASE = font_size
        if (state%BASE <= 0.0_dp) error stop "layout_fragment: font size must be positive"
        call ts_set_page(state%engine, width, 1.0e6_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false.)
        call ts_set_font(state%engine, state%BASE, state%LEAD*state%BASE)
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        state%PARINDENT = 0.0_dp
        ctx%size = state%BASE
        ctx%indent = .false.
        call labels(state, tree, 1)
        state%SEC = 0
        state%CHAPTER = 0
        state%EQNO = 0
        call set_blocks(state, tree, 1, ctx)
        call ts_finish_frame(state%engine, frame)
    end subroutine layout_fragment

    subroutine defaults(state)
        type(layout_context_t), intent(inout) :: state
        state%BASE = 10.0_dp
        state%LEAD = 1.2_dp
        state%PARINDENT = -1.0_dp
        state%PARSKIP_G = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        state%DOC_ALIGN = ALIGN_JUSTIFY
        state%NUMBER_SECTIONS = .false.
        state%NUMBER_EQS = .false.
        state%BOOK = .false.
        state%TITLE = 0
        state%SUBTITLE = 0
        state%NAUTHOR = 0
        state%DATE = 0
        state%ABSTRACT = 0
        state%TEXT_COL = 0
        state%PAGE_COL = 255
        state%NLAB = 0
        if (.not. allocated(state%label)) allocate (state%label(16))
        state%SEC = 0
        state%CHAPTER = 0
        state%EQNO = 0
        state%NOINDENT = .false.
        state%graphics_base = 0
        state%PENDING_LABEL = ""
        state%W = ""
        state%SPACE = .false.
        call ts_set_page(state%engine, 595.2756_dp, 841.8898_dp, 72.0_dp, 72.0_dp, 72.0_dp, 72.0_dp)
    end subroutine defaults

    ! The settings of the front matter, in its order (a length in ems is
    ! in the font size given before it).
    subroutine settings(state, doc)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer :: i
        character(len=:), allocatable :: key, val
        real(dp) :: pw, ph, ml, mr, mt, mb, m
        logical :: numbers, heads

        pw = 595.2756_dp
        ph = 841.8898_dp
        m = -1.0_dp
        ml = -1.0_dp
        mr = -1.0_dp
        mt = -1.0_dp
        mb = -1.0_dp
        numbers = .true.
        heads = .false.
        do i = 1, doc%nmeta
            key = doc%meta(i)%key
            val = doc%meta(i)%value
            select case (key)
            case ("title")
                state%TITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("subtitle")
                state%SUBTITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("author")
                if (len(val) > 0 .and. state%NAUTHOR < size(state%AUTHORS)) then
                    state%NAUTHOR = state%NAUTHOR + 1
                    state%AUTHORS(state%NAUTHOR) = doc%meta(i)%node
                end if
            case ("date")
                state%DATE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("abstract")
                state%ABSTRACT = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("fontsize")
                state%BASE = length(val, 10.0_dp)
            case ("linestretch", "leading")
                state%LEAD = 1.2_dp*number(val, 1.0_dp)
            case ("paper", "papersize")
                call paper_size(state, lower(val), pw, ph)
            case ("margin")
                m = length(val, state%BASE)
            case ("margin-left")
                ml = length(val, state%BASE)
            case ("margin-right")
                mr = length(val, state%BASE)
            case ("margin-top")
                mt = length(val, state%BASE)
            case ("margin-bottom")
                mb = length(val, state%BASE)
            case ("indent", "parindent")
                if (lower(val) == "false" .or. lower(val) == "no") then
                    state%PARINDENT = 0.0_dp
                else if (lower(val) /= "true" .and. lower(val) /= "yes") then
                    state%PARINDENT = length(val, state%BASE)
                end if
            case ("parskip")
                state%PARSKIP_G = ts_glue_t(length(val, state%BASE), 0.2_dp*length(val, state%BASE), &
                                      0.0_dp, 0, 0)
                if (state%PARINDENT < 0.0_dp) state%PARINDENT = 0.0_dp
            case ("align")
                state%DOC_ALIGN = align_of(lower(val), ALIGN_JUSTIFY)
            case ("numbersections", "number-sections")
                state%NUMBER_SECTIONS = truth(val)
            case ("numberequations", "number-equations")
                state%NUMBER_EQS = truth(val)
            case ("pagenumbers", "page-numbers")
                numbers = truth(val)
            case ("class", "documentclass")
                state%BOOK = lower(val) == "book"
                heads = state%BOOK
            case ("color", "fontcolor")
                state%TEXT_COL = color_of(val, [0, 0, 0])
            case ("pagecolor", "background")
                state%PAGE_COL = color_of(val, [255, 255, 255])
            end select
        end do
        if (state%PARINDENT < 0.0_dp) state%PARINDENT = 1.5_dp*state%BASE
        ! LaTeX's geometry is set here by margins; without them, one inch.
        if (m < 0.0_dp) m = 72.0_dp
        if (ml < 0.0_dp) ml = m
        if (mr < 0.0_dp) mr = m
        if (mt < 0.0_dp) mt = m
        if (mb < 0.0_dp) mb = m
        call ts_set_page(state%engine, pw, ph, ml, mr, mt, mb, numbers, heads, state%BOOK)
    end subroutine settings

    subroutine paper_size(state, v, w, h)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: v
        real(dp), intent(inout) :: w, h
        integer :: x
        select case (v)
        case ("a4")
            w = 595.2756_dp
            h = 841.8898_dp
        case ("a5")
            w = 419.5276_dp
            h = 595.2756_dp
        case ("a6")
            w = 297.6378_dp
            h = 419.5276_dp
        case ("letter", "us-letter")
            w = 612.0_dp
            h = 792.0_dp
        case ("legal")
            w = 612.0_dp
            h = 1008.0_dp
        case ("b5")
            w = 498.8976_dp
            h = 708.6614_dp
        case default
            ! "W x H", lengths.
            x = index(v, "x")
            if (x > 0) then
                w = length(trim(v(1:x - 1)), state%BASE)
                h = length(trim(v(x + 1:)), state%BASE)
            end if
        end select
    end subroutine paper_size

    ! LaTeX's \maketitle and abstract, for the article class.
    subroutine title_block(state, doc, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        integer :: i
        if (state%TITLE == 0) return
        st = base_style(ctx)
        call ts_vkeep(state%engine, ts_glue_t(2.0_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        st%size = 1.728_dp*state%BASE
        call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, leading=22.0_dp*state%BASE/10.0_dp, &
                          skip=.false.)
        call set_inlines(state, doc, state%TITLE, st)
        call ts_end_par(state%engine)
        if (state%SUBTITLE > 0) then
            st%size = 1.2_dp*state%BASE
            call ts_vskip(state%engine, ts_glue_t(0.5_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*state%BASE/10.0_dp, skip=.false.)
            call set_inlines(state, doc, state%SUBTITLE, st)
            call ts_end_par(state%engine)
        end if
        st%size = 1.2_dp*state%BASE
        if (state%NAUTHOR > 0) then
            call ts_vskip(state%engine, ts_glue_t(1.5_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
            do i = 1, state%NAUTHOR
                call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                                  leading=14.0_dp*state%BASE/10.0_dp, skip=.false.)
                call set_inlines(state, doc, state%AUTHORS(i), st)
                call ts_end_par(state%engine)
            end do
        end if
        if (state%DATE > 0) then
            call ts_vskip(state%engine, ts_glue_t(state%BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*state%BASE/10.0_dp, skip=.false.)
            call set_inlines(state, doc, state%DATE, st)
            call ts_end_par(state%engine)
        end if
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_vskip(state%engine, ts_glue_t(1.5_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
        if (state%ABSTRACT > 0) then
            ! \small, a centred bold heading, and a quotation.
            st = base_style(ctx)
            st%size = 0.9_dp*state%BASE
            st%bold = .true.
            call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=11.0_dp*state%BASE/10.0_dp, skip=.false.)
            call set_words(state, "Abstract", st)
            call ts_end_par(state%engine)
            st%bold = .false.
            call ts_vskip(state%engine, ts_glue_t(-0.5_dp*st%size + 0.5_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(state%engine, ALIGN_JUSTIFY, 1.5_dp*st%size, left=2.5_dp*state%BASE, &
                              right=2.5_dp*state%BASE, size=st%size, leading=11.0_dp*state%BASE/10.0_dp)
            call set_inlines(state, doc, state%ABSTRACT, st)
            call ts_end_par(state%engine)
            call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        end if
        state%NOINDENT = .false.
    end subroutine title_block

    ! ------------------------------------------------------------------
    ! Blocks.
    ! ------------------------------------------------------------------

    ! The blocks that are the children of node parent.
    recursive subroutine set_blocks(state, doc, parent, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(ctx_t), intent(in) :: ctx
        type(ctx_t) :: sub
        integer :: c, aligns

        c = doc%nodes(parent)%first
        do while (c > 0)
            select case (doc%nodes(c)%kind)
            case (DOC_PARA)
                call paragraph(state, doc, c, ctx)
            case (DOC_HEADING)
                call heading(state, doc, c, ctx)
            case (DOC_CODE)
                call code_block(state, doc%nodes(c)%text, ctx)
            case (DOC_DIV)
                ! A div that aligns its text is a LaTeX environment
                ! (center, flushright, flushleft), a list with the space of
                ! one around it; one that only changes the type is a group.
                sub = div_ctx(state, doc%nodes(c)%attr, ctx, aligns)
                if (aligns > 0) call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                call set_blocks(state, doc, c, sub)
                call ts_end_par(state%engine)
                if (aligns > 0) call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            case (DOC_QUOTE)
                call quote_block(state, doc, c, ctx)
            case (DOC_LIST)
                call list_block(state, doc, c, ctx)
            case (DOC_RULE)
                call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, left=ctx%left, right=ctx%right)
                call ts_end_par(state%engine)
                call ts_rule(state%engine, 0.5_dp*(ts_hsize(state%engine) - ctx%left - ctx%right), 0.5_dp, ctx%color)
                call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            case (DOC_RAW)
                call raw_block(state, doc%nodes(c)%text, ctx)
            case (DOC_FRAME)
                if (state%graphics_base == 0) error stop "document: missing frame resources"
                call ts_place_frame(state%engine, state%graphics_base + doc%nodes(c)%num - 1, &
                                    left=ctx%left, right=ctx%right, align=ctx%align)
            case (DOC_FIGURE)
                call figure_block(state, doc, c, ctx)
            case (DOC_TABLE)
                call table_block(state, doc, c, ctx)
            end select
            c = doc%nodes(c)%next
        end do
    end subroutine set_blocks

    ! Captions get their own workspace, but share the resolved reference
    ! values. They cannot disturb a report that is being laid out.
    recursive subroutine caption_frame(state, doc, node, width, ctx, frame)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        real(dp), intent(in) :: width
        type(ctx_t), intent(in) :: ctx
        type(frame_t), intent(out) :: frame
        type(layout_context_t) :: nested
        type(ctx_t) :: sub
        call ts_reset(nested%engine)
        call defaults(nested)
        nested%BASE = state%BASE
        nested%LEAD = state%LEAD
        nested%PARINDENT = 0.0_dp
        nested%NUMBER_EQS = state%NUMBER_EQS
        nested%BOOK = state%BOOK
        nested%CHAPTER = state%CHAPTER
        nested%EQNO = state%EQNO
        nested%NLAB = state%NLAB
        deallocate (nested%label)
        allocate (nested%label(max(16, state%NLAB)))
        nested%label(1:state%NLAB) = state%label(1:state%NLAB)
        sub = ctx
        sub%left = 0.0_dp
        sub%right = 0.0_dp
        sub%indent = .false.
        sub%align = ALIGN_CENTER
        sub%size = 0.9_dp*ctx%size
        call ts_set_page(nested%engine, width, 1.0e6_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false.)
        call ts_set_font(nested%engine, sub%size, nested%LEAD*sub%size)
        call ts_set_parskip(nested%engine, ts_glue_t())
        call set_blocks(nested, doc, node, sub)
        call ts_finish_frame(nested%engine, frame)
        state%EQNO = nested%EQNO
    end subroutine caption_frame

    recursive subroutine figure_block(state, doc, node, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        type(frame_t) :: caption, frame
        type(recording_renderer_t) :: recorder
        type(clip_t) :: clip
        real(dp) :: w, h, width, scale_, cw, ch, gap, available, matrix(6), left
        integer :: graphic, cap, handle
        graphic = doc%nodes(node)%first
        if (graphic == 0) error stop "document figure: missing graphics"
        if (doc%nodes(graphic)%kind /= DOC_FRAME) error stop "document figure: expected a frame"
        call doc%graphics%metrics(w, h, handle=doc%nodes(graphic)%num)
        if (w <= 0.0_dp .or. h <= 0.0_dp) error stop "document figure: empty graphics"
        available = ts_hsize(state%engine) - ctx%left - ctx%right
        width = min(w, available)
        if (doc%nodes(node)%width > 0) width = min(doc%nodes(node)%width, available)
        if (width <= 0.0_dp) error stop "document figure: no horizontal space"
        cap = doc%nodes(graphic)%next
        ch = 0.0_dp
        gap = 0.0_dp
        if (cap > 0) then
            call caption_frame(state, doc, cap, width, ctx, caption)
            call caption%metrics(cw, ch)
            gap = 0.5_dp*state%BASE
        end if
        if (ch + gap >= ts_vsize(state%engine)) error stop "document figure: caption exceeds page height"
        scale_ = min(width/w, (ts_vsize(state%engine) - ch - gap)/h)
        left = 0.5_dp*(width - scale_*w)
        call recorder%open_canvas(width, scale_*h + gap + ch)
        matrix = [scale_, 0.0_dp, 0.0_dp, scale_, left, 0.0_dp]
        call recorder%begin_frame(matrix, clip)
        call doc%graphics%draw(recorder, doc%nodes(graphic)%num)
        call recorder%end_frame()
        if (cap > 0) then
            matrix = IDENTITY
            matrix(6) = scale_*h + gap
            call recorder%begin_frame(matrix, clip)
            call caption%draw(recorder)
            call recorder%end_frame()
        end if
        call recorder%close_canvas()
        call recorder%take(frame)
        call ts_end_par(state%engine)
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
        call ts_import_frame(state%engine, frame, handle)
        call ts_place_frame(state%engine, handle, left=ctx%left, right=ctx%right, &
                            align=ALIGN_CENTER, interline=.false.)
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
        state%NOINDENT = .true.
    end subroutine figure_block

    ! Plain data cells are measured before choosing column widths, then
    ! paragraphs are laid out to those widths. The core packs rows and
    ! paginates them, reserving repeated headers on continuation pages.
    recursive subroutine table_block(state, doc, node, ctx)
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
        t = doc%nodes(node)%num
        if (t < 1 .or. t > doc%ntables) error stop "document table: invalid table"
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
                call cell_widths(trim(doc%tables(t)%headers(j)), FACE_BOLD, fs, nw, mw)
                natural(j) = nw
                minimum(j) = mw
            end if
            do i = 1, nr
                call cell_widths(trim(doc%tables(t)%cells(i, j)), FACE_REGULAR, fs, nw, mw)
                natural(j) = max(natural(j), nw)
                minimum(j) = max(minimum(j), mw)
            end do
        end do
        call grid_widths(natural, minimum, available, padding, widths)
        call ts_end_par(state%engine)
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
        if (doc%nodes(node)%first > 0) then
            call caption_frame(state, doc, doc%nodes(node)%first, available, ctx, caption)
            call ts_import_frame(state%engine, caption, handle)
            call ts_place_frame(state%engine, handle, left=ctx%left, interline=.false.)
            call ts_penalty(state%engine, 10000)
            call ts_vskip(state%engine, ts_glue_t(0.4_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
        end if
        header = 0
        if (allocated(doc%tables(t)%headers)) then
            do j = 1, nc
                call cell_frame(cell_state, trim(doc%tables(t)%headers(j)), &
                                widths(j) - 2*padding, FACE_BOLD, fs, ALIGN_LEFT, cells(j))
            end do
            call grid_row(cells, widths, padding, row, background=[238, 242, 247])
            call ts_import_frame(state%engine, row, header)
            call ts_place_frame(state%engine, header, left=ctx%left, interline=.false.)
            if (nr > 0) call ts_penalty(state%engine, 10000)
        end if
        align = ALIGN_LEFT
        if (doc%tables(t)%numeric) align = ALIGN_RIGHT
        do i = 1, nr
            do j = 1, nc
                call cell_frame(cell_state, trim(doc%tables(t)%cells(i, j)), &
                                widths(j) - 2*padding, FACE_REGULAR, fs, align, cells(j))
            end do
            call grid_row(cells, widths, padding, row)
            call ts_import_frame(state%engine, row, handle)
            call ts_place_frame(state%engine, handle, left=ctx%left, interline=.false., repeat_before=header)
            call ts_penalty(state%engine, 0)
        end do
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0))
        state%NOINDENT = .true.
    end subroutine table_block

    subroutine cell_frame(state, text, width, face, fs, align, frame)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width, fs
        integer, intent(in) :: face, align
        type(frame_t), intent(out) :: frame
        call ts_reset(state)
        call ts_set_page(state, width, 1.0e6_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false.)
        call ts_set_font(state, fs, 1.2_dp*fs)
        call ts_set_parskip(state, ts_glue_t())
        call ts_begin_par(state, align, 0.0_dp, size=fs)
        call ts_strut(state, 0.7_dp*fs, 0.3_dp*fs)
        call ts_text(state, text, face, fs)
        call ts_finish_frame(state, frame)
    end subroutine cell_frame

    subroutine cell_widths(text, face, fs, natural, minimum)
        character(len=*), intent(in) :: text
        integer, intent(in) :: face
        real(dp), intent(in) :: fs
        real(dp), intent(out) :: natural, minimum
        character(len=:), allocatable :: line
        integer :: a, b, i, j, k
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
            natural = max(natural, ts_word_width(line, face, fs))
            i = 1
            do while (i <= len(line))
                j = index(line(i:), " ")
                if (j == 0) j = len(line) - i + 2
                minimum = max(minimum, ts_word_width(line(i:i + j - 2), face, fs))
                i = i + j
            end do
            a = a + b
        end do
    end subroutine cell_widths

    ! A paragraph of inline text in the context's settings.
    subroutine paragraph(state, doc, k, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        type(ctx_t), intent(in) :: ctx
        real(dp) :: ind
        integer :: c
        ind = 0.0_dp
        if (ctx%indent .and. .not. state%NOINDENT .and. ctx%align == ALIGN_JUSTIFY) ind = state%PARINDENT
        c = doc%nodes(k)%first
        if (c > 0) then
            if (doc%nodes(c)%kind == IN_RAW .and. doc%nodes(c)%text == "noindent") ind = 0.0_dp
        end if
        state%NOINDENT = .false.
        call ts_begin_par(state%engine, ctx%align, ind, left=ctx%left, right=ctx%right, size=ctx%size, &
                          leading=state%LEAD*ctx%size)
        if (len(state%PENDING_LABEL) > 0) then
            call ts_label(state%engine, state%PENDING_LABEL, label_face(ctx), ctx%size, state%LABEL_SEP, ctx%color)
            state%PENDING_LABEL = ""
        end if
        call set_inlines(state, doc, k, base_style(ctx))
        call ts_end_par(state%engine)
    end subroutine paragraph

    integer function label_face(ctx)
        type(ctx_t), intent(in) :: ctx
        label_face = FACE_REGULAR
        if (ctx%bold) label_face = FACE_BOLD
    end function label_face

    ! Headings: LaTeX's \section, \subsection and \subsubsection (and,
    ! for a book, \chapter for #).
    subroutine heading(state, doc, node, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: text, num
        type(style_t) :: st
        real(dp) :: ex, size, lead, hang
        type(ts_glue_t) :: before, after
        integer :: lv

        text = doc_plain(doc, node)
        ex = face_xheight(FACE_REGULAR)*state%BASE
        call heading_number(state, doc%nodes(node)%num, lv, num)
        if (state%BOOK .and. lv == 0) then
            call chapter_heading(state, doc, node, text, ctx)
            return
        end if
        if (.not. state%NUMBER_SECTIONS .or. lv > 3) num = ""
        select case (lv)
        case (1)
            size = 1.44_dp*state%BASE
            lead = 18.0_dp*state%BASE/10.0_dp
            before = ts_glue_t(3.5_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(2.3_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case (2)
            size = 1.2_dp*state%BASE
            lead = 14.0_dp*state%BASE/10.0_dp
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case default
            size = state%BASE
            lead = state%LEAD*state%BASE
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        end select
        call ts_addpenalty(state%engine, -300)
        call ts_addvspace(state%engine, before)
        if (state%BOOK .and. lv == 1) then
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
        if (len(num) > 0) hang = text_width(num, FACE_BOLD, size) + size
        call ts_begin_par(state%engine, ALIGN_JUSTIFY, 0.0_dp, left=ctx%left, right=ctx%right, size=size, &
                          leading=lead, hang=hang, nobreak=.true.)
        if (len(num) > 0) then
            call ts_word(state%engine, num, FACE_BOLD, size, ctx%color)
            call ts_kern(state%engine, size)
        end if
        call set_inlines(state, doc, node, st)
        call ts_end_par(state%engine)
        call ts_penalty(state%engine, 10000)
        call ts_vskip(state%engine, after)
        call ts_nobreak_next(state%engine)
        state%NOINDENT = .true.
    end subroutine heading

    ! LaTeX's \chapter in the book class: a new page, "Chapter n" and the
    ! title below it in large bold, and the chapter as the running head.
    subroutine chapter_heading(state, doc, node, text, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        call ts_page_break(state%engine)
        ! The running heads are the book class's: in capitals,
        ! "CHAPTER 1. TITLE" and "1.2. SECTION".
        if (state%NUMBER_SECTIONS) then
            call ts_mark(state%engine, upper("Chapter "//itoa(state%CHAPTER)//".  "//text), .true.)
        else
            call ts_mark(state%engine, upper(text), .true.)
        end if
        call ts_vkeep(state%engine, ts_glue_t(50.0_dp*state%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        st = base_style(ctx)
        st%bold = .true.
        if (state%NUMBER_SECTIONS) then
            st%size = 2.074_dp*state%BASE
            call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, size=st%size, leading=25.0_dp*state%BASE/10.0_dp, &
                              skip=.false., nobreak=.true.)
            call set_words(state, "Chapter "//itoa(state%CHAPTER), st)
            call ts_end_par(state%engine)
            call ts_penalty(state%engine, 10000)
            call ts_vskip(state%engine, ts_glue_t(20.0_dp*state%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        end if
        st%size = 2.488_dp*state%BASE
        call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, size=st%size, leading=30.0_dp*state%BASE/10.0_dp, &
                          skip=.false., nobreak=.true.)
        call set_inlines(state, doc, node, st)
        call ts_end_par(state%engine)
        call ts_penalty(state%engine, 10000)
        call ts_vskip(state%engine, ts_glue_t(40.0_dp*state%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        call ts_nobreak_next(state%engine)
        state%NOINDENT = .true.
    end subroutine chapter_heading

    ! A list: LaTeX's itemize or enumerate, with its spacing at the depth
    ! it is at. A tight list (no blank lines between its items) is set as
    ! Pandoc's \tightlist sets it, without \itemsep and \parsep.
    recursive subroutine list_block(state, doc, list, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: list
        type(ctx_t), intent(in) :: ctx
        integer :: lev, kind, num, nitem, it
        type(ctx_t) :: sub
        type(ts_glue_t) :: topsep, partopsep, itemsep, parsep
        real(dp) :: lm, f

        f = state%BASE/10.0_dp
        lev = min(ctx%depth + 1, 4)
        select case (lev)
        case (1)
            topsep = ts_glue_t(8.0_dp*f, 2.0_dp*f, 4.0_dp*f, 0, 0)
            parsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.5_dp*state%BASE
        case (2)
            topsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.2_dp*state%BASE
        case (3)
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.87_dp*state%BASE
        case default
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.7_dp*state%BASE
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
            call ts_addpenalty(state%engine, -51)
            call ts_addvspace(state%engine, add_glue(topsep, partopsep))
        else
            call ts_end_par(state%engine)
            call ts_addpenalty(state%engine, -51)
            call ts_addvspace(state%engine, topsep)
        end if

        num = doc%nodes(list)%num
        nitem = 0
        it = doc%nodes(list)%first
        do while (it > 0)
            nitem = nitem + 1
            if (nitem > 1) then
                call ts_addpenalty(state%engine, -51)
                call ts_addvspace(state%engine, itemsep)
            end if
            state%PENDING_LABEL = list_label(kind, merge(sub%ilev, sub%elev, kind == 0), num)
            state%LABEL_SEP = 0.5_dp*state%BASE
            call ts_set_parskip(state%engine, parsep)
            call set_blocks(state, doc, it, sub)
            if (len(state%PENDING_LABEL) > 0) then
                ! An item with no paragraph of its own still has its label.
                call ts_begin_par(state%engine, sub%align, 0.0_dp, left=sub%left, right=sub%right, &
                                  size=sub%size)
                call ts_label(state%engine, state%PENDING_LABEL, FACE_REGULAR, sub%size, state%LABEL_SEP, sub%color)
                call ts_strut(state%engine, 0.7_dp*sub%size, 0.3_dp*sub%size)
                call ts_end_par(state%engine)
                state%PENDING_LABEL = ""
            end if
            num = num + 1
            it = doc%nodes(it)%next
        end do
        call ts_end_par(state%engine)
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        if (ctx%depth > 0) call ts_set_parskip(state%engine, parsep_of(state, ctx%depth))
        call ts_addpenalty(state%engine, -51)
        if (ctx%depth == 0) then
            call ts_addvspace(state%engine, add_glue(topsep, partopsep))
        else
            call ts_addvspace(state%engine, topsep)
        end if
    end subroutine list_block

    ! A block quote: LaTeX's quote environment, a list with no label and
    ! equal margins.
    recursive subroutine quote_block(state, doc, node, ctx)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        type(ctx_t) :: sub
        sub = ctx
        sub%depth = ctx%depth + 1
        sub%left = ctx%left + 2.5_dp*state%BASE
        sub%right = ctx%right + 2.5_dp*state%BASE
        sub%indent = .false.
        call ts_end_par(state%engine)
        call ts_addpenalty(state%engine, -51)
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(state%engine, parsep_of(state, sub%depth))
        call set_blocks(state, doc, node, sub)
        call ts_end_par(state%engine)
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        if (ctx%depth > 0) call ts_set_parskip(state%engine, parsep_of(state, ctx%depth))
        call ts_addpenalty(state%engine, -51)
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
    end subroutine quote_block

    ! Code: each line (each ending with a newline) as it is, unbroken, its
    ! spaces kept.
    subroutine code_block(state, text, ctx)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        integer :: a, b, i, j
        real(dp) :: sp
        character(len=:), allocatable :: s
        call ts_end_par(state%engine)
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(state%engine, ts_glue_t())
        sp = text_width(" ", FACE_REGULAR, 0.9_dp*ctx%size)
        a = 1
        do while (a <= len(text))
            b = index(text(a:), NL)
            if (b == 0) b = len(text) - a + 2
            s = text(a:a + b - 2)
            a = a + b
            call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, left=ctx%left + 1.5_dp*state%BASE, &
                              right=ctx%right, size=0.9_dp*ctx%size, leading=state%LEAD*ctx%size)
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
                call ts_word(state%engine, s(i:j - 1), FACE_REGULAR, 0.9_dp*ctx%size, CODE_COL)
                i = j
            end do
            call ts_end_par(state%engine)
        end do
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
    end subroutine code_block

    ! A TeX command on a line by itself: \newpage, \pagebreak,
    ! \clearpage, \vfill, \bigskip, \medskip, \smallskip, \vspace{...} and
    ! \vspace*{...}.
    subroutine raw_block(state, t, ctx)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: t
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: arg
        integer :: a, b
        real(dp) :: f
        f = state%BASE/10.0_dp
        call ts_end_par(state%engine)
        if (starts(t, BS//"newpage") .or. starts(t, BS//"pagebreak") .or. &
            starts(t, BS//"clearpage")) then
            call ts_page_break(state%engine)
            state%NOINDENT = .false.
        else if (starts(t, BS//"vfill")) then
            call ts_vfil(state%engine)
        else if (starts(t, BS//"bigskip")) then
            call ts_vskip(state%engine, ts_glue_t(12.0_dp*f, 4.0_dp*f, 4.0_dp*f, 0, 0))
        else if (starts(t, BS//"medskip")) then
            call ts_vskip(state%engine, ts_glue_t(6.0_dp*f, 2.0_dp*f, 2.0_dp*f, 0, 0))
        else if (starts(t, BS//"smallskip")) then
            call ts_vskip(state%engine, ts_glue_t(3.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0))
        else if (starts(t, BS//"vspace")) then
            a = index(t, "{")
            b = index(t, "}", back=.true.)
            if (a > 0 .and. b > a) then
                arg = trim(adjustl(t(a + 1:b - 1)))
                if (index(t(1:a), "*") > 0) then
                    call ts_vkeep(state%engine, skip_of(arg, ctx%size))
                else
                    call ts_vskip(state%engine, skip_of(arg, ctx%size))
                end if
            end if
        end if
    end subroutine raw_block

    ! The settings of a div with attributes a; aligns is 1 when it sets an
    ! alignment.
    function div_ctx(state, a, ctx, aligns) result(sub)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: a
        type(ctx_t), intent(in) :: ctx
        integer, intent(out) :: aligns
        type(ctx_t) :: sub
        sub = ctx
        sub%align = -1
        call apply_attrs(state, a, sub%align, sub%size, sub%color, sub%bold, sub%italic, ctx%size)
        aligns = merge(1, 0, sub%align >= 0)
        if (sub%align < 0) sub%align = ctx%align
        if (sub%align /= ALIGN_JUSTIFY) sub%indent = .false.
    end function div_ctx

    function parsep_of(state, depth) result(g)
        type(layout_context_t), intent(inout) :: state
        integer, intent(in) :: depth
        type(ts_glue_t) :: g
        real(dp) :: f
        f = state%BASE/10.0_dp
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

    ! A length or \fill as glue.
    function skip_of(arg, size) result(g)
        character(len=*), intent(in) :: arg
        real(dp), intent(in) :: size
        type(ts_glue_t) :: g
        if (arg == BS//"fill" .or. arg == BS//"vfill" .or. arg == BS//"stretch{1}") then
            g = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0)
        else
            g = ts_glue_t(length(arg, size), 0.0_dp, 0.0_dp, 0, 0)
        end if
    end function skip_of

    ! Attributes of a div or a span: classes (.center, .right, .left,
    ! .justify, .bold, .italic, .upright, and LaTeX's size names .small to .Huge)
    ! and key=value pairs (size, color).
    subroutine apply_attrs(state, a, align, size, color, bold, italic, base_size)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: a
        integer, intent(inout) :: align, color(3)
        real(dp), intent(inout) :: size
        logical, intent(inout) :: bold, italic
        real(dp), intent(in) :: base_size
        integer :: i, j, e
        character(len=:), allocatable :: w, k, v
        i = 1
        do while (i <= len(a))
            if (a(i:i) == " ") then
                i = i + 1
                cycle
            end if
            j = i
            do while (j <= len(a))
                if (a(j:j) == " ") exit
                if (a(j:j) == '"') then
                    j = j + 1
                    do while (j <= len(a))
                        if (a(j:j) == '"') exit
                        j = j + 1
                    end do
                end if
                j = j + 1
            end do
            w = a(i:min(j - 1, len(a)))
            i = j
            ! A bare word is a class, as Pandoc reads ::: right.
            if (w(1:1) /= "." .and. index(w, "=") == 0) w = "."//w
            if (w(1:1) == ".") then
                select case (w(2:))
                case ("center", "centering")
                    align = ALIGN_CENTER
                case ("right", "flushright", "raggedleft")
                    align = ALIGN_RIGHT
                case ("left", "flushleft", "raggedright")
                    align = ALIGN_LEFT
                case ("justify")
                    align = ALIGN_JUSTIFY
                case ("bold", "strong")
                    bold = .true.
                case ("italic", "emph")
                    italic = .true.
                case ("upright")
                    italic = .false.
                case ("tiny")
                    size = 0.5_dp*state%BASE
                case ("scriptsize")
                    size = 0.7_dp*state%BASE
                case ("footnotesize")
                    size = 0.8_dp*state%BASE
                case ("small")
                    size = 0.9_dp*state%BASE
                case ("normalsize")
                    size = state%BASE
                case ("large")
                    size = 1.2_dp*state%BASE
                case ("Large")
                    size = 1.44_dp*state%BASE
                case ("LARGE")
                    size = 1.728_dp*state%BASE
                case ("huge")
                    size = 2.074_dp*state%BASE
                case ("Huge")
                    size = 2.488_dp*state%BASE
                end select
            else
                e = index(w, "=")
                if (e == 0) cycle
                k = lower(w(1:e - 1))
                v = unquote(w(e + 1:))
                select case (k)
                case ("size", "font-size", "fontsize")
                    size = length(v, base_size)
                case ("color", "colour")
                    color = color_of(v, color)
                case ("align")
                    align = align_of(lower(v), align)
                end select
            end if
        end do
    end subroutine apply_attrs

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
    subroutine set_inlines(state, doc, k, st)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        type(style_t), intent(in) :: st
        state%W = ""
        state%SPACE = .false.
        call walk(state, doc, k, st)
        call flush(state, st)
    end subroutine set_inlines

    ! Words in style st, a space between each two.
    subroutine set_words(state, s, st)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: s
        type(style_t), intent(in) :: st
        integer :: i, j
        i = 1
        do while (i <= len(s))
            j = index(s(i:), " ")
            if (j == 0) then
                j = len(s) + 1
            else
                j = i + j - 1
            end if
            if (i > 1) call ts_space(state%engine, face_of(st), st%size)
            call ts_word(state%engine, s(i:j - 1), face_of(st), st%size, st%color)
            i = j + 1
        end do
    end subroutine set_words

    ! The children of node parent, in style st. A word goes out when
    ! something else than text comes, after the space before it.
    recursive subroutine walk(state, doc, parent, st)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(style_t), intent(in) :: st
        type(style_t) :: sx
        character(len=:), allocatable :: tag
        integer :: c, al

        c = doc%nodes(parent)%first
        do while (c > 0)
            associate (nd => doc%nodes(c))
                select case (nd%kind)
                case (IN_STR)
                    call add_text(state, nd%text, st)
                case (IN_SPACE)
                    call flush(state, st)
                    if (.not. state%SPACE) then
                        state%SP_FACE = face_of(st)
                        state%SP_SIZE = st%size
                    end if
                    state%SPACE = .true.
                case (IN_BREAK)
                    call flush(state, st)
                    call ts_hard_break(state%engine)
                    state%SPACE = .false.
                case (IN_EMPH, IN_STRONG, IN_SPAN, IN_LINK)
                    call flush(state, st)
                    sx = st
                    select case (nd%kind)
                    case (IN_EMPH)
                        sx%italic = .not. st%italic
                    case (IN_STRONG)
                        sx%bold = .true.
                    case (IN_SPAN)
                        al = ALIGN_JUSTIFY
                        call apply_attrs(state, nd%attr, al, sx%size, sx%color, sx%bold, sx%italic, &
                                         st%size)
                    case (IN_LINK)
                        sx%color = LINK_COL
                    end select
                    call walk(state, doc, c, sx)
                    call flush(state, sx)
                case (IN_CODE)
                    call flush(state, st)
                    call flush_space(state)
                    call set_code(state, nd%text, st%size)
                case (IN_MATH)
                    call flush(state, st)
                    if (nd%display) then
                        tag = display_tag(state, doc, c)
                        call ts_math(state%engine, strip_math_labels(nd%text), st%size, st%color, &
                                     display=.true., tag=tag)
                        state%SPACE = .false.
                    else
                        call flush_space(state)
                        call ts_math(state%engine, nd%text, st%size, st%color)
                    end if
                case (IN_RAW)
                    select case (nd%text)
                    case ("hfill")
                        call flush(state, st)
                        call ts_hfil(state%engine)
                        state%SPACE = .false.
                    case ("quad", "qquad")
                        call flush(state, st)
                        call ts_kern(state%engine, merge(1.0_dp, 2.0_dp, nd%text == "quad")*st%size)
                        state%SPACE = .false.
                    case ("TeX", "LaTeX")
                        call flush(state, st)
                        call flush_space(state)
                        call tex_logo(state, st, nd%text == "LaTeX")
                    end select
                case (IN_REF)
                    state%W = state%W//ref_text(state, nd%id, nd%num)
                end select
            end associate
            c = doc%nodes(c)%next
        end do
    end subroutine walk

    ! Text onto the word; a no-break space is glue that does not break.
    subroutine add_text(state, s, st)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: s
        type(style_t), intent(in) :: st
        integer :: i, j
        i = 1
        do
            j = index(s(i:), NBSP)
            if (j == 0) exit
            state%W = state%W//s(i:i + j - 2)
            call flush(state, st)
            call ts_nbsp(state%engine, face_of(st), st%size)
            state%SPACE = .false.
            i = i + j + 1
        end do
        state%W = state%W//s(i:)
    end subroutine add_text

    ! The word so far goes out, after a space if one came before it.
    subroutine flush(state, st)
        type(layout_context_t), intent(inout) :: state
        type(style_t), intent(in) :: st
        if (len(state%W) == 0) return
        call flush_space(state)
        call ts_word(state%engine, state%W, face_of(st), st%size, st%color)
        state%W = ""
    end subroutine flush

    subroutine flush_space(state)
        type(layout_context_t), intent(inout) :: state
        if (state%SPACE) call ts_space(state%engine, state%SP_FACE, state%SP_SIZE)
        state%SPACE = .false.
    end subroutine flush_space

    ! Code, as it is: its words upright, its spaces glue.
    subroutine set_code(state, t, size)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: t
        real(dp), intent(in) :: size
        integer :: i, j
        i = 1
        do while (i <= len(t))
            if (t(i:i) == " ") then
                call ts_space(state%engine, FACE_REGULAR, size)
                i = i + 1
                cycle
            end if
            j = i
            do while (j <= len(t))
                if (t(j:j) == " ") exit
                j = j + 1
            end do
            call ts_word(state%engine, t(i:j - 1), FACE_REGULAR, size, CODE_COL)
            i = j
        end do
    end subroutine set_code

    ! The TeX and LaTeX logos, as plain TeX and LaTeX draw them.
    subroutine tex_logo(state, st, la)
        type(layout_context_t), intent(inout) :: state
        type(style_t), intent(in) :: st
        logical, intent(in) :: la
        real(dp) :: em, ex
        integer :: f
        f = face_of(st)
        em = st%size
        ex = face_xheight(FACE_REGULAR)*st%size
        if (la) then
            ! The A at the script size, its top at the T's.
            call ts_word(state%engine, "L", f, st%size, st%color)
            call ts_kern(state%engine, -0.36_dp*em)
            call ts_word(state%engine, "A", f, 0.7_dp*st%size, st%color, &
                         raise=0.3_dp*face_capheight(FACE_REGULAR)*st%size)
            call ts_kern(state%engine, -0.15_dp*em)
        end if
        call ts_word(state%engine, "T", f, st%size, st%color)
        call ts_kern(state%engine, -0.1667_dp*em)
        call ts_word(state%engine, "E", f, st%size, st%color, raise=-0.5_dp*ex)
        call ts_kern(state%engine, -0.125_dp*em)
        call ts_word(state%engine, "X", f, st%size, st%color)
    end subroutine tex_logo

    ! The formula without \label{...}, \tag{...}, \notag and \nonumber,
    ! which are for the numbering.
    function strip_math_labels(src) result(r)
        character(len=*), intent(in) :: src
        character(len=:), allocatable :: r
        integer :: a, b
        r = src
        do
            a = index(r, BS//"label{")
            if (a == 0) a = index(r, BS//"tag{")
            if (a == 0) exit
            b = index(r(a:), "}")
            if (b == 0) exit
            r = r(1:a - 1)//r(a + b:)
        end do
        do
            a = index(r, BS//"notag")
            if (a == 0) exit
            r = r(1:a - 1)//r(a + 6:)
        end do
        do
            a = index(r, BS//"nonumber")
            if (a == 0) exit
            r = r(1:a - 1)//r(a + 9:)
        end do
    end function strip_math_labels

    ! ------------------------------------------------------------------
    ! Numbers and cross references.
    ! ------------------------------------------------------------------

    ! The number of the next heading of the level: lv is its depth among
    ! sections (0 for a chapter of a book), num its number, 1.2.3 (empty
    ! below \subsubsection's level).
    subroutine heading_number(state, level, lv, num)
        type(layout_context_t), intent(inout) :: state
        integer, intent(in) :: level
        integer, intent(out) :: lv
        character(len=:), allocatable, intent(out) :: num
        integer :: k
        lv = level
        if (state%BOOK) lv = level - 1
        num = ""
        if (lv == 0) then
            state%CHAPTER = state%CHAPTER + 1
            state%SEC = 0
            state%EQNO = 0
            num = itoa(state%CHAPTER)
            return
        end if
        if (lv > 4) return
        state%SEC(lv) = state%SEC(lv) + 1
        state%SEC(lv + 1:) = 0
        if (state%BOOK) then
            num = itoa(state%CHAPTER)
        else
            num = itoa(state%SEC(1))
        end if
        do k = merge(1, 2, state%BOOK), lv
            num = num//"."//itoa(state%SEC(k))
        end do
    end subroutine heading_number

    ! The tag of displayed formula k: its \tag{t}, or its number when it is
    ! numbered: in a document with numberequations, or with an {#id} after
    ! it or \label{name} in it, but not with \notag or \nonumber. Within a
    ! book, formulas are numbered by chapter.
    function display_tag(state, doc, k) result(tag)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        character(len=:), allocatable :: tag
        character(len=:), allocatable :: src
        integer :: a, b
        logical :: numbered
        src = doc%nodes(k)%text
        tag = ""
        numbered = state%NUMBER_EQS .or. doc%nodes(k)%num == 1
        if (index(src, BS//"label{") > 0) numbered = .true.
        if (index(src, BS//"notag") > 0 .or. index(src, BS//"nonumber") > 0) numbered = .false.
        a = index(src, BS//"tag{")
        if (a > 0) then
            b = index(src(a:), "}")
            tag = src(a + 5:a + b - 2)
            return
        end if
        if (numbered) then
            state%EQNO = state%EQNO + 1
            if (state%BOOK) then
                tag = itoa(state%CHAPTER)//"."//itoa(state%EQNO)
            else
                tag = itoa(state%EQNO)
            end if
        end if
    end function display_tag

    ! The labels of the headings and displays under node parent, with
    ! their numbers, found before anything is set, so that a reference may
    ! come before what it refers to.
    recursive subroutine labels(state, doc, parent)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        character(len=:), allocatable :: num, name, src
        integer :: c, lv, a, b
        c = doc%nodes(parent)%first
        do while (c > 0)
            select case (doc%nodes(c)%kind)
            case (DOC_HEADING)
                call heading_number(state, doc%nodes(c)%num, lv, num)
                if (len(doc%nodes(c)%id) > 0 .and. len(num) > 0) &
                    call add_label(state, doc%nodes(c)%id, num)
            case (IN_MATH)
                if (doc%nodes(c)%display) then
                    num = display_tag(state, doc, c)
                    name = doc%nodes(c)%id
                    src = doc%nodes(c)%text
                    a = index(src, BS//"label{")
                    if (a > 0) then
                        b = index(src(a:), "}")
                        if (b > 0) name = src(a + 7:a + b - 2)
                    end if
                    if (len(name) > 0 .and. len(num) > 0) call add_label(state, name, num)
                end if
            case (DOC_FIGURE, DOC_TABLE)
                if (len(doc%nodes(c)%id) > 0) call add_label(state, doc%nodes(c)%id, doc%nodes(c)%number)
                call labels(state, doc, c)
            case default
                call labels(state, doc, c)
            end select
            c = doc%nodes(c)%next
        end do
    end subroutine labels

    ! How a reference to name is written: its number, in parentheses for
    ! \eqref and @eq:name; ?? for an unknown \ref, @name as it is.
    function ref_text(state, name, form) result(s)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: name
        integer, intent(in) :: form
        character(len=:), allocatable :: s
        integer :: k
        k = find_label(state, name)
        if (k == 0) then
            if (form == REF_AT) then
                s = "@"//name
            else
                s = "??"
            end if
        else if (form == REF_EQ .or. (form == REF_AT .and. starts(name, "eq:"))) then
            s = "("//state%label(k)%text//")"
        else
            s = state%label(k)%text
        end if
    end function ref_text

    subroutine add_label(state, name, text)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: name, text
        type(label_t), allocatable :: tmp(:)
        integer :: k
        do k = 1, state%NLAB
            if (state%label(k)%name == name) error stop "document: duplicate label"
        end do
        if (state%NLAB == size(state%label)) then
            allocate (tmp(2*size(state%label)))
            do k = 1, state%NLAB
                call move_alloc(state%label(k)%name, tmp(k)%name)
                call move_alloc(state%label(k)%text, tmp(k)%text)
            end do
            call move_alloc(tmp, state%label)
        end if
        state%NLAB = state%NLAB + 1
        state%label(state%NLAB)%name = name
        state%label(state%NLAB)%text = text
    end subroutine add_label

    integer function find_label(state, name)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: name
        integer :: k
        find_label = 0
        do k = 1, state%NLAB
            if (state%label(k)%name == name) then
                find_label = k
                return
            end if
        end do
    end function find_label

    ! ------------------------------------------------------------------
    ! Small things.
    ! ------------------------------------------------------------------

    pure logical function starts(s, p)
        character(len=*), intent(in) :: s, p
        starts = .false.
        if (len(s) < len(p)) return
        starts = s(1:len(p)) == p
    end function starts

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

    function lower(s) result(t)
        character(len=*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: k
        t = s
        do k = 1, len(s)
            if (t(k:k) >= "A" .and. t(k:k) <= "Z") t(k:k) = achar(iachar(t(k:k)) + 32)
        end do
    end function lower

    function unquote(s) result(t)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t
        t = trim(s)
        if (len(t) >= 2) then
            if ((t(1:1) == '"' .and. t(len(t):len(t)) == '"') .or. &
                (t(1:1) == "'" .and. t(len(t):len(t)) == "'")) t = t(2:len(t) - 1)
        end if
    end function unquote

    logical function truth(s)
        character(len=*), intent(in) :: s
        truth = lower(trim(s)) == "true" .or. lower(trim(s)) == "yes" .or. trim(s) == "1"
    end function truth

    integer function align_of(v, dflt)
        character(len=*), intent(in) :: v
        integer, intent(in) :: dflt
        select case (v)
        case ("justify", "justified")
            align_of = ALIGN_JUSTIFY
        case ("left", "raggedright")
            align_of = ALIGN_LEFT
        case ("center", "centre")
            align_of = ALIGN_CENTER
        case ("right", "raggedleft")
            align_of = ALIGN_RIGHT
        case default
            align_of = dflt
        end select
    end function align_of

    ! A colour: #rrggbb, #rgb, or one of matplotlib's names.
    function color_of(v, dflt) result(rgb)
        character(len=*), intent(in) :: v
        integer, intent(in) :: dflt(3)
        integer :: rgb(3)
        character(len=7) :: h
        character(len=:), allocatable :: t
        integer :: ios, c
        rgb = dflt
        t = trim(adjustl(v))
        if (len(t) == 0) return
        if (t(1:1) == "#" .and. len(t) == 4) then
            t = "#"//t(2:2)//t(2:2)//t(3:3)//t(3:3)//t(4:4)//t(4:4)
        end if
        if (t(1:1) /= "#") then
            h = color_from_name(t)
            if (len_trim(h) == 0) return
            t = h
        end if
        if (len(t) /= 7) return
        read (t(2:7), "(Z6)", iostat=ios) c
        if (ios == 0) rgb = [ishft(c, -16), iand(ishft(c, -8), 255), iand(c, 255)]
    end function color_of

    ! A number, for keys that take one.
    real(dp) function number(v, dflt)
        character(len=*), intent(in) :: v
        real(dp), intent(in) :: dflt
        integer :: ios
        read (v, *, iostat=ios) number
        if (ios /= 0) number = dflt
    end function number

    ! A length in points: a number with pt, bp, in, cm, mm, em or ex (an
    ! em being size), a bare number in points.
    real(dp) function length(v, size)
        character(len=*), intent(in) :: v
        real(dp), intent(in) :: size
        character(len=:), allocatable :: t, u
        integer :: k, ios
        real(dp) :: x
        t = trim(adjustl(v))
        length = 0.0_dp
        k = len(t)
        do while (k > 0)
            if (index("0123456789.-+", t(k:k)) > 0) exit
            k = k - 1
        end do
        if (k == 0) return
        read (t(1:k), *, iostat=ios) x
        if (ios /= 0) return
        u = trim(adjustl(t(k + 1:)))
        select case (u)
        case ("in")
            length = 72.0_dp*x
        case ("cm")
            length = 72.0_dp/2.54_dp*x
        case ("mm")
            length = 72.0_dp/25.4_dp*x
        case ("em")
            length = size*x
        case ("ex")
            length = face_xheight(FACE_REGULAR)*size*x
        case default
            length = x
        end select
    end function length

    ! LaTeX's glue scaled from its 10pt values to the body size.
    function scale(state, g) result(r)
        type(layout_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: g
        type(ts_glue_t) :: r
        real(dp) :: f
        f = state%BASE/10.0_dp
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

    ! The width of a string in a face, as the engine measures words.
    real(dp) function text_width(s, face, size)
        use fplotlib_text, only: tw => text_width
        character(len=*), intent(in) :: s
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        text_width = tw(s, size, face)
    end function text_width

end module fplotlib_docclass
