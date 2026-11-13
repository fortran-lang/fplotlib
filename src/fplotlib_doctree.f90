! fplotlib_doctree -- a document as a tree, between a reader and a class.
!
! A reader (fplotlib_markdown) builds the tree from the text; a document
! class (fplotlib_docclass) sets it, with fplotlib_typeset, as LaTeX's
! article or book class would. The tree is Pandoc's: blocks hold blocks or
! inlines, inlines hold inlines, and the front matter is a list of keys
! and values. A program may build a tree itself and hand it to a class.
!
! Nodes live in one array; a node's children are a list from first to
! last through next. Node 1 is the root, the document's blocks.
module fplotlib_doctree
    use fplotlib_style, only: dp
    use fplotlib_scene, only: frame_t
    implicit none
    private

    public :: doc_t, doc_node_t, doc_meta_t, doc_table_t
    public :: doc_init, doc_add, doc_add_text, doc_add_meta, doc_plain, doc_add_frame, doc_add_table
    public :: DOC_ROOT, DOC_PARA, DOC_HEADING, DOC_LIST, DOC_ITEM, DOC_QUOTE, DOC_CODE, &
              DOC_RULE, DOC_DIV, DOC_RAW, DOC_INLINES, DOC_FRAME, DOC_FIGURE, DOC_TABLE
    public :: IN_STR, IN_SPACE, IN_BREAK, IN_EMPH, IN_STRONG, IN_CODE, IN_MATH, IN_LINK, &
              IN_SPAN, IN_RAW, IN_REF
    public :: REF_PLAIN, REF_EQ, REF_AT

    ! Blocks.
    integer, parameter :: DOC_ROOT = 1     ! the document: blocks
    integer, parameter :: DOC_PARA = 2     ! a paragraph: inlines
    integer, parameter :: DOC_HEADING = 3  ! level; id; inlines
    integer, parameter :: DOC_LIST = 4     ! ordered, start, tight, spaced; items
    integer, parameter :: DOC_ITEM = 5     ! a list item: blocks
    integer, parameter :: DOC_QUOTE = 6    ! a block quote: blocks
    integer, parameter :: DOC_CODE = 7     ! text, its lines as they are
    integer, parameter :: DOC_RULE = 8     ! a thematic break
    integer, parameter :: DOC_DIV = 9      ! attr; blocks
    integer, parameter :: DOC_RAW = 10     ! a TeX command, text (\newpage, \vspace{1cm})
    integer, parameter :: DOC_INLINES = 11 ! inlines not in a paragraph (a meta value)
    integer, parameter :: DOC_FRAME = 12   ! supplied graphics; num is its handle
    integer, parameter :: DOC_FIGURE = 13  ! frame and optional caption blocks
    integer, parameter :: DOC_TABLE = 14   ! num indexes tables; children are its caption
    ! Inlines.
    integer, parameter :: IN_STR = 20      ! text without spaces
    integer, parameter :: IN_SPACE = 21    ! a space between words
    integer, parameter :: IN_BREAK = 22    ! a hard line break
    integer, parameter :: IN_EMPH = 23     ! emphasis (\emph): inlines
    integer, parameter :: IN_STRONG = 24   ! strong (\textbf): inlines
    integer, parameter :: IN_CODE = 25     ! text, as it is
    integer, parameter :: IN_MATH = 26     ! TeX math, text; display; id
    integer, parameter :: IN_LINK = 27     ! text the target; inlines
    integer, parameter :: IN_SPAN = 28     ! attr; inlines
    integer, parameter :: IN_RAW = 29      ! a TeX command, text (hfill, quad, TeX)
    integer, parameter :: IN_REF = 30      ! a reference to the label id, written as ref
    ! How a reference is written: \ref, \eqref, or @name.
    integer, parameter :: REF_PLAIN = 0, REF_EQ = 1, REF_AT = 2

    type :: doc_node_t
        integer :: kind = 0
        integer :: first = 0, last = 0, next = 0
        ! A heading's level, a list's first number, a reference's form.
        integer :: num = 0
        ! A list: numbered, without space between items (tight), and after
        ! a blank line (spaced, which in LaTeX is a \par before the list).
        ! Math: displayed.
        logical :: ordered = .false., tight = .false., spaced = .false.
        logical :: display = .false.
        ! The text of a string, code, math, raw TeX, or a link's target.
        character(len=:), allocatable :: text
        ! A heading's, a display's or a reference's id.
        character(len=:), allocatable :: id
        ! A div's or a span's attributes, as written: .center size=20pt.
        character(len=:), allocatable :: attr
        character(len=:), allocatable :: number
        real(dp) :: width = 0.0_dp
    end type doc_node_t

    ! A key of the front matter: its value as written, and as inlines.
    type :: doc_meta_t
        character(len=:), allocatable :: key, value
        integer :: node = 0
    end type doc_meta_t

    type :: doc_table_t
        character(len=:), allocatable :: cells(:, :), headers(:)
        logical :: numeric = .false.
    end type doc_table_t

    type :: doc_t
        type(doc_node_t), allocatable :: nodes(:)
        integer :: n = 0
        type(doc_meta_t), allocatable :: meta(:)
        integer :: nmeta = 0
        type(frame_t) :: graphics
        integer :: ngraphics = 0
        type(doc_table_t), allocatable :: tables(:)
        integer :: ntables = 0
    end type doc_t

contains

    subroutine doc_init(doc)
        type(doc_t), intent(out) :: doc
        allocate (doc%nodes(64), doc%meta(16), doc%tables(4))
        doc%n = 1
        doc%nodes(1)%kind = DOC_ROOT
        doc%nmeta = 0
        call doc%graphics%init(0.0_dp, 0.0_dp)
    end subroutine doc_init

    ! A new node of the kind, the last child of parent; its index.
    integer function doc_add(doc, parent, kind) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, kind
        type(doc_node_t), allocatable :: tmp(:)
        if (doc%n == size(doc%nodes)) then
            allocate (tmp(2*size(doc%nodes)))
            tmp(1:doc%n) = doc%nodes(1:doc%n)
            call move_alloc(tmp, doc%nodes)
        end if
        doc%n = doc%n + 1
        k = doc%n
        doc%nodes(k)%kind = kind
        doc%nodes(k)%text = ""
        doc%nodes(k)%id = ""
        doc%nodes(k)%attr = ""
        doc%nodes(k)%number = ""
        if (parent > 0) then
            if (doc%nodes(parent)%last > 0) then
                doc%nodes(doc%nodes(parent)%last)%next = k
            else
                doc%nodes(parent)%first = k
            end if
            doc%nodes(parent)%last = k
        end if
    end function doc_add

    ! The same, with its text.
    integer function doc_add_text(doc, parent, kind, text) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, kind
        character(len=*), intent(in) :: text
        k = doc_add(doc, parent, kind)
        doc%nodes(k)%text = text
    end function doc_add_text

    integer function doc_add_frame(doc, parent, frame) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        type(frame_t), intent(in) :: frame
        integer :: handle
        call doc%graphics%add_frame(frame, handle)
        k = doc_add(doc, parent, DOC_FRAME)
        doc%nodes(k)%num = handle
        doc%ngraphics = doc%ngraphics + 1
    end function doc_add_frame

    integer function doc_add_table(doc, parent, cells, columns, numeric) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        character(len=*), intent(in) :: cells(:, :)
        character(len=*), intent(in), optional :: columns(:)
        logical, intent(in), optional :: numeric
        type(doc_table_t), allocatable :: tmp(:)
        integer :: i, nr, nc
        nr = size(cells, 1)
        nc = size(cells, 2)
        if (nc == 0) error stop "include_table: no columns"
        if (present(columns)) then
            if (size(columns) /= nc) error stop "include_table: column labels do not match data"
        end if
        if (doc%ntables == size(doc%tables)) then
            allocate (tmp(2*size(doc%tables)))
            do i = 1, doc%ntables
                tmp(i)%numeric = doc%tables(i)%numeric
                call move_alloc(doc%tables(i)%cells, tmp(i)%cells)
                call move_alloc(doc%tables(i)%headers, tmp(i)%headers)
            end do
            call move_alloc(tmp, doc%tables)
        end if
        doc%ntables = doc%ntables + 1
        i = doc%ntables
        allocate (character(len=max(1, len(cells))) :: doc%tables(i)%cells(nr, nc))
        doc%tables(i)%cells = cells
        if (present(columns)) then
            allocate (character(len=max(1, len(columns))) :: doc%tables(i)%headers(nc))
            doc%tables(i)%headers = columns
        end if
        if (present(numeric)) doc%tables(i)%numeric = numeric
        k = doc_add(doc, parent, DOC_TABLE)
        doc%nodes(k)%num = i
    end function doc_add_table

    ! A key of the front matter, its value, and the value as inlines (a
    ! DOC_INLINES node, not in the document, or 0).
    subroutine doc_add_meta(doc, key, value, node)
        type(doc_t), intent(inout) :: doc
        character(len=*), intent(in) :: key, value
        integer, intent(in) :: node
        type(doc_meta_t), allocatable :: tmp(:)
        if (doc%nmeta == size(doc%meta)) then
            allocate (tmp(2*size(doc%meta)))
            tmp(1:doc%nmeta) = doc%meta(1:doc%nmeta)
            call move_alloc(tmp, doc%meta)
        end if
        doc%nmeta = doc%nmeta + 1
        doc%meta(doc%nmeta)%key = key
        doc%meta(doc%nmeta)%value = value
        doc%meta(doc%nmeta)%node = node
    end subroutine doc_add_meta

    ! The text of node k's inlines, without their markup (math as $...$).
    recursive function doc_plain(doc, k) result(s)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        character(len=:), allocatable :: s
        integer :: c
        s = ""
        c = doc%nodes(k)%first
        do while (c > 0)
            select case (doc%nodes(c)%kind)
            case (IN_STR, IN_CODE)
                s = s//doc%nodes(c)%text
            case (IN_SPACE, IN_BREAK)
                s = s//" "
            case (IN_MATH)
                s = s//"$"//doc%nodes(c)%text//"$"
            case (IN_RAW, IN_REF)
            case default
                s = s//doc_plain(doc, c)
            end select
            c = doc%nodes(c)%next
        end do
    end function doc_plain

end module fplotlib_doctree
