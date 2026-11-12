"""Regenerate src/fplotlib_glyphs_data.f90 from the pinned font files.

Every backend draws text from outlines compiled into the library, so the
outlines, metrics and kerning of the fonts fplotlib uses have to be part of
it. Text is set in Lato (regular, bold, italic) and math in
Lete Sans Math, whose OpenType MATH table drives the math layout.

The fonts are pinned to exact commits and checked against their SHA-256
hashes. They are downloaded into a cache directory, or read from a
directory given on the command line:

    pixi exec --spec fonttools --spec numpy --spec python=3.12 -- python tools/gen_glyphs.py
    pixi exec --spec fonttools --spec numpy --spec python=3.12 -- \
        python tools/gen_glyphs.py --fonts DIR

What is stored is close to each font's own representation, in integer font
units:

  * glyphs are numbered (glyph ids, "gids"), the faces one after another,
    because a glyph need not have a code point of its own -- a component
    of an accented letter, a size variant, a script-size alternate;
  * a simple glyph is its contours, each a cycle of points that lie on the
    curve or are control points. Lete Sans Math is CFF, so its contours
    are cubic, with the control points in pairs; Lato is TrueType, but is
    stored as cubics too, at half its resolution (see LATO_OSCALE): a
    letter Lete draws the same way is Lete's glyph, and the rest are
    refitted, all within 0.00125 em of Lato's own outlines;
  * a composite glyph (an accented letter, mostly) is a list of component
    gids with their offsets, so the accent and the letter are stored once;
  * every glyph carries its advance width and its ink box, the exact
    bounds of the curves rounded outwards;
  * each face has a cmap, the code points it maps to gids, and its pair
    kerning, reduced to a left class per glyph, a right class per glyph
    and the non-zero cells of the class matrix;
  * the math face carries its MATH table: the constants, and per glyph
    the italic correction, top accent attachment, math kerns, extended
    shape flag, size variants and assemblies.
    Three GSUB features are baked in: cv11 (the single-story g) goes into
    the cmap, and ssty (script-size alternates) and dtls (dotless forms)
    become tables the layout looks glyphs up in.

Not all of each font is kept: see the repertoires below, SSTY_KEPT and
MAX_VARIANT. tools/gen_math_refs.py and tools/gen_delim_refs.py typeset
their references with reduced_math_font(), Lete Sans Math cut down to the
same data, so that XeTeX and Typst lay out exactly what fplotlib can.

Every point is a delta from the one before it, coded as a magnitude class
through a prefix code plus the raw bits under the leading one, which is
deflate's trick for distances; the code lengths are a Huffman code for the
deltas this data actually has, and travel as a parameter beside the blob.
The bit stream is written into the Fortran source as one base85 string,
which fplotlib_glyphs unpacks on first use.
"""

import argparse
import hashlib
import heapq
import json
import math
import sys
import unicodedata
import urllib.request
from pathlib import Path

import numpy as np
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.recordingPen import DecomposingRecordingPen, RecordingPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "fplotlib_glyphs_data.f90"
CACHE = Path.home() / ".cache" / "fplotlib" / "fonts"

LATO_URL = ("https://raw.githubusercontent.com/google/fonts/"
            "15e8fc68b03a0214ace8b52ca0153e1b597345ec/ofl/lato/")
LETE_URL = ("https://raw.githubusercontent.com/abccsss/LeteSansMath/"
            "5672e4573903c5658fb74d96b4282bfb4ed2404f/")

# The pinned files: where each comes from and the hash it must have.
SOURCES = {
    "Lato-Regular.ttf": (LATO_URL, "d636e4683231f931eda222d588e944d082bfd3bdba02f928bee461c0f185b251"),
    "Lato-Bold.ttf": (LATO_URL, "8a0aace75d33794eece4b28187bfc1df0bbd2888b5d8a56e01788c8d65d16be1"),
    "Lato-Italic.ttf": (LATO_URL, "e399c44efe1387100531d26c7e4800c5d12251b890d6654a3098c7c679cb1786"),
    "Lato-BoldItalic.ttf": (LATO_URL, "62c1b7f0d2e74b45960154c3520efc337b553db0961bfdc950d5618334596cc8"),
    "OFL.txt": (LATO_URL, "74ba064d03f1f1c4a952da936c3eb71866c34404916734de3cae73b34357e59e"),
    "LeteSansMath.otf": (LETE_URL, "8e6f7468e12c19668943e71353f8ae0769682547146f11f3471da6f5f9db68b6"),
    "LICENSE.txt": (LETE_URL, "9fe21cbbea717de5a24d757c1564e1f2fde6d8d8cbd975a4f327886b68ed5895"),
}

# The faces, in the order the library numbers them: regular, bold, italic.
# Each predicts its advance widths from the face named, which is the same
# letter drawn another way and usually of a similar width. Bold italic is
# left out: a label asking for it is set in bold.
TEXT_FACES = [
    ("Lato-Regular.ttf", None),
    ("Lato-Bold.ttf", 0),
    ("Lato-Italic.ttf", 0),
]
# The math face comes after them.
MATH_FACE = "LeteSansMath.otf"

# Kerning is stored in steps of KERN_STEP font units (2.5 units, 0.00125
# em, at most off). Bold kerns exactly the pairs Regular does, by a median
# of 3 units more or less, so it uses Regular's kerning (KERN_SHARED); and
# Italic's values are stored as the difference from Regular's value for
# the same pair (KERN_PREDICTED). The glyphs of the three faces line up,
# a letter at the same index in each, which both rely on.
KERN_STEP = 5
KERN_SHARED = {1: 0}
KERN_PREDICTED = {2: 0}

# Lato's outlines are stored as cubics on a grid of LATO_OSCALE font units
# (1000 to the em instead of 2000). Lete Sans Math draws its upright, bold
# and italic letters, digits and Greek as Lato's, converted to cubics at
# 1000 units to the em, so a Lato glyph whose outline Lete has, within
# ALIAS_TOL font units of Lato's own, is that Lete glyph, scaled and
# shifted; any other is refitted with cubics (fontTools' qu2cu, at most
# REFIT_ERR units off) and put on the grid, and must stay within
# REFIT_TOL units of Lato's own outline.
LATO_OSCALE = 2
ALIAS_TOL = 2.0
REFIT_ERR = 1.0
REFIT_TOL = 2.5


def _r(a, b):
    return set(range(a, b + 1))


# The text repertoire: every European script except Cyrillic, without
# polytonic Greek, and the symbols labels are written with. Left out of
# Latin Extended-B are the single-character Croatian digraphs (written as
# two letters in practice), the Sami letters and the accented Å, Æ and Ø.
TEXT_REPERTOIRE = (
    _r(0x20, 0x7E) | _r(0xA0, 0xFF) | _r(0x100, 0x17F)
    | _r(0x218, 0x21B)
    | _r(0x1E80, 0x1E85) | _r(0x1EF2, 0x1EF3) | {0x1E9E}
    | _r(0x384, 0x38A) | {0x38C} | _r(0x38E, 0x3A1) | _r(0x3A3, 0x3CE)
    | {0x3D0, 0x3D1, 0x3D5, 0x3D6, 0x3F0, 0x3F1, 0x3F5}
    | {0x2BC, 0x2C6, 0x2C7} | _r(0x2D8, 0x2DD) | _r(0x300, 0x30C) | _r(0x326, 0x328)
    | _r(0x2007, 0x200A) | _r(0x2010, 0x2015) | _r(0x2018, 0x201F)
    | _r(0x2020, 0x2022) | {0x2026, 0x2030, 0x2032, 0x2033, 0x2039, 0x203A, 0x2044, 0x202F}
    | _r(0x2070, 0x2071) | _r(0x2074, 0x207F) | _r(0x2080, 0x208E)
    | {0x20AC, 0x2113, 0x2116, 0x2122, 0x2126, 0x212E}
    | {0x2212, 0x2248, 0x2260, 0x2264, 0x2265, 0x221E, 0x221A, 0x2202, 0x2211, 0x220F}
    | _r(0x2190, 0x2193)
)

# Code points Lato has no glyph for, drawn with one that looks the same.
# U+2103 (degree Celsius) is two glyphs and is spelled out by the text
# layout instead; U+20BD (ruble) is left out.
TEXT_FALLBACK = {0x2011: 0x2D, 0x2206: 0x394}

# The math repertoire, set in Lete Sans Math: the math alphabets (italic,
# upright, bold, double-struck, script, sans-serif), the operators,
# relations and arrows, the big operators, delimiters, radicals and
# accents. Code points the font does not have are left out.
MATH_REPERTOIRE = (
    _r(0x20, 0x7E) | {0xAC, 0xB0, 0xB1, 0xB7, 0xD7, 0xF7}
    | _r(0x391, 0x3A9) | _r(0x3B1, 0x3C9) | {0x3D1, 0x3D5, 0x3D6, 0x3F0, 0x3F1, 0x3F5}
    | {0x131, 0x237}
    | _r(0x1D400, 0x1D433)                          # bold
    | _r(0x1D434, 0x1D467) | {0x210E}               # italic
    | _r(0x1D49C, 0x1D4B5)                          # script capitals
    | {0x212C, 0x2130, 0x2131, 0x210B, 0x2110, 0x2112, 0x2133, 0x211B}
    | _r(0x1D538, 0x1D551)                          # double-struck capitals
    | {0x2102, 0x210D, 0x2115, 0x2119, 0x211A, 0x211D, 0x2124}
    | _r(0x1D5A0, 0x1D5D3)                          # sans-serif
    | {0x1D6A4, 0x1D6A5}                            # dotless italic i, j
    | _r(0x1D6A8, 0x1D6E1)                          # bold greek
    | _r(0x1D6E2, 0x1D71B)                          # italic greek
    | _r(0x1D7CE, 0x1D7D7) | _r(0x1D7E2, 0x1D7EB)  # bold and sans digits
    # accents
    | _r(0x300, 0x308) | {0x30A, 0x30C, 0x20D6, 0x20D7}
    # binary operators
    | {0x2212, 0x2213, 0x2216, 0x2217, 0x2218, 0x2219, 0x22C5, 0x22C6, 0x2229,
       0x222A, 0x2227, 0x2228, 0x2020, 0x2022, 0x2295, 0x2297, 0x2299}
    # relations
    | {0x2208, 0x2209, 0x220B, 0x2264, 0x2265, 0x2260, 0x2248, 0x223C,
       0x2243, 0x2245, 0x2261, 0x221D, 0x226A, 0x226B, 0x2A7D, 0x2A7E,
       0x2272, 0x2273, 0x2254, 0x22A4, 0x22A5, 0x2223, 0x2224, 0x2225, 0x2226}
    | _r(0x2282, 0x2287)
    # arrows
    | _r(0x2190, 0x2199) | {0x21A6} | _r(0x21D0, 0x21D5) | _r(0x27F5, 0x27FA)
    | {0x27FC}
    # ordinary symbols
    | {0x221E, 0x2202, 0x2207, 0x2205, 0x2200, 0x2203, 0x2204, 0x210F,
       0x2113, 0x211C, 0x2111, 0x2135, 0x2032, 0x2033, 0x2034, 0x2026,
       0x22EF, 0x22EE, 0x22F1, 0x2220, 0x25B3}
    # big operators
    | {0x2211, 0x220F, 0x222B, 0x222C, 0x222E, 0x22C2, 0x22C3, 0x2A01, 0x2A02}
    # delimiters and radicals
    | {0x2016, 0x27E8, 0x27E9, 0x2308, 0x2309, 0x230A, 0x230B, 0x221A}
)

# Left out of the math repertoire as too rare in plot labels to pay for:
# the operators and relations of logic and order theory (⊎ ⊓ ⊔ ⊖ ⊘ ⋆ ‡ ⋄ ◦
# ≺ ≻ ⪯ ⪰ ⊢ ⊣ ≍ ≜ ≐ ∴ ∵ ∶ ∷ ≦ ≧ ▽), the big operators ∐ ∭ ⋀ ⋁ ⨀ ⨄ ⨆,
# and the radicals ∛ ∜, which mathtext sets as \sqrt[3] and \sqrt[4].


def ssty_kept(cp):
    r"""Whether the glyph of a code point keeps its script-size alternate.

    Only letters, digits and primes do, in the alphabets that are written
    in scripts: math italic Latin and Greek, upright Latin and Greek, and
    the digits. Each keeps its first (script) alternate only; scriptscript
    uses it too. Symbols, and \mathbf, \mathsf, \mathbb and \mathcal
    letters, are scaled down from their full-size glyphs instead.
    """
    return (0x30 <= cp <= 0x39 or 0x41 <= cp <= 0x5A or 0x61 <= cp <= 0x7A
            or 0x391 <= cp <= 0x3A9 or 0x3B1 <= cp <= 0x3C9
            or cp in (0x3D1, 0x3D5, 0x3D6, 0x3F0, 0x3F1, 0x3F5)
            or 0x1D434 <= cp <= 0x1D467 or cp == 0x210E
            or 0x1D6E2 <= cp <= 0x1D71B
            or cp in (0x131, 0x237, 0x1D6A4, 0x1D6A5, 0x2032, 0x2033, 0x2034))


# A vertical size variant taller than this, in ems, is left out when the
# glyph has an assembly, which is then built instead; a glyph without an
# assembly keeps all its variants.
MAX_VARIANT = 3.0

# The MATH constants, in the order the OpenType specification lists them.
MATH_CONSTANTS = [
    "ScriptPercentScaleDown", "ScriptScriptPercentScaleDown",
    "DelimitedSubFormulaMinHeight", "DisplayOperatorMinHeight", "MathLeading",
    "AxisHeight", "AccentBaseHeight", "FlattenedAccentBaseHeight",
    "SubscriptShiftDown", "SubscriptTopMax", "SubscriptBaselineDropMin",
    "SuperscriptShiftUp", "SuperscriptShiftUpCramped", "SuperscriptBottomMin",
    "SuperscriptBaselineDropMax", "SubSuperscriptGapMin",
    "SuperscriptBottomMaxWithSubscript", "SpaceAfterScript", "UpperLimitGapMin",
    "UpperLimitBaselineRiseMin", "LowerLimitGapMin", "LowerLimitBaselineDropMin",
    "StackTopShiftUp", "StackTopDisplayStyleShiftUp", "StackBottomShiftDown",
    "StackBottomDisplayStyleShiftDown", "StackGapMin", "StackDisplayStyleGapMin",
    "StretchStackTopShiftUp", "StretchStackBottomShiftDown",
    "StretchStackGapAboveMin", "StretchStackGapBelowMin",
    "FractionNumeratorShiftUp", "FractionNumeratorDisplayStyleShiftUp",
    "FractionDenominatorShiftDown", "FractionDenominatorDisplayStyleShiftDown",
    "FractionNumeratorGapMin", "FractionNumDisplayStyleGapMin",
    "FractionRuleThickness", "FractionDenominatorGapMin",
    "FractionDenomDisplayStyleGapMin", "SkewedFractionHorizontalGap",
    "SkewedFractionVerticalGap", "OverbarVerticalGap", "OverbarRuleThickness",
    "OverbarExtraAscender", "UnderbarVerticalGap", "UnderbarRuleThickness",
    "UnderbarExtraDescender", "RadicalVerticalGap", "RadicalDisplayStyleVerticalGap",
    "RadicalRuleThickness", "RadicalExtraAscender", "RadicalKernBeforeDegree",
    "RadicalKernAfterDegree", "RadicalDegreeBottomRaisePercent",
]

# Printable ASCII without the characters that are awkward inside a Fortran
# literal: the two quotes, the backslash some compilers read escapes from,
# and "&" and "!", which lfortran mistakes for a continuation and a comment
# even inside the quotes. That leaves 89; the first 85 are the alphabet.
ALPHABET = "".join(
    c for c in (chr(i) for i in range(33, 127)) if c not in "\"'\\&!"
)[:85]

VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_CLOSE = 1, 2, 3, 4


# --- the font files --------------------------------------------------


def font_file(name, fontdir):
    """The path of a pinned file, fetched into the cache if need be."""
    url, digest = SOURCES[name]
    if fontdir is not None:
        path = Path(fontdir) / name
    else:
        path = CACHE / name
        if not path.exists():
            CACHE.mkdir(parents=True, exist_ok=True)
            print(f"downloading {url}{name}")
            with urllib.request.urlopen(url + name) as r:
                data = r.read()
            path.write_bytes(data)
    got = hashlib.sha256(path.read_bytes()).hexdigest()
    if got != digest:
        raise SystemExit(f"{path}: SHA-256 {got}, expected {digest}")
    return path


# --- one face --------------------------------------------------------


class Glyph:
    def __init__(self, name):
        self.name = name
        self.adv = 0
        self.contours = []      # [(points, on-curve flags)], for a simple glyph
        self.ref = None         # the glyph it is stored as a difference from
        self.turns = None       # where each contour was started, when stored
        self.comps = None       # [(name, dx, dy, face)], for a composite one;
                                # face is the index of another face the
                                # component comes from, None for this one
        self.bbox = (0, 0, 0, 0)
        self.ink = False


class Face:
    def __init__(self, tag):
        self.tag = tag
        self.glyphs = []
        self.index = {}         # glyph name -> position in self.glyphs
        self.cmap = {}          # code point -> glyph name
        self.kern = {}          # (name, name) -> x advance adjustment
        self.cubic = False
        self.pred = None
        self.math = None
        self.oscale = 1         # outline units are this many font units
        self.xref = None        # the face components may come from too
        self.resid = False      # whether glyphs may be stored as differences
        self.kern_from = None   # the face whose kerning this one uses
        self.kern_pred = None   # the face this one's kerning is predicted from

    def add(self, g):
        self.index[g.name] = len(self.glyphs)
        self.glyphs.append(g)


def quad_contours(glyf, name):
    """A simple TrueType glyph as the font stores it."""
    g = glyf[name]
    if g.numberOfContours <= 0:
        return []
    coords, end_pts, flags = g.getCoordinates(glyf)
    coords = list(coords)
    contours = []
    start = 0
    for end in end_pts:
        pts = []
        for x, y in coords[start:end + 1]:
            if int(x) != x or int(y) != y:
                raise SystemExit(f"{name}: non-integer coordinate {(x, y)}")
            pts.append((int(x), int(y)))
        if any(f & 0x80 for f in flags[start:end + 1]):
            raise SystemExit(f"{name}: cubic off-curve points in a glyf table")
        on = [bool(f & 0x01) for f in flags[start:end + 1]]
        # An on-curve point repeated, which some contours close with, is
        # a line of no length. It draws nothing, but where the contour is
        # turned would decide where it sits, so it is dropped.
        k = 0
        while k < len(pts) and len(pts) > 1:
            j = (k + 1) % len(pts)
            if pts[k] == pts[j] and on[k] and on[j]:
                del pts[j], on[j]
                k = 0
            else:
                k += 1
        contours.append((pts, on))
        start = end + 1
    return contours


def cubic_contours(glyphset, name):
    """A CFF glyph as cycles of points, control points in pairs.

    A contour starts at its moveTo point, every lineTo adds a point on the
    curve and every curveTo two control points and one on it. The last
    segment comes back to the start, and when a curve is what brings it
    back, the end point it repeats is left out: closing the contour
    supplies it.
    """
    pen = RecordingPen()
    glyphset[name].draw(pen)
    contours = []
    pts = on = None
    for op, args in pen.value:
        if op == "moveTo":
            pts, on = [args[0]], [True]
        elif op == "lineTo":
            pts.append(args[0])
            on.append(True)
        elif op == "curveTo":
            if len(args) != 3:
                raise SystemExit(f"{name}: a curveTo with {len(args)} points")
            pts.extend(args)
            on.extend([False, False, True])
        elif op in ("closePath", "endPath"):
            if len(pts) > 1 and pts[-1] == pts[0] and on[-1]:
                pts.pop()
                on.pop()
            ipts = []
            for x, y in pts:
                if int(x) != x or int(y) != y:
                    raise SystemExit(f"{name}: non-integer coordinate {(x, y)}")
                ipts.append((int(x), int(y)))
            contours.append((ipts, on))
            pts = on = None
        else:
            raise SystemExit(f"{name}: unhandled pen op {op}")
    return contours


def ink_box(glyphset, name):
    """The exact bounds of the curves, rounded outwards to font units."""
    pen = BoundsPen(glyphset)
    glyphset[name].draw(pen)
    if pen.bounds is None:
        return (0, 0, 0, 0), False
    x0, y0, x1, y1 = pen.bounds
    return (math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1)), True


def pair_kerning(font, names):
    """The x advance adjustment of every pair of glyphs in names.

    The kern feature's lookups are applied the way a shaper applies them:
    within a lookup the first subtable that matches the pair decides it,
    and a class-based subtable matches whenever the first glyph is in its
    coverage, even where the cell it lands in is zero.
    """
    if "GPOS" not in font:
        return {}
    gpos = font["GPOS"].table
    lookups = []
    for fr in gpos.FeatureList.FeatureRecord:
        if fr.FeatureTag == "kern":
            for li in fr.Feature.LookupListIndex:
                if li not in lookups:
                    lookups.append(li)
    names = set(names)
    total = {}
    for li in sorted(lookups):
        lookup = gpos.LookupList.Lookup[li]
        decided = {}
        for st in lookup.SubTable:
            if lookup.LookupType == 9:
                st = st.ExtSubTable
            if st.LookupType != 2:
                raise SystemExit(f"kern lookup {li} is type {st.LookupType}")
            if st.ValueFormat1 & ~0x4 or st.ValueFormat2:
                raise SystemExit(f"kern lookup {li} adjusts more than the advance")
            if st.Format == 1:
                for i, g1 in enumerate(st.Coverage.glyphs):
                    if g1 not in names:
                        continue
                    for pvr in st.PairSet[i].PairValueRecord:
                        g2 = pvr.SecondGlyph
                        if g2 not in names or (g1, g2) in decided:
                            continue
                        v = getattr(pvr.Value1, "XAdvance", 0) if pvr.Value1 else 0
                        decided[(g1, g2)] = v or 0
            else:
                cd1 = st.ClassDef1.classDefs
                cd2 = st.ClassDef2.classDefs
                for g1 in st.Coverage.glyphs:
                    if g1 not in names:
                        continue
                    row = st.Class1Record[cd1.get(g1, 0)].Class2Record
                    for g2 in names:
                        if (g1, g2) in decided:
                            continue
                        rec = row[cd2.get(g2, 0)]
                        v = getattr(rec.Value1, "XAdvance", 0) if rec.Value1 else 0
                        decided[(g1, g2)] = v or 0
        for k, v in decided.items():
            total[k] = total.get(k, 0) + v
    return {k: v for k, v in total.items() if v}


def load_text_face(path, pred):
    font = TTFont(path)
    cmap = font.getBestCmap()
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    glyphset = font.getGlyphSet()
    face = Face(path.stem)
    face.pred = pred

    for cp in sorted(TEXT_REPERTOIRE | set(TEXT_FALLBACK)):
        src = TEXT_FALLBACK.get(cp, cp)
        if src not in cmap:
            raise SystemExit(f"{path.name} has no glyph for U+{src:04X}")
        face.cmap[cp] = cmap[src]

    # Glyphs in the order of the first code point that reaches them, so
    # that the four faces line up and a gid's neighbours are its
    # neighbours in the alphabet; then whatever the composites are built
    # from that has no code point of its own.
    order = []
    for cp in sorted(face.cmap):
        if face.cmap[cp] not in order:
            order.append(face.cmap[cp])
    extra = []
    for name in order:
        g = glyf[name]
        if g.isComposite():
            for c in g.components:
                if c.glyphName not in order and c.glyphName not in extra:
                    extra.append(c.glyphName)
    for name in order + sorted(extra, key=font.getGlyphID):
        g = Glyph(name)
        g.adv = hmtx[name][0]
        tt = glyf[name]
        if tt.isComposite():
            g.comps = []
            for c in tt.components:
                if hasattr(c, "transform") or not hasattr(c, "x"):
                    raise SystemExit(f"{name}: a component that is not a plain offset")
                if glyf[c.glyphName].isComposite():
                    raise SystemExit(f"{name}: a component that is itself composite")
                g.comps.append((c.glyphName, int(c.x), int(c.y), None))
        else:
            g.contours = quad_contours(glyf, name)
        g.bbox, g.ink = ink_box(glyphset, name)
        face.add(g)

    face.kern = pair_kerning(font, [g.name for g in face.glyphs if g.name in order])
    head = font["head"]
    os2 = font["OS/2"]
    face.em = head.unitsPerEm
    face.asc = font["hhea"].ascent
    face.desc = font["hhea"].descent
    face.xh = os2.sxHeight
    face.cap = os2.sCapHeight
    return face, font, glyphset


def gsub_single(font, tag):
    """The single substitutions of a GSUB feature, as a name mapping."""
    out = {}
    gsub = font["GSUB"].table
    for fr in gsub.FeatureList.FeatureRecord:
        if fr.FeatureTag != tag:
            continue
        for li in fr.Feature.LookupListIndex:
            lookup = gsub.LookupList.Lookup[li]
            for st in lookup.SubTable:
                if lookup.LookupType == 1:
                    for a, b in st.mapping.items():
                        out.setdefault(a, b)
                elif lookup.LookupType == 3:
                    for a, alts in st.alternates.items():
                        out.setdefault(a, list(alts))
    return out


def load_math_face(path):
    """Lete Sans Math: its outlines (CFF, so cubic) and its MATH table.

    Three GSUB features are baked in: cv11, the single-story g that
    matches Lato's italic, goes straight into the cmap; ssty, the script
    and scriptscript alternates, becomes a table the layout picks from by
    style; dtls, the dotless forms under an accent, becomes another.
    """
    font = TTFont(path)
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]
    glyphset = font.getGlyphSet()
    gid_of = font.getGlyphID
    face = Face(path.stem)
    face.cubic = True
    face.pred = None

    cv11 = gsub_single(font, "cv11")
    ssty = gsub_single(font, "ssty")
    dtls = gsub_single(font, "dtls")

    missing = []
    for cp in sorted(MATH_REPERTOIRE):
        if cp in cmap:
            face.cmap[cp] = cv11.get(cmap[cp], cmap[cp])
        elif unicodedata.category(chr(cp)) != "Cn":
            # The holes in the math alphabets, whose letters live in the
            # Letterlike Symbols block, are not characters at all.
            missing.append(cp)

    order = []
    for cp in sorted(face.cmap):
        if face.cmap[cp] not in order:
            order.append(face.cmap[cp])

    math = font["MATH"].table
    mv = math.MathVariants

    def constructions(cov, cons, cap):
        out = {}
        if cov is None:
            return out
        for g, c in zip(cov.glyphs, cons):
            recs = c.MathGlyphVariantRecord or []
            keep = [(r.VariantGlyph, r.AdvanceMeasurement) for r in recs]
            if cap is not None and c.GlyphAssembly is not None:
                keep = [v for k, v in enumerate(keep)
                        if k == 0 or v[1] <= cap * font["head"].unitsPerEm]
            asm = None
            if c.GlyphAssembly is not None:
                a = c.GlyphAssembly
                asm = (a.ItalicsCorrection.Value,
                       [(p.glyph, p.StartConnectorLength, p.EndConnectorLength,
                         p.FullAdvance, p.PartFlags & 1) for p in a.PartRecords])
            out[g] = (keep, asm)
        return out

    vert_all = constructions(mv.VertGlyphCoverage, mv.VertGlyphConstruction, MAX_VARIANT)
    horiz_all = constructions(mv.HorizGlyphCoverage, mv.HorizGlyphConstruction, None)

    extra = set()
    for g in list(order):
        if g in dtls:
            extra.add(dtls[g])
    for g in order + sorted(extra):
        for table in (vert_all, horiz_all):
            if g in table:
                var, asm = table[g]
                extra.update(v for v, _ in var)
                if asm:
                    extra.update(p[0] for p in asm[1])
    # The letters, digits and primes ssty_kept names bring their script
    # alternate along, and so do their dotless forms.
    scripted = {face.cmap[cp] for cp in face.cmap if ssty_kept(cp)}
    scripted |= {dtls[g] for g in scripted if g in dtls}
    face_ssty = {}
    for g in sorted(scripted):
        alts = ssty.get(g)
        if alts:
            face_ssty[g] = alts[0]
            extra.add(alts[0])
    extra -= set(order)
    names = order + sorted(extra, key=gid_of)

    for name in names:
        g = Glyph(name)
        g.adv = hmtx[name][0]
        g.contours = cubic_contours(glyphset, name)
        g.bbox, g.ink = ink_box(glyphset, name)
        face.add(g)

    face.kern = pair_kerning(font, order)

    gi = math.MathGlyphInfo
    italic = {}
    ic = gi.MathItalicsCorrectionInfo
    for g, v in zip(ic.Coverage.glyphs, ic.ItalicsCorrection):
        if g in face.index and v.Value:
            italic[g] = v.Value
    accent = {}
    ta = gi.MathTopAccentAttachment
    for g, v in zip(ta.TopAccentCoverage.glyphs, ta.TopAccentAttachment):
        if g in face.index:
            accent[g] = v.Value
    extended = set(gi.ExtendedShapeCoverage.glyphs) & set(face.index) \
        if gi.ExtendedShapeCoverage else set()
    kerns = {}
    if gi.MathKernInfo:
        for g, rec in zip(gi.MathKernInfo.MathKernCoverage.glyphs,
                          gi.MathKernInfo.MathKernInfoRecords):
            if g not in face.index:
                continue
            corners = []
            for k in (rec.TopRightMathKern, rec.TopLeftMathKern,
                      rec.BottomRightMathKern, rec.BottomLeftMathKern):
                if k is None:
                    corners.append(([], [0]))
                else:
                    corners.append(([h.Value for h in k.CorrectionHeight],
                                    [v.Value for v in k.KernValue]))
            kerns[g] = corners
    present = set(face.index)
    face.math = {
        "italic": italic,
        "accent": accent,
        "extended": extended,
        "kern": kerns,
        "vert": {g: c for g, c in vert_all.items() if g in present},
        "horiz": {g: c for g, c in horiz_all.items() if g in present},
        "ssty": face_ssty,
        "dtls": {a: b for a, b in dtls.items() if a in present and b in present},
        "constants": [getattr(math.MathConstants, n).Value
                      if hasattr(getattr(math.MathConstants, n), "Value")
                      else getattr(math.MathConstants, n)
                      for n in MATH_CONSTANTS],
        "overlap": mv.MinConnectorOverlap,
    }
    head = font["head"]
    os2 = font["OS/2"]
    face.em = head.unitsPerEm
    face.asc = font["hhea"].ascent
    face.desc = font["hhea"].descent
    face.xh = os2.sxHeight
    face.cap = os2.sCapHeight
    if missing:
        print(f"{path.name}: not in the font, left out: "
              + " ".join(f"U+{c:04X}" for c in missing))
    return face, font, glyphset


def reduced_math_font(path):
    """Lete Sans Math cut down to what fplotlib stores of it.

    The ssty substitutions are those of the glyphs that keep a script
    alternate, with that alternate for both script levels, and the
    vertical size variants are those MAX_VARIANT keeps. XeTeX and Typst
    typeset the reference formulas with this font, so that they choose
    exactly among the glyphs fplotlib has.
    """
    face, font, _ = load_math_face(path)
    keep = face.math["ssty"]
    gsub = font["GSUB"].table
    for fr in gsub.FeatureList.FeatureRecord:
        if fr.FeatureTag != "ssty":
            continue
        for li in fr.Feature.LookupListIndex:
            lookup = gsub.LookupList.Lookup[li]
            for st in lookup.SubTable:
                if lookup.LookupType == 3:
                    st.alternates = {a: [keep[a], keep[a]]
                                     for a in st.alternates if a in keep}
                elif lookup.LookupType == 1:
                    st.mapping = {a: keep[a] for a in st.mapping if a in keep}
    mv = font["MATH"].table.MathVariants
    vert = face.math["vert"]
    for g, c in zip(mv.VertGlyphCoverage.glyphs, mv.VertGlyphConstruction):
        if g in vert:
            kept = {v for v, _ in vert[g][0]}
            c.MathGlyphVariantRecord = [r for r in c.MathGlyphVariantRecord
                                        if r.VariantGlyph in kept]
            c.VariantCount = len(c.MathGlyphVariantRecord)
    return font


# --- outlines as the decoder walks them ------------------------------


def quad_to_cubic(p0, q, p2):
    """Exact degree elevation of a quadratic Bezier to a cubic."""
    c1 = (p0[0] + 2.0 / 3.0 * (q[0] - p0[0]), p0[1] + 2.0 / 3.0 * (q[1] - p0[1]))
    c2 = (p2[0] + 2.0 / 3.0 * (q[0] - p2[0]), p2[1] + 2.0 / 3.0 * (q[1] - p2[1]))
    return c1, c2


def contours_to_path(contours, cubic):
    """(verbs, points) for stored contours, the way fplotlib_glyphs does it.

    This is the reference for the Fortran. A quadratic contour is turned
    to start at an on-curve point, consecutive control points have the
    on-curve point between them put back at their midpoint, and every
    quadratic is elevated to a cubic. A cubic contour already starts on
    the curve and takes its control points two at a time.
    """
    verbs, pts = [], []
    for cpts, con in contours:
        n = len(cpts)
        if cubic:
            seq = [(cpts[j], con[j]) for j in range(1, n)] + [(cpts[0], True)]
            start = cpts[0]
        else:
            first = next((j for j in range(n) if con[j]), None)
            if first is None:
                start = ((cpts[0][0] + cpts[-1][0]) / 2.0,
                         (cpts[0][1] + cpts[-1][1]) / 2.0)
                seq = [(p, False) for p in cpts] + [(start, True)]
            else:
                start = cpts[first]
                seq = [(cpts[(first + j) % n], con[(first + j) % n])
                       for j in range(1, n)] + [(start, True)]
        cur = start
        verbs.append(VERB_MOVE)
        pts.append(start)
        i = 0
        while i < len(seq):
            p, on = seq[i]
            if on:
                if i < len(seq) - 1:
                    verbs.append(VERB_LINE)
                    pts.append(p)
                cur = p
                i += 1
            elif cubic:
                c2, end = seq[i + 1][0], seq[i + 2][0]
                verbs.append(VERB_CUBIC)
                pts.extend([p, c2, end])
                cur = end
                i += 3
            else:
                nxt, non = seq[i + 1]
                if non:
                    end = nxt
                    i += 2
                else:
                    end = ((p[0] + nxt[0]) / 2.0, (p[1] + nxt[1]) / 2.0)
                    i += 1
                c1, c2 = quad_to_cubic(cur, p, end)
                verbs.append(VERB_CUBIC)
                pts.extend([c1, c2, end])
                cur = end
        verbs.append(VERB_CLOSE)
    return verbs, pts


def pen_path(glyphset, name):
    """(verbs, points) as the font's own pen draws them, for checking."""
    pen = DecomposingRecordingPen(glyphset)
    glyphset[name].draw(pen)
    verbs, pts = [], []
    cur = start = (0.0, 0.0)
    for op, args in pen.value:
        if op == "moveTo":
            cur = start = args[0]
            verbs.append(VERB_MOVE)
            pts.append(cur)
        elif op == "lineTo":
            cur = args[0]
            verbs.append(VERB_LINE)
            pts.append(cur)
        elif op == "curveTo":
            for i in range(0, len(args), 3):
                verbs.append(VERB_CUBIC)
                pts.extend(args[i:i + 3])
                cur = args[i + 2]
        elif op == "qCurveTo":
            pl = list(args)
            if pl[-1] is None:
                pl = pl[:-1]
                mid = ((pl[0][0] + pl[-1][0]) / 2.0, (pl[0][1] + pl[-1][1]) / 2.0)
                cur = start = mid
                verbs.append(VERB_MOVE)
                pts.append(cur)
                pl = pl + [mid]
            for i in range(len(pl) - 1):
                q, nxt = pl[i], pl[i + 1]
                end = nxt if i == len(pl) - 2 else ((q[0] + nxt[0]) / 2.0,
                                                   (q[1] + nxt[1]) / 2.0)
                c1, c2 = quad_to_cubic(cur, q, end)
                verbs.append(VERB_CUBIC)
                pts.extend([c1, c2, end])
                cur = end
        elif op == "closePath":
            verbs.append(VERB_CLOSE)
            cur = start
        elif op == "endPath":
            verbs.append(VERB_CLOSE)
        else:
            raise SystemExit(f"unhandled pen op {op}")
    return verbs, pts


def path_cycles(verbs, pts):
    """A path as one closed cycle of segments per contour, the implied
    line back to the start put back, so that two ways of drawing the same
    closed contour compare equal whichever point they start from."""
    cycles = []
    i = 0
    for v in verbs:
        if v == VERB_MOVE:
            start = cur = pts[i]
            segs = []
            i += 1
        elif v == VERB_LINE:
            # A line of no length draws nothing, and the stored contours
            # leave such lines out.
            if pts[i] != cur:
                segs.append((v, (pts[i],)))
            cur = pts[i]
            i += 1
        elif v == VERB_CUBIC:
            segs.append((v, tuple(pts[i:i + 3])))
            cur = pts[i + 2]
            i += 3
        else:
            if cur != start:
                segs.append((VERB_LINE, (start,)))
            cycles.append(segs)
    return cycles


def same_shape(a, b, tol=1e-9):
    """True when two paths are the same closed contours, started anywhere."""
    ca, cb = path_cycles(*a), path_cycles(*b)
    if len(ca) != len(cb):
        return False
    for x, y in zip(ca, cb):
        if len(x) != len(y):
            return False
        n = len(x)
        if n == 0:
            continue
        if not any(
            all(
                x[(s + j) % n][0] == y[j][0]
                and all(abs(p - q) < tol for u, v in zip(x[(s + j) % n][1], y[j][1])
                        for p, q in zip(u, v))
                for j in range(n)
            )
            for s in range(n)
        ):
            return False
    return True


def resolved(face, g, faces=None):
    """A glyph's contours with its components put in place, in the font
    units of its face; a component from another face is scaled from that
    face's units."""
    if g.comps is None:
        return g.contours
    out = []
    for name, dx, dy, src in g.comps:
        f = face if src is None else faces[src]
        k = face.em / f.em
        for pts, on in resolved(f, f.glyphs[f.index[name]], faces):
            out.append(([(x * k + dx, y * k + dy) for x, y in pts], on))
    return out


def path_polylines(verbs, pts, n=40):
    """A path as one polyline per contour, each cubic cut into n chords."""
    out, poly, cur, start, i = [], [], None, None, 0
    t = np.linspace(0.0, 1.0, n + 1)[1:, None]
    for v in verbs:
        if v == VERB_MOVE:
            cur = start = pts[i]
            poly = [cur]
            i += 1
        elif v == VERB_LINE:
            cur = pts[i]
            poly.append(cur)
            i += 1
        elif v == VERB_CUBIC:
            p0, p1, p2, p3 = (np.array(q, dtype=float) for q in (cur, *pts[i:i + 3]))
            poly.extend(map(tuple, (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1
                            + 3 * (1 - t) * t * t * p2 + t ** 3 * p3))
            cur = pts[i + 2]
            i += 3
        else:
            poly.append(start)
            out.append(np.array(poly, dtype=float))
    return out


def _to_polyline(points, lines):
    """The distance from each point to the nearest of the polylines."""
    best = np.full(len(points), np.inf)
    for q in lines:
        a, b = q[:-1], q[1:]
        ab = b - a
        ll = np.maximum((ab ** 2).sum(1), 1e-12)
        t = np.clip(((points[:, None, :] - a[None]) * ab[None]).sum(2) / ll[None], 0, 1)
        c = a[None] + t[..., None] * ab[None]
        best = np.minimum(best, np.sqrt(((points[:, None, :] - c) ** 2).sum(2)).min(1))
    return best


def deviation(a, b):
    """How far apart two paths are at most, in their units: the larger of
    the distances from either one's curves to the other's."""
    pa, pb = path_polylines(*a), path_polylines(*b)
    if len(pa) != len(pb):
        return math.inf
    return max(_to_polyline(np.vstack(pa), pb).max(), _to_polyline(np.vstack(pb), pa).max())


def math_counterparts(fi, cp, mface):
    """The Lete glyphs that may draw text face fi's glyph for cp."""
    m = mface.cmap
    out = [m.get(cp)]
    ch = chr(cp)
    if fi == 1:
        if "a" <= ch <= "z":
            out.append(m.get(0x1D41A + cp - 0x61))
        elif "A" <= ch <= "Z":
            out.append(m.get(0x1D400 + cp - 0x41))
        elif "0" <= ch <= "9":
            out.append(m.get(0x1D7CE + cp - 0x30))
        elif 0x3B1 <= cp <= 0x3C9:
            out.append(m.get(0x1D6C2 + cp - 0x3B1))
        elif 0x391 <= cp <= 0x3A9:
            out.append(m.get(0x1D6A8 + cp - 0x391))
    elif fi == 2:
        if "a" <= ch <= "z":
            out.append(m.get(0x210E if ch == "h" else 0x1D44E + cp - 0x61))
        elif "A" <= ch <= "Z":
            out.append(m.get(0x1D434 + cp - 0x41))
        elif 0x3B1 <= cp <= 0x3C9:
            out.append(m.get(0x1D6FC + cp - 0x3B1))
        elif 0x391 <= cp <= 0x3A9:
            out.append(m.get(0x1D6E2 + cp - 0x391))
    return [n for n in out if n]


def refit_contours(glyphset, name, grid):
    """A TrueType glyph refitted with cubics and put on a grid."""
    rec = RecordingPen()
    glyphset[name].draw(Qu2CuPen(rec, max_err=REFIT_ERR, all_cubic=True))

    def q(p):
        return (grid * round(p[0] / grid), grid * round(p[1] / grid))
    contours, pts, on = [], None, None
    for op, args in rec.value:
        if op == "moveTo":
            pts, on = [q(args[0])], [True]
        elif op == "lineTo":
            pts.append(q(args[0]))
            on.append(True)
        elif op == "curveTo" and len(args) % 3 == 0:
            for k in range(0, len(args), 3):
                pts.extend([q(args[k]), q(args[k + 1]), q(args[k + 2])])
                on.extend([False, False, True])
        elif op in ("closePath", "endPath"):
            if len(pts) > 1 and pts[-1] == pts[0] and on[-1]:
                pts.pop()
                on.pop()
            # A line of no length, which putting on the grid can make.
            k = 1
            while k < len(pts):
                if on[k] and on[k - 1] and pts[k] == pts[k - 1]:
                    del pts[k], on[k]
                else:
                    k += 1
            contours.append((pts, on))
        else:
            return None
    return contours


def refit_text_faces(faces, glyphsets):
    """Lato's outlines as Lete's or refitted with cubics; see LATO_OSCALE."""
    mi = len(faces) - 1
    mf = faces[mi]
    aliased = refitted = 0
    for fi, (face, gs) in enumerate(zip(faces[:mi], glyphsets[:mi])):
        face.cubic = True
        face.oscale = LATO_OSCALE
        face.xref = mi
        k = face.em // mf.em
        names = {}
        for cp, n in face.cmap.items():
            names.setdefault(n, cp)
        for g in face.glyphs:
            if g.comps is not None:
                g.comps = [(n, LATO_OSCALE * round(dx / LATO_OSCALE),
                            LATO_OSCALE * round(dy / LATO_OSCALE), src)
                           for n, dx, dy, src in g.comps]
                continue
            if not g.contours:
                continue
            want = pen_path(gs, g.name)
            best = None
            for mn in (math_counterparts(fi, names[g.name], mf) if g.name in names else []):
                mg = mf.glyphs[mf.index[mn]]
                v, pts = contours_to_path(mg.contours, True)
                guess = round(g.bbox[0] / k - mg.bbox[0])
                for dx in (guess - 1, guess, guess + 1):
                    d = deviation((v, [(x * k + dx * k, y * k) for x, y in pts]), want)
                    if d <= ALIAS_TOL and (best is None or d < best[0]):
                        best = (d, mn, dx * k)
            if best is not None:
                g.comps = [(best[1], best[2], 0, mi)]
                g.contours = []
                aliased += 1
                continue
            new = refit_contours(gs, g.name, LATO_OSCALE)
            if new is None:
                raise SystemExit(f"{face.tag} {g.name}: qu2cu left a quadratic")
            d = deviation(contours_to_path(new, True), want)
            if d > REFIT_TOL:
                raise SystemExit(f"{face.tag} {g.name}: refitted {d:.2f} units off")
            g.contours = new
            refitted += 1
    print(f"Lato: {aliased} glyphs drawn as Lete's, {refitted} refitted with cubics")


# --- the bit stream ---------------------------------------------------


def zigzag(v):
    """Signed to unsigned, keeping small magnitudes small."""
    return 2 * v if v >= 0 else -2 * v - 1


def unzigzag(u):
    return u // 2 if u % 2 == 0 else -(u + 1) // 2


# The stream is written with an adaptive binary range coder, the one LZMA
# uses: every bit is coded with a probability, 11 bits wide, that the bits
# before it in the same context have moved towards them by 1/2**MOVE_BITS
# each. A value is binarized: a flag is one such bit; a delta, folded to
# a non-negative number u, is its magnitude class (the position of u's
# leading one, 0 for zero) spelled out as five bits down a binary tree,
# then the bit under the leading one, then the rest of u's bits at a
# fixed even chance; a gamma is Elias gamma, its run of zeros modelled
# bit by bit and its low bits at even chance; and raw bits are at even
# chance. Each kind of value has a context of its own, and the points of
# an outline have contexts that say what the point before them was.
MOVE_BITS = 3

# Delta contexts.
D_ADV, D_CX, D_CY, D_INK, D_ITAL, D_ACC, D_MKH, D_MKV, D_VAR, D_ASM = range(10)
D_CIDX = 10  # component index, from the last composite's: + 0 first, 1 later
D_KERN = 12  # kerning: + the previous value's class in the row
D_OX = 32    # outline x: + ((on * 2 + previous on) * 12 + previous x class) * 2
             #             + whether the previous y delta was zero
D_OY = 128   # outline y: + ((on * 2 + previous on) * 8 + previous y class) * 8 + x class
D_RX = 384   # difference x: + previous x class
D_RY = 396   # difference y: + previous y class * 8 + x class
ND = 460
# Flag contexts.
B_ON = 0     # on the curve: + previous on * 4 + the one before * 2 + cubic
(B_COMP, B_RESID, B_XREF, B_INK, B_CMAP, B_ITAL, B_ACC, B_EXT, B_MKERN, B_ASM,
 B_PARTX) = range(8, 19)
NB = 19
# Gamma contexts.
(G_NCOMP, G_NCONT, G_NPTS, G_CMAPN, G_CMAPSTEP, G_KCLS, G_KROW, G_KSTEP, G_MKN,
 G_CONS, G_NVAR, G_NPART, G_PAIRS) = range(13)
NG = 13


def cls(v):
    """The magnitude class of a delta."""
    return zigzag(v).bit_length()


def outline_ctx(on, onp, cpx, cpy, cdx):
    """The contexts of a point's x and y deltas."""
    k = on * 2 + onp
    return (D_OX + (k * 12 + min(cpx, 11)) * 2 + (1 if cpy == 0 else 0),
            D_OY + (k * 8 + min(cpy, 7)) * 8 + min(cdx, 7))


def resid_ctx(cpx, cpy, cdx):
    """The contexts of a point's x and y differences."""
    return D_RX + min(cpx, 11), D_RY + min(cpy, 7) * 8 + min(cdx, 7)


class Model:
    """The probabilities, all starting at even."""

    def __init__(self):
        self.d = [[1024] * 32 for _ in range(ND)]
        self.m = [[1024] * 96 for _ in range(ND)]
        self.b = [1024] * NB
        self.g = [[1024] * 33 for _ in range(NG)]
        self.t = [[1024] * 512 for _ in range(2)]


class Writer(Model):
    """The range encoder, with the binarization of each kind of value."""

    def __init__(self):
        super().__init__()
        self.low = 0
        self.range = 0xFFFFFFFF
        self.cache = 0
        self.cache_size = 1
        self.out = bytearray()

    def _shift_low(self):
        if self.low < 0xFF000000 or self.low >= 1 << 32:
            carry = self.low >> 32
            temp = self.cache
            while True:
                self.out.append((temp + carry) & 0xFF)
                temp = 0xFF
                self.cache_size -= 1
                if self.cache_size == 0:
                    break
            self.cache = (self.low >> 24) & 0xFF
        self.cache_size += 1
        self.low = (self.low & 0x00FFFFFF) << 8

    def _norm(self):
        while self.range < 1 << 24:
            self.range <<= 8
            self._shift_low()

    def _bit(self, probs, i, bit):
        p = probs[i]
        bound = (self.range >> 11) * p
        if bit:
            self.low += bound
            self.range -= bound
            probs[i] = p - (p >> MOVE_BITS)
        else:
            self.range = bound
            probs[i] = p + ((2048 - p) >> MOVE_BITS)
        self._norm()

    def raw(self, value, n):
        if value < 0 or value >= 1 << n:
            raise SystemExit(f"{value} does not fit in {n} bits")
        for k in range(n - 1, -1, -1):
            self.range >>= 1
            if (value >> k) & 1:
                self.low += self.range
            self._norm()

    def flag(self, ctx, bit):
        self._bit(self.b, ctx, 1 if bit else 0)

    def gamma(self, ctx, n):
        if n < 1:
            raise SystemExit(f"gamma of {n}")
        z = n.bit_length() - 1
        for i in range(z):
            self._bit(self.g[ctx], min(i, 32), 0)
        self._bit(self.g[ctx], min(z, 32), 1)
        self.raw(n - (1 << z), z)

    def tree(self, side, v, n):
        """v in n bits, down a binary tree of probabilities."""
        node = 1
        for k in range(n - 1, -1, -1):
            b = (v >> k) & 1
            self._bit(self.t[side], node, b)
            node = 2 * node + b

    def delta(self, ctx, v):
        u = zigzag(v)
        c = u.bit_length()
        if c > 31:
            raise SystemExit(f"delta {v} too large")
        node = 1
        for k in range(4, -1, -1):
            b = (c >> k) & 1
            self._bit(self.d[ctx], node, b)
            node = 2 * node + b
        if c >= 2:
            b1 = (u >> (c - 2)) & 1
            self._bit(self.m[ctx], c, b1)
            if c >= 3:
                self._bit(self.m[ctx], 32 + 2 * c + b1, (u >> (c - 3)) & 1)
                self.raw(u & ((1 << (c - 3)) - 1), c - 3)

    def bytes(self):
        for _ in range(5):
            self._shift_low()
        out = bytes(self.out)
        return out + bytes((-len(out)) % 4)


class Reader(Model):
    """The range decoder, mirroring Writer."""

    def __init__(self, blob):
        super().__init__()
        self.blob = blob
        self.pos = 0
        self.range = 0xFFFFFFFF
        self.code = 0
        for _ in range(5):
            self.code = (self.code << 8) | self._byte()

    def _byte(self):
        b = self.blob[self.pos] if self.pos < len(self.blob) else 0
        self.pos += 1
        return b

    def _norm(self):
        while self.range < 1 << 24:
            self.range <<= 8
            self.code = ((self.code << 8) | self._byte()) & 0xFFFFFFFF

    def _bit(self, probs, i):
        p = probs[i]
        bound = (self.range >> 11) * p
        if self.code < bound:
            self.range = bound
            probs[i] = p + ((2048 - p) >> MOVE_BITS)
            b = 0
        else:
            self.code -= bound
            self.range -= bound
            probs[i] = p - (p >> MOVE_BITS)
            b = 1
        self._norm()
        return b

    def raw(self, n):
        v = 0
        for _ in range(n):
            self.range >>= 1
            b = 1 if self.code >= self.range else 0
            if b:
                self.code -= self.range
            v = 2 * v + b
            self._norm()
        return v

    def flag(self, ctx):
        return self._bit(self.b, ctx)

    def gamma(self, ctx):
        z = 0
        while self._bit(self.g[ctx], min(z, 32)) == 0:
            z += 1
        return (1 << z) | self.raw(z)

    def tree(self, side, n):
        node = 1
        for _ in range(n):
            node = 2 * node + self._bit(self.t[side], node)
        return node - (1 << n)

    def delta(self, ctx):
        node = 1
        for _ in range(5):
            node = 2 * node + self._bit(self.d[ctx], node)
        c = node - 32
        if c == 0:
            return 0
        u = 1
        if c >= 2:
            b1 = self._bit(self.m[ctx], c)
            u = 2 | b1
            if c >= 3:
                u = (2 * u | self._bit(self.m[ctx], 32 + 2 * c + b1)) << (c - 3) \
                    | self.raw(c - 3)
        return unzigzag(u)


def nbits(n):
    """Bits for a number in 0..n."""
    return max(n, 1).bit_length()


def best_storage(contours, cubic, delta_cost):
    """Turn each contour to the point it is cheapest to store it from.

    A closed contour draws the same shape whichever of its points comes
    first, so the rotation is the generator's to choose: exactly one edge
    of the cycle goes unstored, the one the contour is broken at, and the
    step in from the contour before takes its place. A cubic contour has
    to start on the curve, which is where the decoder starts drawing it.
    """
    stored, turns = [], []
    cur = (0, 0)
    for pts, on in contours:
        n = len(pts)
        cands = [k for k in range(n) if on[k]] if cubic else list(range(n))
        _, k = min(
            (delta_cost(cur, pts[k]) - delta_cost(pts[(k - 1) % n], pts[k]), k)
            for k in cands
        )
        stored.append(([pts[(k + i) % n] for i in range(n)],
                       [on[(k + i) % n] for i in range(n)]))
        turns.append(k)
        cur = pts[(k - 1) % n]
    return stored, turns


def turned(contours, turns):
    """Contours each started at the point turns names."""
    return [([pts[(k + i) % len(pts)] for i in range(len(pts))],
             [on[(k + i) % len(pts)] for i in range(len(pts))])
            for (pts, on), k in zip(contours, turns)]


def plan_residuals(face):
    """Which of the math face's glyphs are stored as the difference from
    another: a script-size alternate from its glyph, a size variant from
    the variant before it. Each must have the same contours, point for
    point, as the glyph it is stored from, which must come before it, and
    the difference must be the cheaper to store (by a rough count)."""
    m = face.math
    pairs = [(alt, base) for base, alt in m["ssty"].items()]
    for key in ("vert", "horiz"):
        for gname, (var, _) in m[key].items():
            names = [gname] + [v for v, _ in var if v != gname]
            pairs += [(names[k], names[k - 1]) for k in range(1, len(names))]

    def rough(vals):
        return sum(2.5 + max(zigzag(v).bit_length() - 1, 0) for v in vals)
    n = 0
    for name, ref in pairs:
        g, r = face.glyphs[face.index[name]], face.glyphs[face.index[ref]]
        if g.ref is not None or g.comps is not None or r.comps is not None:
            continue
        if face.index[ref] >= face.index[name] or not g.contours:
            continue
        if [(len(p), o) for p, o in g.contours] != [(len(p), o) for p, o in r.contours]:
            continue
        plain, diff, px, py, rx0, ry0 = [], [], 0, 0, 0, 0
        for (p, _), (q, _) in zip(g.contours, r.contours):
            for (x, y), (xr, yr) in zip(p, q):
                plain += [x - px, y - py]
                diff += [(x - xr) - rx0, (y - yr) - ry0]
                px, py, rx0, ry0 = x, y, x - xr, y - yr
        if rough(diff) < rough(plain):
            g.ref = ref
            n += 1
    print(f"{face.tag}: {n} glyphs stored as differences from another")


def computed_box(face, g, faces):
    """The ink box the decoder works out for itself: the extremes of a
    simple glyph's points, curve and control points alike, or the union
    of a composite's components' ink boxes, offset (and scaled, for a
    component from another face)."""
    if g.comps:
        boxes = []
        for name, dx, dy, src in g.comps:
            f = face if src is None else faces[src]
            c = f.glyphs[f.index[name]]
            k = face.em // f.em
            if c.ink:
                x0, y0, x1, y1 = c.bbox
                boxes.append((x0 * k + dx, y0 * k + dy, x1 * k + dx, y1 * k + dy))
        return (min(b[0] for b in boxes), min(b[1] for b in boxes),
                max(b[2] for b in boxes), max(b[3] for b in boxes))
    xs = [x for pts, _ in g.contours for x, _ in pts]
    ys = [y for pts, _ in g.contours for _, y in pts]
    return min(xs), min(ys), max(xs), max(ys)


def kern_classes(face):
    """Pair kerning as left and right classes and the non-zero cells.

    Glyphs whose rows (or columns) of the pair table are identical share a
    class; class 0 is the glyphs that are never kerned on that side.
    """
    names = [g.name for g in face.glyphs]
    rows, cols = {}, {}
    for (a, b), v in face.kernq.items():
        rows.setdefault(a, []).append((face.index[b], v))
        cols.setdefault(b, []).append((face.index[a], v))
    lclass = [0] * len(names)
    rclass = [0] * len(names)
    lkeys, rkeys = {}, {}
    for i, n in enumerate(names):
        if n in rows:
            key = tuple(sorted(rows[n]))
            lclass[i] = lkeys.setdefault(key, len(lkeys) + 1)
        if n in cols:
            key = tuple(sorted(cols[n]))
            rclass[i] = rkeys.setdefault(key, len(rkeys) + 1)
    cells = {}
    for (a, b), v in face.kernq.items():
        cells[(lclass[face.index[a]], rclass[face.index[b]])] = v
    return lclass, rclass, len(lkeys), len(rkeys), cells


def kern_predictor(src, lclass, rclass):
    """The prediction of each cell of a face's kerning from face src's.

    A class is represented by its first glyph, and the prediction is what
    src kerns the glyphs at the same indices by; the decoder does the
    same, having unpacked src first.
    """
    slc, src_rc, _, _, scells = kern_classes(src)
    first_l, first_r = {}, {}
    for i, c in enumerate(lclass):
        first_l.setdefault(c, i)
    for i, c in enumerate(rclass):
        first_r.setdefault(c, i)
    ns = len(src.glyphs)

    def pred(lc, rc):
        i, j = first_l[lc], first_r[rc]
        if i >= ns or j >= ns:
            return 0
        return scells.get((slc[i], src_rc[j]), 0)
    return pred


def encode(faces):
    """The whole table as one coded stream; see fplotlib_glyphs for the layout."""
    w = Writer()
    for fi, face in enumerate(faces):
        lbits = nbits(len(face.glyphs))
        cubic = 1 if face.cubic else 0
        prev_adv = 0
        last_comp = {}
        for k, g in enumerate(face.glyphs):
            if face.pred is not None and k < len(faces[face.pred].glyphs):
                guess = faces[face.pred].glyphs[k].adv
            else:
                guess = prev_adv
            w.delta(D_ADV, g.adv - guess)
            prev_adv = g.adv
            w.flag(B_COMP, g.comps is not None)
            if g.comps is not None:
                w.gamma(G_NCOMP, len(g.comps))
                for j, (name, dx, dy, src) in enumerate(g.comps):
                    if face.xref is not None:
                        w.flag(B_XREF, src is not None)
                    idx = (face if src is None else faces[src]).index[name]
                    key = (src is not None, min(j, 1))
                    w.delta(D_CIDX + min(j, 1), idx - last_comp.get(key, 0))
                    last_comp[key] = idx
                    w.delta(D_CX, dx // face.oscale)
                    w.delta(D_CY, dy // face.oscale)
            else:
                if face.resid:
                    w.flag(B_RESID, g.ref is not None)
                if g.ref is not None:
                    r = face.glyphs[face.index[g.ref]]
                    w.raw(face.index[g.ref], lbits)
                    px = py = cpx = cpy = 0
                    for (pts, _), (rpts, _) in zip(g.contours, r.contours):
                        for (x, y), (xr, yr) in zip(pts, rpts):
                            dx = (x - xr - px) // face.oscale
                            dy = (y - yr - py) // face.oscale
                            cx, cy = resid_ctx(cpx, cpy, cls(dx))
                            w.delta(cx, dx)
                            w.delta(cy, dy)
                            px, py, cpx, cpy = x - xr, y - yr, cls(dx), cls(dy)
                else:
                    w.gamma(G_NCONT, len(g.contours) + 1)
                    for pts, _ in g.contours:
                        w.gamma(G_NPTS, len(pts))
                    px = py = cpx = cpy = 0
                    onp = onp2 = 1
                    for pts, on in g.contours:
                        for (x, y), o in zip(pts, on):
                            o = 1 if o else 0
                            w.flag(B_ON + onp * 4 + onp2 * 2 + cubic, o)
                            dx = (x - px) // face.oscale
                            dy = (y - py) // face.oscale
                            cx, cy = outline_ctx(o, onp, cpx, cpy, cls(dx))
                            w.delta(cx, dx)
                            w.delta(cy, dy)
                            px, py, cpx, cpy = x, y, cls(dx), cls(dy)
                            onp2, onp = onp, o
            if g.comps or g.contours:
                cx0, cy0, cx1, cy1 = computed_box(face, g, faces)
                x0, y0, x1, y1 = g.bbox
                same = (x0, y0, x1, y1) == (cx0, cy0, cx1, cy1)
                w.flag(B_INK, not same)
                if not same:
                    for v in (x0 - cx0, y0 - cy0, cx1 - x1, cy1 - y1):
                        w.delta(D_INK, v)

        # The cmap, in code point order: the step to the next code point,
        # and the glyph, which is usually the one after the last.
        w.gamma(G_CMAPN, len(face.cmap) + 1)
        prev_cp = 0
        prev = -1
        for cp in sorted(face.cmap):
            i = face.index[face.cmap[cp]]
            w.gamma(G_CMAPSTEP, cp - prev_cp)
            w.flag(B_CMAP, i == prev + 1)
            if i != prev + 1:
                w.raw(i, lbits)
            prev_cp, prev = cp, i

        if face.kern_from is None:
            lclass, rclass, nl, nr, cells = kern_classes(face)
            pred = (kern_predictor(faces[face.kern_pred], lclass, rclass)
                    if face.kern_pred is not None else (lambda lc, rc: 0))
            w.gamma(G_KCLS, nl + 1)
            w.gamma(G_KCLS, nr + 1)
            for i in range(len(face.glyphs)):
                w.tree(0, lclass[i], nbits(nl))
                w.tree(1, rclass[i], nbits(nr))
            for lc in range(1, nl + 1):
                row = sorted((rc, v) for (l, rc), v in cells.items() if l == lc)
                w.gamma(G_KROW, len(row) + 1)
                prev_rc = 0
                pc = 0
                for rc, v in row:
                    w.gamma(G_KSTEP, rc - prev_rc)
                    d = v - pred(lc, rc)
                    w.delta(D_KERN + min(pc, 7), d)
                    prev_rc, pc = rc, cls(d)
        if face.math is not None:
            encode_math(w, face, lbits)
    return w


def math_tables(face):
    """The MATH data in the order it is written, glyphs as local indices."""
    m = face.math
    ix = face.index
    per = []
    for g in face.glyphs:
        n = g.name
        per.append((m["italic"].get(n), m["accent"].get(n), n in m["extended"],
                    m["kern"].get(n)))
    cons = []
    for key in ("vert", "horiz"):
        table = []
        for gname in sorted(m[key], key=lambda x: ix[x]):
            var, asm = m[key][gname]
            table.append((ix[gname], [(ix[v], a) for v, a in var],
                          None if asm is None else
                          (asm[0], [(ix[p[0]],) + tuple(p[1:]) for p in asm[1]])))
        cons.append(table)
    ssty = sorted((ix[a], ix[b]) for a, b in m["ssty"].items())
    dtls = sorted((ix[a], ix[b]) for a, b in m["dtls"].items())
    return per, cons, ssty, dtls


def encode_math(w, face, lbits):
    """The MATH section of a face; see fplotlib_glyphs for the layout."""
    per, cons, ssty, dtls = math_tables(face)
    for g, (ital, acc, ext, kern) in zip(face.glyphs, per):
        w.flag(B_ITAL, ital is not None)
        if ital is not None:
            w.delta(D_ITAL, ital)
        w.flag(B_ACC, acc is not None)
        if acc is not None:
            w.delta(D_ACC, acc - g.adv // 2)
        w.flag(B_EXT, ext)
        w.flag(B_MKERN, kern is not None)
        if kern is not None:
            for hs, ks in kern:
                w.gamma(G_MKN, len(hs) + 1)
                prev = 0
                for h in hs:
                    w.delta(D_MKH, h - prev)
                    prev = h
                prev = 0
                for k in ks:
                    w.delta(D_MKV, k - prev)
                    prev = k
    for table in cons:
        w.gamma(G_CONS, len(table) + 1)
        for g, var, asm in table:
            w.raw(g, lbits)
            w.gamma(G_NVAR, len(var) + 1)
            prev = 0
            for v, a in var:
                w.raw(v, lbits)
                w.delta(D_VAR, a - prev)
                prev = a
            w.flag(B_ASM, asm is not None)
            if asm is not None:
                w.delta(D_ASM, asm[0])
                w.gamma(G_NPART, len(asm[1]))
                for pg, st, en, full, ext in asm[1]:
                    w.raw(pg, lbits)
                    w.delta(D_ASM, st)
                    w.delta(D_ASM, en)
                    w.delta(D_ASM, full)
                    w.flag(B_PARTX, ext)
    w.gamma(G_PAIRS, len(ssty) + 1)
    for a, b in ssty:
        w.raw(a, lbits)
        w.raw(b, lbits)
    w.gamma(G_PAIRS, len(dtls) + 1)
    for a, b in dtls:
        w.raw(a, lbits)
        w.raw(b, lbits)


def decode_math(r, glyphs, lbits):
    per = []
    for adv, *_ in glyphs:
        ital = r.delta(D_ITAL) if r.flag(B_ITAL) else None
        acc = adv // 2 + r.delta(D_ACC) if r.flag(B_ACC) else None
        ext = r.flag(B_EXT) == 1
        kern = None
        if r.flag(B_MKERN):
            kern = []
            for _ in range(4):
                n = r.gamma(G_MKN) - 1
                hs, ks = [], []
                prev = 0
                for _ in range(n):
                    prev += r.delta(D_MKH)
                    hs.append(prev)
                prev = 0
                for _ in range(n + 1):
                    prev += r.delta(D_MKV)
                    ks.append(prev)
                kern.append((hs, ks))
        per.append((ital, acc, ext, kern))
    cons = []
    for _ in range(2):
        table = []
        for _ in range(r.gamma(G_CONS) - 1):
            g = r.raw(lbits)
            var = []
            prev = 0
            for _ in range(r.gamma(G_NVAR) - 1):
                v = r.raw(lbits)
                prev += r.delta(D_VAR)
                var.append((v, prev))
            asm = None
            if r.flag(B_ASM):
                ital = r.delta(D_ASM)
                parts = []
                for _ in range(r.gamma(G_NPART)):
                    parts.append((r.raw(lbits), r.delta(D_ASM), r.delta(D_ASM),
                                  r.delta(D_ASM), r.flag(B_PARTX)))
                asm = (ital, parts)
            table.append((g, var, asm))
        cons.append(table)
    ssty = [(r.raw(lbits), r.raw(lbits)) for _ in range(r.gamma(G_PAIRS) - 1)]
    dtls = [(r.raw(lbits), r.raw(lbits)) for _ in range(r.gamma(G_PAIRS) - 1)]
    return per, cons, ssty, dtls


def decode(blob, faces):
    """The inverse of encode, so that the round trip can be checked."""
    r = Reader(blob)
    out = []
    for fi, face in enumerate(faces):
        ng = len(face.glyphs)
        lbits = nbits(ng)
        cubic = 1 if face.cubic else 0
        glyphs = []
        prev_adv = 0
        last_comp = {}
        for k in range(ng):
            if face.pred is not None and k < len(out[face.pred]["glyphs"]):
                guess = out[face.pred]["glyphs"][k][0]
            else:
                guess = prev_adv
            adv = guess + r.delta(D_ADV)
            prev_adv = adv
            if r.flag(B_COMP):
                comps = []
                for j in range(r.gamma(G_NCOMP)):
                    src = face.xref if face.xref is not None and r.flag(B_XREF) else None
                    key = (src is not None, min(j, 1))
                    idx = last_comp.get(key, 0) + r.delta(D_CIDX + min(j, 1))
                    last_comp[key] = idx
                    comps.append((idx, r.delta(D_CX) * face.oscale,
                                  r.delta(D_CY) * face.oscale, src))
                contours = None
            elif face.resid and r.flag(B_RESID):
                comps = None
                ref = glyphs[r.raw(lbits)][1]
                contours = []
                px = py = cpx = cpy = 0
                for rpts, ron in ref:
                    pts = []
                    for xr, yr in rpts:
                        cx, _ = resid_ctx(cpx, cpy, 0)
                        dx = r.delta(cx)
                        _, cy = resid_ctx(cpx, cpy, cls(dx))
                        dy = r.delta(cy)
                        px += dx * face.oscale
                        py += dy * face.oscale
                        cpx, cpy = cls(dx), cls(dy)
                        pts.append((xr + px, yr + py))
                    contours.append((pts, list(ron)))
            else:
                comps = None
                counts = [r.gamma(G_NPTS) for _ in range(r.gamma(G_NCONT) - 1)]
                contours = []
                px = py = cpx = cpy = 0
                onp = onp2 = 1
                for n in counts:
                    pts, on = [], []
                    for _ in range(n):
                        o = r.flag(B_ON + onp * 4 + onp2 * 2 + cubic)
                        cx, _ = outline_ctx(o, onp, cpx, cpy, 0)
                        dx = r.delta(cx)
                        _, cy = outline_ctx(o, onp, cpx, cpy, cls(dx))
                        dy = r.delta(cy)
                        px += dx * face.oscale
                        py += dy * face.oscale
                        cpx, cpy = cls(dx), cls(dy)
                        onp2, onp = onp, o
                        on.append(o == 1)
                        pts.append((px, py))
                    contours.append((pts, on))
            bbox = (0, 0, 0, 0)
            if comps or contours:
                g = face.glyphs[k]
                cx0, cy0, cx1, cy1 = computed_box(face, g, faces)
                if r.flag(B_INK):
                    d = [r.delta(D_INK) for _ in range(4)]
                    bbox = (cx0 + d[0], cy0 + d[1], cx1 - d[2], cy1 - d[3])
                else:
                    bbox = (cx0, cy0, cx1, cy1)
            glyphs.append((adv, contours, comps, bbox))
        cmap = {}
        cp = 0
        prev = -1
        for _ in range(r.gamma(G_CMAPN) - 1):
            cp += r.gamma(G_CMAPSTEP)
            prev = prev + 1 if r.flag(B_CMAP) else r.raw(lbits)
            cmap[cp] = prev
        lc, rc, nl, nr, cells = None, None, 0, 0, {}
        if face.kern_from is None:
            nl = r.gamma(G_KCLS) - 1
            nr = r.gamma(G_KCLS) - 1
            lc, rc = [], []
            for _ in range(ng):
                lc.append(r.tree(0, nbits(nl)))
                rc.append(r.tree(1, nbits(nr)))
            pred = (kern_predictor(faces[face.kern_pred], lc, rc)
                    if face.kern_pred is not None else (lambda a, b: 0))
            for l in range(1, nl + 1):
                c = 0
                pc = 0
                for _ in range(r.gamma(G_KROW) - 1):
                    c += r.gamma(G_KSTEP)
                    d = r.delta(D_KERN + min(pc, 7))
                    cells[(l, c)] = d + pred(l, c)
                    pc = cls(d)
        math = decode_math(r, glyphs, lbits) if face.math is not None else None
        out.append({"glyphs": glyphs, "cmap": cmap, "lc": lc, "rc": rc,
                    "nl": nl, "nr": nr, "cells": cells, "math": math})
    return out


def check_round_trip(faces, back):
    for face, d in zip(faces, back):
        for g, (adv, contours, comps, bbox) in zip(face.glyphs, d["glyphs"]):
            want_comps = None if g.comps is None else \
                [((face if src is None else faces[src]).index[n], dx, dy, src)
                 for n, dx, dy, src in g.comps]
            if (adv, comps, bbox) != (g.adv, want_comps, g.bbox if g.ink else (0, 0, 0, 0)):
                raise SystemExit(f"{face.tag} {g.name}: the blob decodes differently")
            if g.comps is None and contours != [(list(p), list(o)) for p, o in g.contours]:
                raise SystemExit(f"{face.tag} {g.name}: the outline decodes differently")
        if d["cmap"] != {cp: face.index[n] for cp, n in face.cmap.items()}:
            raise SystemExit(f"{face.tag}: the cmap decodes differently")
        if face.kern_from is not None:
            continue
        for (a, b), v in face.kernq.items():
            ia, ib = face.index[a], face.index[b]
            if d["cells"].get((d["lc"][ia], d["rc"][ib])) != v:
                raise SystemExit(f"{face.tag}: kerning {a} {b} decodes differently")
        nk = sum(1 for (l, r) in [(d["lc"][i], d["rc"][j])
                                  for i in range(len(face.glyphs))
                                  for j in range(len(face.glyphs))]
                 if (l, r) in d["cells"])
        if nk != len(face.kernq):
            raise SystemExit(f"{face.tag}: the kerning classes kern other pairs too")
        if face.math is not None and d["math"] != math_tables(face):
            raise SystemExit(f"{face.tag}: the MATH data decodes differently")


def base85(blob):
    """Four bytes to five characters, big-endian, like Ascii85 or Z85."""
    out = []
    for i in range(0, len(blob), 4):
        v = int.from_bytes(blob[i:i + 4], "big")
        chunk = []
        for _ in range(5):
            chunk.append(ALPHABET[v % 85])
            v //= 85
        out.extend(reversed(chunk))
    return "".join(out)


# --- the NFD recomposition table ---------------------------------------


def recomposition(repertoire):
    """(base, mark, composed) for every composed character in repertoire.

    Text typed as a letter followed by a combining accent is put back
    together through this, one mark at a time, so a character with two
    marks recomposes in two steps and only its intermediate has to be in
    the table, which it is whenever it is in the repertoire.
    """
    out = []
    for cp in sorted(repertoire):
        d = unicodedata.decomposition(chr(cp))
        if not d or d.startswith("<"):
            continue
        parts = [int(p, 16) for p in d.split()]
        if len(parts) != 2:
            continue
        base, mark = parts
        if unicodedata.combining(chr(mark)) == 0:
            continue
        if unicodedata.normalize("NFC", chr(base) + chr(mark)) != chr(cp):
            continue
        out.append((base, mark, cp))
    return out


# --- the module ------------------------------------------------------


def literal(text, width=127, rows_per_chunk=100):
    """The blob as row parameters, and blob_text to put them together.

    One long literal would be simplest, but ifx caps a single token at
    7194 characters and a character named constant at 7198, so the blob
    cannot be one parameter, however it is spelled. Short rows have
    neither problem, and blob_text glues them back together at run time,
    where no limit applies; BLOB_LEN is the true length, the constructor
    blank-pads the last row to the common width.

    The rows are declared in chunks because a statement may carry only 255
    continuation lines before Fortran 2023, and there are more rows than
    that. They are not gathered into one array parameter, which would be a
    second copy of the blob in the object file. A row is its 127
    characters, quotes, a comma and an ampersand, the 132 column limit.
    """
    rows = [text[i:i + width] for i in range(0, len(text), width)]
    chunks = [rows[i:i + rows_per_chunk]
              for i in range(0, len(rows), rows_per_chunk)]
    decl = [f"    integer, parameter :: BLOB_LEN = {len(text)}",
            f"    integer, parameter :: BLOB_ROW = {width}"]
    for k, chunk in enumerate(chunks):
        decl.append(f"    character(len={width}), parameter :: "
                    f"BLOB_ROWS_{k + 1}({len(chunk)}) = "
                    f"[character(len={width}) :: &")
        for i, row in enumerate(chunk):
            tail = "]" if i == len(chunk) - 1 else ", &"
            decl.append(f'"{row}"{tail}')
        decl.append("")
    body = [
        "    ! The blob, the rows end to end; s is BLOB_LEN long.",
        "    subroutine blob_text(s)",
        "        character(len=*), intent(out) :: s",
        "        integer :: r, k",
        "        k = 0",
    ]
    for k in range(len(chunks)):
        body += [
            f"        do r = 1, size(BLOB_ROWS_{k + 1})",
            f"            s(k + 1:min(k + BLOB_ROW, len(s))) = BLOB_ROWS_{k + 1}(r)",
            "            k = k + BLOB_ROW",
            "        end do",
        ]
    body += ["    end subroutine blob_text"]
    return decl, body


def int_array(name, vals, per_line=12, indent="    "):
    """An integer parameter array, wrapped to stay inside 132 columns."""
    head = f"{indent}integer, parameter :: {name}({len(vals)}) = [ &"
    lines = [head]
    for i in range(0, len(vals), per_line):
        chunk = ", ".join(str(v) for v in vals[i:i + per_line])
        tail = "]" if i + per_line >= len(vals) else ", &"
        lines.append(f"{indent}    {chunk}{tail}")
    return lines


def logical_array(name, vals):
    s = ", ".join(".true." if v else ".false." for v in vals)
    return [f"    logical, parameter :: {name}({len(vals)}) = [{s}]"]


def expectation(faces):
    """What fplotlib_glyphs must hand out for every glyph, as JSON data.

    For checking the Fortran decoder (tools/check_glyphs.f90 dumps what it
    gets): advances, ink boxes and outlines in ems, the cmaps, the
    kerning of every pair and the MATH data, all from the data as stored.
    """
    base = [0]
    for f in faces:
        base.append(base[-1] + len(f.glyphs))
    out = {"glyphs": [], "cmap": [], "kern": [], "math": {}}
    for fi, f in enumerate(faces):
        e = f.em
        for g in f.glyphs:
            v, pts = contours_to_path(resolved(f, g, faces), f.cubic)
            out["glyphs"].append({
                "face": fi + 1, "adv": g.adv / e,
                "bbox": [c / e for c in (g.bbox if g.ink else (0, 0, 0, 0))],
                "verbs": v, "pts": [[x / e, y / e] for x, y in pts]})
        for cp, n in f.cmap.items():
            out["cmap"].append([fi + 1, cp, base[fi] + f.index[n] + 1])
        src = faces[f.kern_from] if f.kern_from is not None else f
        for (a, b), v in src.kernq.items():
            ia, ib = src.index[a], src.index[b]
            out["kern"].append([base[fi] + ia + 1, base[fi] + ib + 1,
                                v * KERN_STEP / e])
    mi = next(i for i, f in enumerate(faces) if f.math is not None)
    mf = faces[mi]
    m = mf.math

    def gid(n):
        return base[mi] + mf.index[n] + 1
    for g in mf.glyphs:
        n = g.name
        d = {"italic": m["italic"].get(n, 0) / mf.em,
             "accent": m["accent"].get(n, g.adv // 2) / mf.em,
             "ext": n in m["extended"],
             "ssty": gid(m["ssty"][n]) if n in m["ssty"] else gid(n),
             "dtls": gid(m["dtls"][n]) if n in m["dtls"] else gid(n),
             "kern": m["kern"].get(n), "cons": []}
        for key in ("vert", "horiz"):
            if n in m[key]:
                var, asm = m[key][n]
                d["cons"].append([[[gid(vn), a / mf.em] for vn, a in var],
                                  None if asm is None else
                                  [asm[0] / mf.em, [[gid(p[0]), p[1] / mf.em, p[2] / mf.em,
                                                     p[3] / mf.em, bool(p[4])]
                                                    for p in asm[1]]]])
            else:
                d["cons"].append([[], None])
        out["math"][gid(n)] = d
    out["em"] = mf.em
    out["constants"] = [c / mf.em for c in m["constants"]]
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fonts", help="read the pinned files from this directory "
                    "instead of downloading them")
    ap.add_argument("--expect", help="also write, as JSON, what fplotlib_glyphs "
                    "must hand out (for tools/check_glyphs.py)")
    args = ap.parse_args()

    faces = []
    loaded = [load_text_face(font_file(f, args.fonts), pred) + (f,)
              for f, pred in TEXT_FACES]
    loaded.append(load_math_face(font_file(MATH_FACE, args.fonts)) + (MATH_FACE,))
    for face, font, glyphset, fname in loaded:
        # The stored outline has to draw what the font's own pen draws.
        for g in face.glyphs:
            want = pen_path(glyphset, g.name)
            got = contours_to_path(resolved(face, g), face.cubic)
            if not same_shape(got, want):
                raise SystemExit(f"{fname} {g.name}: outline walk disagrees")
        faces.append(face)
    font_file("OFL.txt", args.fonts)
    font_file("LICENSE.txt", args.fonts)
    mface = faces[-1]
    refit_text_faces(faces, [gs for _, _, gs, _ in loaded])
    mface.resid = True
    plan_residuals(mface)
    for fi, src in KERN_SHARED.items():
        faces[fi].kern_from = src
        if set(faces[fi].kern) != set(faces[src].kern):
            raise SystemExit(f"{faces[fi].tag} does not kern the pairs {faces[src].tag} does")
    for fi, src in KERN_PREDICTED.items():
        faces[fi].kern_pred = src
    for fi in list(KERN_SHARED) + list(KERN_PREDICTED):
        src = faces[KERN_SHARED.get(fi, KERN_PREDICTED.get(fi))]
        for a, b in faces[fi].kern:
            for n in (a, b):
                k = faces[fi].index[n]
                if k >= len(src.glyphs) or src.glyphs[k].name != n:
                    raise SystemExit(f"{faces[fi].tag} {n} is not where {src.tag} has it")
    for face in faces:
        face.kernq = {k: round(v / KERN_STEP) for k, v in face.kern.items()
                      if round(v / KERN_STEP)}

    # Contours are turned to start where a rough count of the bits says
    # they are cheapest: a magnitude class costs about two, and the bits
    # under its leading one about one each.
    def cost_in(scale):
        def cost(a, b):
            t = 0
            for v in (b[0] - a[0], b[1] - a[1]):
                c = zigzag(v // scale).bit_length()
                t += 2 + max(c - 1, 0)
            return t
        return cost

    for face in faces:
        cost = cost_in(face.oscale)
        # A glyph stored as a difference starts its contours where the
        # glyph it is the difference from does.
        for g in sorted(face.glyphs, key=lambda g: g.ref is not None):
            if g.comps is None:
                if g.ref is None:
                    new, g.turns = best_storage(g.contours, face.cubic, cost)
                else:
                    g.turns = face.glyphs[face.index[g.ref]].turns
                    new = turned(g.contours, g.turns)
                if not same_shape(contours_to_path(new, face.cubic),
                                  contours_to_path(g.contours, face.cubic)):
                    raise SystemExit(f"{face.tag} {g.name}: turning changed it")
                g.contours = new

    w = encode(faces)
    blob = w.bytes()
    check_round_trip(faces, decode(blob, faces))
    text = base85(blob)

    ngl = [len(f.glyphs) for f in faces]
    nglyph = sum(ngl)
    ncont = sum(len(g.contours) for f in faces for g in f.glyphs if g.comps is None)
    npt = sum(len(p) for f in faces for g in f.glyphs if g.comps is None
              for p, _ in g.contours)
    ncomp = sum(len(g.comps) for f in faces for g in f.glyphs if g.comps is not None)
    ncmap = sum(len(f.cmap) for f in faces)
    kc = [kern_classes(f) for f in faces if f.kern_from is None]
    nkern = sum((k[2] + 1) * (k[3] + 1) for k in kc)
    recomp = recomposition(TEXT_REPERTOIRE)

    L = [
        "! fplotlib_glyphs_data -- glyph outlines, metrics and kerning, generated",
        "! by tools/gen_glyphs.py. Do not edit.",
        "!",
        "! The glyph data in this file is derived from two fonts:",
        "!",
        "!   * Lato 2.015, copyright (c) 2010-2014 by tyPoland Lukasz Dziedzic",
        "!     (team@latofonts.com) with Reserved Font Name \"Lato\"; licence",
        "!     in LICENSE_LATO;",
        "!   * Lete Sans Math 0.63, copyright (c) Chenjing Bu and Daniel Flipo,",
        "!     built on Fira Math (copyright (c) Xiangdong Zeng) and Lato, and",
        "!     inheriting Lato's Reserved Font Name; licence in LICENSE_LETE.",
        "!",
        "! Both are licensed under the SIL Open Font License, Version 1.1. The",
        "! rest of fplotlib is MIT; this file is OFL-1.1.",
        "!",
        "! One base85 string holds every face: glyph outlines, advance widths",
        "! and ink boxes in integer font units, each face's cmap and its pair",
        "! kerning, and the math face's MATH table. Lato's outlines are stored",
        "! as cubics at 1000 units to the em, many of them as Lete Sans Math's.",
        "! fplotlib_glyphs unpacks it on first",
        "! use; the format is described there and in the generator.",
        "",
        "module fplotlib_glyphs_data",
        "    implicit none",
        "    public",
        "",
        f"    integer, parameter :: NFACE = {len(faces)}",
        f"    integer, parameter :: NGLYPH = {nglyph}",
        f"    integer, parameter :: NCONT = {ncont}",
        f"    integer, parameter :: NPT = {npt}",
        f"    integer, parameter :: NCOMP = {ncomp}",
        f"    integer, parameter :: NCMAP = {ncmap}",
        f"    integer, parameter :: NKERN = {nkern}",
        "",
        "    ! Per face: how many glyphs it has, its units per em, ascender,",
        "    ! descender, x-height and cap height in its own units, whether its",
        "    ! outlines are cubic (CFF) or quadratic (TrueType), and the face its",
        "    ! advance widths are predicted from, 0 for the glyph before.",
    ]
    L += int_array("FACE_NG", ngl)
    L += int_array("FACE_EM", [f.em for f in faces])
    L += int_array("FACE_ASC", [f.asc for f in faces])
    L += int_array("FACE_DESC", [f.desc for f in faces])
    L += int_array("FACE_XH", [f.xh for f in faces])
    L += int_array("FACE_CAP", [f.cap for f in faces])
    L += logical_array("FACE_CUBIC", [f.cubic for f in faces])
    L += [
        "",
        "    ! The font units an outline unit is, and the face a composite's",
        "    ! components may come from as well as its own, 0 for none.",
    ]
    L += int_array("FACE_OSCALE", [f.oscale for f in faces])
    L += int_array("FACE_XREF", [0 if f.xref is None else f.xref + 1 for f in faces])
    L += ["    ! Whether a face's glyphs may be stored as differences from others."]
    L += logical_array("FACE_RESID", [f.resid for f in faces])
    L += int_array("FACE_PRED", [0 if f.pred is None else f.pred + 1 for f in faces])
    L += [
        "",
        "    ! Kerning is in steps of KERN_STEP font units. A face uses the",
        "    ! kerning of FACE_KERN, itself unless it shares another's, and",
        "    ! stores its values as differences from those of FACE_KPRED, 0 for",
        "    ! none.",
        f"    integer, parameter :: KERN_STEP = {KERN_STEP}",
    ]
    L += int_array("FACE_KERN", [i + 1 if f.kern_from is None else f.kern_from + 1
                                 for i, f in enumerate(faces)])
    L += int_array("FACE_KPRED", [0 if f.kern_pred is None else f.kern_pred + 1
                                  for f in faces])
    mp, mcons, mssty, mdtls = math_tables(mface)
    L += logical_array("FACE_HAS_MATH", [f.math is not None for f in faces])
    L += [
        "",
        "    ! The math face's MATH table: how many size variants, assemblies,",
        "    ! assembly parts, math kern heights and math kern values it has,",
        "    ! the overlap two assembly parts must at least have, and the",
        "    ! constants, in font units (two of them are percentages).",
        f"    integer, parameter :: NVAR = {sum(len(v) for t in mcons for _, v, _ in t)}",
        f"    integer, parameter :: NASM = {sum(1 for t in mcons for _, _, a in t if a)}",
        f"    integer, parameter :: NPART = {sum(len(a[1]) for t in mcons for _, _, a in t if a)}",
        f"    integer, parameter :: NMKH = {sum(len(h) for _, _, _, k in mp if k for h, _ in k)}",
        f"    integer, parameter :: NMKV = {sum(len(v) for _, _, _, k in mp if k for _, v in k)}",
        f"    integer, parameter :: MIN_CONNECTOR_OVERLAP = {mface.math['overlap']}",
        f"    integer, parameter :: NMC = {len(MATH_CONSTANTS)}",
    ]
    for k, name in enumerate(MATH_CONSTANTS):
        snake = "".join("_" + c if c.isupper() and i else c
                        for i, c in enumerate(name)).upper()
        L.append(f"    integer, parameter :: MC_{snake} = {k + 1}")
    L += int_array("MATH_CONSTANT", mface.math["constants"])
    L += [
        "",
        "    ! Canonical composition of a base and one combining mark, for the",
        "    ! characters of the text repertoire: text typed decomposed (NFD) is",
        "    ! put back together through this before it is looked up.",
        f"    integer, parameter :: NRECOMP = {len(recomp)}",
    ]
    L += int_array("RECOMP_BASE", [b for b, _, _ in recomp])
    L += int_array("RECOMP_MARK", [m for _, m, _ in recomp])
    L += int_array("RECOMP_CHAR", [c for _, _, c in recomp])
    L += [
        "",
        "    character(len=*), parameter :: ALPHABET = &",
        f'        "{ALPHABET}"',
        "",
    ]
    decl, body = literal(text)
    L += decl
    L += ["", "contains", ""] + body
    L += ["", "end module fplotlib_glyphs_data", ""]

    OUT.write_text("\n".join(L), encoding="utf-8", newline="\n")
    if args.expect:
        Path(args.expect).write_text(json.dumps(expectation(faces)), encoding="utf-8")
    size = OUT.stat().st_size
    print(f"wrote {OUT}: {nglyph} glyphs ({ncomp} component references), "
          f"{npt} points, {sum(len(f.kern) for f in faces)} kerning pairs, "
          f"{len(blob)} bytes of blob, {size} bytes of source")


if __name__ == "__main__":
    main()
