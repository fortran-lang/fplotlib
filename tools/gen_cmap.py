"""Regenerate src/fplotlib_cmap.f90 from matplotlib and Scientific Colour Maps.

The Fortran library has no way to evaluate matplotlib's colormap definitions,
so the tables are sampled here and interpolated at run time. Run this if a
colormap is added or the anchor count changes:

    pixi run python tools/gen_cmap.py

Scientific Colour Maps (cmcrameri) are created by Fabio Crameri
(https://www.fabiocrameri.ch/colourmaps/) and released under the MIT License.
Crameri, F. (2018). Scientific colour maps. Zenodo.
https://doi.org/10.5281/zenodo.1243862
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

# The order fixes the integer id of every map, and the first one is the
# default. Sequential first, then diverging, then the rest, then Fabio
# Crameri's Scientific Colour Maps.
MPL_NAMES = [
    "viridis", "plasma", "inferno", "magma", "cividis", "gray",
    "Blues", "Greens", "Oranges", "Reds", "Purples", "Greys",
    "YlGnBu", "YlOrRd", "GnBu", "BuPu", "hot", "afmhot", "copper", "bone",
    "pink", "cool", "spring", "summer", "autumn", "winter",
    "coolwarm", "bwr", "seismic", "RdBu", "RdYlBu", "RdYlGn", "Spectral",
    "PiYG", "PRGn", "BrBG", "PuOr",
    "jet", "rainbow", "turbo", "hsv", "twilight", "cubehelix",
    "terrain", "ocean", "gist_earth", "nipy_spectral", "CMRmap", "gnuplot",
]

# Fabio Crameri's Scientific Colour Maps (MIT License).
CRAMERI_NAMES = [
    "batlow", "batlowW", "batlowK", "oslo", "lajolla", "bilbao", "devon",
    "turku", "tokyo", "lapaz", "davos", "acton", "nuuk", "hawaii", "imola",
    "buda", "bamako", "grayC", "oleron", "fes",
    "vik", "roma", "berlin", "lisbon", "tofino", "bam", "broc", "cork",
    "vanimo", "managua", "bukavu",
    "romaO", "brocO", "corkO", "vikO", "bamO",
]

NAMES = MPL_NAMES + CRAMERI_NAMES

# Qualitative maps: discrete lists of colors rather than continuous ramps.
QNAMES = ["tab10", "tab20", "Set1"]

NA = 65
OUT = Path(__file__).resolve().parent.parent / "src" / "fplotlib_cmap.f90"

REST = r'''
contains

    pure logical function eq_ci(a, b)
        character(len=*), intent(in) :: a, b
        integer :: i, ia, ib
        eq_ci = .false.
        if (len(a) /= len(b)) return
        do i = 1, len(a)
            ia = iachar(a(i:i))
            ib = iachar(b(i:i))
            if (ia >= iachar('A') .and. ia <= iachar('Z')) ia = ia + 32
            if (ib >= iachar('A') .and. ib <= iachar('Z')) ib = ib + 32
            if (ia /= ib) return
        end do
        eq_ci = .true.
    end function eq_ci

    ! Case-insensitive colormap lookup, with a "_r" suffix meaning the map
    ! read backwards. An unknown name falls back to viridis, the default.
    pure function cmap_from_str(name) result(id)
        character(len=*), intent(in) :: name
        integer :: id, i, n
        character(len=32) :: c
        logical :: rev

        c = adjustl(name)
        n = len_trim(c)
        rev = .false.
        if (n > 2) then
            if (eq_ci(c(n - 1:n), "_r")) then
                rev = .true.
                n = n - 2
            end if
        end if

        id = CMAP_VIRIDIS
        do i = 1, CMAP_QUAL_COUNT
            if (len_trim(QNAMES(i)) == n) then
                if (eq_ci(c(1:n), QNAMES(i)(1:n))) then
                    id = CMAP_QUAL + i - 1
                    if (rev) id = id + CMAP_REVERSED
                    return
                end if
            end if
        end do
        do i = 1, CMAP_COUNT
            if (len_trim(NAMES(i)) == n) then
                if (eq_ci(c(1:n), NAMES(i)(1:n))) then
                    id = i - 1
                    exit
                end if
            end if
        end do
        ! One alias matplotlib keeps for compatibility.
        if (eq_ci(c(1:n), "grey")) id = CMAP_GRAY
        if (rev) id = id + CMAP_REVERSED
    end function cmap_from_str

    pure function cmap_name(id) result(s)
        integer, intent(in) :: id
        character(len=32) :: s
        if (modulo(id, CMAP_REVERSED) >= CMAP_QUAL) then
            s = QNAMES(modulo(id, CMAP_REVERSED) - CMAP_QUAL + 1)
        else
            s = NAMES(modulo(id, CMAP_REVERSED) + 1)
        end if
        if (id >= CMAP_REVERSED) s = trim(s) // "_r"
    end function cmap_name

    ! Color at position t in [0, 1], linearly interpolated between anchors.
    pure subroutine cmap_rgb(id, t, r, g, b)
        integer, intent(in) :: id
        real(dp), intent(in) :: t
        integer, intent(out) :: r, g, b
        real(dp) :: u, f
        integer :: i0, i1, m, base, nq, k

        m = id
        u = t
        ! A NaN would otherwise propagate into the index arithmetic below.
        if (u /= u) u = 0.0_dp
        if (m >= CMAP_REVERSED) then
            m = m - CMAP_REVERSED
            u = 1.0_dp - u
        end if
        if (m >= CMAP_QUAL) then
            ! A list of colors: matplotlib takes the int(t*N)th entry whole.
            k = m - CMAP_QUAL
            if (k < 0 .or. k >= CMAP_QUAL_COUNT) k = 0
            nq = QSIZE(k + 1)
            ! Reversing a list reverses the entries, which is not the same
            ! as indexing with 1-t at the boundary between two of them.
            if (id >= CMAP_REVERSED) u = 1.0_dp - u
            i0 = int(max(0.0_dp, min(1.0_dp, u)) * real(nq, dp))
            i0 = max(0, min(nq - 1, i0))
            if (id >= CMAP_REVERSED) i0 = nq - 1 - i0
            base = 3 * (QOFF(k + 1) + i0)
            r = QDATA(base + 1)
            g = QDATA(base + 2)
            b = QDATA(base + 3)
            return
        end if
        if (m < 0 .or. m >= CMAP_COUNT) m = CMAP_VIRIDIS
        base = 3 * CMAP_N_ANCHOR * m

        u = max(0.0_dp, min(1.0_dp, u)) * real(CMAP_N_ANCHOR - 1, dp)
        i0 = int(u)
        if (i0 > CMAP_N_ANCHOR - 2) i0 = CMAP_N_ANCHOR - 2
        i1 = i0 + 1
        f = u - real(i0, dp)

        r = lerp(DATA(base + 3*i0 + 1), DATA(base + 3*i1 + 1), f)
        g = lerp(DATA(base + 3*i0 + 2), DATA(base + 3*i1 + 2), f)
        b = lerp(DATA(base + 3*i0 + 3), DATA(base + 3*i1 + 3), f)
    end subroutine cmap_rgb

    pure function cmap_color(id, t) result(hex)
        integer, intent(in) :: id
        real(dp), intent(in) :: t
        character(len=7) :: hex
        integer :: r, g, b
        call cmap_rgb(id, t, r, g, b)
        hex = "#" // hex2(r) // hex2(g) // hex2(b)
    end function cmap_color

    pure function lerp(a, b, f) result(v)
        integer, intent(in) :: a, b
        real(dp), intent(in) :: f
        integer :: v
        v = nint(real(a, dp) + f * real(b - a, dp))
        v = max(0, min(255, v))
    end function lerp

    pure function hex2(v) result(s)
        integer, intent(in) :: v
        character(len=2) :: s
        character(len=16), parameter :: D = "0123456789abcdef"
        integer :: w
        w = max(0, min(255, v))
        s(1:1) = D(w / 16 + 1:w / 16 + 1)
        s(2:2) = D(modulo(w, 16) + 1:modulo(w, 16) + 1)
    end function hex2

end module fplotlib_cmap
'''


def _sample_lut(lut: list[tuple[float, float, float]]) -> list[int]:
    """Sample an N-entry RGB LUT using matplotlib ListedColormap indexing."""
    n = len(lut)
    vals: list[int] = []
    for i in range(NA):
        t = i / (NA - 1)
        idx = n - 1 if t >= 1.0 else min(int(t * n), n - 1)
        r, g, b = lut[idx]
        vals += [round(r * 255), round(g * 255), round(b * 255)]
    return vals


def values_crameri_dir(name: str, crameri_dir: Path) -> list[int]:
    path = crameri_dir / f"{name}.txt"
    lut: list[tuple[float, float, float]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) >= 3:
            lut.append((float(parts[0]), float(parts[1]), float(parts[2])))
    return _sample_lut(lut)


def values_mpl(name: str) -> list[int]:
    import matplotlib

    m = matplotlib.colormaps[name]
    vals: list[int] = []
    for i in range(NA):
        r, g, b, _ = m(i / (NA - 1))
        vals += [round(r * 255), round(g * 255), round(b * 255)]
    return vals


def values_crameri(name: str, crameri_dir: Path | None) -> list[int]:
    if crameri_dir is not None:
        return values_crameri_dir(name, crameri_dir)
    import cmcrameri

    m = cmcrameri.cm.cmaps[name]
    vals: list[int] = []
    for i in range(NA):
        r, g, b, _ = m(i / (NA - 1))
        vals += [round(r * 255), round(g * 255), round(b * 255)]
    return vals


def _extract_existing_array(src: str, array_name: str) -> list[int]:
    m = re.search(
        rf"integer,\s*parameter\s*::\s*{array_name}\([^)]*\)\s*=\s*\[([^\]]*)\]",
        src,
        re.S,
    )
    if not m:
        raise RuntimeError(f"Could not find {array_name} in {OUT}")
    return [int(x) for x in re.findall(r"\d+", m.group(1))]


def load_mpl_and_qual(preserve_mpl: bool) -> tuple[list[int], list[int], list[int]]:
    if preserve_mpl:
        src = OUT.read_text(encoding="utf-8")
        data_all = _extract_existing_array(src, "DATA")
        need = 3 * NA * len(MPL_NAMES)
        if len(data_all) < need:
            raise RuntimeError(f"Existing DATA too short ({len(data_all)} < {need})")
        qsize = _extract_existing_array(src, "QSIZE")
        qdata = _extract_existing_array(src, "QDATA")
        return data_all[:need], qsize, qdata

    import matplotlib

    mpl_flat: list[int] = []
    for name in MPL_NAMES:
        mpl_flat += values_mpl(name)
    qsize: list[int] = []
    qdata: list[int] = []
    for name in QNAMES:
        colors = list(matplotlib.colormaps[name].colors)
        qsize.append(len(colors))
        for r, g, b in colors:
            qdata += [round(r * 255), round(g * 255), round(b * 255)]
    return mpl_flat, qsize, qdata


def rows(vals: list[int]) -> list[str]:
    out: list[str] = []
    line: list[str] = []
    for v in vals:
        line.append(f"{v:4d}")
        if len(line) == 12:
            out.append(", ".join(line))
            line = []
    if line:
        out.append(", ".join(line))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--crameri-dir",
        type=Path,
        default=None,
        help="Directory containing cmcrameri *.txt LUT files",
    )
    parser.add_argument(
        "--preserve-mpl",
        action="store_true",
        help="Reuse existing matplotlib and qualitative tables from src/fplotlib_cmap.f90",
    )
    args = parser.parse_args()

    n = len(NAMES)
    width = max(len(x) for x in NAMES + QNAMES)

    mpl_flat, qsize, qdata = load_mpl_and_qual(args.preserve_mpl)
    flat = list(mpl_flat)
    for name in CRAMERI_NAMES:
        flat += values_crameri(name, args.crameri_dir)

    qoff: list[int] = []
    acc = 0
    for sz in qsize:
        qoff.append(acc)
        acc += sz

    head = [
        "! fplotlib_cmap - matplotlib and Scientific Colour Maps colormaps.",
        "!",
        f"! Generated by tools/gen_cmap.py; do not edit by hand. Each continuous map is {NA}",
        "! evenly spaced anchors sampled and linearly interpolated in between, which",
        "! reproduces the smooth originals to within a level or two out of 255.",
        "!",
        "! Scientific Colour Maps (batlow, roma, vik, oslo, etc.):",
        "! Fabio Crameri (https://www.fabiocrameri.ch/colourmaps/), MIT License.",
        "! Crameri, F. (2018). Scientific colour maps. Zenodo.",
        "! https://doi.org/10.5281/zenodo.1243862",
        "module fplotlib_cmap",
        "    use fplotlib_style, only: dp",
        "    implicit none",
        "    private",
        "",
        "    public :: CMAP_VIRIDIS, CMAP_PLASMA, CMAP_INFERNO, CMAP_MAGMA",
        "    public :: CMAP_GRAY, CMAP_COOLWARM, CMAP_REVERSED, CMAP_QUAL",
        "    public :: cmap_from_str, cmap_color, cmap_rgb, cmap_name",
        "",
        f"    integer, parameter, public :: CMAP_N_ANCHOR = {NA}",
        f"    integer, parameter, public :: CMAP_COUNT = {n}",
        "",
        '    ! A reversed map ("viridis_r") is the same table read backwards, so it',
        "    ! is the same id with this flag added rather than a table of its own.",
        "    integer, parameter :: CMAP_REVERSED = 1000",
        "",
        "    ! Ids at or above this are qualitative maps, held in QDATA below.",
        "    integer, parameter :: CMAP_QUAL = 500",
        "",
    ]
    for c in ["viridis", "plasma", "inferno", "magma", "gray", "coolwarm"]:
        head.append(f"    integer, parameter :: CMAP_{c.upper()} = {NAMES.index(c)}")
    head.append("")
    head.append(f"    character(len={width}), parameter :: NAMES(CMAP_COUNT) = [ &")
    for j, name in enumerate(NAMES):
        end = "]" if j == n - 1 else ", &"
        head.append(f'        "{name:<{width}}"{end}')
    head.append("")
    head.append("    ! The anchors of every map, one map after another.")
    head.append("    integer, parameter :: DATA(3 * CMAP_N_ANCHOR * CMAP_COUNT) = [ &")
    rs = rows(flat)
    for j, r in enumerate(rs):
        end = "]" if j == len(rs) - 1 else ", &"
        head.append(f"        {r}{end}")

    head += [
        "    ! ------------------------------------------------------------------",
        "    ! Qualitative maps. These are lists of colors, not a ramp: matplotlib",
        "    ! picks the entry at int(t*N) and never blends two of them, so they",
        "    ! live in a table of their own rather than among the 65-anchor ramps.",
        "    ! ------------------------------------------------------------------",
        f"    integer, parameter :: CMAP_QUAL_COUNT = {len(QNAMES)}",
        f"    character(len={width}), parameter :: QNAMES(CMAP_QUAL_COUNT) = [ &",
    ]
    for j, name in enumerate(QNAMES):
        end = "]" if j == len(QNAMES) - 1 else ", &"
        head.append(f'        "{name:<{width}}"{end}')
    head.append(
        f"    integer, parameter :: QSIZE(CMAP_QUAL_COUNT) = [{', '.join(str(x) for x in qsize)}]"
    )
    head.append("    ! Where each map starts in QDATA, in colors.")
    head.append(
        f"    integer, parameter :: QOFF(CMAP_QUAL_COUNT) = [{', '.join(str(x) for x in qoff)}]"
    )
    head.append(f"    integer, parameter :: QDATA(3 * {acc}) = [ &")
    qrs = rows(qdata)
    for j, r in enumerate(qrs):
        end = "]" if j == len(qrs) - 1 else ", &"
        head.append(f"        {r}{end}")

    OUT.write_text("\n".join(head) + REST, encoding="utf-8")
    print(f"wrote {OUT} ({n} continuous + {len(QNAMES)} qualitative maps)")


if __name__ == "__main__":
    main()
