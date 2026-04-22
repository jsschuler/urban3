import asyncio
import json
import queue
import threading

import bpy
import websockets


WS_URL = "ws://127.0.0.1:8765"
MATERIALS = {}
SNAPSHOTS = queue.Queue()


def material(name, color):
    if name in MATERIALS:
        return MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    MATERIALS[name] = mat
    return mat


def clear_scene():
    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith("lot_"):
            bpy.data.objects.remove(obj, do_unlink=True)


def lot_color(lot):
    res = lot["residential_units"]
    com = lot["commercial_units"]
    total = max(1, res + com)
    mix = com / total
    occ = (lot["occupied_residential"] + lot["occupied_commercial"]) / total
    return (0.20 + 0.45 * mix, 0.35 + 0.35 * occ, 0.75 - 0.45 * mix, 1.0)


def make_lot(lot, scale):
    total = lot["residential_units"] + lot["commercial_units"]
    if total <= 0:
        return
    height = max(0.08, total * 0.18)
    bpy.ops.mesh.primitive_cube_add(
        size=1,
        location=(lot["x"] * scale, lot["y"] * scale, height / 2),
    )
    obj = bpy.context.object
    obj.name = f"lot_{lot['id']}"
    obj.dimensions = (scale * 0.92, scale * 0.92, height)
    obj.data.materials.append(material("urban_mix", lot_color(lot)))


def render_snapshot(payload):
    clear_scene()
    scale = payload.get("lot_scale", 2)
    for lot in payload.get("lots", []):
        make_lot(lot, scale)
    bpy.context.view_layer.update()


async def listen():
    async with websockets.connect(WS_URL) as ws:
        async for msg in ws:
            payload = json.loads(msg)
            if payload.get("type") == "blender_snapshot":
                SNAPSHOTS.put(payload)


def network_thread():
    asyncio.run(listen())


def pump_snapshots():
    latest = None
    while True:
        try:
            latest = SNAPSHOTS.get_nowait()
        except queue.Empty:
            break
    if latest is not None:
        render_snapshot(latest)
    return 0.25


def start_client():
    thread = threading.Thread(target=network_thread, daemon=True)
    thread.start()
    bpy.app.timers.register(pump_snapshots)


if __name__ == "__main__":
    start_client()
