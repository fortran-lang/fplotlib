! fplotlib_hyph -- where a word may be hyphenated.
!
! Liang's algorithm, as TeX has it (The TeXbook, Appendix H; TeX: The
! Program, part 40), with the patterns LaTeX and Typst use for English
! (fplotlib_hyph_data). The word is put between two dots, every substring
! of it that is a pattern's letters contributes the pattern's digits to
! the gaps it covers, each gap keeps the largest, and a gap whose digit
! is odd may be broken. An exception, a word given with its hyphens,
! overrides the patterns. TeX's \lefthyphenmin and \righthyphenmin keep
! a break at least that many letters from either end.
module fplotlib_hyph
    use fplotlib_status
    use fplotlib_hyph_data, only: N_PATTERNS, N_EXCEPTIONS, BLOB_LEN, blob_text
    implicit none
    private

    public :: hyph_points, initialize_hyphenation

    ! The characters a digit is coded as; tools/gen_hyph.py has the same.
    character(len=*), parameter :: DIGIT_CODES = &
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ#$%()*+,-/:;<=>?@[]^_`{|}"

    logical, save :: ready = .false.
    ! Pattern i's letters are KEYS(KOFF(i) + 1:KOFF(i + 1)) and its digits
    ! DIGS(DOFF(i):DOFF(i) + its length), sorted by letters.
    character(len=:), allocatable, save :: KEYS
    integer, allocatable, save :: KOFF(:), DIGS(:), DOFF(:)
    ! The exceptions, as written (with hyphens), space separated.
    character(len=:), allocatable, save :: EXC
    integer, save :: MAXKEY = 0

contains

    subroutine initialize_hyphenation()
        if (.not. ready) call load()
    end subroutine initialize_hyphenation

    subroutine load()
        character(len=BLOB_LEN) :: s
        character(len=16) :: prev, cur
        integer :: i, n, k, m, idx, p, d, nk, nd, t
        integer :: dg(0:16)

        call blob_text(s)
        ! Front coding saves letters, so the letters take more room than
        ! the data; no pattern is longer than prev and cur.
        allocate (character(len=len(prev)*N_PATTERNS) :: KEYS)
        allocate (KOFF(N_PATTERNS + 1), DOFF(N_PATTERNS))
        allocate (DIGS((len(prev) + 1)*N_PATTERNS))
        nk = 0
        nd = 0
        n = 0
        prev = ""
        i = 1
        do while (n < N_PATTERNS)
            ! A record: the shared count, the new letters, the digits.
            k = iachar(s(i:i)) - iachar("0")
            i = i + 1
            cur = prev(1:k)
            m = k
            do while (i <= BLOB_LEN)
                if (.not. letter(s(i:i))) exit
                m = m + 1
                cur(m:m) = s(i:i)
                i = i + 1
            end do
            dg = 0
            do while (i <= BLOB_LEN)
                if (s(i:i) == "~") then
                    p = iachar(s(i + 1:i + 1)) - iachar("0")
                    d = iachar(s(i + 2:i + 2)) - iachar("0")
                    i = i + 3
                else
                    idx = index(DIGIT_CODES, s(i:i))
                    if (idx == 0) exit
                    p = (idx - 1)/6
                    d = mod(idx - 1, 6) + 1
                    i = i + 1
                end if
                dg(p) = d
            end do
            n = n + 1
            KOFF(n) = nk
            KEYS(nk + 1:nk + m) = cur(1:m)
            nk = nk + m
            DOFF(n) = nd + 1
            do t = 0, m
                DIGS(nd + 1 + t) = dg(t)
            end do
            nd = nd + m + 1
            MAXKEY = max(MAXKEY, m)
            prev = cur
        end do
        KOFF(N_PATTERNS + 1) = nk
        KEYS = KEYS(1:nk)
        ! What is left after the space are the exceptions.
        if (N_EXCEPTIONS > 0) then
            EXC = " "//trim(s(i + 1:BLOB_LEN))//" "
        else
            EXC = " "
        end if
        ready = .true.
    end subroutine load

    pure logical function letter(c)
        character, intent(in) :: c
        letter = (c >= "a" .and. c <= "z") .or. c == "."
    end function letter

    ! The pattern whose letters are k, 0 for none.
    integer function find(k) result(r)
        character(len=*), intent(in) :: k
        integer :: lo, hi, mid
        character(len=:), allocatable :: key
        lo = 1
        hi = N_PATTERNS
        r = 0
        do while (lo <= hi)
            mid = (lo + hi)/2
            key = KEYS(KOFF(mid) + 1:KOFF(mid + 1))
            if (key == k) then
                r = mid
                return
            else if (llt(key, k)) then
                lo = mid + 1
            else
                hi = mid - 1
            end if
        end do
    end function find

    ! The places word may be hyphenated: after its letter pos(1), pos(2),
    ! ..., pos(n). word is lower case; a character that is not a letter
    ! a..z matches no pattern. Breaks closer than lhm letters to the start
    ! or rhm to the end are left out, and so is every break in a word
    ! shorter than lhm + rhm, as in TeX.
    subroutine hyph_points(word, lhm, rhm, pos, n, status)
        character(len=*), intent(in) :: word
        integer, intent(in) :: lhm, rhm
        integer, intent(out) :: pos(:), n
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: w
        integer :: vals(0:len(word) + 2)
        integer :: i, j, p, t, nw, e, q, k

        n = 0
        nw = len(word)
        if (lhm < 0 .or. rhm < 0) then
            call status%set(ERROR_ARGUMENT, "hyph_points: negative minimum")
            return
        end if
        if (lhm > nw .or. rhm > nw) return
        if (lhm > nw - rhm) return
        call initialize_hyphenation()
        vals = 0

        ! An exception decides by itself.
        e = exception(word)
        if (e > 0) then
            q = 0
            do k = e, len(EXC)
                if (EXC(k:k) == " ") exit
                if (EXC(k:k) == "-") then
                    if (q >= lhm .and. nw - q >= rhm) then
                        if (n == size(pos)) then
                            call status%set(ERROR_ARGUMENT, "hyph_points: output array too small")
                            return
                        end if
                        n = n + 1
                        pos(n) = q
                    end if
                else
                    q = q + 1
                end if
            end do
            return
        end if

        w = "."//word//"."
        do i = 1, len(w)
            do j = i, min(len(w), i + MAXKEY - 1)
                p = find(w(i:j))
                if (p == 0) cycle
                do t = 0, j - i + 1
                    vals(i - 1 + t) = max(vals(i - 1 + t), DIGS(DOFF(p) + t))
                end do
            end do
        end do
        ! Gap g lies between w(g) and w(g + 1): after the word's letter g - 1.
        do q = lhm, nw - rhm
            if (mod(vals(q + 1), 2) == 1) then
                if (n == size(pos)) then
                    call status%set(ERROR_ARGUMENT, "hyph_points: output array too small")
                    return
                end if
                n = n + 1
                pos(n) = q
            end if
        end do
    end subroutine hyph_points

    ! Where word's exception starts in EXC, 0 if it has none.
    integer function exception(word) result(e)
        character(len=*), intent(in) :: word
        integer :: k, j, q
        logical :: same
        e = 0
        k = 2
        do while (k < len(EXC))
            ! An exception runs from k to the next space.
            j = k
            q = 0
            same = .true.
            do while (EXC(j:j) /= " ")
                if (EXC(j:j) /= "-") then
                    q = q + 1
                    if (q > len(word)) then
                        same = .false.
                    else if (EXC(j:j) /= word(q:q)) then
                        same = .false.
                    end if
                end if
                j = j + 1
            end do
            if (same .and. q == len(word)) then
                e = k
                return
            end if
            k = j + 1
        end do
    end function exception

end module fplotlib_hyph
