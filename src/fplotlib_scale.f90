! fplotlib_scale — how a data value becomes a position along an axis.
!
! Every axis is a monotone map from data space to a linear "screen" space.
! Collecting that map behind one type means the renderer, the limit padding
! and the tick placement all ask the same question instead of each carrying
! its own `is this a log axis` flag.
module fplotlib_scale
    use fplotlib_style, only: dp
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private

    public :: scale_t, scale_fwd, scale_inv
    public :: SCALE_LINEAR, SCALE_LOG, SCALE_SYMLOG

    integer, parameter :: SCALE_LINEAR = 0
    integer, parameter :: SCALE_LOG = 1
    integer, parameter :: SCALE_SYMLOG = 2

    type :: scale_t
        integer :: kind = SCALE_LINEAR
        ! symlog only: the half-width of the linear region around zero, and
        ! how many decades wide that region is drawn.
        real(dp) :: linthresh = 2.0_dp
        real(dp) :: linscale = 1.0_dp
    end type scale_t

contains

    pure function scale_fwd(s, v) result(u)
        type(scale_t), intent(in) :: s
        real(dp), intent(in) :: v
        real(dp) :: u, a

        select case (s%kind)
        case (SCALE_LOG)
            ! A log axis reaches down to the least normal double: values
            ! below it, subnormal, zero or negative, are drawn there, which
            ! keeps the map total and puts no value below another.
            u = log10(max(v, tiny(1.0_dp)))
        case (SCALE_SYMLOG)
            a = abs(v)
            if (a <= s%linthresh) then
                u = v * linscale_adj(s)
            else
                if (ieee_is_finite(a / s%linthresh)) then
                    u = sign(s%linthresh * (linscale_adj(s) + log10(a / s%linthresh)), v)
                else
                    ! a so far past linthresh that the ratio overflows.
                    u = sign(s%linthresh * (linscale_adj(s) + log10(a) - log10(s%linthresh)), v)
                end if
            end if
        case default
            u = v
        end select
    end function scale_fwd

    pure function scale_inv(s, u) result(v)
        type(scale_t), intent(in) :: s
        real(dp), intent(in) :: u
        real(dp) :: v, edge, e, p

        select case (s%kind)
        case (SCALE_LOG)
            v = 10.0_dp ** u
        case (SCALE_SYMLOG)
            edge = s%linthresh * linscale_adj(s)
            if (abs(u) <= edge) then
                v = u / linscale_adj(s)
            else
                e = abs(u) / s%linthresh - linscale_adj(s)
                p = 10.0_dp ** e
                if (ieee_is_finite(p)) then
                    v = sign(s%linthresh * p, u)
                else
                    ! Past the largest double before linthresh scales it
                    ! down: the product taken in logs.
                    v = sign(10.0_dp ** (e + log10(s%linthresh)), u)
                end if
            end if
        case default
            v = u
        end select
    end function scale_inv

    ! The linear region is stretched so that `linscale` decades of the log
    ! region and the linear region are drawn the same length.
    pure function linscale_adj(s) result(f)
        type(scale_t), intent(in) :: s
        real(dp) :: f
        f = s%linscale / (1.0_dp - 0.1_dp)
    end function linscale_adj

end module fplotlib_scale
