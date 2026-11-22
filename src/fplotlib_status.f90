! Errors.
!
! fplotlib separates two kinds of failure. A call that breaks a documented
! precondition -- a nonfinite coordinate, drawing before the canvas is
! open, an unknown fill rule -- is a bug in the calling code. Nothing at run
! time can make such a call succeed, so it stops the program through
! contract_error, with a message that names the broken rule, instead of
! returning an error for every caller to pass along.
!
! A failure that a correct program can still meet at run time, such as an
! output file that cannot be written, is returned instead, through a
! status_t argument, so that the caller decides what happens next. The
! other outputs of such a call may only be used when status%ok() is true.
module fplotlib_status
    use, intrinsic :: iso_fortran_env, only: error_unit
    implicit none
    private
    public :: status_t, contract_error, set_status
    public :: STATUS_OK, ERROR_IO, ERROR_SIZE

    ! ERROR_IO: a file could not be opened, written or closed.
    ! ERROR_SIZE: what was drawn came out too large to encode, as a PNG
    ! cropped to it with too many pixels.
    integer, parameter :: STATUS_OK = 0, ERROR_IO = 1, ERROR_SIZE = 2

    ! message is blank when the status is ok, and otherwise says what
    ! failed; as in stdlib's state_type it has a fixed length, so that it
    ! is always defined, and is read with trim.
    integer, parameter, public :: MESSAGE_LEN = 512

    type :: status_t
        integer :: code = STATUS_OK
        character(len=MESSAGE_LEN) :: message = ""
    contains
        procedure :: ok => status_okay
    end type status_t

contains

    pure logical function status_okay(self)
        class(status_t), intent(in) :: self
        status_okay = self%code == STATUS_OK
    end function status_okay

    ! Records a failure. It is fplotlib's own: the fplotlib module does not
    ! export it, and a caller only reads a status.
    subroutine set_status(status, code, message)
        type(status_t), intent(out) :: status
        integer, intent(in) :: code
        character(len=*), intent(in) :: message
        status%code = code
        status%message = message
    end subroutine set_status

    ! Stops the program on a broken precondition. message names the rule,
    ! usually after the call or part of fplotlib that checks it, as in
    ! "renderer: canvas is not open". It goes to standard error with
    ! "fplotlib: " in front, and the exit code is 1.
    subroutine contract_error(message)
        character(len=*), intent(in) :: message
        write (error_unit, "(a)") "fplotlib: "//message
        error stop 1
    end subroutine contract_error

end module fplotlib_status
