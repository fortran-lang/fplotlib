! Damped harmonic oscillator with an inset equation card
! =======================================================
!
! A damped oscillator figure pairing three dynamical regimes with a
! typeset Markdown card containing the governing ODE, a justified note
! on the characteristic discriminant, and a summary bullet list.

program plot_damped_oscillator_card
    use fplotlib, only: axhline, dp, figure, grid, legend, plot, savefig, &
                        subplots_adjust, textbox, xlabel, xlim, ylabel, ylim
    implicit none

    integer, parameter :: n = 500
    real(dp), parameter :: pi = 3.14159265358979323846_dp
    real(dp), parameter :: w0 = 2.0_dp*pi
    real(dp), parameter :: z_under = 0.15_dp, z_over = 2.5_dp
    character, parameter :: NL = achar(10)

    real(dp) :: t(n), x_under(n), x_crit(n), x_over(n), env(n)
    real(dp) :: wd, r1, r2
    integer :: i

    wd = w0*sqrt(1.0_dp - z_under*z_under)
    r1 = w0*(-z_over + sqrt(z_over*z_over - 1.0_dp))
    r2 = w0*(-z_over - sqrt(z_over*z_over - 1.0_dp))

    do i = 1, n
        t(i) = 2.6_dp*real(i - 1, dp)/real(n - 1, dp)
        env(i) = exp(-z_under*w0*t(i))
        x_under(i) = env(i)*(cos(wd*t(i)) + (z_under*w0/wd)*sin(wd*t(i)))
        x_crit(i) = (1.0_dp + w0*t(i))*exp(-w0*t(i))
        x_over(i) = (r2*exp(r1*t(i)) - r1*exp(r2*t(i)))/(r2 - r1)
    end do

    call figure(figsize=[8.2_dp, 6.4_dp])
    call subplots_adjust(left=0.11_dp, right=0.96_dp, top=0.81_dp, bottom=0.25_dp)

    call axhline(0.0_dp, color="#94a3b8", lw=0.8_dp)
    call plot(t, env, color="#94a3b8", linestyle="--", lw=1.1_dp, &
              label="Envelope $\pm e^{-\zeta\omega_0 t}$")
    call plot(t, -env, color="#94a3b8", linestyle="--", lw=1.1_dp)
    call plot(t, x_under, color="#2563eb", lw=2.1_dp, label="Underdamped ($\zeta = 0.15$)")
    call plot(t, x_crit, color="#dc2626", lw=2.1_dp, label="Critical ($\zeta = 1.0$)")
    call plot(t, x_over, color="#059669", lw=2.1_dp, label="Overdamped ($\zeta = 2.5$)")

    call xlim(0.0_dp, 2.6_dp)
    call ylim(-0.88_dp, 1.48_dp)
    call xlabel("Time $t / T_0$")
    call ylabel("Normalized displacement $x(t) / x_0$")
    call grid(.true., alpha=0.25_dp)
    call legend(loc="lower right", fontsize=8.5_dp)

    ! Wrapped title and subtitle aligned to the axes width.
    call textbox(0.0_dp, 1.04_dp, &
        "**Damped Harmonic Oscillator: Transient Response Regimes**"//NL//NL// &
        "*Free decay from $x(0) = 1$, $\dot{x}(0) = 0$ at natural frequency "// &
        "$\omega_0 = 2\pi / T_0$ across underdamped, critical, and overdamped motion.*", &
        coords="axes", ha="left", va="bottom", align="left", &
        fontsize=10.5_dp, color="#1a202c")

    ! Rounded inset Markdown card in the upper-right region.
    call textbox(0.975_dp, 0.96_dp, &
        "**Characteristic Equation**"//NL//NL// &
        "$$ \ddot{x} + 2\zeta\omega_0\dot{x} + \omega_0^2 x = 0 $$"//NL//NL// &
        "The roots $r_{\pm} = \omega_0(-\zeta \pm \sqrt{\Delta})$ depend on "// &
        "the dimensionless discriminant $\Delta = \zeta^2 - 1$:"//NL//NL// &
        "- $\zeta < 1$: oscillations at $\omega_d = \omega_0\sqrt{1-\zeta^2}$"//NL// &
        "- $\zeta = 1$: fastest non-oscillatory return"//NL// &
        "- $\zeta > 1$: two real exponential decay rates", &
        width=248.0_dp, coords="axes", ha="right", va="top", &
        fontsize=7.9_dp, align="justify", color="#1a202c", &
        facecolor="#fffbeb", edgecolor="#d97706", lw=0.9_dp, &
        alpha=0.95_dp, pad=7.0_dp, radius=5.0_dp)

    ! Justified figure caption beneath the axes.
    call textbox(0.0_dp, -0.22_dp, &
        "**Figure 1.** Comparison of free-response trajectories for a linear second-order "// &
        "oscillator released from rest. When $\zeta = 0.15$, the amplitude decays within "// &
        "the dashed envelope $\pm e^{-\zeta\omega_0 t}$; at $\zeta = 1.0$, the system "// &
        "settles most rapidly without overshoot, whereas $\zeta = 2.5$ exhibits sluggish "// &
        "relaxation governed by the slower root $r_+$.", &
        coords="axes", ha="left", va="top", align="justify", &
        fontsize=8.6_dp, color="#334155")

    call savefig("damped_oscillator_card.svg")
    print *, "wrote damped_oscillator_card.svg"

end program plot_damped_oscillator_card
