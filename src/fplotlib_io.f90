! Shared file output for plots and animations.
module fplotlib_io
    use fplotlib_style, only: lower
    use fplotlib_status
    use, intrinsic :: iso_fortran_env, only: int64
    implicit none
    private
    public :: file_ext, write_bytes, read_bytes, dir_name, join_path

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

    recursive subroutine read_bytes(filename, data, status)
        character(len=*), intent(in) :: filename
        character(len=:), allocatable, intent(out) :: data
        type(status_t), intent(out) :: status
        integer :: u, ios, close_ios
        integer(int64) :: nbytes
        character(len=512) :: message, close_message

        open (newunit=u, file=trim(filename), status="old", action="read", &
              form="unformatted", access="stream", iostat=ios, iomsg=message)
        if (ios /= 0) then
            data = ""
            call set_status(status, ERROR_IO, io_message("cannot open", filename, message))
            return
        end if
        message = ""
        inquire (unit=u, size=nbytes, iostat=ios, iomsg=message)
        if (ios /= 0 .or. nbytes < 0_int64) then
            data = ""
            if (ios == 0) message = "file size is unknown"
            call set_status(status, ERROR_IO, io_message("cannot size", filename, message))
            close (u, iostat=close_ios)
            return
        end if
        if (nbytes > int(huge(0), int64)) then
            data = ""
            call set_status(status, ERROR_SIZE, &
                            "file '"//trim(filename)//"' is too large to read")
            close (u, iostat=close_ios)
            return
        end if
        if (nbytes > 0_int64) then
            allocate (character(len=int(nbytes)) :: data)
            read (u, iostat=ios, iomsg=message) data
            if (ios /= 0) then
                deallocate (data)
                data = ""
                call set_status(status, ERROR_IO, io_message("cannot read", filename, message))
                close (u, iostat=close_ios, iomsg=close_message)
                if (close_ios /= 0) status%message = trim(status%message)// &
                                                     "; close failed: "//trim(close_message)
                return
            end if
        else
            data = ""
        end if
        close (u, iostat=ios, iomsg=message)
        if (ios /= 0) &
            call set_status(status, ERROR_IO, io_message("cannot close", filename, message))
    end subroutine read_bytes

    pure function dir_name(path) result(dir)
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: dir
        integer :: n, slash
        n = len_trim(path)
        if (n == 0) then
            dir = ""
            return
        end if
        slash = max(index(path(1:n), "/", back=.true.), &
                    index(path(1:n), achar(92), back=.true.))
        if (slash == 0) then
            dir = ""
        else if (slash == 1) then
            dir = path(1:1)
        else if (slash == 3) then
            if (path(2:2) == ":") then
                dir = path(1:3)
            else
                dir = path(1:2)
            end if
        else
            dir = path(1:slash - 1)
        end if
    end function dir_name

    pure function join_path(dir, rel) result(path)
        character(len=*), intent(in) :: dir, rel
        character(len=:), allocatable :: path, d, r
        d = trim(dir)
        r = trim(rel)
        if (len(d) == 0) then
            path = r
            return
        end if
        if (len(r) == 0) then
            path = d
            return
        end if
        if (r(1:1) == "/" .or. r(1:1) == achar(92)) then
            path = r
            return
        end if
        if (len(r) >= 2) then
            if (r(2:2) == ":") then
                path = r
                return
            end if
        end if
        if (d(len(d):len(d)) == "/" .or. d(len(d):len(d)) == achar(92)) then
            path = d//r
        else
            path = d//"/"//r
        end if
    end function join_path

    ! The compiler's message, with the file name in front unless the
    ! message already quotes it, as gfortran's does.
    recursive function io_message(what, filename, message) result(m)
        character(len=*), intent(in) :: what, filename, message
        character(len=:), allocatable :: m
        if (index(message, "'"//trim(filename)//"'") > 0) then
            m = trim(message)
        else
            m = what//" '"//trim(filename)//"': "//trim(message)
        end if
    end function io_message

end module fplotlib_io
