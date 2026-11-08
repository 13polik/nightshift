"""NIGHT SHIFT boot splash (replaces the Godot logo while the engine starts).

Landscape 1920x1080: THE HUNTER from the app icon emerging on the right out of red
emergency light and fog, the title on the left. Every edge fades to the boot background
colour, so the image can be letterboxed on any screen ratio (phones 16:9 ... 21:9, tablets
4:3) without visible borders.

    python tools/paint_splash.py
Output: assets/ui/splash/splash.png (+ splash_portrait.png for iOS storyboard / tablets)
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "ui", "splash")
BG = np.array([5, 5, 6], dtype=float)          # == application/boot_splash/bg_color
AMBER = (234, 150, 52)
TEXT = (226, 232, 238)
rng = np.random.default_rng(7)


def font(size, bold=True):
    for name in (["bahnschrift.ttf"] if bold else []) + ["bahnschrift.ttf", "segoeuib.ttf", "arialbd.ttf"]:
        p = os.path.join("C:/Windows/Fonts", name)
        if os.path.exists(p):
            f = ImageFont.truetype(p, size)
            try:  # Bahnschrift is variable: pick a condensed bold instance
                f.set_variation_by_name("SemiBold SemiCondensed" if bold else "SemiLight SemiCondensed")
            except Exception:
                pass
            return f
    return ImageFont.load_default()


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def paint(W, H, portrait=False, cover=False):
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    img = np.ones((H, W, 3)) * BG
    # --- the creature (from the painted icon), large on the right / bottom in portrait
    icon = Image.open(os.path.join(ROOT, "icon.png")).convert("RGB")
    size = int(H * 1.02) if not portrait else int(W * 1.15)
    if cover:
        size = int(H * 0.92)
    icon = np.asarray(icon.resize((size, size), Image.LANCZOS), dtype=float)
    ox = W - size + int(size * 0.06) if not portrait else (W - size) // 2 + int(size * 0.08)
    oy = (H - size) // 2 if not portrait else H - size + int(size * 0.04)
    if cover:
        ox, oy = W - size + int(size * 0.08), -int(size * 0.02)
    # soft mask: fade to the background on every side of the art
    iy, ix = np.mgrid[0:size, 0:size].astype(float) / size
    m = smooth(0.0, 0.32, ix) * smooth(1.0, 0.86, ix) * smooth(0.0, 0.16, iy) * smooth(1.0, 0.8, iy)
    m = m[..., None]
    x0, y0 = max(ox, 0), max(oy, 0)
    x1, y1 = min(ox + size, W), min(oy + size, H)
    sub_icon = icon[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    sub_m = m[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - sub_m) + sub_icon * sub_m
    # --- atmosphere: low fog band + red bleed from the lamp toward the title
    cx, cy = (ox + size * 0.25, oy + size * 0.2)
    red = np.exp(-(((xx - cx) / (W * 0.55)) ** 2 + ((yy - cy) / (H * 0.5)) ** 2)) * 0.10
    img += red[..., None] * np.array([255, 30, 20])
    fog_img = Image.fromarray((rng.random((H // 24 + 1, W // 24 + 1)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    fog = np.asarray(fog_img.filter(ImageFilter.GaussianBlur(H * 0.03)), dtype=float) / 255.0
    band = np.exp(-(((yy - H * 0.82) / (H * 0.14)) ** 2))
    img += (fog * band * 14)[..., None] * np.array([0.8, 0.85, 1.0])
    # --- vignette to the exact background colour at the borders
    v = smooth(0.0, 0.12, xx / W) * smooth(1.0, 0.9, xx / W) * smooth(0.0, 0.12, yy / H) * smooth(1.0, 0.88, yy / H)
    img = BG + (img - BG) * v[..., None]
    # film grain
    img += rng.normal(0, 2.2, img.shape)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))

    # --- title block
    d = ImageDraw.Draw(out)
    if cover:
        tx, ty, tsize = int(W * 0.07), int(H * 0.64), int(H * 0.13)
    elif not portrait:
        tx, ty, tsize = int(W * 0.075), int(H * 0.36), int(H * 0.15)
    else:
        tx, ty, tsize = int(W * 0.09), int(H * 0.12), int(W * 0.15)
    f_title = font(tsize)
    glow = Image.new("L", out.size, 0)
    ImageDraw.Draw(glow).text((tx, ty), "NIGHT SHIFT", font=f_title, fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(tsize * 0.12))
    out = Image.composite(Image.new("RGB", out.size, (90, 20, 14)), out, glow.point(lambda p: int(p * 0.55)))
    d = ImageDraw.Draw(out)
    d.text((tx, ty), "NIGHT SHIFT", font=f_title, fill=TEXT)
    bbox = d.textbbox((tx, ty), "NIGHT SHIFT", font=f_title)
    line_y = bbox[3] + int(tsize * 0.28)
    d.rectangle([tx + 4, line_y, tx + 4 + int((bbox[2] - bbox[0]) * 0.34), line_y + max(3, tsize // 32)], fill=AMBER)
    f_sub = font(int(tsize * 0.22), bold=False)
    d.text((tx + 4, line_y + int(tsize * 0.22)), "CO-OP SURVIVAL HORROR  \u00b7  1-4 PLAYERS", font=f_sub, fill=(150, 156, 164))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    land = paint(1920, 1080)
    land.save(os.path.join(OUT, "splash.png"), optimize=True)
    port = paint(1080, 1920, portrait=True)
    port.save(os.path.join(OUT, "splash_portrait.png"), optimize=True)
    # store cover (itch.io 630x500): painted at 2x, title on top, creature below
    cover = paint(1260, 1000, cover=True).resize((630, 500), Image.LANCZOS)
    cover.save(os.path.join(OUT, "cover_630x500.png"), optimize=True)
    print("wrote", os.path.join(OUT, "splash.png"), ", splash_portrait.png and cover_630x500.png")


if __name__ == "__main__":
    main()
