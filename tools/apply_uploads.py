"""
apply_uploads.py -- writes a batch of freshly uploaded asset ids back into the two files that
have to agree about them.

WHY THIS IS A SCRIPT AND NOT A CAREFUL HALF HOUR WITH AN EDITOR
---------------------------------------------------------------
An icon's id lives in two places: `assets/icons/uploaded.json` (the record of what was uploaded)
and the `ID` table in `ReplicatedStorage/Modules/IconLibrary.lua` (what the game reads). They must
never disagree, and there are seventy-odd of them. Transcribing that by hand is not hard, it is
just long -- which is exactly the shape of job that produces one wrong digit in one id and an
invisible bug: a broken image id is not an error in Roblox, it is an empty square.

REGENERATING A PNG DOES NOT CHANGE ITS ASSET ID. Uploading is what mints one, and re-uploading a
name mints a SECOND asset rather than updating the first. So the flow is: draw, upload the whole
set in one call, feed the resulting map through here.

  py tools/apply_uploads.py uploads.json          write both files
  py tools/apply_uploads.py uploads.json --check  say what would change, touch nothing

`uploads.json` is exactly what the upload tool returns -- a map of image URL to asset id:

  { "http://127.0.0.1:8731/assets/icons/dna.png": "rbxassetid://81434690219399", ... }
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPLOADED = os.path.join(ROOT, "assets", "icons", "uploaded.json")
LIBRARY = os.path.join(ROOT, "src", "ReplicatedStorage", "Modules", "IconLibrary.lua")


def names_from(upload_map):
    """URL -> icon name, by basename. The name is the contract between the PNG, `uploaded.json`,
    the `ID` table and every `BY_EMOJI` row, so it is derived rather than typed anywhere."""
    out = {}
    for url, asset in upload_map.items():
        name = os.path.basename(url)
        if not name.endswith(".png"):
            raise SystemExit("not a png url: %s" % url)
        if not re.fullmatch(r"rbxassetid://\d+", asset):
            raise SystemExit("not an asset id for %s: %r" % (name, asset))
        out[name[:-4]] = asset
    return out


def rewrite_id_table(source, ids):
    """Replace the body of `local ID = { ... }` with one row per icon, name-sorted and aligned.

    Anchored on the two literal lines rather than parsed: this file is hand-written Lua with
    comments that matter, and the surgical replacement is the one that cannot damage them.
    """
    start = source.index("local ID = {")
    end = source.index("\n}", start) + len("\n}")
    # `uploaded.json` carries a `_note` explaining the never-re-upload rule, which is a note to
    # humans and not an icon. Anything not shaped like an asset id is skipped rather than written
    # into Lua, where it would be a syntax-valid row pointing at prose.
    rows_in = {k: v for k, v in ids.items()
               if not k.startswith("_") and re.fullmatch(r"rbxassetid://\d+", str(v))}
    width = max(len(n) for n in rows_in)
    rows = "\n".join(
        '\t%-*s = "%s",' % (width, name, rows_in[name]) for name in sorted(rows_in)
    )
    return source[:start] + "local ID = {\n" + rows + "\n}" + source[end:]


def audit_reachability(source, ids):
    """Cross-check the two halves of IconLibrary: `BY_EMOJI` names an icon, `ID` gives it an id.

    Both directions are real faults and neither raises an error at runtime:
      * a BY_EMOJI row naming an icon with no ID row resolves to nil -- the call site silently
        falls back to the emoji glyph, which looks exactly like "we never drew that one";
      * an ID row nothing points at is art that was drawn, uploaded and is unreachable. That is
        not hypothetical -- `zone` sat in this file that way, drawn and orphaned.
    """
    body = source[source.index("local BY_EMOJI = {"):source.index("\n}", source.index("local BY_EMOJI = {"))]
    referenced = set(re.findall(r'\]\s*=\s*"([a-z_]+)"', body))
    missing = sorted(referenced - set(ids))
    orphan = sorted(set(ids) - referenced)
    if missing:
        print("  !! BY_EMOJI names icons with no ID row (they resolve to nil): %s" % ", ".join(missing))
    if orphan:
        print("  !! ID rows nothing maps to (drawn but unreachable): %s" % ", ".join(orphan))
    if not missing and not orphan:
        print("  reachability: every icon has an id and every id has at least one emoji")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    if len(args) != 1:
        raise SystemExit(__doc__.strip().splitlines()[-1])

    with open(args[0], encoding="utf-8") as f:
        fresh = names_from(json.load(f))

    with open(UPLOADED, encoding="utf-8") as f:
        record = json.load(f)
    before = dict(record)
    record.update(fresh)

    added = sorted(k for k in fresh if k not in before)
    moved = sorted(k for k in fresh if k in before and before[k] != fresh[k])
    kept = sorted(k for k in record if k not in fresh and not k.startswith("_"))

    print("%d uploaded: %d new, %d re-pointed" % (len(fresh), len(added), len(moved)))
    for k in added:
        print("  NEW  %-14s %s" % (k, fresh[k]))
    for k in moved:
        print("  MOVE %-14s %s -> %s" % (k, before[k], fresh[k]))
    if kept:
        # Loud, because this is the dangerous case: an icon whose art was redrawn but which was
        # left out of the upload keeps pointing at its OLD asset, and the game shows the old
        # drawing with no error anywhere.
        print("  %d untouched (still on their previous id): %s" % (len(kept), ", ".join(kept)))

    with open(LIBRARY, encoding="utf-8") as f:
        lua = f.read()
    new_lua = rewrite_id_table(lua, record)

    if check:
        print("\n--check: nothing written")
        return

    with open(UPLOADED, "w", encoding="utf-8") as f:
        json.dump(record, f, indent=1, sort_keys=True)
        f.write("\n")
    with open(LIBRARY, "w", encoding="utf-8", newline="\n") as f:
        f.write(new_lua)
    print("\nwrote %s\nwrote %s" % (UPLOADED, LIBRARY))
    print("NOW: check every new name has a BY_EMOJI row, or the art is unreachable.")


if __name__ == "__main__":
    main()
