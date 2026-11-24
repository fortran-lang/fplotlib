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
    use fplotlib_render, only: renderer_t, glyphrun_t, paint_t
    use fplotlib_glyphs, only: glyph_char, glyph_face, glyph_adv, FACE_REGULAR, FACE_BOLD, &
                               FACE_ITALIC
    use fplotlib_markdown, only: md_typeset, md_meta
    use fplotlib_typeset, only: ts_page_count, ts_page_draw, ts_page_size
    implicit none
    private

    public :: markdown_check

    character, parameter :: NL = achar(10), FF = achar(12)
    character(len=*), parameter :: BULLET = achar(226)//achar(128)//achar(162)

    type, extends(renderer_t) :: text_renderer_t
        integer :: n = 0
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
        print "(a,i0,a,i0)", "markdown: ", ncase, " documents, failures = ", nfail
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
        call set_doc("---"//NL//"note: "//long//NL//"---"//NL//"Text.", t, f)
        ncase = ncase + 1
        if (md_meta("note") /= long) then
            nfail = nfail + 1
            print "(a,i0,a)", "  FAIL markdown long value: md_meta gave ", len(md_meta("note")), &
                " characters of 300"
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

    ! ------------------------------------------------------------------
    ! Setting a document and reading it back.
    ! ------------------------------------------------------------------

    ! The text of document md's pages, the face of each of its bytes
    ! ("0" + face, " " for a space or line end), the lowest baseline on
    ! any page and the leftmost glyph.
    subroutine set_doc(md, text, faces, lowest, leftmost)
        character(len=*), intent(in) :: md
        character(len=:), allocatable, intent(out) :: text, faces
        real(dp), intent(out), optional :: lowest, leftmost
        type(text_renderer_t) :: r
        real(dp) :: w, h
        integer :: p, col

        call md_typeset(md)
        call ts_page_size(w, h, col)
        text = ""
        faces = ""
        if (present(lowest)) lowest = 0.0_dp
        if (present(leftmost)) leftmost = huge(1.0_dp)
        do p = 1, ts_page_count()
            call r%open_canvas(w, h)
            call ts_page_draw(r, p)
            call r%close_canvas()
            if (present(lowest) .and. r%n > 0) lowest = max(lowest, maxval(r%y(1:r%n)))
            if (present(leftmost) .and. r%n > 0) leftmost = min(leftmost, minval(r%x(1:r%n)))
            if (p > 1) then
                text = text//FF
                faces = faces//" "
            end if
            call page_lines(r, text, faces)
        end do
    end subroutine set_doc

    ! The glyphs of a page, sorted into lines, appended to text and faces.
    subroutine page_lines(r, text, faces)
        type(text_renderer_t), intent(inout) :: r
        character(len=:), allocatable, intent(inout) :: text, faces
        integer, allocatable :: order(:)
        character(len=:), allocatable :: c
        integer :: i, j, k, t
        order = [(i, i=1, r%n)]
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
        integer :: k
        do k = 1, run%n
            self%x = [self%x(1:self%n), x + run%x(k)]
            self%y = [self%y(1:self%n), y]
            self%adv = [self%adv(1:self%n), glyph_adv(run%gid(k))*run%size(k)]
            self%cp = [self%cp(1:self%n), glyph_char(run%gid(k))]
            self%face = [self%face(1:self%n), glyph_face(run%gid(k))]
            self%n = self%n + 1
        end do
    end subroutine tr_glyphs

    subroutine tr_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(text_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint
    end subroutine tr_image

end module test_markdown
