! Broken preconditions stop the program.
!
! A call that breaks a documented precondition is a bug in the caller and
! stops through contract_error, which no test can catch from inside. So
! test_plots runs itself again once per case, as "test_plots contract k",
! where contract_case makes the broken call, and contract_check checks
! that each run exited with a failure and wrote the rule it broke to
! standard error.
module test_contract
    use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan
    use fplotlib
    use fplotlib_render
    use fplotlib_backend_svg, only: svg_renderer_t
    use fplotlib_backend_png, only: png_renderer_t
    use fplotlib_backend_pdf, only: pdf_renderer_t
    use fplotlib_backend_eps, only: eps_renderer_t
    use fplotlib_text, only: text_width
    use fplotlib_glyphs, only: FACE_REGULAR
    implicit none
    private

    public :: contract_case, contract_check

    integer, parameter :: NCASE = 24
    character(len=*), parameter :: EXPECT(NCASE) = [character(len=64) :: &
        "fplotlib: renderer: canvas is not open", &
        "fplotlib: path: nonfinite coordinate", &
        "fplotlib: renderer: end_group without begin_group", &
        "fplotlib: renderer: begin_group without end_group", &
        "fplotlib: renderer: bytes before close_canvas", &
        "fplotlib: paint: fill alpha must be in [0,1]", &
        "fplotlib: path: a contour must begin with MOVE", &
        "fplotlib: image: expected a nonempty 4 x nx x ny RGBA array", &
        "fplotlib: png: dpi must be finite and positive", &
        "fplotlib: text: font size must be finite and nonnegative", &
        "fplotlib: savefig: supported formats are", &
        "fplotlib: xlim: limits must be finite", &
        "fplotlib: plot: alpha must be in [0, 1], got 1.5", &
        "fplotlib: scatter: linewidths must be finite and nonnegative", &
        "fplotlib: figure: figsize must be finite and positive", &
        "fplotlib: subplots_adjust: left must be finite", &
        "fplotlib: pie: values must not be negative", &
        "fplotlib: scatter: s must be finite and nonnegative", &
        "fplotlib: set_xscale: linthresh must be finite and positive", &
        "fplotlib: plot: dashes must not be all zero", &
        "fplotlib: tick_params: rotation must be finite", &
        "fplotlib: plot: dashes must be finite and nonnegative", &
        "fplotlib: errorbar: yerr must not be negative", &
        "fplotlib: savefig: pad_inches leaves nothing of the figure"]

contains

    ! Makes broken call k. It must not return.
    subroutine contract_case(k)
        integer, intent(in) :: k
        type(svg_renderer_t) :: svg
        type(png_renderer_t) :: png
        type(pdf_renderer_t) :: pdf
        type(eps_renderer_t) :: eps
        type(paint_t) :: p
        character(len=:), allocatable :: b
        real(dp) :: nan, w

        nan = ieee_value(nan, ieee_quiet_nan)
        p%filled = .true.
        select case (k)
        case (1)
            call svg%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, p)
        case (2)
            call png%open_canvas(10.0_dp, 10.0_dp)
            call png%draw_path([0.0_dp, nan], [0.0_dp, 1.0_dp], [VERB_MOVE, VERB_LINE], 2, p)
        case (3)
            call pdf%open_canvas(10.0_dp, 10.0_dp)
            call pdf%end_group()
        case (4)
            call eps%open_canvas(10.0_dp, 10.0_dp)
            call eps%begin_group("g")
            call eps%close_canvas()
        case (5)
            call svg%open_canvas(10.0_dp, 10.0_dp)
            b = svg%bytes()
        case (6)
            call png%open_canvas(10.0_dp, 10.0_dp)
            p%fill_alpha = 1.5_dp
            call png%draw_rect(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, p)
        case (7)
            call pdf%open_canvas(10.0_dp, 10.0_dp)
            call pdf%draw_path([0.0_dp], [0.0_dp], [VERB_LINE], 1, p)
        case (8)
            call eps%open_canvas(10.0_dp, 10.0_dp)
            call eps%draw_image(0.0_dp, 0.0_dp, 1.0_dp, 1.0_dp, reshape([0], [1, 1, 1]), 1, 1, p)
        case (9)
            call png%set_dpi(0.0_dp)
        case (10)
            w = text_width("x", -1.0_dp, FACE_REGULAR)
        case (11)
            call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
            call savefig("tests/out/contract.jpg")
        case (12)
            call xlim(0.0_dp, nan)
        case (13)
            call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], alpha=1.5_dp)
        case (14)
            call scatter([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], linewidths=nan)
        case (15)
            call figure(figsize=[nan, 2.0_dp])
        case (16)
            call subplots_adjust(left=nan)
        case (17)
            call pie([1.0_dp, -1.0_dp, 2.0_dp])
        case (18)
            call scatter([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], s=nan)
        case (19)
            call set_xscale("symlog", linthresh=nan)
        case (20)
            call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], dashes=[0.0_dp, 0.0_dp])
        case (21)
            call tick_params(rotation=nan)
        case (22)
            call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], dashes=[nan, 1.0_dp])
        case (23)
            call errorbar([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], yerr=[0.1_dp, -0.1_dp])
        case (24)
            call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
            call savefig("tests/out/contract.svg", bbox_inches="tight", pad_inches=-100.0_dp)
        end select
    end subroutine contract_case

    ! Runs this program once per case and checks how each run ended.
    subroutine contract_check(nfail)
        integer, intent(out) :: nfail
        character(len=1024) :: self, line
        character(len=:), allocatable :: err, log
        integer :: k, stat, cstat, u, ios
        logical :: found

        nfail = 0
        call get_command_argument(0, self)
        do k = 1, NCASE
            log = "tests/out/contract_"//itoa(k)//".err"
            err = trim(EXPECT(k))
            call execute_command_line('"'//trim(self)//'" contract '//itoa(k)//" 2> "//log, &
                                      exitstat=stat, cmdstat=cstat)
            found = .false.
            open (newunit=u, file=log, status="old", action="read", iostat=ios)
            if (ios == 0) then
                do
                    read (u, "(a)", iostat=ios) line
                    if (ios /= 0) exit
                    if (index(line, err) > 0) found = .true.
                end do
                close (u)
            end if
            ! Exit code 1 is a broken precondition; 2 is a file that could
            ! not be written.
            if (cstat /= 0 .or. stat /= 1 .or. .not. found) then
                print "(a, i0, a, i0, a)", "contract case ", k, ": exit status ", stat, &
                    ", expected 1 and '"//err//"'"
                nfail = nfail + 1
            end if
        end do
        print "(a, i0, a, i0)", "contract checks: ", NCASE, " broken calls, failures = ", nfail
    end subroutine contract_check

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: buf
        write (buf, "(i0)") i
        s = trim(buf)
    end function itoa

end module test_contract
