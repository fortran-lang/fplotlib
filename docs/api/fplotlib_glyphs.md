# fplotlib_glyphs module

Internal queries over the compiled-in glyph tables do not initialize shared
state. Direct users must first call
`fplotlib_resources:initialize_resources(status)` and check its result.
Public text, math and renderer entrypoints do this for ordinary serial use.
After initialization the decoded tables are read-only.

```{f:module} fplotlib_glyphs
```
