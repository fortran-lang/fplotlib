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
!     and optional scripts, fractions, radicals and explicit spaces;
!   * the list is turned into boxes in a style (display, text, script,
!     scriptscript, each possibly cramped), which decides the size and
!     which MATH constants apply;
!   * the boxes are set side by side with TeX's inter-atom glue.
!
! A box is a range of items in one arena (glyphs and rules, positioned
! relative to the box's origin, y up) together with its width, height and
! depth. Laying a sub-list out appends its items contiguously, so placing
! a box is moving its range. Nothing is truncated: the arenas grow.
!
! Text outside the dollar signs is set in Lato, as any other text.
module fplotlib_mathtext
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_render, only: glyphrun_t
    use fplotlib_text, only: text_layout, run_add
    use fplotlib_glyphs, only: glyph_cmap, glyph_adv, glyph_bbox, glyph_italic, &
                               glyph_variants, glyph_ssty, glyph_math_kern, &
                               math_const, math_percent, &
                               FACE_MATH, FACE_REGULAR
    use fplotlib_glyphs_data, only: MC_SCRIPT_PERCENT_SCALE_DOWN, &
                               MC_SCRIPT_SCRIPT_PERCENT_SCALE_DOWN, MC_AXIS_HEIGHT, &
                               MC_SUBSCRIPT_SHIFT_DOWN, MC_SUBSCRIPT_TOP_MAX, &
                               MC_SUBSCRIPT_BASELINE_DROP_MIN, MC_SUPERSCRIPT_SHIFT_UP, &
                               MC_SUPERSCRIPT_SHIFT_UP_CRAMPED, &
                               MC_SUPERSCRIPT_BOTTOM_MIN, &
                               MC_SUPERSCRIPT_BASELINE_DROP_MAX, &
                               MC_SUB_SUPERSCRIPT_GAP_MIN, &
                               MC_SUPERSCRIPT_BOTTOM_MAX_WITH_SUBSCRIPT, &
                               MC_SPACE_AFTER_SCRIPT, &
                               MC_FRACTION_NUMERATOR_SHIFT_UP, &
                               MC_FRACTION_NUMERATOR_DISPLAY_STYLE_SHIFT_UP, &
                               MC_FRACTION_DENOMINATOR_SHIFT_DOWN, &
                               MC_FRACTION_DENOMINATOR_DISPLAY_STYLE_SHIFT_DOWN, &
                               MC_FRACTION_NUMERATOR_GAP_MIN, &
                               MC_FRACTION_NUM_DISPLAY_STYLE_GAP_MIN, &
                               MC_FRACTION_RULE_THICKNESS, &
                               MC_FRACTION_DENOMINATOR_GAP_MIN, &
                               MC_FRACTION_DENOM_DISPLAY_STYLE_GAP_MIN, &
                               MC_RADICAL_VERTICAL_GAP, &
                               MC_RADICAL_DISPLAY_STYLE_VERTICAL_GAP, &
                               MC_RADICAL_RULE_THICKNESS, MC_RADICAL_EXTRA_ASCENDER
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

    ! Atom classes, in the order of TeX's spacing table. CL_NONE is "no
    ! atom yet", which is not a class: a binary operator in that position
    ! is set as ordinary, the way a leading minus is.
    integer, parameter :: CL_NONE = 0, CL_ORD = 1, CL_OP = 2, CL_BIN = 3, &
                          CL_REL = 4, CL_OPEN = 5, CL_CLOSE = 6, &
                          CL_PUNCT = 7, CL_INNER = 8

    ! What a noad is. An atom has a class; the rest are spaced as one.
    integer, parameter :: K_ATOM = 1, K_FRAC = 2, K_RAD = 3, K_SPACE = 4

    ! What a nucleus is.
    integer, parameter :: NUC_NONE = 0, NUC_CHAR = 1, NUC_LIST = 2, NUC_TEXT = 3

    ! Alphabets: what a letter typed in math becomes.
    integer, parameter :: ALPH_MATH = 0, ALPH_RM = 1

    ! TeX's math glue, in mu (an eighteenth of an em). \, and \; are the
    ! thin and thick spaces written by hand, \: the medium one.
    real(dp), parameter :: THIN = 3.0_dp, MED = 4.0_dp, THICK = 5.0_dp

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
        ! NUC_TEXT: the text, s(t0:t1) of the text pool.
        integer :: t0 = 1, t1 = 0
        ! The scripts' lists, -1 for none.
        integer :: sup = -1, sub = -1
        ! K_FRAC: numerator and denominator; K_RAD: the radicand.
        integer :: a = 0, b = 0
        ! K_SPACE: the width, in mu when mu is true and ems otherwise.
        real(dp) :: amount = 0.0_dp
        logical :: mu = .true.
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
    ! operator names among them.
    type(noad_t), allocatable :: NOADS(:)
    integer :: NN = 0
    character(len=:), allocatable :: TPOOL

    ! The items, glyphs (kind 1) and rules (kind 2). A glyph's (x, y) is
    ! its origin; a rule's is its bottom left corner.
    integer, allocatable :: IT_KIND(:), IT_GID(:)
    real(dp), allocatable :: IT_X(:), IT_Y(:), IT_S(:), IT_W(:), IT_H(:)
    integer :: NI = 0

contains

    ! Is there anything in this string for the mathtext engine to do?
    pure function math_is(s) result(yes)
        character(len=*), intent(in) :: s
        logical :: yes
        yes = index(s, "$") > 0
    end function math_is

    ! Width of a string in points, mathtext or not.
    function math_width(s, size) result(w)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size
        real(dp) :: w
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        call math_layout(s, size, run, rules, w)
    end function math_width

    ! Lay a string out: its glyphs are appended to run and its rules to
    ! rules, starting at the origin, and width is how far it reaches.
    ! Text outside the dollar signs is copied through as ordinary text.
    subroutine math_layout(s, size, run, rules, width)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size
        type(glyphrun_t), intent(inout) :: run
        type(mrules_t), intent(inout) :: rules
        real(dp), intent(out) :: width
        type(mbox_t) :: box
        integer :: i, j, head, k
        real(dp) :: pen, xnew

        pen = 0.0_dp
        i = 1
        do while (i <= len(s))
            if (s(i:i) == "$") then
                j = i + 1
                do while (j <= len(s))
                    if (s(j:j) == "$") exit
                    j = j + 1
                end do
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
                    j = j + 1
                end do
                call text_layout(s(i:j - 1), size, FACE_REGULAR, pen, 0.0_dp, run, xnew)
                pen = xnew
                i = j
            end if
        end do
        width = pen
    end subroutine math_layout

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

    ! A character as an ordinary-or-whatever atom, set in the math font.
    integer function char_noad(code, alph) result(k)
        integer, intent(in) :: code, alph
        integer :: c
        c = code
        ! A hyphen in math is a minus sign, as in TeX.
        if (c == iachar("-")) c = 8722
        k = new_noad(K_ATOM, char_class(c))
        NOADS(k)%nuc = NUC_CHAR
        NOADS(k)%cp = math_alphabet(c, alph)
        NOADS(k)%face = FACE_MATH
    end function char_noad

    ! An atom whose nucleus is a list. A list that is a single ordinary
    ! atom without scripts is that atom, as TeX simplifies a group, so
    ! that {x}^2 is set exactly as x^2.
    integer function list_noad(head, cls) result(k)
        integer, intent(in) :: head, cls
        if (head > 0 .and. cls == CL_ORD) then
            if (plain_ord(head)) then
                k = head
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

    ! The list s describes. Spaces are dropped, as TeX drops them: the
    ! glue between atoms comes from their classes.
    recursive function parse_list(s, alph) result(head)
        character(len=*), intent(in) :: s
        integer, intent(in) :: alph
        integer :: head, tail, cur, i, j, k, code, nb, sl

        head = 0
        tail = 0
        cur = 0
        i = 1
        do while (i <= len(s))
            select case (s(i:i))
            case (" ", achar(9))
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
                    if (NOADS(cur)%sup >= 0) then
                        cur = new_noad(K_ATOM, CL_ORD)
                        call append(head, tail, cur)
                    end if
                    NOADS(cur)%sup = sl
                else
                    if (NOADS(cur)%sub >= 0) then
                        cur = new_noad(K_ATOM, CL_ORD)
                        call append(head, tail, cur)
                    end if
                    NOADS(cur)%sub = sl
                end if
                i = j + 1
            case ("{")
                call group_end(s, i, j)
                k = list_noad(parse_list(s(i + 1:j - 1), alph), CL_ORD)
                call append(head, tail, k)
                cur = k
                i = j + 1
            case ("}")
                i = i + 1
            case (BS)
                call command_end(s, i, j)
                k = parse_command(s(i:j), alph)
                if (k > 0) then
                    call append(head, tail, k)
                    cur = k
                    if (NOADS(k)%kind == K_SPACE) cur = 0
                end if
                i = j + 1
            case default
                call utf8_next(s, i, code, nb)
                k = char_noad(code, alph)
                call append(head, tail, k)
                cur = k
                i = i + nb
            end select
        end do
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

    ! One command, as a noad; 0 when it makes nothing.
    recursive function parse_command(s, alph) result(k)
        character(len=*), intent(in) :: s
        integer, intent(in) :: alph
        integer :: k, j, code, a0, a1, b0, b1
        character(len=16) :: name

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
        case ("$", "{", "}", "%", "&", "#", "_")
            k = char_noad(iachar(s(2:2)), ALPH_RM)
            return
        end select

        name = cmd_name(s)
        select case (name)
        case ("quad")
            k = space_noad(1.0_dp, .false.)
            return
        case ("qquad")
            k = space_noad(2.0_dp, .false.)
            return
        case ("frac")
            call cmd_arg(s, 1, a0, a1)
            call cmd_arg(s, 2, b0, b1)
            k = new_noad(K_FRAC, CL_INNER)
            NOADS(k)%a = parse_list(s(a0:a1), alph)
            NOADS(k)%b = parse_list(s(b0:b1), alph)
            return
        case ("sqrt")
            call cmd_arg(s, 1, a0, a1)
            k = new_noad(K_RAD, CL_ORD)
            NOADS(k)%a = parse_list(s(a0:a1), alph)
            return
        case ("mathrm")
            call cmd_arg(s, 1, a0, a1)
            k = list_noad(parse_list(s(a0:a1), ALPH_RM), CL_ORD)
            return
        end select

        code = symbol_code(name)
        if (code > 0) then
            k = char_noad(code, alph)
            return
        end if

        ! Any other command with a group sets the group, so \hat{x} is x.
        ! A name with no group is an operator: \sin, \cos, \log.
        j = index(s, "{")
        if (j > 0) then
            k = list_noad(parse_list(s(j + 1:len(s) - 1), alph), CL_ORD)
        else
            k = new_noad(K_ATOM, CL_OP)
            NOADS(k)%nuc = NUC_TEXT
            NOADS(k)%t0 = len(TPOOL) + 1
            TPOOL = TPOOL//trim(name)
            NOADS(k)%t1 = len(TPOOL)
        end if
    end function parse_command

    integer function space_noad(amount, mu) result(k)
        real(dp), intent(in) :: amount
        logical, intent(in) :: mu
        k = new_noad(K_SPACE, CL_NONE)
        NOADS(k)%amount = amount
        NOADS(k)%mu = mu
    end function space_noad

    ! ------------------------------------------------------------------
    ! Characters
    ! ------------------------------------------------------------------

    ! The class of an atom made of one character.
    pure integer function char_class(code) result(c)
        integer, intent(in) :: code
        select case (code)
        case (iachar("+"), iachar("*"), 215, 177, 247, 8722, 8723, 8901, 8728)
            c = CL_BIN
        case (iachar("="), iachar("<"), iachar(">"), iachar(":"), &
              8804, 8805, 8800, 8776, 8764, 8801, 8594, 8592)
            c = CL_REL
        case (iachar("("), iachar("["), iachar("{"))
            c = CL_OPEN
        case (iachar(")"), iachar("]"), iachar("}"), iachar("!"), iachar("?"))
            c = CL_CLOSE
        case (iachar(","), iachar(";"))
            c = CL_PUNCT
        case default
            c = CL_ORD
        end select
    end function char_class

    ! The character a typed one is set as. In math, Latin letters and
    ! lowercase Greek are the math italic ones and everything else stands
    ! upright, which is TeX's convention; \mathrm keeps them all upright.
    pure integer function math_alphabet(code, alph) result(c)
        integer, intent(in) :: code, alph
        c = code
        if (alph /= ALPH_MATH) return
        if (code >= iachar("A") .and. code <= iachar("Z")) then
            c = 119860 + code - iachar("A")
        else if (code == iachar("h")) then
            ! Planck's constant stands in for the italic h, which is
            ! missing from the math italic block.
            c = 8462
        else if (code >= iachar("a") .and. code <= iachar("z")) then
            c = 119886 + code - iachar("a")
        else if (code >= 945 .and. code <= 969) then
            c = 120572 + code - 945
        else
            select case (code)
            case (1013); c = 120598     ! lunate epsilon
            case (977); c = 120599      ! theta symbol
            case (1008); c = 120600     ! kappa symbol
            case (981); c = 120601      ! phi symbol
            case (1009); c = 120602     ! rho symbol
            case (982); c = 120603      ! pi symbol
            end select
        end if
    end function math_alphabet

    ! The code point a symbol command stands for, 0 for none. The Greek
    ! letters follow TeX: \epsilon and \phi are the lunate and the
    ! stroked forms, and the var- forms the others.
    pure integer function symbol_code(name) result(code)
        character(len=*), intent(in) :: name
        select case (name)
        case ("alpha"); code = 945
        case ("beta"); code = 946
        case ("gamma"); code = 947
        case ("delta"); code = 948
        case ("epsilon"); code = 1013
        case ("varepsilon"); code = 949
        case ("zeta"); code = 950
        case ("eta"); code = 951
        case ("theta"); code = 952
        case ("vartheta"); code = 977
        case ("iota"); code = 953
        case ("kappa"); code = 954
        case ("varkappa"); code = 1008
        case ("lambda"); code = 955
        case ("mu"); code = 956
        case ("nu"); code = 957
        case ("xi"); code = 958
        case ("omicron"); code = 959
        case ("pi"); code = 960
        case ("varpi"); code = 982
        case ("rho"); code = 961
        case ("varrho"); code = 1009
        case ("sigma"); code = 963
        case ("varsigma"); code = 962
        case ("tau"); code = 964
        case ("upsilon"); code = 965
        case ("phi"); code = 981
        case ("varphi"); code = 966
        case ("chi"); code = 967
        case ("psi"); code = 968
        case ("omega"); code = 969
        case ("Gamma"); code = 915
        case ("Delta"); code = 916
        case ("Theta"); code = 920
        case ("Lambda"); code = 923
        case ("Xi"); code = 926
        case ("Pi"); code = 928
        case ("Sigma"); code = 931
        case ("Upsilon"); code = 933
        case ("Phi"); code = 934
        case ("Psi"); code = 936
        case ("Omega"); code = 937
        ! The multiplication sign, which log tick labels are written with.
        case ("times"); code = 215
        case default; code = 0
        end select
    end function symbol_code

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

    ! A list of noads as a box, in a style: TeX's mlist_to_hlist. The
    ! first pass turns every noad into a box and settles the classes; the
    ! second sets the boxes side by side with the glue between classes.
    recursive subroutine mlist_box(head, style, cramped, size, box)
        integer, intent(in) :: head, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t), allocatable :: bx(:)
        integer, allocatable :: cls(:), idx(:)
        integer :: n, k, q, prev
        real(dp) :: pen, sz, mu

        n = 0
        q = head
        do while (q > 0)
            n = n + 1
            q = NOADS(q)%next
        end do
        allocate (bx(n), cls(n), idx(n))
        box = empty_box()
        if (n == 0) return

        sz = style_size(style, size)
        mu = sz/18.0_dp
        q = head
        prev = 0
        do k = 1, n
            idx(k) = q
            cls(k) = NOADS(q)%cls
            select case (NOADS(q)%kind)
            case (K_SPACE)
                bx(k) = empty_box()
                if (NOADS(q)%mu) then
                    bx(k)%w = NOADS(q)%amount*mu
                else
                    bx(k)%w = NOADS(q)%amount*sz
                end if
            case (K_FRAC)
                call make_frac(q, style, cramped, size, bx(k))
            case (K_RAD)
                call make_rad(q, style, size, bx(k))
            case default
                ! A binary operator with nothing, or with an operator,
                ! relation, opening or punctuation before it, is ordinary;
                ! and so is one followed by a relation, closing or
                ! punctuation (rules 5 and 6).
                if (cls(k) == CL_BIN) then
                    if (prev == 0) then
                        cls(k) = CL_ORD
                    else if (any(cls(prev) == [CL_BIN, CL_OP, CL_REL, CL_OPEN, &
                                               CL_PUNCT])) then
                        cls(k) = CL_ORD
                    end if
                end if
                if (prev > 0) then
                    if (cls(prev) == CL_BIN .and. any(cls(k) == [CL_REL, CL_CLOSE, &
                                                               CL_PUNCT])) then
                        cls(prev) = CL_ORD
                    end if
                end if
                call make_atom(q, style, cramped, size, bx(k))
            end select
            if (NOADS(q)%kind /= K_SPACE) prev = k
            q = NOADS(q)%next
        end do
        ! A binary operator at the very end has nothing to operate on.
        if (prev > 0) then
            if (cls(prev) == CL_BIN) cls(prev) = CL_ORD
        end if

        pen = 0.0_dp
        prev = 0
        box%h = 0.0_dp
        box%d = 0.0_dp
        do k = 1, n
            if (NOADS(idx(k))%kind == K_SPACE) then
                pen = pen + bx(k)%w
                cycle
            end if
            if (prev > 0) pen = pen + muskip(cls(prev), cls(k), style)*mu
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

    ! An atom: its nucleus, and its scripts if it has any.
    recursive subroutine make_atom(q, style, cramped, size, box)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: g
        integer :: k, code, nb, i0
        real(dp) :: sz, pen

        sz = style_size(style, size)
        select case (NOADS(q)%nuc)
        case (NUC_CHAR)
            call glyph_box(script_glyph(math_gid(NOADS(q)%cp, NOADS(q)%face), style), &
                           sz, box)
            box%kgid = math_gid(NOADS(q)%cp, NOADS(q)%face)
            ! TeX's rule for a character of a math font: its italic
            ! correction is part of its width unless a subscript is going
            ! to tuck in under it.
            if (NOADS(q)%sub < 0) then
                box%w = box%w + box%ital
                box%ital = 0.0_dp
            end if
        case (NUC_LIST)
            call mlist_box(NOADS(q)%list, style, cramped, size, box)
        case (NUC_TEXT)
            ! An operator name, upright, its letters side by side.
            box = empty_box()
            i0 = NI + 1
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
            box%i0 = i0
            box%i1 = NI
            box%w = pen
            box%gid = 0
        case default
            box = empty_box()
        end select
        if (NOADS(q)%sup >= 0 .or. NOADS(q)%sub >= 0) then
            call make_scripts(q, style, cramped, size, box)
        end if
    end subroutine make_atom

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

    ! \frac{a}{b} (rule 15, with the MATH table's constants): the halves
    ! one style down, the denominator cramped, each centred over the rule,
    ! which sits on the axis. Each half is moved out until it clears the
    ! rule by the minimum gap. A null delimiter's space is left on either
    ! side, as TeX leaves it.
    recursive subroutine make_frac(q, style, cramped, size, box)
        integer, intent(in) :: q, style
        logical, intent(in) :: cramped
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: num, den
        real(dp) :: sz, u, v, a, th, phi_n, phi_d, w, nds
        integer :: i0

        sz = style_size(style, size)
        nds = 0.12_dp*size
        i0 = NI + 1
        call mlist_box(NOADS(q)%a, frac_style(style), cramped, size, num)
        call mlist_box(NOADS(q)%b, frac_style(style), .true., size, den)
        a = math_const(MC_AXIS_HEIGHT)*sz
        th = math_const(MC_FRACTION_RULE_THICKNESS)*sz
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

        w = max(num%w, den%w)
        call move_box(num, nds + 0.5_dp*(w - num%w), u)
        call move_box(den, nds + 0.5_dp*(w - den%w), -v)
        call add_rule(nds, a - 0.5_dp*th, w, th)
        box%i0 = i0
        box%i1 = NI
        box%w = w + 2.0_dp*nds
        box%h = max(u + num%h, a + 0.5_dp*th)
        box%d = max(v + den%d, -(a - 0.5_dp*th))
    end subroutine make_frac

    ! \sqrt{a} (rule 11, with the MATH table's constants): the radicand in
    ! the same style, cramped; the smallest variant of the radical sign
    ! that covers it with the gap and the rule above; any height the sign
    ! has to spare split evenly above and below; and the rule along the
    ! top of the sign, with the extra ascender above it.
    recursive subroutine make_rad(q, style, size, box)
        integer, intent(in) :: q, style
        real(dp), intent(in) :: size
        type(mbox_t), intent(out) :: box
        type(mbox_t) :: x, sign
        integer, allocatable :: vg(:)
        real(dp), allocatable :: va(:)
        real(dp) :: sz, th, phi, need, x0, y0, x1, y1, hg, dg, extra, rise
        integer :: nvar, k, g, i0

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
        call glyph_variants(g, .true., nvar, vg, va)
        do k = 1, nvar
            g = vg(k)
            if (va(k)*sz >= need) exit
        end do
        call glyph_bbox(g, x0, y0, x1, y1)
        hg = y1*sz
        dg = -y0*sz
        extra = (hg + dg) - need
        if (extra > 0.0_dp) phi = phi + 0.5_dp*extra
        ! The top of the sign is where the rule's top goes.
        rise = x%h + phi + th - hg
        call glyph_box(g, sz, sign)
        call move_box(sign, 0.0_dp, rise)
        call move_box(x, sign%w, 0.0_dp)
        call to_front(x%i0, sign%i0, sign%i1)
        call add_rule(sign%w, x%h + phi, x%w, th)
        box%i0 = i0
        box%i1 = NI
        box%w = sign%w + x%w
        box%h = x%h + phi + th + math_const(MC_RADICAL_EXTRA_ASCENDER)*sz
        box%d = max(x%d, dg - rise)
    end subroutine make_rad

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
        character(len=16) :: name
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

    ! End of the command that starts at s(i:i) == "\". A command is the
    ! backslash plus its letters, plus a braced argument if there is one.
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
        ! One braced argument, or two for the commands that take two.
        nargs = 1
        if (s(i + 1:j) == "frac") nargs = 2
        do a = 1, nargs
            if (j >= len(s)) exit
            if (s(j + 1:j + 1) /= "{") exit
            call group_end(s, j + 1, k)
            j = k
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
