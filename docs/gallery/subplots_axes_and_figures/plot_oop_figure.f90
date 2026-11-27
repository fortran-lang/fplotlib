! Object-Oriented Figure and Axes API
! ===================================
!
! This example demonstrates the object-oriented ``figure_t`` and ``axes_t`` API.
! Instead of importing module-level plotting procedures and relying on global
! state, you can create explicit ``figure_t`` instances, add ``axes_t``
! subplots, and keep multiple independent figures live at the same time.

program plot_oop_figure
    use fplotlib, only: dp, figure_t, axes_t
    implicit none

    integer, parameter :: n = 200
    real(dp), parameter :: pi = 3.14159265358979323846_dp
    real(dp) :: x(n), y_sin(n), y_cos(n), y_damp(n), env(n)
    integer :: i
    type(figure_t) :: fig1, fig2
    type(axes_t) :: ax1, ax2, ax_damp

! %%
! Generate sample data
! --------------------

    do i = 1, n
        x(i) = 4.0_dp * pi * real(i - 1, dp) / real(n - 1, dp)
        y_sin(i) = sin(x(i))
        y_cos(i) = cos(x(i))
        env(i) = exp(-0.15_dp * x(i))
        y_damp(i) = env(i) * sin(2.0_dp * x(i))
    end do

! %%
! Build two independent figures at the same time
! ----------------------------------------------
!
! Because each ``figure_t`` owns its own figure slot, calls on ``fig1`` and
! ``fig2`` can be interleaved without interfering with each other.

    fig1 = figure_t(figsize=[7.0_dp, 5.2_dp], dpi=150.0_dp)
    fig2 = figure_t(figsize=[6.4_dp, 4.2_dp], dpi=150.0_dp)

    ax1 = fig1%add_subplot(2, 1, 1, title="Sine", ylabel="$\sin(x)$", &
                           ylim=[-1.15_dp, 1.15_dp], grid=.true.)
    call ax1%plot(x, y_sin, "C0-", lw=2.0_dp, label="$\sin(x)$")
    call ax1%legend()

    ax_damp = fig2%add_subplot(title="Damped Oscillation", xlabel="$x$", &
                               ylabel="amplitude", ylim=[-1.15_dp, 1.15_dp], &
                               grid=.true.)
    call ax_damp%plot(x, y_damp, "C3-", lw=2.0_dp, label="$e^{-0.15x}\sin(2x)$")
    call ax_damp%plot(x, env, "k--", lw=1.2_dp, label="$\pm e^{-0.15x}$")
    call ax_damp%plot(x, -env, "k--", lw=1.2_dp)
    call ax_damp%legend()

    ax2 = fig1%add_subplot(2, 1, 2, title="Cosine", xlabel="$x$", &
                           ylabel="$\cos(x)$", ylim=[-1.15_dp, 1.15_dp], &
                           grid=.true.)
    call ax2%plot(x, y_cos, "C1--", lw=2.0_dp, label="$\cos(x)$")
    call ax2%legend()

    call fig1%suptitle("Object-Oriented Subplots")
    call fig1%savefig("oop_figure_subplots.svg")

! %%
! Save the second independent figure and close both
! -------------------------------------------------

    call fig2%savefig("oop_figure_damped.svg")
    call fig1%close()
    call fig2%close()

end program plot_oop_figure
