! Shared file output for plots, animations and documents.
module fplotlib_io
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

    subroutine write_bytes(filename, data)
        character(len=*), intent(in) :: filename, data
        integer :: u, ios
        open (newunit=u, file=trim(filename), status="replace", action="write", &
              form="unformatted", access="stream", iostat=ios)
        if (ios /= 0) then
            print *, "fplotlib: failed to open ", trim(filename), ", iostat=", ios
            error stop "fplotlib: output file could not be opened"
        end if
        if (len(data) > 0) then
            write (u, iostat=ios) data
            if (ios /= 0) then
                print *, "fplotlib: failed to write ", trim(filename), ", iostat=", ios
                close (u)
                error stop "fplotlib: output write failed"
            end if
        end if
        close (u, iostat=ios)
        if (ios /= 0) error stop "fplotlib: output close failed"
    end subroutine write_bytes

end module fplotlib_io
