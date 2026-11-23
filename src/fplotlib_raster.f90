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
! Even-odd needs no other accumulator: the running sum is the winding number,
! and even-odd keeps its parity, folding |w| into [0, 1] as a triangle wave
! (w mod 2, mirrored past 1) where nonzero clamps it at 1, as Vello does. Both
! are exact where a pixel is wholly inside or outside every edge. At a pixel
! that edges cross, each takes the sum of their signed areas for the area of
! what they cover: under nonzero, overlapping contours there can saturate a
! pixel only partly covered; under even-odd, two contours along the same line
! sum to a whole winding where neither covers more than part of the pixel.
!
! That is why an even-odd fill is never clipped as geometry, as nonzero is in
! a frame: cut to a clip, every contour gains an edge along the clip's
! border, and under even-odd two of them there would draw a solid line. An
! even-odd fill under a clip in a frame (a frame's clip, or a paint clip in a
! transformed frame) is filled whole and its coverage multiplied by the
! clip's, an antialiased mask over the rows the fill reaches. The product
! is exact inside the clip and where only one of the two edges crosses a
! pixel; where both cross the same pixel it can be off by up to a quarter
! of the pixel either way: a quarter for two halves that coincide, where a
! half is covered, and a quarter for a shape that ends just where the clip
! begins, where nothing is.
!
! Everything else reduces to filling a path. Strokes are converted to outlines
! and filled; text is glyph outlines and filled; markers are a shape filled once
! per point. There is one rasterizer here, not five.

module fplotlib_raster
    use fplotlib_style, only: dp
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use fplotlib_status, only: contract_error
    use fplotlib_render, only: paint_t, clip_t, VERB_MOVE, VERB_LINE, VERB_CUBIC, &
                            VERB_CLOSE, CAP_BUTT, CAP_ROUND, CAP_SQUARE, &
                            JOIN_MITER, JOIN_ROUND, JOIN_BEVEL, MAX_DASH
    implicit none
    private

    public :: canvas_t, pathbuf_t
    public :: canvas_init, canvas_rgba, canvas_free
    public :: canvas_begin_frame, canvas_end_frame
    public :: pb_reset, pb_move, pb_line, pb_cubic, pb_close, pb_poly
    public :: pb_should_snap, pb_snap
    public :: fill_path_buf, stroke_path_buf, blit_image
    public :: clip_to_box, clip_segment
    public :: full_walk

    ! For tests only: true walks every dash of every stroke in full,
    ! without leaving out anything that cannot be seen, so that a test can
    ! compare what the shortcuts draw with what they stand for.
    logical :: full_walk = .false.

    real(dp), parameter :: IDENTITY(6) = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp]

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
        real(dp) :: curve_scale = 1.0_dp
    end type pathbuf_t

    type :: raster_frame_t
        real(dp) :: matrix(6) = IDENTITY
        logical :: clipped = .false.
        real(dp) :: clip_x(4) = 0.0_dp, clip_y(4) = 0.0_dp
    end type raster_frame_t

    type :: canvas_t
        integer :: w = 0, h = 0
        real(dp) :: scale = 1.0_dp      ! pixels per point
        real(dp), allocatable :: px(:, :, :)   ! (4, w, h), premultiplied
        real(dp), allocatable :: acc(:, :)     ! (0:w, h) area deltas
        ! Geometry and stroke outlines stay in local pixels until filling.
        ! Ancestor clips are frozen in device pixels when their frames open.
        real(dp) :: matrix(6) = IDENTITY
        logical :: identity_transform = .true.
        real(dp) :: curve_scale = 1.0_dp
        integer :: n_frame = 0, n_clip = 0
        type(raster_frame_t), allocatable :: frames(:)
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
        if (allocated(cv%frames)) deallocate (cv%frames)
    end subroutine canvas_free

    ! The matrix acts on local pixels; clip coordinates, like paint clips,
    ! are points in the same local, origin-shifted coordinate system.
    subroutine canvas_begin_frame(cv, matrix, clip)
        type(canvas_t), intent(inout) :: cv
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        type(raster_frame_t), allocatable :: grown(:)
        real(dp) :: p(6), m(6), qx(4), qy(4)

        if (.not. allocated(cv%px)) call contract_error("raster: begin_frame outside canvas")
        if (.not. allocated(cv%frames)) allocate (cv%frames(8))
        if (cv%n_frame == size(cv%frames)) then
            allocate (grown(2*cv%n_frame))
            grown(1:cv%n_frame) = cv%frames(1:cv%n_frame)
            call move_alloc(grown, cv%frames)
        end if
        p = cv%matrix
        m(1) = p(1)*matrix(1) + p(3)*matrix(2)
        m(2) = p(2)*matrix(1) + p(4)*matrix(2)
        m(3) = p(1)*matrix(3) + p(3)*matrix(4)
        m(4) = p(2)*matrix(3) + p(4)*matrix(4)
        m(5) = p(1)*matrix(5) + p(3)*matrix(6) + p(5)
        m(6) = p(2)*matrix(5) + p(4)*matrix(6) + p(6)
        ! Frames nested so deep that together they stretch or move by more
        ! than 1e100 place nothing they hold, as a shape whose place is past
        ! the largest double is left out: a matrix of zeros draws nothing.
        ! Below that, every point a frame holds, within MAX_COORD, maps to
        ! a finite one.
        if (.not. all(ieee_is_finite(m))) m = 0.0_dp
        if (any(abs(m) > 1.0e100_dp)) m = 0.0_dp
        call set_transform(cv, m)
        cv%n_frame = cv%n_frame + 1
        cv%frames(cv%n_frame)%matrix = m
        cv%frames(cv%n_frame)%clipped = clip%on
        if (clip%on) then
            call transformed_rect(cv, clip, qx, qy)
            cv%frames(cv%n_frame)%clip_x = qx
            cv%frames(cv%n_frame)%clip_y = qy
            cv%n_clip = cv%n_clip + 1
        end if
    end subroutine canvas_begin_frame

    subroutine canvas_end_frame(cv)
        type(canvas_t), intent(inout) :: cv
        real(dp) :: matrix(6)

        if (cv%n_frame == 0) call contract_error("raster: unmatched end_frame")
        if (cv%frames(cv%n_frame)%clipped) cv%n_clip = cv%n_clip - 1
        cv%n_frame = cv%n_frame - 1
        matrix = IDENTITY
        if (cv%n_frame > 0) matrix = cv%frames(cv%n_frame)%matrix
        call set_transform(cv, matrix)
    end subroutine canvas_end_frame

    subroutine set_transform(cv, matrix)
        type(canvas_t), intent(inout) :: cv
        real(dp), intent(in) :: matrix(6)
        real(dp) :: u, v, dot

        cv%matrix = matrix
        cv%identity_transform = all(matrix == IDENTITY)
        ! The largest singular value controls subdivision only, never pen
        ! width: the entire local outline receives the full affine map.
        u = matrix(1)**2 + matrix(2)**2
        v = matrix(3)**2 + matrix(4)**2
        dot = matrix(1)*matrix(3) + matrix(2)*matrix(4)
        cv%curve_scale = max(1.0_dp, sqrt(0.5_dp*(u + v + hypot(u - v, 2.0_dp*dot))))
    end subroutine set_transform

    ! The corners of the canvas widened by two pixels on every side, in the
    ! coordinates of the current frame, which its matrix maps onto the
    ! canvas: a point outside them touches no pixel. False for a matrix that
    ! maps everything onto a line or a point, where nothing drawn can be
    ! seen. Corners too far off for a double are left infinite.
    logical function local_canvas(cv, kx, ky) result(ok)
        type(canvas_t), intent(in) :: cv
        real(dp), intent(out) :: kx(4), ky(4)
        real(dp) :: m(6), det, dx(4), dy(4)

        m = cv%matrix
        det = m(1)*m(4) - m(2)*m(3)
        ok = det /= 0.0_dp
        kx = 0.0_dp
        ky = 0.0_dp
        if (.not. ok) return
        dx = [-2.0_dp, cv%w + 2.0_dp, cv%w + 2.0_dp, -2.0_dp] - m(5)
        dy = [-2.0_dp, -2.0_dp, cv%h + 2.0_dp, cv%h + 2.0_dp] - m(6)
        kx = (m(4)*dx - m(3)*dy)/det
        ky = (m(1)*dy - m(2)*dx)/det
    end function local_canvas

    ! The most matrix stretches a length by: the larger singular value of
    ! its 2 by 2 part.
    pure function max_stretch(matrix) result(smax)
        real(dp), intent(in) :: matrix(6)
        real(dp) :: smax, u, v, dot
        u = matrix(1)**2 + matrix(2)**2
        v = matrix(3)**2 + matrix(4)**2
        dot = matrix(1)*matrix(3) + matrix(2)*matrix(4)
        smax = sqrt(0.5_dp*(u + v + hypot(u - v, 2.0_dp*dot)))
    end function max_stretch

    subroutine transformed_rect(cv, clip, x, y)
        type(canvas_t), intent(in) :: cv
        type(clip_t), intent(in) :: clip
        real(dp), intent(out) :: x(4), y(4)
        real(dp) :: lx(4), ly(4)

        if (clip%w <= 0.0_dp .or. clip%h <= 0.0_dp) then
            x = 0.0_dp
            y = 0.0_dp
            return
        end if
        lx = [clip%x, clip%x + clip%w, clip%x + clip%w, clip%x]*cv%scale
        ly = [clip%y, clip%y, clip%y + clip%h, clip%y + clip%h]*cv%scale
        x = cv%matrix(1)*lx + cv%matrix(3)*ly + cv%matrix(5)
        y = cv%matrix(2)*lx + cv%matrix(4)*ly + cv%matrix(6)
    end subroutine transformed_rect

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
        ! As many segments as the curve is long on the canvas, a frame's
        ! scale included, up to the most a curve gets.
        n = max(3, min(128, ceiling(min(d*pb%curve_scale, 1000.0_dp)*0.6_dp)))
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
        ! Taken about the first point: about the origin, the terms of a
        ! piece far from it, as in a frame moved far, are so large that
        ! their sum is rounding, and its sign no orientation at all.
        a = 0.0_dp
        do i = 2, n
            j = merge(1, i + 1, i == n)
            a = a + (px(i) - px(1))*(py(j) - py(1)) - (px(j) - px(1))*(py(i) - py(1))
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
        integer :: y, yi0, yi1

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
            if (xa >= 0.0_dp .and. xb <= real(cv%w, dp)) then
                call deposit(cv, y, xa, xb, d)
            else
                ! A piece of the edge crossing the left or right side of
                ! the canvas is cut there, its height shared out by length:
                ! what lies left of the canvas winds every pixel of the row,
                ! a step at column zero, and what lies right of it none.
                ! Clamping the two ends instead would tilt the piece and
                ! spread its coverage along the row.
                if (xb > xa) then
                    if (xa < 0.0_dp) call deposit(cv, y, 0.0_dp, 0.0_dp, d*(min(xb, 0.0_dp) - xa)/(xb - xa))
                    if (xb > 0.0_dp .and. xa < real(cv%w, dp)) &
                        call deposit(cv, y, max(xa, 0.0_dp), min(xb, real(cv%w, dp)), &
                                     d*(min(xb, real(cv%w, dp)) - max(xa, 0.0_dp))/(xb - xa))
                else if (xa < 0.0_dp) then
                    call deposit(cv, y, 0.0_dp, 0.0_dp, d)
                end if
            end if
            x = xn
        end do
    end subroutine acc_edge

    ! The area deltas of one piece of an edge within one row: from xa to
    ! xb, both inside [0, w], with d its signed height in the row.
    subroutine deposit(cv, y, xa, xb, d)
        type(canvas_t), intent(inout) :: cv
        integer, intent(in) :: y
        real(dp), intent(in) :: xa, xb, d
        real(dp) :: s, x0f, x1f, a0, am, a1, a2, xmf, x0fl, x1cl
        integer :: i0, i1, xi

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
    end subroutine deposit

    ! ------------------------------------------------------------------
    ! Fill a flattened path. Subpaths are treated as closed whether or not
    ! they were declared so, because an unclosed fill is meaningless and every
    ! renderer closes it implicitly.
    ! ------------------------------------------------------------------

    ! Fill pb with the nonzero rule, or with even-odd when evenodd is given
    ! and true.
    subroutine fill_path_buf(cv, pb, rgb, alpha, clip, evenodd)
        type(canvas_t), intent(inout) :: cv
        type(pathbuf_t), intent(in) :: pb
        integer, intent(in) :: rgb(3)
        real(dp), intent(in) :: alpha
        type(clip_t), intent(in) :: clip
        logical, intent(in), optional :: evenodd
        integer :: s, i, b, n, y, x, cx0, cx1, cy0, cy1, y0b, y1b, m, j, ylo, yhi
        real(dp) :: run, cov, sa, sr, sg, sb_, ia
        real(dp), allocatable :: cx(:), cy(:), mask(:, :)
        logical :: scoped, odd, masked, empty

        if (pb%ns == 0 .or. alpha <= 0.0_dp) return
        odd = .false.
        if (present(evenodd)) odd = evenodd

        scoped = .not. cv%identity_transform .or. cv%n_clip > 0
        masked = .false.
        if (scoped .and. odd) then
            masked = clip%on
            do j = 1, cv%n_frame
                if (cv%frames(j)%clipped) masked = .true.
            end do
        end if
        if (masked) then
            ! The clip's coverage over the rows the fill can reach.
            call path_rows(cv, pb, ylo, yhi)
            if (yhi < ylo) return
            call clip_mask(cv, clip, ylo, yhi, mask, empty)
            if (empty) return
        end if
        y0b = cv%h + 1
        y1b = 0
        if (scoped) then
            ! In a transformed or clipped frame: mapped to the canvas, cut
            ! to the frames' clips, and only then accumulated; or, for an
            ! even-odd fill under a clip, accumulated whole for the mask.
            call acc_transformed_path(cv, pb, clip, y0b, y1b, unclipped=masked)
        else
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
        end if
        if (y1b < y0b) return

        if (scoped) then
            cx0 = 1; cx1 = cv%w
            cy0 = 1; cy1 = cv%h
        else
            call clip_box(cv, clip, cx0, cx1, cy0, cy1)
        end if
        sr = real(rgb(1), dp)/255.0_dp
        sg = real(rgb(2), dp)/255.0_dp
        sb_ = real(rgb(3), dp)/255.0_dp

        do y = y0b, y1b
            run = 0.0_dp
            do x = 1, cv%w
                run = run + cv%acc(x - 1, y)
                cv%acc(x - 1, y) = 0.0_dp
                if (y < cy0 .or. y > cy1 .or. x < cx0 .or. x > cx1) cycle
                if (odd) then
                    ! |run| folded into [0, 1], worked out past 1 only:
                    ! a pixel at a winding of 0 or 1 is as nonzero has it.
                    cov = abs(run)
                    if (cov > 1.0_dp) then
                        cov = cov - 2.0_dp*aint(0.5_dp*cov)
                        if (cov > 1.0_dp) cov = 2.0_dp - cov
                    end if
                    if (masked) then
                        if (y < ylo .or. y > yhi) then
                            cov = 0.0_dp
                        else
                            cov = cov*mask(x, y)
                        end if
                    end if
                else
                    cov = min(1.0_dp, abs(run))
                end if
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

    ! The rows ylo to yhi the fill of pb can reach once mapped onto the
    ! canvas: those its points span, within the canvas.
    subroutine path_rows(cv, pb, ylo, yhi)
        type(canvas_t), intent(in) :: cv
        type(pathbuf_t), intent(in) :: pb
        integer, intent(out) :: ylo, yhi
        real(dp) :: ymin, ymax, yy
        integer :: s, i

        ymin = huge(1.0_dp)
        ymax = -huge(1.0_dp)
        do s = 1, pb%ns
            ! Fewer than three points fill nothing, as the fill skips them.
            if (pb%sub_len(s) < 3) cycle
            do i = pb%sub_beg(s), pb%sub_beg(s) + pb%sub_len(s) - 1
                yy = cv%matrix(2)*pb%x(i) + cv%matrix(4)*pb%y(i) + cv%matrix(6)
                ymin = min(ymin, yy)
                ymax = max(ymax, yy)
            end do
        end do
        ylo = 1
        yhi = 0
        ! A path wholly above or below the canvas reaches no row of it; the
        ! rest is clamped to the canvas before it becomes an integer.
        if (ymax < ymin .or. ymax <= 0.0_dp .or. ymin >= real(cv%h, dp)) return
        ylo = max(1, floor(max(0.0_dp, ymin)) + 1)
        yhi = min(cv%h, ceiling(min(real(cv%h, dp), ymax)))
    end subroutine path_rows

    ! The coverage, from 0 to 1, of the region every clip open now leaves
    ! visible, the frames' clips and clip, as an antialiased mask over the
    ! rows ylo to yhi: mask(x, y) for y in ylo..yhi. The region is cut to
    ! those rows first, so that the mask costs no more than the fill.
    ! empty when nothing there is visible.
    subroutine clip_mask(cv, clip, ylo, yhi, mask, empty)
        type(canvas_t), intent(inout) :: cv
        type(clip_t), intent(in) :: clip
        integer, intent(in) :: ylo, yhi
        real(dp), allocatable, intent(out) :: mask(:, :)
        logical, intent(out) :: empty
        real(dp), allocatable :: x(:), y(:)
        real(dp) :: qx(4), qy(4), run
        integer :: n, i, j, y0b, y1b, px, py

        allocate (mask(cv%w, ylo:yhi))
        mask = 0.0_dp
        empty = .true.
        allocate (x(4), y(4))
        x = [-2.0_dp, real(cv%w + 2, dp), real(cv%w + 2, dp), -2.0_dp]
        y = [real(ylo - 1, dp), real(ylo - 1, dp), real(yhi, dp), real(yhi, dp)]
        n = 4
        do j = 1, cv%n_frame
            if (.not. cv%frames(j)%clipped) cycle
            call clip_polygon(x, y, n, cv%frames(j)%clip_x, cv%frames(j)%clip_y)
            if (n < 3) return
        end do
        if (clip%on) then
            call transformed_rect(cv, clip, qx, qy)
            call clip_polygon(x, y, n, qx, qy)
        end if
        if (n < 3) return
        empty = .false.
        y0b = cv%h + 1
        y1b = 0
        do i = 1, n
            call acc_edge(cv, x(i), y(i), x(mod(i, n) + 1), y(mod(i, n) + 1), y0b, y1b)
        end do
        do py = max(1, y0b), min(cv%h, y1b)
            run = 0.0_dp
            do px = 1, cv%w
                run = run + cv%acc(px - 1, py)
                cv%acc(px - 1, py) = 0.0_dp
                if (py >= ylo .and. py <= yhi) mask(px, py) = min(1.0_dp, abs(run))
            end do
            cv%acc(cv%w, py) = 0.0_dp
        end do
    end subroutine clip_mask

    ! With unclipped, the frames' clips and clip are left to the caller.
    subroutine acc_transformed_path(cv, pb, clip, y0b, y1b, unclipped)
        type(canvas_t), intent(inout) :: cv
        type(pathbuf_t), intent(in) :: pb
        type(clip_t), intent(in) :: clip
        integer, intent(inout) :: y0b, y1b
        logical, intent(in), optional :: unclipped
        real(dp), allocatable :: x(:), y(:), cx(:), cy(:)
        real(dp) :: qx(4), qy(4)
        integer :: s, b, n, i, j
        logical :: cut

        cut = .true.
        if (present(unclipped)) cut = .not. unclipped

        if (cv%matrix(1)*cv%matrix(4) - cv%matrix(2)*cv%matrix(3) == 0.0_dp) return
        if (clip%on) call transformed_rect(cv, clip, qx, qy)
        do s = 1, pb%ns
            b = pb%sub_beg(s)
            n = pb%sub_len(s)
            if (n < 3) cycle
            allocate (x(n), y(n))
            x = cv%matrix(1)*pb%x(b:b + n - 1) + cv%matrix(3)*pb%y(b:b + n - 1) + cv%matrix(5)
            y = cv%matrix(2)*pb%x(b:b + n - 1) + cv%matrix(4)*pb%y(b:b + n - 1) + cv%matrix(6)
            ! Far off the canvas once mapped onto it: cut down as any path is.
            if (maxval(abs(x)) > FAR .or. maxval(abs(y)) > FAR) then
                call clip_to_box(x, y, -2.0_dp, real(cv%w + 2, dp), -2.0_dp, real(cv%h + 2, dp), cx, cy, n)
                call move_alloc(cx, x)
                call move_alloc(cy, y)
                if (n < 3) then
                    deallocate (x, y)
                    cycle
                end if
            end if
            if (cut) then
                do j = 1, cv%n_frame
                    if (.not. cv%frames(j)%clipped) cycle
                    call clip_polygon(x, y, n, cv%frames(j)%clip_x, cv%frames(j)%clip_y)
                    if (n < 3) exit
                end do
                if (clip%on .and. n >= 3) call clip_polygon(x, y, n, qx, qy)
            end if
            if (n >= 3) then
                do i = 1, n - 1
                    call acc_edge(cv, x(i), y(i), x(i + 1), y(i + 1), y0b, y1b)
                end do
                call acc_edge(cv, x(n), y(n), x(1), y(1), y0b, y1b)
            end if
            deallocate (x, y)
        end do
    end subroutine acc_transformed_path

    ! Clip each contour against convex frame rectangles before accumulating
    ! coverage. This intersects geometry, rather than multiplying unrelated
    ! antialias masks, and preserves holes and reflected winding.
    subroutine clip_polygon(x, y, n, qx, qy)
        real(dp), allocatable, intent(inout) :: x(:), y(:)
        integer, intent(inout) :: n
        real(dp), intent(in) :: qx(4), qy(4)
        real(dp), allocatable :: tx(:), ty(:)
        real(dp) :: orientation, dx, dy, sx, sy, ex, ey, ds, de, t
        integer :: edge, next, i, nn

        if (n < 3) return
        orientation = (qx(2) - qx(1))*(qy(4) - qy(1)) - (qy(2) - qy(1))*(qx(4) - qx(1))
        if (orientation == 0.0_dp) then
            n = 0
            return
        end if
        orientation = sign(1.0_dp, orientation)
        do edge = 1, 4
            next = mod(edge, 4) + 1
            dx = qx(next) - qx(edge)
            dy = qy(next) - qy(edge)
            allocate (tx(2*n), ty(2*n))
            nn = 0
            sx = x(n); sy = y(n)
            ds = orientation*(dx*(sy - qy(edge)) - dy*(sx - qx(edge)))
            do i = 1, n
                ex = x(i); ey = y(i)
                de = orientation*(dx*(ey - qy(edge)) - dy*(ex - qx(edge)))
                if ((ds >= 0.0_dp) .neqv. (de >= 0.0_dp)) then
                    t = ds/(ds - de)
                    nn = nn + 1
                    tx(nn) = sx + t*(ex - sx)
                    ty(nn) = sy + t*(ey - sy)
                end if
                if (de >= 0.0_dp) then
                    nn = nn + 1
                    tx(nn) = ex
                    ty(nn) = ey
                end if
                sx = ex; sy = ey
                ds = de
            end do
            call move_alloc(tx, x)
            call move_alloc(ty, y)
            n = nn
            if (n < 3) return
        end do
    end subroutine clip_polygon

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
        real(dp) :: hw, cover, bx0, bx1, by0, by1, reach, kx(4), ky(4), margin, stretch
        type(pathbuf_t) :: solid
        logical :: walk

        hw = 0.5_dp*paint%line_width*cv%scale
        if (hw <= 0.0_dp) return
        call pb_reset(out)
        out%curve_scale = cv%curve_scale
        ! The box a dash has to reach into to be seen: the canvas, widened
        ! by the pen and by the corner of a square end. A corner's join, a
        ! mitre's spike included, is drawn at every point the walk passes
        ! while a dash is on, so it need not widen the box.
        reach = 1.5_dp*hw
        if (cv%identity_transform) then
            bx0 = -reach - 2.0_dp
            bx1 = real(cv%w, dp) + reach + 2.0_dp
            by0 = -reach - 2.0_dp
            by1 = real(cv%h, dp) + reach + 2.0_dp
            kx = [0.0_dp, real(cv%w, dp), real(cv%w, dp), 0.0_dp]
            ky = [0.0_dp, 0.0_dp, real(cv%h, dp), real(cv%h, dp)]
            margin = 2.0_dp
            stretch = 1.0_dp
        else
            ! The stroke is built in a frame's own coordinates, which the
            ! frame's matrix maps onto the canvas. The box is the canvas, two
            ! pixels out, on the canvas; stroke_dashed widens each of its
            ! sides by the pen as the matrix stretches that axis. kx, ky are
            ! the same box's corners in frame coordinates, which hold every
            ! point that touches a pixel: no margin is added to them.
            if (.not. local_canvas(cv, kx, ky)) return
            margin = 0.0_dp
            stretch = max_stretch(cv%matrix)
            bx0 = -2.0_dp
            bx1 = real(cv%w, dp) + 2.0_dp
            by0 = -2.0_dp
            by1 = real(cv%h, dp) + 2.0_dp
            call pb_reset(solid)
            solid%curve_scale = cv%curve_scale
        end if
        call dash_plan(paint, hw, cv%scale, stretch, walk, cover)
        if (full_walk .and. paint%n_dash > 0) then
            walk = .true.
            cover = 1.0_dp
        end if

        do s = 1, pb%ns
            b = pb%sub_beg(s)
            n = pb%sub_len(s)
            if (n < 1) cycle
            call gather(pb, b, n, pb%sub_closed(s), dx, dy, nd)
            if (walk .and. cv%identity_transform) then
                call stroke_dashed(out, dx, dy, nd, hw, paint, cv%scale, bx0, bx1, by0, by1, &
                                   kx, ky, margin)
            else if (walk) then
                call stroke_dashed(out, dx, dy, nd, hw, paint, cv%scale, bx0, bx1, by0, by1, &
                                   kx, ky, margin, cv%matrix, solid, reach)
            else
                call stroke_run(out, dx, dy, nd, hw, paint, pb%sub_closed(s))
            end if
        end do

        call fill_path_buf(cv, out, paint%stroke_rgb, paint%stroke_alpha*cover, paint%clip)
        ! In a frame, the segments the matrix shrinks so far that their
        ! pattern is finer than half a pixel on the canvas: solid, at the
        ! cover the pattern gives.
        if (walk .and. .not. cv%identity_transform) then
            if (.not. full_walk) then
                call dash_plan(paint, hw, cv%scale, 0.0_dp, walk, cover)
                call fill_path_buf(cv, solid, paint%stroke_rgb, paint%stroke_alpha*cover, paint%clip)
            end if
        end if
    end subroutine stroke_path_buf

    ! Whether a dashed stroke is walked dash by dash. The one exception is
    ! a pattern finer than half a pixel, where no dash can be told apart:
    ! the line is drawn solid at the cover the pattern gives, the share of
    ! dash in it and, with round or square ends, what the ends add, half a
    ! pen each.
    ! stretch is the most a frame's transform magnifies a length by, 1
    ! without one: a pattern is too fine to see once it is on the canvas.
    subroutine dash_plan(paint, hw, scale, stretch, walk, cover)
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: hw, scale, stretch
        logical, intent(out) :: walk
        real(dp), intent(out) :: cover
        real(dp) :: period

        walk = .false.
        cover = 1.0_dp
        if (paint%n_dash == 0) return
        period = sum(paint%dash(1:paint%n_dash))*scale
        ! An odd number of lengths repeats only after going round twice.
        if (mod(paint%n_dash, 2) == 1) period = 2.0_dp*period
        if (period*stretch < 0.5_dp) then
            ! The ends add a pen's width to each dash, and a round of the
            ! lengths holds n_dash/2 dashes, whether or not it repeats
            ! after one round or two.
            cover = on_fraction(paint)
            if (paint%cap /= CAP_BUTT) cover = min(1.0_dp, cover + hw*real(paint%n_dash, dp) &
                                               /max(sum(paint%dash(1:paint%n_dash))*scale, tiny(1.0_dp)))
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
    !
    ! In a frame, matrix maps the stroke's coordinates onto the canvas, and
    ! [bx0, bx1] by [by0, by1] is a box on the canvas, which each side
    ! widened by the pen's reach as the matrix stretches its axis. A segment
    ! is cut where it leaves that box, found in the frame's own coordinates
    ! from where along the segment each side is crossed, so nothing is
    ! taken back through the inverse of the matrix. A segment whose dashes
    ! the matrix makes stripes less than half a pixel apart on the canvas
    ! is not walked but added to solid, to be drawn at the cover the
    ! pattern gives, as a whole stroke that fine is.
    subroutine stroke_dashed(out, px, py, n, hw, paint, scale, bx0, bx1, by0, by1, kx, ky, margin, &
                             matrix, solid, reach)
        type(pathbuf_t), intent(inout) :: out
        real(dp), intent(in) :: px(:), py(:), hw, scale, bx0, bx1, by0, by1
        ! The canvas's corners in the stroke's coordinates, and two canvas
        ! pixels in them; in a frame, the corners of the canvas two pixels
        ! wider all round, and no margin.
        real(dp), intent(in) :: kx(4), ky(4), margin
        integer, intent(in) :: n
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: matrix(6)
        type(pathbuf_t), intent(inout), optional :: solid
        ! The pen's reach in the frame's coordinates.
        real(dp), intent(in), optional :: reach
        real(dp) :: period_px, ca, cb, ext, d, room
        ! What is left of a dash too short to count, a trillionth of a
        ! canvas pixel: in a frame that stretches, divided by the most it
        ! stretches, and a trillionth of a unit in one that does not.
        real(dp) :: tol
        real(dp), allocatable :: zx(:), zy(:)
        integer :: nz
        logical :: framed
        real(dp) :: rem, seg, t0, t1, ex, ey, sx, sy, l, ta, tb
        real(dp) :: qx, qy, ax, ay, fx, fy, period, ux, uy, lp, p0, p1, pk, vx, vy
        real(dp), allocatable :: rx(:), ry(:)
        integer :: i, di, nr, c
        logical :: on, inside, visible, cut0, cut1, wide, bare

        allocate (rx(2*n + 8), ry(2*n + 8))
        framed = present(matrix)
        nz = 0
        tol = 1.0e-12_dp
        if (framed) tol = 1.0e-12_dp/max(max_stretch(matrix), 1.0_dp)
        if (framed) then
            allocate (zx(n), zy(n))
            period_px = sum(paint%dash(1:paint%n_dash))*scale
            if (mod(paint%n_dash, 2) == 1) period_px = 2.0_dp*period_px
        end if
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
            if (framed) then
                call frame_cut(matrix, sx, sy, qx, qy, bx0, bx1, by0, by1, reach, ca, cb)
                ! Narrowed further to the dashes that can reach the canvas
                ! at all: those whose place along the line falls within the
                ! span of the widened canvas's corners along it, and a cap's
                ! length beyond. Every point a dash covers has its dash's
                ! place along the line, whatever the pen and the matrix do
                ! across it, and a point that touches a pixel lies within
                ! those corners. Left as cut where they are too far off.
                if (.not. full_walk .and. all(ieee_is_finite(kx)) .and. all(ieee_is_finite(ky))) then
                    ux = (qx - sx)/l
                    uy = (qy - sy)/l
                    p0 = huge(1.0_dp)
                    p1 = -huge(1.0_dp)
                    do c = 1, 4
                        pk = (kx(c) - sx)*ux + (ky(c) - sy)*uy
                        p0 = min(p0, pk)
                        p1 = max(p1, pk)
                    end do
                    ext = 0.0_dp
                    if (paint%cap /= CAP_BUTT) ext = hw
                    ca = max(ca, (p0 - ext)/l)
                    cb = min(cb, (p1 + ext)/l)
                end if
                ! Solid, ending any dash under way here as a cut does: a
                ! segment whose dashes cross the canvas as stripes less than
                ! half a pixel apart. The stripes are where the pattern
                ! stands still, the segment's normal n as the matrix maps
                ! it, a period apart along the segment: |det| over |M n|
                ! of a period apart across. Never more than along the
                ! segment, |M u| a period, and the same without a frame.
                ! Stripes at least half a pixel apart cross the canvas,
                ! two pixels wider all round, at most 2(W + H + 8) + 2
                ! times, and a cap reaches at most 100 periods further at
                ! either end: so the count of periods walked, the second
                ! test, is only a guard, which no such segment exceeds.
                ! Only a matrix whose canvas corners are past the largest
                ! double, which leaves the span along the line uncut, can
                ! make it apply, and that matrix squeezes the pen to far
                ! less than a level of one pixel.
                if (.not. full_walk .and. (period_px*abs(matrix(1)*matrix(4) - matrix(2)*matrix(3))*l &
                                           < 0.5_dp*hypot(matrix(3)*(qx - sx) - matrix(1)*(qy - sy), &
                                                          matrix(4)*(qx - sx) - matrix(2)*(qy - sy)) &
                                           .or. (min(cb, 1.0_dp) - max(ca, 0.0_dp))*l > &
                                           (2.0_dp*(bx1 - bx0 + by1 - by0) + 1000.0_dp)*period_px)) then
                    ! A dash under way through the segment's first point
                    ! ends there with the join, as at a cut: a step along
                    ! this segment, without a cap. After a solid segment the
                    ! solid run already holds the join, and the stub begun
                    ! for a walk that did not come is dropped.
                    if (on .and. nr > 0 .and. nz == 0) then
                        call unit_dir(px(i), py(i), px(i + 1), py(i + 1), vx, vy)
                        d = stub_len(px(i), py(i), min(rem, l))
                        nr = nr + 1
                        rx(nr) = px(i) + d*vx
                        ry(nr) = py(i) + d*vy
                        call stroke_run(out, rx, ry, nr, hw, paint, .false., bare0=bare, bare1=.true.)
                    end if
                    nr = 0
                    bare = .false.
                    if (nz == 0) then
                        nz = 1
                        zx(1) = sx
                        zy(1) = sy
                    end if
                    nz = nz + 1
                    zx(nz) = qx
                    zy(nz) = qy
                    call dash_advance(min(l, huge(1.0_dp)), paint, scale, di, rem, on)
                    ! And a dash running on through its last point into a
                    ! segment that is walked starts there with the join: a
                    ! capless stub a step back along this segment.
                    if (on .and. i < n - 1 .and. paint%dash(di)*scale - rem > tol) then
                        call unit_dir(px(i), py(i), px(i + 1), py(i + 1), vx, vy)
                        d = stub_len(px(i + 1), py(i + 1), min(paint%dash(di)*scale - rem, l))
                        rx(1) = px(i + 1) - d*vx
                        ry(1) = py(i + 1) - d*vy
                        rx(2) = px(i + 1)
                        ry(2) = py(i + 1)
                        nr = 2
                        bare = .true.
                    end if
                    cycle
                end if
                if (nz > 1) call stroke_run(solid, zx, zy, nz, hw, paint, .false.)
                nz = 0
            end if
            t0 = 0.0_dp
            tb = l
            ! Only butt ends: their dashes never overlap, so leaving out the
            ! ones that cannot reach changes no pixel even where coverage is
            ! summed. Round and square ends overlap and are walked in full
            ! within the box, which their pen, at most MAX_PEN_PER_DASH
            ! patterns wide, keeps to a bounded number of dashes.
            wide = hw > max(maxval(kx) - minval(kx), maxval(ky) - minval(ky)) .and. &
                   paint%cap == CAP_BUTT .and. .not. full_walk
            if (framed) then
                ! ca, cb: where the segment is cut, found above.
                inside = (ca <= 0.0_dp .and. cb >= 1.0_dp .and. .not. wide) .or. full_walk
            else
                inside = (sx >= bx0 .and. sx <= bx1 .and. sy >= by0 .and. sy <= by1 .and. &
                          qx >= bx0 .and. qx <= bx1 .and. qy >= by0 .and. qy <= by1 .and. .not. wide) &
                         .or. full_walk
            end if
            if (.not. inside) then
                ! What lies outside is skipped, ending any dash under way;
                ! the walk then runs over the visible piece alone.
                if (framed) then
                    ! Each end of the piece is found from the nearer end of
                    ! the segment, where a fraction of it is still exact.
                    ca = max(ca, 0.0_dp)
                    cb = min(cb, 1.0_dp)
                    visible = ca < cb
                    cut0 = ca > 0.0_dp
                    cut1 = cb < 1.0_dp
                    call along(sx, sy, qx, qy, ca, ax, ay)
                    call along(sx, sy, qx, qy, cb, fx, fy)
                else
                    call clip_segment(sx, sy, qx, qy, bx0, bx1, by0, by1, &
                                      ax, ay, fx, fy, visible, cut0, cut1)
                end if
                if (visible .and. wide) then
                    ! Narrowed to the canvas's span along the line.
                    lp = hypot(fx - ax, fy - ay)
                    if (lp > 0.0_dp) then
                        ux = (fx - ax)/lp
                        uy = (fy - ay)/lp
                        p0 = huge(1.0_dp)
                        p1 = -huge(1.0_dp)
                        do c = 0, 3
                            pk = (kx(c + 1) - ax)*ux + (ky(c + 1) - ay)*uy
                            p0 = min(p0, pk)
                            p1 = max(p1, pk)
                        end do
                        p0 = max(0.0_dp, p0 - margin)
                        p1 = min(lp, p1 + margin)
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
                        ! Within the dash and short of where the walk
                        ! resumes, so that it stays where nothing is seen.
                        room = min(rem, l)
                        if (visible) room = min(room, hypot(ax - px(i), ay - py(i)))
                        d = stub_len(px(i), py(i), room)
                        nr = nr + 1
                        rx(nr) = px(i) + d*vx
                        ry(nr) = py(i) + d*vy
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
                    if (on .and. i < n - 1 .and. paint%dash(di)*scale - rem > tol) then
                        call unit_dir(px(i), py(i), px(i + 1), py(i + 1), vx, vy)
                        d = stub_len(px(i + 1), py(i + 1), min(paint%dash(di)*scale - rem, l))
                        rx(1) = px(i + 1) - d*vx
                        ry(1) = py(i + 1) - d*vy
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
                ! t0 + (tb - t0) can round to just short of tb, which would
                ! add a point a rounding step on in no particular direction.
                if (seg >= tb - t0) t1 = tb
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
                if (rem <= tol) then
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
                    if (on .and. i < n - 1 .and. paint%dash(di)*scale - rem > tol) then
                        call unit_dir(px(i), py(i), px(i + 1), py(i + 1), vx, vy)
                        d = stub_len(px(i + 1), py(i + 1), min(paint%dash(di)*scale - rem, &
                                                               hypot(px(i + 1) - qx, py(i + 1) - qy)))
                        rx(1) = px(i + 1) - d*vx
                        ry(1) = py(i + 1) - d*vy
                        rx(2) = px(i + 1)
                        ry(2) = py(i + 1)
                        nr = 2
                        bare = .true.
                    end if
                end if
            end if
        end do
        if (on .and. nr > 1) call stroke_run(out, rx, ry, nr, hw, paint, .false., bare0=bare)
        if (framed) then
            if (nz > 1) call stroke_run(solid, zx, zy, nz, hw, paint, .false.)
        end if
    end subroutine stroke_dashed

    ! Where along the segment from (sx, sy) to (qx, qy), as a fraction
    ! from ta to tb, matrix maps it into the box [bx0, bx1] by [by0, by1]
    ! on the canvas, each side widened by r, the pen's reach in the frame,
    ! as the matrix stretches that axis: the side x = bx0 is the line
    ! matrix(1)*x + matrix(3)*y + matrix(5) = bx0 in the frame, and so on.
    ! An empty piece has ta >= tb.
    pure subroutine frame_cut(matrix, sx, sy, qx, qy, bx0, bx1, by0, by1, r, ta, tb)
        real(dp), intent(in) :: matrix(6), sx, sy, qx, qy, bx0, bx1, by0, by1, r
        real(dp), intent(out) :: ta, tb
        real(dp) :: g0, g1, d, lo, hi, w, t1, t2
        integer :: k

        ta = -huge(1.0_dp)
        tb = huge(1.0_dp)
        do k = 1, 2
            w = r*hypot(matrix(k), matrix(k + 2))
            if (k == 1) then
                lo = bx0 - w
                hi = bx1 + w
            else
                lo = by0 - w
                hi = by1 + w
            end if
            g0 = matrix(k)*sx + matrix(k + 2)*sy + matrix(k + 4)
            g1 = matrix(k)*qx + matrix(k + 2)*qy + matrix(k + 4)
            d = g1 - g0
            if (d == 0.0_dp) then
                if (g0 < lo .or. g0 > hi) then
                    ta = 1.0_dp
                    tb = 0.0_dp
                    return
                end if
            else
                t1 = (lo - g0)/d
                t2 = (hi - g0)/d
                ta = max(ta, min(t1, t2))
                tb = min(tb, max(t1, t2))
            end if
        end do
    end subroutine frame_cut

    ! The point a fraction t of the way from (sx, sy) to (qx, qy), measured
    ! from whichever end is nearer.
    pure subroutine along(sx, sy, qx, qy, t, x, y)
        real(dp), intent(in) :: sx, sy, qx, qy, t
        real(dp), intent(out) :: x, y
        if (t <= 0.5_dp) then
            x = sx + (qx - sx)*t
            y = sy + (qy - sy)*t
        else
            x = qx + (sx - qx)*(1.0_dp - t)
            y = qy + (sy - qy)*(1.0_dp - t)
        end if
    end subroutine along

    ! A step along a segment from (x, y) short enough to carry a join there
    ! without adding anything that can be seen, and long enough still to
    ! move the point: a millionth of a pixel, more where a double is
    ! coarser than that.
    pure function stub_at(x, y) result(d)
        real(dp), intent(in) :: x, y
        real(dp) :: d
        d = 1.0e-6_dp + 1.0e3_dp*epsilon(1.0_dp)*max(abs(x), abs(y))
    end function stub_at

    ! The length of a capless stub that carries the join at (x, y): at
    ! most room, the part of the dash through that point that lies along
    ! the segment short of where the walk goes on, so that the stub lies
    ! inside a dash the full walk draws, where it adds nothing that can be
    ! seen, whatever a frame stretches or moves it by. stub_at, in a
    ! frame's coordinates, could otherwise reach the canvas. Never under
    ! four steps of a double at the point, to move it.
    pure function stub_len(x, y, room) result(d)
        real(dp), intent(in) :: x, y, room
        real(dp) :: d
        d = max(min(stub_at(x, y), room), 4.0_dp*spacing(max(abs(x), abs(y))))
    end function stub_len

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

        ! Moving nowhere changes nothing, even at a dash of no length.
        if (d <= 0.0_dp) return
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

        n = max(8, min(64, ceiling(min(r*out%curve_scale, 100.0_dp)*4.0_dp)))
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

        if (nx < 1 .or. ny < 1 .or. w <= 0.0_dp .or. h <= 0.0_dp .or. alpha <= 0.0_dp) return
        if (.not. cv%identity_transform .or. cv%n_clip > 0) then
            call blit_affine_image(cv, x, y, w, h, rgba, nx, ny, alpha, clip)
            return
        end if
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

    subroutine blit_affine_image(cv, x, y, w, h, rgba, nx, ny, alpha, clip)
        type(canvas_t), intent(inout) :: cv
        real(dp), intent(in) :: x, y, w, h, alpha
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(4, nx, ny)
        type(clip_t), intent(in) :: clip
        real(dp) :: qx(4), qy(4), m(6), det, dx, dy, lx, ly, u, v, sa, ia
        integer :: ix, iy, sx, sy, px0, px1, py0, py1, j
        logical :: visible

        m = cv%matrix
        det = m(1)*m(4) - m(2)*m(3)
        if (det == 0.0_dp) return
        call transformed_rect(cv, clip_t(.true., x, y, w, h), qx, qy)
        px0 = floor(max(0.0_dp, min(real(cv%w, dp), minval(qx)))) + 1
        px1 = ceiling(max(0.0_dp, min(real(cv%w, dp), maxval(qx))))
        py0 = floor(max(0.0_dp, min(real(cv%h, dp), minval(qy)))) + 1
        py1 = ceiling(max(0.0_dp, min(real(cv%h, dp), maxval(qy))))
        do iy = py0, py1
            do ix = px0, px1
                dx = real(ix, dp) - 0.5_dp - m(5)
                dy = real(iy, dp) - 0.5_dp - m(6)
                ! Divided by det, then by the scale: their product can
                ! underflow where neither does.
                lx = (m(4)*dx - m(3)*dy)/det/cv%scale
                ly = (m(1)*dy - m(2)*dx)/det/cv%scale
                u = (lx - x)/w
                v = (ly - y)/h
                ! Written so that a NaN, from 0/0 say, fails it too.
                if (.not. (u >= 0.0_dp .and. u < 1.0_dp .and. v >= 0.0_dp .and. v < 1.0_dp)) cycle
                if (clip%on) then
                    if (lx < clip%x .or. lx >= clip%x + clip%w .or. &
                        ly < clip%y .or. ly >= clip%y + clip%h) cycle
                end if
                visible = .true.
                do j = 1, cv%n_frame
                    if (.not. cv%frames(j)%clipped) cycle
                    if (inside_quad(real(ix, dp) - 0.5_dp, real(iy, dp) - 0.5_dp, &
                                    cv%frames(j)%clip_x, cv%frames(j)%clip_y)) cycle
                    visible = .false.
                    exit
                end do
                if (.not. visible) cycle
                sx = min(nx, max(1, int(u*real(nx, dp)) + 1))
                sy = min(ny, max(1, int(v*real(ny, dp)) + 1))
                sa = alpha*real(rgba(4, sx, sy), dp)/255.0_dp
                if (sa <= 0.0_dp) cycle
                ia = 1.0_dp - sa
                cv%px(1, ix, iy) = real(rgba(1, sx, sy), dp)/255.0_dp*sa + cv%px(1, ix, iy)*ia
                cv%px(2, ix, iy) = real(rgba(2, sx, sy), dp)/255.0_dp*sa + cv%px(2, ix, iy)*ia
                cv%px(3, ix, iy) = real(rgba(3, sx, sy), dp)/255.0_dp*sa + cv%px(3, ix, iy)*ia
                cv%px(4, ix, iy) = sa + cv%px(4, ix, iy)*ia
            end do
        end do
    end subroutine blit_affine_image

    logical function inside_quad(x, y, qx, qy) result(inside)
        real(dp), intent(in) :: x, y, qx(4), qy(4)
        real(dp) :: orientation, cross
        integer :: i, j

        inside = .false.
        orientation = (qx(2) - qx(1))*(qy(4) - qy(1)) - (qy(2) - qy(1))*(qx(4) - qx(1))
        if (orientation == 0.0_dp) return
        orientation = sign(1.0_dp, orientation)
        do i = 1, 4
            j = mod(i, 4) + 1
            cross = (qx(j) - qx(i))*(y - qy(i)) - (qy(j) - qy(i))*(x - qx(i))
            if (orientation*cross < 0.0_dp) return
        end do
        inside = .true.
    end function inside_quad

end module fplotlib_raster
