"""Compare fplotlib's documents with LaTeX's and Typst's.

The literal markdown([...]) examples of docs/gallery/typesetting contain a
Markdown document in a Fortran program. This script takes that document out
and sets it three ways, all with the same Lato and Lete Sans Math files,
paper, margins and sizes:

  * by fplotlib, which the program is run for (with fpm, writing a PDF);
  * by LaTeX and Typst: the pinned upstream MyST parser supplies the AST;
    Pandoc is only an output writer, followed by Tectonic or Typst.

The pages are rasterized and put side by side, fplotlib's on the left, in
one PNG per document:

    pixi exec --spec pandoc --spec tectonic --spec typst --spec pymupdf \\
        --spec pillow --spec fonttools --spec numpy --spec pyyaml -- \\
        python tools/compare_docs.py --fonts DIR --out DIR --myst-parser DIR

The last directory is an existing myst-parser@1.7.5 package installation,
also used by tools/gen_myst_refs.mjs. Node must be available on PATH.

LaTeX's article and book classes give the spacing fplotlib follows, so the
LaTeX column is the reference; Typst lays out pages by its own rules, and
its column shows how another modern system sets the same text. Lato's
ligatures are switched off in both, since fplotlib has none.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import unquote

import fitz
import yaml
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_glyphs import font_file  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GALLERY = ROOT / "docs" / "gallery" / "typesetting"
ORACLE = Path(__file__).resolve().parent / "gen_myst_refs.mjs"

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


def length(v, size):
    m = re.fullmatch(r"\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*([a-z]*)\s*", str(v))
    if m is None:
        raise ValueError(f"Invalid template length: {v}")
    n, u = float(m.group(1)), m.group(2)
    return {"in": 72 * n, "cm": 72 / 2.54 * n, "mm": 72 / 25.4 * n,
            "em": size * n}.get(u, n)


def settings(meta):
    """Declared native template defaults, not extra Markdown syntax."""
    export = meta.get("exports", [{}])[0]
    template = export.get("template", "article")
    defaults = {
        "article": {},
        "book": {"paper": "a5", "margin": "1.8cm", "margin-top": "2.2cm"},
        "letter": {"paper": "letter", "fontsize": "11pt", "margin": "1.1in",
                   "parskip": "6pt", "pagenumbers": False},
        "invitation": {"paper": "5in x 7in", "fontsize": "12pt", "margin": "0.55in",
                       "parskip": "8pt", "align": "center", "pagenumbers": False,
                       "color": "#3b2b23", "pagecolor": "#fbf3e4"},
    }
    options = defaults[template] | export
    s = {"template": template}
    s["size"] = length(options.get("fontsize", "10pt"), 10)
    paper = options.get("paper", "a4")
    if paper in PAPERS:
        s["w"], s["h"] = PAPERS[paper]
    else:
        w, h = paper.split("x")
        s["w"], s["h"] = length(w, s["size"]), length(h, s["size"])
    m = length(options.get("margin", "72"), s["size"])
    for side in ("left", "right", "top", "bottom"):
        s[side] = length(options["margin-" + side], s["size"]) if "margin-" + side in options else m
    s["parskip"] = length(options["parskip"], s["size"]) if "parskip" in options else None
    s["indent"] = options.get("indent", s["parskip"] is None)
    s["numbers"] = options.get("pagenumbers", True)
    numbering = meta.get("numbering", {})
    s["sections"] = numbering if isinstance(numbering, bool) else numbering.get("headings", False)
    s["equations"] = numbering if isinstance(numbering, bool) else numbering.get("equations", True)
    s["book"] = template == "book"
    s["align"] = options.get("align", "justify")
    s["color"] = options.get("color")
    s["pagecolor"] = options.get("pagecolor")
    for k in ("title", "subtitle", "date", "abstract"):
        s[k] = str(meta[k]) if meta.get(k) is not None else None
    authors = meta.get("authors", meta.get("author", []))
    if not isinstance(authors, list):
        authors = [authors]
    s["author"] = "\n".join(a["name"] if isinstance(a, dict) else str(a) for a in authors)
    return s


def pandoc_node(kind, content=None):
    return {"t": kind, **({"c": content} if content is not None else {})}


def text_inlines(text):
    return [pandoc_node("Space") if part.isspace() else pandoc_node("Str", part)
            for part in re.findall(r"\s+|\S+", text)]


def identifier(value):
    return re.sub(r"""['‘’"“”]""", "", re.sub(r"[\t\n\r ]+", " ", value)).strip().lower()


class MystDocument:
    """Convert canonical MyST nodes into Pandoc's writer-only interchange."""

    def __init__(self, source, parser):
        self.parser = parser
        self.cache = {}
        root = self.parse(source)
        self.meta = {}
        if root and root[0]["type"] == "code" and root[0].get("lang") == "yaml":
            self.meta = yaml.safe_load(root.pop(0)["value"]) or {}
        self.settings = settings(self.meta)
        self.parts = {}
        self.body = []
        for node in root:
            part = json.loads(node.get("meta", "{}")).get("part") if node["type"] == "block" else None
            if part:
                self.parts.setdefault(part, []).extend(node["children"])
            else:
                self.body.append(node)
        for name, value in self.meta.get("parts", {}).items():
            self.parts[name] = self.parse(value)
        if self.meta.get("abstract"):
            self.parts["abstract"] = self.parse(str(self.meta["abstract"]))
        self.targets = {}
        self.sec = [0] * 6
        self.eqno = 0
        order = {
            "article": ("abstract",), "book": ("abstract",),
            "letter": ("sender", "recipient", "opening"), "invitation": ("intro", "ornament"),
        }
        for name in order[self.settings["template"]]:
            self.collect(self.parts.get(name, []))
        self.collect(self.body)
        for name in ("closing", "signature", "reply"):
            self.collect(self.parts.get(name, []))

    def parse(self, source):
        if source not in self.cache:
            self.cache[source] = json.loads(run(
                ["node", str(ORACLE), str(self.parser), "--parse"], input=source).stdout)["children"]
        return self.cache[source]

    def collect(self, nodes):
        pending = ""
        for node in nodes:
            kind = node["type"]
            if kind == "mystTarget":
                pending = identifier(node["label"])
                continue
            if node.get("_collected"):
                continue
            node["_collected"] = True
            if pending:
                node["identifier"] = pending
                pending = ""
            if kind == "mystDirective":
                if node.get("identifier") and node.get("children"):
                    node["children"][0]["identifier"] = node["identifier"]
            if kind == "heading":
                depth = node["depth"]
                self.sec[depth - 1] += 1
                self.sec[depth:] = [0] * (6 - depth)
                if self.settings["book"] and depth == 1:
                    self.eqno = 0
                node["_number"] = ".".join(map(str, self.sec[:depth])) if self.settings["sections"] else ""
            elif kind == "math":
                label = re.search(r"\\label\{([^}]+)\}", node["value"])
                if label:
                    node["identifier"] = identifier(label.group(1))
                tag = re.search(r"\\tag\{([^}]+)\}", node["value"])
                numbered = node.get("enumerated", self.settings["equations"])
                numbered = numbered and not re.search(r"\\(?:notag|nonumber)\b", node["value"])
                node["_number"] = tag.group(1) if tag else ""
                if numbered and not tag:
                    self.eqno += 1
                    node["_number"] = str(self.eqno)
                    if self.settings["book"] and self.sec[0]:
                        node["_number"] = f"{self.sec[0]}.{self.eqno}"
            key = identifier(node.get("identifier", node.get("label", "")))
            if key and kind not in ("cite", "mystRole", "mystDirective", "crossReference"):
                self.targets[key] = node
            self.collect(node.get("children", []))

    def reference(self, target, form="auto", custom=""):
        node = self.targets[identifier(unquote(target))]
        number = node.get("_number", "")
        title = self.plain(node.get("children", []))
        if custom:
            return custom.replace("{number}", number).replace("%s", number).replace("{name}", title or target)
        if form == "ref" and title:
            return title
        if number:
            return f"({number})" if node["type"] == "math" else f"Section {number}"
        return title or target

    @staticmethod
    def plain(nodes):
        return "".join(node.get("value", "") if "children" not in node else MystDocument.plain(node["children"])
                       for node in nodes)

    def inline_source(self, source, fmt):
        nodes = self.parse(source)
        if len(nodes) != 1 or nodes[0]["type"] != "paragraph":
            raise ValueError("Expected inline metadata")
        return self.inlines(nodes[0]["children"], fmt)

    def inlines(self, nodes, fmt):
        out = []
        for node in nodes:
            kind = node["type"]
            if kind == "text":
                out.extend(text_inlines(node["value"]))
            elif kind in ("emphasis", "strong", "link"):
                content = self.inlines(node["children"], fmt)
                if kind == "link" and node["url"].startswith("#"):
                    display = self.reference(node["url"][1:], custom=self.plain(node["children"]))
                    out.extend(text_inlines(display))
                elif kind == "link":
                    out.append(pandoc_node("Link", [["", [], []], content, [node["url"], node.get("title", "")]]))
                else:
                    out.append(pandoc_node("Emph" if kind == "emphasis" else "Strong", content))
            elif kind == "inlineCode":
                out.append(pandoc_node("Code", [["", [], []], node["value"]]))
            elif kind == "inlineMath":
                out.append(pandoc_node("Math", [pandoc_node("InlineMath"), node["value"]]))
            elif kind == "math":
                out.append(pandoc_node("RawInline", [fmt, self.formula(node, fmt)]))
            elif kind == "break" or (kind == "html" and re.fullmatch(r"<br\s*/?>", node["value"])):
                out.append(pandoc_node("LineBreak"))
            elif kind == "cite":
                out.extend(text_inlines(self.reference(node["identifier"])))
            elif kind == "mystRole":
                if node["name"] == "math":
                    out.append(pandoc_node("Math", [pandoc_node("InlineMath"), node["value"]]))
                else:
                    match = re.fullmatch(r"(.*?)\s*<([^>]+)>", node["value"])
                    target = match.group(2) if match else node["value"]
                    custom = match.group(1) if match else ""
                    out.extend(text_inlines(self.reference(target, node["name"], custom)))
            else:
                raise ValueError(f"Unsupported comparison inline: {kind}")
        return out

    def formula(self, node, fmt):
        tex = re.sub(r"\\(?:label|tag)\{[^}]*\}|\\(?:notag|nonumber)\b", "", node["value"]).strip()
        number = node.get("_number", "")
        if fmt == "latex":
            tag = r"\tag{" + number + "}" if number else ""
            return r"\noindent\begin{equation*}" + tex + tag + r"\end{equation*}"
        math = write_pandoc([pandoc_node("Plain", [pandoc_node("Math", [pandoc_node("DisplayMath"), tex])])], "typst")
        numbering = f'(..args) => [({number})]' if number else "none"
        return f"#[#set math.equation(numbering: {numbering})\n{math}]"

    def blocks(self, nodes, fmt):
        out = []
        for node in nodes:
            kind = node["type"]
            if kind in ("comment", "mystTarget"):
                continue
            if kind == "paragraph":
                out.append(pandoc_node("Para", self.inlines(node["children"], fmt)))
            elif kind == "heading":
                attr = [node.get("identifier", ""), [] if self.settings["sections"] else ["unnumbered"], []]
                out.append(pandoc_node("Header", [node["depth"], attr, self.inlines(node["children"], fmt)]))
            elif kind == "code":
                out.append(pandoc_node("CodeBlock", [["", [], []], node["value"]]))
            elif kind == "thematicBreak":
                out.append(pandoc_node("HorizontalRule"))
            elif kind == "blockquote":
                out.append(pandoc_node("BlockQuote", self.blocks(node["children"], fmt)))
            elif kind == "list":
                items = [self.blocks(item["children"], fmt) for item in node["children"]]
                if not node.get("spread", False):
                    for item in items:
                        for block in item:
                            if block["t"] == "Para":
                                block["t"] = "Plain"
                out.append(pandoc_node("OrderedList", [[node.get("start", 1), pandoc_node("Decimal"),
                                                       pandoc_node("Period")], items]) if node["ordered"]
                           else pandoc_node("BulletList", items))
            elif kind == "math":
                out.append(pandoc_node("RawBlock", [fmt, self.formula(node, fmt)]))
            elif kind in ("mystDirective", "container", "div", "block"):
                meta = json.loads(node.get("meta", "{}"))
                if meta.get("new-page") or meta.get("page-break"):
                    out.append(pandoc_node("RawBlock", [fmt, r"\newpage" if fmt == "latex" else "#pagebreak()"]))
                out.extend(self.blocks(node["children"], fmt))
            else:
                raise ValueError(f"Unsupported comparison block: {kind}")
        return out

    def template_body(self, fmt):
        out = []
        size = self.settings["size"]

        def raw(value):
            out.append(pandoc_node("RawBlock", [fmt, value]))

        def part(name, scale=1, color=None, italic=False, align=None, before=0, after=0):
            if not self.parts.get(name):
                return
            if fmt == "latex":
                raw(r"\vspace{%gbp}" % before)
                raw(r"\begin{" + {"right": "flushright", "left": "flushleft"}.get(align, "center") + "}"
                    if align else "{")
                raw(r"\fontsize{%gbp}{%gbp}\selectfont" % (scale * size, 1.2 * scale * size))
                if color:
                    raw(r"\color[HTML]{" + color.lstrip("#") + "}")
                if italic:
                    raw(r"\itshape")
            else:
                raw(f"#v({before}pt)")
                raw(f"#align({align})[" if align else "#[")
                raw(f"#set text(size: {scale * size}pt" + (f', fill: rgb("{color}")' if color else "") +
                    (', style: "italic"' if italic else "") + ")")
            out.extend(self.blocks(self.parts[name], fmt))
            if fmt == "latex":
                raw(r"\end{" + {"right": "flushright", "left": "flushleft"}.get(align, "center") + "}"
                    if align else r"\par}")
                raw(r"\vspace{%gbp}" % after)
            else:
                raw(f"]\n#v({after}pt)")

        template = self.settings["template"]
        if template == "letter":
            part("sender", align="right", before=size, after=size)
            part("recipient", align="left")
            part("opening", align="left", before=1.2 * size)
            out.extend(self.blocks(self.body, fmt))
            part("closing", align="left", before=1.2 * size)
            part("signature", align="left", before=72 * 1.2 / 2.54)
        elif template == "invitation":
            raw(r"\vspace*{\fill}" if fmt == "latex" else "#v(1fr)")
            part("intro", scale=1.2, color="#9a6a3a", italic=True)
            title = self.inline_source(self.settings["title"], fmt)
            raw(r"{\fontsize{%gbp}{%gbp}\selectfont\bfseries\color[HTML]{8B1A1A}" %
                (2.488 * size, 1.2 * 2.488 * size) if fmt == "latex"
                else f'#text(size: {2.488 * size}pt, weight: "bold", fill: rgb("#8b1a1a"))[')
            out.append(pandoc_node("Para", title))
            raw(r"\par}" if fmt == "latex" else "]")
            part("ornament", color="#c08a3e")
            out.extend(self.blocks(self.body, fmt))
            part("reply", scale=0.9, color="#9a6a3a")
            raw(r"\vspace*{\fill}" if fmt == "latex" else "#v(1fr)")
        else:
            out.extend(self.blocks(self.body, fmt))
        return out


def write_pandoc(blocks, fmt, meta=None, extra=()):
    version = json.loads(run(["pandoc", "-f", "markdown", "-t", "json"], input="").stdout)["pandoc-api-version"]
    doc = {"pandoc-api-version": version, "meta": meta or {}, "blocks": blocks}
    return run(["pandoc", "-f", "json", "-t", fmt, *extra], input=json.dumps(doc)).stdout


def latex_source(md_body, s, fonts):
    meta = ["---"]
    for k in ("title", "date", "abstract"):
        if s[k]:
            meta.append(f"{k}: " + json.dumps(s[k], ensure_ascii=False))
    if s["author"]:
        meta.append("author:")
        for a in s["author"].split("\n"):
            meta.append("  - " + json.dumps(a, ensure_ascii=False))
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


def typst_template(s, document):
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
    def inline(value):
        return write_pandoc([pandoc_node("Plain", document.inline_source(value, "typst"))], "typst").strip()

    if s["template"] in ("article", "book") and s["title"]:
        tb.append(f'#align(center)[#v(2em)#text(size: {1.728 * size}pt)[{inline(s["title"])}]')
        if s["author"]:
            for a in s["author"].split("\n"):
                tb.append(f'#v(1em)#text(size: {1.2 * size}pt)[{inline(a)}]')
        if s["date"]:
            tb.append(f'#v(0.6em)#text(size: {1.2 * size}pt)[{inline(s["date"])}]')
        tb.append("]#v(2em)")
    if s["template"] in ("article", "book") and document.parts.get("abstract"):
        abstract = write_pandoc(document.blocks(document.parts["abstract"], "typst"), "typst")
        tb.append(f'#align(center)[#text(size: {0.9 * size}pt, weight: "bold")[Abstract]]')
        tb.append(f'#pad(x: 2.5em)[#text(size: {0.9 * size}pt)[{abstract}]]')
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
    ap.add_argument("--myst-parser", required=True, type=Path, help="installed myst-parser@1.7.5 package directory")
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
            document = MystDocument(md, args.myst_parser.resolve())
            s = document.settings
            name = ex.stem
            latex_settings = s.copy()
            if s["template"] not in ("article", "book"):
                for field in ("title", "subtitle", "author", "date", "abstract"):
                    latex_settings[field] = None
            scaffold = json.loads(run(["pandoc", "-f", "markdown", "-t", "json"],
                                     input=latex_source("", latex_settings, fonts)).stdout)
            if s["template"] in ("article", "book"):
                for field in ("title", "subtitle", "date"):
                    if s[field]:
                        scaffold["meta"][field] = pandoc_node("MetaInlines", document.inline_source(s[field], "latex"))
                if s["author"]:
                    scaffold["meta"]["author"] = pandoc_node("MetaList", [
                        pandoc_node("MetaInlines", document.inline_source(author, "latex"))
                        for author in s["author"].split("\n")])
                if document.parts.get("abstract"):
                    scaffold["meta"]["abstract"] = pandoc_node("MetaBlocks", document.blocks(document.parts["abstract"], "latex"))
            tex = write_pandoc(document.template_body("latex"), "latex", scaffold["meta"], ("-s",))
            (work / f"{name}.tex").write_text(tex, encoding="utf-8")
            run(["tectonic", "--chatter", "minimal", f"{name}.tex"], cwd=work)
            typst_body = write_pandoc(document.template_body("typst"), "typst")
            (work / f"{name}.typ").write_text(typst_template(s, document).replace("$body$", typst_body), encoding="utf-8")
            run(["typst", "compile", "--font-path", str(fonts), f"{name}.typ",
                 f"{name}.typst.pdf"], cwd=work)
            montage([pages(ours[name], args.dpi), pages(work / f"{name}.pdf", args.dpi),
                     pages(work / f"{name}.typst.pdf", args.dpi)],
                    ["fplotlib", "LaTeX (Tectonic)", "Typst"], out / f"{name}.png")
            print(f"wrote {out / name}.png")


if __name__ == "__main__":
    main()
