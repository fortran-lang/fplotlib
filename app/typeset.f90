! Command-line driver for fplotlib's Markdown typesetter.
!
! Usage:
!   typeset input1.md [input2.md ...] [-o output.pdf] [--dpi 150]
program typeset_cli
    use fplotlib, only: dp, typeset_file, status_t
    use fplotlib_style, only: lower
    use, intrinsic :: iso_fortran_env, only: error_unit, output_unit
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none

    integer :: nargs, i, nin, arglen, ios
    character(len=1024) :: arg
    character(len=1024), allocatable :: inputs(:)
    character(len=:), allocatable :: out_file, first_in
    real(dp) :: dpi_val
    logical :: has_dpi, end_opts
    type(status_t) :: st

    nargs = command_argument_count()
    if (nargs == 0) then
        call print_usage(error_unit)
        stop 1
    end if

    allocate (inputs(nargs))
    nin = 0
    out_file = ""
    dpi_val = 150.0_dp
    has_dpi = .false.
    end_opts = .false.

    i = 1
    do while (i <= nargs)
        call get_command_argument(i, arg, length=arglen)
        if (arglen > len(arg)) then
            write (error_unit, "(a)") "typeset: argument is too long"
            stop 1
        end if
        if (.not. end_opts .and. (trim(arg) == "-h" .or. trim(arg) == "--help")) then
            call print_usage(output_unit)
            stop 0
        else if (.not. end_opts .and. trim(arg) == "--") then
            end_opts = .true.
        else if (.not. end_opts .and. (trim(arg) == "-o" .or. trim(arg) == "--output")) then
            if (i + 1 > nargs) then
                write (error_unit, "(a)") "typeset: "//trim(arg)//" requires an output file"
                stop 1
            end if
            i = i + 1
            call get_command_argument(i, arg, length=arglen)
            if (arglen > len(arg)) then
                write (error_unit, "(a)") "typeset: output filename is too long"
                stop 1
            end if
            out_file = trim(arg)
        else if (.not. end_opts .and. trim(arg) == "--dpi") then
            if (i + 1 > nargs) then
                write (error_unit, "(a)") "typeset: --dpi requires a number"
                stop 1
            end if
            i = i + 1
            call get_command_argument(i, arg, length=arglen)
            if (arglen > len(arg)) then
                write (error_unit, "(a)") "typeset: --dpi value is too long"
                stop 1
            end if
            read (arg(1:arglen), *, iostat=ios) dpi_val
            if (ios /= 0) then
                write (error_unit, "(a)") "typeset: invalid --dpi value: "//trim(arg)
                stop 1
            else if (.not. ieee_is_finite(dpi_val) .or. dpi_val <= 0.0_dp) then
                write (error_unit, "(a)") "typeset: invalid --dpi value: "//trim(arg)
                stop 1
            end if
            has_dpi = .true.
        else if (.not. end_opts .and. arglen > 0) then
            if (arg(1:1) == "-") then
                write (error_unit, "(a)") "typeset: unknown option: "//trim(arg)
                call print_usage(error_unit)
                stop 1
            end if
            nin = nin + 1
            inputs(nin) = trim(arg)
        else
            nin = nin + 1
            inputs(nin) = trim(arg)
        end if
        i = i + 1
    end do

    if (nin == 0) then
        write (error_unit, "(a)") "typeset: at least one input Markdown file is required"
        call print_usage(error_unit)
        stop 1
    end if

    if (len(out_file) == 0) then
        first_in = trim(inputs(1))
        if (len(first_in) > 3) then
            if (lower(first_in(len(first_in) - 2:len(first_in))) == ".md") then
                out_file = first_in(1:len(first_in) - 3)//".pdf"
            else
                out_file = "out.pdf"
            end if
        else
            out_file = "out.pdf"
        end if
    end if

    if (has_dpi) then
        call typeset_file(inputs(1:nin), out_file, dpi=dpi_val, status=st)
    else
        call typeset_file(inputs(1:nin), out_file, status=st)
    end if
    if (.not. st%ok()) then
        write (error_unit, "(a)") trim(st%message)
        stop 2
    end if

contains

    subroutine print_usage(u)
        integer, intent(in) :: u
        write (u, "(a)") "Usage: typeset input1.md [input2.md ...] [-o output.pdf] [--dpi 150]"
        write (u, "(a)") ""
        write (u, "(a)") "Options:"
        write (u, "(a)") "  -o, --output FILE  Output file (.pdf, .svg, .png, .eps)"
        write (u, "(a)") "                     Default: replace .md with .pdf, or out.pdf"
        write (u, "(a)") "  --dpi N            Resolution in DPI for PNG output (default: 150)"
        write (u, "(a)") "  -h, --help         Show this help message"
    end subroutine print_usage

end program typeset_cli
