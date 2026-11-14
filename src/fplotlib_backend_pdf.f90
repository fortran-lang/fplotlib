! PDF backend.
!
! PDF is the cheapest of the four to reach: it is a vector format, so there
! is no rasterizer, and its page operators line up almost one for one with
! the API's primitives. The three things it does not share with the API are
! handled here and nowhere else:
!
!   * y grows upwards. The whole page is drawn under one flipping matrix,
!     set once in the content stream, so every coordinate arrives unchanged.
!     Text would come out mirrored under that flip, so each string carries a
!     text matrix that undoes it.
!
!   * there is no circle operator, so circles become four cubics.
!
!   * constant alpha is not a graphics operator but a named graphics state
!     resource, so the distinct alpha values used by a figure are collected
!     and written into the page's /ExtGState.
!
! Text arrives as glyphs already laid out, and is drawn with Type 3 fonts
! built from the compiled-in outlines (see fplotlib_type3): the page shows
! exactly what PNG and SVG show, and a ToUnicode map keeps the text
! selectable and searchable. Only the glyphs the page uses are embedded.
module fplotlib_backend_pdf
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_render
    use fplotlib_svg, only: svg_builder, builder_init, builder_append, &
                         builder_get, fmt_num
    use fplotlib_png, only: zlib_compress
    use fplotlib_glyphs, only: glyph_adv, glyph_inked
    use fplotlib_type3, only: t3set_t, t3_reset, t3_code, t3_font_name, &
                              t3_glyph_ops, t3_width, t3_box, t3_unicode
    implicit none
    private

    public :: pdf_renderer_t

    ! An image already compressed and ready to become an XObject. The samples
    ! are kept as the deflated stream rather than as pixels because that is
    ! the only form the file wants them in.
    type :: pdf_image_t
        integer :: w = 0, h = 0
        character(len=:), allocatable :: rgb
        ! Empty unless some sample is transparent, since a fully opaque
        ! image needs no soft mask.
        character(len=:), allocatable :: alpha
    end type pdf_image_t

    ! A finished page's content stream.
    type :: pdf_page_t
        character(len=:), allocatable :: content
        real(dp) :: w = 0.0_dp, h = 0.0_dp
    end type pdf_page_t

    type, extends(encoded_renderer_t) :: pdf_renderer_t
        ! The page content stream. The file itself is assembled in
        ! close_canvas, once the length of this is known.
        type(svg_builder) :: c
        ! The pages before the current one, for a document of several;
        ! they share the fonts, images and alpha states.
        integer :: npages = 0
        type(pdf_page_t), allocatable :: pages(:)
        logical :: has_bg = .false.
        integer :: bg(3) = 255
        real(dp) :: bga = 1.0_dp
        character(len=:), allocatable :: out
        real(dp) :: w = 0.0_dp, h = 0.0_dp
        real(dp) :: x0 = 0.0_dp, y0 = 0.0_dp
        ! Distinct alpha pairs, each of which becomes an /ExtGState.
        integer :: n_alpha = 0
        real(dp), allocatable :: alpha_fill(:), alpha_stroke(:)
        integer :: n_img = 0
        type(pdf_image_t), allocatable :: img(:)
        integer :: n_frame = 0
        ! The glyphs the page has drawn, and the fonts they went into.
        type(t3set_t) :: t3
    contains
        procedure :: open_canvas => pdf_open_canvas
        procedure :: close_canvas => pdf_close_canvas
        procedure :: bytes => pdf_bytes
        procedure :: draw_path => pdf_draw_path
        procedure :: draw_rect => pdf_draw_rect
        procedure :: draw_circle => pdf_draw_circle
        procedure :: draw_markers => pdf_draw_markers
        procedure :: draw_glyphs => pdf_draw_glyphs
        procedure :: draw_image => pdf_draw_image
        procedure :: begin_frame => pdf_begin_frame
        procedure :: end_frame => pdf_end_frame
        procedure :: new_page => pdf_new_page
    end type pdf_renderer_t


contains

    subroutine put(self, s)
        class(pdf_renderer_t), intent(inout) :: self
        character(len=*), intent(in) :: s
        call builder_append(self%c, s)
    end subroutine put

    subroutine put_num(self, x)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x
        character(len=64) :: s
        integer :: n
        call fmt_num(x, s, n)
        call builder_append(self%c, s(1:n))
        call builder_append(self%c, " ")
    end subroutine put_num

    function num_str(x) result(t)
        real(dp), intent(in) :: x
        character(len=:), allocatable :: t
        character(len=64) :: s
        integer :: n
        call fmt_num(x, s, n)
        t = s(1:n)
    end function num_str

    pure function int_str(i) result(t)
        integer, intent(in) :: i
        character(len=:), allocatable :: t
        character(len=16) :: s
        write (s, "(I0)") i
        t = trim(s)
    end function int_str


    ! PDF colors are components in 0..1.
    subroutine put_rgb(self, rgb, stroking)
        class(pdf_renderer_t), intent(inout) :: self
        integer, intent(in) :: rgb(3)
        logical, intent(in) :: stroking
        integer :: i
        do i = 1, 3
            call put_num(self, real(rgb(i), dp)/255.0_dp)
        end do
        if (stroking) then
            call put(self, "RG"//new_line("a"))
        else
            call put(self, "rg"//new_line("a"))
        end if
    end subroutine put_rgb

    ! Alpha is a resource, not an operator, so each distinct pair is
    ! registered once and referenced by name.
    function alpha_state(self, fa, sa) result(id)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: fa, sa
        integer :: id, i
        real(dp), allocatable :: f(:), s(:)

        do i = 1, self%n_alpha
            if (self%alpha_fill(i) == fa .and. self%alpha_stroke(i) == sa) then
                id = i
                return
            end if
        end do
        if (.not. allocated(self%alpha_fill)) then
            allocate (self%alpha_fill(16), self%alpha_stroke(16))
        end if
        if (self%n_alpha == size(self%alpha_fill)) then
            allocate (f(2*self%n_alpha), s(2*self%n_alpha))
            f(1:self%n_alpha) = self%alpha_fill(1:self%n_alpha)
            s(1:self%n_alpha) = self%alpha_stroke(1:self%n_alpha)
            call move_alloc(f, self%alpha_fill)
            call move_alloc(s, self%alpha_stroke)
        end if
        self%n_alpha = self%n_alpha + 1
        self%alpha_fill(self%n_alpha) = fa
        self%alpha_stroke(self%n_alpha) = sa
        id = self%n_alpha
    end function alpha_state

    ! Everything that has to be in force before a painting operator: colors,
    ! line style, transparency and the clip. Emitted inside q/Q so it cannot
    ! leak into the next primitive.
    subroutine begin_paint(self, p)
        class(pdf_renderer_t), intent(inout) :: self
        type(paint_t), intent(in) :: p
        integer :: g, i

        call put(self, "q"//new_line("a"))
        if (p%clip%on) then
            call put_num(self, p%clip%x)
            call put_num(self, p%clip%y)
            call put_num(self, p%clip%w)
            call put_num(self, p%clip%h)
            call put(self, "re W n"//new_line("a"))
        end if
        if (p%fill_alpha < 1.0_dp .or. p%stroke_alpha < 1.0_dp) then
            g = alpha_state(self, p%fill_alpha, p%stroke_alpha)
            call put(self, "/GS"//int_str(g)//" gs"//new_line("a"))
        end if
        if (p%filled) call put_rgb(self, p%fill_rgb, .false.)
        if (p%stroked) then
            call put_rgb(self, p%stroke_rgb, .true.)
            call put_num(self, p%line_width)
            call put(self, "w"//new_line("a"))
            call put(self, int_str(p%cap)//" J"//new_line("a"))
            select case (p%join)
            case (JOIN_ROUND); call put(self, "1 j"//new_line("a"))
            case (JOIN_BEVEL); call put(self, "2 j"//new_line("a"))
            case default; call put(self, "0 j"//new_line("a"))
            end select
            if (p%n_dash > 0) then
                call put(self, "[")
                do i = 1, p%n_dash
                    call put_num(self, p%dash(i))
                end do
                call put(self, "] "//num_str(p%dash_offset)//" d"//new_line("a"))
            else
                call put(self, "[] 0 d"//new_line("a"))
            end if
        end if
    end subroutine begin_paint

    ! The operator that actually marks the page, chosen by what the paint
    ! asks for, followed by the restore that closes begin_paint.
    subroutine end_paint(self, p)
        class(pdf_renderer_t), intent(inout) :: self
        type(paint_t), intent(in) :: p
        if (p%filled .and. p%stroked) then
            if (p%fill_rule == FILL_EVENODD) then
                call put(self, "B*"//new_line("a"))
            else
                call put(self, "B"//new_line("a"))
            end if
        else if (p%filled) then
            if (p%fill_rule == FILL_EVENODD) then
                call put(self, "f*"//new_line("a"))
            else
                call put(self, "f"//new_line("a"))
            end if
        else if (p%stroked) then
            call put(self, "S"//new_line("a"))
        else
            call put(self, "n"//new_line("a"))
        end if
        call put(self, "Q"//new_line("a"))
    end subroutine end_paint

    subroutine pdf_open_canvas(self, width, height, bg_rgb, bg_alpha, x0, y0)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha
        real(dp), intent(in), optional :: x0, y0

        if (self%n_frame /= 0) error stop "pdf: unclosed frame at open_canvas"
        self%width = width
        self%height = height
        self%is_open = .true.
        self%w = width
        self%h = height
        self%x0 = 0.0_dp
        self%y0 = 0.0_dp
        if (present(x0)) self%x0 = x0
        if (present(y0)) self%y0 = y0
        self%n_alpha = 0
        self%n_img = 0
        self%npages = 0
        if (allocated(self%pages)) deallocate (self%pages)
        if (allocated(self%img)) deallocate (self%img)
        if (allocated(self%out)) deallocate (self%out)
        call t3_reset(self%t3)
        self%has_bg = present(bg_rgb)
        if (present(bg_rgb)) self%bg = bg_rgb
        self%bga = 1.0_dp
        if (present(bg_alpha)) self%bga = bg_alpha
        call start_page(self)
    end subroutine pdf_open_canvas

    ! A page's content starts with the matrix that turns the API's
    ! top-left origin with y downwards into PDF's bottom-left origin with
    ! y upwards, and applies the canvas origin at the same time; then the
    ! background, if there is one.
    subroutine start_page(self)
        class(pdf_renderer_t), intent(inout) :: self
        type(paint_t) :: p
        call builder_init(self%c)
        call put(self, "1 0 0 -1 "//num_str(-self%x0)//" " &
                 //num_str(self%y0 + self%h)//" cm"//new_line("a"))
        if (self%has_bg) then
            p%filled = .true.
            p%fill_rgb = self%bg
            p%fill_alpha = self%bga
            call pdf_draw_rect(self, self%x0, self%y0, self%w, self%h, p)
        end if
    end subroutine start_page

    ! Omitted page settings inherit the preceding page, including its
    ! background. Alpha zero requests a transparent background.
    subroutine pdf_new_page(self, width, height, bg_rgb, bg_alpha)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in), optional :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha
        type(pdf_page_t), allocatable :: t(:)

        if (.not. self%is_open) error stop "pdf: new_page outside canvas"
        if (self%n_frame /= 0) error stop "pdf: unclosed frame at new_page"
        if (.not. allocated(self%pages)) allocate (self%pages(4))
        if (self%npages >= size(self%pages)) then
            allocate (t(2*size(self%pages)))
            t(1:self%npages) = self%pages(1:self%npages)
            call move_alloc(t, self%pages)
        end if
        self%npages = self%npages + 1
        self%pages(self%npages)%content = builder_get(self%c)
        self%pages(self%npages)%w = self%w
        self%pages(self%npages)%h = self%h
        if (present(width)) self%w = width
        if (present(height)) self%h = height
        self%width = self%w
        self%height = self%h
        if (present(bg_rgb)) then
            self%has_bg = .true.
            self%bg = bg_rgb
        end if
        if (present(bg_alpha)) self%bga = bg_alpha
        call start_page(self)
    end subroutine pdf_new_page

    subroutine pdf_begin_frame(self, matrix, clip)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        integer :: i

        if (.not. self%is_open) error stop "pdf: begin_frame outside canvas"
        call put(self, "q"//new_line("a"))
        do i = 1, 6
            call put_num(self, matrix(i))
        end do
        call put(self, "cm"//new_line("a"))
        if (clip%on) then
            call put_num(self, clip%x)
            call put_num(self, clip%y)
            call put_num(self, clip%w)
            call put_num(self, clip%h)
            call put(self, "re W n"//new_line("a"))
        end if
        self%n_frame = self%n_frame + 1
    end subroutine pdf_begin_frame

    subroutine pdf_end_frame(self)
        class(pdf_renderer_t), intent(inout) :: self

        if (self%n_frame == 0) error stop "pdf: unmatched end_frame"
        call put(self, "Q"//new_line("a"))
        self%n_frame = self%n_frame - 1
    end subroutine pdf_end_frame

    subroutine emit_path(self, x, y, verbs, n_verb)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        integer :: i, k, j

        k = 0
        do i = 1, n_verb
            select case (verbs(i))
            case (VERB_MOVE)
                k = k + 1
                call put_num(self, x(k))
                call put_num(self, y(k))
                call put(self, "m"//new_line("a"))
            case (VERB_LINE)
                k = k + 1
                call put_num(self, x(k))
                call put_num(self, y(k))
                call put(self, "l"//new_line("a"))
            case (VERB_CUBIC)
                do j = 1, 3
                    k = k + 1
                    call put_num(self, x(k))
                    call put_num(self, y(k))
                end do
                call put(self, "c"//new_line("a"))
            case (VERB_CLOSE)
                call put(self, "h"//new_line("a"))
            end select
        end do
    end subroutine emit_path

    subroutine pdf_draw_path(self, x, y, verbs, n_verb, paint)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        if (n_verb <= 0) return
        call begin_paint(self, paint)
        call emit_path(self, x, y, verbs, n_verb)
        call end_paint(self, paint)
    end subroutine pdf_draw_path

    subroutine pdf_draw_rect(self, x, y, w, h, paint, radius)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius

        call begin_paint(self, paint)
        ! Rounded corners are rare enough that they go through the general
        ! path; the plain case gets the single "re" operator.
        call put_num(self, x)
        call put_num(self, y)
        call put_num(self, w)
        call put_num(self, h)
        call put(self, "re"//new_line("a"))
        call end_paint(self, paint)
    end subroutine pdf_draw_rect

    subroutine pdf_draw_circle(self, cx, cy, r, paint)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
        real(dp) :: x(13), y(13), k
        integer :: v(6)

        k = r*0.5522847498307933_dp
        x = [cx + r, cx + r, cx + k, cx, cx - k, cx - r, cx - r, cx - r, &
             cx - k, cx, cx + k, cx + r, cx + r]
        y = [cy, cy + k, cy + r, cy + r, cy + r, cy + k, cy, cy - k, &
             cy - r, cy - r, cy - r, cy - k, cy]
        v = [VERB_MOVE, VERB_CUBIC, VERB_CUBIC, VERB_CUBIC, VERB_CUBIC, VERB_CLOSE]
        call pdf_draw_path(self, x, y, v, 6, paint)
    end subroutine pdf_draw_circle

    ! Repeating the outline per point rather than defining a form XObject.
    ! A form would make the file smaller, but every point still needs its own
    ! placement operator, so the drawing cost is the same either way.
    subroutine pdf_draw_markers(self, x, y, mx, my, mverbs, n_mverb, paint)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        real(dp), intent(in) :: mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
        integer :: i
        do i = 1, size(x)
            call pdf_draw_path(self, mx + x(i), my + y(i), mverbs, n_mverb, paint)
        end do
    end subroutine pdf_draw_markers

    ! The run is shown in segments, each a stretch of glyphs in one font
    ! at one size on one baseline, placed by its own text matrix. Within a
    ! segment the glyphs follow each other by their widths, and kerning is
    ! the number TJ takes between two of them.
    subroutine pdf_draw_glyphs(self, x, y, run, paint, angle)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
        type(paint_t) :: pp
        real(dp) :: ca, sa, rad, cur_size, cur_y, expect, adj
        integer :: i, font, code, cur_font
        logical :: open, actual_text
        character(len=1) :: eol

        if (run%n == 0) return
        eol = new_line("a")
        pp = paint
        pp%stroked = .false.
        pp%filled = .true.
        call begin_paint(self, pp)
        actual_text = .false.
        if (allocated(run%text)) actual_text = len(run%text) > 0 .and. .not. run%source_math
        if (actual_text) call put_actual_text(self, run%text)
        call put(self, "BT"//eol)
        ! The page flip would leave text mirrored, so the text matrix flips
        ! back; the rotation is folded into the same matrix.
        rad = angle*acos(-1.0_dp)/180.0_dp
        ca = cos(rad)
        sa = sin(rad)
        cur_font = 0
        cur_size = -1.0_dp
        cur_y = 0.0_dp
        expect = 0.0_dp
        open = .false.
        do i = 1, run%n
            call t3_code(self%t3, run%gid(i), font, code)
            if (open) then
                if (font /= cur_font .or. run%size(i) /= cur_size &
                    .or. abs(run%y(i) - cur_y) > 1.0e-9_dp) then
                    call put(self, ">] TJ"//eol)
                    open = .false.
                end if
            end if
            if (.not. open) then
                if (font /= cur_font .or. run%size(i) /= cur_size) then
                    call put(self, "/T"//int_str(font)//" "//num_str(run%size(i)) &
                             //" Tf"//eol)
                    cur_font = font
                    cur_size = run%size(i)
                end if
                call put_num(self, ca)
                call put_num(self, sa)
                call put_num(self, sa)
                call put_num(self, -ca)
                call put_num(self, x + run%x(i)*ca - run%y(i)*sa)
                call put_num(self, y + run%x(i)*sa + run%y(i)*ca)
                call put(self, "Tm"//eol//"[<")
                cur_y = run%y(i)
                open = .true.
            else
                ! TJ moves the next glyph left by a thousandth of the size
                ! per unit.
                adj = (expect - run%x(i))/run%size(i)*1000.0_dp
                if (abs(adj) > 1.0e-6_dp) then
                    call put(self, "> ")
                    call put_num(self, adj)
                    call put(self, "<")
                end if
            end if
            call put(self, hex2(code))
            expect = run%x(i) + glyph_adv(run%gid(i))*run%size(i)
        end do
        if (open) call put(self, ">] TJ"//eol)
        call put(self, "ET"//eol)
        if (actual_text) call put(self, "EMC"//eol)
        call put(self, "Q"//eol)
    end subroutine pdf_draw_glyphs

    subroutine put_actual_text(self, text)
        class(pdf_renderer_t), intent(inout) :: self
        character(len=*), intent(in) :: text
        integer :: i, code, nb, hi, lo

        call put(self, "/Span << /ActualText <FEFF")
        i = 1
        do while (i <= len(text))
            call utf8_next(text, i, code, nb)
            if (code > 1114111 .or. (code >= 55296 .and. code <= 57343)) code = 65533
            if (code < 65536) then
                call put(self, hex2(code/256)//hex2(mod(code, 256)))
            else
                code = code - 65536
                hi = 55296 + code/1024
                lo = 56320 + mod(code, 1024)
                call put(self, hex2(hi/256)//hex2(mod(hi, 256)) &
                         //hex2(lo/256)//hex2(mod(lo, 256)))
            end if
            i = i + nb
        end do
        call put(self, "> >> BDC"//new_line("a"))
    end subroutine put_actual_text

    pure elemental function hex2(v) result(s)
        integer, intent(in) :: v
        character(len=2) :: s
        character(len=16), parameter :: H = "0123456789ABCDEF"
        s = H(v/16 + 1:v/16 + 1)//H(mod(v, 16) + 1:mod(v, 16) + 1)
    end function hex2

    ! The image itself is registered for later; what goes in the content
    ! stream is a matrix and one Do. PDF draws an image into the unit square
    ! with the first row at the top of it, so the matrix that lands it on the
    ! API's rectangle is a flip: v = 1 is the top edge, and the page is
    ! already flipped underneath.
    subroutine pdf_draw_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(pdf_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(4, nx, ny)
        type(paint_t), intent(in) :: paint
        integer, allocatable :: rgb(:), a(:)
        type(pdf_image_t), allocatable :: images(:)
        integer :: i, j, k, id
        logical :: opaque

        if (nx < 1 .or. ny < 1) return
        if (.not. allocated(self%img)) allocate (self%img(16))
        if (self%n_img == size(self%img)) then
            allocate (images(2*self%n_img))
            images(1:self%n_img) = self%img(1:self%n_img)
            call move_alloc(images, self%img)
        end if

        allocate (rgb(3*nx*ny), a(nx*ny))
        k = 0
        opaque = .true.
        do j = 1, ny
            do i = 1, nx
                rgb(3*k + 1:3*k + 3) = rgba(1:3, i, j)
                a(k + 1) = rgba(4, i, j)
                if (rgba(4, i, j) < 255) opaque = .false.
                k = k + 1
            end do
        end do

        self%n_img = self%n_img + 1
        id = self%n_img
        self%img(id)%w = nx
        self%img(id)%h = ny
        self%img(id)%rgb = zlib_compress(rgb)
        if (opaque) then
            self%img(id)%alpha = ""
        else
            self%img(id)%alpha = zlib_compress(a)
        end if

        call begin_paint(self, paint)
        call put_num(self, w)
        call put_num(self, 0.0_dp)
        call put_num(self, 0.0_dp)
        call put_num(self, -h)
        call put_num(self, x)
        call put_num(self, y + h)
        call put(self, "cm"//new_line("a"))
        call put(self, "/Im"//int_str(id)//" Do"//new_line("a"))
        call put(self, "Q"//new_line("a"))
    end subroutine pdf_draw_image


    ! Assemble the file. Objects have to be byte-counted as they are written
    ! because the trailing xref table records where each one starts.
    subroutine pdf_close_canvas(self)
        class(pdf_renderer_t), intent(inout) :: self
        type(svg_builder) :: f
        character(len=:), allocatable :: content, res, gs, xo, ft, kids
        integer, allocatable :: off(:), font_obj(:), img_obj(:), mask_obj(:)
        integer :: nobj, i, pos, xref_pos, np, k
        real(dp) :: page_w, page_h
        character(len=1) :: eol

        if (self%n_frame /= 0) error stop "pdf: unclosed frame at close_canvas"
        eol = new_line("a")
        content = builder_get(self%c)
        ! Page k is object 2k + 1 and its content 2k + 2; the last page is
        ! the one being drawn.
        np = self%npages + 1

        ! /ExtGState entries for the alpha values the figure actually used.
        gs = ""
        do i = 1, self%n_alpha
            gs = gs//"/GS"//int_str(i)//" << /Type /ExtGState /ca " &
                 //num_str(self%alpha_fill(i))//" /CA " &
                 //num_str(self%alpha_stroke(i))//" >> "
        end do

        ! Each font is three kinds of object: its dictionary, its map back
        ! to Unicode, and one stream per glyph. The images follow, one
        ! object each and a second for a soft mask where one is needed.
        nobj = 2 + 2*np
        allocate (font_obj(self%t3%nfont), img_obj(self%n_img), mask_obj(self%n_img))
        ft = ""
        do i = 1, self%t3%nfont
            font_obj(i) = nobj + 1
            nobj = nobj + 2 + self%t3%n(i)
            ft = ft//"/T"//int_str(i)//" "//int_str(font_obj(i))//" 0 R "
        end do
        xo = ""
        do i = 1, self%n_img
            nobj = nobj + 1
            img_obj(i) = nobj
            mask_obj(i) = 0
            if (len(self%img(i)%alpha) > 0) then
                nobj = nobj + 1
                mask_obj(i) = nobj
            end if
            xo = xo//"/Im"//int_str(i)//" "//int_str(img_obj(i))//" 0 R "
        end do

        allocate (off(nobj))
        res = "<<"
        if (len(ft) > 0) res = res//" /Font << "//ft//">>"
        if (len(gs) > 0) res = res//" /ExtGState << "//gs//">>"
        if (len(xo) > 0) res = res//" /XObject << "//xo//">>"
        res = res//" >>"

        call builder_init(f)
        pos = 0

        call emit(f, pos, "%PDF-1.4"//eol)
        ! A comment with high bytes marks the file as binary for tools that
        ! sniff it.
        call emit(f, pos, "%"//achar(226)//achar(227)//achar(207)//achar(211)//eol)

        off(1) = pos
        call emit(f, pos, "1 0 obj"//eol//"<< /Type /Catalog /Pages 2 0 R >>" &
                  //eol//"endobj"//eol)

        kids = ""
        do k = 1, np
            if (k > 1) kids = kids//" "
            kids = kids//int_str(2*k + 1)//" 0 R"
        end do
        off(2) = pos
        call emit(f, pos, "2 0 obj"//eol//"<< /Type /Pages /Kids ["//kids//"] /Count " &
                  //int_str(np)//" >>"//eol//"endobj"//eol)

        do k = 1, np
            page_w = self%w
            page_h = self%h
            if (k < np) then
                page_w = self%pages(k)%w
                page_h = self%pages(k)%h
            end if
            off(2*k + 1) = pos
            call emit(f, pos, int_str(2*k + 1)//" 0 obj"//eol &
                      //"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " &
                      //num_str(page_w)//" "//num_str(page_h)//"] /Contents " &
                      //int_str(2*k + 2)//" 0 R /Resources "//res//" >>"//eol//"endobj"//eol)
            off(2*k + 2) = pos
            if (k < np) then
                call emit(f, pos, int_str(2*k + 2)//" 0 obj"//eol//"<< /Length " &
                          //int_str(len(self%pages(k)%content))//" >>"//eol//"stream"//eol)
                call emit(f, pos, self%pages(k)%content)
            else
                call emit(f, pos, int_str(2*k + 2)//" 0 obj"//eol//"<< /Length " &
                          //int_str(len(content))//" >>"//eol//"stream"//eol)
                call emit(f, pos, content)
            end if
            call emit(f, pos, "endstream"//eol//"endobj"//eol)
        end do

        do i = 1, self%t3%nfont
            call emit_font(self, f, pos, off, i, font_obj(i))
        end do

        do i = 1, self%n_img
            off(img_obj(i)) = pos
            call emit(f, pos, int_str(img_obj(i))//" 0 obj"//eol &
                      //"<< /Type /XObject /Subtype /Image /Width " &
                      //int_str(self%img(i)%w)//" /Height "//int_str(self%img(i)%h) &
                      //" /ColorSpace /DeviceRGB /BitsPerComponent 8" &
                      //" /Filter /FlateDecode")
            if (mask_obj(i) > 0) then
                call emit(f, pos, " /SMask "//int_str(mask_obj(i))//" 0 R")
            end if
            call emit(f, pos, " /Length "//int_str(len(self%img(i)%rgb))//" >>" &
                      //eol//"stream"//eol)
            call emit(f, pos, self%img(i)%rgb)
            call emit(f, pos, eol//"endstream"//eol//"endobj"//eol)

            ! The mask is the alpha channel as a greyscale image of the same
            ! size, which is how PDF spells per-sample transparency.
            if (mask_obj(i) > 0) then
                off(mask_obj(i)) = pos
                call emit(f, pos, int_str(mask_obj(i))//" 0 obj"//eol &
                          //"<< /Type /XObject /Subtype /Image /Width " &
                          //int_str(self%img(i)%w)//" /Height "//int_str(self%img(i)%h) &
                          //" /ColorSpace /DeviceGray /BitsPerComponent 8" &
                          //" /Filter /FlateDecode /Length " &
                          //int_str(len(self%img(i)%alpha))//" >>"//eol//"stream"//eol)
                call emit(f, pos, self%img(i)%alpha)
                call emit(f, pos, eol//"endstream"//eol//"endobj"//eol)
            end if
        end do

        xref_pos = pos
        call emit(f, pos, "xref"//eol//"0 "//int_str(nobj + 1)//eol)
        call emit(f, pos, "0000000000 65535 f "//eol)
        do i = 1, nobj
            call emit(f, pos, pad10(off(i))//" 00000 n "//eol)
        end do
        call emit(f, pos, "trailer"//eol//"<< /Size "//int_str(nobj + 1) &
                  //" /Root 1 0 R >>"//eol)
        call emit(f, pos, "startxref"//eol//int_str(xref_pos)//eol//"%%EOF"//eol)

        self%out = builder_get(f)
        self%is_open = .false.
    end subroutine pdf_close_canvas

    ! One Type 3 font: the dictionary at object obj, its ToUnicode map at
    ! obj + 1 and the glyph procedures after that, one per code.
    subroutine emit_font(self, f, pos, off, font, obj)
        class(pdf_renderer_t), intent(in) :: self
        type(svg_builder), intent(inout) :: f
        integer, intent(inout) :: pos, off(:)
        integer, intent(in) :: font, obj
        character(len=:), allocatable :: procs, diffs, widths, cmap, body, u
        character(len=1) :: eol
        integer :: k, gid, b(4), fb(4), nmap, first
        logical :: any

        eol = new_line("a")
        procs = ""
        diffs = ""
        widths = ""
        fb = 0
        any = .false.
        do k = 0, self%t3%n(font) - 1
            gid = self%t3%gids(k, font)
            procs = procs//"/g"//int_str(gid)//" "//int_str(obj + 2 + k)//" 0 R "
            diffs = diffs//"/g"//int_str(gid)
            widths = widths//num_str(t3_width(gid))//" "
            if (glyph_inked(gid)) then
                call t3_box(gid, b)
                if (any) then
                    fb = [min(fb(1), b(1)), min(fb(2), b(2)), &
                          max(fb(3), b(3)), max(fb(4), b(4))]
                else
                    fb = b
                    any = .true.
                end if
            end if
        end do

        off(obj) = pos
        call emit(f, pos, int_str(obj)//" 0 obj"//eol &
                  //"<< /Type /Font /Subtype /Type3 /Name /"//t3_font_name(self%t3, font) &
                  //" /FontBBox ["//int_str(fb(1))//" "//int_str(fb(2))//" " &
                  //int_str(fb(3))//" "//int_str(fb(4))//"]" &
                  //" /FontMatrix [0.001 0 0 0.001 0 0]"//eol &
                  //"/CharProcs << "//procs//">>"//eol &
                  //"/Encoding << /Type /Encoding /Differences [0 "//diffs//"] >>"//eol &
                  //"/FirstChar 0 /LastChar "//int_str(self%t3%n(font) - 1) &
                  //" /Widths ["//widths//"]"//eol &
                  //"/Resources << >> /ToUnicode "//int_str(obj + 1)//" 0 R >>"//eol &
                  //"endobj"//eol)

        ! The map back to Unicode, at most a hundred entries to a block as
        ! the CMap syntax requires.
        cmap = "/CIDInit /ProcSet findresource begin"//eol//"12 dict begin"//eol &
               //"begincmap"//eol &
               //"/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def" &
               //eol//"/CMapName /Adobe-Identity-UCS def"//eol//"/CMapType 2 def"//eol &
               //"1 begincodespacerange"//eol//"<00> <FF>"//eol//"endcodespacerange"//eol
        first = 0
        do while (first < self%t3%n(font))
            body = ""
            nmap = 0
            k = first
            do while (k < self%t3%n(font) .and. nmap < 100)
                u = t3_unicode(self%t3%gids(k, font))
                if (len(u) > 0) then
                    body = body//"<"//hex2(k)//"> <"//u//">"//eol
                    nmap = nmap + 1
                end if
                k = k + 1
            end do
            if (nmap > 0) cmap = cmap//int_str(nmap)//" beginbfchar"//eol//body &
                                 //"endbfchar"//eol
            first = k
        end do
        cmap = cmap//"endcmap"//eol//"CMapName currentdict /CMap defineresource pop" &
               //eol//"end"//eol//"end"//eol
        off(obj + 1) = pos
        call emit(f, pos, int_str(obj + 1)//" 0 obj"//eol//"<< /Length " &
                  //int_str(len(cmap))//" >>"//eol//"stream"//eol)
        call emit(f, pos, cmap)
        call emit(f, pos, "endstream"//eol//"endobj"//eol)

        ! Each glyph procedure sets its width and box with d1, which also
        ! says it takes its colour from the text it is part of, and then
        ! fills its outline.
        do k = 0, self%t3%n(font) - 1
            gid = self%t3%gids(k, font)
            if (glyph_inked(gid)) then
                call t3_box(gid, b)
                body = num_str(t3_width(gid))//" 0 "//int_str(b(1))//" " &
                       //int_str(b(2))//" "//int_str(b(3))//" "//int_str(b(4)) &
                       //" d1"//eol//t3_glyph_ops(gid, [character(len=1) :: &
                                                         "m", "l", "c", "h"]) &
                       //"f"//eol
            else
                body = num_str(t3_width(gid))//" 0 0 0 0 0 d1"//eol
            end if
            off(obj + 2 + k) = pos
            call emit(f, pos, int_str(obj + 2 + k)//" 0 obj"//eol//"<< /Length " &
                      //int_str(len(body))//" >>"//eol//"stream"//eol)
            call emit(f, pos, body)
            call emit(f, pos, "endstream"//eol//"endobj"//eol)
        end do
    end subroutine emit_font

    subroutine emit(f, pos, s)
        type(svg_builder), intent(inout) :: f
        integer, intent(inout) :: pos
        character(len=*), intent(in) :: s
        call builder_append(f, s)
        pos = pos + len(s)
    end subroutine emit

    ! xref offsets are a fixed ten digits wide.
    pure function pad10(i) result(t)
        integer, intent(in) :: i
        character(len=10) :: t
        write (t, "(I10.10)") i
    end function pad10

    function pdf_bytes(self) result(s)
        class(pdf_renderer_t), intent(in) :: self
        character(len=:), allocatable :: s
        if (allocated(self%out)) then
            s = self%out
        else
            s = ""
        end if
    end function pdf_bytes

end module fplotlib_backend_pdf
