"""Compare fplotlib's documents with LaTeX's and Typst's.

Each gallery example of docs/gallery/typesetting is a Markdown document
in a Fortran program. This script takes the document out of the program
and sets it three ways, all with the same Lato and Lete Sans Math files,
paper, margins and sizes:

  * by fplotlib, which the program is run for (with fpm, writing a PDF);
  * by LaTeX: the MyST subset is rewritten to the divs and TeX Pandoc
    already maps (tools/compare_docs.lua), and Tectonic (XeTeX) sets it;
  * by Typst: the same rewrite, then Pandoc turns it into Typst markup
    and typst sets it.

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
          "a6": (297.6378, 419.5276), "b5": (498.8976, 708.6614),
          "letter": (612.0, 792.0), "us-letter": (612.0, 792.0),
          "legal": (612.0, 1008.0)}


def fortran_document(path):
    """The Markdown in the typeset([...]) call of a gallery program."""
    src = path.read_text(encoding="utf-8")
    m = re.search(r"call typeset\(\[character\(len=\d+\) :: &\n(.*?)\],\s*&?\s*\n?\s*\"([^\"]+)\"",
                  src, re.S)
    if not m:
        raise SystemExit(f"{path}: no typeset([...]) call found")
    lines = []
    for line in m.group(1).split("\n"):
        line = line.strip()
        if not line:
            continue
        lit = re.match(r'"((?:[^"]|"")*)"', line)
        if lit:
            lines.append(lit.group(1).replace('""', '"').rstrip())
    return "\n".join(lines) + "\n", m.group(2)


def front_matter(md):
    """Our front matter as a dict, and the body after it, as fplotlib reads
    them: authors one to a line, from a YAML list or a repeated key."""
    meta, body = {}, md
    if md.startswith("---\n") and "\n---\n" in md[3:]:
        end = md.index("\n---\n", 3)
        key = None
        for line in md[4:end].split("\n"):
            if line.startswith(" ") and key:
                item = line.strip()
                if item.startswith("- "):
                    item = item[2:].strip().strip("'\"")
                    meta[key] = meta[key] + "\n" + item if meta[key] else item
                else:
                    meta[key] = (meta[key] + " " + item).strip()
                continue
            if ":" in line:
                key, val = line.split(":", 1)
                key = key.strip().lower()
                if key == "authors":
                    key = "author"
                val = val.strip()
                if val.startswith("[") and val.endswith("]"):
                    val = "\n".join(v.strip().strip("'\"") for v in
                                    re.findall(r'"[^"]*"|\'[^\']*\'|[^,]+', val[1:-1]))
                val = val.strip("'\"")
                meta[key] = meta[key] + "\n" + val if key == "author" and key in meta else val
        body = md[end + 5:]
    return meta, body


def length(v, size):
    m = re.match(r"^\s*([\d.]+)\s*([a-z]*)\s*$", v)
    n, u = float(m.group(1)), m.group(2)
    return {"pc": 12 * n, "in": 72 * n, "cm": 72 / 2.54 * n, "mm": 72 / 25.4 * n,
            "em": size * n, "ex": 0.507 * size * n}.get(u, n)


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
    s["book"] = (meta.get("class", "article") == "book" or
                 meta.get("chapters", "").lower() in ("true", "yes", "1"))
    s["align"] = meta.get("align", "justify")
    s["color"] = meta.get("color")
    s["pagecolor"] = meta.get("pagecolor")
    for k in ("title", "author", "date", "abstract"):
        s[k] = meta.get(k)
    return s


_SIZES = {"tiny", "scriptsize", "footnotesize", "small", "normalsize", "large",
          "Large", "LARGE", "huge", "Huge"}
_DIRECTIVES = {"div", "sender", "recipient", "closing", "pagebreak"}


def _opens(line):
    rest = line.strip()[3:]
    return any(c != ":" for c in rest)


def _parse_open(line):
    """Directive name, and a Pandoc attribute string when the opener is one."""
    rest = line.strip().lstrip(":").strip()
    if rest.startswith("{") and "}" in rest:
        inner = rest[1:rest.index("}")].strip()
        if inner.lower() in _DIRECTIVES:
            return inner.lower(), ""
        return "div", "{" + inner + "}" if inner else ""
    if rest.lower() in _DIRECTIVES:
        return rest.lower(), ""
    return "div", rest


def _take(lines, i):
    """lines[i] opens a directive. Return name, options, inline attr, content, next index."""
    name, inline = _parse_open(lines[i])
    depth, j, raw = 1, i + 1, []
    while j < len(lines):
        t = lines[j].strip()
        if t.startswith(":::"):
            if _opens(t):
                depth += 1
            else:
                depth -= 1
                if depth == 0:
                    j += 1
                    break
        raw.append(lines[j])
        j += 1
    opts, k = {}, 0
    while k < len(raw):
        m = re.fullmatch(r":([A-Za-z0-9_-]+):\s*(.*)", raw[k].strip())
        if not m:
            break
        opts[m.group(1).lower()] = m.group(2).strip()
        k += 1
    return name, opts, inline, raw[k:], j


def _paragraphs(lines):
    paras, cur = [], []
    for line in lines:
        if line.strip() == "":
            if cur:
                paras.append(cur)
                cur = []
        else:
            cur.append(line)
    if cur:
        paras.append(cur)
    return paras


def _pandoc_div(opts, inline):
    """A Pandoc fenced-div opener argument, or '' when the div carries nothing."""
    if inline and not opts:
        return inline
    classes, attrs = [], []
    for word in opts.get("class", "").split():
        classes.append(word[1:] if word.startswith(".") else word)
    size = opts.get("size") or opts.get("font-size") or opts.get("fontsize")
    if size:
        if size in _SIZES:
            classes.append(size)
        else:
            attrs.append("size=" + size)
    if opts.get("weight", "").lower() == "bold":
        classes.append("bold")
    if opts.get("italic", "").lower() in ("true", "yes", "1"):
        classes.append("italic")
    align = {"centre": "center"}.get(opts.get("align", "").lower(),
                                      opts.get("align", "").lower())
    if align in ("center", "right", "left", "justify"):
        classes.append(align)
    color = opts.get("color") or opts.get("colour")
    if color:
        attrs.append("color=" + color)
    inside = " ".join(["." + c for c in classes] + attrs)
    if inside:
        return "{" + inside + "}"
    return ""


def _emit(name, opts, inline, content, sig):
    content = _transform(content, sig)
    if name == "pagebreak":
        return ["\\newpage"]
    if name == "sender":
        return ["::: {.right}"] + content + [":::"]
    if name == "recipient":
        while content and content[-1].strip() == "":
            content.pop()
        return content + ["", "\\bigskip"]
    if name == "closing":
        out = ["\\bigskip", ""]
        for n, para in enumerate(_paragraphs(content)):
            if n:
                out.extend(["", "\\vspace{%s}" % sig, ""])
            out.extend(para)
        return out
    spec = _pandoc_div(opts, inline)
    if not spec:
        return content
    return ["::: " + spec] + content + [":::"]


def _label_displays(line, inside):
    """Each $$ (label) of line that closes a display, as \\label{label}$$;
    inside tells whether a display is open where the line starts. Returns
    the line and whether a display is open where it ends."""
    out, pos = [], 0
    for m in re.finditer(r"\$\$", line):
        out.append(line[pos:m.start()] + "$$")
        pos = m.end()
        if inside:
            lab = re.match(r"\s*\(([^)\s]+)\)", line[pos:])
            if lab:
                out[-1] = out[-1][:-2] + "\\label{%s}$$" % lab.group(1)
                pos += lab.end()
        inside = not inside
    out.append(line[pos:])
    return "".join(out), inside


def _role(m):
    """A MyST role as Pandoc citations and TeX: {numref} with "Section",
    {ref} the heading's title, and a role's own text, "text <target>"."""
    role, arg = m.group(1), m.group(2).strip()
    own = re.fullmatch(r"(.+?)\s*<([^>]+)>", arg)
    if own:
        text, target = own.group(1), own.group(2).strip()
        if role == "numref":
            return text.replace("%s", "@" + target).replace("{number}", "@" + target)
        return text
    if role == "ref":
        return "\\nameref{%s}" % arg
    if role == "numref" and not arg.startswith("eq:"):
        return "Section @" + arg
    return "@" + arg


def _transform(lines, sig):
    """MyST directives and heading targets, as the Pandoc filter reads them."""
    out, i, inside, code = [], 0, False, False
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            code = not code
        if code or stripped.startswith("```") or stripped.startswith("~~~"):
            out.append(lines[i])
            i += 1
            continue
        label = re.fullmatch(r"\(([^)\s]+)\)=", stripped)
        if label and i + 1 < len(lines) and re.match(r"#{1,6} ", lines[i + 1].strip()):
            out.append(lines[i + 1].rstrip() + " {#" + label.group(1) + "}")
            i += 2
            continue
        if stripped.startswith(":::") and _opens(stripped):
            name, opts, inline, content, i = _take(lines, i)
            out.extend(_emit(name, opts, inline, content, sig))
            continue
        line, inside = _label_displays(lines[i], inside)
        out.append(re.sub(r"\{(eq|ref|numref)\}`([^`]+)`", _role, line))
        i += 1
    return out


def for_pandoc(body, meta):
    """The MyST subset rewritten to the divs and TeX compare_docs.lua maps.

    fplotlib sets the directives itself. Pandoc sees the older spelling:
    an aligning div, \\bigskip, \\vspace and \\vspace*{\\fill}.
    """
    sig = meta.get("signature-skip") or meta.get("signature_skip") or "1.2cm"
    valign = (meta.get("valign") or meta.get("vertical-align") or "").lower()
    text = "\n".join(_transform(body.split("\n"), sig))
    if valign in ("center", "centre"):
        if text and not text.endswith("\n"):
            text += "\n"
        text = "\\vspace*{\\fill}\n\n" + text + "\\vspace*{\\fill}\n"
    return text


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
    ap.add_argument("examples", nargs="*", help="gallery programs (default: all)")
    args = ap.parse_args()
    examples = [Path(e).resolve() for e in args.examples] or sorted(GALLERY.glob("plot_*.f90"))
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
            body = for_pandoc(body, meta)
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
