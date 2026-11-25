! Publication-style wrapped title and justified figure caption
! =============================================================
!
! Calling :f:subr:`textbox` with its default width (``0``) wraps text to
! the exact width of the axes, making multi-line titles, subtitles, and
! justified, hyphenated figure captions align flush with the plot frame.

program plot_publication_caption
    use fplotlib, only: axhline, axvline, dp, figure, grid, legend, plot, &
                        savefig, scatter, subplots_adjust, textbox, xlabel, &
                        xlim, ylabel, ylim
    implicit none

    integer, parameter :: nstep = 4000, nskip = 1500
    real(dp), parameter :: dt = 0.015_dp
    real(dp), parameter :: mus(3) = [0.2_dp, 1.0_dp, 2.5_dp]
    character(len=7), parameter :: cols(3) = ["#0f766e", "#2563eb", "#b91c1c"]
    character(len=16), parameter :: labs(3) = [ &
        "$\mu = 0.2$", "$\mu = 1.0$", "$\mu = 2.5$" ]
    character, parameter :: NL = achar(10)

    real(dp) :: x_lc(nstep - nskip + 1), v_lc(nstep - nskip + 1)
    real(dp) :: x_tr(900), v_tr(900)
    integer :: j

    call figure(figsize=[7.6_dp, 6.6_dp])
    call subplots_adjust(left=0.12_dp, right=0.95_dp, top=0.79_dp, bottom=0.28_dp)

    call axhline(0.0_dp, color="#cbd5e1", lw=0.8_dp)
    call axvline(0.0_dp, color="#cbd5e1", lw=0.8_dp)

    ! Spiral-in transient for mu = 1.0 from an interior initial condition.
    call integrate_vdp(1.0_dp, 0.25_dp, 0.0_dp, dt, 900, x_tr, v_tr)
    call plot(x_tr, v_tr, color="#93c5fd", lw=1.1_dp, linestyle="--", &
              label="Transient ($\mu = 1.0$)")

    ! Limit cycles for mu = 0.2, 1.0, 2.5.
    do j = 1, 3
        call vdp_limit_cycle(mus(j), dt, nstep, nskip, x_lc, v_lc)
        call plot(x_lc, v_lc, color=cols(j), lw=2.1_dp, label=trim(labs(j)))
    end do
    call scatter([0.0_dp], [0.0_dp], c="#1e293b", s=30.0_dp, &
                 label="Unstable origin")

    call xlim(-2.95_dp, 2.55_dp)
    call ylim(-5.1_dp, 5.4_dp)
    call xlabel("Displacement $x$")
    call ylabel("Velocity $\dot{x} = dx/dt$")
    call grid(.true., alpha=0.25_dp)
    call legend(loc="upper left", fontsize=8.2_dp)

    ! Full-axes-width wrapped title and subtitle.
    call textbox(0.0_dp, 1.04_dp, &
        "**Relaxation Oscillations and Limit Cycles of the Van der Pol Equation**"//NL//NL// &
        "*Phase-plane portraits $(x, \dot{x})$ illustrating the continuous transition "// &
        "from near-harmonic motion at $\mu = 0.2$ to stiff relaxation oscillations "// &
        "at $\mu = 2.5$.*", &
        coords="axes", ha="left", va="bottom", align="left", &
        fontsize=10.5_dp, color="#0f172a")

    ! Rich justified, hyphenated publication caption flush with axes edges.
    call textbox(0.0_dp, -0.21_dp, &
        "**Figure 1.** *Phase-plane limit cycles of the self-excited Van der Pol "// &
        "oscillator* $\ddot{x} - \mu(1 - x^2)\dot{x} + x = 0$ integrated via fourth-order "// &
        "Runge--Kutta for nonlinearity parameters $\mu \in \{0.2, 1.0, 2.5\}$. Every "// &
        "nonzero trajectory---such as the dashed interior transient starting at "// &
        "$(0.25, 0)$---is repelled by the unstable equilibrium at the origin and "// &
        "converges onto a unique attracting limit cycle of amplitude $A \approx 2$. "// &
        "Increasing $\mu$ sharpens the fast--slow separation along the cubic nullcline.", &
        coords="axes", ha="left", va="top", align="justify", &
        fontsize=8.6_dp, color="#334155")

    call savefig("publication_caption.svg")
    print *, "wrote publication_caption.svg"

contains

    subroutine vdp_step(mu, x, v, h)
        real(dp), intent(in) :: mu, h
        real(dp), intent(inout) :: x, v
        real(dp) :: k1x, k1v, k2x, k2v, k3x, k3v, k4x, k4v
        k1x = v
        k1v = mu*(1.0_dp - x*x)*v - x
        k2x = v + 0.5_dp*h*k1v
        k2v = mu*(1.0_dp - (x + 0.5_dp*h*k1x)**2)*k2x - (x + 0.5_dp*h*k1x)
        k3x = v + 0.5_dp*h*k2v
        k3v = mu*(1.0_dp - (x + 0.5_dp*h*k2x)**2)*k3x - (x + 0.5_dp*h*k2x)
        k4x = v + h*k3v
        k4v = mu*(1.0_dp - (x + h*k3x)**2)*k4x - (x + h*k3x)
        x = x + (h/6.0_dp)*(k1x + 2.0_dp*k2x + 2.0_dp*k3x + k4x)
        v = v + (h/6.0_dp)*(k1v + 2.0_dp*k2v + 2.0_dp*k3v + k4v)
    end subroutine vdp_step

    subroutine integrate_vdp(mu, x0, v0, h, n, xs, vs)
        real(dp), intent(in) :: mu, x0, v0, h
        integer, intent(in) :: n
        real(dp), intent(out) :: xs(n), vs(n)
        real(dp) :: x, v
        integer :: i
        x = x0
        v = v0
        do i = 1, n
            xs(i) = x
            vs(i) = v
            call vdp_step(mu, x, v, h)
        end do
    end subroutine integrate_vdp

    subroutine vdp_limit_cycle(mu, h, ntot, nskip, xs, vs)
        real(dp), intent(in) :: mu, h
        integer, intent(in) :: ntot, nskip
        real(dp), intent(out) :: xs(ntot - nskip + 1), vs(ntot - nskip + 1)
        real(dp) :: x, v
        integer :: i
        x = 2.0_dp
        v = 0.0_dp
        do i = 1, ntot
            if (i >= nskip) then
                xs(i - nskip + 1) = x
                vs(i - nskip + 1) = v
            end if
            call vdp_step(mu, x, v, h)
        end do
    end subroutine vdp_limit_cycle

end program plot_publication_caption
