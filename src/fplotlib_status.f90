! Recoverable errors.
!
! fplotlib separates two kinds of failure. A call that breaks a documented
! precondition -- a nonfinite coordinate, drawing before the canvas is
! open, an unknown fill rule -- is a bug in the calling code and stops the
! program with a message (see fplotlib_render_checks). A failure that a
! correct program can still meet at run time, such as an output file that
! cannot be written, is returned instead, through a required status_t
! argument, so that the caller decides what happens next. The other outputs
! of such a call may only be used when status%ok() is true.
module fplotlib_status
    implicit none
    private
    public :: status_t
    public :: STATUS_OK, ERROR_IO

    integer, parameter :: STATUS_OK = 0, ERROR_IO = 1

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
