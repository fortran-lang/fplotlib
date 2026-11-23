! Export owned pages to memory or files, without a frontend or live layout context.
module fplotlib_document
    use fplotlib_style, only: dp
    use fplotlib_scene, only: paged_document_t
    use fplotlib_io, only: file_ext, write_bytes
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use, intrinsic :: iso_fortran_env, only: error_unit
    use fplotlib_status, only: status_t, contract_error
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
    subroutine export_document(document, format, assets, dpi)
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
        character(len=:), allocatable :: fmt
        integer :: p, n
        n = document%page_count()
        if (n == 0) call contract_error("export_document: no pages")
        ! The resolution savefig and the PNG backend take by default.
        resolution = 100.0_dp
        if (present(dpi)) resolution = dpi
        ! In any case, as save_document takes a file's extension.
        fmt = lower(format)
        select case (fmt)
        case ("pdf")
            allocate (pending(1))
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
            pending(1)%bytes = pdf%bytes()
        case ("svg", "png", "eps")
            allocate (pending(n))
            do p = 1, n
                pending(p)%page = p
                call document%page_size(p, w, h)
                select case (fmt)
                case ("svg")
                    call svg%open_canvas(w, h)
                    call document%draw_page(p, svg)
                    call svg%close_canvas()
                    pending(p)%bytes = svg%bytes()
                case ("png")
                    if (.not. ieee_is_finite(resolution) .or. resolution <= 0.0_dp) &
                        call contract_error("export_document: dpi must be finite and positive")
                    call png%set_dpi(resolution)
                    call png%open_canvas(w, h)
                    call document%draw_page(p, png)
                    call png%close_canvas()
                    pending(p)%bytes = png%bytes()
                case ("eps")
                    call eps%open_canvas(w, h)
                    call document%draw_page(p, eps)
                    call eps%close_canvas()
                    pending(p)%bytes = eps%bytes()
                end select
            end do
        case default
            call contract_error("export_document: expected pdf, svg, png or eps")
        end select
        call move_alloc(pending, assets)
    end subroutine export_document

    ! Writing a file is the one step here that can fail at run time: the
    ! first file that cannot be written stops the export, after the pages
    ! before it were written, and is returned in status, as savefig returns
    ! it. Without status, the program stops with the message and exit
    ! code 2.
    subroutine save_document(document, filename, status, dpi)
        type(paged_document_t), intent(in) :: document
        character(len=*), intent(in) :: filename
        type(status_t), intent(out), optional :: status
        real(dp), intent(in), optional :: dpi
        type(document_asset_t), allocatable :: assets(:)
        type(status_t) :: local
        integer :: p
        call export_document(document, file_ext(filename), assets, dpi)
        do p = 1, size(assets)
            call write_bytes(page_file(filename, p, size(assets)), assets(p)%bytes, local)
            if (.not. local%ok()) exit
        end do
        if (present(status)) then
            status = local
        else if (.not. local%ok()) then
            write (error_unit, "(a)") "fplotlib: save_document: "//trim(local%message)
            error stop 2
        end if
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

    pure function lower(s) result(t)
        character(len=*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: i
        t = s
        do i = 1, len(s)
            if (s(i:i) >= "A" .and. s(i:i) <= "Z") t(i:i) = achar(iachar(s(i:i)) + 32)
        end do
    end function lower
end module fplotlib_document
