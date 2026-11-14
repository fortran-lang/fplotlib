# fplotlib_typeset module

**Prototype API, subject to change.** The `ts_*` routines expose the current
paragraph and page engine, not a finalized general-purpose typesetting API.
Colors are integer RGB triples in `[0, 255]`, matching grid rows and `paint_t`.
Lengths are points (1/72 inch); glyph baselines and frame placement use the
shared top-left, y-down coordinate system.

The low-level interface is a work in progress. It does not yet expose arbitrary
inline frames or general horizontal glue, penalties and discretionaries;
`ts_penalty` currently affects the vertical list. Math input is still a TeX
string, not a public programmatic math tree. `layout_fragment` in
`fplotlib_docclass` uses a very tall temporary page rather than an unbounded
flow constraint. These are interface gaps, not promises of complete
TeX/Typst compatibility.

Fallible operations take a required `status_t` output. Infallible state queries
and simple list operations do not. In particular, oversized unbreakable
content returns a layout error rather than terminating the application.
The [complete inventory](typesetting_api.md) distinguishes these signatures.

```{f:module} fplotlib_typeset
```
