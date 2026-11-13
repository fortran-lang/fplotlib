# fplotlib_scene module

Owned frames and pages are the boundary between layout and rendering.
Capture a plot with `render_frame`, lay out a paragraph with
`layout_fragment`, or obtain an equation with `math_frame`. Each produces
the same `frame_t`, with local point coordinates, a baseline and ink bounds.

`add_frame` copies a child into the receiving frame's arena and returns an
owner-local handle. Repeated `place` calls share that copy. Neither the
original child nor a layout context needs to remain alive. The affine
matrix is `[a,b,c,d,e,f]`; an optional clip is in the child's coordinates.

`paged_document_t` owns its pages and all captured drawing data. Built-in
font data is shared read-only rather than copied into each document.

```{f:module} fplotlib_scene
```
