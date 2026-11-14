! Native article, book, letter and invitation templates for the MyST frontend.
! Template policy owns typography and physical layout, while the document
! supplies standard metadata, parts and content. References are resolved in
! a first pass, independently of identifier spelling.
module fplotlib_docclass
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_colors, only: color_from_name
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_BOLD, FACE_ITALIC, face_xheight, &
                               face_capheight
    use fplotlib_text, only: text_width
    use fplotlib_doctree
    use fplotlib_doctemplate
    use fplotlib_markdown, only: md_parse
    use fplotlib_myst_inline, only: md_inlines, md_label
    use fplotlib_myst_metadata, only: decimal_number, author_name_key
    use fplotlib_render_checks, only: check_finite
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
        character(len=:), allocatable :: name, title, number
        integer :: kind = 0
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
        logical :: NUMBER_FIGURES = .true., NUMBER_TABLES = .true.
        type(template_t) :: template
        integer :: FIGURE_NO = 0, TABLE_NO = 0, REF_DEPTH = 0
        ! The title block's inlines: nodes of the front matter, 0 for none.
        integer :: TITLE = 0, SUBTITLE = 0, DATE = 0, ABSTRACT = 0
        integer :: NAUTHOR = 0
        integer, allocatable :: AUTHORS(:)
        integer :: TEXT_COL(3) = 0, PAGE_COL(3) = 255

        ! Counters and cross references.
        integer :: SEC(6) = 0, CHAPTER = 0, EQNO = 0
        integer :: NLAB = 0
        type(label_t), allocatable :: label(:)
        integer, allocatable :: NODE_TARGET(:)

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

        type(status_t), intent(out) :: status
        call doc_validate(doc, status=status)
        if (.not. status%ok()) return
        call ts_reset(state%engine, status=status)
        if (.not. status%ok()) return
        call defaults(state, status=status)
        if (.not. status%ok()) return
        if (doc%ngraphics > 0) then
            call ts_import_frame(state%engine, doc%graphics, state%graphics_base, status=status)
            if (.not. status%ok()) return
        end if
        call settings(state, doc, status=status)
        if (.not. status%ok()) return
        call validate_parts(state, doc, status)
        if (.not. status%ok()) return
        call ts_set_font(state%engine, state%BASE, state%LEAD*state%BASE, status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        call ts_set_colors(state%engine, state%TEXT_COL, state%PAGE_COL, status=status)
        if (.not. status%ok()) return
        call prepare_labels(state, doc, status)
        if (.not. status%ok()) return
        state%SEC = 0
        state%CHAPTER = 0
        state%EQNO = 0
        ctx%size = state%BASE
        ctx%color = state%TEXT_COL
        ctx%align = state%DOC_ALIGN
        call template_document(state, doc, ctx, status)
        if (.not. status%ok()) return
        call ts_finish(state%engine, document, status=status)
        if (.not. status%ok()) return
    end subroutine doc_typeset

    subroutine layout_markdown(state, text, document, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        type(paged_document_t), intent(out) :: document
        type(doc_t) :: tree
        type(status_t), intent(out) :: status
        call md_parse(text, tree, status=status)
        if (.not. status%ok()) return
        call doc_typeset(state, tree, document, status=status)
        if (.not. status%ok()) return
    end subroutine layout_markdown

    ! A width-constrained fragment for an annotation or another layout engine.
    ! It uses the same block/inline layout without title or page furniture.
    subroutine layout_fragment(state, text, width, frame, font_size, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width
        type(frame_t), intent(out) :: frame
        real(dp), intent(in), optional :: font_size
        type(doc_t) :: tree
        type(ctx_t) :: ctx
        integer :: i
        type(status_t), intent(out) :: status
        if (width <= 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "layout_fragment: width must be positive")
            return
        end if
        call md_parse(text, tree, status=status)
        if (.not. status%ok()) return
        if (tree%nmeta > 0) then
            call status%set(ERROR_UNSUPPORTED, "layout_fragment: document metadata requires a report")
            return
        end if
        do i = 1, tree%n
            if (tree%nodes(i)%kind == DOC_PART .or. tree%nodes(i)%break_before /= 0) then
                call status%set(ERROR_UNSUPPORTED, "layout_fragment: document parts and page breaks require a report")
                return
            end if
        end do
        call ts_reset(state%engine, status=status)
        if (.not. status%ok()) return
        call defaults(state, status=status)
        if (.not. status%ok()) return
        if (present(font_size)) state%BASE = font_size
        if (state%BASE <= 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "layout_fragment: font size must be positive")
            return
        end if
        call ts_set_page(state%engine, width, 1.0e6_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false., status=status)
        if (.not. status%ok()) return
        call ts_set_font(state%engine, state%BASE, state%LEAD*state%BASE, status=status)
        if (.not. status%ok()) return
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        state%PARINDENT = 0.0_dp
        ctx%size = state%BASE
        ctx%indent = .false.
        call prepare_labels(state, tree, status)
        if (.not. status%ok()) return
        state%SEC = 0
        state%CHAPTER = 0
        state%EQNO = 0
        call set_blocks(state, tree, 1, ctx, status=status)
        if (.not. status%ok()) return
        call ts_finish_frame(state%engine, frame, status=status)
        if (.not. status%ok()) return
    end subroutine layout_fragment

    subroutine defaults(state, status)
        type(layout_context_t), intent(inout) :: state
        type(status_t), intent(out) :: status
        call native_template("article", state%template, status)
        if (.not. status%ok()) return
        call template_style(state)
        state%NUMBER_SECTIONS = .false.
        state%NUMBER_EQS = .true.
        state%NUMBER_FIGURES = .true.
        state%NUMBER_TABLES = .true.
        state%FIGURE_NO = 0
        state%TABLE_NO = 0
        state%REF_DEPTH = 0
        state%TITLE = 0
        state%SUBTITLE = 0
        state%NAUTHOR = 0
        if (.not. allocated(state%AUTHORS)) allocate (state%AUTHORS(16))
        state%DATE = 0
        state%ABSTRACT = 0
        state%NLAB = 0
        if (.not. allocated(state%label)) allocate (state%label(16))
        if (allocated(state%NODE_TARGET)) deallocate (state%NODE_TARGET)
        state%SEC = 0
        state%CHAPTER = 0
        state%EQNO = 0
        state%NOINDENT = .false.
        state%graphics_base = 0
        state%PENDING_LABEL = ""
        state%W = ""
        state%SPACE = .false.
        call ts_set_page(state%engine, state%template%body%page_width, state%template%body%page_height, &
                         state%template%body%margins(1), state%template%body%margins(2), &
                         state%template%body%margins(3), state%template%body%margins(4), status=status)
        if (.not. status%ok()) return
    end subroutine defaults

    subroutine template_style(state)
        type(layout_context_t), intent(inout) :: state
        state%BASE = state%template%body%BASE
        state%LEAD = state%template%body%LEAD
        state%PARINDENT = state%template%body%PARINDENT
        state%PARSKIP_G = state%template%body%PARSKIP_G
        state%DOC_ALIGN = state%template%body%DOC_ALIGN
        state%TEXT_COL = state%template%body%TEXT_COL
        state%PAGE_COL = state%template%body%PAGE_COL
        state%BOOK = state%template%body%BOOK
    end subroutine template_style

    ! Standard MyST metadata plus declared options of one native print template.
    subroutine settings(state, doc, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer :: i, j
        character(len=:), allocatable :: key, val, name
        real(dp) :: pw, ph, margins(4), m
        logical :: numbers, flag, have_margin(4), have_indent, have_parskip
        integer, allocatable :: grown(:)
        type(status_t), intent(out) :: status

        name = state%template%name
        do i = 1, doc%nmeta
            if (doc%meta(i)%key == "exports.1.template") then
                if (doc%meta(i)%kind /= META_STRING) then
                    call status%set(ERROR_ARGUMENT, "MyST: template must be a string")
                    return
                end if
                if (len(doc%meta(i)%value) > len(state%template%name)) then
                    call status%set(ERROR_UNSUPPORTED, "MyST: unsupported native template")
                    return
                end if
                name = doc%meta(i)%value
            end if
        end do
        call native_template(name, state%template, status)
        if (.not. status%ok()) return
        call template_style(state)
        pw = state%template%body%page_width
        ph = state%template%body%page_height
        margins = state%template%body%margins
        numbers = state%template%body%page_numbers
        ! Mapping order does not affect relative lengths.
        do i = 1, doc%nmeta
            if (doc%meta(i)%key /= "exports.1.fontsize") cycle
            call read_length(doc%meta(i)%value, state%BASE, m, status)
            if (.not. status%ok()) return
            if (m <= 0.0_dp) then
                call status%set(ERROR_ARGUMENT, "MyST: fontsize must be positive")
                return
            end if
            state%BASE = m
        end do
        have_margin = .false.
        have_indent = .false.
        have_parskip = .false.
        m = -1.0_dp
        do i = 1, doc%nmeta
            key = doc%meta(i)%key
            val = doc%meta(i)%value
            if (key == "exports" .or. key == "exports.1") then
                if (key == "exports" .and. doc%meta(i)%kind /= META_SEQUENCE) then
                    call status%set(ERROR_UNSUPPORTED, "MyST: exports must be one block-style export entry")
                    return
                end if
                if (key == "exports.1" .and. doc%meta(i)%kind /= META_MAP) then
                    call status%set(ERROR_ARGUMENT, "MyST: a native export entry must be a mapping")
                    return
                end if
                cycle
            end if
            if (starts(key, "exports.")) then
                if (.not. starts(key, "exports.1.")) then
                    call status%set(ERROR_UNSUPPORTED, "MyST: the native renderer accepts one print export profile")
                    return
                end if
                key = key(11:)
                select case (key)
                case ("template", "fontsize", "id")
                case ("output")
                    call status%set(ERROR_UNSUPPORTED, "MyST: select the output filename with save(), not front matter")
                    return
                case ("format")
                    if (val /= "pdf") then
                        call status%set(ERROR_UNSUPPORTED, "MyST: the native print profile uses format: pdf")
                        return
                    end if
                case ("paper")
                    call native_paper(val, pw, ph, status)
                case ("margin")
                    call read_length(val, state%BASE, m, status)
                case ("margin-left", "margin-right", "margin-top", "margin-bottom")
                    j = 1
                    if (key == "margin-right") j = 2
                    if (key == "margin-top") j = 3
                    if (key == "margin-bottom") j = 4
                    call read_length(val, state%BASE, margins(j), status)
                    have_margin(j) = .true.
                case ("parskip")
                    call read_length(val, state%BASE, state%PARSKIP_G%w, status)
                    state%PARSKIP_G%st = 0.2_dp*state%PARSKIP_G%w
                    have_parskip = .true.
                case ("indent")
                    have_indent = .true.
                    if (doc%meta(i)%kind == META_BOOL) then
                        state%PARINDENT = merge(1.5_dp*state%BASE, 0.0_dp, val == "true")
                    else
                        call read_length(val, state%BASE, state%PARINDENT, status)
                    end if
                case ("linestretch")
                    if (.not. decimal_number(val)) then
                        call status%set(ERROR_ARGUMENT, "MyST: linestretch must be a number")
                        return
                    end if
                    read (val, *, iostat=j) state%LEAD
                    if (j /= 0) then
                        call status%set(ERROR_ARGUMENT, "MyST: linestretch must be a number")
                        return
                    end if
                    call check_finite([state%LEAD], status)
                    if (.not. status%ok()) return
                    if (state%LEAD <= 0.0_dp) then
                        call status%set(ERROR_ARGUMENT, "MyST: linestretch must be positive")
                        return
                    end if
                    state%LEAD = 1.2_dp*state%LEAD
                case ("align")
                    select case (val)
                    case ("left"); state%DOC_ALIGN = ALIGN_LEFT
                    case ("right"); state%DOC_ALIGN = ALIGN_RIGHT
                    case ("center"); state%DOC_ALIGN = ALIGN_CENTER
                    case ("justify"); state%DOC_ALIGN = ALIGN_JUSTIFY
                    case default
                        call status%set(ERROR_ARGUMENT, "MyST: invalid template alignment")
                        return
                    end select
                case ("pagenumbers")
                    call metadata_boolean(doc%meta(i), numbers, status)
                case ("color")
                    call native_color(val, state%TEXT_COL, status)
                case ("pagecolor")
                    call native_color(val, state%PAGE_COL, status)
                case default
                    call status%set(ERROR_UNSUPPORTED, "MyST: unsupported native template option: "//key)
                    return
                end select
                if (.not. status%ok()) return
                cycle
            end if
            select case (key)
            case ("title", "subtitle", "date", "abstract")
                if (doc%meta(i)%kind /= META_STRING .and. doc%meta(i)%kind /= META_NULL) then
                    call status%set(ERROR_ARGUMENT, "MyST: "//key//" must be a string")
                    return
                end if
            end select
            select case (key)
            case ("title")
                state%TITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("subtitle")
                state%SUBTITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("date")
                state%DATE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("abstract")
                state%ABSTRACT = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("numbering")
                if (doc%meta(i)%kind == META_MAP) cycle
                call metadata_boolean(doc%meta(i), flag, status)
                if (.not. status%ok()) return
                state%NUMBER_SECTIONS = flag
                state%NUMBER_EQS = flag
                state%NUMBER_FIGURES = flag
                state%NUMBER_TABLES = flag
            case ("numbering.headings", "numbering.equations", "numbering.figures", "numbering.tables")
                call metadata_boolean(doc%meta(i), flag, status)
                if (.not. status%ok()) return
                select case (key)
                case ("numbering.headings"); state%NUMBER_SECTIONS = flag
                case ("numbering.equations"); state%NUMBER_EQS = flag
                case ("numbering.figures"); state%NUMBER_FIGURES = flag
                case ("numbering.tables"); state%NUMBER_TABLES = flag
                end select
            case ("parts")
                if (doc%meta(i)%kind /= META_MAP) then
                    call status%set(ERROR_ARGUMENT, "MyST: parts must be a mapping")
                    return
                end if
            case default
                if (starts(key, "parts.")) then
                    if (doc%meta(i)%kind /= META_STRING) then
                        call status%set(ERROR_ARGUMENT, "MyST: native parts must contain Markdown strings")
                        return
                    end if
                else if (key == "authors" .or. starts(key, "authors.")) then
                    if (.not. author_name_key(key)) then
                        call status%set(ERROR_UNSUPPORTED, "MyST: native authors support names only")
                        return
                    end if
                    if (key == "authors" .and. doc%meta(i)%kind == META_MAP) then
                        call status%set(ERROR_ARGUMENT, "MyST: use a sequence for author mappings")
                        return
                    end if
                    if (doc%meta(i)%node > 0) then
                        if (state%NAUTHOR == size(state%AUTHORS)) then
                            allocate (grown(2*size(state%AUTHORS)))
                            grown(1:state%NAUTHOR) = state%AUTHORS(1:state%NAUTHOR)
                            call move_alloc(grown, state%AUTHORS)
                        end if
                        state%NAUTHOR = state%NAUTHOR + 1
                        state%AUTHORS(state%NAUTHOR) = doc%meta(i)%node
                    else if (doc%meta(i)%kind /= META_MAP .and. doc%meta(i)%kind /= META_SEQUENCE .and. &
                             doc%meta(i)%kind /= META_NULL) then
                        call status%set(ERROR_UNSUPPORTED, "MyST: native authors support names only")
                        return
                    end if
                else
                    call status%set(ERROR_UNSUPPORTED, "MyST: unsupported native front matter key: "//key)
                    return
                end if
            end select
        end do
        if (have_parskip .and. .not. have_indent) state%PARINDENT = 0.0_dp
        if (state%PARINDENT < 0.0_dp) state%PARINDENT = 1.5_dp*state%BASE
        if (m >= 0.0_dp) then
            do j = 1, 4
                if (.not. have_margin(j)) margins(j) = m
            end do
        end if
        call ts_set_page(state%engine, pw, ph, margins(1), margins(2), margins(3), margins(4), &
                         numbers, state%BOOK, state%BOOK, status=status)
        if (.not. status%ok()) return
    end subroutine settings

    subroutine metadata_boolean(meta, value, status)
        type(doc_meta_t), intent(in) :: meta
        logical, intent(out) :: value
        type(status_t), intent(out) :: status
        value = .false.
        if (meta%kind /= META_BOOL) then
            call status%set(ERROR_ARGUMENT, "MyST: "//meta%key//" must be a boolean")
            return
        end if
        value = meta%value == "true"
    end subroutine metadata_boolean

    subroutine read_length(text, size, value, status)
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: size
        real(dp), intent(out) :: value
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: t, unit
        integer :: n, ios
        t = trim(adjustl(text))
        unit = "bp"
        n = len(t)
        if (n >= 2) then
            select case (t(n - 1:n))
            case ("bp", "pt", "in", "cm", "mm", "em", "ex")
                unit = t(n - 1:n)
                t = trim(t(1:n - 2))
            end select
        end if
        if (.not. decimal_number(t)) then
            call status%set(ERROR_ARGUMENT, "MyST: invalid native-template length: "//text)
            return
        end if
        read (t, *, iostat=ios) value
        if (ios /= 0) then
            call status%set(ERROR_ARGUMENT, "MyST: invalid native-template length: "//text)
            return
        end if
        select case (unit)
        case ("in"); value = value*72.0_dp
        case ("cm"); value = value*72.0_dp/2.54_dp
        case ("mm"); value = value*72.0_dp/25.4_dp
        case ("em"); value = value*size
        case ("ex"); value = value*size*face_xheight(FACE_REGULAR)
        end select
        call check_finite([value], status)
        if (.not. status%ok()) return
        if (value < 0.0_dp) call status%set(ERROR_ARGUMENT, "MyST: native-template lengths must be nonnegative")
    end subroutine read_length

    subroutine native_paper(text, width, height, status)
        character(len=*), intent(in) :: text
        real(dp), intent(out) :: width, height
        type(status_t), intent(out) :: status
        integer :: split
        select case (text)
        case ("a4"); width = 595.2756_dp; height = 841.8898_dp
        case ("a5"); width = 419.5276_dp; height = 595.2756_dp
        case ("a6"); width = 297.6378_dp; height = 419.5276_dp
        case ("letter"); width = 612.0_dp; height = 792.0_dp
        case ("legal"); width = 612.0_dp; height = 1008.0_dp
        case ("b5"); width = 498.8976_dp; height = 708.6614_dp
        case default
            split = index(text, "x")
            if (split == 0) then
                call status%set(ERROR_ARGUMENT, "MyST: unknown native paper size: "//text)
                return
            end if
            call read_length(text(1:split - 1), 10.0_dp, width, status)
            if (.not. status%ok()) return
            call read_length(text(split + 1:), 10.0_dp, height, status)
        end select
    end subroutine native_paper

    subroutine native_color(text, rgb, status)
        character(len=*), intent(in) :: text
        integer, intent(out) :: rgb(3)
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: t
        integer :: value, ios
        t = trim(text)
        if (len(t) == 0) then
            call status%set(ERROR_ARGUMENT, "MyST: empty color; quote YAML hex colors")
            return
        end if
        if (t(1:1) /= "#") t = trim(color_from_name(t))
        if (len(t) == 4) t = "#"//t(2:2)//t(2:2)//t(3:3)//t(3:3)//t(4:4)//t(4:4)
        if (len(t) /= 7) then
            call status%set(ERROR_ARGUMENT, "MyST: unsupported color: "//text)
            return
        end if
        if (verify(t(2:), "0123456789abcdefABCDEF") /= 0) then
            call status%set(ERROR_ARGUMENT, "MyST: invalid hex color: "//text)
            return
        end if
        read (t(2:), "(z6)", iostat=ios) value
        if (ios /= 0) then
            call status%set(ERROR_ARGUMENT, "MyST: invalid hex color: "//text)
            return
        end if
        rgb = [ishft(value, -16), iand(ishft(value, -8), 255), iand(value, 255)]
    end subroutine native_color

    subroutine validate_parts(state, doc, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(status_t), intent(out) :: status
        integer :: i, j, k, part
        integer, allocatable :: nodes(:)
        do i = 1, doc%nmeta
            k = doc%meta(i)%node
            if (k == 0) cycle
            if (doc%nodes(k)%kind /= DOC_PART) cycle
            do j = 1, i - 1
                if (doc%meta(j)%node == 0) cycle
                if (doc%nodes(doc%meta(j)%node)%kind /= DOC_PART) cycle
                if (doc%nodes(doc%meta(j)%node)%part == doc%nodes(k)%part) then
                    call status%set(ERROR_ARGUMENT, "MyST: duplicate front-matter part: "//doc%nodes(k)%part)
                    return
                end if
            end do
        end do
        do i = 1, doc%n
            if (doc%nodes(i)%kind /= DOC_PART) cycle
            if (template_part_index(state%template, doc%nodes(i)%part) == 0) then
                call status%set(ERROR_UNSUPPORTED, "MyST: native template "//trim(state%template%name)// &
                                " does not declare part "//doc%nodes(i)%part)
                return
            end if
        end do
        state%ABSTRACT = 0
        do i = 1, size(state%template%steps)
            if (state%template%steps(i)%kind /= STEP_TITLE_BLOCK) cycle
            part = state%template%steps(i)%part
            call part_nodes(doc, trim(state%template%parts(part)%name), nodes)
            if (size(nodes) > 0) state%ABSTRACT = nodes(1)
        end do
    end subroutine validate_parts

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
                if (state%TITLE == 0) cycle
                title_context = part_context(state%template%title, ctx)
                title_style = base_style(title_context)
                call ts_begin_par(state%engine, title_context%align, 0.0_dp, size=title_style%size, &
                                  leading=state%LEAD*title_style%size, status=status)
                if (.not. status%ok()) return
                call set_inlines(state, doc, state%TITLE, title_style, status)
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
        integer, allocatable :: parts(:)
        real(dp) :: before, after
        call part_nodes(doc, trim(state%template%parts(part)%name), parts)
        if (size(parts) == 0) return
        style = state%template%parts(part)%style
        sub = part_context(style, ctx)
        before = style%before_fixed + style%before_base*state%BASE
        after = style%after_fixed + style%after_base*state%BASE
        if (before > 0.0_dp) then
            call ts_vskip(state%engine, ts_glue_t(before, 0.0_dp, 0.0_dp, 0, 0), status)
            if (.not. status%ok()) return
        end if
        do i = 1, size(parts)
            node = parts(i)
            call block_page_break(state, doc%nodes(node)%break_before, status)
            if (.not. status%ok()) return
            call set_blocks(state, doc, node, sub, status)
            if (.not. status%ok()) return
        end do
        if (after > 0.0_dp) call ts_vskip(state%engine, ts_glue_t(after, 0.0_dp, 0.0_dp, 0, 0), status)
    end subroutine named_part

    subroutine part_nodes(doc, name, parts)
        type(doc_t), intent(in) :: doc
        character(len=*), intent(in) :: name
        integer, allocatable, intent(out) :: parts(:)
        integer :: i, node, n
        do i = 1, doc%nmeta
            node = doc%meta(i)%node
            if (node == 0) cycle
            if (doc%nodes(node)%kind /= DOC_PART) cycle
            if (doc%nodes(node)%part /= name) cycle
            allocate (parts(1))
            parts(1) = node
            return
        end do
        n = 0
        node = doc%nodes(1)%first
        do while (node > 0)
            if (doc%nodes(node)%kind == DOC_PART .and. doc%nodes(node)%part == name) n = n + 1
            node = doc%nodes(node)%next
        end do
        allocate (parts(n))
        i = 0
        node = doc%nodes(1)%first
        do while (node > 0)
            if (doc%nodes(node)%kind == DOC_PART .and. doc%nodes(node)%part == name) then
                i = i + 1
                parts(i) = node
            end if
            node = doc%nodes(node)%next
        end do
    end subroutine part_nodes

    ! LaTeX's \maketitle and abstract, for the article class.
    subroutine title_block(state, doc, ctx, abstract_part, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(ctx_t), intent(in) :: ctx
        integer, intent(in) :: abstract_part
        type(style_t) :: st
        integer :: i
        type(status_t), intent(out) :: status
        if (state%TITLE == 0) then
            call abstract_block(state, doc, ctx, abstract_part, status)
            return
        end if
        st = base_style(ctx)
        call ts_vkeep(state%engine, ts_glue_t(2.0_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
        st%size = 1.728_dp*state%BASE
        call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, leading=22.0_dp*state%BASE/10.0_dp, &
                          skip=.false., status=status)
        if (.not. status%ok()) return
        call set_inlines(state, doc, state%TITLE, st, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        if (state%SUBTITLE > 0) then
            st%size = 1.2_dp*state%BASE
            call ts_vskip(state%engine, ts_glue_t(0.5_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
            call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*state%BASE/10.0_dp, skip=.false., status=status)
            if (.not. status%ok()) return
            call set_inlines(state, doc, state%SUBTITLE, st, status=status)
            if (.not. status%ok()) return
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
        end if
        st%size = 1.2_dp*state%BASE
        if (state%NAUTHOR > 0) then
            call ts_vskip(state%engine, ts_glue_t(1.5_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
            do i = 1, state%NAUTHOR
                call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                                  leading=14.0_dp*state%BASE/10.0_dp, skip=.false., status=status)
                if (.not. status%ok()) return
                call set_inlines(state, doc, state%AUTHORS(i), st, status=status)
                if (.not. status%ok()) return
                call ts_end_par(state%engine, status=status)
                if (.not. status%ok()) return
            end do
        end if
        if (state%DATE > 0) then
            call ts_vskip(state%engine, ts_glue_t(state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
            call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=st%size, &
                              leading=14.0_dp*state%BASE/10.0_dp, skip=.false., status=status)
            if (.not. status%ok()) return
            call set_inlines(state, doc, state%DATE, st, status=status)
            if (.not. status%ok()) return
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
        end if
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
        call ts_vskip(state%engine, ts_glue_t(1.5_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
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
        if (state%ABSTRACT == 0) return
        heading_style = base_style(ctx)
        heading_style%size = 0.9_dp*state%BASE
        heading_style%bold = .true.
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status)
        if (.not. status%ok()) return
        call ts_begin_par(state%engine, ALIGN_CENTER, 0.0_dp, size=heading_style%size, &
                          leading=1.1_dp*state%BASE, skip=.false., status=status)
        if (.not. status%ok()) return
        call set_words(state, "Abstract", heading_style, status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status)
        if (.not. status%ok()) return
        call ts_vskip(state%engine, ts_glue_t(0.05_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status)
        if (.not. status%ok()) return
        sub = ctx
        sub%size = 0.9_dp*state%BASE
        sub%left = 2.5_dp*state%BASE
        sub%right = sub%left
        sub%align = ALIGN_JUSTIFY
        sub%indent = .true.
        saved_indent = state%PARINDENT
        saved_leading = state%LEAD
        state%PARINDENT = 1.5_dp*sub%size
        state%LEAD = 11.0_dp/9.0_dp
        call named_part(state, doc, part, sub, status)
        state%PARINDENT = saved_indent
        state%LEAD = saved_leading
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
                call ts_math(state%engine, strip_math_labels(doc%nodes(c)%text), ctx%size, ctx%color, &
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
        call defaults(nested, status=status)
        if (.not. status%ok()) return
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
        if (allocated(state%NODE_TARGET)) then
            allocate (nested%NODE_TARGET(size(state%NODE_TARGET)))
            nested%NODE_TARGET = state%NODE_TARGET
        end if
        sub = ctx
        sub%left = 0.0_dp
        sub%right = 0.0_dp
        sub%indent = .false.
        sub%align = ALIGN_CENTER
        sub%size = 0.9_dp*ctx%size
        call ts_set_page(nested%engine, width, 1.0e6_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false., status=status)
        if (.not. status%ok()) return
        call ts_set_font(nested%engine, sub%size, nested%LEAD*sub%size, status=status)
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
        state%EQNO = nested%EQNO
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
            gap = 0.5_dp*state%BASE
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
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        call ts_import_frame(state%engine, frame, handle, status=status)
        if (.not. status%ok()) return
        call ts_place_frame(state%engine, handle, left=ctx%left, right=ctx%right, &
                            align=ALIGN_CENTER, interline=.false., status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
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
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
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
            call ts_vskip(state%engine, ts_glue_t(0.4_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
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
        call ts_addvspace(state%engine, ts_glue_t(0.6_dp*state%BASE, 0.0_dp, 0.0_dp, 0, 0), status=status)
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
        if (ctx%indent .and. .not. state%NOINDENT .and. ctx%align == ALIGN_JUSTIFY) ind = state%PARINDENT
        state%NOINDENT = .false.
        call ts_begin_par(state%engine, ctx%align, ind, left=ctx%left, right=ctx%right, size=ctx%size, &
                          leading=state%LEAD*ctx%size, status=status)
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
        ex = face_xheight(FACE_REGULAR)*state%BASE
        call heading_number(state, doc%nodes(node)%num, lv, num)
        if (state%BOOK .and. lv == 0) then
            call chapter_heading(state, doc, node, text, ctx, status=status)
            if (.not. status%ok()) return
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
        call ts_addpenalty(state%engine, -300, status=status)
        if (.not. status%ok()) return
        call ts_addvspace(state%engine, before, status=status)
        if (.not. status%ok()) return
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
        if (state%NUMBER_SECTIONS) then
            call ts_mark(state%engine, upper("Chapter "//itoa(state%CHAPTER)//".  "//text), .true.)
        else
            call ts_mark(state%engine, upper(text), .true.)
        end if
        call ts_vkeep(state%engine, ts_glue_t(50.0_dp*state%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0), status=status)
        if (.not. status%ok()) return
        st = base_style(ctx)
        st%bold = .true.
        if (state%NUMBER_SECTIONS) then
            st%size = 2.074_dp*state%BASE
            call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, size=st%size, leading=25.0_dp*state%BASE/10.0_dp, &
                              skip=.false., nobreak=.true., status=status)
            if (.not. status%ok()) return
            call set_words(state, "Chapter "//itoa(state%CHAPTER), st, status=status)
            if (.not. status%ok()) return
            call ts_end_par(state%engine, status=status)
            if (.not. status%ok()) return
            call ts_penalty(state%engine, 10000)
            call ts_vskip(state%engine, ts_glue_t(20.0_dp*state%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0), status=status)
            if (.not. status%ok()) return
        end if
        st%size = 2.488_dp*state%BASE
        call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, size=st%size, leading=30.0_dp*state%BASE/10.0_dp, &
                          skip=.false., nobreak=.true., status=status)
        if (.not. status%ok()) return
        call set_inlines(state, doc, node, st, status=status)
        if (.not. status%ok()) return
        call ts_end_par(state%engine, status=status)
        if (.not. status%ok()) return
        call ts_penalty(state%engine, 10000)
        call ts_vskip(state%engine, ts_glue_t(40.0_dp*state%BASE/10.0_dp, 0.0_dp, 0.0_dp, 0, 0), status=status)
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
            state%LABEL_SEP = 0.5_dp*state%BASE
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
        call ts_set_parskip(state%engine, state%PARSKIP_G)
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
        sub%left = ctx%left + 2.5_dp*state%BASE
        sub%right = ctx%right + 2.5_dp*state%BASE
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
        call ts_set_parskip(state%engine, state%PARSKIP_G)
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
            call ts_begin_par(state%engine, ALIGN_LEFT, 0.0_dp, left=ctx%left + 1.5_dp*state%BASE, &
                              right=ctx%right, size=0.9_dp*ctx%size, leading=state%LEAD*ctx%size, status=status)
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
        call ts_set_parskip(state%engine, state%PARSKIP_G)
        call ts_addvspace(state%engine, scale(state, ts_glue_t(10.0_dp, 3.0_dp, 5.0_dp, 0, 0)), status=status)
        if (.not. status%ok()) return
    end subroutine code_block

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
        character(len=:), allocatable :: tag, reference
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
                        call ts_math(state%engine, strip_math_labels(nd%text), st%size, st%color, &
                                     display=.true., tag=tag, status=status)
                        if (.not. status%ok()) return
                        state%SPACE = .false.
                    else
                        call flush_space(state, status=status)
                        if (.not. status%ok()) return
                        call ts_math(state%engine, nd%text, st%size, st%color, status=status)
                        if (.not. status%ok()) return
                    end if
                case (IN_REF)
                    call flush(state, st, status)
                    if (.not. status%ok()) return
                    call reference_text(state, nd%id, nd%num, nd%text, reference, status)
                    if (.not. status%ok()) return
                    call reference_inline(state, reference, st, status)
                    if (.not. status%ok()) return
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
        if (lv > size(state%SEC)) return
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

    subroutine prepare_labels(state, doc, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        type(status_t), intent(out) :: status
        integer :: i, part
        state%NLAB = 0
        state%SEC = 0
        state%CHAPTER = 0
        state%EQNO = 0
        state%FIGURE_NO = 0
        state%TABLE_NO = 0
        if (allocated(state%NODE_TARGET)) deallocate (state%NODE_TARGET)
        allocate (state%NODE_TARGET(doc%n))
        state%NODE_TARGET = 0
        do i = 1, size(state%template%steps)
            part = state%template%steps(i)%part
            if (state%template%steps(i)%kind == STEP_BODY) then
                call collect_targets(state, doc, 1, status)
            else if (part > 0) then
                call collect_part_targets(state, doc, trim(state%template%parts(part)%name), status)
            end if
            if (.not. status%ok()) return
        end do
    end subroutine prepare_labels

    subroutine collect_part_targets(state, doc, name, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        character(len=*), intent(in) :: name
        type(status_t), intent(out) :: status
        integer, allocatable :: parts(:)
        integer :: i, node
        call part_nodes(doc, name, parts)
        do i = 1, size(parts)
            node = parts(i)
            if (len(doc%nodes(node)%id) > 0) then
                call add_target(state, node, DOC_PART, md_label(doc%nodes(node)%id), "", "", status)
                if (.not. status%ok()) return
            end if
            call collect_targets(state, doc, node, status)
            if (.not. status%ok()) return
        end do
    end subroutine collect_part_targets

    recursive subroutine collect_targets(state, doc, parent, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(status_t), intent(out) :: status
        integer :: node, kind, level, cap
        character(len=:), allocatable :: name, title, number
        node = doc%nodes(parent)%first
        do while (node > 0)
            kind = doc%nodes(node)%kind
            if (kind == DOC_PART) then
                node = doc%nodes(node)%next
                cycle
            end if
            name = md_label(doc%nodes(node)%id)
            title = ""
            number = ""
            select case (kind)
            case (DOC_HEADING)
                call heading_number(state, doc%nodes(node)%num, level, number)
                if (.not. state%NUMBER_SECTIONS) number = ""
                title = doc%nodes(node)%text
            case (DOC_MATH, IN_MATH)
                if (kind == DOC_MATH .or. doc%nodes(node)%display) then
                    kind = DOC_MATH
                    call math_target(state, doc%nodes(node), name, number, status)
                    if (.not. status%ok()) return
                end if
            case (DOC_FIGURE)
                if (state%NUMBER_FIGURES) then
                    state%FIGURE_NO = state%FIGURE_NO + 1
                    number = itoa(state%FIGURE_NO)
                end if
                cap = doc%nodes(node)%first
                if (cap > 0) cap = doc%nodes(cap)%next
                if (cap > 0) title = doc%nodes(cap)%text
            case (DOC_TABLE)
                if (state%NUMBER_TABLES) then
                    state%TABLE_NO = state%TABLE_NO + 1
                    number = itoa(state%TABLE_NO)
                end if
                cap = doc%nodes(node)%first
                if (cap > 0) title = doc%nodes(cap)%text
            end select
            if (kind /= IN_REF .and. (len(name) > 0 .or. kind == DOC_MATH .or. kind == DOC_HEADING .or. &
                                     kind == DOC_FIGURE .or. kind == DOC_TABLE)) then
                call add_target(state, node, kind, name, title, number, status)
                if (.not. status%ok()) return
            end if
            call collect_targets(state, doc, node, status)
            if (.not. status%ok()) return
            node = doc%nodes(node)%next
        end do
    end subroutine collect_targets

    subroutine math_target(state, node, name, number, status)
        type(layout_context_t), intent(inout) :: state
        type(doc_node_t), intent(in) :: node
        character(len=:), allocatable, intent(inout) :: name
        character(len=:), allocatable, intent(out) :: number
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: label
        integer :: a, b
        logical :: numbered
        number = ""
        a = index(node%text, BS//"label{")
        if (a > 0) then
            b = index(node%text(a:), "}")
            if (b < 8) then
                call status%set(ERROR_ARGUMENT, "MyST: malformed equation label")
                return
            end if
            label = md_label(node%text(a + 7:a + b - 2))
            if (len(name) > 0 .and. name /= label) then
                call status%set(ERROR_ARGUMENT, "MyST: conflicting equation labels")
                return
            end if
            name = label
            if (index(node%text(a + b:), BS//"label{") > 0) then
                call status%set(ERROR_UNSUPPORTED, "MyST: multiple labels on one equation are unsupported")
                return
            end if
        end if
        numbered = state%NUMBER_EQS
        if (node%enum_set) numbered = node%enumerated
        if (index(node%text, BS//"notag") > 0 .or. index(node%text, BS//"nonumber") > 0) numbered = .false.
        a = index(node%text, BS//"tag{")
        if (a > 0) then
            b = index(node%text(a:), "}")
            if (b < 6) then
                call status%set(ERROR_ARGUMENT, "MyST: malformed equation tag")
                return
            end if
            number = node%text(a + 5:a + b - 2)
        else if (numbered) then
            state%EQNO = state%EQNO + 1
            number = itoa(state%EQNO)
            if (state%BOOK .and. state%CHAPTER > 0) number = itoa(state%CHAPTER)//"."//number
        end if
    end subroutine math_target

    subroutine add_target(state, node, kind, name, title, number, status)
        type(layout_context_t), intent(inout) :: state
        integer, intent(in) :: node, kind
        character(len=*), intent(in) :: name, title, number
        type(status_t), intent(out) :: status
        type(label_t), allocatable :: grown(:)
        integer :: i
        call check_identifier(name, status)
        if (.not. status%ok()) return
        do i = 1, state%NLAB
            if (len(name) > 0 .and. state%label(i)%name == name) then
                call status%set(ERROR_LAYOUT, "MyST: duplicate target: "//name)
                return
            end if
        end do
        if (state%NLAB == size(state%label)) then
            allocate (grown(2*size(state%label)))
            grown(1:state%NLAB) = state%label(1:state%NLAB)
            call move_alloc(grown, state%label)
        end if
        state%NLAB = state%NLAB + 1
        i = state%NLAB
        state%label(i)%name = name
        state%label(i)%title = title
        state%label(i)%number = number
        state%label(i)%kind = kind
        state%NODE_TARGET(node) = i
    end subroutine add_target

    subroutine check_identifier(name, status)
        character(len=*), intent(in) :: name
        type(status_t), intent(out) :: status
        integer :: i
        do i = 1, len(name)
            if (iachar(name(i:i)) < 32 .or. iachar(name(i:i)) > 126) then
                call status%set(ERROR_UNSUPPORTED, "MyST: the native profile currently requires ASCII target identifiers")
                return
            end if
        end do
    end subroutine check_identifier

    function target_number(state, node) result(number)
        type(layout_context_t), intent(in) :: state
        integer, intent(in) :: node
        character(len=:), allocatable :: number
        integer :: target
        number = ""
        if (.not. allocated(state%NODE_TARGET)) return
        if (node < 1 .or. node > size(state%NODE_TARGET)) return
        target = state%NODE_TARGET(node)
        if (target > 0) number = state%label(target)%number
    end function target_number

    subroutine reference_text(state, id, form, custom, text, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: id, custom
        integer, intent(in) :: form
        character(len=:), allocatable, intent(out) :: text
        type(status_t), intent(out) :: status
        integer :: i
        character(len=:), allocatable :: title, number
        if (len(md_label(id)) == 0) then
            call status%set(ERROR_ARGUMENT, "MyST: empty reference target")
            return
        end if
        call check_identifier(md_label(id), status)
        if (.not. status%ok()) return
        i = find_label(state, md_label(id))
        if (i == 0) then
            call status%set(ERROR_LAYOUT, "MyST: unresolved target: "//id)
            return
        end if
        title = state%label(i)%title
        number = state%label(i)%number
        if (form == REF_EQ .and. state%label(i)%kind /= DOC_MATH) then
            call status%set(ERROR_ARGUMENT, "MyST: eq role requires an equation target")
            return
        end if
        if (len(custom) > 0) then
            text = custom
            if (len(number) == 0 .and. (index(text, "%s") > 0 .or. index(text, "{number}") > 0)) then
                call status%set(ERROR_LAYOUT, "MyST: target has no number: "//id)
                return
            end if
            if (len(title) == 0) title = id
            call replace_reference_fields(text, number, title)
        else if (form == REF_TITLE .and. len(title) > 0) then
            text = title
        else if (len(number) > 0) then
            select case (state%label(i)%kind)
            case (DOC_MATH); text = "("//number//")"
            case (DOC_FIGURE); text = "Figure "//number
            case (DOC_TABLE); text = "Table "//number
            case (DOC_HEADING); text = "Section "//number
            case default; text = number
            end select
        else if (state%label(i)%kind == DOC_MATH) then
            call status%set(ERROR_LAYOUT, "MyST: equation target is not numbered: "//id)
        else if (len(title) > 0) then
            text = title
        else
            text = id
        end if
    end subroutine reference_text

    subroutine replace_reference_fields(text, number, title)
        character(len=:), allocatable, intent(inout) :: text
        character(len=*), intent(in) :: number, title
        character(len=:), allocatable :: result
        integer :: i, count, j
        result = ""
        i = 1
        do while (i <= len(text))
            if (text(i:i) == "`") then
                count = 1
                do while (i + count <= len(text))
                    if (text(i + count:i + count) /= "`") exit
                    count = count + 1
                end do
                j = index(text(i + count:), repeat("`", count))
                if (j > 0) then
                    j = i + count + j - 1 + count
                    result = result//text(i:j - 1)
                    i = j
                    cycle
                end if
            end if
            if (starts(text(i:), "{number}")) then
                result = result//number
                i = i + 8
            else if (starts(text(i:), "{name}")) then
                result = result//title
                i = i + 6
            else if (starts(text(i:), "%s")) then
                result = result//number
                i = i + 2
            else
                result = result//text(i:i)
                i = i + 1
            end if
        end do
        text = result
    end subroutine replace_reference_fields

    recursive subroutine reference_inline(state, text, style, status)
        type(layout_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        type(style_t), intent(in) :: style
        type(status_t), intent(out) :: status
        type(doc_t) :: tree
        integer :: node
        if (state%REF_DEPTH >= 16) then
            call status%set(ERROR_LAYOUT, "MyST: cyclic reference display text")
            return
        end if
        call doc_init(tree, status)
        if (.not. status%ok()) return
        node = doc_add(tree, 1, DOC_PARA, status)
        if (.not. status%ok()) return
        call md_inlines(tree, node, text, status)
        if (.not. status%ok()) return
        state%REF_DEPTH = state%REF_DEPTH + 1
        call walk(state, tree, node, style, status)
        state%REF_DEPTH = state%REF_DEPTH - 1
    end subroutine reference_inline

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

end module fplotlib_docclass
