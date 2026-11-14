# fplotlib_document module

`export_document(document, format, assets, dpi, status)` exports finished pages
without a parser, plotting state or filesystem. It returns one byte asset
for PDF, or one per page for SVG, PNG and EPS. `dpi` affects PNG only.
`save_document(document, filename, dpi, status)` writes the same assets directly to
files. Both functions live here, not in the high-level plotting facade.

`dpi` is optional; `status` is required. Failed byte exports leave `assets`
unallocated. File errors include the filename and an I/O diagnostic; a
multi-file export is not a filesystem transaction and may have written earlier
pages before a later file fails.

The exporters do not perform text or math layout. Glyph source mappings
are preserved in frames; ordinary PDF text carries `ActualText`, while
TeX formula source is not presented as a Unicode replacement string.

```{f:module} fplotlib_document
```
