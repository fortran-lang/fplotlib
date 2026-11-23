! Unit tests for fplotlib_hyph (Liang's hyphenation with hyph-en-us).
module test_hyph
    use fplotlib_hyph, only: hyph_points
    implicit none
    private

    public :: hyph_check

contains

    subroutine hyph_check(nfail)
        integer, intent(out) :: nfail
        integer :: small(2), n

        nfail = 0

        ! Standard pattern breaks (LaTeX English defaults: lhm=2, rhm=3).
        call check("hyphenation", 2, 3, [2, 6], nfail)
        call check("algorithm", 2, 3, [2, 4], nfail)
        call check("computer", 2, 3, [3], nfail)
        call check("representation", 2, 3, [3, 5, 8, 10], nfail)
        call check("fortran", 2, 3, [3], nfail)

        ! Explicit exceptions from hyph-en-us.tex.
        call check("associate", 2, 3, [2, 4], nfail)
        call check("table", 2, 3, [2], nfail)
        call check("declination", 2, 3, [3, 5, 7], nfail)
        call check("present", 2, 3, [integer ::], nfail)
        call check("project", 2, 3, [integer ::], nfail)

        ! lhm / rhm bounds and short or non-letter inputs.
        call check("table", 3, 3, [integer ::], nfail)
        call check("computer", 2, 2, [3, 6], nfail)
        call check("", 2, 3, [integer ::], nfail)
        call check("a", 2, 3, [integer ::], nfail)
        call check("word", 2, 3, [integer ::], nfail)
        call check("123456", 2, 3, [integer ::], nfail)

        ! Respect the caller's output buffer size.
        call hyph_points("declination", 2, 3, small, n)
        if (n /= 2 .or. small(1) /= 3 .or. small(2) /= 5) then
            print "(A,I0)", "  FAIL hyph buffer cap: n=", n
            nfail = nfail + 1
        end if

        print "(A,I0)", "hyphenation: failures = ", nfail
    end subroutine hyph_check

    subroutine check(word, lhm, rhm, want, nfail)
        character(len=*), intent(in) :: word
        integer, intent(in) :: lhm, rhm, want(:)
        integer, intent(inout) :: nfail
        integer :: pos(32), n, i
        logical :: ok

        call hyph_points(word, lhm, rhm, pos, n)
        ok = n == size(want)
        if (ok) then
            do i = 1, n
                if (pos(i) /= want(i)) ok = .false.
            end do
        end if
        if (.not. ok) then
            print "(A,A,A,I0,A,I0)", "  FAIL hyph '", word, "': got ", n, " breaks, want ", size(want)
            print *, "    got: ", pos(1:n)
            print *, "    want:", want
            nfail = nfail + 1
        end if
    end subroutine check

end module test_hyph
