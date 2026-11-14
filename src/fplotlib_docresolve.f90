! Internal semantic preparation for the small report frontend. Layout receives
! typed settings and an owned, resolved tree, never raw metadata or MyST input.
module fplotlib_docresolve
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_doctree
    use fplotlib_doctemplate
    use fplotlib_myst_inline, only: md_label, md_plain
    use fplotlib_myst_metadata, only: decimal_number, author_name_key
    use fplotlib_colors, only: color_from_name
    use fplotlib_glyphs, only: FACE_REGULAR, face_xheight
    use fplotlib_resources, only: initialize_resources
    use fplotlib_render_checks, only: check_finite
    use fplotlib_typeset, only: ALIGN_JUSTIFY, ALIGN_LEFT, ALIGN_CENTER, ALIGN_RIGHT
    implicit none
    private
    public :: document_settings_t, resolved_document_t, resolved_node_t, resolved_part_t, resolve_document

    character, parameter :: BS = achar(92), NL = achar(10)

    type, extends(document_style_t) :: document_settings_t
        logical :: NUMBER_SECTIONS = .false., NUMBER_EQS = .true.
        logical :: NUMBER_FIGURES = .true., NUMBER_TABLES = .true.
        integer :: TITLE = 0, SUBTITLE = 0, DATE = 0, ABSTRACT = 0, NAUTHOR = 0
        integer, allocatable :: AUTHORS(:)
    end type document_settings_t

    type :: resolved_node_t
        character(len=:), allocatable :: number
        integer :: level = 0, chapter = 0
    end type resolved_node_t

    type :: resolved_part_t
        integer, allocatable :: nodes(:)
    end type resolved_part_t

    type :: resolved_document_t
        type(doc_t) :: content
        type(document_settings_t) :: settings
        type(template_t) :: template
        type(resolved_node_t), allocatable :: nodes(:)
        type(resolved_part_t), allocatable :: parts(:)
    end type resolved_document_t

    type :: label_t
        character(len=:), allocatable :: name, number
        integer :: kind = 0, node = 0
    end type label_t

    type :: resolve_context_t
        type(document_settings_t) :: settings
        type(template_t) :: template
        integer :: SEC(6) = 0, CHAPTER = 0, EQNO = 0, FIGURE_NO = 0, TABLE_NO = 0, NLAB = 0
        type(label_t), allocatable :: label(:)
        integer, allocatable :: NODE_TARGET(:)
        type(resolved_node_t), allocatable :: nodes(:)
        logical, allocatable :: visiting(:), prepared(:)
    end type resolve_context_t

contains

    subroutine resolve_document(source, resolved, status)
        type(doc_t), intent(in) :: source
        type(resolved_document_t), intent(out) :: resolved
        type(status_t), intent(out) :: status
        type(resolve_context_t) :: state
        integer :: i, j, part
        call doc_validate(source, status)
        if (.not. status%ok()) return
        call initialize_resources(status)
        if (.not. status%ok()) return
        allocate (state%settings%AUTHORS(16), state%label(16), state%nodes(source%n), state%prepared(source%n))
        state%settings%AUTHORS = 0
        state%prepared = .false.
        do i = 1, source%n
            state%nodes(i)%number = ""
        end do
        call settings(state, source, status)
        if (.not. status%ok()) return
        call validate_parts(state, source, status)
        if (.not. status%ok()) return
        call prepare_labels(state, source, status)
        if (.not. status%ok()) return
        allocate (state%visiting(state%NLAB))
        state%visiting = .false.
        do i = 1, state%NLAB
            state%nodes(state%label(i)%node)%number = state%label(i)%number
        end do
        resolved%content = source
        resolved%settings = state%settings
        resolved%template = state%template
        allocate (resolved%nodes(size(source%nodes)), resolved%parts(size(state%template%parts)))
        resolved%nodes(1:source%n) = state%nodes
        do i = 1, size(resolved%parts)
            call part_nodes(source, trim(state%template%parts(i)%name), resolved%parts(i)%nodes)
        end do
        do i = 1, size(state%template%steps)
            part = state%template%steps(i)%part
            select case (state%template%steps(i)%kind)
            case (STEP_BODY)
                call resolve_node(state, source, 1, resolved, status, 0)
            case (STEP_TITLE_BLOCK)
                if (state%settings%TITLE > 0) then
                    call resolve_node(state, source, state%settings%TITLE, resolved, status, 0)
                    if (.not. status%ok()) return
                    call resolve_node(state, source, state%settings%SUBTITLE, resolved, status, 0)
                    if (.not. status%ok()) return
                    call resolve_node(state, source, state%settings%DATE, resolved, status, 0)
                    if (.not. status%ok()) return
                    do j = 1, state%settings%NAUTHOR
                        call resolve_node(state, source, state%settings%AUTHORS(j), resolved, status, 0)
                        if (.not. status%ok()) return
                    end do
                end if
            case (STEP_TITLE)
                call resolve_node(state, source, state%settings%TITLE, resolved, status, 0)
            end select
            if (.not. status%ok()) return
            if (part > 0) then
                do j = 1, size(resolved%parts(part)%nodes)
                    call resolve_node(state, source, resolved%parts(part)%nodes(j), resolved, status, 0)
                    if (.not. status%ok()) return
                end do
            end if
        end do
        ! Inactive source parts and detached parser nodes are not layout input.
        ! Keep their arena slots stable, but do not retain unresolved references.
        do i = 1, resolved%content%n
            if (resolved%content%nodes(i)%kind /= IN_REF) cycle
            resolved%content%nodes(i)%kind = DOC_INLINES
            resolved%content%nodes(i)%first = 0
            resolved%content%nodes(i)%last = 0
            resolved%content%nodes(i)%text = ""
        end do
        resolved%content%nmeta = 0
        call doc_validate(resolved%content, status)
    end subroutine resolve_document

    recursive subroutine resolve_node(state, source, node, output, status, depth)
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: source
        integer, intent(in) :: node, depth
        type(resolved_document_t), intent(inout) :: output
        type(status_t), intent(out) :: status
        integer :: child, kind
        if (node == 0) return
        if (state%prepared(node)) return
        state%prepared(node) = .true.
        kind = source%nodes(node)%kind
        if (kind == IN_REF) then
            call resolve_reference(state, source, node, output, node, status, depth)
            return
        end if
        if (kind == DOC_MATH .or. (kind == IN_MATH .and. source%nodes(node)%display)) &
            output%content%nodes(node)%text = strip_math_labels(source%nodes(node)%text)
        child = source%nodes(node)%first
        do while (child > 0)
            if (kind /= DOC_ROOT .or. source%nodes(child)%kind /= DOC_PART) then
                call resolve_node(state, source, child, output, status, depth + 1)
                if (.not. status%ok()) return
            end if
            child = source%nodes(child)%next
        end do
    end subroutine resolve_node

    subroutine ensure_node_info(output, first)
        type(resolved_document_t), intent(inout) :: output
        integer, intent(in) :: first
        type(resolved_node_t), allocatable :: grown(:)
        integer :: i
        if (size(output%nodes) < size(output%content%nodes)) then
            allocate (grown(size(output%content%nodes)))
            grown(1:first - 1) = output%nodes(1:first - 1)
            call move_alloc(grown, output%nodes)
        end if
        do i = first, output%content%n
            output%nodes(i)%number = ""
        end do
    end subroutine ensure_node_info

    subroutine append_text(output, parent, text, status)
        type(resolved_document_t), intent(inout) :: output
        integer, intent(in) :: parent
        character(len=*), intent(in) :: text
        type(status_t), intent(out) :: status
        integer :: first
        first = output%content%n + 1
        call md_plain(output%content, parent, text, status)
        if (.not. status%ok()) return
        call ensure_node_info(output, first)
    end subroutine append_text

    recursive subroutine clone_inline(state, source, node, output, parent, status, depth, fields)
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: source
        integer, intent(in) :: node, parent, depth
        type(resolved_document_t), intent(inout) :: output
        type(status_t), intent(out) :: status
        integer, intent(in), optional :: fields
        integer :: added, child
        if (depth > 100) then
            call status%set(ERROR_LAYOUT, "MyST: resolved inline nesting exceeds the native profile")
            return
        end if
        if (present(fields)) then
            if (source%nodes(node)%kind == IN_STR) then
                call append_fields(state, source, source%nodes(node)%text, fields, output, parent, status, depth)
                return
            end if
        end if
        added = doc_add(output%content, parent, source%nodes(node)%kind, status)
        if (.not. status%ok()) return
        call ensure_node_info(output, added)
        output%nodes(added) = state%nodes(node)
        output%content%nodes(added) = source%nodes(node)
        output%content%nodes(added)%first = 0
        output%content%nodes(added)%last = 0
        output%content%nodes(added)%next = 0
        if (source%nodes(node)%kind == IN_REF) then
            call resolve_reference(state, source, node, output, added, status, depth)
            return
        end if
        if (source%nodes(node)%kind == DOC_MATH .or. &
            (source%nodes(node)%kind == IN_MATH .and. source%nodes(node)%display)) &
            output%content%nodes(added)%text = strip_math_labels(source%nodes(node)%text)
        child = source%nodes(node)%first
        do while (child > 0)
            call clone_inline(state, source, child, output, added, status, depth + 1, fields)
            if (.not. status%ok()) return
            child = source%nodes(child)%next
        end do
    end subroutine clone_inline

    recursive subroutine resolve_reference(state, source, reference, output, node, status, depth)
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: source
        integer, intent(in) :: reference, node, depth
        type(resolved_document_t), intent(inout) :: output
        type(status_t), intent(out) :: status
        integer :: target, child, title_node, form
        character(len=:), allocatable :: id, text, number
        id = md_label(source%nodes(reference)%id)
        if (len(id) == 0) then
            call status%set(ERROR_ARGUMENT, "MyST: empty reference target")
            return
        end if
        call check_identifier(id, status)
        if (.not. status%ok()) return
        target = find_label(state, id)
        if (target == 0) then
            call status%set(ERROR_LAYOUT, "MyST: unresolved target: "//id)
            return
        end if
        form = source%nodes(reference)%num
        if (form == REF_EQ .and. state%label(target)%kind /= DOC_MATH) then
            call status%set(ERROR_ARGUMENT, "MyST: eq role requires an equation target")
            return
        end if
        output%content%nodes(node)%kind = DOC_INLINES
        output%content%nodes(node)%first = 0
        output%content%nodes(node)%last = 0
        output%content%nodes(node)%text = ""
        child = source%nodes(reference)%first
        if (child > 0) then
            do while (child > 0)
                call clone_inline(state, source, child, output, node, status, depth + 1, target)
                if (.not. status%ok()) return
                child = source%nodes(child)%next
            end do
            return
        else if (len(source%nodes(reference)%text) > 0) then
            ! Programmatic trees supply literal display text or parsed children.
            call append_fields(state, source, source%nodes(reference)%text, target, output, node, status, depth)
            return
        end if
        title_node = target_title(source, state%label(target))
        number = state%label(target)%number
        if (title_node > 0 .and. (form == REF_TITLE .or. len(number) == 0)) then
            call append_title(state, source, target, output, node, status, depth)
            return
        else if (len(number) > 0) then
            select case (state%label(target)%kind)
            case (DOC_MATH); text = "("//number//")"
            case (DOC_FIGURE); text = "Figure "//number
            case (DOC_TABLE); text = "Table "//number
            case (DOC_HEADING); text = "Section "//number
            case default; text = number
            end select
        else if (state%label(target)%kind == DOC_MATH) then
            call status%set(ERROR_LAYOUT, "MyST: equation target is not numbered: "//id)
            return
        else
            text = id
        end if
        call append_text(output, node, text, status)
    end subroutine resolve_reference

    integer function target_title(source, target) result(node)
        type(doc_t), intent(in) :: source
        type(label_t), intent(in) :: target
        node = 0
        select case (target%kind)
        case (DOC_HEADING)
            node = target%node
        case (DOC_FIGURE)
            node = source%nodes(target%node)%first
            if (node > 0) node = source%nodes(node)%next
        case (DOC_TABLE)
            node = source%nodes(target%node)%first
        end select
        if (node > 0) then
            if (source%nodes(node)%first == 0) node = 0
        end if
    end function target_title

    recursive subroutine append_title(state, source, target, output, parent, status, depth)
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: source
        integer, intent(in) :: target, parent, depth
        type(resolved_document_t), intent(inout) :: output
        type(status_t), intent(out) :: status
        integer :: node
        node = target_title(source, state%label(target))
        if (node == 0) then
            call append_text(output, parent, state%label(target)%name, status)
            return
        end if
        if (state%visiting(target)) then
            call status%set(ERROR_LAYOUT, "MyST: cyclic reference display text")
            return
        end if
        state%visiting(target) = .true.
        call title_children(state, source, node, output, parent, status, depth + 1)
        state%visiting(target) = .false.
    end subroutine append_title

    recursive subroutine title_children(state, source, node, output, parent, status, depth)
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: source
        integer, intent(in) :: node, parent, depth
        type(resolved_document_t), intent(inout) :: output
        type(status_t), intent(out) :: status
        integer :: child, added, i
        character(len=:), allocatable :: text
        if (depth > 100) then
            call status%set(ERROR_LAYOUT, "MyST: reference title nesting exceeds the native profile")
            return
        end if
        child = source%nodes(node)%first
        do while (child > 0)
            select case (source%nodes(child)%kind)
            case (DOC_PARA, DOC_HEADING, DOC_DIV, DOC_PART, DOC_LIST, DOC_ITEM, DOC_QUOTE)
                if (output%content%nodes(parent)%first > 0) call append_text(output, parent, " ", status)
                if (.not. status%ok()) return
                call title_children(state, source, child, output, parent, status, depth + 1)
            case (DOC_CODE)
                text = source%nodes(child)%text
                do i = 1, len(text)
                    if (text(i:i) == NL) text(i:i) = " "
                end do
                added = doc_add_text(output%content, parent, IN_CODE, trim(text), status)
                if (.not. status%ok()) return
                call ensure_node_info(output, added)
            case (DOC_MATH)
                added = doc_add_text(output%content, parent, IN_MATH, &
                                     strip_math_labels(source%nodes(child)%text), status)
                if (.not. status%ok()) return
                call ensure_node_info(output, added)
                output%content%nodes(added)%display = .true.
                output%nodes(added) = state%nodes(child)
            case default
                call clone_inline(state, source, child, output, parent, status, depth + 1)
            end select
            if (.not. status%ok()) return
            child = source%nodes(child)%next
        end do
    end subroutine title_children

    recursive subroutine append_fields(state, source, text, target, output, parent, status, depth)
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: source
        character(len=*), intent(in) :: text
        integer, intent(in) :: target, parent, depth
        type(resolved_document_t), intent(inout) :: output
        type(status_t), intent(out) :: status
        integer :: i, first, length
        logical :: title
        i = 1
        first = 1
        do while (i <= len(text))
            length = 0
            title = .false.
            if (starts(text(i:), "{number}")) length = 8
            if (starts(text(i:), "%s")) length = 2
            if (starts(text(i:), "{name}")) then
                length = 6
                title = .true.
            end if
            if (length == 0) then
                i = i + 1
                cycle
            end if
            call append_text(output, parent, text(first:i - 1), status)
            if (.not. status%ok()) return
            if (title) then
                call append_title(state, source, target, output, parent, status, depth + 1)
            else
                if (len(state%label(target)%number) == 0) then
                    call status%set(ERROR_LAYOUT, "MyST: target has no number: "//state%label(target)%name)
                    return
                end if
                call append_text(output, parent, state%label(target)%number, status)
            end if
            if (.not. status%ok()) return
            i = i + length
            first = i
        end do
        call append_text(output, parent, text(first:), status)
    end subroutine append_fields

    pure logical function starts(s, p)
        character(len=*), intent(in) :: s, p
        starts = .false.
        if (len(s) >= len(p)) starts = s(1:len(p)) == p
    end function starts

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: buffer
        write (buffer, "(i0)") i
        s = trim(buffer)
    end function itoa

    subroutine settings(state, doc, status)
        type(resolve_context_t), intent(inout) :: state
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
        state%settings%document_style_t = state%template%body
        pw = state%template%body%page_width
        ph = state%template%body%page_height
        margins = state%template%body%margins
        numbers = state%template%body%page_numbers
        ! Mapping order does not affect relative lengths.
        do i = 1, doc%nmeta
            if (doc%meta(i)%key /= "exports.1.fontsize") cycle
            call read_length(doc%meta(i)%value, state%settings%BASE, m, status)
            if (.not. status%ok()) return
            if (m <= 0.0_dp) then
                call status%set(ERROR_ARGUMENT, "MyST: fontsize must be positive")
                return
            end if
            state%settings%BASE = m
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
                    call read_length(val, state%settings%BASE, m, status)
                case ("margin-left", "margin-right", "margin-top", "margin-bottom")
                    j = 1
                    if (key == "margin-right") j = 2
                    if (key == "margin-top") j = 3
                    if (key == "margin-bottom") j = 4
                    call read_length(val, state%settings%BASE, margins(j), status)
                    have_margin(j) = .true.
                case ("parskip")
                    call read_length(val, state%settings%BASE, state%settings%PARSKIP_G%w, status)
                    state%settings%PARSKIP_G%st = 0.2_dp*state%settings%PARSKIP_G%w
                    have_parskip = .true.
                case ("indent")
                    have_indent = .true.
                    if (doc%meta(i)%kind == META_BOOL) then
                        state%settings%PARINDENT = merge(1.5_dp*state%settings%BASE, 0.0_dp, val == "true")
                    else
                        call read_length(val, state%settings%BASE, state%settings%PARINDENT, status)
                    end if
                case ("linestretch")
                    if (.not. decimal_number(val)) then
                        call status%set(ERROR_ARGUMENT, "MyST: linestretch must be a number")
                        return
                    end if
                    read (val, *, iostat=j) state%settings%LEAD
                    if (j /= 0) then
                        call status%set(ERROR_ARGUMENT, "MyST: linestretch must be a number")
                        return
                    end if
                    call check_finite([state%settings%LEAD], status)
                    if (.not. status%ok()) return
                    if (state%settings%LEAD <= 0.0_dp) then
                        call status%set(ERROR_ARGUMENT, "MyST: linestretch must be positive")
                        return
                    end if
                    state%settings%LEAD = 1.2_dp*state%settings%LEAD
                case ("align")
                    select case (val)
                    case ("left"); state%settings%DOC_ALIGN = ALIGN_LEFT
                    case ("right"); state%settings%DOC_ALIGN = ALIGN_RIGHT
                    case ("center"); state%settings%DOC_ALIGN = ALIGN_CENTER
                    case ("justify"); state%settings%DOC_ALIGN = ALIGN_JUSTIFY
                    case default
                        call status%set(ERROR_ARGUMENT, "MyST: invalid template alignment")
                        return
                    end select
                case ("pagenumbers")
                    call metadata_boolean(doc%meta(i), numbers, status)
                case ("color")
                    call native_color(val, state%settings%TEXT_COL, status)
                case ("pagecolor")
                    call native_color(val, state%settings%PAGE_COL, status)
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
                state%settings%TITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("subtitle")
                state%settings%SUBTITLE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("date")
                state%settings%DATE = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("abstract")
                state%settings%ABSTRACT = merge(doc%meta(i)%node, 0, len(val) > 0)
            case ("numbering")
                if (doc%meta(i)%kind == META_MAP) cycle
                call metadata_boolean(doc%meta(i), flag, status)
                if (.not. status%ok()) return
                state%settings%NUMBER_SECTIONS = flag
                state%settings%NUMBER_EQS = flag
                state%settings%NUMBER_FIGURES = flag
                state%settings%NUMBER_TABLES = flag
            case ("numbering.headings", "numbering.equations", "numbering.figures", "numbering.tables")
                call metadata_boolean(doc%meta(i), flag, status)
                if (.not. status%ok()) return
                select case (key)
                case ("numbering.headings"); state%settings%NUMBER_SECTIONS = flag
                case ("numbering.equations"); state%settings%NUMBER_EQS = flag
                case ("numbering.figures"); state%settings%NUMBER_FIGURES = flag
                case ("numbering.tables"); state%settings%NUMBER_TABLES = flag
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
                        if (state%settings%NAUTHOR == size(state%settings%AUTHORS)) then
                            allocate (grown(2*size(state%settings%AUTHORS)))
                            grown(1:state%settings%NAUTHOR) = state%settings%AUTHORS(1:state%settings%NAUTHOR)
                            call move_alloc(grown, state%settings%AUTHORS)
                        end if
                        state%settings%NAUTHOR = state%settings%NAUTHOR + 1
                        state%settings%AUTHORS(state%settings%NAUTHOR) = doc%meta(i)%node
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
        if (have_parskip .and. .not. have_indent) state%settings%PARINDENT = 0.0_dp
        if (state%settings%PARINDENT < 0.0_dp) state%settings%PARINDENT = 1.5_dp*state%settings%BASE
        if (m >= 0.0_dp) then
            do j = 1, 4
                if (.not. have_margin(j)) margins(j) = m
            end do
        end if
        state%settings%page_width = pw
        state%settings%page_height = ph
        state%settings%margins = margins
        state%settings%page_numbers = numbers
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
        type(resolve_context_t), intent(inout) :: state
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
        state%settings%ABSTRACT = 0
        do i = 1, size(state%template%steps)
            if (state%template%steps(i)%kind /= STEP_TITLE_BLOCK) cycle
            part = state%template%steps(i)%part
            call part_nodes(doc, trim(state%template%parts(part)%name), nodes)
            if (size(nodes) > 0) state%settings%ABSTRACT = nodes(1)
        end do
    end subroutine validate_parts

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

    subroutine heading_number(state, level, lv, num)
        type(resolve_context_t), intent(inout) :: state
        integer, intent(in) :: level
        integer, intent(out) :: lv
        character(len=:), allocatable, intent(out) :: num
        integer :: k
        lv = level
        if (state%settings%BOOK) lv = level - 1
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
        if (state%settings%BOOK) then
            num = itoa(state%CHAPTER)
        else
            num = itoa(state%SEC(1))
        end if
        do k = merge(1, 2, state%settings%BOOK), lv
            num = num//"."//itoa(state%SEC(k))
        end do
    end subroutine heading_number

    subroutine prepare_labels(state, doc, status)
        type(resolve_context_t), intent(inout) :: state
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
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        character(len=*), intent(in) :: name
        type(status_t), intent(out) :: status
        integer, allocatable :: parts(:)
        integer :: i, node
        call part_nodes(doc, name, parts)
        do i = 1, size(parts)
            node = parts(i)
            if (len(doc%nodes(node)%id) > 0) then
                call add_target(state, node, DOC_PART, md_label(doc%nodes(node)%id), "", status)
                if (.not. status%ok()) return
            end if
            call collect_targets(state, doc, node, status)
            if (.not. status%ok()) return
        end do
    end subroutine collect_part_targets

    recursive subroutine collect_targets(state, doc, parent, status)
        type(resolve_context_t), intent(inout) :: state
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(status_t), intent(out) :: status
        integer :: node, kind, level
        character(len=:), allocatable :: name, number
        node = doc%nodes(parent)%first
        do while (node > 0)
            kind = doc%nodes(node)%kind
            if (kind == DOC_PART) then
                node = doc%nodes(node)%next
                cycle
            end if
            name = md_label(doc%nodes(node)%id)
            number = ""
            select case (kind)
            case (DOC_HEADING)
                call heading_number(state, doc%nodes(node)%num, level, number)
                state%nodes(node)%level = level
                state%nodes(node)%chapter = state%CHAPTER
                if (.not. state%settings%NUMBER_SECTIONS) number = ""
            case (DOC_MATH, IN_MATH)
                if (kind == DOC_MATH .or. doc%nodes(node)%display) then
                    kind = DOC_MATH
                    call math_target(state, doc%nodes(node), name, number, status)
                    if (.not. status%ok()) return
                end if
            case (DOC_FIGURE)
                if (state%settings%NUMBER_FIGURES) then
                    state%FIGURE_NO = state%FIGURE_NO + 1
                    number = itoa(state%FIGURE_NO)
                end if
            case (DOC_TABLE)
                if (state%settings%NUMBER_TABLES) then
                    state%TABLE_NO = state%TABLE_NO + 1
                    number = itoa(state%TABLE_NO)
                end if
            end select
            if (kind /= IN_REF .and. (len(name) > 0 .or. kind == DOC_MATH .or. kind == DOC_HEADING .or. &
                                     kind == DOC_FIGURE .or. kind == DOC_TABLE)) then
                call add_target(state, node, kind, name, number, status)
                if (.not. status%ok()) return
            end if
            call collect_targets(state, doc, node, status)
            if (.not. status%ok()) return
            node = doc%nodes(node)%next
        end do
    end subroutine collect_targets

    subroutine math_target(state, node, name, number, status)
        type(resolve_context_t), intent(inout) :: state
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
        numbered = state%settings%NUMBER_EQS
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
            if (state%settings%BOOK .and. state%CHAPTER > 0) number = itoa(state%CHAPTER)//"."//number
        end if
    end subroutine math_target

    subroutine add_target(state, node, kind, name, number, status)
        type(resolve_context_t), intent(inout) :: state
        integer, intent(in) :: node, kind
        character(len=*), intent(in) :: name, number
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
        state%label(i)%number = number
        state%label(i)%kind = kind
        state%label(i)%node = node
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

    integer function find_label(state, name)
        type(resolve_context_t), intent(in) :: state
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

end module fplotlib_docresolve
