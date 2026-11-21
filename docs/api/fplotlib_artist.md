# fplotlib_artist module

The drawing primitives the plot types are built from. Every call they make
to a renderer goes through `put_path`, `put_rect`, `put_circle`,
`put_markers`, `put_glyphs` and `put_image`, which leave out missing data,
NaN or infinite, the way matplotlib does: a path is broken where a vertex
is missing, and a shape, a marker, a run of text or an image placed at a
missing point is not drawn. The renderer itself accepts only finite
coordinates.

```{f:module} fplotlib_artist
```
