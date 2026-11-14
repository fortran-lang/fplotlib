# fplotlib_docclass module

`layout_markdown`, `layout_fragment` and `doc_typeset` take explicit
`layout_context_t` workspaces and required `status_t` outputs.
Their finished frames/pages own the drawing data and outlive the workspace.

This is the small article/book frontend's policy layer, not a universal
document language. Fragment layout currently uses a very tall temporary page;
a general unbounded-flow constraint is still work in progress.

```{f:module} fplotlib_docclass
```
