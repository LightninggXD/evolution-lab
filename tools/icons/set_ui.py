"""
set_ui.py -- the chrome the audit found still falling back to platform emoji.

Icon bodies. Each draws into a 0..100 box with the shared `Pen`; the lighting, the contour and the
gloss are added afterwards by `iconkit.render` and must NOT be drawn here -- see iconkit's header.

THE ONE RULE: never ask a primitive for a stroke. The silhouette is derived from the finished
colour layer, so a stroke here becomes an internal ring around every shape instead of one contour
around the icon. Deliberate internal linework goes through `p.inkline`.

Every icon here closes a specific hole found by a coverage audit of the interface: a glyph that
renders in a tile, a pill or a header and had no art, so it came out as whatever emoji font the
player's device happens to ship.
"""

from iconkit import (  # noqa: F401  -- the palette is a namespace, not a checklist
    icon, Pen,
    INK, WHITE, CREAM, GOLD, GOLD_D, ORANGE, BLUE, SKY, GREEN, GREEN_D, RED, PURPLE, PURPLE_D,
    PINK, GREY, MINT, SUNNY, BUBBLEGUM, LAVENDER, AQUA, PEACH, CORAL, BROWN, BROWN_D, STEEL,
    STEEL_D, TEAL, PLUM, shade,
)

import math  # noqa: F401


# ---------------------------------------------------------------- local shape helpers
# Three shapes in this file are needed more than once and are fiddly enough that hand-typing their
# vertices a second time would guarantee the two copies drift apart. They live here rather than in
# iconkit because nothing outside this file wants them.


def _leaf_pts(cx, cy, length, width, deg, steps=14):
    """A lens -- pointed at both ends, fattest in the middle -- laid along `deg`.

    An ellipse is the lazy leaf and it reads as a pill; the two points are what make the eye call
    it foliage. Returned as points rather than drawn so the caller can hand them to `poly` or
    shift them for a midrib.
    """
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    top, bot = [], []
    for i in range(steps + 1):
        t = i / float(steps)
        x = -length / 2.0 + length * t
        y = width * math.sin(math.pi * t)
        top.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
        bot.append((cx + x * ca + y * sa, cy + x * sa - y * ca))
    return top + bot[::-1]


def _z_pts(cx, cy, s):
    """A capital Z with real thickness, in units of `s`.

    Drawn as one closed outline rather than three bars: three overlapping rectangles leave notches
    at the joins that the contour pass happily finds and inks, which turns a Z into a small pile of
    unrelated marks at 40px.
    """
    raw = [
        (-1.00, -1.00), (1.00, -1.00), (-0.30, 0.58), (1.00, 0.58),
        (1.00, 1.00), (-1.00, 1.00), (0.30, -0.58), (-1.00, -0.58),
    ]
    return [(cx + x * s, cy + y * s) for x, y in raw]


def _medal(p, ribbon_a, ribbon_b, face, rim, pip):
    """THE medal, once, in whatever metal is asked for.

    `medal` in set_currency.py is the gold one and this is deliberately the same drawing: first,
    second and third sit in one leaderboard column, and three medals that disagree about their
    ribbon geometry read as three different awards rather than as a podium. Only the metal and the
    ribbon colours move. If the gold body over there changes shape, this changes with it.
    """
    p.poly([(28, 8), (46, 8), (56, 44), (38, 44)], ribbon_a)
    p.poly([(54, 8), (72, 8), (62, 44), (44, 44)], ribbon_b)
    p.circle(50, 64, 28, face)
    p.circle(50, 64, 20, rim)
    p.star(50, 64, 14, 6, 5, pip, rot=-90)


# ---------------------------------------------------------------- the icons


@icon("speed")
def _speed(p):
    """A winged running shoe, toe to the right, leaning into the run.

    One drawing has to serve the Speed upgrade tile and the 2x Speed game pass chip, so it cannot
    just be a shoe -- a shoe on a game pass reads as a cosmetic. The wing off the heel and the two
    motion bars behind it are what turn footwear into velocity, and they are sized so that if the
    shoe itself dissolves at 40px the swept diagonal still says "fast".

    The whole shoe is built flat and then tilted -12 degrees about the heel, which drops the toe
    and lifts the collar: a level shoe reads as a product photo, a tilted one reads as mid-stride.
    Drawing it pre-tilted was tried and every subsequent tweak had to be re-derived by hand.
    """
    cx, cy = 34, 60          # the pivot: roughly the heel, so tilting swings the toe down
    tilt = -12

    # MOTION BARS FIRST, so the shoe overlaps them rather than the other way round. They are fat
    # (7 units) because the contour pass grows every disconnected shape by 5 units on each side --
    # a hairline speed line comes back as a solid ink dash with no colour left in the middle.
    for y, x0, x1 in ((36, 4, 26), (52, 2, 20), (70, 8, 24)):
        p.rot_poly(
            [(x0, y - 3.5), (x1, y - 3.5), (x1 + 3, y), (x1, y + 3.5), (x0, y + 3.5)],
            cx, cy, tilt, AQUA,
        )

    # THE WING. Three feathers fanning back off the heel, longest on top. Feathers are lenses
    # rather than triangles: a triangle wing reads as a fin, and the game already has fins.
    for ln, wd, ang, col in ((30, 7.0, 196, CREAM), (26, 6.0, 214, SKY), (20, 5.0, 232, AQUA)):
        a = math.radians(ang)
        lx = 30 + (ln / 2.0) * math.cos(a)
        ly = 44 + (ln / 2.0) * math.sin(a)
        p.rot_poly(_leaf_pts(lx, ly, ln, wd, ang), cx, cy, tilt, col)

    # PROPORTION IS THE WHOLE FIX HERE. The first version spanned x 17..94 and y 32..74 -- more
    # than twice as wide as it was tall -- and a long thin tapered thing with a fin on the back is
    # a FISH. It read as one at every size. Nothing about the detail was wrong; the box was.
    #
    # Redrawn short and fat: the shoe now fills y 30..86 in about the same width, so the silhouette
    # is a chunky wedge rather than a sliver. Everything a cartoon sneaker exaggerates is
    # exaggerated -- a sole thick enough to have its own two layers, a heel counter that stands up
    # tall, and a big round toe rather than a taper to a point. A toe that comes to a point is the
    # other half of why it read as a fish.
    p.rot_poly([(16, 66), (84, 62), (92, 70), (90, 84), (24, 86), (13, 78)], cx, cy, tilt, CORAL)
    # the midsole: a pale band along the top of the sole, so the sole is two materials thick
    p.rot_poly([(15, 65), (84, 61), (90, 68), (18, 72)], cx, cy, tilt, CREAM)

    # THE UPPER. Tall heel counter at the left, a deep collar dip, and a fat rounded toe.
    p.rot_poly(
        [(19, 68), (20, 38), (26, 30), (38, 30), (46, 44), (58, 50), (76, 56), (88, 62), (84, 66)],
        cx, cy, tilt, BLUE,
    )
    p.rot_poly([(38, 30), (46, 44), (40, 46), (33, 34)], cx, cy, tilt, shade(BLUE, -0.18))  # collar
    # the toe cap, lighter, so the shoe reads as two-tone rather than as one blue slab
    p.rot_poly([(62, 51), (88, 62), (84, 66), (58, 56)], cx, cy, tilt, SKY)

    # laces: two ink bars across the instep. Three were tried and the middle one closed the gap
    # between the other two at 40px into a grey smear.
    for t in (0, 1):
        a0 = (34 + t * 10, 42 + t * 6)
        a1 = (46 + t * 10, 50 + t * 6)
        pa = _rot_pt(a0, cx, cy, tilt)
        pb = _rot_pt(a1, cx, cy, tilt)
        p.inkline([pa, pb], 3.2)


def _rot_pt(pt, cx, cy, deg):
    """One point through the same rotation `rot_poly` applies -- for linework that must land on an
    already-tilted shape. Without it the laces sit beside the shoe instead of on it."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    x, y = pt
    return (cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca)


@icon("warning")
def _warning(p):
    """A fat rounded hazard triangle under the pet Fuse row.

    The corners are cut rather than pointed. A true triangle's apex is a needle, the contour pass
    grows it into a spike, and at 40px the whole sign gains a horn -- clipping each corner into a
    short flat gives the dilation something blunt to grow around.

    The exclamation is INK, not a darker yellow: ink is the one thing the shading passes leave
    alone, so it stays the same weight on the lit top half and the shaded bottom half. Hazard
    stripes run along the base only. Stripes across the whole face were tried first and they fight
    the exclamation for the same real estate; along the bottom they read as a caution band.
    """
    tilt = 8
    body = [
        (50, 8), (57, 12), (92, 76), (90, 86), (82, 91),
        (18, 91), (10, 86), (8, 76), (43, 12),
    ]
    p.rot_poly(body, 50, 56, tilt, SUNNY)

    # the caution band across the base, and the diagonal stripes inside it. The stripes are drawn
    # as tilted quads clipped by eye to the band -- there is no clipping primitive here, so they
    # are simply short enough not to escape.
    p.rot_poly([(22, 76), (78, 76), (82, 86), (18, 86)], 50, 56, tilt, CREAM)
    for i in range(4):
        x = 24 + i * 14
        p.rot_poly([(x, 76), (x + 6, 76), (x - 2, 86), (x - 8, 86)], 50, 56, tilt, ORANGE)

    # the mark itself: a tapering bar over a fat dot, both well clear of the band
    p.rot_poly([(44, 28), (56, 28), (54, 58), (46, 58)], 50, 56, tilt, INK)
    ex, ey = _rot_pt((50, 68), 50, 56, tilt)
    p.circle(ex, ey, 6.0, INK)


@icon("sleep")
def _sleep(p):
    """Stacked Z's over a pillow, for the offline-earnings WELCOME BACK card.

    A cloud was the first instinct and it was wrong: a cloud plus Z's is the "daydream" idiom, and
    this card is about time spent away from the game, not about imagination. A pillow -- squashed,
    tufted at the corners, tipped 10 degrees -- says bed, and bed says the hours you were gone.

    The Z's climb up and to the right and grow as they go, which is the direction the eye already
    reads. Each one is an INK Z with a slightly smaller BLUE Z on top: the contour pass only inks
    the OUTER silhouette, so three pale letters lying on a pale pillow would have merged into it.
    The ink copy underneath is the same trick `luck` uses for its four touching leaves.
    """
    # the pillow, wider than it is tall, with a corner tuft at each end
    p.rot_poly(
        [(14, 56), (26, 48), (74, 48), (88, 56), (90, 74), (78, 84), (26, 84), (12, 74)],
        50, 66, -10, CREAM,
    )
    for tx, ty in ((16, 62), (86, 66)):
        cxx, cyy = _rot_pt((tx, ty), 50, 66, -10)
        p.circle(cxx, cyy, 7.0, shade(CREAM, -0.10))
    # one seam line so the pillow has a near face and a far face rather than being a beige blob
    sa = _rot_pt((24, 76), 50, 66, -10)
    sb = _rot_pt((78, 76), 50, 66, -10)
    p.inkline([sa, sb], 2.6)

    # the three Z's. Sizes 7 / 10.5 / 14 -- a ratio near 1.4 each step, enough that the smallest
    # still resolves at 40px but the stack is obviously a progression.
    for (zx, zy, zs) in ((32, 52, 7.0), (52, 34, 10.5), (76, 16, 14.0)):
        p.rot_poly(_z_pts(zx, zy, zs * 1.30), zx, zy, -14, INK)
        p.rot_poly(_z_pts(zx, zy, zs), zx, zy, -14, BLUE)


@icon("skull")
def _skull(p):
    """The boss-revive prompt: a cartoon skull, big cranium over a small jaw.

    Exaggerated the way the reference art exaggerates -- the cranium is roughly two thirds of the
    whole height and the jaw is a stub. A correctly proportioned skull reads as anatomy, which is
    the wrong register for a prompt that is meant to be exciting rather than grim.

    The sockets are huge tilted ellipses with a white catchlight inside each, which is what keeps
    it friendly-menacing: an empty black hole is gory, a black hole with a glint in it is a
    character. Teeth are ink gaps drawn onto the jaw rather than white blocks on a dark mouth,
    because the whole skull is one cream mass and a dark mouth would punch a hole in the middle of
    the silhouette that the eye reads as damage.
    """
    tilt = -9
    # cranium and jaw, both cream, deliberately touching so they contour as one head
    p.rot_poly(
        [(18, 46), (20, 24), (34, 10), (66, 10), (80, 24), (82, 46), (76, 62), (24, 62)],
        50, 44, tilt, CREAM,
    )
    p.rot_poly([(32, 58), (68, 58), (72, 78), (62, 88), (38, 88), (28, 78)], 50, 44, tilt, CREAM)
    # the cheek line: the one thing separating skull from jaw now that they are one mass
    ca = _rot_pt((28, 60), 50, 44, tilt)
    cb = _rot_pt((72, 60), 50, 44, tilt)
    p.inkline([ca, cb], 2.8)

    # sockets. Tilted outward at the top, which is the cartoonist's angry-but-cute brow.
    for sx, deg in ((34, 14), (66, -14)):
        ex, ey = _rot_pt((sx, 38), 50, 44, tilt)
        pts = []
        for i in range(26):
            a = 2 * math.pi * i / 26
            pts.append((ex + 14 * math.cos(a), ey + 15.5 * math.sin(a)))
        p.rot_poly(pts, ex, ey, deg + tilt, INK)
        p.circle(ex + 5.0, ey - 5.0, 4.0, WHITE)

    # nose: an upside-down heart-ish notch, drawn as a wide triangle so it survives the downsample
    nx, ny = _rot_pt((50, 58), 50, 44, tilt)
    p.rot_poly([(nx - 7, ny - 8), (nx + 7, ny - 8), (nx, ny + 2)], nx, ny, tilt, INK)

    # teeth: four ink gaps down the jaw plus one line along the top of it
    ta = _rot_pt((34, 70), 50, 44, tilt)
    tb = _rot_pt((66, 70), 50, 44, tilt)
    p.inkline([ta, tb], 3.0)
    for gx in (42, 50, 58):
        ga = _rot_pt((gx, 70), 50, 44, tilt)
        gb = _rot_pt((gx, 86), 50, 44, tilt)
        p.inkline([ga, gb], 2.8)


@icon("sparkle")
def _sparkle(p):
    """A scatter of four-point sparkles for the season track's shard reward face.

    HOW THIS STAYS DISTINCT FROM `shard` AND `xp`, which is the entire design problem here:

      * `shard` is ONE four-point star, centred, filling the box, GOLD with a cream core.
      * `xp` is ONE five-point star, centred, SUNNY with a cream core.
      * this is THREE stars of three different sizes, scattered off-centre, in cool blue-white.

    Count and layout do the work at 40px, where colour is still legible but point-count is not:
    the silhouette of a single centred star and the silhouette of a three-star scatter are
    unmistakably different shapes even when both are 12 pixels of yellow. Colour is the second
    guard rather than the first -- gold is spoken for by the two currencies, so this cluster is
    SKY/CREAM with one pink accent, which also matches the "magic" register of a season reward.

    The spikes are thinner than `shard`'s (inner radius is a fifth of the outer rather than a
    third), because a sparkle is a glint and a shard is an object.
    """
    # big one, low-left; medium, upper-right; small, lower-right. Deliberately NOT on a line --
    # three collinear stars read as a progress bar.
    p.star(38, 44, 30, 6.0, 4, SKY, rot=-90)
    p.star(38, 44, 13, 3.0, 4, CREAM, rot=-90)

    p.star(74, 24, 19, 3.8, 4, CREAM, rot=-90)
    p.star(74, 24, 8, 1.8, 4, WHITE, rot=-90)

    p.star(72, 72, 15, 3.0, 4, BUBBLEGUM, rot=-90)
    p.star(72, 72, 6, 1.4, 4, CREAM, rot=-90)

    # two dust motes. They are round, so they cannot be mistaken for a fourth sparkle, and they
    # fill the empty upper-left corner the three stars leave.
    p.circle(20, 18, 4.5, CREAM)
    p.circle(52, 88, 3.8, SKY)


@icon("orb")
def _orb(p):
    """The Mystery Potions crystal ball, for the shop sign and the counter.

    The stand matters more than it looks: a purple sphere on its own is a bubble or a planet, and
    the game already has both. Three claw feet under a flared collar are the shorthand that says
    fortune-telling, so they are drawn fat enough to survive the downsample even though they only
    occupy the bottom fifth of the box.

    The swirl inside is a sampled spiral rather than a couple of arcs. Arcs read as reflections;
    a spiral reads as something moving in there, which is the point of a MYSTERY potion. It is
    drawn in two weights -- a wide dim pass and a narrow bright one over it -- so it has depth
    inside the glass instead of sitting on the surface like a decal.
    """
    # the stand: collar, then three claws splayed under it
    for dx in (-1, 0, 1):
        p.rot_poly(
            [(50 + dx * 15 - 8, 74), (50 + dx * 15 + 8, 74), (50 + dx * 19 + 7, 92),
             (50 + dx * 19 - 7, 92)],
            50, 84, dx * 7, GOLD_D,
        )
    p.rrect(26, 68, 74, 82, 7, GOLD)

    # the glass
    p.circle(50, 44, 33, PURPLE)
    # a deeper crescent along the lower right, so the sphere has a shadow side of its own on top
    # of the pipeline's vertical ramp -- a ball lit only top-to-bottom still looks like a disc
    p.wedge(50, 44, 33, -40, 130, shade(PURPLE_D, -0.10), steps=40)
    p.circle(46, 40, 29, PURPLE)

    # the swirl, from the middle outward
    dim, bright = [], []
    for i in range(30):
        t = i / 29.0
        a = math.radians(-40 + t * 430)
        r = 3 + t * 21
        dim.append((48 + r * math.cos(a), 43 + r * math.sin(a) * 0.92))
    p.line(dim, 7.0, shade(LAVENDER, -0.05))
    for i in range(30):
        t = i / 29.0
        a = math.radians(-40 + t * 430)
        r = 3 + t * 21
        bright.append((48 + r * math.cos(a) * 0.86, 43 + r * math.sin(a) * 0.80))
    p.line(bright, 3.4, CREAM)

    # the glint. Two of them: the hard wet dot the pipeline's soft gloss cannot give, plus a small
    # companion, which is the pairing every glass surface in the reference art uses.
    p.sheen(36, 26, 11, 6.0, deg=-34)
    p.circle(26, 40, 3.6, (255, 255, 255, 200))  # raw: a deliberately semi-transparent accent


@icon("medal_silver")
def _medal_silver(p):
    """Second place. The gold medal's drawing in steel, with cool ribbons.

    See `_medal` above for why the geometry is shared rather than re-invented. Silver's problem is
    that STEEL is close to the CREAM the gold medal uses for its star, so the star here is pure
    WHITE against STEEL_D -- a cream star on a steel face vanishes at 40px. The ribbons go
    AQUA/LAVENDER: gold's are CORAL/SKY, and swapping the warm half for a cool one is the fastest
    way to tell two medals apart in a leaderboard column where all three are the same silhouette.
    """
    _medal(p, AQUA, LAVENDER, STEEL, STEEL_D, WHITE)


@icon("medal_bronze")
def _medal_bronze(p):
    """Third place. The same medal again, in bronze.

    The face is ORANGE deepened rather than BROWN: raw BROWN is a wood colour and the disc came
    out looking like a coaster. Deepening ORANGE keeps the metal in the copper family and leaves
    enough separation from the GOLD of first place, which was the risk -- gold and bronze are the
    two that get confused, never gold and silver. BROWN is demoted to the inner rim, where being
    slightly muddy is exactly what a recessed ring should be. Ribbons are GREEN/MINT so all three
    medals have a different ribbon pair.
    """
    _medal(p, GREEN, MINT, shade(ORANGE, -0.20), BROWN, CREAM)


@icon("handshake")
def _handshake(p):
    """Two hands clasped, for the "Trade complete!" message.

    Everything about this is a fight with 40 pixels. Fingers are the natural way to draw a
    handshake and fingers are exactly what disappears, so the read is carried by SILHOUETTE and by
    COLOUR: two forearms in two clearly different skin tones meeting in a single fat clasp. Ink
    lines between the fingers are 3 units wide -- thinner ones grey out, and a grey band across the
    middle of the clasp reads as a crack.

    THE ARMS RUN HORIZONTALLY, and that is the correction. The first version brought both forearms
    up from the two lower corners, which draws a V -- and a fat V of two rounded limbs is a
    boomerang or a pair of mittens, which is exactly how it read. Two arms that both travel in the
    same direction cannot say "meeting"; the gesture only exists when they OPPOSE.

    So: one arm in from the left, one in from the right, both roughly level, and a clasp in the
    middle that is TALLER than either of them. That height difference is what stops the silhouette
    reading as a bone -- a bone has two lumps and a thin waist, this has a thin pair of ends and
    one fat middle, which is the opposite profile.
    """
    far = BROWN                 # the darker hand
    near = PEACH                # the lighter hand

    # THIN ARMS, FAT CLASP. Level arms of the same thickness as the grip drew a BONE -- two lumps
    # and a shaft. The profile has to be the other way up, so the forearms are 15 and the clasp is
    # 52 tall, and the arms enter LOW while the clasp stands high. Four evenly spaced ink lines
    # across it were the other half of the bone read (a grille of stripes on a shaft); there are
    # two now, and they are on the join rather than spread across the whole mass.
    p.capsule(4, 68, 36, 66, 15, near)
    p.capsule(96, 70, 64, 68, 15, far)
    # cuffs, so each arm reads as a sleeve entering the frame rather than as a severed limb
    p.rrect(2, 58, 15, 79, 4, shade(near, -0.34))
    p.rrect(85, 60, 98, 81, 4, shade(far, -0.30))

    # THE CLASP. The far hand's fist first, then the near hand wrapping over its top-left -- the
    # overlap is what makes this a grip rather than two hands touching, and it is the reason the
    # two skin tones have to be far apart: at 40px the join is the only thing still legible.
    p.rrect(40, 30, 78, 78, 12, far)
    p.rot_poly([(26, 40), (62, 28), (70, 54), (34, 68)], 50, 48, 4, near)
    p.capsule(30, 46, 64, 34, 15, near)                      # the thumb, laid across the top
    p.circle(30, 46, 8, near)                                # its knuckle, so the wrap has a corner
    p.sheen(40, 38, 8, 3.5)

    # two separations only, both on the near hand's fingers where they cross the far fist
    p.inkline([(46, 34), (50, 62)], 3.0)
    p.inkline([(58, 31), (62, 58)], 3.0)


@icon("home")
def _home(p):
    """The arena's Back portal: a squat cartoon house.

    Squat on purpose -- the roof is nearly half the height and overhangs the walls on both sides.
    A house drawn at real proportions is a tall thin box with a small hat, and at 40px that is a
    pentagon. Overhang plus a fat roof is what makes a house read instantly at any size.

    NOT tilted, unlike most of this set. Eight degrees of lean on a building does not read as
    "hand-drawn", it reads as subsidence, and this is the icon that means "go back to safety". The
    hand-drawn feeling is bought instead with an off-centre chimney and a roof ridge that is a
    couple of units left of the middle.
    """
    # chimney first, so the roof laps over its base
    p.rrect(64, 16, 78, 40, 3, CORAL)
    p.rrect(62, 12, 80, 20, 3, shade(CORAL, 0.18))

    # walls
    p.rrect(20, 46, 80, 90, 5, CREAM)

    # the roof: a slab with real thickness, ridge nudged left of centre
    p.poly([(48, 10), (94, 46), (94, 54), (48, 20), (6, 54), (6, 46)], CORAL)
    p.poly([(48, 18), (88, 50), (8, 50)], shade(CORAL, -0.18))

    # door: tall, rounded top, with a knob. It runs to the very bottom edge of the wall so the
    # house sits on the ground instead of floating.
    p.rrect(42, 60, 64, 90, 8, BROWN)
    p.circle(59, 76, 3.4, GOLD)

    # window: one, big, four panes. Two small windows both turn to mush; one big one survives.
    p.rrect(25, 58, 39, 74, 3, SKY)
    p.inkline([(32, 58), (32, 74)], 2.6)
    p.inkline([(25, 66), (39, 66)], 2.6)


@icon("snow")
def _snow(p):
    """A six-arm snowflake for the Frostbloom season theme.

    Six arms, not eight: eight is a compass rose and reads as navigation. The arms are thick bars
    with a pair of barbs two thirds of the way out and a chevron tip, which is the minimum amount
    of detail that still reads as ice rather than as a wheel -- fully fractal arms were tried and
    became a fuzzy disc the moment the icon was downsampled.

    Rotated 12 degrees off the vertical for the same reason everything else here is tilted, and
    because an arm pointing exactly straight up aligns with the pixel grid and gains a stair-step
    the neighbouring arms do not have.
    """
    for i in range(6):
        a = math.radians(-90 + 12 + i * 60)
        ca, sa = math.cos(a), math.sin(a)

        def at(r, off=0.0):
            # a point r units out along the arm, offset sideways -- keeps the barbs square to the
            # arm instead of square to the canvas
            return (50 + r * ca - off * sa, 50 + r * sa + off * ca)

        p.line([at(2), at(42)], 8.0, AQUA)

    # the barbs and tips, drawn in a second pass so they sit ON the arms rather than under them
    for i in range(6):
        a = math.radians(-90 + 12 + i * 60)
        ca, sa = math.cos(a), math.sin(a)

        def at(r, off=0.0):
            return (50 + r * ca - off * sa, 50 + r * sa + off * ca)

        for s in (-1, 1):
            p.line([at(22), at(32, s * 12)], 6.5, SKY)
            p.line([at(34), at(40, s * 8)], 5.5, SKY)

    p.circle(50, 50, 11, CREAM)
    p.star(50, 50, 8, 4, 6, WHITE, rot=-78)


@icon("sprig")
def _sprig(p):
    """A leafy sprig for the Overgrowth season theme.

    Four leaves on a curving stem, alternating left and right and shrinking toward the tip -- an
    even, symmetric arrangement reads as a corporate eco logo, and this is a season banner on a
    game about mutating creatures. The curve of the stem is sampled rather than drawn as two
    straight segments, because the join between two straights is visible at this contour weight.

    The leaves alternate GREEN and MINT rather than all being one green: touching same-colour
    leaves merge into a bush, since the contour pass only inks the outer silhouette. Each leaf also
    carries a midrib in ink, which is what stops the fat lens shape reading as a balloon.
    """
    stem = []
    for i in range(21):
        t = i / 20.0
        stem.append((28 + 34 * t + 8 * math.sin(t * 2.2), 92 - 76 * t))
    p.line(stem, 7.0, GREEN_D)

    # (x, y, length, width, angle, colour) -- angles fan away from the stem's local direction
    for lx, ly, ln, wd, ang, col in (
        (30, 70, 40, 12.5, 196, GREEN),
        (72, 56, 36, 11.5, -18, MINT),
        (38, 40, 32, 10.0, 205, MINT),
        (72, 26, 26, 8.5, -24, GREEN),
    ):
        p.poly(_leaf_pts(lx, ly, ln, wd, ang), col)
        a = math.radians(ang)
        p.inkline([
            (lx - (ln / 2.4) * math.cos(a), ly - (ln / 2.4) * math.sin(a)),
            (lx + (ln / 2.4) * math.cos(a), ly + (ln / 2.4) * math.sin(a)),
        ], 2.6)

    # a bud at the tip, so the stem ends in something rather than just stopping
    p.circle(66, 14, 6.5, MINT)


@icon("honey")
def _honey(p):
    """A honey pot with a dripping dipper -- the Large potion size marker.

    This one has a job beyond depicting honey: it is the biggest of the three size markers, so it
    has to read as GENEROUS. That is bought with a pot filled past its rim, a fat bulge at the
    waist, a run of honey escaping down the side, and a drip mid-fall off the dipper. A neat,
    level, half-full pot would be correct and would be the wrong answer.

    The dipper leans 14 degrees rather than standing upright, which also lets the falling drip sit
    in the empty upper-right corner instead of being hidden behind the stick.
    """
    # the pot: widest at the waist, tucked in at the foot -- a straight-sided jar reads as a tin
    p.poly([(24, 46), (76, 46), (84, 68), (78, 90), (22, 90), (16, 68)], shade(ORANGE, -0.26))
    # the lip: a wide collar overhanging the body on both sides
    p.rrect(14, 38, 86, 52, 6, CREAM)
    # the honey surface in the mouth, sitting proud of the lip
    p.ellipse(50, 40, 30, 7.5, GOLD)
    # the overfill: honey running over the front of the collar and down the pot
    p.poly([(26, 46), (38, 46), (36, 66), (28, 74), (22, 66)], GOLD)
    p.circle(26, 76, 5.5, GOLD)

    # the dipper. Stick, then four graded ridges -- a dipper is defined by its grooves, and four
    # is the fewest that still stripes at 40px.
    p.rot_poly([(52, 4), (60, 4), (58, 34), (50, 34)], 56, 20, 14, BROWN)
    for i, r in enumerate((7.5, 9.0, 9.5, 8.0)):
        cxx, cyy = _rot_pt((56, 22 + i * 6.5), 56, 20, 14)
        p.ellipse(cxx, cyy, r, 3.6, GOLD_D if i % 2 else GOLD)

    # the drip, caught in the air: a teardrop plus the thread it just broke off
    p.capsule(66, 42, 68, 50, 4.0, GOLD)
    p.circle(69, 58, 6.0, GOLD)
    p.poly([(69, 47), (74, 58), (64, 58)], GOLD)

    # the wet dot on the pot's shoulder -- ceramic, and the one place a hard catchlight belongs
    p.sheen(34, 60, 8, 4.5, deg=-30)
