# fplotlib_status module

Every recoverable core failure has a required `status_t` output argument.
Use `status=error` when optional arguments are omitted. `error%ok()` reports
success; `error%code` distinguishes argument, state, unsupported-operation, I/O,
layout and resource errors. `error%message` is allocated on failure.

Check or propagate the result before using other outputs or making another
fallible call. The next call replaces the status, including clearing an earlier
diagnostic. No global or context-stored last-error state is used. Only the
high-level `fplotlib` facade aborts on these failures.

Drawing and layout are not transactions: discard a partial drawing target or
reset/rebuild a failed primitive layout. Finished input frames remain valid.
This contract covers recoverable library errors, not recovery from Fortran
runtime allocation failure.

```{f:module} fplotlib_status
```
