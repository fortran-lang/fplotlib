module test_status
    use fplotlib_status, only: status_t
    implicit none
    private
    public :: require_ok

contains

    subroutine require_ok(status)
        type(status_t), intent(in) :: status
        if (status%ok()) return
        print "(a)", status%message
        error stop 1
    end subroutine require_ok

end module test_status
