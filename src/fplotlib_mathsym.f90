! fplotlib_mathsym -- the math symbols mathtext knows by name.
!
! Every command that stands for one character, with the character it is
! set as and the atom class TeX gives it (ordinary, large operator,
! binary operator, relation, opening, closing, punctuation). A character
! typed directly, as UTF-8, gets the class of the command that stands for
! it, so "a ≤ b" is spaced exactly as "a \leq b".
!
! The names are TeX's and unicode-math's; the classes follow plain TeX
! and unicode-math.
module fplotlib_mathsym
    implicit none
    private

    public :: sym_lookup, sym_class
    public :: CL_ORD, CL_OP, CL_BIN, CL_REL, CL_OPEN, CL_CLOSE, CL_PUNCT, CL_INNER

    integer, parameter :: CL_ORD = 1, CL_OP = 2, CL_BIN = 3, CL_REL = 4, &
                          CL_OPEN = 5, CL_CLOSE = 6, CL_PUNCT = 7, CL_INNER = 8

    integer, parameter :: NSYM = 207
    integer, parameter :: O = CL_ORD, L = CL_OP, B = CL_BIN, R = CL_REL, &
                          OP = CL_OPEN, CL = CL_CLOSE, P = CL_PUNCT

    character(len=18), parameter :: NAMES(NSYM) = [character(len=18) :: &
        ! Greek, lowercase and the variant forms. \epsilon and \phi are the
        ! lunate and the stroked forms, as in TeX.
        "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", &
        "eta", "theta", "vartheta", "iota", "kappa", "varkappa", "lambda", "mu", &
        "nu", "xi", "omicron", "pi", "varpi", "rho", "varrho", "sigma", &
        "varsigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega", &
        ! Greek, uppercase.
        "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", &
        "Phi", "Psi", "Omega", &
        ! Ordinary symbols.
        "infty", "partial", "nabla", "hbar", "ell", "Re", "Im", "aleph", &
        "emptyset", "varnothing", "forall", "exists", "nexists", "neg", "lnot", &
        "prime", "angle", "triangle", "bot", "top", "ldots", "dots", "cdots", &
        "vdots", "ddots", "imath", "jmath", "backslash", "vert", "Vert", &
        "degree", "surd", "therefore", "because", &
        ! Binary operators.
        "pm", "mp", "times", "div", "cdot", "ast", "star", "circ", "bullet", &
        "cap", "cup", "uplus", "sqcap", "sqcup", "vee", "lor", "wedge", "land", &
        "setminus", "oplus", "ominus", "otimes", "oslash", "odot", "diamond", &
        "dagger", "ddagger", &
        ! Relations.
        "leq", "le", "geq", "ge", "neq", "ne", "equiv", "approx", "sim", &
        "simeq", "cong", "propto", "ll", "gg", "prec", "succ", "preceq", &
        "succeq", "subset", "supset", "subseteq", "supseteq", "in", "notin", &
        "ni", "owns", "mid", "nmid", "parallel", "nparallel", "perp", "vdash", &
        "dashv", "doteq", "coloneqq", "asymp", "leqslant", "geqslant", &
        "lesssim", "gtrsim", "triangleq", "leqq", "geqq", "colon", &
        ! Arrows, which are relations.
        "to", "rightarrow", "leftarrow", "gets", "leftrightarrow", &
        "Rightarrow", "Leftarrow", "Leftrightarrow", "implies", "impliedby", &
        "iff", "mapsto", "longrightarrow", "longleftarrow", &
        "longleftrightarrow", "Longrightarrow", "Longleftarrow", &
        "Longleftrightarrow", "longmapsto", "uparrow", "downarrow", &
        "updownarrow", "Uparrow", "Downarrow", "nearrow", "searrow", "swarrow", &
        "nwarrow", &
        ! Large operators.
        "sum", "prod", "coprod", "int", "iint", "iiint", "oint", "bigcup", &
        "bigcap", "bigvee", "bigwedge", "bigoplus", "bigotimes", "bigodot", &
        "biguplus", "bigsqcup", &
        ! Delimiters.
        "langle", "rangle", "lfloor", "rfloor", "lceil", "rceil", "lbrace", &
        "rbrace", "lbrack", "rbrack", "lvert", "rvert", "lVert", "rVert", &
        ! Punctuation.
        "ldotp", "cdotp"]

    integer, parameter :: CODES(NSYM) = [ &
        945, 946, 947, 948, 1013, 949, 950, &
        951, 952, 977, 953, 954, 1008, 955, 956, &
        957, 958, 959, 960, 982, 961, 1009, 963, &
        962, 964, 965, 981, 966, 967, 968, 969, &
        915, 916, 920, 923, 926, 928, 931, 933, &
        934, 936, 937, &
        8734, 8706, 8711, 8463, 8467, 8476, 8465, 8501, &
        8709, 8709, 8704, 8707, 8708, 172, 172, &
        8242, 8736, 9651, 8869, 8868, 8230, 8230, 8943, &
        8942, 8945, 120484, 120485, 92, 124, 8214, &
        176, 8730, 8756, 8757, &
        177, 8723, 215, 247, 8901, 8727, 8902, 8728, 8729, &
        8745, 8746, 8846, 8851, 8852, 8744, 8744, 8743, 8743, &
        8726, 8853, 8854, 8855, 8856, 8857, 8900, &
        8224, 8225, &
        8804, 8804, 8805, 8805, 8800, 8800, 8801, 8776, 8764, &
        8771, 8773, 8733, 8810, 8811, 8826, 8827, 10927, &
        10928, 8834, 8835, 8838, 8839, 8712, 8713, &
        8715, 8715, 8739, 8740, 8741, 8742, 8869, 8866, &
        8867, 8784, 8788, 8781, 10877, 10878, &
        8818, 8819, 8796, 8806, 8807, 58, &
        8594, 8594, 8592, 8592, 8596, &
        8658, 8656, 8660, 10233, 10232, &
        10234, 8614, 10230, 10229, &
        10231, 10233, 10232, &
        10234, 10236, 8593, 8595, &
        8597, 8657, 8659, 8599, 8600, 8601, &
        8598, &
        8721, 8719, 8720, 8747, 8748, 8749, 8750, 8899, &
        8898, 8897, 8896, 10753, 10754, 10752, &
        10756, 10758, &
        10216, 10217, 8970, 8971, 8968, 8969, 123, &
        125, 91, 93, 124, 124, 8214, 8214, &
        46, 8901]

    integer, parameter :: CLASSES(NSYM) = [ &
        O, O, O, O, O, O, O, &
        O, O, O, O, O, O, O, O, &
        O, O, O, O, O, O, O, O, &
        O, O, O, O, O, O, O, O, &
        O, O, O, O, O, O, O, O, &
        O, O, O, &
        O, O, O, O, O, O, O, O, &
        O, O, O, O, O, O, O, &
        O, O, O, O, O, O, O, O, &
        O, O, O, O, O, O, O, &
        O, O, R, R, &
        B, B, B, B, B, B, B, B, B, &
        B, B, B, B, B, B, B, B, B, &
        B, B, B, B, B, B, B, &
        B, B, &
        R, R, R, R, R, R, R, R, R, &
        R, R, R, R, R, R, R, R, &
        R, R, R, R, R, R, R, &
        R, R, R, R, R, R, R, R, &
        R, R, R, R, R, R, &
        R, R, R, R, R, P, &
        R, R, R, R, R, &
        R, R, R, R, R, &
        R, R, R, R, &
        R, R, R, &
        R, R, R, R, &
        R, R, R, R, R, R, &
        R, &
        L, L, L, L, L, L, L, L, &
        L, L, L, L, L, L, &
        L, L, &
        OP, CL, OP, CL, OP, CL, OP, &
        CL, OP, CL, OP, CL, OP, CL, &
        P, P]

contains

    ! The character and class a command name stands for; code is 0 when
    ! the name is not a symbol.
    pure subroutine sym_lookup(name, code, cls)
        character(len=*), intent(in) :: name
        integer, intent(out) :: code, cls
        integer :: i
        code = 0
        cls = CL_ORD
        do i = 1, NSYM
            if (NAMES(i) == name) then
                code = CODES(i)
                cls = CLASSES(i)
                return
            end if
        end do
    end subroutine sym_lookup

    ! The class of a character typed into a formula: that of the command
    ! that stands for it, or TeX's for the ASCII characters it gives a
    ! class of their own.
    pure integer function sym_class(code) result(cls)
        integer, intent(in) :: code
        integer :: i
        select case (code)
        case (iachar("+"), iachar("-"), iachar("*"), 8722)
            cls = CL_BIN
            return
        case (iachar("="), iachar("<"), iachar(">"), iachar(":"))
            cls = CL_REL
            return
        case (iachar("("), iachar("["))
            cls = CL_OPEN
            return
        case (iachar(")"), iachar("]"), iachar("!"), iachar("?"))
            cls = CL_CLOSE
            return
        case (iachar(","), iachar(";"))
            cls = CL_PUNCT
            return
        case (iachar("{"), iachar("}"), iachar("|"), iachar("."), iachar("/"))
            cls = CL_ORD
            return
        end select
        cls = CL_ORD
        do i = 1, NSYM
            if (CODES(i) == code) then
                cls = CLASSES(i)
                return
            end if
        end do
    end function sym_class

end module fplotlib_mathsym
