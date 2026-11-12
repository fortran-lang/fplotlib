! fplotlib_typeset -- TeX's paragraph and page layout.
!
! The engine under fplotlib's documents (fplotlib_markdown builds them).
! It is TeX's, as The TeXbook and TeX: The Program describe it, with the
! choices LaTeX makes, so that a paragraph breaks into the same lines and
! a document into the same pages as XeTeX sets them with the same fonts:
!
!   * text becomes a horizontal list of words, glue, kerns, penalties and
!     discretionary hyphens. A word is shaped with the face's kerning;
!     the glue between words is XeTeX's for an OpenType font (the space's
!     width, stretching by half of it and shrinking by a third), scaled
!     by the space factor after punctuation as \nonfrenchspacing does;
!   * a paragraph is broken into lines by Knuth and Plass's algorithm,
!     TeX's line_break: a first pass without hyphenation within
!     \pretolerance, a second with every word hyphenated (fplotlib_hyph)
!     within \tolerance, demerits, fitness classes and all;
!   * the lines go onto a vertical list with \baselineskip, \lineskip and
!     \lineskiplimit between them and TeX's penalties (club, widow,
!     broken) after them; displayed equations, headings and skips go
!     there too;
!   * TeX's page builder cuts the vertical list into pages at the break of
!     least cost, with \topskip and \maxdepth as TeX has them.
!
! Lengths are in PostScript points (bp, 1/72 in), the unit of fplotlib's
! canvases; badness is computed in TeX's scaled points, with TeX's own
! integer formula, so that it is exactly TeX's.
!
! The document is built by calls (ts_begin_par, ts_word, ts_space, ...)
! into module state, then ts_paginate cuts it into pages and ts_page_draw
! draws one page on any renderer.
module fplotlib_typeset
    use fplotlib_style, only: dp
    use fplotlib_render, only: renderer_t, paint_t, glyphrun_t
    use fplotlib_text, only: code_points, run_add
    use fplotlib_glyphs, only: glyph_cmap, glyph_adv, glyph_kern, glyph_bbox, &
                               face_xheight, FACE_REGULAR, FACE_BOLD, FACE_ITALIC, &
                               FACE_MATH
    use fplotlib_hyph, only: hyph_points
    use fplotlib_mathtext, only: math_formula, mrules_t
    implicit none
    private

    public :: ts_reset, ts_set_page, ts_set_font
    public :: ts_begin_par, ts_end_par, ts_word, ts_space, ts_math, ts_hard_break
    public :: ts_hfil, ts_kern, ts_nbsp, ts_label, ts_display, ts_in_par
    public :: ts_vskip, ts_addvspace, ts_penalty, ts_addpenalty, ts_vfil, ts_rule
    public :: ts_page_break, ts_mark, ts_nobreak_next, ts_set_clubpenalty
    public :: ts_vkeep, ts_set_colors, ts_hsize, ts_font_size, ts_strut, ts_set_parskip
    public :: ts_paginate, ts_page_count, ts_page_draw, ts_page_size
    public :: ts_line_count, ts_line_info, ts_par_lines
    public :: ts_glue_t, ts_xheight, ts_quad
    public :: ALIGN_JUSTIFY, ALIGN_LEFT, ALIGN_CENTER, ALIGN_RIGHT

    integer, parameter :: ALIGN_JUSTIFY = 0, ALIGN_LEFT = 1, ALIGN_CENTER = 2, &
                          ALIGN_RIGHT = 3

    ! A glue specification: natural width, stretch and shrink, and their
    ! orders (0 finite, 1 fil, 2 fill, 3 filll).
    type :: ts_glue_t
        real(dp) :: w = 0.0_dp, st = 0.0_dp, sh = 0.0_dp
        integer :: sto = 0, sho = 0
    end type ts_glue_t

    ! TeX's constants.
    integer, parameter :: INF_BAD = 10000, INF_PENALTY = 10000, EJECT_PENALTY = -10000
    integer, parameter :: AWFUL_BAD = 1073741823, DEPLORABLE = 100000
    ! Scaled points to a big point.
    real(dp), parameter :: SP_PER_BP = 65536.0_dp*72.27_dp/72.0_dp

    ! LaTeX's line breaking parameters.
    integer, parameter :: PRETOLERANCE = 100, TOLERANCE = 200
    integer, parameter :: LINE_PENALTY = 10, HYPHEN_PENALTY = 50, EX_HYPHEN_PENALTY = 50
    integer, parameter :: ADJ_DEMERITS = 10000, DOUBLE_HYPHEN_DEMERITS = 10000
    integer, parameter :: FINAL_HYPHEN_DEMERITS = 5000
    integer, parameter :: INTERLINE_PENALTY = 0, WIDOW_PENALTY = 150
    integer, parameter :: DISPLAY_WIDOW_PENALTY = 50, BROKEN_PENALTY = 100
    integer, parameter :: PRE_DISPLAY_PENALTY = 10000, POST_DISPLAY_PENALTY = 0
    integer, parameter :: LEFT_HYPHEN_MIN = 2, RIGHT_HYPHEN_MIN = 3
    integer :: CLUB_PENALTY = 150

    integer, parameter :: VERY_LOOSE = 0, LOOSE = 1, DECENT = 2, TIGHT = 3

    ! --- the horizontal list of the paragraph being built ---------------

    integer, parameter :: HK_WORD = 1, HK_GLUE = 2, HK_KERN = 3, HK_PEN = 4, &
                          HK_DISC = 5, HK_BOX = 6

    integer :: HN = 0
    integer, allocatable :: HK(:), HFACE(:), HCOL(:), HC0(:), HC1(:), HI0(:), HI1(:)
    integer, allocatable :: HSO(:), HHO(:), HP(:)
    logical, allocatable :: HEXPL(:)
    real(dp), allocatable :: HW(:), HH(:), HD(:), HST(:), HSH(:), HSZ(:), HRAISE(:)
    ! The code points of the words.
    integer :: NCP = 0
    integer, allocatable :: CPA(:)
    ! The items of the boxes in the list (formulas, labels), about each
    ! box's origin, y up.
    integer :: NBX = 0
    integer, allocatable :: BXK(:), BXG(:), BXC(:)
    real(dp), allocatable :: BXX(:), BXY(:), BXS(:), BXW(:), BXH(:)

    ! The paragraph's settings.
    logical :: IN_PAR = .false.
    integer :: P_ALIGN = ALIGN_JUSTIFY
    real(dp) :: P_LEFT = 0.0_dp, P_RIGHT = 0.0_dp, P_HANG = 0.0_dp
    real(dp) :: P_SF = 1000.0_dp
    integer :: P_PREV_GRAF = 0
    real(dp) :: P_SIZE = 10.0_dp
    ! Lines of the paragraph may not be broken between (a heading's).
    logical :: P_NOBREAK = .false.
    ! The \baselineskip the paragraph's lines are set with.
    type(ts_glue_t) :: CUR_BASELINE

    ! --- the items of the finished boxes, about their box's origin --------

    integer :: NIT = 0
    integer, allocatable :: ITK(:), ITG(:), ITC(:)
    real(dp), allocatable :: ITX(:), ITY(:), ITS(:), ITW(:), ITH(:)

    ! --- the main vertical list -------------------------------------------

    integer, parameter :: VK_BOX = 1, VK_GLUE = 2, VK_KERN = 3, VK_PEN = 4, VK_MARK = 5
    integer :: NV = 0
    integer, allocatable :: VK(:), VSO(:), VHO(:), VP(:), VI0(:), VI1(:)
    real(dp), allocatable :: VW(:), VH(:), VD(:), VST(:), VSH(:), VX(:)
    ! VK_MARK: a running head, MARKS(VI0) to MARKS(VI1); VSO 0 for the
    ! chapter's (LaTeX's left mark), 1 for a section's (the right mark);
    ! VP 1 for a page that is to have no head (a chapter's first).
    character(len=:), allocatable :: MARKS
    real(dp) :: PREV_DEPTH = -1000.0_dp
    real(dp), parameter :: IGNORE_DEPTH = -1000.0_dp
    ! A paragraph after a heading may not break after its first line.
    logical :: NOBREAK_NEXT = .false.

    ! --- the document's settings -------------------------------------------

    real(dp) :: PAPER_W = 595.2756_dp, PAPER_H = 841.8898_dp
    real(dp) :: MARGIN_L = 72.0_dp, MARGIN_R = 72.0_dp, MARGIN_T = 72.0_dp, &
                MARGIN_B = 72.0_dp
    real(dp) :: HSIZE = 451.2756_dp, VSIZE = 697.8898_dp
    real(dp) :: FONT_SIZE = 10.0_dp
    type(ts_glue_t) :: BASELINESKIP, LINESKIP, PARSKIP
    real(dp) :: LINESKIPLIMIT = 0.0_dp, TOPSKIP = 10.0_dp, MAXDEPTH = 5.0_dp
    real(dp) :: FOOTSKIP = 30.0_dp
    logical :: PAGE_NUMBERS = .true.
    logical :: HEADINGS = .false.
    ! LaTeX's \flushbottom (the book class): a page's glue stretches to
    ! fill it; otherwise \raggedbottom, the glue at its natural size.
    logical :: FLUSH_BOTTOM = .false.
    integer :: TEXT_COLOR = 0
    integer :: PAGE_COLOR = 16777215

    ! --- the pages -------------------------------------------------------

    integer :: NPAGE = 0
    integer, allocatable :: PG0(:), PG1(:), PGHEAD0(:), PGHEAD1(:), PGSTART(:)
    logical, allocatable :: PGPLAIN(:)
    ! How a page's glue is set: by PGSET times its stretch (positive) or
    ! shrink (negative) of order PGORD.
    real(dp), allocatable :: PGSET(:)
    integer, allocatable :: PGORD(:)

    ! The lines of the last paragraph, for tests: their vertical list
    ! entries.
    integer :: LAST_PAR0 = 0, LAST_PAR1 = -1

contains

    ! ------------------------------------------------------------------
    ! Settings.
    ! ------------------------------------------------------------------

    ! Start a new document.
    subroutine ts_reset()
        HN = 0
        NCP = 0
        NBX = 0
        NIT = 0
        NV = 0
        NPAGE = 0
        IN_PAR = .false.
        PREV_DEPTH = IGNORE_DEPTH
        NOBREAK_NEXT = .false.
        CLUB_PENALTY = 150
        MARKS = ""
        call ts_set_page(595.2756_dp, 841.8898_dp, 72.0_dp, 72.0_dp, 72.0_dp, 72.0_dp)
        call ts_set_font(10.0_dp)
        PAGE_NUMBERS = .true.
        HEADINGS = .false.
        FLUSH_BOTTOM = .false.
        TEXT_COLOR = 0
        PAGE_COLOR = 16777215
    end subroutine ts_reset

    ! The colours of the text and of the page, as 0xRRGGBB.
    subroutine ts_set_colors(text, page)
        integer, intent(in) :: text, page
        TEXT_COLOR = text
        PAGE_COLOR = page
    end subroutine ts_set_colors

    pure real(dp) function ts_hsize()
        ts_hsize = HSIZE
    end function ts_hsize

    pure real(dp) function ts_font_size()
        ts_font_size = FONT_SIZE
    end function ts_font_size

    subroutine ts_set_page(w, h, left, right, top, bottom, numbers, headings_, flush)
        real(dp), intent(in) :: w, h, left, right, top, bottom
        logical, intent(in), optional :: numbers, headings_, flush
        PAPER_W = w
        PAPER_H = h
        MARGIN_L = left
        MARGIN_R = right
        MARGIN_T = top
        MARGIN_B = bottom
        HSIZE = w - left - right
        VSIZE = h - top - bottom
        if (present(numbers)) PAGE_NUMBERS = numbers
        if (present(headings_)) HEADINGS = headings_
        if (present(flush)) FLUSH_BOTTOM = flush
    end subroutine ts_set_page

    ! The body size and what goes with it, LaTeX's lengths scaled from its
    ! 10pt ones: \baselineskip 1.2 em, \parskip 0pt plus 1pt, \topskip one
    ! em, \maxdepth half of it, \footskip 30pt.
    subroutine ts_set_font(size, leading)
        real(dp), intent(in) :: size
        real(dp), intent(in), optional :: leading
        FONT_SIZE = size
        BASELINESKIP = ts_glue_t(1.2_dp*size, 0.0_dp, 0.0_dp, 0, 0)
        if (present(leading)) BASELINESKIP%w = leading
        LINESKIP = ts_glue_t(1.0_dp, 0.0_dp, 0.0_dp, 0, 0)
        LINESKIPLIMIT = 0.0_dp
        PARSKIP = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        TOPSKIP = size
        MAXDEPTH = 0.5_dp*size
        FOOTSKIP = 3.0_dp*size
        CUR_BASELINE = BASELINESKIP
    end subroutine ts_set_font

    pure real(dp) function ts_xheight(size)
        real(dp), intent(in) :: size
        ts_xheight = face_xheight(FACE_REGULAR)*size
    end function ts_xheight

    pure real(dp) function ts_quad(size)
        real(dp), intent(in) :: size
        ts_quad = size
    end function ts_quad

    pure logical function ts_in_par()
        ts_in_par = IN_PAR
    end function ts_in_par

    subroutine ts_page_size(w, h, color)
        real(dp), intent(out) :: w, h
        integer, intent(out), optional :: color
        w = PAPER_W
        h = PAPER_H
        if (present(color)) color = PAGE_COLOR
    end subroutine ts_page_size

    ! The glue \parskip puts between paragraphs from here on.
    subroutine ts_set_parskip(g)
        type(ts_glue_t), intent(in) :: g
        PARSKIP = g
    end subroutine ts_set_parskip

    subroutine ts_set_clubpenalty(p)
        integer, intent(in) :: p
        CLUB_PENALTY = p
    end subroutine ts_set_clubpenalty

    ! ------------------------------------------------------------------
    ! The horizontal list.
    ! ------------------------------------------------------------------

    ! Start a paragraph: its alignment, how far its lines are moved in
    ! from the left and right margins, its indentation (0 for none), and a
    ! hanging indentation of all lines but the first.
    subroutine ts_begin_par(align, indent, left, right, size, hang, skip, leading, &
                            nobreak)
        integer, intent(in) :: align
        real(dp), intent(in) :: indent
        real(dp), intent(in), optional :: left, right, size, hang, leading
        logical, intent(in), optional :: skip, nobreak
        logical :: sk
        if (IN_PAR) call ts_end_par()
        IN_PAR = .true.
        P_ALIGN = align
        P_LEFT = 0.0_dp
        P_RIGHT = 0.0_dp
        P_HANG = 0.0_dp
        P_SIZE = FONT_SIZE
        P_NOBREAK = .false.
        CUR_BASELINE = BASELINESKIP
        if (present(left)) P_LEFT = left
        if (present(right)) P_RIGHT = right
        if (present(size)) P_SIZE = size
        if (present(hang)) P_HANG = hang
        if (present(leading)) CUR_BASELINE%w = leading
        if (present(nobreak)) P_NOBREAK = nobreak
        P_SF = 1000.0_dp
        P_PREV_GRAF = 0
        HN = 0
        NCP = 0
        NBX = 0
        ! \parskip goes between paragraphs, not at the top of the list.
        sk = .true.
        if (present(skip)) sk = skip
        if (sk .and. NV > 0) call v_glue(PARSKIP)
        if (indent > 0.0_dp) then
            call h_new(HK_BOX)
            HW(HN) = indent
            HI0(HN) = 1
            HI1(HN) = 0
        end if
    end subroutine ts_begin_par

    ! Words: s is one word or a piece of one (no spaces), in face at size.
    ! Explicit hyphens in it are places it may break, as TeX's
    ! \exhyphenpenalty allows.
    subroutine ts_word(s, face, size, color, raise)
        character(len=*), intent(in) :: s
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        integer, intent(in), optional :: color
        real(dp), intent(in), optional :: raise
        integer, allocatable :: cps(:)
        integer :: n, k, k0, col
        real(dp) :: up
        if (.not. IN_PAR) call ts_begin_par(ALIGN_JUSTIFY, 0.0_dp)
        col = TEXT_COLOR
        if (present(color)) col = color
        up = 0.0_dp
        if (present(raise)) up = raise
        call code_points(s, cps, n)
        k0 = 1
        do k = 1, n
            ! A hyphen ends a piece, and a discretionary with nothing
            ! before the break follows it.
            if (cps(k) == 45 .and. k > 1 .and. k < n) then
                call word_piece(cps(k0:k), face, size, col, up)
                call h_new(HK_DISC)
                HFACE(HN) = face
                HSZ(HN) = size
                HC0(HN) = 0
                HW(HN) = 0.0_dp
                k0 = k + 1
            end if
        end do
        if (k0 <= n) call word_piece(cps(k0:n), face, size, col, up)
    end subroutine ts_word

    subroutine word_piece(cps, face, fs, col, up)
        integer, intent(in) :: cps(:), face, col
        real(dp), intent(in) :: fs, up
        integer :: k
        call h_new(HK_WORD)
        call cp_reserve(size(cps))
        HC0(HN) = NCP + 1
        CPA(NCP + 1:NCP + size(cps)) = cps
        NCP = NCP + size(cps)
        HC1(HN) = NCP
        HFACE(HN) = face
        HSZ(HN) = fs
        HCOL(HN) = col
        HRAISE(HN) = up
        call measure(HN)
        do k = 1, size(cps)
            call space_factor(cps(k))
        end do
    end subroutine word_piece

    ! TeX's \sfcode and its rule for the space factor (\nonfrenchspacing:
    ! 3000 after a full stop, 2000 after a colon and so on, 999 for a
    ! capital letter, which keeps the space after an initial normal, and 0
    ! for closing brackets and quotes, which leave it as it was).
    subroutine space_factor(cp)
        integer, intent(in) :: cp
        real(dp) :: s
        select case (cp)
        case (46, 63, 33)
            s = 3000.0_dp
        case (58)
            s = 2000.0_dp
        case (59)
            s = 1500.0_dp
        case (44)
            s = 1250.0_dp
        case (41, 93, 39, 8217, 8221)
            s = 0.0_dp
        case (65:90, 192:214, 216:222)
            s = 999.0_dp
        case default
            s = 1000.0_dp
            if (cp >= 256 .and. cp < 384 .and. mod(cp, 2) == 0) s = 999.0_dp
        end select
        if (s == 1000.0_dp) then
            P_SF = 1000.0_dp
        else if (s < 1000.0_dp) then
            if (s > 0.0_dp) P_SF = s
        else if (P_SF < 1000.0_dp) then
            P_SF = 1000.0_dp
        else
            P_SF = s
        end if
    end subroutine space_factor

    ! The glyph a code point is set as in a face: the face's own, else
    ! the regular face's, else the math font's, else a space.
    integer function glyph_for(face, cp, gf) result(g)
        integer, intent(in) :: face, cp
        integer, intent(out) :: gf
        gf = face
        g = glyph_cmap(face, cp)
        if (g /= 0) return
        gf = FACE_REGULAR
        g = glyph_cmap(FACE_REGULAR, cp)
        if (g /= 0) return
        gf = FACE_MATH
        g = glyph_cmap(FACE_MATH, cp)
        if (g /= 0) return
        gf = face
        g = glyph_cmap(face, 32)
    end function glyph_for

    ! A word's width, height and depth: its glyphs' advances and kerning,
    ! and their ink, as XeTeX measures a word.
    subroutine measure(i)
        integer, intent(in) :: i
        call shape(CPA(HC0(i):HC1(i)), HFACE(i), HSZ(i), HW(i), HH(i), HD(i))
    end subroutine measure

    subroutine shape(cps, face, s, w, h, d)
        integer, intent(in) :: cps(:), face
        real(dp), intent(in) :: s
        real(dp), intent(out) :: w, h, d
        integer :: k, g, prev, gf, pf
        real(dp) :: x0, y0, x1, y1
        w = 0.0_dp
        h = 0.0_dp
        d = 0.0_dp
        prev = 0
        pf = 0
        do k = 1, size(cps)
            g = glyph_for(face, cps(k), gf)
            if (prev > 0 .and. gf == pf) w = w + glyph_kern(gf, prev, g)*s
            w = w + glyph_adv(g)*s
            call glyph_bbox(g, x0, y0, x1, y1)
            h = max(h, y1*s)
            d = max(d, -y0*s)
            prev = g
            pf = gf
        end do
    end subroutine shape

    ! The space between words, in face at size: XeTeX's glue for an
    ! OpenType font, the width of the space with half of it to stretch and
    ! a third to shrink, adjusted by the space factor.
    subroutine ts_space(face, size)
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        real(dp) :: sp
        integer :: gf
        if (.not. IN_PAR) return
        if (HN == 0) return
        if (HK(HN) == HK_GLUE) return
        sp = glyph_adv(glyph_for(face, 32, gf))*size
        call h_new(HK_GLUE)
        HW(HN) = sp
        HST(HN) = sp/2.0_dp
        HSH(HN) = sp/3.0_dp
        if (P_SF /= 1000.0_dp) then
            if (P_SF >= 2000.0_dp) HW(HN) = HW(HN) + sp/3.0_dp
            HST(HN) = HST(HN)*P_SF/1000.0_dp
            HSH(HN) = HSH(HN)*1000.0_dp/P_SF
        end if
    end subroutine ts_space

    ! A space that does not break: the same glue behind a penalty.
    subroutine ts_nbsp(face, size)
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        if (.not. IN_PAR) call ts_begin_par(ALIGN_JUSTIFY, 0.0_dp)
        P_SF = 1000.0_dp
        call h_new(HK_PEN)
        HP(HN) = INF_PENALTY
        call ts_space(face, size)
        if (HK(HN) /= HK_GLUE) then
            HN = HN - 1
        end if
    end subroutine ts_nbsp

    ! Infinitely stretchable glue, \hfil, and a fixed kern.
    subroutine ts_hfil()
        call h_new(HK_GLUE)
        HSO(HN) = 1
        HST(HN) = 1.0_dp
    end subroutine ts_hfil

    subroutine ts_kern(w)
        real(dp), intent(in) :: w
        call h_new(HK_KERN)
        HW(HN) = w
        HEXPL(HN) = .true.
    end subroutine ts_kern

    ! An inline formula, set in text style as one box.
    subroutine ts_math(src, size, color)
        character(len=*), intent(in) :: src
        real(dp), intent(in) :: size
        integer, intent(in), optional :: color
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        real(dp) :: w, h, d
        integer :: col
        if (.not. IN_PAR) call ts_begin_par(ALIGN_JUSTIFY, 0.0_dp)
        col = TEXT_COLOR
        if (present(color)) col = color
        call math_formula(src, size, .false., run, rules, w, h, d)
        call h_new(HK_BOX)
        HW(HN) = w
        HH(HN) = h
        HD(HN) = d
        call box_items(run, rules, col, HI0(HN), HI1(HN))
        P_SF = 1000.0_dp
    end subroutine ts_math

    ! A label hung to the left of the paragraph's first line, ending sep
    ! before the text, as a LaTeX \item puts it; a penalty of 0 follows,
    ! as there.
    subroutine ts_label(s, face, size, sep, color)
        character(len=*), intent(in) :: s
        integer, intent(in) :: face
        real(dp), intent(in) :: size, sep
        integer, intent(in), optional :: color
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        integer, allocatable :: cps(:)
        integer :: n, k, g, gf, prev, pf, col
        real(dp) :: pen, w
        col = TEXT_COLOR
        if (present(color)) col = color
        call code_points(s, cps, n)
        pen = 0.0_dp
        prev = 0
        pf = 0
        do k = 1, n
            g = glyph_for(face, cps(k), gf)
            if (prev > 0 .and. gf == pf) pen = pen + glyph_kern(gf, prev, g)*size
            call run_add(run, g, pen, 0.0_dp, size)
            pen = pen + glyph_adv(g)*size
            prev = g
            pf = gf
        end do
        w = pen
        do k = 1, run%n
            run%x(k) = run%x(k) - sep - w
        end do
        call h_new(HK_BOX)
        HW(HN) = 0.0_dp
        HH(HN) = 0.0_dp
        HD(HN) = 0.0_dp
        call box_items(run, rules, col, HI0(HN), HI1(HN))
        call h_new(HK_PEN)
        HP(HN) = 0
    end subroutine ts_label

    ! A line break within the paragraph, LaTeX's \\: in justified or
    ! ragged right text \nobreak\hfil\break; in centred or ragged left
    ! text the paragraph ends and a new one goes on with the same settings,
    ! as \centering's \\ does.
    subroutine ts_hard_break()
        integer :: al
        real(dp) :: l, r, s, hg, lead
        logical :: nb
        if (.not. IN_PAR) return
        do while (HN > 0)
            if (HK(HN) /= HK_GLUE) exit
            HN = HN - 1
        end do
        if (P_ALIGN == ALIGN_CENTER .or. P_ALIGN == ALIGN_RIGHT) then
            al = P_ALIGN
            l = P_LEFT
            r = P_RIGHT
            s = P_SIZE
            hg = P_HANG
            lead = CUR_BASELINE%w
            nb = P_NOBREAK
            call ts_end_par()
            call ts_begin_par(al, 0.0_dp, l, r, s, hg, skip=.false., leading=lead, &
                              nobreak=nb)
            return
        end if
        call h_new(HK_PEN)
        HP(HN) = INF_PENALTY
        call ts_hfil()
        call h_new(HK_PEN)
        HP(HN) = EJECT_PENALTY
    end subroutine ts_hard_break

    ! ------------------------------------------------------------------
    ! Line breaking.
    ! ------------------------------------------------------------------

    ! End the paragraph: break it into lines and put them on the vertical
    ! list.
    subroutine ts_end_par()
        if (.not. IN_PAR) return
        IN_PAR = .false.
        if (HN > 0) then
            call line_break(.false.)
            NOBREAK_NEXT = .false.
        end if
        CUR_BASELINE = BASELINESKIP
    end subroutine ts_end_par

    ! TeX's line_break. d is true when a display follows, which changes
    ! the penalty before the last line.
    subroutine line_break(d)
        logical, intent(in) :: d
        type(ts_glue_t) :: lskip, rskip, pfill
        integer :: nlines
        integer, allocatable :: brk(:)
        logical, allocatable :: hyph(:)

        ! The glue at the end goes, and \penalty10000 \parfillskip comes.
        if (HK(HN) == HK_GLUE) HN = HN - 1
        call align_glue(lskip, rskip, pfill)
        call h_new(HK_PEN)
        HP(HN) = INF_PENALTY
        call h_new(HK_GLUE)
        HW(HN) = pfill%w
        HST(HN) = pfill%st
        HSO(HN) = pfill%sto

        call find_breaks(lskip, rskip, brk, hyph, nlines)
        call post_line_break(lskip, rskip, brk, hyph, nlines, d)
    end subroutine line_break

    ! \leftskip, \rightskip and \parfillskip for the alignment, LaTeX's:
    ! \raggedright, \centering and \raggedleft use \@flushglue.
    subroutine align_glue(lskip, rskip, pfill)
        type(ts_glue_t), intent(out) :: lskip, rskip, pfill
        type(ts_glue_t), parameter :: FIL = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0)
        lskip = ts_glue_t()
        rskip = ts_glue_t()
        pfill = FIL
        select case (P_ALIGN)
        case (ALIGN_LEFT)
            rskip = FIL
        case (ALIGN_CENTER)
            lskip = FIL
            rskip = FIL
            pfill = ts_glue_t()
        case (ALIGN_RIGHT)
            lskip = FIL
            pfill = ts_glue_t()
        end select
    end subroutine align_glue

    ! TeX's badness, from the shortfall t and the stretch or shrink s, in
    ! scaled points: about 100 (t/s)^3.
    pure integer function badness(tb, sb)
        real(dp), intent(in) :: tb, sb
        integer(8) :: t, s, r
        t = nint(tb*SP_PER_BP, 8)
        s = nint(sb*SP_PER_BP, 8)
        if (t == 0) then
            badness = 0
        else if (s <= 0) then
            badness = INF_BAD
        else
            if (t <= 7230584_8) then
                r = (t*297_8)/s
            else if (s >= 1663497_8) then
                r = t/(s/297_8)
            else
                r = t
            end if
            if (r > 1290_8) then
                badness = INF_BAD
            else
                badness = int((r*r*r + 131072_8)/262144_8)
            end if
        end if
    end function badness

    ! Knuth and Plass: the breaks of least total demerits, brk(1..n) the
    ! nodes the n lines end at (HN + 1 for the end of the paragraph) and
    ! hyph(k) whether line k ends at a hyphen.
    subroutine find_breaks(lskip, rskip, brk, hyph, nlines)
        type(ts_glue_t), intent(in) :: lskip, rskip
        integer, allocatable, intent(out) :: brk(:)
        logical, allocatable, intent(out) :: hyph(:)
        integer, intent(out) :: nlines
        ! Prefix sums of the list: natural width, finite stretch, fil,
        ! fill and filll stretch, and shrink, of nodes 1..k.
        real(dp), allocatable :: sw(:, :)
        ! Active nodes: the break (passive node) they stand for, line
        ! number, fitness, whether hyphenated, total demerits, next.
        integer, allocatable :: a_pas(:), a_line(:), a_fit(:), a_next(:)
        logical, allocatable :: a_hyph(:)
        integer(8), allocatable :: a_dem(:)
        ! Passive nodes: where the break is, the passive node before it.
        integer, allocatable :: p_at(:), p_prev(:)
        logical, allocatable :: p_hyph(:)
        integer :: na, np, head, threshold, pass, cur, r, prev_r, l
        integer :: fit, b, pi, k, best, bestl(0:3), best_pl(0:3), bp
        integer(8) :: mind(0:3), minimum, fewest
        logical :: second, final, artificial, stays, ishyph, legal, hyphenated
        real(dp) :: bg(6), cw(6), shortfall, linew, discw
        integer :: start, nfree

        nlines = 0
        hyphenated = .false.
        bg = 0.0_dp
        call add_glue(bg, lskip%w, lskip%st, lskip%sto, lskip%sh)
        call add_glue(bg, rskip%w, rskip%st, rskip%sto, rskip%sh)

        if (PRETOLERANCE >= 0) then
            threshold = PRETOLERANCE
            second = .false.
            final = .false.
        else
            threshold = TOLERANCE
            second = .true.
            final = .true.
        end if

        do pass = 1, 3
            if (second .and. .not. hyphenated) then
                call hyphenate_all()
                hyphenated = .true.
            end if
            if (allocated(sw)) deallocate (sw)
            allocate (sw(6, 0:HN))
            call prefix_sums(sw)
            nfree = 4*HN + 16
            if (allocated(a_pas)) deallocate (a_pas, a_line, a_fit, a_next, a_hyph, a_dem, &
                                              p_at, p_prev, p_hyph)
            allocate (a_pas(nfree), a_line(nfree), a_fit(nfree), a_next(nfree), &
                      a_hyph(nfree), a_dem(nfree))
            allocate (p_at(nfree), p_prev(nfree), p_hyph(nfree))
            ! The active list starts with a node for the paragraph's start.
            ! An active node's line number is that of the line it starts.
            na = 1
            np = 0
            head = 1
            a_pas(1) = 0
            a_line(1) = P_PREV_GRAF + 1
            a_fit(1) = DECENT
            a_hyph(1) = .false.
            a_dem(1) = 0
            a_next(1) = 0

            cur = 1
            do while (cur <= HN + 1 .and. head /= 0)
                legal = .false.
                pi = 0
                ishyph = .false.
                discw = 0.0_dp
                if (cur == HN + 1) then
                    legal = .true.
                    pi = EJECT_PENALTY
                    ishyph = .true.
                else
                    select case (HK(cur))
                    case (HK_GLUE)
                        if (cur > 1) legal = precedes_break(cur - 1)
                    case (HK_KERN)
                        if (HEXPL(cur) .and. cur < HN) legal = HK(cur + 1) == HK_GLUE
                    case (HK_PEN)
                        legal = HP(cur) < INF_PENALTY
                        pi = HP(cur)
                    case (HK_DISC)
                        legal = .true.
                        ishyph = .true.
                        discw = HW(cur)
                        if (HC0(cur) == 0) then
                            pi = EX_HYPHEN_PENALTY
                        else
                            pi = HYPHEN_PENALTY
                        end if
                    end select
                end if
                if (legal) call try_break()
                cur = cur + 1
            end do

            if (head /= 0) then
                ! The active node of fewest demerits ends the paragraph.
                fewest = huge(1_8)
                best = 0
                r = head
                do while (r /= 0)
                    if (a_dem(r) < fewest) then
                        fewest = a_dem(r)
                        best = r
                    end if
                    r = a_next(r)
                end do
                nlines = a_line(best) - 1 - P_PREV_GRAF
                allocate (brk(nlines), hyph(nlines))
                bp = a_pas(best)
                do k = nlines, 1, -1
                    brk(k) = p_at(bp)
                    hyph(k) = p_hyph(bp)
                    bp = p_prev(bp)
                end do
                return
            end if

            if (.not. second) then
                threshold = TOLERANCE
                second = .true.
                final = .true.
            else
                final = .true.
            end if
        end do
        error stop "fplotlib: line breaking failed"

    contains

        ! A glue node is a legal break when what precedes it is not
        ! discardable: a word, a box, a discretionary, or a font kern.
        logical function precedes_break(i)
            integer, intent(in) :: i
            precedes_break = HK(i) == HK_WORD .or. HK(i) == HK_BOX .or. &
                             HK(i) == HK_DISC .or. (HK(i) == HK_KERN .and. .not. HEXPL(i))
        end function precedes_break

        ! TeX's try_break(pi, break_type) at node cur.
        subroutine try_break()
            integer :: old_l
            integer(8) :: dd
            if (abs(pi) >= INF_PENALTY) then
                if (pi > 0) return
                pi = EJECT_PENALTY
            end if
            mind = int(AWFUL_BAD, 8)
            minimum = int(AWFUL_BAD, 8)
            old_l = 0
            prev_r = 0
            r = head
            do
                if (r /= 0) then
                    l = a_line(r)
                else
                    l = huge(1)
                end if
                if (l > old_l) then
                    ! Every line has the same width but the first when
                    ! there is a hanging indentation, so one class of
                    ! line numbers ends after line 1 and the other at
                    ! the end of the active list.
                    if (minimum < int(AWFUL_BAD, 8) .and. (old_l /= easy_line() .or. r == 0)) then
                        call new_active(prev_r)
                        minimum = int(AWFUL_BAD, 8)
                        mind = int(AWFUL_BAD, 8)
                    end if
                    if (r == 0) return
                    linew = line_width(l)
                    if (l > easy_line()) then
                        old_l = huge(1) - 1
                    else
                        old_l = l
                    end if
                end if

                ! The line from r to cur.
                start = line_start(a_pas(r))
                call line_totals(start, cw)
                shortfall = linew - cw(1)
                artificial = .false.
                if (shortfall > 0.0_dp) then
                    if (cw(3) /= 0.0_dp .or. cw(4) /= 0.0_dp .or. cw(5) /= 0.0_dp) then
                        b = 0
                        fit = DECENT
                    else
                        if (nint(shortfall*SP_PER_BP, 8) > 7230584_8 .and. &
                            nint(cw(2)*SP_PER_BP, 8) < 1663497_8) then
                            b = INF_BAD
                            fit = VERY_LOOSE
                        else
                            b = badness(shortfall, cw(2))
                            if (b > 12) then
                                if (b > 99) then
                                    fit = VERY_LOOSE
                                else
                                    fit = LOOSE
                                end if
                            else
                                fit = DECENT
                            end if
                        end if
                    end if
                else
                    if (-shortfall > cw(6)) then
                        b = INF_BAD + 1
                    else
                        b = badness(-shortfall, cw(6))
                    end if
                    if (b > 12) then
                        fit = TIGHT
                    else
                        fit = DECENT
                    end if
                end if

                if (b > INF_BAD .or. pi == EJECT_PENALTY) then
                    if (final .and. minimum == int(AWFUL_BAD, 8) .and. &
                        a_next(r) == 0 .and. prev_r == 0) then
                        artificial = .true.
                    else if (b > threshold) then
                        call deactivate()
                        cycle
                    end if
                    stays = .false.
                else
                    prev_r = r
                    if (b > threshold) then
                        r = a_next(r)
                        cycle
                    end if
                    stays = .true.
                end if

                ! Record a feasible break.
                if (artificial) then
                    dd = 0
                else
                    dd = LINE_PENALTY + b
                    if (abs(dd) >= 10000) then
                        dd = 100000000_8
                    else
                        dd = dd*dd
                    end if
                    if (pi /= 0) then
                        if (pi > 0) then
                            dd = dd + int(pi, 8)*pi
                        else if (pi > EJECT_PENALTY) then
                            dd = dd - int(pi, 8)*pi
                        end if
                    end if
                    if (ishyph .and. a_hyph(r)) then
                        if (cur <= HN) then
                            dd = dd + DOUBLE_HYPHEN_DEMERITS
                        else
                            dd = dd + FINAL_HYPHEN_DEMERITS
                        end if
                    end if
                    if (abs(fit - a_fit(r)) > 1) dd = dd + ADJ_DEMERITS
                end if
                dd = dd + a_dem(r)
                if (dd <= mind(fit)) then
                    mind(fit) = dd
                    best_pl(fit) = a_pas(r)
                    bestl(fit) = l
                    if (dd < minimum) minimum = dd
                end if
                if (stays) then
                    r = a_next(r)
                    cycle
                end if
                call deactivate()
            end do
        end subroutine try_break

        ! Remove r from the active list; r becomes the one after it.
        subroutine deactivate()
            integer :: nx
            nx = a_next(r)
            if (prev_r == 0) then
                head = nx
            else
                a_next(prev_r) = nx
            end if
            r = nx
        end subroutine deactivate

        ! Insert active nodes for the best breaks of each fitness class
        ! found, before r (after prev_r), as TeX does.
        subroutine new_active(after)
            integer, intent(in) :: after
            integer :: fc, ins
            integer(8) :: lim
            lim = minimum
            if (lim <= int(AWFUL_BAD, 8) - ADJ_DEMERITS) then
                lim = lim + abs(ADJ_DEMERITS)
            else
                lim = int(AWFUL_BAD, 8) - 1
            end if
            ins = after
            do fc = VERY_LOOSE, TIGHT
                if (mind(fc) <= lim) then
                    np = np + 1
                    p_at(np) = cur
                    p_prev(np) = best_pl(fc)
                    p_hyph(np) = ishyph
                    na = na + 1
                    a_pas(na) = np
                    a_line(na) = bestl(fc) + 1
                    a_fit(na) = fc
                    a_hyph(na) = ishyph
                    a_dem(na) = mind(fc)
                    if (ins == 0) then
                        a_next(na) = head
                        head = na
                    else
                        a_next(na) = a_next(ins)
                        a_next(ins) = na
                    end if
                    ins = na
                end if
            end do
            prev_r = ins
        end subroutine new_active

        ! The first node of a line after the break at passive node p:
        ! what follows the break, its glue, kerns and penalties discarded.
        integer function line_start(p) result(s)
            integer, intent(in) :: p
            integer :: at
            if (p == 0) then
                s = 1
                return
            end if
            at = p_at(p)
            s = at + 1
            if (at <= HN) then
                if (HK(at) == HK_DISC) return
            end if
            do while (s <= HN)
                select case (HK(s))
                case (HK_GLUE, HK_PEN)
                    s = s + 1
                case (HK_KERN)
                    if (.not. HEXPL(s)) exit
                    s = s + 1
                case default
                    exit
                end select
            end do
        end function line_start

        ! The totals of the line from start to the break at cur: the
        ! background, the nodes before cur, and a discretionary's hyphen.
        subroutine line_totals(start, t)
            integer, intent(in) :: start
            real(dp), intent(out) :: t(6)
            integer :: last
            last = cur - 1
            if (cur == HN + 1) last = HN
            t = bg
            if (last >= start) t = t + sw(:, last) - sw(:, start - 1)
            t(1) = t(1) + discw
        end subroutine line_totals

        subroutine prefix_sums(s)
            real(dp), intent(inout) :: s(:, 0:)
            integer :: i
            s(:, 0) = 0.0_dp
            do i = 1, HN
                s(:, i) = s(:, i - 1)
                select case (HK(i))
                case (HK_WORD, HK_BOX, HK_KERN)
                    s(1, i) = s(1, i) + HW(i)
                case (HK_GLUE)
                    call add_glue(s(:, i), HW(i), HST(i), HSO(i), HSH(i))
                end select
            end do
        end subroutine prefix_sums

    end subroutine find_breaks

    subroutine add_glue(t, w, st, sto, sh)
        real(dp), intent(inout) :: t(6)
        real(dp), intent(in) :: w, st, sh
        integer, intent(in) :: sto
        t(1) = t(1) + w
        t(2 + sto) = t(2 + sto) + st
        t(6) = t(6) + sh
    end subroutine add_glue

    ! The line number up to which lines are special (have widths of their
    ! own): the first, when there is a hanging indentation.
    pure integer function easy_line()
        if (P_HANG /= 0.0_dp) then
            easy_line = 1
        else
            easy_line = 0
        end if
    end function easy_line

    ! The width of line l of the paragraph.
    pure real(dp) function line_width(l)
        integer, intent(in) :: l
        line_width = HSIZE - P_LEFT - P_RIGHT
        if (l > 1) line_width = line_width - abs(P_HANG)
    end function line_width

    ! Where line l starts, from the left margin.
    pure real(dp) function line_indent(l)
        integer, intent(in) :: l
        line_indent = P_LEFT
        if (l > 1 .and. P_HANG > 0.0_dp) line_indent = line_indent + P_HANG
    end function line_indent

    ! TeX's second pass hyphenates every word that follows glue: each such
    ! word is cut where letters meet other characters, as XeTeX cuts a
    ! word of an OpenType font, and its letters are cut again at the
    ! places the patterns allow, with a discretionary hyphen in each cut.
    ! The pieces are measured separately, as in XeTeX.
    subroutine hyphenate_all()
        integer :: i, j, k, a, b, n, npos, pos(64), m
        character(len=64) :: lw
        logical :: ok
        i = 1
        do while (i <= HN)
            if (HK(i) /= HK_GLUE) then
                i = i + 1
                cycle
            end if
            j = i + 1
            if (j > HN) exit
            if (HK(j) /= HK_WORD) then
                i = i + 1
                cycle
            end if
            ! What may follow the word for it to be hyphenated: glue, a
            ! penalty, a font kern, another word, or nothing; anything
            ! else and it is left whole.
            ok = .true.
            if (j < HN) then
                select case (HK(j + 1))
                case (HK_GLUE, HK_PEN, HK_WORD)
                case (HK_KERN)
                    ok = .not. HEXPL(j + 1)
                case default
                    ok = .false.
                end select
            end if
            if (.not. ok) then
                i = j + 1
                cycle
            end if
            ! The first letter, which must be in the word.
            a = 0
            do k = HC0(j), HC1(j)
                if (is_letter(CPA(k))) then
                    a = k
                    exit
                end if
            end do
            if (a == 0) then
                i = j + 1
                cycle
            end if
            if (a > HC0(j)) then
                call split_word(j, a)
                j = j + 1
            end if
            ! The letters run to b.
            b = HC1(j)
            do k = HC0(j), HC1(j)
                if (.not. is_letter(CPA(k))) then
                    b = k - 1
                    exit
                end if
            end do
            if (b < HC1(j)) call split_word(j, b + 1)
            n = b - HC0(j) + 1
            if (n < LEFT_HYPHEN_MIN + RIGHT_HYPHEN_MIN .or. n > 63) then
                i = j + 1
                cycle
            end if
            do k = 1, n
                lw(k:k) = lower(CPA(HC0(j) + k - 1))
            end do
            call hyph_points(lw(1:n), LEFT_HYPHEN_MIN, RIGHT_HYPHEN_MIN, pos, npos)
            ! Cut from the end, so that the earlier positions stay valid.
            do m = npos, 1, -1
                call split_word(j, HC0(j) + pos(m))
                call insert_disc(j + 1)
            end do
            i = j + 1
        end do
    end subroutine hyphenate_all

    ! Node j becomes two words, the second starting at code point c.
    subroutine split_word(j, c)
        integer, intent(in) :: j, c
        call h_insert(j + 1)
        HK(j + 1) = HK_WORD
        HFACE(j + 1) = HFACE(j)
        HSZ(j + 1) = HSZ(j)
        HCOL(j + 1) = HCOL(j)
        HC0(j + 1) = c
        HC1(j + 1) = HC1(j)
        HC1(j) = c - 1
        call measure(j)
        call measure(j + 1)
    end subroutine split_word

    ! A discretionary hyphen at position j, in the face of the word
    ! before it.
    subroutine insert_disc(j)
        integer, intent(in) :: j
        integer :: gf
        call h_insert(j)
        HK(j) = HK_DISC
        HFACE(j) = HFACE(j - 1)
        HSZ(j) = HSZ(j - 1)
        HCOL(j) = HCOL(j - 1)
        HC0(j) = 45
        HW(j) = glyph_adv(glyph_for(HFACE(j), 45, gf))*HSZ(j)
    end subroutine insert_disc

    ! Letters are what TeX gives a \lccode: the Latin, Greek and Cyrillic
    ! letters of the repertoire.
    pure logical function is_letter(cp)
        integer, intent(in) :: cp
        is_letter = (cp >= 65 .and. cp <= 90) .or. (cp >= 97 .and. cp <= 122) .or. &
                    (cp >= 192 .and. cp <= 591 .and. cp /= 215 .and. cp /= 247) .or. &
                    (cp >= 880 .and. cp <= 1279)
    end function is_letter

    ! The letter as the patterns know it: a..z, and anything else as a
    ! character no pattern has.
    pure character function lower(cp)
        integer, intent(in) :: cp
        if (cp >= 65 .and. cp <= 90) then
            lower = achar(cp + 32)
        else if (cp >= 97 .and. cp <= 122) then
            lower = achar(cp)
        else
            lower = "#"
        end if
    end function lower

    ! ------------------------------------------------------------------
    ! Lines into boxes.
    ! ------------------------------------------------------------------

    ! TeX's post_line_break: each line packed to its width, with \leftskip
    ! and \rightskip, and appended to the vertical list with the penalties
    ! between lines.
    subroutine post_line_break(lskip, rskip, brk, hyph, nlines, d)
        type(ts_glue_t), intent(in) :: lskip, rskip
        integer, intent(in) :: brk(:), nlines
        logical, intent(in) :: hyph(:), d
        integer :: l, s, e, pen, best_line, cur_line
        real(dp) :: w, h, dp_
        integer :: i0, i1
        s = 1
        best_line = P_PREV_GRAF + nlines + 1
        LAST_PAR0 = NV + 1
        do l = 1, nlines
            cur_line = P_PREV_GRAF + l
            e = brk(l)
            call pack_line(s, e, lskip, rskip, line_width(cur_line), i0, i1, w, h, dp_)
            call append_box(i0, i1, w, h, dp_, line_indent(cur_line))
            if (cur_line + 1 /= best_line) then
                pen = INTERLINE_PENALTY
                if (P_NOBREAK) pen = INF_PENALTY
                if (cur_line == P_PREV_GRAF + 1) then
                    if (NOBREAK_NEXT) then
                        pen = pen + INF_PENALTY
                    else
                        pen = pen + CLUB_PENALTY
                    end if
                end if
                if (cur_line + 2 == best_line) then
                    if (d) then
                        pen = pen + DISPLAY_WIDOW_PENALTY
                    else
                        pen = pen + WIDOW_PENALTY
                    end if
                end if
                if (hyph(l)) pen = pen + BROKEN_PENALTY
                if (pen /= 0) call ts_penalty(min(pen, INF_PENALTY))
            end if
            ! The next line starts after the break, discardables dropped.
            s = e + 1
            if (e <= HN) then
                if (HK(e) /= HK_DISC) then
                    do while (s <= HN)
                        if (HK(s) == HK_GLUE .or. HK(s) == HK_PEN .or. &
                            (HK(s) == HK_KERN .and. HEXPL(s))) then
                            s = s + 1
                        else
                            exit
                        end if
                    end do
                end if
            end if
        end do
        LAST_PAR1 = NV
        P_PREV_GRAF = P_PREV_GRAF + nlines
    end subroutine post_line_break

    ! Pack nodes s..e-1 (and the hyphen of a discretionary at e) into a
    ! line width wide: TeX's hpack, glue set to fit, shrink no further
    ! than its total. The items are appended to the item arena.
    subroutine pack_line(s, e, lskip, rskip, width, i0, i1, w, h, d)
        integer, intent(in) :: s, e
        type(ts_glue_t), intent(in) :: lskip, rskip
        real(dp), intent(in) :: width
        integer, intent(out) :: i0, i1
        real(dp), intent(out) :: w, h, d
        real(dp) :: t(6), x, ratio, gw, cw, ch, cd
        integer :: k, k1, last, ord, sgn
        logical :: hy
        last = min(e - 1, HN)
        t = 0.0_dp
        call add_glue(t, lskip%w, lskip%st, lskip%sto, lskip%sh)
        call add_glue(t, rskip%w, rskip%st, rskip%sto, rskip%sh)
        h = 0.0_dp
        d = 0.0_dp
        k = s
        do while (k <= last)
            select case (HK(k))
            case (HK_WORD)
                call chain(k, last, e, k1, hy)
                call chain_size(k, k1, hy, cw, ch, cd)
                t(1) = t(1) + cw
                h = max(h, ch + HRAISE(k))
                d = max(d, cd - HRAISE(k))
                k = k1
            case (HK_BOX)
                t(1) = t(1) + HW(k)
                h = max(h, HH(k) + HRAISE(k))
                d = max(d, HD(k) - HRAISE(k))
            case (HK_KERN)
                t(1) = t(1) + HW(k)
            case (HK_GLUE)
                call add_glue(t, HW(k), HST(k), HSO(k), HSH(k))
            end select
            k = k + 1
        end do
        ! A hyphen not joined to a word before it stands alone.
        if (e <= HN) then
            if (HK(e) == HK_DISC .and. HC0(e) /= 0) then
                if (.not. joins_hyphen(last, e)) t(1) = t(1) + HW(e)
            end if
        end if
        x = width - t(1)
        sgn = 0
        ord = 0
        ratio = 0.0_dp
        if (x > 0.0_dp) then
            do ord = 3, 0, -1
                if (t(2 + ord) /= 0.0_dp) exit
            end do
            if (ord >= 0) then
                sgn = 1
                ratio = x/t(2 + ord)
            end if
        else if (x < 0.0_dp) then
            ord = 0
            if (t(6) /= 0.0_dp) then
                sgn = -1
                ratio = min(-x/t(6), 1.0_dp)
            end if
        end if

        i0 = NIT + 1
        x = glue_set(lskip%w, lskip%st, lskip%sto, lskip%sh)
        k = s
        do while (k <= last)
            select case (HK(k))
            case (HK_WORD)
                call chain(k, last, e, k1, hy)
                call emit_chain(k, k1, hy, x, cw)
                x = x + cw
                k = k1
            case (HK_BOX)
                call emit_box(k, x)
                x = x + HW(k)
            case (HK_KERN)
                x = x + HW(k)
            case (HK_GLUE)
                gw = glue_set(HW(k), HST(k), HSO(k), HSH(k))
                x = x + gw
            end select
            k = k + 1
        end do
        if (e <= HN) then
            if (HK(e) == HK_DISC .and. HC0(e) /= 0) then
                if (.not. joins_hyphen(last, e)) call emit_hyphen(e, x)
            end if
        end if
        i1 = NIT
        w = width

    contains

        real(dp) function glue_set(gw0, st, sto, sh) result(g)
            real(dp), intent(in) :: gw0, st, sh
            integer, intent(in) :: sto
            g = gw0
            if (sgn == 1 .and. sto == ord) g = g + ratio*st
            if (sgn == -1 .and. ord == 0) g = g - ratio*sh
        end function glue_set

    end subroutine pack_line

    ! XeTeX's hpack joins the fragments a word was cut into for
    ! hyphenation, and the hyphen of a break after them, back into one
    ! word, and shapes it again, so a line's words are kerned across the
    ! cuts even though the breaks were found without. A chain is the
    ! words k..k1 of one face, size and colour whose characters follow on
    ! from each other, with the discretionaries between them not taken;
    ! hy is whether the hyphen of the break at e ends it.
    subroutine chain(k, last, e, k1, hy)
        integer, intent(in) :: k, last, e
        integer, intent(out) :: k1
        logical, intent(out) :: hy
        integer :: n
        k1 = k
        do
            n = k1 + 1
            if (n > last) exit
            if (HK(n) == HK_DISC .and. n + 1 <= last) then
                if (same_font(k, n + 1) .and. HC0(n + 1) == HC1(k1) + 1) then
                    k1 = n + 1
                    cycle
                end if
            else if (HK(n) == HK_WORD) then
                if (same_font(k, n) .and. HC0(n) == HC1(k1) + 1) then
                    k1 = n
                    cycle
                end if
            end if
            exit
        end do
        hy = .false.
        if (k1 == last .and. e <= HN) hy = joins_hyphen(last, e)
    end subroutine chain

    logical function same_font(a, b)
        integer, intent(in) :: a, b
        same_font = HK(b) == HK_WORD .and. HFACE(a) == HFACE(b) .and. &
                    HSZ(a) == HSZ(b) .and. HCOL(a) == HCOL(b) .and. HRAISE(a) == HRAISE(b)
    end function same_font

    ! Whether the hyphen of the break at e is joined to the word at last.
    logical function joins_hyphen(last, e)
        integer, intent(in) :: last, e
        joins_hyphen = .false.
        if (last < 1 .or. e > HN) return
        if (HK(e) /= HK_DISC .or. HC0(e) == 0) return
        if (HK(last) /= HK_WORD) return
        joins_hyphen = HFACE(last) == HFACE(e) .and. HSZ(last) == HSZ(e) .and. &
                       HCOL(last) == HCOL(e)
    end function joins_hyphen

    ! The code points of a chain, with the hyphen when it has one.
    subroutine chain_cps(k, k1, hy, c)
        integer, intent(in) :: k, k1
        logical, intent(in) :: hy
        integer, allocatable, intent(out) :: c(:)
        integer :: n
        n = HC1(k1) - HC0(k) + 1
        if (hy) then
            allocate (c(n + 1))
            c(n + 1) = 45
        else
            allocate (c(n))
        end if
        c(1:n) = CPA(HC0(k):HC1(k1))
    end subroutine chain_cps

    subroutine chain_size(k, k1, hy, w, h, d)
        integer, intent(in) :: k, k1
        logical, intent(in) :: hy
        real(dp), intent(out) :: w, h, d
        integer, allocatable :: c(:)
        call chain_cps(k, k1, hy, c)
        call shape(c, HFACE(k), HSZ(k), w, h, d)
    end subroutine chain_size

    subroutine emit_chain(k, k1, hy, x0, w)
        integer, intent(in) :: k, k1
        logical, intent(in) :: hy
        real(dp), intent(in) :: x0
        real(dp), intent(out) :: w
        integer, allocatable :: c(:)
        integer :: j, g, gf, prev, pf
        real(dp) :: x, s
        call chain_cps(k, k1, hy, c)
        s = HSZ(k)
        x = x0
        prev = 0
        pf = 0
        do j = 1, size(c)
            g = glyph_for(HFACE(k), c(j), gf)
            if (prev > 0 .and. gf == pf) x = x + glyph_kern(gf, prev, g)*s
            call it_glyph(g, x, HRAISE(k), s, HCOL(k))
            x = x + glyph_adv(g)*s
            prev = g
            pf = gf
        end do
        w = x - x0
    end subroutine emit_chain

    subroutine emit_hyphen(k, x0)
        integer, intent(in) :: k
        real(dp), intent(in) :: x0
        integer :: gf
        call it_glyph(glyph_for(HFACE(k), 45, gf), x0, 0.0_dp, HSZ(k), HCOL(k))
    end subroutine emit_hyphen

    subroutine emit_box(k, x0)
        integer, intent(in) :: k
        real(dp), intent(in) :: x0
        integer :: j
        do j = HI0(k), HI1(k)
            if (BXK(j) == 1) then
                call it_glyph(BXG(j), x0 + BXX(j), BXY(j) + HRAISE(k), BXS(j), BXC(j))
            else
                call it_rule(x0 + BXX(j), BXY(j) + HRAISE(k), BXW(j), BXH(j), BXC(j))
            end if
        end do
    end subroutine emit_box

    ! A formula's glyphs and rules as box items, y up.
    subroutine box_items(run, rules, col, i0, i1)
        type(glyphrun_t), intent(in) :: run
        type(mrules_t), intent(in) :: rules
        integer, intent(in) :: col
        integer, intent(out) :: i0, i1
        integer :: k
        i0 = NBX + 1
        do k = 1, run%n
            call bx_new()
            BXK(NBX) = 1
            BXG(NBX) = run%gid(k)
            BXX(NBX) = run%x(k)
            BXY(NBX) = -run%y(k)
            BXS(NBX) = run%size(k)
            BXC(NBX) = col
        end do
        do k = 1, rules%n
            call bx_new()
            BXK(NBX) = 2
            BXX(NBX) = rules%x(k)
            ! rules%y is the top, y down.
            BXY(NBX) = -(rules%y(k) + rules%h(k))
            BXW(NBX) = rules%w(k)
            BXH(NBX) = rules%h(k)
            BXC(NBX) = col
        end do
        i1 = NBX
    end subroutine box_items

    ! ------------------------------------------------------------------
    ! Displays.
    ! ------------------------------------------------------------------

    ! A displayed formula, TeX's $$...$$: what of the paragraph comes
    ! before it is broken into lines (if anything), the formula is centred
    ! between \abovedisplayskip and \belowdisplayskip (or the short ones
    ! when the line before ends well before it), with its number, tag, at
    ! the right margin, and the paragraph goes on after it, not indented.
    subroutine ts_display(src, size, tag, color)
        character(len=*), intent(in) :: src
        real(dp), intent(in) :: size
        character(len=*), intent(in) :: tag
        integer, intent(in), optional :: color
        type(glyphrun_t) :: run, trun
        type(mrules_t) :: rules
        real(dp) :: w, h, d, z, e, dd, pre, s, f, x0, tw, ts_
        integer :: col, k, al, i0, i1, g, gf, prev, pg
        integer, allocatable :: cps(:)
        logical :: inpar
        type(ts_glue_t) :: g1, g2
        real(dp) :: lft, rgt, hg

        col = TEXT_COLOR
        if (present(color)) col = color
        f = size/10.0_dp
        inpar = IN_PAR .and. HN > 0
        al = P_ALIGN
        lft = P_LEFT
        rgt = P_RIGHT
        hg = P_HANG
        pre = -huge(1.0_dp)
        pg = 0
        if (inpar) then
            call line_break(.true.)
            pre = pre_display_size(size)
            pg = P_PREV_GRAF
        else if (NV > 0) then
            ! A display that starts a paragraph, as \noindent$$ does.
            call v_glue(PARSKIP)
        end if
        IN_PAR = .false.

        call math_formula(src, size, .true., run, rules, w, h, d)
        z = HSIZE - lft - rgt
        s = lft
        ! The number, in the text font.
        e = 0.0_dp
        if (len_trim(tag) > 0) then
            call code_points("("//trim(tag)//")", cps, k)
            tw = 0.0_dp
            prev = 0
            do i0 = 1, k
                g = glyph_for(FACE_REGULAR, cps(i0), gf)
                if (prev > 0) tw = tw + glyph_kern(FACE_REGULAR, prev, g)*size
                call run_add(trun, g, tw, 0.0_dp, size)
                tw = tw + glyph_adv(g)*size
                prev = g
            end do
            e = tw
        end if
        dd = 0.5_dp*(z - w)
        if (e > 0.0_dp .and. dd < 2.0_dp*e) then
            dd = 0.5_dp*(z - w - e)
        end if
        if (dd < 0.0_dp) dd = 0.0_dp

        ! LaTeX's display skips, scaled from its 10pt ones.
        call ts_penalty(PRE_DISPLAY_PENALTY)
        if (dd + s <= pre) then
            g1 = ts_glue_t(10.0_dp*f, 2.0_dp*f, 5.0_dp*f, 0, 0)
            g2 = g1
        else
            g1 = ts_glue_t(0.0_dp, 3.0_dp*f, 0.0_dp, 0, 0)
            g2 = ts_glue_t(6.0_dp*f, 3.0_dp*f, 3.0_dp*f, 0, 0)
        end if
        if (.not. inpar) then
            g1 = ts_glue_t(10.0_dp*f, 2.0_dp*f, 5.0_dp*f, 0, 0)
            g2 = g1
        end if
        call v_glue(g1)

        i0 = NIT + 1
        x0 = dd
        do k = 1, run%n
            call it_glyph(run%gid(k), x0 + run%x(k), -run%y(k), run%size(k), col)
        end do
        do k = 1, rules%n
            call it_rule(x0 + rules%x(k), -(rules%y(k) + rules%h(k)), rules%w(k), &
                         rules%h(k), col)
        end do
        ts_ = 0.0_dp
        if (e > 0.0_dp) then
            ts_ = z - e
            do k = 1, trun%n
                call it_glyph(trun%gid(k), ts_ + trun%x(k), 0.0_dp, trun%size(k), col)
            end do
        end if
        i1 = NIT
        call append_box(i0, i1, z, h, d, s)
        call ts_penalty(POST_DISPLAY_PENALTY)
        call v_glue(g2)

        ! The paragraph resumes, unindented, if anything follows.
        call ts_begin_par(al, 0.0_dp, lft, rgt, P_SIZE, hg, skip=.false.)
        P_PREV_GRAF = pg + 3
    end subroutine ts_display

    ! TeX's \predisplaysize: where the last line's text ends, from the
    ! left margin, plus two ems.
    real(dp) function pre_display_size(size) result(p)
        real(dp), intent(in) :: size
        integer :: k, last
        real(dp) :: xend
        last = NV
        p = -huge(1.0_dp)
        do k = last, 1, -1
            if (VK(k) == VK_BOX) exit
        end do
        if (k < 1) return
        xend = 0.0_dp
        if (VI1(k) >= VI0(k)) then
            xend = maxval(ITX(VI0(k):VI1(k)) + item_width(VI0(k), VI1(k)))
        end if
        p = VX(k) + xend + 2.0_dp*size
    end function pre_display_size

    function item_width(i0, i1) result(w)
        integer, intent(in) :: i0, i1
        real(dp) :: w(i1 - i0 + 1)
        integer :: k
        do k = i0, i1
            if (ITK(k) == 1) then
                w(k - i0 + 1) = glyph_adv(ITG(k))*ITS(k)
            else
                w(k - i0 + 1) = ITW(k)
            end if
        end do
    end function item_width

    ! ------------------------------------------------------------------
    ! The vertical list.
    ! ------------------------------------------------------------------

    ! TeX's append_to_vlist: the interline glue, then the box.
    subroutine append_box(i0, i1, w, h, d, shift)
        integer, intent(in) :: i0, i1
        real(dp), intent(in) :: w, h, d, shift
        real(dp) :: g
        if (PREV_DEPTH > IGNORE_DEPTH) then
            g = CUR_BASELINE%w - PREV_DEPTH - h
            ! In scaled points, as TeX compares: a hair under is equal.
            if (g < LINESKIPLIMIT - 1.0e-6_dp) then
                call v_glue(LINESKIP)
            else
                call v_glue(ts_glue_t(g, CUR_BASELINE%st, CUR_BASELINE%sh, &
                                      CUR_BASELINE%sto, CUR_BASELINE%sho))
            end if
        end if
        call v_new(VK_BOX)
        VI0(NV) = i0
        VI1(NV) = i1
        VW(NV) = w
        VH(NV) = h
        VD(NV) = d
        VX(NV) = shift
        PREV_DEPTH = d
    end subroutine append_box

    subroutine v_glue(g)
        type(ts_glue_t), intent(in) :: g
        call v_new(VK_GLUE)
        VW(NV) = g%w
        VST(NV) = g%st
        VSH(NV) = g%sh
        VSO(NV) = g%sto
        VHO(NV) = g%sho
    end subroutine v_glue

    subroutine ts_vskip(g)
        type(ts_glue_t), intent(in) :: g
        if (IN_PAR) call ts_end_par()
        call v_glue(g)
    end subroutine ts_vskip

    ! LaTeX's \addvspace: a skip that merges with one just before it, the
    ! larger of the two winning.
    subroutine ts_addvspace(g)
        type(ts_glue_t), intent(in) :: g
        if (IN_PAR) call ts_end_par()
        if (NV > 0) then
            if (VK(NV) == VK_GLUE .and. VP(NV) == 1) then
                if (g%w > VW(NV)) then
                    VW(NV) = g%w
                    VST(NV) = g%st
                    VSH(NV) = g%sh
                    VSO(NV) = g%sto
                end if
                return
            end if
        end if
        call v_glue(g)
        VP(NV) = 1
    end subroutine ts_addvspace

    subroutine ts_vfil()
        if (IN_PAR) call ts_end_par()
        call v_glue(ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0))
    end subroutine ts_vfil

    ! A skip that stays at the top of a page, LaTeX's \vspace*: an empty
    ! rule before it, which is not discarded, and which, as a rule does,
    ! leaves no \baselineskip to the line after it.
    subroutine ts_vkeep(g)
        type(ts_glue_t), intent(in) :: g
        if (IN_PAR) call ts_end_par()
        call v_new(VK_BOX)
        VI0(NV) = 1
        VI1(NV) = 0
        PREV_DEPTH = IGNORE_DEPTH
        call v_glue(g)
    end subroutine ts_vkeep

    ! An invisible box of the given height and depth in the paragraph,
    ! LaTeX's \strut.
    subroutine ts_strut(h, d)
        real(dp), intent(in) :: h, d
        call h_new(HK_BOX)
        HH(HN) = h
        HD(HN) = d
    end subroutine ts_strut

    subroutine ts_penalty(p)
        integer, intent(in) :: p
        call v_new(VK_PEN)
        VP(NV) = p
    end subroutine ts_penalty

    ! LaTeX's \addpenalty: a penalty that goes before a skip just added.
    subroutine ts_addpenalty(p)
        integer, intent(in) :: p
        type(ts_glue_t) :: g
        integer :: m
        if (IN_PAR) call ts_end_par()
        if (NV == 0) return
        if (VK(NV) == VK_GLUE) then
            g = ts_glue_t(VW(NV), VST(NV), VSH(NV), VSO(NV), VHO(NV))
            m = VP(NV)
            NV = NV - 1
            call ts_penalty(p)
            call v_glue(g)
            VP(NV) = m
        else
            call ts_penalty(p)
        end if
    end subroutine ts_addpenalty

    ! LaTeX's \newpage: \vfil\penalty-10000.
    subroutine ts_page_break()
        if (IN_PAR) call ts_end_par()
        if (NV == 0) return
        call ts_vfil()
        call ts_penalty(EJECT_PENALTY)
        PREV_DEPTH = IGNORE_DEPTH
    end subroutine ts_page_break

    ! The next paragraph may not break after its first line, nor before
    ! it: what follows a heading.
    subroutine ts_nobreak_next()
        NOBREAK_NEXT = .true.
    end subroutine ts_nobreak_next

    ! A horizontal rule, width wide and thick high, centred.
    subroutine ts_rule(width, thick, color)
        real(dp), intent(in) :: width, thick
        integer, intent(in), optional :: color
        integer :: col, i0
        col = TEXT_COLOR
        if (present(color)) col = color
        if (IN_PAR) call ts_end_par()
        i0 = NIT + 1
        call it_rule(0.5_dp*(HSIZE - width), 0.0_dp, width, thick, col)
        call append_box(i0, NIT, HSIZE, thick, 0.0_dp, 0.0_dp)
    end subroutine ts_rule

    ! A running head from here on: a chapter's (section false), which
    ! even pages carry, or a section's, which odd pages carry; plain is
    ! true for a page that is to have none (where a chapter starts).
    subroutine ts_mark(s, plain, section)
        character(len=*), intent(in) :: s
        logical, intent(in) :: plain
        logical, intent(in), optional :: section
        call v_new(VK_MARK)
        VI0(NV) = len(MARKS) + 1
        MARKS = MARKS//s
        VI1(NV) = len(MARKS)
        VP(NV) = merge(1, 0, plain)
        VSO(NV) = 0
        if (present(section)) VSO(NV) = merge(1, 0, section)
    end subroutine ts_mark

    ! ------------------------------------------------------------------
    ! Pages.
    ! ------------------------------------------------------------------

    ! TeX's page builder over the whole vertical list: items are moved
    ! onto the page one by one; at each legal break the cost of breaking
    ! there is computed from the page's badness and the penalty, the
    ! cheapest so far is remembered, and when the page is overfull or a
    ! penalty forces a break, the page ends at the cheapest.
    subroutine ts_paginate()
        integer :: i, start, best, c, b, pi
        integer :: least
        real(dp) :: total, depth, so_far(6), goal
        logical :: empty, legal, plain, pplain

        if (IN_PAR) call ts_end_par()
        NPAGE = 0
        if (allocated(PG0)) deallocate (PG0, PG1, PGHEAD0, PGHEAD1, PGPLAIN, PGSET, PGORD, &
                                        PGSTART)
        allocate (PG0(NV + 1), PG1(NV + 1), PGHEAD0(NV + 1), PGHEAD1(NV + 1), &
                  PGPLAIN(NV + 1), PGSET(NV + 1), PGORD(NV + 1), PGSTART(NV + 1))
        start = 1
        do while (start <= NV)
            PGSTART(NPAGE + 1) = start
            empty = .true.
            total = 0.0_dp
            depth = 0.0_dp
            so_far = 0.0_dp
            goal = VSIZE
            least = AWFUL_BAD
            best = 0
            plain = .false.
            pplain = .false.
            i = start
            do while (i <= NV)
                legal = .false.
                pi = 0
                select case (VK(i))
                case (VK_GLUE)
                    if (.not. empty) legal = VK(i - 1) == VK_BOX
                case (VK_KERN)
                    if (.not. empty .and. i < NV) legal = VK(i + 1) == VK_GLUE
                case (VK_PEN)
                    if (.not. empty) then
                        legal = VP(i) < INF_PENALTY
                        pi = VP(i)
                    end if
                case (VK_MARK)
                    if (VP(i) == 1) pplain = .true.
                end select
                if (legal) then
                    if (total < goal) then
                        if (so_far(3) /= 0.0_dp .or. so_far(4) /= 0.0_dp .or. &
                            so_far(5) /= 0.0_dp) then
                            b = 0
                        else
                            b = badness(goal - total, so_far(2))
                        end if
                    else if (total - goal > so_far(6)) then
                        b = AWFUL_BAD
                    else
                        b = badness(total - goal, so_far(6))
                    end if
                    if (b < AWFUL_BAD) then
                        if (pi <= EJECT_PENALTY) then
                            c = pi
                        else if (b < INF_BAD) then
                            c = b + pi
                        else
                            c = DEPLORABLE
                        end if
                    else
                        c = b
                    end if
                    if (c <= least) then
                        best = i
                        least = c
                        plain = pplain
                    end if
                    if (c == AWFUL_BAD .or. pi <= EJECT_PENALTY) exit
                end if
                ! The item goes onto the page.
                select case (VK(i))
                case (VK_BOX)
                    if (empty) then
                        ! \topskip less the box's height comes first.
                        empty = .false.
                        start = i
                        total = max(TOPSKIP - VH(i), 0.0_dp) + VH(i)
                    else
                        total = total + depth + VH(i)
                    end if
                    depth = VD(i)
                case (VK_GLUE)
                    if (.not. empty) then
                        so_far(2 + VSO(i)) = so_far(2 + VSO(i)) + VST(i)
                        if (VHO(i) == 0) so_far(6) = so_far(6) + VSH(i)
                        total = total + depth + VW(i)
                        depth = 0.0_dp
                    end if
                case (VK_KERN)
                    if (.not. empty) then
                        total = total + depth + VW(i)
                        depth = 0.0_dp
                    end if
                end select
                if (depth > MAXDEPTH) then
                    total = total + depth - MAXDEPTH
                    depth = MAXDEPTH
                end if
                i = i + 1
            end do
            if (empty) exit
            ! Running out of material ends the page, as \end{document} does.
            if (i > NV) then
                best = NV + 1
                plain = pplain
            end if
            NPAGE = NPAGE + 1
            PG0(NPAGE) = start
            PG1(NPAGE) = best - 1
            PGPLAIN(NPAGE) = plain
            call page_head(NPAGE, PGHEAD0(NPAGE), PGHEAD1(NPAGE))
            call set_page_glue(NPAGE)
            ! What is left starts at the break, where the glue or penalty
            ! of the break is discarded at the top of the next page.
            start = best
        end do
    end subroutine ts_paginate

    ! The running head of page p, as LaTeX's headings style has it: an
    ! even page carries the chapter's mark (the last on the page or
    ! before it), an odd one the section's (the first on the page, or the
    ! last before it).
    subroutine page_head(p, h0, h1)
        integer, intent(in) :: p
        integer, intent(out) :: h0, h1
        integer :: k, want
        h0 = 1
        h1 = 0
        want = merge(0, 1, mod(p, 2) == 0)
        if (want == 1) then
            do k = PGSTART(p), PG1(p)
                if (VK(k) == VK_MARK .and. VSO(k) == 1) then
                    h0 = VI0(k)
                    h1 = VI1(k)
                    return
                end if
            end do
        end if
        do k = min(PG1(p), NV), 1, -1
            if (VK(k) == VK_MARK .and. VSO(k) == want) then
                h0 = VI0(k)
                h1 = VI1(k)
                return
            end if
        end do
    end subroutine page_head

    ! How the glue of page p is set, as LaTeX boxes a page to \textheight:
    ! infinite stretch, where there is any (\vfill), takes up the room
    ! left; otherwise \raggedbottom leaves the glue at its natural size
    ! and \flushbottom stretches it to fill the page; a page too full
    ! shrinks its glue, no further than its shrink.
    subroutine set_page_glue(p)
        integer, intent(in) :: p
        real(dp) :: total, depth, st(0:3), shrink
        integer :: k, o
        logical :: first
        total = 0.0_dp
        depth = 0.0_dp
        st = 0.0_dp
        shrink = 0.0_dp
        first = .true.
        do k = PG0(p), PG1(p)
            select case (VK(k))
            case (VK_BOX)
                if (first) then
                    total = max(TOPSKIP, VH(k))
                    first = .false.
                else
                    total = total + depth + VH(k)
                end if
                depth = VD(k)
            case (VK_GLUE)
                if (.not. first) then
                    total = total + depth + VW(k)
                    depth = 0.0_dp
                    st(VSO(k)) = st(VSO(k)) + VST(k)
                    if (VHO(k) == 0) shrink = shrink + VSH(k)
                end if
            case (VK_KERN)
                if (.not. first) then
                    total = total + depth + VW(k)
                    depth = 0.0_dp
                end if
            end select
        end do
        PGSET(p) = 0.0_dp
        PGORD(p) = 0
        if (total < VSIZE) then
            do o = 3, 1, -1
                if (st(o) > 0.0_dp) exit
            end do
            if (o >= 1) then
                PGSET(p) = (VSIZE - total)/st(o)
                PGORD(p) = o
            else if (FLUSH_BOTTOM .and. st(0) > 0.0_dp .and. p < filling_limit()) then
                PGSET(p) = (VSIZE - total)/st(0)
            end if
        else if (total > VSIZE .and. shrink > 0.0_dp) then
            PGSET(p) = -min((total - VSIZE)/shrink, 1.0_dp)
        end if
    end subroutine set_page_glue

    ! Pages before the last are filled; the last ends with LaTeX's
    ! \clearpage, whose \vfil takes up what is left.
    integer function filling_limit()
        filling_limit = huge(1)
        if (PG1(NPAGE) >= NV) filling_limit = NPAGE
    end function filling_limit

    integer function ts_page_count()
        ts_page_count = NPAGE
    end function ts_page_count

    ! Draw page p on r, which the caller has opened at the paper's size.
    subroutine ts_page_draw(r, p)
        class(renderer_t), intent(inout) :: r
        integer, intent(in) :: p
        real(dp) :: y, depth, gw
        integer :: k
        logical :: first
        character(len=16) :: num
        y = MARGIN_T
        depth = 0.0_dp
        first = .true.
        do k = PG0(p), PG1(p)
            select case (VK(k))
            case (VK_BOX)
                if (first) then
                    y = y + max(TOPSKIP, VH(k))
                    first = .false.
                else
                    y = y + depth + VH(k)
                end if
                call draw_box(r, k, MARGIN_L + VX(k), y)
                depth = VD(k)
            case (VK_GLUE)
                if (.not. first) then
                    gw = VW(k)
                    if (PGSET(p) < 0.0_dp .and. VHO(k) == 0) gw = gw + PGSET(p)*VSH(k)
                    if (PGSET(p) > 0.0_dp .and. VSO(k) == PGORD(p)) gw = gw + PGSET(p)*VST(k)
                    y = y + depth + gw
                    depth = 0.0_dp
                end if
            case (VK_KERN)
                if (.not. first) then
                    y = y + depth + VW(k)
                    depth = 0.0_dp
                end if
            end select
        end do
        if (PAGE_NUMBERS .and. (.not. HEADINGS .or. PGPLAIN(p))) then
            write (num, "(I0)") p
            call draw_string(r, trim(num), FACE_REGULAR, FONT_SIZE, &
                             MARGIN_L + 0.5_dp*HSIZE, MARGIN_T + VSIZE + FOOTSKIP, 1)
        else if (HEADINGS) then
            write (num, "(I0)") p
            ! LaTeX's headings: the number at the outer edge, the head in
            ! slanted capitals at the inner one; here, italic.
            if (mod(p, 2) == 0) then
                call draw_string(r, trim(num), FACE_REGULAR, FONT_SIZE, MARGIN_L, &
                                 MARGIN_T - 2.5_dp*FONT_SIZE, 0)
                if (PGHEAD1(p) >= PGHEAD0(p)) &
                    call draw_string(r, MARKS(PGHEAD0(p):PGHEAD1(p)), FACE_ITALIC, &
                                     FONT_SIZE, MARGIN_L + HSIZE, &
                                     MARGIN_T - 2.5_dp*FONT_SIZE, 2)
            else
                call draw_string(r, trim(num), FACE_REGULAR, FONT_SIZE, MARGIN_L + HSIZE, &
                                 MARGIN_T - 2.5_dp*FONT_SIZE, 2)
                if (PGHEAD1(p) >= PGHEAD0(p)) &
                    call draw_string(r, MARKS(PGHEAD0(p):PGHEAD1(p)), FACE_ITALIC, &
                                     FONT_SIZE, MARGIN_L, MARGIN_T - 2.5_dp*FONT_SIZE, 0)
            end if
        end if
    end subroutine ts_page_draw

    ! A box's items, its origin at (x, y) on the page, y down: a run of
    ! glyphs and then the rules, for each colour in it.
    subroutine draw_box(r, k, x, y)
        class(renderer_t), intent(inout) :: r
        integer, intent(in) :: k
        real(dp), intent(in) :: x, y
        type(glyphrun_t) :: run
        integer :: j, c, ncol
        integer, allocatable :: cols(:)
        allocate (cols(max(1, VI1(k) - VI0(k) + 1)))
        ncol = 0
        do j = VI0(k), VI1(k)
            if (any(cols(1:ncol) == ITC(j))) cycle
            ncol = ncol + 1
            cols(ncol) = ITC(j)
        end do
        do c = 1, ncol
            run%n = 0
            do j = VI0(k), VI1(k)
                if (ITK(j) == 1 .and. ITC(j) == cols(c)) &
                    call run_add(run, ITG(j), ITX(j), -ITY(j), ITS(j))
            end do
            if (run%n > 0) then
                run%text = ""
                call r%draw_glyphs(x, y, run, color_paint(cols(c)), 0.0_dp)
            end if
            do j = VI0(k), VI1(k)
                if (ITK(j) == 2 .and. ITC(j) == cols(c)) &
                    call r%draw_rect(x + ITX(j), y - ITY(j) - ITH(j), ITW(j), ITH(j), &
                                     color_paint(cols(c)))
            end do
        end do
    end subroutine draw_box

    function color_paint(col) result(p)
        integer, intent(in) :: col
        type(paint_t) :: p
        p%filled = .true.
        p%fill_rgb = [ishft(col, -16), iand(ishft(col, -8), 255), iand(col, 255)]
    end function color_paint

    ! A string on the page, anchored at its start (0), middle (1) or end
    ! (2), its baseline at y.
    subroutine draw_string(r, s, face, size, x, y, anchor)
        class(renderer_t), intent(inout) :: r
        character(len=*), intent(in) :: s
        integer, intent(in) :: face, anchor
        real(dp), intent(in) :: size, x, y
        type(glyphrun_t) :: run
        integer, allocatable :: cps(:)
        integer :: n, k, g, gf, prev
        real(dp) :: pen
        call code_points(s, cps, n)
        pen = 0.0_dp
        prev = 0
        do k = 1, n
            g = glyph_for(face, cps(k), gf)
            if (prev > 0) pen = pen + glyph_kern(face, prev, g)*size
            call run_add(run, g, pen, 0.0_dp, size)
            pen = pen + glyph_adv(g)*size
            prev = g
        end do
        if (run%n == 0) return
        run%text = s
        call r%draw_glyphs(x - 0.5_dp*anchor*pen, y, run, color_paint(TEXT_COLOR), 0.0_dp)
    end subroutine draw_string

    ! ------------------------------------------------------------------
    ! For tests: the lines of the last paragraph.
    ! ------------------------------------------------------------------

    subroutine ts_par_lines(i0, i1)
        integer, intent(out) :: i0, i1
        i0 = LAST_PAR0
        i1 = LAST_PAR1
    end subroutine ts_par_lines

    integer function ts_line_count()
        integer :: k
        ts_line_count = 0
        do k = LAST_PAR0, LAST_PAR1
            if (VK(k) == VK_BOX) ts_line_count = ts_line_count + 1
        end do
    end function ts_line_count

    ! Line l of the last paragraph: its glyphs' code points (as glyph ids)
    ! and x positions.
    subroutine ts_line_info(l, gids, xs, n)
        integer, intent(in) :: l
        integer, allocatable, intent(out) :: gids(:)
        real(dp), allocatable, intent(out) :: xs(:)
        integer, intent(out) :: n
        integer :: k, c, j
        c = 0
        n = 0
        do k = LAST_PAR0, LAST_PAR1
            if (VK(k) /= VK_BOX) cycle
            c = c + 1
            if (c /= l) cycle
            allocate (gids(VI1(k) - VI0(k) + 1), xs(VI1(k) - VI0(k) + 1))
            do j = VI0(k), VI1(k)
                if (ITK(j) /= 1) cycle
                n = n + 1
                gids(n) = ITG(j)
                xs(n) = ITX(j) + VX(k)
            end do
            return
        end do
        allocate (gids(0), xs(0))
    end subroutine ts_line_info

    ! ------------------------------------------------------------------
    ! The arenas.
    ! ------------------------------------------------------------------

    subroutine h_new(kind)
        integer, intent(in) :: kind
        call h_reserve(HN + 1)
        HN = HN + 1
        call h_clear(HN)
        HK(HN) = kind
    end subroutine h_new

    subroutine h_clear(i)
        integer, intent(in) :: i
        HK(i) = 0
        HFACE(i) = FACE_REGULAR
        HCOL(i) = TEXT_COLOR
        HC0(i) = 1
        HC1(i) = 0
        HI0(i) = 1
        HI1(i) = 0
        HSO(i) = 0
        HHO(i) = 0
        HP(i) = 0
        HEXPL(i) = .false.
        HW(i) = 0.0_dp
        HH(i) = 0.0_dp
        HD(i) = 0.0_dp
        HST(i) = 0.0_dp
        HSH(i) = 0.0_dp
        HSZ(i) = FONT_SIZE
        HRAISE(i) = 0.0_dp
    end subroutine h_clear

    ! Make room for a node at j, moving the nodes from j on up by one.
    subroutine h_insert(j)
        integer, intent(in) :: j
        call h_reserve(HN + 1)
        HK(j + 1:HN + 1) = HK(j:HN)
        HFACE(j + 1:HN + 1) = HFACE(j:HN)
        HCOL(j + 1:HN + 1) = HCOL(j:HN)
        HC0(j + 1:HN + 1) = HC0(j:HN)
        HC1(j + 1:HN + 1) = HC1(j:HN)
        HI0(j + 1:HN + 1) = HI0(j:HN)
        HI1(j + 1:HN + 1) = HI1(j:HN)
        HSO(j + 1:HN + 1) = HSO(j:HN)
        HHO(j + 1:HN + 1) = HHO(j:HN)
        HP(j + 1:HN + 1) = HP(j:HN)
        HEXPL(j + 1:HN + 1) = HEXPL(j:HN)
        HW(j + 1:HN + 1) = HW(j:HN)
        HH(j + 1:HN + 1) = HH(j:HN)
        HD(j + 1:HN + 1) = HD(j:HN)
        HST(j + 1:HN + 1) = HST(j:HN)
        HSH(j + 1:HN + 1) = HSH(j:HN)
        HSZ(j + 1:HN + 1) = HSZ(j:HN)
        HRAISE(j + 1:HN + 1) = HRAISE(j:HN)
        HN = HN + 1
        call h_clear(j)
    end subroutine h_insert

    subroutine h_reserve(n)
        integer, intent(in) :: n
        integer :: cap
        if (.not. allocated(HK)) then
            cap = 256
        else if (n > size(HK)) then
            cap = 2*n
        else
            return
        end if
        call grow_i(HK, cap)
        call grow_i(HFACE, cap)
        call grow_i(HCOL, cap)
        call grow_i(HC0, cap)
        call grow_i(HC1, cap)
        call grow_i(HI0, cap)
        call grow_i(HI1, cap)
        call grow_i(HSO, cap)
        call grow_i(HHO, cap)
        call grow_i(HP, cap)
        call grow_l(HEXPL, cap)
        call grow_r(HW, cap)
        call grow_r(HH, cap)
        call grow_r(HD, cap)
        call grow_r(HST, cap)
        call grow_r(HSH, cap)
        call grow_r(HSZ, cap)
        call grow_r(HRAISE, cap)
    end subroutine h_reserve

    subroutine cp_reserve(extra)
        integer, intent(in) :: extra
        if (.not. allocated(CPA)) then
            call grow_i(CPA, max(1024, 2*extra))
        else if (NCP + extra > size(CPA)) then
            call grow_i(CPA, 2*(NCP + extra))
        end if
    end subroutine cp_reserve

    subroutine bx_new()
        integer :: cap
        if (.not. allocated(BXK)) then
            cap = 256
        else if (NBX + 1 > size(BXK)) then
            cap = 2*size(BXK)
        else
            cap = 0
        end if
        if (cap > 0) then
            call grow_i(BXK, cap)
            call grow_i(BXG, cap)
            call grow_i(BXC, cap)
            call grow_r(BXX, cap)
            call grow_r(BXY, cap)
            call grow_r(BXS, cap)
            call grow_r(BXW, cap)
            call grow_r(BXH, cap)
        end if
        NBX = NBX + 1
        BXK(NBX) = 0
        BXG(NBX) = 0
        BXC(NBX) = 0
        BXX(NBX) = 0.0_dp
        BXY(NBX) = 0.0_dp
        BXS(NBX) = 0.0_dp
        BXW(NBX) = 0.0_dp
        BXH(NBX) = 0.0_dp
    end subroutine bx_new

    subroutine it_new()
        integer :: cap
        if (.not. allocated(ITK)) then
            cap = 4096
        else if (NIT + 1 > size(ITK)) then
            cap = 2*size(ITK)
        else
            cap = 0
        end if
        if (cap > 0) then
            call grow_i(ITK, cap)
            call grow_i(ITG, cap)
            call grow_i(ITC, cap)
            call grow_r(ITX, cap)
            call grow_r(ITY, cap)
            call grow_r(ITS, cap)
            call grow_r(ITW, cap)
            call grow_r(ITH, cap)
        end if
        NIT = NIT + 1
        ITK(NIT) = 0
        ITG(NIT) = 0
        ITC(NIT) = 0
        ITX(NIT) = 0.0_dp
        ITY(NIT) = 0.0_dp
        ITS(NIT) = 0.0_dp
        ITW(NIT) = 0.0_dp
        ITH(NIT) = 0.0_dp
    end subroutine it_new

    subroutine it_glyph(g, x, y, s, col)
        integer, intent(in) :: g, col
        real(dp), intent(in) :: x, y, s
        call it_new()
        ITK(NIT) = 1
        ITG(NIT) = g
        ITX(NIT) = x
        ITY(NIT) = y
        ITS(NIT) = s
        ITC(NIT) = col
    end subroutine it_glyph

    subroutine it_rule(x, y, w, h, col)
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: col
        call it_new()
        ITK(NIT) = 2
        ITX(NIT) = x
        ITY(NIT) = y
        ITW(NIT) = w
        ITH(NIT) = h
        ITC(NIT) = col
    end subroutine it_rule

    subroutine v_new(kind)
        integer, intent(in) :: kind
        integer :: cap
        if (.not. allocated(VK)) then
            cap = 1024
        else if (NV + 1 > size(VK)) then
            cap = 2*size(VK)
        else
            cap = 0
        end if
        if (cap > 0) then
            call grow_i(VK, cap)
            call grow_i(VSO, cap)
            call grow_i(VHO, cap)
            call grow_i(VP, cap)
            call grow_i(VI0, cap)
            call grow_i(VI1, cap)
            call grow_r(VW, cap)
            call grow_r(VH, cap)
            call grow_r(VD, cap)
            call grow_r(VST, cap)
            call grow_r(VSH, cap)
            call grow_r(VX, cap)
        end if
        NV = NV + 1
        VK(NV) = kind
        VSO(NV) = 0
        VHO(NV) = 0
        VP(NV) = 0
        VI0(NV) = 1
        VI1(NV) = 0
        VW(NV) = 0.0_dp
        VH(NV) = 0.0_dp
        VD(NV) = 0.0_dp
        VST(NV) = 0.0_dp
        VSH(NV) = 0.0_dp
        VX(NV) = 0.0_dp
    end subroutine v_new

    subroutine grow_i(a, cap)
        integer, allocatable, intent(inout) :: a(:)
        integer, intent(in) :: cap
        integer, allocatable :: t(:)
        allocate (t(cap))
        t = 0
        if (allocated(a)) t(1:min(size(a), cap)) = a(1:min(size(a), cap))
        call move_alloc(t, a)
    end subroutine grow_i

    subroutine grow_r(a, cap)
        real(dp), allocatable, intent(inout) :: a(:)
        integer, intent(in) :: cap
        real(dp), allocatable :: t(:)
        allocate (t(cap))
        t = 0.0_dp
        if (allocated(a)) t(1:min(size(a), cap)) = a(1:min(size(a), cap))
        call move_alloc(t, a)
    end subroutine grow_r

    subroutine grow_l(a, cap)
        logical, allocatable, intent(inout) :: a(:)
        integer, intent(in) :: cap
        logical, allocatable :: t(:)
        allocate (t(cap))
        t = .false.
        if (allocated(a)) t(1:min(size(a), cap)) = a(1:min(size(a), cap))
        call move_alloc(t, a)
    end subroutine grow_l

end module fplotlib_typeset
