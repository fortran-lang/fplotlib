# fplotlib_document module

`export_document(document, format, assets, dpi)` exports finished pages
without plotting state or a filesystem. It returns one byte asset for PDF,
or one per page for SVG, PNG and EPS, the format named in any case. `dpi`
affects PNG only, and is 100 unless given, as for `savefig`.
`save_document(document, filename, status, dpi)` writes the same assets
directly to files. Both live here, not in the high-level plotting facade.

Writing a file is the one step that can fail at run time, so
`save_document` alone takes a `status_t`, optional as `savefig`'s is: with
it, a file that cannot be written is returned (`ERROR_IO`, with a message
naming the file); without it, the program stops with the message and exit
code 2. A multi-file export is not a filesystem transaction: the pages
before the file that failed have been written. An unknown format, a
document without pages, or, exporting PNG, a `dpi` that is not finite and
positive is a bug in the caller and stops the program. So is a PNG page
with more than `MAX_PNG_PIXELS` pixels: a page's size is known before it
is exported (`page_size`, and `png_pixels` in `fplotlib_backend_png` to
count it at a dpi), unlike a figure cropped tight by `savefig`. A page may
be of no size, as the frame of a formula of negative space alone is: it is
written as such, which some PDF viewers decline to show.

The exporters do not lay out text or math. Glyph source mappings
are preserved in frames; ordinary PDF text carries `ActualText`, while
TeX formula source is not presented as a Unicode replacement string.

```{f:module} fplotlib_document
```
