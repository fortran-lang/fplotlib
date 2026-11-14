# fplotlib_render module

`renderer_t` is the format-independent drawing contract. Drawing does not
require a file, an encoded format, or a `bytes` method. `encoded_renderer_t`
extends it with `bytes` for PDF/SVG/PNG/EPS output; other targets can
implement drawing alone.

The built-in text family has size, weight and slant styles. There is no
serif/monospace family selector that silently substitutes the sans font.

Every renderer operation has a required `status_t` output. This includes
`bytes(status)`, which is available only after successful finalization of an
encoded target.

```{f:module} fplotlib_render
```
