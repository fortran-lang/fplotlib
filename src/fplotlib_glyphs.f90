! fplotlib_glyphs -- the glyphs every backend draws text with.
!
! The outlines, metrics and kerning of the fonts are compiled in, packed
! into one base85 string in fplotlib_glyphs_data (written by
! tools/gen_glyphs.py) and unpacked here the first time anything is asked
! for. Text is Lato, in three faces: regular, bold and italic; math is
! Lete Sans Math, the fourth face, whose MATH table comes with it.
!
! Glyphs are numbered: a glyph id (gid) runs over all the faces, one after
! another, and a face's cmap takes a code point to one of its gids. A
! glyph need not have a code point -- the pieces composite glyphs are
! built from have none -- so everything below the cmap speaks gids.
!
! The bit stream, most significant bit first. A delta is a signed number
! folded to a non-negative one, small magnitudes staying small, and then
! written as the position of its leading one -- a magnitude class, spelled
! with the canonical prefix code whose lengths are CLEN -- followed by the
! bits below that one. This is what deflate does with distances. gamma is
! Elias gamma: the length in zeros, then the number with its leading one.
! For each face in turn:
!
!   * every glyph: its advance width, as a delta from a guess (the glyph
!     at the same position in the face FACE_PRED names, which is the same
!     letter in another weight or slant, or else the glyph before); one
!     bit saying whether it is composite; then either the number of
!     components, gamma coded, and for each the face-local index of the
!     glyph it places (in as many raw bits as the face's glyph count
!     needs) and its offset as two deltas, or the number of contours plus
!     one, each contour's number of points, and for every point one bit
!     saying whether it lies on the curve and its x and y as deltas from
!     the point before it (the first is a delta from the origin); and one
!     bit saying whether it has ink, followed if it has by its ink box as
!     deltas: x0, y0, x1 less the advance, y1;
!   * the cmap: the number of entries plus one, then per entry in code
!     point order the step from the previous code point, gamma coded, and
!     one bit when its glyph is the one after the previous entry's, else
!     that bit and the glyph's face-local index in raw bits;
!   * the pair kerning: the numbers of left and right classes plus one,
!     each glyph's left and right class in raw bits, then per left class
!     its non-zero cells plus one, gamma coded, and per cell the step to
!     its right class, gamma coded, and the adjustment as a delta;
!   * for the math face (FACE_HAS_MATH), its MATH table: per glyph a bit
!     and a delta for an italic correction, a bit and a delta from half
!     the advance for a top accent attachment, a bit for an extended
!     shape and a bit for math kerns, followed by the four corners (top
!     right, top left, bottom right, bottom left), each its number of
!     heights plus one and the heights and kerns as running deltas; then
!     the vertical and the horizontal constructions, each a count plus one
!     and per glyph its index, its variants (count plus one, then glyph and
!     advance as a running delta) and a bit for an assembly, followed by
!     its italic correction and parts (count, then glyph, start and end
!     connector lengths, full advance and an extender bit); then the
!     script-size alternates as pairs of indices (the glyph and the one
!     both script styles use), and the dotless forms as pairs.
!
! A face is TrueType (quadratic) or CFF (cubic), FACE_CUBIC says which.
! A quadratic contour may start anywhere and may leave an on-curve point
! implied midway between two control points; a cubic contour starts on
! the curve and has its control points in pairs. Either way the path
! handed out is in the cubics fplotlib_render speaks, so a backend fills a
! glyph with exactly the code that fills any other path: a quadratic is
! elevated exactly, its control points landing at p0 + 2/3 (q - p0) and
! p2 + 2/3 (q - p2).
!
! The gid functions measure in ems: an advance of 0.5 is half the font
! size. glyph_advance, glyph_verbs and glyph_points are the older
! code point interface, in the font units of the text faces (EM per em).
module fplotlib_glyphs
    use iso_fortran_env, only: int16, int64
    use fplotlib_style, only: dp
    use fplotlib_render, only: VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_CLOSE
    use fplotlib_glyphs_data, only: NFACE, NGLYPH, NCONT, NPT, NCOMP, NCMAP, &
                                 NKERN, FACE_NG, FACE_EM, FACE_ASC, FACE_DESC, &
                                 FACE_XH, FACE_CAP, FACE_CUBIC, FACE_PRED, &
                                 NCLASS, CLEN, NRECOMP, RECOMP_BASE, &
                                 RECOMP_MARK, RECOMP_CHAR, ALPHABET, &
                                 BLOB_ROWS, BLOB_LEN, FACE_HAS_MATH, NVAR, NASM, &
                                 NPART, NMKH, NMKV, MATH_CONSTANT
    implicit none
    private

    public :: NFACE, NGLYPH
    public :: FACE_REGULAR, FACE_BOLD, FACE_ITALIC, FACE_MATH
    public :: math_const, math_percent, glyph_italic, glyph_top_accent, &
              glyph_math_kern, glyph_extended, glyph_variants, glyph_assembly, &
              glyph_ssty, glyph_dotless
    public :: FACE_OBLIQUE
    public :: glyph_cmap, glyph_face, glyph_adv, glyph_bbox, glyph_outline, &
              glyph_kern, glyph_char, glyph_recompose, glyph_inked
    public :: face_ascent, face_descent, face_xheight, face_capheight
    public :: EM, ASCENT, DESCENT, XHEIGHT
    public :: glyph_advance, glyph_verbs, glyph_points

    integer, parameter :: FACE_REGULAR = 1
    integer, parameter :: FACE_BOLD = 2
    integer, parameter :: FACE_ITALIC = 3
    ! Lete Sans Math, the face with the MATH table.
    integer, parameter :: FACE_MATH = 4
    ! The name the italic face had when it was an oblique.
    integer, parameter :: FACE_OBLIQUE = FACE_ITALIC

    ! The text faces' metrics in their own font units, for the code point
    ! interface.
    real(dp), parameter :: EM = real(FACE_EM(1), dp)
    real(dp), parameter :: ASCENT = real(FACE_ASC(1), dp)
    real(dp), parameter :: DESCENT = real(FACE_DESC(1), dp)
    real(dp), parameter :: XHEIGHT = real(FACE_XH(1), dp)

    ! The longest code a magnitude class can have.
    integer, parameter :: MAXLEN = 15

    ! The unpacked tables. Module variables are saved, so the work is done
    ! once however many figures are drawn.
    logical :: loaded = .false.
    integer :: FBASE(NFACE + 1)             ! gid before each face's first
    integer :: GADV(NGLYPH)                 ! advance width, font units
    integer :: GBOX(4, NGLYPH)              ! ink box x0, y0, x1, y1
    integer :: GFACE(NGLYPH)                ! the face a glyph belongs to
    integer :: GCHAR(NGLYPH)                ! lowest code point mapped to it
    integer :: OBEG(NGLYPH + 1)             ! first contour of each glyph
    integer :: CBEG(NCONT + 1)              ! first point of each contour
    integer(int16) :: QX(NPT), QY(NPT)      ! points, in font units
    logical :: QON(NPT)                     ! on the curve, or a control point
    integer :: PBEG(NGLYPH + 1)             ! first component of each glyph
    integer :: PG(NCOMP), PDX(NCOMP), PDY(NCOMP)
    integer :: CMB(NFACE + 1)               ! first cmap entry of each face
    integer :: CMCP(NCMAP), CMG(NCMAP)      ! code point, gid
    integer :: KLC(NGLYPH), KRC(NGLYPH)     ! left and right kerning class
    integer :: KNR(NFACE), KOFF(NFACE)      ! right classes, matrix offset
    integer(int16) :: KVAL(NKERN)           ! the class matrices, font units

    ! The MATH table, by gid. A glyph outside the math face has none of it.
    integer :: GITAL(NGLYPH), GACC(NGLYPH)  ! italic correction, top accent x
    logical :: GEXT(NGLYPH)                 ! extended shape
    ! Math kerns: for each corner the first height in MKH and the first
    ! value in MKV, and the number of heights, -1 for no kern at all.
    integer :: MKH0(4, NGLYPH), MKV0(4, NGLYPH), MKN(4, NGLYPH)
    integer :: MKH(max(NMKH, 1)), MKV(max(NMKV, 1))
    ! Constructions, vertical (1) and horizontal (2): the first variant and
    ! how many, and the assembly, 0 for none.
    integer :: CV0(2, NGLYPH), CVN(2, NGLYPH), CASM(2, NGLYPH)
    integer :: VARG(max(NVAR, 1)), VARA(max(NVAR, 1))
    integer :: ASMI(max(NASM, 1)), ASMP0(max(NASM, 1)), ASMN(max(NASM, 1))
    integer :: PARTG(max(NPART, 1)), PARTST(max(NPART, 1)), PARTEN(max(NPART, 1))
    integer :: PARTF(max(NPART, 1))
    logical :: PARTX(max(NPART, 1))
    ! Script and scriptscript alternates, and dotless forms; 0 for none.
    integer :: SSTY(2, NGLYPH), DTLS(NGLYPH)

    ! The canonical prefix code for the magnitude classes, built from
    ! CLEN: how many codes have each length, the smallest of them, and the
    ! symbols in the order the codes run.
    integer :: NLEN(MAXLEN), FIRST(MAXLEN), CBASE(MAXLEN), CSYM(NCLASS)

    ! The bit stream while it is being read, and how far into the MATH
    ! arrays it has got.
    integer, allocatable :: BUF(:)
    integer :: BPOS
    integer :: nmkh_, nmkv_, nvar_, nasm_, npart_

contains

    ! --- the gid interface -------------------------------------------

    ! The glyph a face draws a code point with, 0 when it has none.
    function glyph_cmap(face, cp) result(gid)
        integer, intent(in) :: face, cp
        integer :: gid, lo, hi, mid
        call ensure_loaded()
        gid = 0
        if (face < 1 .or. face > NFACE) return
        lo = CMB(face)
        hi = CMB(face + 1) - 1
        do while (lo <= hi)
            mid = (lo + hi)/2
            if (CMCP(mid) == cp) then
                gid = CMG(mid)
                return
            else if (CMCP(mid) < cp) then
                lo = mid + 1
            else
                hi = mid - 1
            end if
        end do
    end function glyph_cmap

    integer function glyph_face(gid)
        integer, intent(in) :: gid
        call ensure_loaded()
        glyph_face = 0
        if (gid >= 1 .and. gid <= NGLYPH) glyph_face = GFACE(gid)
    end function glyph_face

    ! Advance width in ems.
    function glyph_adv(gid) result(a)
        integer, intent(in) :: gid
        real(dp) :: a
        call ensure_loaded()
        a = 0.0_dp
        if (gid < 1 .or. gid > NGLYPH) return
        a = real(GADV(gid), dp)/real(FACE_EM(GFACE(gid)), dp)
    end function glyph_adv

    ! The ink box in ems, y up from the baseline; all zero for a glyph
    ! that draws nothing.
    subroutine glyph_bbox(gid, x0, y0, x1, y1)
        integer, intent(in) :: gid
        real(dp), intent(out) :: x0, y0, x1, y1
        real(dp) :: s
        call ensure_loaded()
        x0 = 0.0_dp
        y0 = 0.0_dp
        x1 = 0.0_dp
        y1 = 0.0_dp
        if (gid < 1 .or. gid > NGLYPH) return
        s = 1.0_dp/real(FACE_EM(GFACE(gid)), dp)
        x0 = GBOX(1, gid)*s
        y0 = GBOX(2, gid)*s
        x1 = GBOX(3, gid)*s
        y1 = GBOX(4, gid)*s
    end subroutine glyph_bbox

    ! The outline in ems, y up, as verbs and points: one point per move
    ! and line, three per cubic.
    subroutine glyph_outline(gid, v, nv, x, y, np)
        integer, intent(in) :: gid
        integer, allocatable, intent(out) :: v(:)
        integer, intent(out) :: nv
        real(dp), allocatable, intent(out) :: x(:), y(:)
        integer, intent(out) :: np
        call ensure_loaded()
        if (gid < 1 .or. gid > NGLYPH) then
            nv = 0
            np = 0
            allocate (v(0), x(0), y(0))
            return
        end if
        call outline_of(gid, 1.0_dp/real(FACE_EM(GFACE(gid)), dp), v, nv, x, y, np)
    end subroutine glyph_outline

    ! Whether a glyph draws anything at all; a space does not.
    logical function glyph_inked(gid)
        integer, intent(in) :: gid
        call ensure_loaded()
        glyph_inked = .false.
        if (gid < 1 .or. gid > NGLYPH) return
        glyph_inked = OBEG(gid + 1) > OBEG(gid) .or. PBEG(gid + 1) > PBEG(gid)
    end function glyph_inked

    ! The pair kerning between two glyphs of a face, in ems.
    function glyph_kern(face, g1, g2) result(k)
        integer, intent(in) :: face, g1, g2
        real(dp) :: k
        integer :: l, r
        call ensure_loaded()
        k = 0.0_dp
        if (face < 1 .or. face > NFACE) return
        if (g1 < 1 .or. g1 > NGLYPH .or. g2 < 1 .or. g2 > NGLYPH) return
        if (GFACE(g1) /= face .or. GFACE(g2) /= face) return
        l = KLC(g1)
        r = KRC(g2)
        if (l == 0 .or. r == 0) return
        k = real(KVAL(KOFF(face) + l*(KNR(face) + 1) + r + 1), dp) &
            /real(FACE_EM(face), dp)
    end function glyph_kern

    ! The code point a glyph stands for, 0 for one that has none.
    integer function glyph_char(gid)
        integer, intent(in) :: gid
        call ensure_loaded()
        glyph_char = 0
        if (gid >= 1 .and. gid <= NGLYPH) glyph_char = GCHAR(gid)
    end function glyph_char

    ! The character a base and one combining mark compose to, 0 if none.
    pure integer function glyph_recompose(base, mark) result(c)
        integer, intent(in) :: base, mark
        integer :: i
        c = 0
        do i = 1, NRECOMP
            if (RECOMP_BASE(i) == base .and. RECOMP_MARK(i) == mark) then
                c = RECOMP_CHAR(i)
                return
            end if
        end do
    end function glyph_recompose

    ! A face's ascender, descender (negative), x-height and cap height,
    ! in ems.
    pure real(dp) function face_ascent(face)
        integer, intent(in) :: face
        face_ascent = real(FACE_ASC(face), dp)/real(FACE_EM(face), dp)
    end function face_ascent

    pure real(dp) function face_descent(face)
        integer, intent(in) :: face
        face_descent = real(FACE_DESC(face), dp)/real(FACE_EM(face), dp)
    end function face_descent

    pure real(dp) function face_xheight(face)
        integer, intent(in) :: face
        face_xheight = real(FACE_XH(face), dp)/real(FACE_EM(face), dp)
    end function face_xheight

    pure real(dp) function face_capheight(face)
        integer, intent(in) :: face
        face_capheight = real(FACE_CAP(face), dp)/real(FACE_EM(face), dp)
    end function face_capheight

    ! --- the MATH table ----------------------------------------------

    ! A MATH constant in ems. The three that are percentages are read with
    ! math_percent instead.
    pure real(dp) function math_const(i)
        integer, intent(in) :: i
        math_const = real(MATH_CONSTANT(i), dp)/real(FACE_EM(FACE_MATH), dp)
    end function math_const

    pure real(dp) function math_percent(i)
        integer, intent(in) :: i
        math_percent = real(MATH_CONSTANT(i), dp)
    end function math_percent

    ! The italic correction of a glyph, in ems.
    function glyph_italic(gid) result(v)
        integer, intent(in) :: gid
        real(dp) :: v
        call ensure_loaded()
        v = 0.0_dp
        if (gid < 1 .or. gid > NGLYPH) return
        v = real(GITAL(gid), dp)/real(FACE_EM(GFACE(gid)), dp)
    end function glyph_italic

    ! Where an accent over a glyph is centred, in ems from its origin: the
    ! MATH table's attachment point, or half the advance without one.
    function glyph_top_accent(gid) result(v)
        integer, intent(in) :: gid
        real(dp) :: v
        call ensure_loaded()
        v = 0.0_dp
        if (gid < 1 .or. gid > NGLYPH) return
        if (FACE_HAS_MATH(GFACE(gid))) then
            v = real(GACC(gid), dp)/real(FACE_EM(GFACE(gid)), dp)
        else
            v = 0.5_dp*glyph_adv(gid)
        end if
    end function glyph_top_accent

    ! The math kern at a corner of a glyph (1 top right, 2 top left, 3
    ! bottom right, 4 bottom left) for a height in ems: the step of the
    ! staircase that height falls on.
    function glyph_math_kern(gid, corner, height) result(v)
        integer, intent(in) :: gid, corner
        real(dp), intent(in) :: height
        real(dp) :: v, em
        integer :: n, i
        call ensure_loaded()
        v = 0.0_dp
        if (gid < 1 .or. gid > NGLYPH) return
        n = MKN(corner, gid)
        if (n < 0) return
        em = real(FACE_EM(GFACE(gid)), dp)
        i = 0
        do while (i < n)
            if (height*em < real(MKH(MKH0(corner, gid) + i), dp)) exit
            i = i + 1
        end do
        v = real(MKV(MKV0(corner, gid) + i), dp)/em
    end function glyph_math_kern

    logical function glyph_extended(gid)
        integer, intent(in) :: gid
        call ensure_loaded()
        glyph_extended = .false.
        if (gid >= 1 .and. gid <= NGLYPH) glyph_extended = GEXT(gid)
    end function glyph_extended

    ! The size variants of a glyph along one direction, smallest first,
    ! with the advance each measures in ems along it. Empty for a glyph
    ! with none.
    subroutine glyph_variants(gid, vertical, n, gids, adv)
        integer, intent(in) :: gid
        logical, intent(in) :: vertical
        integer, intent(out) :: n
        integer, allocatable, intent(out) :: gids(:)
        real(dp), allocatable, intent(out) :: adv(:)
        integer :: d, k
        call ensure_loaded()
        n = 0
        if (gid >= 1 .and. gid <= NGLYPH) then
            d = merge(1, 2, vertical)
            n = CVN(d, gid)
        end if
        allocate (gids(n), adv(n))
        do k = 1, n
            gids(k) = VARG(CV0(d, gid) + k - 1)
            adv(k) = real(VARA(CV0(d, gid) + k - 1), dp)/real(FACE_EM(GFACE(gid)), dp)
        end do
    end subroutine glyph_variants

    ! The assembly a glyph is built from along one direction, n = 0 for
    ! none: the parts bottom to top (or left to right), their connector
    ! lengths at the start and the end and full advances in ems, whether
    ! each is an extender, and the italic correction of the whole.
    subroutine glyph_assembly(gid, vertical, n, parts, starts, ends, fulls, &
                              exts, italic)
        integer, intent(in) :: gid
        logical, intent(in) :: vertical
        integer, intent(out) :: n
        integer, allocatable, intent(out) :: parts(:)
        real(dp), allocatable, intent(out) :: starts(:), ends(:), fulls(:)
        logical, allocatable, intent(out) :: exts(:)
        real(dp), intent(out) :: italic
        integer :: d, a, k, p
        real(dp) :: em
        call ensure_loaded()
        n = 0
        italic = 0.0_dp
        a = 0
        if (gid >= 1 .and. gid <= NGLYPH) then
            d = merge(1, 2, vertical)
            a = CASM(d, gid)
            if (a > 0) n = ASMN(a)
        end if
        allocate (parts(n), starts(n), ends(n), fulls(n), exts(n))
        if (a == 0) return
        em = real(FACE_EM(GFACE(gid)), dp)
        italic = real(ASMI(a), dp)/em
        do k = 1, n
            p = ASMP0(a) + k - 1
            parts(k) = PARTG(p)
            starts(k) = real(PARTST(p), dp)/em
            ends(k) = real(PARTEN(p), dp)/em
            fulls(k) = real(PARTF(p), dp)/em
            exts(k) = PARTX(p)
        end do
    end subroutine glyph_assembly

    ! The script (level 1) or scriptscript (level 2) alternate of a glyph,
    ! the glyph itself when it has none.
    integer function glyph_ssty(gid, level)
        integer, intent(in) :: gid, level
        call ensure_loaded()
        glyph_ssty = gid
        if (gid < 1 .or. gid > NGLYPH .or. level < 1 .or. level > 2) return
        if (SSTY(level, gid) > 0) glyph_ssty = SSTY(level, gid)
    end function glyph_ssty

    ! The dotless form of a glyph, for under an accent; itself if none.
    integer function glyph_dotless(gid)
        integer, intent(in) :: gid
        call ensure_loaded()
        glyph_dotless = gid
        if (gid < 1 .or. gid > NGLYPH) return
        if (DTLS(gid) > 0) glyph_dotless = DTLS(gid)
    end function glyph_dotless

    ! --- the code point interface ------------------------------------

    ! The glyph for a code point in a text face. An unknown face is the
    ! regular one, and a code point the face has nothing for is a space,
    ! so that an unexpected one cannot crash a plot.
    function text_gid(c, face) result(gid)
        integer, intent(in) :: c
        integer, intent(in), optional :: face
        integer :: gid, f
        f = FACE_REGULAR
        if (present(face)) f = face
        if (f < 1 .or. f > NFACE) f = FACE_REGULAR
        gid = glyph_cmap(f, c)
        if (gid == 0) gid = glyph_cmap(f, 32)
    end function text_gid

    ! Advance width in font units.
    function glyph_advance(c, face) result(a)
        integer, intent(in) :: c
        integer, intent(in), optional :: face
        real(dp) :: a
        a = real(GADV(text_gid(c, face)), dp)
    end function glyph_advance

    ! The verbs for one character, empty when there is nothing to draw.
    subroutine glyph_verbs(c, v, n, face)
        integer, intent(in) :: c
        integer, allocatable, intent(out) :: v(:)
        integer, intent(out) :: n
        integer, intent(in), optional :: face
        real(dp), allocatable :: x(:), y(:)
        integer :: np
        call outline_of(text_gid(c, face), 1.0_dp, v, n, x, y, np)
    end subroutine glyph_verbs

    ! The points for one character, in font units.
    subroutine glyph_points(c, x, y, n, face)
        integer, intent(in) :: c
        real(dp), allocatable, intent(out) :: x(:), y(:)
        integer, intent(out) :: n
        integer, intent(in), optional :: face
        integer, allocatable :: v(:)
        integer :: nv
        call outline_of(text_gid(c, face), 1.0_dp, v, nv, x, y, n)
    end subroutine glyph_points

    ! --- stored contours to the path the backends fill ---------------

    ! One glyph as verbs and points, scaled by s. Both are built together
    ! because the walk that produces one produces the other.
    subroutine outline_of(gid, s, v, nv, x, y, np)
        integer, intent(in) :: gid
        real(dp), intent(in) :: s
        integer, allocatable, intent(out) :: v(:)
        integer, intent(out) :: nv
        real(dp), allocatable, intent(out) :: x(:), y(:)
        integer, intent(out) :: np
        integer, allocatable :: tv(:)
        real(dp), allocatable :: tx(:), ty(:)
        integer :: nc, npts

        nc = 0
        npts = 0
        call count_glyph(gid, nc, npts)
        ! A contour of n points comes to at most n segments, so at most
        ! n + 2 verbs and 1 + 3n points once the cubics are written out.
        allocate (tv(npts + 2*nc), tx(3*npts + nc), ty(3*npts + nc))
        nv = 0
        np = 0
        call add_glyph(gid, 0, 0, tv, nv, tx, ty, np)
        allocate (v(nv), x(np), y(np))
        v = tv(1:nv)
        x = tx(1:np)*s
        y = ty(1:np)*s
    end subroutine outline_of

    recursive subroutine count_glyph(gid, nc, npts)
        integer, intent(in) :: gid
        integer, intent(inout) :: nc, npts
        integer :: k
        nc = nc + OBEG(gid + 1) - OBEG(gid)
        npts = npts + CBEG(OBEG(gid + 1)) - CBEG(OBEG(gid))
        do k = PBEG(gid), PBEG(gid + 1) - 1
            call count_glyph(PG(k), nc, npts)
        end do
    end subroutine count_glyph

    recursive subroutine add_glyph(gid, dx, dy, v, nv, x, y, np)
        integer, intent(in) :: gid, dx, dy
        integer, intent(inout) :: v(:), nv
        real(dp), intent(inout) :: x(:), y(:)
        integer, intent(inout) :: np
        integer :: ci, k
        do ci = OBEG(gid), OBEG(gid + 1) - 1
            if (FACE_CUBIC(GFACE(gid))) then
                call add_cubic(CBEG(ci), CBEG(ci + 1) - CBEG(ci), dx, dy, &
                               v, nv, x, y, np)
            else
                call add_quad(CBEG(ci), CBEG(ci + 1) - CBEG(ci), dx, dy, &
                              v, nv, x, y, np)
            end if
        end do
        do k = PBEG(gid), PBEG(gid + 1) - 1
            call add_glyph(PG(k), dx + PDX(k), dy + PDY(k), v, nv, x, y, np)
        end do
    end subroutine add_glyph

    ! A cubic contour: it starts on the curve, and every control point
    ! comes with a second one and then the point the curve ends on, the
    ! start itself for the last one.
    subroutine add_cubic(b, n, dx, dy, v, nv, x, y, np)
        integer, intent(in) :: b, n, dx, dy
        integer, intent(inout) :: v(:), nv
        real(dp), intent(inout) :: x(:), y(:)
        integer, intent(inout) :: np
        integer :: j, k

        nv = nv + 1
        v(nv) = VERB_MOVE
        np = np + 1
        x(np) = real(QX(b) + dx, dp)
        y(np) = real(QY(b) + dy, dp)
        j = 1
        do while (j < n)
            if (QON(b + j)) then
                nv = nv + 1
                v(nv) = VERB_LINE
                np = np + 1
                x(np) = real(QX(b + j) + dx, dp)
                y(np) = real(QY(b + j) + dy, dp)
                j = j + 1
            else
                nv = nv + 1
                v(nv) = VERB_CUBIC
                do k = 0, 2
                    np = np + 1
                    x(np) = real(QX(b + mod(j + k, n)) + dx, dp)
                    y(np) = real(QY(b + mod(j + k, n)) + dy, dp)
                end do
                j = j + 3
            end if
        end do
        nv = nv + 1
        v(nv) = VERB_CLOSE
    end subroutine add_cubic

    ! A quadratic contour. TrueType lets a contour start anywhere, so it
    ! is turned to start at a point on the curve; if it has none, the
    ! start is implied halfway between the last point and the first.
    subroutine add_quad(b, n, dx, dy, v, nv, x, y, np)
        integer, intent(in) :: b, n, dx, dy
        integer, intent(inout) :: v(:), nv
        real(dp), intent(inout) :: x(:), y(:)
        integer, intent(inout) :: np
        real(dp) :: sx(n + 2), sy(n + 2)
        logical :: son(n + 2)
        integer :: first, j, k, m, jn
        real(dp) :: cx, cy, ex, ey

        first = 0
        do j = 1, n
            if (QON(b + j - 1)) then
                first = j
                exit
            end if
        end do

        if (first == 0) then
            sx(1) = 0.5_dp*(real(QX(b), dp) + real(QX(b + n - 1), dp))
            sy(1) = 0.5_dp*(real(QY(b), dp) + real(QY(b + n - 1), dp))
            do j = 1, n
                sx(j + 1) = real(QX(b + j - 1), dp)
                sy(j + 1) = real(QY(b + j - 1), dp)
                son(j + 1) = .false.
            end do
            m = n + 1
        else
            sx(1) = real(QX(b + first - 1), dp)
            sy(1) = real(QY(b + first - 1), dp)
            do j = 1, n - 1
                k = b + mod(first - 1 + j, n)
                sx(j + 1) = real(QX(k), dp)
                sy(j + 1) = real(QY(k), dp)
                son(j + 1) = QON(k)
            end do
            m = n
        end if
        sx = sx + real(dx, dp)
        sy = sy + real(dy, dp)
        ! The start comes round again as the point the contour ends on.
        son(1) = .true.
        sx(m + 1) = sx(1)
        sy(m + 1) = sy(1)
        son(m + 1) = .true.

        nv = nv + 1
        v(nv) = VERB_MOVE
        np = np + 1
        x(np) = sx(1)
        y(np) = sy(1)
        cx = sx(1)
        cy = sy(1)

        j = 2
        do while (j <= m + 1)
            if (son(j)) then
                ! A line back to the start is what closing the contour
                ! already says, so the last one is left out.
                if (j < m + 1) then
                    nv = nv + 1
                    v(nv) = VERB_LINE
                    np = np + 1
                    x(np) = sx(j)
                    y(np) = sy(j)
                end if
                cx = sx(j)
                cy = sy(j)
                j = j + 1
            else
                ! Two control points in a row have the point they share
                ! left out of the font; it sits at their midpoint.
                if (son(j + 1)) then
                    ex = sx(j + 1)
                    ey = sy(j + 1)
                    jn = j + 2
                else
                    ex = 0.5_dp*(sx(j) + sx(j + 1))
                    ey = 0.5_dp*(sy(j) + sy(j + 1))
                    jn = j + 1
                end if
                nv = nv + 1
                v(nv) = VERB_CUBIC
                x(np + 1) = cx + (2.0_dp/3.0_dp)*(sx(j) - cx)
                y(np + 1) = cy + (2.0_dp/3.0_dp)*(sy(j) - cy)
                x(np + 2) = ex + (2.0_dp/3.0_dp)*(sx(j) - ex)
                y(np + 2) = ey + (2.0_dp/3.0_dp)*(sy(j) - ey)
                x(np + 3) = ex
                y(np + 3) = ey
                np = np + 3
                cx = ex
                cy = ey
                j = jn
            end if
        end do

        nv = nv + 1
        v(nv) = VERB_CLOSE
    end subroutine add_quad

    ! --- unpacking the blob ------------------------------------------

    subroutine ensure_loaded()
        if (loaded) return
        call unpack()
        loaded = .true.
    end subroutine ensure_loaded

    subroutine unpack()
        integer :: f, k, j, gid, base, ng, lbits, nc, n, ip, ic, icp, ik, ikv
        integer :: guess, prev_adv, xx, yy, cp, prev, nl, nr, l, c, cnt, pf

        call from_base85()
        call build_code()
        BPOS = 0

        FBASE(1) = 0
        do f = 1, NFACE
            FBASE(f + 1) = FBASE(f) + FACE_NG(f)
        end do
        if (FBASE(NFACE + 1) /= NGLYPH) error stop "fplotlib_glyphs: face sizes disagree"

        ip = 0
        ic = 0
        icp = 0
        ik = 0
        ikv = 0
        OBEG(1) = 1
        CBEG(1) = 1
        PBEG(1) = 1
        GCHAR = 0
        GITAL = 0
        GACC = 0
        GEXT = .false.
        MKN = -1
        MKH0 = 0
        MKV0 = 0
        CV0 = 0
        CVN = 0
        CASM = 0
        SSTY = 0
        DTLS = 0
        nmkh_ = 0
        nmkv_ = 0
        nvar_ = 0
        nasm_ = 0
        npart_ = 0
        if (.not. FACE_HAS_MATH(FACE_MATH)) error stop "fplotlib_glyphs: FACE_MATH is not the math face"
        do f = 1, NFACE
            base = FBASE(f)
            ng = FACE_NG(f)
            lbits = nbits(ng)
            pf = FACE_PRED(f)
            prev_adv = 0
            do k = 1, ng
                gid = base + k
                GFACE(gid) = f
                guess = prev_adv
                if (pf > 0) then
                    if (k <= FACE_NG(pf)) guess = GADV(FBASE(pf) + k)
                end if
                GADV(gid) = guess + get_delta()
                prev_adv = GADV(gid)
                if (get_bit() == 1) then
                    n = get_gamma()
                    do j = 1, n
                        ik = ik + 1
                        PG(ik) = base + get_bits(lbits) + 1
                        PDX(ik) = get_delta()
                        PDY(ik) = get_delta()
                    end do
                    nc = 0
                else
                    nc = get_gamma() - 1
                    do j = 1, nc
                        CBEG(ic + j + 1) = CBEG(ic + j) + get_gamma()
                    end do
                    n = CBEG(ic + nc + 1) - CBEG(ic + 1)
                    xx = 0
                    yy = 0
                    do j = 1, n
                        QON(ip + j) = get_bit() == 1
                        xx = xx + get_delta()
                        yy = yy + get_delta()
                        QX(ip + j) = int(xx, int16)
                        QY(ip + j) = int(yy, int16)
                    end do
                    ip = ip + n
                end if
                ic = ic + nc
                OBEG(gid + 1) = ic + 1
                PBEG(gid + 1) = ik + 1
                GBOX(:, gid) = 0
                if (get_bit() == 1) then
                    GBOX(1, gid) = get_delta()
                    GBOX(2, gid) = get_delta()
                    GBOX(3, gid) = GADV(gid) + get_delta()
                    GBOX(4, gid) = get_delta()
                end if
            end do

            ! The cmap, and the code point each glyph is first reached by.
            CMB(f) = icp + 1
            n = get_gamma() - 1
            cp = 0
            prev = -1
            do j = 1, n
                cp = cp + get_gamma()
                if (get_bit() == 1) then
                    prev = prev + 1
                else
                    prev = get_bits(lbits)
                end if
                icp = icp + 1
                CMCP(icp) = cp
                CMG(icp) = base + prev + 1
                if (GCHAR(base + prev + 1) == 0) GCHAR(base + prev + 1) = cp
            end do

            ! The kerning classes and the cells of their matrix.
            nl = get_gamma() - 1
            nr = get_gamma() - 1
            do k = 1, ng
                KLC(base + k) = get_bits(nbits(nl))
                KRC(base + k) = get_bits(nbits(nr))
            end do
            KNR(f) = nr
            KOFF(f) = ikv
            KVAL(ikv + 1:ikv + (nl + 1)*(nr + 1)) = 0_int16
            do l = 1, nl
                cnt = get_gamma() - 1
                c = 0
                do j = 1, cnt
                    c = c + get_gamma()
                    KVAL(ikv + l*(nr + 1) + c + 1) = int(get_delta(), int16)
                end do
            end do
            ikv = ikv + (nl + 1)*(nr + 1)
            if (FACE_HAS_MATH(f)) call unpack_math(base, ng, lbits)
        end do
        CMB(NFACE + 1) = icp + 1

        if (ip /= NPT .or. ic /= NCONT .or. ik /= NCOMP .or. icp /= NCMAP &
            .or. ikv /= NKERN .or. nmkh_ /= NMKH .or. nmkv_ /= NMKV &
            .or. nvar_ /= NVAR .or. nasm_ /= NASM .or. npart_ /= NPART) then
            error stop "fplotlib_glyphs: blob does not fill the tables"
        end if
        deallocate (BUF)
    end subroutine unpack

    ! The MATH section of the face whose gids follow base.
    subroutine unpack_math(base, ng, lbits)
        integer, intent(in) :: base, ng, lbits
        integer :: k, gid, c, n, j, prev, dim, ncons, nv, np_, a, b

        do k = 1, ng
            gid = base + k
            if (get_bit() == 1) GITAL(gid) = get_delta()
            GACC(gid) = GADV(gid)/2
            if (get_bit() == 1) GACC(gid) = GADV(gid)/2 + get_delta()
            GEXT(gid) = get_bit() == 1
            if (get_bit() == 1) then
                do c = 1, 4
                    n = get_gamma() - 1
                    MKN(c, gid) = n
                    MKH0(c, gid) = nmkh_ + 1
                    MKV0(c, gid) = nmkv_ + 1
                    prev = 0
                    do j = 1, n
                        prev = prev + get_delta()
                        nmkh_ = nmkh_ + 1
                        MKH(nmkh_) = prev
                    end do
                    prev = 0
                    do j = 1, n + 1
                        prev = prev + get_delta()
                        nmkv_ = nmkv_ + 1
                        MKV(nmkv_) = prev
                    end do
                end do
            end if
        end do
        do dim = 1, 2
            ncons = get_gamma() - 1
            do k = 1, ncons
                gid = base + get_bits(lbits) + 1
                nv = get_gamma() - 1
                CV0(dim, gid) = nvar_ + 1
                CVN(dim, gid) = nv
                prev = 0
                do j = 1, nv
                    nvar_ = nvar_ + 1
                    VARG(nvar_) = base + get_bits(lbits) + 1
                    prev = prev + get_delta()
                    VARA(nvar_) = prev
                end do
                if (get_bit() == 1) then
                    nasm_ = nasm_ + 1
                    CASM(dim, gid) = nasm_
                    ASMI(nasm_) = get_delta()
                    np_ = get_gamma()
                    ASMP0(nasm_) = npart_ + 1
                    ASMN(nasm_) = np_
                    do j = 1, np_
                        npart_ = npart_ + 1
                        PARTG(npart_) = base + get_bits(lbits) + 1
                        PARTST(npart_) = get_delta()
                        PARTEN(npart_) = get_delta()
                        PARTF(npart_) = get_delta()
                        PARTX(npart_) = get_bit() == 1
                    end do
                end if
            end do
        end do
        n = get_gamma() - 1
        do k = 1, n
            a = base + get_bits(lbits) + 1
            SSTY(1, a) = base + get_bits(lbits) + 1
            SSTY(2, a) = SSTY(1, a)
        end do
        n = get_gamma() - 1
        do k = 1, n
            a = base + get_bits(lbits) + 1
            b = base + get_bits(lbits) + 1
            DTLS(a) = b
        end do

        ! A script-size alternate or a size variant stands for the same
        ! character as its base, which is what a PDF's map back to
        ! Unicode has to say for it.
        do k = 1, ng
            gid = base + k
            if (GCHAR(gid) == 0) cycle
            do j = 1, 2
                if (SSTY(j, gid) > 0) then
                    if (GCHAR(SSTY(j, gid)) == 0) GCHAR(SSTY(j, gid)) = GCHAR(gid)
                end if
            end do
            do dim = 1, 2
                do j = 1, CVN(dim, gid)
                    if (GCHAR(VARG(CV0(dim, gid) + j - 1)) == 0) &
                        GCHAR(VARG(CV0(dim, gid) + j - 1)) = GCHAR(gid)
                end do
            end do
        end do
    end subroutine unpack_math

    ! Bits for a number in 0..n.
    pure integer function nbits(n)
        integer, intent(in) :: n
        integer :: m
        m = max(n, 1)
        nbits = 0
        do while (m > 0)
            nbits = nbits + 1
            m = m/2
        end do
    end function nbits

    ! Five characters back into four bytes, most significant first.
    ! The blob is stored as rows of equal length because ifx caps a
    ! character named constant at 7198 characters; gluing them back
    ! together at run time is not bound by that.
    subroutine from_base85()
        integer :: val(0:127), i, j, k, n, r, w
        integer(int64) :: acc
        character(len=:), allocatable :: blob
        allocate (character(len=BLOB_LEN) :: blob)
        w = len(BLOB_ROWS)
        do r = 1, size(BLOB_ROWS)
            blob((r - 1)*w + 1:min(r*w, BLOB_LEN)) = BLOB_ROWS(r)
        end do
        val = -1
        do i = 1, len(ALPHABET)
            val(iachar(ALPHABET(i:i))) = i - 1
        end do
        n = BLOB_LEN/5
        allocate (BUF(4*n))
        do k = 0, n - 1
            acc = 0
            do j = 1, 5
                acc = acc*85 + int(val(iachar(blob(5*k + j:5*k + j))), int64)
            end do
            do j = 1, 4
                BUF(4*k + j) = int(ibits(acc, 8*(4 - j), 8))
            end do
        end do
    end subroutine from_base85

    ! The canonical code the class lengths describe: codes of one length
    ! run consecutively, in order of the class they stand for, and each
    ! length starts where the one before it left off, shifted up a bit.
    subroutine build_code()
        integer :: l, s, code, k
        if (maxval(CLEN) > MAXLEN) error stop "fplotlib_glyphs: code too long"
        NLEN = 0
        do s = 1, NCLASS
            NLEN(CLEN(s)) = NLEN(CLEN(s)) + 1
        end do
        code = 0
        k = 0
        do l = 1, MAXLEN
            FIRST(l) = code
            CBASE(l) = k
            do s = 1, NCLASS
                if (CLEN(s) == l) then
                    k = k + 1
                    CSYM(k) = s - 1
                end if
            end do
            code = 2*(code + NLEN(l))
        end do
    end subroutine build_code

    integer function get_bit()
        get_bit = ibits(BUF(BPOS/8 + 1), 7 - mod(BPOS, 8), 1)
        BPOS = BPOS + 1
    end function get_bit

    integer function get_bits(n)
        integer, intent(in) :: n
        integer :: i
        get_bits = 0
        do i = 1, n
            get_bits = 2*get_bits + get_bit()
        end do
    end function get_bits

    integer function get_gamma()
        integer :: zeros
        zeros = 0
        do while (get_bit() == 0)
            zeros = zeros + 1
        end do
        get_gamma = ior(ishft(1, zeros), get_bits(zeros))
    end function get_gamma

    integer function get_class()
        integer :: code, l, idx
        code = 0
        do l = 1, MAXLEN
            code = 2*code + get_bit()
            idx = code - FIRST(l)
            if (idx >= 0 .and. idx < NLEN(l)) then
                get_class = CSYM(CBASE(l) + idx + 1)
                return
            end if
        end do
        error stop "fplotlib_glyphs: the glyph blob has a code this module cannot read"
    end function get_class

    ! One delta: its magnitude class, the bits under the leading one, and
    ! then the fold back to a signed number.
    integer function get_delta()
        integer :: c, u
        c = get_class()
        if (c == 0) then
            u = 0
        else
            u = ior(ishft(1, c - 1), get_bits(c - 1))
        end if
        if (mod(u, 2) == 0) then
            get_delta = u/2
        else
            get_delta = -(u + 1)/2
        end if
    end function get_delta

end module fplotlib_glyphs
