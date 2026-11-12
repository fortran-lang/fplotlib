! fplotlib_markdown -- documents written in Markdown, set by TeX's rules.
!
! The input is Markdown as Pandoc reads it, with TeX math: $...$ inline and
! $$...$$ displayed. It is turned into calls to fplotlib_typeset, which
! breaks paragraphs and pages as TeX does; the spacing is LaTeX's article
! (or book) class, so that a document comes out the way the same source
! does through Pandoc and LaTeX.
!
! Blocks: a YAML front matter between --- lines (title, author, date,
! abstract, paper, fontsize, margin, ...); ATX headings (# to ####) and
! setext ones; paragraphs; bullet and ordered lists, nested; block
! quotes; fenced code; thematic breaks; Pandoc's fenced divs (::: {.center
! size=24pt color=navy}) for alignment, size and colour; and, on a line of
! their own, the TeX commands \newpage, \pagebreak, \clearpage, \vfill,
! \vspace{...}, \vspace*{...}, \bigskip, \medskip and \smallskip.
!
! Inline: *emphasis*, **strong**, `code`, [links](url), Pandoc's bracketed
! spans ([text]{color=red size=1.2em .bold}), \textbf, \textit and \emph,
! hard line breaks (a backslash or two spaces at the end of a line, or
! <br>),
! "smart" quotes, -- and --- as dashes, ... as an ellipsis, \hfill, \quad,
! \qquad, \TeX and \LaTeX, and cross references: a displayed formula
! followed by {#eq:name} or containing \label{name} is numbered, a
! heading followed by {#sec:name} can be referred to, and @eq:name,
! @sec:name, \eqref{name} and \ref{name} write the number.
!
! Lengths are in points (1/72 in, as in PostScript and Typst), or in bp,
! in, cm, mm, em or ex.
module fplotlib_markdown
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_colors, only: color_from_name
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_BOLD, FACE_ITALIC, face_xheight, &
                               face_capheight
    use fplotlib_typeset
    implicit none
    private

    public :: md_typeset

    character, parameter :: BS = achar(92), NL = achar(10)

    type :: line_t
        character(len=:), allocatable :: s
    end type line_t

    ! The style of inline text.
    type :: style_t
        logical :: bold = .false., italic = .false., code = .false.
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
    character(len=:), allocatable :: TITLE, SUBTITLE, AUTHOR, DATE, ABSTRACT
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

contains

    ! ------------------------------------------------------------------
    ! The document.
    ! ------------------------------------------------------------------

    ! Set text, a Markdown document, into fplotlib_typeset's pages.
    subroutine md_typeset(text)
        character(len=*), intent(in) :: text
        type(line_t), allocatable :: lines(:)
        type(ctx_t) :: ctx
        integer :: n, first

        call split_lines(text, lines, n)
        call ts_reset()
        call defaults()
        first = 1
        call front_matter(lines, n, first)
        call ts_set_font(BASE, LEAD*BASE)
        call ts_set_parskip(PARSKIP_G)
        call ts_set_colors(TEXT_COL, PAGE_COL)
        call labels(lines, first, n)
        SEC = 0
        CHAPTER = 0
        EQNO = 0
        ctx%size = BASE
        ctx%color = TEXT_COL
        ctx%align = DOC_ALIGN
        call title_block(ctx)
        if (first <= n) call blocks(lines(first:n), n - first + 1, ctx)
        call ts_paginate()
    end subroutine md_typeset

    subroutine defaults()
        BASE = 10.0_dp
        LEAD = 1.2_dp
        PARINDENT = -1.0_dp
        PARSKIP_G = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        DOC_ALIGN = ALIGN_JUSTIFY
        NUMBER_SECTIONS = .false.
        NUMBER_EQS = .false.
        BOOK = .false.
        TITLE = ""
        SUBTITLE = ""
        AUTHOR = ""
        DATE = ""
        ABSTRACT = ""
        TEXT_COL = 0
        PAGE_COL = 16777215
        NLAB = 0
        NOINDENT = .false.
        PENDING_LABEL = ""
        call ts_set_page(595.2756_dp, 841.8898_dp, 72.0_dp, 72.0_dp, 72.0_dp, 72.0_dp)
    end subroutine defaults

    ! The front matter: "key: value" lines between two lines of ---.
    subroutine front_matter(lines, n, first)
        type(line_t), intent(in) :: lines(:)
        integer, intent(in) :: n
        integer, intent(inout) :: first
        integer :: i, j, c
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
        if (n >= 1) then
            if (trim(lines(1)%s) == "---") then
                do i = 2, n
                    if (trim(lines(i)%s) == "---" .or. trim(lines(i)%s) == "...") exit
                    ! An indented line goes on the value before it.
                    if (len(lines(i)%s) > 0) then
                        if (lines(i)%s(1:1) == " ") cycle
                    end if
                    c = index(lines(i)%s, ":")
                    if (c == 0) cycle
                    key = lower(adjustl(trim(lines(i)%s(1:c - 1))))
                    val = unquote(adjustl(trim(lines(i)%s(c + 1:))))
                    ! A value goes on over the indented lines after it, as
                    ! does a block value (| or >).
                    if (val == "|" .or. val == ">") val = ""
                    do j = i + 1, n
                        if (len(lines(j)%s) == 0) exit
                        if (lines(j)%s(1:1) /= " ") exit
                        if (len(val) > 0) val = val//" "
                        val = val//trim(adjustl(lines(j)%s))
                    end do
                    select case (key)
                    case ("title")
                        TITLE = val
                    case ("subtitle")
                        SUBTITLE = val
                    case ("author")
                        if (len(AUTHOR) > 0) then
                            AUTHOR = AUTHOR//NL//val
                        else
                            AUTHOR = val
                        end if
                    case ("date")
                        DATE = val
                    case ("abstract")
                        ABSTRACT = val
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
                first = i + 1
            end if
        end if
        if (PARINDENT < 0.0_dp) PARINDENT = 1.5_dp*BASE
        ! LaTeX's geometry is set here by margins; without them, one inch.
        if (m < 0.0_dp) m = 72.0_dp
        if (ml < 0.0_dp) ml = m
        if (mr < 0.0_dp) mr = m
        if (mt < 0.0_dp) mt = m
        if (mb < 0.0_dp) mb = m
        call ts_set_page(pw, ph, ml, mr, mt, mb, numbers, heads, BOOK)
    end subroutine front_matter

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
    subroutine title_block(ctx)
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        integer :: i, j
        if (len(TITLE) == 0) return
        st = base_style(ctx)
        call ts_vkeep(ts_glue_t(2.0_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        st%size = 1.728_dp*BASE
        call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, leading=22.0_dp*BASE/10.0_dp, &
                          skip=.false.)
        call inline(TITLE, st)
        call ts_end_par()
        if (len(SUBTITLE) > 0) then
            st%size = 1.2_dp*BASE
            call ts_vskip(ts_glue_t(0.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*BASE/10.0_dp, skip=.false.)
            call inline(SUBTITLE, st)
            call ts_end_par()
        end if
        st%size = 1.2_dp*BASE
        if (len(AUTHOR) > 0) then
            call ts_vskip(ts_glue_t(1.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
            i = 1
            do while (i <= len(AUTHOR))
                j = index(AUTHOR(i:), NL)
                if (j == 0) then
                    j = len(AUTHOR) + 1
                else
                    j = i + j - 1
                end if
                call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                                  leading=14.0_dp*BASE/10.0_dp, skip=.false.)
                call inline(AUTHOR(i:j - 1), st)
                call ts_end_par()
                i = j + 1
            end do
        end if
        if (len(DATE) > 0) then
            call ts_vskip(ts_glue_t(BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*BASE/10.0_dp, skip=.false.)
            call inline(DATE, st)
            call ts_end_par()
        end if
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_vskip(ts_glue_t(1.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
        if (len(ABSTRACT) > 0) then
            ! \small, a centred bold heading, and a quotation.
            st = base_style(ctx)
            st%size = 0.9_dp*BASE
            st%bold = .true.
            call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            call ts_begin_par(ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=11.0_dp*BASE/10.0_dp, skip=.false.)
            call inline("Abstract", st)
            call ts_end_par()
            st%bold = .false.
            call ts_vskip(ts_glue_t(-0.5_dp*st%size + 0.5_dp*BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_begin_par(ALIGN_JUSTIFY, 1.5_dp*st%size, left=2.5_dp*BASE, &
                              right=2.5_dp*BASE, size=st%size, leading=11.0_dp*BASE/10.0_dp)
            call inline(ABSTRACT, st)
            call ts_end_par()
            call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        end if
        NOINDENT = .false.
    end subroutine title_block

    ! ------------------------------------------------------------------
    ! Blocks.
    ! ------------------------------------------------------------------

    recursive subroutine blocks(L, n, ctx)
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        type(ctx_t), intent(in) :: ctx
        integer :: i, j, k, lev, depth
        character(len=:), allocatable :: s, t, para
        type(ctx_t) :: sub
        logical :: blank_before

        i = 1
        blank_before = .true.
        do while (i <= n)
            s = L(i)%s
            t = trim(adjustl(s))
            if (len(t) == 0) then
                i = i + 1
                blank_before = .true.
                cycle
            end if

            if (is_heading(t, lev)) then
                call heading(heading_text(t, lev), lev, ctx)
                i = i + 1
            else if (is_fence(t)) then
                j = i + 1
                do while (j <= n)
                    if (is_fence(trim(adjustl(L(j)%s)))) exit
                    j = j + 1
                end do
                call code_block(L(i + 1:min(j - 1, n)), max(0, min(j - 1, n) - i), ctx)
                i = j + 1
            else if (starts(t, ":::")) then
                ! A fenced div runs to the matching :::, divs nesting.
                depth = 0
                do j = i, n
                    k = len_trim(adjustl(L(j)%s))
                    if (.not. starts(trim(adjustl(L(j)%s)), ":::")) cycle
                    if (div_opens(trim(adjustl(L(j)%s)))) then
                        depth = depth + 1
                    else
                        depth = depth - 1
                        if (depth == 0) exit
                    end if
                end do
                ! A div that aligns its text is a LaTeX environment
                ! (center, flushright, flushleft), a list with the space of
                ! one around it; one that only changes the type is a group.
                sub = div_ctx(t, ctx, k)
                if (k > 0) call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                if (j - 1 > i) call blocks(L(i + 1:j - 1), j - 1 - i, sub)
                call ts_end_par()
                if (k > 0) call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                i = j + 1
            else if (t(1:1) == ">") then
                j = i
                do while (j <= n)
                    if (len_trim(L(j)%s) == 0) exit
                    j = j + 1
                end do
                call quote_block(L(i:j - 1), j - i, ctx)
                i = j
            else if (is_item(s, k, lev)) then
                call list_block(L, n, i, ctx, blank_before)
            else if (is_rule(t)) then
                call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                call ts_begin_par(ALIGN_CENTER, 0.0_dp, left=ctx%left, right=ctx%right)
                call ts_end_par()
                call ts_rule(0.5_dp*(ts_hsize() - ctx%left - ctx%right), 0.5_dp, ctx%color)
                call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                i = i + 1
            else if (raw_block(t, ctx)) then
                i = i + 1
            else
                ! A paragraph: lines up to a blank one or a block that
                ! interrupts it; a display may run over several lines.
                para = ""
                j = i
                do while (j <= n)
                    t = trim(adjustl(L(j)%s))
                    if (len(t) == 0) exit
                    if (j > i) then
                        if (interrupts(L(j)%s)) exit
                        ! A setext heading underlines one line.
                        if (j == i + 1 .and. (is_underline(t, "=") .or. &
                                              is_underline(t, "-"))) then
                            if (is_underline(t, "=")) then
                                lev = 1
                            else
                                lev = 2
                            end if
                            exit
                        end if
                    end if
                    if (len(para) > 0) para = para//NL
                    para = para//L(j)%s
                    j = j + 1
                end do
                if (j == i + 1 .and. j <= n) then
                    t = trim(adjustl(L(j)%s))
                    if (len(t) > 0 .and. (is_underline(t, "=") .or. is_underline(t, "-"))) then
                        if (is_underline(t, "=")) then
                            call heading(trim(adjustl(para)), 1, ctx)
                        else
                            call heading(trim(adjustl(para)), 2, ctx)
                        end if
                        i = j + 1
                        cycle
                    end if
                end if
                call paragraph(para, ctx)
                i = j
            end if
            blank_before = .false.
        end do
    end subroutine blocks

    ! Whether a line starts a block that ends a paragraph before it.
    logical function interrupts(s)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t
        integer :: k, lev
        t = trim(adjustl(s))
        interrupts = .false.
        if (len(t) == 0) return
        if (is_heading(t, lev) .or. is_fence(t) .or. starts(t, ":::") .or. &
            t(1:1) == ">" .or. is_rule(t)) then
            interrupts = .true.
        else if (is_item(s, k, lev)) then
            ! Only a bullet, or a list starting at 1, interrupts.
            interrupts = lev == 0 .or. k == 1
        else if (is_raw_block(t)) then
            interrupts = .true.
        end if
    end function interrupts

    ! A paragraph of inline text in the context's settings.
    subroutine paragraph(text, ctx)
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: s
        real(dp) :: ind
        s = trim(adjustl(text))
        ind = 0.0_dp
        if (ctx%indent .and. .not. NOINDENT .and. ctx%align == ALIGN_JUSTIFY) ind = PARINDENT
        if (starts(s, BS//"noindent")) then
            ind = 0.0_dp
            s = trim(adjustl(s(10:)))
        end if
        NOINDENT = .false.
        call ts_begin_par(ctx%align, ind, left=ctx%left, right=ctx%right, size=ctx%size, &
                          leading=LEAD*ctx%size)
        if (len(PENDING_LABEL) > 0) then
            call ts_label(PENDING_LABEL, label_face(ctx), ctx%size, LABEL_SEP, ctx%color)
            PENDING_LABEL = ""
        end if
        call inline(s, base_style(ctx))
        call ts_end_par()
    end subroutine paragraph

    integer function label_face(ctx)
        type(ctx_t), intent(in) :: ctx
        label_face = FACE_REGULAR
        if (ctx%bold) label_face = FACE_BOLD
    end function label_face

    ! Headings: LaTeX's \section, \subsection and \subsubsection (and,
    ! for a book, \chapter for #).
    subroutine heading(text0, level, ctx)
        character(len=*), intent(in) :: text0
        integer, intent(in) :: level
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: text, num
        type(style_t) :: st
        real(dp) :: ex, size, lead, hang
        type(ts_glue_t) :: before, after
        integer :: lv, k

        text = strip_attrs(text0)
        ex = face_xheight(FACE_REGULAR)*BASE
        lv = level
        if (BOOK) then
            if (level == 1) then
                call chapter_heading(text, ctx)
                return
            end if
            lv = level - 1
        end if
        num = ""
        if (NUMBER_SECTIONS .and. lv <= 3) then
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
        end if
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
                call ts_mark(upper(num//".  "//strip_markup(text)), .false., section=.true.)
            else
                call ts_mark(upper(strip_markup(text)), .false., section=.true.)
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
        call inline(text, st)
        call ts_end_par()
        call ts_penalty(10000)
        call ts_vskip(after)
        call ts_nobreak_next()
        NOINDENT = .true.
    end subroutine heading

    ! LaTeX's \chapter in the book class: a new page, "Chapter n" and the
    ! title below it in large bold, and the chapter as the running head.
    subroutine chapter_heading(text, ctx)
        character(len=*), intent(in) :: text
        type(ctx_t), intent(in) :: ctx
        type(style_t) :: st
        CHAPTER = CHAPTER + 1
        SEC = 0
        EQNO = 0
        call ts_page_break()
        ! The running heads are the book class's: in capitals,
        ! "CHAPTER 1. TITLE" and "1.2. SECTION".
        if (NUMBER_SECTIONS) then
            call ts_mark(upper("Chapter "//itoa(CHAPTER)//".  "//strip_markup(text)), .true.)
        else
            call ts_mark(upper(strip_markup(text)), .true.)
        end if
        call ts_vkeep(ts_glue_t(50.0_dp*BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        st = base_style(ctx)
        st%bold = .true.
        if (NUMBER_SECTIONS) then
            st%size = 2.074_dp*BASE
            call ts_begin_par(ALIGN_LEFT, 0.0_dp, size=st%size, leading=25.0_dp*BASE/10.0_dp, &
                              skip=.false., nobreak=.true.)
            call inline("Chapter "//itoa(CHAPTER), st)
            call ts_end_par()
            call ts_penalty(10000)
            call ts_vskip(ts_glue_t(20.0_dp*BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        end if
        st%size = 2.488_dp*BASE
        call ts_begin_par(ALIGN_LEFT, 0.0_dp, size=st%size, leading=30.0_dp*BASE/10.0_dp, &
                          skip=.false., nobreak=.true.)
        call inline(text, st)
        call ts_end_par()
        call ts_penalty(10000)
        call ts_vskip(ts_glue_t(40.0_dp*BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        call ts_nobreak_next()
        NOINDENT = .true.
    end subroutine chapter_heading

    ! A list: LaTeX's itemize or enumerate, with its spacing at the depth
    ! it is at. A tight list (no blank lines between its items) is set as
    ! Pandoc's \tightlist sets it, without \itemsep and \parsep.
    recursive subroutine list_block(L, n, i, ctx, blank_before)
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        integer, intent(inout) :: i
        type(ctx_t), intent(in) :: ctx
        logical, intent(in) :: blank_before
        type(line_t), allocatable :: item(:)
        integer :: j, k, num, lev, col, kind, ni, nitem, start_num, ind0, m, ln, k2, lev2
        logical :: tight, blank
        type(ctx_t) :: sub
        type(ts_glue_t) :: topsep, partopsep, itemsep, parsep
        real(dp) :: lm, f
        character(len=:), allocatable :: s

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

        ! The items: each from its marker to the next marker at the same
        ! indentation, or the end of the list.
        if (.not. is_item(L(i)%s, start_num, kind)) return
        ind0 = indent_of(L(i)%s)
        tight = .true.
        ! First pass: is the list tight, and where does it end?
        j = i + 1
        blank = .false.
        do while (j <= n)
            if (len_trim(L(j)%s) == 0) then
                blank = .true.
                j = j + 1
                cycle
            end if
            if (indent_of(L(j)%s) <= ind0 + 1 .and. is_item(L(j)%s, k2, lev2)) then
                if (lev2 /= kind) exit
                if (blank) tight = .false.
                blank = .false.
                j = j + 1
                cycle
            end if
            if (indent_of(L(j)%s) > ind0) then
                if (blank) then
                    tight = .false.
                    blank = .false.
                end if
                j = j + 1
                cycle
            end if
            if (blank) exit
            ! A lazy continuation of the item's paragraph.
            if (interrupts(L(j)%s)) exit
            j = j + 1
        end do
        m = j - 1
        do while (m > i .and. len_trim(L(m)%s) == 0)
            m = m - 1
        end do

        if (tight) then
            itemsep = ts_glue_t()
            parsep = ts_glue_t()
        end if
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
        if (blank_before .and. .not. ts_in_par()) then
            call ts_addpenalty(-51)
            call ts_addvspace(add_glue(topsep, partopsep))
        else
            call ts_end_par()
            call ts_addpenalty(-51)
            call ts_addvspace(topsep)
        end if

        num = start_num
        nitem = 0
        j = i
        do while (j <= m)
            ! Item j: its lines up to the next marker at this level.
            if (.not. is_item(L(j)%s, k, lev2)) then
                j = j + 1
                cycle
            end if
            col = content_col(L(j)%s)
            k = j + 1
            do while (k <= m)
                if (len_trim(L(k)%s) > 0) then
                    if (indent_of(L(k)%s) <= ind0 + 1 .and. is_item(L(k)%s, k2, lev2)) exit
                end if
                k = k + 1
            end do
            ni = k - j
            allocate (item(ni))
            item(1)%s = L(j)%s(col:)
            do ln = 2, ni
                s = L(j + ln - 1)%s
                if (indent_of(s) >= col - 1) then
                    item(ln)%s = s(min(col, len(s) + 1):)
                else
                    item(ln)%s = trim(adjustl(s))
                end if
            end do
            nitem = nitem + 1
            if (nitem > 1) then
                call ts_addpenalty(-51)
                call ts_addvspace(itemsep)
            end if
            PENDING_LABEL = list_label(kind, merge(sub%ilev, sub%elev, kind == 0), num)
            LABEL_SEP = 0.5_dp*BASE
            call ts_set_parskip(parsep)
            call blocks(item, ni, sub)
            if (len(PENDING_LABEL) > 0) then
                ! An item with no paragraph of its own still has its label.
                call ts_begin_par(sub%align, 0.0_dp, left=sub%left, right=sub%right, &
                                  size=sub%size)
                call ts_label(PENDING_LABEL, FACE_REGULAR, sub%size, LABEL_SEP, sub%color)
                call ts_strut(0.7_dp*sub%size, 0.3_dp*sub%size)
                call ts_end_par()
                PENDING_LABEL = ""
            end if
            deallocate (item)
            num = num + 1
            j = k
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
        i = m + 1
    end subroutine list_block

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

    ! A block quote: LaTeX's quote environment, a list with no label and
    ! equal margins.
    recursive subroutine quote_block(L, n, ctx)
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        type(ctx_t), intent(in) :: ctx
        type(line_t), allocatable :: q(:)
        type(ctx_t) :: sub
        integer :: k
        character(len=:), allocatable :: s
        allocate (q(n))
        do k = 1, n
            s = trim(adjustl(L(k)%s))
            if (len(s) > 0) then
                if (s(1:1) == ">") then
                    s = s(2:)
                    if (len(s) > 0) then
                        if (s(1:1) == " ") s = s(2:)
                    end if
                end if
            end if
            q(k)%s = s
        end do
        sub = ctx
        sub%depth = ctx%depth + 1
        sub%left = ctx%left + 2.5_dp*BASE
        sub%right = ctx%right + 2.5_dp*BASE
        sub%indent = .false.
        call ts_end_par()
        call ts_addpenalty(-51)
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(parsep_of(sub%depth))
        call blocks(q, n, sub)
        call ts_end_par()
        call ts_set_parskip(PARSKIP_G)
        if (ctx%depth > 0) call ts_set_parskip(parsep_of(ctx%depth))
        call ts_addpenalty(-51)
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
    end subroutine quote_block

    ! Fenced code: each line as it is, unbroken, its spaces kept.
    subroutine code_block(L, n, ctx)
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        type(ctx_t), intent(in) :: ctx
        integer :: k, i, j
        real(dp) :: sp
        character(len=:), allocatable :: s
        call ts_end_par()
        call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(ts_glue_t())
        sp = text_width(" ", FACE_REGULAR, 0.9_dp*ctx%size)
        do k = 1, n
            s = L(k)%s
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

    ! The TeX commands a line may hold by itself.
    logical function is_raw_block(t)
        character(len=*), intent(in) :: t
        is_raw_block = .false.
        if (len(t) < 2) return
        if (t(1:1) /= BS) return
        is_raw_block = starts(t, BS//"newpage") .or. starts(t, BS//"pagebreak") .or. &
                       starts(t, BS//"clearpage") .or. starts(t, BS//"vfill") .or. &
                       starts(t, BS//"vspace") .or. starts(t, BS//"bigskip") .or. &
                       starts(t, BS//"medskip") .or. starts(t, BS//"smallskip")
    end function is_raw_block

    logical function raw_block(t, ctx)
        character(len=*), intent(in) :: t
        type(ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: arg
        integer :: a, b
        real(dp) :: f
        f = BASE/10.0_dp
        raw_block = is_raw_block(t)
        if (.not. raw_block) return
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
    end function raw_block

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

    ! The settings of a fenced div: ::: {.center size=20pt color=red};
    ! aligns is 1 when it sets an alignment.
    function div_ctx(t, ctx, aligns) result(sub)
        character(len=*), intent(in) :: t
        type(ctx_t), intent(in) :: ctx
        integer, intent(out) :: aligns
        type(ctx_t) :: sub
        character(len=:), allocatable :: a
        integer :: k
        sub = ctx
        a = trim(adjustl(t(4:)))
        k = len(a)
        if (k > 0) then
            if (a(1:1) == "{") a = a(2:)
        end if
        if (len(a) > 0) then
            if (a(len(a):len(a)) == "}") a = a(1:len(a) - 1)
        end if
        sub%align = -1
        call apply_attrs(a, sub%align, sub%size, sub%color, sub%bold, sub%italic, ctx%size)
        aligns = merge(1, 0, sub%align >= 0)
        if (sub%align < 0) sub%align = ctx%align
        if (sub%align /= ALIGN_JUSTIFY) sub%indent = .false.
    end function div_ctx

    ! Attributes of a div or a span: classes (.center, .right, .left,
    ! .justify, .bold, .italic, and LaTeX's size names .small to .Huge)
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

    ! Set inline text s in style st0 into the current paragraph.
    recursive subroutine inline(s, st0)
        character(len=*), intent(in) :: s
        type(style_t), intent(in) :: st0
        type(style_t) :: st, sp
        character(len=:), allocatable :: w, src, tag, cmd, arg
        integer :: i, j, k, r, cp, nb, sp_face
        real(dp) :: sp_size
        logical :: space, em_open, strong_open, lf, rf
        character :: c, em_c, strong_c, prev, next

        st = st0
        w = ""
        space = .false.
        em_open = .false.
        strong_open = .false.
        em_c = " "
        strong_c = " "
        i = 1
        do while (i <= len(s))
            c = s(i:i)
            prev = " "
            if (i > 1) prev = s(i - 1:i - 1)
            select case (c)
            case (" ", NL, achar(9))
                ! Two spaces before the end of a line break it.
                if (c == " " .and. i + 2 <= len(s)) then
                    if (s(i:i + 2) == "  "//NL) then
                        call flush()
                        call ts_hard_break()
                        space = .false.
                        i = i + 3
                        cycle
                    end if
                end if
                call flush()
                ! The space is the type's it is in, as TeX's is.
                if (.not. space) then
                    sp_face = face_of(st)
                    sp_size = st%size
                end if
                space = .true.
                i = i + 1
            case ("*", "_")
                r = 1
                do while (i + r <= len(s))
                    if (s(i + r:i + r) /= c) exit
                    r = r + 1
                end do
                next = " "
                if (i + r <= len(s)) next = s(i + r:i + r)
                lf = .not. white(next) .and. (.not. punct(next) .or. white(prev) .or. punct(prev))
                rf = .not. white(prev) .and. (.not. punct(prev) .or. white(next) .or. punct(next))
                if (c == "_") then
                    ! Inside a word, an underscore is just that.
                    if (lf .and. rf) then
                        lf = .false.
                        rf = .false.
                    end if
                end if
                if (rf .and. ((r == 1 .and. em_open .and. em_c == c) .or. &
                              (r == 2 .and. strong_open .and. strong_c == c) .or. &
                              (r >= 3 .and. em_open .and. strong_open))) then
                    call flush()
                    if (r == 1 .or. r >= 3) then
                        em_open = .false.
                        st%italic = st0%italic
                    end if
                    if (r >= 2) then
                        strong_open = .false.
                        st%bold = st0%bold
                    end if
                else if (lf .and. r <= 3) then
                    call flush()
                    if (r == 1 .or. r == 3) then
                        em_open = .true.
                        em_c = c
                        st%italic = .not. st0%italic
                    end if
                    if (r >= 2) then
                        strong_open = .true.
                        strong_c = c
                        st%bold = .true.
                    end if
                else
                    w = w//s(i:i + r - 1)
                end if
                i = i + r
            case ("`")
                r = 1
                do while (i + r <= len(s))
                    if (s(i + r:i + r) /= "`") exit
                    r = r + 1
                end do
                j = index(s(i + r:), repeat("`", r))
                if (j == 0) then
                    w = w//s(i:i + r - 1)
                    i = i + r
                    cycle
                end if
                call flush()
                call flush_space()
                sp = st
                sp%code = .true.
                sp%bold = .false.
                sp%italic = .false.
                call plain(trim(adjustl(s(i + r:i + r + j - 2))), sp, verbatim=.true.)
                i = i + r + j - 1 + r
            case ("$")
                if (i < len(s)) then
                    if (s(i + 1:i + 1) == "$") then
                        ! A display.
                        j = index(s(i + 2:), "$$")
                        if (j > 0) then
                            call flush()
                            src = s(i + 2:i + j)
                            k = i + j + 3
                            tag = ""
                            call display_tag(s, k, src, tag)
                            call ts_display(strip_math_labels(src), st%size, tag, st%color)
                            space = .false.
                            i = k
                            ! A line break after it is not a space.
                            do while (i <= len(s))
                                if (s(i:i) /= " " .and. s(i:i) /= NL) exit
                                i = i + 1
                            end do
                            cycle
                        end if
                    end if
                end if
                j = closing_dollar(s, i)
                if (j > 0) then
                    call flush()
                    call flush_space()
                    call ts_math(s(i + 1:j - 1), st%size, st%color)
                    i = j + 1
                else
                    w = w//"$"
                    i = i + 1
                end if
            case (BS)
                if (i == len(s)) then
                    w = w//BS
                    i = i + 1
                    cycle
                end if
                next = s(i + 1:i + 1)
                if (next == NL) then
                    call flush()
                    call ts_hard_break()
                    space = .false.
                    i = i + 2
                else if (next == " ") then
                    call flush()
                    call ts_nbsp(face_of(st), st%size)
                    space = .false.
                    i = i + 2
                else if (is_alpha(next)) then
                    j = i + 1
                    do while (j <= len(s))
                        if (.not. is_alpha(s(j:j))) exit
                        j = j + 1
                    end do
                    cmd = s(i + 1:j - 1)
                    arg = ""
                    k = j
                    if (j <= len(s)) then
                        if (s(j:j) == "{") then
                            k = matching(s, j)
                            arg = s(j + 1:k - 1)
                            k = k + 1
                        end if
                    end if
                    call command(cmd, arg, k, j)
                    ! A command without an argument may be ended by {}.
                    if (k == j .and. j + 1 <= len(s)) then
                        if (s(j:j + 1) == "{}") k = j + 2
                    end if
                    i = k
                else
                    w = w//next
                    i = i + 2
                end if
            case ("[")
                j = matching(s, i)
                if (j > 0 .and. j < len(s)) then
                    if (s(j + 1:j + 1) == "(") then
                        k = index(s(j + 1:), ")")
                        if (k > 0) then
                            call flush()
                            sp = st
                            sp%color = LINK_COL
                            call inline_sub(s(i + 1:j - 1), sp)
                            i = j + k + 1
                            cycle
                        end if
                    else if (s(j + 1:j + 1) == "{") then
                        k = matching(s, j + 1)
                        if (k > 0) then
                            call flush()
                            sp = st
                            call span_style(s(j + 2:k - 1), sp)
                            call inline_sub(s(i + 1:j - 1), sp)
                            i = k + 1
                            cycle
                        end if
                    end if
                end if
                w = w//"["
                i = i + 1
            case ("<")
                ! <br>, the HTML line break Markdown allows too.
                k = 0
                if (starts(s(i:), "<br>")) k = 4
                if (starts(s(i:), "<br/>")) k = 5
                if (starts(s(i:), "<br />")) k = 6
                if (k > 0) then
                    call flush()
                    call ts_hard_break()
                    space = .false.
                    i = i + k
                    do while (i <= len(s))
                        if (s(i:i) /= " " .and. s(i:i) /= NL) exit
                        i = i + 1
                    end do
                else
                    w = w//"<"
                    i = i + 1
                end if
            case ("@")
                ! A cross reference, @eq:name or @sec:name.
                j = i + 1
                do while (j <= len(s))
                    if (.not. (is_alnum(s(j:j)) .or. s(j:j) == ":" .or. s(j:j) == "-" &
                               .or. s(j:j) == "_")) exit
                    j = j + 1
                end do
                do while (j > i + 1)
                    if (is_alnum(s(j - 1:j - 1))) exit
                    j = j - 1
                end do
                k = find_label(s(i + 1:j - 1))
                if (k > 0 .and. white(prev)) then
                    if (starts(s(i + 1:), "eq:")) then
                        w = w//"("//trim(LAB_TEXT(k))//")"
                    else
                        w = w//trim(LAB_TEXT(k))
                    end if
                    i = j
                else
                    w = w//"@"
                    i = i + 1
                end if
            case ("-")
                if (i + 2 <= len(s)) then
                    if (s(i:i + 2) == "---") then
                        w = w//achar(226)//achar(128)//achar(148)
                        i = i + 3
                        cycle
                    end if
                end if
                if (i + 1 <= len(s)) then
                    if (s(i:i + 1) == "--") then
                        w = w//achar(226)//achar(128)//achar(147)
                        i = i + 2
                        cycle
                    end if
                end if
                w = w//"-"
                i = i + 1
            case (".")
                if (i + 2 <= len(s)) then
                    if (s(i:i + 2) == "...") then
                        w = w//achar(226)//achar(128)//achar(166)
                        i = i + 3
                        cycle
                    end if
                end if
                w = w//"."
                i = i + 1
            case ('"')
                if (opening(prev)) then
                    w = w//achar(226)//achar(128)//achar(156)
                else
                    w = w//achar(226)//achar(128)//achar(157)
                end if
                i = i + 1
            case ("'")
                if (opening(prev)) then
                    w = w//achar(226)//achar(128)//achar(152)
                else
                    w = w//achar(226)//achar(128)//achar(153)
                end if
                i = i + 1
            case default
                ! One UTF-8 character; a no-break space is glue that
                ! does not break.
                call utf8_next(s, i, cp, nb)
                if (cp == 160) then
                    call flush()
                    call ts_nbsp(face_of(st), st%size)
                    space = .false.
                else
                    w = w//s(i:i + nb - 1)
                end if
                i = i + nb
            end select
        end do
        call flush()

    contains

        ! The word so far goes out, after a space if one came before it.
        subroutine flush()
            if (len(w) == 0) return
            call flush_space()
            if (st%code) then
                call ts_word(w, FACE_REGULAR, st%size, CODE_COL)
            else
                call ts_word(w, face_of(st), st%size, st%color)
            end if
            w = ""
        end subroutine flush

        subroutine flush_space()
            if (space) call ts_space(sp_face, sp_size)
            space = .false.
        end subroutine flush_space

        ! A command written in the text.
        recursive subroutine command(cmd, arg, k, j)
            character(len=*), intent(in) :: cmd, arg
            integer, intent(inout) :: k
            integer, intent(in) :: j
            type(style_t) :: sx
            integer :: lb
            select case (cmd)
            case ("hfill")
                call flush()
                call ts_hfil()
                space = .false.
                k = j
            case ("quad")
                call flush()
                call ts_kern(st%size)
                space = .false.
                k = j
            case ("qquad")
                call flush()
                call ts_kern(2.0_dp*st%size)
                space = .false.
                k = j
            case ("newline", "linebreak")
                call flush()
                call ts_hard_break()
                space = .false.
                k = j
            case ("textbf", "emph", "textit", "textrm", "textsf", "textup")
                call flush()
                sx = st
                if (cmd == "textbf") sx%bold = .true.
                if (cmd == "textit") sx%italic = .true.
                if (cmd == "emph") sx%italic = .not. st%italic
                if (cmd == "textrm" .or. cmd == "textup") sx%italic = .false.
                call inline_sub(arg, sx)
            case ("TeX")
                call flush_space()
                call tex_logo(st, .false.)
                k = j
            case ("LaTeX")
                call flush_space()
                call tex_logo(st, .true.)
                k = j
            case ("eqref", "ref")
                lb = find_label(arg)
                if (lb > 0) then
                    if (cmd == "eqref") then
                        w = w//"("//trim(LAB_TEXT(lb))//")"
                    else
                        w = w//trim(LAB_TEXT(lb))
                    end if
                else
                    w = w//"??"
                end if
            case ("noindent", "par")
                k = j
            case default
                ! Unknown: written as it is, so that it is noticed.
                w = w//BS//cmd
                k = j
            end select
        end subroutine command

        ! Text in another style within this paragraph.
        recursive subroutine inline_sub(t, sx)
            character(len=*), intent(in) :: t
            type(style_t), intent(in) :: sx
            call flush_space()
            call inline(t, sx)
        end subroutine inline_sub

    end subroutine inline

    ! Text set as it is, without markup (code spans).
    subroutine plain(t, st, verbatim)
        character(len=*), intent(in) :: t
        type(style_t), intent(in) :: st
        logical, intent(in) :: verbatim
        integer :: i, j
        i = 1
        do while (i <= len(t))
            if (t(i:i) == " ") then
                call ts_space(FACE_REGULAR, st%size)
                i = i + 1
                cycle
            end if
            j = i
            do while (j <= len(t))
                if (t(j:j) == " ") exit
                j = j + 1
            end do
            if (verbatim) then
                call ts_word(t(i:j - 1), FACE_REGULAR, st%size, CODE_COL)
            else
                call ts_word(t(i:j - 1), face_of(st), st%size, st%color)
            end if
            i = j
        end do
    end subroutine plain

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

    ! A span's attributes: [text]{.bold color=red size=12pt}.
    subroutine span_style(a, st)
        character(len=*), intent(in) :: a
        type(style_t), intent(inout) :: st
        integer :: al
        al = ALIGN_JUSTIFY
        call apply_attrs(a, al, st%size, st%color, st%bold, st%italic, st%size)
    end subroutine span_style

    ! After a display, {#eq:name} numbers it; within it, \label{name}
    ! numbers it and \tag{t} gives it t; \notag and \nonumber, nothing.
    subroutine display_tag(s, k, src, tag)
        character(len=*), intent(in) :: s, src
        integer, intent(inout) :: k
        character(len=:), allocatable, intent(inout) :: tag
        integer :: j, a, b
        logical :: numbered
        numbered = NUMBER_EQS
        j = k
        do while (j <= len(s))
            if (s(j:j) /= " ") exit
            j = j + 1
        end do
        if (j + 1 <= len(s)) then
            if (s(j:j + 1) == "{#") then
                b = index(s(j:), "}")
                if (b > 0) then
                    numbered = .true.
                    k = j + b
                end if
            end if
        end if
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
    end subroutine display_tag

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
    ! Cross references: the numbers of labelled displays and headings,
    ! found before anything is set, so that a reference may come first.
    ! ------------------------------------------------------------------

    subroutine labels(lines, first, n)
        type(line_t), intent(in) :: lines(:)
        integer, intent(in) :: first, n
        character(len=:), allocatable :: all, t, name, num
        integer :: i, j, k, b, lev, eq, sec_(4), chap, a, nch
        integer, allocatable :: chstart(:)
        integer :: last_chap
        logical :: numbered
        ! The text, and where each chapter starts in it.
        all = ""
        allocate (chstart(n + 1))
        nch = 0
        do i = first, n
            t = trim(adjustl(lines(i)%s))
            if (BOOK .and. is_heading(t, lev)) then
                if (lev == 1) then
                    nch = nch + 1
                    chstart(nch) = len(all) + 1
                end if
            end if
            all = all//lines(i)%s//NL
        end do
        eq = 0
        sec_ = 0
        chap = 0
        last_chap = 0
        ! Headings, in order.
        do i = first, n
            t = trim(adjustl(lines(i)%s))
            if (.not. is_heading(t, lev)) cycle
            if (BOOK .and. lev == 1) then
                chap = chap + 1
                sec_ = 0
                num = itoa(chap)
            else
                if (BOOK) lev = lev - 1
                if (lev > 4) cycle
                sec_(lev) = sec_(lev) + 1
                sec_(lev + 1:) = 0
                if (BOOK) then
                    num = itoa(chap)
                else
                    num = itoa(sec_(1))
                end if
                do k = merge(1, 2, BOOK), lev
                    num = num//"."//itoa(sec_(k))
                end do
            end if
            a = index(t, "{#")
            if (a > 0) then
                b = index(t(a:), "}")
                if (b > 0) call add_label(t(a + 2:a + b - 2), num)
            end if
        end do
        ! Displays, in order.
        i = 1
        do while (i < len(all))
            if (all(i:i) == BS) then
                i = i + 2
                cycle
            end if
            if (all(i:i + 1) /= "$$") then
                i = i + 1
                cycle
            end if
            j = index(all(i + 2:), "$$")
            if (j == 0) exit
            k = i + j + 3
            numbered = NUMBER_EQS .or. index(all(i + 2:i + j), BS//"label{") > 0
            name = ""
            do while (k <= len(all))
                if (all(k:k) /= " ") exit
                k = k + 1
            end do
            if (k + 1 <= len(all)) then
                if (all(k:k + 1) == "{#") then
                    b = index(all(k:), "}")
                    name = all(k + 2:k + b - 2)
                    numbered = .true.
                end if
            end if
            a = index(all(i + 2:i + j), BS//"label{")
            if (a > 0) then
                b = index(all(i + 1 + a:), "}")
                name = all(i + 1 + a + 7:i + a + b - 1)
            end if
            if (index(all(i + 2:i + j), BS//"tag{") > 0 .or. &
                index(all(i + 2:i + j), BS//"notag") > 0 .or. &
                index(all(i + 2:i + j), BS//"nonumber") > 0) numbered = .false.
            if (numbered) then
                ! Within a book, equations are numbered by chapter.
                chap = count(chstart(1:nch) <= i)
                if (BOOK) then
                    if (chap /= a_chap()) eq = 0
                end if
                eq = eq + 1
                if (len(name) > 0) then
                    if (BOOK) then
                        call add_label(name, itoa(chap)//"."//itoa(eq))
                    else
                        call add_label(name, itoa(eq))
                    end if
                end if
                last_chap = chap
            end if
            i = i + j + 3
        end do

    contains

        integer function a_chap()
            a_chap = last_chap
        end function a_chap

    end subroutine labels

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
    ! Recognizing lines.
    ! ------------------------------------------------------------------

    logical function is_heading(t, lev)
        character(len=*), intent(in) :: t
        integer, intent(out) :: lev
        lev = 0
        do while (lev < len(t))
            if (t(lev + 1:lev + 1) /= "#") exit
            lev = lev + 1
        end do
        is_heading = lev >= 1 .and. lev <= 6
        if (is_heading .and. lev < len(t)) is_heading = t(lev + 1:lev + 1) == " "
    end function is_heading

    function heading_text(t, lev) result(h)
        character(len=*), intent(in) :: t
        integer, intent(in) :: lev
        character(len=:), allocatable :: h
        h = trim(adjustl(t(lev + 1:)))
        ! Closing #s go.
        do while (len(h) > 0)
            if (h(len(h):len(h)) /= "#") exit
            h = trim(h(1:len(h) - 1))
        end do
    end function heading_text

    ! A heading's text without its {#name .class} attributes.
    function strip_attrs(t) result(h)
        character(len=*), intent(in) :: t
        character(len=:), allocatable :: h
        integer :: a
        h = t
        a = index(h, "{#")
        if (a == 0) a = index(h, "{-}")
        if (a == 0) a = index(h, "{.")
        if (a > 0) h = trim(h(1:a - 1))
    end function strip_attrs

    logical function is_fence(t)
        character(len=*), intent(in) :: t
        is_fence = starts(t, "```") .or. starts(t, "~~~")
    end function is_fence

    logical function div_opens(t)
        character(len=*), intent(in) :: t
        div_opens = len_trim(t(4:)) > 0 .and. verify(trim(t), ":") > 0
    end function div_opens

    logical function is_rule(t)
        character(len=*), intent(in) :: t
        character :: c
        integer :: k, n
        is_rule = .false.
        if (len(t) < 3) return
        c = t(1:1)
        if (c /= "-" .and. c /= "*" .and. c /= "_") return
        n = 0
        do k = 1, len(t)
            if (t(k:k) == c) then
                n = n + 1
            else if (t(k:k) /= " ") then
                return
            end if
        end do
        is_rule = n >= 3
    end function is_rule

    logical function is_underline(t, c)
        character(len=*), intent(in) :: t
        character, intent(in) :: c
        is_underline = len(t) >= 2 .and. verify(trim(t), c) == 0
    end function is_underline

    ! A list item: a bullet (kind 0) or a number (kind 1, num its value),
    ! then a space.
    logical function is_item(s, num, kind)
        character(len=*), intent(in) :: s
        integer, intent(out) :: num, kind
        character(len=:), allocatable :: t
        integer :: k
        is_item = .false.
        num = 1
        kind = 0
        t = adjustl(s)
        t = trim(t)
        if (len(t) < 2) return
        if ((t(1:1) == "-" .or. t(1:1) == "*" .or. t(1:1) == "+") .and. t(2:2) == " ") then
            if (is_rule(t)) return
            is_item = .true.
            return
        end if
        k = 0
        do while (k < len(t))
            if (t(k + 1:k + 1) < "0" .or. t(k + 1:k + 1) > "9") exit
            k = k + 1
        end do
        if (k == 0 .or. k > 9 .or. k + 2 > len(t)) return
        if ((t(k + 1:k + 1) == "." .or. t(k + 1:k + 1) == ")") .and. t(k + 2:k + 2) == " ") then
            read (t(1:k), *) num
            kind = 1
            is_item = .true.
        end if
    end function is_item

    ! Where an item's text starts in its first line.
    integer function content_col(s)
        character(len=*), intent(in) :: s
        integer :: k
        k = indent_of(s) + 1
        do while (k <= len(s))
            if (s(k:k) == " ") exit
            k = k + 1
        end do
        do while (k <= len(s))
            if (s(k:k) /= " ") exit
            k = k + 1
        end do
        content_col = k
    end function content_col

    pure integer function indent_of(s)
        character(len=*), intent(in) :: s
        indent_of = verify(s, " ") - 1
        if (indent_of < 0) indent_of = len(s)
    end function indent_of

    ! ------------------------------------------------------------------
    ! Small things.
    ! ------------------------------------------------------------------

    subroutine split_lines(text, lines, n)
        character(len=*), intent(in) :: text
        type(line_t), allocatable, intent(out) :: lines(:)
        integer, intent(out) :: n
        integer :: i, j, k
        n = 1
        do i = 1, len(text)
            if (text(i:i) == NL) n = n + 1
        end do
        allocate (lines(n))
        i = 1
        k = 0
        do while (k < n)
            j = index(text(i:), NL)
            if (j == 0) then
                j = len(text) + 1
            else
                j = i + j - 1
            end if
            k = k + 1
            lines(k)%s = text(i:j - 1)
            ! A carriage return before the newline goes; tabs are spaces.
            if (len(lines(k)%s) > 0) then
                if (lines(k)%s(len(lines(k)%s):) == achar(13)) &
                    lines(k)%s = lines(k)%s(1:len(lines(k)%s) - 1)
            end if
            call detab(lines(k)%s)
            i = j + 1
        end do
        do while (n > 0)
            if (len_trim(lines(n)%s) > 0) exit
            n = n - 1
        end do
    end subroutine split_lines

    subroutine detab(s)
        character(len=:), allocatable, intent(inout) :: s
        integer :: k
        do k = 1, len(s)
            if (s(k:k) == achar(9)) s(k:k) = " "
        end do
    end subroutine detab

    ! The closing $ of an inline formula opened at i, as Pandoc finds it:
    ! the opening one has no space after it, the closing one no space
    ! before it and no digit after it. 0 when there is none.
    integer function closing_dollar(s, i) result(j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        j = 0
        if (i >= len(s)) return
        if (s(i + 1:i + 1) == " " .or. s(i + 1:i + 1) == NL) return
        j = i + 1
        do while (j <= len(s))
            if (s(j:j) == BS) then
                j = j + 2
                cycle
            end if
            if (s(j:j) == "$") then
                if (s(j - 1:j - 1) /= " " .and. s(j - 1:j - 1) /= NL) then
                    if (j == len(s)) return
                    if (s(j + 1:j + 1) < "0" .or. s(j + 1:j + 1) > "9") return
                end if
            end if
            j = j + 1
        end do
        j = 0
    end function closing_dollar

    ! The bracket or brace closing the one at i, 0 if none.
    integer function matching(s, i) result(j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        character :: o, c
        integer :: depth
        o = s(i:i)
        if (o == "[") then
            c = "]"
        else if (o == "{") then
            c = "}"
        else
            c = ")"
        end if
        depth = 0
        j = i
        do while (j <= len(s))
            if (s(j:j) == BS) then
                j = j + 2
                cycle
            end if
            if (s(j:j) == o) depth = depth + 1
            if (s(j:j) == c) then
                depth = depth - 1
                if (depth == 0) return
            end if
            j = j + 1
        end do
        j = 0
    end function matching

    ! Whether a quote after prev opens: after a space, an opening bracket
    ! or a hyphen.
    pure logical function opening(prev)
        character, intent(in) :: prev
        opening = white(prev) .or. prev == "(" .or. prev == "[" .or. prev == "{" .or. &
                  prev == "-"
    end function opening

    pure logical function white(c)
        character, intent(in) :: c
        white = c == " " .or. c == NL .or. c == achar(9)
    end function white

    pure logical function punct(c)
        character, intent(in) :: c
        punct = index("!""#$%&'()*+,-./:;<=>?@[\]^_`{|}~", c) > 0
    end function punct

    pure logical function is_alpha(c)
        character, intent(in) :: c
        is_alpha = (c >= "a" .and. c <= "z") .or. (c >= "A" .and. c <= "Z")
    end function is_alpha

    pure logical function is_alnum(c)
        character, intent(in) :: c
        is_alnum = is_alpha(c) .or. (c >= "0" .and. c <= "9")
    end function is_alnum

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

    ! A heading's text without the emphasis marks, for a running head.
    function strip_markup(s) result(t)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t
        integer :: k
        t = ""
        do k = 1, len(s)
            if (s(k:k) /= "*" .and. s(k:k) /= "_" .and. s(k:k) /= "`") t = t//s(k:k)
        end do
    end function strip_markup

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

end module fplotlib_markdown
