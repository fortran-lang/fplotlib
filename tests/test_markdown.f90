! Documents set from Markdown, checked by what their pages say.
!
! Each case sets a small document with md_typeset and reads its pages back
! through a renderer that keeps the glyphs it is handed: a line is the
! glyphs of one baseline, left to right, with a space wherever two glyphs
! are further apart than the first one's advance. Pages are separated by
! a form feed. The face of every byte of that text is kept beside it, so
! that a case can ask whether a word came out italic.
module test_markdown
    use fplotlib_style, only: dp
    use fplotlib_render, only: renderer_t, glyphrun_t, paint_t, clip_t
    use fplotlib_scene, only: frame_t, recording_renderer_t
    use fplotlib_glyphs, only: glyph_char, glyph_face, glyph_adv, face_xheight, FACE_REGULAR, &
                               FACE_BOLD, FACE_ITALIC
    use fplotlib_markdown, only: md_document_t, md_typeset, md_typeset_files, md_typeset_box, &
                                 md_meta, md_directive_cb, md_directive_t, md_ctx_t, md_body_cb, &
                                 md_heading_cb, md_heading_t, md_blocks, md_option, md_figure_t
    use fplotlib_typeset, only: ts_page_count, ts_page_draw, ts_page_size, ts_box_height
    use fplotlib_io, only: write_bytes, read_bytes, dir_name, join_path
    use fplotlib_status, only: status_t, ERROR_IO
    use fplotlib, only: figure, plot, title, clf, close, typeset, typeset_file, &
                        named_figure, capture_figure, report_t, document_asset_t, &
                        new_report, markdown, include_figure, include_table, save, &
                        render_report
    implicit none
    private

    public :: markdown_check

    character, parameter :: NL = achar(10), FF = achar(12)
    character(len=*), parameter :: BULLET = achar(226)//achar(128)//achar(162)
    character(len=*), parameter :: DASH = achar(226)//achar(128)//achar(147)

    type, extends(renderer_t) :: text_renderer_t
        integer :: n = 0
        integer :: n_frames = 0, frame_depth = 0
        logical :: include_frames = .false.
        real(dp) :: last_mat(6) = 0.0_dp
        real(dp), allocatable :: x(:), y(:), adv(:)
        integer, allocatable :: cp(:), face(:)
    contains
        procedure :: open_canvas_impl => tr_open
        procedure :: close_canvas_impl => tr_close
        procedure :: draw_path_impl => tr_path
        procedure :: draw_rect_impl => tr_rect
        procedure :: draw_circle_impl => tr_circle
        procedure :: draw_markers_impl => tr_markers
        procedure :: draw_glyphs_impl => tr_glyphs
        procedure :: draw_image_impl => tr_image
        procedure :: begin_frame_impl => tr_begin_frame
        procedure :: end_frame_impl => tr_end_frame
    end type text_renderer_t

contains

    subroutine markdown_check(nfail)
        integer, intent(out) :: nfail
        integer :: ncase

        nfail = 0
        ncase = 0
        call numbering_cases(ncase, nfail)
        call role_cases(ncase, nfail)
        call display_cases(ncase, nfail)
        call page_cases(ncase, nfail)
        call front_matter_cases(ncase, nfail)
        call emphasis_cases(ncase, nfail)
        call target_cases(ncase, nfail)
        call tab_cases(ncase, nfail)
        call abstract_cases(ncase, nfail)
        call label_cases(ncase, nfail)
        call heading_cases(ncase, nfail)
        call directive_cases(ncase, nfail)
        call heading_template_cases(ncase, nfail)
        call nesting_cases(ncase, nfail)
        call two_docs_cases(ncase, nfail)
        call bugfix_cases(ncase, nfail)
        call file_cases(ncase, nfail)
        call figure_cases(ncase, nfail)
        call box_cases(ncase, nfail)
        call table_cases(ncase, nfail)
        call report_cases(ncase, nfail)
        print "(a,i0,a,i0)", "markdown: ", ncase, " checks, failures = ", nfail
    end subroutine markdown_check

    ! Sections and displays are numbered as they are set, and references
    ! give those numbers, whatever else the text holds.
    subroutine numbering_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        ! A "#" line in a fenced code block is code, not a heading.
        call set_doc("---"//NL//"numbersections: true"//NL//"---"//NL// &
                     "# One"//NL//NL//"```sh"//NL//"# install"//NL//"make"//NL//"```"//NL//NL// &
                     "(sec:two)="//NL//"# Two"//NL//NL//"Two is {numref}`sec:two`.", t, f)
        call expect("code comment", t, "Two is Section 2.", ncase, nfail)
        ! $$ in a code block or a code span is no display.
        call set_doc("```"//NL//"$$ x $$ (eq:fake)"//NL//"```"//NL//NL// &
                     "Code `$$ z $$ (eq:z)` and $$ y $$ (eq:real)"//NL// &
                     "Real {eq}`eq:real`, fake {eq}`eq:fake`.", t, f)
        call expect("code display", t, "Real (1), fake ??.", ncase, nfail)
        ! An underlined heading is numbered as a # heading is.
        call set_doc("---"//NL//"numbersections: true"//NL//"---"//NL// &
                     "One"//NL//"==="//NL//NL//"(sec:b)="//NL//"# Two"//NL//NL// &
                     "Two is {numref}`sec:b`.", t, f)
        call expect("setext heading", t, "Two is Section 2.", ncase, nfail)
        ! So is a heading in a quotation.
        call set_doc("---"//NL//"numbersections: true"//NL//"---"//NL// &
                     "> # Quoted"//NL//NL//"(sec:c)="//NL//"# After"//NL//NL// &
                     "After is {numref}`sec:c`.", t, f)
        call expect("quoted heading", t, "After is Section 2.", ncase, nfail)
        ! A heading set without a number has none to refer to, but its
        ! title can be.
        call set_doc("---"//NL//"numbersections: true"//NL//"---"//NL// &
                     "# A"//NL//"## B"//NL//"### C"//NL//"(sec:d)="//NL//"#### D"//NL//NL// &
                     "Deep {numref}`sec:d`, {ref}`sec:d`.", t, f)
        call expect("deep heading", t, "Deep ??, D.", ncase, nfail)
        call set_doc("(sec:a)="//NL//"# Alpha"//NL//NL//"Plain {numref}`sec:a`, {ref}`sec:a`.", &
                     t, f)
        call expect("unnumbered heading", t, "Plain ??, Alpha.", ncase, nfail)
        ! In a book, displays are numbered within their chapter.
        call set_doc("---"//NL//"chapters: true"//NL//"---"//NL// &
                     "# A"//NL//NL//"$$ x $$ (eq:a)"//NL//NL//"# B"//NL//NL// &
                     "$$ y $$ (eq:b)"//NL//NL//"See {eq}`eq:a` and {eq}`eq:b`.", t, f)
        call expect("chapter displays", t, "See (1.1) and (2.1).", ncase, nfail)
    end subroutine numbering_cases

    ! The roles write what Sphinx writes for them, a text of their own
    ! included.
    subroutine role_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("---"//NL//"numbersections: true"//NL//"---"//NL// &
                     "(sec:a)="//NL//"# Alpha"//NL//NL//"$$ x $$ (eq:x)"//NL//NL// &
                     "{ref}`the intro <sec:a>`; {numref}`Part %s <sec:a>`;"//NL// &
                     "{numref}`{name} ({number}) <sec:a>`; {numref}`eq:x`; {eq}`eq:x`;"//NL// &
                     "{ref}`eq:x`; {eq}`sec:a`; {ref}`gone`; {ref}`kept <gone>`.", t, f)
        call expect("explicit ref", t, "the intro; Part 1;", ncase, nfail)
        call expect("numref fields", t, "Alpha (1); (1); (1);", ncase, nfail)
        call expect("unresolved", t, "??; ??; ??; kept.", ncase, nfail)
    end subroutine role_cases

    ! A display goes on over its lines whatever they start with, and a $$
    ! that is not closed is text.
    subroutine display_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("Energy"//NL//"$$ E = mc^2"//NL//"+ \frac{p^2}{2m}"//NL//"- V"//NL// &
                     "> 0 $$"//NL//"follows.", t, f)
        call reject("display source", t, "frac", ncase, nfail)
        call reject("display item", t, BULLET, ncase, nfail)
        call reject("display dollars", t, "$", ncase, nfail)
        call expect("display text", t, NL//"follows.", ncase, nfail)
        call set_doc("Costs $$ 5 here.", t, f)
        call expect("unclosed display", t, "Costs $$ 5 here.", ncase, nfail)
    end subroutine display_cases

    ! A heading and the line after it that do not fit at the foot of the
    ! last page go onto a new page, not into the margin.
    subroutine page_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f, md
        real(dp) :: lowest
        integer :: k

        md = "---"//NL//"paper: 300 x 322"//NL//"pagenumbers: false"//NL//"---"//NL
        do k = 1, 30
            md = md//"Line."//NL//NL
        end do
        call set_doc(md//"# Last"//NL//NL//"Final words.", t, f, lowest)
        ncase = ncase + 1
        if (lowest > 322.0_dp - 72.0_dp) then
            nfail = nfail + 1
            print "(a,f0.1,a)", "  FAIL markdown last page: a line at ", lowest, &
                " is below the text, which ends at 250"
        end if
        call expect("last page", t, FF//"Last"//NL//"Final words.", ncase, nfail)
    end subroutine page_cases

    ! Front matter is front matter only when it is closed; its em is the
    ! type size wherever that is given; its lists are lists.
    subroutine front_matter_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f
        real(dp) :: left
        character(len=300) :: long
        type(md_document_t) :: d

        call set_doc("---"//NL//"title: x"//NL//NL//"Hello world.", t, f)
        call expect("unclosed front matter", t, "title: x"//NL//"Hello world.", ncase, nfail)
        call set_doc("---"//NL//"margin: 2em"//NL//"fontsize: 20pt"//NL//"align: left"//NL// &
                     "---"//NL//"Text.", t, f, leftmost=left)
        call near("em before fontsize", left, 40.0_dp, ncase, nfail)
        call set_doc("---"//NL//"margin: 3pc"//NL//"align: left"//NL//"---"//NL//"Text.", &
                     t, f, leftmost=left)
        call near("picas", left, 36.0_dp, ncase, nfail)
        call set_doc("---"//NL//"margin: 3qq"//NL//"align: left"//NL//"---"//NL//"Text.", &
                     t, f, leftmost=left)
        call near("unknown unit", left, 72.0_dp, ncase, nfail)
        call set_doc("---"//NL//"title: T"//NL//"author:"//NL//"  - Ada"//NL//"  - Charles"//NL// &
                     "---"//NL//"Text.", t, f)
        call expect("author list", t, "T"//NL//"Ada"//NL//"Charles"//NL, ncase, nfail)
        call set_doc("---"//NL//"title: T"//NL//"authors: [Ada, ""King, Charles""]"//NL// &
                     "---"//NL//"Text.", t, f)
        call expect("flow list", t, "T"//NL//"Ada"//NL//"King, Charles"//NL, ncase, nfail)
        long = repeat("w", 300)
        call md_typeset(d, "---"//NL//"note: "//long//NL//"---"//NL//"Text.")
        ncase = ncase + 1
        if (md_meta(d, "note") /= long) then
            nfail = nfail + 1
            print "(a,i0,a)", "  FAIL markdown long value: md_meta gave ", &
                len(md_meta(d, "note")), " characters of 300"
        end if
    end subroutine front_matter_cases

    ! A * or _ with nothing to close it is text; emphasis that is closed
    ! is italic or bold.
    subroutine emphasis_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("Twice 2*3 is six, upright; _private stays; *it* and **bold *both* bold**;"// &
                     " $a*b$ *x `y*` z*.", t, f)
        call expect("lone star", t, "Twice 2*3 is six, upright; _private stays;", ncase, nfail)
        call face("upright", t, f, "upright", FACE_REGULAR, ncase, nfail)
        call face("closed emphasis", t, f, "it and", FACE_ITALIC, ncase, nfail)
        call face("strong", t, f, "bold both", FACE_BOLD, ncase, nfail)
        call face("past code and math", t, f, "x y* z", FACE_ITALIC, ncase, nfail)
    end subroutine emphasis_cases

    ! A target is not set: it labels the block after it, a heading with
    ! its number and title.
    subroutine target_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("---"//NL//"numbersections: true"//NL//"---"//NL// &
                     "(par:x)="//NL//"A paragraph."//NL//NL// &
                     "(sec:a)="//NL//NL//"# Alpha"//NL//NL// &
                     "(sec:s)="//NL//"(sec:t)="//NL//"Setext"//NL//"------"//NL//NL// &
                     "See {ref}`this one <par:x>`, {numref}`par:x`, {ref}`sec:a`,"// &
                     " {numref}`sec:s`, {ref}`sec:t`."//NL//NL//"(end)=", t, f)
        call reject("target text", t, ")=", ncase, nfail)
        call expect("targets", t, "See this one, ??, Alpha, Section 1.1, Setext.", ncase, nfail)
    end subroutine target_cases

    ! A tab goes to the next stop of four columns, so a tab before an item
    ! nests it.
    subroutine tab_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("- a"//NL//achar(9)//"- nested b"//NL//"- c", t, f)
        call expect("tab nesting", t, BULLET//" a"//NL//DASH//" nested b"//NL//BULLET//" c", &
                     ncase, nfail)
    end subroutine tab_cases

    ! An abstract is set without a title as with one.
    subroutine abstract_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("---"//NL//"abstract: What this is about."//NL//"---"//NL//"Body.", t, f)
        call expect("abstract alone", t, "Abstract"//NL//"What this is about."//NL//"Body.", &
                     ncase, nfail)
    end subroutine abstract_cases

    ! An item that begins with a list, or with code, keeps its label, on
    ! its first line.
    subroutine label_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("- - inner"//NL//"- second"//NL//NL//"1. - x"//NL//NL// &
                     "- ```"//NL//"  code"//NL//"  ```", t, f)
        call expect("item of a list", t, BULLET//" "//DASH//" inner"//NL//BULLET//" second", &
                     ncase, nfail)
        call expect("numbered item", t, "1. "//BULLET//" x", ncase, nfail)
        call expect("item of code", t, BULLET//" code", ncase, nfail)
    end subroutine label_cases

    ! A \subsubsection's lines are \baselineskip apart.
    subroutine heading_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f
        real(dp), allocatable :: ys(:)
        real(dp) :: ex

        call set_doc("---"//NL//"paper: 200 x 300"//NL//"margin: 20pt"//NL//"pagenumbers: false"// &
                     NL//"---"//NL//"### A subsubsection long enough for two lines", t, f, &
                     baselines=ys)
        ncase = ncase + 1
        if (size(ys) /= 2) then
            nfail = nfail + 1
            print "(a,i0,a)", "  FAIL markdown subsubsection: ", size(ys), " lines in:"
            print "(a)", t
        else
            call near("subsubsection leading", ys(2) - ys(1), 12.0_dp, ncase, nfail)
        end if
        ! A heading straight after another adds no space of its own; after
        ! text, it adds 3.25ex.
        ex = face_xheight(FACE_REGULAR)*10.0_dp
        call set_doc("### C"//NL//"### D"//NL//NL//"Text."//NL//NL//"### E", t, f, baselines=ys)
        ncase = ncase + 1
        if (size(ys) /= 5) then
            nfail = nfail + 1
            print "(a,i0,a)", "  FAIL markdown consecutive headings: ", size(ys), " baselines in:"
            print "(a)", t
        else
            call near("heading after heading", ys(2) - ys(1), 12.0_dp + 1.5_dp*ex, ncase, nfail)
            call near("heading after text", ys(4) - ys(3), 12.0_dp + 3.25_dp*ex, ncase, nfail)
        end if
    end subroutine heading_cases

    ! A directive's callback is given its name, argument, options and
    ! body; a directive it leaves has its body set, and nothing else.
    subroutine directive_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc(":::{Admonition} My Title"//NL//":class: tip"//NL//"Body."//NL//":::"//NL// &
                     NL//":::{note} Dropped"//NL//"Kept body."//NL//":::", t, f, &
                     on_directive=admonition)
        call expect("directive argument", t, "My Title [tip]"//NL//"Body."//NL//"Kept body.", &
                     ncase, nfail)
        call face("directive title", t, f, "My Title", FACE_BOLD, ncase, nfail)
        call reject("unhandled argument", t, "Dropped", ncase, nfail)
        ! A callback that does not set handled leaves the directive to the
        ! core.
        call set_doc(":::{aside} Title"//NL//"Body kept."//NL//":::", t, f, &
                     on_directive=look_only)
        call expect("handled left alone", t, "Body kept.", ncase, nfail)
        ! A directive in a directive the callback sets calls it again.
        call set_doc("::::{admonition} Outer"//NL//":::{admonition} Inner"//NL//"Deep."//NL// &
                     ":::"//NL//"::::", t, f, on_directive=admonition)
        call expect("nested directive", t, "Outer []"//NL//"Inner []"//NL//"Deep.", ncase, nfail)
    end subroutine directive_cases

    ! A heading's callback is given its level, text and number, and what
    ! it leaves is set by the core.
    subroutine heading_template_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f

        call set_doc("---"//NL//"numbersections: true"//NL//"---"//NL//"# Alpha"//NL//NL// &
                     "Text."//NL//NL//"## Beta", t, f, on_heading=part_heading)
        call expect("heading template", t, "Part 1: Alpha"//NL//"Text."//NL//"1.1 Beta", &
                     ncase, nfail)
        ! A heading the callback sets as another heading calls it again.
        call set_doc("# Alpha"//NL//NL//"Text.", t, f, on_heading=demote)
        call expect("demoted heading", t, "Alpha"//NL//"Text.", ncase, nfail)
        call face("demoted heading face", t, f, "Alpha", FACE_BOLD, ncase, nfail)
    end subroutine heading_template_cases

    ! A callback may set a nested document without affecting the outer one.
    subroutine nesting_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: md, t0, f0, t1, f1
        type(md_document_t) :: d0, d1

        md = "---"//NL//"numbersections: true"//NL//"---"//NL//"# Alpha"//NL//NL// &
             "Text."//NL//NL//"## Beta"
        call md_typeset(d0, md, on_heading=part_heading)
        call render_doc(d0, t0, f0)
        call md_typeset(d1, md, on_body=nested_body, on_heading=part_heading)
        call render_doc(d1, t1, f1)
        ncase = ncase + 1
        if (t1 /= t0 .or. f1 /= f0) then
            nfail = nfail + 1
            print "(a)", "  FAIL markdown nested document changed outer pages"
        end if
    end subroutine nesting_cases

    ! Two documents alive at once, set in either order, match each set alone.
    subroutine two_docs_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=*), parameter :: md1 = &
            "---"//NL//"title: First"//NL//"numbersections: true"//NL//"---"//NL// &
            "# One"//NL//NL//"Body $$ x^2 $$ (eq:a) and {eq}`eq:a`."
        character(len=*), parameter :: md2 = &
            "---"//NL//"title: Second"//NL//"---"//NL// &
            "# Other"//NL//NL//"Different text."
        type(md_document_t) :: a0, b0, a1, b1, a2, b2
        character(len=:), allocatable :: ta0, fa0, tb0, fb0, ta1, fa1, tb1, fb1
        character(len=:), allocatable :: ta2, fa2, tb2, fb2

        call md_typeset(a0, md1)
        call render_doc(a0, ta0, fa0)
        call md_typeset(b0, md2)
        call render_doc(b0, tb0, fb0)

        call md_typeset(a1, md1)
        call md_typeset(b1, md2)
        call render_doc(a1, ta1, fa1)
        call render_doc(b1, tb1, fb1)

        call md_typeset(b2, md2)
        call md_typeset(a2, md1)
        call render_doc(a2, ta2, fa2)
        call render_doc(b2, tb2, fb2)

        ncase = ncase + 1
        if (ta1 /= ta0 .or. fa1 /= fa0 .or. tb1 /= tb0 .or. fb1 /= fb0 .or. &
            ta2 /= ta0 .or. fa2 /= fa0 .or. tb2 /= tb0 .or. fb2 /= fb0) then
            nfail = nfail + 1
            print "(a)", "  FAIL markdown two simultaneous documents differ from solo"
        end if
    end subroutine two_docs_cases

    ! Regression cases for #105.
    subroutine bugfix_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f, longp
        real(dp) :: low
        real(dp), allocatable :: bl(:)
        integer :: k
        character(len=*), parameter :: LQUOT = achar(226)//achar(128)//achar(156)
        character(len=*), parameter :: RQUOT = achar(226)//achar(128)//achar(157)
        character(len=*), parameter :: LSQUOT = achar(226)//achar(128)//achar(152)

        ! {ref} formats markup inside referenced titles and explicit text,
        ! and breaks long titles across lines instead of overflowing.
        call set_doc("(sec:r)="//NL//"# Results -- part *one* and $x^2$"//NL//NL// &
                     "See {ref}`sec:r` and {ref}`the *intro* -- here <sec:r>`.", t, f)
        call expect("ref en-dash", t, "Results "//DASH//" part one", ncase, nfail)
        call reject("ref raw asterisks", t, "*one*", ncase, nfail)
        call reject("ref raw explicit asterisks", t, "*intro*", ncase, nfail)
        call expect("ref explicit en-dash", t, "the intro "//DASH//" here", ncase, nfail)

        ! Cyclic self-referencing heading title terminates safely.
        call set_doc("(sec:self)="//NL//"# Loop {ref}`sec:self`"//NL//NL//"Body.", t, f)
        call expect("cyclic ref", t, "Body.", ncase, nfail)

        ! Document starting with a --- rule followed by a blank line keeps its content.
        call set_doc("---"//NL//NL//"Intro paragraph."//NL//NL//"Section"//NL//"---"//NL//NL// &
                     "Body.", t, f)
        call expect("leading rule intro", t, "Intro paragraph.", ncase, nfail)
        call expect("leading rule section", t, "Section", ncase, nfail)
        call expect("leading rule body", t, "Body.", ncase, nfail)

        ! Inline triple-backtick code span does not open a code fence;
        ! 4-backtick fence is not closed by inner 3-backtick fence.
        call set_doc("```x``` is code"//NL//NL//"Next *para*."//NL//NL//"# Heading", t, f)
        call expect("inline 3-tick", t, "x is code", ncase, nfail)
        call face("inline 3-tick next para", t, f, "para", FACE_ITALIC, ncase, nfail)
        call face("inline 3-tick heading", t, f, "Heading", FACE_BOLD, ncase, nfail)

        call set_doc("````"//NL//"```"//NL//"inside"//NL//"```"//NL//"````"//NL//NL// &
                     "*after*", t, f)
        call expect("4-tick fence", t, "inside", ncase, nfail)
        call face("4-tick fence after", t, f, "after", FACE_ITALIC, ncase, nfail)

        ! Closing #s are stripped only after a space.
        call set_doc("# Programming in C#"//NL//NL//"# Title ###", t, f)
        call expect("heading C#", t, "Programming in C#", ncase, nfail)
        call reject("heading closing ###", t, "###", ncase, nfail)

        ! Quotes right after emphasis marks open rather than close.
        call set_doc("*""Hello""* and **""Bold""** and _'x'_", t, f)
        call expect("italic open quote", t, LQUOT//"Hello"//RQUOT, ncase, nfail)
        call expect("bold open quote", t, LQUOT//"Bold"//RQUOT, ncase, nfail)
        call expect("italic open single quote", t, LSQUOT//"x", ncase, nfail)

        ! $a$$b$, \$$x$$, and lone unclosed $$ do not swallow the next heading.
        call set_doc("Values $a$$b$ here"//NL//"# Heading", t, f)
        call face("adjacent inline math heading", t, f, "Heading", FACE_BOLD, ncase, nfail)
        call set_doc(achar(92)//"$$x$$"//NL//"# Heading", t, f)
        call face("escaped dollar heading", t, f, "Heading", FACE_BOLD, ncase, nfail)
        call set_doc("Cost is $$"//NL//"# Heading", t, f)
        call face("unclosed $$ heading", t, f, "Heading", FACE_BOLD, ncase, nfail)

        ! Block quote ends before a heading that does not start with >.
        call set_doc("> quoted"//NL//"# Heading", t, f)
        call face("quote ends at heading", t, f, "Heading", FACE_BOLD, ncase, nfail)

        ! List item starting with a heading places its bullet on the heading's line.
        call set_doc("- # Item Head"//NL//NL//"  Next para.", t, f)
        call expect("list heading bullet", t, BULLET//" Item Head", ncase, nfail)

        ! Loose list preserves paragraph spacing after an inner code block.
        call set_doc("- First"//NL//NL//"  ```"//NL//"  code"//NL//"  ```"//NL//NL// &
                     "  Second"//NL//NL//"  Third", t, f, baselines=bl)
        ncase = ncase + 1
        if (size(bl) < 4) then
            nfail = nfail + 1
            print "(a)", "  FAIL markdown loose list after code: too few baselines"
        else if (bl(size(bl)) - bl(size(bl) - 1) < 13.0_dp) then
            nfail = nfail + 1
            print "(a,f0.2)", "  FAIL markdown loose list after code: gap = ", &
                bl(size(bl)) - bl(size(bl) - 1)
        end if

        ! Nested emphasis with the same delimiter stays italic with no stray *.
        call set_doc("*a *b* c*", t, f)
        call reject("nested emphasis stray *", t, "*", ncase, nfail)
        call face("nested emphasis c italic", t, f, "c", FACE_ITALIC, ncase, nfail)

        ! Bad front matter sizes warn and keep valid defaults instead of crashing.
        call set_doc("---"//NL//"fontsize: -10pt"//NL//"paper: -100 x 200"//NL// &
                     "margin: 900pt"//NL//"---"//NL//"Safe body.", t, f)
        call expect("bad sizes safe", t, "Safe body.", ncase, nfail)

        ! Malformed math warns and does not crash.
        call set_doc("Before $\frac{a$ after.", t, f)
        call expect("malformed math safe", t, "after.", ncase, nfail)

        ! Deep display at the foot of a flushbottom page respects maxdepth.
        call set_doc("---"//NL//"paper: 300 x 200"//NL//"margin: 36pt"//NL//"fontsize: 14pt"//NL// &
                     "pagenumbers: false"//NL//"flushbottom: true"//NL//"---"//NL// &
                     "One."//NL//NL//"Two."//NL//NL//"Three."//NL//NL//"Four."//NL//NL// &
                     "Text before the display"//NL//"$$ \int_0^1 f(x)\,dx $$"//NL// &
                     "and after it."//NL//NL//"More text.", t, f, lowest=low)
        ncase = ncase + 1
        if (low > 171.0_dp) then
            nfail = nfail + 1
            print "(a,f0.2)", "  FAIL markdown deep display foot: lowest = ", low
        end if

        ! Pandoc column-1 YAML author list and blank line in abstract: |.
        call set_doc("---"//NL//"title: Paper # draft comment"//NL//"author:"//NL// &
                     "- Author One"//NL//"- Author Two"//NL//"abstract: |"//NL// &
                     "  First abstract."//NL//NL//"  Second abstract."//NL//"---"//NL// &
                     "Body.", t, f)
        call expect("yaml comment stripped", t, "Paper", ncase, nfail)
        call reject("yaml comment absent", t, "draft", ncase, nfail)
        call expect("yaml col1 author 1", t, "Author One", ncase, nfail)
        call expect("yaml col1 author 2", t, "Author Two", ncase, nfail)
        call expect("yaml abstract para 2", t, "Second abstract.", ncase, nfail)

        ! Long word and long paragraph do not overflow stack (especially under flang).
        call set_doc(repeat("x", 5000), t, f)
        call expect("long word", t, "xxxx", ncase, nfail)
        allocate (character(len=500*12) :: longp)
        do k = 1, 500
            longp((k - 1)*12 + 1:k*12) = "word line  "//NL
        end do
        call set_doc(longp, t, f)
        call expect("long paragraph", t, "word line", ncase, nfail)
    end subroutine bugfix_cases

    ! An on_body callback that sets a nested document of its own.
    recursive subroutine nested_body(doc, after, ctx)
        type(md_document_t), intent(inout) :: doc
        logical, intent(in) :: after
        type(md_ctx_t), intent(in) :: ctx
        type(md_document_t) :: inner
        if (.not. after) call md_typeset(inner, "# Inner"//NL//NL//"Nested.")
    end subroutine nested_body

    ! A template that sets a level-one heading as a level-two one.
    recursive subroutine demote(doc, h, ctx, handled)
        type(md_document_t), intent(inout) :: doc
        type(md_heading_t), intent(in) :: h
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(inout) :: handled
        if (h%level /= 1) return
        handled = .true.
        call md_blocks(doc, "## "//h%text, ctx)
    end subroutine demote

    ! A template that sets a level-one heading as a part.
    recursive subroutine part_heading(doc, h, ctx, handled)
        type(md_document_t), intent(inout) :: doc
        type(md_heading_t), intent(in) :: h
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(inout) :: handled
        if (h%level /= 1) return
        handled = .true.
        call md_blocks(doc, "**Part "//h%num//":** "//h%text, ctx)
    end subroutine part_heading

    ! A template that sets no directive, and leaves handled as it is.
    recursive subroutine look_only(doc, d, ctx, handled)
        type(md_document_t), intent(inout) :: doc
        type(md_directive_t), intent(in) :: d
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(inout) :: handled
    end subroutine look_only

    ! A template's admonition: its argument in bold, with its class, and
    ! then its body.
    recursive subroutine admonition(doc, d, ctx, handled)
        type(md_document_t), intent(inout) :: doc
        type(md_directive_t), intent(in) :: d
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(inout) :: handled
        handled = d%name == "admonition"
        if (.not. handled) return
        call md_blocks(doc, "**"//d%arg//"** ["//md_option(d%opts, "class")//"]"//NL//NL// &
                       d%body, ctx)
    end subroutine admonition

    ! Files, multi-file typesetting, path helpers, and :::{literalinclude}.
    subroutine file_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f, raw, pdf
        character(len=256) :: texts(2), dirs(2)
        character(len=64) :: files(2)
        type(md_document_t) :: doc
        type(status_t) :: st
        logical :: is_pdf

        ! Path helpers: dir_name and join_path.
        call expect_eq("dir_name plain", dir_name("foo.md"), "", ncase, nfail)
        call expect_eq("dir_name sub", dir_name("a/b/c.md"), "a/b", ncase, nfail)
        call expect_eq("dir_name root", dir_name("/c.md"), "/", ncase, nfail)
        call expect_eq("dir_name backslash", dir_name("a"//achar(92)//"b.md"), "a", ncase, nfail)
        call expect_eq("dir_name drive", dir_name("C:"//achar(92)//"foo.md"), &
                       "C:"//achar(92), ncase, nfail)
        call expect_eq("join_path empty dir", join_path("", "code.f90"), "code.f90", ncase, nfail)
        call expect_eq("join_path rel", join_path("a/b", "code.f90"), "a/b/code.f90", ncase, nfail)
        call expect_eq("join_path slash", join_path("a/b/", "c.f90"), "a/b/c.f90", ncase, nfail)
        call expect_eq("join_path abs", join_path("a/b", "/x/c.f90"), "/x/c.f90", ncase, nfail)
        call expect_eq("join_path drive", join_path("a/b", "C:"//achar(92)//"x.f90"), &
                       "C:"//achar(92)//"x.f90", ncase, nfail)

        ! Create test fixtures in subdirectories under tests/out.
        call execute_command_line("mkdir -p tests/out/md_file_test/sub/code")
        call write_bytes("tests/out/md_file_test/sub/code/sample.f90", &
                         "line_one"//NL//"line_two"//NL//"line_three"//NL// &
                         "line_four"//NL//"line_five"//NL, st)
        call write_bytes("tests/out/md_file_test/sub/code/local.txt", &
                         "from_code_dir"//NL, st)
        call write_bytes("tests/out/md_file_test/sub/code/empty.txt", "", st)

        ! read_bytes round-trip, empty file, and missing file error.
        call read_bytes("tests/out/md_file_test/sub/code/local.txt", raw, st)
        call expect_true("read_bytes ok", st%ok(), ncase, nfail)
        call expect_eq("read_bytes data", raw, "from_code_dir"//NL, ncase, nfail)
        call read_bytes("tests/out/md_file_test/sub/code/empty.txt", raw, st)
        call expect_true("read_bytes empty ok", st%ok() .and. len(raw) == 0, ncase, nfail)
        call read_bytes("tests/out/md_file_test/no_such_file.md", raw, st)
        call expect_true("read_bytes missing", .not. st%ok() .and. st%code == ERROR_IO, &
                         ncase, nfail)

        ! :::{literalinclude} relative path resolution, :lines:, :language:.
        call md_typeset(doc, "Before."//NL//NL// &
                        ":::{literalinclude} code/sample.f90"//NL// &
                        ":language: fortran"//NL// &
                        ":lines: 2-4"//NL// &
                        ":::"//NL//NL//"After.", &
                        base_dir="tests/out/md_file_test/sub")
        call render_doc(doc, t, f)
        call expect("literalinclude 2-4 has 2", t, "line_two", ncase, nfail)
        call expect("literalinclude 2-4 has 3", t, "line_three", ncase, nfail)
        call expect("literalinclude 2-4 has 4", t, "line_four", ncase, nfail)
        call reject("literalinclude 2-4 no 1", t, "line_one", ncase, nfail)
        call reject("literalinclude 2-4 no 5", t, "line_five", ncase, nfail)

        ! Multiple ranges and open-ended ranges.
        call md_typeset(doc, ":::{literalinclude} code/sample.f90"//NL// &
                        ":lines: 1-2, 4-5"//NL//":::", &
                        base_dir="tests/out/md_file_test/sub")
        call render_doc(doc, t, f)
        call expect("literalinclude multi has 1", t, "line_one", ncase, nfail)
        call expect("literalinclude multi has 2", t, "line_two", ncase, nfail)
        call reject("literalinclude multi no 3", t, "line_three", ncase, nfail)
        call expect("literalinclude multi has 4", t, "line_four", ncase, nfail)
        call expect("literalinclude multi has 5", t, "line_five", ncase, nfail)

        call md_typeset(doc, ":::{literalinclude} code/sample.f90"//NL// &
                        ":lines: -2, 5-"//NL//":::", &
                        base_dir="tests/out/md_file_test/sub")
        call render_doc(doc, t, f)
        call expect("literalinclude open has 1", t, "line_one", ncase, nfail)
        call expect("literalinclude open has 2", t, "line_two", ncase, nfail)
        call reject("literalinclude open no 3", t, "line_three", ncase, nfail)
        call expect("literalinclude open has 5", t, "line_five", ncase, nfail)

        ! Missing literalinclude file and invalid/out-of-bounds :lines: continue cleanly.
        call md_typeset(doc, "Start."//NL//NL// &
                        ":::{literalinclude} does_not_exist.f90"//NL//":::"//NL//NL// &
                        ":::{literalinclude} code/sample.f90"//NL// &
                        ":lines: 5-3, 0, abc, -, 99-"//NL//":::"//NL//NL// &
                        ":::{literalinclude} code/sample.f90"//NL// &
                        ":lines: 4-999"//NL//":::"//NL//NL// &
                        "Still here.", base_dir="tests/out/md_file_test/sub")
        call render_doc(doc, t, f)
        call expect("literalinclude clamped 4", t, "line_four", ncase, nfail)
        call expect("literalinclude clamped 5", t, "line_five", ncase, nfail)
        call reject("literalinclude clamped no 3", t, "line_three", ncase, nfail)
        call expect("literalinclude missing continues", t, "Still here.", ncase, nfail)

        ! md_typeset_files with 0 files succeeds cleanly.
        call md_typeset_files(doc, texts(1:0), dirs(1:0))
        call render_doc(doc, t, f)
        call expect_eq("multi zero files", t, "", ncase, nfail)

        ! md_typeset_files: front matter from file 1, cross-references across
        ! files, and per-file base directories for :::{literalinclude}.
        texts(1) = "---"//NL//"title: Multi Doc"//NL//"numbersections: true"//NL//"---"//NL// &
                   "(sec:one)="//NL//"# First"//NL//NL// &
                   "See {numref}`sec:two` and {eq}`eq:two`."//NL//NL// &
                   ":::{literalinclude} code/sample.f90"//NL//":lines: 3"//NL//":::"//NL
        texts(2) = "(sec:two)="//NL//"# Second"//NL//NL// &
                   "Back to {numref}`sec:one`."//NL// &
                   "$$ a = b $$ (eq:two)"//NL//NL// &
                   ":::{literalinclude} local.txt"//NL//":::"//NL
        dirs(1) = "tests/out/md_file_test/sub"
        dirs(2) = "tests/out/md_file_test/sub/code"
        call md_typeset_files(doc, texts, dirs)
        call render_doc(doc, t, f)
        call expect("multi title", t, "Multi Doc", ncase, nfail)
        call expect("multi fwd ref", t, "See Section 2 and (1).", ncase, nfail)
        call expect("multi back ref", t, "Back to Section 1.", ncase, nfail)
        call expect("multi dir 1 include", t, "line_three", ncase, nfail)
        call expect("multi dir 2 include", t, "from_code_dir", ncase, nfail)

        ! typeset_file public API: single file, multiple files, missing file.
        call write_bytes("tests/out/md_file_test/sub/ch1.md", trim(texts(1)), st)
        call write_bytes("tests/out/md_file_test/sub/code/ch2.md", trim(texts(2)), st)

        call typeset_file("tests/out/md_file_test/sub/ch1.md", &
                          "tests/out/md_file_test/one.pdf", status=st)
        call expect_true("typeset_file one ok", st%ok(), ncase, nfail)
        call read_bytes("tests/out/md_file_test/one.pdf", pdf, st)
        is_pdf = .false.
        if (st%ok() .and. len(pdf) >= 5) is_pdf = pdf(1:5) == "%PDF-"
        call expect_true("typeset_file one pdf", is_pdf, ncase, nfail)

        files(1) = "tests/out/md_file_test/sub/ch1.md"
        files(2) = "tests/out/md_file_test/sub/code/ch2.md"
        call typeset_file(files, "tests/out/md_file_test/many.pdf", status=st)
        call expect_true("typeset_file many ok", st%ok(), ncase, nfail)
        call read_bytes("tests/out/md_file_test/many.pdf", pdf, st)
        is_pdf = .false.
        if (st%ok() .and. len(pdf) >= 5) is_pdf = pdf(1:5) == "%PDF-"
        call expect_true("typeset_file many pdf", is_pdf, ncase, nfail)

        call typeset_file("tests/out/md_file_test/missing.md", &
                          "tests/out/md_file_test/none.pdf", status=st)
        call expect_true("typeset_file missing err", .not. st%ok() .and. st%code == ERROR_IO, &
                         ncase, nfail)
    end subroutine file_cases

    subroutine expect_eq(what, got, want, ncase, nfail)
        character(len=*), intent(in) :: what, got, want
        integer, intent(inout) :: ncase, nfail
        ncase = ncase + 1
        if (got == want) return
        nfail = nfail + 1
        print "(a)", "  FAIL markdown "//what//": got '"//got//"', want '"//want//"'"
    end subroutine expect_eq

    subroutine expect_true(what, cond, ncase, nfail)
        character(len=*), intent(in) :: what
        logical, intent(in) :: cond
        integer, intent(inout) :: ncase, nfail
        ncase = ncase + 1
        if (cond) return
        nfail = nfail + 1
        print "(a)", "  FAIL markdown "//what
    end subroutine expect_true

    ! ------------------------------------------------------------------
    ! Setting a document and reading it back.
    ! ------------------------------------------------------------------

    ! The text of document md's pages, the face of each of its bytes
    ! ("0" + face, " " for a space or line end), the lowest baseline on
    ! any page, the leftmost glyph, and the baselines of the first page;
    ! on_directive and on_heading are the template's, if any.
    subroutine set_doc(md, text, faces, lowest, leftmost, baselines, on_directive, on_heading, &
                       figures, nframes, last_mat)
        character(len=*), intent(in) :: md
        character(len=:), allocatable, intent(out) :: text, faces
        real(dp), intent(out), optional :: lowest, leftmost
        real(dp), allocatable, intent(out), optional :: baselines(:)
        procedure(md_directive_cb), optional :: on_directive
        procedure(md_heading_cb), optional :: on_heading
        type(md_figure_t), intent(in), optional :: figures(:)
        integer, intent(out), optional :: nframes
        real(dp), intent(out), optional :: last_mat(6)
        type(md_document_t) :: doc

        call md_typeset(doc, md, on_directive=on_directive, on_heading=on_heading, &
                        figures=figures)
        call render_doc(doc, text, faces, lowest, leftmost, baselines, nframes, last_mat)
    end subroutine set_doc

    subroutine render_doc(doc, text, faces, lowest, leftmost, baselines, nframes, last_mat)
        type(md_document_t), intent(in) :: doc
        character(len=:), allocatable, intent(out) :: text, faces
        real(dp), intent(out), optional :: lowest, leftmost
        real(dp), allocatable, intent(out), optional :: baselines(:)
        integer, intent(out), optional :: nframes
        real(dp), intent(out), optional :: last_mat(6)
        type(text_renderer_t) :: r
        real(dp) :: w, h
        integer :: p, col

        call ts_page_size(doc%engine, w, h, col)
        text = ""
        faces = ""
        if (present(lowest)) lowest = 0.0_dp
        if (present(leftmost)) leftmost = huge(1.0_dp)
        if (present(nframes)) nframes = 0
        if (present(last_mat)) last_mat = 0.0_dp
        do p = 1, ts_page_count(doc%engine)
            call r%open_canvas(w, h)
            call ts_page_draw(doc%engine, r, p)
            call r%close_canvas()
            if (present(lowest) .and. r%n > 0) lowest = max(lowest, maxval(r%y(1:r%n)))
            if (present(leftmost) .and. r%n > 0) leftmost = min(leftmost, minval(r%x(1:r%n)))
            if (present(nframes)) nframes = nframes + r%n_frames
            if (present(last_mat) .and. r%n_frames > 0) last_mat = r%last_mat
            if (present(baselines) .and. p == 1) call page_baselines(r, baselines)
            if (p > 1) then
                text = text//FF
                faces = faces//" "
            end if
            call page_lines(r, text, faces)
        end do
    end subroutine render_doc

    ! The glyphs of a page, sorted into lines, appended to text and faces.
    subroutine page_lines(r, text, faces)
        type(text_renderer_t), intent(inout) :: r
        character(len=:), allocatable, intent(inout) :: text, faces
        integer, allocatable :: order(:)
        character(len=:), allocatable :: c
        integer :: i, j, k, t
        allocate (order(r%n))
        do i = 1, r%n
            order(i) = i
        end do
        ! By baseline, then from left to right.
        do i = 2, r%n
            t = order(i)
            j = i - 1
            do while (j >= 1)
                if (.not. before(r, t, order(j))) exit
                order(j + 1) = order(j)
                j = j - 1
            end do
            order(j + 1) = t
        end do
        do i = 1, r%n
            k = order(i)
            if (i > 1) then
                j = order(i - 1)
                if (abs(r%y(k) - r%y(j)) > 0.01_dp) then
                    text = text//NL
                    faces = faces//" "
                else if (r%x(k) - (r%x(j) + r%adv(j)) > 0.1_dp) then
                    text = text//" "
                    faces = faces//" "
                end if
            end if
            c = utf8(r%cp(k))
            text = text//c
            faces = faces//repeat(achar(48 + r%face(k)), len(c))
        end do
    end subroutine page_lines

    ! The baselines of a page, from the top.
    subroutine page_baselines(r, ys)
        type(text_renderer_t), intent(in) :: r
        real(dp), allocatable, intent(out) :: ys(:)
        real(dp) :: lo
        integer :: k, n
        n = 0
        lo = -huge(1.0_dp)
        do while (any(r%y(1:r%n) > lo + 0.01_dp))
            n = n + 1
            lo = minval(r%y(1:r%n), mask=r%y(1:r%n) > lo + 0.01_dp)
        end do
        allocate (ys(n))
        lo = -huge(1.0_dp)
        do k = 1, n
            ys(k) = minval(r%y(1:r%n), mask=r%y(1:r%n) > lo + 0.01_dp)
            lo = ys(k)
        end do
    end subroutine page_baselines

    logical function before(r, a, b)
        type(text_renderer_t), intent(in) :: r
        integer, intent(in) :: a, b
        if (abs(r%y(a) - r%y(b)) > 0.01_dp) then
            before = r%y(a) < r%y(b)
        else
            before = r%x(a) < r%x(b)
        end if
    end function before

    ! A code point as UTF-8, the math alphabets' four bytes included.
    function utf8(code) result(s)
        integer, intent(in) :: code
        character(len=:), allocatable :: s
        if (code < 128) then
            s = achar(code)
        else if (code < 2048) then
            s = achar(192 + code/64)//achar(128 + iand(code, 63))
        else if (code < 65536) then
            s = achar(224 + code/4096)//achar(128 + iand(code/64, 63))//achar(128 + iand(code, 63))
        else
            s = achar(240 + code/262144)//achar(128 + iand(code/4096, 63)) &
                //achar(128 + iand(code/64, 63))//achar(128 + iand(code, 63))
        end if
    end function utf8

    subroutine reject(what, text, unwanted, ncase, nfail)
        character(len=*), intent(in) :: what, text, unwanted
        integer, intent(inout) :: ncase, nfail
        ncase = ncase + 1
        if (index(text, unwanted) == 0) return
        nfail = nfail + 1
        print "(a)", "  FAIL markdown "//what//": '"//unwanted//"' in:"
        print "(a)", text
    end subroutine reject

    ! Whether the first letter of word, found in text, is in face.
    subroutine face(what, text, faces, word, want, ncase, nfail)
        character(len=*), intent(in) :: what, text, faces, word
        integer, intent(in) :: want
        integer, intent(inout) :: ncase, nfail
        integer :: k
        ncase = ncase + 1
        k = index(text, word)
        if (k > 0) then
            if (faces(k:k) == achar(48 + want)) return
        end if
        nfail = nfail + 1
        print "(a,i0,a)", "  FAIL markdown "//what//": '"//word//"' not in face ", want, " in:"
        print "(a)", text
        print "(a)", faces
    end subroutine face

    subroutine near(what, got, want, ncase, nfail)
        character(len=*), intent(in) :: what
        real(dp), intent(in) :: got, want
        integer, intent(inout) :: ncase, nfail
        ncase = ncase + 1
        if (abs(got - want) < 0.5_dp) return
        nfail = nfail + 1
        print "(a,f0.2,a,f0.2)", "  FAIL markdown "//what//": ", got, " instead of ", want
    end subroutine near

    subroutine expect(what, text, want, ncase, nfail)
        character(len=*), intent(in) :: what, text, want
        integer, intent(inout) :: ncase, nfail
        ncase = ncase + 1
        if (index(text, want) > 0) return
        nfail = nfail + 1
        print "(a)", "  FAIL markdown "//what//": no '"//want//"' in:"
        print "(a)", text
    end subroutine expect

    ! ------------------------------------------------------------------
    ! The renderer.
    ! ------------------------------------------------------------------

    subroutine tr_open(self, width, height, bg_rgb, bg_alpha, x0, y0)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha, x0, y0
        self%n = 0
        self%n_frames = 0
        self%frame_depth = 0
        self%last_mat = 0.0_dp
        if (.not. allocated(self%x)) allocate (self%x(0), self%y(0), self%adv(0), self%cp(0), &
                                               self%face(0))
    end subroutine tr_open

    subroutine tr_close(self)
        class(text_renderer_t), intent(inout) :: self
    end subroutine tr_close

    subroutine tr_path(self, x, y, verbs, n_verb, paint)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
    end subroutine tr_path

    subroutine tr_rect(self, x, y, w, h, paint, radius)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
    end subroutine tr_rect

    subroutine tr_circle(self, cx, cy, r, paint)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
    end subroutine tr_circle

    subroutine tr_markers(self, x, y, mx, my, mverbs, n_mverb, paint)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:), mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
    end subroutine tr_markers

    ! Each glyph at its place on the baseline it is drawn on.
    subroutine tr_glyphs(self, x, y, run, paint, angle)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
        integer :: k, m
        if (self%frame_depth > 0 .and. .not. self%include_frames) return
        if (self%n + run%n > size(self%x)) call grow(self, self%n + run%n)
        do k = 1, run%n
            m = self%n + k
            self%x(m) = x + run%x(k)
            self%y(m) = y
            self%adv(m) = glyph_adv(run%gid(k))*run%size(k)
            self%cp(m) = glyph_char(run%gid(k))
            self%face(m) = glyph_face(run%gid(k))
        end do
        self%n = self%n + run%n
    end subroutine tr_glyphs

    ! Room for at least need glyphs.
    subroutine grow(self, need)
        class(text_renderer_t), intent(inout) :: self
        integer, intent(in) :: need
        real(dp), allocatable :: r(:)
        integer, allocatable :: i(:)
        integer :: m
        m = max(256, 2*size(self%x), need)
        allocate (r(m))
        r(1:self%n) = self%x(1:self%n)
        call move_alloc(r, self%x)
        allocate (r(m))
        r(1:self%n) = self%y(1:self%n)
        call move_alloc(r, self%y)
        allocate (r(m))
        r(1:self%n) = self%adv(1:self%n)
        call move_alloc(r, self%adv)
        allocate (i(m))
        i(1:self%n) = self%cp(1:self%n)
        call move_alloc(i, self%cp)
        allocate (i(m))
        i(1:self%n) = self%face(1:self%n)
        call move_alloc(i, self%face)
    end subroutine grow

    subroutine tr_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint
    end subroutine tr_image

    subroutine tr_begin_frame(self, matrix, clip)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        if (self%frame_depth == 0) then
            self%n_frames = self%n_frames + 1
            self%last_mat = matrix
        end if
        self%frame_depth = self%frame_depth + 1
    end subroutine tr_begin_frame

    subroutine tr_end_frame(self)
        class(text_renderer_t), intent(inout) :: self
        self%frame_depth = self%frame_depth - 1
    end subroutine tr_end_frame

    ! Build a simple vector frame of size (w, h) for testing figure layout.
    subroutine make_test_frame(w, h, frame)
        real(dp), intent(in) :: w, h
        type(frame_t), intent(out) :: frame
        type(recording_renderer_t) :: rec
        type(paint_t) :: p
        p%filled = .true.
        p%fill_rgb = [31, 119, 180]
        call rec%open_canvas(w, h)
        call rec%draw_rect(0.0_dp, 0.0_dp, w, h, p)
        call rec%close_canvas()
        call rec%take(frame)
    end subroutine make_test_frame

    subroutine figure_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        type(md_figure_t) :: figs(2), pfigs(1)
        type(frame_t) :: fr
        type(status_t) :: st
        character(len=:), allocatable :: t, f, svg_data
        real(dp) :: mat(6), avail, fw, fh
        integer :: nf, u, ios, sz
        logical :: ex

        figs(1)%name = "box"
        call make_test_frame(200.0_dp, 100.0_dp, figs(1)%frame)
        figs(2)%name = "wide"
        call make_test_frame(600.0_dp, 300.0_dp, figs(2)%frame)

        ! :::{figure} with :width: percentage, :name:, caption, and forward {numref}/{ref}.
        avail = 595.2756_dp - 144.0_dp
        call set_doc("See {numref}`fig:box` ({ref}`fig:box`)."//NL//NL// &
                     ":::{figure} box"//NL// &
                     ":width: 80%"//NL// &
                     ":name: fig:box"//NL// &
                     "A *simple* box."//NL// &
                     ":::", t, f, figures=figs, nframes=nf, last_mat=mat)
        call expect("figure numref", t, "See Fig. 1 (A simple box.).", ncase, nfail)
        call expect("figure caption", t, "Figure 1: A simple box.", ncase, nfail)
        call face("figure caption bold", t, f, "Figure", FACE_BOLD, ncase, nfail)
        call face("figure caption italic", t, f, "simple", FACE_ITALIC, ncase, nfail)
        call near("figure frame count", real(nf, dp), 1.0_dp, ncase, nfail)
        call near("figure 80% scale", mat(1)*200.0_dp, 0.8_dp*avail, ncase, nfail)
        call near("figure centered x", mat(5), 72.0_dp + 0.1_dp*avail, ncase, nfail)

        ! :width: in inches with :align: right.
        call set_doc(":::{figure} box"//NL// &
                     ":width: 3in"//NL// &
                     ":align: right"//NL// &
                     "Right aligned."//NL// &
                     ":::", t, f, figures=figs, nframes=nf, last_mat=mat)
        call near("figure 3in width", mat(1)*200.0_dp, 216.0_dp, ncase, nfail)
        call near("figure right x", mat(5), 72.0_dp + avail - 216.0_dp, ncase, nfail)

        ! :align: left with natural width clamped to avail (600pt > avail).
        call set_doc(":::{figure} wide"//NL// &
                     ":align: left"//NL// &
                     ":::", t, f, figures=figs, nframes=nf, last_mat=mat)
        call near("figure clamped width", mat(1)*600.0_dp, avail, ncase, nfail)
        call near("figure left x", mat(5), 72.0_dp, ncase, nfail)

        ! Standalone ![caption](name) with preceding (fig:s)= target.
        call set_doc("(fig:s)="//NL// &
                     "![Standalone plot.](box)"//NL//NL// &
                     "As in {numref}`fig:s` and {numref}`Figure %s <fig:s>`.", &
                     t, f, figures=figs, nframes=nf, last_mat=mat)
        call expect("standalone caption", t, "Figure 1: Standalone plot.", ncase, nfail)
        call expect("standalone numref", t, "As in Fig. 1 and Figure 1.", ncase, nfail)
        call near("standalone frame count", real(nf, dp), 1.0_dp, ncase, nfail)

        ! Chapter-based figure numbering.
        call set_doc("---"//NL//"chapters: true"//NL//"---"//NL// &
                     "# One"//NL//NL//"(fig:a)="//NL//"![First.](box)"//NL//NL// &
                     "# Two"//NL//NL//"(fig:b)="//NL//"![Second.](box)"//NL//NL// &
                     "Refs {numref}`fig:a` and {numref}`fig:b`.", &
                     t, f, figures=figs, nframes=nf)
        call expect("chapter fig refs", t, "Refs Fig. 1.1 and Fig. 2.1.", ncase, nfail)
        call near("chapter frame count", real(nf, dp), 2.0_dp, ncase, nfail)

        ! Unknown figure warns gracefully without crashing.
        call set_doc("![Missing.](no_such_fig)", t, f, figures=figs, nframes=nf)
        call expect("unknown fig caption", t, "Figure 1: Missing.", ncase, nfail)
        call near("unknown fig frames", real(nf, dp), 0.0_dp, ncase, nfail)

        ! Indented figure (inside blockquote) and invalid negative :width: falls back to natural.
        call set_doc("> :::{figure} box"//NL// &
                     "> :width: -1in"//NL// &
                     "> :align: left"//NL// &
                     "> Quoted."//NL// &
                     "> :::", t, f, figures=figs, nframes=nf, last_mat=mat)
        call expect("quoted fig caption", t, "Figure 1: Quoted.", ncase, nfail)
        call near("quoted fig natural width", mat(1)*200.0_dp, 200.0_dp, ncase, nfail)
        call near("quoted fig left x", mat(5), 72.0_dp + 25.0_dp, ncase, nfail)

        ! End-to-end fplotlib capture_figure + named_figure + typeset PDF/SVG.
        call figure()
        call plot([0.0_dp, 1.0_dp, 2.0_dp], [0.0_dp, 1.0_dp, 0.0_dp])
        call title("Triangle")
        call capture_figure(fr)
        call fr%metrics(fw, fh)
        ncase = ncase + 1
        if (fw <= 0.0_dp .or. fh <= 0.0_dp) then
            nfail = nfail + 1
            print "(a)", "  FAIL markdown capture_figure metrics"
        end if
        call named_figure(pfigs(1), "tri")
        call close()

        call typeset([character(len=80) :: &
                      "# Report", "", "See {numref}`fig:tri`.", "", &
                      ":::{figure} tri", ":width: 75%", ":name: fig:tri", &
                      "Vector triangle plot.", ":::"], &
                     "/tmp/fplotlib_test_fig.pdf", figures=pfigs, status=st)
        ncase = ncase + 1
        inquire (file="/tmp/fplotlib_test_fig.pdf", exist=ex, size=sz)
        if (.not. st%ok() .or. .not. ex .or. sz <= 0) then
            nfail = nfail + 1
            print "(a)", "  FAIL markdown typeset PDF with figure"
        end if

        call typeset([character(len=80) :: &
                      "![Vector triangle.](tri)"], &
                     "/tmp/fplotlib_test_fig.svg", figures=pfigs, status=st)
        ncase = ncase + 1
        inquire (file="/tmp/fplotlib_test_fig.svg", exist=ex, size=sz)
        if (.not. st%ok() .or. .not. ex .or. sz <= 0) then
            nfail = nfail + 1
            print "(a)", "  FAIL markdown typeset SVG with figure"
        else
            allocate (character(len=sz) :: svg_data)
            svg_data(1:sz) = " "
            open (newunit=u, file="/tmp/fplotlib_test_fig.svg", access="stream", &
                  form="unformatted", status="old", iostat=ios)
            if (ios == 0) then
                read (u, iostat=ios) svg_data
                close (u)
            end if
            call expect("svg vector path", svg_data, "<path", ncase, nfail)
        end if

        open (newunit=u, file="/tmp/fplotlib_test_fig.pdf", status="old", iostat=ios)
        if (ios == 0) close (u, status="delete")
        open (newunit=u, file="/tmp/fplotlib_test_fig.svg", status="old", iostat=ios)
        if (ios == 0) close (u, status="delete")
    end subroutine figure_cases

    ! md_typeset_box: exact width, measured height, background/border, empty text.
    subroutine box_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        type(frame_t) :: f1, f2, f_empty
        real(dp) :: w1, h1, w2, h2, we, he, b(4)
        logical :: ink

        call md_typeset_box("**Heading**"//NL//NL//"A justified paragraph with "// &
                            "$E = mc^2$ and a display:"//NL//NL//"$$x^2 + y^2 = 1$$"// &
                            NL//NL//"- first"//NL//"- second", &
                            200.0_dp, f1, fontsize=9.0_dp, align="justify", &
                            color="#111111", bg_color="#f8fafc", border_color="#94a3b8", &
                            border_width=1.0_dp, alpha=0.95_dp, pad=8.0_dp, radius=4.0_dp)
        call f1%metrics(w1, h1)
        call f1%ink_bounds(b, ink)
        ncase = ncase + 1
        if (abs(w1 - 200.0_dp) > 1.0e-6_dp .or. h1 <= 40.0_dp .or. .not. ink) then
            print *, "FAIL md_typeset_box metrics:", w1, h1, ink
            nfail = nfail + 1
        end if

        ! Narrower box wraps to more lines and therefore has larger height.
        call md_typeset_box("A moderately long paragraph of prose that wraps across "// &
                            "multiple lines when constrained to a narrower box width.", &
                            220.0_dp, f1, fontsize=10.0_dp, pad=4.0_dp)
        call md_typeset_box("A moderately long paragraph of prose that wraps across "// &
                            "multiple lines when constrained to a narrower box width.", &
                            110.0_dp, f2, fontsize=10.0_dp, pad=4.0_dp)
        call f1%metrics(w1, h1)
        call f2%metrics(w2, h2)
        ncase = ncase + 1
        if (h2 <= h1) then
            print *, "FAIL md_typeset_box wrapping height:", h1, h2
            nfail = nfail + 1
        end if

        ! Empty input produces a valid, non-degenerate frame.
        call md_typeset_box("", 120.0_dp, f_empty, pad=5.0_dp)
        call f_empty%metrics(we, he)
        ncase = ncase + 1
        if (abs(we - 120.0_dp) > 1.0e-6_dp .or. he < 1.0_dp) then
            print *, "FAIL md_typeset_box empty:", we, he
            nfail = nfail + 1
        end if

        ! ts_box_height: valid page and out-of-range page bounds.
        block
            type(md_document_t) :: d
            real(dp) :: th, tg
            call md_typeset(d, "One line of text.")
            th = ts_box_height(d%engine, 1, tg)
            ncase = ncase + 1
            if (th <= 0.0_dp .or. tg < 0.0_dp) then
                print *, "FAIL ts_box_height valid:", th, tg
                nfail = nfail + 1
            end if
            ncase = ncase + 1
            if (ts_box_height(d%engine, 0) /= 0.0_dp .or. &
                ts_box_height(d%engine, 99) /= 0.0_dp) then
                print *, "FAIL ts_box_height out-of-range"
                nfail = nfail + 1
            end if
        end block
    end subroutine box_cases

    ! Markdown pipe tables, :::{table}, column alignments, and cross-references.
    subroutine table_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        character(len=:), allocatable :: t, f, src_txt
        type(md_document_t) :: d
        real(dp) :: pw, ph
        integer :: nf, pcol

        ! Basic pipe table with column alignments and inline markup/math.
        call set_doc("(tab:data)="//NL// &
                     "| Name | Value | Note |"//NL// &
                     "| :--- | :---: | ---: |"//NL// &
                     "| Alpha | $1.5$ | *ok* |"//NL// &
                     "| Beta | 2.0 | **done** |"//NL//NL// &
                     "See {numref}`tab:data`.", t, f, nframes=nf)
        call expect("pipe table numref", t, "See Table 1.", ncase, nfail)
        call near("pipe table frame count", real(nf, dp), 1.0_dp, ncase, nfail)

        ! Verify table cell text is actually rendered inside the frame.
        block
            type(text_renderer_t) :: tr
            integer :: k
            call md_typeset(d, "| Name | Value |"//NL//"| :--- | ---: |"//NL// &
                            "| Alpha | 1.5 |")
            call ts_page_size(d%engine, pw, ph, pcol)
            tr%include_frames = .true.
            call tr%open_canvas(pw, ph)
            call ts_page_draw(d%engine, tr, 1)
            call tr%close_canvas()
            allocate (character(len=max(1, tr%n)) :: src_txt)
            src_txt(:) = " "
            do k = 1, tr%n
                if (tr%cp(k) >= 32 .and. tr%cp(k) <= 126) src_txt(k:k) = achar(tr%cp(k))
            end do
            call expect("pipe table header", src_txt, "Name", ncase, nfail)
            call expect("pipe table cell", src_txt, "Alpha", ncase, nfail)
        end block

        ! :::{table} directive with caption, :name:, :align:, {numref}, and {ref}.
        call set_doc("Forward ref: {numref}`tab:res` ({ref}`tab:res`)."//NL//NL// &
                     ":::{table} Summary of *results*"//NL// &
                     ":name: tab:res"//NL// &
                     ":align: center"//NL// &
                     "| $t$ | $y(t)$ |"//NL// &
                     "| ---: | ---: |"//NL// &
                     "| 0.0 | 1.000 |"//NL// &
                     "| 2.0 | -0.308 |"//NL// &
                     ":::", t, f, nframes=nf)
        call expect("table directive numref", t, "Forward ref: Table 1 (Summary of results).", &
                    ncase, nfail)
        call expect("table directive caption", t, "Table 1: Summary of results", ncase, nfail)
        call face("table caption bold", t, f, "Table 1:", FACE_BOLD, ncase, nfail)
        call face("table caption italic", t, f, "results", FACE_ITALIC, ncase, nfail)
        call near("table directive frame count", real(nf, dp), 1.0_dp, ncase, nfail)

        ! Chapter-based table numbering.
        call set_doc("---"//NL//"chapters: true"//NL//"---"//NL// &
                     "# First"//NL//NL//"(tab:a)="//NL// &
                     "| A | B |"//NL//"| --- | --- |"//NL//"| 1 | 2 |"//NL//NL// &
                     "# Second"//NL//NL//"(tab:b)="//NL// &
                     "| C | D |"//NL//"| --- | --- |"//NL//"| 3 | 4 |"//NL//NL// &
                     "Tables {numref}`tab:a` and {numref}`tab:b`.", t, f, nframes=nf)
        call expect("chapter table refs", t, "Tables Table 1.1 and Table 2.1.", ncase, nfail)
        call near("chapter table frames", real(nf, dp), 2.0_dp, ncase, nfail)
    end subroutine table_cases

    ! Immediate-mode report API and explicit report_t.
    subroutine report_cases(ncase, nfail)
        integer, intent(inout) :: ncase, nfail
        type(report_t) :: rep
        type(document_asset_t), allocatable :: svg_assets(:), pdf_assets(:), png_assets(:)
        type(status_t) :: st
        real(dp) :: rvals(2, 2)
        integer :: ivals(2, 2), u, ios, sz
        character(len=12) :: cvals(2, 2)
        logical :: ex

        rvals = reshape([0.0_dp, 2.0_dp, 1.0_dp, -0.308_dp], [2, 2])
        ivals = reshape([1, 2, 10, 20], [2, 2])
        cvals = reshape(["A           ", "B           ", "pass        ", "ok          "], [2, 2])

        ! Immediate-mode API: markdown + figure + clf() isolation + tables + repeated saves.
        call new_report()
        call markdown("# Immediate Report")
        call markdown([character(len=64) :: &
                       "See {numref}`fig:p1`, {numref}`tab:r1`, {numref}`tab:i1`,", &
                       "and {numref}`tab:c1`."])

        call figure()
        call plot([0.0_dp, 1.0_dp, 2.0_dp], [0.0_dp, 1.0_dp, 0.0_dp])
        call title("Wave")
        call include_figure(caption="Captured vector plot.", label="fig:p1", width="80%")
        ! Clearing the plot afterwards must not affect the already-captured figure.
        call clf()
        call close()

        call include_table(rvals, columns=[character(len=8) :: "t", "y"], &
                           caption="Real values.", label="tab:r1")
        call include_table(ivals, columns=[character(len=8) :: "id", "count"], &
                           caption="Integer counts.", label="tab:i1")
        call include_table(cvals, columns=[character(len=8) :: "key", "status"], &
                           caption="String status.", label="tab:c1")

        ! Non-destructive repeated save to SVG and PDF.
        call save("/tmp/fplotlib_test_rep.svg", status=st)
        ncase = ncase + 1
        inquire (file="/tmp/fplotlib_test_rep.svg", exist=ex, size=sz)
        if (.not. st%ok() .or. .not. ex .or. sz <= 0) then
            nfail = nfail + 1
            print "(a)", "  FAIL report save SVG"
        end if

        call save("/tmp/fplotlib_test_rep.pdf", status=st)
        ncase = ncase + 1
        inquire (file="/tmp/fplotlib_test_rep.pdf", exist=ex, size=sz)
        if (.not. st%ok() .or. .not. ex .or. sz <= 0) then
            nfail = nfail + 1
            print "(a)", "  FAIL report save PDF"
        end if

        ! In-memory byte export via render_report.
        call render_report("svg", svg_assets, status=st)
        ncase = ncase + 1
        if (.not. st%ok() .or. size(svg_assets) < 1) then
            nfail = nfail + 1
            print "(a)", "  FAIL render_report svg"
        else
            call expect("report svg path", svg_assets(1)%bytes, "<path", ncase, nfail)
        end if

        call render_report("pdf", pdf_assets, status=st)
        ncase = ncase + 1
        if (.not. st%ok() .or. size(pdf_assets) /= 1) then
            nfail = nfail + 1
            print "(a)", "  FAIL render_report pdf"
        else if (len(pdf_assets(1)%bytes) < 5) then
            nfail = nfail + 1
            print "(a)", "  FAIL render_report pdf length"
        else
            call expect("report pdf header", pdf_assets(1)%bytes(1:5), "%PDF-", ncase, nfail)
        end if

        call render_report("png", png_assets, dpi=72.0_dp, status=st)
        ncase = ncase + 1
        if (.not. st%ok() .or. size(png_assets) < 1) then
            nfail = nfail + 1
            print "(a)", "  FAIL render_report png"
        else if (len(png_assets(1)%bytes) < 8) then
            nfail = nfail + 1
            print "(a)", "  FAIL render_report png length"
        end if

        ! new_report resets state cleanly.
        call new_report()
        call markdown("Fresh report.")
        call render_report("svg", svg_assets, status=st)
        ncase = ncase + 1
        if (.not. st%ok() .or. size(svg_assets) /= 1) then
            nfail = nfail + 1
            print "(a)", "  FAIL new_report reset"
        end if

        ! Explicit report_t works independently with zero global state.
        call rep%markdown("# Explicit")
        call rep%include_table(rvals, columns=[character(len=8) :: "x", "f(x)"], fmt="F0.2")
        call rep%export("pdf", pdf_assets, status=st)
        ncase = ncase + 1
        if (.not. st%ok() .or. size(pdf_assets) /= 1) then
            nfail = nfail + 1
            print "(a)", "  FAIL explicit report_t export"
        end if
        call rep%clear()

        open (newunit=u, file="/tmp/fplotlib_test_rep.svg", status="old", iostat=ios)
        if (ios == 0) close (u, status="delete")
        open (newunit=u, file="/tmp/fplotlib_test_rep.pdf", status="old", iostat=ios)
        if (ios == 0) close (u, status="delete")
    end subroutine report_cases

end module test_markdown
