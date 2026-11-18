"""Models the panel hardware of the RBMK-800 control room in Blender.

Run with Blender's Python (the `bpy` module):  python build_models.py OUTDIR

Every model is built in the panel's own frame: X to the operator's right,
Y up the face of the panel, Z out of the panel towards the operator, in
board units (the units the panel layout uses; 1 unit is 0.18 m in the room).
The origin is the device's mounting point on the panel surface.

Writes:
  OUTDIR/RBMKModels.glb   every model as a named mesh, for Roblox Studio's
                          3D importer (glTF is Y-up, so the meshes come in
                          with X right, Y up the panel, Z out of it), and
                          four probe cubes that mark the axes
  OUTDIR/Meshes/          the same triangles as Luau modules, for building
                          the meshes in-game (src/client/Meshes)
  OUTDIR/models.json      sizes and centres, for the preview renderer
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Matrix, Vector

OUT = sys.argv[-1] if len(sys.argv) > 1 and not sys.argv[-1].endswith(".py") else "."
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
models = {}


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    models[name] = obj
    return obj


def lathe(name, profile, segments=32):
    """A solid of revolution about Z from a profile of (radius, z) points,
    listed from the axis round the outside and back to the axis."""
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1),
                   angle=math.radians(360), steps=segments, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object(name, bm)


def extrude_outline(name, outline, z0, z1, bevel=0.0, segments=3):
    """A plate cut to a 2D outline in the panel plane, from z0 to z1, with
    rounded edges."""
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, z0)) for x, y in outline]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    top = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, z1 - z0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments,
                        profile=0.5, affect='EDGES', clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object(name, bm)


def rounded_rect(w, h, r, steps=6):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(steps + 1):
            a = math.radians(a0 + 90 * i / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def box(bm, cx, cy, cz, sx, sy, sz):
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def cylinder_x(bm, cx, cy, cz, r, length, segs=16):
    """A cylinder lying along X (a hinge barrel)."""
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Rotation(math.radians(90), 4, 'Y')
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r,
                          depth=length, matrix=m)


# ---------------------------------------------------------------- pushbuttons
# An oiltight pushbutton: a coloured cap, slightly domed, standing in a
# chrome collar.
lathe("PushCap", [(0, 0.195), (0.07, 0.193), (0.115, 0.187), (0.14, 0.175),
                  (0.15, 0.16), (0.15, 0.06), (0, 0.06)], 32)
lathe("PushCollar", [(0.152, 0.0), (0.152, 0.09), (0.162, 0.102), (0.2, 0.102),
                     (0.212, 0.09), (0.212, 0.0), (0.152, 0.0)], 40)

# The scram button: a large red mushroom head on a stem.
lathe("MushroomCap", [(0, 0.34), (0.12, 0.335), (0.22, 0.32), (0.29, 0.29),
                      (0.32, 0.25), (0.32, 0.21), (0.3, 0.19), (0.18, 0.18),
                      (0.17, 0.0), (0, 0.0)], 40)

# ---------------------------------------------------------------- lights
# An indicating light: a chrome bezel ring and a domed glass lens.
lathe("LampBezel", [(0.09, 0.0), (0.09, 0.055), (0.1, 0.068), (0.124, 0.068),
                    (0.135, 0.058), (0.135, 0.0), (0.09, 0.0)], 32)
lathe("LampLens", [(0, 0.125), (0.04, 0.123), (0.065, 0.113), (0.083, 0.095),
                   (0.09, 0.075), (0.09, 0.0), (0, 0.0)], 32)

# ---------------------------------------------------------------- switches
# A GE SBM control switch: a round boss on the escutcheon and a black
# pistol-grip handle pointing along +Y, rounded all over.
lathe("SwitchHub", [(0, 0.062), (0.09, 0.062), (0.105, 0.055), (0.115, 0.035),
                    (0.115, 0.0), (0, 0.0)], 32)


def pistol_grip(name):
    """The pistol-grip handle: broad over the shaft, narrowing to a rounded
    end along +Y, and thinner towards the end too, every edge rounded."""
    half_width = [(-0.07, 0.072), (0.0, 0.074), (0.1, 0.068), (0.2, 0.058), (0.29, 0.05)]
    tip_y, tip_r = 0.3, 0.05
    outline = [(w, y) for y, w in half_width]
    for i in range(1, 12):
        a = math.radians(180 * i / 12)
        outline.append((tip_r * math.cos(a), tip_y + tip_r * math.sin(a)))
    outline += [(-w, y) for y, w in reversed(half_width)]
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, 0.05)) for x, y in outline]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            # 0.15 thick over the shaft, 0.11 at the end.
            t = (v.co.y + 0.07) / (tip_y + tip_r + 0.07)
            v.co.z = 0.2 - 0.04 * t
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.022, segments=3, profile=0.5,
                    affect='EDGES', clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object(name, bm)


pistol_grip("PistolGrip")

# A key switch: a chrome lock cylinder and a brass key standing in it,
# its bow up when turned to 0.
lathe("KeyLock", [(0, 0.07), (0.07, 0.07), (0.075, 0.075), (0.125, 0.075),
                  (0.14, 0.06), (0.14, 0.0), (0, 0.0)], 32)
bm = bmesh.new()
box(bm, 0, 0, 0.11, 0.026, 0.07, 0.09)              # blade in the lock
box(bm, 0, 0, 0.165, 0.03, 0.12, 0.03)              # shoulder
new_object("Key", bm)
# The bow stands up out of the lock, flat across X, with a hole in it.
bm = bmesh.new()
verts = [bm.verts.new((-0.015, y, 0.265 + z)) for y, z in rounded_rect(0.19, 0.17, 0.06)]
face = bm.faces.new(verts)
ext = bmesh.ops.extrude_face_region(bm, geom=[face])
bmesh.ops.translate(bm, verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)],
                    vec=(0.03, 0, 0))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.008, segments=2, profile=0.5,
                affect='EDGES', clamp_overlap=True)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bow = new_object("KeyBow", bm)
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.025, radius2=0.025, depth=0.2,
                      matrix=Matrix.Translation((0, 0, 0.3)) @ Matrix.Rotation(math.radians(90), 4, 'Y'))
cut = bow.modifiers.new("hole", 'BOOLEAN')
cut.object = new_object("_bowhole", bm)
cut.operation = 'DIFFERENCE'

# A rotary selector: a black skirted knob and a white pointer bar.
lathe("Knob", [(0, 0.17), (0.12, 0.17), (0.145, 0.155), (0.15, 0.13), (0.15, 0.07),
               (0.19, 0.06), (0.21, 0.045), (0.21, 0.0), (0, 0.0)], 36)
bm = bmesh.new()
box(bm, 0, 0.03, 0.185, 0.05, 0.3, 0.04)
new_object("KnobPointer", bm)

# ---------------------------------------------------------------- guards
# A guarded pushbutton for the protection functions: a base plate clamped
# under the button's collar, with hinge knuckles along its top edge, and a
# hinged translucent cover with a lifting tab that has to be raised before
# the button can be pressed. The hinge axis runs along X at y = +half,
# z = base thickness; the button stands on the base. `k` scales the guard.
def guard(suffix, k, cover_h):
    half = 0.31 * k
    base_t = 0.05 * k
    bm = bmesh.new()
    vo = [bm.verts.new((x, y, 0)) for x, y in rounded_rect(2 * half, 2 * half, 0.06 * k)]
    bm.faces.new(vo)
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    bmesh.ops.translate(bm, verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)],
                        vec=(0, 0, base_t))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    base = new_object("GuardBase" + suffix, bm)
    bev = base.modifiers.new("bevel", 'BEVEL')
    bev.width = 0.014 * k
    bev.segments = 3
    bev.limit_method = 'ANGLE'
    # Hinge knuckles on the base, either side of the cover's barrel.
    bm2 = bmesh.new()
    for x in (-0.205 * k, 0.205 * k):
        cylinder_x(bm2, x, half, base_t, 0.032 * k, 0.11 * k, 20)
        box(bm2, x, half - 0.02 * k, base_t / 2 + 0.008 * k, 0.11 * k, 0.05 * k, base_t + 0.016 * k)
    j = base.modifiers.new("knuckles", 'BOOLEAN')
    j.object = new_object("_knuckles" + suffix, bm2)
    j.operation = 'UNION'
    j.solver = 'EXACT'
    j.use_self = True
    # The cover: an open-backed box with well rounded edges and walls a
    # couple of millimetres thick, the hinge barrel along its top edge and
    # a tab at the bottom to lift it by.
    bm3 = bmesh.new()
    box(bm3, 0, -0.012 * k, base_t + cover_h / 2, 2 * half - 0.03 * k, 2 * half - 0.05 * k, cover_h)
    bmesh.ops.delete(bm3, geom=[f for f in bm3.faces if f.normal.z < -0.9], context='FACES_ONLY')
    cover = new_object("GuardCover" + suffix, bm3)
    b2 = cover.modifiers.new("round", 'BEVEL')
    b2.width = 0.06 * k
    b2.segments = 5
    sh = cover.modifiers.new("shell", 'SOLIDIFY')
    sh.thickness = 0.02 * k
    sh.offset = -1
    bm4 = bmesh.new()
    cylinder_x(bm4, 0, half, base_t, 0.028 * k, 0.29 * k, 20)
    box(bm4, 0, half - 0.03 * k, base_t + 0.012 * k, 0.29 * k, 0.05 * k, 0.03 * k)
    tab_y = -half - 0.01 * k
    box(bm4, 0, tab_y, base_t + cover_h - 0.035 * k, 0.24 * k, 0.07 * k, 0.03 * k)
    u = cover.modifiers.new("barrel", 'BOOLEAN')
    u.object = new_object("_barrel" + suffix, bm4)
    u.operation = 'UNION'
    u.solver = 'EXACT'
    u.use_self = True
    return half, base_t


hinge = {}
for suffix, k, ch in (("", 1.0, 0.26), ("Large", 1.65, 0.42)):
    half, base_t = guard(suffix, k, ch)
    hinge[suffix] = (half, base_t)

# The scram button's chrome bezel ring, around the mushroom's stem.
lathe("MushroomCollar", [(0.172, 0.0), (0.172, 0.085), (0.186, 0.1), (0.27, 0.1),
                         (0.29, 0.085), (0.29, 0.0), (0.172, 0.0)], 40)

# ---------------------------------------------------------------- probes
# Four tiny cubes at the origin and one unit along each axis of the panel
# frame. They go into the glTF file (not the game's mesh data) so that the
# game can tell how Studio's importer turned the meshes.
PROBES = {"ProbeO": (0, 0, 0), "ProbeX": (1, 0, 0), "ProbeY": (0, 1, 0), "ProbeZ": (0, 0, 1)}
for name, at in PROBES.items():
    bm = bmesh.new()
    box(bm, at[0], at[1], at[2], 0.02, 0.02, 0.02)
    new_object(name, bm)

# ---------------------------------------------------------------- export
depsgraph = bpy.context.evaluated_depsgraph_get()
keep = [n for n in models if not n.startswith("_") and n not in PROBES]
data = {}
fmt = lambda x: ("%.4f" % x).rstrip("0").rstrip(".") if abs(x) >= 5e-5 else "0"
mesh_dir = os.path.join(OUT, "Meshes")
os.makedirs(mesh_dir, exist_ok=True)
for old in os.listdir(mesh_dir):
    os.remove(os.path.join(mesh_dir, old))
TO_GLTF = Matrix.Rotation(math.radians(90), 4, 'X')
for name in keep:
    obj = models[name]
    ev = obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(ev)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.set_sharp_from_angle(angle=math.radians(40))
    mesh.calc_loop_triangles()
    co = [v.co.copy() for v in mesh.vertices]
    assert co, name + ": empty after modifiers"
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    centre = (lo + hi) / 2
    size = hi - lo
    normals, nidx = [], {}
    tris = []
    corner = mesh.corner_normals
    for t in mesh.loop_triangles:
        ns = []
        for li in t.loops:
            n = corner[li].vector
            key = (round(n.x, 3), round(n.y, 3), round(n.z, 3))
            if key not in nidx:
                nidx[key] = len(normals) + 1
                normals.append(key)
            ns.append(nidx[key])
        tris.append([v + 1 for v in t.vertices] + ns)
    data[name] = {"size": [size.x, size.y, size.z], "center": [centre.x, centre.y, centre.z],
                  "tris": len(tris), "verts": len(co)}
    with open(os.path.join(mesh_dir, name + ".luau"), "w") as out:
        out.write("--!nolint\n-- Generated by models/blender/build_models.py: the %s mesh.\n" % name)
        out.write("-- v: vertex positions relative to the centre of the mesh (board units,\n")
        out.write("-- panel frame); n: normals; t: triangles, three vertex indices and then\n")
        out.write("-- the normal index for each corner.\nreturn {\n")
        out.write("\tv = { %s },\n" % ",".join(fmt(c[i] - centre[i]) for c in co for i in range(3)))
        out.write("\tn = { %s },\n" % ",".join(fmt(c) for k in normals for c in k))
        out.write("\tt = { %s },\n}\n" % ",".join(str(i) for tri in tris for i in tri))
    # Replace the object's mesh with the evaluated one for the glTF export,
    # centred and turned so that glTF's Y-up axes land on the panel frame.
    mesh.transform(Matrix.Translation(-centre))
    mesh.transform(TO_GLTF)
    # A plain planar UV map, so that importers that want one get one.
    uv = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        c = mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (0.5 + c.x, 0.5 + c.y)
    obj.modifiers.clear()
    obj.data = mesh
for name in PROBES:
    models[name].data.transform(TO_GLTF)
for k, (half, base_t) in hinge.items():
    data["GuardCover" + k]["hinge"] = [0.0, half, base_t]

index = ["--!nolint",
         "-- Generated by models/blender/build_models.py from the Blender models of",
         "-- the panel hardware. Sizes and centres are in board units, in the panel",
         "-- frame of the device: X to the operator's right, Y up the panel, Z out of",
         "-- it, with the origin at the device's mounting point on the panel. The",
         "-- triangles of each mesh are in the module of the same name.",
         "local Meshes = {}", "", "Meshes.info = {"]
for name in keep:
    d = data[name]
    index.append("\t%s = { size = { %s }, center = { %s }, tris = %d }," % (
        name, ", ".join(fmt(x) for x in d["size"]), ", ".join(fmt(x) for x in d["center"]), d["tris"]))
index += ["}", "",
          "-- Guard hinges: the axis runs along X through (0, y, z); z is also the",
          "-- thickness of the guard's base, on which the button stands.",
          "Meshes.hinge = {"]
for k, (half, base_t) in hinge.items():
    index.append("\t[\"%s\"] = { 0, %s, %s }," % (k, fmt(half), fmt(base_t)))
index += ["}", "",
          "-- The probes in RBMKModels.glb: where each axis of the panel frame ends up.",
          "Meshes.probes = { ProbeO = { 0, 0, 0 }, ProbeX = { 1, 0, 0 }, ProbeY = { 0, 1, 0 }, ProbeZ = { 0, 0, 1 } }",
          "",
          "function Meshes.geometry(name: string): { v: { number }, n: { number }, t: { number } }",
          "\treturn require((script :: any)[name])",
          "end", "", "return Meshes"]
open(os.path.join(mesh_dir, "init.luau"), "w").write("\n".join(index) + "\n")
open(os.path.join(OUT, "models.json"), "w").write(json.dumps(data, indent=1))

for name in list(models):
    if name.startswith("_"):
        bpy.data.objects.remove(models[name], do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for name in keep + list(PROBES):
    models[name].select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "RBMKModels.glb"), export_format='GLB',
                          use_selection=True, export_yup=True, export_apply=True)
for name in keep:
    print("%-16s %5d tris  size %s" % (name, data[name]["tris"], ["%.3f" % s for s in data[name]["size"]]))
