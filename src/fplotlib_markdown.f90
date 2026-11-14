! Native MyST subset: CommonMark structure, math, targets/references, document
! parts and print templates. No raw TeX document commands or Pandoc attributes.
module fplotlib_markdown
    use fplotlib_status
    use fplotlib_doctree
    use fplotlib_myst_metadata
    use fplotlib_myst_inline
    implicit none
    private
    public :: md_parse, md_append
    character, parameter :: NL = achar(10), BS = achar(92)

contains

    subroutine md_parse(text, doc, status)
        character(len=*), intent(in) :: text
        type(doc_t), intent(out) :: doc
        type(status_t), intent(out) :: status
        type(md_line_t), allocatable :: lines(:), part_lines(:)
        integer :: first, last, i, k, nm
        character(len=:), allocatable :: key
        call doc_init(doc, status)
        if (.not. status%ok()) return
        call md_split_lines(text, lines)
        first = 1
        if (size(lines) > 0) then
            if (trim(lines(1)%text) == "---") then
                last = 2
                do while (last <= size(lines))
                    if (trim(lines(last)%text) == "---" .or. trim(lines(last)%text) == "...") exit
                    last = last + 1
                end do
                if (last <= size(lines)) then
                    call read_frontmatter(lines(2:last - 1), doc, status)
                    if (.not. status%ok()) return
                    first = last + 1
                end if
            end if
        end if
        nm = doc%nmeta
        do i = 1, nm
            if (doc%meta(i)%kind /= META_STRING) cycle
            key = doc%meta(i)%key
            if (key == "title" .or. key == "subtitle" .or. key == "date" .or. &
                key == "authors" .or. starts(key, "authors.")) then
                if (starts(key, "authors.")) then
                    if (.not. author_name_key(key)) cycle
                end if
                k = doc_add(doc, 0, DOC_INLINES, status)
                if (.not. status%ok()) return
                call md_inlines(doc, k, doc%meta(i)%value, status)
                if (.not. status%ok()) return
                doc%meta(i)%node = k
            else if (key == "abstract" .or. starts(key, "parts.")) then
                k = doc_add(doc, 0, DOC_PART, status)
                if (.not. status%ok()) return
                doc%nodes(k)%part = key
                if (starts(key, "parts.")) doc%nodes(k)%part = key(7:)
                call md_split_lines(doc%meta(i)%value, part_lines)
                call blocks(doc, k, part_lines, 1, size(part_lines), 0, status)
                if (.not. status%ok()) return
                doc%meta(i)%node = k
            end if
        end do
        call blocks(doc, 1, lines, first, size(lines), 0, status)
    end subroutine md_parse

    ! Appending is transactional: a syntax error cannot leave an old report's
    ! cached pages paired with partially appended content.
    subroutine md_append(text, doc, parent, status)
        character(len=*), intent(in) :: text
        type(doc_t), intent(inout) :: doc
        integer, intent(in), optional :: parent
        type(status_t), intent(out) :: status
        type(md_line_t), allocatable :: lines(:)
        integer :: p, old_n, old_tables, old_first, old_last, old_next, i
        p = 1
        if (present(parent)) p = parent
        if (p < 1 .or. p > doc%n .or. .not. allocated(doc%nodes)) then
            call status%set(ERROR_ARGUMENT, "md_append: invalid parent")
            return
        end if
        old_n = doc%n
        call doc_validate(doc, status)
        if (.not. status%ok()) return
        old_tables = doc%ntables
        old_first = doc%nodes(p)%first
        old_last = doc%nodes(p)%last
        old_next = 0
        if (old_last > 0) old_next = doc%nodes(old_last)%next
        call md_split_lines(text, lines)
        call blocks(doc, p, lines, 1, size(lines), 0, status)
        if (status%ok()) return
        do i = old_n + 1, doc%n
            doc%nodes(i) = doc_node_t()
        end do
        do i = old_tables + 1, doc%ntables
            doc%tables(i) = doc_table_t()
        end do
        doc%n = old_n
        doc%ntables = old_tables
        doc%nodes(p)%first = old_first
        doc%nodes(p)%last = old_last
        if (old_last > 0) doc%nodes(old_last)%next = old_next
    end subroutine md_append

    pure logical function starts(text, prefix)
        character(len=*), intent(in) :: text, prefix
        starts = .false.
        if (len(text) >= len(prefix)) starts = text(1:len(prefix)) == prefix
    end function starts

    pure logical function ends(text, suffix)
        character(len=*), intent(in) :: text, suffix
        ends = .false.
        if (len(text) >= len(suffix)) ends = text(len(text) - len(suffix) + 1:) == suffix
    end function ends

    function left_trim(text) result(value)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: value
        integer :: i
        i = 1
        do while (i <= len(text))
            if (text(i:i) /= " " .and. text(i:i) /= achar(9)) exit
            i = i + 1
        end do
        value = text(i:)
    end function left_trim

    function deindent(text, columns) result(value)
        character(len=*), intent(in) :: text
        integer, intent(in) :: columns
        character(len=:), allocatable :: value
        integer :: i, n
        i = 1
        n = 0
        do while (i <= len(text) .and. n < columns)
            if (text(i:i) == " ") then
                n = n + 1
            else if (text(i:i) == achar(9)) then
                n = n + 4 - mod(n, 4)
            else
                exit
            end if
            i = i + 1
        end do
        value = repeat(" ", max(0, n - columns))//text(i:)
    end function deindent

    logical function empty(text)
        character(len=*), intent(in) :: text
        empty = len_trim(left_trim(text)) == 0
    end function empty

    integer function heading_level(text) result(level)
        character(len=*), intent(in) :: text
        integer :: i
        level = 0
        do i = 1, len(text)
            if (text(i:i) /= "#") exit
            level = level + 1
        end do
        if (level > 6) level = 0
        if (level > 0 .and. level < len(text)) then
            if (text(level + 1:level + 1) /= " " .and. text(level + 1:level + 1) /= achar(9)) level = 0
        end if
    end function heading_level

    function heading_text(text, level) result(value)
        character(len=*), intent(in) :: text
        integer, intent(in) :: level
        character(len=:), allocatable :: value
        integer :: i
        value = trim(left_trim(text(level + 1:)))
        i = len(value)
        do while (i > 0)
            if (value(i:i) /= "#") exit
            i = i - 1
        end do
        if (i == 0) then
            value = ""
        else if (i < len(value)) then
            if (value(i:i) == " " .or. value(i:i) == achar(9)) value = trim(value(1:i))
        end if
    end function heading_text

    logical function rule(text)
        character(len=*), intent(in) :: text
        integer :: i, n
        character :: marker
        rule = .false.
        if (len(text) == 0) return
        marker = text(1:1)
        if (scan(marker, "*-_") == 0) return
        n = 0
        do i = 1, len(text)
            if (text(i:i) == marker) then
                n = n + 1
            else if (text(i:i) /= " " .and. text(i:i) /= achar(9)) then
                return
            end if
        end do
        rule = n >= 3
    end function rule

    integer function underline(text) result(level)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: t
        level = 0
        t = trim(text)
        if (len(t) == 0) return
        if (verify(t, "=") == 0) level = 1
        if (verify(t, "-") == 0) level = 2
    end function underline

    subroutine fence(text, marker, count, info)
        character(len=*), intent(in) :: text
        character, intent(out) :: marker
        integer, intent(out) :: count
        character(len=:), allocatable, intent(out) :: info
        integer :: i
        marker = " "
        count = 0
        info = ""
        if (md_indent(text) > 3) return
        info = left_trim(text)
        if (len(info) == 0) return
        marker = info(1:1)
        if (marker /= "`" .and. marker /= "~" .and. marker /= ":") then
            marker = " "
            info = ""
            return
        end if
        do i = 1, len(info)
            if (info(i:i) /= marker) exit
            count = count + 1
        end do
        info = trim(left_trim(info(count + 1:)))
        if (count < 3 .or. (marker == "`" .and. index(info, "`") > 0)) then
            count = 0
            marker = " "
        end if
    end subroutine fence

    integer function fence_end(lines, first, last, marker, count) result(j)
        type(md_line_t), intent(in) :: lines(:)
        integer, intent(in) :: first, last, count
        character, intent(in) :: marker
        character :: c
        integer :: n
        character(len=:), allocatable :: info
        j = first
        do while (j <= last)
            call fence(lines(j)%text, c, n, info)
            if (c == marker .and. n >= count .and. len(info) == 0) return
            j = j + 1
        end do
    end function fence_end

    logical function block_break(text, metadata)
        character(len=*), intent(in) :: text
        integer, intent(out), optional :: metadata
        character(len=:), allocatable :: t
        integer :: i, n
        t = trim(left_trim(text))
        block_break = .false.
        if (present(metadata)) metadata = 1
        if (md_indent(text) > 3 .or. len(t) < 3) return
        if (t(1:1) /= "+") return
        n = 0
        i = 1
        do while (i <= len(t))
            if (t(i:i) == "+") then
                n = n + 1
            else if (t(i:i) /= " " .and. t(i:i) /= achar(9)) then
                exit
            end if
            i = i + 1
        end do
        if (present(metadata)) metadata = i
        block_break = n >= 3
    end function block_break

    logical function target_line(text, label)
        character(len=*), intent(in) :: text
        character(len=:), allocatable, intent(out) :: label
        character(len=:), allocatable :: t
        t = trim(left_trim(text))
        target_line = .false.
        label = ""
        if (md_indent(text) > 3 .or. len(t) < 4) return
        if (t(1:1) /= "(" .or. .not. ends(t, ")=")) return
        if (len(t) - 3 > 100) return
        if (verify(t(2:len(t) - 2), "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789|@<>*./_-+:") /= 0) return
        label = md_label(t(2:len(t) - 2))
        target_line = len(label) > 0
    end function target_line

    logical function item_marker(text, number, kind, content, marker, body)
        character(len=*), intent(in) :: text
        integer, intent(out) :: number, kind, content
        character, intent(out) :: marker
        character(len=:), allocatable, intent(out), optional :: body
        character(len=:), allocatable :: t
        integer :: i, j, spaces, used, ios
        item_marker = .false.
        number = 1
        kind = 0
        content = 0
        marker = " "
        if (present(body)) body = ""
        if (md_indent(text) > 3) return
        t = left_trim(text)
        if (len(t) == 0) return
        i = 1
        if (scan(t(i:i), "-+*") > 0) then
            marker = t(i:i)
            if (rule(t)) return
        else
            do while (i <= len(t))
                if (verify(t(i:i), "0123456789") /= 0) exit
                i = i + 1
            end do
            if (i == 1 .or. i > 10 .or. i > len(t)) return
            if (t(i:i) /= "." .and. t(i:i) /= ")") return
            read (t(1:i - 1), *, iostat=ios) number
            if (ios /= 0) return
            kind = 1
            marker = t(i:i)
        end if
        if (i < len(t)) then
            if (t(i + 1:i + 1) /= " " .and. t(i + 1:i + 1) /= achar(9)) return
        end if
        spaces = 0
        j = i + 1
        do while (j <= len(t))
            if (t(j:j) == " ") then
                spaces = spaces + 1
            else if (t(j:j) == achar(9)) then
                spaces = spaces + 4 - mod(md_indent(text) + i + spaces, 4)
            else
                exit
            end if
            j = j + 1
        end do
        used = spaces
        if (used > 4 .or. used == 0) used = 1
        content = md_indent(text) + i + used
        if (present(body)) body = repeat(" ", max(0, spaces - used))//t(j:)
        item_marker = .true.
    end function item_marker

    logical function interrupts(text)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: t, info, label, body
        integer :: n, number, kind, col
        character :: marker, bullet
        interrupts = .false.
        if (md_indent(text) > 3) return
        t = trim(left_trim(text))
        if (len(t) == 0) return
        call fence(text, marker, n, info)
        interrupts = heading_level(t) > 0 .or. rule(t) .or. n >= 3 .or. t(1:1) == ">" .or. &
                     block_break(text) .or. target_line(text, label) .or. starts(t, "$$") .or. t(1:1) == "%"
        if (.not. interrupts .and. item_marker(text, number, kind, col, bullet, body)) &
            interrupts = len_trim(body) > 0 .and. (kind == 0 .or. number == 1)
    end function interrupts

    recursive subroutine blocks(doc, parent, lines, first, last, depth, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, first, last, depth
        type(md_line_t), intent(in) :: lines(:)
        type(status_t), intent(out) :: status
        type(md_line_t), allocatable :: inner(:)
        character(len=:), allocatable :: t, info, text, pending, label, part, next
        character :: marker, bullet
        integer :: i, j, k, count, lev, node, container, indent, number, kind, col, brk
        if (depth > 100) then
            call status%set(ERROR_UNSUPPORTED, "MyST: block nesting exceeds the native profile")
            return
        end if
        pending = ""
        container = parent
        i = first
        do while (i <= last)
            if (empty(lines(i)%text)) then
                i = i + 1
                cycle
            end if
            indent = md_indent(lines(i)%text)
            t = trim(left_trim(lines(i)%text))
            if (indent <= 3 .and. t(1:1) == "%") then
                i = i + 1
                cycle
            end if
            if (target_line(lines(i)%text, label)) then
                if (len(pending) > 0) then
                    call md_error(status, lines(i)%number, "multiple targets before one block are unsupported", .true.)
                    return
                end if
                pending = label
                i = i + 1
                cycle
            end if
            node = 0
            if (block_break(lines(i)%text, col)) then
                call read_block_metadata(t(col:), part, brk, status)
                if (.not. status%ok()) return
                if (len(part) > 0 .and. parent /= 1) then
                    call md_error(status, lines(i)%number, "document parts must be top-level blocks", .true.)
                    return
                end if
                kind = DOC_DIV
                if (len(part) > 0) kind = DOC_PART
                node = doc_add(doc, parent, kind, status)
                if (.not. status%ok()) return
                doc%nodes(node)%part = part
                doc%nodes(node)%break_before = brk
                container = node
                i = i + 1
            else
                call fence(lines(i)%text, marker, count, info)
                lev = heading_level(t)
                if (indent >= 4) then
                    j = i
                    text = ""
                    do while (j <= last)
                        if (.not. empty(lines(j)%text) .and. md_indent(lines(j)%text) < 4) exit
                        text = text//deindent(lines(j)%text, 4)//NL
                        j = j + 1
                    end do
                    do while (len(text) > 1)
                        if (text(len(text) - 1:) /= NL//NL) exit
                        text = text(1:len(text) - 1)
                    end do
                    node = doc_add_text(doc, container, DOC_CODE, text, status)
                    i = j
                else if (count >= 3) then
                    j = fence_end(lines, i + 1, last, marker, count)
                    if (starts(info, "{")) then
                        if (j > last) then
                            call md_error(status, lines(i)%number, "unterminated MyST directive")
                            return
                        end if
                        allocate (inner(max(0, j - i - 1)))
                        do k = 1, size(inner)
                            inner(k) = lines(i + k)
                            inner(k)%text = deindent(inner(k)%text, indent)
                        end do
                        call directive(doc, container, info, inner, depth + 1, node, status)
                        deallocate (inner)
                    else
                        if (marker == ":") then
                            call md_error(status, lines(i)%number, "colon fences require a supported {directive}", .true.)
                            return
                        end if
                        text = ""
                        do k = i + 1, min(j - 1, last)
                            text = text//deindent(lines(k)%text, indent)//NL
                        end do
                        node = doc_add_text(doc, container, DOC_CODE, text, status)
                        if (.not. status%ok()) return
                        k = scan(info, " "//achar(9))
                        if (k > 0) info = info(1:k - 1)
                        call md_unescape(info, doc%nodes(node)%language, status)
                        if (.not. status%ok()) return
                    end if
                    i = min(j + 1, last + 1)
                else if (lev > 0) then
                    node = doc_add(doc, container, DOC_HEADING, status)
                    if (.not. status%ok()) return
                    doc%nodes(node)%num = lev
                    doc%nodes(node)%text = heading_text(t, lev)
                    call md_inlines(doc, node, heading_text(t, lev), status)
                    i = i + 1
                else if (starts(t, "$$")) then
                    call display_math(doc, container, lines, i, last, node, status)
                else if (rule(t)) then
                    node = doc_add(doc, container, DOC_RULE, status)
                    i = i + 1
                else if (t(1:1) == ">") then
                    call quote_block(doc, container, lines, i, last, depth + 1, node, status)
                else if (item_marker(lines(i)%text, number, kind, col, bullet)) then
                    call list_block(doc, container, lines, i, last, depth + 1, node, status)
                else
                    if (starts(t, "[^") .or. starts(t, BS//"begin{")) then
                        call md_error(status, lines(i)%number, "this block construct is outside the native MyST profile", .true.)
                        return
                    end if
                    if (starts(t, "[") .and. index(t, "]:") > 0) then
                        call md_error(status, lines(i)%number, "reference-definition links are outside this profile", .true.)
                        return
                    end if
                    if (i < last) then
                        if (index(t, "|") > 0 .and. table_delimiter(lines(i + 1)%text, t)) then
                            call pipe_table(doc, container, lines, i, last, node, status)
                            if (.not. status%ok()) return
                            call attach_target(doc, node, pending, status)
                            if (.not. status%ok()) return
                            cycle
                        end if
                    end if
                    text = left_trim(lines(i)%text)
                    j = i + 1
                    lev = 0
                    do while (j <= last)
                        if (empty(lines(j)%text)) exit
                        next = trim(left_trim(lines(j)%text))
                        if (md_indent(lines(j)%text) <= 3) then
                            lev = underline(next)
                            if (lev > 0) exit
                        end if
                        if (interrupts(lines(j)%text)) exit
                        text = text//NL//left_trim(lines(j)%text)
                        j = j + 1
                    end do
                    kind = DOC_PARA
                    if (lev > 0) kind = DOC_HEADING
                    node = doc_add(doc, container, kind, status)
                    if (.not. status%ok()) return
                    doc%nodes(node)%num = lev
                    if (kind == DOC_HEADING) doc%nodes(node)%text = trim(text)
                    call md_inlines(doc, node, trim(text), status)
                    i = j
                    if (lev > 0) i = j + 1
                end if
            end if
            if (.not. status%ok()) return
            if (node > 0) call attach_target(doc, node, pending, status)
            if (.not. status%ok()) return
        end do
        if (len(pending) > 0) call status%set(ERROR_ARGUMENT, "MyST: target has no following block: "//pending)
    end subroutine blocks

    subroutine attach_target(doc, node, pending, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: node
        character(len=:), allocatable, intent(inout) :: pending
        type(status_t), intent(out) :: status
        if (len(pending) == 0) return
        if (len(doc%nodes(node)%id) > 0 .and. doc%nodes(node)%id /= pending) then
            call status%set(ERROR_ARGUMENT, "MyST: conflicting labels on one block")
            return
        end if
        doc%nodes(node)%id = pending
        pending = ""
    end subroutine attach_target

    recursive subroutine directive(doc, parent, info, lines, depth, node, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, depth
        character(len=*), intent(in) :: info
        type(md_line_t), intent(in) :: lines(:)
        integer, intent(out) :: node
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: name, label, value, key, text, t
        integer :: close, i, colon, kind, j
        logical :: enumerated, enum_set
        node = 0
        close = index(info, "}")
        if (close < 3) then
            call status%set(ERROR_ARGUMENT, "MyST: invalid directive name")
            return
        end if
        name = info(2:close - 1)
        if (len_trim(info(close + 1:)) /= 0) then
            call status%set(ERROR_UNSUPPORTED, "MyST: directive arguments/inline options are outside this profile")
            return
        end if
        if (name /= "math" .and. name /= "div") then
            call status%set(ERROR_UNSUPPORTED, "MyST: unsupported directive: "//name)
            return
        end if
        label = ""
        enumerated = .true.
        enum_set = .false.
        i = 1
        do while (i <= size(lines))
            t = trim(left_trim(lines(i)%text))
            if (len(t) == 0) exit
            if (t(1:1) /= ":") exit
            colon = index(t(2:), ":") + 1
            if (colon <= 1) exit
            key = t(2:colon - 1)
            call read_scalar(t(colon + 1:), value, kind, status)
            if (.not. status%ok()) return
            select case (key)
            case ("label", "name")
                if (len(label) > 0 .or. kind /= META_STRING .or. len_trim(value) == 0) then
                    call md_error(status, lines(i)%number, "invalid or duplicate directive label")
                    return
                end if
                label = md_label(value)
            case ("enumerated")
                if (name /= "math" .or. kind /= META_BOOL .or. enum_set) then
                    call md_error(status, lines(i)%number, "invalid enumerated option")
                    return
                end if
                enumerated = value == "true"
                enum_set = .true.
            case default
                call md_error(status, lines(i)%number, "unsupported directive option: "//key, .true.)
                return
            end select
            i = i + 1
        end do
        if (i <= size(lines)) then
            if (empty(lines(i)%text)) i = i + 1
        end if
        kind = DOC_DIV
        if (name == "math") kind = DOC_MATH
        node = doc_add(doc, parent, kind, status)
        if (.not. status%ok()) return
        doc%nodes(node)%id = label
        if (name == "math") then
            text = ""
            do j = i, size(lines)
                if (j > i) text = text//NL
                text = text//lines(j)%text
            end do
            doc%nodes(node)%text = text
            doc%nodes(node)%display = .true.
            doc%nodes(node)%enumerated = enumerated
            doc%nodes(node)%enum_set = enum_set
        else
            call blocks(doc, node, lines, i, size(lines), depth, status)
        end if
    end subroutine directive

    subroutine display_math(doc, parent, lines, i, last, node, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, last
        type(md_line_t), intent(in) :: lines(:)
        integer, intent(inout) :: i
        integer, intent(out) :: node
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: text, t, suffix
        integer :: close, j
        t = left_trim(lines(i)%text)
        t = t(3:)
        text = ""
        j = i
        do
            close = index(t, "$$")
            if (close > 0) exit
            if (j > i) text = text//NL
            text = text//t
            j = j + 1
            if (j > last) then
                call md_error(status, lines(i)%number, "unterminated display math")
                return
            end if
            t = lines(j)%text
        end do
        if (j > i) text = text//NL
        text = text//t(1:close - 1)
        suffix = trim(left_trim(t(close + 2:)))
        if (len(suffix) > 0) then
            if (suffix(1:1) /= "(" .or. .not. ends(suffix, ")")) then
                call md_error(status, lines(j)%number, "text after display math; use \\label or a MyST target")
                return
            end if
        end if
        node = doc_add_text(doc, parent, DOC_MATH, trim(text), status)
        if (.not. status%ok()) return
        doc%nodes(node)%display = .true.
        if (len(suffix) > 0) doc%nodes(node)%id = md_label(suffix(2:len(suffix) - 1))
        i = j + 1
    end subroutine display_math

    function quote_content(text) result(value)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: value, t
        integer :: start, column, at
        t = left_trim(text)
        value = t
        if (len(t) == 0) return
        if (t(1:1) /= ">") return
        start = md_indent(text) + 1
        column = start
        at = 2
        do while (at <= len(t))
            if (t(at:at) == " ") then
                column = column + 1
            else if (t(at:at) == achar(9)) then
                column = column + 4 - mod(column, 4)
            else
                exit
            end if
            at = at + 1
        end do
        value = repeat(" ", max(0, column - start - 1))//t(at:)
    end function quote_content

    subroutine continuation_state(text, marker, count, paragraph)
        character(len=*), intent(in) :: text
        character, intent(inout) :: marker
        integer, intent(inout) :: count
        logical, intent(inout) :: paragraph
        character(len=:), allocatable :: t, info, body, label
        character :: c, bullet
        integer :: n, number, kind, col
        t = trim(left_trim(text))
        if (count > 0) then
            paragraph = .false.
            if (marker == "$") then
                if (index(t, "$$") > 0) count = 0
            else
                call fence(text, c, n, info)
                if (c == marker .and. n >= count .and. len(info) == 0) count = 0
            end if
            return
        end if
        if (md_indent(text) >= 4) return
        do while (starts(t, ">"))
            t = quote_content(t)
        end do
        if (item_marker(t, number, kind, col, bullet, body)) t = body
        call fence(t, c, n, info)
        paragraph = .false.
        if (n >= 3) then
            marker = c
            count = n
        else if (starts(t, "$$")) then
            if (index(t(3:), "$$") == 0) then
                marker = "$"
                count = 2
            end if
        else
            paragraph = len_trim(t) > 0 .and. heading_level(t) == 0 .and. .not. rule(t) .and. &
                        .not. block_break(t) .and. .not. target_line(t, label)
        end if
    end subroutine continuation_state

    recursive subroutine quote_block(doc, parent, lines, i, last, depth, node, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, last, depth
        type(md_line_t), intent(in) :: lines(:)
        integer, intent(inout) :: i
        integer, intent(out) :: node
        type(status_t), intent(out) :: status
        type(md_line_t), allocatable :: inner(:)
        character(len=:), allocatable :: t
        integer :: j, k, count
        character :: marker
        logical :: paragraph
        j = i
        count = 0
        marker = " "
        paragraph = .false.
        do while (j <= last)
            if (empty(lines(j)%text)) exit
            t = left_trim(lines(j)%text)
            if (t(1:1) /= ">" .and. j > i) then
                if (.not. paragraph .or. interrupts(lines(j)%text)) exit
            else
                call continuation_state(quote_content(lines(j)%text), marker, count, paragraph)
            end if
            j = j + 1
        end do
        allocate (inner(j - i))
        do k = i, j - 1
            inner(k - i + 1) = lines(k)
            inner(k - i + 1)%text = quote_content(lines(k)%text)
        end do
        node = doc_add(doc, parent, DOC_QUOTE, status)
        if (.not. status%ok()) return
        call blocks(doc, node, inner, 1, size(inner), depth, status)
        i = j
    end subroutine quote_block

    recursive subroutine list_block(doc, parent, lines, i, last, depth, node, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, last, depth
        type(md_line_t), intent(in) :: lines(:)
        integer, intent(inout) :: i
        integer, intent(out) :: node
        type(status_t), intent(out) :: status
        type(md_line_t), allocatable :: item(:)
        character(len=:), allocatable :: body
        integer :: start_num, kind, col, other_num, other_kind, other_col, j, k, it, first, count
        character :: marker, other_marker, code_marker
        logical :: matched, blank, tight, paragraph
        matched = item_marker(lines(i)%text, start_num, kind, col, marker)
        node = doc_add(doc, parent, DOC_LIST, status)
        if (.not. status%ok()) return
        doc%nodes(node)%ordered = kind == 1
        doc%nodes(node)%num = start_num
        doc%nodes(node)%spaced = .true.
        tight = .true.
        do while (i <= last)
            matched = item_marker(lines(i)%text, other_num, other_kind, col, other_marker, body)
            if (.not. matched) exit
            if (other_kind /= kind .or. other_marker /= marker) exit
            first = i
            paragraph = .false.
            count = 0
            code_marker = " "
            call continuation_state(body, code_marker, count, paragraph)
            j = i + 1
            blank = .false.
            do while (j <= last)
                if (empty(lines(j)%text)) then
                    if (count == 0) blank = .true.
                    paragraph = .false.
                    j = j + 1
                    cycle
                end if
                if (md_indent(lines(j)%text) >= col) then
                    if (blank) tight = .false.
                    blank = .false.
                    call continuation_state(deindent(lines(j)%text, col), code_marker, count, paragraph)
                    j = j + 1
                    cycle
                end if
                if (item_marker(lines(j)%text, other_num, other_kind, other_col, other_marker)) then
                    if (blank .and. other_kind == kind .and. other_marker == marker) tight = .false.
                    exit
                end if
                if (blank .or. .not. paragraph .or. interrupts(lines(j)%text)) exit
                j = j + 1
            end do
            k = j - 1
            do while (k > first)
                if (.not. empty(lines(k)%text)) exit
                k = k - 1
            end do
            allocate (item(k - first + 1))
            item(1) = lines(first)
            item(1)%text = body
            do it = first + 1, k
                item(it - first + 1) = lines(it)
                if (md_indent(lines(it)%text) >= col) then
                    item(it - first + 1)%text = deindent(lines(it)%text, col)
                else
                    item(it - first + 1)%text = left_trim(lines(it)%text)
                end if
            end do
            it = doc_add(doc, node, DOC_ITEM, status)
            if (.not. status%ok()) return
            call blocks(doc, it, item, 1, size(item), depth, status)
            if (.not. status%ok()) return
            deallocate (item)
            i = j
        end do
        doc%nodes(node)%tight = tight
    end subroutine list_block

    logical function table_delimiter(text, header)
        character(len=*), intent(in) :: text
        character(len=*), intent(in) :: header
        type(md_line_t), allocatable :: cells(:), columns(:)
        character(len=:), allocatable :: t
        integer :: i
        table_delimiter = .false.
        if (md_indent(text) > 3 .or. scan(text, "-") == 0 .or. verify(text, " |-:"//achar(9)) /= 0) return
        call split_cells(text, cells)
        call split_cells(header, columns)
        if (size(cells) /= size(columns)) return
        do i = 1, size(cells)
            t = cells(i)%text
            if (len(t) == 0) return
            if (t(1:1) == ":") t = t(2:)
            if (len(t) == 0) return
            if (t(len(t):) == ":") t = t(1:len(t) - 1)
            if (len(t) == 0 .or. verify(t, "-") /= 0) return
        end do
        table_delimiter = .true.
    end function table_delimiter

    subroutine split_cells(text, cells)
        character(len=*), intent(in) :: text
        type(md_line_t), allocatable, intent(out) :: cells(:)
        character(len=:), allocatable :: t, value
        integer :: n, i, k
        t = trim(left_trim(text))
        if (len(t) > 0) then
            if (t(1:1) == "|") t = t(2:)
        end if
        if (len(t) > 0) then
            if (t(len(t):) == "|") then
                if (len(t) == 1) then
                    t = ""
                else if (t(len(t) - 1:len(t) - 1) /= BS) then
                    t = t(1:len(t) - 1)
                end if
            end if
        end if
        n = 1
        i = 1
        do while (i <= len(t))
            if (t(i:i) == "|") then
                if (i == 1) then
                    n = n + 1
                else if (t(i - 1:i - 1) /= BS) then
                    n = n + 1
                end if
            end if
            i = i + 1
        end do
        allocate (cells(n))
        value = ""
        k = 1
        i = 1
        do while (i <= len(t))
            if (t(i:i) == "|") then
                if (i > 1) then
                    if (t(i - 1:i - 1) == BS) then
                        value = value(1:len(value) - 1)//"|"
                        i = i + 1
                        cycle
                    end if
                end if
                cells(k)%text = trim(left_trim(value))
                value = ""
                k = k + 1
            else
                value = value//t(i:i)
            end if
            i = i + 1
        end do
        cells(k)%text = trim(left_trim(value))
    end subroutine split_cells

    subroutine plain_cell(doc, text, value, status)
        type(doc_t), intent(inout) :: doc
        character(len=*), intent(in) :: text
        character(len=:), allocatable, intent(out) :: value
        type(status_t), intent(out) :: status
        integer :: node, child
        node = doc_add(doc, 0, DOC_INLINES, status)
        if (.not. status%ok()) return
        call md_inlines(doc, node, text, status)
        if (.not. status%ok()) return
        child = doc%nodes(node)%first
        value = ""
        do while (child > 0)
            select case (doc%nodes(child)%kind)
            case (IN_STR)
                value = value//doc%nodes(child)%text
            case (IN_SPACE)
                value = value//" "
            case default
                call status%set(ERROR_UNSUPPORTED, "MyST: pipe-table cells currently support plain text only")
                return
            end select
            child = doc%nodes(child)%next
        end do
    end subroutine plain_cell

    subroutine pipe_table(doc, parent, lines, i, last, node, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, last
        type(md_line_t), intent(in) :: lines(:)
        integer, intent(inout) :: i
        integer, intent(out) :: node
        type(status_t), intent(out) :: status
        type(md_line_t), allocatable :: header(:), delimiter(:), row(:), values(:, :)
        character(len=:), allocatable :: cells(:, :), columns(:), value, t
        character(len=1), allocatable :: aligns(:)
        integer :: nc, nr, j, k, r, width
        call split_cells(lines(i)%text, header)
        call split_cells(lines(i + 1)%text, delimiter)
        nc = size(header)
        if (size(delimiter) /= nc) then
            call md_error(status, lines(i + 1)%number, "table header and delimiter widths differ")
            return
        end if
        allocate (aligns(nc))
        aligns = "l"
        do k = 1, nc
            t = delimiter(k)%text
            if (len(t) == 0 .or. index(t, "-") == 0 .or. verify(t, ":-") /= 0) then
                call md_error(status, lines(i + 1)%number, "invalid table delimiter")
                return
            end if
            if (t(len(t):) == ":") aligns(k) = "r"
            if (t(1:1) == ":" .and. t(len(t):) == ":") aligns(k) = "c"
        end do
        j = i + 2
        do while (j <= last)
            if (empty(lines(j)%text) .or. interrupts(lines(j)%text)) exit
            j = j + 1
        end do
        nr = j - i - 2
        allocate (values(nr + 1, nc))
        width = 1
        do k = 1, nc
            call plain_cell(doc, header(k)%text, value, status)
            if (.not. status%ok()) return
            values(1, k)%text = value
            width = max(width, len(value))
        end do
        do r = 1, nr
            call split_cells(lines(i + 1 + r)%text, row)
            do k = 1, nc
                value = ""
                if (k <= size(row)) then
                    call plain_cell(doc, row(k)%text, value, status)
                    if (.not. status%ok()) return
                end if
                values(r + 1, k)%text = value
                width = max(width, len(value))
            end do
        end do
        allocate (character(len=width) :: cells(nr, nc), columns(nc))
        do k = 1, nc
            columns(k) = values(1, k)%text
            do r = 1, nr
                cells(r, k) = values(r + 1, k)%text
            end do
        end do
        node = doc_add_table(doc, parent, cells, columns, status=status)
        if (.not. status%ok()) return
        allocate (doc%tables(doc%nodes(node)%num)%alignment(nc))
        doc%tables(doc%nodes(node)%num)%alignment = aligns
        i = j
    end subroutine pipe_table

end module fplotlib_markdown
