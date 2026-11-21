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
failed (`ERROR_IO`), and `status%message` is allocated on failure. Use the
call's other outputs only when `status%ok()` is true. There is no global
last-error state.

`fplotlib_io:write_bytes` requires its `status`. `savefig` and
`save_animation` take an optional one: when it is present a file that
cannot be written is returned in it, and when it is absent the call stops
with the message, as the exception does in matplotlib, and exit code 2, so
that a script's caller can tell it from a broken precondition. `show` also
takes an optional `status`, and without one only reports the failure.
`fplotlib` re-exports `status_t`, `STATUS_OK` and `ERROR_IO`.

```{f:module} fplotlib_status
```
