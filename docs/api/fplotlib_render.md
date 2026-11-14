# fplotlib_render module

`renderer_t` is the format-independent drawing contract. Drawing does not
require a file, an encoded format, or a `bytes` method. `encoded_renderer_t`
extends it with `bytes` for PDF/SVG/PNG/EPS output; recording and interactive
targets can implement drawing alone.

The built-in text family has size, weight and slant styles. There is no
serif/monospace family selector that silently substitutes the sans font.
Finished glyph runs identify the actual built-in glyphs they use.

Every renderer operation has a required `status_t` output. This includes
`bytes(status)`, which is available only after successful finalization of an
encoded target. Unsupported frame transforms on a custom target return
`ERROR_UNSUPPORTED`; they are not silently ignored.

`begin_frame(matrix, clip, status)` and `end_frame(status)` scope an affine
transform and a rectangular clip. Every built-in backend implements them.

```{f:module} fplotlib_render
```
