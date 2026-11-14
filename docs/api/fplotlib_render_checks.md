# fplotlib_render_checks module

The preconditions of the rendering contract, shared by the backends: an open
canvas, finite geometry, colors and alphas in range, a known fill rule, cap
and join, a consistent path and a valid glyph run. A call that breaks one is
a bug in the caller, so `contract_error` stops the program with a message
naming the rule instead of returning an error.

```{f:module} fplotlib_render_checks
```
