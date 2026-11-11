! fplotlib_type3 -- the glyphs a PDF or EPS file uses, as Type 3 fonts.
!
! PDF and PostScript both let a document carry a font whose glyphs are
! procedures that draw them, a Type 3 font. That is what fplotlib embeds:
! each glyph's procedure is its compiled-in outline, so the file draws
! exactly what PNG and SVG draw and names no font a viewer could swap in,
! while the text stays text, selectable and searchable through a map back
! to Unicode.
!
! A Type 3 font has 256 codes, so the glyphs a document uses are handed
! out codes in the order they are first drawn, face by face, and a face
! that needs more than 256 glyphs gets a second font. Glyph space is a
! thousandth of an em, with y up, which is what the font matrix
! [0.001 0 0 0.001 0 0] says.
!
! The fonts get neutral names: the outlines are derived from Lato, and its
! licence reserves that name, so the files call them FplotlibSans-Regular,
! FplotlibSans-Bold, FplotlibSans-Italic and FplotlibSans-BoldItalic.
module fplotlib_type3
    use fplotlib_style, only: dp
    use fplotlib_render, only: VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_CLOSE
    use fplotlib_svg, only: svg_builder, builder_init, builder_append, &
                            builder_get, fmt_num
    use fplotlib_glyphs, only: NGLYPH, NFACE, glyph_face, glyph_adv, glyph_bbox, &
                               glyph_outline, glyph_char
    implicit none
    private

    public :: t3set_t, t3_reset, t3_code, t3_font_name, t3_glyph_ops, &
              t3_width, t3_box, t3_unicode

    type :: t3set_t
        integer :: nfont = 0
        ! By gid: the font a glyph went into and its code there, 0 for a
        ! glyph not yet used.
        integer, allocatable :: font_of(:), code_of(:)
        ! By font: its face, how many codes it has handed out, and the gid
        ! behind each code.
        integer, allocatable :: face(:), n(:), gids(:, :)
        ! The font each face is filling at the moment.
        integer :: cur(NFACE) = 0
    end type t3set_t

contains

    subroutine t3_reset(t)
        type(t3set_t), intent(inout) :: t
        if (allocated(t%font_of)) deallocate (t%font_of, t%code_of)
        if (allocated(t%face)) deallocate (t%face, t%n, t%gids)
        allocate (t%font_of(NGLYPH), t%code_of(NGLYPH))
        allocate (t%face(4), t%n(4), t%gids(0:255, 4))
        t%font_of = 0
        t%code_of = 0
        t%nfont = 0
        t%cur = 0
    end subroutine t3_reset

    ! The font and code a glyph is drawn with, handing them out the first
    ! time it is asked for.
    subroutine t3_code(t, gid, font, code)
        type(t3set_t), intent(inout) :: t
        integer, intent(in) :: gid
        integer, intent(out) :: font, code
        integer, allocatable :: ti(:), tg(:, :)
        integer :: f, cap

        if (t%font_of(gid) > 0) then
            font = t%font_of(gid)
            code = t%code_of(gid)
            return
        end if
        f = glyph_face(gid)
        font = t%cur(f)
        if (font > 0) then
            if (t%n(font) >= 256) font = 0
        end if
        if (font == 0) then
            if (t%nfont >= size(t%face)) then
                cap = 2*size(t%face)
                allocate (ti(cap))
                ti(1:t%nfont) = t%face(1:t%nfont)
                call move_alloc(ti, t%face)
                allocate (ti(cap))
                ti(1:t%nfont) = t%n(1:t%nfont)
                call move_alloc(ti, t%n)
                allocate (tg(0:255, cap))
                tg(:, 1:t%nfont) = t%gids(:, 1:t%nfont)
                call move_alloc(tg, t%gids)
            end if
            t%nfont = t%nfont + 1
            font = t%nfont
            t%face(font) = f
            t%n(font) = 0
            t%cur(f) = font
        end if
        code = t%n(font)
        t%gids(code, font) = gid
        t%n(font) = t%n(font) + 1
        t%font_of(gid) = font
        t%code_of(gid) = code
    end subroutine t3_code

    ! The name a font goes by: its face's, and a number after it for the
    ! second and later fonts of one face.
    function t3_font_name(t, font) result(name)
        type(t3set_t), intent(in) :: t
        integer, intent(in) :: font
        character(len=:), allocatable :: name
        character(len=16) :: num
        integer :: k, i

        select case (t%face(font))
        case (2); name = "FplotlibSans-Bold"
        case (3); name = "FplotlibSans-Italic"
        case (4); name = "FplotlibSans-BoldItalic"
        case default; name = "FplotlibSans-Regular"
        end select
        k = 0
        do i = 1, font
            if (t%face(i) == t%face(font)) k = k + 1
        end do
        if (k > 1) then
            write (num, "(I0)") k
            name = name//"-"//trim(num)
        end if
    end function t3_font_name

    ! Advance width in glyph space.
    real(dp) function t3_width(gid)
        integer, intent(in) :: gid
        t3_width = 1000.0_dp*glyph_adv(gid)
    end function t3_width

    ! The ink box in glyph space, rounded outwards to whole units.
    subroutine t3_box(gid, b)
        integer, intent(in) :: gid
        integer, intent(out) :: b(4)
        real(dp) :: x0, y0, x1, y1
        call glyph_bbox(gid, x0, y0, x1, y1)
        b = [floor(1000.0_dp*x0), floor(1000.0_dp*y0), &
             ceiling(1000.0_dp*x1), ceiling(1000.0_dp*y1)]
    end subroutine t3_box

    ! The outline as path operators in glyph space, spelled with ops:
    ! move, line, curve and close, which PDF and PostScript name
    ! differently.
    function t3_glyph_ops(gid, ops) result(s)
        integer, intent(in) :: gid
        character(len=*), intent(in) :: ops(4)
        character(len=:), allocatable :: s
        type(svg_builder) :: b
        integer, allocatable :: v(:)
        real(dp), allocatable :: x(:), y(:)
        integer :: nv, np, i, j, k

        call glyph_outline(gid, v, nv, x, y, np)
        call builder_init(b)
        k = 0
        do i = 1, nv
            select case (v(i))
            case (VERB_MOVE)
                k = k + 1
                call num(x(k))
                call num(y(k))
                call builder_append(b, trim(ops(1))//new_line("a"))
            case (VERB_LINE)
                k = k + 1
                call num(x(k))
                call num(y(k))
                call builder_append(b, trim(ops(2))//new_line("a"))
            case (VERB_CUBIC)
                do j = 1, 3
                    k = k + 1
                    call num(x(k))
                    call num(y(k))
                end do
                call builder_append(b, trim(ops(3))//new_line("a"))
            case (VERB_CLOSE)
                call builder_append(b, trim(ops(4))//new_line("a"))
            end select
        end do
        s = builder_get(b)

    contains

        subroutine num(v)
            real(dp), intent(in) :: v
            character(len=64) :: t
            integer :: n
            call fmt_num(1000.0_dp*v, t, n)
            call builder_append(b, t(1:n)//" ")
        end subroutine num

    end function t3_glyph_ops

    ! The character a glyph stands for as UTF-16BE hex digits, for a
    ! ToUnicode map; empty for a glyph that stands for none.
    function t3_unicode(gid) result(s)
        integer, intent(in) :: gid
        character(len=:), allocatable :: s
        integer :: c, hi, lo
        c = glyph_char(gid)
        if (c <= 0) then
            s = ""
        else if (c < 65536) then
            s = hex4(c)
        else
            hi = 55296 + (c - 65536)/1024
            lo = 56320 + mod(c - 65536, 1024)
            s = hex4(hi)//hex4(lo)
        end if
    end function t3_unicode

    pure function hex4(v) result(s)
        integer, intent(in) :: v
        character(len=4) :: s
        character(len=16), parameter :: H = "0123456789ABCDEF"
        integer :: i, d
        do i = 1, 4
            d = ibits(v, 4*(4 - i), 4)
            s(i:i) = H(d + 1:d + 1)
        end do
    end function hex4

end module fplotlib_type3
