module test_frame_backends
    use fplotlib_style, only: dp
    use fplotlib_render, only: renderer_t, paint_t, clip_t
    use fplotlib_backend_svg, only: svg_renderer_t
    use fplotlib_backend_eps, only: eps_renderer_t
    use fplotlib_backend_pdf, only: pdf_renderer_t
    implicit none
    private

    public :: frame_backend_check

contains

    subroutine frame_backend_check(nfail)
        integer, intent(out) :: nfail

        nfail = 0
        call vector_frame_numbers_check(nfail)
        print "(a,i0)", "frame backends: failures = ", nfail
    end subroutine frame_backend_check

    ! SVG, PDF and EPS write a frame's matrix with fifteen significant
    ! digits, so that a scale of 4e-7 is not written as 0, and the numbers
    ! inside a frame with as many more decimals as it magnifies, so that
    ! a frame magnifying a million times still places them to a millionth
    ! of a point on the page.
    subroutine vector_frame_numbers_check(nfail)
        integer, intent(inout) :: nfail
        type(svg_renderer_t) :: svg
        type(pdf_renderer_t) :: pdf
        type(eps_renderer_t) :: eps
        type(paint_t) :: paint
        type(clip_t) :: none
        character(len=:), allocatable :: b
        real(dp), parameter :: small(6) = [4.0e-7_dp, 0.0_dp, 0.0_dp, 4.0e-7_dp, 0.0_dp, 0.0_dp]
        real(dp), parameter :: large(6) = [1.0e6_dp, 0.0_dp, 0.0_dp, 1.0e6_dp, 0.0_dp, 0.0_dp]

        paint%filled = .true.
        call svg%open_canvas(200.0_dp, 150.0_dp)
        call draw(svg)
        call svg%close_canvas()
        b = svg%bytes()
        call expect(index(b, "matrix(0.0000004 0 0 0.0000004 0 0)") > 0 .and. index(b, "0.0000012345") > 0, &
                    "SVG frames keep a small scale and magnified coordinates", nfail)
        call pdf%open_canvas(200.0_dp, 150.0_dp)
        call draw(pdf)
        call pdf%close_canvas()
        b = pdf%bytes()
        call expect(index(b, "0.0000004 0 0 0.0000004 0 0 cm") > 0 .and. index(b, "0.0000012345") > 0, &
                    "PDF frames keep a small scale and magnified coordinates", nfail)
        call eps%open_canvas(200.0_dp, 150.0_dp)
        call draw(eps)
        call eps%close_canvas()
        b = eps%bytes()
        call expect(index(b, "[0.0000004 0 0 0.0000004 0 0 ] concat") > 0 .and. index(b, "0.0000012345") > 0, &
                    "EPS frames keep a small scale and magnified coordinates", nfail)
    contains
        subroutine draw(r)
            class(renderer_t), intent(inout) :: r
            call r%begin_frame(small, none)
            call r%draw_rect(2.5e8_dp, 1.875e8_dp, 1.0e8_dp, 1.0e8_dp, paint)
            call r%end_frame()
            call r%begin_frame(large, none)
            call r%draw_rect(0.0000012345_dp, 0.00001_dp, 0.00001_dp, 0.00001_dp, paint)
            call r%end_frame()
        end subroutine draw
    end subroutine vector_frame_numbers_check

    subroutine expect(ok, label, nfail)
        logical, intent(in) :: ok
        character(len=*), intent(in) :: label
        integer, intent(inout) :: nfail

        if (ok) return
        nfail = nfail + 1
        print "(a)", "  FAIL "//label
    end subroutine expect

end module test_frame_backends
