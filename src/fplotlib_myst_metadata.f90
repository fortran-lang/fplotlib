! The block-style YAML subset used by the native MyST frontend, plus JSON
! metadata on MyST content blocks. Unsupported YAML features are diagnosed.
module fplotlib_myst_metadata
    use fplotlib_status
    use fplotlib_style, only: utf8_char
    use fplotlib_doctree
    implicit none
    private
    public :: md_line_t, md_split_lines, md_indent, md_error
    public :: read_frontmatter, read_block_metadata, read_scalar, decimal_number, author_name_key

    character, parameter :: NL = achar(10), BS = achar(92)
    type :: md_line_t
        character(len=:), allocatable :: text
        integer :: number = 0
    end type md_line_t

contains

    pure logical function author_name_key(key) result(valid)
        character(len=*), intent(in) :: key
        integer :: dot
        valid = key == "authors"
        if (valid .or. len(key) < 9) return
        if (key(1:8) /= "authors.") return
        dot = index(key(9:), ".")
        if (dot == 0) then
            valid = verify(key(9:), "0123456789") == 0
        else if (dot > 1) then
            valid = verify(key(9:dot + 7), "0123456789") == 0 .and. key(dot + 8:) == ".name"
        end if
    end function author_name_key

    subroutine md_error(status, line, message, unsupported)
        type(status_t), intent(out) :: status
        integer, intent(in) :: line
        character(len=*), intent(in) :: message
        logical, intent(in), optional :: unsupported
        character(len=24) :: n
        integer :: code
        code = ERROR_ARGUMENT
        if (present(unsupported)) then
            if (unsupported) code = ERROR_UNSUPPORTED
        end if
        write (n, "(i0)") line
        call status%set(code, "MyST line "//trim(n)//": "//message)
    end subroutine md_error

    subroutine md_split_lines(text, lines)
        character(len=*), intent(in) :: text
        type(md_line_t), allocatable, intent(out) :: lines(:)
        integer :: n, i, first, last
        n = 1
        do i = 1, len(text)
            if (text(i:i) == NL) n = n + 1
        end do
        allocate (lines(n))
        first = 1
        do i = 1, n
            last = index(text(first:), NL)
            if (last == 0) then
                last = len(text) + 1
            else
                last = first + last - 1
            end if
            lines(i)%text = text(first:last - 1)
            lines(i)%number = i
            if (len(lines(i)%text) > 0) then
                if (lines(i)%text(len(lines(i)%text):) == achar(13)) &
                    lines(i)%text = lines(i)%text(1:len(lines(i)%text) - 1)
            end if
            first = last + 1
        end do
    end subroutine md_split_lines

    pure integer function md_indent(text) result(n)
        character(len=*), intent(in) :: text
        integer :: i
        n = 0
        do i = 1, len(text)
            if (text(i:i) == " ") then
                n = n + 1
            else if (text(i:i) == achar(9)) then
                n = n + 4 - mod(n, 4)
            else
                exit
            end if
        end do
    end function md_indent

    pure logical function blank(text)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: t
        t = trim(adjustl(text))
        blank = len(t) == 0
        if (len(t) > 0) blank = t(1:1) == "#"
    end function blank

    pure logical function key_char(c)
        character, intent(in) :: c
        key_char = (c >= "a" .and. c <= "z") .or. (c >= "A" .and. c <= "Z") .or. &
                   (c >= "0" .and. c <= "9") .or. c == "_" .or. c == "-"
    end function key_char

    subroutine read_frontmatter(lines, doc, status)
        type(md_line_t), intent(in) :: lines(:)
        type(doc_t), intent(inout) :: doc
        type(status_t), intent(out) :: status
        type(md_line_t), allocatable :: work(:)
        integer :: i, j
        allocate (work(size(lines)))
        work = lines
        do i = 1, size(work)
            do j = 1, len(work(i)%text)
                if (work(i)%text(j:j) == achar(9)) then
                    call md_error(status, work(i)%number, "tabs are not allowed in YAML indentation")
                    return
                end if
                if (work(i)%text(j:j) /= " ") exit
            end do
        end do
        i = 1
        call yaml_map(work, i, 0, "", doc, 0, status)
        if (.not. status%ok()) return
        if (i <= size(work)) call md_error(status, work(i)%number, "invalid front matter indentation")
    end subroutine read_frontmatter

    subroutine append_meta(doc, path, value, kind, line, status)
        type(doc_t), intent(inout) :: doc
        character(len=*), intent(in) :: path, value
        integer, intent(in) :: kind, line
        type(status_t), intent(out) :: status
        integer :: k
        do k = 1, doc%nmeta
            if (doc%meta(k)%key == path) then
                call md_error(status, line, "duplicate metadata key: "//path)
                return
            end if
        end do
        call doc_add_meta(doc, path, value, 0, status)
        if (.not. status%ok()) return
        doc%meta(doc%nmeta)%kind = kind
    end subroutine append_meta

    recursive subroutine yaml_map(lines, i, indent, prefix, doc, depth, status)
        type(md_line_t), intent(inout) :: lines(:)
        integer, intent(inout) :: i
        integer, intent(in) :: indent, depth
        character(len=*), intent(in) :: prefix
        type(doc_t), intent(inout) :: doc
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: t, key, path, value
        integer :: colon, j, kind, line
        if (depth > 32) then
            call md_error(status, lines(i)%number, "metadata nesting exceeds the native profile", .true.)
            return
        end if
        do while (i <= size(lines))
            if (blank(lines(i)%text)) then
                i = i + 1
                cycle
            end if
            if (md_indent(lines(i)%text) < indent) return
            if (md_indent(lines(i)%text) /= indent) then
                call md_error(status, lines(i)%number, "unexpected YAML indentation")
                return
            end if
            t = trim(lines(i)%text(indent + 1:))
            colon = index(t, ":")
            if (colon < 2) then
                call md_error(status, lines(i)%number, "expected a YAML key: value mapping")
                return
            end if
            key = trim(t(1:colon - 1))
            do j = 1, len(key)
                if (.not. key_char(key(j:j))) then
                    call md_error(status, lines(i)%number, "unsupported YAML mapping key", .true.)
                    return
                end if
            end do
            if (len(prefix) == 0) then
                select case (key)
                case ("author")
                    key = "authors"
                case ("export")
                    key = "exports"
                case ("part")
                    key = "parts"
                end select
            end if
            if (colon < len(t)) then
                if (t(colon + 1:colon + 1) /= " " .and. t(colon + 1:colon + 1) /= achar(9)) then
                    call md_error(status, lines(i)%number, "a YAML mapping colon must be followed by whitespace")
                    return
                end if
            end if
            path = key
            if (len(prefix) > 0) path = prefix//"."//key
            value = trim(adjustl(t(colon + 1:)))
            line = lines(i)%number
            i = i + 1
            if (blank(value)) then
                j = i
                do while (j <= size(lines))
                    if (.not. blank(lines(j)%text)) exit
                    j = j + 1
                end do
                if (j <= size(lines)) then
                    if (md_indent(lines(j)%text) > indent) then
                        i = j
                        call yaml_collection(lines, i, md_indent(lines(i)%text), path, doc, depth + 1, status)
                        if (.not. status%ok()) return
                        cycle
                    end if
                end if
                call append_meta(doc, path, "", META_NULL, line, status)
            else if (value(1:1) == "|" .or. value(1:1) == ">") then
                t = value
                call yaml_block(lines, i, indent, t, value, status)
                if (.not. status%ok()) return
                call append_meta(doc, path, value, META_STRING, line, status)
            else
                t = value
                call read_scalar(t, value, kind, status)
                if (.not. status%ok()) return
                call append_meta(doc, path, value, kind, line, status)
            end if
            if (.not. status%ok()) return
        end do
    end subroutine yaml_map

    recursive subroutine yaml_collection(lines, i, indent, path, doc, depth, status)
        type(md_line_t), intent(inout) :: lines(:)
        integer, intent(inout) :: i
        integer, intent(in) :: indent, depth
        character(len=*), intent(in) :: path
        type(doc_t), intent(inout) :: doc
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: t, child, value
        character(len=24) :: num
        integer :: count, first, col, kind, line
        t = lines(i)%text(indent + 1:)
        if (len(t) > 1) then
            if (t(1:2) == "- ") then
                call append_meta(doc, path, "", META_SEQUENCE, lines(i)%number, status)
                if (.not. status%ok()) return
                count = 0
                do while (i <= size(lines))
                    if (blank(lines(i)%text)) then
                        i = i + 1
                        cycle
                    end if
                    if (md_indent(lines(i)%text) /= indent) return
                    t = trim(lines(i)%text(indent + 1:))
                    if (len(t) < 2) exit
                    if (t(1:2) /= "- ") exit
                    count = count + 1
                    write (num, "(i0)") count
                    child = path//"."//trim(num)
                    col = 3
                    do while (col <= len(t))
                        if (t(col:col) /= " ") exit
                        col = col + 1
                    end do
                    value = t(col:)
                    line = lines(i)%number
                    first = index(value, ":")
                    if (first > 0 .and. first < len(value)) then
                        if (value(first + 1:first + 1) /= " " .and. &
                            value(first + 1:first + 1) /= achar(9)) first = 0
                    end if
                    if (first > 0 .and. value(1:1) /= "'" .and. value(1:1) /= '"') then
                        call append_meta(doc, child, "", META_MAP, line, status)
                        if (.not. status%ok()) return
                        lines(i)%text = repeat(" ", indent + col - 1)//value
                        call yaml_map(lines, i, indent + col - 1, child, doc, depth, status)
                    else
                        t = value
                        call read_scalar(t, value, kind, status)
                        if (.not. status%ok()) return
                        call append_meta(doc, child, value, kind, line, status)
                        i = i + 1
                    end if
                    if (.not. status%ok()) return
                end do
                if (i <= size(lines)) call md_error(status, lines(i)%number, "expected a YAML sequence item")
                return
            end if
        end if
        call append_meta(doc, path, "", META_MAP, lines(i)%number, status)
        if (.not. status%ok()) return
        call yaml_map(lines, i, indent, path, doc, depth, status)
    end subroutine yaml_collection

    subroutine yaml_block(lines, i, parent_indent, indicator, value, status)
        type(md_line_t), intent(in) :: lines(:)
        integer, intent(inout) :: i
        integer, intent(in) :: parent_indent
        character(len=*), intent(in) :: indicator
        character(len=:), allocatable, intent(out) :: value
        type(status_t), intent(out) :: status
        integer :: first, last, indent, j, k
        logical :: folded, more, next_more
        character :: chomp
        character(len=:), allocatable :: line, next
        folded = indicator(1:1) == ">"
        chomp = " "
        if (len(indicator) > 1) chomp = indicator(2:2)
        if (len(indicator) > 2 .or. (chomp /= " " .and. chomp /= "-" .and. chomp /= "+")) then
            call status%set(ERROR_UNSUPPORTED, "MyST: use |, >, |- or >- for YAML block scalars")
            return
        end if
        first = i
        indent = -1
        do j = i, size(lines)
            if (len_trim(lines(j)%text) == 0) cycle
            indent = md_indent(lines(j)%text)
            exit
        end do
        value = ""
        if (indent <= parent_indent) return
        last = first
        do while (last <= size(lines))
            if (len_trim(lines(last)%text) > 0) then
                if (md_indent(lines(last)%text) < indent) exit
            end if
            last = last + 1
        end do
        do j = first, last - 1
            line = ""
            if (len(lines(j)%text) >= indent) line = lines(j)%text(indent + 1:)
            value = value//line
            if (.not. folded .or. j == last - 1) then
                value = value//NL
                cycle
            end if
            next = ""
            if (len(lines(j + 1)%text) >= indent) next = lines(j + 1)%text(indent + 1:)
            more = md_indent(lines(j)%text) > indent
            next_more = md_indent(lines(j + 1)%text) > indent
            if (len_trim(line) == 0 .or. more .or. next_more) then
                value = value//NL
            else if (len_trim(next) > 0) then
                value = value//" "
            end if
        end do
        i = last
        if (chomp /= "+") then
            k = len(value)
            do while (k > 0)
                if (value(k:k) /= NL) exit
                k = k - 1
            end do
            value = value(1:k)
            if (chomp /= "-" .and. k > 0) value = value//NL
        end if
    end subroutine yaml_block

    subroutine quoted_scalar(source, i, value, status, json)
        character(len=*), intent(in) :: source
        integer, intent(inout) :: i
        character(len=:), allocatable, intent(out) :: value
        type(status_t), intent(out) :: status
        logical, intent(in), optional :: json
        character :: quote, c
        integer :: digits, cp, low, ios
        logical :: is_json
        value = ""
        quote = source(i:i)
        is_json = .false.
        if (present(json)) is_json = json
        i = i + 1
        do while (i <= len(source))
            c = source(i:i)
            i = i + 1
            if (is_json .and. iachar(c) < 32) then
                call status%set(ERROR_ARGUMENT, "MyST: unescaped control character in JSON string")
                return
            end if
            if (c == quote) then
                if (quote == "'" .and. i <= len(source)) then
                    if (source(i:i) == "'") then
                        value = value//"'"
                        i = i + 1
                        cycle
                    end if
                end if
                return
            end if
            if (c /= BS .or. quote == "'") then
                value = value//c
                cycle
            end if
            if (i > len(source)) exit
            c = source(i:i)
            i = i + 1
            digits = 0
            select case (c)
            case (BS, '"', "/")
                value = value//c
            case ("b")
                value = value//achar(8)
            case ("f")
                value = value//achar(12)
            case ("n")
                value = value//NL
            case ("r")
                value = value//achar(13)
            case ("t")
                value = value//achar(9)
            case ("u")
                digits = 4
            case ("x", "U")
                if (is_json) then
                    call status%set(ERROR_ARGUMENT, "MyST: invalid JSON string escape")
                    return
                end if
                digits = merge(2, 8, c == "x")
            case default
                call status%set(ERROR_UNSUPPORTED, "MyST: unsupported quoted-string escape")
                return
            end select
            if (digits > 0) then
                if (i + digits - 1 > len(source)) exit
                if (verify(source(i:i + digits - 1), "0123456789abcdefABCDEF") /= 0) then
                    call status%set(ERROR_ARGUMENT, "MyST: invalid Unicode escape")
                    return
                end if
                read (source(i:i + digits - 1), "(z8)", iostat=ios) cp
                if (ios /= 0) then
                    call status%set(ERROR_ARGUMENT, "MyST: invalid Unicode escape")
                    return
                end if
                i = i + digits
                if (is_json .and. cp >= 55296 .and. cp <= 56319) then
                    if (i + 5 > len(source)) exit
                    if (source(i:i + 1) /= BS//"u") then
                        call status%set(ERROR_ARGUMENT, "MyST: missing low Unicode surrogate")
                        return
                    end if
                    if (verify(source(i + 2:i + 5), "0123456789abcdefABCDEF") /= 0) then
                        call status%set(ERROR_ARGUMENT, "MyST: invalid low Unicode surrogate")
                        return
                    end if
                    low = 0
                    read (source(i + 2:i + 5), "(z8)", iostat=ios) low
                    if (ios /= 0 .or. low < 56320 .or. low > 57343) then
                        call status%set(ERROR_ARGUMENT, "MyST: invalid low Unicode surrogate")
                        return
                    end if
                    cp = 65536 + (cp - 55296)*1024 + low - 56320
                    i = i + 6
                end if
                if (cp < 0 .or. cp > 1114111 .or. (cp >= 55296 .and. cp <= 57343)) then
                    call status%set(ERROR_ARGUMENT, "MyST: invalid Unicode scalar")
                    return
                end if
                value = value//utf8_char(cp)
            end if
        end do
        call status%set(ERROR_ARGUMENT, "MyST: unterminated quoted scalar")
    end subroutine quoted_scalar

    subroutine read_scalar(source, value, kind, status)
        character(len=*), intent(in) :: source
        character(len=:), allocatable, intent(out) :: value
        integer, intent(out) :: kind
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: t
        integer :: i, j
        t = trim(adjustl(source))
        kind = META_STRING
        value = ""
        if (len(t) == 0) then
            kind = META_NULL
            return
        end if
        if (t(1:1) == "'" .or. t(1:1) == '"') then
            i = 1
            call quoted_scalar(t, i, value, status)
            if (.not. status%ok()) return
            j = i
            do while (i <= len(t))
                if (t(i:i) /= " " .and. t(i:i) /= achar(9)) exit
                i = i + 1
            end do
            if (i <= len(t)) then
                if (t(i:i) /= "#" .or. i == j) call status%set(ERROR_ARGUMENT, "MyST: text after a quoted YAML scalar")
            end if
            return
        end if
        select case (t(1:1))
        case ("[", "{", "&", "*", "!", "|", ">", "@", "`")
            call status%set(ERROR_UNSUPPORTED, "MyST: unsupported YAML feature; use block mappings and sequences")
            return
        end select
        j = len(t)
        do i = 1, len(t)
            if (t(i:i) == "#") then
                if (i == 1) then
                    j = 0
                    exit
                else if (t(i - 1:i - 1) == " " .or. t(i - 1:i - 1) == achar(9)) then
                    j = i - 1
                    exit
                end if
            end if
        end do
        value = trim(t(1:j))
        if (index(value, ": ") > 0) then
            call status%set(ERROR_ARGUMENT, "MyST: quote YAML scalar values containing ': '")
            return
        end if
        select case (value)
        case ("true", "True", "TRUE")
            kind = META_BOOL
            value = "true"
        case ("false", "False", "FALSE")
            kind = META_BOOL
            value = "false"
        case ("", "~", "null", "Null", "NULL")
            kind = META_NULL
            value = ""
        case default
            if (decimal_number(value)) kind = META_NUMBER
        end select
    end subroutine read_scalar

    pure logical function decimal_number(value) result(valid)
        character(len=*), intent(in) :: value
        integer :: i, digits
        valid = .false.
        if (len(value) == 0) return
        i = 1
        if (scan(value(i:i), "+-") > 0) i = i + 1
        digits = 0
        do while (i <= len(value))
            if (scan(value(i:i), "0123456789") == 0) exit
            digits = digits + 1
            i = i + 1
        end do
        if (i <= len(value)) then
            if (value(i:i) == ".") then
                i = i + 1
                do while (i <= len(value))
                    if (scan(value(i:i), "0123456789") == 0) exit
                    digits = digits + 1
                    i = i + 1
                end do
            end if
        end if
        if (digits == 0) return
        if (i <= len(value)) then
            if (scan(value(i:i), "eE") == 0) return
            i = i + 1
            if (i <= len(value)) then
                if (scan(value(i:i), "+-") > 0) i = i + 1
            end if
            digits = 0
            do while (i <= len(value))
                if (scan(value(i:i), "0123456789") == 0) exit
                digits = digits + 1
                i = i + 1
            end do
            if (digits == 0) return
        end if
        valid = i > len(value)
    end function decimal_number

    subroutine read_block_metadata(source, part, break_before, status)
        character(len=*), intent(in) :: source
        character(len=:), allocatable, intent(out) :: part
        integer, intent(out) :: break_before
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: t, key, value
        integer :: i, start, kind
        logical :: seen_part, seen_break
        part = ""
        break_before = 0
        seen_part = .false.
        seen_break = .false.
        t = trim(adjustl(source))
        if (len(t) == 0) return
        if (t(1:1) /= "{") then
            call status%set(ERROR_ARGUMENT, "MyST: content-block metadata must be a JSON object")
            return
        end if
        i = 2
        do
            call skip_json_space(t, i)
            if (i > len(t)) exit
            if (t(i:i) == "}") then
                i = i + 1
                call skip_json_space(t, i)
                if (i <= len(t)) call status%set(ERROR_ARGUMENT, "MyST: text after block metadata")
                return
            end if
            if (t(i:i) /= '"') exit
            call quoted_scalar(t, i, key, status, json=.true.)
            if (.not. status%ok()) return
            call skip_json_space(t, i)
            if (i > len(t)) exit
            if (t(i:i) /= ":") exit
            i = i + 1
            call skip_json_space(t, i)
            if (i > len(t)) exit
            kind = META_BOOL
            if (t(i:i) == '"') then
                kind = META_STRING
                call quoted_scalar(t, i, value, status, json=.true.)
                if (.not. status%ok()) return
            else
                start = i
                do while (i <= len(t))
                    if (scan(t(i:i), " ,}"//achar(9)) > 0) exit
                    i = i + 1
                end do
                value = t(start:i - 1)
                if (value /= "true" .and. value /= "false") exit
            end if
            select case (key)
            case ("part")
                if (seen_part .or. kind /= META_STRING .or. len_trim(value) == 0) exit
                part = value
                seen_part = .true.
            case ("page-break", "new-page")
                if (seen_break .or. kind /= META_BOOL) exit
                if (value == "true") break_before = merge(1, 2, key == "new-page")
                seen_break = .true.
            case default
                call status%set(ERROR_UNSUPPORTED, "MyST: unsupported block metadata key: "//key)
                return
            end select
            call skip_json_space(t, i)
            if (i > len(t)) exit
            if (t(i:i) == "}") cycle
            if (t(i:i) /= ",") exit
            i = i + 1
            call skip_json_space(t, i)
            if (i > len(t)) exit
            if (t(i:i) == "}") exit
        end do
        call status%set(ERROR_ARGUMENT, "MyST: invalid content-block JSON metadata")
    end subroutine read_block_metadata

    subroutine skip_json_space(text, i)
        character(len=*), intent(in) :: text
        integer, intent(inout) :: i
        do while (i <= len(text))
            if (text(i:i) /= " " .and. text(i:i) /= achar(9)) return
            i = i + 1
        end do
    end subroutine skip_json_space

end module fplotlib_myst_metadata
