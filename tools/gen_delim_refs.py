"""Regenerate tests/delim_refs*.txt: how large Typst makes automatic delimiters.

fplotlib's matched delimiters grow to fit what they enclose, as Typst's
do, and by Typst's rule: a delimiter covers its contents from the axis,
less 0.1 em, with the first size variant that is large enough. Typst
setting the same formulas with the same font files is the reference.
Each formula is written twice, for fplotlib and in Typst's syntax, and
typeset by Typst at 10 pt, one to a page; the advance widths of the
delimiters, which tell their size variants apart, are read back from the
PDF in order from left to right and written out for tests/test_mathref.f90
to compare with the delimiters fplotlib chooses. (The rest of the layout
is TeX's, and is checked against XeTeX by tests/math_refs.txt.)

    pixi exec --spec typst --spec pdfminer.six --spec fonttools \\
        --spec numpy --spec python=3.12 -- python tools/gen_delim_refs.py \\
        [--family serif]

The fonts are the pinned files tools/gen_glyphs.py fetches (or reads from
--fonts DIR) of one family, Lato and Lete Sans Math (tests/delim_refs.txt)
or with --family serif STIX Two (tests/delim_refs_serif.txt), the math
font cut down by reduced_math_font() to the script alternates and size
variants fplotlib stores, so that Typst chooses among the same glyphs.
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from pdfminer.high_level import extract_pages
from pdfminer.layout import LTChar

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_glyphs import FAMILIES, font_file, reduced_math_font  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = {"sans-serif": ROOT / "tests" / "delim_refs.txt",
       "serif": ROOT / "tests" / "delim_refs_serif.txt"}
# The names Typst knows each family's text and math fonts by.
FONT_NAMES = {"sans-serif": ("Lato", "Lete Sans Math"),
              "serif": ("STIX Two Text", "STIX Two Math")}

# Each formula as fplotlib is given it, and in Typst's syntax. Typst does
# not pair | or ‖ by itself, so those pairs are written with lr(), and a
# middle | with mid(). Unmatched delimiters, which Typst would pair up but
# fplotlib leaves alone, are checked against XeTeX instead. So are display
# operators with limits: TeX pads the limits by \big_op_spacing5, which
# Typst does not, so the two measure such an operator differently. And so
# are delimiters tall enough to be built from an assembly, whose parts
# carry no text in Typst's PDF.
FORMULAS = [
    (r"$(x)$", "(x)"),
    (r"$f(x) = (x+1)^2$", "f(x) = (x+1)^2"),
    (r"$(x^2)$", "(x^2)"),
    (r"$(x_i)$", "(x_i)"),
    (r"$(x_i^2)$", "(x_i^2)"),
    (r"$(A^T)$", "(A^T)"),
    (r"$(f'(x))$", "(f'(x))"),
    (r"$(e^{x^2})$", "(e^(x^2))"),
    (r"$(\hat{A})$", "(hat(A))"),
    (r"$(\sqrt{x})$", "(sqrt(x))"),
    (r"$(\frac{a}{b})$", "(a/b)"),
    (r"$[\frac{1}{2}]$", "[1/2]"),
    (r"$\{\frac{a}{b}\}$", "{a/b}"),
    (r"$|\frac{a}{b}|$", "lr(|a/b|)"),
    (r"$\|\frac{a}{b}\|$", "lr(‖a/b‖)"),
    (r"$|x|$", "lr(|x|)"),
    (r"$\langle \frac{a}{b} \rangle$", "⟨a/b⟩"),
    (r"$\lfloor \frac{a}{b} \rfloor$", "⌊a/b⌋"),
    (r"$\lceil \frac{a}{b} \rceil$", "⌈a/b⌉"),
    (r"$((\frac{a}{b}))$", "((a/b))"),
    (r"$(\frac{\frac{a}{b}}{c})$", "(frac(frac(a, b), c))"),
    (r"$(\sum_{i=1}^{n} x_i)$", "(sum_(i=1)^n x_i)"),
    (r"$(\int_0^1 f\,dx)$", "(integral_0^1 f d x)"),
    (r"$x^{(\frac{a}{b})}$", "x^((a/b))"),
    (r"$x_{(\frac{a}{b})}$", "x_((a/b))"),
    (r"$\sqrt{(\frac{a}{b})}$", "sqrt((a/b))"),
    (r"$(\frac{a}{b} | \frac{c}{d})$", "(a/b mid(|) c/d)"),
    (r"$\{x | x > \frac{1}{2}\}$", "{x mid(|) x > 1/2}"),
    (r"$\displaystyle(\frac{\frac{a}{b}}{c})$", "display((frac(frac(a, b), c)))"),
]

# Formulas left out of a family's references, and why. In STIX Two the
# superscript of a text-style integral sits by TeX's baseline drop from
# the integral's top, higher than Typst puts it, so the two enclose
# contents of different heights (the layout is TeX's, and XeTeX's
# agrees); and the nested display fraction is tall enough for an
# assembly, which this comparison does not cover.
SKIP = {"sans-serif": set(),
        "serif": {r"$(\int_0^1 f\,dx)$", r"$\displaystyle(\frac{\frac{a}{b}}{c})$"}}

# The delimiters, as the text Typst gives their glyphs.
DELIMS = set("()[]{}|‖⟨⟩⌊⌋⌈⌉")

PREAMBLE = """#set page(width: auto, height: auto, margin: 5pt)
#set text(font: "TEXTFONT", size: 10pt)
#show math.equation: set text(font: "MATHFONT")
"""


def walk(o, chars):
    if isinstance(o, LTChar):
        chars.append(o)
    if hasattr(o, "__iter__"):
        for c in o:
            walk(c, chars)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fonts", help="the directory holding the pinned font files")
    ap.add_argument("--family", choices=list(OUT), default="sans-serif",
                    help="the family to set the formulas in")
    args = ap.parse_args()
    fam = next(f for f in FAMILIES if f.name == args.family)
    out = OUT[fam.name]
    tname, mname = FONT_NAMES[fam.name]
    formulas = [f for f in FORMULAS if f[0] not in SKIP[fam.name]]
    with tempfile.TemporaryDirectory() as tmp:
        # Typst gets the math font cut down to what fplotlib stores of it.
        fonts = Path(tmp) / "fonts"
        fonts.mkdir()
        regular = fam.text[0][0]
        shutil.copy(font_file(regular, args.fonts), fonts / regular)
        reduced_math_font(font_file(fam.math, args.fonts)).save(fonts / fam.math)
        typ = Path(tmp) / "refs.typ"
        pre = PREAMBLE.replace("TEXTFONT", tname).replace("MATHFONT", mname)
        typ.write_text(pre + "#pagebreak()\n".join(
            "$%s$\n" % t for _, t in formulas), encoding="utf-8")
        subprocess.run(["typst", "compile", "--font-path", str(fonts),
                        "--ignore-system-fonts", str(typ)], check=True)
        pages = list(extract_pages(str(Path(tmp) / "refs.pdf")))

    if len(pages) != len(formulas):
        raise SystemExit(f"{len(pages)} pages for {len(formulas)} formulas")
    L = [
        "# The delimiters Typst sets in the formulas of tools/gen_delim_refs.py,",
        f"# with {mname} at 10 pt, from left to right.",
        "# Generated by tools/gen_delim_refs.py; do not edit.",
        "#",
        "# F formula",
        "# D code point, advance width",
    ]
    for (formula, _), p in zip(formulas, pages):
        chars = []
        walk(p, chars)
        L.append("F " + formula)
        for c in sorted(chars, key=lambda c: (round(c.matrix[4], 2), -c.matrix[5])):
            t = c.get_text()
            if t in DELIMS:
                L.append("D %d %.4f" % (ord(t), c.adv))
    out.write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {out}: {len(formulas)} formulas")


if __name__ == "__main__":
    main()
