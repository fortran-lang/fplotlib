! Export owned pages without a frontend, filesystem, or live layout context.
module fplotlib_document
    use fplotlib_style, only: dp
    use fplotlib_scene, only: paged_document_t
    use fplotlib_backend_pdf, only: pdf_renderer_t
    use fplotlib_backend_svg, only: svg_renderer_t
    use fplotlib_backend_png, only: png_renderer_t
    use fplotlib_backend_eps, only: eps_renderer_t
    implicit none
    private
    public :: document_asset_t, export_document

    type :: document_asset_t
        integer :: page = 0
        character(len=:), allocatable :: bytes
    end type document_asset_t

contains

    ! PDF is one asset; page formats produce one asset per page. A notebook
    ! or WASM host can consume these bytes without creating temporary files.
    subroutine export_document(document, format, assets, dpi)
        type(paged_document_t), intent(in) :: document
        character(len=*), intent(in) :: format
        type(document_asset_t), allocatable, intent(out) :: assets(:)
        real(dp), intent(in), optional :: dpi
        type(pdf_renderer_t) :: pdf
        type(svg_renderer_t) :: svg
        type(png_renderer_t) :: png
        type(eps_renderer_t) :: eps
        real(dp) :: w, h, resolution
        integer :: p, n
        n = document%page_count()
        if (n == 0) error stop "export_document: no pages"
        resolution = 150.0_dp
        if (present(dpi)) resolution = dpi
        select case (format)
        case ("pdf")
            allocate (assets(1))
            do p = 1, n
                call document%page_size(p, w, h)
                if (p == 1) then
                    call pdf%open_canvas(w, h)
                else
                    call pdf%new_page(width=w, height=h)
                end if
                call document%draw_page(p, pdf)
            end do
            call pdf%close_canvas()
            assets(1)%bytes = pdf%bytes()
        case ("svg", "png", "eps")
            allocate (assets(n))
            do p = 1, n
                assets(p)%page = p
                call document%page_size(p, w, h)
                select case (format)
                case ("svg")
                    call svg%open_canvas(w, h)
                    call document%draw_page(p, svg)
                    call svg%close_canvas()
                    assets(p)%bytes = svg%bytes()
                case ("png")
                    if (resolution <= 0.0_dp) error stop "export_document: dpi must be positive"
                    call png%set_dpi(resolution)
                    call png%open_canvas(w, h)
                    call document%draw_page(p, png)
                    call png%close_canvas()
                    assets(p)%bytes = png%bytes()
                case ("eps")
                    call eps%open_canvas(w, h)
                    call document%draw_page(p, eps)
                    call eps%close_canvas()
                    assets(p)%bytes = eps%bytes()
                end select
            end do
        case default
            error stop "export_document: expected pdf, svg, png or eps"
        end select
    end subroutine export_document

end module fplotlib_document
