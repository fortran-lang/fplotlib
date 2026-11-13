! fplotlib_markdown -- read a document written in Markdown into a tree.
!
! The input is Markdown as Pandoc reads it, with TeX math: $...$ inline and
! $$...$$ displayed. md_parse turns it into an fplotlib_doctree tree, which
! a document class (fplotlib_docclass) then sets.
!
! Blocks: a YAML front matter between --- lines (its keys are the class's:
! title, author, date, abstract, paper, fontsize, margin, ...); ATX headings
! (# to ####) and setext ones, with an {#id}; paragraphs; bullet and
! ordered lists, nested; block quotes; fenced code; thematic breaks;
! Pandoc's fenced divs (::: {.center size=24pt color=navy}); and, on a
! line of their own, the TeX commands \newpage, \pagebreak, \clearpage,
! \vfill, \vspace{...}, \vspace*{...}, \bigskip, \medskip and \smallskip.
!
! Inline: *emphasis*, **strong**, `code`, [links](url), Pandoc's bracketed
! spans ([text]{color=red size=1.2em .bold}), \textbf, \textit and \emph,
! hard line breaks (a backslash or two spaces at the end of a line, or
! <br>), "smart" quotes, -- and --- as dashes, ... as an ellipsis, a
! backslash and a space as a no-break space, \hfill, \quad, \qquad, \TeX
! and \LaTeX, and cross references: a displayed formula followed by
! {#eq:name} or containing \label{name} is numbered, and @eq:name,
! @sec:name, \eqref{name} and \ref{name} refer to a formula or a heading.
module fplotlib_markdown
    use fplotlib_style, only: utf8_next
    use fplotlib_doctree
    implicit none
    private

    public :: md_parse, md_append

    character, parameter :: BS = achar(92), NL = achar(10)
    character(len=2), parameter :: NBSP = achar(194)//achar(160)

    type :: line_t
        character(len=:), allocatable :: s
    end type line_t

contains

    ! Read text, a Markdown document, into doc.
    subroutine md_parse(text, doc)
        character(len=*), intent(in) :: text
        type(doc_t), intent(out) :: doc
        type(line_t), allocatable :: lines(:)
        integer :: n, first

        call split_lines(text, lines, n)
        call doc_init(doc)
        first = 1
        call front_matter(doc, lines, n, first)
        if (first <= n) call blocks(doc, 1, lines(first:n), n - first + 1)
    end subroutine md_parse

    ! Append ordinary blocks to an existing tree, e.g. after a supplied plot.
    subroutine md_append(text, doc, parent)
        character(len=*), intent(in) :: text
        type(doc_t), intent(inout) :: doc
        integer, intent(in), optional :: parent
        type(line_t), allocatable :: lines(:)
        integer :: n, p
        p = 1
        if (present(parent)) p = parent
        if (p < 1 .or. p > doc%n) error stop "md_append: invalid parent"
        call split_lines(text, lines, n)
        if (n > 0) call blocks(doc, p, lines, n)
    end subroutine md_append

    ! The front matter: "key: value" lines between two lines of ---. A key
    ! may come more than once (author).
    subroutine front_matter(doc, lines, n, first)
        type(doc_t), intent(inout) :: doc
        type(line_t), intent(in) :: lines(:)
        integer, intent(in) :: n
        integer, intent(inout) :: first
        integer :: i, j, c, k
        character(len=:), allocatable :: key, val

        if (n < 1) return
        if (trim(lines(1)%s) /= "---") return
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
            ! A value goes on over the indented lines after it, as does a
            ! block value (| or >).
            if (val == "|" .or. val == ">") val = ""
            do j = i + 1, n
                if (len(lines(j)%s) == 0) exit
                if (lines(j)%s(1:1) /= " ") exit
                if (len(val) > 0) val = val//" "
                val = val//trim(adjustl(lines(j)%s))
            end do
            k = doc_add(doc, 0, DOC_INLINES)
            call inlines(doc, k, val)
            call doc_add_meta(doc, key, val, k)
        end do
        first = i + 1
    end subroutine front_matter

    ! ------------------------------------------------------------------
    ! Blocks.
    ! ------------------------------------------------------------------

    ! The blocks of lines L(1:n), as children of parent.
    recursive subroutine blocks(doc, parent, L, n)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        integer :: i, j, k, lev, depth, node
        character(len=:), allocatable :: s, t, para, code
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
                call heading(doc, parent, heading_text(t, lev), lev)
                i = i + 1
            else if (is_fence(t)) then
                j = i + 1
                do while (j <= n)
                    if (is_fence(trim(adjustl(L(j)%s)))) exit
                    j = j + 1
                end do
                ! Each line ends with a newline.
                code = ""
                do k = i + 1, min(j - 1, n)
                    code = code//L(k)%s//NL
                end do
                node = doc_add_text(doc, parent, DOC_CODE, code)
                i = j + 1
            else if (starts(t, ":::")) then
                ! A fenced div runs to the matching :::, divs nesting.
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
                node = doc_add(doc, parent, DOC_DIV)
                doc%nodes(node)%attr = div_attrs(t)
                if (j - 1 > i) call blocks(doc, node, L(i + 1:j - 1), j - 1 - i)
                i = j + 1
            else if (t(1:1) == ">") then
                j = i
                do while (j <= n)
                    if (len_trim(L(j)%s) == 0) exit
                    j = j + 1
                end do
                call quote_block(doc, parent, L(i:j - 1), j - i)
                i = j
            else if (is_item(s, k, lev)) then
                call list_block(doc, parent, L, n, i, blank_before)
            else if (is_rule(t)) then
                node = doc_add(doc, parent, DOC_RULE)
                i = i + 1
            else if (is_raw_block(t)) then
                node = doc_add_text(doc, parent, DOC_RAW, t)
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
                            call heading(doc, parent, trim(adjustl(para)), 1)
                        else
                            call heading(doc, parent, trim(adjustl(para)), 2)
                        end if
                        i = j + 1
                        blank_before = .false.
                        cycle
                    end if
                end if
                call paragraph(doc, parent, para)
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

    ! A paragraph; \noindent at its start is kept as a raw inline.
    subroutine paragraph(doc, parent, text)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: s
        integer :: node, k
        s = trim(adjustl(text))
        node = doc_add(doc, parent, DOC_PARA)
        if (starts(s, BS//"noindent")) then
            k = doc_add_text(doc, node, IN_RAW, "noindent")
            s = trim(adjustl(s(10:)))
        end if
        call inlines(doc, node, s)
    end subroutine paragraph

    ! A heading: its text and its {#id}.
    subroutine heading(doc, parent, text, level)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, level
        character(len=*), intent(in) :: text
        integer :: node, a, b
        node = doc_add(doc, parent, DOC_HEADING)
        doc%nodes(node)%num = level
        a = index(text, "{#")
        if (a > 0) then
            b = index(text(a:), "}")
            if (b > 0) doc%nodes(node)%id = text(a + 2:a + b - 2)
        end if
        call inlines(doc, node, strip_attrs(text))
    end subroutine heading

    ! A list: its items, each from its marker to the next marker at the
    ! same indentation, or the end of the list. A tight list has no blank
    ! lines between its items; spaced is whether a blank line came before.
    recursive subroutine list_block(doc, parent, L, n, i, blank_before)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        integer, intent(inout) :: i
        logical, intent(in) :: blank_before
        type(line_t), allocatable :: item(:)
        integer :: j, k, col, kind, ni, start_num, ind0, m, ln, k2, lev2, list, it
        logical :: tight, blank
        character(len=:), allocatable :: s

        if (.not. is_item(L(i)%s, start_num, kind)) return
        ind0 = indent_of(L(i)%s)
        tight = .true.
        ! Is the list tight, and where does it end?
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

        list = doc_add(doc, parent, DOC_LIST)
        doc%nodes(list)%ordered = kind == 1
        doc%nodes(list)%num = start_num
        doc%nodes(list)%tight = tight
        doc%nodes(list)%spaced = blank_before
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
            it = doc_add(doc, list, DOC_ITEM)
            call blocks(doc, it, item, ni)
            deallocate (item)
            j = k
        end do
        i = m + 1
    end subroutine list_block

    ! A block quote: its lines without their >.
    recursive subroutine quote_block(doc, parent, L, n)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        type(line_t), intent(in) :: L(:)
        integer, intent(in) :: n
        type(line_t), allocatable :: q(:)
        integer :: k, node
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
        node = doc_add(doc, parent, DOC_QUOTE)
        call blocks(doc, node, q, n)
    end subroutine quote_block

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

    ! The attributes of a fenced div, ::: {.center size=20pt color=red},
    ! without the braces.
    function div_attrs(t) result(a)
        character(len=*), intent(in) :: t
        character(len=:), allocatable :: a
        a = trim(adjustl(t(4:)))
        if (len(a) > 0) then
            if (a(1:1) == "{") a = a(2:)
        end if
        if (len(a) > 0) then
            if (a(len(a):len(a)) == "}") a = a(1:len(a) - 1)
        end if
    end function div_attrs

    ! ------------------------------------------------------------------
    ! Inlines.
    ! ------------------------------------------------------------------

    ! The inlines of s, as children of parent. Emphasis opens and closes
    ! by Pandoc's rules for * and _; the nodes it opens nest.
    recursive subroutine inlines(doc, parent, s)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: w, cmd, arg
        integer :: i, j, k, r, cp, nb, node, a, b
        integer :: stack(64), ns
        logical :: em_open, strong_open, lf, rf
        character :: c, em_c, strong_c, prev, next

        w = ""
        ns = 1
        stack(1) = parent
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
                        node = doc_add(doc, stack(ns), IN_BREAK)
                        i = i + 3
                        cycle
                    end if
                end if
                call flush()
                node = doc%nodes(stack(ns))%last
                if (node > 0) then
                    if (doc%nodes(node)%kind /= IN_SPACE) node = doc_add(doc, stack(ns), IN_SPACE)
                else
                    node = doc_add(doc, stack(ns), IN_SPACE)
                end if
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
                        call close(IN_EMPH)
                    end if
                    if (r >= 2) then
                        strong_open = .false.
                        call close(IN_STRONG)
                    end if
                else if (lf .and. r <= 3) then
                    call flush()
                    if (r == 1 .or. r == 3) then
                        em_open = .true.
                        em_c = c
                        call open(IN_EMPH)
                    end if
                    if (r >= 2) then
                        strong_open = .true.
                        strong_c = c
                        call open(IN_STRONG)
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
                node = doc_add_text(doc, stack(ns), IN_CODE, &
                                    trim(adjustl(s(i + r:i + r + j - 2))))
                i = i + r + j - 1 + r
            case ("$")
                if (i < len(s)) then
                    if (s(i + 1:i + 1) == "$") then
                        ! A display, and the {#id} after it.
                        j = index(s(i + 2:), "$$")
                        if (j > 0) then
                            call flush()
                            node = doc_add_text(doc, stack(ns), IN_MATH, s(i + 2:i + j))
                            doc%nodes(node)%display = .true.
                            k = i + j + 3
                            a = k
                            do while (a <= len(s))
                                if (s(a:a) /= " ") exit
                                a = a + 1
                            end do
                            if (a + 1 <= len(s)) then
                                if (s(a:a + 1) == "{#") then
                                    b = index(s(a:), "}")
                                    if (b > 0) then
                                        doc%nodes(node)%id = s(a + 2:a + b - 2)
                                        doc%nodes(node)%num = 1
                                        k = a + b
                                    end if
                                end if
                            end if
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
                    node = doc_add_text(doc, stack(ns), IN_MATH, s(i + 1:j - 1))
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
                    node = doc_add(doc, stack(ns), IN_BREAK)
                    i = i + 2
                else if (next == " ") then
                    ! A no-break space, as Pandoc reads it.
                    w = w//NBSP
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
                            node = doc_add_text(doc, stack(ns), IN_LINK, s(j + 2:j + k - 1))
                            call inlines(doc, node, s(i + 1:j - 1))
                            i = j + k + 1
                            cycle
                        end if
                    else if (s(j + 1:j + 1) == "{") then
                        k = matching(s, j + 1)
                        if (k > 0) then
                            call flush()
                            node = doc_add(doc, stack(ns), IN_SPAN)
                            doc%nodes(node)%attr = s(j + 2:k - 1)
                            call inlines(doc, node, s(i + 1:j - 1))
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
                    node = doc_add(doc, stack(ns), IN_BREAK)
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
                ! A cross reference, @eq:name or @sec:name, after a space.
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
                if (j > i + 1 .and. white(prev)) then
                    call ref(s(i + 1:j - 1), REF_AT)
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
                call utf8_next(s, i, cp, nb)
                w = w//s(i:i + nb - 1)
                i = i + nb
            end select
        end do
        call flush()

    contains

        ! The text so far, a string.
        subroutine flush()
            integer :: kk
            if (len(w) == 0) return
            kk = doc_add_text(doc, stack(ns), IN_STR, w)
            w = ""
        end subroutine flush

        subroutine open(kind)
            integer, intent(in) :: kind
            if (ns == size(stack)) return
            ns = ns + 1
            stack(ns) = doc_add(doc, stack(ns - 1), kind)
        end subroutine open

        ! Close the innermost open node of the kind; those opened inside
        ! it go on after it.
        subroutine close(kind)
            integer, intent(in) :: kind
            integer :: p, q, kinds(64), nk
            p = ns
            do while (p > 1)
                if (doc%nodes(stack(p))%kind == kind) exit
                p = p - 1
            end do
            if (p == 1) return
            nk = 0
            do q = p + 1, ns
                nk = nk + 1
                kinds(nk) = doc%nodes(stack(q))%kind
            end do
            ns = p - 1
            do q = 1, nk
                call open(kinds(q))
            end do
        end subroutine close

        subroutine ref(name, form)
            character(len=*), intent(in) :: name
            integer, intent(in) :: form
            integer :: kk
            call flush()
            kk = doc_add(doc, stack(ns), IN_REF)
            doc%nodes(kk)%id = name
            doc%nodes(kk)%num = form
        end subroutine ref

        ! A command written in the text.
        recursive subroutine command(cmd, arg, k, j)
            character(len=*), intent(in) :: cmd, arg
            integer, intent(inout) :: k
            integer, intent(in) :: j
            integer :: kk
            select case (cmd)
            case ("hfill", "quad", "qquad", "TeX", "LaTeX")
                call flush()
                kk = doc_add_text(doc, stack(ns), IN_RAW, cmd)
                k = j
            case ("newline", "linebreak")
                call flush()
                kk = doc_add(doc, stack(ns), IN_BREAK)
                k = j
            case ("textbf", "emph", "textit", "textrm", "textsf", "textup")
                call flush()
                select case (cmd)
                case ("textbf")
                    kk = doc_add(doc, stack(ns), IN_STRONG)
                case ("emph")
                    kk = doc_add(doc, stack(ns), IN_EMPH)
                case default
                    kk = doc_add(doc, stack(ns), IN_SPAN)
                    if (cmd == "textit") doc%nodes(kk)%attr = ".italic"
                    if (cmd == "textrm" .or. cmd == "textup") doc%nodes(kk)%attr = ".upright"
                end select
                call inlines(doc, kk, arg)
            case ("eqref")
                call ref(arg, REF_EQ)
            case ("ref")
                call ref(arg, REF_PLAIN)
            case ("noindent", "par")
                k = j
            case default
                ! Unknown: written as it is, so that it is noticed.
                w = w//BS//cmd
                k = j
            end select
        end subroutine command

    end subroutine inlines

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

end module fplotlib_markdown
