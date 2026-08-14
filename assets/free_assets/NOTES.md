# Free asset harvest — what is here, what is safe, what was actually used

Written 2026-08-14. Read this before touching `catalog.json` / `CATALOG.md`.

## What was collected

`tools/harvest_free_assets.py` pulled **596 unique free Creator Store assets** into
`catalog.json` (machine readable) and `CATALOG.md` (grouped, human readable), across
20 queries: models, audio, decals and meshes.

**Nothing in the catalogue has been inserted into the place.** It is a candidate list
for the next agent, nothing more. The one asset actually adopted is recorded at the
bottom of this file.

### How to re-run it

```
C:\Python313\python.exe tools/harvest_free_assets.py
```

## Why the obvious routes did not work

Worth knowing so nobody burns the time again:

- **`create.roblox.com/store/models/trending` cannot be fetched.** It is a React app;
  a plain fetch returns an empty shell with no listings in it.
- **The Studio `search_asset` tool is close to useless for visual queries.** Asked for
  "stylized cartoon skybox clouds" it returned mirrors, a "vip noob trap" and "Toilet
  Heaven". It is fine for audio, where names are literal.
- **The API behind the store pages is public and unauthenticated**, and that is what the
  harvester uses:
  - `apis.roblox.com/toolbox-service/v1/marketplace/{typeId}?limit&sortType=3&pageNumber&keyword`
    — ids only
  - `apis.roblox.com/toolbox-service/v1/items/details?assetIds=…` — names, creators, prices;
    about 30 ids per call
- **The toolbox `typeId`s are its own, not `Enum.AssetType`.** Probed: `10` Model, `3` Audio,
  `13` Decal, `40` MeshPart answer 200. `1`, `8` and `9` answer **400** — the first run lost
  all three decal queries to exactly that.

## SampleFocus: legally usable in the game, but do NOT mirror it into this repo

`samplefocus.com/tag/roblox` 403s a plain fetch and needs a real browser User-Agent. That is
the least of it. Its Standard License (read 2026-08-14) says:

- ✅ Samples **may** be used in games, commercially, with **no attribution and no royalties**.
- ❌ You may not "upload or make the sound available in a **complete, archived, downloadable,
  or readily extractable format**", nor include it in a "sample pack, **sound library** …
  or similar product".
- ❌ A separate clause forbids use in **any AI/ML training, dataset or corpus**, and the site
  serves a machine-readable `tdm-policy` reserving text-and-data-mining rights.

Bulk-downloading the tag page into a folder of mp3s in this repo is precisely the archived,
readily-extractable sound library the licence prohibits — so **that was not done**, and should
not be done later either. Kristina downloading individual samples herself through the site is
fine and is what the licence contemplates.

**And it is moot for this project anyway.** A downloaded mp3 is useless to Roblox until it is
uploaded as an audio asset under her own account, which is a moderation queue and a rights
attestation per file. `SoundLibrary.lua` already solves the same problem the right way, with
free first-party Roblox audio (mostly ProSoundEffects) that needs no upload at all — see the
header of that file. **Roblox's own free audio is the route for sound. SampleFocus is a dead
end here.**

## Safety: free MODELS are the backdoor vector, the other types are not

A Roblox `Model` from the free store can carry `Script`s, and free models are the classic
delivery mechanism for backdoors (`require(assetId)` loaders, HttpService beacons). `Audio`,
`Decal`, `MeshPart` and `Sky` assets cannot contain code at all.

**Rule for the next agent: insert any Model into `ServerStorage` first, never straight into
`Workspace`, then scan before use:**

```lua
for _, d in ipairs(inserted:GetDescendants()) do
    if d:IsA("LuaSourceContainer") then warn("CODE: " .. d:GetFullName()) end
end
```

All three skyboxes trialled below scanned as **0 scripts**, as expected for `Sky`.

## Quality of the harvest, by category

Not all 596 rows are worth anything. Judged by eye off the names:

| group | verdict |
| --- | --- |
| `Model/skybox` | **genuinely good** — 29 real skyboxes, and the one adopted asset came from here |
| `Audio/*` (177) | plausible, but redundant — `SoundLibrary.lua` already covers this ground |
| `Decal/particle texture` | mixed; some real smoke/flame sprites among the junk |
| `Decal/sparkle` | **worthless** — it is avatar face decals and My Little Pony, not particle sprites |
| `Model/trending` | **worthless for this game** — Spawn Point, HD Admin, Noob NPC, Grass Baseplate, "Shift to run". These are the things an *empty* place needs. Evolution Lab has all of them, better |
| `Model/simulator ui`, `egg hatch`, `pet follow` | untested; treat as script-bearing and scan |

That last row is the important one. The Creator Store trending list is dominated by
beginner-scaffolding assets. This game is well past that stage, so "install what is trending"
would make it worse, not more modern.

## What was actually adopted

**One asset: "Clear Blue Sky (Skybox)" by Oghmond — `18586545848`, free.**

`Lighting` had **no `Sky` child at all**; the game had been rendering against Roblox's built-in
default sky. The full reasoning, the two rejected candidates, and the settle-time trap that
nearly shipped the wrong one are written into `applyDistanceFog()` in
`src/ServerScriptService/ZoneBuilder.lua` — read the `WORLD_SKY` comment there, it is the real
record. Two things worth repeating here:

1. **A skybox is a light source, not a backdrop.** Under ShadowMap/Future it feeds ambient, so a
   texture full of white cloud washes the world out and silently undoes the contrast pass, with
   every `Ambient`/`OutdoorAmbient`/`ToonPunch` value still reading correct.
2. **Skybox-derived ambient settles a beat after the `Sky` is parented.** A capture taken
   immediately shows the *old* lighting under the *new* sky. `task.wait(3)` between parenting and
   capturing, or you will pick the wrong sky — this nearly happened.

Clouds are **`Terrain.Clouds`** (`Cover` 0.62, `Density` 0.55), not a cloud texture. Being real
geometry they contribute nothing to ambient, which is how the world keeps both cloud cover and a
Guardian Titan that is still brown at 1240 studs.
