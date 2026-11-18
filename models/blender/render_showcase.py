"""Renders the panel hardware models on a piece of board, with Cycles.

python render_showcase.py MODELS_DIR OUT_PNG
"""
import bpy, math, sys
from mathutils import Matrix, Vector

src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=src + "/RBMKModels.glb")
import json
info = json.load(open(src + "/models.json"))
proto = {o.name.split(".")[0]: o for o in scene.objects if o.type == 'MESH'}
for o in proto.values():
    o.hide_render = True
    o.hide_viewport = True

# Data frame (X right, Y up the panel, Z out) to Blender (Z up): the glTF
# importer turns the meshes the same way.
C = Matrix.Rotation(math.radians(90), 4, 'X')


def mat(name, color, metal=0.0, rough=0.4, alpha=1.0, emit=0.0, transmission=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["Alpha"].default_value = alpha
    if transmission > 0:
        b.inputs["Transmission Weight"].default_value = transmission
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


BLACK = mat("black", (0.02, 0.02, 0.022), rough=0.35)
CHROME = mat("chrome", (0.8, 0.8, 0.82), metal=1.0, rough=0.18)
BRASS = mat("brass", (0.75, 0.56, 0.22), metal=1.0, rough=0.3)
RED = mat("red", (0.6, 0.03, 0.02), rough=0.3)
COVER = mat("cover", (0.85, 0.12, 0.08), rough=0.08, alpha=0.45, transmission=0.6)
WHITE = mat("white", (0.85, 0.85, 0.8), rough=0.35)
YELLOW = mat("yellow", (0.8, 0.6, 0.05), rough=0.35)
GREEN_LIT = mat("greenlit", (0.2, 1.0, 0.35), emit=6.0, rough=0.2)
RED_DARK = mat("reddark", (0.25, 0.03, 0.03), rough=0.15, transmission=0.3)
BOARD = mat("board", (0.42, 0.47, 0.43), rough=0.55)
PLATE = mat("plate", (0.88, 0.87, 0.82), rough=0.5)


def place(name, material, x, y, angle=0.0, open_angle=None, z=0.0):
    """Put model `name` at board point (x, y), `z` out from the board,
    turned `angle` degrees clockwise as the operator sees it (about Z of
    the data frame); a guard cover is swung `open_angle` degrees open."""
    o = proto[name].copy()
    o.data = proto[name].data.copy()
    scene.collection.objects.link(o)
    o.hide_render = False
    o.hide_viewport = False
    o.data.materials.clear()
    o.data.materials.append(material)
    c = Vector(info[name]["center"])
    T = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(-angle), 4, 'Z')
    if open_angle is not None:
        h = Vector(info[name]["hinge"])
        T = T @ Matrix.Translation(h) @ Matrix.Rotation(math.radians(-open_angle), 4, 'X') @ Matrix.Translation(-h)
    T = T @ Matrix.Translation(c)
    # The imported mesh is already turned by C: undo that, place it in the
    # data frame, and turn the result back into Blender's frame.
    o.matrix_world = C @ T @ C.inverted()
    return o


def guarded(x, y, large, open_angle):
    suffix = "Large" if large else ""
    base_t = info["GuardCover" + suffix]["hinge"][2]
    place("GuardBase" + suffix, YELLOW if large else BLACK, x, y)
    if large:
        place("MushroomCollar", CHROME, x, y, z=base_t)
        place("MushroomCap", RED, x, y, z=base_t)
    else:
        place("PushCollar", CHROME, x, y, z=base_t)
        place("PushCap", RED, x, y, z=base_t)
    place("GuardCover" + suffix, COVER, x, y, open_angle=open_angle)


# A piece of board.
bpy.ops.mesh.primitive_plane_add(size=1)
board = bpy.context.active_object
board.scale = (9.0, 5.0, 1)
board.rotation_euler = (math.radians(90), 0, 0)
board.location = (2.6, 0, 1.2)
board.data.materials.append(BOARD)

# Top row: the scram button's guard closed and lifted, and a guarded
# pushbutton closed and lifted.
guarded(0.3, 1.75, True, 0)
guarded(1.75, 1.75, True, 100)
guarded(3.3, 1.75, False, 0)
guarded(4.35, 1.75, False, 100)
# Bottom row: a control switch module (lamps over a pistol grip turned to
# START), a key switch, a selector and plain pushbuttons.
place("LampBezel", CHROME, 0.08, 0.5)
place("LampLens", GREEN_LIT, 0.08, 0.5)
place("LampBezel", CHROME, 0.48, 0.5)
place("LampLens", RED_DARK, 0.48, 0.5)
place("SwitchHub", BLACK, 0.28, 0.0)
place("PistolGrip", BLACK, 0.28, 0.0, angle=45)
place("KeyLock", CHROME, 1.4, 0.1)
place("Key", BRASS, 1.4, 0.1, angle=-45)
place("KeyBow", BRASS, 1.4, 0.1, angle=-45)
place("Knob", BLACK, 2.3, 0.1)
place("KnobPointer", WHITE, 2.3, 0.1, angle=60)
for i, m in enumerate((BLACK, WHITE, YELLOW, RED)):
    place("PushCollar", CHROME, 3.2 + 0.55 * i, 0.1)
    place("PushCap", m, 3.2 + 0.55 * i, 0.1)

# Light and camera.
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.6, 0.62, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
bpy.ops.object.light_add(type='AREA', location=(2.3, -4, 5))
light = bpy.context.active_object
light.data.energy = 900
light.data.size = 5
light.rotation_euler = (math.radians(45), 0, 0)
bpy.ops.object.camera_add(location=(2.3, -6.4, 3.6))
cam = bpy.context.active_object
cam.data.lens = 40
direction = Vector((2.3, 0, 1.0)) - cam.location
cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
scene.camera = cam
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.device = 'CPU'
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("rendered", out)
