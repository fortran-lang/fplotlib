! fplotlib_raster — an antialiased scanline rasterizer.
!
! This is the part PNG has that the vector backends get for free: something
! has to decide what colour each pixel is. It is kept separate from the PNG
! container and from the backend so that it can be reasoned about, and tested,
! as pure geometry.
!
! Coverage is computed by signed-area accumulation rather than by supersampling.
! Each edge deposits the exact area it cuts from every pixel it crosses into an
! accumulation buffer; a running sum along the row then turns those deltas into
! coverage. Two things recommend it. The antialiasing is analytic, so a shallow
! diagonal comes out smooth instead of stepping between a fixed number of
! sample levels, which is what matplotlib's Agg does and therefore what fplotlib
! has to do to look the same. And the running sum *is* the winding number, so
! the nonzero fill rule falls out of the algorithm rather than needing sorted
! crossing lists. Overlapping contours of the same orientation saturate to one
! and opposite orientations cancel, which is exactly nonzero.
!
! The catch, and the reason to say so plainly: this gives nonzero only. Even-odd
! would need a different accumulator. fplotlib never asks for it.
!
! Everything else reduces to filling a path. Strokes are converted to outlines
! and filled; text is glyph outlines and filled; markers are a shape filled once
! per point. There is one rasterizer here, not five.

module fplotlib_raster
    use fplotlib_style, only: dp
    use fplotlib_render, only: paint_t, clip_t, VERB_MOVE, VERB_LINE, VERB_CUBIC, &
                            VERB_CLOSE, CAP_BUTT, CAP_ROUND, CAP_SQUARE, &
                            JOIN_MITER, JOIN_ROUND, JOIN_BEVEL, MAX_DASH
    implicit none
    private

    public :: canvas_t, pathbuf_t
    public :: canvas_init, canvas_rgba, canvas_free
    public :: pb_reset, pb_move, pb_line, pb_cubic, pb_close, pb_poly
    public :: pb_should_snap, pb_snap
    public :: fill_path_buf, stroke_path_buf, blit_image
    public :: clip_to_box, clip_segment

    ! A path flattened to polylines: every curve is already line segments, so
    ! the rasterizer never sees a Bezier.
    ! A subpath with a point further than FAR pixels from the origin is
    ! clipped to the canvas before it is scanned, and snapping leaves points
    ! beyond SNAP_LIMIT alone: both keep pixel positions within what a
    ! default integer holds.
    real(dp), parameter :: FAR = 1.0e8_dp, SNAP_LIMIT = 1.0e9_dp

    type :: pathbuf_t
        real(dp), allocatable :: x(:), y(:)
        integer, allocatable :: sub_beg(:), sub_len(:)
        logical, allocatable :: sub_closed(:)
        integer :: n = 0, ns = 0
    end type pathbuf_t

    type :: canvas_t
        integer :: w = 0, h = 0
        real(dp) :: scale = 1.0_dp      ! pixels per point
        real(dp), allocatable :: px(:, :, :)   ! (4, w, h), premultiplied
        real(dp), allocatable :: acc(:, :)     ! (0:w, h) area deltas
    end type canvas_t

contains

    ! ------------------------------------------------------------------
    ! Canvas
    ! ------------------------------------------------------------------

    subroutine canvas_init(cv, w, h, scale, bg_rgb, bg_alpha)
        type(canvas_t), intent(out) :: cv
        integer, intent(in) :: w, h
        real(dp), intent(in) :: scale
        integer, intent(in) :: bg_rgb(3)
        real(dp), intent(in) :: bg_alpha
        integer :: c

        cv%w = w
        cv%h = h
        cv%scale = scale
        allocate (cv%px(4, w, h))
        allocate (cv%acc(0:w, h))
        cv%acc = 0.0_dp
        ! Stored premultiplied, so the background is scaled by its own alpha.
        do c = 1, 3
            cv%px(c, :, :) = (real(bg_rgb(c), dp)/255.0_dp)*bg_alpha
        end do
        cv%px(4, :, :) = bg_alpha
    end subroutine canvas_init

    subroutine canvas_free(cv)
        type(canvas_t), intent(inout) :: cv

        if (allocated(cv%px)) deallocate (cv%px)
        if (allocated(cv%acc)) deallocate (cv%acc)
    end subroutine canvas_free

    ! Undo the premultiplication on the way out, because PNG stores straight
    ! alpha. Fully transparent pixels have no colour to recover and are left
    ! black, which is what every other encoder does.
    function canvas_rgba(cv) result(out)
        type(canvas_t), intent(in) :: cv
        integer, allocatable :: out(:, :, :)
        integer :: x, y, c
        real(dp) :: a, v

        allocate (out(4, cv%w, cv%h))
        do y = 1, cv%h
            do x = 1, cv%w
                a = cv%px(4, x, y)
                if (a <= 0.0_dp) then
                    out(:, x, y) = 0
                else
                    do c = 1, 3
                        v = cv%px(c, x, y)/a
                        out(c, x, y) = nint(min(1.0_dp, max(0.0_dp, v))*255.0_dp)
                    end do
                    out(4, x, y) = nint(min(1.0_dp, a)*255.0_dp)
                end if
            end do
        end do
    end function canvas_rgba

    ! ------------------------------------------------------------------
    ! Path building. Coordinates go in as points and come out as pixels, so
    ! the rest of the module never has to think about the scale factor.
    ! ------------------------------------------------------------------

    subroutine pb_reset(pb)
        type(pathbuf_t), intent(inout) :: pb

        pb%n = 0
        pb%ns = 0
        if (.not. allocated(pb%x)) then
            allocate (pb%x(256), pb%y(256))
            allocate (pb%sub_beg(32), pb%sub_len(32), pb%sub_closed(32))
        end if
    end subroutine pb_reset

    subroutine pb_grow(pb)
        type(pathbuf_t), intent(inout) :: pb
        real(dp), allocatable :: t(:)

        if (pb%n < size(pb%x)) return
        allocate (t(2*size(pb%x)))
        t(1:pb%n) = pb%x(1:pb%n); call move_alloc(t, pb%x)
        allocate (t(2*size(pb%y)))
        t(1:pb%n) = pb%y(1:pb%n); call move_alloc(t, pb%y)
    end subroutine pb_grow

    subroutine pb_grow_sub(pb)
        type(pathbuf_t), intent(inout) :: pb
        integer, allocatable :: t(:)
        logical, allocatable :: l(:)

        if (pb%ns < size(pb%sub_beg)) return
        allocate (t(2*size(pb%sub_beg)))
        t(1:pb%ns) = pb%sub_beg(1:pb%ns); call move_alloc(t, pb%sub_beg)
        allocate (t(2*size(pb%sub_len)))
        t(1:pb%ns) = pb%sub_len(1:pb%ns); call move_alloc(t, pb%sub_len)
        allocate (l(2*size(pb%sub_closed)))
        l(1:pb%ns) = pb%sub_closed(1:pb%ns); call move_alloc(l, pb%sub_closed)
    end subroutine pb_grow_sub

    subroutine pb_move(pb, x, y)
        type(pathbuf_t), intent(inout) :: pb
        real(dp), intent(in) :: x, y

        call pb_grow(pb)
        call pb_grow_sub(pb)
        pb%n = pb%n + 1
        pb%x(pb%n) = x
        pb%y(pb%n) = y
        pb%ns = pb%ns + 1
        pb%sub_beg(pb%ns) = pb%n
        pb%sub_len(pb%ns) = 1
        pb%sub_closed(pb%ns) = .false.
    end subroutine pb_move

    subroutine pb_line(pb, x, y)
        type(pathbuf_t), intent(inout) :: pb
        real(dp), intent(in) :: x, y

        if (pb%ns == 0) then
            call pb_move(pb, x, y)
            return
        end if
        call pb_grow(pb)
        pb%n = pb%n + 1
        pb%x(pb%n) = x
        pb%y(pb%n) = y
        pb%sub_len(pb%ns) = pb%sub_len(pb%ns) + 1
    end subroutine pb_line

    subroutine pb_close(pb)
        type(pathbuf_t), intent(inout) :: pb

        if (pb%ns > 0) pb%sub_closed(pb%ns) = .true.
    end subroutine pb_close

    ! Flatten a cubic. The segment count follows the control polygon length so
    ! that a big sweeping curve gets more segments than a marker-sized one; the
    ! ceiling keeps a pathological control net from costing thousands.
    subroutine pb_cubic(pb, x1, y1, x2, y2, x3, y3)
        type(pathbuf_t), intent(inout) :: pb
        real(dp), intent(in) :: x1, y1, x2, y2, x3, y3
        real(dp) :: x0, y0, t, mt, d
        integer :: i, n

        if (pb%ns == 0) call pb_move(pb, x1, y1)
        x0 = pb%x(pb%n)
        y0 = pb%y(pb%n)
        d = hypot(x1 - x0, y1 - y0) + hypot(x2 - x1, y2 - y1) + hypot(x3 - x2, y3 - y2)
        n = max(3, min(128, ceiling(min(d, 1000.0_dp)*0.6_dp)))
        do i = 1, n
            t = real(i, dp)/real(n, dp)
            mt = 1.0_dp - t
            call pb_line(pb, &
                         mt**3*x0 + 3.0_dp*mt*mt*t*x1 + 3.0_dp*mt*t*t*x2 + t**3*x3, &
                         mt**3*y0 + 3.0_dp*mt*mt*t*y1 + 3.0_dp*mt*t*t*y2 + t**3*y3)
        end do
    end subroutine pb_cubic

    ! Append a closed polygon, forcing the orientation. Nonzero winding unions
    ! shapes only when they turn the same way, and a stroke is built by piling
    ! quads and join wedges on top of each other, so every piece has to be
    ! wound the same way or the overlaps would cancel into holes.
    subroutine pb_poly(pb, px, py, n, negative)
        type(pathbuf_t), intent(inout) :: pb
        real(dp), intent(in) :: px(:), py(:)
        integer, intent(in) :: n
        logical, intent(in) :: negative
        real(dp) :: a
        integer :: i, j

        if (n < 3) return
        a = 0.0_dp
        do i = 1, n
            j = merge(1, i + 1, i == n)
            a = a + px(i)*py(j) - px(j)*py(i)
        end do

        if ((a < 0.0_dp) .eqv. negative) then
            call pb_move(pb, px(1), py(1))
            do i = 2, n
                call pb_line(pb, px(i), py(i))
            end do
        else
            call pb_move(pb, px(n), py(n))
            do i = n - 1, 1, -1
                call pb_line(pb, px(i), py(i))
            end do
        end if
        call pb_close(pb)
    end subroutine pb_poly

    ! ------------------------------------------------------------------
    ! Pixel snapping.
    !
    ! A one point gridline landing across two pixel columns comes out as two
    ! half-dark columns, which reads as blurred rather than thin. Matplotlib
    ! avoids this by rounding paths made only of horizontal and vertical
    ! segments onto the pixel grid, and since fplotlib is trying to look like
    ! matplotlib it has to do the same thing by the same rule: axis spines,
    ! gridlines, ticks and rectangles are exactly the paths this catches.
    !
    ! Curved or diagonal paths are left alone, because snapping them would
    ! distort the shape for no gain.
    ! ------------------------------------------------------------------

    function pb_should_snap(pb) result(yes)
        type(pathbuf_t), intent(in) :: pb
        logical :: yes
        integer :: s, b, n, i

        yes = .false.
        if (pb%n < 2 .or. pb%n > 1024) return
        do s = 1, pb%ns
            b = pb%sub_beg(s)
            n = pb%sub_len(s)
            do i = b, b + n - 2
                if (abs(pb%x(i) - pb%x(i + 1)) >= 1.0e-4_dp .and. &
                    abs(pb%y(i) - pb%y(i + 1)) >= 1.0e-4_dp) return
            end do
        end do
        yes = .true.
    end function pb_should_snap

    ! An odd number of pixels of width is centred on a pixel centre and an
    ! even number on a pixel boundary; that is the whole of the offset rule.
    subroutine pb_snap(pb, line_width_px)
        type(pathbuf_t), intent(inout) :: pb
        real(dp), intent(in) :: line_width_px
        real(dp) :: sv
        integer :: i

        sv = 0.0_dp
        if (modulo(nint(min(line_width_px, 1.0e9_dp)), 2) == 1) sv = 0.5_dp
        ! A coordinate meant to be exactly x.5 arrives as x.5 plus or minus
        ! 1e-13, and floor(x + 0.5) then picks either pixel depending on the
        ! compiler. Rounding to 1/65536 px first (exact in binary) makes it
        ! x.5 again, and every build snaps it the same way.
        ! Points far off the canvas are left where they are; they could not
        ! be snapped through an integer anyway.
        do i = 1, pb%n
            if (abs(pb%x(i)) < SNAP_LIMIT) &
                pb%x(i) = floor(anint(pb%x(i)*65536.0_dp)/65536.0_dp + 0.5_dp) + sv
            if (abs(pb%y(i)) < SNAP_LIMIT) &
                pb%y(i) = floor(anint(pb%y(i)*65536.0_dp)/65536.0_dp + 0.5_dp) + sv
        end do
    end subroutine pb_snap

    ! ------------------------------------------------------------------
    ! The accumulator.
    !
    ! One edge, deposited as area deltas. Adapted from the standard signed
    ! area method: for each scanline the edge crosses, work out how much of
    ! each pixel lies to its left and record the difference from the pixel
    ! before. x is clamped into the canvas, which is exact rather than
    ! approximate: geometry off the left edge contributes full winding to
    ! everything to its right, and that is what clamping to column zero says.
    ! ------------------------------------------------------------------

    subroutine acc_edge(cv, ax, ay, bx, by, y0b, y1b)
        type(canvas_t), intent(inout) :: cv
        real(dp), intent(in) :: ax, ay, bx, by
        integer, intent(inout) :: y0b, y1b
        real(dp) :: x0, y0, x1, y1, dir, dxdy, x, xn, dy, d, xa, xb
        real(dp) :: s, x0f, x1f, a0, am, a1, a2, xmf, x0fl, x1cl
        integer :: y, yi0, yi1, i0, i1, xi

        if (abs(ay - by) < 1.0e-12_dp) return
        if (ay < by) then
            x0 = ax; y0 = ay; x1 = bx; y1 = by; dir = 1.0_dp
        else
            x0 = bx; y0 = by; x1 = ax; y1 = ay; dir = -1.0_dp
        end if
        if (y1 <= 0.0_dp .or. y0 >= real(cv%h, dp)) return

        dxdy = (x1 - x0)/(y1 - y0)
        x = x0
        if (y0 < 0.0_dp) x = x - y0*dxdy
        yi0 = max(0, floor(max(y0, -1.0_dp)))
        yi1 = min(cv%h, ceiling(min(y1, real(cv%h + 1, dp))))
        y0b = min(y0b, yi0 + 1)
        y1b = max(y1b, yi1)

        do y = yi0, yi1 - 1
            dy = min(real(y + 1, dp), y1) - max(real(y, dp), y0)
            if (dy <= 0.0_dp) cycle
            xn = x + dxdy*dy
            d = dy*dir
            xa = min(x, xn)
            xb = max(x, xn)
            xa = min(max(xa, 0.0_dp), real(cv%w, dp))
            xb = min(max(xb, 0.0_dp), real(cv%w, dp))
            x0fl = real(floor(xa), dp)
            x1cl = real(ceiling(xb), dp)
            i0 = int(x0fl)
            i1 = int(x1cl)
            if (i0 > cv%w) i0 = cv%w
            if (i1 > cv%w) i1 = cv%w

            if (i1 <= i0 + 1) then
                ! Narrower than a pixel: split the area between two columns.
                xmf = 0.5_dp*(xa + xb) - x0fl
                cv%acc(i0, y + 1) = cv%acc(i0, y + 1) + d*(1.0_dp - xmf)
                if (i0 + 1 <= cv%w) &
                    cv%acc(i0 + 1, y + 1) = cv%acc(i0 + 1, y + 1) + d*xmf
            else
                s = 1.0_dp/(xb - xa)
                x0f = xa - x0fl
                a0 = 0.5_dp*s*(1.0_dp - x0f)**2
                x1f = xb - x1cl + 1.0_dp
                am = 0.5_dp*s*x1f**2
                cv%acc(i0, y + 1) = cv%acc(i0, y + 1) + d*a0
                if (i1 == i0 + 2) then
                    cv%acc(i0 + 1, y + 1) = cv%acc(i0 + 1, y + 1) + d*(1.0_dp - a0 - am)
                else
                    a1 = s*(1.5_dp - x0f)
                    cv%acc(i0 + 1, y + 1) = cv%acc(i0 + 1, y + 1) + d*(a1 - a0)
                    do xi = i0 + 2, i1 - 2
                        cv%acc(xi, y + 1) = cv%acc(xi, y + 1) + d*s
                    end do
                    a2 = a1 + real(i1 - i0 - 3, dp)*s
                    cv%acc(i1 - 1, y + 1) = cv%acc(i1 - 1, y + 1) + d*(1.0_dp - a2 - am)
                end if
                if (i1 <= cv%w) cv%acc(i1, y + 1) = cv%acc(i1, y + 1) + d*am
            end if
            x = xn
        end do
    end subroutine acc_edge

    ! ------------------------------------------------------------------
    ! Fill a flattened path. Subpaths are treated as closed whether or not
    ! they were declared so, because an unclosed fill is meaningless and every
    ! renderer closes it implicitly.
    ! ------------------------------------------------------------------

    subroutine fill_path_buf(cv, pb, rgb, alpha, clip)
        type(canvas_t), intent(inout) :: cv
        type(pathbuf_t), intent(in) :: pb
        integer, intent(in) :: rgb(3)
        real(dp), intent(in) :: alpha
        type(clip_t), intent(in) :: clip
        integer :: s, i, b, n, y, x, cx0, cx1, cy0, cy1, y0b, y1b, m
        real(dp) :: run, cov, sa, sr, sg, sb_, ia
        real(dp), allocatable :: cx(:), cy(:)

        if (pb%ns == 0 .or. alpha <= 0.0_dp) return

        y0b = cv%h + 1
        y1b = 0
        do s = 1, pb%ns
            b = pb%sub_beg(s)
            n = pb%sub_len(s)
            if (n < 2) cycle
            ! A subpath reaching far off the canvas is cut down to a box just
            ! around it first, which keeps every pixel's winding and every
            ! coordinate small enough for the scanline arithmetic.
            if (maxval(abs(pb%x(b:b + n - 1))) > FAR .or. maxval(abs(pb%y(b:b + n - 1))) > FAR) then
                call clip_to_box(pb%x(b:b + n - 1), pb%y(b:b + n - 1), &
                                 -2.0_dp, real(cv%w + 2, dp), -2.0_dp, real(cv%h + 2, dp), cx, cy, m)
                do i = 1, m
                    call acc_edge(cv, cx(i), cy(i), cx(mod(i, m) + 1), cy(mod(i, m) + 1), y0b, y1b)
                end do
                cycle
            end if
            do i = b, b + n - 2
                call acc_edge(cv, pb%x(i), pb%y(i), pb%x(i + 1), pb%y(i + 1), y0b, y1b)
            end do
            call acc_edge(cv, pb%x(b + n - 1), pb%y(b + n - 1), pb%x(b), pb%y(b), y0b, y1b)
        end do
        if (y1b < y0b) return

        call clip_box(cv, clip, cx0, cx1, cy0, cy1)
        sr = real(rgb(1), dp)/255.0_dp
        sg = real(rgb(2), dp)/255.0_dp
        sb_ = real(rgb(3), dp)/255.0_dp

        do y = y0b, y1b
            run = 0.0_dp
            do x = 1, cv%w
                run = run + cv%acc(x - 1, y)
                cv%acc(x - 1, y) = 0.0_dp
                if (y < cy0 .or. y > cy1 .or. x < cx0 .or. x > cx1) cycle
                cov = min(1.0_dp, abs(run))
                if (cov <= 0.0_dp) cycle
                sa = cov*alpha
                ia = 1.0_dp - sa
                cv%px(1, x, y) = sr*sa + cv%px(1, x, y)*ia
                cv%px(2, x, y) = sg*sa + cv%px(2, x, y)*ia
                cv%px(3, x, y) = sb_*sa + cv%px(3, x, y)*ia
                cv%px(4, x, y) = sa + cv%px(4, x, y)*ia
            end do
            cv%acc(cv%w, y) = 0.0_dp
        end do
    end subroutine fill_path_buf

    ! The polygon x, y (closed implicitly) cut to the box [x0, x1] by
    ! [y0, y1], one side at a time (Sutherland and Hodgman). Inside the
    ! box every point keeps the winding number it had. Crossings are found
    ! by interpolating between the two ends, which cannot overflow however
    ! far apart they are.
    subroutine clip_to_box(x, y, x0, x1, y0, y1, ox, oy, m)
        real(dp), intent(in) :: x(:), y(:), x0, x1, y0, y1
        real(dp), allocatable, intent(out) :: ox(:), oy(:)
        integer, intent(out) :: m
        real(dp), allocatable :: ax(:), ay(:)
        integer :: side

        call refine_far_edges(x, y, x0, x1, y0, y1, ox, oy, m)
        do side = 1, 4
            if (m == 0) exit
            call move_alloc(ox, ax)
            call move_alloc(oy, ay)
            call clip_side(ax(1:m), ay(1:m), side, x0, x1, y0, y1, ox, oy, m)
        end do
    end subroutine clip_to_box

    subroutine clip_side(x, y, side, x0, x1, y0, y1, ox, oy, m)
        real(dp), intent(in) :: x(:), y(:), x0, x1, y0, y1
        integer, intent(in) :: side
        real(dp), allocatable, intent(out) :: ox(:), oy(:)
        integer, intent(out) :: m
        integer :: i, j, n, u, v
        logical :: inp, inq
        real(dp) :: t, c

        n = size(x)
        allocate (ox(2*n), oy(2*n))
        m = 0
        do i = 1, n
            j = mod(i, n) + 1
            inp = inside_side(x(i), y(i), side, x0, x1, y0, y1)
            inq = inside_side(x(j), y(j), side, x0, x1, y0, y1)
            if (inp) then
                m = m + 1
                ox(m) = x(i)
                oy(m) = y(i)
            end if
            if (inp .neqv. inq) then
                ! Measured from the end nearer the side, where a fraction
                ! of a long edge is still exact.
                u = i
                v = j
                select case (side)
                case (1, 2)
                    c = merge(x0, x1, side == 1)
                    if (abs(x(j) - c) < abs(x(i) - c)) then
                        u = j
                        v = i
                    end if
                    t = crossing(x(u), x(v), c)
                case default
                    c = merge(y0, y1, side == 3)
                    if (abs(y(j) - c) < abs(y(i) - c)) then
                        u = j
                        v = i
                    end if
                    t = crossing(y(u), y(v), c)
                end select
                m = m + 1
                ox(m) = x(u)*(1.0_dp - t) + x(v)*t
                oy(m) = y(u)*(1.0_dp - t) + y(v)*t
                select case (side)
                case (1); ox(m) = x0
                case (2); ox(m) = x1
                case (3); oy(m) = y0
                case default; oy(m) = y1
                end select
            end if
        end do
    end subroutine clip_side

    ! An edge with both ends far outside the box that still passes near it
    ! is split in half until one end of every piece is near: a fraction of
    ! an edge spanning 1e300 cannot otherwise place the point where it
    ! crosses a box a few hundred wide.
    subroutine refine_far_edges(x, y, x0, x1, y0, y1, ox, oy, m)
        real(dp), intent(in) :: x(:), y(:), x0, x1, y0, y1
        real(dp), allocatable, intent(out) :: ox(:), oy(:)
        integer, intent(out) :: m
        integer :: i, j, n

        n = size(x)
        allocate (ox(max(16, 2*n)), oy(max(16, 2*n)))
        m = 0
        do i = 1, n
            j = mod(i, n) + 1
            call push_xy(ox, oy, m, x(i), y(i))
            call split_far(x(i), y(i), x(j), y(j), x0, x1, y0, y1, ox, oy, m, 0)
        end do
    end subroutine refine_far_edges

    recursive subroutine split_far(ax, ay, bx, by, x0, x1, y0, y1, ox, oy, m, depth)
        real(dp), intent(in) :: ax, ay, bx, by, x0, x1, y0, y1
        real(dp), allocatable, intent(inout) :: ox(:), oy(:)
        integer, intent(inout) :: m
        integer, intent(in) :: depth
        real(dp) :: px, py, qx, qy, mx, my
        logical :: moved_p, moved_q, lrel, rrel
        integer :: it

        if (depth > 1100) return
        if (.not. both_far(ax, ay, bx, by, x0, x1, y0, y1)) return
        ! While only one half still reaches the box, the other is dropped:
        ! its points are collinear and far away, so only the last of them
        ! needs keeping.
        px = ax; py = ay
        qx = bx; qy = by
        moved_p = .false.
        moved_q = .false.
        do it = 1, 1100
            if (.not. both_far(px, py, qx, qy, x0, x1, y0, y1)) exit
            mx = 0.5_dp*px + 0.5_dp*qx
            my = 0.5_dp*py + 0.5_dp*qy
            lrel = touches(px, py, mx, my, x0, x1, y0, y1)
            rrel = touches(mx, my, qx, qy, x0, x1, y0, y1)
            if (lrel .and. rrel) exit
            if (lrel) then
                qx = mx; qy = my
                moved_q = .true.
            else if (rrel) then
                px = mx; py = my
                moved_p = .true.
            else
                return
            end if
        end do
        if (moved_p) call push_xy(ox, oy, m, px, py)
        if (both_far(px, py, qx, qy, x0, x1, y0, y1)) then
            mx = 0.5_dp*px + 0.5_dp*qx
            my = 0.5_dp*py + 0.5_dp*qy
            call split_far(px, py, mx, my, x0, x1, y0, y1, ox, oy, m, depth + 1)
            call push_xy(ox, oy, m, mx, my)
            call split_far(mx, my, qx, qy, x0, x1, y0, y1, ox, oy, m, depth + 1)
        end if
        if (moved_q) call push_xy(ox, oy, m, qx, qy)
    end subroutine split_far

    ! Whether the bounding box of the segment meets the box.
    pure logical function touches(ax, ay, bx, by, x0, x1, y0, y1) result(r)
        real(dp), intent(in) :: ax, ay, bx, by, x0, x1, y0, y1
        r = min(ax, bx) <= x1 .and. max(ax, bx) >= x0 .and. &
            min(ay, by) <= y1 .and. max(ay, by) >= y0
    end function touches

    ! Whether both ends lie further from the box than a thousand times its
    ! size while the segment's bounding box still reaches it.
    pure logical function both_far(ax, ay, bx, by, x0, x1, y0, y1) result(r)
        real(dp), intent(in) :: ax, ay, bx, by, x0, x1, y0, y1
        real(dp) :: n
        n = 1.0e3_dp*max(x1 - x0, y1 - y0)
        r = .not. near_box(ax, ay, x0 - n, x1 + n, y0 - n, y1 + n) .and. &
            .not. near_box(bx, by, x0 - n, x1 + n, y0 - n, y1 + n) .and. &
            min(ax, bx) <= x1 .and. max(ax, bx) >= x0 .and. &
            min(ay, by) <= y1 .and. max(ay, by) >= y0
    end function both_far

    pure logical function near_box(px, py, x0, x1, y0, y1) result(r)
        real(dp), intent(in) :: px, py, x0, x1, y0, y1
        r = px >= x0 .and. px <= x1 .and. py >= y0 .and. py <= y1
    end function near_box

    subroutine push_xy(ox, oy, m, px, py)
        real(dp), allocatable, intent(inout) :: ox(:), oy(:)
        integer, intent(inout) :: m
        real(dp), intent(in) :: px, py
        real(dp), allocatable :: t(:)
        if (m + 1 > size(ox)) then
            allocate (t(2*(m + 1)))
            t(1:m) = ox(1:m)
            call move_alloc(t, ox)
            allocate (t(size(ox)))
            t(1:m) = oy(1:m)
            call move_alloc(t, oy)
        end if
        m = m + 1
        ox(m) = px
        oy(m) = py
    end subroutine push_xy

    ! The part of the segment from (x0, y0) to (x1, y1) inside the box,
    ! from (ax, ay) to (ex, ey). cut0 and cut1 say whether the start and the
    ! end were cut off. The points are found from the end nearer the box,
    ! and a segment both of whose ends are far is halved first, so that
    ! even a segment spanning the whole range of a double is placed
    ! exactly where it crosses the box.
    recursive subroutine clip_segment(x0, y0, x1, y1, bx0, bx1, by0, by1, &
                                      ax, ay, ex, ey, visible, cut0, cut1, depth)
        real(dp), intent(in) :: x0, y0, x1, y1, bx0, bx1, by0, by1
        real(dp), intent(out) :: ax, ay, ex, ey
        logical, intent(out) :: visible, cut0, cut1
        integer, intent(in), optional :: depth
        real(dp) :: ta, tb, mx, my, a2x, a2y, e2x, e2y
        logical :: v2, c20, c21
        integer :: d

        d = 0
        if (present(depth)) d = depth
        if (d < 1100 .and. both_far(x0, y0, x1, y1, bx0, bx1, by0, by1)) then
            mx = 0.5_dp*x0 + 0.5_dp*x1
            my = 0.5_dp*y0 + 0.5_dp*y1
            call clip_segment(x0, y0, mx, my, bx0, bx1, by0, by1, ax, ay, ex, ey, &
                              visible, cut0, cut1, d + 1)
            call clip_segment(mx, my, x1, y1, bx0, bx1, by0, by1, a2x, a2y, e2x, e2y, &
                              v2, c20, c21, d + 1)
            if (visible .and. v2) then
                ex = e2x
                ey = e2y
                cut1 = c21
            else if (v2) then
                ax = a2x
                ay = a2y
                ex = e2x
                ey = e2y
                visible = .true.
                cut0 = .true.
                cut1 = c21
            else if (visible) then
                cut1 = .true.
            end if
            return
        end if
        if (abs(x1 - 0.5_dp*(bx0 + bx1)) + abs(y1 - 0.5_dp*(by0 + by1)) < &
            abs(x0 - 0.5_dp*(bx0 + bx1)) + abs(y0 - 0.5_dp*(by0 + by1))) then
            ! From the second end, which is the nearer.
            call segment_in_box(x1, y1, x0, y0, bx0, bx1, by0, by1, ta, tb)
            visible = tb > ta
            ex = x1*(1.0_dp - ta) + x0*ta
            ey = y1*(1.0_dp - ta) + y0*ta
            ax = x1*(1.0_dp - tb) + x0*tb
            ay = y1*(1.0_dp - tb) + y0*tb
            cut0 = tb < 1.0_dp
            cut1 = ta > 0.0_dp
        else
            call segment_in_box(x0, y0, x1, y1, bx0, bx1, by0, by1, ta, tb)
            visible = tb > ta
            ax = x0*(1.0_dp - ta) + x1*ta
            ay = y0*(1.0_dp - ta) + y1*ta
            ex = x0*(1.0_dp - tb) + x1*tb
            ey = y0*(1.0_dp - tb) + y1*tb
            cut0 = ta > 0.0_dp
            cut1 = tb < 1.0_dp
        end if
    end subroutine clip_segment

    pure logical function inside_side(px, py, side, x0, x1, y0, y1) result(r)
        real(dp), intent(in) :: px, py, x0, x1, y0, y1
        integer, intent(in) :: side
        select case (side)
        case (1); r = px >= x0
        case (2); r = px <= x1
        case (3); r = py >= y0
        case default; r = py <= y1
        end select
    end function inside_side

    ! Where along a to b the value c is crossed, as a fraction.
    pure function crossing(a, b, c) result(t)
        real(dp), intent(in) :: a, b, c
        real(dp) :: t
        t = (0.5_dp*c - 0.5_dp*a)/(0.5_dp*b - 0.5_dp*a)
        t = max(0.0_dp, min(1.0_dp, t))
    end function crossing

    ! A position in pixels, kept within a pixel or two of the canvas, as an
    ! integer: anything further off is clipped away by the caller anyway.
    pure integer function ipix(v, n)
        real(dp), intent(in) :: v
        integer, intent(in) :: n
        ipix = nint(max(-2.0_dp, min(real(n + 2, dp), v)))
    end function ipix

    subroutine clip_box(cv, clip, x0, x1, y0, y1)
        type(canvas_t), intent(in) :: cv
        type(clip_t), intent(in) :: clip
        integer, intent(out) :: x0, x1, y0, y1

        if (clip%on) then
            x0 = max(1, ipix(clip%x*cv%scale, cv%w) + 1)
            y0 = max(1, ipix(clip%y*cv%scale, cv%h) + 1)
            x1 = min(cv%w, ipix((clip%x + clip%w)*cv%scale, cv%w))
            y1 = min(cv%h, ipix((clip%y + clip%h)*cv%scale, cv%h))
        else
            x0 = 1; y0 = 1; x1 = cv%w; y1 = cv%h
        end if
    end subroutine clip_box

    ! ------------------------------------------------------------------
    ! Stroking: turn a centreline into an outline and fill it.
    !
    ! Rather than compute one exact offset polygon, which needs self
    ! intersection handling, each segment contributes a quad and each joint a
    ! wedge, all wound the same way. Nonzero winding then unions them for
    ! free. This is both far shorter and more robust than offsetting, and the
    ! result is identical wherever the pen is round or the corner convex.
    ! ------------------------------------------------------------------

    subroutine stroke_path_buf(cv, pb, paint)
        type(canvas_t), intent(inout) :: cv
        type(pathbuf_t), intent(in) :: pb
        type(paint_t), intent(in) :: paint
        type(pathbuf_t) :: out
        real(dp), allocatable :: dx(:), dy(:)
        integer :: s, b, n, nd
        real(dp) :: hw, cover, bx0, bx1, by0, by1, reach
        logical :: walk

        hw = 0.5_dp*paint%line_width*cv%scale
        if (hw <= 0.0_dp) return
        call pb_reset(out)
        ! The box a dash has to reach into to be seen: the canvas, widened
        ! by the pen and by the corner of a square end. A corner's join, a
        ! mitre's spike included, is drawn at every point the walk passes
        ! while a dash is on, so it need not widen the box.
        reach = 1.5_dp*hw
        bx0 = -reach - 2.0_dp
        bx1 = real(cv%w, dp) + reach + 2.0_dp
        by0 = -reach - 2.0_dp
        by1 = real(cv%h, dp) + reach + 2.0_dp
        call dash_plan(paint, hw, cv%scale, walk, cover)

        do s = 1, pb%ns
            b = pb%sub_beg(s)
            n = pb%sub_len(s)
            if (n < 1) cycle
            call gather(pb, b, n, pb%sub_closed(s), dx, dy, nd)
            if (walk) then
                call stroke_dashed(out, dx, dy, nd, hw, paint, cv%scale, bx0, bx1, by0, by1, &
                                   real(cv%w, dp), real(cv%h, dp))
            else
                call stroke_run(out, dx, dy, nd, hw, paint, pb%sub_closed(s))
            end if
        end do

        call fill_path_buf(cv, out, paint%stroke_rgb, paint%stroke_alpha*cover, paint%clip)
    end subroutine stroke_path_buf

    ! Whether a dashed stroke is walked dash by dash. The one exception is a
    ! pattern finer than half a pixel, where no dash can be told apart and
    ! the line is drawn solid at the cover the pattern gives it: the share
    ! of dash in it, and with round or square ends also what the ends add,
    ! half a pen each.
    subroutine dash_plan(paint, hw, scale, walk, cover)
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: hw, scale
        logical, intent(out) :: walk
        real(dp), intent(out) :: cover
        real(dp) :: period

        walk = .false.
        cover = 1.0_dp
        if (paint%n_dash == 0) return
        period = sum(paint%dash(1:paint%n_dash))*scale
        if (period < 0.5_dp) then
            cover = on_fraction(paint)
            if (paint%cap /= CAP_BUTT) &
                cover = min(1.0_dp, cover + hw*real(paint%n_dash, dp)/max(period, tiny(1.0_dp)))
            return
        end if
        walk = .true.
    end subroutine dash_plan

    ! The share of a dash pattern that is dash rather than gap.
    pure function on_fraction(paint) result(f)
        type(paint_t), intent(in) :: paint
        real(dp) :: f, on, total
        integer :: i
        on = 0.0_dp
        total = 0.0_dp
        do i = 1, paint%n_dash
            total = total + paint%dash(i)
            if (mod(i, 2) == 1) on = on + paint%dash(i)
        end do
        ! An odd count repeats with dash and gap swapped, half and half.
        if (mod(paint%n_dash, 2) == 1) on = 0.5_dp*total
        f = 1.0_dp
        if (total > 0.0_dp) f = on/total
    end function on_fraction

    subroutine gather(pb, b, n, closed, dx, dy, nd)
        type(pathbuf_t), intent(in) :: pb
        integer, intent(in) :: b, n
        logical, intent(in) :: closed
        real(dp), allocatable, intent(out) :: dx(:), dy(:)
        integer, intent(out) :: nd

        nd = n
        if (closed) nd = n + 1
        allocate (dx(nd), dy(nd))
        dx(1:n) = pb%x(b:b + n - 1)
        dy(1:n) = pb%y(b:b + n - 1)
        if (closed) then
            dx(nd) = pb%x(b)
            dy(nd) = pb%y(b)
        end if
    end subroutine gather

    ! Walk the polyline handing out alternating on and off runs of the dash
    ! pattern. Each on run is stroked as its own open subpath, which is why
    ! dash caps are applied per dash and not per line. A segment reaching
    ! outside the box [bx0, bx1] by [by0, by1], the canvas widened by the
    ! pen, is only walked where it is inside: the rest just moves the
    ! pattern along, so that a line far longer than the canvas costs no
    ! more than one across it.
    !
    ! A pen wider than the canvas widens that box past the canvas many
    ! times over. Its dashes are then walked only where their place along
    ! the line falls within the canvas's span along it (and a cap's length
    ! beyond): a dash anywhere else cannot touch the canvas, however wide.
    subroutine stroke_dashed(out, px, py, n, hw, paint, scale, bx0, bx1, by0, by1, cw, ch)
        type(pathbuf_t), intent(inout) :: out
        real(dp), intent(in) :: px(:), py(:), hw, scale, bx0, bx1, by0, by1, cw, ch
        integer, intent(in) :: n
        type(paint_t), intent(in) :: paint
        real(dp) :: rem, seg, t0, t1, ex, ey, sx, sy, l, ta, tb
        real(dp) :: qx, qy, ax, ay, fx, fy, period, ux, uy, lp, p0, p1, ce, pk, vx, vy, q0, q1
        real(dp), allocatable :: rx(:), ry(:)
        integer :: i, di, nr, c
        logical :: on, inside, visible, cut0, cut1, wide, bare

        allocate (rx(2*n + 8), ry(2*n + 8))
        bare = .false.
        di = 1
        rem = paint%dash(1)*scale
        on = .true.
        nr = 0
        ! The pattern begins dash_offset into itself, as in SVG and PDF; a
        ! negative offset is the same distance back from a whole period.
        if (paint%dash_offset /= 0.0_dp) then
            ! In points, then scaled, so that equal phases give equal
            ! pictures to the last bit.
            period = sum(paint%dash(1:paint%n_dash))
            if (mod(paint%n_dash, 2) == 1) period = 2.0_dp*period
            if (abs(paint%dash_offset) < 1.0e15_dp*period) &
                call dash_advance(modulo(paint%dash_offset, period)*scale, paint, scale, di, rem, on)
        end if

        do i = 1, n - 1
            sx = px(i); sy = py(i)
            qx = px(i + 1); qy = py(i + 1)
            l = hypot(qx - sx, qy - sy)
            if (l <= 0.0_dp) cycle
            t0 = 0.0_dp
            tb = l
            wide = hw > max(cw, ch)
            inside = sx >= bx0 .and. sx <= bx1 .and. sy >= by0 .and. sy <= by1 .and. &
                     qx >= bx0 .and. qx <= bx1 .and. qy >= by0 .and. qy <= by1 .and. .not. wide
            if (.not. inside) then
                ! What lies outside is skipped, ending any dash under way;
                ! the walk then runs over the visible piece alone.
                call clip_segment(sx, sy, qx, qy, bx0, bx1, by0, by1, &
                                  ax, ay, fx, fy, visible, cut0, cut1)
                if (visible .and. wide) then
                    ! Narrowed to the canvas's span along the line.
                    lp = hypot(fx - ax, fy - ay)
                    if (lp > 0.0_dp) then
                        ux = (fx - ax)/lp
                        uy = (fy - ay)/lp
                        ! Round and square ends reach a pen width past
                        ! a dash, but of the dashes beyond either side
                        ! only the nearest can reach in, its end covering
                        ! all a further one could: the window takes in
                        ! one whole pattern more at most.
                        ce = 0.0_dp
                        period = sum(paint%dash(1:paint%n_dash))*scale
                        if (mod(paint%n_dash, 2) == 1) period = 2.0_dp*period
                        if (paint%cap /= CAP_BUTT) ce = min(1.5_dp*hw, period)
                        p0 = huge(1.0_dp)
                        p1 = -huge(1.0_dp)
                        do c = 0, 3
                            pk = (merge(cw, 0.0_dp, c == 1 .or. c == 2) - ax)*ux + &
                                 (merge(ch, 0.0_dp, c >= 2) - ay)*uy
                            p0 = min(p0, pk)
                            p1 = max(p1, pk)
                        end do
                        ! The nearest dash on either side is counted from
                        ! the canvas, or from the piece's own end where
                        ! the canvas lies beyond it.
                        q0 = p0 - 2.0_dp
                        q1 = p1 + 2.0_dp
                        if (paint%cap /= CAP_BUTT) then
                            q0 = min(p0, lp) - ce - 2.0_dp
                            q1 = max(p1, 0.0_dp) + ce + 2.0_dp
                        end if
                        p0 = max(0.0_dp, q0)
                        p1 = min(lp, q1)
                        if (p1 <= p0) then
                            visible = .false.
                        else
                            if (p0 > 0.0_dp) cut0 = .true.
                            if (p1 < lp) cut1 = .true.
                            fx = ax + ux*p1
                            fy = ay + uy*p1
                            ax = ax + ux*p0
                            ay = ay + uy*p0
                        end if
                    end if
                end if
                ! A dash under way goes on through an end the box does not
                ! cut, keeping its join there. Where the walk stops at the
                ! start of this segment instead, a dash running through
                ! its first point still gets the join there: a step along
                ! the segment before the run is stroked.
                if (.not. visible .or. cut0) then
                    if (on .and. nr > 0) then
                        call unit_dir(px(i), py(i), px(i + 1), py(i + 1), vx, vy)
                        nr = nr + 1
                        rx(nr) = px(i) + stub_at(px(i), py(i))*vx
                        ry(nr) = py(i) + stub_at(px(i), py(i))*vy
                        call stroke_run(out, rx, ry, nr, hw, paint, .false., bare0=bare, bare1=.true.)
                    end if
                    nr = 0
                    bare = .false.
                end if
                if (.not. visible) then
                    call dash_advance(min(l, huge(1.0_dp)), paint, scale, di, rem, on)
                    ! Unseen itself, the segment may still end in a join
                    ! that reaches the canvas: when a dash runs through
                    ! its end, not when one only starts there.
                    if (on .and. i < n - 1 .and. paint%dash(di)*scale - rem > 1.0e-12_dp) then
                        call unit_dir(px(i), py(i), px(i + 1), py(i + 1), vx, vy)
                        rx(1) = px(i + 1) - stub_at(px(i + 1), py(i + 1))*vx
                        ry(1) = py(i + 1) - stub_at(px(i + 1), py(i + 1))*vy
                        rx(2) = px(i + 1)
                        ry(2) = py(i + 1)
                        nr = 2
                        bare = .true.
                    end if
                    cycle
                end if
                call dash_advance(min(hypot(ax - sx, ay - sy), huge(1.0_dp)), paint, scale, di, rem, on)
                ! A dash under way where the walk resumes is not starting
                ! there: the run it begins gets no cap at that end.
                if (cut0 .and. on) bare = .true.
                sx = ax; sy = ay
                l = hypot(fx - ax, fy - ay)
                qx = fx; qy = fy
                tb = l
                if (l <= 0.0_dp) cycle
            end if
            do while (t0 < tb)
                seg = min(rem, tb - t0)
                t1 = t0 + seg
                ex = sx + (qx - sx)*(t1/l)
                ey = sy + (qy - sy)*(t1/l)
                if (on) then
                    if (nr == 0) then
                        nr = 1
                        rx(1) = sx + (qx - sx)*(t0/l)
                        ry(1) = sy + (qy - sy)*(t0/l)
                    end if
                    nr = nr + 1
                    rx(nr) = ex
                    ry(nr) = ey
                end if
                rem = rem - seg
                t0 = t1
                if (rem <= 1.0e-12_dp) then
                    if (on .and. nr > 1) then
                        call stroke_run(out, rx, ry, nr, hw, paint, .false., bare0=bare)
                        nr = 0
                    end if
                    bare = .false.
                    on = .not. on
                    di = di + 1
                    if (di > paint%n_dash) di = 1
                    rem = paint%dash(di)*scale
                    nr = 0
                end if
            end do
            if (.not. inside) then
                if (cut1) then
                    if (on .and. nr > 1) call stroke_run(out, rx, ry, nr, hw, paint, .false., &
                                                         bare0=bare, bare1=.true.)
                    nr = 0
                    bare = .false.
                    call dash_advance(min(hypot(px(i + 1) - qx, py(i + 1) - qy), huge(1.0_dp)), &
                                      paint, scale, di, rem, on)
                    ! A dash running on through the next point starts a
                    ! capless stub there, a step back along this segment,
                    ! so that the join at that point is drawn; a dash
                    ! that only starts there has no join.
                    if (on .and. i < n - 1 .and. paint%dash(di)*scale - rem > 1.0e-12_dp) then
                        call unit_dir(px(i), py(i), px(i + 1), py(i + 1), vx, vy)
                        rx(1) = px(i + 1) - stub_at(px(i + 1), py(i + 1))*vx
                        ry(1) = py(i + 1) - stub_at(px(i + 1), py(i + 1))*vy
                        rx(2) = px(i + 1)
                        ry(2) = py(i + 1)
                        nr = 2
                        bare = .true.
                    end if
                end if
            end if
        end do
        if (on .and. nr > 1) call stroke_run(out, rx, ry, nr, hw, paint, .false., bare0=bare)
    end subroutine stroke_dashed

    ! A step along a segment from (x, y) short enough to carry a join there
    ! without adding anything that can be seen, and long enough still to
    ! move the point: a millionth of a pixel, more where a double is
    ! coarser than that.
    pure function stub_at(x, y) result(d)
        real(dp), intent(in) :: x, y
        real(dp) :: d
        d = 1.0e-6_dp + 1.0e3_dp*epsilon(1.0_dp)*max(abs(x), abs(y))
    end function stub_at

    ! The unit vector from (x0, y0) to (x1, y1), scaled down first so that
    ! ends however far apart cannot overflow.
    pure subroutine unit_dir(x0, y0, x1, y1, ux, uy)
        real(dp), intent(in) :: x0, y0, x1, y1
        real(dp), intent(out) :: ux, uy
        real(dp) :: dx, dy, m, l
        dx = 0.5_dp*x1 - 0.5_dp*x0
        dy = 0.5_dp*y1 - 0.5_dp*y0
        m = max(abs(dx), abs(dy))
        ux = 0.0_dp
        uy = 0.0_dp
        if (m <= 0.0_dp) return
        dx = dx/m
        dy = dy/m
        l = hypot(dx, dy)
        ux = dx/l
        uy = dy/l
    end subroutine unit_dir

    ! Moves the dash pattern on by a distance d without drawing: whole
    ! periods at once, then element by element.
    subroutine dash_advance(d, paint, scale, di, rem, on)
        real(dp), intent(in) :: d, scale
        type(paint_t), intent(in) :: paint
        integer, intent(inout) :: di
        real(dp), intent(inout) :: rem
        logical, intent(inout) :: on
        real(dp) :: left, period

        left = d
        if (left < rem) then
            rem = rem - left
            return
        end if
        left = left - rem
        on = .not. on
        di = di + 1
        if (di > paint%n_dash) di = 1
        rem = paint%dash(di)*scale
        ! An odd number of lengths flips on and off each time round, so the
        ! pattern repeats only after going round twice.
        period = sum(paint%dash(1:paint%n_dash))*scale
        if (mod(paint%n_dash, 2) == 1) period = 2.0_dp*period
        if (period > 0.0_dp) then
            if (left < 1.0e15_dp*period) then
                left = mod(left, period)
            else
                ! Too far along for a double to place within the pattern.
                left = 0.0_dp
            end if
        end if
        do while (left >= rem)
            left = left - rem
            on = .not. on
            di = di + 1
            if (di > paint%n_dash) di = 1
            rem = paint%dash(di)*scale
        end do
        rem = rem - left
    end subroutine dash_advance

    ! The part of the segment from (x0, y0) to (x1, y1) inside the box, as
    ! fractions [ta, tb] of the way along it (Liang and Barsky); ta = tb
    ! when none of it is. Differences are taken of halves, so that ends
    ! far apart cannot overflow.
    pure subroutine segment_in_box(x0, y0, x1, y1, bx0, bx1, by0, by1, ta, tb)
        real(dp), intent(in) :: x0, y0, x1, y1, bx0, bx1, by0, by1
        real(dp), intent(out) :: ta, tb
        real(dp) :: p(4), q(4), r
        integer :: k

        p = [-(0.5_dp*x1 - 0.5_dp*x0), 0.5_dp*x1 - 0.5_dp*x0, &
             -(0.5_dp*y1 - 0.5_dp*y0), 0.5_dp*y1 - 0.5_dp*y0]
        q = [0.5_dp*x0 - 0.5_dp*bx0, 0.5_dp*bx1 - 0.5_dp*x0, &
             0.5_dp*y0 - 0.5_dp*by0, 0.5_dp*by1 - 0.5_dp*y0]
        ta = 0.0_dp
        tb = 1.0_dp
        do k = 1, 4
            if (p(k) == 0.0_dp) then
                if (q(k) < 0.0_dp) then
                    ta = 1.0_dp
                    tb = 1.0_dp
                    return
                end if
            else
                r = q(k)/p(k)
                if (p(k) < 0.0_dp) then
                    ta = max(ta, r)
                else
                    tb = min(tb, r)
                end if
            end if
        end do
        if (ta > tb) then
            ta = 1.0_dp
            tb = 1.0_dp
        end if
    end subroutine segment_in_box

    ! bare0 and bare1 leave the start or the end without a cap, where a run
    ! stops not because its dash does but because the walk does.
    subroutine stroke_run(out, px, py, n, hw, paint, closed, bare0, bare1)
        type(pathbuf_t), intent(inout) :: out
        real(dp), intent(in) :: px(:), py(:), hw
        integer, intent(in) :: n
        type(paint_t), intent(in) :: paint
        logical, intent(in) :: closed
        logical, intent(in), optional :: bare0, bare1
        real(dp) :: qx(4), qy(4), ux, uy, nx, ny, l
        integer :: i
        logical :: cap0, cap1

        cap0 = .true.
        cap1 = .true.
        if (present(bare0)) cap0 = .not. bare0
        if (present(bare1)) cap1 = .not. bare1

        ! A degenerate run still shows as a dot under a round pen, which is
        ! how a zero length dash draws a point.
        if (n < 2) then
            if (n == 1 .and. paint%cap == CAP_ROUND) call add_disc(out, px(1), py(1), hw)
            return
        end if

        do i = 1, n - 1
            ux = px(i + 1) - px(i)
            uy = py(i + 1) - py(i)
            l = hypot(ux, uy)
            if (l <= 0.0_dp) cycle
            ux = ux/l; uy = uy/l
            nx = -uy*hw; ny = ux*hw
            qx(1) = px(i) + nx; qy(1) = py(i) + ny
            qx(2) = px(i + 1) + nx; qy(2) = py(i + 1) + ny
            qx(3) = px(i + 1) - nx; qy(3) = py(i + 1) - ny
            qx(4) = px(i) - nx; qy(4) = py(i) - ny
            if (paint%cap == CAP_SQUARE .and. .not. closed) then
                if (i == 1 .and. cap0) then
                    qx(1) = qx(1) - ux*hw; qy(1) = qy(1) - uy*hw
                    qx(4) = qx(4) - ux*hw; qy(4) = qy(4) - uy*hw
                end if
                if (i == n - 1 .and. cap1) then
                    qx(2) = qx(2) + ux*hw; qy(2) = qy(2) + uy*hw
                    qx(3) = qx(3) + ux*hw; qy(3) = qy(3) + uy*hw
                end if
            end if
            call pb_poly(out, qx, qy, 4, .true.)
        end do

        do i = 2, n - 1
            call add_join(out, px(i - 1), py(i - 1), px(i), py(i), &
                          px(i + 1), py(i + 1), hw, paint%join, paint%miter_limit)
        end do
        if (closed .and. n > 2) then
            call add_join(out, px(n - 1), py(n - 1), px(1), py(1), px(2), py(2), &
                          hw, paint%join, paint%miter_limit)
        else if (paint%cap == CAP_ROUND) then
            if (cap0) call add_disc(out, px(1), py(1), hw)
            if (cap1) call add_disc(out, px(n), py(n), hw)
        end if
    end subroutine stroke_run

    ! The wedge that fills the outer side of a corner. The inner side needs
    ! nothing: the two segment quads already overlap there.
    !
    ! With n1 and n2 the outward unit normals, the two offset edges meet at
    ! b + v*2*hw/|v|**2 where v = n1 + n2, since |v| is twice the cosine of the
    ! half angle. That ratio 2/|v| is also the miter length in pen widths,
    ! which is exactly what the miter limit bounds, so it is tested directly
    ! and the join falls back to a bevel when the corner is too sharp.
    subroutine add_join(out, ax, ay, bx, by, cx, cy, hw, join, miter_limit)
        type(pathbuf_t), intent(inout) :: out
        real(dp), intent(in) :: ax, ay, bx, by, cx, cy, hw, miter_limit
        integer, intent(in) :: join
        real(dp) :: u1x, u1y, u2x, u2y, l1, l2, cross, s, vx, vy, vl
        real(dp) :: n1x, n1y, n2x, n2y
        real(dp) :: tx(4), ty(4)

        u1x = bx - ax; u1y = by - ay
        l1 = hypot(u1x, u1y)
        u2x = cx - bx; u2y = cy - by
        l2 = hypot(u2x, u2y)
        if (l1 <= 0.0_dp .or. l2 <= 0.0_dp) return
        u1x = u1x/l1; u1y = u1y/l1
        u2x = u2x/l2; u2y = u2y/l2
        cross = u1x*u2y - u1y*u2x
        if (abs(cross) < 1.0e-12_dp) return

        if (join == JOIN_ROUND) then
            call add_disc(out, bx, by, hw)
            return
        end if

        s = -sign(1.0_dp, cross)
        n1x = s*(-u1y); n1y = s*u1x
        n2x = s*(-u2y); n2y = s*u2x

        tx(1) = bx; ty(1) = by
        tx(2) = bx + n1x*hw; ty(2) = by + n1y*hw

        if (join == JOIN_MITER) then
            vx = n1x + n2x
            vy = n1y + n2y
            vl = hypot(vx, vy)
            if (vl > 1.0e-12_dp .and. 2.0_dp/vl <= miter_limit) then
                tx(3) = bx + vx*2.0_dp*hw/(vl*vl)
                ty(3) = by + vy*2.0_dp*hw/(vl*vl)
                tx(4) = bx + n2x*hw; ty(4) = by + n2y*hw
                call pb_poly(out, tx, ty, 4, .true.)
                return
            end if
        end if

        tx(3) = bx + n2x*hw; ty(3) = by + n2y*hw
        call pb_poly(out, tx(1:3), ty(1:3), 3, .true.)
    end subroutine add_join

    subroutine add_disc(out, cx, cy, r)
        type(pathbuf_t), intent(inout) :: out
        real(dp), intent(in) :: cx, cy, r
        real(dp), allocatable :: px(:), py(:)
        real(dp), parameter :: TWOPI = 6.283185307179586_dp
        integer :: i, n

        n = max(8, min(64, ceiling(min(r, 100.0_dp)*4.0_dp)))
        allocate (px(n), py(n))
        do i = 1, n
            px(i) = cx + r*cos(TWOPI*real(i - 1, dp)/real(n, dp))
            py(i) = cy + r*sin(TWOPI*real(i - 1, dp)/real(n, dp))
        end do
        call pb_poly(out, px, py, n, .true.)
    end subroutine add_disc

    ! ------------------------------------------------------------------
    ! Images. Nearest neighbour, which is what imshow asks for by default and
    ! the only sampling that leaves data values visibly untouched.
    ! ------------------------------------------------------------------

    subroutine blit_image(cv, x, y, w, h, rgba, nx, ny, alpha, clip)
        type(canvas_t), intent(inout) :: cv
        real(dp), intent(in) :: x, y, w, h, alpha
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(4, nx, ny)
        type(clip_t), intent(in) :: clip
        integer :: px0, px1, py0, py1, ix, iy, sx, sy, cx0, cx1, cy0, cy1
        real(dp) :: sa, ia, u, v

        call clip_box(cv, clip, cx0, cx1, cy0, cy1)
        px0 = max(cx0, ipix(x*cv%scale, cv%w) + 1)
        py0 = max(cy0, ipix(y*cv%scale, cv%h) + 1)
        px1 = min(cx1, ipix((x + w)*cv%scale, cv%w))
        py1 = min(cy1, ipix((y + h)*cv%scale, cv%h))

        do iy = py0, py1
            v = (real(iy, dp) - 0.5_dp)/cv%scale - y
            sy = min(ny, max(1, int(max(-1.0_dp, min(1.0_dp, v/h))*real(ny, dp)) + 1))
            do ix = px0, px1
                u = (real(ix, dp) - 0.5_dp)/cv%scale - x
                sx = min(nx, max(1, int(max(-1.0_dp, min(1.0_dp, u/w))*real(nx, dp)) + 1))
                sa = alpha*real(rgba(4, sx, sy), dp)/255.0_dp
                if (sa <= 0.0_dp) cycle
                ia = 1.0_dp - sa
                cv%px(1, ix, iy) = real(rgba(1, sx, sy), dp)/255.0_dp*sa + cv%px(1, ix, iy)*ia
                cv%px(2, ix, iy) = real(rgba(2, sx, sy), dp)/255.0_dp*sa + cv%px(2, ix, iy)*ia
                cv%px(3, ix, iy) = real(rgba(3, sx, sy), dp)/255.0_dp*sa + cv%px(3, ix, iy)*ia
                cv%px(4, ix, iy) = sa + cv%px(4, ix, iy)*ia
            end do
        end do
    end subroutine blit_image

end module fplotlib_raster
