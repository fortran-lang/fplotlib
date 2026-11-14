! A report directly from a simulation
! ===================================
!
! The immediate-style API follows the program's order: append Markdown,
! make a plot, capture it, insert numerical results, and save. No report
! object, layout context, recorder or intermediate image file is needed.
!
! Calls build an owned document description. Layout happens on export and
! is reused until the content changes. Clearing the current figure after
! ``include_figure`` cannot change the captured plot.
!
! For explicit contexts and frame composition, see the advanced composition
! example alongside this one.
program plot_hpc_report
    use fplotlib, only: dp, markdown, figure, plot, title, xlabel, ylabel, ylim, grid, &
                        include_figure, include_table, clf, save
    implicit none
    real(dp) :: time(401), displacement(401), results(5, 3)
    integer :: i, k

    do i = 1, size(time)
        time(i) = 20.0_dp*real(i - 1, dp)/real(size(time) - 1, dp)
        displacement(i) = exp(-0.15_dp*time(i))*cos(2.0_dp*time(i))
    end do
    do i = 1, size(results, 1)
        k = 1 + (i - 1)*100
        results(i, :) = [time(k), displacement(k), exp(-0.15_dp*time(k))]
    end do

    call markdown([character(len=100) :: &
        "---", &
        "title: A Report Directly from Fortran", &
        "authors: Numerical methods group", &
        "exports:", &
        "  - format: pdf", &
        "    template: article", &
        "    paper: letter", &
        "    margin: 0.7in", &
        "---", &
        "", &
        "# A damped oscillator", &
        "", &
        "The simulation produces a trajectory, a vector plot, and numerical results.", &
        "They go directly into this report, without a separate plotting or typesetting program.", &
        "The model is $x(t)=e^{-\alpha t}\cos(\omega t)$, with $\alpha=0.15$ and $\omega=2$."])

    call figure(figsize=[6.0_dp, 3.2_dp])
    call plot(time, displacement, "b-")
    call title("Damped oscillator")
    call xlabel("Time $t$")
    call ylabel("Displacement $x(t)$")
    call ylim(-1.1_dp, 1.1_dp)
    call grid(.true.)
    call include_figure(caption="Oscillatory motion with exponential damping.", label="fig:motion")
    call clf()

    call include_table(results, columns=[character(len=12) :: "Time", "Displacement", "Envelope"], &
                       caption="Selected values from the simulation.", label="tab:values")
    call markdown([character(len=100) :: &
        "## Interpretation", &
        "", &
        "@fig:motion shows the oscillations and @tab:values their decreasing amplitude.", &
        "The envelope halves after", &
        "```{math}", &
        ":enumerated: false", &
        "t_{1/2}=\frac{\log 2}{\alpha}\approx 4.62.", &
        "```", &
        "The same retained report can be exported repeatedly; saving it does not clear it."])

    call save("hpc_report.svg")
    call save("hpc_report.pdf")
end program plot_hpc_report
