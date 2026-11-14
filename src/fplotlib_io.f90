! Shared file output for plots and animations.
module fplotlib_io
    use fplotlib_status
    implicit none
    private
    public :: file_ext, write_bytes

contains

    ! A filename without an extension selects SVG.
    function file_ext(filename) result(ext)
        character(len=*), intent(in) :: filename
        character(len=:), allocatable :: ext
        integer :: dot, slash, i, c
        dot = index(filename, ".", back=.true.)
        slash = max(index(filename, "/", back=.true.), index(filename, achar(92), back=.true.))
        if (dot <= slash + 1) then
            ext = "svg"
        else
            ext = filename(dot + 1:len_trim(filename))
            do i = 1, len(ext)
                c = iachar(ext(i:i))
                if (c >= iachar("A") .and. c <= iachar("Z")) ext(i:i) = achar(c + 32)
            end do
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
            call status%set(ERROR_IO, "Cannot open '"//trim(filename)//"': "//trim(message))
            return
        end if
        if (len(data) > 0) then
            write (u, iostat=ios, iomsg=message) data
            if (ios /= 0) then
                call status%set(ERROR_IO, "Cannot write '"//trim(filename)//"': "//trim(message))
                close (u, iostat=close_ios, iomsg=close_message)
                if (close_ios /= 0) status%message = status%message//"; close failed: "//trim(close_message)
                return
            end if
        end if
        close (u, iostat=ios, iomsg=message)
        if (ios /= 0) call status%set(ERROR_IO, "Cannot close '"//trim(filename)//"': "//trim(message))
    end subroutine write_bytes

end module fplotlib_io
