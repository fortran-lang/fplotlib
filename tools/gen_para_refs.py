"""Regenerate tests/para_refs.txt: how XeTeX breaks the test paragraphs.

fplotlib breaks paragraphs into lines with TeX's algorithm and LaTeX's
parameters, so XeTeX setting the same paragraphs with the same font files
is the reference: the same lines, hyphenated at the same places, with
every glyph at the same position. Each paragraph is set by Tectonic
(XeTeX, fontspec) in Lato at 10 bp on a page of its own, at the width
given, and the glyphs are read back line by line from the XDV file XeTeX
writes, where their positions are exact (a PDF rounds them).

    pixi exec --spec tectonic --spec fonttools --spec python=3.12 -- \\
        python tools/gen_para_refs.py

Lato's ligatures and contextual alternates are switched off, since
fplotlib has neither; its kerning stays on.
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.ttLib import TTFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_glyphs import font_file  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "para_refs.txt"

FROG = ("In olden times when wishing still helped one, there lived a king whose "
        "daughters were all beautiful; and the youngest was so beautiful that the "
        "sun itself, which has seen so much, was astonished whenever it shone in "
        "her face. Close by the king\u2019s castle lay a great dark forest, and under "
        "an old lime-tree in the forest was a well, and when the day was very warm, "
        "the king\u2019s child went out into the forest and sat down by the side of the "
        "cool fountain; and when she was bored she took a golden ball, and threw it "
        "up on high and caught it; and this ball was her favorite plaything.")

TYPO = ("Typography is the art and technique of arranging type to make written "
        "language legible, readable and appealing when displayed. Dr. Knuth\u2019s "
        "well-known algorithm (published in 1981) considers the paragraph as a "
        "whole: it minimizes the total demerits of all the lines, so that a "
        "decision made early in the paragraph can improve the spacing of lines "
        "much later. U.S. readers, for example, rarely notice it\u2014but they "
        "would notice its absence! Hyphenation, interword stretchability and "
        "shrinkability all play their part.")

# Each paragraph: its text, the width of its lines and its indentation,
# in bp.
PARAGRAPHS = [
    (FROG, 345, 15),
    (FROG, 250, 15),
    (FROG, 180, 15),
    (FROG, 120, 0),
    (TYPO, 300, 15),
    (TYPO, 200, 15),
    (TYPO, 150, 10),
]

PREAMBLE = r"""\documentclass{article}
\usepackage[paperwidth=500bp,paperheight=900bp,margin=20bp]{geometry}
\usepackage{fontspec}
\setmainfont{Lato}[Path=FONTS/, Extension=.ttf, UprightFont=*-Regular,
  ItalicFont=*-Italic, BoldFont=*-Bold, Ligatures={NoCommon}, Contextuals={NoAlternate}]
\pagestyle{empty}
\begin{document}
\fontsize{10bp}{12bp}\selectfont
"""


# A scaled point, in bp.
BP = 72.0 / 72.27 / 65536.0


def xdv_glyphs(path):
    """The glyphs of each page of an XDV file: (h, v, font, glyph id), in
    scaled points, and the file name of each native font."""
    d = Path(path).read_bytes()
    i = 0
    pages, fonts = [], {}
    stack, out = [], None
    h = v = w = x = y = z = 0
    font = None

    def get(n, signed=True):
        nonlocal i
        b = d[i:i + n]
        i += n
        return int.from_bytes(b, "big", signed=signed)

    while i < len(d):
        op = d[i]
        i += 1
        if op == 247:                       # pre
            get(1, False), get(4), get(4), get(4)
            k = get(1, False)
            i += k
        elif op == 139:                     # bop
            i += 44
            h = v = w = x = y = z = 0
            stack, out = [], []
            pages.append(out)
        elif op == 140:                     # eop
            pass
        elif op == 141:
            stack.append((h, v, w, x, y, z))
        elif op == 142:
            h, v, w, x, y, z = stack.pop()
        elif 143 <= op <= 146:
            h += get(op - 142)
        elif op == 147:
            h += w
        elif 148 <= op <= 151:
            w = get(op - 147)
            h += w
        elif op == 152:
            h += x
        elif 153 <= op <= 156:
            x = get(op - 152)
            h += x
        elif 157 <= op <= 160:
            v += get(op - 156)
        elif op == 161:
            v += y
        elif 162 <= op <= 165:
            y = get(op - 161)
            v += y
        elif op == 166:
            v += z
        elif 167 <= op <= 170:
            z = get(op - 166)
            v += z
        elif 171 <= op <= 234:              # fnt_num
            font = op - 171
        elif 235 <= op <= 238:
            font = get(op - 234, False)
        elif 239 <= op <= 242:              # xxx (specials)
            k = get(op - 238, False)
            i += k
        elif op in (132, 137):              # rules
            get(4)
            wd = get(4)
            if op == 132:
                h += wd
        elif op == 252:                     # native font definition
            k = get(4, False)
            get(4)
            flags = get(2, False)
            n = get(1, False)
            fonts[k] = d[i:i + n].decode()
            i += n
            get(4)
            for bit in (0x0200, 0x1000, 0x2000, 0x4000):
                if flags & bit:
                    get(4)
        elif op in (253, 254):              # glyphs, text and glyphs
            if op == 254:
                k = get(2, False)
                i += 2 * k
            wd = get(4)
            n = get(2, False)
            xy = [(get(4), get(4)) for _ in range(n)]
            for (gx, gy) in xy:
                out.append((h + gx, v + gy, font, get(2, False)))
            h += wd
        elif op == 248:                     # post
            break
        else:
            raise SystemExit(f"XDV opcode {op} not understood")
    return pages, fonts


def page(text, width, indent):
    return (r"\hsize=%gbp \parindent=%gbp %s\par\newpage" "\n"
            % (width, indent, text))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fonts", help="the directory holding the pinned font files")
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        fonts = Path(tmp) / "fonts"
        fonts.mkdir()
        for f in ("Lato-Regular.ttf", "Lato-Italic.ttf", "Lato-Bold.ttf"):
            shutil.copy(font_file(f, args.fonts), fonts / f)
        tex = Path(tmp) / "refs.tex"
        tex.write_text(PREAMBLE.replace("FONTS", str(fonts))
                       + "".join(page(*p) for p in PARAGRAPHS) + r"\end{document}" "\n",
                       encoding="utf-8")
        subprocess.run(["tectonic", "--chatter", "minimal", "--outfmt", "xdv", str(tex)],
                       check=True)
        pages, used = xdv_glyphs(Path(tmp) / "refs.xdv")
        # Each glyph back to its character; where two characters share a
        # glyph (the hyphen and U+2010), the lower code point.
        chars = {}
        for k, name in used.items():
            font = TTFont(fonts / Path(name).name)
            rev = {}
            for cp, gname in sorted(font.getBestCmap().items(), reverse=True):
                rev[font.getGlyphID(gname)] = cp
            chars[k] = rev

    if len(pages) != len(PARAGRAPHS):
        raise SystemExit(f"{len(pages)} pages for {len(PARAGRAPHS)} paragraphs")
    L = [
        "# How XeTeX (Tectonic, fontspec) breaks the paragraphs of",
        "# tools/gen_para_refs.py into lines, in Lato at 10 bp.",
        "# Generated by tools/gen_para_refs.py; do not edit.",
        "#",
        "# P width, indentation: a paragraph, in bp",
        "# T its text",
        "# L a line's glyphs, as text",
        "# X their origins, from the left margin",
    ]
    for (text, width, indent), glyphs in zip(PARAGRAPHS, pages):
        lines = {}
        for h, v, font, g in glyphs:
            lines.setdefault(v, []).append((h, chr(chars[font][g])))
        rows = [sorted(lines[v]) for v in sorted(lines)]
        # Every line but an indented first one starts at the margin.
        margin = min(r[0][0] for r in (rows[1:] if indent else rows))
        L.append("P %g %g" % (width, indent))
        L.append("T " + text)
        for r in rows:
            L.append("L " + "".join(c for _, c in r))
            L.append("X " + " ".join("%.4f" % ((h - margin) * BP) for h, _ in r))
    OUT.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"wrote {OUT}: {len(PARAGRAPHS)} paragraphs")


if __name__ == "__main__":
    main()
