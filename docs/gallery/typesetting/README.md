# Documents

Documents written in Markdown, with TeX mathematics between dollar signs,
and set by fplotlib itself with TeX's algorithms: paragraphs are broken
into lines by Knuth and Plass's method and hyphenated with TeX's patterns,
pages are cut by TeX's page builder, and the spacing is LaTeX's. Each
basic example is one call, `typeset(lines, "file.svg")`; a PDF holds every
page, the other formats one file per page. The HPC report also shows
programmatic composition: a vector plot and its typeset annotation are
owned frames inserted into a Markdown document without intermediate files.
