"""
make_icons.py -- draws Evolution Lab's UI icon set as PNGs, in the house style.

WHY THIS EXISTS RATHER THAN A FOLDER OF HAND-DRAWN FILES
--------------------------------------------------------
The HUD had no asset layer at all: every icon in the game was an emoji in a TextLabel. That is
not a style choice, it is a different picture on every platform -- Windows, Android and console
each ship their own emoji font, so the same tile renders three different ways and none of them
shares the thick dark outline and flat pastel fill that everything else in this game is built
from. An icon that is generated is an icon that can be REGENERATED: change OUTLINE or a palette
entry here and all forty move together, which is the same argument the UITheme module itself
makes about buttons.

HOW THE OUTLINE IS MADE, AND WHY NOT WITH `outline=`
-----------------------------------------------------
Pillow can stroke each shape (`outline=INK, width=N`), but an icon built from four overlapping
circles then shows four internal rings -- the outline of every shape, not the outline of the
icon. The house rule is one silhouette (see the chunky-look notes): draw every shape with NO
stroke, take the alpha of the whole layer, DILATE it, and use that as an ink layer underneath.
The result is one uniform contour around whatever the shapes happen to add up to, and internal
detail is then drawn deliberately in INK rather than appearing by accident.

Everything is authored in a 0..100 space and rendered supersampled (SS), because a dilation on a
hard-edged mask is what produces the aliasing this style shows most.
"""

import json
import math
import os

from PIL import Image, ImageChops, ImageDraw

# ---------------------------------------------------------------- render setup

SIZE = 256          # final PNG edge. HUD icons draw at ~40-60px, so this is ~5x headroom.
SS = 3              # supersample factor; the dilated mask is what needs it
W = SIZE * SS
OUTLINE = 3.6       # contour thickness, in 0..100 units
PAD = 7.0           # margin the 0..100 box is inset by, so the contour is never cropped
DILATE_SAMPLES = 96  # see `dilate`

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")

# ---------------------------------------------------------------- palette
# Lifted from UITheme.Color so an icon and the tile under it are the same design system. Any
# change there has to be mirrored here -- that is the one duplication in this file, and it is
# cheaper than teaching Lua to draw PNGs.

INK        = (26, 18, 36, 255)
WHITE      = (255, 255, 255, 255)
CREAM      = (255, 248, 235, 255)
GOLD       = (255, 205, 70, 255)
GOLD_D     = (222, 158, 30, 255)
ORANGE     = (247, 150, 35, 255)
BLUE       = (74, 164, 224, 255)
SKY        = (120, 205, 245, 255)
GREEN      = (95, 205, 105, 255)
GREEN_D    = (58, 158, 72, 255)
RED        = (232, 72, 72, 255)
PURPLE     = (170, 110, 240, 255)
PURPLE_D   = (126, 74, 190, 255)
PINK       = (255, 110, 200, 255)
GREY       = (150, 150, 165, 255)
MINT       = (124, 226, 142, 255)
SUNNY      = (255, 214, 92, 255)
BUBBLEGUM  = (255, 138, 205, 255)
LAVENDER   = (186, 146, 250, 255)
AQUA       = (114, 202, 245, 255)
PEACH      = (255, 168, 104, 255)
CORAL      = (255, 124, 124, 255)
BROWN      = (150, 96, 60, 255)
STEEL      = (206, 214, 232, 255)


# ---------------------------------------------------------------- primitives
# Each returns nothing and draws into the colour layer. The silhouette is derived afterwards, so
# nothing here ever asks for a stroke.

PAD_PX = PAD * W / 100.0
SPAN = W - 2 * PAD_PX


class Pen:
    def __init__(self, draw):
        self.d = draw

    def _s(self, v):
        # 0..100 maps into the canvas INSET by PAD on every side. Two things depend on that
        # margin: the dilated contour has somewhere to grow into, and `dilate` can use a wrapping
        # offset without an icon that touches its box bleeding round to the opposite edge.
        return PAD_PX + v * SPAN / 100.0

    def _l(self, v):
        # A LENGTH, not a position -- stroke widths and corner radii must not pick up the margin
        # that `_s` adds, or a 9-unit line comes out as wide as the padding plus nine.
        return v * SPAN / 100.0

    def _pts(self, pts):
        return [(self._s(x), self._s(y)) for x, y in pts]

    def poly(self, pts, color):
        self.d.polygon(self._pts(pts), fill=color)

    def ellipse(self, cx, cy, rx, ry, color):
        self.d.ellipse(
            [self._s(cx - rx), self._s(cy - ry), self._s(cx + rx), self._s(cy + ry)], fill=color
        )

    def circle(self, cx, cy, r, color):
        self.ellipse(cx, cy, r, r, color)

    def rrect(self, x0, y0, x1, y1, r, color):
        self.d.rounded_rectangle(
            [self._s(x0), self._s(y0), self._s(x1), self._s(y1)], radius=self._l(r), fill=color
        )

    def line(self, pts, width, color):
        p = self._pts(pts)
        self.d.line(p, fill=color, width=int(self._l(width)), joint="curve")
        # PIL leaves square butt-ends on a thick line; a round cap at each vertex is what keeps a
        # stroke reading as one drawn mark rather than as a chain of rectangles
        r = self._l(width) / 2.0
        for x, y in p:
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=color)

    def arc(self, cx, cy, rx, ry, start, end, width, color):
        self.d.arc(
            [self._s(cx - rx), self._s(cy - ry), self._s(cx + rx), self._s(cy + ry)],
            start, end, fill=color, width=int(self._l(width)),
        )
        # same cap treatment as `line`, at the two ends of the sweep
        r = self._l(width) / 2.0
        for a in (start, end):
            ax = self._s(cx + rx * math.cos(math.radians(a)))
            ay = self._s(cy + ry * math.sin(math.radians(a)))
            self.d.ellipse([ax - r, ay - r, ax + r, ay + r], fill=color)

    def star(self, cx, cy, outer, inner, points, color, rot=-90):
        pts = []
        for i in range(points * 2):
            r = outer if i % 2 == 0 else inner
            a = math.radians(rot + i * 180.0 / points)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.poly(pts, color)


# ---------------------------------------------------------------- the icons
# One function each, all drawing into a 0..100 box. Kept deliberately blunt: three or four big
# shapes beat a faithful miniature, because these are read at 40 pixels.

ICONS = {}


def icon(name):
    def wrap(fn):
        ICONS[name] = fn
        return fn
    return wrap


@icon("dna")
def _dna(p):
    # two strands crossing four times, with rungs between them. Drawn as sampled sine paths --
    # the crossing is the whole read of this shape, so both strands run the full height.
    top, bot = 12, 88
    for phase, col in ((0.0, SKY), (math.pi, PINK)):
        pts = []
        for i in range(25):
            t = i / 24.0
            y = top + (bot - top) * t
            x = 50 + 26 * math.sin(t * math.pi * 2 + phase)
            pts.append((x, y))
        p.line(pts, 9, col)
    for i in range(3):
        t = 0.22 + i * 0.28
        y = top + (bot - top) * t
        x1 = 50 + 26 * math.sin(t * math.pi * 2)
        x2 = 50 + 26 * math.sin(t * math.pi * 2 + math.pi)
        p.line([(x1, y), (x2, y)], 6, CREAM)


@icon("diamond")
def _diamond(p):
    body = [(28, 22), (72, 22), (90, 44), (50, 88), (10, 44)]
    p.poly(body, AQUA)
    # the crown facets. Without them this is a blue pentagon; with them it is cut glass.
    p.poly([(28, 22), (72, 22), (64, 44), (36, 44)], SKY)
    p.poly([(10, 44), (36, 44), (50, 88)], (150, 220, 250, 255))
    for a, b in (((28, 22), (36, 44)), ((72, 22), (64, 44)), ((10, 44), (90, 44)),
                 ((36, 44), (50, 88)), ((64, 44), (50, 88))):
        p.line([a, b], 2.4, INK)


@icon("shard")
def _shard(p):
    # a four-point sparkle, not a five-point star: it has to be distinguishable from `xp` at a
    # glance, and the two sit next to each other on the Daily panel
    p.star(50, 50, 44, 13, 4, GOLD, rot=-90)
    p.star(50, 50, 20, 7, 4, CREAM, rot=-90)


@icon("xp")
def _xp(p):
    p.star(50, 52, 42, 18, 5, SUNNY, rot=-90)
    p.star(50, 52, 19, 8, 5, CREAM, rot=-90)


@icon("luck")
def _luck(p):
    # EACH LEAF CARRIES ITS OWN INK RING. The silhouette pass draws the OUTER contour only, so
    # four touching circles come out as one green blob -- the internal edges have to be drawn on
    # purpose. Same treatment as `paw`, and the reason both were unreadable in the first pass.
    p.line([(52, 52), (60, 88)], 6, GREEN_D)
    for cx, cy in ((36, 38), (64, 38), (36, 64), (64, 64)):
        p.circle(cx, cy, 20, INK)
        p.circle(cx, cy, 17.5, GREEN)


@icon("sword")
def _sword(p):
    p.poly([(50, 8), (61, 22), (61, 62), (39, 62), (39, 22)], STEEL)
    p.poly([(50, 8), (56, 20), (50, 24), (44, 20)], WHITE)
    p.rrect(24, 62, 76, 72, 4, GOLD)
    p.rrect(44, 72, 56, 88, 4, BROWN)
    p.circle(50, 90, 7, GOLD)


@icon("paw")
def _paw(p):
    # ink ring per pad, for the reason written on `luck`
    p.ellipse(50, 68, 27, 22, INK)
    p.ellipse(50, 68, 24, 19, BUBBLEGUM)
    for cx, cy in ((24, 41), (42, 26), (62, 26), (80, 41)):
        p.ellipse(cx, cy, 13, 15, INK)
        p.ellipse(cx, cy, 10.5, 12.5, PINK)


@icon("potion")
def _potion(p):
    p.poly([(38, 14), (62, 14), (62, 40), (84, 84), (16, 84), (38, 40)], STEEL)
    # the liquid, sitting only in the wide part -- a flask filled to the neck reads as a solid block
    p.poly([(45, 52), (55, 52), (78, 84), (22, 84)], PURPLE)
    p.rrect(34, 8, 66, 18, 4, CREAM)
    p.circle(42, 72, 5, LAVENDER)
    p.circle(58, 66, 3.5, LAVENDER)


@icon("egg")
def _egg(p):
    p.ellipse(50, 56, 30, 38, CREAM)
    p.circle(40, 46, 7, AQUA)
    p.circle(60, 64, 9, PINK)
    p.circle(58, 38, 5, SUNNY)


@icon("crown")
def _crown(p):
    p.poly([(12, 76), (12, 34), (30, 52), (50, 22), (70, 52), (88, 34), (88, 76)], GOLD)
    p.rrect(12, 72, 88, 88, 4, GOLD_D)
    for cx in (30, 50, 70):
        p.circle(cx, 80, 5, CORAL)


@icon("lock")
def _lock(p):
    p.arc(50, 44, 20, 20, 180, 360, 9, GREY)
    p.rrect(22, 42, 78, 88, 10, SUNNY)
    p.circle(50, 60, 8, INK)
    p.poly([(46, 60), (54, 60), (52, 78), (48, 78)], INK)


@icon("check")
def _check(p):
    p.circle(50, 50, 42, GREEN)
    p.line([(28, 52), (44, 68), (74, 33)], 11, WHITE)


@icon("cross")
def _cross(p):
    p.circle(50, 50, 42, RED)
    p.line([(32, 32), (68, 68)], 11, WHITE)
    p.line([(68, 32), (32, 68)], 11, WHITE)


@icon("fire")
def _fire(p):
    p.poly([(50, 6), (74, 36), (80, 60), (68, 84), (50, 94), (32, 84), (20, 60), (30, 34)], ORANGE)
    p.poly([(50, 34), (66, 58), (62, 80), (50, 90), (38, 80), (34, 58)], SUNNY)
    p.poly([(50, 58), (58, 74), (50, 88), (42, 74)], CREAM)


@icon("clock")
def _clock(p):
    p.circle(28, 22, 12, GREY)
    p.circle(72, 22, 12, GREY)
    p.circle(50, 56, 38, CREAM)
    p.circle(50, 56, 30, WHITE)
    p.line([(50, 56), (50, 34)], 6, INK)
    p.line([(50, 56), (66, 62)], 6, INK)
    p.circle(50, 56, 5, INK)


@icon("wheel")
def _wheel(p):
    cols = (CORAL, SUNNY, MINT, AQUA, LAVENDER, PEACH, BUBBLEGUM, GREEN)
    for i, col in enumerate(cols):
        a0, a1 = i * 45 - 90, (i + 1) * 45 - 90
        pts = [(50, 54)]
        for k in range(9):
            a = math.radians(a0 + (a1 - a0) * k / 8.0)
            pts.append((50 + 40 * math.cos(a), 54 + 40 * math.sin(a)))
        p.poly(pts, col)
    p.circle(50, 54, 10, CREAM)
    p.poly([(50, 4), (58, 18), (42, 18)], INK)


@icon("upgrade")
def _upgrade(p):
    p.poly([(50, 8), (86, 46), (66, 46), (66, 90), (34, 90), (34, 46), (14, 46)], MINT)
    p.poly([(50, 20), (70, 42), (58, 42), (58, 60), (42, 60), (42, 42), (30, 42)], CREAM)


@icon("arrow")
def _arrow(p):
    p.poly([(92, 50), (54, 88), (54, 66), (8, 66), (8, 34), (54, 34), (54, 12)], SUNNY)


@icon("question")
def _question(p):
    p.circle(50, 50, 42, LAVENDER)
    # ONE SAMPLED PATH, not an arc plus a stem. The first version glued a PIL arc to a straight
    # segment and the join read as an upside-down mark, because an arc's own end is square to the
    # radius and the stem met it at a corner. Walking the hook round and letting the tail continue
    # from wherever it ends keeps it a single stroke, which is what a "?" is.
    pts = []
    for i in range(17):
        a = math.radians(190 + i * (170.0 / 16))
        pts.append((50 + 16 * math.cos(a), 40 + 16 * math.sin(a)))
    pts += [(65, 45), (58, 53), (50, 60)]
    p.line(pts, 9, WHITE)
    p.circle(50, 78, 6.5, WHITE)


@icon("boom")
def _boom(p):
    p.star(50, 50, 46, 20, 9, CORAL, rot=-90)
    p.star(50, 50, 27, 12, 9, SUNNY, rot=-70)


@icon("coin")
def _coin(p):
    # two overlapping faces rather than a stack of flat ellipses: edge-on discs read as a smear at
    # 40px, where one coin half behind another reads as "more than one" immediately
    p.circle(68, 62, 25, INK)
    p.circle(68, 62, 22, GOLD_D)
    p.circle(42, 46, 31, INK)
    p.circle(42, 46, 28, GOLD)
    p.circle(42, 46, 20, GOLD_D)
    p.star(42, 46, 13, 5.5, 4, CREAM, rot=-90)


@icon("gear")
def _gear(p):
    for i in range(8):
        a = math.radians(i * 45)
        ca, sa = math.cos(a), math.sin(a)
        # each tooth is a quad built in the cog's own frame, so they stay square to the radius
        def rot(dx, dy):
            return (50 + dx * ca - dy * sa, 50 + dx * sa + dy * ca)
        p.poly([rot(26, -11), rot(45, -8), rot(45, 8), rot(26, 11)], GREY)
    p.circle(50, 50, 30, STEEL)
    p.circle(50, 50, 13, INK)


@icon("bolt")
def _bolt(p):
    p.poly([(58, 6), (24, 54), (44, 54), (36, 94), (76, 42), (52, 42), (64, 6)], SUNNY)


@icon("ticket")
def _ticket(p):
    # TWO STUBS WITH A GAP, not one rectangle with holes punched in it. A transparent fill does
    # not erase here -- the ink layer underneath simply shows through the hole -- so the pinched
    # waist that says "ticket" has to be built out of what IS drawn.
    p.rrect(8, 26, 46, 74, 8, CORAL)
    p.rrect(54, 26, 92, 74, 8, CORAL)
    p.poly([(46, 34), (54, 34), (54, 66), (46, 66)], CORAL)
    p.rrect(14, 34, 40, 66, 5, CREAM)
    for y in (40, 50, 60):
        p.line([(60, y), (86, y)], 4, CREAM)


@icon("gift")
def _gift(p):
    p.rrect(16, 40, 84, 90, 6, CORAL)
    p.rrect(10, 26, 90, 44, 5, RED)
    p.rrect(43, 26, 57, 90, 3, SUNNY)
    p.circle(37, 20, 12, SUNNY)
    p.circle(63, 20, 12, SUNNY)
    p.circle(50, 22, 7, GOLD)


@icon("cart")
def _cart(p):
    p.line([(8, 18), (24, 18)], 7, BROWN)
    p.poly([(22, 28), (90, 28), (80, 66), (34, 66)], SUNNY)
    p.line([(24, 18), (34, 66)], 7, BROWN)
    p.circle(40, 82, 9, INK)
    p.circle(74, 82, 9, INK)


@icon("bag")
def _bag(p):
    p.arc(50, 40, 20, 22, 180, 360, 8, BROWN)
    p.poly([(16, 34), (84, 34), (90, 92), (10, 92)], MINT)
    p.rrect(38, 52, 62, 62, 4, CREAM)


@icon("book")
def _book(p):
    p.rrect(14, 12, 86, 90, 7, PURPLE)
    p.rrect(26, 12, 86, 90, 7, CREAM)
    p.rrect(14, 12, 30, 90, 5, PURPLE_D)
    for y in (34, 48, 62):
        p.line([(40, y), (74, y)], 4.5, GREY)
    p.poly([(62, 12), (78, 12), (78, 42), (70, 34), (62, 42)], CORAL)


@icon("map")
def _map(p):
    p.poly([(8, 22), (36, 12), (64, 24), (92, 12), (92, 82), (64, 92), (36, 80), (8, 90)], MINT)
    p.line([(36, 12), (36, 80)], 3, GREEN_D)
    p.line([(64, 24), (64, 92)], 3, GREEN_D)
    p.line([(20, 66), (40, 46), (58, 60), (80, 34)], 4.5, CORAL)


@icon("rebirth")
def _rebirth(p):
    # a ring with a bite out of it and an arrowhead on the open end: three curved arrows chasing
    # each other is unreadable at 40px, one is not
    # The gap sits at the TOP, where a refresh mark is read, and the ring is left hollow -- a
    # cream disc in the middle picks up its own contour from the dilation and reads as a punched
    # hole rather than as a hub.
    p.arc(50, 50, 31, 31, 305, 580, 12, MINT)
    # the head is placed and aimed off the sweep's own end rather than typed in as three points,
    # so moving the gap cannot leave the arrow pointing at nothing
    a = math.radians(580)
    cx, cy = 50 + 31 * math.cos(a), 50 + 31 * math.sin(a)
    tx, ty = -math.sin(a), math.cos(a)   # tangent, in the direction the sweep is going
    nx, ny = math.cos(a), math.sin(a)    # radial
    p.poly([
        (cx + tx * 17, cy + ty * 17),
        (cx + nx * 12, cy + ny * 12),
        (cx - nx * 12, cy - ny * 12),
    ], GREEN)


@icon("backpack")
def _backpack(p):
    p.arc(50, 34, 20, 20, 180, 360, 8, PURPLE_D)
    p.rrect(16, 30, 84, 92, 14, LAVENDER)
    p.rrect(28, 56, 72, 82, 8, CREAM)
    p.rrect(44, 62, 56, 70, 3, PURPLE_D)


@icon("audio")
def _audio(p):
    p.poly([(12, 38), (32, 38), (54, 16), (54, 84), (32, 62), (12, 62)], AQUA)
    p.arc(54, 50, 20, 22, -60, 60, 6, CREAM)
    p.arc(54, 50, 32, 34, -60, 60, 6, CREAM)


@icon("medal")
def _medal(p):
    p.poly([(28, 8), (46, 8), (56, 44), (38, 44)], CORAL)
    p.poly([(54, 8), (72, 8), (62, 44), (44, 44)], SKY)
    p.circle(50, 64, 28, GOLD)
    p.circle(50, 64, 20, GOLD_D)
    p.star(50, 64, 14, 6, 5, CREAM, rot=-90)


@icon("rainbow")
def _rainbow(p):
    for i, col in enumerate((CORAL, ORANGE, SUNNY, MINT, AQUA, LAVENDER)):
        r = 44 - i * 7
        p.arc(50, 78, r, r, 180, 360, 7, col)


@icon("sun")
def _sun(p):
    for i in range(8):
        a = math.radians(i * 45)
        ca, sa = math.cos(a), math.sin(a)
        def rot(dx, dy):
            return (50 + dx * ca - dy * sa, 50 + dx * sa + dy * ca)
        p.poly([rot(28, -8), rot(46, 0), rot(28, 8)], GOLD)
    p.circle(50, 50, 28, SUNNY)


@icon("calendar")
def _calendar(p):
    p.rrect(10, 20, 90, 92, 9, CREAM)
    p.rrect(10, 20, 90, 42, 9, CORAL)
    p.rrect(24, 8, 32, 30, 4, GREY)
    p.rrect(68, 8, 76, 30, 4, GREY)
    for r in range(2):
        for c in range(4):
            p.rrect(20 + c * 17, 52 + r * 17, 32 + c * 17, 64 + r * 17, 3, SKY)


@icon("party")
def _party(p):
    p.poly([(16, 90), (56, 22), (76, 44)], CORAL)
    p.poly([(16, 90), (40, 58), (52, 70)], SUNNY)
    for cx, cy, col in ((78, 16, MINT), (90, 40, AQUA), (66, 8, BUBBLEGUM), (88, 66, SUNNY)):
        p.circle(cx, cy, 6, col)


@icon("hourglass")
def _hourglass(p):
    p.rrect(18, 8, 82, 20, 4, BROWN)
    p.rrect(18, 80, 82, 92, 4, BROWN)
    p.poly([(26, 20), (74, 20), (54, 50), (74, 80), (26, 80), (46, 50)], STEEL)
    p.poly([(34, 26), (66, 26), (50, 48)], SUNNY)
    p.poly([(50, 52), (68, 74), (32, 74)], SUNNY)


@icon("boss")
def _boss(p):
    p.poly([(16, 40), (10, 10), (34, 26)], CORAL)
    p.poly([(84, 40), (90, 10), (66, 26)], CORAL)
    p.rrect(16, 26, 84, 82, 20, RED)
    p.circle(36, 50, 9, CREAM)
    p.circle(64, 50, 9, CREAM)
    p.circle(36, 50, 4.5, INK)
    p.circle(64, 50, 4.5, INK)
    p.poly([(32, 66), (68, 66), (62, 78), (38, 78)], INK)
    for x in (40, 50, 60):
        p.poly([(x - 5, 66), (x + 5, 66), (x, 72)], CREAM)


@icon("heart")
def _heart(p):
    p.circle(34, 38, 20, CORAL)
    p.circle(66, 38, 20, CORAL)
    p.poly([(15, 44), (85, 44), (50, 90)], CORAL)
    p.circle(38, 32, 7, (255, 190, 190, 255))


@icon("plus")
def _plus(p):
    p.circle(50, 50, 42, GREEN)
    p.line([(50, 28), (50, 72)], 12, WHITE)
    p.line([(28, 50), (72, 50)], 12, WHITE)


@icon("shop")
def _shop(p):
    p.poly([(8, 34), (92, 34), (84, 46), (16, 46)], CORAL)
    p.rrect(14, 44, 86, 92, 6, SUNNY)
    p.rrect(36, 62, 64, 92, 5, BROWN)
    p.rrect(8, 26, 92, 36, 4, CREAM)


@icon("zone")
def _zone(p):
    p.poly([(6, 84), (34, 40), (54, 68), (68, 50), (94, 84)], GREEN)
    p.poly([(34, 40), (46, 58), (22, 58)], CREAM)
    p.circle(74, 26, 13, SUNNY)


@icon("pet")
def _pet(p):
    p.ellipse(50, 62, 30, 26, PEACH)
    p.poly([(24, 44), (20, 16), (44, 32)], PEACH)
    p.poly([(76, 44), (80, 16), (56, 32)], PEACH)
    p.circle(38, 58, 6, INK)
    p.circle(62, 58, 6, INK)
    p.ellipse(50, 72, 7, 5, CORAL)


# ---------------------------------------------------------------- render

def dilate(mask, radius):
    """Grow an alpha mask by `radius`, as the union of the mask shifted onto a ring of offsets.

    `ImageFilter.MaxFilter` is the obvious call and is unusable here: at this supersample the
    kernel is ~75x75 and one icon took minutes. Dilation by a disc is the union of every
    translation by a point of that disc, and for a filled shape the ring alone reaches the same
    outer contour (the untranslated mask fills the middle), so this is ~96 cheap whole-image
    `lighter` passes instead of a per-pixel window -- a couple of hundred milliseconds an icon.
    """
    out = mask
    for i in range(DILATE_SAMPLES):
        a = 2 * math.pi * i / DILATE_SAMPLES
        out = ImageChops.lighter(
            out,
            ImageChops.offset(mask, int(round(radius * math.cos(a))), int(round(radius * math.sin(a)))),
        )
    return out


def render(name, fn):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    fn(Pen(ImageDraw.Draw(layer)))

    # THE SILHOUETTE. Dilating the alpha of the finished colour layer is what gives one contour
    # around the whole icon instead of one around each shape -- see the file header.
    mask = dilate(layer.split()[3], int(round(OUTLINE * SPAN / 100.0)))
    ink = Image.new("RGBA", (W, W), INK)
    ink.putalpha(mask)

    return Image.alpha_composite(ink, layer).resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for name in sorted(ICONS):
        img = render(name, ICONS[name])
        path = os.path.abspath(os.path.join(OUT_DIR, name + ".png"))
        img.save(path, optimize=True)
        written.append((name, path, os.path.getsize(path)))

    print("%d icons -> %s" % (len(written), os.path.abspath(OUT_DIR)))
    for n, p, s in written:
        print("  %-10s %6d bytes" % (n, s))
    manifest = os.path.abspath(os.path.join(OUT_DIR, "icons.json"))
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump([n for n, _, _ in written], f, indent=1)
    print("manifest:", manifest)


if __name__ == "__main__":
    main()
