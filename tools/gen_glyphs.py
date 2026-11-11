"""Regenerate src/fplotlib_glyphs_data.f90 from the pinned font files.

Every backend draws text from outlines compiled into the library, so the
outlines, metrics and kerning of the fonts fplotlib uses have to be part of
it. Text is set in Lato (regular, bold, italic, bold italic).

The fonts are pinned to exact commits and checked against their SHA-256
hashes. They are downloaded into a cache directory, or read from a
directory given on the command line:

    pixi exec --spec fonttools --spec python=3.12 -- python tools/gen_glyphs.py
    pixi exec --spec fonttools --spec python=3.12 -- python tools/gen_glyphs.py --fonts DIR

What is stored is each font's own representation, in integer font units:

  * glyphs are numbered (glyph ids, "gids"), the faces one after another,
    because a glyph need not have a code point of its own -- a component
    of an accented letter, a size variant, a script-size alternate;
  * a simple glyph is its contours, each a cycle of points that lie on the
    curve or are control points. TrueType's control points are quadratic
    and CFF's cubic, and each face is stored in its own kind: a CFF
    contour has its control points in pairs, a TrueType contour may leave
    an on-curve point implied between two of them;
  * a composite glyph (an accented letter, mostly) is a list of component
    gids with their offsets, so the accent and the letter are stored once;
  * every glyph carries its advance width and its ink box, the exact
    bounds of the curves rounded outwards;
  * each face has a cmap, the code points it maps to gids, and its pair
    kerning, reduced to a left class per glyph, a right class per glyph
    and the non-zero cells of the class matrix.

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
import math
import sys
import unicodedata
import urllib.request
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
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

# The faces, in the order the library numbers them: regular, bold, italic,
# bold italic. Each predicts its advance widths from the face named, which
# is the same letter drawn another way and usually of a similar width.
TEXT_FACES = [
    ("Lato-Regular.ttf", None),
    ("Lato-Bold.ttf", 0),
    ("Lato-Italic.ttf", 0),
    ("Lato-BoldItalic.ttf", 2),
]


def _r(a, b):
    return set(range(a, b + 1))


# The text repertoire: every European script except Cyrillic, without
# polytonic Greek, and the symbols labels are written with.
TEXT_REPERTOIRE = (
    _r(0x20, 0x7E) | _r(0xA0, 0xFF) | _r(0x100, 0x17F)
    | _r(0x1C4, 0x1CC) | _r(0x1E6, 0x1E9) | _r(0x1EE, 0x1EF) | {0x1B7, 0x292}
    | _r(0x1FA, 0x1FF) | _r(0x218, 0x21B)
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

# Printable ASCII without the characters that are awkward inside a Fortran
# literal: the two quotes, the backslash some compilers read escapes from,
# and "&" and "!", which lfortran mistakes for a continuation and a comment
# even inside the quotes. That leaves 89; the first 85 are the alphabet.
ALPHABET = "".join(
    c for c in (chr(i) for i in range(33, 127)) if c not in "\"'\\&!"
)[:85]

VERB_MOVE, VERB_LINE, VERB_CUBIC, VERB_CLOSE = 1, 2, 3, 4

# The longest code a magnitude class may get. The decoder reads a code a
# bit at a time, so this only bounds a loop.
MAXLEN = 15


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
        self.comps = None       # [(name, dx, dy)], for a composite one
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
                g.comps.append((c.glyphName, int(c.x), int(c.y)))
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


def resolved(face, g):
    """A glyph's contours with its components put in place."""
    if g.comps is None:
        return g.contours
    out = []
    for name, dx, dy in g.comps:
        for pts, on in face.glyphs[face.index[name]].contours:
            out.append(([(x + dx, y + dy) for x, y in pts], on))
    return out


# --- the bit stream ---------------------------------------------------


def zigzag(v):
    """Signed to unsigned, keeping small magnitudes small."""
    return 2 * v if v >= 0 else -2 * v - 1


def unzigzag(u):
    return u // 2 if u % 2 == 0 else -(u + 1) // 2


def huffman_lengths(freq):
    """Code lengths of a Huffman code for these frequencies, at most MAXLEN.

    Every class up to the largest used one gets a code, so the code is
    complete and the decoder never meets a gap.
    """
    n = len(freq)
    heap = [(max(f, 1), i, [i]) for i, f in enumerate(freq)]
    heapq.heapify(heap)
    lengths = [0] * n
    tie = n
    while len(heap) > 1:
        fa, _, a = heapq.heappop(heap)
        fb, _, b = heapq.heappop(heap)
        for s in a + b:
            lengths[s] += 1
        heapq.heappush(heap, (fa + fb, tie, a + b))
        tie += 1
    if n == 1:
        lengths = [1]
    if max(lengths) > MAXLEN:
        raise SystemExit("a magnitude class needs a code longer than MAXLEN")
    return lengths


def canonical(lengths):
    """Codes for a canonical prefix code, shortest and lowest symbol first."""
    order = sorted(range(len(lengths)), key=lambda s: (lengths[s], s))
    codes = {}
    code = 0
    prev = 0
    for sym in order:
        code <<= lengths[sym] - prev
        prev = lengths[sym]
        codes[sym] = code
        code += 1
    if sum(2.0 ** -length for length in lengths) != 1.0:
        raise SystemExit("the magnitude classes are not a complete prefix code")
    return codes


class Writer:
    """Writes the stream; with no code yet, only counts the classes."""

    def __init__(self, clen=None):
        self.bits = []
        self.clen = clen
        self.codes = canonical(clen) if clen else None
        self.freq = [0] * 32

    def bit(self, b):
        self.bits.append(b)

    def raw(self, value, n):
        if value < 0 or value >= 1 << n:
            raise SystemExit(f"{value} does not fit in {n} bits")
        for k in range(n - 1, -1, -1):
            self.bits.append((value >> k) & 1)

    def gamma(self, n):
        """Elias gamma: the length in zeros, then the number itself."""
        if n < 1:
            raise SystemExit(f"gamma of {n}")
        length = n.bit_length()
        self.raw(0, length - 1)
        self.raw(n, length)

    def delta(self, v):
        u = zigzag(v)
        cls = u.bit_length()
        self.freq[cls] += 1
        if self.codes is not None:
            if cls >= len(self.clen):
                raise SystemExit(f"delta {v} needs class {cls}")
            self.raw(self.codes[cls], self.clen[cls])
        if cls > 1:
            self.raw(u - (1 << (cls - 1)), cls - 1)

    def bytes(self):
        pad = (-len(self.bits)) % 32
        bits = self.bits + [0] * pad
        return bytes(
            int("".join(str(b) for b in bits[i:i + 8]), 2)
            for i in range(0, len(bits), 8)
        )


class Reader:
    def __init__(self, blob, clen):
        self.blob = blob
        self.pos = 0
        self.clen = clen
        self.codes = canonical(clen)

    def bit(self):
        b = (self.blob[self.pos >> 3] >> (7 - (self.pos & 7))) & 1
        self.pos += 1
        return b

    def raw(self, n):
        v = 0
        for _ in range(n):
            v = 2 * v + self.bit()
        return v

    def gamma(self):
        zeros = 0
        while self.bit() == 0:
            zeros += 1
        return (1 << zeros) | self.raw(zeros)

    def delta(self):
        code = 0
        length = 0
        while True:
            code = 2 * code + self.bit()
            length += 1
            for sym, clen in enumerate(self.clen):
                if clen == length and self.codes[sym] == code:
                    if sym == 0:
                        return 0
                    return unzigzag((1 << (sym - 1)) | self.raw(sym - 1))
            if length > MAXLEN:
                raise SystemExit("bad prefix code in blob")


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
    stored = []
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
        cur = pts[(k - 1) % n]
    return stored


def kern_classes(face):
    """Pair kerning as left and right classes and the non-zero cells.

    Glyphs whose rows (or columns) of the pair table are identical share a
    class; class 0 is the glyphs that are never kerned on that side.
    """
    names = [g.name for g in face.glyphs]
    rows, cols = {}, {}
    for (a, b), v in face.kern.items():
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
    for (a, b), v in face.kern.items():
        cells[(lclass[face.index[a]], rclass[face.index[b]])] = v
    return lclass, rclass, len(lkeys), len(rkeys), cells


def encode(faces, clen):
    """The whole table as one bit stream; see fplotlib_glyphs for the layout."""
    w = Writer(clen)
    for fi, face in enumerate(faces):
        lbits = nbits(len(face.glyphs))
        prev_adv = 0
        for k, g in enumerate(face.glyphs):
            if face.pred is not None and k < len(faces[face.pred].glyphs):
                guess = faces[face.pred].glyphs[k].adv
            else:
                guess = prev_adv
            w.delta(g.adv - guess)
            prev_adv = g.adv
            if g.comps is not None:
                w.bit(1)
                w.gamma(len(g.comps))
                for name, dx, dy in g.comps:
                    w.raw(face.index[name], lbits)
                    w.delta(dx)
                    w.delta(dy)
            else:
                w.bit(0)
                w.gamma(len(g.contours) + 1)
                for pts, _ in g.contours:
                    w.gamma(len(pts))
                px = py = 0
                for pts, on in g.contours:
                    for (x, y), o in zip(pts, on):
                        w.bit(1 if o else 0)
                        w.delta(x - px)
                        w.delta(y - py)
                        px, py = x, y
            w.bit(1 if g.ink else 0)
            if g.ink:
                x0, y0, x1, y1 = g.bbox
                w.delta(x0)
                w.delta(y0)
                w.delta(x1 - g.adv)
                w.delta(y1)

        # The cmap, in code point order: the step to the next code point,
        # and the glyph, which is usually the one after the last.
        w.gamma(len(face.cmap) + 1)
        prev_cp = 0
        prev = -1
        for cp in sorted(face.cmap):
            i = face.index[face.cmap[cp]]
            w.gamma(cp - prev_cp)
            if i == prev + 1:
                w.bit(1)
            else:
                w.bit(0)
                w.raw(i, lbits)
            prev_cp, prev = cp, i

        lclass, rclass, nl, nr, cells = kern_classes(face)
        w.gamma(nl + 1)
        w.gamma(nr + 1)
        for i in range(len(face.glyphs)):
            w.raw(lclass[i], nbits(nl))
            w.raw(rclass[i], nbits(nr))
        for lc in range(1, nl + 1):
            row = sorted((rc, v) for (l, rc), v in cells.items() if l == lc)
            w.gamma(len(row) + 1)
            prev_rc = 0
            for rc, v in row:
                w.gamma(rc - prev_rc)
                w.delta(v)
                prev_rc = rc
    return w


def decode(blob, clen, faces):
    """The inverse of encode, so that the round trip can be checked."""
    r = Reader(blob, clen)
    out = []
    for fi, face in enumerate(faces):
        ng = len(face.glyphs)
        lbits = nbits(ng)
        glyphs = []
        prev_adv = 0
        for k in range(ng):
            if face.pred is not None and k < len(out[face.pred]["glyphs"]):
                guess = out[face.pred]["glyphs"][k][0]
            else:
                guess = prev_adv
            adv = guess + r.delta()
            prev_adv = adv
            if r.bit():
                comps = []
                for _ in range(r.gamma()):
                    comps.append((r.raw(lbits), r.delta(), r.delta()))
                contours = None
            else:
                comps = None
                counts = [r.gamma() for _ in range(r.gamma() - 1)]
                contours = []
                px = py = 0
                for n in counts:
                    pts, on = [], []
                    for _ in range(n):
                        on.append(r.bit() == 1)
                        px += r.delta()
                        py += r.delta()
                        pts.append((px, py))
                    contours.append((pts, on))
            if r.bit():
                x0, y0 = r.delta(), r.delta()
                x1 = adv + r.delta()
                bbox = (x0, y0, x1, r.delta())
            else:
                bbox = (0, 0, 0, 0)
            glyphs.append((adv, contours, comps, bbox))
        cmap = {}
        cp = 0
        prev = -1
        for _ in range(r.gamma() - 1):
            cp += r.gamma()
            prev = prev + 1 if r.bit() else r.raw(lbits)
            cmap[cp] = prev
        nl = r.gamma() - 1
        nr = r.gamma() - 1
        lc, rc = [], []
        for _ in range(ng):
            lc.append(r.raw(nbits(nl)))
            rc.append(r.raw(nbits(nr)))
        cells = {}
        for l in range(1, nl + 1):
            c = 0
            for _ in range(r.gamma() - 1):
                c += r.gamma()
                cells[(l, c)] = r.delta()
        out.append({"glyphs": glyphs, "cmap": cmap, "lc": lc, "rc": rc,
                    "nl": nl, "nr": nr, "cells": cells})
    return out


def check_round_trip(faces, back):
    for face, d in zip(faces, back):
        for g, (adv, contours, comps, bbox) in zip(face.glyphs, d["glyphs"]):
            want_comps = None if g.comps is None else \
                [(face.index[n], dx, dy) for n, dx, dy in g.comps]
            if (adv, comps, bbox) != (g.adv, want_comps, g.bbox if g.ink else (0, 0, 0, 0)):
                raise SystemExit(f"{face.tag} {g.name}: the blob decodes differently")
            if g.comps is None and contours != [(list(p), list(o)) for p, o in g.contours]:
                raise SystemExit(f"{face.tag} {g.name}: the outline decodes differently")
        if d["cmap"] != {cp: face.index[n] for cp, n in face.cmap.items()}:
            raise SystemExit(f"{face.tag}: the cmap decodes differently")
        for (a, b), v in face.kern.items():
            ia, ib = face.index[a], face.index[b]
            if d["cells"].get((d["lc"][ia], d["rc"][ib])) != v:
                raise SystemExit(f"{face.tag}: kerning {a} {b} decodes differently")
        nk = sum(1 for (l, r) in [(d["lc"][i], d["rc"][j])
                                  for i in range(len(face.glyphs))
                                  for j in range(len(face.glyphs))]
                 if (l, r) in d["cells"])
        if nk != len(face.kern):
            raise SystemExit(f"{face.tag}: the kerning classes kern other pairs too")


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


def literal(text, width=118, rows_per_chunk=100):
    """The blob as an array of equal-length row parameters.

    One long literal would be simplest, but ifx caps a single token at
    7194 characters and a character named constant at 7198, so the blob
    cannot be one parameter, however it is spelled. An array of short rows
    has neither problem, and fplotlib_glyphs glues the rows back together
    at run time, where no limit applies. BLOB_LEN is the true length; the
    constructor blank-pads the last row to the common width.

    The rows are declared in chunks which BLOB_ROWS then concatenates,
    because a statement may carry only 255 continuation lines before
    Fortran 2023 and there are more rows than that. 118 payload characters
    plus quotes, comma and ampersand at an 8-column indent is the 132
    column limit.
    """
    rows = [text[i:i + width] for i in range(0, len(text), width)]
    chunks = [rows[i:i + rows_per_chunk]
              for i in range(0, len(rows), rows_per_chunk)]
    out = [f"    integer, parameter :: BLOB_LEN = {len(text)}"]
    for k, chunk in enumerate(chunks):
        out.append(f"    character(len={width}), parameter :: "
                   f"BLOB_ROWS_{k + 1}({len(chunk)}) = "
                   f"[character(len={width}) :: &")
        for i, row in enumerate(chunk):
            tail = "]" if i == len(chunk) - 1 else ", &"
            out.append(f'        "{row}"{tail}')
        out.append("")
    # The concatenation itself is a statement too, so it is chunked the
    # same way once there are more than a couple of hundred chunks.
    out.append(f"    character(len={width}), parameter :: "
               f"BLOB_ROWS({len(rows)}) = [ &")
    for k in range(len(chunks)):
        tail = "]" if k == len(chunks) - 1 else ", &"
        out.append(f"        BLOB_ROWS_{k + 1}{tail}")
    return out


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


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fonts", help="read the pinned files from this directory "
                    "instead of downloading them")
    args = ap.parse_args()

    faces = []
    for fname, pred in TEXT_FACES:
        path = font_file(fname, args.fonts)
        face, font, glyphset = load_text_face(path, pred)

        # The stored outline has to draw what the font's own pen draws.
        for g in face.glyphs:
            want = pen_path(glyphset, g.name)
            got = contours_to_path(resolved(face, g), face.cubic)
            if not same_shape(got, want):
                raise SystemExit(f"{fname} {g.name}: outline walk disagrees")
        faces.append(face)
    font_file("OFL.txt", args.fonts)

    # Turning contours to their cheapest start needs the code lengths and
    # the code lengths depend on the deltas, so the code is fitted to the
    # unturned data and the turn fitted to that code.
    first = encode(faces, None)
    maxcls = max(i for i, f in enumerate(first.freq) if f)
    clen = huffman_lengths(first.freq[:maxcls + 1])

    def cost(a, b):
        t = 0
        for v in (b[0] - a[0], b[1] - a[1]):
            c = zigzag(v).bit_length()
            t += (clen[c] if c < len(clen) else 99) + max(c - 1, 0)
        return t

    for face in faces:
        for g in face.glyphs:
            if g.comps is None:
                turned = best_storage(g.contours, face.cubic, cost)
                if not same_shape(contours_to_path(turned, face.cubic),
                                  contours_to_path(g.contours, face.cubic)):
                    raise SystemExit(f"{face.tag} {g.name}: turning changed it")
                g.contours = turned

    second = encode(faces, None)
    maxcls = max(i for i, f in enumerate(second.freq) if f)
    clen = huffman_lengths(second.freq[:maxcls + 1])
    w = encode(faces, clen)
    blob = w.bytes()
    check_round_trip(faces, decode(blob, clen, faces))
    text = base85(blob)

    ngl = [len(f.glyphs) for f in faces]
    nglyph = sum(ngl)
    ncont = sum(len(g.contours) for f in faces for g in f.glyphs if g.comps is None)
    npt = sum(len(p) for f in faces for g in f.glyphs if g.comps is None
              for p, _ in g.contours)
    ncomp = sum(len(g.comps) for f in faces for g in f.glyphs if g.comps is not None)
    ncmap = sum(len(f.cmap) for f in faces)
    kc = [kern_classes(f) for f in faces]
    nkern = sum((k[2] + 1) * (k[3] + 1) for k in kc)
    recomp = recomposition(TEXT_REPERTOIRE)

    L = [
        "! fplotlib_glyphs_data -- glyph outlines, metrics and kerning, generated",
        "! by tools/gen_glyphs.py. Do not edit.",
        "!",
        "! The glyph data in this file is derived from Lato 2.015,",
        "! copyright (c) 2010-2014 by tyPoland Lukasz Dziedzic",
        "! (team@latofonts.com) with Reserved Font Name \"Lato\".",
        "!",
        "! It is licensed under the SIL Open Font License, Version 1.1, whose",
        "! text is in LICENSE_LATO. The rest of fplotlib is MIT; this file is",
        "! OFL-1.1.",
        "!",
        "! One base85 string holds every face: glyphs as the fonts store them,",
        "! in integer font units, with their advance widths and ink boxes, each",
        "! face's cmap and its pair kerning. fplotlib_glyphs unpacks it on first",
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
    L += int_array("FACE_PRED", [0 if f.pred is None else f.pred + 1 for f in faces])
    L += [
        "",
        "    ! Code lengths of the prefix code for the magnitude classes of a",
        "    ! delta, a Huffman code for this data.",
        f"    integer, parameter :: NCLASS = {len(clen)}",
    ]
    L += int_array("CLEN", clen, per_line=16)
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
    L += literal(text)
    L += ["", "end module fplotlib_glyphs_data", ""]

    OUT.write_text("\n".join(L), encoding="utf-8", newline="\n")
    size = OUT.stat().st_size
    print(f"wrote {OUT}: {nglyph} glyphs ({ncomp} component references), "
          f"{npt} points, {sum(len(f.kern) for f in faces)} kerning pairs, "
          f"{len(blob)} bytes of blob, {size} bytes of source")


if __name__ == "__main__":
    main()
