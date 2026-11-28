! Tests for runtime loading of external TrueType (.ttf) and OpenType (.otf)
! font files via load_font / reset_fonts across all four backends (SVG, PNG,
! PDF, EPS).
program test_external_font
    use, intrinsic :: iso_fortran_env, only: int64
    use fplotlib, only: dp, status_t, figure, clf, close, plot, title, xlabel, &
                        ylabel, render_svg, render_png, render_pdf, render_eps, &
                        load_font, reset_fonts
    use fplotlib_glyphs, only: NGLYPH, FACE_REGULAR, FACE_BOLD, FACE_ITALIC, &
                               FACE_MATH, glyph_count, glyph_cmap, glyph_adv, &
                               glyph_bbox, glyph_outline, glyph_kern, glyph_char, &
                               face_ascent, face_descent, math_const, math_percent
    use fplotlib_glyphs_data, only: MC_AXIS_HEIGHT, MC_SCRIPT_PERCENT_SCALE_DOWN, &
                                    MC_FRACTION_RULE_THICKNESS
    use fplotlib_render, only: VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_CLOSE
    use fplotlib_io, only: write_bytes
    implicit none

    call execute_command_line("mkdir -p tests/out")
    call test_minimal_ttf()
    call test_minimal_otf_math()
    call test_error_handling()
    call test_real_fonts_if_present()
    print *, "test_external_font: all checks passed"

contains

    ! --- Binary packing helpers (big-endian) --------------------------

    subroutine push_u8(buf, n, v)
        character(len=:), allocatable, intent(inout) :: buf
        integer, intent(inout) :: n
        integer, intent(in) :: v
        character(len=:), allocatable :: tmp
        integer :: cap
        if (.not. allocated(buf)) then
            allocate (character(len=256) :: buf)
            n = 0
        else if (n >= len(buf)) then
            cap = 2*len(buf)
            allocate (character(len=cap) :: tmp)
            tmp(1:n) = buf(1:n)
            call move_alloc(tmp, buf)
        end if
        n = n + 1
        buf(n:n) = achar(iand(v, 255))
    end subroutine push_u8

    subroutine push_u16(buf, n, v)
        character(len=:), allocatable, intent(inout) :: buf
        integer, intent(inout) :: n
        integer, intent(in) :: v
        integer :: u
        u = iand(v + 65536, 65535)
        call push_u8(buf, n, u/256)
        call push_u8(buf, n, mod(u, 256))
    end subroutine push_u16

    subroutine push_u32(buf, n, v)
        character(len=:), allocatable, intent(inout) :: buf
        integer, intent(inout) :: n
        integer(int64), intent(in) :: v
        call push_u8(buf, n, int(mod(v/16777216_int64, 256_int64)))
        call push_u8(buf, n, int(mod(v/65536_int64, 256_int64)))
        call push_u8(buf, n, int(mod(v/256_int64, 256_int64)))
        call push_u8(buf, n, int(mod(v, 256_int64)))
    end subroutine push_u32

    subroutine push_str(buf, n, s)
        character(len=:), allocatable, intent(inout) :: buf
        integer, intent(inout) :: n
        character(len=*), intent(in) :: s
        integer :: i
        do i = 1, len(s)
            call push_u8(buf, n, iachar(s(i:i)))
        end do
    end subroutine push_str

    ! Build a minimal valid TrueType (.ttf) font with:
    !   gid 0 (.notdef): empty, adv=500
    !   gid 1 (' ' U+0020): empty, adv=300
    !   gid 2 ('A' U+0041): simple quad contour (0,0)-(400,700 off)-(700,0), adv=800
    !   gid 3 ('V' U+0056): simple line contour (50,700)-(350,0)-(650,700), adv=750
    !   gid 4 ('B' U+0042): composite of gid 2 scaled 0.5 and shifted (50, 0), adv=900
    !   kern ('A', 'V') = -120
    subroutine build_minimal_ttf(path)
        character(len=*), intent(in) :: path
        character(len=4) :: tags(8)
        character(len=:), allocatable :: b
        integer :: n, i, g_off(6)
        character(len=:), allocatable :: t_cmap, t_glyf, t_head, t_hhea
        character(len=:), allocatable :: t_hmtx, t_kern, t_loca, t_maxp

        ! 1. head (54 bytes, unitsPerEm=1000, indexToLocFormat=1 long)
        n = 0
        call push_u32(b, n, 65536_int64)
        call push_u32(b, n, 65536_int64)
        call push_u32(b, n, 0_int64)
        call push_u32(b, n, 1594834165_int64)
        call push_u16(b, n, 0)
        call push_u16(b, n, 1000)
        do i = 1, 4
            call push_u32(b, n, 0_int64)
        end do
        call push_u16(b, n, 0); call push_u16(b, n, -200)
        call push_u16(b, n, 800); call push_u16(b, n, 800)
        call push_u16(b, n, 0); call push_u16(b, n, 8)
        call push_u16(b, n, 2); call push_u16(b, n, 1)
        call push_u16(b, n, 0)
        t_head = b(1:n)

        ! 2. hhea (36 bytes, asc=800, desc=-200, numberOfHMetrics=5)
        n = 0
        call push_u32(b, n, 65536_int64)
        call push_u16(b, n, 800); call push_u16(b, n, -200)
        call push_u16(b, n, 0); call push_u16(b, n, 900)
        do i = 1, 11
            call push_u16(b, n, 0)
        end do
        call push_u16(b, n, 5)
        t_hhea = b(1:n)

        ! 3. maxp (6 bytes, numGlyphs=5)
        n = 0
        call push_u32(b, n, 65536_int64)
        call push_u16(b, n, 5)
        t_maxp = b(1:n)

        ! 4. hmtx (5 * 4 = 20 bytes)
        n = 0
        call push_u16(b, n, 500); call push_u16(b, n, 0)
        call push_u16(b, n, 300); call push_u16(b, n, 0)
        call push_u16(b, n, 800); call push_u16(b, n, 0)
        call push_u16(b, n, 750); call push_u16(b, n, 50)
        call push_u16(b, n, 900); call push_u16(b, n, 50)
        t_hmtx = b(1:n)

        ! 5. glyf
        n = 0
        g_off(1) = 0
        g_off(2) = 0
        g_off(3) = n
        call push_u16(b, n, 1)
        call push_u16(b, n, 0); call push_u16(b, n, 0)
        call push_u16(b, n, 700); call push_u16(b, n, 700)
        call push_u16(b, n, 2); call push_u16(b, n, 0)
        call push_u8(b, n, 1); call push_u8(b, n, 0); call push_u8(b, n, 1)
        call push_u16(b, n, 0); call push_u16(b, n, 400); call push_u16(b, n, 300)
        call push_u16(b, n, 0); call push_u16(b, n, 700); call push_u16(b, n, -700)

        g_off(4) = n
        call push_u16(b, n, 1)
        call push_u16(b, n, 50); call push_u16(b, n, 0)
        call push_u16(b, n, 650); call push_u16(b, n, 700)
        call push_u16(b, n, 2); call push_u16(b, n, 0)
        call push_u8(b, n, 1); call push_u8(b, n, 1); call push_u8(b, n, 1)
        call push_u16(b, n, 50); call push_u16(b, n, 300); call push_u16(b, n, 300)
        call push_u16(b, n, 700); call push_u16(b, n, -700); call push_u16(b, n, 700)

        g_off(5) = n
        call push_u16(b, n, -1)
        call push_u16(b, n, 50); call push_u16(b, n, 0)
        call push_u16(b, n, 400); call push_u16(b, n, 350)
        call push_u16(b, n, 11); call push_u16(b, n, 2)
        call push_u16(b, n, 50); call push_u16(b, n, 0); call push_u16(b, n, 8192)
        g_off(6) = n
        t_glyf = b(1:n)

        ! 6. loca (long format, 6 * 4 bytes)
        n = 0
        do i = 1, 6
            call push_u32(b, n, int(g_off(i), int64))
        end do
        t_loca = b(1:n)

        ! 7. cmap (Format 4, 5 segments: ' '->1, 'A'->2, 'B'->4, 'V'->3, 0xFFFF->0)
        n = 0
        call push_u16(b, n, 0); call push_u16(b, n, 1)
        call push_u16(b, n, 3); call push_u16(b, n, 1)
        call push_u32(b, n, 12_int64)
        call push_u16(b, n, 4); call push_u16(b, n, 56)
        call push_u16(b, n, 0); call push_u16(b, n, 10)
        call push_u16(b, n, 8); call push_u16(b, n, 2); call push_u16(b, n, 2)
        call push_u16(b, n, 32); call push_u16(b, n, 65); call push_u16(b, n, 66)
        call push_u16(b, n, 86); call push_u16(b, n, 65535)
        call push_u16(b, n, 0)
        call push_u16(b, n, 32); call push_u16(b, n, 65); call push_u16(b, n, 66)
        call push_u16(b, n, 86); call push_u16(b, n, 65535)
        call push_u16(b, n, -31); call push_u16(b, n, -63); call push_u16(b, n, -62)
        call push_u16(b, n, -83); call push_u16(b, n, 1)
        do i = 1, 5
            call push_u16(b, n, 0)
        end do
        t_cmap = b(1:n)

        ! 8. kern (Format 0, 1 pair: (2='A', 3='V') -> -120)
        n = 0
        call push_u16(b, n, 0); call push_u16(b, n, 1)
        call push_u16(b, n, 0); call push_u16(b, n, 20)
        call push_u16(b, n, 1); call push_u16(b, n, 1)
        call push_u16(b, n, 6); call push_u16(b, n, 0); call push_u16(b, n, 0)
        call push_u16(b, n, 2); call push_u16(b, n, 3); call push_u16(b, n, -120)
        t_kern = b(1:n)

        tags = ["cmap", "glyf", "head", "hhea", "hmtx", "kern", "loca", "maxp"]
        call write_sfnt_8(path, 65536_int64, tags, t_cmap, t_glyf, t_head, t_hhea, &
                          t_hmtx, t_kern, t_loca, t_maxp)
    end subroutine build_minimal_ttf

    ! Assemble an SFNT container from 8 tables.
    subroutine write_sfnt_8(path, ver, tags, d1, d2, d3, d4, d5, d6, d7, d8)
        character(len=*), intent(in) :: path
        integer(int64), intent(in) :: ver
        character(len=4), intent(in) :: tags(8)
        character(len=*), intent(in) :: d1, d2, d3, d4, d5, d6, d7, d8
        character(len=:), allocatable :: out
        integer :: n, i, off, pad, lens(8)
        type(status_t) :: st

        lens = [len(d1), len(d2), len(d3), len(d4), len(d5), len(d6), len(d7), len(d8)]
        n = 0
        call push_u32(out, n, ver)
        call push_u16(out, n, 8)
        call push_u16(out, n, 128)
        call push_u16(out, n, 3)
        call push_u16(out, n, 0)

        off = 12 + 16*8
        do i = 1, 8
            call push_str(out, n, tags(i))
            call push_u32(out, n, 0_int64)
            call push_u32(out, n, int(off, int64))
            call push_u32(out, n, int(lens(i), int64))
            pad = mod(4 - mod(lens(i), 4), 4)
            off = off + lens(i) + pad
        end do

        call append_padded(out, n, d1)
        call append_padded(out, n, d2)
        call append_padded(out, n, d3)
        call append_padded(out, n, d4)
        call append_padded(out, n, d5)
        call append_padded(out, n, d6)
        call append_padded(out, n, d7)
        call append_padded(out, n, d8)

        call write_bytes(path, out(1:n), st)
        if (.not. st%ok()) error stop "write_sfnt_8: failed to write "//trim(path)
    end subroutine write_sfnt_8

    subroutine append_padded(out, n, d)
        character(len=:), allocatable, intent(inout) :: out
        integer, intent(inout) :: n
        character(len=*), intent(in) :: d
        integer :: pad
        call push_str(out, n, d)
        pad = mod(4 - mod(len(d), 4), 4)
        do while (pad > 0)
            call push_u8(out, n, 0)
            pad = pad - 1
        end do
    end subroutine append_padded

    ! Build a minimal valid OpenType CFF (.otf) font with a MATH table:
    !   gid 0 (.notdef): empty
    !   gid 1 (' ' U+0020): empty, adv=300
    !   gid 2 ('X' U+0058): CFF cubic contour (rrcurveto + rlineto + endchar), adv=700
    !   MATH table: ScriptPercentScaleDown=72, AxisHeight=310, FractionRuleThickness=55
    subroutine build_minimal_otf(path)
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: b, out
        character(len=:), allocatable :: t_cff, t_math, t_cmap, t_head, t_hhea, t_hmtx, t_maxp
        character(len=4) :: tags(7)
        integer :: n, i, off, pad, lens(7), cs_off
        type(status_t) :: st

        ! 1. head (54 bytes, unitsPerEm=1000)
        n = 0
        call push_u32(b, n, 65536_int64)
        call push_u32(b, n, 65536_int64)
        call push_u32(b, n, 0_int64)
        call push_u32(b, n, 1594834165_int64)
        call push_u16(b, n, 0)
        call push_u16(b, n, 1000)
        do i = 1, 4
            call push_u32(b, n, 0_int64)
        end do
        call push_u16(b, n, 0); call push_u16(b, n, -200)
        call push_u16(b, n, 700); call push_u16(b, n, 800)
        do i = 1, 5
            call push_u16(b, n, 0)
        end do
        t_head = b(1:n)

        ! 2. hhea (36 bytes, numberOfHMetrics=3)
        n = 0
        call push_u32(b, n, 65536_int64)
        call push_u16(b, n, 800); call push_u16(b, n, -200)
        call push_u16(b, n, 0); call push_u16(b, n, 700)
        do i = 1, 11
            call push_u16(b, n, 0)
        end do
        call push_u16(b, n, 3)
        t_hhea = b(1:n)

        ! 3. maxp (6 bytes, CFF version 0.5 = 0x00005000, numGlyphs=3)
        n = 0
        call push_u32(b, n, 20480_int64)
        call push_u16(b, n, 3)
        t_maxp = b(1:n)

        ! 4. hmtx (3 * 4 bytes)
        n = 0
        call push_u16(b, n, 500); call push_u16(b, n, 0)
        call push_u16(b, n, 300); call push_u16(b, n, 0)
        call push_u16(b, n, 700); call push_u16(b, n, 0)
        t_hmtx = b(1:n)

        ! 5. cmap (Format 12: ' '->1, 'X'->2)
        n = 0
        call push_u16(b, n, 0)             ! version
        call push_u16(b, n, 1)             ! numTables
        call push_u16(b, n, 3)             ! Windows
        call push_u16(b, n, 10)            ! Unicode full
        call push_u32(b, n, 12_int64)      ! subtable offset
        call push_u16(b, n, 12)            ! format 12
        call push_u16(b, n, 0)             ! reserved
        call push_u32(b, n, 40_int64)      ! length = 16 + 2*12
        call push_u32(b, n, 0_int64)       ! language
        call push_u32(b, n, 2_int64)       ! numGroups = 2
        call push_u32(b, n, 32_int64); call push_u32(b, n, 32_int64); call push_u32(b, n, 1_int64)
        call push_u32(b, n, 88_int64); call push_u32(b, n, 88_int64); call push_u32(b, n, 2_int64)
        t_cmap = b(1:n)

        ! 6. CFF 1.0 table:
        ! Header (4 bytes): major=1, minor=0, hdrSize=4, offSize=1
        ! Name INDEX (7 bytes): count=1, offSize=1, off=[1,3], "T1"
        ! Top DICT INDEX (9 bytes): count=1, offSize=1, off=[1,5], dict=[28, hi, lo, 17]
        ! String INDEX (2 bytes): count=0
        ! Global Subr INDEX (2 bytes): count=0
        ! => CharStrings INDEX starts at cs_off = 4 + 7 + 9 + 2 + 2 = 24!
        cs_off = 24
        n = 0
        call push_u8(b, n, 1); call push_u8(b, n, 0)
        call push_u8(b, n, 4); call push_u8(b, n, 1)
        ! Name INDEX
        call push_u16(b, n, 1); call push_u8(b, n, 1)
        call push_u8(b, n, 1); call push_u8(b, n, 3); call push_str(b, n, "T1")
        ! Top DICT INDEX (4 bytes: 28, cs_off_hi, cs_off_lo, 17)
        call push_u16(b, n, 1); call push_u8(b, n, 1)
        call push_u8(b, n, 1); call push_u8(b, n, 5)
        call push_u8(b, n, 28); call push_u16(b, n, cs_off); call push_u8(b, n, 17)
        ! String INDEX (empty) & Global Subr INDEX (empty)
        call push_u16(b, n, 0)
        call push_u16(b, n, 0)
        ! CharStrings INDEX (3 glyphs):
        !   cs0 (.notdef): [14] (1 byte)
        !   cs1 (' '):     [14] (1 byte)
        !   cs2 ('X'):     rmoveto(100,0), rrcurveto(100,300, 100,300, 100,0),
        !                  rlineto(-100,-600), endchar
        !     100 -> 239 (1 byte), 0 -> 139 (1 byte), rmoveto=21 => 3 bytes
        !     rrcurveto: 100(239), 300(247,192), 100(239), 300(247,192),
        !                100(239), 0(139), op=8 => 9 bytes
        !     rlineto: -100(39), -600(252,236), op=5 => 4 bytes
        !     endchar: 14 => 1 byte
        !     total cs2 = 17 bytes -> offsets = [1, 2, 3, 20]
        call push_u16(b, n, 3); call push_u8(b, n, 1)
        call push_u8(b, n, 1); call push_u8(b, n, 2)
        call push_u8(b, n, 3); call push_u8(b, n, 20)
        call push_u8(b, n, 14)             ! cs0
        call push_u8(b, n, 14)             ! cs1
        ! cs2:
        call push_u8(b, n, 239); call push_u8(b, n, 139); call push_u8(b, n, 21)
        call push_u8(b, n, 239)
        call push_u8(b, n, 247); call push_u8(b, n, 192)
        call push_u8(b, n, 239)
        call push_u8(b, n, 247); call push_u8(b, n, 192)
        call push_u8(b, n, 239); call push_u8(b, n, 139); call push_u8(b, n, 8)
        call push_u8(b, n, 39)
        call push_u8(b, n, 252); call push_u8(b, n, 236); call push_u8(b, n, 5)
        call push_u8(b, n, 14)
        t_cff = b(1:n)

        ! 7. MATH table (header 10 bytes + MathConstants 214 bytes = 224 bytes)
        n = 0
        call push_u16(b, n, 1); call push_u16(b, n, 0) ! version 1.0
        call push_u16(b, n, 10)            ! mathConstantsOffset = 10
        call push_u16(b, n, 0)             ! mathGlyphInfoOffset = 0
        call push_u16(b, n, 0)             ! mathVariantsOffset = 0
        ! MathConstants:
        call push_u16(b, n, 72)            ! 1: ScriptPercentScaleDown = 72
        call push_u16(b, n, 56)            ! 2: ScriptScriptPercentScaleDown = 56
        call push_u16(b, n, 1400)          ! 3: DelimitedSubFormulaMinHeight
        call push_u16(b, n, 1400)          ! 4: DisplayOperatorMinHeight
        do i = 5, 55
            if (i == MC_AXIS_HEIGHT) then
                call push_u16(b, n, 310); call push_u16(b, n, 0)
            else if (i == MC_FRACTION_RULE_THICKNESS) then
                call push_u16(b, n, 55); call push_u16(b, n, 0)
            else
                call push_u16(b, n, 150); call push_u16(b, n, 0)
            end if
        end do
        call push_u16(b, n, 60)            ! 56: RadicalDegreeBottomRaisePercent
        t_math = b(1:n)

        ! Write OTF ('OTTO' = 0x4F54544F = 1330926671)
        tags = ["CFF ", "MATH", "cmap", "head", "hhea", "hmtx", "maxp"]
        lens = [len(t_cff), len(t_math), len(t_cmap), len(t_head), &
                len(t_hhea), len(t_hmtx), len(t_maxp)]
        n = 0
        call push_u32(out, n, 1330926671_int64)
        call push_u16(out, n, 7)
        call push_u16(out, n, 64)
        call push_u16(out, n, 2)
        call push_u16(out, n, 48)
        off = 12 + 16*7
        do i = 1, 7
            call push_str(out, n, tags(i))
            call push_u32(out, n, 0_int64)
            call push_u32(out, n, int(off, int64))
            call push_u32(out, n, int(lens(i), int64))
            pad = mod(4 - mod(lens(i), 4), 4)
            off = off + lens(i) + pad
        end do
        call append_padded(out, n, t_cff)
        call append_padded(out, n, t_math)
        call append_padded(out, n, t_cmap)
        call append_padded(out, n, t_head)
        call append_padded(out, n, t_hhea)
        call append_padded(out, n, t_hmtx)
        call append_padded(out, n, t_maxp)
        call write_bytes(path, out(1:n), st)
        if (.not. st%ok()) error stop "build_minimal_otf: failed to write "//trim(path)
    end subroutine build_minimal_otf

    subroutine test_minimal_ttf()
        character(len=*), parameter :: path = "tests/out/minimal_test.ttf"
        real(dp) :: x(5), y(5), x0, y0, x1, y1, k
        character(len=:), allocatable :: svg0, png0, pdf0, eps0
        character(len=:), allocatable :: svg1, png1, pdf1, eps1
        character(len=:), allocatable :: svg2, png2, pdf2, eps2
        integer, allocatable :: v(:)
        real(dp), allocatable :: gx(:), gy(:)
        integer :: gA, gV, gB, nv, np
        type(status_t) :: st

        call build_minimal_ttf(path)
        x = [0.0_dp, 1.0_dp, 2.0_dp, 3.0_dp, 4.0_dp]
        y = [0.0_dp, 1.0_dp, 0.5_dp, 1.5_dp, 1.0_dp]

        ! Baseline rendering with built-in fonts
        call reset_fonts()
        call figure()
        call plot(x, y)
        call title("AV B")
        call xlabel("A")
        call ylabel("V")
        svg0 = render_svg()
        png0 = render_png()
        pdf0 = render_pdf()
        eps0 = render_eps()
        call close()

        ! Load minimal TTF into regular face
        call load_font(path, face="regular", status=st)
        if (.not. st%ok()) error stop "test_minimal_ttf: load_font failed: "//trim(st%message)
        if (glyph_count() /= NGLYPH + 5) error stop "test_minimal_ttf: unexpected glyph_count"

        gA = glyph_cmap(FACE_REGULAR, iachar("A"))
        gV = glyph_cmap(FACE_REGULAR, iachar("V"))
        gB = glyph_cmap(FACE_REGULAR, iachar("B"))
        if (gA <= NGLYPH .or. gV <= NGLYPH .or. gB <= NGLYPH) &
            error stop "test_minimal_ttf: expected external gids"
        if (glyph_char(gA) /= iachar("A")) error stop "test_minimal_ttf: glyph_char mismatch"
        if (abs(glyph_adv(gA) - 0.8_dp) > 1.0e-9_dp) error stop "test_minimal_ttf: adv(A)"
        if (abs(glyph_adv(gV) - 0.75_dp) > 1.0e-9_dp) error stop "test_minimal_ttf: adv(V)"
        if (abs(glyph_adv(gB) - 0.9_dp) > 1.0e-9_dp) error stop "test_minimal_ttf: adv(B)"
        if (abs(face_ascent(FACE_REGULAR) - 0.8_dp) > 1.0e-9_dp) &
            error stop "test_minimal_ttf: face_ascent"
        if (abs(face_descent(FACE_REGULAR) - (-0.2_dp)) > 1.0e-9_dp) &
            error stop "test_minimal_ttf: face_descent"

        k = glyph_kern(FACE_REGULAR, gA, gV)
        if (abs(k - (-0.12_dp)) > 1.0e-9_dp) error stop "test_minimal_ttf: kern(A,V)"

        call glyph_bbox(gA, x0, y0, x1, y1)
        if (abs(x1 - 0.7_dp) > 1.0e-9_dp .or. abs(y1 - 0.7_dp) > 1.0e-9_dp) &
            error stop "test_minimal_ttf: bbox(A)"

        ! Simple glyph with quadratic Bezier -> elevated to VERB_CUBIC
        call glyph_outline(gA, v, nv, gx, gy, np)
        if (nv < 3 .or. .not. any(v(1:nv) == VERB_CUBIC)) &
            error stop "test_minimal_ttf: expected cubic from quad elevation"

        ! Composite glyph 'B' = 0.5*'A' + (50, 0)
        call glyph_outline(gB, v, nv, gx, gy, np)
        if (nv < 3 .or. np < 4) error stop "test_minimal_ttf: composite outline empty"
        if (abs(gx(1) - 0.05_dp) > 1.0e-9_dp) error stop "test_minimal_ttf: composite shift"

        ! Render with external font across ALL 4 backends
        call figure()
        call plot(x, y)
        call title("AV B")
        call xlabel("A")
        call ylabel("V")
        svg1 = render_svg()
        png1 = render_png()
        pdf1 = render_pdf()
        eps1 = render_eps()
        call close()

        if (index(svg1, "</svg>") == 0) error stop "test_minimal_ttf: invalid SVG"
        if (len(png1) < 100) error stop "test_minimal_ttf: invalid PNG"
        if (index(pdf1, "%PDF-") /= 1) error stop "test_minimal_ttf: invalid PDF"
        if (index(eps1, "%!PS-Adobe-") /= 1) error stop "test_minimal_ttf: invalid EPS"
        if (svg1 == svg0) error stop "test_minimal_ttf: SVG did not change with external font"
        if (png1 == png0) error stop "test_minimal_ttf: PNG did not change with external font"
        if (pdf1 == pdf0) error stop "test_minimal_ttf: PDF did not change with external font"
        if (eps1 == eps0) error stop "test_minimal_ttf: EPS did not change with external font"

        ! Load into "text" and "all"
        call load_font(path, face="text", status=st)
        if (.not. st%ok()) error stop "test_minimal_ttf: load_font(text) failed"
        if (glyph_cmap(FACE_BOLD, iachar("A")) <= NGLYPH) &
            error stop "test_minimal_ttf: bold face not loaded"
        if (glyph_cmap(FACE_ITALIC, iachar("A")) <= NGLYPH) &
            error stop "test_minimal_ttf: italic face not loaded"

        ! Reset fonts and verify exact byte-for-byte restoration
        call reset_fonts()
        if (glyph_count() /= NGLYPH) error stop "test_minimal_ttf: reset_fonts count"
        call figure()
        call plot(x, y)
        call title("AV B")
        call xlabel("A")
        call ylabel("V")
        svg2 = render_svg()
        png2 = render_png()
        pdf2 = render_pdf()
        eps2 = render_eps()
        call close()

        if (svg2 /= svg0) error stop "test_minimal_ttf: SVG not restored by reset_fonts"
        if (png2 /= png0) error stop "test_minimal_ttf: PNG not restored by reset_fonts"
        if (pdf2 /= pdf0) error stop "test_minimal_ttf: PDF not restored by reset_fonts"
        if (eps2 /= eps0) error stop "test_minimal_ttf: EPS not restored by reset_fonts"
    end subroutine test_minimal_ttf

    subroutine test_minimal_otf_math()
        character(len=*), parameter :: path = "tests/out/minimal_test.otf"
        real(dp) :: x(3), y(3), base_axis
        character(len=:), allocatable :: svg1, png1, pdf1, eps1
        integer, allocatable :: v(:)
        real(dp), allocatable :: gx(:), gy(:)
        integer :: gid_x, nv, np
        type(status_t) :: st

        call build_minimal_otf(path)
        base_axis = math_const(MC_AXIS_HEIGHT)

        call load_font(path, face="math", status=st)
        if (.not. st%ok()) error stop "test_minimal_otf: load_font failed: "//trim(st%message)

        gid_x = glyph_cmap(FACE_MATH, iachar("X"))
        if (gid_x <= NGLYPH) error stop "test_minimal_otf: expected external math gid"
        if (abs(glyph_adv(gid_x) - 0.7_dp) > 1.0e-9_dp) error stop "test_minimal_otf: adv(X)"
        if (abs(math_const(MC_AXIS_HEIGHT) - 0.31_dp) > 1.0e-9_dp) &
            error stop "test_minimal_otf: MATH AxisHeight mismatch"
        if (abs(math_const(MC_FRACTION_RULE_THICKNESS) - 0.055_dp) > 1.0e-9_dp) &
            error stop "test_minimal_otf: MATH FractionRuleThickness mismatch"
        if (abs(math_percent(MC_SCRIPT_PERCENT_SCALE_DOWN) - 72.0_dp) > 1.0e-9_dp) &
            error stop "test_minimal_otf: MATH ScriptPercentScaleDown mismatch"

        call glyph_outline(gid_x, v, nv, gx, gy, np)
        if (nv < 3 .or. .not. any(v(1:nv) == VERB_CUBIC)) &
            error stop "test_minimal_otf: expected CFF cubic outline"

        x = [0.0_dp, 1.0_dp, 2.0_dp]
        y = [0.0_dp, 1.0_dp, 0.5_dp]
        call figure()
        call plot(x, y)
        call title("$\frac{X}{X}$")
        svg1 = render_svg()
        png1 = render_png()
        pdf1 = render_pdf()
        eps1 = render_eps()
        call close()
        if (index(svg1, "</svg>") == 0) error stop "test_minimal_otf: invalid SVG"
        if (len(png1) < 100) error stop "test_minimal_otf: invalid PNG"
        if (index(pdf1, "%PDF-") /= 1) error stop "test_minimal_otf: invalid PDF"
        if (index(eps1, "%!PS-Adobe-") /= 1) error stop "test_minimal_otf: invalid EPS"

        call reset_fonts()
        if (abs(math_const(MC_AXIS_HEIGHT) - base_axis) > 1.0e-9_dp) &
            error stop "test_minimal_otf: MATH constant not restored by reset_fonts"
    end subroutine test_minimal_otf_math

    subroutine test_error_handling()
        type(status_t) :: st
        integer :: cnt_before

        cnt_before = glyph_count()
        call load_font("tests/out/does_not_exist_12345.ttf", status=st)
        if (st%ok()) error stop "test_error_handling: expected error for missing file"
        if (glyph_count() /= cnt_before) &
            error stop "test_error_handling: glyph_count modified on failure"

        ! Invalid SFNT magic
        call write_bytes("tests/out/bad_font.ttf", "NOT_A_FONT_FILE_AT_ALL", st)
        call load_font("tests/out/bad_font.ttf", status=st)
        if (st%ok()) error stop "test_error_handling: expected error for invalid font"
    end subroutine test_error_handling

    subroutine test_real_fonts_if_present()
        character(len=512) :: home, p_ttf, p_otf
        integer :: lhome, stat
        logical :: ex_ttf, ex_otf
        type(status_t) :: st
        real(dp) :: x(3), y(3)
        character(len=:), allocatable :: svg_s, pdf_s, png_s, eps_s

        call get_environment_variable("HOME", home, length=lhome, status=stat)
        if (stat /= 0 .or. lhome <= 0) return
        p_ttf = home(1:lhome)//"/.cache/fplotlib/fonts/Lato-Regular.ttf"
        p_otf = home(1:lhome)//"/.cache/fplotlib/fonts/LeteSansMath.otf"
        inquire (file=trim(p_ttf), exist=ex_ttf)
        inquire (file=trim(p_otf), exist=ex_otf)
        if (.not. ex_ttf .and. .not. ex_otf) return

        x = [0.0_dp, 1.0_dp, 2.0_dp]
        y = [0.0_dp, 1.0_dp, 0.5_dp]
        if (ex_ttf) then
            call load_font(trim(p_ttf), face="text", status=st)
            if (.not. st%ok()) error stop "real TTF load failed: "//trim(st%message)
        end if
        if (ex_otf) then
            call load_font(trim(p_otf), face="math", status=st)
            if (.not. st%ok()) error stop "real OTF load failed: "//trim(st%message)
        end if

        call figure()
        call plot(x, y)
        call title("External TTF/OTF: $\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$")
        svg_s = render_svg()
        png_s = render_png()
        pdf_s = render_pdf()
        eps_s = render_eps()
        call close()
        if (index(svg_s, "</svg>") == 0) error stop "real fonts: invalid SVG"
        if (len(png_s) < 100) error stop "real fonts: invalid PNG"
        if (index(pdf_s, "%PDF-") /= 1) error stop "real fonts: invalid PDF"
        if (index(eps_s, "%!PS-Adobe-") /= 1) error stop "real fonts: invalid EPS"
        call reset_fonts()
    end subroutine test_real_fonts_if_present

end program test_external_font
