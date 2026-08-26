"""Draw what the village camera sees at a gate, from MEASURED geometry -- not a screenshot.

WHY THIS EXISTS. Roadmap row 33.4 has two halves: an occlusion survey (arithmetic) and a capture
(judgement). Two builds of the gate rampart passed the survey at 0 of 840 visible wall cells and
were refused by the capture -- one buried the gate, one read as a picket fence -- so the row does
not close on numbers alone. On 2026-08-26 `screen_capture` stopped answering: `RenderStepped` fired
0 times in 2 seconds while `Heartbeat` fired 121, i.e. Studio was simulating and not drawing a
single frame, so there was nothing for the capture to grab and it timed out seven times.

This draws the same frame from the geometry the survey already measures. It is NOT a substitute for
the capture and must never be called one: it has no lighting, no fog, no textures and no mesh
detail -- it is the SILHOUETTE, which is exactly and only what the two failed builds were refused
over. It answers "is the gate covered by rock" and "do the rocks read as a range or as a fence",
and it cannot answer anything about colour or material.

Input is `tools/_33_4_geometry.json`, posted out of Studio: every rock as a cone (centre, half
extents, top, sink) and every gate piece as a world AABB.

    python tools/render_gate_elevation.py south   -> tools/_33_4_south.png
    python tools/render_gate_elevation.py north   -> tools/_33_4_north.png
"""

import json
import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEOM = os.path.join(ROOT, "tools", "_33_4_geometry.json")

W, H = 1100, 620
FOV_DEG = 70.0                     # Studio's default field of view

# The two eyes the 33.4 survey judged from, and the two the captures were taken from.
VIEWS = {
    "south": dict(eye=(0.0, 25.0, -240.0), at=(0.0, 80.0, -580.0), sign=-1),
    "north": dict(eye=(0.0, 25.0, 250.0), at=(0.0, 90.0, 560.0), sign=1),
}

SKY = (150, 200, 240)
GROUND = (120, 175, 110)
WALL = (past := (108, 124, 148))
ROCK_FILL = {
    "GateRampart": (176, 196, 214),
    "HorizonHill": (150, 174, 196),
    "PassShoulder": (150, 174, 196),
    "GateFlank": (120, 146, 170),
    "GateBackfill": (120, 146, 170),
    "FlankHill": (150, 174, 196),
    "FlankCrag": (120, 146, 170),
    "PassRock": (110, 134, 158),
    "RidgePlate": (140, 164, 186),
}
GATE_FILL = (196, 92, 96)


def look_basis(eye, at):
    fx, fy, fz = at[0] - eye[0], at[1] - eye[1], at[2] - eye[2]
    fl = math.sqrt(fx * fx + fy * fy + fz * fz)
    f = (fx / fl, fy / fl, fz / fl)
    # right = normalise(forward x worldUp)
    rx, ry, rz = f[1] * 0.0 - f[2] * 1.0, f[2] * 0.0 - f[0] * 0.0, f[0] * 1.0 - f[1] * 0.0
    rl = math.sqrt(rx * rx + ry * ry + rz * rz)
    r = (rx / rl, ry / rl, rz / rl)
    u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])
    return f, r, u


def project(p, eye, f, r, u, focal):
    d = (p[0] - eye[0], p[1] - eye[1], p[2] - eye[2])
    depth = d[0] * f[0] + d[1] * f[1] + d[2] * f[2]
    if depth <= 1.0:
        return None
    sx = d[0] * r[0] + d[1] * r[1] + d[2] * r[2]
    sy = d[0] * u[0] + d[1] * u[1] + d[2] * u[2]
    return (W / 2 + focal * sx / depth, H / 2 - focal * sy / depth, depth)


def main():
    which = (sys.argv[1] if len(sys.argv) > 1 else "south").lower()
    v = VIEWS[which]
    eye, at, sign = v["eye"], v["at"], v["sign"]

    geom = json.load(open(GEOM, encoding="utf-8"))
    focal = (W / 2) / math.tan(math.radians(FOV_DEG) / 2)
    f, r, u = look_basis(eye, at)

    img = Image.new("RGB", (W, H), SKY)
    dr = ImageDraw.Draw(img)

    horizon = project((0.0, 0.0, at[2]), eye, f, r, u, focal)
    if horizon:
        dr.rectangle([0, horizon[1], W, H], fill=GROUND)

    prims = []

    # The boundary wall of THIS side, as a flat slab: the thing the row is about.
    wz = sign * geom["wall"]["z"]
    wh = geom["wall"]["h"]
    quad = [(-900, 0, wz), (900, 0, wz), (900, wh, wz), (-900, wh, wz)]
    pts = [project(p, eye, f, r, u, focal) for p in quad]
    if all(pts):
        prims.append((abs(wz - eye[2]), [(p[0], p[1]) for p in pts], WALL, "wall"))

    # Every rock as its silhouette triangle: the two extreme base points across the view, and
    # the apex. A cone's outline from a camera is that triangle to within the width of the peak,
    # which is the accuracy this drawing claims.
    for k in geom["rocks"]:
        if k["z"] * sign <= 0:
            continue
        base_y = -k["sink"]
        tri = [(k["x"] - k["rx"], base_y, k["z"]),
               (k["x"] + k["rx"], base_y, k["z"]),
               (k["x"], k["top"], k["z"])]
        pts = [project(p, eye, f, r, u, focal) for p in tri]
        if not all(pts):
            continue
        depth = sum(p[2] for p in pts) / 3.0
        prims.append((depth, [(p[0], p[1]) for p in pts],
                      ROCK_FILL.get(k["n"], (150, 174, 196)), k["n"]))

    # The gate, as the screen-space box of each piece.
    for g in geom["gate"]:
        if g["z"] * sign <= 0:
            continue
        corners = []
        for dx in (-0.5, 0.5):
            for dy in (-0.5, 0.5):
                for dz in (-0.5, 0.5):
                    corners.append((g["x"] + dx * g["sx"], g["y"] + dy * g["sy"],
                                    g["z"] + dz * g["sz"]))
        pts = [project(p, eye, f, r, u, focal) for p in corners]
        pts = [p for p in pts if p]
        if not pts:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        depth = sum(p[2] for p in pts) / len(pts)
        box = [(min(xs), min(ys)), (max(xs), min(ys)), (max(xs), max(ys)), (min(xs), max(ys))]
        prims.append((depth, box, GATE_FILL, "gate"))

    # Painter's algorithm: furthest first, so what is in front covers what is behind -- which is
    # the whole question this row asks about the wall.
    prims.sort(key=lambda t: -t[0])
    for _, poly, fill, _kind in prims:
        dr.polygon(poly, fill=fill, outline=(70, 84, 104))

    label = "%s gate  --  eye %s looking at %s  --  SILHOUETTE FROM MEASURED GEOMETRY, NOT A CAPTURE" % (
        which.upper(), eye, at)
    dr.rectangle([0, 0, W, 22], fill=(24, 28, 36))
    dr.text((8, 6), label, fill=(235, 238, 245))

    out = os.path.join(ROOT, "tools", "_33_4_%s.png" % which)
    img.save(out)
    print("wrote %s  (%d primitives)" % (out, len(prims)))


if __name__ == "__main__":
    main()
