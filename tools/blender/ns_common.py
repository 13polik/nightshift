"""Shared helpers for NIGHT SHIFT's Blender asset scripts (Blender 5.x, background mode).

Conventions
 * Characters face +Y in Blender (=> -Z, Godot's forward, after glTF export).
 * Material names match MaterialLibrary entries in Godot; models carry geometry + UVs only,
   Godot assigns the shared PBR materials by name (MaterialLibrary.apply_named).
 * 1 UV unit = 1 metre (cube projection) so tiling texture sets keep texel density.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FPS = 30


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def mat(name, color=(0.5, 0.5, 0.5, 1.0)):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = color
    return m


def set_active(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifiers(obj):
    set_active(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def assign_material(obj, name):
    obj.data.materials.clear()
    obj.data.materials.append(mat(name))


def cube_uv(obj, size=1.0):
    set_active(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=size, scale_to_bounds=False, correct_aspect=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def shade_smooth(obj, angle=40):
    set_active(obj)
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except Exception:
        pass


def skin_body(name, joints, edges, radii, root=0, subdiv=2, material="fabric_suit"):
    """Organic body from a joint graph using the Skin modifier.
    joints: list of Vector, edges: list of (i, j), radii: list of (rx, ry)."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in joints], edges, [])
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    sk = obj.modifiers.new("Skin", "SKIN")
    sk.use_smooth_shade = True
    sk.branch_smoothing = 0.6
    layer = me.skin_vertices[""].data if "" in me.skin_vertices else me.skin_vertices[0].data
    for i, r in enumerate(radii):
        layer[i].radius = r
        layer[i].use_root = i == root
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = subdiv
    sub.render_levels = subdiv
    apply_modifiers(obj)
    assign_material(obj, material)
    shade_smooth(obj, 180)
    return obj


def add_prim(kind, name, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), material="steel_dark", bevel=0.0, segments=16, **kw):
    if kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1.0)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=0.5, depth=1.0)
    elif kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=max(6, segments // 2), radius=0.5)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=segments, radius1=0.5, radius2=kw.get("r2", 0.0), depth=1.0)
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(major_segments=segments, minor_segments=8, major_radius=0.5, minor_radius=kw.get("minor", 0.1))
    obj = bpy.context.active_object
    obj.name = name
    obj.location = loc
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    obj.scale = scale
    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0:
        b = obj.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        b.limit_method = "ANGLE"
        apply_modifiers(obj)
    assign_material(obj, material)
    cube_uv(obj, 1.0)
    shade_smooth(obj, 35)
    return obj


def join(objs, name):
    objs = [o for o in objs if o is not None]
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    out = bpy.context.active_object
    out.name = name
    return out


def rigid_to_bone(obj, bone):
    """All vertices weighted 1.0 to `bone` (equipment that does not deform)."""
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def armature(name, bones):
    """bones: list of (name, head, tail, parent or None, roll_deg). Returns armature object."""
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bpy.context.collection.objects.link(obj)
    set_active(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, head, tail, parent, roll in bones:
        eb = arm.edit_bones.new(bname)
        eb.head = head
        eb.tail = tail
        eb.roll = math.radians(roll)
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = (eb.parent.tail - eb.head).length < 1e-4
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return obj


def bind(mesh_obj, arm_obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    mesh_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def parent_rigid(mesh_obj, arm_obj):
    mesh_obj.parent = arm_obj
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj


# ------------------------------------------------------------------ animation authoring
class Pose:
    """Builds bone rotations from axis/angle pairs expressed in armature (rest) space,
    so animation code can say "rotate the thigh forward 30 degrees" independent of the
    individual bone roll."""

    def __init__(self, arm_obj):
        self.arm = arm_obj
        self.rest = {b.name: b.matrix_local.to_3x3() for b in arm_obj.data.bones}

    def q(self, bone, *rots):
        """rots: ('x'|'y'|'z', degrees) applied in order, about armature axes."""
        world = Matrix.Identity(3)
        for axis, deg in rots:
            world = Matrix.Rotation(math.radians(deg), 3, axis.upper()) @ world
        r = self.rest[bone]
        local = r.inverted() @ world @ r
        return local.to_quaternion()


def new_action(arm_obj, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    arm_obj.animation_data.action = act
    return act


def key_pose(arm_obj, frame, pose_dict, loc_dict=None):
    """pose_dict: bone -> Quaternion. Bones not listed are keyed at rest so blends are clean."""
    for pb in arm_obj.pose.bones:
        q = pose_dict.get(pb.name, Quaternion())
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        loc = (loc_dict or {}).get(pb.name)
        pb.location = loc if loc is not None else Vector()
        if loc_dict is not None and pb.name in loc_dict or pb.parent is None:
            pb.keyframe_insert("location", frame=frame)


def make_cyclic(arm_obj):
    act = arm_obj.animation_data.action
    for fc in _fcurves(act):
        if not any(m.type == "CYCLES" for m in fc.modifiers):
            fc.modifiers.new("CYCLES")


def _fcurves(act):
    try:
        return list(act.fcurves)
    except AttributeError:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def stash(arm_obj):
    """Push the current action to an NLA track so every action gets exported."""
    ad = arm_obj.animation_data
    act = ad.action
    track = ad.nla_tracks.new()
    track.name = act.name
    track.strips.new(act.name, int(act.frame_range[0]), act)
    track.mute = True
    ad.action = None


def export_glb(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_materials="EXPORT",
        export_image_format="NONE",
        export_apply=False,
    )
    print("EXPORTED", path)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def render_preview(path, objs, cam_loc, target, lens=50, res=(640, 640)):
    """Workbench preview render (used to inspect generated assets)."""
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.display.shading.light = "STUDIO"
    scn.display.shading.color_type = "MATERIAL"
    scn.render.resolution_x, scn.render.resolution_y = res
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = cam_loc
    d = Vector(target) - Vector(cam_loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def arg(name, default=None):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for a in argv:
        if a.startswith(f"--{name}="):
            return a.split("=", 1)[1]
    return default


def preview_poses(arm_obj, objs, path, poses, cam_loc, target, lens=40):
    ad = arm_obj.animation_data
    for t in ad.nla_tracks:
        t.mute = True
    files = []
    for label, action, frame in poses:
        ad.action = bpy.data.actions[action] if action else None
        for pb in arm_obj.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
        bpy.context.scene.frame_set(max(1, frame))
        f = path.replace(".png", f"_{label}.png")
        render_preview(f, objs, cam_loc, target, lens, (420, 560))
        files.append(f)
    ad.action = None
    print("PREVIEWS", files)
