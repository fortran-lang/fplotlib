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
    use fplotlib_status
    implicit none
    private

    public :: doc_t, doc_node_t, doc_meta_t, doc_table_t
    public :: doc_init, doc_add, doc_add_text, doc_add_meta, doc_plain, doc_add_frame, doc_add_table
    public :: doc_validate
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

    subroutine doc_init(doc, status)
        type(doc_t), intent(out) :: doc
        type(status_t), intent(out) :: status
        allocate (doc%nodes(64), doc%meta(16), doc%tables(4))
        doc%n = 1
        doc%nodes(1)%kind = DOC_ROOT
        doc%nmeta = 0
        call doc%graphics%init(0.0_dp, 0.0_dp, status=status)
        if (.not. status%ok()) return
    end subroutine doc_init

    ! A new node of the kind, the last child of parent; its index.
    integer function doc_add(doc, parent, kind, status) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, kind
        type(status_t), intent(out) :: status
        type(doc_node_t), allocatable :: tmp(:)

        k = 0
        k = 0
        call check_parent(doc, parent, status)
        if (.not. status%ok()) return
        if (.not. ((kind >= DOC_ROOT .and. kind <= DOC_TABLE) .or. (kind >= IN_STR .and. kind <= IN_REF))) then
            call status%set(ERROR_UNSUPPORTED, "doc_add: unsupported node kind")
            return
        end if
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
    integer function doc_add_text(doc, parent, kind, text, status) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent, kind
        character(len=*), intent(in) :: text
        type(status_t), intent(out) :: status

        k = 0
        k = doc_add(doc, parent, kind, status=status)
        if (.not. status%ok()) return
        doc%nodes(k)%text = text
    end function doc_add_text

    integer function doc_add_frame(doc, parent, frame, status) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        type(frame_t), intent(in) :: frame
        integer :: handle
        type(status_t), intent(out) :: status

        k = 0
        call check_parent(doc, parent, status=status)
        if (.not. status%ok()) return
        call doc%graphics%import_frame(frame, handle, status=status)
        if (.not. status%ok()) return
        k = doc_add(doc, parent, DOC_FRAME, status=status)
        if (.not. status%ok()) return
        doc%nodes(k)%num = handle
        doc%ngraphics = doc%ngraphics + 1
    end function doc_add_frame

    integer function doc_add_table(doc, parent, cells, columns, numeric, status) result(k)
        type(doc_t), intent(inout) :: doc
        integer, intent(in) :: parent
        character(len=*), intent(in) :: cells(:, :)
        character(len=*), intent(in), optional :: columns(:)
        logical, intent(in), optional :: numeric
        type(doc_table_t), allocatable :: tmp(:)
        integer :: i, nr, nc
        type(status_t), intent(out) :: status

        k = 0
        call check_parent(doc, parent, status=status)
        if (.not. status%ok()) return
        nr = size(cells, 1)
        nc = size(cells, 2)
        if (nc == 0) then
            call status%set(ERROR_ARGUMENT, "include_table: no columns")
            return
        end if
        if (present(columns)) then
            if (size(columns) /= nc) then
                call status%set(ERROR_ARGUMENT, "include_table: column labels do not match data")
                return
            end if
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
        k = doc_add(doc, parent, DOC_TABLE, status=status)
        if (.not. status%ok()) return
        doc%nodes(k)%num = i
    end function doc_add_table

    ! A key of the front matter, its value, and the value as inlines (a
    ! DOC_INLINES node, not in the document, or 0).
    subroutine doc_add_meta(doc, key, value, node, status)
        type(doc_t), intent(inout) :: doc
        character(len=*), intent(in) :: key, value
        integer, intent(in) :: node
        type(doc_meta_t), allocatable :: tmp(:)
        type(status_t), intent(out) :: status
        call check_parent(doc, node, status=status)
        if (.not. status%ok()) return
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
    function doc_plain(doc, k, status) result(s)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: k
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: s

        s = ""
        s = ""
        call doc_validate(doc, status)
        if (.not. status%ok()) return
        if (k < 1 .or. k > doc%n) then
            call status%set(ERROR_ARGUMENT, "doc_plain: invalid node")
            return
        end if
        s = plain_node(doc, k)
    end function doc_plain

    recursive function plain_node(doc, k) result(s)
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
                s = s//plain_node(doc, c)
            end select
            c = doc%nodes(c)%next
        end do
    end function plain_node

    subroutine check_parent(doc, parent, status)
        type(doc_t), intent(in) :: doc
        integer, intent(in) :: parent
        type(status_t), intent(out) :: status
        if (.not. allocated(doc%nodes) .or. .not. allocated(doc%meta) .or. .not. allocated(doc%tables)) then
            call status%set(ERROR_STATE, "document: call doc_init before adding nodes")
            return
        end if
        if (doc%n < 1 .or. doc%n > size(doc%nodes) .or. doc%nmeta < 0 .or. doc%nmeta > size(doc%meta) .or. &
            doc%ntables < 0 .or. doc%ntables > size(doc%tables)) then
            call status%set(ERROR_STATE, "document: inconsistent arena counts")
            return
        end if
        if (parent < 0 .or. parent > doc%n) then
            call status%set(ERROR_ARGUMENT, "document: invalid parent")
            return
        end if
        if (parent > 0) then
            if (doc%nodes(parent)%last < 0 .or. doc%nodes(parent)%last > doc%n) &
                call status%set(ERROR_ARGUMENT, "document: invalid last child")
        end if
    end subroutine check_parent

    subroutine doc_validate(doc, status)
        type(doc_t), intent(in) :: doc
        type(status_t), intent(out) :: status
        integer :: i, first, last, next, kind, head, count, node, link, j
        integer, allocatable :: incoming(:), order(:), chain_end(:)
        call check_parent(doc, 0, status)
        if (.not. status%ok()) return
        if (doc%nodes(1)%kind /= DOC_ROOT) then
            call status%set(ERROR_ARGUMENT, "document: missing root")
            return
        end if
        do i = 1, doc%n
            first = doc%nodes(i)%first
            last = doc%nodes(i)%last
            next = doc%nodes(i)%next
            if (min(first, last, next) < 0 .or. max(first, last, next) > doc%n .or. &
                ((first == 0) .neqv. (last == 0))) then
                call status%set(ERROR_ARGUMENT, "document: invalid node link")
                return
            end if
            kind = doc%nodes(i)%kind
            if (.not. ((kind >= DOC_ROOT .and. kind <= DOC_TABLE) .or. (kind >= IN_STR .and. kind <= IN_REF))) then
                call status%set(ERROR_UNSUPPORTED, "document: unsupported node kind")
                return
            end if
            if (i == 1) cycle
            if (.not. allocated(doc%nodes(i)%text) .or. .not. allocated(doc%nodes(i)%id) .or. &
                .not. allocated(doc%nodes(i)%attr) .or. .not. allocated(doc%nodes(i)%number)) then
                call status%set(ERROR_ARGUMENT, "document: initialize node strings with doc_add")
                return
            end if
        end do
        ! Validate the traversal graph without restricting node allocation or
        ! sibling order. Clients may reorder an existing tree.
        allocate (incoming(doc%n), order(doc%n), chain_end(doc%n))
        incoming = 0
        do i = 1, doc%n
            first = doc%nodes(i)%first
            next = doc%nodes(i)%next
            if (first > 0) incoming(first) = incoming(first) + 1
            if (next > 0) incoming(next) = incoming(next) + 1
        end do
        count = 0
        do i = 1, doc%n
            if (incoming(i) /= 0) cycle
            count = count + 1
            order(count) = i
        end do
        head = 1
        do while (head <= count)
            node = order(head)
            head = head + 1
            do j = 1, 2
                link = merge(doc%nodes(node)%first, doc%nodes(node)%next, j == 1)
                if (link == 0) cycle
                incoming(link) = incoming(link) - 1
                if (incoming(link) /= 0) cycle
                count = count + 1
                order(count) = link
            end do
        end do
        if (count /= doc%n) then
            call status%set(ERROR_ARGUMENT, "document: cyclic node links")
            return
        end if
        do i = doc%n, 1, -1
            node = order(i)
            next = doc%nodes(node)%next
            chain_end(node) = node
            if (next > 0) chain_end(node) = chain_end(next)
            first = doc%nodes(node)%first
            if (first == 0) cycle
            if (doc%nodes(node)%last /= chain_end(first)) then
                call status%set(ERROR_ARGUMENT, "document: last child does not end its sibling chain")
                return
            end if
        end do
        do i = 1, doc%nmeta
            if (doc%meta(i)%node < 0 .or. doc%meta(i)%node > doc%n .or. &
                .not. allocated(doc%meta(i)%key) .or. .not. allocated(doc%meta(i)%value)) then
                call status%set(ERROR_ARGUMENT, "document: invalid metadata")
                return
            end if
        end do
        do i = 1, doc%ntables
            if (.not. allocated(doc%tables(i)%cells)) then
                call status%set(ERROR_ARGUMENT, "document: missing table cells")
                return
            end if
        end do
    end subroutine doc_validate

end module fplotlib_doctree
