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
    use fplotlib_text, only: text_width, text_layout
    use fplotlib_mathtext, only: math_formula, mrules_t
    use fplotlib_glyphs, only: FACE_REGULAR
    implicit none
    private

    public :: contract_case, contract_check

    integer, parameter :: NCASE = 50

    ! A target that draws nothing and cannot transform: it leaves the
    ! frame methods to renderer_t's defaults.
    type, extends(renderer_t) :: flat_renderer_t
    contains
        procedure :: open_canvas_impl => flat_open
        procedure :: close_canvas_impl => flat_close
        procedure :: draw_path_impl => flat_path
        procedure :: draw_rect_impl => flat_rect
        procedure :: draw_circle_impl => flat_circle
        procedure :: draw_markers_impl => flat_markers
        procedure :: draw_glyphs_impl => flat_glyphs
        procedure :: draw_image_impl => flat_image
    end type flat_renderer_t
    character(len=*), parameter :: EXPECT(NCASE) = [character(len=100) :: &
        "fplotlib: renderer: canvas is not open", &
        "fplotlib: path: nonfinite or out-of-range coordinate", &
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
        "fplotlib: figure: figsize must be positive and at most 1e9 inches", &
        "fplotlib: subplots_adjust: left must be finite", &
        "fplotlib: pie: values must not be negative", &
        "fplotlib: scatter: s must be finite and nonnegative", &
        "fplotlib: set_xscale: linthresh must be from 1e-300 to 1e300", &
        "fplotlib: plot: dashes must not be all zero", &
        "fplotlib: tick_params: rotation must be finite", &
        "fplotlib: plot: dashes must be finite and nonnegative", &
        "fplotlib: errorbar: yerr must not be negative", &
        "fplotlib: figure: figsize must be positive and at most 1e9 inches", &
        "fplotlib: hist: bins must be from 1 to 1000000, got 0", &
        "fplotlib: streamplot: density must be at most 10", &
        "fplotlib: secondary_xaxis: scale must be finite", &
        "fplotlib: tick_format: decimals must be from 0 to 17, got 25", &
        "fplotlib: subplot: a grid of more than 10000 axes", &
        "fplotlib: figure: num must be from 1 to 100000", &
        "fplotlib: paint: a pen with round or square dash ends may be at most 100 times its dash pattern", &
        "fplotlib: savefig: the cropped figure has too many pixels at this dpi", &
        "fplotlib: render_png: the figure has too many pixels at this dpi", &
        "fplotlib: render_svg: pad_inches must be finite and at most 1e9 inches", &
        "fplotlib: set_yscale: linthresh must be from 1e-300 to 1e300", &
        "fplotlib: text: glyph run count must be nonnegative", &
        "fplotlib: text: a glyph run needs gid, x, y and size", &
        "fplotlib: text: glyph run arrays shorter than its count", &
        "fplotlib: renderer: end_frame without begin_frame", &
        "fplotlib: renderer: end_frame inside a group begun after the frame", &
        "fplotlib: renderer: begin_frame without end_frame at close_canvas", &
        "fplotlib: frame: nonfinite or out-of-range transform", &
        "fplotlib: renderer: this target cannot transform or clip a frame", &
        "fplotlib: renderer: frame_decimals(outer) with no frame open", &
        "fplotlib: pdf: new_page inside a frame or group", &
        "fplotlib: mathtext: rule list count must be nonnegative", &
        "fplotlib: mathtext: a rule list needs x, y, w and h", &
        "fplotlib: mathtext: rule list arrays shorter than its count", &
        "fplotlib: text: glyph run arrays must start at index 1", &
        "fplotlib: mathtext: rule list arrays must start at index 1"]
    ! The exit status each case must end with: 1 for a broken
    ! precondition, 2 for a failure at run time with no status to take it.
    integer, parameter :: CODE(NCASE) = [ &
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, &
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, &
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1]

contains

    ! Makes broken call k. It must not return.
    subroutine contract_case(k)
        integer, intent(in) :: k
        type(svg_renderer_t) :: svg
        integer :: k2
        type(glyphrun_t) :: run
        real(dp) :: adv, rw, rh, rd
        type(mrules_t) :: rules
        type(png_renderer_t) :: png
        type(pdf_renderer_t) :: pdf
        type(eps_renderer_t) :: eps
        type(paint_t) :: p
        character(len=:), allocatable :: b
        real(dp) :: nan, w
        type(axes), allocatable :: axs(:, :)
        type(axes) :: sec
        type(flat_renderer_t) :: flat
        type(clip_t) :: none
        real(dp), parameter :: unit(6) = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp]

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
            call figure(figsize=[1.0e13_dp, 1.0_dp])
        case (25)
            call hist([1.0_dp, 2.0_dp], bins=0)
        case (26)
            call streamplot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp], reshape([1.0_dp, 1.0_dp, 1.0_dp, 1.0_dp], [2, 2]), &
                            reshape([1.0_dp, 1.0_dp, 1.0_dp, 1.0_dp], [2, 2]), density=1000.0_dp)
        case (27)
            ! A method of type(axes) checks as its free function does.
            call subplots(1, 1, axs)
            sec = axs(1, 1)%secondary_xaxis(scale=nan)
        case (28)
            call tick_format(style="percent", decimals=25)
        case (29)
            call subplot(1, 20000, 1)
        case (30)
            call figure(num=1000000000)
        case (31)
            call png%open_canvas(10.0_dp, 10.0_dp)
            p%filled = .false.
            p%stroked = .true.
            p%line_width = 1000.0_dp
            p%cap = CAP_ROUND
            p%n_dash = 2
            p%dash(1:2) = [1.0_dp, 1.0_dp]
            call png%draw_path([0.0_dp, 10.0_dp], [5.0_dp, 5.0_dp], [VERB_MOVE, VERB_LINE], 2, p)
        case (32)
            call plot([0.0_dp, 1.0_dp], [0.0_dp, 1.0_dp])
            call ylabel("y", labelpad=1.0e6_dp)
            call savefig("tests/out/contract.png", bbox_inches="tight")
        case (33)
            ! Not cropped, the figure's size is known beforehand: a broken
            ! precondition, not a status.
            call figure(figsize=[200.0_dp, 200.0_dp], dpi=100.0_dp)
            b = render_png()
        case (34)
            ! Checked in render_svg's own name, cropped or not.
            call figure()
            b = render_svg(pad_inches=2.0e9_dp)
        case (35)
            ! A symlog threshold whose linear part would be subnormal.
            call figure()
            call set_yscale("symlog", linthresh=1.0e-310_dp)
        ! Glyph runs built by hand are checked whole before text is added.
        case (36)
            run%n = -1
            call text_layout("A", 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, adv)
        case (37)
            allocate (run%x(4), run%y(4), run%size(4))
            call text_layout("A", 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, adv)
        case (38)
            allocate (run%gid(1), run%x(1), run%y(1), run%size(1))
            run%n = 5
            call text_layout("A", 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, adv)
        ! Frames scope a transform and a clip, and nest with groups.
        case (39)
            call svg%open_canvas(10.0_dp, 10.0_dp)
            call svg%end_frame()
        case (40)
            call svg%open_canvas(10.0_dp, 10.0_dp)
            call svg%begin_frame(unit, none)
            call svg%begin_group("g")
            call svg%end_frame()
        case (41)
            call png%open_canvas(10.0_dp, 10.0_dp)
            call png%begin_frame(unit, none)
            call png%close_canvas()
        case (42)
            call eps%open_canvas(10.0_dp, 10.0_dp)
            call eps%begin_frame([1.0_dp, 0.0_dp, 0.0_dp, nan, 0.0_dp, 0.0_dp], none)
        case (43)
            ! The identity without a clip is fine; a scale is not.
            call flat%open_canvas(10.0_dp, 10.0_dp)
            call flat%begin_frame(unit, none)
            call flat%end_frame()
            call flat%begin_frame([2.0_dp, 0.0_dp, 0.0_dp, 2.0_dp, 0.0_dp, 0.0_dp], none)
        case (44)
            call svg%open_canvas(10.0_dp, 10.0_dp)
            k2 = frame_decimals(svg, outer=.true.)
        ! A PDF page cannot end inside a frame or group.
        case (45)
            call pdf%open_canvas(10.0_dp, 10.0_dp)
            call pdf%begin_frame(unit, none)
            call pdf%new_page()
        ! Rule lists built by hand are checked whole before a formula adds
        ! to them.
        case (46)
            rules%n = -1
            call math_formula("\frac{a}{b}", 10.0_dp, .false., run, rules, rw, rh, rd)
        case (47)
            allocate (rules%x(4), rules%y(4), rules%w(4))
            call math_formula("\frac{a}{b}", 10.0_dp, .false., run, rules, rw, rh, rd)
        case (48)
            allocate (rules%x(1), rules%y(1), rules%w(1), rules%h(1))
            rules%n = 5
            call math_formula("\frac{a}{b}", 10.0_dp, .false., run, rules, rw, rh, rd)
        ! Arrays that start anywhere but 1.
        case (49)
            allocate (run%gid(0:3), run%x(0:3), run%y(0:3), run%size(0:3))
            run%n = 3
            call text_layout("A", 10.0_dp, FACE_REGULAR, 0.0_dp, 0.0_dp, run, adv)
        case (50)
            allocate (rules%x(0:3), rules%y(0:3), rules%w(0:3), rules%h(0:3))
            rules%n = 3
            call math_formula("\frac{a}{b}", 10.0_dp, .false., run, rules, rw, rh, rd)
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
            if (cstat /= 0 .or. stat /= CODE(k) .or. .not. found) then
                print "(a, i0, a, i0, a, i0, a)", "contract case ", k, ": exit status ", stat, &
                    ", expected ", CODE(k), " and '"//err//"'"
                nfail = nfail + 1
            end if
        end do
        print "(a, i0, a, i0)", "contract checks: ", NCASE, " broken calls, failures = ", nfail
    end subroutine contract_check

    subroutine flat_open(self, width, height, bg_rgb, bg_alpha, x0, y0)
        class(flat_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha, x0, y0
    end subroutine flat_open

    subroutine flat_close(self)
        class(flat_renderer_t), intent(inout) :: self
    end subroutine flat_close

    subroutine flat_path(self, x, y, verbs, n_verb, paint)
        class(flat_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
    end subroutine flat_path

    subroutine flat_rect(self, x, y, w, h, paint, radius)
        class(flat_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
    end subroutine flat_rect

    subroutine flat_circle(self, cx, cy, r, paint)
        class(flat_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
    end subroutine flat_circle

    subroutine flat_markers(self, x, y, mx, my, mverbs, n_mverb, paint)
        class(flat_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:), mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
    end subroutine flat_markers

    subroutine flat_glyphs(self, x, y, run, paint, angle)
        class(flat_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
    end subroutine flat_glyphs

    subroutine flat_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(flat_renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint
    end subroutine flat_image

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: buf
        write (buf, "(i0)") i
        s = trim(buf)
    end function itoa

end module test_contract
