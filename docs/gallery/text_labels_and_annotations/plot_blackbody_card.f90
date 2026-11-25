! Blackbody radiation with a typeset inset card
! ==============================================
!
! :f:subr:`textbox` places a full MyST Markdown block anywhere on a plot,
! laid out with Knuth--Plass line breaking, hyphenation, and TeX math.
! Here it renders a wrapped title and subtitle above the axes, a rounded
! derivation card inside the plot, and a justified figure caption below.

program plot_blackbody_card
    use fplotlib, only: axvspan, dp, figure, grid, legend, plot, savefig, &
                        scatter, subplots_adjust, text, textbox, xlabel, &
                        xlim, ylabel, ylim
    implicit none

    integer, parameter :: n = 500, nt = 3
    real(dp), parameter :: h_p = 6.62607015e-34_dp
    real(dp), parameter :: c_0 = 2.99792458e8_dp
    real(dp), parameter :: k_b = 1.380649e-23_dp
    real(dp), parameter :: b_wien = 2897.771955_dp
    real(dp), parameter :: temps(nt) = [6000.0_dp, 4500.0_dp, 3000.0_dp]
    character(len=7), parameter :: cols(nt) = ["#c0392b", "#d35400", "#2980b9"]
    character(len=28), parameter :: labs(nt) = [ &
        "$T = 6000\,\mathrm{K}$", &
        "$T = 4500\,\mathrm{K}$", &
        "$T = 3000\,\mathrm{K}$" ]
    character, parameter :: NL = achar(10)

    real(dp) :: lam(n), b_spec(n, nt), t_ridge(200), l_ridge(200), b_ridge(200)
    real(dp) :: pk_l(nt), pk_b(nt)
    integer :: i, j

    do i = 1, n
        lam(i) = 0.12_dp + 2.88_dp*real(i - 1, dp)/real(n - 1, dp)
        do j = 1, nt
            b_spec(i, j) = planck_kw(lam(i), temps(j))
        end do
    end do

    do i = 1, 200
        t_ridge(i) = 2400.0_dp + 4000.0_dp*real(i - 1, dp)/199.0_dp
        l_ridge(i) = b_wien/t_ridge(i)
        b_ridge(i) = planck_kw(l_ridge(i), t_ridge(i))
    end do

    do j = 1, nt
        pk_l(j) = b_wien/temps(j)
        pk_b(j) = planck_kw(pk_l(j), temps(j))
    end do

    call figure(figsize=[8.2_dp, 6.4_dp])
    call subplots_adjust(left=0.11_dp, right=0.96_dp, top=0.81_dp, bottom=0.25_dp)

    call axvspan(0.38_dp, 0.75_dp, color="#dceefb", alpha=0.55_dp)
    call text(0.565_dp, 35.6_dp, "Visible", ha="center", va="top", &
              fontsize=8.5_dp, color="#2c5282")

    do j = 1, nt
        call plot(lam, b_spec(:, j), color=cols(j), lw=2.2_dp, label=trim(labs(j)))
    end do
    call plot(l_ridge, b_ridge, color="#4a5568", linestyle="--", lw=1.3_dp, &
              label="Wien ridge $\lambda_{\max} T = b$")
    call scatter(pk_l, pk_b, c="#2d3748", s=32.0_dp)

    call xlim(0.1_dp, 3.0_dp)
    call ylim(0.0_dp, 36.8_dp)
    call xlabel("Wavelength $\lambda$ [$\mu\mathrm{m}$]")
    call ylabel("Spectral radiance $B_\lambda$ [$\mathrm{kW\,sr^{-1}\,m^{-2}\,nm^{-1}}$]")
    call grid(.true., alpha=0.25_dp)
    call legend(loc="lower right", fontsize=8.8_dp)

    ! Wrapped multi-line title and subtitle aligned to the axes width.
    call textbox(0.0_dp, 1.04_dp, &
        "**Planck's Blackbody Radiation Spectra and Wien's Displacement Law**"//NL//NL// &
        "*Equilibrium thermal emission across visible and near-infrared wavelengths "// &
        "for $T \in \{3000, 4500, 6000\}\,\mathrm{K}$, with the peak locus "// &
        "$\lambda_{\max} = b / T$.*", &
        coords="axes", ha="left", va="bottom", align="left", &
        fontsize=10.5_dp, color="#1a202c")

    ! Rounded inset derivation card in the open upper-right region.
    call textbox(0.97_dp, 0.95_dp, &
        "**Quantum Radiance Law**"//NL//NL// &
        "Quantizing cavity modes in units of $h\nu$ removes the classical "// &
        "ultraviolet divergence and yields the spectral radiance"//NL//NL// &
        "$$ B_\lambda(T) = \frac{2hc^2}{\lambda^5} "// &
        "\frac{1}{e^{hc/(\lambda k_B T)} - 1} $$"//NL//NL// &
        "- $6000\,\mathrm{K}$: $\lambda_{\max} = 0.48\,\mu\mathrm{m}$ (solar peak)"//NL// &
        "- $4500\,\mathrm{K}$: $\lambda_{\max} = 0.64\,\mu\mathrm{m}$ (red visible)"//NL// &
        "- $3000\,\mathrm{K}$: $\lambda_{\max} = 0.97\,\mu\mathrm{m}$ (near-IR)", &
        width=242.0_dp, coords="axes", ha="right", va="top", &
        fontsize=8.4_dp, align="justify", color="#1a202c", &
        facecolor="#f8fafc", edgecolor="#94a3b8", lw=0.9_dp, &
        alpha=0.95_dp, pad=8.0_dp, radius=5.0_dp)

    ! Justified figure caption beneath the axes.
    call textbox(0.0_dp, -0.22_dp, &
        "**Figure 1.** Spectral radiance $B_\lambda(T)$ of an ideal blackbody at three "// &
        "photospheric temperatures. The shaded band marks the visible spectrum "// &
        "($0.38$--$0.75\,\mu\mathrm{m}$), and the dashed curve traces Wien's displacement "// &
        "ridge $\lambda_{\max} T = 2898\,\mu\mathrm{m}\cdot\mathrm{K}$, where integrated "// &
        "emission scales as $\sigma T^4$ by the Stefan--Boltzmann law.", &
        coords="axes", ha="left", va="top", align="justify", &
        fontsize=8.6_dp, color="#334155")

    call savefig("blackbody_card.svg")
    print *, "wrote blackbody_card.svg"

contains

    ! Spectral radiance in kW / (sr * m^2 * nm) for wavelength lam_um in microns.
    pure real(dp) function planck_kw(lam_um, T) result(val)
        real(dp), intent(in) :: lam_um, T
        real(dp) :: lam_m, expo
        lam_m = lam_um*1.0e-6_dp
        expo = (h_p*c_0)/(lam_m*k_b*T)
        if (expo > 700.0_dp) then
            val = 0.0_dp
        else
            val = (2.0_dp*h_p*c_0*c_0)/(lam_m**5*(exp(expo) - 1.0_dp))*1.0e-12_dp
        end if
    end function planck_kw

end program plot_blackbody_card
