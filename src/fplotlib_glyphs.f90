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
! The stream is coded with an adaptive binary range coder, LZMA's: each
! bit has a probability, in a context of its own, that the bits before it
! in that context have moved towards them. A flag is one such bit. A delta
! is a signed number folded to a non-negative one, small magnitudes
! staying small, and written as the position of its leading one -- its
! magnitude class, five bits down a binary tree -- then the bit under the
! leading one, then the bits below that at even chance. gamma is Elias
! gamma: the run of zeros bit by bit, then the bits under the leading one
! at even chance. Raw bits are at even chance. Every kind of value has
! its own context, and an outline point's x and y have contexts saying
! whether it and the point before it are on the curve and how large the
! deltas before them were (tools/gen_glyphs.py, Writer, says exactly).
! For each face in turn:
!
!   * every glyph: its advance width, as a delta from a guess (the glyph
!     at the same position in the face FACE_PRED names, which is the same
!     letter in another weight or slant, or else the glyph before); one
!     bit saying whether it is composite; then either the number of
!     components, gamma coded, and for each -- after a bit saying whether
!     it comes from face FACE_XREF, for a face that has one -- the index
!     in its face of the glyph it places (in as many raw bits as that
!     face's glyph count needs) and its offset as two deltas, or -- after
!     a bit saying whether it is stored as the difference from an earlier
!     glyph with the same contours, for a face that has FACE_RESID, and
!     if it is, that glyph's face-local index in raw bits and, for each
!     point, how far it is from that glyph's point, as deltas from how far
!     the point before it is -- the number of contours plus one, each
!     contour's number of points, and for every point one bit saying
!     whether it lies on the curve and its x and y as deltas from the
!     point before it (the first is a delta from the origin); coordinates
!     and offsets are in outline units of
!     FACE_OSCALE font units, and a component from another face is scaled
!     from its face's units per em to this one's; and, for
!     a glyph with contours or components, its ink box: the decoder works
!     it out (the extremes of a simple glyph's points, or the union of a
!     composite's components' boxes), and one bit says whether the true
!     box is smaller, followed if it is by how much at each side as
!     deltas: left, bottom, right, top;
!   * the cmap: the number of entries plus one, then per entry in code
!     point order the step from the previous code point, gamma coded, and
!     one bit when its glyph is the one after the previous entry's, else
!     that bit and the glyph's face-local index in raw bits;
!   * the pair kerning, unless the face uses another's (FACE_KERN): the
!     numbers of left and right classes plus one, each glyph's left and
!     right class in raw bits, then per left class its non-zero cells plus
!     one, gamma coded, and per cell the step to its right class, gamma
!     coded, and the adjustment in steps of KERN_STEP units as a delta --
!     from the adjustment face FACE_KPRED makes between the glyphs at the
!     same indices as the first glyphs of the two classes, when it names
!     one;
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
    use fplotlib_status
    use iso_fortran_env, only: int16, int64
    use fplotlib_style, only: dp
    use fplotlib_render, only: VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_CLOSE
    use fplotlib_glyphs_data, only: NFACE, NGLYPH, NCONT, NPT, NCOMP, NCMAP, &
                                 NKERN, FACE_NG, FACE_EM, FACE_ASC, FACE_DESC, &
                                 FACE_XH, FACE_CAP, FACE_CUBIC, FACE_PRED, &
                                 NRECOMP, RECOMP_BASE, &
                                 RECOMP_MARK, RECOMP_CHAR, ALPHABET, &
                                 blob_text, BLOB_LEN, FACE_HAS_MATH, NVAR, NASM, &
                                 FACE_KERN, FACE_KPRED, KERN_STEP, &
                                 FACE_OSCALE, FACE_XREF, FACE_RESID, &
                                 NPART, NMKH, NMKV, MATH_CONSTANT
    implicit none
    private

    public :: NFACE, NGLYPH, initialize_glyphs
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

    ! The range coder's adaptation rate, and the contexts it codes with,
    ! as tools/gen_glyphs.py numbers them.
    integer, parameter :: MOVE_BITS = 3
    integer, parameter :: D_ADV = 0, D_CX = 1, D_CY = 2, D_INK = 3, D_ITAL = 4, &
                          D_ACC = 5, D_MKH = 6, D_MKV = 7, D_VAR = 8, D_ASM = 9, &
                          D_CIDX = 10, D_KERN = 12, D_OX = 32, D_OY = 128, &
                          D_RX = 384, D_RY = 396, ND = 460
    integer, parameter :: B_ON = 0, B_COMP = 8, B_RESID = 9, B_XREF = 10, B_INK = 11, &
                          B_CMAP = 12, B_ITAL = 13, B_ACC = 14, B_EXT = 15, &
                          B_MKERN = 16, B_ASM = 17, B_PARTX = 18, NB = 19
    integer, parameter :: G_NCOMP = 0, G_NCONT = 1, G_NPTS = 2, G_CMAPN = 3, &
                          G_CMAPSTEP = 4, G_KCLS = 5, G_KROW = 6, G_KSTEP = 7, &
                          G_MKN = 8, G_CONS = 9, G_NVAR = 10, G_NPART = 11, &
                          G_PAIRS = 12, NG = 13

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

    ! The range decoder: its probabilities, one per context and tree
    ! node, its range and code, and the byte it has got to.
    integer :: RC_D(31, 0:ND - 1), RC_M(95, 0:ND - 1), RC_B(0:NB - 1), &
               RC_G(0:32, 0:NG - 1), RC_T(511, 0:1)
    integer(int64) :: RRANGE, RCODE

    ! The bytes while they are being read, and how far into the MATH
    ! arrays the reading has got.
    integer, allocatable :: BUF(:)
    integer :: BPOS
    integer :: nmkh_, nmkv_, nvar_, nasm_, npart_

contains

    ! --- the gid interface -------------------------------------------

    ! The glyph a face draws a code point with, 0 when it has none.
    function glyph_cmap(face, cp) result(gid)
        integer, intent(in) :: face, cp
        integer :: gid, lo, hi, mid
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
        glyph_face = 0
        if (gid >= 1 .and. gid <= NGLYPH) glyph_face = GFACE(gid)
    end function glyph_face

    ! Advance width in ems.
    function glyph_adv(gid) result(a)
        integer, intent(in) :: gid
        real(dp) :: a
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
        glyph_inked = .false.
        if (gid < 1 .or. gid > NGLYPH) return
        glyph_inked = OBEG(gid + 1) > OBEG(gid) .or. PBEG(gid + 1) > PBEG(gid)
    end function glyph_inked

    ! The pair kerning between two glyphs of a face, in ems. A face that
    ! uses another's kerning looks its glyphs up at the same indices there.
    function glyph_kern(face, g1, g2) result(k)
        integer, intent(in) :: face, g1, g2
        real(dp) :: k
        integer :: l, r, src, i1, i2
        k = 0.0_dp
        if (face < 1 .or. face > NFACE) return
        if (g1 < 1 .or. g1 > NGLYPH .or. g2 < 1 .or. g2 > NGLYPH) return
        if (GFACE(g1) /= face .or. GFACE(g2) /= face) return
        src = FACE_KERN(face)
        i1 = g1 - FBASE(face)
        i2 = g2 - FBASE(face)
        if (i1 > FACE_NG(src) .or. i2 > FACE_NG(src)) return
        l = KLC(FBASE(src) + i1)
        r = KRC(FBASE(src) + i2)
        if (l == 0 .or. r == 0) return
        k = real(KVAL(KOFF(src) + l*(KNR(src) + 1) + r + 1)*KERN_STEP, dp) &
            /real(FACE_EM(face), dp)
    end function glyph_kern

    ! The code point a glyph stands for, 0 for one that has none.
    integer function glyph_char(gid)
        integer, intent(in) :: gid
        glyph_char = 0
        if (gid >= 1 .and. gid <= NGLYPH) glyph_char = GCHAR(gid)
    end function glyph_char

    ! The character a base and one combining mark compose to, 0 if none.
    pure elemental integer function glyph_recompose(base, mark) result(c)
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
    pure elemental real(dp) function face_ascent(face)
        integer, intent(in) :: face
        face_ascent = real(FACE_ASC(face), dp)/real(FACE_EM(face), dp)
    end function face_ascent

    pure elemental real(dp) function face_descent(face)
        integer, intent(in) :: face
        face_descent = real(FACE_DESC(face), dp)/real(FACE_EM(face), dp)
    end function face_descent

    pure elemental real(dp) function face_xheight(face)
        integer, intent(in) :: face
        face_xheight = real(FACE_XH(face), dp)/real(FACE_EM(face), dp)
    end function face_xheight

    pure elemental real(dp) function face_capheight(face)
        integer, intent(in) :: face
        face_capheight = real(FACE_CAP(face), dp)/real(FACE_EM(face), dp)
    end function face_capheight

    ! --- the MATH table ----------------------------------------------

    ! A MATH constant in ems. The three that are percentages are read with
    ! math_percent instead.
    pure elemental real(dp) function math_const(i)
        integer, intent(in) :: i
        math_const = real(MATH_CONSTANT(i), dp)/real(FACE_EM(FACE_MATH), dp)
    end function math_const

    pure elemental real(dp) function math_percent(i)
        integer, intent(in) :: i
        math_percent = real(MATH_CONSTANT(i), dp)
    end function math_percent

    ! The italic correction of a glyph, in ems.
    function glyph_italic(gid) result(v)
        integer, intent(in) :: gid
        real(dp) :: v
        v = 0.0_dp
        if (gid < 1 .or. gid > NGLYPH) return
        v = real(GITAL(gid), dp)/real(FACE_EM(GFACE(gid)), dp)
    end function glyph_italic

    ! Where an accent over a glyph is centred, in ems from its origin: the
    ! MATH table's attachment point, or half the advance without one.
    function glyph_top_accent(gid) result(v)
        integer, intent(in) :: gid
        real(dp) :: v
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
        glyph_ssty = gid
        if (gid < 1 .or. gid > NGLYPH .or. level < 1 .or. level > 2) return
        if (SSTY(level, gid) > 0) glyph_ssty = SSTY(level, gid)
    end function glyph_ssty

    ! The dotless form of a glyph, for under an accent; itself if none.
    integer function glyph_dotless(gid)
        integer, intent(in) :: gid
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
        call add_glyph(gid, 0.0_dp, 0.0_dp, 1.0_dp, tv, nv, tx, ty, np)
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

    ! A glyph's contours, scaled by s and offset by (dx, dy), and its
    ! components'; a component from another face is scaled from its
    ! face's units per em to the glyph's.
    recursive subroutine add_glyph(gid, dx, dy, s, v, nv, x, y, np)
        integer, intent(in) :: gid
        real(dp), intent(in) :: dx, dy, s
        integer, intent(inout) :: v(:), nv
        real(dp), intent(inout) :: x(:), y(:)
        integer, intent(inout) :: np
        integer :: ci, k, n0
        real(dp) :: r
        n0 = np
        do ci = OBEG(gid), OBEG(gid + 1) - 1
            if (FACE_CUBIC(GFACE(gid))) then
                call add_cubic(CBEG(ci), CBEG(ci + 1) - CBEG(ci), v, nv, x, y, np)
            else
                call add_quad(CBEG(ci), CBEG(ci + 1) - CBEG(ci), v, nv, x, y, np)
            end if
        end do
        x(n0 + 1:np) = x(n0 + 1:np)*s + dx
        y(n0 + 1:np) = y(n0 + 1:np)*s + dy
        do k = PBEG(gid), PBEG(gid + 1) - 1
            r = real(FACE_EM(GFACE(gid)), dp)/real(FACE_EM(GFACE(PG(k))), dp)
            call add_glyph(PG(k), dx + PDX(k)*s, dy + PDY(k)*s, s*r, v, nv, x, y, np)
        end do
    end subroutine add_glyph

    ! A cubic contour: it starts on the curve, and every control point
    ! comes with a second one and then the point the curve ends on, the
    ! start itself for the last one.
    subroutine add_cubic(b, n, v, nv, x, y, np)
        integer, intent(in) :: b, n
        integer, intent(inout) :: v(:), nv
        real(dp), intent(inout) :: x(:), y(:)
        integer, intent(inout) :: np
        integer :: j, k

        nv = nv + 1
        v(nv) = VERB_MOVE
        np = np + 1
        x(np) = real(QX(b), dp)
        y(np) = real(QY(b), dp)
        j = 1
        do while (j < n)
            if (QON(b + j)) then
                nv = nv + 1
                v(nv) = VERB_LINE
                np = np + 1
                x(np) = real(QX(b + j), dp)
                y(np) = real(QY(b + j), dp)
                j = j + 1
            else
                nv = nv + 1
                v(nv) = VERB_CUBIC
                do k = 0, 2
                    np = np + 1
                    x(np) = real(QX(b + mod(j + k, n)), dp)
                    y(np) = real(QY(b + mod(j + k, n)), dp)
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
    subroutine add_quad(b, n, v, nv, x, y, np)
        integer, intent(in) :: b, n
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

    ! Internal table queries below do not initialize shared state. Public text,
    ! math and rendering entrypoints prepare resources and check this result.
    subroutine initialize_glyphs(status)
        use fplotlib_status, only: status_t
        type(status_t), intent(out) :: status
        if (loaded) return
        call unpack(status)
        if (.not. status%ok()) return
        loaded = .true.
    end subroutine initialize_glyphs

    subroutine unpack(status)
        use fplotlib_status, only: status_t, ERROR_RESOURCE
        type(status_t), intent(out) :: status
        integer :: f, k, j, gid, base, ng, lbits, nc, n, ip, ic, icp, ik, ikv
        integer :: guess, prev_adv, xx, yy, cp, prev, nl, nr, l, c, cnt, pf
        integer :: shrink(4, NGLYPH), xf, rg, r0, cx, cy, dx, dy, o, onp, onp2
        integer :: lastc(0:1, 0:1), jj, pc, d
        logical :: boxed(NGLYPH)

        call from_base85()
        call rc_init()

        FBASE(1) = 0
        do f = 1, NFACE
            FBASE(f + 1) = FBASE(f) + FACE_NG(f)
        end do
        if (FBASE(NFACE + 1) /= NGLYPH) then
            call status%set(ERROR_RESOURCE, "fplotlib_glyphs: face sizes disagree")
            deallocate (BUF)
            return
        end if

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
        if (.not. FACE_HAS_MATH(FACE_MATH)) then
            call status%set(ERROR_RESOURCE, "fplotlib_glyphs: FACE_MATH is not the math face")
            deallocate (BUF)
            return
        end if
        do f = 1, NFACE
            base = FBASE(f)
            ng = FACE_NG(f)
            lbits = nbits(ng)
            pf = FACE_PRED(f)
            prev_adv = 0
            lastc = 0
            do k = 1, ng
                gid = base + k
                GFACE(gid) = f
                guess = prev_adv
                if (pf > 0) then
                    if (k <= FACE_NG(pf)) guess = GADV(FBASE(pf) + k)
                end if
                GADV(gid) = guess + get_delta(D_ADV)
                prev_adv = GADV(gid)
                if (get_flag(B_COMP) == 1) then
                    n = get_gamma(G_NCOMP)
                    do j = 1, n
                        ik = ik + 1
                        xf = 0
                        if (FACE_XREF(f) > 0) then
                            if (get_flag(B_XREF) == 1) xf = FACE_XREF(f)
                        end if
                        ! The index, from the last one at this position.
                        jj = min(j - 1, 1)
                        lastc(merge(1, 0, xf > 0), jj) = lastc(merge(1, 0, xf > 0), jj) &
                                                        + get_delta(D_CIDX + jj)
                        if (xf > 0) then
                            PG(ik) = FBASE(xf) + lastc(1, jj) + 1
                        else
                            PG(ik) = base + lastc(0, jj) + 1
                        end if
                        PDX(ik) = get_delta(D_CX)*FACE_OSCALE(f)
                        PDY(ik) = get_delta(D_CY)*FACE_OSCALE(f)
                    end do
                    nc = 0
                else
                    rg = 0
                    if (FACE_RESID(f)) then
                        if (get_flag(B_RESID) == 1) rg = base + get_raw(lbits) + 1
                    end if
                    if (rg > 0) then
                        ! The contours of glyph rg, point for point, moved.
                        nc = OBEG(rg + 1) - OBEG(rg)
                        do j = 1, nc
                            CBEG(ic + j + 1) = CBEG(ic + j) + CBEG(OBEG(rg) + j) &
                                               - CBEG(OBEG(rg) + j - 1)
                        end do
                        n = CBEG(ic + nc + 1) - CBEG(ic + 1)
                        r0 = CBEG(OBEG(rg)) - 1
                        xx = 0
                        yy = 0
                        cx = 0
                        cy = 0
                        do j = 1, n
                            QON(ip + j) = QON(r0 + j)
                            dx = get_delta(D_RX + min(cx, 11))
                            dy = get_delta(D_RY + min(cy, 7)*8 + min(vcls(dx), 7))
                            xx = xx + dx
                            yy = yy + dy
                            cx = vcls(dx)
                            cy = vcls(dy)
                            QX(ip + j) = int(QX(r0 + j) + xx*FACE_OSCALE(f), int16)
                            QY(ip + j) = int(QY(r0 + j) + yy*FACE_OSCALE(f), int16)
                        end do
                    else
                        nc = get_gamma(G_NCONT) - 1
                        do j = 1, nc
                            CBEG(ic + j + 1) = CBEG(ic + j) + get_gamma(G_NPTS)
                        end do
                        n = CBEG(ic + nc + 1) - CBEG(ic + 1)
                        xx = 0
                        yy = 0
                        cx = 0
                        cy = 0
                        onp = 1
                        onp2 = 1
                        do j = 1, n
                            o = get_flag(B_ON + onp*4 + onp2*2 + merge(1, 0, FACE_CUBIC(f)))
                            QON(ip + j) = o == 1
                            dx = get_delta(D_OX + ((o*2 + onp)*12 + min(cx, 11))*2 &
                                           + merge(1, 0, cy == 0))
                            dy = get_delta(D_OY + ((o*2 + onp)*8 + min(cy, 7))*8 &
                                           + min(vcls(dx), 7))
                            xx = xx + dx
                            yy = yy + dy
                            cx = vcls(dx)
                            cy = vcls(dy)
                            onp2 = onp
                            onp = o
                            QX(ip + j) = int(xx*FACE_OSCALE(f), int16)
                            QY(ip + j) = int(yy*FACE_OSCALE(f), int16)
                        end do
                    end if
                    ip = ip + n
                end if
                ic = ic + nc
                OBEG(gid + 1) = ic + 1
                PBEG(gid + 1) = ik + 1
                GBOX(:, gid) = 0
                shrink(:, gid) = 0
                if (nc > 0 .or. PBEG(gid + 1) > PBEG(gid)) then
                    if (get_flag(B_INK) == 1) then
                        do j = 1, 4
                            shrink(j, gid) = get_delta(D_INK)
                        end do
                    end if
                end if
                if (nc > 0) then
                    GBOX(1, gid) = minval(QX(CBEG(OBEG(gid)):ip))
                    GBOX(2, gid) = minval(QY(CBEG(OBEG(gid)):ip))
                    GBOX(3, gid) = maxval(QX(CBEG(OBEG(gid)):ip))
                    GBOX(4, gid) = maxval(QY(CBEG(OBEG(gid)):ip))
                    call shrink_box(gid, shrink(:, gid))
                end if
            end do

            ! The cmap, and the code point each glyph is first reached by.
            CMB(f) = icp + 1
            n = get_gamma(G_CMAPN) - 1
            cp = 0
            prev = -1
            do j = 1, n
                cp = cp + get_gamma(G_CMAPSTEP)
                if (get_flag(B_CMAP) == 1) then
                    prev = prev + 1
                else
                    prev = get_raw(lbits)
                end if
                icp = icp + 1
                CMCP(icp) = cp
                CMG(icp) = base + prev + 1
                if (GCHAR(base + prev + 1) == 0) GCHAR(base + prev + 1) = cp
            end do

            ! The kerning classes and the cells of their matrix.
            KLC(base + 1:base + ng) = 0
            KRC(base + 1:base + ng) = 0
            if (FACE_KERN(f) == f) then
                nl = get_gamma(G_KCLS) - 1
                nr = get_gamma(G_KCLS) - 1
                do k = 1, ng
                    KLC(base + k) = get_tree(0, nbits(nl))
                    KRC(base + k) = get_tree(1, nbits(nr))
                end do
                KNR(f) = nr
                KOFF(f) = ikv
                KVAL(ikv + 1:ikv + (nl + 1)*(nr + 1)) = 0_int16
                do l = 1, nl
                    cnt = get_gamma(G_KROW) - 1
                    c = 0
                    pc = 0
                    do j = 1, cnt
                        c = c + get_gamma(G_KSTEP)
                        d = get_delta(D_KERN + min(pc, 7))
                        KVAL(ikv + l*(nr + 1) + c + 1) = int(d + kern_guess(f, l, c), int16)
                        pc = vcls(d)
                    end do
                end do
                ikv = ikv + (nl + 1)*(nr + 1)
            end if
            if (FACE_HAS_MATH(f)) call unpack_math(base, ng, lbits)
        end do
        CMB(NFACE + 1) = icp + 1

        ! A composite's box is its components', which may come after it,
        ! in a later face, or be composite themselves.
        boxed = PBEG(2:NGLYPH + 1) == PBEG(1:NGLYPH)
        do gid = 1, NGLYPH
            call composite_box(gid, boxed, shrink)
        end do

        if (ip /= NPT .or. ic /= NCONT .or. ik /= NCOMP .or. icp /= NCMAP &
            .or. ikv /= NKERN .or. nmkh_ /= NMKH .or. nmkv_ /= NMKV &
            .or. nvar_ /= NVAR .or. nasm_ /= NASM .or. npart_ /= NPART) then
            call status%set(ERROR_RESOURCE, "fplotlib_glyphs: blob does not fill the tables")
        end if
        deallocate (BUF)
    end subroutine unpack

    ! The ink box of a composite, once its components have theirs.
    recursive subroutine composite_box(gid, boxed, shrink)
        integer, intent(in) :: gid, shrink(:, :)
        logical, intent(inout) :: boxed(:)
        integer :: j, c, k
        if (boxed(gid)) return
        GBOX(1, gid) = huge(1)
        GBOX(2, gid) = huge(1)
        GBOX(3, gid) = -huge(1)
        GBOX(4, gid) = -huge(1)
        do j = PBEG(gid), PBEG(gid + 1) - 1
            c = PG(j)
            call composite_box(c, boxed, shrink)
            if (OBEG(c + 1) == OBEG(c) .and. PBEG(c + 1) == PBEG(c)) cycle
            k = FACE_EM(GFACE(gid))/FACE_EM(GFACE(c))
            GBOX(1, gid) = min(GBOX(1, gid), GBOX(1, c)*k + PDX(j))
            GBOX(2, gid) = min(GBOX(2, gid), GBOX(2, c)*k + PDY(j))
            GBOX(3, gid) = max(GBOX(3, gid), GBOX(3, c)*k + PDX(j))
            GBOX(4, gid) = max(GBOX(4, gid), GBOX(4, c)*k + PDY(j))
        end do
        call shrink_box(gid, shrink(:, gid))
        boxed(gid) = .true.
    end subroutine composite_box

    ! The true ink box of a glyph from the one worked out for it.
    subroutine shrink_box(gid, d)
        integer, intent(in) :: gid, d(4)
        GBOX(1, gid) = GBOX(1, gid) + d(1)
        GBOX(2, gid) = GBOX(2, gid) + d(2)
        GBOX(3, gid) = GBOX(3, gid) - d(3)
        GBOX(4, gid) = GBOX(4, gid) - d(4)
    end subroutine shrink_box

    ! What face FACE_KPRED(f) kerns the first glyphs of left class l and
    ! right class r of face f by, in steps; 0 when f has no such face.
    integer function kern_guess(f, l, r) result(v)
        integer, intent(in) :: f, l, r
        integer :: p, i, j, k
        v = 0
        p = FACE_KPRED(f)
        if (p == 0) return
        i = 0
        j = 0
        do k = 1, FACE_NG(f)
            if (i == 0 .and. KLC(FBASE(f) + k) == l) i = k
            if (j == 0 .and. KRC(FBASE(f) + k) == r) j = k
            if (i > 0 .and. j > 0) exit
        end do
        if (i == 0 .or. j == 0 .or. i > FACE_NG(p) .or. j > FACE_NG(p)) return
        i = KLC(FBASE(p) + i)
        j = KRC(FBASE(p) + j)
        if (i == 0 .or. j == 0) return
        v = KVAL(KOFF(p) + i*(KNR(p) + 1) + j + 1)
    end function kern_guess

    ! The MATH section of the face whose gids follow base.
    subroutine unpack_math(base, ng, lbits)
        integer, intent(in) :: base, ng, lbits
        integer :: k, gid, c, n, j, prev, dim, ncons, nv, np_, a, b

        do k = 1, ng
            gid = base + k
            if (get_flag(B_ITAL) == 1) GITAL(gid) = get_delta(D_ITAL)
            GACC(gid) = GADV(gid)/2
            if (get_flag(B_ACC) == 1) GACC(gid) = GADV(gid)/2 + get_delta(D_ACC)
            GEXT(gid) = get_flag(B_EXT) == 1
            if (get_flag(B_MKERN) == 1) then
                do c = 1, 4
                    n = get_gamma(G_MKN) - 1
                    MKN(c, gid) = n
                    MKH0(c, gid) = nmkh_ + 1
                    MKV0(c, gid) = nmkv_ + 1
                    prev = 0
                    do j = 1, n
                        prev = prev + get_delta(D_MKH)
                        nmkh_ = nmkh_ + 1
                        MKH(nmkh_) = prev
                    end do
                    prev = 0
                    do j = 1, n + 1
                        prev = prev + get_delta(D_MKV)
                        nmkv_ = nmkv_ + 1
                        MKV(nmkv_) = prev
                    end do
                end do
            end if
        end do
        do dim = 1, 2
            ncons = get_gamma(G_CONS) - 1
            do k = 1, ncons
                gid = base + get_raw(lbits) + 1
                nv = get_gamma(G_NVAR) - 1
                CV0(dim, gid) = nvar_ + 1
                CVN(dim, gid) = nv
                prev = 0
                do j = 1, nv
                    nvar_ = nvar_ + 1
                    VARG(nvar_) = base + get_raw(lbits) + 1
                    prev = prev + get_delta(D_VAR)
                    VARA(nvar_) = prev
                end do
                if (get_flag(B_ASM) == 1) then
                    nasm_ = nasm_ + 1
                    CASM(dim, gid) = nasm_
                    ASMI(nasm_) = get_delta(D_ASM)
                    np_ = get_gamma(G_NPART)
                    ASMP0(nasm_) = npart_ + 1
                    ASMN(nasm_) = np_
                    do j = 1, np_
                        npart_ = npart_ + 1
                        PARTG(npart_) = base + get_raw(lbits) + 1
                        PARTST(npart_) = get_delta(D_ASM)
                        PARTEN(npart_) = get_delta(D_ASM)
                        PARTF(npart_) = get_delta(D_ASM)
                        PARTX(npart_) = get_flag(B_PARTX) == 1
                    end do
                end if
            end do
        end do
        n = get_gamma(G_PAIRS) - 1
        do k = 1, n
            a = base + get_raw(lbits) + 1
            SSTY(1, a) = base + get_raw(lbits) + 1
            SSTY(2, a) = SSTY(1, a)
        end do
        n = get_gamma(G_PAIRS) - 1
        do k = 1, n
            a = base + get_raw(lbits) + 1
            b = base + get_raw(lbits) + 1
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
    pure elemental integer function nbits(n)
        integer, intent(in) :: n
        integer :: m
        m = max(n, 1)
        nbits = 0
        do while (m > 0)
            nbits = nbits + 1
            m = m/2
        end do
    end function nbits

    ! Five characters back into four bytes, most significant first. The
    ! blob is stored as rows of equal length because ifx caps a character
    ! named constant at 7198 characters; blob_text glues them back
    ! together at run time, which is not bound by that.
    subroutine from_base85()
        integer :: val(0:127), i, j, k, n
        integer(int64) :: acc
        character(len=:), allocatable :: blob
        allocate (character(len=BLOB_LEN) :: blob)
        call blob_text(blob)
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

    ! --- the range decoder ----------------------------------------------

    subroutine rc_init()
        integer :: i
        RC_D = 1024
        RC_M = 1024
        RC_B = 1024
        RC_G = 1024
        RC_T = 1024
        BPOS = 0
        RRANGE = 4294967295_int64
        RCODE = 0
        do i = 1, 5
            RCODE = ior(ishft(RCODE, 8), int(next_byte(), int64))
        end do
    end subroutine rc_init

    integer function next_byte()
        next_byte = 0
        if (BPOS < size(BUF)) next_byte = BUF(BPOS + 1)
        BPOS = BPOS + 1
    end function next_byte

    subroutine rc_norm()
        do while (RRANGE < 16777216_int64)
            RRANGE = ishft(RRANGE, 8)
            RCODE = iand(ior(ishft(RCODE, 8), int(next_byte(), int64)), 4294967295_int64)
        end do
    end subroutine rc_norm

    ! One bit, coded with probability p (of 2048) of being 0, which it
    ! then moves towards the bit it was.
    integer function rc_bit(p)
        integer, intent(inout) :: p
        integer(int64) :: bound
        bound = ishft(RRANGE, -11)*p
        if (RCODE < bound) then
            RRANGE = bound
            p = p + ishft(2048 - p, -MOVE_BITS)
            rc_bit = 0
        else
            RCODE = RCODE - bound
            RRANGE = RRANGE - bound
            p = p - ishft(p, -MOVE_BITS)
            rc_bit = 1
        end if
        call rc_norm()
    end function rc_bit

    ! n bits at even chance, most significant first.
    integer function get_raw(n)
        integer, intent(in) :: n
        integer :: i
        get_raw = 0
        do i = 1, n
            RRANGE = ishft(RRANGE, -1)
            if (RCODE >= RRANGE) then
                RCODE = RCODE - RRANGE
                get_raw = 2*get_raw + 1
            else
                get_raw = 2*get_raw
            end if
            call rc_norm()
        end do
    end function get_raw

    ! n bits down binary tree side of RC_T.
    integer function get_tree(side, n)
        integer, intent(in) :: side, n
        integer :: node, i, b
        node = 1
        do i = 1, n
            b = rc_bit(RC_T(node, side))
            node = 2*node + b
        end do
        get_tree = node - 2**n
    end function get_tree

    integer function get_flag(ctx)
        integer, intent(in) :: ctx
        get_flag = rc_bit(RC_B(ctx))
    end function get_flag

    ! Elias gamma: the run of zeros bit by bit, then the bits under the
    ! leading one.
    integer function get_gamma(ctx)
        integer, intent(in) :: ctx
        integer :: z, b
        z = 0
        do
            b = rc_bit(RC_G(min(z, 32), ctx))
            if (b == 1) exit
            z = z + 1
        end do
        get_gamma = ior(ishft(1, z), get_raw(z))
    end function get_gamma

    ! A delta: its magnitude class down a five-level binary tree, the two
    ! bits under the leading one (the second in the context of the first),
    ! then the rest at even chance, and the fold back to a signed number.
    integer function get_delta(ctx)
        integer, intent(in) :: ctx
        integer :: node, i, c, u, b
        node = 1
        do i = 1, 5
            b = rc_bit(RC_D(node, ctx))
            node = 2*node + b
        end do
        c = node - 32
        u = 0
        if (c == 1) then
            u = 1
        else if (c >= 2) then
            b = rc_bit(RC_M(c, ctx))
            u = ior(2, b)
            if (c >= 3) then
                i = rc_bit(RC_M(32 + 2*c + b, ctx))
                u = ior(ishft(ior(2*u, i), c - 3), get_raw(c - 3))
            end if
        end if
        if (mod(u, 2) == 0) then
            get_delta = u/2
        else
            get_delta = -(u + 1)/2
        end if
    end function get_delta

    ! The magnitude class of a delta: the position of the leading one of
    ! its fold to a non-negative number.
    pure elemental integer function vcls(v)
        integer, intent(in) :: v
        integer :: u
        u = merge(2*v, -2*v - 1, v >= 0)
        vcls = 0
        do while (u > 0)
            vcls = vcls + 1
            u = u/2
        end do
    end function vcls

end module fplotlib_glyphs
