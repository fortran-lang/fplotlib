# fplotlib_report module

`report_t` is an explicit, retained document builder. It owns content,
captured graphics and a layout cache; it never consults the implicit report
or the current plot. The procedural API in `fplotlib` delegates to one
default instance.

Use `markdown` to append blocks, `include_frame` to snapshot supplied graphics,
and `include_table` to copy numerical or character cells. `export` performs
layout only when the content has changed, then returns PDF/SVG/PNG/EPS byte
assets; `save(filename, dpi, status)` writes the same pages directly to files.
`page_frame` returns an owned page snapshot. `clear` starts a fresh
description without invalidating previously returned frames or byte assets.

Captions and labels are stored with the content. Figure/table numbers are
assigned in insertion order, and references are resolved at layout time.
Character table cells are plain text; numeric cells use `G0.6` or `I0`.

All builder operations have a required `status_t` argument, including
`page_count(status)`, which may trigger layout. Check or propagate it immediately.
This module never aborts. The implicit `fplotlib` wrappers abort on a failed
status instead of requiring application code to pass an error argument.

See the [complete API inventory](typesetting_api.md) for signatures.

```{f:module} fplotlib_report
```
