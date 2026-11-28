program bench_imshow
    use fplotlib
    implicit none
    integer :: n, i, j, ios
    real(dp), allocatable :: z(:, :)
    real(dp) :: x, y
    character(len=:), allocatable :: ext
    character(len=16) :: arg

    ext = "png"
    n = 256
    if (command_argument_count() >= 1) then
        call get_command_argument(1, arg)
        ext = trim(arg)
    end if
    if (command_argument_count() >= 2) then
        call get_command_argument(2, arg)
        read (arg, *, iostat=ios) n
        if (ios /= 0 .or. n < 2) n = 256
    end if

    allocate (z(n, n))
    do j = 1, n
        x = -3.0_dp + 6.0_dp*real(j - 1, dp)/real(n - 1, dp)
        do i = 1, n
            y = -3.0_dp + 6.0_dp*real(i - 1, dp)/real(n - 1, dp)
            z(i, j) = sin(x)*cos(y)*exp(-0.1_dp*(x*x + y*y))
        end do
    end do

    call imshow(z, cmap="viridis", extent=[-3.0_dp, 3.0_dp, -3.0_dp, 3.0_dp])
    call colorbar()
    call title("imshow benchmark")
    call savefig("imshow_f." // ext)
end program bench_imshow
