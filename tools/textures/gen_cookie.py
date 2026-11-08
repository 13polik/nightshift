"""Flashlight light-cookie: bright hotspot, soft spill ring, faint reflector rings and
lens smudges - makes the projected beam read like a real torch."""
import os
import numpy as np
from PIL import Image

r = 256
yy, xx = np.mgrid[-1:1:r * 1j, -1:1:r * 1j]
rad = np.hypot(xx, yy)
hot = np.exp(-(rad / 0.28) ** 2)
spill = np.clip(1 - rad, 0, 1) ** 1.6 * 0.45
rings = (0.5 + 0.5 * np.cos(rad * 38)) * np.exp(-(rad / 0.55) ** 2) * 0.08
rng = np.random.default_rng(3)
smudge = np.zeros_like(rad)
for _ in range(6):
    cx, cy, s = rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(0.08, 0.2)
    smudge += np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / s ** 2) * 0.06
edge = np.clip((0.98 - rad) * 20, 0, 1)
v = np.clip((hot * 0.75 + spill + rings - smudge) * edge, 0, 1)
out = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "effects", "textures", "flashlight_cookie.png")
Image.fromarray((np.dstack([v, v * 0.97, v * 0.9]) * 255).astype(np.uint8), "RGB").save(out)
print("wrote", out)
