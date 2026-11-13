! Owned, positioned graphics. Layout engines and plotting code produce frames;
! exporters replay them without retaining any layout workspace.
module fplotlib_scene
    use fplotlib_style, only: dp
    use fplotlib_render
    use fplotlib_text, only: run_copy
    use fplotlib_glyphs, only: glyph_bbox
    implicit none
    private

    public :: frame_t, paged_document_t, recording_renderer_t, IDENTITY

    real(dp), parameter :: IDENTITY(6) = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp]
    integer, parameter :: PATH = 1, RECT = 2, CIRCLE = 3, MARKERS = 4, GLYPHS = 5, &
                          IMAGE = 6, GROUP = 7

    type :: item_t
        integer :: kind = 0, next = 0, child = 0, nv = 0
        real(dp) :: x = 0, y = 0, w = 0, h = 0, radius = 0, angle = 0
        real(dp) :: matrix(6) = IDENTITY
        type(paint_t) :: paint
        type(clip_t) :: clip
        type(glyphrun_t) :: run
        real(dp), allocatable :: px(:), py(:), mx(:), my(:)
        integer, allocatable :: verbs(:), rgba(:, :, :)
        character(len=:), allocatable :: name
    end type item_t

    type :: box_t
        integer :: first = 0, last = 0
        real(dp) :: w = 0, h = 0, baseline = 0
    end type box_t

    ! Handles returned by add_frame belong to this owner. Placing a handle
    ! again shares its graphics; importing a frame makes an independent copy.
    type :: frame_t
        private
        type(box_t), allocatable :: boxes(:)
        type(item_t), allocatable :: items(:)
        integer :: nb = 0, ni = 0
    contains
        procedure :: init => frame_init
        procedure :: metrics => frame_metrics
        procedure :: ink_bounds => frame_ink_bounds
        procedure :: set_baseline => frame_set_baseline
        procedure :: set_size => frame_set_size
        procedure :: add_frame => frame_import
        procedure :: place => frame_place
        procedure :: draw => frame_draw
        procedure :: logical_text => frame_text
    end type frame_t

    type :: paged_document_t
        private
        type(frame_t) :: scene
        integer, allocatable :: pages(:)
        integer :: n = 0
    contains
        procedure :: clear => document_clear
        procedure :: add_page => document_add_page
        procedure :: page_count => document_page_count
        procedure :: page_size => document_page_size
        procedure :: draw_page => document_draw_page
        procedure :: page_frame => document_page_frame
    end type paged_document_t

    type, extends(renderer_t) :: recording_renderer_t
        private
        type(frame_t) :: scene
        integer, allocatable :: stack(:)
        integer :: depth = 0, current = 1
    contains
        procedure :: open_canvas => record_open
        procedure :: close_canvas => record_close
        procedure :: bytes => record_bytes
        procedure :: draw_path => record_path
        procedure :: draw_rect => record_rect
        procedure :: draw_circle => record_circle
        procedure :: draw_markers => record_markers
        procedure :: draw_glyphs => record_glyphs
        procedure :: draw_image => record_image
        procedure :: begin_group => record_group
        procedure :: end_group => record_end_group
        procedure :: begin_frame => record_frame
        procedure :: end_frame => record_end_frame
        procedure :: take => record_take
    end type recording_renderer_t

contains

    subroutine frame_init(self, width, height, baseline)
        class(frame_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        real(dp), intent(in), optional :: baseline
        if (width < 0 .or. height < 0) error stop "frame: negative size"
        if (allocated(self%boxes)) deallocate (self%boxes)
        if (allocated(self%items)) deallocate (self%items)
        allocate (self%boxes(8), self%items(32))
        self%nb = 1
        self%ni = 0
        self%boxes(1)%w = width
        self%boxes(1)%h = height
        self%boxes(1)%baseline = height
        if (present(baseline)) self%boxes(1)%baseline = baseline
    end subroutine frame_init

    subroutine frame_metrics(self, width, height, baseline, handle)
        class(frame_t), intent(in) :: self
        real(dp), intent(out) :: width, height
        real(dp), intent(out), optional :: baseline
        integer, intent(in), optional :: handle
        integer :: k
        k = 1
        if (present(handle)) k = handle
        if (k < 1 .or. k > self%nb) error stop "frame: invalid handle"
        width = self%boxes(k)%w
        height = self%boxes(k)%h
        if (present(baseline)) baseline = self%boxes(k)%baseline
    end subroutine frame_metrics

    subroutine frame_set_baseline(self, baseline)
        class(frame_t), intent(inout) :: self
        real(dp), intent(in) :: baseline
        if (self%nb == 0) error stop "frame: uninitialized"
        self%boxes(1)%baseline = baseline
    end subroutine frame_set_baseline

    subroutine frame_set_size(self, width, height)
        class(frame_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        if (self%nb == 0) error stop "frame: uninitialized"
        if (width < 0 .or. height < 0) error stop "frame: negative size"
        self%boxes(1)%w = width
        self%boxes(1)%h = height
    end subroutine frame_set_size

    subroutine frame_ink_bounds(self, bounds, has_ink)
        class(frame_t), intent(in) :: self
        real(dp), intent(out) :: bounds(4)
        logical, intent(out), optional :: has_ink
        logical :: ink
        if (self%nb == 0) error stop "frame: uninitialized"
        call bounds_of(self, 1, bounds, ink)
        if (present(has_ink)) has_ink = ink
    end subroutine frame_ink_bounds

    subroutine reserve_boxes(self, n)
        class(frame_t), intent(inout) :: self
        integer, intent(in) :: n
        type(box_t), allocatable :: tmp(:)
        if (n <= size(self%boxes)) return
        allocate (tmp(max(n, 2*size(self%boxes))))
        tmp(1:self%nb) = self%boxes(1:self%nb)
        call move_alloc(tmp, self%boxes)
    end subroutine reserve_boxes

    subroutine reserve_items(self, n)
        class(frame_t), intent(inout) :: self
        integer, intent(in) :: n
        type(item_t), allocatable :: tmp(:)
        integer :: k
        if (n <= size(self%items)) return
        allocate (tmp(max(n, 2*size(self%items))))
        do k = 1, self%ni
            call move_item(self%items(k), tmp(k))
        end do
        call move_alloc(tmp, self%items)
    end subroutine reserve_items

    integer function new_item(self, parent, kind) result(k)
        class(frame_t), intent(inout) :: self
        integer, intent(in) :: parent, kind
        call reserve_items(self, self%ni + 1)
        self%ni = self%ni + 1
        k = self%ni
        self%items(k)%kind = kind
        if (self%boxes(parent)%last > 0) then
            self%items(self%boxes(parent)%last)%next = k
        else
            self%boxes(parent)%first = k
        end if
        self%boxes(parent)%last = k
    end function new_item

    subroutine copy_scalars(a, b)
        type(item_t), intent(in) :: a
        type(item_t), intent(inout) :: b
        b%kind = a%kind
        b%next = a%next
        b%child = a%child
        b%nv = a%nv
        b%x = a%x
        b%y = a%y
        b%w = a%w
        b%h = a%h
        b%radius = a%radius
        b%angle = a%angle
        b%matrix = a%matrix
        b%paint = a%paint
        b%clip = a%clip
        if (allocated(a%name)) b%name = a%name
    end subroutine copy_scalars

    subroutine copy_item(a, b)
        type(item_t), intent(in) :: a
        type(item_t), intent(out) :: b
        call copy_scalars(a, b)
        if (allocated(a%px)) then
            allocate (b%px(size(a%px)), b%py(size(a%py)))
            b%px = a%px
            b%py = a%py
        end if
        if (allocated(a%mx)) then
            allocate (b%mx(size(a%mx)), b%my(size(a%my)))
            b%mx = a%mx
            b%my = a%my
        end if
        if (allocated(a%verbs)) then
            allocate (b%verbs(size(a%verbs)))
            b%verbs = a%verbs
        end if
        if (allocated(a%rgba)) then
            allocate (b%rgba(size(a%rgba, 1), size(a%rgba, 2), size(a%rgba, 3)))
            b%rgba = a%rgba
        end if
        if (a%kind == GLYPHS) call run_copy(a%run, b%run)
    end subroutine copy_item

    subroutine move_item(a, b)
        type(item_t), intent(inout) :: a
        type(item_t), intent(out) :: b
        call copy_scalars(a, b)
        call move_alloc(a%px, b%px)
        call move_alloc(a%py, b%py)
        call move_alloc(a%mx, b%mx)
        call move_alloc(a%my, b%my)
        call move_alloc(a%verbs, b%verbs)
        call move_alloc(a%rgba, b%rgba)
        b%run%n = a%run%n
        b%run%source_math = a%run%source_math
        call move_alloc(a%run%gid, b%run%gid)
        call move_alloc(a%run%font, b%run%font)
        call move_alloc(a%run%first, b%run%first)
        call move_alloc(a%run%last, b%run%last)
        call move_alloc(a%run%x, b%run%x)
        call move_alloc(a%run%y, b%run%y)
        call move_alloc(a%run%size, b%run%size)
        call move_alloc(a%run%text, b%run%text)
    end subroutine move_item

    subroutine frame_import(self, child, handle)
        class(frame_t), intent(inout) :: self
        type(frame_t), intent(in) :: child
        integer, intent(out) :: handle
        integer :: b0, i0, k
        if (self%nb == 0 .or. child%nb == 0) error stop "frame: uninitialized import"
        b0 = self%nb
        i0 = self%ni
        call reserve_boxes(self, b0 + child%nb)
        call reserve_items(self, i0 + child%ni)
        do k = 1, child%nb
            self%boxes(b0 + k) = child%boxes(k)
            if (child%boxes(k)%first > 0) self%boxes(b0 + k)%first = child%boxes(k)%first + i0
            if (child%boxes(k)%last > 0) self%boxes(b0 + k)%last = child%boxes(k)%last + i0
        end do
        do k = 1, child%ni
            call copy_item(child%items(k), self%items(i0 + k))
            if (child%items(k)%next > 0) self%items(i0 + k)%next = child%items(k)%next + i0
            if (child%items(k)%child > 0) self%items(i0 + k)%child = child%items(k)%child + b0
        end do
        self%nb = b0 + child%nb
        self%ni = i0 + child%ni
        handle = b0 + 1
    end subroutine frame_import

    subroutine frame_place(self, handle, matrix, clip)
        class(frame_t), intent(inout) :: self
        integer, intent(in) :: handle
        real(dp), intent(in), optional :: matrix(6)
        type(clip_t), intent(in), optional :: clip
        integer :: k
        if (handle <= 1 .or. handle > self%nb) error stop "frame: invalid child handle"
        k = new_item(self, 1, GROUP)
        self%items(k)%child = handle
        if (present(matrix)) self%items(k)%matrix = matrix
        if (present(clip)) self%items(k)%clip = clip
    end subroutine frame_place

    subroutine frame_draw(self, renderer, handle)
        class(frame_t), intent(in) :: self
        class(renderer_t), intent(inout) :: renderer
        integer, intent(in), optional :: handle
        integer :: k
        k = 1
        if (present(handle)) k = handle
        if (k < 1 .or. k > self%nb) error stop "frame: invalid handle"
        call replay(self, k, renderer)
    end subroutine frame_draw

    recursive subroutine replay(self, box, renderer)
        class(frame_t), intent(in) :: self
        integer, intent(in) :: box
        class(renderer_t), intent(inout) :: renderer
        integer :: k
        logical :: scoped, named
        k = self%boxes(box)%first
        do while (k > 0)
            associate (p => self%items(k))
                select case (p%kind)
                case (PATH)
                    call renderer%draw_path(p%px, p%py, p%verbs, p%nv, p%paint)
                case (RECT)
                    call renderer%draw_rect(p%x, p%y, p%w, p%h, p%paint, p%radius)
                case (CIRCLE)
                    call renderer%draw_circle(p%x, p%y, p%radius, p%paint)
                case (MARKERS)
                    call renderer%draw_markers(p%px, p%py, p%mx, p%my, p%verbs, p%nv, p%paint)
                case (GLYPHS)
                    call renderer%draw_glyphs(p%x, p%y, p%run, p%paint, p%angle)
                case (IMAGE)
                    call renderer%draw_image(p%x, p%y, p%w, p%h, p%rgba, &
                                             size(p%rgba, 2), size(p%rgba, 3), p%paint)
                case (GROUP)
                    named = .false.
                    if (allocated(p%name)) named = len(p%name) > 0
                    scoped = p%clip%on .or. any(p%matrix /= IDENTITY)
                    if (named) call renderer%begin_group(p%name)
                    if (scoped) call renderer%begin_frame(p%matrix, p%clip)
                    call replay(self, p%child, renderer)
                    if (scoped) call renderer%end_frame()
                    if (named) call renderer%end_group()
                end select
            end associate
            k = self%items(k)%next
        end do
    end subroutine replay

    recursive function text_of(self, box) result(text)
        class(frame_t), intent(in) :: self
        integer, intent(in) :: box
        character(len=:), allocatable :: text
        integer :: k
        text = ""
        k = self%boxes(box)%first
        do while (k > 0)
            if (self%items(k)%kind == GLYPHS) then
                if (allocated(self%items(k)%run%text)) text = text//self%items(k)%run%text
            else if (self%items(k)%kind == GROUP) then
                text = text//text_of(self, self%items(k)%child)
            end if
            k = self%items(k)%next
        end do
    end function text_of

    function frame_text(self) result(text)
        class(frame_t), intent(in) :: self
        character(len=:), allocatable :: text
        if (self%nb == 0) error stop "frame: uninitialized text"
        text = text_of(self, 1)
    end function frame_text

    subroutine union_bounds(bounds, ink, b)
        real(dp), intent(inout) :: bounds(4)
        logical, intent(inout) :: ink
        real(dp), intent(in) :: b(4)
        if (ink) then
            bounds(1:2) = min(bounds(1:2), b(1:2))
            bounds(3:4) = max(bounds(3:4), b(3:4))
        else
            bounds = b
            ink = .true.
        end if
    end subroutine union_bounds

    subroutine transform_bounds(b, matrix)
        real(dp), intent(inout) :: b(4)
        real(dp), intent(in) :: matrix(6)
        real(dp) :: x(4), y(4), tx(4), ty(4)
        x = [b(1), b(3), b(3), b(1)]
        y = [b(2), b(2), b(4), b(4)]
        tx = matrix(1)*x + matrix(3)*y + matrix(5)
        ty = matrix(2)*x + matrix(4)*y + matrix(6)
        b = [minval(tx), minval(ty), maxval(tx), maxval(ty)]
    end subroutine transform_bounds

    recursive subroutine bounds_of(self, box, bounds, ink)
        class(frame_t), intent(in) :: self
        integer, intent(in) :: box
        real(dp), intent(out) :: bounds(4)
        logical, intent(out) :: ink
        real(dp) :: b(4), g(4), m(6), ca, sa, pad
        integer :: k, j
        logical :: child_ink
        type(clip_t) :: clip
        ink = .false.
        bounds = 0
        k = self%boxes(box)%first
        do while (k > 0)
            associate (p => self%items(k))
                child_ink = .true.
                clip = p%paint%clip
                select case (p%kind)
                case (GROUP)
                    call bounds_of(self, p%child, b, child_ink)
                    clip = p%clip
                case (PATH, MARKERS)
                    child_ink = size(p%px) > 0
                    if (child_ink) b = [minval(p%px), minval(p%py), maxval(p%px), maxval(p%py)]
                    if (child_ink .and. p%kind == MARKERS) &
                        b = b + [minval(p%mx), minval(p%my), maxval(p%mx), maxval(p%my)]
                case (RECT, IMAGE)
                    b = [p%x, p%y, p%x + p%w, p%y + p%h]
                case (CIRCLE)
                    b = [p%x - p%radius, p%y - p%radius, p%x + p%radius, p%y + p%radius]
                case (GLYPHS)
                    child_ink = .false.
                    b = 0
                    ca = cos(p%angle*acos(-1.0_dp)/180.0_dp)
                    sa = sin(p%angle*acos(-1.0_dp)/180.0_dp)
                    do j = 1, p%run%n
                        call glyph_bbox(p%run%gid(j), g(1), g(2), g(3), g(4))
                        g = [g(1), -g(4), g(3), -g(2)]*p%run%size(j)
                        g = g + [p%run%x(j), p%run%y(j), p%run%x(j), p%run%y(j)]
                        m = [ca, sa, -sa, ca, p%x, p%y]
                        call transform_bounds(g, m)
                        call union_bounds(b, child_ink, g)
                    end do
                end select
                if (child_ink) then
                    if (p%paint%stroked .and. p%kind /= GROUP .and. p%kind /= GLYPHS) then
                        pad = 0.5_dp*p%paint%line_width*max(1.0_dp, p%paint%miter_limit)
                        b = b + [-pad, -pad, pad, pad]
                    end if
                    if (clip%on) then
                        b(1:2) = max(b(1:2), [clip%x, clip%y])
                        b(3:4) = min(b(3:4), [clip%x + clip%w, clip%y + clip%h])
                        child_ink = all(b(3:4) >= b(1:2))
                    end if
                    if (p%kind == GROUP) call transform_bounds(b, p%matrix)
                    if (child_ink) call union_bounds(bounds, ink, b)
                end if
            end associate
            k = self%items(k)%next
        end do
    end subroutine bounds_of

    subroutine record_open(self, width, height, bg_rgb, bg_alpha, x0, y0)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha, x0, y0
        type(paint_t) :: paint
        real(dp) :: matrix(6), ox, oy
        type(clip_t) :: clip
        call self%scene%init(width, height)
        self%width = width
        self%height = height
        self%is_open = .true.
        self%current = 1
        self%depth = 0
        ox = 0
        oy = 0
        if (present(x0)) ox = x0
        if (present(y0)) oy = y0
        if (present(bg_rgb)) then
            paint%filled = .true.
            paint%fill_rgb = bg_rgb
            if (present(bg_alpha)) paint%fill_alpha = bg_alpha
            call self%draw_rect(0.0_dp, 0.0_dp, width, height, paint)
        end if
        ! The crop is a frame, not a rewrite of every recorded coordinate.
        matrix = IDENTITY
        matrix(5:6) = [-ox, -oy]
        call self%begin_frame(matrix, clip)
    end subroutine record_open

    subroutine record_close(self)
        class(recording_renderer_t), intent(inout) :: self
        if (.not. self%is_open .or. self%depth /= 1) error stop "recorder: unbalanced scopes"
        call self%end_frame()
        self%is_open = .false.
    end subroutine record_close

    function record_bytes(self) result(bytes)
        class(recording_renderer_t), intent(in) :: self
        character(len=:), allocatable :: bytes
        error stop "recorder: use take() to obtain a frame, not bytes()"
    end function record_bytes

    subroutine record_take(self, frame)
        class(recording_renderer_t), intent(inout) :: self
        type(frame_t), intent(out) :: frame
        if (self%is_open .or. self%scene%nb == 0) error stop "recorder: frame is not finished"
        frame%nb = self%scene%nb
        frame%ni = self%scene%ni
        call move_alloc(self%scene%boxes, frame%boxes)
        call move_alloc(self%scene%items, frame%items)
        self%scene%nb = 0
        self%scene%ni = 0
    end subroutine record_take

    integer function record_item(self, kind, paint) result(k)
        class(recording_renderer_t), intent(inout) :: self
        integer, intent(in) :: kind
        type(paint_t), intent(in) :: paint
        if (.not. self%is_open) error stop "recorder: canvas is closed"
        k = new_item(self%scene, self%current, kind)
        self%scene%items(k)%paint = paint
    end function record_item

    subroutine record_path(self, x, y, verbs, n_verb, paint)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        integer :: k
        k = record_item(self, PATH, paint)
        associate (p => self%scene%items(k))
            allocate (p%px(size(x)), p%py(size(y)), p%verbs(n_verb))
            p%px = x
            p%py = y
            p%verbs = verbs(1:n_verb)
            p%nv = n_verb
        end associate
    end subroutine record_path

    subroutine record_rect(self, x, y, w, h, paint, radius)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        integer :: k
        k = record_item(self, RECT, paint)
        self%scene%items(k)%x = x
        self%scene%items(k)%y = y
        self%scene%items(k)%w = w
        self%scene%items(k)%h = h
        if (present(radius)) self%scene%items(k)%radius = radius
    end subroutine record_rect

    subroutine record_circle(self, cx, cy, r, paint)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
        integer :: k
        k = record_item(self, CIRCLE, paint)
        self%scene%items(k)%x = cx
        self%scene%items(k)%y = cy
        self%scene%items(k)%radius = r
    end subroutine record_circle

    subroutine record_markers(self, x, y, mx, my, mverbs, n_mverb, paint)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:), mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
        integer :: k
        k = record_item(self, MARKERS, paint)
        associate (p => self%scene%items(k))
            allocate (p%px(size(x)), p%py(size(y)), p%mx(size(mx)), p%my(size(my)), p%verbs(n_mverb))
            p%px = x
            p%py = y
            p%mx = mx
            p%my = my
            p%verbs = mverbs(1:n_mverb)
            p%nv = n_mverb
        end associate
    end subroutine record_markers

    subroutine record_glyphs(self, x, y, run, paint, angle)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, angle
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        integer :: k
        k = record_item(self, GLYPHS, paint)
        self%scene%items(k)%x = x
        self%scene%items(k)%y = y
        self%scene%items(k)%angle = angle
        call run_copy(run, self%scene%items(k)%run)
    end subroutine record_glyphs

    subroutine record_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny, rgba(4, nx, ny)
        type(paint_t), intent(in) :: paint
        integer :: k
        if (nx < 1 .or. ny < 1) error stop "recorder: empty image"
        k = record_item(self, IMAGE, paint)
        self%scene%items(k)%x = x
        self%scene%items(k)%y = y
        self%scene%items(k)%w = w
        self%scene%items(k)%h = h
        allocate (self%scene%items(k)%rgba(4, nx, ny))
        self%scene%items(k)%rgba = rgba
    end subroutine record_image

    subroutine record_frame(self, matrix, clip)
        class(recording_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        integer :: k, child
        integer, allocatable :: tmp(:)
        if (.not. self%is_open) error stop "recorder: canvas is closed"
        if (.not. allocated(self%stack)) allocate (self%stack(16))
        if (self%depth == size(self%stack)) then
            allocate (tmp(2*size(self%stack)))
            tmp(1:self%depth) = self%stack(1:self%depth)
            call move_alloc(tmp, self%stack)
        end if
        self%depth = self%depth + 1
        self%stack(self%depth) = self%current
        call reserve_boxes(self%scene, self%scene%nb + 1)
        self%scene%nb = self%scene%nb + 1
        child = self%scene%nb
        k = new_item(self%scene, self%current, GROUP)
        self%scene%items(k)%child = child
        self%scene%items(k)%matrix = matrix
        self%scene%items(k)%clip = clip
        self%current = child
    end subroutine record_frame

    subroutine record_end_frame(self)
        class(recording_renderer_t), intent(inout) :: self
        if (self%depth < 1) error stop "recorder: unbalanced frame"
        self%current = self%stack(self%depth)
        self%depth = self%depth - 1
    end subroutine record_end_frame

    subroutine record_group(self, name)
        class(recording_renderer_t), intent(inout) :: self
        character(len=*), intent(in) :: name
        type(clip_t) :: clip
        call self%begin_frame(IDENTITY, clip)
        self%scene%items(self%scene%ni)%name = name
    end subroutine record_group

    subroutine record_end_group(self)
        class(recording_renderer_t), intent(inout) :: self
        call self%end_frame()
    end subroutine record_end_group

    subroutine document_clear(self)
        class(paged_document_t), intent(inout) :: self
        call self%scene%init(0.0_dp, 0.0_dp)
        self%n = 0
        if (allocated(self%pages)) deallocate (self%pages)
        allocate (self%pages(4))
    end subroutine document_clear

    subroutine document_add_page(self, page)
        class(paged_document_t), intent(inout) :: self
        type(frame_t), intent(in) :: page
        integer, allocatable :: tmp(:)
        integer :: handle
        if (.not. allocated(self%pages)) call self%clear()
        if (self%n == size(self%pages)) then
            allocate (tmp(2*size(self%pages)))
            tmp(1:self%n) = self%pages(1:self%n)
            call move_alloc(tmp, self%pages)
        end if
        call self%scene%add_frame(page, handle)
        self%n = self%n + 1
        self%pages(self%n) = handle
    end subroutine document_add_page

    integer function document_page_count(self) result(n)
        class(paged_document_t), intent(in) :: self
        n = self%n
    end function document_page_count

    subroutine document_page_size(self, page, width, height)
        class(paged_document_t), intent(in) :: self
        integer, intent(in) :: page
        real(dp), intent(out) :: width, height
        if (page < 1 .or. page > self%n) error stop "document: invalid page"
        width = self%scene%boxes(self%pages(page))%w
        height = self%scene%boxes(self%pages(page))%h
    end subroutine document_page_size

    subroutine document_draw_page(self, page, renderer)
        class(paged_document_t), intent(in) :: self
        integer, intent(in) :: page
        class(renderer_t), intent(inout) :: renderer
        if (page < 1 .or. page > self%n) error stop "document: invalid page"
        call replay(self%scene, self%pages(page), renderer)
    end subroutine document_draw_page

    ! Extract a page without retaining the document. Re-recording also removes
    ! unreachable resources belonging only to other pages.
    subroutine document_page_frame(self, page, frame)
        class(paged_document_t), intent(in) :: self
        integer, intent(in) :: page
        type(frame_t), intent(out) :: frame
        type(recording_renderer_t) :: rec
        real(dp) :: w, h
        call self%page_size(page, w, h)
        call rec%open_canvas(w, h)
        call self%draw_page(page, rec)
        call rec%close_canvas()
        call rec%take(frame)
    end subroutine document_page_frame

end module fplotlib_scene
