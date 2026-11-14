# fplotlib_scene module

Owned frames and pages are the boundary between drawing and output.
Capture a plot with `fplotlib_draw:render_frame`, obtain an equation with
`fplotlib_mathtext:math_frame`, or record any drawing with a
`recording_renderer_t`. Each produces the same `frame_t`, with local point
coordinates, a baseline and ink bounds.

`import_frame` copies a child into the receiving frame's arena and returns an
owner-local handle. Repeated `place` calls share that copy. The original child
does not need to remain alive. The affine matrix is `[a,b,c,d,e,f]`; an
optional clip is in the child's coordinates.

`paged_document_t` owns its pages and all captured drawing data. Built-in
font data is shared read-only rather than copied into each document.

`source_text()` concatenates stored glyph-run source in drawing order.
It includes raw TeX, so it is neither plain-text extraction nor an accessibility
representation. Importing a frame does not place it; `place` controls each
occurrence in the drawing order.

An invalid handle, size, transform or scope operation is a bug in the caller
and stops the program with a message, like any other broken precondition of
the rendering contract (see [`fplotlib_render`](fplotlib_render.md) and
[`fplotlib_status`](fplotlib_status.md)). `recording_renderer_t` implements
only the `*_impl` methods, so `renderer_t` checks every call it records.

```{f:module} fplotlib_scene
```
