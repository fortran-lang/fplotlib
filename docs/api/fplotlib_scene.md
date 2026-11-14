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

`source_text(status)` concatenates stored glyph-run source in drawing order.
It includes raw TeX, so it is neither plain-text extraction nor an accessibility
representation. Importing a frame does not place it; `place` controls each
occurrence in the drawing order.

Fallible methods require `status_t`. Invalid handles, sizes, scope operations
and drawing requests return errors, not `error stop`. Frame replay stops at the
first backend error; an unfinished drawing target should be discarded after a
drawing failure. Finished input frames remain owned and independent.

```{f:module} fplotlib_scene
```
