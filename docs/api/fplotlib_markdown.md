# fplotlib_markdown module

The native reader implements a **small MyST Markdown profile**, in Fortran,
with no parser or publishing-tool dependency. It is not a complete MyST or
CommonMark implementation. The extension syntax comes from MyST; physical
layout belongs to native templates, not a second document command language.

`markdown()` appends complete blocks in program order. Separate calls do not
continue a paragraph, open fence or document part from a previous call.
Front matter belongs to the first call. `md_parse` and `md_append` are the
explicit-context reader API; a failed append preserves the previous tree.
The reader retains parsed caption and reference-display nodes. Semantic
preparation works on an owned tree copy before layout; layout does not reparse
Markdown display strings. The explicit Markdown layout adapters are imported
from `fplotlib_report`.

## Content

| Construct | Native profile |
|---|---|
| Paragraphs and headings | Soft line breaks become spaces; ATX headings have levels 1–6; setext headings are supported. |
| Emphasis and code | CommonMark delimiter flanking/nesting, escapes and backtick runs; code contents stay literal. |
| Hard line breaks | Backslash before a newline, two trailing spaces, or `<br>`. For an array of padded Fortran lines, use backslash or `<br>`: the array API trims padding. |
| Lists and block quotes | Ordered/bullet lists, nested blocks and tight/loose list spacing. |
| Code blocks | Indented or fenced. Closing fences must match the opening character and have at least its length. Ordinary code fences may end at EOF. |
| Thematic rules and comments | CommonMark rules and MyST `%` line comments. |
| Links | Inline `[text](url)` and angle-bracket URL/email autolinks. Reference-definition links are outside the profile. Links currently style text; clickable-link and semantic HTML export are not promised. |
| Entities | Numeric Unicode entities plus `amp`, `lt`, `gt`, `quot`, `apos` and `nbsp`; other named entities are unsupported. |
| Pipe tables | Plain-text cells, escaped pipes and left/center/right column alignment. Missing cells are empty; surplus cells are discarded, as in the upstream table parser. Rich cells are unsupported. |
| Directives | `{math}` and plain `{div}` groups, with backtick, tilde or colon fences. Nested fences use a longer outer fence; directives must close. |

Optional smart quotes, dash/ellipsis substitution, definition lists and task-list
interpretation are disabled. Write typography such as curly quotes and dashes
literally. Images, raw HTML other than line breaks, footnotes, bibliography
processing, includes, executable notebooks, arbitrary roles/directives and
CSS-driven styling are outside this profile. Unsupported recognized features
return a status error; the high-level facade currently aborts on such errors.

Plots and numerical tables use `include_figure` and `include_table`; there is
no Markdown data-embedding language. Their input is copied immediately.
Programmatically supplied table cells are plain text, including literal `$`;
captions are Markdown without document metadata, parts or page breaks.

## Math and references

````markdown
(results)=
# Results

```{math}
:label: energy
E = mc^2
```

See @energy or [](#energy).
````

Inline math uses `$...$` or `` {math}`...` ``. Displays use `$$...$$` or
the `{math}` directive. MyST dollar math permits spaces and digits next to
delimiters: `$ a $` is math, and a pair of currency dollar signs can also
start math. Escape currency as `\$`. Double-dollar math inside a paragraph
is also a display. Only fplotlib's implemented TeX **math** language is supported;
standalone AMS environments outside math delimiters are not enabled.

Equation labels can be given by `(target)=` before the block, `:label:` on a
math directive, `\label{target}` inside the formula, or `$$...$$ (target)`.
Use `:enumerated: false` for an unnumbered math directive. Within math,
`\tag{...}`, `\notag` and `\nonumber` are supported.

References are typed, not inferred from names such as `eq:`:

| Syntax | Meaning |
|---|---|
| `@target`, `[](#target)`, `` {numref}`target` `` | Automatic display: `(1)`, `Figure 1`, `Table 1`, or `Section 1`; an unnumbered heading uses its title. |
| `` {ref}`target` `` | The target's title when available, otherwise its automatic display. |
| `` {eq}`target` `` | An equation reference; a non-equation target is an error, even with custom text. |
| `[Equation {number}](#target)`, `` {ref}`custom text <target>` `` | Custom display text; `{number}`, `%s` and `{name}` substitute the target's number/title. Code spans stay literal. |

Targets must be explicit; automatic heading-slug generation and references to
other files are not implemented. Native reference identifiers are currently
ASCII. `(target)=` follows MyST's restricted target-token grammar (at most
100 characters); directive and programmatic labels may be longer. Matching
normalizes ASCII case, whitespace and quotation marks; link fragments decode
percent escapes. Duplicate/unresolved targets, unavailable equation numbers
and cyclic reference display text return errors.

Headings are unnumbered by default; equations, included figures and tables
are numbered. Configure standard MyST numbering with a boolean or mapping:

```yaml
numbering:
  headings: true
  equations: true
  figures: true
  tables: true
```

`numbering: false` disables all four. The native book template uses chapter
numbers for headings and equations.

## Native templates and document parts

Choose a template through standard MyST export metadata:

```yaml
---
exports:
  - format: pdf
    template: letter
numbering: false
---
```

`article`, `book`, `letter` and `invitation` are **fplotlib's native templates**,
not names claimed to be built-in community MyST templates. This is not a
general template interpreter. One `format: pdf` entry configures the print
layout; `save("report.svg")`, for example, can serialize those same pages as
SVG. `save` selects the filename; `exports.output` is unsupported rather than
silently overriding that argument.

| Template | Defaults | Declared document parts |
|---|---|---|
| `article` | A4, 10 bp, 1-inch margins, justified text and page numbers | `abstract` |
| `book` | A5, 10 bp, 1.8-cm margins (2.2 cm at top), chapters and running heads | `abstract` |
| `letter` | US letter, 11 bp, 1.1-inch margins, paragraph spacing, no page numbers | `sender`, `recipient`, `opening`, `closing`, `signature` |
| `invitation` | 5 × 7 inches, 12 bp, 0.55-inch margins, centered text, cream background | `intro`, `ornament`, `reply`; the card title is `title` metadata |

Parts contain ordinary Markdown. Supply them using standard MyST content
blocks:

```markdown
+++ {"part": "sender"}
Ada Lovelace<br>
London

+++ {"part": "recipient"}
Charles Babbage

+++ {"part": "opening"}
Dear colleague,

+++
Here is the body of the letter, including $E=mc^2$.

+++ {"part": "closing"}
Yours sincerely,

+++ {"part": "signature"}
Ada
```

The letter template aligns addresses and supplies signature spacing. The
invitation template chooses title/ornament colors and sizes and centers the
card vertically. Those are **template policies**, not `.Huge`, `size=`,
`\vspace` or other document-input extensions.

Parts may instead be Markdown strings under front matter:

```yaml
parts:
  sender: |
    Ada Lovelace<br>
    London
```

A front-matter part takes precedence over content-block parts of the same
name. Multiple content blocks for a part are retained in order. Parts must
be top-level and declared by the chosen template. Article/book abstracts may
also use the standard top-level `abstract` key.

Standard `+++ {"new-page": true}` starts a new page without stretching the
previous page to fill it; `+++ {"page-break": true}` inserts a forced page
break while retaining normal page filling. Neither introduces a custom
directive. A part-level break applies where the template places that part.

## Metadata subset

Front matter uses block-style YAML mappings/sequences, string/boolean/decimal/
null scalars, quoted escapes and literal/folded block strings (`|`, `>`, with
optional `-` or `+` chomping). Duplicate keys and invalid indentation are
errors. Flow collections, anchors, aliases, tags, complex keys, multiline
quoted/plain scalars and explicit block-scalar indentation indicators are
unsupported. Quote hex colors: `"#fbf3e4"`; an unquoted `#` begins a YAML comment.
ISO dates remain strings.

The supported document keys are `title`, `subtitle`, `authors`, `date`,
`abstract`, `parts`, `numbering` and `exports`. Authors may be a name, a sequence
of names, or a sequence of mappings with `name`. Standard aliases `author`,
`part` and `export` are accepted. Unknown native metadata/options are errors.
Article/book title blocks use title, subtitle, authors and date. Letter
content comes from its parts; invitation content uses its title and parts.

Native template options are direct keys on the export entry, as MyST
template options are, not root document keys:

```yaml
exports:
  - format: pdf
    template: article
    paper: letter
    fontsize: 11pt
    margin: 0.8in
```

The declared options are `paper`, `fontsize`, `margin`, `margin-left`,
`margin-right`, `margin-top`, `margin-bottom`, `parskip`, `indent`,
`linestretch`, `align`, `pagenumbers`, `color` and `pagecolor`.
`paper` accepts `a4`, `a5`, `a6`, `b5`, `letter`, `legal` or `W x H`.
Lengths are nonnegative, in native points (`bp`/`pt`, 1/72 inch), `in`, `cm`,
`mm`, `em` or `ex`; bare numbers are points. `indent` also accepts a boolean.
`linestretch` is a positive multiplier of the normal 1.2-times-font-size leading.
`align` is `left`, `right`, `center` or `justify`; page numbering is boolean.
Colors are named colors or quoted `#rgb`/`#rrggbb`. Font size is resolved before
relative lengths, and side-specific margins override the general margin,
independently of key order.

Fragments (`layout_fragment`) cannot contain document metadata, parts or page
breaks: those require a report.

## Migration and conformance checks

There is no legacy parsing mode. Replace heading `{#id}` attributes with
`(id)=`, equation suffix `{#id}` with MyST labels, root layout keys with
native export options, and raw page commands with MyST content-block metadata.
Move letter/card styling into their templates and named parts. Former Pandoc
span/heading attributes and raw TeX document commands are ordinary literal
text where Markdown permits them; old fenced-div styling is unsupported.

`tests/myst_refs.txt` records normalized structures from pinned upstream
`myst-parser` 1.7.5; `test_markdown` checks the native reader against them.
Regenerate with `node tools/gen_myst_refs.mjs /path/to/node_modules/myst-parser`.
The oracle retains list tightness from upstream tokens because its default
AST conversion drops it. Two upstream data-loss cases are checked separately
against CommonMark: unterminated front matter does not swallow the document,
and an all-space code span retains all its spaces. These checks do not claim
complete CommonMark conformance.

`tools/compare_docs.py` uses the same upstream MyST parser, then Pandoc only
as a LaTeX/Typst **writer**, with matching native template policies. It does
not feed MyST documents to Pandoc's Markdown reader.

## Primary syntax references

- [MyST syntax overview](https://mystmd.org/guide/syntax-overview): CommonMark,
  directives, roles and their extension syntax.
- [MyST cross-references](https://mystmd.org/guide/cross-references): `@target`,
  link references, target labels and reference formatting.
- [MyST math](https://mystmd.org/guide/math): dollar math, `\label` and math
  directives.
- [MyST document parts](https://mystmd.org/guide/document-parts).
- [MyST exports](https://mystmd.org/guide/documents-exports) and
  [template options](https://mystmd.org/guide/creating-pdf-documents).

```{f:module} fplotlib_markdown
```
