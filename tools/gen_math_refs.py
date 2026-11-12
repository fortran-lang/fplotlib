"""Regenerate tests/math_refs.txt: how XeTeX lays out the test formulas.

fplotlib's math layout is TeX's, driven by the MATH table of the same
font, so XeTeX setting the same formulas with the same font files is the
reference it is checked against. Each formula is typeset by Tectonic
(XeTeX with unicode-math) at 10 bp, one to a page, after a tiny rule that
marks where the formula starts; the glyph origins, sizes and rules are
read back from the PDF relative to that mark, and written out for
tests/test_mathref.f90 to compare fplotlib's layout with.

    pixi exec --spec tectonic --spec pdfminer.six --spec fonttools \\
        --spec python=3.12 -- python tools/gen_math_refs.py

The fonts are the pinned files tools/gen_glyphs.py fetches (or reads from
--fonts DIR), with Lete Sans Math cut down by reduced_math_font() to the
script alternates and size variants fplotlib stores, so that XeTeX chooses
among the same glyphs.
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.ttLib import TTFont
from pdfminer.high_level import extract_pages
from pdfminer.layout import LTChar, LTCurve, LTLine, LTRect

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_glyphs import font_file, reduced_math_font  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "math_refs.txt"

# The formulas, as fplotlib is given them. Each is set in text style, the
# way an inline formula in a label is.
FORMULAS = [
    r"$x^2$",
    r"$x_i$",
    r"$x_i^2$",
    r"$T^{2}_{n}$",
    r"$10^{-3}$",
    r"$10^{3}$",
    r"$E = mc^2$",
    r"$a + b - c$",
    r"$-x$",
    r"$e^{-x^2}$",
    r"$x_{i,j}$",
    r"$f(x) = x^2$",
    r"$\alpha_1 \times \beta^2$",
    r"$\Omega = \alpha + \beta$",
    r"$\frac{a}{b}$",
    r"$\frac{x}{2}$",
    r"$\frac{x+1}{y_k}$",
    r"$\sqrt{y}$",
    r"$\sqrt{x+1}$",
    r"$T = 2\pi\sqrt{\frac{L}{g}}$",
    r"$\mathrm{d}x$",
    r"$\sin x$",
    r"$a\,b\;c\ d$",
    r"$T^2 + 1$",
    r"$P_k + 1$",
    # Both scripts on a base without a top-right math kern: Tectonic's
    # XeTeX leaves that kern out when there is a subscript too (it tests
    # the wrong field), where TeX Live's XeTeX and fplotlib apply it.
    r"$T^{2}_{1} x$",
    r"$f^2(x)$",
    r"$y^{(n)}$",
    # Large operators, limits and the integrals' side scripts.
    r"$\displaystyle\sum_{i=1}^{n} i^2$",
    r"$\sum_{i=1}^n x_i$",
    r"$\int_0^1 f(x)\,dx$",
    r"$\displaystyle\int_0^1 x\,dx$",
    r"$\lim_{x \to 0} \frac{\sin x}{x}$",
    r"$\displaystyle\lim_{n \to \infty} a_n$",
    r"$\prod_k a_k$",
    r"$\sum\limits_{k=0}^{N} k$",
    # Fractions and stacks.
    r"$\binom{n}{k}$",
    r"$\dbinom{n}{k} + \tbinom{n}{k}$",
    r"${a \atop b}$",
    r"${a \over b}$",
    r"$\dfrac{1}{2} + \tfrac{1}{2}$",
    r"$\cfrac{1}{1+\cfrac{1}{x}}$",
    # Radicals.
    r"$\sqrt[3]{x}$",
    r"$\sqrt{\frac{1}{1+x^2}}$",
    r"$\sqrt{\displaystyle\sum_{k=1}^{n} \frac{a_k}{b_k}}$",
    # Accents.
    r"$\hat{x} + \tilde{y} + \bar{z}$",
    r"$\vec{v} \cdot \dot{x} + \ddot{y}$",
    r"$\widehat{xyz} + \widetilde{AB}$",
    # fplotlib sets an i or j under an accent dotless (dtls), which XeTeX
    # leaves to the font's own choice; written dotless, both agree.
    r"$\hat{\imath} + \hat{\jmath}$",
    r"$\check{c}\breve{u}$",
    r"$\hat{x}^2$",
    r"$\overrightarrow{AB}$",
    # Delimiters.
    r"$\left(\frac{a}{b}\right)$",
    r"$\left[x\right]$",
    r"$\left\{ x \middle| x > 0 \right\}$",
    r"$\big( \Big( \bigg( \Bigg($",
    r"$\bigl[ x \bigr]$",
    r"$\left( \sum_{i} x_i \right)^2$",
    # XeTeX scales a fraction's gaps by the font of the last character it
    # set rather than by the fraction's own size, so the gap only comes out
    # as the MATH table has it when that character is at the same size, as
    # in a display fraction's denominator.
    r"$\dfrac{\frac{a}{b}}{c}$",
    r"$\left(\dfrac{\frac{a}{b}}{c + d}\right)$",
    r"$2\frac{a}{b}, \frac{c}{d}x$",
    # Delimiters that do not pair up stay as they are, as TeX sets them:
    # unmatched ones, escaped ones and ones in braces.
    r"$[\frac{1}{2}, 1)$",
    r"$\(\frac{a}{b}\) + \[\frac{c}{d}\]$",
    r"${(}\frac{a}{b}{)}$",
    r"$\left(\displaystyle\sum_{k=1}^{n}\frac{1}{k^2}\right)$",
    r"$\langle x, y \rangle$",
    r"$\left\lfloor x \right\rfloor$",
    # Alphabets, text and operator names.
    r"$\mathbf{F} = m\mathbf{a}$",
    r"$\mathbb{R}^n \times \mathbb{C}$",
    r"$\mathcal{L}\{f\}$",
    r"$\mathsf{A}\mathit{diff}$",
    r"$\text{if } x > 0$",
    r"$\operatorname{erf}(x)$",
    # Symbols, primes and styles.
    r"$a \leq b \neq c \approx d$",
    r"$x \to \infty$",
    r"$f'(x) + f''(x)$",
    r"$y = f'(x)^2$",
    r"$\alpha \pm \beta \cdot \gamma$",
    r"$\hbar\omega = \nabla \times \vec{E}$",
    r"$\partial_t u = \Delta u$",
    r"$x \in \mathbb{N},\ y \notin A$",
    r"$\textstyle \sum_i \scriptstyle x_i$",
    r"$\$5$",
    # Alignments: LaTeX's array (matrices, cases) and amsmath's aligned
    # and gathered.
    r"$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$",
    r"$\begin{bmatrix} 1 & \frac{1}{2} \\ \frac{1}{3} & x^2 \end{bmatrix}$",
    r"$\begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad - bc$",
    r"$\begin{matrix} 1 & 2 & 3 \\ 4 & 5 & 6 \end{matrix}$",
    r"$\begin{array}{lcr} a & b & c \\ dd & ee & ff \end{array}$",
    r"$f(x) = \begin{cases} x & x \geq 0 \\ -x & x < 0 \end{cases}$",
    r"$\displaystyle \begin{aligned} a &= b + c \\ &= d \end{aligned}$",
    r"$\displaystyle \begin{aligned} x &= \frac{1}{2} & y &= 3 \\ z &= 4 & w &= 5 \end{aligned}$",
    r"$\displaystyle \begin{gathered} x = y \\ x + 1 = y + 1 \end{gathered}$",
]

PREAMBLE = r"""\documentclass{article}
\usepackage[paperwidth=300bp,paperheight=100bp,margin=20bp]{geometry}
\usepackage{amsmath}
\usepackage{fontspec}
\usepackage{unicode-math}
\setmainfont{Lato}[Path=FONTS/, Extension=.ttf, UprightFont=*-Regular,
  ItalicFont=*-Italic, BoldFont=*-Bold]
\setmathfont{LeteSansMath.otf}[Path=FONTS/, CharacterVariant=11]
\pagestyle{empty}
\setlength{\parindent}{0pt}
\makeatletter
% The script sizes are the font's own percentages rather than LaTeX's
% table, which would make the scriptscript size 5pt instead of 55%.
\fontsize{10bp}{12bp}\selectfont
\dimen0=\f@size pt
\dimen2=0.SCRIPT\dimen0
\dimen4=0.SCRIPTSCRIPT\dimen0
\edef\x{\noexpand\DeclareMathSizes{\f@size}{\f@size}{\strip@pt\dimen2}{\strip@pt\dimen4}}\x
\makeatother
% The space after a script is the font's SpaceAfterScript at the size of
% the formula, as fplotlib sets it.
\scriptspace=SPACEAFTERbp
\begin{document}
\fontsize{10bp}{12bp}\selectfont
"""

# The mark: a rule this wide and high, standing on the baseline at the
# start of the formula and taking no room.
MARK = 0.2


# fplotlib's \mathbf, \mathsf, \mathit, \mathbb and \mathcal are the math
# alphabets, which unicode-math calls \symbf and so on (its \mathbf is the
# bold text font), so the formulas are spelled that way for XeTeX.
ALPHABETS = {r"\mathbf": r"\symbf", r"\mathsf": r"\symsf", r"\mathit": r"\symit",
             r"\mathbb": r"\symbb", r"\mathcal": r"\symcal"}


# fplotlib's \binom is \atopwithdelims() as TeX sets it; amsmath's sizes
# its parentheses by \fontdimen 20 and 21, which under XeTeX are unrelated
# MATH constants.
BINOM = re.compile(r"\\([dt]?)binom\{([^{}]*)\}\{([^{}]*)\}")
BINOM_STYLE = {"": "", "d": r"\displaystyle", "t": r"\textstyle"}


# fplotlib's escaped \( \) \[ \] are the plain characters, which TeX
# writes without the backslash.
ESCAPES = {"\\(": "(", "\\)": ")", "\\[": "[", "\\]": "]"}


def page(formula):
    for a, b in ALPHABETS.items():
        formula = formula.replace(a + "{", b + "{")
    for a, b in ESCAPES.items():
        formula = formula.replace(a, b)
    formula = BINOM.sub(lambda m: r"{%s{{%s}\atopwithdelims(){%s}}}"
                        % (BINOM_STYLE[m[1]], m[2], m[3]), formula)
    return (r"\vrule width %gbp height %gbp depth 0pt\kern-%gbp%s\newpage" "\n"
            % (MARK, MARK, MARK, formula))


def walk(o, chars, rules):
    if isinstance(o, LTChar):
        chars.append(o)
    elif isinstance(o, (LTRect, LTLine, LTCurve)):
        rules.append(o)
    if hasattr(o, "__iter__"):
        for c in o:
            walk(c, chars, rules)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fonts", help="the directory holding the pinned font files")
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        # XeTeX gets Lete Sans Math cut down to what fplotlib stores of it.
        fonts = Path(tmp) / "fonts"
        fonts.mkdir()
        for f in ("Lato-Regular.ttf", "Lato-Italic.ttf", "Lato-Bold.ttf"):
            shutil.copy(font_file(f, args.fonts), fonts / f)
        reduced_math_font(font_file("LeteSansMath.otf", args.fonts)).save(
            fonts / "LeteSansMath.otf")
        tex = Path(tmp) / "refs.tex"
        mc = TTFont(fonts / "LeteSansMath.otf")["MATH"].table.MathConstants
        pre = (PREAMBLE.replace("FONTS", str(fonts))
               .replace("SCRIPTSCRIPT", "%02d" % mc.ScriptScriptPercentScaleDown)
               .replace("SCRIPT", "%02d" % mc.ScriptPercentScaleDown)
               .replace("SPACEAFTER", "%g" % (mc.SpaceAfterScript.Value / 100)))
        tex.write_text(pre
                       + "".join(page(f) for f in FORMULAS) + r"\end{document}" "\n",
                       encoding="utf-8")
        subprocess.run(["tectonic", "--chatter", "minimal", str(tex)], check=True)
        pages = list(extract_pages(str(Path(tmp) / "refs.pdf")))

    if len(pages) != len(FORMULAS):
        raise SystemExit(f"{len(pages)} pages for {len(FORMULAS)} formulas")
    L = [
        "# How XeTeX (Tectonic, unicode-math) lays out the formulas of",
        "# tools/gen_math_refs.py with Lato and Lete Sans Math at 10 bp.",
        "# Generated by tools/gen_math_refs.py; do not edit.",
        "#",
        "# F formula",
        "# G code point (0 for none), size, x, y: a glyph's origin, y up",
        "# R x0, y0, x1, y1: a rule's box",
        "# All relative to where the formula starts on its baseline.",
    ]
    for formula, p in zip(FORMULAS, pages):
        chars, rules = [], []
        walk(p, chars, rules)
        # The mark is the first rule drawn, and the only one this small.
        marks = [r for r in rules if abs(r.x1 - r.x0) <= MARK + 1e-3
                 and abs(r.y1 - r.y0) <= MARK + 1e-3]
        if not marks:
            raise SystemExit(f"no mark found for {formula}")
        mark = marks[0]
        ox = min(mark.x0, mark.x1)
        oy = min(mark.y0, mark.y1)
        # A rule this thin comes back as a stroked line along its middle.
        if abs(mark.x1 - mark.x0) < 1e-6:
            ox -= MARK / 2
        L.append("F " + formula)
        for c in chars:
            t = c.get_text()
            cp = ord(t) if len(t) == 1 else 0
            L.append("G %d %.4f %.4f %.4f" % (cp, c.size, c.matrix[4] - ox, c.matrix[5] - oy))
        for r in rules:
            if r is mark:
                continue
            lw = getattr(r, "linewidth", 0.0) or 0.0
            x0, y0, x1, y1 = r.bbox
            # A thin rule may come back as a stroked line: its box is
            # then its centre line, and its width is the line's.
            if isinstance(r, LTLine) and abs(y1 - y0) < 1e-6:
                y0 -= lw / 2
                y1 += lw / 2
            L.append("R %.4f %.4f %.4f %.4f" % (x0 - ox, y0 - oy, x1 - ox, y1 - oy))
    OUT.write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OUT}: {len(FORMULAS)} formulas")


if __name__ == "__main__":
    main()
