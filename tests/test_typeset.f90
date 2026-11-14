! The paragraph layout checked against XeTeX's.
!
! tests/para_refs.txt holds how XeTeX, setting each paragraph in the same
! Lato files with LaTeX's parameters, breaks it into lines and where it
! puts every glyph (tools/gen_para_refs.py makes it). fplotlib breaks
! paragraphs with the same algorithm, so the two have to agree: the same
! lines, hyphenated at the same places, and every glyph within TOL points
! of XeTeX's. With Lato's exact kerning they agree to 0.02 bp; fplotlib
! stores its kerning to 5 font units (tools/gen_glyphs.py, KERN_STEP),
! which moves a glyph by up to 0.0125 bp and, through the spacing of a
! justified line, the glyphs after it by up to about 0.065 bp.
module test_typeset
    use fplotlib_status
    use test_status
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_typeset, only: typeset_context_t, ts_reset, ts_set_page, ts_set_font, ts_begin_par, &
                                ts_end_par, ts_word, ts_space, ts_line_count, &
                                ts_line_info, ALIGN_JUSTIFY
    use fplotlib_glyphs, only: glyph_char, FACE_REGULAR
    implicit none
    private

    public :: para_ref_check

    real(dp), parameter :: TOL = 0.07_dp
    real(dp), parameter :: SIZE = 10.0_dp
    integer, parameter :: MAXL = 64

contains

    subroutine para_ref_check(path, nfail)
        character(len=*), intent(in) :: path
        integer, intent(out) :: nfail
        character(len=8192) :: line
        character(len=:), allocatable :: text
        character(len=2048) :: ltext(MAXL)
        character(len=8192) :: lx(MAXL)
        integer :: u, ios, nl, npar
        real(dp) :: width, indent

        nfail = 0
        npar = 0
        open (newunit=u, file=path, status="old", action="read", iostat=ios)
        if (ios /= 0) then
            print "(a)", "paragraph refs: "//path//" not found"
            nfail = 1
            return
        end if
        nl = 0
        text = ""
        width = 0.0_dp
        indent = 0.0_dp
        do
            read (u, "(a)", iostat=ios) line
            if (ios /= 0) exit
            if (len_trim(line) == 0 .or. line(1:1) == "#") cycle
            select case (line(1:2))
            case ("P ")
                if (len(text) > 0) then
                    call check_one(text, width, indent, nl, ltext, lx, nfail)
                    npar = npar + 1
                end if
                read (line(3:), *) width, indent
                nl = 0
            case ("T ")
                text = trim(line(3:))
            case ("L ")
                nl = nl + 1
                ltext(nl) = line(3:)
            case ("X ")
                lx(nl) = line(3:)
            end select
        end do
        close (u)
        if (len(text) > 0) then
            call check_one(text, width, indent, nl, ltext, lx, nfail)
            npar = npar + 1
        end if
        print "(a,i0,a,i0,a)", "paragraph refs: ", npar, " paragraphs, ", nfail, &
            " differ from XeTeX"
    end subroutine para_ref_check

    subroutine check_one(text, width, indent, nl, ltext, lx, nfail)
        character(len=*), intent(in) :: text, ltext(:), lx(:)
        real(dp), intent(in) :: width, indent
        integer, intent(in) :: nl
        integer, intent(inout) :: nfail
        integer, allocatable :: gids(:)
        real(dp), allocatable :: xs(:)
        real(dp) :: rx(1024), worst
        integer :: i, j, l, n, nr, cp, nb, k
        logical :: bad
        type(typeset_context_t) :: state
        character(len=64) :: what

        type(status_t) :: status
        call ts_reset(state, status=status)
        call require_ok(status)
        call ts_set_page(state, width, 10000.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, status=status)
        call require_ok(status)
        call ts_set_font(state, SIZE, status=status)
        call require_ok(status)
        call ts_begin_par(state, ALIGN_JUSTIFY, indent, status=status)
        call require_ok(status)
        i = 1
        do while (i <= len(text))
            j = index(text(i:), " ")
            if (j == 0) then
                j = len(text) + 1
            else
                j = i + j - 1
            end if
            if (j > i) then
                call ts_word(state, text(i:j - 1), FACE_REGULAR, SIZE, status=status)
                call require_ok(status)
            end if
            if (j <= len(text)) then
                call ts_space(state, FACE_REGULAR, SIZE, status=status)
                call require_ok(status)
            end if
            i = j + 1
        end do
        call ts_end_par(state, status=status)
        call require_ok(status)

        bad = .false.
        worst = 0.0_dp
        what = ""
        if (ts_line_count(state) /= nl) then
            bad = .true.
            write (what, "(a,i0,a,i0)") "lines ", ts_line_count(state), " vs ", nl
        else
            do l = 1, nl
                call ts_line_info(state, l, gids, xs, n, status=status)
                call require_ok(status)
                nr = 0
                read (lx(l), *, iostat=k) (rx(j), j=1, count_words(lx(l)))
                nr = count_words(lx(l))
                if (nr /= n) then
                    bad = .true.
                    write (what, "(a,i0,a,i0,a,i0)") "line ", l, " glyphs ", n, " vs ", nr
                    exit
                end if
                ! The characters, in order.
                i = 1
                do k = 1, n
                    call utf8_next(ltext(l), i, cp, nb)
                    i = i + nb
                    if (glyph_char(gids(k)) /= cp) then
                        bad = .true.
                        write (what, "(a,i0,a,i0)") "line ", l, " differs at glyph ", k
                        exit
                    end if
                    worst = max(worst, abs(xs(k) - rx(k)))
                end do
                if (bad) exit
            end do
            if (.not. bad .and. worst > TOL) then
                bad = .true.
                write (what, "(a,f0.4)") "off by ", worst
            end if
        end if
        if (bad) then
            nfail = nfail + 1
            print "(a,f0.0,a,a)", "  FAIL width ", width, ": ", trim(what)
        end if
    end subroutine check_one

    pure integer function count_words(s)
        character(len=*), intent(in) :: s
        integer :: i
        logical :: inw
        count_words = 0
        inw = .false.
        do i = 1, len_trim(s)
            if (s(i:i) /= " ") then
                if (.not. inw) count_words = count_words + 1
                inw = .true.
            else
                inw = .false.
            end if
        end do
    end function count_words

end module test_typeset
