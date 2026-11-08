"""NIGHT SHIFT item pickups + small set pieces (notes, elevator car).

    blender --background --python tools/blender/build_items.py [-- --only=a,b]

Output: assets/items/<item_id>.glb, assets/environment/note.glb, assets/environment/elevator_car.glb
Origin = bottom centre, sizes in metres (real-world scale).
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import ns_common as ns  # noqa: E402
import build_props as bp  # noqa: E402  (shared primitives; its main block is guarded)
from build_props import box, cyl, sph, ring, finish  # noqa: E402


def battery():
    cyl("Cell", 0.05, 0.15, (0, 0, 0.075), "steel_dark", seg=16)
    cyl("Wrap", 0.052, 0.09, (0, 0, 0.085), "metal_yellow", seg=16)
    cyl("Cap", 0.03, 0.012, (0, 0, 0.156), "steel_bright", seg=12)
    box("Stripe", (0.053, 0.01, 0.02), (0, -0.02, 0.12), "emissive_green", 0.0)


def medkit():
    box("Case", (0.34, 0.12, 0.24), (0, 0, 0.06), "plastic_white", 0.015)
    box("Lid", (0.345, 0.125, 0.03), (0, 0, 0.105), "plastic_white", 0.01)
    box("CrossH", (0.16, 0.01, 0.045), (0, -0.064, 0.06), "emissive_red", 0.0)
    box("CrossV", (0.045, 0.01, 0.16 * 0.6), (0, -0.064, 0.06), "emissive_red", 0.0)
    box("Handle", (0.14, 0.03, 0.02), (0, 0, 0.13), "plastic_dark", 0.006)
    for x in (-0.14, 0.14):
        box(f"Latch{x}", (0.03, 0.13, 0.03), (x, 0, 0.09), "steel_bright", 0.004)


def bandage():
    cyl("Roll", 0.09, 0.07, (0, 0, 0.045), "fabric_suit", rot=(90, 0, 0), seg=18)
    cyl("Core", 0.03, 0.072, (0, 0, 0.045), "plastic_white", rot=(90, 0, 0), seg=10)
    box("Tail", (0.06, 0.004, 0.08), (0.02, -0.03, 0.01), "fabric_suit", 0.0, rot=(0, 0, 20))


def keycard():
    box("Card", (0.09, 0.14, 0.006), (0, 0, 0.004), "plastic_white", 0.003)
    box("Strip", (0.091, 0.03, 0.007), (0, -0.04, 0.004), "emissive_cyan", 0.0)
    box("Chip", (0.02, 0.018, 0.008), (-0.02, 0.03, 0.005), "metal_yellow", 0.001)
    box("Photo", (0.03, 0.035, 0.007), (0.022, 0.03, 0.005), "plastic_dark", 0.0)
    cyl("Clip", 0.02, 0.008, (0, 0.075, 0.005), "steel_bright", seg=10)


def fuse():
    cyl("Glass", 0.035, 0.12, (0, 0, 0.035), "glass", rot=(0, 90, 0), seg=14)
    cyl("Filament", 0.006, 0.11, (0, 0, 0.035), "emissive_amber", rot=(0, 90, 0), seg=6)
    for x in (-0.07, 0.07):
        cyl(f"Cap{x}", 0.04, 0.035, (x, 0, 0.035), "steel_bright", rot=(0, 90, 0), seg=14)
    box("Label", (0.05, 0.036, 0.012), (0, 0, 0.06), "hazard", 0.0)


def circuit_board():
    box("Board", (0.22, 0.16, 0.012), (0, 0, 0.006), "emissive_green", 0.002)
    box("ChipA", (0.05, 0.05, 0.012), (0.04, 0.02, 0.018), "plastic_dark", 0.002)
    box("ChipB", (0.03, 0.02, 0.01), (-0.06, -0.04, 0.017), "plastic_dark", 0.002)
    for i in range(4):
        cyl(f"Cap{i}", 0.014, 0.025, (-0.08 + i * 0.03, 0.05, 0.025), "steel_bright", seg=8)
    box("Header", (0.12, 0.012, 0.012), (0, -0.07, 0.018), "metal_yellow", 0.0)


def capacitor():
    cyl("Body", 0.09, 0.16, (0, 0, 0.08), "steel_dark", seg=18)
    cyl("Sleeve", 0.092, 0.11, (0, 0, 0.075), "metal_painted", seg=18)
    box("Mark", (0.02, 0.093, 0.1), (0.035, 0, 0.075), "plastic_white", 0.0)
    for x in (-0.02, 0.02):
        cyl(f"Lead{x}", 0.012, 0.03, (x, 0, 0.17), "steel_bright", seg=8)


def access_decoder():
    box("Body", (0.14, 0.22, 0.05), (0, 0, 0.025), "plastic_dark", 0.012)
    box("Screen", (0.1, 0.08, 0.004), (0, 0.04, 0.051), "screen_on", 0.0)
    for i in range(6):
        box(f"Key{i}", (0.025, 0.02, 0.006), (-0.035 + (i % 3) * 0.035, -0.03 - (i // 3) * 0.03, 0.052), "rubber", 0.002)
    cyl("Cable", 0.012, 0.18, (0.0, -0.18, 0.02), "rubber", rot=(90, 0, 0), seg=6)
    box("Plug", (0.03, 0.04, 0.02), (0, -0.28, 0.02), "steel_bright", 0.003)


def sample_case():
    box("Case", (0.4, 0.24, 0.26), (0, 0, 0.13), "steel_bright", 0.02)
    box("Window", (0.2, 0.01, 0.12), (0, -0.121, 0.15), "glass", 0.0)
    cyl("Vial", 0.06, 0.18, (0, 0, 0.15), "biohazard_liquid", rot=(0, 90, 0), seg=12)
    box("Seal", (0.41, 0.03, 0.03), (0, -0.11, 0.24), "emissive_amber", 0.0)
    box("Handle", (0.16, 0.04, 0.03), (0, 0, 0.275), "rubber", 0.008)
    box("Hazard", (0.12, 0.005, 0.06), (0.12, -0.122, 0.06), "hazard", 0.0)


def crowbar():
    cyl("Bar", 0.025, 0.72, (0, 0, 0.0125), "rust_metal", rot=(0, 90, 0), seg=8)
    cyl("Hook", 0.025, 0.12, (0.4, 0.04, 0.03), "rust_metal", rot=(0, 90, 60), seg=8)
    box("Claw", (0.06, 0.03, 0.01), (-0.38, 0, 0.02), "steel_dark", 0.004, rot=(0, -20, 0))
    box("Grip", (0.18, 0.032, 0.032), (0.12, 0, 0.0125), "hazard", 0.006)


def arc_emitter():
    box("Body", (0.1, 0.3, 0.12), (0, 0, 0.06), "metal_painted", 0.015)
    box("Grip", (0.06, 0.08, 0.14), (0, 0.08, -0.02), "rubber", 0.01, rot=(15, 0, 0))
    for x in (-0.03, 0.03):
        cyl(f"Prong{x}", 0.018, 0.12, (x, -0.2, 0.07), "steel_bright", rot=(90, 0, 0), seg=8)
    box("Coil", (0.08, 0.06, 0.06), (0, -0.12, 0.07), "emissive_cyan", 0.008)
    box("Gauge", (0.05, 0.04, 0.004), (0, 0.04, 0.122), "screen_on", 0.0)


def arc_cell():
    cyl("Shell", 0.05, 0.11, (0, 0, 0.055), "steel_dark", seg=14)
    cyl("Core", 0.04, 0.07, (0, 0, 0.055), "emissive_cyan", seg=14)
    for z in (0.01, 0.1):
        ring(f"Band{z}", 0.055, (0, 0, z), "steel_bright", minor=0.06, seg=14, h=0.4)


def data_drive():
    box("Body", (0.08, 0.12, 0.022), (0, 0, 0.011), "steel_bright", 0.006)
    box("Label", (0.06, 0.06, 0.003), (0, 0.01, 0.023), "plastic_white", 0.0)
    box("Led", (0.012, 0.012, 0.004), (0.025, -0.045, 0.023), "emissive_cyan", 0.0)
    box("Port", (0.03, 0.012, 0.01), (0, -0.064, 0.011), "plastic_dark", 0.0)


def note():
    for i in range(3):
        box(f"Sheet{i}", (0.21, 0.297, 0.002), (i * 0.012, i * 0.01, 0.002 + i * 0.002), "plastic_white", 0.0, rot=(0, 0, i * 9))
    box("Ink", (0.15, 0.2, 0.0005), (0.024, 0.02, 0.0078), "plastic_dark", 0.0, rot=(0, 0, 18))
    box("Stain", (0.08, 0.06, 0.0005), (-0.04, -0.07, 0.0079), "blood", 0.0, rot=(0, 0, 30))
    cyl("Clip", 0.02, 0.008, (0.0, 0.15, 0.009), "steel_bright", seg=8)


def elevator_car():
    # authored at the real car footprint from the layout: 4 x 2 tiles = 8 x 4 m
    box("Floor", (8.0, 4.0, 0.08), (0, 0, 0.04), "metal_grate", 0.0)
    box("Kick", (8.1, 0.25, 0.14), (0, -2.0, 0.07), "hazard", 0.0)
    for x in (-3.95, 3.95):
        box(f"Rail{x}", (0.06, 4.0, 0.06), (x, 0, 1.0), "steel_bright", 0.004)
        for y in (-1.8, 0.0, 1.8):
            box(f"Post{x}{y}", (0.06, 0.06, 1.0), (x, y, 0.5), "steel_bright", 0.004)
    box("Roof", (8.0, 4.0, 0.2), (0, 0, 3.2), "steel_dark", 0.01)
    for x in (-2.5, 2.5):
        box(f"Tube{x}", (1.2, 0.25, 0.03), (x, 0, 3.08), "emissive_white", 0.0)
    for x in (-4.05, 4.05):
        box(f"Cable{x}", (0.04, 0.04, 0.5), (x, 1.9, 3.55), "rubber", 0.0)


ITEMS = ["battery", "medkit", "bandage", "keycard", "fuse", "circuit_board", "capacitor", "access_decoder",
         "sample_case", "crowbar", "arc_emitter", "arc_cell", "data_drive"]

if __name__ == "__main__":
    only = [s for s in (ns.arg("only", "") or "").split(",") if s]
    ns.reset()
    for name in ITEMS:
        if not only or name in only:
            globals()[name]()
            finish(name, "items")
    for name in ("note", "elevator_car"):
        if not only or name in only:
            globals()[name]()
            finish(name, "environment")
