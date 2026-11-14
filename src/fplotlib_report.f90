! An explicit, retained report builder. The procedural facade owns a default
! instance; this module never accesses a current report or a current figure.
module fplotlib_report
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_doctree
    use fplotlib_markdown, only: md_parse, md_append
    use fplotlib_docclass, only: layout_context_t, doc_typeset
    use fplotlib_scene, only: frame_t, paged_document_t
    use fplotlib_document, only: document_asset_t, export_document, save_document
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private
    public :: report_t

    type :: report_t
        private
        type(doc_t) :: content
        type(layout_context_t) :: workspace
        type(paged_document_t) :: pages
        logical :: initialized = .false., dirty = .true.
        integer :: figures = 0
    contains
        procedure :: clear => report_clear
        procedure, private :: markdown_text => report_markdown_text
        procedure, private :: markdown_lines => report_markdown_lines
        generic :: markdown => markdown_text, markdown_lines
        procedure :: include_frame => report_include_frame
        procedure, private :: table_text => report_table_text
        procedure, private :: table_real => report_table_real
        procedure, private :: table_integer => report_table_integer
        generic :: include_table => table_text, table_real, table_integer
        procedure :: export => report_export
        procedure :: save => report_save
        procedure :: page_count => report_page_count
        procedure :: page_frame => report_page_frame
    end type report_t

contains

    subroutine report_clear(self, status)
        class(report_t), intent(inout) :: self
        type(status_t), intent(out) :: status
        call doc_init(self%content, status=status)
        if (.not. status%ok()) return
        call self%pages%clear(status=status)
        if (.not. status%ok()) return
        self%figures = 0
        self%initialized = .true.
        self%dirty = .true.
    end subroutine report_clear

    subroutine initialize(self, status)
        class(report_t), intent(inout) :: self
        type(status_t), intent(out) :: status
        if (.not. self%initialized) then
            call self%clear(status=status)
            if (.not. status%ok()) return
        end if
    end subroutine initialize

    subroutine report_markdown_text(self, text, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: text
        type(status_t), intent(out) :: status
        call initialize(self, status=status)
        if (.not. status%ok()) return
        ! Front matter belongs at the beginning, not in every appended block.
        if (self%content%n == 1 .and. self%content%nmeta == 0) then
            call md_parse(text, self%content, status=status)
            if (.not. status%ok()) return
        else
            call md_append(text, self%content, status=status)
            if (.not. status%ok()) return
        end if
        self%dirty = .true.
    end subroutine report_markdown_text

    subroutine report_markdown_lines(self, lines, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: lines(:)
        character(len=:), allocatable :: text
        integer :: i
        type(status_t), intent(out) :: status
        text = ""
        do i = 1, size(lines)
            text = text//trim(lines(i))//achar(10)
        end do
        call self%markdown_text(text, status=status)
        if (.not. status%ok()) return
    end subroutine report_markdown_lines

    ! Snapshot already captured graphics; layout and the plotting facade are
    ! deliberately separate. Width, if supplied, is in PostScript points.
    subroutine report_include_frame(self, frame, caption, label, width, status)
        class(report_t), intent(inout) :: self
        type(frame_t), intent(in) :: frame
        character(len=*), intent(in), optional :: caption, label
        real(dp), intent(in), optional :: width
        integer :: node, child
        real(dp) :: frame_width, frame_height
        type(status_t), intent(out) :: status
        call initialize(self, status=status)
        if (.not. status%ok()) return
        if (present(width)) then
            if (.not. ieee_is_finite(width) .or. width <= 0.0_dp) then
                call status%set(ERROR_ARGUMENT, "include_figure: width must be finite and positive")
                return
            end if
        end if
        call frame%metrics(frame_width, frame_height, status=status)
        if (.not. status%ok()) return
        if (frame_width <= 0.0_dp .or. frame_height <= 0.0_dp) then
            call status%set(ERROR_ARGUMENT, "include_frame: empty graphics")
            return
        end if
        self%figures = self%figures + 1
        node = doc_add(self%content, 1, DOC_FIGURE, status=status)
        if (.not. status%ok()) return
        self%content%nodes(node)%number = integer_text(self%figures)
        if (present(label)) self%content%nodes(node)%id = label
        if (present(width)) self%content%nodes(node)%width = width
        child = doc_add_frame(self%content, node, frame, status=status)
        if (.not. status%ok()) return
        call add_caption(self%content, node, "Figure", caption, status=status)
        if (.not. status%ok()) return
        self%dirty = .true.
    end subroutine report_include_frame

    subroutine report_table_text(self, values, columns, caption, label, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        type(status_t), intent(out) :: status
        call append_table(self, values, columns, caption, label, .false., status=status)
        if (.not. status%ok()) return
    end subroutine report_table_text

    ! Numeric formatting is frontend policy. Preformatted character cells are
    ! also accepted, so callers retain control over units and precision.
    subroutine report_table_real(self, values, columns, caption, label, status)
        class(report_t), intent(inout) :: self
        real(dp), intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        character(len=64), allocatable :: text(:, :)
        character(len=:), allocatable :: cells(:, :)
        integer :: i, j, width, ios
        type(status_t), intent(out) :: status
        allocate (text(size(values, 1), size(values, 2)))
        width = 1
        do j = 1, size(values, 2)
            do i = 1, size(values, 1)
                write (text(i, j), "(g0.6)", iostat=ios) values(i, j)
                if (ios /= 0) then
                    call status%set(ERROR_IO, "include_table: cannot format real value")
                    return
                end if
                width = max(width, len_trim(text(i, j)))
            end do
        end do
        allocate (character(len=width) :: cells(size(values, 1), size(values, 2)))
        cells = text
        call append_table(self, cells, columns, caption, label, .true., status=status)
        if (.not. status%ok()) return
    end subroutine report_table_real

    subroutine report_table_integer(self, values, columns, caption, label, status)
        class(report_t), intent(inout) :: self
        integer, intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        character(len=64), allocatable :: text(:, :)
        character(len=:), allocatable :: cells(:, :)
        integer :: i, j, width, ios
        type(status_t), intent(out) :: status
        allocate (text(size(values, 1), size(values, 2)))
        width = 1
        do j = 1, size(values, 2)
            do i = 1, size(values, 1)
                write (text(i, j), "(i0)", iostat=ios) values(i, j)
                if (ios /= 0) then
                    call status%set(ERROR_IO, "include_table: cannot format integer value")
                    return
                end if
                width = max(width, len_trim(text(i, j)))
            end do
        end do
        allocate (character(len=width) :: cells(size(values, 1), size(values, 2)))
        cells = text
        call append_table(self, cells, columns, caption, label, .true., status=status)
        if (.not. status%ok()) return
    end subroutine report_table_integer

    subroutine append_table(self, cells, columns, caption, label, numeric, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: cells(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        logical, intent(in) :: numeric
        integer :: node
        type(status_t), intent(out) :: status
        call initialize(self, status=status)
        if (.not. status%ok()) return
        node = doc_add_table(self%content, 1, cells, columns, numeric, status=status)
        if (.not. status%ok()) return
        self%content%nodes(node)%number = integer_text(self%content%ntables)
        if (present(label)) self%content%nodes(node)%id = label
        call add_caption(self%content, node, "Table", caption, status=status)
        if (.not. status%ok()) return
        self%dirty = .true.
    end subroutine append_table

    subroutine add_caption(tree, parent, kind, caption, status)
        type(doc_t), intent(inout) :: tree
        integer, intent(in) :: parent
        character(len=*), intent(in) :: kind
        character(len=*), intent(in), optional :: caption
        integer :: node
        type(status_t), intent(out) :: status
        if (.not. present(caption)) return
        if (len_trim(caption) == 0) return
        node = doc_add(tree, parent, DOC_DIV, status=status)
        if (.not. status%ok()) return
        call md_append("**"//kind//" "//tree%nodes(parent)%number//".** "//caption, tree, node, status=status)
        if (.not. status%ok()) return
    end subroutine add_caption

    subroutine layout(self, status)
        class(report_t), intent(inout) :: self
        type(status_t), intent(out) :: status
        call initialize(self, status=status)
        if (.not. status%ok()) return
        if (.not. self%dirty) return
        call doc_typeset(self%workspace, self%content, self%pages, status=status)
        if (.not. status%ok()) return
        self%dirty = .false.
    end subroutine layout

    subroutine report_export(self, format, assets, dpi, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: format
        type(document_asset_t), allocatable, intent(out) :: assets(:)
        real(dp), intent(in), optional :: dpi
        type(status_t), intent(out) :: status
        call layout(self, status=status)
        if (.not. status%ok()) return
        call export_document(self%pages, format, assets, dpi, status=status)
        if (.not. status%ok()) return
    end subroutine report_export

    subroutine report_save(self, filename, dpi, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: filename
        real(dp), intent(in), optional :: dpi
        type(status_t), intent(out) :: status
        call layout(self, status=status)
        if (.not. status%ok()) return
        call save_document(self%pages, filename, dpi, status=status)
        if (.not. status%ok()) return
    end subroutine report_save

    integer function report_page_count(self, status) result(n)
        class(report_t), intent(inout) :: self
        type(status_t), intent(out) :: status

        n = 0
        call layout(self, status=status)
        if (.not. status%ok()) return
        n = self%pages%page_count()
    end function report_page_count

    subroutine report_page_frame(self, page, frame, status)
        class(report_t), intent(inout) :: self
        integer, intent(in) :: page
        type(frame_t), intent(out) :: frame
        type(status_t), intent(out) :: status
        call layout(self, status=status)
        if (.not. status%ok()) return
        call self%pages%page_frame(page, frame, status=status)
        if (.not. status%ok()) return
    end subroutine report_page_frame

    function integer_text(i) result(text)
        integer, intent(in) :: i
        character(len=:), allocatable :: text
        character(len=32) :: buffer
        write (buffer, "(i0)") i
        text = trim(buffer)
    end function integer_text

end module fplotlib_report
