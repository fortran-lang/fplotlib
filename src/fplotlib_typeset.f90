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
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_render, only: renderer_t, paint_t, glyphrun_t, clip_t
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t, IDENTITY
    use fplotlib_text, only: code_points, run_add, run_map, text_layout
    use fplotlib_glyphs, only: glyph_cmap, glyph_adv, glyph_kern, glyph_bbox, &
                               face_xheight, FACE_REGULAR, FACE_BOLD, FACE_ITALIC, &
                               FACE_MATH
    use fplotlib_hyph, only: hyph_points
    use fplotlib_mathtext, only: math_context_t, math_formula, mrules_t
    implicit none
    private

    public :: typeset_context_t

    public :: ts_reset, ts_set_page, ts_set_font
    public :: ts_begin_par, ts_end_par, ts_word, ts_space, ts_math, ts_hard_break, ts_text
    public :: ts_word_width
    public :: ts_hfil, ts_kern, ts_nbsp, ts_label, ts_in_par
    public :: ts_vskip, ts_addvspace, ts_penalty, ts_addpenalty, ts_vfil, ts_rule
    public :: ts_page_break, ts_mark, ts_nobreak_next, ts_set_clubpenalty
    public :: ts_vkeep, ts_set_colors, ts_hsize, ts_vsize, ts_font_size, ts_strut, ts_set_parskip
    public :: ts_paginate, ts_page_count, ts_page_draw, ts_page_size
    public :: ts_line_count, ts_line_info, ts_par_lines
    public :: ts_glue_t, ts_xheight, ts_quad
    public :: ts_finish, ts_finish_frame, ts_import_frame, ts_place_frame
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
    integer, parameter :: VERY_LOOSE = 0, LOOSE = 1, DECENT = 2, TIGHT = 3
    integer, parameter :: HK_WORD = 1, HK_GLUE = 2, HK_KERN = 3, HK_PEN = 4, &
                          HK_DISC = 5, HK_BOX = 6
    integer, parameter :: VK_BOX = 1, VK_GLUE = 2, VK_KERN = 3, VK_PEN = 4, VK_MARK = 5
    real(dp), parameter :: IGNORE_DEPTH = -1000.0_dp

    type :: typeset_context_t
        private
        type(math_context_t) :: math
        type(frame_t) :: graphics
        integer :: CLUB_PENALTY = 150


        ! --- the horizontal list of the paragraph being built ---------------


        integer :: HN = 0
        integer, allocatable :: HK(:), HFACE(:), HCOL(:), HC0(:), HC1(:), HI0(:), HI1(:)
        integer, allocatable :: HSO(:), HHO(:), HP(:)
        logical, allocatable :: HEXPL(:)
        real(dp), allocatable :: HW(:), HH(:), HD(:), HST(:), HSH(:), HSZ(:), HRAISE(:)
        ! The code points of the words.
        integer :: NCP = 0
        integer, allocatable :: CPA(:), CPFIRST(:), CPLAST(:)
        character(len=:), allocatable :: SOURCE_TEXT
        ! Explicit plain-text whitespace through this byte must survive extraction.
        integer :: SOURCE_EXACT_END = 0
        ! The items of the boxes in the list (formulas, labels), about each
        ! box's origin, y up.
        integer :: NBX = 0
        integer, allocatable :: BXK(:), BXG(:), BXC(:), BXFIRST(:), BXLAST(:)
        logical, allocatable :: BXMATH(:)
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
        integer, allocatable :: ITK(:), ITG(:), ITC(:), ITFIRST(:), ITLAST(:)
        logical, allocatable :: ITMATH(:)
        real(dp), allocatable :: ITX(:), ITY(:), ITS(:), ITW(:), ITH(:)

        ! --- the main vertical list -------------------------------------------

        integer :: NV = 0
        integer, allocatable :: VK(:), VSO(:), VHO(:), VP(:), VI0(:), VI1(:)
        integer, allocatable :: VREPEAT(:)
        logical, allocatable :: VPACKED(:)
        real(dp), allocatable :: VW(:), VH(:), VD(:), VST(:), VSH(:), VX(:)
        ! VK_MARK: a running head, MARKS(VI0) to MARKS(VI1); VSO 0 for the
        ! chapter's (LaTeX's left mark), 1 for a section's (the right mark);
        ! VP 1 for a page that is to have no head (a chapter's first).
        character(len=:), allocatable :: MARKS
        real(dp) :: PREV_DEPTH = -1000.0_dp
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
        integer, allocatable :: PGREPEAT(:)
        logical, allocatable :: PGPLAIN(:)
        ! How a page's glue is set: by PGSET times its stretch (positive) or
        ! shrink (negative) of order PGORD.
        real(dp), allocatable :: PGSET(:)
        integer, allocatable :: PGORD(:)

        ! The lines of the last paragraph, for tests: their vertical list
        ! entries.
        integer :: LAST_PAR0 = 0, LAST_PAR1 = -1
    end type typeset_context_t

contains

    ! ------------------------------------------------------------------
    ! Settings.
    ! ------------------------------------------------------------------

    ! Start a new document.
    subroutine ts_reset(state)
        type(typeset_context_t), intent(inout) :: state
        state%HN = 0
        state%NCP = 0
        state%NBX = 0
        state%NIT = 0
        state%NV = 0
        state%NPAGE = 0
        state%IN_PAR = .false.
        state%PREV_DEPTH = IGNORE_DEPTH
        state%NOBREAK_NEXT = .false.
        state%CLUB_PENALTY = 150
        state%MARKS = ""
        state%SOURCE_TEXT = ""
        state%SOURCE_EXACT_END = 0
        if (allocated(state%VREPEAT)) state%VREPEAT(:) = 0
        if (allocated(state%VPACKED)) state%VPACKED(:) = .false.
        if (allocated(state%PGREPEAT)) state%PGREPEAT(:) = 0
        call state%graphics%init(0.0_dp, 0.0_dp)
        call ts_set_page(state, 595.2756_dp, 841.8898_dp, 72.0_dp, 72.0_dp, 72.0_dp, 72.0_dp)
        call ts_set_font(state, 10.0_dp)
        state%PAGE_NUMBERS = .true.
        state%HEADINGS = .false.
        state%FLUSH_BOTTOM = .false.
        state%TEXT_COLOR = 0
        state%PAGE_COLOR = 16777215
    end subroutine ts_reset

    ! The colours of the text and of the page, as 0xRRGGBB.
    subroutine ts_set_colors(state, text, page)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: text, page
        state%TEXT_COLOR = text
        state%PAGE_COLOR = page
    end subroutine ts_set_colors

    pure real(dp) function ts_hsize(state)
        type(typeset_context_t), intent(in) :: state
        ts_hsize = state%HSIZE
    end function ts_hsize

    pure real(dp) function ts_vsize(state)
        type(typeset_context_t), intent(in) :: state
        ts_vsize = state%VSIZE
    end function ts_vsize

    pure real(dp) function ts_font_size(state)
        type(typeset_context_t), intent(in) :: state
        ts_font_size = state%FONT_SIZE
    end function ts_font_size

    subroutine ts_set_page(state, w, h, left, right, top, bottom, numbers, headings_, flush)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(in) :: w, h, left, right, top, bottom
        logical, intent(in), optional :: numbers, headings_, flush
        state%PAPER_W = w
        state%PAPER_H = h
        state%MARGIN_L = left
        state%MARGIN_R = right
        state%MARGIN_T = top
        state%MARGIN_B = bottom
        state%HSIZE = w - left - right
        state%VSIZE = h - top - bottom
        if (present(numbers)) state%PAGE_NUMBERS = numbers
        if (present(headings_)) state%HEADINGS = headings_
        if (present(flush)) state%FLUSH_BOTTOM = flush
    end subroutine ts_set_page

    ! The body size and what goes with it, LaTeX's lengths scaled from its
    ! 10pt ones: \baselineskip 1.2 em, \parskip 0pt plus 1pt, \topskip one
    ! em, \maxdepth half of it, \footskip 30pt.
    subroutine ts_set_font(state, size, leading)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(in) :: size
        real(dp), intent(in), optional :: leading
        state%FONT_SIZE = size
        state%BASELINESKIP = ts_glue_t(1.2_dp*size, 0.0_dp, 0.0_dp, 0, 0)
        if (present(leading)) state%BASELINESKIP%w = leading
        state%LINESKIP = ts_glue_t(1.0_dp, 0.0_dp, 0.0_dp, 0, 0)
        state%LINESKIPLIMIT = 0.0_dp
        state%PARSKIP = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        state%TOPSKIP = size
        state%MAXDEPTH = 0.5_dp*size
        state%FOOTSKIP = 3.0_dp*size
        state%CUR_BASELINE = state%BASELINESKIP
    end subroutine ts_set_font

    pure real(dp) function ts_xheight(size)
        real(dp), intent(in) :: size
        ts_xheight = face_xheight(FACE_REGULAR)*size
    end function ts_xheight

    pure real(dp) function ts_quad(size)
        real(dp), intent(in) :: size
        ts_quad = size
    end function ts_quad

    pure logical function ts_in_par(state)
        type(typeset_context_t), intent(in) :: state
        ts_in_par = state%IN_PAR
    end function ts_in_par

    subroutine ts_page_size(state, w, h, color)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(out) :: w, h
        integer, intent(out), optional :: color
        w = state%PAPER_W
        h = state%PAPER_H
        if (present(color)) color = state%PAGE_COLOR
    end subroutine ts_page_size

    ! The glue \parskip puts between paragraphs from here on.
    subroutine ts_set_parskip(state, g)
        type(typeset_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: g
        state%PARSKIP = g
    end subroutine ts_set_parskip

    subroutine ts_set_clubpenalty(state, p)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: p
        state%CLUB_PENALTY = p
    end subroutine ts_set_clubpenalty

    ! ------------------------------------------------------------------
    ! The horizontal list.
    ! ------------------------------------------------------------------

    ! Start a paragraph: its alignment, how far its lines are moved in
    ! from the left and right margins, its indentation (0 for none), and a
    ! hanging indentation of all lines but the first.
    subroutine ts_begin_par(state, align, indent, left, right, size, hang, skip, leading, &
                            nobreak)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: align
        real(dp), intent(in) :: indent
        real(dp), intent(in), optional :: left, right, size, hang, leading
        logical, intent(in), optional :: skip, nobreak
        logical :: sk
        if (state%IN_PAR) call ts_end_par(state)
        state%IN_PAR = .true.
        state%P_ALIGN = align
        state%P_LEFT = 0.0_dp
        state%P_RIGHT = 0.0_dp
        state%P_HANG = 0.0_dp
        state%P_SIZE = state%FONT_SIZE
        state%P_NOBREAK = .false.
        state%CUR_BASELINE = state%BASELINESKIP
        if (present(left)) state%P_LEFT = left
        if (present(right)) state%P_RIGHT = right
        if (present(size)) state%P_SIZE = size
        if (present(hang)) state%P_HANG = hang
        if (present(leading)) state%CUR_BASELINE%w = leading
        if (present(nobreak)) state%P_NOBREAK = nobreak
        state%P_SF = 1000.0_dp
        state%P_PREV_GRAF = 0
        state%HN = 0
        state%NCP = 0
        state%NBX = 0
        ! \parskip goes between paragraphs, not at the top of the list.
        sk = .true.
        if (present(skip)) sk = skip
        if (sk .and. state%NV > 0) call v_glue(state, state%PARSKIP)
        if (indent > 0.0_dp) then
            call h_new(state, HK_BOX)
            state%HW(state%HN) = indent
            state%HI0(state%HN) = 1
            state%HI1(state%HN) = 0
        end if
    end subroutine ts_begin_par

    ! Words: s is one word or a piece of one (no spaces), in face at size.
    ! Explicit hyphens in it are places it may break, as TeX's
    ! \exhyphenpenalty allows.
    subroutine ts_word(state, s, face, size, color, raise)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: s
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        integer, intent(in), optional :: color
        real(dp), intent(in), optional :: raise
        integer, allocatable :: cps(:), first(:), last(:)
        integer :: n, k, k0, col, offset
        real(dp) :: up
        if (.not. state%IN_PAR) call ts_begin_par(state, ALIGN_JUSTIFY, 0.0_dp)
        col = state%TEXT_COLOR
        if (present(color)) col = color
        up = 0.0_dp
        if (present(raise)) up = raise
        call code_points(s, cps, n, first, last)
        offset = add_source(state, s)
        first(1:n) = first(1:n) + offset
        last(1:n) = last(1:n) + offset
        k0 = 1
        do k = 1, n
            ! A hyphen ends a piece, and a discretionary with nothing
            ! before the break follows it.
            if (cps(k) == 45 .and. k > 1 .and. k < n) then
                call word_piece(state, cps(k0:k), face, size, col, up, first(k0:k), last(k0:k))
                call h_new(state, HK_DISC)
                state%HFACE(state%HN) = face
                state%HSZ(state%HN) = size
                state%HC0(state%HN) = 0
                state%HW(state%HN) = 0.0_dp
                k0 = k + 1
            end if
        end do
        if (k0 <= n) call word_piece(state, cps(k0:n), face, size, col, up, first(k0:n), last(k0:n))
    end subroutine ts_word

    ! Plain UTF-8, not markup. Horizontal whitespace uses ordinary word glue;
    ! its original bytes, including tabs and CRLF, remain in the logical source.
    subroutine ts_text(state, text, face, size, color)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        integer, intent(in), optional :: color
        integer :: i, first, cp, nb, offset

        if (len(text) == 0) return
        if (.not. state%IN_PAR) call ts_begin_par(state, ALIGN_JUSTIFY, 0.0_dp)
        first = 1
        i = 1
        do while (i <= len(text))
            call utf8_next(text, i, cp, nb)
            if (cp == 9 .or. cp == 10 .or. cp == 13 .or. cp == 32) then
                if (i > first) call ts_word(state, text(first:i - 1), face, size, color)
                offset = len(state%SOURCE_TEXT)
                if (cp == 10 .or. cp == 13) then
                    if (cp == 13 .and. i < len(text)) then
                        if (text(i + 1:i + 1) == achar(10)) nb = 2
                    end if
                    call ts_strut(state, 0.0_dp, 0.0_dp)
                    call ts_hard_break(state)
                    call ts_strut(state, 0.0_dp, 0.0_dp)
                else
                    call ts_space(state, face, size)
                end if
                state%SOURCE_TEXT = state%SOURCE_TEXT(:offset)//text(i:i + nb - 1)
                first = i + nb
            end if
            i = i + nb
        end do
        if (first <= len(text)) call ts_word(state, text(first:), face, size, color)
        if (state%HN == 0) call ts_strut(state, 0.0_dp, 0.0_dp)
        state%SOURCE_EXACT_END = len(state%SOURCE_TEXT)
    end subroutine ts_text

    subroutine word_piece(state, cps, face, fs, col, up, first, last)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: cps(:), face, col
        integer, intent(in) :: first(:), last(:)
        real(dp), intent(in) :: fs, up
        integer :: k
        call h_new(state, HK_WORD)
        call cp_reserve(state, size(cps))
        state%HC0(state%HN) = state%NCP + 1
        state%CPA(state%NCP + 1:state%NCP + size(cps)) = cps
        state%CPFIRST(state%NCP + 1:state%NCP + size(cps)) = first
        state%CPLAST(state%NCP + 1:state%NCP + size(cps)) = last
        state%NCP = state%NCP + size(cps)
        state%HC1(state%HN) = state%NCP
        state%HFACE(state%HN) = face
        state%HSZ(state%HN) = fs
        state%HCOL(state%HN) = col
        state%HRAISE(state%HN) = up
        call measure(state, state%HN)
        do k = 1, size(cps)
            call space_factor(state, cps(k))
        end do
    end subroutine word_piece

    integer function add_source(state, text) result(offset)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: text
        if (.not. allocated(state%SOURCE_TEXT)) state%SOURCE_TEXT = ""
        offset = len(state%SOURCE_TEXT)
        state%SOURCE_TEXT = state%SOURCE_TEXT//text
    end function add_source

    ! TeX's \sfcode and its rule for the space factor (\nonfrenchspacing:
    ! 3000 after a full stop, 2000 after a colon and so on, 999 for a
    ! capital letter, which keeps the space after an initial normal, and 0
    ! for closing brackets and quotes, which leave it as it was).
    subroutine space_factor(state, cp)
        type(typeset_context_t), intent(inout) :: state
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
            state%P_SF = 1000.0_dp
        else if (s < 1000.0_dp) then
            if (s > 0.0_dp) state%P_SF = s
        else if (state%P_SF < 1000.0_dp) then
            state%P_SF = 1000.0_dp
        else
            state%P_SF = s
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
    subroutine measure(state, i)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: i
        call shape(state%CPA(state%HC0(i):state%HC1(i)), state%HFACE(i), state%HSZ(i), state%HW(i), state%HH(i), state%HD(i))
    end subroutine measure

    ! Measure with the same Unicode normalization, font fallback and kerning as ts_word.
    real(dp) function ts_word_width(text, face, fontsize) result(width)
        character(len=*), intent(in) :: text
        integer, intent(in) :: face
        real(dp), intent(in) :: fontsize
        integer, allocatable :: cps(:)
        integer :: n
        real(dp) :: height, depth
        call code_points(text, cps, n)
        call shape(cps(1:n), face, fontsize, width, height, depth)
    end function ts_word_width

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
    subroutine ts_space(state, face, size)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        real(dp) :: sp
        integer :: gf
        if (.not. state%IN_PAR) return
        if (state%HN == 0) return
        if (state%HK(state%HN) == HK_GLUE) return
        sp = glyph_adv(glyph_for(face, 32, gf))*size
        call h_new(state, HK_GLUE)
        state%SOURCE_TEXT = state%SOURCE_TEXT//" "
        state%HW(state%HN) = sp
        state%HST(state%HN) = sp/2.0_dp
        state%HSH(state%HN) = sp/3.0_dp
        if (state%P_SF /= 1000.0_dp) then
            if (state%P_SF >= 2000.0_dp) state%HW(state%HN) = state%HW(state%HN) + sp/3.0_dp
            state%HST(state%HN) = state%HST(state%HN)*state%P_SF/1000.0_dp
            state%HSH(state%HN) = state%HSH(state%HN)*1000.0_dp/state%P_SF
        end if
    end subroutine ts_space

    ! A space that does not break: the same glue behind a penalty.
    subroutine ts_nbsp(state, face, size)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: face
        real(dp), intent(in) :: size
        if (.not. state%IN_PAR) call ts_begin_par(state, ALIGN_JUSTIFY, 0.0_dp)
        state%P_SF = 1000.0_dp
        call h_new(state, HK_PEN)
        state%HP(state%HN) = INF_PENALTY
        call ts_space(state, face, size)
        if (state%HK(state%HN) /= HK_GLUE) then
            state%HN = state%HN - 1
        else
            state%SOURCE_TEXT = state%SOURCE_TEXT(1:len(state%SOURCE_TEXT) - 1)//achar(194)//achar(160)
        end if
    end subroutine ts_nbsp

    ! Infinitely stretchable glue, \hfil, and a fixed kern.
    subroutine ts_hfil(state)
        type(typeset_context_t), intent(inout) :: state
        call h_new(state, HK_GLUE)
        state%HSO(state%HN) = 1
        state%HST(state%HN) = 1.0_dp
    end subroutine ts_hfil

    subroutine ts_kern(state, w, text)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(in) :: w
        character(len=*), intent(in), optional :: text
        call h_new(state, HK_KERN)
        state%HW(state%HN) = w
        state%HEXPL(state%HN) = .true.
        if (present(text)) state%SOURCE_TEXT = state%SOURCE_TEXT//text
    end subroutine ts_kern

    ! A formula: inline, in text style as one box of the paragraph, or,
    ! with display, displayed (TeX's $$...$$, below) with the number tag.
    ! The layout of the formula itself is the same, math_formula's; only
    ! its style and where it goes differ.
    subroutine ts_math(state, src, size, color, display, tag)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: src
        real(dp), intent(in) :: size
        integer, intent(in), optional :: color
        logical, intent(in), optional :: display
        character(len=*), intent(in), optional :: tag
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        real(dp) :: w, h, d
        integer :: col, i0, i1
        col = state%TEXT_COLOR
        if (present(color)) col = color
        if (present(display)) then
            if (display) then
                if (present(tag)) then
                    call set_display(state, src, size, tag, col)
                else
                    call set_display(state, src, size, "", col)
                end if
                return
            end if
        end if
        if (.not. state%IN_PAR) call ts_begin_par(state, ALIGN_JUSTIFY, 0.0_dp)
        call math_formula(src, size, .false., run, rules, w, h, d, context=state%math)
        call h_new(state, HK_BOX)
        state%HW(state%HN) = w
        state%HH(state%HN) = h
        state%HD(state%HN) = d
        call box_items(state, run, rules, col, i0, i1)
        state%HI0(state%HN) = i0
        state%HI1(state%HN) = i1
        state%P_SF = 1000.0_dp
    end subroutine ts_math

    ! A label hung to the left of the paragraph's first line, ending sep
    ! before the text, as a LaTeX \item puts it; a penalty of 0 follows,
    ! as there.
    subroutine ts_label(state, s, face, size, sep, color)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: s
        integer, intent(in) :: face
        real(dp), intent(in) :: size, sep
        integer, intent(in), optional :: color
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        integer, allocatable :: cps(:)
        integer :: n, k, g, gf, prev, pf, col, i0, i1
        real(dp) :: pen, w
        col = state%TEXT_COLOR
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
        call run_map(run, 1, run%n, s)
        call h_new(state, HK_BOX)
        state%HW(state%HN) = 0.0_dp
        state%HH(state%HN) = 0.0_dp
        state%HD(state%HN) = 0.0_dp
        call box_items(state, run, rules, col, i0, i1)
        state%HI0(state%HN) = i0
        state%HI1(state%HN) = i1
        call h_new(state, HK_PEN)
        state%HP(state%HN) = 0
    end subroutine ts_label

    ! A line break within the paragraph, LaTeX's \\: in justified or
    ! ragged right text \nobreak\hfil\break; in centred or ragged left
    ! text the paragraph ends and a new one goes on with the same settings,
    ! as \centering's \\ does.
    subroutine ts_hard_break(state)
        type(typeset_context_t), intent(inout) :: state
        integer :: al
        real(dp) :: l, r, s, hg, lead
        logical :: nb
        if (.not. state%IN_PAR) return
        do while (state%HN > 0)
            if (state%HK(state%HN) /= HK_GLUE) exit
            state%HN = state%HN - 1
        end do
        if (state%P_ALIGN == ALIGN_CENTER .or. state%P_ALIGN == ALIGN_RIGHT) then
            al = state%P_ALIGN
            l = state%P_LEFT
            r = state%P_RIGHT
            s = state%P_SIZE
            hg = state%P_HANG
            lead = state%CUR_BASELINE%w
            nb = state%P_NOBREAK
            call ts_end_par(state)
            call ts_begin_par(state, al, 0.0_dp, l, r, s, hg, skip=.false., leading=lead, &
                              nobreak=nb)
            return
        end if
        call h_new(state, HK_PEN)
        state%HP(state%HN) = INF_PENALTY
        call ts_hfil(state)
        call h_new(state, HK_PEN)
        state%HP(state%HN) = EJECT_PENALTY
    end subroutine ts_hard_break

    ! ------------------------------------------------------------------
    ! Line breaking.
    ! ------------------------------------------------------------------

    ! End the paragraph: break it into lines and put them on the vertical
    ! list.
    subroutine ts_end_par(state)
        type(typeset_context_t), intent(inout) :: state
        if (.not. state%IN_PAR) return
        state%IN_PAR = .false.
        if (state%HN > 0) then
            call line_break(state, .false.)
            state%NOBREAK_NEXT = .false.
            state%SOURCE_TEXT = state%SOURCE_TEXT//achar(10)
        end if
        state%CUR_BASELINE = state%BASELINESKIP
    end subroutine ts_end_par

    ! TeX's line_break. d is true when a display follows, which changes
    ! the penalty before the last line.
    subroutine line_break(state, d)
        type(typeset_context_t), intent(inout) :: state
        logical, intent(in) :: d
        type(ts_glue_t) :: lskip, rskip, pfill
        integer :: nlines
        integer, allocatable :: brk(:)
        logical, allocatable :: hyph(:)

        ! The glue at the end goes, and \penalty10000 \parfillskip comes.
        if (state%HK(state%HN) == HK_GLUE) state%HN = state%HN - 1
        call align_glue(state, lskip, rskip, pfill)
        call h_new(state, HK_PEN)
        state%HP(state%HN) = INF_PENALTY
        call h_new(state, HK_GLUE)
        state%HW(state%HN) = pfill%w
        state%HST(state%HN) = pfill%st
        state%HSO(state%HN) = pfill%sto

        call find_breaks(state, lskip, rskip, brk, hyph, nlines)
        call post_line_break(state, lskip, rskip, brk, hyph, nlines, d)
    end subroutine line_break

    ! \leftskip, \rightskip and \parfillskip for the alignment, LaTeX's:
    ! \raggedright, \centering and \raggedleft use \@flushglue.
    subroutine align_glue(state, lskip, rskip, pfill)
        type(typeset_context_t), intent(inout) :: state
        type(ts_glue_t), intent(out) :: lskip, rskip, pfill
        type(ts_glue_t), parameter :: FIL = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0)
        lskip = ts_glue_t()
        rskip = ts_glue_t()
        pfill = FIL
        select case (state%P_ALIGN)
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
    subroutine find_breaks(state, lskip, rskip, brk, hyph, nlines)
        type(typeset_context_t), intent(inout) :: state
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
                call hyphenate_all(state)
                hyphenated = .true.
            end if
            if (allocated(sw)) deallocate (sw)
            allocate (sw(6, 0:state%HN))
            call prefix_sums(sw)
            nfree = 4*state%HN + 16
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
            a_line(1) = state%P_PREV_GRAF + 1
            a_fit(1) = DECENT
            a_hyph(1) = .false.
            a_dem(1) = 0
            a_next(1) = 0

            cur = 1
            do while (cur <= state%HN + 1 .and. head /= 0)
                legal = .false.
                pi = 0
                ishyph = .false.
                discw = 0.0_dp
                if (cur == state%HN + 1) then
                    legal = .true.
                    pi = EJECT_PENALTY
                    ishyph = .true.
                else
                    select case (state%HK(cur))
                    case (HK_GLUE)
                        if (cur > 1) legal = precedes_break(cur - 1)
                    case (HK_KERN)
                        if (state%HEXPL(cur) .and. cur < state%HN) legal = state%HK(cur + 1) == HK_GLUE
                    case (HK_PEN)
                        legal = state%HP(cur) < INF_PENALTY
                        pi = state%HP(cur)
                    case (HK_DISC)
                        legal = .true.
                        ishyph = .true.
                        discw = state%HW(cur)
                        if (state%HC0(cur) == 0) then
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
                nlines = a_line(best) - 1 - state%P_PREV_GRAF
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
            precedes_break = state%HK(i) == HK_WORD .or. state%HK(i) == HK_BOX .or. &
                             state%HK(i) == HK_DISC .or. (state%HK(i) == HK_KERN .and. .not. state%HEXPL(i))
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
                    if (minimum < int(AWFUL_BAD, 8) .and. (old_l /= easy_line(state) .or. r == 0)) then
                        call new_active(prev_r)
                        minimum = int(AWFUL_BAD, 8)
                        mind = int(AWFUL_BAD, 8)
                    end if
                    if (r == 0) return
                    linew = line_width(state, l)
                    if (l > easy_line(state)) then
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
                        if (cur <= state%HN) then
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
            if (at <= state%HN) then
                if (state%HK(at) == HK_DISC) return
            end if
            do while (s <= state%HN)
                select case (state%HK(s))
                case (HK_GLUE, HK_PEN)
                    s = s + 1
                case (HK_KERN)
                    if (.not. state%HEXPL(s)) exit
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
            if (cur == state%HN + 1) last = state%HN
            t = bg
            if (last >= start) t = t + sw(:, last) - sw(:, start - 1)
            t(1) = t(1) + discw
        end subroutine line_totals

        subroutine prefix_sums(s)
            real(dp), intent(inout) :: s(:, 0:)
            integer :: i
            s(:, 0) = 0.0_dp
            do i = 1, state%HN
                s(:, i) = s(:, i - 1)
                select case (state%HK(i))
                case (HK_WORD, HK_BOX, HK_KERN)
                    s(1, i) = s(1, i) + state%HW(i)
                case (HK_GLUE)
                    call add_glue(s(:, i), state%HW(i), state%HST(i), state%HSO(i), state%HSH(i))
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
    pure integer function easy_line(state)
        type(typeset_context_t), intent(in) :: state
        if (state%P_HANG /= 0.0_dp) then
            easy_line = 1
        else
            easy_line = 0
        end if
    end function easy_line

    ! The width of line l of the paragraph.
    pure real(dp) function line_width(state, l)
        type(typeset_context_t), intent(in) :: state
        integer, intent(in) :: l
        line_width = state%HSIZE - state%P_LEFT - state%P_RIGHT
        if (l > 1) line_width = line_width - abs(state%P_HANG)
    end function line_width

    ! Where line l starts, from the left margin.
    pure real(dp) function line_indent(state, l)
        type(typeset_context_t), intent(in) :: state
        integer, intent(in) :: l
        line_indent = state%P_LEFT
        if (l > 1 .and. state%P_HANG > 0.0_dp) line_indent = line_indent + state%P_HANG
    end function line_indent

    ! TeX's second pass hyphenates every word that follows glue: each such
    ! word is cut where letters meet other characters, as XeTeX cuts a
    ! word of an OpenType font, and its letters are cut again at the
    ! places the patterns allow, with a discretionary hyphen in each cut.
    ! The pieces are measured separately, as in XeTeX.
    subroutine hyphenate_all(state)
        type(typeset_context_t), intent(inout) :: state
        integer :: i, j, k, a, b, n, npos, pos(64), m
        character(len=64) :: lw
        logical :: ok
        i = 1
        do while (i <= state%HN)
            if (state%HK(i) /= HK_GLUE) then
                i = i + 1
                cycle
            end if
            j = i + 1
            if (j > state%HN) exit
            if (state%HK(j) /= HK_WORD) then
                i = i + 1
                cycle
            end if
            ! What may follow the word for it to be hyphenated: glue, a
            ! penalty, a font kern, another word, or nothing; anything
            ! else and it is left whole.
            ok = .true.
            if (j < state%HN) then
                select case (state%HK(j + 1))
                case (HK_GLUE, HK_PEN, HK_WORD)
                case (HK_KERN)
                    ok = .not. state%HEXPL(j + 1)
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
            do k = state%HC0(j), state%HC1(j)
                if (is_letter(state%CPA(k))) then
                    a = k
                    exit
                end if
            end do
            if (a == 0) then
                i = j + 1
                cycle
            end if
            if (a > state%HC0(j)) then
                call split_word(state, j, a)
                j = j + 1
            end if
            ! The letters run to b.
            b = state%HC1(j)
            do k = state%HC0(j), state%HC1(j)
                if (.not. is_letter(state%CPA(k))) then
                    b = k - 1
                    exit
                end if
            end do
            if (b < state%HC1(j)) call split_word(state, j, b + 1)
            n = b - state%HC0(j) + 1
            if (n < LEFT_HYPHEN_MIN + RIGHT_HYPHEN_MIN .or. n > 63) then
                i = j + 1
                cycle
            end if
            do k = 1, n
                lw(k:k) = lower(state%CPA(state%HC0(j) + k - 1))
            end do
            call hyph_points(lw(1:n), LEFT_HYPHEN_MIN, RIGHT_HYPHEN_MIN, pos, npos)
            ! Cut from the end, so that the earlier positions stay valid.
            do m = npos, 1, -1
                call split_word(state, j, state%HC0(j) + pos(m))
                call insert_disc(state, j + 1)
            end do
            i = j + 1
        end do
    end subroutine hyphenate_all

    ! Node j becomes two words, the second starting at code point c.
    subroutine split_word(state, j, c)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: j, c
        call h_insert(state, j + 1)
        state%HK(j + 1) = HK_WORD
        state%HFACE(j + 1) = state%HFACE(j)
        state%HSZ(j + 1) = state%HSZ(j)
        state%HCOL(j + 1) = state%HCOL(j)
        state%HC0(j + 1) = c
        state%HC1(j + 1) = state%HC1(j)
        state%HC1(j) = c - 1
        call measure(state, j)
        call measure(state, j + 1)
    end subroutine split_word

    ! A discretionary hyphen at position j, in the face of the word
    ! before it.
    subroutine insert_disc(state, j)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: j
        integer :: gf
        call h_insert(state, j)
        state%HK(j) = HK_DISC
        state%HFACE(j) = state%HFACE(j - 1)
        state%HSZ(j) = state%HSZ(j - 1)
        state%HCOL(j) = state%HCOL(j - 1)
        state%HC0(j) = 45
        state%HW(j) = glyph_adv(glyph_for(state%HFACE(j), 45, gf))*state%HSZ(j)
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
    subroutine post_line_break(state, lskip, rskip, brk, hyph, nlines, d)
        type(typeset_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: lskip, rskip
        integer, intent(in) :: brk(:), nlines
        logical, intent(in) :: hyph(:), d
        integer :: l, s, e, pen, best_line, cur_line
        real(dp) :: w, h, dp_
        integer :: i0, i1
        s = 1
        best_line = state%P_PREV_GRAF + nlines + 1
        state%LAST_PAR0 = state%NV + 1
        do l = 1, nlines
            cur_line = state%P_PREV_GRAF + l
            e = brk(l)
            call pack_line(state, s, e, lskip, rskip, line_width(state, cur_line), i0, i1, w, h, dp_)
            call append_box(state, i0, i1, w, h, dp_, line_indent(state, cur_line))
            if (cur_line + 1 /= best_line) then
                pen = INTERLINE_PENALTY
                if (state%P_NOBREAK) pen = INF_PENALTY
                if (cur_line == state%P_PREV_GRAF + 1) then
                    if (state%NOBREAK_NEXT) then
                        pen = pen + INF_PENALTY
                    else
                        pen = pen + state%CLUB_PENALTY
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
                if (pen /= 0) call ts_penalty(state, min(pen, INF_PENALTY))
            end if
            ! The next line starts after the break, discardables dropped.
            s = e + 1
            if (e <= state%HN) then
                if (state%HK(e) /= HK_DISC) then
                    do while (s <= state%HN)
                        if (state%HK(s) == HK_GLUE .or. state%HK(s) == HK_PEN .or. &
                            (state%HK(s) == HK_KERN .and. state%HEXPL(s))) then
                            s = s + 1
                        else
                            exit
                        end if
                    end do
                end if
            end if
        end do
        state%LAST_PAR1 = state%NV
        state%P_PREV_GRAF = state%P_PREV_GRAF + nlines
    end subroutine post_line_break

    ! Pack nodes s..e-1 (and the hyphen of a discretionary at e) into a
    ! line width wide: TeX's hpack, glue set to fit, shrink no further
    ! than its total. The items are appended to the item arena.
    subroutine pack_line(state, s, e, lskip, rskip, width, i0, i1, w, h, d)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: s, e
        type(ts_glue_t), intent(in) :: lskip, rskip
        real(dp), intent(in) :: width
        integer, intent(out) :: i0, i1
        real(dp), intent(out) :: w, h, d
        real(dp) :: t(6), x, ratio, gw, cw, ch, cd
        integer :: k, k1, last, ord, sgn
        logical :: hy
        last = min(e - 1, state%HN)
        t = 0.0_dp
        call add_glue(t, lskip%w, lskip%st, lskip%sto, lskip%sh)
        call add_glue(t, rskip%w, rskip%st, rskip%sto, rskip%sh)
        h = 0.0_dp
        d = 0.0_dp
        k = s
        do while (k <= last)
            select case (state%HK(k))
            case (HK_WORD)
                call chain(state, k, last, e, k1, hy)
                call chain_size(state, k, k1, hy, cw, ch, cd)
                t(1) = t(1) + cw
                h = max(h, ch + state%HRAISE(k))
                d = max(d, cd - state%HRAISE(k))
                k = k1
            case (HK_BOX)
                t(1) = t(1) + state%HW(k)
                h = max(h, state%HH(k) + state%HRAISE(k))
                d = max(d, state%HD(k) - state%HRAISE(k))
            case (HK_KERN)
                t(1) = t(1) + state%HW(k)
            case (HK_GLUE)
                call add_glue(t, state%HW(k), state%HST(k), state%HSO(k), state%HSH(k))
            end select
            k = k + 1
        end do
        ! A hyphen not joined to a word before it stands alone.
        if (e <= state%HN) then
            if (state%HK(e) == HK_DISC .and. state%HC0(e) /= 0) then
                if (.not. joins_hyphen(state, last, e)) t(1) = t(1) + state%HW(e)
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

        i0 = state%NIT + 1
        x = glue_set(lskip%w, lskip%st, lskip%sto, lskip%sh)
        k = s
        do while (k <= last)
            select case (state%HK(k))
            case (HK_WORD)
                call chain(state, k, last, e, k1, hy)
                call emit_chain(state, k, k1, hy, x, cw)
                x = x + cw
                k = k1
            case (HK_BOX)
                call emit_box(state, k, x)
                x = x + state%HW(k)
            case (HK_KERN)
                x = x + state%HW(k)
            case (HK_GLUE)
                gw = glue_set(state%HW(k), state%HST(k), state%HSO(k), state%HSH(k))
                x = x + gw
            end select
            k = k + 1
        end do
        if (e <= state%HN) then
            if (state%HK(e) == HK_DISC .and. state%HC0(e) /= 0) then
                if (.not. joins_hyphen(state, last, e)) call emit_hyphen(state, e, x)
            end if
        end if
        i1 = state%NIT
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
    subroutine chain(state, k, last, e, k1, hy)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: k, last, e
        integer, intent(out) :: k1
        logical, intent(out) :: hy
        integer :: n
        k1 = k
        do
            n = k1 + 1
            if (n > last) exit
            if (state%HK(n) == HK_DISC .and. n + 1 <= last) then
                if (same_font(state, k, n + 1) .and. state%HC0(n + 1) == state%HC1(k1) + 1) then
                    k1 = n + 1
                    cycle
                end if
            else if (state%HK(n) == HK_WORD) then
                if (same_font(state, k, n) .and. state%HC0(n) == state%HC1(k1) + 1) then
                    k1 = n
                    cycle
                end if
            end if
            exit
        end do
        hy = .false.
        if (k1 == last .and. e <= state%HN) hy = joins_hyphen(state, last, e)
    end subroutine chain

    logical function same_font(state, a, b)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: a, b
        same_font = state%HK(b) == HK_WORD .and. state%HFACE(a) == state%HFACE(b) .and. &
                    state%HSZ(a) == state%HSZ(b) .and. state%HCOL(a) == state%HCOL(b) .and. state%HRAISE(a) == &
            state%HRAISE(b)
    end function same_font

    ! Whether the hyphen of the break at e is joined to the word at last.
    logical function joins_hyphen(state, last, e)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: last, e
        joins_hyphen = .false.
        if (last < 1 .or. e > state%HN) return
        if (state%HK(e) /= HK_DISC .or. state%HC0(e) == 0) return
        if (state%HK(last) /= HK_WORD) return
        joins_hyphen = state%HFACE(last) == state%HFACE(e) .and. state%HSZ(last) == state%HSZ(e) .and. &
                       state%HCOL(last) == state%HCOL(e)
    end function joins_hyphen

    ! The code points of a chain, with the hyphen when it has one.
    subroutine chain_cps(state, k, k1, hy, c)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: k, k1
        logical, intent(in) :: hy
        integer, allocatable, intent(out) :: c(:)
        integer :: n
        n = state%HC1(k1) - state%HC0(k) + 1
        if (hy) then
            allocate (c(n + 1))
            c(n + 1) = 45
        else
            allocate (c(n))
        end if
        c(1:n) = state%CPA(state%HC0(k):state%HC1(k1))
    end subroutine chain_cps

    subroutine chain_size(state, k, k1, hy, w, h, d)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: k, k1
        logical, intent(in) :: hy
        real(dp), intent(out) :: w, h, d
        integer, allocatable :: c(:)
        call chain_cps(state, k, k1, hy, c)
        call shape(c, state%HFACE(k), state%HSZ(k), w, h, d)
    end subroutine chain_size

    subroutine emit_chain(state, k, k1, hy, x0, w)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: k, k1
        logical, intent(in) :: hy
        real(dp), intent(in) :: x0
        real(dp), intent(out) :: w
        integer, allocatable :: c(:)
        integer :: j, g, gf, prev, pf
        real(dp) :: x, s
        call chain_cps(state, k, k1, hy, c)
        s = state%HSZ(k)
        x = x0
        prev = 0
        pf = 0
        do j = 1, size(c)
            g = glyph_for(state%HFACE(k), c(j), gf)
            if (prev > 0 .and. gf == pf) x = x + glyph_kern(gf, prev, g)*s
            call it_glyph(state, g, x, state%HRAISE(k), s, state%HCOL(k))
            if (j <= state%HC1(k1) - state%HC0(k) + 1) then
                state%ITFIRST(state%NIT) = state%CPFIRST(state%HC0(k) + j - 1)
                state%ITLAST(state%NIT) = state%CPLAST(state%HC0(k) + j - 1)
            end if
            x = x + glyph_adv(g)*s
            prev = g
            pf = gf
        end do
        w = x - x0
    end subroutine emit_chain

    subroutine emit_hyphen(state, k, x0)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: k
        real(dp), intent(in) :: x0
        integer :: gf
        call it_glyph(state, glyph_for(state%HFACE(k), 45, gf), x0, 0.0_dp, state%HSZ(k), state%HCOL(k))
    end subroutine emit_hyphen

    subroutine emit_box(state, k, x0)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: k
        real(dp), intent(in) :: x0
        integer :: j
        do j = state%HI0(k), state%HI1(k)
            if (state%BXK(j) == 1) then
                call it_glyph(state, state%BXG(j), x0 + state%BXX(j), state%BXY(j) + state%HRAISE(k), state%BXS(j), &
            state%BXC(j))
                state%ITFIRST(state%NIT) = state%BXFIRST(j)
                state%ITLAST(state%NIT) = state%BXLAST(j)
                state%ITMATH(state%NIT) = state%BXMATH(j)
            else
                call it_rule(state, x0 + state%BXX(j), state%BXY(j) + state%HRAISE(k), state%BXW(j), state%BXH(j), &
            state%BXC(j))
            end if
        end do
    end subroutine emit_box

    ! A formula's glyphs and rules as box items, y up.
    subroutine box_items(state, run, rules, col, i0, i1)
        type(typeset_context_t), intent(inout) :: state
        type(glyphrun_t), intent(in) :: run
        type(mrules_t), intent(in) :: rules
        integer, intent(in) :: col
        integer, intent(out) :: i0, i1
        integer :: k, offset
        i0 = state%NBX + 1
        offset = 0
        if (allocated(run%text)) offset = add_source(state, run%text)
        do k = 1, run%n
            call bx_new(state)
            state%BXK(state%NBX) = 1
            state%BXG(state%NBX) = run%gid(k)
            state%BXX(state%NBX) = run%x(k)
            state%BXY(state%NBX) = -run%y(k)
            state%BXS(state%NBX) = run%size(k)
            state%BXC(state%NBX) = col
            state%BXMATH(state%NBX) = run%source_math
            if (allocated(run%first)) then
                if (run%first(k) > 0) then
                    state%BXFIRST(state%NBX) = offset + run%first(k)
                    state%BXLAST(state%NBX) = offset + run%last(k)
                end if
            end if
        end do
        do k = 1, rules%n
            call bx_new(state)
            state%BXK(state%NBX) = 2
            state%BXX(state%NBX) = rules%x(k)
            ! rules%y is the top, y down.
            state%BXY(state%NBX) = -(rules%y(k) + rules%h(k))
            state%BXW(state%NBX) = rules%w(k)
            state%BXH(state%NBX) = rules%h(k)
            state%BXC(state%NBX) = col
        end do
        i1 = state%NBX
    end subroutine box_items

    ! ------------------------------------------------------------------
    ! Displays.
    ! ------------------------------------------------------------------

    ! A displayed formula, TeX's $$...$$: what of the paragraph comes
    ! before it is broken into lines (if anything), the formula is centred
    ! between \abovedisplayskip and \belowdisplayskip (or the short ones
    ! when the line before ends well before it), with its number, tag, at
    ! the right margin, and the paragraph goes on after it, not indented.
    subroutine set_display(state, src, size, tag, col)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: src
        real(dp), intent(in) :: size
        character(len=*), intent(in) :: tag
        integer, intent(in) :: col
        type(glyphrun_t) :: run, trun
        type(mrules_t) :: rules
        real(dp) :: w, h, d, z, e, dd, pre, s, f, x0, tw, ts_
        integer :: k, al, i0, i1, g, gf, prev, pg
        integer, allocatable :: cps(:)
        logical :: inpar
        type(ts_glue_t) :: g1, g2
        real(dp) :: lft, rgt, hg, paragraph_size

        f = size/10.0_dp
        inpar = state%IN_PAR .and. state%HN > 0
        al = state%P_ALIGN
        lft = state%P_LEFT
        rgt = state%P_RIGHT
        hg = state%P_HANG
        paragraph_size = state%P_SIZE
        pre = -huge(1.0_dp)
        pg = 0
        if (inpar) then
            call line_break(state, .true.)
            pre = pre_display_size(state, size)
            pg = state%P_PREV_GRAF
        else if (state%NV > 0) then
            ! A display that starts a paragraph, as \noindent$$ does.
            call v_glue(state, state%PARSKIP)
        end if
        state%IN_PAR = .false.

        call math_formula(src, size, .true., run, rules, w, h, d, context=state%math)
        z = state%HSIZE - lft - rgt
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
            call run_map(trun, 1, trun%n, "("//trim(tag)//")")
        end if
        dd = 0.5_dp*(z - w)
        if (e > 0.0_dp .and. dd < 2.0_dp*e) then
            dd = 0.5_dp*(z - w - e)
        end if
        if (dd < 0.0_dp) dd = 0.0_dp

        ! LaTeX's display skips, scaled from its 10pt ones.
        call ts_penalty(state, PRE_DISPLAY_PENALTY)
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
        call v_glue(state, g1)

        i0 = state%NIT + 1
        x0 = dd
        call emit_run(state, run, x0, 0.0_dp, col)
        do k = 1, rules%n
            call it_rule(state, x0 + rules%x(k), -(rules%y(k) + rules%h(k)), rules%w(k), &
                         rules%h(k), col)
        end do
        ts_ = 0.0_dp
        if (e > 0.0_dp) then
            ts_ = z - e
            call emit_run(state, trun, ts_, 0.0_dp, col)
        end if
        i1 = state%NIT
        call append_box(state, i0, i1, z, h, d, s)
        call ts_penalty(state, POST_DISPLAY_PENALTY)
        call v_glue(state, g2)

        ! The paragraph resumes, unindented, if anything follows.
        call ts_begin_par(state, al, 0.0_dp, lft, rgt, paragraph_size, hg, skip=.false.)
        state%P_PREV_GRAF = pg + 3
    end subroutine set_display

    subroutine emit_run(state, run, x, y, col)
        type(typeset_context_t), intent(inout) :: state
        type(glyphrun_t), intent(in) :: run
        real(dp), intent(in) :: x, y
        integer, intent(in) :: col
        integer :: k, offset
        offset = 0
        if (allocated(run%text)) offset = add_source(state, run%text)
        do k = 1, run%n
            call it_glyph(state, run%gid(k), x + run%x(k), y - run%y(k), run%size(k), col)
            state%ITMATH(state%NIT) = run%source_math
            if (allocated(run%first)) then
                if (run%first(k) > 0) then
                    state%ITFIRST(state%NIT) = offset + run%first(k)
                    state%ITLAST(state%NIT) = offset + run%last(k)
                end if
            end if
        end do
    end subroutine emit_run

    ! TeX's \predisplaysize: where the last line's text ends, from the
    ! left margin, plus two ems.
    real(dp) function pre_display_size(state, size) result(p)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(in) :: size
        integer :: k, last
        real(dp) :: xend
        last = state%NV
        p = -huge(1.0_dp)
        do k = last, 1, -1
            if (state%VK(k) == VK_BOX) exit
        end do
        if (k < 1) return
        xend = 0.0_dp
        if (state%VI1(k) >= state%VI0(k)) then
            xend = maxval(state%ITX(state%VI0(k):state%VI1(k)) + item_width(state, state%VI0(k), state%VI1(k)))
        end if
        p = state%VX(k) + xend + 2.0_dp*size
    end function pre_display_size

    function item_width(state, i0, i1) result(w)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: i0, i1
        real(dp) :: w(i1 - i0 + 1)
        integer :: k
        do k = i0, i1
            if (state%ITK(k) == 1) then
                w(k - i0 + 1) = glyph_adv(state%ITG(k))*state%ITS(k)
            else
                w(k - i0 + 1) = state%ITW(k)
            end if
        end do
    end function item_width

    ! ------------------------------------------------------------------
    ! The vertical list.
    ! ------------------------------------------------------------------

    ! TeX's append_to_vlist: the interline glue, then the box.
    subroutine append_box(state, i0, i1, w, h, d, shift)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: i0, i1
        real(dp), intent(in) :: w, h, d, shift
        real(dp) :: g
        if (state%PREV_DEPTH > IGNORE_DEPTH) then
            g = state%CUR_BASELINE%w - state%PREV_DEPTH - h
            ! In scaled points, as TeX compares: a hair under is equal.
            if (g < state%LINESKIPLIMIT - 1.0e-6_dp) then
                call v_glue(state, state%LINESKIP)
            else
                call v_glue(state, ts_glue_t(g, state%CUR_BASELINE%st, state%CUR_BASELINE%sh, &
                                      state%CUR_BASELINE%sto, state%CUR_BASELINE%sho))
            end if
        end if
        call v_new(state, VK_BOX)
        state%VI0(state%NV) = i0
        state%VI1(state%NV) = i1
        state%VW(state%NV) = w
        state%VH(state%NV) = h
        state%VD(state%NV) = d
        state%VX(state%NV) = shift
        state%PREV_DEPTH = d
    end subroutine append_box

    subroutine v_glue(state, g)
        type(typeset_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: g
        call v_new(state, VK_GLUE)
        state%VW(state%NV) = g%w
        state%VST(state%NV) = g%st
        state%VSH(state%NV) = g%sh
        state%VSO(state%NV) = g%sto
        state%VHO(state%NV) = g%sho
    end subroutine v_glue

    subroutine ts_vskip(state, g)
        type(typeset_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: g
        if (state%IN_PAR) call ts_end_par(state)
        call v_glue(state, g)
    end subroutine ts_vskip

    ! LaTeX's \addvspace: a skip that merges with one just before it, the
    ! larger of the two winning.
    subroutine ts_addvspace(state, g)
        type(typeset_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: g
        if (state%IN_PAR) call ts_end_par(state)
        if (state%NV > 0) then
            if (state%VK(state%NV) == VK_GLUE .and. state%VP(state%NV) == 1) then
                if (g%w > state%VW(state%NV)) then
                    state%VW(state%NV) = g%w
                    state%VST(state%NV) = g%st
                    state%VSH(state%NV) = g%sh
                    state%VSO(state%NV) = g%sto
                end if
                return
            end if
        end if
        call v_glue(state, g)
        state%VP(state%NV) = 1
    end subroutine ts_addvspace

    subroutine ts_vfil(state)
        type(typeset_context_t), intent(inout) :: state
        if (state%IN_PAR) call ts_end_par(state)
        call v_glue(state, ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0))
    end subroutine ts_vfil

    ! A skip that stays at the top of a page, LaTeX's \vspace*: an empty
    ! rule before it, which is not discarded, and which, as a rule does,
    ! leaves no \baselineskip to the line after it.
    subroutine ts_vkeep(state, g)
        type(typeset_context_t), intent(inout) :: state
        type(ts_glue_t), intent(in) :: g
        if (state%IN_PAR) call ts_end_par(state)
        call v_new(state, VK_BOX)
        state%VI0(state%NV) = 1
        state%VI1(state%NV) = 0
        state%PREV_DEPTH = IGNORE_DEPTH
        call v_glue(state, g)
    end subroutine ts_vkeep

    ! An invisible box of the given height and depth in the paragraph,
    ! LaTeX's \strut.
    subroutine ts_strut(state, h, d)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(in) :: h, d
        call h_new(state, HK_BOX)
        state%HH(state%HN) = h
        state%HD(state%HN) = d
    end subroutine ts_strut

    subroutine ts_penalty(state, p)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: p
        call v_new(state, VK_PEN)
        state%VP(state%NV) = p
    end subroutine ts_penalty

    ! LaTeX's \addpenalty: a penalty that goes before a skip just added.
    subroutine ts_addpenalty(state, p)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: p
        type(ts_glue_t) :: g
        integer :: m
        if (state%IN_PAR) call ts_end_par(state)
        if (state%NV == 0) return
        if (state%VK(state%NV) == VK_GLUE) then
            g = ts_glue_t(state%VW(state%NV), state%VST(state%NV), state%VSH(state%NV), state%VSO(state%NV), &
            state%VHO(state%NV))
            m = state%VP(state%NV)
            state%NV = state%NV - 1
            call ts_penalty(state, p)
            call v_glue(state, g)
            state%VP(state%NV) = m
        else
            call ts_penalty(state, p)
        end if
    end subroutine ts_addpenalty

    ! LaTeX's \newpage: \vfil\penalty-10000.
    subroutine ts_page_break(state)
        type(typeset_context_t), intent(inout) :: state
        if (state%IN_PAR) call ts_end_par(state)
        if (state%NV == 0) return
        call ts_vfil(state)
        call ts_penalty(state, EJECT_PENALTY)
        state%PREV_DEPTH = IGNORE_DEPTH
    end subroutine ts_page_break

    ! The next paragraph may not break after its first line, nor before
    ! it: what follows a heading.
    subroutine ts_nobreak_next(state)
        type(typeset_context_t), intent(inout) :: state
        state%NOBREAK_NEXT = .true.
    end subroutine ts_nobreak_next

    ! A horizontal rule, width wide and thick high, centred.
    subroutine ts_rule(state, width, thick, color)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(in) :: width, thick
        integer, intent(in), optional :: color
        integer :: col, i0
        col = state%TEXT_COLOR
        if (present(color)) col = color
        if (state%IN_PAR) call ts_end_par(state)
        i0 = state%NIT + 1
        call it_rule(state, 0.5_dp*(state%HSIZE - width), 0.0_dp, width, thick, col)
        call append_box(state, i0, state%NIT, state%HSIZE, thick, 0.0_dp, 0.0_dp)
    end subroutine ts_rule

    ! A running head from here on: a chapter's (section false), which
    ! even pages carry, or a section's, which odd pages carry; plain is
    ! true for a page that is to have none (where a chapter starts).
    subroutine ts_mark(state, s, plain, section)
        type(typeset_context_t), intent(inout) :: state
        character(len=*), intent(in) :: s
        logical, intent(in) :: plain
        logical, intent(in), optional :: section
        call v_new(state, VK_MARK)
        state%VI0(state%NV) = len(state%MARKS) + 1
        state%MARKS = state%MARKS//s
        state%VI1(state%NV) = len(state%MARKS)
        state%VP(state%NV) = merge(1, 0, plain)
        state%VSO(state%NV) = 0
        if (present(section)) state%VSO(state%NV) = merge(1, 0, section)
    end subroutine ts_mark

    ! ------------------------------------------------------------------
    ! Pages.
    ! ------------------------------------------------------------------

    ! TeX's page builder over the whole vertical list: items are moved
    ! onto the page one by one; at each legal break the cost of breaking
    ! there is computed from the page's badness and the penalty, the
    ! cheapest so far is remembered, and when the page is overfull or a
    ! penalty forces a break, the page ends at the cheapest.
    subroutine ts_paginate(state)
        type(typeset_context_t), intent(inout) :: state
        integer :: i, start, best, c, b, pi
        integer :: least
        real(dp) :: total, depth, so_far(6), goal
        logical :: empty, legal, plain, pplain, packed

        if (state%IN_PAR) call ts_end_par(state)
        do i = 1, state%NV
            if (state%VK(i) /= VK_BOX) cycle
            if (state%VREPEAT(i) > 0) then
                if (repeat_height(state, state%VREPEAT(i)) + state%VH(i) + state%VD(i) > state%VSIZE) &
                    error stop "typeset: repeated header and unbreakable row exceed page body"
            else if (state%VPACKED(i)) then
                if (max(state%TOPSKIP, state%VH(i)) + state%VD(i) > state%VSIZE) &
                    error stop "typeset: unbreakable row exceeds page body"
            end if
        end do
        state%NPAGE = 0
        if (allocated(state%PG0)) deallocate (state%PG0, state%PG1, state%PGHEAD0, state%PGHEAD1, state%PGPLAIN, &
            state%PGSET, state%PGORD, &
                                        state%PGSTART, state%PGREPEAT)
        allocate (state%PG0(state%NV + 1), state%PG1(state%NV + 1), state%PGHEAD0(state%NV + 1), state%PGHEAD1(state%NV &
            + 1), &
                  state%PGPLAIN(state%NV + 1), state%PGSET(state%NV + 1), state%PGORD(state%NV + 1), &
            state%PGSTART(state%NV + 1), state%PGREPEAT(state%NV + 1))
        state%PGREPEAT(:) = 0
        start = 1
        do while (start <= state%NV)
            state%PGSTART(state%NPAGE + 1) = start
            empty = .true.
            total = 0.0_dp
            depth = 0.0_dp
            so_far = 0.0_dp
            goal = state%VSIZE
            least = AWFUL_BAD
            best = 0
            plain = .false.
            pplain = .false.
            packed = .false.
            i = start
            do while (i <= state%NV)
                legal = .false.
                pi = 0
                select case (state%VK(i))
                case (VK_GLUE)
                    if (.not. empty) legal = state%VK(i - 1) == VK_BOX
                case (VK_KERN)
                    if (.not. empty .and. i < state%NV) legal = state%VK(i + 1) == VK_GLUE
                case (VK_PEN)
                    if (.not. empty) then
                        legal = state%VP(i) < INF_PENALTY
                        pi = state%VP(i)
                    end if
                case (VK_MARK)
                    if (state%VP(i) == 1) pplain = .true.
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
                select case (state%VK(i))
                case (VK_BOX)
                    packed = packed .or. state%VPACKED(i)
                    if (empty) then
                        ! \topskip less the box's height comes first.
                        empty = .false.
                        start = i
                        state%PGREPEAT(state%NPAGE + 1) = state%VREPEAT(i)
                        if (state%VREPEAT(i) > 0) then
                            total = repeat_height(state, state%VREPEAT(i)) + state%VH(i)
                        else
                            total = max(state%TOPSKIP - state%VH(i), 0.0_dp) + state%VH(i)
                        end if
                    else
                        total = total + depth + state%VH(i)
                    end if
                    depth = state%VD(i)
                case (VK_GLUE)
                    if (.not. empty) then
                        so_far(2 + state%VSO(i)) = so_far(2 + state%VSO(i)) + state%VST(i)
                        if (state%VHO(i) == 0) so_far(6) = so_far(6) + state%VSH(i)
                        total = total + depth + state%VW(i)
                        depth = 0.0_dp
                    end if
                case (VK_KERN)
                    if (.not. empty) then
                        total = total + depth + state%VW(i)
                        depth = 0.0_dp
                    end if
                end select
                if (depth > state%MAXDEPTH) then
                    total = total + depth - state%MAXDEPTH
                    depth = state%MAXDEPTH
                end if
                i = i + 1
            end do
            if (empty) exit
            ! Running out of material ends the page, as \end{document} does.
            if (i > state%NV) then
                ! Packed rows need no trailing glue or penalty. An overflowing
                ! final row must still use the last legal break before it.
                if (.not. packed .or. total - goal <= so_far(6) .or. best == 0) then
                    best = state%NV + 1
                    plain = pplain
                end if
            end if
            state%NPAGE = state%NPAGE + 1
            state%PG0(state%NPAGE) = start
            state%PG1(state%NPAGE) = best - 1
            state%PGPLAIN(state%NPAGE) = plain
            call page_head(state, state%NPAGE, state%PGHEAD0(state%NPAGE), state%PGHEAD1(state%NPAGE))
            call set_page_glue(state, state%NPAGE)
            ! What is left starts at the break, where the glue or penalty
            ! of the break is discarded at the top of the next page.
            start = best
        end do
    end subroutine ts_paginate

    real(dp) function repeat_height(state, handle) result(height)
        type(typeset_context_t), intent(in) :: state
        integer, intent(in) :: handle
        real(dp) :: w, h, baseline
        call state%graphics%metrics(w, h, baseline, handle)
        height = h + max(state%TOPSKIP - baseline, 0.0_dp)
    end function repeat_height

    ! The running head of page p, as LaTeX's headings style has it: an
    ! even page carries the chapter's mark (the last on the page or
    ! before it), an odd one the section's (the first on the page, or the
    ! last before it).
    subroutine page_head(state, p, h0, h1)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: p
        integer, intent(out) :: h0, h1
        integer :: k, want
        h0 = 1
        h1 = 0
        want = merge(0, 1, mod(p, 2) == 0)
        if (want == 1) then
            do k = state%PGSTART(p), state%PG1(p)
                if (state%VK(k) == VK_MARK .and. state%VSO(k) == 1) then
                    h0 = state%VI0(k)
                    h1 = state%VI1(k)
                    return
                end if
            end do
        end if
        do k = min(state%PG1(p), state%NV), 1, -1
            if (state%VK(k) == VK_MARK .and. state%VSO(k) == want) then
                h0 = state%VI0(k)
                h1 = state%VI1(k)
                return
            end if
        end do
    end subroutine page_head

    ! How the glue of page p is set, as LaTeX boxes a page to \textheight:
    ! infinite stretch, where there is any (\vfill), takes up the room
    ! left; otherwise \raggedbottom leaves the glue at its natural size
    ! and \flushbottom stretches it to fill the page; a page too full
    ! shrinks its glue, no further than its shrink.
    subroutine set_page_glue(state, p)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: p
        real(dp) :: total, depth, st(0:3), shrink
        integer :: k, o
        logical :: first
        total = 0.0_dp
        depth = 0.0_dp
        st = 0.0_dp
        shrink = 0.0_dp
        first = .true.
        do k = state%PG0(p), state%PG1(p)
            select case (state%VK(k))
            case (VK_BOX)
                if (first) then
                    if (state%PGREPEAT(p) > 0) then
                        total = repeat_height(state, state%PGREPEAT(p)) + state%VH(k)
                    else
                        total = max(state%TOPSKIP, state%VH(k))
                    end if
                    first = .false.
                else
                    total = total + depth + state%VH(k)
                end if
                depth = state%VD(k)
            case (VK_GLUE)
                if (.not. first) then
                    total = total + depth + state%VW(k)
                    depth = 0.0_dp
                    st(state%VSO(k)) = st(state%VSO(k)) + state%VST(k)
                    if (state%VHO(k) == 0) shrink = shrink + state%VSH(k)
                end if
            case (VK_KERN)
                if (.not. first) then
                    total = total + depth + state%VW(k)
                    depth = 0.0_dp
                end if
            end select
        end do
        state%PGSET(p) = 0.0_dp
        state%PGORD(p) = 0
        if (total < state%VSIZE) then
            do o = 3, 1, -1
                if (st(o) > 0.0_dp) exit
            end do
            if (o >= 1) then
                state%PGSET(p) = (state%VSIZE - total)/st(o)
                state%PGORD(p) = o
            else if (state%FLUSH_BOTTOM .and. st(0) > 0.0_dp .and. p < filling_limit(state)) then
                state%PGSET(p) = (state%VSIZE - total)/st(0)
            end if
        else if (total > state%VSIZE .and. shrink > 0.0_dp) then
            state%PGSET(p) = -min((total - state%VSIZE)/shrink, 1.0_dp)
        end if
    end subroutine set_page_glue

    ! Pages before the last are filled; the last ends with LaTeX's
    ! \clearpage, whose \vfil takes up what is left.
    integer function filling_limit(state)
        type(typeset_context_t), intent(inout) :: state
        filling_limit = huge(1)
        if (state%PG1(state%NPAGE) >= state%NV) filling_limit = state%NPAGE
    end function filling_limit

    integer function ts_page_count(state)
        type(typeset_context_t), intent(inout) :: state
        ts_page_count = state%NPAGE
    end function ts_page_count

    subroutine ts_import_frame(state, frame, handle)
        type(typeset_context_t), intent(inout) :: state
        type(frame_t), intent(in) :: frame
        integer, intent(out) :: handle
        call state%graphics%import_frame(frame, handle)
    end subroutine ts_import_frame

    ! An unbreakable block. Its contents remain a shared child frame.
    ! interline=false omits the preceding interline glue. repeat_before is
    ! an imported frame drawn above this block only when it starts a page.
    subroutine ts_place_frame(state, handle, left, right, align, interline, repeat_before)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: handle
        real(dp), intent(in), optional :: left, right
        integer, intent(in), optional :: align
        logical, intent(in), optional :: interline
        integer, intent(in), optional :: repeat_before
        real(dp) :: w, h, baseline, x, remaining, rm
        real(dp) :: rw, rh
        integer :: i0, al, repeat
        logical :: packed
        call ts_end_par(state)
        call state%graphics%metrics(w, h, baseline, handle)
        repeat = 0
        if (present(repeat_before)) repeat = repeat_before
        if (repeat < 0 .or. repeat == 1) error stop "typeset: repeat_before is not an imported frame handle"
        if (repeat > 0) call state%graphics%metrics(rw, rh, handle=repeat)
        packed = .false.
        if (present(interline)) then
            packed = .not. interline
            if (packed) state%PREV_DEPTH = IGNORE_DEPTH
        end if
        x = 0.0_dp
        rm = 0.0_dp
        if (present(left)) x = left
        if (present(right)) rm = right
        al = ALIGN_LEFT
        if (present(align)) al = align
        remaining = max(0.0_dp, state%HSIZE - x - rm - w)
        if (al == ALIGN_CENTER) x = x + 0.5_dp*remaining
        if (al == ALIGN_RIGHT) x = x + remaining
        call it_new(state)
        i0 = state%NIT
        state%ITK(i0) = 3
        state%ITG(i0) = handle
        state%ITY(i0) = baseline
        state%ITW(i0) = w
        state%ITH(i0) = h
        call append_box(state, i0, i0, w, baseline, h - baseline, x)
        state%VREPEAT(state%NV) = repeat
        state%VPACKED(state%NV) = packed .or. repeat > 0
    end subroutine ts_place_frame

    subroutine ts_finish(state, document)
        type(typeset_context_t), intent(inout) :: state
        type(paged_document_t), intent(out) :: document
        type(recording_renderer_t) :: rec
        type(frame_t) :: page
        type(paint_t) :: background
        integer :: p
        call ts_paginate(state)
        call document%clear()
        background = color_paint(state%PAGE_COLOR)
        do p = 1, max(1, state%NPAGE)
            call rec%open_canvas(state%PAPER_W, state%PAPER_H, bg_rgb=background%fill_rgb)
            if (p <= state%NPAGE) call ts_page_draw(state, rec, p)
            call rec%close_canvas()
            call rec%take(page)
            call document%add_page(page)
        end do
    end subroutine ts_finish

    ! Pack the whole flow at natural vertical spacing, without page furniture.
    subroutine ts_finish_frame(state, frame)
        type(typeset_context_t), intent(inout) :: state
        type(frame_t), intent(out) :: frame
        type(recording_renderer_t) :: rec
        real(dp) :: bottom, baseline
        call ts_end_par(state)
        call rec%open_canvas(state%HSIZE, 0.0_dp)
        call draw_vertical(state, rec, 1, state%NV, 0.0_dp, 0.0_dp, 0.0_dp, 0, bottom, baseline)
        call rec%close_canvas()
        call rec%take(frame)
        call frame%set_size(state%HSIZE, max(0.0_dp, bottom))
        call frame%set_baseline(baseline)
    end subroutine ts_finish_frame

    subroutine draw_vertical(state, r, first_node, last_node, left, top, ratio, order, bottom, baseline, repeat_before)
        type(typeset_context_t), intent(inout) :: state
        class(renderer_t), intent(inout) :: r
        integer, intent(in) :: first_node, last_node, order
        real(dp), intent(in) :: left, top, ratio
        real(dp), intent(out) :: bottom, baseline
        integer, intent(in), optional :: repeat_before
        type(clip_t) :: clip
        type(glyphrun_t) :: run
        real(dp) :: y, depth, gw, w, h, base, matrix(6)
        integer :: k, source_end, repeat
        logical :: first
        y = top
        depth = 0.0_dp
        first = .true.
        baseline = 0.0_dp
        source_end = 0
        repeat = 0
        if (present(repeat_before)) repeat = repeat_before
        do k = first_node, last_node
            select case (state%VK(k))
            case (VK_BOX)
                if (first) then
                    if (repeat > 0) then
                        call state%graphics%metrics(w, h, base, repeat)
                        matrix = IDENTITY
                        matrix(5:6) = [left + state%VX(k), y + max(state%TOPSKIP - base, 0.0_dp)]
                        call r%begin_frame(matrix, clip)
                        call state%graphics%draw(r, repeat)
                        call r%end_frame()
                        y = y + repeat_height(state, repeat) + state%VH(k)
                    else
                        y = y + max(state%TOPSKIP, state%VH(k))
                    end if
                    baseline = y
                    first = .false.
                else
                    y = y + depth + state%VH(k)
                end if
                call draw_box(state, r, k, left + state%VX(k), y, source_end)
                depth = state%VD(k)
            case (VK_GLUE)
                if (.not. first) then
                    gw = state%VW(k)
                    if (ratio < 0.0_dp .and. state%VHO(k) == 0) gw = gw + ratio*state%VSH(k)
                    if (ratio > 0.0_dp .and. state%VSO(k) == order) gw = gw + ratio*state%VST(k)
                    y = y + depth + gw
                    depth = 0.0_dp
                end if
            case (VK_KERN)
                if (.not. first) then
                    y = y + depth + state%VW(k)
                    depth = 0.0_dp
                end if
            end select
        end do
        bottom = y + depth
        if (last_node == state%NV .and. state%SOURCE_EXACT_END > source_end) then
            if (source_white(state%SOURCE_TEXT(source_end + 1:state%SOURCE_EXACT_END))) then
                run%text = state%SOURCE_TEXT(source_end + 1:state%SOURCE_EXACT_END)
                call r%draw_glyphs(left, y, run, color_paint(state%TEXT_COLOR), 0.0_dp)
            end if
        end if
    end subroutine draw_vertical

    ! Draw page p on r, which the caller has opened at the paper's size.
    subroutine ts_page_draw(state, r, p)
        type(typeset_context_t), intent(inout) :: state
        class(renderer_t), intent(inout) :: r
        integer, intent(in) :: p
        real(dp) :: bottom, baseline
        character(len=16) :: num
        call draw_vertical(state, r, state%PG0(p), state%PG1(p), state%MARGIN_L, state%MARGIN_T, &
                           state%PGSET(p), state%PGORD(p), bottom, baseline, state%PGREPEAT(p))
        if (state%PAGE_NUMBERS .and. (.not. state%HEADINGS .or. state%PGPLAIN(p))) then
            write (num, "(I0)") p
            call draw_string(state, r, trim(num), FACE_REGULAR, state%FONT_SIZE, &
                             state%MARGIN_L + 0.5_dp*state%HSIZE, state%MARGIN_T + state%VSIZE + state%FOOTSKIP, 1)
        else if (state%HEADINGS) then
            write (num, "(I0)") p
            ! LaTeX's headings: the number at the outer edge, the head in
            ! slanted capitals at the inner one; here, italic.
            if (mod(p, 2) == 0) then
                call draw_string(state, r, trim(num), FACE_REGULAR, state%FONT_SIZE, state%MARGIN_L, &
                                 state%MARGIN_T - 2.5_dp*state%FONT_SIZE, 0)
                if (state%PGHEAD1(p) >= state%PGHEAD0(p)) &
                    call draw_string(state, r, state%MARKS(state%PGHEAD0(p):state%PGHEAD1(p)), FACE_ITALIC, &
                                     state%FONT_SIZE, state%MARGIN_L + state%HSIZE, &
                                     state%MARGIN_T - 2.5_dp*state%FONT_SIZE, 2)
            else
                call draw_string(state, r, trim(num), FACE_REGULAR, state%FONT_SIZE, state%MARGIN_L + state%HSIZE, &
                                 state%MARGIN_T - 2.5_dp*state%FONT_SIZE, 2)
                if (state%PGHEAD1(p) >= state%PGHEAD0(p)) &
                    call draw_string(state, r, state%MARKS(state%PGHEAD0(p):state%PGHEAD1(p)), FACE_ITALIC, &
                                     state%FONT_SIZE, state%MARGIN_L, state%MARGIN_T - 2.5_dp*state%FONT_SIZE, 0)
            end if
        end if
    end subroutine ts_page_draw

    ! Batch only adjacent glyphs: grouping all glyphs of a colour would
    ! reorder both painting and logical text.
    subroutine draw_box(state, r, k, x, y, source_end)
        type(typeset_context_t), intent(inout) :: state
        class(renderer_t), intent(inout) :: r
        integer, intent(in) :: k
        real(dp), intent(in) :: x, y
        integer, intent(inout) :: source_end
        type(glyphrun_t) :: run
        type(clip_t) :: clip
        real(dp) :: matrix(6)
        integer :: j, start, c, lo, hi, g, cp, nb, next
        j = state%VI0(k)
        do while (j <= state%VI1(k))
            select case (state%ITK(j))
            case (1)
                start = j
                c = state%ITC(j)
                run%n = 0
                run%source_math = state%ITMATH(j)
                lo = huge(1)
                hi = 0
                do while (j <= state%VI1(k))
                    if (state%ITK(j) /= 1 .or. state%ITC(j) /= c) exit
                    if (state%ITMATH(j) .neqv. run%source_math) exit
                    call run_add(run, state%ITG(j), state%ITX(j), -state%ITY(j), state%ITS(j))
                    if (state%ITFIRST(j) > 0) lo = min(lo, state%ITFIRST(j))
                    hi = max(hi, state%ITLAST(j))
                    j = j + 1
                end do
                run%text = ""
                if (hi >= lo) then
                    if (state%SOURCE_EXACT_END > 0) then
                        if (source_end == 0 .and. lo > 1) then
                            if (source_white(state%SOURCE_TEXT(:lo - 1))) lo = 1
                        end if
                        next = hi + 1
                        do while (next <= state%SOURCE_EXACT_END)
                            call utf8_next(state%SOURCE_TEXT, next, cp, nb)
                            if (.not. source_white(state%SOURCE_TEXT(next:next + nb - 1))) exit
                            hi = next + nb - 1
                            next = hi + 1
                        end do
                    end if
                    if (source_end > 0 .and. lo > source_end + 1) then
                        if (source_white(state%SOURCE_TEXT(source_end + 1:lo - 1))) lo = source_end + 1
                    end if
                    run%text = state%SOURCE_TEXT(lo:hi)
                    do g = 1, run%n
                        if (state%ITFIRST(start + g - 1) == 0) cycle
                        run%first(g) = state%ITFIRST(start + g - 1) - lo + 1
                        run%last(g) = state%ITLAST(start + g - 1) - lo + 1
                    end do
                    source_end = max(source_end, hi)
                end if
                call r%draw_glyphs(x, y, run, color_paint(c), 0.0_dp)
            case (2)
                call r%draw_rect(x + state%ITX(j), y - state%ITY(j) - state%ITH(j), &
                                 state%ITW(j), state%ITH(j), color_paint(state%ITC(j)))
                j = j + 1
            case (3)
                matrix = IDENTITY
                matrix(5:6) = [x + state%ITX(j), y - state%ITY(j)]
                call r%begin_frame(matrix, clip)
                call state%graphics%draw(r, state%ITG(j))
                call r%end_frame()
                j = j + 1
            case default
                error stop "typeset: invalid finished item"
            end select
        end do
    end subroutine draw_box

    logical function source_white(text) result(white)
        character(len=*), intent(in) :: text
        integer :: i, cp, n
        white = .false.
        i = 1
        do while (i <= len(text))
            call utf8_next(text, i, cp, n)
            if (cp /= 9 .and. cp /= 10 .and. cp /= 13 .and. cp /= 32 .and. cp /= 160) return
            i = i + n
        end do
        white = .true.
    end function source_white

    function color_paint(col) result(p)
        integer, intent(in) :: col
        type(paint_t) :: p
        p%filled = .true.
        p%fill_rgb = [ishft(col, -16), iand(ishft(col, -8), 255), iand(col, 255)]
    end function color_paint

    ! A string on the page, anchored at its start (0), middle (1) or end
    ! (2), its baseline at y.
    subroutine draw_string(state, r, s, face, size, x, y, anchor)
        type(typeset_context_t), intent(inout) :: state
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
        call run_map(run, 1, run%n, s)
        call r%draw_glyphs(x - 0.5_dp*anchor*pen, y, run, color_paint(state%TEXT_COLOR), 0.0_dp)
    end subroutine draw_string

    ! ------------------------------------------------------------------
    ! For tests: the lines of the last paragraph.
    ! ------------------------------------------------------------------

    subroutine ts_par_lines(state, i0, i1)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(out) :: i0, i1
        i0 = state%LAST_PAR0
        i1 = state%LAST_PAR1
    end subroutine ts_par_lines

    integer function ts_line_count(state)
        type(typeset_context_t), intent(inout) :: state
        integer :: k
        ts_line_count = 0
        do k = state%LAST_PAR0, state%LAST_PAR1
            if (state%VK(k) == VK_BOX) ts_line_count = ts_line_count + 1
        end do
    end function ts_line_count

    ! Line l of the last paragraph: its glyphs' code points (as glyph ids)
    ! and x positions.
    subroutine ts_line_info(state, l, gids, xs, n)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: l
        integer, allocatable, intent(out) :: gids(:)
        real(dp), allocatable, intent(out) :: xs(:)
        integer, intent(out) :: n
        integer :: k, c, j
        c = 0
        n = 0
        do k = state%LAST_PAR0, state%LAST_PAR1
            if (state%VK(k) /= VK_BOX) cycle
            c = c + 1
            if (c /= l) cycle
            allocate (gids(state%VI1(k) - state%VI0(k) + 1), xs(state%VI1(k) - state%VI0(k) + 1))
            do j = state%VI0(k), state%VI1(k)
                if (state%ITK(j) /= 1) cycle
                n = n + 1
                gids(n) = state%ITG(j)
                xs(n) = state%ITX(j) + state%VX(k)
            end do
            return
        end do
        allocate (gids(0), xs(0))
    end subroutine ts_line_info

    ! ------------------------------------------------------------------
    ! The arenas.
    ! ------------------------------------------------------------------

    subroutine h_new(state, kind)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: kind
        call h_reserve(state, state%HN + 1)
        state%HN = state%HN + 1
        call h_clear(state, state%HN)
        state%HK(state%HN) = kind
    end subroutine h_new

    subroutine h_clear(state, i)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: i
        state%HK(i) = 0
        state%HFACE(i) = FACE_REGULAR
        state%HCOL(i) = state%TEXT_COLOR
        state%HC0(i) = 1
        state%HC1(i) = 0
        state%HI0(i) = 1
        state%HI1(i) = 0
        state%HSO(i) = 0
        state%HHO(i) = 0
        state%HP(i) = 0
        state%HEXPL(i) = .false.
        state%HW(i) = 0.0_dp
        state%HH(i) = 0.0_dp
        state%HD(i) = 0.0_dp
        state%HST(i) = 0.0_dp
        state%HSH(i) = 0.0_dp
        state%HSZ(i) = state%FONT_SIZE
        state%HRAISE(i) = 0.0_dp
    end subroutine h_clear

    ! Make room for a node at j, moving the nodes from j on up by one.
    subroutine h_insert(state, j)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: j
        call h_reserve(state, state%HN + 1)
        state%HK(j + 1:state%HN + 1) = state%HK(j:state%HN)
        state%HFACE(j + 1:state%HN + 1) = state%HFACE(j:state%HN)
        state%HCOL(j + 1:state%HN + 1) = state%HCOL(j:state%HN)
        state%HC0(j + 1:state%HN + 1) = state%HC0(j:state%HN)
        state%HC1(j + 1:state%HN + 1) = state%HC1(j:state%HN)
        state%HI0(j + 1:state%HN + 1) = state%HI0(j:state%HN)
        state%HI1(j + 1:state%HN + 1) = state%HI1(j:state%HN)
        state%HSO(j + 1:state%HN + 1) = state%HSO(j:state%HN)
        state%HHO(j + 1:state%HN + 1) = state%HHO(j:state%HN)
        state%HP(j + 1:state%HN + 1) = state%HP(j:state%HN)
        state%HEXPL(j + 1:state%HN + 1) = state%HEXPL(j:state%HN)
        state%HW(j + 1:state%HN + 1) = state%HW(j:state%HN)
        state%HH(j + 1:state%HN + 1) = state%HH(j:state%HN)
        state%HD(j + 1:state%HN + 1) = state%HD(j:state%HN)
        state%HST(j + 1:state%HN + 1) = state%HST(j:state%HN)
        state%HSH(j + 1:state%HN + 1) = state%HSH(j:state%HN)
        state%HSZ(j + 1:state%HN + 1) = state%HSZ(j:state%HN)
        state%HRAISE(j + 1:state%HN + 1) = state%HRAISE(j:state%HN)
        state%HN = state%HN + 1
        call h_clear(state, j)
    end subroutine h_insert

    subroutine h_reserve(state, n)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: n
        integer :: cap
        if (.not. allocated(state%HK)) then
            cap = 256
        else if (n > size(state%HK)) then
            cap = 2*n
        else
            return
        end if
        call grow_i(state%HK, cap)
        call grow_i(state%HFACE, cap)
        call grow_i(state%HCOL, cap)
        call grow_i(state%HC0, cap)
        call grow_i(state%HC1, cap)
        call grow_i(state%HI0, cap)
        call grow_i(state%HI1, cap)
        call grow_i(state%HSO, cap)
        call grow_i(state%HHO, cap)
        call grow_i(state%HP, cap)
        call grow_l(state%HEXPL, cap)
        call grow_r(state%HW, cap)
        call grow_r(state%HH, cap)
        call grow_r(state%HD, cap)
        call grow_r(state%HST, cap)
        call grow_r(state%HSH, cap)
        call grow_r(state%HSZ, cap)
        call grow_r(state%HRAISE, cap)
    end subroutine h_reserve

    subroutine cp_reserve(state, extra)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: extra
        integer :: cap
        cap = 0
        if (.not. allocated(state%CPA)) then
            cap = max(1024, 2*extra)
        else if (state%NCP + extra > size(state%CPA)) then
            cap = 2*(state%NCP + extra)
        end if
        if (cap == 0) return
        call grow_i(state%CPA, cap)
        call grow_i(state%CPFIRST, cap)
        call grow_i(state%CPLAST, cap)
    end subroutine cp_reserve

    subroutine bx_new(state)
        type(typeset_context_t), intent(inout) :: state
        integer :: cap
        if (.not. allocated(state%BXK)) then
            cap = 256
        else if (state%NBX + 1 > size(state%BXK)) then
            cap = 2*size(state%BXK)
        else
            cap = 0
        end if
        if (cap > 0) then
            call grow_i(state%BXK, cap)
            call grow_i(state%BXG, cap)
            call grow_i(state%BXC, cap)
            call grow_i(state%BXFIRST, cap)
            call grow_i(state%BXLAST, cap)
            call grow_l(state%BXMATH, cap)
            call grow_r(state%BXX, cap)
            call grow_r(state%BXY, cap)
            call grow_r(state%BXS, cap)
            call grow_r(state%BXW, cap)
            call grow_r(state%BXH, cap)
        end if
        state%NBX = state%NBX + 1
        state%BXK(state%NBX) = 0
        state%BXG(state%NBX) = 0
        state%BXC(state%NBX) = 0
        state%BXFIRST(state%NBX) = 0
        state%BXLAST(state%NBX) = 0
        state%BXMATH(state%NBX) = .false.
        state%BXX(state%NBX) = 0.0_dp
        state%BXY(state%NBX) = 0.0_dp
        state%BXS(state%NBX) = 0.0_dp
        state%BXW(state%NBX) = 0.0_dp
        state%BXH(state%NBX) = 0.0_dp
    end subroutine bx_new

    subroutine it_new(state)
        type(typeset_context_t), intent(inout) :: state
        integer :: cap
        if (.not. allocated(state%ITK)) then
            cap = 4096
        else if (state%NIT + 1 > size(state%ITK)) then
            cap = 2*size(state%ITK)
        else
            cap = 0
        end if
        if (cap > 0) then
            call grow_i(state%ITK, cap)
            call grow_i(state%ITG, cap)
            call grow_i(state%ITC, cap)
            call grow_i(state%ITFIRST, cap)
            call grow_i(state%ITLAST, cap)
            call grow_l(state%ITMATH, cap)
            call grow_r(state%ITX, cap)
            call grow_r(state%ITY, cap)
            call grow_r(state%ITS, cap)
            call grow_r(state%ITW, cap)
            call grow_r(state%ITH, cap)
        end if
        state%NIT = state%NIT + 1
        state%ITK(state%NIT) = 0
        state%ITG(state%NIT) = 0
        state%ITC(state%NIT) = 0
        state%ITFIRST(state%NIT) = 0
        state%ITLAST(state%NIT) = 0
        state%ITMATH(state%NIT) = .false.
        state%ITX(state%NIT) = 0.0_dp
        state%ITY(state%NIT) = 0.0_dp
        state%ITS(state%NIT) = 0.0_dp
        state%ITW(state%NIT) = 0.0_dp
        state%ITH(state%NIT) = 0.0_dp
    end subroutine it_new

    subroutine it_glyph(state, g, x, y, s, col)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: g, col
        real(dp), intent(in) :: x, y, s
        call it_new(state)
        state%ITK(state%NIT) = 1
        state%ITG(state%NIT) = g
        state%ITX(state%NIT) = x
        state%ITY(state%NIT) = y
        state%ITS(state%NIT) = s
        state%ITC(state%NIT) = col
    end subroutine it_glyph

    subroutine it_rule(state, x, y, w, h, col)
        type(typeset_context_t), intent(inout) :: state
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: col
        call it_new(state)
        state%ITK(state%NIT) = 2
        state%ITX(state%NIT) = x
        state%ITY(state%NIT) = y
        state%ITW(state%NIT) = w
        state%ITH(state%NIT) = h
        state%ITC(state%NIT) = col
    end subroutine it_rule

    subroutine v_new(state, kind)
        type(typeset_context_t), intent(inout) :: state
        integer, intent(in) :: kind
        integer :: cap
        if (.not. allocated(state%VK)) then
            cap = 1024
        else if (state%NV + 1 > size(state%VK)) then
            cap = 2*size(state%VK)
        else
            cap = 0
        end if
        if (cap > 0) then
            call grow_i(state%VK, cap)
            call grow_i(state%VSO, cap)
            call grow_i(state%VHO, cap)
            call grow_i(state%VP, cap)
            call grow_i(state%VI0, cap)
            call grow_i(state%VI1, cap)
            call grow_i(state%VREPEAT, cap)
            call grow_l(state%VPACKED, cap)
            call grow_r(state%VW, cap)
            call grow_r(state%VH, cap)
            call grow_r(state%VD, cap)
            call grow_r(state%VST, cap)
            call grow_r(state%VSH, cap)
            call grow_r(state%VX, cap)
        end if
        state%NV = state%NV + 1
        state%VK(state%NV) = kind
        state%VSO(state%NV) = 0
        state%VHO(state%NV) = 0
        state%VP(state%NV) = 0
        state%VI0(state%NV) = 1
        state%VI1(state%NV) = 0
        state%VREPEAT(state%NV) = 0
        state%VPACKED(state%NV) = .false.
        state%VW(state%NV) = 0.0_dp
        state%VH(state%NV) = 0.0_dp
        state%VD(state%NV) = 0.0_dp
        state%VST(state%NV) = 0.0_dp
        state%VSH(state%NV) = 0.0_dp
        state%VX(state%NV) = 0.0_dp
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
