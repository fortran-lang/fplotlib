# fplotlib_report module

`report_t` is an explicit, retained document builder. It owns content,
captured graphics and a layout cache; it never consults the implicit report
or the current plot. The procedural API in `fplotlib` delegates to one
default instance.

Use `markdown` to append blocks, `include_frame` to snapshot supplied graphics,
and `include_table` to copy numerical or character cells. `export` performs
layout only when the content has changed, then returns PDF/SVG/PNG/EPS byte
assets. `page_frame` returns an owned page snapshot. `clear` starts a fresh
description without invalidating previously returned frames or byte assets.

Captions and labels are stored with the content. Figure/table numbers are
assigned in insertion order, and references are resolved at layout time.
Character table cells are plain text; numeric cells use `G0.6` or `I0`.

```{f:module} fplotlib_report
```
