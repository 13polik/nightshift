"""THE HUNTER - original creature model, rig and animations for NIGHT SHIFT.

Design: a 2.5 m hunched, eyeless predator. Elongated skull with sensory slits, a jaw that
splits vertically into two mandibles around a bioluminescent throat, dorsal bone spines,
chitin plates over taut grey-black hide, very long arms ending in three blade-fingers, and
digitigrade legs that make it rock forward when it stalks.

    blender --background --python tools/blender/build_hunter.py [-- --preview=<png>]

Output: assets/creatures/hunter/hunter.glb
Animations: idle patrol investigate search chase attack alert stunned door_open
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402,F401
from mathutils import Vector  # noqa: E402
import ns_common as ns  # noqa: E402

ns.reset()

J = {
    "pelvis": (0, 0.0, 1.28), "sp1": (0, 0.06, 1.52), "sp2": (0, 0.18, 1.76), "chest": (0, 0.34, 1.94),
    "nk1": (0, 0.5, 2.03), "nk2": (0, 0.64, 2.05), "head": (0, 0.76, 2.02),
}
for s, sx in (("R", 1), ("L", -1)):
    J.update({
        f"sh_{s}": (0.3 * sx, 0.3, 1.94), f"el_{s}": (0.42 * sx, 0.34, 1.42), f"wr_{s}": (0.4 * sx, 0.56, 0.96), f"hd_{s}": (0.39 * sx, 0.66, 0.82),
        f"hip_{s}": (0.17 * sx, 0.0, 1.22), f"kn_{s}": (0.21 * sx, 0.3, 0.86), f"hk_{s}": (0.21 * sx, -0.14, 0.42),
        f"bl_{s}": (0.21 * sx, 0.06, 0.07), f"to_{s}": (0.21 * sx, 0.3, 0.02),
    })
names = list(J.keys())
idx = {n: i for i, n in enumerate(names)}
edges = [("pelvis", "sp1"), ("sp1", "sp2"), ("sp2", "chest"), ("chest", "nk1"), ("nk1", "nk2"), ("nk2", "head")]
for s in ("R", "L"):
    edges += [("chest", f"sh_{s}"), (f"sh_{s}", f"el_{s}"), (f"el_{s}", f"wr_{s}"), (f"wr_{s}", f"hd_{s}"),
              ("pelvis", f"hip_{s}"), (f"hip_{s}", f"kn_{s}"), (f"kn_{s}", f"hk_{s}"), (f"hk_{s}", f"bl_{s}"), (f"bl_{s}", f"to_{s}")]
R = {"pelvis": (0.17, 0.12), "sp1": (0.13, 0.1), "sp2": (0.15, 0.12), "chest": (0.23, 0.17), "nk1": (0.075, 0.08), "nk2": (0.06, 0.065), "head": (0.075, 0.08)}
for s in ("R", "L"):
    R.update({f"sh_{s}": (0.085, 0.085), f"el_{s}": (0.05, 0.05), f"wr_{s}": (0.04, 0.035), f"hd_{s}": (0.045, 0.02),
              f"hip_{s}": (0.115, 0.11), f"kn_{s}": (0.085, 0.08), f"hk_{s}": (0.042, 0.042), f"bl_{s}": (0.045, 0.04), f"to_{s}": (0.03, 0.02)})
body = ns.skin_body("HunterBody", [Vector(J[n]) for n in names], [(idx[a], idx[b]) for a, b in edges],
                    [R[n] for n in names], root=idx["pelvis"], subdiv=2, material="hunter_skin")
ns.cube_uv(body, 0.6)

bones = [
    ("hips", J["pelvis"], J["sp1"], None), ("spine1", J["sp1"], J["sp2"], "hips"), ("spine2", J["sp2"], J["chest"], "spine1"),
    ("chest", J["chest"], J["nk1"], "spine2"), ("neck1", J["nk1"], J["nk2"], "chest"), ("neck2", J["nk2"], J["head"], "neck1"),
    ("head", J["head"], (0, 1.05, 1.98), "neck2"),
    ("jaw_R", (0.03, 0.8, 1.96), (0.06, 1.0, 1.88), "head"), ("jaw_L", (-0.03, 0.8, 1.96), (-0.06, 1.0, 1.88), "head"),
]
for s, sx in (("R", 1), ("L", -1)):
    bones += [
        (f"shoulder_{s}", (0.08 * sx, 0.32, 1.94), J[f"sh_{s}"], "chest"), (f"upperarm_{s}", J[f"sh_{s}"], J[f"el_{s}"], f"shoulder_{s}"),
        (f"forearm_{s}", J[f"el_{s}"], J[f"wr_{s}"], f"upperarm_{s}"), (f"hand_{s}", J[f"wr_{s}"], J[f"hd_{s}"], f"forearm_{s}"),
        (f"thigh_{s}", J[f"hip_{s}"], J[f"kn_{s}"], "hips"), (f"shin_{s}", J[f"kn_{s}"], J[f"hk_{s}"], f"thigh_{s}"),
        (f"hock_{s}", J[f"hk_{s}"], J[f"bl_{s}"], f"shin_{s}"), (f"toe_{s}", J[f"bl_{s}"], J[f"to_{s}"], f"hock_{s}"),
    ]
arm = ns.armature("HunterRig", [(n, h, t, p, 0) for n, h, t, p in bones])
ns.bind(body, arm)

parts = []


def part(bone, *a, **k):
    o = ns.add_prim(*a, **k)
    ns.rigid_to_bone(o, bone)
    parts.append(o)
    return o


# elongated eyeless skull, crest, sensory slits, split mandibles, glowing throat
part("head", "sphere", "Skull", loc=(0, 0.86, 2.02), rot=(-12, 0, 0), scale=(0.2, 0.42, 0.22), material="hunter_skin", segments=24)
part("head", "sphere", "SkullCrest", loc=(0, 0.78, 2.13), rot=(-20, 0, 0), scale=(0.05, 0.38, 0.12), material="hunter_skin", segments=16)
for sx in (1, -1):
    part("head", "sphere", f"Slit{sx}", loc=(0.085 * sx, 0.98, 2.05), rot=(0, 0, 10 * sx), scale=(0.015, 0.12, 0.025), material="hunter_glow", segments=10)
    part("head", "sphere", f"Slit2{sx}", loc=(0.09 * sx, 0.9, 2.08), scale=(0.012, 0.08, 0.018), material="hunter_glow", segments=8)
part("head", "sphere", "Throat", loc=(0, 0.88, 1.93), scale=(0.1, 0.18, 0.07), material="hunter_glow", segments=12)
for s, sx in (("R", 1), ("L", -1)):
    part(f"jaw_{s}", "cone", f"Mandible{s}", loc=(0.06 * sx, 0.93, 1.9), rot=(-80, 0, -8 * sx), scale=(0.1, 0.1, 0.32), material="hunter_skin", segments=10, r2=0.1)
    for t in range(3):
        part(f"jaw_{s}", "cone", f"Tooth{s}{t}", loc=(0.03 * sx, 0.86 + t * 0.06, 1.88), rot=(180, 0, 0), scale=(0.018, 0.018, 0.07), material="steel_bright", segments=6)
# dorsal spines and chitin plates
for i, (b, y, z) in enumerate([("spine1", -0.05, 1.55), ("spine1", 0.0, 1.66), ("spine2", 0.07, 1.78), ("spine2", 0.14, 1.88), ("chest", 0.24, 2.0), ("chest", 0.36, 2.07)]):
    part(b, "cone", f"Spine{i}", loc=(0, y - 0.09, z + 0.05), rot=(40, 0, 0), scale=(0.05, 0.05, 0.18 + 0.04 * (i % 3)), material="hunter_skin", segments=8)
part("chest", "sphere", "ChestPlate", loc=(0, 0.44, 1.86), rot=(25, 0, 0), scale=(0.34, 0.16, 0.3), material="hunter_skin", segments=18)
for i in range(4):
    part("chest", "torus", f"Rib{i}", loc=(0, 0.36 - i * 0.02, 1.74 + i * 0.06), rot=(80, 0, 0), scale=(0.42 - i * 0.03, 0.3, 0.25), material="hunter_skin", segments=16, minor=0.06)
for s, sx in (("R", 1), ("L", -1)):
    part(f"shoulder_{s}", "sphere", f"ShoulderPlate{s}", loc=(0.3 * sx, 0.28, 2.0), rot=(0, 20 * sx, 0), scale=(0.2, 0.22, 0.12), material="hunter_skin", segments=14)
    part(f"upperarm_{s}", "cone", f"ElbowSpur{s}", loc=(0.44 * sx, 0.28, 1.45), rot=(110, 0, 0), scale=(0.04, 0.04, 0.16), material="hunter_skin", segments=8)
    for f, ang in enumerate((-14, 0, 14)):
        part(f"hand_{s}", "cone", f"Claw{s}{f}", loc=(0.39 * sx + ang * 0.002 * sx, 0.73, 0.66), rot=(-152, ang * sx, 0), scale=(0.042, 0.042, 0.4), material="steel_dark", segments=8)
    for f, ang in enumerate((-12, 12)):
        part(f"toe_{s}", "cone", f"ToeClaw{s}{f}", loc=(0.21 * sx + ang * 0.003, 0.36, 0.03), rot=(-85, ang, 0), scale=(0.03, 0.03, 0.14), material="steel_dark", segments=8)
    part(f"shin_{s}", "cone", f"HockSpur{s}", loc=(0.21 * sx, -0.22, 0.5), rot=(130, 0, 0), scale=(0.035, 0.035, 0.14), material="hunter_skin", segments=8)

gear = ns.join(parts, "Anatomy")
model = ns.join([body, gear], "Hunter")
for m in list(model.modifiers):
    model.modifiers.remove(m)
ns.parent_rigid(model, arm)
print("HUNTER TRIS", ns.tri_count(model))

# ---------------------------------------------------------------- animations
P = ns.Pose(arm)
fwd = lambda b, d: P.q(b, ("x", d))  # noqa: E731


def hips(dz=0.0, dy=0.0):
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


def gait(a, stride, lift, arm_sw, hunch, head_sweep=0.0, head_low=0.0, sway=0.0, jaw=0.0):
    s, c = math.sin(a), math.cos(a)
    pose = {
        "spine1": P.q("spine1", ("x", -hunch * 0.4), ("z", sway * s)),
        "spine2": P.q("spine2", ("x", -hunch * 0.3 + 3 * math.sin(2 * a)), ("z", sway * s * 0.5)),
        "chest": P.q("chest", ("x", -hunch * 0.3), ("y", 4 * s)),
        "neck1": fwd("neck1", hunch * 0.3 + head_low),
        "neck2": P.q("neck2", ("x", hunch * 0.2), ("z", head_sweep)),
        "head": P.q("head", ("z", head_sweep * 0.6), ("y", 6 * math.sin(a * 0.5))),
        "jaw_R": P.q("jaw_R", ("z", -jaw)), "jaw_L": P.q("jaw_L", ("z", jaw)),
        "thigh_R": fwd("thigh_R", stride * s), "thigh_L": fwd("thigh_L", -stride * s),
        "shin_R": fwd("shin_R", -lift * max(0.0, -math.sin(a - 0.5))), "shin_L": fwd("shin_L", -lift * max(0.0, math.sin(a - 0.5))),
        "hock_R": fwd("hock_R", lift * 0.6 * max(0.0, -math.sin(a - 0.3))), "hock_L": fwd("hock_L", lift * 0.6 * max(0.0, math.sin(a - 0.3))),
        "toe_R": fwd("toe_R", 15 * c), "toe_L": fwd("toe_L", -15 * c),
        "upperarm_R": P.q("upperarm_R", ("x", -arm_sw * s + hunch * 0.5), ("y", -6)),
        "upperarm_L": P.q("upperarm_L", ("x", arm_sw * s + hunch * 0.5), ("y", 6)),
        "forearm_R": fwd("forearm_R", 18 + arm_sw * 0.4 * max(0, s)), "forearm_L": fwd("forearm_L", 18 + arm_sw * 0.4 * max(0, -s)),
        "hand_R": fwd("hand_R", -10 + 8 * s), "hand_L": fwd("hand_L", -10 - 8 * s),
    }
    return pose, hips(-abs(c) * 0.04 - hunch * 0.003, 0)


cycle("idle", 90, lambda a: ({
    "spine2": fwd("spine2", 2 * math.sin(a)), "chest": fwd("chest", 3 * math.sin(a)),
    "neck2": P.q("neck2", ("z", 12 * math.sin(a * 0.5))), "head": P.q("head", ("y", 14 * math.sin(a)), ("x", -4 * math.sin(a * 2))),
    "jaw_R": P.q("jaw_R", ("z", -3 - 3 * math.sin(a * 3))), "jaw_L": P.q("jaw_L", ("z", 3 + 3 * math.sin(a * 3))),
    "upperarm_R": P.q("upperarm_R", ("x", 8), ("y", -5)), "upperarm_L": P.q("upperarm_L", ("x", 8), ("y", 5)),
    "forearm_R": fwd("forearm_R", 20), "forearm_L": fwd("forearm_L", 20),
    "hand_R": fwd("hand_R", -10 + 12 * max(0, math.sin(a * 4))), "hand_L": fwd("hand_L", -10),
}, hips(-0.01 * (1 + math.sin(a)))))
cycle("patrol", 48, lambda a: gait(a, 22, 35, 14, 15, 10 * math.sin(a * 0.5), 5, 4))
cycle("investigate", 60, lambda a: gait(a, 16, 28, 8, 22, 28 * math.sin(a), 18, 3, 6))
cycle("search", 96, lambda a: ({
    "spine1": fwd("spine1", -10), "spine2": P.q("spine2", ("x", -8), ("z", 15 * math.sin(a))), "chest": P.q("chest", ("z", 10 * math.sin(a))),
    "neck1": fwd("neck1", 15), "neck2": P.q("neck2", ("z", 35 * math.sin(a)), ("x", 8 * math.sin(a * 3))), "head": P.q("head", ("y", 18 * math.sin(a * 2))),
    "jaw_R": P.q("jaw_R", ("z", -6)), "jaw_L": P.q("jaw_L", ("z", 6)),
    "thigh_R": fwd("thigh_R", 25), "thigh_L": fwd("thigh_L", 20), "shin_R": fwd("shin_R", -30), "shin_L": fwd("shin_L", -25),
    "hock_R": fwd("hock_R", 20), "hock_L": fwd("hock_L", 15),
    "upperarm_R": P.q("upperarm_R", ("x", 25), ("y", -10)), "upperarm_L": P.q("upperarm_L", ("x", 25), ("y", 10)),
    "forearm_R": fwd("forearm_R", 30), "forearm_L": fwd("forearm_L", 30),
}, hips(-0.15)))
cycle("chase", 18, lambda a: gait(a, 42, 75, 45, 48, 0, -10, 8, 10))
cycle("stunned", 24, lambda a: ({
    "spine1": P.q("spine1", ("x", -15 + 6 * math.sin(a * 3)), ("z", 8 * math.sin(a * 5))), "chest": P.q("chest", ("y", 15 * math.sin(a * 4))),
    "neck2": P.q("neck2", ("z", 30 * math.sin(a * 6)), ("x", 10 * math.sin(a * 7))), "head": P.q("head", ("y", 25 * math.sin(a * 5))),
    "jaw_R": P.q("jaw_R", ("z", -18 - 8 * math.sin(a * 8))), "jaw_L": P.q("jaw_L", ("z", 18 + 8 * math.sin(a * 8))),
    "upperarm_R": P.q("upperarm_R", ("x", 40 + 20 * math.sin(a * 4)), ("y", 30)), "upperarm_L": P.q("upperarm_L", ("x", 30 - 20 * math.sin(a * 5)), ("y", -30)),
    "forearm_R": fwd("forearm_R", 60), "forearm_L": fwd("forearm_L", 50),
    "thigh_R": fwd("thigh_R", 30), "thigh_L": fwd("thigh_L", 25), "shin_R": fwd("shin_R", -40), "shin_L": fwd("shin_L", -35),
}, hips(-0.25 + 0.03 * math.sin(a * 3))), keys=16)

rest = gait(0.0, 0, 0, 0, 15)
wind = ({"spine1": fwd("spine1", 10), "spine2": fwd("spine2", 12), "chest": P.q("chest", ("x", 10), ("y", -25)),
         "neck1": fwd("neck1", -10), "jaw_R": P.q("jaw_R", ("z", -25)), "jaw_L": P.q("jaw_L", ("z", 25)),
         "upperarm_R": P.q("upperarm_R", ("x", 150), ("y", -40)), "forearm_R": fwd("forearm_R", 70),
         "upperarm_L": P.q("upperarm_L", ("x", 40), ("y", 20)), "thigh_R": fwd("thigh_R", -10), "thigh_L": fwd("thigh_L", 20)}, hips(0.05))
strike = ({"spine1": fwd("spine1", -25), "spine2": fwd("spine2", -20), "chest": P.q("chest", ("x", -20), ("y", 30)),
           "neck1": fwd("neck1", 20), "jaw_R": P.q("jaw_R", ("z", -30)), "jaw_L": P.q("jaw_L", ("z", 30)),
           "upperarm_R": P.q("upperarm_R", ("x", 20), ("y", 20)), "forearm_R": fwd("forearm_R", 10), "hand_R": fwd("hand_R", -30),
           "upperarm_L": P.q("upperarm_L", ("x", 70), ("y", 30)), "thigh_R": fwd("thigh_R", 30), "shin_R": fwd("shin_R", -30), "thigh_L": fwd("thigh_L", -20)}, hips(-0.2, 0.15))
once("attack", [(1, rest), (12, wind), (17, strike), (24, strike), (34, rest)])
screech = ({"spine1": fwd("spine1", 12), "spine2": fwd("spine2", 15), "chest": fwd("chest", 12), "neck1": fwd("neck1", -25),
            "neck2": fwd("neck2", -20), "head": P.q("head", ("x", -15)), "jaw_R": P.q("jaw_R", ("z", -45)), "jaw_L": P.q("jaw_L", ("z", 45)),
            "upperarm_R": P.q("upperarm_R", ("x", 40), ("y", -70)), "upperarm_L": P.q("upperarm_L", ("x", 40), ("y", 70)),
            "forearm_R": fwd("forearm_R", 30), "forearm_L": fwd("forearm_L", 30)}, hips(0.12))
shake = (dict(screech[0], neck2=P.q("neck2", ("x", -20), ("z", 10)), head=P.q("head", ("x", -15), ("y", 10))), screech[1])
once("alert", [(1, rest), (8, screech), (14, shake), (20, screech), (26, shake), (30, screech), (40, rest)])
shove = ({"spine1": fwd("spine1", -15), "chest": fwd("chest", -10), "upperarm_R": P.q("upperarm_R", ("x", 85)), "forearm_R": fwd("forearm_R", 5),
          "hand_R": fwd("hand_R", 40), "thigh_R": fwd("thigh_R", 25), "shin_R": fwd("shin_R", -25), "neck1": fwd("neck1", 10)}, hips(-0.05, 0.1))
once("door_open", [(1, rest), (10, ({"upperarm_R": P.q("upperarm_R", ("x", 50)), "forearm_R": fwd("forearm_R", 60), "chest": fwd("chest", 6)}, hips())),
                   (16, shove), (24, shove), (32, rest)])

for pb in arm.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)

out = os.path.join(ns.ROOT, "assets", "creatures", "hunter", "hunter.glb")
ns.export_glb(out, [arm, model])
preview = ns.arg("preview")
if preview:
    ns.preview_poses(arm, [model], preview, [("rest", None, 0), ("chase", "chase", 5), ("attack", "attack", 17), ("alert", "alert", 9)],
                     (3.0, 3.6, 2.0), (0, 0.3, 1.3), 38)
