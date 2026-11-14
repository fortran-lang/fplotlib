# fplotlib_mathtext module

Math measurement and layout take required `status_t` outputs. The layout keeps
no state between calls. An optional `math_context_t` reuses scratch storage;
otherwise the call owns local scratch.

The input is TeX math source, not a public math-tree API. A programmatic math
representation, broader shaping/font selection and complete TeX compatibility
are not provided.

```{f:module} fplotlib_mathtext
```
