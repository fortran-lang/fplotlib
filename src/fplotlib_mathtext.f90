! Mathtext layout.
!
! matplotlib lets any label contain a TeX fragment between dollar signs,
! and that is by far the most used piece of it: exponents in "$10^{3}$"
! and indices in "$x_i$". The layout is done here, once, and turned into
! a list of positioned glyphs and rules (fraction bars, radical bars)
! that every backend draws the way it draws any other text.
!
! The layout is TeX's (The TeXbook, Appendix G), with every dimension
! read from the OpenType MATH table of the math font, Lete Sans Math, as
! LuaTeX, XeTeX and Typst do:
!
!   * a fragment is parsed into a list of noads -- atoms with a nucleus
!     and optional scripts, fractions and stacks, radicals, accents,
!     over- and underlines, delimited groups, style changes and explicit
!     spaces;
!   * the list is turned into boxes in a style (display, text, script,
!     scriptscript, each possibly cramped), which decides the size, the
!     glyphs (the script styles take the font's script-size alternates)
!     and which MATH constants apply;
!   * the boxes are set side by side with TeX's inter-atom glue.
!
! A box is a range of items in one arena (glyphs and rules, positioned
! relative to the box's origin, y up) together with its width, height and
! depth. Laying a sub-list out appends its items contiguously, so placing
! a box is moving its range. Nothing is truncated: the arenas grow.
!
! Where TeX leaves a choice to the macro package, the choice is LaTeX's
! with amsmath and unicode-math (\big, \cfrac, \text), so that XeTeX is
! the reference the layout is checked against. \binom is TeX's own
! \atopwithdelims(), which sizes the parentheses by the MATH table.
!
! Matched delimiters grow by themselves, as Typst's do (auto_pair and
! settle_auto): a pair of the same kind in one list encloses what is
! between them, and if that is taller than the plain delimiters they
! become a \left...\right sized by Typst's rule; otherwise they are set
! exactly as written. Escaped (\( \[) and braced delimiters never pair.
!
! Text outside the dollar signs is set in Lato, as any other text; a
! dollar sign written \$ is a dollar sign, in text and in math.
module fplotlib_mathtext
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_render, only: glyphrun_t
    use fplotlib_text, only: text_layout, run_add
    use fplotlib_mathsym, only: sym_lookup, sym_class, CL_ORD, CL_OP, CL_BIN, &
                                CL_REL, CL_OPEN, CL_CLOSE, CL_PUNCT, CL_INNER
    use fplotlib_glyphs, only: glyph_cmap, glyph_adv, glyph_bbox, glyph_italic, &
                               glyph_variants, glyph_assembly, glyph_ssty, &
                               glyph_math_kern, glyph_top_accent, glyph_dotless, &
                               math_const, math_percent, FACE_MATH, FACE_REGULAR
    use fplotlib_glyphs_data, only: MIN_CONNECTOR_OVERLAP, FACE_EM, &
                               MC_SCRIPT_PERCENT_SCALE_DOWN, &
                               MC_SCRIPT_SCRIPT_PERCENT_SCALE_DOWN, MC_AXIS_HEIGHT, &
                               MC_DELIMITED_SUB_FORMULA_MIN_HEIGHT, &
                               MC_DISPLAY_OPERATOR_MIN_HEIGHT, MC_ACCENT_BASE_HEIGHT, &
                               MC_SUBSCRIPT_SHIFT_DOWN, MC_SUBSCRIPT_TOP_MAX, &
                               MC_SUBSCRIPT_BASELINE_DROP_MIN, MC_SUPERSCRIPT_SHIFT_UP, &
                               MC_SUPERSCRIPT_SHIFT_UP_CRAMPED, &
                               MC_SUPERSCRIPT_BOTTOM_MIN, &
                               MC_SUPERSCRIPT_BASELINE_DROP_MAX, &
                               MC_SUB_SUPERSCRIPT_GAP_MIN, &
                               MC_SUPERSCRIPT_BOTTOM_MAX_WITH_SUBSCRIPT, &
                               MC_SPACE_AFTER_SCRIPT, MC_UPPER_LIMIT_GAP_MIN, &
                               MC_UPPER_LIMIT_BASELINE_RISE_MIN, MC_LOWER_LIMIT_GAP_MIN, &
                               MC_LOWER_LIMIT_BASELINE_DROP_MIN, &
                               MC_STACK_TOP_SHIFT_UP, MC_STACK_TOP_DISPLAY_STYLE_SHIFT_UP, &
                               MC_STACK_BOTTOM_SHIFT_DOWN, &
                               MC_STACK_BOTTOM_DISPLAY_STYLE_SHIFT_DOWN, &
                               MC_STACK_GAP_MIN, MC_STACK_DISPLAY_STYLE_GAP_MIN, &
                               MC_FRACTION_NUMERATOR_SHIFT_UP, &
                               MC_FRACTION_NUMERATOR_DISPLAY_STYLE_SHIFT_UP, &
                               MC_FRACTION_DENOMINATOR_SHIFT_DOWN, &
                               MC_FRACTION_DENOMINATOR_DISPLAY_STYLE_SHIFT_DOWN, &
                               MC_FRACTION_NUMERATOR_GAP_MIN, &
                               MC_FRACTION_NUM_DISPLAY_STYLE_GAP_MIN, &
                               MC_FRACTION_RULE_THICKNESS, &
                               MC_FRACTION_DENOMINATOR_GAP_MIN, &
                               MC_FRACTION_DENOM_DISPLAY_STYLE_GAP_MIN, &
                               MC_OVERBAR_VERTICAL_GAP, MC_OVERBAR_RULE_THICKNESS, &
                               MC_OVERBAR_EXTRA_ASCENDER, MC_UNDERBAR_VERTICAL_GAP, &
                               MC_UNDERBAR_RULE_THICKNESS, MC_UNDERBAR_EXTRA_DESCENDER, &
                               MC_RADICAL_VERTICAL_GAP, &
                               MC_RADICAL_DISPLAY_STYLE_VERTICAL_GAP, &
                               MC_RADICAL_RULE_THICKNESS, MC_RADICAL_EXTRA_ASCENDER, &
                               MC_RADICAL_KERN_BEFORE_DEGREE, MC_RADICAL_KERN_AFTER_DEGREE, &
                               MC_RADICAL_DEGREE_BOTTOM_RAISE_PERCENT
    implicit none
    private

    public :: math_is, math_width, math_layout, mrules_t

    ! Rules, in the same frame as the glyphs of a run: (x, y) is the top
    ! left corner, y down, w and h the width and height.
    type :: mrules_t
        integer :: n = 0
        real(dp), allocatable :: x(:), y(:), w(:), h(:)
    end type mrules_t

    ! Styles, in TeX's order. A cramped style is the same style with its
    ! superscripts held lower; it travels as a separate flag.
    integer, parameter :: ST_D = 0, ST_T = 1, ST_S = 2, ST_SS = 3

    ! "No atom yet", which is not a class: a binary operator in that
    ! position is set as ordinary, the way a leading minus is.
    integer, parameter :: CL_NONE = 0

    ! What a noad is. An atom has a class; the rest are spaced as the
    ! class they are given (a fraction is inner, a radical ordinary, and
    ! so on), except for spaces and style changes, which are not atoms.
    integer, parameter :: K_ATOM = 1, K_FRAC = 2, K_RAD = 3, K_SPACE = 4, &
                          K_STYLE = 5, K_ACC = 6, K_OVER = 7, K_UNDER = 8, &
                          K_LR = 9, K_MID = 10, K_BIG = 11

    ! What a nucleus is.
    integer, parameter :: NUC_NONE = 0, NUC_CHAR = 1, NUC_LIST = 2, NUC_TEXT = 3

    ! Alphabets: what a letter typed in math becomes.
    integer, parameter :: ALPH_MATH = 0, ALPH_RM = 1, ALPH_IT = 2, ALPH_BF = 3, &
                          ALPH_BB = 4, ALPH_CAL = 5, ALPH_SF = 6

    ! TeX's math glue, in mu (an eighteenth of an em). \, and \; are the
    ! thin and thick spaces written by hand, \: the medium one.
    real(dp), parameter :: THIN = 3.0_dp, MED = 4.0_dp, THICK = 5.0_dp

    ! LaTeX's lengths, in ems of the formula: \nulldelimiterspace (1.2pt),
    ! \delimitershortfall (5pt), and the strut of a 12pt baseline, which
    ! \cfrac puts into its numerators. \delimiterfactor is 901.
    real(dp), parameter :: NULL_DELIM = 0.12_dp, SHORTFALL = 0.5_dp
    real(dp), parameter :: STRUT_H = 0.84_dp, STRUT_D = 0.36_dp
    real(dp), parameter :: DELIM_FACTOR = 901.0_dp/500.0_dp
    ! How much less than its contents an automatic delimiter may cover, in
    ! ems: Typst's DELIM_SHORT_FALL.
    real(dp), parameter :: AUTO_SHORTFALL = 0.1_dp
    integer, parameter :: ROLE_OPEN = 1, ROLE_CLOSE = 2, ROLE_EITHER = 3

    ! Spelled this way because a backslash inside a string literal is not
    ! portable: some compilers read it as the start of an escape.
    character, parameter :: BS = achar(92)

    type :: noad_t
        integer :: kind = K_ATOM
        integer :: cls = CL_ORD
        integer :: next = 0
        integer :: nuc = NUC_NONE
        ! NUC_CHAR: the code point and the face it is set in.
        integer :: cp = 0
        integer :: face = 0
        ! NUC_LIST: the head of the list, 0 for an empty one.
        integer :: list = 0
        ! NUC_TEXT: the text, TPOOL(t0:t1), set in face.
        integer :: t0 = 1, t1 = 0
        ! The scripts' lists, -1 for none. A superscript started by primes
        ! takes a following ^ as more of itself, as x'^2 is x^{\prime 2}.
        integer :: sup = -1, sub = -1
        logical :: primed = .false.
        ! K_FRAC: numerator and denominator; K_RAD: the radicand and the
        ! degree (-1 for none); K_ACC, K_OVER, K_UNDER, K_LR: the list.
        integer :: a = 0, b = -1
        ! K_SPACE: the width, in mu when mu is true and ems otherwise.
        real(dp) :: amount = 0.0_dp
        logical :: mu = .true.
        ! An operator: 0 for TeX's default (limits in display style), 1 for
        ! \limits, 2 for \nolimits.
        integer :: limits = 0
        ! K_STYLE: the style it changes to. K_FRAC: the style it is set in
        ! whatever the list says (\dfrac, \tfrac, \cfrac), -1 for none.
        integer :: style = -1
        ! K_FRAC: whether it has a rule, and its delimiters, 0 for none.
        logical :: rule = .true.
        integer :: dl = 0, dr = 0
        ! K_FRAC: a strut in the numerator, as \cfrac has.
        logical :: strut = .false.
        ! K_ACC: whether the accent grows to the width of what it is over.
        logical :: wide = .false.
        ! K_BIG: 1 to 4 for \big, \Big, \bigg, \Bigg.
        integer :: level = 0
        ! Automatic delimiters. An atom that is a delimiter may pair up
        ! with another unless it is fixed (written \( or in braces), and a
        ! | left between a pair is its middle (amid). A K_LR made from a
        ! pair has auto 1 until settle_auto decides it, 2 once it has
        ! grown; lo and lc are its opening and closing atoms.
        logical :: fixed = .false., amid = .false.
        integer :: auto = 0, lo = 0, lc = 0
    end type noad_t

    ! A box: items i0..i1 of the arena, and its dimensions in points. A box
    ! made of a single character remembers which glyph it is, at what
    ! size, and its italic correction, which a superscript is moved out by;
    ! a box whose list is a single character remembers the glyph too, for
    ! the math kern of a script made of it.
    type :: mbox_t
        integer :: i0 = 1, i1 = 0
        real(dp) :: w = 0.0_dp, h = 0.0_dp, d = 0.0_dp
        real(dp) :: ital = 0.0_dp
        logical :: is_char = .false.
        integer :: gid = 0
        real(dp) :: sz = 0.0_dp
        ! The glyph the math kerns are read from: the character's own,
        ! before any script-size alternate took its place.
        integer :: kgid = 0
    end type mbox_t

    ! The noads of the fragment being laid out, and the text of the
    ! operator names and \text among them.
    type(noad_t), allocatable :: NOADS(:)
    integer :: NN = 0
    character(len=:), allocatable :: TPOOL

    ! The items, glyphs (kind 1) and rules (kind 2). A glyph's (x, y) is
    ! its origin; a rule's is its bottom left corner.
    integer, allocatable :: IT_KIND(:), IT_GID(:)
    real(dp), allocatable :: IT_X(:), IT_Y(:), IT_S(:), IT_W(:), IT_H(:)
    integer :: NI = 0

    ! The size the \middle delimiters of the \left...\right group being
    ! laid out are to have, negative while the group is being measured,
    ! and the size an assembly for them is built to.
    real(dp) :: LR_TARGET = -1.0_dp, LR_FULL = -1.0_dp

contains

    ! Is there anything in this string for the mathtext engine to do?
    pure function math_is(s) result(yes)
        character(len=*), intent(in) :: s
        logical :: yes
        yes = index(s, "$") > 0
    end function math_is

    ! Width of a string in points, mathtext or not, with its text in face.
    function math_width(s, size, face) result(w)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size
        integer, intent(in), optional :: face
        real(dp) :: w
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        call math_layout(s, size, run, rules, w, face)
    end function math_width

    ! Lay a string out: its glyphs are appended to run and its rules to
    ! rules, starting at the origin, and width is how far it reaches.
    ! Text outside the dollar signs is copied through as ordinary text, in
    ! face (the regular one by default), with \$ written as a dollar sign.
    subroutine math_layout(s, size, run, rules, width, face)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size
        type(glyphrun_t), intent(inout) :: run
        type(mrules_t), intent(inout) :: rules
        real(dp), intent(out) :: width
        integer, intent(in), optional :: face
        type(mbox_t) :: box
        integer :: i, j, head, k, tf
        real(dp) :: pen, xnew

        tf = FACE_REGULAR
        if (present(face)) tf = face
        pen = 0.0_dp
        i = 1
        do while (i <= len(s))
            if (s(i:i) == "$") then
                j = dollar(s, i + 1)
                if (j > i + 1) then
                    call reset_arenas()
                    head = parse_list(s(i + 1:j - 1), ALPH_MATH)
                    call mlist_box(head, ST_T, .false., size, box)
                    do k = box%i0, box%i1
                        if (IT_KIND(k) == 1) then
                            call run_add(run, IT_GID(k), pen + IT_X(k), -IT_Y(k), IT_S(k))
                        else
                            call rule_add(rules, pen + IT_X(k), -(IT_Y(k) + IT_H(k)), &
                                          IT_W(k), IT_H(k))
                        end if
                    end do
                    pen = pen + box%w
                end if
                i = j + 1
            else
                j = i
                do while (j <= len(s))
                    if (s(j:j) == "$") exit
                    if (s(j:j) == BS .and. j < len(s)) then
                        if (s(j + 1:j + 1) == "$") exit
                    end if
                    j = j + 1
                end do
                if (j > i) then
                    call text_layout(s(i:j - 1), size, tf, pen, 0.0_dp, run, xnew)
                    pen = xnew
                end if
                ! A dollar written \$ is one.
                if (j < len(s)) then
                    if (s(j:j) == BS) then
                        call text_layout("$", size, tf, pen, 0.0_dp, run, xnew)
                        pen = xnew
                        j = j + 2
                    end if
                end if
                i = j
            end if
        end do
        width = pen
    end subroutine math_layout

    ! The dollar sign that closes a formula opened before i, skipping
    ! the ones written \$; len(s) + 1 when there is none.
    pure integer function dollar(s, i) result(j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        j = i
        do while (j <= len(s))
            if (s(j:j) == BS) then
                j = j + 2
                cycle
            end if
            if (s(j:j) == "$") return
            j = j + 1
        end do
        j = len(s) + 1
    end function dollar

    subroutine rule_add(rules, x, y, w, h)
        type(mrules_t), intent(inout) :: rules
        real(dp), intent(in) :: x, y, w, h
        real(dp), allocatable :: t(:)
        integer :: cap
        if (.not. allocated(rules%x)) then
            allocate (rules%x(4), rules%y(4), rules%w(4), rules%h(4))
        else if (rules%n >= size(rules%x)) then
            cap = 2*size(rules%x)
            allocate (t(cap))
            t(1:rules%n) = rules%x(1:rules%n)
            call move_alloc(t, rules%x)
            allocate (t(cap))
            t(1:rules%n) = rules%y(1:rules%n)
            call move_alloc(t, rules%y)
            allocate (t(cap))
            t(1:rules%n) = rules%w(1:rules%n)
            call move_alloc(t, rules%w)
            allocate (t(cap))
            t(1:rules%n) = rules%h(1:rules%n)
            call move_alloc(t, rules%h)
        end if
        rules%n = rules%n + 1
        rules%x(rules%n) = x
        rules%y(rules%n) = y
        rules%w(rules%n) = w
        rules%h(rules%n) = h
    end subroutine rule_add
    ! ------------------------------------------------------------------
    ! Parsing: a fragment into a list of noads
    ! ------------------------------------------------------------------

    subroutine reset_arenas()
        if (.not. allocated(NOADS)) allocate (NOADS(64))
        NN = 0
        TPOOL = ""
        if (.not. allocated(IT_KIND)) then
            allocate (IT_KIND(64), IT_GID(64), IT_X(64), IT_Y(64), IT_S(64), &
                      IT_W(64), IT_H(64))
        end if
        NI = 0
        LR_TARGET = -1.0_dp
    end subroutine reset_arenas

    integer function new_noad(kind, cls) result(k)
        integer, intent(in) :: kind, cls
        type(noad_t), allocatable :: t(:)
        if (NN >= size(NOADS)) then
            allocate (t(2*size(NOADS)))
            t(1:NN) = NOADS(1:NN)
            call move_alloc(t, NOADS)
        end if
        NN = NN + 1
        k = NN
        NOADS(k) = noad_t()
        NOADS(k)%kind = kind
        NOADS(k)%cls = cls
    end function new_noad

    ! A character as an atom of the class it has, set in the math font.
    integer function char_noad(code, alph, cls) result(k)
        integer, intent(in) :: code, alph
        integer, intent(in), optional :: cls
        integer :: c
        c = code
        ! A hyphen in math is a minus sign, as in TeX.
        if (c == iachar("-")) c = 8722
        if (present(cls)) then
            k = new_noad(K_ATOM, cls)
        else
            k = new_noad(K_ATOM, sym_class(c))
        end if
        NOADS(k)%nuc = NUC_CHAR
        NOADS(k)%cp = math_alphabet(c, alph)
        NOADS(k)%face = FACE_MATH
        ! The integrals take their scripts beside them, as TeX's \int is
        ! \intop\nolimits.
        if (c >= 8747 .and. c <= 8755) NOADS(k)%limits = 2
    end function char_noad

    ! An atom whose nucleus is a list. A list that is a single ordinary
    ! atom without scripts is that atom, as TeX simplifies a group, so
    ! that {x}^2 is set exactly as x^2.
    integer function list_noad(head, cls) result(k)
        integer, intent(in) :: head, cls
        if (head > 0 .and. cls == CL_ORD) then
            if (plain_ord(head)) then
                k = head
                ! A delimiter in braces is a character, not a fence.
                NOADS(k)%fixed = .true.
                return
            end if
        end if
        k = new_noad(K_ATOM, cls)
        NOADS(k)%nuc = NUC_LIST
        NOADS(k)%list = head
    end function list_noad

    logical function plain_ord(head)
        integer, intent(in) :: head
        plain_ord = NOADS(head)%next == 0 .and. NOADS(head)%kind == K_ATOM &
                    .and. NOADS(head)%cls == CL_ORD .and. NOADS(head)%sup < 0 &
                    .and. NOADS(head)%sub < 0
    end function plain_ord

    ! An atom whose nucleus is text: an operator name in the math font's
    ! upright letters, or \text in the text font.
    integer function text_noad(text, cls, face) result(k)
        character(len=*), intent(in) :: text
        integer, intent(in) :: cls, face
        k = new_noad(K_ATOM, cls)
        NOADS(k)%nuc = NUC_TEXT
        NOADS(k)%face = face
        NOADS(k)%t0 = len(TPOOL) + 1
        TPOOL = TPOOL//text
        NOADS(k)%t1 = len(TPOOL)
    end function text_noad

    ! The list s describes. Spaces are dropped, as TeX drops them: the
    ! glue between atoms comes from their classes. \over, \atop and
    ! \choose make the list a fraction of what comes before them and what
    ! comes after.
    recursive function parse_list(s, alph) result(head)
        character(len=*), intent(in) :: s
        integer, intent(in) :: alph
        integer :: head, tail, cur, i, j, k, code, nb, sl, n, code2
        integer :: num, infix, cls, lv
        character(len=24) :: name
        character :: last

        head = 0
        tail = 0
        cur = 0
        num = -1
        infix = 0
        i = 1
        do while (i <= len(s))
            select case (s(i:i))
            case (" ", achar(9), achar(10))
                i = i + 1
            case ("^", "_")
                ! A script with nothing before it hangs off an empty atom.
                if (cur == 0) then
                    cur = new_noad(K_ATOM, CL_ORD)
                    call append(head, tail, cur)
                end if
                call unit_end(s, i + 1, j)
                sl = parse_arg(s(i + 1:j), alph)
                if (s(i:i) == "^") then
                    if (NOADS(cur)%primed) then
                        call append_list(NOADS(cur)%sup, sl)
                        NOADS(cur)%primed = .false.
                    else
                        if (NOADS(cur)%sup >= 0) then
                            cur = new_noad(K_ATOM, CL_ORD)
                            call append(head, tail, cur)
                        end if
                        NOADS(cur)%sup = sl
                    end if
                else
                    if (NOADS(cur)%sub >= 0) then
                        cur = new_noad(K_ATOM, CL_ORD)
                        call append(head, tail, cur)
                    end if
                    NOADS(cur)%sub = sl
                end if
                i = j + 1
            case ("'")
                ! Primes are a superscript: one, two, three or four of them
                ! as the single character Unicode has for each.
                n = 0
                do while (i + n <= len(s))
                    if (s(i + n:i + n) /= "'") exit
                    n = n + 1
                end do
                if (cur == 0) then
                    cur = new_noad(K_ATOM, CL_ORD)
                    call append(head, tail, cur)
                end if
                select case (min(n, 4))
                case (1); code = 8242
                case (2); code = 8243
                case (3); code = 8244
                case default; code = 8279
                end select
                k = char_noad(code, ALPH_RM, CL_ORD)
                if (NOADS(cur)%sup >= 0 .and. .not. NOADS(cur)%primed) then
                    cur = new_noad(K_ATOM, CL_ORD)
                    call append(head, tail, cur)
                end if
                call append_list(NOADS(cur)%sup, k)
                NOADS(cur)%primed = .true.
                i = i + n
            case ("{")
                call group_end(s, i, j)
                k = list_noad(parse_list(s(i + 1:j - 1), alph), CL_ORD)
                call append(head, tail, k)
                cur = k
                i = j + 1
            case ("}")
                i = i + 1
            case (BS)
                name = cmd_name(s(i:))
                select case (name)
                case ("over", "atop", "choose")
                    num = head
                    head = 0
                    tail = 0
                    cur = 0
                    if (name == "over") infix = 1
                    if (name == "atop") infix = 2
                    if (name == "choose") infix = 3
                    i = i + len_trim(name) + 1
                case ("left")
                    call parse_left(s, i, alph, k, j)
                    call append(head, tail, k)
                    cur = k
                    i = j + 1
                case ("middle")
                    call read_delim(s, i + 7, code, j)
                    k = new_noad(K_MID, CL_ORD)
                    NOADS(k)%cp = code
                    call append(head, tail, k)
                    cur = 0
                    i = j + 1
                case ("right")
                    ! A \right without its \left: the delimiter alone.
                    call read_delim(s, i + 6, code, j)
                    if (code > 0) then
                        k = char_noad(code, ALPH_RM, CL_CLOSE)
                        call append(head, tail, k)
                        cur = k
                    end if
                    i = j + 1
                case ("big", "Big", "bigg", "Bigg", "bigl", "Bigl", "biggl", "Biggl", &
                      "bigr", "Bigr", "biggr", "Biggr", "bigm", "Bigm", "biggm", "Biggm")
                    call read_delim(s, i + len_trim(name) + 1, code, j)
                    lv = 1
                    if (name(1:4) == "Bigg") then
                        lv = 4
                    else if (name(1:4) == "bigg") then
                        lv = 3
                    else if (name(1:3) == "Big") then
                        lv = 2
                    end if
                    cls = CL_ORD
                    last = name(len_trim(name):len_trim(name))
                    if (last == "l") cls = CL_OPEN
                    if (last == "r") cls = CL_CLOSE
                    if (last == "m") cls = CL_REL
                    k = new_noad(K_BIG, cls)
                    NOADS(k)%cp = code
                    NOADS(k)%level = lv
                    call append(head, tail, k)
                    cur = k
                    i = j + 1
                case ("limits", "nolimits", "displaylimits")
                    if (cur > 0) then
                        if (NOADS(cur)%cls == CL_OP) then
                            NOADS(cur)%limits = 0
                            if (name == "limits") NOADS(cur)%limits = 1
                            if (name == "nolimits") NOADS(cur)%limits = 2
                        end if
                    end if
                    i = i + len_trim(name) + 1
                case default
                    call command_end(s, i, j)
                    k = parse_command(s(i:j), alph)
                    if (k > 0) then
                        call append(head, tail, k)
                        cur = k
                        if (NOADS(k)%kind == K_SPACE .or. NOADS(k)%kind == K_STYLE) cur = 0
                        ! \cfrac takes back one null delimiter's space.
                        if (NOADS(k)%kind == K_ATOM .and. NOADS(k)%nuc == NUC_LIST) then
                            if (NOADS(k)%list > 0) then
                                if (NOADS(NOADS(k)%list)%strut) then
                                    code2 = space_noad(-NULL_DELIM, .false.)
                                    call append(head, tail, code2)
                                end if
                            end if
                        end if
                    end if
                    i = j + 1
                end select
            case default
                call utf8_next(s, i, code, nb)
                if (code == 8731 .or. code == 8732) then
                    ! The cube and fourth roots are \sqrt[3] and \sqrt[4] of
                    ! what follows them.
                    n = i + nb
                    do while (n <= len(s))
                        if (s(n:n) /= " ") exit
                        n = n + 1
                    end do
                    call unit_end(s, n, j)
                    k = new_noad(K_RAD, CL_ORD)
                    NOADS(k)%b = char_noad(merge(iachar("3"), iachar("4"), code == 8731), &
                                           ALPH_MATH)
                    NOADS(k)%a = parse_arg(s(n:j), alph)
                    call append(head, tail, k)
                    cur = k
                    i = j + 1
                    cycle
                end if
                k = char_noad(code, alph)
                call append(head, tail, k)
                cur = k
                i = i + nb
            end select
        end do

        head = auto_pair(head)
        if (infix > 0) then
            k = new_noad(K_FRAC, CL_INNER)
            NOADS(k)%a = auto_pair(num)
            NOADS(k)%b = head
            NOADS(k)%rule = infix == 1
            if (infix == 3) then
                NOADS(k)%dl = iachar("(")
                NOADS(k)%dr = iachar(")")
            end if
            head = k
        end if
    end function parse_list

    subroutine append(head, tail, k)
        integer, intent(inout) :: head, tail
        integer, intent(in) :: k
        if (head == 0) then
            head = k
        else
            NOADS(tail)%next = k
        end if
        tail = k
    end subroutine append

    ! Append list b to list a, -1 meaning no list at all.
    subroutine append_list(a, b)
        integer, intent(inout) :: a
        integer, intent(in) :: b
        integer :: q
        if (a <= 0) then
            a = max(b, 0)
            return
        end if
        q = a
        do while (NOADS(q)%next > 0)
            q = NOADS(q)%next
        end do
        if (b > 0) NOADS(q)%next = b
    end subroutine append_list

    ! Automatic delimiters, as Typst has them. In one list, an opening
    ! delimiter written as a character or a symbol (( [ \{ \langle \lfloor
    ! \lceil) pairs up with the next closing one of the same kind, nested
    ! as brackets nest, and two | or two ‖ pair up as well; a | or ‖ left
    ! alone between a pair is that pair's middle. A delimiter with nothing
    ! to pair with, as in [0, 1), stays as it is. Each pair becomes an
    ! automatic \left...\right, which settle_auto turns back into the
    ! plain delimiters unless what they enclose is taller than they are.
    recursive function auto_pair(head) result(new)
        integer, intent(in) :: head
        integer :: new
        integer, allocatable :: arr(:), pend(:), stk(:), skind(:), srole(:)
        integer :: n, q, k, j, top, kind, role
        logical :: found

        new = head
        n = 0
        q = head
        do while (q > 0)
            n = n + 1
            q = NOADS(q)%next
        end do
        if (n < 2) return
        allocate (arr(n), pend(n), stk(n), skind(n), srole(n))
        pend = 0
        q = head
        do k = 1, n
            arr(k) = q
            q = NOADS(q)%next
        end do
        top = 0
        do k = 1, n
            call fence_role(arr(k), kind, role)
            if (kind == 0) cycle
            found = .false.
            if (role /= ROLE_OPEN) then
                ! The nearest opening of the same kind, past lone fences.
                j = top
                do while (j > 0)
                    if (skind(j) == kind) then
                        found = .true.
                        exit
                    end if
                    if (srole(j) /= ROLE_EITHER) exit
                    j = j - 1
                end do
            end if
            if (found) then
                pend(stk(j)) = k
                do q = j + 1, top
                    NOADS(arr(stk(q)))%amid = .true.
                end do
                top = j - 1
            else if (role /= ROLE_CLOSE .and. NOADS(arr(k))%sup < 0 &
                     .and. NOADS(arr(k))%sub < 0) then
                top = top + 1
                stk(top) = k
                skind(top) = kind
                srole(top) = role
            end if
        end do
        if (all(pend == 0)) return
        new = pair_build(arr, pend, 1, n)
    end function auto_pair

    ! The list of arr(lo:hi), each pair in it (from the opening at k to
    ! the closing at pend(k)) made one automatic \left...\right.
    recursive function pair_build(arr, pend, lo, hi) result(head)
        integer, intent(in) :: arr(:), pend(:), lo, hi
        integer :: head, tail, p, k
        head = 0
        tail = 0
        p = lo
        do while (p <= hi)
            if (pend(p) > 0) then
                k = new_noad(K_LR, CL_INNER)
                NOADS(k)%auto = 1
                NOADS(k)%lo = arr(p)
                NOADS(k)%lc = arr(pend(p))
                NOADS(k)%dl = NOADS(arr(p))%cp
                NOADS(k)%dr = NOADS(arr(pend(p)))%cp
                NOADS(k)%a = pair_build(arr, pend, p + 1, pend(p) - 1)
                p = pend(p) + 1
            else
                k = arr(p)
                p = p + 1
            end if
            call append(head, tail, k)
        end do
        if (tail > 0) NOADS(tail)%next = 0
    end function pair_build

    ! Which kind of delimiter atom q is (0 when it cannot pair up), and
    ! whether it opens, closes or, for | and ‖, may do either.
    subroutine fence_role(q, kind, role)
        integer, intent(in) :: q
        integer, intent(out) :: kind, role
        kind = 0
        role = 0
        if (NOADS(q)%kind /= K_ATOM .or. NOADS(q)%nuc /= NUC_CHAR) return
        if (NOADS(q)%fixed) return
        select case (NOADS(q)%cp)
        case (40, 41); kind = 1
        case (91, 93); kind = 2
        case (123, 125); kind = 3
        case (10216, 10217); kind = 4
        case (8970, 8971); kind = 5
        case (8968, 8969); kind = 6
        case (124); kind = 7
        case (8214); kind = 8
        case default; return
        end select
        if (NOADS(q)%cls == CL_OPEN) then
            role = ROLE_OPEN
        else if (NOADS(q)%cls == CL_CLOSE) then
            role = ROLE_CLOSE
        else if (NOADS(q)%cls == CL_ORD .and. kind >= 7) then
            role = ROLE_EITHER
        else
            kind = 0
        end if
    end subroutine fence_role

    ! The argument of a script or a command: a braced group is its
    ! contents, anything else is itself.
    recursive function parse_arg(s, alph) result(head)
        character(len=*), intent(in) :: s
        integer, intent(in) :: alph
        integer :: head, j
        if (len(s) == 0) then
            head = 0
        else if (s(1:1) == "{") then
            call group_end(s, 1, j)
            head = parse_list(s(2:j - 1), alph)
        else
            head = parse_list(s, alph)
        end if
    end function parse_arg

    ! \left d1 ... \right d2, with s(i:i) the backslash of \left: the
    ! group as one inner atom, j the last character of d2. Without a
    ! matching \right, the left delimiter is an ordinary opening.
    recursive subroutine parse_left(s, i, alph, k, j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i, alph
        integer, intent(out) :: k, j
        integer :: code, p, q, depth, code2, jr
        character(len=24) :: name

        call read_delim(s, i + 5, code, p)
        q = p + 1
        depth = 0
        jr = 0
        do while (q <= len(s))
            if (s(q:q) == "{") then
                call group_end(s, q, jr)
                q = jr + 1
                cycle
            end if
            if (s(q:q) == BS) then
                name = cmd_name(s(q:))
                if (name == "left") depth = depth + 1
                if (name == "right") then
                    if (depth == 0) exit
                    depth = depth - 1
                end if
                q = q + max(len_trim(name), 1) + 1
                cycle
            end if
            q = q + 1
        end do
        if (q > len(s)) then
            k = char_noad(max(code, iachar(".")), ALPH_RM, CL_OPEN)
            j = p
            return
        end if
        call read_delim(s, q + 6, code2, j)
        k = new_noad(K_LR, CL_INNER)
        NOADS(k)%a = parse_list(s(p + 1:q - 1), alph)
        NOADS(k)%dl = code
        NOADS(k)%dr = code2
    end subroutine parse_left

    ! The delimiter that follows a \left, \right, \middle or \big, with
    ! the scan starting at i: its code point, 0 for the null delimiter
    ! ".", and j the last character it takes.
    subroutine read_delim(s, i, code, j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        integer, intent(out) :: code, j
        integer :: k, nb
        character(len=24) :: name

        code = 0
        k = i
        do while (k <= len(s))
            if (s(k:k) /= " ") exit
            k = k + 1
        end do
        j = k
        if (k > len(s)) then
            j = len(s)
            return
        end if
        select case (s(k:k))
        case (".")
            code = 0
        case ("<")
            code = 10216
        case (">")
            code = 10217
        case (BS)
            if (k == len(s)) return
            select case (s(k + 1:k + 1))
            case ("{"); code = iachar("{")
            case ("}"); code = iachar("}")
            case ("|"); code = 8214
            case default
                name = cmd_name(s(k:))
                code = delim_code(trim(name))
                j = k + len_trim(name)
                return
            end select
            j = k + 1
        case default
            call utf8_next(s, k, code, nb)
            j = k + nb - 1
        end select
    end subroutine read_delim

    ! The character a delimiter named by a command stands for, 0 for none.
    function delim_code(name) result(code)
        character(len=*), intent(in) :: name
        integer :: code, cls
        select case (name)
        case ("vert", "lvert", "rvert", "mid"); code = iachar("|")
        case ("Vert", "lVert", "rVert", "parallel"); code = 8214
        case ("backslash"); code = 92
        case ("lbrace"); code = iachar("{")
        case ("rbrace"); code = iachar("}")
        case ("lbrack"); code = iachar("[")
        case ("rbrack"); code = iachar("]")
        case default
            call math_sym(name, code, cls)
        end select
    end function delim_code

    ! A symbol by name, as fplotlib_mathsym knows it, provided the math
    ! font has its glyph; code is 0 otherwise, and the name is spelled out
    ! like any other unknown command.
    subroutine math_sym(name, code, cls)
        character(len=*), intent(in) :: name
        integer, intent(out) :: code, cls
        call sym_lookup(name, code, cls)
        if (code > 0) then
            if (glyph_cmap(FACE_MATH, math_alphabet(code, ALPH_MATH)) == 0) code = 0
        end if
    end subroutine math_sym

    ! One command, as a noad; 0 when it makes nothing.
    recursive function parse_command(s, alph) result(k)
        character(len=*), intent(in) :: s
        integer, intent(in) :: alph
        integer :: k, j, code, cls, a0, a1, b0, b1, o0, o1, ac
        character(len=24) :: name
        logical :: wide

        k = 0
        if (len(s) < 2) return
        ! An explicit skip is not an atom: the next symbol is still spaced
        ! against whatever came before the skip.
        select case (s(2:2))
        case (",")
            k = space_noad(THIN, .true.)
            return
        case (":", ">")
            k = space_noad(MED, .true.)
            return
        case (";")
            k = space_noad(THICK, .true.)
            return
        case ("!")
            k = space_noad(-THIN, .true.)
            return
        case (" ")
            ! The interword space of the text font.
            k = space_noad(glyph_adv(glyph_cmap(FACE_REGULAR, 32)), .false.)
            return
        case ("{")
            k = char_noad(iachar("{"), ALPH_RM, CL_OPEN)
            return
        case ("}")
            k = char_noad(iachar("}"), ALPH_RM, CL_CLOSE)
            return
        case ("|")
            k = char_noad(8214, ALPH_RM, CL_ORD)
            return
        case ("(", "[")
            ! An escaped parenthesis or bracket is the character itself,
            ! which never pairs up and never grows.
            k = char_noad(iachar(s(2:2)), ALPH_RM, CL_OPEN)
            NOADS(k)%fixed = .true.
            return
        case (")", "]")
            k = char_noad(iachar(s(2:2)), ALPH_RM, CL_CLOSE)
            NOADS(k)%fixed = .true.
            return
        case ("$", "%", "&", "#", "_")
            k = char_noad(iachar(s(2:2)), ALPH_RM, CL_ORD)
            return
        case (BS)
            return
        end select

        name = cmd_name(s)
        call cmd_arg(s, 1, a0, a1)
        call cmd_arg(s, 2, b0, b1)
        select case (name)
        case ("quad")
            k = space_noad(1.0_dp, .false.)
        case ("qquad")
            k = space_noad(2.0_dp, .false.)
        case ("displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle")
            k = new_noad(K_STYLE, CL_NONE)
            select case (name)
            case ("displaystyle"); NOADS(k)%style = ST_D
            case ("textstyle"); NOADS(k)%style = ST_T
            case ("scriptstyle"); NOADS(k)%style = ST_S
            case default; NOADS(k)%style = ST_SS
            end select
        case ("frac", "dfrac", "tfrac")
            k = new_noad(K_FRAC, CL_INNER)
            NOADS(k)%a = parse_list(s(a0:a1), alph)
            NOADS(k)%b = parse_list(s(b0:b1), alph)
            if (name(1:1) == "d") NOADS(k)%style = ST_D
            if (name(1:1) == "t") NOADS(k)%style = ST_T
            ! LaTeX's \frac is {a\over b}, and amsmath's \genfrac sets the
            ! others in a group too: an ordinary atom, as spaced.
            k = list_noad(k, CL_ORD)
        case ("binom", "dbinom", "tbinom")
            ! A stack between parentheses, as \atopwithdelims sets it (rule
            ! 15e), in a group. (amsmath's \genfrac sizes the parentheses
            ! by \fontdimen 20 and 21, which under XeTeX are unrelated
            ! MATH constants.)
            k = new_noad(K_FRAC, CL_INNER)
            NOADS(k)%a = parse_list(s(a0:a1), alph)
            NOADS(k)%b = parse_list(s(b0:b1), alph)
            NOADS(k)%rule = .false.
            NOADS(k)%dl = iachar("(")
            NOADS(k)%dr = iachar(")")
            if (name(1:1) == "d") NOADS(k)%style = ST_D
            if (name(1:1) == "t") NOADS(k)%style = ST_T
            k = list_noad(k, CL_ORD)
        case ("cfrac")
            ! amsmath: {\displaystyle\frac{\strut a}{b}}, and then the
            ! null delimiter's space taken back (by parse_list).
            k = new_noad(K_FRAC, CL_INNER)
            NOADS(k)%a = parse_list(s(a0:a1), alph)
            NOADS(k)%b = parse_list(s(b0:b1), alph)
            NOADS(k)%style = ST_D
            NOADS(k)%strut = .true.
            k = list_noad(k, CL_ORD)
        case ("sqrt")
            k = new_noad(K_RAD, CL_ORD)
            call opt_arg(s, o0, o1)
            if (o1 >= o0) NOADS(k)%b = parse_list(s(o0:o1), alph)
            call cmd_arg(s, 1, a0, a1)
            NOADS(k)%a = parse_list(s(a0:a1), alph)
        case ("overline", "underline")
            k = new_noad(merge(K_OVER, K_UNDER, name == "overline"), CL_ORD)
            NOADS(k)%a = parse_list(s(a0:a1), alph)
        case ("mathrm", "mathup", "mathnormal", "mathit", "mathbf", "mathbb", &
              "mathcal", "mathscr", "mathsf")
            k = list_noad(parse_list(s(a0:a1), alphabet_of(name)), CL_ORD)
        case ("text", "textrm", "mbox", "textnormal")
            k = text_noad(s(a0:a1), CL_ORD, FACE_REGULAR)
        case ("operatorname")
            k = text_noad(s(a0:a1), CL_OP, FACE_REGULAR)
            if (index(s, "*") /= len(trim(name)) + 2) NOADS(k)%limits = 2
        case default
            call accent_code(name, ac, wide)
            if (ac > 0) then
                k = new_noad(K_ACC, CL_ORD)
                NOADS(k)%cp = ac
                NOADS(k)%wide = wide
                NOADS(k)%a = parse_list(s(a0:a1), alph)
                return
            end if
            call math_sym(trim(name), code, cls)
            if (code > 0) then
                k = char_noad(code, alph, cls)
                return
            end if
            ! The operator names, and anything else without a group: an
            ! operator spelled out, as \sin is.
            j = index(s, "{")
            if (j > 0) then
                ! Any other command with a group sets the group.
                k = list_noad(parse_list(s(a0:a1), alph), CL_ORD)
            else
                select case (name)
                case ("liminf"); k = text_noad("lim inf", CL_OP, FACE_REGULAR)
                case ("limsup"); k = text_noad("lim sup", CL_OP, FACE_REGULAR)
                case default; k = text_noad(trim(name), CL_OP, FACE_REGULAR)
                end select
                ! Only these take their limits above and below in display
                ! style, as in TeX; the rest keep them beside.
                select case (name)
                case ("lim", "liminf", "limsup", "max", "min", "sup", "inf", "det", &
                      "gcd", "Pr")
                    NOADS(k)%limits = 0
                case default
                    NOADS(k)%limits = 2
                end select
            end if
        end select
    end function parse_command

    integer function space_noad(amount, mu) result(k)
        real(dp), intent(in) :: amount
        logical, intent(in) :: mu
        k = new_noad(K_SPACE, CL_NONE)
        NOADS(k)%amount = amount
        NOADS(k)%mu = mu
    end function space_noad

    ! The accent a command puts over its argument, and whether it grows
    ! to the argument's width; 0 for a command that is not an accent.
    pure subroutine accent_code(name, code, wide)
        character(len=*), intent(in) :: name
        integer, intent(out) :: code
        logical, intent(out) :: wide
        wide = .false.
        select case (name)
        case ("hat"); code = 770
        case ("widehat"); code = 770; wide = .true.
        case ("check"); code = 780
        case ("widecheck"); code = 780; wide = .true.
        case ("tilde"); code = 771
        case ("widetilde"); code = 771; wide = .true.
        case ("acute"); code = 769
        case ("grave"); code = 768
        case ("dot"); code = 775
        case ("ddot"); code = 776
        case ("breve"); code = 774
        case ("widebreve"); code = 774; wide = .true.
        case ("bar"); code = 772
        case ("mathring"); code = 778
        case ("vec"); code = 8407
        case ("overrightarrow"); code = 8407; wide = .true.
        case ("overleftarrow"); code = 8406; wide = .true.
        case default; code = 0
        end select
    end subroutine accent_code

    pure integer function alphabet_of(name) result(alph)
        character(len=*), intent(in) :: name
        select case (name)
        case ("mathit", "mathnormal"); alph = ALPH_IT
        case ("mathbf"); alph = ALPH_BF
        case ("mathbb"); alph = ALPH_BB
        case ("mathcal", "mathscr"); alph = ALPH_CAL
        case ("mathsf"); alph = ALPH_SF
        case default; alph = ALPH_RM
        end select
    end function alphabet_of

    ! ------------------------------------------------------------------
    ! Characters
    ! ------------------------------------------------------------------

    ! The character a typed one is set as in an alphabet. In plain math,
    ! Latin letters and lowercase Greek are the math italic ones and
    ! everything else stands upright, which is TeX's convention; \mathrm
    ! keeps them all upright, \mathit slopes all the letters, and the
    ! others take the math font's alphabets, falling back on the upright
    ! letter where an alphabet has no such character.
    integer function math_alphabet(code, alph) result(c)
        integer, intent(in) :: code, alph
        logical :: upper, lower, digit, gu, gl

        c = code
        upper = code >= iachar("A") .and. code <= iachar("Z")
        lower = code >= iachar("a") .and. code <= iachar("z")
        digit = code >= iachar("0") .and. code <= iachar("9")
        gu = code >= 913 .and. code <= 937
        gl = code >= 945 .and. code <= 969
        select case (alph)
        case (ALPH_MATH, ALPH_IT)
            if (upper) then
                c = 119860 + code - iachar("A")
            else if (code == iachar("h")) then
                ! Planck's constant stands in for the italic h, which is
                ! missing from the math italic block.
                c = 8462
            else if (lower) then
                c = 119886 + code - iachar("a")
            else if (gl) then
                c = 120572 + code - 945
            else if (gu .and. alph == ALPH_IT) then
                c = 120546 + code - 913
            else
                select case (code)
                case (1013); c = 120598     ! lunate epsilon
                case (977); c = 120599      ! theta symbol
                case (1008); c = 120600     ! kappa symbol
                case (981); c = 120601      ! phi symbol
                case (1009); c = 120602     ! rho symbol
                case (982); c = 120603      ! pi symbol
                case (8706); c = 120597     ! partial, italic as in unicode-math
                end select
            end if
        case (ALPH_BF)
            if (upper) c = 119808 + code - iachar("A")
            if (lower) c = 119834 + code - iachar("a")
            if (digit) c = 120782 + code - iachar("0")
            if (gu) c = 120488 + code - 913
            if (gl) c = 120514 + code - 945
        case (ALPH_BB)
            if (upper) then
                select case (code)
                case (iachar("C")); c = 8450
                case (iachar("H")); c = 8461
                case (iachar("N")); c = 8469
                case (iachar("P")); c = 8473
                case (iachar("Q")); c = 8474
                case (iachar("R")); c = 8477
                case (iachar("Z")); c = 8484
                case default; c = 120120 + code - iachar("A")
                end select
            end if
        case (ALPH_CAL)
            if (upper) then
                select case (code)
                case (iachar("B")); c = 8492
                case (iachar("E")); c = 8496
                case (iachar("F")); c = 8497
                case (iachar("H")); c = 8459
                case (iachar("I")); c = 8464
                case (iachar("L")); c = 8466
                case (iachar("M")); c = 8499
                case (iachar("R")); c = 8475
                case default; c = 119964 + code - iachar("A")
                end select
            end if
        case (ALPH_SF)
            if (upper) c = 120224 + code - iachar("A")
            if (lower) c = 120250 + code - iachar("a")
            if (digit) c = 120802 + code - iachar("0")
        end select
        if (c /= code) then
            if (glyph_cmap(FACE_MATH, c) == 0) c = code
        end if
    end function math_alphabet

    ! The glyph for a code point: the math font's, or Lato's for a
    ! character the math font does not have.
    integer function math_gid(cp, face) result(g)
        integer, intent(in) :: cp, face
        g = glyph_cmap(face, cp)
        if (g == 0) g = glyph_cmap(FACE_REGULAR, cp)
        if (g == 0) g = glyph_cmap(FACE_MATH, 32)
    end function math_gid

    ! ------------------------------------------------------------------
    ! Boxes
    ! ------------------------------------------------------------------

    ! The font size of a style, for a formula set at size.
    pure real(dp) function style_size(style, size) result(sz)
        integer, intent(in) :: style
        real(dp), intent(in) :: size
        select case (style)
        case (ST_S)
            sz = size*math_percent(MC_SCRIPT_PERCENT_SCALE_DOWN)/100.0_dp
        case (ST_SS)
            sz = size*math_percent(MC_SCRIPT_SCRIPT_PERCENT_SCALE_DOWN)/100.0_dp
        case default
            sz = size
        end select
    end function style_size

    ! The style of a superscript, and of a fraction's halves.
    pure integer function sup_style(style)
        integer, intent(in) :: style
        select case (style)
        case (ST_D, ST_T); sup_style = ST_S
        case default; sup_style = ST_SS
        end select
    end function sup_style

    pure integer function frac_style(style)
        integer, intent(in) :: style
        select case (style)
        case (ST_D); frac_style = ST_T
        case (ST_T); frac_style = ST_S
        case default; frac_style = ST_SS
        end select
    end function frac_style

    subroutine need_items(n)
        integer, intent(in) :: n
        integer, allocatable :: ti(:)
        real(dp), allocatable :: t(:)
        integer :: cap
        if (NI + n <= size(IT_KIND)) return
        cap = max(2*size(IT_KIND), NI + n)
        allocate (ti(cap))
        ti(1:NI) = IT_KIND(1:NI)
        call move_alloc(ti, IT_KIND)
        allocate (ti(cap))
        ti(1:NI) = IT_GID(1:NI)
        call move_alloc(ti, IT_GID)
        allocate (t(cap))
        t(1:NI) = IT_X(1:NI)
        call move_alloc(t, IT_X)
        allocate (t(cap))
        t(1:NI) = IT_Y(1:NI)
        call move_alloc(t, IT_Y)
        allocate (t(cap))
        t(1:NI) = IT_S(1:NI)
        call move_alloc(t, IT_S)
        allocate (t(cap))
        t(1:NI) = IT_W(1:NI)
        call move_alloc(t, IT_W)
        allocate (t(cap))
        t(1:NI) = IT_H(1:NI)
        call move_alloc(t, IT_H)
    end subroutine need_items
    subroutine add_glyph(gid, x, y, sz)
        integer, intent(in) :: gid
        real(dp), intent(in) :: x, y, sz
        call need_items(1)
        NI = NI + 1
        IT_KIND(NI) = 1
        IT_GID(NI) = gid
        IT_X(NI) = x
        IT_Y(NI) = y
        IT_S(NI) = sz
        IT_W(NI) = 0.0_dp
        IT_H(NI) = 0.0_dp
    end subroutine add_glyph
    subroutine add_rule(x, y, w, h)
        real(dp), intent(in) :: x, y, w, h
        call need_items(1)
        NI = NI + 1
        IT_KIND(NI) = 2
        IT_GID(NI) = 0
        IT_X(NI) = x
        IT_Y(NI) = y
        IT_S(NI) = 0.0_dp
        IT_W(NI) = w
        IT_H(NI) = h
    end subroutine add_rule
    ! Move a box's items by (dx, dy), y up.
    subroutine move_box(b, dx, dy)
        type(mbox_t), intent(in) :: b
        real(dp), intent(in) :: dx, dy
        integer :: k
        do k = b%i0, b%i1
            IT_X(k) = IT_X(k) + dx
            IT_Y(k) = IT_Y(k) + dy
        end do
    end subroutine move_box
    ! Move items k0..k1 to start at i0, sliding i0..k0-1 after them, for a
    ! box whose later part has to come first in reading order.
    subroutine to_front(i0, k0, k1)
        integer, intent(in) :: i0, k0, k1
        integer :: n
        n = k1 - i0 + 1
        if (k0 <= i0 .or. n <= 0) return
        IT_KIND(i0:k1) = cshift(IT_KIND(i0:k1), k0 - i0)
        IT_GID(i0:k1) = cshift(IT_GID(i0:k1), k0 - i0)
        IT_X(i0:k1) = cshift(IT_X(i0:k1), k0 - i0)
        IT_Y(i0:k1) = cshift(IT_Y(i0:k1), k0 - i0)
        IT_S(i0:k1) = cshift(IT_S(i0:k1), k0 - i0)
        IT_W(i0:k1) = cshift(IT_W(i0:k1), k0 - i0)
        IT_H(i0:k1) = cshift(IT_H(i0:k1), k0 - i0)
    end subroutine to_front
    ! An empty box at the end of the arena.
    pure function empty_box() result(b)
        type(mbox_t) :: b
        b%i0 = NI + 1
        b%i1 = NI
    end function empty_box
    ! The glyph a style sets: the script and scriptscript styles take the
    ! math font's alternates drawn for those sizes (ssty), where it has
    ! them.
    integer function script_glyph(gid, style) result(g)
        integer, intent(in) :: gid, style
        select case (style)
        case (ST_S); g = glyph_ssty(gid, 1)
        case (ST_SS); g = glyph_ssty(gid, 2)
        case default; g = gid
        end select
    end function script_glyph
    ! One glyph as a box: its advance, and its ink above and below the
    ! baseline.
    subroutine glyph_box(gid, sz, b)
        integer, intent(in) :: gid
        real(dp), intent(in) :: sz
        type(mbox_t), intent(out) :: b
        real(dp) :: x0, y0, x1, y1
        b%i0 = NI + 1
        call add_glyph(gid, 0.0_dp, 0.0_dp, sz)
        b%i1 = NI
        call glyph_bbox(gid, x0, y0, x1, y1)
        b%w = glyph_adv(gid)*sz
        b%h = y1*sz
        b%d = -y0*sz
        b%ital = glyph_italic(gid)*sz
        b%is_char = .true.
        b%gid = gid
        b%sz = sz
    end subroutine glyph_box
    ! Make a box at least as high and as deep as given, as a strut does.
    pure subroutine strut_box(b, h, d)
        type(mbox_t), intent(inout) :: b
        real(dp), intent(in) :: h, d
        b%h = max(b%h, h)
        b%d = max(b%d, d)
    end subroutine strut_box

    ! A list of noads as a box, in a style: TeX's mlist_to_hlist. The
    ! first pass turns every noad into a box and settles the classes; the
    ! second sets the boxes side by side with the glue between classes.
    ! A style change applies to what follows it in the list.
    recursive subroutine mlist_box(head, style, cramped, size, box)
        integer, intent(in) :: head, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t), allocatable :: bx(:)
        integer, allocatable :: cls_l(:), cls_r(:), idx(:), st(:)
        integer :: n, k, q, prev, cur
        real(dp) :: pen, sz

        call settle_auto(head, style, cramped, size)
        n = 0
        q = head
        do while (q > 0)
            n = n + 1
            q = NOADS(q)%next
        end do
        allocate (bx(n), cls_l(n), cls_r(n), idx(n), st(n))
        box = empty_box()
        if (n == 0) return

        cur = style
        q = head
        prev = 0
        do k = 1, n
            idx(k) = q
            st(k) = cur
            cls_l(k) = NOADS(q)%cls
            cls_r(k) = NOADS(q)%cls
            sz = style_size(cur, size)
            select case (NOADS(q)%kind)
            case (K_STYLE)
                cur = NOADS(q)%style
                bx(k) = empty_box()
            case (K_SPACE)
                bx(k) = empty_box()
                if (NOADS(q)%mu) then
                    bx(k)%w = NOADS(q)%amount*sz/18.0_dp
                else
                    bx(k)%w = NOADS(q)%amount*sz
                end if
            case (K_FRAC)
                call make_frac(q, cur, cramped, size, bx(k))
            case (K_RAD)
                call make_rad(q, cur, size, bx(k))
            case (K_ACC)
                call make_acc(q, cur, cramped, size, bx(k))
            case (K_OVER, K_UNDER)
                call make_bar(q, cur, cramped, size, bx(k))
            case (K_LR)
                call make_lr(q, cur, cramped, size, bx(k))
                ! An automatic pair is spaced as its delimiters would be.
                if (NOADS(q)%auto > 0) then
                    cls_l(k) = CL_OPEN
                    cls_r(k) = CL_CLOSE
                end if
            case (K_MID)
                ! Spaced as a closing on its left and an opening on its
                ! right, as e-TeX spaces \middle.
                cls_l(k) = CL_CLOSE
                cls_r(k) = CL_OPEN
                if (LR_TARGET >= 0.0_dp) then
                    call make_delim(NOADS(q)%cp, LR_TARGET, cur, size, bx(k), LR_FULL)
                else
                    bx(k) = empty_box()
                end if
            case (K_BIG)
                call make_big(q, cur, size, bx(k))
            case default
                ! A binary operator with nothing, or with an operator,
                ! relation, opening or punctuation before it, is ordinary;
                ! and so is one followed by a relation, closing or
                ! punctuation (rules 5 and 6).
                if (cls_l(k) == CL_BIN) then
                    if (prev == 0) then
                        cls_l(k) = CL_ORD
                    else if (any(cls_r(prev) == [CL_BIN, CL_OP, CL_REL, CL_OPEN, &
                                                 CL_PUNCT])) then
                        cls_l(k) = CL_ORD
                    end if
                    cls_r(k) = cls_l(k)
                end if
                if (prev > 0) then
                    if (cls_r(prev) == CL_BIN .and. any(cls_l(k) == [CL_REL, CL_CLOSE, &
                                                                     CL_PUNCT])) then
                        cls_l(prev) = CL_ORD
                        cls_r(prev) = CL_ORD
                    end if
                end if
                call make_atom(q, cur, cramped, size, bx(k))
            end select
            ! Whatever else carries scripts takes them on its box.
            select case (NOADS(q)%kind)
            case (K_FRAC, K_RAD, K_OVER, K_UNDER, K_LR, K_BIG)
                if (NOADS(q)%sup >= 0 .or. NOADS(q)%sub >= 0) &
                    call make_scripts(q, cur, cramped, size, bx(k))
            end select
            if (NOADS(q)%kind /= K_SPACE .and. NOADS(q)%kind /= K_STYLE) prev = k
            q = NOADS(q)%next
        end do
        ! A binary operator at the very end has nothing to operate on.
        if (prev > 0) then
            if (cls_r(prev) == CL_BIN) then
                cls_l(prev) = CL_ORD
                cls_r(prev) = CL_ORD
            end if
        end if

        pen = 0.0_dp
        prev = 0
        box%h = 0.0_dp
        box%d = 0.0_dp
        do k = 1, n
            if (NOADS(idx(k))%kind == K_STYLE) cycle
            if (NOADS(idx(k))%kind == K_SPACE) then
                pen = pen + bx(k)%w
                cycle
            end if
            if (prev > 0) pen = pen + muskip(cls_r(prev), cls_l(k), st(k)) &
                *style_size(st(k), size)/18.0_dp
            call move_box(bx(k), pen, 0.0_dp)
            pen = pen + bx(k)%w
            box%h = max(box%h, bx(k)%h)
            box%d = max(box%d, bx(k)%d)
            prev = k
        end do
        box%w = pen
        box%i1 = NI
        if (n == 1) then
            box%gid = bx(1)%gid
            box%kgid = bx(1)%kgid
            box%sz = bx(1)%sz
        end if
    end subroutine mlist_box

    ! An atom: its nucleus, and its scripts if it has any. A large
    ! operator takes them above and below in display style (or after
    ! \limits) and beside it otherwise.
    recursive subroutine make_atom(q, style, cramped, size, box)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        real(dp) :: sz, delta
        logical :: op, limits

        sz = style_size(style, size)
        op = NOADS(q)%cls == CL_OP
        delta = 0.0_dp
        select case (NOADS(q)%nuc)
        case (NUC_CHAR)
            if (op) then
                call make_op(q, style, size, box, delta)
            else
                call glyph_box(script_glyph(math_gid(NOADS(q)%cp, NOADS(q)%face), style), &
                               sz, box)
                box%kgid = math_gid(NOADS(q)%cp, NOADS(q)%face)
                ! TeX's rule for a character of a math font: its italic
                ! correction is part of its width unless a subscript is
                ! going to tuck in under it.
                if (NOADS(q)%sub < 0) then
                    box%w = box%w + box%ital
                    box%ital = 0.0_dp
                end if
            end if
        case (NUC_LIST)
            call mlist_box(NOADS(q)%list, style, cramped, size, box)
        case (NUC_TEXT)
            call text_box(q, style, size, box)
        case default
            box = empty_box()
        end select
        if (NOADS(q)%sup < 0 .and. NOADS(q)%sub < 0) return

        limits = op .and. (NOADS(q)%limits == 1 .or. &
                           (NOADS(q)%limits == 0 .and. style == ST_D))
        if (limits) then
            call make_limits(q, style, cramped, size, box, delta)
        else
            if (op) then
                ! An operator's italic correction goes only between its
                ! subscript and its superscript.
                if (NOADS(q)%sub >= 0) then
                    box%w = box%w - delta
                    box%ital = delta
                else
                    box%ital = 0.0_dp
                end if
            end if
            call make_scripts(q, style, cramped, size, box)
        end if
    end subroutine make_atom

    ! Text as a box: the letters of an operator name in the math font, or
    ! \text in the text font with its kerning.
    subroutine text_box(q, style, size, box)
        integer, intent(in) :: q, style
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: g
        type(glyphrun_t) :: run
        integer :: k, code, nb, i0
        real(dp) :: sz, pen, x0, y0, x1, y1

        sz = style_size(style, size)
        box = empty_box()
        i0 = NI + 1
        if (NOADS(q)%face == FACE_MATH) then
            pen = 0.0_dp
            k = NOADS(q)%t0
            do while (k <= NOADS(q)%t1)
                call utf8_next(TPOOL, k, code, nb)
                k = k + nb
                call glyph_box(script_glyph(math_gid(code, FACE_MATH), style), sz, g)
                call move_box(g, pen, 0.0_dp)
                pen = pen + g%w
                box%h = max(box%h, g%h)
                box%d = max(box%d, g%d)
            end do
        else
            ! Word by word: a space is glue, as in TeX, kerned against
            ! nothing.
            pen = 0.0_dp
            k = NOADS(q)%t0
            do while (k <= NOADS(q)%t1)
                if (TPOOL(k:k) == " ") then
                    pen = pen + glyph_adv(glyph_cmap(NOADS(q)%face, 32))*sz
                    k = k + 1
                    cycle
                end if
                nb = index(TPOOL(k:NOADS(q)%t1), " ") - 1
                if (nb < 0) nb = NOADS(q)%t1 - k + 1
                call text_layout(TPOOL(k:k + nb - 1), sz, NOADS(q)%face, &
                                 pen, 0.0_dp, run, x1)
                pen = x1
                k = k + nb
            end do
            do k = 1, run%n
                call add_glyph(run%gid(k), run%x(k), 0.0_dp, sz)
                call glyph_bbox(run%gid(k), x0, y0, x1, y1)
                box%h = max(box%h, y1*sz)
                box%d = max(box%d, -y0*sz)
            end do
        end if
        box%i0 = i0
        box%i1 = NI
        box%w = pen
    end subroutine text_box

    ! A large operator's nucleus (rule 13): in display style the variant
    ! of the symbol made for it, at least DisplayOperatorMinHeight and a
    ! quarter larger than the text-style one, or its assembly where no
    ! variant is that large; centred on the axis. delta is its italic
    ! correction, which goes between its scripts.
    recursive subroutine make_op(q, style, size, box, delta)
        integer, intent(in) :: q, style
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        real(dp), intent(out) :: delta
        integer, allocatable :: vg(:)
        real(dp), allocatable :: va(:)
        integer :: g0, g, nvar, k
        real(dp) :: sz, x0, y0, x1, y1, h1, dy
        logical :: found

        sz = style_size(style, size)
        g0 = math_gid(NOADS(q)%cp, FACE_MATH)
        g = script_glyph(g0, style)
        found = .true.
        if (style == ST_D) then
            call glyph_bbox(g0, x0, y0, x1, y1)
            h1 = max(math_const(MC_DISPLAY_OPERATOR_MIN_HEIGHT), 1.25_dp*(y1 - y0))*sz
            call glyph_variants(g0, .true., nvar, vg, va)
            found = .false.
            do k = 1, nvar
                g = vg(k)
                if (va(k)*sz >= h1) then
                    found = .true.
                    exit
                end if
            end do
            if (nvar == 0) found = .true.
        end if
        if (.not. found .and. has_assembly(g0, .true.)) then
            call make_assembly(g0, h1, sz, .true., box)
            delta = 0.0_dp
        else
            call glyph_box(g, sz, box)
            delta = box%ital
        end if
        ! Centred on the axis.
        dy = math_const(MC_AXIS_HEIGHT)*sz - 0.5_dp*(box%h - box%d)
        call move_box(box, 0.0_dp, dy)
        box%h = box%h + dy
        box%d = box%d - dy
        ! The scripts of a large operator go by the box, not by a glyph.
        box%is_char = .false.
        box%kgid = 0
        box%ital = 0.0_dp
    end subroutine make_op

    ! Limits above and below an operator: each centred over it, the upper
    ! one moved right and the lower one left by half its italic correction,
    ! each clear of it by the MATH table's gap and baseline distance, with
    ! TeX's \big_op_spacing5 of space beyond it, which XeTeX takes to be
    ! StackGapMin.
    recursive subroutine make_limits(q, style, cramped, size, box, delta)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size, delta
        type(mbox_t), intent(inout) :: box
        type(mbox_t) :: x, z
        real(dp) :: sz, w, up, down, h, d, w0
        logical :: has_sup, has_sub

        sz = style_size(style, size)
        has_sup = NOADS(q)%sup >= 0
        has_sub = NOADS(q)%sub >= 0
        w0 = box%w
        h = box%h
        d = box%d
        w = w0
        if (has_sup) then
            call mlist_box(NOADS(q)%sup, sup_style(style), cramped, size, x)
            w = max(w, x%w)
        end if
        if (has_sub) then
            call mlist_box(NOADS(q)%sub, sup_style(style), .true., size, z)
            w = max(w, z%w)
        end if
        call move_box(box, 0.5_dp*(w - w0), 0.0_dp)
        if (has_sup) then
            up = max(math_const(MC_UPPER_LIMIT_BASELINE_RISE_MIN)*sz - x%d, &
                     math_const(MC_UPPER_LIMIT_GAP_MIN)*sz)
            call move_box(x, 0.5_dp*(w - x%w) + 0.5_dp*delta, h + up + x%d)
            box%h = h + up + x%d + x%h + math_const(MC_STACK_GAP_MIN)*sz
        end if
        if (has_sub) then
            down = max(math_const(MC_LOWER_LIMIT_BASELINE_DROP_MIN)*sz - z%h, &
                       math_const(MC_LOWER_LIMIT_GAP_MIN)*sz)
            call move_box(z, 0.5_dp*(w - z%w) - 0.5_dp*delta, -(d + down + z%h))
            box%d = d + down + z%h + z%d + math_const(MC_STACK_GAP_MIN)*sz
        end if
        ! Reading order: the upper limit, the operator, the lower one.
        if (has_sup) call to_front(box%i0, x%i0, x%i1)
        box%w = w
        box%i1 = NI
        box%is_char = .false.
        box%ital = 0.0_dp
    end subroutine make_limits

    ! The scripts of an atom set against its nucleus (rule 18, with the
    ! MATH table's constants). A superscript is raised by at least its
    ! shift and far enough for its bottom to clear the baseline's minimum;
    ! a subscript is lowered by at least its shift and far enough for its
    ! top to stay under its maximum; with both, they are pulled apart to
    ! the minimum gap, the subscript going down until the superscript's
    ! bottom has risen as far as it may. A superscript is moved out by the
    ! nucleus's italic correction and a subscript is not.
    recursive subroutine make_scripts(q, style, cramped, size, box)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(inout) :: box
        type(mbox_t) :: sup, sub
        real(dp) :: sz, ssz, u, v, gap, psi, w, x_sup, x_sub
        logical :: has_sup, has_sub

        sz = style_size(style, size)
        ssz = style_size(sup_style(style), size)
        has_sup = NOADS(q)%sup >= 0
        has_sub = NOADS(q)%sub >= 0
        if (box%is_char) then
            u = 0.0_dp
            v = 0.0_dp
        else
            u = box%h - math_const(MC_SUPERSCRIPT_BASELINE_DROP_MAX)*ssz
            v = box%d + math_const(MC_SUBSCRIPT_BASELINE_DROP_MIN)*ssz
        end if
        x_sup = box%w + box%ital

        if (has_sup) call mlist_box(NOADS(q)%sup, sup_style(style), cramped, size, sup)
        if (has_sub) call mlist_box(NOADS(q)%sub, sup_style(style), .true., size, sub)

        if (has_sup) then
            if (cramped) then
                u = max(u, math_const(MC_SUPERSCRIPT_SHIFT_UP_CRAMPED)*sz)
            else
                u = max(u, math_const(MC_SUPERSCRIPT_SHIFT_UP)*sz)
            end if
            u = max(u, sup%d + math_const(MC_SUPERSCRIPT_BOTTOM_MIN)*sz)
        end if
        if (has_sub .and. .not. has_sup) then
            v = max(v, math_const(MC_SUBSCRIPT_SHIFT_DOWN)*sz, &
                    sub%h - math_const(MC_SUBSCRIPT_TOP_MAX)*sz)
        else if (has_sub) then
            v = max(v, math_const(MC_SUBSCRIPT_SHIFT_DOWN)*sz)
            gap = (u - sup%d) - (sub%h - v)
            if (gap < math_const(MC_SUB_SUPERSCRIPT_GAP_MIN)*sz) then
                v = v + math_const(MC_SUB_SUPERSCRIPT_GAP_MIN)*sz - gap
                psi = math_const(MC_SUPERSCRIPT_BOTTOM_MAX_WITH_SUBSCRIPT)*sz - (u - sup%d)
                if (psi > 0.0_dp) then
                    u = u + psi
                    v = v - psi
                end if
            end if
        end if

        ! The math kerns at the nucleus's corners and the scripts' facing
        ! ones, where both are single glyphs.
        if (has_sup) x_sup = x_sup + script_kern(box, sup, u, .true.)
        x_sub = box%w
        if (has_sub) x_sub = x_sub + script_kern(box, sub, -v, .false.)

        w = box%w
        if (has_sup) then
            call move_box(sup, x_sup, u)
            w = max(w, x_sup + sup%w)
            box%h = max(box%h, u + sup%h)
            box%d = max(box%d, sup%d - u)
        end if
        if (has_sub) then
            call move_box(sub, x_sub, -v)
            w = max(w, x_sub + sub%w)
            box%h = max(box%h, sub%h - v)
            box%d = max(box%d, sub%d + v)
        end if
        ! The space after the scripts is the formula's, as TeX's
        ! \scriptspace is, whatever the style of the nucleus.
        box%w = w + math_const(MC_SPACE_AFTER_SCRIPT)*size
        box%i1 = NI
        box%is_char = .false.
        box%ital = 0.0_dp
    end subroutine make_scripts
    ! How far a script moves in towards its nucleus, from the math kerns
    ! (OpenType's cut-ins): the nucleus's kern at its top or bottom right
    ! corner plus the script's at its facing left corner, each read at two
    ! heights -- the nucleus's top and the script's bottom for a
    ! superscript, the script's top and the nucleus's bottom for a
    ! subscript -- and the    ! smaller of the two sums taken, as XeTeX takes it. The kerns are the
    ! characters' own, not those of their script-size alternates. shift is
    ! how far the script's baseline sits above the nucleus's.
    function script_kern(base, scr, shift, sup) result(k)
        type(mbox_t), intent(in) :: base, scr
        real(dp), intent(in) :: shift
        logical, intent(in) :: sup
        real(dp) :: k, h1, h2
        k = 0.0_dp
        if (.not. base%is_char .or. base%kgid == 0) return
        if (sup) then
            h1 = base%h
            h2 = shift - scr%d
            k = min(corner(h1, 1, 4), corner(h2, 1, 4))
        else
            h1 = shift + scr%h
            h2 = -base%d
            k = min(corner(h1, 3, 2), corner(h2, 3, 2))
        end if

    contains

        real(dp) function corner(h, cb, cs)
            real(dp), intent(in) :: h
            integer, intent(in) :: cb, cs
            corner = glyph_math_kern(base%kgid, cb, h/base%sz)*base%sz
            if (scr%kgid > 0) corner = corner + &
                glyph_math_kern(scr%kgid, cs, (h - shift)/scr%sz)*scr%sz
        end function corner

    end function script_kern

    ! \frac{a}{b} and the stacks without a rule (\binom, \atop), rule 15
    ! with the MATH table's constants: the halves one style down, the
    ! denominator cramped, each centred over the other. A fraction's
    ! halves are moved out until they clear the rule, which sits on the
    ! axis, by the minimum gap; a stack's are moved apart, half each, to
    ! its minimum gap. The delimiters of \binom and \choose are
    ! DelimitedSubFormulaMinHeight tall in display style and at most 1.5
    ! ems otherwise, as in XeTeX; a fraction without delimiters has a null
    ! delimiter's space on either side, as TeX leaves it.
    recursive subroutine make_frac(q, style0, cramped, size, box)
        integer, intent(in) :: q, style0
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: num, den, dl, dr
        real(dp) :: sz, u, v, a, th, phi_n, phi_d, w, nds, clr, delta, target
        integer :: i0, style

        target = 0.0_dp
        style = style0
        if (NOADS(q)%style >= 0) style = NOADS(q)%style
        sz = style_size(style, size)
        nds = NULL_DELIM*size
        i0 = NI + 1
        a = math_const(MC_AXIS_HEIGHT)*sz
        th = 0.0_dp
        if (NOADS(q)%rule) th = math_const(MC_FRACTION_RULE_THICKNESS)*sz

        if (NOADS(q)%dl > 0) then
            target = math_const(MC_DELIMITED_SUB_FORMULA_MIN_HEIGHT)*sz
            if (style /= ST_D) target = min(1.5_dp*sz, target)
            call make_delim(NOADS(q)%dl, target, style, size, dl)
        end if
        call mlist_box(NOADS(q)%a, frac_style(style), cramped, size, num)
        if (NOADS(q)%strut) call strut_box(num, STRUT_H*size, STRUT_D*size)
        call mlist_box(NOADS(q)%b, frac_style(style), .true., size, den)

        if (NOADS(q)%rule) then
            if (style == ST_D) then
                u = math_const(MC_FRACTION_NUMERATOR_DISPLAY_STYLE_SHIFT_UP)*sz
                v = math_const(MC_FRACTION_DENOMINATOR_DISPLAY_STYLE_SHIFT_DOWN)*sz
                phi_n = math_const(MC_FRACTION_NUM_DISPLAY_STYLE_GAP_MIN)*sz
                phi_d = math_const(MC_FRACTION_DENOM_DISPLAY_STYLE_GAP_MIN)*sz
            else
                u = math_const(MC_FRACTION_NUMERATOR_SHIFT_UP)*sz
                v = math_const(MC_FRACTION_DENOMINATOR_SHIFT_DOWN)*sz
                phi_n = math_const(MC_FRACTION_NUMERATOR_GAP_MIN)*sz
                phi_d = math_const(MC_FRACTION_DENOMINATOR_GAP_MIN)*sz
            end if
            if ((u - num%d) - (a + 0.5_dp*th) < phi_n) u = phi_n + a + 0.5_dp*th + num%d
            if ((a - 0.5_dp*th) - (den%h - v) < phi_d) v = phi_d - a + 0.5_dp*th + den%h
        else
            if (style == ST_D) then
                u = math_const(MC_STACK_TOP_DISPLAY_STYLE_SHIFT_UP)*sz
                v = math_const(MC_STACK_BOTTOM_DISPLAY_STYLE_SHIFT_DOWN)*sz
                clr = math_const(MC_STACK_DISPLAY_STYLE_GAP_MIN)*sz
            else
                u = math_const(MC_STACK_TOP_SHIFT_UP)*sz
                v = math_const(MC_STACK_BOTTOM_SHIFT_DOWN)*sz
                clr = math_const(MC_STACK_GAP_MIN)*sz
            end if
            delta = 0.5_dp*(clr - ((u - num%d) - (den%h - v)))
            if (delta > 0.0_dp) then
                u = u + delta
                v = v + delta
            end if
        end if

        w = max(num%w, den%w)
        if (NOADS(q)%dl > 0) then
            nds = dl%w
        end if
        call move_box(num, nds + 0.5_dp*(w - num%w), u)
        call move_box(den, nds + 0.5_dp*(w - den%w), -v)
        if (NOADS(q)%rule) call add_rule(nds, a - 0.5_dp*th, w, th)
        box%w = nds + w
        box%h = max(u + num%h, a + 0.5_dp*th)
        box%d = max(v + den%d, -(a - 0.5_dp*th))
        if (NOADS(q)%dr > 0) then
            call make_delim(NOADS(q)%dr, target, style, size, dr)
            call move_box(dr, box%w, 0.0_dp)
            box%w = box%w + dr%w
            box%h = max(box%h, dr%h)
            box%d = max(box%d, dr%d)
        else
            box%w = box%w + nds
        end if
        if (NOADS(q)%dl > 0) then
            box%h = max(box%h, dl%h)
            box%d = max(box%d, dl%d)
        end if
        box%i0 = i0
        box%i1 = NI
    end subroutine make_frac

    ! \sqrt{a} and \sqrt[n]{a} (rule 11, with the MATH table's constants):
    ! the radicand in the same style, cramped; the smallest variant of the
    ! radical sign that covers it with the gap and the rule above, or the
    ! sign's assembly; any height the sign has to spare split evenly above
    ! and below; the rule along the top of the sign, with the extra
    ! ascender above it. A degree is set in scriptscript style with
    ! RadicalKernBeforeDegree before it and RadicalKernAfterDegree after,
    ! its baseline raised by RadicalDegreeBottomRaisePercent of the
    ! radical's height less its depth, as unicode-math places it.
    recursive subroutine make_rad(q, style, size, box)
        integer, intent(in) :: q, style
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: x, sign, deg
        real(dp) :: sz, th, phi, need, hg, dg, extra, rise, xs, left, ybot
        integer :: i0, g, nd

        sz = style_size(style, size)
        th = math_const(MC_RADICAL_RULE_THICKNESS)*sz
        if (style == ST_D) then
            phi = math_const(MC_RADICAL_DISPLAY_STYLE_VERTICAL_GAP)*sz
        else
            phi = math_const(MC_RADICAL_VERTICAL_GAP)*sz
        end if
        i0 = NI + 1
        ! The sign goes into the box before the radicand, as TeX puts it;
        ! the radicand is laid out first to know how tall a sign it needs,
        ! and then moved behind it.
        call mlist_box(NOADS(q)%a, style, .true., size, x)
        need = x%h + x%d + phi + th

        g = glyph_cmap(FACE_MATH, 8730)
        call make_delim_box(g, need, sz, sign)
        hg = sign%h
        dg = sign%d
        extra = (hg + dg) - need
        if (extra > 0.0_dp) phi = phi + 0.5_dp*extra
        ! The top of the sign is where the rule's top goes.
        rise = x%h + phi + th - hg
        call move_box(sign, 0.0_dp, rise)
        xs = 0.0_dp
        nd = 0
        box%h = x%h + phi + th + math_const(MC_RADICAL_EXTRA_ASCENDER)*sz
        box%d = max(x%d, dg - rise)
        if (NOADS(q)%b >= 0) then
            call mlist_box(NOADS(q)%b, ST_SS, .false., size, deg)
            nd = deg%i1 - deg%i0 + 1
            left = math_const(MC_RADICAL_KERN_BEFORE_DEGREE)*sz
            ybot = math_percent(MC_RADICAL_DEGREE_BOTTOM_RAISE_PERCENT)/100.0_dp &
                   *(box%h - box%d)
            call move_box(deg, left, ybot)
            xs = left + deg%w + math_const(MC_RADICAL_KERN_AFTER_DEGREE)*sz
            box%h = max(box%h, ybot + deg%h)
            box%d = max(box%d, deg%d - ybot)
            if (xs < 0.0_dp) then
                ! A degree narrower than the kern after it leaves the sign
                ! where it would be without one.
                call move_box(deg, -xs, 0.0_dp)
                xs = 0.0_dp
            end if
        end if
        call move_box(sign, xs, 0.0_dp)
        call move_box(x, xs + sign%w, 0.0_dp)
        ! Reading order: the degree, the sign, the radicand.
        if (nd > 0) call to_front(i0, deg%i0, deg%i1)
        call to_front(i0 + nd, sign%i0 + nd, sign%i1 + nd)
        call add_rule(xs + sign%w, x%h + phi, x%w, th)
        box%i0 = i0
        box%i1 = NI
        box%w = xs + sign%w + x%w
    end subroutine make_rad

    ! An accent over its argument (rule 12, with the MATH table's
    ! constants): the argument cramped; the accent centred on the
    ! argument's top accent attachment (or its middle) by its own, the
    ! smallest of its widths that covers the argument when it is a wide
    ! one, or its assembly; lowered into the argument by the argument's
    ! height or AccentBaseHeight, whichever is less, so that an accent sits
    ! as the font draws it over a letter the height of an x and rises over
    ! a taller one. Under an accent the dotless i and j are used. A
    ! character's scripts are set on it first, the accent going over the
    ! character alone, as TeX sets them.
    recursive subroutine make_acc(q, style, cramped, size, box)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: x, acc
        integer, allocatable :: vg(:)
        real(dp), allocatable :: va(:)
        integer :: g, ga, ga0, nvar, k, i0, hq, cnuc
        real(dp) :: sz, s, sa, h, w, delta, x0, y0, x1, y1, ya
        logical :: char_nuc, asm, has_scripts

        sz = style_size(style, size)
        i0 = NI + 1
        hq = NOADS(q)%a
        char_nuc = .false.
        cnuc = 0
        if (hq > 0) then
            if (NOADS(hq)%next == 0 .and. NOADS(hq)%kind == K_ATOM .and. &
                NOADS(hq)%nuc == NUC_CHAR .and. NOADS(hq)%cls /= CL_OP .and. &
                NOADS(hq)%sup < 0 .and. NOADS(hq)%sub < 0) then
                char_nuc = .true.
                cnuc = hq
            end if
        end if
        has_scripts = NOADS(q)%sup >= 0 .or. NOADS(q)%sub >= 0
        if (char_nuc) then
            g = math_gid(NOADS(cnuc)%cp, FACE_MATH)
            g = glyph_dotless(g)
            call glyph_box(script_glyph(g, style), sz, x)
            x%kgid = g
            s = glyph_top_accent(script_glyph(g, style))*sz
            w = x%w + x%ital
            h = x%h
            ! The accent's scripts go on the character, as TeX sets them,
            ! and the accent over the character alone.
            if (NOADS(q)%sub < 0) then
                x%w = x%w + x%ital
                x%ital = 0.0_dp
            end if
            if (has_scripts) call make_scripts(q, style, cramped, size, x)
        else
            call mlist_box(hq, style, .true., size, x)
            s = 0.5_dp*x%w
            w = x%w
            h = x%h
        end if

        ga0 = math_gid(NOADS(q)%cp, FACE_MATH)
        ga = ga0
        asm = .false.
        if (NOADS(q)%wide) then
            call glyph_variants(ga0, .false., nvar, vg, va)
            do k = 1, nvar
                if (va(k)*sz > w) exit
                ga = vg(k)
            end do
            if (nvar > 0) then
                if (va(nvar)*sz <= w .and. has_assembly(ga0, .false.)) asm = .true.
            end if
        end if
        if (asm) then
            call make_assembly(ga0, w, sz, .false., acc)
            sa = 0.5_dp*acc%w
            ya = 0.0_dp
        else
            call glyph_box(script_glyph(ga, style), sz, acc)
            sa = glyph_top_accent(script_glyph(ga, style))*sz
            call glyph_bbox(script_glyph(ga, style), x0, y0, x1, y1)
            ya = max(-y0*sz, 0.0_dp)
        end if
        delta = min(h, math_const(MC_ACCENT_BASE_HEIGHT)*sz)
        call move_box(acc, s - sa, h - delta + ya)
        call to_front(i0, acc%i0, acc%i1)
        box%i0 = i0
        box%i1 = NI
        box%w = x%w
        box%h = max(x%h, h - delta + ya + acc%h)
        box%d = x%d
        ! Anything but a character takes the scripts on the accented box.
        if (has_scripts .and. .not. char_nuc) call make_scripts(q, style, cramped, size, box)
    end subroutine make_acc

    ! \overline and \underline (rules 9 and 10, with the MATH table's
    ! Overbar and Underbar constants): a rule above the argument, which is
    ! cramped, or below it, with the gap between and the extra space
    ! beyond.
    recursive subroutine make_bar(q, style, cramped, size, box)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        real(dp) :: sz, gap, th, extra

        sz = style_size(style, size)
        if (NOADS(q)%kind == K_OVER) then
            call mlist_box(NOADS(q)%a, style, .true., size, box)
            gap = math_const(MC_OVERBAR_VERTICAL_GAP)*sz
            th = math_const(MC_OVERBAR_RULE_THICKNESS)*sz
            extra = math_const(MC_OVERBAR_EXTRA_ASCENDER)*sz
            call add_rule(0.0_dp, box%h + gap, box%w, th)
            box%h = box%h + gap + th + extra
        else
            call mlist_box(NOADS(q)%a, style, cramped, size, box)
            gap = math_const(MC_UNDERBAR_VERTICAL_GAP)*sz
            th = math_const(MC_UNDERBAR_RULE_THICKNESS)*sz
            extra = math_const(MC_UNDERBAR_EXTRA_DESCENDER)*sz
            call add_rule(0.0_dp, -(box%d + gap + th), box%w, th)
            box%d = box%d + gap + th + extra
        end if
        box%i1 = NI
        box%is_char = .false.
        box%ital = 0.0_dp
    end subroutine make_bar

    ! Decides the automatic pairs of a list, in the styles they are set
    ! in. A pair grows, becoming a \left...\right, when what it encloses
    ! is taller than the plain delimiters by Typst's measure (it spans
    ! more than either delimiter's height and 0.1 em from the axis); it
    ! then takes the closing delimiter's scripts, and its lone |s become
    ! \middle. Otherwise the pair is put back as it was written, so that
    ! f(x) is set exactly as without automatic delimiters.
    recursive subroutine settle_auto(head, style, cramped, size)
        integer, intent(in) :: head, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t) :: inner
        integer :: q, cur, i0, o, c, nxt, a, last
        real(dp) :: sz, ax, full, save, x0, y0, x1, y1, hl, hr
        logical :: grow

        cur = style
        q = head
        do while (q > 0)
            if (NOADS(q)%kind == K_STYLE) cur = NOADS(q)%style
            if (NOADS(q)%kind == K_LR .and. NOADS(q)%auto == 1) then
                sz = style_size(cur, size)
                i0 = NI
                save = LR_TARGET
                LR_TARGET = -1.0_dp
                call mlist_box(NOADS(q)%a, cur, cramped, size, inner)
                LR_TARGET = save
                NI = i0
                ax = math_const(MC_AXIS_HEIGHT)*sz
                full = 2.0_dp*max(inner%h - ax, inner%d + ax)
                call glyph_bbox(math_gid(NOADS(q)%dl, FACE_MATH), x0, y0, x1, y1)
                hl = (y1 - y0)*sz
                call glyph_bbox(math_gid(NOADS(q)%dr, FACE_MATH), x0, y0, x1, y1)
                hr = (y1 - y0)*sz
                grow = full - AUTO_SHORTFALL*sz > max(hl, hr)
                o = NOADS(q)%lo
                c = NOADS(q)%lc
                a = NOADS(q)%a
                if (grow) then
                    NOADS(q)%auto = 2
                    NOADS(q)%sup = NOADS(c)%sup
                    NOADS(q)%sub = NOADS(c)%sub
                    NOADS(c)%sup = -1
                    NOADS(c)%sub = -1
                    last = a
                    do while (last > 0)
                        if (NOADS(last)%amid) NOADS(last)%kind = K_MID
                        last = NOADS(last)%next
                    end do
                else
                    ! The opening takes the pair's place in the list, and
                    ! the contents and the closing follow it.
                    nxt = NOADS(q)%next
                    NOADS(q) = NOADS(o)
                    if (a > 0) then
                        NOADS(q)%next = a
                        last = a
                        do while (NOADS(last)%next > 0)
                            last = NOADS(last)%next
                        end do
                        NOADS(last)%next = c
                    else
                        NOADS(q)%next = c
                    end if
                    NOADS(c)%next = nxt
                end if
            end if
            q = NOADS(q)%next
        end do
    end subroutine settle_auto

    ! \left ... \right (rule 19): the group is laid out once to measure it,
    ! and its delimiters are made to cover it from the axis, by TeX's
    ! \delimiterfactor of 901 and \delimitershortfall of 5pt; then it is
    ! laid out again with its \middle delimiters at that size. The
    ! delimiters of an automatic pair cover it as Typst's do: all of it,
    ! less 0.1 em, with an assembly built to cover all of it.
    recursive subroutine make_lr(q, style, cramped, size, box)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: inner, dl, dr
        real(dp) :: sz, a, d1, d2, target, full, save, save_full
        integer :: i0

        sz = style_size(style, size)
        i0 = NI + 1
        save = LR_TARGET
        save_full = LR_FULL
        LR_TARGET = -1.0_dp
        call mlist_box(NOADS(q)%a, style, cramped, size, inner)
        NI = i0 - 1
        a = math_const(MC_AXIS_HEIGHT)*sz
        d2 = inner%d + a
        d1 = inner%h + inner%d - d2
        if (d2 > d1) d1 = d2
        if (NOADS(q)%auto > 0) then
            full = 2.0_dp*d1
            target = full - AUTO_SHORTFALL*sz
        else
            target = max(DELIM_FACTOR*d1, 2.0_dp*d1 - SHORTFALL*size)
            full = target
        end if

        call make_delim(NOADS(q)%dl, target, style, size, dl, full)
        LR_TARGET = target
        LR_FULL = full
        call mlist_box(NOADS(q)%a, style, cramped, size, inner)
        LR_TARGET = save
        LR_FULL = save_full
        call make_delim(NOADS(q)%dr, target, style, size, dr, full)
        call move_box(inner, dl%w, 0.0_dp)
        call move_box(dr, dl%w + inner%w, 0.0_dp)
        box%i0 = i0
        box%i1 = NI
        box%w = dl%w + inner%w + dr%w
        box%h = max(dl%h, inner%h, dr%h)
        box%d = max(dl%d, inner%d, dr%d)
    end subroutine make_lr

    ! \big and its relatives, as amsmath makes them: the delimiter a
    ! \left would put around an empty box 1, 1.5, 2 or 2.5 times 1.2 the
    ! height and depth of a parenthesis, centred on the axis.
    subroutine make_big(q, style, size, box)
        integer, intent(in) :: q, style
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        real(dp) :: sz, hb, x0, y0, x1, y1, d1, target
        real(dp), parameter :: FACTOR(4) = [1.0_dp, 1.5_dp, 2.0_dp, 2.5_dp]

        sz = style_size(style, size)
        call glyph_bbox(glyph_cmap(FACE_MATH, iachar("(")), x0, y0, x1, y1)
        hb = FACTOR(NOADS(q)%level)*1.2_dp*(y1 - y0)*size
        d1 = 0.5_dp*hb
        target = max(DELIM_FACTOR*d1, 2.0_dp*d1 - SHORTFALL*size)
        call make_delim(NOADS(q)%cp, target, style, size, box)
    end subroutine make_big

    ! A delimiter at least target tall, centred on the axis; the null
    ! delimiter is an empty box a null delimiter's space wide. An assembly
    ! is built to full, when given, rather than to target.
    subroutine make_delim(code, target, style, size, box, full)
        integer, intent(in) :: code, style
        real(dp), intent(in) :: target, size
        type(mbox_t), intent(out) :: box
        real(dp), intent(in), optional :: full
        real(dp) :: sz, dy

        sz = style_size(style, size)
        if (code == 0) then
            box = empty_box()
            box%w = NULL_DELIM*size
            return
        end if
        call make_delim_box(math_gid(code, FACE_MATH), target, sz, box, full)
        dy = math_const(MC_AXIS_HEIGHT)*sz - 0.5_dp*(box%h - box%d)
        call move_box(box, 0.0_dp, dy)
        box%h = box%h + dy
        box%d = box%d - dy
    end subroutine make_delim

    ! The glyph g at size sz, or the first of its vertical variants at
    ! least target tall, or its assembly when none is, or the largest
    ! variant when it has no assembly either; not yet centred.
    subroutine make_delim_box(g, target, sz, box, full)
        integer, intent(in) :: g
        real(dp), intent(in) :: target, sz
        type(mbox_t), intent(out) :: box
        real(dp), intent(in), optional :: full
        integer, allocatable :: vg(:)
        real(dp), allocatable :: va(:)
        integer :: nvar, k, best
        real(dp) :: bv

        call glyph_variants(g, .true., nvar, vg, va)
        best = g
        bv = -1.0_dp
        do k = 1, nvar
            if (va(k) > bv) then
                bv = va(k)
                best = vg(k)
            end if
            if (va(k)*sz >= target) then
                call glyph_box(vg(k), sz, box)
                return
            end if
        end do
        if (has_assembly(g, .true.)) then
            if (present(full)) then
                call make_assembly(g, max(target, full), sz, .true., box)
            else
                call make_assembly(g, target, sz, .true., box)
            end if
        else
            call glyph_box(best, sz, box)
        end if
    end subroutine make_delim_box

    logical function has_assembly(g, vertical)
        integer, intent(in) :: g
        logical, intent(in) :: vertical
        integer, allocatable :: parts(:)
        real(dp), allocatable :: st(:), en(:), fu(:)
        logical, allocatable :: ex(:)
        integer :: n
        real(dp) :: ic
        call glyph_assembly(g, vertical, n, parts, st, en, fu, ex, ic)
        has_assembly = n > 0
    end function has_assembly

    ! A glyph built from its assembly, at least s long along its
    ! direction (as XeTeX builds it): as few repeats of the extenders as
    ! reach s with every joint at its largest overlap, and then the joints
    ! eased out evenly, each no further than MinConnectorOverlap allows. A
    ! vertical one stands on the baseline, its parts bottom to top; a
    ! horizontal one runs left to right.
    subroutine make_assembly(g, s, sz, vertical, box)
        integer, intent(in) :: g
        real(dp), intent(in) :: s, sz
        logical, intent(in) :: vertical
        type(mbox_t), intent(out) :: box
        integer, allocatable :: parts(:)
        real(dp), allocatable :: st(:), en(:), fu(:)
        logical, allocatable :: ex(:)
        real(dp), allocatable :: joint(:), give(:)
        integer :: n, reps, i, j, m, k, nj
        real(dp) :: ic, minov, smax, o, prev_o, nat, str, stretch, pos, x0, y0, x1, y1
        logical :: no_ext
        integer, allocatable :: seq(:)

        call glyph_assembly(g, vertical, n, parts, st, en, fu, ex, ic)
        minov = real(MIN_CONNECTOR_OVERLAP, dp)/real(FACE_EM(FACE_MATH), dp)
        reps = -1
        no_ext = .true.
        do
            reps = reps + 1
            smax = 0.0_dp
            prev_o = 0.0_dp
            do i = 1, n
                m = 1
                if (ex(i)) then
                    no_ext = .false.
                    m = reps
                end if
                do j = 1, m
                    o = min(st(i), minov, prev_o)
                    smax = smax - o + fu(i)
                    prev_o = en(i)
                end do
            end do
            if (smax*sz >= s .or. no_ext .or. reps > 1000) exit
        end do

        ! The parts in order, and at each joint the overlap at most and
        ! how much of it may be given back.
        allocate (seq(n*(reps + 1)), joint(n*(reps + 1)), give(n*(reps + 1)))
        k = 0
        prev_o = 0.0_dp
        do i = 1, n
            m = 1
            if (ex(i)) m = reps
            do j = 1, m
                k = k + 1
                seq(k) = parts(i)
                o = min(st(i), prev_o)
                joint(k) = o
                give(k) = max(o - min(o, minov), 0.0_dp)
                prev_o = en(i)
            end do
        end do
        nj = k

        nat = 0.0_dp
        str = 0.0_dp
        do k = 1, nj
            call glyph_bbox(seq(k), x0, y0, x1, y1)
            if (vertical) then
                nat = nat + (y1 - y0) - joint(k)
            else
                nat = nat + glyph_adv(seq(k)) - joint(k)
            end if
            str = str + give(k)
        end do
        stretch = 0.0_dp
        if (s/sz > nat .and. str > 0.0_dp) stretch = min(s/sz - nat, str)/str

        box = empty_box()
        pos = 0.0_dp
        do k = 1, nj
            pos = pos - joint(k) + stretch*give(k)
            call glyph_bbox(seq(k), x0, y0, x1, y1)
            if (vertical) then
                call add_glyph(seq(k), 0.0_dp, (pos - y0)*sz, sz)
                pos = pos + (y1 - y0)
                box%w = max(box%w, glyph_adv(seq(k))*sz)
            else
                call add_glyph(seq(k), pos*sz, 0.0_dp, sz)
                pos = pos + glyph_adv(seq(k))
                box%h = max(box%h, y1*sz)
                box%d = max(box%d, -y0*sz)
            end if
        end do
        box%i1 = NI
        if (vertical) then
            box%h = pos*sz
            box%d = 0.0_dp
        else
            box%w = pos*sz
        end if
        box%ital = ic*sz
    end subroutine make_assembly

    ! TeX's spacing table, in mu. The parenthesised entries are the ones
    ! that exist only in display and text style; a script returns zero
    ! for those.
    pure function muskip(left, right, style) result(w)
        integer, intent(in) :: left, right, style
        real(dp) :: w
        integer :: kind
        logical :: text_only

        w = 0.0_dp
        kind = 0
        text_only = .false.
        select case (left)
        case (CL_ORD)
            select case (right)
            case (CL_OP); kind = 1
            case (CL_BIN); kind = 2; text_only = .true.
            case (CL_REL); kind = 3; text_only = .true.
            case (CL_INNER); kind = 1; text_only = .true.
            end select
        case (CL_OP)
            select case (right)
            case (CL_ORD, CL_OP); kind = 1
            case (CL_REL); kind = 3; text_only = .true.
            case (CL_INNER); kind = 1; text_only = .true.
            end select
        case (CL_BIN)
            select case (right)
            case (CL_ORD, CL_OP, CL_OPEN, CL_INNER)
                kind = 2
                text_only = .true.
            end select
        case (CL_REL)
            select case (right)
            case (CL_ORD, CL_OP, CL_OPEN, CL_INNER)
                kind = 3
                text_only = .true.
            end select
        case (CL_CLOSE)
            select case (right)
            case (CL_OP); kind = 1
            case (CL_BIN); kind = 2; text_only = .true.
            case (CL_REL); kind = 3; text_only = .true.
            case (CL_INNER); kind = 1; text_only = .true.
            end select
        case (CL_PUNCT)
            kind = 1
            text_only = .true.
        case (CL_INNER)
            select case (right)
            case (CL_OP); kind = 1
            case (CL_ORD, CL_OPEN, CL_PUNCT, CL_INNER)
                kind = 1
                text_only = .true.
            case (CL_BIN); kind = 2; text_only = .true.
            case (CL_REL); kind = 3; text_only = .true.
            end select
        end select
        if (kind == 0) return
        if (text_only .and. style > ST_T) return
        if (kind == 1) w = THIN
        if (kind == 2) w = MED
        if (kind == 3) w = THICK
    end function muskip
    ! ------------------------------------------------------------------
    ! Scanning
    ! ------------------------------------------------------------------

    ! The letters of the command that s starts with, without the backslash.
    pure function cmd_name(s) result(name)
        character(len=*), intent(in) :: s
        character(len=24) :: name
        integer :: j
        name = ""
        j = 2
        do while (j <= len(s))
            if (.not. is_alpha(s(j:j))) exit
            j = j + 1
        end do
        if (j > 2 .and. j - 2 <= len(name)) name = s(2:j - 1)
    end function cmd_name
    ! The k-th braced argument of a command, empty when there is no such
    ! argument. i0:i1 is the text inside the braces.
    pure subroutine cmd_arg(s, k, i0, i1)
        character(len=*), intent(in) :: s
        integer, intent(in) :: k
        integer, intent(out) :: i0, i1
        integer :: i, j, seen
        i0 = 1
        i1 = 0
        seen = 0
        i = 2
        do while (i <= len(s))
            if (s(i:i) == "{") then
                call group_end(s, i, j)
                seen = seen + 1
                if (seen == k) then
                    i0 = i + 1
                    i1 = j - 1
                    return
                end if
                i = j + 1
            else
                i = i + 1
            end if
        end do
    end subroutine cmd_arg
    ! The optional [argument] of a command, i0:i1 inside the brackets,
    ! empty when there is none.
    pure subroutine opt_arg(s, i0, i1)
        character(len=*), intent(in) :: s
        integer, intent(out) :: i0, i1
        integer :: j, k
        i0 = 1
        i1 = 0
        j = 2
        do while (j <= len(s))
            if (.not. is_alpha(s(j:j))) exit
            j = j + 1
        end do
        if (j > len(s)) return
        if (s(j:j) /= "[") return
        k = index(s(j:), "]")
        if (k == 0) return
        i0 = j + 1
        i1 = j + k - 2
    end subroutine opt_arg

    ! End of the group that starts at s(i:i) == "{".
    pure subroutine group_end(s, i, j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        integer, intent(out) :: j
        integer :: depth
        depth = 0
        do j = i, len(s)
            if (s(j:j) == BS) cycle
            if (j > 1) then
                if (s(j - 1:j - 1) == BS) cycle
            end if
            if (s(j:j) == "{") depth = depth + 1
            if (s(j:j) == "}") then
                depth = depth - 1
                if (depth == 0) return
            end if
        end do
        j = len(s)
    end subroutine group_end
    ! How many braced arguments a command takes.
    pure integer function cmd_nargs(name) result(n)
        character(len=*), intent(in) :: name
        integer :: code, cls
        logical :: wide
        select case (name)
        case ("frac", "dfrac", "tfrac", "cfrac", "binom", "dbinom", "tbinom")
            n = 2
        case ("sqrt", "overline", "underline", "mathrm", "mathup", "mathnormal", &
              "mathit", "mathbf", "mathbb", "mathcal", "mathscr", "mathsf", "text", &
              "textrm", "mbox", "textnormal", "operatorname")
            n = 1
        case ("quad", "qquad", "displaystyle", "textstyle", "scriptstyle", &
              "scriptscriptstyle", "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", &
              "arccos", "arctan", "sinh", "cosh", "tanh", "coth", "exp", "log", "ln", &
              "lg", "det", "dim", "ker", "hom", "arg", "deg", "gcd", "max", "min", &
              "sup", "inf", "lim", "liminf", "limsup", "Pr")
            n = 0
        case default
            call accent_code(name, code, wide)
            if (code > 0) then
                n = 1
            else
                call sym_lookup(name, code, cls)
                n = merge(0, -1, code > 0)
            end if
        end select
    end function cmd_nargs

    ! End of the command that starts at s(i:i) == "\": the backslash, its
    ! letters (or the one character after it), and its arguments: an
    ! optional [degree] for \sqrt and a * for \operatorname, and as many
    ! braced groups as it takes. A command not known to take any takes one
    ! group if one follows, so that \foo{x} sets x.
    pure subroutine command_end(s, i, j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        integer, intent(out) :: j
        integer :: k, a, nargs
        if (i + 1 > len(s)) then
            j = i
            return
        end if
        if (.not. is_alpha(s(i + 1:i + 1))) then
            j = i + 1
            return
        end if
        j = i + 1
        do while (j < len(s))
            if (.not. is_alpha(s(j + 1:j + 1))) exit
            j = j + 1
        end do
        nargs = cmd_nargs(s(i + 1:j))
        if (nargs == 0) return
        if (j < len(s)) then
            if (s(j + 1:j + 1) == "*") j = j + 1
        end if
        if (j < len(s)) then
            if (s(j + 1:j + 1) == "[") then
                k = index(s(j + 1:), "]")
                if (k > 0) j = j + k
            end if
        end if
        do a = 1, max(nargs, 1)
            k = j + 1
            do while (k <= len(s))
                if (s(k:k) /= " ") exit
                k = k + 1
            end do
            if (k > len(s)) exit
            if (s(k:k) /= "{") exit
            call group_end(s, k, j)
        end do
    end subroutine command_end

    ! End of the unit that starts at index i, for a script argument.
    pure subroutine unit_end(s, i, j)
        character(len=*), intent(in) :: s
        integer, intent(in) :: i
        integer, intent(out) :: j
        integer :: code, nb
        if (i > len(s)) then
            j = i - 1
        else if (s(i:i) == "{") then
            call group_end(s, i, j)
        else if (s(i:i) == BS) then
            call command_end(s, i, j)
        else
            call utf8_next(s, i, code, nb)
            j = i + nb - 1
        end if
    end subroutine unit_end

    pure function is_alpha(c) result(yes)
        character, intent(in) :: c
        logical :: yes
        yes = (c >= "a" .and. c <= "z") .or. (c >= "A" .and. c <= "Z")
    end function is_alpha
end module fplotlib_mathtext
