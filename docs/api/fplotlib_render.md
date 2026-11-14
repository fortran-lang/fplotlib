# fplotlib_render module

`renderer_t` is the format-independent drawing contract. Drawing does not
require a file, an encoded format, or a `bytes` method. `encoded_renderer_t`
extends it with `bytes` for PDF/SVG/PNG/EPS output; other targets can
implement drawing alone.

The built-in text family has size, weight and slant styles. There is no
serif/monospace family selector that silently substitutes the sans font.

No renderer call returns an error. A call that breaks the contract, such as
drawing before `open_canvas` or asking for `bytes` before `close_canvas`,
stops the program with a message (see
[`fplotlib_render_checks`](fplotlib_render_checks.md)).

```{f:module} fplotlib_render
```
