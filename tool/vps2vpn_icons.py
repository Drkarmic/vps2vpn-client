"""Draw the vps2vpn icons: a gradient rounded tile with a white "V" and dot.

Writes the app icon (.ico/.png) and the tray status icons for Windows,
Linux and macOS into the FlClash clone. Usage: python make_icons.py <repo>
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

REPO = sys.argv[1]
S = 1024  # draw big, shrink for smoothness

CORAL = (255, 138, 112)
DEEP = (230, 62, 92)
VIOLET = (139, 92, 246)
GREY_A = (150, 154, 170)
GREY_B = (98, 102, 120)
AMBER = (245, 166, 35)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(stops):
    """Diagonal gradient (top-left -> bottom-right) through the given stops."""
    g = Image.new("RGB", (S, S))
    px = g.load()
    n = len(stops) - 1
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * (S - 1))
            k = min(int(t * n), n - 1)
            px[x, y] = lerp(stops[k], stops[k + 1], t * n - k)
    return g


def mark(draw, scale=1.0, color=(255, 255, 255, 255), cx=0.5, cy=0.5):
    """The V and its dot, in a box of size S*scale centred at (cx, cy)."""
    w = S * scale
    ox, oy = S * cx - w / 2, S * cy - w / 2
    pts = [(ox + w * 0.27, oy + w * 0.36), (ox + w * 0.5, oy + w * 0.76), (ox + w * 0.73, oy + w * 0.36)]
    lw = int(w * 0.115)
    draw.line(pts, fill=color, width=lw, joint="curve")
    for x, y in (pts[0], pts[2], pts[1]):
        r = lw / 2
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
    r = w * 0.08
    x, y = ox + w * 0.5, oy + w * 0.29
    draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def tile(stops, inset=0.0, radius=0.27, badge=None, shadow=False):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a = int(S * inset)
    box = [a, a, S - a, S - a]
    if shadow:
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            [box[0], box[1] + S * 0.025, box[2], box[3] + S * 0.025],
            radius=int((S - 2 * a) * radius), fill=(120, 30, 40, 110))
        img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(S * 0.025)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=int((S - 2 * a) * radius), fill=255)
    body = gradient(stops).convert("RGBA")
    # soft top highlight for depth
    hl = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    ImageDraw.Draw(hl).ellipse([-S * 0.3, -S * 0.75, S * 1.3, S * 0.45], fill=(255, 255, 255, 38))
    body = Image.alpha_composite(body, hl.filter(ImageFilter.GaussianBlur(S * 0.04)))
    img.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(img)
    mark(d, scale=1 - 2 * inset)
    if badge:
        r = S * 0.17
        cx, cy = S - a - r - S * 0.045, S - a - r - S * 0.045
        d.ellipse([cx - r - S * 0.04, cy - r - S * 0.04, cx + r + S * 0.04, cy + r + S * 0.04], fill=(255, 255, 255, 255))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=badge + (255,))
    return img


def small(img, size):
    return img.resize((size, size), Image.LANCZOS)


def save_ico(img, path, sizes):
    small(img, 256).save(path, format="ICO", sizes=[(s, s) for s in sizes])


def out(*parts):
    p = os.path.join(REPO, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


app = tile([CORAL, DEEP, VIOLET], inset=0.06, shadow=True)
save_ico(app, out("windows", "runner", "resources", "app_icon.ico"), [16, 20, 24, 32, 40, 48, 64, 128, 256])
save_ico(app, out("assets", "images", "icon.ico"), [16, 24, 32, 48, 64, 128, 256])
small(app, 550).save(out("assets", "images", "icon.png"))
small(app, 1024).save(out("assets_source", "images", "icon", "vps2vpn-1024.png"))

# Tray: 1 off (grey), 2 on (coral), 3 on + whole-system (coral->violet),
# 4 safe mode (grey with amber badge).
tray = {
    1: tile([GREY_A, GREY_B], radius=0.3),
    2: tile([CORAL, DEEP], radius=0.3),
    3: tile([CORAL, DEEP, VIOLET], radius=0.3, badge=VIOLET),
    4: tile([GREY_A, GREY_B], radius=0.3, badge=AMBER),
}
for n, img in tray.items():
    save_ico(img, out("assets", "images", "tray", "windows", f"status_{n}.ico"), [16, 20, 24, 32, 40, 48, 64])
    for scale, folder in ((1, ""), (2, "2.0x"), (3, "3.0x"), (4, "4.0x")):
        parts = ["assets", "images", "tray", "unix"] + ([folder] if folder else []) + [f"status_{n}.png"]
        small(img, 18 * scale).save(out(*parts))

# macOS template icons are black shapes the system tints.
for n in (1, 4):
    tmpl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mark(ImageDraw.Draw(tmpl), scale=1.15, color=(0, 0, 0, 255))
    if n == 4:
        d = ImageDraw.Draw(tmpl)
        r = S * 0.12
        d.ellipse([S - 2.2 * r, S - 2.2 * r, S - 0.2 * r, S - 0.2 * r], fill=(0, 0, 0, 255))
    for scale, folder in ((1, ""), (2, "2.0x"), (3, "3.0x"), (4, "4.0x")):
        parts = ["assets", "images", "tray", "macos"] + ([folder] if folder else []) + [f"status_{n}.png"]
        small(tmpl, 18 * scale).save(out(*parts))

# Preview sheet for review.
sheet = Image.new("RGBA", (5 * 220, 240), (247, 244, 242, 255))
sheet.alpha_composite(small(app, 200), (10, 20))
for i, n in enumerate((1, 2, 3, 4)):
    sheet.alpha_composite(small(tray[n], 120), (240 + i * 210, 60))
sheet.save(os.path.join(REPO, "build", "icons-preview.png"))
print("ok")
