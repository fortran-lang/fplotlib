! An explicit, retained report builder. The procedural facade owns a default
! instance; this module never accesses a current report or a current figure.
module fplotlib_report
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

    subroutine report_clear(self)
        class(report_t), intent(inout) :: self
        call doc_init(self%content)
        call self%pages%clear()
        self%figures = 0
        self%initialized = .true.
        self%dirty = .true.
    end subroutine report_clear

    subroutine initialize(self)
        class(report_t), intent(inout) :: self
        if (.not. self%initialized) call self%clear()
    end subroutine initialize

    subroutine report_markdown_text(self, text)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: text
        call initialize(self)
        ! Front matter belongs at the beginning, not in every appended block.
        if (self%content%n == 1 .and. self%content%nmeta == 0) then
            call md_parse(text, self%content)
        else
            call md_append(text, self%content)
        end if
        self%dirty = .true.
    end subroutine report_markdown_text

    subroutine report_markdown_lines(self, lines)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: lines(:)
        character(len=:), allocatable :: text
        integer :: i
        text = ""
        do i = 1, size(lines)
            text = text//trim(lines(i))//achar(10)
        end do
        call self%markdown_text(text)
    end subroutine report_markdown_lines

    ! Snapshot already captured graphics; layout and the plotting facade are
    ! deliberately separate. Width, if supplied, is in PostScript points.
    subroutine report_include_frame(self, frame, caption, label, width)
        class(report_t), intent(inout) :: self
        type(frame_t), intent(in) :: frame
        character(len=*), intent(in), optional :: caption, label
        real(dp), intent(in), optional :: width
        integer :: node, child
        call initialize(self)
        if (present(width)) then
            if (.not. ieee_is_finite(width) .or. width <= 0.0_dp) &
                error stop "include_figure: width must be finite and positive"
        end if
        self%figures = self%figures + 1
        node = doc_add(self%content, 1, DOC_FIGURE)
        self%content%nodes(node)%number = integer_text(self%figures)
        if (present(label)) self%content%nodes(node)%id = label
        if (present(width)) self%content%nodes(node)%width = width
        child = doc_add_frame(self%content, node, frame)
        call add_caption(self%content, node, "Figure", caption)
        self%dirty = .true.
    end subroutine report_include_frame

    subroutine report_table_text(self, values, columns, caption, label)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        call append_table(self, values, columns, caption, label, .false.)
    end subroutine report_table_text

    ! Numeric formatting is frontend policy. Preformatted character cells are
    ! also accepted, so callers retain control over units and precision.
    subroutine report_table_real(self, values, columns, caption, label)
        class(report_t), intent(inout) :: self
        real(dp), intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        character(len=64), allocatable :: text(:, :)
        character(len=:), allocatable :: cells(:, :)
        integer :: i, j, width, ios
        allocate (text(size(values, 1), size(values, 2)))
        width = 1
        do j = 1, size(values, 2)
            do i = 1, size(values, 1)
                write (text(i, j), "(g0.6)", iostat=ios) values(i, j)
                if (ios /= 0) error stop "include_table: cannot format real value"
                width = max(width, len_trim(text(i, j)))
            end do
        end do
        allocate (character(len=width) :: cells(size(values, 1), size(values, 2)))
        cells = text
        call append_table(self, cells, columns, caption, label, .true.)
    end subroutine report_table_real

    subroutine report_table_integer(self, values, columns, caption, label)
        class(report_t), intent(inout) :: self
        integer, intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        character(len=64), allocatable :: text(:, :)
        character(len=:), allocatable :: cells(:, :)
        integer :: i, j, width, ios
        allocate (text(size(values, 1), size(values, 2)))
        width = 1
        do j = 1, size(values, 2)
            do i = 1, size(values, 1)
                write (text(i, j), "(i0)", iostat=ios) values(i, j)
                if (ios /= 0) error stop "include_table: cannot format integer value"
                width = max(width, len_trim(text(i, j)))
            end do
        end do
        allocate (character(len=width) :: cells(size(values, 1), size(values, 2)))
        cells = text
        call append_table(self, cells, columns, caption, label, .true.)
    end subroutine report_table_integer

    subroutine append_table(self, cells, columns, caption, label, numeric)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: cells(:, :)
        character(len=*), intent(in), optional :: columns(:), caption, label
        logical, intent(in) :: numeric
        integer :: node
        call initialize(self)
        node = doc_add_table(self%content, 1, cells, columns, numeric)
        self%content%nodes(node)%number = integer_text(self%content%ntables)
        if (present(label)) self%content%nodes(node)%id = label
        call add_caption(self%content, node, "Table", caption)
        self%dirty = .true.
    end subroutine append_table

    subroutine add_caption(tree, parent, kind, caption)
        type(doc_t), intent(inout) :: tree
        integer, intent(in) :: parent
        character(len=*), intent(in) :: kind
        character(len=*), intent(in), optional :: caption
        integer :: node
        if (.not. present(caption)) return
        if (len_trim(caption) == 0) return
        node = doc_add(tree, parent, DOC_DIV)
        call md_append("**"//kind//" "//tree%nodes(parent)%number//".** "//caption, tree, node)
    end subroutine add_caption

    subroutine layout(self)
        class(report_t), intent(inout) :: self
        call initialize(self)
        if (.not. self%dirty) return
        call doc_typeset(self%workspace, self%content, self%pages)
        self%dirty = .false.
    end subroutine layout

    subroutine report_export(self, format, assets, dpi)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: format
        type(document_asset_t), allocatable, intent(out) :: assets(:)
        real(dp), intent(in), optional :: dpi
        call layout(self)
        call export_document(self%pages, format, assets, dpi)
    end subroutine report_export

    subroutine report_save(self, filename, dpi)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: filename
        real(dp), intent(in), optional :: dpi
        call layout(self)
        call save_document(self%pages, filename, dpi)
    end subroutine report_save

    integer function report_page_count(self) result(n)
        class(report_t), intent(inout) :: self
        call layout(self)
        n = self%pages%page_count()
    end function report_page_count

    subroutine report_page_frame(self, page, frame)
        class(report_t), intent(inout) :: self
        integer, intent(in) :: page
        type(frame_t), intent(out) :: frame
        call layout(self)
        call self%pages%page_frame(page, frame)
    end subroutine report_page_frame

    function integer_text(i) result(text)
        integer, intent(in) :: i
        character(len=:), allocatable :: text
        character(len=32) :: buffer
        write (buffer, "(i0)") i
        text = trim(buffer)
    end function integer_text

end module fplotlib_report
