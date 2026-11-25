! A scientific report from Fortran
! ================================
!
! A single-page report built directly from Fortran using the immediate-mode
! report API: YAML front matter, prose with TeX mathematics, a vector plot
! containing a typeset Markdown inset card, a booktabs-styled numeric table,
! automatic cross-references (``{numref}``, ``{eq}``), and non-destructive
! export to both SVG and PDF.

program plot_hpc_report
    use fplotlib, only: dp, figure, plot, xlabel, ylabel, title, ylim, grid, &
                        legend, textbox, clf, markdown, include_figure, &
                        include_table, save
    implicit none

    integer, parameter :: N = 400, NSAMP = 5
    real(dp), parameter :: ALPHA = 0.15_dp, OMEGA = 2.0_dp
    real(dp) :: t(N), y(N), env(N), results(NSAMP, 4), ts
    integer :: i
    character, parameter :: NL = achar(10)

    do i = 1, N
        t(i) = 12.0_dp*real(i - 1, dp)/real(N - 1, dp)
        env(i) = exp(-ALPHA*t(i))
        y(i) = env(i)*cos(OMEGA*t(i))
    end do

    do i = 1, NSAMP
        ts = 2.0_dp*real(i - 1, dp)
        results(i, 1) = ts
        results(i, 2) = exp(-ALPHA*ts)*cos(OMEGA*ts)
        results(i, 3) = exp(-ALPHA*ts)
        results(i, 4) = exp(-2.0_dp*ALPHA*ts)
    end do

    call markdown([character(len=96) :: &
        "---", &
        "title: A Report Directly from Fortran", &
        "author: Numerical Methods Group", &
        "paper: letter", &
        "margin: 0.7in", &
        "numbersections: true", &
        "---", &
        "", &
        "# A Damped Oscillator", &
        "", &
        "A linear oscillator with angular frequency $\omega_0 = 2.0\;\mathrm{rad/s}$ and", &
        "damping rate $\alpha = 0.15\;\mathrm{s}^{-1}$ follows", &
        "$y(t) = e^{-\alpha t}\cos(\omega_0 t)$. Both the vector figure and the numerical", &
        "summary below are generated directly inside the simulation program without", &
        "intermediate files."])

    call figure(figsize=[5.6_dp, 2.45_dp])
    call plot(t, y, "C0-", lw=1.8_dp, label="$y(t) = e^{-\alpha t}\cos(\omega_0 t)$")
    call plot(t, env, "k--", lw=1.0_dp, alpha=0.55_dp, label="Envelope $\pm e^{-\alpha t}$")
    call plot(t, -env, "k--", lw=1.0_dp, alpha=0.55_dp)
    call xlabel("Time $t$ (s)")
    call ylabel("Displacement $y(t)$")
    call title("Underdamped Harmonic Response")
    call ylim(-1.15_dp, 1.15_dp)
    call grid(.true., alpha=0.3_dp)
    call legend(loc="upper right")
    call textbox(0.96_dp, 0.08_dp, &
                 "**Governing ODE**"//NL//NL// &
                 "$\ddot{y} + 2\alpha\dot{y} + (\omega_0^2 + \alpha^2)y = 0$"//NL//NL// &
                 "$\alpha = 0.15\;\mathrm{s}^{-1},\quad \omega_0 = 2.0\;\mathrm{rad/s}$", &
                 width=175.0_dp, coords="axes", ha="right", va="bottom", align="left", &
                 fontsize=8.0_dp, facecolor="#f8fafc", edgecolor="#94a3b8", pad=5.0_dp, &
                 radius=4.0_dp, alpha=0.94_dp)
    call include_figure(caption="Damped harmonic motion $y(t)$ with exponential decay envelope.", &
                        label="fig:motion", width="84%", bbox_inches="tight", pad_inches=0.05_dp)
    call clf()

    call include_table(results, &
                       columns=[character(len=20) :: "$t$ (s)", "$y(t)$", &
                                "$e^{-\alpha t}$", "$E(t)/E_0$"], &
                       caption="Sampled displacement, envelope, and normalized energy.", &
                       label="tab:values")

    call markdown([character(len=96) :: &
        "## Interpretation", &
        "", &
        "As shown in {numref}`fig:motion` and quantified in {numref}`tab:values`, the", &
        "oscillation amplitude decays monotonically within the exponential envelope. The", &
        "amplitude half-life is given by", &
        "$$ t_{1/2} = \frac{\ln 2}{\alpha} \approx 4.62\;\mathrm{s}, $$ (eq:halflife)", &
        "matching the drop from $1.000$ at $t = 0$ to $0.549$ at $t = 4.0\;\mathrm{s}$ in", &
        "{numref}`tab:values`. By $t = 8.0\;\mathrm{s}$, the stored energy $E(t)/E_0$ has fallen", &
        "to less than ten percent of its initial value, consistent with {eq}`eq:halflife`."])

    call save("hpc_report.svg")
    call save("hpc_report.pdf")
end program plot_hpc_report
