"""
harvest_free_assets.py -- pull the free Roblox Creator Store assets that are worth
knowing about into a catalogue on disk, so an agent does not have to re-crawl the
store every session.

WHY THIS EXISTS
---------------
The Creator Store web pages (create.roblox.com/store/models/trending) are a React
app: WebFetch gets an empty shell, and the Studio `search_asset` tool returns a
junkyard for most visual queries ("vip noob trap", "Toilet Heaven"). The API that
actually backs those pages is public and unauthenticated, so we hit it directly.

  marketplace list :  GET apis.roblox.com/toolbox-service/v1/marketplace/{typeId}
                      ?limit&sortType&pageNumber&keyword
                      -> { data: [ { id: <assetId> }, ... ] }
  details          :  GET apis.roblox.com/toolbox-service/v1/items/details
                      ?assetIds=a,b,c
                      -> { data: [ { asset: {...}, creator: {...} }, ... ] }

Details is the only call that carries name / creator / price, and it caps out
around 30 ids per request, so results are chunked.

OUTPUT
------
  assets/free_assets/catalog.json  -- every row, machine readable
  assets/free_assets/CATALOG.md    -- the same grouped by query, for a human

Run:  C:\\Python313\\python.exe tools/harvest_free_assets.py
(The `python` on PATH is the Microsoft Store stub and exits 49 -- use the full path.)
"""

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://apis.roblox.com/toolbox-service/v1"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

# toolbox assetTypeId -> label
# NOTE: these are the toolbox endpoint's own category ids, NOT Enum.AssetType.
# Probed 2026-08-14: 10/3/13/40 answer 200; 1, 8 and 9 all answer 400.
TYPES = {10: "Model", 3: "Audio", 13: "Decal", 40: "MeshPart"}

# (assetTypeId, keyword, why-it-is-here). An empty keyword is the plain
# "trending" feed for that type -- exactly what the store page shows.
QUERIES = [
    (10, "", "trending models (what the store front page shows)"),
    (10, "skybox", "skybox -- Lighting has no Sky object, this is the real gap"),
    (10, "vfx pack", "particle / effect packs"),
    (10, "particle effect", "particle emitters"),
    (10, "simulator ui", "simulator-style interface kits"),
    (10, "egg hatch", "hatching / egg feedback"),
    (10, "pet follow", "pet rigs and followers"),
    (10, "cartoon tree", "stylised set dressing"),
    (10, "low poly nature", "stylised set dressing"),
    (10, "portal", "zone gates"),
    (3, "", "trending audio"),
    (3, "ui click", "interface clicks"),
    (3, "coin collect", "pickup / currency"),
    (3, "level up", "progression stingers"),
    (3, "magic whoosh", "evolve / ability whooshes"),
    (3, "impact hit", "combat hits"),
    (13, "particle texture", "sparkle / glow sprites for ParticleEmitter"),
    (13, "sparkle", "sparkle sprites"),
    (13, "gradient", "UI gradients and glows"),
    (40, "low poly", "stylised meshes"),
]

PER_QUERY = 30
DETAIL_CHUNK = 30


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def list_ids(type_id, keyword, limit=PER_QUERY):
    """One page of the marketplace feed. sortType=3 is the store's popularity sort."""
    params = {"limit": limit, "sortType": 3, "pageNumber": 0}
    if keyword:
        params["keyword"] = keyword
    url = f"{API}/marketplace/{type_id}?{urllib.parse.urlencode(params)}"
    payload = get_json(url)
    return [row["id"] for row in payload.get("data", []) if "id" in row]


def details(asset_ids):
    """Names / creators / prices. Chunked -- the endpoint rejects long id lists."""
    out = []
    for i in range(0, len(asset_ids), DETAIL_CHUNK):
        chunk = asset_ids[i : i + DETAIL_CHUNK]
        url = f"{API}/items/details?assetIds={','.join(str(a) for a in chunk)}"
        try:
            payload = get_json(url)
        except urllib.error.HTTPError as exc:
            print(f"    ! details failed for {len(chunk)} ids: {exc}")
            continue
        for row in payload.get("data", []):
            asset = row.get("asset") or {}
            creator = row.get("creator") or {}
            out.append(
                {
                    "assetId": asset.get("id"),
                    "name": asset.get("name"),
                    "typeId": asset.get("typeId"),
                    "creator": creator.get("name"),
                    "creatorId": creator.get("id"),
                    # price is absent on free items in this feed; treat missing as 0
                    "price": (asset.get("price") or 0),
                    "description": (asset.get("description") or "").strip()[:200],
                    "url": f"https://create.roblox.com/store/asset/{asset.get('id')}",
                }
            )
        time.sleep(0.3)
    return out


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outdir = os.path.join(repo, "assets", "free_assets")
    os.makedirs(outdir, exist_ok=True)

    catalog = []
    seen = set()

    for type_id, keyword, why in QUERIES:
        label = TYPES.get(type_id, str(type_id))
        tag = f"{label}/{keyword or 'trending'}"
        print(f"[*] {tag}")
        try:
            ids = list_ids(type_id, keyword)
        except Exception as exc:  # noqa: BLE001 - a dead query must not kill the run
            print(f"    ! list failed: {exc}")
            continue
        rows = details(ids)
        kept = 0
        for row in rows:
            # free only, and never record the same asset twice
            if row["price"] not in (0, None):
                continue
            if row["assetId"] in seen:
                continue
            seen.add(row["assetId"])
            row["query"] = tag
            row["why"] = why
            row["assetType"] = label
            catalog.append(row)
            kept += 1
        print(f"    {kept} free, {len(rows)} seen")
        time.sleep(0.3)

    with open(os.path.join(outdir, "catalog.json"), "w", encoding="utf-8") as fh:
        json.dump(catalog, fh, indent=2, ensure_ascii=False)

    # grouped markdown
    by_query = {}
    for row in catalog:
        by_query.setdefault((row["query"], row["why"]), []).append(row)

    lines = [
        "# Free Roblox Creator Store assets — harvested catalogue",
        "",
        f"{len(catalog)} unique free assets, pulled by `tools/harvest_free_assets.py`.",
        "",
        "**Nothing here has been inserted into the place.** These are candidates only.",
        "Read `NOTES.md` next to this file before using any of them — Model-type assets",
        "from the free store are the standard Roblox backdoor vector and must be script-",
        "scanned after insertion, whereas Audio / Decal / Sky assets cannot carry code.",
        "",
    ]
    for (tag, why), rows in by_query.items():
        lines.append(f"## {tag}")
        lines.append(f"_{why}_")
        lines.append("")
        lines.append("| assetId | name | creator |")
        lines.append("| --- | --- | --- |")
        for row in rows:
            name = (row["name"] or "").replace("|", "/")
            creator = (row["creator"] or "").replace("|", "/")
            lines.append(f"| `{row['assetId']}` | {name} | {creator} |")
        lines.append("")

    with open(os.path.join(outdir, "CATALOG.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))

    print(f"\n{len(catalog)} free assets -> {outdir}")


if __name__ == "__main__":
    main()
