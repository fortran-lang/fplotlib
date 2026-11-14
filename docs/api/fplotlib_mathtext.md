# fplotlib_mathtext module

Math measurement and layout take required `status_t` outputs. An optional
`math_context_t` reuses scratch storage; otherwise the call owns local scratch.
`math_frame` returns an independently owned frame.

The input is TeX math source, not a public math-tree API. A programmatic math
representation, broader shaping/font selection and complete TeX compatibility
are not provided by this prototype.

```{f:module} fplotlib_mathtext
```
