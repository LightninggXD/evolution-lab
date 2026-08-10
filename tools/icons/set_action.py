"""
set_action.py -- verbs: confirm, cancel, go, upgrade, spin, mute, unlock.

Icon bodies. Each draws into a 0..100 box with the shared `Pen`; the lighting, the contour and the
gloss are added afterwards by `iconkit.render` and must NOT be drawn here -- see iconkit's header.

THE ONE RULE: never ask a primitive for a stroke. The silhouette is derived from the finished
colour layer, so a stroke here becomes an internal ring around every shape instead of one contour
around the icon. Deliberate internal linework goes through `p.inkline`.

WHY THIS SET IS DRAWN AS OBJECTS RATHER THAN AS MARKS
------------------------------------------------------
Every other set in this folder gets a THING for free -- a coin is a coin, an egg is an egg. This
one is verbs, and a tick, a cross and an arrow are pure abstraction: there is nothing to give a
light side and a shadow side to, so the first version came out as flat pictograms in a game full
of painted toys. The fix is to hand every abstract mark a physical object to live on and then draw
THAT object properly: the tick is punched into a badge, the cross is the face of a stop button, the
arrow is a signpost plank with a bolt through it. The mark stays the loudest shape on the icon; it
just now sits on something that can catch light.

THREE MOVES DO MOST OF THE WORK, AND THEY ARE THE SAME THREE ON ALL ELEVEN
--------------------------------------------------------------------------
  * THICKNESS. Every solid is drawn twice -- once in a deepened shade, offset about two units right
    and three down, then again in its real colour on top. The sliver that survives underneath reads
    as the side face of a moulded object. This is far cheaper and steadier than trying to model a
    bevel with gradients, and it is what stops these from looking die-cut.
  * TILT. Nothing is left square to the canvas; every body is rotated between six and ten degrees
    through `_rot`. A dead-straight object reads as a diagram no matter how well it is shaded.
  * INTERNAL LINEWORK. Bevels, seams, spokes and perforations go in as `p.inkline`, which the
    shading passes are documented to skip. Ink is the only detail that reliably survives being
    resampled to the ~40px the HUD actually draws at; a two-tone colour difference at that size is
    a smudge, an ink line is still a line.

THE CLEARANCE NUMBER, WHICH DECIDES MOST OF THE LAYOUT
-------------------------------------------------------
`OUTLINE` is 5 units, so any two DETACHED pieces grow five units toward each other and need about
fourteen units of clear air before a reader sees a gap at all. That single constant is why `audio`
has two sound waves instead of the obvious three, why the sparkles on `upgrade` sit out in the
corners rather than hugging the shaft, and why the trailing dashes on `rebirth` live in the ring's
own opening. Anything closer merges into one ink blob, which looks like a rendering bug rather than
a style.
"""

from iconkit import (  # noqa: F401  -- the palette is a namespace, not a checklist
    icon, Pen,
    INK, WHITE, CREAM, GOLD, GOLD_D, ORANGE, BLUE, SKY, GREEN, GREEN_D, RED, PURPLE, PURPLE_D,
    PINK, GREY, MINT, SUNNY, BUBBLEGUM, LAVENDER, AQUA, PEACH, CORAL, BROWN, BROWN_D, STEEL,
    STEEL_D, TEAL, PLUM, shade,
)

import math  # noqa: F401


# ---------------------------------------------------------------- local geometry
# These return POINT LISTS rather than drawing, which is the whole reason they are here: the same
# outline has to be filled once as a colour, filled again offset as a side face, and traced a third
# time as an ink bevel. `Pen.rrect` and `Pen.rot_poly` can each do one of those three and none of
# them can do all three, so the shape is built once as data and spent three ways.


def _rot(pts, deg, cx=50.0, cy=50.0):
    """Turn a point list about a centre. Everything in this file is tilted; see the header."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def _shift(pts, dx, dy):
    """The side-face offset. Always down and to the right, because the light is upper-left."""
    return [(x + dx, y + dy) for x, y in pts]


def _rr(x0, y0, x1, y1, r, n=6):
    """A rounded rectangle as points, walking the four corner arcs clockwise from the top right."""
    out = []
    corners = ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180))
    for cx, cy, a0 in corners:
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def _ngon(cx, cy, r, n, rot=0.0):
    """A regular polygon. Only `cross` needs it, but an octagon typed out by hand is unreadable."""
    return [
        (cx + r * math.cos(math.radians(rot + i * 360.0 / n)),
         cy + r * math.sin(math.radians(rot + i * 360.0 / n)))
        for i in range(n)
    ]


def _closed(pts):
    """A point list that returns to its start, for tracing an outline with `inkline`."""
    return list(pts) + [pts[0]]


# ---------------------------------------------------------------- the icons


@icon("check")
def _check(p):
    # A FAT GLOSSY BADGE WITH A TICK PUNCHED INTO IT, not a tick in a circle. A bare tick has no
    # volume to light and a plain disc behind it is just a coloured hole, so the badge is built as
    # three stacked plates -- side face, rim, raised centre -- which gives the shading passes three
    # different heights to work on and makes the whole thing read as moulded plastic.
    #
    # The badge is a squircle rather than a disc on purpose: `cross` next to it is an octagon and
    # `question` is a circle, and three round buttons in one set are impossible to tell apart in
    # peripheral vision on a HUD. Silhouette is the only thing that separates them at 40px.
    tilt = -9
    body = _rot(_rr(7, 7, 93, 93, 28), tilt)
    p.poly(_shift(body, 2.2, 3.2), shade(GREEN_D, -0.42))     # the side face
    p.poly(body, GREEN_D)                                     # the rim
    face = _rot(_rr(16, 16, 84, 84, 22), tilt)
    p.poly(face, GREEN)                                       # the raised centre plate
    p.inkline(_closed(face), 2.4)                             # the bevel between rim and plate

    # Four rivets around the rim. They are drawn at r=3.4 which is barely over a pixel on the HUD,
    # and that is fine -- individually they are invisible at that size, collectively they keep the
    # rim from reading as an empty band, which is the job.
    for x, y in _rot([(50, 11.5), (88.5, 50), (50, 88.5), (11.5, 50)], tilt):
        p.circle(x, y, 3.4, INK)

    # The tick is drawn twice, the lower copy in a deep green, so it reads as pressed INTO the
    # plate rather than painted onto it. Tried it the other way round (a light copy above a dark
    # tick, i.e. embossed outward) and it fought the global gloss, which already lights the top.
    tick = _rot([(28, 53), (44, 70), (76, 29)], tilt)
    p.line(_shift(tick, 1.8, 2.6), 14, shade(GREEN_D, -0.34))
    p.line(tick, 14, CREAM)
    p.sheen(35, 32, 11, 6.5, -32)


@icon("cross")
def _cross(p):
    # A CHUNKY STOP BUTTON. The octagon is doing double duty: it is the only silhouette in the whole
    # icon set that already means "no" before you have read anything inside it, and it gives the
    # cross somewhere to sit that is unmistakably a different object from the check badge.
    #
    # Same three-plate build as `check` so the two read as a matched pair -- they are almost always
    # drawn side by side on a confirm dialog, and a mismatched pair there looks like a bug.
    tilt = 8
    body = _rot(_ngon(50, 50, 43, 8, 22.5), tilt)
    p.poly(_shift(body, 2.2, 3.2), shade(RED, -0.48))
    p.poly(body, shade(RED, -0.24))
    face = _rot(_ngon(50, 50, 34, 8, 22.5), tilt)
    p.poly(face, RED)
    p.inkline(_closed(face), 2.4)

    for x, y in _rot([(50, 12), (88, 50), (50, 88), (12, 50)], tilt):
        p.circle(x, y, 3.4, INK)

    # Both bars get the same pressed-in shadow as the tick. They are drawn as two separate strokes
    # rather than one X polygon because the round caps are what make the ends look moulded; a
    # polygon X has square tips and immediately reads as a font glyph.
    for a, b in (((32, 32), (68, 68)), ((68, 32), (32, 68))):
        bar = _rot([a, b], tilt)
        p.line(_shift(bar, 1.8, 2.6), 13.5, shade(RED, -0.42))
    for a, b in (((32, 32), (68, 68)), ((68, 32), (32, 68))):
        p.line(_rot([a, b], tilt), 13.5, CREAM)
    p.sheen(35, 33, 10, 6, -32)


@icon("arrow")
def _arrow(p):
    # A PAINTED SIGNPOST PLANK, bolted at the tail. The old arrow was one flat polygon, which is
    # the most diagram-like thing in the entire icon set: a shape with no thickness, no seam and no
    # reason to exist as an object. Nothing about the silhouette changed -- it still has to read as
    # "go" instantly -- but it now has a side face, a routed bevel line following the outline, a
    # seam where the head is jointed onto the shaft, and a steel bolt holding it to a post.
    tilt = -8
    shaft = [(6, 36), (52, 36), (52, 14), (92, 50), (52, 86), (52, 64), (6, 64)]
    body = _rot(shaft, tilt)
    p.poly(_shift(body, 2.4, 3.4), shade(GOLD_D, -0.34))
    p.poly(body, GOLD)

    # The inset outline is the single biggest gain here: one ink path parallel to the silhouette
    # turns a flat sign into a routed one, and it survives downsampling better than any amount of
    # tonal shading because ink is protected from the shading passes.
    inner = _rot([(11, 41), (50, 41), (50, 26), (83, 50), (50, 74), (50, 59), (11, 59)], tilt)
    p.inkline(_closed(inner), 2.4)
    # The joint between head and shaft. A sign made of two boards is more of an object than a sign
    # milled out of one, and this line also stops the arrowhead from reading as a stuck-on triangle.
    p.inkline(_rot([(50, 27), (50, 73)], tilt), 2.4)

    # The bolt. Ink disc first so it keeps a hard edge against the gold no matter how the volume
    # ramp lands on that part of the plank, then the steel head, then a wet dot on it.
    bx, by = _rot([(23, 50)], tilt)[0]
    p.circle(bx, by, 7.5, INK)
    p.circle(bx, by, 4.6, STEEL)
    p.sheen(bx - 1.4, by - 1.6, 2.2, 1.4, -30)


@icon("upgrade")
def _upgrade(p):
    # AN ARROW RISING OFF A PLINTH, with sparks coming off it. The old version was an arrow with a
    # smaller arrow cut out of it, which is a perfectly good flat icon and says nothing about the
    # thing going UP -- the motion had to be implied by something outside the shape.
    #
    # The plinth is what sells it: an arrow with a bar under it is leaving somewhere, an arrow on
    # its own is just pointing. The bar is also the reason the arrow could be made shorter and
    # therefore fatter, which is the direction the whole redraw is pushing.
    tilt = -6
    base = _rot(_rr(21, 78, 79, 93, 7), tilt)
    p.poly(_shift(base, 2.2, 3.0), shade(GREEN_D, -0.42))
    p.poly(base, GREEN_D)

    arrow = [(50, 7), (88, 45), (69, 45), (69, 79), (31, 79), (31, 45), (12, 45)]
    body = _rot(arrow, tilt)
    p.poly(_shift(body, 2.2, 3.2), shade(GREEN_D, -0.38))
    p.poly(body, MINT)
    p.inkline(_closed(_rot([(50, 15), (79, 44), (64, 44), (64, 78), (36, 78), (36, 44), (21, 44)], tilt)), 2.4)
    # One line across the throat of the arrowhead, so the head reads as a cap sitting on the shaft
    # rather than as one moulded lump. Same trick as the signpost joint on `arrow`.
    p.inkline(_rot([(36, 44.5), (64, 44.5)], tilt), 2.4)
    p.inkline(_rot([(30, 85.5), (70, 85.5)], tilt), 2.4)

    # Sparks. They sit right out in the top corners because a detached shape needs about fourteen
    # units of air before the contour stops swallowing the gap -- see the header. Tucked in beside
    # the shaft, which is where they naturally want to go, they merged into the arrow.
    p.star(88, 20, 8.5, 3.0, 4, SUNNY, rot=-90)
    p.star(13, 15, 6.0, 2.1, 4, SUNNY, rot=-90)
    p.sheen(40, 26, 7, 4, -34)


@icon("rebirth")
def _rebirth(p):
    # ONE FAT LOOPING ARROW ROUND A PRIZE. The old note here still holds and is worth keeping: three
    # curved arrows chasing each other is unreadable at 40px and one is not. What changed is that
    # the single arrow now has thickness, a trail, and something in the middle worth going round --
    # rebirth in this game is a reset that PAYS, and an empty loop only says "reset".
    #
    # The star is deliberately small. The ring's hole is 42 units across and a detached shape eats
    # five units of that on every side, so anything bigger than about nine units of radius closes
    # the gap and the star fuses to the ring.
    cx, cy, rad, band = 50, 52, 27, 12.5
    p.arc(cx + 1.8, cy + 2.8, rad, rad, 300, 580, band, shade(GREEN_D, -0.40))
    p.arc(cx, cy, rad, rad, 300, 580, band, MINT)

    # The head is placed and aimed off the sweep's own end rather than typed in as three points, so
    # moving the gap cannot leave the arrow pointing at nothing.
    a = math.radians(580)
    hx, hy = cx + rad * math.cos(a), cy + rad * math.sin(a)
    tx, ty = -math.sin(a), math.cos(a)   # tangent, in the direction the sweep is going
    nx, ny = math.cos(a), math.sin(a)    # radial
    head = [(hx + tx * 19, hy + ty * 19), (hx + nx * 14, hy + ny * 14), (hx - nx * 14, hy - ny * 14)]
    p.poly(_shift(head, 1.8, 2.8), shade(GREEN_D, -0.40))
    p.poly(head, MINT)

    # The trail lives INSIDE the ring's own opening, which is the only place on this icon with
    # enough clearance for detached marks. Two dashes, the leading one heavier, at forty-five
    # degrees apart -- closer together and they merge into each other instead of the ring.
    for deg, w, ln in ((243, 5.5, 5.0), (285, 3.6, 3.6)):
        ra = math.radians(deg)
        px_, py_ = cx + rad * math.cos(ra), cy + rad * math.sin(ra)
        dx, dy = -math.sin(ra), math.cos(ra)
        p.line([(px_ - dx * ln, py_ - dy * ln), (px_ + dx * ln, py_ + dy * ln)], w, MINT)

    p.star(cx, cy, 9.5, 4.0, 5, GOLD, rot=-90)
    p.sheen(36, 34, 6, 3.4, -34)


@icon("wheel")
def _wheel(p):
    # A PRIZE WHEEL AS A BUILT OBJECT: a painted rim with pegs round it, eight candy wedges, a
    # bolted hub, and a pointer that the wheel actually passes under. The old one was eight wedges
    # and a dot, which is a pie chart with a spike on it.
    #
    # The ink spokes are the detail that matters most here. Eight saturated wedges meeting with no
    # separator turn to a single grey-brown ring the moment the icon is resampled to HUD size; with
    # a line between them the wheel still reads as segmented at 40px even when the individual
    # colours no longer do.
    cx, cy = 50, 53
    p.circle(cx + 2.2, cy + 3.0, 43, shade(PLUM, -0.35))
    p.circle(cx, cy, 43, PLUM)

    cols = (CORAL, SUNNY, MINT, AQUA, LAVENDER, PEACH, BUBBLEGUM, GREEN)
    for i, col in enumerate(cols):
        a0, a1 = i * 45 - 101, (i + 1) * 45 - 101
        pts = [(cx, cy)]
        for k in range(9):
            a = math.radians(a0 + (a1 - a0) * k / 8.0)
            pts.append((cx + 36 * math.cos(a), cy + 36 * math.sin(a)))
        p.poly(pts, col)
    for i in range(8):
        a = math.radians(i * 45 - 101)
        p.inkline([(cx, cy), (cx + 36 * math.cos(a), cy + 36 * math.sin(a))], 2.4)

    # Pegs on the rim. Same argument as the rivets on `check`: no one sees an individual peg at HUD
    # size, but their absence leaves the rim looking like an unpainted washer.
    for i in range(8):
        a = math.radians(i * 45 - 78)
        p.circle(cx + 39.5 * math.cos(a), cy + 39.5 * math.sin(a), 3.0, CREAM)

    p.circle(cx, cy, 10, CREAM)
    p.circle(cx, cy, 5, GOLD_D)
    p.sheen(cx - 2.6, cy - 3.0, 3.0, 1.9, -30)

    # The pointer overlaps the rim so the two share one contour, which is what makes it look like a
    # flap the wheel ticks past rather than a triangle parked above it.
    p.poly([(50, 2), (60, 21), (40, 21)], CREAM)
    p.inkline([(43, 17.5), (57, 17.5)], 2.4)


@icon("question")
def _question(p):
    # A GLOSSY MYSTERY ORB. This is the one icon in the set where the mark genuinely is the subject,
    # so the object under it stays simple -- side face, rim, raised plate -- and everything goes
    # into making the "?" itself heavy: fatter stroke, a real tilt, and a pressed-in shadow copy so
    # the glyph looks moulded into the plate the same way the tick and the cross do.
    p.circle(52.4, 53.2, 42, shade(PURPLE_D, -0.42))
    p.circle(50, 50, 42, PURPLE_D)
    p.circle(50, 50, 33, LAVENDER)
    p.ring(50, 50, 33, 2.4, INK)
    for i in range(4):
        a = math.radians(i * 90 + 45)
        p.circle(50 + 37.5 * math.cos(a), 50 + 37.5 * math.sin(a), 3.4, INK)

    # ONE SAMPLED PATH, not an arc plus a stem. The first version glued a PIL arc to a straight
    # segment and the join read as an upside-down mark, because an arc's own end is square to the
    # radius and the stem met it at a corner. Walking the hook round and letting the tail continue
    # from wherever it ends keeps it a single stroke, which is what a "?" is.
    pts = []
    for i in range(17):
        a = math.radians(190 + i * (170.0 / 16))
        pts.append((50 + 16 * math.cos(a), 38 + 16 * math.sin(a)))
    pts += [(66, 44), (58, 52), (50, 61)]
    glyph = _rot(pts, 7)
    dot = _rot([(50, 79)], 7)[0]
    p.line(_shift(glyph, 1.8, 2.6), 11.5, shade(PURPLE_D, -0.34))
    p.circle(dot[0] + 1.8, dot[1] + 2.6, 7, shade(PURPLE_D, -0.34))
    p.line(glyph, 11.5, CREAM)
    p.circle(dot[0], dot[1], 7, CREAM)
    p.sheen(34, 32, 10, 6, -32)


@icon("gear")
def _gear(p):
    # A COG WITH DEPTH AND A HUB. Two changes carry it. First, the teeth are capsules instead of
    # quads, so they have domed ends -- a machined tooth has a sharp corner and a toy one does not,
    # and this set is toys. Second, the whole cog is stamped twice, offset, which gives it a rim of
    # dark metal all down its right side; a gear read head-on with no depth is the flattest object
    # in any icon set.
    #
    # Eleven degrees of tooth rotation, so no tooth sits exactly on an axis. A cog with a tooth
    # pointing straight up looks like a diagram of a cog.
    def cog(dx, dy, tooth, plate):
        for i in range(8):
            a = math.radians(i * 45 + 11)
            ca, sa = math.cos(a), math.sin(a)
            p.capsule(50 + dx + 23 * ca, 50 + dy + 23 * sa,
                      50 + dx + 38 * ca, 50 + dy + 38 * sa, 15, tooth)
        p.circle(50 + dx, 50 + dy, 30, plate)

    cog(2.4, 3.2, shade(STEEL_D, -0.44), shade(STEEL_D, -0.44))
    cog(0, 0, STEEL_D, STEEL)

    # The inner ring is where the "plate bolted onto the cog" reading comes from, and it is also
    # what stops the middle of the gear from being an empty grey field at HUD size.
    p.ring(50, 50, 24, 2.4, INK)
    p.circle(50, 50, 13, STEEL_D)
    p.circle(50, 50, 7, INK)
    for i in range(3):
        a = math.radians(i * 120 - 60)
        p.circle(50 + 19 * math.cos(a), 50 + 19 * math.sin(a), 3.2, INK)
    p.sheen(36, 32, 8, 4.6, -32)


@icon("audio")
def _audio(p):
    # A SPEAKER WITH A CONE IN IT, and two waves of different weight. The silhouette is left exactly
    # where convention puts it -- box plus flared trapezoid -- because it is one of about five
    # shapes on a HUD that everyone already reads without thinking, and there is no cartoon idea
    # worth breaking that for. The detail all goes inside: a side face, the seam where the magnet
    # housing meets the cone, two mounting rivets, and a lighter membrane down the cone's mouth.
    #
    # TWO waves, not three, and this is the one compromise in the set I would call a real loss.
    # Three concentric arcs is the better drawing, but at OUTLINE 5 the middle arc cannot be more
    # than a couple of units clear of its neighbours in the space left, and three arcs that merge
    # into one dark fan is strictly worse than two that read. The weight difference between the two
    # (6.5 against 8.5) is doing the job the third arc would have done.
    tilt = -6
    box = _rot(_rr(4, 36, 21, 64, 6), tilt)
    cone = _rot([(15, 40), (38, 11), (38, 89), (15, 60)], tilt)
    p.poly(_shift(box, 2.2, 3.2), shade(BLUE, -0.40))
    p.poly(_shift(cone, 2.2, 3.2), shade(BLUE, -0.40))
    p.poly(box, AQUA)
    p.poly(cone, AQUA)
    # The membrane. A tall thin ellipse down the mouth of the cone is the cheapest way to say the
    # cone is hollow; without it the trapezoid reads as a solid wedge of plastic.
    mx, my = _rot([(36, 50)], tilt)[0]
    p.ellipse(mx, my, 4.6, 33, shade(AQUA, 0.30))
    p.inkline(_rot([(17, 38), (17, 62)], tilt), 2.4)
    for x, y in _rot([(9, 43), (9, 57)], tilt):
        p.circle(x, y, 3.0, INK)

    p.arc(42, 50, 19, 19, -44, 44, 6.5, CREAM)
    p.arc(42, 50, 41, 41, -44, 44, 8.5, CREAM)


@icon("lock")
def _lock(p):
    # A PADLOCK BUILT OUT OF PARTS: a steel shackle with a catchlight on its upper limb, a body with
    # a side face and a raised front plate, four rivets, and a keyhole. The old one was an arc, a
    # rounded rectangle and a keyhole -- correct, and completely weightless.
    #
    # The shackle's limbs are sunk four units INTO the body rather than stopping at its top edge.
    # Butted up against it they left a hairline gap that the contour dilation filled with ink, which
    # at HUD size looks exactly like a rendering seam.
    p.arc(50, 46, 19, 19, 180, 360, 11, STEEL_D)
    p.arc(50, 46, 19, 19, 196, 256, 4.0, shade(STEEL, 0.34))

    tilt = 6
    body = _rot(_rr(17, 43, 83, 93, 13), tilt)
    p.poly(_shift(body, 2.4, 3.2), shade(GOLD_D, -0.36))
    p.poly(body, GOLD_D)
    face = _rot(_rr(24, 50, 76, 86, 9), tilt)
    p.poly(face, SUNNY)
    p.inkline(_closed(face), 2.4)
    for x, y in _rot([(21.5, 47.5), (78.5, 47.5), (21.5, 88.5), (78.5, 88.5)], tilt):
        p.circle(x, y, 3.4, INK)

    kx, ky = _rot([(50, 64)], tilt)[0]
    p.circle(kx, ky, 8, INK)
    p.poly(_rot([(44.5, 64), (55.5, 64), (53, 82), (47, 82)], tilt), INK)
    p.sheen(36, 56, 7, 4, -32)


@icon("ticket")
def _ticket(p):
    # A TORN-OFF PRIZE TICKET: a tilted body, a stub with a star on it, a perforation running
    # between them and a punched hole on the far edge. The old note here is still the load-bearing
    # one and is kept: a transparent fill does NOT erase, because the ink layer underneath simply
    # shows through, so a hole or a notch cannot be cut out -- it has to be DRAWN, as ink, in the
    # place the missing material would be.
    #
    # That constraint turns out to be a gift. Two ink discs sitting on the top and bottom edges at
    # the perforation merge with the contour and read as bitten-out notches, which is a better and
    # steadier trick than trying to build the pinched waist out of three overlapping rectangles the
    # way the previous version did.
    tilt = -8
    body = _rot(_rr(6, 26, 94, 74, 8), tilt)
    p.poly(_shift(body, 2.2, 3.2), shade(CORAL, -0.42))
    p.poly(body, CORAL)

    panel = _rot(_rr(12, 33, 58, 67, 5), tilt)
    p.poly(panel, CREAM)
    p.inkline(_closed(panel), 2.4)
    for i, x1 in enumerate((50, 44, 50)):
        y = 41.5 + i * 8.5
        p.inkline(_rot([(18, y), (x1, y)], tilt), 3.4)

    # The perforation. Drawn as five separate dashes rather than a dotted line, because a dashed
    # line of anything under about three units of width dissolves at HUD size and the ticket loses
    # the only mark that says it tears.
    for i in range(5):
        y = 31.5 + i * 9.3
        p.inkline(_rot([(66, y), (66, y + 4.6)], tilt), 3.0)
    for x, y in _rot([(66, 26), (66, 74)], tilt):
        p.circle(x, y, 6.0, INK)

    p.star(*_rot([(80, 50)], tilt)[0], 11.0, 4.6, 5, SUNNY, rot=-90)
    p.sheen(28, 38, 9, 4.5, -34)
