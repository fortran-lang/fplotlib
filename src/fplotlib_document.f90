! Export owned pages to memory or files, without a frontend or live layout context.
module fplotlib_document
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_scene, only: paged_document_t
    use fplotlib_io, only: file_ext, write_bytes
    use fplotlib_backend_pdf, only: pdf_renderer_t
    use fplotlib_backend_svg, only: svg_renderer_t
    use fplotlib_backend_png, only: png_renderer_t
    use fplotlib_backend_eps, only: eps_renderer_t
    implicit none
    private
    public :: document_asset_t, export_document, save_document

    type :: document_asset_t
        integer :: page = 0
        character(len=:), allocatable :: bytes
    end type document_asset_t

contains

    ! PDF is one asset; page formats produce one asset per page. A notebook
    ! or WASM host can consume these bytes without creating temporary files.
    subroutine export_document(document, format, assets, dpi, status)
        type(paged_document_t), intent(in) :: document
        character(len=*), intent(in) :: format
        type(document_asset_t), allocatable, intent(out) :: assets(:)
        real(dp), intent(in), optional :: dpi
        type(document_asset_t), allocatable :: pending(:)
        type(pdf_renderer_t) :: pdf
        type(svg_renderer_t) :: svg
        type(png_renderer_t) :: png
        type(eps_renderer_t) :: eps
        real(dp) :: w, h, resolution
        integer :: p, n
        type(status_t), intent(out) :: status
        n = document%page_count()
        if (n == 0) then
            call status%set(ERROR_STATE, "export_document: no pages")
            return
        end if
        resolution = 150.0_dp
        if (present(dpi)) resolution = dpi
        select case (format)
        case ("pdf")
            allocate (pending(1))
            do p = 1, n
                call document%page_size(p, w, h, status=status)
                if (.not. status%ok()) return
                if (p == 1) then
                    call pdf%open_canvas(w, h, status=status)
                    if (.not. status%ok()) return
                else
                    call pdf%new_page(width=w, height=h, status=status)
                    if (.not. status%ok()) return
                end if
                call document%draw_page(p, pdf, status=status)
                if (.not. status%ok()) return
            end do
            call pdf%close_canvas(status=status)
            if (.not. status%ok()) return
            pending(1)%bytes = pdf%bytes(status=status)
            if (.not. status%ok()) return
        case ("svg", "png", "eps")
            allocate (pending(n))
            do p = 1, n
                pending(p)%page = p
                call document%page_size(p, w, h, status=status)
                if (.not. status%ok()) return
                select case (format)
                case ("svg")
                    call svg%open_canvas(w, h, status=status)
                    if (.not. status%ok()) return
                    call document%draw_page(p, svg, status=status)
                    if (.not. status%ok()) return
                    call svg%close_canvas(status=status)
                    if (.not. status%ok()) return
                    pending(p)%bytes = svg%bytes(status=status)
                    if (.not. status%ok()) return
                case ("png")
                    if (resolution <= 0.0_dp) then
                        call status%set(ERROR_ARGUMENT, "export_document: dpi must be positive")
                        return
                    end if
                    call png%set_dpi(resolution, status=status)
                    if (.not. status%ok()) return
                    call png%open_canvas(w, h, status=status)
                    if (.not. status%ok()) return
                    call document%draw_page(p, png, status=status)
                    if (.not. status%ok()) return
                    call png%close_canvas(status=status)
                    if (.not. status%ok()) return
                    pending(p)%bytes = png%bytes(status=status)
                    if (.not. status%ok()) return
                case ("eps")
                    call eps%open_canvas(w, h, status=status)
                    if (.not. status%ok()) return
                    call document%draw_page(p, eps, status=status)
                    if (.not. status%ok()) return
                    call eps%close_canvas(status=status)
                    if (.not. status%ok()) return
                    pending(p)%bytes = eps%bytes(status=status)
                    if (.not. status%ok()) return
                end select
            end do
        case default
            call status%set(ERROR_UNSUPPORTED, "export_document: expected pdf, svg, png or eps")
            return
        end select
        call move_alloc(pending, assets)
    end subroutine export_document

    subroutine save_document(document, filename, dpi, status)
        type(paged_document_t), intent(in) :: document
        character(len=*), intent(in) :: filename
        real(dp), intent(in), optional :: dpi
        type(document_asset_t), allocatable :: assets(:)
        integer :: p
        type(status_t), intent(out) :: status
        call export_document(document, file_ext(filename), assets, dpi, status=status)
        if (.not. status%ok()) return
        do p = 1, size(assets)
            call write_bytes(page_file(filename, p, size(assets)), assets(p)%bytes, status=status)
            if (.not. status%ok()) return
        end do
    end subroutine save_document

    ! A single asset uses filename; multiple assets use name-page.ext.
    function page_file(filename, p, n) result(f)
        character(len=*), intent(in) :: filename
        integer, intent(in) :: p, n
        character(len=:), allocatable :: f
        character(len=16) :: num
        integer :: dot, slash
        if (n <= 1) then
            f = filename
            return
        end if
        write (num, "(i0)") p
        dot = index(filename, ".", back=.true.)
        slash = max(index(filename, "/", back=.true.), index(filename, achar(92), back=.true.))
        if (dot <= slash + 1) then
            f = trim(filename)//"-"//trim(num)//".svg"
        else
            f = filename(1:dot - 1)//"-"//trim(num)//filename(dot:)
        end if
    end function page_file

end module fplotlib_document
