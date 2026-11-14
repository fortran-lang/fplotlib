module test_report
    use fplotlib_status
    use test_status
    use fplotlib, only: dp, markdown, new_report, include_figure, include_table, save, render_report, &
                        figure, plot, title, clf, render_png
    use fplotlib_report, only: report_t
    use fplotlib_scene, only: frame_t
    use fplotlib_document, only: document_asset_t
    implicit none
    private
    public :: report_check

contains

    subroutine report_check(nfail)
        integer, intent(out) :: nfail
        nfail = 0
        call procedural_report(nfail)
        call independent_reports(nfail)
        call table_pages(nfail)
        print "(a,i0)", "immediate reports: failures = ", nfail
    end subroutine report_check

    subroutine check(ok, message, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: message
        integer, intent(inout) :: nfail
        if (ok) return
        print "(a)", "  FAIL "//message
        nfail = nfail + 1
    end subroutine check

    subroutine procedural_report(nfail)
        integer, intent(inout) :: nfail
        type(document_asset_t), allocatable :: before(:), after(:), pdf(:)
        character(len=16) :: cells(1, 2)
        character(len=:), allocatable :: picture, data
        integer :: u, n

        ! No initialization call: the first document operation starts it.
        call markdown("# Immediate report")
        call markdown("See Figure @fig:original and Table @tab:original.")
        call figure(figsize=[2.5_dp, 1.5_dp], dpi=72.0_dp)
        call plot([0.0_dp, 1.0_dp], [1.0_dp, 0.0_dp])
        call title("Original plot")
        picture = render_png()
        call include_figure(caption="Captured figure.", label="fig:original")
        call check(render_png() == picture, "including a figure does not clear or change it", nfail)
        cells(1, :) = ["Original cell   ", "literal $value  "]
        call include_table(cells, columns=["Name", "Data"], caption="Captured values.", label="tab:original")
        cells = "Changed cells"
        call clf()
        call title("Unrelated plot")
        call render_report("svg", before)
        call check(index(before(1)%bytes, "Original plot") > 0, "figure is captured at include time", nfail)
        call check(index(before(1)%bytes, "Unrelated plot") == 0, "later plotting does not alter report", nfail)
        call check(index(before(1)%bytes, "Original cell") > 0 .and. &
                   index(before(1)%bytes, "Changed cells") == 0, "table input is copied immediately", nfail)
        call check(index(before(1)%bytes, "literal $value") > 0, "table cells are plain text", nfail)
        call check(index(before(1)%bytes, "@fig:original") == 0 .and. &
                   index(before(1)%bytes, "@tab:original") == 0, "forward references resolve at layout", nfail)

        call save("tests/out/immediate_report.pdf")
        call render_report("pdf", pdf)
        inquire (file="tests/out/immediate_report.pdf", size=n)
        allocate (character(len=n) :: data)
        open (newunit=u, file="tests/out/immediate_report.pdf", access="stream", form="unformatted", status="old")
        read (u) data
        close (u)
        call check(data == pdf(1)%bytes, "save exports the current retained report", nfail)
        call render_report("svg", after)
        call check(before(1)%bytes == after(1)%bytes, "saving in another format is non-destructive", nfail)

        call markdown("Appended after export.")
        call render_report("svg", after)
        call check(index(after(1)%bytes, "Appended after export.") > 0 .and. &
                   index(after(1)%bytes, "Original cell") > 0, "appending invalidates cached layout without clearing", nfail)
        picture = render_png()
        call new_report()
        call check(render_png() == picture, "new_report does not reset plotting", nfail)
        call markdown("Replacement report.")
        call render_report("svg", after)
        call check(index(after(1)%bytes, "Replacement report.") > 0 .and. &
                   index(after(1)%bytes, "Original cell") == 0, "new_report replaces the old description", nfail)
        call new_report()
    end subroutine procedural_report

    subroutine independent_reports(nfail)
        integer, intent(inout) :: nfail
        type(report_t) :: a, b
        type(frame_t) :: page
        type(document_asset_t), allocatable :: before(:), after(:)
        real(dp) :: numbers(1, 2)
        integer :: counts(1, 2), u, n
        character(len=:), allocatable :: text, label, data
        type(status_t) :: status
        character(len=:), allocatable :: source_text_value1
        label = "tab:"//repeat("long_label_", 8)//"end"
        call a%markdown("See Table @"//label//".", status=status)
        call require_ok(status)
        numbers(1, :) = [1.25_dp, 2.5_dp]
        call a%include_table(numbers, columns=["Left ", "Right"], label=label, caption="Numeric values.", status=status)
        call require_ok(status)
        numbers = -99.0_dp
        counts(1, :) = [7, 11]
        call a%include_table(counts, columns=["Left ", "Right"], caption="Integer values.", status=status)
        call require_ok(status)
        call a%export("svg", before, status=status)
        call require_ok(status)
        call b%markdown("Another report.", status=status)
        call require_ok(status)
        call b%clear(status=status)
        call require_ok(status)
        call markdown("Default report remains independent.")
        call a%export("svg", after, status=status)
        call require_ok(status)
        call check(before(1)%bytes == after(1)%bytes, "explicit reports do not share the default session", nfail)
        call a%page_frame(1, page, status=status)
        call require_ok(status)
        text = page%source_text(status=status)
        call require_ok(status)
        call check(index(text, "See Table 1.") > 0, "long named table reference is retained", nfail)
        call check(index(text, "1.25000") > 0 .and. index(text, "-99") == 0, "numeric values are snapshotted", nfail)
        call check(index(text, "7") > 0 .and. index(text, "11") > 0, "integer tables reach layout", nfail)
        call a%save("tests/out/explicit_report.pdf", status=status)
        call require_ok(status)
        call a%export("pdf", after, status=status)
        call require_ok(status)
        inquire (file="tests/out/explicit_report.pdf", size=n)
        allocate (character(len=n) :: data)
        open (newunit=u, file="tests/out/explicit_report.pdf", access="stream", form="unformatted", status="old")
        read (u) data
        close (u)
        call check(data == after(1)%bytes, "explicit save uses the report's cached pages", nfail)
        call a%clear(status=status)
        call require_ok(status)
        source_text_value1 = page%source_text(status=status)
        call require_ok(status)
        call check(index(source_text_value1, "See Table 1.") > 0, "exported page outlives report reset", nfail)
        call new_report()
    end subroutine independent_reports

    subroutine table_pages(nfail)
        integer, intent(inout) :: nfail
        type(report_t) :: report
        type(frame_t) :: page
        character(len=56) :: cells(60, 2)
        character(len=8) :: row
        character(len=:), allocatable :: text, all_text
        integer :: i, p, pages
        type(status_t) :: status
        do i = 1, size(cells, 1)
            write (cells(i, 1), "(a,i3.3)") "ROW", i
            cells(i, 2) = "A description which can wrap within its column."
        end do
        call report%markdown([character(len=32) :: "---", "paper: a6", "margin: 12pt", &
                              "fontsize: 9pt", "pagenumbers: false", "---", "", "Introductory paragraph."], status=status)
        call require_ok(status)
        call report%include_table(cells, columns=["Index      ", "Description"], caption="Rows across pages.", status=status)
        call require_ok(status)
        cells = "Overwritten"
        pages = report%page_count(status=status)
        call require_ok(status)
        call check(pages > 1, "long table paginates", nfail)
        all_text = ""
        do p = 1, pages
            call report%page_frame(p, page, status=status)
            call require_ok(status)
            text = page%source_text(status=status)
            call require_ok(status)
            call check(occurrences(text, "Index") == 1, "table header repeats exactly once per page", nfail)
            all_text = all_text//text
        end do
        do i = 1, 60
            write (row, "(a,i3.3)") "ROW", i
            call check(occurrences(all_text, trim(row)) == 1, "table row is neither lost nor duplicated", nfail)
        end do
    end subroutine table_pages

    integer function occurrences(text, needle) result(n)
        character(len=*), intent(in) :: text, needle
        integer :: i, j
        n = 0
        i = 1
        do while (i <= len(text))
            j = index(text(i:), needle)
            if (j == 0) exit
            n = n + 1
            i = i + j - 1 + len(needle)
        end do
    end function occurrences

end module test_report
