module test_grid
    use fplotlib_status
    use test_status
    use fplotlib_style, only: dp
    use fplotlib_grid, only: grid_widths, grid_row
    use fplotlib_typeset
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY
    use fplotlib_render, only: glyphrun_t, paint_t, clip_t
    use fplotlib_text, only: text_layout, run_copy
    use fplotlib_glyphs, only: FACE_REGULAR, FACE_MATH, glyph_cmap, glyph_adv, glyph_kern
    implicit none
    private
    public :: grid_check

    type :: text_sample_t
        character(len=:), allocatable :: text
        type(glyphrun_t) :: run
        real(dp) :: x = 0.0_dp, y = 0.0_dp
        integer :: rgb(3) = 0
    end type text_sample_t

    type :: rect_sample_t
        real(dp) :: x = 0.0_dp, y = 0.0_dp, w = 0.0_dp, h = 0.0_dp
        integer :: rgb(3) = 0
    end type rect_sample_t

    ! Observe the public renderer stream, including the frame transforms.
    type, extends(recording_renderer_t) :: probe_t
        integer :: n = 0, nr = 0, level = 0
        real(dp) :: matrix(6, 0:64)
        type(text_sample_t), allocatable :: text(:)
        type(rect_sample_t), allocatable :: rect(:)
    contains
        procedure :: begin_frame => probe_begin
        procedure :: end_frame => probe_end
        procedure :: draw_glyphs => probe_glyphs
        procedure :: draw_rect => probe_rect
    end type probe_t

contains

    subroutine grid_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call widths_check(nfail)
        call word_width_check(nfail)
        call plain_text_check(nfail)
        call row_check(nfail)
        call pages_check(.true., 0, nfail)
        call pages_check(.true., 1, nfail)
        call pages_check(.true., 5, nfail)
        call pages_check(.false., 0, nfail)
        call repeat_metrics_check(nfail)
        print "(a,i0)", "grid failures: ", nfail
    end subroutine grid_check

    subroutine check(ok, message, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: message
        integer, intent(inout) :: nfail
        if (ok) return
        print "(a)", "  FAIL "//message
        nfail = nfail + 1
    end subroutine check

    subroutine widths_check(nfail)
        integer, intent(inout) :: nfail
        real(dp), allocatable :: widths(:)
        real(dp) :: empty(0), extra(3)

        type(status_t) :: status
        call grid_widths([30.0_dp, 50.0_dp, 20.0_dp], [10.0_dp, 20.0_dp, 20.0_dp], &
                         150.0_dp, 2.0_dp, widths, status=status)
        call require_ok(status)
        extra = widths - [34.0_dp, 54.0_dp, 24.0_dp]
        call check(abs(sum(widths) - 150.0_dp) < 1.0e-10_dp .and. minval(extra) > 0.0_dp, &
                   "columns use the available width including padding", nfail)
        call check(maxval(extra) - minval(extra) < 1.0e-10_dp, "extra width is shared equally", nfail)
        call grid_widths([60.0_dp, 30.0_dp, 10.0_dp], [20.0_dp, 10.0_dp, 10.0_dp], &
                         80.0_dp, 2.0_dp, widths, status=status)
        call require_ok(status)
        call check(abs(sum(widths) - 80.0_dp) < 1.0e-10_dp .and. &
                   all(widths >= [24.0_dp, 14.0_dp, 14.0_dp]) .and. &
                   widths(1) < 64.0_dp .and. widths(2) < 34.0_dp .and. widths(3) == 14.0_dp, &
                   "flexible columns shrink without shrinking a column at its minimum", nfail)
        call grid_widths([60.0_dp, 30.0_dp, 10.0_dp], [20.0_dp, 10.0_dp, 10.0_dp], &
                         52.0_dp, 2.0_dp, widths, status=status)
        call require_ok(status)
        call check(all(widths == [24.0_dp, 14.0_dp, 14.0_dp]), "exact minimum fit", nfail)
        call grid_widths([5.0_dp, 0.0_dp], [10.0_dp, 0.0_dp], 14.0_dp, 1.0_dp, widths, status=status)
        call require_ok(status)
        call check(all(widths == [12.0_dp, 2.0_dp]), "minimum takes precedence over preferred width", nfail)
        call grid_widths(empty, empty, 0.0_dp, 0.0_dp, widths, status=status)
        call require_ok(status)
        call check(size(widths) == 0, "empty column arrays are allocated explicitly", nfail)
    end subroutine widths_check

    subroutine word_width_check(nfail)
        use fplotlib_text, only: text_width
        use fplotlib_mathtext, only: math_width
        integer, intent(inout) :: nfail
        character(len=3), parameter :: double_struck_c = achar(226)//achar(132)//achar(130)
        integer :: g
        real(dp) :: measured, expected

        type(status_t) :: status
        call text_width("label", -1.0_dp, FACE_REGULAR, measured, status)
        call check(status%code == ERROR_ARGUMENT, "text measurement propagates an invalid size", nfail)
        call math_width("$x$", -1.0_dp, measured, status=status)
        call check(status%code == ERROR_ARGUMENT, "math measurement propagates an invalid size", nfail)
        call ts_word_width("label", FACE_REGULAR, -1.0_dp, measured, status)
        call check(status%code == ERROR_ARGUMENT, "word measurement propagates an invalid size", nfail)
        g = glyph_cmap(FACE_MATH, 8450)
        call check(glyph_cmap(FACE_REGULAR, 8450) == 0 .and. g > 0, &
                   "double-struck C exercises the math-face fallback", nfail)
        if (g == 0) return
        call ts_word_width(double_struck_c//double_struck_c, FACE_REGULAR, 12.0_dp, measured, status=status)
        call require_ok(status)
        expected = (2.0_dp*glyph_adv(g) + glyph_kern(FACE_MATH, g, g))*12.0_dp
        call check(abs(measured - expected) < 1.0e-10_dp, &
                   "plain word width uses the actual math-fallback advances and kerning", nfail)
    end subroutine word_width_check

    subroutine plain_text_check(nfail)
        integer, intent(inout) :: nfail
        type(typeset_context_t) :: state
        type(frame_t) :: frame
        type(probe_t) :: probe
        character(len=:), allocatable :: source

        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
        character(len=:), allocatable :: source_text_value2
        character(len=:), allocatable :: source_text_value3
        character(len=:), allocatable :: source_text_value4
        source = "  A"//achar(204)//achar(138)//"  "//achar(226)//achar(132)//achar(131)// &
                 achar(9)//"*literal* \alpha $x$"//achar(13)//achar(10)//"tail  "
        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, 400.0_dp, 200.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false., status=status)
        call require_ok(status)
        call ts_set_font(state, 12.0_dp, status=status)
        call require_ok(status)
        call ts_begin_par(state, ALIGN_LEFT, 0.0_dp, status=status)
        call require_ok(status)
        call ts_text(state, source, FACE_REGULAR, 12.0_dp, color=[18, 52, 86], status=status)
        call require_ok(status)
        call ts_finish_frame(state, frame, status=status)
        call require_ok(status)
        source_text_value1 = frame%source_text(status=status)
        call require_ok(status)
        call check(source_text_value1 == source, "plain UTF-8 retains whitespace and literal markup", nfail)
        call check(ts_line_count(state) == 2, "CRLF is one hard line break", nfail)
        call observe(frame, probe)
        call check(probe%n == 2, "plain text paints two lines", nfail)
        if (probe%n >= 2) then
            call check(probe%text(2)%y > probe%text(1)%y, "hard break moves text to the next baseline", nfail)
            call check(all(probe%text(1)%rgb == [18, 52, 86]), "plain text uses its requested colour", nfail)
            call check(.not. probe%text(1)%run%source_math, "plain TeX-like text is not math", nfail)
            if (probe%text(1)%run%n >= 3) then
                call check(all(probe%text(1)%run%first(1:3) == [3, 8, 8]) .and. &
                           all(probe%text(1)%run%last(1:3) == [5, 10, 10]), &
                           "plain text retains combining and expanded UTF-8 clusters", nfail)
            else
                call check(.false., "plain text retains its visible glyphs", nfail)
            end if
        end if

        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_begin_par(state, ALIGN_CENTER, 0.0_dp, status=status)
        call require_ok(status)
        source = "one"//achar(10)//achar(10)//"two"
        call ts_text(state, source, FACE_REGULAR, 10.0_dp, status=status)
        call require_ok(status)
        call ts_finish_frame(state, frame, status=status)
        call require_ok(status)
        source_text_value2 = frame%source_text(status=status)
        call require_ok(status)
        call check(source_text_value2 == source, "centred hard breaks retain blank lines in source", nfail)
        call observe(frame, probe)
        if (probe%n == 2) then
            call check(probe%text(2)%y - probe%text(1)%y > 20.0_dp, "blank line retains vertical space", nfail)
        else
            call check(.false., "centred plain text retains both lines", nfail)
        end if

        call ts_reset(state, status=status)
        call require_ok(status)
        source = "  "//achar(9)
        call ts_text(state, source, FACE_REGULAR, 10.0_dp, status=status)
        call require_ok(status)
        call ts_finish_frame(state, frame, status=status)
        call require_ok(status)
        source_text_value3 = frame%source_text(status=status)
        call require_ok(status)
        call check(source_text_value3 == source, "whitespace-only plain text retains its source", nfail)

        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, 40.0_dp, 200.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, numbers=.false., status=status)
        call require_ok(status)
        call ts_begin_par(state, ALIGN_LEFT, 0.0_dp, status=status)
        call require_ok(status)
        source = "one two  three four"
        call ts_text(state, source, FACE_REGULAR, 10.0_dp, status=status)
        call require_ok(status)
        call ts_finish_frame(state, frame, status=status)
        call require_ok(status)
        source_text_value4 = frame%source_text(status=status)
        call require_ok(status)
        call check(ts_line_count(state) > 1 .and. source_text_value4 == source, &
                   "wrapping preserves plain source whitespace exactly once", nfail)
    end subroutine plain_text_check

    subroutine cell(text, width, height, baseline, size, frame)
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width, height, baseline, size
        type(frame_t), intent(out) :: frame
        type(recording_renderer_t) :: recorder
        type(glyphrun_t) :: run
        type(paint_t) :: paint
        real(dp) :: advance
        type(status_t) :: status
        call text_layout(text, size, FACE_REGULAR, 0.0_dp, 0.0_dp, run, advance, status=status)
        call require_ok(status)
        paint%filled = .true.
        call recorder%open_canvas(width, height, status=status)
        call require_ok(status)
        call recorder%draw_glyphs(0.0_dp, baseline, run, paint, 0.0_dp, status=status)
        call require_ok(status)
        call recorder%close_canvas(status=status)
        call require_ok(status)
        call recorder%take(frame, status=status)
        call require_ok(status)
        call frame%set_baseline(baseline, status=status)
        call require_ok(status)
    end subroutine cell

    subroutine row_check(nfail)
        integer, intent(inout) :: nfail
        type(frame_t) :: cells(2), row
        type(probe_t) :: probe
        real(dp) :: w, h, baseline

        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
        character(len=:), allocatable :: source_text_value2
        call cell("Up", 40.0_dp, 16.0_dp, 12.0_dp, 12.0_dp, cells(1))
        call cell("down", 60.0_dp, 20.0_dp, 8.0_dp, 9.0_dp, cells(2))
        call grid_row(cells, [44.0_dp, 64.0_dp], 2.0_dp, row, [210, 220, 230], [255, 0, 0], status=status)
        call require_ok(status)
        call row%metrics(w, h, baseline, status=status)
        call require_ok(status)
        call check(w == 108.0_dp .and. h == 28.0_dp .and. baseline == h, &
                   "row accommodates both ascents and descents with a bottom baseline", nfail)
        call observe(row, probe)
        source_text_value1 = row%source_text(status=status)
        call require_ok(status)
        call check(probe%n == 2 .and. source_text_value1 == "Updown", "both cells reach the row", nfail)
        if (probe%n == 2) then
            call check(probe%text(1)%x == 2.0_dp .and. probe%text(2)%x == 46.0_dp .and. &
                       probe%text(1)%y == 14.0_dp .and. probe%text(2)%y == 14.0_dp, &
                       "actual cell text shares the first baseline and respects column padding", nfail)
        end if
        call check(probe%nr == 2, "row records its background and bottom rule", nfail)
        if (probe%nr == 2) then
            call check(all(probe%rect(1)%rgb == [210, 220, 230]) .and. &
                       probe%rect(1)%w == w .and. probe%rect(1)%h == h, "background covers the row", nfail)
            call check(all(probe%rect(2)%rgb == [255, 0, 0]) .and. &
                       probe%rect(2)%h > 0.0_dp .and. probe%rect(2)%h < 1.0_dp .and. &
                       abs(probe%rect(2)%y + probe%rect(2)%h - h) < 1.0e-10_dp, &
                       "thin rule stays inside the bottom edge", nfail)
        end if
        call grid_row(cells, [44.0_dp, 64.0_dp], 2.0_dp, row, status=status)
        call require_ok(status)
        call observe(row, probe)
        call check(probe%nr == 0, "row decoration is optional", nfail)
        call cells(1)%init(0.0_dp, 0.0_dp, status=status)
        call require_ok(status)
        call cells(2)%init(0.0_dp, 0.0_dp, status=status)
        call require_ok(status)
        source_text_value2 = row%source_text(status=status)
        call require_ok(status)
        call check(source_text_value2 == "Updown", "row owns its imported cells", nfail)
    end subroutine row_check

    subroutine pages_check(with_header, intro_lines, nfail)
        logical, intent(in) :: with_header
        integer, intent(in) :: intro_lines
        integer, intent(inout) :: nfail
        type(typeset_context_t) :: state
        type(paged_document_t) :: document
        type(frame_t) :: cells(2), row, page
        type(probe_t) :: probe
        character(len=:), allocatable :: source, all_text
        character(len=6) :: label
        integer :: header, handle, i, p, j, rows, np, page_rows, header_pages, previous, at
        integer :: seen(9)
        logical :: positions, headers

        type(status_t) :: status
        rows = 9
        if (with_header) rows = 7
        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, 200.0_dp, 100.0_dp, 10.0_dp, 10.0_dp, 10.0_dp, 10.0_dp, numbers=.false., status=status)
        call require_ok(status)
        if (intro_lines > 0) then
            call ts_begin_par(state, ALIGN_LEFT, 0.0_dp, status=status)
            call require_ok(status)
            do i = 1, intro_lines
                if (i > 1) then
                    call ts_text(state, achar(10), FACE_REGULAR, 10.0_dp, status=status)
                    call require_ok(status)
                end if
                call ts_text(state, "Preface", FACE_REGULAR, 10.0_dp, status=status)
                call require_ok(status)
            end do
            call ts_end_par(state, status=status)
            call require_ok(status)
            call ts_vskip(state, ts_glue_t(8.0_dp), status=status)
            call require_ok(status)
        end if
        header = 0
        if (with_header) then
            call cell("HEADER", 46.0_dp, 10.0_dp, 8.0_dp, 8.0_dp, cells(1))
            call cell("VALUE", 66.0_dp, 10.0_dp, 8.0_dp, 8.0_dp, cells(2))
            call grid_row(cells, [50.0_dp, 70.0_dp], 2.0_dp, row, status=status)
            call require_ok(status)
            call ts_import_frame(state, row, header, status=status)
            call require_ok(status)
            call ts_place_frame(state, header, 7.0_dp, 5.0_dp, ALIGN_CENTER, interline=.false., status=status)
            call require_ok(status)
            call ts_penalty(state, 10000)
        end if
        do i = 1, rows
            if (i > 1) call ts_penalty(state, 0)
            write (label, "(a,i3.3)") "ROW", i
            call cell(label, 46.0_dp, 16.0_dp, 12.0_dp, 9.0_dp, cells(1))
            call cell("value", 66.0_dp, 16.0_dp, 12.0_dp, 9.0_dp, cells(2))
            call grid_row(cells, [50.0_dp, 70.0_dp], 2.0_dp, row, status=status)
            call require_ok(status)
            call ts_import_frame(state, row, handle, status=status)
            call require_ok(status)
            call ts_place_frame(state, handle, 7.0_dp, 5.0_dp, ALIGN_CENTER, &
                                interline=.false., repeat_before=header, status=status)
            call require_ok(status)
        end do
        call ts_finish(state, document, status=status)
        call require_ok(status)
        np = document%page_count()
        call check(np >= 3, "packed final rows paginate without a trailing penalty", nfail)
        if (intro_lines == 0) call check(np == 3, "header reservation determines page capacity", nfail)
        seen = 0
        all_text = ""
        positions = .true.
        headers = .true.
        header_pages = 0
        do p = 1, np
            call document%page_frame(p, page, status=status)
            call require_ok(status)
            source = page%source_text(status=status)
            call require_ok(status)
            all_text = all_text//source
            page_rows = 0
            do i = 1, rows
                write (label, "(a,i3.3)") "ROW", i
                at = occurrences(source, label)
                seen(i) = seen(i) + at
                page_rows = page_rows + at
            end do
            if (with_header .and. page_rows > 0) then
                header_pages = header_pages + 1
                if (occurrences(source, "HEADER") /= 1) headers = .false.
                if (index(source, "HEADER") > index(source, "ROW")) headers = .false.
                if (p > 1 .and. index(source, "HEADER") /= 1) headers = .false.
            else
                if (occurrences(source, "HEADER") /= 0) headers = .false.
            end if
            call observe(page, probe)
            do j = 1, probe%n
                if (index(probe%text(j)%text, "ROW") /= 1 .and. probe%text(j)%text /= "HEADER") cycle
                if (abs(probe%text(j)%x - 43.0_dp) > 1.0e-10_dp) positions = .false.
                if (probe%text(j)%y < 10.0_dp .or. probe%text(j)%y + 6.0_dp > 90.0_dp) positions = .false.
            end do
            if (intro_lines == 1 .and. p == 1) then
                call check(index(source, "Preface") == 1 .and. index(source, "ROW001") > 1, &
                           "table begins after the paragraph on the same page", nfail)
            end if
        end do
        call check(all(seen(1:rows) == 1), "every table row occurs on exactly one page", nfail)
        call check(headers, "each table page has exactly one header, or none when disabled", nfail)
        call check(positions, "continuation headers share row offsets and rows stay inside the body", nfail)
        if (with_header) call check(occurrences(all_text, "HEADER") == header_pages, &
                                   "initial header is not repeated twice", nfail)
        previous = 0
        do i = 1, rows
            write (label, "(a,i3.3)") "ROW", i
            at = index(all_text, label)
            call check(at > previous, "rows retain their order across pages", nfail)
            previous = at
        end do
        call check(occurrences(all_text, "Preface") == intro_lines, "paragraphs survive table pagination", nfail)
    end subroutine pages_check

    subroutine repeat_metrics_check(nfail)
        integer, intent(inout) :: nfail
        type(typeset_context_t) :: state
        type(frame_t) :: header, cells(1), row, frame
        type(paged_document_t) :: document
        type(probe_t) :: probe
        integer :: head, handle, i, p
        real(dp) :: w, h, baseline

        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
        character(len=:), allocatable :: source_text_value2
        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, 80.0_dp, 46.0_dp, 10.0_dp, 10.0_dp, 10.0_dp, 10.0_dp, numbers=.false., status=status)
        call require_ok(status)
        call cell("HDR", 40.0_dp, 12.0_dp, 3.0_dp, 3.0_dp, header)
        call cell("body", 40.0_dp, 4.0_dp, 2.0_dp, 2.0_dp, cells(1))
        call grid_row(cells, [40.0_dp], 0.0_dp, row, status=status)
        call require_ok(status)
        call ts_import_frame(state, header, head, status=status)
        call require_ok(status)
        call ts_import_frame(state, row, handle, status=status)
        call require_ok(status)
        call ts_place_frame(state, head, interline=.false., status=status)
        call require_ok(status)
        call ts_penalty(state, 10000)
        do i = 1, 3
            if (i > 1) call ts_penalty(state, 0)
            call ts_place_frame(state, handle, interline=.false., repeat_before=head, status=status)
            call require_ok(status)
        end do
        call ts_finish_frame(state, frame, status=status)
        call require_ok(status)
        call frame%metrics(w, h, baseline, status=status)
        call require_ok(status)
        source_text_value1 = frame%source_text(status=status)
        call require_ok(status)
        source_text_value2 = frame%source_text(status=status)
        call require_ok(status)
        call check(occurrences(source_text_value1, "HDR") == 1 .and. &
                   occurrences(source_text_value2, "body") == 3 .and. h == 31.0_dp, &
                   "natural flow has adjoining rows and never synthesizes continuation headers", nfail)
        call ts_finish(state, document, status=status)
        call require_ok(status)
        call check(document%page_count() == 3, "repeated header reserves its full depth and topskip", nfail)
        do p = 1, document%page_count()
            call document%page_frame(p, frame, status=status)
            call require_ok(status)
            call observe(frame, probe)
            call check(probe%n == 2, "short continuation page contains header and body", nfail)
            if (probe%n == 2) then
                call check(probe%text(1)%y == 20.0_dp .and. probe%text(2)%y == 31.0_dp, &
                           "header gets topskip once and short body row gets none", nfail)
            end if
        end do

        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, 80.0_dp, 60.0_dp, 10.0_dp, 10.0_dp, 10.0_dp, 10.0_dp, numbers=.false., status=status)
        call require_ok(status)
        call ts_import_frame(state, header, head, status=status)
        call require_ok(status)
        call ts_import_frame(state, row, handle, status=status)
        call require_ok(status)
        call ts_place_frame(state, head, interline=.false., status=status)
        call require_ok(status)
        call ts_penalty(state, 10000)
        call ts_place_frame(state, handle, interline=.false., repeat_before=head, status=status)
        call require_ok(status)
        call ts_page_break(state, status=status)
        call require_ok(status)
        call ts_place_frame(state, handle, interline=.false., repeat_before=head, status=status)
        call require_ok(status)
        call ts_vfil(state, status=status)
        call require_ok(status)
        call ts_place_frame(state, handle, interline=.false., repeat_before=head, status=status)
        call require_ok(status)
        call ts_finish(state, document, status=status)
        call require_ok(status)
        call check(document%page_count() == 2, "forced continuation page retains its header", nfail)
        call document%page_frame(2, frame, status=status)
        call require_ok(status)
        call observe(frame, probe)
        call check(probe%n == 3, "glue-fitted continuation page retains both rows", nfail)
        if (probe%n == 3) then
            call check(probe%text(2)%y == 31.0_dp .and. probe%text(3)%y == 48.0_dp, &
                       "page glue fitting accounts for the repeated header reservation", nfail)
        end if
    end subroutine repeat_metrics_check

    integer function occurrences(text, word) result(n)
        character(len=*), intent(in) :: text, word
        integer :: first, found
        n = 0
        first = 1
        do
            found = index(text(first:), word)
            if (found == 0) return
            n = n + 1
            first = first + found - 1 + len(word)
        end do
    end function occurrences

    subroutine observe(frame, probe)
        type(frame_t), intent(in) :: frame
        type(probe_t), intent(inout) :: probe
        real(dp) :: w, h
        type(status_t) :: status
        probe%n = 0
        probe%nr = 0
        probe%level = 0
        probe%matrix(:, 0) = IDENTITY
        if (allocated(probe%text)) deallocate (probe%text, probe%rect)
        allocate (probe%text(128), probe%rect(128))
        call frame%metrics(w, h, status=status)
        call require_ok(status)
        call probe%open_canvas(w, h, status=status)
        call require_ok(status)
        call frame%draw(probe, status=status)
        call require_ok(status)
        call probe%close_canvas(status=status)
        call require_ok(status)
    end subroutine observe

    subroutine probe_begin(self, matrix, clip, status)
        class(probe_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        real(dp) :: old(6)
        type(status_t), intent(out) :: status
        old = self%matrix(:, self%level)
        self%level = self%level + 1
        if (self%level > ubound(self%matrix, 2)) error stop "grid test: transform stack overflow"
        self%matrix(:, self%level) = [old(1)*matrix(1) + old(3)*matrix(2), &
                                      old(2)*matrix(1) + old(4)*matrix(2), &
                                      old(1)*matrix(3) + old(3)*matrix(4), &
                                      old(2)*matrix(3) + old(4)*matrix(4), &
                                      old(1)*matrix(5) + old(3)*matrix(6) + old(5), &
                                      old(2)*matrix(5) + old(4)*matrix(6) + old(6)]
        call self%recording_renderer_t%begin_frame(matrix, clip, status=status)
        if (.not. status%ok()) return
    end subroutine probe_begin

    subroutine probe_end(self, status)
        class(probe_t), intent(inout) :: self
        type(status_t), intent(out) :: status
        call self%recording_renderer_t%end_frame(status=status)
        if (.not. status%ok()) return
        self%level = self%level - 1
    end subroutine probe_end

    subroutine probe_glyphs(self, x, y, run, paint, angle, status)
        class(probe_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, angle
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp) :: m(6), gx, gy
        type(status_t), intent(out) :: status
        self%n = self%n + 1
        if (self%n > size(self%text)) error stop "grid test: text sample overflow"
        m = self%matrix(:, self%level)
        gx = x
        gy = y
        if (run%n > 0) then
            gx = gx + run%x(1)
            gy = gy + run%y(1)
        end if
        self%text(self%n)%x = m(1)*gx + m(3)*gy + m(5)
        self%text(self%n)%y = m(2)*gx + m(4)*gy + m(6)
        self%text(self%n)%rgb = paint%fill_rgb
        self%text(self%n)%text = ""
        if (allocated(run%text)) self%text(self%n)%text = run%text
        call run_copy(run, self%text(self%n)%run, status=status)
        if (.not. status%ok()) return
        call self%recording_renderer_t%draw_glyphs(x, y, run, paint, angle, status=status)
        if (.not. status%ok()) return
    end subroutine probe_glyphs

    subroutine probe_rect(self, x, y, w, h, paint, radius, status)
        class(probe_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        real(dp) :: m(6)
        type(status_t), intent(out) :: status
        self%nr = self%nr + 1
        if (self%nr > size(self%rect)) error stop "grid test: rectangle sample overflow"
        m = self%matrix(:, self%level)
        self%rect(self%nr)%x = m(1)*x + m(3)*y + m(5)
        self%rect(self%nr)%y = m(2)*x + m(4)*y + m(6)
        self%rect(self%nr)%w = w
        self%rect(self%nr)%h = h
        self%rect(self%nr)%rgb = paint%fill_rgb
        call self%recording_renderer_t%draw_rect(x, y, w, h, paint, radius, status=status)
        if (.not. status%ok()) return
    end subroutine probe_rect

end module test_grid
