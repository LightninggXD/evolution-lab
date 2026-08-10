"""
set_zone.py -- one badge per zone, the twenty places the game is played in.

Icon bodies. Each draws into a 0..100 box with the shared `Pen`; the lighting, the contour and the
gloss are added afterwards by `iconkit.render` and must NOT be drawn here -- see iconkit's header.

THE ONE RULE: never ask a primitive for a stroke. The silhouette is derived from the finished
colour layer, so a stroke here becomes an internal ring around every shape instead of one contour
around the icon. Deliberate internal linework goes through `p.inkline`.

THESE ARE THE BIGGEST ICONS IN THE GAME. The zone emoji is drawn on the zone row, on the unlock
toast, on the boss bar -- and on `ZoneTransition`'s full-screen card at 190x190, which is several
times the size anything else here is ever seen at. They can carry more detail than a 40px tile
icon, and they still have to survive being shrunk to one.

THEY ARE ALSO A SEQUENCE. The zones run Forest to Absolute Plane and the player climbs them in
order, so the set has to read as one journey getting stranger: green and friendly at the start,
cosmic and unsettling at the end. Six of them are variations on "a dark round thing in space" --
blackhole, void, singularity, nebula, galaxy, multiverse -- and they sit in the same scrolling
list, so telling them apart at a glance is the hardest constraint in this file.

HOW THE SIX ROUND ONES ARE KEPT APART
--------------------------------------
Colour alone is not enough: the zone list is scrolled fast and hue is the first thing that stops
registering. Each of the six was given a DIFFERENT OUTLINE, so the contour pass -- the heaviest
mark on every icon -- is already telling them apart before any fill is seen:

  galaxy       a tilted lens, two lumpy arms sticking out past the disc
  blackhole    a wide flat ring with a ball bulging out of its middle -- a saucer
  multiverse   an ARCH. Flat bottom, round top. Nothing else in the set has a flat bottom.
  nebula       a bumpy cloud with wisps trailing off it
  void         a solid disc with three angular bites torn out of its rim
  singularity  not round at all: a spiked flash with four tails curling into it

A NOTE ON `CLEAR`
------------------
PIL's ImageDraw REPLACES pixels rather than compositing them, so filling a shape with a fully
transparent colour cuts a hole in whatever has already been drawn. That is the only way to get a
true hole -- a crescent, a flat ring, a torn rim -- and holes matter enormously here, because the
contour pass traces the alpha and therefore inks the inside of a hole as well as the outside.
"""

from iconkit import (  # noqa: F401  -- the palette is a namespace, not a checklist
    icon, Pen,
    INK, WHITE, CREAM, GOLD, GOLD_D, ORANGE, BLUE, SKY, GREEN, GREEN_D, RED, PURPLE, PURPLE_D,
    PINK, GREY, MINT, SUNNY, BUBBLEGUM, LAVENDER, AQUA, PEACH, CORAL, BROWN, BROWN_D, STEEL,
    STEEL_D, TEAL, PLUM, shade,
)

import math  # noqa: F401


# Filling with this cuts a hole -- see the header. Named rather than inlined because a bare
# (0, 0, 0, 0) at a call site reads as "transparent black" and gets "fixed" into INK by the next
# person through the file.
CLEAR = (0, 0, 0, 0)

# The deep-space hues the UITheme palette genuinely does not carry. UITheme is a UI palette: its
# darkest colours are PLUM and INK, both of which are violet, and nine of these icons need a cold
# empty black-blue that no amount of `shade` on a violet will produce. These four are the whole
# list of raw tuples in the file.
SPACE     = (38, 34, 68, 255)     # the ground colour of every cosmic zone
SPACE_D   = (22, 20, 44, 255)     # one step deeper, for the inside of a hole
RUST      = (206, 92, 54, 255)    # Mars. ORANGE is a traffic cone, RED is a strawberry.
RUST_D    = (156, 62, 40, 255)


# ---------------------------------------------------------------- helpers
# Three shapes were being written out longhand in icon after icon. They are here rather than in
# iconkit because they are specific to this set -- a planetary cap and a spiral arm are not things
# the currency or the creature sets will ever want.


def _cap(p, cx, cy, r, a0, a1, color, steps=20):
    """A circular SEGMENT: the arc from a0 to a1 closed by its chord.

    A polar ice cap is a segment, not an ellipse. Drawing it as an ellipse and letting it hang
    over the planet's rim is the version that was tried first and it makes the planet look like it
    is wearing a hat rather than like the cap is part of the sphere.
    """
    pts = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    p.poly(pts, color)


def _arm(p, cx, cy, rot, sweep, r0, r1, w0, w1, squash, tilt, cols):
    """One spiral arm, as a chain of shrinking circles.

    A tapering ribbon cannot be had from `p.line`, whose width is constant, and a two-sided
    polygon of it comes out spindly at 40px. A chain of overlapping discs is chunkier than either,
    gives the arm visible lumps -- which read as star clusters -- and lets the colour walk along
    the arm so the tip can be a different hue from the core.
    """
    n = len(cols)
    ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    for i in range(n):
        t = i / (n - 1.0)
        a = math.radians(rot + sweep * t)
        r = r0 + (r1 - r0) * t
        x, y = r * math.cos(a), r * math.sin(a) * squash
        p.circle(cx + x * ct - y * st, cy + x * st + y * ct, w0 + (w1 - w0) * t, cols[i])


def _bite(p, cx, cy, a, r, spread):
    """Tear a triangular notch out of a rim at angle `a`. Used only by `void`."""
    o = math.radians(a)
    p.poly([
        (cx + r * 1.35 * math.cos(o - math.radians(spread)),
         cy + r * 1.35 * math.sin(o - math.radians(spread))),
        (cx + r * 1.35 * math.cos(o + math.radians(spread)),
         cy + r * 1.35 * math.sin(o + math.radians(spread))),
        (cx + r * 0.34 * math.cos(o), cy + r * 0.34 * math.sin(o)),
    ], CLEAR)


# ================================================================ the green end
# Zones 1-4 are places with a horizon: ground at the bottom, sky at the top, an object standing on
# it. They are the only four in the set that have an up and a down, and that is deliberate --
# losing the horizon is how the sequence announces that the player has left the planet.


@icon("forest")
def _forest(p):
    # The first zone, and the friendliest thing in the set: one fat three-tier conifer standing on
    # a grass bank with two smaller trees behind it for depth.
    #
    # The tiers are the whole read and they are all the same green, so touching triangles come out
    # as one green blob -- the outer contour is the ONLY line the pipeline draws. Two things fix
    # it: each tier is a shade apart from its neighbour, and each tier's lower edge gets a shallow
    # ink V. A flat ink line was tried and made the tree look like a stack of pennants; the V is
    # what makes the branch layer read as drooping.
    p.rrect(4, 76, 96, 96, 12, GREEN_D)                      # the bank
    for cx in (17, 83):                                      # back trees, one shade cooler
        p.poly([(cx, 30), (cx + 15, 78), (cx - 15, 78)], shade(GREEN_D, -0.22))
    p.rrect(44, 58, 56, 88, 4, BROWN_D)                      # trunk, drawn under the foliage
    p.poly([(50, 44), (89, 82), (11, 82)], shade(GREEN_D, -0.06))
    p.poly([(50, 25), (79, 62), (21, 62)], GREEN_D)
    p.poly([(50, 6), (71, 40), (29, 40)], GREEN)
    p.inkline([(21, 62), (50, 66), (79, 62)], 2.6)
    p.inkline([(11, 82), (50, 86), (89, 82)], 2.6)
    for bx, by in ((36, 52), (63, 55), (50, 74)):            # berries: three warm dots so the
        p.circle(bx, by, 3.6, CORAL)                         # green has something to sit against
    p.sheen(40, 20, 5, 2.6)


@icon("desert")
def _desert(p):
    # Two dunes and a saguaro against a low sun. The sun is drawn BEHIND the back dune and half
    # sunk into it, which is what makes the picture read as a horizon rather than as a ball above
    # a hill -- an unoccluded sun sat in the corner looking like a separate icon.
    p.circle(72, 40, 19, SUNNY)
    p.poly([(4, 96), (4, 62), (30, 48), (58, 62), (82, 50), (96, 58), (96, 96)],
           shade(GOLD_D, -0.10))                             # back dune
    p.poly([(4, 96), (4, 78), (28, 66), (62, 80), (96, 70), (96, 96)], GOLD)   # front dune
    p.inkline([(4, 78), (28, 66), (62, 80), (96, 70)], 2.4)
    # The cactus is the silhouette cue -- dunes alone are two beige humps and could be anything.
    # It is offset left and overlaps the crest so it is clearly standing IN the scene.
    p.rrect(20, 30, 36, 88, 8, GREEN_D)
    p.rrect(6, 46, 20, 56, 5, GREEN_D)
    p.rrect(6, 46, 16, 70, 5, GREEN_D)
    p.rrect(36, 54, 50, 64, 5, GREEN_D)
    p.rrect(40, 40, 50, 64, 5, GREEN_D)
    p.inkline([(28, 38), (28, 80)], 2.2)                     # the rib, so it is a cactus not a pipe
    p.circle(44, 34, 4.5, CORAL)                             # flower
    p.sheen(26, 40, 3.4, 8, deg=0)


@icon("ocean")
def _ocean(p):
    # One big curling wave, and the SECOND attempt at it. The first tried to draw a real barrel --
    # a crest breaking rightward with the lip curling back under itself and the tube mouth cut out
    # with CLEAR -- and it came out as a blue rock formation with bubbles stuck to it. Two reasons,
    # both worth keeping: the cut mouth put a hole in the middle of the silhouette (so the contour
    # ran round the INSIDE of the wave, which reads as a handle), and the foam circles were the
    # same size as the tube, so the eye could not tell which was the subject.
    #
    # The hook was the SECOND failure and is worth recording too: a narrow comma rising steeply and
    # bending right, over a low bar of water, read as a tap running into a sink. The fault was
    # proportion, not shape -- it was taller than it was wide, and water is never that.
    #
    # THIRD VERSION: BROAD AND LOW. The swell is a wide mound filling the bottom two thirds, and
    # only its right shoulder rises and tips over into a curl. A wave is a horizontal event with
    # one vertical accent, which is the opposite of what the first two drew. The foam sits along
    # the whole top edge -- not just on the tip -- so the eye reads a line of white water rather
    # than a knob on a stick.
    # BUILT AS OVERLAPPING MASSES, not as one traced outline, and that is the lesson of three
    # attempts. Every failure was the same mistake in a different pose: a single polygon whose
    # return path came back near its outgoing path, which is a BAND, and a band always reads as a
    # rope, a hose or a tap however it is bent. The silhouette here is derived from the union of
    # the whole colour layer, so overlapping solid shapes are free -- a broad mound with a curl
    # dropped on top of it cannot come out as a ribbon, because neither piece is one.
    p.rrect(2, 76, 98, 97, 8, BLUE)                          # the water it comes out of
    # 1. THE MOUND: base flat on the waterline, shoulders wide, the mass of the wave.
    p.poly([(2, 94), (2, 62), (14, 44), (34, 34), (56, 34), (72, 42), (80, 58), (80, 94)], AQUA)
    # 2. THE CURL: a fat lip growing out of the mound's right shoulder and tipping over. Solid and
    #    round, overlapping the mound by a long way so the two read as one body of water.
    p.poly([(52, 52), (58, 28), (70, 16), (86, 18), (95, 32), (94, 52), (86, 66), (66, 62)], AQUA)
    # NO DARK PATCH INSIDE THE CURL. One was drawn there to suggest the hollow of the tube and it
    # read as an eye -- a dark rounded shape in the upper half of a pale blob is a face before it
    # is anything else. The tube is implied by the foam wrapping over the top instead, which costs
    # nothing and cannot be misread.
    # 3. The lit face, up the mound's leading edge only -- the light is top-left, as everywhere.
    p.poly([(8, 62), (18, 46), (36, 37), (54, 37), (44, 44), (26, 52), (16, 64)], SKY)
    # 4. FOAM ALONG THE CREST, sizes falling left to right so the break has a direction.
    for fx, fy, fr in ((76, 12, 11), (90, 22, 8), (58, 30, 7), (38, 30, 6), (20, 40, 5)):
        p.circle(fx, fy, fr, CREAM)
    p.circle(74, 10, 4.5, WHITE)
    for fx, fy, fr in ((22, 88, 5), (54, 90, 4.5), (86, 86, 5)):
        p.circle(fx, fy, fr, shade(SKY, 0.34))               # chop in the water below
    p.sheen(24, 56, 7, 3)


@icon("volcano")
def _volcano(p):
    # A squat cone with the crater CUT OUT of its top rather than painted on it: the notch gives
    # the silhouette its own ink dip, and a volcano is recognised by that dip long before the lava
    # is visible at 40px. Lava overflows the near lip in two tongues and there are three bombs in
    # the air; the smoke is one big puff, because three small ones turned into grey noise.
    for sx, sy, sr in ((36, 12, 13), (58, 8, 15), (74, 18, 11)):
        p.circle(sx, sy, sr, shade(GREY, -0.12))             # smoke plume
    p.poly([(6, 94), (32, 34), (68, 34), (94, 94)], BROWN)
    p.poly([(52, 34), (68, 34), (94, 94), (60, 94)], shade(BROWN, -0.22))   # shadow side
    p.poly([(30, 36), (44, 26), (56, 26), (70, 36), (50, 44)], CLEAR)       # the crater notch
    p.poly([(32, 38), (44, 30), (56, 30), (68, 38), (50, 46)], ORANGE)      # lava in the bowl
    p.poly([(38, 40), (46, 62), (40, 82), (52, 92), (58, 74), (52, 52), (60, 40)], RED)
    p.poly([(42, 42), (48, 60), (44, 78), (52, 84), (54, 66), (49, 48)], ORANGE)
    for bx, by, br in ((18, 26, 6), (84, 34, 5), (26, 54, 4)):
        p.circle(bx, by, br, RED)                            # bombs
    p.sheen(24, 60, 4, 9, deg=-58)


# ================================================================ leaving the ground
# Zones 5-6 still have a body you could stand on, but no horizon: from here the icon is an object
# floating in the box, and the palette starts losing its greens.


@icon("moon")
def _moon(p):
    # A fat crescent, cut with CLEAR so the inner curve gets its own contour -- a crescent painted
    # as a light shape over a dark disc has no ink on its concave side and reads as a lemon.
    # The craters sit on the THICK part of the crescent only; a crater near the thin horn is three
    # pixels wide at 40px and turns the horn into a dotted line.
    p.circle(46, 52, 42, CREAM)
    p.circle(80, 34, 34, CLEAR)
    for cx, cy, cr in ((30, 34, 9), (24, 60, 11), (40, 78, 8), (18, 44, 5), (44, 24, 5)):
        p.circle(cx, cy, cr, shade(CREAM, -0.16))
        p.circle(cx - cr * 0.16, cy - cr * 0.16, cr * 0.62, shade(CREAM, -0.06))
    # Two stars in the crescent's bay. They fill the hole the cut leaves, and they are the first
    # stars in the sequence -- the moon is where this stops being a landscape set.
    p.star(80, 22, 9, 3.6, 4, SUNNY, rot=-90)
    p.star(88, 48, 6, 2.4, 4, SUNNY, rot=-90)
    p.sheen(34, 22, 6, 3)


@icon("mars")
def _mars(p):
    # A rust sphere with a white cap, dark maria and two craters. RUST is a raw tuple: the palette
    # jumps straight from ORANGE to RED and neither is a planet.
    #
    # The cap is a circular segment (see `_cap`) so it belongs to the sphere. The maria are drawn
    # as squashed ellipses aligned to the sphere's curve rather than as round blobs, which is what
    # keeps the disc from reading as a cookie with chocolate chips.
    p.circle(50, 52, 42, RUST)
    _cap(p, 50, 52, 42, 200, 340, CREAM)                     # north polar cap
    _cap(p, 50, 52, 42, 44, 118, shade(CREAM, -0.14))        # a sliver of the south one
    p.ellipse(34, 52, 16, 9, RUST_D)
    p.ellipse(64, 66, 13, 7, RUST_D)
    p.ellipse(72, 42, 8, 5, RUST_D)
    p.circle(44, 74, 6, shade(RUST, -0.28))
    p.circle(44, 74, 3.6, shade(RUST, 0.14))
    p.inkline([(20, 44), (36, 40), (52, 44)], 2.0)           # a canyon, so it has one hard mark
    p.sheen(34, 30, 8, 4)


# ================================================================ deep space
# Zones 7-17. Everything from here is round, dark and lit from inside, which is exactly the
# problem this file exists to solve -- see the header for what separates each silhouette.


@icon("galaxy")
def _galaxy(p):
    # A tilted two-armed spiral. Its silhouette cue is the TILT plus the two lumpy arms that swing
    # out past the disc: a lopsided lens with knuckles, where nothing else in the six is lopsided.
    #
    # The arms walk from violet at the core to aqua at the tip so the outside of the icon is a
    # different temperature from the inside, which is what a real spiral looks like and also what
    # stops the whole thing greying out at 40px. The faint disc behind them is squashed and tilted
    # by the same numbers the arms use, or the arms sit on it like wire on a plate.
    cols_in = [PURPLE_D, PURPLE, PURPLE, LAVENDER, LAVENDER, SKY, AQUA, AQUA]
    p.rot_poly([(50 + 46 * math.cos(math.radians(a)), 52 + 27 * math.sin(math.radians(a)))
                for a in range(0, 360, 12)], 50, 52, -22, shade(PLUM, -0.30))
    for rot in (0, 180):
        _arm(p, 50, 52, rot, 165, 9, 44, 13, 4.5, 0.60, -22, cols_in)
    p.ellipse(50, 52, 17, 12, SUNNY)                         # the core, brighter than any arm
    p.ellipse(50, 52, 10, 7, CREAM)
    for sx, sy, sr in ((22, 30, 3.4), (78, 74, 3.0), (84, 34, 2.6), (18, 70, 2.6)):
        p.circle(sx, sy, sr, WHITE)
    p.sheen(34, 38, 6, 3)


@icon("blackhole")
def _blackhole(p):
    # A BLACK DISC INSIDE A CONCENTRIC FIRE RING, drawn flat-on rather than as a tilted saucer.
    #
    # The tilted version is the more accurate picture and it was the wrong one: a wide gold ellipse
    # with a dark ball bulging out of the top of it reads as a hat -- brim, crown -- or as a flying
    # saucer, and at 40px it read as nothing at all. Accuracy lost to silhouette, which is the
    # right way round for an icon.
    #
    # Flat-on, the shape is two concentric circles with a hard black hole punched through the
    # middle, and that is unambiguous. It is told apart from `void`, its nearest neighbour in the
    # zone list, by being RINGED AND HOT: void is a cold purple disc with nothing round it, this is
    # a black pupil inside gold. Colour alone would not be enough -- the ring is the silhouette
    # difference too, because it makes this the only perfectly circular haloed icon in the set.
    #
    # The horizon is SPACE_D rather than INK on purpose: INK is contour colour and is protected
    # from every shading pass, so an INK ball would sit dead flat inside its own outline.
    p.circle(50, 50, 45, ORANGE)
    p.circle(50, 50, 39, GOLD)
    p.circle(50, 50, 32, SUNNY)
    # the ring is a RING, so the fire has an inner edge to be inked against
    p.circle(50, 50, 26, SPACE_D)
    p.circle(50, 50, 20, shade(SPACE_D, -0.6))               # a darker pit inside the dark
    # Two lensing streaks across the ring, tangential rather than radial: light going AROUND the
    # hole is the one piece of physics worth keeping, and it also stops the ring reading as a
    # plain donut.
    p.arc(50, 50, 35, 35, 200, 250, 4, CREAM)
    p.arc(50, 50, 35, 35, 20, 70, 4, CREAM)
    for sx, sy, sr in ((14, 22, 3.0), (88, 30, 2.6), (80, 86, 2.4)):
        p.circle(sx, sy, sr, WHITE)                          # stars, so it reads as space
    p.sheen(34, 26, 7, 3.4)


@icon("multiverse")
def _multiverse(p):
    # AN ARCH. This is the only icon in the set with a flat bottom, and that is the whole point:
    # in a scrolling list of round things a doorway is spotted before it is identified. The brief
    # asked for a spiral portal, so the spiral is inside the arch rather than instead of it -- a
    # bare pinwheel was drawn first and it was a second galaxy.
    #
    # Two small worlds ride the frame, one popping out of the top of the mouth: the zone is called
    # Multiverse and one swirl is a singular thing. They also break the arch's outline so it does
    # not read as a plain gravestone.
    p.poly([(10, 92), (10, 44), (50, 6), (90, 44), (90, 92)], PURPLE_D)      # the frame
    p.poly([(20, 92), (20, 48), (50, 20), (80, 48), (80, 92)], SPACE)        # the mouth
    for i, c in enumerate((BUBBLEGUM, LAVENDER, AQUA)):                      # the swirl in it
        _arm(p, 50, 58, 90 + i * 120, 128, 6, 27, 8.5, 3.0, 1.0, 0, [c] * 7)
    p.circle(50, 58, 7, CREAM)
    p.rrect(6, 86, 94, 96, 5, PURPLE)                        # a plinth, to sit the arch on
    p.circle(50, 14, 9, SUNNY)                               # a world coming through the top
    p.circle(84, 40, 7, TEAL)
    p.sheen(28, 40, 5, 10, deg=-40)


@icon("nebula")
def _nebula(p):
    # A bumpy gas cloud with wisps trailing off two corners, so the contour is knobbly where every
    # other cosmic icon's is smooth. Colour goes magenta at the top, teal at the bottom, because a
    # single-hue cloud is a blob and the two-temperature version is what a nebula photograph
    # actually looks like.
    #
    # The stars are ON the cloud and one is over its edge. Stars floating in the empty corners
    # were tried and they stretched the icon's bounding box, which drags the pipeline's volume
    # ramp across empty space and leaves the cloud itself flat.
    for cx, cy, rx, ry in ((34, 40, 26, 22), (66, 36, 24, 20), (52, 60, 30, 24),
                           (26, 62, 18, 15), (74, 64, 19, 16)):
        p.ellipse(cx, cy, rx, ry, PURPLE_D)
    p.poly([(8, 30), (26, 24), (22, 44)], PURPLE_D)          # wisps
    p.poly([(94, 52), (76, 44), (82, 66)], PURPLE_D)
    for cx, cy, rx, ry in ((38, 36, 18, 14), (64, 34, 16, 13), (52, 50, 20, 15)):
        p.ellipse(cx, cy, rx, ry, BUBBLEGUM)
    p.ellipse(50, 68, 24, 14, TEAL)
    p.ellipse(34, 66, 12, 9, AQUA)
    p.ellipse(50, 44, 13, 9, PINK)
    for sx, sy, so in ((32, 30, 10), (70, 52, 8), (52, 74, 7), (78, 30, 6)):
        p.star(sx, sy, so, so * 0.34, 4, CREAM, rot=-90)
    p.sheen(30, 28, 6, 3)


@icon("wormhole")
def _wormhole(p):
    # A funnel, built as eight ellipses that shrink and walk down and to the right. The union of
    # them is a horn, which is the one silhouette in this file that has a wide end and a point --
    # every other cosmic icon is symmetric. The offset matters more than the shrink: rings that
    # only shrink read as a flat target, rings that also drift read as a tunnel going away.
    #
    # The colour marches AQUA -> BLUE -> PURPLE -> SPACE_D so the far end is the darkest thing in
    # the picture, which is the second depth cue and the one that still works at 40px when the
    # individual rings have merged.
    cols = [AQUA, SKY, BLUE, shade(BLUE, -0.30), PURPLE, PURPLE_D, PLUM, SPACE_D]
    for i, c in enumerate(cols):
        t = i / (len(cols) - 1.0)
        p.ellipse(46 + 22 * t * t, 26 + 54 * t, 44 - 38 * t, 17 - 13.6 * t, c)
    p.inkline([(4, 28), (52, 78)], 2.2)                      # the two walls of the throat, so the
    p.inkline([(88, 28), (76, 68)], 2.2)                     # rings read as one solid pipe
    p.circle(70, 82, 3.4, WHITE)                             # something falling in
    p.circle(60, 68, 2.4, WHITE)
    p.sheen(30, 22, 8, 3.4)


@icon("quantum")
def _quantum(p):
    # The classic atom: a fat nucleus and three tilted orbits. The orbits are drawn as closed
    # chains of points rather than with `p.arc`, because arc cannot tilt and an untilted set of
    # three ellipses is a bullseye.
    #
    # Each orbit gets its own hue and its own electron. One colour for all three was tried and the
    # crossings became impossible to follow -- the eye needs to know which ring goes behind.
    for deg, col in ((0, AQUA), (60, LAVENDER), (120, MINT)):
        ca, sa = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        pts = []
        for i in range(41):
            a = 2 * math.pi * i / 40
            x, y = 42 * math.cos(a), 16 * math.sin(a)
            pts.append((50 + x * ca - y * sa, 50 + x * sa + y * ca))
        p.line(pts, 5.5, col)
    p.circle(50, 50, 16, TEAL)
    p.circle(44, 45, 6, AQUA)
    p.circle(56, 54, 5, shade(TEAL, -0.28))
    for deg, col in ((0, AQUA), (60, LAVENDER), (120, MINT)):
        ca, sa = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        x, y = 42 * math.cos(math.radians(35)), 16 * math.sin(math.radians(35))
        p.circle(50 + x * ca - y * sa, 50 + x * sa + y * ca, 6.5, CREAM)
    p.sheen(38, 38, 5, 2.6)


@icon("dream")
def _dream(p):
    # A pastel thought bubble with two trailing puffs. It shares the cloud family with `nebula`
    # and is separated from it three ways: the trailing puffs give it a diagonal read rather than
    # a centred one, the lobes are circles of nearly one size so its edge is even where nebula's
    # is ragged, and the palette is unsaturated where nebula is at full chroma.
    #
    # A crescent and a star sit inside the bubble. An empty bubble is a cloud, and there is
    # already a cloud in this set.
    for cx, cy, cr in ((30, 46, 20), (52, 34, 22), (74, 46, 19), (60, 58, 20), (36, 60, 17)):
        p.circle(cx, cy, cr, shade(LAVENDER, 0.42))
    p.circle(26, 82, 9, shade(LAVENDER, 0.42))               # the trail down to the thinker
    p.circle(13, 93, 5, shade(LAVENDER, 0.42))
    p.circle(52, 46, 27, shade(BUBBLEGUM, 0.46))             # a warmer inside
    p.circle(58, 40, 15, CREAM)                              # the crescent, cut from a cream disc
    p.circle(66, 34, 12, CLEAR)
    p.star(38, 56, 11, 4, 4, SUNNY, rot=-90)
    p.circle(70, 58, 4.5, AQUA)
    p.sheen(30, 34, 7, 3.4)


@icon("mirror")
def _mirror(p):
    # A hand mirror, tilted, with the glass drawn as two hard diagonal shine bars on a cold blue
    # face. The bars are the whole trick: a plain pale oval is a plate, and two bars at a shared
    # angle say "glass" instantly -- it is the same shorthand a comic uses for a window.
    #
    # The handle points down-left and is short and fat. A long thin handle disappeared at 40px and
    # the icon became an egg.
    p.rot_poly([(38, 62), (58, 62), (52, 96), (32, 96)], 46, 78, 14, GOLD_D)   # handle
    p.circle(46, 74, 11, GOLD_D)                                               # the collar
    p.ellipse(54, 42, 38, 40, GOLD)                                            # frame
    p.ellipse(54, 42, 29, 31, shade(SKY, -0.22))                               # glass
    p.ellipse(54, 42, 29, 31, shade(BLUE, -0.10))
    p.rot_poly([(34, 12), (48, 12), (30, 74), (16, 74)], 54, 42, 0, shade(AQUA, 0.30))
    p.rot_poly([(56, 14), (64, 14), (46, 72), (38, 72)], 54, 42, 0, shade(AQUA, 0.30))
    p.poly([(30, 14), (78, 14), (82, 24), (26, 24)], CLEAR)   # keep the bars inside the glass by
    p.poly([(26, 62), (82, 62), (78, 72), (30, 72)], CLEAR)   # cutting their ends off flat
    p.ellipse(54, 42, 29, 31, CLEAR) if False else None       # (kept: see note below)
    p.star(76, 20, 10, 3.6, 4, CREAM, rot=-90)                # the glint
    p.sheen(40, 26, 6, 3)


@icon("void")
def _void(p):
    # Emptiness, not a hole with a machine in it. Three angular bites are torn out of the rim, so
    # the contour has hard corners where `blackhole`'s is a smooth saucer and `singularity`'s is a
    # spike. There is deliberately NO bright ring anywhere -- the ring is blackhole's entire
    # identity and giving the void one would make them the same icon in two colours.
    #
    # The disc is not flat black, and the first version made it far too nearly so: three deep
    # violets stacked inside a black contour came out as one muddy lump with no readable edge, and
    # the three torn bites -- meant to be the silhouette cue -- vanished into it. The fix is
    # CONTRAST INSIDE THE SHAPE rather than more shapes: a pale cold rim, a mid body and a genuinely
    # black core, so the eye sees a ring of dusk around a pit. Now the bites read, because there is
    # something light for them to be cut out of.
    p.circle(50, 52, 42, shade(LAVENDER, -0.34))             # the dusk rim, the lightest thing here
    p.circle(50, 52, 34, shade(PLUM, -0.30))
    p.circle(50, 52, 22, shade(SPACE_D, -0.35))              # the pit
    for a in (-150, -18, 96):
        _bite(p, 50, 52, a, 42, 13)
    # Three dim stars being pulled in, drawn small and cool. They are the only light in the icon
    # and they are what says "expanse" rather than "sphere".
    for sx, sy, sr in ((16, 20, 3.6), (88, 26, 3.0), (80, 88, 2.6)):
        p.circle(sx, sy, sr, STEEL)
    p.sheen(34, 30, 6, 3)


@icon("singularity")
def _singularity(p):
    # Not round: a four-point flash with four tails curling into it. That is the whole separation
    # strategy -- five of the six cosmic icons are discs, so the sixth is a spike, and it is
    # spotted in the list by shape alone.
    #
    # The tails are `_arm` chains running INWARD, each shrinking as it approaches the core, which
    # is the picture of light being dragged in. Straight spokes were tried and read as a sparkle
    # off a gem; the curl is what makes it a collapse.
    #
    # It also has to not be the currency set's `shard`, which is a four-point gold sparkle. This
    # one is violet-white, has the curled tails, and its long axis is vertical.
    p.star(50, 50, 46, 9, 4, LAVENDER, rot=-90)
    p.star(50, 50, 30, 7, 4, PURPLE, rot=-45)
    for rot in (0, 90, 180, 270):
        _arm(p, 50, 50, rot, 62, 40, 9, 6.5, 2.0, 1.0, 0,
             [AQUA, SKY, LAVENDER, LAVENDER, BUBBLEGUM, CREAM])
    p.circle(50, 50, 13, CREAM)
    p.circle(50, 50, 7, WHITE)
    p.sheen(44, 42, 4, 2)


@icon("absolute")
def _absolute(p):
    # The last zone, and the only austere thing in the file: a white prism on a gold plinth, two
    # visible faces and one hard edge. Everything else in the set is a colourful object; this one
    # earns its place by being the one that is NOT, which is what makes it read as the end of a
    # climb rather than as another planet.
    #
    # The faces are cream and steel rather than white and grey. Two neutrals let the pipeline's
    # volume ramp do the work; pure white leaves nothing for the ramp to darken and the prism came
    # out as a flat paper triangle.
    #
    # THE PLINTH AND THE VERTICAL RIDGE ARE BOTH GONE, and that is the entire fix. Two attempts
    # drew a pale triangle standing on a horizontal gold bar with a line up its middle, and that is
    # a SAILBOAT -- bar reads as hull, triangle as sail, ridge as mast. Widening the base made it a
    # broader sail. The read does not come from any one of the three, it comes from the arrangement,
    # so no adjustment to them could ever have worked.
    #
    # What is left is the triangle alone, TILTED, floating, drawn flat-on as nested plates. Nothing
    # is under it and nothing runs up its centre, so there is no hull and no mast for the eye to
    # find. The tilt does the rest: a boat's sail is upright by definition, and a leaning triangle
    # cannot be one. It stays the austere one in the file -- neutral plates, gold trim, no scenery.
    for pts, col in (
        ([(50, 4), (96, 84), (4, 84)], GOLD),                # the trim, showing as a border
        ([(50, 13), (88, 79), (12, 79)], CREAM),             # the plate
        ([(50, 27), (76, 72), (24, 72)], STEEL_D),           # the inner void
        ([(50, 38), (67, 67), (33, 67)], SUNNY),             # the core
    ):
        p.rot_poly(pts, 50, 56, 13, col)
    p.rot_poly([(50, 13), (68, 45), (50, 50), (32, 45)], 50, 56, 13, WHITE)  # apex glint
    for sx, sy, so in ((18, 26, 8), (84, 40, 7), (74, 14, 5)):
        p.star(sx, sy, so, so * 0.3, 4, GOLD, rot=-90)       # three sparks, no more
    p.sheen(38, 28, 4, 9, deg=-62)
