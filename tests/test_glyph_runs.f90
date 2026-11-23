! Glyph runs that keep the source text they were set from: the UTF-8
! range of each glyph, runs and rule lists built by hand, PDF ActualText,
! and SVG text and group names.
module test_glyph_runs
    use fplotlib_style, only: dp
    use fplotlib_render, only: glyphrun_t, paint_t
    use fplotlib_text, only: text_layout
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
    ! needs; what XML 1.0 cannot hold at all is U+FFFD. Group names are
    ! escaped, and one shaped like an id the backend makes itself is
    ! renamed rather than taking that id.
    subroutine svg_text_check(nfail)
        integer, intent(inout) :: nfail
        character(len=200) :: out
        character(len=:), allocatable :: b
        type(svg_renderer_t) :: svg
        integer :: n

        ! "A", U+1F600, U+1D465 (math italic x), U+0001, a tab.
        call xml_escape_to("A"//achar(240)//achar(159)//achar(152)//achar(128) &
                           //achar(240)//achar(157)//achar(145)//achar(165)//achar(1)//achar(9), out, n)
        call check(out(1:n) == "A&#128512;&#119909;&#65533;"//achar(9), &
                   "SVG escapes code points of six digits and control characters", nfail)
        call svg%open_canvas(10.0_dp, 10.0_dp)
        call svg%begin_group('a"b')
        call svg%end_group()
        call svg%begin_group("clip1")
        call svg%end_group()
        call svg%close_canvas()
        b = svg%bytes()
        call check(index(b, 'id="a&quot;b"') > 0, "SVG escapes group names", nfail)
        call check(index(b, 'id="clip1"') == 0 .and. index(b, 'id="clip1-2"') > 0, &
                   "SVG group names never take the backend's own ids", nfail)
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
