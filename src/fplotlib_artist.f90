! fplotlib_artist - the drawing primitives every plot type is built from.
!
! Nothing here knows what is being drawn: these take a renderer and points
! on the canvas and put strokes, fills, markers and text on it. The plot
! types turn data into calls to these, which is the division matplotlib
! draws between its artists and its backends.
module fplotlib_artist
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use fplotlib_colors
    use fplotlib_style
    use fplotlib_render
    use fplotlib_raster, only: clip_to_box, clip_segment
    use fplotlib_state
    use fplotlib_mathtext
    use fplotlib_text, only: text_face, text_layout, text_width, run_shift
    use fplotlib_glyphs, only: face_ascent, face_descent, FACE_REGULAR
    implicit none
    public
    ! put_path's own bookkeeping.
    private :: finite_point, path_move, path_put
    private :: emit_path, far_path, grow_put, push_point, view_box, tame, turn_angle
    private :: flatten_cubic, image_groups, set_along

contains

    pure function hex_byte(s) result(v)
        character(len=2), intent(in) :: s
        integer :: v
        v = 16 * hex_digit(s(1:1)) + hex_digit(s(2:2))
    end function hex_byte

    pure function hex_digit(c) result(v)
        character(len=1), intent(in) :: c
        integer :: v, k
        k = iachar(c)
        if (k >= 48 .and. k <= 57) then
            v = k - 48
        else if (k >= 97 .and. k <= 102) then
            v = k - 87
        else if (k >= 65 .and. k <= 70) then
            v = k - 55
        else
            v = 0
        end if
    end function hex_digit

    pure function hex_pair(v) result(s)
        integer, intent(in) :: v
        character(len=2) :: s
        character(len=16), parameter :: D = "0123456789abcdef"
        integer :: w
        w = max(0, min(255, v))
        s = D(w / 16 + 1:w / 16 + 1) // D(mod(w, 16) + 1:mod(w, 16) + 1)
    end function hex_pair

    ! Insertion sort. The samples behind one box are few and already close to
    ! sorted often enough that anything cleverer would not pay for itself.
    pure subroutine sort_in_place(v)
        real(dp), intent(inout) :: v(:)
        integer :: i, j
        real(dp) :: t
        do i = 2, size(v)
            t = v(i)
            j = i - 1
            do while (j >= 1)
                if (v(j) <= t) exit
                v(j + 1) = v(j)
                j = j - 1
            end do
            v(j + 1) = t
        end do
    end subroutine sort_in_place

    ! fplotlib carries colors as "#rrggbb" because that is what a format string
    ! and a colormap table both produce; the renderer wants components.
    pure function hex_rgb(s) result(c)
        character(len=*), intent(in) :: s
        integer :: c(3), i
        c = 0
        if (len(s) < 7) return
        do i = 1, 3
            c(i) = hex_byte(s(2*i:2*i + 1))
        end do
    end function hex_rgb

    ! The clip in force for the primitives being emitted now. The rendering
    ! API is stateless by design, but fplotlib draws in regions ("everything
    ! inside the axes box"), so the front end tracks the current region here
    ! and stamps it into each paint rather than passing it through fifteen
    ! layers of call.
    subroutine set_clip(x, y, w, h)
        real(dp), intent(in) :: x, y, w, h
        g_clip%on = .true.
        g_clip%x = x
        g_clip%y = y
        g_clip%w = w
        g_clip%h = h
    end subroutine set_clip

    subroutine clear_clip()
        g_clip%on = .false.
    end subroutine clear_clip

    ! Stroke-only paint.
    function pen(color, lw, alpha, ls) result(p)
        character(len=*), intent(in) :: color
        real(dp), intent(in) :: lw
        real(dp), intent(in), optional :: alpha
        integer, intent(in), optional :: ls
        type(paint_t) :: p
        p%filled = .false.
        p%stroked = .true.
        p%stroke_rgb = hex_rgb(color)
        p%line_width = lw
        if (present(alpha)) p%stroke_alpha = alpha
        if (present(ls)) call set_dash(p, ls)
        p%clip = g_clip
    end function pen

    ! Fill-only paint.
    function brush(color, alpha) result(p)
        character(len=*), intent(in) :: color
        real(dp), intent(in), optional :: alpha
        type(paint_t) :: p
        p%filled = .true.
        p%stroked = .false.
        p%fill_rgb = hex_rgb(color)
        if (present(alpha)) p%fill_alpha = alpha
        p%clip = g_clip
    end function brush

    ! matplotlib's dash patterns, in points, for its four line styles.
    subroutine set_dash(p, ls)
        type(paint_t), intent(inout) :: p
        integer, intent(in) :: ls
        select case (ls)
        case (LINE_DASHED)
            p%n_dash = 2
            p%dash(1:2) = [5.55_dp, 2.4_dp]
        case (LINE_DOTTED)
            p%n_dash = 2
            p%dash(1:2) = [1.5_dp, 2.475_dp]
        case (LINE_DASHDOT)
            p%n_dash = 4
            p%dash(1:4) = [9.9_dp, 2.4_dp, 1.5_dp, 2.4_dp]
        end select
    end subroutine set_dash

    ! Verbs for an open polyline through np points.
    pure function line_verbs(np) result(v)
        integer, intent(in) :: np
        integer :: v(np), i
        v(1) = VERB_MOVE
        do i = 2, np
            v(i) = VERB_LINE
        end do
    end function line_verbs

    ! ------------------------------------------------------------------
    ! The way into the renderer. Plotted data may be missing, as NaN or an
    ! infinity, the way matplotlib allows, and so is anything computed from
    ! it, while the renderer takes only finite coordinates. Every drawing
    ! call of the plot types goes through these, which leave out what is
    ! missing as matplotlib's own path handling does: a path is broken
    ! where a vertex is missing, and a shape, a marker, a run of text or an
    ! image placed at a missing point is not drawn. A call with nothing
    ! missing reaches the renderer unchanged.
    ! ------------------------------------------------------------------

    subroutine put_path(b, x, y, verbs, n_verb, paint)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        real(dp), allocatable :: ox(:), oy(:)
        integer, allocatable :: ov(:)
        integer :: i, k, np, no, nv
        logical :: pen, broken

        np = 0
        do i = 1, min(n_verb, size(verbs))
            if (verbs(i) == VERB_MOVE .or. verbs(i) == VERB_LINE) np = np + 1
            if (verbs(i) == VERB_CUBIC) np = np + 3
        end do
        ! A path that breaks the contract in any other way is left for the
        ! renderer to report.
        if (n_verb < 0 .or. n_verb > size(verbs) .or. np > min(size(x), size(y))) then
            call b%draw_path(x, y, verbs, n_verb, paint)
            return
        end if
        if (all(ieee_is_finite(x(1:np))) .and. all(ieee_is_finite(y(1:np)))) then
            call emit_path(b, x, y, verbs, n_verb, paint)
            return
        end if

        ! pen: the output has a current point to continue from. broken: the
        ! contour has lost a piece, so closing it would bridge the gap.
        allocate (ox(np), oy(np), ov(n_verb))
        no = 0
        nv = 0
        k = 0
        pen = .false.
        broken = .false.
        do i = 1, n_verb
            select case (verbs(i))
            case (VERB_MOVE)
                k = k + 1
                pen = finite_point(x, y, k)
                ! A contour whose first point is missing is broken already.
                broken = .not. pen
                if (pen) call path_move(ox, oy, ov, no, nv, x(k), y(k))
            case (VERB_LINE)
                k = k + 1
                if (.not. finite_point(x, y, k)) then
                    pen = .false.
                    broken = .true.
                else if (pen) then
                    call path_put(ox, oy, ov, no, nv, VERB_LINE, x(k:k), y(k:k))
                else
                    call path_move(ox, oy, ov, no, nv, x(k), y(k))
                    pen = .true.
                end if
            case (VERB_CUBIC)
                k = k + 3
                if (pen .and. finite_point(x, y, k - 2) .and. finite_point(x, y, k - 1) &
                    .and. finite_point(x, y, k)) then
                    call path_put(ox, oy, ov, no, nv, VERB_CUBIC, x(k - 2:k), y(k - 2:k))
                else if (finite_point(x, y, k)) then
                    call path_move(ox, oy, ov, no, nv, x(k), y(k))
                    pen = .true.
                    broken = .true.
                else
                    pen = .false.
                    broken = .true.
                end if
            case (VERB_CLOSE)
                if (pen .and. .not. broken) then
                    call path_put(ox, oy, ov, no, nv, VERB_CLOSE, x(1:0), y(1:0))
                else
                    pen = .false.
                end if
            end select
        end do
        ! A move with nothing after it draws nothing.
        if (nv > 0) then
            if (ov(nv) == VERB_MOVE) then
                nv = nv - 1
                no = no - 1
            end if
        end if
        if (nv > 0) call emit_path(b, ox(1:no), oy(1:no), ov(1:nv), nv, paint)
    end subroutine put_path

    ! Data far outside the view is finite but can be as large as a double
    ! goes, and nothing gains from handing the renderer coordinates a
    ! file format cannot write. Geometry is therefore cut down to a box ten
    ! canvases wide around the canvas, which changes nothing that can be
    ! seen: a filled contour is clipped as a polygon (Sutherland and
    ! Hodgman), a stroked one segment by segment (Liang and Barsky), so
    ! every line keeps its direction. A path inside the box is untouched.
    subroutine view_box(b, bx0, bx1, by0, by1, paint)
        class(renderer_t), intent(in) :: b
        real(dp), intent(out) :: bx0, bx1, by0, by1
        type(paint_t), intent(in), optional :: paint
        type(paint_t) :: p
        real(dp) :: m
        m = min(10.0_dp*max(b%width, b%height, 72.0_dp), 1.0e13_dp)
        ! A stroke reaches past its line by half its width, and a mitred
        ! corner further: an edge the clip makes must stay out of reach.
        if (present(paint)) then
            p = tame(paint)
            if (p%stroked) m = m + p%line_width*max(1.5_dp, 0.5_dp*min(p%miter_limit, 20.0_dp))
        end if
        bx0 = -m
        bx1 = b%width + m
        by0 = -m
        by1 = b%height + m
    end subroutine view_box

    ! A line width or dash a trillion points long covers anything that can
    ! be seen as fully as a larger one does, and stays within what the
    ! renderer takes.
    function tame(paint) result(p)
        type(paint_t), intent(in) :: paint
        type(paint_t) :: p
        real(dp), parameter :: BIG = 1.0e12_dp
        real(dp) :: m
        p = paint
        if (.not. p%stroked) return
        p%line_width = min(p%line_width, BIG)
        if (p%n_dash > 0) then
            m = maxval(p%dash(1:p%n_dash))
            if (m > BIG) p%dash(1:p%n_dash) = p%dash(1:p%n_dash)*(BIG/m)
            p%dash_offset = mod(p%dash_offset, BIG)
        end if
    end function tame

    subroutine emit_path(b, x, y, verbs, n_verb, paint)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint
        real(dp) :: bx0, bx1, by0, by1, period
        real(dp), allocatable :: ox(:), oy(:), al(:)
        integer, allocatable :: ov(:)
        integer :: i, np, no, nv, i0, i1, k0, k1
        type(paint_t) :: p, pf, ps, pd

        np = 0
        do i = 1, n_verb
            if (verbs(i) == VERB_MOVE .or. verbs(i) == VERB_LINE) np = np + 1
            if (verbs(i) == VERB_CUBIC) np = np + 3
        end do
        call view_box(b, bx0, bx1, by0, by1, paint)
        if (all(x(1:np) >= bx0 .and. x(1:np) <= bx1 .and. y(1:np) >= by0 .and. y(1:np) <= by1)) then
            call b%draw_path(x, y, verbs, n_verb, tame(paint))
            return
        end if
        ! The fill is clipped as a polygon and the stroke as lines, apart:
        ! the edges the clip adds to a polygon are not edges of the shape.
        p = tame(paint)
        if (p%filled) then
            pf = p
            pf%stroked = .false.
            call far_path(x, y, verbs, n_verb, .true., bx0, bx1, by0, by1, ox, oy, ov, al, no, nv)
            if (nv > 0) call b%draw_path(ox(1:no), oy(1:no), ov(1:nv), nv, pf)
        end if
        if (.not. p%stroked) return
        ps = p
        ps%filled = .false.
        call far_path(x, y, verbs, n_verb, .false., bx0, bx1, by0, by1, ox, oy, ov, al, no, nv)
        if (nv == 0) return
        if (ps%n_dash == 0) then
            call b%draw_path(ox(1:no), oy(1:no), ov(1:nv), nv, ps)
            return
        end if
        ! A dashed line cut into pieces would start its pattern afresh at
        ! each cut. Each piece goes out on its own instead, with the offset
        ! of the pattern where it begins along the whole line.
        period = sum(ps%dash(1:ps%n_dash))
        if (mod(ps%n_dash, 2) == 1) period = 2.0_dp*period
        k0 = 1
        i0 = 1
        do while (i0 <= nv)
            i1 = i0 + 1
            k1 = k0 + 1
            do while (i1 <= nv)
                if (ov(i1) == VERB_MOVE) exit
                if (ov(i1) == VERB_LINE) k1 = k1 + 1
                if (ov(i1) == VERB_CUBIC) k1 = k1 + 3
                i1 = i1 + 1
            end do
            pd = ps
            ! Beyond a quadrillion periods along, a double no longer knows
            ! where in the pattern it is, and mod need not either.
            pd%dash_offset = 0.0_dp
            if (al(i0) < 1.0e15_dp*period) pd%dash_offset = mod(ps%dash_offset + mod(al(i0), period), period)
            call b%draw_path(ox(k0:k1 - 1), oy(k0:k1 - 1), ov(i0:i1 - 1), i1 - i0, pd)
            i0 = i1
            k0 = k1
        end do
    end subroutine emit_path

    ! al(v) is, for a move at verb v of the output, how far along the
    ! original contour it starts, for a dash pattern to carry on from.
    subroutine far_path(x, y, verbs, n_verb, filled, bx0, bx1, by0, by1, ox, oy, ov, al, no, nv)
        real(dp), intent(in) :: x(:), y(:), bx0, bx1, by0, by1
        integer, intent(in) :: verbs(:), n_verb
        logical, intent(in) :: filled
        real(dp), allocatable, intent(out) :: ox(:), oy(:), al(:)
        integer, allocatable, intent(out) :: ov(:)
        integer, intent(out) :: no, nv
        real(dp), allocatable :: cx(:), cy(:), qx(:), qy(:), cum(:)
        real(dp), allocatable :: sa(:, :)
        logical, allocatable :: sv(:), s0(:), s1(:)
        integer :: i, j, k, kc, v, m, nc, q, ns, first, t_i
        logical :: inside, pen, closed

        allocate (ox(16), oy(16), ov(16), al(16))
        al = 0.0_dp
        no = 0
        nv = 0
        k = 0
        i = 1
        do while (i <= n_verb)
            ! One contour: from a move to the next one.
            j = i + 1
            do while (j <= n_verb)
                if (verbs(j) == VERB_MOVE) exit
                j = j + 1
            end do
            kc = 0
            do v = i, j - 1
                if (verbs(v) == VERB_MOVE .or. verbs(v) == VERB_LINE) kc = kc + 1
                if (verbs(v) == VERB_CUBIC) kc = kc + 3
            end do
            inside = all(x(k + 1:k + kc) >= bx0 .and. x(k + 1:k + kc) <= bx1 .and. &
                         y(k + 1:k + kc) >= by0 .and. y(k + 1:k + kc) <= by1)
            if (inside) then
                q = k
                do v = i, j - 1
                    select case (verbs(v))
                    case (VERB_MOVE, VERB_LINE)
                        call grow_put(ox, oy, ov, no, nv, verbs(v), x(q + 1:q + 1), y(q + 1:q + 1))
                        q = q + 1
                    case (VERB_CUBIC)
                        call grow_put(ox, oy, ov, no, nv, VERB_CUBIC, x(q + 1:q + 3), y(q + 1:q + 3))
                        q = q + 3
                    case (VERB_CLOSE)
                        call grow_put(ox, oy, ov, no, nv, VERB_CLOSE, x(1:0), y(1:0))
                    end select
                end do
            else
                ! The contour as a polyline, curves flattened, closed by an
                ! explicit return to its start.
                nc = 0
                closed = .false.
                allocate (cx(16), cy(16))
                q = k
                do v = i, j - 1
                    select case (verbs(v))
                    case (VERB_MOVE, VERB_LINE)
                        call push_point(cx, cy, nc, x(q + 1), y(q + 1))
                        q = q + 1
                    case (VERB_CUBIC)
                        call flatten_cubic(cx, cy, nc, [cx(nc), x(q + 1), x(q + 2), x(q + 3)], &
                                           [cy(nc), y(q + 1), y(q + 2), y(q + 3)], &
                                           bx0, bx1, by0, by1, 0)
                        q = q + 3
                    case (VERB_CLOSE)
                        call push_point(cx, cy, nc, cx(1), cy(1))
                        closed = .true.
                    end select
                end do
                if (filled) then
                    call clip_to_box(cx(1:nc), cy(1:nc), bx0, bx1, by0, by1, qx, qy, m)
                    if (m >= 2) then
                        call grow_put(ox, oy, ov, no, nv, VERB_MOVE, qx(1:1), qy(1:1))
                        do v = 2, m
                            call grow_put(ox, oy, ov, no, nv, VERB_LINE, qx(v:v), qy(v:v))
                        end do
                        call grow_put(ox, oy, ov, no, nv, VERB_CLOSE, x(1:0), y(1:0))
                    end if
                else
                    ns = nc - 1
                    allocate (sa(4, max(ns, 1)), sv(max(ns, 1)), s0(max(ns, 1)), s1(max(ns, 1)))
                    allocate (cum(max(ns, 1) + 1))
                    cum(1) = 0.0_dp
                    do v = 1, ns
                        call clip_segment(cx(v), cy(v), cx(v + 1), cy(v + 1), bx0, bx1, by0, by1, &
                                          sa(1, v), sa(2, v), sa(3, v), sa(4, v), sv(v), s0(v), s1(v))
                        cum(v + 1) = min(cum(v) + hypot(cx(v + 1) - cx(v), cy(v + 1) - cy(v)), huge(1.0_dp))
                    end do
                    ! Not cut anywhere: the contour as it was, closed.
                    if (closed .and. all(sv(1:ns)) .and. .not. any(s0(1:ns)) .and. .not. any(s1(1:ns))) then
                        call grow_put(ox, oy, ov, no, nv, VERB_MOVE, cx(1:1), cy(1:1))
                        call set_along(al, nv, 0.0_dp)
                        do v = 2, ns
                            call grow_put(ox, oy, ov, no, nv, VERB_LINE, cx(v:v), cy(v:v))
                        end do
                        call grow_put(ox, oy, ov, no, nv, VERB_CLOSE, x(1:0), y(1:0))
                        deallocate (sa, sv, s0, s1, cum, cx, cy)
                        k = k + kc
                        i = j
                        cycle
                    end if
                    ! Where to begin: the first segment after a break, if the
                    ! contour closes on itself.
                    first = 1
                    if (closed) then
                        do v = 1, ns
                            q = v - 1
                            if (q < 1) q = ns
                            if (sv(v) .and. (s0(v) .or. .not. sv(q) .or. s1(q))) then
                                first = v
                                exit
                            end if
                        end do
                    end if
                    pen = .false.
                    do t_i = 0, ns - 1
                        v = mod(first - 1 + t_i, ns) + 1
                        if (.not. sv(v)) then
                            pen = .false.
                            cycle
                        end if
                        if (.not. (pen .and. .not. s0(v))) then
                            call grow_put(ox, oy, ov, no, nv, VERB_MOVE, sa(1:1, v), sa(2:2, v))
                            ! Pieces after the wrap of a closed contour come
                            ! once round it later.
                            call set_along(al, nv, min(cum(v) + hypot(sa(1, v) - cx(v), sa(2, v) - cy(v)) &
                                                       + merge(cum(ns + 1), 0.0_dp, v < first), huge(1.0_dp)))
                        end if
                        call grow_put(ox, oy, ov, no, nv, VERB_LINE, sa(3:3, v), sa(4:4, v))
                        pen = .not. s1(v)
                    end do
                    deallocate (sa, sv, s0, s1, cum)
                end if
                deallocate (cx, cy)
            end if
            k = k + kc
            i = j
        end do
        ! Every verb has its entry, zero where nothing set one.
        if (nv > size(al)) call set_along(al, nv, 0.0_dp)
    end subroutine far_path

    ! Appends the cubic from (px(1), py(1)) to (px(4), py(4)) to the
    ! polyline as points after its start: finely where it comes near the
    ! box, as a single chord where it does not, so that even a curve of a
    ! very large radius keeps within a twentieth of a point of itself in
    ! view.
    recursive subroutine flatten_cubic(cx, cy, nc, px, py, bx0, bx1, by0, by1, depth)
        real(dp), allocatable, intent(inout) :: cx(:), cy(:)
        integer, intent(inout) :: nc
        real(dp), intent(in) :: px(4), py(4), bx0, bx1, by0, by1
        integer, intent(in) :: depth
        real(dp) :: lx(4), ly(4), rx(4), ry(4), flat

        flat = max(abs(px(2) - (2.0_dp*px(1) + px(4))/3.0_dp), abs(py(2) - (2.0_dp*py(1) + py(4))/3.0_dp), &
                   abs(px(3) - (px(1) + 2.0_dp*px(4))/3.0_dp), abs(py(3) - (py(1) + 2.0_dp*py(4))/3.0_dp))
        if (depth >= 48 .or. flat <= 0.05_dp .or. minval(px) > bx1 .or. maxval(px) < bx0 .or. &
            minval(py) > by1 .or. maxval(py) < by0) then
            call push_point(cx, cy, nc, px(4), py(4))
            return
        end if
        ! de Casteljau at one half.
        lx(1) = px(1)
        ly(1) = py(1)
        lx(2) = 0.5_dp*px(1) + 0.5_dp*px(2)
        ly(2) = 0.5_dp*py(1) + 0.5_dp*py(2)
        rx(3) = 0.5_dp*px(3) + 0.5_dp*px(4)
        ry(3) = 0.5_dp*py(3) + 0.5_dp*py(4)
        rx(4) = px(4)
        ry(4) = py(4)
        lx(3) = 0.5_dp*lx(2) + 0.5_dp*(0.5_dp*px(2) + 0.5_dp*px(3))
        ly(3) = 0.5_dp*ly(2) + 0.5_dp*(0.5_dp*py(2) + 0.5_dp*py(3))
        rx(2) = 0.5_dp*(0.5_dp*px(2) + 0.5_dp*px(3)) + 0.5_dp*rx(3)
        ry(2) = 0.5_dp*(0.5_dp*py(2) + 0.5_dp*py(3)) + 0.5_dp*ry(3)
        lx(4) = 0.5_dp*lx(3) + 0.5_dp*rx(2)
        ly(4) = 0.5_dp*ly(3) + 0.5_dp*ry(2)
        rx(1) = lx(4)
        ry(1) = ly(4)
        call flatten_cubic(cx, cy, nc, lx, ly, bx0, bx1, by0, by1, depth + 1)
        call flatten_cubic(cx, cy, nc, rx, ry, bx0, bx1, by0, by1, depth + 1)
    end subroutine flatten_cubic

    subroutine set_along(al, nv, d)
        real(dp), allocatable, intent(inout) :: al(:)
        integer, intent(in) :: nv
        real(dp), intent(in) :: d
        real(dp), allocatable :: t(:)
        if (nv > size(al)) then
            allocate (t(2*nv))
            t = 0.0_dp
            t(1:size(al)) = al
            call move_alloc(t, al)
        end if
        al(nv) = d
    end subroutine set_along

    subroutine grow_put(ox, oy, ov, no, nv, verb, px, py)
        real(dp), allocatable, intent(inout) :: ox(:), oy(:)
        integer, allocatable, intent(inout) :: ov(:)
        integer, intent(inout) :: no, nv
        integer, intent(in) :: verb
        real(dp), intent(in) :: px(:), py(:)
        real(dp), allocatable :: tx(:)
        integer, allocatable :: tv(:)

        if (no + size(px) > size(ox)) then
            allocate (tx(2*(no + size(px))))
            tx(1:no) = ox(1:no)
            call move_alloc(tx, ox)
            allocate (tx(size(ox)))
            tx(1:no) = oy(1:no)
            call move_alloc(tx, oy)
        end if
        if (nv + 1 > size(ov)) then
            allocate (tv(2*(nv + 1)))
            tv(1:nv) = ov(1:nv)
            call move_alloc(tv, ov)
        end if
        nv = nv + 1
        ov(nv) = verb
        ox(no + 1:no + size(px)) = px
        oy(no + 1:no + size(py)) = py
        no = no + size(px)
    end subroutine grow_put

    subroutine push_point(cx, cy, n, px, py)
        real(dp), allocatable, intent(inout) :: cx(:), cy(:)
        integer, intent(inout) :: n
        real(dp), intent(in) :: px, py
        real(dp), allocatable :: t(:)

        if (n + 1 > size(cx)) then
            allocate (t(2*(n + 1)))
            t(1:n) = cx(1:n)
            call move_alloc(t, cx)
            allocate (t(size(cx)))
            t(1:n) = cy(1:n)
            call move_alloc(t, cy)
        end if
        n = n + 1
        cx(n) = px
        cy(n) = py
    end subroutine push_point

    pure logical function finite_point(x, y, k)
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: k
        finite_point = ieee_is_finite(x(k)) .and. ieee_is_finite(y(k))
    end function finite_point

    ! Starts a contour at (px, py). A move right after a move replaces it,
    ! since the first one would draw nothing.
    pure subroutine path_move(ox, oy, ov, no, nv, px, py)
        real(dp), intent(inout) :: ox(:), oy(:)
        integer, intent(inout) :: ov(:), no, nv
        real(dp), intent(in) :: px, py
        if (nv > 0) then
            if (ov(nv) == VERB_MOVE) then
                nv = nv - 1
                no = no - 1
            end if
        end if
        call path_put(ox, oy, ov, no, nv, VERB_MOVE, [px], [py])
    end subroutine path_move

    pure subroutine path_put(ox, oy, ov, no, nv, verb, px, py)
        real(dp), intent(inout) :: ox(:), oy(:)
        integer, intent(inout) :: ov(:), no, nv
        integer, intent(in) :: verb
        real(dp), intent(in) :: px(:), py(:)
        nv = nv + 1
        ov(nv) = verb
        ox(no + 1:no + size(px)) = px
        oy(no + 1:no + size(py)) = py
        no = no + size(px)
    end subroutine path_put

    subroutine put_rect(b, x, y, w, h, paint, radius)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius
        real(dp) :: bx0, bx1, by0, by1, x0, x1, y0, y1

        if (.not. all(ieee_is_finite([x, y, w, h]))) return
        call view_box(b, bx0, bx1, by0, by1, paint)
        if (x >= bx0 .and. y >= by0 .and. x + w <= bx1 .and. y + h <= by1) then
            call b%draw_rect(x, y, w, h, tame(paint), radius)
            return
        end if
        ! Cut to the box. The box lies further out than the stroke reaches,
        ! so the sides the cut makes cannot be seen.
        x0 = max(x, bx0)
        y0 = max(y, by0)
        x1 = min(x + w, bx1)
        y1 = min(y + h, by1)
        if (x1 < x0 .or. y1 < y0) return
        call b%draw_rect(x0, y0, x1 - x0, y1 - y0, tame(paint), radius)
    end subroutine put_rect

    subroutine put_circle(b, cx, cy, r, paint)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint
        real(dp) :: bx0, bx1, by0, by1, a
        real(dp), allocatable :: px(:), py(:)
        integer, allocatable :: v(:)
        integer :: i, n

        if (.not. all(ieee_is_finite([cx, cy, r]))) return
        call view_box(b, bx0, bx1, by0, by1, paint)
        if (cx - r >= bx0 .and. cx + r <= bx1 .and. cy - r >= by0 .and. cy + r <= by1) then
            call b%draw_circle(cx, cy, r, tame(paint))
            return
        end if
        ! Fine enough that a chord strays less than a tenth of a point
        ! from the circle, capped where only a sliver could be in view.
        n = max(64, min(200000, ceiling(PI*sqrt(min(r, 1.0e10_dp)/0.8_dp))))
        allocate (px(n), py(n), v(n + 1))
        do i = 1, n
            a = 2.0_dp*PI*real(i - 1, dp)/real(n, dp)
            px(i) = cx + r*cos(a)
            py(i) = cy + r*sin(a)
            v(i) = VERB_LINE
        end do
        v(1) = VERB_MOVE
        v(n + 1) = VERB_CLOSE
        call emit_path(b, px, py, v, n + 1, paint)
    end subroutine put_circle

    ! Markers at missing points are dropped; a marker whose own size is
    ! missing is not drawn anywhere.
    subroutine put_markers(b, x, y, mx, my, mverbs, n_mverb, paint)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x(:), y(:), mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint
        logical, allocatable :: keep(:)
        real(dp) :: bx0, bx1, by0, by1, e
        integer :: i

        if (.not. all(ieee_is_finite(mx)) .or. .not. all(ieee_is_finite(my))) return
        if (size(x) /= size(y)) then
            call b%draw_markers(x, y, mx, my, mverbs, n_mverb, paint)
            return
        end if
        allocate (keep(size(x)))
        keep = ieee_is_finite(x) .and. ieee_is_finite(y)
        call view_box(b, bx0, bx1, by0, by1, paint)
        e = max(maxval(abs(mx)), maxval(abs(my)), 0.0_dp)
        if (e > bx1 - bx0) then
            ! A marker larger than the box itself is drawn as the path it is.
            do i = 1, size(x)
                if (keep(i)) call emit_path(b, mx + x(i), my + y(i), mverbs, n_mverb, paint)
            end do
            return
        end if
        ! A marker further off the canvas than its own size cannot be seen.
        do i = 1, size(x)
            if (keep(i)) keep(i) = x(i) >= bx0 - e .and. x(i) <= bx1 + e .and. &
                                   y(i) >= by0 - e .and. y(i) <= by1 + e
        end do
        if (all(keep)) then
            call b%draw_markers(x, y, mx, my, mverbs, n_mverb, tame(paint))
        else
            call b%draw_markers(pack(x, keep), pack(y, keep), mx, my, mverbs, n_mverb, tame(paint))
        end if
    end subroutine put_markers

    ! An angle of more than a turn as one of less, in [0, 360). Whole turns
    ! are taken off a few at a time rather than through modulo, which not
    ! every compiler gets right for a real past 2**53; where the spacing of
    ! doubles is past a turn the angle has no meaning left, and any angle
    ! of the turn will do.
    pure function turn_angle(angle) result(a)
        real(dp), intent(in) :: angle
        real(dp) :: a
        integer :: i
        a = angle
        do i = 1, 64
            if (abs(a) < 360.0_dp) exit
            a = a - 360.0_dp*aint(a/360.0_dp)
        end do
        if (abs(a) >= 360.0_dp) a = 0.0_dp
        if (a < 0.0_dp) a = a + 360.0_dp
    end function turn_angle

    subroutine put_glyphs(b, x, y, run, paint, angle)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle
        real(dp) :: bx0, bx1, by0, by1, a

        if (.not. all(ieee_is_finite([x, y, angle]))) return
        ! An angle of many turns is the same as its last one, and the
        ! renderer takes no number past MAX_COORD.
        a = angle
        if (abs(a) > 360.0_dp) a = turn_angle(a)
        ! Text anchored outside the box is out of sight, and so, for all
        ! practical purposes, is text a trillion points tall.
        call view_box(b, bx0, bx1, by0, by1)
        if (x < bx0 .or. x > bx1 .or. y < by0 .or. y > by1) return
        if (run%n > 0) then
            if (maxval(abs(run%x(1:run%n))) > 1.0e12_dp .or. maxval(abs(run%y(1:run%n))) > 1.0e12_dp &
                .or. maxval(run%size(1:run%n)) > 1.0e12_dp) return
        end if
        call b%draw_glyphs(x, y, run, paint, a)
    end subroutine put_glyphs

    subroutine put_image(b, x, y, w, h, rgba, nx, ny, paint)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint
        real(dp) :: bx0, bx1, by0, by1, ga(2, 3), gb(2, 3)
        integer :: ka(2, 3), kb(2, 3), na, nb, i, j

        if (.not. all(ieee_is_finite([x, y, w, h]))) return
        call view_box(b, bx0, bx1, by0, by1)
        if (x >= bx0 .and. y >= by0 .and. x + w <= bx1 .and. y + h <= by1) then
            call b%draw_image(x, y, w, h, rgba, nx, ny, paint)
            return
        end if
        ! An image reaching out of the box is cut to the columns and rows in
        ! it. A column or row only partly in the box is drawn on its own,
        ! cut to the box: it is one color across, so nothing in view moves.
        call image_groups(x, w, nx, bx0, bx1, ka, ga, na)
        call image_groups(y, h, ny, by0, by1, kb, gb, nb)
        do i = 1, na
            do j = 1, nb
                call b%draw_image(ga(1, i), gb(1, j), ga(2, i) - ga(1, i), gb(2, j) - gb(1, j), &
                                  rgba(:, ka(1, i):ka(2, i), kb(1, j):kb(2, j)), &
                                  ka(2, i) - ka(1, i) + 1, kb(2, j) - kb(1, j) + 1, paint)
            end do
        end do
    end subroutine put_image

    ! The n cells of size w/n from x0 that meet [lo, hi], as at most three
    ! groups: k(1:2, g) the first and last cell of group g and e(1:2, g) the
    ! span it is drawn over. A cell only partly in [lo, hi] is a group of
    ! its own, its span cut to [lo, hi].
    subroutine image_groups(x0, w, n, lo, hi, k, e, ng)
        real(dp), intent(in) :: x0, w, lo, hi
        integer, intent(in) :: n
        integer, intent(out) :: k(2, 3)
        real(dp), intent(out) :: e(2, 3)
        integer, intent(out) :: ng
        real(dp) :: pw, left, right
        integer :: kmin, kmax, c, c2

        ng = 0
        if (n < 1 .or. w <= 0.0_dp) return
        pw = w/real(n, dp)
        ! The cells meeting [lo, hi], found in reals first so that a cell
        ! count far beyond an integer cannot overflow.
        kmin = 1 + int(max(0.0_dp, min(real(n - 1, dp), (lo - x0)/pw)))
        kmax = int(max(1.0_dp, min(real(n, dp), (hi - x0)/pw + 1.0_dp)))
        c = kmin
        do while (c <= kmax .and. ng < 3)
            left = x0 + real(c - 1, dp)*pw
            right = x0 + real(c, dp)*pw
            if (right < lo .or. left > hi) then
                c = c + 1
                cycle
            end if
            if (left < lo .or. right > hi) then
                ng = ng + 1
                k(:, ng) = [c, c]
                e(:, ng) = [max(left, lo), min(right, hi)]
                c = c + 1
            else
                c2 = c
                do while (c2 < kmax)
                    if (x0 + real(c2 + 1, dp)*pw > hi) exit
                    c2 = c2 + 1
                end do
                ng = ng + 1
                k(:, ng) = [c, c2]
                e(:, ng) = [left, x0 + real(c2, dp)*pw]
                c = c2 + 1
            end if
        end do
    end subroutine image_groups

    subroutine append_stroke_path(b, px, py, np, color, lw, alpha)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: px(:), py(:)
        integer, intent(in) :: np
        character(len=*), intent(in) :: color
        real(dp), intent(in) :: lw, alpha
        if (np < 2) return
        call put_path(b, px(1:np), py(1:np), line_verbs(np), np, &
                         pen(color, lw, alpha))
    end subroutine append_stroke_path

    ! A filled closed polygon, used by the shaped markers and by fill_between.
    subroutine append_polygon(b, px, py, np, color, alpha, seal)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: px(:), py(:)
        integer, intent(in) :: np
        character(len=*), intent(in) :: color
        real(dp), intent(in) :: alpha
        logical, intent(in), optional :: seal
        type(paint_t) :: p
        integer :: v(np + 1)

        if (np < 2) return
        v(1:np) = line_verbs(np)
        v(np + 1) = VERB_CLOSE
        p = brush(color, alpha)
        ! Abutting polygons leave a hairline of background showing through
        ! where the renderer antialiases both edges, so seal the seam by
        ! stroking the outline in the fill color.
        if (present(seal)) then
            if (seal) then
                p%stroked = .true.
                p%stroke_rgb = p%fill_rgb
                p%stroke_alpha = alpha
                p%line_width = 0.5_dp
            end if
        end if
        call put_path(b, px(1:np), py(1:np), v, np + 1, p)
    end subroutine append_polygon

    ! The outline of one marker, described about the origin, together with
    ! how it should be painted. Handing the renderer a shape plus a list of
    ! positions lets every backend name the outline once and then reference
    ! it: an SVG <use>, a PDF form XObject, a cached sprite in PNG.
    subroutine marker_shape(mk, ms, mx, my, mv, nv, np, do_fill, do_stroke, lw)
        integer, intent(in) :: mk
        real(dp), intent(in) :: ms
        real(dp), intent(out) :: mx(:), my(:)
        integer, intent(out) :: mv(:), nv, np
        logical, intent(out) :: do_fill, do_stroke
        real(dp), intent(out) :: lw
        real(dp) :: r, k, ang
        integer :: i

        do_fill = .true.
        do_stroke = .false.
        lw = 1.0_dp
        nv = 0
        np = 0

        select case (mk)
        case (MARKER_CIRCLE, MARKER_POINT)
            if (mk == MARKER_POINT) then
                r = 0.5_dp*ms*0.5_dp
            else
                r = 0.5_dp*ms
                do_stroke = .true.
            end if
            ! Four cubics with the standard offset match a circle to about a
            ! part in ten thousand, which is far below a pixel here.
            k = r*0.5522847498307933_dp
            mx(1) = r;  my(1) = 0.0_dp
            mx(2) = r;  my(2) = k
            mx(3) = k;  my(3) = r
            mx(4) = 0.0_dp; my(4) = r
            mx(5) = -k; my(5) = r
            mx(6) = -r; my(6) = k
            mx(7) = -r; my(7) = 0.0_dp
            mx(8) = -r; my(8) = -k
            mx(9) = -k; my(9) = -r
            mx(10) = 0.0_dp; my(10) = -r
            mx(11) = k; my(11) = -r
            mx(12) = r; my(12) = -k
            mx(13) = r; my(13) = 0.0_dp
            np = 13
            mv(1:6) = [VERB_MOVE, VERB_CUBIC, VERB_CUBIC, VERB_CUBIC, &
                       VERB_CUBIC, VERB_CLOSE]
            nv = 6
        case (MARKER_X)
            r = 0.5_dp*ms
            mx(1:4) = [-r, r, -r, r]
            my(1:4) = [-r, r, r, -r]
            mv(1:4) = [VERB_MOVE, VERB_LINE, VERB_MOVE, VERB_LINE]
            np = 4
            nv = 4
            do_fill = .false.
            do_stroke = .true.
            lw = 1.5_dp
        case (MARKER_PLUS)
            r = 0.5_dp*ms
            mx(1:4) = [-r, r, 0.0_dp, 0.0_dp]
            my(1:4) = [0.0_dp, 0.0_dp, -r, r]
            mv(1:4) = [VERB_MOVE, VERB_LINE, VERB_MOVE, VERB_LINE]
            np = 4
            nv = 4
            do_fill = .false.
            do_stroke = .true.
            lw = 1.5_dp
        case (MARKER_SQUARE)
            r = 0.5_dp*ms
            mx(1:4) = [-r, r, r, -r]
            my(1:4) = [-r, -r, r, r]
            np = 4
        case (MARKER_DIAMOND)
            ! The diamond is the unit square turned on its corner, so it
            ! reaches a half diagonal rather than a half side.
            r = 0.5_dp*ms*sqrt(2.0_dp)
            mx(1:4) = [0.0_dp, r, 0.0_dp, -r]
            my(1:4) = [-r, 0.0_dp, r, 0.0_dp]
            np = 4
        case (MARKER_TRI_UP)
            r = 0.5_dp*ms
            mx(1:3) = [0.0_dp, r, -r]
            my(1:3) = [-r, r, r]
            np = 3
        case (MARKER_TRI_DOWN)
            r = 0.5_dp*ms
            mx(1:3) = [0.0_dp, r, -r]
            my(1:3) = [r, -r, -r]
            np = 3
        case (MARKER_TRI_LEFT)
            r = 0.5_dp*ms
            mx(1:3) = [-r, r, r]
            my(1:3) = [0.0_dp, -r, r]
            np = 3
        case (MARKER_TRI_RIGHT)
            r = 0.5_dp*ms
            mx(1:3) = [r, -r, -r]
            my(1:3) = [0.0_dp, -r, r]
            np = 3
        case (MARKER_STAR)
            ! Five-pointed star: alternate outer and inner vertices.
            r = 0.5_dp*ms
            do i = 1, 10
                ang = -0.5_dp*PI + real(i - 1, dp)*PI/5.0_dp
                if (mod(i, 2) == 1) then
                    mx(i) = r*cos(ang)
                    my(i) = r*sin(ang)
                else
                    mx(i) = 0.5_dp*r*cos(ang)
                    my(i) = 0.5_dp*r*sin(ang)
                end if
            end do
            np = 10
        end select

        ! The polygonal markers all share one closed outline.
        if (nv == 0 .and. np > 0) then
            mv(1:np) = line_verbs(np)
            mv(np + 1) = VERB_CLOSE
            nv = np + 1
        end if
    end subroutine marker_shape

    ! Draw the same marker at every point of x/y.
    subroutine append_markers(b, mk, x, y, n, ms, color, alpha, face, edge, ewidth)
        class(renderer_t), intent(inout) :: b
        integer, intent(in) :: mk, n
        real(dp), intent(in) :: x(:), y(:), ms, alpha
        character(len=*), intent(in) :: color
        ! Empty face or edge means the colour of the line, which is what a
        ! marker takes when nothing else is said.
        character(len=*), intent(in), optional :: face, edge
        real(dp), intent(in), optional :: ewidth
        real(dp) :: mx(16), my(16), lw
        integer :: mv(16), nv, np
        logical :: do_fill, do_stroke
        type(paint_t) :: p

        if (mk == MARKER_NONE .or. n <= 0) return
        call marker_shape(mk, ms, mx, my, mv, nv, np, do_fill, do_stroke, lw)
        if (nv <= 0) return

        p%filled = do_fill
        p%stroked = do_stroke
        p%fill_rgb = hex_rgb(color)
        p%stroke_rgb = p%fill_rgb
        if (present(face)) then
            if (len_trim(face) > 0) then
                p%filled = .true.
                p%fill_rgb = hex_rgb(face)
            end if
        end if
        if (present(edge)) then
            if (len_trim(edge) > 0) then
                p%stroked = .true.
                p%stroke_rgb = hex_rgb(edge)
                if (lw <= 0.0_dp) lw = 1.0_dp
            end if
        end if
        if (present(ewidth)) then
            if (ewidth >= 0.0_dp) then
                p%stroked = p%stroked .or. ewidth > 0.0_dp
                lw = ewidth
            end if
        end if
        p%fill_alpha = alpha
        p%stroke_alpha = alpha
        p%line_width = lw
        p%clip = g_clip
        call put_markers(b, x(1:n), y(1:n), mx(1:np), my(1:np), mv(1:nv), nv, p)
    end subroutine append_markers

    ! One marker, for the legend key and anywhere else a single point is
    ! drawn on its own.
    subroutine append_marker(b, mk, cx, cy, ms, color, alpha)
        class(renderer_t), intent(inout) :: b
        integer, intent(in) :: mk
        real(dp), intent(in) :: cx, cy, ms
        character(len=*), intent(in) :: color
        real(dp), intent(in) :: alpha
        call append_markers(b, mk, [cx], [cy], 1, ms, color, alpha)
    end subroutine append_marker

    ! Text element. anchor is a matplotlib horizontal alignment
    ! (left/center/right) or an SVG anchor (start/middle/end). rot is a
    ! matplotlib rotation, counterclockwise in degrees.
    subroutine append_text(b, x, y, s, anchor, fontsize, color, rot, weight, &
                           slant, baseline)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, fontsize
        character(len=*), intent(in) :: s, anchor, color
        real(dp), intent(in), optional :: rot
        integer, intent(in), optional :: weight, slant, baseline
        type(font_t) :: f
        type(glyphrun_t) :: run
        integer :: an, bl
        real(dp) :: ang, w

        select case (anchor)
        case ("left", "start"); an = ANCHOR_START
        case ("right", "end"); an = ANCHOR_END
        case default; an = ANCHOR_MIDDLE
        end select
        f%size = fontsize
        if (present(weight)) f%weight = weight
        if (present(slant)) f%slant = slant
        bl = BASE_ALPHABETIC
        if (present(baseline)) bl = baseline
        ang = 0.0_dp
        ! The API turns angles clockwise, matplotlib counterclockwise.
        if (present(rot)) ang = -rot
        ! Reduced once here, so that glyphs and the rules of a formula turn
        ! by the same angle.
        if (abs(ang) > 360.0_dp) ang = turn_angle(ang)
        if (len_trim(s) == 0) return
        if (math_is(s)) then
            call append_math(b, x, y, s, f, brush(color), an, bl, ang)
        else
            call text_layout(s, f%size, text_face(f%weight, f%slant), 0.0_dp, &
                             0.0_dp, run, w)
            call align_run(run, w, f, an, bl)
            call put_glyphs(b, x, y, run, brush(color), ang)
        end if
    end subroutine append_text

    ! The extent of a line of text above and below its baseline, in points:
    ! the font's ascender and descender, which is what matplotlib sizes a
    ! line of text by and aligns it with. A line is their sum, 1.2 ems in
    ! Lato.
    pure elemental real(dp) function text_ascent(size)
        real(dp), intent(in) :: size
        text_ascent = face_ascent(FACE_REGULAR)*size
    end function text_ascent

    pure elemental real(dp) function text_descent(size)
        real(dp), intent(in) :: size
        text_descent = -face_descent(FACE_REGULAR)*size
    end function text_descent

    ! Where the baseline goes for text centred on y, below it: matplotlib's
    ! "center" puts the middle of the line there.
    pure elemental real(dp) function text_mid(size)
        real(dp), intent(in) :: size
        text_mid = 0.5_dp*(text_ascent(size) - text_descent(size))
    end function text_mid

    ! Width of a label in points, mathtext or not, as append_text sets it.
    function str_width(s, size, weight, slant) result(w)
        character(len=*), intent(in) :: s
        real(dp), intent(in) :: size
        integer, intent(in), optional :: weight, slant
        real(dp) :: w
        integer :: wt, sl
        wt = WEIGHT_NORMAL
        sl = SLANT_ROMAN
        if (present(weight)) wt = weight
        if (present(slant)) sl = slant
        if (math_is(s)) then
            w = math_width(s, size, text_face(wt, sl))
        else
            w = text_width(s, size, text_face(wt, sl))
        end if
    end function str_width

    ! Slide a laid out run so that its anchor sits at the origin: across
    ! by its width for the horizontal alignment, and down to the baseline
    ! for the vertical one, which goes by the line's ascent and descent as
    ! matplotlib's does.
    subroutine align_run(run, w, f, anchor, baseline, dx, dy)
        type(glyphrun_t), intent(inout) :: run
        real(dp), intent(in) :: w
        type(font_t), intent(in) :: f
        integer, intent(in) :: anchor, baseline
        real(dp), intent(out), optional :: dx, dy
        real(dp) :: x0, y0

        select case (anchor)
        case (ANCHOR_MIDDLE); x0 = -0.5_dp*w
        case (ANCHOR_END); x0 = -w
        case default; x0 = 0.0_dp
        end select
        select case (baseline)
        case (BASE_TOP); y0 = text_ascent(f%size)
        case (BASE_BOTTOM); y0 = -text_descent(f%size)
        case (BASE_MIDDLE); y0 = text_mid(f%size)
        case default; y0 = 0.0_dp
        end select
        call run_shift(run, 1, x0, y0)
        if (present(dx)) dx = x0
        if (present(dy)) dy = y0
    end subroutine align_run

    ! Mathtext is laid out into glyphs and rules: the glyphs are drawn as
    ! any other text and the rules (fraction bars, radical bars) as filled
    ! rectangles, turned with the text about the same origin.
    subroutine append_math(b, x, y, s, f, p, anchor, baseline, ang)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, ang
        character(len=*), intent(in) :: s
        type(font_t), intent(in) :: f
        type(paint_t), intent(in) :: p
        integer, intent(in) :: anchor, baseline
        type(glyphrun_t) :: run
        type(mrules_t) :: rules
        type(paint_t) :: rp
        type(font_t) :: mf
        integer :: i
        real(dp) :: w, x0, y0, ca, sa, rad, rx(4), ry(4)

        call math_layout(s, f%size, run, rules, w, text_face(f%weight, f%slant))
        ! The text around the math takes the weight and slant asked for, and
        ! the math is set in its regular font whatever they are; the faces
        ! share their metrics, so the run is aligned by the regular one.
        mf = f
        mf%weight = WEIGHT_NORMAL
        mf%slant = SLANT_ROMAN
        call align_run(run, w, mf, anchor, baseline, x0, y0)
        call put_glyphs(b, x, y, run, p, ang)

        rad = ang*PI/180.0_dp
        ca = cos(rad)
        sa = sin(rad)
        rp = p
        rp%filled = .true.
        rp%stroked = .false.
        do i = 1, rules%n
            rx = x0 + rules%x(i) + [0.0_dp, rules%w(i), rules%w(i), 0.0_dp]
            ry = y0 + rules%y(i) + [0.0_dp, 0.0_dp, rules%h(i), rules%h(i)]
            call put_path(b, x + rx*ca - ry*sa, y + rx*sa + ry*ca, &
                             [VERB_MOVE, VERB_LINE, VERB_LINE, VERB_LINE, VERB_CLOSE], &
                             5, rp)
        end do
    end subroutine append_math

    ! How many lines the string has, and where the k-th one lies in it.
    pure integer function line_count(s)
        character(len=*), intent(in) :: s
        integer :: i
        line_count = 1
        do i = 1, len_trim(s)
            if (s(i:i) == achar(10)) line_count = line_count + 1
        end do
    end function line_count

    pure subroutine line_bounds(s, k, i0, i1)
        character(len=*), intent(in) :: s
        integer, intent(in) :: k
        integer, intent(out) :: i0, i1
        integer :: i, n, seen

        n = len_trim(s)
        seen = 1
        i0 = 1
        i1 = n
        do i = 1, n
            if (s(i:i) /= achar(10)) cycle
            if (seen == k) then
                i1 = i - 1
                return
            end if
            seen = seen + 1
            i0 = i + 1
        end do
    end subroutine line_bounds

    ! The connector of an annotation: a shaft from the text to the point it
    ! talks about, pulled back at both ends, and optionally a two-stroke head
    ! at the point. Head geometry follows matplotlib's "->" style: it reaches
    ! 0.4 em back along the shaft and 0.2 em out to each side.
    subroutine append_arrow(b, t, px, py, tx, ty)
        class(renderer_t), intent(inout) :: b
        type(text_t), intent(in) :: t
        real(dp), intent(in) :: px, py, tx, ty
        real(dp) :: dx, dy, d, ux, uy, x0, y0, x1, y1, hl, hw
        real(dp) :: bx(3), by(3), cx, cy, qx(4), qy(4)

        dx = tx - px
        dy = ty - py
        d = sqrt(dx*dx + dy*dy)
        if (d <= 0.0_dp) return
        ! The control point of matplotlib's arc3: the midpoint pushed out
        ! sideways by rad times the length of the chord. The sideways
        ! direction is matplotlib's, which is the other way round here
        ! because pixels count downwards.
        cx = 0.5_dp*(px + tx) - t%arc_rad*dy
        cy = 0.5_dp*(py + ty) + t%arc_rad*dx
        ! Both ends are pulled back along the direction the shaft leaves in,
        ! which for a bowed shaft is the direction of the control point.
        call unit_towards(px, py, cx, cy, tx, ty, ux, uy)
        if (d <= 2.0_dp*t%arrow_shrink) return
        x0 = px + ux*t%arrow_shrink
        y0 = py + uy*t%arrow_shrink
        call unit_towards(tx, ty, cx, cy, px, py, ux, uy)
        x1 = tx + ux*t%arrow_shrink
        y1 = ty + uy*t%arrow_shrink
        ! The head points the way the shaft arrives, so keep that direction.
        ux = -ux
        uy = -uy
        if (t%arc_rad == 0.0_dp) then
            call append_line(b, x0, y0, x1, y1, trim(t%arrow_color), t%arrow_lw, &
                             LINE_SOLID, 1.0_dp)
        else
            ! The quadratic through the control point, written as the cubic
            ! the renderer draws.
            qx = [x0, x0 + 2.0_dp/3.0_dp*(cx - x0), x1 + 2.0_dp/3.0_dp*(cx - x1), x1]
            qy = [y0, y0 + 2.0_dp/3.0_dp*(cy - y0), y1 + 2.0_dp/3.0_dp*(cy - y1), y1]
            call put_path(b, qx, qy, [VERB_MOVE, VERB_CUBIC], 2, &
                             pen(trim(t%arrow_color), t%arrow_lw, 1.0_dp))
        end if
        if (.not. t%arrow_head) return
        hl = 0.4_dp*t%fontsize
        hw = 0.2_dp*t%fontsize
        bx(1) = x1 - hl*ux + hw*uy
        by(1) = y1 - hl*uy - hw*ux
        bx(2) = x1
        by(2) = y1
        bx(3) = x1 - hl*ux - hw*uy
        by(3) = y1 - hl*uy + hw*ux
        call append_stroke_path(b, bx, by, 3, trim(t%arrow_color), t%arrow_lw, &
                                1.0_dp)
    end subroutine append_arrow

    ! Unit vector from (x, y) towards (cx, cy), or towards the far end
    ! when the two coincide.
    subroutine unit_towards(x, y, cx, cy, fx, fy, ux, uy)
        real(dp), intent(in) :: x, y, cx, cy, fx, fy
        real(dp), intent(out) :: ux, uy
        real(dp) :: dx, dy, d
        dx = cx - x
        dy = cy - y
        d = sqrt(dx*dx + dy*dy)
        if (d <= 0.0_dp) then
            dx = fx - x
            dy = fy - y
            d = sqrt(dx*dx + dy*dy)
        end if
        if (d <= 0.0_dp) then
            ux = 0.0_dp
            uy = 0.0_dp
            return
        end if
        ux = dx/d
        uy = dy/d
    end subroutine unit_towards

    ! One annotation: its box, then its lines. A string is broken at every
    ! newline and the lines are stacked at matplotlib's spacing of 1.2 times
    ! the font size.
    subroutine append_annotation(b, t, px, py)
        class(renderer_t), intent(inout) :: b
        type(text_t), intent(in) :: t
        real(dp), intent(in) :: px, py
        integer :: nl, k, i0, i1, base
        real(dp) :: lh, dy, wmax, x0, y0, pad, hgt

        lh = 1.2_dp*t%fontsize
        nl = line_count(t%s)

        ! The vertical anchor is the backend's, except that the older
        ! placement has no name in matplotlib and so has none here either.
        select case (trim(t%va))
        case ("center"); base = BASE_MIDDLE
        case ("top"); base = BASE_TOP
        case ("bottom"); base = BASE_BOTTOM
        case default; base = BASE_ALPHABETIC
        end select
        dy = 0.0_dp
        if (len_trim(t%va) == 0) dy = 3.5_dp
        ! Extra lines hang below the first, so a block that is centred or
        ! bottom-aligned has to be lifted by the rest of its height.
        select case (trim(t%va))
        case ("center"); dy = dy - 0.5_dp*(nl - 1)*lh
        case ("bottom", "baseline"); dy = dy - (nl - 1)*lh
        end select

        if (t%has_box) then
            wmax = 0.0_dp
            do k = 1, nl
                call line_bounds(t%s, k, i0, i1)
                if (i1 >= i0) wmax = max(wmax, str_width(t%s(i0:i1), t%fontsize, &
                                                         t%weight, t%slant))
            end do
            pad = t%box_pad*t%fontsize
            hgt = (nl - 1)*lh + t%fontsize
            select case (trim(t%ha))
            case ("center"); x0 = px - 0.5_dp*wmax
            case ("right", "end"); x0 = px - wmax
            case default; x0 = px
            end select
            y0 = py + dy - text_ascent(t%fontsize)
            if (base == BASE_MIDDLE) y0 = py + dy - 0.5_dp*t%fontsize
            if (base == BASE_TOP) y0 = py + dy
            if (base == BASE_BOTTOM) y0 = py + dy - hgt
            ! A negative pad, which matplotlib takes, draws the box inside
            ! the text, and none at all once it has shrunk past nothing.
            if (wmax + 2.0_dp*pad < 0.0_dp .or. hgt + 2.0_dp*pad < 0.0_dp) then
                continue
            else if (trim(t%box_style) == "round") then
                call append_round_rect(b, x0 - pad, y0 - pad, wmax + 2.0_dp*pad, &
                                       hgt + 2.0_dp*pad, max(pad, 0.0_dp), trim(t%box_fc), &
                                       t%box_alpha, trim(t%box_ec))
            else if (len_trim(t%box_ec) > 0) then
                call append_rect(b, x0 - pad, y0 - pad, wmax + 2.0_dp*pad, &
                                 hgt + 2.0_dp*pad, trim(t%box_fc), t%box_alpha, &
                                 trim(t%box_ec), 1.0_dp)
            else
                call append_rect(b, x0 - pad, y0 - pad, wmax + 2.0_dp*pad, &
                                 hgt + 2.0_dp*pad, trim(t%box_fc), t%box_alpha)
            end if
        end if

        do k = 1, nl
            call line_bounds(t%s, k, i0, i1)
            if (i1 < i0) cycle
            call append_text(b, px, py + dy + (k - 1)*lh, t%s(i0:i1), &
                             trim(t%ha), t%fontsize, trim(t%color), rot=t%rot, &
                             weight=t%weight, slant=t%slant, baseline=base)
        end do
    end subroutine append_annotation

    ! Straight line segment in pixel coordinates.
    subroutine append_line(b, x1, y1, x2, y2, color, lw, ls, alpha)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x1, y1, x2, y2, lw
        character(len=*), intent(in) :: color
        integer, intent(in) :: ls
        real(dp), intent(in) :: alpha
        if (ls == LINE_NONE) return
        call put_path(b, [x1, x2], [y1, y2], [VERB_MOVE, VERB_LINE], 2, &
                         pen(color, lw, alpha, ls))
    end subroutine append_line

    ! matplotlib's hatching: lines ruled across the shape and clipped to
    ! it. The pattern is anchored to the canvas rather than to the shape,
    ! so that neighbouring shapes line up, and the spacings are the ones
    ! matplotlib puts in its 72 point tile. "/", "\", "|", "-", "+" and "x"
    ! say which way the lines run; repeating a character packs them closer,
    ! which is what matplotlib's density does.
    subroutine append_hatch(b, px, py, np, pattern, color, alpha)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: px(:), py(:)
        integer, intent(in) :: np
        character(len=*), intent(in) :: pattern, color
        real(dp), intent(in) :: alpha
        character(len=7) :: col

        col = "#000000"
        if (len_trim(color) > 0) col = color
        call hatch_family(b, px, py, np, 1, char_count(pattern, "|") &
                          + char_count(pattern, "+"), col, alpha)
        call hatch_family(b, px, py, np, 2, char_count(pattern, "-") &
                          + char_count(pattern, "+"), col, alpha)
        call hatch_family(b, px, py, np, 3, char_count(pattern, "/") &
                          + char_count(pattern, "x"), col, alpha)
        call hatch_family(b, px, py, np, 4, char_count(pattern, achar(92)) &
                          + char_count(pattern, "x"), col, alpha)
    end subroutine append_hatch

    pure function char_count(s, c) result(n)
        character(len=*), intent(in) :: s, c
        integer :: n, i
        n = 0
        do i = 1, len_trim(s)
            if (s(i:i) == c) n = n + 1
        end do
    end function char_count

    ! One family of parallel lines. Each line is written as a point and a
    ! direction, and the family as the offsets c of its members: x for the
    ! uprights, y for the flats, x+y and x-y for the two diagonals.
    subroutine hatch_family(b, px, py, np, fam, nrep, color, alpha)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: px(:), py(:)
        integer, intent(in) :: np, fam, nrep
        character(len=*), intent(in) :: color
        real(dp), intent(in) :: alpha
        real(dp) :: x0, x1, y0, y1, step, c0, cmin, cmax, c, dx, dy, ox, oy
        integer :: k, k0, k1

        if (nrep < 1 .or. np < 3) return
        x0 = minval(px(1:np))
        x1 = maxval(px(1:np))
        y0 = minval(py(1:np))
        y1 = maxval(py(1:np))

        select case (fam)
        case (1)
            step = 12.0_dp/real(nrep, dp)
            c0 = 0.5_dp*step
            cmin = x0
            cmax = x1
            dx = 0.0_dp
            dy = 1.0_dp
        case (2)
            step = 12.0_dp/real(nrep, dp)
            c0 = 0.5_dp*step
            cmin = y0
            cmax = y1
            dx = 1.0_dp
            dy = 0.0_dp
        case (3)
            ! The diagonals are twice as far apart in c as the uprights,
            ! which is what leaves them the same distance apart on paper.
            step = 24.0_dp/real(nrep, dp)
            c0 = 0.0_dp
            cmin = x0 + y0
            cmax = x1 + y1
            dx = 1.0_dp
            dy = -1.0_dp
        case default
            step = 24.0_dp/real(nrep, dp)
            c0 = 0.0_dp
            cmin = x0 - y1
            cmax = x1 - y0
            dx = 1.0_dp
            dy = 1.0_dp
        end select

        k0 = floor((cmin - c0)/step)
        k1 = ceiling((cmax - c0)/step)
        do k = k0, k1
            c = c0 + real(k, dp)*step
            select case (fam)
            case (2)
                ox = 0.0_dp
                oy = c
            case default
                ox = c
                oy = 0.0_dp
            end select
            call hatch_line(b, px, py, np, ox, oy, dx, dy, color, alpha)
        end do
    end subroutine hatch_family

    ! One ruled line, cut to the parts of it that lie inside the shape.
    ! Where the line crosses the outline an odd number of times it is in,
    ! so the crossings sort into pairs and every pair is one dash.
    subroutine hatch_line(b, px, py, np, ox, oy, dx, dy, color, alpha)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: px(:), py(:)
        integer, intent(in) :: np
        real(dp), intent(in) :: ox, oy, dx, dy
        character(len=*), intent(in) :: color
        real(dp), intent(in) :: alpha
        real(dp) :: ts(np + 1), ex, ey, det, t, s, ax_, ay
        integer :: i, j, nt

        nt = 0
        do i = 1, np
            j = i + 1
            if (j > np) j = 1
            ax_ = px(i)
            ay = py(i)
            ex = px(j) - ax_
            ey = py(j) - ay
            det = -dx*ey + ex*dy
            if (abs(det) < 1.0e-12_dp) cycle
            s = (dx*(ay - oy) - dy*(ax_ - ox))/det
            ! Half open, so a crossing exactly at a vertex counts once.
            if (s < 0.0_dp .or. s >= 1.0_dp) cycle
            t = (-(ax_ - ox)*ey + ex*(ay - oy))/det
            nt = nt + 1
            ts(nt) = t
        end do
        if (nt < 2) return
        call sort_in_place(ts(1:nt))
        do i = 1, nt - 1, 2
            call append_line(b, ox + ts(i)*dx, oy + ts(i)*dy, &
                             ox + ts(i + 1)*dx, oy + ts(i + 1)*dy, &
                             color, 1.0_dp, LINE_SOLID, alpha)
        end do
    end subroutine hatch_line

    ! An axis aligned filled rectangle, optionally outlined.
    ! A rectangle with quarter-circle corners of radius r, which is
    ! matplotlib's "round" box style.
    subroutine append_round_rect(b, x, y, w, h, r, color, alpha, edge)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, w, h, r, alpha
        character(len=*), intent(in) :: color, edge
        real(dp) :: px(17), py(17), k, rr
        integer :: v(10)
        type(paint_t) :: p

        rr = min(r, 0.5_dp*w, 0.5_dp*h)
        k = rr*(1.0_dp - 0.5522847498307933_dp)
        px = [x + rr, x + w - rr, x + w - k, x + w, x + w, &
              x + w, x + w, x + w - k, x + w - rr, x + rr, &
              x + k, x, x, x, x, x + k, x + rr]
        py = [y, y, y, y + k, y + rr, &
              y + h - rr, y + h - k, y + h, y + h, y + h, &
              y + h, y + h - k, y + h - rr, y + rr, y + k, y, y]
        v = [VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_LINE, VERB_CUBIC, &
             VERB_LINE, VERB_CUBIC, VERB_LINE, VERB_CUBIC, VERB_CLOSE]
        p%clip = g_clip
        if (len_trim(color) > 0) then
            p%filled = .true.
            p%fill_rgb = hex_rgb(color)
            p%fill_alpha = alpha
        end if
        if (len_trim(edge) > 0) then
            p%stroked = .true.
            p%stroke_rgb = hex_rgb(edge)
            p%line_width = 1.0_dp
        end if
        call put_path(b, px, py, v, 10, p)
    end subroutine append_round_rect

    subroutine append_rect(b, x, y, w, h, color, alpha, edge, elw)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, w, h
        character(len=*), intent(in) :: color
        real(dp), intent(in), optional :: alpha
        character(len=*), intent(in), optional :: edge
        real(dp), intent(in), optional :: elw
        type(paint_t) :: p

        p%clip = g_clip
        if (len_trim(color) > 0) then
            p%filled = .true.
            p%fill_rgb = hex_rgb(color)
            if (present(alpha)) p%fill_alpha = alpha
        end if
        if (present(edge)) then
            p%stroked = .true.
            p%stroke_rgb = hex_rgb(edge)
            p%line_width = 1.0_dp
            if (present(elw)) p%line_width = elw
        end if
        call put_rect(b, x, y, w, h, p)
    end subroutine append_rect

    subroutine append_open_circle(b, cx, cy, r, color)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: cx, cy, r
        character(len=*), intent(in) :: color
        call put_circle(b, cx, cy, r, pen(color, 1.0_dp))
    end subroutine append_open_circle

    ! One wedge: out along a radius, round the rim, back to the centre.
    !
    ! The rim is emitted as cubics rather than as an SVG arc. Only SVG has an
    ! arc primitive, so flattening here is what lets the same wedge reach a
    ! PDF or a rasterizer unchanged. Splitting at 90 degrees keeps the error
    ! of the standard cubic approximation far below a pixel.
    subroutine append_wedge(b, cx, cy, rx, ry, a0, a1, color, alpha, edge, ewidth)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: cx, cy, rx, ry, a0, a1, alpha
        character(len=*), intent(in) :: color
        ! matplotlib leaves a wedge edgeless unless wedgeprops asks for one.
        character(len=*), intent(in), optional :: edge
        real(dp), intent(in), optional :: ewidth
        integer, parameter :: MAXSEG = 8
        real(dp) :: px(2 + 3*MAXSEG), py(2 + 3*MAXSEG)
        integer :: verbs(3 + MAXSEG), np, nv, nseg, i
        real(dp) :: t0, t1, dt, al
        type(paint_t) :: p

        ! A wedge of a missing size, or about a missing centre, is not
        ! drawn; its angle would not even give a number of segments.
        if (.not. all(ieee_is_finite([cx, cy, rx, ry, a0, a1]))) return
        nseg = max(1, min(MAXSEG, int(abs(a1 - a0)/(0.5_dp*PI)) + 1))
        dt = (a1 - a0)/real(nseg, dp)
        ! y grows downwards on the canvas, so the sine term is subtracted.
        px(1) = cx
        py(1) = cy
        px(2) = cx + rx*cos(a0)
        py(2) = cy - ry*sin(a0)
        np = 2
        verbs(1) = VERB_MOVE
        verbs(2) = VERB_LINE
        nv = 2

        al = 4.0_dp/3.0_dp*tan(0.25_dp*dt)
        do i = 1, nseg
            t0 = a0 + real(i - 1, dp)*dt
            t1 = t0 + dt
            ! Control points ride the tangents at each end of the segment.
            px(np + 1) = cx + rx*cos(t0) + al*(-rx*sin(t0))
            py(np + 1) = cy - ry*sin(t0) + al*(-ry*cos(t0))
            px(np + 2) = cx + rx*cos(t1) - al*(-rx*sin(t1))
            py(np + 2) = cy - ry*sin(t1) - al*(-ry*cos(t1))
            px(np + 3) = cx + rx*cos(t1)
            py(np + 3) = cy - ry*sin(t1)
            np = np + 3
            nv = nv + 1
            verbs(nv) = VERB_CUBIC
        end do
        nv = nv + 1
        verbs(nv) = VERB_CLOSE

        p = brush(color, alpha)
        if (present(edge)) then
            if (len_trim(edge) > 0) then
                p%stroked = .true.
                p%stroke_rgb = hex_rgb(edge)
                p%stroke_alpha = alpha
                p%line_width = 1.0_dp
                if (present(ewidth)) p%line_width = ewidth
            end if
        end if
        call put_path(b, px(1:np), py(1:np), verbs(1:nv), nv, p)
    end subroutine append_wedge

    ! Cells are grown by a hairline so that neighbours overlap; without it the
    ! renderer leaves visible seams between abutting rectangles.
    subroutine append_cell(b, x, y, w, h, color)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, w, h
        character(len=*), intent(in) :: color
        real(dp), parameter :: BLEED = 0.05_dp
        call append_rect(b, x - BLEED, y - BLEED, w + 2.0_dp*BLEED, &
                         h + 2.0_dp*BLEED, color)
    end subroutine append_cell

    subroutine append_tick(b, x1, y1, x2, y2)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x1, y1, x2, y2
        call append_line(b, x1, y1, x2, y2, rc_text_color, 0.8_dp, LINE_SOLID, 1.0_dp)
    end subroutine append_tick

    subroutine append_spine(b, x1, y1, x2, y2)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x1, y1, x2, y2
        call append_line(b, x1, y1, x2, y2, rc_spine_color, rc_spine_lw, LINE_SOLID, 1.0_dp)
    end subroutine append_spine

    ! A tick at (x, y) on a spine whose outward normal is (ox, oy). dir 1
    ! puts it outside the axes, -1 inside, 0 straddling the spine.
    subroutine append_tick_at(b, x, y, ox, oy, dir, length)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, ox, oy, dir, length
        real(dp) :: a, c
        if (dir > 0.0_dp) then
            a = 0.0_dp
            c = length
        else if (dir < 0.0_dp) then
            a = 0.0_dp
            c = -length
        else
            a = -length
            c = length
        end if
        call append_tick(b, x + ox * a, y + oy * a, x + ox * c, y + oy * c)
    end subroutine append_tick_at

    ! A tick label, rotated about its anchor when asked.
    subroutine append_tick_text(b, x, y, s, anchor, fontsize, rot)
        class(renderer_t), intent(inout) :: b
        real(dp), intent(in) :: x, y, fontsize, rot
        character(len=*), intent(in) :: s, anchor
        call append_text(b, x, y, s, anchor, fontsize, rc_text_color, rot)
    end subroutine append_tick_text

end module fplotlib_artist
