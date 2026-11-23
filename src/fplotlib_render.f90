! fplotlib_render — the backend rendering API.
!
! One abstract drawing target that SVG, PNG, PDF, EPS and recorders implement. The plotting
! code above it never learns which one it is talking to, so a new output format
! is a new module here and nothing else.
!
! Four rules keep the API from leaking any one format's habits:
!
!   1. No hidden paint state. Every drawing call carries the paint it should be
!      drawn with, so nothing depends on what was called before it. A backend
!      may cache the last paint internally to avoid re-emitting attributes,
!      but that is its own business and cannot be observed through the API.
!      Canvas lifecycle and transform/clip scopes are explicit.
!
!   2. Purely additive, in painter's order. Calls are composited in the order
!      they arrive; later drawings cover earlier ones. A raster backend can
!      therefore rasterize each call immediately and never has to keep a
!      display list. Only the container has to wait: PNG deflates, PDF writes
!      its xref and SVG closes its root element in close_canvas.
!
!   3. One coordinate system, fixed here rather than negotiated. Points
!      (1/72 inch), origin at the top left, x right, y down, angles in degrees
!      clockwise. PDF and EPS flip this internally; PNG scales by its own dpi.
!      Callers never ask which way is up.
!
!   4. Geometry is reduced to what all four can express: straight lines and
!      cubic Beziers. There is no arc primitive, because only SVG has one;
!      the front end flattens its pie wedges into cubics that every backend
!      can already draw.
!
! What counts as a primitive
! --------------------------
! A call earns a place in the backend contract only when a backend has a real
! decision to make about it. Each is deferred, as draw_path_impl and so on,
! so the compiler tells a backend author exactly what has to be written:
!
!   draw_path     the universal fallback shape
!   draw_rect     SVG <rect>, PDF "re", EPS rectfill, PNG an exact axis
!                 aligned span fill that needs no scanline work at all
!   draw_circle   SVG <circle>, EPS "arc", PNG an exact antialiased disc;
!                 PDF alone has to approximate with four cubics
!   draw_markers  one shape stamped at many points: SVG <defs> plus <use>,
!                 PDF a form XObject, EPS a defined procedure, PNG a cached
!                 sprite. Matplotlib emits 3330 <use> elements across our
!                 reference figures, so this is where scatter plots are won
!   draw_glyphs   text, as glyphs already laid out: PNG fills them, SVG
!                 defines each glyph once and places it with <use>, PDF and
!                 EPS embed a Type 3 font built from the same outlines
!   draw_image    a raster block, for imshow
!
! Anything a backend would only ever implement one way is not a primitive, and
! it is not in this file at all. Lines, polylines and polygons are just paths,
! so the front end builds the path and calls draw_path; there is nothing for a
! backend to decide and so nothing to declare. Matplotlib goes further still
! and has draw_path as its only geometry primitive; its SVG backend emits no
! <rect> or <circle> at all, trading file size for a smaller contract.
!
! By the same rule this module is the interface, and the checks that enforce
! it, and nothing else. Text metrics,
! arc flattening and circle-to-cubic conversion are all absent: either a
! backend has a real reason to do them its own way, in which case that is the
! backend's own code, or it does not, in which case it belongs to whoever
! calls the API rather than to the API.
!
! begin_frame_impl and end_frame_impl scope an affine transform and a local
! clip. Unlike named groups, these change the picture and cannot be ignored:
! their concrete defaults accept only the identity without a clip, and stop
! on anything else, so a target that cannot transform says so.
!
! begin_group_impl and end_group_impl are different again: they are concrete
! and default to doing nothing, because doing nothing is the correct implementation for a
! format without a document tree, not a lazy one. See the note on groups.
!
! Errors
! ------
! Nothing in this contract returns an error. A call that breaks it, such as
! drawing before open_canvas, a coordinate that is not finite or lies
! beyond MAX_COORD (1e15 points), or an end_group without a begin_group,
! is a bug in the caller and stops the program with a message naming the
! rule (contract_error in fplotlib_status). A correct sequence of
! calls always succeeds.
!
! The checks are made here, once, rather than in each backend. Every public
! method of renderer_t is non_overridable: it checks the call, keeps the
! canvas state (open, finished, group depth) and only then calls the
! backend's *_impl method, which may therefore assume a valid call. A backend
! cannot forget a check, and no two backends can disagree about one. A call
! that draws nothing -- a path without verbs, markers at no points, an empty
! glyph run -- returns before it reaches the backend.
!
! The *_impl bindings and the state components are public only because
! Fortran cannot otherwise let a backend in another module implement or
! read them. They are for backends: code that draws calls the methods
! without the suffix, since calling an *_impl directly skips the checks.
! open_canvas records width and height after open_canvas_impl returns, so
! a backend sizes itself from its arguments, not from those components.

module fplotlib_render
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use fplotlib_style, only: dp
    use fplotlib_status, only: contract_error
    use fplotlib_glyphs_data, only: NGLYPH
    implicit none
    private

    public :: renderer_t, encoded_renderer_t, paint_t, font_t, clip_t, glyphrun_t
    public :: VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_CLOSE
    public :: CAP_BUTT, CAP_ROUND, CAP_SQUARE
    public :: JOIN_MITER, JOIN_ROUND, JOIN_BEVEL
    public :: FILL_NONZERO, FILL_EVENODD
    public :: ANCHOR_START, ANCHOR_MIDDLE, ANCHOR_END
    public :: BASE_ALPHABETIC, BASE_MIDDLE, BASE_TOP, BASE_BOTTOM
    public :: WEIGHT_NORMAL, WEIGHT_BOLD, SLANT_ROMAN, SLANT_ITALIC
    public :: MAX_DASH, MAX_COORD, MAX_PEN_PER_DASH
    public :: frame_decimals

    ! Path verbs. A path is x/y vertex arrays plus one verb per vertex group:
    ! MOVE and LINE consume one vertex, CUBIC consumes three (two controls and
    ! an endpoint), CLOSE consumes none.
    integer, parameter :: VERB_MOVE = 1
    integer, parameter :: VERB_LINE = 2
    integer, parameter :: VERB_CUBIC = 3
    integer, parameter :: VERB_CLOSE = 4

    integer, parameter :: CAP_BUTT = 0, CAP_ROUND = 1, CAP_SQUARE = 2
    integer, parameter :: JOIN_MITER = 0, JOIN_ROUND = 1, JOIN_BEVEL = 2
    integer, parameter :: FILL_NONZERO = 0, FILL_EVENODD = 1

    integer, parameter :: ANCHOR_START = 0, ANCHOR_MIDDLE = 1, ANCHOR_END = 2
    integer, parameter :: BASE_ALPHABETIC = 0, BASE_MIDDLE = 1
    integer, parameter :: BASE_TOP = 2, BASE_BOTTOM = 3

    ! Styles of the built-in sans family. Font selection is carried by glyph
    ! IDs in a finished run, not by an unsupported family preference.
    integer, parameter :: WEIGHT_NORMAL = 0, WEIGHT_BOLD = 1
    integer, parameter :: SLANT_ROMAN = 0, SLANT_ITALIC = 1

    integer, parameter :: MAX_DASH = 8

    ! Every coordinate, size and width is finite and at most this far from
    ! zero, in points. The plotting layer clips its geometry long before.
    real(dp), parameter :: MAX_COORD = 1.0e15_dp

    ! A dashed pen with round or square ends is at most this many times as
    ! wide as its dash pattern is long.
    real(dp), parameter :: MAX_PEN_PER_DASH = 100.0_dp

    ! Rectangular clip. fplotlib only ever clips series to the axes box, and a
    ! rectangle is the one clip shape all four formats support cheaply.
    ! Carried inside the paint so that drawing stays stateless; a backend is
    ! free to notice a run of identical clips and emit one SVG <g> for them.
    type :: clip_t
        logical :: on = .false.
        real(dp) :: x = 0.0_dp, y = 0.0_dp, w = 0.0_dp, h = 0.0_dp
    end type clip_t

    ! Everything needed to draw one thing, passed by value. This is the
    ! equivalent of a graphics pipeline object in a modern GPU API: build it
    ! once, hand it to many draw calls, and no call can disturb another.
    !
    ! Colors are numeric, not "#rrggbb": a rasterizer needs the components
    ! and only the SVG backend wants the hex spelling.
    type :: paint_t
        logical :: filled = .false.
        integer :: fill_rgb(3) = [0, 0, 0]
        real(dp) :: fill_alpha = 1.0_dp
        ! FILL_NONZERO or FILL_EVENODD, which every backend honours.
        integer :: fill_rule = FILL_NONZERO

        logical :: stroked = .false.
        integer :: stroke_rgb(3) = [0, 0, 0]
        real(dp) :: stroke_alpha = 1.0_dp
        real(dp) :: line_width = 1.0_dp
        integer :: cap = CAP_BUTT
        integer :: join = JOIN_MITER
        real(dp) :: miter_limit = 10.0_dp

        ! Dash pattern in points, empty means solid.
        integer :: n_dash = 0
        real(dp) :: dash(MAX_DASH) = 0.0_dp
        real(dp) :: dash_offset = 0.0_dp

        type(clip_t) :: clip
    end type paint_t

    type :: font_t
        real(dp) :: size = 10.0_dp
        integer :: weight = WEIGHT_NORMAL
        integer :: slant = SLANT_ROMAN
    end type font_t

    ! Text, laid out. Glyph i is gid(i) of fplotlib_glyphs at font size
    ! size(i), its origin (x(i), y(i)) points from the run's origin along
    ! the text direction, y down. The layout -- which glyph, kerning,
    ! scripts and fractions -- is the front end's, done once for every
    ! backend, so the four cannot disagree about where a glyph goes.
    ! text is the string the run was made from, for a backend that can
    ! keep it searchable.
    type :: glyphrun_t
        integer :: n = 0
        integer, allocatable :: gid(:)
        integer, allocatable :: font(:), first(:), last(:)
        real(dp), allocatable :: x(:), y(:), size(:)
        character(len=:), allocatable :: text
        ! first:last are inclusive UTF-8 byte ranges, zero when unmapped.
        ! Math source is TeX, not a Unicode replacement for the painted formula.
        logical :: source_math = .false.
    end type glyphrun_t

    type, abstract :: renderer_t
        ! The canvas state. The methods below keep it; a backend may read it
        ! but never sets it.
        real(dp) :: width = 0.0_dp    ! canvas size in points
        real(dp) :: height = 0.0_dp
        logical :: is_open = .false.
        logical :: is_finished = .false.   ! closed since the last open
        integer :: n_group = 0             ! groups begun and not yet ended
        integer :: n_frame = 0             ! frames begun and not yet ended
        ! For each open frame, outermost first, log10 of a bound on how
        ! much it and the frames around it magnify: see frame_decimals.
        real(dp), allocatable, private :: frame_log_zoom(:)
        ! The open groups (G) and frames (F), innermost last: each must end
        ! inside whatever began after it.
        character(len=:), allocatable :: scopes
    contains
        ! The contract. Each method checks the call and then hands it to
        ! the backend's implementation below.
        procedure, non_overridable :: open_canvas, close_canvas
        procedure, non_overridable :: draw_path, draw_rect, draw_circle
        procedure, non_overridable :: draw_markers, draw_glyphs, draw_image
        procedure, non_overridable :: begin_group, end_group
        procedure, non_overridable :: begin_frame, end_frame

        ! Lifecycle.
        procedure(open_canvas_i), deferred :: open_canvas_impl
        procedure(close_canvas_i), deferred :: close_canvas_impl

        ! The primitives. Every one is a decision a backend has to make for
        ! itself, which is why none of them has a default.
        procedure(draw_path_i), deferred :: draw_path_impl
        procedure(draw_rect_i), deferred :: draw_rect_impl
        procedure(draw_circle_i), deferred :: draw_circle_impl
        procedure(draw_markers_i), deferred :: draw_markers_impl
        procedure(draw_glyphs_i), deferred :: draw_glyphs_impl
        procedure(draw_image_i), deferred :: draw_image_impl

        ! Structure. Concrete, and doing nothing is a correct implementation
        ! for any format without a document tree.
        procedure :: begin_group_impl
        procedure :: end_group_impl

        ! Frames. Concrete, accepting only the identity without a clip; every
        ! built-in backend overrides them.
        procedure :: begin_frame_impl
        procedure :: end_frame_impl
    end type renderer_t

    ! Encoding is separate from drawing: a recorder or an interactive target
    ! need not invent a file format or implement a meaningless bytes method.
    type, abstract, extends(renderer_t) :: encoded_renderer_t
    contains
        procedure, non_overridable :: bytes
        procedure(bytes_i), deferred :: bytes_impl
    end type encoded_renderer_t

    abstract interface

        ! Canvas size is fixed up front because PDF needs a MediaBox, EPS a
        ! BoundingBox and SVG a width/height before any drawing is emitted.
        !
        ! x0/y0 move the canvas rectangle's top left corner, which is how a
        ! figure gets cropped: drawing coordinates are untouched and the
        ! window onto them moves instead. Every format takes this natively,
        ! as an SVG viewBox, a PDF MediaBox or an EPS BoundingBox, so it
        ! costs nothing to expose and saves the caller translating geometry.
        subroutine open_canvas_i(self, width, height, bg_rgb, bg_alpha, x0, y0)
            import :: renderer_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: width, height
            integer, intent(in), optional :: bg_rgb(3)
            real(dp), intent(in), optional :: bg_alpha
            real(dp), intent(in), optional :: x0, y0
        end subroutine open_canvas_i

        ! Finalizes the container: deflate and CRC for PNG, xref for PDF,
        ! trailer for EPS, closing tag for SVG.
        subroutine close_canvas_i(self)
            import :: renderer_t
            class(renderer_t), intent(inout) :: self
        end subroutine close_canvas_i

        ! The finished document. A character string rather than a specific
        ! file type, so binary formats can return raw bytes and callers can
        ! write a file or hand it to a notebook without a temporary file.
        function bytes_i(self) result(b)
            import :: encoded_renderer_t
            class(encoded_renderer_t), intent(in) :: self
            character(len=:), allocatable :: b
        end function bytes_i

        ! n_verb entries of verbs() describe the vertices in x()/y(): MOVE and
        ! LINE take one vertex, CUBIC takes three, CLOSE takes none.
        subroutine draw_path_i(self, x, y, verbs, n_verb, paint)
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x(:), y(:)
            integer, intent(in) :: verbs(:), n_verb
            type(paint_t), intent(in) :: paint
        end subroutine draw_path_i

        ! radius rounds the corners, as the legend box needs. Axis aligned, so
        ! a rasterizer can fill whole spans and skip antialiasing on the two
        ! edges that fall on pixel boundaries.
        subroutine draw_rect_i(self, x, y, w, h, paint, radius)
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x, y, w, h
            type(paint_t), intent(in) :: paint
            real(dp), intent(in), optional :: radius
        end subroutine draw_rect_i

        subroutine draw_circle_i(self, cx, cy, r, paint)
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: cx, cy, r
            type(paint_t), intent(in) :: paint
        end subroutine draw_circle_i

        ! One shape, described once about the origin, stamped at every point
        ! in x/y with a single paint. The whole reason this is a primitive is
        ! that every format can express the shape once and then reference it.
        subroutine draw_markers_i(self, x, y, mx, my, mverbs, n_mverb, paint)
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x(:), y(:)
            real(dp), intent(in) :: mx(:), my(:)
            integer, intent(in) :: mverbs(:), n_mverb
            type(paint_t), intent(in) :: paint
        end subroutine draw_markers_i

        ! Glyphs placed along a line through (x, y), turned angle degrees
        ! clockwise about that point, and filled with the paint's fill.
        ! Every backend draws the same outlines: there is no font for a
        ! viewer to substitute, so the four formats cannot disagree about
        ! what the text looks like. PDF and EPS still keep it text, through
        ! a font embedded from the outlines with a map back to Unicode.
        subroutine draw_glyphs_i(self, x, y, run, paint, angle)
            import :: renderer_t, glyphrun_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x, y
            type(glyphrun_t), intent(in) :: run
            type(paint_t), intent(in) :: paint
            real(dp), intent(in) :: angle
        end subroutine draw_glyphs_i

        ! An RGBA raster placed in the rectangle (x, y, w, h), row major from
        ! the top left. Used by imshow; PNG blits it, the vector backends
        ! embed or tile it.
        subroutine draw_image_i(self, x, y, w, h, rgba, nx, ny, paint)
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x, y, w, h
            integer, intent(in) :: nx, ny
            integer, intent(in) :: rgba(:, :, :)
            type(paint_t), intent(in) :: paint
        end subroutine draw_image_i

    end interface

contains

    ! x' = matrix(1)*x + matrix(3)*y + matrix(5), likewise y with 2,4,6.
    ! clip is in the new local coordinates. Backends restore both on exit.
    ! The defaults of a target that cannot transform: the identity without
    ! a clip is a frame it can draw, and anything else stops rather than
    ! being drawn wrong.
    subroutine begin_frame_impl(self, matrix, clip)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip

        if (clip%on .or. any(matrix /= [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp])) then
            call contract_error("renderer: this target cannot transform or clip a frame")
        end if
    end subroutine begin_frame_impl

    subroutine end_frame_impl(self)
        class(renderer_t), intent(inout) :: self
    end subroutine end_frame_impl

    ! ------------------------------------------------------------------
    ! Structure.
    !
    ! Why a group is worth an API call at all: it carries meaning the backend
    ! cannot reconstruct. Matplotlib nests every figure as figure_1 > axes_1 >
    ! line2d_1, and that tree is what lets someone open the figure in Inkscape
    ! or Illustrator and select "the second curve" as one object to restyle.
    ! For a paper figure that workflow matters more than anything else in the
    ! file. The same names give CSS and Javascript something to target.
    !
    ! Note what is deliberately not a reason. Hoisting a shared clip onto one
    ! <g clip-path=...> rather than repeating it on fifty children is an
    ! optimization the SVG backend can find by itself, by noticing a run of
    ! identical clips in the paint. Optimizations a backend can discover on
    ! its own do not belong in the contract.
    !
    ! PDF can map these onto marked content, which Illustrator reads as
    ! layers. EPS and PNG have no document tree, so ignoring them is correct.
    ! ------------------------------------------------------------------

    subroutine begin_group_impl(self, name)
        class(renderer_t), intent(inout) :: self
        character(len=*), intent(in) :: name
    end subroutine begin_group_impl

    subroutine end_group_impl(self)
        class(renderer_t), intent(inout) :: self
    end subroutine end_group_impl

    ! ------------------------------------------------------------------
    ! The contract. Each method below checks its call, keeps the canvas
    ! state and calls the backend; see "Errors" at the top of the file.
    ! ------------------------------------------------------------------

    subroutine open_canvas(self, width, height, bg_rgb, bg_alpha, x0, y0)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: width, height
        integer, intent(in), optional :: bg_rgb(3)
        real(dp), intent(in), optional :: bg_alpha
        real(dp), intent(in), optional :: x0, y0

        if (self%is_open) call contract_error("renderer: canvas is already open")
        if (.not. all(in_range([width, height])) .or. width < 0.0_dp .or. height < 0.0_dp) then
            call contract_error("renderer: canvas size must be finite, nonnegative and at most 1e15")
        end if
        if (present(bg_rgb)) call check_rgb(bg_rgb)
        if (present(bg_alpha)) call check_alpha(bg_alpha, "renderer: background alpha must be in [0,1]")
        if (present(x0)) call check_finite([x0], "renderer: nonfinite or out-of-range canvas origin")
        if (present(y0)) call check_finite([y0], "renderer: nonfinite or out-of-range canvas origin")
        call self%open_canvas_impl(width, height, bg_rgb, bg_alpha, x0, y0)
        self%width = width
        self%height = height
        self%is_open = .true.
        self%is_finished = .false.
        self%n_group = 0
        self%n_frame = 0
        self%scopes = ""
    end subroutine open_canvas

    subroutine close_canvas(self)
        class(renderer_t), intent(inout) :: self

        call check_open(self)
        if (self%n_group /= 0) call contract_error("renderer: begin_group without end_group at close_canvas")
        if (self%n_frame /= 0) call contract_error("renderer: begin_frame without end_frame at close_canvas")
        call self%close_canvas_impl()
        self%is_open = .false.
        self%is_finished = .true.
    end subroutine close_canvas

    subroutine draw_path(self, x, y, verbs, n_verb, paint)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        type(paint_t), intent(in) :: paint

        call check_open(self)
        call check_path(x, y, verbs, n_verb, "path")
        call check_paint(paint)
        if (n_verb == 0) return
        call self%draw_path_impl(x, y, verbs, n_verb, paint)
    end subroutine draw_path

    subroutine draw_rect(self, x, y, w, h, paint, radius)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        type(paint_t), intent(in) :: paint
        real(dp), intent(in), optional :: radius

        call check_open(self)
        call check_box(x, y, w, h, "rectangle")
        if (present(radius)) then
            if (.not. in_range(radius) .or. radius < 0.0_dp) then
                call contract_error("rectangle: invalid corner radius")
            end if
        end if
        call check_paint(paint)
        call self%draw_rect_impl(x, y, w, h, paint, radius)
    end subroutine draw_rect

    subroutine draw_circle(self, cx, cy, r, paint)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: cx, cy, r
        type(paint_t), intent(in) :: paint

        call check_open(self)
        if (.not. all(in_range([cx, cy, r])) .or. r < 0.0_dp) then
            call contract_error("circle: expected an in-range center and an in-range nonnegative radius")
        end if
        call check_paint(paint)
        call self%draw_circle_impl(cx, cy, r, paint)
    end subroutine draw_circle

    subroutine draw_markers(self, x, y, mx, my, mverbs, n_mverb, paint)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x(:), y(:)
        real(dp), intent(in) :: mx(:), my(:)
        integer, intent(in) :: mverbs(:), n_mverb
        type(paint_t), intent(in) :: paint

        call check_open(self)
        if (size(x) /= size(y)) call contract_error("markers: x and y differ in length")
        call check_finite(x, "markers: nonfinite or out-of-range position")
        call check_finite(y, "markers: nonfinite or out-of-range position")
        call check_path(mx, my, mverbs, n_mverb, "markers")
        call check_paint(paint)
        if (size(x) == 0 .or. n_mverb == 0) return
        call self%draw_markers_impl(x, y, mx, my, mverbs, n_mverb, paint)
    end subroutine draw_markers

    subroutine draw_glyphs(self, x, y, run, paint, angle)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y
        type(glyphrun_t), intent(in) :: run
        type(paint_t), intent(in) :: paint
        real(dp), intent(in) :: angle

        call check_open(self)
        call check_finite([x, y, angle], "glyphs: nonfinite or out-of-range position or angle")
        call check_glyphs(run)
        call check_paint(paint)
        if (run%n == 0) return
        call self%draw_glyphs_impl(x, y, run, paint, angle)
    end subroutine draw_glyphs

    subroutine draw_image(self, x, y, w, h, rgba, nx, ny, paint)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: x, y, w, h
        integer, intent(in) :: nx, ny
        integer, intent(in) :: rgba(:, :, :)
        type(paint_t), intent(in) :: paint

        call check_open(self)
        if (nx < 1 .or. ny < 1 .or. any(shape(rgba) /= [4, nx, ny])) then
            call contract_error("image: expected a nonempty 4 x nx x ny RGBA array")
        end if
        if (any(rgba < 0) .or. any(rgba > 255)) then
            call contract_error("image: components must be in [0,255]")
        end if
        call check_box(x, y, w, h, "image")
        call check_paint(paint)
        call self%draw_image_impl(x, y, w, h, rgba, nx, ny, paint)
    end subroutine draw_image

    subroutine begin_group(self, name)
        class(renderer_t), intent(inout) :: self
        character(len=*), intent(in) :: name

        call check_open(self)
        self%n_group = self%n_group + 1
        call push_scope(self, "G")
        call self%begin_group_impl(name)
    end subroutine begin_group

    subroutine end_group(self)
        class(renderer_t), intent(inout) :: self

        call check_open(self)
        if (self%n_group == 0) call contract_error("renderer: end_group without begin_group")
        call pop_scope(self, "G", "renderer: end_group inside a frame begun after the group")
        call self%end_group_impl()
        self%n_group = self%n_group - 1
    end subroutine end_group

    ! matrix maps the frame's coordinates to its parent's:
    ! x' = matrix(1)*x + matrix(3)*y + matrix(5), and y' likewise with
    ! matrix(2), (4) and (6). clip, when on, is in the frame's coordinates.
    ! Until end_frame, everything drawn is transformed and clipped so.
    subroutine begin_frame(self, matrix, clip)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        type(clip_t), intent(in) :: clip

        call check_open(self)
        call check_finite(matrix, "frame: nonfinite or out-of-range transform")
        if (clip%on) call check_box(clip%x, clip%y, clip%w, clip%h, "frame clip")
        self%n_frame = self%n_frame + 1
        call push_scope(self, "F")
        call push_zoom(self, matrix)
        call self%begin_frame_impl(matrix, clip)
    end subroutine begin_frame

    ! The frame's magnification, bounded by sqrt(|A|_1 |A|_inf) of the
    ! 2 by 2 part of its matrix, which is at least the most it stretches
    ! and exactly 1 for a frame that only moves, times that of the frames
    ! around it: both norms bound a product by the product. Kept as a
    ! logarithm, which deep nesting cannot overflow.
    subroutine push_zoom(self, matrix)
        class(renderer_t), intent(inout) :: self
        real(dp), intent(in) :: matrix(6)
        real(dp), allocatable :: grown(:)
        real(dp) :: outer

        if (.not. allocated(self%frame_log_zoom)) allocate (self%frame_log_zoom(8))
        if (self%n_frame > size(self%frame_log_zoom)) then
            allocate (grown(2*size(self%frame_log_zoom)))
            grown(1:size(self%frame_log_zoom)) = self%frame_log_zoom
            call move_alloc(grown, self%frame_log_zoom)
        end if
        outer = 0.0_dp
        if (self%n_frame > 1) outer = self%frame_log_zoom(self%n_frame - 1)
        self%frame_log_zoom(self%n_frame) = outer + 0.5_dp*( &
            log10(max(abs(matrix(1)) + abs(matrix(2)), abs(matrix(3)) + abs(matrix(4)), tiny(1.0_dp))) + &
            log10(max(abs(matrix(1)) + abs(matrix(3)), abs(matrix(2)) + abs(matrix(4)), tiny(1.0_dp))))
    end subroutine push_zoom

    ! How many decimals a vector encoder writes a number with, inside the
    ! frames open now, to place it within a millionth of a point on the
    ! page: six, and one more for each power of ten those frames magnify
    ! by, up to forty. With outer, inside the frames around the innermost,
    ! for the numbers of its own matrix, from begin_frame_impl: a contract
    ! error with no frame open.
    integer function frame_decimals(r, outer) result(d)
        class(renderer_t), intent(in) :: r
        logical, intent(in), optional :: outer
        integer :: level

        level = r%n_frame
        if (present(outer)) then
            if (outer) then
                if (r%n_frame == 0) call contract_error("renderer: frame_decimals(outer) with no frame open")
                level = r%n_frame - 1
            end if
        end if
        d = 6
        if (level > 0) d = 6 + max(0, ceiling(min(34.0_dp, r%frame_log_zoom(level))))
    end function frame_decimals

    subroutine end_frame(self)
        class(renderer_t), intent(inout) :: self

        call check_open(self)
        if (self%n_frame == 0) call contract_error("renderer: end_frame without begin_frame")
        call pop_scope(self, "F", "renderer: end_frame inside a group begun after the frame")
        call self%end_frame_impl()
        self%n_frame = self%n_frame - 1
    end subroutine end_frame

    subroutine push_scope(self, kind)
        class(renderer_t), intent(inout) :: self
        character, intent(in) :: kind
        if (.not. allocated(self%scopes)) self%scopes = ""
        self%scopes = self%scopes//kind
    end subroutine push_scope

    ! Groups and frames nest: the one ended must be the innermost open.
    subroutine pop_scope(self, kind, message)
        class(renderer_t), intent(inout) :: self
        character, intent(in) :: kind
        character(len=*), intent(in) :: message
        integer :: n
        n = len(self%scopes)
        if (self%scopes(n:n) /= kind) call contract_error(message)
        self%scopes = self%scopes(1:n - 1)
    end subroutine pop_scope

    function bytes(self) result(b)
        class(encoded_renderer_t), intent(in) :: self
        character(len=:), allocatable :: b

        if (self%is_open .or. .not. self%is_finished) then
            call contract_error("renderer: bytes before close_canvas")
        end if
        b = self%bytes_impl()
    end function bytes

    ! ------------------------------------------------------------------
    ! The checks themselves.
    ! ------------------------------------------------------------------

    subroutine check_open(self)
        class(renderer_t), intent(in) :: self
        if (.not. self%is_open) call contract_error("renderer: canvas is not open")
    end subroutine check_open

    ! Finite and no further than MAX_COORD from zero: the most any format
    ! here can write, as a plain decimal, and far beyond any canvas.
    elemental logical function in_range(v)
        real(dp), intent(in) :: v
        in_range = ieee_is_finite(v) .and. abs(v) <= MAX_COORD
    end function in_range

    subroutine check_finite(values, message)
        real(dp), intent(in) :: values(:)
        character(len=*), intent(in) :: message
        if (.not. all(in_range(values))) call contract_error(message)
    end subroutine check_finite

    subroutine check_rgb(rgb)
        integer, intent(in) :: rgb(3)
        if (any(rgb < 0) .or. any(rgb > 255)) call contract_error("color: expected RGB values in [0,255]")
    end subroutine check_rgb

    subroutine check_alpha(alpha, message)
        real(dp), intent(in) :: alpha
        character(len=*), intent(in) :: message
        if (.not. ieee_is_finite(alpha) .or. alpha < 0.0_dp .or. alpha > 1.0_dp) call contract_error(message)
    end subroutine check_alpha

    ! An axis aligned box: rectangles and images.
    subroutine check_box(x, y, w, h, what)
        real(dp), intent(in) :: x, y, w, h
        character(len=*), intent(in) :: what
        if (.not. all(in_range([x, y, w, h])) .or. w < 0.0_dp .or. h < 0.0_dp) then
            call contract_error(what//": expected in-range coordinates and nonnegative size")
        end if
    end subroutine check_box

    subroutine check_paint(paint)
        type(paint_t), intent(in) :: paint
        if (paint%clip%on) then
            call check_box(paint%clip%x, paint%clip%y, paint%clip%w, paint%clip%h, "clip")
        end if
        if (paint%filled) then
            call check_rgb(paint%fill_rgb)
            if (paint%fill_rule /= FILL_NONZERO .and. paint%fill_rule /= FILL_EVENODD) then
                call contract_error("paint: unsupported fill rule")
            end if
            call check_alpha(paint%fill_alpha, "paint: fill alpha must be in [0,1]")
        end if
        if (.not. paint%stroked) return
        call check_rgb(paint%stroke_rgb)
        call check_alpha(paint%stroke_alpha, "paint: stroke alpha must be in [0,1]")
        call check_finite([paint%line_width, paint%miter_limit, paint%dash_offset], "paint: nonfinite or out-of-range stroke")
        if (paint%line_width < 0.0_dp .or. paint%miter_limit < 0.0_dp) then
            call contract_error("paint: negative line width or miter limit")
        end if
        if (paint%cap < CAP_BUTT .or. paint%cap > CAP_SQUARE .or. &
            paint%join < JOIN_MITER .or. paint%join > JOIN_BEVEL) then
            call contract_error("paint: unsupported stroke cap or join")
        end if
        if (paint%n_dash < 0 .or. paint%n_dash > MAX_DASH) then
            call contract_error("paint: invalid dash count")
        end if
        if (paint%n_dash > 0) then
            call check_finite(paint%dash(1:paint%n_dash), "paint: nonfinite or out-of-range dash length")
            if (any(paint%dash(1:paint%n_dash) < 0.0_dp)) call contract_error("paint: negative dash length")
            if (sum(paint%dash(1:paint%n_dash)) <= 0.0_dp) then
                call contract_error("paint: dash pattern must have positive length")
            end if
            ! Round and square ends overlap one another, so every dash a
            ! pen's width from the canvas has to be drawn; a pen far wider
            ! than its pattern would mean drawing ever more of them.
            if (paint%cap /= CAP_BUTT .and. paint%line_width > MAX_PEN_PER_DASH*sum(paint%dash(1:paint%n_dash))) then
                call contract_error("paint: a pen with round or square dash ends may be at most 100 times its dash pattern")
            end if
        end if
    end subroutine check_paint

    ! The verbs must start each contour with MOVE, and x and y must hold
    ! the points they consume, all finite.
    subroutine check_path(x, y, verbs, n_verb, what)
        real(dp), intent(in) :: x(:), y(:)
        integer, intent(in) :: verbs(:), n_verb
        character(len=*), intent(in) :: what
        integer :: i, points
        logical :: started

        if (n_verb < 0 .or. n_verb > size(verbs)) call contract_error(what//": invalid verb count")
        points = 0
        started = .false.
        do i = 1, n_verb
            select case (verbs(i))
            case (VERB_MOVE)
                started = .true.
                points = points + 1
            case (VERB_LINE)
                if (.not. started) call contract_error(what//": a contour must begin with MOVE")
                points = points + 1
            case (VERB_CUBIC)
                if (.not. started) call contract_error(what//": a contour must begin with MOVE")
                points = points + 3
            case (VERB_CLOSE)
                if (.not. started) call contract_error(what//": a contour must begin with MOVE")
            case default
                call contract_error(what//": unsupported verb")
            end select
        end do
        if (points > size(x) .or. points > size(y)) then
            call contract_error(what//": not enough coordinates for the verbs")
        end if
        call check_finite(x(1:points), what//": nonfinite or out-of-range coordinate")
        call check_finite(y(1:points), what//": nonfinite or out-of-range coordinate")
    end subroutine check_path

    subroutine check_glyphs(run)
        type(glyphrun_t), intent(in) :: run
        integer :: n

        n = run%n
        if (n < 0) call contract_error("glyphs: negative glyph count")
        if (n == 0) return
        if (.not. allocated(run%gid) .or. .not. allocated(run%x) .or. &
            .not. allocated(run%y) .or. .not. allocated(run%size)) then
            call contract_error("glyphs: run arrays are not allocated")
        end if
        if (any([lbound(run%gid, 1), lbound(run%x, 1), lbound(run%y, 1), lbound(run%size, 1)] /= 1)) then
            call contract_error("glyphs: run arrays must start at index 1")
        end if
        if (min(size(run%gid), size(run%x), size(run%y), size(run%size)) < n) then
            call contract_error("glyphs: run arrays are shorter than the glyph count")
        end if
        if (any(run%gid(1:n) < 0) .or. any(run%gid(1:n) > NGLYPH)) then
            call contract_error("glyphs: invalid glyph ID")
        end if
        call check_finite(run%x(1:n), "glyphs: nonfinite or out-of-range glyph position")
        call check_finite(run%y(1:n), "glyphs: nonfinite or out-of-range glyph position")
        call check_finite(run%size(1:n), "glyphs: nonfinite or out-of-range font size")
        if (any(run%size(1:n) < 0.0_dp)) call contract_error("glyphs: negative font size")
        if (allocated(run%font)) then
            if (lbound(run%font, 1) /= 1) call contract_error("glyphs: run arrays must start at index 1")
            if (size(run%font) < n) call contract_error("glyphs: font array is shorter than the glyph count")
        end if
        if (allocated(run%first) .neqv. allocated(run%last)) then
            call contract_error("glyphs: incomplete source mapping")
        end if
        if (allocated(run%first)) then
            if (lbound(run%first, 1) /= 1 .or. lbound(run%last, 1) /= 1) then
                call contract_error("glyphs: run arrays must start at index 1")
            end if
            if (min(size(run%first), size(run%last)) < n) then
                call contract_error("glyphs: source mapping is shorter than the glyph count")
            end if
        end if
    end subroutine check_glyphs

end module fplotlib_render
