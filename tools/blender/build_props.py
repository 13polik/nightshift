"""NIGHT SHIFT environment models: props, mission devices and architectural details.

    blender --background --python tools/blender/build_props.py [-- --only=a,b --preview=<dir>]

Each model is exported to assets/props/<kind>.glb (devices: assets/props/devices/,
architecture: assets/environment/). Footprints match the collision volumes defined in
scripts/environments/prop_factory.gd so gameplay is unaffected.

Orientation: front faces Blender -Y (= Godot +Z, PropFactory's "into the room").
Named nodes used by code: Screen, StatusLamp, Fan*, Tube*, Beacon.
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
import ns_common as ns  # noqa: E402

OUT = os.path.join(ns.ROOT, "assets")
parts = []


def box(name, size, loc, material="metal_painted", bevel=0.012, rot=(0, 0, 0)):
    o = ns.add_prim("cube", name, loc=loc, rot=rot, scale=size, material=material, bevel=bevel)
    parts.append(o)
    return o


def cyl(name, d, h, loc, material="steel_dark", rot=(0, 0, 0), seg=16, d2=None):
    o = ns.add_prim("cyl", name, loc=loc, rot=rot, scale=(d, d if d2 is None else d2, h), material=material, segments=seg)
    parts.append(o)
    return o


def sph(name, size, loc, material="plastic_white", seg=16, rot=(0, 0, 0)):
    o = ns.add_prim("sphere", name, loc=loc, rot=rot, scale=size, material=material, segments=seg)
    parts.append(o)
    return o


def cone(name, d, h, loc, material="steel_dark", rot=(0, 0, 0), seg=10, r2=0.0):
    o = ns.add_prim("cone", name, loc=loc, rot=rot, scale=(d, d, h), material=material, segments=seg, r2=r2)
    parts.append(o)
    return o


def ring(name, d, loc, material="steel_dark", rot=(0, 0, 0), minor=0.08, seg=20, h=1.0):
    o = ns.add_prim("torus", name, loc=loc, rot=rot, scale=(d, d, h), material=material, segments=seg, minor=minor)
    parts.append(o)
    return o


def finish(kind, folder="props"):
    """Exports every part as its own node (keeps names like Screen/StatusLamp) - parts that
    share a material are batched by Godot automatically."""
    global parts
    path = os.path.join(OUT, folder, f"{kind}.glb")
    tris = sum(ns.tri_count(p) for p in parts)
    # merge all static parts into one multi-material mesh; keep functional nodes separate
    keep = [p for p in parts if p.name.split(".")[0] in ("Screen", "StatusLamp", "Beacon") or p.name.startswith(("Fan", "Tube"))]
    static = [p for p in parts if p not in keep]
    out = list(keep)
    if static:
        out.append(ns.join(static, kind) if len(static) > 1 else static[0])
    ns.export_glb(path, out)
    print("PROP", kind, "tris", tris)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    parts = []


# ------------------------------------------------------------------------- shared bits
def handle(name, loc, w=0.12, vertical=False):
    box(name, (0.02, 0.025, w) if vertical else (w, 0.025, 0.02), loc, "steel_bright", 0.004)


def screws(prefix, pts, y):
    for i, (x, z) in enumerate(pts):
        cyl(f"{prefix}{i}", 0.018, 0.01, (x, y, z), "steel_bright", rot=(90, 0, 0), seg=8)


# ------------------------------------------------------------------------- props
def bench():
    box("Seat", (1.6, 0.45, 0.06), (0, 0, 0.45), "wood", 0.01)
    for x in (-0.68, 0.68):
        box(f"Leg{x}", (0.06, 0.4, 0.42), (x, 0, 0.21), "steel_dark")
    box("Rail", (1.5, 0.04, 0.04), (0, 0.15, 0.12), "steel_dark")


def crate_stack():
    box("CrateA", (0.9, 0.9, 0.8), (0, 0, 0.4), "cardboard", 0.02, rot=(0, 0, 7))
    box("TapeA", (0.92, 0.12, 0.81), (0, 0, 0.4), "plastic_white", 0.0, rot=(0, 0, 7))
    box("CrateB", (0.7, 0.7, 0.6), (0.05, 0, 1.1), "cardboard", 0.02, rot=(0, 0, -12))
    box("Label", (0.2, 0.01, 0.12), (0.05, -0.36, 1.12), "plastic_white", 0.0, rot=(0, 0, -12))
    box("Pallet", (1.0, 1.0, 0.12), (0, 0, 0.06), "wood", 0.005)


def wall_cabinet():
    box("Body", (0.9, 0.4, 0.8), (0, 0, 1.5), "metal_painted", 0.015)
    box("DoorL", (0.43, 0.02, 0.76), (-0.225, -0.205, 1.5), "metal_painted", 0.006)
    box("DoorR", (0.43, 0.02, 0.76), (0.225, -0.205, 1.5), "metal_painted", 0.006)
    handle("HL", (-0.03, -0.22, 1.5), 0.1, True)
    handle("HR", (0.03, -0.22, 1.5), 0.1, True)
    box("Sign", (0.3, 0.005, 0.12), (0, -0.218, 1.78), "hazard", 0.0)


def vending():
    box("Body", (1.0, 0.8, 1.9), (0, 0, 0.95), "plastic_dark", 0.03)
    box("Screen", (0.62, 0.02, 1.25), (-0.12, -0.41, 1.2), "screen_on", 0.0)
    box("Glass", (0.64, 0.01, 1.27), (-0.12, -0.42, 1.2), "glass", 0.0)
    for r in range(5):
        box(f"Shelf{r}", (0.6, 0.3, 0.015), (-0.12, -0.25, 0.7 + r * 0.22), "steel_bright", 0.0)
    box("Pad", (0.18, 0.03, 0.35), (0.36, -0.41, 1.25), "steel_dark", 0.005)
    box("Slot", (0.6, 0.04, 0.16), (-0.12, -0.41, 0.3), "steel_dark", 0.01)


def filing_cabinet():
    box("Body", (0.5, 0.6, 1.3), (0, 0, 0.65), "metal_painted", 0.012)
    for i in range(3):
        box(f"Drawer{i}", (0.46, 0.02, 0.38), (0, -0.305, 0.25 + i * 0.42), "metal_painted", 0.006)
        handle(f"H{i}", (0, -0.325, 0.38 + i * 0.42), 0.14)
        box(f"Tag{i}", (0.08, 0.005, 0.04), (0, -0.317, 0.32 + i * 0.42), "plastic_white", 0.0)


def shelves(width=1.8, depth=0.55, mat="metal_painted", boxes=True):
    for x in (-width / 2 + 0.03, width / 2 - 0.03):
        for y in (-depth / 2 + 0.03, depth / 2 - 0.03):
            box(f"Post{x}{y}", (0.04, 0.04, 2.1), (x, y, 1.05), "steel_dark", 0.004)
    for i in range(4):
        box(f"Board{i}", (width, depth, 0.03), (0, 0, 0.2 + i * 0.6), mat, 0.004)
        if boxes and i < 3:
            box(f"Box{i}", (0.5, 0.4, 0.32), (-width / 4 + (i % 2) * 0.55, 0, 0.38 + i * 0.6), "cardboard", 0.01, rot=(0, 0, i * 9))
            box(f"Box2{i}", (0.35, 0.35, 0.22), (width / 4, 0.02, 0.33 + i * 0.6), "plastic_dark", 0.01, rot=(0, 0, -i * 7))
            for b in range(4):
                box(f"Binder{i}{b}", (0.05, 0.28, 0.3), (-0.05 + b * 0.06, 0, 0.37 + i * 0.6), ["hazard", "plastic_white", "fabric_dark", "metal_yellow"][b % 4], 0.004)


def bookshelf():
    shelves(1.8, 0.55, "wood")


def shelf_unit():
    shelves(1.8, 0.55, "metal_painted")


def shelf_row():
    for i, x in enumerate((-0.9, 0.9)):
        for xx in (x - 0.87, x + 0.87):
            for y in (-0.32, 0.32):
                box(f"Post{i}{xx}{y}", (0.04, 0.04, 2.1), (xx, y, 1.05), "steel_dark", 0.004)
        for j in range(4):
            box(f"Board{i}{j}", (1.76, 0.7, 0.03), (x, 0, 0.2 + j * 0.6), "metal_painted", 0.004)
            if (i + j) % 2 == 0 and j < 3:
                box(f"Box{i}{j}", (0.6, 0.5, 0.35), (x - 0.3, 0, 0.4 + j * 0.6), "cardboard", 0.01, rot=(0, 0, j * 11))
            elif j < 3:
                cyl(f"Drum{i}{j}", 0.35, 0.4, (x + 0.4, 0, 0.42 + j * 0.6), "metal_yellow")


def plant():
    cyl("Pot", 0.44, 0.45, (0, 0, 0.22), "plastic_dark", seg=14)
    cyl("Soil", 0.4, 0.02, (0, 0, 0.44), "cardboard", seg=14)
    for i in range(7):
        a = i * 51
        cone(f"Leaf{i}", 0.06, 0.7, (0.1 * math.cos(math.radians(a)), 0.1 * math.sin(math.radians(a)), 0.75), "fabric_dark", rot=(25 * math.cos(math.radians(a)), 25 * math.sin(math.radians(a)), 0), seg=5)


def water_cooler():
    box("Body", (0.35, 0.35, 1.0), (0, 0, 0.5), "plastic_white", 0.02)
    cyl("Bottle", 0.28, 0.45, (0, 0, 1.24), "glass", seg=14)
    box("Tap", (0.06, 0.05, 0.05), (0, -0.19, 0.85), "steel_bright", 0.005)


def fume_hood():
    box("Base", (1.6, 0.8, 0.9), (0, 0, 0.45), "plastic_white", 0.015)
    box("Top", (1.6, 0.8, 0.06), (0, 0, 0.92), "plastic_dark", 0.005)
    box("Hood", (1.6, 0.75, 1.1), (0, 0.03, 1.5), "steel_bright", 0.015)
    box("Sash", (1.5, 0.02, 0.7), (0, -0.37, 1.35), "glass", 0.0, rot=(-8, 0, 0))
    box("Duct", (0.35, 0.35, 0.5), (0, 0.15, 2.3), "steel_dark", 0.01)
    for i in range(3):
        cyl(f"Flask{i}", 0.09, 0.2, (-0.4 + i * 0.4, 0.1, 1.05), "biohazard_liquid" if i == 1 else "glass", seg=10)


def glass_cabinet(med=False):
    box("Body", (0.9, 0.5, 1.9), (0, 0, 0.95), "plastic_white", 0.015)
    box("Glass", (0.82, 0.01, 0.9), (0, -0.255, 1.4), "glass", 0.0)
    box("Lower", (0.82, 0.02, 0.75), (0, -0.255, 0.45), "plastic_white", 0.006)
    for i in range(2):
        box(f"Shelf{i}", (0.8, 0.45, 0.015), (0, 0, 1.15 + i * 0.35), "steel_bright", 0.0)
        for b in range(4):
            cyl(f"Bottle{i}{b}", 0.07, 0.16, (-0.3 + b * 0.2, 0.02, 1.24 + i * 0.35), "plastic_dark" if b % 2 else "glass", seg=8)
    handle("H", (0.35, -0.27, 0.55), 0.1, True)
    if med:
        box("Cross", (0.18, 0.006, 0.05), (0, -0.262, 1.78), "emissive_red", 0.0)
        box("Cross2", (0.05, 0.006, 0.18), (0, -0.262, 1.78), "emissive_red", 0.0)


def lab_cabinet():
    glass_cabinet(False)


def med_cabinet():
    glass_cabinet(True)


def specimen_tank():
    cyl("Base", 0.95, 0.22, (0, 0, 0.11), "steel_dark", seg=20)
    cyl("Glass", 0.82, 1.56, (0, 0, 1.0), "glass", seg=20)
    cyl("Fluid", 0.76, 1.15, (0, 0, 0.8), "biohazard_liquid", seg=20)
    sph("Specimen", (0.3, 0.22, 0.5), (0, 0, 0.95), "hunter_skin", seg=12, rot=(20, 10, 0))
    cyl("Cap", 0.95, 0.22, (0, 0, 1.89), "steel_dark", seg=20)
    for i in range(4):
        a = math.radians(i * 90 + 45)
        cyl(f"Strut{i}", 0.04, 1.6, (0.43 * math.cos(a), 0.43 * math.sin(a), 1.0), "steel_bright", seg=8)
    cyl("Hose", 0.06, 0.6, (0.3, 0.2, 2.2), "rubber", rot=(30, 0, 0), seg=8)


def med_bed():
    box("Frame", (0.9, 1.9, 0.12), (0, 0, 0.6), "steel_bright", 0.01)
    box("Mattress", (0.85, 1.85, 0.13), (0, 0, 0.72), "fabric_suit", 0.04)
    box("Sheet", (0.87, 1.0, 0.02), (0, 0.35, 0.79), "plastic_white", 0.01, rot=(2, 3, 0))
    box("Pillow", (0.6, 0.35, 0.1), (0, -0.7, 0.83), "plastic_white", 0.04)
    box("Stain", (0.4, 0.5, 0.005), (0.1, 0.1, 0.8), "blood", 0.0)
    for x in (-0.4, 0.4):
        for y in (-0.85, 0.85):
            cyl(f"Leg{x}{y}", 0.04, 0.55, (x, y, 0.3), "steel_dark", seg=8)
            cyl(f"Wheel{x}{y}", 0.08, 0.04, (x, y, 0.05), "rubber", rot=(0, 90, 0), seg=10)
        box(f"Rail{x}", (0.03, 1.0, 0.25), (x * 1.06, 0.2, 0.85), "steel_bright", 0.005)
    box("Head", (0.9, 0.04, 0.5), (0, -0.95, 0.85), "steel_bright", 0.01)


def iv_stand():
    cyl("Pole", 0.03, 1.9, (0, 0, 0.95), "steel_bright", seg=8)
    for i in range(5):
        a = math.radians(i * 72)
        box(f"Foot{i}", (0.3, 0.03, 0.03), (0.15 * math.cos(a), 0.15 * math.sin(a), 0.03), "steel_bright", 0.0, rot=(0, 0, i * 72))
    box("Bag", (0.12, 0.04, 0.2), (0.1, 0, 1.68), "glass", 0.02)
    cyl("Line", 0.008, 1.0, (0.1, 0, 1.1), "rubber", seg=4)


def locker(mat="metal_painted"):
    box("Body", (0.6, 0.55, 1.95), (0, 0, 0.975), mat, 0.012)
    box("Door", (0.56, 0.02, 1.85), (0, -0.28, 0.975), mat, 0.006)
    for i in range(6):
        box(f"Vent{i}", (0.3, 0.025, 0.012), (0, -0.295, 1.6 + i * 0.03), "steel_dark", 0.0)
        box(f"VentB{i}", (0.3, 0.025, 0.012), (0, -0.295, 0.25 + i * 0.03), "steel_dark", 0.0)
    handle("H", (0.2, -0.31, 1.0), 0.14, True)
    box("Nameplate", (0.15, 0.005, 0.05), (0, -0.293, 1.45), "plastic_white", 0.0)


def tool_locker():
    locker("metal_yellow")
    box("Warning", (0.3, 0.005, 0.1), (0, -0.294, 1.2), "hazard", 0.0)


def workbench():
    box("Top", (1.8, 0.8, 0.08), (0, 0, 0.9), "wood", 0.01)
    for x in (-0.85, 0.85):
        box(f"Leg{x}", (0.06, 0.7, 0.86), (x, 0, 0.43), "steel_dark", 0.005)
    box("Shelf", (1.7, 0.7, 0.03), (0, 0, 0.2), "steel_dark", 0.004)
    box("Pegboard", (1.8, 0.04, 0.8), (0, 0.38, 1.4), "metal_painted", 0.008)
    box("Vise", (0.2, 0.15, 0.12), (-0.6, -0.25, 1.0), "metal_yellow", 0.01)
    cyl("Spool", 0.25, 0.12, (0.5, 0.1, 1.0), "rust_metal", rot=(90, 0, 0))
    for i in range(5):
        box(f"Tool{i}", (0.03, 0.02, 0.25), (-0.6 + i * 0.25, 0.35, 1.45), ["steel_bright", "metal_yellow", "rubber"][i % 3], 0.003, rot=(0, i * 8 - 16, 0))
    box("Toolbox", (0.45, 0.22, 0.2), (0.2, -0.1, 1.04), "metal_yellow", 0.01)


def barrel():
    cyl("Drum", 0.6, 0.9, (0, 0, 0.45), "metal_yellow", seg=20)
    for z in (0.05, 0.3, 0.6, 0.85):
        ring(f"Rib{z}", 0.62, (0, 0, z), "steel_dark", minor=0.03, seg=20, h=0.6)
    cyl("Lid", 0.56, 0.02, (0, 0, 0.9), "steel_dark", seg=20)
    cyl("Bung", 0.06, 0.02, (0.15, 0, 0.915), "steel_bright", seg=8)
    box("Label", (0.25, 0.005, 0.2), (0, -0.302, 0.45), "hazard", 0.0)


def rack(prefix, x):
    box(f"{prefix}Body", (0.62, 1.0, 2.1), (x, 0, 1.05), "plastic_dark", 0.012)
    box(f"{prefix}Door", (0.58, 0.02, 2.0), (x, -0.505, 1.05), "metal_grate" if False else "steel_dark", 0.004)
    for j in range(10):
        box(f"{prefix}Unit{j}", (0.52, 0.03, 0.14), (x, -0.52, 0.25 + j * 0.17), "plastic_dark", 0.003)
        box(f"{prefix}Led{j}", (0.06, 0.005, 0.015), (x - 0.18, -0.537, 0.25 + j * 0.17), "emissive_cyan" if j % 3 else "emissive_green", 0.0)
        box(f"{prefix}LedB{j}", (0.02, 0.005, 0.015), (x + 0.2, -0.537, 0.25 + j * 0.17), "emissive_amber" if j % 4 == 0 else "emissive_green", 0.0)
    box(f"{prefix}Cables", (0.5, 0.04, 1.6), (x, 0.52, 1.1), "rubber", 0.01)


def server_rack():
    rack("A", 0.0)


def server_row():
    for i, x in enumerate((-0.66, 0.0, 0.66)):
        rack("R%d" % i, x)
    box("Tray", (2.0, 0.3, 0.06), (0, 0, 2.2), "steel_dark", 0.004)


def tank():
    cyl("Shell", 1.4, 2.2, (0, 0, 1.2), "metal_painted", seg=24)
    sph("Dome", (1.4, 1.4, 0.4), (0, 0, 2.3), "metal_painted", seg=24)
    for z in (0.3, 1.2, 2.1):
        ring(f"Band{z}", 1.43, (0, 0, z), "steel_dark", minor=0.025, seg=24, h=0.5)
    cyl("Valve", 0.12, 0.3, (0, -0.75, 0.6), "steel_dark", rot=(90, 0, 0), seg=10)
    ring("Wheel", 0.3, (0, -0.92, 0.6), "metal_yellow", rot=(90, 0, 0), minor=0.06, seg=14)
    for i in range(10):
        box(f"Rung{i}", (0.35, 0.03, 0.03), (0.55, -0.55, 0.3 + i * 0.22), "steel_bright", 0.0, rot=(0, 0, 45))
    cyl("Gauge", 0.14, 0.04, (-0.4, -0.66, 1.4), "plastic_white", rot=(90, 0, 25), seg=12)
    for i in range(3):
        cyl(f"Foot{i}", 0.1, 0.12, (0.5 * math.cos(i * 2.09), 0.5 * math.sin(i * 2.09), 0.06), "steel_dark", seg=8)


def pump_unit():
    box("Skid", (1.4, 1.2, 0.2), (0, 0, 0.1), "steel_dark", 0.01)
    cyl("Motor", 0.7, 0.8, (-0.25, 0, 0.6), "metal_yellow", rot=(0, 90, 0), seg=18)
    for i in range(6):
        ring(f"Fin{i}", 0.72, (-0.55 + i * 0.12, 0, 0.6), "steel_dark", rot=(0, 90, 0), minor=0.04, seg=18, h=0.3)
    sph("Volute", (0.55, 0.45, 0.55), (0.4, 0, 0.55), "metal_painted", seg=16)
    cyl("Outlet", 0.22, 1.6, (0.45, 0, 1.4), "rust_metal", seg=12)
    ring("Flange", 0.3, (0.45, 0, 0.9), "steel_bright", minor=0.12, seg=14, h=0.4)


def monitor_desk():
    box("Top", (1.6, 0.8, 0.05), (0, 0, 0.75), "plastic_dark", 0.008)
    box("Base", (1.5, 0.7, 0.72), (0, 0.03, 0.36), "metal_painted", 0.01)
    for i, x in enumerate((-0.4, 0.4)):
        box(f"Mon{i}", (0.62, 0.05, 0.4), (x, 0.2, 1.06), "plastic_dark", 0.01, rot=(-8, 0, 0))
        box("Screen" if i == 0 else "ScreenB", (0.56, 0.01, 0.34), (x, 0.17, 1.06), "screen_on" if i == 0 else "screen_red", 0.0, rot=(-8, 0, 0))
        box(f"Stand{i}", (0.05, 0.05, 0.25), (x, 0.24, 0.88), "steel_dark", 0.004)
    box("Keyboard", (0.45, 0.16, 0.02), (0, -0.15, 0.785), "plastic_dark", 0.005)
    box("Chair", (0.5, 0.5, 0.08), (0.1, -0.65, 0.48), "fabric_dark", 0.03, rot=(0, 0, 25))
    box("ChairBack", (0.5, 0.08, 0.55), (0.18, -0.85, 0.8), "fabric_dark", 0.03, rot=(-10, 0, 25))
    cyl("ChairPost", 0.05, 0.4, (0.1, -0.65, 0.22), "steel_dark", seg=8)
    box("Papers", (0.3, 0.22, 0.01), (0.55, -0.1, 0.78), "plastic_white", 0.0, rot=(0, 0, 14))
    cyl("Mug", 0.08, 0.1, (-0.6, -0.15, 0.82), "plastic_white", seg=10)


def containment_cell():
    box("Floor", (1.9, 1.7, 0.15), (0, 0, 0.075), "steel_dark", 0.01)
    box("Roof", (1.9, 1.7, 0.2), (0, 0, 2.9), "steel_dark", 0.01)
    for x in (-0.92, 0.92):
        box(f"Side{x}", (0.06, 1.7, 2.7), (x, 0, 1.45), "steel_bright", 0.008)
    box("Back", (1.84, 0.06, 2.7), (0, 0.82, 1.45), "steel_bright", 0.008)
    box("Glass", (1.8, 0.05, 2.7), (0, -0.82, 1.45), "glass", 0.0)
    box("Crack", (0.5, 0.06, 0.9), (0.35, -0.83, 1.1), "blood", 0.0, rot=(0, 18, 0))
    box("Strip", (1.8, 0.05, 0.05), (0, -0.82, 2.75), "emissive_cyan", 0.0)
    for z in (0.6, 1.4):
        box(f"Restraint{z}", (0.5, 0.08, 0.1), (0, 0.76, z), "rubber", 0.01)
    for i in range(6):
        cyl(f"Bolt{i}", 0.04, 0.03, (-0.8 + (i % 3) * 0.8, -0.85, 0.3 if i < 3 else 2.65), "steel_bright", rot=(90, 0, 0), seg=8)
    box("Gouges", (0.3, 0.01, 1.0), (-0.4, 0.78, 1.5), "scorch", 0.0)


def lab_bench():
    box("Top", (3.6, 1.2, 0.06), (0, 0, 0.92), "plastic_white", 0.008)
    box("Base", (3.5, 1.1, 0.86), (0, 0, 0.44), "metal_painted", 0.01)
    for i in range(4):
        box(f"Door{i}", (0.8, 0.02, 0.7), (-1.3 + i * 0.86, -0.56, 0.45), "metal_painted", 0.005)
        handle(f"H{i}", (-1.3 + i * 0.86, -0.58, 0.72), 0.14)
    box("ReagentShelf", (3.2, 0.25, 0.03), (0, 0.15, 1.45), "steel_bright", 0.004)
    for x in (-1.5, 0, 1.5):
        cyl(f"ShelfPost{x}", 0.03, 0.5, (x, 0.15, 1.2), "steel_bright", seg=6)
    for i in range(9):
        cyl(f"Reagent{i}", 0.07, 0.16, (-1.4 + i * 0.35, 0.15, 1.55), "glass" if i % 3 else "biohazard_liquid", seg=8)
    box("Microscope", (0.18, 0.25, 0.08), (-1.1, 0.1, 0.99), "plastic_white", 0.01)
    cyl("Scope", 0.06, 0.32, (-1.1, 0.05, 1.18), "plastic_dark", rot=(20, 0, 0), seg=8)
    box("Analyzer", (0.5, 0.4, 0.35), (1.1, 0.15, 1.13), "plastic_white", 0.02)
    box("Screen", (0.3, 0.01, 0.15), (1.1, -0.055, 1.2), "screen_on", 0.0)
    for i in range(4):
        cyl(f"Beaker{i}", 0.08, 0.13, (0.1 + i * 0.15, -0.3, 1.01), "glass", seg=8)
    box("Spill", (0.6, 0.4, 0.004), (0.3, -0.25, 0.952), "blood", 0.0)


def desk_pair():
    box("Top", (1.6, 0.8, 0.05), (0, 0, 0.74), "wood", 0.006)
    box("Pedestal", (0.45, 0.7, 0.7), (0.55, 0, 0.36), "metal_painted", 0.008)
    for i in range(3):
        box(f"Drawer{i}", (0.42, 0.02, 0.2), (0.55, -0.36, 0.15 + i * 0.22), "metal_painted", 0.004)
        handle(f"H{i}", (0.55, -0.375, 0.2 + i * 0.22), 0.1)
    box("Panel", (0.04, 0.7, 0.7), (-0.76, 0, 0.36), "metal_painted", 0.005)
    box("Monitor", (0.55, 0.05, 0.36), (-0.1, 0.22, 1.0), "plastic_dark", 0.01)
    box("ScreenOff", (0.5, 0.01, 0.3), (-0.1, 0.19, 1.0), "screen_off", 0.0)
    box("Keyboard", (0.42, 0.15, 0.02), (-0.1, -0.12, 0.775), "plastic_dark", 0.004)
    box("Chair", (0.5, 0.5, 0.08), (-0.2, -0.75, 0.46), "fabric_dark", 0.03, rot=(0, 0, 20))
    box("ChairBack", (0.5, 0.08, 0.5), (-0.13, -0.95, 0.77), "fabric_dark", 0.03, rot=(-12, 0, 20))
    for i in range(3):
        box(f"Paper{i}", (0.21, 0.29, 0.003), (0.3 + i * 0.05, -0.05, 0.77 + i * 0.004), "plastic_white", 0.0, rot=(0, 0, i * 17))


def pillar():
    box("Column", (0.7, 0.7, 4.0), (0, 0, 2.0), "concrete", 0.03)
    box("Band", (0.72, 0.72, 0.2), (0, 0, 0.3), "hazard", 0.005)
    for z in (1.0, 2.5):
        box(f"Bracket{z}", (0.74, 0.74, 0.06), (0, 0, z), "steel_dark", 0.004)
    cyl("Conduit", 0.08, 4.0, (0.37, 0.2, 2.0), "steel_bright", seg=8)


def console_island():
    box("Body", (3.4, 1.0, 0.9), (0, 0, 0.45), "metal_painted", 0.015)
    box("Desk", (3.4, 0.7, 0.06), (0, -0.2, 0.95), "plastic_dark", 0.006, rot=(-12, 0, 0))
    for i in range(3):
        box(f"Mon{i}", (0.9, 0.06, 0.5), (-1.1 + i * 1.1, 0.25, 1.35), "plastic_dark", 0.01, rot=(-15, 0, 0))
        box("Screen" if i == 1 else f"Scr{i}", (0.82, 0.01, 0.42), (-1.1 + i * 1.1, 0.215, 1.35), "screen_on", 0.0, rot=(-15, 0, 0))
    for i in range(12):
        box(f"Btn{i}", (0.05, 0.04, 0.02), (-1.4 + i * 0.25, -0.35, 0.98), ["emissive_green", "emissive_amber", "emissive_red"][i % 3], 0.003, rot=(-12, 0, 0))


def barrier():
    box("Base", (2.0, 0.6, 0.25), (0, 0, 0.125), "concrete", 0.02)
    box("Wall", (2.0, 0.3, 0.7), (0, 0, 0.6), "concrete", 0.03)
    box("Stripe", (2.02, 0.32, 0.12), (0, 0, 0.75), "hazard", 0.005)


def lamp_post():
    cyl("Pole", 0.16, 5.0, (0, 0, 2.5), "steel_dark", seg=10)
    cyl("Base", 0.35, 0.3, (0, 0, 0.15), "concrete", seg=10)
    box("Arm", (0.08, 0.9, 0.08), (0.3, -0.3, 4.95), "steel_dark", 0.005, rot=(0, 0, 45))
    box("Head", (0.5, 0.3, 0.12), (0.6, -0.6, 4.9), "steel_dark", 0.02, rot=(0, 0, 45))
    box("Tube", (0.4, 0.22, 0.03), (0.6, -0.6, 4.83), "emissive_amber", 0.0, rot=(0, 0, 45))


def evac_beacon():
    cyl("Base", 1.0, 0.3, (0, 0, 0.15), "steel_dark", seg=16)
    cyl("Pole", 0.24, 2.2, (0, 0, 1.3), "metal_yellow", seg=12)
    sph("Beacon", (0.44, 0.44, 0.44), (0, 0, 2.55), "emissive_off", seg=14)
    ring("Cage", 0.5, (0, 0, 2.55), "steel_dark", minor=0.06, seg=14, h=1.0)
    box("Panel", (0.3, 0.1, 0.4), (0, -0.15, 1.0), "plastic_dark", 0.01)


def vehicle():
    box("Chassis", (2.2, 4.6, 0.5), (0, 0, 0.7), "steel_dark", 0.05)
    box("Body", (2.2, 3.2, 1.4), (0, 0.6, 1.6), "metal_painted", 0.06)
    box("Cab", (2.1, 1.4, 1.1), (0, -1.6, 1.45), "metal_painted", 0.08)
    box("Windshield", (1.9, 0.05, 0.6), (0, -2.28, 1.65), "glass", 0.0, rot=(-15, 0, 0))
    box("Bumper", (2.3, 0.2, 0.3), (0, -2.35, 0.7), "steel_dark", 0.03)
    for x in (-0.75, 0.75):
        box(f"Head{x}", (0.35, 0.03, 0.15), (x, -2.32, 1.05), "emissive_amber", 0.0)
    for x in (-1.05, 1.05):
        for y in (-1.5, 1.5):
            cyl(f"Wheel{x}{y}", 0.88, 0.32, (x, y, 0.44), "rubber", rot=(0, 90, 0), seg=18)
            cyl(f"Hub{x}{y}", 0.4, 0.34, (x, y, 0.44), "steel_bright", rot=(0, 90, 0), seg=10)
    box("Stripe", (2.22, 3.0, 0.15), (0, 0.6, 1.4), "hazard", 0.0)
    box("LightBar", (1.4, 0.3, 0.12), (0, -1.6, 2.06), "emissive_red", 0.02)


def reception_desk():
    box("Front", (4.0, 0.15, 1.1), (0, -0.35, 0.55), "wood", 0.02)
    box("Top", (4.1, 0.95, 0.06), (0, 0, 1.12), "steel_bright", 0.01)
    box("Back", (4.0, 0.6, 0.75), (0, 0.1, 0.38), "metal_painted", 0.01)
    box("Logo", (1.2, 0.01, 0.25), (0, -0.43, 0.65), "metal_yellow", 0.0)
    box("Monitor", (0.5, 0.05, 0.32), (1.0, 0.15, 1.33), "plastic_dark", 0.01)
    box("ScreenOff", (0.45, 0.01, 0.28), (1.0, 0.12, 1.33), "screen_off", 0.0)


def scanner_gate():
    for x in (-0.9, 0.9):
        box(f"Side{x}", (0.2, 0.6, 2.2), (x, 0, 1.1), "plastic_dark", 0.03)
        box(f"Strip{x}", (0.03, 0.4, 1.8), (x * 0.88, 0, 1.1), "emissive_red", 0.0)
    box("Top", (2.0, 0.6, 0.2), (0, 0, 2.3), "plastic_dark", 0.03)
    box("Sensor", (1.6, 0.06, 0.04), (0, -0.3, 2.18), "emissive_red", 0.0)


def debris():
    for i in range(6):
        a = i * 1.3
        box(f"Chunk{i}", (0.15 + (i % 3) * 0.1, 0.12 + (i % 2) * 0.1, 0.08 + (i % 3) * 0.05), (0.3 * math.cos(a), 0.3 * math.sin(a), 0.05),
            "concrete" if i % 2 else "rust_metal", 0.02, rot=(i * 13, i * 7, i * 31))
    box("Panel", (0.6, 0.4, 0.02), (0, 0, 0.03), "ceiling", 0.0, rot=(4, 6, 20))


def pipe_cluster():
    for i in range(3):
        cyl(f"Pipe{i}", 0.16 + i * 0.04, 2.0, (-0.1 + i * 0.13, 0, 3.2 - i * 0.2), "steel_dark" if i % 2 == 0 else "rust_metal", rot=(0, 90, 0), seg=12)
    cyl("Riser", 0.14, 3.4, (0.6, 0.05, 1.7), "metal_painted", seg=12)
    for z in (0.8, 1.9, 2.9):
        ring(f"Clamp{z}", 0.17, (0.6, 0.05, z), "steel_bright", minor=0.15, seg=12, h=0.5)
    cyl("Valve", 0.1, 0.2, (0.6, -0.12, 1.4), "steel_dark", rot=(90, 0, 0), seg=8)
    ring("Wheel", 0.22, (0.6, -0.24, 1.4), "emissive_off" if False else "metal_yellow", rot=(90, 0, 0), minor=0.08, seg=12)
    box("Tag", (0.12, 0.005, 0.06), (0.6, -0.08, 1.7), "hazard", 0.0)


# ------------------------------------------------------------------------- devices
def d_terminal():
    box("Body", (0.9, 0.5, 1.0), (0, 0.05, 0.5), "metal_painted", 0.015)
    box("Desk", (0.95, 0.6, 0.06), (0, 0, 1.02), "steel_dark", 0.008)
    box("Housing", (0.78, 0.12, 0.55), (0, 0.18, 1.36), "plastic_dark", 0.02, rot=(12, 0, 0))
    box("Screen", (0.7, 0.01, 0.45), (0, 0.115, 1.36), "screen_off", 0.0, rot=(12, 0, 0))
    box("Keyboard", (0.6, 0.22, 0.03), (0, -0.12, 1.06), "plastic_dark", 0.005, rot=(-8, 0, 0))
    box("StatusLamp", (0.06, 0.02, 0.06), (0.38, -0.21, 0.9), "emissive_red", 0.0)
    box("Vent", (0.6, 0.01, 0.2), (0, -0.205, 0.3), "steel_dark", 0.0)


def d_electrical_panel():
    box("Cabinet", (1.1, 0.3, 1.6), (0, 0.1, 1.2), "metal_painted", 0.015)
    box("DoorOpen", (1.0, 0.04, 1.5), (-0.62, -0.35, 1.2), "metal_painted", 0.008, rot=(0, 0, -70))
    box("Hazard", (0.9, 0.01, 0.08), (0, -0.055, 1.9), "hazard", 0.0)
    for i in range(4):
        box(f"Breaker{i}", (0.12, 0.06, 0.2), (-0.3 + i * 0.2, -0.06, 1.3), "plastic_dark", 0.008)
    for i in range(3):
        box(f"BurntWire{i}", (0.02, 0.02, 0.5), (-0.2 + i * 0.2, -0.04, 0.85), "rubber", 0.0, rot=(0, (i - 1) * 15, 0))
    box("Scorch", (0.5, 0.005, 0.5), (0, -0.052, 0.95), "scorch", 0.0)
    box("StatusLamp", (0.08, 0.03, 0.08), (0.4, -0.06, 1.75), "emissive_red", 0.0)
    cyl("Conduit", 0.08, 1.2, (0.4, 0.1, 2.6), "steel_bright", seg=8)


def d_generator():
    box("Skid", (3.6, 2.0, 0.2), (0, 0, 0.1), "steel_dark", 0.02)
    box("Block", (2.4, 1.6, 1.4), (-0.4, 0, 0.9), "metal_yellow", 0.04)
    box("Radiator", (0.8, 1.7, 1.5), (1.25, 0, 0.95), "steel_dark", 0.03)
    for i in range(10):
        box(f"Grille{i}", (0.02, 1.5, 1.3), (1.66, 0, 0.95), "steel_bright", 0.0)
    for i in range(3):
        cyl(f"Fan{i}", 0.6, 0.06, (-1.2 + i * 0.8, 0, 1.64), "steel_dark", seg=12)
    cyl("Exhaust", 0.25, 1.8, (-1.3, 0.5, 2.3), "rust_metal", seg=12)
    ring("ExhaustCap", 0.3, (-1.3, 0.5, 3.2), "steel_dark", minor=0.15, seg=12, h=0.4)
    box("ControlBox", (0.7, 0.2, 0.5), (0.6, -0.9, 1.1), "metal_painted", 0.015)
    box("Screen", (0.5, 0.01, 0.28), (0.6, -1.005, 1.15), "screen_off", 0.0)
    box("StatusLamp", (0.08, 0.02, 0.08), (0.95, -1.005, 1.25), "emissive_red", 0.0)
    for i in range(4):
        cyl(f"Cyl{i}", 0.22, 0.35, (-1.2 + i * 0.4, 0, 1.7), "steel_bright", seg=10)
    box("Warning", (0.5, 0.005, 0.3), (-0.4, -0.805, 1.0), "hazard", 0.0)


def d_breaker():
    box("Box", (0.8, 0.25, 1.2), (0, 0.08, 1.3), "steel_dark", 0.015)
    box("Plate", (0.6, 0.01, 0.9), (0, -0.05, 1.3), "metal_painted", 0.0)
    box("LeverBase", (0.2, 0.08, 0.3), (0, -0.08, 1.3), "plastic_dark", 0.01)
    box("Lever", (0.06, 0.25, 0.06), (0, -0.2, 1.38), "hazard", 0.01, rot=(-30, 0, 0))
    box("StatusLamp", (0.08, 0.02, 0.08), (0.28, -0.06, 1.75), "emissive_red", 0.0)


def d_containment_console():
    cyl("Pedestal", 2.2, 0.25, (0, 1.6, 0.12), "steel_dark", seg=24)
    cyl("Tube", 1.8, 2.6, (0, 1.6, 1.55), "glass", seg=24)
    cyl("Fluid", 1.5, 1.6, (0, 1.6, 1.1), "biohazard_liquid", seg=24)
    sph("Sample", (0.35, 0.3, 0.6), (0, 1.6, 1.2), "hunter_skin", seg=14, rot=(10, 30, 0))
    cyl("Cap", 2.2, 0.3, (0, 1.6, 2.95), "steel_dark", seg=24)
    for i in range(6):
        a = math.radians(i * 60)
        cyl(f"Rib{i}", 0.06, 2.6, (1.0 * math.cos(a), 1.6 + 1.0 * math.sin(a), 1.55), "steel_bright", seg=8)
    box("Console", (1.2, 0.6, 1.0), (0, 0, 0.5), "metal_painted", 0.02)
    box("Screen", (0.9, 0.01, 0.4), (0, -0.2, 1.2), "screen_off", 0.0, rot=(25, 0, 0))
    box("ScreenHousing", (1.0, 0.1, 0.48), (0, -0.15, 1.2), "plastic_dark", 0.01, rot=(25, 0, 0))
    box("StatusLamp", (0.08, 0.02, 0.08), (0.5, -0.31, 0.85), "emissive_red", 0.0)
    for i in range(3):
        cyl(f"Hose{i}", 0.08, 1.6, (-0.3 + i * 0.3, 0.8, 0.3), "rubber", rot=(80, 0, 0), seg=8)


def d_evac_console():
    box("Body", (1.2, 0.6, 1.1), (0, 0, 0.55), "metal_painted", 0.02)
    box("Hazard", (0.5, 0.3, 0.06), (0, -0.05, 1.12), "hazard", 0.006)
    cyl("Button", 0.18, 0.08, (0, -0.05, 1.18), "emissive_red", seg=14)
    box("Cover", (0.3, 0.3, 0.01), (0, 0.05, 1.3), "glass", 0.0, rot=(60, 0, 0))
    box("Housing", (1.0, 0.1, 0.6), (0, 0.25, 1.55), "plastic_dark", 0.015, rot=(-10, 0, 0))
    box("Screen", (0.9, 0.01, 0.5), (0, 0.195, 1.55), "screen_off", 0.0, rot=(-10, 0, 0))
    box("StatusLamp", (0.08, 0.02, 0.08), (0.5, -0.31, 0.9), "emissive_red", 0.0)


def d_alarm_panel():
    box("Body", (0.6, 0.15, 0.8), (0, 0.05, 1.4), "metal_painted", 0.015)
    cyl("StatusLamp", 0.2, 0.1, (0, -0.05, 1.62), "emissive_off", rot=(90, 0, 0), seg=14)
    ring("Cage", 0.24, (0, -0.07, 1.62), "steel_dark", rot=(90, 0, 0), minor=0.08, seg=14)
    box("Key", (0.12, 0.04, 0.12), (0, -0.04, 1.3), "steel_bright", 0.01)
    box("Label", (0.4, 0.005, 0.08), (0, -0.026, 1.15), "hazard", 0.0)


def d_elevator_panel():
    box("Plate", (0.35, 0.08, 0.6), (0, 0.02, 1.3), "steel_bright", 0.01)
    box("StatusLamp", (0.12, 0.02, 0.12), (0, -0.03, 1.45), "emissive_red", 0.0)
    cyl("Call", 0.1, 0.03, (0, -0.03, 1.22), "plastic_dark", rot=(90, 0, 0), seg=12)
    box("Reader", (0.1, 0.03, 0.14), (0, -0.03, 1.05), "plastic_dark", 0.005)


# ------------------------------------------------------------------------- architecture
def a_door_frame():
    for x in (-0.91, 0.91):
        box(f"Post{x}", (0.18, 0.4, 2.7), (x, 0, 1.35), "steel_dark", 0.02)
        for i in range(5):
            box(f"Hz{x}{i}", (0.185, 0.41, 0.1), (x, 0, 0.2 + i * 0.5), "hazard", 0.0)
    box("Header", (2.0, 0.4, 0.25), (0, 0, 2.82), "steel_dark", 0.02)
    box("Track", (2.0, 0.08, 0.06), (0, 0, 2.66), "steel_bright", 0.005)
    box("Sill", (1.8, 0.4, 0.03), (0, 0, 0.015), "metal_grate", 0.0)
    box("LampHousing", (0.32, 0.44, 0.1), (0, 0, 2.82), "plastic_dark", 0.01)


def a_door_panel():
    box("Panel", (0.82, 0.12, 2.6), (0, 0, 1.3), "metal_painted", 0.015)
    box("Window", (0.3, 0.13, 0.5), (0, 0, 1.75), "glass", 0.0)
    box("WindowFrame", (0.36, 0.125, 0.56), (0, 0, 1.75), "steel_dark", 0.005)
    box("Kick", (0.8, 0.125, 0.3), (0, 0, 0.2), "steel_dark", 0.005)
    box("Stripe", (0.8, 0.126, 0.08), (0, 0, 1.1), "hazard", 0.0)
    for z in (0.6, 2.2):
        box(f"Rib{z}", (0.78, 0.13, 0.04), (0, 0, z), "steel_dark", 0.004)


def a_light_fixture():
    box("Housing", (1.4, 0.35, 0.08), (0, 0, -0.04), "steel_bright", 0.01)
    box("Tube", (1.3, 0.25, 0.02), (0, 0, -0.09), "emissive_white", 0.0)
    for x in (-0.5, 0, 0.5):
        box(f"Louver{x}", (0.02, 0.33, 0.04), (x, 0, -0.1), "steel_bright", 0.0)


def a_emergency_light():
    box("Base", (0.3, 0.15, 0.08), (0, 0.05, 0), "plastic_dark", 0.01)
    cyl("Tube", 0.2, 0.16, (0, -0.02, 0), "emissive_red", rot=(0, 90, 0), seg=12)
    ring("Cage", 0.24, (0, -0.02, 0), "steel_dark", rot=(0, 90, 0), minor=0.06, seg=12, h=1.0)


def a_wall_vent():
    box("Frame", (0.7, 0.05, 0.45), (0, 0, 0), "steel_dark", 0.008)
    for i in range(7):
        box(f"Slat{i}", (0.62, 0.04, 0.03), (0, -0.01, -0.18 + i * 0.06), "steel_bright", 0.0, rot=(30, 0, 0))


def a_pipe_run():
    cyl("PipeA", 0.18, 2.0, (0, 0, 0.12), "steel_dark", rot=(0, 90, 0), seg=12)
    cyl("PipeB", 0.12, 2.0, (0, 0.22, 0.08), "rust_metal", rot=(0, 90, 0), seg=10)
    cyl("Conduit", 0.06, 2.0, (0, -0.18, 0.05), "steel_bright", rot=(0, 90, 0), seg=8)
    for x in (-0.6, 0.6):
        box(f"Hanger{x}", (0.04, 0.6, 0.04), (x, 0.02, 0.22), "steel_dark", 0.004)
        cyl(f"Rod{x}", 0.015, 0.25, (x, 0.02, 0.36), "steel_bright", seg=6)


def a_cable_tray():
    box("Tray", (2.0, 0.4, 0.02), (0, 0, 0), "metal_grate", 0.0)
    for y in (-0.2, 0.2):
        box(f"Lip{y}", (2.0, 0.02, 0.08), (0, y, 0.04), "steel_dark", 0.0)
    for i in range(5):
        cyl(f"Cable{i}", 0.035, 2.0, (0, -0.14 + i * 0.07, 0.03), ["rubber", "metal_yellow", "rubber", "fabric_dark", "rubber"][i], rot=(0, 90, 0), seg=6)


PROP_NAMES = ["bench", "crate_stack", "wall_cabinet", "vending", "filing_cabinet", "bookshelf", "shelf_unit", "shelf_row",
              "plant", "water_cooler", "fume_hood", "lab_cabinet", "med_cabinet", "specimen_tank", "med_bed", "iv_stand",
              "locker", "tool_locker", "workbench", "barrel", "server_rack", "server_row", "tank", "pump_unit", "monitor_desk",
              "containment_cell", "lab_bench", "desk_pair", "pillar", "console_island", "barrier", "lamp_post", "evac_beacon",
              "vehicle", "reception_desk", "scanner_gate", "debris", "pipe_cluster"]
PROPS = {k: globals()[k] for k in PROP_NAMES}
DEVICES = {k[2:]: v for k, v in list(globals().items()) if k.startswith("d_")}
ARCH = {k[2:]: v for k, v in list(globals().items()) if k.startswith("a_")}

if __name__ == "__main__":
    only = [s for s in (ns.arg("only", "") or "").split(",") if s]
    ns.reset()
    for table, folder in ((PROPS, "props"), (DEVICES, "props/devices"), (ARCH, "environment")):
        for kind, fn in table.items():
            if only and kind not in only:
                continue
            fn()
            finish(kind, folder)
