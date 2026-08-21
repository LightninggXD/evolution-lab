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


def id_table_span(source):
    """Where the body of `local ID = { ... }` starts and ends."""
    start = source.index("local ID = {")
    end = source.index("\n}", start) + len("\n}")
    return start, end


def id_rows_in(source):
    """Every `name = "rbxassetid://n"` row already in the Lua ID table, name -> id.

    Read out of the LUA rather than out of `uploaded.json`, because the two are deliberately not
    the same set -- see `patch_id_table`.
    """
    start, end = id_table_span(source)
    body = source[start:end]
    return dict(re.findall(r'^\t([a-z_0-9]+)\s*=\s*"(rbxassetid://\d+)"', body, re.M))


def pinned_rows(source):
    """Names whose row carries `-- store`, which the ID table uses to mean NOT OUR UPLOAD.

    These are the rows the rebuild silently reversed. A dozen of them have a house PNG on disk and
    an old house upload recorded in `uploaded.json` under the same name, showing a DIFFERENT
    PICTURE -- `IconLibrary`'s header says so in as many words: "redrawing one and re-uploading it
    silently swaps the HUD back to the house look". The marker is the file telling this tool to
    keep its hands off, so it is read rather than ignored.
    """
    start, end = id_table_span(source)
    body = source[start:end]
    return set(re.findall(r'^	([a-z_0-9]+)\s*=\s*"rbxassetid://\d+",\s*--\s*store', body, re.M))


def patch_id_table(source, ids):
    """Update the id on rows that exist, append rows that do not, and TOUCH NOTHING ELSE.

    ===== THIS FUNCTION USED TO REBUILD THE TABLE, AND THAT DESTROYED THE FILE =====

    It used to replace the whole body with one row per entry of `uploaded.json`, name-sorted, and
    its docstring claimed that was "the surgical replacement that cannot damage" the comments. It
    could not damage the comments and it deleted the DATA, because **`uploaded.json` is the record
    of our own PNG uploads and the ID table holds much more than those.** Measured 2026-08-21, on
    one run that was adding ten new icons:

      * **51 rows deleted.** Every `-- store` id -- the seven aura tiers, `dna`, `gift`, `paw`,
        `potion`, `plus`, `bolt`, `backpack`, `shop`, `upgrade`, `wheel`, `zone`, `book`, `robux`
        -- and the entire 2026-08-17 Decal batch, which is all fifteen relic foods. None of those
        has a PNG on disk, so none is in `uploaded.json`, so the rebuild simply did not emit them.
      * **Seven rows silently repointed at house art.** `dna`, `gift`, `paw`, `potion`, `plus`,
        `bolt` and `backpack` each have an old house upload recorded in `uploaded.json` AND a store
        id that this table deliberately overrides it with. Rebuilding reinstated the house PNG,
        which is exactly the swap `IconLibrary`'s own header warns about.
      * And it printed **"74 untouched (still on their previous id)"** while doing all of it, which
        is why the output looked safe. The damage was found only because fifteen relic tiles
        rendered as holes in a screen capture.

    A row is a line; patching lines is what keeps a hand-written table hand-written.
    """
    start, end = id_table_span(source)
    body = source[start:end]
    existing = id_rows_in(source)
    rows_in = {k: v for k, v in ids.items()
               if not k.startswith("_") and re.fullmatch(r"rbxassetid://\d+", str(v))}

    pinned = pinned_rows(source)
    changed, added, skipped = [], [], []
    for name in sorted(rows_in):
        want = rows_in[name]
        if existing.get(name) == want:
            continue
        if name in pinned:
            # a `-- store` row is never ours to move, however new the upload is
            skipped.append((name, existing[name], want))
            continue
        if name in existing:
            # replace ONLY the id inside that one row, so its alignment and any trailing comment
            # survive -- `-- store` is load-bearing documentation on a dozen of these
            pattern = r'(^\t%s\s*=\s*")rbxassetid://\d+(")' % re.escape(name)
            body, n = re.subn(pattern, lambda m: m.group(1) + want + m.group(2), body,
                              count=1, flags=re.M)
            if n == 1:
                changed.append((name, existing[name], want))
        else:
            added.append((name, want))

    if added:
        width = max(len(n) for n, _ in added)
        block = "\n".join('\t%-*s = "%s",' % (width, n, v) for n, v in sorted(added))
        # in front of the closing brace, which is where a hand-added row would go
        body = body[: -len("\n}")] + "\n\n" + block + "\n}"

    return source[:start] + body + source[end:], changed, added, skipped


def audit_reachability(source, _ids):
    """Cross-check the two halves of IconLibrary: `BY_EMOJI` names an icon, `ID` gives it an id.

    Both directions are real faults and neither raises an error at runtime:
      * a BY_EMOJI row naming an icon with no ID row resolves to nil -- the call site silently
        falls back to the emoji glyph, which looks exactly like "we never drew that one";
      * an ID row nothing points at is art that was drawn, uploaded and is unreachable. That is
        not hypothetical -- `zone` sat in this file that way, drawn and orphaned.
    """
    body = source[source.index("local BY_EMOJI = {"):source.index("\n}", source.index("local BY_EMOJI = {"))]
    referenced = set(re.findall(r'\]\s*=\s*"([a-z_]+)"', body))
    # AGAINST THE LUA TABLE, not against `uploaded.json` -- the table is what the game reads and it
    # holds store and Decal ids that file has never heard of.
    ids = id_rows_in(source)
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
    before_rows = id_rows_in(lua)
    new_lua, changed, added, skipped = patch_id_table(lua, record)
    after_rows = id_rows_in(new_lua)

    # WHAT THE TABLE ITSELF IS ABOUT TO DO, which is a different report from what was uploaded. The
    # old version printed only the latter, and that is how a run which deleted 51 rows read clean.
    print("")
    print("IconLibrary ID table: %d rows -> %d rows" % (len(before_rows), len(after_rows)))
    for name, old_id, new_id in changed:
        print("  REPOINT %-14s %s -> %s" % (name, old_id, new_id))
    for name, new_id in added:
        print("  ADD     %-14s %s" % (name, new_id))
    for name, old_id, new_id in skipped:
        print("  PINNED  %-14s kept %s (would have been %s)" % (name, old_id, new_id))
    lost = sorted(set(before_rows) - set(after_rows))
    if lost:
        raise SystemExit("REFUSING: this would delete %d ID rows: %s" % (len(lost), ", ".join(lost)))

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
