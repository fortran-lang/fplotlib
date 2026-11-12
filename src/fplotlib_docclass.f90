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
    use fplotlib_typeset
    implicit none
    private

    public :: doc_typeset

    character, parameter :: BS = achar(92), NL = achar(10)
    character(len=2), parameter :: NBSP = achar(194)//achar(160)

    ! The style of inline text.
    type :: style_t
        logical :: bold = .false., italic = .false.
        real(dp) :: size = 10.0_dp
        integer :: color = 0
    end type style_t

    ! Where blocks are being set: their margins, alignment, size and
    ! colour, and how deep in lists they are.
    type :: ctx_t
        real(dp) :: left = 0.0_dp, right = 0.0_dp
        integer :: align = ALIGN_JUSTIFY
        real(dp) :: size = 10.0_dp
        integer :: color = 0
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
    real(dp) :: BASE = 10.0_dp, LEAD = 1.2_dp
    real(dp) :: PARINDENT = 15.0_dp
    type(ts_glue_t) :: PARSKIP_G
    integer :: DOC_ALIGN = ALIGN_JUSTIFY
    logical :: NUMBER_SECTIONS = .false., BOOK = .false., NUMBER_EQS = .false.
    ! The title block's inlines: nodes of the front matter, 0 for none.
    integer :: TITLE = 0, SUBTITLE = 0, DATE = 0, ABSTRACT = 0
    integer :: NAUTHOR = 0, AUTHORS(16)
    integer :: TEXT_COL = 0, PAGE_COL = 16777215
    integer, parameter :: LINK_COL = 1728436, CODE_COL = 5263440

    ! Counters and cross references.
    integer :: SEC(4) = 0, CHAPTER = 0, EQNO = 0
    integer :: NLAB = 0
    character(len=64) :: LAB_NAME(512)
    character(len=24) :: LAB_TEXT(512)

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

contains

    ! ------------------------------------------------------------------
    ! The document.
    ! ------------------------------------------------------------------

    ! Set doc into fplotlib_typeset's pages.
    subroutine doc_typeset(doc)
        type(doc_t), intent(in) :: doc
        type(ctx_t) :: ctx

        call ts_reset()
        call defaults()
        call settings(doc)
        call ts_set_font(BASE, LEAD*BASE)
        call ts_set_parskip(PARSKIP_G)
        call ts_set_colors(TEXT_COL, PAGE_COL)
        call labels(doc, 1)
        SEC = 0
        CHAPTER = 0
        EQNO = 0
        ctx%size = BASE
        ctx%color = TEXT_COL
        ctx%align = DOC_ALIGN
        call title_block(doc, ctx)
        call set_blocks(doc, 1, ctx)
        call ts_paginate()
    end subroutine doc_typeset

    subroutine defaults()
        BASE = 10.0_dp
        LEAD = 1.2_dp
        PARINDENT = -1.0_dp
        PARSKIP_G = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        DOC_ALIGN = ALIGN_JUSTIFY
        NUMBER_SECTIONS = .false.
        NUMBER_EQS = .false.
        BOOK = .false.
        TITLE = 0
        SUBTITLE = 0
        NAUTHOR = 0
        DATE = 0
        ABSTRACT = 0
        TEXT_COL = 0
        PAGE_COL = 16777215
        NLAB = 0
        SEC = 0
        CHAPTER = 0
        EQNO = 0
        NOINDENT = .false.
        PENDING_LABEL = ""
        W = ""
        SPACE = .false.
        call ts_set_page(595.2756_dp, 841.8898_dp, 72.0_dp, 72.0_dp, 72.0_dp, 72.0_dp)
    end subroutine defaults

    ! The settings of the front matter, in its order (a length in ems is
    ! in the font size given before it).
    subroutine settings(doc)
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
                TITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("subtitle")
                SUBTITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("author")
                if (len(val) > 0 .and. NAUTHOR < size(AUTHORS)) then
                    NAUTHOR = NAUTHOR + 1
                    AUTHORS(NAUTHOR) = doc%meta(i)%node
                end if
            case ("date")
                DATE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("abstract")
                ABSTRACT = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("fontsize")
                BASE = length(val, 10.0_dp)
            case ("linestretch", "leading")
                LEAD = 1.2_dp*number(val, 1.0_dp)
            case ("paper", "papersize")
                call paper_size(lower(val), pw, ph)
            case ("margin")
                m = length(val, BASE)
            case ("margin-left")
                ml = length(val, BASE)
            case ("margin-right")
                mr = length(val, BASE)
            case ("margin-top")
                mt = length(val, BASE)
            case ("margin-bottom")
                mb = length(val, BASE)
            case ("indent", "parindent")
                if (lower(val) == "false" .or. lower(val) == "no") then
                    PARINDENT = 0.0_dp
                else if (lower(val) /= "true" .and. lower(val) /= "yes") then
                    PARINDENT = length(val, BASE)
                end if
            case ("parskip")
                PARSKIP_G = ts_glue_t(length(val, BASE), 0.2_dp*length(val, BASE), &
                                      0.0_dp, 0, 0)
                if (PARINDENT < 0.0_dp) PARINDENT = 0.0_dp
            case ("align")
                DOC_ALIGN = align_of(lower(val), ALIGN_JUSTIFY)
            case ("numbersections", "number-sections")
                NUMBER_SECTIONS = truth(val)
            case ("numberequations", "number-equations")
                NUMBER_EQS = truth(val)
            case ("pagenumbers", "page-numbers")
                numbers = truth(val)
            case ("class", "documentclass")
                BOOK = lower(val) == "book"
                heads = BOOK
            case ("color", "fontcolor")
                TEXT_COL = color_of(val, 0)
            case ("pagecolor", "background")
                PAGE_COL = color_of(val, 16777215)
            end select
        end do
        if (PARINDENT < 0.0_dp) PARINDENT = 1.5_dp*BASE
        ! LaTeX's geometry is set here by margins; without them, one inch.
        if (m < 0.0_dp) m = 72.0_dp
        if (ml < 0.0_dp) ml = m
        if (mr < 0.0_dp) mr = m
        if (mt < 0.0_dp) mt = m
        if (mb < 0.0_dp) mb = m
        call ts_set_page(pw, ph, ml, mr, mt, mb, numbers, heads, BOOK)
    end subroutine settings

    subroutine paper_size(v, w, h)
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
                w = length(trim(v(1:x - 1)), BASE)
                h = length(trim(v(x + 1:)), BASE)
            end if
        end select
    end subroutine paper_size

    ! LaTeX's \maketitle and abstract, for the article class.
    subroutine title_block(doc, ctx)
        type(doc_t), intent(in) :: doc
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        integer :: i
        if (TITLE == 0) return
        st = base_style(ctx)
        call ts_vkeep(ts_glue_t(2.0_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        st%size = 1.728_dp*BASE
        call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, leading=22.0_dp*BASE/10.0_dp, &
                          skip=.false.)
        call set_inlines(doc, TITLE, st)
        call ts_end_par()
        if (SUBTITLE > 0) then
            st%size = 1.2_dp*BASE
            call ts_vskip(ts_glue_t(0.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*BASE/10.0_dp, skip=.false.)
            call set_inlines(doc, SUBTITLE, st)
            call ts_end_par()
        end if
        st%size = 1.2_dp*BASE
        if (NAUTHOR > 0) then
            call ts_vskip(ts_glue_t(1.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
            do i = 1, NAUTHOR
                call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                                  leading=14.0_dp*BASE/10.0_dp, skip=.false.)
                call set_inlines(doc, AUTHORS(i), st)
                call ts_end_par()
            end do
        end if
        if (DATE > 0) then
            call ts_vskip(ts_glue_t(BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*BASE/10.0_dp, skip=.false.)
            call set_inlines(doc, DATE, st)
            call ts_end_par()
        end if
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_vskip(ts_glue_t(1.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
        if (ABSTRACT > 0) then
            ! \small, a centred bold heading, and a quotation.
            st = base_style(ctx)
            st%size = 0.9_dp*BASE
            st%bold = .true.
            call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=11.0_dp*BASE/10.0_dp, skip=.false.)
            call set_words("Abstract", st)
            call ts_end_par()
            st%bold = .false.
            call ts_vskip(ts_glue_t(-0.5_dp*st%size + 0.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(ALIGN_JUSTIFY, 1.5_dp*st%size, left=2.5_dp*BASE, &
                              right=2.5_dp*BASE, size=st%size, leading=11.0_dp*BASE/10.0_dp)
            call set_inlines(doc, ABSTRACT, st)
            call ts_end_par()
            call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        end if
        NOINDENT = .false.
    end subroutine title_block

    ! ------------------------------------------------------------------
    ! Blocks.
    ! ------------------------------------------------------------------

    ! The blocks that are the children of node parent.
    recursive subroutine set_blocks(doc, parent, ctx)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(ctx_t), intent(in) :: ctx
        type(ctx_t) :: sub
        integer :: c, aligns

        c = doc%nodes(parent)%first
        do while (c > 0)
            select case (doc%nodes(c)%kind)
            case (DOC_PARA)
                call paragraph(doc, c, ctx)
            case (DOC_HEADING)
                call heading(doc, c, ctx)
            case (DOC_CODE)
                call code_block(doc%nodes(c)%text, ctx)
            case (DOC_DIV)
                ! A div that aligns its text is a LaTeX environment
                ! (center, flushright, flushleft), a list with the space of
                ! one around it; one that only changes the type is a group.
                sub = div_ctx(doc%nodes(c)%attr, ctx, aligns)
                if (aligns > 0) call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                call set_blocks(doc, c, sub)
                call ts_end_par()
                if (aligns > 0) call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            case (DOC_QUOTE)
                call quote_block(doc, c, ctx)
            case (DOC_LIST)
                call list_block(doc, c, ctx)
            case (DOC_RULE)
                call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                call ts_begin_par(ALIGN_CENTER, 0.0_dp, left=ctx%left, right=ctx%right)
                call ts_end_par()
                call ts_rule(0.5_dp*(ts_hsize() - ctx%left - ctx%right), 0.5_dp, ctx%color)
                call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            case (DOC_RAW)
                call raw_block(doc%nodes(c)%text, ctx)
            end select
            c = doc%nodes(c)%next
        end do
    end subroutine set_blocks

    ! A paragraph of inline text in the context's settings.
    subroutine paragraph(doc, k, ctx)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        type(ctx_t), intent(in) :: ctx
        real(dp) :: ind
        integer :: c
        ind = 0.0_dp
        if (ctx%indent .and. .not. NOINDENT .and. ctx%align == ALIGN_JUSTIFY) ind = PARINDENT
        c = doc%nodes(k)%first
        if (c > 0) then
            if (doc%nodes(c)%kind == IN_RAW .and. doc%nodes(c)%text == "noindent") ind = 0.0_dp
        end if
        NOINDENT = .false.
        call ts_begin_par(ctx%align, ind, left=ctx%left, right=ctx%right, size=ctx%size, &
                          leading=LEAD*ctx%size)
        if (len(PENDING_LABEL) > 0) then
            call ts_label(PENDING_LABEL, label_face(ctx), ctx%size, LABEL_SEP, ctx%color)
            PENDING_LABEL = ""
        end if
        call set_inlines(doc, k, base_style(ctx))
        call ts_end_par()
    end subroutine paragraph

    integer function label_face(ctx)
        type(ctx_t), intent(in) :: ctx
        label_face = FACE_REGULAR
        if (ctx%bold) label_face = FACE_BOLD
    end function label_face

    ! Headings: LaTeX's \section, \subsection and \subsubsection (and,
    ! for a book, \chapter for #).
    subroutine heading(doc, node, ctx)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: text, num
        type(style_t) :: st
        real(dp) :: ex, size, lead, hang
        type(ts_glue_t) :: before, after
        integer :: lv

        text = doc_plain(doc, node)
        ex = face_xheight(FACE_REGULAR)*BASE
        call heading_number(doc%nodes(node)%num, lv, num)
        if (BOOK .and. lv == 0) then
            call chapter_heading(doc, node, text, ctx)
            return
        end if
        if (.not. NUMBER_SECTIONS .or. lv > 3) num = ""
        select case (lv)
        case (1)
            size = 1.44_dp*BASE
            lead = 18.0_dp*BASE/10.0_dp
            before = ts_glue_t(3.5_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(2.3_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case (2)
            size = 1.2_dp*BASE
            lead = 14.0_dp*BASE/10.0_dp
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case default
            size = BASE
            lead = LEAD*BASE
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        end select
        call ts_addpenalty(-300)
        call ts_addvspace(before)
        if (BOOK .and. lv == 1) then
            if (len(num) > 0) then
                call ts_mark(upper(num//".  "//text), .false., section=.true.)
            else
                call ts_mark(upper(text), .false., section=.true.)
            end if
        end if
        st = base_style(ctx)
        st%bold = .true.
        st%size = size
        hang = 0.0_dp
        if (len(num) > 0) hang = text_width(num, FACE_BOLD, size) + size
        call ts_begin_par(ALIGN_JUSTIFY, 0.0_dp, left=ctx%left, right=ctx%right, size=size, &
                          leading=lead, hang=hang, nobreak=.true.)
        if (len(num) > 0) then
            call ts_word(num, FACE_BOLD, size, ctx%color)
            call ts_kern(size)
        end if
        call set_inlines(doc, node, st)
        call ts_end_par()
        call ts_penalty(10000)
        call ts_vskip(after)
        call ts_nobreak_next()
        NOINDENT = .true.
    end subroutine heading

    ! LaTeX's \chapter in the book class: a new page, "Chapter n" and the
    ! title below it in large bold, and the chapter as the running head.
    subroutine chapter_heading(doc, node, text, ctx)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        call ts_page_break()
        ! The running heads are the book class's: in capitals,
        ! "CHAPTER 1. TITLE" and "1.2. SECTION".
        if (NUMBER_SECTIONS) then
            call ts_mark(upper("Chapter "//itoa(CHAPTER)//".  "//text), .true.)
        else
            call ts_mark(upper(text), .true.)
        end if
        call ts_vkeep(ts_glue_t(50.0_dp*BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        st = base_style(ctx)
        st%bold = .true.
        if (NUMBER_SECTIONS) then
            st%size = 2.074_dp*BASE
            call ts_begin_par(ALIGN_LEFT, 0.0_dp, size=st%size, leading=25.0_dp*BASE/10.0_dp, &
                              skip=.false., nobreak=.true.)
            call set_words("Chapter "//itoa(CHAPTER), st)
            call ts_end_par()
            call ts_penalty(10000)
            call ts_vskip(ts_glue_t(20.0_dp*BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        end if
        st%size = 2.488_dp*BASE
        call ts_begin_par(ALIGN_LEFT, 0.0_dp, size=st%size, leading=30.0_dp*BASE/10.0_dp, &
                          skip=.false., nobreak=.true.)
        call set_inlines(doc, node, st)
        call ts_end_par()
        call ts_penalty(10000)
        call ts_vskip(ts_glue_t(40.0_dp*BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        call ts_nobreak_next()
        NOINDENT = .true.
    end subroutine chapter_heading

    ! A list: LaTeX's itemize or enumerate, with its spacing at the depth
    ! it is at. A tight list (no blank lines between its items) is set as
    ! Pandoc's \tightlist sets it, without \itemsep and \parsep.
    recursive subroutine list_block(doc, list, ctx)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: list
        type(ctx_t), intent(in) :: ctx
        integer :: lev, kind, num, nitem, it
        type(ctx_t) :: sub
        type(ts_glue_t) :: topsep, partopsep, itemsep, parsep
        real(dp) :: lm, f

        f = BASE/10.0_dp
        lev = min(ctx%depth + 1, 4)
        select case (lev)
        case (1)
            topsep = ts_glue_t(8.0_dp*f, 2.0_dp*f, 4.0_dp*f, 0, 0)
            parsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.5_dp*BASE
        case (2)
            topsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.2_dp*BASE
        case (3)
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.87_dp*BASE
        case default
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.7_dp*BASE
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
        if (doc%nodes(list)%spaced .and. .not. ts_in_par()) then
            call ts_addpenalty(-51)
            call ts_addvspace(add_glue(topsep, partopsep))
        else
            call ts_end_par()
            call ts_addpenalty(-51)
            call ts_addvspace(topsep)
        end if

        num = doc%nodes(list)%num
        nitem = 0
        it = doc%nodes(list)%first
        do while (it > 0)
            nitem = nitem + 1
            if (nitem > 1) then
                call ts_addpenalty(-51)
                call ts_addvspace(itemsep)
            end if
            PENDING_LABEL = list_label(kind, merge(sub%ilev, sub%elev, kind == 0), num)
            LABEL_SEP = 0.5_dp*BASE
            call ts_set_parskip(parsep)
            call set_blocks(doc, it, sub)
            if (len(PENDING_LABEL) > 0) then
                ! An item with no paragraph of its own still has its label.
                call ts_begin_par(sub%align, 0.0_dp, left=sub%left, right=sub%right, &
                                  size=sub%size)
                call ts_label(PENDING_LABEL, FACE_REGULAR, sub%size, LABEL_SEP, sub%color)
                call ts_strut(0.7_dp*sub%size, 0.3_dp*sub%size)
                call ts_end_par()
                PENDING_LABEL = ""
            end if
            num = num + 1
            it = doc%nodes(it)%next
        end do
        call ts_end_par()
        call ts_set_parskip(PARSKIP_G)
        if (ctx%depth > 0) call ts_set_parskip(parsep_of(ctx%depth))
        call ts_addpenalty(-51)
        if (ctx%depth == 0) then
            call ts_addvspace(add_glue(topsep, partopsep))
        else
            call ts_addvspace(topsep)
        end if
    end subroutine list_block

    ! A block quote: LaTeX's quote environment, a list with no label and
    ! equal margins.
    recursive subroutine quote_block(doc, node, ctx)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: node
        type(ctx_t), intent(in) :: ctx
        type(ctx_t) :: sub
        sub = ctx
        sub%depth = ctx%depth + 1
        sub%left = ctx%left + 2.5_dp*BASE
        sub%right = ctx%right + 2.5_dp*BASE
        sub%indent = .false.
        call ts_end_par()
        call ts_addpenalty(-51)
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(parsep_of(sub%depth))
        call set_blocks(doc, node, sub)
        call ts_end_par()
        call ts_set_parskip(PARSKIP_G)
        if (ctx%depth > 0) call ts_set_parskip(parsep_of(ctx%depth))
        call ts_addpenalty(-51)
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
    end subroutine quote_block

    ! Code: each line (each ending with a newline) as it is, unbroken, its
    ! spaces kept.
    subroutine code_block(text, ctx)
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        integer :: a, b, i, j
        real(dp) :: sp
        character(len=:), allocatable :: s
        call ts_end_par()
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(ts_glue_t())
        sp = text_width(" ", FACE_REGULAR, 0.9_dp*ctx%size)
        a = 1
        do while (a <= len(text))
            b = index(text(a:), NL)
            if (b == 0) b = len(text) - a + 2
            s = text(a:a + b - 2)
            a = a + b
            call ts_begin_par(ALIGN_LEFT, 0.0_dp, left=ctx%left + 1.5_dp*BASE, &
                              right=ctx%right, size=0.9_dp*ctx%size, leading=LEAD*ctx%size)
            call ts_strut(0.7_dp*ctx%size, 0.3_dp*ctx%size)
            i = 1
            do while (i <= len(s))
                if (s(i:i) == " ") then
                    call ts_kern(sp)
                    i = i + 1
                    cycle
                end if
                j = i
                do while (j <= len(s))
                    if (s(j:j) == " ") exit
                    j = j + 1
                end do
                call ts_word(s(i:j - 1), FACE_REGULAR, 0.9_dp*ctx%size, CODE_COL)
                i = j
            end do
            call ts_end_par()
        end do
        call ts_set_parskip(PARSKIP_G)
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
    end subroutine code_block

    ! A TeX command on a line by itself: \newpage, \pagebreak,
    ! \clearpage, \vfill, \bigskip, \medskip, \smallskip, \vspace{...} and
    ! \vspace*{...}.
    subroutine raw_block(t, ctx)
        character(len=*), intent(in) :: t
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: arg
        integer :: a, b
        real(dp) :: f
        f = BASE/10.0_dp
        call ts_end_par()
        if (starts(t, BS//"newpage") .or. starts(t, BS//"pagebreak") .or. &
            starts(t, BS//"clearpage")) then
            call ts_page_break()
            NOINDENT = .false.
        else if (starts(t, BS//"vfill")) then
            call ts_vfil()
        else if (starts(t, BS//"bigskip")) then
            call ts_vskip(ts_glue_t(12.0_dp*f, 4.0_dp*f, 4.0_dp*f, 0, 0))
        else if (starts(t, BS//"medskip")) then
            call ts_vskip(ts_glue_t(6.0_dp*f, 2.0_dp*f, 2.0_dp*f, 0, 0))
        else if (starts(t, BS//"smallskip")) then
            call ts_vskip(ts_glue_t(3.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0))
        else if (starts(t, BS//"vspace")) then
            a = index(t, "{")
            b = index(t, "}", back=.true.)
            if (a > 0 .and. b > a) then
                arg = trim(adjustl(t(a + 1:b - 1)))
                if (index(t(1:a), "*") > 0) then
                    call ts_vkeep(skip_of(arg, ctx%size))
                else
                    call ts_vskip(skip_of(arg, ctx%size))
                end if
            end if
        end if
    end subroutine raw_block

    ! The settings of a div with attributes a; aligns is 1 when it sets an
    ! alignment.
    function div_ctx(a, ctx, aligns) result(sub)
        character(len=*), intent(in) :: a
        type(ctx_t), intent(in) :: ctx
        integer, intent(out) :: aligns
        type(ctx_t) :: sub
        sub = ctx
        sub%align = -1
        call apply_attrs(a, sub%align, sub%size, sub%color, sub%bold, sub%italic, ctx%size)
        aligns = merge(1, 0, sub%align >= 0)
        if (sub%align < 0) sub%align = ctx%align
        if (sub%align /= ALIGN_JUSTIFY) sub%indent = .false.
    end function div_ctx

    function parsep_of(depth) result(g)
        integer, intent(in) :: depth
        type(ts_glue_t) :: g
        real(dp) :: f
        f = BASE/10.0_dp
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
    subroutine apply_attrs(a, align, size, color, bold, italic, base_size)
        character(len=*), intent(in) :: a
        integer, intent(inout) :: align, color
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
                    size = 0.5_dp*BASE
                case ("scriptsize")
                    size = 0.7_dp*BASE
                case ("footnotesize")
                    size = 0.8_dp*BASE
                case ("small")
                    size = 0.9_dp*BASE
                case ("normalsize")
                    size = BASE
                case ("large")
                    size = 1.2_dp*BASE
                case ("Large")
                    size = 1.44_dp*BASE
                case ("LARGE")
                    size = 1.728_dp*BASE
                case ("huge")
                    size = 2.074_dp*BASE
                case ("Huge")
                    size = 2.488_dp*BASE
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
    subroutine set_inlines(doc, k, st)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        type(style_t), intent(in) :: st
        W = ""
        SPACE = .false.
        call walk(doc, k, st)
        call flush(st)
    end subroutine set_inlines

    ! Words in style st, a space between each two.
    subroutine set_words(s, st)
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
            if (i > 1) call ts_space(face_of(st), st%size)
            call ts_word(s(i:j - 1), face_of(st), st%size, st%color)
            i = j + 1
        end do
    end subroutine set_words

    ! The children of node parent, in style st. A word goes out when
    ! something else than text comes, after the space before it.
    recursive subroutine walk(doc, parent, st)
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
                    call add_text(nd%text, st)
                case (IN_SPACE)
                    call flush(st)
                    if (.not. SPACE) then
                        SP_FACE = face_of(st)
                        SP_SIZE = st%size
                    end if
                    SPACE = .true.
                case (IN_BREAK)
                    call flush(st)
                    call ts_hard_break()
                    SPACE = .false.
                case (IN_EMPH, IN_STRONG, IN_SPAN, IN_LINK)
                    call flush(st)
                    sx = st
                    select case (nd%kind)
                    case (IN_EMPH)
                        sx%italic = .not. st%italic
                    case (IN_STRONG)
                        sx%bold = .true.
                    case (IN_SPAN)
                        al = ALIGN_JUSTIFY
                        call apply_attrs(nd%attr, al, sx%size, sx%color, sx%bold, sx%italic, &
                                         st%size)
                    case (IN_LINK)
                        sx%color = LINK_COL
                    end select
                    call walk(doc, c, sx)
                    call flush(sx)
                case (IN_CODE)
                    call flush(st)
                    call flush_space()
                    call set_code(nd%text, st%size)
                case (IN_MATH)
                    call flush(st)
                    if (nd%display) then
                        tag = display_tag(doc, c)
                        call ts_math(strip_math_labels(nd%text), st%size, st%color, &
                                     display=.true., tag=tag)
                        SPACE = .false.
                    else
                        call flush_space()
                        call ts_math(nd%text, st%size, st%color)
                    end if
                case (IN_RAW)
                    select case (nd%text)
                    case ("hfill")
                        call flush(st)
                        call ts_hfil()
                        SPACE = .false.
                    case ("quad", "qquad")
                        call flush(st)
                        call ts_kern(merge(1.0_dp, 2.0_dp, nd%text == "quad")*st%size)
                        SPACE = .false.
                    case ("TeX", "LaTeX")
                        call flush(st)
                        call flush_space()
                        call tex_logo(st, nd%text == "LaTeX")
                    end select
                case (IN_REF)
                    W = W//ref_text(nd%id, nd%num)
                end select
            end associate
            c = doc%nodes(c)%next
        end do
    end subroutine walk

    ! Text onto the word; a no-break space is glue that does not break.
    subroutine add_text(s, st)
        character(len=*), intent(in) :: s
        type(style_t), intent(in) :: st
        integer :: i, j
        i = 1
        do
            j = index(s(i:), NBSP)
            if (j == 0) exit
            W = W//s(i:i + j - 2)
            call flush(st)
            call ts_nbsp(face_of(st), st%size)
            SPACE = .false.
            i = i + j + 1
        end do
        W = W//s(i:)
    end subroutine add_text

    ! The word so far goes out, after a space if one came before it.
    subroutine flush(st)
        type(style_t), intent(in) :: st
        if (len(W) == 0) return
        call flush_space()
        call ts_word(W, face_of(st), st%size, st%color)
        W = ""
    end subroutine flush

    subroutine flush_space()
        if (SPACE) call ts_space(SP_FACE, SP_SIZE)
        SPACE = .false.
    end subroutine flush_space

    ! Code, as it is: its words upright, its spaces glue.
    subroutine set_code(t, size)
        character(len=*), intent(in) :: t
        real(dp), intent(in) :: size
        integer :: i, j
        i = 1
        do while (i <= len(t))
            if (t(i:i) == " ") then
                call ts_space(FACE_REGULAR, size)
                i = i + 1
                cycle
            end if
            j = i
            do while (j <= len(t))
                if (t(j:j) == " ") exit
                j = j + 1
            end do
            call ts_word(t(i:j - 1), FACE_REGULAR, size, CODE_COL)
            i = j
        end do
    end subroutine set_code

    ! The TeX and LaTeX logos, as plain TeX and LaTeX draw them.
    subroutine tex_logo(st, la)
        type(style_t), intent(in) :: st
        logical, intent(in) :: la
        real(dp) :: em, ex
        integer :: f
        f = face_of(st)
        em = st%size
        ex = face_xheight(FACE_REGULAR)*st%size
        if (la) then
            ! The A at the script size, its top at the T's.
            call ts_word("L", f, st%size, st%color)
            call ts_kern(-0.36_dp*em)
            call ts_word("A", f, 0.7_dp*st%size, st%color, &
                         raise=0.3_dp*face_capheight(FACE_REGULAR)*st%size)
            call ts_kern(-0.15_dp*em)
        end if
        call ts_word("T", f, st%size, st%color)
        call ts_kern(-0.1667_dp*em)
        call ts_word("E", f, st%size, st%color, raise=-0.5_dp*ex)
        call ts_kern(-0.125_dp*em)
        call ts_word("X", f, st%size, st%color)
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
    subroutine heading_number(level, lv, num)
        integer, intent(in) :: level
        integer, intent(out) :: lv
        character(len=:), allocatable, intent(out) :: num
        integer :: k
        lv = level
        if (BOOK) lv = level - 1
        num = ""
        if (lv == 0) then
            CHAPTER = CHAPTER + 1
            SEC = 0
            EQNO = 0
            num = itoa(CHAPTER)
            return
        end if
        if (lv > 4) return
        SEC(lv) = SEC(lv) + 1
        SEC(lv + 1:) = 0
        if (BOOK) then
            num = itoa(CHAPTER)
        else
            num = itoa(SEC(1))
        end if
        do k = merge(1, 2, BOOK), lv
            num = num//"."//itoa(SEC(k))
        end do
    end subroutine heading_number

    ! The tag of displayed formula k: its \tag{t}, or its number when it is
    ! numbered: in a document with numberequations, or with an {#id} after
    ! it or \label{name} in it, but not with \notag or \nonumber. Within a
    ! book, formulas are numbered by chapter.
    function display_tag(doc, k) result(tag)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        character(len=:), allocatable :: tag
        character(len=:), allocatable :: src
        integer :: a, b
        logical :: numbered
        src = doc%nodes(k)%text
        tag = ""
        numbered = NUMBER_EQS .or. doc%nodes(k)%num == 1
        if (index(src, BS//"label{") > 0) numbered = .true.
        if (index(src, BS//"notag") > 0 .or. index(src, BS//"nonumber") > 0) numbered = .false.
        a = index(src, BS//"tag{")
        if (a > 0) then
            b = index(src(a:), "}")
            tag = src(a + 5:a + b - 2)
            return
        end if
        if (numbered) then
            EQNO = EQNO + 1
            if (BOOK) then
                tag = itoa(CHAPTER)//"."//itoa(EQNO)
            else
                tag = itoa(EQNO)
            end if
        end if
    end function display_tag

    ! The labels of the headings and displays under node parent, with
    ! their numbers, found before anything is set, so that a reference may
    ! come before what it refers to.
    recursive subroutine labels(doc, parent)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        character(len=:), allocatable :: num, name, src
        integer :: c, lv, a, b
        c = doc%nodes(parent)%first
        do while (c > 0)
            select case (doc%nodes(c)%kind)
            case (DOC_HEADING)
                call heading_number(doc%nodes(c)%num, lv, num)
                if (len(doc%nodes(c)%id) > 0 .and. len(num) > 0) &
                    call add_label(doc%nodes(c)%id, num)
            case (IN_MATH)
                if (doc%nodes(c)%display) then
                    num = display_tag(doc, c)
                    name = doc%nodes(c)%id
                    src = doc%nodes(c)%text
                    a = index(src, BS//"label{")
                    if (a > 0) then
                        b = index(src(a:), "}")
                        if (b > 0) name = src(a + 7:a + b - 2)
                    end if
                    if (len(name) > 0 .and. len(num) > 0) call add_label(name, num)
                end if
            case default
                call labels(doc, c)
            end select
            c = doc%nodes(c)%next
        end do
    end subroutine labels

    ! How a reference to name is written: its number, in parentheses for
    ! \eqref and @eq:name; ?? for an unknown \ref, @name as it is.
    function ref_text(name, form) result(s)
        character(len=*), intent(in) :: name
        integer, intent(in) :: form
        character(len=:), allocatable :: s
        integer :: k
        k = find_label(name)
        if (k == 0) then
            if (form == REF_AT) then
                s = "@"//name
            else
                s = "??"
            end if
        else if (form == REF_EQ .or. (form == REF_AT .and. starts(name, "eq:"))) then
            s = "("//trim(LAB_TEXT(k))//")"
        else
            s = trim(LAB_TEXT(k))
        end if
    end function ref_text

    subroutine add_label(name, text)
        character(len=*), intent(in) :: name, text
        if (NLAB >= size(LAB_NAME)) return
        NLAB = NLAB + 1
        LAB_NAME(NLAB) = name
        LAB_TEXT(NLAB) = text
    end subroutine add_label

    integer function find_label(name)
        character(len=*), intent(in) :: name
        integer :: k
        find_label = 0
        do k = 1, NLAB
            if (trim(LAB_NAME(k)) == name) then
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
    integer function color_of(v, dflt)
        character(len=*), intent(in) :: v
        integer, intent(in) :: dflt
        character(len=7) :: h
        character(len=:), allocatable :: t
        integer :: ios, c
        color_of = dflt
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
        if (ios == 0) color_of = c
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
    function scale(g) result(r)
        type(ts_glue_t), intent(in) :: g
        type(ts_glue_t) :: r
        real(dp) :: f
        f = BASE/10.0_dp
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
