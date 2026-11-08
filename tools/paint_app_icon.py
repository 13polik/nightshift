"""NIGHT SHIFT app icon - 2D painted illustration (no 3D render).

THE HUNTER's head in profile: an elongated eyeless skull with sensory slits, a crest, a
hanging split jaw over a glowing throat, bone spines down the neck. Backlit by a red
emergency lamp, its jaw caught by a torch beam from the lower left. Painted procedurally
(vector shapes + NumPy lighting, grain and glow), supersampled for clean edges.

    python tools/paint_app_icon.py
Output: icon.png and assets/ui/app_icon/* (all export sizes + Android adaptive layers)
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "ui", "app_icon")
S = 2048  # supersampled canvas, downsampled to 1024 at the end
rng = np.random.default_rng(11)


# ------------------------------------------------------------------ helpers
def spline(points, closed=True, steps=24):
    """Catmull-Rom curve through control points (unit coords) -> pixel polygon."""
    p = np.array(points, dtype=float)
    n = len(p)
    out = []
    rng_i = range(n) if closed else range(n - 1)
    for i in rng_i:
        p0, p1, p2, p3 = p[(i - 1) % n], p[i], p[(i + 1) % n], p[(i + 2) % n]
        if not closed:
            p0 = p[max(i - 1, 0)]
            p3 = p[min(i + 2, n - 1)]
        for t in np.linspace(0, 1, steps, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return [(x * S, y * S) for x, y in out]


def mask_of(polys):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    for poly in polys:
        d.polygon(poly, fill=255)
    return np.asarray(m).astype(float) / 255


def blur(a, r):
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")
    return np.asarray(img.filter(ImageFilter.GaussianBlur(r))).astype(float) / 255


def shift(a, dx, dy):
    return np.roll(np.roll(a, int(dy), 0), int(dx), 1)


def fbm(octaves=5, base=6, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((S, S))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cells = base * 2 ** o
        g = r.random((cells, cells))
        img = Image.fromarray((g * 255).astype(np.uint8), "L").resize((S, S), Image.BICUBIC)
        out += np.asarray(img).astype(float) / 255 * amp
        tot += amp
        amp *= 0.5
    return out / tot


yy, xx = np.mgrid[0:S, 0:S] / S

# ------------------------------------------------------------------ shapes (unit coords, y down)
skull = spline([
    (0.25, 0.44), (0.28, 0.33), (0.36, 0.25), (0.47, 0.21), (0.58, 0.215), (0.69, 0.25),
    (0.79, 0.31), (0.88, 0.38), (0.955, 0.455), (0.95, 0.475), (0.87, 0.49), (0.76, 0.5),
    (0.66, 0.52), (0.58, 0.56), (0.53, 0.63), (0.51, 0.76), (0.5, 0.92), (0.51, 1.08),
    (0.14, 1.08), (0.17, 0.9), (0.2, 0.72), (0.22, 0.56),
])
crest = spline([(0.36, 0.26), (0.43, 0.17), (0.53, 0.13), (0.62, 0.15), (0.56, 0.2), (0.46, 0.215)])
# two hooked mandibles splitting around the throat (the Hunter's split jaw)
mand_a = spline([(0.6, 0.53), (0.68, 0.52), (0.76, 0.57), (0.81, 0.66), (0.8, 0.75), (0.775, 0.7), (0.745, 0.62), (0.68, 0.575), (0.61, 0.57)])
mand_b = spline([(0.57, 0.56), (0.63, 0.58), (0.68, 0.64), (0.7, 0.73), (0.675, 0.79), (0.66, 0.73), (0.63, 0.66), (0.58, 0.61)])
jaw = mand_a
spines = []
for t, ln in ((0.08, 0.12), (0.28, 0.15), (0.5, 0.13), (0.72, 0.1), (0.9, 0.08)):
    bx, by = 0.22 + (0.15 - 0.22) * t + 0.012, 0.56 + (0.98 - 0.56) * t
    tip = (bx - ln * 0.9, by - ln * 0.75)
    mid = (bx - ln * 0.35, by - ln * 0.5)
    spines.append(spline([(bx, by - 0.03), mid, tip, (bx - ln * 0.3, by - ln * 0.2), (bx + 0.008, by + 0.03)], closed=True, steps=6))
teeth = []
for i, x in enumerate(np.linspace(0.7, 0.9, 5)):
    y_top = 0.497 - (x - 0.7) * 0.06
    ln = 0.05 + 0.015 * (i % 2)
    teeth.append([((x - 0.006) * S, y_top * S), ((x + 0.006) * S, y_top * S), ((x - 0.008) * S, (y_top + ln) * S)])

head_m = np.clip(mask_of([skull, crest, mand_a, mand_b] + spines), 0, 1)
teeth_m = mask_of(teeth)
mouth_m = np.clip(mask_of([spline([(0.62, 0.55), (0.72, 0.53), (0.8, 0.6), (0.8, 0.72), (0.7, 0.74), (0.64, 0.66)])]) - mask_of([mand_a, mand_b]), 0, 1)
mouth_m *= (1 - mask_of([skull]))
# ------------------------------------------------------------------ background
bg = np.zeros((S, S, 3))
bg[..., 0] = 0.02 + 0.015 * (1 - yy)
bg[..., 1] = 0.022 + 0.012 * (1 - yy)
bg[..., 2] = 0.032 + 0.02 * (1 - yy)
lamp = np.exp(-((xx - 0.27) ** 2 + (yy - 0.2) ** 2) / 0.05) * 1.0 + np.exp(-((xx - 0.27) ** 2 + (yy - 0.2) ** 2) / 0.25) * 0.35
bg += lamp[..., None] * np.array([0.9, 0.1, 0.04])
haze = fbm(4, 3, seed=2)
bg *= (0.75 + 0.5 * haze)[..., None]

# torch beam from the lower left toward the jaw
ang = np.arctan2(yy - 1.08, xx + 0.08)
target = np.arctan2(0.66 - 1.08, 0.8 + 0.08)
beam = np.clip(1 - np.abs(ang - target) / 0.16, 0, 1) ** 1.5 * np.clip(1 - np.hypot(xx + 0.08, yy - 1.08) / 1.35, 0, 1)
dust = (rng.random((S, S)) > 0.9985).astype(float)
dust = blur(dust, 2) * 6
bg += (beam * 0.32 + beam * dust * 0.8)[..., None] * np.array([1.0, 0.95, 0.85])

# ------------------------------------------------------------------ the creature
skin = fbm(6, 10, seed=5)
plates = np.abs(fbm(3, 14, seed=6) - 0.5) < 0.025
body = np.zeros((S, S, 3)) + np.array([0.035, 0.032, 0.036])
body *= (0.6 + 0.8 * skin)[..., None]
body *= np.where(plates, 0.55, 1.0)[..., None]
# top-left red rim light from the lamp
rim_red = np.clip(head_m - shift(head_m, 9, 11), 0, 1)
rim_red = blur(rim_red, 2.5) * head_m
body += rim_red[..., None] * np.array([1.0, 0.14, 0.06]) * 1.1
# volume: soft red bounce on the lamp-facing half, falling off into black
inner = blur(head_m, 60)
facing_lamp = np.clip(1 - np.hypot(xx - 0.3, yy - 0.2) * 1.4, 0, 1)
body += ((1 - inner) * head_m * facing_lamp * 0.35)[..., None] * np.array([0.6, 0.08, 0.05])
# warm torch kiss along the underside of the jaw/neck facing the beam
rim_torch = np.clip(head_m - shift(head_m, -9, 8), 0, 1)
rim_torch = blur(rim_torch, 3) * head_m * np.clip(beam * 2.5, 0, 1)
body += rim_torch[..., None] * np.array([1.0, 0.92, 0.78]) * 1.4
# faint bioluminescent veins across the skull
veins_raw = np.abs(fbm(4, 7, seed=9) - 0.5)
veins = np.clip(1 - veins_raw / 0.006, 0, 1) * (fbm(2, 4, seed=10) > 0.6) * head_m * (yy < 0.5) * (xx > 0.4)
body += veins[..., None] * np.array([0.25, 0.75, 0.9]) * 0.35

img = bg * (1 - head_m[..., None]) + body * head_m[..., None]
# open mouth: glowing throat behind the teeth
throat = mouth_m * (0.08 + 0.6 * np.exp(-((xx - 0.69) ** 2 + (yy - 0.585) ** 2) / 0.0012))
img = img * (1 - mouth_m[..., None]) + throat[..., None] * np.array([0.25, 0.75, 0.9])
img = img * (1 - teeth_m[..., None]) + teeth_m[..., None] * np.array([0.75, 0.72, 0.62]) * (0.55 + 0.45 * yy[..., None] / yy.max())

# sensory slits along the skull + their bloom
slit_m = np.zeros((S, S))
# a row of small sensor slits (not eyes) along the skull
for cx, cy, ln in ((0.6, 0.305, 0.03), (0.665, 0.33, 0.028), (0.725, 0.36, 0.025), (0.78, 0.39, 0.021), (0.83, 0.42, 0.017)):
    a = np.radians(32)
    u = (xx - cx) * np.cos(a) + (yy - cy) * np.sin(a)
    v = -(xx - cx) * np.sin(a) + (yy - cy) * np.cos(a)
    slit_m = np.maximum(slit_m, np.clip(1 - (u / ln) ** 2 - (v / 0.0055) ** 2, 0, 1) ** 0.4)
glow = blur(slit_m, 14) * 1.2 + blur(mouth_m * throat, 30) * 0.9
img += slit_m[..., None] * np.array([0.85, 0.97, 1.0]) * 1.2
img += glow[..., None] * np.array([0.25, 0.75, 1.0])

# ------------------------------------------------------------------ finishing
vig = np.clip(1.25 - np.hypot(xx - 0.5, yy - 0.5) * 1.1, 0.2, 1)
img *= vig[..., None]
img += rng.normal(0, 0.018, (S, S, 1))
img = np.clip(img, 0, 1) ** 0.92  # slight lift for small screens

full = Image.fromarray((img * 255).astype(np.uint8), "RGB").resize((1024, 1024), Image.LANCZOS)
os.makedirs(OUT, exist_ok=True)
full.save(os.path.join(OUT, "icon_1024.png"))
for size in (512, 192, 180, 167, 152, 120, 76, 48):
    full.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"icon_{size}.png"))
full.save(os.path.join(ROOT, "icon.png"))

# Android adaptive layers: background = scene without the creature, foreground = creature
bg_img = np.clip(bg * vig[..., None], 0, 1)
Image.fromarray((bg_img * 255).astype(np.uint8), "RGB").resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "adaptive_background_432.png"))
fg_alpha = np.clip(head_m + slit_m + glow * 0.8, 0, 1)
fg_rgb = np.clip(img, 0, 1)
fg = Image.fromarray((np.dstack([fg_rgb, fg_alpha]) * 255).astype(np.uint8), "RGBA").resize((311, 311), Image.LANCZOS)
canvas = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
canvas.alpha_composite(fg, (60, 60))
canvas.save(os.path.join(OUT, "adaptive_foreground_432.png"))
print("painted app icon written to", OUT)
