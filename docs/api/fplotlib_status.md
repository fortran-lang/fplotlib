# fplotlib_status module

fplotlib tells two kinds of failure apart.

A call that breaks a documented precondition is a bug in the calling code:
drawing before `open_canvas`, a nonfinite coordinate, an alpha outside
`[0,1]`, an unknown fill rule, `bytes` before `close_canvas`. Such a call
stops the program through `contract_error`, which writes `fplotlib: `
and a message naming the broken rule to standard error and exits with
code 1. It does not return an error, because no caller could do anything
with it but stop.

A failure that a correct program can still meet at run time, such as an
output file that cannot be written, is returned instead, through a
`status_t` argument. `status%ok()` reports success, `status%code` says what
failed (`ERROR_IO`, or `ERROR_SIZE` for a cropped PNG too large to
encode), and `status%message`, a string of `MESSAGE_LEN` (512)
characters, says what failed, blank when nothing did (read it with
`trim`). Use the call's other outputs only when `status%ok()` is true. There is no global
last-error state.

`fplotlib_io:write_bytes` requires its `status`. `savefig` and
`save_animation` take an optional one: when it is present a file that
cannot be written is returned in it, and when it is absent the call stops
with the message, as the exception does in matplotlib, and exit code 2, so
that a script's caller can tell it from a broken precondition. `show` also
takes an optional `status`, and without one only reports the failure.
A PNG cropped with `bbox_inches="tight"` takes its size from what is
drawn, which the caller cannot know beforehand. One with more than
`MAX_PNG_PIXELS` pixels is a failure at run time: `savefig` and
`render_png` return it as `ERROR_SIZE` (`render_png` with an empty
result), or stop with exit code 2 without a `status`. `render_svg`,
`render_pdf` and `render_eps` take the same optional `status`, which is
always ok. A whole figure too large for a PNG, which its size and dpi
tell beforehand, is a broken precondition; only a crop is returned.

`fplotlib` re-exports `status_t`, `STATUS_OK`, `ERROR_IO`, `ERROR_SIZE`
and `MESSAGE_LEN`, and the limits below that a plotting call can reach,
`MAX_DASH` and `MAX_PNG_PIXELS`; it defines `MAX_REEL_BYTES`. The
renderer's own limits, `MAX_COORD` and `MAX_PEN_PER_DASH`, are in
`fplotlib_render`. `set_status`, which records a failure, is for
fplotlib's own use, and `fplotlib` does not export it.

## Limits

Some arguments have upper bounds that matplotlib doesn't have. Past
them, the arrays, the canvas or the work would not fit, or a value could
no longer be written. Going past one is a broken precondition, and stops:

| What | Limit |
|---|---|
| A coordinate, size or width handed to a renderer | finite, at most `MAX_COORD` (1e15 points) |
| `figure`/`rc` `figsize`, `pad_inches` of `savefig` and `render_*` | at most 1e9 inches |
| `figure` `num` | 1 to 100000 |
| Axes in one `subplot`/`subplots` grid | at most 10000 |
| A count: `bins`, `ncol`, `nbins`, `markevery`, `nrows`, ... | 1 to 1000000 |
| The side of a 2D grid: `hexbin` `gridsize`, `hist2d` `bins` | 1 to 1000 |
| `tick_format` `decimals` | 0 to 17 |
| `streamplot` `density` | at most 10 |
| `subplots_adjust` fractions, `colorbar` `fraction`, `pad`, `shrink` | at most 1000 in size |
| `colorbar` `aspect` | 0.001 to 1000 |
| symlog `linthresh` (`set_xscale`, `set_yscale`, `imshow`, `pcolormesh`) | 1e-300 to 1e300 |
| symlog `linscale` | 1e-6 to 1e6 |
| Lengths in a dash pattern, `plot` `dashes` included | at most `MAX_DASH` (8) |
| A renderer pen with round or square dash ends, in every format | at most `MAX_PEN_PER_DASH` (100) times its dash pattern |
| A PNG figure, `figsize` times `dpi`, rounded to whole pixels | at most `MAX_PNG_PIXELS` (1e8) pixels, some 4 GB as rasterized |
| The frames of one animation, each counted as it encodes at worst, `h(3w + 1)·9/8 + 1024` bytes for `w` by `h` pixels | at most `MAX_REEL_BYTES` (1e9) bytes |

Data is never limited: a value of any size, or a missing one, never
stops a plot, and is drawn or left out as the view shows it. Line widths
and dash lengths beyond 1e12 points are drawn as 1e12, which covers
anything that can be seen just as fully. Axis limits, which may span the
whole range of a double, stop at the largest double. A shape that reaches
so far past the view that its own place on the canvas is past the largest
double, such as a circle of radius 1e308 about a point in a unit view,
cannot be placed, and is left out as missing data is. A log axis reaches
down to the least normal double, about 2.2e-308: a value below it,
subnormal, zero or negative, is drawn there. A log or symlog axis tells
values apart only as finely as doubles tell apart their places on it,
about `epsilon` times the transformed value rather than times the value
itself: data spread over a few such roundings is widened as a constant
is, and data spread over a few dozen is drawn as finely as those
roundings allow, as in matplotlib.

The PNG backend draws one thing approximately: a dash pattern shorter
than half a pixel, whose dashes cannot be told apart, is drawn as a solid
line at the share of the line the pattern would cover (more where round
or square ends close the gaps). Walking such a pattern dash by dash could
take without end. In a frame (see [`fplotlib_render`](fplotlib_render.md))
the same holds segment by segment, for a segment whose dashes cross the
canvas as stripes less than half a pixel apart. A frame that squeezes
across a line can make them so even where each dash is long along it, as
the stripes then lie almost along the line. Everything else it draws as the full walk of every dash would, up to the
rounding of where along a very long segment the pattern stands, which the
walk works out by adding dash after dash and the shortcuts by division. In
a PNG, a frame whose matrix, taken together with those of the frames
around it, stretches or moves by more than 1e100 places nothing it holds,
nor do the frames inside it, as a shape whose place on the canvas is past
the largest double is left out.

```{f:module} fplotlib_status
```
