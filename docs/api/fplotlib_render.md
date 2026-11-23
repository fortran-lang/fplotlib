# fplotlib_render module

`renderer_t` is the format-independent drawing contract. Drawing does not
require a file, an encoded format, or a `bytes` method. `encoded_renderer_t`
extends it with `bytes` for PDF/SVG/PNG/EPS output; other targets can
implement drawing alone.

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

```{f:module} fplotlib_render
```
