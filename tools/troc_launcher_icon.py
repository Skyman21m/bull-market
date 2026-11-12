# Generates Troc's Android launcher icon: one bull-robot head seen from the front, split down the middle into two halves,
# the two peers, left in Bitcoin orange and right light. Wide crescent horns, bolts for ears, a square head with rectangular
# eyes, a muzzle plate with oval nostrils, and a golden half-ring hanging from it.
# Outputs, for every density: the adaptive icon layers (ic_launcher_foreground, ic_launcher_background) in the main and debug
# source sets, the monochrome layer for Android 13 themed icons (ic_launcher_monochrome, main only: debug falls back to it),
# and the legacy launcher_icon.png (plus ic_launcher.png in main). main/res/mipmap-anydpi-v26/launcher_icon.xml declares the layers.
# The monochrome layer is the head alone: in one colour the ring would merge into the muzzle.
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
ORANGE, LIGHT, GOLD, WHITE = (247, 147, 26), (243, 238, 230), (255, 210, 63), (255, 255, 255)
BACKGROUNDS = {'main': (21, 23, 28), 'debug': (60, 42, 8)}
DENSITIES = {'mdpi': (108, 48), 'hdpi': (162, 72), 'xhdpi': (216, 96), 'xxhdpi': (324, 144), 'xxxhdpi': (432, 192)}

# The mark, in canvas pixels around the centre of the head, y down. It is symmetric: left-side shapes are mirrored.
HEAD = (0, 0, 304, 234, 49)  # centre x, centre y, width, height, corner radius
HORN = [(-76, -78), (-180, -78), (-234, -102), (-246, -166)]  # centre line of the left horn, a cubic curve from inside the head
HORN_BASE, HORN_TIP = 64, 20  # widths; the tip is rounded so that it survives at 40 px
BOLT = (-166, -4, 39, 64, 13)  # the left bolt, in place of an ear
EYE = (-67, -20, 68, 49, 12)  # the left eye
MUZZLE = (0, 143, 213, 149, 43)  # a plate over the bottom of the head
NOSTRIL = (-43, 139, 17, 21)  # the left nostril: centre x, centre y, radii
RING = (0, 206, 42, 24)  # centre x, centre y, radius, width of the half-ring hanging from the muzzle
GAP = 20  # the cuts in the background colour, down the middle and above the muzzle: about 1 px wide at 40 px
OPTICAL_DROP = 20  # the horns weigh less than the head: centre the mark a little below its bounding box centre


def rounded_rect(cx, cy, w, h, r, steps=24):
    pts = []
    for ox, oy, a0 in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        for i in range(steps + 1):
            a = math.radians(a0 + 90 * i / steps)
            pts.append((cx + ox + r * math.cos(a), cy + oy + r * math.sin(a)))
    return pts


def ellipse(cx, cy, rx, ry, steps=64):
    return [(cx + rx * math.cos(2 * math.pi * i / steps), cy + ry * math.sin(2 * math.pi * i / steps)) for i in range(steps)]


def horn(p, steps=96):
    """Outline of a stroke along the cubic curve p, tapering from HORN_BASE to HORN_TIP, with a round tip."""
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
        hw = (HORN_BASE + (HORN_TIP - HORN_BASE) * t) / 2
        left.append((x - dy / n * hw, y + dx / n * hw))
        right.append((x + dy / n * hw, y - dx / n * hw))
    dx, dy = tangent(1)
    phi, hw = math.atan2(dy, dx), HORN_TIP / 2
    cap = [(p[3][0] + hw * math.cos(phi + math.pi / 2 - math.pi * i / 32), p[3][1] + hw * math.sin(phi + math.pi / 2 - math.pi * i / 32)) for i in range(33)]
    return left + cap + right[::-1]


def half_ring(cx, cy, r, w, steps=64):
    """Lower half of a ring of radius r and width w, with round ends."""
    hw = w / 2
    outer = [(cx + (r + hw) * math.cos(math.pi * i / steps), cy + (r + hw) * math.sin(math.pi * i / steps)) for i in range(steps + 1)]
    inner = [(cx + (r - hw) * math.cos(math.pi * i / steps), cy + (r - hw) * math.sin(math.pi * i / steps)) for i in range(steps, -1, -1)]
    left_end = [(cx - r - hw * math.cos(math.pi * i / 16), cy - hw * math.sin(math.pi * i / 16)) for i in range(17)]
    right_end = [(cx + r - hw * math.cos(math.pi * i / 16), cy - hw * math.sin(math.pi * i / 16)) for i in range(17)]
    return outer + left_end + inner + right_end


def mirrored(pts):
    return [(-x, y) for x, y in pts]


def head():
    """Silhouette of the head: head, horns, bolts and muzzle."""
    bolt = rounded_rect(*BOLT)
    return [rounded_rect(*HEAD), horn(HORN), mirrored(horn(HORN)), bolt, mirrored(bolt), rounded_rect(*MUZZLE)]


def cuts():
    """Eyes, nostrils, the line above the muzzle and the line down the middle, in the background colour."""
    eye, nostril = rounded_rect(*EYE), ellipse(*NOSTRIL)
    mx, my, mw, mh, _ = MUZZLE
    top = my - mh / 2
    above_muzzle = [(mx - mw / 2, top - GAP), (mx + mw / 2, top - GAP), (mx + mw / 2, top), (mx - mw / 2, top)]
    middle = [(-GAP / 2, -C), (GAP / 2, -C), (GAP / 2, C), (-GAP / 2, C)]
    return [eye, mirrored(eye), nostril, mirrored(nostril), above_muzzle, middle]


def mask(shapes, holes=(), centre=None):
    """Coverage of shapes minus holes, drawn SS times larger, with the head centre at `centre`."""
    cx, cy = centre or layout()
    im = Image.new('L', (N * SS, N * SS), 0)
    d = ImageDraw.Draw(im)
    for group, fill in ((shapes, 255), (holes, 0)):
        for pts in group:
            d.polygon([((cx + x) * SS, (cy + y) * SS) for x, y in pts], fill=fill)
    return im


def layout():
    """Centre of the head, so that the whole mark is centred on the canvas."""
    ys = [y for pts in head() + [half_ring(*RING)] for _, y in pts]
    return C, C - (min(ys) + max(ys)) / 2 + OPTICAL_DROP


def marks():
    """Coverage (mode L, N x N) of the orange half, the light half and the ring, which never overlap."""
    ring = mask([half_ring(*RING)])
    face = ImageChops.subtract(mask(head(), cuts()), ring)
    left = Image.new('L', (N * SS, N * SS), 0)
    ImageDraw.Draw(left).rectangle([0, 0, C * SS - 1, N * SS], fill=255)
    orange, light = ImageChops.multiply(face, left), ImageChops.subtract(face, left)
    return orange.reduce(SS), light.reduce(SS), ring.reduce(SS)


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
    orange, light, ring = marks()
    halves = ImageChops.add(orange, light)
    check_safe_zone(ImageChops.add(halves, ring))
    fg = layer((ORANGE, orange), (LIGHT, light), (GOLD, ring))
    mono = layer((WHITE, halves))
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
