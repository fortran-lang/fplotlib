! Rotated Axis Tick Labels
! ========================
!
! Long categorical names, dates, or dense numeric labels along an axis can
! overlap when drawn horizontally. Use ``tick_params(axis=..., rotation=...)``
! to rotate x-axis or y-axis tick labels by an angle in degrees, together with
! ``constrained_layout(.true.)`` or ``tight_layout()`` so the rotated labels
! stay inside the figure margins.

program plot_rotated_tick_labels
    use fplotlib, only: bar, constrained_layout, dp, figure, grid, plot, &
                        savefig, subplot, suptitle, tick_params, tight_layout, &
                        title, xlabel, xticks, ylabel, ylim, yticks
    implicit none

    real(dp), parameter :: x_cat(6) = [1.0_dp, 2.0_dp, 3.0_dp, &
                                       4.0_dp, 5.0_dp, 6.0_dp]
    real(dp), parameter :: throughput(6) = [42.0_dp, 68.5_dp, 81.2_dp, &
                                            55.0_dp, 93.4_dp, 74.8_dp]
    character(len=7), parameter :: categories(6) = [ &
        "Dense  ", &
        "Sparse ", &
        "3D FFT ", &
        "MC Sim ", &
        "Stencil", &
        "N-Body "  &
    ]

    real(dp), parameter :: t(6) = [1.0_dp, 2.0_dp, 3.0_dp, &
                                   4.0_dp, 5.0_dp, 6.0_dp]
    real(dp), parameter :: temp(6) = [2.4_dp, 4.1_dp, 9.6_dp, &
                                      14.2_dp, 19.5_dp, 24.1_dp]
    character(len=5), parameter :: dates(6) = [ &
        "26-01", "26-02", "26-03", &
        "26-04", "26-05", "26-06"  &
    ]

    real(dp), parameter :: x_q(4) = [1.0_dp, 2.0_dp, 3.0_dp, 4.0_dp]
    real(dp), parameter :: y_val(4) = [1.8_dp, 3.1_dp, 2.6_dp, 4.2_dp]
    character(len=12), parameter :: quarters(4) = [ &
        "2026 Q1     ", "2026 Q2     ", &
        "2026 Q3     ", "2026 Q4     "  &
    ]
    real(dp), parameter :: y_pos(5) = [1.0_dp, 2.0_dp, 3.0_dp, 4.0_dp, 5.0_dp]
    character(len=10), parameter :: levels(5) = [ &
        "Very Low  ", "Low       ", "Medium    ", &
        "High      ", "Very High "  &
    ]

! %%
! Rotating x-axis tick labels at 45 and 90 degrees
! ------------------------------------------------
!
! Passing ``axis="x"`` and ``rotation=45.0_dp`` (or ``90.0_dp`` for vertical
! labels) to ``tick_params`` rotates the x-axis tick labels. Enabling
! ``constrained_layout(.true.)`` expands the bottom margin automatically so
! long rotated labels are not clipped.

    call figure(figsize=[11.0_dp, 4.8_dp])
    call constrained_layout(.true.)

    call subplot(1, 2, 1)
    call bar(x_cat, throughput, color="C0", edgecolor="k", linewidth=0.6_dp)
    call xticks(x_cat, categories)
    call tick_params(axis="x", rotation=45.0_dp, labelsize=9.0_dp)
    call xlabel("Kernel", labelpad=14.0_dp)
    call ylabel("Throughput (GFLOP/s)")
    call ylim(0.0_dp, 105.0_dp)
    call title("45-degree categorical x-ticks")
    call grid(.true., axis="y", alpha=0.3_dp)

    call subplot(1, 2, 2)
    call plot(t, temp, "C3-o", lw=1.8_dp)
    call xticks(t, dates)
    call tick_params(axis="x", rotation=90.0_dp, labelsize=9.0_dp)
    call xlabel("Month (YY-MM)", labelpad=16.0_dp)
    call ylabel("Temperature (C)")
    call ylim(0.0_dp, 28.0_dp)
    call title("90-degree vertical x-ticks")
    call grid(.true., alpha=0.3_dp)

    call suptitle("Rotated X-Axis Tick Labels")
    call savefig("rotated_xticks.svg")

! %%
! Rotating both x-axis and y-axis tick labels
! -------------------------------------------
!
! ``tick_params`` accepts ``axis="x"``, ``axis="y"``, or ``axis="both"``.
! Here both axes use custom tick labels rotated by different angles, and
! ``tight_layout()`` adjusts the figure margins before saving.

    call figure(figsize=[6.8_dp, 4.6_dp])
    call plot(x_q, y_val, "C2-s", lw=2.0_dp)
    call xticks(x_q, quarters)
    call yticks(y_pos, levels)
    call tick_params(axis="x", rotation=30.0_dp)
    call tick_params(axis="y", rotation=45.0_dp)
    call xlabel("Quarter")
    call ylabel("Load level")
    call ylim(0.5_dp, 5.5_dp)
    call title("Rotated X-Axis and Y-Axis Tick Labels")
    call grid(.true., alpha=0.3_dp)
    call tight_layout()
    call savefig("rotated_xy_ticks.svg")

end program plot_rotated_tick_labels
