# Generates Troc's provisional launcher icon (two opposing arrows) for every Android density, in the main and debug source sets.
# Usage: python3 tools/troc_launcher_icon.py [repo-root]   (requires Pillow)
import sys
from PIL import Image, ImageDraw
root = sys.argv[1] if len(sys.argv) > 1 else "."
N = 1080  # adaptive canvas, 108dp x10
ORANGE, WHITE = (247,147,26,255), (245,245,245,255)

def arrow(d, y, x0, x1, color, thick=62, head=118):
    # horizontal arrow from x0 to x1
    s = 1 if x1 > x0 else -1
    d.rectangle([min(x0, x1 - s*head), y - thick//2, max(x0, x1 - s*head), y + thick//2], fill=color)
    d.polygon([(x1, y), (x1 - s*head, y - head), (x1 - s*head, y + head)], fill=color)

def foreground():
    im = Image.new('RGBA', (N, N), (0,0,0,0)); d = ImageDraw.Draw(im)
    # safe zone: central 66dp circle => x from about 300 to 780
    arrow(d, 440, 330, 750, ORANGE)
    arrow(d, 640, 750, 330, WHITE)
    return im

def background(color):
    return Image.new('RGBA', (N, N), color)

def legacy(bg, fg):
    # legacy icon: rounded square, content = central 72/108 area
    full = Image.alpha_composite(bg, fg)
    c = full.crop((180, 180, 900, 900))
    mask = Image.new('L', c.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, c.size[0]-1, c.size[1]-1], radius=150, fill=255)
    out = Image.new('RGBA', c.size, (0,0,0,0)); out.paste(c, (0,0), mask); return out

dens = {'mdpi':(108,48), 'hdpi':(162,72), 'xhdpi':(216,96), 'xxhdpi':(324,144), 'xxxhdpi':(432,192)}
for variant, bgcol in (('main', (21,23,28,255)), ('debug', (60,42,8,255))):
    fg, bg = foreground(), background(bgcol); leg = legacy(bg, fg)
    for d, (a, l) in dens.items():
        base = f'{root}/android/app/src/{variant}/res'
        fg.resize((a,a), Image.LANCZOS).save(f'{base}/drawable-{d}/ic_launcher_foreground.png')
        bg.resize((a,a), Image.LANCZOS).save(f'{base}/drawable-{d}/ic_launcher_background.png')
        leg.resize((l,l), Image.LANCZOS).save(f'{base}/mipmap-{d}/launcher_icon.png')
        if variant == 'main':
            leg.resize((l,l), Image.LANCZOS).save(f'{base}/mipmap-{d}/ic_launcher.png')
