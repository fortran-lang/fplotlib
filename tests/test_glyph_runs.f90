! Glyph runs that keep the source text they were set from: the UTF-8
! range of each glyph, runs and rule lists built by hand, PDF ActualText,
! and SVG text and group names.
module test_glyph_runs
    use fplotlib_style, only: dp
    use fplotlib_render, only: glyphrun_t, paint_t
    use fplotlib_text, only: text_layout, run_add
    use fplotlib_glyphs, only: glyph_cmap, FACE_REGULAR
    use fplotlib_backend_pdf, only: pdf_renderer_t
    use fplotlib_backend_svg, only: svg_renderer_t
    use fplotlib_svg, only: xml_escape_to
    use fplotlib_mathtext, only: math_formula, mrules_t
    implicit none
    private
    public :: glyph_runs_check

contains

    subroutine glyph_runs_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call source_ranges(nfail)
        call hand_built_runs(nfail)
        call pdf_text_check(nfail)
        call svg_text_check(nfail)
        call hand_built_rules(nfail)
        call own_glyph(nfail)
        call long_formulas(nfail)
        print "(a,i0)", "glyph runs: failures = ", nfail
    end subroutine glyph_runs_check

    subroutine check(ok, message, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: message
        integer, intent(inout) :: nfail
        if (ok) return
        print "(a)", "  FAIL "//message
        nfail = nfail + 1
    end subroutine check

    ! Each glyph keeps the UTF-8 bytes it was set from, a cluster all of
    ! its glyphs, and the run its source text.
    subroutine source_ranges(nfail)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run
        character(len=:), allocatable :: source
        real(dp) :: advance
        source = "A"//achar(204)//achar(138)//achar(226)//achar(132)//achar(131)
        call text_layout(source, 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance)
        call check(run%n == 3, "normalization and Celsius expansion", nfail)
        if (run%n == 3) then
            call check(all(run%first(1:3) == [1, 4, 4]) .and. &
                       all(run%last(1:3) == [3, 6, 6]), "UTF-8 glyph cluster ranges", nfail)
        end if
        call check(run%text == source, "normalization preserves logical source", nfail)
    end subroutine source_ranges

    ! A glyph run built by hand without each glyph's font and source,
    ! which the renderer contract takes as optional, can still be added to
    ! by text_layout, and one whose arrays differ in length grows by the
    ! shortest.
    subroutine hand_built_runs(nfail)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run, uneven
        real(dp) :: advance

        allocate (run%gid(1), run%x(1), run%y(1), run%size(1))
        run%gid = 1
        run%x = 0.0_dp
        run%y = 0.0_dp
        run%size = 10.0_dp
        run%n = 1
        call text_layout("BC", 10.0_dp, FACE_REGULAR, 5.0_dp, 0.0_dp, run, advance)
        call check(run%n == 3, "text_layout adds to a run without fonts or source ranges", nfail)
        if (run%n == 3) then
            call check(run%first(1) == 0 .and. run%last(1) == 0 .and. &
                       all(run%first(2:3) == [1, 2]), "the hand-built glyph keeps no source", nfail)
        end if

        ! A run built by hand with gid longer than x, y and size grows by
        ! its shortest array, not by gid.
        allocate (uneven%gid(8), uneven%x(1), uneven%y(1), uneven%size(1))
        uneven%gid = 1
        uneven%x = 0.0_dp
        uneven%y = 0.0_dp
        uneven%size = 10.0_dp
        uneven%n = 1
        call text_layout("BCDEFG", 10.0_dp, FACE_REGULAR, 5.0_dp, 0.0_dp, uneven, advance)
        call check(uneven%n == 7 .and. size(uneven%x) >= 7 .and. size(uneven%size) >= 7, &
                   "a run with arrays of different lengths grows by the shortest", nfail)
    end subroutine hand_built_runs

    ! SVG text goes out as character references for anything past ASCII,
    ! of six and seven digits too, as an emoji or a math italic letter
    ! needs, and what XML 1.0 cannot hold at all as U+FFFD: one written form
    ! for each code point. Group names are escaped, compared as written, and
    ! never take an id the backend makes itself.
    subroutine svg_text_check(nfail)
        integer, intent(inout) :: nfail
        character(len=200) :: out
        character(len=:), allocatable :: b
        type(svg_renderer_t) :: svg
        type(paint_t) :: paint
        type(glyphrun_t) :: run
        integer :: n

        ! "A", U+1F600, U+1D465 (math italic x), U+10FFFD, U+0001, a tab.
        call xml_escape_to("A"//achar(240)//achar(159)//achar(152)//achar(128) &
                           //achar(240)//achar(157)//achar(145)//achar(165) &
                           //achar(244)//achar(143)//achar(191)//achar(189)//achar(1)//achar(9), out, n)
        call check(out(1:n) == "A&#128512;&#119909;&#1114109;&#65533;&#9;", &
                   "SVG escapes code points of six and seven digits, and control characters", nfail)
        ! A surrogate, U+FFFE, and a code past U+10FFFF: none is XML.
        call xml_escape_to(achar(237)//achar(160)//achar(128)//achar(239)//achar(191)//achar(190) &
                           //achar(244)//achar(144)//achar(128)//achar(128), out, n)
        call check(out(1:n) == "&#65533;&#65533;&#65533;", "SVG writes what XML cannot hold as U+FFFD", nfail)
        ! An overlong "c" is written as "c"; trailing blanks stay when asked.
        call xml_escape_to(achar(193)//achar(163)//"d ", out, n)
        call check(out(1:n) == "cd", "SVG writes bytes that decode to ASCII as that character", nfail)
        call xml_escape_to("d ", out, n, whole=.true.)
        call check(out(1:n) == "d ", "SVG keeps trailing blanks when asked", nfail)

        paint%filled = .true.
        paint%clip%on = .true.
        paint%clip%w = 5.0_dp
        paint%clip%h = 5.0_dp
        call svg%open_canvas(10.0_dp, 10.0_dp)
        ! The backend's own clip1.
        call svg%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, paint)
        call svg%begin_group('a"b')
        call svg%end_group()
        call svg%begin_group("clip1")
        call svg%end_group()
        call svg%begin_group(achar(193)//achar(163)//"lip1")
        call svg%end_group()
        call svg%begin_group("clip1 ")
        call svg%end_group()
        call svg%begin_group(achar(1)//"x")
        call svg%end_group()
        call svg%begin_group(achar(2)//"x")
        call svg%end_group()
        ! In an attribute a reader reads a raw tab, newline or return as a
        ! space: written as references, these four are four ids.
        call svg%begin_group("a b")
        call svg%end_group()
        call svg%begin_group("a"//achar(9)//"b")
        call svg%end_group()
        call svg%begin_group("a"//achar(10)//"b")
        call svg%end_group()
        call svg%begin_group("a"//achar(13)//"b")
        call svg%end_group()
        call svg%begin_group("m2")
        call svg%end_group()
        call svg%begin_group("g40")
        call svg%end_group()
        ! Text whose control characters each take eight bytes written.
        run%n = 1
        allocate (run%gid(1), run%x(1), run%y(1), run%size(1))
        run%gid = glyph_cmap(FACE_REGULAR, 65)
        run%x = 0.0_dp
        run%y = 5.0_dp
        run%size = 10.0_dp
        run%text = "a"//repeat(achar(1), 6)//"Z"
        paint%clip%on = .false.
        call svg%draw_glyphs(0.0_dp, 0.0_dp, run, paint, 0.0_dp)
        call svg%close_canvas()
        b = svg%bytes()
        call check(index(b, 'id="a&quot;b"') > 0, "SVG escapes group names", nfail)
        call check(occurrences(b, 'id="clip1"') == 1 .and. index(b, 'id="clip1-2"') > 0 .and. &
                   index(b, 'id="clip1-3"') > 0, "SVG group names never take the backend's own ids", nfail)
        call check(index(b, 'id="clip1 "') > 0, "SVG keeps a group name's trailing blank", nfail)
        call check(index(b, 'id="a b"') > 0 .and. index(b, 'id="a&#9;b"') > 0 .and. &
                   index(b, 'id="a&#10;b"') > 0 .and. index(b, 'id="a&#13;b"') > 0, &
                   "SVG writes tab, newline and return in a group name as references", nfail)
        call check(index(b, 'id="m2-2"') > 0 .and. index(b, 'id="g40-2"') > 0, &
                   "SVG renames group names shaped like a marker's or glyph's id", nfail)
        call check(index(b, 'id="&#65533;x"') > 0 .and. index(b, 'id="&#65533;x-2"') > 0, &
                   "SVG group names that read alike are different ids", nfail)
        call check(index(b, 'aria-label="a'//repeat("&#65533;", 6)//'Z"') > 0, &
                   "SVG writes all of a label's text", nfail)
    end subroutine svg_text_check

    ! A rule list built by hand with x longer than y, w and h grows by its
    ! shortest array when a formula adds to it.
    subroutine hand_built_rules(nfail)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        real(dp) :: w, h, d

        allocate (rules%x(8), rules%y(1), rules%w(1), rules%h(1))
        rules%x = 0.0_dp
        rules%y = 0.0_dp
        rules%w = 1.0_dp
        rules%h = 1.0_dp
        rules%n = 1
        call math_formula("\frac{a}{b}+\sqrt{c}", 10.0_dp, .false., run, rules, w, h, d)
        call check(rules%n >= 3 .and. size(rules%y) >= rules%n .and. size(rules%h) >= rules%n, &
                   "a rule list with arrays of different lengths grows by the shortest", nfail)
    end subroutine hand_built_rules

    ! run_add given a glyph of the run it adds to, when the run is full:
    ! the glyph is read before the run grows, which would free it.
    subroutine own_glyph(nfail)
        integer, intent(inout) :: nfail
        type(glyphrun_t) :: run
        real(dp) :: advance
        integer :: k

        call text_layout(repeat("A", 16), 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance)
        k = run%n
        call run_add(run, run%gid(1), run%x(1), run%y(1), run%size(1))
        call check(run%n == k + 1 .and. run%gid(run%n) == run%gid(1) .and. &
                   run%x(run%n) == run%x(1), "run_add takes a glyph of the run it grows", nfail)
    end subroutine own_glyph

    ! Formulas long enough that parsing a part of one adds more noads than
    ! there is room for, while the noad the part belongs to is being
    ! stored into: under the sanitizer job, a part stored straight from the
    ! parse into the array the parse has moved is a use after free. Each
    ! of the stores is reached: the parts of \frac, \binom and \cfrac, a
    ! root's radicand and index, \overline, an accent, \left...\right,
    ! and, as their place in the array depends on how full it is, \over,
    ! automatic parentheses and a cube root after 1 to 140 atoms.
    subroutine long_formulas(nfail)
        integer, intent(inout) :: nfail
        character(len=:), allocatable :: many, tex
        character(len=*), parameter :: cbrt = achar(226)//achar(136)//achar(155)
        integer :: k, m
        logical :: ok

        many = ""
        do k = 1, 150
            many = many//"a "
        end do
        call lays_out("\frac{"//many//"}{"//many//"}", "\frac")
        call lays_out("\binom{"//many//"}{"//many//"}", "\binom")
        call lays_out("\cfrac{"//many//"}{"//many//"}", "\cfrac")
        call lays_out("\sqrt{"//many//"}", "\sqrt")
        call lays_out("\sqrt["//many//"]{x}", "\sqrt[...]")
        call lays_out("\overline{"//many//"}", "\overline")
        call lays_out("\hat{"//many//"}", "an accent")
        call lays_out("\left("//many//"\right)", "\left...\right")
        call lays_out(cbrt//"{"//many//"}", "a cube root")
        ok = .true.
        do m = 1, 140
            tex = "("//repeat("a ", m)//") \over b"
            ok = ok .and. formula_ok(tex)
            tex = "("//repeat("a ", m)//"(b))"
            ok = ok .and. formula_ok(tex)
            tex = repeat("a ", m)//cbrt//"x"
            ok = ok .and. formula_ok(tex)
        end do
        call check(ok, "formulas with \over, parentheses and a cube root after 1 to 140 atoms lay out", nfail)
    contains
        subroutine lays_out(tex, what)
            character(len=*), intent(in) :: tex, what
            call check(formula_ok(tex), "a long formula with "//what//" lays out whole", nfail)
        end subroutine lays_out

        logical function formula_ok(tex)
            character(len=*), intent(in) :: tex
            type(glyphrun_t) :: run
            type(mrules_t) :: rules
            real(dp) :: w, h, d
            call math_formula(tex, 10.0_dp, .false., run, rules, w, h, d)
            formula_ok = run%n >= 1 .and. w > 0.0_dp
        end function formula_ok
    end subroutine long_formulas

    subroutine pdf_text_check(nfail)
        integer, intent(inout) :: nfail
        type(pdf_renderer_t) :: pdf
        type(paint_t) :: paint
        type(glyphrun_t) :: run
        character(len=:), allocatable :: document

        run%n = 3
        allocate (run%gid(3), run%font(3), run%first(3), run%last(3))
        allocate (run%x(3), run%y(3), run%size(3))
        run%gid = [glyph_cmap(FACE_REGULAR, 65), glyph_cmap(FACE_REGULAR, 233), glyph_cmap(FACE_REGULAR, 63)]
        run%font = FACE_REGULAR
        run%x = [0.0_dp, 12.0_dp, 24.0_dp]
        run%y = 0.0_dp
        run%size = 12.0_dp
        run%first = [1, 2, 4]
        run%last = [1, 3, 7]
        ! The emoji has a fallback outline, but extraction must retain its source.
        run%text = "Aé😀"
        paint%filled = .true.
        call pdf%open_canvas(100.0_dp, 80.0_dp)
        call pdf%draw_glyphs(5.0_dp, 15.0_dp, run, paint, 0.0_dp)

        run%text = "$A^2$"
        run%source_math = .true.
        run%first = 0
        run%last = 0
        call pdf%draw_glyphs(5.0_dp, 35.0_dp, run, paint, 0.0_dp)
        deallocate (run%text)
        run%source_math = .false.
        call pdf%draw_glyphs(5.0_dp, 55.0_dp, run, paint, 0.0_dp)
        call pdf%close_canvas()
        document = pdf%bytes()

        call check(index(document, "/ActualText <FEFF004100E9D83DDE00>") > 0, &
                    "PDF ActualText retains BMP and supplementary Unicode", nfail)
        call check(occurrences(document, "/ActualText") == 1 .and. occurrences(document, "EMC") == 1, &
                    "PDF excludes TeX source and unmapped runs from ActualText", nfail)
        call check(occurrences(document, "BT"//new_line("a")) == 3 .and. &
                    occurrences(document, "ET"//new_line("a")) == 3 .and. &
                    index(document, "/ToUnicode") > 0 .and. index(document, "beginbfchar") > 0, &
                    "PDF still paints and maps text without ActualText", nfail)
    end subroutine pdf_text_check

    integer function occurrences(text, token) result(n)
        character(len=*), intent(in) :: text, token
        integer :: offset, found

        n = 0
        offset = 1
        do while (offset <= len(text))
            found = index(text(offset:), token)
            if (found == 0) exit
            n = n + 1
            offset = offset + found - 1 + len(token)
        end do
    end function occurrences

end module test_glyph_runs
