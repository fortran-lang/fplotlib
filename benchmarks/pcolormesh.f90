program bench_pcolormesh
    use fplotlib
    implicit none
    integer :: n, i, j, ios
    real(dp), allocatable :: x(:), y(:), z(:, :)
    real(dp) :: xv, yv
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

    allocate (x(n + 1), y(n + 1), z(n, n))
    do i = 1, n + 1
        x(i) = -3.0_dp + 6.0_dp*real(i - 1, dp)/real(n, dp)
        y(i) = x(i)
    end do
    do j = 1, n
        xv = 0.5_dp*(x(j) + x(j + 1))
        do i = 1, n
            yv = 0.5_dp*(y(i) + y(i + 1))
            z(i, j) = sin(xv)*cos(yv)*exp(-0.1_dp*(xv*xv + yv*yv))
        end do
    end do

    call pcolormesh(x, y, z, cmap="viridis")
    call colorbar()
    call title("pcolormesh benchmark")
    call savefig("pcolormesh_f." // ext)
end program bench_pcolormesh
