! Aerodynamic regime map with typeset Markdown callout boxes
! ===========================================================
!
! Multiple compact :f:subr:`textbox` callouts placed in distinct regions
! of a 2D log--log phase plane, each pairing a bold heading, a short
! justified description, and an asymptotic scaling law in TeX math.

program plot_regime_map
    use fplotlib, only: annotate, dp, figure, fill_between, grid, loglog, &
                        plot, savefig, set_xscale, set_yscale, &
                        subplots_adjust, text, textbox, xlabel, xlim, &
                        ylabel, ylim
    implicit none

    integer, parameter :: n = 200
    real(dp), parameter :: re_min = 1.0e1_dp, re_max = 1.0e8_dp
    real(dp), parameter :: ma_min = 0.04_dp, ma_max = 28.0_dp
    character, parameter :: NL = achar(10)

    real(dp) :: re(n), ma_kn01(n), ma_kn1(n), ma_top(n), ma_bot(n)
    real(dp) :: re_t(2), ma_t(2), re_s(2), ma_s(2), re_h(2), ma_h(2)
    integer :: i

    do i = 1, n
        re(i) = 10.0_dp**(1.0_dp + 7.0_dp*real(i - 1, dp)/real(n - 1, dp))
        ! Continuum breakdown Kn ~ 1.5 * Ma / Re
        ma_kn01(i) = min(ma_max, (0.01_dp/1.5_dp)*re(i))
        ma_kn1(i) = min(ma_max, (0.1_dp/1.5_dp)*re(i))
        ma_top(i) = ma_max
        ma_bot(i) = ma_min
    end do
    re_t = [5.0e5_dp, 5.0e5_dp]
    ma_t = [ma_min, 1.0_dp]
    ! Sonic (Ma = 1) and hypersonic (Ma = 5) boundaries in the continuum region.
    re_s = [1.5e2_dp, re_max]
    ma_s = [1.0_dp, 1.0_dp]
    re_h = [7.5e2_dp, re_max]
    ma_h = [5.0_dp, 5.0_dp]

    call figure(figsize=[8.6_dp, 6.6_dp])
    call subplots_adjust(left=0.11_dp, right=0.96_dp, top=0.81_dp, bottom=0.24_dp)

    ! Subtle region shading across the Ma-Re plane.
    call fill_between(re, ma_kn01, ma_top, color="#fef3c7", alpha=0.55_dp)
    call fill_between(re, ma_bot, ma_kn01, color="#eff6ff", alpha=0.45_dp)

    ! Regime boundary curves.
    call loglog(re, ma_kn01, "-", color="#b45309", lw=1.8_dp)
    call loglog(re, ma_kn1, ":", color="#d97706", lw=1.2_dp)
    call plot(re_s, ma_s, "--", color="#dc2626", lw=1.5_dp)
    call plot(re_h, ma_h, "-.", color="#7c3aed", lw=1.2_dp)
    call plot(re_t, ma_t, "--", color="#0f766e", lw=1.5_dp)

    ! Compact boundary labels.
    call text(1.2e7_dp, 1.18_dp, "Sonic ($\mathrm{Ma} = 1$)", &
              ha="center", va="bottom", fontsize=7.8_dp, color="#b91c1c")
    call text(1.2e4_dp, 5.7_dp, "Hypersonic ($\mathrm{Ma} = 5$)", &
              ha="center", va="bottom", fontsize=7.8_dp, color="#6d28d9")
    call text(9.0e5_dp, 0.055_dp, "$\mathrm{Re}_c \approx 5\times 10^5$", &
              ha="left", va="bottom", fontsize=7.8_dp, color="#0f766e")

    call set_xscale("log")
    call set_yscale("log")
    call xlim(re_min, re_max)
    call ylim(ma_min, ma_max)
    call xlabel("Reynolds number $\mathrm{Re} = \rho U L / \mu$")
    call ylabel("Mach number $\mathrm{Ma} = U / c$")
    call grid(.true., which="major", alpha=0.25_dp)

    ! Wrapped title and subtitle aligned to the axes width.
    call textbox(0.0_dp, 1.04_dp, &
        "**Compressible Aerodynamic Flow Regimes in the $(\mathrm{Re}, \mathrm{Ma})$ Plane**" &
        //NL//NL// &
        "*Asymptotic boundaries separating rarefied gas dynamics ($\mathrm{Kn} > 0.01$), "// &
        "subsonic viscous boundary layers, and supersonic shock-dominated flow.*", &
        coords="axes", ha="left", va="bottom", align="left", &
        fontsize=10.3_dp, color="#0f172a")

    ! Callout 1: Rarefied / Slip Flow (upper-left, above Kn = 0.01).
    call textbox(0.025_dp, 0.96_dp, &
        "**Rarefied & Slip Flow**"//NL//NL// &
        "Mean free path rivals body scale; continuum theory fails "// &
        "above $\mathrm{Kn} = 0.01$."//NL//NL// &
        "$$\mathrm{Kn} \approx 1.5\,\mathrm{Ma}/\mathrm{Re}$$", &
        width=164.0_dp, coords="axes", ha="left", va="top", &
        fontsize=7.7_dp, align="justify", color="#451a03", &
        facecolor="#fffbeb", edgecolor="#d97706", lw=0.9_dp, &
        alpha=0.96_dp, pad=6.0_dp, radius=4.0_dp)
    call annotate("", 90.0_dp, 0.85_dp, xtext=70.0_dp, ytext=4.2_dp, &
                  arrowstyle="->", arrowcolor="#b45309", arrowlw=1.2_dp)

    ! Callout 2: Supersonic / Hypersonic Continuum (upper-right, above Ma = 5).
    call textbox(0.975_dp, 0.96_dp, &
        "**Supersonic Continuum**"//NL//NL// &
        "Compressibility dominates for $\mathrm{Ma} > 1$; oblique shocks "// &
        "govern wave drag."//NL//NL// &
        "$$C_p \sim \frac{2\theta}{\sqrt{\mathrm{Ma}^2 - 1}}$$", &
        width=168.0_dp, coords="axes", ha="right", va="top", &
        fontsize=7.7_dp, align="justify", color="#3b0764", &
        facecolor="#faf5ff", edgecolor="#7c3aed", lw=0.9_dp, &
        alpha=0.96_dp, pad=6.0_dp, radius=4.0_dp)
    call annotate("", 1.2e6_dp, 2.2_dp, xtext=1.8e6_dp, ytext=4.6_dp, &
                  arrowstyle="->", arrowcolor="#7c3aed", arrowlw=1.2_dp)

    ! Callout 3: Subsonic Boundary Layers (bottom-center-left, clear of Re_c line).
    call textbox(0.39_dp, 0.05_dp, &
        "**Incompressible Viscous Flow**"//NL//NL// &
        "For $\mathrm{Ma} < 0.3$, density is nearly constant; Blasius "// &
        "layers transition at $\mathrm{Re}_c$:"//NL//NL// &
        "$$C_f \propto \mathrm{Re}^{-1/2} \;\to\; \mathrm{Re}^{-1/5}$$", &
        width=182.0_dp, coords="axes", ha="center", va="bottom", &
        fontsize=7.7_dp, align="justify", color="#0f172a", &
        facecolor="#f0fdfa", edgecolor="#0f766e", lw=0.9_dp, &
        alpha=0.96_dp, pad=6.0_dp, radius=4.0_dp)
    call annotate("", 4.6e5_dp, 0.22_dp, xtext=9.5e4_dp, ytext=0.22_dp, &
                  arrowstyle="->", arrowcolor="#0f766e", arrowlw=1.2_dp)

    ! Justified figure caption beneath the axes.
    call textbox(0.0_dp, -0.22_dp, &
        "**Figure 1.** Canonical aerodynamic regimes spanned by Reynolds number "// &
        "$\mathrm{Re}$ and Mach number $\mathrm{Ma}$. Solid and dotted amber lines mark "// &
        "Knudsen numbers $\mathrm{Kn} = 0.01$ and $0.1$; dashed crimson and dash-dotted "// &
        "violet lines denote sonic ($\mathrm{Ma} = 1$) and hypersonic ($\mathrm{Ma} = 5$) "// &
        "thresholds, while the vertical teal line indicates boundary-layer transition.", &
        coords="axes", ha="left", va="top", align="justify", &
        fontsize=8.5_dp, color="#334155")

    call savefig("regime_map.svg")
    print *, "wrote regime_map.svg"

end program plot_regime_map
