# fplotlib_docclass module

`doc_typeset` and `doc_fragment` accept parsed frontend trees and explicit
`layout_context_t` workspaces and required `status_t` outputs.
Their finished frames/pages own the drawing data and outlive the workspace.

An internal resolution pass prepares a separate owned copy with typed settings,
part selections, numbering and reference display nodes. Layout consumes those
results without parsing Markdown or interpreting raw metadata. The Markdown
adapters `layout_markdown` and `layout_fragment` live in `fplotlib_report`;
the parser remains independent in `fplotlib_markdown`.

The internal `fplotlib_doctemplate` records define the native templates'
defaults, allowed parts, part styles and ordered steps in one place.
Validation, reference traversal and rendering use those same records.
They are not a public template DSL or a universal document language.

Fragment layout currently uses a very tall temporary page;
a general unbounded-flow constraint is still work in progress.

```{f:module} fplotlib_docclass
```
