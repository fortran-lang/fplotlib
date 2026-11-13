# fplotlib_grid module

These layout primitives do not parse Markdown or access an implicit report.

`grid_widths` fits preferred and minimum content widths to an available width,
including cell padding. `grid_row` composes already laid-out cell frames,
aligns their first baselines and produces an owned row frame.

The page builder accepts rows through `ts_place_frame` with `interline=.false.`
and an optional `repeat_before` header-frame handle. It reserves and draws that
header when a row starts a continuation page. Rows are unbreakable; a row that
cannot fit with its repeated header is rejected rather than clipped.

```{f:module} fplotlib_grid
```
