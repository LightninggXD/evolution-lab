"""
set_place.py -- where the player goes and what tells them the time.

Icon bodies. Each draws into a 0..100 box with the shared `Pen`; the lighting, the contour and the
gloss are added afterwards by `iconkit.render` and must NOT be drawn here -- see iconkit's header.

THE ONE RULE: never ask a primitive for a stroke. The silhouette is derived from the finished
colour layer, so a stroke here becomes an internal ring around every shape instead of one contour
around the icon. Deliberate internal linework goes through `p.inkline`.

WHY THIS SET IS DRAWN AS DIORAMAS
----------------------------------
"Containers and places" is the set most at risk of turning into a settings menu: a bag, a book, a
calendar and a clock are all things the flat-icon world has already agreed on a glyph for, and
copying those glyphs would put a stock pictogram next to Evolution Lab's painted toys. So every
body here is built as a small object with structure rather than as a symbol: the shop is a stall
you could walk up to, the zone is a piece of landscape, the hourglass has wood on it. The rule of
thumb used throughout was "would this survive being cast in vinyl" -- if a shape only exists as a
line, it got thickness; if a surface was blank, it got a seam through `p.inkline`.
"""

from iconkit import (  # noqa: F401  -- the palette is a namespace, not a checklist
    icon, Pen,
    INK, WHITE, CREAM, GOLD, GOLD_D, ORANGE, BLUE, SKY, GREEN, GREEN_D, RED, PURPLE, PURPLE_D,
    PINK, GREY, MINT, SUNNY, BUBBLEGUM, LAVENDER, AQUA, PEACH, CORAL, BROWN, BROWN_D, STEEL,
    STEEL_D, TEAL, PLUM, shade,
)

import math  # noqa: F401


def _rot(pts, cx, cy, deg):
    """The same rotation `Pen.rot_poly` does, but returning points instead of drawing them.

    Tilt is most of what stops a rectangular object reading as a diagram, and the book below is
    tilted -- but a tilted book still needs its spine seam, its page edges and its ribbon to be
    tilted by the SAME angle, and those go through `inkline` and `line`, which have no rotation of
    their own. Rotating the points here keeps one angle for the whole object; the alternative,
    which was tried first, was hand-computing each rotated endpoint and it drifted by a degree or
    two per shape, which reads as a badly glued model rather than as a tilt.
    """
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


# A market stall rather than a storefront. A shop drawn as a building is a box with a door, and at
# 40px a box with a door is indistinguishable from the `home` glyph everyone has already seen; a
# stall has an awning, which is a strong, wide, top-heavy silhouette nothing else in the set owns.
# The awning is built as real segments with scalloped ends instead of a painted-on stripe pattern,
# because the scallops survive the downscale as a visibly wavy edge even when the stripes blur into
# each other. The goods on the counter are the storytelling prop: three fat fruit in three different
# hues say "things are for sale here" faster than any sign would.
@icon("shop")
def _shop(p):
    p.capsule(13, 40, 13, 70, 5.5, BROWN_D)
    p.capsule(87, 40, 87, 70, 5.5, BROWN_D)
    p.rrect(18, 32, 82, 88, 5, CREAM)
    p.inkline([(22, 50), (78, 50)], 3.0)

    p.rrect(8, 62, 92, 78, 4, BROWN)
    p.rrect(8, 72, 92, 90, 3, BROWN_D)
    p.inkline([(10, 72), (90, 72)], 3.2)
    for x in (30, 50, 70):
        p.inkline([(x, 75), (x, 88)], 2.8)

    p.circle(28, 55, 9.5, RED)
    p.sheen(25, 51, 3.4, 2.2)
    p.circle(47, 57, 7.5, GREEN)
    p.circle(65, 55, 9.0, GOLD)
    p.sheen(62, 51, 3.2, 2.0)

    p.poly([(5, 20), (95, 20), (90, 44), (10, 44)], CORAL)
    for i in range(8):
        if i % 2:
            p.poly([(5 + 11.25 * i, 20), (5 + 11.25 * (i + 1), 20),
                    (10 + 10 * (i + 1), 44), (10 + 10 * i, 44)], CREAM)
    for i in range(8):
        p.circle(15 + 10 * i, 44, 5.2, CREAM if i % 2 else CORAL)
    p.rrect(5, 14, 95, 23, 3, BROWN)
    p.inkline([(8, 23), (92, 23)], 2.8)


# The old cart was a trapezoid on two dots. What makes a cart read as a cart at a glance is the
# grid, so the basket is now a real lattice of ink -- four uprights and a rail -- and the rim is a
# separate darker bar so the basket has a lip to hang off. Goods spill over that lip, which is the
# one detail that turns a container into a cart in use. The wheels grew fat hubs; small dark discs
# alone read as feet, and a hub with a highlight reads as a wheel even at 40px.
@icon("cart")
def _cart(p):
    p.capsule(8, 16, 24, 16, 7.0, STEEL_D)
    p.capsule(24, 16, 30, 32, 6.0, STEEL_D)

    p.circle(42, 24, 10.5, CORAL)
    p.sheen(38, 20, 3.6, 2.4)
    p.circle(62, 21, 9.0, MINT)
    p.circle(78, 26, 8.0, LAVENDER)

    p.poly([(26, 34), (94, 34), (84, 70), (38, 70)], SUNNY)
    p.poly([(24, 27), (95, 27), (94, 36), (26, 36)], GOLD_D)
    for t in (0.25, 0.5, 0.75):
        p.inkline([(26 + 68 * t, 37), (38 + 46 * t, 70)], 2.8)
    p.inkline([(32, 53), (89, 53)], 2.8)

    p.capsule(46, 68, 44, 80, 6, STEEL_D)
    p.capsule(76, 68, 78, 80, 6, STEEL_D)
    p.circle(44, 84, 10.5, INK)
    p.circle(44, 84, 4.6, STEEL)
    p.circle(78, 84, 10.5, INK)
    p.circle(78, 84, 4.6, STEEL)


# A loot sack, not a paper carrier. The game's bag holds what you picked up, so it bulges: the body
# is a hexagon widened by an ellipse across its belly, which is the cheapest way to get a fat,
# under-inflated silhouette out of straight-edged primitives. Coins sit BEHIND the body and above
# the cuff so they read as being inside and overflowing -- drawn in front they looked stuck on. The
# vertical ink ticks on the cuff are gathered cloth; they were originally horizontal stitching and
# that read as a zip.
@icon("bag")
def _bag(p):
    # REDRAWN. The first version ran a row of gold coins across the mouth of the bag with a wide
    # pale band under them, and the whole thing read as a CAKE -- or a bed. Two rules came out of
    # it, both general to this file: the handle is the entire silhouette of a bag, so nothing may
    # be drawn in front of it; and a light horizontal band across the top third of any object turns
    # it into furniture.
    #
    # So the handles are two open loops standing clear ABOVE the body with daylight through them,
    # which is a shape nothing else in the set has. The body is a tapered tub, wider at the base,
    # and the only decoration is a vertical seam and a vertical gold tag -- vertical on purpose, to
    # cut the horizontal read rather than add to it. Coins spill over ONE shoulder; spilling them
    # symmetrically just drew a second pair of handles.
    p.poly([(16, 40), (84, 40), (94, 86), (88, 96), (12, 96), (6, 86)], MINT)
    p.poly([(16, 40), (50, 40), (50, 96), (12, 96), (6, 86)], shade(MINT, 0.20))  # lit half
    for cx in (34, 66):
        p.arc(cx, 40, 13, 15, 180, 360, 7, shade(GREEN_D, 0.10))
        p.arc(cx, 40, 13, 15, 190, 260, 3, shade(MINT, 0.5))  # highlight on the near side
    p.rrect(6, 36, 94, 48, 5, GREEN_D)                       # the rim, holding the handles' feet
    p.inkline([(50, 48), (50, 94)], 2.6)                     # the seam
    p.inkline([(8, 62), (92, 62)], 2.0)                      # one stitch line, thin and low
    p.rrect(60, 52, 76, 76, 4, GOLD)                         # the tag
    p.circle(68, 58, 3, shade(GOLD_D, -0.2))
    p.sheen(66, 64, 3, 5, deg=0)
    p.circle(20, 30, 9, GOLD)                                # coins tipping out, left shoulder
    p.circle(30, 22, 7, SUNNY)
    p.sheen(28, 19, 2.6, 1.8)


# Fat side pockets are the whole idea: a backpack seen flat-on is a rounded rectangle, and a rounded
# rectangle is a card, a phone or a door. Two bulges drawn BEFORE the body give the silhouette three
# lobes, which is unmistakable at any size. Everything else is structure the flat version skipped --
# a lid with its own seam, a strap running under a gold buckle, a front pocket with a zip and a pull.
# The grab loop at the top is small but it is what tells you which way up the object is.
@icon("backpack")
def _backpack(p):
    p.arc(50, 24, 11, 10, 180, 360, 6.5, PURPLE_D)
    p.rrect(4, 46, 28, 86, 11, shade(LAVENDER, -0.18))
    p.rrect(72, 46, 96, 86, 11, shade(LAVENDER, -0.18))
    p.inkline([(10, 60), (22, 60)], 2.8)
    p.inkline([(78, 60), (90, 60)], 2.8)

    p.rrect(16, 26, 84, 92, 18, LAVENDER)
    p.rrect(16, 26, 84, 54, 18, shade(LAVENDER, 0.22))
    p.rrect(16, 44, 84, 54, 3, shade(LAVENDER, 0.22))
    p.inkline([(19, 54), (81, 54)], 3.2)

    p.rrect(43, 46, 57, 66, 3, PURPLE_D)
    p.rrect(40, 56, 60, 67, 3, GOLD)
    p.inkline([(46, 61), (54, 61)], 3.0)

    p.rrect(26, 69, 74, 89, 8, CREAM)
    p.inkline([(30, 75), (70, 75)], 3.0)
    p.circle(70, 75, 4.2, GOLD)


# The book is tilted eight degrees because a straight-on book is a rectangle with lines in it. The
# thickness is the point: a stack of page edges down the fore-edge, a darker spine block with its
# own seam, and gold corner protectors, so it reads as an object with a front and a side rather than
# as a cover illustration. The ribbon lies OVER the cover from the top edge down to a swallowtail --
# tucked between the pages it was only a six-unit stub after the cover clipped it, which nobody
# would have recognised.
@icon("book")
def _book(p):
    c = (50, 52, -8)
    p.poly(_rot([(26, 16), (90, 16), (90, 88), (26, 88)], *c), CREAM)
    p.poly(_rot([(82, 16), (90, 16), (90, 88), (82, 88)], *c), shade(CREAM, -0.16))
    for x in (82, 86):
        p.inkline(_rot([(x, 20), (x, 86)], *c), 2.6)

    p.poly(_rot([(12, 12), (82, 12), (82, 90), (12, 90)], *c), PURPLE)
    p.poly(_rot([(12, 12), (28, 12), (28, 90), (12, 90)], *c), PURPLE_D)
    p.inkline(_rot([(28, 14), (28, 88)], *c), 3.0)
    p.poly(_rot([(70, 12), (82, 12), (82, 24)], *c), GOLD)
    p.poly(_rot([(70, 90), (82, 90), (82, 78)], *c), GOLD)

    sx, sy = _rot([(44, 52)], *c)[0]
    p.star(sx, sy, 15, 6.5, 5, GOLD, rot=-98)
    p.line(_rot([(32, 76), (58, 76)], *c), 4.5, GOLD)

    p.poly(_rot([(62, 10), (74, 10), (74, 74), (68, 66), (62, 74)], *c), CORAL)


# A folded paper map, so the folds are load-bearing: two ink creases split it into three panels and
# the zigzag top and bottom edges are what say "paper" instead of "screen". On top of that goes the
# reason anyone opens a map -- a dashed route ending in a red X -- plus a landmass, a river and a
# compass rose so the paper is not blank between the marks. The route is dashes rather than dots: at
# 40px a dot is one pixel and disappears, while a four-unit dash still reads as a broken line.
@icon("map")
def _map(p):
    p.poly([(6, 20), (35, 10), (65, 22), (94, 10), (94, 80), (65, 92), (35, 80), (6, 90)], CREAM)
    p.poly([(14, 52), (30, 42), (52, 46), (58, 62), (42, 76), (20, 72)], MINT)
    p.line([(72, 26), (79, 46), (70, 68)], 6, AQUA)
    p.inkline([(35, 12), (35, 79)], 3.0)
    p.inkline([(65, 23), (65, 90)], 3.0)

    for a, b in (((22, 68), (32, 62)), ((38, 58), (48, 55)), ((54, 57), (63, 61)), ((70, 54), (78, 44))):
        p.line([a, b], 4.6, CORAL)
    p.capsule(78, 28, 90, 40, 5.5, RED)
    p.capsule(90, 28, 78, 40, 5.5, RED)

    p.star(19, 25, 9, 3.6, 4, BLUE)
    p.circle(19, 25, 2.8, CREAM)


# A place, drawn as a floating chunk of it. A hill alone is a triangle and the old version was
# exactly that; what makes this a location is the stack -- soil under grass, a tree standing on the
# grass, a bush balancing it, a sun and a cloud behind. The soil comes to a blunt point at the
# bottom so the island reads as lifted out of the world rather than as ground running off the edge.
# Birds were drawn in the sky and cut: two three-pixel arcs turned into grit at HUD size.
@icon("zone")
def _zone(p):
    p.star(78, 22, 18, 12, 8, SUNNY)
    p.circle(78, 22, 11, shade(SUNNY, 0.30))
    p.circle(15, 18, 8, CREAM)
    p.circle(26, 14, 11, CREAM)
    p.circle(36, 20, 8, CREAM)

    p.poly([(8, 58), (92, 58), (76, 84), (52, 94), (30, 84)], BROWN)
    p.inkline([(18, 68), (40, 71)], 3.0)
    p.inkline([(58, 73), (80, 66)], 3.0)
    p.ellipse(50, 58, 43, 15, GREEN)
    p.ellipse(46, 54, 32, 9, shade(GREEN, 0.20))

    p.capsule(38, 52, 38, 32, 7, BROWN_D)
    p.circle(26, 32, 10, GREEN_D)
    p.circle(50, 32, 11, GREEN_D)
    p.circle(38, 25, 15, GREEN_D)
    p.circle(33, 20, 6.5, shade(GREEN_D, 0.24))
    p.circle(72, 50, 9, GREEN_D)


# A wall calendar on binder rings. The rings are the detail that names the object -- a bare grid is
# a table, a table with two metal loops through the top is a calendar -- so they are drawn fat and
# in front of the header, with ink holes under them. The grid dropped from four columns to three
# because four columns of twelve units is under five pixels a cell on the HUD and turns to noise;
# three fat cells plus one ringed day still says "a date is marked". A curled bottom corner was
# tried and abandoned: without being able to cut the corner away it read as a lump, so the marker is
# a tab off the right edge instead, which also breaks the rectangle's silhouette.
@icon("calendar")
def _calendar(p):
    p.rrect(14, 26, 94, 90, 9, shade(CREAM, -0.20))
    p.rrect(86, 52, 96, 68, 3, CORAL)
    p.rrect(8, 22, 88, 88, 9, CREAM)
    p.rrect(8, 22, 88, 48, 9, CORAL)
    p.rrect(8, 38, 88, 48, 2, CORAL)
    p.inkline([(11, 48), (85, 48)], 3.2)

    for cx in (28, 66):
        p.capsule(cx, 6, cx, 32, 7, STEEL)
        p.circle(cx, 33, 3.2, INK)

    for r in range(2):
        for c in range(3):
            p.rrect(14 + c * 22, 54 + r * 18, 32 + c * 22, 68 + r * 18, 3, SKY)
    p.circle(45, 79, 10, GOLD)
    p.ring(45, 79, 10, 3.2, CORAL)


# A wind-up alarm clock, because a bare dial is a circle with two lines in it and reads as a gauge.
# The bells give it a top-heavy three-lobed silhouette and a hammer between them; the feet stop it
# floating. The two hands are deliberately different weights -- a short fat hour hand and a longer
# thin minute hand -- since equal hands read as a cross, and the gold pin holding them is what makes
# them look joined rather than crossed. The face carries a `sheen` because it is under glass.
@icon("clock")
def _clock(p):
    p.rrect(44, 6, 56, 17, 3, STEEL_D)
    p.circle(22, 22, 16, STEEL)
    p.circle(78, 22, 16, STEEL)
    p.capsule(30, 88, 22, 95, 7, STEEL_D)
    p.capsule(70, 88, 78, 95, 7, STEEL_D)

    p.circle(50, 58, 34, STEEL_D)
    p.circle(50, 58, 27, CREAM)
    p.circle(50, 58, 23, WHITE)
    p.inkline([(50, 37), (50, 43)], 3.2)
    p.inkline([(71, 58), (65, 58)], 3.2)
    p.inkline([(50, 79), (50, 73)], 3.2)
    p.inkline([(29, 58), (35, 58)], 3.2)

    p.line([(50, 58), (50, 40)], 4.6, INK)
    p.line([(50, 58), (63, 50)], 7.0, INK)
    p.circle(50, 58, 5, GOLD)
    p.circle(50, 58, 2.2, INK)
    p.sheen(38, 45, 7, 11, -32)


# Wood, glass and sand, three materials rather than one outline. The caps are chunky planks with a
# lighter band and an ink seam where they meet the glass, and two posts run down the sides -- that
# frame is what makes the pinch in the middle read as contained rather than as an accidental
# hourglass-shaped hole. Sand is drawn three times: a wedge resting in the top bulb, a falling
# stream through the waist, and a mound piled in the bottom. Falling grains as separate dots were
# tried and are invisible below 60px, so the stream carries the motion on its own.
@icon("hourglass")
def _hourglass(p):
    p.capsule(19, 20, 19, 82, 6, BROWN_D)
    p.capsule(81, 20, 81, 82, 6, BROWN_D)
    p.poly([(28, 20), (72, 20), (53, 50), (72, 80), (28, 80), (47, 50)], shade(AQUA, 0.44))

    p.poly([(32, 24), (68, 24), (50, 46)], SUNNY)
    p.capsule(50, 44, 50, 66, 3.4, SUNNY)
    p.poly([(50, 58), (70, 76), (30, 76)], SUNNY)
    p.sheen(38, 32, 5, 10, -18)

    p.rrect(10, 6, 90, 21, 5, BROWN)
    p.rrect(14, 8, 86, 13, 2, shade(BROWN, 0.26))
    p.inkline([(13, 21), (87, 21)], 3.2)
    p.rrect(10, 79, 90, 94, 5, BROWN)
    p.rrect(14, 87, 86, 92, 2, shade(BROWN, -0.18))
    p.inkline([(13, 79), (87, 79)], 3.2)


# The odd one out: not a container but a threat. It is a head rather than a full body because a body
# at 40px is a blob with limbs, while a head can spend all its pixels on the three things that make
# a monster read as one -- horns, brow and teeth. The horns are big enough to own the top third of
# the box, which also gives the silhouette its menace before any colour is seen. Yellow sclera under
# ink pupils is what stops the eyes reading as two holes; the brow is drawn OVER the top of each eye
# so the angle actually pinches them, since angry eyebrows floating above eyes read as surprise.
@icon("boss")
def _boss(p):
    p.poly([(32, 36), (10, 6), (5, 26), (24, 46)], CREAM)
    p.poly([(68, 36), (90, 6), (95, 26), (76, 46)], CREAM)
    p.inkline([(12, 16), (24, 32)], 2.8)
    p.inkline([(88, 16), (76, 32)], 2.8)

    p.rrect(14, 30, 86, 86, 24, RED)
    p.poly([(6, 48), (16, 44), (16, 62)], shade(RED, -0.20))
    p.poly([(94, 48), (84, 44), (84, 62)], shade(RED, -0.20))
    p.rrect(24, 62, 76, 90, 18, shade(RED, -0.18))

    p.circle(34, 56, 11, SUNNY)
    p.circle(66, 56, 11, SUNNY)
    p.poly([(20, 40), (48, 50), (48, 60), (20, 50)], INK)
    p.poly([(80, 40), (52, 50), (52, 60), (80, 50)], INK)
    p.eyes(50, 58, 16, 6.0)

    p.poly([(26, 68), (74, 68), (66, 88), (34, 88)], INK)
    for x in (34, 50, 66):
        p.poly([(x - 6.5, 68), (x + 6.5, 68), (x, 80)], CREAM)
    for x in (42, 58):
        p.poly([(x - 6, 88), (x + 6, 88), (x, 76)], CREAM)
