# fplotlib_render module

`renderer_t` is the format-independent drawing contract. Drawing does not
require a file, an encoded format, or a `bytes` method. `encoded_renderer_t`
extends it with `bytes` for PDF/SVG/PNG/EPS output; recording and interactive
targets can implement drawing alone.

The built-in text family has size, weight and slant styles. There is no
serif/monospace family selector that silently substitutes the sans font.
Finished glyph runs identify the actual built-in glyphs they use.

No renderer call returns an error. A call that breaks the contract, such as
drawing before `open_canvas` or asking for `bytes` before `close_canvas`,
stops the program with a message (see
[`fplotlib_render_checks`](fplotlib_render_checks.md)).

`begin_frame(matrix, clip)` and `end_frame()` scope an affine transform and a
rectangular clip. Every built-in backend implements them. A custom target that
does not override them accepts only the identity transform without a clip,
and stops on any other rather than ignoring it.

```{f:module} fplotlib_render
```
