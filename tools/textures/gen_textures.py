"""NIGHT SHIFT - original PBR texture generator.

Generates tileable PBR texture sets (albedo, normal, ORM = AO/roughness/metallic) for the
facility, props, characters and the Hunter. Every texture is synthesised here from
seeded noise, so all output is original work owned by the project (see
assets/ASSET_MANIFEST.md).

    python tools/textures/gen_textures.py [--size 1024] [--only name,name]

Output: assets/textures/<set>/<set>_albedo.png, _normal.png, _orm.png
"""
import argparse
import os
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")


# ---------------------------------------------------------------------- noise helpers
def _lattice(res, cells, rng):
    g = rng.random((cells, cells))
    # tileable smooth (cubic) interpolation of a periodic lattice
    x = np.linspace(0, cells, res, endpoint=False)
    i0 = np.floor(x).astype(int)
    f = x - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = g[np.ix_(i0, i0)]
    b = g[np.ix_(i0, i1)]
    c = g[np.ix_(i1, i0)]
    d = g[np.ix_(i1, i1)]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(res, base_cells, octaves, seed, gain=0.5):
    rng = np.random.default_rng(seed)
    out = np.zeros((res, res))
    amp, total = 1.0, 0.0
    cells = base_cells
    for _ in range(octaves):
        cells_c = min(cells, res)
        out += _lattice(res, cells_c, rng) * amp
        total += amp
        amp *= gain
        cells *= 2
    return out / total


def ridged(res, cells, octaves, seed):
    n = fbm(res, cells, octaves, seed)
    return 1.0 - np.abs(n * 2 - 1)


def cracks(res, seed, density=10, width=0.012):
    """Worley-style cell borders -> crack mask (1 at cracks)."""
    rng = np.random.default_rng(seed)
    pts = rng.random((density * density, 2))
    yy, xx = np.mgrid[0:res, 0:res] / res
    d1 = np.full((res, res), 9.0)
    d2 = np.full((res, res), 9.0)
    for p in pts:
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                d = np.hypot(xx - (p[0] + ox), yy - (p[1] + oy))
                closer = d < d1
                d2 = np.where(closer, d1, np.minimum(d2, d))
                d1 = np.where(closer, d, d1)
    edge = d2 - d1
    return np.clip(1 - edge / width, 0, 1)


def blur(a, r=1):
    out = a.copy()
    for _ in range(r):
        out = (out + np.roll(out, 1, 0) + np.roll(out, -1, 0) + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 5
    return out


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)  # OpenGL convention (Y+), Godot default
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def ao_from_height(h):
    b = blur(h, 6)
    return np.clip(1 - np.maximum(b - h, 0) * 4, 0.35, 1)


def grid_lines(res, n, width_px):
    """Panel seams: 1 on seams, 0 elsewhere, n panels per tile."""
    x = np.arange(res)
    step = res / n
    d = np.minimum(x % step, step - (x % step))
    line = np.clip(1 - d / width_px, 0, 1)
    return np.maximum(line[None, :], line[:, None])


def lerp(a, b, t):
    return a + (b - a) * t


def rgb(c):
    return np.array(c, dtype=float)[None, None, :]


def save_set(name, albedo, height, rough, metal, normal_strength=2.0, ao=None):
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    albedo = np.clip(albedo, 0, 1)
    Image.fromarray((albedo * 255).astype(np.uint8), "RGB").save(os.path.join(d, f"{name}_albedo.png"))
    Image.fromarray(normal_from_height(height, normal_strength), "RGB").save(os.path.join(d, f"{name}_normal.png"))
    if ao is None:
        ao = ao_from_height(height)
    rough = np.broadcast_to(np.asarray(rough, dtype=float), height.shape)
    metal = np.broadcast_to(np.asarray(metal, dtype=float), height.shape)
    orm = np.stack([ao, np.clip(rough, 0.04, 1), np.clip(metal, 0, 1)], -1)
    Image.fromarray((orm * 255).astype(np.uint8), "RGB").save(os.path.join(d, f"{name}_orm.png"))
    print("wrote", name)


# ---------------------------------------------------------------------- material sets
def concrete(r, seed=1):
    n = fbm(r, 4, 7, seed)
    pores = (fbm(r, 64, 2, seed + 1) > 0.72).astype(float) * 0.35
    stains = fbm(r, 3, 4, seed + 2)
    crk = cracks(r, seed + 3, 5, 0.0035) * (fbm(r, 4, 3, seed + 4) > 0.68) * 0.7
    h = n * 0.6 - pores * 0.3 - crk * 0.6
    base = lerp(rgb([0.30, 0.30, 0.29]), rgb([0.42, 0.41, 0.39]), n[..., None])
    base *= (1 - 0.35 * np.clip(stains - 0.5, 0, 1)[..., None] * 2)
    base *= (1 - crk[..., None] * 0.5)
    rough = 0.82 + n * 0.12 - np.clip(stains - 0.6, 0, 1) * 0.5  # damp patches are smoother
    save_set("concrete", base, h, rough, np.zeros_like(n), 3.0)


def painted_panels(r, name, color, seed, panels=2, stripe=None, chip=0.6):
    n = fbm(r, 6, 6, seed)
    seams = grid_lines(r, panels, r / 256)
    rivets = np.zeros((r, r))
    step = r // panels
    yy, xx = np.mgrid[0:r, 0:r]
    for cx in range(panels):
        for cy in range(panels):
            for ox, oy in ((0.08, 0.08), (0.92, 0.08), (0.08, 0.92), (0.92, 0.92)):
                px, py = (cx + ox) * step, (cy + oy) * step
                rivets = np.maximum(rivets, np.clip(1 - np.hypot(xx - px, yy - py) / (r / 220), 0, 1))
    chips = (fbm(r, 16, 5, seed + 7) > chip).astype(float)
    chips = np.maximum(chips, seams * (fbm(r, 32, 3, seed + 8) > 0.6))
    grime = np.clip(fbm(r, 3, 5, seed + 9) * 1.4 - 0.45, 0, 1)
    vertical = np.clip(blur(fbm(r, 48, 2, seed + 11), 1)[0:1, :].repeat(r, 0) - 0.62, 0, 1) * 2.5
    h = 0.6 - seams * 0.5 + rivets * 0.4 + n * 0.08 - chips * 0.12
    paint = rgb(color) * (0.92 + n[..., None] * 0.16)
    metal_col = rgb([0.36, 0.35, 0.34])
    base = np.where(chips[..., None] > 0.5, metal_col, paint)
    if stripe is not None:
        band = (np.abs(yy - r * 0.18) < r * 0.025).astype(float)
        base = np.where(band[..., None] > 0.5, rgb(stripe) * (0.9 + n[..., None] * 0.2), base)
    dirt = np.clip(grime + vertical * np.linspace(0.4, 1.0, r)[:, None], 0, 1)
    base = base * (1 - dirt[..., None] * 0.45) + rgb([0.09, 0.075, 0.06]) * dirt[..., None] * 0.35
    base *= (1 - seams[..., None] * 0.55)
    rough = 0.55 + n * 0.15 + dirt * 0.25 - chips * 0.15
    metal = chips * 0.8
    save_set(name, base, h, rough, metal, 2.5)


def tiles(r, name, color, grout, n_tiles, seed):
    n = fbm(r, 8, 6, seed)
    seams = grid_lines(r, n_tiles, r / 300)
    rng = np.random.default_rng(seed)
    step = r // n_tiles
    var = rng.random((n_tiles, n_tiles))
    tv = np.kron(var, np.ones((step, step)))[:r, :r]
    crk = cracks(r, seed + 5, 5, 0.004) * (fbm(r, 3, 3, seed + 6) > 0.6)
    grime = np.clip(fbm(r, 2, 5, seed + 7) * 1.5 - 0.55, 0, 1)
    h = 0.7 - seams * 0.6 + n * 0.04 - crk * 0.4
    base = rgb(color) * (0.9 + tv[..., None] * 0.12 + n[..., None] * 0.06)
    base = np.where(seams[..., None] > 0.4, rgb(grout), base)
    base = base * (1 - grime[..., None] * 0.5) * (1 - crk[..., None] * 0.6)
    rough = 0.32 + seams * 0.5 + grime * 0.35 + n * 0.08
    save_set(name, base, h, rough, np.zeros_like(n), 2.5)


def metal_grate(r, seed=21):
    yy, xx = np.mgrid[0:r, 0:r] / r
    cells = 16
    gx = np.abs(((xx * cells) % 1) - 0.5)
    gy = np.abs((((yy + xx * 0.0) * cells) % 1) - 0.5)
    bars = np.clip((np.maximum(gx, gy) - 0.36) * 12, 0, 1)
    n = fbm(r, 8, 6, seed)
    rust = np.clip(fbm(r, 4, 6, seed + 1) * 1.6 - 0.65, 0, 1)
    h = bars * 0.8 + n * 0.05
    holes = 1 - bars
    base = lerp(rgb([0.02, 0.02, 0.02]), rgb([0.38, 0.38, 0.39]), bars[..., None])
    base = lerp(base, rgb([0.32, 0.16, 0.07]), (rust * bars)[..., None])
    rough = 0.35 + rust * 0.5 + n * 0.1 + holes * 0.5
    metal = bars * (1 - rust * 0.8)
    save_set("metal_grate", base, h, rough, metal, 5.0, ao=np.clip(0.25 + bars * 0.75, 0, 1))


def brushed_steel(r, name, tint, seed, rust_amount=0.0):
    streak = blur(np.random.default_rng(seed).random((r, r)), 1)
    streak = np.repeat(streak.mean(axis=1, keepdims=True), r, 1) * 0.6 + fbm(r, 64, 2, seed)[...] * 0.4
    n = fbm(r, 6, 6, seed + 1)
    scratches = (ridged(r, 24, 3, seed + 2) > 0.93).astype(float)
    rust = np.clip(fbm(r, 3, 7, seed + 3) * (1 + rust_amount * 2) - (1.05 - rust_amount * 0.5), 0, 1)
    h = streak * 0.15 + n * 0.1 - scratches * 0.2 + rust * 0.3
    base = rgb(tint) * (0.85 + streak[..., None] * 0.3)
    base = lerp(base, rgb([0.30, 0.14, 0.06]) * (0.7 + n[..., None] * 0.6), rust[..., None])
    rough = 0.32 + streak * 0.15 + rust * 0.55 + scratches * 0.15
    metal = 1 - rust * 0.9
    save_set(name, base, h, rough, metal, 1.5)


def hazard(r, seed=31):
    yy, xx = np.mgrid[0:r, 0:r] / r
    stripes = (((xx + yy) * 4) % 1) < 0.5
    n = fbm(r, 8, 6, seed)
    wear = (fbm(r, 12, 5, seed + 1) > 0.66).astype(float)
    base = np.where(stripes[..., None], rgb([0.85, 0.62, 0.06]), rgb([0.05, 0.05, 0.05]))
    base = lerp(base, rgb([0.35, 0.34, 0.33]), wear[..., None])
    base *= (0.85 + n[..., None] * 0.3)
    save_set("hazard", base, n * 0.2 - wear * 0.1, 0.6 + n * 0.2, wear * 0.7, 2.0)


def asphalt(r, seed=41):
    n = fbm(r, 16, 7, seed)
    grit = np.random.default_rng(seed).random((r, r))
    puddle = np.clip(fbm(r, 2, 5, seed + 1) * 2 - 1.1, 0, 1)
    crk = cracks(r, seed + 2, 7, 0.005)
    h = n * 0.3 + grit * 0.25 - crk * 0.5 - puddle * 0.2
    base = rgb([0.07, 0.07, 0.075]) * (0.7 + grit[..., None] * 0.5 + n[..., None] * 0.4)
    base *= (1 - crk[..., None] * 0.5)
    rough = 0.9 - puddle * 0.82
    save_set("asphalt", base, h, rough, np.zeros_like(n), 3.0)


def ceiling(r, seed=51):
    n = fbm(r, 16, 5, seed)
    seams = grid_lines(r, 2, r / 320)
    holes = (fbm(r, 128, 1, seed + 1) > 0.78).astype(float)
    stain = np.clip(fbm(r, 2, 5, seed + 2) * 1.6 - 0.7, 0, 1)
    h = 0.6 - seams * 0.5 - holes * 0.15 + n * 0.05
    base = rgb([0.55, 0.55, 0.52]) * (0.9 + n[..., None] * 0.1)
    base = lerp(base, rgb([0.35, 0.28, 0.17]), stain[..., None] * 0.7)
    base *= (1 - seams[..., None] * 0.5)
    save_set("ceiling", base, h, 0.9 - seams * 0.2, np.zeros_like(n), 2.0)


def fabric(r, name, color, seed):
    yy, xx = np.mgrid[0:r, 0:r]
    weave = (np.sin(xx * np.pi * 2 / 6) * np.sin(yy * np.pi * 2 / 6)) * 0.5 + 0.5
    n = fbm(r, 8, 6, seed)
    dirt = np.clip(fbm(r, 3, 5, seed + 1) * 1.6 - 0.7, 0, 1)
    h = weave * 0.3 + n * 0.2
    base = rgb(color) * (0.85 + weave[..., None] * 0.1 + n[..., None] * 0.15)
    base = lerp(base, rgb([0.12, 0.1, 0.08]), dirt[..., None] * 0.5)
    save_set(name, base, h, 0.85 + n * 0.1, np.zeros_like(n), 1.5)


def plastic(r, name, color, seed, rough=0.45):
    n = fbm(r, 8, 6, seed)
    scuff = (ridged(r, 16, 3, seed + 1) > 0.94).astype(float)
    dirt = np.clip(fbm(r, 3, 5, seed + 2) * 1.6 - 0.75, 0, 1)
    base = rgb(color) * (0.95 + n[..., None] * 0.08)
    base = lerp(base, rgb([0.15, 0.13, 0.1]), dirt[..., None] * 0.6)
    save_set(name, base, n * 0.1 - scuff * 0.1, rough + n * 0.1 + dirt * 0.3 + scuff * 0.2, np.zeros_like(n), 1.0)


def rubber(r, seed=71):
    n = fbm(r, 32, 5, seed)
    save_set("rubber", rgb([0.045, 0.045, 0.045]) * (0.8 + n[..., None] * 0.4), n * 0.3, 0.92 + n * 0.05, np.zeros_like(n), 2.0)


def wood(r, seed=81):
    yy, xx = np.mgrid[0:r, 0:r] / r
    warp = fbm(r, 4, 4, seed) * 0.6
    rings = np.sin((xx * 22 + warp * 6) * np.pi) * 0.5 + 0.5
    grain = fbm(r, 64, 3, seed + 1)
    h = rings * 0.2 + grain * 0.2
    base = lerp(rgb([0.22, 0.13, 0.07]), rgb([0.42, 0.28, 0.16]), (rings * 0.6 + grain * 0.4)[..., None])
    save_set("wood", base, h, 0.6 + grain * 0.2, np.zeros_like(grain), 1.5)


def cardboard(r, seed=91):
    yy, xx = np.mgrid[0:r, 0:r]
    flutes = np.sin(xx * np.pi * 2 / 12) * 0.5 + 0.5
    n = fbm(r, 8, 5, seed)
    stain = np.clip(fbm(r, 3, 5, seed + 1) * 1.8 - 0.9, 0, 1)
    base = rgb([0.48, 0.36, 0.22]) * (0.9 + n[..., None] * 0.15)
    base = lerp(base, rgb([0.25, 0.17, 0.1]), stain[..., None])
    save_set("cardboard", base, flutes * 0.1 + n * 0.1, 0.9, np.zeros_like(n), 1.0)


def hunter_skin(r, seed=101):
    """Original creature hide: taut grey-black skin over sinew, wet chitin plates,
    raw fissures with faint bioluminescent veins (emission masked by the shader)."""
    sinew = ridged(r, 6, 6, seed)
    fibers = blur(np.random.default_rng(seed).random((r, r)), 2)
    fibers = np.repeat(fibers.mean(axis=0, keepdims=True), r, 0) * 0.5 + fibers * 0.5
    plates = cracks(r, seed + 1, 9, 0.02)
    plate_mask = 1 - np.clip(plates * 1.3, 0, 1)
    veins = np.clip((ridged(r, 12, 2, seed + 2) - 0.975) * 40, 0, 1) * (fbm(r, 4, 3, seed + 3) > 0.52)
    wet = fbm(r, 6, 5, seed + 4)
    h = sinew * 0.5 + plate_mask * 0.4 + fibers * 0.15 - veins * 0.3
    base = lerp(rgb([0.045, 0.04, 0.045]), rgb([0.16, 0.14, 0.15]), (sinew * 0.6 + fibers * 0.4)[..., None])
    base = lerp(base, rgb([0.24, 0.07, 0.06]), (plates * 0.6)[..., None])  # raw flesh in fissures
    base = lerp(base, rgb([0.45, 0.75, 0.85]), veins[..., None] * 0.5)
    rough = 0.25 + (1 - wet) * 0.35 + plates * 0.2
    save_set("hunter_skin", base, h, rough, np.zeros_like(h), 4.0)
    # emission mask for the bioluminescent veins
    glow = np.stack([veins * 0.35, veins * 0.85, veins * 1.0], -1)
    Image.fromarray((glow * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "hunter_skin", "hunter_skin_emission.png"))


def blood(r, seed=111):
    n = fbm(r, 3, 7, seed)
    splat = np.clip((n - 0.45) * 6, 0, 1)
    drops = (fbm(r, 48, 2, seed + 1) > 0.8).astype(float)
    mask = np.clip(splat + drops * (n > 0.35), 0, 1)
    d = os.path.join(OUT, "decals")
    os.makedirs(d, exist_ok=True)
    col = np.dstack([0.22 * np.ones_like(n), 0.015 * np.ones_like(n), 0.01 * np.ones_like(n), mask])
    Image.fromarray((col * 255).astype(np.uint8), "RGBA").save(os.path.join(d, "blood_albedo.png"))
    rng = np.random.default_rng(seed + 2)
    soot = np.clip(fbm(r, 3, 6, seed + 3) * 2 - 0.7, 0, 1) * np.clip(1 - np.hypot(*np.mgrid[-1:1:r * 1j, -1:1:r * 1j]), 0, 1) * 1.5
    col2 = np.dstack([0.02 * np.ones_like(n), 0.02 * np.ones_like(n), 0.02 * np.ones_like(n), np.clip(soot, 0, 1)])
    Image.fromarray((col2 * 255).astype(np.uint8), "RGBA").save(os.path.join(d, "scorch_albedo.png"))
    print("wrote decals")


def particles(r=128):
    """Soft particle sprites: smoke puff, spark streak, dust mote."""
    d = os.path.join(ROOT, "assets", "effects", "textures")
    os.makedirs(d, exist_ok=True)
    yy, xx = np.mgrid[-1:1:r * 1j, -1:1:r * 1j]
    rad = np.hypot(xx, yy)
    n = fbm(r, 4, 5, 5)
    smoke = np.clip(1 - rad, 0, 1) ** 1.5 * (0.6 + n * 0.8)
    Image.fromarray((np.dstack([np.ones_like(rad), np.ones_like(rad), np.ones_like(rad), np.clip(smoke, 0, 1)]) * 255).astype(np.uint8), "RGBA").save(os.path.join(d, "smoke.png"))
    spark = np.clip(1 - np.abs(xx) * 8, 0, 1) * np.clip(1 - np.abs(yy), 0, 1)
    Image.fromarray((np.dstack([np.ones_like(rad), np.ones_like(rad) * 0.8, np.ones_like(rad) * 0.5, spark]) * 255).astype(np.uint8), "RGBA").save(os.path.join(d, "spark.png"))
    dust = np.clip(1 - rad, 0, 1) ** 3
    Image.fromarray((np.dstack([np.ones_like(rad), np.ones_like(rad), np.ones_like(rad), dust]) * 255).astype(np.uint8), "RGBA").save(os.path.join(d, "dust.png"))
    beam = np.clip(1 - rad, 0, 1) ** 2
    Image.fromarray((np.dstack([np.ones_like(rad), np.ones_like(rad), np.ones_like(rad), beam]) * 255).astype(np.uint8), "RGBA").save(os.path.join(d, "soft_glow.png"))
    print("wrote particle sprites")


SETS = {
    "concrete": lambda r: concrete(r),
    "wall_panel": lambda r: painted_panels(r, "wall_panel", [0.33, 0.36, 0.37], 11, 2, None, 0.72),
    "wall_lab": lambda r: painted_panels(r, "wall_lab", [0.70, 0.73, 0.73], 12, 3, None, 0.72),
    "wall_medical": lambda r: painted_panels(r, "wall_medical", [0.72, 0.76, 0.75], 13, 4, None, 0.72),
    "wall_industrial": lambda r: painted_panels(r, "wall_industrial", [0.24, 0.27, 0.24], 14, 1, None, 0.68),
    "metal_painted": lambda r: painted_panels(r, "metal_painted", [0.28, 0.32, 0.31], 15, 1, None, 0.7),
    "metal_yellow": lambda r: painted_panels(r, "metal_yellow", [0.72, 0.52, 0.08], 16, 1, None, 0.68),
    "floor_tile": lambda r: tiles(r, "floor_tile", [0.42, 0.44, 0.44], [0.12, 0.12, 0.11], 4, 17),
    "floor_lab": lambda r: tiles(r, "floor_lab", [0.62, 0.65, 0.64], [0.3, 0.31, 0.3], 2, 18),
    "metal_grate": lambda r: metal_grate(r),
    "steel_dark": lambda r: brushed_steel(r, "steel_dark", [0.22, 0.23, 0.24], 19, 0.25),
    "steel_bright": lambda r: brushed_steel(r, "steel_bright", [0.62, 0.63, 0.64], 20, 0.05),
    "rust_metal": lambda r: brushed_steel(r, "rust_metal", [0.3, 0.29, 0.27], 22, 0.9),
    "hazard": lambda r: hazard(r),
    "asphalt": lambda r: asphalt(r),
    "ceiling": lambda r: ceiling(r),
    "fabric_suit": lambda r: fabric(r, "fabric_suit", [0.6, 0.62, 0.6], 61),
    "fabric_dark": lambda r: fabric(r, "fabric_dark", [0.14, 0.15, 0.17], 62),
    "plastic_white": lambda r: plastic(r, "plastic_white", [0.78, 0.8, 0.8], 63),
    "plastic_dark": lambda r: plastic(r, "plastic_dark", [0.07, 0.075, 0.08], 64, 0.5),
    "rubber": lambda r: rubber(r),
    "wood": lambda r: wood(r),
    "cardboard": lambda r: cardboard(r),
    "hunter_skin": lambda r: hunter_skin(r),
    "decals": lambda r: blood(r),
    "particles": lambda r: particles(),
}

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    for name, fn in SETS.items():
        if only and name not in only:
            continue
        fn(a.size)
