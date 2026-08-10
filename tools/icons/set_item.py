"""
set_item.py -- things with character: weapons, prizes, weather, creatures.

Icon bodies. Each draws into a 0..100 box with the shared `Pen`; the lighting, the contour and the
gloss are added afterwards by `iconkit.render` and must NOT be drawn here -- see iconkit's header.

THE ONE RULE: never ask a primitive for a stroke. The silhouette is derived from the finished
colour layer, so a stroke here becomes an internal ring around every shape instead of one contour
around the icon. Deliberate internal linework goes through `p.inkline`.

WHY THIS SET IS THE DENSE ONE
------------------------------
These eleven are the trophies, the loot and the pets -- the icons a player actually wants to look
at -- so they carry more internal detail than the currency or place sets do. The first pass was
three or four flat shapes each, which is a settings-menu pictogram; the reference this game is
built against is a vinyl collectible, and a collectible has THICKNESS: a blade has a bevel and a
fuller, a gift has a lid with a visible side, fire is three temperatures and not one. The rule
kept across the whole set is that detail must be *structural* -- a facet, a seam, a rim -- because
structure survives being drawn at 40px and texture does not.

Everything here is tilted rather than square-on wherever the object has an axis. A vertical sword
is a diagram of a sword; sixteen degrees of lean is a drawing of one. `p.rot_poly` does the work,
and `_turn` / `_oval` below exist so circles and ellipses can join the same rotation.
"""

from iconkit import (  # noqa: F401  -- the palette is a namespace, not a checklist
    icon, Pen,
    INK, WHITE, CREAM, GOLD, GOLD_D, ORANGE, BLUE, SKY, GREEN, GREEN_D, RED, PURPLE, PURPLE_D,
    PINK, GREY, MINT, SUNNY, BUBBLEGUM, LAVENDER, AQUA, PEACH, CORAL, BROWN, BROWN_D, STEEL,
    STEEL_D, TEAL, PLUM, shade,
)

import math  # noqa: F401


# ---------------------------------------------------------------- local helpers
# `Pen.rot_poly` turns a polygon, which covers most of a tilted object -- but not the circles and
# ellipses in it. These two close that gap: `_turn` rotates a single point so `p.circle` can be
# placed in the tilted frame, and `_oval` emits an ellipse AS a polygon so `rot_poly` can turn it.
# They are three lines each and they are the difference between a sword that leans and a sword
# whose blade leans while its pommel stays put.


def _turn(x, y, cx, cy, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return (cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca)


def _oval(cx, cy, rx, ry, n=32):
    return [
        (cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n))
        for i in range(n)
    ]


def _scale(pts, k, cx=50.0, cy=50.0):
    """A polygon shrunk toward a point -- how the nested flame and bolt layers are derived.

    Drawing each inner layer by hand meant re-deriving a silhouette that already existed, and the
    hand-drawn inner shape never quite echoed the outer one, so the layers read as separate objects
    instead of as one object seen at three temperatures.
    """
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]


# ---------------------------------------------------------------- weapons and prizes


@icon("sword")
def _sword(p):
    """A hero's greatsword: the blade is WIDE and the crossguard is absurd.

    The old one was a letter opener -- a straight steel wedge, a thin bar, a stick. Three changes
    make it read as a cartoon weapon. The blade swells outward on its way UP and only then snaps to
    a point, which is the proportion every toy sword uses and the opposite of a real one. The guard
    is a fat capsule two thirds the width of the whole box with a ball on each end, because on a
    collectible the guard is the part that says "weapon" from across the room. And the whole thing
    leans sixteen degrees: a vertical sword sits in the icon like a ruler.

    The blade is split into a lit left face and a shadowed right face with an ink fuller down the
    middle, which is the cheapest possible way to say "this has a cross-section". A three-facet
    blade was tried and the third facet was a grey smear at 40px.
    """
    C, D = 50.0, 54.0          # the pivot everything leans about
    T = 16.0                   # lean, degrees

    blade = [(50, 11), (65, 29), (63, 58), (37, 58), (35, 29)]
    p.rot_poly(blade, C, D, T, STEEL_D)
    p.rot_poly([(50, 11), (35, 29), (37, 58), (48, 58), (48, 27)], C, D, T, STEEL)
    p.rot_poly([(50, 11), (39, 25), (41, 57), (45, 57), (45, 24)], C, D, T, shade(STEEL, 0.55))

    # the fuller. One line, generous width, so it is still a line and not a hairline at HUD size.
    p.inkline([_turn(50, 24, C, D, T), _turn(50, 56, C, D, T)], 3.0)

    # the crossguard: ball, bar, ball, with a darker underside so it has a bottom edge
    gl, gr = _turn(19, 62, C, D, T), _turn(81, 62, C, D, T)
    p.capsule(gl[0], gl[1], gr[0], gr[1], 15, GOLD)
    ul, ur = _turn(22, 67, C, D, T), _turn(78, 67, C, D, T)
    p.capsule(ul[0], ul[1], ur[0], ur[1], 6, GOLD_D)
    for bx in (17, 83):
        b = _turn(bx, 60, C, D, T)
        p.circle(b[0], b[1], 8, GOLD)
    # the boss: a red stone where guard meets blade, which is the eye the whole icon reads from
    b = _turn(50, 62, C, D, T)
    p.circle(b[0], b[1], 9, GOLD_D)
    p.circle(b[0], b[1], 5.5, CORAL)
    p.sheen(b[0] - 1.6, b[1] - 1.8, 2.4, 1.5)

    # the grip, bound with three wraps
    h0, h1 = _turn(50, 70, C, D, T), _turn(50, 82, C, D, T)
    p.capsule(h0[0], h0[1], h1[0], h1[1], 14, BROWN)
    for wy in (72, 76, 80):
        a = _turn(43, wy, C, D, T)
        b = _turn(57, wy, C, D, T)
        p.inkline([a, b], 2.4)

    # the pommel, jewelled
    q = _turn(50, 89, C, D, T)
    p.circle(q[0], q[1], 9.5, GOLD)
    p.circle(q[0], q[1], 5, AQUA)
    p.sheen(q[0] - 1.6, q[1] - 2.0, 2.6, 1.6)


@icon("crown")
def _crown(p):
    """Five points, a band you could stand on, and gems big enough to count.

    The old crown was a gold zigzag with three dots on it. What was missing was the BAND -- on a
    real crown the band is the heavy part, and drawing it as the same gold as the points made the
    whole thing one flat sheet. Here the band is a deeper gold, separated by a full-width ink line,
    which instantly reads as two pieces of metal rather than one silhouette.

    Each point wears a ball and the band wears three cut gems, alternating hue so the middle one is
    the focus. Two sparkles sit off the outer points; they are outside the crown's own mass on
    purpose, because a sparkle drawn on top of gold is invisible and a sparkle drawn in the empty
    corner is what says "treasure". The whole crown leans four degrees -- any more and the band
    stopped reading as horizontal.
    """
    C, D, T = 50.0, 58.0, -4.0

    body = [(10, 70), (13, 27), (30, 52), (50, 15), (70, 52), (87, 27), (90, 70)]
    p.rot_poly(body, C, D, T, GOLD)
    # facet creases dropping from each valley to the band: the only thing that gives the points
    # any interior at all, and they cost one line each.
    for vx in (30, 70):
        a = _turn(vx, 53, C, D, T)
        b = _turn(vx + (2 if vx < 50 else -2), 68, C, D, T)
        p.inkline([a, b], 2.6)

    band = [(9, 66), (91, 66), (91, 86), (9, 86)]
    p.rot_poly(band, C, D, T, GOLD_D)
    p.inkline([_turn(9, 67, C, D, T), _turn(91, 67, C, D, T)], 3.0)

    # balls on the points
    for bx, by, col in ((13, 25, AQUA), (50, 14, CORAL), (87, 25, AQUA)):
        b = _turn(bx, by, C, D, T)
        r = 7.5 if bx == 50 else 6.0
        p.circle(b[0], b[1], r, col)
        p.sheen(b[0] - r * 0.3, b[1] - r * 0.35, r * 0.34, r * 0.22)

    # cut stones in the band, drawn as diamonds so they are not three more circles
    for gx, col in ((26, MINT), (50, CORAL), (74, LAVENDER)):
        s = 8.0 if gx == 50 else 6.5
        p.rot_poly([(gx, 76 - s), (gx + s, 76), (gx, 76 + s), (gx - s, 76)], C, D, T, col)
        g = _turn(gx - s * 0.25, 76 - s * 0.3, C, D, T)
        p.sheen(g[0], g[1], s * 0.28, s * 0.18)

    p.star(15, 12, 7, 2.6, 4, CREAM, rot=-90)
    p.star(89, 46, 5.5, 2.0, 4, CREAM, rot=-90)


@icon("bolt")
def _bolt(p):
    """Lightning at three temperatures, with the spark trail it threw off.

    A single flat zigzag is a keyboard symbol. Nesting two shrunken copies of the same silhouette
    inside it -- orange rind, yellow body, white-hot core -- turns it into something that is
    glowing rather than something that is yellow, and because the inner shapes are derived from the
    outer one by `_scale` they echo it exactly instead of being three different zigzags.

    The bolt is fattened at the shoulders relative to the old one so the core layer still has room
    to exist at 40px, and four sparks are scattered off its path. The sparks are separate islands,
    so the contour pass rings each one; that is the same trick `party` uses for confetti and it is
    what sells motion in a still icon.
    """
    outer = [(63, 7), (24, 55), (46, 55), (33, 93), (78, 41), (55, 41), (70, 7)]
    p.poly(outer, ORANGE)
    p.poly(_scale(outer, 0.80), SUNNY)
    p.poly(_scale(outer, 0.48), CREAM)
    # the fold where the upper arm turns into the lower one -- the bolt's one piece of anatomy
    p.inkline([(60, 16), (39, 44)], 2.6)

    for sx, sy, sr, col in ((14, 28, 5.0, SUNNY), (25, 79, 4.0, ORANGE), (85, 20, 3.6, CREAM)):
        p.circle(sx, sy, sr, col)
    p.star(88, 63, 7.0, 2.6, 4, SUNNY, rot=-90)


@icon("boom")
def _boom(p):
    """A comic-book impact: three burst layers that do not line up, plus flung debris.

    The old one was two concentric stars at the same rotation, which reads as a snowflake. Two
    things fixed it. The layers are rotated OFF each other so no spike ever sits inside another
    spike, which is what makes the edge look torn rather than symmetric. And the radiating ink
    cracks -- six short lines from the core outward -- are the actual comic-book convention for
    "this exploded"; without them a burst is just a spiky sun.

    The debris is deliberately unequal in size and unevenly placed. Four evenly spaced identical
    chips looked like a border, which is the one thing an explosion must not look like.
    """
    p.star(50, 50, 46, 21, 10, CORAL, rot=-93)
    p.star(50, 50, 36, 16, 10, RED, rot=-75)
    p.star(50, 50, 27, 12, 9, ORANGE, rot=-97)
    p.star(50, 50, 17, 8, 8, SUNNY, rot=-80)
    p.circle(50, 50, 8.5, CREAM)

    for a in range(6):
        ang = math.radians(-90 + a * 60 + 14)
        ca, sa = math.cos(ang), math.sin(ang)
        p.inkline([(50 + 11 * ca, 50 + 11 * sa), (50 + 24 * ca, 50 + 24 * sa)], 2.6)

    p.star(12, 22, 8, 3, 4, CORAL, rot=-90)
    p.star(90, 30, 6, 2.2, 4, SUNNY, rot=-90)
    p.circle(84, 86, 5.0, CORAL)
    p.circle(16, 84, 3.6, SUNNY)


@icon("fire")
def _fire(p):
    """Four temperatures and a pair of side licks, so the flame has a direction.

    The old flame was a symmetrical teardrop with two smaller teardrops in it -- a shape that never
    moves. Real cartoon fire is asymmetric: it has tongues peeling off one side, and the tip leans.
    The outer silhouette here has two licks curling out at different heights, and every inner layer
    is that same silhouette shrunk, so they nest the way heat actually does.

    The embers above are what make it read as burning rather than as a leaf; they are placed off
    the flame's own axis so they look thrown rather than stacked. An ink crease inside the flame
    was tried and rejected -- fire has no seams, and the line read as a crack in a gemstone.
    """
    outer = [
        (49, 5), (58, 21), (67, 13), (70, 34), (81, 49), (78, 72),
        (61, 92), (38, 93), (21, 77), (20, 53), (31, 37), (33, 17), (42, 27),
    ]
    p.poly(outer, shade(ORANGE, -0.22))
    p.poly(_scale(outer, 0.80, 50, 58), ORANGE)
    p.poly(_scale(outer, 0.56, 50, 64), SUNNY)
    p.poly(_scale(outer, 0.30, 50, 70), CREAM)

    p.circle(80, 22, 4.5, ORANGE)
    p.circle(20, 27, 3.4, SUNNY)
    p.circle(89, 41, 2.8, CREAM)


@icon("party")
def _party(p):
    """A popper mid-bang: striped cone, dark rim, white blast, confetti of four different shapes.

    The old one was a plain triangle with four identical dots. The cone now has a rim capsule at
    its mouth and two banded stripes running across its axis, which is what turns a triangle into
    an object -- a cone tapers, so the stripes must taper with it, and they are placed by walking
    along the cone's own axis rather than being drawn as horizontal bars.

    The confetti is the point of the icon, so it is four DIFFERENT shapes in four hues: a disc, a
    tumbling square, a star and a streamer. Identical dots read as a pattern; mixed shapes read as
    a mess flying through the air, which is what confetti is.
    """
    tip = (13, 92)
    mouth = (68, 39)
    ax, ay = mouth[0] - tip[0], mouth[1] - tip[1]
    n = math.hypot(ax, ay)
    px_, py_ = ax / n, ay / n              # along the cone
    qx, qy = -py_, px_                     # across it

    p.poly([tip, (56, 27), (81, 51)], CORAL)
    # the rim: a fat dark band across the mouth, which is what gives the cone an opening
    p.capsule(56, 27, 81, 51, 10, shade(CORAL, -0.3))
    p.inkline([(57, 29), (79, 50)], 2.6)

    for t, w in ((0.44, 7.0), (0.72, 11.0)):
        cx, cy = tip[0] + ax * t, tip[1] + ay * t
        p.capsule(cx - qx * w, cy - qy * w, cx + qx * w, cy + qy * w, 7, SUNNY)

    p.star(72, 33, 15, 6, 8, CREAM, rot=-90)

    p.circle(88, 16, 6.0, MINT)
    p.rot_poly([(90, 40), (96, 46), (90, 52), (84, 46)], 90, 46, 0, AQUA)
    p.star(64, 10, 7.5, 3.0, 5, BUBBLEGUM, rot=-90)
    p.capsule(74, 20, 82, 8, 5, LAVENDER)
    p.circle(94, 66, 4.4, SUNNY)


# ---------------------------------------------------------------- weather


@icon("rainbow")
def _rainbow(p):
    """Six bands, and a cloud puff sitting on each foot.

    An arc alone floats -- there is nothing telling you which way is up or what it is standing on.
    The clouds are the fix, and they do double duty: they anchor the arch and they give the icon
    two big rounded masses at the bottom, which is the weight the house style wants and which six
    thin arcs cannot supply on their own.

    Six hues is more colours than any other icon here uses, and that is fine -- a rainbow is the
    one object whose whole identity IS the sequence. What is not fine is ink between the bands:
    that was tried, and at 40px the black lines ate more width than the colours did, so the bands
    are separated by their own contrast alone and each is kept fat enough to survive.
    """
    for i, col in enumerate((CORAL, ORANGE, SUNNY, MINT, AQUA, LAVENDER)):
        p.arc(50, 74, 44 - i * 6.5, 44 - i * 6.5, 180, 360, 6.5, col)

    for side in (-1, 1):
        bx = 50 + side * 34
        p.circle(bx - side * 10, 83, 8.0, CREAM)
        p.circle(bx, 77, 10.5, CREAM)
        p.circle(bx + side * 10, 83, 7.0, CREAM)
        p.sheen(bx - 3, 73, 4.0, 2.2)

    p.star(50, 14, 7.0, 2.6, 4, CREAM, rot=-90)
    p.star(16, 40, 5.0, 1.8, 4, CREAM, rot=-90)


@icon("sun")
def _sun(p):
    """A fat disc with a rim, ringed by kite rays and the small ones between them.

    Triangular rays give a sun a sawtooth edge, which is a sunburst pattern rather than a sun. The
    kite shape here -- wide at the base, a shoulder, then a point -- has a waist, so the rays look
    like they were drawn with a brush. Eight of them, with a bead in each gap, because eight rays
    alone left the diagonals empty.

    The disc gets an ink ring just inside its edge and a lighter core inside that. This is the one
    piece of internal line in the icon and it does all the work: without it the disc and the rays
    are one continuous yellow blob and the sun has no face at all.
    """
    for i in range(8):
        a = math.radians(i * 45)
        ca, sa = math.cos(a), math.sin(a)

        def rot(dx, dy):
            return (50 + dx * ca - dy * sa, 50 + dx * sa + dy * ca)

        p.poly([rot(24, -10), rot(33, -6), rot(46, 0), rot(33, 6), rot(24, 10)], GOLD)
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        p.circle(50 + 37 * math.cos(a), 50 + 37 * math.sin(a), 4.6, GOLD_D)

    p.circle(50, 50, 29, GOLD)
    p.arc(50, 50, 25.5, 25.5, 0, 360, 3.0, INK)
    p.circle(50, 50, 24, SUNNY)
    p.sheen(40, 40, 8.0, 5.0)


# ---------------------------------------------------------------- loot and creatures


@icon("gift")
def _gift(p):
    """A box with a LID, ribbon that wraps the corner, and a bow made of two real loops.

    The old gift was three flat rectangles and two circles, which is the shape of a present but not
    the object: nothing about it had thickness. The lid is now its own darker slab overhanging the
    box on both sides with an ink line under it, so you can see it is a separate piece that lifts
    off -- that overhang is the single change that made the icon read as a container.

    The bow loops are tilted ellipses with a darker ellipse punched into each, which is how you
    draw a hole in a shape that must not have a hole: a real transparent hole would be swallowed by
    the contour dilation, since anything narrower than the ink weight fills in solid. The ribbon is
    edged with ink down both sides rather than being a flat yellow stripe, which is what stops it
    from looking like a stripe painted ON the box.
    """
    p.rrect(17, 50, 83, 93, 6, CORAL)
    p.rrect(11, 34, 89, 55, 5, RED)
    p.rrect(13, 35, 87, 43, 4, shade(RED, 0.2))
    p.inkline([(12, 55), (88, 55)], 3.0)

    p.rrect(42, 36, 58, 93, 2, SUNNY)
    p.rrect(11, 41, 89, 51, 2, SUNNY)
    p.inkline([(42, 56), (42, 92)], 2.6)
    p.inkline([(58, 56), (58, 92)], 2.6)

    for side, ang in ((-1, -20), (1, 20)):
        cx = 50 + side * 19
        p.rot_poly(_oval(cx, 22, 16, 11), cx, 22, ang, SUNNY)
        p.rot_poly(_oval(cx, 22, 6.5, 4.2), cx, 22, ang, GOLD_D)

    p.circle(50, 28, 9, GOLD)
    p.circle(50, 28, 4.2, shade(GOLD, 0.35))
    p.sheen(47.5, 25.5, 3.0, 1.9)


@icon("paw")
def _paw(p):
    """A three-lobed pad, four tilted beans, side tufts, and ink between everything.

    Every pad still gets its own ink ring for the reason written on `luck`: pink on pink has no
    edge of its own, so without a ring the beans merge into the pad and the paw becomes a blob.
    What is new is that the main pad is no longer an ellipse -- it is an ellipse plus two bottom
    lobes, which is the actual shape of a paw pad and is the difference between "paw" and "flower".

    The outer beans are tilted away from centre, which is how toes actually splay; four beans all
    pointing straight up looked like a row of buttons. The two fur tufts on the sides break the
    silhouette so the contour pass gives the paw a ragged edge, and the small ink chevrons under
    the beans are the creases where the toes fold. Claws were tried and rejected -- this icon marks
    pets, and claws made it read as a threat.
    """
    for tx, ty, ang in ((17, 58, -30), (83, 58, 30)):
        p.rot_poly([(tx - 8, ty + 6), (tx, ty - 12), (tx + 8, ty + 6)], tx, ty, ang, BUBBLEGUM)

    p.ellipse(50, 68, 28, 22, INK)
    p.circle(33, 76, 13.5, INK)
    p.circle(67, 76, 13.5, INK)
    p.ellipse(50, 68, 25.4, 19.4, BUBBLEGUM)
    p.circle(33, 76, 10.9, BUBBLEGUM)
    p.circle(67, 76, 10.9, BUBBLEGUM)
    p.sheen(40, 60, 8.0, 4.6)

    for cx, cy, ang in ((21, 42, -26), (40, 25, -9), (60, 25, 9), (79, 42, 26)):
        p.rot_poly(_oval(cx, cy, 13.5, 15.5), cx, cy, ang, INK)
        p.rot_poly(_oval(cx, cy, 10.9, 12.9), cx, cy, ang, PINK)
        p.sheen(cx - 3, cy - 4, 3.6, 2.2)

    for cx, cy in ((32, 52), (50, 47), (68, 52)):
        p.inkline([(cx - 4, cy - 3), (cx, cy + 2), (cx + 4, cy - 3)], 2.4)


@icon("pet")
def _pet(p):
    """A face, because this is the one icon in the game that is allowed to look back at you.

    The old pet was a peach ellipse with two dots and a mouth -- correct, and completely blank. The
    things that make a cartoon creature cute are all cheap: eyes that are far too big for the head,
    a lighter muzzle patch so the mouth sits on something, blush, and inner ears in a second colour
    so the ears are not just peach spikes. `p.eyes` supplies the catchlights, and the pupils are
    shifted right by `look` so the creature is looking at something rather than through you.

    The two feet peeking out under the chin are what stop it from being a severed head, and the
    cowlick between the ears gives the silhouette an asymmetry to hang on. A full body was tried
    first and lost: at 40px the head shrank to nothing and the face -- the entire point -- died.
    """
    p.capsule(50, 33, 53, 21, 6, PEACH)
    p.circle(56, 20, 4.5, PEACH)

    for side in (-1, 1):
        ex = 50 + side * 26
        p.rot_poly([(ex - side * 10, 44), (ex + side * 6, 9), (ex + side * 18, 36)], ex, 34, 0, PEACH)
        p.rot_poly([(ex - side * 6, 41), (ex + side * 5, 18), (ex + side * 12, 35)], ex, 34, 0, CORAL)

    p.ellipse(34, 89, 10, 7, PEACH)
    p.ellipse(66, 89, 10, 7, PEACH)
    p.ellipse(50, 58, 31, 27, PEACH)

    p.ellipse(26, 66, 8, 5, PINK)
    p.ellipse(74, 66, 8, 5, PINK)
    p.ellipse(50, 71, 17, 12, CREAM)

    p.eyes(50, 52, 14, 8.5, look=1.6)
    p.rot_poly([(43, 64), (57, 64), (50, 73)], 50, 68, 0, INK)
    p.inkline([(50, 71), (50, 76)], 2.6)
    p.inkline([(41, 74), (45.5, 79), (50, 75.5), (54.5, 79), (59, 74)], 2.8)
