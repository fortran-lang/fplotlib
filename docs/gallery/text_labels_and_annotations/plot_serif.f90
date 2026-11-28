! Serif text and math: STIX Two
! =============================
!
! ``rc(fontfamily="serif")`` sets every label of the figures drawn after
! it in STIX Two Text and the math in them in STIX Two Math, a Times-like
! pair drawn to go together, so that a figure matches a paper set in
! Times or STIX: the letters of $x_i$ in a caption are the letters of
! $x_i$ in the plot. Like the default sans-serif pair, Lato and Lete Sans
! Math, both fonts are compiled into the library, and the math is laid
! out with TeX's rules from STIX Two Math's own MATH table: its script
! sizes and script-size glyphs, its italic corrections and math kerns
! (the subscript of $P_k$ tucks in under the P), and its delimiters.
! ``rc(fontfamily="sans-serif")`` or a ``style_use`` goes back to Lato.

program plot_serif
    use fplotlib, only: axis, dp, figure, fill_between, grid, legend, plot, rc, &
                        savefig, subplot, text, textbox, title, xlabel, ylabel, ylim
    implicit none

    integer, parameter :: n = 200
    character, parameter :: NL = achar(10)
    real(dp) :: t(n), y(n), env(n)
    integer :: i

    do i = 1, n
        t(i) = 6.0_dp*real(i - 1, dp)/real(n - 1, dp)
    end do
    env = exp(-0.4_dp*t)
    y = env*cos(2.0_dp*3.141592653589793_dp*t)

    call rc(fontfamily="serif")
    call figure(figsize=[9.0_dp, 4.2_dp])

! %%
! A plot as it would sit in a paper: the labels, the legend and the
! tick labels in STIX Two Text, the formulas in STIX Two Math.

    call subplot(1, 2, 1)
    call fill_between(t, -env, env, color="#dbeafe")
    call plot(t, y, "C0-", lw=1.4_dp, label="$x(t) = e^{-\gamma t}\cos(\omega_0 t)$")
    call plot(t, env, "C3--", lw=1.0_dp, label="$\pm e^{-\gamma t}$")
    call plot(t, -env, "C3--", lw=1.0_dp)
    call xlabel("time $t$ [s]")
    call ylabel("displacement $x(t)/x_0$")
    call title("Damped oscillator, $\gamma = 0.4\,\mathrm{s}^{-1}$")
    call ylim(-1.1_dp, 1.25_dp)
    call grid(.true., alpha=0.3_dp)
    call legend(loc="upper right", fontsize=8.5_dp)

! %%
! Larger formulas: fractions, roots, sums with limits, matched
! delimiters that grow with what they enclose, and a matrix.

    call subplot(1, 2, 2)
    call axis("off")
    call text(0.03_dp, 0.90_dp, "$\displaystyle E_n = -\frac{m_e e^4}{8 \varepsilon_0^2 h^2} \frac{1}{n^2}," &
              //"\quad x_{1,2} = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$", fontsize=11.0_dp, transform="axes")
    call text(0.03_dp, 0.71_dp, "$\displaystyle \zeta(s) = \sum_{n=1}^{\infty} \frac{1}{n^s}" &
              //" = \prod_{p} \left(1 - p^{-s}\right)^{-1}$", fontsize=11.0_dp, transform="axes")
    call text(0.03_dp, 0.52_dp, "$\displaystyle \oint_{\partial S} \mathbf{B} \cdot d\mathbf{l}" &
              //" = \mu_0 \int_S \mathbf{J} \cdot d\mathbf{A}$", fontsize=11.0_dp, transform="axes")
    call text(0.03_dp, 0.33_dp, "$R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\" &
              //" \sin\theta & \cos\theta \end{pmatrix}, \quad \hat{\mathbf{n}} \cdot" &
              //" \vec{v} = \|\vec{v}\| \cos\varphi$", fontsize=11.0_dp, transform="axes")
    call textbox(0.03_dp, 0.02_dp, "*Italic*, **bold** and $f'(x) = \lim_{h \to 0} " &
                 //"\frac{f(x+h) - f(x)}{h}$ in a typeset box, hyphenated and justified" &
                 //" like the rest of a paragraph.", width=240.0_dp, &
                 coords="axes", ha="left", va="bottom", fontsize=9.0_dp)
    call title("Mathtext in STIX Two Math")

    call savefig("plot_serif.svg")
    call rc(fontfamily="sans-serif")
end program plot_serif
