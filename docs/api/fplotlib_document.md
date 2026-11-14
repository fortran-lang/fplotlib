# fplotlib_document module

`export_document(document, format, assets, dpi)` exports finished pages
without plotting state or a filesystem. It returns one byte asset for PDF,
or one per page for SVG, PNG and EPS. `dpi` affects PNG only.
`save_document(document, filename, status, dpi)` writes the same assets
directly to files. Both live here, not in the high-level plotting facade.

Writing a file is the one step that can fail at run time, so
`save_document` alone takes a required `status_t`. Its message names the
file. A multi-file export is not a filesystem transaction: the pages before
the file that failed have been written. An unknown format, a document
without pages or a nonpositive `dpi` is a bug in the caller and stops the
program.

The exporters do not lay out text or math. Glyph source mappings
are preserved in frames; ordinary PDF text carries `ActualText`, while
TeX formula source is not presented as a Unicode replacement string.

```{f:module} fplotlib_document
```
