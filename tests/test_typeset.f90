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
    use fplotlib_style, only: dp, utf8_next
    use fplotlib_typeset, only: typeset_context_t, ts_reset, ts_set_page, ts_set_font, &
                                ts_begin_par, &
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
        call check_interleaved(nfail)
        print "(a,i0,a,i0,a)", "paragraph refs: ", npar, " paragraphs, ", nfail, &
            " differ from XeTeX"
    end subroutine para_ref_check

    ! Two contexts used interleaved produce the same lines as one used alone.
    subroutine check_interleaved(nfail)
        integer, intent(inout) :: nfail
        type(typeset_context_t) :: alone, a, b
        character(len=*), parameter :: p1 = &
            "When Donald Knuth received the galley proofs of the second edition of his book "// &
            "on algorithms in 1977, he was dismayed by the uneven spacing and typography."
        character(len=*), parameter :: p2 = &
            "A different paragraph set at a narrower width while the first context is open."
        integer, allocatable :: g0(:), g1(:)
        real(dp), allocatable :: x0(:), x1(:)
        integer :: nl0, nl1, l, n0, n1, k

        call set_par(alone, p1, 220.0_dp, 15.0_dp, finish=.true.)
        call set_par(a, p1, 220.0_dp, 15.0_dp, finish=.false.)
        call set_par(b, p2, 140.0_dp, 0.0_dp, finish=.true.)
        call ts_end_par(a)

        nl0 = ts_line_count(alone)
        nl1 = ts_line_count(a)
        if (nl0 /= nl1 .or. nl0 == 0) then
            print "(a,i0,a,i0)", "  FAIL interleaved contexts: lines ", nl1, " vs ", nl0
            nfail = nfail + 1
            return
        end if
        do l = 1, nl0
            call ts_line_info(alone, l, g0, x0, n0)
            call ts_line_info(a, l, g1, x1, n1)
            if (n0 /= n1) then
                print "(a,i0,a,i0,a,i0)", "  FAIL interleaved line ", l, ": ", n1, " vs ", n0
                nfail = nfail + 1
                return
            end if
            do k = 1, n0
                if (g0(k) /= g1(k) .or. abs(x0(k) - x1(k)) > 1.0e-12_dp) then
                    print "(a,i0,a,i0)", "  FAIL interleaved line ", l, " glyph ", k
                    nfail = nfail + 1
                    return
                end if
            end do
        end do
    end subroutine check_interleaved

    subroutine set_par(ts, text, width, indent, finish)
        type(typeset_context_t), intent(inout) :: ts
        character(len=*), intent(in) :: text
        real(dp), intent(in) :: width, indent
        logical, intent(in) :: finish
        integer :: i, j
        call ts_set_page(ts, width, 10000.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp)
        call ts_set_font(ts, SIZE)
        call ts_begin_par(ts, ALIGN_JUSTIFY, indent)
        i = 1
        do while (i <= len(text))
            j = index(text(i:), " ")
            if (j == 0) then
                j = len(text) + 1
            else
                j = i + j - 1
            end if
            if (j > i) call ts_word(ts, text(i:j - 1), FACE_REGULAR, SIZE)
            if (j <= len(text)) call ts_space(ts, FACE_REGULAR, SIZE)
            i = j + 1
        end do
        if (finish) call ts_end_par(ts)
    end subroutine set_par

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
        character(len=64) :: what
        type(typeset_context_t) :: ts

        call ts_reset(ts)
        call ts_set_page(ts, width, 10000.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp)
        call ts_set_font(ts, SIZE)
        call ts_begin_par(ts, ALIGN_JUSTIFY, indent)
        i = 1
        do while (i <= len(text))
            j = index(text(i:), " ")
            if (j == 0) then
                j = len(text) + 1
            else
                j = i + j - 1
            end if
            if (j > i) call ts_word(ts, text(i:j - 1), FACE_REGULAR, SIZE)
            if (j <= len(text)) call ts_space(ts, FACE_REGULAR, SIZE)
            i = j + 1
        end do
        call ts_end_par(ts)

        bad = .false.
        worst = 0.0_dp
        what = ""
        if (ts_line_count(ts) /= nl) then
            bad = .true.
            write (what, "(a,i0,a,i0)") "lines ", ts_line_count(ts), " vs ", nl
        else
            do l = 1, nl
                call ts_line_info(ts, l, gids, xs, n)
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
