# fplotlib_docclass module

`layout_markdown`, `layout_fragment` and `doc_typeset` take explicit
`layout_context_t` workspaces and required `status_t` outputs.
Their finished frames/pages own the drawing data and outlive the workspace.

The internal `fplotlib_doctemplate` records define the native templates'
defaults, allowed parts, part styles and ordered steps in one place.
Validation, reference traversal and rendering use those same records.
They are not a public template DSL or a universal document language.

Fragment layout currently uses a very tall temporary page;
a general unbounded-flow constraint is still work in progress.

```{f:module} fplotlib_docclass
```
