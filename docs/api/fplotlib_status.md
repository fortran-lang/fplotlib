# fplotlib_status module

fplotlib tells two kinds of failure apart.

A call that breaks a documented precondition is a bug in the calling code:
drawing before `open_canvas`, a nonfinite coordinate, an alpha outside
`[0,1]`, an unknown fill rule, `bytes` before `close_canvas`. Such a call
stops the program with a message that names the broken rule (see
[`fplotlib_render_checks`](fplotlib_render_checks.md)). It does not return
an error, because no caller could do anything with it but stop.

A failure that a correct program can still meet at run time, such as an
output file that cannot be written, is returned instead, through a required
`status_t` argument. `status%ok()` reports success, `status%code` says what
failed (`ERROR_IO`), and `status%message` is allocated on failure. Use the
call's other outputs only when `status%ok()` is true. There is no global
last-error state.

The `fplotlib` plotting procedures, `savefig` among them, stop with the
message when such a call fails.

```{f:module} fplotlib_status
```
