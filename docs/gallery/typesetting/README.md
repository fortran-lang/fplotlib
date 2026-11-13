# Documents

Documents written in Markdown, with TeX mathematics between dollar signs,
and set by fplotlib itself with TeX's algorithms: paragraphs are broken
into lines by Knuth and Plass's method and hyphenated with TeX's patterns,
pages are cut by TeX's page builder, and the spacing is LaTeX's. Each
basic example is one call, `typeset(lines, "file.svg")`; a PDF holds every
page, the other formats one file per page. The HPC report uses the procedural
`markdown`, `include_figure`, `include_table` and `save` API. The advanced
composition example separately demonstrates explicit contexts and owned
frames, including a typeset paragraph and equation inside a vector plot.
