# Generates Troc's Android launcher icon: two robot heads with bull horns in place of antennas, leaning in until they touch,
# their inner horns crossed (peer to peer). The left head is Bitcoin orange, the right one light; eyes and mouths are cut out.
# Outputs, for every density: the adaptive icon layers (ic_launcher_foreground, ic_launcher_background) in the main and debug
# source sets, the monochrome layer for Android 13 themed icons (ic_launcher_monochrome, main only: debug falls back to it),
# and the legacy launcher_icon.png (plus ic_launcher.png in main). main/res/mipmap-anydpi-v26/launcher_icon.xml declares the layers.
# The shapes are drawn 4x larger then downscaled, for smooth edges. The script is deterministic: with the same Python and
# Pillow versions, two runs give identical bytes, and --check tells whether the committed files are what it generates.
# Usage: python3 tools/troc_launcher_icon.py [repo-root]           writes every file
#        python3 tools/troc_launcher_icon.py --check [repo-root]   writes nothing, exits 1 if a file differs or is missing
import io
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw

N = 1080  # adaptive icon canvas: 108 dp x 10
SS = 4  # supersampling factor
C = N / 2
SAFE_R = 330  # radius of the 66 dp safe zone: no launcher mask cuts inside it
ORANGE, LIGHT, WHITE = (247, 147, 26), (243, 238, 230), (255, 255, 255)
BACKGROUNDS = {'main': (21, 23, 28), 'debug': (60, 42, 8)}
DENSITIES = {'mdpi': (108, 48), 'hdpi': (162, 72), 'xhdpi': (216, 96), 'xxhdpi': (324, 144), 'xxxhdpi': (432, 192)}

# The left head, in canvas pixels, centred on the origin, y down, before its tilt. The right head is its mirror image.
HEAD_W, HEAD_H, HEAD_R = 255, 220, 56
TILT = 14  # degrees each head leans toward the other; their top inner corners meet on the axis
EYES = [(-49, -22, 63, 60, 20), (49, -22, 63, 60, 20)]  # centre x, centre y, width, height, corner radius
MOUTH = [(0, 52, 108, 27, 11)]  # one slot: a grille's bars vanish below 96 px and three slots read as teeth
LOOK = 13  # the eyes and mouth sit this much toward the other head, so the two faces look at each other
# Horns: tapered strokes along cubic curves, from deep inside the head (where an antenna would stand) to a rounded tip.
# The outer horn is a crescent; the inner one rises steeply so that it crosses the other head's inner horn above their contact.
INNER_HORN = [(31, -49), (56, -164), (96, -215), (130, -296)]
OUTER_HORN = [(-45, -45), (-157, -90), (-177, -190), (-125, -235)]
HORN_BASE, HORN_TIP = 74, 34  # widths
GAP = 14  # the light head is on top: the orange one is cut this far around it, so the two always read apart
OPTICAL_DROP = 10  # the horns weigh less than the heads: centre the mark a little below its bounding box centre


def rounded_rect(cx, cy, w, h, r, steps=24):
    pts = []
    for ox, oy, a0 in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        for i in range(steps + 1):
            a = math.radians(a0 + 90 * i / steps)
            pts.append((cx + ox + r * math.cos(a), cy + oy + r * math.sin(a)))
    return pts


def horn(p, grow=0.0, steps=96):
    """Outline of a stroke along the cubic curve p, tapering from HORN_BASE to HORN_TIP, with a round tip; `grow` widens it."""
    def at(t):
        u = 1 - t
        return tuple(u * u * u * p[0][k] + 3 * u * u * t * p[1][k] + 3 * u * t * t * p[2][k] + t * t * t * p[3][k] for k in (0, 1))

    def tangent(t):
        u = 1 - t
        return tuple(3 * u * u * (p[1][k] - p[0][k]) + 6 * u * t * (p[2][k] - p[1][k]) + 3 * t * t * (p[3][k] - p[2][k]) for k in (0, 1))

    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        (x, y), (dx, dy) = at(t), tangent(t)
        n = math.hypot(dx, dy)
        hw = (HORN_BASE + (HORN_TIP - HORN_BASE) * t) / 2 + grow
        left.append((x - dy / n * hw, y + dx / n * hw))
        right.append((x + dy / n * hw, y - dx / n * hw))
    dx, dy = tangent(1)
    phi, hw = math.atan2(dy, dx), HORN_TIP / 2 + grow
    cap = [(p[3][0] + hw * math.cos(phi + math.pi / 2 - math.pi * i / 32), p[3][1] + hw * math.sin(phi + math.pi / 2 - math.pi * i / 32)) for i in range(33)]
    return left + cap + right[::-1]


def head(grow=0.0):
    """Silhouette of the left head and its two horns, optionally grown outward."""
    return [rounded_rect(0, 0, HEAD_W + 2 * grow, HEAD_H + 2 * grow, HEAD_R + grow), horn(INNER_HORN, grow), horn(OUTER_HORN, grow)]


def face():
    return [rounded_rect(x + LOOK, y, w, h, r) for x, y, w, h, r in EYES + MOUTH]


def place(shapes, cx, cy, mirror=False):
    """Tilts shapes of the left head, moves them to (cx, cy), and mirrors them across the axis for the right head."""
    a = math.radians(TILT)
    out = []
    for pts in shapes:
        moved = []
        for x, y in pts:
            x, y = cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)
            moved.append((N - x if mirror else x, y))
        out.append(moved)
    return out


def layout():
    """Centre of the left head: its top inner corner touches the axis, and the whole mark is centred."""
    a = math.radians(TILT)
    reach = (HEAD_W / 2 - HEAD_R) * math.cos(a) + (HEAD_H / 2 - HEAD_R) * math.sin(a) + HEAD_R
    ys = [y for shape in place(head(), 0, 0) for _, y in shape]
    return C - reach, C - (min(ys) + max(ys)) / 2 + OPTICAL_DROP


def mask(shapes, holes=()):
    im = Image.new('L', (N * SS, N * SS), 0)
    d = ImageDraw.Draw(im)
    for group, fill in ((shapes, 255), (holes, 0)):
        for pts in group:
            d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)
    return im


def marks():
    """Coverage (mode L, N x N) of the orange head and of the light head, which never overlap."""
    cx, cy = layout()
    orange = ImageChops.subtract(mask(place(head(), cx, cy), place(face(), cx, cy)), mask(place(head(GAP), cx, cy, True)))
    light = mask(place(head(), cx, cy, True), place(face(), cx, cy, True))
    return orange.reduce(SS), light.reduce(SS)


def check_safe_zone(alpha):
    outside = Image.new('L', (N, N), 255)
    ImageDraw.Draw(outside).ellipse([C - SAFE_R, C - SAFE_R, C + SAFE_R, C + SAFE_R], fill=0)
    stray = ImageChops.multiply(alpha, outside).getbbox()
    if stray:
        sys.exit(f'the mark leaves the 66 dp safe zone at {stray}')


def layer(*coloured):
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    for colour, alpha in coloured:
        im = Image.alpha_composite(im, Image.merge('RGBA', [Image.new('L', (N, N), v) for v in colour] + [alpha]))
    return im


def legacy(bg, fg):
    """Pre-Android 8 icon: the central 72 dp of the layers in a rounded square."""
    c = Image.alpha_composite(bg, fg).crop((180, 180, 900, 900))
    m = Image.new('L', (720 * SS, 720 * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, 720 * SS - 1, 720 * SS - 1], radius=150 * SS, fill=255)
    c.putalpha(m.reduce(SS))
    return c


def png(im, size):
    buf = io.BytesIO()
    im.resize((size, size), Image.LANCZOS).save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def outputs():
    orange, light = marks()
    both = ImageChops.add(orange, light)
    check_safe_zone(both)
    fg = layer((ORANGE, orange), (LIGHT, light))
    mono = layer((WHITE, both))
    files = {}
    for variant, colour in BACKGROUNDS.items():
        bg = Image.new('RGBA', (N, N), colour + (255,))
        leg = legacy(bg, fg)
        res = f'android/app/src/{variant}/res'
        for d, (adaptive, legacy_size) in DENSITIES.items():
            files[f'{res}/drawable-{d}/ic_launcher_foreground.png'] = png(fg, adaptive)
            files[f'{res}/drawable-{d}/ic_launcher_background.png'] = png(bg, adaptive)
            files[f'{res}/mipmap-{d}/launcher_icon.png'] = png(leg, legacy_size)
            if variant == 'main':
                files[f'{res}/drawable-{d}/ic_launcher_monochrome.png'] = png(mono, adaptive)
                files[f'{res}/mipmap-{d}/ic_launcher.png'] = png(leg, legacy_size)
    return files


def main(args):
    check = '--check' in args
    rest = [a for a in args if a != '--check']
    root = rest[0] if rest else '.'
    stale = []
    for path, data in outputs().items():
        full = os.path.join(root, path)
        if check:
            if not os.path.isfile(full):
                stale.append(path)
                continue
            with open(full, 'rb') as f:
                if f.read() != data:
                    stale.append(path)
        else:
            with open(full, 'wb') as f:
                f.write(data)
    if stale:
        sys.exit('not what tools/troc_launcher_icon.py generates:\n' + '\n'.join(stale))


if __name__ == '__main__':
    main(sys.argv[1:])
