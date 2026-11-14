! Recoverable errors for the explicit core. A fallible call requires a status
! argument; its other outputs may only be used when status%ok() is true.
module fplotlib_status
    implicit none
    private
    public :: status_t
    public :: STATUS_OK, ERROR_ARGUMENT, ERROR_STATE, ERROR_UNSUPPORTED
    public :: ERROR_IO, ERROR_LAYOUT, ERROR_RESOURCE

    integer, parameter :: STATUS_OK = 0, ERROR_ARGUMENT = 1, ERROR_STATE = 2, &
                          ERROR_UNSUPPORTED = 3, ERROR_IO = 4, ERROR_LAYOUT = 5, &
                          ERROR_RESOURCE = 6

    type :: status_t
        integer :: code = STATUS_OK
        character(len=:), allocatable :: message
    contains
        procedure :: ok => status_okay
        procedure :: set => status_set
    end type status_t

contains

    pure logical function status_okay(self)
        class(status_t), intent(in) :: self
        status_okay = self%code == STATUS_OK
    end function status_okay

    subroutine status_set(self, code, message)
        class(status_t), intent(out) :: self
        integer, intent(in) :: code
        character(len=*), intent(in) :: message
        self%code = code
        self%message = message
    end subroutine status_set

end module fplotlib_status
