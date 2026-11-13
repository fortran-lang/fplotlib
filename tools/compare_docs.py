"""Compare fplotlib's documents with LaTeX's and Typst's.

The literal markdown([...]) examples of docs/gallery/typesetting contain a
Markdown document in a Fortran program. This script takes that document out
and sets it three ways, all with the same Lato and Lete Sans Math files,
paper, margins and sizes:

  * by fplotlib, which the program is run for (with fpm, writing a PDF);
  * by LaTeX: Pandoc turns it into LaTeX (with tools/compare_docs.lua for
    fplotlib's extensions) and Tectonic (XeTeX) sets it;
  * by Typst: Pandoc turns it into Typst markup and typst sets it.

The pages are rasterized and put side by side, fplotlib's on the left, in
one PNG per document:

    pixi exec --spec pandoc --spec tectonic --spec typst --spec pymupdf \\
        --spec pillow --spec fonttools --spec numpy --spec python=3.12 -- \\
        python tools/compare_docs.py --fonts DIR --out DIR

LaTeX's article and book classes give the spacing fplotlib follows, so the
LaTeX column is the reference; Typst lays out pages by its own rules, and
its column shows how another modern system sets the same text. Lato's
ligatures are switched off in both, since fplotlib has none.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import fitz
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_glyphs import font_file  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GALLERY = ROOT / "docs" / "gallery" / "typesetting"
FILTER = Path(__file__).resolve().parent / "compare_docs.lua"

PAPERS = {"a4": (595.2756, 841.8898), "a5": (419.5276, 595.2756),
          "a6": (297.6378, 419.5276), "letter": (612.0, 792.0),
          "us-letter": (612.0, 792.0), "legal": (612.0, 1008.0)}


def literal_document(src):
    """Match one complete literal document, not a composed report."""
    calls = re.findall(r"^\s*call\s+(markdown|include_figure|include_table)\s*\(",
                       src, re.M | re.I)
    if [name.lower() for name in calls] != ["markdown"]:
        return None
    m = re.search(r"^\s*call\s+markdown\(\[character\(len=\d+\)\s*::\s*&\n(.*?)\]\s*\)\s*$",
                  src, re.S | re.M | re.I)
    if m is None:
        return None
    out = re.search(r'^\s*call\s+save\("([^"]+)"\)', src[m.end():], re.M | re.I)
    if out is None:
        return None
    return m, out


def fortran_document(path):
    """The Markdown and output filename of a literal gallery document."""
    parsed = literal_document(path.read_text(encoding="utf-8"))
    if parsed is None:
        raise SystemExit(f"{path}: expected one literal markdown([...]) call followed by save(...), "
                         "without included figures or tables")
    m, out = parsed
    lines = []
    for line in m.group(1).split("\n"):
        line = line.strip()
        if not line:
            continue
        lit = re.match(r'"((?:[^"]|"")*)"', line)
        if lit:
            lines.append(lit.group(1).replace('""', '"'))
    return "\n".join(lines) + "\n", out.group(1)


def front_matter(md):
    """Our front matter as a dict, and the body after it."""
    meta, body = {}, md
    if md.startswith("---\n"):
        end = md.index("\n---\n", 4)
        key = None
        for line in md[4:end].split("\n"):
            if line.startswith(" ") and key:
                meta[key] += " " + line.strip()
                continue
            if ":" in line:
                key, val = line.split(":", 1)
                key = key.strip().lower()
                val = val.strip().strip("'\"")
                meta[key] = meta[key] + "\n" + val if key == "author" and key in meta else val
        body = md[end + 5:]
    return meta, body


def length(v, size):
    m = re.match(r"^\s*([\d.]+)\s*([a-z]*)\s*$", v)
    n, u = float(m.group(1)), m.group(2)
    return {"in": 72 * n, "cm": 72 / 2.54 * n, "mm": 72 / 25.4 * n,
            "em": size * n}.get(u, n)


def settings(meta):
    """The page and type settings both LaTeX and Typst are given."""
    s = {}
    s["size"] = length(meta.get("fontsize", "10pt"), 10)
    paper = meta.get("paper", "a4").lower()
    if paper in PAPERS:
        s["w"], s["h"] = PAPERS[paper]
    else:
        w, h = paper.split("x")
        s["w"], s["h"] = length(w, s["size"]), length(h, s["size"])
    m = length(meta.get("margin", "72"), s["size"])
    for side in ("left", "right", "top", "bottom"):
        s[side] = length(meta["margin-" + side], s["size"]) if "margin-" + side in meta else m
    s["parskip"] = length(meta["parskip"], s["size"]) if "parskip" in meta else None
    s["indent"] = s["parskip"] is None and meta.get("indent", "true") != "false"
    s["numbers"] = meta.get("pagenumbers", "true") != "false"
    s["sections"] = meta.get("numbersections", "false") == "true"
    s["book"] = meta.get("class", "article") == "book"
    s["align"] = meta.get("align", "justify")
    s["color"] = meta.get("color")
    s["pagecolor"] = meta.get("pagecolor")
    for k in ("title", "author", "date", "abstract"):
        s[k] = meta.get(k)
    return s


def latex_source(md_body, s, fonts):
    meta = ["---"]
    for k in ("title", "date", "abstract"):
        if s[k]:
            meta.append(f'{k}: "{s[k]}"')
    if s["author"]:
        meta.append("author:")
        for a in s["author"].split("\n"):
            meta.append(f'  - "{a}"')
    meta.append(f"documentclass: {'book' if s['book'] else 'article'}")
    meta.append(f"fontsize: {min(12, max(10, round(s['size'])))}pt")
    if s["book"]:
        meta.append("classoption: [openany]")
    meta.append(f"basesize: {s['size']}")
    meta.append("geometry:")
    meta.append(f"  - paperwidth={s['w']}bp")
    meta.append(f"  - paperheight={s['h']}bp")
    for side in ("left", "right", "top", "bottom"):
        meta.append(f"  - {side}={s[side]}bp")
    if s["indent"]:
        meta.append("indent: true")
    if s["sections"]:
        meta.append("numbersections: true")
    if not s["numbers"]:
        meta.append("pagestyle: empty")
    hdr = [
        r"\setmainfont{Lato}[Path=%s/, Extension=.ttf, UprightFont=*-Regular, "
        r"ItalicFont=*-Italic, BoldFont=*-Bold, BoldItalicFont=*-Bold, "
        r"Ligatures={NoCommon}, Contextuals={NoAlternate}]" % fonts,
        r"\setmathfont{LeteSansMath.otf}[Path=%s/, Scale=1]" % fonts,
        # The class's sizes, set in bp, as fplotlib's points are.
        r"\makeatletter\renewcommand\normalsize{\@setfontsize\normalsize{%gbp}{%gbp}"
        r"\abovedisplayskip %gbp \@plus%gbp \@minus%gbp \abovedisplayshortskip \z@ \@plus%gbp"
        r"\belowdisplayshortskip %gbp \@plus%gbp \@minus%gbp \belowdisplayskip \abovedisplayskip}"
        r"\makeatother\normalsize"
        % (s["size"], 1.2 * s["size"], s["size"], 0.2 * s["size"], 0.5 * s["size"],
           0.3 * s["size"], 0.6 * s["size"], 0.3 * s["size"], 0.3 * s["size"]),
        r"\usepackage{xcolor}",
    ]
    if s["parskip"] is not None:
        hdr.append(r"\setlength{\parskip}{%gbp plus 1bp}\setlength{\parindent}{0pt}"
                   % s["parskip"])
    if s["pagecolor"]:
        hdr.append(r"\pagecolor[HTML]{%s}" % s["pagecolor"].lstrip("#").upper())
    if s["color"]:
        hdr.append(r"\AtBeginDocument{\color[HTML]{%s}}" % s["color"].lstrip("#").upper())
    if s["align"] == "center":
        hdr.append(r"\AtBeginDocument{\centering}")
    meta.append("header-includes:")
    for h in hdr:
        meta.append("  - |\n    ```{=latex}\n    " + h + "\n    ```")
    meta.append("---")
    return "\n".join(meta) + "\n" + md_body


TYPST = r"""
#set page(width: $w$pt, height: $h$pt,
  margin: (left: $left$pt, right: $right$pt, top: $top$pt, bottom: $bottom$pt),
  numbering: $numbering$, fill: $fill$)
#set text(font: "Lato", size: $size$pt, ligatures: false, fill: $color$, lang: "en")
#set par(justify: $justify$, first-line-indent: $indent$, leading: 0.48em,
  spacing: $spacing$)
#show math.equation: set text(font: "Lete Sans Math")
#set math.equation(supplement: none)
#set heading(numbering: $headnum$, supplement: none)
#show heading.where(level: 1): set text(size: $h1$pt)
#show heading.where(level: 2): set text(size: $h2$pt)
#show heading: it => block(above: 1.4em, below: 1em, it)
$align$
$titleblock$
$body$
"""


def typst_template(s):
    size = s["size"]
    t = TYPST
    if s["book"]:
        t = t.replace("$h1$pt)", "$h1$pt)\n#show heading.where(level: 1): it => {"
                      " v(50pt);"
                      " text(size: $huge$pt, weight: \"bold\")[Chapter #counter(heading).display()];"
                      " v(20pt); text(size: $Huge$pt, weight: \"bold\", it.body); v(30pt) }")
    vals = {
        "w": s["w"], "h": s["h"], "left": s["left"], "right": s["right"],
        "top": s["top"], "bottom": s["bottom"], "size": size,
        "numbering": '"1"' if s["numbers"] else "none",
        "fill": f'rgb("{s["pagecolor"]}")' if s["pagecolor"] else "white",
        "color": f'rgb("{s["color"]}")' if s["color"] else "black",
        "justify": "true" if s["align"] == "justify" else "false",
        "indent": f"{1.5 * size}pt" if s["indent"] else "0pt",
        "spacing": f"{(s['parskip'] or 0) / size + 0.48:.3f}em",
        "headnum": '"1.1"' if s["sections"] else "none",
        "h1": 2.488 * size if s["book"] else 1.44 * size,
        "h2": 1.44 * size if s["book"] else 1.2 * size,
        "huge": 2.074 * size, "Huge": 2.488 * size,
        "align": "#set align(center)" if s["align"] == "center" else "",
    }
    tb = []
    if s["title"]:
        tb.append(f'#align(center)[#v(2em)#text(size: {1.728 * size}pt)[{s["title"]}]')
        if s["author"]:
            for a in s["author"].split("\n"):
                tb.append(f'#v(1em)#text(size: {1.2 * size}pt)[{a}]')
        if s["date"]:
            tb.append(f'#v(0.6em)#text(size: {1.2 * size}pt)[{s["date"]}]')
        tb.append("]#v(2em)")
        if s["abstract"]:
            tb.append(f'#align(center)[#text(size: {0.9 * size}pt, weight: "bold")[Abstract]]')
            tb.append(f'#pad(x: 2.5em)[#text(size: {0.9 * size}pt)[{s["abstract"]}]]')
    vals["titleblock"] = "\n".join(tb)
    for k, v in vals.items():
        t = t.replace("$" + k + "$", f"{v:g}" if isinstance(v, float) else str(v))
    return t


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise SystemExit(f"{' '.join(map(str, cmd))} failed:\n{r.stdout}\n{r.stderr}")
    return r


def fplotlib_pdfs(examples, work):
    """Run the gallery programs, each writing its document as a PDF."""
    proj = work / "fplotlib"
    (proj / "app").mkdir(parents=True)
    rel = os.path.relpath(ROOT, proj.resolve())
    (proj / "fpm.toml").write_text(
        f'name = "compare"\n[build]\nauto-executables = true\n'
        f'[dependencies]\nfplotlib = {{ path = "{rel}" }}\n')
    # fpm looks for the programs in app/ only when app/main.f90 is there.
    (proj / "app" / "main.f90").write_text("program compare\nend program compare\n")
    for ex in examples:
        src = ex.read_text(encoding="utf-8")
        _, out = fortran_document(ex)
        src = src.replace(f'"{out}"', f'"{ex.stem}.pdf"')
        (proj / "app" / ex.name).write_text(src, encoding="utf-8")
    fc = os.environ.get("FPM_FC", "gfortran")
    for ex in examples:
        run(["fpm", "run", ex.stem, "--compiler", fc], cwd=proj)
    return {ex.stem: proj / f"{ex.stem}.pdf" for ex in examples}


def pages(pdf, dpi):
    doc = fitz.open(pdf)
    return [Image.frombytes("RGB", (p.width, p.height), p.samples)
            for p in (page.get_pixmap(dpi=dpi) for page in doc)]


def montage(columns, labels, path):
    """Pages side by side, a column per system, a row per page."""
    pad, head = 24, 40
    n = max(len(c) for c in columns)
    w = max(p.width for c in columns for p in c)
    h = max(p.height for c in columns for p in c)
    img = Image.new("RGB", (len(columns) * (w + pad) + pad, head + n * (h + pad) + pad),
                    (200, 200, 200))
    d = ImageDraw.Draw(img)
    for i, (col, label) in enumerate(zip(columns, labels)):
        x = pad + i * (w + pad)
        d.text((x, 12), label, fill=(0, 0, 0))
        for j, p in enumerate(col):
            img.paste(p, (x, head + j * (h + pad)))
    img.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fonts", help="the directory holding the pinned font files")
    ap.add_argument("--out", default="compare_docs", help="where the PNGs go")
    ap.add_argument("--dpi", type=int, default=80)
    ap.add_argument("examples", nargs="*", help="gallery programs (default: literal Markdown examples)")
    args = ap.parse_args()
    if args.examples:
        examples = [Path(e).resolve() for e in args.examples]
    else:
        examples = []
        for example in sorted(GALLERY.glob("plot_*.f90")):
            if literal_document(example.read_text(encoding="utf-8")) is not None:
                examples.append(example)
            else:
                print(f"skipping {example.name}: programmatic composition, not a literal Markdown document")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        fonts = work / "fonts"
        fonts.mkdir()
        for f in ("Lato-Regular.ttf", "Lato-Italic.ttf", "Lato-Bold.ttf", "LeteSansMath.otf"):
            shutil.copy(font_file(f, args.fonts), fonts / f)
        ours = fplotlib_pdfs(examples, work)
        for ex in examples:
            md, _ = fortran_document(ex)
            meta, body = front_matter(md)
            s = settings(meta)
            name = ex.stem
            (work / f"{name}.md").write_text(latex_source(body, s, fonts), encoding="utf-8")
            run(["pandoc", f"{name}.md", "-f", "markdown", "-t", "latex", "-s",
                 "--lua-filter", str(FILTER), "-o", f"{name}.tex"], cwd=work)
            run(["tectonic", "--chatter", "minimal", f"{name}.tex"], cwd=work)
            (work / f"{name}.typ.md").write_text(
                "---\nbasesize: %g\n---\n" % s["size"] + body, encoding="utf-8")
            (work / f"{name}.template.typ").write_text(typst_template(s), encoding="utf-8")
            run(["pandoc", f"{name}.typ.md", "-f", "markdown", "-t", "typst",
                 "--template", f"{name}.template.typ", "--lua-filter", str(FILTER),
                 "-o", f"{name}.typ"], cwd=work)
            run(["typst", "compile", "--font-path", str(fonts), f"{name}.typ",
                 f"{name}.typst.pdf"], cwd=work)
            montage([pages(ours[name], args.dpi), pages(work / f"{name}.pdf", args.dpi),
                     pages(work / f"{name}.typst.pdf", args.dpi)],
                    ["fplotlib", "LaTeX (Tectonic)", "Typst"], out / f"{name}.png")
            print(f"wrote {out / name}.png")


if __name__ == "__main__":
    main()
