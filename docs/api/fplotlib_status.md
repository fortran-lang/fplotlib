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
encode), and `status%message` is allocated on failure. Use the
call's other outputs only when `status%ok()` is true. There is no global
last-error state.

`fplotlib_io:write_bytes` requires its `status`. `savefig` and
`save_animation` take an optional one: when it is present a file that
cannot be written is returned in it, and when it is absent the call stops
with the message, as the exception does in matplotlib, and exit code 2, so
that a script's caller can tell it from a broken precondition. `show` also
takes an optional `status`, and without one only reports the failure.
A PNG cropped with `bbox_inches="tight"` takes its size from what is
drawn, which the caller cannot know beforehand. One with more pixels than
the encoder can count is a failure at run time: `savefig` returns it as
`ERROR_SIZE`, or stops with exit code 2 without a `status`.
`fplotlib` re-exports `status_t`, `STATUS_OK` and `ERROR_IO`.

## Limits

Some arguments have upper bounds that matplotlib doesn't have. Past
them, the arrays, the canvas or the work would not fit, or a value could
no longer be written. Going past one is a broken precondition, and stops:

| What | Limit |
|---|---|
| A coordinate, size or width handed to a renderer | finite, at most `MAX_COORD` (1e15 points) |
| `figure`/`rc` `figsize`, `savefig` `pad_inches` | at most 1e9 inches |
| `figure` `num` | 1 to 100000 |
| Axes in one `subplot`/`subplots` grid | at most 10000 |
| A count: `bins`, `ncol`, `nbins`, `markevery`, `nrows`, ... | 1 to 1000000 |
| The side of a 2D grid: `hexbin` `gridsize`, `hist2d` `bins` | 1 to 1000 |
| `tick_format` `decimals` | 0 to 17 |
| `streamplot` `density` | at most 10 |
| `subplots_adjust` fractions, `colorbar` `fraction`, `pad`, `shrink` | at most 1000 in size |
| `colorbar` `aspect` | 0.001 to 1000 |
| Lengths in a dash pattern, `plot` `dashes` included | at most `MAX_DASH` (8) |
| A renderer pen with round or square dash ends | at most `MAX_PEN_PER_DASH` (100) times its dash pattern |
| A PNG figure, `figsize` times `dpi` | fewer than `huge(1)/8` pixels |

Data is never limited: a value of any size, or a missing one, is drawn or
left out as the view shows it. Line widths and dash lengths beyond 1e12
points are drawn as 1e12, which covers anything that can be seen just as
fully.

```{f:module} fplotlib_status
```
