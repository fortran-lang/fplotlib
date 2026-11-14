# fplotlib_resources module

`initialize_resources(status)` prepares the built-in fonts and English
hyphenation tables. Check its required status. Call it serially before starting
concurrent explicit-context work; after preparation, subsequent calls only read
initialization flags and the resource tables are immutable.

Ordinary serial text, math and rendering entrypoints prepare resources
automatically. Context-owned layout does not imply a blanket thread-safety
guarantee, and the implicit plotting/report facade is not reentrant.
This is a fixed built-in resource provider, not an external-font registry.

```{f:module} fplotlib_resources
```
