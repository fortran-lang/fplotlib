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
! Even-odd paths are split at vertices and edge crossings into disjoint
! trapezoids, which use the same analytic area accumulator. Applying parity
! to an already averaged winding number would give incorrect edge coverage.
!
! Everything else reduces to filling a path. Strokes are converted to outlines
! and filled; text is glyph outlines and filled; markers are a shape filled once
! per point. There is one rasterizer here, not five.

module fplotlib_raster
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_render, only: paint_t, clip_t, VERB_MOVE, VERB_LINE, VERB_CUBIC, &
                            VERB_CLOSE, CAP_BUTT, CAP_ROUND, CAP_SQUARE, &
                            JOIN_MITER, JOIN_ROUND, JOIN_BEVEL, MAX_DASH, FILL_NONZERO, FILL_EVENODD
    implicit none
    private

    public :: canvas_t, pathbuf_t
    public :: canvas_init, canvas_rgba, canvas_free
    public :: canvas_begin_frame, canvas_end_frame
    public :: pb_reset, pb_move, pb_line, pb_cubic, pb_close, pb_poly
    public :: pb_should_snap, pb_snap
    public :: fill_path_buf, stroke_path_buf, blit_image

    real(dp), parameter :: IDENTITY(6) = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp]

    ! A path flattened to polylines: every curve is already line segments, so
    ! the rasterizer never sees a Bezier.
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

    subroutine canvas_free(cv, status)
        type(canvas_t), intent(inout) :: cv

        type(status_t), intent(out) :: status
        if (cv%n_frame /= 0) then
            call status%set(ERROR_STATE, "raster: unclosed frame at canvas_free")
            return
        end if
        if (allocated(cv%px)) deallocate (cv%px)
        if (allocated(cv%acc)) deallocate (cv%acc)
        if (allocated(cv%frames)) deallocate (cv%frames)
    end subroutine canvas_free

    ! The matrix acts on local pixels; clip coordinates, like paint clips,
    ! are points in the same local, origin-shifted coordinate system.
    subroutine canvas_begin_frame(cv, matrix, clip, status)
        type(canvas_t), intent(inout) :: cv
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip
        type(raster_frame_t), allocatable :: grown(:)
        real(dp) :: p(6), m(6), qx(4), qy(4)

        type(status_t), intent(out) :: status
        if (.not. allocated(cv%px)) then
            call status%set(ERROR_STATE, "raster: begin_frame outside canvas")
            return
        end if
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

    subroutine canvas_end_frame(cv, status)
        type(canvas_t), intent(inout) :: cv
        real(dp) :: matrix(6)

        type(status_t), intent(out) :: status
        if (cv%n_frame == 0) then
            call status%set(ERROR_STATE, "raster: unmatched end_frame")
            return
        end if
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
    subroutine canvas_rgba(cv, out, status)
        use fplotlib_status, only: status_t, ERROR_STATE
        type(canvas_t), intent(in) :: cv
        integer, allocatable, intent(out) :: out(:, :, :)
        type(status_t), intent(out) :: status
        integer :: x, y, c
        real(dp) :: a, v

        if (.not. allocated(cv%px)) then
            call status%set(ERROR_STATE, "raster: canvas is not initialized")
            return
        end if
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
    end subroutine canvas_rgba

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
        n = max(3, min(128, ceiling(d*pb%curve_scale*0.6_dp)))
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
        if (modulo(nint(line_width_px), 2) == 1) sv = 0.5_dp
        ! A coordinate meant to be exactly x.5 arrives as x.5 plus or minus
        ! 1e-13, and floor(x + 0.5) then picks either pixel depending on the
        ! compiler. Rounding to 1/65536 px first (exact in binary) makes it
        ! x.5 again, and every build snaps it the same way.
        do i = 1, pb%n
            pb%x(i) = floor(anint(pb%x(i)*65536.0_dp)/65536.0_dp + 0.5_dp) + sv
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
        yi0 = max(0, floor(y0))
        yi1 = min(cv%h, ceiling(y1))
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

    subroutine fill_path_buf(cv, pb, rgb, alpha, clip, fill_rule)
        type(canvas_t), intent(inout) :: cv
        type(pathbuf_t), intent(in) :: pb
        integer, intent(in) :: rgb(3)
        real(dp), intent(in) :: alpha
        type(clip_t), intent(in) :: clip
        integer, intent(in), optional :: fill_rule
        integer :: s, i, b, n, y, x, cx0, cx1, cy0, cy1, y0b, y1b
        real(dp) :: run, cov, sa, sr, sg, sb_, ia
        logical :: scoped, evenodd

        if (pb%ns == 0 .or. alpha <= 0.0_dp) return

        evenodd = .false.
        if (present(fill_rule)) evenodd = fill_rule == FILL_EVENODD
        scoped = .not. cv%identity_transform .or. cv%n_clip > 0 .or. evenodd
        y0b = cv%h + 1
        y1b = 0
        if (evenodd) then
            call acc_evenodd_path(cv, pb, clip, y0b, y1b)
        else if (scoped) then
            call acc_transformed_path(cv, pb, clip, y0b, y1b)
        else
            do s = 1, pb%ns
                b = pb%sub_beg(s)
                n = pb%sub_len(s)
                if (n < 2) cycle
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

    subroutine acc_transformed_path(cv, pb, clip, y0b, y1b)
        type(canvas_t), intent(inout) :: cv
        type(pathbuf_t), intent(in) :: pb
        type(clip_t), intent(in) :: clip
        integer, intent(inout) :: y0b, y1b
        real(dp), allocatable :: x(:), y(:)
        integer :: s, n, i

        if (cv%matrix(1)*cv%matrix(4) - cv%matrix(2)*cv%matrix(3) == 0.0_dp) return
        do s = 1, pb%ns
            call transformed_contour(cv, pb, s, clip, x, y, n)
            if (n >= 3) then
                do i = 1, n - 1
                    call acc_edge(cv, x(i), y(i), x(i + 1), y(i + 1), y0b, y1b)
                end do
                call acc_edge(cv, x(n), y(n), x(1), y(1), y0b, y1b)
            end if
        end do
    end subroutine acc_transformed_path

    subroutine transformed_contour(cv, pb, s, clip, x, y, n)
        type(canvas_t), intent(in) :: cv
        type(pathbuf_t), intent(in) :: pb
        integer, intent(in) :: s
        type(clip_t), intent(in) :: clip
        real(dp), allocatable, intent(out) :: x(:), y(:)
        integer, intent(out) :: n
        real(dp) :: qx(4), qy(4)
        integer :: b, j
        b = pb%sub_beg(s)
        n = pb%sub_len(s)
        if (n < 3) return
        allocate (x(n), y(n))
        x = cv%matrix(1)*pb%x(b:b + n - 1) + cv%matrix(3)*pb%y(b:b + n - 1) + cv%matrix(5)
        y = cv%matrix(2)*pb%x(b:b + n - 1) + cv%matrix(4)*pb%y(b:b + n - 1) + cv%matrix(6)
        do j = 1, cv%n_frame
            if (.not. cv%frames(j)%clipped) cycle
            call clip_polygon(x, y, n, cv%frames(j)%clip_x, cv%frames(j)%clip_y)
            if (n < 3) return
        end do
        if (clip%on) then
            call transformed_rect(cv, clip, qx, qy)
            call clip_polygon(x, y, n, qx, qy)
        end if
    end subroutine transformed_contour

    subroutine acc_evenodd_path(cv, pb, clip, y0b, y1b)
        type(canvas_t), intent(inout) :: cv
        type(pathbuf_t), intent(in) :: pb
        type(clip_t), intent(in) :: clip
        integer, intent(inout) :: y0b, y1b
        type(pathbuf_t) :: flat
        real(dp), allocatable :: x(:), y(:), edges(:, :), events(:), crossings(:)
        integer, allocatable :: order(:)
        real(dp) :: lo, hi, mid, slope, cross, left0, left1, right0, right1
        integer :: s, b, n, i, j, k, next, ne, ny, na, left, right

        if (cv%matrix(1)*cv%matrix(4) - cv%matrix(2)*cv%matrix(3) == 0.0_dp) return
        call pb_reset(flat)
        do s = 1, pb%ns
            call transformed_contour(cv, pb, s, clip, x, y, n)
            if (n < 3) cycle
            call pb_move(flat, x(1), y(1))
            do i = 2, n
                call pb_line(flat, x(i), y(i))
            end do
            call pb_close(flat)
        end do
        allocate (edges(4, flat%n), crossings(flat%n), order(flat%n), events(max(2, 2*flat%n)))
        ne = 0
        ny = 0
        call append_event(events, ny, 0.0_dp)
        call append_event(events, ny, real(cv%h, dp))
        do s = 1, flat%ns
            b = flat%sub_beg(s)
            n = flat%sub_len(s)
            do i = b, b + n - 1
                next = b + mod(i - b + 1, n)
                if (flat%y(i) == flat%y(next)) cycle
                j = i
                k = next
                if (flat%y(j) > flat%y(k)) then
                    j = next
                    k = i
                end if
                if (flat%y(k) <= 0.0_dp .or. flat%y(j) >= real(cv%h, dp)) cycle
                ne = ne + 1
                slope = (flat%x(k) - flat%x(j))/(flat%y(k) - flat%y(j))
                edges(:, ne) = [flat%x(j), flat%y(j), slope, flat%y(k)]
                call append_event(events, ny, max(0.0_dp, flat%y(j)))
                call append_event(events, ny, min(real(cv%h, dp), flat%y(k)))
            end do
        end do
        do i = 1, ne
            do j = i + 1, ne
                lo = max(edges(2, i), edges(2, j), 0.0_dp)
                hi = min(edges(4, i), edges(4, j), real(cv%h, dp))
                if (hi <= lo) cycle
                slope = edges(3, i) - edges(3, j)
                if (slope == 0.0_dp) cycle
                cross = lo + (edges(1, j) + edges(3, j)*(lo - edges(2, j)) &
                              - edges(1, i) - edges(3, i)*(lo - edges(2, i)))/slope
                if (cross > lo .and. cross < hi) call append_event(events, ny, cross)
            end do
        end do
        call sort_crossings(events, ny)
        do k = 1, ny - 1
            lo = events(k)
            hi = events(k + 1)
            if (hi <= lo) cycle
            mid = lo + 0.5_dp*(hi - lo)
            na = 0
            do i = 1, ne
                if (mid < edges(2, i) .or. mid >= edges(4, i)) cycle
                na = na + 1
                order(na) = i
                crossings(na) = edges(1, i) + edges(3, i)*(mid - edges(2, i))
            end do
            call sort_crossings(crossings, na, order)
            do i = 1, na - 1, 2
                left = order(i)
                right = order(i + 1)
                left0 = edges(1, left) + edges(3, left)*(lo - edges(2, left))
                left1 = edges(1, left) + edges(3, left)*(hi - edges(2, left))
                right0 = edges(1, right) + edges(3, right)*(lo - edges(2, right))
                right1 = edges(1, right) + edges(3, right)*(hi - edges(2, right))
                call acc_edge(cv, left1, hi, left0, lo, y0b, y1b)
                call acc_edge(cv, right0, lo, right1, hi, y0b, y1b)
            end do
        end do
    end subroutine acc_evenodd_path

    subroutine append_event(events, n, value)
        real(dp), allocatable, intent(inout) :: events(:)
        integer, intent(inout) :: n
        real(dp), intent(in) :: value
        real(dp), allocatable :: grown(:)
        if (n == size(events)) then
            allocate (grown(2*size(events)))
            grown(1:n) = events(1:n)
            call move_alloc(grown, events)
        end if
        n = n + 1
        events(n) = value
    end subroutine append_event

    subroutine sort_crossings(values, n, order)
        real(dp), intent(inout) :: values(:)
        integer, intent(in) :: n
        integer, intent(inout), optional :: order(:)
        real(dp) :: value
        integer :: gap, i, j, index
        gap = n/2
        do while (gap > 0)
            do i = gap + 1, n
                value = values(i)
                if (present(order)) index = order(i)
                j = i
                do while (j > gap)
                    if (values(j - gap) <= value) exit
                    values(j) = values(j - gap)
                    if (present(order)) order(j) = order(j - gap)
                    j = j - gap
                end do
                values(j) = value
                if (present(order)) order(j) = index
            end do
            gap = gap/2
        end do
    end subroutine sort_crossings

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
            x0 = max(1, nint(clip%x*cv%scale) + 1)
            y0 = max(1, nint(clip%y*cv%scale) + 1)
            x1 = min(cv%w, nint((clip%x + clip%w)*cv%scale))
            y1 = min(cv%h, nint((clip%y + clip%h)*cv%scale))
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
        real(dp) :: hw

        hw = 0.5_dp*paint%line_width*cv%scale
        if (hw <= 0.0_dp) return
        call pb_reset(out)
        out%curve_scale = cv%curve_scale

        do s = 1, pb%ns
            b = pb%sub_beg(s)
            n = pb%sub_len(s)
            if (n < 1) cycle
            call gather(pb, b, n, pb%sub_closed(s), dx, dy, nd)
            if (paint%n_dash > 0) then
                call stroke_dashed(out, dx, dy, nd, hw, paint, cv%scale)
            else
                call stroke_run(out, dx, dy, nd, hw, paint, pb%sub_closed(s))
            end if
        end do

        call fill_path_buf(cv, out, paint%stroke_rgb, paint%stroke_alpha, paint%clip)
    end subroutine stroke_path_buf

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
    ! dash caps are applied per dash and not per line.
    subroutine stroke_dashed(out, px, py, n, hw, paint, scale)
        type(pathbuf_t), intent(inout) :: out
        real(dp), intent(in) :: px(:), py(:), hw, scale
        integer, intent(in) :: n
        type(paint_t), intent(in) :: paint
        real(dp) :: rem, seg, t0, t1, ex, ey, sx, sy, l
        real(dp), allocatable :: rx(:), ry(:)
        integer :: i, di, nr
        logical :: on

        allocate (rx(n + 4), ry(n + 4))
        di = 1
        rem = paint%dash(1)*scale
        on = .true.
        nr = 0

        do i = 1, n - 1
            sx = px(i); sy = py(i)
            l = hypot(px(i + 1) - sx, py(i + 1) - sy)
            if (l <= 0.0_dp) cycle
            t0 = 0.0_dp
            do while (t0 < l)
                seg = min(rem, l - t0)
                t1 = t0 + seg
                ex = sx + (px(i + 1) - sx)*(t1/l)
                ey = sy + (py(i + 1) - sy)*(t1/l)
                if (on) then
                    if (nr == 0) then
                        nr = 1
                        rx(1) = sx + (px(i + 1) - sx)*(t0/l)
                        ry(1) = sy + (py(i + 1) - sy)*(t0/l)
                    end if
                    nr = nr + 1
                    rx(nr) = ex
                    ry(nr) = ey
                end if
                rem = rem - seg
                t0 = t1
                if (rem <= 1.0e-12_dp) then
                    if (on .and. nr > 1) then
                        call stroke_run(out, rx, ry, nr, hw, paint, .false.)
                        nr = 0
                    end if
                    on = .not. on
                    di = di + 1
                    if (di > paint%n_dash) di = 1
                    rem = paint%dash(di)*scale
                    nr = 0
                end if
            end do
        end do
        if (on .and. nr > 1) call stroke_run(out, rx, ry, nr, hw, paint, .false.)
    end subroutine stroke_dashed

    subroutine stroke_run(out, px, py, n, hw, paint, closed)
        type(pathbuf_t), intent(inout) :: out
        real(dp), intent(in) :: px(:), py(:), hw
        integer, intent(in) :: n
        type(paint_t), intent(in) :: paint
        logical, intent(in) :: closed
        real(dp) :: qx(4), qy(4), ux, uy, nx, ny, l
        integer :: i

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
                if (i == 1) then
                    qx(1) = qx(1) - ux*hw; qy(1) = qy(1) - uy*hw
                    qx(4) = qx(4) - ux*hw; qy(4) = qy(4) - uy*hw
                end if
                if (i == n - 1) then
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
            call add_disc(out, px(1), py(1), hw)
            call add_disc(out, px(n), py(n), hw)
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

        n = max(8, min(64, ceiling(r*out%curve_scale*4.0_dp)))
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
        px0 = max(cx0, nint(x*cv%scale) + 1)
        py0 = max(cy0, nint(y*cv%scale) + 1)
        px1 = min(cx1, nint((x + w)*cv%scale))
        py1 = min(cy1, nint((y + h)*cv%scale))

        do iy = py0, py1
            v = (real(iy, dp) - 0.5_dp)/cv%scale - y
            sy = min(ny, max(1, int(v/h*real(ny, dp)) + 1))
            do ix = px0, px1
                u = (real(ix, dp) - 0.5_dp)/cv%scale - x
                sx = min(nx, max(1, int(u/w*real(nx, dp)) + 1))
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
                lx = (m(4)*dx - m(3)*dy)/(det*cv%scale)
                ly = (m(1)*dy - m(2)*dx)/(det*cv%scale)
                u = (lx - x)/w
                v = (ly - y)/h
                if (u < 0.0_dp .or. u >= 1.0_dp .or. v < 0.0_dp .or. v >= 1.0_dp) cycle
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
