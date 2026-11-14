! fplotlib_render — the backend rendering API.
!
! One abstract drawing target that SVG, PNG, PDF and EPS each implement. The plotting
! code above it never learns which one it is talking to, so a new output format
! is a new module here and nothing else.
!
! Four rules keep the API from leaking any one format's habits:
!
!   1. No hidden paint state. Every drawing call carries the paint it should be
!      drawn with, so nothing depends on what was called before it. A backend
!      may cache the last paint internally to avoid re-emitting attributes,
!      but that is its own business and cannot be observed through the API.
!      The canvas lifecycle is explicit.
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
! decision to make about it. Those are all deferred, so the compiler tells a
! backend author exactly what has to be written:
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
! By the same rule this module is interface and nothing else. Text metrics,
! arc flattening and circle-to-cubic conversion are all absent: either a
! backend has a real reason to do them its own way, in which case that is the
! backend's own code, or it does not, in which case it belongs to whoever
! calls the API rather than to the API.
!
! begin_group and end_group are different again: they are concrete and default
! to doing nothing, because doing nothing is the correct implementation for a
! format without a document tree, not a lazy one. See the note on groups.

module fplotlib_render
    use fplotlib_status
    use fplotlib_style, only: dp
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
    public :: MAX_DASH

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
        real(dp), allocatable :: x(:), y(:), size(:)
        character(len=:), allocatable :: text
    end type glyphrun_t

    type, abstract :: renderer_t
        real(dp) :: width = 0.0_dp    ! canvas size in points
        real(dp) :: height = 0.0_dp
        logical :: is_open = .false.
    contains
        ! Lifecycle.
        procedure(open_canvas_i), deferred :: open_canvas
        procedure(close_canvas_i), deferred :: close_canvas

        ! The primitives. Every one is a decision a backend has to make for
        ! itself, which is why none of them has a default.
        procedure(draw_path_i), deferred :: draw_path
        procedure(draw_rect_i), deferred :: draw_rect
        procedure(draw_circle_i), deferred :: draw_circle
        procedure(draw_markers_i), deferred :: draw_markers
        procedure(draw_glyphs_i), deferred :: draw_glyphs
        procedure(draw_image_i), deferred :: draw_image

        ! Structure. Concrete, and doing nothing is a correct implementation
        ! for any format without a document tree.
        procedure :: begin_group
        procedure :: end_group
    end type renderer_t

    ! Encoding is separate from drawing: a target that only draws, such as an
    ! interactive one, need not invent a file format or a bytes method.
    type, abstract, extends(renderer_t) :: encoded_renderer_t
        logical :: has_output = .false.
    contains
        procedure(bytes_i), deferred :: bytes
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
        subroutine open_canvas_i(self, width, height, bg_rgb, bg_alpha, x0, y0, status)
            import :: status_t
            import :: renderer_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: width, height
            integer, intent(in), optional :: bg_rgb(3)
            real(dp), intent(in), optional :: bg_alpha
            real(dp), intent(in), optional :: x0, y0
            type(status_t), intent(out) :: status
        end subroutine open_canvas_i

        ! Finalizes the container: deflate and CRC for PNG, xref for PDF,
        ! trailer for EPS, closing tag for SVG.
        subroutine close_canvas_i(self, status)
            import :: status_t
            import :: renderer_t
            class(renderer_t), intent(inout) :: self
            type(status_t), intent(out) :: status
        end subroutine close_canvas_i

        ! The finished document. A character string rather than a specific
        ! file type, so binary formats can return raw bytes and callers can
        ! write a file or hand it to a notebook without a temporary file.
        function bytes_i(self, status) result(b)
            import :: status_t
            import :: encoded_renderer_t
            class(encoded_renderer_t), intent(in) :: self
            character(len=:), allocatable :: b
            type(status_t), intent(out) :: status
        end function bytes_i

        ! n_verb entries of verbs() describe the vertices in x()/y(): MOVE and
        ! LINE take one vertex, CUBIC takes three, CLOSE takes none.
        subroutine draw_path_i(self, x, y, verbs, n_verb, paint, status)
            import :: status_t
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x(:), y(:)
            integer, intent(in) :: verbs(:), n_verb
            type(paint_t), intent(in) :: paint
            type(status_t), intent(out) :: status
        end subroutine draw_path_i

        ! radius rounds the corners, as the legend box needs. Axis aligned, so
        ! a rasterizer can fill whole spans and skip antialiasing on the two
        ! edges that fall on pixel boundaries.
        subroutine draw_rect_i(self, x, y, w, h, paint, radius, status)
            import :: status_t
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x, y, w, h
            type(paint_t), intent(in) :: paint
            real(dp), intent(in), optional :: radius
            type(status_t), intent(out) :: status
        end subroutine draw_rect_i

        subroutine draw_circle_i(self, cx, cy, r, paint, status)
            import :: status_t
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: cx, cy, r
            type(paint_t), intent(in) :: paint
            type(status_t), intent(out) :: status
        end subroutine draw_circle_i

        ! One shape, described once about the origin, stamped at every point
        ! in x/y with a single paint. The whole reason this is a primitive is
        ! that every format can express the shape once and then reference it.
        subroutine draw_markers_i(self, x, y, mx, my, mverbs, n_mverb, paint, status)
            import :: status_t
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x(:), y(:)
            real(dp), intent(in) :: mx(:), my(:)
            integer, intent(in) :: mverbs(:), n_mverb
            type(paint_t), intent(in) :: paint
            type(status_t), intent(out) :: status
        end subroutine draw_markers_i

        ! Glyphs placed along a line through (x, y), turned angle degrees
        ! clockwise about that point, and filled with the paint's fill.
        ! Every backend draws the same outlines: there is no font for a
        ! viewer to substitute, so the four formats cannot disagree about
        ! what the text looks like. PDF and EPS still keep it text, through
        ! a font embedded from the outlines with a map back to Unicode.
        subroutine draw_glyphs_i(self, x, y, run, paint, angle, status)
            import :: status_t
            import :: renderer_t, glyphrun_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x, y
            type(glyphrun_t), intent(in) :: run
            type(paint_t), intent(in) :: paint
            real(dp), intent(in) :: angle
            type(status_t), intent(out) :: status
        end subroutine draw_glyphs_i

        ! An RGBA raster placed in the rectangle (x, y, w, h), row major from
        ! the top left. Used by imshow; PNG blits it, the vector backends
        ! embed or tile it.
        subroutine draw_image_i(self, x, y, w, h, rgba, nx, ny, paint, status)
            import :: status_t
            import :: renderer_t, paint_t, dp
            class(renderer_t), intent(inout) :: self
            real(dp), intent(in) :: x, y, w, h
            integer, intent(in) :: nx, ny
            integer, intent(in) :: rgba(:, :, :)
            type(paint_t), intent(in) :: paint
            type(status_t), intent(out) :: status
        end subroutine draw_image_i

    end interface

contains

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

    subroutine begin_group(self, name, status)
        class(renderer_t), intent(inout) :: self
        character(len=*), intent(in) :: name
        type(status_t), intent(out) :: status

        if (.not. self%is_open) then
            call status%set(ERROR_STATE, "renderer: canvas is not open")
            return
        end if
    end subroutine begin_group

    subroutine end_group(self, status)
        class(renderer_t), intent(inout) :: self
        type(status_t), intent(out) :: status

        if (.not. self%is_open) then
            call status%set(ERROR_STATE, "renderer: canvas is not open")
            return
        end if
    end subroutine end_group

end module fplotlib_render
