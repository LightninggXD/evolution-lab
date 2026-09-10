"""Draw the Vivarium gallery from MEASURED geometry -- a plan of the lawn and a section of one case.

WHY THIS EXISTS. Same reason `render_gate_elevation.py` exists, and the same failure: on 2026-09-10
`screen_capture` stopped answering while closing 24.1. Diagnosed with 33.4's own test --
`RenderStepped` fired **0** times in 2 seconds while `Heartbeat` fired **113**, in Edit and in Play
alike -- so Studio was simulating and not drawing a single frame and the capture had nothing to grab.
Three attempts timed out at 180 s each.

This is NOT a substitute for a capture and must never be called one. It has no lighting, no
materials, no mesh detail and no camera: it is the LAYOUT and the PROPORTIONS, which is what a
photograph from above would have been read for here -- do the sixty cases fit the two measured
rectangles, does every one front an aisle, does anything sit in the walking lane, and is a case's
own stack (pad / shelves / lid / board) in the right order at the right heights.

It cannot answer anything about colour, readability at distance, or whether the thing looks good.

INPUT is real: `tools/_viv_anchors.csv`, posted out of the running server by the probe bridge --
every anchor's index, x, z, yaw and bank, as `VivariumPlaza.layOutAnchors` actually produced them.
The case section is drawn from `VivariumCase`'s authored constants, which are the numbers in that
file and not a re-measurement.

    C:\\Python313\\python.exe tools/render_vivarium.py   ->  tools/_viv_layout.png
"""

import csv
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHORS = os.path.join(ROOT, "tools", "_viv_anchors.csv")
OUT = os.path.join(ROOT, "tools", "_viv_layout.png")

# ---- VivariumCase's authored constants, kept in step with that file by hand ----
PAD_W, PAD_D = 9, 8
PAD_TOP = 0.34
WALL_H = 16.4
BACK_T = 0.7
FIN_T = 0.7
ROOF_T = 0.8
SHELF_W, SHELF_T, SHELF_D = 8.0, 0.6, 5.4
SHELF_Y = [3.0, 7.4, 11.8]
SHELF_Z = 0.6
SLOT_X = [-2.1, 2.1]
BOARD_W, BOARD_H = 10.0, 5.0
BOARD_Y = PAD_TOP + WALL_H + ROOF_T + 3.0
# the TALLEST rig, not the Normal-tier one: Golden/Rainbow/Celestial are all 3.50
RIG_W, RIG_H, RIG_D = 2.90, 3.50, 3.28

# ---- the lawn, all measured this session ----
BANKS = [
    ("WEST bank  x -195..-85  z 365..470", -195, -85, 365, 470),
    ("EAST bank  x 70..170  z 370..430", 70, 170, 370, 430),
    ("NORTH bank  x 40..140  z 465..525", 40, 140, 465, 525),
]
UNUSED = ("UNUSED -- biggest rectangle of all, and it straddles the arrival walk", -55, 80, 410, 525)
CORRIDOR_HALF = 30
FURNITURE_HALF = 40
SPAWN = (0, 366)
SPRINT_LANE = (-66, 174, 435)   # x0, x1, z -- SprintTrack v1, 240-stud lane
HERALD = (-106, 502)
PARTY = (-88, 278)

INK = (232, 230, 242)
DIM = (128, 124, 148)
BG = (20, 18, 30)
PANEL = (28, 25, 40)
ACCENT = (146, 116, 240)
WARM = (228, 176, 96)
GREEN = (110, 200, 130)
RED = (226, 98, 98)


def main():
    if not os.path.exists(ANCHORS):
        print("missing %s -- run the probe dump in Play first" % ANCHORS)
        return 1

    anchors = []
    with open(ANCHORS, newline="", encoding="utf-8") as fh:
        for row in csv.reader(fh):
            if len(row) < 5:
                continue
            anchors.append({
                "i": int(row[0]), "x": float(row[1]), "z": float(row[2]),
                "yaw": float(row[3]), "bank": row[4].strip(),
            })
    if not anchors:
        print("no anchors parsed")
        return 1

    W, H = 1480, 1180
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # ================= PLAN =================
    # world x -> px, world z -> py with NORTH UP (z increasing upward)
    px0, py0, px1, py1 = 70, 70, 1410, 740
    wx0, wx1 = -260, 260
    wz0, wz1 = 250, 560
    sx = (px1 - px0) / (wx1 - wx0)
    sz = (py1 - py0) / (wz1 - wz0)

    def P(x, z):
        return (px0 + (x - wx0) * sx, py1 - (z - wz0) * sz)

    d.rectangle([px0 - 12, py0 - 34, px1 + 12, py1 + 34], fill=PANEL)
    d.text((px0, py0 - 30), "PLAN -- the arrival lawn, north up.  60 anchors as measured on the live server.", fill=INK)

    # the walking lane and the furnished band, the two things nothing may enter
    d.rectangle([P(-FURNITURE_HALF, wz1)[0], py0, P(FURNITURE_HALF, wz0)[0], py1], fill=(34, 30, 48))
    d.rectangle([P(-CORRIDOR_HALF, wz1)[0], py0, P(CORRIDOR_HALF, wz0)[0], py1], fill=(46, 38, 62))
    d.text((P(0, wz1 - 8)[0] - 56, py0 + 6), "walking lane", fill=DIM)
    d.text((P(FURNITURE_HALF + 3, wz1 - 26)[0], py0 + 24), "street furniture |x|<40", fill=DIM)

    # the unused rectangle, drawn because the file header promises it is recorded
    ux0, ux1, uz0, uz1 = UNUSED[1], UNUSED[2], UNUSED[3], UNUSED[4]
    a, b = P(ux0, uz1), P(ux1, uz0)
    d.rectangle([a[0], a[1], b[0], b[1]], outline=RED)
    for yy in range(int(a[1]), int(b[1]), 10):
        d.line([a[0], yy, b[0], yy], fill=(70, 34, 40))
    d.text((a[0] + 6, a[1] + 6), "UNUSED 135x115", fill=RED)

    # the two banks
    for label, bx0, bx1, bz0, bz1 in BANKS:
        a, b = P(bx0, bz1), P(bx1, bz0)
        d.rectangle([a[0], a[1], b[0], b[1]], outline=GREEN)
        d.text((a[0] + 4, a[1] - 16), label, fill=GREEN)

    # SprintTrack's lane -- the thing that blocked nine anchors
    a, b = P(SPRINT_LANE[0], SPRINT_LANE[2] + 3), P(SPRINT_LANE[1], SPRINT_LANE[2] - 3)
    d.rectangle([a[0], a[1], b[0], b[1]], fill=(92, 74, 40), outline=WARM)
    d.text((b[0] + 8, (a[1] + b[1]) / 2 - 7), "SprintTrack lane z 435", fill=WARM)

    # the cases
    for an in anchors:
        a = P(an["x"] - PAD_W / 2, an["z"] + PAD_D / 2)
        b = P(an["x"] + PAD_W / 2, an["z"] - PAD_D / 2)
        d.rectangle([a[0], a[1], b[0], b[1]], fill=(58, 50, 86), outline=ACCENT)
        # the open front, as a bright edge: facing 0 means the front is -Z (toward the spawn)
        front_z = an["z"] - PAD_D / 2 if abs(an["yaw"]) < 90 else an["z"] + PAD_D / 2
        fa = P(an["x"] - PAD_W / 2, front_z)
        fb = P(an["x"] + PAD_W / 2, front_z)
        d.line([fa[0], fa[1], fb[0], fb[1]], fill=(255, 232, 150), width=3)

    # the spawn and the two authored neighbours
    for (nx, nz), label, col in (
        (SPAWN, "ForestSpawn", (255, 236, 160)),
        (HERALD, "HeraldStation", DIM),
        (PARTY, "PartyStand", DIM),
    ):
        p = P(nx, nz)
        d.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], fill=col)
        d.text((p[0] + 10, p[1] - 7), label, fill=col)

    # axes
    for x in range(-250, 251, 50):
        p = P(x, wz0)
        d.line([p[0], py1, p[0], py1 + 6], fill=DIM)
        d.text((p[0] - 12, py1 + 10), str(x), fill=DIM)
    for z in range(250, 561, 50):
        p = P(wx0, z)
        d.line([px0 - 6, p[1], px0, p[1]], fill=DIM)
        d.text((px0 - 44, p[1] - 7), str(z), fill=DIM)
    d.text((px1 - 40, py1 + 10), "x", fill=DIM)
    d.text((px0 - 44, py0 - 4), "z", fill=DIM)

    # ================= SECTION =================
    qx0, qy0 = 90, 840
    scale = 10.0   # px per stud -- the stack is 23 studs to the top of the board, so this is
                   # the largest scale that keeps the whole section inside its own panel
    ground_y = qy0 + 250

    d.rectangle([qx0 - 20, qy0 - 36, qx0 + 560, ground_y + 60], fill=PANEL)
    d.text((qx0 - 10, qy0 - 32), "SECTION -- one case, looking along the row.  Front (open) is to the LEFT.", fill=INK)

    def S(zz, yy):
        # z across the page, y up
        return (qx0 + 150 + zz * scale, ground_y - yy * scale)

    d.line([qx0 - 10, ground_y, qx0 + 540, ground_y], fill=(70, 64, 90), width=2)
    d.text((qx0 - 10, ground_y + 8), "lawn y=0", fill=DIM)

    def box(z_c, y_c, dz, dy, col, label=None, lab_col=None):
        a = S(z_c - dz / 2, y_c + dy / 2)
        b = S(z_c + dz / 2, y_c - dy / 2)
        d.rectangle([a[0], a[1], b[0], b[1]], fill=col, outline=(18, 14, 28))
        if label:
            d.text((b[0] + 8, (a[1] + b[1]) / 2 - 7), label, fill=lab_col or DIM)

    # pad (stated by its top, grown down)
    box(0, PAD_TOP - (PAD_TOP + 1.2) / 2, PAD_D, PAD_TOP + 1.2, (150, 126, 96), "pad, top %.2f" % PAD_TOP, WARM)
    # sill at the open front
    box(-(PAD_D / 2 - 0.4), PAD_TOP + 0.25, 0.8, 0.5, (40, 34, 58))
    # back wall
    box(PAD_D / 2 - BACK_T / 2, PAD_TOP + WALL_H / 2, BACK_T, WALL_H, (48, 40, 72), "back wall %.0f tall" % WALL_H)
    # roof
    box(0.4, PAD_TOP + WALL_H + ROOF_T / 2, PAD_D + 1.2, ROOF_T, (40, 34, 58), "lid", WARM)
    # shelves, glow strips and the rigs standing on them
    for i, sy in enumerate(SHELF_Y):
        box(SHELF_Z, PAD_TOP + sy, SHELF_D, SHELF_T, (104, 76, 52))
        box(SHELF_Z - SHELF_D / 2, PAD_TOP + sy - SHELF_T / 2 - 0.11, 0.3, 0.22, ACCENT)
        top = PAD_TOP + sy + SHELF_T / 2
        box(SHELF_Z, top + RIG_H / 2, RIG_D, RIG_H, (92, 150, 210),
            "shelf %d top %.2f, rig foot %.2f" % (i + 1, top, top), GREEN)
    # the board, hanging on nothing
    a = S(-BOARD_W / 2 * 0.0 - 3.0, BOARD_Y + BOARD_H / 2)
    b = S(3.0, BOARD_Y - BOARD_H / 2)
    d.rectangle([a[0], a[1], b[0], b[1]], fill=(30, 27, 44), outline=ACCENT)
    d.text((b[0] + 8, (a[1] + b[1]) / 2 - 7), "board %.0fx%.0f studs, y %.2f -- nothing behind it" % (BOARD_W, BOARD_H, BOARD_Y), fill=ACCENT)

    # ================= FACTS =================
    fx = 720
    d.rectangle([fx - 20, qy0 - 36, 1410, ground_y + 60], fill=PANEL)
    lines = [
        ("MEASURED LIVE, 39th session", INK),
        ("", INK),
        ("anchors                  60 of a possible 60", GREEN),
        ("case                     9 x 8, three shelves of two", INK),
        ("west / east / north      %d / %d / %d" % (
            sum(1 for a in anchors if a["bank"] == "West"),
            sum(1 for a in anchors if a["bank"] == "East"),
            sum(1 for a in anchors if a["bank"] == "North")), INK),
        ("footprint                x %.0f..%.0f   z %.0f..%.0f" % (
            min(a["x"] for a in anchors) - PAD_W / 2, max(a["x"] for a in anchors) + PAD_W / 2,
            min(a["z"] for a in anchors) - PAD_D / 2, max(a["z"] for a in anchors) + PAD_D / 2), INK),
        ("overlapping pad pairs     0", GREEN),
        ("nearest to walking lane  |x| = %.0f   (limit 30)" % min(abs(a["x"]) - PAD_W / 2 for a in anchors), GREEN),
        ("facings                  %d at 0 deg, %d at 180" % (
            sum(1 for a in anchors if abs(a["yaw"]) < 90),
            sum(1 for a in anchors if abs(a["yaw"]) >= 90)), INK),
        ("", INK),
        ("slots                    2 + rebirths//4, capped 6", INK),
        ("   R0->2  R4->3  R8->4  R12->5  R16->6", DIM),
        ("", INK),
        ("cases on the sprint lane  0   (was 7 before RESERVED)", GREEN),
        ("worst rig headroom       +0.30 over every tier", GREEN),
        ("a claimed case           R9 -> 4 slots, 4 rigs", INK),
        ("rig feet vs shelf tops   exact on all three shelves", GREEN),
        ('board                    "no passive income yet"', WARM),
        ("                         AutoCollect is 0 on that save", DIM),
        ("", INK),
        ("NOT A CAPTURE.  screen_capture timed out 3x:", RED),
        ("RenderStepped 0 in 2s vs Heartbeat 113 --", RED),
        ("Studio is simulating and drawing nothing.", RED),
        ("No claim here about colour or how it looks.", RED),
    ]
    yy = qy0 - 6
    for text, col in lines:
        d.text((fx, yy), text, fill=col)
        yy += 21

    img.save(OUT)
    print("wrote %s  (%d anchors)" % (OUT, len(anchors)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
