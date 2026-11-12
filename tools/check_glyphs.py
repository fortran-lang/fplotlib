"""Check what fplotlib_glyphs hands out against what it must.

    python tools/gen_glyphs.py --expect expect.json
    (build and run tools/dump_glyphs.f90, see there) > glyphs_dump.txt
    python tools/check_glyphs.py expect.json glyphs_dump.txt

Every glyph's advance, ink box and outline, every cmap entry, the kerning
of every pair and the MATH data must agree to 1e-9 em.
"""

import json
import sys

TOL = 1e-9


def close(a, b):
    return abs(a - b) <= TOL


def main():
    exp = json.load(open(sys.argv[1]))
    lines = open(sys.argv[2]).read().split("\n")
    em = exp["em"]
    cmap, kern = {}, {}
    ng = 0
    i = 0
    while i < len(lines):
        p = lines[i].split()
        if not p:
            i += 1
            continue
        tag = p[0]
        if tag == "G":
            g, face = int(p[1]), int(p[2])
            adv, *box = map(float, p[3:])
            v = list(map(int, lines[i + 1].split()[1:]))
            xy = list(map(float, lines[i + 2].split()[1:]))
            want = exp["glyphs"][g - 1]
            assert face == want["face"], g
            assert close(adv, want["adv"]), (g, "advance", adv, want["adv"])
            assert all(close(a, b) for a, b in zip(box, want["bbox"])), \
                (g, "ink box", box, want["bbox"])
            assert v == want["verbs"], (g, "verbs")
            pts = [(xy[k], xy[k + 1]) for k in range(0, len(xy), 2)]
            assert len(pts) == len(want["pts"]) and all(
                close(a[0], b[0]) and close(a[1], b[1]) for a, b in zip(pts, want["pts"])), \
                (g, "outline")
            ng += 1
            i += 3
            continue
        if tag == "M":
            g = int(p[1])
            d = exp["math"][str(g)]
            assert close(float(p[2]), d["italic"]), (g, "italic")
            assert close(float(p[3]), d["accent"]), (g, "accent")
            assert (p[4] == "T") == d["ext"], (g, "extended")
            assert int(p[5]) == d["ssty"] and int(p[6]) == d["ssty"], (g, "ssty")
            assert int(p[7]) == d["dtls"], (g, "dtls")
        elif tag == "K":
            g = int(p[1])
            k = exp["math"][str(g)]["kern"]
            vals = list(map(float, p[2:]))
            hs = [0.01 * j for j in range(-50, 151, 5)]
            want = []
            for c in range(4):
                for h in hs:
                    if k is None:
                        want.append(0.0)
                        continue
                    heights, kerns = k[c]
                    j = 0
                    while j < len(heights) and h * em >= heights[j]:
                        j += 1
                    want.append(kerns[j] / em)
            assert all(close(a, b) for a, b in zip(vals, want)), (g, "math kern")
        elif tag == "W":
            g, c = int(p[1]), int(p[2])
            got = [[int(p[k]), float(p[k + 1])] for k in range(3, len(p), 2)]
            want = exp["math"][str(g)]["cons"][c - 1][0]
            assert len(got) == len(want) and all(
                a[0] == b[0] and close(a[1], b[1]) for a, b in zip(got, want)), (g, "variants")
        elif tag == "A":
            g, c = int(p[1]), int(p[2])
            asm = exp["math"][str(g)]["cons"][c - 1][1]
            rest = p[4:]
            if asm is None:
                assert rest == [] and float(p[3]) == 0, (g, "assembly")
            else:
                assert close(float(p[3]), asm[0]), (g, "assembly italic")
                parts = [rest[k:k + 5] for k in range(0, len(rest), 5)]
                assert len(parts) == len(asm[1]), (g, "assembly parts")
                for q, w in zip(parts, asm[1]):
                    assert int(q[0]) == w[0] and all(close(float(q[j]), w[j]) for j in (1, 2, 3)) \
                        and (q[4] == "T") == w[4], (g, "assembly part")
        elif tag == "C":
            f, cp, g = map(int, p[1:])
            cmap[(f, cp)] = g
        elif tag == "R":
            kern[(int(p[1]), int(p[2]))] = float(p[3])
        elif tag == "X":
            assert all(close(float(a), b) for a, b in zip(p[1:], exp["constants"])), "constants"
        i += 1
    assert ng == len(exp["glyphs"]), (ng, len(exp["glyphs"]))
    assert cmap == {(f, cp): g for f, cp, g in exp["cmap"]}, "cmap"
    want = {(a, b): v for a, b, v in exp["kern"]}
    assert set(kern) == set(want), ("kerned pairs", len(kern), len(want))
    assert all(close(kern[k], want[k]) for k in want), "kerning"
    print(f"glyphs: all {ng} glyphs, {len(cmap)} cmap entries and {len(kern)} "
          f"kerning pairs agree")


if __name__ == "__main__":
    main()
