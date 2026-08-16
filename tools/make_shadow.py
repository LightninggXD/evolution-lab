"""make_shadow.py -- draws the one sprite the UI kit needs and cannot fake with a Frame.

WHY AN IMAGE AT ALL
-------------------
`addShadow` has been a no-op since 2026-08-11, when both of its Frame-based variants were removed
on play-test feedback ("an ugly line at the bottom of the button that even sticks out"). Both
deserved it, and the reason is geometric rather than cosmetic: a Frame has ONE corner radius and
hard edges, so any offset copy of a rounded shell pokes out of the corners the shell has already
curved away from. That is unfixable with more Frames -- a shadow is soft, and softness is alpha
falling off over a distance, which no `UICorner` can express.

So: one 9-sliceable sprite. A rounded rectangle, Gaussian-blurred, drawn in pure black with the
falloff carried entirely in the ALPHA channel -- so the game can tint it (`ImageColor3`) and fade
it (`ImageTransparency`) without the art fighting either.

GEOMETRY, AND WHY THESE NUMBERS
-------------------------------
  canvas   192 x 192
  rect     inset 48 on every side (so 96 x 96 of shape), corner radius 30
  blur     sigma 14

48 of padding is what the blur needs: a Gaussian is effectively dead by 3*sigma = 42, so the
sprite's own edge is transparent and the slice can never clip the falloff. Radius 30 is the top of
the kit's pixel ladder (14 / 22 / 30) -- a shadow one step rounder than its shell reads as light
scattering, a shadow SQUARER than its shell reads as a mistake, so the ladder's roundest is the
safe end to sit at.

  SliceCenter = Rect(78, 78, 114, 114)

i.e. inset + radius = 78 on each side. The four corner slices then carry the whole curve and the
whole blur, and the middle slices are flat -- which is what makes one sprite stretch to a 640 px
panel and a 82 px tile without the corners deforming.

  py tools/make_shadow.py        writes assets/ui/shadow.png
"""

import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "shadow.png")

SIZE = 192
INSET = 48
RADIUS = 30
SIGMA = 14


def main():
    # Alpha-only art: the RGB channels are black everywhere, including where the sprite is
    # transparent. A tinted ImageLabel multiplies RGB, so any colour baked in here would survive
    # the tint and show up as a fringe.
    mask = Image.new("L", (SIZE, SIZE), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([INSET, INSET, SIZE - INSET - 1, SIZE - INSET - 1], radius=RADIUS, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(SIGMA))

    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img.putalpha(mask)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)

    # Report the two numbers the Luau side has to agree with, so a regenerated sprite that moved
    # them cannot land silently.
    print(f"wrote {OUT}  {SIZE}x{SIZE}  SliceCenter = Rect({INSET+RADIUS}, {INSET+RADIUS}, "
          f"{SIZE-INSET-RADIUS}, {SIZE-INSET-RADIUS})  padding = {INSET}")
    print(f"alpha at centre = {mask.getpixel((SIZE//2, SIZE//2))}, at the sprite edge = {mask.getpixel((0, 0))}")


if __name__ == "__main__":
    main()
