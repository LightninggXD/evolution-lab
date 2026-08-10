"""
set_currency.py -- what the player earns, spends and drinks.

Icon bodies. Each draws into a 0..100 box with the shared `Pen`; the lighting, the contour and the
gloss are added afterwards by `iconkit.render` and must NOT be drawn here -- see iconkit's header.

THE ONE RULE: never ask a primitive for a stroke. The silhouette is derived from the finished
colour layer, so a stroke here becomes an internal ring around every shape instead of one contour
around the icon. Deliberate internal linework goes through `p.inkline`.

WHY THESE ELEVEN WERE REDRAWN
------------------------------
The first pass was three or four flat shapes per icon: correct pictograms, and they read at 40px,
but a pictogram is what a settings menu looks like and this game looks like a shelf of vinyl
collectibles. The rule applied to every body below is that the object must have THICKNESS and a
STORY: a coin has a side face you can see, a gem has facets and a table, a flask has a cork and a
liquid line and bubbles. Three techniques carry almost all of it:

  * `p.inkline` for internal linework -- facets, seams, ribbon folds, engraved rims. It is the one
    thing the shading passes leave alone, so it is the only detail guaranteed to survive them.
  * an INK shape drawn slightly larger underneath an overlapping one, because the contour pass
    only outlines the OUTSIDE of the silhouette; two touching shapes are one blob without it.
  * a few degrees of tilt on anything that has a natural axis. Dead-straight reads as a diagram.

Everything is still lit from the top left, so every `p.sheen` sits upper-left of its own shape.
"""

from iconkit import (  # noqa: F401  -- the palette is a namespace, not a checklist
    icon, Pen,
    INK, WHITE, CREAM, GOLD, GOLD_D, ORANGE, BLUE, SKY, GREEN, GREEN_D, RED, PURPLE, PURPLE_D,
    PINK, GREY, MINT, SUNNY, BUBBLEGUM, LAVENDER, AQUA, PEACH, CORAL, BROWN, BROWN_D, STEEL,
    STEEL_D, TEAL, PLUM, shade,
)

import math  # noqa: F401


# ---------------------------------------------------------------- local geometry helpers
# `p.rot_poly` fills a rotated polygon, which covers the fills but not the linework that has to
# sit ON the same rotated shape. These return POINTS instead, so one tilt can be shared by a
# `p.poly` and the three `p.inkline` calls that draw its facets.


def _rot(pts, cx, cy, deg):
    """The point list, turned about (cx, cy). Same maths as `Pen.rot_poly`, without the fill."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def _star_pts(cx, cy, outer, inner, points, rot=-90):
    """`Pen.star`'s vertices, so facet lines can be drawn to the exact tips of a drawn star."""
    out = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = math.radians(rot + i * 180.0 / points)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def _heart_pts(cx, cy, w, h, deg=0.0, n=64):
    """The classic parametric heart, normalised into a w x h box.

    Built from the curve rather than from two circles and a triangle because the cleft is the part
    that has to look drawn: circles-plus-triangle gives a flat-topped valley, and at 40px that
    valley is the only thing separating this from a spade.
    """
    raw = []
    for i in range(n):
        t = 2 * math.pi * i / n
        raw.append((
            16 * math.sin(t) ** 3,
            -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)),
        ))
    xs = [q[0] for q in raw]
    ys = [q[1] for q in raw]
    mx, my = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
    sx, sy = w / (max(xs) - min(xs)), h / (max(ys) - min(ys))
    return _rot([(cx + (x - mx) * sx, cy + (y - my) * sy) for x, y in raw], cx, cy, deg)


# ---------------------------------------------------------------- the icons


@icon("dna")
def _dna(p):
    # The helix went from four crossings to two. Four is what a real diagram has and it is exactly
    # what turns to a striped smear at 40px; two big crossings is what a toy has, and the eye reads
    # "twist" from the first one. The strands are also much fatter (11.5 wide against 9) and the
    # rungs sit BEHIND them so the ladder passes through rather than butting onto the sides.
    #
    # Each strand is laid down twice: an INK pass 5 units wider, then the colour. The contour pass
    # only outlines the outside of the silhouette, so without that the pink strand crossing the
    # blue one would merge into a single two-tone blob at the crossing -- the same failure `luck`
    # documents. The ink pass is what makes one strand read as being in front of the other.
    top, bot = 9, 91
    turn = math.pi * 2.2      # 1.1 periods: strands are apart at both ends, crossing twice between

    def curve(phase):
        return [(50 + 26 * math.sin(t * turn + math.pi / 2 + phase), top + (bot - top) * t)
                for t in (i / 36.0 for i in range(37))]

    for i in range(7):
        t = 0.035 + i * 0.155
        y = top + (bot - top) * t
        x1 = 50 + 26 * math.sin(t * turn + math.pi / 2)
        x2 = 50 + 26 * math.sin(t * turn + math.pi / 2 + math.pi)
        if abs(x1 - x2) < 16:
            continue          # near a crossing the rung is a stub; a stub reads as a smudge
        p.line([(x1, y), (x2, y)], 11, INK)
        p.line([(x1, y), (x2, y)], 6, CREAM)
        p.inkline([(50, y - 2.6), (50, y + 2.6)], 2.0)   # the base-pair split, mid-rung

    for phase, col in ((0.0, SKY), (math.pi, PINK)):
        pts = curve(phase)
        p.line(pts, 17, INK)
        p.line(pts, 11.5, col)
        p.sheen(pts[1][0] - 1.5, pts[1][1] + 4, 3.4, 2.2)


@icon("diamond")
def _diamond(p):
    # A brilliant cut instead of a pentagon with three lines on it: a wide flat table, a crown of
    # three facets, a girdle you can see, and a pavilion split into three tones. The whole gem is
    # tilted 8 degrees -- upright it read as a playing-card suit rather than as an object sitting
    # in the light.
    #
    # The tones are the point: left facets lighter, right facets deepened, so the stone is lit from
    # the top left like everything else on the HUD. A single AQUA fill with facet lines drawn on it
    # was tried first and looked like a wireframe, because a facet is a change in VALUE and the
    # line is only there to sharpen the edge between two of them.
    def r(pts):
        return _rot(pts, 50, 52, -8)

    tl, tr = (32, 14), (68, 14)          # the table
    kl, kr = (28, 40), (72, 40)          # where the crown facets meet the girdle
    gl, gr = (9, 40), (91, 40)           # the girdle corners, the widest part of the stone
    apex = (50, 91)

    p.poly(r([gl, tl, kl]), shade(AQUA, 0.16))
    p.poly(r([tl, tr, kr, kl]), shade(AQUA, 0.34))
    p.poly(r([tr, gr, kr]), shade(AQUA, -0.14))
    p.poly(r([gl, kl, apex]), shade(AQUA, 0.06))
    p.poly(r([kl, kr, apex]), AQUA)
    p.poly(r([kr, gr, apex]), shade(AQUA, -0.24))

    for a, b in ((gl, gr), (tl, kl), (tr, kr), (kl, apex), (kr, apex)):
        p.inkline(r([a, b]), 2.6)

    p.sheen(38, 25, 11, 5.0)
    p.star(64, 58, 9, 3.2, 4, CREAM, rot=-90)     # the deep glint, low on the pavilion


@icon("shard")
def _shard(p):
    # This used to be a four-point sparkle whose only job was not to look like `xp`. That works,
    # but a sparkle is not a shard, and the flat star had nowhere to put detail. It is now what the
    # word says: a broken crystal, a tall tilted spike with a smaller chip leaning on it.
    #
    # Purple settles the collision with `xp` far better than the shape ever did -- the two sat side
    # by side on the Daily panel in the same gold. Purple also separates it from `diamond`, which
    # is the wide symmetrical aqua stone; this one is tall, lopsided and tilted.
    #
    # Two faces and a centre ridge is the whole trick. One flat fill with lines on it reads as a
    # kite; a light face against a dark face reads as a solid with a corner pointing at you.
    def r(pts):
        return _rot(pts, 52, 50, 7)

    apex, base_l, base_r = (52, 7), (36, 88), (68, 88)
    left, right = (28, 44), (76, 44)

    p.poly(r([apex, (52, 88), base_l, left]), shade(PURPLE, 0.20))
    p.poly(r([apex, right, base_r, (52, 88)]), PURPLE_D)
    p.inkline(r([apex, (52, 88)]), 2.8)                     # the ridge, the near corner
    p.inkline(r([left, right]), 2.6)                        # the widest girdle of the crystal
    p.inkline(r([(34, 66), (70, 66)]), 2.2)                 # one lower facet break, for depth

    # the chip: drawn over the spike, so it needs its own ink pad to sit in front of it
    chip = [(16, 50), (30, 62), (26, 88), (10, 80)]
    p.poly(_rot([(x + (x - 20) * 0.16, y + (y - 70) * 0.14) for x, y in chip], 20, 70, -12), INK)
    p.poly(_rot(chip, 20, 70, -12), LAVENDER)
    p.inkline(_rot([(21, 54), (20, 86)], 20, 70, -12), 2.2)

    p.sheen(44, 30, 7, 3.4, deg=-70)
    p.star(84, 20, 11, 3.6, 4, CREAM, rot=-90)              # sparkles coming off the crystal
    p.star(24, 22, 7, 2.4, 4, CREAM, rot=-90)


@icon("xp")
def _xp(p):
    # Still a five-point star, because that is what a level-up is everywhere, but now a bevelled
    # one: a darker rim star with a brighter star inside it and five ink facets running from the
    # centre to the tips. That bevel is what stops a star from reading as a flat sticker.
    #
    # Ten facet lines -- to the inner vertices as well -- was the first attempt and it filled the
    # middle with black hair at 40px. Five, to the tips only, survives the downscale.
    tips = _star_pts(50, 52, 44, 18.5, 5, rot=-84)
    p.star(50, 52, 44, 18.5, 5, GOLD_D, rot=-84)
    p.star(50, 52, 36, 15, 5, SUNNY, rot=-84)
    for i in range(0, 10, 2):
        p.inkline([(50, 52), tips[i]], 2.4)
    p.circle(50, 52, 6.5, shade(SUNNY, 0.42))               # the boss of the bevel
    p.sheen(38, 40, 8, 4.2)


@icon("coin")
def _coin(p):
    # The two overlapping faces stay -- one coin behind another is what says "currency" instantly.
    # What is new is THICKNESS: each disc is drawn twice, once offset four units down in a deepened
    # gold, so a crescent of the side face shows under the front face. A coin with no visible edge
    # is a token.
    #
    # The front face also gets a milled rim: eight ink ticks between r26 and r30. Twelve was tried
    # and closed into a grey band at 40px; eight stays as separate marks.
    p.circle(70, 62, 23, INK)
    p.circle(70, 67, 20, shade(GOLD_D, -0.34))
    p.circle(70, 62, 20, GOLD_D)
    p.inkline([(52, 56), (56, 46)], 2.2)                    # where the front coin cuts the back one

    p.circle(40, 47, 33, INK)
    p.circle(40, 51, 30, shade(GOLD_D, -0.34))
    p.circle(40, 46, 30, GOLD_D)
    p.circle(40, 46, 22, GOLD)
    p.ring(40, 46, 22.5, 2.4, INK)
    for i in range(8):
        a = math.radians(i * 45 + 12)
        p.inkline([(40 + 26 * math.cos(a), 46 + 26 * math.sin(a)),
                   (40 + 29.5 * math.cos(a), 46 + 29.5 * math.sin(a))], 2.6)
    p.star(40, 46, 14, 5.5, 4, CREAM, rot=-90)              # the device stamped into the face
    p.sheen(28, 32, 10, 5.0)
    p.star(12, 12, 6.5, 2.2, 4, CREAM, rot=-90)             # the cast-off glint, off the metal


@icon("luck")
def _luck(p):
    # EACH LEAF STILL CARRIES ITS OWN INK RING. The silhouette pass draws the OUTER contour only,
    # so four touching circles come out as one green blob -- the internal edges have to be drawn on
    # purpose. That was true in the flat version and it is still the load-bearing trick here.
    #
    # What changed: the leaves are heart-shaped, not round. The notch is an INK disc parked on the
    # outer edge of each leaf -- it cannot be cut out of the alpha (there is no erase), but ink
    # touching the contour is indistinguishable from a bite taken out of it. Each leaf also gets a
    # vein running back to the centre, and the four are tilted 10 degrees off the axes so the
    # clover sits at an angle rather than squaring up with the tile.
    p.line([(52, 52), (60, 74), (50, 91)], 7.5, GREEN_D)
    p.inkline([(53, 60), (58, 74)], 2.0)

    tones = (MINT, GREEN, GREEN, shade(GREEN, -0.14))
    for (cx, cy), tone in zip(_rot([(34, 35), (66, 35), (34, 65), (66, 65)], 50, 50, 10), tones):
        dx, dy = cx - 50, cy - 50
        n = math.hypot(dx, dy)
        p.circle(cx, cy, 20, INK)
        p.circle(cx, cy, 17.5, tone)
        p.circle(cx + dx / n * 19, cy + dy / n * 19, 6.2, INK)     # the heart notch
        p.inkline([(cx - dx / n * 3, cy - dy / n * 3), (cx + dx / n * 13, cy + dy / n * 13)], 2.2)

    p.sheen(27, 27, 7.5, 4.2)


@icon("potion")
def _potion(p):
    # The conical flask became a round-bottomed bottle, because a cone is a lab diagram and a fat
    # bottle is a thing you drink. It now has every part the reference art gives glassware: a cork
    # with a seam, a collar ring at the neck, a glass wall, a liquid line with a meniscus, bubbles,
    # and a hard vertical catchlight down the left of the sphere.
    #
    # The liquid is a real circular segment, sampled off the body's own arc, rather than a trapezoid
    # sitting inside it. A straight-sided fill inside a round bottle leaves two slivers of glass at
    # the waterline and reads as a second object floating in the bottle.
    cx, cy, rr, surf = 50, 63, 29, 55

    p.rrect(41, 16, 59, 42, 4, shade(STEEL, 0.22))          # the neck, behind everything
    p.circle(cx, cy, rr, shade(STEEL, 0.30))                # the glass

    a0 = math.degrees(math.asin((surf - cy) / rr))
    p.poly([(cx + rr * math.cos(math.radians(a)), cy + rr * math.sin(math.radians(a)))
            for a in (a0 + (180 - 2 * a0) * i / 40.0 for i in range(41))], PURPLE)
    p.ellipse(cx, surf, rr * math.cos(math.radians(a0)) - 1, 4, LAVENDER)
    p.inkline([(cx - 26, surf - 1), (cx + 26, surf - 1)], 2.0)

    for bx, by, br in ((41, 70, 5.4), (58, 77, 3.6), (52, 63, 2.6)):
        p.circle(bx, by, br, shade(LAVENDER, 0.34))
    p.inkline([(38, 82), (46, 86)], 2.0)                    # a sediment mark, low in the glass

    p.rrect(36, 33, 64, 43, 4, STEEL_D)                     # the collar
    p.inkline([(37, 38), (63, 38)], 2.2)

    cork = _rot([(38, 7), (62, 7), (60, 26), (40, 26)], 50, 16, 6)
    p.poly(cork, BROWN)
    p.poly(_rot([(38, 7), (62, 7), (61.5, 14), (38.5, 14)], 50, 16, 6), shade(BROWN, 0.26))
    p.inkline(_rot([(38.5, 14), (61.5, 14)], 50, 16, 6), 2.2)
    p.inkline(_rot([(50, 15), (50, 26)], 50, 16, 6), 2.0)

    p.sheen(33, 52, 4.2, 12, deg=-14)                       # the wet streak down the glass wall
    p.sheen(41, 43, 3.2, 2.2)


@icon("egg")
def _egg(p):
    # The crack is a bold ink zigzag with one chip lifted clear of it, which is what stops the egg
    # from being a spotted ellipse. It runs across the upper third rather than the middle: a crack
    # on the equator cuts the silhouette in half and the shape stops reading as an egg.
    #
    # NO FACE, AND THE FIRST VERSION HAD ONE. Two eyes were drawn under the crack on the theory
    # that everything in this game hatches, so an egg with something looking out of it says so
    # without a second object in frame. What it actually produced was not an egg with a face, it
    # was a FACE: two dark discs in the middle of a pale oval are read as eyes before any other
    # part of the drawing is read at all, and the coloured speckles were then recruited into cheeks
    # and a nose. The silhouette stopped being an egg and became a blob with an expression.
    #
    # The rule that comes out of it is general and the temptation recurs: A FACE IS NOT A
    # DECORATION YOU ADD TO AN OBJECT, IT REPLACES THE OBJECT. `pet` and `boss` are meant to be
    # faces and should have them; this is meant to be a thing you hatch. So the speckles carry the
    # character instead, and there are now four of them placed deliberately OFF a shared baseline,
    # because any two at the same height pair up into eyes again.
    p.rot_poly([(50 + 30 * math.cos(a), 58 + 37 * math.sin(a))
                for a in (2 * math.pi * i / 48 for i in range(48))], 50, 58, 7, CREAM)

    p.circle(34, 64, 9.5, AQUA)
    p.circle(62, 76, 11, PINK)
    p.circle(66, 52, 6.5, SUNNY)
    p.circle(30, 44, 4.5, LAVENDER)

    crack = [(21, 40), (32, 34), (38, 42), (50, 33), (58, 41), (68, 32), (78, 38)]
    p.inkline(crack, 3.0)
    p.inkline([(50, 33), (52, 25)], 2.6)                    # one chip lifting off the shell
    p.inkline([(52, 25), (61, 28)], 2.6)

    p.sheen(38, 50, 9, 5)


@icon("heart")
def _heart(p):
    # A bevelled heart rather than a solid one: a deepened rim with a brighter heart inside it,
    # offset up and left so the rim is thickest along the bottom right. That offset is doing the
    # same job as the pipeline's core shade, but on a shape INSIDE the silhouette, where the
    # pipeline cannot reach.
    #
    # The small heart flying off the top right is the storytelling prop. It is detached, so the
    # contour pass wraps it separately and it reads as a second object rather than as a lump; it
    # also breaks the perfect symmetry that made the flat version look like a suit on a card.
    p.poly(_heart_pts(50, 56, 82, 76, deg=-7), shade(CORAL, -0.22))
    p.poly(_heart_pts(48, 54, 66, 62, deg=-7), CORAL)
    p.inkline(_rot([(50, 30), (50.5, 40)], 50, 56, -7), 2.4)     # the cleft, sharpened
    p.poly(_heart_pts(84, 17, 22, 21, deg=14), CORAL)
    p.sheen(34, 41, 10, 6)
    p.sheen(80, 12, 3.6, 2.4)


@icon("plus")
def _plus(p):
    # A button, not a glyph. The disc is two rings deep now -- a deepened outer band and a lighter
    # face -- so the plus sits in a bezel instead of floating on a circle, and the cross is tilted
    # 10 degrees, which is the entire difference between "drawn" and "aligned to the pixel grid".
    #
    # The cross gets its own ink pad four units wider before the white goes down. White on green
    # would be legible without it, but every other icon in this set separates its parts with ink
    # and one that does not is the one that looks like it came from a different set.
    p.circle(50, 50, 43, GREEN_D)
    p.circle(50, 50, 35, GREEN)
    p.ring(50, 50, 35, 2.4, INK)

    for a, b in (((50, 25), (50, 75)), ((25, 50), (75, 50))):
        pts = _rot([a, b], 50, 50, 10)
        p.line(pts, 19, INK)
    for a, b in (((50, 25), (50, 75)), ((25, 50), (75, 50))):
        pts = _rot([a, b], 50, 50, 10)
        p.line(pts, 13.5, WHITE)

    p.sheen(31, 28, 9, 5)
    p.star(72, 26, 7.5, 2.6, 4, CREAM, rot=-90)             # a spark off the bezel
    p.star(28, 72, 5, 1.8, 4, CREAM, rot=-90)


@icon("medal")
def _medal(p):
    # Three things were added and each is doing a job. The rim is scalloped -- a sixteen-point star
    # with barely any difference between its radii -- so the contour pass traces a milled edge
    # instead of a circle, which is the cheapest way to make a disc read as struck metal. The
    # ribbons get swallowtail notches cut into their tops (ink touching the contour reads as a cut)
    # and a fold line down each, so they read as cloth rather than as two coloured quadrilaterals.
    # And a steel hanging loop joins the ribbons to the medal, which is the part the flat version
    # left the eye to assume.
    p.poly([(18, 6), (39, 6), (58, 44), (43, 52)], CORAL)
    p.poly([(59, 6), (80, 6), (55, 52), (40, 44)], SKY)
    p.inkline([(59, 6), (40, 44)], 3.0)                     # the ribbon in front, separated
    p.inkline([(28, 8), (47, 42)], 2.2)
    p.inkline([(70, 8), (50, 44)], 2.2)
    p.poly([(24, 6), (33, 6), (28.5, 15)], INK)             # swallowtail notches
    p.poly([(65, 6), (74, 6), (69.5, 15)], INK)

    p.circle(50, 44, 8.5, INK)
    p.ring(50, 44, 6, 3.4, STEEL)

    p.star(50, 66, 28, 25, 16, GOLD_D, rot=-90)             # the milled rim
    p.circle(50, 66, 23, GOLD)
    p.ring(50, 66, 23, 2.4, INK)
    p.circle(50, 66, 18, shade(GOLD, 0.20))
    p.star(50, 66, 13.5, 5.5, 5, CREAM, rot=-84)
    p.sheen(37, 55, 8, 4.4)
