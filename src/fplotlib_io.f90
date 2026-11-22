! Shared file output for plots and animations.
module fplotlib_io
    use fplotlib_style, only: lower
    use fplotlib_status
    implicit none
    private
    public :: file_ext, write_bytes

contains

    ! The extension, in lower case, picks the format, as it does in
    ! matplotlib. A name with no extension at all is taken as SVG.
    function file_ext(filename) result(ext)
        character(len=*), intent(in) :: filename
        character(len=:), allocatable :: ext
        integer :: dot, slash
        dot = index(filename, ".", back=.true.)
        slash = max(index(filename, "/", back=.true.), index(filename, achar(92), back=.true.))
        if (dot <= slash + 1) then
            ext = "svg"
        else
            ext = lower(filename(dot + 1:len_trim(filename)))
        end if
    end function file_ext

    subroutine write_bytes(filename, data, status)
        character(len=*), intent(in) :: filename, data
        type(status_t), intent(out) :: status
        integer :: u, ios, close_ios
        character(len=512) :: message, close_message
        open (newunit=u, file=trim(filename), status="replace", action="write", &
              form="unformatted", access="stream", iostat=ios, iomsg=message)
        if (ios /= 0) then
            call set_status(status, ERROR_IO, io_message("cannot open", filename, message))
            return
        end if
        if (len(data) > 0) then
            write (u, iostat=ios, iomsg=message) data
            if (ios /= 0) then
                call set_status(status, ERROR_IO, io_message("cannot write", filename, message))
                close (u, iostat=close_ios, iomsg=close_message)
                if (close_ios /= 0) status%message = trim(status%message)//"; close failed: "//trim(close_message)
                return
            end if
        end if
        close (u, iostat=ios, iomsg=message)
        if (ios /= 0) call set_status(status, ERROR_IO, io_message("cannot close", filename, message))
    end subroutine write_bytes

    ! The compiler's message, with the file name in front unless the
    ! message already quotes it, as gfortran's does.
    function io_message(what, filename, message) result(m)
        character(len=*), intent(in) :: what, filename, message
        character(len=:), allocatable :: m
        if (index(message, "'"//trim(filename)//"'") > 0) then
            m = trim(message)
        else
            m = what//" '"//trim(filename)//"': "//trim(message)
        end if
    end function io_message

end module fplotlib_io
