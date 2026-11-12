# fplotlib

[![CI](https://github.com/certik/fplotlib/actions/workflows/ci.yml/badge.svg)](https://github.com/certik/fplotlib/actions/workflows/ci.yml)

Pure Fortran plotting library with a pylab-style API, writing SVG, PNG, PDF and EPS.
No external graphics library: the PNG rasterizer and its fonts are part of fplotlib.

```fortran
use fplotlib
call plot(x, y, "k-", label="sin")
call title("My plot")
call xlabel("x")
call ylabel("y")
call grid(.true.)
call legend()
call savefig("out.svg")   ! or "out.png", "out.pdf", "out.eps"
call show()               ! Jupyter (LFortran) or writes fplotlib_show.svg

! subplots
call clf()
call subplot(2, 1, 1)
call plot(x, y, "b-", label="sin")
call title("top")
call subplot(2, 1, 2)
call plot(x, y2, "r--", label="cos")
call title("bottom")
call suptitle("figure title")
```

## Features

- `plot`, `scatter`, `bar`, `hist`, `fill_between`, `errorbar`
- `bar` takes `yerr=`, `capsize=`, `align="edge"` and `tick_label=`;
  `errorbar` takes `ecolor=`, `elinewidth=`, `lw=` and `alpha=`
- `plot(y)` with a single array numbers the points `0, 1, 2, ...` for x
- `xlim`/`ylim` to set, `get_xlim`/`get_ylim` to read back what autoscaling
  chose, and `invert_xaxis`/`invert_yaxis` to make an axis count down
- `scatter` also takes per-point `sizes=` and color-mapped `cvals=`
  (separate keywords because Fortran cannot overload one dummy as
  scalar-or-array the way matplotlib's `s=` and `c=` do)
- `step`, `stem`, `barh`, `pie`, `boxplot`, `violinplot`
- `boxplot(y)` for one dataset or `boxplot(y(:,:), labels=)` for a row
  each, with `vert=`, `notch=`, `showmeans=`, `patch_artist=` and `whis=`
- `violinplot` the same way, with `vert=`, `showmeans=`, `showmedians=`
  and `showextrema=`
- `pie(explode=, startangle=, counterclock=, autopct=, pctdistance=,
  labeldistance=, radius=, colors=, edgecolor=, linewidth=)`
- `semilogx`, `semilogy`, `loglog`, `axhline`, `axvline`
- `fill_betweenx` for a band along y, `stackplot` for layers summed on top
  of each other, and `axline` for an endless line through two points or
  through one with a `slope=`
- `text` and `annotate` (`arrowstyle="->"` draws a leader with a head at the
  annotated point, with `arrowcolor=`, `arrowlw=` and `shrink=`), with
  `rotation=`, `va=`, a `bbox_facecolor=` box behind them and lines broken
  at `achar(10)`; `figtext` places on the canvas instead of in the axes, and
  `transform="axes"` places in fractions of the axes box.
  `connectionstyle="arc3,rad=0.3"` bows the leader out of the straight
  line, and `boxstyle="round,pad=0.5"` rounds the corners of the box
- `imshow` of an (row, column, channel) array paints the colours given,
  three channels for RGB or four for RGBA
- `imshow` with `cmap`, `extent`, `origin`, `vmin`/`vmax` and square-pixel
  `aspect`, plus `colorbar(label=, orientation=, fraction=, pad=, shrink=,
  aspect=)`, upright or lying on its side
- `contour` and `contourf` with automatic or explicit `levels`
- Colormaps: `viridis`, `plasma`, `inferno`, `magma`, `gray`, `coolwarm`
- Format strings: colors `bgrcmykw` / `C0`–`C9`, linestyles `-` `--` `:` `-.`,
  markers `o x . s ^ v < > * + D`
- Optional `label=`, `lw=`, `color=`, `marker=`, `alpha=`
- `hatch=` on bars, fills and patches: `/`, `\`, `|`, `-`, `+` and `x`,
  repeated to pack the lines closer, ruled across the shape and clipped
  to it (matplotlib's dotted hatches are not drawn)
- Marker and line detail on `plot`: `markersize=`, `markerfacecolor=`,
  `markeredgecolor=`, `markeredgewidth=`, `markevery=`, `drawstyle=` and
  a `dashes=` pattern of your own
- Title, axis labels, grid, `xlim` / `ylim`, `clf` / `figure(figsize=, dpi=)`
- `set_facecolor(color, alpha=)` for the background of one axes
- `grid(on, axis=, which=, color=, linestyle=, lw=, alpha=)` for one axis
  only, for the minor ticks, or in a colour of your own; log axes carry
  minor ticks without being asked, as matplotlib's do
- `savefig(file, transparent=, facecolor=)`; the extension picks the format,
  one of `.svg`, `.png`, `.pdf` or `.eps`, and `dpi=` sizes the PNG raster
- `axis("on"|"off"|"equal"|"scaled"|"tight"|"auto")` and `set_aspect`
- `margins(m)` or `margins(x=, y=)` for the room left past the data, and
  `autoscale(enable, axis=, tight=)`; `autoscale(.false.)` pins the limits
  where the data has put them so far, so nothing drawn later moves them
- `set_xscale` / `set_yscale` with `"linear"`, `"log"` or `"symlog"`
- `tick_params(axis=, direction=, length=, labelsize=, rotation=)` and `spines`
- `legend(loc=, fontsize=, ncol=, frameon=, title=, bbox_to_anchor=,
  labels=)`, placed where the data leaves most room when `loc` is left
  out, as matplotlib's `"best"` does; a label starting with `_` keeps
  its artist out of the legend,
  `figlegend(loc=, fontsize=, ncol=, frameon=, title=)` for one legend
  covering every panel,
  `xticks` / `yticks` with optional labels, `minorticks_on`,
  `xticks(vals, minor=.true.)` to place minor ticks by hand, and
  `locator_params(axis=, nbins=, prune=)`
- Formatters and locators: `tick_format(axis, "percent"/"comma"/"fixed")`,
  `tick_locator(axis, base=, nbins=)` and `ticklabel_format(style=,
  useoffset=, scilimits=)`. An axis whose labels would otherwise repeat
  themselves factors the shared offset and power of ten out into a single
  label at its end, as matplotlib's ScalarFormatter does
- Font sizes: `fontsize=` on `title` / `xlabel` / `ylabel` / `suptitle`, and
  `set_fontsize(size=, title=, labels=, ticks=, legend=)` to set them globally
- `title(loc="left"|"right")` and `xlabel`/`ylabel(labelpad=)`
- `savefig(dpi=, bbox_inches="tight", pad_inches=)` to crop to the drawing
- Several live figures at once: `figure(num=)`, `gcf()`, `close(num=, all=)`
- `subplots(m, n, axs, sharex=, sharey=)` hands back axes handles, so
  `call axs(1,2)%plot(x, y)` works alongside the stateful `subplot` style;
  shared axes span the union of the group and drop their inner tick labels.
  Every call the stateful interface offers is also a method on the handle
- Subplots: `subplot(m, n, i)` and figure-level `suptitle`; per-axes state
  (series, labels, grid, legend, scale, limits) with matplotlib's default
  subplot spacing
- `subplots_adjust` and `tight_layout`
- `constrained_layout(.true.)`: the same fit, but made afresh at draw
  time, so labels added after the plotting still get their room. Ours
  keeps one margin for the whole grid where matplotlib works row by row
- `twinx` and `twiny` for a second y or x axis on the same plot
- Bars: `bar`/`barh` with `bottom=`/`left=` for stacks, `colors=` for a
  color per bar, `edgecolor=`/`linewidth=`, and `bar_label(fmt=, padding=)`
- `add_axes` for an axes placed by hand, `inset_axes` for a small axes
  inside another, and `secondary_xaxis`/`secondary_yaxis` for a second
  scale along an edge
- `table` for a block of text below (or above) the axes
- `streamplot` for the streamlines of a vector field
- `add_frame` / `save_animation(file, fps=, loop=)` to write an animated GIF, or a full-colour animated PNG with a `.png` or `.apng` file name
- `spy` (sparsity pattern of a dense matrix or COO indices), `matshow`, `eventplot` and `broken_barh`
- `hist2d` and `hexbin` for counting points into square or hexagonal bins
- `imshow(interpolation="bilinear")` to smooth an image instead of
  showing it as blocks
- 3D axes: `plot3d`, `scatter3d`, `plot_surface` (flat or `cmap=`) and
  `plot_wireframe`, with `view_init`, `zlabel` and `zlim`, drawn with
  mplot3d's camera, panes and lighting
- Polar axes: `polar(theta, r)`, or `set_polar()` on an axes, with the
  angular grid, the degree labels and the radial labels along 22.5°
- Layered like matplotlib: images below patches, the grid above the
  patches and below the lines, text on top, with `set_zorder` to lift
  the artist just drawn out of that order
- Missing data: a NaN or an infinity breaks the line and the band there
  and takes no part in the limits, as it does in matplotlib
- Patches: `add_rectangle`, `add_circle`, `add_ellipse`, `add_polygon`,
  `add_arrow` and `add_path` for an arbitrary path of lines and cubics,
  filled and outlined in data coordinates
- `clabel` to write the level into each contour line, breaking the line
  at its straightest stretch to make room
- `quiver` for a field of arrows, sized as matplotlib sizes them, and
  `quiverkey` for a reference arrow drawn to the same scale
- Date axes: `date_num(y, m, d)` for the numbers and `xaxis_date()` to
  have the ticks land on round dates and read as dates
- `subplot2grid`: panels that span several cells of a grid, so a wide
  plot can sit over two narrow ones
- `subplot_mosaic(["AB", "CC"], keys, axs)`: the panels drawn as a small
  picture of the figure, one character per cell, a panel per character
- `gridspec(width_ratios=, height_ratios=)`: columns and rows of unequal
  size, for a wide panel beside a narrow one
- `pcolormesh` and `pcolor`: a grid of cells with edges of your own
  choosing, which is what an unevenly sampled field needs
- `triplot` and `tripcolor`: scattered points joined into triangles by
  the same Delaunay triangulation matplotlib gets from Qhull, drawn as
  edges or filled by value
- `tricontour` and `tricontourf`: level lines and filled bands over those
  same triangles, with matplotlib's rounded levels and a colorbar
- `plot_trisurf`: those triangles lifted into three dimensions and lit by
  the same light source `plot_surface` uses
- `bar3d`: boxes standing on the xy plane, six lit faces each, painted
  back to front with everything else in the axes
- `quiver3d`: arrows in space, a shaft and two barbs turned fifteen
  degrees off it, with the limits taken from where the arrows start
- `contour3d`: level lines of a grid drawn in space, each at the height
  of its own level
- matplotlib's tick locator and formatter: the same 1/2/2.5/5 steps, the
  same number of ticks for the space available, and one decimal count
  shared by the whole axis. A log axis writes its decades as powers, and
  when it spans a decade or less it labels the multiples between them
- Mathtext: TeX math in any label (`$E = mc^2$`, `$x_i^2$`,
  `$\frac{a}{b}$`, `$\sqrt[3]{x}$`), set in Lete Sans Math with TeX's
  layout (The TeXbook, Appendix G) driven by the font's OpenType MATH
  table, as XeTeX, LuaTeX and Typst do: script sizes and alternates, script
  shifts, math kerns and italic corrections, fractions, radicals, size
  variants and assemblies all come from the font. Supported are the greek
  letters, about two hundred operators, relations, arrows and other
  symbols; primes; `\frac`, `\dfrac`, `\tfrac`, `\cfrac`, `\binom`,
  `\over`, `\atop` and `\choose`; large operators with limits
  (`\sum`, `\int`, `\lim`, `\limits`, `\nolimits`) and the named functions
  (`\sin`, `\log`, `\operatorname{erf}`) in Lato; `\left`, `\middle` and
  `\right`, and `\big` to `\Bigg`; accents (`\hat`, `\bar`, `\vec`,
  `\widehat`, ...), `\overline` and `\underline`; the alphabets `\mathrm`,
  `\mathit`, `\mathbf`, `\mathsf`, `\mathbb` and `\mathcal`; `\text` in
  Lato; the four styles (`\displaystyle`, ...) and TeX's spaces (`\,`,
  `\quad`, ...); and the alignments `matrix`, `pmatrix`, `bmatrix`,
  `Bmatrix`, `vmatrix`, `Vmatrix`, `cases`, `array`, `aligned` and
  `gathered`. `tests/math_refs.txt` holds where XeTeX puts every glyph
  and rule of 92 test formulas, and the layout is checked against it
- Automatic delimiters, as Typst has them: matched `( )`, `[ ]`, `\{ \}`,
  `| |`, `\| \|`, `\langle \rangle`, `\lfloor \rfloor` and `\lceil \rceil`
  grow to fit what they enclose, so `$(\frac{a}{b})$` needs no `\left` and
  `\right`, and a `|` between them grows with them. They never shrink, so
  `$f(x)$` keeps its plain parentheses; unmatched ones (`$[0, 1)$`),
  escaped ones (`\(`, `\[`) and ones in braces (`{(}`) stay plain.
  `tests/delim_refs.txt` holds the sizes Typst chooses for 29 formulas
- Text is UTF-8 and set in Lato (regular, bold and italic; bold italic is
  set in bold), with
  its kerning, in every European script except Cyrillic. The outlines are
  compiled in, so every format draws the same glyphs: PNG fills them, SVG
  defines each once and `<use>`s it, and PDF and EPS embed them as Type 3
  fonts that keep the text selectable. Tick labels write their minus as
  U+2212, as matplotlib does
- `fontweight=` and `fontstyle=` on `title`, `suptitle`, `xlabel`,
  `ylabel`, `text` and `annotate`: real bold and italic faces, not a
  smeared or sheared regular one
- Categorical axes: `plot`, `bar` and `barh` take a list of names in place
  of the numbers, and place them at 0, 1, 2, ... with the names as ticks
- 49 matplotlib colormaps, plus the qualitative `tab10`, `tab20` and
  `Set1`, any of them reversed with a `_r` suffix
- `imshow(norm="log")` for a logarithmic color scale, and
  `imshow(boundaries=)` for matplotlib's `BoundaryNorm`: one flat color
  per band, and a colorbar of blocks to match
- `norm="centered"` with `vcenter=`, `norm="power"` with `gamma=` and
  `norm="symlog"` with `linthresh=`, on `imshow` and `pcolormesh`
- `set_bad`, `set_under` and `set_over` for the samples a colormap has
  nothing to say about, and `set_cmap_colors` to build one from a list of
  stops; missing samples are left clear unless `set_bad` says otherwise
- `errorbar` with `xerr=` and asymmetric `yerr_lo=`/`yerr_hi=` arms
- `fill_between(where=, interpolate=)` to shade only where a condition
  holds, carried out to the crossing point
- `scatter(edgecolors=, linewidths=)` to outline the markers
- `hist(bins=, bin_edges=, density=, cumulative=, histtype="step"/"stepfilled",
  weights=, stacked=, orientation="horizontal", log=, rwidth=)`
- `axhspan`/`axvspan` shaded bands and `hlines`/`vlines` line runs
- `style_use("ggplot")` and friends (`seaborn`, `fivethirtyeight`,
  `dark_background`, `grayscale`, `default`), or `rc(figsize=, dpi=,
  fontsize=, linewidth=, grid=, facecolor=, axes_facecolor=, grid_color=,
  text_color=, color_cycle=)` for one setting at a time
- Colors as CSS4/X11 names, `tab:` names, `#rgb`, `#rrggbb`, `#rrggbbaa`,
  single letters, `C0`-`C9`, or a greyscale fraction such as `"0.5"`
- SVG defaults aligned with matplotlib (6.4×4.8 in, tab10 colors, subplot margins)

## Documents

`typeset` sets a whole document, written in Markdown with TeX mathematics
(`$...$` inline, `$$...$$` displayed), and writes it as PDF, or as one SVG,
PNG or EPS file per page:

```fortran
call typeset([character(len=80) :: &
    "---", &
    "title: Notes", &
    "numbersections: true", &
    "---", &
    "# Energy", &
    "", &
    "The energy of a mass at rest is", &
    "$$ E = mc^2 $$ {#eq:einstein}", &
    "and @eq:einstein is the best known formula of physics."], "notes.pdf")
```

The layout is TeX's (`fplotlib_typeset`), with LaTeX's parameters and the
spacing of its article and book classes:

- paragraphs are broken into lines by Knuth and Plass's algorithm, TeX's
  `line_break` with its two passes, badness, demerits and fitness
  classes, and hyphenated with Liang's algorithm and the patterns LaTeX
  and Typst use for English (`hyph-en-us`); interword glue is XeTeX's
  for an OpenType font, and the space factor is `\nonfrenchspacing`'s;
- lines go onto a vertical list with `\baselineskip`, `\lineskip` and
  TeX's club, widow and broken penalties, and TeX's page builder cuts it
  into pages at the breaks of least cost;
- displays get `\abovedisplayskip` or the short skips, equation numbers
  at the right margin, and the paragraph goes on after them unindented.

A document goes through three layers, as in Pandoc and LaTeX: a reader
(`fplotlib_markdown`) reads the text into a tree of blocks and inlines
(`fplotlib_doctree`, Pandoc's); a document class (`fplotlib_docclass`) sets
the tree with LaTeX's styles, numbering sections and equations from a first
pass over it as LaTeX does from its `.aux` file; and the engine
(`fplotlib_typeset`) works at the level of TeX's primitives: words, glue,
kerns, penalties, paragraphs, formulas, marks, and the page builder with
its output routine. A program
can also build a tree itself and give it to the class.

The Markdown is Pandoc's: YAML front matter (`title`,
`author`, `date`, `abstract`, `paper`, `fontsize`, `margin`, `parskip`,
`align`, `numbersections`, `class: book`, `color`, `pagecolor`, ...),
headings, emphasis, lists, block quotes, code, rules, links, fenced divs
and bracketed spans for alignment, size and colour (`::: {.center .Huge
color=darkred}`), cross references (`$$...$$ {#eq:name}` and `@eq:name`,
`# Title {#sec:name}` and `@sec:name`, `\label`, `\eqref`, `\ref`), and the
TeX commands `\newpage`, `\vspace`, `\vspace*{\fill}`, `\bigskip`, `\hfill`
and `\quad`. The book class sets chapters, running heads and flush bottoms.
Lengths are PostScript points (1/72 in), as in Typst.

Why Markdown and not TeX: TeX as input means TeX's macro language
(category codes, `\def`, expansion) and LaTeX on top of it, and anything
less would break on the first document pasted from LaTeX. Markdown is small
and readable, the mathematics stays TeX, and a handful of TeX commands
cover the layout Markdown has no words for, as in Pandoc.

`tests/para_refs.txt` holds how XeTeX breaks seven paragraphs of Lato into
lines, read from its XDV output (`tools/gen_para_refs.py`), and `fpm test`
requires the same lines, hyphenated at the same places, with every glyph
within 0.07 bp (0.02 bp with Lato's exact kerning, which fplotlib stores
to 5 font units). `tools/compare_docs.py` sets the gallery's documents with
fplotlib, with LaTeX (Pandoc and Tectonic) and with Typst, with the same
fonts, and puts the pages side by side.

## Using fplotlib in your project

fplotlib is an [fpm](https://fpm.fortran-lang.org) package with no dependencies
outside the Fortran standard library, so a project picks it up with one entry
in its `fpm.toml`:

```toml
[dependencies]
fplotlib = { git = "https://github.com/certik/fplotlib" }
```

and then `use fplotlib` and call `plot`, `title`, `savefig` as the examples below
do. It builds with gfortran, flang and LFortran:

```bash
fpm build --compiler gfortran
fpm build --compiler flang
fpm build --compiler lfortran
```

The pixi tasks below are for developing fplotlib itself, with pinned compilers.

## Build

Requires [pixi](https://pixi.sh). Every compiler has its own environment with
nothing in it but the compiler and fpm: gfortran and LFortran come from
conda-forge on Linux and macOS, flang on Linux (on macOS provide a system
flang on `PATH`). A task installs its environment the first time it runs.

```bash
pixi run test-gfortran       # fpm test --compiler gfortran
pixi run test-gfortran-O3    # the same, built with -O3 -march=native
pixi run test-flang
pixi run test-flang-O3
pixi run test-lfortran
pixi run demo-flang          # fpm run --example demo, writes demo.svg

# Compare the flang build against matplotlib references (needs Python,
# which lives in its own environment)
pixi run compare-all   # all five below, sharing one build
pixi run compare       # SVG, structurally
pixi run compare-png   # PNG, pixel by pixel
pixi run compare-pdf   # PDF, rasterized by pdftoppm
pixi run compare-eps   # EPS, rasterized by ghostscript
pixi run compare-gif   # GIF, frame by frame
```

## Tests

`fpm test` (or `pixi run test-gfortran`, `test-flang`, `test-lfortran`) writes every
test plot to `tests/out/` and checks each PNG, and each frame of the GIF,
against a stored fingerprint in `tests/fingerprints.txt`. It needs nothing
outside the repository: no Python and no reference images.

A fingerprint is 4096 bits, 64 words of 64 bits, one word per tile of the
image, computed with integer arithmetic only (`tests/test_fingerprint.f90`).
Two builds of the same picture differ in a few bits per word, because
compilers round some antialiased edge pixels one level differently; a moved,
missing or recoloured element changes about half the bits of its tile's word.
A case fails when any word differs by more than 10 bits, and the report says
where in the image:

```
  FAIL clabel: 36 bits differ near x=80..160, y=120..180 (limit 10)
```

Measured on this suite, a tick moved by 1 px, a changed tick label or a one
letter typo in a title changes a word by 18 to 40 bits, while a tick moved by
0.25 px or less passes. What the fingerprint cannot tell is whether a change
is right, so after an intended change look at the new pictures (and run the
matplotlib comparisons below), then store the new fingerprints:

```bash
fpm test -- --update
```

CI also runs the gfortran and flang tests built with `-O3 -march=native`
(`pixi run test-gfortran-O3`, `test-flang-O3`), where fused multiply-add
changes the rounding, so a picture that depends on the last bits of a
floating point value fails there.

The fingerprints cover the raster output. SVG, PDF and EPS are written by the
same layout and drawing code but checked only by the comparisons below.

The SVG comparison is structural because a viewer, not fplotlib, decides what an
SVG looks like. PNG, PDF and EPS are compared as pixels, since there fplotlib
decides.

CI (Linux) has one job per compiler, each with only that compiler and fpm
installed, the compiler from `fortran-lang/setup-fortran`: gfortran, flang
and ifx are tested twice, the second time with `-O3 -march=native` so that
fused multiply-add is allowed and the pictures must not change; LFortran is
tested once. Each job also builds and runs the demo. ifx is given
`-fp-model precise`, because by default it reassociates, which turns a
linspace into a running sum and moves its endpoint and a contour grid's
exactly-zero column by a few ulps. A separate job, on pixi, compares the
flang build against matplotlib.

## Layout

```
src/           library modules
               fplotlib_state.f90   shared types and the figure state
               fplotlib_artist.f90  drawing primitives (strokes, fills, markers)
               fplotlib_draw.f90    layout, axes decoration, one renderer per plot type
               fplotlib_typeset.f90 TeX's paragraph and page layout, for documents
               fplotlib_doctree.f90 a document as a tree of blocks and inlines
               fplotlib_markdown.f90 Markdown into that tree
               fplotlib_docclass.f90 the tree set as LaTeX's article and book classes
               fplotlib.f90         the plotting API
examples/      demo.f90
tests/         Fortran test plots, fingerprints, matplotlib refs, compare scripts
```

## License

The code is MIT, in `LICENSE`.

The generated glyph data in `src/fplotlib_glyphs_data.f90` (outlines, metrics,
kerning and the math table) is OFL-1.1, derived from two fonts under the SIL
Open Font License 1.1: Lato, © tyPoland Łukasz Dziedzic with Reserved Font
Name "Lato" (`LICENSE_LATO`), and Lete Sans Math, © Chenjing Bu and Daniel
Flipo, built on Fira Math (© Xiangdong Zeng) and Lato (`LICENSE_LETE`). The
OFL is permissive: a program built with fplotlib ships the
OFL notice alongside the MIT one, and the plots fplotlib produces carry no
obligations. Because "Lato" is a Reserved Font Name, the fonts fplotlib
embeds in PDF and EPS files have names of their own: `FplotlibSans-Regular`,
`FplotlibSans-Bold`, `FplotlibSans-Italic` and `FplotlibMath`. `tools/gen_glyphs.py` regenerates the file from the pinned font
files. The hyphenation patterns in `src/fplotlib_hyph_data.f90` are generated by
`tools/gen_hyph.py` from `hyph-en-us.tex` of the hyph-utf8 project, © Gerard
D.C. Kuiken, whose licence permits copying and distribution with or without
modification provided the copyright notice is kept, as it is in the file.
The colormap tables in `src/fplotlib_cmap.f90` are sampled from matplotlib, which is
BSD-licensed, and the perceptual maps (viridis, magma, inferno, plasma) are
released by their authors under CC0.

## Jupyter (LFortran)

With LFortran as a Jupyter kernel, display the SVG interactively:

```fortran
use fplotlib
use lfortran_display
! ... plot / title / grid / legend ...
call display_data("image/svg+xml", render_svg())
```

`show()` always writes `fplotlib_show.svg` (works with Flang and LFortran offline).

## Fidelity to matplotlib

fplotlib is measured against matplotlib rather than described as similar to it:
every feature has a case in `tests/test_plots.f90` and a matplotlib reference
in `tests/gen_mpl_refs.py`, and the comparisons above put a number on the
difference. As of this writing, over 100 cases:

| format | cases | mean difference |
| --- | --- | --- |
| PNG | 126 | 1.31/255 |
| PDF | 125 | 0.93/255 |
| EPS | 126 | 2.28/255 |
| GIF | 20 frames | 0.39/255 |

The references are made with matplotlib set to the same Lato files fplotlib's
glyphs come from. What is left is mostly antialiasing along edges, and text:
fplotlib fills the outlines unhinted where matplotlib hints them through
FreeType, so a stem lands on the same pixel column as matplotlib's but not
always with the same coverage. The SVG is not matplotlib's SVG byte for byte,
and is not meant to be: both write every glyph as a path, but matplotlib
attaches its own ids and metadata.

Math is the exception: matplotlib's mathtext is its own approximation of TeX,
and fplotlib follows TeX itself, so the formulas are checked against XeTeX
instead. `tests/math_refs.txt` holds where XeTeX (Tectonic, with
unicode-math and the same font files) puts every glyph and rule of 92
formulas, and `fpm test` requires fplotlib to put each within 0.02 pt of it.
The automatic delimiters, which TeX does not have, are checked against
Typst's in `tests/delim_refs.txt`. Both files are regenerated with pixi,
nothing installed system-wide:

```
pixi exec --spec tectonic --spec pdfminer.six --spec fonttools \
    --spec python=3.12 -- python tools/gen_math_refs.py
pixi exec --spec typst --spec pdfminer.six --spec fonttools \
    --spec python=3.12 -- python tools/gen_delim_refs.py
```
