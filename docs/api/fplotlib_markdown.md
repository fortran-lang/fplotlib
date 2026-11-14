# fplotlib_markdown module

The current reader is a **Pandoc-inspired scientific Markdown subset**.
It is not a conforming CommonMark, Pandoc, or MyST implementation. The API
cleanup does not change the accepted syntax; a dialect change needs its own
compatibility decision and parser tests.

## What the current syntax means

| Surface | Current contract |
|---|---|
| Headings, paragraphs, emphasis, code, lists, quotes and links | A handwritten Markdown subset. Parsing a link does not imply a clickable-link backend or semantic HTML export. |
| `$...$` and `$$...$$` | TeX math delimiters also used by Pandoc and MyST. Only the implemented math language is supported. |
| `\label{name}` inside display math | An equation label; modern MyST also supports this spelling. |
| `@label` | A reference shorthand also present in modern MyST. fplotlib's numbering/rendering policy is its own, including its `eq:` prefix convention. |
| Heading/display `{#id}` attributes | The current attribute-based labeling convention, not a claim of MyST target syntax support. |
| `::: {.center ...}` and `[text]{...}` | Pandoc-style fenced divs and bracketed spans. Classes such as `.Huge` and properties such as `size=` have fplotlib-specific layout meanings. |
| Front matter between `---` lines | A small metadata reader, not arbitrary YAML. Keys such as `paper`, `margin`, `class`, `numbersections` and `numberequations` configure the current article/book policy. |
| `\newpage`, `\vspace`, `\vfill`, `\hfill`, size/style commands | Legacy convenience extensions interpreted by this frontend. They do not make it a TeX macro system or a portable MyST document. |

Figures and tables can be supplied through `include_figure` and `include_table`
without inventing a Markdown data-embedding language. Table cells supplied by
the Fortran API are plain text; captions are Markdown.

## Direction for the next syntax review

A small, explicitly documented **CommonMark + MyST profile** would give the
frontend an established extension grammar while keeping full publishing-system
features outside fplotlib. Dollar math and `@label` can remain; they are not
inherently custom syntax. The changes to consider are MyST block targets,
standard math directives, and consistent typed reference targets instead of
inferring equation formatting from an identifier prefix.

For example, the following is a **proposal, not syntax currently supported by
this reader**:

````markdown
(results)=
# Results

```{math}
:label: energy
E = mc^2
```

See @energy or [](#energy).
````

The profile should enumerate supported constructs and their behavior,
including currency/escaped dollars, nesting, whitespace and reference
formatting. It should not promise every MyST role, directive, citation system,
notebook integration, or arbitrary YAML structure. Existing Pandoc-style
attributes and raw document-layout commands need an explicit migration policy,
not silent reinterpretation.

## Primary syntax references

- [MyST syntax overview](https://mystmd.org/guide/syntax-overview): CommonMark,
  directives, roles and their extension syntax.
- [MyST cross-references](https://mystmd.org/guide/cross-references): `@target`,
  link references, target labels and reference formatting.
- [MyST math](https://mystmd.org/guide/math): dollar math, `\label` and math
  directives.
- [Pandoc manual](https://pandoc.org/MANUAL.html): the `fenced_divs`,
  `bracketed_spans`, `tex_math_dollars`, `raw_tex` and `yaml_metadata_block`
  extensions. The [manual source](https://github.com/jgm/pandoc/blob/main/MANUAL.txt)
  documents these separately.

```{f:module} fplotlib_markdown
```
