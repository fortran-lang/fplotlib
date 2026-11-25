! fplotlib_report -- explicit, self-contained scientific report builder.
!
! Accumulates MyST Markdown blocks, owned vector frames (e.g. captured
! fplotlib figures), and formatted tables into a report_t, caches the
! laid-out pages across repeated exports (SVG, PDF, PNG, EPS), and has
! no global state.
module fplotlib_report
    use fplotlib_style, only: dp
    use fplotlib_scene, only: frame_t, paged_document_t, recording_renderer_t
    use fplotlib_typeset, only: ts_page_count, ts_page_draw, ts_page_size
    use fplotlib_markdown, only: md_document_t, md_figure_t, md_typeset
    use fplotlib_document, only: document_asset_t, export_document, save_document
    use fplotlib_status, only: status_t, contract_error
    use fplotlib_io, only: file_ext
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use, intrinsic :: iso_fortran_env, only: error_unit
    implicit none
    private

    public :: report_t, document_asset_t

    character, parameter :: NL = achar(10), BS = achar(92)

    type :: report_t
        private
        character(len=:), allocatable :: md_buf
        integer :: md_len = 0
        type(frame_t) :: fig_scene
        integer, allocatable :: fig_handles(:)
        integer :: nfig = 0
        type(paged_document_t) :: pages
        logical :: dirty = .true.
        logical :: has_pages = .false.
    contains
        procedure :: clear => report_clear
        procedure, private :: report_markdown_text, report_markdown_lines
        generic :: markdown => report_markdown_text, report_markdown_lines
        procedure :: include_frame => report_include_frame
        procedure, private :: report_table_char, report_table_real, report_table_int
        generic :: include_table => report_table_char, report_table_real, report_table_int
        procedure :: export => report_export
        procedure :: save => report_save
    end type report_t

contains

    subroutine report_clear(self)
        class(report_t), intent(inout) :: self
        self%md_len = 0
        if (allocated(self%md_buf)) deallocate (self%md_buf)
        self%nfig = 0
        if (allocated(self%fig_handles)) deallocate (self%fig_handles)
        call self%pages%clear()
        self%dirty = .true.
        self%has_pages = .false.
    end subroutine report_clear

    subroutine report_append_raw(self, s)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: grown
        integer :: need, cap, m

        m = len(s)
        if (m == 0) return
        need = self%md_len + m
        cap = 0
        if (allocated(self%md_buf)) cap = len(self%md_buf)
        if (cap < need) then
            cap = max(max(256, 2*cap), need)
            allocate (character(len=cap) :: grown)
            if (self%md_len > 0) grown(1:self%md_len) = self%md_buf(1:self%md_len)
            call move_alloc(grown, self%md_buf)
        end if
        self%md_buf(self%md_len + 1:need) = s
        self%md_len = need
    end subroutine report_append_raw

    subroutine report_markdown_text(self, text)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: text

        if (len(text) == 0) return
        if (self%md_len > 0) then
            if (self%md_buf(self%md_len:self%md_len) == NL) then
                call report_append_raw(self, NL)
            else
                call report_append_raw(self, NL//NL)
            end if
        end if
        call report_append_raw(self, text)
        self%dirty = .true.
    end subroutine report_markdown_text

    subroutine report_markdown_lines(self, lines)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: lines(:)
        character(len=:), allocatable :: blk
        integer :: k, n, tot, pos, l

        n = size(lines)
        if (n == 0) return
        tot = max(0, n - 1)
        do k = 1, n
            tot = tot + len_trim(lines(k))
        end do
        allocate (character(len=max(1, tot)) :: blk)
        pos = 1
        do k = 1, n
            if (k > 1) then
                blk(pos:pos) = NL
                pos = pos + 1
            end if
            l = len_trim(lines(k))
            if (l > 0) then
                blk(pos:pos + l - 1) = lines(k)(1:l)
                pos = pos + l
            end if
        end do
        if (tot > 0) call report_markdown_text(self, blk(1:tot))
    end subroutine report_markdown_lines

    subroutine report_include_frame(self, frame, caption, label, width, align)
        class(report_t), intent(inout) :: self
        type(frame_t), intent(in) :: frame
        character(len=*), intent(in), optional :: caption, label, width, align
        integer, allocatable :: grown(:)
        character(len=:), allocatable :: blk, fig_name
        integer :: h

        if (self%nfig == 0) call self%fig_scene%init(0.0_dp, 0.0_dp)
        if (.not. allocated(self%fig_handles)) allocate (self%fig_handles(8))
        if (self%nfig == size(self%fig_handles)) then
            allocate (grown(2*size(self%fig_handles)))
            grown(1:self%nfig) = self%fig_handles(1:self%nfig)
            call move_alloc(grown, self%fig_handles)
        end if
        call self%fig_scene%import_frame(frame, h)
        self%nfig = self%nfig + 1
        self%fig_handles(self%nfig) = h

        fig_name = "__report_fig_"//itoa(self%nfig)
        blk = ""
        if (present(label)) then
            if (len_trim(label) > 0) blk = "("//trim(adjustl(label))//")="//NL
        end if
        blk = blk//":::{figure} "//fig_name//NL
        if (present(width)) then
            if (len_trim(width) > 0) blk = blk//":width: "//trim(adjustl(width))//NL
        end if
        if (present(align)) then
            if (len_trim(align) > 0) blk = blk//":align: "//trim(adjustl(align))//NL
        end if
        if (present(caption)) then
            if (len_trim(caption) > 0) blk = blk//trim(caption)//NL
        end if
        blk = blk//":::"
        call report_markdown_text(self, blk)
    end subroutine report_include_frame

    subroutine report_table_char(self, cells, columns, caption, label, align)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: cells(:, :)
        character(len=*), intent(in), optional :: columns(:)
        character(len=*), intent(in), optional :: caption, label
        character(len=*), intent(in), optional :: align(:)
        character(len=:), allocatable :: blk, row_s, sep_s
        integer :: nr, nc, r, c
        logical :: has_cap

        nr = size(cells, 1)
        nc = size(cells, 2)
        if (nc <= 0) return
        if (present(columns)) then
            if (size(columns) /= nc) &
                call contract_error("include_table: columns length must match number of columns")
        end if
        if (present(align)) then
            if (size(align) /= nc) &
                call contract_error("include_table: align length must match number of columns")
        end if

        row_s = "|"
        sep_s = "|"
        do c = 1, nc
            if (present(columns)) then
                row_s = row_s//" "//escape_pipe(trim(adjustl(columns(c))))//" |"
            else
                row_s = row_s//" Col "//itoa(c)//" |"
            end if
            if (present(align)) then
                sep_s = sep_s//" "//align_sep(align(c), .false.)//" |"
            else
                sep_s = sep_s//" --- |"
            end if
        end do

        blk = ""
        if (present(label)) then
            if (len_trim(label) > 0) blk = "("//trim(adjustl(label))//")="//NL
        end if
        has_cap = .false.
        if (present(caption)) has_cap = len_trim(caption) > 0
        if (has_cap) blk = blk//":::{table} "//trim(adjustl(caption))//NL
        blk = blk//row_s//NL//sep_s
        do r = 1, nr
            row_s = "|"
            do c = 1, nc
                row_s = row_s//" "//escape_pipe(trim(adjustl(cells(r, c))))//" |"
            end do
            blk = blk//NL//row_s
        end do
        if (has_cap) blk = blk//NL//":::"
        call report_markdown_text(self, blk)
    end subroutine report_table_char

    subroutine report_table_real(self, values, columns, caption, label, fmt, align)
        class(report_t), intent(inout) :: self
        real(dp), intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:)
        character(len=*), intent(in), optional :: caption, label, fmt
        character(len=*), intent(in), optional :: align(:)
        character(len=64), allocatable :: cells(:, :)
        character(len=16), allocatable :: col_al(:)
        integer :: nr, nc, r, c

        nr = size(values, 1)
        nc = size(values, 2)
        if (nc <= 0) return
        allocate (cells(nr, nc))
        do r = 1, nr
            do c = 1, nc
                if (present(fmt)) then
                    cells(r, c) = format_real(values(r, c), fmt)
                else
                    cells(r, c) = format_real(values(r, c), "")
                end if
            end do
        end do
        if (present(align)) then
            call report_table_char(self, cells, columns=columns, caption=caption, &
                                   label=label, align=align)
        else
            allocate (col_al(nc))
            col_al = "right"
            call report_table_char(self, cells, columns=columns, caption=caption, &
                                   label=label, align=col_al)
        end if
    end subroutine report_table_real

    subroutine report_table_int(self, values, columns, caption, label, align)
        class(report_t), intent(inout) :: self
        integer, intent(in) :: values(:, :)
        character(len=*), intent(in), optional :: columns(:)
        character(len=*), intent(in), optional :: caption, label
        character(len=*), intent(in), optional :: align(:)
        character(len=32), allocatable :: cells(:, :)
        character(len=16), allocatable :: col_al(:)
        integer :: nr, nc, r, c

        nr = size(values, 1)
        nc = size(values, 2)
        if (nc <= 0) return
        allocate (cells(nr, nc))
        do r = 1, nr
            do c = 1, nc
                write (cells(r, c), "(I0)") values(r, c)
            end do
        end do
        if (present(align)) then
            call report_table_char(self, cells, columns=columns, caption=caption, &
                                   label=label, align=align)
        else
            allocate (col_al(nc))
            col_al = "right"
            call report_table_char(self, cells, columns=columns, caption=caption, &
                                   label=label, align=col_al)
        end if
    end subroutine report_table_int

    subroutine report_ensure_layout(self)
        class(report_t), intent(inout) :: self
        type(md_document_t) :: doc
        type(md_figure_t), allocatable :: figs(:)
        type(recording_renderer_t) :: rec
        type(frame_t) :: page
        character(len=:), allocatable :: src
        real(dp) :: fw, fh, w, h
        integer :: k, p, col, bg(3)

        if (.not. self%dirty .and. self%has_pages) return

        if (self%md_len > 0 .and. allocated(self%md_buf)) then
            src = self%md_buf(1:self%md_len)
        else
            src = ""
        end if

        if (self%nfig > 0) then
            allocate (figs(self%nfig))
            do k = 1, self%nfig
                figs(k)%name = "__report_fig_"//itoa(k)
                call self%fig_scene%metrics(fw, fh, handle=self%fig_handles(k))
                call rec%open_canvas(fw, fh)
                call self%fig_scene%draw(rec, handle=self%fig_handles(k))
                call rec%close_canvas()
                call rec%take(figs(k)%frame)
            end do
            call md_typeset(doc, src, figures=figs)
        else
            call md_typeset(doc, src)
        end if

        call self%pages%clear()
        call ts_page_size(doc%engine, w, h, col)
        bg = [ishft(col, -16), iand(ishft(col, -8), 255), iand(col, 255)]
        do p = 1, max(1, ts_page_count(doc%engine))
            call rec%open_canvas(w, h, bg_rgb=bg)
            if (p <= ts_page_count(doc%engine)) call ts_page_draw(doc%engine, rec, p)
            call rec%close_canvas()
            call rec%take(page)
            call self%pages%add_page(page)
        end do
        self%dirty = .false.
        self%has_pages = .true.
    end subroutine report_ensure_layout

    subroutine report_export(self, format, assets, dpi, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: format
        type(document_asset_t), allocatable, intent(out) :: assets(:)
        real(dp), intent(in), optional :: dpi
        type(status_t), intent(out), optional :: status
        real(dp) :: res
        type(status_t) :: ok

        res = 150.0_dp
        if (present(dpi)) then
            if (.not. ieee_is_finite(dpi) .or. dpi <= 0.0_dp) &
                call contract_error("render_report: dpi must be finite and positive")
            res = dpi
        end if
        call report_ensure_layout(self)
        call export_document(self%pages, format, assets, dpi=res)
        if (present(status)) status = ok
    end subroutine report_export

    subroutine report_save(self, filename, dpi, status)
        class(report_t), intent(inout) :: self
        character(len=*), intent(in) :: filename
        real(dp), intent(in), optional :: dpi
        type(status_t), intent(out), optional :: status
        type(status_t) :: local
        real(dp) :: res

        select case (file_ext(filename))
        case ("svg", "pdf", "eps", "png")
        case default
            call contract_error("save: supported formats are .svg, .pdf, .eps and .png, not ." &
                                //file_ext(filename))
        end select
        res = 150.0_dp
        if (present(dpi)) then
            if (.not. ieee_is_finite(dpi) .or. dpi <= 0.0_dp) &
                call contract_error("save: dpi must be finite and positive")
            res = dpi
        end if
        call report_ensure_layout(self)
        call save_document(self%pages, filename, local, res)
        if (present(status)) then
            status = local
        else if (.not. local%ok()) then
            write (error_unit, "(a)") "fplotlib: save: "//trim(local%message)
            error stop 2
        end if
    end subroutine report_save

    function format_real(val, fmt) result(s)
        real(dp), intent(in) :: val
        character(len=*), intent(in) :: fmt
        character(len=64) :: s
        character(len=:), allocatable :: fspec, t
        integer :: ios

        s = ""
        if (.not. ieee_is_finite(val)) then
            write (s, "(G0)") val
            s = adjustl(s)
            return
        end if
        if (len_trim(fmt) > 0) then
            t = trim(adjustl(fmt))
            if (t(1:1) == "(") then
                fspec = t
            else
                fspec = "("//t//")"
            end if
            write (s, fspec, iostat=ios) val
            if (ios /= 0) write (s, "(G0)") val
        else
            if (val /= 0.0_dp .and. (abs(val) >= 1.0e6_dp .or. abs(val) < 1.0e-3_dp)) then
                write (s, "(ES10.2)") val
            else
                write (s, "(F0.3)") val
            end if
        end if
        s = adjustl(s)
        if (s(1:1) == ".") then
            s = "0"//trim(s)
        else if (s(1:2) == "-.") then
            s = "-0."//trim(s(3:))
        end if
    end function format_real

    function align_sep(spec, default_right) result(s)
        character(len=*), intent(in) :: spec
        logical, intent(in) :: default_right
        character(len=:), allocatable :: s, t
        integer :: k
        t = trim(adjustl(spec))
        do k = 1, len(t)
            if (t(k:k) >= "A" .and. t(k:k) <= "Z") t(k:k) = achar(iachar(t(k:k)) + 32)
        end do
        select case (t)
        case ("left", "l")
            s = ":---"
        case ("center", "centre", "c")
            s = ":---:"
        case ("right", "r")
            s = "---:"
        case default
            if (default_right) then
                s = "---:"
            else
                s = "---"
            end if
        end select
    end function align_sep

    function escape_pipe(s) result(t)
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: t
        integer :: k, n
        n = 0
        do k = 1, len(s)
            if (s(k:k) == "|") then
                n = n + 2
            else
                n = n + 1
            end if
        end do
        allocate (character(len=n) :: t)
        n = 0
        do k = 1, len(s)
            if (s(k:k) == "|") then
                t(n + 1:n + 2) = BS//"|"
                n = n + 2
            else
                n = n + 1
                t(n:n) = s(k:k)
            end if
        end do
    end function escape_pipe

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: b
        write (b, "(I0)") i
        s = trim(b)
    end function itoa

end module fplotlib_report
