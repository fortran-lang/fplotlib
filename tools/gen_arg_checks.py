#!/usr/bin/env python3
"""Write the argument checks at the top of every public plotting procedure.

Run from the repository root after adding or changing a procedure in
src/fplotlib.f90:

    python3 tools/gen_arg_checks.py

A call that breaks a documented precondition stops with a message naming
the call (see fplotlib_status). For the plotting API that means every real
argument is checked where it comes in, against the table below, rather
than wherever the drawing first trips over a bad value. The script removes
the checks it wrote last time and writes them again, so running it twice
changes nothing; CI runs it and fails if src/fplotlib.f90 is out of date.
It also fails on a real argument the table does not classify.

Each real argument is one of:
  unit      finite, in [0, 1]                 (alpha)
  size      finite, >= 0                      (widths and sizes in points)
  positive  finite, > 0                       (scales, thresholds)
  finite    any finite value                  (angles, offsets, limits)
  margin    finite, > -0.5                    (margins)
  pad       finite, at most 1e9 either way    (pad_inches; checked whether cropped or not)
  thresh    1e-300 to 1e300                   (symlog linthresh: its linear part must be normal)
  linscale  1e-6 to 1e6                       (symlog linscale)
  layout    finite, at most 1000 either way    (fractions of the figure or axes)
  ratio     1e-3 to 1e3                        (a shape's width to height)
  errors    not negative, NaN allowed         (error bar lengths, arrays only)
  dashes    finite, >= 0, not all zero        (dash patterns, arrays only)
  data      may be missing: NaN is left out of the picture
  own       checked by hand in the procedure itself

and each integer argument one of:
  count     1 to a million                     (bins, columns, ticks)
  grid      1 to a thousand                    (the side of a 2D grid of cells)
  nonneg    not negative                       (minimum counts)
  digits    0 to 17                            (decimals; a double has no more)
  any       any value
  own       checked by hand in the procedure itself
"""
import re, sys
p = 'src/fplotlib.f90'
L = open(p).read().split('\n')

BY_NAME = {
    'alpha': 'unit', 'bbox_alpha': 'unit',
    'lw': 'size', 'linewidth': 'size', 'linewidths': 'size', 'markersize': 'size',
    'markeredgewidth': 'size', 'fontsize': 'size', 'labelsize': 'size',
    'length': 'size', 'capsize': 'size', 'elinewidth': 'size', 'arrowlw': 'size',
    's': 'size', 'rwidth': 'size', 'fraction': 'size', 'shrink': 'size',
    'radius': 'size', 'arrowsize': 'size', 'density': 'size', 'linelength': 'size',
    'labelsep': 'size',
    'dpi': 'own', 'fps': 'own', 'ratio': 'own',
    'linthresh': 'thresh', 'linscale': 'linscale', 'gamma': 'positive', 'base': 'positive',
    'aspect': 'positive',
    'rotation': 'finite', 'angle': 'finite', 'startangle': 'finite', 'elev': 'finite',
    'azim': 'finite', 'labelpad': 'finite', 'offset': 'finite', 'vmin': 'finite',
    'vmax': 'finite', 'vcenter': 'finite', 'lineoffset': 'finite', 'pad': 'finite',
    'bbox_pad': 'finite', 'whis': 'finite', 'whole': 'finite', 'left': 'finite',
    'right': 'finite', 'bottom': 'finite', 'top': 'finite', 'wspace': 'finite',
    'hspace': 'finite', 'pad_inches': 'pad', 'pctdistance': 'finite',
    'labeldistance': 'finite', 'padding': 'finite', 'u': 'finite',
    'm': 'margin',
    # where things go: missing data
    'x': 'data', 'y': 'data', 'xtext': 'data', 'ytext': 'data', 'dx': 'data',
    'dy': 'data', 'slope': 'data', 'xmin': 'data', 'xmax': 'data', 'ymin': 'data',
    'ymax': 'data', 'position': 'data', 'lo': 'data', 'hi': 'data',
}
BY_PROC = {
    ('subplots_adjust', 'left'): 'layout', ('subplots_adjust', 'right'): 'layout',
    ('subplots_adjust', 'bottom'): 'layout', ('subplots_adjust', 'top'): 'layout',
    ('subplots_adjust', 'wspace'): 'layout', ('subplots_adjust', 'hspace'): 'layout',
    ('colorbar', 'fraction'): 'layout', ('colorbar', 'pad'): 'layout',
    ('colorbar', 'shrink'): 'layout', ('colorbar', 'aspect'): 'ratio',
    ('set_fontsize', 'size'): 'size', ('set_fontsize', 'title'): 'size',
    ('set_fontsize', 'labels'): 'size', ('set_fontsize', 'ticks'): 'size',
    ('set_fontsize', 'legend'): 'size',
    # matplotlib's own rule is any number; fplotlib has always kept zorder
    # nonnegative.
    ('set_zorder', 'z'): 'size',
    ('eventplot', 'linelength'): 'finite',
    ('spy', 'precision'): 'finite',
    ('margins', 'x'): 'margin', ('margins', 'y'): 'margin',
    ('xlim', 'xmin'): 'own', ('xlim', 'xmax'): 'own',
    ('ylim', 'ymin'): 'own', ('ylim', 'ymax'): 'own',
    ('zlim', 'lo'): 'own', ('zlim', 'hi'): 'own',
    ('quiver', 'width'): 'size', ('quiver', 'scale'): 'positive',
    ('add_arrow', 'width'): 'size',
    ('boxplot', 'width'): 'size', ('violinplot', 'width'): 'size',
    ('bar', 'width'): 'finite', ('barh', 'height'): 'finite',
    ('add_rectangle', 'width'): 'finite', ('add_rectangle', 'height'): 'finite',
    ('add_ellipse', 'width'): 'finite', ('add_ellipse', 'height'): 'finite',
    ('secondary_xaxis', 'scale'): 'finite', ('secondary_yaxis', 'scale'): 'finite',
    ('quiver3d', 'length'): 'finite',
}
ARRAYS = {
    'bounds': 'finite', 'width_ratios': 'positive', 'height_ratios': 'positive', 'bbox_to_anchor': 'finite',
    'vals': 'finite', 'extent': 'finite', 'boundaries': 'finite', 'col_widths': 'size',
    'levels': 'finite', 'explode': 'finite', 'dashes': 'dashes', 'bin_edges': 'finite',
    'figsize': 'own', 'rect': 'own',
    'yerr': 'errors', 'xerr': 'errors', 'yerr_lo': 'errors', 'yerr_hi': 'errors',
    'xerr_lo': 'errors', 'xerr_hi': 'errors',
    'col_widths': 'size',
}
# Arrays of data, which may hold missing values. An array argument that is
# in neither table stops the script.
DATA_ARRAYS = {
    'x', 'y', 'z', 'u', 'v', 'w', 'c', 'a', 'sizes', 'cvals', 'positions', 'xranges',
    'yrange', 'dz', 'theta', 'r', 'values', 'y1', 'y2', 'x1', 'x2', 'height',
    'bottom', 'width', 'left', 'ydata', 'weights', 'xy', 'xy1', 'xy2',
}
INTS = {
    'ncol': 'count', 'nbins': 'count', 'markevery': 'count', 'bins': 'count',
    'gridsize': 'grid', 'nrows': 'count', 'ncols': 'count', 'colspan': 'count',
    'rowspan': 'count', 'mincnt': 'nonneg', 'decimals': 'digits',
    'scilimits': 'any', 'ij': 'any', 'm': 'own', 'n': 'own', 'i': 'own',
    'num': 'own', 'loc': 'own', 'shape': 'own',
}
# spy's m and n only set the axis limits; they allocate nothing.
INTS_BY_PROC = {('spy', 'm'): 'any', ('spy', 'n'): 'any', ('hist2d', 'bins'): 'grid'}
IHELPER = {'count': 'check_count_arg', 'grid': 'check_grid_arg', 'nonneg': 'check_nonneg_arg',
           'digits': 'check_digits_arg'}
IAHELPER = {'count': 'check_count_args', 'grid': 'check_grid_args'}
HELPER = {'layout': 'check_layout_arg', 'ratio': 'check_ratio_arg', 'unit': 'check_unit_arg', 'size': 'check_size_arg', 'positive': 'check_positive_arg',
          'finite': 'check_finite_arg', 'margin': 'check_margin_arg', 'pad': 'check_pad_arg',
          'thresh': 'check_thresh_arg', 'linscale': 'check_linscale_arg'}
AHELPER = {'errors': 'check_errors_arg', 'dashes': 'check_dashes_arg', 'size': 'check_size_args', 'positive': 'check_positive_args', 'finite': 'check_finite_args'}
# Each block the script writes starts with this line; only such blocks are
# ever removed, so a check written by hand is left alone.
MARK = '        ! Arguments checked as tools/gen_arg_checks.py tables them.'
GEN = re.compile(r'^        call check_\w+_args?\("')

# Drop what an earlier run generated, and the blank line it added.
out = []
i = 0
while i < len(L):
    if L[i] == MARK:
        j = i + 1
        while j < len(L) and GEN.match(L[j]): j += 1
        if out and out[-1].strip() == '' and j < len(L) and L[j].strip() == '':
            out.pop()
        i = j
        continue
    out.append(L[i]); i += 1
L = out

public = set()
for l in L:
    m = re.match(r'\s*public\s*::\s*(.*)', l)
    if m: public |= {x.strip() for x in m.group(1).split(',')}
spec2gen = {}; cur = None
for l in L:
    m = re.match(r'\s*interface\s+(\w+)\s*$', l)
    if m: cur = m.group(1); continue
    if re.match(r'\s*end interface', l): cur = None; continue
    if cur:
        m = re.match(r'\s*module procedure\s+(.*)', l)
        if m:
            for x in m.group(1).split(','): spec2gen[x.strip()] = cur
DECL = re.compile(r'\s*(real|integer|character|logical|type\s*\(|class\s*\(|procedure)\b.*::')

def split_names(d):
    names = d.split('::', 1)[1]
    depth = 0; c = ''; parts = []
    for ch in names:
        if ch == '(': depth += 1
        if ch == ')': depth -= 1
        if ch == ',' and depth == 0: parts.append(c); c = ''
        else: c += ch
    parts.append(c)
    return [x.strip().rstrip('&').strip() for x in parts if x.strip().rstrip('&').strip()]

unknown = []
out = []
i = 0
while i < len(L):
    l = L[i]
    m = re.match(r'\s{4}(?:recursive\s+|pure\s+)?(subroutine|function)\s+(\w+)\s*\(', l)
    if not m:
        out.append(l); i += 1; continue
    name = m.group(2)
    user = spec2gen.get(name, name)
    out.append(l); i += 1
    # The methods of type(axes), ax_plot and the rest, are checked too,
    # under the name of the call they stand for.
    if name.startswith('ax_'):
        user = spec2gen.get(name[3:], name[3:])
    elif user not in public:
        continue
    while out[-1].rstrip().endswith('&'):
        out.append(L[i]); i += 1
    decls = []
    while i < len(L) and (DECL.match(L[i]) or (decls and decls[-1].rstrip().endswith('&'))):
        decls.append(L[i]); out.append(L[i]); i += 1
    calls = []
    for d in decls:
        if d.strip().startswith('integer') and 'intent(in)' in d:
            for part in split_names(d):
                arg = part.split('(')[0].strip()
                kind = INTS_BY_PROC.get((user, arg), INTS.get(arg))
                if kind is None:
                    unknown.append((user, arg)); continue
                if kind in ('any', 'own'): continue
                if '(' in part:
                    calls.append(f'        call {IAHELPER[kind]}("{user}", "{arg}", {arg})')
                else:
                    calls.append(f'        call {IHELPER[kind]}("{user}", "{arg}", {arg})')
            continue
        if not d.strip().startswith('real(dp)') or 'intent(in)' not in d:
            continue
        opt = 'optional' in d
        for part in split_names(d):
            arg = part.split('(')[0].strip()
            if '(' in part:
                kind = ARRAYS.get(arg)
                if kind is None:
                    if arg not in DATA_ARRAYS:
                        unknown.append((user, arg))
                    continue
                if kind == 'own': continue
                calls.append(f'        call {AHELPER[kind]}("{user}", "{arg}", {arg})')
                continue
            kind = BY_PROC.get((user, arg), BY_NAME.get(arg))
            if kind is None:
                unknown.append((user, arg)); continue
            if kind in ('data', 'own'): continue
            calls.append(f'        call {HELPER[kind]}("{user}", "{arg}", {arg})')
    if calls:
        if out[-1].strip() != '': out.append('')
        out.append(MARK)
        out.extend(calls)
        if i < len(L) and L[i].strip() != '': out.append('')
open(p, 'w').write('\n'.join(out))
if unknown:
    print('UNCLASSIFIED:', unknown); sys.exit(1)
