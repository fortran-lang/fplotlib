! CommonMark inline structure and the native MyST math/reference roles.
module fplotlib_myst_inline
    use fplotlib_status
    use fplotlib_style, only: utf8_next, utf8_char
    use fplotlib_doctree
    use fplotlib_markdown_chars, only: markdown_punctuation
    implicit none
    private
    public :: md_inlines, md_label, md_plain, md_unescape
    character, parameter :: NL = achar(10), BS = achar(92)

    type :: delimiter_t
        integer :: node = 0, count = 0, previous = 0, following = 0
        character :: marker = " "
        logical :: opener = .false., closer = .false., active = .true.
    end type delimiter_t

contains

    pure logical function space_cp(cp)
        integer, intent(in) :: cp
        space_cp = (cp >= 9 .and. cp <= 13) .or. cp == 32 .or. cp == 160 .or. cp == 5760 .or. &
                   (cp >= 8192 .and. cp <= 8202) .or. cp == 8239 .or. cp == 8287 .or. cp == 12288
    end function space_cp

    integer function cp_at(text, i) result(cp)
        character(len=*), intent(in) :: text
        integer, intent(in) :: i
        integer :: n
        cp = 32
        if (i < 1 .or. i > len(text)) return
        call utf8_next(text, i, cp, n)
    end function cp_at

    integer function cp_before(text, i) result(cp)
        character(len=*), intent(in) :: text
        integer, intent(in) :: i
        integer :: j
        cp = 32
        j = i - 1
        if (j < 1) return
        do while (j > 1)
            if (iachar(text(j:j)) < 128 .or. iachar(text(j:j)) >= 192) exit
            j = j - 1
        end do
        cp = cp_at(text, j)
    end function cp_before

    pure logical function ascii_punctuation(c)
        character, intent(in) :: c
        integer :: cp
        cp = iachar(c)
        ascii_punctuation = (cp >= 33 .and. cp <= 47) .or. (cp >= 58 .and. cp <= 64) .or. &
                            (cp >= 91 .and. cp <= 96) .or. (cp >= 123 .and. cp <= 126)
    end function ascii_punctuation

    function md_label(text) result(label)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: label
        integer :: i, cp, n
        logical :: space
        label = ""
        space = .false.
        i = 1
        do while (i <= len(text))
            call utf8_next(text, i, cp, n)
            i = i + n
            select case (cp)
            case (9, 10, 13, 32)
                space = .true.
                cycle
            case (34, 39, 8216, 8217, 8220, 8221)
                cycle
            end select
            if (space .and. len(label) > 0) label = label//" "
            space = .false.
            if (cp >= 65 .and. cp <= 90) cp = cp + 32
            label = label//utf8_char(cp)
        end do
    end function md_label

    function fragment_label(text) result(label)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: label, value
        character(len=*), parameter :: HEX = "0123456789abcdef"
        integer :: i, a, b, cp
        character :: digit
        value = ""
        i = 1
        do while (i <= len(text))
            if (text(i:i) == "%" .and. i + 2 <= len(text)) then
                digit = text(i + 1:i + 1)
                cp = iachar(digit)
                if (cp >= 65 .and. cp <= 70) digit = achar(cp + 32)
                a = index(HEX, digit) - 1
                digit = text(i + 2:i + 2)
                cp = iachar(digit)
                if (cp >= 65 .and. cp <= 70) digit = achar(cp + 32)
                b = index(HEX, digit) - 1
                if (a >= 0 .and. b >= 0) then
                    value = value//achar(16*a + b)
                    i = i + 3
                    cycle
                end if
            end if
            value = value//text(i:i)
            i = i + 1
        end do
        label = md_label(value)
    end function fragment_label

    subroutine md_plain(doc, parent, text, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        character(len=*), intent(in) :: text
        type(status_t), intent(out) :: status
        integer :: i, first, node
        first = 1
        i = 1
        do while (i <= len(text))
            if (scan(text(i:i), " "//NL//achar(9)//achar(13)) == 0) then
                i = i + 1
                cycle
            end if
            if (i > first) then
                node = doc_add_text(doc, parent, IN_STR, text(first:i - 1), status)
                if (.not. status%ok()) return
            end if
            node = doc%nodes(parent)%last
            if (node > 0) then
                if (doc%nodes(node)%kind /= IN_SPACE .and. doc%nodes(node)%kind /= IN_BREAK) then
                    node = doc_add(doc, parent, IN_SPACE, status)
                    if (.not. status%ok()) return
                end if
            end if
            do while (i <= len(text))
                if (scan(text(i:i), " "//NL//achar(9)//achar(13)) == 0) exit
                i = i + 1
            end do
            first = i
        end do
        if (first <= len(text)) node = doc_add_text(doc, parent, IN_STR, text(first:), status)
    end subroutine md_plain

    subroutine entity(text, i, value, finish, status)
        character(len=*), intent(in) :: text
        integer, intent(in) :: i
        character(len=:), allocatable, intent(out) :: value
        integer, intent(out) :: finish
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: name
        integer :: j, cp, ios
        value = "&"
        finish = i + 1
        j = index(text(i:), ";")
        if (j < 3 .or. j > 34) return
        name = text(i + 1:i + j - 2)
        cp = -1
        if (name(1:1) == "#") then
            if (len(name) < 2) return
            if (name(2:2) == "x" .or. name(2:2) == "X") then
                if (len(name) < 3 .or. len(name) > 8) return
                if (verify(name(3:), "0123456789abcdefABCDEF") /= 0) return
                read (name(3:), "(z8)", iostat=ios) cp
            else
                if (len(name) > 8 .or. verify(name(2:), "0123456789") /= 0) return
                read (name(2:), *, iostat=ios) cp
            end if
            if (ios /= 0) return
            if (cp <= 8 .or. cp == 11 .or. (cp >= 14 .and. cp <= 31) .or. &
                (cp >= 127 .and. cp <= 159) .or. (cp >= 55296 .and. cp <= 57343) .or. &
                (cp >= 64976 .and. cp <= 65007) .or. iand(cp, 65535) >= 65534 .or. cp > 1114111) cp = 65533
            value = utf8_char(cp)
        else
            select case (name)
            case ("amp")
                value = "&"
            case ("lt")
                value = "<"
            case ("gt")
                value = ">"
            case ("quot")
                value = '"'
            case ("apos")
                value = "'"
            case ("nbsp")
                value = utf8_char(160)
            case default
                if (verify(name, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") == 0) &
                    call status%set(ERROR_UNSUPPORTED, "MyST: unsupported named entity; use Unicode or a numeric entity")
                return
            end select
        end if
        finish = i + j
    end subroutine entity

    subroutine md_unescape(text, value, status)
        character(len=*), intent(in) :: text
        character(len=:), allocatable, intent(out) :: value
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: part
        integer :: i, last
        value = ""
        i = 1
        do while (i <= len(text))
            if (text(i:i) == BS .and. i < len(text)) then
                if (ascii_punctuation(text(i + 1:i + 1))) then
                    value = value//text(i + 1:i + 1)
                    i = i + 2
                    cycle
                end if
            else if (text(i:i) == "&") then
                call entity(text, i, part, last, status)
                if (.not. status%ok()) return
                value = value//part
                i = last
                cycle
            end if
            value = value//text(i:i)
            i = i + 1
        end do
    end subroutine md_unescape

    integer function run_end(text, i, marker) result(j)
        character(len=*), intent(in) :: text
        integer, intent(in) :: i
        character, intent(in) :: marker
        j = i
        do while (j <= len(text))
            if (text(j:j) /= marker) exit
            j = j + 1
        end do
    end function run_end

    integer function code_close(text, first, count) result(j)
        character(len=*), intent(in) :: text
        integer, intent(in) :: first, count
        integer :: last
        j = first
        do while (j <= len(text))
            if (text(j:j) /= "`") then
                j = j + 1
                cycle
            end if
            last = run_end(text, j, "`")
            if (last - j == count) return
            j = last
        end do
        j = 0
    end function code_close

    integer function matching_bracket(text, start) result(last)
        character(len=*), intent(in) :: text
        integer, intent(in) :: start
        integer :: depth, j, count, close
        depth = 1
        j = start + 1
        last = 0
        do while (j <= len(text))
            select case (text(j:j))
            case (BS)
                j = j + 2
                cycle
            case ("`")
                count = run_end(text, j, "`") - j
                close = code_close(text, j + count, count)
                if (close > 0) then
                    j = close + count
                    cycle
                end if
            case ("[")
                depth = depth + 1
            case ("]")
                depth = depth - 1
                if (depth == 0) then
                    last = j
                    return
                end if
            end select
            j = j + 1
        end do
    end function matching_bracket

    subroutine link_destination(text, start, url, finish, status)
        character(len=*), intent(in) :: text
        integer, intent(in) :: start
        character(len=:), allocatable, intent(out) :: url
        integer, intent(out) :: finish
        type(status_t), intent(out) :: status
        integer :: i, first, depth
        character :: quote
        finish = 0
        url = ""
        i = start
        do while (i <= len(text))
            if (text(i:i) /= " " .and. text(i:i) /= NL .and. text(i:i) /= achar(9)) exit
            i = i + 1
        end do
        if (i > len(text)) return
        first = i
        if (text(i:i) == "<") then
            i = i + 1
            first = i
            do while (i <= len(text))
                if (text(i:i) == ">") exit
                if (text(i:i) == NL .or. text(i:i) == "<") return
                if (text(i:i) == BS) i = i + 1
                i = i + 1
            end do
            if (i > len(text)) return
            call md_unescape(text(first:i - 1), url, status)
            if (.not. status%ok()) return
            i = i + 1
        else
            depth = 0
            do while (i <= len(text))
                if (text(i:i) == BS .and. i < len(text)) then
                    if (ascii_punctuation(text(i + 1:i + 1))) then
                        i = i + 2
                        cycle
                    end if
                end if
                if (text(i:i) == "(") depth = depth + 1
                if (text(i:i) == ")") then
                    if (depth == 0) exit
                    depth = depth - 1
                end if
                if (scan(text(i:i), " "//NL//achar(9)) > 0) exit
                i = i + 1
            end do
            if (depth /= 0) return
            call md_unescape(text(first:i - 1), url, status)
            if (.not. status%ok()) return
        end if
        first = i
        do while (i <= len(text))
            if (scan(text(i:i), " "//NL//achar(9)) == 0) exit
            i = i + 1
        end do
        if (i > len(text)) return
        if (i > first .and. (text(i:i) == '"' .or. text(i:i) == "'" .or. text(i:i) == "(")) then
            quote = text(i:i)
            if (quote == "(") quote = ")"
            i = i + 1
            do while (i <= len(text))
                if (text(i:i) == quote) exit
                if (text(i:i) == BS) i = i + 1
                i = i + 1
            end do
            i = i + 1
            do while (i <= len(text))
                if (scan(text(i:i), " "//NL//achar(9)) == 0) exit
                i = i + 1
            end do
        end if
        if (i <= len(text)) then
            if (text(i:i) == ")") finish = i + 1
        end if
    end subroutine link_destination

    recursive subroutine md_inlines(doc, parent, text, status, level)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        character(len=*), intent(in) :: text
        type(status_t), intent(out) :: status
        integer, intent(in), optional :: level
        type(delimiter_t), allocatable :: delimiters(:)
        type(doc_t) :: link_text
        character(len=:), allocatable :: plain, value, url, role, label, display_text
        integer :: i, j, k, n, count, node, nd, prev, next, depth, finish, mark
        logical :: left, right, image
        depth = 0
        if (present(level)) depth = level
        if (depth >= 100) then
            call status%set(ERROR_UNSUPPORTED, "MyST: inline nesting exceeds the native profile")
            return
        end if
        allocate (delimiters(len(text)))
        nd = 0
        plain = ""
        i = 1
        do while (i <= len(text))
            select case (text(i:i))
            case (BS)
                if (i < len(text)) then
                    if (text(i + 1:i + 1) == NL) then
                        call flush(status)
                        if (.not. status%ok()) return
                        node = doc_add(doc, parent, IN_BREAK, status)
                        if (.not. status%ok()) return
                        i = i + 2
                        cycle
                    else if (ascii_punctuation(text(i + 1:i + 1))) then
                        plain = plain//text(i + 1:i + 1)
                        i = i + 2
                        cycle
                    end if
                end if
                plain = plain//BS
                i = i + 1
            case (" ")
                j = run_end(text, i, " ")
                if (j <= len(text)) then
                    if (text(j:j) == NL .and. j - i >= 2) then
                        call flush(status)
                        if (.not. status%ok()) return
                        node = doc_add(doc, parent, IN_BREAK, status)
                        if (.not. status%ok()) return
                        i = j + 1
                        cycle
                    end if
                end if
                plain = plain//text(i:j - 1)
                i = j
            case ("`")
                count = run_end(text, i, "`") - i
                j = code_close(text, i + count, count)
                if (j == 0) then
                    plain = plain//repeat("`", count)
                    i = i + count
                    cycle
                end if
                value = text(i + count:j - 1)
                do k = 1, len(value)
                    if (value(k:k) == NL) value(k:k) = " "
                end do
                if (len(value) > 1) then
                    if (value(1:1) == " " .and. value(len(value):) == " " .and. len_trim(value) > 0) &
                        value = value(2:len(value) - 1)
                end if
                call flush(status)
                if (.not. status%ok()) return
                node = doc_add_text(doc, parent, IN_CODE, value, status)
                if (.not. status%ok()) return
                i = j + count
            case ("*", "_")
                call flush(status)
                if (.not. status%ok()) return
                count = run_end(text, i, text(i:i)) - i
                prev = cp_before(text, i)
                next = cp_at(text, i + count)
                left = .not. space_cp(next) .and. &
                       (.not. markdown_punctuation(next) .or. space_cp(prev) .or. markdown_punctuation(prev))
                right = .not. space_cp(prev) .and. &
                        (.not. markdown_punctuation(prev) .or. space_cp(next) .or. markdown_punctuation(next))
                node = doc_add_text(doc, parent, IN_STR, repeat(text(i:i), count), status)
                if (.not. status%ok()) return
                nd = nd + 1
                delimiters(nd)%node = node
                delimiters(nd)%count = count
                delimiters(nd)%marker = text(i:i)
                delimiters(nd)%opener = left
                delimiters(nd)%closer = right
                if (text(i:i) == "_") then
                    delimiters(nd)%opener = left .and. (.not. right .or. markdown_punctuation(prev))
                    delimiters(nd)%closer = right .and. (.not. left .or. markdown_punctuation(next))
                end if
                delimiters(nd)%previous = nd - 1
                if (nd > 1) delimiters(nd - 1)%following = nd
                i = i + count
            case ("$")
                count = 1
                if (i < len(text)) then
                    if (text(i + 1:i + 1) == "$") count = 2
                end if
                j = i + count
                do while (j + count - 1 <= len(text))
                    if (text(j:j + count - 1) == repeat("$", count)) exit
                    if (text(j:j) == BS .and. j < len(text)) j = j + 1
                    j = j + 1
                end do
                if (j + count - 1 <= len(text) .and. j > i + count) then
                    call flush(status)
                    if (.not. status%ok()) return
                    node = doc_add_text(doc, parent, IN_MATH, text(i + count:j - 1), status)
                    if (.not. status%ok()) return
                    doc%nodes(node)%display = count == 2
                    i = j + count
                else
                    plain = plain//repeat("$", count)
                    i = i + count
                end if
            case ("{")
                j = index(text(i:), "}")
                if (j > 1) then
                    j = i + j - 1
                    if (j < len(text)) then
                        if (text(j + 1:j + 1) == "`") then
                            count = run_end(text, j + 1, "`") - j - 1
                            k = code_close(text, j + count + 1, count)
                            if (k > 0) then
                                role = text(i + 1:j - 1)
                                value = text(j + count + 1:k - 1)
                                call flush(status)
                                if (.not. status%ok()) return
                                select case (role)
                                case ("math")
                                    node = doc_add_text(doc, parent, IN_MATH, value, status)
                                case ("ref", "eq", "numref")
                                    node = doc_add(doc, parent, IN_REF, status)
                                    if (.not. status%ok()) return
                                    doc%nodes(node)%num = REF_TITLE
                                    if (role == "eq") doc%nodes(node)%num = REF_EQ
                                    if (role == "numref") doc%nodes(node)%num = REF_AUTO
                                    mark = index(value, "<", back=.true.)
                                    label = value
                                    if (mark > 0 .and. len(value) > mark) then
                                        if (value(len(value):) == ">") then
                                            label = value(mark + 1:len(value) - 1)
                                            doc%nodes(node)%text = trim(value(1:mark - 1))
                                        end if
                                    end if
                                    doc%nodes(node)%id = md_label(label)
                                    display_text = doc%nodes(node)%text
                                    if (len(display_text) > 0) then
                                        call md_inlines(doc, node, display_text, status, depth + 1)
                                        if (.not. status%ok()) return
                                    end if
                                case default
                                    call status%set(ERROR_UNSUPPORTED, "MyST: unsupported role: "//role)
                                end select
                                if (.not. status%ok()) return
                                i = k + count
                                cycle
                            end if
                        end if
                    end if
                end if
                plain = plain//"{"
                i = i + 1
            case ("[", "!")
                image = text(i:i) == "!"
                j = i
                if (image) j = j + 1
                if (j <= len(text)) then
                    if (text(j:j) == "[") then
                        mark = matching_bracket(text, j)
                        if (mark > 0 .and. mark < len(text)) then
                            if (text(mark + 1:mark + 1) == "(") then
                                call link_destination(text, mark + 2, url, finish, status)
                                if (.not. status%ok()) return
                                if (finish > 0) then
                                    if (image) then
                                        call status%set(ERROR_UNSUPPORTED, "MyST: image loading is unsupported; use include_figure")
                                        return
                                    end if
                                    call doc_init(link_text, status)
                                    if (.not. status%ok()) return
                                    call md_inlines(link_text, 1, text(j + 1:mark - 1), status, depth + 1)
                                    if (.not. status%ok()) return
                                    image = .false.
                                    do n = 2, link_text%n
                                        if (link_text%nodes(n)%kind == IN_LINK .or. link_text%nodes(n)%kind == IN_REF) &
                                            image = .true.
                                    end do
                                    if (image) then
                                        plain = plain//text(i:i)
                                        i = i + 1
                                        cycle
                                    end if
                                    call flush(status)
                                    if (.not. status%ok()) return
                                    n = IN_LINK
                                    if (len(url) > 0) then
                                        if (url(1:1) == "#") n = IN_REF
                                    end if
                                    node = doc_add_text(doc, parent, n, url, status)
                                    if (.not. status%ok()) return
                                    if (n == IN_REF) then
                                        doc%nodes(node)%id = fragment_label(url(2:))
                                        doc%nodes(node)%num = REF_AUTO
                                        doc%nodes(node)%text = ""
                                        if (mark > j + 1) then
                                            doc%nodes(node)%text = text(j + 1:mark - 1)
                                        end if
                                    end if
                                    call doc_append_children(doc, node, link_text, 1, status)
                                    if (.not. status%ok()) return
                                    i = finish
                                    cycle
                                end if
                            end if
                        end if
                    end if
                end if
                plain = plain//text(i:i)
                i = i + 1
            case ("@")
                j = i + 1
                do while (j <= len(text))
                    if (verify(text(j:j), "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:-.") /= 0) exit
                    j = j + 1
                end do
                do while (j > i + 1)
                    if (scan(text(j - 1:j - 1), ".:-") == 0) exit
                    j = j - 1
                end do
                prev = cp_before(text, i)
                if (j > i + 1 .and. (space_cp(prev) .or. prev == 40 .or. prev == 91)) then
                    call flush(status)
                    if (.not. status%ok()) return
                    node = doc_add(doc, parent, IN_REF, status)
                    if (.not. status%ok()) return
                    doc%nodes(node)%id = md_label(text(i + 1:j - 1))
                    doc%nodes(node)%num = REF_AUTO
                    i = j
                else
                    plain = plain//"@"
                    i = i + 1
                end if
            case ("<")
                j = index(text(i:), ">")
                if (j > 1) then
                    value = text(i + 1:i + j - 2)
                    if (value == "br" .or. value == "br/" .or. value == "br /") then
                        call flush(status)
                        if (.not. status%ok()) return
                        node = doc_add(doc, parent, IN_BREAK, status)
                        if (.not. status%ok()) return
                        i = i + j
                        cycle
                    end if
                    if (index(value, "://") > 0 .or. index(value, "@") > 0) then
                        if (scan(value, " "//NL//achar(9)//"<") == 0) then
                            call flush(status)
                            if (.not. status%ok()) return
                            url = value
                            if (index(value, "@") > 0 .and. index(value, "://") == 0) url = "mailto:"//value
                            node = doc_add_text(doc, parent, IN_LINK, url, status)
                            if (.not. status%ok()) return
                            call md_plain(doc, node, value, status)
                            if (.not. status%ok()) return
                            i = i + j
                            cycle
                        end if
                    end if
                    if (len(value) > 0) then
                        if (scan(value(1:1), "/!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") > 0) then
                            call status%set(ERROR_UNSUPPORTED, "MyST: raw HTML is outside the native profile")
                            return
                        end if
                    end if
                end if
                plain = plain//"<"
                i = i + 1
            case ("&")
                call entity(text, i, value, finish, status)
                if (.not. status%ok()) return
                plain = plain//value
                i = finish
            case default
                plain = plain//text(i:i)
                i = i + 1
            end select
        end do
        call flush(status)
        if (.not. status%ok()) return
        call emphasis(doc, parent, delimiters, nd, status)

    contains

        subroutine flush(status)
            type(status_t), intent(out) :: status
            if (len(plain) == 0) return
            call md_plain(doc, parent, plain, status)
            plain = ""
        end subroutine flush

    end subroutine md_inlines

    integer function preceding(doc, parent, node) result(previous)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent, node
        integer :: k
        previous = 0
        k = doc%nodes(parent)%first
        do while (k /= 0 .and. k /= node)
            previous = k
            k = doc%nodes(k)%next
        end do
    end function preceding

    subroutine unlink_node(doc, parent, node)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, node
        integer :: prev
        prev = preceding(doc, parent, node)
        if (prev == 0) then
            doc%nodes(parent)%first = doc%nodes(node)%next
        else
            doc%nodes(prev)%next = doc%nodes(node)%next
        end if
        if (doc%nodes(parent)%last == node) doc%nodes(parent)%last = prev
        doc%nodes(node)%next = 0
    end subroutine unlink_node

    recursive integer function inline_depth(doc, parent) result(depth)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        integer :: k
        depth = 0
        k = doc%nodes(parent)%first
        do while (k > 0)
            depth = max(depth, 1 + inline_depth(doc, k))
            k = doc%nodes(k)%next
        end do
    end function inline_depth

    subroutine emphasis(doc, parent, d, n, status)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, n
        type(delimiter_t), intent(inout) :: d(:)
        type(status_t), intent(out) :: status
        integer :: closer, opener, use_count, kind, node, first, last, k
        logical :: odd
        closer = 1
        do while (closer <= n .and. closer > 0)
            if (.not. d(closer)%closer) then
                closer = d(closer)%following
                cycle
            end if
            opener = d(closer)%previous
            do while (opener > 0)
                odd = (d(closer)%opener .or. d(opener)%closer) .and. &
                      mod(d(opener)%count + d(closer)%count, 3) == 0 .and. &
                      (mod(d(opener)%count, 3) /= 0 .or. mod(d(closer)%count, 3) /= 0)
                if (d(opener)%opener .and. d(opener)%marker == d(closer)%marker .and. .not. odd) exit
                opener = d(opener)%previous
            end do
            if (opener == 0) then
                closer = d(closer)%following
                cycle
            end if
            use_count = min(2, d(opener)%count, d(closer)%count)
            kind = merge(IN_STRONG, IN_EMPH, use_count == 2)
            first = doc%nodes(d(opener)%node)%next
            last = preceding(doc, parent, d(closer)%node)
            node = doc_add(doc, 0, kind, status)
            if (.not. status%ok()) return
            doc%nodes(node)%first = first
            doc%nodes(node)%last = last
            doc%nodes(last)%next = 0
            doc%nodes(d(opener)%node)%next = node
            doc%nodes(node)%next = d(closer)%node
            if (inline_depth(doc, node) > 100) then
                call status%set(ERROR_UNSUPPORTED, "MyST: emphasis nesting exceeds the native profile")
                return
            end if
            k = d(opener)%following
            do while (k /= closer)
                d(k)%active = .false.
                k = d(k)%following
            end do
            d(opener)%following = closer
            d(closer)%previous = opener
            d(opener)%count = d(opener)%count - use_count
            d(closer)%count = d(closer)%count - use_count
            doc%nodes(d(opener)%node)%text = repeat(d(opener)%marker, d(opener)%count)
            doc%nodes(d(closer)%node)%text = repeat(d(closer)%marker, d(closer)%count)
            if (d(opener)%count == 0) then
                call unlink_node(doc, parent, d(opener)%node)
                k = d(opener)%previous
                if (k > 0) d(k)%following = closer
                d(closer)%previous = k
                d(opener)%active = .false.
            end if
            if (d(closer)%count == 0) then
                call unlink_node(doc, parent, d(closer)%node)
                k = d(closer)%following
                if (d(closer)%previous > 0) d(d(closer)%previous)%following = k
                if (k > 0) d(k)%previous = d(closer)%previous
                d(closer)%active = .false.
                closer = k
            end if
        end do
    end subroutine emphasis

end module fplotlib_myst_inline
