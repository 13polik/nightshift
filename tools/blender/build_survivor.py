"""NIGHT SHIFT survivor ("operative") - original character model, rig and animations.

    blender --background --python tools/blender/build_survivor.py [-- --preview=<png>]

Output: assets/characters/survivor/survivor.glb
Bones: hips spine chest neck head, shoulder/upperarm/forearm/hand _L/_R, thigh/shin/foot _L/_R
Animations: idle walk run crouch_idle crouch_walk interact revive use_item hit
            downed_idle crawl death dead
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import ns_common as ns  # noqa: E402

ns.reset()

# ---------------------------------------------------------------- joints (character faces +Y)
J = {
    "pelvis": (0, 0.0, 0.97), "spine": (0, 0.01, 1.14), "chest": (0, 0.0, 1.35), "neck": (0, 0.0, 1.54),
    "head": (0, 0.03, 1.66),
    "sh_R": (0.18, -0.01, 1.47), "el_R": (0.26, -0.02, 1.2), "wr_R": (0.3, 0.03, 0.96), "hd_R": (0.31, 0.05, 0.86),
    "sh_L": (-0.18, -0.01, 1.47), "el_L": (-0.26, -0.02, 1.2), "wr_L": (-0.3, 0.03, 0.96), "hd_L": (-0.31, 0.05, 0.86),
    "hip_R": (0.1, 0.0, 0.93), "kn_R": (0.11, 0.03, 0.51), "an_R": (0.11, -0.01, 0.09), "to_R": (0.11, 0.15, 0.03),
    "hip_L": (-0.1, 0.0, 0.93), "kn_L": (-0.11, 0.03, 0.51), "an_L": (-0.11, -0.01, 0.09), "to_L": (-0.11, 0.15, 0.03),
}
names = list(J.keys())
idx = {n: i for i, n in enumerate(names)}
edges = [("pelvis", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head")]
for s in ("R", "L"):
    edges += [("chest", f"sh_{s}"), (f"sh_{s}", f"el_{s}"), (f"el_{s}", f"wr_{s}"), (f"wr_{s}", f"hd_{s}"),
              ("pelvis", f"hip_{s}"), (f"hip_{s}", f"kn_{s}"), (f"kn_{s}", f"an_{s}"), (f"an_{s}", f"to_{s}")]
R = {"pelvis": (0.18, 0.13), "spine": (0.16, 0.115), "chest": (0.195, 0.13), "neck": (0.065, 0.065), "head": (0.08, 0.085)}
for s_ in ("R", "L"):
    R.update({f"sh_{s_}": (0.085, 0.085), f"el_{s_}": (0.068, 0.068), f"wr_{s_}": (0.052, 0.045), f"hd_{s_}": (0.055, 0.03),
              f"hip_{s_}": (0.125, 0.125), f"kn_{s_}": (0.086, 0.088), f"an_{s_}": (0.062, 0.066), f"to_{s_}": (0.055, 0.04)})

body = ns.skin_body("Body", [Vector(J[n]) for n in names], [(idx[a], idx[b]) for a, b in edges],
                    [R[n] for n in names], root=idx["pelvis"], subdiv=2, material="fabric_suit")
ns.cube_uv(body, 0.5)

# ---------------------------------------------------------------- armature
def mid(a, b):
    return tuple((Vector(J[a]) + Vector(J[b])) * 0.5)


bones = [
    ("hips", J["pelvis"], J["spine"], None, 0),
    ("spine", J["spine"], J["chest"], "hips", 0),
    ("chest", J["chest"], J["neck"], "spine", 0),
    ("neck", J["neck"], J["head"], "chest", 0),
    ("head", J["head"], (0, 0.03, 1.9), "neck", 0),
]
for s in ("R", "L"):
    sx = 1 if s == "R" else -1
    bones += [
        (f"shoulder_{s}", (0.05 * sx, 0.0, 1.47), J[f"sh_{s}"], "chest", 0),
        (f"upperarm_{s}", J[f"sh_{s}"], J[f"el_{s}"], f"shoulder_{s}", 0),
        (f"forearm_{s}", J[f"el_{s}"], J[f"wr_{s}"], f"upperarm_{s}", 0),
        (f"hand_{s}", J[f"wr_{s}"], J[f"hd_{s}"], f"forearm_{s}", 0),
        (f"thigh_{s}", J[f"hip_{s}"], J[f"kn_{s}"], "hips", 0),
        (f"shin_{s}", J[f"kn_{s}"], J[f"an_{s}"], f"thigh_{s}", 0),
        (f"foot_{s}", J[f"an_{s}"], J[f"to_{s}"], f"shin_{s}", 0),
    ]
arm = ns.armature("SurvivorRig", bones)
ns.bind(body, arm)

# ---------------------------------------------------------------- equipment (rigid parts)
parts = []


def part(bone, *a, **k):
    o = ns.add_prim(*a, **k)
    ns.rigid_to_bone(o, bone)
    parts.append(o)
    return o


# helmet: hard shell, visor, lamp, collar
# helmet: hard shell, flush curved faceplate in a rubber seal, ear modules, chin guard
part("head", "sphere", "Helmet", loc=(0, -0.015, 1.74), scale=(0.3, 0.32, 0.31), material="metal_painted", segments=28)
part("head", "cube", "HelmetRidge", loc=(0, -0.03, 1.875), scale=(0.06, 0.26, 0.05), material="metal_painted", bevel=0.02)
part("head", "sphere", "Visor", loc=(0, 0.045, 1.725), scale=(0.25, 0.25, 0.17), material="visor", segments=28)
part("head", "torus", "VisorSeal", loc=(0, 0.1, 1.725), rot=(90, 0, 0), scale=(0.25, 0.17, 0.25), material="rubber", segments=24, minor=0.12)
part("head", "cube", "ChinGuard", loc=(0, 0.1, 1.615), scale=(0.17, 0.08, 0.06), material="plastic_dark", bevel=0.025)
for sx in (1, -1):
    part("head", "cyl", f"EarModule{sx}", loc=(0.148 * sx, 0.0, 1.72), rot=(0, 90, 0), scale=(0.1, 0.1, 0.04), material="plastic_dark", segments=16)
    part("head", "cyl", f"EarCap{sx}", loc=(0.17 * sx, 0.0, 1.72), rot=(0, 90, 0), scale=(0.06, 0.06, 0.012), material="steel_bright", segments=12)
part("head", "cyl", "HelmetLamp", loc=(0.15, 0.06, 1.8), rot=(90, 0, 0), scale=(0.05, 0.05, 0.08), material="steel_dark")
part("head", "cyl", "HelmetLampLens", loc=(0.15, 0.105, 1.8), rot=(90, 0, 0), scale=(0.04, 0.04, 0.01), material="emissive_amber")
part("neck", "torus", "Collar", loc=(0, 0.0, 1.55), scale=(0.26, 0.24, 0.5), material="rubber", minor=0.18)
# vest + pouches + radio
part("chest", "cube", "Vest", loc=(0, 0.015, 1.33), scale=(0.37, 0.25, 0.33), material="fabric_dark", bevel=0.04)
for i, x in enumerate((-0.11, 0.0, 0.11)):
    part("chest", "cube", f"Pouch{i}", loc=(x, 0.15, 1.27), scale=(0.09, 0.06, 0.1), material="fabric_dark", bevel=0.015)
part("chest", "cube", "Radio", loc=(-0.13, 0.14, 1.43), scale=(0.05, 0.04, 0.09), material="plastic_dark", bevel=0.008)
part("chest", "cyl", "Antenna", loc=(-0.15, 0.12, 1.53), scale=(0.008, 0.008, 0.16), material="rubber")
part("chest", "cube", "ChestPlate", loc=(0, 0.14, 1.41), scale=(0.2, 0.03, 0.08), material="metal_yellow", bevel=0.01)
part("chest", "cube", "ChestLampBody", loc=(0.1, 0.16, 1.47), scale=(0.07, 0.05, 0.05), material="steel_dark", bevel=0.01)
part("chest", "cyl", "ChestLampLens", loc=(0.1, 0.19, 1.47), rot=(90, 0, 0), scale=(0.035, 0.035, 0.01), material="emissive_amber")
# backpack life-support unit
part("chest", "cube", "Pack", loc=(0, -0.18, 1.33), scale=(0.31, 0.15, 0.42), material="metal_painted", bevel=0.03)
part("chest", "cyl", "Tank", loc=(0.1, -0.29, 1.32), scale=(0.11, 0.11, 0.44), material="steel_bright", segments=20)
part("chest", "cyl", "Tank2", loc=(-0.1, -0.29, 1.32), scale=(0.11, 0.11, 0.44), material="steel_bright", segments=20)
part("chest", "cube", "PackStrap", loc=(0, -0.29, 1.2), scale=(0.34, 0.04, 0.04), material="hazard", bevel=0.005)
part("chest", "torus", "Hose", loc=(-0.12, -0.06, 1.5), rot=(0, 90, 0), scale=(0.25, 0.25, 0.25), material="rubber", minor=0.12)
# belt + utility
part("hips", "torus", "Belt", loc=(0, 0.0, 1.0), scale=(0.34, 0.25, 0.4), material="rubber", minor=0.16)
part("hips", "cube", "Buckle", loc=(0, 0.125, 1.0), scale=(0.07, 0.02, 0.05), material="steel_bright", bevel=0.005)
part("hips", "cube", "HipPouchR", loc=(0.17, 0.04, 0.96), scale=(0.06, 0.1, 0.11), material="fabric_dark", bevel=0.012)
part("hips", "cube", "HipPouchL", loc=(-0.17, 0.04, 0.96), scale=(0.06, 0.1, 0.11), material="fabric_dark", bevel=0.012)
for s in ("R", "L"):
    sx = 1 if s == "R" else -1
    part(f"shin_{s}", "cube", f"KneePad{s}", loc=(0.11 * sx, 0.09, 0.51), scale=(0.1, 0.05, 0.13), material="rubber", bevel=0.02)
    part(f"forearm_{s}", "cube", f"ElbowPad{s}", loc=(0.26 * sx, -0.06, 1.2), scale=(0.08, 0.05, 0.09), material="rubber", bevel=0.015)
    part(f"foot_{s}", "cube", f"Boot{s}", loc=(0.11 * sx, 0.06, 0.06), scale=(0.12, 0.29, 0.12), material="rubber", bevel=0.03)
    part(f"shin_{s}", "cyl", f"BootTop{s}", loc=(0.11 * sx, 0.0, 0.18), scale=(0.115, 0.12, 0.16), material="rubber")
    part(f"hand_{s}", "sphere", f"Glove{s}", loc=(0.31 * sx, 0.05, 0.89), scale=(0.075, 0.06, 0.11), material="rubber", segments=12)
    part(f"forearm_{s}", "cyl", f"Cuff{s}", loc=(0.295 * sx, 0.025, 0.99), rot=(8, 0, -8 * sx), scale=(0.085, 0.085, 0.06), material="fabric_dark")
    part(f"shoulder_{s}", "sphere", f"ShoulderPad{s}", loc=(0.19 * sx, -0.01, 1.5), scale=(0.17, 0.17, 0.075), material="metal_painted", segments=14)
    part(f"thigh_{s}", "cube", f"ThighPocket{s}", loc=(0.18 * sx, 0.02, 0.72), scale=(0.04, 0.12, 0.14), material="fabric_dark", bevel=0.012)

gear = ns.join(parts, "Gear")
model = ns.join([body, gear], "Survivor")
for m in list(model.modifiers):
    model.modifiers.remove(m)
ns.parent_rigid(model, arm)
print("SURVIVOR TRIS", ns.tri_count(model))

# ---------------------------------------------------------------- animations
P = ns.Pose(arm)
fwd = lambda b, d: P.q(b, ("x", d))  # noqa: E731  (+ = limb forward, - = trunk forward)


def hips_loc(dz=0.0, dy=0.0):
    # hips bone points up (+Z): bone-local Y = armature Z, bone-local Z = armature -Y
    return {"hips": Vector((0, dz, -dy))}


def cycle(name, frames, fn, keys=8):
    ns.new_action(arm, name)
    for k in range(keys + 1):
        t = k / keys
        pose, loc = fn(t * 2 * math.pi)
        ns.key_pose(arm, 1 + round(t * frames), pose, loc)
    ns.make_cyclic(arm)
    ns.stash(arm)


def once(name, keys):
    ns.new_action(arm, name)
    for frame, (pose, loc) in keys:
        ns.key_pose(arm, frame, pose, loc)
    ns.stash(arm)


def locomotion(a, amp_leg, amp_knee, amp_arm, lean, elbow, bob, crouch=0.0):
    s, c = math.sin(a), math.cos(a)
    pose = {
        "spine": fwd("spine", -lean * 0.5 - crouch * 18),
        "chest": fwd("chest", -lean * 0.5 + 2 * math.sin(2 * a)),
        "head": fwd("head", lean * 0.6 + crouch * 10),
        "thigh_R": fwd("thigh_R", amp_leg * s + crouch * 65),
        "thigh_L": fwd("thigh_L", -amp_leg * s + crouch * 65),
        "shin_R": fwd("shin_R", -amp_knee * max(0.0, -math.sin(a - 0.6)) - 6 - crouch * 105),
        "shin_L": fwd("shin_L", -amp_knee * max(0.0, math.sin(a - 0.6)) - 6 - crouch * 105),
        "foot_R": fwd("foot_R", 8 * c + crouch * 40),
        "foot_L": fwd("foot_L", -8 * c + crouch * 40),
        "upperarm_R": fwd("upperarm_R", -amp_arm * s + crouch * 25),
        "upperarm_L": fwd("upperarm_L", amp_arm * s + crouch * 25),
        "forearm_R": fwd("forearm_R", elbow + 10 * max(0.0, -s)),
        "forearm_L": fwd("forearm_L", elbow + 10 * max(0.0, s)),
    }
    return pose, hips_loc(-abs(c) * bob - crouch * 0.36)


cycle("idle", 72, lambda a: ({
    "chest": fwd("chest", 1.5 * math.sin(a)), "head": P.q("head", ("z", 6 * math.sin(a * 0.5)), ("x", -2)),
    "upperarm_R": P.q("upperarm_R", ("x", 4), ("y", 4 + math.sin(a) * 1.5)), "upperarm_L": P.q("upperarm_L", ("x", 4), ("y", -4 - math.sin(a) * 1.5)),
    "forearm_R": fwd("forearm_R", 14), "forearm_L": fwd("forearm_L", 14),
    "thigh_R": fwd("thigh_R", 2), "thigh_L": fwd("thigh_L", -2),
}, hips_loc(-0.006 * (1 + math.sin(a)))))
cycle("walk", 32, lambda a: locomotion(a, 24, 40, 16, 4, 16, 0.025))
cycle("run", 20, lambda a: locomotion(a, 40, 80, 38, 14, 75, 0.05))
cycle("crouch_idle", 60, lambda a: locomotion(0.0, 0, 0, 0, 6, 45, 0.0, 1.0)[0:1] + ({"hips": Vector((0, -0.36 - 0.005 * math.sin(a), 0))},))
cycle("crouch_walk", 36, lambda a: locomotion(a, 16, 22, 8, 6, 45, 0.015, 1.0))


def crawl(a):
    s = math.sin(a)
    pose = {
        "hips": P.q("hips", ("x", -82)),
        "spine": fwd("spine", 6), "chest": fwd("chest", 4), "head": fwd("head", 45),
        "upperarm_R": P.q("upperarm_R", ("x", 150 + 25 * s)), "upperarm_L": P.q("upperarm_L", ("x", 150 - 25 * s)),
        "forearm_R": fwd("forearm_R", 30 - 25 * s), "forearm_L": fwd("forearm_L", 30 + 25 * s),
        "thigh_R": fwd("thigh_R", 8 * s), "thigh_L": fwd("thigh_L", -8 * s),
        "shin_R": fwd("shin_R", -15 - 20 * max(0, s)), "shin_L": fwd("shin_L", -15 - 20 * max(0, -s)),
    }
    return pose, {"hips": Vector((0, -0.76, -0.25))}


cycle("crawl", 48, crawl)
cycle("downed_idle", 60, lambda a: (lambda p: (dict(p[0], chest=fwd("chest", 4 + 3 * math.sin(a))), p[1]))(crawl(0.0)))


def interact_pose(a, reach=55):
    return {
        "spine": fwd("spine", -6), "chest": fwd("chest", -4), "head": fwd("head", 14),
        "upperarm_R": fwd("upperarm_R", reach + 6 * math.sin(a * 2)), "upperarm_L": fwd("upperarm_L", reach - 6 * math.sin(a * 2 + 1)),
        "forearm_R": fwd("forearm_R", 50 + 10 * math.sin(a * 3)), "forearm_L": fwd("forearm_L", 50 + 10 * math.sin(a * 3 + 2)),
        "hand_R": fwd("hand_R", 10 * math.sin(a * 4)), "hand_L": fwd("hand_L", -10 * math.sin(a * 4)),
    }, hips_loc()


cycle("interact", 40, interact_pose)


def revive_pose(a):
    p = {
        "spine": fwd("spine", -25), "chest": fwd("chest", -18 - 6 * math.sin(a)), "head": fwd("head", 25),
        "thigh_R": fwd("thigh_R", 95), "shin_R": fwd("shin_R", -100), "foot_R": fwd("foot_R", 20),
        "thigh_L": fwd("thigh_L", 10), "shin_L": fwd("shin_L", -115), "foot_L": fwd("foot_L", 60),
        "upperarm_R": fwd("upperarm_R", 70 + 12 * math.sin(a)), "upperarm_L": fwd("upperarm_L", 70 + 12 * math.sin(a)),
        "forearm_R": fwd("forearm_R", 15), "forearm_L": fwd("forearm_L", 15),
    }
    return p, hips_loc(-0.5 - 0.02 * math.sin(a), 0.05)


cycle("revive", 30, revive_pose)
once("use_item", [(1, interact_pose(0.0, 0)), (8, interact_pose(1.0, 70)), (18, interact_pose(2.0, 70)), (24, interact_pose(0.0, 0))])
stand = ({}, hips_loc())
once("hit", [(1, stand), (4, ({"spine": fwd("spine", 12), "chest": fwd("chest", 8), "head": fwd("head", -15),
                                "upperarm_R": fwd("upperarm_R", 30), "upperarm_L": fwd("upperarm_L", 30)}, hips_loc(-0.03, -0.05))), (14, stand)])
lying = {"hips": P.q("hips", ("x", 86), ("y", 8)), "head": fwd("head", -10), "upperarm_R": P.q("upperarm_R", ("y", 50)),
         "upperarm_L": P.q("upperarm_L", ("y", -40)), "thigh_R": fwd("thigh_R", 12), "shin_R": fwd("shin_R", -30), "forearm_L": fwd("forearm_L", 30)}
lying_loc = {"hips": Vector((0, -0.8, 0.35))}
once("death", [(1, stand), (8, ({"spine": fwd("spine", 15), "head": fwd("head", -20), "thigh_R": fwd("thigh_R", 30), "shin_R": fwd("shin_R", -60),
                                 "shin_L": fwd("shin_L", -50)}, hips_loc(-0.35))), (22, (lying, lying_loc)), (26, (lying, {"hips": Vector((0, -0.78, 0.35))})), (30, (lying, lying_loc))])
once("dead", [(1, (lying, lying_loc)), (2, (lying, lying_loc))])

# rest pose for export
for pb in arm.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)

out = os.path.join(ns.ROOT, "assets", "characters", "survivor", "survivor.glb")
ns.export_glb(out, [arm, model])
preview = ns.arg("preview")
if preview:
    ns.preview_poses(arm, [model], preview, [("rest", None, 0), ("run", "run", 6), ("crouch", "crouch_walk", 9), ("crawl", "crawl", 12)],
                     (2.4, 3.2, 1.5), (0, 0, 0.9))
