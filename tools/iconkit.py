"""
iconkit.py -- the drawing kit and the render pipeline every Evolution Lab icon is built with.

WHY THIS IS SPLIT OUT OF make_icons.py
---------------------------------------
`make_icons.py` used to be one 635-line file: palette, primitives, render pipeline and all
forty-four icon bodies. The bodies are the part that grows -- and the part several people can work
on at once -- while everything here is shared and must NOT diverge. So the kit lives here, the
bodies live in `tools/icons/set_*.py`, and `make_icons.py` is the orchestrator that imports both.
A set file can be rewritten without touching a line of shared code, which is the whole point.

THE HOUSE LOOK, AND WHERE ITS NUMBERS COME FROM
------------------------------------------------
These icons sit on the same screen as UITheme's buttons and cards, so they are lit by the SAME
curve rather than by one invented here. `UITheme.gradientFor` is three stops -- shade(c, +0.62) at
the top, shade(c, +0.10) at 42%, shade(c, -0.28) at the bottom -- and `addGloss` is white at 0.72
transparency over the upper 40%. `VOLUME_STOPS` and `GLOSS_ALPHA` below are those two numbers.
If UITheme's curve moves, move these; that duplication is deliberate and is cheaper than teaching
Lua to draw PNGs.

WHAT MAKES THIS READ AS CARTOON RATHER THAN AS FLAT DESIGN
-----------------------------------------------------------
The first version of this file drew flat colour inside a thin contour, which is the generic
flat-icon look and is NOT what this game looks like: every surface in Evolution Lab is a painted
toy with a light side, a shadow side and a wet-looking highlight. Five passes were added, and they
run over the FINISHED colour layer, so they apply to every icon -- old or new -- without a single
icon body knowing they exist:

  1. VOLUME     -- the UITheme curve, applied down the icon's own bounding box.
  2. RIM LIGHT  -- a bright band just inside the top of the silhouette.
  3. CORE SHADE -- a dark band just inside the bottom of the silhouette.
  4. GLOSS      -- a soft elliptical highlight, upper left, clipped to the silhouette.
  5. CONTOUR    -- one dilated ink silhouette, thicker than before (5.0 vs 3.6).

INK IS PROTECTED FROM ALL OF THEM. Passes 1-4 skip pixels that are already close to INK, because
those are deliberate internal linework -- a mouth, a facet, a seam -- and lightening the top half
of a black line turns a drawn detail into a grey smudge. That protection is the difference
between "shaded icon" and "shaded icon with mud in it".
"""

import math

from PIL import Image, ImageChops, ImageDraw, ImageFilter

try:
    import numpy as np
except ImportError as exc:  # pragma: no cover - the pipeline cannot run without it
    raise SystemExit("iconkit needs numpy: py -m pip install numpy") from exc


# ---------------------------------------------------------------- render setup

SIZE = 256           # final PNG edge. HUD icons draw at ~40-60px, so this is ~5x headroom.
SS = 3               # supersample factor; the dilated mask is what needs it
W = SIZE * SS
OUTLINE = 5.0        # contour thickness in 0..100 units. 3.6 before -- see the header.
PAD = 9.0            # margin the 0..100 box is inset by, so the contour is never cropped
DILATE_SAMPLES = 96


# ---------------------------------------------------------------- palette
# Lifted from UITheme.Color so an icon and the tile under it are the same design system.

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
BROWN_D    = (110, 68, 40, 255)
STEEL      = (206, 214, 232, 255)
STEEL_D    = (150, 162, 190, 255)
TEAL       = (72, 200, 196, 255)
PLUM       = (96, 62, 132, 255)


def shade(c, amt):
    """UITheme.Shade, in RGB tuples. amt > 0 lightens toward white; amt < 0 deepens the hue.

    Deliberately NOT a fade to black on the negative side -- that is the exact mistake UITheme's
    own comment records: a button that goes to 30% of its colour reads as plastic lit from above
    rather than as a painted toy.
    """
    r, g, b = c[0], c[1], c[2]
    a = c[3] if len(c) > 3 else 255
    if amt >= 0:
        return (
            int(r + (255 - r) * amt),
            int(g + (255 - g) * amt),
            int(b + (255 - b) * amt),
            a,
        )
    k = 1 + amt
    return (int(r * k), int(g * k), int(b * k), a)


# ---------------------------------------------------------------- the pen
# Each primitive draws into the colour layer and NEVER asks for a stroke: the silhouette is
# derived afterwards, so a stroke here would show up as an internal ring around every shape.

PAD_PX = PAD * W / 100.0
SPAN = W - 2 * PAD_PX


class Pen:
    def __init__(self, draw):
        self.d = draw

    def _s(self, v):
        # 0..100 maps into the canvas INSET by PAD on every side: the dilated contour needs
        # somewhere to grow into, and `dilate` uses a wrapping offset, so an icon that touched its
        # box would bleed round to the opposite edge.
        return PAD_PX + v * SPAN / 100.0

    def _l(self, v):
        # A LENGTH, not a position -- stroke widths and corner radii must not pick up the margin
        # `_s` adds, or a 9-unit line comes out as wide as the padding plus nine.
        return v * SPAN / 100.0

    def _pts(self, pts):
        return [(self._s(x), self._s(y)) for x, y in pts]

    # ---- basic shapes -------------------------------------------------

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
        self.d.line(p, fill=color, width=max(int(self._l(width)), 1), joint="curve")
        # PIL leaves square butt-ends on a thick line; a round cap at each vertex keeps a stroke
        # reading as one drawn mark rather than as a chain of rectangles.
        r = self._l(width) / 2.0
        for x, y in p:
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=color)

    def arc(self, cx, cy, rx, ry, start, end, width, color):
        self.d.arc(
            [self._s(cx - rx), self._s(cy - ry), self._s(cx + rx), self._s(cy + ry)],
            start, end, fill=color, width=max(int(self._l(width)), 1),
        )
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

    # ---- detail primitives --------------------------------------------
    # Added for the cartoon pass. Every one of these exists because the same three or four lines
    # were being written by hand in icon after icon, and a shared version is a shared look.

    def rot_poly(self, pts, cx, cy, deg, color):
        """A polygon turned about a point. Tilt is most of what separates a toy from a diagram."""
        a = math.radians(deg)
        ca, sa = math.cos(a), math.sin(a)
        self.poly(
            [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts],
            color,
        )

    def capsule(self, x0, y0, x1, y1, width, color):
        """A round-ended bar from one point to another -- limbs, handles, bars, straps."""
        self.line([(x0, y0), (x1, y1)], width, color)

    def ring(self, cx, cy, r, width, color):
        self.arc(cx, cy, r, r, 0, 360, width, color)

    def wedge(self, cx, cy, r, start, end, color, steps=24):
        """A filled pie slice -- the only honest way to cut a disc into coloured segments."""
        pts = [(cx, cy)]
        for i in range(steps + 1):
            a = math.radians(start + (end - start) * i / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.poly(pts, color)

    def sheen(self, cx, cy, rx, ry, deg=-28, color=None):
        """The wet dot: a small tilted ellipse of near-white ON TOP of a shape.

        The global gloss pass gives the whole icon one soft highlight; this is the local one that
        says a particular sphere or gem is glassy. Both, not either -- the reference art has a
        broad sheen and a hard little catchlight.
        """
        color = color or (255, 255, 255, 210)
        pts = []
        for i in range(28):
            a = 2 * math.pi * i / 28
            pts.append((rx * math.cos(a), ry * math.sin(a)))
        self.rot_poly([(cx + x, cy + y) for x, y in pts], cx, cy, deg, color)

    def inkline(self, pts, width=2.4):
        """Deliberate internal linework. Protected from every shading pass -- see the header."""
        self.line(pts, width, INK)

    def eyes(self, cx, cy, spread, r, look=0.0):
        """Two ink eyes with catchlights. `look` shifts the pupils, which is the whole difference
        between a face that stares through you and one that is looking at something."""
        for sx in (-1, 1):
            ex = cx + sx * spread
            self.circle(ex, cy, r, INK)
            self.circle(ex + r * 0.34 + look, cy - r * 0.34, r * 0.36, WHITE)


# ---------------------------------------------------------------- morphology


def dilate(mask, radius):
    """Grow an alpha mask by `radius`, as the union of the mask shifted onto a ring of offsets.

    `ImageFilter.MaxFilter` is the obvious call and is unusable here: at this supersample the
    kernel is ~75x75 and one icon took minutes. Dilation by a disc is the union of every
    translation by a point of that disc, and for a filled shape the ring alone reaches the same
    outer contour (the untranslated mask fills the middle), so this is ~96 cheap whole-image
    `lighter` passes instead of a per-pixel window.
    """
    if radius <= 0:
        return mask
    out = mask
    for i in range(DILATE_SAMPLES):
        a = 2 * math.pi * i / DILATE_SAMPLES
        out = ImageChops.lighter(
            out,
            ImageChops.offset(mask, int(round(radius * math.cos(a))), int(round(radius * math.sin(a)))),
        )
    return out


def erode(mask, radius):
    """Shrink a mask. Dilation of the inverse, inverted -- the standard identity, and the reason
    the rim passes below can talk about "just inside the edge" at all."""
    if radius <= 0:
        return mask
    return ImageChops.invert(dilate(ImageChops.invert(mask), radius))


# ---------------------------------------------------------------- shading

# UITheme.gradientFor, as (position, shade amount). See the header.
VOLUME_STOPS = ((0.00, 0.62), (0.42, 0.10), (1.00, -0.28))
# UITheme.addGloss is white at BackgroundTransparency 0.72, i.e. 28% opaque.
GLOSS_ALPHA = 0.28
# How far inside the silhouette the two rim bands reach, in 0..100 units.
RIM_LIGHT_DEPTH = 3.4
CORE_SHADE_DEPTH = 5.6
RIM_LIGHT_AMT = 0.34
CORE_SHADE_AMT = -0.20
# A pixel this close to INK is linework and is left alone by every shading pass.
INK_GUARD = 74.0


def _volume_ramp(h):
    """The UITheme curve sampled to one column of `h` multipliers, then broadcast across the row."""
    ys = np.linspace(0.0, 1.0, h, dtype=np.float32)
    xs = np.array([s[0] for s in VOLUME_STOPS], dtype=np.float32)
    amt = np.array([s[1] for s in VOLUME_STOPS], dtype=np.float32)
    return np.interp(ys, xs, amt).astype(np.float32)


def _apply_shade(rgb, amount, weight):
    """Lighten or deepen `rgb` by a per-pixel `amount`, scaled by `weight` (0..1).

    Both directions in one call because they are one idea: the positive side lerps toward white,
    the negative side scales the hue down. Splitting them into two functions made call sites
    choose a sign twice.
    """
    amt = amount * weight
    up = np.clip(amt, 0.0, None)[..., None]
    down = np.clip(amt, None, 0.0)[..., None]
    out = rgb + (255.0 - rgb) * up
    out = out * (1.0 + down)
    return out


def shade_layer(layer):
    """Turn a flat colour layer into a lit one. Everything in the header's list, passes 1-4."""
    arr = np.asarray(layer, dtype=np.float32)
    rgb, alpha = arr[..., :3], arr[..., 3]
    solid = alpha > 8.0
    if not solid.any():
        return layer

    # WHERE THE ICON ACTUALLY IS. The ramp runs down the icon's own bounding box, not the canvas:
    # a short wide icon lit over the full canvas gets only the middle of the curve and comes out
    # looking unlit next to a tall one.
    rows = np.where(solid.any(axis=1))[0]
    y0, y1 = int(rows[0]), int(rows[-1])
    cols = np.where(solid.any(axis=0))[0]
    x0, x1 = int(cols[0]), int(cols[-1])
    bw, bh = max(x1 - x0, 1), max(y1 - y0, 1)

    # LINEWORK IS NOT A SURFACE. Distance to INK, falling to 0 at INK_GUARD -- a soft edge rather
    # than a hard test, so an antialiased ink line does not get a bright fringe where it fades.
    dist = np.sqrt(((rgb - np.array(INK[:3], dtype=np.float32)) ** 2).sum(axis=-1))
    paint = np.clip(dist / INK_GUARD, 0.0, 1.0)

    # 1. VOLUME
    ramp = np.zeros(arr.shape[0], dtype=np.float32)
    ramp[y0:y1 + 1] = _volume_ramp(bh + 1)
    ramp[:y0] = ramp[y0]
    ramp[y1 + 1:] = ramp[y1]
    rgb = _apply_shade(rgb, ramp[:, None], paint)

    # 2 + 3. THE TWO RIM BANDS. A band is the mask minus an eroded copy of itself; the top band is
    # lit and the bottom band is deepened, which is what gives a flat shape a thick painted edge.
    px = SPAN / 100.0
    a_mask = layer.split()[3]
    inner_light = ImageChops.subtract(a_mask, erode(a_mask, int(round(RIM_LIGHT_DEPTH * px))))
    inner_core = ImageChops.subtract(a_mask, erode(a_mask, int(round(CORE_SHADE_DEPTH * px))))
    band_light = np.asarray(inner_light, dtype=np.float32) / 255.0
    band_core = np.asarray(inner_core, dtype=np.float32) / 255.0

    # ...weighted by height so the light band only really lands on the top of the shape and the
    # shade band on the bottom. An unweighted rim is a uniform outline in a second colour, which
    # is the "sticker with a border" look and not this one.
    ty = np.clip((np.arange(arr.shape[0], dtype=np.float32) - y0) / bh, 0.0, 1.0)[:, None]
    rgb = _apply_shade(rgb, RIM_LIGHT_AMT * band_light * np.clip(1.0 - ty * 2.1, 0.0, 1.0), paint)
    rgb = _apply_shade(rgb, CORE_SHADE_AMT * band_core * np.clip(ty * 2.1 - 1.1, 0.0, 1.0), paint)

    # 4. GLOSS. Same geometry as UITheme.addGloss -- upper area, generously rounded -- but blurred
    # into a soft sheen, because a hard-edged pill drawn inside a star reads as a second object.
    gl = Image.new("L", layer.size, 0)
    gd = ImageDraw.Draw(gl)
    gx0, gx1 = x0 + bw * 0.10, x0 + bw * 0.78
    gy0, gy1 = y0 + bh * 0.05, y0 + bh * 0.44
    gd.ellipse([gx0, gy0, gx1, gy1], fill=255)
    gl = gl.filter(ImageFilter.GaussianBlur(radius=bh * 0.09))
    gloss = np.asarray(gl, dtype=np.float32) / 255.0
    gloss = gloss * (alpha / 255.0) * paint
    rgb = rgb + (255.0 - rgb) * (gloss * GLOSS_ALPHA)[..., None]

    out = np.concatenate([np.clip(rgb, 0, 255), alpha[..., None]], axis=-1)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


# ---------------------------------------------------------------- registry

ICONS = {}


def icon(name):
    def wrap(fn):
        if name in ICONS:
            raise ValueError("two icon bodies claim the name %r" % name)
        ICONS[name] = fn
        return fn
    return wrap


def render(name, fn):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    fn(Pen(ImageDraw.Draw(layer)))
    layer = shade_layer(layer)

    # 5. THE CONTOUR. Dilating the alpha of the finished colour layer is what gives ONE contour
    # around the whole icon instead of one around each shape -- see the file header.
    mask = dilate(layer.split()[3], int(round(OUTLINE * SPAN / 100.0)))
    ink = Image.new("RGBA", (W, W), INK)
    ink.putalpha(mask)

    return Image.alpha_composite(ink, layer).resize((SIZE, SIZE), Image.LANCZOS)
