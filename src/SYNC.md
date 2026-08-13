# `src/` — Luau mirror of the Evolution Lab place

> ## ✅ IN SYNC WITH THE CLOUD PLACE (2026-08-13, fifth session)
>
> **The sweep the block below asked for has been run, and it predicted correctly.** Studio on
> **Evolution Lab BETA V0.2** (`GameId` 10675543038 / `PlaceId` 102217824272435), 58 scripts. Every
> shared file hashed identical except the two whose fixes had landed in the *local* file only:
> `MainUI` at **378,671** (pre-11.32) and `HatchReveal` at **48,310** (pre-11.19). Both pushed from
> `src/` over the HTTP bridge and verified byte-identical — `MainUI` **380,324 / roll 144286258**,
> `HatchReveal` **54,074 / roll 648462907** — and `MainUI` `loadstring`s clean.
>
> **Direction was proven before writing:** both Studio hashes reproduce byte-exactly from the git
> blob at `ab93230^`, so Studio was simply behind that commit. That is the cheap version of the rule
> in the block below — hash the historical blobs rather than guessing.
>
> Remaining known differences, both fine to leave: three `ServerStorage.LightConfig` files carry
> **CRLF** where `src/` has LF (dead third-party code — the byte counts differ by exactly the line
> count), and two Studio-only backups exist, `_PushBackup.MachineService_removed_2026_08_11` and
> `_RewardFresh`.
>
> ⚠️ **`tools/push_two.lua` has served its purpose** — its baked hashes describe a push that is now
> done. Re-hash both sides before trusting it again.
>
> ---
>
> ## Historical: IN SYNC (2026-08-13, fourth session) — after Studio had reverted SIX files
>
> A full sweep of all 59 live scripts found six behind, and **each hashed byte-identical to an older
> commit** rather than to anything Studio had authored: `UITheme` (`e4b6c17`), `BossService`
> (`416cb67`), `PetService` (`444bd44`), `ZoneBuilder` (`416cb67`), `HatchReveal` (`796a83f`),
> `MainUI` (`975b07b`). All six were pushed from `src/` and verified byte-identical. **57 shared
> paths now agree**; `ServerScriptService.ZoneDecor` is Studio-only (orphaned dead code) and the six
> `ServerStorage._PushBackup.*` are disk-only.
>
> **Prove the DIRECTION before pushing, and this is how it is cheap:** hash every historical git
> blob of the differing file and look for the revision that reproduces Studio's hash. A hit means
> Studio is simply behind and the push cannot destroy work; a miss means Studio holds something that
> exists nowhere else and must be pulled first. `tools/` has the rolling hash both sides use.
>
> **The six were not lost work — the WRONG DOCUMENT was open.** `game.GameId` and `game.PlaceId`
> were both **0** and the window title read `...\evolution-lab\Evolution-lab.rbxl`: Studio was on the
> **local place file** (written 2026-08-12 16:27), not the published cloud place. **Read
> `game.GameId` before you interpret a sweep** — 0 means the local file and the differences are just
> that snapshot's age. `game:Save()` does not exist in this version, but `AppActivate` + `SendKeys ^s`
> does and the local file now holds the restore.
>
> ⚠️ **These pushes are in the LOCAL file only.** When Studio next opens **Evolution Lab BETA
> V0.2** (`10675543038` / `102217824272435`), sweep again before anything else — expect a different
> set of differences there.

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

`tools/luastruct.py` passes on all 44.

## The `luanames.py` baseline — **re-measured 2026-08-12, and it is 13, not 6**

**This section was badly stale and was actively misleading**, which matters because it is written as
a tripwire: it used to say "six across five files… an agent that sees six here has regressed
nothing; seven means something new". A cold agent running the linter today sees **13 names across
10 files** and, believing this note, would conclude it had broken seven things. Two agents reached
that conclusion on 2026-08-12 before the count was checked. The file grew from 44 scripts to 56
between those two measurements; the note did not.

**The baseline is 13 names across 10 files.** Every one is checked and is a false positive or dead
code. More than 13 means something new; the list below says which are already known.

| File | Line | Name |
|---|---|---|
| `MainUI.client.lua` | 804 | `animatePanel` |
| `MainUI.client.lua` | 3364 | `stop` |
| `LoadingScreen.client.lua` | 208, 231 | `modules`, `bar` |
| `SoundLibrary.lua` | 334 | `flatCache` |
| `StatsService.lua` | 70 | `publish` |
| `FirstJoin.client.lua` | 333 | `runGuide` |
| `HatchReveal.client.lua` | 82 | `bestDist` |
| `RarityBeam.client.lua` | 174 | `toastSeq` |
| `Type.lua` | 23 | `Game` |
| `LightConfig.server.lua` | 38 | `Game` |
| `ZoneBuilder_pre_gate_axis.lua` | 110, 112 | `scatterPoint`, `makeSign` |

They are three causes, not eleven:

- **The linter's binding blind spot** — a `local` declared inside a `do` block, before a `repeat`,
  or forward-declared and assigned by a later `function name(...)`. That covers `animatePanel`,
  `stop`, `modules`, `bar`, `flatCache`, `publish`, `runGuide`, `bestDist` and `toastSeq`.
  `animatePanel`'s pattern is deliberate: it is what keeps MainUI under Luau's 200-local cap.
- **`Game`, the deprecated Roblox global**, in the third-party LightConfig code parked in
  `ServerStorage`, which sets nothing.
- **`_PushBackup` snapshots**, which are dead code by definition — never edit them and never read
  them for current behaviour.

`EvolutionVisuals.lua:305` `waited` was on the old list and is **no longer reported**; it was fixed
at some point and nobody updated this file, which is the same failure in the other direction.

**If you change this number, say so here in the same commit.** A stale tripwire is worse than none:
it converts every real regression into "probably just the baseline".

## Reading a big file without loading it — `tools/luamap.py`

Five files in this tree cannot be read whole without spending most of a context window:

| File | Size | ~tokens if read whole |
|---|---:|---:|
| `ServerScriptService/ZoneBuilder.lua` | 560 KB | **~147k** |
| `StarterPlayer/.../MainUI.client.lua` | 379 KB | **~99k** |
| `ReplicatedStorage/Modules/GameConfig.lua` | 262 KB | ~69k |
| `ServerScriptService/CreatureService.lua` | 204 KB | ~54k |
| `ServerScriptService/BossService.lua` | 156 KB | ~41k |

**Never `Read` one of these without an `offset`/`limit`.** One such read poisons the rest of the
session: every later request re-sends it.

`tools/luamap.py` prints a table of contents — kind, name, start line, line count, byte weight, and
the exact `offset`/`limit` to read that entry — for a few kilobytes:

```
python tools/luamap.py --by-size --top 20 --min-lines 5 src/ServerScriptService/ZoneBuilder.lua
python tools/luamap.py --grep decorationBuilders src/ServerScriptService/ZoneBuilder.lua
```

Measured on ZoneBuilder: 91 top-level entries covering 81% of the file, and the **largest single
one is `buildValleySide` at 1,267 lines / 76 KB (~20k tokens)**. So the worst case a targeted read
can cost is about a seventh of reading the file, and a typical one is 2–5k.

**It is a keyword counter, not a parser, and the counting is the whole trick.** The first version
counted `function|if|for|while|do` against `end`, which double-counts every loop — `for ... do`
opens on both keywords and is closed by one `end` — so depth never returned to zero and the map
reported a single 8,737-line "function" covering 99% of ZoneBuilder. `for`/`while` are therefore not
openers; their `do` is, tracked through `pending_do` so a wrapped loop header still claims the right
one. If the coverage percentage ever collapses toward one giant entry again, that counter is why.

## Why ZoneBuilder is NOT split, and what to do instead

It was split once (`ZoneBuilder` + `ZoneDecor`) and the split was reverted; `ZoneDecor` sat as
orphaned, diverged dead code until 11.27 deleted it. The mechanism was a function module closing
over ZoneBuilder's top-level locals, with **29 helpers passed in by hand and 4 names returned** — so
adding a helper call meant editing both lists, and forgetting one produced a `nil` at build time
rather than an error at edit time. A fresh `require` of a cloned ZoneBuilder also did not give a
fresh ZoneDecor, which is its own rebuild trap.

The map replaces the reason to split: the unit worth addressing is the **function**, not the file,
and a split would still hand you a 76 KB `buildValleySide` when that is what you need. If a file
really must shrink, shrink that function first — it is the actual monolith — and treat it as a
roadmap row with a rebuild to verify, not as a side quest.

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
