# `src/` — Luau mirror of the Evolution Lab place

**This tree is extracted directly from the place file and is byte-identical to Studio.**
Read code from here, not through `script_read` — pulling this place through the MCP costs
roughly 180k tokens, which does not fit in one session.

Last extracted **2026-08-08** from `Evolution-lab.rbxlx.rbxl`, a save made at 00:29 the same
day. 44 scripts, 2,315,591 bytes.

## How to re-extract

```
C:\Python313\python.exe tools/rbxl_extract.py <place.rbxl> src
```

Requires `zstandard` (`pip install zstandard`); older places also need `lz4`.

**Studio's Save As dialog in this install offers only the binary `.rbxl`** — there is no XML
`.rbxlx` option in the type dropdown, and renaming the extension does not convert anything
(the file stays binary, `Type of file` still reads *Roblox Place*). `tools/rbxl_extract.py`
parses the binary format directly, so the missing option does not matter. Note that Studio
appends `.rbxl` to whatever name is typed, which is why the place on disk is called
`Evolution-lab.rbxlx.rbxl`.

## File naming

Rojo convention, so the instance class survives the round trip:

| Class | Suffix |
|---|---|
| `ModuleScript` | `.lua` |
| `Script` | `.server.lua` |
| `LocalScript` | `.client.lua` |

`ServerMain.lua` was renamed to `ServerMain.server.lua` in the 2026-08-08 extraction — it is a
`Script`, and pushing it back as a `ModuleScript` would stop the server booting.

## Verification of the 2026-08-08 extraction

Six files were checked against the live Edit datamodel on both length and a positional rolling
checksum (`sum = (sum + byte(i) * i) % 2147483647`), and the place's total
`LuaSourceContainer` count was compared with the number of files written:

| File | Bytes | Checksum |
|---|---|---|
| `ServerScriptService/RobuxShopService.lua` | 4,020 | match |
| `ServerScriptService/DNAService.lua` | 23,439 | match |
| `ServerScriptService/ZoneBuilder.lua` | 493,867 | match |
| `ReplicatedStorage/Modules/GameConfig.lua` | 143,405 | match |
| `StarterPlayer/StarterPlayerScripts/MainUI.client.lua` | 215,079 | match |
| `ServerScriptService/PlayerDataService.lua` | 14,622 | match |

Studio reports **44** `LuaSourceContainer`s; the extraction wrote **44** files.

`tools/luastruct.py` passes on all 44. `tools/luanames.py` reports four names, all checked and
all false positives or dead code:

- `MainUI.client.lua:730` `animatePanel` — a forward-declared `local` assigned by
  `function animatePanel(...)` inside a `do` block. That pattern is deliberate (it keeps the
  file under Luau's 200-local register cap) and the linter does not pair the two.
- `LightConfig.server.lua:38`, `Type.lua:23` — `Game`, the deprecated Roblox global, in
  third-party LightConfig code parked in `ServerStorage` that sets nothing.
- `ZoneBuilder_pre_gate_axis.lua:110,112` — a `_PushBackup` snapshot, dead code.

## What is in here

All 44 scripts in the place, including `ServerStorage/_PushBackup/*` (older snapshots kept
inside the place) and the third-party `ServerStorage/LightConfig`. The `_PushBackup` copies are
**not** live code — do not edit them and do not read them for current behaviour.

## Applying changes back to Studio

Studio remains the source of truth for running code; this tree is a mirror. When pushing back:

1. `list_roblox_studios` → `set_active_studio` to confirm the right instance.
2. Overwrite whole scripts rather than patching if the two have diverged — `old_string` anchors
   from a stale mirror will not match.
3. `multi_edit` only works against the **Edit** datamodel; ask for Stop if Studio is in Play.
   Its `replace_all` has reported success while changing nothing — always check the count.
4. After any `MainUI` edit, run the `loadstring` check (see `ROADMAP.md`); the register cap
   fails silently and takes the whole HUD with it.
5. `ZoneBuilder.Build()` skips any zone already present in `workspace.Zones`, so decoration
   changes stay invisible until `BUILD_VERSION` forces a rebuild.

---

## Historical: how this tree existed before 2026-08-08

The mirror was originally reconstructed on 2026-08-03 from agent transcripts, after a session
hit its API limit mid-edit and left the work only inside a Studio session that later
disconnected. `script_read` results were stitched back with overlap dedup and `multi_edit`
inputs replayed as exact substitutions.

That method produced a **partial** tree — 14 files, with `ZoneService`, `PetService`,
`PlayerDataService`, `DNAService` and others missing entirely — and it drifted badly out of date
between sessions (`ZoneBuilder` was 163k here against 273k in Studio). Direct extraction from
the place file replaces it and is the only method that should be used from now on.

Two fixes found while reviewing those replayed `CreatureService` edits, kept here because they
were written blind and had never been read back by anyone:

- **Rig animation was dead metadata.** `att()` records a `motion` / `amp` / `speed` / `phase`
  per joint, but the idle loop only applied the static `offset`, so every limb was welded.
- **The hit tween deformed the rig.** It tweened `body.Size` to a cube of `tier.size`, correct
  back when every creature was a sphere; against a rig torso the first click squashed the body
  and it never came back. It now tweens off `bodyBaseSize`.
