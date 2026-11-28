! fplotlib_sixel — DEC Sixel terminal graphics encoder.
!
! Sixel encodes a palette-indexed raster image as printable ASCII wrapped in
! a Device Control String (DCS): ESC P 0;1 q ... ESC \. Each graphics line
! covers six vertical rows of pixels, with one pass per colour present in
! that 6-row band and run-length encoding (!<count><char>) for runs of four
! or more identical sixels.
!
! Palette quantization reuses the median-cut quantizer from fplotlib_gif so
! that Sixel and GIF share the exact same 256-colour reduction.

module fplotlib_sixel
    use fplotlib_gif, only: build_palette, bucket, NBUCKET, NPAL
    implicit none
    private

    public :: sixel_encode

    type :: sbuf_t
        character(len=:), allocatable :: s
        integer :: n = 0
        integer :: cap = 0
    end type sbuf_t

contains

    subroutine sbuf_reserve(buf, extra)
        type(sbuf_t), intent(inout) :: buf
        integer, intent(in) :: extra
        character(len=:), allocatable :: tmp
        integer :: need, newcap

        need = buf%n + extra
        if (need <= buf%cap) return
        if (buf%cap == 0) then
            newcap = max(65536, need)
            allocate (character(len=newcap) :: buf%s)
            buf%cap = newcap
            return
        end if
        newcap = max(2*buf%cap, need)
        allocate (character(len=newcap) :: tmp)
        if (buf%n > 0) tmp(1:buf%n) = buf%s(1:buf%n)
        call move_alloc(tmp, buf%s)
        buf%cap = newcap
    end subroutine sbuf_reserve

    subroutine sbuf_put_str(buf, text)
        type(sbuf_t), intent(inout) :: buf
        character(len=*), intent(in) :: text
        integer :: m

        m = len(text)
        if (m == 0) return
        call sbuf_reserve(buf, m)
        buf%s(buf%n + 1:buf%n + m) = text
        buf%n = buf%n + m
    end subroutine sbuf_put_str

    subroutine sbuf_put_char(buf, ch)
        type(sbuf_t), intent(inout) :: buf
        character(len=1), intent(in) :: ch

        call sbuf_reserve(buf, 1)
        buf%n = buf%n + 1
        buf%s(buf%n:buf%n) = ch
    end subroutine sbuf_put_char

    subroutine sbuf_put_int(buf, v)
        type(sbuf_t), intent(inout) :: buf
        integer, intent(in) :: v
        character(len=16) :: num

        write (num, "(I0)") v
        call sbuf_put_str(buf, trim(num))
    end subroutine sbuf_put_int

    subroutine emit_run(buf, ch, count)
        type(sbuf_t), intent(inout) :: buf
        character(len=1), intent(in) :: ch
        integer, intent(in) :: count
        integer :: k

        if (count <= 0) return
        if (count >= 4) then
            call sbuf_put_char(buf, "!")
            call sbuf_put_int(buf, count)
            call sbuf_put_char(buf, ch)
        else
            do k = 1, count
                call sbuf_put_char(buf, ch)
            end do
        end if
    end subroutine emit_run

    ! Encode a w-by-h packed RGB buffer (len = 3*w*h, row-major top to bottom)
    ! as a DEC Sixel byte stream.
    function sixel_encode(w, h, pix) result(out)
        integer, intent(in) :: w, h
        character(len=*), intent(in) :: pix
        character(len=:), allocatable :: out
        character(len=1), parameter :: ESC = achar(27)
        character(len=1), parameter :: BS = achar(92)
        type(sbuf_t) :: buf
        integer :: pal(3, 0:NPAL - 1)
        integer, allocatable :: map(:), ind(:), band(:, :), masks(:)
        logical, allocatable :: used(:)
        integer :: npix, ncolors, i, x, y0, dy, rows, c, base, r, g, b
        integer :: rp, gp, bp, last_x, run_len, mask
        character(len=1) :: run_ch, cur_ch
        logical :: first_in_band

        ! DCS introducer: P1=0, P2=1 (leave unwritten pixels untouched), q
        ! Raster attributes: "1;1;w;h (1:1 square pixel aspect ratio)
        call sbuf_put_str(buf, ESC//"P0;1q""1;1;")
        call sbuf_put_int(buf, max(w, 0))
        call sbuf_put_char(buf, ";")
        call sbuf_put_int(buf, max(h, 0))

        if (w <= 0 .or. h <= 0) then
            call sbuf_put_str(buf, ESC//BS)
            out = buf%s(1:buf%n)
            return
        end if

        npix = w*h
        allocate (map(0:NBUCKET - 1), ind(npix))
        call build_palette(pix, npix, pal, map, ncolors)

        do i = 1, npix
            base = 3*(i - 1)
            r = iachar(pix(base + 1:base + 1))
            g = iachar(pix(base + 2:base + 2))
            b = iachar(pix(base + 3:base + 3))
            ind(i) = map(bucket(r, g, b))
        end do

        ! Define RGB colour registers (0..100 integer percentages).
        do c = 0, ncolors - 1
            rp = (pal(1, c)*100 + 127)/255
            gp = (pal(2, c)*100 + 127)/255
            bp = (pal(3, c)*100 + 127)/255
            call sbuf_put_char(buf, "#")
            call sbuf_put_int(buf, c)
            call sbuf_put_str(buf, ";2;")
            call sbuf_put_int(buf, rp)
            call sbuf_put_char(buf, ";")
            call sbuf_put_int(buf, gp)
            call sbuf_put_char(buf, ";")
            call sbuf_put_int(buf, bp)
        end do

        allocate (band(w, 0:5), masks(w), used(0:ncolors - 1))

        do y0 = 1, h, 6
            rows = min(6, h - y0 + 1)
            used = .false.
            do dy = 0, rows - 1
                base = (y0 + dy - 1)*w
                do x = 1, w
                    c = ind(base + x)
                    band(x, dy) = c
                    used(c) = .true.
                end do
            end do

            first_in_band = .true.
            do c = 0, ncolors - 1
                if (.not. used(c)) cycle
                if (.not. first_in_band) call sbuf_put_char(buf, "$")
                first_in_band = .false.

                call sbuf_put_char(buf, "#")
                call sbuf_put_int(buf, c)

                last_x = 0
                do x = 1, w
                    mask = 0
                    do dy = 0, rows - 1
                        if (band(x, dy) == c) mask = ior(mask, ishft(1, dy))
                    end do
                    masks(x) = mask
                    if (mask /= 0) last_x = x
                end do

                if (last_x > 0) then
                    run_ch = achar(63 + masks(1))
                    run_len = 1
                    do x = 2, last_x
                        cur_ch = achar(63 + masks(x))
                        if (cur_ch == run_ch) then
                            run_len = run_len + 1
                        else
                            call emit_run(buf, run_ch, run_len)
                            run_ch = cur_ch
                            run_len = 1
                        end if
                    end do
                    call emit_run(buf, run_ch, run_len)
                end if
            end do

            if (y0 + 6 <= h) call sbuf_put_char(buf, "-")
        end do

        ! String terminator: ESC \
        call sbuf_put_str(buf, ESC//BS)
        out = buf%s(1:buf%n)
    end function sixel_encode

end module fplotlib_sixel
