"""
set_relic.py -- the ten collection-relic forms (ROADMAP 30.2).

Icon bodies. Each draws into a 0..100 box with the shared `Pen`; the lighting, the contour and the
gloss are added afterwards by `iconkit.render` and must NOT be drawn here -- see iconkit's header.

THE ONE RULE: never ask a primitive for a stroke. The silhouette is derived from the finished
colour layer, so a stroke here becomes an internal ring around every shape instead of one contour
around the icon. Deliberate internal linework goes through `p.inkline`.

WHY THIS SET IS DRAWN IN GREYSCALE, WHICH NO OTHER SET IS
----------------------------------------------------------
These ten are rendered ONCE and drawn TWO HUNDRED times. Every one of the twenty zone sets shows
the same ten pictures tinted to its own palette through `ImageColor3`, which is what turns 200
relics into 10 uploads -- the whole economics of the row.

`ImageColor3` MULTIPLIES. That is the constraint the entire file is shaped by:

  * tint x white = the tint, at full strength. So the art has to be near-white.
  * tint x a coloured drawing = mud. A gold coin tinted Forest green comes out olive-brown, and
    every one of the twenty zones would get its own separate wrong colour.
  * tint x ink = ink. Dark stays dark whatever it is multiplied by, which is why the contour and
    the internal linework survive tinting untouched and are doing MORE work here than in any
    other set -- they are the only marks guaranteed to look the same in all twenty zones.

So the palette below is a value ramp from white to mid-grey and nothing else. Contrast inside a
form has to come from VALUE, because hue is not ours to spend: at the tinted end a 255 face beside
a 165 face still reads as a lit face beside a shaded one, where two different hues would just read
as a mistake.

Sixty per cent grey is the floor. Below that a face survives the multiply as a smudge -- the tint
itself is only guaranteed to clear luminance 0.42 (`GameConfig.RelicTintMinLuminance`), and 0.42 of
a 40% grey is not a shape any more.

WHAT THE TEN HAVE TO DO AS A GROUP
-----------------------------------
A player learns TEN SHAPES, not two hundred items: the picture says the rarity (a shard is always
Common, a sigil is always the capstone) and the tint says the zone. So these are judged on being
distinguishable FROM EACH OTHER at 40px far more than on being detailed -- which is why each one
is built from two or three big masses with one piece of internal linework, and why the four
Commons deliberately differ in gross silhouette (angular / pointed / round / soft) rather than in
their details.
"""

from iconkit import (  # noqa: F401  -- the palette is a namespace, not a checklist
    icon, Pen, INK, WHITE, shade,
)

import math  # noqa: F401


# ---------------------------------------------------------------- the value ramp
# Named by ROLE rather than by brightness, so a body says what a face is doing and the ramp can be
# retuned in one place. `L` is a lit face, `M` a turned one, `D` the deepest a face may go.

L = (255, 255, 255, 255)   # lit face -- takes the tint at full strength
M = (214, 216, 224, 255)   # a face turned away from the light
D = (172, 176, 190, 255)   # the deepest a face may go; 60% grey is the floor, see the header
X = (150, 154, 170, 255)   # recesses and undersides ONLY, never a whole face


def _turn(x, y, cx, cy, deg):
    """One point rotated about another, so a circle can be placed in a tilted frame."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return (cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca)


def _oval(cx, cy, rx, ry, n=32):
    """An ellipse emitted AS a polygon, so `rot_poly` can turn it."""
    return [
        (cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n))
        for i in range(n)
    ]


# ================================================================ THE FOUR COMMONS
# These four are the ones a player sees most and the ones most at risk of blurring together, so
# they are separated by GROSS SILHOUETTE first: angular, pointed, round, soft.


@icon("relic_shard")
def relic_shard(p):
    """A splinter of something that broke and kept its edge.

    Three facets, not one solid -- a crystal with a single flat face is a triangle, and a triangle
    at 40px is an arrow. The facet seams are inkline rather than a colour change because they must
    survive the tint in all twenty zones.
    """
    # the main body, leaning right: a long asymmetric quadrilateral
    p.poly([(46, 8), (70, 34), (62, 92), (38, 78)], L)
    # the turned face down the left, which is what gives it a thickness rather than a profile
    p.poly([(46, 8), (38, 78), (26, 60), (30, 30)], M)
    # a small chipped facet at the shoulder, so the top is not one clean point
    p.poly([(46, 8), (70, 34), (54, 36)], D)
    p.inkline([(46, 9), (54, 36), (62, 91)], 2.0)
    p.inkline([(30, 31), (54, 36)], 1.8)
    p.sheen(41, 30, 4.0, 11.0, deg=8)


@icon("relic_tooth")
def relic_tooth(p):
    """A shed molar: a wide rounded crown over two short roots.

    THE ROOTS GO UNDERNEATH, and getting that wrong twice is what this docstring is for. The first
    version stood two slim prongs on top of a tapering body and read as a tuning fork; the second
    kept them on top but made them stubby and read as a pair of trousers. Both are the same mistake
    -- limbs rising off a mass, which is iconkit's sixth trap -- and no adjustment to the prongs
    fixes it, because the read is the ARRANGEMENT.

    A crown on top with the roots hanging below is the shape every tooth in every icon set on earth
    uses, and it is not a coincidence: it is the only arrangement where the big rounded mass is
    doing the identifying and the small forked one is only a qualifier.
    """
    # the crown: wide, rounded, with a dip in the middle of the biting surface
    p.circle(34, 34, 20, L)
    p.circle(66, 34, 20, L)
    p.rrect(14, 30, 86, 58, 10, L)
    # the dip, which is what makes it a molar rather than a ball
    p.poly([(38, 14), (62, 14), (58, 24), (42, 24)], X)
    p.circle(50, 22, 9, X)
    # the two roots, hanging and splaying apart
    p.poly([(26, 54), (46, 54), (40, 90), (28, 86)], M)
    p.poly([(54, 54), (74, 54), (72, 86), (60, 90)], M)
    p.poly([(46, 54), (54, 54), (52, 74), (48, 74)], X)
    # the turned side of the crown
    p.poly([(86, 40), (80, 56), (62, 56), (68, 38)], M)
    p.inkline([(30, 56), (70, 56)], 1.8)
    p.sheen(34, 28, 6.0, 9.0, deg=-24)


@icon("relic_coin")
def relic_coin(p):
    """A struck token, seen at a tilt so it has an edge.

    THE EDGE IS THE ICON. A flat disc with a mark on it is a button, a badge or a full moon; the
    band of thickness under the face is what makes it a struck object you could pick up. The face
    is tilted to an ellipse for the same reason -- a perfect circle reads as a symbol rather than
    as a thing lying at an angle.
    """
    # the thickness, drawn first so the face sits on top of it
    p.ellipse(50, 58, 34, 25, X)
    p.rrect(16, 40, 84, 58, 4, X)
    # the struck face
    p.ellipse(50, 46, 34, 25, L)
    # the raised rim, as a ring of turned value inside the edge
    p.ellipse(50, 46, 28, 20, D)
    p.ellipse(50, 46, 25, 17.5, L)
    # THE STAMP IS INK, NOT A VALUE. Every other form in this set gets its internal read from the
    # value ramp, and on the coin that did not work: the mark sits on a face that the volume pass
    # has already lightened, so a `D` star on an `L` face was two neighbouring greys and the icon
    # read as a blank white lozenge at 40px. Ink is also the only mark guaranteed to survive the
    # tint unchanged, which matters most on the form whose whole content is one struck mark.
    p.star(50, 46, 15, 5.4, 4, INK, rot=-90)
    p.circle(50, 46, 3.4, L)
    # the milled edge
    for x in (20, 30, 50, 70, 80):
        p.inkline([(x, 44 + abs(x - 50) * 0.18), (x, 52 + abs(x - 50) * 0.18)], 1.5)
    p.sheen(36, 36, 6.0, 4.0, deg=-24)


@icon("relic_plume")
def relic_plume(p):
    """A feather too stiff to have come off anything living.

    Built as TWO OVERLAPPING VANES rather than as an outline around a shaft -- the trap here is
    iconkit's first one, that a shape whose return path runs near its outgoing path reads as a
    rope. Two solid masses with the shaft drawn ON them as linework cannot do that.
    """
    # the far vane (narrower, turned away) and the near one
    p.rot_poly([(50, 10), (68, 40), (62, 74), (50, 84)], 50, 46, 8, M)
    p.rot_poly([(50, 10), (32, 42), (38, 76), (50, 84)], 50, 46, 8, L)
    # the quill, below the vanes
    p.rot_poly([(47, 78), (53, 78), (52, 94), (48, 94)], 50, 46, 8, D)
    # the shaft, and the barb slits that make it a feather rather than a leaf
    p.inkline([(48, 14), (52, 88)], 2.0)
    for i in range(5):
        y = 26 + i * 12
        p.inkline([(49.5 + i * 0.4, y), (36 + i * 1.2, y + 7)], 1.5)
        p.inkline([(50.5 + i * 0.4, y + 5), (63 - i * 1.0, y + 11)], 1.5)


# ================================================================ THE THREE RARES


@icon("relic_horn")
def relic_horn(p):
    """A curved horn, still warm at the base.

    A SOLID TAPER ALONG A BEZIER, and it took three goes to get there. The first version swept the
    curve in polar coordinates and put the base at (1, 91) -- outside the 0..100 box -- so it
    rendered as a flat squiggle in the corner; a quadratic Bezier through three points that are
    visibly inside the box cannot do that.

    The second drew the taper as a RUN OF SHRINKING DISCS, which is the standard trick for a solid
    tapering curve and is wrong here: at a 16-unit radius the discs scallop the outer edge, the
    growth rings land in the scallops, and the whole thing reads as a caterpillar. So the body is
    ONE polygon walking the curve's two offset edges, which has a smooth silhouette by
    construction, and the rings are cut back to three.

    It is still built as a solid mass rather than as an outline -- iconkit's first trap, and the
    worst offender in this set: a tapering curve drawn as an outline is a hose every time.
    """
    BASE, CTRL, TIP = (28, 88), (24, 30), (78, 22)
    def at(t):
        u = 1 - t
        return (u * u * BASE[0] + 2 * u * t * CTRL[0] + t * t * TIP[0],
                u * u * BASE[1] + 2 * u * t * CTRL[1] + t * t * TIP[1])
    N = 26
    left, right, mids = [], [], []
    for i in range(N + 1):
        t = i / N
        cx, cy = at(t)
        nx, ny = at(min(t + 0.01, 1.0))
        px, py = at(max(t - 0.01, 0.0))
        dx, dy = nx - px, ny - py
        n = math.hypot(dx, dy) or 1
        ox, oy = -dy / n, dx / n
        rad = 15.0 * (1 - t) ** 0.78 + 0.8
        left.append((cx - ox * rad, cy - oy * rad))
        right.append((cx + ox * rad, cy + oy * rad))
        mids.append((cx, cy, ox, oy, rad))
    p.poly(left + list(reversed(right)), L)
    # the inside of the curve, turned away from the light -- the near half of the same band
    inner = [(cx + ox * rad * 0.05, cy + oy * rad * 0.05) for cx, cy, ox, oy, rad in mids]
    p.poly(inner + list(reversed(right)), M)
    # three growth rings, drawn ACROSS the taper
    for i in (5, 11, 17):
        cx, cy, ox, oy, rad = mids[i]
        p.inkline([(cx - ox * rad * 0.95, cy - oy * rad * 0.95),
                   (cx + ox * rad * 0.95, cy + oy * rad * 0.95)], 1.9)


@icon("relic_rune")
def relic_rune(p):
    """A tablet with one mark cut deep enough to outlast it.

    THE OUTLINE IS CHIPPED, and that is not decoration: a clean rounded rectangle with a symbol on
    it is a phone, a card or a sign at any size. Two bites out of the edge and a corner knocked off
    make it stone. The mark is a single angular glyph -- a curved one reads as a letter, and a
    letter reads as language the player is supposed to understand.
    """
    p.poly([(26, 12), (74, 16), (78, 62), (70, 88), (30, 84), (22, 44)], L)
    # a turned face down the right-hand third, so the slab has a thickness
    p.poly([(74, 16), (78, 62), (70, 88), (62, 86), (66, 60), (63, 15)], M)
    # the chips
    p.poly([(22, 44), (34, 40), (28, 54)], X)
    p.poly([(74, 16), (63, 15), (70, 26)], X)
    # THE CUT GLYPH, and the first version of it was a letter K -- which is the exact failure this
    # function's own docstring warns about, written and then walked into. A stem with two strokes
    # leaving the SAME side at mirrored angles is the Latin alphabet; a stem crossed by one chevron
    # that spans it, plus a mark that does not touch it, is a rune.
    p.inkline([(46, 24), (46, 74)], 3.4)
    p.inkline([(32, 40), (46, 30), (60, 40)], 3.0)
    p.inkline([(36, 62), (58, 62)], 2.8)
    p.inkline([(60, 50), (61, 51)], 4.0)


@icon("relic_vial")
def relic_vial(p):
    """A sealed vial whose contents have not settled.

    The liquid is drawn as a DARKER VALUE OF THE SAME RAMP rather than as its own colour, which is
    the file's rule paying off: in twenty zones this reads as twenty different liquids for free,
    where an authored green would be green in the Volcano set.
    """
    # body
    p.rrect(30, 38, 70, 88, 13, L)
    p.circle(50, 76, 20, L)
    # neck and stopper
    p.rrect(42, 18, 58, 42, 3, M)
    p.rrect(38, 8, 62, 22, 4, D)
    # the liquid, filling the lower two thirds, with a flat top. `X` rather than `D`: it is a
    # recess seen THROUGH glass, which is the one place this set spends its darkest value.
    p.circle(50, 76, 16.5, X)
    p.rrect(34, 58, 66, 80, 6, X)
    # the meniscus, so the liquid has a surface rather than an edge
    p.inkline([(34, 58), (66, 58)], 2.0)
    # the seam where the stopper meets the neck
    p.inkline([(39, 21), (61, 21)], 1.8)
    p.sheen(39, 50, 4.0, 9.0, deg=-8)


# ================================================================ THE TWO EPICS


@icon("relic_idol")
def relic_idol(p):
    """A carved head, facing you.

    THIS IS THE ONE ICON IN THE SET ALLOWED A FACE. iconkit's second trap is that a face replaces
    whatever it is drawn on -- two dark discs in a pale oval are read as eyes before anything else
    -- and here that read is the object: an idol IS a carved face. The rest of the set therefore
    has no paired dark discs anywhere, so this one cannot be confused with any of them.

    The eyes are RECESSES rather than `p.eyes`, which draws pupils and catchlights: a carving that
    makes eye contact is a character, and a character is a pet, not a relic.
    """
    # the block: wider at the crown, narrowing to a chin, on a plinth
    p.poly([(26, 18), (74, 18), (70, 62), (50, 82), (30, 62)], L)
    p.rrect(32, 78, 68, 92, 3, M)
    # the headdress, which is what makes it carved rather than a person
    p.poly([(24, 26), (76, 26), (72, 12), (28, 12)], M)
    p.poly([(28, 12), (72, 12), (66, 4), (34, 4)], D)
    # the turned side of the face
    p.poly([(74, 18), (70, 62), (50, 82), (58, 62), (60, 20)], M)
    # sunken eyes and a cut mouth -- recesses, not features
    p.rot_poly(_oval(40, 40, 7.5, 5.0), 40, 40, -8, X)
    p.rot_poly(_oval(60, 40, 7.5, 5.0), 60, 40, 8, X)
    p.inkline([(40, 40), (41, 41)], 4.2)
    p.inkline([(59, 40), (60, 41)], 4.2)
    p.inkline([(42, 62), (58, 62)], 2.6)
    p.inkline([(50, 44), (50, 56)], 1.8)


@icon("relic_core")
def relic_core(p):
    """A core held in a claw mount -- it draws light in and gives a little of it back.

    Four attempts, and each one failed for a reason worth keeping, because they are all the same
    reason wearing different clothes: **the contour is a union of the whole layer, so anything that
    touches the orb stops being a separate object and becomes part of its outline.**

      1. Grey wedges cut into the orb -- read as a cracked egg.
      2. Ink lines radiating from an off-centre point -- read as a cracked plate.
      3. Claws drawn behind the orb -- hidden by the orb entirely; no mount at all.
      4. Claws drawn in front, ending below the orb's equator -- merged into one blob and the icon
         read as a mushroom.

    What fixes it is not more contrast, it is SILHOUETTE: the claw tips are carried above the orb's
    widest point with clear air between them and the orb, so the mount is visible in the outline
    itself and survives being drawn at 40px in a grey that the tint may darken. Same lesson the
    coin's stamp taught one form over -- at this size a shape either changes the outline or it is
    not there.
    """
    # the two claws, tips above the orb's equator and standing clear of it on both sides
    p.poly([(14, 30), (26, 26), (36, 68), (22, 74)], M)
    p.poly([(86, 30), (74, 26), (64, 68), (78, 74)], M)
    p.inkline([(15, 31), (25, 27)], 1.8)
    p.inkline([(85, 31), (75, 27)], 1.8)
    # the plinth, wider than the claws so it reads as what they stand on
    p.rrect(24, 76, 76, 92, 6, D)
    p.rrect(30, 70, 70, 80, 4, M)
    p.inkline([(26, 79), (74, 79)], 1.9)
    # the orb, last and smaller than the span of the claws, so the air between them stays air
    p.circle(50, 46, 24, L)
    p.poly(_oval(50, 46, 24, 24), D)
    p.circle(45, 41, 22, L)
    p.sheen(39, 33, 5.5, 8.5, deg=-30)


# ================================================================ THE CAPSTONE


@icon("relic_sigil")
def relic_sigil(p):
    """The mark a place leaves on whatever survives it.

    Legendary in fifteen zones and MYTHIC in five, and it is the same drawing in both -- the tile's
    rarity frame and the tint already say which one is in your hand, and a second Mythic-only
    picture would have been an eleventh upload for five relics.

    A MEDALLION RATHER THAN A STAR. A bare star is the most over-used shape in the genre and this
    set already has one struck into the coin; the ring, the points and the centre stone together
    make a silhouette no other form here comes close to, which is what a capstone needs at 40px.
    """
    # the eight radiating points, longest at the cardinals
    for i in range(8):
        a = math.radians(i * 45 - 90)
        long = (i % 2 == 0)
        r0, r1 = 26, (46 if long else 38)
        w = 9 if long else 6
        p.poly([
            (50 + r0 * math.cos(a - w * 0.012), 46 + r0 * math.sin(a - w * 0.012)),
            (50 + r1 * math.cos(a), 46 + r1 * math.sin(a)),
            (50 + r0 * math.cos(a + w * 0.012), 46 + r0 * math.sin(a + w * 0.012)),
        ], M if long else D)
    # the disc, and a raised inner ring on it
    p.circle(50, 46, 28, L)
    p.circle(50, 46, 22, M)
    p.circle(50, 46, 18, L)
    # the centre stone, faceted so it catches the eye first
    p.rot_poly([(50, 32), (62, 46), (50, 60), (38, 46)], 50, 46, 0, D)
    p.inkline([(50, 33), (50, 59)], 1.8)
    p.inkline([(39, 46), (61, 46)], 1.8)
    p.sheen(40, 34, 5.0, 8.0, deg=-28)
