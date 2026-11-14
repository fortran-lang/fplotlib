program test_markdown
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_doctree
    use fplotlib_markdown
    use fplotlib_myst_metadata, only: read_scalar, read_block_metadata
    use fplotlib_docclass, only: layout_context_t, doc_typeset
    use fplotlib_report, only: layout_fragment
    use fplotlib_docresolve, only: resolve_document, resolved_document_t
    use fplotlib_scene, only: paged_document_t, frame_t
    implicit none
    character, parameter :: NL = achar(10), BS = achar(92)
    type(status_t) :: status
    type(doc_t) :: doc
    type(layout_context_t) :: context
    type(paged_document_t) :: pages
    type(frame_t) :: page
    integer :: failures, node, first, n, i, kind, page_break
    real(dp) :: w, h
    character(len=:), allocatable :: text, before

    failures = 0
    call oracle_cases()
    call resolution_check()
    call parsed_copy_check()
    call read_scalar("2026-11-14", text, kind, status)
    call ok()
    call expect(kind == META_STRING .and. text == "2026-11-14", "ISO dates are strings, not decimal numbers")
    call read_scalar("-1.25e+2", text, kind, status)
    call ok()
    call expect(kind == META_NUMBER, "decimal metadata grammar")
    call read_scalar("1-2", text, kind, status)
    call ok()
    call expect(kind == META_STRING, "arbitrary digits and signs are not numbers")
    call read_scalar('"quoted"#comment', text, kind, status)
    call expect(status%code == ERROR_ARGUMENT, "YAML comments require separation")
    call read_scalar("[a, b]", text, kind, status)
    call expect(status%code == ERROR_UNSUPPORTED, "unsupported YAML flow collections are diagnosed")
    call read_block_metadata('{"part":"\uD83D\uDE00"}', text, page_break, status)
    call ok()
    call expect(text == achar(240)//achar(159)//achar(152)//achar(128), "JSON Unicode surrogate pair")
    call read_block_metadata('{"part":"bad'//achar(9)//'control"}', text, page_break, status)
    call expect(status%code == ERROR_ARGUMENT, "JSON rejects unescaped control characters")
    call read_block_metadata('{"part":"\u  41"}', text, page_break, status)
    call expect(status%code == ERROR_ARGUMENT, "Unicode escapes require hex digits")
    call parse("---"//NL//"authors:"//NL//"  - name:"//NL//"  - name: Second"//NL//"---")
    call expect(meta_kind("authors.1.name") == META_NULL .and. meta_value("authors.2.name") == "Second", &
                "YAML sequences permit empty mapping values")
    call parse("---"//NL//"abstract: >-"//NL//"  First"//NL//"  second."//NL//NL//"  Third."//NL//"---")
    call expect(meta_value("abstract") == "First second."//NL//"Third.", "folded YAML paragraphs")
    call parse("---"//NL//"title: |+"//NL//NL//"  A"//NL//NL//"---")
    call expect(meta_value("title") == NL//"A"//NL//NL, "literal YAML leading and trailing newlines")
    call parse("---"//NL//"Not front matter.")
    call expect(doc%nmeta == 0, "unterminated front matter does not consume the document")
    call expect(doc%nodes(doc%nodes(1)%first)%kind == DOC_RULE, "initial thematic break remains a rule")

    call parse("````markdown"//NL//"```fortran"//NL//"print *, 1"//NL//"```"//NL//"````")
    node = doc%nodes(1)%first
    call expect(doc%nodes(node)%kind == DOC_CODE, "fenced code block")
    call expect(doc%nodes(node)%text == "```fortran"//NL//"print *, 1"//NL//"```"//NL, &
                "shorter nested fence stays literal")
    call parse("```"//NL//"~~~"//NL//"```")
    call expect(doc%nodes(doc%nodes(1)%first)%text == "~~~"//NL, "fence closing marker must match")
    call parse("```text"//NL//"unclosed code")
    call expect(doc%nodes(doc%nodes(1)%first)%text == "unclosed code"//NL, "ordinary code fence may end at EOF")

    call parse("*unclosed and foo_bar_baz")
    text = doc_plain(doc, 1, status)
    call ok()
    call expect(text == "*unclosed and foo_bar_baz", "unmatched emphasis stays literal")
    call parse("***nested*** and **strong *inside***")
    call expect(count_kind(IN_EMPH) == 2 .and. count_kind(IN_STRONG) == 2, "nested emphasis structure")
    call parse("``  x ` y  ``")
    node = doc%nodes(doc%nodes(1)%first)%first
    call expect(doc%nodes(node)%text == " x ` y ", "code spans strip one surrounding space only")
    call parse("`   `")
    node = doc%nodes(doc%nodes(1)%first)%first
    call expect(doc%nodes(node)%text == "   ", "CommonMark preserves code spans containing only spaces")
    call parse("\newpage and [text]{color=red}")
    text = doc_plain(doc, 1, status)
    call ok()
    call expect(text == "\newpage and [text]{color=red}", "removed document extensions remain literal")
    call parse("hard  "//NL//"break")
    call expect(count_kind(IN_BREAK) == 1, "two spaces create a hard break")
    call parse("literal -- dash ... and ""quotes""")
    text = doc_plain(doc, 1, status)
    call ok()
    call expect(text == 'literal -- dash ... and "quotes"', "optional typography transforms are not implicit")
    call parse("$ a $")
    node = doc%nodes(doc%nodes(1)%first)%first
    call expect(doc%nodes(node)%kind == IN_MATH .and. doc%nodes(node)%text == " a ", &
                "MyST dollar math permits delimiter-adjacent spaces")

    call parse("(target)="//NL//"# Heading"//NL//NL//"See @target and [](#target).")
    first = doc%nodes(1)%first
    call expect(doc%nodes(first)%id == "target", "MyST block target attaches to its heading")
    call expect(count_kind(IN_REF) == 2, "shorthand and link references")
    call parse("```{math}"//NL//":label: energy"//NL//"E=mc^2"//NL//"```")
    first = doc%nodes(1)%first
    call expect(doc%nodes(first)%kind == DOC_MATH .and. doc%nodes(first)%id == "energy", "math directive")
    call md_parse("```{unsupported}"//NL//"body"//NL//"```", doc, status)
    call expect(status%code == ERROR_UNSUPPORTED, "unknown directives are explicit errors")

    call parse("Before.")
    before = doc_plain(doc, 1, status)
    call ok()
    n = doc%n
    call md_append("Added."//NL//NL//"```{unsupported}"//NL//"body"//NL//"```", doc, status=status)
    call expect(status%code == ERROR_UNSUPPORTED .and. doc%n == n, "failed appends restore the tree")
    text = doc_plain(doc, 1, status)
    call ok()
    call expect(text == before, "failed appends preserve previous content")
    call md_append("After.", doc, status=status)
    call ok()
    call doc_validate(doc, status)
    call ok()

    call parse("| Left | Right |"//NL//"| :--- | ---: |"//NL//"| one | two |")
    node = doc%nodes(1)%first
    call expect(doc%nodes(node)%kind == DOC_TABLE, "plain pipe tables")
    i = doc%nodes(node)%num
    call expect(all(doc%tables(i)%alignment == ["l", "r"]), "pipe table alignment")

    call parse("---"//NL//"exports:"//NL//"  - format: pdf"//NL//"    template: letter"//NL// &
               "numbering: false"//NL//"---"//NL// &
               "+++ {""part"": ""sender""}"//NL//"Sender"//NL// &
               "+++ {""part"": ""recipient""}"//NL//"Recipient"//NL// &
               "+++ {""part"": ""opening""}"//NL//"Dear colleague,"//NL// &
               "+++"//NL//"Body."//NL// &
               "+++ {""part"": ""closing""}"//NL//"Regards,"//NL// &
               "+++ {""part"": ""signature""}"//NL//"Signature")
    call doc_typeset(context, doc, pages, status)
    call ok()
    call expect(pages%page_count() == 1, "letter template fits one page")
    call pages%page_size(1, w, h, status)
    call ok()
    call expect(w == 612.0_dp .and. h == 792.0_dp, "letter template paper")
    call pages%page_frame(1, page, status)
    call ok()
    text = page%source_text(status)
    call ok()
    call expect(index(text, "Sender") > 0 .and. index(text, "Signature") > 0, "letter parts reach the page")

    call parse("---"//NL//"title: Invitation"//NL//"exports:"//NL//"  - format: pdf"//NL// &
               "    template: invitation"//NL//"numbering: false"//NL//"---"//NL// &
               "+++ {""part"": ""intro""}"//NL//"You are invited."//NL// &
               "+++"//NL//"Details."//NL//"+++ {""part"": ""reply""}"//NL//"Please reply.")
    call doc_typeset(context, doc, pages, status)
    call ok()
    call expect(pages%page_count() == 1, "invitation template fits one page")
    call pages%page_size(1, w, h, status)
    call ok()
    call expect(w == 360.0_dp .and. h == 504.0_dp, "invitation template paper")

    call parse("```{math}"//NL//":label: energy"//NL//"E=mc^2"//NL//"```"//NL//NL//"See @energy.")
    call doc_typeset(context, doc, pages, status)
    call ok()
    call pages%page_frame(1, page, status)
    call ok()
    text = page%source_text(status)
    call ok()
    call expect(index(text, "See (1).") > 0, "equation reference formatting does not depend on an eq prefix")

    call parse("---"//NL//"numbering:"//NL//"  headings: true"//NL//"---"//NL// &
               "(eq:section)="//NL//"# Heading"//NL//NL// &
               "```{math}"//NL//":label: energy"//NL//"E=mc^2"//NL//"```"//NL//NL// &
               "See @eq:section, {ref}`eq:section` and [Equation {number}](#energy).")
    call doc_typeset(context, doc, pages, status)
    call ok()
    call pages%page_frame(1, page, status)
    call ok()
    text = page%source_text(status)
    call ok()
    call expect(index(text, "See Section 1, Heading and Equation 1.") > 0, "typed and custom references")
    call parse("(heading)="//NL//"# Heading"//NL//NL//"{eq}`custom <heading>`")
    call doc_typeset(context, doc, pages, status)
    call expect(status%code == ERROR_ARGUMENT, "custom eq role still requires an equation")
    call parse("# Heading"//NL//NL//"[](#)")
    call doc_typeset(context, doc, pages, status)
    call expect(status%code == ERROR_ARGUMENT, "empty references cannot resolve to an anonymous target")
    call parse("See @missing.")
    call doc_typeset(context, doc, pages, status)
    call expect(status%code == ERROR_LAYOUT, "unresolved reference is recoverable")
    call parse("(self)="//NL//"# @self")
    call doc_typeset(context, doc, pages, status)
    call expect(status%code == ERROR_LAYOUT, "cyclic reference display text is recoverable")
    call parse("+++ {""part"": ""abstract""}"//NL//"First abstract paragraph."//NL// &
               "+++ {""part"": ""abstract""}"//NL//"Second abstract paragraph."//NL//"+++"//NL//"Body.")
    call doc_typeset(context, doc, pages, status)
    call ok()
    call pages%page_frame(1, page, status)
    call ok()
    text = page%source_text(status)
    call ok()
    call expect(index(text, "First abstract paragraph.") > 0 .and. index(text, "Second abstract paragraph.") > 0, &
                "multiple abstract blocks are retained")
    call parse("---"//NL//"abstract: |"//NL//"  (same)="//NL//"  # Visible"//NL//"---"//NL// &
               "+++ {""part"": ""abstract""}"//NL//"(same)="//NL//"# Hidden"//NL//NL//"@missing"//NL// &
               "+++"//NL//"See {ref}`same`.")
    call doc_typeset(context, doc, pages, status)
    call ok()
    call pages%page_frame(1, page, status)
    call ok()
    text = page%source_text(status)
    call ok()
    call expect(index(text, "Hidden") == 0 .and. index(text, "See Visible.") > 0, &
                "overridden parts do not render or register hidden targets")
    call parse("```{math}"//NL//":label: é"//NL//"x"//NL//"```")
    call doc_typeset(context, doc, pages, status)
    call expect(status%code == ERROR_UNSUPPORTED, "non-ASCII target identifiers are explicitly outside the profile")
    call md_parse("[link]: https://example.org", doc, status)
    call expect(status%code == ERROR_UNSUPPORTED, "reference-definition links are explicitly unsupported")
    call layout_fragment(context, "---"//NL//"title: Hidden"//NL//"---"//NL//"Body", 100.0_dp, page, status=status)
    call expect(status%code == ERROR_UNSUPPORTED, "fragments do not silently discard document metadata")
    call bad_layout("paper: letter", ERROR_UNSUPPORTED)
    call bad_layout("title: true", ERROR_ARGUMENT)
    call bad_layout("exports:"//NL//"  - format: pdf"//NL//"    margin: 10 junk", ERROR_ARGUMENT)
    call bad_layout("exports:"//NL//"  - format: pdf"//NL//"    linestretch: 1 extra", ERROR_ARGUMENT)
    call bad_layout("exports:"//NL//"  - format: pdf"//NL//"    color: '#0 0000'", ERROR_ARGUMENT)
    call bad_layout("authors:"//NL//"  - name: Author"//NL//"    affiliation: Unsupported", ERROR_UNSUPPORTED)
    call bad_layout("abstract: First"//NL//"parts:"//NL//"  abstract: Second", ERROR_ARGUMENT)

    print "(a,i0)", "MyST failures: ", failures
    if (failures /= 0) error stop "MyST frontend failed"

contains

    subroutine resolution_check()
        type(resolved_document_t) :: resolved
        integer :: heading, paragraph, reference, child, old_n
        call doc_init(doc, status)
        call ok()
        heading = doc_add(doc, 1, DOC_HEADING, status)
        call ok()
        doc%nodes(heading)%num = 1
        doc%nodes(heading)%id = "literal"
        child = doc_add_text(doc, heading, IN_STR, "*literal*", status)
        call ok()
        paragraph = doc_add(doc, 1, DOC_PARA, status)
        call ok()
        reference = doc_add(doc, paragraph, IN_REF, status)
        call ok()
        doc%nodes(reference)%id = "literal"
        doc%nodes(reference)%num = REF_TITLE
        old_n = doc%n
        call resolve_document(doc, resolved, status)
        call ok()
        call expect(doc%n == old_n .and. doc%nodes(reference)%kind == IN_REF, "resolution preserves the source tree")
        child = resolved%content%nodes(reference)%first
        call expect(resolved%content%nodes(reference)%kind == DOC_INLINES .and. child > 0, &
                    "references lower to resolved inline content")
        call expect(resolved%content%nodes(child)%kind == IN_STR .and. &
                    resolved%content%nodes(child)%text == "*literal*", "programmatic titles are not parsed as Markdown")
        call doc_typeset(context, doc, pages, status)
        call ok()
        call pages%page_frame(1, page, status)
        call ok()
        text = page%source_text(status)
        call ok()
        call expect(index(text, "*literal*", back=.true.) > index(text, "*literal*"), &
                    "literal programmatic title survives reference layout")

        call parse("(heading)="//NL//"# Heading"//NL//NL//"[`{number}`](#heading)")
        call doc_typeset(context, doc, pages, status)
        call ok()
        call pages%page_frame(1, page, status)
        call ok()
        text = page%source_text(status)
        call ok()
        call expect(index(text, "{number}") > 0, "code-span placeholders do not require a target number")

        call parse("$$ x^2 \label{energy} $$")
        child = doc%nodes(1)%first
        before = doc%nodes(child)%text
        call resolve_document(doc, resolved, status)
        call ok()
        call expect(doc%nodes(child)%text == before, "equation preparation does not strip labels from source")
        call expect(index(resolved%content%nodes(child)%text, "\label") == 0 .and. &
                    resolved%nodes(child)%number == "1", "layout receives prepared math and its number")
    end subroutine resolution_check

    subroutine parsed_copy_check()
        type(doc_t) :: source
        type(frame_t) :: graphics
        integer :: child
        call parse("Existing."//NL//NL//"| C | D |"//NL//"|---|---|"//NL//"| old | cells |")
        call md_parse("**Copied** text."//NL//NL//"| A | B |"//NL//"|:--|--:|"//NL//"| one | two |", source, status)
        call ok()
        call graphics%init(11.0_dp, 13.0_dp, status=status)
        call ok()
        child = doc_add_frame(source, 1, graphics, status)
        call ok()
        call doc_append_children(doc, 1, source, 1, status)
        call ok()
        call doc_init(source, status)
        call ok()
        call graphics%set_size(99.0_dp, 99.0_dp, status)
        call ok()
        call doc_validate(doc, status)
        call ok()
        call expect(doc%ntables == 2 .and. doc%tables(2)%cells(1, 1) == "one", "parsed tables are copied with new handles")
        call expect(all(doc%tables(2)%alignment == ["l", "r"]), "parsed table alignment survives copying")
        child = doc%nodes(1)%last
        call doc%graphics%metrics(w, h, handle=doc%nodes(child)%num, status=status)
        call ok()
        call expect(w == 11.0_dp .and. h == 13.0_dp, "copied graphics handles retain owned source dimensions")
        text = doc_plain(doc, 1, status)
        call ok()
        call expect(index(text, "Copied text.") > 0, "parsed inline children survive source reset")
    end subroutine parsed_copy_check

    subroutine bad_layout(metadata, code)
        character(len=*), intent(in) :: metadata
        integer, intent(in) :: code
        call parse("---"//NL//metadata//NL//"---"//NL//"Body.")
        call doc_typeset(context, doc, pages, status)
        call expect(status%code == code, "reject invalid metadata: "//metadata)
    end subroutine bad_layout

    function meta_value(key) result(value)
        character(len=*), intent(in) :: key
        character(len=:), allocatable :: value
        integer :: j
        value = ""
        do j = 1, doc%nmeta
            if (doc%meta(j)%key == key) value = doc%meta(j)%value
        end do
    end function meta_value

    integer function meta_kind(key) result(value)
        character(len=*), intent(in) :: key
        integer :: j
        value = 0
        do j = 1, doc%nmeta
            if (doc%meta(j)%key == key) value = doc%meta(j)%kind
        end do
    end function meta_kind

    subroutine oracle_cases()
        character(len=16384) :: line
        character(len=:), allocatable :: source, expected, actual, name
        integer :: unit, ios, kind
        open (newunit=unit, file="tests/myst_refs.txt", status="old", action="read")
        do
            read (unit, "(a)", iostat=ios) line
            if (ios < 0) exit
            if (ios /= 0) error stop "reading MyST oracle"
            if (line(1:1) == "#") cycle
            name = trim(line)
            read (unit, "(a)") line
            call read_scalar(trim(line), source, kind, status)
            call ok()
            read (unit, "(a)") line
            expected = trim(line)
            call md_parse(source, doc, status)
            if (.not. status%ok()) then
                call expect(.false., name//": "//status%message)
                cycle
            end if
            call doc_validate(doc, status)
            call ok()
            actual = ast_node(1)
            call expect(actual == expected, "oracle "//name)
            if (actual /= expected) then
                print "(a)", "expected "//expected
                print "(a)", "actual   "//actual
            end if
        end do
        close (unit)
    end subroutine oracle_cases

    function quoted(value) result(out)
        character(len=*), intent(in) :: value
        character(len=:), allocatable :: out
        character(len=4) :: hex
        integer :: j, cp
        out = '"'
        do j = 1, len(value)
            cp = iachar(value(j:j))
            select case (value(j:j))
            case ('"', BS)
                out = out//BS//value(j:j)
            case (NL)
                out = out//BS//"n"
            case (achar(9))
                out = out//BS//"t"
            case (achar(13))
                out = out//BS//"r"
            case default
                if (cp < 32) then
                    write (hex, "(z4.4)") cp
                    out = out//BS//"u"//hex
                else
                    out = out//value(j:j)
                end if
            end select
        end do
        out = out//'"'
    end function quoted

    function integer_text(value) result(out)
        integer, intent(in) :: value
        character(len=:), allocatable :: out
        character(len=24) :: buffer
        write (buffer, "(i0)") value
        out = trim(buffer)
    end function integer_text

    function boolean_text(value) result(out)
        logical, intent(in) :: value
        character(len=:), allocatable :: out
        out = "false"
        if (value) out = "true"
    end function boolean_text

    function strip(value) result(out)
        character(len=*), intent(in) :: value
        character(len=:), allocatable :: out
        integer :: a, b
        a = 1
        b = len(value)
        do while (a <= b)
            if (scan(value(a:a), " "//NL//achar(9)//achar(13)) == 0) exit
            a = a + 1
        end do
        do while (b >= a)
            if (scan(value(b:b), " "//NL//achar(9)//achar(13)) == 0) exit
            b = b - 1
        end do
        out = value(a:b)
    end function strip

    recursive function ast_children(parent) result(out)
        integer, intent(in) :: parent
        character(len=:), allocatable :: out, pending, value
        integer :: child
        out = ""
        pending = ""
        child = doc%nodes(parent)%first
        do while (child > 0)
            if (doc%nodes(child)%kind == IN_STR) then
                pending = pending//doc%nodes(child)%text
            else if (doc%nodes(child)%kind == IN_SPACE) then
                pending = pending//" "
            else
                if (len(pending) > 0) then
                    call comma(out, '["text",'//quoted(pending)//']')
                    pending = ""
                end if
                if (doc%nodes(child)%kind == DOC_DIV .and. doc%nodes(child)%id == "" .and. &
                    doc%nodes(child)%part == "" .and. doc%nodes(child)%break_before == 0) then
                    value = ast_children(child)
                    value = value(2:len(value) - 1)
                else
                    value = ast_node(child)
                end if
                if (len(value) > 0) call comma(out, value)
            end if
            child = doc%nodes(child)%next
        end do
        if (len(pending) > 0) call comma(out, '["text",'//quoted(pending)//']')
        out = "["//out//"]"
    end function ast_children

    subroutine comma(out, value)
        character(len=:), allocatable, intent(inout) :: out
        character(len=*), intent(in) :: value
        if (len(out) > 0) out = out//","
        out = out//value
    end subroutine comma

    recursive function ast_node(k) result(out)
        integer, intent(in) :: k
        character(len=:), allocatable :: out, value, aligns, rows, row
        integer :: t, r, c
        select case (doc%nodes(k)%kind)
        case (DOC_ROOT)
            out = '["root",'//ast_children(k)//']'
        case (DOC_PARA)
            out = '["p",'//quoted(doc%nodes(k)%id)//','//ast_children(k)//']'
        case (DOC_HEADING)
            out = '["h",'//integer_text(doc%nodes(k)%num)//','//quoted(doc%nodes(k)%id)//','//ast_children(k)//']'
        case (IN_EMPH)
            out = '["em",'//ast_children(k)//']'
        case (IN_STRONG)
            out = '["strong",'//ast_children(k)//']'
        case (IN_CODE)
            out = '["code",'//quoted(doc%nodes(k)%text)//']'
        case (IN_MATH)
            if (doc%nodes(k)%display) then
                out = '["display",'//quoted(doc%nodes(k)%id)//','//boolean_text(doc%nodes(k)%enumerated)//','// &
                      boolean_text(doc%nodes(k)%enum_set)//','//quoted(strip(doc%nodes(k)%text))//']'
            else
                out = '["math",'//quoted(doc%nodes(k)%text)//']'
            end if
        case (IN_BREAK)
            out = '["break"]'
        case (IN_REF)
            out = '["ref",'//integer_text(doc%nodes(k)%num)//','//quoted(doc%nodes(k)%id)//','// &
                  quoted(doc%nodes(k)%text)//']'
        case (IN_LINK)
            out = '["link",'//quoted(doc%nodes(k)%text)//','//ast_children(k)//']'
        case (DOC_CODE)
            value = doc%nodes(k)%text
            if (len(value) > 0) then
                if (value(len(value):) == NL) value = value(1:len(value) - 1)
            end if
            out = '["pre",'//quoted(doc%nodes(k)%id)//','//quoted(doc%nodes(k)%language)//','//quoted(value)//']'
        case (DOC_MATH)
            out = '["display",'//quoted(doc%nodes(k)%id)//','//boolean_text(doc%nodes(k)%enumerated)//','// &
                  boolean_text(doc%nodes(k)%enum_set)//','//quoted(strip(doc%nodes(k)%text))//']'
        case (DOC_RULE)
            out = '["rule",'//quoted(doc%nodes(k)%id)//']'
        case (DOC_QUOTE)
            out = '["quote",'//quoted(doc%nodes(k)%id)//','//ast_children(k)//']'
        case (DOC_LIST)
            out = '["list",'//boolean_text(doc%nodes(k)%ordered)//','//integer_text(doc%nodes(k)%num)//','// &
                  boolean_text(doc%nodes(k)%tight)//','//quoted(doc%nodes(k)%id)//','//ast_children(k)//']'
        case (DOC_ITEM)
            out = '["item",'//ast_children(k)//']'
        case (DOC_DIV, DOC_PART)
            out = '["block",'//quoted(doc%nodes(k)%id)//','//quoted(doc%nodes(k)%part)//','// &
                  integer_text(doc%nodes(k)%break_before)//','//ast_children(k)//']'
        case (DOC_TABLE)
            t = doc%nodes(k)%num
            aligns = ""
            rows = ""
            do c = 1, size(doc%tables(t)%headers)
                call comma(aligns, quoted(doc%tables(t)%alignment(c)))
            end do
            do r = 0, size(doc%tables(t)%cells, 1)
                row = ""
                do c = 1, size(doc%tables(t)%headers)
                    value = doc%tables(t)%headers(c)
                    if (r > 0) value = doc%tables(t)%cells(r, c)
                    call comma(row, quoted(trim(value)))
                end do
                call comma(rows, "["//row//"]")
            end do
            out = '["table",'//quoted(doc%nodes(k)%id)//',['//aligns//'],['//rows//']]'
        case default
            error stop "unexpected oracle node"
        end select
    end function ast_node

    subroutine parse(source)
        character(len=*), intent(in) :: source
        call md_parse(source, doc, status)
        call ok()
        call doc_validate(doc, status)
        call ok()
    end subroutine parse

    subroutine ok()
        if (status%ok()) return
        print "(a)", status%message
        error stop "unexpected MyST error"
    end subroutine ok

    subroutine expect(condition, message)
        logical, intent(in) :: condition
        character(len=*), intent(in) :: message
        if (condition) return
        failures = failures + 1
        print "(a)", "FAIL "//message
    end subroutine expect

    integer function count_kind(kind) result(count)
        integer, intent(in) :: kind
        integer :: j
        count = 0
        do j = 1, doc%n
            if (doc%nodes(j)%kind == kind) count = count + 1
        end do
    end function count_kind

end program test_markdown
