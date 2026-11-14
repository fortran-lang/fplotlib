# fplotlib_document module

`export_document(document, format, assets, dpi)` exports finished pages
without a parser, plotting state or filesystem. It returns one byte asset
for PDF, or one per page for SVG, PNG and EPS. `dpi` affects PNG only.
`save_document(document, filename, dpi)` writes the same assets directly to
files. Both functions live here, not in the high-level plotting facade.

The exporters do not perform text or math layout. Glyph source mappings
are preserved in frames; ordinary PDF text carries `ActualText`, while
TeX formula source is not presented as a Unicode replacement string.

```{f:module} fplotlib_document
```
