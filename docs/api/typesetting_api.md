# Report and typesetting API

This is the document-facing API inventory. The existing plotting catalog is
documented in the [fplotlib module](fplotlib.md). Internal font-decoder,
rasterizer and plotting-adapter helpers are not a second application API.

Square brackets below mean optional arguments, not Fortran syntax.
`status` is **required**, never optional, wherever it appears. In particular,
write `status=error` when omitting preceding optional arguments.

## High-level facade

Import these from `fplotlib`. They select an implicit report and abort on error:

```text
new_report()
markdown(text)
markdown(lines)
include_figure([caption, label, width])
include_table(values, [columns, caption, label])
save(filename, [dpi])
render_report(format, assets, [dpi])
```

`values` is a rank-two real(dp), default-integer or character array.
`document_asset_t` is re-exported here for the in-memory result. All advanced
types and operations below are imported from their owning modules.
`figure`, `table`, `savefig` and animation `add_frame` keep their plotting meanings.
There is no one-shot `typeset` function.

Commands append or capture content in program order. Layout is deferred and
cached; export does not clear the report or the current plot.

## Explicit report builder

`fplotlib_report:report_t` owns its content, workspace and finished-page cache.
It never consults the implicit report or current figure.

```text
report%clear(status)
report%markdown(text, status)
report%markdown(lines, status)
report%include_frame(frame, [caption, label, width], status)
report%include_table(values, [columns, caption, label], status)
report%export(format, assets, [dpi], status)
report%save(filename, [dpi], status)
report%page_count(status) -> n
report%page_frame(page, frame, status)
```

`include_frame` and `include_table` snapshot their inputs. Cells are plain text;
captions are Markdown. `page_count` may perform layout and therefore can fail.
The similarly named query on a finished `paged_document_t` does not perform
layout and cannot fail.

## Frontend tree and document-class policy

These are the small report frontend, not the universal positioned-graphics IR.
An independent frontend can bypass them.

```text
fplotlib_markdown
  md_parse(text, doc, status)
  md_append(text, doc, [parent], status)

fplotlib_doctree
  doc_init(doc, status)
  doc_add(doc, parent, kind, status) -> node
  doc_add_text(doc, parent, kind, text, status) -> node
  doc_add_frame(doc, parent, frame, status) -> node
  doc_add_table(doc, parent, cells, [columns, numeric], status) -> node
  doc_add_meta(doc, key, value, node, status)
  doc_plain(doc, k, status) -> text
  doc_validate(doc, status)

fplotlib_docclass
  doc_typeset(state, doc, document, status)
  layout_markdown(state, text, document, status)
  layout_fragment(state, text, width, frame, [font_size], status)
```

The types are `doc_t`, `doc_node_t`, `doc_meta_t`, `doc_table_t` and
`layout_context_t`. The tree uses `DOC_*` block kinds, `IN_*` inline kinds and
`REF_AUTO`, `REF_TITLE`, `REF_EQ` reference forms. Reference display text is
independent of the reference kind. `DOC_MATH` and `DOC_PART` represent display
equations and template parts; metadata retains `META_*` scalar/container kinds
and tables may carry per-column `l`/`c`/`r` alignment. There are no raw-document
or free-form style-attribute nodes. Its validator rejects invalid links and
cycles without imposing node-allocation order on valid trees.

This is a prototype **frontend tree**, not the positioned graphics IR or an
implementation of all MyST AST nodes. The [native MyST profile](fplotlib_markdown.md)
defines the reader, reference and template contracts. `layout_fragment` rejects
document-level metadata, parts and page breaks rather than silently ignoring them.

## Positioned frames, pages and export

`fplotlib_scene` owns the reusable, finished drawing data. Handles are local
to one owning frame; import copies a child once and placement reuses that copy.

```text
frame%init(width, height, [baseline], status)
frame%metrics(width, height, [baseline, handle], status)
frame%ink_bounds(bounds, [has_ink], status)
frame%set_size(width, height, status)
frame%set_baseline(baseline, status)
frame%import_frame(child, handle, status)
frame%place(handle, [matrix, clip], status)
frame%draw(renderer, [handle], status)
frame%source_text(status) -> text

document%clear(status)
document%add_page(page, status)
document%page_count() -> n
document%page_size(page, width, height, status)
document%draw_page(page, renderer, status)
document%page_frame(page, frame, status)

fplotlib_document
  export_document(document, format, assets, [dpi], status)
  save_document(document, filename, [dpi], status)

fplotlib_draw
  render_frame(frame, [facecolor, transparent, bbox_inches, pad_inches], status)
```

The last function is a bridge from the **implicit current plot** to an owned
frame, not an explicit-context plotting API. The reusable typesetting and
export modules do not depend on it.

`set_size` changes nominal layout dimensions, not graphical scale.
`source_text` concatenates stored source in painting order, including TeX;
it is not semantic, accessibility or reading-order text.

PDF produces one `document_asset_t` for all pages. SVG, PNG and EPS produce
one per page. `dpi` affects PNG only. Failed byte export leaves `assets`
unallocated; multi-file filesystem output is not transactional.

## Primitive layout: prototype

**All `ts_*` interfaces are prototypes, subject to change.** They accept a
caller-owned `typeset_context_t`. The finished frames/pages do not borrow its
arenas. Settings, paragraph construction and vertical-list construction are:

```text
ts_reset(state, status)
ts_set_page(state, w, h, left, right, top, bottom, [numbers, headings_, flush], status)
ts_set_font(state, size, [leading], status)
ts_set_colors(state, text, page, status)
ts_set_parskip(state, g)
ts_set_clubpenalty(state, p)

ts_begin_par(state, align, indent, [left, right, size, hang, skip, leading, nobreak], status)
ts_end_par(state, status)
ts_in_par(state) -> logical
ts_text(state, text, face, size, [color], status)
ts_word(state, s, face, size, [color, raise], status)
ts_math(state, src, size, [color, display, tag], status)
ts_label(state, s, face, size, sep, [color], status)
ts_space(state, face, size, status)
ts_nbsp(state, face, size, status)
ts_hfil(state)
ts_kern(state, w, [text])
ts_hard_break(state, status)
ts_strut(state, h, d)

ts_vskip(state, g, status)
ts_addvspace(state, g, status)
ts_vkeep(state, g, status)
ts_vfil(state, status)
ts_penalty(state, p)
ts_addpenalty(state, p, status)
ts_rule(state, width, thick, [color], status)
ts_page_break(state, status)
ts_mark(state, s, plain, [section])
ts_nobreak_next(state)
```

Frame composition, completion and measurement are:

```text
ts_import_frame(state, frame, handle, status)
ts_place_frame(state, handle, [left, right, align, interline, repeat_before], status)
ts_finish_frame(state, frame, status)
ts_finish(state, document, status)
ts_paginate(state, status)
ts_page_count(state) -> n
ts_page_size(state, w, h, [color])
ts_page_draw(state, r, p, status)
ts_hsize(state) -> width
ts_vsize(state) -> height
ts_font_size(state) -> size
ts_word_width(text, face, fontsize, status) -> width
ts_xheight(size) -> height
ts_quad(size) -> width
```

`ts_glue_t(w, st, sh, sto, sho)` stores natural width, stretch/shrink and
their orders. Alignment constants are `ALIGN_JUSTIFY`, `ALIGN_LEFT`,
`ALIGN_CENTER`, `ALIGN_RIGHT`. The diagnostic interfaces used by reference
comparisons are also prototype APIs:

```text
ts_par_lines(state, i0, i1)
ts_line_count(state) -> n
ts_line_info(state, l, gids, xs, n, status)
```

## Text, math and grid primitives

```text
fplotlib_text
  text_face(weight, slant) -> face
  text_layout(s, size, face, x0, y0, run, xend, status)
  text_width(s, size, face, status) -> width
  code_points(s, cps, n, [first, last])
  run_reset(run)
  run_add(run, gid, x, y, fs, status)
  run_map(run, first_glyph, last_glyph, text, [math], status)
  run_copy(source, dest, status)
  run_shift(run, k0, dx, dy)

fplotlib_hyph
  hyph_points(word, lhm, rhm, pos, n, status)

fplotlib_mathtext
  math_is(s) -> logical
  math_width(s, size, [face, context], status) -> width
  math_layout(s, size, run, rules, width, [face, context], status)
  math_formula(s, size, display, run, rules, w, h, d, [context], status)
  math_frame(s, size, display, frame, [paint, context], status)

fplotlib_grid
  grid_widths(natural, minimum, available, padding, widths, status)
  grid_row(cells, widths, padding, frame, [background, rule_color], status)
```

`math_is` only detects dollar signs; it is not a syntax validator.
`math_layout` handles mixed text and `$...$`; `math_formula` and `math_frame`
take a formula without dollar delimiters. `math_context_t` is optional reusable
scratch storage, not a global math workspace. `mrules_t` holds rule positions.
Grid cells are already laid-out `frame_t` objects, independent of Markdown.

## Drawing targets and encoders

`fplotlib_render:renderer_t` is the drawing interface. No file or byte
serialization is required to implement it:

```text
open_canvas(width, height, [bg_rgb, bg_alpha, x0, y0], status)
close_canvas(status)
draw_path(x, y, verbs, n_verb, paint, status)
draw_rect(x, y, w, h, paint, [radius], status)
draw_circle(cx, cy, r, paint, status)
draw_markers(x, y, mx, my, mverbs, n_mverb, paint, status)
draw_glyphs(x, y, run, paint, angle, status)
draw_image(x, y, w, h, rgba, nx, ny, paint, status)
begin_group(name, status)
end_group(status)
begin_frame(matrix, clip, status)
end_frame(status)
```

`encoded_renderer_t` adds `bytes(status) -> bytes`. The SVG/PDF/PNG/EPS
renderers extend that type; `recording_renderer_t` extends drawing alone and
adds `take(frame, status)`. PDF also has
`new_page([width, height, bg_rgb, bg_alpha], status)`, and PNG has
`set_dpi(dpi, status)`.

The data records are `clip_t`, `paint_t`, `font_t` and `glyphrun_t`.
Colors are integer RGB triples in `[0, 255]`. Positions use points (1/72 inch),
top-left origin, y down, clockwise angles. Affine entries `[a,b,c,d,e,f]` map
`(x,y)` to `(a*x+c*y+e, b*x+d*y+f)`; frame clips use child-local coordinates.
All four built-in backends support both nonzero and even-odd path filling.

## Resource and error contracts

`fplotlib_resources:initialize_resources(status)` prepares the built-in fonts
and English hyphenation tables. Ordinary serial entrypoints do this
automatically. Call it serially before concurrent explicit-context work.
After initialization the tables are shared read-only; the convenience facade
is not reentrant, and this policy is not a blanket thread-safety guarantee.

`fplotlib_status:status_t` contains `code` and an allocatable `message`, with
`ok()` and `set(code, message)` methods. Codes are `STATUS_OK`, `ERROR_ARGUMENT`,
`ERROR_STATE`, `ERROR_UNSUPPORTED`, `ERROR_IO`, `ERROR_LAYOUT`, `ERROR_RESOURCE`.
Every fallible call requires the argument and replaces its previous value.
Check or propagate it immediately. On failure, ignore data outputs and discard
a partial drawing target or reset/rebuild a failed primitive layout.
The contract does not promise recovery from runtime allocation failure.

## Known gaps

The foundation is reusable, not yet a complete Typst/TeX engine. General
inline frames and horizontal glue/penalty/discretionary constructors, a public
math tree, external-font resources and full complex-script shaping are not
implemented. `ts_penalty` currently affects the vertical list, and fragment
layout uses a tall temporary page rather than an unbounded-flow constraint.
Report tables do not span columns/rows or split one row across pages.
Frames carry positioned graphics and source mappings, not the full semantic
structure needed for accessible HTML or tagged PDF.
