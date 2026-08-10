"""
make_icons.py -- renders Evolution Lab's UI icon set to PNGs.

WHY THIS EXISTS RATHER THAN A FOLDER OF HAND-DRAWN FILES
--------------------------------------------------------
The HUD had no asset layer at all: every icon in the game was an emoji in a TextLabel. That is not
a style choice, it is a different picture on every platform -- Windows, Android and console each
ship their own emoji font, so the same tile renders three different ways and none of them shares
the thick dark outline and flat pastel fill that everything else in this game is built from. An
icon that is generated is an icon that can be REGENERATED: change the lighting curve in `iconkit`
and all forty-four move together, which is the same argument the UITheme module makes about
buttons.

WHERE EVERYTHING LIVES NOW
---------------------------
This file used to be all of it -- palette, primitives, pipeline and every icon body -- and was
split when the bodies were redrawn:

  * `tools/iconkit.py`      the palette, the `Pen`, and the five-pass render pipeline.
  * `tools/icons/set_*.py`  the icon bodies, four sets of eleven.
  * this file               renders whatever those registered, and nothing else.

REGENERATING A PNG DOES NOT CHANGE ITS ASSET ID. `assets/icons/uploaded.json` records the upload;
if the art moves, the PNG has to be uploaded again and the new id written into BOTH that file and
`ReplicatedStorage/Modules/IconLibrary.lua`. Re-uploading a name mints a SECOND asset -- it does
not update the first.

  py tools/make_icons.py                 render everything
  py tools/make_icons.py dna coin        render two, for a quick look
  py tools/make_icons.py --sheet         also write assets/icons/_contact_sheet.png
  py tools/make_icons.py --sheet=X.png   ...write it somewhere else instead

That last form exists because more than one person renders at once: the PNGs they write are
disjoint, but a shared sheet path is the one file they would race on.
"""

import json
import os
import sys

from PIL import Image, ImageDraw

import iconkit
from iconkit import ICONS, render

import icons  # noqa: F401  -- importing the package is what registers the bodies

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")


def contact_sheet(names, path, cols=8, cell=150):
    """One image of the whole set, at roughly twice HUD size.

    Worth its twenty lines: these are judged as a FAMILY -- whether they share a weight, a light
    direction and a palette -- and that is invisible when they are opened one at a time.
    """
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 20)), (60, 64, 84, 255))
    draw = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        img = Image.open(os.path.join(OUT_DIR, name + ".png")).convert("RGBA")
        img = img.resize((cell - 20, cell - 20), Image.LANCZOS)
        x, y = (i % cols) * cell + 10, (i // cols) * (cell + 20) + 6
        sheet.alpha_composite(img, (x, y))
        draw.text((x, y + cell - 16), name, fill=(255, 255, 255, 255))
    sheet.save(path)
    return path


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sheet_path = None
    for a in sys.argv[1:]:
        if a == "--sheet":
            sheet_path = os.path.abspath(os.path.join(OUT_DIR, "_contact_sheet.png"))
        elif a.startswith("--sheet="):
            sheet_path = os.path.abspath(a.split("=", 1)[1])

    names = sorted(ICONS)
    if args:
        missing = [a for a in args if a not in ICONS]
        if missing:
            raise SystemExit("no such icon: %s\nknown: %s" % (", ".join(missing), ", ".join(names)))
        names = sorted(args)

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for name in names:
        img = render(name, ICONS[name])
        path = os.path.abspath(os.path.join(OUT_DIR, name + ".png"))
        img.save(path, optimize=True)
        written.append((name, path, os.path.getsize(path)))

    print("%d icons -> %s  (outline %.1f, gloss %.2f)"
          % (len(written), os.path.abspath(OUT_DIR), iconkit.OUTLINE, iconkit.GLOSS_ALPHA))
    for n, _, s in written:
        print("  %-10s %6d bytes" % (n, s))

    # The manifest lists EVERY registered icon, not just the ones this run drew, so a partial
    # render can never quietly shrink it.
    manifest = os.path.abspath(os.path.join(OUT_DIR, "icons.json"))
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump(sorted(ICONS), f, indent=1)
    print("manifest:", manifest)

    if sheet_path:
        print("sheet:", contact_sheet(sorted(ICONS), sheet_path))


if __name__ == "__main__":
    main()
