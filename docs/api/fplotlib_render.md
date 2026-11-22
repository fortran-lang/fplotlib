# fplotlib_render module

`renderer_t` is the format-independent drawing contract. Drawing does not
require a file, an encoded format, or a `bytes` method. `encoded_renderer_t`
extends it with `bytes` for PDF/SVG/PNG/EPS output; recording and interactive
targets can implement drawing alone.

The built-in text family has size, weight and slant styles. There is no
serif/monospace family selector that silently substitutes the sans font.
Finished glyph runs identify the actual built-in glyphs they use.

No renderer call returns an error. A call that breaks the contract, such as
drawing before `open_canvas`, a coordinate that is not finite or lies
beyond `MAX_COORD` (1e15 points), an `end_group`
without a `begin_group` or asking for `bytes` before `close_canvas`, stops
the program with a message naming the rule (see
[`fplotlib_status`](fplotlib_status.md)).

`renderer_t` makes these checks itself, the same way for every backend.
Its public methods are `non_overridable`: each checks the call and keeps
the canvas state, then calls the backend's deferred `*_impl` method
(`open_canvas_impl`, `draw_path_impl`, ..., `bytes_impl`). A new backend
implements only those, and may assume every call it receives is valid.
The `*_impl` bindings are public only so that a backend in another module
can implement them; code that draws calls the methods without the suffix,
since calling an `*_impl` directly skips the checks.

`begin_frame(matrix, clip)` and `end_frame()` scope an affine transform and a
rectangular clip: `matrix` is `[a,b,c,d,e,f]`, mapping a point of the frame
to `(a*x+c*y+e, b*x+d*y+f)` in its parent, and `clip`, when on, is in the
frame's coordinates. Like the other methods they are checked once, in
`renderer_t`: the canvas must be open, the matrix finite and within
`MAX_COORD`, and the clip a box of nonnegative size. Frames and groups nest:
each must end inside whatever began after it, and none may be open at
`close_canvas`. Every built-in backend implements `begin_frame_impl` and
`end_frame_impl`. A custom target that does not accepts only the identity
transform without a clip, and stops on any other rather than ignoring it.

The PNG backend draws a frame's content transformed and clipped exactly; a
paint clip inside a clipped frame is cut as geometry, so its edges are
antialiased rather than whole pixels. A dashed stroke is built in the
frame's coordinates, but what the rasterizer may skip of it is decided by
the canvas: a segment is walked only where the matrix maps it into the
canvas, widened on each side by the pen as the matrix stretches that axis.
A segment whose pattern is finer than half a pixel on the canvas, or whose
visible piece holds more periods than the canvas has pixels around it
twice over, is drawn solid at the pattern's cover, the approximation
[`fplotlib_status`](fplotlib_status.md) describes; that bounds every walk
by the canvas, however the frame shrinks, shears or stretches. Everywhere
else the dashes are what walking every one of them draws.

Pages are not part of `renderer_t`: `pdf_renderer_t%new_page` starts the
next page of a PDF, and the other formats write one page each.

```{f:module} fplotlib_render
```
