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
    use fplotlib_render, only: paint_t, clip_t
    use fplotlib_scene, only: frame_t, recording_renderer_t
    use fplotlib_typeset
    use fplotlib_io, only: read_bytes, join_path
    use fplotlib_status, only: status_t
    use, intrinsic :: iso_fortran_env, only: error_unit
    implicit none
    private

    public :: md_typeset, md_typeset_files, md_typeset_box, md_document_t, md_ctx_t, &
              md_directive_t, md_heading_t, md_figure_t
    public :: md_directive_cb, md_body_cb, md_heading_cb
    public :: md_blocks, md_inline, md_option, md_meta
    public :: md_length, md_color, md_align, md_noindent, md_base_size

    character, parameter :: BS = achar(92), NL = achar(10)
    integer, parameter :: LINK_COL = 1728436, CODE_COL = 5263440
    integer, parameter :: LAB_SECTION = 1, LAB_EQUATION = 2, LAB_OTHER = 3, &
                          LAB_FIGURE = 4, LAB_TABLE = 5

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
    ! (md_blocks, md_inline).
    type :: md_ctx_t
        real(dp) :: left = 0.0_dp, right = 0.0_dp
        integer :: align = ALIGN_JUSTIFY
        real(dp) :: size = 10.0_dp
        integer :: color = 0
        logical :: bold = .false., italic = .false.
        logical :: indent = .true.
        integer, private :: depth = 0
        integer, private :: ilev = 0, elev = 0
        type(ts_glue_t), private :: parskip = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
    end type md_ctx_t

    ! A MyST directive, as on_directive is given it.
    type :: md_directive_t
        character(len=:), allocatable :: name, arg, opts, body
    end type md_directive_t

    ! A heading, as on_heading is given it.
    type :: md_heading_t
        integer :: level = 0
        character(len=:), allocatable :: text, num
    end type md_heading_t

    ! A named vector figure passed to md_typeset / typeset.
    type :: md_figure_t
        character(len=:), allocatable :: name
        type(frame_t) :: frame
    end type md_figure_t

    type :: meta_t
        character(len=:), allocatable :: key, val
    end type meta_t

    type :: label_t
        character(len=:), allocatable :: name, num, title
        integer :: kind = LAB_SECTION
    end type label_t

    type :: pending_t
        character(len=:), allocatable :: s
        real(dp) :: left = 0.0_dp
    end type pending_t

    ! A document being typeset: its engine (public so templates call
    ! ts_*(doc%engine, ...)) and all Markdown layout state (private).
    type :: md_document_t
        private
        type(typeset_context_t), public :: engine
        procedure(md_directive_cb), pointer, nopass :: CB_DIR => null()
        procedure(md_body_cb), pointer, nopass :: CB_BODY => null()
        procedure(md_heading_cb), pointer, nopass :: CB_HEAD => null()
        real(dp) :: BASE = 10.0_dp, LEAD = 1.2_dp
        real(dp) :: PARINDENT = 15.0_dp
        type(ts_glue_t) :: PARSKIP_G = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        integer :: DOC_ALIGN = ALIGN_JUSTIFY
        logical :: NUMBER_SECTIONS = .false., CHAPTERS = .false., NUMBER_EQS = .false.
        character(len=:), allocatable :: TITLE, SUBTITLE, AUTHOR, DATE, ABSTRACT
        integer :: TEXT_COL = 0, PAGE_COL = 16777215
        integer :: NMETA = 0
        type(meta_t), allocatable :: META(:)
        integer :: SEC(4) = 0, CHAPTER = 0, EQNO = 0, FIGNO = 0, TABNO = 0
        integer :: NLAB = 0
        type(label_t), allocatable :: LABS(:)
        integer :: NFIG = 0
        type(frame_t) :: FIG_SCENE
        integer, allocatable :: FIG_HANDLES(:)
        type(line_t), allocatable :: FIG_NAMES(:)
        logical :: FIRST_PASS = .false.
        character(len=:), allocatable :: TARGETS
        logical :: AFTER_HEADING = .false.
        logical :: NOINDENT = .false.
        integer :: NPEND = 0
        type(pending_t), allocatable :: PENDING(:)
        integer :: REF_DEPTH = 0
        character(len=:), allocatable :: BASE_DIR
    end type md_document_t

    ! Template callbacks given to md_typeset. Callbacks receive the
    ! document first (doc) and may set a nested document of their own.
    abstract interface
        subroutine md_directive_cb(doc, directive, ctx, handled)
            import :: md_document_t, md_directive_t, md_ctx_t
            type(md_document_t), intent(inout) :: doc
            type(md_directive_t), intent(in) :: directive
            type(md_ctx_t), intent(in) :: ctx
            logical, intent(inout) :: handled
        end subroutine md_directive_cb

        subroutine md_body_cb(doc, after, ctx)
            import :: md_document_t, md_ctx_t
            type(md_document_t), intent(inout) :: doc
            logical, intent(in) :: after
            type(md_ctx_t), intent(in) :: ctx
        end subroutine md_body_cb

        subroutine md_heading_cb(doc, heading, ctx, handled)
            import :: md_document_t, md_heading_t, md_ctx_t
            type(md_document_t), intent(inout) :: doc
            type(md_heading_t), intent(in) :: heading
            type(md_ctx_t), intent(in) :: ctx
            logical, intent(inout) :: handled
        end subroutine md_heading_cb
    end interface

contains

    ! ------------------------------------------------------------------
    ! The document.
    ! ------------------------------------------------------------------

    ! Set text, a MyST Markdown document, into doc%engine's pages.
    ! The document is set twice (see FIRST_PASS), so the callbacks are
    ! called twice, and only the second pass's pages are kept. A callback
    ! may set a nested md_document_t without affecting doc.
    recursive subroutine md_typeset(doc, text, on_directive, on_body, on_heading, base_dir, figures)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: text
        procedure(md_directive_cb), optional :: on_directive
        procedure(md_body_cb), optional :: on_body
        procedure(md_heading_cb), optional :: on_heading
        character(len=*), intent(in), optional :: base_dir
        type(md_figure_t), intent(in), optional :: figures(:)
        character(len=:), allocatable :: texts(:), dirs(:), bdir

        allocate (character(len=len(text) + 1) :: texts(1))
        texts(1) = text//NL
        if (present(base_dir)) then
            bdir = trim(base_dir)
        else
            bdir = ""
        end if
        allocate (character(len=max(1, len(bdir))) :: dirs(1))
        if (len(bdir) > 0) then
            dirs(1) = bdir
        else
            dirs(1) = " "
        end if
        call md_typeset_files(doc, texts, dirs, on_directive=on_directive, &
                              on_body=on_body, on_heading=on_heading, figures=figures)
    end subroutine md_typeset

    ! Set one or more MyST Markdown sources as a single document. Front
    ! matter is read from the first source; labels and cross-references
    ! resolve across all sources; each source keeps its own base directory
    ! in dirs for relative paths (such as :::{literalinclude}).
    recursive subroutine md_typeset_files(doc, texts, dirs, on_directive, on_body, on_heading, &
                                          figures)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: texts(:), dirs(:)
        procedure(md_directive_cb), optional :: on_directive
        procedure(md_body_cb), optional :: on_body
        procedure(md_heading_cb), optional :: on_heading
        type(md_figure_t), intent(in), optional :: figures(:)
        type(line_t), allocatable :: lines(:)
        type(md_ctx_t) :: ctx
        integer :: nfiles, f, n, first, pass, k

        doc%CB_DIR => null()
        doc%CB_BODY => null()
        doc%CB_HEAD => null()
        if (present(on_directive)) doc%CB_DIR => on_directive
        if (present(on_body)) doc%CB_BODY => on_body
        if (present(on_heading)) doc%CB_HEAD => on_heading

        doc%NFIG = 0
        if (present(figures)) then
            if (size(figures) > 0) then
                call doc%FIG_SCENE%init(0.0_dp, 0.0_dp)
                if (allocated(doc%FIG_NAMES)) deallocate (doc%FIG_NAMES)
                if (allocated(doc%FIG_HANDLES)) deallocate (doc%FIG_HANDLES)
                allocate (doc%FIG_NAMES(size(figures)), doc%FIG_HANDLES(size(figures)))
                do k = 1, size(figures)
                    if (allocated(figures(k)%name)) then
                        if (len_trim(figures(k)%name) > 0) then
                            doc%NFIG = doc%NFIG + 1
                            doc%FIG_NAMES(doc%NFIG)%s = trim(adjustl(figures(k)%name))
                            call doc%FIG_SCENE%import_frame(figures(k)%frame, &
                                                            doc%FIG_HANDLES(doc%NFIG))
                        end if
                    end if
                end do
            end if
        end if

        nfiles = size(texts)
        doc%NLAB = 0
        do pass = 1, 2
            doc%FIRST_PASS = pass == 1
            call ts_reset(doc%engine)
            call defaults(doc)
            first = 1
            n = 0
            if (nfiles >= 1) then
                if (size(dirs) >= 1) doc%BASE_DIR = trim(dirs(1))
                call split_lines(texts(1), lines, n)
                call front_matter(doc, lines, n, first)
            else
                doc%PARINDENT = 1.5_dp*doc%BASE
            end if
            call ts_set_font(doc%engine, doc%BASE, doc%LEAD*doc%BASE)
            call ts_set_parskip(doc%engine, doc%PARSKIP_G)
            call ts_set_colors(doc%engine, doc%TEXT_COL, doc%PAGE_COL)
            doc%SEC = 0
            doc%CHAPTER = 0
            doc%EQNO = 0
            doc%FIGNO = 0
            doc%TABNO = 0
            doc%TARGETS = ""
            doc%AFTER_HEADING = .false.
            ctx = md_ctx_t()
            ctx%size = doc%BASE
            ctx%color = doc%TEXT_COL
            ctx%align = doc%DOC_ALIGN
            ctx%parskip = doc%PARSKIP_G
            doc%REF_DEPTH = 0
            call title_block(doc, ctx)
            if (associated(doc%CB_BODY)) call doc%CB_BODY(doc, .false., ctx)
            do f = 1, nfiles
                if (f <= size(dirs)) then
                    doc%BASE_DIR = trim(dirs(f))
                else
                    doc%BASE_DIR = ""
                end if
                if (f == 1) then
                    if (first <= n) call blocks(doc, lines(first:n), n - first + 1, ctx)
                else
                    call split_lines(texts(f), lines, n)
                    if (n > 0) call blocks(doc, lines(1:n), n, ctx)
                end if
            end do
            call place_targets(doc)
            if (associated(doc%CB_BODY)) call doc%CB_BODY(doc, .true., ctx)
        end do
        doc%FIRST_PASS = .false.
        doc%BASE_DIR = ""
        call ts_paginate(doc%engine)

        doc%CB_DIR => null()
        doc%CB_BODY => null()
        doc%CB_HEAD => null()
    end subroutine md_typeset_files

    ! Typeset a MyST Markdown snippet into a self-contained frame_t of exact
    ! width `width` (in points) and auto-measured height, with optional rounded
    ! background and border.
    recursive subroutine md_typeset_box(text, width, frame, fontsize, align, color, &
                                        bg_color, border_color, border_width, alpha, &
                                        pad, radius)
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width
        type(frame_t), intent(out) :: frame
        real(dp), intent(in), optional :: fontsize, border_width, alpha, pad, radius
        character(len=*), intent(in), optional :: align, color, bg_color, border_color
        type(md_document_t) :: doc
        type(line_t), allocatable :: lines(:)
        type(md_ctx_t) :: ctx
        type(recording_renderer_t) :: rec
        type(paint_t) :: bg_paint
        type(clip_t) :: no_clip
        real(dp) :: fsz, bw, a, pd, rad, inner_w, content_h, top_gap, box_h, w_use
        integer :: n, pass, al, tcol, bgcol, bdcol
        logical :: has_bg, has_bd

        w_use = max(1.0_dp, width)
        fsz = 10.0_dp
        if (present(fontsize)) then
            if (fontsize > 0.0_dp) fsz = fontsize
        end if
        al = ALIGN_JUSTIFY
        if (present(align)) al = align_of(lower(trim(align)), ALIGN_JUSTIFY)
        tcol = 0
        if (present(color)) then
            if (len_trim(color) > 0) tcol = md_color(color, 0)
        end if
        has_bg = .false.
        bgcol = 16777215
        if (present(bg_color)) then
            if (len_trim(bg_color) > 0 .and. lower(trim(bg_color)) /= "none") then
                bgcol = md_color(bg_color, -1)
                if (bgcol >= 0) then
                    has_bg = .true.
                else
                    bgcol = 16777215
                end if
            end if
        end if
        has_bd = .false.
        bdcol = 0
        if (present(border_color)) then
            if (len_trim(border_color) > 0 .and. lower(trim(border_color)) /= "none") then
                bdcol = md_color(border_color, -1)
                if (bdcol >= 0) then
                    has_bd = .true.
                else
                    bdcol = 0
                end if
            end if
        end if
        bw = 0.8_dp
        if (present(border_width)) bw = max(0.0_dp, border_width)
        if (bw <= 0.0_dp) has_bd = .false.
        a = 1.0_dp
        if (present(alpha)) a = min(1.0_dp, max(0.0_dp, alpha))
        if (present(pad)) then
            pd = max(0.0_dp, pad)
        else if (has_bg .or. has_bd) then
            pd = 6.0_dp
        else
            pd = 0.0_dp
        end if
        pd = min(pd, max(0.0_dp, 0.5_dp*(w_use - 1.0_dp)))
        rad = 0.0_dp
        if (present(radius)) rad = max(0.0_dp, radius)

        inner_w = max(1.0_dp, w_use - 2.0_dp*pd)
        call split_lines(text, lines, n)
        doc%NLAB = 0
        do pass = 1, 2
            doc%FIRST_PASS = pass == 1
            call ts_reset(doc%engine)
            call defaults(doc)
            doc%BASE = fsz
            doc%LEAD = 1.2_dp
            doc%PARINDENT = 0.0_dp
            doc%PARSKIP_G = ts_glue_t(0.45_dp*fsz, 0.1_dp*fsz, 0.0_dp, 0, 0)
            doc%DOC_ALIGN = al
            doc%TEXT_COL = tcol
            doc%PAGE_COL = bgcol
            call ts_set_page(doc%engine, inner_w + 2.0_dp*pd, 100000.0_dp, &
                             pd, pd, 0.0_dp, 0.0_dp, &
                             numbers=.false., headings_=.false., flush=.false.)
            call ts_set_font(doc%engine, doc%BASE, doc%LEAD*doc%BASE)
            call ts_set_parskip(doc%engine, doc%PARSKIP_G)
            call ts_set_colors(doc%engine, doc%TEXT_COL, doc%PAGE_COL)
            doc%SEC = 0
            doc%CHAPTER = 0
            doc%EQNO = 0
            doc%FIGNO = 0
            doc%TABNO = 0
            doc%TARGETS = ""
            doc%AFTER_HEADING = .false.
            ctx = md_ctx_t()
            ctx%size = doc%BASE
            ctx%color = doc%TEXT_COL
            ctx%align = doc%DOC_ALIGN
            ctx%parskip = doc%PARSKIP_G
            ctx%indent = .false.
            doc%REF_DEPTH = 0
            if (n > 0) call blocks(doc, lines(1:n), n, ctx)
            call place_targets(doc)
        end do
        doc%FIRST_PASS = .false.
        call ts_paginate(doc%engine)

        content_h = ts_box_height(doc%engine, 1, top_gap)
        box_h = max(1.0_dp, content_h + 2.0_dp*pd)

        call rec%open_canvas(w_use, box_h)
        if (has_bg .or. has_bd) then
            if (has_bg) then
                bg_paint%filled = .true.
                bg_paint%fill_rgb = [bgcol/65536, mod(bgcol/256, 256), mod(bgcol, 256)]
                bg_paint%fill_alpha = a
            end if
            if (has_bd) then
                bg_paint%stroked = .true.
                bg_paint%stroke_rgb = [bdcol/65536, mod(bdcol/256, 256), mod(bdcol, 256)]
                bg_paint%stroke_alpha = a
                bg_paint%line_width = bw
            end if
            call rec%draw_rect(0.0_dp, 0.0_dp, w_use, box_h, bg_paint, radius=rad)
        end if
        if (ts_page_count(doc%engine) >= 1) then
            call rec%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, pd - top_gap], no_clip)
            call ts_page_draw(doc%engine, rec, 1)
            call rec%end_frame()
        end if
        call rec%close_canvas()
        call rec%take(frame)
    end subroutine md_typeset_box

    recursive subroutine defaults(doc)
        type(md_document_t), intent(inout) :: doc
        doc%BASE = 10.0_dp
        doc%LEAD = 1.2_dp
        doc%PARINDENT = -1.0_dp
        doc%PARSKIP_G = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        doc%DOC_ALIGN = ALIGN_JUSTIFY
        doc%NUMBER_SECTIONS = .false.
        doc%NUMBER_EQS = .false.
        doc%CHAPTERS = .false.
        doc%TITLE = ""
        doc%SUBTITLE = ""
        doc%AUTHOR = ""
        doc%DATE = ""
        doc%ABSTRACT = ""
        doc%TEXT_COL = 0
        doc%PAGE_COL = 16777215
        doc%NMETA = 0
        doc%NOINDENT = .false.
        doc%NPEND = 0
        doc%BASE_DIR = ""
        call ts_set_page(doc%engine, 595.2756_dp, 841.8898_dp, 72.0_dp, 72.0_dp, 72.0_dp, 72.0_dp)
    end subroutine defaults

    ! The front matter: "key: value" lines between a first line of --- and
    ! the next line of --- (or ...). Without that closing line there is no
    ! front matter, and the --- is a rule. The type size is read first, as
    ! the em and ex of the other values are its. A value that cannot be
    ! read is warned of, and the setting keeps its default.
    recursive subroutine front_matter(doc, lines, n, first)
        type(md_document_t), intent(inout) :: doc
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
        if (n >= 3) then
            if (trim(lines(1)%s) == "---" .and. len_trim(lines(2)%s) > 0) then
                if (lines(2)%s(1:1) == "#" .or. &
                    (lines(2)%s(1:1) /= " " .and. index(lines(2)%s, ":") > 1)) then
                    do i = 2, n
                        if (trim(lines(i)%s) == "---" .or. trim(lines(i)%s) == "...") then
                            last = i
                            exit
                        end if
                    end do
                end if
            end if
        end if
        i = 2
        do while (i <= last - 1)
            if (.not. entry(lines, i, last, key, val, c)) then
                i = i + 1
                cycle
            end if
            i = c
            if (key /= "fontsize") cycle
            x = length(doc, val, doc%BASE, ok)
            if (ok .and. x > 0.0_dp) then
                doc%BASE = x
            else if (ok) then
                call warn(doc, "fontsize must be positive: '"//val//"'")
            end if
        end do
        i = 2
        do while (i <= last - 1)
            if (.not. entry(lines, i, last, key, val, c)) then
                i = i + 1
                cycle
            end if
            i = c
            call add_meta(doc, key, val)
            select case (key)
            case ("title")
                doc%TITLE = val
            case ("subtitle")
                doc%SUBTITLE = val
            case ("author", "authors")
                if (len(doc%AUTHOR) > 0) then
                    doc%AUTHOR = doc%AUTHOR//NL//val
                else
                    doc%AUTHOR = val
                end if
            case ("date")
                doc%DATE = val
            case ("abstract")
                doc%ABSTRACT = val
            case ("linestretch", "leading")
                x = number(doc, val, ok)
                if (ok .and. x > 0.0_dp) then
                    doc%LEAD = 1.2_dp*x
                else if (ok) then
                    call warn(doc, "linestretch must be positive: '"//val//"'")
                end if
            case ("paper", "papersize")
                call paper_size(doc, lower(val), pw, ph)
            case ("margin")
                call set_nonneg_length(doc, val, m, "margin")
            case ("margin-left")
                call set_nonneg_length(doc, val, ml, "margin-left")
            case ("margin-right")
                call set_nonneg_length(doc, val, mr, "margin-right")
            case ("margin-top")
                call set_nonneg_length(doc, val, mt, "margin-top")
            case ("margin-bottom")
                call set_nonneg_length(doc, val, mb, "margin-bottom")
            case ("indent", "parindent")
                if (lower(val) == "false" .or. lower(val) == "no") then
                    doc%PARINDENT = 0.0_dp
                else if (lower(val) /= "true" .and. lower(val) /= "yes") then
                    call set_length(doc, val, doc%PARINDENT)
                end if
            case ("parskip")
                x = length(doc, val, doc%BASE, ok)
                if (ok .and. x >= 0.0_dp) then
                    doc%PARSKIP_G = ts_glue_t(x, 0.2_dp*x, 0.0_dp, 0, 0)
                    if (doc%PARINDENT < 0.0_dp) doc%PARINDENT = 0.0_dp
                else if (ok) then
                    call warn(doc, "parskip must not be negative: '"//val//"'")
                end if
            case ("align")
                c = align_of(lower(val), -1)
                if (c < 0) then
                    call warn(doc, "cannot read the alignment '"//val//"'")
                else
                    doc%DOC_ALIGN = c
                end if
            case ("numbersections", "number-sections")
                doc%NUMBER_SECTIONS = flag(doc, val)
            case ("numberequations", "number-equations")
                doc%NUMBER_EQS = flag(doc, val)
            case ("pagenumbers", "page-numbers")
                numbers = flag(doc, val)
            case ("runningheads", "running-heads")
                heads = flag(doc, val)
            case ("flushbottom", "flush-bottom")
                flushb = flag(doc, val)
            case ("chapters")
                doc%CHAPTERS = flag(doc, val)
            case ("color", "fontcolor")
                call set_color(doc, val, doc%TEXT_COL)
            case ("pagecolor", "background")
                call set_color(doc, val, doc%PAGE_COL)
            end select
        end do
        if (last > 0) first = last + 1
        if (doc%PARINDENT < 0.0_dp) doc%PARINDENT = 1.5_dp*doc%BASE
        ! LaTeX's geometry is set here by margins; without them, one inch.
        if (m < 0.0_dp) m = 72.0_dp
        if (ml < 0.0_dp) ml = m
        if (mr < 0.0_dp) mr = m
        if (mt < 0.0_dp) mt = m
        if (mb < 0.0_dp) mb = m
        if (ml + mr >= pw .or. mt + mb >= ph) then
            call warn(doc, "margins leave no room on the page; keeping default margins")
            ml = min(72.0_dp, 0.1_dp*pw)
            mr = ml
            mt = min(72.0_dp, 0.1_dp*ph)
            mb = mt
        end if
        call ts_set_page(doc%engine, pw, ph, ml, mr, mt, mb, numbers, heads, flushb)
    end subroutine front_matter

    ! The key and value of front matter line i, when it is a line that is
    ! not indented and has a colon. The value goes on over the indented
    ! lines after it (or column-1 "- item" lines after an empty value), up
    ! to line last; "- item" lines, or [a, b], are a list, its items one
    ! to a line. next_i is the first line after the entry.
    logical function entry(lines, i, last, key, val, next_i)
        type(line_t), intent(in) :: lines(:)
        integer, intent(in) :: i, last
        character(len=:), allocatable, intent(out) :: key, val
        integer, intent(out) :: next_i
        character(len=:), allocatable :: t, raw
        integer :: c, j, k
        logical :: blk_lit, blk_fold, empty_val, has_more, blank_seen
        entry = .false.
        key = ""
        val = ""
        next_i = i + 1
        if (len(lines(i)%s) == 0) return
        if (lines(i)%s(1:1) == " " .or. lines(i)%s(1:1) == "#") return
        c = index(lines(i)%s, ":")
        if (c == 0) return
        entry = .true.
        key = trim(lower(adjustl(lines(i)%s(1:c - 1))))
        raw = trim(adjustl(strip_yaml_comment(lines(i)%s(c + 1:))))
        blk_lit = raw == "|"
        blk_fold = raw == ">"
        if (blk_lit .or. blk_fold) then
            val = ""
        else
            val = unquote(raw)
        end if
        empty_val = len(val) == 0 .and. .not. blk_lit .and. .not. blk_fold
        if (len(val) >= 2) then
            if (val(1:1) == "[" .and. val(len(val):) == "]") val = flow_list(val(2:len(val) - 1))
        end if
        blank_seen = .false.
        j = i + 1
        do while (j <= last - 1)
            if (len_trim(lines(j)%s) == 0) then
                if (blk_lit .or. blk_fold) then
                    has_more = .false.
                    do k = j + 1, last - 1
                        if (len_trim(lines(k)%s) > 0) then
                            has_more = lines(k)%s(1:1) == " "
                            exit
                        end if
                    end do
                    if (has_more) then
                        blank_seen = .true.
                        j = j + 1
                        cycle
                    end if
                end if
                exit
            end if
            if (lines(j)%s(1:1) == " ") then
                t = trim(adjustl(lines(j)%s))
                if (starts(t, "#") .and. .not. blk_lit .and. .not. blk_fold) then
                    j = j + 1
                    cycle
                end if
                if (starts(t, "- ") .and. .not. blk_lit .and. .not. blk_fold) then
                    if (len(val) > 0) val = val//NL
                    val = val//unquote(trim(adjustl(strip_yaml_comment(t(3:)))))
                else if (blk_lit) then
                    if (len(val) > 0) then
                        if (blank_seen) then
                            val = val//NL//NL
                        else
                            val = val//NL
                        end if
                    end if
                    val = val//t
                else
                    if (len(val) > 0) then
                        if (blank_seen) then
                            val = val//NL//NL
                        else
                            val = val//" "
                        end if
                    end if
                    val = val//t
                end if
                blank_seen = .false.
            else if (empty_val .and. starts(lines(j)%s, "- ")) then
                t = trim(adjustl(strip_yaml_comment(lines(j)%s(3:))))
                if (len(val) > 0) val = val//NL
                val = val//unquote(t)
            else
                exit
            end if
            j = j + 1
        end do
        next_i = j
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
    recursive subroutine add_meta(doc, key, val)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: key, val
        type(meta_t), allocatable :: grown(:)
        if (.not. allocated(doc%META)) allocate (doc%META(16))
        if (doc%NMETA == size(doc%META)) then
            allocate (grown(2*size(doc%META)))
            grown(1:doc%NMETA) = doc%META(1:doc%NMETA)
            call move_alloc(grown, doc%META)
        end if
        doc%NMETA = doc%NMETA + 1
        doc%META(doc%NMETA)%key = key
        doc%META(doc%NMETA)%val = val
    end subroutine add_meta

    recursive subroutine set_length(doc, val, var)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: val
        real(dp), intent(inout) :: var
        real(dp) :: x
        logical :: ok
        x = length(doc, val, doc%BASE, ok)
        if (ok) var = x
    end subroutine set_length

    recursive subroutine set_nonneg_length(doc, val, var, name)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: val, name
        real(dp), intent(inout) :: var
        real(dp) :: x
        logical :: ok
        x = length(doc, val, doc%BASE, ok)
        if (ok .and. x >= 0.0_dp) then
            var = x
        else if (ok) then
            call warn(doc, name//" must not be negative: '"//val//"'")
        end if
    end subroutine set_nonneg_length

    recursive subroutine set_color(doc, val, var)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: val
        integer, intent(inout) :: var
        integer :: c
        c = color_of(val, -1)
        if (c < 0) then
            call warn(doc, "cannot read the colour '"//val//"'")
        else
            var = c
        end if
    end subroutine set_color

    ! A yes or no: true, yes or 1, or false, no or 0.
    recursive logical function flag(doc, val)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: val
        flag = truth(val)
        select case (lower(trim(val)))
        case ("true", "yes", "1", "false", "no", "0")
        case default
            call warn(doc, "cannot read '"//val//"' as true or false")
        end select
    end function flag

    recursive subroutine paper_size(doc, v, w, h)
        type(md_document_t), intent(in) :: doc
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
                a = length(doc, trim(v(1:x - 1)), doc%BASE, oka)
                b = length(doc, trim(v(x + 1:)), doc%BASE, okb)
            end if
            if (oka .and. okb .and. a > 0.0_dp .and. b > 0.0_dp) then
                w = a
                h = b
            else
                call warn(doc, "cannot read the paper '"//v//"'")
            end if
        end select
    end subroutine paper_size

    ! LaTeX's \maketitle and abstract, for the article class.
    recursive subroutine title_block(doc, ctx)
        type(md_document_t), intent(inout) :: doc
        type(md_ctx_t), intent(in) :: ctx
        type(style_t) :: st
        integer :: i, j
        ! The title, with its authors and date; an abstract is set with or
        ! without one.
        if (len(doc%TITLE) > 0) then
            st = base_style(ctx)
            call ts_vkeep(doc%engine, ts_glue_t(2.0_dp*doc%BASE, 0.0_dp, 0.0_dp, 0, 0))
            call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            st%size = 1.728_dp*doc%BASE
            call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                    leading=22.0_dp*doc%BASE/10.0_dp, &
                              skip=.false.)
            call inline(doc, doc%TITLE, st)
            call ts_end_par(doc%engine)
            if (len(doc%SUBTITLE) > 0) then
                st%size = 1.2_dp*doc%BASE
                call ts_vskip(doc%engine, ts_glue_t(0.5_dp*doc%BASE, 0.0_dp, 0.0_dp, 0, 0))
                call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                                  leading=14.0_dp*doc%BASE/10.0_dp, skip=.false.)
                call inline(doc, doc%SUBTITLE, st)
                call ts_end_par(doc%engine)
            end if
            st%size = 1.2_dp*doc%BASE
            if (len(doc%AUTHOR) > 0) then
                call ts_vskip(doc%engine, ts_glue_t(1.5_dp*doc%BASE, 0.0_dp, 0.0_dp, 0, 0))
                i = 1
                do while (i <= len(doc%AUTHOR))
                    j = index(doc%AUTHOR(i:), NL)
                    if (j == 0) then
                        j = len(doc%AUTHOR) + 1
                    else
                        j = i + j - 1
                    end if
                    call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                                      leading=14.0_dp*doc%BASE/10.0_dp, skip=.false.)
                    call inline(doc, doc%AUTHOR(i:j - 1), st)
                    call ts_end_par(doc%engine)
                    i = j + 1
                end do
            end if
            if (len(doc%DATE) > 0) then
                call ts_vskip(doc%engine, ts_glue_t(doc%BASE, 0.0_dp, 0.0_dp, 0, 0))
                call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                                  leading=14.0_dp*doc%BASE/10.0_dp, skip=.false.)
                call inline(doc, doc%DATE, st)
                call ts_end_par(doc%engine)
            end if
            call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            call ts_vskip(doc%engine, ts_glue_t(1.5_dp*doc%BASE, 0.0_dp, 0.0_dp, 0, 0))
        end if
        if (len(doc%ABSTRACT) > 0) then
            ! \small, a centred bold heading, and a quotation.
            st = base_style(ctx)
            st%size = 0.9_dp*doc%BASE
            st%bold = .true.
            call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
            call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=11.0_dp*doc%BASE/10.0_dp, skip=.false.)
            call inline(doc, "Abstract", st)
            call ts_end_par(doc%engine)
            st%bold = .false.
            call ts_vskip(doc%engine, ts_glue_t(-0.5_dp*st%size + 0.5_dp*doc%BASE, 0.0_dp, &
                    0.0_dp, 0, 0))
            call ts_begin_par(doc%engine, ALIGN_JUSTIFY, 1.5_dp*st%size, left=2.5_dp*doc%BASE, &
                              right=2.5_dp*doc%BASE, size=st%size, leading=11.0_dp*doc%BASE/10.0_dp)
            call inline(doc, doc%ABSTRACT, st)
            call ts_end_par(doc%engine)
            call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        end if
        doc%NOINDENT = .false.
    end subroutine title_block

    ! ------------------------------------------------------------------
    ! Blocks.
    ! ------------------------------------------------------------------

    recursive subroutine blocks(doc, L, n, ctx)
        type(md_document_t), intent(inout) :: doc
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        type(md_ctx_t), intent(in) :: ctx
        integer :: i, j, k, lev, depth, flen, tot, pos
        character(len=:), allocatable :: s, t, para, lab, fig_cap, fig_name
        character :: fch
        logical :: blank_before, in_disp

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
                if (.not. allocated(doc%TARGETS)) doc%TARGETS = ""
                doc%TARGETS = doc%TARGETS//" "//lab
                i = i + 1
                cycle
            end if
            if (is_heading(t, lev)) then
                call heading(doc, heading_text(t, lev), lev, ctx)
                i = i + 1
            else if (fence_open(t, fch, flen)) then
                call other_block(doc)
                j = i + 1
                do while (j <= n)
                    if (fence_close(trim(adjustl(L(j)%s)), fch, flen)) exit
                    j = j + 1
                end do
                call code_block(doc, L(i + 1:min(j - 1, n)), max(0, min(j - 1, n) - i), ctx)
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
                call set_div(doc, t, L, i, j, ctx)
                i = j + 1
            else if (is_figure_line(t, fig_cap, fig_name)) then
                call set_figure(doc, fig_name, fig_cap, "", "", "", ctx)
                i = i + 1
            else if (i < n .and. is_table_start(s, L(min(i + 1, n))%s)) then
                j = i + 2
                do while (j <= n)
                    if (len_trim(L(j)%s) == 0) exit
                    if (index(L(j)%s, "|") == 0) exit
                    j = j + 1
                end do
                call set_table(doc, L(i:j - 1), j - i, "", "", "", ctx)
                i = j
            else if (t(1:1) == ">") then
                j = i + 1
                do while (j <= n)
                    if (len_trim(L(j)%s) == 0) exit
                    if (.not. starts(trim(adjustl(L(j)%s)), ">")) then
                        if (interrupts(L(j)%s)) exit
                    end if
                    j = j + 1
                end do
                call other_block(doc)
                call quote_block(doc, L(i:j - 1), j - i, ctx)
                i = j
            else if (is_item(s, k, lev)) then
                call other_block(doc)
                call list_block(doc, L, n, i, ctx, blank_before)
            else if (is_rule(t)) then
                call other_block(doc)
                call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, left=ctx%left, right=ctx%right)
                call ts_end_par(doc%engine)
                call ts_rule(doc%engine, 0.5_dp*(ts_hsize(doc%engine) - ctx%left - ctx%right), &
                        0.5_dp, ctx%color)
                call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
                i = i + 1
            else
                in_disp = .false.
                j = i
                do while (j <= n)
                    t = trim(adjustl(L(j)%s))
                    if (len(t) == 0) exit
                    ! Inside a display, a line is mathematics, whatever it
                    ! starts with, provided a closing $$ follows in the block.
                    if (j > i) then
                        if (.not. in_disp) then
                            if (interrupts(L(j)%s)) exit
                            if (j < n) then
                                if (is_table_start(L(j)%s, L(j + 1)%s)) exit
                            end if
                            if (j == i + 1 .and. (is_underline(t, "=") .or. &
                                                  is_underline(t, "-"))) exit
                        else if (.not. has_display_close(L, j, n)) then
                            if (interrupts(L(j)%s)) exit
                            if (j < n) then
                                if (is_table_start(L(j)%s, L(j + 1)%s)) exit
                            end if
                            if (j == i + 1 .and. (is_underline(t, "=") .or. &
                                                  is_underline(t, "-"))) exit
                        end if
                    end if
                    call scan_display(L(j)%s, in_disp)
                    j = j + 1
                end do
                tot = max(0, j - i - 1)
                do k = i, j - 1
                    tot = tot + len(L(k)%s)
                end do
                if (allocated(para)) deallocate (para)
                allocate (character(len=tot) :: para)
                pos = 1
                do k = i, j - 1
                    if (k > i) then
                        para(pos:pos) = NL
                        pos = pos + 1
                    end if
                    if (len(L(k)%s) > 0) then
                        para(pos:pos + len(L(k)%s) - 1) = L(k)%s
                        pos = pos + len(L(k)%s)
                    end if
                end do
                if (j == i + 1 .and. j <= n) then
                    t = trim(adjustl(L(j)%s))
                    if (len(t) > 0 .and. (is_underline(t, "=") .or. is_underline(t, "-"))) then
                        if (is_underline(t, "=")) then
                            call heading(doc, trim(adjustl(para)), 1, ctx)
                        else
                            call heading(doc, trim(adjustl(para)), 2, ctx)
                        end if
                        i = j + 1
                        blank_before = .false.
                        cycle
                    end if
                end if
                call other_block(doc)
                call paragraph(doc, para, ctx)
                i = j
            end if
            blank_before = .false.
        end do
    end subroutine blocks

    ! A block that is not a heading: the targets before it label it, and a
    ! heading after it is not one straight after a heading.
    recursive subroutine other_block(doc)
        type(md_document_t), intent(inout) :: doc
        call place_targets(doc)
        doc%AFTER_HEADING = .false.
    end subroutine other_block

    ! The targets waiting for a block label it: a heading with its number
    ! and title, anything else with neither, for a reference that gives
    ! its own text.
    recursive subroutine place_targets(doc, num, title, kind)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in), optional :: num, title
        integer, intent(in), optional :: kind
        character(len=:), allocatable :: name
        integer :: k, knd
        if (.not. allocated(doc%TARGETS)) return
        do while (len_trim(doc%TARGETS) > 0)
            doc%TARGETS = adjustl(doc%TARGETS)
            k = index(doc%TARGETS, " ")
            if (k == 0) k = len(doc%TARGETS) + 1
            name = doc%TARGETS(1:k - 1)
            doc%TARGETS = doc%TARGETS(k:)
            if (present(num)) then
                knd = LAB_SECTION
                if (present(kind)) knd = kind
                call add_label(doc, name, num, title, knd)
            else
                call add_label(doc, name, "", "", LAB_OTHER)
            end if
        end do
        doc%TARGETS = ""
    end subroutine place_targets

    ! Whether a line starts a block that ends a paragraph before it.
    logical function interrupts(s)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t, lab, fig_cap, fig_name
        integer :: k, lev, flen
        character :: fch
        t = trim(adjustl(s))
        interrupts = .false.
        if (len(t) == 0) return
        if (is_heading(t, lev) .or. fence_open(t, fch, flen) .or. &
            (starts(t, ":::") .and. div_opens(t)) .or. &
            is_figure_line(t, fig_cap, fig_name) .or. &
            t(1:1) == ">" .or. is_rule(t) .or. is_target(t, lab)) then
            interrupts = .true.
        else if (is_item(s, k, lev)) then
            interrupts = lev == 0 .or. k == 1
        end if
    end function interrupts

    ! Update in_disp after scanning one line, respecting escapes, code
    ! spans, and inline $...$ spans so $a$$b$ and \$$x$$ do not open one.
    subroutine scan_display(text, in_disp)
        character(len=*), intent(in) :: text
        logical, intent(inout) :: in_disp
        integer :: i, j, r
        i = 1
        do while (i <= len(text))
            if (text(i:i) == BS) then
                i = i + 2
            else if (text(i:i) == "`" .and. .not. in_disp) then
                r = 1
                do while (i + r <= len(text))
                    if (text(i + r:i + r) /= "`") exit
                    r = r + 1
                end do
                j = index(text(i + r:), repeat("`", r))
                i = i + r
                if (j > 0) i = i + j - 1 + r
            else if (text(i:i) == "$") then
                if (i < len(text)) then
                    if (text(i + 1:i + 1) == "$") then
                        in_disp = .not. in_disp
                        i = i + 2
                        cycle
                    end if
                end if
                if (.not. in_disp) then
                    j = closing_dollar(text, i)
                    if (j > 0) then
                        i = j + 1
                    else
                        i = i + 1
                    end if
                else
                    i = i + 1
                end if
            else
                i = i + 1
            end if
        end do
    end subroutine scan_display

    ! Whether a closing $$ appears in lines(from:n) before the next blank line.
    logical function has_display_close(L, from, n) result(found)
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: from, n
        integer :: k
        logical :: in_disp
        found = .false.
        in_disp = .true.
        do k = from, n
            if (len_trim(L(k)%s) == 0) exit
            call scan_display(L(k)%s, in_disp)
            if (.not. in_disp) then
                found = .true.
                return
            end if
        end do
    end function has_display_close

    ! A paragraph of inline text in the context's settings.
    recursive subroutine paragraph(doc, text, ctx)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: text
        type(md_ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: s
        real(dp) :: ind
        s = trim(adjustl(text))
        ind = 0.0_dp
        if (ctx%indent .and. .not. doc%NOINDENT .and. ctx%align == ALIGN_JUSTIFY) &
            ind = doc%PARINDENT
        doc%NOINDENT = .false.
        call ts_begin_par(doc%engine, ctx%align, ind, left=ctx%left, right=ctx%right, &
                size=ctx%size, &
                          leading=doc%LEAD*ctx%size)
        call put_labels(doc, ctx, ctx%left)
        call inline(doc, s, base_style(ctx))
        call ts_end_par(doc%engine)
    end subroutine paragraph

    ! An item's label, waiting for the item's first line.
    recursive subroutine push_label(doc, s, left)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: left
        type(pending_t), allocatable :: grown(:)
        if (.not. allocated(doc%PENDING)) allocate (doc%PENDING(4))
        if (doc%NPEND == size(doc%PENDING)) then
            allocate (grown(2*size(doc%PENDING)))
            grown(1:doc%NPEND) = doc%PENDING(1:doc%NPEND)
            call move_alloc(grown, doc%PENDING)
        end if
        doc%NPEND = doc%NPEND + 1
        doc%PENDING(doc%NPEND)%s = s
        doc%PENDING(doc%NPEND)%left = left
    end subroutine push_label

    ! The labels waiting for the line just begun, whose text starts at
    ! left: each half an em before its own item's text.
    recursive subroutine put_labels(doc, ctx, left)
        type(md_document_t), intent(inout) :: doc
        type(md_ctx_t), intent(in) :: ctx
        real(dp), intent(in) :: left
        integer :: k
        do k = 1, doc%NPEND
            call ts_label(doc%engine, doc%PENDING(k)%s, label_face(ctx), ctx%size, &
                          0.5_dp*doc%BASE + left - doc%PENDING(k)%left, ctx%color)
        end do
        doc%NPEND = 0
    end subroutine put_labels

    integer function label_face(ctx)
        type(md_ctx_t), intent(in) :: ctx
        label_face = FACE_REGULAR
        if (ctx%bold) label_face = FACE_BOLD
    end function label_face

    ! Headings: LaTeX's \section, \subsection and \subsubsection, numbered
    ! within the chapter in a book, unless on_heading sets them.
    recursive subroutine heading(doc, text0, level, ctx)
        type(md_document_t), intent(inout) :: doc
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
        ex = face_xheight(FACE_REGULAR)*doc%BASE
        lv = level
        num = ""
        if (doc%CHAPTERS .and. level == 1) then
            doc%CHAPTER = doc%CHAPTER + 1
            doc%SEC = 0
            doc%EQNO = 0
            doc%FIGNO = 0
            doc%TABNO = 0
            if (doc%NUMBER_SECTIONS) num = itoa(doc%CHAPTER)
        else
            if (doc%CHAPTERS) lv = level - 1
            if (doc%NUMBER_SECTIONS .and. lv <= 3) then
                doc%SEC(lv) = doc%SEC(lv) + 1
                doc%SEC(lv + 1:) = 0
                if (doc%CHAPTERS) then
                    num = itoa(doc%CHAPTER)
                else
                    num = itoa(doc%SEC(1))
                end if
                do k = merge(1, 2, doc%CHAPTERS), lv
                    num = num//"."//itoa(doc%SEC(k))
                end do
            end if
        end if
        call place_targets(doc, num, text)
        if (associated(doc%CB_HEAD)) then
            this%level = level
            this%text = text
            this%num = num
            handled = .false.
            call doc%CB_HEAD(doc, this, ctx, handled)
            if (handled) then
                doc%AFTER_HEADING = .true.
                return
            end if
        end if
        select case (lv)
        case (1)
            size = 1.44_dp*doc%BASE
            baseline = 18.0_dp*doc%BASE/10.0_dp
            before = ts_glue_t(3.5_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(2.3_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case (2)
            size = 1.2_dp*doc%BASE
            baseline = 14.0_dp*doc%BASE/10.0_dp
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        case default
            size = doc%BASE
            baseline = doc%LEAD*doc%BASE
            before = ts_glue_t(3.25_dp*ex, 1.0_dp*ex, 0.2_dp*ex, 0, 0)
            after = ts_glue_t(1.5_dp*ex, 0.2_dp*ex, 0.0_dp, 0, 0)
        end select
        ! Straight after a heading, the space after that one is all there
        ! is, as \@startsection has it when @nobreak is set.
        if (.not. doc%AFTER_HEADING) then
            call ts_addpenalty(doc%engine, -300)
            call ts_addvspace(doc%engine, before)
        end if
        st = base_style(ctx)
        st%bold = .true.
        st%size = size
        hang = 0.0_dp
        if (len(num) > 0) hang = text_width(num, FACE_BOLD, size) + size
        call ts_begin_par(doc%engine, ALIGN_JUSTIFY, 0.0_dp, left=ctx%left, right=ctx%right, &
                size=size, &
                          leading=baseline, hang=hang, nobreak=.true.)
        call put_labels(doc, ctx, ctx%left)
        if (len(num) > 0) then
            call ts_word(doc%engine, num, FACE_BOLD, size, ctx%color)
            call ts_kern(doc%engine, size)
        end if
        call inline(doc, text, st)
        call ts_end_par(doc%engine)
        call ts_penalty(doc%engine, 10000)
        call ts_vskip(doc%engine, after)
        call ts_nobreak_next(doc%engine)
        doc%NOINDENT = .true.
        doc%AFTER_HEADING = .true.
    end subroutine heading

    ! A list: LaTeX's itemize or enumerate, with its spacing at the depth
    ! it is at. A tight list (no blank lines between its items) is set as
    ! Pandoc's \tightlist sets it, without \itemsep and \parsep.
    recursive subroutine list_block(doc, L, n, i, ctx, blank_before)
        type(md_document_t), intent(inout) :: doc
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

        f = doc%BASE/10.0_dp
        lev = min(ctx%depth + 1, 4)
        select case (lev)
        case (1)
            topsep = ts_glue_t(8.0_dp*f, 2.0_dp*f, 4.0_dp*f, 0, 0)
            parsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.5_dp*doc%BASE
        case (2)
            topsep = ts_glue_t(4.0_dp*f, 2.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            itemsep = parsep
            lm = 2.2_dp*doc%BASE
        case (3)
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.87_dp*doc%BASE
        case default
            topsep = ts_glue_t(2.0_dp*f, 1.0_dp*f, 1.0_dp*f, 0, 0)
            parsep = ts_glue_t(0.0_dp, 1.0_dp*f, 0.0_dp, 0, 0)
            itemsep = topsep
            lm = 1.7_dp*doc%BASE
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
        sub%parskip = parsep
        if (kind == 0) then
            sub%ilev = ctx%ilev + 1
        else
            sub%elev = ctx%elev + 1
        end if
        if (doc%NPEND > 0) then
            ! A list that begins an item starts on the item's first line,
            ! its labels after the item's, as LaTeX's \@donoparitem has it.
            call ts_end_par(doc%engine)
        else if (blank_before .and. .not. ts_in_par(doc%engine)) then
            call ts_addpenalty(doc%engine, -51)
            call ts_addvspace(doc%engine, add_glue(topsep, partopsep))
        else
            call ts_end_par(doc%engine)
            call ts_addpenalty(doc%engine, -51)
            call ts_addvspace(doc%engine, topsep)
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
                call ts_addpenalty(doc%engine, -51)
                call ts_addvspace(doc%engine, itemsep)
            end if
            call push_label(doc, list_label(kind, merge(sub%ilev, sub%elev, kind == 0), num), &
                    sub%left)
            call ts_set_parskip(doc%engine, parsep)
            call blocks(doc, item, ni, sub)
            if (doc%NPEND > 0) then
                ! An item with no paragraph of its own still has its label.
                call ts_begin_par(doc%engine, sub%align, 0.0_dp, left=sub%left, right=sub%right, &
                                  size=sub%size)
                call put_labels(doc, sub, sub%left)
                call ts_strut(doc%engine, 0.7_dp*sub%size, 0.3_dp*sub%size)
                call ts_end_par(doc%engine)
            end if
            deallocate (item)
            num = num + 1
            j = k
        end do
        call ts_end_par(doc%engine)
        call ts_set_parskip(doc%engine, ctx%parskip)
        call ts_addpenalty(doc%engine, -51)
        if (ctx%depth == 0) then
            call ts_addvspace(doc%engine, add_glue(topsep, partopsep))
        else
            call ts_addvspace(doc%engine, topsep)
        end if
        i = m + 1
    end subroutine list_block

    recursive function parsep_of(doc, depth) result(g)
        type(md_document_t), intent(in) :: doc
        integer, intent(in) :: depth
        type(ts_glue_t) :: g
        real(dp) :: f
        f = doc%BASE/10.0_dp
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
    recursive subroutine quote_block(doc, L, n, ctx)
        type(md_document_t), intent(inout) :: doc
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
        sub%left = ctx%left + 2.5_dp*doc%BASE
        sub%right = ctx%right + 2.5_dp*doc%BASE
        sub%indent = .false.
        sub%parskip = parsep_of(doc, sub%depth)
        call ts_end_par(doc%engine)
        call ts_addpenalty(doc%engine, -51)
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(doc%engine, parsep_of(doc, sub%depth))
        call blocks(doc, q, n, sub)
        call ts_end_par(doc%engine)
        call ts_set_parskip(doc%engine, ctx%parskip)
        call ts_addpenalty(doc%engine, -51)
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
    end subroutine quote_block

    ! Fenced code: each line as it is, unbroken, its spaces kept.
    recursive subroutine code_block(doc, L, n, ctx)
        type(md_document_t), intent(inout) :: doc
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        type(md_ctx_t), intent(in) :: ctx
        integer :: k, i, j
        real(dp) :: sp
        character(len=:), allocatable :: s
        call ts_end_par(doc%engine)
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
        call ts_set_parskip(doc%engine, ts_glue_t())
        sp = text_width(" ", FACE_REGULAR, 0.9_dp*ctx%size)
        do k = 1, n
            s = L(k)%s
            call ts_begin_par(doc%engine, ALIGN_LEFT, 0.0_dp, left=ctx%left + 1.5_dp*doc%BASE, &
                              right=ctx%right, size=0.9_dp*ctx%size, leading=doc%LEAD*ctx%size)
            call ts_strut(doc%engine, 0.7_dp*ctx%size, 0.3_dp*ctx%size)
            if (k == 1) call put_labels(doc, ctx, ctx%left + 1.5_dp*doc%BASE)
            i = 1
            do while (i <= len(s))
                if (s(i:i) == " ") then
                    call ts_kern(doc%engine, sp)
                    i = i + 1
                    cycle
                end if
                j = i
                do while (j <= len(s))
                    if (s(j:j) == " ") exit
                    j = j + 1
                end do
                call ts_word(doc%engine, s(i:j - 1), FACE_REGULAR, 0.9_dp*ctx%size, CODE_COL)
                i = j
            end do
            call ts_end_par(doc%engine)
        end do
        call ts_set_parskip(doc%engine, ctx%parskip)
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)))
    end subroutine code_block

    ! A MyST directive :::{name} argument, followed by :key: value options
    ! and content, dispatched to the caller's on_directive callback when
    ! supplied.
    recursive subroutine set_div(doc, open_line, L, i, j, ctx)
        type(md_document_t), intent(inout) :: doc
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
        if (name /= "figure" .and. name /= "table") call other_block(doc)
        handled = .false.
        if (associated(doc%CB_DIR)) call doc%CB_DIR(doc, directive, ctx, handled)
        if (handled) then
            if (name == "figure" .or. name == "table") call other_block(doc)
        else if (name == "literalinclude") then
            call set_literalinclude(doc, directive, ctx)
        else if (name == "figure") then
            call set_figure(doc, arg, body, md_option(opts, "width"), &
                            md_option(opts, "align"), md_option(opts, "name"), ctx)
        else if (name == "table") then
            if (j - 1 >= content_at) then
                call set_table_directive(doc, arg, L(content_at:j - 1), j - content_at, &
                                         md_option(opts, "align"), md_option(opts, "name"), ctx)
            else
                call warn(doc, "table directive has no pipe table")
                call other_block(doc)
            end if
        else
            if (len(name) > 0) call warn(doc, "unhandled directive '"//name//"'")
            if (j - 1 >= content_at) &
                call blocks(doc, L(content_at:j - 1), j - content_at, ctx)
        end if
    end subroutine set_div

    ! Built-in :::{literalinclude} path directive. Resolves path relative
    ! to doc%BASE_DIR, supports :lines: ranges and :language:, and sets
    ! the selected lines as a code block.
    recursive subroutine set_literalinclude(doc, directive, ctx)
        type(md_document_t), intent(inout) :: doc
        type(md_directive_t), intent(in) :: directive
        type(md_ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: arg, path, raw, lines_opt
        type(line_t), allocatable :: all_lines(:), sel_lines(:)
        type(status_t) :: st
        integer :: nall, nsel

        arg = trim(directive%arg)
        if (len(arg) == 0) then
            call warn(doc, "literalinclude requires a file path")
            return
        end if
        path = join_path(doc%BASE_DIR, arg)
        call read_bytes(path, raw, st)
        if (.not. st%ok()) then
            call warn(doc, "literalinclude: "//trim(st%message))
            return
        end if
        call split_lines(raw, all_lines, nall)
        lines_opt = md_option(directive%opts, "lines")
        if (len(lines_opt) == 0) then
            if (nall > 0) call code_block(doc, all_lines, nall, ctx)
        else
            call select_literal_lines(doc, all_lines, nall, lines_opt, sel_lines, nsel)
            if (nsel > 0) call code_block(doc, sel_lines, nsel, ctx)
        end if
    end subroutine set_literalinclude

    ! Select 1-based inclusive line ranges from spec (e.g. "1-10", "5-",
    ! "-10", "1-3, 7-9", "4").
    recursive subroutine select_literal_lines(doc, all_lines, nall, spec, sel, nsel)
        type(md_document_t), intent(in) :: doc
        type(line_t), intent(in) :: all_lines(:)
        integer, intent(in) :: nall
        character(len=*), intent(in) :: spec
        type(line_t), allocatable, intent(out) :: sel(:)
        integer, intent(out) :: nsel
        integer, allocatable :: lo(:), hi(:)
        character(len=:), allocatable :: tok, left, right
        integer :: nparts, nr, i, j, dash, a, b, r, k, m
        logical :: ok1, ok2

        nparts = 1
        do i = 1, len(spec)
            if (spec(i:i) == ",") nparts = nparts + 1
        end do
        allocate (lo(nparts), hi(nparts))
        nr = 0
        i = 1
        do while (i <= len(spec))
            j = index(spec(i:), ",")
            if (j == 0) then
                tok = trim(adjustl(spec(i:)))
                i = len(spec) + 1
            else
                tok = trim(adjustl(spec(i:i + j - 2)))
                i = i + j
            end if
            if (len(tok) == 0) cycle
            dash = index(tok, "-")
            if (dash == 0) then
                a = parse_pos_int(tok, ok1)
                if (.not. ok1) then
                    call warn(doc, "literalinclude: invalid :lines: '"//trim(spec)//"'")
                    cycle
                end if
                nr = nr + 1
                lo(nr) = a
                hi(nr) = a
            else
                left = trim(adjustl(tok(1:dash - 1)))
                right = trim(adjustl(tok(dash + 1:)))
                if (len(left) == 0 .and. len(right) == 0) then
                    call warn(doc, "literalinclude: invalid :lines: '"//trim(spec)//"'")
                    cycle
                end if
                if (len(left) == 0) then
                    a = 1
                    ok1 = .true.
                else
                    a = parse_pos_int(left, ok1)
                end if
                if (len(right) == 0) then
                    b = nall
                    ok2 = .true.
                else
                    b = parse_pos_int(right, ok2)
                end if
                if (.not. ok1 .or. .not. ok2) then
                    call warn(doc, "literalinclude: invalid :lines: '"//trim(spec)//"'")
                    cycle
                end if
                if (len(right) > 0 .and. a > b) then
                    call warn(doc, "literalinclude: invalid :lines: '"//trim(spec)//"'")
                    cycle
                end if
                nr = nr + 1
                lo(nr) = a
                hi(nr) = b
            end if
        end do

        nsel = 0
        do r = 1, nr
            hi(r) = min(hi(r), nall)
            if (lo(r) <= hi(r)) nsel = nsel + (hi(r) - lo(r) + 1)
        end do
        allocate (sel(nsel))
        k = 0
        do r = 1, nr
            if (lo(r) > hi(r)) cycle
            do m = lo(r), hi(r)
                k = k + 1
                sel(k)%s = all_lines(m)%s
            end do
        end do
    end subroutine select_literal_lines

    recursive integer function parse_pos_int(s, ok)
        character(len=*), intent(in) :: s
        logical, intent(out) :: ok
        integer :: k, d
        parse_pos_int = 0
        ok = .false.
        if (len(s) == 0 .or. len(s) > 9) return
        do k = 1, len(s)
            d = iachar(s(k:k)) - iachar("0")
            if (d < 0 .or. d > 9) return
            parse_pos_int = parse_pos_int*10 + d
        end do
        ok = parse_pos_int >= 1
    end function parse_pos_int

    ! A vector figure (from :::{figure} name or ![caption](name)): looks up
    ! name in doc%FIG_NAMES, numbers it, binds pending targets and :name:,
    ! places the frame via ts_frame, and sets the caption beneath it.
    recursive subroutine set_figure(doc, fig_name, caption, width_opt, align_opt, &
                                    label_opt, ctx)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: fig_name, caption, width_opt, align_opt, label_opt
        type(md_ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: name, cap, num, al_str
        type(style_t) :: st
        type(recording_renderer_t) :: rec
        type(frame_t) :: fig_frame
        real(dp) :: avail, w, fw, fh
        integer :: idx, al, c, a, b

        name = trim(adjustl(fig_name))
        a = 1
        b = len(caption)
        do while (a <= b)
            if (caption(a:a) /= " " .and. caption(a:a) /= NL) exit
            a = a + 1
        end do
        do while (b >= a)
            if (caption(b:b) /= " " .and. caption(b:b) /= NL) exit
            b = b - 1
        end do
        if (a <= b) then
            cap = caption(a:b)
        else
            cap = ""
        end if

        doc%FIGNO = doc%FIGNO + 1
        if (doc%CHAPTERS) then
            num = itoa(doc%CHAPTER)//"."//itoa(doc%FIGNO)
        else
            num = itoa(doc%FIGNO)
        end if
        call place_targets(doc, num, cap, LAB_FIGURE)
        if (len_trim(label_opt) > 0) &
            call add_label(doc, trim(adjustl(label_opt)), num, cap, LAB_FIGURE)

        idx = find_figure(doc, name)
        if (idx == 0) call warn(doc, "unknown figure '"//name//"'")

        avail = max(0.0_dp, ts_hsize(doc%engine) - ctx%left - ctx%right)
        w = figure_width(doc, width_opt, avail)
        al = ALIGN_CENTER
        al_str = lower(trim(adjustl(align_opt)))
        if (len(al_str) > 0) then
            c = align_of(al_str, -1)
            if (c < 0) then
                call warn(doc, "cannot read the alignment '"//trim(adjustl(align_opt))//"'")
            else
                al = c
            end if
        end if

        call ts_end_par(doc%engine)
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(12.0_dp, 3.0_dp, 4.0_dp, 0, 0)))
        if (idx > 0 .and. .not. doc%FIRST_PASS) then
            call doc%FIG_SCENE%metrics(fw, fh, handle=doc%FIG_HANDLES(idx))
            if (fw > 0.0_dp .and. fh > 0.0_dp) then
                call rec%open_canvas(fw, fh)
                call doc%FIG_SCENE%draw(rec, handle=doc%FIG_HANDLES(idx))
                call rec%close_canvas()
                call rec%take(fig_frame)
                if (w > 0.0_dp) then
                    call ts_frame(doc%engine, fig_frame, width=w, align=al, &
                                  left=ctx%left, right=ctx%right)
                else
                    call ts_frame(doc%engine, fig_frame, align=al, &
                                  left=ctx%left, right=ctx%right)
                end if
            end if
        end if
        if (len(cap) > 0) then
            call ts_penalty(doc%engine, 10000)
            call ts_vskip(doc%engine, scale(doc, ts_glue_t(6.0_dp, 1.0_dp, 1.0_dp, 0, 0)))
            st = base_style(ctx)
            st%size = 0.9_dp*doc%BASE
            call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, left=ctx%left, &
                              right=ctx%right, size=st%size, leading=doc%LEAD*st%size, &
                              skip=.false.)
            call ts_word(doc%engine, "Figure", FACE_BOLD, st%size, st%color)
            call ts_nbsp(doc%engine, FACE_BOLD, st%size)
            call ts_word(doc%engine, num//":", FACE_BOLD, st%size, st%color)
            call ts_space(doc%engine, FACE_REGULAR, st%size)
            call inline(doc, cap, st)
            call ts_end_par(doc%engine)
        end if
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(12.0_dp, 3.0_dp, 4.0_dp, 0, 0)))
        doc%AFTER_HEADING = .false.
    end subroutine set_figure

    recursive integer function find_figure(doc, name)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: name
        integer :: k
        find_figure = 0
        do k = 1, doc%NFIG
            if (doc%FIG_NAMES(k)%s == name) then
                find_figure = k
                return
            end if
        end do
    end function find_figure

    ! Figure width from :width: (percentage of avail, or a length); 0 when omitted.
    recursive real(dp) function figure_width(doc, val, avail) result(w)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: val
        real(dp), intent(in) :: avail
        character(len=:), allocatable :: t
        real(dp) :: x
        logical :: ok
        w = 0.0_dp
        t = trim(adjustl(val))
        if (len(t) == 0) return
        if (t(len(t):len(t)) == "%") then
            x = number(doc, trim(t(1:len(t) - 1)), ok)
            if (ok .and. x > 0.0_dp) then
                w = (x/100.0_dp)*avail
            else if (ok) then
                call warn(doc, "figure width must be positive: '"//t//"'")
            end if
        else
            x = length(doc, t, doc%BASE, ok)
            if (ok .and. x > 0.0_dp) then
                w = x
            else if (ok) then
                call warn(doc, "figure width must be positive: '"//t//"'")
            end if
        end if
    end function figure_width

    ! Built-in :::{table} Caption directive wrapping a pipe table.
    recursive subroutine set_table_directive(doc, caption, L, n, align_opt, label_opt, ctx)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: caption, align_opt, label_opt
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        type(md_ctx_t), intent(in) :: ctx
        integer :: i, j

        i = 1
        do while (i <= n)
            if (len_trim(L(i)%s) > 0) exit
            i = i + 1
        end do
        if (i + 1 > n) then
            call warn(doc, "table directive has no pipe table")
            call other_block(doc)
            return
        end if
        if (.not. is_table_start(L(i)%s, L(i + 1)%s)) then
            call warn(doc, "table directive body is not a pipe table")
            call other_block(doc)
            return
        end if
        j = i + 2
        do while (j <= n)
            if (len_trim(L(j)%s) == 0) exit
            if (index(L(j)%s, "|") == 0) exit
            j = j + 1
        end do
        call set_table(doc, L(i:j - 1), j - i, caption, align_opt, label_opt, ctx)
    end subroutine set_table_directive

    ! Render a Markdown pipe table in booktabs style into a frame_t, place
    ! it with ts_frame, and attach an optional caption below it.
    recursive subroutine set_table(doc, L, nlines, caption, align_opt, label_opt, ctx)
        type(md_document_t), intent(inout) :: doc
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: nlines
        character(len=*), intent(in) :: caption, align_opt, label_opt
        type(md_ctx_t), intent(in) :: ctx
        character(len=:), allocatable :: cap, num, al_str
        type(line_t), allocatable :: row_cells(:), grid(:, :)
        integer, allocatable :: col_align(:), cell_handles(:, :)
        real(dp), allocatable :: col_w(:), col_x(:), cell_w(:, :), cell_h(:, :), row_h(:)
        type(frame_t) :: cell_scene, cf, tab_frame
        type(recording_renderer_t) :: rec
        type(paint_t) :: rule_paint
        type(clip_t) :: no_clip
        type(style_t) :: st
        real(dp) :: avail, fsz, outer_pad, col_gap, total_w, total_h, budget, scale_f
        real(dp) :: top_rule, mid_rule, bot_rule, hdr_pt, hdr_pb, row_pt, row_pb, last_pb
        real(dp) :: y_cur, dx, cw, ch
        integer :: ncols, nrows, nc, r, c, al, ci
        logical :: ok, wrapped

        cap = trim(adjustl(caption))
        doc%TABNO = doc%TABNO + 1
        if (doc%CHAPTERS) then
            num = itoa(doc%CHAPTER)//"."//itoa(doc%TABNO)
        else
            num = itoa(doc%TABNO)
        end if
        call place_targets(doc, num, cap, LAB_TABLE)
        if (len_trim(label_opt) > 0) &
            call add_label(doc, trim(adjustl(label_opt)), num, cap, LAB_TABLE)

        al = ALIGN_CENTER
        al_str = lower(trim(adjustl(align_opt)))
        if (len(al_str) > 0) then
            ci = align_of(al_str, -1)
            if (ci < 0) then
                call warn(doc, "cannot read the alignment '"//trim(adjustl(align_opt))//"'")
            else
                al = ci
            end if
        end if

        ok = is_table_sep(L(2)%s, col_align, ncols)
        if (.not. ok .or. ncols <= 0) then
            doc%AFTER_HEADING = .false.
            return
        end if

        nrows = nlines - 1
        allocate (grid(nrows, ncols))
        do r = 1, nrows
            if (r == 1) then
                call split_table_row(L(1)%s, row_cells, nc)
            else
                call split_table_row(L(r + 1)%s, row_cells, nc)
            end if
            do c = 1, ncols
                if (c <= nc) then
                    grid(r, c)%s = row_cells(c)%s
                else
                    grid(r, c)%s = ""
                end if
            end do
        end do

        call ts_end_par(doc%engine)
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 4.0_dp, 0, 0)))

        if (.not. doc%FIRST_PASS) then
            fsz = 0.9_dp*ctx%size
            avail = max(20.0_dp, ts_hsize(doc%engine) - ctx%left - ctx%right)
            call cell_scene%init(0.0_dp, 0.0_dp)
            allocate (cell_handles(nrows, ncols), cell_w(nrows, ncols), cell_h(nrows, ncols))
            allocate (col_w(ncols), col_x(ncols), row_h(nrows))
            col_w = 0.0_dp

            do r = 1, nrows
                do c = 1, ncols
                    call typeset_cell(doc, grid(r, c)%s, 10000.0_dp, fsz, r == 1, &
                                      ctx%color, ALIGN_LEFT, cf, cw, ch)
                    call cell_scene%import_frame(cf, cell_handles(r, c))
                    cell_w(r, c) = cw
                    cell_h(r, c) = ch
                    if (cw > col_w(c)) col_w(c) = cw
                end do
            end do
            do c = 1, ncols
                col_w(c) = max(col_w(c), 0.5_dp*fsz)
            end do

            outer_pad = 0.6_dp*fsz
            col_gap = 1.4_dp*fsz
            total_w = sum(col_w) + 2.0_dp*outer_pad + real(max(0, ncols - 1), dp)*col_gap
            wrapped = .false.
            if (total_w > avail) then
                wrapped = .true.
                outer_pad = 0.4_dp*fsz
                col_gap = 1.0_dp*fsz
                budget = max(real(ncols, dp)*12.0_dp, &
                             avail - 2.0_dp*outer_pad - real(max(0, ncols - 1), dp)*col_gap)
                scale_f = budget/max(1.0_dp, sum(col_w))
                do c = 1, ncols
                    col_w(c) = max(12.0_dp, col_w(c)*scale_f)
                end do
                call cell_scene%init(0.0_dp, 0.0_dp)
                do r = 1, nrows
                    do c = 1, ncols
                        call typeset_cell(doc, grid(r, c)%s, col_w(c), fsz, r == 1, &
                                          ctx%color, col_align(c), cf, cw, ch)
                        call cell_scene%import_frame(cf, cell_handles(r, c))
                        cell_w(r, c) = cw
                        cell_h(r, c) = ch
                    end do
                end do
                total_w = sum(col_w) + 2.0_dp*outer_pad + real(max(0, ncols - 1), dp)*col_gap
            end if

            col_x(1) = outer_pad
            do c = 2, ncols
                col_x(c) = col_x(c - 1) + col_w(c - 1) + col_gap
            end do

            do r = 1, nrows
                row_h(r) = fsz
                do c = 1, ncols
                    if (cell_h(r, c) > row_h(r)) row_h(r) = cell_h(r, c)
                end do
            end do

            top_rule = 0.8_dp
            mid_rule = 0.4_dp
            bot_rule = 0.8_dp
            hdr_pt = 4.5_dp
            hdr_pb = 4.5_dp
            row_pt = 3.2_dp
            row_pb = 3.2_dp
            last_pb = 4.5_dp

            total_h = top_rule + hdr_pt + row_h(1) + hdr_pb + mid_rule
            do r = 2, nrows
                if (r == nrows) then
                    total_h = total_h + row_pt + row_h(r) + last_pb
                else
                    total_h = total_h + row_pt + row_h(r) + row_pb
                end if
            end do
            total_h = total_h + bot_rule

            rule_paint%filled = .true.
            rule_paint%fill_rgb = [ctx%color/65536, mod(ctx%color/256, 256), mod(ctx%color, 256)]

            call rec%open_canvas(total_w, total_h)
            call rec%draw_rect(0.0_dp, 0.0_dp, total_w, top_rule, rule_paint)

            y_cur = top_rule + hdr_pt
            do r = 1, nrows
                if (r == 2) then
                    call rec%draw_rect(0.0_dp, y_cur, total_w, mid_rule, rule_paint)
                    y_cur = y_cur + mid_rule + row_pt
                end if
                do c = 1, ncols
                    if (wrapped) then
                        dx = col_x(c)
                    else if (col_align(c) == ALIGN_CENTER) then
                        dx = col_x(c) + 0.5_dp*(col_w(c) - cell_w(r, c))
                    else if (col_align(c) == ALIGN_RIGHT) then
                        dx = col_x(c) + col_w(c) - cell_w(r, c)
                    else
                        dx = col_x(c)
                    end if
                    call rec%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, dx, y_cur], no_clip)
                    call cell_scene%draw(rec, handle=cell_handles(r, c))
                    call rec%end_frame()
                end do
                if (r == 1) then
                    y_cur = y_cur + row_h(1) + hdr_pb
                    if (nrows == 1) then
                        call rec%draw_rect(0.0_dp, y_cur, total_w, mid_rule, rule_paint)
                        y_cur = y_cur + mid_rule
                    end if
                else if (r == nrows) then
                    y_cur = y_cur + row_h(r) + last_pb
                else
                    y_cur = y_cur + row_h(r) + row_pb + row_pt
                end if
            end do
            call rec%draw_rect(0.0_dp, total_h - bot_rule, total_w, bot_rule, rule_paint)
            call rec%close_canvas()
            call rec%take(tab_frame)

            call ts_frame(doc%engine, tab_frame, align=al, left=ctx%left, right=ctx%right)
        end if

        if (len(cap) > 0) then
            call ts_penalty(doc%engine, 10000)
            call ts_vskip(doc%engine, scale(doc, ts_glue_t(6.0_dp, 1.0_dp, 1.0_dp, 0, 0)))
            st = base_style(ctx)
            st%size = 0.9_dp*doc%BASE
            call ts_begin_par(doc%engine, ALIGN_CENTER, 0.0_dp, left=ctx%left, &
                              right=ctx%right, size=st%size, leading=doc%LEAD*st%size, &
                              skip=.false.)
            call ts_word(doc%engine, "Table", FACE_BOLD, st%size, st%color)
            call ts_nbsp(doc%engine, FACE_BOLD, st%size)
            call ts_word(doc%engine, num//":", FACE_BOLD, st%size, st%color)
            call ts_space(doc%engine, FACE_REGULAR, st%size)
            call inline(doc, cap, st)
            call ts_end_par(doc%engine)
        end if
        call ts_addvspace(doc%engine, scale(doc, ts_glue_t(10.0_dp, 3.0_dp, 4.0_dp, 0, 0)))
        doc%AFTER_HEADING = .false.
    end subroutine set_table

    ! Typeset a single table cell into a frame_t of exact height and measured ink width.
    recursive subroutine typeset_cell(parent, text, width, fsz, bold, col, align, &
                                      frame, ink_w, box_h)
        type(md_document_t), intent(in) :: parent
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width, fsz
        logical, intent(in) :: bold
        integer, intent(in) :: col, align
        type(frame_t), intent(out) :: frame
        real(dp), intent(out) :: ink_w, box_h
        type(md_document_t) :: sub
        type(style_t) :: st
        type(recording_renderer_t) :: rec
        type(clip_t) :: no_clip
        real(dp) :: w_use, top_gap, b(4)
        logical :: has_ink

        w_use = max(1.0_dp, width)
        call ts_reset(sub%engine)
        call defaults(sub)
        sub%BASE = fsz
        sub%LEAD = 1.2_dp
        sub%PARINDENT = 0.0_dp
        sub%DOC_ALIGN = align
        sub%TEXT_COL = col
        sub%FIRST_PASS = .false.
        if (parent%NLAB > 0 .and. allocated(parent%LABS)) then
            sub%NLAB = parent%NLAB
            allocate (sub%LABS(parent%NLAB))
            sub%LABS(1:parent%NLAB) = parent%LABS(1:parent%NLAB)
        end if
        call ts_set_page(sub%engine, w_use, 100000.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                         numbers=.false., headings_=.false., flush=.false.)
        call ts_set_font(sub%engine, fsz, 1.2_dp*fsz)
        call ts_set_colors(sub%engine, col, 16777215)

        st%size = fsz
        st%color = col
        st%bold = bold
        st%italic = .false.
        st%code = .false.

        call ts_begin_par(sub%engine, align, 0.0_dp, size=fsz, leading=1.2_dp*fsz, skip=.false.)
        call ts_strut(sub%engine, 0.75_dp*fsz, 0.25_dp*fsz)
        if (len_trim(text) > 0) call inline(sub, trim(text), st)
        call ts_end_par(sub%engine)
        call ts_paginate(sub%engine)

        box_h = max(fsz, ts_box_height(sub%engine, 1, top_gap))
        call rec%open_canvas(w_use, box_h)
        if (ts_page_count(sub%engine) >= 1) then
            call rec%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, -top_gap], no_clip)
            call ts_page_draw(sub%engine, rec, 1)
            call rec%end_frame()
        end if
        call rec%close_canvas()
        call rec%take(frame)

        call frame%ink_bounds(b, has_ink)
        if (has_ink) then
            ink_w = max(0.0_dp, b(3))
        else
            ink_w = 0.0_dp
        end if
    end subroutine typeset_cell

    ! Whether line1 and line2 begin a Markdown pipe table (header + separator).
    recursive logical function is_table_start(line1, line2)
        character(len=*), intent(in) :: line1, line2
        integer, allocatable :: aligns(:)
        integer :: nc
        is_table_start = .false.
        if (index(line1, "|") == 0) return
        if (index(line2, "|") == 0) return
        is_table_start = is_table_sep(line2, aligns, nc)
    end function is_table_start

    ! Parse a Markdown table separator row like `| --- | :--- | :---: | ---: |`.
    recursive logical function is_table_sep(s, aligns, ncols)
        character(len=*), intent(in) :: s
        integer, allocatable, intent(out) :: aligns(:)
        integer, intent(out) :: ncols
        type(line_t), allocatable :: cells(:)
        character(len=:), allocatable :: c
        integer :: k, a, b, j
        logical :: lcol, rcol

        is_table_sep = .false.
        ncols = 0
        if (index(s, "|") == 0 .or. index(s, "-") == 0) return
        call split_table_row(s, cells, ncols)
        if (ncols <= 0) return
        allocate (aligns(ncols))
        do k = 1, ncols
            c = trim(adjustl(cells(k)%s))
            if (len(c) == 0) return
            a = 1
            b = len(c)
            lcol = .false.
            rcol = .false.
            if (c(a:a) == ":") then
                lcol = .true.
                a = a + 1
            end if
            if (b >= a) then
                if (c(b:b) == ":") then
                    rcol = .true.
                    b = b - 1
                end if
            end if
            if (a > b) return
            do j = a, b
                if (c(j:j) /= "-") return
            end do
            if (lcol .and. rcol) then
                aligns(k) = ALIGN_CENTER
            else if (rcol) then
                aligns(k) = ALIGN_RIGHT
            else
                aligns(k) = ALIGN_LEFT
            end if
        end do
        is_table_sep = .true.
    end function is_table_sep

    ! Split a pipe-table row into trimmed cells, handling optional outer pipes
    ! and escaped `\|`.
    recursive subroutine split_table_row(s, cells, ncells)
        character(len=*), intent(in) :: s
        type(line_t), allocatable, intent(out) :: cells(:)
        integer, intent(out) :: ncells
        character(len=:), allocatable :: t, buf
        type(line_t), allocatable :: grown(:)
        integer :: a, b, i, cap, nlen

        t = trim(adjustl(s))
        a = 1
        b = len(t)
        if (a <= b) then
            if (t(a:a) == "|") a = a + 1
        end if
        if (a <= b) then
            if (t(b:b) == "|") then
                if (b == 1) then
                    b = b - 1
                else if (t(b - 1:b - 1) /= BS) then
                    b = b - 1
                end if
            end if
        end if

        cap = 8
        allocate (cells(cap))
        ncells = 0
        if (a > b) return

        allocate (character(len=max(16, b - a + 1)) :: buf)
        nlen = 0
        i = a
        do while (i <= b)
            if (t(i:i) == BS .and. i < b) then
                if (t(i + 1:i + 1) == "|") then
                    nlen = nlen + 1
                    buf(nlen:nlen) = "|"
                    i = i + 2
                    cycle
                end if
            end if
            if (t(i:i) == "|") then
                if (ncells == cap) then
                    allocate (grown(2*cap))
                    grown(1:ncells) = cells(1:ncells)
                    call move_alloc(grown, cells)
                    cap = 2*cap
                end if
                ncells = ncells + 1
                cells(ncells)%s = trim(adjustl(buf(1:nlen)))
                nlen = 0
            else
                nlen = nlen + 1
                buf(nlen:nlen) = t(i:i)
            end if
            i = i + 1
        end do
        if (ncells == cap) then
            allocate (grown(2*cap))
            grown(1:ncells) = cells(1:ncells)
            call move_alloc(grown, cells)
        end if
        ncells = ncells + 1
        cells(ncells)%s = trim(adjustl(buf(1:nlen)))
    end subroutine split_table_row

    ! --- Template helpers -------------------------------------------------

    recursive subroutine md_blocks(doc, body, ctx)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: body
        type(md_ctx_t), intent(in) :: ctx
        type(line_t), allocatable :: L(:)
        integer :: n
        if (len_trim(body) == 0) return
        call split_lines(body, L, n)
        if (n > 0) call blocks(doc, L, n, ctx)
    end subroutine md_blocks

    recursive subroutine md_inline(doc, text, ctx)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: text
        type(md_ctx_t), intent(in) :: ctx
        if (doc%NPEND > 0 .and. ts_in_par(doc%engine)) call put_labels(doc, ctx, ctx%left)
        call inline(doc, text, base_style(ctx))
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

    recursive function md_meta(doc, key) result(val)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: key
        character(len=:), allocatable :: val, want
        integer :: k
        val = ""
        want = lower(trim(key))
        do k = 1, doc%NMETA
            if (doc%META(k)%key == want) then
                val = doc%META(k)%val
                return
            end if
        end do
    end function md_meta

    recursive subroutine md_noindent(doc, flag)
        type(md_document_t), intent(inout) :: doc
        logical, intent(in) :: flag
        doc%NOINDENT = flag
    end subroutine md_noindent

    recursive real(dp) function md_base_size(doc)
        type(md_document_t), intent(in) :: doc
        md_base_size = doc%BASE
    end function md_base_size

    recursive real(dp) function md_length(doc, v, size)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: v
        real(dp), intent(in) :: size
        md_length = length(doc, v, size)
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
    recursive subroutine inline(doc, s, st0)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: s
        type(style_t), intent(in) :: st0
        type(style_t) :: st, sp
        character(len=:), allocatable :: wbuf, src, tag, cmd, arg, ref_text
        integer :: i, j, k, r, cp, nb, sp_face, nw, em_depth, strong_depth
        real(dp) :: sp_size
        logical :: space, lf, rf, m_ok
        character :: c, prev, next
        character :: em_cs(16), strong_cs(16)

        st = st0
        allocate (character(len=max(64, len(s))) :: wbuf)
        nw = 0
        space = .false.
        em_depth = 0
        strong_depth = 0
        em_cs = " "
        strong_cs = " "
        i = 1
        do while (i <= len(s))
            c = s(i:i)
            select case (c)
            case (" ", NL, achar(9))
                ! Two spaces before the end of a line break it.
                if (c == " " .and. i + 2 <= len(s)) then
                    if (s(i:i + 2) == "  "//NL) then
                        call flush()
                        call ts_hard_break(doc%engine)
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
                if (rf .and. ((r == 1 .and. em_depth > 0 .and. em_cs(max(1, em_depth)) == c) .or. &
                              (r == 2 .and. strong_depth > 0 .and. &
                               strong_cs(max(1, strong_depth)) == c) .or. &
                              (r >= 3 .and. em_depth > 0 .and. strong_depth > 0))) then
                    call flush()
                    if (r == 1 .or. r >= 3) then
                        em_depth = max(0, em_depth - 1)
                        st%italic = (em_depth > 0) .neqv. st0%italic
                    end if
                    if (r >= 2) then
                        strong_depth = max(0, strong_depth - 1)
                        st%bold = (strong_depth > 0) .or. st0%bold
                    end if
                else if (lf .and. r <= 3 .and. has_closer(s, i + r, c, r)) then
                    call flush()
                    if (r == 1 .or. r == 3) then
                        if (em_depth < size(em_cs)) then
                            em_depth = em_depth + 1
                            em_cs(em_depth) = c
                        end if
                        st%italic = (em_depth > 0) .neqv. st0%italic
                    end if
                    if (r >= 2) then
                        if (strong_depth < size(strong_cs)) then
                            strong_depth = strong_depth + 1
                            strong_cs(strong_depth) = c
                        end if
                        st%bold = .true.
                    end if
                else
                    call append_w(s(i:i + r - 1))
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
                    call append_w(s(i:i + r - 1))
                    i = i + r
                    cycle
                end if
                call flush()
                call flush_space()
                sp = st
                sp%code = .true.
                sp%bold = .false.
                sp%italic = .false.
                call plain(doc, trim(adjustl(s(i + r:i + r + j - 2))), sp, verbatim=.true.)
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
                            call display_tag(doc, s, k, tag)
                            call ts_math(doc%engine, src, st%size, st%color, display=.true., &
                                         tag=tag, ok=m_ok)
                            if (.not. m_ok) call warn(doc, "malformed math '"//trim(src)//"'")
                            space = .false.
                            i = k
                            do while (i <= len(s))
                                if (s(i:i) /= " " .and. s(i:i) /= NL) exit
                                i = i + 1
                            end do
                            cycle
                        end if
                        ! A $$ that is not closed is text.
                        call append_w("$$")
                        i = i + 2
                        cycle
                    end if
                end if
                j = closing_dollar(s, i)
                if (j > 0) then
                    call flush()
                    call flush_space()
                    call ts_math(doc%engine, s(i + 1:j - 1), st%size, st%color, display=.false., &
                                 ok=m_ok)
                    if (.not. m_ok) &
                        call warn(doc, "malformed math '"//trim(s(i + 1:j - 1))//"'")
                    i = j + 1
                else
                    call append_w("$")
                    i = i + 1
                end if
            case (BS)
                if (i == len(s)) then
                    call append_w(BS)
                    i = i + 1
                    cycle
                end if
                next = s(i + 1:i + 1)
                if (next == NL) then
                    call flush()
                    call ts_hard_break(doc%engine)
                    space = .false.
                    i = i + 2
                else if (punct(next)) then
                    call append_w(next)
                    i = i + 2
                else
                    call append_w(BS)
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
                            call inline(doc, s(i + 1:j - 1), sp)
                            i = j + k + 1
                            cycle
                        end if
                    end if
                end if
                call append_w("[")
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
                            ref_text = reference(doc, cmd, arg)
                            if (cmd == "eq") then
                                call append_w(ref_text)
                            else
                                call flush()
                                call flush_space()
                                if (doc%REF_DEPTH >= 4) then
                                    call warn(doc, "cyclic reference {"//cmd//"}`"//arg//"`")
                                    call append_w("??")
                                else
                                    doc%REF_DEPTH = doc%REF_DEPTH + 1
                                    call inline(doc, ref_text, st)
                                    doc%REF_DEPTH = doc%REF_DEPTH - 1
                                end if
                            end if
                            i = i + j + k + 1
                            cycle
                        end if
                    end if
                end if
                call append_w("{")
                i = i + 1
            case ("-")
                if (i + 2 <= len(s)) then
                    if (s(i:i + 2) == "---") then
                        call append_w(achar(226)//achar(128)//achar(148))
                        i = i + 3
                        cycle
                    end if
                end if
                if (i + 1 <= len(s)) then
                    if (s(i:i + 1) == "--") then
                        call append_w(achar(226)//achar(128)//achar(147))
                        i = i + 2
                        cycle
                    end if
                end if
                call append_w("-")
                i = i + 1
            case (".")
                if (i + 2 <= len(s)) then
                    if (s(i:i + 2) == "...") then
                        call append_w(achar(226)//achar(128)//achar(166))
                        i = i + 3
                        cycle
                    end if
                end if
                call append_w(".")
                i = i + 1
            case ('"')
                prev = quote_prev(s, i)
                if (opening(prev)) then
                    call append_w(achar(226)//achar(128)//achar(156))
                else
                    call append_w(achar(226)//achar(128)//achar(157))
                end if
                i = i + 1
            case ("'")
                prev = quote_prev(s, i)
                if (opening(prev)) then
                    call append_w(achar(226)//achar(128)//achar(152))
                else
                    call append_w(achar(226)//achar(128)//achar(153))
                end if
                i = i + 1
            case default
                ! One UTF-8 character; a no-break space is glue that
                ! does not break.
                call utf8_next(s, i, cp, nb)
                if (cp == 160) then
                    call flush()
                    call ts_nbsp(doc%engine, face_of(st), st%size)
                    space = .false.
                else
                    call append_w(s(i:i + nb - 1))
                end if
                i = i + nb
            end select
        end do
        call flush()

    contains

        subroutine append_w(piece)
            character(len=*), intent(in) :: piece
            character(len=:), allocatable :: grown
            integer :: need, m
            m = len(piece)
            if (m == 0) return
            need = nw + m
            if (need > len(wbuf)) then
                allocate (character(len=max(2*len(wbuf), need)) :: grown)
                if (nw > 0) grown(1:nw) = wbuf(1:nw)
                call move_alloc(grown, wbuf)
            end if
            wbuf(nw + 1:need) = piece
            nw = need
        end subroutine append_w

        ! The word so far goes out, after a space if one came before it.
        subroutine flush()
            if (nw == 0) return
            call flush_space()
            if (st%code) then
                call ts_word(doc%engine, wbuf(1:nw), FACE_REGULAR, st%size, CODE_COL)
            else
                call ts_word(doc%engine, wbuf(1:nw), face_of(st), st%size, st%color)
            end if
            nw = 0
        end subroutine flush

        subroutine flush_space()
            if (space) call ts_space(doc%engine, sp_face, sp_size)
            space = .false.
        end subroutine flush_space

    end subroutine inline

    ! The character before a quote at s(i:i), skipping emphasis/code delimiters.
    pure character function quote_prev(s, i)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        integer :: k
        k = i - 1
        do while (k >= 1)
            if (s(k:k) /= "*" .and. s(k:k) /= "_" .and. s(k:k) /= "`") exit
            k = k - 1
        end do
        quote_prev = " "
        if (k >= 1) quote_prev = s(k:k)
    end function quote_prev

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
    recursive subroutine plain(doc, t, st, verbatim)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: t
        type(style_t), intent(in) :: st
        logical, intent(in) :: verbatim
        integer :: i, j
        i = 1
        do while (i <= len(t))
            if (t(i:i) == " ") then
                call ts_space(doc%engine, FACE_REGULAR, st%size)
                i = i + 1
                cycle
            end if
            j = i
            do while (j <= len(t))
                if (t(j:j) == " ") exit
                j = j + 1
            end do
            if (verbatim) then
                call ts_word(doc%engine, t(i:j - 1), FACE_REGULAR, st%size, CODE_COL)
            else
                call ts_word(doc%engine, t(i:j - 1), face_of(st), st%size, st%color)
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
    recursive subroutine display_tag(doc, s, k, tag)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: s
        integer, intent(inout) :: k
        character(len=:), allocatable, intent(inout) :: tag
        character(len=:), allocatable :: name
        logical :: numbered
        numbered = doc%NUMBER_EQS
        if (parse_display_label(s, k, name)) numbered = .true.
        if (numbered) then
            doc%EQNO = doc%EQNO + 1
            if (doc%CHAPTERS) then
                tag = itoa(doc%CHAPTER)//"."//itoa(doc%EQNO)
            else
                tag = itoa(doc%EQNO)
            end if
        end if
        if (len(name) > 0) call add_label(doc, name, tag, "", LAB_EQUATION)
    end subroutine display_tag

    ! ------------------------------------------------------------------
    ! Cross references: the labels of headings and displays, with the
    ! numbers the first pass gave them, so that a reference may come
    ! before what it refers to.
    ! ------------------------------------------------------------------

    ! A label, recorded in the first pass; the second only reads them.
    recursive subroutine add_label(doc, name, num, title, kind)
        type(md_document_t), intent(inout) :: doc
        character(len=*), intent(in) :: name, num, title
        integer, intent(in) :: kind
        type(label_t), allocatable :: grown(:)
        if (.not. doc%FIRST_PASS) return
        if (find_label(doc, name) > 0) then
            write (error_unit, "(a)") "fplotlib: typeset: warning: duplicate label "//name
            return
        end if
        if (.not. allocated(doc%LABS)) allocate (doc%LABS(64))
        if (doc%NLAB == size(doc%LABS)) then
            allocate (grown(2*size(doc%LABS)))
            grown(1:doc%NLAB) = doc%LABS(1:doc%NLAB)
            call move_alloc(grown, doc%LABS)
        end if
        doc%NLAB = doc%NLAB + 1
        doc%LABS(doc%NLAB)%name = name
        doc%LABS(doc%NLAB)%num = num
        doc%LABS(doc%NLAB)%title = title
        doc%LABS(doc%NLAB)%kind = kind
    end subroutine add_label

    recursive integer function find_label(doc, name)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: name
        integer :: k
        find_label = 0
        do k = 1, doc%NLAB
            if (doc%LABS(k)%name == name) then
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
    recursive function reference(doc, role, arg) result(s)
        type(md_document_t), intent(in) :: doc
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
        r = find_label(doc, target)
        if (r > 0) then
            select case (role)
            case ("eq")
                if (doc%LABS(r)%kind == LAB_EQUATION .and. len(doc%LABS(r)%num) > 0) &
                    s = "("//doc%LABS(r)%num//")"
            case ("ref")
                if (explicit) then
                    s = title
                else if (len(doc%LABS(r)%title) > 0) then
                    s = doc%LABS(r)%title
                end if
            case ("numref")
                if (len(doc%LABS(r)%num) > 0) then
                    if (.not. explicit) then
                        title = "Section"//achar(194)//achar(160)//"%s"
                        if (doc%LABS(r)%kind == LAB_EQUATION) title = "(%s)"
                        if (doc%LABS(r)%kind == LAB_FIGURE) &
                            title = "Fig."//achar(194)//achar(160)//"%s"
                        if (doc%LABS(r)%kind == LAB_TABLE) &
                            title = "Table"//achar(194)//achar(160)//"%s"
                    end if
                    s = replace(replace(replace(title, "%s", doc%LABS(r)%num), "{number}", &
                                        doc%LABS(r)%num), "{name}", doc%LABS(r)%title)
                end if
            end select
        else if (explicit .and. role == "ref") then
            s = title
        end if
        if (r == 0 .or. s == "??") &
            call warn(doc, "unresolved reference {"//role//"}`"//trim(adjustl(arg))//"`")
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
    recursive subroutine warn(doc, message)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: message
        if (doc%FIRST_PASS) return
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
        integer :: k
        h = trim(adjustl(t(lev + 1:)))
        ! Closing #s go only when preceded by a space (or alone), as in CommonMark.
        k = len(h)
        do while (k > 0)
            if (h(k:k) /= "#") exit
            k = k - 1
        end do
        if (k < len(h)) then
            if (k == 0) then
                h = ""
            else if (h(k:k) == " " .or. h(k:k) == achar(9)) then
                h = trim(h(1:k))
            end if
        end if
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

    logical function fence_open(t, ch, flen)
        character(len=*), intent(in) :: t
        character, intent(out) :: ch
        integer, intent(out) :: flen
        integer :: k
        fence_open = .false.
        ch = " "
        flen = 0
        if (len(t) < 3) return
        if (t(1:1) /= "`" .and. t(1:1) /= "~") return
        ch = t(1:1)
        k = 1
        do while (k <= len(t))
            if (t(k:k) /= ch) exit
            k = k + 1
        end do
        flen = k - 1
        if (flen < 3) return
        ! CommonMark: a backtick fence's info string may not contain a backtick.
        if (ch == "`" .and. k <= len(t)) then
            if (index(t(k:), "`") > 0) return
        end if
        fence_open = .true.
    end function fence_open

    logical function fence_close(t, ch, flen)
        character(len=*), intent(in) :: t
        character, intent(in) :: ch
        integer, intent(in) :: flen
        fence_close = len(t) >= flen .and. verify(t, ch) == 0
    end function fence_close

    logical function div_opens(t)
        character(len=*), intent(in) :: t
        div_opens = .false.
        if (len(t) <= 3) return
        div_opens = len_trim(t(4:)) > 0 .and. verify(trim(t), ":") > 0
    end function div_opens

    ! A standalone Markdown image block: ![caption](name)
    logical function is_figure_line(t, caption, name)
        character(len=*), intent(in) :: t
        character(len=:), allocatable, intent(out) :: caption, name
        integer :: j
        is_figure_line = .false.
        caption = ""
        name = ""
        if (len(t) < 5) return
        if (t(1:2) /= "![") return
        j = matching(t, 2)
        if (j <= 0 .or. j + 2 > len(t)) return
        if (t(j + 1:j + 1) /= "(") return
        if (matching(t, j + 1) /= len(t)) return
        name = trim(adjustl(t(j + 2:len(t) - 1)))
        if (len(name) == 0) return
        caption = trim(t(3:j - 1))
        is_figure_line = .true.
    end function is_figure_line

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

    recursive subroutine split_lines(text, lines, n)
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
    recursive subroutine detab(s)
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

    ! Strip an unquoted YAML # comment (preceded by whitespace or at start).
    function strip_yaml_comment(s) result(t)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t
        character :: q
        integer :: k
        q = " "
        do k = 1, len(s)
            if (q /= " ") then
                if (s(k:k) == q) q = " "
            else if (s(k:k) == '"' .or. s(k:k) == "'") then
                q = s(k:k)
            else if (s(k:k) == "#") then
                if (k == 1) then
                    t = ""
                    return
                else if (s(k - 1:k - 1) == " " .or. s(k - 1:k - 1) == achar(9)) then
                    t = trim(s(1:k - 1))
                    return
                end if
            end if
        end do
        t = s
    end function strip_yaml_comment

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
    recursive real(dp) function number(doc, v, ok)
        type(md_document_t), intent(in) :: doc
        character(len=*), intent(in) :: v
        logical, intent(out) :: ok
        integer :: ios
        number = 0.0_dp
        read (v, *, iostat=ios) number
        ok = ios == 0
        if (.not. ok) call warn(doc, "cannot read the number '"//trim(v)//"'")
    end function number

    ! A length in points (1/72 in): a number with pt or bp, pc, in, cm,
    ! mm, em or ex (an em being size), a bare number in points. Nothing is
    ! 0; anything else is 0 too, with ok false and a warning.
    recursive real(dp) function length(doc, v, size, ok)
        type(md_document_t), intent(in) :: doc
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
            call warn(doc, "cannot read the length '"//t//"'")
        end if
        if (present(ok)) ok = good
    end function length

    ! LaTeX's glue scaled from its 10pt values to the body size.
    recursive function scale(doc, g) result(r)
        type(md_document_t), intent(in) :: doc
        type(ts_glue_t), intent(in) :: g
        type(ts_glue_t) :: r
        real(dp) :: f
        f = doc%BASE/10.0_dp
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
