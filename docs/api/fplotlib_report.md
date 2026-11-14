# fplotlib_report module

`report_t` is an explicit, retained document builder. It owns content,
captured graphics and a layout cache; it never consults the implicit report
or the current plot. The procedural API in `fplotlib` delegates to one
default instance.

Use `markdown` to append blocks, `include_frame` to snapshot supplied graphics,
and `include_table` to copy numerical or character cells. `export` performs
layout only when the content has changed, then returns PDF/SVG/PNG/EPS byte
assets; `save(filename, dpi, status)` writes the same pages directly to files.
`layout(document, status)` returns an owned `paged_document_t` snapshot.
Use that document's page queries or pass it to another compositor/exporter.
`clear` starts a fresh description without invalidating previously returned
documents, frames or byte assets.

Captions and labels are stored with the content. Figure/table numbers are
assigned in insertion order, and references are resolved at layout time.
Character table cells are plain text; numeric cells use `G0.6` or `I0`.

All builder operations have a required `status_t` argument, including
`layout(document, status)`. Check or propagate it immediately.
This module never aborts. The implicit `fplotlib` wrappers abort on a failed
status instead of requiring application code to pass an error argument.

`layout_markdown` and `layout_fragment` are explicit Markdown adapters for
callers that already own a `layout_context_t`. They parse once and delegate to
the parsed-tree resolution/layout pipeline; they do not use the implicit report.

See the [complete API inventory](typesetting_api.md) for signatures.

```{f:module} fplotlib_report
```
