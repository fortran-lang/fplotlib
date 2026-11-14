! EPS backend.
!
! PostScript is the oldest of the four formats and the one with the fewest
! features, so this backend is the PDF one with three things taken away and
! one added:
!
!   * there is no transparency. PostScript has no alpha at all, so a
!     translucent color is composited against the page here instead, which
!     is the only way to get the intended appearance into the file. That is
!     exact where the thing underneath is the white page and approximate
!     where it is not, and matplotlib's own PS output does not even try.
!
!   * y grows upwards, as in PDF, and is handled the same way: one flipping
!     matrix for the whole page, undone around each run of glyphs so text
!     is not drawn mirrored.
!
!   * there is no arc operator that would help, so circles become four
!     cubics, exactly as in PDF.
!
! What it adds is the DSC header, %%BoundingBox above all, which is what
! makes the file embeddable in a document.
!
! Text arrives as glyphs already laid out and is shown with Type 3 fonts
! built from the compiled-in outlines (see fplotlib_type3), defined in the
! prolog once the page knows which glyphs it used.
module fplotlib_backend_eps
    use fplotlib_render_checks
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_render
    use fplotlib_glyphs, only: glyph_inked
    use fplotlib_type3, only: t3set_t, t3_reset, t3_code, t3_font_name, &
                              t3_glyph_ops, t3_width, t3_box
    use fplotlib_svg, only: svg_builder, builder_init, builder_append, &
                         builder_get, fmt_num
    implicit none
    private

    public :: eps_renderer_t

    type, extends(encoded_renderer_t) :: eps_renderer_t
        type(svg_builder) :: c
        character(len=:), allocatable :: out
        real(dp) :: w = 0.0_dp, h = 0.0_dp
        real(dp) :: x0 = 0.0_dp, y0 = 0.0_dp
        ! What a translucent color is composited against.
        integer :: page_rgb(3) = [255, 255, 255]
        ! The glyphs the page has drawn, and the fonts they went into.
        type(t3set_t) :: t3
    contains
        procedure :: open_canvas => eps_open_canvas
        procedure :: close_canvas => eps_close_canvas
        procedure :: bytes => eps_bytes
        procedure :: draw_path => eps_draw_path
        procedure :: draw_rect => eps_draw_rect
        procedure :: draw_circle => eps_draw_circle
        procedure :: draw_markers => eps_draw_markers
        procedure :: draw_glyphs => eps_draw_glyphs
        procedure :: draw_image => eps_draw_image
    end type eps_renderer_t


contains

    subroutine put(self, s)
        class(eps_renderer_t), intent(inout) :: self
        character(len=*), intent(in) :: s
        call builder_append(self%c, s)
    end subroutine put

    subroutine put_num(self, x)
        class(eps_renderer_t), intent(inout) :: self
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


    ! A translucent color has to become an opaque one, since the format
    ! cannot express the first.
    pure function blend(rgb, a, page) result(o)
        integer, intent(in) :: rgb(3), page(3)
        real(dp), intent(in) :: a
        integer :: o(3), i
        do i = 1, 3
            o(i) = nint(a*real(rgb(i), dp) + (1.0_dp - a)*real(page(i), dp))
        end do
    end function blend

    subroutine put_rgb(self, rgb, alpha)
        class(eps_renderer_t), intent(inout) :: self
        integer, intent(in) :: rgb(3)
        real(dp), intent(in) :: alpha
        integer :: c(3), i
        c = blend(rgb, alpha, self%page_rgb)
        do i = 1, 3
            call put_num(self, real(c(i), dp)/255.0_dp)
        end do
        call put(self, "setrgbcolor"//new_line("a"))
    end subroutine put_rgb

    ! Everything that has to be in force before a painting operator, inside
    ! gsave/grestore so it cannot leak into the next primitive.
    subroutine begin_paint(self, p)
        class(eps_renderer_t), intent(inout) :: self
        type(paint_t), intent(in) :: p
        integer :: i

        call put(self, "gsave"//new_line("a"))
        if (p%clip%on) then
            call put_num(self, p%clip%x)
            call put_num(self, p%clip%y)
            call put_num(self, p%clip%w)
            call put_num(self, p%clip%h)
            call put(self, "rectclip"//new_line("a"))
        end if
        if (p%stroked) then
            call put_num(self, p%line_width)
            call put(self, "setlinewidth"//new_line("a"))
            call put(self, int_str(p%cap)//" setlinecap"//new_line("a"))
            select case (p%join)
            case (JOIN_ROUND); call put(self, "1 setlinejoin"//new_line("a"))
            case (JOIN_BEVEL); call put(self, "2 setlinejoin"//new_line("a"))
            case default; call put(self, "0 setlinejoin"//new_line("a"))
            end select
            call put(self, "[")
            do i = 1, p%n_dash
                call put_num(self, p%dash(i))
            end do
            call put(self, "] "//num_str(p%dash_offset)//" setdash"//new_line("a"))
        end if
    end subroutine begin_paint

    ! Fill and stroke are separate operators in PostScript and each consumes
    ! the path, so a primitive that wants both keeps a copy of it.
    subroutine end_paint(self, p)
        class(eps_renderer_t), intent(inout) :: self
        type(paint_t), intent(in) :: p

        if (p%filled .and. p%stroked) call put(self, "gsave"//new_line("a"))
        if (p%filled) then
            call put_rgb(self, p%fill_rgb, p%fill_alpha)
            if (p%fill_rule == FILL_EVENODD) then
                call put(self, "eofill"//new_line("a"))
            else
                call put(self, "fill"//new_line("a"))
            end if
        end if
        if (p%filled .and. p%stroked) call put(self, "grestore"//new_line("a"))
        if (p%stroked) then
            call put_rgb(self, p%stroke_rgb, p%stroke_alpha)
            call put(self, "stroke"//new_line("a"))
        end if
        if (.not. (p%filled .or. p%stroked)) call put(self, "newpath"//new_line("a"))
        call put(self, "grestore"//new_line("a"))
    end subroutine end_paint

    subroutine eps_open_canvas(self, width, height, bg_rgb, bg_alpha, x0, y0, status)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha
        real(dp), intent(in), optional :: x0, y0
        type(paint_t) :: p

        type(status_t), intent(out) :: status

        call check_canvas(self, width, height, bg_rgb, bg_alpha, x0, y0, status=status)
        if (.not. status%ok()) return
        self%has_output = .false.
        self%width = width
        self%height = height
        self%is_open = .true.
        self%w = width
        self%h = height
        self%x0 = 0.0_dp
        self%y0 = 0.0_dp
        if (present(x0)) self%x0 = x0
        if (present(y0)) self%y0 = y0
        call t3_reset(self%t3)
        call builder_init(self%c)

        ! One matrix for the whole page turns the API's top-left origin with
        ! y downwards into PostScript's bottom-left origin with y upwards,
        ! and applies the canvas origin at the same time.
        call put(self, "[1 0 0 -1 "//num_str(-self%x0)//" " &
                 //num_str(self%y0 + height)//"] concat"//new_line("a"))

        if (present(bg_rgb)) then
            self%page_rgb = bg_rgb
            p%filled = .true.
            p%fill_rgb = bg_rgb
            if (present(bg_alpha)) p%fill_alpha = bg_alpha
            call eps_draw_rect(self, self%x0, self%y0, width, height, p, status=status)
            if (.not. status%ok()) return
        end if
    end subroutine eps_open_canvas

    subroutine emit_path(self, x, y, verbs, n_verb)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        integer :: i, k, j

        call put(self, "newpath"//new_line("a"))
        k = 0
        do i = 1, n_verb
            select case (verbs(i))
            case (VERB_MOVE)
                k = k + 1
                call put_num(self, x(k))
                call put_num(self, y(k))
                call put(self, "moveto"//new_line("a"))
            case (VERB_LINE)
                k = k + 1
                call put_num(self, x(k))
                call put_num(self, y(k))
                call put(self, "lineto"//new_line("a"))
            case (VERB_CUBIC)
                do j = 1, 3
                    k = k + 1
                    call put_num(self, x(k))
                    call put_num(self, y(k))
                end do
                call put(self, "curveto"//new_line("a"))
            case (VERB_CLOSE)
                call put(self, "closepath"//new_line("a"))
            end select
        end do
    end subroutine emit_path

    subroutine eps_draw_path(self, x, y, verbs, n_verb, paint, status)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        type(status_t), intent(out) :: status

        call check_open(self, status=status)
        if (.not. status%ok()) return
        call check_path(x, y, verbs, n_verb, paint, status=status)
        if (.not. status%ok()) return
        if (n_verb <= 0) return
        call begin_paint(self, paint)
        call emit_path(self, x, y, verbs, n_verb)
        call end_paint(self, paint)
    end subroutine eps_draw_path

    subroutine eps_draw_rect(self, x, y, w, h, paint, radius, status)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius

        type(status_t), intent(out) :: status

        call check_open(self, status=status)
        if (.not. status%ok()) return
        call check_rect(x, y, w, h, paint, radius, status=status)
        if (.not. status%ok()) return
        call begin_paint(self, paint)
        call put(self, "newpath"//new_line("a"))
        call put_num(self, x)
        call put_num(self, y)
        call put(self, "moveto"//new_line("a"))
        call put_num(self, w)
        call put(self, "0 rlineto"//new_line("a"))
        call put_num(self, 0.0_dp)
        call put_num(self, h)
        call put(self, "rlineto"//new_line("a"))
        call put_num(self, -w)
        call put(self, "0 rlineto"//new_line("a"))
        call put(self, "closepath"//new_line("a"))
        call end_paint(self, paint)
    end subroutine eps_draw_rect

    subroutine eps_draw_circle(self, cx, cy, r, paint, status)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint

        type(status_t), intent(out) :: status

        call check_open(self, status=status)
        if (.not. status%ok()) return
        call check_rect(cx, cy, r, r, paint, status=status)
        if (.not. status%ok()) return
        call begin_paint(self, paint)
        call put(self, "newpath"//new_line("a"))
        call put_num(self, cx)
        call put_num(self, cy)
        call put_num(self, r)
        call put(self, "0 360 arc closepath"//new_line("a"))
        call end_paint(self, paint)
    end subroutine eps_draw_circle

    subroutine eps_draw_markers(self, x, y, mx, my, mverbs, n_mverb, paint, status)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        real(dp), intent(in) :: mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
        integer :: i
        type(status_t), intent(out) :: status

        call check_open(self, status=status)
        if (.not. status%ok()) return
        if (size(x) /= size(y)) then
            call status%set(ERROR_ARGUMENT, "markers: inconsistent coordinate counts")
            return
        end if
        call check_finite(x, status=status)
        if (.not. status%ok()) return
        call check_finite(y, status=status)
        if (.not. status%ok()) return
        call check_path(mx, my, mverbs, n_mverb, paint, status=status)
        if (.not. status%ok()) return
        do i = 1, size(x)
            call eps_draw_path(self, mx + x(i), my + y(i), mverbs, n_mverb, paint, status=status)
            if (.not. status%ok()) return
        end do
    end subroutine eps_draw_markers

    ! The run is shown in segments, each a stretch of glyphs in one font
    ! at one size on one baseline, set in a frame that turns the flipped
    ! page upright and along the text. xshow takes each glyph's advance
    ! from the layout, so kerning costs nothing extra.
    subroutine eps_draw_glyphs(self, x, y, run, paint, angle, status)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
        real(dp) :: ca, sa, rad
        integer :: i, j, k, font, code, font_j, code_j
        character(len=1) :: eol

        type(status_t), intent(out) :: status

        call check_open(self, status=status)
        if (.not. status%ok()) return
        call check_finite([x, y, angle], status=status)
        if (.not. status%ok()) return
        call check_paint(paint, status=status)
        if (.not. status%ok()) return
        call check_glyphs(run, status=status)
        if (.not. status%ok()) return
        if (run%n == 0) return
        eol = new_line("a")
        call put(self, "gsave"//eol)
        if (paint%clip%on) then
            call put_num(self, paint%clip%x)
            call put_num(self, paint%clip%y)
            call put_num(self, paint%clip%w)
            call put_num(self, paint%clip%h)
            call put(self, "rectclip"//eol)
        end if
        call put_rgb(self, paint%fill_rgb, paint%fill_alpha)
        rad = angle*acos(-1.0_dp)/180.0_dp
        ca = cos(rad)
        sa = sin(rad)

        i = 1
        do while (i <= run%n)
            call t3_code(self%t3, run%gid(i), font, code)
            ! The segment runs to the last glyph that shares all three.
            j = i
            do while (j < run%n)
                call t3_code(self%t3, run%gid(j + 1), font_j, code_j)
                if (font_j /= font .or. run%size(j + 1) /= run%size(i) &
                    .or. abs(run%y(j + 1) - run%y(i)) > 1.0e-9_dp) exit
                j = j + 1
            end do
            call put(self, "gsave ["//num_str(ca)//" "//num_str(sa)//" " &
                     //num_str(sa)//" "//num_str(-ca)//" " &
                     //num_str(x + run%x(i)*ca - run%y(i)*sa)//" " &
                     //num_str(y + run%x(i)*sa + run%y(i)*ca)//"] concat"//eol)
            call put(self, "/"//t3_font_name(self%t3, font)//" findfont " &
                     //num_str(run%size(i))//" scalefont setfont"//eol)
            call put(self, "0 0 moveto <")
            do k = i, j
                call t3_code(self%t3, run%gid(k), font_j, code_j)
                call put(self, hex2(code_j))
            end do
            call put(self, "> [")
            do k = i, j - 1
                call put_num(self, run%x(k + 1) - run%x(k))
            end do
            call put(self, "0] xshow grestore"//eol)
            i = j + 1
        end do
        call put(self, "grestore"//eol)
    end subroutine eps_draw_glyphs

    pure elemental function hex2(v) result(s)
        integer, intent(in) :: v
        character(len=2) :: s
        character(len=16), parameter :: H = "0123456789ABCDEF"
        s = H(v/16 + 1:v/16 + 1)//H(mod(v, 16) + 1:mod(v, 16) + 1)
    end function hex2

    ! The samples go into the file as hexadecimal, which every PostScript
    ! interpreter reads and which keeps the file printable. Transparency is
    ! composited against the page here, as everywhere else in this backend.
    subroutine eps_draw_image(self, x, y, w, h, rgba, nx, ny, paint, status)
        class(eps_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint
        character(len=*), parameter :: HEX = "0123456789abcdef"
        integer :: i, j, k, c(3)
        character(len=1) :: buf(6)

        type(status_t), intent(out) :: status

        call check_open(self, status=status)
        if (.not. status%ok()) return
        call check_image(x, y, w, h, rgba, nx, ny, paint, status=status)
        if (.not. status%ok()) return
        if (nx < 1 .or. ny < 1) return

        call put(self, "gsave"//new_line("a"))
        call put_num(self, x)
        call put_num(self, y + h)
        call put(self, "translate"//new_line("a"))
        call put_num(self, w)
        call put_num(self, -h)
        call put(self, "scale"//new_line("a"))
        call put(self, int_str(nx)//" "//int_str(ny)//" 8 [" &
                 //int_str(nx)//" 0 0 "//int_str(-ny)//" 0 "//int_str(ny)//"]" &
                 //new_line("a"))
        call put(self, "{currentfile "//int_str(3*nx) &
                 //" string readhexstring pop} bind" &
                 //new_line("a"))
        call put(self, "false 3 colorimage"//new_line("a"))

        k = 0
        do j = 1, ny
            do i = 1, nx
                c = blend(rgba(1:3, i, j), real(rgba(4, i, j), dp)/255.0_dp, &
                          self%page_rgb)
                buf(1) = HEX(c(1)/16 + 1:c(1)/16 + 1)
                buf(2) = HEX(mod(c(1), 16) + 1:mod(c(1), 16) + 1)
                buf(3) = HEX(c(2)/16 + 1:c(2)/16 + 1)
                buf(4) = HEX(mod(c(2), 16) + 1:mod(c(2), 16) + 1)
                buf(5) = HEX(c(3)/16 + 1:c(3)/16 + 1)
                buf(6) = HEX(mod(c(3), 16) + 1:mod(c(3), 16) + 1)
                call put(self, buf(1)//buf(2)//buf(3)//buf(4)//buf(5)//buf(6))
                k = k + 1
                if (mod(k, 12) == 0) call put(self, new_line("a"))
            end do
        end do
        call put(self, new_line("a")//"grestore"//new_line("a"))
    end subroutine eps_draw_image

    ! Wrap the page in the DSC comments that make it an EPS rather than a
    ! bare PostScript program: the bounding box above all, since that is what
    ! a document that embeds the figure reads.
    subroutine eps_close_canvas(self, status)
        class(eps_renderer_t), intent(inout) :: self
        type(svg_builder) :: f
        character(len=1) :: eol
        integer :: i

        type(status_t), intent(out) :: status

        call check_open(self, status=status)
        if (.not. status%ok()) return
        eol = new_line("a")
        call builder_init(f)
        call builder_append(f, "%!PS-Adobe-3.0 EPSF-3.0"//eol)
        call builder_append(f, "%%Creator: fplotlib"//eol)
        call builder_append(f, "%%BoundingBox: 0 0 "//int_str(ceiling(self%w)) &
                            //" "//int_str(ceiling(self%h))//eol)
        call builder_append(f, "%%HiResBoundingBox: 0 0 "//num_str(self%w) &
                            //" "//num_str(self%h)//eol)
        call builder_append(f, "%%EndComments"//eol)
        call builder_append(f, "%%BeginProlog"//eol)
        do i = 1, self%t3%nfont
            call builder_append(f, font_resource(self, i))
        end do
        call builder_append(f, "%%EndProlog"//eol)
        call builder_append(f, "%%Page: 1 1"//eol)
        call builder_append(f, builder_get(self%c))
        call builder_append(f, "showpage"//eol//"%%EOF"//eol)
        self%out = builder_get(f)
        self%is_open = .false.
        self%has_output = .true.
    end subroutine eps_close_canvas

    ! One Type 3 font as a PostScript resource. Each glyph is a procedure
    ! that declares its width and box with setcachedevice, which also says
    ! it takes its colour from the text, and fills its outline. BuildGlyph
    ! runs the procedure by name, and BuildChar finds the name through the
    ! encoding, for the interpreters that only know the older of the two.
    function font_resource(self, font) result(r)
        class(eps_renderer_t), intent(in) :: self
        integer, intent(in) :: font
        character(len=:), allocatable :: r, name
        type(svg_builder) :: b
        character(len=1) :: eol
        integer :: k, gid, bx(4), fb(4)
        logical :: any

        eol = new_line("a")
        name = t3_font_name(self%t3, font)
        fb = 0
        any = .false.
        do k = 0, self%t3%n(font) - 1
            gid = self%t3%gids(k, font)
            if (.not. glyph_inked(gid)) cycle
            call t3_box(gid, bx)
            if (any) then
                fb = [min(fb(1), bx(1)), min(fb(2), bx(2)), &
                      max(fb(3), bx(3)), max(fb(4), bx(4))]
            else
                fb = bx
                any = .true.
            end if
        end do

        call builder_init(b)
        call builder_append(b, "%%BeginResource: font "//name//eol)
        call builder_append(b, "10 dict begin"//eol//"/FontType 3 def"//eol &
                            //"/FontName /"//name//" def"//eol &
                            //"/FontMatrix [0.001 0 0 0.001 0 0] def"//eol &
                            //"/FontBBox ["//int_str(fb(1))//" "//int_str(fb(2))//" " &
                            //int_str(fb(3))//" "//int_str(fb(4))//"] def"//eol &
                            //"/Encoding 256 array def"//eol &
                            //"0 1 255 {Encoding exch /.notdef put} for"//eol)
        do k = 0, self%t3%n(font) - 1
            call builder_append(b, "Encoding "//int_str(k)//" /g" &
                                //int_str(self%t3%gids(k, font))//" put"//eol)
        end do
        call builder_append(b, "/CharProcs "//int_str(self%t3%n(font) + 1) &
                            //" dict def"//eol//"CharProcs begin"//eol &
                            //"/.notdef {0 0 0 0 0 0 setcachedevice} def"//eol)
        do k = 0, self%t3%n(font) - 1
            gid = self%t3%gids(k, font)
            if (glyph_inked(gid)) then
                call t3_box(gid, bx)
                call builder_append(b, "/g"//int_str(gid)//" {" &
                                    //num_str(t3_width(gid))//" 0 "//int_str(bx(1)) &
                                    //" "//int_str(bx(2))//" "//int_str(bx(3))//" " &
                                    //int_str(bx(4))//" setcachedevice"//eol &
                                    //"newpath"//eol &
                                    //t3_glyph_ops(gid, [character(len=9) :: "moveto", &
                                                         "lineto", "curveto", "closepath"]) &
                                    //"fill} bind def"//eol)
            else
                call builder_append(b, "/g"//int_str(gid)//" {" &
                                    //num_str(t3_width(gid)) &
                                    //" 0 0 0 0 0 setcachedevice} bind def"//eol)
            end if
        end do
        call builder_append(b, "end"//eol &
                            //"/BuildGlyph {exch /CharProcs get exch 2 copy known" &
                            //" not {pop /.notdef} if get exec} bind def"//eol &
                            //"/BuildChar {1 index /Encoding get exch get" &
                            //" 1 index /BuildGlyph get exec} bind def"//eol &
                            //"currentdict end"//eol &
                            //"/"//name//" exch definefont pop"//eol &
                            //"%%EndResource"//eol)
        r = builder_get(b)
    end function font_resource

    function eps_bytes(self, status) result(s)
        class(eps_renderer_t), intent(in) :: self
        character(len=:), allocatable :: s
        type(status_t), intent(out) :: status

        s = ""
        if (.not. self%has_output .or. self%is_open) then
            call status%set(ERROR_STATE, "renderer: no finished encoded output")
            return
        end if
        if (allocated(self%out)) then
            s = self%out
        else
            s = ""
        end if
    end function eps_bytes

end module fplotlib_backend_eps
