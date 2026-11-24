! fplotlib_markdown -- documents in a strict MyST subset of Markdown.
!
! Text is Markdown; TeX is confined to $...$ (inline) and $$...$$ (displayed)
! mathematics. Calls go straight to fplotlib_typeset.
!
! Blocks: YAML front matter (--- ... ---); ATX and setext headings with
! MyST targets (name)=; paragraphs; nested bullet and ordered lists; block
! quotes; fenced code; thematic breaks; and MyST colon-fenced directives
! (:::{name} argument, with :key: value options, dispatched to an optional
! callback).
!
! Inline: *emphasis*, **strong**, `code`, [links](url), hard line breaks
! (a backslash at the end of a line, or two spaces before it), smart
! quotes, --/--- dashes, ... ellipsis, and MyST cross-references:
! $$ ... $$ (eq:name) numbers a display, {eq}`eq:name` writes (n),
! {numref}`sec:name` writes "Section n" (and {numref}`Part %s <sec:name>`
! "Part n"), and {ref}`sec:name` writes the section title (and
! {ref}`text <sec:name>` the text).
!
! Lengths are in points (1/72 in; pt and bp alike), or in pc, in, cm, mm,
! em or ex.
module fplotlib_markdown
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_colors, only: color_from_name
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_BOLD, FACE_ITALIC, face_xheight
    use fplotlib_typeset
    use, intrinsic :: iso_fortran_env, only: error_unit
    implicit none
    private

    public :: md_typeset, md_ctx_t, md_directive_t, md_heading_t
    public :: md_directive_cb, md_body_cb, md_heading_cb
    public :: md_blocks, md_inline, md_option, md_meta
    public :: md_length, md_color, md_align, md_noindent, md_base_size

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

    ! Where blocks are set, as the callbacks are given it: a template
    ! copies it, changes what it wants, and sets blocks with the copy
    ! (md_blocks, md_inline). left and right are how far the text is moved
    ! in from the margins, in points; align is one of fplotlib_typeset's
    ! ALIGN_*; size is the type size in points, and color is 0xRRGGBB; bold
    ! and italic are the face; indent is whether a justified paragraph's
    ! first line is indented. The nesting of lists and quotations is the
    ! core's own, and private.
    type :: md_ctx_t
        real(dp) :: left = 0.0_dp, right = 0.0_dp
        integer :: align = ALIGN_JUSTIFY
        real(dp) :: size = 10.0_dp
        integer :: color = 0
        logical :: bold = .false., italic = .false.
        logical :: indent = .true.
        integer, private :: depth = 0
        integer, private :: ilev = 0, elev = 0
    end type md_ctx_t

    ! A MyST directive, as on_directive is given it:
    !
    !     :::{name} argument
    !     :key: value
    !     body
    !     :::
    !
    ! name in lower case; the argument, the rest of the opening line; opts,
    ! the :key: value lines, one to a line (md_option reads them); and the
    ! body, the lines after them. A directive is one argument, so that what
    ! it is given may grow without changing the callbacks.
    type :: md_directive_t
        character(len=:), allocatable :: name, arg, opts, body
    end type md_directive_t

    ! A heading, as on_heading is given it: its level (1 for #), its text,
    ! and its number ("" when it has none), such as "2.1". One argument,
    ! as a directive is.
    type :: md_heading_t
        integer :: level = 0
        character(len=:), allocatable :: text, num
    end type md_heading_t

    ! The callbacks a template gives md_typeset. on_directive sets a MyST
    ! directive, and on_heading a heading; either sets handled to .true.
    ! when it did (it is .false. on entry, and a callback that leaves it so
    ! leaves the block to the core), and what it leaves is set as the core
    ! sets it: a directive's body as blocks, a heading as LaTeX's \section.
    ! on_body is called before the body (after false) and after it (true).
    abstract interface
        subroutine md_directive_cb(directive, ctx, handled)
            import :: md_directive_t, md_ctx_t
            type(md_directive_t), intent(in) :: directive
            type(md_ctx_t), intent(in) :: ctx
            logical, intent(inout) :: handled
        end subroutine md_directive_cb

        subroutine md_body_cb(after, ctx)
            import :: md_ctx_t
            logical, intent(in) :: after
            type(md_ctx_t), intent(in) :: ctx
        end subroutine md_body_cb

        subroutine md_heading_cb(heading, ctx, handled)
            import :: md_heading_t, md_ctx_t
            type(md_heading_t), intent(in) :: heading
            type(md_ctx_t), intent(in) :: ctx
            logical, intent(inout) :: handled
        end subroutine md_heading_cb
    end interface

    ! Active template callbacks for the current md_typeset call.
    procedure(md_directive_cb), pointer, save :: CB_DIR => null()
    procedure(md_body_cb), pointer, save :: CB_BODY => null()
    procedure(md_heading_cb), pointer, save :: CB_HEAD => null()

    ! The document's settings.
    real(dp) :: BASE = 10.0_dp, LEAD = 1.2_dp
    real(dp) :: PARINDENT = 15.0_dp
    type(ts_glue_t) :: PARSKIP_G
    integer :: DOC_ALIGN = ALIGN_JUSTIFY
    logical :: NUMBER_SECTIONS = .false., CHAPTERS = .false., NUMBER_EQS = .false.
    character(len=:), allocatable :: TITLE, SUBTITLE, AUTHOR, DATE, ABSTRACT
    integer :: TEXT_COL = 0, PAGE_COL = 16777215
    integer, parameter :: LINK_COL = 1728436, CODE_COL = 5263440

    ! The front matter's keys and values, for templates (md_meta).
    type :: meta_t
        character(len=:), allocatable :: key, val
    end type meta_t
    integer :: NMETA = 0
    type(meta_t), allocatable :: META(:)

    ! Counters and cross references. A label is a heading's or a display's
    ! name, its number ("" when it has none) and, for a heading, its title.
    integer :: SEC(4) = 0, CHAPTER = 0, EQNO = 0
    integer, parameter :: LAB_SECTION = 1, LAB_EQUATION = 2, LAB_OTHER = 3
    type :: label_t
        character(len=:), allocatable :: name, num, title
        integer :: kind = LAB_SECTION
    end type label_t
    integer :: NLAB = 0
    type(label_t), allocatable :: LABS(:)

    ! The document is set twice, as LaTeX is run twice: the first pass
    ! numbers the headings and displays and records their labels, and the
    ! second, with every label known, sets the pages.
    logical :: FIRST_PASS = .false.

    ! The MyST targets, (name)=, waiting for the block they label; and
    ! whether the last block was a heading (LaTeX's @nobreak), after which
    ! a heading adds no space and no break of its own.
    character(len=:), allocatable :: TARGETS
    logical :: AFTER_HEADING = .false.

    ! Next paragraph is not indented (after a heading or display), and the
    ! labels of items waiting for their first line: an item's own and, when
    ! an item begins with a list, those of the items it is in, each with
    ! the left edge of its item's text.
    logical :: NOINDENT = .false.
    type :: pending_t
        character(len=:), allocatable :: s
        real(dp) :: left = 0.0_dp
    end type pending_t
    integer :: NPEND = 0
    type(pending_t), allocatable :: PENDING(:)

contains

    ! ------------------------------------------------------------------
    ! The document.
    ! ------------------------------------------------------------------

    ! Set text, a MyST Markdown document, into fplotlib_typeset's pages.
    ! The document is set twice (see FIRST_PASS), so the callbacks are
    ! called twice, and only the second pass's pages are kept.
    subroutine md_typeset(text, on_directive, on_body, on_heading)
        character(len=*), intent(in) :: text
        procedure(md_directive_cb), optional :: on_directive
        procedure(md_body_cb), optional :: on_body
        procedure(md_heading_cb), optional :: on_heading
        type(line_t), allocatable :: lines(:)
        type(md_ctx_t) :: ctx
        integer :: n, first, pass

        CB_DIR => null()
        CB_BODY => null()
        CB_HEAD => null()
        if (present(on_directive)) CB_DIR => on_directive
        if (present(on_body)) CB_BODY => on_body
        if (present(on_heading)) CB_HEAD => on_heading

        call split_lines(text, lines, n)
        NLAB = 0
        do pass = 1, 2
            FIRST_PASS = pass == 1
            call ts_reset()
            call defaults()
            first = 1
            call front_matter(lines, n, first)
            call ts_set_font(BASE, LEAD*BASE)
            call ts_set_parskip(PARSKIP_G)
            call ts_set_colors(TEXT_COL, PAGE_COL)
            SEC = 0
            CHAPTER = 0
            EQNO = 0
            TARGETS = ""
            AFTER_HEADING = .false.
            ctx = md_ctx_t()
            ctx%size = BASE
            ctx%color = TEXT_COL
            ctx%align = DOC_ALIGN
            call title_block(ctx)
            if (associated(CB_BODY)) call CB_BODY(.false., ctx)
            if (first <= n) call blocks(lines(first:n), n - first + 1, ctx)
            call place_targets()
            if (associated(CB_BODY)) call CB_BODY(.true., ctx)
        end do
        FIRST_PASS = .false.
        call ts_paginate()

        CB_DIR => null()
        CB_BODY => null()
        CB_HEAD => null()
    end subroutine md_typeset

    subroutine defaults()
        BASE = 10.0_dp
        LEAD = 1.2_dp
        PARINDENT = -1.0_dp
        PARSKIP_G = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        DOC_ALIGN = ALIGN_JUSTIFY
        NUMBER_SECTIONS = .false.
        NUMBER_EQS = .false.
        CHAPTERS = .false.
        TITLE = ""
        SUBTITLE = ""
        AUTHOR = ""
        DATE = ""
        ABSTRACT = ""
        TEXT_COL = 0
        PAGE_COL = 16777215
        NMETA = 0
        NOINDENT = .false.
        NPEND = 0
        call ts_set_page(595.2756_dp, 841.8898_dp, 72.0_dp, 72.0_dp, 72.0_dp, 72.0_dp)
    end subroutine defaults

    ! The front matter: "key: value" lines between a first line of --- and
    ! the next line of --- (or ...). Without that closing line there is no
    ! front matter, and the --- is a rule. The type size is read first, as
    ! the em and ex of the other values are its. A value that cannot be
    ! read is warned of, and the setting keeps its default.
    subroutine front_matter(lines, n, first)
        type(line_t), intent(in) :: lines(:)
        integer, intent(in) :: n
        integer, intent(inout) :: first
        integer :: i, last, c
        character(len=:), allocatable :: key, val
        real(dp) :: pw, ph, ml, mr, mt, mb, m, x
        logical :: numbers, heads, flushb, ok

        pw = 595.2756_dp
        ph = 841.8898_dp
        m = -1.0_dp
        ml = -1.0_dp
        mr = -1.0_dp
        mt = -1.0_dp
        mb = -1.0_dp
        numbers = .true.
        heads = .false.
        flushb = .false.
        last = 0
        if (n >= 1) then
            if (trim(lines(1)%s) == "---") then
                do i = 2, n
                    if (trim(lines(i)%s) == "---" .or. trim(lines(i)%s) == "...") then
                        last = i
                        exit
                    end if
                end do
            end if
        end if
        do i = 2, last - 1
            if (.not. entry(lines, i, last, key, val)) cycle
            if (key /= "fontsize") cycle
            x = length(val, BASE, ok)
            if (ok) BASE = x
        end do
        do i = 2, last - 1
            if (.not. entry(lines, i, last, key, val)) cycle
            call add_meta(key, val)
            select case (key)
            case ("title")
                TITLE = val
            case ("subtitle")
                SUBTITLE = val
            case ("author", "authors")
                if (len(AUTHOR) > 0) then
                    AUTHOR = AUTHOR//NL//val
                else
                    AUTHOR = val
                end if
            case ("date")
                DATE = val
            case ("abstract")
                ABSTRACT = val
            case ("linestretch", "leading")
                x = number(val, ok)
                if (ok) LEAD = 1.2_dp*x
            case ("paper", "papersize")
                call paper_size(lower(val), pw, ph)
            case ("margin")
                call set_length(val, m)
            case ("margin-left")
                call set_length(val, ml)
            case ("margin-right")
                call set_length(val, mr)
            case ("margin-top")
                call set_length(val, mt)
            case ("margin-bottom")
                call set_length(val, mb)
            case ("indent", "parindent")
                if (lower(val) == "false" .or. lower(val) == "no") then
                    PARINDENT = 0.0_dp
                else if (lower(val) /= "true" .and. lower(val) /= "yes") then
                    call set_length(val, PARINDENT)
                end if
            case ("parskip")
                x = length(val, BASE, ok)
                if (ok) then
                    PARSKIP_G = ts_glue_t(x, 0.2_dp*x, 0.0_dp, 0, 0)
                    if (PARINDENT < 0.0_dp) PARINDENT = 0.0_dp
                end if
            case ("align")
                c = align_of(lower(val), -1)
                if (c < 0) then
                    call warn("cannot read the alignment '"//val//"'")
                else
                    DOC_ALIGN = c
                end if
            case ("numbersections", "number-sections")
                NUMBER_SECTIONS = flag(val)
            case ("numberequations", "number-equations")
                NUMBER_EQS = flag(val)
            case ("pagenumbers", "page-numbers")
                numbers = flag(val)
            case ("runningheads", "running-heads")
                heads = flag(val)
            case ("flushbottom", "flush-bottom")
                flushb = flag(val)
            case ("chapters")
                CHAPTERS = flag(val)
            case ("color", "fontcolor")
                call set_color(val, TEXT_COL)
            case ("pagecolor", "background")
                call set_color(val, PAGE_COL)
            end select
        end do
        if (last > 0) first = last + 1
        if (PARINDENT < 0.0_dp) PARINDENT = 1.5_dp*BASE
        ! LaTeX's geometry is set here by margins; without them, one inch.
        if (m < 0.0_dp) m = 72.0_dp
        if (ml < 0.0_dp) ml = m
        if (mr < 0.0_dp) mr = m
        if (mt < 0.0_dp) mt = m
        if (mb < 0.0_dp) mb = m
        call ts_set_page(pw, ph, ml, mr, mt, mb, numbers, heads, flushb)
    end subroutine front_matter

    ! The key and value of front matter line i, when it is a line that is
    ! not indented and has a colon. The value goes on over the indented
    ! lines after it, up to line last; "- item" lines, or [a, b], are a
    ! list, its items one to a line.
    logical function entry(lines, i, last, key, val)
        type(line_t), intent(in) :: lines(:)
        integer, intent(in) :: i, last
        character(len=:), allocatable, intent(out) :: key, val
        character(len=:), allocatable :: t
        integer :: c, j
        entry = .false.
        key = ""
        val = ""
        if (len(lines(i)%s) == 0) return
        if (lines(i)%s(1:1) == " ") return
        c = index(lines(i)%s, ":")
        if (c == 0) return
        entry = .true.
        key = trim(lower(adjustl(lines(i)%s(1:c - 1))))
        val = unquote(trim(adjustl(lines(i)%s(c + 1:))))
        if (val == "|" .or. val == ">") val = ""
        if (len(val) >= 2) then
            if (val(1:1) == "[" .and. val(len(val):) == "]") val = flow_list(val(2:len(val) - 1))
        end if
        do j = i + 1, last - 1
            if (len(lines(j)%s) == 0) exit
            if (lines(j)%s(1:1) /= " ") exit
            t = trim(adjustl(lines(j)%s))
            if (starts(t, "- ")) then
                if (len(val) > 0) val = val//NL
                val = val//unquote(trim(adjustl(t(3:))))
            else
                if (len(val) > 0) val = val//" "
                val = val//t
            end if
        end do
    end function entry

    ! The items of a YAML flow list, a, "b, c", one to a line.
    function flow_list(s) result(t)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t
        character :: q
        integer :: i, j
        t = ""
        q = " "
        j = 1
        do i = 1, len(s) + 1
            if (i <= len(s)) then
                if (q /= " ") then
                    if (s(i:i) == q) q = " "
                    cycle
                end if
                if (s(i:i) == '"' .or. s(i:i) == "'") then
                    q = s(i:i)
                    cycle
                end if
                if (s(i:i) /= ",") cycle
            end if
            if (len(t) > 0) t = t//NL
            t = t//unquote(trim(adjustl(s(j:i - 1))))
            j = i + 1
        end do
    end function flow_list

    ! A front matter value, kept for the templates (md_meta).
    subroutine add_meta(key, val)
        character(len=*), intent(in) :: key, val
        type(meta_t), allocatable :: grown(:)
        if (.not. allocated(META)) allocate (META(16))
        if (NMETA == size(META)) then
            allocate (grown(2*size(META)))
            grown(1:NMETA) = META(1:NMETA)
            call move_alloc(grown, META)
        end if
        NMETA = NMETA + 1
        META(NMETA)%key = key
        META(NMETA)%val = val
    end subroutine add_meta

    subroutine set_length(val, var)
        character(len=*), intent(in) :: val
        real(dp), intent(inout) :: var
        real(dp) :: x
        logical :: ok
        x = length(val, BASE, ok)
        if (ok) var = x
    end subroutine set_length

    subroutine set_color(val, var)
        character(len=*), intent(in) :: val
        integer, intent(inout) :: var
        integer :: c
        c = color_of(val, -1)
        if (c < 0) then
            call warn("cannot read the colour '"//val//"'")
        else
            var = c
        end if
    end subroutine set_color

    ! A yes or no: true, yes or 1, or false, no or 0.
    logical function flag(val)
        character(len=*), intent(in) :: val
        flag = truth(val)
        select case (lower(trim(val)))
        case ("true", "yes", "1", "false", "no", "0")
        case default
            call warn("cannot read '"//val//"' as true or false")
        end select
    end function flag

    subroutine paper_size(v, w, h)
        character(len=*), intent(in) :: v
        real(dp), intent(inout) :: w, h
        real(dp) :: a, b
        logical :: oka, okb
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
            oka = .false.
            okb = .false.
            if (x > 0) then
                a = length(trim(v(1:x - 1)), BASE, oka)
                b = length(trim(v(x + 1:)), BASE, okb)
            end if
            if (oka .and. okb) then
                w = a
                h = b
            else
                call warn("cannot read the paper '"//v//"'")
            end if
        end select
    end subroutine paper_size

    ! LaTeX's \maketitle and abstract, for the article class.
    subroutine title_block(ctx)
        type(md_ctx_t), intent(in) :: ctx
        type(style_t) :: st
        integer :: i, j
        ! The title, with its authors and date; an abstract is set with or
        ! without one.
        if (len(TITLE) > 0) then
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
        end if
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
        type(md_ctx_t), intent(in) :: ctx
        integer :: i, j, k, lev, depth
        character(len=:), allocatable :: s, t, para, lab
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

            ! A MyST target labels the block after it, and is not set.
            if (is_target(t, lab)) then
                TARGETS = TARGETS//" "//lab
                i = i + 1
                cycle
            end if
            if (is_heading(t, lev)) then
                call heading(heading_text(t, lev), lev, ctx)
                i = i + 1
            else if (is_fence(t)) then
                call other_block()
                j = i + 1
                do while (j <= n)
                    if (is_fence(trim(adjustl(L(j)%s)))) exit
                    j = j + 1
                end do
                call code_block(L(i + 1:min(j - 1, n)), max(0, min(j - 1, n) - i), ctx)
                i = j + 1
            else if (starts(t, ":::") .and. div_opens(t)) then
                depth = 0
                do j = i, n
                    if (.not. starts(trim(adjustl(L(j)%s)), ":::")) cycle
                    if (div_opens(trim(adjustl(L(j)%s)))) then
                        depth = depth + 1
                    else
                        depth = depth - 1
                        if (depth == 0) exit
                    end if
                end do
                call other_block()
                call set_div(t, L, i, j, ctx)
                i = j + 1
            else if (t(1:1) == ">") then
                j = i
                do while (j <= n)
                    if (len_trim(L(j)%s) == 0) exit
                    j = j + 1
                end do
                call other_block()
                call quote_block(L(i:j - 1), j - i, ctx)
                i = j
            else if (is_item(s, k, lev)) then
                call other_block()
                call list_block(L, n, i, ctx, blank_before)
            else if (is_rule(t)) then
                call other_block()
                call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                call ts_begin_par(ALIGN_CENTER, 0.0_dp, left=ctx%left, right=ctx%right)
                call ts_end_par()
                call ts_rule(0.5_dp*(ts_hsize() - ctx%left - ctx%right), 0.5_dp, ctx%color)
                call ts_addvspace(scale(ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                i = i + 1
            else
                para = ""
                j = i
                do while (j <= n)
                    t = trim(adjustl(L(j)%s))
                    if (len(t) == 0) exit
                    ! Inside a display, a line is mathematics, whatever it
                    ! starts with.
                    if (j > i .and. .not. open_display(para)) then
                        if (interrupts(L(j)%s)) exit
                        if (j == i + 1 .and. (is_underline(t, "=") .or. &
                                              is_underline(t, "-"))) exit
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
                        blank_before = .false.
                        cycle
                    end if
                end if
                call other_block()
                call paragraph(para, ctx)
                i = j
            end if
            blank_before = .false.
        end do
    end subroutine blocks

    ! A block that is not a heading: the targets before it label it, and a
    ! heading after it is not one straight after a heading.
    subroutine other_block()
        call place_targets()
        AFTER_HEADING = .false.
    end subroutine other_block

    ! The targets waiting for a block label it: a heading with its number
    ! and title, anything else with neither, for a reference that gives
    ! its own text.
    subroutine place_targets(num, title)
        character(len=*), intent(in), optional :: num, title
        character(len=:), allocatable :: name
        integer :: k
        do while (len_trim(TARGETS) > 0)
            TARGETS = adjustl(TARGETS)
            k = index(TARGETS, " ")
            if (k == 0) k = len(TARGETS) + 1
            name = TARGETS(1:k - 1)
            TARGETS = TARGETS(k:)
            if (present(num)) then
                call add_label(name, num, title, LAB_SECTION)
            else
                call add_label(name, "", "", LAB_OTHER)
            end if
        end do
        TARGETS = ""
    end subroutine place_targets

    ! Whether a line starts a block that ends a paragraph before it.
    logical function interrupts(s)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t, lab
        integer :: k, lev
        t = trim(adjustl(s))
        interrupts = .false.
        if (len(t) == 0) return
        if (is_heading(t, lev) .or. is_fence(t) .or. (starts(t, ":::") .and. div_opens(t)) .or. &
            t(1:1) == ">" .or. is_rule(t) .or. is_target(t, lab)) then
            interrupts = .true.
        else if (is_item(s, k, lev)) then
            interrupts = lev == 0 .or. k == 1
        end if
    end function interrupts

    ! Whether text leaves a $$ display open: whether it has an odd number
    ! of $$, outside code spans and escapes.
    logical function open_display(text)
        character(len=*), intent(in) :: text
        integer :: i, j, r
        open_display = .false.
        i = 1
        do while (i <= len(text))
            if (text(i:i) == BS) then
                i = i + 2
            else if (text(i:i) == "`" .and. .not. open_display) then
                r = 1
                do while (i + r <= len(text))
                    if (text(i + r:i + r) /= "`") exit
                    r = r + 1
                end do
                j = index(text(i + r:), repeat("`", r))
                i = i + r
                if (j > 0) i = i + j - 1 + r
            else if (i < len(text) .and. text(i:i) == "$") then
                if (text(i + 1:i + 1) == "$") then
                    open_display = .not. open_display
                    i = i + 2
                else
                    i = i + 1
                end if
            else
                i = i + 1
            end if
        end do
    end function open_display

    ! A paragraph of inline text in the context's settings.
    subroutine paragraph(text, ctx)
        character(len=*), intent(in) :: text
        type(md_ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: s
        real(dp) :: ind
        s = trim(adjustl(text))
        ind = 0.0_dp
        if (ctx%indent .and. .not. NOINDENT .and. ctx%align == ALIGN_JUSTIFY) ind = PARINDENT
        NOINDENT = .false.
        call ts_begin_par(ctx%align, ind, left=ctx%left, right=ctx%right, size=ctx%size, &
                          leading=LEAD*ctx%size)
        call put_labels(ctx, ctx%left)
        call inline(s, base_style(ctx))
        call ts_end_par()
    end subroutine paragraph

    ! An item's label, waiting for the item's first line.
    subroutine push_label(s, left)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: left
        type(pending_t), allocatable :: grown(:)
        if (.not. allocated(PENDING)) allocate (PENDING(4))
        if (NPEND == size(PENDING)) then
            allocate (grown(2*size(PENDING)))
            grown(1:NPEND) = PENDING(1:NPEND)
            call move_alloc(grown, PENDING)
        end if
        NPEND = NPEND + 1
        PENDING(NPEND)%s = s
        PENDING(NPEND)%left = left
    end subroutine push_label

    ! The labels waiting for the line just begun, whose text starts at
    ! left: each half an em before its own item's text.
    subroutine put_labels(ctx, left)
        type(md_ctx_t), intent(in) :: ctx
        real(dp), intent(in) :: left
        integer :: k
        do k = 1, NPEND
            call ts_label(PENDING(k)%s, label_face(ctx), ctx%size, &
                          0.5_dp*BASE + left - PENDING(k)%left, ctx%color)
        end do
        NPEND = 0
    end subroutine put_labels

    integer function label_face(ctx)
        type(md_ctx_t), intent(in) :: ctx
        label_face = FACE_REGULAR
        if (ctx%bold) label_face = FACE_BOLD
    end function label_face

    ! Headings: LaTeX's \section, \subsection and \subsubsection, numbered
    ! within the chapter in a book, unless on_heading sets them.
    subroutine heading(text0, level, ctx)
        character(len=*), intent(in) :: text0
        integer, intent(in) :: level
        type(md_ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: text, num
        type(style_t) :: st
        real(dp) :: ex, size, baseline, hang
        type(ts_glue_t) :: before, after
        integer :: lv, k
        logical :: handled
        type(md_heading_t) :: this

        text = trim(text0)
        ex = face_xheight(FACE_REGULAR)*BASE
        lv = level
        num = ""
        if (CHAPTERS .and. level == 1) then
            CHAPTER = CHAPTER + 1
            SEC = 0
            EQNO = 0
            if (NUMBER_SECTIONS) num = itoa(CHAPTER)
        else
            if (CHAPTERS) lv = level - 1
            if (NUMBER_SECTIONS .and. lv <= 3) then
                SEC(lv) = SEC(lv) + 1
                SEC(lv + 1:) = 0
                if (CHAPTERS) then
                    num = itoa(CHAPTER)
                else
                    num = itoa(SEC(1))
                end if
                do k = merge(1, 2, CHAPTERS), lv
                    num = num//"."//itoa(SEC(k))
                end do
            end if
        end if
        call place_targets(num, strip_markup(text))
        if (associated(CB_HEAD)) then
            this%level = level
            this%text = text
            this%num = num
            handled = .false.
            call CB_HEAD(this, ctx, handled)
            if (handled) then
                AFTER_HEADING = .true.
                return
            end if
        end if
        select case (lv)
        case (1)
            size = 1.44_dp*BASE
            baseline = 18.0_dp*BASE/10.0_dp
            before = ts_glue_t(3.5_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(2.3_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case (2)
            size = 1.2_dp*BASE
            baseline = 14.0_dp*BASE/10.0_dp
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case default
            size = BASE
            baseline = LEAD*BASE
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        end select
        ! Straight after a heading, the space after that one is all there
        ! is, as \@startsection has it when @nobreak is set.
        if (.not. AFTER_HEADING) then
            call ts_addpenalty(-300)
            call ts_addvspace(before)
        end if
        st = base_style(ctx)
        st%bold = .true.
        st%size = size
        hang = 0.0_dp
        if (len(num) > 0) hang = text_width(num, FACE_BOLD, size) + size
        call ts_begin_par(ALIGN_JUSTIFY, 0.0_dp, left=ctx%left, right=ctx%right, size=size, &
                          leading=baseline, hang=hang, nobreak=.true.)
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
        AFTER_HEADING = .true.
    end subroutine heading

    ! A list: LaTeX's itemize or enumerate, with its spacing at the depth
    ! it is at. A tight list (no blank lines between its items) is set as
    ! Pandoc's \tightlist sets it, without \itemsep and \parsep.
    recursive subroutine list_block(L, n, i, ctx, blank_before)
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        integer, intent(inout) :: i
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(in) :: blank_before
        type(line_t), allocatable :: item(:)
        integer :: j, k, num, lev, col, kind, ni, nitem, start_num, ind0, m, ln, k2, lev2
        logical :: tight, blank
        type(md_ctx_t) :: sub
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
        sub%align = ctx%align
        if (kind == 0) then
            sub%ilev = ctx%ilev + 1
        else
            sub%elev = ctx%elev + 1
        end if
        if (NPEND > 0) then
            ! A list that begins an item starts on the item's first line,
            ! its labels after the item's, as LaTeX's \@donoparitem has it.
            call ts_end_par()
        else if (blank_before .and. .not. ts_in_par()) then
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
            call push_label(list_label(kind, merge(sub%ilev, sub%elev, kind == 0), num), sub%left)
            call ts_set_parskip(parsep)
            call blocks(item, ni, sub)
            if (NPEND > 0) then
                ! An item with no paragraph of its own still has its label.
                call ts_begin_par(sub%align, 0.0_dp, left=sub%left, right=sub%right, &
                                  size=sub%size)
                call put_labels(sub, sub%left)
                call ts_strut(0.7_dp*sub%size, 0.3_dp*sub%size)
                call ts_end_par()
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
        type(md_ctx_t), intent(in) :: ctx
        type(line_t), allocatable :: q(:)
        type(md_ctx_t) :: sub
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
        type(md_ctx_t), intent(in) :: ctx
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
            if (k == 1) call put_labels(ctx, ctx%left + 1.5_dp*BASE)
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

    ! A MyST directive :::{name} argument, followed by :key: value options
    ! and content, dispatched to the caller's on_directive callback when
    ! supplied.
    recursive subroutine set_div(open_line, L, i, j, ctx)
        character(len=*), intent(in) :: open_line
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: i, j
        type(md_ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: rest, name, arg, opts, body, line
        type(md_directive_t) :: directive
        integer :: a, c, k, content_at
        logical :: handled

        name = ""
        arg = ""
        rest = ""
        a = verify(open_line, ":")
        if (a > 0) rest = trim(adjustl(open_line(a:)))
        if (len(rest) >= 2) then
            if (rest(1:1) == "{") then
                a = index(rest, "}")
                if (a >= 2) then
                    name = trim(lower(trim(adjustl(rest(2:a - 1)))))
                    arg = trim(adjustl(rest(a + 1:)))
                end if
            end if
        end if

        opts = ""
        content_at = i + 1
        do while (content_at < j)
            line = trim(adjustl(L(content_at)%s))
            if (len(line) < 3) exit
            if (line(1:1) /= ":") exit
            c = index(line(2:), ":")
            if (c < 2) exit
            if (len(opts) > 0) opts = opts//NL
            opts = opts//line
            content_at = content_at + 1
        end do

        body = ""
        do k = content_at, j - 1
            if (len(body) > 0) body = body//NL
            body = body//L(k)%s
        end do

        directive%name = name
        directive%arg = arg
        directive%opts = opts
        directive%body = body
        handled = .false.
        if (associated(CB_DIR)) call CB_DIR(directive, ctx, handled)
        if (.not. handled .and. j - 1 >= content_at) &
            call blocks(L(content_at:j - 1), j - content_at, ctx)
    end subroutine set_div

    ! --- Template helpers -------------------------------------------------

    recursive subroutine md_blocks(body, ctx)
        character(len=*), intent(in) :: body
        type(md_ctx_t), intent(in) :: ctx
        type(line_t), allocatable :: L(:)
        integer :: n
        if (len_trim(body) == 0) return
        call split_lines(body, L, n)
        if (n > 0) call blocks(L, n, ctx)
    end subroutine md_blocks

    subroutine md_inline(text, ctx)
        character(len=*), intent(in) :: text
        type(md_ctx_t), intent(in) :: ctx
        call inline(text, base_style(ctx))
    end subroutine md_inline

    function md_option(opts, key) result(val)
        character(len=*), intent(in) :: opts, key
        character(len=:), allocatable :: val, want, line
        integer :: i, j, c
        val = ""
        want = lower(trim(key))
        i = 1
        do while (i <= len(opts))
            j = index(opts(i:), NL)
            if (j == 0) then
                line = trim(adjustl(opts(i:)))
                i = len(opts) + 1
            else
                line = trim(adjustl(opts(i:i + j - 2)))
                i = i + j
            end if
            if (len(line) < 3) cycle
            if (line(1:1) /= ":") cycle
            c = index(line(2:), ":")
            if (c < 2) cycle
            if (lower(line(2:c)) == want) then
                val = trim(adjustl(line(c + 2:)))
                return
            end if
        end do
    end function md_option

    function md_meta(key) result(val)
        character(len=*), intent(in) :: key
        character(len=:), allocatable :: val, want
        integer :: k
        val = ""
        want = lower(trim(key))
        do k = 1, NMETA
            if (META(k)%key == want) then
                val = META(k)%val
                return
            end if
        end do
    end function md_meta

    subroutine md_noindent(flag)
        logical, intent(in) :: flag
        NOINDENT = flag
    end subroutine md_noindent

    real(dp) function md_base_size()
        md_base_size = BASE
    end function md_base_size

    real(dp) function md_length(v, size)
        character(len=*), intent(in) :: v
        real(dp), intent(in) :: size
        md_length = length(v, size)
    end function md_length

    integer function md_color(v, dflt)
        character(len=*), intent(in) :: v
        integer, intent(in) :: dflt
        md_color = color_of(v, dflt)
    end function md_color

    integer function md_align(v, dflt)
        character(len=*), intent(in) :: v
        integer, intent(in) :: dflt
        md_align = align_of(lower(trim(v)), dflt)
    end function md_align

    ! ------------------------------------------------------------------
    ! Inline text.
    ! ------------------------------------------------------------------

    function base_style(ctx) result(st)
        type(md_ctx_t), intent(in) :: ctx
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
                call delimiter_run(s, i, r, lf, rf)
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
                else if (lf .and. r <= 3 .and. has_closer(s, i + r, c, r)) then
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
                        ! A display, optionally followed by a MyST (label).
                        j = index(s(i + 2:), "$$")
                        if (j > 0) then
                            call flush()
                            src = s(i + 2:i + j)
                            k = i + j + 3
                            tag = ""
                            call display_tag(s, k, tag)
                            call ts_math(src, st%size, st%color, display=.true., tag=tag)
                            space = .false.
                            i = k
                            do while (i <= len(s))
                                if (s(i:i) /= " " .and. s(i:i) /= NL) exit
                                i = i + 1
                            end do
                            cycle
                        end if
                        ! A $$ that is not closed is text.
                        w = w//"$$"
                        i = i + 2
                        cycle
                    end if
                end if
                j = closing_dollar(s, i)
                if (j > 0) then
                    call flush()
                    call flush_space()
                    call ts_math(s(i + 1:j - 1), st%size, st%color, display=.false.)
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
                else if (punct(next)) then
                    w = w//next
                    i = i + 2
                else
                    w = w//BS
                    i = i + 1
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
                            call flush_space()
                            call inline(s(i + 1:j - 1), sp)
                            i = j + k + 1
                            cycle
                        end if
                    end if
                end if
                w = w//"["
                i = i + 1
            case ("{")
                ! MyST cross-reference roles: {eq}`name`, {numref}`name`, {ref}`name`.
                j = index(s(i:), "}`")
                if (j > 2) then
                    cmd = lower(trim(s(i + 1:i + j - 2)))
                    if (cmd == "eq" .or. cmd == "ref" .or. cmd == "numref") then
                        k = index(s(i + j + 1:), "`")
                        if (k > 1) then
                            arg = trim(s(i + j + 1:i + j + k - 1))
                            w = w//reference(cmd, arg)
                            i = i + j + k + 1
                            cycle
                        end if
                    end if
                end if
                w = w//"{"
                i = i + 1
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

    end subroutine inline

    ! The run of * or _ at s(i:i): its length r, and whether it can open
    ! (lf, left-flanking) and close (rf, right-flanking) emphasis, by
    ! CommonMark's rules. Inside a word, an underscore is just that.
    subroutine delimiter_run(s, i, r, lf, rf)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        integer, intent(out) :: r
        logical, intent(out) :: lf, rf
        character :: c, prev, next
        c = s(i:i)
        r = 1
        do while (i + r <= len(s))
            if (s(i + r:i + r) /= c) exit
            r = r + 1
        end do
        prev = " "
        if (i > 1) prev = s(i - 1:i - 1)
        next = " "
        if (i + r <= len(s)) next = s(i + r:i + r)
        lf = .not. white(next) .and. (.not. punct(next) .or. white(prev) .or. punct(prev))
        rf = .not. white(prev) .and. (.not. punct(prev) .or. white(next) .or. punct(next))
        if (c == "_" .and. lf .and. rf) then
            lf = .false.
            rf = .false.
        end if
    end subroutine delimiter_run

    ! Whether a run of r c's that opens emphasis is closed after s(from:):
    ! by a run of c that can close it (one or three for *, two or three
    ! for **, any for ***), outside code spans, mathematics and escapes,
    ! and not taken by an opener nearer to it. A run with nothing to close
    ! it is text, as in CommonMark.
    logical function has_closer(s, from, c, r) result(found)
        character(len=*), intent(in) :: s
        integer, intent(in) :: from, r
        character, intent(in) :: c
        integer :: j, q, k, nearer
        logical :: lf, rf
        found = .false.
        nearer = 0
        j = from
        do while (j <= len(s))
            if (s(j:j) == BS) then
                j = j + 2
            else if (s(j:j) == "`") then
                q = 1
                do while (j + q <= len(s))
                    if (s(j + q:j + q) /= "`") exit
                    q = q + 1
                end do
                k = index(s(j + q:), repeat("`", q))
                j = j + q
                if (k > 0) j = j + k - 1 + q
            else if (s(j:j) == "$") then
                k = 0
                if (j < len(s)) then
                    if (s(j + 1:j + 1) == "$") then
                        k = index(s(j + 2:), "$$")
                        if (k > 0) k = j + k + 2
                    end if
                end if
                if (k == 0) k = closing_dollar(s, j)
                j = max(j, k) + 1
            else if (s(j:j) == c) then
                call delimiter_run(s, j, q, lf, rf)
                if (rf .and. nearer > 0) then
                    nearer = nearer - 1
                else if (rf) then
                    select case (r)
                    case (1)
                        found = q == 1 .or. q >= 3
                    case (2)
                        found = q >= 2
                    case default
                        found = .true.
                    end select
                    if (found) return
                else if (lf) then
                    nearer = nearer + 1
                end if
                j = j + q
            else
                j = j + 1
            end if
        end do
    end function has_closer

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

    ! Parse a MyST display label ` (name)` immediately after `$$`.
    logical function parse_display_label(s, k, name)
        character(len=*), intent(in) :: s
        integer, intent(inout) :: k
        character(len=:), allocatable, intent(out) :: name
        integer :: j, b, c
        parse_display_label = .false.
        name = ""
        j = k
        do while (j <= len(s))
            if (s(j:j) /= " ") exit
            j = j + 1
        end do
        if (j > len(s)) return
        if (s(j:j) /= "(") return
        b = index(s(j:), ")")
        if (b < 3) return
        name = s(j + 1:j + b - 2)
        do c = 1, len(name)
            if (name(c:c) == " " .or. name(c:c) == NL .or. name(c:c) == "(") then
                name = ""
                return
            end if
        end do
        k = j + b
        parse_display_label = .true.
    end function parse_display_label

    ! A MyST (label) after $$ numbers the display.
    subroutine display_tag(s, k, tag)
        character(len=*), intent(in) :: s
        integer, intent(inout) :: k
        character(len=:), allocatable, intent(inout) :: tag
        character(len=:), allocatable :: name
        logical :: numbered
        numbered = NUMBER_EQS
        if (parse_display_label(s, k, name)) numbered = .true.
        if (numbered) then
            EQNO = EQNO + 1
            if (CHAPTERS) then
                tag = itoa(CHAPTER)//"."//itoa(EQNO)
            else
                tag = itoa(EQNO)
            end if
        end if
        if (len(name) > 0) call add_label(name, tag, "", LAB_EQUATION)
    end subroutine display_tag

    ! ------------------------------------------------------------------
    ! Cross references: the labels of headings and displays, with the
    ! numbers the first pass gave them, so that a reference may come
    ! before what it refers to.
    ! ------------------------------------------------------------------

    ! A label, recorded in the first pass; the second only reads them.
    subroutine add_label(name, num, title, kind)
        character(len=*), intent(in) :: name, num, title
        integer, intent(in) :: kind
        type(label_t), allocatable :: grown(:)
        if (.not. FIRST_PASS) return
        if (find_label(name) > 0) then
            write (error_unit, "(a)") "fplotlib: typeset: warning: duplicate label "//name
            return
        end if
        if (.not. allocated(LABS)) allocate (LABS(64))
        if (NLAB == size(LABS)) then
            allocate (grown(2*size(LABS)))
            grown(1:NLAB) = LABS(1:NLAB)
            call move_alloc(grown, LABS)
        end if
        NLAB = NLAB + 1
        LABS(NLAB)%name = name
        LABS(NLAB)%num = num
        LABS(NLAB)%title = title
        LABS(NLAB)%kind = kind
    end subroutine add_label

    integer function find_label(name)
        character(len=*), intent(in) :: name
        integer :: k
        find_label = 0
        do k = 1, NLAB
            if (LABS(k)%name == name) then
                find_label = k
                return
            end if
        end do
    end function find_label

    ! What a role writes, as Sphinx resolves it: {eq} a display's number
    ! in parentheses; {numref} "Section n" for a heading and "(n)" for a
    ! display; {ref} a heading's title. A role may give its own text,
    ! "text <target>", in which {numref} replaces %s and {number} with the
    ! number and {name} with the title. A reference that cannot be resolved
    ! is ??, and a warning, as in LaTeX.
    function reference(role, arg) result(s)
        character(len=*), intent(in) :: role, arg
        character(len=:), allocatable :: s, target, title
        integer :: r, a
        logical :: explicit

        target = trim(adjustl(arg))
        title = ""
        explicit = .false.
        a = index(target, "<", back=.true.)
        if (a > 1 .and. target(len(target):) == ">") then
            title = trim(target(1:a - 1))
            if (len(title) > 0) then
                explicit = .true.
                target = trim(adjustl(target(a + 1:len(target) - 1)))
            end if
        end if
        s = "??"
        r = find_label(target)
        if (r > 0) then
            select case (role)
            case ("eq")
                if (LABS(r)%kind == LAB_EQUATION .and. len(LABS(r)%num) > 0) &
                    s = "("//LABS(r)%num//")"
            case ("ref")
                if (explicit) then
                    s = title
                else if (len(LABS(r)%title) > 0) then
                    s = LABS(r)%title
                end if
            case ("numref")
                if (len(LABS(r)%num) > 0) then
                    if (.not. explicit) then
                        title = "Section %s"
                        if (LABS(r)%kind == LAB_EQUATION) title = "(%s)"
                    end if
                    s = replace(replace(replace(title, "%s", LABS(r)%num), "{number}", &
                                        LABS(r)%num), "{name}", LABS(r)%title)
                end if
            end select
        else if (explicit .and. role == "ref") then
            s = title
        end if
        if (r == 0 .or. s == "??") &
            call warn("unresolved reference {"//role//"}`"//trim(adjustl(arg))//"`")
    end function reference

    ! s with every occurrence of a replaced by b.
    function replace(s, a, b) result(t)
        character(len=*), intent(in) :: s, a, b
        character(len=:), allocatable :: t
        integer :: i, k
        t = ""
        i = 1
        do
            k = index(s(i:), a)
            if (k == 0) exit
            t = t//s(i:i + k - 2)//b
            i = i + k - 1 + len(a)
        end do
        t = t//s(i:)
    end function replace

    ! A warning about the document, as LaTeX gives one: written to the
    ! error unit in the pass that sets the pages, the document set anyway.
    subroutine warn(message)
        character(len=*), intent(in) :: message
        if (FIRST_PASS) return
        write (error_unit, "(a)") "fplotlib: typeset: warning: "//message
    end subroutine warn

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

    ! A MyST target line: (name)=
    logical function is_target(t, name)
        character(len=*), intent(in) :: t
        character(len=:), allocatable, intent(out) :: name
        integer :: k
        is_target = .false.
        name = ""
        if (len(t) < 4) return
        if (t(1:1) /= "(" .or. t(len(t) - 1:len(t)) /= ")=") return
        name = t(2:len(t) - 2)
        if (len(name) == 0) return
        do k = 1, len(name)
            if (name(k:k) == " " .or. name(k:k) == "(" .or. name(k:k) == ")") then
                name = ""
                return
            end if
        end do
        is_target = .true.
    end function is_target

    logical function is_fence(t)
        character(len=*), intent(in) :: t
        is_fence = starts(t, "```") .or. starts(t, "~~~")
    end function is_fence

    logical function div_opens(t)
        character(len=*), intent(in) :: t
        div_opens = .false.
        if (len(t) <= 3) return
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

    ! Tabs, to the next tab stop of four columns, as CommonMark has them.
    subroutine detab(s)
        character(len=:), allocatable, intent(inout) :: s
        character(len=:), allocatable :: t
        integer :: k, col, c
        if (index(s, achar(9)) == 0) return
        t = ""
        col = 0
        do k = 1, len(s)
            if (s(k:k) == achar(9)) then
                t = t//repeat(" ", 4 - mod(col, 4))
                col = col + 4 - mod(col, 4)
            else
                t = t//s(k:k)
                ! A column is a character, not a UTF-8 continuation byte.
                c = iachar(s(k:k))
                if (c < 128 .or. c >= 192) col = col + 1
            end if
        end do
        s = t
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

    pure logical function starts(s, p)
        character(len=*), intent(in) :: s, p
        starts = .false.
        if (len(s) < len(p)) return
        starts = s(1:len(p)) == p
    end function starts

    ! A heading's text without emphasis marks.
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

    ! A number, for keys that take one; ok false, and a warning, when v
    ! is not one.
    real(dp) function number(v, ok)
        character(len=*), intent(in) :: v
        logical, intent(out) :: ok
        integer :: ios
        number = 0.0_dp
        read (v, *, iostat=ios) number
        ok = ios == 0
        if (.not. ok) call warn("cannot read the number '"//trim(v)//"'")
    end function number

    ! A length in points (1/72 in): a number with pt or bp, pc, in, cm,
    ! mm, em or ex (an em being size), a bare number in points. Nothing is
    ! 0; anything else is 0 too, with ok false and a warning.
    real(dp) function length(v, size, ok)
        character(len=*), intent(in) :: v
        real(dp), intent(in) :: size
        logical, intent(out), optional :: ok
        character(len=:), allocatable :: t, u
        integer :: k, ios
        real(dp) :: x
        logical :: good
        t = trim(adjustl(v))
        length = 0.0_dp
        good = .false.
        if (present(ok)) ok = .false.
        if (len(t) == 0) return
        k = len(t)
        do while (k > 0)
            if (index("0123456789.-+", t(k:k)) > 0) exit
            k = k - 1
        end do
        if (k > 0) then
            read (t(1:k), *, iostat=ios) x
            if (ios == 0) then
                u = trim(lower(adjustl(t(k + 1:))))
                good = .true.
                select case (u)
                case ("", "pt", "bp")
                    length = x
                case ("pc")
                    length = 12.0_dp*x
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
                    good = .false.
                end select
            end if
        end if
        if (.not. good) then
            length = 0.0_dp
            call warn("cannot read the length '"//t//"'")
        end if
        if (present(ok)) ok = good
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
