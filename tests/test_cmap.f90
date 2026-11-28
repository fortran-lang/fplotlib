! Unit tests for Fabio Crameri's Scientific Colour Maps in fplotlib_cmap.
module test_cmap
    use fplotlib
    use fplotlib_cmap, only: CMAP_COUNT, CMAP_VIRIDIS, CMAP_REVERSED, &
                             cmap_from_str, cmap_name, cmap_rgb, cmap_color
    implicit none
    private

    public :: cmap_check

contains

    subroutine cmap_check(nfail)
        integer, intent(out) :: nfail
        character(len=7), parameter :: CRAMERI(36) = [ &
            "batlow ", "batlowW", "batlowK", "oslo   ", "lajolla", "bilbao ", &
            "devon  ", "turku  ", "tokyo  ", "lapaz  ", "davos  ", "acton  ", &
            "nuuk   ", "hawaii ", "imola  ", "buda   ", "bamako ", "grayC  ", &
            "oleron ", "fes    ", "vik    ", "roma   ", "berlin ", "lisbon ", &
            "tofino ", "bam    ", "broc   ", "cork   ", "vanimo ", "managua", &
            "bukavu ", "romaO  ", "brocO  ", "corkO  ", "vikO   ", "bamO   "]
        integer :: i, id, id_lo, id_up, id_rev, id_rev_ci
        integer :: r0, g0, b0, r1, g1, b1, rm, gm, bm
        integer :: rr0, gr0, br0, rr1, gr1, br1, rrm, grm, brm
        character(len=16) :: lo, up, rev_name, rev_ci
        real(dp) :: z(8, 8)
        character(len=:), allocatable :: svg1, svg2, png1
        integer :: ix, iy

        nfail = 0

        ! 1) All 36 Crameri colormaps exist, resolve case-insensitively,
        !    and support _r / _R reversed lookup with swapped endpoints.
        do i = 1, size(CRAMERI)
            id = cmap_from_str(trim(CRAMERI(i)))
            if (id == CMAP_VIRIDIS .or. id < 0 .or. id >= CMAP_COUNT) then
                print *, "FAIL cmap_check: missing ", trim(CRAMERI(i))
                nfail = nfail + 1
                cycle
            end if
            if (trim(cmap_name(id)) /= trim(CRAMERI(i))) then
                print *, "FAIL cmap_check: name mismatch for ", trim(CRAMERI(i)), &
                    " got ", trim(cmap_name(id))
                nfail = nfail + 1
            end if

            call make_lower(trim(CRAMERI(i)), lo)
            call make_upper(trim(CRAMERI(i)), up)
            id_lo = cmap_from_str(trim(lo))
            id_up = cmap_from_str(trim(up))
            if (id_lo /= id .or. id_up /= id) then
                print *, "FAIL cmap_check: case-insensitive lookup failed for ", &
                    trim(CRAMERI(i))
                nfail = nfail + 1
            end if

            rev_name = trim(CRAMERI(i))//"_r"
            rev_ci = trim(up)//"_R"
            id_rev = cmap_from_str(trim(rev_name))
            id_rev_ci = cmap_from_str(trim(rev_ci))
            if (id_rev /= id + CMAP_REVERSED .or. id_rev_ci /= id_rev) then
                print *, "FAIL cmap_check: reversed lookup failed for ", trim(rev_name)
                nfail = nfail + 1
            end if
            if (trim(cmap_name(id_rev)) /= trim(rev_name)) then
                print *, "FAIL cmap_check: reversed name mismatch for ", trim(rev_name)
                nfail = nfail + 1
            end if

            call cmap_rgb(id, 0.0_dp, r0, g0, b0)
            call cmap_rgb(id, 0.5_dp, rm, gm, bm)
            call cmap_rgb(id, 1.0_dp, r1, g1, b1)
            call cmap_rgb(id_rev, 0.0_dp, rr0, gr0, br0)
            call cmap_rgb(id_rev, 0.5_dp, rrm, grm, brm)
            call cmap_rgb(id_rev, 1.0_dp, rr1, gr1, br1)
            if (rr0 /= r1 .or. gr0 /= g1 .or. br0 /= b1) then
                print *, "FAIL cmap_check: rev(0) /= fwd(1) for ", trim(CRAMERI(i))
                nfail = nfail + 1
            end if
            if (rr1 /= r0 .or. gr1 /= g0 .or. br1 /= b0) then
                print *, "FAIL cmap_check: rev(1) /= fwd(0) for ", trim(CRAMERI(i))
                nfail = nfail + 1
            end if
            if (rrm /= rm .or. grm /= gm .or. brm /= bm) then
                print *, "FAIL cmap_check: rev(0.5) /= fwd(0.5) for ", trim(CRAMERI(i))
                nfail = nfail + 1
            end if
        end do

        ! 2) Check exact reference RGB anchors for representative Crameri maps.
        call check_rgb("batlow", 0.0_dp, 1, 25, 89, nfail)
        call check_rgb("batlow", 0.5_dp, 130, 130, 49, nfail)
        call check_rgb("batlow", 1.0_dp, 250, 204, 250, nfail)
        call check_rgb("batlowW", 0.0_dp, 1, 25, 89, nfail)
        call check_rgb("batlowW", 1.0_dp, 255, 254, 254, nfail)
        call check_rgb("batlowW_r", 0.0_dp, 255, 254, 254, nfail)
        call check_rgb("batlowW_r", 1.0_dp, 1, 25, 89, nfail)
        call check_rgb("vik", 0.0_dp, 0, 18, 97, nfail)
        call check_rgb("vik", 0.5_dp, 236, 229, 224, nfail)
        call check_rgb("vik", 1.0_dp, 89, 0, 8, nfail)
        call check_rgb("romaO", 0.0_dp, 115, 57, 87, nfail)
        call check_rgb("romaO", 0.5_dp, 203, 225, 179, nfail)
        call check_rgb("romaO", 1.0_dp, 114, 57, 89, nfail)
        call check_rgb("romaO_r", 0.0_dp, 114, 57, 89, nfail)
        call check_rgb("grayC", 0.0_dp, 0, 0, 0, nfail)
        call check_rgb("grayC", 1.0_dp, 255, 255, 255, nfail)

        if (cmap_color(cmap_from_str("batlow"), 0.0_dp) /= "#011959") then
            print *, "FAIL cmap_check: batlow(0) hex mismatch"
            nfail = nfail + 1
        end if

        ! 3) Render plots using Crameri colormaps and verify output.
        do iy = 1, 8
            do ix = 1, 8
                z(ix, iy) = real(ix + iy - 2, dp) / 14.0_dp
            end do
        end do
        call clf()
        call figure(figsize=[4.0_dp, 3.0_dp])
        call imshow(z, cmap="batlow")
        call colorbar()
        svg1 = render_svg()
        png1 = render_png()
        if (len(svg1) < 500 .or. index(svg1, "</svg>") == 0) then
            print *, "FAIL cmap_check: invalid SVG for batlow"
            nfail = nfail + 1
        end if
        if (len(png1) < 200 .or. index(png1, achar(137)//"PNG") /= 1) then
            print *, "FAIL cmap_check: invalid PNG for batlow"
            nfail = nfail + 1
        end if

        call clf()
        call figure(figsize=[4.0_dp, 3.0_dp])
        call imshow(z, cmap="batlow_r")
        call colorbar()
        svg2 = render_svg()
        if (svg1 == svg2) then
            print *, "FAIL cmap_check: batlow and batlow_r rendered identically"
            nfail = nfail + 1
        end if

        print '(A,I0,A,I0)', "crameri colormaps: ", size(CRAMERI), " maps, failures = ", nfail
    end subroutine cmap_check

    subroutine check_rgb(name, t, er, eg, eb, nfail)
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: t
        integer, intent(in) :: er, eg, eb
        integer, intent(inout) :: nfail
        integer :: r, g, b
        call cmap_rgb(cmap_from_str(name), t, r, g, b)
        if (r /= er .or. g /= eg .or. b /= eb) then
            print *, "FAIL cmap_check: ", trim(name), " at ", t, &
                " expected ", er, eg, eb, " got ", r, g, b
            nfail = nfail + 1
        end if
    end subroutine check_rgb

    subroutine make_lower(s, out)
        character(len=*), intent(in) :: s
        character(len=*), intent(out) :: out
        integer :: i, ic
        out = ""
        do i = 1, len(s)
            ic = iachar(s(i:i))
            if (ic >= iachar('A') .and. ic <= iachar('Z')) then
                out(i:i) = achar(ic + 32)
            else
                out(i:i) = s(i:i)
            end if
        end do
    end subroutine make_lower

    subroutine make_upper(s, out)
        character(len=*), intent(in) :: s
        character(len=*), intent(out) :: out
        integer :: i, ic
        out = ""
        do i = 1, len(s)
            ic = iachar(s(i:i))
            if (ic >= iachar('a') .and. ic <= iachar('z')) then
                out(i:i) = achar(ic - 32)
            else
                out(i:i) = s(i:i)
            end if
        end do
    end subroutine make_upper

end module test_cmap
