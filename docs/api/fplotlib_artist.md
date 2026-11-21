# fplotlib_artist module

The drawing primitives the plot types are built from. Every call they make
to a renderer goes through `put_path`, `put_rect`, `put_circle`,
`put_markers`, `put_glyphs` and `put_image`, which leave out missing data,
NaN or infinite, the way matplotlib does: a path is broken where a vertex
is missing, and a shape, a marker, a run of text or an image placed at a
missing point is not drawn. The renderer itself accepts only finite
coordinates. Geometry reaching far outside the view, up to the largest
double, is clipped to a box ten canvases wide around the canvas, filled
shapes as polygons and strokes segment by segment, so every format gets
coordinates it can write and every line keeps its direction.

```{f:module} fplotlib_artist
```
