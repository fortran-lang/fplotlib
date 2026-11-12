! Mathematical expressions
! ========================
!
! What fplotlib's mathtext lays out. A pair of ``$`` signs switches into
! math and back, and text outside them is set as ordinary text, in Lato.
! Math is set in Lete Sans Math, with TeX's layout (The TeXbook, Appendix
! G) and every dimension read from the font's OpenType MATH table, as
! XeTeX, LuaTeX and Typst do: the script sizes and their glyphs, the
! script shifts and kerns, fractions, roots, large operators, accents and
! the sizes of delimiters all come from the font.
!
! The commands are TeX's and LaTeX's (with amsmath), and a formula that
! works in LaTeX gives the same layout here: fplotlib's test suite checks
! it glyph by glyph against XeTeX. Matched delimiters also grow by
! themselves to fit what they enclose, as Typst's do, so ``\left`` and
! ``\right`` are rarely needed.
!
! The backslash in these strings is a real character. That is the default
! for gfortran, flang and ifx. A compiler that treats ``\`` as an escape
! wants ``\\`` in the literal, or the character ``achar(92)``.

program plot_mathtext_examples
    use fplotlib, only: axis, dp, figure, savefig, text
    implicit none

    real(dp) :: y

    call figure(figsize=[12.0_dp, 19.0_dp])
    call axis("off")
    y = 0.985_dp

! %%
! Scripts and primes. ``^`` and ``_`` raise and lower the next character,
! or the next group in braces, and the two scripts of one base can come in
! either order. A prime is a superscript, and ``f''`` is two of them.

    call sheet(y, "mixed with text", &
               "energy $E = mc^2$ at $T = 300\,\mathrm{K}$")
    call sheet(y, "scripts", &
               "$x^2$, $x_i$, $x_i^2$, $10^{-3} < T^2_n < 10^3$, $e^{-x^2}$")
    call sheet(y, "primes", "$f'(x)$, $f''(x)$, $y'^2$")

! %%
! Fractions, binomials and roots. ``\dfrac`` and ``\tfrac`` force the
! display and the text size, ``\cfrac`` makes a continued fraction, and
! ``\sqrt`` takes an optional degree.

    call sheet(y, "fractions", &
               "$\frac{3}{4}$, $\frac{1}{2\pi}$, $\dfrac{a}{b} \ne \tfrac{a}{b}$, $e^{-\frac{t}{\tau}}$")
    call sheet(y, "continued fraction", &
               "$x = a_0 + \cfrac{1}{a_1 + \cfrac{1}{a_2 + \cfrac{1}{a_3}}}$", 3.4_dp)
    call sheet(y, "binomials", "$\binom{n}{k} = \frac{n!}{k!\,(n-k)!}$", 1.3_dp)
    call sheet(y, "roots", &
               "$\sqrt{2}$, $\sqrt{x^2+y^2}$, $\sqrt[3]{x}$, $T = 2\pi\sqrt{\frac{L}{g}}$", 1.3_dp)

! %%
! Large operators. In a label they take their limits beside them, as in
! running text; ``\displaystyle`` sets them large, with the limits above
! and below. ``\limits`` and ``\nolimits`` choose either way.

    call sheet(y, "operators", &
               "$\sum_{i=1}^{n} x_i$, $\prod_{k} a_k$, $\int_0^\infty e^{-x}\,dx$, $\oint_C F \cdot dr$")
    call sheet(y, "display style", &
               "$\displaystyle\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$, $\displaystyle\int_0^1 x^2\,dx$", 2.6_dp)
    call sheet(y, "limits", "$\lim_{x \to 0} \frac{\sin x}{x} = 1$, $\max_{i} |x_i|$", 1.3_dp)

! %%
! Delimiters. Matched pairs grow to fit what they enclose, and a ``|``
! between them grows with them. Pairs that need not grow, unmatched
! delimiters, and the escaped ``\(`` ``\)`` ``\[`` ``\]`` keep their
! normal size. ``\left``, ``\middle`` and ``\right`` work as in TeX, and
! so do ``\big``, ``\Big``, ``\bigg`` and ``\Bigg``.

    call sheet(y, "automatic", &
               "$(\frac{a}{b})^2$, $\{x | x > \frac{1}{2}\}$, $|\frac{a}{b}|$, $\langle \frac{a}{b} \rangle$, $\lfloor \frac{n}{2} \rfloor$", 1.5_dp)
    call sheet(y, "normal size", "$f(x)$, $[0, 1)$, $\(\frac{a}{b}\)$, $|x|$", 1.3_dp)
    call sheet(y, "explicit", &
               "$\left[\frac{a}{b}\right)$, $\left. \frac{df}{dx} \right|_{x=0}$, $\Bigg(\bigg(\Big(\big(x\big)\Big)\bigg)\Bigg)$", 2.0_dp)

! %%
! Accents sit over the letter's own attachment point; the wide ones grow
! with what they cover. An i or a j under an accent loses its dot.

    call sheet(y, "accents", &
               "$\hat{x}$, $\bar{x}$, $\vec{v}$, $\tilde{a}$, $\dot{x}$, $\ddot{x}$, $\hat{i}$, $\widehat{xyz}$, $\overline{AB}$, $\underline{x}$")

! %%
! Alphabets, Greek and symbols. Letters in math are italic, digits and
! Greek capitals upright; the alphabet commands choose another.

    call sheet(y, "alphabets", &
               "$x\,\mathrm{x}\,\mathit{x}\,\mathbf{x}\,\mathsf{x}$, $\mathbb{R}^n$, $\mathcal{L}$, $\mathbf{F} = m\mathbf{a}$")
    call sheet(y, "lowercase Greek", &
               "$\alpha\ \beta\ \gamma\ \delta\ \epsilon\ \varepsilon\ \zeta\ \eta\ \theta\ \vartheta\ \iota\ \kappa\ \lambda\ \mu$")
    call sheet(y, "", &
               "$\nu\ \xi\ \pi\ \varpi\ \rho\ \varrho\ \sigma\ \varsigma\ \tau\ \upsilon\ \phi\ \varphi\ \chi\ \psi\ \omega$")
    call sheet(y, "uppercase Greek", &
               "$\Gamma\ \Delta\ \Theta\ \Lambda\ \Xi\ \Pi\ \Sigma\ \Upsilon\ \Phi\ \Psi\ \Omega$")
    call sheet(y, "operators", "$a \pm b \times c \cdot d \div e$, $A \cup B \cap C$, $p \wedge q$")
    call sheet(y, "relations", &
               "$a \le b \ne c \approx d \equiv e$, $x \in A \subseteq B$, $f \propto g$")
    call sheet(y, "arrows", &
               "$x \to \infty$, $A \Rightarrow B \iff C$, $x \mapsto x^2$, $\nabla \cdot \vec{E} = \frac{\rho}{\epsilon_0}$", 1.3_dp)

! %%
! Words. The named functions are set upright and spaced as operators;
! ``\operatorname`` makes another, and ``\text`` sets words in Lato.

    call sheet(y, "functions", &
               "$\sin(2\pi f t)$, $\cos\theta$, $\log x$, $\exp(-x)$, $\operatorname{erf}(x)$")
    call sheet(y, "text", "$|x| = x \text{ if } x \ge 0$")

! %%
! Space. The layout spaces symbols by their kind, as TeX does, and drops
! the spaces typed between them. ``\,``, ``\:``, ``\;`` and ``\!`` are
! thin, medium, thick and negative thin spaces, ``\quad`` and ``\qquad``
! one and two ems.

    call sheet(y, "spacing", "$ab$, $a b$, $a\,b$, $a\:b$, $a\;b$, $a\!b$, $a\quad b$, $a\qquad b$")

    call savefig("mathtext_examples.svg", bbox_inches="tight")
    print *, "wrote mathtext_examples.svg"

contains

    ! One row: a caption, and the formula at its right. A tall formula
    ! takes more than one row's height.
    subroutine sheet(y, caption, formula, rows)
        real(dp), intent(inout) :: y
        character(len=*), intent(in) :: caption, formula
        real(dp), intent(in), optional :: rows
        real(dp) :: h

        h = 1.0_dp
        if (present(rows)) h = rows
        y = y - 0.5_dp*(h - 1.0_dp)*0.03_dp
        if (len_trim(caption) > 0) then
            call text(0.0_dp, y, caption, fontsize=12.0_dp, ha="left", va="center", &
                      transform="axes", color="dimgray")
        end if
        call text(0.22_dp, y, formula, fontsize=15.0_dp, ha="left", va="center", &
                  transform="axes")
        y = y - (0.5_dp*(h - 1.0_dp) + 1.0_dp)*0.03_dp
    end subroutine sheet

end program plot_mathtext_examples
