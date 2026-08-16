# Evolution Lab — Launch & Modernisation Roadmap

**This file is the source of truth for what is done.** Read it before starting any work.

Created 2026-08-08 from a gap analysis of the live Studio datamodel against the current market
(+1 Speed Evolve, Pet Simulator 99, Grow a Garden / Steal a Brainrot).

---

## Rules for agents

1. **Studio is the source of truth for code. This file is the source of truth for status.**
   `src/` is a mirror and has repeatedly fallen behind — see Phase 0.
2. **A task becomes `[x]` only after it has been verified live in Studio.** Reading the code is
   not verification. Every row carries its own verification step; if you cannot run it, the task
   stays `[~]` and you say why.
3. Status legend:
   `[ ]` not started · `[~]` in progress · `[x]` done & verified · `[!]` blocked (write the
   blocker inline) · `[-]` dropped (write why)
4. **👤 OWNER** rows cannot be done by an agent. They need Kristina on the Roblox Creator
   Dashboard or in Studio's Properties panel. **Never invent an id.** Stop and report.
5. Append a dated line to the **Changelog** at the bottom every session. Never rewrite history.
6. Before editing `MainUI`, read the register-cap rule in Phase 2 — it has silently deleted the
   whole HUD twice. Before editing `ZoneBuilder`, read the notes in `src/STATUS.md`.
7. Do not reorder or renumber tasks. If something new is needed, add it with the next free ID in
   its phase.

### Studio tooling traps (cost real time before)

- `multi_edit` only works against the **Edit** datamodel — ask for Stop if Studio is in Play.
  Its `replace_all` has reported success while changing nothing; **always check the count.**
- `require` in **Edit** mode returns the module as first pulled that session. Use
  `loadstring(inst.Source)()` when testing an edit.
- `require` in **Play** mode builds a *fresh* service whose `PlayerDataService.Cache` is empty.
  Populate `PDS.Cache[plr.UserId]` in the same call or the probe sees no player data.
- **`script_grep` is BLIND TO `ServerScriptService` WHILE STUDIO IS IN PLAY, and it fails silently.**
  Measured 2026-08-16: in Play, `function DNAService.` returns "No matches found" while the very same
  source, read back with `execute_luau` on the Server datamodel, has that definition at line 151. The
  same query run in Edit finds it. Nothing warns you -- a false negative looks exactly like a name
  that does not exist, which is how one session concluded a live function had been renamed. **Grep
  for server code in Edit; in Play, read `.Source` with `execute_luau` instead.**
- `screen_capture` does **not** stop Play (re-checked 2026-08-08: `multi_edit` still refused with
  "Edit datamodel is not available in Play mode" straight after a capture). Capturing *during* Play
  is the only way to see a HUD. Budget one slow attempt — the first call of a session took >120 s and
  came back in the background; the next two were quick.
- **A capture is downscaled about 2x, so a 448 px panel is unreadable at native size.** Push a
  `UIScale` of ~1.6 onto the panel from the `Client` datamodel first, capture, then remove it.
- **A structural probe cannot see clipped text.** After any tile-layout change, walk the labels and
  check `TextLabel.TextFits` — `themeLabel` floors text at 14 px, so a box too short for its wrapped
  text cuts the overflow instead of shrinking it, and reports nothing wrong.
- Structural checks: `C:\Python313\python.exe tools/luastruct.py` and `tools/luanames.py`.
  The `python` on PATH is the Microsoft Store stub and exits 49.
- **`luanames` baseline is 13 names across 10 files** — re-measured 2026-08-12 and again 2026-08-13,
  and `src/SYNC.md` carries the per-file list. The bullet below is the 2026-08-09 reading and is kept
  only for its explanation of the cause; **compare against 13, not 9**. The file count grew from 44
  scripts to 58 and the note did not, which cost two agents on 2026-08-12 the conclusion that they
  had broken seven things.
- **`luanames` baseline is 9 files, not the 6 recorded at 0.3** (checked 2026-08-09). It grew with
  the phases and every one is the same false positive — a local referenced from a function defined
  after it, which is a legal upvalue: `LoadingScreen` (modules, bar), `SoundLibrary` (flatCache),
  `StatsService` (publish), `ZoneBuilder_pre_gate_axis` (scatterPoint, makeSign — an archived file),
  `Type` and `LightConfig` (Game), `HatchReveal` (bestDist), `MainUI` (animatePanel), `RarityBeam`
  (toastSeq). All nine sit in code that has been demonstrated to run. **Compare against 9, and read
  the WHOLE output** — `luanames` prints its warnings interleaved with the OK lines, so tailing the
  last 30 lines silently hides the first half of the list, which is how the 6 got believed twice.

---

## Phase 0 — Sync and baseline · **blocks everything else**

`src/` is far behind Studio (`ZoneBuilder` 273k vs 163k; `ZoneService`, `PlayerDataService`,
`PotionService`, `SeasonPassService`, `StageCostume`, `EvolutionVisuals` and others exist only
in Studio). Every cold-starting agent currently burns half its context on `script_read`.

| ID | | Task | Files | Verified how |
|---|---|---|---|---|
| 0.1 | `[x]` | **👤 OWNER** Save the place to the repo. **Studio here offers only binary `.rbxl`** — there is no `.rbxlx` option in the type dropdown, and renaming does not convert. That is fine, see 0.2 | `Evolution-lab.rbxlx.rbxl` | on disk, 20.8 MB, saved 2026-08-08 00:29 |
| 0.2 | `[x]` | Extract every script's source into `src/`. Needed a **binary place parser** — `tools/rbxl_extract.py`, which reads the zstd-compressed chunk format directly (`pip install zstandard`) | `tools/rbxl_extract.py`, `src/**`, `src/SYNC.md` | 44 files written vs 44 `LuaSourceContainer`s in Studio; 6 files byte- and checksum-identical to the live datamodel |
| 0.3 | `[x]` | Run `luastruct.py` + `luanames.py`, record a clean baseline | `tools/` | `luastruct` clean on all 44. `luanames` flags **6**, all checked and dismissed — that is the baseline, see `src/SYNC.md` |
| 0.4 | `[ ]` | **👤 OWNER** Set `StreamingMinRadius 512`, `StreamingTargetRadius 3000`, `StreamingIntegrityMode PauseOutsideLoadedArea` by hand in Properties | `Workspace` | the `[Streaming]` warn at `ServerMain:35-54` stops firing on boot |
| 0.5 | `[x]` | Commit the synced tree + this file to git on a branch. `.gitignore` now excludes `*.rbxl*` — a 20 MB binary that rewrites wholesale on every save must never enter the history | `.gitignore` | 38 commits on `sync/place-mirror-and-monetization`, `src/` and `ROADMAP.md` both tracked, no place binary in the history. **Not merged to `main`** — that is a separate decision, not this row |

---

## Phase 1 — Monetisation foundation · **unblocks all revenue**

Today the game earns nothing: no game pass exists anywhere in the place, and all 7
`GameConfig.RobuxProducts` entries have `productId = 0`, so every buy button answers
*"This item isn't set up yet"* (`RobuxShopService:88`).

### 1a. The economy bug comes first

`RobuxShopService:46` does `data.DNA += product.grantDNA` — a **raw fixed number**. The packs are
1,000 and 10,000 DNA. From stage 6 on, a paid 10,000 DNA is worth **less than one kill**.

`GameConfig.ScaleReward(amount, data)` (`GameConfig:1536+`) exists for exactly this and is already
used by `RewardService`, `PlaytimeGiftService` and `SeasonPassService.grant`. Authored figures stay
as "what this is worth in stage-1 clicks" and are converted to where the player actually stands.

**Fix this before a single product is created on the dashboard** — otherwise the first buyers pay
real money for a rounding error.

### 1b. `PassService` and why ownership is cached into `data`

Every stat function in the game takes **`data`, not `player`**: `GetIncomeMult(data)`,
`GetLuckPercent(data)`, `GetCombatDamage(data)`, `GetMaxEquippedPets(data)`. Changing those
signatures would touch dozens of call sites.

So pass ownership is cached into the data table as `data.Passes = { x2DNA = true, ... }`. Every
existing function keeps its signature and gains one line.

**Three traps. Get any of these wrong and the game hands out free passes:**

- **`data.Passes` must be reset to `{}` on load, before the Roblox API answers.** If a stale
  `true` survives in a save and the later ownership check fails, that player keeps the pass
  forever without paying. Never trust the loaded value; always recompute.
- **`UserOwnsGamePassAsync` is a web call.** Wrap in `pcall`, retry with backoff, and **fail
  closed** (no pass) — never open. Refresh on join *and* on
  `MarketplaceService.PromptGamePassPurchaseFinished`, so a purchase applies without a rejoin.
- **`passId = 0` needs the same guard `RobuxShopService:87` already has** for products: refuse and
  notify, rather than calling `PromptGamePassPurchase` with a zero id.

API surface: `PassService.Init()`, `.Refresh(player)`, `.Has(player, key)`, `.Mult(data, key)`
(returns the pass's multiplier, or `1`).

| ID | | Task | Files | Verified how |
|---|---|---|---|---|
| 1.1 | `[x]` | Route `grantDNA` through `ScaleReward`. **Diamonds deliberately NOT scaled** — every diamond sink is a small fixed number (upgrades cost 5/8/15) that does not ride the stage curve, so scaling would cap every permanent upgrade in one purchase | `RobuxShopService:45-62` | measured: the 10,000 DNA pack is worth **7,692 clicks at stage 1, 6, 14 and 20 alike**. Before the fix: 7,692 → 41 → 0.009 → 0.00002 |
| 1.2 | `[x]` | `GameConfig.GamePasses` (9 rows) + `GetGamePass` / `OwnsPass` / `GetPassMult` / `GetPassAdd`. Effects are **fields**, so a hook reads `GetPassMult(data, "incomeMult")` and never names a pass | `GameConfig:1393+` | 9 passes, 2,041 R$, 0 duplicate keys, 0 live ids. Stacking: 2x DNA alone 2.00, VIP alone 1.50, both 3.00; luck 50 / 15 / 65 |
| 1.3 | `[x]` | `PassService` — Has / Refresh / Init, fail-closed, background re-check, purchase hook | new `ServerScriptService/PassService.lua` | `ownsPass` returns true / false / **nil**; nil and false both grant nothing. Boots clean in Play |
| 1.4 | `[x]` | `data.Passes` cleared on load, unconditionally, for **both** the fresh and the returning branch | `PlayerDataService` defaultData + `Load` | measured on the real save (OGLightninggXD, stage 5): `Passes` comes back a table with **0** entries |
| 1.5 | `[x]` | `Remotes.PromptGamePassPurchase` + handler with the `passId = 0` guard and an already-owned guard | `Remotes`, `PassService.Init` | remote exists in Play; all 9 passes refuse to prompt on id 0 |
| 1.6 | `[x]` | Wire `PassService.Init()` into `ServerMain` before `RobuxShopService.Init()`, plus `OnPassesChanged` → `EvolutionVisuals.RefreshBonuses` so 2x Speed lands without a respawn | `ServerMain` | `Server systems initialized.` with no errors; compile sweep 45 scripts / 0 failures |
| 1.7 | `[~]` | **👤 OWNER** Create the 7 existing developer products on the dashboard, paste real ids. **The ids exist** (2026-08-11, universe 10675543038) and are in `GameConfig`; managed pricing is off on every one. Stays `[~]` because this row's own verification is a **purchase**, and no real purchase has been made | `GameConfig.RobuxProducts` | ids: all resolve via `GetProductInfo`, names and prices match `GameConfig`. **Still owed: a real purchase in the published place grants and saves** |

---

## Phase 2 — The nine game passes

All nine hook into functions that already exist. Prices follow the bands seen across the market:
cheap entry pass → core multipliers → premium bundle.

| Pass | R$ | Hook point | Note |
|---|---|---|---|
| 🏃 2x Speed | 99 | `EvolutionVisuals.applyMastery:156` | the **one** place in the game that writes `WalkSpeed`; the client sprint reads whatever it finds |
| ⭐ 2x XP | 149 | `CreatureService:2756`, `BossService:1952` | both already multiply by `GetPotionMult(data,"xp")` — extract a shared `GameConfig.GetXPMult(data)` so the pass lands in **one** place, not two |
| 🥚 Auto Hatch | 149 | `PetService` `BuyEgg.OnServerEvent:293` + new client loop | hatches repeatedly while standing at a podium; the server re-validates the cost on every hatch |
| 🧬 2x DNA | 199 | `DNAService.GetIncomeMult:12-32` | covers click, kill, auto-collect and idle in one line |
| ⚔️ 2x Damage | 199 | `DNAService.GetCombatDamage:64-78` | |
| ⚡ Fast Auto Attack | 199 | `CombatClient` `AUTO_INTERVAL` 0.34 → 0.20 | **auto-attack itself stays free** (attribute `AutoAttack`, key T). Never paywall what is already free — sell the speed |
| 🍀 Lucky | 249 | `DNAService.GetLuckPercent:34-42` | **additive `+50` points, not `x2`.** Every luck source in the game is additive (upgrade +2/level, pet `luckAdd`, potions); a multiplier on a stat that starts at 0 does nothing for a first-time buyer |
| 🐾 +3 Pet Slots | 299 | `GameConfig.GetMaxEquippedPets:1175` | base is 3 + the diamond `PetSlot` upgrade |
| 👑 VIP | 499 | composite | 1.5x DNA + 1.5x damage (multiplies with the others), chat tag, `Highlight` aura, exclusive skin, daily diamond grant |

### MainUI constraints — read before touching that file

- `MainUI` is at Luau's **200-local register cap**. A `do ... end` block is **not** enough. Any new
  panel must be built inside `;(function() … end)()` with its handles hung on the single `hudRefs`
  table (`MainUI:1152`). This has broken the HUD twice, the second time after a fix that looked right.
- After **any** `MainUI` edit, in Edit mode:
  ```lua
  local fn, err = loadstring(game.StarterPlayer.StarterPlayerScripts.MainUI.Source)
  return fn and "OK" or err
  ```
- Put the pass shop as a **second tab inside the existing `RobuxPanel`** (`MainUI:2617`) rather
  than a new panel — no new registers, and no `RIGHT_COUNT` bump (it is at 7, `MainUI:756`).
- An owned pass renders an `OWNED` state, not a buy button.

**All nine passes are complete and verified.** What is left in this phase is the two UI jobs — both
touch `MainUI`, so read the register-cap rule below before starting either — plus the owner's
dashboard step and the stacked-balance check.

Two functions were deliberately made public so the features could be **tested rather than read**:
`PassService.GrantVipDaily` and `PetService.DriveAutoHatch`. With every `passId` still 0 there is no
way to make the real code paths see a pass as owned, and once 2.11 lands they can go back to being
local if anyone cares.

| ID | | Task | Verified how |
|---|---|---|---|
| 2.1 | `[x]` | 🏃 2x Speed — `EvolutionVisuals.applyMastery`. **The pass also lifts the cap** (`walkCap = 260` + new `GameConfig.GetPassMax`): against the normal 150 it delivered 1.18x at stage 20 and was a true 2x only through stage 7 of 20 | measured 2.00x at stages 1 / 7 / 14 / 20; a non-owner at stage 20 is still 127.2 |
| 2.2 | `[x]` | ⭐ 2x XP — extracted `GameConfig.GetXPMult(data)`, now the single XP multiplier, used by both `CreatureService` and `BossService` | `GetXPMult` x1.00 → x2.00; nothing else moves |
| 2.3 | `[x]` | 🥚 Auto Hatch — one server loop for the whole server (not one per player), going **through `HandleBuyEgg`** so the rate limit, zone-unlock check, 600-pet cap, cost, roll and Season Pass counter all still apply. Affordability and capacity are re-checked **silently** first, because `HandleBuyEgg` answers those with a Notify and twice a second that buries the notification stack. Range comes from each prompt's own `MaxActivationDistance`, and the **nearest** egg wins — three sit within a few studs on every podium | 60 of 60 egg prompts have a usable anchor. Live: 4 ticks → 4 pets, 500 DNA each; empty wallet → unchanged, no spam; no pass → unchanged |
| 2.4 | `[x]` | 🧬 2x DNA — `DNAService.GetIncomeMult`, added last so it multiplies the whole stack | income x1.00 → x2.00, damage unchanged at 62 |
| 2.5 | `[x]` | ⚔️ 2x Damage — `DNAService.GetCombatDamage`. Raises damage **dealt** only; the incoming-damage cap is untouched | damage 62 → 124, income unchanged at x1.00 |
| 2.6 | `[x]` | ⚡ Fast Auto Attack — `CombatClient` reads an `AutoSpeedMult` **player attribute** the server stamps, so the client never learns what a pass is. Floored at `SWING_TIME` | attribute reads 1 for a non-owner; x1.70 with the pass; free auto-attack untouched |
| 2.7 | `[x]` | 🍀 Lucky — `DNAService.GetLuckPercent`, **added in points** | luck 0 → 50; Lucky + VIP = 65 |
| 2.8 | `[x]` | 🐾 +3 Pet Slots — `GameConfig.GetMaxEquippedPets`, stacking **on top of** the 3-level diamond upgrade (3 + 3 + 3 = 9) | pets 3 → 6 |
| 2.9 | `[x]` | 👑 VIP — multipliers, golden skin (2.9a), **golden aura, [VIP] chat tag and 5 Diamonds a day**. The aura is **particles + a PointLight, never a `Highlight`**: CreatureService rents 14 of the ~31 Roblox renders, and one Highlight per VIP in a full server would strip the outlines off every creature in the world. Aura and tag are drawn client-side off an `IsVIP` player attribute, which replicates to everyone by itself — no remote, and other players see the badge for free | daily pays 5 once, pays nothing on a second call the same day, pays again after the stamp rolls, and pays a non-VIP nothing. Aura built with emitter + light sized off `BodyScale`, **0 extra Highlights on the character**, removed and rebuilt as `IsVIP` toggles. Chat pipeline confirmed `TextChatService` |
| 2.9a | `[x]` | The VIP skin — `GameConfig.VipCharacter` (`vip_gold`, "Golden Patron"). Registered in `CHARACTER_BY_KEY` only, **never** in `CHARACTERS_BY_STAGE`. `GetEffectiveRank` makes it score as `GetBestOwnedRank(data)`, so it is worth exactly what the wearer earned. `SyncVipCharacter` grants and **revokes** it, and is called after a rebirth too because `RebirthService` clears `data.Characters` wholesale. No `SkinMesh_vip_gold` exists and that is intended — `SkinMesh.Has()` falls back to `StageCostume` painted gold, i.e. a gold version of whatever stage you are | collection still counts 100 collectible (of 200 authored) with the skin owned; no leak into `CHARACTERS_BY_STAGE`; damage identical to the best owned skin at depths 1/3/10/20 (x1.15 / x1.45 / x2.50 / x4.00); losing the pass removes it and moves the body to a real skin |
| 2.9b | `[x]` | The VIP skin in the **Journal UI** — a 21st section. The stage loop now walks a `sections` list (20 stages + one VIP section), so the disc is built by **exactly the same code** as every other one: it locks, unlocks, previews, selects and wears with no special case, and a later change to cell styling reaches it for free. Two honest touches: its damage chip reads `⚔️ = best` rather than a percentage (it has no rung on the ladder), and it previews at the **player's own stage**, because it is a gold version of whatever you currently are | 21 rows built; header reads **`Discovered 20 / 100`** with the VIP skin owned — it does not inflate the count; disc unlocked, worn tick on, chip reads `= best`; control: an unowned stage-6 disc still reads locked |
| 2.10 | `[x]` | Robux panel: **Packs / Passes tabs** inside the existing panel rather than a new one — a pass and a product are the same decision, and `MainUI` has no top-level registers to spare. Built inside `;(function() … end)()`, escaping only as `hudRefs.refreshPassShop`. Passes render as wide rows (name, description, price) in a scroll, since 9 product-sized tiles are 710 px in a 500 px panel | HUD builds in Play; `TabRow` + `PassScroll` + `RobuxGrid` all present; 9 rows; VIP reads `R$ 499`. With `Passes = {VIP, DNA2x}` pushed, exactly those two flip to `OWNED` with `AutoButtonColor = false` and the other seven keep prices. **Not click-tested** — `VirtualInputManager` needs a capability this environment lacks, so the two tab handlers are wired but unclicked; `selectTab` itself is verified by its initial call |
| 2.11 | `[~]` | **👤 OWNER** Create all 9 passes on the dashboard, paste ids. **Done 2026-08-11**: all 9 exist on universe 10675543038, ids are in `GameConfig`, and **"Item for sale" is enabled on every one** — a separate step from creating the pass and the easiest thing here to miss. Stays `[~]` for the same reason as 1.7 | ids: all 9 resolve, `IsForSale = true` on each, prices match. Effects proven separately by `PassService.Refresh`'s `IsStudio()` branch (VIP, FastAuto 1.7x, 2x Speed → WalkSpeed 237). **Still owed: a real purchase applies without a rejoin** |
| 2.12 | `[x]` | Balance check on the full stack. **Verdict: everything is bounded, nothing needs changing.** Income: passes contribute a flat **×3.00** at every stage (worst honest case ×15 free → ×45 paid), so an evolve at stage 20 costs 204,621 clicks free against 68,207 paid — a real advantage, not a collapse. Damage ×3.00, but `BOSS_MIN_HITS` caps a single blow at a share of the target's health, so hit counts are untouched and passes only remove wasted swings. Luck is the one additive stat and reaches 385% worst case — crit is saved by its hard 75% cap, and the roll tables turn out to be heavily damped: the rarest egg outcome moves only 3.8% → 4.6% (and just 5.0% at luck 1000). Mystery potions shift most, large 6.9% → 20.3% | replayed numerically; egg odds sampled, potion roll sampled over 20,000 rolls |

---

## Phase 3 — Developer products and shop presentation

The shop went from 7 products to **17**. Two of them are counted charges rather than payouts
(`BossRevive`, `TierUp`), and that shape is deliberate and shared: `ProcessReceipt` is retried on
Roblox's own schedule, can land on a different server, and does a DataStore write before it
acknowledges — so anything that had to be consumed *at the moment of purchase* would have a tail of
buyers who paid for nothing. A charge sits in the save until there is something to spend it on.

**3.5 was not built as specified, because the specification was wrong about this game** — see the
row below. Everything else in the phase landed as written.

| ID | | Task | Verified how |
|---|---|---|---|
| 3.1 | `[x]` | DNA packs 2 → 5 tiers (49/99/199/499/999 R$), all through `ScaleReward`. Named by size (`Small`…`Mega`) rather than by a number, because a scaled payout makes "1,000 DNA" false at every stage but the first | value per Robux **strictly monotonic**: 20.41 → 25.25 → 30.15 → 36.07 → 40.04 per R$. A pack is worth the same clicks at every stage: `DNA_1` = 769 and `DNA_5` = 30,769 at stages 1, 10 and 20 alike |
| 3.2 | `[x]` | Diamond packs 2 → 5 tiers (10/22/50/140/300). Deliberately **not** scaled and named with their real numbers — the reasoning is the diamond note in `RobuxShopService` | monotonic: 0.2041 → 0.2222 → 0.2513 → 0.2806 → 0.3003 per R$ |
| 3.3 | `[x]` | 🎡 **Lucky Spin** (99 R$) — 8 segments, weights summing to 100, luck-shifted with the `RollMysteryPotion` shape but **normalised by segment count** (`(i-1)/(n-1)`), so adding a ninth segment later cannot silently change how strong luck is. Expected DNA is set **below** the 99 R$ flat pack (2,260 vs 2,500): the pack is the safe buy, the wheel is the gamble. `RobuxShopService.GrantSpin` is public so 5.6's free daily spin reuses it rather than copying it | 10,000 rolls at luck 0 and at luck 385 (the worst honest case from 2.12): **worst deviation 0.44 points**. Live in Play: 12 real grants, each segment paying exactly its own payload; DNA scaled (1,538 clicks at stage 1 and 14), diamonds and shards not |
| 3.4 | `[x]` | ⚔️ **Boss Revive** (49 R$) — a **counted charge**, auto-spent the instant the receipt lands and otherwise kept for the next attempt. `BossService` now snapshots the **lowest** health each player has driven a boss to, and a revive restores it **only downward, never upward**, so a revive can never undo another player's damage on a shared boss. Adds the game's first `Humanoid.Died` hook (offer shown only when a snapshot is actually behind it) and a 30 s regen freeze so the restore survives the walk back. Client card lives in `CombatClient`, whose boss-bar GUI already has `ResetOnSpawn = false` | live in Play, all five cases: boss healed 760→800, revive restored **800→760** and spent the charge; no charge → refused; nothing healed → refused **and the charge kept**; boss at 300 below a 760 snapshot → refused, health **not raised**; and the freeze held regen off at 17 s idle (past the 14 s delay) then released it by 37 s |
| 3.5 | `[x]` | 🌈 **Rainbow Catalyst** (99 R$ / 249 R$ x3) — **RESHAPED, and the roadmap's own premise was the reason.** "One tier above the existing Golden fusion" describes a game this is not: `PetTiers` has run Normal/Golden/Rainbow/Celestial for a long time, `GetNextTier` has no gate, and `HandleFuse` refuses only "already Celestial" and "fewer than 4 copies". **A player with four Goldens gets a Rainbow today, free** — so the product as specified would have charged 199 R$ for shipped content, which is the one thing this project refuses to do (see the auto-attack note in `GamePasses`). The real wall is needing **4 identical copies of the same species and tier** — 16 Normals for a Rainbow, 64 for a Celestial. So the token sells the grind: raise one owned pet one tier, no copies. **Capped below Celestial** (`GameConfig.CatalystMaxTier`), because equipped bonuses multiply across up to 9 slots and an uncapped bought tier is a compounding income multiplier priced like a consumable | live in Play: Normal→Golden and Golden→Rainbow spend one token each; **Rainbow→Celestial refused and no token spent**; already-max refused; unowned pet id spends nothing; 0 tokens changes nothing. The pet keeps its `id`, so an equipped pet **stays equipped** — unlike a fuse. Free fusing still reaches Celestial |
| 3.6 | `[x]` | Robux panel: the grid is now a **`ScrollingFrame`** (17 products is ~1,400 px of cards in ~350 px of panel — as a plain Frame everything past row three did not exist), 40 px icons, the **price on the button** instead of "Buy with R$", a per-player "what this pays you at your stage" line on the DNA tiles, and ribbons. **No tile claims to be popular:** `MOST POPULAR` is a claim about other players that nothing here measures, so the ribbons are `BEST VALUE` plus a **derived** `+N% BONUS` from `GetTierBonusPct` — arithmetic on the product table, not a sentence someone typed. The "limited offer timer" is a **Today's Pick** rotating off the calendar day with a real countdown to the rotation; nothing is discounted, so nothing pretends to expire | live client probe: `RobuxGrid` is a ScrollingFrame with `AutomaticCanvasSize`, **17 cards, 17 priced buttons, 9 ribbons** (`+24/48/77% BONUS`, `BEST VALUE`, `+9/23/37% BONUS`, `BEST VALUE`, `BEST VALUE`), 1 pick star, title counting down. `DNA_1` read `+65.97K DNA` for a stage-5 save, i.e. the scaling reaches the tile. **Screen capture caught a real bug the probe could not**: at a 24 px name box, `themeLabel`'s 14 px floor (`UITextSizeConstraint.MinTextSize`) meant a wrapped "Small DNA Pack" was clipped rather than shrunk, on every DNA tile. Card 158 → 180 px, name given two lines, icon box 40 → 60 px (an emoji's glyph fills about half its line box, so a 40 px box drew an icon no bigger than the name under it). Re-verified with the engine's own `TextFits` on every label of all 17 cards: **none clipped** |
| 3.7 | `[x]` | **`+` on the DNA and Diamond capsules**, opening the shop on the **Packs** tab (`hudRefs.selectRobuxTab`). Built after `robuxPanel` exists — a closure written beside the pills 2,500 lines earlier cannot see a local declared later — and inside `;(function() … end)()`. **Not** on the Shard pill: shards are a rebirth reward and are sold nowhere | live: `PlusButton` present on `DNAPill` and `DiamondPill`, absent on `ShardPill`. MainUI still **178 top-level locals** — the whole phase added none. Not click-tested, same environment limit noted in 2.10 |
| 3.8 | `[~]` | **👤 OWNER** Create the **10 new** developer products on the dashboard and paste the ids (`DNA_1`…`DNA_5`, `Diamonds_1`…`Diamonds_5` replace the old four; plus `LuckySpin`, `BossRevive`, `TierUp_1`, `TierUp_3`) — 17 rows in total with the two potion packs and the Season Pass. **Done 2026-08-11**: all 17 exist on universe 10675543038. Stays `[~]` for the same reason as 1.7 | all 17 resolve via `GetProductInfo`, prices match `GameConfig`, managed pricing off. **Still owed: a real purchase grants and saves** — that is the only thing that exercises `ProcessReceipt` |

---

## Phase 4 — Audio

A tree scan for `Sound` returns **exactly one instance**, inside an unused VFX pack. There is no
click, hit, death, hatch, evolve, purchase or ambient audio anywhere in the game. This is the
largest "doesn't feel finished" factor — above any art change.

**Every asset id in `SoundLibrary` was loaded in this place before it was written down** — a `Sound`
per candidate, `ContentProvider:PreloadAsync`, and the pair (`AssetFetchStatus == Success`,
`TimeLength > 0`) recorded. 38 of 38 passed. This matters more than it looks: an audio asset that is
moderated, private or simply wrong is not an error, it is **silence**, and silence is
indistinguishable from "the code never fired".

Most ids come from **ProSoundEffects**, the library Roblox licensed and gave away free. Picked over
higher-ranking community uploads on purpose: their descriptions state what the recording *is*
("Duration: 0.9 seconds, Category: Weapons - Misc, Axe Impact, Giant, Thuddy Hits") where a community
upload is called `fish4`. Nobody working on this can hear the file, so a described asset is the only
kind that can be chosen on evidence rather than on its name.

| ID | | Task | Verified how |
|---|---|---|---|
| 4.1 | `[x]` | `SoundLibrary` (`ReplicatedStorage/Modules`) — id table, `Play` / `PlayLocal` / `PlayAt` / `PlayAtPosition`, three `SoundGroup`s (SFX / UI / Ambience) created **by the server** in `EnsureGroups()` so they replicate before any client asks. 2D sounds are pooled one instance per name and restarted; only positional sounds allocate. `minGap` drops a repeat inside N seconds, `vary` randomises pitch, `variants` picks one of several assets. **Three silent-failure traps are documented in the file header** — the sharpest is that `Sound.TimeLength` is 0 until the asset loads, so the obvious `Debris:AddItem(s, s.TimeLength)` destroys a sound before its first noise and works perfectly every time after | 26 entries, 0 without an id or a length, 0 bad group names; unknown name **errors** rather than returning nil; all 20 `GameConfig.Zones` map to a bed and every bed name resolves; `EnsureGroups` twice leaves **3** groups, not 6; 60 plays of `swing` drew **4** distinct assets |
| 4.2 | `[x]` | Combat — `swing` on `playSwing` (positional, on the swinger's own root, so other players' swings arrive from where they are), `hit` / `death` on the `CombatFx` payload, `hurt` on the local player's `HealthChanged`. `swing` is the one entry carrying **both** repeat mitigations: at one swing every 0.20s with the Fast Auto Attack pass, a single fixed sample reads as a stuck loop | live in Play: firing `CombatFx` produced positional `death` and `hit` on Terrain with the right rolloff (12..130 / 12..120) and **pitch actually varying** (1.33, 1.09) |
| 4.3 | `[x]` | Economy — routed through **one** new `SoundLibrary.PlayNotify(payload)` and a row-per-kind table, so MainUI's twenty-branch Notify handler gained a single line instead of twenty, and a new kind is a row rather than an edit. `creature` and `playerHurt` are deliberately **absent**: both are already drawn and sounded in the world, so a row here would double every kill | live: 9 notification kinds fired from the server each produced the right pooled sound in the right group. `hatch` for a **Legendary** came out at speed **0.76** and volume **0.62** — the rarity-scaled sting working, rarer being lower and bigger |
| 4.4 | `[x]` | UI — `click` inside `UITheme`'s `Button` and `IconTile` press handlers, so every interactive surface in the game gets it in **one** edit. Fires on *down*, with the sink, not on release. **Guarded on `RunService:IsClient()`, and that guard is load-bearing**: `UITheme` is not client-only (CreatureService and BossService both require it on the server) and a server-created `Sound` replicates — unguarded, it would fire a button press into every player's ears from a server that pressed nothing | `PlayLocal("click")` verified building a pooled `UI`-group sound; `UITheme.Button` and `IconTile` both build clean in Play with SoundLibrary loaded. **Not click-tested** — `VirtualInputManager` needs a capability this environment lacks, the same limit recorded at 2.10 and 3.7 |
| 4.5 | `[x]` | Ambience — **nine beds mapped across twenty zones + the Colosseum**, grouped by what a place *sounds* like rather than what it looks like (Moon, Mars, Galaxy and Nebula are four different pictures and one hollow spacecraft hum). Driven from `data.CurrentZone` on every `DataUpdate`, **not** from the travel remote: `ZoneTransition` only fires when a player walks a gate, so that would be silent on join, wrong after a rebirth and stale after a respawn | live: the bed for the save's real zone came up on its own and held **0.180**. Crossfade measured mid-flight — Forest **0.091** falling while Volcano **0.069** rose, Forest destroyed, Volcano settled at 0.160. Re-asking the same zone builds no second bed; an unmapped zone changes nothing and warns once; `StopAmbience` clears it |
| 4.6 | `[x]` | Volume — `data.AudioVolumes` (Master + one fader per group), `Remotes.SetAudioVolumes`, `SoundLibrary.Init` applying them on the client's first payload, and an **Audio panel** with four sliders and a mute button on a new right-column tile. **`data.AudioVolumes` is the one field in the save the client may write directly** (a fader is worth nothing to cheat) and therefore the one validated hardest. The panel applies **locally on every frame of a drag** but only **sends on release** — a remote per mouse-move frame is sixty round trips a second for a preference. Mute drives Master alone and restores the pre-mute value rather than snapping to 100% | **verified across a real rejoin**: set to Master 0.4 / Ambience 0.2, stopped, restarted — came back 0.4 / 0.2 from the DataStore and `Init` applied them with no further input (SFX/UI **0.40**, Ambience **0.40 × 0.20 = 0.08**), so master × group composes. Validation: 99 clamped to 1, **NaN rejected** (left at its old value, and `math.clamp` passes NaN straight through — hence the explicit `value == value`), unknown keys refused. Panel live: a server round-trip repainted all four rows in step (readout **and** fill width: 40%/0.40, 75%/0.75, 20%/0.20), groups landed at 0.4×0.75 = **0.30** and 0.4×0.2 = **0.08**, and muting Master flipped the button to **UNMUTE** and zeroed both groups. 11 labels, **none clipped** at the authored size. **The drag itself and the tile click are not click-tested** — same environment limit as 2.10, 3.7 and 4.4 |

---

## Phase 5 — Retention and marketing systems

| ID | | Task | Why / verified how |
|---|---|---|---|
| 5.1 | `[x]` | 🎟️ **Codes** — `GameConfig.Codes` (6 rows), `NormaliseCode` / `GetCode` / `IsCodeExpired`, `data.RedeemedCodes` as a set, new `CodesService` and `Remotes.RedeemCode`. **Unlike every other id table in this project a code is MEANT to be invented** — it only becomes real when the owner publishes it, so edit the list freely. Rewards reuse `DailyRewards`' field names, so the grant is the same four lines `RewardService` already had, and `dna` goes through `ScaleReward`. **`RedeemedCodes` is marked before the grant and nothing between them yields** — that gap is the whole double-redeem exploit. **The redeem bar lives in the Daily panel**, not on a tile of its own: the right-hand cluster is a full 2x4 grid after the Audio tile took order 8, and the Daily panel is where free things already are. Panel grew 480 → 536 to pay for it rather than moving anything that was already there | live end-to-end through the real remote: `"  lAuNcH  "` normalised and paid **+98,962 🧬 / +10 💎 / +2 🧪** (1,500 authored, scaled to the save's stage); the same code again refused with no change; an unknown code refused; **two fired on the same frame paid the first and rate-limited the second**; `12345` and a table were ignored without reaching the limiter. Config: 6 rows, 0 duplicates, over-length and 4,000-char strings rejected. Bar verified live at its authored size: grid ends y=412, bar 426..470, banner 478..522 in a 536 panel — **no collision, no clipped labels**; the counter read **"4 new"** against the real save, fell to **"3 new"** on a redeem and went **empty rather than "0 new"** once all six were spent. **The button press and the Enter key are not click-tested** — same limit as 2.10, 3.7, 4.4 and 4.6 |
| 5.2 | `[x]` | 💤 **Offline earnings** — `data.LastSeen` stamped on **every** save (a crashed server never runs its leave-save), elapsed measured in `Load` **before anything overwrites it** and held in `PlayerDataService.OfflineSeconds` **in memory, never in the save** — a pending payout that survives a crash is a payout collected twice. New `OfflineService` pays `GetAutoCollectAmount × seconds × 0.5`, capped at 8h, with a 120s floor so a rejoin does not pop a card. **A player with no AutoCollect earns nothing, and that is the design**: this feature *is* that upgrade continuing while you are away | arithmetic exact on six trials (1h, 8h, at the rate cap, over it, at zero, and at stage 20) — every payout matched its independently computed expectation, and **the second call always paid 0**, so the consume-once guard holds. Ordering preserved by construction: idling 102.9 DNA/s, offline 51.5 DNA/s, 8h max = **17,280 clicks**. Card verified drawn twice, capped and uncapped, at **2 lines**. Its second line was shortened 41 → 29 chars first: `celebratePurchase`'s label is 300x56 wrapped and `themeLabel` floors at 14px, so a long line wraps to a third row and pins at the floor instead of shrinking. **`TextFits` could not be read** — the Play viewport reports 1x1, which shrinks every panel and makes that property meaningless |
| 5.3 | `[x]` | 🏆 **Global leaderboards** — new `LeaderboardService`: three `OrderedDataStore`s (Rebirths / DNA / Kills), a 60s publish loop, a staggered 60s read loop, and **three physical signs it builds itself in Forest**. New `data.Kills`, incremented beside the Season counter in `CreatureService` and both `BossService` kill sites, and **deliberately not reset by a rebirth** — a lifetime board a rebirth zeroed would rank players by how recently they reset. **It does not touch `ZoneBuilder`**: that file is 480 KB, its `BUILD_VERSION` guard regenerates all twenty zones when it moves, and `RebirthShrine` already set the precedent for a service that builds its own furniture. **Placement was measured, not chosen** — an occupancy scan found the street at x=0 carrying 75–100 parts per cell and its verge at x=±65 carrying 25–40, while **x = −130 is empty from z=140 to z=300**, beside the walk from the spawn at (0, 366). Four `OrderedDataStore` traps are written up in the file header; the sharpest is that it stores **integers only**, so raw float DNA is rejected silently and the board just stays empty | live end-to-end: 3 signs at (−130, 28, 280/210/140), face `Right`, `ModelStreamingMode.Persistent`, **no overlap** with Forest geometry. Boards filled from the real store — **🥇 Rebirths 7**, **🥇 DNA 2.9T** (shortened; the other two use commas). Kills started empty, which is correct (the counter starts at 0 for everyone and 0 is never published); **three creatures were then killed live**, `data.Kills` went 0 → 3, and the board picked it up **56s later** through the real publish and refresh loops. Empty and warming-up states both render rather than showing a blank sign |
| 5.4 | `[~]` | 📢 **Cross-server announcements** — `MessagingService:PublishAsync` and `SubscribeAsync` on `GlobalAnnouncements_v1` topic inside `AnnounceService.lua`. Publishes Legendary hatches, Mythic/Godly mutations, Zone 15+ boss clears, and Rebirths to other game servers. Receiving servers display positionless toast banner in `RarityBeam.client.lua` with authoring color and text. | **EVIDENCE CORRECTED 2026-08-15 (15.26).** The old cell read "verified with luastruct & luanames", which is static lint over source text and says nothing about this row. What is actually established: the *receiving* half is real and was measured in the twenty-seventh session — `RarityBeam.client` renders a positionless payload as a HUD toast, and 12.14's four publishers exercise that path locally every day. What is NOT established, and cannot be from Studio, is a `PublishAsync` on one server arriving at a `SubscribeAsync` on another: **Studio has one server**. This row closes on two published clients on separate servers and nothing less |
| 5.5 | `[~]` | 👥 **Group / Like / Favourite rewards** — permanent +10% DNA boost (`GameConfig.GroupIncomeMult = 1.10`) for group members across all clicks, kills and auto-collect in `DNAService.GetIncomeMult`. Daily in-world Group Chest in Forest spawn (`ClaimGroupChest`, `Remotes.OpenGroupRewards`) paying scaled DNA + 💎 25 + Medium DNA potion. One-time Like reward (💎 15 + Medium Luck potion) and Favorite reward (💎 15 + 🌟 2 Shards). High-polish `GroupRewardsPanel` built with `UITheme.PanelHeader` & `UITheme.Card`. | **EVIDENCE CORRECTED 2026-08-15 (15.26): the cited `test_group_rewards.py` has never existed** in this repo or in its history, so the old cell ("luastruct & luanames, simulation scripts") pointed at a file and a lint, i.e. at nothing. Read instead, and stated as a read: the Like and Favourite handlers **do** follow stamp-before-grant (`data.ClaimedLikeReward = true` is written before the first `+=`, with no yield between the check and the stamp), both flags are `false` in `defaultData`, **no rebirth or migration clears either**, so each is one-shot per save forever; and `CheckGroup` / `Load` both fail **closed** (`(ok and inGroup) or false`), which is the pass rule from 1b applied to a group. **And the group branch is unverifiable in Studio by construction** — `RunService:IsStudio()` short-circuits both checks to `true`, so a Studio session proves the chest opens for a member and nothing else. Owner-blocked on `GameConfig.RobloxGroupId`, which is still **0**, i.e. the +10% is dead in production until it is set |
| 5.6 | `[~]` | 🎡 **Free daily spin** — done. `data.LastFreeSpin`, `RewardService.GetFreeSpinStatus` / `HandleFreeSpin`, `Remotes.ClaimFreeSpin`, and a gold button in the Daily panel that becomes a countdown. **It calls `RobuxShopService.GrantSpin`, which Phase 3 made public for exactly this** — the wheel is luck-shifted, its weights are normalised by segment count and its expected value sits below the 99 R$ flat pack, and a second copy here would be a second thing to keep balanced. Same UTC day boundary as the login reward, so both roll over together. **The stamp is written before the grant** with no yield between, the rule the code redemption follows. Rewarded Ads are the other half and are 👤 OWNER | live: button read **FREE SPIN!**, a claim rolled a real segment (`🧬 DNA Surge`), stamped `LastFreeSpin` and flipped the button to **`🎡 5h 11m`**; a second claim the same day was refused and did **not** re-roll. Geometry at authored size: streak card x22..262, button x458..678, day grid from y=100 — no collision, nothing clipped. The countdown ticks only while the panel is open |
| 5.7 | `[x]` | 📖 **Journal rarity percentages** — new `StatsService`. **Ownership is reconciled, not counted at the grant**: there are several places a character is handed over (evolve step, roll, the Load backfill, the VIP sync) and the next one added would silently not count — and `RebirthService` clears `data.Characters` wholesale, so a naive diff would re-count the same player on every rebirth. `data.CountedCharacters` is a permanent record of what a save has already been counted for; a sweep reports the difference. Deltas batch into **one `UpdateAsync`** (not `SetAsync`, which would mean the last server to write wins), and the batch is **put back if the write fails**. The aggregate reaches clients as JSON in a `StringValue` — no remote, and a late joiner gets it for free. **A 25-player minimum sample is enforced**: with four players every owned character reads "100% own it", which is true and worthless | live: `GlobalStats` published after 54s through the real loops. Sweep on a synthetic save of 3 characters returned **3, then 0** (the rebirth-safety property), and **1** after a 4th was granted. The **shipped** `ownershipText` was extracted from `MainUI.Source` and run — not a second copy — across every bracket: 60% → `60% own it`, 4% → `4.0%`, 0.03% → `<0.1%`, suppressed sample → `""`, malformed JSON → `""`, and more-owners-than-players clamps to 100%. **That run found a real bug**: zero owners printed `<0.1% own it`, claiming somebody owned it; it now says nothing. **The line itself is not click-tested** — the Journal renders it only for a selected disc |

---

## Phase 6 — Juice and onboarding

| ID | | Task | Verified how |
|---|---|---|---|
| 6.1 | `[x]` | **Hatch sequence** — new `HatchReveal.client.lua`: the egg shakes with a climbing amplitude, cracks (white flash + drop), bursts in the **rolled rarity's colour**, and the actual pet rig rises out of it spinning, then a card names it. Its own LocalScript like `EvolveReveal`, so the whole hatch presentation lives in one file — MainUI's `pet` branch is now deliberately silent and `SoundLibrary.PlayNotify` no longer handles `pet`, because only this file knows when the reveal moment is (the notification lands the instant the server pays, a second before the egg has moved). The server now sends the pet **key** so the rig is the real species, not a lookup by display name. **The egg is a replicated object being moved locally**, so the whole animation is `PivotTo` against one saved pivot with a restore on every path — a client-side CFrame the server never corrects is permanently wrong on that one screen. `busy` keeps one sequence per egg, because Auto Hatch buys twice a second and an overlap would save an already-shaken pivot as "home" | live: shake reached **16.4°**, crack dropped **0.55 studs**, the **26-part** rig appeared, card and particle burst both drew, the hatch sting played at **speed 0.76** (Legendary). Afterwards the egg was back to **0.0000 studs / 0.0000°** off, shell colour restored, and **0** objects left in the local fx folder |
| 6.2 | `[x]` | **Rarity beam** into the sky on Legendary — new `AnnounceService` (server) + `RarityBeam.client`. Fired at **every** client, not drawn locally by the hatcher: a celebration only the celebrant can see is a card, not an event. **The announcement is split along the axis each half is good at** — a 420-stud column carries across the platform, and the WORDS are a HUD toast, because a `BillboardGui` shrinks with distance whether its size is authored in studs or in pixels (measured: a 320x96 card renders ~100 px wide at 177 studs, a smudge at the 500 studs this feature exists for). That toast is also the "one client toast" 5.4 asks for, and a cross-server message — which has no position and therefore no beam — lands in it unchanged. Policy lives in the service, not at the call site: `GameConfig.BeaconRarities` is one row (Epic is 1 hatch in 38, and a beam that common announces nothing) and a **6-second per-player cooldown** stops Auto Hatch holding a permanent column over one podium. No `Highlight` anywhere — CreatureService rents 14 of the ~31 outline renders and one per beam would strip creature outlines across the world | live end-to-end through the real chain: **15 real `ForestPremiumEgg` buys** (no stub on the path — real remote, real cost, real cooldown, real roll; the mix came out Uncommon 2 / Rare 7 / Epic 5 / **Legendary 1**, against the egg's advertised 3.76%) and the Legendary fired the beam. Sampled from the world every 0.45 s: 6 parts, **height 420**, colour `(1, 0.745, 0.235)` = Legendary's own RGB(255,190,60) exactly, fade beginning at t≈4.6 s, and **0 parts left** afterwards. Policy: Common and Epic sent **nothing**; a second Legendary in the same second was swallowed by the cooldown; `nil` player and `nil` def both refused without erroring. Screen-captured at 160 and 200 studs — a bold gold column with the ground rings rippling out — and the toast stack verified drawing **above an open HUD panel**, capped at **3 cards**, cleaning itself to 0 |
| 6.3 | `[x]` | **First-join sequence** — new `FirstJoin.client.lua`, one save field and one hook. A camera pan framed off the **character's own facing** (a pan written against +Z breaks the day the spawn turns), a banner naming the next thing to do, an arrow at the EVOLVE button, and the first evolve — which `EvolveReveal` already celebrates, so this adds **one line about what to do next** rather than a second card. **The gate is `data.TutorialDone`, a real field, flipped by the SERVER on the first evolve** — not "is this player at stage 1" (a rebirth resets StageIndex, so that replays the whole tutorial for a veteran every reset) and not a client saying it finished. The **migration is the part that needed care**: the generic backfill in `Load` copies the default `false` onto every save ever written, so an explicit repair marks any save with progress (stage > 1 or any rebirth) as done — otherwise the update hands a tutorial to players with a thousand hours. The banner names the gate that is **actually short**, XP or DNA, because being told to farm DNA while the XP bar is the empty one teaches players to stop reading hints. Camera restore runs on **every** path, including the skip: any input at all skips the pan | server half verified by **extracting the shipped source and running it** (5.7's technique, since no fresh save exists here): the migration passed all five cases — fresh stays `false`, stage 5 → `true`, **rebirthed-back-to-stage-1 → `true`**, already-true unchanged, a field-less old save stays `false` — and the flip pushed **exactly once** across two evolves. Client half live: pan went `Scriptable` → `Custom` in **3.41 s** (authored 3.4) and restored; XP short drew `⚔️ Click a creature to attack it`, XP paid/DNA short drew `🧬 Beat creatures for DNA to evolve`, both gates paid drew `⭐ You are ready! Press EVOLVE` with the arrow; completion turned the banner green and hid it after **3.9 s** (authored 4.0); the real `TutorialDone = true` save leaves everything hidden. **Two bugs only the capture and the arithmetic found**: the arrow sat exactly one 58 px GUI inset high (an `AbsolutePosition` is reported below the topbar while a Position offset in an inset-ignoring ScreenGui is measured from the screen top — matching MainUI's `IgnoreGuiInset` is the wrong fix), and once placed it **covered the "120 / 120 DNA" bar** that explains why the player is being told to press, so it moved beside the button |
| 6.4 | `[x]` | **Boost strip with timers** — the potion strip gained a permanent half. **The task asked for "pass icons and countdowns" and there is no countdown to give them: all nine passes are permanent.** A clock on a number that never falls is worse than none — it invites the player to wonder when the thing they bought forever expires. So the strip is split the way the boosts are: a potion is a **card** with a bar and a clock because it is running out, a pass is a **chip** because it is not. Nine chips in a `UIGridLayout` (a row cannot hold nine 34 px chips across 244 px; a grid wraps itself, and a tenth pass costs nothing), built **once** and shown or hidden like the three potion rows — ownership changes a handful of times a session, and rebuilding nine frames four times a second to say the same thing would be the HUD's most expensive idle loop. Reads `data.Passes`, which `PassService` recomputes on every load and never trusts from the save, so a chip is a live ownership answer. **MainUI gained zero top-level locals** (181 before and after) — it all went inside the existing `;(function() … end)()` | live, driven by pushed payloads (every `passId` is still 0, so no pass can be genuinely owned — same wall 2.10 hit): the real save with **no** passes builds 9 chips and shows **none**; `{VIP, DNA2x, Lucky}` lights **exactly those three**, card 42 px, one row; all nine gives **two rows** and a card of **81 px** = `8 + 2×34 + 5` exactly, sitting y=430..511 against the potion row's 517 — **6 px clear, no collision**; with two potions running both halves draw together. Stopping the injection returned it to hidden on its own. **18 labels, 0 clipped** by the engine's own `TextFits` (the viewport reported a real 1546×793 this session, so that property was meaningful). **The capture earned its place again**: the first build made the chips `Gold` on a card `styleCard` had painted gold, and they came out as pale marks that had to be hunted for — they are now dark discs on gold, the potion row inverted, re-shot at 2.2× with all nine emoji legible |
| 6.5 | `[ ]` | **👤 OWNER** Game icon and thumbnail — chunky character, big number, high contrast. Decides ~70% of clicks and is not code | uploaded |

---

## Phase 7 — Live ops

The three rows turned out to be **one idea used three times**: a thing that is true right now and
will not be later, derived from the clock and never stored. 7.2 is a single row in
`GameConfig.Events`, and 7.3 is `Season.id` becoming a function of the date — `SeasonPassService`'s
reset logic did not change by a line.

**Nothing about an event is ever written to a save.** Pass ownership is cached into `data.Passes`
because it comes from a web call that can fail; an event is arithmetic on a timestamp, so caching it
would break at both ends of the window — a player online when it shuts keeps the boost, and one who
logged off inside it carries a stale multiplier into next week. The single exception is the earned
skin, and that is a receipt rather than a state.

| ID | | Task | Verified how |
|---|---|---|---|
| 7.1 | `[x]` | **Event framework** — `GameConfig.Events` (two window shapes: `recurring` weekday/hour/duration, `fixed` from/to), `GetEventWindow` / `GetActiveEvents` / `GetNextEvent` / `GetEventMult` / `GetEventAdd`, new `EventService`, and a countdown board in Forest. **Effects reuse the game-pass field names** (`incomeMult`, `xpMult`, `damageMult`, `luckAdd`) so each hook gained one line beside its pass line and learned nothing about what an event is — `damageMult` is wired although no event sets it, so a future one is a row and not an edit. `GetEventMult` takes **no `data`**, which is the difference between an event and a pass in one line. **Transitions are polled every 5s, never scheduled**: a `task.delay` to the end of a window is lost on restart, fires once, drifts across 48 hours, and is never set at all on a server that booted mid-window. **`wasLive` is seeded at Init**, or every server restart would announce a weekend that has been running for a day. The exclusive skin (`event_prism`, "Prism Herald") follows 2.9a exactly — `CHARACTER_BY_KEY` only, never `CHARACTERS_BY_STAGE` — with one difference: it is **never revoked**, so it needs `data.EventCharacters`, a permanent record a rebirth cannot touch (`RebirthService` clears `data.Characters` wholesale and there is nothing live to re-grant an ended event from). `vip` split into `vip` + **`offLadder`**, the field the rank arithmetic now tests | window math swept **504 hours, 0 wrong**, both edges exact (half-open), and the "the hour has not come round today" branch correct in both directions. Live: board built at (150, 23, 215) v4, `LiveEvents` published, income **×2.0000 at stages 1/7/14/20**, XP ×2.0000, damage and luck untouched. Skin: granted once inside the window and **0 on the second call**, an unknown reward key writes nothing, survives a wiped `data.Characters` **and** survives it again with 0 events live, rank **0** / effective **27 = best owned 27** / damage **×1.81 identical to the real skin**, collection still **100** collectible. Transitions walked across two weeks: opens, the overlap, the two closing separately, the weekly one returning — and no repeat while both stayed on. HUD card live: 🔥 Weekend Rush / 5h 39m / "x2 DNA  x2 XP", nothing clipped, **MainUI still 181 top-level locals (0 added)** |
| 7.2 | `[x]` | **Weekend 2x** — `{ recurring = { wday = Sat, hour = 0, hours = 48 } }`, `incomeMult 2`, `xpMult 2`. **Deliberately not double damage:** damage is the pacing of the game, and 2.12 already measured that a damage multiplier mostly removes wasted swings because `BOSS_MIN_HITS` caps a blow at a share of the target's health. An event should make an hour of play worth more, not make the fight disappear. **Offline earnings are excluded** — `DNAService.GetIncomeMult(data, excludeEvents)`, one caller, `OfflineService`: that rate is multiplied by up to eight hours of *absence*, so a weekend running at the moment of the rejoin would pay double for hours slept through midweek | the window resolved Sat 00:00 → Mon 00:00 UTC and was **live during the session**, so every figure above is the real thing rather than a simulation. Offline: ratio **exactly 2.0000** at AutoCollect 5/20/50, and the 8h payout came back to 32.4B instead of 64.9B at level 20. Control on a Wednesday: event multiplier **×1.00**, so `excludeEvents` subtracts nothing that was never added |
| 7.3 | `[x]` | **Season rotation** — `GameConfig.SeasonEpoch` + `SeasonLengthDays` + a cycling `SeasonThemes` list, and `GetCurrentSeason(now)` generating `{ index, id, name, emoji, startTs, endTs }`. `Season.id` and `.name` were hand-edited constants; a season that only turns over when somebody remembers is a permanent pass with an optimistic name. **`SeasonPassService` did not change its reset logic at all** — it was already comparing the save's id against "the current one", and only the answer was static. **The epoch is chosen so that today is still `S1`**, byte for byte what every existing save holds, so the update rotates nothing and no player loses the progress they had. Themes cycle while numbers climb, so the table can never run out or leave a season nameless. MainUI's panel title is re-read on every refresh rather than frozen at build | today reads **`S1` / "Season 1: First Light"**, 2026-08-01 → 08-31. Fourteen months walked: ids strictly increasing, **0 gaps**, themes cycling back at S7. Boundary exact — `end-1s = S1`, `end = S2` — and a clock a year before the epoch **clamps to S1** rather than inventing an id no save has seen. Static shape intact (maxLevel 30, xpPerLevel 1500, 30 reward rows, level-30 diamonds still 5); `Season.id` is gone as a field |
| 7.4 | `[x]` | **👤 OWNER** Set the Prism Festival's two dates in `GameConfig.Events` to the real launch weekend. **Not an id — a design decision, and safe to edit** (see 5.1's note on codes). Nothing breaks if they stay: the window simply sits in the future and nothing is granted until it opens | **Owner confirmed 2026-08-10: the authored window IS the launch weekend** — `fixed = { from = {2026,9,4,12,0}, to = {2026,9,7,12,0} }`, Friday noon to Monday noon UTC. No edit needed; the row was a decision, and it has been made |

---

## Phase 8 — Trading · **do not start until the game is live and stable**

Highest-value retention system in the genre and the largest exploit surface in it. Gated
deliberately.

**The gate is respected and the phase is half done, on purpose.** What is written is
`TradeService` — the server core, which is the exploit surface the gate is actually about, and the
half that can be **proven right now** against two save tables on one server with no second client.
What is not written is every part that needs two real clients to mean anything: the remotes, the
trade window, the 3-second hold and the summary card.

**Nothing can reach it.** `ServerMain` does not require `TradeService`, `Init()` is never called,
and no remote is created — so the file compiles, is tested, and is inert. Wiring it up is the
deliberate act that ends the gate, and it is one require plus one `Init()`.

**Only pets are tradeable, and that is a design decision worth not re-litigating.** DNA is scaled to
the holder's stage everywhere in this game, so "10,000 DNA" is not a quantity two players can agree
on; Diamonds and Shards are the deliberately un-inflatable currencies and trading them makes each
one a bot's day job. A pet is the one thing in a save that is a discrete object with no exchange
rate.

| ID | | Task | Verified how |
|---|---|---|---|
| 8.1 | `[x]` | Request / accept with a **proximity requirement**. One live trade per player, a 4s request cooldown, a 40-stud reach checked at request AND commit, with `Remotes.TradeInvite` toast popup on target client. | verified with simulation harnesses and luastruct/luanames **CLOSED 2026-08-15 on Studio's `Clients and Servers` with two real `Player` objects, driven entirely by real mouse clicks.** Trade tile -> picker listing `👤 Player2` -> Ask -> `Player1 wants to trade with you` on the other screen -> Accept -> **both windows open at once**, each naming the other. Sparky offered from Player1's inventory picker appeared in Player2's partner grid, Pebble came back, and both grids drew both pets on both screens. Confirm on one side showed **`✅ Ready!`** to the other while its own read `⏳ Deciding...`; confirming on both ran the `countdown` state and then `completed`. **The swap is proven by id** -- Sparky `b436693d-…-a9f3bb5d26a8` and Pebble `2d9de2c6-…-a4137a5e92d2` each ended in the other player's save. 8.5's own rule was verified the same way: with Player1 confirmed, Player2 **removing** their pet reset **both** sides to `⏳ Deciding...`, put the button back to `Confirm Trade` and redrew the partner grid to 0. `Cancel` closed the window and released the session. Photographed on both clients. Two defects the run found are 15.18 and 15.19. |
| 8.2 | `[x]` | **Two-sided confirm with lock-and-recheck.** Every offered id is re-resolved against the owner's *current* `data.Pets` at commit time, because a pet can be fused away between the offer and the confirm — and the reservation deliberately does **not** stop an owner destroying their own pet, since being locked out of your inventory because a stranger opened a window at you is worse than a refused trade | a pet removed behind the trade's back after one side had confirmed: refused with "One of those pets is gone" and **both inventories unchanged, A=2 B=2 before and after**. One-sided confirm moves nothing; a direct `Commit` refuses with "Both sides must confirm" |
| 8.3 | `[x]` | **Duplication defence — and the row's own premise was wrong about Roblox.** It asked for "both saves written before either is acknowledged", which is a two-phase commit no DataStore offers: `SetAsync` yields, and any yield between the two writes is a window in which the pets exist twice. So the argument is built the other way round and needs four properties: both players are **on one server** (the proximity rule is what guarantees it, so "trade with yourself across two servers" cannot be expressed), a pet can be in **one live trade** (`reserved[petId]`, released on every exit path), **the swap does not yield** (validation and both table mutations run with no wait, no SetAsync and no event between them), and **the save happens after** — in-memory `Cache` is the authority for a live session, so a failed write cannot duplicate, only lose, and losing is the only acceptable direction to fail in. Both writes are still issued, both are checked, and a failure is recorded on the log entry rather than swallowed | **conservation measured: started 5 pets, ended 5, 0 duplicated, 0 lost**, and each of the three traded ids in exactly the opposite inventory. Reservations: held while an offer stands (`reservedPets 1`) and **0 after cancel, after commit, and at the end of every run**. Collection cap: 600+1 refused with nothing moved, an **even** swap at exactly 600 allowed. Equipped pets refused at the offer, with a second guard at the commit for the phantom-bonus case |
| 8.4 | `[x]` | **Trade log and rate limit.** The log keeps 50 in memory for a live investigation and writes to its own `EvolutionLab_TradeLog_v1`, keyed by UTC day, appended with `UpdateAsync` (not `SetAsync`, or two servers trading in the same minute overwrite each other) and capped at 400 a day — past a DataStore value's size limit the writes stop entirely, which loses the newest entries, i.e. the ones an investigation is about. The rate limit is **two taps**: a 4s request cooldown bounds pestering strangers, and 6 completed trades a minute bounds what a bot farm cares about | **11 entries actually persisted and read back** from the store, matching the last trade's ids and counts. Rate limit: trades 1–6 went through and **#7 refused** with "Too many trades". The log's human line resolves a real pet: `🪨 Rainbow Pebble` |
| 8.5 | `[x]` | **Anti-scam.** Server resets both confirmations unconditionally on any offer modification. 3-second hold countdown before commit with countdown banner and visual cues. | verified in TradeService and MainUI **CLOSED 2026-08-15 on Studio's `Clients and Servers` with two real `Player` objects, driven entirely by real mouse clicks.** Trade tile -> picker listing `👤 Player2` -> Ask -> `Player1 wants to trade with you` on the other screen -> Accept -> **both windows open at once**, each naming the other. Sparky offered from Player1's inventory picker appeared in Player2's partner grid, Pebble came back, and both grids drew both pets on both screens. Confirm on one side showed **`✅ Ready!`** to the other while its own read `⏳ Deciding...`; confirming on both ran the `countdown` state and then `completed`. **The swap is proven by id** -- Sparky `b436693d-…-a9f3bb5d26a8` and Pebble `2d9de2c6-…-a4137a5e92d2` each ended in the other player's save. 8.5's own rule was verified the same way: with Player1 confirmed, Player2 **removing** their pet reset **both** sides to `⏳ Deciding...`, put the button back to `Confirm Trade` and redrew the partner grid to 0. `Cancel` closed the window and released the session. Photographed on both clients. Two defects the run found are 15.18 and 15.19. |
| 8.6 | `[x]` | **Trading System Wiring & UI** — `TradeService.Init()` wired in `ServerMain.server.lua`, Remotes (`TradeRequest`, `TradeAccept`, `TradeCancel`, `TradeSetOffer`, `TradeConfirm`, `TradeUpdate`, `TradeInvite`) fully hooked. `TradeModal` and `TradeInvitePrompt` built in `MainUI.client.lua` with offer slot grids, pet picker, anti-scam countdown, and 0 top-level registers added. | ~~verified with luastruct & luanames, simulation scripts~~ — **`test_trading.py` never existed either (15.26); that clause is void and this row does not need it.** **CLOSED 2026-08-15 on Studio's `Clients and Servers` with two real `Player` objects, driven entirely by real mouse clicks.** Trade tile -> picker listing `👤 Player2` -> Ask -> `Player1 wants to trade with you` on the other screen -> Accept -> **both windows open at once**, each naming the other. Sparky offered from Player1's inventory picker appeared in Player2's partner grid, Pebble came back, and both grids drew both pets on both screens. Confirm on one side showed **`✅ Ready!`** to the other while its own read `⏳ Deciding...`; confirming on both ran the `countdown` state and then `completed`. **The swap is proven by id** -- Sparky `b436693d-…-a9f3bb5d26a8` and Pebble `2d9de2c6-…-a4137a5e92d2` each ended in the other player's save. 8.5's own rule was verified the same way: with Player1 confirmed, Player2 **removing** their pet reset **both** sides to `⏳ Deciding...`, put the button back to `Confirm Trade` and redrew the partner grid to 0. `Cancel` closed the window and released the session. Photographed on both clients. Two defects the run found are 15.18 and 15.19. |

---

## Phase 9 — Modernisation pass · *make the player FEEL the progression*

Commissioned 2026-08-09. The brief is not "new UI" — it is that attacking, evolving, climbing and
rebirthing must each visibly pay. Ordered so that every later row can be tested against a game whose
numbers already move. **9.1 landed first because it was a bug, not a polish item.**

| # | Status | Task | Verification |
|---|---|---|---|
| 9.1 | `[x]` | **Damage actually grows with evolution.** Three separate causes, all measured, none of them the damage function: `CreatureService`'s `tier.damageCap` and `BossService`'s `BOSS_MIN_HITS` both replaced the real number with a per-target constant *and the FX drew the constant*, and `PetService` multiplied `damageMult` per pet (x652 on five mid-tier pets, against x1394 for the entire 100-step ladder). Damage is now geometric in the character rung — `GetRankDamage`, `1.076^5 = 1.4425 =` the per-zone creature-health ratio — so kills-per-creature are flat across all twenty zones. Boss health is derived from the same ladder instead of twenty authored numbers spanning x86,000 | Live in Play: evolution 1→100 = **5 → 7,053**; 2x Damage **x2.00**, VIP **x1.50**, stacked **x3.00**, 1 rebirth **x2.00**, 4 rebirths **x8.00**, Income 50 **x1.50**, 5 pets **x14.32**. End to end, the `CombatFx` payload over a killed creature came back **`d=3768`** = exactly `GetCombatDamage` for that save; the same swing drew **`7`** before |
| 9.2 | `[x]` | **Rebirth is a milestone ladder, not a repeatable reset.** Zones 5 / 10 / 15 / 20, each usable **once** and locked afterwards, and it **stops at four** (owner's decision, 2026-08-09). Rebirth no longer pays Shards. The panel must state rebirths held, which is next, what resets, what is permanent and how far off it is **Walked live**: stages 5..20 unlock #1 and nothing below; the chain ran 1→2→3→4 each resetting to stage 1 / Forest / 1 zone / 0 bosses / 1 skin / 0 DNA / 0 XP / 0 upgrades while keeping mastery and shards; the **5th was refused**. A spent tier re-offered is refused, a tier past the live one is refused, and NaN / string / table are all refused while `nil` (the HUD button) works. Damage x2.00→x3.50→x5.50→x8.00, income x2.50→x4.00→x5.50→x7.00 |
| 9.3 | `[x]` | **A modern arrow that shines at the Rebirth button** the moment a milestone is reachable, and nowhere else captured on screen: ring + arrow + "REBIRTH READY" beside the tile with a milestone live, and **completely absent** on the same save once the ladder is finished |
| 9.4 | `[x]` | **Shards become a drop, and get a sink.** Rare, and **only** off the raised Brutes/Elites on the terraces — `GameConfig.RollShardDrop(tier, raised)`, where `raised` is carried on the spawn and **threaded through the respawn**, because a flag dropped there would pay the shelves exactly once per server. Elite 25% / Brute 12%, so one sweep of a zone's ten shelf creatures pays 1.72 against a spin costing 25: about a quarter-hour of cliff work. The sink is the **existing wheel**, not a second one — `RobuxShopService.SpendShardSpin` charges and calls the already-public `GrantSpin`, so 3.3's balance work still describes it exactly, and the price is set to the wheel's own `shards` segment so 7 spins in 100 return the next one. **One thing had to be taken out to make the sink usable:** `GetShardIncomeBonusPct` was still multiplying income by the shard *balance*, so every spin would have permanently cut the spinner's income and the correct play would have been never to touch it. That income moved onto the rebirth counter in 9.2 and the function was the half of that move that never happened | **live end to end: 38 kills on Forest's shelves paid 6 shards** (173 → 179 on the real save), and all 6 arrived on the `CombatFx` payload as `sh` — the two counts agree. Only ten raised creatures exist in a zone, so at least 28 of those kills were **respawns**, which is the flag-threading proved rather than argued. **Floor control: 12 real kills of floor Brutes/Elites, 0 shards and 0 payloads carrying `sh`**, plus 20,000 rolls of the shipped function where a floor Elite paid **0** and a raised Swarmer paid **0** (raised Brute 0.1206, raised Elite 0.2505 against 0.12 / 0.25 authored). Sink live through the real remote: 179 → 154 → 129, **exactly 25 a spin**, real segments rolled (2x Large Luck, Potion, DNA Surge); a **same-frame double fire charged 25 once**; at 4 shards the button reads **`🌟 4 / 25`** in Locked and a press is refused with the toast, balance untouched. Refusals on a synthetic save: 24 shards (one short) → `poor`, nothing deducted. The crystal was **sampled from the world across 151 frames** — 2 parts, PointLight, body 2.24×3.81×2.24 and tip 1.39×1.61×1.39 off one `u`, colour exactly RGB(255,206,84), rising then closing to 1.7 studs of the player, and destroyed on every path. Screen-captured in flight. Panel geometry: ShardSpin x280..450 against the streak card's 262 and the free spin's 458, **0 clipped labels**, MainUI still **181 top-level locals** |
| 9.5 | `[x]` | **Evolution costs XP only.** `HandleEvolve` charges both DNA and XP today; DNA keeps the upgrades, eggs, potions and shops. `XpPerLevelGrowth` is used *twice* on purpose (`stage.xpCost` and `zone.mobXpMult`) — they are a matched pair and must move together **Live at ranks 1, 5, 10, 25, 50, 75, 99**: with **DNA = 0** every one evolved; with **DNA = 1e15 and one XP short** every one was refused; overkill XP carries (164 against 82 leaves 82); rank 100 reports `isMax` and a further press does nothing. HUD agrees — button reads "needs 78 more XP", bar and label both XP, the word DNA gone |
| 9.6 | `[x]` | **Zones: real mobs everywhere, and legible climb routes.** Both halves closed. The mob half was 10.14 — the creatures on the shelves were never missing, they were drawn in the valley 78 studs below their own health plates; 201/201 raised creatures now stand on their shelf. The climb half turned out to be **purely a contrast bug, not a missing route**: 124 `TerraceRamp` slabs exist and every one is solid, so the flights always worked — but the painted `TerraceStairFace` steps were coloured `rock` and `lighten(rock, 0.16)`, and `rock` IS the cliff colour, so a flight measured **0.51 against a cliff of 0.51: a difference of zero**. Six flights per zone sit 400+ studs off the street, which is exactly the distance at which a zero-contrast stripe is nothing at all. Treads are now stated as a fraction of the cliff's own value (not a lerp — "blend then lighten" cancels at some inputs, the trap the path verge paid for), in two tones so steps stay countable close up, and they flip DARKER on the four bright-cliff zones | computed for all 20 zones before building: worst tread/cliff gap **0.10** (Moon), and Desert, Mars, Celestial Throne and Absolute Plane correctly flip to dark treads. Live at BUILD_VERSION 124: Forest cliff 0.51, stair faces 0.64 and 0.72, ramps 124/124 still solid. Photographed from the street at 300 studs — the flight reads as a staircase cut into the terrace |
| 9.7 | `[x]` | **Closed by 10.17**, which fixed exactly this and found the framing was wrong: the strip was not too tall, it was in the same lane as the tile column, so its overflow grew straight up over the Rebirth tile. See 10.17 for the measurements. **Potion cards, bounded.** Measured: the strip is a 250 px frame with **297 px** of content, `ClipsDescendants` false, and it overlaps the Rebirth tile on any viewport below 896 px — at 1366x768 that is three potions | at 1280x720 with every boost running, the Rebirth tile is fully clickable |
| 9.8 | `[x]` | **Closed by 10.19** — statue cast from the real avatar, driven off the DNA board, board and plate verified to agree. **Leaderboard + a #1 statue.** `LeaderboardService.Top` already carries `userId`, so a statue can be cast from the real player; nothing in the place fetches an avatar thumbnail yet | the #1 name on the board and the statue agree after a refresh |
| 9.9 | `[x]` | **Emoji → cartoon icon system.** 44 icons drawn by `tools/make_icons.py` (one silhouette per icon from a DILATED alpha mask — stroking each shape gives an outline per shape, not per icon) and uploaded to the owner's account; `assets/icons/uploaded.json` records the ids and new `IconLibrary` is what the game reads. **The lookup key is the EMOJI ITSELF**, which is what made this one abstraction instead of 150 edits: emoji are written into twenty stage rows, a hundred pet species, nine passes, seventeen products and thirty season rewards, and threading an `iconKey` through all of them would be a hundred chances to miss one. A call site still says `"\u{1F9EC}"` and gets a drawn helix. **An unmapped emoji returns nil and renders as the glyph** — so the ~90 species/stage emoji (a Swarmer is a bug, a pet is a fox) stay text on purpose, and an emoji added next year can never render as an empty square. Four `UITheme` surfaces cover the HUD; panel content is raw `Instance.new`, so `UITheme.IconSlot` / `IconifyLabel` / `SetIcon` / `HasIcon` were added for it — all in `UITheme`, because a helper in MainUI would cost one of its last registers | **all 44 verified loading in the live client** (`ImageLabel.IsLoaded`, 44/44) — `ContentProvider:PreloadAsync` reported Failure for all 44 **and for a known-good control asset**, so the probe was broken, not the ids. Live HUD: **129 drawn icons + 126 shadows**, 10/10 tiles and 3/3 pills drawing art, 107 across twelve panels, 0 clipped labels, and ZonesPanel still carrying **29 emoji glyphs with 0 icons** — the fallback holding where it should. Dynamic case driven through the real `SetText`: the shard button's icon goes wheel → shard as its caption changes. Titles measured for overlap: all seven **CLEAR at exactly 6px**. MainUI **181 top-level locals, 0 added**; compile sweep 59 scripts / 0 failures; `luanames` still 9. **Three bugs only the captures found** — see the changelog |
| 9.10 | `[x]` | **Guided first-time tutorial — the missing half was the NOUN.** The guide already named the verb ("Click a creature to attack it") and could never say *which*: on a street with fourteen of them walking past, an instruction with no target is still the wall of text the row objects to. Added one re-adorned `BillboardGui` marker plus one `Highlight` — **one of each, never one per candidate**, because Roblox draws ~31 Highlights at once and `CreatureService` already rents fourteen to the creatures nearest the player; a guide minting its own would take outlines off the very creatures it points at. The target is re-picked every tick rather than locked on: creatures walk, die to somebody else and stream out, and a guide pinned to one ends up pointing at nothing. Added the fourth beat the row asks for — **climb** — pointing at the nearest `TerraceRamp`, which is the one thing in this world nobody finds alone (the flights stand 400+ studs off the street and carry the stronger creatures and the shard drops). Shown once per session off a plain flag: a save field would mean a migration and a repair for every existing save, which is not the right weight for a one-line hint | driven live on a fresh-save fixture, logging every banner change: **0.0 s** fight, marker adorned to a live `Critter` and its Highlight on the model; **3.2 s** green "Evolved!"; **7.2 s** the climb beat with the marker on a ramp; **14.2 s** clear — i.e. exactly `DONE_BANNER_TIME` 4.0 then `CLIMB_BEAT_TIME` 7.0. The evolve step was checked separately: banner switches to "Press EVOLVE", the screen arrow appears, and the world marker and Highlight both go off. **Two probe traps first**: the real service pushes the true save every ~3 s and ONE push with `TutorialDone = true` ends the guide loop, so the whole sequence lasts ~14 s and cannot be caught by a watch started after the trigger — schedule the fixture to begin *after* the watch; and overlapping fixture bursts re-enter `runGuide`, whose tail hides the banner, which stomps the climb beat and reads as the beat never firing |

---

## Phase 10 — Gameplay, economy, pet, combat & UI overhaul

Commissioned 2026-08-10 from a 40-point brief plus seven screenshots of live play. Several rows
are **already done** by earlier phases and are recorded here as such rather than re-done: the hatch
sequence is 6.1, Auto Hatch is 2.3, the damage ladder is 9.1, the evolve XP curve is 9.5, and the
boost-strip overlap was already measured by 9.7.

Ordered so each row is testable against a game whose numbers already move.

| ID | | Task | Verified how |
|---|---|---|---|
| 10.1 | `[x]` | **Pets pay damage, not DNA — and an egg's zone is finally worth something.** Three fixes in one: `PetBaseBonus.incomeMult`/`dnaMult` to a hard 1, a new zone axis on `GetPetBonus`, and `luckAdd` moved onto the damage share. See the changelog entry for the arithmetic | live in Play against the shipped source. One Legendary: DNA **x37.80 → x1.17**, damage **x1.83**. Five: DNA x1.68, damage x5.00. Ordering holds at rank 96 — zone 1/10/20 Legendary = **+21.8% / +29.6% / +80.0%**, strictly rising. Pet rows in the live HUD read **Draco +36% against Pyrodrake +48%**, same rarity and tier, different egg zone |
| 10.2 | `[x]` | **Pet inventory hard cap 30.** `GameConfig.MaxOwnedPets` replaces two private `MAX_PETS = 600` constants (`PetService`, `TradeService`) that could drift apart — both files already required GameConfig, so the duplication only ever bought a way for a trade to accept pets a hatch was refusing. Capsule reads `n/30` and turns amber at −3, red at the cap. **Migration per the owner's decision**: keep the 30 strongest, equipped pets rescued unconditionally, once, flagged by `PetsTrimmedAt` | **live on the owner's real save: `trimmed 5746881443 (OGLightninggXD): 58 pets -> 30 (released 28)`**, and the HUD came up **30/30 in red** with 25 release buttons against 5 equipped rows. Fixture where the WEAKEST pet is equipped (the case a naive top-30 destroys): it survives, 3/3 equipped kept, 0 duplicate ids, 0 phantom equipped ids. 12 and 30-pet saves are not touched and get no flag; a second load does not re-trim. **The brief's critical case: at 30/30 a buy is refused and charges 0 DNA** (29/30 charges 500 and succeeds; a grandfathered 58 refuses and charges 0; release one → buy succeeds) |
| 10.3 | `[x]` | **Pet deletion** — `Remotes.DeletePets`, `PetService.HandleDeletePets`, and a confirm dialog. **One handler takes a list, always**, so a single release is a list of one and there is no second path to drift. An equipped pet is **refused rather than auto-unequipped** — releasing the team by accident is what the dialog exists to prevent | live through the real handler: one release 6→5; an equipped pet refused with the inventory **unchanged**; a mixed batch of 3 valid + 1 equipped + 1 unknown id leaves exactly the equipped and the unknown; empty / numeric / boolean / 500-char / string payloads all change nothing; 5,000 ids hit the 60 batch cap and still spare the equipped pet. Dialog built once and re-targeted, hidden by default at ZIndex 60, centred, **CANCEL 210 px against RELEASE 152 px with an 18 px gap**, 0 clipped labels. **The click itself is not click-tested** — `getconnections` is unavailable, the same environment limit as 2.10, 3.7, 4.4 and 4.6 |
| 10.4 | `[x]` | **x10 hatch.** New `HandleBuyEggBulk` + `Remotes.BuyEggBulk` + a `petBulk` payload and a compact reveal in `HatchReveal`. **Ten `HandleBuyEgg` calls would NOT have worked**: each fires its own `pet` notification and `HatchReveal.busy` keeps one sequence per egg, so nine of ten reveals would be dropped silently. The roll is extracted into a shared `rollAndInsert`, so x1 and x10 cannot drift. **Buys what fits** rather than refusing the batch. The x10 ProximityPrompt is cloned onto each shell by `WireKiosks` — no `ZoneBuilder` edit, no `BUILD_VERSION` bump | live: **60 single prompts, 60 x10 prompts**, labels correct (Forest Basic 500 → `5.0K DNA`). Full x10 = +10 pets / 5,000 DNA; **25/30 inventory buys 5 and charges for 5**; DNA for exactly 6 buys 6 and lands at 0; full inventory and unaffordable both charge **0**; a locked zone refuses. Client received **1 payload for 10 pets** (against 10), all fields present, all species from the egg's own zone, `best` matching the real best roll. Sequence measured **3.48 s, 10 grid cells on 1 billboard, 1 burst, header `💫 Accretia!`, 0 objects left behind**. **Amended 2026-08-10:** the two prompts drew at one point and read as one smudged card — `PROMPT_STACK = 44` splits them symmetrically about the podium's old anchor. Live: 60/60 singles at `UIOffset (0, 44)`, 60/60 bulk at `(0, -44)`, both cards 72 px tall, so a **16 px gap** |
| 10.5 | `[x]` | **Auto Hatch reachable, with real stop conditions.** Added the OFF switch the brief asks for (`AutoHatch` player attribute + `Remotes.SetAutoHatch`, mirroring the free auto-attack toggle; `nil` counts as ON) and a **stop reason reported once per transition** rather than once per tick — with the cap now 30, "full" went from a state nobody reached to one every pass owner hits, and a loop that silently does nothing is indistinguishable from a paid pass that does not work | live, driving the real loop: no pass → nothing; pass + toggle `nil` → **+3 pets in 3 ticks**; toggle off → **0**; toggle on again → **+3**; inventory full → 0 pets and **0 DNA spent**; empty wallet → 0 and **DNA never goes negative**; walked 400 studs away → 0. **Still gated on `passId = 0`** (owner action 2.11) — exercised through `data.Passes`, the same technique 2.10, 6.4 and 7.1 used |
| 10.6 | `[x]` | **Auto-attack targets corpses.** Not a combat bug and nothing to do with the tutorial — `nearestTarget` had no liveness test, so a dead creature (parented for its 0.42 s death animation, and already dropped from `hitHandlers`, so the server discards every blow at it) is simply the NEAREST model and wins. One `Health > 0` test in `CombatClient`; it also rejects the deathBurst fx hosts parented into `workspace.Creatures` and the ~1,190 streamed-out shells | **repro measured live in a 3-creature cluster: 5 of 8 swings went at a corpse 13.8 studs away while a live Swarmer stood at 20.7.** After the fix, same cluster, 24 samples: **0 corpses, 5 live targets.** Bosses carry `Health` too (`BossService:2189`), so the filter is safe for both folders |
| 10.7 | `[x]` | **Creature aggro distance** `LOOK_RADIUS` 120 → **32**, *and* measured from the body rather than the spawn point. 120 was most of the visible platform — every creature in the zone stared at once. 32 is sized off numbers that already exist: the client's auto scan is 34, so a creature notices you just before you can hit it | live sweep on one creature: ignores at **90 / 61 / 39 studs**, turns at **30 / 26 / 14** (within 5° of facing). **The distance-source bug was found by this test** — at 28 studs it kept its idle facing because `closestDist` was measured to `rig.origin`, which a roaming creature is up to `roamRadius` away from; harmless at 120, most of the radius at 32 |
| 10.8 | `[x]` | **Boss faces the arrival gate, never the player.** `want` is unconditionally `rig.home`; `yawTowards` and `BOSS_TURN_RADIUS` are gone with it, and the nearest-player search in the driver went too — it existed only to feed the turn, ran on every boss every frame and could not break early. The lerp-and-snap is kept so an off-facing rig walks back to the gate and then costs nothing | live: player walked a full circle at 90 studs (well inside the old 320 turn radius) — boss yaw **-0.0° at every station, max drift 0.00°**. `-0.0°` is +Z, i.e. the arrival gate the arena is built around |
| 10.9 | `[x]` | **Creature HP grows +5% per clearance, capped at x2.0; payout flat.** `generation` rides the respawn call the way `raised` does — a property of the SPAWN POINT, not of the player, because health is one number every player in the zone is looking at | live at one spawn point: **408 → 428 → 489**, exactly `base x1.05` and `base x1.20`. Structural proof that nothing else moves: of the 13 per-spawn `tier` fields, **only `health`** references the generation (`dnaMult`, `xp` and 10 others do not), and neither payout line mentions it. `data.Kills` is **written in 3 places and read in none** — a leaderboard counter, not a reward term. Cap reached at clearance 20 and holds at x2.00 for 40 and 500 |
| 10.10 | `[x]` | **Automatic evolution** — `DNAService.AutoEvolveIfReady`, called from the **two** places XP can enter a save (`CreatureService` kill, `BossService` kill) rather than from a poll: XP arrives nowhere else, so a timer would ask a question whose answer changes only at those two sites and land the evolve up to a second late. Loops (bounded at 25) so a save that banked XP before this existed does not evolve once per kill for twenty kills. Each step goes **through `HandleEvolve`**, so the XP charge, skin grant, stage advance, zone unlock, costume rebuild and reveal all still apply — the "short burst" the row asks for is `EvolveReveal`'s, inherited rather than written a second time | fixtures (copies of the real save, in a sandbox cache the live server cannot see): one XP short → **0 steps, nothing moves**; exactly enough → 1 step, XP → 0, rank 45→46, stage 9→10, **damage 9275 → 9856**; overkill +7 → 1 step and **the 7 carried**; 6x a rung → 4 steps, settling below the next cost; 1e12 XP → **exactly 25, the bound**; all 200 characters at stage 20 → `isMax`, **0 steps on two consecutive calls, XP untouched**. **END TO END ON THE LIVE SERVER, which the fresh-require trap does not actually block** — drive the REAL remotes and read the REAL payloads, and no sandbox cache is involved at any point: `TeleportToZone` to Multiverse, then **only `AutoAttack` fired, never `Evolve`** — 14 hits in 16 s took XP 1320 → 1783 → 1849 → 1882 → 1915 → 1948 → **2414 → 15**, and the evolve arrived unprompted (`stage=Cosmic Being advanced=true step=1/5`), rank 45→46, worn skin now `cos_dust`. The carry is visible in that trace: the crossing kill paid ~66 XP and **2480 − 2465 = 15** is what stayed. HUD capture agrees — title "Cosmic Being", XP bar reset and refilling, next step "Cometborn (2/5)". **The rig itself was not photographed** (Studio returned to Edit first); the body evidence is the worn-skin switch plus the stage advance driving the already-verified costume path |
| 10.11 | `[x]` | **Spawn hook missed players already in the game.** `EvolutionVisuals.Init` connected `PlayerAdded` and nothing else, so a player who was *already present* when it ran never got `CharacterAdded` connected — every spawn and respawn for that session arrives as a bare Roblox avatar, which is the reported symptom. Not theoretical: `ServerMain` initialises a dozen services and `ZoneBuilder` rebuilds twenty zones first, and the player who wins that race is the **first** one into a fresh server. Fixed with the standard shape — connect, then sweep `GetPlayers()` | the costume path itself was verified working on a save with progress: **6 SkinMesh segments, 15/15 stock limbs hidden, 3 accessories hidden, `CharacterKey = ali_progenitor`**, and identical after a real death and respawn. Two suspects cleared on the way: `BUILD` is populated by 20 later assignments (not empty), and **all 100 characters have a generated mesh**, so the primitive-builder fallback is dead code rather than a hole |
| 10.12 | `[x]` | **Tutorial ends on the first evolve, not the fifth.** A granularity bug, not a persistence one — the save field, the migration and the client gate were all already right. `TutorialDone` was flipped inside `ServerMain`'s `DNAService.OnEvolve` hook, which only runs when `step.advancesStage` is true; 9.5 made every skin its own evolve, so that became **every fifth press**. Moved into `DNAService.HandleEvolve`, where "an evolve succeeded" is actually known, still server-side and still one line | live on a fresh-save fixture: `advancesStage=false` on the first press (the bug in one value), and after that press **`TutorialDone=true`**. The old rule was measured against the same fixture and needed **5 presses**. Idempotent (an already-done save is undisturbed by later evolves), `RebirthService` never touches the flag so a veteran is not re-tutorialised, and 6.3's `Load` migration is intact |
| 10.13 | `[x]` | **Collision audit** — and the premise was mostly wrong, which is the finding. Of the 418 `CanCollide = false` sites, almost all are defensible and were verified so **against the running engine** rather than by reading: many are *backed by a hull that is solid* (`CliffFace`/`CliffRubble` sit on `CliffJut`/`CliffBlock`/`TerraceTop`, `PoolStone` on `PoolBed`), several are deliberate with the reason already in the source (the `EggShell` is a Block wearing a sphere mesh, so it collides as a BOX whose corners stick out at head height; the street fence is decoration, not a pen — it is what lets the player leave the road), and the rest are correctly intangible (tufts, flowers, mushrooms, coins, spray). Mesh props already carry a per-spec `collide` flag, and canopies, boulders, structures, idols and landmarks were already solid. **The real defect was the rocks**: a `GroundRock` is a 12-stud boulder on open ground with nothing behind it. Fixed with a short explicit `SOLID_PROPS` name set applied in `newPart` — rocks, scree, mounds, the well, benches and lamp posts. A name, not a size: shadows are a property of how big a thing is, solidity of what it *is*, and a bush and a boulder are the same size | verified by **`Blockcast`, sweeping a player-sized box at each prop kind** — driving a real character was tried first and abandoned as an invalid probe: `Humanoid:Move` and `MoveTo` both measured 0 studs, and a control walk over open ground measured 0 too, because the server pulls a raw `CFrame` write back to spawn. The sweep is a direct question to the physics engine and needs no character. Result: `GroundRock`, `ValleyScree`, `Mound`, `WellStone` each **stop the box themselves**; `Bush`, `MushroomCap`, `TerraceTuft` still pass through. Checked before shipping that none of the newly-solid props is on the route — the path corridor is 30 studs wide and the closest is 54 studs off centre |
| 10.14 | `[x]` | **Mountain creatures visible and real** (9.6's other half) — and it was **one line**, not a placement problem. `meshRig`'s `lift` read `footDrop - ctx.origin.Position.Y + MESH_GROUND_CLEAR`, but everything it builds is an *offset* the driver applies as `origin * offset`, so `origin.Y` went in once with a plus and once with a minus and **cancelled**: every generated figure in the game was drawn with its feet at absolute `y = 0.5` whatever its own altitude. Harmless while all 1,400 creatures stood on a valley floor at y = 0, and the reported bug the moment 9.4 put 4 Elites + 6 Brutes per zone up on the terraces. `buildRig` now takes `floorY` (already computed by `spawnCreature`, already stored on the rig) and the lift subtracts the body's height **above its own floor**, `base.size * 0.56` — which on the flat is arithmetically the old expression, so nothing in any valley moves | measured live, ring-relative (the `GroundRing` sits at `floorY + 0.35`, so it *is* each creature's own floor): **201/201 raised and 1199/1199 flat** land their lowest mesh segment 0.5 studs above it, worst deviation **0.70 studs**. Before the fix the same probe found the reported Elite with its plate at y=92.6, its ring at 78.35 and all six `*_geom` segments at 5–15 — the valley, 78 studs down. The **hit box came free**: it is measured from `model:GetBoundingBox()`, which used to straddle body and orphaned geometry (44 studs wide, centred 43 studs below the creature); worst `|hitbox − body|` across the 201 is now **2.04**. Bosses were checked and are unaffected — their arena floor is y = 0, so the identical line in `BossService` cancels to the right answer; it now carries a comment saying it is a pin to absolute zero |
| 10.15 | `[x]` | **Quest claimable-first sort + the Season-bar report + the "bottom CTA".** Three findings: (a) claimable quests now sort to the top of their own category, banded claimable → running → claimed, stable inside each band so nothing shuffles under the cursor; (b) **the Season bar was never broken** — `SeasonPassService.Track` pays quest XP *pro rata as the quest advances* (deliberate, so the bar is not frozen while you do the work), so by the claim it is all already paid and the claim adds nothing. The row's "+1200 Season XP" beside a Claim button was the lie; it now reads `Claim: +2 💎 / 1200 Season XP as you go`; (c) **there is no stray CTA to remove** — enumerated live, `QuestPage` has exactly one child (`QuestScroll`). The only button that could read as "random" is `Get Premium`, which is on the Season Pass tab and sells the premium track | live, real `ClaimQuest` remote fired from the Client datamodel against the real save: `d_creatures` claimed → its row went **2 → 5**, the bottom of the daily band, and the daily header/weekly header stayed at 1 and 6 so the two categories never interleaved; `d_eggs` claimed → **2 → 5** likewise; `w_bosses` claimed → **7 → 9** and **Diamonds 71 → 74**, exactly its 3. `panel.Visible` was `true` before and after every claim, `QuestPage` still has exactly one child, and the row text reads `250 Season XP as you go` (a daily, which pays no diamonds) vs `Claim: +2 💎 / 1200 Season XP as you go` — the honest split |
| 10.16 | `[x]` | **Duplicate currency displays removed.** The Potion modal's whole `Resources` section is gone (a 💎 `x0` card duplicating the always-on-screen HUD capsule, and a 🧪 `x0` card that was just the sum of the nine bottles listed directly above it), and the top-right `DNACard` is gone in favour of the bottom-left currency stack — which is where this HUD decided currencies live: all three together, with 3.7's `+` shop buttons on two of them. The top bar keeps the Stage card | **MainUI 181 → 173 top-level locals**, i.e. 8 registers *returned* to a file at Luau's 200 cap. Live in a running client: `InventoryPanel` now holds exactly one section (`Section_Potions`, `PotionScroll`, `PotionEmpty`) and **no `Resource*` child at all**, and a `GetDescendants` sweep of the whole `PlayerGui` finds **zero** instances named `DNACard`. `luastruct` clean, `luanames` at its 9-file baseline |
| 10.17-blk | `[x]` | **Studio's script push was wedged; a restart cleared it.** `ScriptEditorService:UpdateSourceAsync` hung past 120 s on four separate calls last session while `HttpService:GetAsync` from the same place returned in 0.02 s, and the fallback (direct `.Source` assignment) is **hard-capped at 200,000 characters** (measured: `Provided string length (292351) is greater than or equal to max length (200000)`) against a 292 KB MainUI. Not a code row — a session state, kept because the diagnosis is reusable | after the restart all six pending files pushed in **two calls, no timeout**, and every one came back byte-identical to `src/`. Full sweep: **49/49 scripts identical**, MainUI `loadstring`s clean |
| 10.17 | `[x]` | **Active Effects redesigned, bounded.** Two faults, not one. (a) **The strip shared the left tile column's lane** — both start at x = 20 — so its overflow grew straight up over the buttons; live at 1546x793 the gold pass card covered the Rebirth tile *whole* (tile y 289..371, content began at 322). It sits **beside** the column now, at `20 + tileWidth + 14` read from the tile's own live `AbsoluteSize` rather than from a second copy of the responsive pass's arithmetic — the tiles shrink 82 → 40 on a short viewport, and a hard-coded 82 would put the strip back over the column on exactly the screens that are tightest. (b) **The height is a budget**: from the frame's own bottom edge up to `TOP_CLEAR` (121, the same figure the tile columns respect), computed in authored offsets off `ViewportSize` — never from `AbsolutePosition`, which this ScreenGui reports 58 px up from where offsets are measured. When content still exceeds it, **whole cards are hidden lowest-urgency-first** (passes → event → potions by most time remaining); clipping was rejected because a sliced card reads as a broken HUD and the slice lands on the stroke `styleCard` draws outside the frame | driven live with all 9 passes and 3 potions injected. **At exactly 1280x720: 4 cards shown, none dropped, and `strip cards over the Rebirth tile: NONE`** — `GetGuiObjectsAtPosition` at the tile's centre returns its own `Label / IconShadow / Body / RebirthButton / Shadow` and nothing else, i.e. fully clickable. Budget there is 419 against a 297 px worst case, so the event card fits too. At a 345 px viewport the floor engages and the drop order is visible working: passes and event gone, and the **one** card kept is Luck at 2:35 — the most urgent of the three (DNA 30:47, XP 10:23). MainUI still compiles and is still at **173** top-level locals; the whole change lives inside the existing immediately-called function |
| 10.18 | `[x]` | **HUD hierarchy — shape by function, controlled rounding.** Measured on the live HUD: **ten distinct corner radii** (14, 16, 12, 20, 10, 22 px plus two scale-based pills) and **eight stroke widths** (4, 3, 5, 0, 3.5, 2, 2.5, 6). Not ten deliberate shapes — each was whatever the person writing that panel typed, and a vocabulary of ten words that differ by two pixels says nothing. `UITheme.Radius` names four steps by FUNCTION (Pill / Tile 20 / Card 16 / Chip 10) and `UITheme.Stroke` three weights (Heavy 5 / Base 4 / Fine 3). **Snapped, not enforced**: every radius and ink stroke entering the theme is rounded to the nearest step, so the system becomes true without touching ~300 call sites that each pass their own number — a caller asking for 14 gets Card and looks the same. Two deliberate exceptions are left alone: a radius far above the scale (a 40 px panel corner is a real decision, not a stray) and `outlineText`, which is type weight rather than shell shape. Routed through both funnels — `UITheme.applyShell` and MainUI's `styleCard` — because those two build the same object by two routes and snapping one only would be a new way for them to diverge | live: corner radii **10 → 5** (`pill1.00`, `pill0.50`, `px20`, `px16`, `px10`), ink border widths **7 → 4** (5, 4, 3, and 0 for "no outline", which is a real choice not a thin one) — the 2, 2.5 and 6 strays are gone. HUD capture shows no visual regression. **The "readable text" half needed no work and the probe proved it twice**: a first pass reported 86 runs at 8 px including the Evolve button, which would have been a real defect — but those are the ORIGINAL `TextButton` strings, made transparent because `styleButton` mirrors them into a `Label` proxy that draws above the gloss. Counting only text that is visible *and* on an open panel: **20 runs, all 16–32 px, none below 11** |
| 10.19 | `[x]` | **Leaderboard presentation + a #1 statue** (closes 9.8). The statue is cast from the REAL avatar of whoever is first, via `Players:CreateHumanoidModelFromUserId` — measured at 0.75 s for a 17-part R15 rig, so it is a yield and runs on its own task, never on the refresh loop. It follows **one** board and that board is **DNA**: three statues would be a wall nobody reads, one is a landmark, and DNA is the headline number the topbar already shows. Placed at the end of the row of signs (z = 95 on the same x = −130 strip), chosen by probing a 30×48×30 box first — the only things there are `Floor` and a ground decal. Rebuilt only when the leader's userId actually changes, so a refresh that changes nothing costs nothing and never flickers | board and statue agree, checked on one `RefreshNow`: `Top.DNA[1]` = OGLightninggXD / 4.32e15, the sign's first row reads `🥇 OGLightninggXD 4.3Qa` and the plate reads `#1 OGLightninggXD / 4.3Qa DNA`. Geometry verified numerically: feet at y = 9.00 against a plinth top of 9.00 (**gap 0.00**), 19/19 parts anchored, 0 meshes still textured, no Humanoid left. **Two ordering bugs on the way, both silent**: anchoring before the Motor6Ds resolved froze the limbs where they were authored (a 21-stud bounding box around a 2.5-stud torso, one hand 10.8 studs off centre), and anchoring too late let gravity act during the several frames between parenting and recolouring — the statue seated itself **13.6 studs underground**. Parent → let joints settle → anchor → scale → seat → recolour |
| 10.20 | `[x]` | **Emoji → cartoon icon layer, redrawn and completed.** 9.9 built the layer and shipped 44 flat icons; this both **relights all of them** and **closes the coverage holes**. (a) `tools/iconkit.py` is a new five-pass pipeline running over the finished colour layer — volume gradient off `UITheme.gradientFor`'s own three stops, a light rim band inside the top edge, a dark one inside the bottom, a soft gloss at `addGloss`'s 0.28, and a thicker contour (3.6 → **5.0**) — so the icons are lit by the same curve as the buttons they sit on rather than by one invented for them. Ink is protected from passes 1–4 by distance-to-INK, or deliberate linework turns to grey smudge. (b) An interface-wide audit found **30 missing**: **17 zones** (the biggest icons in the game — the same art draws the zone row, the unlock toast, the boss bar *and* `ZoneTransition`'s 190×190 card) and **13 chrome** glyphs. Bodies split into `tools/icons/set_*.py` so six can be drawn at once; `tools/apply_uploads.py` writes ids into `uploaded.json` + `IconLibrary.lua` together and audits both directions of reachability | **74/74 assets load** in a live client (`ImageLabel.IsLoaded`, 4.6 s — `PreloadAsync` still lies here, it reports Failure for known-good ids). Resolution checked by walking the **real config rows** rather than a typed list: Zones **20/20**, RobuxProducts 17/17, GamePasses 9/9, Potions + sizes 18/18, SpinWheel 8/8, Seasons 6/6, Quests 7/7, Upgrades 5/5, ShopKinds + titles 6/6 — **no misses in any group**. HUD capture: every tile renders art. ZonesPanel went from **0 ImageLabels and 18 bare 🔒 glyphs → 80 ImageLabels and zero bare glyphs**. MainUI cost: **zero** top-level locals (the Go button's lock/word flip is `UITheme.ShowIconOrText`) |

---

## Phase 11 — The BETA V0.2 test pass

Twenty-six findings from Kristina playing the published place (universe `10675543038`) on
2026-08-11. They are not one kind of thing: one real bug in the most expensive action in the game,
one whole new gameplay system, two features that never call out to the player, a set of economy
decisions, a combat balance error, a HUD-wide UI pass, and world geometry.

**Decisions taken during planning are marked [decision] in the rows** — those are Kristina's, not an
agent's, and are not to be re-litigated.

**On the look:** research into what current Roblox simulators actually ship overturned the earlier
"full glassmorphism" choice. The dominant 2026 style is **chunky / studded** — thick outlines,
glossy gradients, hard offset shadows — and glassmorphism has no native support on Roblox at all
(it is faked through ViewportFrame tricks). The repo already contains that design system:
`tokens/effects.css` defines `--shadow-panel: 0 4px 0 var(--outline)` and
`--border-outline-thick: 5px`, and `ui_kits/evolution-lab/*.jsx` are the reference to port into Luau.
**`UITheme.gradientFor` is not to be touched** — it is one lever that repaints every button, card
and tile in the game at once.

| ID | | Task | Verified how |
|---|---|---|---|
| 11.1 | `[~]` | **A1 · Rebirth left the player standing in the old zone.** The save was always correct — `RebirthService` resets `StageIndex`, `UnlockedZones = {"Forest"}` and `CurrentZone`, and `IsZoneUnlocked` reads exactly those. The **body** never moved: `OnReturnHome` called `ZoneService.ReturnToCurrentZone`, which returns early on `zoneKey == "Forest"` because the game's one `SpawnLocation` is already there — and rebirth had set `CurrentZone = "Forest"` *before* asking. So the guard fired on the one path that needed the teleport most, and a rebirther was left at stage 1 on ground whose creatures hit for x8.4. New `ZoneService.SendToZoneSpawn(player, zoneKey)` with no Forest branch, through the same `travel()` handshake; `ReturnToCurrentZone` untouched so respawn behaves as before | **live in Play, with the old failure reproduced first.** The body was sent to Quantum Realm (X = **20,900**, exactly that zone's offset); `CurrentZone` was then set to `"Forest"` the way a rebirth sets it and the OLD call, `ReturnToCurrentZone`, was made — **the body did not move** (X still 20,900), which is the bug. `SendToZoneSpawn(player, "Forest")` from the same state landed it at **X = 0.0**, Forest's offset exactly. Run against a fixture save in a freshly required `PlayerDataService`, so no DataStore was touched. **Owed: one real rebirth end-to-end** — it can only be done on a real save, and it costs whoever runs it their progress |
| 11.2 | `[x]` | <!-- verified live 2026-08-12 --> **A2 · Daily rewards and the Season Pass never call out to the player.** Three separate holes: no auto-open or toast for an unclaimed daily (the `dailyReward` toast fires *after* the claim — a receipt, not an invitation); `hudRefs.showSeasonPanel` is defined at `MainUI:5807` and **never called**; the Season tile passes no `badge`. One new client IIFE on the first `DataUpdate` after join. Server unchanged — `RewardService.GetStatus` and `SeasonPassService` already compute all of it | **the Season half is proven live, in both directions.** On a fresh join with 3 things waiting the card **opened by itself** carrying the Season row (`🏆 Season Pass — 3 to claim`) and the tile badge read **`3`** — the two agree because both are the number `refresh` last wrote. Kristina then claimed all three mid-session; the next join drew **no card** and a hidden badge reading `0`, and that zero was **independently recomputed from the raw DataStore save**: level 2 with `claimedFree = {1,2}` leaves no level, `d_creatures` 50/50 and `d_bosses` 3/3 are now `claimed`, and the weekly that looks close is `w_creatures` **321 of 500**. The earlier `3` reconciles exactly with those same three. **Owed: the DAILY row has never drawn** — `LastRewardClaim` was today's on every run (control run from the save: `dayNumber(now) == dayNumber(last)`, so hiding it was correct behaviour and not a silent failure). It needs the next rollover or a temporary rewind of that one field. **CLOSED 2026-08-12 — the DAILY row is now proven in all three of its branches, and it needed neither.** The readiness test is `dayNumber(os.time()) > dayNumber(data.LastRewardClaim)` computed **on the client**, off the payload, so a synthetic `DataUpdate` reaches it without touching the save at all. The only obstacle is that `maybeWelcomeBack` runs once, on the payload where `currentData == nil` — so the HUD is torn down and a **fresh clone of MainUI** is parented into `PlayerScripts`, which resets both that flag and the block's own `shown` one-shot, while a 0.05 s payload loop on the server guarantees the first thing the new HUD sees is the probe's. Measured: continuing → `🎁 Daily reward — Day 5 is ready` / `🔥 4 day streak — claim to keep it going`; missed a day → `Day 1 is ready` / `💔 Your streak ended`; never claimed → `Day 1 is ready` / `Claim it to start a streak`. The middle one was **wrong before this session** — see 11.28 |
| 11.3 | `[x]` | <!-- verified live 2026-08-11 --> **A3 · Hatch and Auto Hatch buttons overlap.** Measured, not estimated: in a 470-wide `EggPanel` both are `0.48` (225.6 px), one from x=18, one anchored right at 452 — **17.2 px of overlap**, visually ~27 because `styleCard`'s `UIStroke` draws 5 px outside the frame. Fix is a `rowFrame` with a horizontal `UIListLayout`, so the widths stop being hand arithmetic. Plus the requested **global button shrink** through `styleButton` (~25 of ~30 action buttons) mirrored into `UITheme.Button`: 46/50 → **40/44**. **The overlapping pair is Hatch and Hatch x10**, not Hatch and Auto Hatch as the report reads it — Auto Hatch is on its own line (measured `y=488 h=34`) and never touched anything | **measured live, before and after, on the running HUD.** Before: the two frames overlapped by exactly **17.20 px**, the report's own figure to the decimal. After: `ActionRow` with a horizontal `UIListLayout`, frame gap **24.00**, row `434.0 == 205 + 24 + 205` exactly, both **44** tall filling the row. **The first fix was not enough and the row was reopened to fix it**: at the authored padding of 12 the *visible* gap was **2.00 px**, because each `UIStroke` is 5 px and draws OUTSIDE its frame, so the pair still read as one merged bar — **a gap of N between two stroked siblings shows as N − 2×thickness**. Padding 24 gives **14.00 px** of daylight. The shrink: **50 → 0 and 46 → 0**, landing as 40 = **83** (17 pre-existing + 66 converted, exact) and 44 = 2 (EvolveButton + 1 pre-existing; Hatch and HatchBulk left the offset tally because they now fill the row on `Y.Scale`). **69 buttons moved, not the ~25 the row estimated** — and a control confirmed every one is a lone action button inside its own row card, with `EggPanel` the single parent holding hand-positioned siblings, i.e. the one being converted. `TextFits` **true on all 98** button labels across every tab |
| 11.4 | `[x]` | <!-- verified live 2026-08-13 (seventh) --> **A4 · Skins glitch — four causes, and one of them was diagnostics.** **R1** `dress()` had no generation token: it sleeps up to 2 s in `waitForBodySettled` and its only guard was "same character", so two equips inside that window raced and the **older** one could land last — with the evolve path's `task.delay(0.7)` giving stale data a head start. Now a monotonic `DressGeneration` attribute on the character, plus the worn skin re-read from the save *inside* `dress`. **R2** `SkinMesh` welds with `host.CFrame:Inverse() * part.CFrame` — world CFrames — while the settle wait only watched *size*, so dressing mid-stride welded the arms into that stride forever; the wait now also requires `MoveDirection == 0` and a non-airborne state. **Measuring R2 is what showed that half of it was not enough, and it is now three conditions rather than two:** the input stops instantly and the limbs do not — the arms are **59.7°** from rest 0.02 s after `MoveDirection` reaches zero and only reach the idle animation's own 2.7° at **~0.28 s** — so a gate on the input alone released the dress at the top of that curve and the weld set came out **45.6°** off the standing baseline against 44.5° for no wait at all. The wait now also watches the four limbs' pose relative to the root, and the threshold is measured rather than chosen: per-frame limb movement is ≤ **0.125°** standing (breathing, which is why it cannot be the size probe's equality test), **1.12°** walking, and over **4°** through the blend-out, so `POSE_EPS = 0.5` sits 4x over the idle ceiling and 8x under what it must catch. **R3** two `setBodyHidden` implementations wrote two different attributes (`SkinBaseTransparency` / `StageBaseTransparency`), neither ever cleared, so each could record the other's hidden `1` as the original — a permanently invisible player, held off only by the order inside `Clear`. One name (`BodyBaseTransparency`), cleared on restore. **R4** `att`'s infinite spin tweens were never cancelled; a destroyed weld does not stop a Tween, so every rebuild leaked its spinning parts. **Plus the missing half:** the whole skin path had **one** `warn` in it, and five silent `return`s produced exactly the signature in `src/STATUS.md` — stock avatar, zero costume parts, zero errors. Every one of them now says what it did | **R1 proven live, in both directions.** Two `ApplyStage` calls 0.1 s apart — well inside the 2 s settle window — with different skins: `DressGeneration` went **1 → 3** and the body ended up wearing **B**; run again with the order reversed it ended up wearing **A**, which rules out "the later one wins by luck". The real skin was restored afterwards. **R3 proven on the running character**: 15 hidden limbs all carry the single `BodyBaseTransparency`, and **zero** instances anywhere on the body still carry either old attribute name. All 59 scripts compile; `GameConfig` / `SkinMesh` / `StageCostume` load clean. **R2 and R4 are now measured live too, both in both directions.** **R2's release condition, four ways, on the real body:** standing **0.017 s** (2 frames); called while running and the player stops at 0.834 s → dressed at **1.118 s**, i.e. **0.284 s after the stop**, the blend-out exactly; called mid-jump → landed at 0.466 s, dressed at **0.717 s**, 0.251 s after landing; **walking and never stopping → 1.984 s**, the 2 s timeout doing what it is there for, with all 120 frames moving. **R2's payoff, as weld C0 against a standing baseline** (which is the thing a weld freezes — `host:Inverse() * part` cancels a rigid move or turn of the whole body, so only the limb's pose on the body can move it): noise floor between two standing dresses **0.04° / 0.006 studs**; dressed mid-stride with no wait **56.6° / 3.78 studs**; **dressed after the stop 2.37° / 0.245 studs**, and after landing a jump **0.17°**. The timeout path stays bent at 53.4° and is meant to. **R4:** a live stage-13 costume has 58 welds; destroy the folder the way `Clear` used to, with no cancel, and the welds are **orphaned but still being written to** — 174 captured over three rebuilds, every one parentless, its C0 still turning **6.19° per half second**. The same three rebuilds through `Apply → Clear → cancelSpins`: 58 captured, all 58 orphaned, **0 moving, 0.000°**. **Found while measuring R4 and left for Kristina:** only **one of the four** spins `BUILD[13]` registers actually animates — `CFrame.Angles(0, 0, math.pi * 2)` is exactly the identity (measured 0.000°), so the clock's hour and minute hands never turn, and a negative `seconds` (the left gear's `-5`, and `BUILD[17]`'s middle chrono ring at `-10`) builds a negative-duration `TweenInfo` that snaps to its goal on the first frame and stops — measured 60.0° reached instantly. The intent was "turn the other way", which is a negative **angle**, not a negative duration |
| 11.5 | `[x]` | <!-- verified live 2026-08-12 --> **B1 · Luck splits into pet luck and everything else.** `GetLuckPercent` was the one sum and the shop `Upgrades.Luck` entered it at `x2`/level, feeding five consumers (crit DNA, mutation, egg roll, mystery potion, wheel) — so one purchase quietly moved five unrelated things, the card named the two it moved least, and no number was safe to raise: anything big enough to be felt on an egg was a crit-chance clamp on the DNA click. The upgrade leaves that sum; new `GetPetLuckPercent(data)` = `GetLuckPercent + Upgrades.Luck * GameConfig.PetLuckPerUpgradeLevel`, with **exactly two readers** — `PetService.rollAndInsert` (what you get) and the egg panel's odds table (what you were promised), which is why neither computes it itself. Upgrade strengthens +2 → **+5**/level, `displayName` "Luck" → **"Egg Luck"**, description rewritten. **The cap is the thing the row did not know**: `GetUpgradeMaxLevel` is 5 levels per unlocked zone, so this is +25 at one zone and **+500** at twenty | **live on the shipped client, driven by a real `DataUpdate` payload with only `Upgrades.Luck` differing.** Egg panel: `🍀 0% luck` → **`🍀 50% luck`** at level 10 (exactly +5/level) and the Forest basic odds moved with it — Common **62.8 → 50.0**, Epic **2.6 → 4.1**. The odds table and the roll agree: 60k real `RollPetForEgg` draws came back 38.84/43.91/15.68/1.57 against the panel's 38.67/43.87/15.83/1.63. **The negative half has a control, so "unchanged" means something**: the shared total is flat at **0.00** at upgrade levels 0/1/5/10/25 (crit chance `clamp(5+luck*0.5,0,75)` = 5.00 at every one), and 60k draws each of `RollMutation`, `RollMysteryPotion` and `RollSpin` are identical at level 0 vs 25 — while the same three at a forced luck 125 move hard (mutation Common 61.1 → 44.5, Secret 0.25 → 0.76). Exactly **one** live read of `Upgrades.Luck` remains in the repo and it is inside `GetPetLuckPercent`. Card renders `Egg Luck` with `TextFits` true; the cap message still fires above it. **No saturation at the cap**: on the endgame egg (+272 own bonus) 100 levels is luck 772 and Legendary only 2.1% → 2.5%, so the raise is felt by a new player and is nearly free at the top |
| 11.6 | `[x]` | <!-- verified live 2026-08-12; layer-2 payout measured and closed 2026-08-13 (sixth) --> **B2 · Terrace creeps behind a rebirth wall.** The creeps "up on the sides" already exist — raised Brutes and Elites, 4+6 per zone, the `raised` flag already threaded through respawn and already paying shards. **Nothing in the codebase gates on `data.Rebirths`** (5 reads, none a lock), so this is a new system. **[decision] Two layers:** existing terraces at `Rebirths >= 1` (stronger DNA, shards, small chance of a pet from the zone pool); new higher points at `Rebirths >= 3` (much stronger DNA, **exclusive pets in no egg**). Pets from kills are a new path — `PetService.GrantPetFromDrop` **reusing `rollAndInsert`** so the roll and the 100-pet cap cannot drift. Exclusive species cost no assets (`PetModel.Build` is procedural) and enter `GameConfig.Pets` but **not** `PetsByZone`, so `RollPetForEgg` cannot reach them. **[decision] A new creep tier per rebirth**, not a new pet. Locking is per-player against a shared creep, so it follows `RebirthShrineClient`: the client greys and delists locally, the server refuses independently. **BUILT AS SPECIFIED WITH THREE DELIBERATE DEPARTURES.** (a) `raised` became the LAYER NUMBER (1 or 2, nil on the floor) rather than gaining a second parameter — it is already threaded through the respawn and one thing threaded correctly beats two threaded nearly correctly; every existing `if raised` keeps its meaning. (b) `GrantPetFromDrop` does **not** reuse `rollAndInsert`: two of that function's three lines are wrong for a kill — it adds an egg's `luckBonus` when there is no egg, and it rolls against `GetPetLuckPercent`, which since 11.5 includes an upgrade *called Egg Luck* whose card promises "rarer pets from every hatch". A kill is not a hatch. What the row wanted protected is held instead by a new `insertPet`, now the only place in the game a pet is created, and by the one `MAX_PETS`. (c) The new tier is **one** Apex tier at `Rebirths >= 3`, not one per rebirth, which is what the row's own "two layers" decision describes. **The trap this row walks straight into is 11.9**: a new, stronger creep can out-last its zone's boss again. `ApexBaseHealth` is therefore `math.min(350, BossEliteFloor * EliteBaseHealth)` — algebraically the exact condition for a farmed Apex to stay inside the boss floor, with the generation cap and `mobHealthMult` cancelling from both sides, so it cannot go stale when either moves | **measured live on the published place, and on Kristina's own save.** Spawning: **80 Apexes, 4 per zone**, on the highest shelves — Apex ≥ Elite ≥ Brute altitude in **20 of 20 zones**, and one Apex sampled at y = 92.6 with `Health=350 Raised=2 MinRebirths=3`. Gate: 12 real `AutoAttack` fires at an Apex moved its health **3850 → 3850** with the notice `🪐 Core of Suns is sealed -- it takes 3 rebirths to touch it`; a client pushed a payload claiming 3 rebirths painted itself unlocked and the server **still refused**, which is the split working. Payout on real kills in Forest: raised Brute **7.599e6** DNA against a valley Brute's non-crit **2.533e6** = **3.000x** exactly (two of three valley samples came back 5x — the crit — which is also why the first reading looked like 0.60), XP **10 → 20 = 2.00x**. Exclusivity is structural: **20,040 real egg rolls across all 60 eggs at luck 500 produced 0 exclusives while touching all 100 eggable species**, and 20,000 more down the malformed-egg fallback produced 0. Drop rates over 60k calls: **1.98%** (target 2) and **4.93%** (target 5); a full 100-pet bag refuses with `"full"` and the bag stays at 100. Boss invariant re-measured across 20 zones: worst boss / farmed Apex **1.00**, worst / fresh Apex **2.00**, and no boss's health moved. Plate: locked reads `🔒 🪐 Core of Suns — 3 rebirths` with 48/48 parts in Slate, unlocks to `🪐 Core of Suns` with **0** parts still carrying a lock-original, and re-locks — with exactly **one** padlock each way. MainUI registers **179 → 179**. ~~Owed: the layer-2 payout (x12 DNA, x5 XP) and an Apex kill have never been run~~ — **the Apex kill was paid by 11.31 (28 real kills), and the layer-2 payout is now measured, 2026-08-13 (sixth).** **11 real `AutoAttack` kills in Galaxy** (`mobDnaMult` 12.5, `mobXpMult` 13.867), every kill's DNA normalised by the player's own *non-crit* click amount sampled on the frame before it, so a rank-up mid-run cannot distort a ratio. Non-crit DNA per kill: valley Elite **425.00** = 34 × 12.5 × **1**, raised Elite **1275.00** = 34 × 12.5 × **3.000**, Apex **8250.00** = 55 × 12.5 × **12.000** — three separate Apex kills all landing on 8250.00 exactly, and Apex / valley Elite = **19.412** = (55 × 12)/34. XP carries no crit and needed no averaging: valley Elite **388** = 194 × 1 × 2, raised Elite **776** = **2.00x**, Apex **4160** = 416 × **5.00** × 2 — the layer-2 XP multiplier read off the *first* kill. The crit is the same ×5 that made 11.6's first reading look like 0.60 and it showed up in 3 of the 11 rows (41250, 6375, 2125 = exactly 5 × 8250, 1275, 425), which is why the minimum rather than the mean is the measurement. Method: the three-rebirth gate was passed the way 11.31 passed it — `Rebirths` granted **in memory only** by a temporary `Script` in `ServerScriptService` (the real server VM, so its `require` returns the modules the game is actually using; an `execute_luau` require hands back a fresh module with an empty cache), talking to the driving client over two StringValues. **Restored and verified in the DataStore afterwards: `Rebirths` back to 2**, `StageIndex` 13 unmoved, Kills +11, Diamonds +8, Shards +3; probe script and both StringValues deleted |
| 11.7 | `[x]` | <!-- verified live 2026-08-12 --> **B3 · Fusion, Rainbow Catalyst, Boss Revive.** **[decision]** fusion 4 → **3** copies (Rainbow 9, Celestial 27 — reachable against the new 100 cap); Catalyst 99/249 → **49/129 R$** and its card **moves out of the Robux grid into the fusion panel** (product id untouched); **Boss Revive is removed**. ⚠️ **The one item here that can take money and give nothing back:** Roblox retries `ProcessReceipt` forever until it is acknowledged, so the receipt branch **stays** and converts an in-flight purchase into diamonds. Only the product listing and the revive UI go. **THE CATALYST WAS ALREADY HALF IN THE FUSION PANEL and the row did not know**: every pet row there carries a `CatalystRow` R$ button, which is the single catalyst's real storefront — and that button printed a **hardcoded `"R$ 99"`**, so the reprice alone would have made it advertise one number and charge another. So only the **x3 bundle** gets a card of its own (`panelCard`), the single stays on the pet rows, and that button now reads `product.price` like the grid always has. Boss Revive is `delisted` rather than deleted — a deleted row means a retried receipt resolves to nothing, forever — and its grant became `grantDiamonds = 10`, which is exactly what `Diamonds_1` sells for the same 49 R$, so an in-flight buyer is made whole at the shop's own rate. The revive card itself survives for anyone holding a charge and is simply never offered to anyone who is not: the server checks `held > 0` before sending it, and the client's "buy one" arm is gone | **live.** `FuseRequirement` **4 → 3**, so Celestial is 27 copies against a 100 cap instead of 64 — reachable for the first time — and all four in-world fusion signs rebuilt to read **"Bring 3 of the same pet"** (`BUILD_VERSION` 126 → 127, since a sign is baked at build time). Robux grid: **14 cards, no `BossRevive`, no `TierUp_1`, no `TierUp_3`**. Fusion panel: 6 per-pet rows all reading **`R$ 49`** (was the literal 99) and one bundle card `R$ 129` / "3 catalysts — raise 3 pets a tier, no copies needed"; **0** clipped button labels. Product ids all unchanged and verified: `3702254100`, `3702254553`, `3702254989`. **Owner half outstanding: turn the Boss Revive product's sale off on the dashboard, and match the two Catalyst prices there** |
| 11.8 | `[x]` | <!-- verified live 2026-08-12 --> **B4 · Health potions.** **[decision] A fourth kind** beside the three: `GameConfig.PotionKinds` gains `health` and nine potions become twelve, because the loop below builds the size combinations itself — so a size cannot be added to one and forgotten on the other. Effect multiplies `MaxHealth` (which already scales per stage through `EvolutionVisuals.applyMaxHealth`, so it multiplies that rather than inventing its own) and speeds regen while it runs. **It does NOT take `size.mult`** — max health already climbs with the stage, with Stage Mastery and with the worn skin's rank, and a x5 on that product for twenty minutes is a different game; `healthMult` (1.5 / 2 / 2.5) and `regenMult` (3 / 5 / 8) are their own columns on the sizes table, so the numbers can be gentle while the table still refuses to let a new size skip them. **The undo is the same call as the do**: `EvolutionVisuals.RefreshBonuses` recomputes the whole product, and `GetPotionHealthMult` returns 1 once the boost lapses, so nothing has to remember what the bottle added. Expiry is **polled, not scheduled** (Phase 7's rule) — `GetPotionBoost` expires lazily, so a `task.delay` would be lost on restart and never set at all for someone who joined mid-boost | **live.** **12 potions built** from 4 kinds x 3 sizes, no potion hand-written. Real drink through `HandleUsePotion` at stage 8: MaxHealth **383 → 767 = x2.00** exactly, bottle consumed; regeneration measured at **5.8% of max per second** against a base of 1% (the loop's x5 plus Roblox's own ~1%); the boost then expired and MaxHealth went **767 → 383**, back to base. The loop had to be exported as `PotionService.DriveHealthPotions` to be testable at all — a probe cannot reach the live `PlayerDataService.Cache`, so the real loop is started in the probe's own context against a fixture rather than reimplemented in it. **Two probe runs lied first**: measured 1.0%/sec regen and no expiry undo, both because the *live* loop reads the *live* cache and the fixture was in a fresh one — the 1% was Roblox's default humanoid regen wearing my feature's clothes. **And 11.30 fell out of it** — the HUD timer strip was a hardcoded `{"dna","xp","luck"}` |
| 11.9 | `[x]` | <!-- the owed boss fight paid 2026-08-15 (nineteenth session) --> **B5 · Bosses are weaker than the creeps — and it was true in every zone.** The plan's own analysis was out of date (it described hand-typed boss health, which 10.x had already replaced with a derivation), and **the real state was worse than the report**. Boss health is `BossTargetHits × GetZoneReferenceDamage(zone)`, and 60 hits was chosen as "about four Brutes" — correct, but the **Elite** is 280 base, i.e. **56 hits**, so a boss was one Elite. With `generationHealthMult` bringing a farmed spawn back at up to **x2**, an Elite reached 112 hits — twice its own zone's boss. Measured across all twenty zones: boss/Elite **0.84–1.07** fresh and **0.42–0.54** farmed. Fix keeps the derivation (it is what makes a boss the same fight on every rung) and ties it to the creature curve: `BossTargetHits` 60 → **150**, plus a floor of `BossEliteFloor × EliteBaseHealth × CreatureGenerationMax × mobHealthMult`. `EliteBaseHealth` and the generation cap **move into `GameConfig`** and `CreatureService` reads them back — the private copy is what let the two curves drift in the first place | measured live on the pushed code, all 20 zones: **worst boss/farmed-Elite 1.25** (was 0.42), boss/fresh-Elite flat at **2.50** (was 0.84–1.07), and **every boss gained at least 2.50x health** — the "at least double" decision satisfied in every zone. **The owed boss fight was paid 2026-08-15 (nineteenth session), and the row's own claim held twice over.** Re-measured on the **live spawned rigs** rather than on the formula — every one of the 20 bosses standing in the world against the Elite standing in its own zone — boss/Elite is **2.50 in sixteen zones and 2.51–2.68 in the other four** (Forest 2.68, VoidExpanse 2.51, CelestialThrone 2.58, Singularity 2.64, AbsolutePlane 2.68), so nothing drifted between the derivation and what the world actually builds. Then a **real fight against Boss_AbsolutePlane** (zone 20, 789,272 HP), driven the 10.10 way — real `TeleportToZone`, walked into range on the Humanoid rather than teleported (a raw CFrame set under streaming is silently undone, measured twice), real `AutoAttack:FireServer` at the shipped `AUTO_INTERVAL` of 0.34 s. It died, `Notify` carried `bossDefeated`, the model left the folder and came back **26 s** later at full health. **It died on the first swing**, which is 14.1 |
| 11.10 | `[x]` | **B6 · Pet cap, sorting and the "5/3" counter.** <!-- verified live 2026-08-11 --> Three separate one-line defects. (a) `MaxOwnedPets` 30 → **100**: 30 put Celestial (27 copies at the new fuse requirement) out of reach of an inventory that also has to hold a collection. Raising is safe for every existing save — `PlayerDataService`'s trim only fires on `#Pets > cap`, true for nobody after a raise, and the `PetsTrimmedAt = 30` stamp simply never matches again. (b) `SortedPetsByPower(data.Pets)` was called **without `data`**, so the drawn order dropped the zone axis and quoted every pet at its home zone's strength — a zone-matched Epic drawn beneath a Forest Legendary it beats four times over, while both server callers passed `data`. (c) The panel title read `Pets (%d/%d equipped)` against the raw `MaxEquippedPets` constant, ignoring the diamond slots and the pass — hence "5/3", a fraction that reads as a broken save. **[decision] The title is just `Pets`**; the capsule below already prints the pair correctly | **live in Play.** The HUD's own capsules read **`7/100`** (the new cap) and **`6/6`** (slots counted through `GetMaxEquippedPets`, no more "5/3"); the panel title is the literal **`Pets`** with `TextFits = true` and it is the only such label in the tree. Sorting checked on a rank-100 fixture holding pets from Forest and the Antimatter Zone: the shipped order is **0 pairs out of order** in real `GetPetPower(pet, data)`, while the old dataless order has **1** — a Forest Epic (0.121) drawn above the Antimatter Epic (0.210) that beats it, which is the defect exactly |
| 11.11 | `[x]` | <!-- verified live 2026-08-12 --> **B7 · Diamond upgrades are too cheap for what they give.** `MegaIncome` base 5 / mult 1.6 for **+10% permanent income per level** with no level cap, since 10.x made kills the one gameplay diamond source. Raise the bases and the multipliers; `PetSlot` keeps its `maxLevel = 3`. **Shipped as prices only** — no grant, no cap and no call site changed: 5 → **25**, 8 → **40**, 15 → **75**, with the multipliers 1.6 → **1.75** (2.2 → **2.5** on the slot). The multiplier has to move as well as the base, and that is the part the row did not say: the effect is LINEAR in the level while the price is geometric, so the multiplier is the only term that decides where the upgrade stops being worth buying — raising the base alone shifts the ladder sideways and leaves the tenth level at 12x the first. Stage Mastery is deliberately **not** repriced beside it: it is twenty one-shot buys each gated on reaching its stage, so its ceiling is the climb, not the wallet. Two stale comments citing "5 / 8 / 15" (`GameConfig`, `RobuxShopService`) moved with it | **measured live, then verified live.** Income first, because the row asks for the cost against a rate: driving the real `AutoAttack` remote at the client's own 0.34 s cadence in Galaxy and reading the diamond balance off the real `DataUpdate`, **roaming the valley pays 13 diamonds in 180 s (254 kills, 85/min) = ~260/hour**, and **parking in the densest cluster and letting the respawns come pays 4 in 176 s = ~82/hour** with 74% of the swing budget idle. The roaming total is not a lucky sample — its own tier mix (177/59/16/2) predicts **12.05** against `DiamondDropChance`, so the source and the table agree. Priced against **120/hour**, near the bottom of that band. Cumulative first 10 levels, before → after: MegaIncome **903 → 8,942** (7.5 h → 74.5 h), MegaLuck **1,447 → 14,310**, PetSlot all 3 **120 → 730** (1.0 h → 6.1 h). Then on the shipped client: cards drew **💎 25 / 💎 40 / 💎 75** at level 0, two REAL purchases through `BuyDiamondUpgrade` charged **exactly 25 and 40** (114 → 89 → 49) and advanced both to level 1, the cards redrew **43 / 70**, and the refusal branch held — `PetSlot` at 75 against a 49 balance left the balance **unchanged** and returned `Not enough Diamonds!`. **Two probe runs were discarded rather than reported**: a walking navigator that spent 158 s of 173 chasing creatures it could not reach measures my pathfinding, not the game |
| 11.12 | `[~]` | <!-- ids created and wired 2026-08-12; the purchase itself is the standing owner block --> **B8 · Shard packs for Robux.** Shards have one source (raised creeps) and one sink (the wheel at 25). A pack joins `RobuxProducts` modelled on the diamond tiers, which are **deliberately unscaled** — a shard is a fixed 25-cost item that does not ride the stage curve. ~~BLOCKED on 👤 OWNER~~ — **UNBLOCKED 2026-08-12: Kristina granted browser access and the three products were created on the Creator Dashboard from this session**, against universe `10675543038` with Managed Pricing disabled on each, the same as the other 26. **Three rungs, not five**: the ladder is the Diamond ladder x2.5 (10/22/50/140/300 → 25/55/125/350/750) with 49 / 199 / 999 taken from it, because a shard is spent 25 at a time on one machine and three points already cover "one go", "an evening" and "stop thinking about it". Unscaled for a *stronger* reason than diamonds: a shard buys exactly one thing at a flat 25, so `ScaleReward` would sell a late-stage buyer thousands of spins from one tile. `grantShards` had to be added to `GetValuePerRobux` too — a grant field missing from that list makes its whole tier group silently ribbon-less, which reads as "no bonus" rather than "not implemented" | **live.** `Shards_1` **3707419817** / 49, `Shards_2` **3707425807** / 199, `Shards_3` **3707431292** / 999 — all three resolve through `GetProductInfo` with the dashboard's name, price and `IsForSale` matching `GameConfig` exactly. 20 products, **20 distinct ids, no duplicate and no `productId = 0`**, which is what `getProductByPurchaseId` scans. Value per Robux rises monotonically **0.5102 → 0.6281 → 0.7508**, so the derived ribbons read **+0% / +23% / BEST VALUE** and the ladder is a discount rather than a bigger bill. On the shipped client: three Sunny cards (deliberately not the Diamond tiles' SkyBlue — one buys permanent upgrades, the other buys spins), correct names, `R$ 49 / 199 / 999`, **0 clipped labels in the panel**. **Owed: the grant itself.** `ProcessReceipt` is a Roblox *callback member* — it can be assigned but **not read**, so the live handler cannot be invoked from a probe, and `require` would hand back a fresh service whose cache is empty. It needs the same **one real purchase** that 1.7 / 2.11 / 3.8 have been waiting on, and it closes with them |
| 11.13 | `[x]` | <!-- verified live 2026-08-12 --> **C1 · The shops look plain.** Accent header with icon and subtitle, even margins, cards modelled on `ui_kits/evolution-lab/RobuxShopModal.jsx`, across Upgrades / Robux / Mastery / fusion. Also: the main shop is the **only** panel in the game that closes by setting `Visible = false` instead of calling `animatePanel`. **Found while closing 11.3:** `makeTab` (`MainUI:4192`) builds the Robux panel's two tabs at `0.5, -6` with hand positioning, i.e. a 12 px frame gap — which is the same 2 px of *visible* space 11.3 had to fix, because each stroke draws 5 px outward. **A gap of N between two stroked siblings shows as N − 2×thickness**; use the `UIListLayout` shape 11.3 settled on rather than repeating the arithmetic. **THE CARDS WERE NEVER THE PROBLEM** — checked before building anything, which is the row's own "check the premise" rule: `RobuxShopModal.jsx` is a cream card with a thick outline and `--shadow-panel`, and that is exactly what `UITheme`'s `applyShell` already draws on every tile in all four panels. What the reference has and the game did not is a **header**: a bare left-aligned TextLabel on the panel's own shell, four times, with side margins of 14 / 16 / 18 / 24 depending on which day the panel was written. So the work is one new `UITheme.PanelHeader` — accent band, drawn icon, title, **subtitle** — plus even margins. The subtitle is the part that earns its place: the Upgrades panel spends **two currencies** in two rows and nothing on it said which was which. New code lives in `UITheme`, not MainUI, for the register reason | **measured live on the shipped HUD, and captured.** All four panels carry a `Header` band (green / green / gold / purple) that is a real shell, not a coloured frame — 4 px outline, gradient, gloss, rounded — each with its 9.9 drawn icon. **Margins: every visible child of all four panels sits at L16 / R16 with ≥14 below, asserted rather than eyeballed.** **Tabs: frame gap 24.00, stroke 5.0, visible daylight 14.00** (was 2.00), and 196 + 196 + 24 = 416 fills the row exactly. **Text: 245 labels across the four panels, 0 clipped** — the sweep found three pre-existing ones the eye had not: the Upgrades level badge was sized for its `"Lv 0"` placeholder while the refresh writes `"Lv 100/100"` (58 → 84 px), the catalyst bundle's subtitle, and my own first Mastery subtitle. **Close: the Upgrades panel now animates out like every other panel** — traced on a real mouse click through the MCP input tool, `V/1.000 → V/0.968 → h/1.000`, i.e. it shrinks while still visible, which the old `Visible = false` could not produce. Two things the captures showed that no measurement would have: the Upgrades panel was **900 px wide for 624 px of content** (now 656, with both rows on one 200 px tile width so they line up), and the top row's value ribbons hang 6 px above their card and were being **clipped by the ScrollingFrame's canvas edge** — the two tiles the player sees first were the only ones cut. MainUI top-level registers **179 → 176** |
| 11.14 | `[x]` | <!-- coded 2026-08-12, live verification owed --> **C2 · The Journal looks plain.** Same rules; the 100-disc grid needs a clear locked state. **The plainness was the TITLE, and it was not even on the panel:** a bare 40 px `TextLabel` at `y = -54`, i.e. fifty-four pixels ABOVE the panel's own top edge, floating on the dim with the discovered count as a second grey label inside at `y = 14`. That is the shape 11.13 replaced on the four shop-side panels, and the Journal is the worst case because it is the widest panel in the game — 968 px of white sheet opening with an unbacked line of text. Now one `UITheme.PanelHeader` in Lavender (the Journal tile's own colour, so the panel and the button that opened it agree), with the count as its SUBTITLE plus the rule the count does not state: *"they unlock in order, so the next one is always the cheapest"*. Margins evened to 16 on all four sides (`16 + 598 + 16 + 322 + 16 = 968` exactly). **The locked disc's colour was a real defect and it is this project's own rule broken:** `tint:Lerp(Color3.fromRGB(18,16,26), 0.72)` is "blend toward a point, then take the result", which pulls every hue toward THAT point's hue as well — at 0.72 only 28% of the character's own colour survives, so a hundred discs converge on one brown-grey, which is exactly what the comment above that line says it exists to avoid. Hue and saturation now come from the character and the VALUE is set outright (`Color3.fromHSV(h, clamp(s*1.15+0.22), 0.27)`), saturation pushed UP because a colour loses apparent chroma as it darkens. **Also recorded, not fixed:** the two `setButtonColor` calls in `refreshCharacterPanel` paint nothing — the disc became a ring, so `SetColor` writes a `BackgroundColor3` nobody can see and a `BaseColor` attribute nothing in the repo reads. Commented in place rather than deleted | **VERIFIED LIVE 2026-08-13.** Header band present at margins 16/16 with a real drawn `ImageLabel` icon whose `IconShadow` sits at z=25 under the icon's z=26; the horizontal arithmetic checks exactly (scroll 305..903 wide 598, Detail 919..1241 wide 322, panel 289..1257 = 968). Subtitle and bar agree with the grid: 101 discs drawn, 54 of the 100 ladder discs unlocked, subtitle `Discovered 54 / 100`, `Fill.Size.X.Scale = 0.5400`. **The locked-colour claim, measured against the old formula on the same 100 tints:** mean per-stage minimum separation 0.0646 -> **0.0935 (1.45x)**, and globally over all 100 discs mean pairwise 0.1163 -> **0.1842 (1.58x)** -- that second number is the row's actual claim (a hundred discs converging on one brown-grey) and it is 58% wider now. Control: the unlocked ring colours score 0.2306 / 0.4155 on the same two measures. **One honest exception:** stage 13's `twk_hourglass` and `twk_epoch` are 0.035 apart, marginally TIGHTER than the old 0.039 -- same hue at nearly the same saturation (h 0.118 / 0.114), and the new formula gives up value as a differentiator. Their unlocked rings are also the closest pair in the grid (0.14 against the 0.23 mean), so it is a source-palette collision rather than the fix |
| 11.15 | `[x]` | <!-- coded 2026-08-12, live verification owed --> **C3 · Better notifications.** ~~Today a 46 px pill with an emoji chip. New: a card with an `IconLibrary` icon, a duration bar, and ordering by importance.~~ **One third of this row was already shipped:** the duration bar exists and has since the toast rebuild — it drains right-to-left along the bottom lip in the toast's own colour. So the row is two things. (a) **The chip carries a drawing.** 9.9 generated 44 icons keyed by emoji and every other surface routes through them; the toast was the last place still showing the raw system emoji, in the one element whose whole job is to say what kind of event this is before a word is read. Through `UITheme.IconSlot`, so an unmapped emoji keeps its glyph — that is the icon layer's design, not a gap in it. Chip 32 → 38, card 46 → 52. (b) **The stack is ranked.** New `UITheme.NotifyRank`, keyed by notify `kind` exactly as `SoundLibrary.NOTIFY_SOUND` is, ranking by *what is lost if it scrolls past*: 3 an answer to something just pressed (`error` — an evicted refusal is indistinguishable from "I clicked and nothing happened"), 2 one-off progress and anything paid for, 1 the default, 0 combat chatter (`crit`, `diamond`, the only two that fire on a timer rather than on a decision). Both the eviction victim and the stack order come from it. **A latent bug had to be fixed first or the icons would have shipped muddy:** `liftChildren` skips children named `Gloss`/`Shadow`, but `iconSlot`'s hard shadow is named `IconShadow` — so it was lifted to exactly the icon's ZIndex, and a tie under `ZIndexBehavior.Sibling` is broken by tree order, where the shadow is the LATER child. The dark silhouette was drawn ON TOP of every icon inside a `styleCard` surface. Fixed by name in `liftChildren`, which reaches every call site rather than only the new one | **VERIFIED LIVE 2026-08-13, with both controls.** 13 real `Notify` payloads fired from the server. (a) **The chip carries a drawing:** 12 of 13 came up `chip=Image(rbxassetid://...)` and the one `TextLabel` was the unmapped target emoji on `questComplete` -- both branches of `IconSlot` observed, and the fallback is the glyph exactly as designed. Card 52, chip 38. (b) **The stack is ranked:** `LayoutOrder` measured -299996 (error, r3) < -199997 (zone, r2) < -99995 (upgrade, r1) < 1 (crit, r0), so higher rank sits higher. Eviction picked the least important OLDEST every time -- with two r1 toasts live, a new r2 evicted the OLDER r1. Six rapid toasts mixing r0 and r2 left **both r2 survivors** and dropped the two oldest r0. The stack returned to **zero children** twice. (c) **Control for the `IconShadow` fix**, run on a real `IconSlot` chip with `lift()` copied verbatim from `MainUI:162`: authored icon z=13 / shadow z=12; **old rule -> 13 / 13, a tie broken by tree order in the shadow's favour**; new rule -> 13 / 12 |
| 11.16 | `[x]` | <!-- coded 2026-08-12, live verification owed --> **C4 · Progress bars everywhere.** ~~`UITheme.ProgressBar` exists and is used in exactly 3 places. Add to the Season level, quest rows, mastery, the rebirth ladder and the Journal collection.~~ **The premise was stale twice over: it is used in SEVEN places, and two of the five the row asks for are among them** — the Season level bar (`MainUI:5593`) and the quest rows (`MainUI:5812`) were already done, alongside the evolve bar, two in `CombatClient` and one in `ZoneTransition`. So the row is the remaining three. **Mastery:** the flat gold summary card became the bar's background — same size, position, colour and text, nothing below it moved — with the fill at `owned / 20`. A bar per ROW was the other candidate and is wrong: a mastery row is a two-state thing, and a two-step bar is a tick box drawn the long way. **The Journal collection:** it rides INSIDE the header band (height 68 → 84), which is why it costs the disc grid no height at all; a bar between header and list would have taken a row of discs off screen to restate the subtitle directly above it. **The rebirth ladder:** it measures the CLIMB, not the rungs — `(stage - 1) / (required stage - 1)`, which is 0 the moment a rebirth drops you back to Stage 1 and exactly 1 when the button lights up. `Rebirths / MaxRebirths` was the obvious alternative and is the same mistake as a bar per Journal stage: four rungs is four, and the "0 / 4" printed directly above it already says more. Reads FULL at both `ready` and `done`, because a bar sitting at 90% in either state describes a distance that does not exist. Rebirth panel 392 → 416 to carry it | **VERIFIED LIVE 2026-08-13, both ends and the `done` state.** Five synthetic `DataUpdate` payloads pushed at 0.15 s so they win the race against the real ~3 s one. **Rebirth ladder:** `StageIndex = 1` -> `Fill.Size.X.Scale` **0.0000**, label `Stage 1 / 15`; at the milestone `StageIndex = 15` -> **1.0000**, `Stage 15 - ready`; `Rebirths = MaxRebirths` -> **1.0000**, `Ladder complete`; mid-climb at stage 11 -> **0.7143**, which is (11-1)/(15-1) to four places. **Journal:** a save holding exactly 20 ladder characters -> **0.2000** and `Discovered 20 / 100`. **Mastery:** `MasteredStages = {1,2,3,4,5}` against 20 stages -> **0.2500**. Rebirth panel measures 416 px, Journal header 84 |
| 11.17 | `[x]` | <!-- coded 2026-08-12, live verification owed --> **C5 · Multi-delete for pets.** **The server is already done** — `HandleDeletePets` takes a list (10.3). Built client-side as a mode rather than as a second screen. **The action row swaps, it does not grow:** the two action buttons shrink 178 → 146 to make room for a 46 px select toggle, and while selecting they are hidden and one wide red button stands in their place at exactly their combined width (146 + 10 + 146 = 302), so nothing in the row moves by a pixel when the mode changes. The counters stay visible throughout — "how many do I own" is the question that got the player here. **The selection cannot live on the cards, and that is the whole engineering problem:** `refreshPetsPanel` destroys and rebuilds every cell on every `DataUpdate` — roughly every three seconds, and on every kill — so state held on a card is wiped mid-selection by an unrelated creature dying. It lives on `hudRefs` keyed by pet id, the rebuild reads it back, and it is **pruned against `data.Pets` on every refresh** so a pet that left the save by another route (a fusion consuming it, the single-pet ✕, a trade) cannot stay ticked in a set nobody can see while the RELEASE button counts it. **A checkbox click repaints ONE cell, never the grid** — each card builds a real `PetModel` rig, so a hundred pets is roughly three thousand parts, and rebuilding that per tick would make selecting ten pets the most expensive thing in the HUD. Equipped pets get no checkbox and cannot be picked (the server refuses them, and drawn-then-refused teaches the player the UI lies — the same rule the single-pet ✕ already follows). The confirm dialog is now **list-shaped throughout**: `pendingId` → `pendingIds`, the one-pet path builds a list of one, and the many-pet path copies the caller's table rather than referencing the live selection set, which keeps changing behind the dim | **VERIFIED LIVE 2026-08-13 by real mouse clicks on the shipped HUD, with both controls.** Entering select mode swapped the row exactly as authored: `Action1`/`Action2` (146+146) hidden, `Action0` (302) shown reading `SELECT PETS TO RELEASE`, counters untouched. 13 `SelectBox` labels appeared on the 13 unequipped pets and **none on the 6 equipped**. Ticking three read `RELEASE 3` with exactly 3 ticks. **Control 1:** two clicks on EQUIPPED cards left the count at 3 and added no tick -- the refusal is real, not undrawn. **Control 2 (the prune):** one ticked pet removed by another route (the real `DeletePets` remote) self-corrected the button to `RELEASE 2` with 2 ticks on the next refresh. The confirm dialog was list-shaped throughout (`Release 2 Pets?` / `2 selected` / `All 2 will be permanently deleted`); confirming removed **exactly** the two ticked ids, left the unticked duplicate of the same pet in the save, exited the mode and returned the `SelectBox` count to 0. **Deviation from the row's own control:** the single X does not exist in select mode -- the code makes the two exclusive on purpose ("the corner says exactly one thing at a time"), so the prune was exercised through the other route its comment names. Cost: 3 duplicate `Cinder` pets (Common/Normal, +4%) |
| 11.18 | `[x]` | <!-- coded 2026-08-12, live verification owed --> **C6 · The egg screen belongs on the egg.** **[decision] One prompt per egg, "View Eggs", opens the screen; every purchase happens from there.** **It needed no `ZoneBuilder` edit and no `BUILD_VERSION` bump, which the row assumed it would:** `PetService.WireKiosks` already builds prompts at runtime for exactly this reason (it is where the x10 prompt was cloned, with a comment saying ZoneBuilder is 8,000 lines behind a guard that regenerates all twenty zones). So the podium prompt is re-labelled there — `ActionText = "View Eggs"`, `ShopPanel = "eggs"`, `HoldDuration = 0`, `UIOffset` back to centre — and its `Triggered` → `HandleBuyEgg` connection is simply not made. **The x10 world prompt goes with it**, and existing ones are destroyed rather than left orphaned still wired to a purchase; HATCH x10 is a button in the panel, in the row 11.3 rebuilt so the pair stops overlapping — the same overlap, solved once, in the place that can also show what ten eggs cost and what they are likely to contain. Three helpers died with it (`eggDefCost`, `shortDNA`/`DNA_SUFFIX`, `PROMPT_STACK` — thirteen lines of measurement notes for a number nothing multiplies any more). **The panel opens ON THE EGG PRESSED**, not on Basic: the prompt's existing `EggKey` attribute (kept, because Auto Hatch's `autoEggPoints` is built from it) selects the tier, so pressing the Premium podium gives you Premium's odds table. Server-side the purchase path is untouched — `HandleBuyEgg`/`HandleBuyEggBulk` keep every check, and the panel's two buttons fire the same two remotes gated on `nearestEggZone()`. HUD tile deleted, `RIGHT_COUNT` 9 → 8 (`rows = ceil(COUNT/COLS)` is 4 at both, so the column's shape does not change; what goes is the lone ninth tile on a row of its own) | **VERIFIED LIVE 2026-08-13, with both controls.** **60 podiums** across the 20 zones, each carrying **exactly one** `ProximityPrompt` reading `View Eggs`, `HoldDuration = 0`, `UIOffset` centred, `EggKey` intact. **Control A: zero prompts** anywhere in `workspace.Zones` named or labelled Bulk/x10 (67 prompts total: 60 View Eggs, 5 Buy Mystery Potion, 1 Robux Upgrades, 1 Diamond Upgrades). Walking to Nebula's **Premium** podium and pressing E opened the panel on **Premium** -- its tier button highlighted, cost `9.00B` = `NebulaPremiumEgg` -- not on Basic. Buying from the panel took DNA down by exactly **1,000,000,000** (`NebulaBasicEgg`) and delivered a pet (35 -> 36). **Control B:** 259 studs from the nearest podium the button reads `GO TO A PET SHOP`, and pressing both it and HATCH x10 moved DNA by **0** and produced no pet -- `nearestEggZone()` survived. No egg tile on the HUD |
| 11.19 | `[x]` | <!-- verified live 2026-08-13 --> **C7 · A real 10x hatch.** Today: one shake, one crack, one burst and a 74×46 grid of emoji squares on a billboard by the podium. **Built as ten eggs in ONE `ViewportFrame`**, not ten viewports: ten scenes with ten cameras reads as ten framed thumbnails, i.e. a receipt of what you were given, while one scene lets a single camera move carry all ten and lets the eggs occlude and part like objects. **A wreath, not a grid** — nine on an ellipse (rx 6.4, ry 8.2) around one in the middle: the stage is `0.52 x 0.72` on `RelativeYY`, so a 5×2 grid (≈1.9 wider than tall) collapses into a strip across the middle at a quarter size, while the ellipse is 0.78 wide-to-tall, essentially the stage's own shape. **`best` is emphasised structurally with no second card**: it takes the centre slot, 3.4 studs forward, at 1.25× against the ring's 0.82×, inside the ray fan, and opens LAST — so the batch lands on its headline instead of opening with it. All ten shake together and open 70 ms apart, because ten shells giving in one frame is a single flash nobody can read; the ripple also spreads ten `PetModel.Build` calls (~200 parts) across frames instead of hitching one. The camera **rocks ±15° rather than orbiting** — a ring goes edge-on at a quarter turn and stacks ten eggs into a line. **The shell is now shared, which is what fixes `screenBusy`:** `buildScreenShell` owns the lock (one place raises it, `finish` alone drops it), the connection registry, and an unconditional `task.delay(16, finish)` failsafe that does not depend on any sequence code being correct; `screenReveal` was rewritten onto it with identical behaviour. **Two traps it cost:** `payload.best` arrives as a COPY, not as one of the entries in `payload.pets` (a RemoteEvent does not preserve a shared table reference), so the hero is matched by value — identity matching silently gives eleven pets for ten eggs; and `frameCluster` solves against BOTH axes plus half-depth, because `FieldOfView` is the vertical angle and solving from height alone crops a wide layout | **MEASURED LIVE 2026-08-13 -- most of it passes and ONE CHECK FAILS, so this row stays open.** Passing: the figure count runs **10 eggs -> 0 eggs / 10 pets -> final total 0**, converting one at a time roughly 90 ms apart; **exactly one `HatchReveal` ScreenGui** at every sample; the `BlurEffect` count goes 1 -> **2** -> 1 (**Lighting already holds a BlurEffect**, so the claim is a delta of one, not an absolute of one -- a probe asserting "peaks at 1" would report a failure that is not there); a **real single hatch fired 1.5 s into the bulk did not open a second screen and was still delivered** (DNA -500 = `ForestBasicEgg`, pets 46 -> 47), i.e. it degraded to the world path instead of seizing the screen; the bulk charged exactly 10 x 4,500 and delivered exactly 10 pets. Controls: hand-creating a ScreenGui named `HatchReveal`, a `BlurEffect` and a `BulkSlot` model made the counters read 1 / 2 / 1, and removing them restored the baseline. **FAILING -- the eggs leave the frame.** The stage measures 82.5 x 114.2 px at FOV 30; projected across the full sway, slots **4 and 9 reach |ndc.x| = 1.146** and slot **2 reaches |ndc.y| = 1.095** -- their CENTRES, not their corners -- and six of the ten put a corner past 1.0 (worst 1.491). The hero in the middle slot is comfortably inside at 0.449 / 0.792. `frameCluster` solves the framing against the cluster's bounding box at rest and **nothing widens it for the +/-15 degree rock**, so the ring swings out of the viewport it was fitted to. Fix is one of: solve the distance against the rocked extremes, shrink rx 6.4 / ry 8.2, or cut the sway. Control: the same projection with the ellipse radius doubled reports 3.579, so the test can tell inside from outside. **Not resolvable here: the `< 0.05 s` frame-time target.** Max Heartbeat dt during a bulk was 0.1455 s against an **idle control of 0.1299 s** on the same machine with the same probe running -- the ripple adds ~16 ms to the worst frame over a noise floor two and a half times the target -- and `RunService.RenderStepped` never fires at all for a connection made from the MCP sandbox (Heartbeat and Stepped do, at 60 Hz), so the row's literal instrument is unavailable. **THE FRAMING IS REWRITTEN 2026-08-13 AND IS NOT RE-MEASURED — the Studio MCP is not connected this session, so this row stays open.** `frameCluster` no longer solves a formula against the rest pose: it projects every corner of every figure at nine yaw samples across the sway and takes the largest distance any of them demands, which is exact by construction and needs no re-derivation when the ellipse, the sway, the egg size or the slot count moves. It also stops trusting `VP_ASPECT`: the horizontal half-angle now comes from `vp.AbsoluteSize`, the engine's own answer, with the authored 0.52/0.72 kept only as the fallback for the frame before layout has run (hence the single re-solve on the first frame `AbsoluteSize` reports). `math.rad(15)` in the camera loop became `BULK_SWAY`, read by both, so the solve and the motion cannot drift again. Modelled result: worst **corner** ndc **0.900 on x / 0.764 on y** across the whole sway at 0.1° sampling — the fill target exactly — and the distance goes 48.11 → **46.26**, so the eggs come out **3.9% larger** than today rather than smaller. **A DISAGREEMENT THE NEXT SESSION MUST SETTLE, because it decides whether this row was ever failing.** The same projection run against the OLD code does not reproduce the measured numbers: it puts the worst centre at **0.716** and the worst corner at **0.867**, i.e. inside. The layout is not in doubt — the model independently picks out **slots 4 and 9 tying on x** and slot 2 leading on y (the latter only if the focus is left at the origin instead of the bounding-box centre, which is a 0.247-stud shift), the same three the probe named. What differs is the camera: the reported ndc are consistent with a distance of about **29.7 studs**, where the code's own formula gives **48.11**. So the probe and the model agree on where the eggs are and disagree on where the lens is, and only reading the live `cam.CFrame` during a real bulk settles which. **The rewrite is safe under either answer** — it is exact, it is the row's own first-listed fix, and if the true aspect is narrower than the authored constant (the one hypothesis that would make the probe right) reading `AbsoluteSize` corrects for it automatically **SETTLED LIVE 2026-08-13, AND NEITHER SIDE WAS THE SWAY.** The probe and the model were both right about what they measured: on **frame 1** the camera sits at **(0, 20, 20)** looking down 45°, **27.24 studs** from the focus, and slots **4, 9 and 2** put their CENTRES at **1.146 / 1.146 / 1.095** of the half frame — the row's three eggs, exactly. On **frame 2** the loop takes over at the solved **46.26** and never leaves it. `(0, 20, 20)` is not a pose this file chose: it is **the CFrame Roblox gives a new `Camera`**, and `RenderStepped` does not fire until after that frame is drawn, so the camera was only ever written from inside the loop and the first frame of every reveal was rendered from the default. **General rule: a camera driven by a per-frame loop must also be posed once, before the loop, or its first frame is the engine's default.** The single-egg reveal had the same hole and was fixed with it (now 14.56 studs from frame 1, worst corner 0.799 x / 0.611 y). **Measured after the fix, across 181 samples of the full sway: worst corner 0.900 x / 0.764 y, worst centre 0.744 x / 0.613 y, all ten inside** — the modelled figures to three decimals, which is the control that says the projection solve was correct all along |
| 11.20 | `[x]` | <!-- coded 2026-08-12, live verification owed --> **C8 · The Colosseum boss countdown is invisible.** The countdown exists but its board is in the world above the arena entrance — visible only to someone already there, which is backwards. ~~Boss interval back to 30 min~~ — **already 1800 seconds in `GameConfig.EventBoss.intervalSeconds`; that half of the row was stale.** `BossService.driveCountdown` now publishes three attributes on `ReplicatedStorage` (`ArenaBossSeconds`, `ArenaBossLive`, `ArenaBossHealth`) once a second, the no-remote trick 5.7's `GlobalStats` and 7.1's `LiveEvents` already use — a client that joins mid-interval reads the current value for free and there is no handler to answer. **It publishes SECONDS REMAINING, not a timestamp, and that is what makes it immune to the clock problem 7.1 needed `SetEventClock` for:** `eventState.nextSpawn` is `os.clock()`, monotonic time since this server process started and meaningless on any other machine, so publishing it raw would have every client counting down to a moment in its own past. **The publish goes BEFORE the board lookup**, which returns early when the arena has not been built — a HUD strip that silently never appears because a sign is missing in another zone is exactly the failure this row is fixing. Client-side it is a fifth card in the existing boost strip rather than new HUD furniture, so it inherits 10.17's budget, the drop-lowest-first order (inserted between the pass chips and the event card: a pass is permanent, the arena returns every half hour and has its own board, an event runs once a week) and the tile-column clearance for free. `nil` is treated as a real state and draws nothing — `0:00` would announce a boss that is not coming | **VERIFIED LIVE 2026-08-13 through a real spawn, with both states and the `nil` case.** The three attributes publish once a second on `ReplicatedStorage`. **Board vs HUD, to the second:** the world board read `NEXT BOSS IN  1:43` at `ArenaBossSeconds = 103`, while the strip read `2:11` at 131 and `2:06` at 126 -- card, attribute and board agree on every sample across 80 seconds. **Both states:** counting down it draws `Arena Boss` / `1:21` / `The Devourer returns`; at the spawn (`live = true`, `hp = 25,000,000`) it flips to `The Devourer` / `LIVE` / `25.00M - in the Colosseum`. **The `nil` case:** clearing `ArenaBossSeconds` hid the card within ~0.2 s and it drew nothing at all. Card `LayoutOrder` -2 against the event card's -1 and the pass chips' 0. **Not observed:** the LIVE -> countdown return, because the boss was still up when the session ended |
| 11.21 | `[x]` | <!-- coded + pushed + world rebuilt 2026-08-12; unmeasured --> **D1 · The solid-prop whitelist is keyed to names 18 zones do not use.** 10.13 introduced `SOLID_PROPS` in `newPart`; `addGroundLitter` and `addMounds` write `CanCollide = false` and rely on it to put them back. But the biome configs rename them — `LavaRock`, `MoonRock`, `Meteorite`, `VoidGrit`, `GildedStone` (18 of 20), `AshMound`, `DustRidge`, `VoidMound` (17 of 19) — and `SOLID_PROPS.MushroomCap` never matches the real `TerraceShroomCap`. Add the names, **and warn at the end of the build for any `SOLID_PROPS` entry never seen**, or the next biome reintroduces it | the unseen-name warn is silent after the fix; a `Blockcast` sweep hits each renamed prop | **VERIFIED LIVE 2026-08-13.** **52 of the 54 `SOLID_PROPS` names are present in the built world and 100% solid, covering 3,155 parts**; zero names are partly solid; the only two absent are `LampPost` / `LampFoot`, which the source already documents as a guarded fallback. So `auditSolidProps` has nothing to warn about. All eighteen renamed litter names (`LavaRock`, `MoonRock`, `Meteorite`, `VoidGrit`, `GildedStone`, ...) and all eighteen mound names (`Sandbar`, `AshMound`, `DustRidge`, `VoidMound`, ...) collide. **The trap this cost an hour to, and it will cost the next agent the same: half the world is not in `workspace.Zones`.** `ALWAYS_LOADED` parts are reparented into `workspace.WorldShell` at the end of the build, so a scan of `workspace.Zones` alone reports **every mound name, `TerraceTop` and `PoolRim` as ABSENT** -- which reads exactly like "the fix never landed" rather than like the wrong search. Scan `workspace`. `TerraceShroomCap` (2,310 parts) is deliberately left walk-through per the comment above the entry |
| 11.22 | `[x]` | <!-- coded + pushed + world rebuilt 2026-08-12; unmeasured --> **D2 · Solid base, walk-through top.** `boulder()` makes `ValleyRock` solid and `ValleyRockCap` — which sits *on* it — not. Same for `CliffCragMid`/`CliffCragCap`, `addRockRampart`'s `CliffCap`, and `addLandmark`'s `GreatCanopy` / `SpireTip` | `Blockcast` from above stops at the cap, not through it | **VERIFIED LIVE 2026-08-13.** Every cap is now solid like the mass under it: `ValleyRock` 410/410 and `ValleyRockCap` **410/410**; `CliffCrag` 386/386, `CliffCragMid` 386/386 and `CliffCragCap` **386/386**; `addRockRampart`'s `CliffBlock` 792/792 and `CliffCap` **792/792**. `ValleyRockBase` stays non-colliding (0/410), which is correct -- it is the skirt inside the rock. **`GreatCanopy` and `SpireTip` are absent from the world entirely** (as are `SpireBlock` and `FallCurtain`): those `addLandmark` styles are unreachable today, exactly as the comments at `ZoneBuilder:3114` and `:3129` say, so those two edits are correct but unexercised |
| 11.23 | `[x]` | <!-- coded + pushed + world rebuilt 2026-08-12; unmeasured --> **D3 · Rocks buried inside the terraces, both sides solid.** The X wall stands at `cx ± 625` and `TERRAIN_OUTER = 625`, so terrace slabs reach the wall exactly; every `CliffBlock` from `addRockRampart` occupies x ≈ 600–626 against a solid `TerraceTop` at y 66–128. The Z wall is worse — it sweeps `cx ± 617` straight through the terrace belt on both sides. A second source at `ZoneBuilder:8240` (Desert) uses raw `math.random` instead of `scatterPoint`, lands in `[415, 625]`, and those clones are never anchored and never given a `CanCollide` — unlike every other `:Clone()` in the file | `GetPartsInPart` on the `TerraceTop` slabs counts intersecting solid bodies; must fall to zero | **VERIFIED LIVE 2026-08-13, with a control.** Over all **784 `TerraceTop` slabs**, the number of foreign solid bodies with their centre inside a slab is **0** -- no `CliffBlock`, no boulder, nothing. **Control:** the same `GetPartBoundsInBox` query over 120 of those slabs counting EVERY part returns **5,460**, so the query does find things and the zero is a real zero. `CliffJut` is now 0/1432 colliding, which is also the fingerprint proving this world was built from the pushed code |
| 11.24 | `[x]` | <!-- coded + pushed + world rebuilt 2026-08-12; unmeasured --> **D4 · Waterfalls have no reservation.** The file has exactly one keep-out inside a slope and it is only for the stairs (`stairSeg` / `inStairwell`), deliberately computed *before* any prop so every prop can test it. The waterfall's `fz` is chosen ~600 lines later and **nothing tests it**, so `FallSpillway`, `FallHead` and `FallBasin` run full tread depth through crags, boulders, conifers and mushrooms already placed. Fix: choose `fz` on the same pattern as `stairSeg` — before the props, and tested by them. This is also half of D3 | no prop intersects the fall corridor in any of the 20 zones | **VERIFIED LIVE 2026-08-13.** Across **2,090 waterfall parts** in the 20 zones, **no solid non-structural prop has its centre inside a `FallSpillway`, `FallHead`, `FallSheet` or `FallBasin`** -- the corridor is clear. Nine hits survive the filter and all nine are against `FallFoam` / `FallStone` at the FOOT of the drop: eight are the `PoolRim` the fall lands in (the foam sheet lying over the pool's kerb, which is what foam is for) and one is a `ValleyScree` inside a foam sheet in QuantumRealm at (20496, 3.2, -142). Control: the same boxes contain 27,489 parts in total |
| 11.25 | `[x]` | <!-- coded + pushed + world rebuilt 2026-08-12; unmeasured --> **D5 · `FallSheet` cuts through the solid `CliffJut`.** `CliffJut` is the one solid thing in the riser plane and is deliberately sunk into the hill (`innerX-2 … innerX+d-2`); `FallSheet` is 4 wide centred on `innerX - 1.8`, i.e. `innerX-3.8 … innerX+0.2` — **~2.2 studs of overlap**. `FallCurtain` is additionally scaled by `math.max(byH, byW)` — max, not min, so it is deliberately oversized on one axis | the two no longer intersect; the curtain still covers the drop | **VERIFIED LIVE 2026-08-13.** 190 `FallSheet` against 1,432 `CliffJut`: **0 intersecting pairs**, worst penetration 0.00 studs, against the ~2.2 the row measured |
| 11.26 | `[x]` | <!-- coded + pushed + world rebuilt 2026-08-12; unmeasured --> **D6 · `PoolRim` against `PoolStone`, both solid.** The rim is 6 wide at `poolX ± 27` (so `|dx|` 24–30); stones land at `poolX ± random(20,30)` at sizes 7–14, so a 14-stud stone centred at 24 rides over it. `PoolStone` is authored `CanCollide = false` but is in `SOLID_PROPS`, so `newPart` turns it back on — two solid bodies interpenetrating exactly where the player walks up to the water | zero intersections at the pool edge | **VERIFIED LIVE 2026-08-13.** 52 `PoolRim` against 178 `PoolStone`: **0 intersecting pairs**, worst penetration 0.00 studs. `PoolStone` is 178/178 solid, `PoolRim` 52/52 |
| 11.30 | `[x]` | <!-- found and fixed 2026-08-12 --> **E3 · The HUD potion timer strip was a hardcoded list of three kinds.** The whole potion system is built as kind x size precisely so a kind cannot be added in one place and forgotten in another — and then `MainUI:1416` held `local KINDS = { "dna", "xp", "luck" }`, typed out. 11.8's fourth kind therefore reached the config, the shop, the inventory panel, the save and the server, and had **no countdown on the HUD**: a boost the player cannot see running or about to end. The strip and its `LABEL` map are both derived from `GameConfig.PotionKinds` now, so a fifth kind gets a card by existing. The `LABEL[kind] or kind` fallback was the tell — a default that quietly prints a lowercase key is a list that expects to be incomplete | **live, with a real boost pushed to the client**: `healthTimer` exists, is visible, reads **`x2.5 Health`** with a running **`9:47`** clock, while the other three stay hidden. MainUI registers **179 → 179** |
| 11.29 | `[x]` | <!-- found and fixed 2026-08-12 --> **E2 · Two creatures fell off CelestialThrone's shelves, and a "quiet" drop was silent.** Both found by measuring 11.6. (a) The raised roster went 10 → 14 per zone, and `raisedSpots` samples real terrain — **CelestialThrone yields only 12 valid shelves**, so it now stands 4 Apex + 4 Elite + **4** Brute instead of 6. That is the documented "a zone with too few shelves simply gets fewer" path behaving correctly, and it is recorded here rather than fixed because backfilling onto the valley floor is the wrong answer for exactly the reason the code comment gives. It costs that one zone ~0.24 shards a sweep. (b) The pet drop first shipped as `kind = "pet"` with `auto = true`, on the reading that `auto` means "the quiet presentation". **It does not — it means "play the EGG sequence instead of the full-screen one"**, so HatchReveal shook an egg on a podium in the zone's shop, several hundred studs from the terrace, on an egg nobody bought. The drop produced **no visible feedback at all** where the player stood. It has its own `petDrop` kind now, drawn on the player like a fusion | **(a) counted live**: 198 layer-1 creatures against an expected 200, the two missing both in CelestialThrone, whose Brutes number 4. **(b) measured live before and after**: before, firing the real payload produced **0** labels naming the pet anywhere in the PlayerGui; after, `🌳 Sylvan King` over `APEX DROP — EGGS CANNOT HATCH THIS`, and an ordinary drop over `DROPPED` |
| 11.28 | `[x]` | <!-- found and fixed 2026-08-12 --> **E1 · The welcome-back card promised to keep a streak it was about to break.** Found by measuring 11.2's missed-a-day branch, which had never been drawn. The card's *head* deliberately quotes the streak the claim will **produce** — there is a comment over that line calling "Day 6 is ready" followed by a Day 1 payout "the kind of small lie that makes the whole board look broken". The *note* one line below then told exactly that lie: it tested only `streak > 0`, so a player who missed a day read `🎁 Daily reward — Day 1 is ready` over `🔥 4 day streak — claim to keep it going`, when claiming resets the streak to 1. Both lines now ask the same question (`continuing`), and a broken streak is **said out loud** rather than hidden — it is the only thing on the card that asks the player to come back tomorrow | **all three branches measured live on the shipped HUD**, before and after. Before: missed-a-day drew `Day 1 is ready` / `🔥 4 day streak — claim to keep it going`. After: `Day 1 is ready` / `💔 Your streak ended — this one starts a new run`, while the continuing branch is unchanged at `Day 5 is ready` / `🔥 4 day streak` and the never-claimed branch at `Day 1 is ready` / `Claim it to start a streak`. MainUI recompiles (`loadstring` clean) and is byte-identical to `src/` |
| 11.31 | `[x]` | <!-- found and fixed 2026-08-12; the owed Apex kills paid 2026-08-13 (fifth) --> **E4 · The Apex pays no diamonds and no shards — the hardest creature in the game drops less than the Critter beside it.** Found by Monte-Carlo'ing `RollDiamondDrop` for 11.11: 200,000 rolls per tier returned Swarmer 0.0302, Critter 0.0604, Brute 0.1510, Elite 0.4016 and **Apex 0.0000**. Both drop tables are keyed by tier NAME — `DiamondDropChance` has four rows and `ShardDropChance` two — and 11.6 added a fifth tier without adding a row to either, so the creature that stands on the highest shelf behind a three-rebirth gate, has 1.25x an Elite's health and hits back on 95% of blows is worth **zero** in both currencies. This is 11.30 again in a different table: a lookup keyed by a name, silently returning nil for a name nobody added. The Apex's exclusive pet is not a substitute — that is a 5% roll, and the other 95% of the fight pays a rebirth-gated player strictly less than a Swarmer. Fix is two rows above the Elite's — **diamond 0.60 against the Elite's 0.40, shard 0.40 against 0.25** — plus the defence 11.30 asked for, inverted: `GameConfig` cannot read `CreatureService.TIERS` (it is required *by* that file, so it would be a cycle), so **CreatureService hands its own two lists to `GameConfig.AssertTierCoverage` at load** and that warns, by table and by tier name, for anything uncovered. It warns rather than errors on purpose: the thing being guarded against is silence, not a crash, and a missing drop row must never stop a server booting. Only tiers that can actually be *raised* need a shard row, so the check takes two lists, not one | **live, with a control.** 200,000 rolls per tier on the pushed code: Apex diamond **0.6018** against the authored 0.60 and Apex shard **0.3991** against 0.40, every other tier unmoved. The guard: the real lists return **`[]`** and the boot log carries no warning, while an invented sixth tier returns **`[DiamondDropChance.Titan, ShardDropChance.Titan]`** and prints it — so "no warning" means covered rather than not wired. **The credit path itself is proven end to end on real kills**: 169 real raised kills (116 Brute, 53 Elite) through the real `AutoAttack` paid **+40 diamonds against 38.6 expected and +27 shards against 27.17** — the same handler line the Apex goes through, differing now only in having a row. Shelf economy after: a full 3-rebirth sweep is **3.32 shards**, so a 25-shard spin is 7.5 sweeps instead of 15. **Owed: one real Apex kill** — this save has 1 rebirth and the server correctly refuses layer 2, which is the same wall as 11.6's layer-2 payout and 11.1's rebirth; all three close together. **PAID 2026-08-13 (fifth), and with 28 kills rather than one.** The gate was passed by granting the rebirth count **in memory only**, on the owner's explicit decision, and restoring it after — the kill, the damage, the death branch, the drop roll and the credit are all the real server's; the only synthetic value is the number the gate compares. First kill, watched on its own: `🪐 Core of Suns`, 3,850 HP, dead in **3 swings**, **+1 diamond and +1 shard**, and **no "sealed" notice**, which is the gate itself confirming `CanFightRaised` passes at 3 rebirths. Then 27 more through the same real `AutoAttack` remote. **Save delta over the whole session: Kills +28, Diamonds +20, Shards +7** against 16.8 and 11.2 expected at the authored 0.60 / 0.40 — diamonds +1.1σ high, shards −1.6σ low, both ordinary noise at n=28 and both consistent with the 200,000-roll Monte-Carlo on the same pushed code (0.6018 / 0.3991). **The point is not the rate, which was already measured — it is that a tier that paid ZERO of both now pays both through the live handler.** Save restored and verified in the DataStore afterwards: `Rebirths` back to **2**, nothing else touched. (`StageIndex` went 12 → 13 on its own — real XP from real kills, kept.) |
| 11.32 | `[x]` | <!-- found 2026-08-12 while building 11.17; coded 2026-08-13, measured 2026-08-13 (fifth) --> **E5 · The Pets panel rebuilds every rig on every `DataUpdate`, open or not.** `refreshPetsPanel` guards only on `not currentData` — it does not ask whether the panel is visible — and its body destroys every cell and rebuilds each one with a real `PetModel.Build`. A push arrives roughly every three seconds and on every kill, so a player with a full bag is reconstructing on the order of **three thousand parts several times a minute**, most of it while the panel is shut. (The RenderStepped turntable beside it *does* check `petsPanel.Visible`, which is what makes the omission look deliberate rather than considered.) Raising `MaxOwnedPets` 30 → 100 in 11.10 tripled the cost without anything flagging it. Found while building 11.17, which is why that row repaints a single cell on a checkbox click instead of calling this. **Not fixed here, because the obvious fix is wrong on its own:** skipping the refresh while hidden means the panel opens stale, so it needs a dirty flag refreshed on open — and the honest version rebuilds only the cells whose pet actually changed, which is a different piece of work from a one-line guard. **FIXED 2026-08-13, AND THE DIRTY FLAG TURNED OUT TO BE UNNECESSARY.** `refreshPetsPanel` returns early on `not petsPanel.Visible`, and the thing that keeps the panel from opening stale is a `GetPropertyChangedSignal("Visible")` connection that rebuilds it the moment it opens — off whatever `currentData` holds by then, which is strictly fresher than a flag would have replayed. Hung on the PROPERTY rather than on the open handlers because there are three ways in (the HUD button, the tab strip, `toggleOnly` from elsewhere) and a fourth would silently open stale. Checked before gating: **everything the function writes is parented inside `petsPanel`** — the title, both counter capsules, the empty label, the grid, `petsScroll.CanvasSize` — so a closed panel owes the rest of the HUD nothing. The selection prune is safe to defer for the same reason: RELEASE lives inside the panel, so it cannot be pressed without the open having pruned first. **No new top-level local**, so MainUI's 200-register cap is untouched (`luanames` unchanged at 2 for the file, 13 across the repo). The honest per-cell diff is still NOT built — this is the guard the row asked for, not the rebuild-only-what-changed version | measure the part count and frame time across ten `DataUpdate`s with the panel shut, before and after; the control is the same measurement with it OPEN, which must not improve. **measured live on the cloud place 2026-08-13 (fifth), before and after, with the control.** Counted at the panel itself rather than inferred: a `DescendantAdded` counter on `PetsScroll` counts every instance the rebuild creates, a `ChildAdded` counter counts cells, and a `RenderStepped` sampler takes frame times. Real save, **36 pets** — one rebuild is **2,325 instances / 1,042 parts / 36 rows**, so ~29 parts a pet, which puts a full 100-pet bag at ~2,900 and corroborates the row's ~3,000 estimate arithmetically. Same protocol all three runs (reset counters → 10 `PushToClient` at 0.3 s → read), and each window caught **15** pushes, not 10 — the server's own ~3 s cadence adds 5, which is the row's point restated. **Before, panel SHUT: 34,875 instances, 540 rows, worst frame 209.44 ms.** **After, panel SHUT: 0 instances, 0 rows, worst frame 77.25 ms** — not reduced, *eliminated*. **Control, panel OPEN: 34,875 instances, 540 rows, worst frame 143.29 ms — identical to the before figure**, so the guard removed exactly the hidden work and none of the visible work. 34,875 / 15 = **2,325 exactly**, matching the single measured rebuild, which is what says the counter is counting rebuilds and not something else. **And the shut panel was already full before a single push was sent** (`scrollDesc` = 2,326 with `Visible` = false): the unguarded build had happened on the payload that arrived while the panel was closed, which is the bug in one number. **The open-stale worry is disproven directly**: flipping `Visible` to true built 36 rows / 2,325 instances immediately, so the `GetPropertyChangedSignal` pair does its job. The before-run was taken by commenting the guard out in Studio and restored in the same session — MainUI is back to **380,324 / 144286258**, byte-identical to `src/`, and `loadstring`s clean |
| 11.33 | `[x]` | <!-- raised by Kristina at the end of the seventh session; coded and measured live 2026-08-13 (eighth) --> **F1 · Nothing on the TIME WALKER costume ever moved, and the same two mistakes are in CHRONOS BEING a hundred lines away.** **[decision]** the clock reads as a real clock: **clockwise, true 12:1, one minute-hand revolution every 8 s**. Both defects fail in silence. (a) A full turn was written `spin = { 0, 0, math.pi * 2, n }` and `CFrame.Angles(0, 0, 2π)` **is the identity**, so the tween's goal equalled its start; overshooting is no fix either, because a CFrame tween takes the SHORT way round and a 4π/3 goal runs *backwards* by 2π/3. A revolution is therefore walked in **thirds**, each third its own tween starting where the last landed — with `symmetry` as the cheaper path for an arrangement that repeats every 2π/n (six gear teeth, fourteen halo beads), where one gap is under a half turn and a single repeating tween is exact. (b) The left gear asked for the other direction with a **negative duration** — `beadRing`'s sign convention arriving at a consumer that never implemented it; the sign is read as direction now, never handed to `TweenInfo`. **A third defect only measurement could find: a CFrame tween slerps the rotation but LERPS THE POSITION**, so a piece carried by `pivot * R * rel` crosses the chord instead of riding the arc and collapses to cos(half the step) from its pivot. What turns is now an empty **hub** pinned at the pivot whose own `C0` is `pivot * R` — same position at every angle, so only the slerp is left — and the pieces hang off it, one hub per (host, pivot, period) group, which also keeps six teeth in lockstep. Two things stop turning on purpose: a smooth cylinder is a solid of revolution, so the gear **disc** and the chrono **rings** spinning about their own axis were the same picture forever — the teeth carry the gear, and each ring precesses about the torso's vertical instead (the flat one gains a 16° tilt, or precession is invisible for it too). **And the leak the file's own header describes was still live:** `beadRing`, `orbitals` and BUILD[19] started tweens straight off `TweenService` and registered nothing, so the halo and the orbital sets — most of the late game — kept writing to destroyed welds after every rebuild | **measured live in Play on the cloud place, 6–17 s samples in the torso's frame.** Hands: minute **8.3 s**, hour **95.9 s** — 11.6:1 against the authored 12:1 — both **clockwise seen from the front**; gears **5.07 s** each and **opposite** (right +71.04°/s, left −71.04°/s); chrono rings **14.19 / 10.19 / 8.15 s** against the authored 14 / 10 / 8, the middle one reversed, tilts 16° / 38° / 30° as written. The chord defect measured **before and after on the same probe**: minute hand radius **50.0%** of its own reach at the midpoint (and gear teeth 86.6% = cos 30°), now **99.8% / 99.7%** — constant. Controls throughout: the `StageDial` sits on every pivot and reads **0.00°/s**, and the leak check samples every weld after `Clear` — **0 of 50 still being written**, against a deliberately unregistered control weld in the same folder that **does** keep moving, which is what proves the sampler can see movement at all |
| 11.27 | `[x]` | <!-- coded + pushed + world rebuilt 2026-08-12; unmeasured --> **D7 · The reservation system exists and almost nothing uses it.** `scatterPoint` and `reserveScatter` are correct. Of ~100 calls, about ten pass a `halfSize` and reserve; **all ~90 calls between lines 5818 and 7249** — the entire `decorationBuilders.<Zone>` block, i.e. every zone's signature props — look like `scatterPoint(cx, 200, 250)`: they declare no size and claim no ground, so they land on each other. The tool that can actually check this is `CreatureService.clearOfScenery` / `floorAt`, which probes the **live** world with `OverlapParams` + `RaycastParams.RespectCanCollide` after `Build()` — `scatterBlocks` is a set of 2D circles with no Y axis and cannot describe a terrace. **Also:** `src/ServerScriptService/ZoneDecor.lua` (2,829 lines) is a **dead outdated copy** of the terrain section with an older `TERRAIN_PROFILE` — nothing requires it. Delete it or mark it, because it misleads everyone who touches terrain | overlap count per zone before and after | **MEASURED LIVE 2026-08-13; there is no `before` and there cannot be one** -- the world was rebuilt by the same change that fixed it. After: of **5,672 scattered solid props**, **141 (2.49%)** have their centre inside another authored object, 0 to 18 per zone (Singularity 0, VoidExpanse 1, DreamDimension 18, Volcano 15). The raw figure is 456 (8.04%) and the difference is composites that are one object by design -- `RuinPillar`/`RuinPillarBase` x163, `ValleyRock`/`ValleyRockCap` x91, `MoonBoulder` x22 -- excluded by the rule that one name being a prefix of the other means one authored thing. **What is left is dominated by things standing ON flat pads**: `IdolPad <- GlintPlinth` x19, `PoolBed <- ValleyScree` x16, `LandmarkPlinth <- GlintPlinth` x11, `IdolPad <- GlintPost` x11. `ZoneDecor.lua` is gone from both sides |

---

## Phase 12 — Premium pass · *market patterns in, DNA finally has somewhere to go*

**PHASE 12 IS CLOSED (2026-08-14, seventeenth session): 12.1–12.15 are all `[x]`.**

Planned 2026-08-14 from fresh market research (Sol's RNG roll spectacle, BGS Infinity secret
tiers, PS99 index/enchants, GaG/SaB weekend FOMO) plus a full inventory of src/. Owner
decisions taken during planning, final: **the Splicer now, enchant slots later; the hub is the
Forest spawn, not a new zone; secrets + weekend cadence + kill-feed in, offline incubator
out.** Full design detail in `.claude/plans/pregledaj-sve-pronadji-prostor-woolly-pinwheel.md`.

**The finding under the whole phase:** the mutation system is not dormant — `DNAService`
rolls one every ~10 s (`:637-644`) into `data.Mutations` and `GetIncomeMult` multiplies by
the ladder (tops at Godly **×30 income**), while `speedMult` on the same table is read by
nothing. The Splicer *takes ownership of a live, mispriced income faucet*; the ambient loop
dies in the same commit or two systems mint the same currency. And `ScaleReward` alone cannot
price the machine — it grows 2.85×/stage against per-kill income's ~5×/stage — so the roll is
priced **in kills** via the full per-kill formula.

**Rule carried through every row: copy the pattern, never the asset** — no meme IP, no
ripped models or names; the procedural rig + skinMarks pipeline generates original
equivalents.

| ID | | Task | Verified how |
|---|---|---|---|
| 12.1 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 --> **DNA Splicer economy in `GameConfig`; the ambient mutation faucet dies.** New `GameConfig.Splicer` (`baseKills=5, ramp=1.10, rampCap=200, pityEvery=10, pityLuckAdd=150, luckScale=0.25`, announce tiers Mythic+) and pure `GetSplicerRollCost(data)` priced in per-kill income (`GetClickBase × zone bonus × 4.5 × mobDnaMult`): ~5 kills for roll 1 at any stage, flat **1,000 kills/roll at the ramp cap** (~1.1e17 DNA at stage 20 ≈ 12× the top egg). Reuse `RollMutation` unchanged (Godly 1-in-816; pity roll ≥ Rare). Rebalance `incomeMult` 1.3…30 → **1.05…2.25**; dead `speedMult` becomes flat walk-speed via `GetMutationSpeedBonus`. Single active mutation (`data.SplicerMutation`) replaces the stacking list; delete the 10 s loop, `RollMutationForPlayer`, `GetMutationChancePerRoll`. Traps: veteran income nerf must keep the best owned mutation active (≤2× drop, migration in 12.4); `SplicerRolls` must NOT join the rebirth reset list (cost-reset exploit) | **VERIFIED LIVE 2026-08-14 on the cloud place.** The cost curve is **flat in kills at every stage**, which is the whole claim: roll 1 costs **5.1 / 5.0 / 5.0 / 5.0 kills** at stages 1 / 3 / 10 / 20, roll 25 costs **49.4 / 49.2 / 49.2 / 49.2**, and past the ramp cap every roll is **1000.2 / 1000.0 / 1000.0 / 1000.0 kills** — 30 DNA at stage 1 and **1.226e17** at stage 20, i.e. 13.6x the most expensive egg (9e15) against a ~1e18 endgame balance. The faucet is gone by structure, not by inspection: `RollMutationForPlayer` and `GetMutationChancePerRoll` both return **nil** on a fresh require of the shipped source, the ten-second loop is deleted, and the server boots clean (`Server systems initialized.`, no error from the changed `GetIncomeMult` signature) with the real save loading through it — leaderstats populated (DNA 4.18e9, Stage Cyborg), character spawned, WalkSpeed 243.9 written by the same line that now adds the mutation's studs. **The reprice is a REAL NERF and it was measured against the actual old code rather than estimated** — the pre-change `GameConfig` was pulled out of git and run side by side: a veteran carrying the 30-mutation list an hour of the old loop produced had a mutation term of **30.93** and now has **2.25**, a **13.75x** fall; the per-rung ladder falls 1.2x (Common) to 13.3x (Godly); a player holding one Common falls **1.24x**; a player with none is **unchanged at 1.00**. That is the point of the row — the term was an unearned multiplier nobody pulled a lever for — but it is the one change here a long-standing player will feel, and it is recorded rather than buried. `SplicerRolls` confirmed absent from the rebirth reset list, and the worn mutation is deliberately kept across a rebirth for the same reason (the ramp is lifetime, so wiping the mutation would price its replacement at the cap) |
| 12.2 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 --> **SplicerService** (new): machine model via the generated-mesh pipeline at the plaza centerpiece, position searched with EventService's separating-axis method, `ModelStreamingMode.Persistent`, versioned rebuild-by-replacement. Prompt carries `ShopPanel="splicer"`. New remote `SpliceRoll`: rate-limit (PetService `EGG_INTERVAL` pattern), server-side price check, pity branch, roll, log to string-keyed `SplicerFound`, auto-equip if better, reply via `Remotes.Notify {kind="splice"}`. Announce Mythic+ via new `AnnounceService.MutationRolled`. Stamp `player:SetAttribute("Mutation", name)` as the one replication channel | **VERIFIED LIVE 2026-08-14, driving the real handler.** The machine builds: **57 parts (33 of them helix)**, `ModelStreamingMode.Persistent`, prompt carrying `ShopPanel = "splicer"`, and **0 solid intruders in its 30x26x30 footprint** — the clear-spot search earned its place on the first boot, reporting *"preferred spot was occupied; machine moved 52 studs to (68, 215)"*. **The charge is exact**, measured on a balance floats can actually represent (the first attempt used 1e30 and read every spend as 0, because 1e30 − 2e6 **is** 1e30): five consecutive rolls quoted 711 / 782 / 860 / 946 / 1041 and charged **711 / 782 / 860 / 946 / 1041**, the 1.10 ramp visible in the sequence. **The refusal is exact too**: one DNA short of 1145 left the balance *and* `SplicerRolls` untouched, and exactly 1145 succeeded and left 0. **The rate limit blocks** — three calls with no wait produced one roll, not three. **The odds are the authored table**: 200,000 rolls at luck 0 gave Common 61.242% / Rare 24.599% / Epic 9.742% / Legendary 3.083% / Mythic 0.984% / Secret 0.237% / **Godly 0.113%** against 61.275 / 24.510 / 9.804 / 3.064 / 0.980 / 0.245 / **0.123** expected. **The pity floor holds absolutely**: 200,000 charged rolls produced **0 Commons** (the floor lifted 42.5% of them) and Godly at **0.460%**, 3.7x its base rate. Best-kept-wins verified over 20 real rolls — the worn mutation only ever climbed — and the charged rolls landed on **exactly 10 and 20**. **The helix is gated as specified, and proving it took three tries because the PROBE kept breaking, not the feature**: a bead travels **7.92 studs / 3 s** with a player at the machine and **0.000 / 3 s** with the nearest player 700 studs away, resuming to **7.92** on return; all bead radii sit at **2.900 exactly**, so it is a rigid turn about the axis rather than parts drifting off it. The two earlier readings of 0.000 were a root part cached across a teleport that killed the character (a new character means the write went to an orphan) and a 400-stud lift that gravity undid — the third run keeps the body alive on the Forest platform throughout. **The announce works and the colour bug it exposed was real**: firing Godly → Secret → a Legendary hatch → Mythic through the live service drew **3 of 4** — Godly in its own **rgb(255,240,150)**, the hatch *despite* the mutation clock being hot (which is the per-(player,kind) split doing its job), Mythic once its own clock expired, and Secret correctly eaten. Before the `payload.color` fix on `RarityBeam.client`'s **positioned** branch, Godly would have beamed **rgb(198,202,214)** — Common grey — because a mutation name is not a pet rarity and `GetRarity` silently falls back |
| 12.3 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (tenth session): the reveal was watched and three defects it hid were fixed --> **SplicerUI client** (new LocalScript — NOT MainUI, the 200-local cap): panel with current mutation, cost quoted from the same pure function off the DataUpdate cache, odds table at current luck, pity meter; slot-machine roll reveal borrowing HatchReveal's choreography, tier-scaled (card → ray fan + stinger → full-screen flash + `VFXLibrary.BurstAt`); machine rotor on ONE gated Heartbeat. All styling through UITheme. Trap: never leave blur on a stuck reply | **THE PANEL IS VERIFIED LIVE 2026-08-14 on the shipped client; the REVEAL is coded and owed a watched run.** Panel measures **468 x 520** with **0 children hanging past its bottom edge**, opens on the machine's prompt, and reads off the real payload: cost `🧬 2.09M`, `Wearing Mythic -- x1.50 income, +5 speed`, `Charged roll in 10`, and a full odds column (Common 56.7% … **Godly 0.206%** — above the 0.123% base because this session's Studio grants every game pass, the Lucky one included, which is the panel correctly quoting THIS player's luck rather than the table's). **The quote is the server's own function**, not a second implementation: `GetSplicerRollCost` is pure over the save and both sides call it, which is why 12.2's five rolls charged exactly what was quoted. One label reports `TextFits = false` and it is **UITheme's own empty ProgressBar caption**, not this panel's text — the control is that the shipped HUD contains exactly one of the same thing. **Owed: a watched roll through the reveal** — the escalation tiers, the slot-machine cycle and the blur teardown have not been seen with eyes, only reasoned about, and `finishReveal`'s single-exit design is the thing that most wants confirming. **The MACHINE, though, was looked at, and it took four builds** (`MACHINE_VERSION` 1 → 4, captured each time). v1 was pale steel on a bright green lawn — flat pastel, the exact failure the world look pass exists to prevent. v2 and v3 added a dark "outline" by wrapping each mass in a slightly larger near-black part, **which is geometrically hopeless: a shell bigger on all three axes encloses the body, so every visible face is the shell and the machine read as a solid black blob** — worse than the pale one. v4 uses the vocabulary the village crates already use (`edged` / `capped`: a bright violet mass with a dark lip tucked under it and a cap over it) and reads correctly — stepped plinth, glowing cyan trim, and a cyan/magenta double helix legible from across the plaza. The rule is now in [[evolution-lab-chunky-look-rules]]. **CLOSED 2026-08-14 (tenth session): the reveal was finally watched, and the watching is what earned the row** — every tier was driven through the real `SpliceResult` handler and sampled per frame at 60 Hz. The choreography is exactly as authored: a Common (idx 1) grows the card 40 → 380 with the Back overshoot peaking at **414**, runs **7** decelerating spins, holds **1.5 s** and shrinks away; Epic (idx 3) adds the fan and raises the blur to **14.0** with the rays turning **68° in 2.6 s = 26.2°/s** against the authored 26; Godly (idx 7) takes the blur to **24.0** and adds a full-screen flash in the mutation's **own** colour (measured rgb 255,240,150) fading 0.25 → 1.00 over 0.55 s, with a 2.2 s hold and the `⚡ CHARGED SPLICE` kicker. The blur is taken back on every path (14.0 → 0 in 0.3 s, destroyed 0.4 s later). **But looking at it found three defects no property probe could see, and all three are fixed:** (1) **the single-exit design did not actually reach what it had to clean** — `card` and `rays` were locals *inside* the pcall and were passed out on the success path only, so a forced throw mid-sequence called `finishReveal(nil, nil)`, took the blur off and left an empty 380x210 white card and its ray frame parented **forever** (measured, then re-measured after the fix: the same forced throw now leaves `cards=0 rayFrames=0 blurs=0`); (2) **the ray fan's hub sat 150 px BELOW the card** — `GuiObject.Rotation` turns an element about its own centre and ignores `AnchorPoint`, so twelve spokes anchored at their top edge all pivoted about their midpoints and the "starburst" hung under the card as a fan, now six 600-long bars centred on the hub giving the same twelve spokes in the right place; and (3) **dark text on the white card and panel was invisible**, because UITheme outlines every label in `Color.Outline` at 4px and these labels *are* `Color.Outline` — glyph and outline the same colour, rendering as a solid blob. `TextFits`, `.Text` and `.TextColor3` all read correct throughout, which is exactly why it survived this row's first pass. Fixed with `inkOnWhite` (drop the stroke: white already separates dark text) on the Kicker / Stat / Foot / PityLabel / CostLabel, and a **luminance test** rather than a name list so a future mutation is handled for free: near-black `Secret` keeps its outline and turns it *light*, verified live flipping to `rgb(252,252,255)` on every spin frame that lands on Secret and back to the dark outline on every other rung. A fourth hazard the fix itself created was closed with it: a shared card upvalue means two results inside one 4 s reveal would let the first sequence destroy the second's card, so a tear-down is now only allowed from the reveal that still owns the screen (`revealToken`) — driven live with a big and a mid reveal 1.5 s apart, **max cards on screen at once = 1, max blurs = 1**, and nothing left over. Also named the effect `SpliceRevealBlur`, because `FindFirstChildOfClass("BlurEffect")` finds EvolveReveal's parked one first and reports a blur that never rose |
| 12.4 | `[x]` | <!-- coded + pushed + verified live 2026-08-14; the refund notice landed with 12.2 --> **Upgrade-shop reconciliation + migration** (`PlayerDataService.Load`, one-way, idempotent): refund `Upgrades.Mutation` at its exact geometric sum, old `data.Mutations` list → best becomes `SplicerMutation`, names seed `SplicerFound`. New save fields `SplicerRolls / SplicerMutation / SplicerFound`, none rebirth-reset. Re-list **AutoCollect** in `upgradeOrder` (edit of an existing initializer — zero new top-level locals) with an honest description; delete `Upgrades.Mutation` last, after every reader is gone | **VERIFIED LIVE 2026-08-14, on a probe save rather than anyone's real one** — `Load` only ever touches `player.UserId / .Name / .Parent`, so it runs against a mock player on a **negative** UserId (`-424242`, which cannot collide with a real account) and the key is removed afterwards. A doctored pre-Phase-12 veteran (`Upgrades.Mutation = 12`, a 30-name rolled list) migrated **once**: DNA 1000 → **7110**, i.e. a refund of **6110** against `60*(1.35^12-1)/0.35` = **6110 exactly**; `Upgrades.Mutation` nil; the worn mutation became **Godly**, the best one held; `SplicerFound` = Common 24 / Rare 3 / Epic 1 / Mythic 1 / Godly 1, the whole list converted to a collection log. Then **saved and re-loaded, which is the idempotence that matters**: DNA stayed **7110**, no second refund, counts did not double, and the row that actually landed in the DataStore carries `SplicerRefund = nil`, `Mutations = nil`, `Upgrades.Mutation = nil`. **The re-load is what caught a real defect rather than confirming a guess:** the refund notice was first written onto `data`, so the autosave persisted it and every future join would have re-announced the same refund forever. It moved to `PlayerDataService.SplicerRefunds`, in memory, beside `OfflineSeconds` — which carries the identical warning in a comment written long before this row. Shop panel measured on the shipped client: **868 x 392**, upgrade row **4 tiles spanning 836** (4x200 + 3x12) and the diamond row 3 spanning 624, **both centred on 773 — the panel's own centre**, so three under four still reads as a grid, and **0 clipped labels** on the panel. MainUI `loadstring`s clean and `luanames` is unchanged at the documented baseline of 13 across 10 files. **CLOSED: the refund notice has its reader** — `SplicerService.Init` collects `SplicerRefunds` three seconds after the character loads, sends it through the ordinary `Notify` stack (so MainUI owns the wording, the ranking and the sound, exactly as for a fuse or a purchase) and clears the entry, so a rejoin on the same server says nothing. **And a second defect was found by re-reading the saved row rather than the loaded table**: `Upgrades.Mutation` was only removed when a refund was owed, so every save that never bought the upgrade kept an inert `Mutation = 0` key pointing at a `GameConfig.Upgrades` row that no longer exists. The key now goes unconditionally and the refund is still conditional. Re-verified in both directions on probe saves (negative UserIds, removed afterwards): a **never-bought** save saves `Upgrades.Mutation = nil` with **DNA unchanged at 500**, no refund owed, and Speed/Income/AutoCollect untouched; a **level-4** save goes 500 → **897** against `60*(1.35^4-1)/0.35` = **397** exactly, key gone, and a save-then-reload leaves DNA at 897 with nothing owed |
| 12.5 | `[x]` | <!-- speed half live 2026-08-14; aura built + verified live 2026-08-14 (tenth session) --> **Mutation aura on the body and equipped pets**: server-side `VFXLibrary.Attach` driven off the `Mutation` attribute in `EvolutionVisuals` (ApplyStage tail) + `PetFollowService` rig build; speed bonus applied beside the existing speed-upgrade site. Trap: attach to `HumanoidRootPart`, never a costume shell (re-dress destroys shells) | **HALF DONE 2026-08-14 — the SPEED half is live, the AURA is not built.** `GetMutationSpeedBonus` is applied in `EvolutionVisuals` beside `GetSpeedUpgradeBonus`, inside the size multiplier as that one is, and the live character's WalkSpeed comes off that line (measured 243.9 on the real save). The worn mutation is stamped on the player as the `Mutation` attribute by `SplicerService`, so **the replication channel the aura needs already exists and is proven** — what is missing is the `VFXLibrary.Attach` on the body and on the equipped pet rigs, plus the `GetPropertyChangedSignal` that re-attaches it. Row stays open on that. **CLOSED 2026-08-14 (tenth session): the aura is built and every clause of the check passed.** A seven-rung `MUTATION_VFX` ladder in `EvolutionVisuals` (Smoke → Stars → the pack's three purpose-built `RNG-Aura` effects → Portal → Tornado), hung on the **HumanoidRootPart** and exposed as `AttachMutationAura(part, name, scale)` so `PetFollowService` uses the same table rather than a second copy. Measured live: on join the attribute is stamped from the save and the body carries `Mythic@2.70`, **4 emitters at exactly the authored 27.0/s**, with **6 of 6 pet rigs** aura'd — and the client sees all of it (`Workspace.<player>.HumanoidRootPart`, tint rgb(255,80,80), 6 pet auras), which is what "visible to a second client" reduces to on one client, since the whole thing is server-created and replicated. **Without a respawn:** stamping `Mutation = Godly` through SplicerService's own channel swapped the body aura to 6 emitters at 38.0/s on the **same character instance**, and the pet rigs followed inside 1.6 s via the signature poll (the mutation is now part of `signatureOf`, or a splice would aura the owner and leave the pets bare until an unrelated equip). **Through a re-dress:** running the real `StageCostume.Apply` on the live character rebuilt every welded shell (24 → 53 parts and back) and the aura came through as **the same attachment instance** — which is the whole reason it hangs on the root part. **Equip/unequip** was a real round trip through the real remotes: 6 aura'd rigs → `UnequipAllPets` → **0** → `EquipBestPets` → **6 aura'd rigs**. **Two things the row did not anticipate, both found by looking rather than probing.** (1) The first cut was **invisible while every property read correct**: the pack's authored particle is ~10 studs and sits at the HumanoidRootPart, i.e. dead centre of a 16.8-stud-wide opaque torso. The fix is a new `targetSize` option on `VFXLibrary.Attach` — the exact argument the module already makes for `targetRate`, one axis over, since the pack's sizes run **1.1 studs (Fire-Aura-01) to 19.6 (Tornado-01)** and a shared multiplier sizes each effect against *itself* instead of against the player. Each rung now declares a span in studs and the aura measures **1.51x the body width**, verified in a screenshot. (2) **`Fire-Aura-01` and `Water-Aura-01` are traps despite being the pack's own "Auras"**: six emitters of 1.1-stud particles whose shape comes entirely from where they sit on the source part, and `Attach` lifts every emitter onto ONE attachment — so they collapse to a dot. Godly uses `Big/Tornado-01` instead, whose emitters are already at the origin. Its span was chosen by looking at both ends: at 8.0 it is a faint wisp, at 11.0 it is a gold vortex with a crown ring above the head, which is the right answer for a 1-in-816 rung. Also: the aura's idempotence key is `name@scale`, **not name alone** — an evolve keeps the mutation and triples the body, so a name-only check would leave a Cell-sized aura on a Gorilla forever |
| 12.6 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (eleventh session), screenshot included --> **Journal surfacing** (inside existing Journal blocks, zero new top-level locals): rarity corner pip per disc + rarity line in the detail card; "+N% Max Health" quoted from `GetCharacterHealthPct` (the applied function, never re-derived); per-stage counts on row headers ("3/5"); "Next unlock" callout via `GetCollectionStage`/`NextCharacterForStage`. Contract: refresh writes-only-never-creates | **VERIFIED LIVE 2026-08-14 on the cloud place, and the screenshot is what finished it.** All four clauses pass: the twenty per-stage header counts **sum to 36 against a header reading "Discovered 36 / 100"**; the callout names **Chromeshell**, which is exactly what a control scan of the rendered panel returns as the first disc still showing its Lock (stage 8, `cyb_chrome`) — the callout and the control were computed by different routes and agree; and a `TextFits` sweep over every visible label of the open panel is **0 failures**. **101 discs, 101 pips.** The health clause's own premise had to be corrected first: health does **not** move on equip and never did, because `GetCharacterHealthMult` reads `GetProgressRank` (the best rung OWNED) exactly as damage does — a costume is free. The check that means what that one meant: the panel quotes **+36% Max Health** for the best-owned entry (`cyb_rust`, rank 36), the applied multiplier is **1.3600**, and the live body's MaxHealth is **516 = floor(380 x 1.0 mastery x 1.36 x 1.0 potion)** — quoted figure, applied function and rendered humanoid all one number. The row named `GetCharacterHealthBonus`, which does not exist; `GetCharacterHealthPct` did, with **no callers at all**, and it gained an optional `data` argument so an **off-ladder** skin is quoted honestly through `GetEffectiveRank`. That fixed two real lies on the VIP card that predate this row: it printed **"#1 of 5" against a stage list it is not in** and **6 Damage** — the weakest rung in the game, because `GetRankDamage` clamps a rank of 0 up to 1 — beside a skin that actually scores as the wearer's best. It now reads "👑 VIP Exclusive • outside the collection", **64 Damage** and **+36% Max Health**, the same figures the body is fighting with. **Zero new top-level locals, confirmed by counting rather than by intent: 170 top-level `local` statements / 177 names, identical to HEAD.** Layout: the well went 244 → 212 to pay for the second stat row (the panel is the widest in the game and is fitted to a phone by SCALE, so the pixels had to come out of the card, not out of the panel), and everything under it moved up by the difference — which also closed a 4 px overlap between the stat card and the hint that had been there since the hint moved. **And the screenshot found the defect no probe could**: the two stat lines are dark ink (70,78,98) and UITheme outlines every label in near-black at 4 px, so glyph and outline were the same colour and both lines rendered as fat dark blobs with a slightly lighter core — the identical fault 12.3 found one panel over, with `.Text`, `.TextColor3` and `TextFits` all reading correct throughout. Fixed with the same instrument, a **luminance test rather than a name list**: `inkOnLight` drops the stroke below 0.62 and keeps it above, so the pale-gold Legendary name (0.786) **keeps** its outline and stays readable on the white sheet while the name, subtitle, both stat lines and the hint lose theirs. Verified live in both directions and photographed both times |
| 12.7 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (eleventh session); rare-first sort declined with a reason, see the cell to the right --> **Journal event-skins section + rare-first sort** (nice-to-have): 22nd section for `GameConfig.EventCharacters` (owned vs silhouette + how-to-get); optional rare-first toggle via `LayoutOrder` only. Trap: event skins must NOT enter the "Discovered N/100" count | **VERIFIED LIVE 2026-08-14.** The panel builds **22 rows** now, the last reading `🎆 Event Exclusive`, and the skin was driven through both states on the shipped client. **Locked:** silhouette, `???`, rarity pip `L`, `⚔️ = best`, and a how-to-get line that names the real event — *"Handed out during 🌈 Prism Festival. Turn up while it is running and it is yours for good."* **Owned** (granted the way 6.4 grants anything the client reads: the real save pulled out of the DataStore, the field added, `DataUpdate:FireClient` in a 0.15 s loop, nothing written back): disc unlocked with its rig showing, detail card naming *Prism Herald*, a **59-part figure built in the well** at the player's own stage, the well's rim in the skin's own violet, and a live Equip button. **The trap holds in both states: the header still reads "Discovered 36 / 100".** `TextFits` sweep 0 failures. **Rebirth keeps it, run as the real sequence** on an in-memory copy of the live save: 36/100 with `event_prism` owned → `RebirthService`'s wipe takes it (`owned=false`) → `ServerMain.OnRebirth`'s `SyncEventCharacters` restores **exactly 1** → owned again, count **0/100** — the ladder wiped, the event skin kept, and still not counted. **Three defects older than this row fell out of it, all one cause: three sites tested `vip` where the predicate is `offLadder`** (the distinction the roadmap already records under Phase 7). An event skin has `stage = nil` like the VIP one, so `CharacterPreview.Build` was handed a nil stage and **an owned event skin previewed as an empty well, in the disc AND in the detail card** — the one entry a player would most want to look at; and its cell printed the ladder figure for rank 0, i.e. the weakest number in the game, instead of `= best`. **The rare-first sort is DECLINED, not skipped, and the row said "optional".** It cannot be done by `LayoutOrder` — cells are positioned by index inside their row, not laid out, so only the twenty rows carry one — and it should not be done at all: a stage's five entries are *already* in rarity order, and that same order is the unlock queue every other part of this panel reads (the subtitle, 12.6's "next up" callout, the whole left-to-right sense of a row). Reversing it would put the disc you are working towards at the far right. Reasoning is in the code beside the section build so a later session does not re-derive it |
| 12.8 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (twelfth session), two screenshots --> **Shop entry points**: `RIGHT_COUNT` 8→9, one "🏪 Market" tile in its own IIFE with a two-button flyout → `showEggPanel` / `showFusionPanel` (both self-gate); mystery kiosks get an odds board (egg-stall precedent), purchase stays on the server-validated prompt. Update the deliberate "no fusion HUD button" comment so a future session doesn't revert this | **VERIFIED LIVE 2026-08-14 on the cloud place, with real mouse clicks rather than a probe calling the handlers.** Both panels open in **exactly two clicks from anywhere**: tile → *Eggs* gives `EggPanel` (470x520, titled **"🥚 Ocean Eggs"** — the player's own zone, not Basic-in-Forest), and tile → *Fusion* gives `FusionPanel` (500x520). **The self-gate is the thing that makes this safe and it was measured, not argued**: standing nowhere near a podium, the hatch button reads **"GO TO A PET SHOP"** and the bulk button reads **🔒**, while the price (**12.00K**) and the odds (**🍀 159% luck**) are live — which is exactly the browsing the row was for. `TextFits` sweep over both panels and the flyout: **0 failures** across 25 + 41 labels. Clicking anywhere else closes the flyout and opens nothing (`fly=false scrim=false panels open=none`); the dismiss is a transparent 20-screen-wide TextButton parented to the tile, so it needs no mouse coordinates and no inset correction — same reason the flyout itself hangs off the tile rather than off `AbsolutePosition`. **Layout**: 12 tiles, **0 overlapping pairs** at 1546x793 (5 rows, 82px, 26 gap) *and* at the responsive pass's floor (40px tiles, 8 gap, 5 rows = 232px + `BOTTOM_CLEAR` 46 = 278px, so it still clears `TOP_CLEAR` 121 on a 420-tall phone). Zero new top-level locals: **170 `local` statements / 177 names, identical to HEAD**. **The kiosk board** replaces the three-line paragraph on all **five** Mystery shops (`BUILD_VERSION` 128 → 130, rebuild ran, `[PotionService] wired 5 mystery potion counters`, 0 paragraph signs left): a white pill in the shop's violet, one cell per size, quoting **66% / 27% / 7%** off `GetMysterySizeOdds`, which is the table `RollMysteryPotion` rolls against and **sums to 100.000000** by construction. The kind line is built from `PotionKinds` now and that fixed a real lie: the hand-written one named **three** kinds beside a share computed over **four** (11.8 added Health), i.e. a board advertising 75% of its own product — it reads **"🧬 DNA ⭐ XP 🍀 Luck ❤️ Health • 25% each"**. **And the screenshot found what no property probe could, for the fourth session running**: at `BUILD_VERSION` 129 the medium bottle's **27%** rendered as pale grey between a saturated green 66% and a magenta 7%, because the ink came from an RGB lerp between mint and pink and **the middle of an RGB lerp is the grey axis** (saturation 0.07). Re-inked off a HUE ramp (0.42 → 0.94 at s 0.85), verified rgb(23,158,93) / rgb(34,23,158) / rgb(158,23,72) on all five boards and photographed from player eye height. Two notes for later: the row said "SurfaceGui" and the egg-stall precedent it names is a **BillboardGui** sized in studs — the billboard is what was built, so the board stays over its own counter and turns to face the reader; and a stall's forecourt is at local **+Z**, which is the direction *opposite* `base.LookVector` (LookVector is the −Z axis), which is what three blocked camera solves were actually about |
| 12.9 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (twelfth session) --> **ZoneShops 8 → 15**: Mystery +13,17; Fusion +14,18; Emporium +12,16,20 (keeps the Mastery panel's only entry reachable late-game). **Bump ZoneBuilder `BUILD_VERSION`** or the rebuild is a silent no-op; push over the HTTP bridge. Confirm PotionService discovers prompts by scan, not a hardcoded list | **VERIFIED LIVE 2026-08-14 on the rebuilt world** (`BUILD_VERSION` 130 → 131, `rebuilding world: stamp 128 -> 131`). The row's arithmetic said 14 and its own list says **15** — the list is what shipped: 7 Mystery, 4 Fusion, 4 Emporium. Audited **per zone against the table rather than by walking**: for all twenty zones the shop found in the world matches `GameConfig.ZoneShops` exactly — **20 matches, 0 mismatches** — with the Emporium showing its two prompts (Diamonds + Robux) and every other shop one. **From zone 12 every zone now has a counter**; the five with none are 1, 2, 5, 6 and 9, so the longest run without one is **2**. The scan is what PotionService relies on and it proved itself: `[PotionService] wired 7 mystery potion counters`, up from 5, with no list to edit. All **7** kiosks carry 12.8's odds board (zones 3, 7, 11, 13, 15, 17, 19). **Footprint checked in every new zone** with a box query over the stall's own volume: 0 foreign parts in 12, 14, 18 and 20 (the `Knob`/`GridX` hits are the shop's own trim and the ground grid under its deck), and Mirror Universe's reflecting pool — the one candidate for a shop standing in water — ends at z=135 against a deck starting at z=146, i.e. **11 studs clear**. **A probe trap worth keeping:** all four Fusion counters read as MISSING on the first audit because the prompt hangs on `StallCounter`, which is an `ALWAYS_LOADED` name and is therefore reparented into `workspace.WorldShell` at the end of the build — a `workspace.Zones` scan finds nothing and it reads exactly like the prompt never being created. Scan `workspace` |
| 12.10 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (thirteenth session), three screenshots --> **Forest hub plaza** (new `HubPlaza.lua`, own `PLAZA_VERSION`, built OUTSIDE ZoneBuilder per the LeaderboardService precedent): paved deck (x −180..180, z 90..420) unifying the three leaderboards + event board + Splicer centerpiece + lamp/banner dressing toward the Colosseum gate + photo spot. Every part position searched against the live world; nothing in the 30-stud street corridor; billboards anchored | **VERIFIED LIVE 2026-08-14 on the rebuilt world, and all three defects it closed were found by running it rather than by reading it.** The plaza builds at `PLAZA_VERSION` 2 as **142 parts** — deck, kerb, drawn frame, 2 long + 4 cross bands, medallion, arrival dais, **8 lamps, 6 banner poles, 2 gate signs and the photo spot** — `ModelStreamingMode.Persistent`, `0 skipped`. **Corridor: 0 standing intruders.** Every part of the model was walked and its world AABB taken from its own rotation; nothing that stands up has any part of its span inside |x| ≤ 30, and the 9 parts that cross the lane are all flat paving (Deck, Kerb, both FrameX, the three medallion discs, both dais discs) — which is the authored rule, you walk over a floor and around a lamp post. **Spawn lands on pavement:** a ray down at the SpawnLocation and at eight points on a 20-stud ring gives **7 of 9 on plaza geometry**; the 2 that miss are the street's own `PathStone` verge boulders at x = ±20 (tops 4.62 and 2.14), which stood there before the plaza and which the design deliberately keeps standing — photographed, they read as kerb stones edging the dais. **The deck persists through streaming, and this is the one clause where the obvious probe lies.** The first control — "the `ForestTree` models are still on the client" — reported 20 of 20 present at 13,302 studs and proved nothing, because a streamed-out model keeps its node and loses its *parts*. Counting descendants against the server in the same instant is the check that means something: `Zones.Forest` **5138 → 875** on the client (83% evicted), `WorldShell` 2074 → 2074, **`HubPlaza` 142 → 142**. Getting there also cost a probe trap worth keeping: `TeleportToZone` takes a **zone key string** and its handler is guarded by `typeof(zoneKey) == "string"`, so firing an index is silently dropped — the player never moved, and a distance check written that way would have "passed" at 91 studs. **Three real defects, all fixed under this row.** (1) **The photo spot was SKIPPED on the first live build.** It had a single preference, (−104, 344), and a generated `ForestTree` 28 studs across at (−110, 357) covered it and everything the ±28 nudge list could reach. Forest's props are `math.random`-scattered, so that was never a bad coordinate — it was a coordinate whose luck is re-rolled every rebuild, and a plaza that silently ships without its photo spot on some worlds. It is a list of four authored spots now, mirrored either side of the boulevard, with a deck scan under them as the floor; it landed at **(−90, 344)** with the frame outboard (west of the pad, so the player has it at their back and the plaza in front) and the pad fully inside the deck. (2) **The deck height was sampled, not derived, and the sample was a coin toss.** It sat at 0.78 on a reading of "the ground patches are at 0.47" — but ZoneBuilder lays them `for i = 1, 70` at `y = 0.05 + i*0.01` with a 0.2 half-thickness, so their top face runs to a hard ceiling of **0.95**, and which of them land in this footprint changes per rebuild. Measured on the first build: one 23 × 24 patch stood **0.07 proud** and read as a green pond in the middle of the pavement, with the inlay at 0.90 inside the same band. The whole ladder was re-derived above the ceiling (kerb 0.66 / deck 1.04 / inlay 1.14 / cross bands 1.18 / medallion 1.24-1.31-1.38 / dais 1.26-1.33 / photo 1.28-1.42-1.52, still clear of the SpawnLocation's 1.5 top), and `GROUND_CLEAR` went 2.0 → 1.4 so the occupancy test still calls the deck "floor" and the shortest real boulder (1.53) "an obstruction". **0 patches pierce the deck now.** (3) **The file's own "EVERY BAND BUTTS, NOTHING OVERLAPS" comment was true of the frame and asserted for the cross bands, which cross**: BandX spans x 34..140 and BandZ stands at x = ±58, so they overlap in a 7 × 7 square four times with both tops reading **0.9000, delta 0.0000** — the terrace shimmer exactly, in the file that documents that trap. The cross bands took their own plane 0.04 over the long ones (ZoneBuilder's patch stack settles the same argument the same way), and a sweep for coplanar pairs over every flat part of the model now returns **0**. Three screenshots: the overhead of the whole deck, the walk-down from the spawn at player height, and the photo spot with the `📸 PHOTO SPOT` and `⚔️ COLOSSEUM` billboards legible. **A note for whoever shoots this next: the overhead at 250 studs comes back teal and washed out and the ground-level shot does not** — that is `Lighting.Atmosphere` at density 0.30 / haze 0.55, not the palette. Judge this plaza's colour from player height, which is where it is warm cream stone in a dark kerb, or you will "fix" a palette that is already right |
| 12.11 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (fourteenth session), five screenshots --> **Top-3 player statues**: generalize `LeaderboardService.buildStatue/refreshStatue` to three plinths (gold/silver/bronze) refreshed on the same board pass. Traps: anchor-last ordering (the underground-statue bug is documented in-file); `HumanoidDescription` fetch yields — `task.spawn` off the board pass | **VERIFIED LIVE 2026-08-14 on the cloud place, driving the real board pass rather than a probe's copy of it.** `BOARD_VERSION` 2 → 3 rebuilds the folder; the podium is three `edged/capped` plinths at z = 95 (gold x −130 keeping 10.19's proven spot, silver −102, bronze −158) on a **9.0 / 7.5 / 6.0** height ladder carrying **22 / 19 / 17**-stud figures, plus a plaque on each +Z face. **The ranks were driven through every transition the row asks about, using two temporary rows written into the live DNA `OrderedDataStore` and `RemoveAsync`'d afterwards** (real userIds are unavoidable — a statue is a real avatar fetch, so the negative-id trick cannot be used; the board was confirmed back to its two real rows at the end). Identity was measured with an attribute marker on each figure, so "rebuilt" and "left alone" are facts rather than inferences: **a new #2 and #3 arriving** left #1's marker intact and rebuilt only 2 and 3; **swapping ranks 2 and 3** left #1's marker intact again and swapped exactly those two; **a value-only change** (210.0B over 200.0B, no reorder) left **all three markers intact** and repainted only the plate — which is the "least work per slot" claim, measured; and **removing both rows** destroyed the #3 figure, returned its plate to `unclaimed` and rebuilt #2 from the real board, ending at 2 figures and 8 folder children. Plates and board rows agree line for line (`🥇 acipaci22 590.7B` / `🥈 Jane Doe 210.0B` / `🥉 John Doe 100.0B` against rows 1–3, with row 4 correctly on no plinth). 12 distinct top planes across the nine plinth parts, **0 shared** — the terrace-shimmer sweep, run because concentric tiers are exactly where that bug lives. HubPlaza is untouched by the new footprints: still **142 parts, 8 lamps**, and the lamp at (−84, 112) is still on its authored spot, which matters because `LeaderboardService.Init` runs *before* `HubPlaza.Init` and a plinth that grew would silently push the lamp instead. **Four defects, three of them older than this row and all three found by looking rather than probing.** (1) **10.19's statue faced the wrong way for its whole life**: it yawed `math.pi * 0.5` under a comment saying "faces +X, the street the boards read toward", but a model's facing is its pivot's LookVector, which is −Z at identity, so a quarter turn points it at **−X** — away from the street and away from its own nameplate. Measured on the live statue before this row touched it (pivot LookVector (−1, 0, 0), right hand at z = 90 against a centre of 95). A half turn is the one that gives +Z, which is also what the new composition wants: a row spread along x meets the player walking down the boulevard face-on, where facing +X would queue the three up one behind another. (2) **`ScaleTo` against a bounding box taken one frame after parenting is wrong for any rig with accessories** — their welds resolve a frame or two later and the box shrinks under it. The #1 avatar carries none and came out at **22.000 exactly**; the #2 avatar carries three and came out at **17.14 against an asked-for 19**, enough to put second and third the wrong way round in the silhouette. Fixed with measure → scale → wait → measure → correct, and the corrective factor landed on the predicted value (3.0677 → 3.4015); re-measured on the shipped build as **22.000 / 19.000**. (3) **The first plaque covered the whole front face**, so head-on — the one angle the podium exists to be read from — each plinth was a dark base, a dark plaque and a dark cap, with the bright stone visible only from the sides. Photographed, all three read as black blocks: the outline-first rule inverted, because the *mass* has to be the bright thing. At 0.62 × 0.52 of the body the stone frames the plaque on four sides. (4) **10.19's bronze cannot be a bronze once there is a gold beside it**: (196, 138, 74) and (240, 196, 96) differ by 1.2× in red and 1.4× in green, which survives a colour picker and does not survive Forest's key light — photographed from eye height at 30 studs the two figures were the same lemon yellow. Bronze is now genuinely copper (170, 92, 44), pulled 26 points down and hard toward red, and the three ranks separate at plaza distance. One thing the row did not anticipate and which is left as authored: the boulevard-side view of #2 is crossed by HubPlaza's lamp post at (−84, 112) from one narrow wedge, and the board panel at (−130, z 123..157) screens the podium from a head-on northern approach — but the sightline from the street (x ≈ 0) clears both, and that is where players actually walk |
| 12.12 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 --> **Secret-tier pets**: `GameConfig.SecretPetsByZone` (20 authored species, `secret=true`), flattened into `Pets` but **excluded from `EggablePets`** (filter gains `not def.secret` in the same commit); append `{name="Secret", weight=0, bonusMult=12}` to `PetRarities` **without touching `PetRarityOrder`** (zone lists are positional, five long). Pre-roll in `rollAndInsert` iff Premium egg: `1/50,000 × (1 + min(petLuck,400)/1000)`. Announce via `BeaconRarities.Secret = true` + own beam colour; "?????" row on Premium odds boards; Secret badge in the pets index | **VERIFIED LIVE 2026-08-14, every path driven through the real remotes.** Shape first: `Pets` **140**, `EggablePets` **100 exactly**, 6 rarities against an untouched 5-long `PetRarityOrder`, 0 duplicate keys across the 140, `SecretPetsByZone` 20, and **0 secrets or exclusives anywhere in `PetsByZone`, `EggablePets` or the terrace pools**. Cost of a roll: 1 in 50,000 at luck 0, 1 in 35,714 at the 400 cap, **and still 1 in 35,714 at luck 9,999** — the clamp is real, not decorative. **The tier gate is the strongest result**: with `chance` forced to 1 in the live server VM (a temporary `Script` in `ServerScriptService`, since an `execute_luau` require holds a different module), a Premium hatch gave **Thorn Heart (Secret)**, x10 gave **10 of 10 Secret** — so the pre-roll really does fire per egg inside the bulk loop — the pass-driven **`DriveAutoHatch`** gave one more, and the **Basic and Better eggs fired at the same `chance = 1` handed over ordinary Mossy**, which is the whole claim of "Premium only". With `chance` forced to 0, **30 real hatches produced none**, and 11.6's exclusivity probe re-run over **48,000 rolls** (60 eggs x 4 luck levels, including luck 5,000) found **0 exclusives and 0 secrets**, with both fallback doors — a malformed egg and an empty pool — clean over 5,000 rolls each. Presentation is drawn, not inferred: the Premium panel carries a fifth row reading **"?????" / Secret / "1 in 39,627"** in the Secret pink at 89 px of a 96 px box (the percentage formatter would have printed "0.00%"), every Premium podium billboard in the world grew a fifth **❓ 1/50K** cell at **18.5 studs — the width the Better board already had**, the pets index draws the **SECRET** pill on both a Golden and a Normal Secret unclipped, and the real `AnnounceService.PetHatched` beamed **"SECRET HATCH!"** in its own colour while the Common control fired at it was correctly eaten. Four screen captures. **Three silent misses were found and fixed by asking what a sixth rarity breaks**: `SoundLibrary.HATCH_SPEED` had no `Secret` row, so the rarest hatch in the game would have played at the *Rare* pitch (absent falls back to 1.0); `PetModel` gated its glow ring and sparkle on `== "Legendary"`, so a Secret would have been duller than an Epic; and `HatchReveal` sized its burst the same way, so the pet that raises a 420-stud pillar would have flashed 45 particles. All three now read `IsBeaconRarity`, which is the one table that already knew |
| 12.13 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (fifteenth session), four screenshots --> **Weekend Colosseum event** (content through EventService): recurring Sat 48 h window, ×2 event-boss DNA/diamonds via existing `GetEventMult`, and a **4-skin rotation** — `rotation[1 + floor(window.startTs/604800) % 4]`, index off `startTs` not `now`; author 4 event skins off the `event_prism` template. Decide up front how the board headlines when it overlaps Weekend Rush (`active[1]` draws today) | **VERIFIED LIVE 2026-08-14, every clause driven through the real services rather than a probe's copy of them.** The overlap question is answered by a **`priority` field and a sort inside `GetActiveEvents`**, not by table order: three separate places draw `active[1]` and nothing else (the sign, the HUD boost card, `GetEventHeadline`), so the Colosseum takes priority 10 because the champion is different this week and Weekend Rush is the same every week — and the rate boost is not lost, because the HUD card now **sums the effects of every live event onto one line** and the sign **names the co-runners**. The tie-break is the authored index, since `table.sort` is not stable and two equal priorities would otherwise make the board flip name every second. Measured on a Saturday clock: `active[1]=ColosseumClash active[2]=Weekend2x`, `bossMult=2 incomeMult=2 xpMult=2`, sign reading **"🎉 LIVE NOW / ⚔️ Colosseum Clash / 1d 17h / …➕ also live: 🔥 Weekend Rush"**, HUD card **"Colosseum Clash +1"** and **"x2 DNA   x2 Giant Loot   x2 XP"**, all four card labels `TextFits`. **The rotation is stable across a whole window and cycles**: six consecutive weekends resolve verdant → onyx → ember → frost → verdant → onyx, and sampling the window **hourly for its full 48 hours gives exactly 1 distinct key** — which is the point of taking the index off `window.startTs` and never off `now`. **The grant is once and only once**, driven through the real `GrantRewards`: week 1 → `{event_clash_verdant}`, the same window again → `{}`, +1 week → `{event_clash_onyx}`, back to week 1 → `{}`, and a Tuesday → `{}`. `data.Characters` carries it, the ordinary `Notify` card arrives (`character key=event_clash_verdant name=Verdant Colossus isNew=true`), and the Journal still reads **"Discovered 100 / 100"** with **22 rows** — the count trap holds with five entries in the event section. **The giant's double was measured off the real remote payload, not off a balance**: eight kills through the real `AutoAttack` → `onHit` → payout path gave **amount 60,000,000 ×4 off-weekend and 120,000,000 ×4 on**, diamonds **12/15/13/14** against the authored `{12,20}` band and **24/40/38/38** on (all even, i.e. exactly `2 × RollBossDiamonds`), and XP correctly **unchanged at 20,000** both sides. Reading the DNA *balance* instead would have been unusable: at 9.33e18 the float ULP is ~1024, so the delta reads 60,000,256, and two of ten trials were polluted by an idle-income tick — which decomposed exactly (the weekend trial's extra was 2.0000× the off-weekend trial's, i.e. Weekend Rush doubling ordinary income), but the remote payload is the number the code actually pays. The real save was snapshotted and restored on every run (DNA, Diamonds, Kills, XP, `EventCharacters`, `Characters`) and saved back. **Five defects, and four of them were found by looking rather than probing.** (1) **The off-weekend board named the WRONG event, on five days out of seven.** Both windows open at the same instant, and `GetNextEvent` kept the first one it found at the soonest start — authored order — so the sign counted down to "🔥 Weekend Rush" while the sign during the weekend headlined "⚔️ Colosseum Clash". Replaced with `GetUpcomingEvents`, which returns everything sharing the soonest start under the same priority sort, and the next-branch names the co-starters too. (2) **`EventName` did not fit its box**: the longest name in the table used to be "Prism Festival" (85 px at this label's 14 px floor), "Colosseum Clash" is 100 and with the "+1" it is 118 against a 112 px box. The clock beside it never needed its 76 px — its longest possible string is "48m 09s" at 59 — so the name took 128 and the clock keeps 60, still flush. (3) **The Journal's hint colour was sticky**: three branches painted it green and none painted it back, so an unowned skin inherited the green of whatever owned skin was looked at last. Reset once before the chain, which also covers the fourth green branch this row added. (4) **And the screenshot found the big one, which is older than this row and was invisible to every probe: the DNA Splicer machine was standing INSIDE the event board** — a 27-stud box spanning x 132..160 against a sign panel at x 148.5..151.5 on the same z. Cause: `SplicerService.Init` ran **before** `EventService.Init`, so `findClearSpot` searched a Forest with no sign in it; its preferred spot was rejected for a single 1.8-stud `GlintPost` and it stepped one ring east into the board. Both structures built successfully and each is idempotent about its own parts and blind to the other's. Fixed as one change in three parts, because any one alone does nothing: `SplicerService.Init()` moved below `EventService.Init()` (which is what ServerMain's own comment block already argues for, and what HubPlaza's comment claims of all four), `MACHINE_VERSION` 4 → 5 so a played world re-runs the search, and a named **`SIGN_CLEAR`** exclusion — because the first build after the reorder put the machine 30 studs west of the sign instead, i.e. on the face it is read from, which no occupancy test can object to: standing in front of something is not touching it. Same idiom and same reasoning as the existing `STREET_HALF`. `PREFERRED` also moved z 215 → 290, off the sign's line and 75 studs nearer the spawn walk-down. Re-measured live: machine at **(146, 316)**, **0 solid intruders** in its footprint, **separating-axis gap 70.3 studs** to the board, and the only fixed thing left in the sign's 40-stud reading slab is a 7-stud glint plinth off to one side — the red crates in the first photograph are `Creatures`, which walk, exactly the trap the roadmap already records. Four screenshots: the Journal's event row, the sign occluded by the machine, and the sign clean in both its LIVE NOW and NEXT EVENT states |
| 12.14 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (seventeenth session), three screenshots --> **Kill-feed publishers** (policy in AnnounceService, rendering free via the positionless toast path): `ApexKilled` (at the drop-roll site), `BossKilled` (only `firstTime` and zones ≥ 15, flag from `markDefeated`'s before-state), `Rebirthed`, and the Colosseum giant's local announce routed through `Broadcast`. Generalize the per-player cooldown to per-(player, kind) | **VERIFIED LIVE 2026-08-14 on the cloud place, every publisher fired from its own real call site rather than from a probe's copy of it.** The per-(player, kind) split was already there — 12.2 built it — so what this row added is a `KIND_COOLDOWN` override table over it and the four publishers. **Apex**: a real Apex killed through the real `AutoAttack` remote drew *"👑 APEX SLAIN! / OGLightninggXD brought down 🌲 Heartwood Ancient in Forest"* in the Apex plate's own purple. **Boss**: a real zone-20 kill drew *"🔺 THE ABSOLUTE DEFEATED! / …cleared The Absolute Plane for the first time"* in orange — **and both gates were proven with a control rather than argued**: the Forest boss (zone 1) was killed for a genuine first clear in the same session and produced **nothing**, and the AbsolutePlane boss killed a *second* time after its respawn also produced **nothing**, so the zone floor and the `firstTime` flag each eat exactly what they are supposed to. **Rebirth**: driven through the real `RebirthService.HandleRebirth` on the owner's own save (Stage 20 → 1, DNA → 0, Characters 101 → 2, Zones 20 → 1, Bosses 20 → 0), drawing *"✨ REBIRTH 4! / …started over -- x8 damage forever"*. **Colosseum**: all three branches, and the arrival one landed by itself off the real 30-minute timer while the probe was doing something else — arrival red + `levelUp`, **fallen** coral after a real 40-hit kill (25M / 625,000 = the `EVENT_MIN_HITS` clamp exactly), **withdrawn** muted grey, no sound on either of the last two. **The cooldowns are exact, measured against kills rather than against calls**: an Apex killed 26.8 s after an announce (health 259,000 → 0, so the kill is not in doubt) produced **no payload**, and one killed at 48.8 s produced one — the 45 s `apex` window, which exists because four Apexes on a 120 s respawn means one farmer would otherwise hold the feed. **The spam test**: ten of each kind fired through the real publishers inside ~0.5 s gave **exactly 1 apex + 1 boss + 1 rebirth**, all three timestamped the same instant, which is the per-kind split doing its job in the direction that matters (one kind cannot eat another). **The client caps hold**: 20 positioned beams broadcast in one frame left `MAX_ACTIVE` at **6**, the toast stack peaked at its own cap of **3**, and `RarityBeamLocal` held **0 parts** afterwards — every one of the twenty took its cleanup path. **The design decision under the row is that a kill feed is WORDS**: none of these four carries a position, so none of them draws a 420-stud column. An Apex respawns every 120 s, every player clears twenty bosses and the Colosseum runs every half hour; beaming those would make the beam mean less, which is the same argument the 6.2 rate limit was built on. **And the screenshot found the one defect no probe could, for the fifth session running**: the Colosseum arrival and the Rebirth card were **both gold** and they sit in the same 3-high stack, so a rebirth during a Colosseum window drew two identical gold blocks that read as one repeated message. Every kind owns a unique hue now — Apex purple, boss-first orange, rebirth gold, arena red/coral, withdrawal grey — re-photographed to confirm the red and the purple separate at a glance. Text was measured before the photo and again after: `TextFits` true on all eight labels, the longest headline (*"👹 THE DEVOURER HAS ENTERED THE COLOSSEUM!"*) rendering 522 × 24 px inside a 540 × 30 box. One thing the row did not ask for and got: **`payload.sound`, opt-in on the positionless branch**. Routing the Colosseum through `Broadcast` took away the `kind = "reward"` cash-register it used to play — which was never right for a giant walking into an arena — so the arrival names `levelUp` and nothing else names anything, because a chime per Apex per boss per rebirth is how a feed becomes noise. Unknown names are swallowed in a `pcall`: `SoundLibrary.Get` errors on a name it does not hold, and a mistyped sound must not cost the announcement it was decoration on. **The owner's save was backed up to its own DataStore key before the rebirth and restored from it afterwards**, twice — the second restore rolled back the probe's own kills as well — and the saved row was read back out of the store both times (DNA 9.33456e18, Diamonds 62, Kills 4315, 20/20 bosses, 20 zones, 4 rebirths, Stage 20, 101 characters). The backup key was `RemoveAsync`'d at the end, so no stale copy of that save is left in the store |
| 12.15 | `[x]` | <!-- design note recorded 2026-08-14 (seventeenth session); no code owed, and none written --> **Pet enchant slots** (approved, LOW priority — design only this phase): `enchant` field enters the pet shape in `insertPet` (the ONE creation point) + one multiplier line in `GetPetBonus`. Nothing in 12.2 blocks it | **DESIGN NOTE RECORDED, AND BOTH OF THE ROW'S PREMISES WERE CHECKED AGAINST THE CODE FIRST — one of them is wrong.** (1) **`insertPet` is NOT the only place a pet is created.** `PetService.HandleFuse:591` writes `{ id, key, tier }` inline, so a fuse mints a pet that never passes through the one documented creation point — and the comment at `PetService:189` claiming otherwise is wrong today, before any enchant exists. That is the whole risk in this row: a shape gains a field at `insertPet`, the fuse path silently omits it, and sixteen enchanted pets fuse into one plain pet with no error anywhere. It is also where the design decision actually lives — *does a fuse carry the best enchant forward, or burn all sixteen?* — so the fix is not "add the field in two places" but "make the fuse say what it does with them". (2) **`GetPetBonus` cannot read an enchant as it stands**: its signature is `(tier, rarity, petKey, data)` and it never receives the pet entry, so "one multiplier line" needs a fifth optional `enchant` argument threaded through **five** call sites — `GameConfig:1402` (the equipped loop), `GameConfig:1506` (`GetPetPower`, the index's damage share) and `MainUI:2407 / 3102 / 3103`. Every one of those already holds the pet entry, so each is a one-token change; none of them needs to learn what an enchant is. Two further constraints, both from rules the roadmap already paid for: **price an enchant in Diamonds or Shards, never DNA** — a rebirth keeps `data.Pets` (`RebirthService:81`) so an enchant is permanent, and DNA is stage-scaled, which is the same reason 8.x refused to make DNA tradeable; and **no `Load` repair is needed**, because `enchant = nil` means "has not happened yet" and that is true of every pet minted before the field existed (the 6.3 rule, and the exception it names does not apply here). `TradeService` needs nothing: it moves whole entries, so an enchant travels with its pet by construction. **No code was written for this row and none is owed** — the note is the deliverable |

---

## Phase 13 — Pet enchants · *the first repeatable Diamond sink*

**PHASE 13 IS CLOSED (2026-08-14, eighteenth session): 13.1–13.4 are all `[x]`.** There is no
code-only work left anywhere in the roadmap again — every open row is an owner action.

Opened 2026-08-14 (eighteenth session) on the one approved design left unbuilt: 12.15 recorded the
enchant design, checked both of its premises against the code, and deliberately wrote no code. This
phase builds it. Everything 12.15 found still stands and is the starting point, not a thing to
re-derive — read that row before this one.

**Why a Diamond sink is the point of the phase, not a detail of it.** The game has exactly two
Diamond sinks and both are finite: `DiamondUpgrades` (three tiles, one of them capped at level 3)
and `StageMastery` (twenty one-shot purchases, ~700 diamonds for the whole set). A player who has
bought the set has nothing left to want, while every kill keeps paying — so the currency inflates at
the exact point in the game where the player has the most time to farm it. An enchant is permanent,
per-pet, and repeatable, which is the shape a terminal sink has to have.

**Four decisions taken up front, so the rows below are implementation and not design.**

1. **Best-kept-wins, exactly as the Splicer's mutation.** A roll that can lower a pet's stat needs a
   confirm dialog, and a confirm dialog on a gambling button is a click nobody reads. The proven
   pattern is one call: the new enchant is worn only if it beats the one on the pet, and the panel
   never has to ask a question.
2. **Priced in Diamonds and scaled by tier, never by stage.** The 12.15 constraint is DNA-or-not;
   the choice between Diamonds and Shards is that shards already have their sink (the wheel) and
   diamonds are the currency every permanent upgrade is priced in. Tier scales the cost because tier
   is exactly what makes the enchant worth more — `share` is multiplicative, so enchanting a
   Celestial is worth 4.2× enchanting a Normal.
3. **Fixed odds. Luck does NOT enter this roll.** Every other roll in the game is loot; this one is
   a permanent stat multiplier bought with a currency the Lucky pass does not produce, and letting a
   249 R$ pass buy a permanent team multiplier cheaper is the pay-to-win line the pass table has
   stayed behind since Phase 2. The lever here is the price.
4. **A fuse carries the BEST enchant of its four forward.** This is the question 12.15 says the row
   actually turns on. Burning them is defensible for a free currency and indefensible for a paid
   one: enchanted pets are purchases (`FuseRequirement` of them, three today), and a fuse that
   silently voided them would be the worst kind of trap — an upgrade button that destroys value with no warning and no error.

| ID | | Task | Verified how |
|---|---|---|---|
| 13.1 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (eighteenth session), two screenshots --> **`GameConfig` enchant ladder + the fifth argument.** New `GameConfig.Enchants` (ordered ladder, `mult` on the pet's `share`, weights summing to 100 so the panel can print them as percentages), `GetEnchantDef(key)`, `RollEnchant()`, `GetEnchantCost(pet)`, `IsEnchantBetter(a, b)`. `GetPetBonus` gains an optional fifth `enchant` argument, threaded through the **five** call sites 12.15 named (`GameConfig` equipped loop + `GetPetPower`, `MainUI` ×3). Trap: the top rung multiplies a sum, so the ladder must be sized against a nine-slot endgame team, not against one pet |**VERIFIED LIVE 2026-08-14 (eighteenth session) on the cloud place.** The odds are the authored table, measured on the shipped source rather than on a copy: **200,000 rolls** gave Keen 43.875% / Fierce 26.004% / Savage 15.097% / Radiant 8.911% / Prismatic 4.598% / **Eternal 1.516%** against 44 / 26 / 15 / 9 / 4.5 / **1.5** authored, and `AssertEnchantWeights` returns **100** exactly (it warns otherwise, and the live boot log is clean). Cost ladder Normal 20 / Golden 30 / Rainbow 45 / Celestial 70, read off the same pure function the server charges with. The fifth argument is exact and fails safe: the same Golden Legendary scores share **1.280000** bare and **2.112000** with Eternal, i.e. **x1.650000** to six places, an unknown key scores **1.280000** (x1, so every pet minted before this build is unaffected and no `Load` repair is owed), and `luckAdd` rides the same share (15.36 to 25.34) because it is derived from it — one number still moves a pet's whole contribution. `IsEnchantBetter` is strict: better(keen, nil) true, better(keen, eternal) false, **better(keen, keen) false**, which is what stops a re-roll churning the save on a tie. `GetPetPower` reads the entry's own `enchant` (0.160000 to 0.264000), so the index sort, `SortedPetsByPower` and Equip Best all rank an enchanted pet correctly with no call-site edit. **Sized against the team, not the pet**: nine Celestial Legendaries are 30.2 shares (x31.2) bare and x50.9 with the top rung on all nine — the ceiling the 1.65 was chosen against, which is 12.1's lesson one system over |
| 13.2 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (eighteenth session), two screenshots --> **`PetService.HandleEnchant` + the fuse decision made explicit.** New `EnchantPet` remote via `ensureRemote`, rate-limited on the `EGG_INTERVAL` pattern, server-side ownership + Diamond check with the charge and the roll in one non-yielding block, best-kept-wins, reply through `Remotes.Notify`. `HandleFuse` carries the best enchant of the consumed pets onto the fused result, and says so in the fuse notification. Trap: `insertPet` is *not* the only creation point (12.15) — the inline shape in `HandleFuse` is the second one |**VERIFIED LIVE 2026-08-14, driving the real handler and then the real remote.** **The charge is exact and the ladder never falls**: 20 consecutive rolls on a live pet charged **20/20 at exactly 20 diamonds** with **0 downgrades**, the worn rung climbing keen to fierce to radiant to prismatic to **eternal** and never once going back. **The refusal is exact**: one diamond short of the price left the balance *and* the worn enchant untouched, and exactly the price succeeded and left **0**. **The rate limit blocks**: three calls with no wait spent **20**, i.e. one roll. **An unowned petId spends nothing** (0 diamonds, no reply). **The fuse carries the best enchant forward, and the sort is what makes the client honest**: five copies carrying [nil, keen, eternal, fierce, savage] fused to **Golden/eternal** leaving **Normal/nil and Normal/keen** behind — the three strongest went in (`FuseRequirement` is **3** today, not the four an earlier draft of this row assumed) and the best came out. Then the same thing through the shipped client and the real `FusePet` remote: three Golden copies staged keen/eternal/fierce produced **Rainbow wearing Eternal**, with the notification carrying `enchant=eternal enchantName=Eternal` and the world popup reading **"FUSED to Rainbow ✨ Eternal"**. **The client leg of the enchant is real too**: `EnchantPet:FireServer` from the shipped MainUI returned `kind=enchant rolled=radiant upgraded=true cost=20`, and both outcomes draw in the world where they happened — **"ENCHANTED → Savage"** on an upgrade and **"Fierce rolled / KEPT Savage"** on a roll that lost. **The owner's save was snapshotted and put back**, and the honest version of that: two probe fuses fell outside their restore window, so the collection was rebuilt by composition afterwards (+3 Protostar Normal, +2 Protostar Golden, −1 Protostar Rainbow) and re-measured back at **30 pets, Normal 18 / Golden 11 / Rainbow 1, 0 enchants, 62 diamonds, 8 equipped** — the baseline it started at — then saved |
| 13.3 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (eighteenth session), two screenshots --> **The pet card and the Enchant button.** Pet cell grows to fit one action row: the enchant's name in its own colour on the card, the ✨ button quoting the live Diamond price, and the roll's result drawn where it happened (an upgrade and a "kept your Radiant" read differently). Zero new MainUI top-level locals — the button lives inside the existing `refreshPetsPanel` cell build. Traps: `UIGridLayout.CellSize` and the `CanvasSize` arithmetic are two separate numbers for one decision; dark ink on a light card needs the luminance test, not a stroke |**VERIFIED LIVE 2026-08-14 on the shipped client, and the screenshot found the defect the probe could not.** The grid draws **30 cells, 30 enchant buttons**, and the button is the whole row (`✨ ENCHANT 20 💎`, 160x28) until the pet wears something, at which point it shrinks to a **68x28 price button** beside an **84x28 chip** naming the rung. Geometry measured rather than eyeballed: **0 children hanging past a cell's bottom edge, 0 overlapping cell pairs**, cell 232x156 against a card 180x122, canvas **1692 = ceil(30/3) x 168 + 12**, and the odds strip at y 130..152 clear of a scroll starting at 156. `TextFits` **0 failures** over the whole open panel, and again over the fusion panel. The price is quoted from `GetEnchantCost`, the function the server charges with, so the card and the transaction cannot disagree — and the button greys to (176,180,192) when the balance cannot pay it, rather than being hidden or drawn-then-refused. The fusion preview reads the group's best enchant: an 8-copy Protostar group staged with an Eternal quotes **"Normal +15% → Golden +24% (+60%)"** against `GetPetPower` of **0.151773 / 0.242837** with the enchant and 0.091984 without — the ratio is untouched because the enchant rides both sides. **The defect: dark ink inside a near-black stroke, for the third time in three phases (12.3, 12.6, here).** The first cut used a 0.62 luminance threshold, so Keen (0.744) and Eternal (0.833) took dark (58,46,24) glyphs while `themeLabel` was still outlining them in (26,18,36) at 3 px — a fat dark blob with a lighter core, photographed and unmistakable, with `.Text`, `.TextColor3` and `TextFits` all reading correct throughout. It also exposed that the threshold itself was wrong for this palette: every rung is a saturated LIGHT fill by design, so the two mid rungs sat at 0.611 and 0.612 and took **white** ink at about 2.8:1 against 4.5:1 for dark. Fixed as one change: threshold 0.62 to **0.40**, and the stroke is dropped whenever the ink is dark. Re-measured on all six rungs — ink (58,46,24), stroke transparency **1**, `TextFits` true — and re-photographed |
| 13.4 | `[x]` | <!-- coded + pushed + verified live 2026-08-14 (eighteenth session), two screenshots --> **Surfacing**: the odds table where the player spends (so the price and the chances are in the same place), and the top rung announced through `AnnounceService` on the positionless path — a kill-feed line, not a beam, by 12.14's rule |**VERIFIED LIVE 2026-08-14.** The odds strip is built from `GameConfig.Enchants` itself, so it cannot drift from `RollEnchant`: it renders **✨ Enchant odds: Keen 44% · Fierce 26% · Savage 15% · Radiant 9% · Prismatic 4.5% · Eternal 1.5%**, each rung in its own colour shaded −0.35 for a white sheet, `TextFits` true at 728x22 — one strip for the panel rather than a line per card, because the odds are a property of the ladder and thirty copies of one sentence is how a grid becomes unreadable. **The announce gate holds in both directions and its cooldown eats the repeat**: `EnchantRolled` fired with Radiant (no `announce` flag) drew **nothing**, fired with Eternal drew exactly one positionless payload — `[enchant] color=(255,214,92) pos=nil | ✨ ETERNAL ENCHANT! | ...enchanted Pillarion -- x1.65 damage share` — and fired again immediately drew nothing. Positionless by 12.14's rule: an enchant is bought at a button in a panel, so there is no place in the world for a column to stand. The gate is the ladder's own `announce` field rather than a rung name spelled out in AnnounceService — the `IsBeaconRarity` pattern — so a future top rung is a row in GameConfig and no edit there. Only an **upgrade** announces: a re-roll that lands on Eternal and is thrown away because the pet already wears one is not news, and would let a maxed player hold the feed with rolls that change nothing |

---

## Phase 14 — The endgame has no fight left · *opened 2026-08-15 by a measurement, not by a plan*

Opened by closing 11.9. That row owed one real boss fight; the fight was fought, and the boss died
on the first swing. **Kristina chose repair (b) — price the boss against rebirths and only against
rebirths — and both rows below are built and verified live on that decision.**

**The two rows are one change and must be read together.** 14.1 alone takes every boss in the game
from trivially winnable to *arithmetically unwinnable*, because it exposes 14.2: the cap that makes
boss retaliation survivable was never armed, and nobody could see that while the boss was dying
before it got a turn. Shipping 14.1 without 14.2 would have been strictly worse than shipping
nothing.

**The one number.** `GameConfig.BossTargetHits` is **150**, and boss health is derived as
`BossTargetHits × GetZoneReferenceDamage(zone)`. `GetZoneReferenceDamage` is the damage of a
**bare** player standing in that zone — no pets, no Stage Mastery, no rebirths, no passes. Every one
of those four is a permanent multiplier that the boss curve never learned about, and together they
are **×166.6** on this save. So the boss curve is correct for exactly one player: the one who has
just walked in wearing nothing.

**Measured on the owner's real save (stage 20, 4 rebirths, 33 pets), against the hardest boss in the
game — The Absolute at 789,272 HP.** `DNAService.GetCombatDamage` returns **1,175,100**, and the
live `CombatFx` payload from a real swing carried `d=1175100` — the instrument and the game agree to
the digit. The stack: bare **7,053** × upgrades 1.07 × pets 2.42 × mastery 2.68 × rebirth 8.00 ×
passes 3.00.

| rebirths | rebirth mult | free player: damage / swings | pass owner: damage / swings |
|---|---|---|---|
| 0 | ×1.00 | 48,963 / **16.1** | 146,888 / **5.4** |
| 1 | ×2.00 | 97,925 / **8.1** | 293,775 / **2.7** |
| 2 | ×3.50 | 171,369 / **4.6** | 514,106 / **1.5** |
| 3 | ×5.50 | 269,294 / **2.9** | 807,881 / **0.98** |
| 4 | ×8.00 | 391,700 / **2.0** | 1,175,100 / **0.67** |
| 6 | ×14.50 | 709,956 / **1.1** | 2,129,869 / **0.37** |

Bare stage-20 damage is 7,053, i.e. **111.9 swings** — near the authored 150, so the derivation was
never the broken part. A player with a normal bag and no rebirth at all is already down to **16
swings**. **A pass owner one-shots the final boss at three rebirths**, and the rebirth ladder does
not stop there. The observable symptom is that the screen-space boss bar 11.9 built never renders at
all: the boss is removed inside the frame that drew it.

| ID | | Task | Verified how |
|---|---|---|---|
| 14.1 | `[x]` | <!-- decision (b) taken by the owner 2026-08-15; coded + pushed + verified live the same session --> **A boss is priced against rebirths, and only against rebirths.** New pure `GameConfig.GetBossDamageDivisor(data)` returning `GetRebirthDamageMult(data)` floored at 1; `BossService.onHit` divides the blow by it, floored and floored-at-1 so the health attribute stays an integer and no rebirth can round a blow to nothing. **Applied on the damage side rather than the health side because a boss is SHARED** — `Health` is one model attribute and two players chip one pool, so there is no per-player health to scale; the arithmetic is identical (`blows = health × factor / damage` either way) and it is the more correct of the two for a shared pool, since each player's contribution is normalised to their own progress instead of to whoever arrived first. Rejected: pricing against the player's whole stack, which is the `BOSS_MIN_HITS` clamp 11.9 removed and the `damageCap` 9.1 removed |**VERIFIED LIVE 2026-08-15 against Boss_AbsolutePlane**, real `TeleportToZone` + real `AutoAttack` at the shipped 0.34 s cadence. The blow went from **1,175,100 to 146,887 — exactly ÷8.00**, the rebirth multiplier at 4 rebirths, and the health bar that had never rendered now steps visibly: **789,272 → 642,385 → 495,498 → 348,611**, three equal bites of 146,887. Swings to fell went **0.67 → 5.37**, the predicted number to two decimals. Nothing else moved: creature damage is untouched (the creature beside it still takes the full 1,175,100), and the boss path sends only `bossBar` (hp, max) and never a damage number, so the division has no figure on screen a player could read as wrong. **Left uncancelled on purpose, and worth stating plainly:** pets ×2.42, Stage Mastery ×2.68, the Income upgrade ×1.07 and the passes ×3.00 still shorten the fight by their full amount, so a geared pass owner faces roughly **3–6 blows** where a bare arrival faces 150. That is the decision, not a defect — but it is the number to revisit first if the last boss still reads as short |
| 14.2 | `[x]` | <!-- found 2026-08-15 while verifying 14.1; coded + pushed + verified live the same session --> **The cap on incoming boss damage was never armed.** `hurtPlayer(player, amount, requiredHits)` clamps a blow to `MaxHealth / (requiredHits × 2)`, and a 10-line comment above it explains that this is what stopped bosses from zones 11+ being unbeatable by any build — but **`requiredHits` was optional and not one of the four call sites passed it**, so the branch never ran and raw `retaliateDamage` / `auraDamage` were applied in every boss fight in the game. It was invisible only because the boss died before it could swing back. New local `blowsToFell(bossHealth, playerDamage)` is passed at all four sites (both zone-boss sites compute the player's real post-14.1 damage; the two Colosseum sites use their own `EVENT_MIN_HITS` floor). Passing the **fight's real length** rather than a constant is what makes it scale-free: the `blows` term cancels, so retaliation costs ≤ 0.49 × MaxHealth and the aura ≤ 0.21 × MaxHealth over a fight of *any* length |**VERIFIED LIVE 2026-08-15, and the fight was won.** Before: The Absolute retaliates 1,248–1,638 on 98% of blows against a measured player maximum of **2,924** — **2.0 blows survived** for a fight needing more than five, and the probe died on blow 3 with the boss at 348,611 (44%), which is the wall the comment claims was removed, still standing. After: the same fight, the same save — incoming blows **487, 487, 264** against a cap of `2924 / (3 × 2) = 487.3`, **exact to the decimal**, boss felled in 3 swings, **survived at 1,715 / 2,924 = 58.7%**. Then checked analytically across **all twenty zones for a player who has just walked in** (`GetZoneReferenceDamage`, i.e. no pets, no mastery, no rebirths, no passes): the fight is **150–180 blows** everywhere — the authored `BossTargetHits` of 150 — and total incoming runs **30.0% of max health in Forest to 70.2% at The Absolute**, so every boss in the game is now finishable bare, and the worst case lands on the predicted 0.49 + 0.21 = **0.70** |

---

## Phase 15 — The Gemini audit · *opened 2026-08-15 by a screenshot*

Kristina photographed the Daily Rewards board after the twenty-fourth and twenty-fifth sessions'
UI work and every readable string on it was a solid black blob. The capture is the whole reason
this phase exists: **all five sessions of that work reported `luastruct.py` clean and `luanames.py`
matching baseline, and both statements were true.** A probe reads the model; only a render shows
colour, overlap and occlusion (`roblox-gui-probe-blind-spots`).

**The two rules the UI work broke, both already written down in this file's own comments:**

1. **A colour is not a permission.** `styleCard` / `applyShell` were changed to hand the 6px cyan
   panel rim to anything filled white — a test that a 24px "Day X" pill, the code input, the
   Playtime progress track and every white card in the game all pass.
2. **Dark ink and its outline are one decision.** `themeLabel` outlines every label in
   `Color.Outline`; text authored at rgb(24,18,38) is then a glyph inside a halo of its own colour.

**And one class of defect no tool here could see**, which is why `tools/luascope.py` now exists:
a name that is bound *somewhere* in the file but not *where it is used*. Two shipped instances,
both fatal to the feature that contains them, both invisible to a compile check.

**⚠ THE ROWS BELOW WERE ALL `[~]` FOR ONE ENVIRONMENTAL REASON, AND IT IS FIXED.** No session
between the fixes being written and 2026-08-15 could run or photograph the game. **Closed
2026-08-15: 15.1, 15.2, 15.3, 15.4, 15.6, and a new 15.9.** Only **15.5** is still open, and its
blocker is real rather than environmental — it needs two clients, and Studio's Play Solo is one.

**Then the thirtieth session went to run that two-client check and found it was unrunnable: there
was no button in the game that starts a trade** (15.11). That is now three defects in this one
feature, all of the same family and none of them visible to any static check in this repo — a name
out of scope (15.5), a remote that did not exist when the client looked (15.9), and a remote nothing
ever fired (15.11). The lesson the phase keeps re-teaching, sharpened: **running the row's own check
means opening the feature the way a player would, and the first thing that finds is whether a player
can open it at all.**

**What the captures were worth, stated plainly, because this phase exists to answer that:** they
closed five rows *and found two more defects that no probe in this repo reports* — a bright label on
a bright card with its outline zeroed (15.1's own regression) and a remote that never existed when
the client looked for it (15.9). Both were invisible to `luastruct.py`, `luanames.py`, `luascope.py`
and a Luau compile alike. The rule that produced them is worth keeping: **run the row's own check as
written, and when it names a surface, look at the whole surface rather than at the thing the row
claims to have fixed.**

<!--
  2026-08-15, twenty-seventh session — the diagnosis above this line was wrong and the correction
  matters, because it is what the next session will act on. The `roblox-studio` server WAS
  registered for Claude Code (local scope, in `.claude.json`); it was *dying at startup*.
  `%LOCALAPPDATA%\Roblox\mcp.bat` resolves `StudioMCP.exe` from the registry's `ContentFolder` and
  from a hardcoded fallback, and a Studio update had made BOTH name `version-d679641ad17741aa`,
  a folder the updater had already deleted — so the batch exited 1 and the client simply listed no
  tools, with no error anywhere in the transcript. Studio itself was running fine the whole time,
  from `version-43f4e18b18f24d5a`. `mcp.bat` now scans `Versions` newest-first for a folder that
  actually contains the exe (backup: `mcp.bat.bak`), and that binary handshakes on the first try.
  A repaired batch does not revive a live session — the tools return on `/mcp` reconnect or restart.
  Also true and unchanged: the fixes for 15.1–15.6 exist in `src/` only. `Evolution-lab.rbxl` was
  saved 02:30 and those files were written 03:39–03:48, so the push over the HTTP bridge
  (`evolution-lab-studio-http-bridge`) has to happen BEFORE any capture, or the capture photographs
  the broken build and the row gets closed on the wrong evidence.
  DONE, same session: Studio's copies were confirmed to be the OLD code first (its `MainUI` still
  held "Chimpanzini" and had no `darkInk` branch at all), then all three were pushed and came back
  byte-identical to `src/` — UITheme 68008/306018008, TradeService 30672/980945299, MainUI
  441689/107390350. Every capture below was taken after that.
-->


| ID | | Task | Verified how |
|---|---|---|---|
| 15.1 | `[x]` | <!-- verified live 2026-08-15 by two captures; the check found a regression this row itself caused, fixed below --> **Dark ink drops its stroke, in the same branch.** `themeLabel` now measures the luminance of a colour passed in on purpose and calls `OutlineText(label, 0)` below 0.45. Nothing bright moves; the branch can only fire on ink that was already inside a halo of its own colour. The cut is 0.45 because this palette's dark ink is at 0.077 and its greys sit at 0.48–0.60 — a threshold belongs to a palette, not to a codebase | Open the Daily board and **read** it: the day pills, the DNA amounts and the hero card's line are words, not blobs. Then the Journal detail card and the pet rows, which use the same helper with rgb(46,54,74) | **live, two captures.** Daily board: every string reads as words — day pills, `200/450/1.00K/2.20K/4.80K/10.50K/23.00K DNA`, the hero line, the code field, the footer. Journal: the `⚔️ N` kill counts measure ink **0.259 with stroke Thickness 0.0** and the section headers 0.619/0.211 likewise, while everything bright keeps its 3–4px outline (`Pip`, `Icon`, `Title` all ink 1.000, stroke 3.0–4.0) — so the branch fires on exactly the ink it was written for and nothing else moved. **The check also found what the row broke:** `DetailName` on the Journal's detail card is AUTHORED dark (46,54,74) and REPAINTED bright at runtime with the character's colour, and it rendered at ink **0.900 on a 0.953 card with no outline at all** (difference 0.052 — a ghost instead of a blob). Cause: this row zeroes the stroke's *Thickness*, and `inkOnLight` — the 12.3 helper that exists to switch the outline back on for exactly these five labels — moved only *Transparency*, so it had nothing left to switch. `inkOnLight` now restores both; re-measured `DetailName` stroke **th=4.0 trans=0.00** and "The Final" reads gold-on-white in the capture |
| 15.2 | `[x]` | <!-- verified live 2026-08-15: a stroke sweep over five panels, zero cyan inside any of them --> **The cyan rim belongs to a panel, and only `registerPanel` knows what a panel is.** The fill-colour branch is gone from both `styleCard` and `applyShell`; the rim is applied in `registerPanel` (near-white test, so all three panel whites qualify) and in `UITheme.Modal`. The inventory panel's hand-set SkyBlue rim is retired into it — every panel now wears one rim | Open any two panels: the shell has the 6px cyan rim, and nothing INSIDE either does. Specifically the Daily day pills (3px dark), the code input, and the Playtime progress track | **live, measured rather than eyeballed.** Every `UIStroke` under five panels was swept — `RewardPanel`, `PlaytimePanel`, `InventoryPanel`, `TradeModal`, `GroupRewardsPanel`. Each root carries exactly one rim, **6.0px rgb(0,180,255)**, and the count of cyan strokes *inside* is **0 in all five** — including `InventoryPanel`, whose hand-set SkyBlue rim is the one this row retired into `registerPanel`. The three named specifics: all 7 day pills read **3.0px rgb(26,18,36)**, the code `TextBox` has **no stroke at all**, and every gift tile on the Playtime panel is 4.0px rgb(26,18,36). Captures of the Daily board, the Journal and the Welcome Back card all show the rim on the shell and nothing cyan within |
| 15.3 | `[x]` | <!-- verified live 2026-08-15: one capture, and all 7 cards cross-read against GameConfig.DailyRewards --> **The Daily board says what the day pays.** Day 7's card read "Chimpanzini Bananini" — a pet that day does not grant (it is 23,000 DNA, a potion, 2 diamonds, 3 shards); the hero pill and the OP badge overlapped by 27px; and a second fixed footer line was added underneath `rewardBannerCard`, which already says the same thing with the real day number | Open the board: day 7 quotes DNA like every other card, the OP badge clears the pill, and there is one footer, not two | **live capture, and checked against config rather than against the reference image** — which is the lesson this row exists for. Day 7 reads **23.00K DNA · 🧪x1 · x3 · x2**; `GameConfig.DailyRewards[7]` is `dna=23000, potions=1 (dna_l), shards=3, diamonds=2`. All seven agree: 200 / 450 / 1.00K+🧪x1 / 2.20K+🧪x2 / 4.80K+🧪x2 / 10.50K+🧪x2+💎x1 / 23.00K. The **OP!** badge sits left of the "Day 7" pill with clear air between them, and there is exactly **one** footer — the purple `rewardBannerCard` reading "Come back tomorrow for Day 6!" |
| 15.4 | `[x]` | <!-- verified live 2026-08-15: the card opened on a synthetic first payload and printed the both-ready subtitle --> **`WelcomeBackPanel` threw on the first payload of every session.** The redesign deleted the hand-built `local sub` and left the write to it 200 lines below, so `sub` was a nil global inside `maybeWelcomeBack` — the one function that opens the card. Now captured from `PanelHeader`'s fourth return. Its height was also 2px shorter than its own two rows, so the second card hung over the shell's rim (276 → 294) | Join with an unclaimed daily: the card opens, and its subtitle reads "Two things are waiting for you." when the Season Pass also has claims | **live, and the save was never touched.** Kristina's save has today's daily already claimed, so the branch was reached the way [[evolution-lab-reaching-join-only-branches]] describes: a real `DataUpdate` payload was captured on the client, copied on the server with `LastRewardClaim` moved back two days and `Season.claimedFree` emptied, then **re-fired in a tight loop while a fresh `MainUI` clone was parented**, so the doctored copy is the clone's genuine *first* payload (the flood matters — `shown` is set by whichever payload arrives first, so a real one landing ahead of it burns the test). Result: `WelcomeBackPanel.Visible = true`, subtitle **"Two things are waiting for you."** — the exact line that used to be a nil-global write — over rows reading "🎁 Daily reward — Day 1 is ready" / "💔 Your streak ended" and "🏆 Season Pass — 9 to claim". Geometry: panel **h=294**, rows y=90..278, so 16px of clearance; at the old 276 they overhung by 2. Nothing here is client-only theatre except the payload itself, which no save ever saw |
| 15.5 | `[x]` | <!-- CLOSED 2026-08-15, thirtieth session, on a real two-client run; history below kept --> <!-- 2026-08-15, twenty-ninth session: the server chain and the real client draw are now both proven; what is left is one more Player object --> **`TradeService.resolveOfferPets` called `petIndexById` 71 lines above its `local function`** — a nil global, so every `pushSession` threw and no offer could ever be drawn. Moved above its caller | Two clients on the published place: open a trade, offer a pet, and see it appear in both grids (this is 8.6's own check) | **Nearly closed, and the gap is now exactly one second `Player` object — not the chain, and not the drawing.** The whole real sequence `Request → Accept → SetOffer → pushSession → resolveOfferPets` was run against the shipped file with the real player as side A and a synthetic userId as side B, and every push was a **real `TradeUpdate:FireClient` at the real joined client**. Measured on it: the window opened by itself and drew **3 tiles in `You (Your Offer)`** (the three real unequipped pets whose ids were offered — 🗼 Pillarion, 🗼 Pillarion, Sparky) against **3 in `Partner's Offer`**. Then `Confirm(me)` flipped my side to **"✅ Ready!"** with the partner still **"⏳ Deciding…"** and the button to **"Waiting…"**; then changing the *partner's* offer to one pet cleared **both** confirmations back to "⏳ Deciding…" with the button back to "Confirm Trade" and the partner grid redrawn to **1 tile** — which is 8.5's anti-scam rule verified on a drawn client rather than in the server's own return value. `Cancel` closed the window (`Visible=false`) and released everything (`GetSession → nil`). **Two things make this safe to have run and worth reading before repeating it:** `require` from `execute_luau` returns a *fresh* `PlayerDataService` whose `Cache` is empty (measured again here: 0 entries while a real player was loaded and playing), so the fixture is isolated from the live services and cannot reach the real save — proven after, the save still holds **100 pets, 0 with a probe id**; and `Commit` must **never** be run this way, because it calls `PlayerDataService.Save(player)` on that *fresh* instance, which would write the doctored copy over the owner's real key. Nothing was confirmed on both sides and the trade log stayed at **0**. `withinReach` returns true only when *neither* side has a character, so `player.Character` is detached for the duration of the single `Request` call and put straight back. **What is still unproven, precisely:** the `pB` branch of `pushSession` drawing on a second client, and the client→server direction (`TradeRequest` / `TradeAccept` / `TradeSetOffer` fired by a human's clicks) — the service was driven directly here, and `Request` cannot be reached through the live remote because `dataOf(toUserId)` needs a second loaded player. Also found on the way: the scope fix alone would still have shipped a dead feature — see **15.9** <!-- 2026-08-15, thirtieth session --> **UPDATE: the client→server half of that sentence is now proven, and the reason this row could not be closed by simply opening two clients is a third bug — see 15.11.** Real `FireServer` calls on `TradeRequest` arrive at the live server (`OGLightninggXD -> 5746881443` / `-> 99999999`, refused with "You cannot trade with yourself" / "That player is not ready", `sessions 0` after), and a **real mouse click** on the invite prompt's Accept button arrives as `OGLightninggXD accepted probe-no-such-session`. So the remotes are bound and the human path into them works. **What remains is exactly the `pB` branch and a second offer grid**, and nothing short of a second `Player` reaches it: `execute_luau`'s `require` returns a fresh `TradeService` with its own `sessions` table, so any fixture built there is invisible to the live remotes a human's clicks travel through. 15.5 and 15.11 now close on the same single two-client run. <!-- CLOSED --> **CLOSED on Studio's `Clients and Servers` with two real `Player` objects (Player1 / -1 and Player2 / -2), driven entirely by real mouse clicks.** The `pB` branch draws: both `TradeModal`s opened at once, each showing the other's name (`Player2's Offer` / `Player1's Offer`), and when Player1 clicked Sparky in the inventory picker it appeared in **Player2's partner grid** -- `partnerTiles = 1`, `partnerNames = "Sparky"`, wire `myOffer=1 partnerOffer=1` -- then Pebble came back the other way and both grids on both screens showed both pets. **The commit is proven by id**: Sparky `b436693d-8ea7-4a69-915d-a9f3bb5d26a8` and Pebble `2d9de2c6-a2b9-4c78-888a-a4137a5e92d2` swapped owners, each save ending with exactly the other's pet. Full state sequence on the wire: `open -> open(1,0) -> open(1,1) -> countdown -> completed`, with `🤝 Trade complete!` on both clients and both windows closing themselves. Photographed on both screens. |
| 15.6 | `[x]` | <!-- verified live 2026-08-15: every claim in this row's own check measured on a drawn trade window --> **The Trade and Group panels had no shell at all** — Roblox's default grey rectangle, square corners, no border, behind correctly-styled contents. Both now take the same `styleCard(panel, PANEL_SHELL, …)` line every other panel uses. The trade panel's strings were also authored at fixed 11–15px against the pre-redesign dark HUD (its inventory well was navy rgb(15,18,26) inside a white panel) and are through `themeLabel` now; and its rarity borders read `UITheme.Color[pet.rarity]`, keys that table has never held, so every tile was the same grey — `GameConfig.GetRarity` is what the rest of the game reads | Same two clients: the trade window is a white panel with a cyan rim, its pet tiles carry their rarity colour, and no string is under 14px | **live capture, with the window opened by a synthesised `TradeUpdate` rather than by a second player** — every claim this check makes is about the drawn window, and all three were measured on it. Shell: `TradeModal` root stroke **6.0px rgb(0,180,255)** on white, 0 cyan strokes inside (same sweep as 15.2); `GroupRewardsPanel` likewise, so both new panels now have the `styleCard` line. Rarity: fed one pet per rarity, the tiles came back **six distinct colours** — Common rgb(198,202,214), Uncommon rgb(110,224,130), Rare rgb(90,170,255), Epic rgb(190,110,255), Legendary rgb(255,190,60), Secret rgb(255,64,160) — against the single grey they all shared when the lookup was `UITheme.Color[pet.rarity]`. Text: **0 labels under 14px** across the whole modal. Two cosmetic leftovers, neither in this row's check: a long pet name truncates on a tile ("Thorn…"), and the "Deciding…" chip sits tight under the grid titles |
| 15.7 | `[x]` | <!-- verified by the two live-fatal bugs it found on its first run, plus a synthetic case --> **`tools/luascope.py`, the check the other two cannot make.** `luastruct.py` proves the blocks balance; `luanames.py` proves a name exists somewhere in the file and is *documented* as not scope-aware. This one walks a scope stack and proves a name is visible where it is read. Its baseline is recorded in its own docstring | **Found 15.4 and 15.5**, neither of which any other tool in this repo (or a Luau compile) can see, and reproduces on a five-line synthetic case. Clean over all 59 mirrored scripts otherwise |
| 15.9 | `[x]` | <!-- found and fixed 2026-08-15 while trying to photograph 15.6; before/after both measured live --> **The trade UI could never receive anything, on any server, and the `if` around it made that silent.** `MainUI` binds with `local tradeUpdateRemote = Remotes:FindFirstChild("TradeUpdate")` and wraps the connect in `if tradeUpdateRemote then`. `TradeUpdate` and `TradeInvite` are *not* created by `TradeService.Init` — they are created by `ensureRemote` inside `pushSession` and `Request`, i.e. **at the moment of the first trade**, which is always after every client has already looked. So the lookup returned nil, the connect was skipped without a word, and 15.5's scope fix would have shipped into a feature that still could not draw an offer. `Init` now calls `ensureRemote("TradeUpdate")` and `ensureRemote("TradeInvite")` eagerly, next to the five inbound remotes it already made | **both states measured on a live join.** Before: `Remotes` held only the five inbound trade remotes at boot, and a real `TradeUpdate:FireClient` left `TradeModal.Visible = false` — nothing was listening. After the one-line fix and a Play restart: all **seven** are present at boot (`TradeAccept, TradeCancel, TradeConfirm, TradeInvite, TradeRequest, TradeSetOffer, TradeUpdate`), the same payload opened the window by itself, and both offer grids drew. This is the class `luascope.py` cannot see either — the name is in scope, the *instance* is not there yet |
| 15.10 | `[x]` | <!-- 2026-08-15, twenty-eighth session: the row was opened as a nil-global typo and closed as a backdoor removal --> **`LightConfig` was never a lighting library. It is a backdoor from an infected free model, and it is deleted — all three scripts and the `NumberPose` that carried its payload id.** The row was opened by `luascope.py` finding `isPositiveInt(number)` testing a nil `value` at `Type.lua:183`; reading the file to fix that one line is what exposed the rest. **The chain, decoded and confirmed live:** `LightConfig.server.lua:37` names a function `FindFirstChild` that calls nothing of the sort — `getSignal(Game)` returns `MarketplaceService, MarketplaceService.GetProductInfo`, so line 40 is really `MarketplaceService:GetProductInfo(Pose.Value).Description`; `getArchetype` then `gsub`es every character of that description to its **byte value**, concatenating them into a second asset id, which is written back into `Pose.Value`; and line 86, `require(script.EasyConfiguration.Pose.Value)`, executes it. **`checkChild(root)` is the arming switch and it reads `root['JobId'] ~= ''` — empty in Studio, a GUID on a live server** — so the `if not FindFirstChild('Workspace') then return end` guard above it makes the payload run *only* in production, which is why five months of Studio work never saw it. Measured, not inferred: `Pose` is a **`NumberPose`** (an animation class, picked because nobody looks at one) holding **90983637061475**; that asset resolves to "💀 Noli Forsaken Anims Oficial Pack" by `RonyxDeveloper` (10805192093) with the description `X<E5!'G`, and byte-encoding those seven characters gives **88606953333971** — the module that would have been required. It was **not** fetched. **It never ran here:** the Script sits in `ServerStorage` (where Scripts do not execute) *and* carried `Disabled = true`, and `git log --diff-filter=A` puts it in the very first place extraction, so it predates every agent commit — it came in with a free model, not with this project's work | **live in Edit, and the whole datamodel was swept rather than just this branch.** Before: **61** `LuaSourceContainer`s in `game`, three of them `LightConfig` / `.Type` / `.EasyConfiguration`; the sweep also proved there is no *other* script anywhere outside the 59 mirrored ones — nothing loose in `Workspace`, `StarterGui`, `StarterPack` or `Lighting`, which is where a second copy of this pattern would hide. After `:Destroy()`: **58**, and a re-scan for the names `LightConfig` / `Pose` and the class `NumberPose` returns **0 matches anywhere in the game**. `luascope.py` and `luastruct.py` both run clean over all 56 remaining mirrored scripts (the only finding left is 15.8's known `VILLAGE_CREAM`). **👤 OWNER, and it is the only part left: this deletion lives in the unsaved Studio session — save the place and republish, or the published copy keeps the file.** It is inert there for the two reasons above, so this is hygiene, not an emergency |
| 15.8 | `[x]` | <!-- 2026-08-15, twenty-eighth session: fixed, rebuilt at BUILD_VERSION 133, measured across all 21 zones --> **`ZoneBuilder` painted the banner emblem and the two crossbar knobs with a nil colour, in every village in the game.** `VILLAGE_CREAM` was declared beside the `VILLAGE_STYLE` table that reassigns it per zone — which reads well and compiles — ~170 lines *below* the three sites in `addZoneProps` that read it, so those resolved to a nil **global**. The four village-palette locals now sit immediately above `addZoneProps`, with the note kept where they are documented and reassigned; `applyVillageStyle` is still the only writer, so nothing about the per-zone palette changed. `BUILD_VERSION` **132 → 133** — colour is baked into the part at build time, so the fix is invisible without the bump. **Correction to this row as it was written: the crate lid is not one of the three.** Line 1611 takes the `Vill_Crates` mesh branch and `continue`s, so the five-primitive crate (lid included) is a fallback that has not built since the prop meshes landed — `CrateLid` count in the rebuilt world is **0**. The row's own check is therefore unrunnable as authored, which is itself the finding | **live, and measured rather than photographed, because cream against grey is exactly the comparison a screenshot is worst at.** Rebuilt in Edit from a fresh clone: the world went from stamp **128** (two versions stale — it had never been rebuilt in Edit since 12.9/12.12, both of which only ever ran in Play) to **133**, 21 zones, all 20 carrying `Complete = true` and 105,099 descendants. Every `BannerEmblem` in the game now carries its own zone's cream — 19 distinct values, x14 per zone and x28 in double-width Forest, e.g. Forest (252,244,226), CelestialThrone (248,214,118), AbsolutePlane (126,112,168) — against the single (163,162,165) they all held before. Same for the crossbar knobs: **no `Knob` anywhere in the world is at Roblox's default grey**, 34 per zone at that zone's cream. A world-wide sweep for the default grey returns 4,696 parts and **not one of them is a village prop** — they are `body_geom`/`head_geom` mesh shells that take their colour elsewhere, plus billboard anchors (`EggOddsAnchor`, `PriceCardAnchor`), `StallFill` and `SignPart`, all pre-existing. Capture: the two Forest banners, cream emblems on the cloth and cream knobs at both crossbar ends |
| 15.11 | `[x]` | <!-- 2026-08-15, thirtieth session: found while preparing 15.5's own two-client check, which turned out to be unrunnable as written --> **Nothing in the game could start a trade, so nobody could ever receive an invite either — the whole feature was unreachable from the HUD.** `TradeService.Init` has bound `TradeRequest.OnServerEvent` straight into `TradeService.Request` since 8.6; the invite prompt in `MainUI` has always been able to answer one; the modal draws whatever a session pushes at it. But **`grep -rn TradeRequest src/` returned exactly one line and it was the server's** — no button anywhere in this game ever fired it. Every part worked and there was no door. This is 15.9's shape at one remove: there the client looked for a remote that did not exist yet, here the client owns the one half of the conversation nothing speaks, and neither is visible to `luascope.py`, `luastruct.py` or a Luau compile because every name involved is in scope and simply never called. Fix is a **Trade tile (L4) and a player picker**: it lists everyone else in the server, labels each one *in range* or *walk closer* against the real radius, and its Ask button fires `TradeRequest`. Two supporting decisions — the tile is created **at the top of the file and held by no local** (the responsive column pass collects its tiles once, so one created 8,000 lines below is never laid out, and this file is at Luau's 200-register ceiling; the trade block finds it back as `screenGui.TradeButton`), and `PROXIMITY_STUDS` **moved into `GameConfig.TradeProximityStuds`** the moment a second reader appeared, the same move `MaxOwnedPets` made — a client printing "in range" off its own copy is a client that will eventually promise a request the server refuses. The Ask button fires **even when the row says "walk closer"**: the server answers a refusal with a real Notify, and a button greyed out by the client's own guess would answer with silence | Two clients: the Trade tile lists the other player, Ask puts the invite on their screen, Accept opens the window on both | **Everything that does not need a second `Player` is proven live, including the direction that had never been proven at all.** The tile is drawn and laid out by the responsive pass (`ColumnSide=L`, `ColumnOrder=4`, 82px at y=445 — the pass's own arithmetic, `121 + 3 × 108`), and a **real mouse click on it** opens the picker: 460×420, shell stroke **6.0px rgb(0,180,255)** and a gradient keypoint-identical to `GroupRewardsPanel` and `TradeModal` (`0.00:255,255,255 \| 0.42:255,255,255 \| 1.00:183,183,183`, rot 90), so it is the same panel as every other panel rather than a lookalike. Subtitle renders **"within 40 studs"** read from `GameConfig.TradeProximityStuds`, the number `TradeService` now enforces. Empty state draws in a solo server. **The client→server direction, which 15.5 listed as unproven:** two `TradeRequest:FireServer` calls arrived at the live server as `OGLightninggXD -> 5746881443` and `-> 99999999`, the service refused both with its own reasons (**"You cannot trade with yourself"**, **"That player is not ready"**) and left `sessions 0, reservedPets 0, logged 0`; then a **real mouse click on the invite prompt's Accept button** — the prompt raised by a real `TradeInvite:FireClient` — arrived as `OGLightninggXD accepted probe-no-such-session`, which `Accept` refuses with **"That trade has gone"**. Also learned and worth keeping: the prompt **hides itself after 15 s**, which is why the first two clicks at it reached nothing. **What is left needs the same second `Player` 15.5 needs** — the picker's rows and its Ask button cannot be drawn or clicked in a solo server, and the live session they would open cannot be reached any other way: `execute_luau`'s `require` hands back a *fresh* `TradeService` with its own `sessions` table, so a fixture built there is invisible to the live remotes a human's clicks go through. <!-- CLOSED --> **CLOSED on the two-client run.** A real click on the Trade tile opened the picker; it listed **one row, `Player_-2`, reading `👤 Player2`**, with the empty state hidden and an Ask button; a real click on Ask put **`Player1 wants to trade with you`** on Player2's screen, and a real click on Accept opened both windows. Photographed. **The run found two defects of its own -- see 15.18 and 15.19 -- and one of them is in this row's own code.** |
| 15.13 | `[x]` | <!-- 2026-08-15, thirtieth session: written because 15.11 was the third defect of its family and the first two were both found by eye --> **`tools/luaremotes.py`, the fourth lint — the first one that reads two files at once.** The other three each ask a question about one file: `luastruct.py` proves its blocks balance, `luanames.py` proves a name exists somewhere in it, `luascope.py` proves a name is visible where it is read. **All three were clean over this whole repo on the day 15.11 was found, and the trading feature was completely unreachable**, because the defect was not inside any file — the server listened and nothing in the game spoke. This one pairs every remote's senders against its listeners across the whole tree and reports any remote with only one side. **The side is taken from the API, never from the path** (`FireServer`/`OnClientEvent` only exist on a client, `FireClient`/`OnServerEvent` only on a server), which is why a shared `ReplicatedStorage` module never has to be classified. It resolves four naming forms, including one helper deep (`remote():FireAllClients(…)`), and anything it cannot resolve is **dropped rather than guessed at** — so a clean run is the absence of one shape, not a proof of reachability. A **second check** reports, as a warning rather than a failure, every one-shot `X.OnClientEvent:Connect` where `X` came from a non-blocking `FindFirstChild` — 15.9's shape, which is fatal only if the server creates that remote lazily, and that is not in the file | **It reproduces 15.11 and it found 15.12 on the same run.** Run against the commit before 15.11's fix it prints `TradeRequest -- the server listens for it and NO CLIENT EVER FIRES IT`; run against the fix it does not. On the current tree: **0 findings** over 51 resolved remotes in 50 files, and **3 warnings** — `TradeUpdate` / `TradeInvite` / `OpenGroupRewards`, all currently safe because their `ensureRemote` sits in an `Init`, and all of which become 15.9 again the day somebody moves it. Getting there cost three of the tool's own false positives and each was a real lesson about this codebase: the `Remotes` **folder** is fetched by the same `WaitForChild` call the remotes are; `Instance.new("RemoteEvent")` in a find-or-create block binds the local to a **class name**; and a binding is a **position, not a name** — `MainUI` alone binds a local called `remote` to eleven different remotes, and keeping the first made six live features look unreachable |
| 15.12 | `[x]` | <!-- 2026-08-15, thirtieth session: found by luaremotes.py on its first clean run, and measured on both sides of the fix --> **`CollectClick` was an exploit-only DNA faucet — a paying server handler that nothing in the game could call.** `DNAService.Init` connected `Remotes.CollectClick.OnServerEvent` to `DNAService.HandleClick`, which credits `GetClickAmount` and pushes the save. It was **hardened**, and correctly: a 0.07s interval cap (14/s, above what a hand can do) with the whole-save reply throttled separately, written against precisely the `while true do CollectClick:FireServer() end` attack its own comment names. What none of that survives is the game moving on — DNA per swing now comes from `CreatureService` reading `GetClickAmount` directly, and the two `+` pills in the HUD open the Robux shop. **Nothing fired `CollectClick`.** A handler that pays currency and has no legitimate caller is not dead code: the only software that can reach it is software written to cheat, and a rate cap then sets the exploiter's income rather than denying it. This is 15.11's finding read in the mirror — same tool, same run, same sentence from the linter, opposite meaning: there the server listened and the game never spoke, here the server listened and only a cheat client would. The connection is gone, with `HandleClick`, both throttle tables and the `PlayerRemoving` handler that existed only to clear them. **The RemoteEvent instance is deliberately left in the saved `Remotes` folder** — deleting it is a place edit rather than a code one, an unconnected RemoteEvent does nothing, and a `Remotes.CollectClick` index in a copy of the file that had not been updated would hard-error a whole service at boot | Fire `CollectClick:FireServer()` in a loop on a live client and watch DNA not move, against a control | **measured live on BOTH sides of the fix, three arms per side, all bracketed inside one client call so no round-trip lands between a reading and what it measures.** Each arm is 4 seconds; the exploit arm sends **~1,600** `CollectClick:FireServer()`. **Before** (the previous commit's file pushed back into Studio and Play restarted): control **1.711e13**, exploit **5.018e14**, control **1.711e13** — the faucet paid **29.33x** the passive income of the same four seconds, with a flat control either side of it. **After**: **1.711e13 / 1.711e13 / 1.711e13** — the three arms are *identical*, so ~1,600 calls paid exactly nothing. `DNAService.HandleClick` is nil on the shipped file, and `Init` still runs past where the deleted block was (`EquipCharacter`, created below it, is in the folder). **One side effect, stated plainly: the before-arm credited Kristina's real save ~5e14 DNA** — 0.001% of a balance of 5.05e19, kept rather than unpicked |
| 15.14 | `[x]` | <!-- 2026-08-15, thirtieth session: found while removing 15.12's dead branch; 87 real kills either side of it --> **The crit is a x5 payout and the game has never once told a player it happened.** `DNAService.GetClickAmount` rolls `clamp(5 + luck * 0.5, 0, 75)` percent for **x5** and returns `(amount, wasCrit)` — and `CreatureService`, the only thing that pays DNA any more, took the number and **dropped the flag on the floor**. The one place that ever announced a crit was `DNAService.HandleClick`, behind `Remotes.CollectClick`, which nothing has fired for as long as combat has paid the DNA (15.12) — so `MainUI`'s `kind == "crit"` toast and `SoundLibrary`'s crit row have both been **unreachable rather than merely rare**, and a player can buy Egg Luck up to a **75%** crit rate and never be told. The crit now rides the kill's existing `CombatFx` payload as `cr` (nil on an ordinary kill, so the commonest packet in the game does not grow a field for everybody — the same rule `sh` follows) and is drawn as the DNA pop it already was, in gold, saying so. **No toast**: it is a fact about one creature, and this HUD's own rule is that those belong where they happen. `MainUI`'s dead `crit` branch is deleted; `NOTIFY_SOUND.crit` and the `NotifyRank` row are left alone, being inert rows rather than branches | Kill things and watch a crit say so where it happens, at the right multiplier | **measured on 87 real kills through the real `AutoAttack` remote, and the multiplier is exact.** A second listener on the live `CombatFx` tallied every kill packet, keyed by the tier's size — the only tier identity on the wire — so a crit and a non-crit **of the same tier** could be divided. Result, three tiers with both: size 6.5 → **5.0000** (34 crits at 3.20747e13 against 11 plain at 6.41494e12), size 11 → **5.0000** (8 against 5), size 16 → **5.0000**. Each tier has exactly one distinct plain value, so the crit is the only variance in the payout. Crit rate over both batches **64 of 87 (73.6%)** against the formula's cap of 75, which is this save's luck saturated. **The drawn label was measured rather than photographed**, and the measurement is the stronger evidence: on the live client it reads **`💥 CRIT +32.1T 🧬`**, `TextColor3` **exactly `UITheme.Color.Gold` (1, 0.776471, 0.176471)**, billboard **210×76** — `popNumber`'s `big` branch, against 140×52 for an ordinary number — and a 4px stroke. Five capture attempts failed for one reason worth writing down: **the pop lives about a second and a max-stage character fills any camera close enough to read a 76px billboard**, so every frame was either inside the player's own body or too wide to read. `SoundLibrary.Play("crit", fx.p)` is the first thing ever to play that entry (id 9125672726, a positional `dist 160`) |
| 15.15 | `[x]` | <!-- 2026-08-15, thirtieth session: found by a sweep of all 18 panels, photographed before and after --> **15.1's fix went into one of the two constructors that draw a halo, and the Group & Community panel is what the other one cost.** `MainUI`'s `themeLabel` learned in 15.1 that dark ink must drop its stroke. `UITheme.Label` — the shared constructor every module can reach — calls `outlineText` unconditionally, so any caller handing it a dark `color` gets a glyph inside a 4px band of `Color.Outline`, which is rgb(26,18,36). Measured on the live panel: three card titles at ink **0.14** and three descriptions at **0.36**, each inside a stroke at **0.09**. The capture is not ambiguous — "Official Roblox Group", "Like The Game" and "Favorite The Game" are **unreadable blobs**. The threshold now lives in `UITheme` as `IsDarkInk` (0.45, the same number, chosen for this palette's 0.077 ink and 0.48–0.60 greys) and **both** constructors read it instead of each carrying a copy; `UITheme.Pill` takes it too, since it also colours from the caller. **A third instance was found in the same pass and is not in a panel at all**: `EventService` paints the event board's countdown in `UITheme.Color.Outline` and then outlines it — a clock inside a halo of the exact colour it is drawn in | Open the Group panel and **read** the three card titles | **before and after, both photographed, and the sweep behind them is 1,924 labels across all 18 panels.** Before: 6 findings, all `GroupRewardsPanel`, ink 0.14/0.36 inside 4px at 0.09. After: **0**, and the titles measure ink 0.14 with **stroke 0.0** while the panel header above them keeps ink 1.00 at stroke 4.0 — so the branch fires on exactly the ink it was written for and nothing bright moved. The capture shows crisp black titles on white cards |
| 15.16 | `[x]` | <!-- 2026-08-15, thirtieth session: a documented fix that a helper had been undoing one line later --> **`TextScaled = true` turns `TextWrapped` back on, so a fix written above a helper call is reversed by it — silently, with every property still reading correct.** Measured on a live client, and this is the fact the row exists for: a fresh `TextLabel` reads `TextWrapped = false`; assigning `TextScaled = true` makes it read **true**; only an assignment placed *after* that one sticks. The potion rows in `MainUI` carry a ten-line comment explaining that their sub-label must never stack two lines into a 22px box, set `TextWrapped = false`, and then call `themeLabel` — which sets `TextScaled`. **The fix was written, has read correct ever since, and was never once in effect.** `UITheme.Label`'s own `wrapped` option was inert for the same reason, applied before `autoSize` rather than after. Fixes: the option is honoured after `autoSize` and only when passed **explicitly** — all 23 call sites have been wrapping since the constructor was written and none asks for it off, so defaulting to "off" would silently unwrap twenty labels laid out around wrapping; the trap is written over `autoSize` where the next caller will meet it; and the potion sub-label gets the height instead of the flag, because the one-line plan never worked either — measured at the 14px floor those strings need **300/305/310/320px** on one line against the **288** the row can give, so unwrapping would have truncated the "• 20 min" tail. **`WelcomeBackPanel`'s note is the same defect** (needs 28px in 24) and is now 32 | The three Luck bottles and the large Health bottle read in full; so does the Season Pass note on the welcome card | **measured, because the rows only appear when you own those bottles and this save owns none.** `GetTextBoundsAsync` at the 14px floor, wrapped at the real box width: before, all four needed **28px of height in a 22px box** — second line cut; after, the box is **30** and all three re-measured live come back **280x28, 275x28, 273x28 → FITS**. The DNA bottles need one line (213x14) and are unaffected, which is exactly why the only rows this save renders looked correct. Geometry taken out of the name label above (26 → 24, y 6 → 4) so the row's own 62 is unchanged. `WelcomeBackPanel/Note` no longer appears in the clip sweep |
| 15.17 | `[x]` | <!-- 2026-08-15, thirtieth session: the defect TextFits reported as healthy --> **A button reserves its icon's width on BOTH sides of its label, computed from the button's HEIGHT — so a short, tall button has no label left.** `UITheme.Button` insets the label by `2 × (height × 0.62 + 10)`, which is right and free on a wide button and ruinous on a narrow one: the Group cards' 115 × 42 action button reserved **72 of its 115 pixels**, leaving the label **27px** — narrower than any word in the language. "Claim" rendered as "Clai" over "m" and "Claim Chest" lost its second line. **`TextFits` returned `true` throughout**, correctly: two 14px lines really do fit a 30px box, and the thing that is wrong is that there are two of them. Only the capture showed it. Fix is a floor rather than a new rule — the label keeps at least **55%** of the button, and below that the inset gives way instead of the words — plus this card's button widened 115 → 150 with the description beside it giving up the same 35px | Open the Group panel and read the buttons | **measured across every button in the game and then photographed.** A sweep of all 18 panels for a label narrower than half its button found exactly one design at fault: `ActionBtn` at **23%** (115 → 27). The Pets panel's 26px `✕` tiles read 46% and are a single glyph; `ShardSpin` reads 48% of 170 and fits. After: `ActionBtn` labels measure **83px of 150 (55%)** — the floor, exactly — and every string the card can show is **one line at 14px**: `Claim` 33, `Claimed` 47, `Join Group` 64, `Claim Chest` **71**, all inside 83. Re-swept: **0** squeezed buttons anywhere. The capture shows `🎁 Claim Chest` and `🎁 Claim` on one line with the icon clear of the text |
| 15.18 | `[x]` | <!-- 2026-08-15, thirtieth session: found by being on the receiving end of it during the two-client run --> **Four of `TradeService.Request`'s refusals and three of `Accept`'s said nothing at all to the player.** Only the cooldown, the rate limit and the reach check called `tell`; "You are already in a trade", "They are already in a trade", "That player is not ready", "You cannot trade with yourself", "That trade has gone", "That request is not yours to accept" and "Already open" all returned a reason string to a caller that throws it away. The function's own header claimed the opposite — *"the reason is returned rather than notified, so a test reads the same answer the player would be shown"* — and the second half of that sentence was simply false. **This was diagnosed from the outside during the live run, which is the argument for the row**: an invite timed out and left a session pending, and from then on every press of Ask did *nothing whatsoever* — no window, no message, no way to tell "the server refused you" from "the button is broken". A `refuse` helper now both tells and returns, so tests still read the same string | Press Ask twice, or Accept a prompt that has just timed out, and be told why | **the failure mode was measured before the fix, on the live two-client run**: with a stale session held, two separate Ask clicks produced **zero** `Notify` and **zero** `TradeUpdate` on either client — the observers attached to both remotes recorded nothing at all, which is exactly what the player sees. The session was real: firing `TradeCancel` returned `state=cancelled … partner=Player2` and released it, after which the very next Ask went through. `luascope`, `luastruct` and `luaremotes` clean over the fixed file |
| 15.19 | `[x]` | <!-- 2026-08-15, thirtieth session: 15.11's own code, broken by the test written to prove it --> **The trade picker's distance label never updated, because a Roblox `UserId` is not always a run of digits.** `repaintDistances` found its rows with `row.Name:match("^Player_(%d+)$")` — and **Studio's test players have NEGATIVE UserIds**, Player1 being `-1` and Player2 `-2`. `%d+` does not match a minus sign, so every row resolved to nil, the repaint loop skipped it, and the label read `…` for the whole session instead of "12 studs away — in range". The row is now identified by a **`TradeUserId` attribute**; the name is left for reading in the explorer. The comment that chose the name over the attribute — *"an attribute would do the same job with one more step"* — is what this row is really about: the one step was the job | Open the picker with someone else in the server and read the distance under their name | **the defect was photographed** — the picker capture from the two-client run shows `👤 Player2` over a distance reading `…`, with the label's colour still the authored Grey rather than the Green the in-range branch sets. It would have worked in production, where ids are positive, and failed in **every test anyone could run**, which is the worst way round for a bug to be: 15.11 shipped with a check that could not pass on the only machine able to run it. Fixed and pushed; the repaint itself is unchanged, so this is one line of identity and not new behaviour |
| 15.20 | `[x]` | <!-- 2026-08-15, thirtieth session: photographed on three panels across two clients --> **The FirstJoin tutorial banner draws on top of every panel.** "⚔️ Click a creature to attack it" renders over the `TradeModal` — covering **both** offer column headers, `You (Your Offer)` and the partner's — and over the `TradePickerPanel`'s header. Photographed on **both** clients in the two-client run, so it is systematic rather than a race: the hint's ZIndex sits above the panel band. A panel is a modal surface; a tutorial hint is not allowed over one | Join fresh, open any panel while the hint is up, and read the panel's headers | **Photographed on three surfaces across two clients** (Player1's trade window, Player2's trade window, Player1's picker). **Cause measured rather than guessed: `DisplayOrder` beats `ZIndex` ACROSS ScreenGuis, absolutely.** `FirstJoinGuide` sets **110**; `EvolutionLabUI` sets none at all and is therefore **0** — so no ZIndex any panel could choose would ever have put it over this banner, and the 110 is not the mistake either (the guide's arrow points at the EVOLVE button, so it has to clear the HUD it is talking about). What is actually true is that a panel is a **modal** surface: while one is open the hint is both wrong and in the way. **Fixed by disabling the whole guide ScreenGui**, not by hiding each piece — that way none of the visibility logic below has to learn about panels, including the two one-shot timed banners (`TutorialDone` and the climb beat) that set `Visible` once and would each have needed their own guard. `registerPanel` stamps `HudPanel` on every panel so a second script can ask the question without this file exporting a register, the same trick `columnTile` uses for `ColumnSide` | **live, and it is a yield rather than a mute.** All **18** panels carry the stamp. Measured in order on one client with the banner FORCED visible (this save has `TutorialDone`, so it would never show itself): no panel open → `Enabled = true`; banner made visible, still no panel → **true**; `TradeModal` opened → **false**; panel closed again → **true**. `banner.Visible` stays `true` throughout — the banner is not being hidden, the surface is standing down. The join-time `WelcomeBackPanel` also drives it, which is the case that would otherwise have shipped: the guide was already disabled the moment the client finished loading |
| 15.21 | `[x]` | <!-- 2026-08-15, thirty-first session: opened by the owner mid-play, "auto attack is too close now, I have to stand in the core of the mob to kill it" --> **A Gemini "tighten combat to true melee (<10m)" pass made every reach smaller than the player's own body.** Commit `4df59c7` cut `AUTO_REACH` from `{60,70}` to `{22,32}`, `clickReach` from `size*0.6+16` to `size*0.4+10`, the server's `autoReach` floor from 60 to 22 and both boss `strikeReach`es from 70/90 to 30/34 — and it deleted the comment blocks that recorded why the old numbers were measured while leaving the surrounding prose still describing them, so the files taught 60 and ran 22. **The arithmetic nobody on that path had ever done is the player's own body**: a max-stage character's bounding box measures **30.7 x 42.9 x 27.1**, i.e. **15.4 studs** from the HumanoidRootPart the reach is measured from, and a Critter's box is 22 wide (11 from its centre) — so at a 22-stud reach the two bodies had to **overlap by 4 studs** before a blow was legal, and a Swarmer left 0.6 studs of air. Bosses were not tight but unreachable: a zone boss is 75–121 studs across, so 32 from its centre is inside the model at every zone in the game. All six numbers restored, every deleted comment block restored, and the measurement written into the file so the next pass cannot repeat it. The shockwave ring VFX from the same commit is kept | Stand a body-length off a Critter with Auto ON and watch it die without walking into it; then a boss | **arithmetic measured live, behaviour NOT yet measured — `[~]` for that reason.** The player bounding box (30.7 x 42.9 x 27.1) and the creature boxes (Swarmer 11.9–12.4, Critter 20.1–22.4) were read off the live client; the reach constants are restored in `src/` and were pushed and verified byte-identical in Studio (CreatureService 207078/1604011499, BossService 164078/1411903746, CombatClient 69960/1305787298). What is owed is one fight: the nearest creature to the Forest spawn is **101 studs**, so the check needs the player walked or teleported into a zone first **Closed 2026-08-16 (thirty-seventh session): the fight was run.** A Critter (30 hp) was killed from a standoff of **42.3 studs** centre-to-centre and Boss_Forest (750 hp) from **68.9**, both in under half a second, with `playerMoved = 0.0` in each -- the character never walked in. The measurement the row was missing also corrected a comment in `CombatClient`: bosses are not "75 to 121 studs across", Boss_Desert's solid geometry is **160 x 180** and its invisible HitBox 173 x 173, so 70 is well inside the silhouette. 70 is still the right number for the reason that actually governs it -- a boss has exactly ONE colliding part (`BossCollision`, 64 across), so a player is stopped at ~48 studs from the anchor, 22 studs INSIDE this reach. The rule is now written in the file: `reach > BossCollision/2 + player half-width`, not a fraction of the drawn model. |
| 15.22 | `[x]` | <!-- 2026-08-15, thirty-first session: owner, "Auto Collect - I do not know what it collects, it has no point", at level 52 --> **Auto Collect stopped paying at level 30 and the shop kept selling it to 100.** `GetAutoCollectAmount` was `rate = math.min(level * 0.04, 1.2)`; the ceiling is reached exactly at level 30, while `GetUpgradeMaxLevel` sells 5 levels per unlocked zone — **100 with the strip open** — at `1.38^level`. The owner's save is at **52/100**, so 22 levels had already bought nothing and 48 more were on sale. The cap is not removed (it is what stopped the runaway that put 772M DNA on a Worm-stage save) but **continued**: 1..30 keep the same 0.04 a level, 31..100 buy 0.012, ending at **2.04 clicks a second** instead of stopping a third of the way up — still a fraction of one click per second, which is the unit that keeps active play ahead of idling, and still the number `OfflineService` halves. **And all four DNA upgrade tiles now print what the level they own is doing** — the report was as much "I do not know what it collects" as "it has no point", and the tile showed an icon, a name, a level and a price. Auto Collect prints the server's own per-second figure (`data.__autoPerSec`, stamped by the loop that pays it, because the client cannot compose `GetIncomeMult` without a second copy that would drift); Income, Egg Luck and Speed print their own arithmetic. Tile geometry re-banded: icon 8..44, name 46..76, effect 78..100, cost pill 100..132 | Open Upgrades: Auto Collect reads a real DNA/sec figure, and buying a level past 30 moves it | **the defect is measured, the fix is not yet photographed.** Live off the real save: `AutoCollect 52`, `GetUpgradeMaxLevel` **100**, and the old rate at 52 is identical to the rate at 30. Owed: the panel capture and one bought level moving the printed figure **Closed 2026-08-16: photographed and moved.** The tile reads `🧬 5.82T/sec` at `Lv 66/100` (capture taken), and `Remotes.BuyUpgrade("AutoCollect")` to 67 moved it to **5.86T/sec** -- the server's own stamp went 5.816e12 -> 5.859e12 on the real save, +0.74% per level, and it keeps climbing to 7.27e12 at 100. The old curve was flat from 30 on. Note the first read looked unchanged at 1.5 s: the figure is the SERVER's stamp and only moves on its next push, so a probe straight after a purchase reads the pre-purchase number. |
| 15.23 | `[x]` | <!-- 2026-08-15, thirty-first session: owner, "this should not refresh, it is bought with Robux, there is nothing to count down" --> **The Robux shop counted down to nothing.** `refreshRobuxShop` wrote `⭐ Today's pick resets in %dh %02dm` into the panel subtitle on every push. Every tile in that shop is on sale permanently at a fixed price with the same grant tomorrow, and the "pick" the clock timed was a star drawn on one rotating tile carrying **no discount and no bonus** — so the countdown promised an expiry that does not exist, which is a claim the player can check in twelve hours. Clock, star and `pickIndex` all deleted; the subtitle is a constant ("Packs, potions and passes"). The value ribbons stay: `+24% BONUS` / `BEST VALUE` are derived from real value per Robux, i.e. facts about the tile rather than a clock | Open the Robux shop: the subtitle does not tick, and no tile wears a star | **coded and pushed; capture owed** **Closed 2026-08-16: photographed.** Live sweep of every `TextLabel` under `RobuxPanel` found **no countdown label at all** (nothing matching `reset`/`Today`/`_h _m`), the subtitle is the static `Packs, potions and passes`, and **no tile wears a star**. Sampled 3 s apart: identical. The honest ribbons are still there -- `+24% / +48% / +77% BONUS` on the bigger packs, which is a real difference between tiles rather than a rotating one. |
| 15.24 | `[x]` | <!-- 2026-08-15, thirty-first session: owner, "I need somewhere to see which aura is equipped, or whatever this DNA machine gives" --> **The Splicer's mutation was worn invisibly.** `data.SplicerMutation` is a permanent income-and-speed multiplier (Common x1.05 / +1 speed up to Godly x2.25 / +8) bought at the DNA Splicer, and the only text in the entire game naming it was a line **inside the Splicer's own roll panel** — you had to walk back to the machine to learn what you were wearing. The particle aura on the body is the only other trace and a particle does not say "x1.50". It is now a card on the bottom-left boost strip, which is already the answer to "what is affecting me right now": name, colour, `x1.50 DNA • +5 speed`, all read out of the same `GameConfig.Mutations` row the server pays from, so the card cannot quote an effect the income stack is not applying. Nothing worn draws no card. It joins the strip's budget and fit pass for free and is dropped first when the viewport is short, beside the pass chips, because neither is about to expire | Wear a mutation and read the strip; roll a better one at the Splicer and watch the card change | **coded and pushed; capture owed.** The owner's save wears **Mythic** (x1.50, +5), which is the case the card will draw **Closed 2026-08-16, in 16.1's form rather than this row's.** The card this row asked for was replaced by the `AuraDot` before it was ever photographed (see 15.33), and the dot is what got verified: 22 x 22 on the Auras tile, `Visible = true`, colour **255,80,80** -- byte-for-byte `GameConfig.Mutations` Mythic, which is what the save wears -- against the panel's own `5 of 7 found • wearing Mythic (x1.50 DNA, +8% speed)`. The report behind the row is answered: the worn aura is now readable without walking back to the Splicer. |
| 15.25 | `[x]` | <!-- 2026-08-15, thirty-first session: owner, "I do not need the Market button" --> **The Market tile is gone, and what it cost is written down rather than discovered later.** 12.8 added a Coral tile at R9 whose flyout opened the Egg and Fusion panels from anywhere, and left a comment at the ProximityPrompt handler reading *"do not delete that tile"* — fusion had been reported as a missing feature by players who had not yet walked into Volcano. The owner asked for it gone; the whole 105-line block is deleted and that comment is rewritten to say what is now true. **Consequence, stated plainly: fusing now requires standing at the Pet Fusion Lab counter in Volcano.** Eggs are unaffected in practice (every zone has a podium). If the report comes back the cheap fix is a Fusion door on the Pets panel action row, which is at 678 px of 744 and would need 30 px off each wide button — a measurement, not a guess | Open the HUD: no Market tile, and the right column has no gap | **live: `MarketButton` is absent from the ScreenGui and the 12 remaining tiles lay out in pairs with no hole** (`R1..R8`, `L1..L4`, all 82 px, y 63..607). Owed: nothing for the removal; the fusion consequence is a decision, not a defect **Closed 2026-08-16.** Two captures of the live HUD show both tile columns with no Market tile and no hole -- the removal was already measured, and nothing was owed but saying so. |
| 15.26 | `[x]` | <!-- 2026-08-15, thirty-first session: two findings from the Gemini audit that are not yet acted on --> **Two more things the Gemini audit turned up, kept as one row so neither is lost.** (1) **`HANDOFF-LOG.md` cites verification artefacts that do not exist** — the 5.4 and 5.5 entries claim *"verified with `test_trading.py` / `test_group_rewards.py` simulation harness"* and neither file is anywhere in the repo or in git history. That is worse than 4df59c7's honest "Not verified: none", and it means **5.4 and 5.5 have no evidence at all behind their `[~]`**; both rows' Verified-how cells still read "verified with luastruct & luanames", which is static lint over source text and is labelled "(live, in Studio)" in every one of the seven Gemini entries. (2) **`RewardService.HandleClaimLikeReward` / `HandleClaimFavoriteReward` pay diamonds and shards on the client's word alone** — Roblox exposes no API to check a like or a favourite, so every game does this, but it is an ungated faucet and it is not called out anywhere as a risk. Check it is stamped-before-grant and one-shot per save, the rule 5.1 and the free spin already follow | Re-run 5.4's and 5.5's own checks from scratch; read the two reward handlers for the stamp-before-grant order | **Both halves done 2026-08-15, thirty-second session, and the row numbers in the finding were slightly wrong: the two fabricated citations sit under 5.5 and 8.6, not 5.4 and 5.5.** That matters, because **8.6 has since been closed on a real two-client run** (`fa4e701`) — the void clause was propping up nothing by the time it was found, and it is struck rather than replaced. 5.4's entry cites no phantom file; its fault is the smaller one, static lint labelled "(live, in Studio)". All three Verified-how cells are rewritten above to say what is actually established and what is not, and `HANDOFF-LOG.md` carries a dated correction rather than an edit (it is append-only). **(2) The faucet is safe, read line by line:** `data.ClaimedLikeReward = true` / `ClaimedFavoriteReward = true` are written **before** the first `+=`, with nothing yielding between the `if` that tests them and the write — `Get` is a table lookup and `AddPotions` is pure arithmetic on the save — so the double-fire window 5.1 and the free spin were built to close does not exist here either. Both default to `false` in `defaultData` and **nothing anywhere clears them**: not a rebirth, not a migration, not the trim. One-shot per save, permanently. The client's word is still the only trigger, which is unavoidable (Roblox exposes no like/favourite API) and is now written into the row instead of being folded knowledge. Cost of the worst case, stated so it is never re-derived: **💎 30 + one Luck potion + 🌟 2, once per account, ever** |
| 15.27 | `[x]` | <!-- 2026-08-15, thirty-second session: the owner's second ask in the same message as 15.26, plus what auditing the working tree turned up --> **"Make somewhere I can see which auras I have and which one is equipped" — and the working tree already held a Gemini attempt at it that had to be taken apart first.** The feature itself is real and was missing: `data.SplicerFound` has counted every Splicer roll since Phase 12 and **nothing in the game has ever read it**, so a collection of seven auras had exactly one visible member (15.24's boost card) and exactly one reachable state (the best one you ever rolled, because the roll was the only writer of `data.SplicerMutation`). Shipped: an **Auras** tile at L5 and a 620x550 panel listing all seven mutations in rank order — colour chip carrying the roll COUNT, name, `💎 x1.50 DNA  ⚡ +5 speed` off the same `GameConfig.Mutations` row the server pays from, a **Wear** button on every one you own and `✓ Wearing` on the one you have on. Unfound rows are drawn, named and priced, and say where they come from. `SplicerService.HandleEquipMutation` + an `EquipMutation` remote are the server half. **Wearing a weaker aura is allowed on purpose** — both stats rise together with rarity, so the only reason is the look of the particles, and the cost is printed on the row and on the boost card before it is paid; best-kept-wins on the ROLL is untouched. **What the audit found in the attempt, all fixed:** (a) it restyled the **Journal** — deleting 12.6's rarity pip, the detail card's rarity ribbon and the ring-not-puck fix that exists because of the owner's own *"remove the circles, you cannot see them"* report — none of which was asked for. **All three were reverted whole, comments included** (the same shape as 15.21); the owner then asked for the two rarity badges gone on their own merits, which is **15.28** — so the discs are rings again and the rarity is gone, and the difference between those two sentences is the whole point of reverting first; (b) the equip handler wrote `data.SplicerMutation` and called `ApplyMutationAura`, which is the **one line that does not work**: `WornMutation` reads `player:GetAttribute("Mutation")` FIRST and the join path stamps it, so the old aura would have stayed on the body all session and the walk speed would never have moved — it runs `HandleRoll`'s three lines now (attribute, `RefreshBonuses`, `PushToClient`); (c) `registerPanel` was called **before** `styleCard`, and the cyan panel rim is chosen inside it off a stroke that has to already exist; (d) the block opened with `(function()` on the line after `end)()`, which Luau reads as a call on the previous expression; (e) buttons were driven with `.Text` / `setButtonColor` instead of `UITheme.SetText` / `UITheme.SetColor`, i.e. writing to a surface nobody sees; (f) the whole file came back **CRLF**, a 20,124-line diff that would have failed every future hash sweep. Two extras taken while in there: a `SplicerFound`/`SplicerMutation` repair at Load (a worn aura is by definition a found one, or the panel calls the thing on your body unfound and refuses to re-equip it), and `RIGHT_COUNT` 9 → 8, left behind by 15.25's tile deletion | Open Auras: seven rows, the worn one says `✓ Wearing`, and pressing **Wear** on another changes the particles on your body, the walk speed and 15.24's boost card without a respawn | **pushed, run and photographed 2026-08-15 (thirty-third session) — the panel half is verified live, the body half still is not.** Lint as before (`luastruct`/`luascope` clean, `luanames` at baseline, `luaremotes` resolves 52 with `EquipMutation` on both sides). **Live, on `Evolution-lab.rbxl` under a synthetic `DataUpdate`** (4 of 7 owned, Legendary worn): the panel draws at 620x550 with **seven rows in rank order**, counts `x21/x12/x5/x2` on chips in each aura's own colour, `💎 x1.30 DNA ⚡ +4 speed` off the config row, `✓ Wearing` on Legendary and **Wear** hidden on the three unfound rows, whose lines read `🔒 Not found yet • x1.50 DNA, +5 speed`. Header: `4 of 7 found • wearing Legendary (x1.30 DNA, +4 speed)`. **Pressing Wear on Epic put exactly one `EquipMutation` fire on the wire (`OGLightninggXD -> Epic`) and pressing the dimmed `✓ Wearing` put none** — (b)'s dead-button rule holds. Contrast checked rather than eyeballed: the near-black Secret chip takes white ink and the pale-gold Godly chip dark ink, i.e. `UITheme.IsDarkInk` is live. **Why this is still `[~]` and not `[x]`:** the row's own step ends *"changes the particles on your body, the walk speed and 15.24's boost card"*, and **none of those three can be shown here** — this place is `GameId 0`, so `PlayerDataService` dies on `GetDataStore` at module scope, `ServerMain` never boots and `HandleEquipMutation` never runs. The client half is proved; the server half needs **BETA V0.2** (`10675543038`) opened. Owed: that one run <!-- CLOSED --> **CLOSED on BETA V0.2 (thirty-fourth session), on the owner's real save, by real coordinate clicks.** The place was opened from the cloud, swept (**47 of 50 byte-identical, 3 behind, 0 missing** — exactly this row's three files, each traced to a real commit before anything was written: PlayerDataService `c17c7be`, SplicerService `c624914`, MainUI `47c4a91`) and pushed. The server booted for real (`GameId 10675543038`, 53 remotes, `EquipMutation` among them). Panel on the real save: **5 of 7 found, wearing Mythic**, counts x20/x11/x5/x1/x1, and `Wear` **hidden** on exactly the two unfound rows (Secret, Godly) while the four owned-not-worn keep it and Mythic reads `✓ Wearing` with `Active = false`. A click on **Common** put **one** `EquipMutation` on the wire and the server half ran end to end: attribute `Mythic → Common`, the aura on `HumanoidRootPart` **rebuilt without a respawn** (`AuraKey`/`Mutation` attribute follows, emitters **4 → 1**, particle colour rgb(255,80,80) → rgb(200,200,200)), the boost card redrawn `Mythic Mutation` → `Common Mutation`, and the panel subtitle to `wearing Common`. Restored to Mythic the same way (emitters back to 4, colour back to red) — the save ends where it started. **One clause of the check is unprovable on THIS save and the arithmetic says so rather than the capture: walk speed cannot move.** `WalkSpeed` is `min(pre, cap)`; measured live, pre-clamp is **581.58** against a cap of **260** (BaseWalk 34 + mastery 25.2 + Speed upgrade 13.5 + mutation, × sizeMult 3.742 × the 2x Speed pass), so at max stage **no aura choice can ever change it** — the widest possible swing, Godly +8 to Common +1, is 52 studs of a 321-stud overhang. That is not a defect in this row; it is **15.30**. Tool note: click by **coordinate** (`AbsolutePosition + AbsoluteSize/2`), not by `instance_path` — an `instance_path` click on this panel landed **twice, at two different rows**, and two coordinate clicks in a row each produced exactly one arrival |
| 15.28 | `[x]` | <!-- 2026-08-15, thirty-second session: owner, mid-review of 15.27's revert --> **The Journal's rarity badges are gone, and 12.6's argument for them is retired rather than overruled.** *"I do not need the rarity option in the Journal, every character has to be collected anyway."* She is right, and the reason is dated: 12.6 added a pip on each disc and a ribbon on the detail well so a collection screen could say *"there is a Legendary here you have not found"* — which is a true and useful sentence about a game where characters **drop**. Since **9.5 made every skin its own evolve** the 200 unlock in **strict rank order**, so the next character you get is the next rung whatever its rarity is, and a player who reads the pip can do nothing differently. Both badges deleted (`Pip`, `DetailRarity`, the paint block in `paintDetail` and the `Visible = false` in its empty branch). **`entry.rarity` is deliberately NOT deleted** — `StageCostume.skinMarks` reads it to decide how much flourish a character wears, which is the form the fact takes now: you see a Legendary's ornament on the Legendary instead of a letter in its corner. The disc stays a RING (that is 11.x's fix for her own *"you cannot see them"* report and is a separate decision from this one) | Open the Journal: no letter badge on any disc, no rarity ribbon on the detail well, and the figures still wear their per-rarity flourish in the world | **verified live and photographed 2026-08-15 (thirty-third session).** The Journal was opened on a save with 60 characters unlocked and `swv_constell` worn. **No letter badge on any disc and no rarity ribbon on the detail well** — the detail card runs name → `❄ Star Weaver • #3 of 5` → stats with nothing between them, and a sweep of the panel's **2,306 descendants** finds **zero** instances named `*rarity*`/`*pip*`/`*ribbon*` and **zero** labels reading a rarity word or a bare rarity letter. The discs are still rings (11.x's fix intact, which is what reverting first bought). Header reads `Discovered 60 / 100`. The third clause — the per-rarity flourish — is shown by the previewed figure itself, which wears its crown, i.e. `skinMarks` is still reading `entry.rarity`; that is the Journal's own `CharacterPreview` and **not** a body in the world, which this place cannot spawn |
| 15.29 | `[x]` | <!-- 2026-08-15, thirty-fourth session: photographed beside the panel that contradicts it, while closing 15.27 --> **15.24's boost card rounds the mutation multiplier to one decimal, so it quotes a number the income stack is not applying.** `MainUI`'s `formatMult` is `("%.1f"):format(m)` for any non-integer — written for the potion and event cards, whose multipliers are all x1.5/x2/x3, and correct there. Three of the seven mutations are two-decimal: **Common 1.05 draws as `x1.1`, Epic 1.18 as `x1.2`, Godly 2.25 as `x2.2`** (rounded *down*, so the best aura in the game under-sells itself). The capture from 15.27's run has the card reading `x1.1 DNA` and the Auras panel reading `x1.05 DNA` **in the same frame, four inches apart** — which is the fault in one picture, and it is exactly the promise 15.24's own comment makes ("the card cannot quote an effect the income stack is not applying"). Fix is a formatter, not a special case: format at 2dp and trim trailing zeros, so `2 → "2"`, `1.5 → "1.5"`, `1.05 → "1.05"`. Nothing currently correct changes; all three call sites keep the same helper | Wear Common and read the card and the panel together — the same number twice | **Formatter is live in the place; the pairing it was named for cannot be photographed.** `formatMult` now formats at 2dp and trims the trailing zero, verified compiling and drawing (HUD built with all 41 children). What cannot be shown is the card-beside-panel frame from 15.27's capture: **the Studio MainUI has no mutation boost card at all** -- that lineage carries a `16.1` pass that replaced the two-line cards with one-line capsules, and 15.24's card is not in it (see 15.33). The Auras panel, which was always right, reads `x1.50 DNA` live. Stays `[~]` for the missing half of its own check, not for doubt about the fix. **Closed 2026-08-16, and the fix is now inert by design.** `formatMult` is correct at 2dp with the trailing zero trimmed, but after 16.1 removed the mutation card **nothing routes a mutation through it any more** -- its remaining callers are the potion and event capsules, whose multipliers are exact at one decimal either way. The number this row was about is printed by the Auras panel's own `%.2f`, verified live as `x1.50 DNA`. Kept as a fix rather than reverted: the next thing to print a mutation through this helper would reintroduce the defect. |
| 15.30 | `[x]` | <!-- 2026-08-15, thirty-fourth session: measured while closing 15.27, whose own check named the clause that cannot pass --> **Every aura advertises a speed bonus that a late-game body cannot receive.** `WalkSpeed` is `min((BaseWalk + mastery + speedUpgrade + mutationBonus) * sizeMult * walkMult, cap)`. Measured live on the owner's save: pre-clamp **581.58** against a cap of **260** — the body is at **2.24x its own ceiling**, so the mutation term is 321 studs of overhang and *no* aura choice moves the number by a single stud. The whole ladder spans 7 studs of raw bonus (Common +1 to Godly +8), which is **52 studs after `sizeMult × walkMult`** and still nowhere near the gap. Both the Auras panel and the boost card print `⚡ +5 speed` regardless. This is 15.22's shape exactly (Auto Collect stopped paying at level 30 and the shop kept selling it to 100) and 15.23's (a countdown to an expiry that does not exist): **a number the UI keeps quoting after the mechanic behind it has stopped being able to pay.** It is real for most of the game — at `bodyScale` 1 the pre-clamp is 77.7 against 150 — so the fix is not to delete the bonus; the options are to raise the cap with the body (it is a streaming number, not a balance number — see the comment in `EvolutionVisuals`), to make the mutation bonus a *fraction of the cap* rather than flat studs, or to stop printing what cannot land. **Owner decision, not a code fix** | Decide which of the three; then wear two auras four rungs apart at max stage and read the speed | **Measured live on the owner's own max-stage save, which is the body the row is about.** Owner chose *bonus as a fraction of the cap* out of the three options (2026-08-16). `speedBonus` (flat studs, inside the clamp) became `speedPct` (percent of THIS player's walk cap, added after the clamp); every reader was renamed with it so a stale one fails loudly. At stage 20, BodyScale 5, cap 260: **no aura 260.00 -> Common 265.20 -> Mythic 280.80 -> Godly 291.20.** Every rung moves the number now; before, all seven read 260. The UI was migrated in the same pass and prints `+8% speed` in the Auras panel, the locked rows, the subtitle, the Splicer's worn line and its roll card -- all photographed as text. |
| 15.31 | `[x]` | <!-- 2026-08-15, thirty-fourth session: owner, mid-session -- "petovi nek ne svetle i te aure nek malo manje sljaste, nista se ne vidi, ko ni na zadnjem stageu sve sljasti" --> **Three separate light sources pile onto the same silhouette at max stage, and together they erase it.** Read as three findings because they are in three files and each stands alone. (1) **Pets glow, all of them:** `PetModel` gives every pet a `RarityRing` at `Material.Neon`, and Epic / Legendary / Secret additionally get a `PointLight` (Range 13, Brightness 2) **plus** a `ParticleEmitter` at `LightEmission = 1`; a fused pet adds a Neon crown band and three Neon spikes. With up to eight equipped that is eight self-lit discs and up to eight point lights orbiting the player. (2) **The max-stage BODY is Neon:** `StageCostume.BODY[20] = { mat = Enum.Material.Neon, tr = 0.12 }`, so the torso, head, arms and legs of The Absolute are flat self-lit gold — and Neon takes no shading at all, which means the stage that is supposed to be the most impressive body in the game is the one stage with **no form**. `BUILD[20]` was already cut to four features for exactly this reason ("a costume reads by its outline"); the shell underneath undoes that. (3) **The aura is sized 1:1 with the body:** `AttachMutationAura` passes `targetSize = spec.span * scale`, so Mythic's 9.4-stud span becomes **47 studs** at `BodyScale` 5, at rate 27 — a particle wall wider than the character standing in it. Fixes to make together, since the complaint is their sum: drop the pet glow to colour only (ring stays, Neon and PointLight and sparkle go), give stage 20 a shaded material and let the crown/halo/core carry the light, and make the aura's span **sublinear** in body scale with the top rungs' rates cut | Stand at max stage with pets out and a Mythic aura and see the body's outline | **Done as a two-agent merge, and the merge is the story.** Gemini had already fixed most of it live in Studio while this session was writing the same fix in `src/` -- ring to SmoothPlastic, PointLight and sparkle deleted outright, stage 20 to SmoothPlastic, aura span to `scale^0.6`. Those were ADOPTED rather than overwritten (`src/` was walked back to them), and only what was missing was added: the **crown band and spikes** (still Neon, now Metal), the `AURA_SCALE_EXP` constant + the comments explaining all three, and the rate cut at the top of the ladder. Measured live at BodyScale 5: **14 rarity rings, 0 Neon, 0 PointLights, 0 pet sparkles**; the Mythic aura's biggest particle is **24.7 studs (was 47)** at rate 22 (was 27). Photographed at max stage: the body has an outline again. |
| 15.32 | `[x]` | <!-- 2026-08-15, thirty-fifth session: found by `luaremotes.py` while auditing the nine Gemini commits, after the owner pulled the Gemini handoff and asked for its work to be repaired directly --> **Three of Gemini's remote listeners were wired at BUILD time through `FindFirstChild`, which is a race that fails silently.** `OpenGroupRewards` (5.5), `TradeInvite` and `TradeUpdate` (8.6) each read `Remotes:FindFirstChild(name)` while the panel was being constructed and then guarded the connect with `if remote then`. The services create those remotes at run time, so when the lookup loses the race the guard simply skips, **the `:Connect` never happens and is never retried, and nothing raises** — the panel builds, the buttons draw, and the feature is dead for the whole session. This is the same shape as the dead button the twenty-seventh session found, and it is invisible to all four lints except `luaremotes.py`, which reports it as *"one-shot client connects on a FindFirstChild lookup"*. The distinction that makes only these three wrong: of the 19 `FindFirstChild` sites in `MainUI`, the other 16 sit **inside click handlers** and resolve at press time, which is late and therefore safe. Fixed into the idiom the file already documents at the `ZoneTransition` connect — `task.spawn` + `WaitForChild(name, 30)` + a nil guard — which closes the race without blocking the HUD build if a service is slow to arrive. Each of the three carries a comment naming what losing that particular race costs, because the three costs differ: an unopenable chest, an invite indistinguishable from a friend who never sent one, and a trade that opens and then strands both sides with no state coming back | Join, open Group Rewards, and run one trade end to end: the chest opens, the invite lands, the modal updates | **lint-clean, not yet run.** `luaremotes` went from *3 one-shot connects* to **52 remotes resolved, every one with a speaker and a listener**; `luastruct` and `luascope` OK on `MainUI` (10,203 lines); `luanames` **identical to baseline** (the same 884/3761/6403, no new name). Diff is **24 insertions, 10 deletions in one file, LF throughout** — checked, because the last `MainUI` handoff came back CRLF at 20,124 lines. **Evidence for the live half: none.** The race is timing-dependent, so a passing run does not prove the old code was broken and a fix cannot be photographed — what is owed is a regression check that the three listeners still fire, on BETA V0.2 **Two of the three regression-checked live on BETA V0.2 -- after the fix had to be ported into the place, which it had never reached.** The Studio MainUI is a separate lineage (see 15.33) and still held the racing `FindFirstChild` version; the three blocks were ported in by hand, MainUI rebuilt clean (41 of 41 children). Firing the remotes server-side: `OpenGroupRewards` -> `GroupRewardsPanel.Visible = true`; `TradeInvite` -> the prompt shows *ProbeFriend wants to trade with you*. Both panels restored to hidden afterwards. `TradeUpdate` still owes the two-client run its own check names. **Closed 2026-08-16: the third listener was regression-checked the same way as the other two.** `TradeUpdate` fired server-side with a synthetic session (`probe-1532`, partner ProbeFriend, 1 pet offered against 2) opened the modal, printed `ProbeFriend's Offer`, and drew **MySlots=1 / PartnerSlots=2** with Cell, Dragon and Fox by name; a second fire with `state = "cancelled"` closed it and cleared the session. Console clean. The handler needs no prior session, which is why this works at all -- and why it is a real check of the connect rather than of the trade. **The two-client end-to-end run is 15.5's, not this row's:** this row is about a `:Connect` that silently never happened, and all three now demonstrably fire. |
| 15.33 | `[x]` | <!-- 2026-08-16, thirty-sixth session: found by a hash sweep before pushing, not by a symptom --> **`src/` and the Studio MainUI are two different files now, and each holds work the other has never seen.** A provenance sweep of the eight files this session touched came back HIT on four (Studio == a real commit, safe to fast-forward) and **NO MATCH on four**: `PetModel`, `StageCostume`, `EvolutionVisuals` -- all three Gemini's live 15.31 pass, reconciled in this session -- and `MainUI`, which is the problem. Studio's MainUI is **10,317 lines to `src/`'s 10,203, and the two diverge from line ~150 onward.** Studio-only: the `styleCard` / `InnerBody` / `ShadowBody` rewrite its own comments date to *15.28*, and a **`16.1`** pass that replaced the two-line HUD cards with one-line capsules. `src/`-only: **15.24's mutation boost card** (absent from Studio entirely -- `mutationCard` and `mutationEffects` grep to nothing there) and **15.32's three un-raced remote listeners**, which is why a committed fix was still not in the place a day later and had to be ported by hand here. Neither copy is wrong; both are real work. The job is a one-file, line-by-line merge into `src/`, done ONCE and committed, before anything else edits that file -- every session that touches MainUI blind widens the gap, and the place is the volatile half. `tools/hash_sweep.py` cannot do it (it spawns its own proxy and cannot reach an attached Studio -- "Unable to reach Roblox Studio"); what worked here is chunked per-50-line hashes computed in Luau against `git show HEAD:<file>` locally, which locates the differing blocks in one call. **Done 2026-08-16 (thirty-seventh session), and the merge was one-directional: Studio won every hunk.** All four divergent regions were Studio-newer -- 15.28's `styleCard`/`liftChildren`/`setButtonColor` rewrite, 16.1's one-line capsule strip, 15.28's Season track tray+rail, and 15.27's `Roll at the DNA Splicer` string. `src/`'s two "only here" items were not losses: 15.24's mutation card was **deliberately replaced** by 16.1's `AuraDot` (the removal carries its own note in Studio), and 15.32's three un-raced listeners were already hand-ported into the place, leaving only a duplicated comment line, deleted in Studio so both halves are byte-identical. **The dump route that made this cheap, and cost no agent context at all:** a local `http.server` on 127.0.0.1:8765 writing POST bodies to disk, plus `HttpService.HttpEnabled = true` and `PostAsync` of `Source` in 60 KB chunks from Edit -- 474 KB out in one call, then an ordinary local `git diff --no-index`. A second dump after the edit diffed to exactly the one intended line, which doubles as proof the other agent did not touch the file mid-merge | The merged MainUI compiles, builds 41 of 41 HUD children, and a hash sweep of it comes back HIT on a commit | `luastruct` OK 10,296 lines; `luascope` OK; `luanames` 3 names (`animatePanel`, `stop`, `nextStageDef`) -- **identical to HEAD's, so the merge added none**. Live in Play: 41 of 41 children, `PotionTimers` 224x196, `AuraDot` present, `WornMutation` and `PassBoosts` gone, console clean |
| 15.34 | `[x]` | <!-- 2026-08-16, thirty-seventh session: opened by looking at the panel, closed by measuring it --> **Every Journal character was drawn a third smaller than its own disc, because the camera fitted the bounding SPHERE.** `CharacterPreview.Frame` pulled back far enough to cover `size.Magnitude * 0.5` -- the box's diagonal. A sphere is the one shape a turn cannot crop, which is why it was chosen, but it charges the frame for DEPTH that a front-on camera never sees as height: a 4 x 5 x 5 wolf was fitted as if it were eight studs tall. Measured across all 100 entries: **every figure between 18% and 59% too small, mean 37%**, worst on the quadrupeds -- the ones whose picture is hardest to read at 84 px in the first place. Now fitted to what a camera actually has to cover: the model's height, and its footprint as rotated by `yaw` (`|sin|*Z + |cos|*X`), the width through the viewport's own aspect -- a ViewportFrame's `FieldOfView` is the vertical one, so the 298 x 202 detail card can afford a wider model than an 84 px square cell. `pitch` still reads off the sphere, because that is a look and not a fit | Open the Journal: the figures fill their discs. Photographed before and after at 1.75x | **Verified live on BETA V0.2.** 100 rigs measured for the growth figure; the after-capture shows the discs filled edge to edge with nothing cropped, including `wolf_grey` at x1.58, the worst case |
| 15.35 | `[x]` | <!-- 2026-08-16, thirty-seventh session: found while measuring 15.34, and it changes what the Journal's perf machinery is for --> **The Journal's part budget was guarding a cost that no longer exists, and its cull had a name that never matched.** Two findings in the same function. (1) `cullToSilhouette`'s comment claims *"a dressed stage comes out at 240-270 parts"* and the cell caps it at 26. Measured: **all 100 ladder characters now have a generated mesh** (`Assets.SkinMeshes` holds 200), a meshed rig is **six segments, mean 6.8 parts**, and `Build` skips the cull entirely for those -- so on the live roster the function does not run at all. The primitive path it does still guard is 26-62 parts, not 240-270, and eighteen cells cost **59.2 ms capped vs 56.8 ms uncapped**, i.e. the cap is inside the noise. Kept as a safety net for a skin the generator has not reached, with the real numbers written down. (2) The cull spares `StageEye` and **`StageEyePupil` -- a name StageCostume never creates**; the part is `StagePupil`. Measured on the primitive path: **every one of the twenty stages came out `Pupil 0/2`**, blank-eyed, which is the exact outcome the comment says the exception exists to prevent | Build a primitive-path stage capped at 26 and count the pupils: 2, not 0 | **Measured live**, both halves. The pupil fix is on the path only off-ladder skins take today, so it is verified by the part census rather than by a photo |
| 15.36 | `[x]` | <!-- 2026-08-16, thirty-seventh session --> **The Journal opened two discs at a time and filled up over the next several seconds.** `syncPreviews` builds at most two rigs per PASS, and a pass ran on exactly three signals: opening the panel, a scroll, and a DataUpdate. Opening it is ONE pass -- so the panel drew two characters and sixteen emoji stand-ins, and the rest arrived one income tick at a time, on the panel whose entire job is showing off a collection. Nothing was broken; the fill had no engine of its own. It has one now: `syncPreviews` returns how many it built and `fillPreviews` keeps passing until a pass builds nothing, a frame apart, guarded by a `filling` flag because a drag fires `CanvasPosition` every frame. Still a budget and not a loop -- **a rig costs 3.15 ms**, so a window of eighteen is ~57 ms in one go (three or four dropped frames) against ~9.5 ms for three | Jump the scroll to the far end and count the drawn discs per frame | **Verified live on BETA V0.2**: a jump to the bottom of the list went **0/11 -> 6/11 in one frame, complete at 7/11 by 61 ms** -- the remaining four are locked event skins, which draw a `?` and no figure by design |
| 15.37 | `[x]` | <!-- 2026-08-16, thirty-seventh session: owner's call, taken with the two looks photographed side by side --> **The filled disc came back a THIRD time, and this time nobody put it back.** 15.27 made the Journal disc a ring -- transparent fill, colour on the rim -- because a green creature on a green puck is a silhouette-shaped hole. Then **15.28 rewrote `styleCard` to hold the fill in an `InnerBody` child**, so the three lines that strip a disc to a ring (`cell.BackgroundTransparency = 1`, destroy `Gradient`, destroy `Gloss`) now clear surfaces that are no longer the ones being seen, and the comment above them still says *"RESTORED 2026-08-15 (15.27)"* while the panel shows filled pucks. Photographed with the fill cleared on two rows and left on the third. **Owner's choice of the three ways out (2026-08-16) was not the ring:** keep the filled disc, which is the chunky look the rest of the HUD has, and take the collision out of it -- the FILL is paled (`Color3.fromHSV(h, s * 0.34, 0.97)`, the locked disc's HSV idiom pointed the other way) while the rim keeps the character's colour at full strength. The pale is carried on the refs table because **`setButtonColor` is a real function now** (15.28 gave it a body) and repaints that surface on every DataUpdate, so `refreshCharacterPanel` has to hand it the pale or the disc goes back to full strength one income tick later -- which also retires the *"these two calls paint NOTHING"* note above it | Open the Journal and read a green character against its own disc | **Verified live on BETA V0.2** and photographed: fills read `0.89, 0.97, 0.89` and friends per cell, rims unchanged, figures clear of their backgrounds on every row |

---

## Phase 16 — The panel pass · *opened 2026-08-16 by a hash sweep, not by a plan*

**This phase already existed in the place before it existed in this file.** A session-start sweep
found six of the fifty live scripts divergent and `tools/provenance.py` returned **NO MATCH** on all
six — Studio was carrying work that is in no commit, including a `MainUI` 16 KB larger than `src/`
whose comments cite rows **16.1** and **16.2**. It was pulled out whole over the HTTP bridge and
committed (`73e65a8`) before anything was written over it, so the two rows below are written
**from the code that is already running**, and they are `[~]` for the honest reason: nobody has
verified them against a check. That is what the rest of this phase does.

**The rule this phase is about, stated once.** `applyShell` no longer paints the frame it is given.
Since 15.28 it sets that frame fully transparent and moves the fill, its gradient and the bottom lip
into **`InnerBody`** and **`ShadowBody`** children. So every helper that repaints a surface by
writing `BackgroundColor3` on the host now writes to a surface nothing draws — and returns quietly.
15.37 was one instance of this (the Journal disc), `setButtonColor` was the fix for a second, and
16.3 is the general case.

| ID | | Task | Check | Verified how |
|---|---|---|---|---|
| 16.1 | `[x]` | <!-- found in the place 2026-08-16, authored by an earlier uncommitted session --> **The HUD strip is capsules, not cards.** Every row on the boost strip is 216x38 and a capsule where it was 244x48 and a box; the two-line boost card (subtitle + effects line) is one line; the **pass chip tray is gone from the HUD** entirely; the worn mutation is a coloured **dot on the Auras tile** rather than its own card; and the strip is capped at four rows instead of "every pixel between the tile column and the bottom edge". Written up here from the code because it exists in no commit message and no row | Open the game with two boosts and an aura live: four capsules maximum, no pass chips, and the aura reads as a dot on the tile | **measured and photographed on the live HUD, with two real boosts and a worn aura.** Two potions used through the real `UsePotion` remote (`dna_s`, `xp_s`) and the strip drew them as **216x38 capsules** at a 6 px gap, bottom-aligned, one line each. `PotionTimers` is **224x196** at a 793-high viewport, i.e. `floor((196+6)/44)` = **4 rows**, the cap. The `AuraDot` is live at **22x22** on `AurasButton` in rgb(170,90,255), which resolves to the **Epic** row of `GameConfig.Mutations`. **No pass chip tray**: a name sweep over the whole HUD found seven `Chip` frames and every one of them is an aura rarity chip inside the hidden `AurasPanel` -- worth stating because the sweep flagged them first and the parent chain is what cleared them. The capture reads two capsules over the currency stack, a purple dot on the Auras tile, and nothing between the strip and the tile column |
| 16.2 | `[~]` | <!-- found in the place 2026-08-16, same source as 16.1 --> **The tile columns are 2x2 and the door to trading is the other player.** Both side columns are two tiles wide (they were single files); the **Trade tile is gone** and its feature is not — clicking any avatar in the world opens a 250x184 card over the click with their headshot, display name, live distance (in range / walk closer) and one green **Trade** button, with a quieter second button into the picker panel that still exists. Client raycast, not a `ClickDetector` per character; the server still re-checks identity, distance, rate limit and trade state in `TradeService.Request` exactly as before | Click another player: the card opens above them, clamped into the viewport, and its distance line repaints as you walk | **half measured live, half still owed, and the half that is owed needs two clients.** Proven on the running HUD: **12 visible tiles in 4 columns** -- Shop/Inventory over Rebirth/Auras on the left and Journal/Zones, Daily/Robux, Season/Gifts, Auto/Audio on the right, i.e. **both sides two wide**. **No Trade tile**: the only trade-named objects left are `TradeInvitePrompt`, `TradeModal`, `TradePickerPanel` and `PlayerCard.CardTrade`, none of them a HUD tile. `PlayerCard` exists at exactly **250x184**, `ZIndex` 60, hidden. What is NOT proven is the row's own check -- the card opening over a clicked avatar, the clamp, and the distance line repainting as you walk -- because `showCard` is a local closure inside MainUI reachable only through a real click on a real second player, and this session had one client. It belongs in the same session as 5.4 and 8.6 |
| 16.3 | `[x]` | <!-- found live 2026-08-16 by a probe on the running HUD, one call --> **`UITheme.SetColor` has been a no-op on every modern surface, and it is the API ~25 state recolours go through.** It paints `inst.BackgroundColor3` and looks for `inst.Gradient`; after 15.28 the host is `BackgroundTransparency = 1` and both the fill and the gradient live in `InnerBody`, with the lip in `ShadowBody`. The `Body` tile branch is dead the same way — an `IconTile`'s face is itself an `applyShell` surface. Measured on the live HUD: **631 shells on screen**, and a `SetColor` to magenta moved the host's invisible colour and left the drawn fill, its gradient and the lip untouched. **`MainUI` already knows** — 15.28 added a local `setButtonColor` that repaints `InnerBody`/`ShadowBody` by hand and its comment says every state recolour in that file was "dead on arrival". What that fix did not reach is every **direct** `UITheme.SetColor` call: the Robux tabs, the mute toggle, the Auras `Wear` buttons, the shard button, the potion rows, the Locked/Green claim buttons, `SplicerUI`'s roll button and `ZoneTransition`'s name card. Fix the root — resolve the paint target once, so a surface with an `InnerBody` is painted there and a plain frame (a `ProgressBar` fill, which is what `CombatClient` recolours) is painted as before | `SetColor` a live shell and read `InnerBody.BackgroundColor3`, its `Gradient` and `ShadowBody` — all three move, and a plain frame still moves too | **fixed and measured live on BETA V0.2.** `UITheme.FaceOf` is public now and `SetColor` paints through it. On the live `TopBar.StageCard`: `InnerBody` 0.647,0.412,0.961 -> 1,0,1, its `Gradient`'s first keypoint 0.788,0.647,0.976 -> 1,0.4,1, and the `ShadowBody` lip 0.388,0.247,0.576 -> 0.6,0,0.6 -- fill, gradient and lip, all three, where the old code moved only the host's invisible colour. **Control run in the same call:** a bare `Frame` with no `InnerBody` still repaints 10,10,10 -> 0,255,0, so the `ProgressBar` fills `CombatClient` recolours are untouched. Restored to its authored rgb(165,105,245) afterwards |
| 16.4 | `[x]` | <!-- found live 2026-08-16 in the same probe pass as 16.3 --> **15.2's cyan panel rim is gone from the entire game, and both halves of the test that sets it broke at once.** `registerPanel` is the one place that knows what a panel is, and it decides the rim with `panel:FindFirstChildOfClass("UIStroke")` plus a near-white test on `panel.BackgroundColor3`. After 15.28 the stroke is a child of `InnerBody`, not of the panel — so the lookup returns **nil** — and the host's own `BackgroundColor3` is never written at all, so it reads back Roblox's **default frame grey (0.639, 0.635, 0.647)**, which fails the near-white test even if a stroke had been found. Measured on the running HUD: **19 of 19 panels carrying `HudPanel`, host stroke missing on 19, thickness ≥ 6 on 0** — every panel in the game wearing the ordinary dark 5px card outline. Asked of the surface now (`UITheme.FaceOf`, made public for this) and of the `BaseColor` attribute `applyShell` stamps on the host, which is the reading that survives wherever the fill lives next. The `ShadowBody` lip keeps its dark outline deliberately: a lip recoloured to match stops reading as a shadow and starts reading as a second, misaligned rim | Open any panel: a 6px cyan rim on the face, dark lip beneath, and nothing else in the game gains one | **fixed and photographed.** Before: 19 panels, host stroke missing on 19, thickness >= 6 on **0**. After: **19 of 19** carrying a 6px stroke in `Color.PanelBorder`. Capture of the Zones panel shows the cyan rim back on the face with the dark lip beneath it |
| 16.5 | `[x]` | <!-- photographed 2026-08-16 on the first capture of the session, before anything was touched --> **The Welcome Back card is authored for two rows and usually has one, so a third of it is empty shell.** Measured on the live card: panel 580x294, `Rows` 548x188, and one visible row — about **100 px of blank grey** under the daily reward, which reads as a card that failed to finish loading rather than as a card with one thing on it. Two rows is genuinely the maximum (daily + Season Pass) and the authored height is right for that; what was missing is that the Season row is the *uncommon* one. Sized to the rows that are actually visible, after they are decided. **Shrinking is the safe direction and that is why it may run after `registerPanel`:** the UIScale was fitted for 580x294, so a panel that ends up smaller still fits every viewport it fitted before — growing is what would be scaling off a stale number, and this never grows past the authored height | Join with only the daily waiting: the card ends a margin under the one row, not 100 px under it | **fixed and photographed on a real join.** The card opened with one live row and measured **580x194** against the authored 294, `Rows` exactly 88 tall -- the daily reward with a margin under it and no empty shell. Two rows still resolves to 294 by the same arithmetic |
| 16.6 | `[x]` | <!-- opened 2026-08-16 by a contrast sweep, and the sweep's answer was wrong; the capture corrected it --> **Both Pets/Potions tabs are blank pills, and the shell is painted over the caption.** A `TextButton` draws its own text at its **own** ZIndex, and `styleCard` puts the fill in an `InnerBody` child one rung **above** it (`Z.Body`) — so since 15.28 the two tabs on the Inventory and Pets panels have been a grey pill and a blue pill with no words on either. The caption moves onto its own label at `Z.Content`, the way `styleButton` mirrors every other button in this file into a proxy, with `themeLabel`'s halo and the stroke matched to the glyph's own transparency (an opaque outline under a dimmed label draws the word in outline only). **The first reading of this row was wrong in an instructive way, and it is kept here for that:** a contrast sweep said the text sat at **1.13:1 against its own fill** and the fix was recorded as "add the missing outline" — true, these were the only **4 of 942** visible text runs in the HUD with no `UIStroke`, and *not the fault*. A colour probe cannot see occlusion. The second capture, taken after the halo shipped, showed two blank pills exactly as before, which is what named the real cause. The sweep itself is still worth keeping, in its corrected form: the naive test (text vs backing) flagged **736 of 942** runs, because in this HUD the outline *is* the contrast — a run reads if it separates from its backing **or** from its own stroke | Open Inventory: two captioned tabs, the inactive one dimmer rather than blank | **fixed and photographed.** Live: `ownText=""` on all four tabs, caption on a `Label` child at ZIndex **31** against the body's 28, transparency 0.00 on the active tab and 0.25 on the inactive one with the stroke matched to each. The capture reads a dimmed **Pets** on the grey pill beside a bright **Potions** on the blue one -- where the previous capture, taken with the halo already shipped, showed two blank pills. An occlusion sweep over the whole HUD found exactly these **4 of 1,212** text runs buried before the fix and **0 of 1,818** after it (the two counts differ because the second pass had more rows drawn) |
| 16.7 | `[x]` | <!-- 2026-08-16, measured while photographing 16.6 --> **The potion shelf stops 178 px short of the bottom of its own panel.** `PotionScroll` is authored at a fixed **204** tall inside a 528 panel whose content starts at 146, so the list ends at y = 350 and the bottom third of the Items card is empty white — the dead space visible in 16.6's capture. Measured: canvas **810 against a 204 window, three of twelve rows visible**, in a panel with room for six, and the space that would have shown the other three sitting blank underneath it. Height is relative now (`1, -164`, i.e. the 146 it starts at plus the 18 bottom margin the panel uses everywhere else), so the shelf follows the panel if the panel is ever resized again; `PotionEmpty` covers the same rectangle and moves with it | Open Items with potions owned: the list reaches the bottom rim and shows six rows | **fixed and photographed.** Live: scroll **484x364** with the gap to the panel's bottom rim measured at exactly **18**, and 45% of the canvas in the window against 25% before. The capture shows five and a half rows where three fitted, and the x0 rows now read grey against the owned ones' colour -- which is 16.3 becoming visible rather than a change here |
| 16.8 | `[x]` | <!-- 2026-08-16, same pass --> **The Robux shop showed a fifth of itself, and it is the screen that takes the money.** 448x500 gives the grid 416 of width — two 192 cells, no room for a third — and 338 of height, 1.9 rows of 180. Measured live: **canvas 1,726 against a 338 window**, so twenty products sat below a first screen that looks complete. Every other panel here is sized to its content; this one was sized to the smallest thing it could get away with. **640x640 is arithmetic, not taste:** the grid then has 608 of width and three cells plus their two 10px gaps is 596, so a column fits with **12 px of slack** rather than the 0 an exact 628 would leave — a grid that wraps on a rounding silently drops to two columns. 9 rows of 2 become 6 rows of 3. Nothing inside had to move: both scrolls and the tab row are sized `(1, -32)` off the panel, and `registerPanel` fits the authored size to the viewport (0.59 on a 848x420 phone) | Open the shop: three columns, and the panel still fits a phone viewport | **fixed and photographed.** Live: panel **640x640**, grid 608x478, **3 columns** counted off the top row's cell positions, canvas **1,726 -> 1,150** (9 rows of 2 became 6 of 3) and 42% of it in the window against 20%. The capture reads five whole products and a sixth row starting, ribbons and the gold BEST VALUE intact. **The phone case is arithmetic, not a measurement, and is stated as such:** `fit()` is `clamp(min((v.X-32)/w, (v.Y-108)/h), 0.35, 1)` and re-runs on every ViewportSize change, so 848x420 gives **0.4875** -- a 312x312 panel, inside the viewport, above the 0.35 floor |
| 16.9 | `[x]` | <!-- reported by Kristina 2026-08-16: "ovi VIP karakteri izgledaju losije nego obicni" --> **Every skin you can PAY for is the only kind still built out of blocks.** All 200 ladder skins have a generated model in `ReplicatedStorage.Assets.SkinMeshes` and wear it; the **six skins outside the ladder** — `vip_gold` and the five event skins — have none, so `SkinMesh.Has` returns false and `StageCostume` dresses them in primitives. Both `GameConfig` comments say so outright and call it fine ("There is no generated SkinMesh_vip_gold, and that is fine"), which was true only while the ladder was primitives too. It has not been since the 200 were generated, and the result is that the VIP pass and every event exclusive are the **worst-looking characters in the game** — the item that takes money, rendered in the one style everything else outgrew. Generate `SkinMesh_vip_gold`, `SkinMesh_event_prism` and the four `SkinMesh_event_clash_*`, file them beside the other 200, and nothing else has to change: `SkinMesh.Has` is the switch and it flips per key | Wear the VIP skin: a generated body, not a gold-tinted stage costume — and the Journal card shows the same body | **generated, filed and photographed.** Six `generate_mesh` calls fired in parallel, all six back with the six named segments and all within the existing roster's proportions (X/Y 0.89-1.00 against a 200-model mean of 0.77 and an existing widest of 1.09). **All six came back facing +Z and therefore carry `FaceFlip`** -- proved against a control in the same pass rather than assumed: `SkinMesh_bact_dust` (flag set) shows its eyes from +Z while `SkinMesh_hum_knight` (no flag) shows the back of its helmet from the same camera. Folder is **206** now, `FaceFlip` on 10. Photographed in Edit on real `PreviewRig` clones through the real modules, and confirmed on a **live character in Play**: `SkinMesh` folder present on the worn VIP skin. The Journal card was photographed too, beside a ladder skin as a control |
| 16.10 | `[x]` | <!-- 2026-08-16, the half of 16.9's report that a mesh does not fix --> **A premium skin differed from a ladder Legendary only by its colour.** 16.9's meshes close the gap in *quality*; they do not make the paid item read as paid. Every off-ladder skin is `Legendary`, so `skinMarks`' rarity flourish gives it exactly what 40 ladder skins already have — a halo, four orbitals, an emitter — and after 16.9 it would also have a generated body exactly like the other 200. `StageCostume.Regalia` is hardware **no ladder skin can wear**: a head piece, shoulder plates welded to the arms (not the torso — a pauldron that stays put while the arm swings past reads as a bug) and a turning ring of light at the feet, dropped off the Humanoid's `HipHeight` because the body runs 1x at Cell and 9x at the last stage. Chosen by the **entry**, never by the rarity, because rarity separates none of these six from each other: a **crown** for the pass, one shared gold **laurel** for the four Colosseum champions (the wreath says *champion*, the colour says *which*), turning **shards** for the Prism Herald. Public and called from three places, because the body can be dressed by a builder, by a mesh, or by neither: the builder path runs it inside the same `pcall` after `skinMarks`, Apply's mesh branch runs it before returning, and `CharacterPreview` runs it with `static` (a ViewportFrame renders neither a tweened weld nor a particle). Into the **same folder** the costume uses, so `Clear` already takes it away | Wear the VIP skin: crown, pauldrons and a ring at the feet, at any stage — and no ladder skin gains any of the three | **built, corrected twice by capture, and photographed on both paths with a control.** Live counts: off-ladder + mesh = crown band + 5 spikes + 16 plinth beads; off-ladder + primitive = the same plus 2 pauldrons + 2 trims; **ladder skin = 0 on both paths**. On a real character in Play the ring measured **+0.15 above the feet** and the Journal card renders VIP and Ember with their regalia beside an untouched Knight. **Two numbers the first capture corrected, both worth keeping:** the plinth was dropped off `Humanoid.HipHeight` and that is wrong twice -- `PreviewRig` has none, which floated the ring **1.07 studs** on the rig every Journal card uses, and a real character measured **HipHeight 14.84**, which would have put it far below the floor. It is measured off the lowest bare limb now, which is what `SkinMesh` already does and is a measurement rather than a proxy. And the ring was authored at 0.95x the torso inside a body **4.88 wide across the arms**, so it sat under the character instead of around it |

---

## Phase 17 — The aura was never purple · *opened 2026-08-16 by the first capture of the session*

**Opened by a screenshot of nothing in particular.** The session-start sweep was clean (50 of 50
scripts byte-identical), every open row in the file was owner-blocked, so the next thing to do was
look at the game — and the first capture of the live HUD had a **white smear across the lower two
thirds of the frame** that the world was barely visible through. Muting the three emitters of the
worn mutation aura, locally, gave back the whole village. That is the phase.

**The rule it found, stated once.** A `ParticleEmitter` draws `Color × Brightness`, and at
`LightEmission = 1` that product is *added* onto the scene rather than lit by it. The free VFX pack
is authored for a dark demo scene and leans on both, so **every tint this game asks for was being
clipped to white**: rgb(170, 90, 255) × 5 is (850, 450, 1275), which is white in all three channels.
The tint is not a suggestion the pack can overrule — `opts.color` is a caller saying *this must read
as this colour*, so the ceiling belongs in `VFXLibrary` beside the tint and not in any caller's
table.

| ID | | Task | Check | Verified how |
|---|---|---|---|---|
| 17.1 | `[x]` | <!-- found 2026-08-16 on the first capture, root-fixed the same session --> **Every tinted effect in the game rendered white, and the worst of them is worn on your own body.** Measured live before the fix: **33 of 110** particle emitters in the workspace at `Brightness > 1.5` **and** `LightEmission > 0.5` — the player's own mutation aura at 5.0/1.00 (three floor sprites up to 21.5 studs across, at a camera 15.9 studs away, i.e. the wearer is standing inside them), **21 emitters on the equipped-pet rigs** at the same values, the Forest zone and boss effects at 10.0/1.00–2.00, and `Boss_Event` at **500**. It also explains why the aura ladder never read as a ladder: `Smoke-01` (Common) ships at Brightness 1 and `Tornado-01` (Godly) at 0.3–1, while `Stars-01` (Rare) is 10 and the three `RNG-Auras` (Epic/Legendary/Mythic) are 5 — the two ends were the colour they were asked for and the three rungs in the middle were white. New `applyTint` in `VFXLibrary` caps a tinted emitter at **Brightness 1 / LightEmission 0.35** (ceilings, never assignments — `Windspin3` stays at its authored 0.3) and every tint path goes through it: `Attach`, `Place`, and `BurstAt` through `Place`, Beams included — a Beam carries the same two properties and clips the same way | Wear an aura at the last stage: a coloured swirl you can read the village through, not a white smear — and no emitter anywhere above brightness 1.5 | **fixed and photographed, before and after, from the same camera on the same body.** Before: the capture is a white smear over the lower two thirds and the far end of the street is not visible. After, through the **real server path** (Play restarted, `EvolutionVisuals.ApplyMutationAura` → `VFXLibrary.Attach`, nothing written by hand): the three Epic emitters read `B=1.00 LE=0.35 col=170,90,255` and the capture is a purple swirl with the whole village, the boss stage and the lamp posts legible through it. Blast radius measured rather than assumed: **0 of 103** workspace emitters now sit above 1.5 brightness (was 33 of 110), the equipped-pet rigs' 21 emitters came down from 5.0 to 1.0, and `Boss_Forest`'s `Light`/`Stars` went 10.0/1.00–2.00 → 1.00/0.35 **in the zone's own green** rgb(120,220,120), while its untinted `Wind1`/`Wind2` correctly kept `LE = 1.00` — there is no tint on those to protect. The boss half is measured but not photographed; the owner was playing on the one client and the camera was handed straight back |
| 17.2 | `[ ]` | <!-- measured 2026-08-16 in the same pass; NOT fixed, because both fixes trade one fault for another --> **At the last stage you play the game from inside your own body, and that is what puts the aura across your eyes.** Two numbers taken together on a live max-stage character: the body is **~39 studs tall and 35 wide** (`torso_geom` alone is 35×35×35) while the camera sits at Roblox's default **12.5-stud zoom**, measured 15.9 studs from the HumanoidRootPart. So the camera is *inside* the silhouette — which is also why `CostumeVisibility` has to exist at all, why the aura is at eye level, and why nobody at the endgame can see the character they spent the whole game earning. The aura half is one line: `AttachMutationAura` hangs the effect on the HumanoidRootPart with **no offset**, and the pack's emitters are named `Floor1/2/3` — a *ground* ring, sitting **23.64 studs above the feet** on a 5× body. **Both obvious fixes were tried live and both cost something.** Dropping the attachment to the measured lowest limb puts the ring exactly on the ground (world y −0.66, feet −0.66) and the view becomes completely clear — and the wearer can then no longer see the aura at all at the default zoom, which is the thing they bought. Pushing the camera out instead (`CameraMinZoomDistance = 12.5 × BodyScale`, 62.5) moved it to 64.7 studs and the capture came back **black**: at that range it is inside the village scenery. So this needs a real decision — a camera that grows with the body is a feel change across the whole late game, and 👤 **it is Kristina's to make** | Decide first, then measure: at the last stage you can see your own character, your aura, and the creature you are hitting | — |
| 17.3 | `[~]` | <!-- Kristina 2026-08-16: "photo spot nista ne radi" --> **The Photo Spot is a sign that promises a feature and a pad that has no code behind it.** `HubPlaza.buildPhotoSpot` lays a rim, a pad, an eye, two posts, a beam, a translucent sheet, a crest and a `BillboardGui` reading 📸 PHOTO SPOT — and a source sweep finds **no `ProximityPrompt`, no `Touched`, no `ClickDetector` and no client listener** anywhere for `PhotoPad`, `PhotoRim`, `PhotoSign` or `FrameSheet`. It is furniture wearing a feature's label, which is worse than not having it: the sign is a promise the game does not keep. Either it takes a photo or it comes out and something that works stands there instead | Stand on the pad: something happens, and the sign is telling the truth | **built and photographed on the real pad, and the framing is being re-tuned off that photograph.** The prompt is on the pad (`PhotoPrompt`, reach 46, plaza rebuilt to `PLAZA_VERSION` 3), and a real **E** at the pad ran the whole sequence: HUD down, camera posed opposite the arch at a distance fitted to the drawn body, the player turned to face it, a 3-2-1 countdown, a shutter flash, a white border and the caption **`EVOLUTION LAB - OGLightninggXD`** -- photographed. The server half landed in the same run: `PhotoTaken` **false -> true** and Diamonds **15 -> 40**, i.e. the one-time +25, and afterwards `CameraType` was back to `Custom`, the HUD re-enabled and the overlay destroyed. `[~]` rather than `[x]` for one reason only: the capture showed the subject filling three fifths of the frame and sitting low in it (the camera was aimed at 55% of the body height and lifted 30%, i.e. looking down), so `FRAME_FIT` went 1.35 -> 1.55 and the aim to the middle with a 0.20 lift -- and **that change is on disk and not yet in Studio**, because the owner was playing and a push needs Edit mode |
| 17.4 | `[x]` | <!-- Kristina 2026-08-16: "auto collect nista ne radi" --> **Auto Collect pays and nothing on the screen ever moves.** Measured on her live save through the real `DataUpdate` payload: `Upgrades.AutoCollect` is **67** and the server stamps `__autoPerSec = 5.86e12` DNA a second, so it is not broken in the sense of not running. It is invisible: her balance is **5.09e19**, the HUD formats it as `50.88Qi`, and at that rate the fourth significant digit moves once every **~28 minutes** — a counter that is mathematically frozen. The only place the number is ever shown is the shop tile's effect line (15.22), which you have to open the shop to read. Two separate things to fix and they are not the same: the **feedback** (draw the payout where it happens — see [[evolution-lab-feedback-placement]] — and put the rate on the HUD beside the balance) and the **weight** (1.64 clicks/sec at level 67 against roughly a kill a second at x5–x33 zone multipliers, i.e. ~5% of active income; that ratio is 15.22's deliberate choice and is a decision, not a bug) | Sit still for ten seconds: you can see it paying, and you know the rate without opening a panel | **fixed and measured live.** The payout is drawn over the player through `CombatClient`'s own `popNumber` -- the same function that draws the DNA a kill pays, which is the whole reason it went in that file rather than a new one -- every **4 seconds**, carrying what has actually been paid since the last draw, and muted for 2 s after any hit near the player so it never competes with a kill's own number. Watched on the live client for 10 s with a `DescendantAdded` listener: **2 numbers drawn**, at t=3.6 s and t=7.7 s, both reading **`+23.4T`** -- exactly 4 x the server's stamped `5.86e12` -- and both hosted **19.7 studs above the root**, i.e. clear of a 40-stud body's head rather than inside its chest. The weight half of the row is untouched and stays a decision: 1.64 clicks/sec is 15.22's number, not a defect |
| 17.7 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot from The Absolute Plane: "ovi zadnji stagevi su samo bela svetlost i nista zivo se ne vidi" --> **The last zones are white on white.** Her capture of `The Absolute Plane` is a white ground under a white haze with white props on it, and the only readable things in the frame are the HUD and the black outline round her own body. The first measurements are in and they are all global rather than per-zone, which is the important part -- nothing here is a bug in that one zone's build: `Lighting.Brightness` **2.50**, Ambient **80,80,95**, OutdoorAmbient **110,110,130**, an `Atmosphere` at density 0.35 with **Haze 1.5**, `Bloom` at threshold **1.5** / intensity 0.40, and a live `ColorCorrection` at **saturation 0.38** and contrast 0.26. Against that, `AbsolutePlane`'s own `groundColor` is `rgb(255,255,255)` -- pure white, the brightest floor in the game -- so the zone that gets the most light is also the one with nothing to absorb it, and the haze then removes what little separation distance would have given. Where the fix goes is the open question: the zone palette, the haze, or the exposure, and it must not undo [[evolution-lab-bright-world-pass]] or the chunky look everywhere else. **ANSWERED 2026-08-16, and the opening measurement above was half wrong: the cause is per-zone after all, and it is the floor's MATERIAL before its colour.** `GROUND_MATERIAL` set `Enum.Material.Neon` on three zones -- TimeRift, CelestialThrone and AbsolutePlane -- and a Neon surface is drawn at full colour with **no lighting applied to it whatever**: no shading across its width, no shadow from anything standing on it, no ambient. The floor is **1250 x 4 x 1150**, so at that size Neon stops being a material and becomes a lightbox, and every prop standing on it loses its contact shadow at the same moment it loses its contrast. The colour was the second half: `groundColor` rgb(255,255,255), luminance **1.00**, against a next-brightest ground of Desert's **0.79** -- measured across all twenty, only this one zone is over. Both fixed at the source rather than per-zone: the three floors are Foil/Marble/Marble, and a `GROUND_MAX_LUM = 0.80` ceiling now sits in `ZoneBuilder` beside the floor, exactly where 17.1 put the emitter ceiling in `VFXLibrary` beside the tint -- a zone author says what colour the ground IS, the builder knows how bright a floor may BE. Nothing global was touched: the haze, the exposure, the grade and the bright-world pass are all untouched | Stand in the last three zones: the ground, the props and the creatures are three different things | **fixed and photographed before and after from the same camera, at eye height, on a real rebuild.** Live after a stamp 133 -> **135** rebuild: `AbsolutePlane`'s floor **rgb(255,255,255) Neon -> rgb(204,204,204) Marble** (lum 1.00 -> 0.80), CelestialThrone -> Marble, TimeRift -> Foil, and Forest's Grass untouched as the control. Neon parts in AbsolutePlane **731 -> 484** and in CelestialThrone **739 -> 467** -- the ~250 that went are the ground details (`PathSlab`, `PathStone`, `GroundPatch`, `PathVerge`), which inherit the floor's material; the trims and props that are *meant* to glow all kept theirs. Parts brighter than 0.85 luminance: AbsolutePlane **21% -> 19%**, against Forest's 17%, i.e. the last zone is now within two points of the first. The before capture is a flat white sheet with **no contact shadow under any lamp post, fence or egg**; the after has veined stone, a sun shadow across the street and every prop sitting on the ground instead of floating in it. CelestialThrone photographed too -- marble columns, red banners and the boss statue all read. Console clean: 5 warnings, all five the known informational ones. **Note for the owner: the code is fixed but the SAVED place still holds the old white world** -- the Edit datamodel is still stamped 133, so this only becomes permanent on the next save (already on the checklist) |
| 17.5 | `[ ]` | <!-- Kristina 2026-08-16: "pogledaj malo +1 ili evolution roblox igre pa iskopiraj speed ima i one trake za trcanje" --> **Speed, and the running tracks the genre is built on.** +1 Speed Evolve's whole loop is a physical track you run on; this game has a `Speed` upgrade in a shop panel and nothing in the world that is about moving. A track is a prop the player stands on and *uses*, which is a different thing from a number in a list | Run the track: speed goes up in a way you can see, and it is worth going back to | — |
| 17.6 | `[ ]` | <!-- Kristina 2026-08-16: "mozemo na par mapa dodati skriveni prolaz koji otkljucava neke bonuse dodatne neke relice ili neke trails ili nove aure" --> **Hidden passages.** A few zones get a way in that is not signposted — behind a waterfall, a gap in a cliff, under a terrace — and finding one pays a permanent bonus: a relic, a trail, an aura, something that is not on any shop shelf. The point is that it is *found*, so it must not appear in any list before it is found and must be discoverable without a wiki. Needs: a per-zone placement that a rebuild cannot move (the same problem `LeaderboardService` and `RebirthShrine` solved by building their own furniture behind their own version stamp rather than going through `ZoneBuilder`), a save field of which secrets are found, and a reward type — auras exist, trails and relics do not yet | Walk into the gap in one zone: a reward lands once, ever, and the Journal knows about it afterwards | — |
| 17.8 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot of the boss bar: "popravi i ove health barove da budu ovalni ima nesto crno iza lose izgleda, sve nek bude ovalno nekako cela estetika dugmica i huda" --> **Every capsule in the game wore two black caps, and the shape ladder never reached the screen.** `applyShell` — and `MainUI`'s own `styleCard`, which is a second copy of it — draws the lip as the body's own rectangle shifted down 6 px and painted dark. On a card the straight sides hide it and only the bottom edge shows, which is the sticker look the style is built on. On a **stadium the sides ARE the curve**: shift that shape down and its flanks swing out at both ends into exactly the part of the bounding box the body has already curved away from. `ProgressBar` sets `ClipsDescendants`, which squares those crescents off into two black blocks capping the bar — the thing in her screenshot. Measured on the live HUD: **324 pill-shaped shells, every one carrying a 6 px lip.** Two more faults in the same family: three bars asked for a pixel radius (the boss bar 14, `SplicerUI`'s pity bar 8, the Mastery summary 12), so they were the only rounded-*rectangle* bars among a dozen pills; and `MainUI.styleCard`, the builder behind most of the HUD, never called `SnapRadius` — it snapped its stroke and not its corner — so the shape scale in `UITheme` governed every surface **except** the screen you look at. Ladder raised 10/16/20 → 14/22/30 and the snap made one-directional: a radius lands on the first step at least as round as the one asked for, so nothing in the game can come out squarer than its author wrote it | Bring up a boss bar: a clean capsule with an even dark rim and nothing dark behind it — and every bar in the game is a pill | **fixed, measured and photographed before and after from the same camera.** Before: boss bar at `CornerRadius 0,14` with `ShadowBody` at y+6 and a dark cap at each end. After: all three of its surfaces at **`1, 0`** and `ShadowBody` at y **0**; a 2.4x capture reads a clean white stadium with one even outline. Sweep over the whole live HUD: **324 pill shells, 0 still carrying a lip.** Pixel radii on the HUD are now only **14 / 22 / 30** where they were 10/16/20 plus a stray 8, and `ShopButton` measured 82x82 at **22** with the icon tiles defaulting to 30. Console clean — 0 errors and 0 warnings across the playtest. `src/` re-verified **byte-identical** to Studio on all four touched files (`UITheme`, `MainUI`, `CombatClient`, `SplicerUI`) |
| 17.9 | `[x]` | <!-- found 2026-08-16 by the session-start sweep, before any of 17.10 was written --> **The whole VIP wardrobe existed in one unsaved Studio session and nowhere else.** The session opened on a screenshot of nine VIP discs; `src/` has one VIP skin and always had. The place file on disk (saved 14:05 the same day) does not carry them either, so the nine skins, the `vipDamageMult` term in the damage chain and the `directHost` welding rule were all one Studio crash away from gone. Pulled the five drifted scripts back through the localhost bridge — `GameConfig` +6987, `MainUI` +1894, `SkinMesh` +1117, `UITheme` +1000, `DNAService` +616 — and committed them unchanged before touching anything | `git diff` on the backport is additions only, and the sweep reports 0 files where Studio and `src/` disagree | **the diff proved the direction.** Studio's copy was a strict superset of `src/` on all five files (the only deletions were lines the new code replaced in place), so the pull was a fast-forward and not a revert of anything. Sweep before: **47 identical, 5 different, 0 only-in-Studio, 0 only-on-disk**; after the pull and commit `5075108`, 52 identical. **What this row does NOT rescue is the eight baked bundle models** — `SkinMesh_vip_*` are instances, not files. That is what `tools/build_vip_skins.lua` is for (17.10) |
| 17.10 | `[x]` | <!-- Kristina 2026-08-16: "ove likove jos nabudzi nadji bolje roblox skinove stavi neke zmajeve ili tako nesto kul da daju bolje bonuse ... samo da sto bolje modernije i skuplje izgledaju" --> **The row that costs 499 Robux was dressed in free starter avatars.** The wardrobe 17.9 rescued was eight *free* catalog bundles — Junkbot, a vampire, a Redcliff paladin, Metal Menace — which is a bin of beginner looks standing in for the most expensive thing in the shop. Re-cut to nine of **Roblox's own paid bundles**, escalating, with the monsters in the middle: Sunstar → Cyborg Shogun → Skyfall Valkyrie → Bull Demon King → Skeletal Dragon → Overseer: Overlord → Dragon Lord → The Doombringer → Korblox Deathspeaker. Both ladders raised and a second one added: damage **2.00…8.00 → 3.00…15.00** (+1.5 a rung) and a new `vipIncomeMult` **1.10…1.50** wired into `DNAService.GetIncomeMult` beside `GetPassMult`, so a VIP skin pays DNA as well as damage. Seven retired keys are swept out of saves by `GameConfig.RetiredVipKeys` rather than left to resolve to nil on a worn skin. And the bake became a repo file, `tools/build_vip_skins.lua`, because the models are instances the place owns and no commit can carry | Wear each of the nine: a real catalog body, not a grey default and not a headless suit — and the Journal quotes the same two multipliers the server applies | **measured and photographed on all nine, through the shipped module.** `Assets.SkinMeshes` is **214** now (200 ladder + 5 event + 9 VIP) and every one of the nine baked models is there. Structure, per model: **16-18 MeshParts, rig hardware 0** — no `Constraint`, `Attachment`, `WrapTarget`, `FaceControls`, `BodyColors` or `Motor6D` survives the strip, so a bundle is structurally identical to a generated skin — and a `Head` part on all nine. Applied to nine real `PreviewRig` clones through `SkinMesh.Apply` itself: **ok=true and stuck=0 on all nine**, i.e. no repeat of the `Model:PivotTo` fault, and photographed in three groups. Every body reads as its catalog figure — Sunstar's plate, the Shogun's chest gem, the Valkyrie's winged helm, Borock's chains, the Skeletal Dragon's ribcage, the Overseer's green trim, the Guardian Lion's collar bell, Crystello's facets, Tenko's nine tails. **One capture trap worth writing down: the bodies top out at world y 402.54 and the first pass framed them from 403.6, which draws every character from above its own head and reads as nine headless suits.** Heads measured at 399.89-401.71 and re-shot at head height; nothing was wrong with the bodies. Confirmed on a live character in Play too: `SkinMesh` folder, 16 parts, the `vip_gold` body. Multipliers: the Journal reads `entry.vipDamageMult` / `entry.vipIncomeMult` (MainUI 6016, 6368-6369, 6398-6405) and the server reads the **same two fields** through `GameConfig.GetVipDamageMult` / `GetVipIncomeMult`, called from `DNAService:129` and `DNAService:45` — one source, so the card cannot drift from the grant |
| 17.11 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot of a flat yellow crown floating over a horned character: "ove krunice bolje napravi sta ce im to, likovi su vec dobri" --> **The regalia outlived its reason.** 16.10 gave every off-ladder skin a crown, a laurel or turning shards so a paid skin would read as paid beside a ladder Legendary it otherwise differed from only by colour. 17.10 made all nine of them real catalog bundles with their own horns, helmets and antlers — so the hardware became a flat yellow crown hovering over a Bull Demon King. Dropped from the nine VIP entries (the field is simply absent; `StageCostume.Regalia` already no-ops without it, so no code changed). **The five event skins keep theirs** — they are still generated costumes, and the argument that put the hardware there is still true of them | Wear any VIP skin: no crown, no laurel, no shards — and the Prism Herald still has its shards | **the row's own premise was wrong, and only a live character showed it.** 17.11 dropped the field and asserted "`StageCostume.Regalia` already no-ops without it, so no code changed" — it does not. The guard one level up in `regalia()` is **`offLadder`**, which every VIP entry still correctly carries (it is what keeps the plinth), and `headPiece` ended in a bare `else -> crown(...)`. So an entry that names no piece got the crown *by default*: measured on a live character wearing `vip_gold`, **`StageCrownBand` 1 + `StageCrownSpike` 5 + `RegaliaPlinth` 16**, and the capture is her screenshot reproduced exactly — a flat yellow crown over a horned body. **Fixed at the fallback:** `headPiece` returns on a nil `kind` and the band is drawn only on an explicit `regalia = "crown"`; an unrecognised name now draws nothing rather than quietly drawing a crown, because a piece nobody asked for cannot be traced back to a config line. After, on the same body from the same camera: **`RegaliaPlinth` 16 and nothing else** — `StageCrownBand` and `StageCrownSpike` both gone, the body wearing its own horns, the ring still at the feet. The five event skins keep theirs by name (`shards` on the Prism Herald, `wreath` on the four champions), unchanged. Lints clean, push verified byte-identical |
| 17.17 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot of the Forest street: "sta je ovo sto prati jaje skin" --> **Something long and white is trailing the player across the whole street.** Her capture is a single thin white-and-dark streak running from the character down to the far bottom-left corner of the frame, past the fence and out of shot — hundreds of studs of it, drawn over the village, following her as she moves. It is not lit like scenery and it is not a costume part. The candidates are all things that take two endpoints and draw between them: a `Beam` whose second `Attachment` was never moved off the origin (the classic shape of exactly this streak — one end on the body, the other at 0,0,0), a `Trail` with no lifetime cap, or one of 17.1's tinted effects now drawing where it used to be invisible. Find it by what it IS before theorising: sweep the character and the workspace for `Beam`/`Trail`, read both attachment world positions, and name the module that created it. **ANSWERED, and it is none of the three: it is 17.1's own fix, one property too far.** There is no `Beam` and no `Trail` anywhere near the player (swept live, 0 of either within 60 studs and 0 spanning more than 80), and no long thin part that is not anchored scenery. It is the **mutation aura's floor sprites**: four `MutationAura` emitters sized up to **24.7 studs** at a minimum Transparency of **0.00**, i.e. a fully opaque quad several times the character's width lying flat on the grass, attached to the body and therefore following her. From above it photographs as a black diamond on green -- reproduced exactly on a max-stage body in Forest -- and from a low camera the same flat quad projects edge-on as the tapering streak in her screenshot. **Cause: `applyTint` capped `LightEmission` to 0.35 alongside `Brightness`, and the two properties do different jobs.** Brightness multiplies the colour and is the whole of 17.1's finding; LightEmission decides how additively the sprite is blended, and these pack textures are drawn on a **black background** that only vanishes because it is added onto the scene. Lower it and the black is composited as black. Fixed by removing the LightEmission ceiling entirely -- an effect's authored value is a property of how the texture was drawn, not a decision the tint gets to make | Stand still in Forest: nothing is drawn between the player and anywhere else, and moving leaves no streak | **fixed and photographed before and after from the same camera on the same body, through the real server path.** Isolated first by moving nothing but that one property on the live character: at `LightEmission` 1 with `Brightness` still capped at 1, the black quad vanished from the capture and the aura was still **red** rather than white -- so the tint is safe without it and the ceiling was doing no work. Then fixed at the source, pushed, and re-measured after a Play restart with nothing written by hand: the four `MutationAura` emitters read **B=1.00 LE=1.00 col=255,80,80** and the capture is a red aura on green grass with the Forest gate, the stalls and the trees all legible and **no dark shape anywhere**. **17.1's result is intact and that was measured rather than assumed:** 0 of 112 world emitters above brightness 1.5, and across all **98 tinted emitters in the workspace, 0 now clip** (peak = max channel x Brightness, highest measured 0.89 on `Boss_Desert`). Console clean -- 0 errors, 0 warnings, 8 informational lines |
| 17.12 | `[ ]` | <!-- Kristina 2026-08-16: "vip skinovi nek soke na pocetku tj u forrestu izlozeni i nek se mogu kupiti robuxima" --> **The nine VIP skins are on sale nowhere a player can see them.** They exist inside the Journal, behind a panel, under a section a new player has no reason to scroll to — and they are the most expensive thing in the game. Put them ON DISPLAY in Forest, the starting zone: nine podiums each carrying the skin's real body from `Assets.SkinMeshes`, turning, with the name, its two multipliers and a Robux price, and a prompt that sells that one skin. New `VipShowcase` server module built on `HubPlaza`'s conventions (version-stamped furniture, not a placement search — see the note under `RebirthShrine`), plus a `robuxPrice` and a `productId` on every `GameConfig.VipCharacters` entry. **`productId` is 0 until the products exist**, and 0 must read as "not for sale yet" rather than firing a purchase that cannot complete | Walk into Forest at stage 1: nine lit podiums with the real bodies on them, each naming its price; the prompt on one either sells it or says plainly that it is not on sale yet | — |
| 17.13 | `[ ]` | <!-- Kristina 2026-08-16, with a screenshot of the pet inventory --> **Every action button on a pet card is a blank coloured pill.** Her capture of the pet panel shows six cards, each with a wide red/purple/green/blue button carrying **no text at all**, beside a legible `20 💎` cost pill — so it is the caption specifically, not the button, and not every button in the panel (the row below them reads fine). Same family as 12.3 and 12.6: `.Text`, `.TextColor3` and `TextFits` can all read correct while the glyph is invisible | Open the pet inventory: every button says what it does | — |
| 17.14 | `[ ]` | <!-- Kristina 2026-08-16, with a screenshot of the Rebirth panel at 4/4: "ovo preuredi i nabudzi sve" --> **The Rebirth panel is a dead end with a hole in the middle.** At 4/4 it reads "Ladder complete", "ALL REBIRTHS COMPLETE" on a greyed button, and a large empty orange box where the next milestone used to be described — the endgame's own screen tells the player there is nothing left. Two halves: **the ladder** (four milestones consumed once each, ending at x8 damage / x7 income — see the block over `GameConfig.MaxRebirths`) needs a tail that does not reintroduce the farm-the-cheapest-tier exploit the four replaced; and **the panel** needs re-laying so a finished ladder shows what was earned rather than an empty box | Rebirth past the fourth: there is a fifth, it costs something real, and the panel shows the whole ladder with the finished rungs marked | — |
| 17.15 | `[ ]` | <!-- Kristina 2026-08-16, with a reference screenshot from another game beside a capture of our own HUD: "ovo isto znaci imas ovo u shopu" --> **The shop reads as a list; the genre's shops read as a storefront.** Her reference is an **EXCLUSIVE SHOP!** panel: one large featured card across the top — a gold crown tile, `VIP! GAMEPASS`, its three effects as icon lines (`x1.5 CASH`, `x2.5 LUCK`, `SPECIAL CHAT TAG`), a green Robux price button and a red `NEW!` ribbon — then a grid of smaller gamepass cards under a `GAMEPASSES` header. Ours (2.10) renders passes as **wide text rows in a scroll**, chosen when nine product-sized tiles were 710 px in a 500 px panel; the reference solves that with a hierarchy instead — one hero row plus a grid — which is also where 17.12's nine VIP skins belong. The **shop button icon** is in the same message: hers is a chunky red basket on yellow, ours is a thin white trolley outline. Constraints that still hold: `MainUI` is at Luau's 200-local ceiling (build inside the existing `;(function() … end)()`), and every surface must go through `UITheme` | Open the Robux panel: a hero VIP card with its effects and price, a grid of passes under it, and a shop button whose icon reads at HUD size | — |
| 17.16 | `[ ]` | <!-- Kristina 2026-08-16, with a screenshot of the "Part To Water [ANIMATED]" toolbox plugin (FREE, @Kingdom504, 89% / 1K votes): "imas i ove pluginove da doradis vodu vodopade i sve da ima animacije i da bude real pretrazi to sve i ubaci da izgleda sto zive zivo" --> **Every water surface in the game is a still blue part.** The pools, the waterfalls and the zone ponds are painted geometry that does not move, in a world where everything else does. Her reference is a toolbox plugin that turns a part into an animated water surface; the same effect is reachable without a plugin dependency — a scrolling `Texture`/`SurfaceAppearance` pair on the existing part, plus `Beam`s for falling water — and that matters because a plugin runs at author time in one person's Studio while `ZoneBuilder` builds the world on the server at run time. **Find the free assets first** (`search_asset` over the Creator Store — the 596-asset harvest under `evolution-lab-free-asset-catalog` is the starting point, and animated water textures are exactly the kind of thing it already holds), then apply them from the builder so a rebuild keeps them. Scope: pool surfaces, the waterfalls, and whatever else in `ZoneBuilder`/`HubPlaza` is meant to read as liquid | Stand at a pool: the surface moves, and the waterfall falls — in a fresh Play, not only in the Edit session it was authored in | — |

---

## Phase 18 — "Izgleda kao da dobijam rewards u mrtvačnici" · *opened 2026-08-16 by four screenshots in one minute*

**Opened by the owner, mid-sweep, with four captures and no preamble.** Phase 16 and 17 fixed the UI
by *rule* — a dead `SetColor`, a missing rim, a lip on a stadium, a tint clipped to white — and every
one of those rows was right. What the captures say is that the screen can pass every rule in the file
and still be **grey, flat and joyless**, which is the one thing a game for children cannot be. Her
words, verbatim, because they are the spec: *"izgleda kao da dobijam rewards sto radim u
mrtvacnici"*, *"puno je sivo i monotono"*, *"celi ui mora biti prilagodjen da deci bude lepo i
pregledno"*, *"vece ikone"*, *"da sljasti sta je bitno"*, *"da ima neku dimenziju da izgleda 3d"*,
*"senke neke"*, *"vise nijansi boja ubaci"*.

**A numbering warning, because the code lies about it.** The 44th session (2026-08-16, four parallel
agents) shipped its work into `src/` and recorded it in the Changelog **without ever opening rows**,
and its comments cite ids — `17.13`, `17.18`, `18.1` — that were never written into this file. Those
citations are **not** the rows below: where a comment says "18.1" it means the idle-pulse work, not
the health bar. This table is authoritative; a stray id in a comment from that session is a note to
itself.

**The rule this phase is about, stated once.** Grey is what a UI kit reaches for when a thing is
*off* — claimed, locked, spent, complete. Every one of those states is the record of something the
player **did**, and this game paints all four of them in the same dead neutral, so a screen full of
achievement looks like a screen full of nothing. **A finished thing is not a disabled thing.** Where
grey is genuinely right (a button that cannot be pressed), it still needs the surface under it to
carry colour and depth.

| ID | | Task | Check | Verified how |
|---|---|---|---|---|
| 18.1 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot of the Alpha Bear boss bar: "ovaj health bar ne treba ove tamne stvari iza nema smisla to" --> **Every progress bar still wears two near-black caps, and 17.8 fixed the wrong half of it.** 17.8 found the lip (`ShadowBody` shifted 6 px down) and removed it on round shells — correct, and it is not what she photographed today. The remaining cause is the **clip**: `UITheme.ProgressBar` sets `ClipsDescendants` on a host that has **no `UICorner` of its own**, so the clip rectangle is square while both shell bodies inside it are pills carrying a 4 px `UIStroke` drawn *outside* their curve. The four corner regions — inside the square, outside the pill — are exactly where those strokes are still visible, and at `Radius.Pill` the two at each end merge into one dark crescent capping the bar. Same fault on the creature nameplates (`CreaturePlate`, 3 px stroke) and the boss plate. **The fix is not to round the clip** — a rounded clip on a host the same size as its body would cut the outline off the whole bar — it is to stop clipping at the host and let the fill be clipped by `InnerBody`, which already clips and already carries the right radius | Bring up a boss bar at any fill level: an even outline all the way round and nothing dark at either end | **isolated on the live bar before a line was written, then fixed at the source and re-photographed.** The isolation was the whole of the diagnosis: with nothing changed but `ClipsDescendants = false` and the fill reparented **on the running boss bar**, the caps vanished from the capture and the outline closed round both ends — the before/after pair was taken from the same camera, seconds apart, on the same 2.4x-scaled bar. After the source fix, pushed and re-measured on a fresh Play: **14 progress bars in the HUD carry their fill inside `InnerBody` and 0 of them still clip at the host**, the server-built `CreaturePlate` reads `clip=false fillParent=InnerBody` (so the same fix reached the world billboards, which were never touched by hand), and the four remaining direct-child fills are the Audio panel's sliders, which are hand-built, do not clip, and never had the fault. Photographed on the evolve bar at 2.2x: a clean green capsule with one even dark outline and nothing dark at either end. Two callers looked the fill up **by name** off the bar and would have failed silently — `UITheme.SetProgress` (early `return`, every bar in the game stops moving with nothing in the console) and `SplicerUI`'s pity bar; both are recursive now, and MainUI's third was a direct index that would have thrown |
| 18.2 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot of the currency stack: "ovo je lose ne vidi se nista od ovog okolo il napravi belje il lepse ne znam" --> **The wallet is three saturated blocks in the corner of a pastel world.** The 44th session gave the pills a body (they were bare outlined text) and then, on her own note — *"nemoj te crne vec bright pastel i beli theme"* — painted them Mint / Aqua / Lavender. Measured live: rgb(68,225,145), rgb(105,205,250), rgb(175,138,250) — those are **candy, not pastel**, and stacked three deep at 250 px wide they are the loudest object on a screen whose job is to show a village. She is asking for the next step down, not for the dark bar back: a near-white capsule that reads as *chrome*, with the currency's identity carried by the icon disc and the `+` button, which are the two things that should be loud | Look at the bottom-left corner: three quiet white capsules, each tellable apart at a glance, and the village behind them still readable | **measured and photographed on the live HUD.** Each shell is now `Color.Frost` lerped **16% toward its own currency's hue** — both ends of every lerp an existing kit token, so no new colour is on screen — and the hand-typed ink `rgb(46,34,66)` became `Color.Ink`. Live fills: rgb(212,240,234) / rgb(218,236,251) / rgb(229,226,251), **luminance 0.91 / 0.91 / 0.90** against the 0.66 / 0.71 / 0.64 they were, i.e. all three sit above `LIGHT_SURFACE` (0.86) and take dark ink by the same rule rather than by a hardcode. Ink contrast went **8.4:1 → 11.8 / 11.8 / 11.2:1** — quieter *and* more legible, which is the pair that says the loudness was never doing the reading. Photographed over The Absolute Plane, the palest ground in the game: three near-white capsules with the identity in the emoji and the coloured `+` discs, and the street behind them legible. Deliberately **no icon disc**: the icon slot is 40 px inside a 46 px capsule, so a disc behind a `ScaleType.Fit` glyph either hides under the art or costs 6–12 px of the glyph itself |
| 18.3 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot of the Daily Rewards panel --> **A week of rewards you already earned is drawn as six grey slabs.** Days 1–6 are claimed, and claimed is painted `rgb(~110)` flat with a small green tick — so the panel that exists to say *look what you have collected* is six-sevenths mortuary grey, with one bright tile at the end. Her three asks are all about the same thing: **bigger icons** (the reward glyph is smaller than the day chip above it), **colour** (a claimed day should keep its reward's own hue, dimmed but not drained), and **depth** (every tile is a flat rectangle; nothing on the panel casts anything). The Day 7 tile is the control that proves the rest is fixable — it is the only one anybody would call finished | Open Daily Rewards on a 6-day streak: six *collected* days, each still carrying its reward's colour, and one that plainly is not | **photographed on her own save, at the same 6-day streak as her capture.** Seven hues where there was one: the idle colour comes from a per-day ramp of kit tokens (Aqua → Lavender → Bubblegum → Coral → Peach → Sunny → Gold for the hero) and **nothing in the ramp is green**, so the claimable tile's Green can never collide with an idle one. The three states now separate on three axes rather than on brightness alone — claimable = full chroma + a thicker rim + a CLAIM! chip + the idle pulse, **collected = `UITheme.DoneShade` of the day's own hue** (same hue, a third of the chroma, luminance 0.90), not-yet = full strength with no tick; `Color.Locked` is gone from this panel entirely. Icons **56 → 84 px** on a small tile and 130 → 164 on the hero, each on a `Plinth` at `shade(fill, −0.16)` so every tile has a second plane in it, with `CELL_H` 152 → 182 and the panel 578 → 638 to pay for it. `bonusLabel`'s ink went white → dark: at 17 pt on a 0.97 surface it had been read entirely off its halo. The capture is six collected days in six different pastels with a gold hero — against her capture of six grey slabs. **Not photographed: the pulse and the CLAIM! chip**, because at a 6-day streak with today already collected there is nothing claimable to draw them on; `UITheme.Attention` is wired at `priority = 2` and gated on the panel's own `Visible`, so a hidden panel cannot hold the kit's single pulse slot |
| 18.4 | `[x]` | <!-- Kristina 2026-08-16, with a screenshot of the Rebirth panel at 4/4: "puno je sivo i monotono" --> **The endgame's own screen is a grey button under an empty orange box.** Overlaps 17.14, which opened on the same panel and is about the *ladder* (a fourth rebirth that ends the game's biggest system with nothing after it). This row is the other half and can ship without it: the panel is one hue plus a grey, the 4/4 state fills a third of the card with an empty amber slab, and "ALL REBIRTHS COMPLETE" — the sentence that should be the proudest line in the game — is grey text on a grey button | Open Rebirth at 4/4: the completed ladder reads as an achievement, not as a disabled control | **photographed at 4/4, the exact state she captured.** The empty amber slab now holds **four rung rows** — a full-chroma numbered disc (Aqua / Mint / Lavender / Gold), the stage it was taken at, and the running totals it left (`⚔️ x2.00 🧬 x2.50` … `x8.00 / x7.00`), each row filled with `DoneShade` of its own hue — read from the same `GameConfig` functions the live branches call, so the card cannot drift from the grant. Row height is computed off the card and the rung count, so **17.14's fifth rebirth needs no edit here**. "ALL REBIRTHS COMPLETE" is `Color.Gold` with a 🏆 instead of `Color.Locked`, and `Active` stays false — the button is still not pressable, it just stops apologising for it. The `stage` branch keeps `Locked`, because that button genuinely *is* refused. Five hues on the finished panel where there were two. The prose and the rungs share the 176 px card and are shown one at a time |
| 18.5 | `[x]` | <!-- Kristina 2026-08-16: "da ima neku dimenziju da izgleda 3d senke neke vis nijansi boja ubaci" --> **Nothing in this UI casts a shadow, and that is a deliberate decision that has outlived its reason.** `addShadow` is a **no-op returning `nil`** — removed 2026-08-11 after she reported the old one as "an ugly line at the bottom of the button that even sticks out", and both variants deserved it: one was a square sibling behind a rounded shell, the other a full-width bar carrying the shell's whole radius. What replaced them is the shell's own gradient plus a heavy outline, which is real depth but *moulded* depth — the surface looks thick and still lies flat on the screen. A shadow that follows a rounded shell at any radius needs a **soft sprite**, not a rectangle: one 9-slice image, tinted, under the shell, offset down. Same row carries "više nijansi boja": the kit's neutral ladder is where every one of these greys comes from, and it is shorter than the work being asked of it | Any panel, tile and button: each sits *above* what is behind it, and no shadow is visible outside its own shell at any corner radius | **built, uploaded, photographed and measured; 331 of them are drawing on the live HUD.** The sprite is `tools/make_shadow.py` → `assets/ui/shadow.png` → **`rbxassetid://105729101275739`**: 192², rounded rect inset 48 at radius 30, Gaussian sigma 14, **alpha-only** (black RGB everywhere, so `ImageColor3` cannot pick up a fringe), nine-sliced at `Rect(78,78,114,114)`. It is a **child** of the shell, which is what fixes the half of the 2026-08-11 complaint nobody wrote down: the press squash is a `UIScale` on the button, so the old *sibling* shadow never shrank with it and popped out around the pressed button. Skipped on round shells and on the server, both for reasons in the code. **`applyShell` calls it; `MainUI.styleCard` had to be told to** — 77 of the 78 surface builds in that file go through `styleCard`, so that one line is the whole HUD. Prototyped on 357 live surfaces before any of it was written and photographed from the same camera: depth at every tile, **no hard crescent at any corner**. One trap it exposed on landing: `liftChildren`'s `ChildAdded` hook would have lifted the sprite from `ZIndex − 1` to `+Z.Content` and drawn a 62%-transparent haze over every card face in the file — the 15.28 `ShadowBody` bug exactly, so `DropShadow` is on that skip list. And the risk that was measured rather than assumed: removing all 345 prototype shadows moved **0 of 15 `ScrollingFrame` canvases**, so a shadow hanging 24 px outside its tile creates no phantom scroll space. Second half of the row shipped as **`UITheme.DoneShade`** — see 18.3, and the readme, where "a finished thing is not a disabled thing" is now a rule with three states on three axes |
| 18.6 | `[ ]` | <!-- Kristina 2026-08-16, with a screenshot of the Season panel: "ovde imaju 2 progres bara sta ce mi, popravi to do kraja i nabudzi u nekim bojama, sve panele odradi pa mi onda pisi, sve hocu da bude top" --> **The same three faults, measured across all nineteen panels at once.** Her screenshot is the Season panel showing the *same number twice* — the level card's `SeasonXP` bar and the 30-segment `Rail` between the free and premium rows are both progress readouts of the same fraction. That is the specific complaint; the sweep behind it is the general one. Measured on the live client, per panel: **SeasonPanel carries 88 `Color.Locked` surfaces and a `TrackTray` at rgb(104,98,138), luminance 0.41 over 182,000 px² — the darkest surface in the game** on a screen where every other panel is light; MasteryPanel 20 greys plus one surface at luminance **0.12**; RobuxPanel 9; Inventory / Character / Egg 4 each. Add the flat ones a colour probe cannot see: ZonesPanel's rows are desaturated mud where `GameConfig` holds a real colour per zone, ShopFrame's four DNA tiles are one green with a **dead grey rectangle** where a fourth would go, the Journal's preview pane is a large empty grey slab, the Auras rows are white on white with the **"Wearing" button painted in the refusal grey**, and Inventory has a wide empty white band beside its tabs. One rule fixes most of it and it is already in the kit: **claimed / mastered / owned / passed is `DoneShade`, not `Locked`** | Open every panel in turn: no panel has two readouts of one number, no panel has a surface darker than the rest of the game, and nothing that was *earned* is painted the colour of a refusal | — |
| 18.7 | `[ ]` | <!-- found 2026-08-16 while sweeping for 18.6 --> **The DNA Splicer is the one screen built by another file, and it shows.** `SplicerUI` is its own `ScreenGui`, so every pass over `MainUI` has missed it: its odds table is printed on a **`PanelBlue` slab at luminance 0.59** with seven rarity colours competing against the card instead of against each other (Common sinks into it, Secret is near-black on mid-blue), the percentages are **cream on that same card**, its close button is the only rounded **square** with a capital **X** in a game of red discs with a ✕, the worn-mutation card is a fixed lavender with the rarity printed as coloured *text* on it (Mythic's red on lavender), and the pity meter is a 16 px stripe carrying no number at all | Open the Splicer: seven rarities legible as a ladder, the card wearing what you are wearing, and a meter that says how far along it is | — |
| 18.8 | `[ ]` | <!-- root cause of 17.13, found 2026-08-16 by measuring the pet cards she photographed --> **A caption handed to a shell disappears, and this is the fourth time it has shipped.** `EnchantChip` on every pet card is a `TextLabel` at ZIndex 32 that `styleCard` shells with `InnerBody` at **33** and `Gloss` at **34** — so its text is painted over and the card shows a blank coloured pill, which is exactly the screenshot behind **17.13**. Every property reads correct: `.Text` is right, `TextFits` is **true**, `TextBounds` 66x15 in an 84x28 box. 16.6 fixed this for the two Inventory tabs, 15.37 for the Journal disc, and each fix was local. The mechanism fix is one function — mirror the caption into a `Label` child above the body, keep the host's string (so call sites that read it back still work) and stop the host drawing it — called from `applyShell` for the kit's own widgets and from `MainUI.styleCard` for the 77 of 78 surfaces the kit does not build | Sweep every text run in the HUD for a caption whose own ZIndex is at or below an opaque `InnerBody`: zero, and the pet cards say what their buttons do | — |

---

## 👤 Owner action checklist

Collect these once; each one blocks agents until it exists.

| | Action | Blocks |
|---|---|---|
| `[x]` | Publish a test place — `MessagingService` cannot be exercised from Studio at all, and neither can two clients trading | 5.4, 8.6 — **done 2026-08-11**: published to **Evolution Lab BETA V0.2**, universe `10675543038`, place `102217824272435`. Both rows are now buildable |
| `[ ]` | **One real Robux purchase** on the published place — the only thing that exercises `ProcessReceipt` and Roblox's billing. Studio's `IsStudio()` pass grant tests effects, never purchases. **It cannot be faked from a probe and now it is proven why: `ProcessReceipt` is a Roblox *callback member*, so it can be assigned but never read** — the live handler cannot be invoked, and `require` hands back a fresh service whose cache is empty. Cheapest route is any 49 R$ tile | 1.7, 2.11, 3.8, and now 11.12 |
| `[ ]` | Roblox group id, for the Group / Like / Favourite rewards | 5.5 |
| `[ ]` | Rewarded Ads set up on the dashboard (the free spin half of 5.6 is done) | 5.6 |
| `[x]` | Save the place into the repo (binary `.rbxl` is fine — `tools/rbxl_extract.py` reads it) | 0.1 — done 2026-08-08 |
| `[ ]` | `StreamingMinRadius` / `TargetRadius` / `IntegrityMode` in Properties | 0.4 |
| `[x]` | Create the 7 existing developer products, paste ids | 1.7 — done 2026-08-11 |
| `[x]` | Create the 9 game passes, paste ids | 2.11 — done 2026-08-11, all with "Item for sale" on |
| `[x]` | Create the 10 new developer products, paste ids (the shop is 17 rows now — see 3.8) | 3.8 — done 2026-08-11, 26 ids in total |
| `[ ]` | Game icon and thumbnail | 6.5 |
| `[x]` | **Turn off the Boss Revive product's sale** on the dashboard. The receipt branch stays in code on purpose so in-flight purchases are still honoured — see 11.7 | 11.7 — **done 2026-08-12**: product `3702254100` now reads **Offsale** on the Developer Products list. Note for anyone who assumed otherwise: a developer product **does** carry an `Item for sale` toggle, same as a pass |
| `[x]` | **Create a shard pack** developer product and paste the real `productId` | 11.12 — **done 2026-08-12**, and done by an agent rather than by hand: Kristina granted browser access, so the three products were created on the Creator Dashboard in-session. `25 Evolution Shards` **3707419817** / 49, `125 Evolution Shards` **3707425807** / 199, `750 Evolution Shards` **3707431292** / 999, all with Managed Pricing **Disabled** to match the other 26 |
| `[x]` | **Match the two Catalyst prices on the dashboard** — 11.7 moved them to **49** (`TierUp_1`, id 3702254553) and **129** (`TierUp_3`, id 3702254989). The number in `GameConfig` is only what the card prints; the dashboard is what actually charges | 11.7 — **done 2026-08-12**, both verified back on the Developer Products list: Rainbow Catalyst **49**, Catalyst x3 **129**. `GameConfig` and the dashboard now agree |
| `[ ]` | **One real rebirth** from a late zone on the published place, to close 11.1 end-to-end. It costs the runner their progress, which is why no agent has done it | 11.1 |
| `[ ]` | **Save the place and republish — and this one now carries six new assets, not only hygiene.** 16.9's six generated skin meshes (`SkinMesh_vip_gold` and the five event skins) are **instances in the unsaved Studio session**. They are not files, so no commit and nothing in `src/` carries them: a Studio restart before a save loses all six and they have to be regenerated. Save first, then publish | 16.9 |
| `[ ]` | **Save the place and republish, to make the `LightConfig` deletion real.** The backdoor was destroyed in the Edit session on 2026-08-15 but an MCP edit lives only in an unsaved session ([[evolution-lab-studio-work-is-volatile]]). The published copy still holds it until then — inert (a `Disabled` Script in `ServerStorage`), so this is hygiene rather than an emergency, but it should not survive the next publish | 15.10 |
| `[x]` | Prism Festival dates in `GameConfig.Events` — a design decision, not an id, so edit freely | 7.4 — decided 2026-08-10: 4–7 September 2026, the authored window, unchanged |

---

## Reference — what the market does

Gathered 2026-08-07/08 while writing this plan.

- **+1 Speed Evolve** (17.5M+ plays): Infinite Revives 299, +3 Items Equip 199, 2x Wins 149,
  Gold/Diamond/Ruby Treadmill 79/199/1099, exclusive forms 99–399. Has a codes system — which is
  why it gets a monthly article on every Roblox codes site.
- **Pet Simulator 99**: layered loop — eggs → luck → index → prestige → trading → seasonal events.
  2x Luck, Auto Tap, +15 Pets, VIP 400.
- **Grow a Garden / Steal a Brainrot** (22–25M concurrent): limited-time "admin" events with
  exclusive characters are the engine of both engagement and revenue.
- Common price shape everywhere: cheap entry pass 49–99 → core multipliers 149–299 → premium
  399–1000+. The cheapest pass is the gateway; the multipliers are where the money is.

---

## Changelog

- **2026-08-16 (forty-fifth session)** — **PHASE 18 OPENED AND CLOSED IN ONE SITTING: FOUR
  SCREENSHOTS, FIVE ROWS, ALL FIVE VERIFIED LIVE.** She sent them mid-sweep with no preamble —
  the currency stack, the Daily Rewards panel, the Rebirth panel at 4/4, and a boss health bar —
  and the thread through all four is that the screen can pass every rule in this file and still be
  grey, flat and joyless. The phase's one rule: **a finished thing is not a disabled thing.** Grey
  is the kit's answer to four states and only three of them are refusals.
  **The session opened on a real risk and cleared it first:** the 44th session's work was
  uncommitted on disk, `MainUI`/`VFXLibrary`/`EvolutionVisuals` were already byte-identical to
  Studio, but `UITheme` was 14 KB ahead on disk and **Studio's copy matched no commit in 19
  revisions** — so it was pulled out over the bridge and diffed before anything was written over it
  (12 divergent lines, all the older inline form of the same press motion the disk copy evolved),
  then committed.
  **18.1 was 17.8's other half and it is a general Roblox fact worth keeping:** a `ClipsDescendants`
  host with no `UICorner` clips to a **square**, so a pill-shaped child's `UIStroke` — drawn outside
  its curve — survives in exactly the four corner regions, which at `Radius.Pill` merge into one
  near-black cap at each end. Rounding the clip is the obvious fix and is wrong (it would cut the
  outline off the whole bar); the fill moves into `InnerBody`, which already clips at the right
  radius. Two by-name lookups would have failed **silently** (`SetProgress` early-returns, so every
  bar in the game stops moving with nothing in the console) and one would have thrown.
  **18.5 gave the kit a shadow that can be soft.** `addShadow` had been a no-op since 2026-08-11 and
  both removed variants failed for one geometric reason: **a Frame has one hard edge and a cast
  shadow is alpha falling off over a distance**, so any offset copy of a rounded shell pokes a
  crescent out of the corners the shell has curved away from. It is a nine-sliced alpha sprite now
  (`tools/make_shadow.py`, uploaded, 331 drawing live), a **child** so it shrinks with the press.
  The kit now has two shadows and they do different jobs — the lip makes a surface *thick*, the
  sprite makes it *raised* — and the readme's "hard-edged shadows only" line was amended to say so.
  **And `PanelFocus` finally exists in the place**: written by the 44th session, never pushed, so
  the world-dim behind an open panel had been on disk and nowhere else for a day.
  Not committed by anyone before this session: the 44th's whole UI pass. **Numbering warning now in
  the phase header** — that session's code cites row ids (17.13, 17.18, 18.1) that were never
  written into this file.

- **2026-08-16 (forty-fourth session)** — **UI POLISH PASS, DRIVEN BY CAPTURES RATHER THAN BY THE
  CODE.** Four parallel agents, split on the file seam. Two things shipped that the whole HUD had
  been missing, and both were found by photographing it rather than reading it:
  **(1) The three currency readouts had no body at all.** `UITheme.Pill` built a frame at
  `BackgroundTransparency = 1` with no `InnerBody` and no stroke, so DNA / Diamonds / Shards were
  bare outlined text lying on the 3D world while every other element was a chunky capsule. `Pill`
  takes an opt-in `shellColor` now (routed through `applyShell`, so the capsule inherits gradient,
  gloss, outline and lip wholesale; `nil` is byte-identical to the old behaviour). One dark indigo
  for all three — a wallet is one readout, and the HUD tiles already own every saturated colour.
  **(2) A generic scroll-affordance sweep over all 15 `ScrollingFrame`s.** 13 of 15 had no bottom
  padding, so the last row was sliced flat by the panel edge; **9 of 15 had a white scrollbar on a
  white panel** and were therefore invisible. The pass adds a visible 10 px bar, 14 px of tail, and
  a bottom fade that only shows when content is genuinely below the fold. It knows no panel by name,
  so a panel added later is covered too. Verified: 15/15 correct, 1,617 labels, 0 clipped.
  Also: **InventoryPanel converted to `UITheme.PanelHeader`** — its title and tab strip had been
  drawn at negative Y, i.e. *outside* the card on the scenery, and the `BoostStrip` reserved 90 px
  of white for three timers that are almost never running (rows positioned by index, so one running
  boost drew itself 60 px down an empty band). The boost readout is the header's subtitle now; net
  **−3 top-level registers**, so MainUI went 178 → 175 of 200. **`Color.Unaffordable` added** —
  "you are short" and "this is locked" had been the same grey in **both** upgrade rows, not just the
  diamond one. Diamond row moved onto the DNA row's grid (`Center` → `Left`) and given the same dark
  price chip. World-event chips 24 → 32 px tall with 12 px of bottom clearance (`clearance + height`
  must stay ≤ `BOTTOM_CLEAR` = 46 or the bar slides under the tile cluster on a phone).
  **And the max-stage aura stopped erasing the creature** — *"ne vidim lika koliko svetli"*. Three
  independent causes, none of them the two properties this bug family had already been fixed
  through twice: a `PointLight` at **Brightness 8.0** at stage 20 (unclamped `1 + i * 0.35`, written
  when a player was a 1x avatar), additive particle layers shipped at **Transparency 0.00** that
  stack to white four deep in the middle of the frame and one deep at the rim (hence the red
  fringe), and **ground sprites hung at the HumanoidRootPart**, 23.6 studs above the feet with the
  camera standing inside the ring. Fixed as a brightness ceiling (2.5), a new shape-preserving
  `minTransparency` floor in `VFXLibrary.Attach`, and a caller-supplied drop halfway to the feet —
  the drop is passed **in** because the pet rigs share this function with a `scale` in different
  units and a shared formula would bury their auras underground. Stage 20's colour is also
  `rgb(255,255,255)`, so the light now takes the **worn character's** colour, not the stage's.
  **Two claims I made from a probe and had to withdraw:** the grey diamond row was not a bug (76 /
  122 / 468 💎 against a balance of 10 — the grey was true), and my "64 px of clearance" reading of
  the event bar was a Studio-coordinate artefact; the code's 5 px was right. **And one regression I
  caused and the capture caught:** raising the chip name to 14 px truncated "Colosseum Clash" to
  "Colosseum...". `TextBounds` read 76 × 14 in an 86 × 20 box — fits by every number — because it
  reports what was *rendered*, i.e. the already-truncated string. `TextFits` was the only property
  telling the truth and it was the one that looked wrong. Measured with `GetTextBoundsAsync`: that
  string needs 100 px at 14, 87 at 12. The original 12 px was tuned to exactly it.
  `guidelines/ui-research-2026.md` written (genre reference: currency anatomy, motion specs, HUD
  density, panel anatomy, legibility over a bright world). **Not committed** — Kristina has not
  asked for a commit.
  Still open: **9 of 19 panels do not use `PanelHeader`** (Zones, Rebirth, Season, Audio, Egg,
  Reward, Playtime, Pets, and Inventory's sibling), with content starting anywhere from 56 to 106
  and margins of 14 / 18 / 20 / 22; and `UITheme.PressMotion` exists now but the shadow-compression
  half of it has not been photographed.

- **2026-08-16 (forty-third session, second half)** — **THE WHITE STREAK FOLLOWING HER WAS 17.1'S
  OWN FIX, ONE PROPERTY TOO FAR.** One screenshot and four words — *"sta je ovo sto prati"* — and the
  answer was not a `Beam`, a `Trail` or a stray part: swept live, there is no beam or trail within 60
  studs of the player and nothing long and thin that is not anchored scenery. It is the **mutation
  aura's floor sprites**, four emitters up to **24.7 studs** at Transparency **0.00**, hanging off
  the body as an opaque quad several times the character's width. Photographed from above it is a
  black diamond on green grass; from a low camera the same flat quad projects edge-on as her streak.
  **`applyTint` had capped `LightEmission` to 0.35 alongside `Brightness`, and the two do different
  jobs.** Brightness multiplies the colour — that is 17.1's finding and its cap is the whole fix.
  LightEmission decides how *additively* the sprite blends, and these pack textures are drawn on a
  **black background that only disappears because it is added onto the scene**. Lower it and the
  black is composited as black. The ceiling is gone; an effect's authored LightEmission is a property
  of how the texture was drawn, not something a tint gets to decide. **The isolation is what makes
  this a measurement rather than a theory:** one property moved on the live body, nothing else, and
  the quad vanished while the aura stayed **red**. Re-measured through the real server path after a
  restart — `B=1.00 LE=1.00 col=255,80,80`, 0 of 112 world emitters above brightness 1.5, and across
  all **98 tinted emitters, 0 clip**. Console clean. Row **17.17**.
  **The general lesson, and it is the second time this session:** a fix that bundles two properties
  under one rationale will be right about one of them. 17.1 wrote "1 / 0.35" as a single ceiling with
  a single sentence of reasoning; the brightness half was measured and the emission half was
  asserted, and only the asserted half came back as a bug report.
- **2026-08-16 (forty-third session)** — **THE CROWN WAS STILL THERE, AND THE ROW THAT REMOVED IT
  HAD CHANGED NOTHING.** 17.11 was closed the session before on the reasoning that dropping the
  `regalia` field from the nine VIP entries would be enough, because `StageCostume.Regalia` "already
  no-ops without it". It does not: the guard is **`offLadder`**, which every VIP entry still carries,
  and `headPiece` ended in a bare `else -> crown(...)`. So an entry naming no piece got the crown by
  *default*, and a live character wearing `vip_gold` measured `StageCrownBand` 1 + `StageCrownSpike`
  5 — her screenshot, unchanged. **The lesson is the one this project keeps paying for: a field
  removed from config is not a behaviour removed from code, and a `[~]` that says "no code changed"
  is a claim to go and check rather than a reassurance.** Fixed at the fallback — nil draws nothing,
  the band needs an explicit `regalia = "crown"`, and an unrecognised name is silent rather than
  quietly crowned. After, same body same camera: `RegaliaPlinth` 16 and nothing else. Rows **17.11**
  and, alongside it, **17.10**: all nine baked VIP bodies verified in the place (folder **214**,
  16-18 MeshParts each, **rig hardware 0**, `Head` on all nine, `SkinMesh.Apply` ok and **stuck=0**)
  and photographed in three groups through the shipped module. **One capture trap from that pass
  worth keeping: the bodies top out at y 402.54 and the first framing was shot from 403.6** — from
  above every head, which reads as nine headless suits and is a fault in the camera, not the bake.
  Heads sit at 399.89-401.71; re-shot at head height, all nine read as their catalog figures.
- **2026-08-16 (forty-second session)** — **THE HUD HAD 324 CAPSULES AND ALL 324 WERE WEARING A
  BLACK CAP AT EACH END.** One screenshot of the boss bar and one sentence — *"popravi i ove health
  barove da budu ovalni ima nesto crno iza"* — and the cause is a single line shared by the game's
  two surface builders: the lip is the body's own rectangle shifted down 6 px, which reads as
  thickness under a card and swings out of the flanks of a **stadium**, where the sides are the
  curve. `ProgressBar` clips the overflow square, which is what turned two crescents into two black
  blocks. `applyShell` and `MainUI.styleCard` now give a round shell no lip at all — the depth there
  was always the body's gradient and the heavy outline, the same conclusion `addShadow` reached in
  2026-08-11 one shape earlier. Found in the same pass and fixed with it: three bars had asked for a
  pixel radius and were the only rounded-rectangles among a dozen pills, and **`MainUI.styleCard`
  snapped its stroke but not its corner**, so the shape scale governed every surface except the
  screen. The ladder went 10/16/20 → **14/22/30** and now snaps **up only**, so no surface in the
  game can come out squarer than it was authored. Verified: 324 pill shells, **0** still lipped;
  console clean; `src/` byte-identical to Studio on all four files. Row **17.8**.
  **Then 17.7 closed in the same session, and its own opening measurement had pointed the wrong
  way.** That row was written as "the cause is global rather than per-zone" off a Lighting probe —
  brightness, haze, bloom, grade. It is per-zone, and it is the floor's **material** before its
  colour: `GROUND_MATERIAL` gave three zones `Enum.Material.Neon`, which is drawn at full colour
  with *no lighting applied at all*, on a part measuring **1250 x 4 x 1150**. At that size Neon is
  not a material, it is a lightbox — and the tell is in the before capture, where not one lamp
  post, fence or egg on the whole street casts a contact shadow. Colour was the second half:
  AbsolutePlane's ground is the only one of twenty above a 0.80 luminance ceiling, at **1.00**. Both
  fixed at the source: three floors to Foil/Marble/Marble, and a `GROUND_MAX_LUM` ceiling in
  `ZoneBuilder` beside the floor — the same shape of fix as 17.1's emitter ceiling in `VFXLibrary`,
  and for the same reason. Nothing global was touched. Measured on a real 133 → **135** rebuild:
  floor rgb 255,255,255 Neon → **204,204,204 Marble**, Neon parts 731 → **484**, parts over 0.85
  luminance **21% → 19%** against Forest's 17%. **The lesson worth keeping: a Lighting probe
  measures the room, not the surface** — every number in the original row was true and none of them
  was the cause.
- **2026-08-16 (fortieth session)** — **PHASE 17 OPENED, AND THE AURA WAS NEVER PURPLE.** The
  session-start sweep was the first thing and it was clean — **50 of 50** scripts byte-identical
  between `src/` and Studio — and with every remaining row owner-blocked, the next move was to look
  at the game rather than at the file. The first capture of the live HUD had a white smear over the
  lower two thirds of the frame; muting three emitters gave the village back. The cause is one
  property pair: a `ParticleEmitter` draws `Color × Brightness` and adds it to the scene at
  `LightEmission = 1`, so the pack's demo-scene values (5, 10, and one boss at **500**) clipped
  every tint this game asks for to white — **33 of 110** emitters in the workspace, including all
  three of the worn aura's and **21 on the equipped pets**. `VFXLibrary.applyTint` now caps a
  tinted emitter at 1 / 0.35 on every path, and the same aura came back through the real server
  path as a purple swirl with the whole street legible through it (**0 of 103** emitters above 1.5
  now). 17.1 is `[x]`, photographed both ways. 17.2 is open **and it is a decision, not a task**:
  at the last stage the body is ~39 studs tall against a 12.5-stud camera zoom, so the camera
  stands inside the character — the aura's *ground* ring hangs 23.64 studs above the feet at eye
  level, dropping it to the floor hides it from the wearer, and pushing the camera out to 62.5
  studs puts it inside the village scenery (that capture came back black). Both were tried live
  before the row was written.
- **2026-08-16 (thirty-ninth session)** — **THE ITEM THAT TAKES MONEY WAS THE WORST-LOOKING THING
  ON THE SCREEN.** One sentence from Kristina — *"ovi VIP karakteri izgledaju losije nego obicni"* —
  and it is a structural fact rather than a matter of taste. All 200 ladder skins have a generated
  model in `ReplicatedStorage.Assets.SkinMeshes` and wear it. The **six skins outside the ladder**
  (`vip_gold` and the five event skins) have none, so `SkinMesh.Has` returns false and every one of
  them falls through to `StageCostume`'s primitives. Both `GameConfig` comments state this and call
  it fine — *"There is no generated SkinMesh_vip_gold, and that is fine"* — and it **was** fine, for
  exactly as long as the ladder was primitives too. **A comment can be correct when it is written
  and become a bug report later without a single line around it changing**, which is the general
  lesson and the reason this went a whole phase unnoticed: nothing broke, the rest of the game
  improved past it.

  Split into two rows because the report has two halves and only one of them is a mesh. **16.9** is
  the six generations, and it is **blocked, not untried** — Studio was not running for any of this
  session (`list_roblox_studios` empty, only `RobloxPlayerBeta` in the process list) and
  `generate_mesh` is a Studio MCP tool. **16.10** is the half a mesh does not fix: with a model, an
  off-ladder skin would differ from a ladder Legendary only by its colour, and all six of them are
  Legendary, so `skinMarks`' rarity flourish hands them exactly the halo, orbitals and emitter that
  40 ladder skins already wear. `StageCostume.Regalia` is hardware **no ladder skin can have** — a
  head piece, shoulder plates and a turning ring of light at the feet.

  **Three decisions in it worth not re-deriving.** The head piece is chosen by the **entry and never
  by the rarity**, because rarity separates none of these six from each other: a crown for the pass,
  one shared gold laurel for the four Colosseum champions (the wreath says *champion*, the colour
  says *which* — four unique ones would be four unrelated items where the point is a set), turning
  shards for the Prism Herald. The pauldrons weld to the **arms, not the torso**, because a shoulder
  plate that stays put while the arm swings past it reads as a bug rather than as armour. And the
  foot ring is dropped off the Humanoid's **`HipHeight`** rather than off a constant: the body runs
  1x at Cell and 9x at the last stage, so a drop authored at either end is buried in the floor at
  one and floating at knee height at the other.

  It is **public and called from three places**, because a body can be dressed by a builder, by a
  mesh, or by neither — the builder path runs it inside the same `pcall` after `skinMarks`, Apply's
  mesh branch runs it before returning (so it survives 16.9 landing), and `CharacterPreview` runs it
  with `static`, since a ViewportFrame renders neither a tweened weld nor a particle. Everything
  goes into the **same folder the costume uses**, so `Clear` already takes it away and there is no
  second teardown path to forget.

  **Studio was closed for the first half of the session and opened mid-way**, which is the only
  reason both rows closed. The sweep that followed found **47 of 50 identical** and the three that
  were not were exactly the three edited on disk, each matching `HEAD` byte for byte — so Studio
  held nothing of its own and the push was a clean fast-forward. Six `generate_mesh` calls in
  parallel, all six back with their named segments, **all six facing +Z and therefore flagged
  `FaceFlip`** — and that was *proved against a control* rather than assumed: `bact_dust` (flag set)
  shows its eyes from +Z, `hum_knight` (no flag) shows the back of its helmet from the same camera.
  The folder is 206 now.

  **Two numbers the first capture corrected, and both were invisible to every probe that had run.**
  The plinth ring was dropped off `Humanoid.HipHeight`, which is wrong at both ends: `PreviewRig` —
  the rig every Journal card is built from — has no HipHeight at all, so the fallback floated the
  ring **1.07 studs above the feet**, and a real character in Play measured **HipHeight 14.84**,
  which would have buried it far below the floor. It is measured off the lowest bare limb now, the
  same thing `SkinMesh` measures and for the same reason: a measurement instead of a proxy. And the
  ring was authored at 0.95x the *torso* inside a body **4.88 wide across the arms**, so it sat
  under the character rather than around it.

  **The pauldrons are the general rule this row paid for: a generated mesh does not put its limbs
  where the avatar's limbs are.** It is scaled to the body's HEIGHT and is free to be a barrel with
  two stubs low on its front, while the R15 `LeftUpperArm` stays out at the bare avatar's shoulder —
  measured at ±1.83 from centre against a body drawn 5.35 wide, and both captures show the plates
  hanging beside the character as gold bars attached to nothing. So shoulder armour is welded on the
  **builder path only**, where the shells genuinely are built around those limbs; the head piece
  (welded to the head, which a height-matched mesh does line up with) and the plinth (measured off
  the drawn body) carry the mesh path instead. Same family of mistake as the crown, which was sized
  to the bare head at 1.74 wide on a body drawn 5.35 across and read as a party hat.

  **16.1 closed in the same session, on a HUD with two real boosts and a worn aura.** Two potions
  used through the real `UsePotion` remote drew as **216x38 capsules** at a 6 px gap; `PotionTimers`
  is **224x196** at a 793-high viewport, i.e. `floor((196+6)/44)` = **4 rows**, the cap; the
  `AuraDot` is live at 22x22 on the Auras tile in the **Epic** mutation's colour. The pass-chip
  sweep is the part worth keeping: a name search over the whole HUD returned **seven `Chip`
  frames**, which reads as "the tray is still there" — and every one of them is an aura rarity chip
  inside the hidden `AurasPanel`. *A name match is not a location.* Walk the parent chain before
  believing either answer.

  **16.2 is half closed and the other half needs two clients.** Measured: **12 visible tiles in 4
  columns**, both sides two wide; **no Trade tile** (the only trade-named objects left are the
  modal, the picker, the invite prompt and the card's own button); `PlayerCard` present at exactly
  250x184. Its own check — the card opening over a clicked avatar, clamped, with the distance line
  repainting — cannot be run from one client, because `showCard` is a local closure reached only by
  a real click on a real other player. It belongs with 5.4 and 8.6.

  Final sweep: **50 of 50 identical**, no strays left in `workspace`.

  ⚠️ **The six meshes exist only in the unsaved Studio session.** They are instances, not files, so
  nothing in `src/` or in a commit carries them. The place has to be saved and republished or they
  are gone with the next Studio restart — filed on the owner checklist beside 15.10, which wants the
  same publish.

- **2026-08-16 (thirty-eighth session)** — **PHASE 16 OPENED, AND IT WAS ALREADY RUNNING IN THE
  PLACE.** Asked to improve the game and to start from the panels. The session-start sweep found
  **six of the fifty live scripts divergent** and `tools/provenance.py` answered **NO MATCH** on all
  six — Studio held work in no commit, including a `MainUI` 16 KB larger than `src/` whose comments
  cite rows *16.1* and *16.2* that exist nowhere in this file. Pulled out whole over the HTTP bridge
  and committed first (`73e65a8`), then written up as 16.1 and 16.2 and left `[~]`, because nobody
  has run their checks.

  **One structural change from 15.28 is behind everything that follows, and it is worth stating
  once: `applyShell` no longer paints the frame it is given.** The fill, its gradient and the bottom
  lip live in `InnerBody` and `ShadowBody` children and the host is left fully transparent. Every
  helper that repaints or measures *the host* therefore reads and writes a surface nothing draws —
  silently, with every property still reading back exactly what was set. Three separate faults this
  session were that one sentence:

  **16.3 — `UITheme.SetColor` has been a no-op on every modern surface**, and it is the API roughly
  25 state recolours go through: the Robux tabs, the mute toggle, the Auras *Wear* buttons, the
  shard button, the potion rows, every Locked/Green claim button, `SplicerUI`'s roll button,
  `ZoneTransition`'s name card. Measured on the running HUD — **631 shells on screen**, and a
  `SetColor` to magenta moved the host's invisible colour while the drawn fill, its gradient and the
  lip stayed put. `MainUI` already knew and had patched around it locally (15.28's `setButtonColor`);
  what that never reached was every *direct* call. Fixed at the root with a public
  `UITheme.FaceOf`, and proved with a control: a plain frame with no `InnerBody` still repaints.

  **16.4 — 15.2's cyan panel rim is gone from the entire game, and both halves of the test broke at
  once.** `registerPanel` looks for `panel:FindFirstChildOfClass("UIStroke")` (now **nil** for every
  panel — the stroke is on `InnerBody`) and then applies a near-white test to
  `panel.BackgroundColor3`, which is never written any more and reads back **Roblox's default frame
  grey**. Measured before: **19 panels, 19 missing host strokes, 0 rims**. After: 19 of 19. Asked of
  `UITheme.FaceOf` and of the `BaseColor` attribute now, which is the reading that survives wherever
  the fill lives next.

  **16.6 — both Inventory tabs are blank pills, and the first diagnosis was wrong in a way worth
  keeping.** A contrast sweep found them at **1.13:1** against their own fill and named the missing
  outline — true (**4 of 942** visible runs in the HUD had no `UIStroke`, and they were these four)
  and not the fault. The halo shipped and the next capture showed two blank pills exactly as before.
  A `TextButton` draws its own text at its **own** ZIndex and `styleCard` puts the fill one rung
  above it, so the shell had been painted over the caption since 15.28. The caption is a `Label`
  child at `Z.Content` now. **A colour probe cannot see occlusion.** The corrected sweep is worth
  keeping in both forms: the naive test (text vs backing) flagged **736 of 942** runs, because in
  this HUD the outline *is* the contrast.

  **16.7 and 16.8 are dead space, not the shell bug.** The potion shelf was authored at a fixed 204
  inside a 528 panel and stopped 178 px short of its own bottom rim — canvas 810 against a 204
  window, three of twelve rows visible in a panel with room for six. And the **Robux shop was
  showing a fifth of itself**: 448x500 gives the grid two 192 cells and 1.9 rows, so twenty products
  sat under a first screen that looks complete. 640x640 is arithmetic rather than taste — three
  cells plus their gaps is 596 in 608 of width, **12 px of slack** rather than the 0 an exact 628
  would leave, because a grid that wraps on a rounding drops to two columns and nothing reports it.
  Canvas 1,726 → 1,150. Nothing inside either panel had to move: the scrolls are sized off the panel
  and `registerPanel` fits the authored size to the viewport.

  **16.5 is the only one that is not that bug** — the Welcome Back card is authored for two rows and
  usually has one, so a third of it was empty shell (measured 580x294 around a single 88px row). It
  is sized to what is actually waiting now, **580x194** on a real join. Shrinking after
  `registerPanel` is safe in a way growing would not be: the UIScale was fitted for the authored
  size, so anything smaller still fits every viewport it fitted before.

- **2026-08-16 (thirty-seventh session)** - **THE JOURNAL, MEASURED RATHER THAN ADMIRED - and three of
  the four findings were in code whose own comments described a game that has moved on.** Asked for
  "radi journal i doradi charactere" while a second Claude worked 15.33 on the same file. Nothing here
  is a rewrite; every row is a number that turned out to be wrong.

  **The characters were being drawn a third too small, everywhere, for a geometric reason.**
  `CharacterPreview.Frame` fitted the bounding SPHERE, so depth was charged as if it were height -
  measured across all 100 entries, every figure was 18%-59% too small for its own disc (mean 37%),
  worst on the quadrupeds. Fitting the actual silhouette (height, and the yaw-rotated footprint
  through the viewport's aspect) is 15.34, and the before/after captures are the proof.

  **"Doradi charactere" turned out to mean something different from what the code says it means.**
  The costume builders in `StageCostume` - twenty hand-written stages - are no longer what a player
  sees: **all 100 ladder characters have a generated mesh now**, six segments and 6.8 parts, and
  `CharacterPreview.Build` skips the whole primitive path for them. So the Journal's 26-part cap
  guards nothing (59.2 ms capped vs 56.8 ms uncapped for a full window) and its comment's "240-270
  parts" is off by a factor of ten. Written down as 15.35, with the one genuine bug it was hiding:
  the cull spares `StageEyePupil`, **a name nothing creates** - the part is `StagePupil` - so every
  stage on that path came out blank-eyed, `Pupil 0/2`.

  **The panel opened two discs at a time (15.36).** `syncPreviews` had a per-pass budget of two and
  no engine to run passes: opening the Journal was ONE pass, and the other sixteen discs arrived one
  income tick apart. A rig costs **3.15 ms**, so a whole window is ~57 ms in one go - a real reason
  for a budget, and no reason at all to stop at two. It fills over frames now: a jump to the far end
  of the list went 0/11 -> 6/11 in one frame and settled complete at 61 ms.

  **And the filled disc came back a third time on its own (15.37).** Not by anyone reinstating it:
  15.28 moved `styleCard`'s fill into an `InnerBody` child, so 15.27's three ring lines now clear
  surfaces nobody sees, while the comment above them still claims the ring was restored. Photographed
  both ways in one frame - fill cleared on two rows, left on the third - and the owner picked neither
  the ring nor the status quo: **keep the filled disc, pale the fill, keep the rim at full strength.**
  The pale has to be handed to `setButtonColor` as well, because 15.28 also made that call real and it
  repaints the disc on every DataUpdate.

  **Two notes for whoever holds 15.33.** The Journal edits went into `src/` and the place **as the
  same text**, so a line-by-line merge sees no conflict on them. And the fork is wider than MainUI's
  line count suggests: the place's left sidebar has **no Trade tile at all** (`columnTile("L", 4)` is
  Auras there, Trade in `src/`), so the place builds 40 HUD children where `src/` builds 41 - that
  difference is the fork, not a regression, and `screenGui.TradeButton` resolves to nil on that side.

- **2026-08-16** — **Phase 15 is closed.** 15.32's last owed check landed: `TradeUpdate` fired from the
  server with a made-up session opened the modal, drew 1 pet against 2 by name, and a `cancelled`
  payload closed it and cleared the state. Nothing is left open in this phase but the owner's
  dashboard rows elsewhere in the file. The genuine two-client trade run is 15.5's and still needs a
  second client Studio cannot provide.

- **2026-08-16** — **Phase 15's whole `[~]` tail is closed: 15.21, 15.22, 15.23, 15.24, 15.25, 15.29.**
  Every one of them was coded and pushed already and owed nothing but a live check, and one playtest
  paid all six. Combat: a Critter died from 42.3 studs and a boss from 68.9 with the character never
  moving. Auto Collect: 5.82T/sec at Lv 66 became 5.86T/sec at 67, against a server stamp that keeps
  climbing to level 100. The Robux shop has no clock and no star. The worn aura reads as a Mythic-red
  dot on the Auras tile against a panel that agrees with it. Two findings came out of the run rather
  than the code: `CombatClient`'s boss-size comment was **wrong** (a boss is 160-180 studs across,
  not 75-121, and what makes 70 the right reach is the 64-stud collision hull, now written down),
  and **`script_grep` cannot see `ServerScriptService` while Studio is in Play** — a silent false
  negative, now in the traps list.

- **2026-08-16** — **15.33 closed: `src/` and the place are one file again.** The fork was resolved in
  ONE direction — Studio won all four divergent regions, because every one of them was newer work
  (15.28's `styleCard`/`ShadowBody` rewrite, 16.1's one-line strip, the Season rail, 15.27's Splicer
  string). Neither `src/`-only item was a loss: 15.24's mutation card is what 16.1 deliberately
  replaced with the `AuraDot`, and 15.32's listeners had already been hand-ported into the place.
  `src/` is now 10,296 lines and byte-identical to Studio's `MainUI`. **The technique is the reusable
  part:** dump a whole script out of Studio by `PostAsync`-ing its `Source` in 60 KB chunks at a
  local `http.server` writing to disk, then diff locally with git — 474 KB moved in one call, no
  agent context spent, and a re-dump after editing proves the other agent did not touch the file
  mid-merge. Verified live: 41 of 41 HUD children, console clean.

- **2026-08-16 (thirty-sixth session)** — **TWO AGENTS FIXING THE SAME ROW AT THE SAME TIME, AND
  THE SWEEP THAT CAUGHT IT BEFORE EITHER GOT OVERWRITTEN.** Opened on "nastavi sa fazama" with
  15.29/15.30/15.31 as the only code-shaped rows left open. All three were written in `src/` first;
  then the provenance sweep that has to run before any push came back **NO MATCH on four of eight
  files** — and the Studio-only content in three of them was **Gemini, mid-flight on 15.31**: the
  rarity ring already SmoothPlastic, the PointLight and sparkle already deleted, stage 20 already
  off Neon, the aura already `scale^0.6`. Nothing was reverted. `src/` was walked BACK onto those
  choices and only the gaps were added — the Neon crown, the `AURA_SCALE_EXP` constant, the rate cut
  — so the repo now records Gemini's pass rather than replacing it.

  **15.30 was the one place the two answers could not both stand,** and it is the owner's call, not
  an agent's: Gemini had raised the ceiling with the body (`cap * sizeMult`, ~580 studs/s at max
  stage — the speed the cap exists to prevent); the owner, asked, chose the aura paying a
  **percentage of the cap**. `speedBonus` → `speedPct` across GameConfig, EvolutionVisuals,
  SplicerService, SplicerUI and MainUI, renamed rather than redefined so a stale reader gets nil and
  fails loudly. Measured on the owner's own stage-20 save: **260.00 with nothing worn, 265.20
  Common, 280.80 Mythic, 291.20 Godly** — every rung moves the number where before all seven read
  260. 15.30 `[x]`, 15.31 `[x]`.

  **The real find is 15.33.** `MainUI` in Studio is 10,317 lines to `src/`'s 10,203 and the two have
  been diverging since line ~150: Studio carries a `styleCard`/`ShadowBody` rewrite and a **`16.1`**
  card pass nobody committed, `src/` carries 15.24's mutation boost card and 15.32's un-raced
  listeners, which had **never reached the place** — a fix committed on 2026-08-15 that the running
  game did not have. It was ported by hand here and two of its three listeners then regression-checked
  live (the chest panel opened, `ProbeFriend wants to trade with you` landed), so 15.32 keeps `[~]`
  only for the two-client `TradeUpdate` leg. 15.29 keeps `[~]` for the opposite reason: the formatter
  is in and correct, but the card it was written to stop contradicting **does not exist in the Studio
  lineage**, so its own check cannot be photographed.

  **Method worth keeping:** `tools/hash_sweep.py` cannot reach an attached Studio (it spawns a second
  proxy — "Unable to reach Roblox Studio"). What worked: compute per-50-line rolling hashes in Luau
  via `execute_luau`, compare against `git show HEAD:<file>` locally, and read back only the blocks
  that differ. Four files, ~40 lines of output, one round trip — instead of pulling 10,000 lines
  through the session.

- **2026-08-15 (thirty-third session)** — **THE STUDIO THAT WAS TEN FILES BEHIND, AND WHAT THAT
  MEANT ABOUT THE COMBAT REVERT.** A Studio was finally attached, so the thirty-second session's
  one blocker lifted and 15.27/15.28 could be pushed and photographed. **The push was not three
  files, it was ten.** `src/` and the place were compared file by file on the same rolling hash —
  50 scripts, **40 already byte-identical, 10 behind, 0 missing** — and before writing a single one
  of them each Studio-side copy was traced to the **commit it came from**, which is the check that
  separates "Studio is old" from "Studio holds work nobody committed". All ten matched a real
  commit; nothing was lost. MainUI alone was **five commits** behind.

  **The finding is in the provenance list, not in the push.** `BossService`, `CreatureService` and
  `CombatClient` were all sitting at **`4df59c7`** — the "tighten combat to true melee" pass that
  **15.21 reverted last session as a regression**. The place had been carrying the reverted reaches
  the whole time. Anything measured live in that Studio before this push was measured against code
  the repo had already thrown away, and the two 15.2x rows that were closed "live" on it are worth
  reading in that light. Also stale: `UITheme` predated 15.15, so `UITheme.IsDarkInk` did not exist
  and the freshly pushed MainUI **threw at line 135 and drew only 5 of its 41 children** — a HUD
  that looked half-built for a reason that had nothing to do with the new code. This is
  [[evolution-lab-local-place-cannot-run]]'s "sweep and push from `src/` first" arriving as a bill.

  **15.28 is `[x]`** — both deletions verified on a populated Journal (2,306 descendants, zero
  rarity-shaped instances, no ribbon on the detail well) and photographed. **15.27 stays `[~]`, and
  the blocker is now one clause instead of the whole row:** the panel, the seven rows, the colours,
  the locked lines and the Wear button are all proved live, including that **Wear on Epic put one
  `EquipMutation` on the wire and the dimmed `✓ Wearing` put none**. What cannot be shown here is
  the row's last clause — particles, walk speed, boost card — because `GameId 0` means
  `HandleEquipMutation` never runs. That needs **BETA V0.2** opened, and it is the only thing owed.

  **Method note worth keeping:** the whole capture ran on the dead server, on a synthetic
  `DataUpdate` loop plus a fresh `MainUI` clone. The one failure was self-inflicted and instructive
  — a payload with `StageIndex = 42` against a 20-entry `GameConfig.Stages` made `refreshUI` throw
  on every tick, so the HUD read `0 DNA / Cell` while the panel under test drew perfectly. A probe
  that half-works reports a defect in the wrong file.

- **2026-08-15 (thirty-second session)** — **THE PHANTOM TEST FILES, THE FAUCET, AND AN AURAS
  PANEL THAT ARRIVED WITH A JOURNAL REGRESSION ATTACHED.** Two owner items, and the working tree
  turned out to be holding a third.

  **15.26 (1): the fabricated evidence is dealt with, and one detail of the finding was wrong in a
  way that made it smaller.** The two citations sit under **5.5** and **8.6**, not 5.4 and 5.5 —
  and 8.6 was closed on a real two-client run three commits later, so `test_trading.py` was propping
  up nothing by the time anyone looked. That clause is struck. 5.5's is replaced with what is
  actually established (a read, labelled as a read) plus the thing that makes a Studio check on it
  meaningless whoever runs it: **`RunService:IsStudio()` short-circuits both group checks to
  `true`**, so no Studio session has ever tested group membership. 5.4's cell is rewritten too — its
  receiving half is real and measured, its `PublishAsync` → `SubscribeAsync` half needs two servers
  and Studio has one. `HANDOFF-LOG.md` gets a **dated correction entry**, not an edit; it is
  append-only and a redaction that erases the claim also erases the lesson.

  **15.26 (2): the Like/Favourite faucet is safe.** `data.ClaimedLikeReward = true` is written
  before the first `+=` with nothing yielding in between, both flags default to `false` and
  **nothing anywhere clears them** — not a rebirth, not a migration. One-shot per save, forever;
  worst case **💎 30 + one potion + 🌟 2 per account, ever**. The client's word is still the trigger
  and always will be, because Roblox exposes no API for either — that is now written in the row
  instead of being folded knowledge.

  **15.27: the Auras panel — and six defects in the attempt that was already in the working tree.**
  `data.SplicerFound` has counted every Splicer roll since Phase 12 and **nothing in the game has
  ever read it**. There is a panel now: seven rows in rank order, the roll count on a chip painted
  the exact colour of the particles on your body, the multiplier and speed off the config row the
  server pays from, and a **Wear** button that makes any aura you own the one you wear. The worst of
  what had to be undone first was not in the new code at all: the attempt had **restyled the
  Journal**, deleting 12.6's rarity pip, the detail rarity ribbon and the ring-not-puck fix that
  exists because of her own *"remove the circles, you cannot see them"* report. Reverted whole,
  comments included. **The new code's own fatal one is worth keeping:** its equip handler set the
  save field and called `ApplyMutationAura`, but `WornMutation` reads the **attribute** first and
  the join path stamps it — so the aura and the walk speed would both have stayed on the old
  mutation for the rest of the session while the panel said the new one was worn. It runs
  `HandleRoll`'s three lines now. Plus: `registerPanel` before `styleCard` (no cyan rim), a block
  opening `(function()` under `end)()`, buttons driven with `.Text` instead of `UITheme.SetText`,
  and the whole file rewritten **CRLF** — a 20,124-line diff that would have failed every future
  hash sweep.

  **15.28: and then she asked for the rarity out of the Journal on its own merits** — *"every
  character has to be collected anyway"* — which is correct and dates 12.6's argument precisely.
  A pip saying "there is a Legendary you have not found" is a useful sentence about a game where
  characters **drop**; since 9.5 made every skin its own evolve they unlock in **strict rank
  order**, so the next one you get is the next rung whatever the pip says. Both badges deleted.
  `entry.rarity` stays — `skinMarks` reads it, so the fact now appears as the ornament ON a
  Legendary rather than as a letter in its corner. Worth separating from 15.27: the badges were
  reverted first and deleted second, and only the second one is a decision.

  **Nothing was pushed or photographed: the Studio MCP proxy answers but no Studio is attached to
  it.** 15.27 and 15.28 are `[~]` for exactly that reason and for no other. `tools/studio_mcp.py`
  is new and is what proves which half is down — it speaks to the proxy directly over stdio, so
  `tools` answering while `exec` reports "Unable to reach Roblox Studio" separates a dead proxy
  (the `mcp.bat` stale-version failure) from a Studio with no plugin attached, in one command.

- **2026-08-15 (thirty-first session)** — **FIVE OWNER REPORTS IN ONE SITTING, AND THE FIRST
  ONE WAS A GEMINI REGRESSION.** *"Auto attack is too close now, I have to stand in the core of the
  mob to kill it"* is commit `4df59c7`, a "tighten combat to true melee (<10m)" pass that cut every
  reach in the game by roughly three: `AUTO_REACH` 60/70 → 22/32, `clickReach` `size*0.6+16` →
  `size*0.4+10`, the server's auto floor 60 → 22, boss `strikeReach` 70/90 → 30/34. **The number
  it never measured is the player's own body.** A max-stage character's bounding box is
  **30.7 x 42.9 x 27.1**, i.e. 15.4 studs from the HumanoidRootPart every one of those reaches is
  measured from, and a Critter is 22 wide — so at 22 the two bodies had to overlap by 4 studs before
  a blow was legal. Bosses were worse than tight, they were unreachable: 75–121 studs across against
  a 32-stud reach. All six numbers are restored, and so is every comment block that commit deleted
  — it had left the surrounding prose describing 60 while the code ran 22, which is the exact shape
  of defect this phase exists to catch (**15.21**).

  The audit that came with it found more of the same: **`HANDOFF-LOG.md` cites `test_trading.py` and
  `test_group_rewards.py` as evidence for 5.4 and 5.5 and neither file has ever existed** in the repo
  or in git history, and every one of the seven Gemini entries labels `luastruct.py` + `luanames.py`
  — static lint over source text — as "Evidence (live, in Studio)". Filed as **15.26** with the
  second finding, an ungated Like/Favourite diamond faucet.

  **The other four reports, all fixed the same session.** **15.22**: Auto Collect *"has no point"*
  because it genuinely had none — its rate hit the 1.2 ceiling at level **30** while the shop sells
  to **100** at `1.38^level`, and the owner's save sits at **52**. The cap is continued rather than
  removed (0.012 a level past 30, ending at 2.04 clicks a second), and all four DNA tiles now print
  what the level you own is doing, Auto Collect off the server's own per-second figure. **15.23**: the
  Robux shop's *"Today's pick resets in 10h 51m"* counted down to nothing — every tile is permanent
  at a fixed price and the "pick" was a star with no discount attached; clock, star and `pickIndex`
  deleted. **15.24**: the Splicer mutation was worn invisibly, so it is now a card on the boost strip
  reading its name, `x1.50 DNA` and `+5 speed` out of the same config row the server pays from.
  **15.25**: the Market tile is deleted at the owner's request, and the comment that said "do not
  delete that tile" is rewritten to record what it costs — fusing now needs the Volcano counter.

  All five files pushed and verified byte-identical, and a **full sweep found all 56 mirrored scripts
  identical between `src/` and Studio**. `luastruct`, `luascope` clean; `luanames` matches baseline
  exactly (same three forward references, shifted lines). The four new rows are `[~]`, not `[x]`:
  what is owed is one fight at range, one Upgrades capture, one shop capture and one strip capture.

- **2026-08-15 (thirtieth session, part two)** — **THE TWO-CLIENT RUN HAPPENED, AND TRADING IS
  CLOSED.** Kristina started `Test → Clients and Servers → 2 players`, which put two real `Player`
  objects in the server — Player1 (`-1`) and Player2 (`-2`) — and the whole feature was driven from
  the two clients by **real mouse clicks and one real key press**, with no service called directly.

  **What closed: 8.1, 8.5, 8.6, 15.5 and 15.11.** Trade tile → the picker listing `👤 Player2` →
  Ask → **`Player1 wants to trade with you`** on the other screen → Accept → **both trade windows
  open at once**, each naming the other. Player1 clicked Sparky in the inventory picker and it drew
  in **Player2's partner grid**; Pebble came back the other way; both grids showed both pets on both
  screens. Confirming on one side put **`✅ Ready!`** on the other while its own still read
  `⏳ Deciding...`; confirming on both ran `countdown` and then `completed`, with `🤝 Trade complete!`
  on both clients and both windows closing themselves. **The commit is proven by id** — Sparky
  `b436693d-…` and Pebble `2d9de2c6-…` each ended in the other player's save. Then 8.5's own rule,
  the same way: with Player1 confirmed, Player2 **removing** their pet reset **both** sides to
  `⏳ Deciding...`, put the button back to `Confirm Trade`, and redrew the partner grid to 0.

  **Getting there needed no save edits.** Both test players joined empty, so both redeemed the real
  `LAUNCH` code (+1500 DNA) through the real remote, walked to the Forest pet shop, opened the egg
  panel with a real **E** on the podium prompt — which opened on **Better**, the podium's own
  `EggKey`, exactly as 11.18 intended — clicked **Basic**, and hatched one pet each.

  **The run found three defects, and one of them is in 15.11's own code.** **15.19**: the picker's
  distance label never updated, because it identified rows with `Name:match("^Player_(%d+)$")` and
  **Studio's test players have negative UserIds** — `%d+` cannot match `-2`. It would have worked in
  production and failed in every test anyone could run. **15.18**: seven refusals in `Request` and
  `Accept` returned a reason to a caller that discards it, so a stale session made every press of
  Ask do *nothing at all* — measured, with observers on both remotes recording zero events. That
  cost a run to diagnose from the outside, which is what a player would have to do. **15.20**: the
  FirstJoin tutorial banner draws over the trade window's column headers and the picker's header,
  photographed on both clients; filed rather than rushed, because the fix is a ZIndex band decision.

  **15.20 fixed the same session.** `DisplayOrder` beats `ZIndex` **across** ScreenGuis and does it
  absolutely: `FirstJoinGuide` is at **110**, `EvolutionLabUI` sets none and is at **0**, so no
  ZIndex a panel could pick would ever have cleared that banner — and the 110 is not the mistake,
  since the guide's arrow points at the EVOLVE button and has to be over the HUD it is talking
  about. A panel is a **modal** surface, so the guide now stands down while one is open: the whole
  ScreenGui is disabled by one watcher, rather than each piece hidden, so none of the visibility
  logic below it — including the two one-shot timed banners that set `Visible` once — has to learn
  about panels. `registerPanel` stamps `HudPanel` on every panel so a second script can ask the
  question without this register-starved file exporting anything, the same trick `columnTile`
  already uses. Measured in order with the banner FORCED visible: no panel → `Enabled = true`;
  banner up, still no panel → **true**; `TradeModal` open → **false**; closed again → **true**,
  with `banner.Visible` staying `true` the whole way — a yield, not a mute. All 18 panels stamped.
  **Owed: the confirming capture.** `screen_capture` began timing out on this Studio right after
  the multi-client session and did not recover across four attempts; the fix is proven by
  measurement and the *before* is already photographed on both clients.

  Also confirmed in passing: `ShopPanel = "eggs"` really is set by `WireKiosks` at server start (the
  Edit-mode sweep that showed 60 unwired egg podiums was reading the pre-server world), and the
  invite prompt's 15-second self-hide is short enough that an ordinary MCP round trip misses it —
  Ask and Accept have to be fired back to back.

- **2026-08-15 (thirtieth session)** — **The two-client check could not be run, because there was
  no way to start a trade.** The session opened on the standing checks and all of them were clean:
  `luascope.py` and `luastruct.py` over every mirrored script, a full hash sweep finding all **56**
  byte-identical between `src/` and Studio's Edit datamodel, and 15.10's backdoor deletion still
  standing in the unsaved session (**58** `LuaSourceContainer`s, **0** matches for `LightConfig` /
  `Pose` / `NumberPose`). Studio was in Edit, so the two-player test had not been started — and
  preparing for it is what found **15.11**.

  **The finding.** `grep -rn TradeRequest src/` returns exactly one line and it is the server's.
  `TradeService.Init` has bound that remote to `TradeService.Request` since 8.6, the invite prompt
  has always been able to answer one, and the modal draws whatever a session pushes — but no button
  in this game ever fired it, so no trade could be opened and therefore no invite could ever arrive
  either. **15.5's own check was unrunnable as written**: two clients would have found no door.
  That is the third defect in this one feature and the third of the same family — a name out of
  scope (15.5), a remote that did not exist when the client looked (15.9), a remote nothing ever
  fires (15.11) — and **none of the three is visible to `luascope.py`, `luastruct.py` or a Luau
  compile**, because every name in all three is in scope and correct.

  **The fix**: a Trade tile at L4 and a player picker that lists everyone else in the server, labels
  each one *in range* or *walk closer*, and fires `TradeRequest` from its Ask button. Two decisions
  in it are worth knowing before the next tile is added — the tile is created at the **top** of
  `MainUI` and held by **no local** (the responsive column pass collects its tiles once by walking
  `screenGui`, so a tile created below it is never laid out at all; and the file is at Luau's
  200-register ceiling, so the trade block finds it back as `screenGui.TradeButton`), and
  `PROXIMITY_STUDS` moved into **`GameConfig.TradeProximityStuds`** the moment a second reader
  appeared — the same move `MaxOwnedPets` made, and for the same reason.

  **What that bought, live.** The tile is laid out by the responsive pass on the pass's own
  arithmetic (82px at y=445 = `121 + 3 × 108`), a **real mouse click** opens the picker, and the
  picker is the same panel as every other panel rather than a lookalike — 6.0px cyan rim and a
  gradient keypoint-identical to `GroupRewardsPanel` and `TradeModal`. And **the direction 15.5
  listed as unproven is now proven**: real `FireServer` calls on `TradeRequest` reach the live
  server and are refused with the service's own reasons leaving `sessions 0`, and a **real click on
  the invite prompt's Accept button** arrives as `OGLightninggXD accepted probe-no-such-session`.
  (The prompt hides itself after 15 s — that is why the first clicks at it reached nothing.)

  **Both rows now close on one two-client run**, and nothing short of a second `Player` reaches what
  is left: `execute_luau`'s `require` hands back a fresh `TradeService` with its own `sessions`
  table, so a fixture built there is invisible to the live remotes a human's clicks travel through.

  **Then the session wrote the check that would have found it, and the check found another one.**
  15.11 was the third defect of its family in this phase and all three had been found by eye, so
  `tools/luaremotes.py` (15.13) now pairs every remote's senders against its listeners across the
  whole tree — the first lint here that reads two files at once. It reproduces 15.11 exactly (the
  finding is printed against the previous commit and gone against the fix), and on its first clean
  run it printed a second name: **`CollectClick`** (15.12).

  **`CollectClick` read identically to `TradeRequest` and meant the opposite.** A server handler
  that credits DNA, hardened years-correctly against the exact spam attack its own comment names —
  and with no caller anywhere in the game, because DNA per swing moved to `CreatureService` and the
  HUD's `+` pills open the Robux shop. A paying handler with no legitimate caller is an exploit-only
  faucet: the only software that can reach it is software written to cheat, and the rate cap then
  sets the cheater's income rather than denying it. **Measured on both sides**, three 4-second arms
  each, all bracketed inside one client call: before the fix, ~1,600 `FireServer` calls paid
  **29.33x** the passive income of the same four seconds against flat controls either side; after,
  the three arms are **identical to four significant figures** and the calls paid nothing.

  **And removing that faucet exposed a third thing, which is the one a player would actually
  notice** (15.14). Deleting `HandleClick` left `MainUI`'s `kind == "crit"` toast with no sender at
  all — so it was checked, and it turned out it had never had one: `CreatureService` is the only
  thing that pays DNA now, and it called `GetClickAmount` for the number and **threw away the
  second return**. The crit is **x5**, at a chance that Egg Luck raises to a cap of **75%**, and the
  game has never once said it happened. It now rides the kill's existing `CombatFx` packet as `cr`
  and is drawn as the DNA pop that was already there, in gold — no toast, because a fact about one
  creature belongs where it happened. **Measured on 87 real kills** through the real `AutoAttack`:
  crit against non-crit of the same tier is **5.0000** on all three tiers that produced both, and
  the crit rate is **64 of 87 (73.6%)** against the 75 cap. The drawn label was measured rather than
  photographed and five attempts say why: the pop lives about a second, and a max-stage character
  fills any camera close enough to read a 76px billboard.

  **Then the same "both sides at once" question was asked of everything else that pairs across a
  boundary, and all of it came back clean** — recorded so nobody spends a session re-deriving it.
  `Notify` **kinds**: 26 sent, and the set sent and the set the client branches on are *identical*,
  0 either way. **`hudRefs`**: every function read is assigned (the two that looked missing are
  declared `function hudRefs.X`, not `hudRefs.X =`). **Attributes**: four are read and never set —
  `MysteryCost` is set through a table (`addPrompt(..., { MysteryCost = cost })`), and `FaceFlip`,
  `BulkPrompt` and `IsLip` are each documented *in their own file* as deliberately inert. **Save
  fields**: no client read names a field the server never writes. **Name-keyed config tables**, the
  class that produced 11.30 *and* 11.31: all four zone-keyed tables cover all 20 zones exactly, the
  four pet-tier tables agree with each other, and every rarity a pet uses has a row. **And every
  `ProximityPrompt` in the built world is wired** — 81 of them, checked live rather than by reading:
  60 eggs, 7 mystery dispensers, 4 fusion, 4 mastery, 4 robux, 1 splicer, 1 chest and 4 rebirth
  plinths, the last wired by a direct `Triggered:Connect` rather than by an attribute. Two things
  that audit taught: `ShopPanel = "eggs"` is set by `PetService.WireKiosks` **at server start**, so
  in the Edit world every egg podium looks unwired and is not; and the client sees only what has
  streamed in, so the sweep has to run on the server for coverage and on the client to prove the
  attributes replicate. Both were run.

  **With every pairing clean, the session turned to what a probe calls healthy: a sweep of all 18
  panels, 1,924 labels, three checks** — text that does not fit its box, dark ink inside a stroke of
  its own darkness, and bright ink on a bright surface with no stroke. It came back with **11
  findings and three distinct causes**, all now fixed and all invisible to every tool in this repo.

  **15.15 — 15.1's fix went into one of the two constructors that draw a halo.** `themeLabel`
  learned the rule; `UITheme.Label`, the shared one, never did. The Group & Community panel is what
  that cost: three card titles at ink **0.14** inside a 4px stroke at **0.09**, photographed and
  plainly unreadable. The threshold is now `UITheme.IsDarkInk` and both constructors read it. A
  third instance turned up outside the HUD entirely — `EventService` paints the event board's clock
  in `Color.Outline` and then outlines it.

  **15.16 — `TextScaled = true` turns `TextWrapped` back on**, measured on a live label going
  false → true the instant it is assigned. The potion rows carry a ten-line comment explaining why
  they must never stack two lines, set the flag, and then call a helper that scales: **the fix was
  written, has read correct ever since, and was never once in effect.** `UITheme.Label`'s `wrapped`
  option was inert for the same reason.

  **15.17 — the one `TextFits` reported as healthy, correctly.** A button reserves its icon's width
  on both sides of the label from the button's HEIGHT, so the Group cards' 115 × 42 button kept
  **27px** for its text and "Claim" rendered as "Clai" over "m". Two 14px lines do fit a 30px box;
  what is wrong is that there are two of them. Only the capture showed it.

  **The sweep was then widened twice more and both came back clean, which is worth recording so it
  is not repeated.** The world's own signage — every `BillboardGui` and `SurfaceGui` in `Workspace`,
  **2,018** of them, swept on the SERVER because a client only holds what streamed in — returns 0 on
  both colour checks, and the event board's countdown, which was one of 15.15's three instances,
  now measures **stroke 0.0** on the surface it was written for and is photographed reading
  `1d 12h` in clean dark type. And the HUD outside the panels — the tile columns, the currency
  stack, the stage card, the tickers — returns 0 as well, after one false positive that is itself
  worth knowing: **a `UITheme.Button` keeps its own `Text` and hides it at `TextTransparency = 1`,
  drawing through a `Label` child instead**, so a sweep that does not filter on transparency reports
  that invisible string as dark ink in a dark halo. The final pass, panels and HUD together with
  that guard, is **1,672 visible labels, 0 findings**.

  Cost of the tool's own accuracy, recorded because each one is a fact about this codebase: the
  `Remotes` **folder** is fetched by the same `WaitForChild` call the remotes are; a find-or-create
  block binds its local to the **class name** `RemoteEvent`; and a binding is a **position, not a
  name** — `MainUI` binds a local called `remote` to eleven different remotes, and keeping the first
  made six live features look unreachable on the first run.

- **2026-08-15 (twenty-ninth session)** — **No code-only row was left to take, so the session spent
  itself narrowing the one row that is not owner-blocked, and 15.5 is now one `Player` object short
  of closing.** Opened with the standing checks and all three came back clean: `luascope.py` and
  `luastruct.py` run clean over every mirrored script (15.8's `VILLAGE_CREAM` finding is gone with
  the fix), and a full hash sweep found **all 56 mirrored scripts byte-identical** between `src/` and
  Studio's Edit datamodel. The Edit session still holds 15.10's deletion — 58 `LuaSourceContainer`s,
  **0** matches for `LightConfig` / `Pose` / `NumberPose` — so that work has not been lost, but it is
  still unsaved and still owed a republish. The two scripts in Studio with no `src/` counterpart were
  identified rather than assumed: `ServerStorage._RewardFresh` and
  `ServerStorage._PushBackup.MachineService_removed_2026_08_11`, both inert `ModuleScript`s that
  nothing requires.

  **What 15.5 gained.** The real `Request → Accept → SetOffer → pushSession → resolveOfferPets`
  chain was run against the shipped file with the real player on one side, and every push was a real
  `TradeUpdate:FireClient` at the real joined client — where the previous session could only
  synthesise the payload. Both offer grids drew from the real resolver, `Confirm` moved one side to
  "✅ Ready!" on screen, and changing the *other* side's offer cleared both confirmations and redrew
  the grid — 8.5's anti-scam rule measured on a drawn client for the first time. Cancel closed the
  window and released every reservation. **The two rules this is worth remembering for:** `require`
  from `execute_luau` hands back a fresh `PlayerDataService` whose `Cache` is empty even while a real
  player is loaded (measured again, 0 entries), which is what makes a fixture like this isolated from
  the real save — and is also exactly why **`TradeService.Commit` must never be driven this way**,
  since it calls `PlayerDataService.Save(player)` on that fresh instance and would write the doctored
  copy over the owner's live key. Nothing was committed, the trade log stayed at 0, and the real save
  was re-read afterwards at 100 pets with none of the probe's ids in it.

- **2026-08-15 (twenty-eighth session)** — **PHASE 15'S LAST TWO CODE ROWS ARE CLOSED, AND ONE OF
  THEM WAS NOT THE BUG IT WAS FILED AS.** 15.10 and 15.8 are `[x]`. Only 15.5 is still open in the
  phase, and its blocker is two clients rather than code.

  **15.10 was filed as a nil-global typo in a vendored lighting helper and it is a backdoor.**
  `luascope.py` flagged `isPositiveInt(number)` testing a nil `value` at `LightConfig/Type.lua:183`;
  opening the file to fix that one line is what showed the rest. `LightConfig.server.lua` declares a
  local named `FindFirstChild` that does no such thing: `getSignal(Game)` hands back
  `MarketplaceService, GetProductInfo`, so the line reads `GetProductInfo(Pose.Value).Description`;
  `getArchetype` `gsub`es every character of that description to its **byte value** and concatenates
  them into a second asset id; that id is written back into `Pose.Value`; and forty lines down,
  `require(script.EasyConfiguration.Pose.Value)` runs it. **The arming switch is `checkChild`, which
  returns `root['JobId'] ~= ''` — empty string in Studio, a GUID on a live server** — and the guard
  above it (`if not FindFirstChild('Workspace') then return end`) means the payload can only ever run
  in production. Decoded live rather than guessed: `Pose` is a **`NumberPose`** holding
  `90983637061475`, which resolves to "💀 Noli Forsaken Anims Oficial Pack" by `RonyxDeveloper`
  (10805192093) with description `X<E5!'G`; byte-encoding those seven characters gives
  **88606953333971**. That module was **not** fetched.

  **It never ran, and it is not this project's work.** The Script sits in `ServerStorage` (Scripts do
  not execute there) *and* carried `Disabled = true`, and `git log --diff-filter=A` puts all three
  files in commit `5239953`, the very first extraction of the place — so it arrived with a free
  model, before `src/` existed. All three are destroyed in Studio and deleted from `src/`; a sweep of
  the **whole** datamodel (not just the mirrored branches) went 61 `LuaSourceContainer`s → **58**,
  with 0 remaining matches for `LightConfig` / `Pose` / class `NumberPose`, and confirmed there is no
  loose script in `Workspace`, `StarterGui`, `StarterPack` or `Lighting` either — which is where a
  second copy of this pattern would hide. **👤 OWNER: save the place and republish**, or the
  published copy keeps the file. It is inert there for the two reasons above, so this is hygiene, not
  an emergency.

  **The general rule, and it is the third time this file has had to write a version of it: a lint
  finding is a reason to READ the file, not a reason to patch the line.** The one-line fix
  `luascope.py` asked for would have left the backdoor in place and marked the row done.

  **15.8 was three props and is really two, because the crate no longer exists.** The four village
  palette locals moved above `addZoneProps`, `BUILD_VERSION` went 132 → 133 and the world was rebuilt
  — but the crate lid the row names is in the primitive fallback that the `Vill_Crates` mesh branch
  `continue`s past, so `CrateLid` has not been built since the prop meshes landed (count in the
  rebuilt world: **0**). What was actually grey is the banner emblem and the two crossbar knobs, in
  all 21 villages. Measured rather than photographed, because cream against grey is the comparison a
  screenshot is worst at: every `BannerEmblem` now carries its own zone's cream (19 distinct values)
  against the one (163,162,165) they all shared, no `Knob` in the world is at the default grey, and
  the 4,696 parts that *are* at that grey are all `*_geom` mesh shells and billboard anchors that
  were always so.

  **Also found, and it is a fact about how this world is kept: the Edit-mode world was at stamp
  128.** 12.9's seven new zone shops and 12.12's Secret odds row were verified in Play, where
  `ServerMain` rebuilds at boot and then throws the result away — so the saved world had never
  contained them. Harmless (a live server rebuilds too), but a part-count or colour question asked of
  the Edit world is being asked of whatever stamp it was last saved at, not of the current code.

- **2026-08-15 (twenty-seventh session)** — **PHASE 15 CLOSED, EXCEPT THE ROW THAT NEEDS TWO
  PLAYERS — and the captures paid for themselves twice over.** 15.1, 15.2, 15.3, 15.4 and 15.6 are
  now `[x]` on live evidence; 15.5 stays `[~]` because Play Solo is one client; 15.9 and 15.10 are
  new rows.

  **The blocker was never what the last session wrote down.** It concluded the `roblox-studio` MCP
  server "is not registered for Claude Code" and needed a restart. It *was* registered — it was
  dying at startup. `%LOCALAPPDATA%\Roblox\mcp.bat` finds `StudioMCP.exe` through the registry's
  `ContentFolder` and through a hardcoded fallback, and a Studio update had left **both** naming
  `version-d679641ad17741aa`, a folder the updater had already deleted. The batch exited 1, the
  client listed no tools, and **nothing said so anywhere** — while Studio ran fine the whole time
  from `version-43f4e18b18f24d5a`. The batch now scans `Versions` newest-first for one that
  actually contains the exe. Two commands diagnose this without a restart; they are written down in
  `evolution-lab-studio-mcp-stale-version`.

  **Then the order that mattered:** Studio was holding the pre-fix code (its `MainUI` still said
  "Chimpanzini", with no `darkInk` branch), so all three files went over the HTTP bridge and were
  confirmed byte-identical before a single capture was taken. Photographing first would have
  photographed the bug and closed the rows on it.

  **What the captures found that nothing else could.** (1) 15.1 had broken the Journal's detail
  card in the mirror direction: `themeLabel` zeroes a dark label's stroke **Thickness**, and
  `inkOnLight` — the 12.3 helper whose whole job is to switch the outline back on for the five
  labels that are authored dark and repainted bright — only ever moved **Transparency**. "The Final"
  rendered at luminance 0.900 on a 0.953 card with no outline: a ghost rather than a blob, and just
  as unreadable. (2) 15.9: `MainUI` binds `TradeUpdate` with `FindFirstChild` inside an `if`, and
  `TradeService` only creates that remote on the first trade — so on every server the connect was
  skipped silently and **no trade update could ever reach a client**. 15.5's scope fix would have
  shipped into a still-dead feature. Both defects compile, both pass `luastruct`/`luanames`, and
  `luascope` cannot see either.

  **Nothing here touched the save.** 15.4's join-only branch was reached by capturing a real
  `DataUpdate`, copying it on the server with the daily moved back two days, and flooding the copy
  at a freshly-parented `MainUI` clone so the doctored payload is that clone's genuine first
  payload — the flood is the load-bearing part, since `shown` is set by whichever arrives first.

- **2026-08-15 (twenty-sixth session)** — **PHASE 15 OPENED BY A SCREENSHOT: the Daily board's
  text was unreadable, and the five sessions that built it all reported clean.** Kristina
  photographed the panel; every string authored in dark ink was a solid black blob, the little day
  pills wore a 6px cyan border meant for a 700px panel, and day 7 advertised a pet it does not
  grant. **The two static tools were not lying — they cannot see this.** `luastruct.py` counts
  blocks, `luanames.py` says a name exists somewhere in the file and documents that it is not
  scope-aware, and neither reads a colour. Fixed centrally rather than at the call sites, because
  both faults were one decision made in the wrong place: **dark ink drops its stroke inside
  `themeLabel`**, and **the cyan rim moved out of `styleCard` / `applyShell` into `registerPanel`**,
  which is the only function that knows what a panel is.
  - **Two runtime-fatal bugs found by a new instrument.** `tools/luascope.py` walks a scope stack
    and proves a name is visible *where it is read*. First run: `WelcomeBackPanel` writes to a `sub`
    whose declaration the redesign deleted, so the welcome card threw on the first payload of every
    session; and `TradeService.resolveOfferPets` calls `petIndexById` **71 lines above** its `local
    function`, so every `pushSession` threw and no trade offer could ever be drawn. Luau compiles
    both — an undeclared read is a global read — so a compile check cannot see them either.
  - **Two panels had no shell at all.** Trade and Group were Roblox's default grey rectangle with
    square corners, behind correctly-styled contents. The trade window's strings were also authored
    at fixed 11–15px against the *previous* dark HUD, and its rarity borders indexed `UITheme.Color`
    with `"Common"` / `"Legendary"` — keys it has never held, so every tile came out the same grey.
  - **Nothing here is `[x]`.** The `roblox-studio` MCP server was configured for Gemini only, so
    this session could not run or photograph the game; `.mcp.json` now declares it at the repo root
    for both agents and takes effect on the next Claude Code start. Every 15.x row's check is one
    capture, and they are written down per row.

- **2026-08-15 (twenty-fifth session)** — **1:1 Pet Simulator 99 UI Replication & Uniform Aesthetic Standard.**
  - **White Shell + Cyan Border:** Applied pure white modal background (`Color3.fromRGB(255, 255, 255)`) with vibrant 6px cyan border (`Color3.fromRGB(0, 180, 255)`) across all main panels in `UITheme.lua` and `MainUI.client.lua`.
  - **Pet Simulator 99 Daily Rewards:** Replicated exact reference layout in `rewardPanel` with sunny-gold cards (Days 1–6), top `"Day X"` capsule tabs, giant full-height lime-gold Day 7 card with `"OP!"` star badge, 3D mascot preview, and centered `"Join Tomorrow For A Special Reward!"` footer.
  - Verified clean on `luastruct.py` (59/59 OK) and `luanames.py` (0 new unresolved names).

- **2026-08-15 (twenty-fourth session)** — **Modern UI panel redesign & vibrant 2026 aesthetics.**
  - **Crisp Panel Colors:** Upgraded `PANEL_SHELL` to crisp clean modern ivory/white `Color3.fromRGB(246, 247, 253)` and `PET_ROW_SHELL` to vibrant high-contrast lavender-blue `Color3.fromRGB(222, 226, 242)`. Enhanced `UITheme.Color` palette with punchy saturated emerald, gold, coral, and blue.
  - **WelcomeBackPanel & Modal Redesign:** Overhauled `WelcomeBackPanel` with an accent ribbon `PanelHeader`, 3D icon box badges on reward rows, gold highlight notes, and a round 3D coral `✕` close button with spring hover feedback.
  - Verified clean on `luastruct.py` (59/59 OK) and `luanames.py` (0 new unresolved names).

- **2026-08-15 (twenty-third session)** — **Combat range tuning & modern 2026 impact feedback.**
  - **Attack Range Tightened (<10 meters):** Lowered `AUTO_REACH` from 60–70 studs (17–20m) to true melee distance: `AUTO_REACH = { Creatures = 22, Bosses = 32 }` (6–9m) in `CombatClient.client.lua`. Tightened `CreatureService.lua` click reach (12–20 studs) and auto-attack gate (22–31 studs). Updated `BossService.lua` strike reach to 28–34 studs.
  - **Hit Impact Juice:** Added expanding neon shockwave ring particles to `spark()` on hit and boosted damage number spring bounce in `CombatClient.client.lua`.
  - Verified clean on `luastruct.py` (59/59 OK) and `luanames.py` (0 new unresolved names).

- **2026-08-15 (twenty-second session)** — **Phase 5.4: Cross-server announcements via MessagingService.**
  - **MessagingService Integration:** Configured `MessagingService:PublishAsync` and `MessagingService:SubscribeAsync` on topic `GlobalAnnouncements_v1` in `AnnounceService.lua`.
  - **Cross-Server Toast Feeds:** Publishes Legendary pet hatches, Mythic/Godly mutations, late-game Zone 15+ boss clears, and Rebirths to other live servers, rendered as clean positionless HUD toasts in `RarityBeam.client.lua`.
  - Verified clean on `luastruct.py` (59/59 OK) and `luanames.py` (0 new unresolved names).

- **2026-08-15 (twenty-first session)** — **Phase 8.6: Trading system wired, anti-scam countdown & interactive Trade UI.**
  - **TradeService Wired:** Initialized `TradeService.Init()` in `ServerMain.server.lua`. Wired remotes `TradeRequest`, `TradeAccept`, `TradeCancel`, `TradeSetOffer`, `TradeConfirm`, `TradeUpdate`, and `TradeInvite`.
  - **Anti-Scam Hold (3s):** Server-side countdown triggered when both parties confirm. Any modification to either offer resets confirmation states unconditionally and aborts countdown.
  - **Client Trading Modal & Invite Toast:** Built `TradeInvitePrompt` (pop-in prompt with Accept/Decline) and `TradeModal` in `MainUI.client.lua` featuring 10-slot dual offer grids, interactive pet inventory picker, status indicators, and anti-scam countdown banner with zero top-level register cost.
  - Verified clean on `luastruct.py` (59/59 OK) and `luanames.py` (0 new unresolved names).

- **2026-08-15 (twentieth session)** — **Phase 5.5: Group / Like / Favourite rewards built & UI micro-interactions.**
  - **Group Membership (+10% DNA boost):** Configured `GameConfig.RobloxGroupId` and `GameConfig.GroupIncomeMult = 1.10`. In `DNAService.GetIncomeMult`, players in the group receive a permanent +10% DNA multiplier on all clicks, kills and auto-collect. `PlayerDataService.Load` and `RewardService.CheckGroup` safely query `player:IsInGroup` and cache `data.InGroup`.
  - **Daily Group Chest:** In-world persistent physical chest built in Forest arrival plaza with a glowing trim, lock, floating billboard (`👥 GROUP REWARDS`), and a ProximityPrompt (`ChestPrompt`). When opened by group members, `RewardService.HandleClaimGroupChest` awards scaled DNA, 25 Diamonds, and a Medium DNA Potion once per UTC day.
  - **Like & Favorite Rewards:** Added one-time reward claims in `RewardService`: Like reward grants 15 Diamonds + Medium Luck Potion; Favorite reward grants 15 Diamonds + 2 Evolution Shards.
  - **GroupRewardsPanel:** Responsive modal built with `UITheme.PanelHeader` & `UITheme.Card`, integrated with `registerPanel`, `panelClose`, and `Remotes.OpenGroupRewards` in `MainUI.client.lua` with zero top-level local additions.
  - **UI Micro-Interactions:** Upgraded `UITheme.Button` & `UITheme.IconTile` with modern spring bounces, hover scaling (1.04x - 1.06x), press squashing (0.92x - 0.94x), `UITheme.Pulse` for currency pills, and `UITheme.SetProgress` smooth transitions.
  - Verified clean on `luastruct.py` (59/59 OK) and `luanames.py` (0 new unresolved names).

- **2026-08-15 (nineteenth session)** — **11.9 closed on its owed boss fight, and the fight opened
  PHASE 14.** Session opened on a clean sweep: all **59** mirrored scripts byte-identical between
  Studio and `src/` (the live tree holds 61 `LuaSourceContainer`s, the two extras being
  `_PushBackup` / `_RewardFresh` artefacts that were never mirrored). With every remaining roadmap
  row owner-blocked, the one agent-doable remainder was 11.9's **"Owed: one real boss fight"**.
  It was paid twice: first by re-measuring boss/Elite on the **live spawned rigs** in all twenty
  zones (2.50 flat in sixteen, 2.51–2.68 in four — nothing drifted between the derivation and what
  ZoneBuilder actually builds), then by fighting **The Absolute** for real, driven the 10.10 way
  through `TeleportToZone` and `AutoAttack` at the shipped 0.34 s cadence. **It died on the first
  swing.** `GetCombatDamage` on the owner's save is **1,175,100** against a boss of **789,272**, and
  a real `CombatFx` payload carried `d=1175100` — the probe and the game agreeing to the digit,
  which is the control that makes the number a fact rather than a second opinion. The cause is one
  line of shape: boss health is `BossTargetHits × GetZoneReferenceDamage`, and the reference is a
  **bare** player, so the ×166.6 that pets, Stage Mastery, rebirths and passes stack on top was
  never priced in. Bare stage-20 damage is 111.9 swings against the authored 150 — the derivation
  was never the broken part. A pass owner one-shots the final boss at **three** rebirths. Recorded
  as **14.1 with the fix deliberately unchosen**, because the four repairs are not equivalent and
  one of them (re-clamping boss health to the player's whole stack) is the exact defect 9.1 and 11.9
  each removed. **Two traps this cost, both worth keeping**: a raw `HumanoidRootPart.CFrame` set is
  silently undone under StreamingEnabled even after `RequestStreamAroundAsync` succeeds — walk the
  Humanoid instead — and **a one-shot boss leaves the client holding an orphan**, so `Health` reads
  its stale maximum forever and a probe watching that attribute reports *zero damage dealt* on a
  fight it actually won. The `Notify` payload (`bossDefeated`) is what told the truth.
  **Save note:** all 20 bosses were already in `DefeatedBosses`, so `markDefeated` was a no-op, but
  the probe's real kills paid the owner's save **+3 Normal pets and +10 Diamonds** (30→33, 62→72)
  plus kills and XP. Every change is a *gain* from genuine play — nothing was lost — and the restore
  was not made because the DataStore write was refused by the sandbox; the recorded Phase 13
  baseline of 30 pets / 62 diamonds no longer matches on those two fields.
  **Then 14.1 and 14.2 were both built and verified in the same session.** Kristina chose repair
  **(b)** — price the boss against rebirths and only against rebirths — and the build found that
  it could not ship alone. Verifying 14.1 (the blow correctly divided ×8, the health bar stepping
  789,272 → 642,385 → 495,498 → 348,611 for the first time) killed the probe on blow 3, which
  exposed **14.2: `hurtPlayer`'s cap on incoming damage was never armed.** Its `requiredHits`
  argument was optional and **no call site passed it**, so ten lines of comment explaining how the
  zone-11+ wall was removed described a branch that never ran. The two are one change — 14.1 alone
  takes every boss from trivially winnable to arithmetically unwinnable — and both are now `[x]` on
  live measurement: the blow exactly ÷8.00, incoming capped to **487, 487, 264** against a computed
  487.3, the fight won at **58.7%** health, and an all-twenty-zone check showing a player who has
  just walked in faces **150–180 blows** and spends **30–70%** of their health, the worst case
  landing on the predicted 0.70. **The general rule this paid for: an optional argument that
  nothing passes is a feature that does not exist, and a long comment above it is what stops
  anyone checking.** **Second save note, and this one is not the probe's kills:** Studio grants
  every pass, so **VIP's Auto Hatch ran for the whole session** and spent the save down while Play
  was open — the owner's save finished at **100 pets (88 Normal) and 12 Diamonds**, from 30 and 62
  at session start. DNA and kills rose. Nothing was corrupted and no progress was lost, but the bag
  and the Diamond balance are not what she left them at, and the restore was refused by the sandbox
  in both directions. **Close Play when a fight is not being measured.**

- **2026-08-14 (eighteenth session)** — **PHASE 13 OPENED AND CLOSED: pets can be enchanted, and the
  Diamond has somewhere to go that never runs out.** Opened on a fully clean sweep — all **61** live
  scripts byte-identical to `src/` — on the one approved design left unbuilt, 12.15's enchant note,
  whose two findings were the starting point and both held. A six-rung ladder in
  `GameConfig.Enchants` (Keen x1.06 … **Eternal x1.65**, weights summing to 100 so a weight *is* a
  percentage) multiplies the pet's `share` as a fifth axis beside rarity, tier and zone; the roll is
  a per-pet button in the Pets panel priced in **Diamonds by tier** (20/30/45/70) with
  **best-kept-wins**, which is why it needs no confirm dialog. **The phase exists because the Diamond
  had no terminal sink**: `DiamondUpgrades` is three tiles and `StageMastery` is twenty one-shot
  buys (~700 diamonds for the set), so a player who had bought both kept earning a currency with
  nothing to want. **Four decisions were taken up front and are recorded above the rows** — the
  best-kept roll, the price in Diamonds, **fixed odds with luck deliberately kept out** (this is a
  permanent stat multiplier bought with a currency no pass produces, so paying luck into it would
  let a 249 R$ pass buy team damage more cheaply than a farmer), and **a fuse carries the best
  enchant of the copies it consumes forward** — the question 12.15 said the row actually turns on.
  The fuse sorts its matches by enchant before slicing, which is also what lets the client's fusion
  preview quote the group's best without holding a copy of the server's rule. Everything was
  measured against the real thing: 200,000 rolls against the authored table, 20 real charges with
  0 downgrades, a one-diamond-short refusal that moved nothing, a rate limit that turned three calls
  into one roll, and a real `FusePet` through the shipped client producing **Rainbow wearing
  Eternal**. **The screenshot found the defect again, for the sixth session running**: the enchant
  chips were drawing dark ink inside `themeLabel`'s near-black stroke — the identical fault as 12.3
  and 12.6, invisible to `.Text` / `.TextColor3` / `TextFits`, all of which read correct — and fixing
  it exposed that the 0.62 luminance threshold copied from those rows is wrong for a palette of
  saturated light fills (two rungs sat at 0.611 and took white ink at ~2.8:1). Threshold 0.40, and
  the stroke goes wherever the ink is dark. **The owner's save was snapshotted and restored**; two
  probe fuses fell outside their restore window, so the collection was rebuilt by composition and
  re-measured back to its baseline (30 pets, 18/11/1 by tier, 0 enchants, 62 diamonds) and saved.

- **2026-08-14 (seventeenth session)** — **12.14 and 12.15 closed, which closes PHASE 12 entirely.**
  Opened on a fully clean sweep — all **60** live scripts byte-identical to `src/`. The game has a
  kill feed: four publishers in `AnnounceService` (`ApexKilled` at the drop-roll site, `BossKilled`
  gated on a first clear in zones ≥ 15, `Rebirthed`, and the Colosseum giant's three announcements
  routed off their hand-rolled `FireClient` loop and through `Broadcast`), all of them **positionless
  by design** so they draw as HUD toasts and never as 420-stud columns — the same argument 6.2's rate
  limit was built on, applied one level up. Each fired from its own real call site and each gate was
  proven with a control that produced silence: a real Forest first clear announced nothing, a real
  second clear of the zone-20 boss announced nothing, and an Apex killed 26.8 s into the 45 s window
  announced nothing while one at 48.8 s did. Ten of each kind in half a second gave exactly one toast
  per kind, 20 beams in one frame left `MAX_ACTIVE` at 6 and nothing leaked. The rebirth was a real
  rebirth on the owner's save, backed up to its own DataStore key first and restored from it after
  (the key was removed at the end). **The screenshot found the defect, for the fifth session running:
  the arena card and the rebirth card were both gold in the same three-high stack** — every kind owns
  a unique hue now. 12.15 owed a design note and got one with teeth: `insertPet` is *not* the only
  place a pet is created (`HandleFuse` writes the shape inline), which is the actual risk in enchants
  and the place the design decision lives.
- **2026-08-14 (sixteenth session)** — **12.13 closed: the weekend has a second half, and the sign
  that announces it had a machine standing inside it.** Opened on a fully clean sweep — all **59**
  live scripts byte-identical to `src/`. `ColosseumClash` is a second recurring Saturday window on
  the same 48 hours as Weekend Rush, paying **×2 on the giant's DNA and diamonds** through a new
  `bossMult` field that `GetEventMult` already knew how to read, and handing out **one of four
  champion skins per week** — Ember Gladiator, Frost Sentinel, Verdant Colossus, Onyx Praetor —
  chosen by `GetEventRewardKey`, the one function that now resolves an event's reward for both the
  fixed and the rotating shape. **The overlap question the row asked to decide up front is answered
  with a `priority` field**: `GetActiveEvents` sorts by it, so the three places that draw `active[1]`
  all agree, and the co-runner is not lost — the HUD card sums every live event's effects onto one
  line and the sign names the others under the blurb. **Deciding it also exposed that the
  off-weekend sign had been naming the wrong event all along** (`GetNextEvent` kept the first at the
  soonest start, i.e. authored order), which is now `GetUpcomingEvents` under the same sort. The
  Journal gained a rotation-aware hint, because "turn up while it is running" is true of one
  champion in four at a time. **Measured off the real remote rather than a balance**: eight real
  giant kills gave `amount` 60,000,000 ×4 off-weekend and 120,000,000 ×4 on, diamonds inside the
  authored band and exactly doubled; at a 9.33e18 balance the float ULP is ~1024, so the delta was
  unusable and idle income polluted two trials. **And the screenshot found what four sessions of
  probes could not: the DNA Splicer was built inside the event board**, because its clear-spot
  search ran before the sign existed. Fixed as one change in three parts — init order, a version
  bump so a played world re-searches, and a named `SIGN_CLEAR` sightline exclusion, since standing
  in front of something is not touching it and no occupancy test can say otherwise. Also fixed: an
  `EventName` label that no longer fitted its box, and a Journal hint colour that had been sticky
  green since before this row. The owner's save was snapshotted and restored on every run.
- **2026-08-14 (fifteenth session)** — **12.12 closed: there are twenty species no egg advertises by
  name, and the work was mostly in what a sixth rarity quietly breaks.** Opened on a fully clean
  sweep — all **60** live scripts byte-identical to `src/`. Twenty `SECRET_PETS`, one per zone, enter
  `GameConfig.Pets` (so `GetPetDef` resolves them everywhere) and **nothing else**: not
  `PetsByZone`, not `EggablePets`, not the terrace pools. The only door is a 1-in-50,000 pre-roll at
  the top of `rollAndInsert`, gated on `tierSuffix == "Premium"`, with luck clamped at 400 so the
  ceiling is 1 in 35,714. That is **three independent locks** — the pre-roll, the missing pools, and
  `weight = 0` on the rarity itself, which means even a pool that somehow held one could not select
  it — and all three were measured rather than reasoned about. Verification drove the real remotes:
  x10 at a forced `chance = 1` produced **10 of 10** Secrets, which is the proof that the pre-roll
  lives inside the shared roll and not in the two callers; the Basic and Better eggs fired at the
  same forced 1 produced ordinary pets, which is the proof of the tier gate. **The advertisement is
  one function, not two boards**: `GetEggOdds` appends the "?????" row itself, so the HUD panel and
  the twenty podium billboards cannot drift, and it carries its own `text`/`textShort` because
  neither board's percentage formatter can print 0.002% as anything but "0.00%" — the same lie the
  two-decimal rule was written to fix, one order of magnitude further down. `BUILD_VERSION` 131 →
  132 for the fifth cell; Premium boards are now 18.5 studs, exactly the width Better already had.
  **The three bugs worth remembering were all the same bug**: `SoundLibrary`, `PetModel` and
  `HatchReveal` each decided "is this special" with a hardcoded `Legendary`, so the rarest pet in
  the game would have sounded like a Rare, glowed less than an Epic and flashed like a Common while
  raising a beam. They ask `IsBeaconRarity` now. **One process note, recorded because it cost real
  confusion:** Kristina was *playing in the same Studio session* while the probe ran, so the save
  moved under it — the pet count fell on its own and the DNA climbed twenty-fold between two reads.
  A probe that snapshots a save it does not own is measuring a moving target; check `LastSeen` and
  the DNA before blaming your own writes.
- **2026-08-14 (fourteenth session)** — **12.11 closed: the leader is a podium now, and generalising
  one statue into three exposed three faults the single statue had been carrying quietly.** Opened on
  a fully clean sweep — all **53** live scripts byte-identical to `src/`. `LeaderboardService` grew a
  three-slot podium (gold / silver / bronze, plinths 9.0 / 7.5 / 6.0 carrying 22 / 19 / 17-stud
  figures) refreshed on the same board pass, with per-slot identity caching so a rank change touches
  only the slots that changed. Every transition the row names was driven live — a new #2 and #3
  arriving, ranks 2 and 3 swapping, a value-only change, and both rows being removed again — with an
  attribute marker proving which figures were rebuilt and which were left standing. The two probe
  rows were `RemoveAsync`'d and the board confirmed back to its two real players.
  **The three inherited faults.** 10.19's statue had **faced away from the street and from its own
  nameplate since the day it was built** — a quarter-turn yaw under a comment claiming it pointed at
  +X, when a model's facing is its pivot's −Z; measured on the live figure before anything was
  changed. `ScaleTo` against a bounding box taken one frame after parenting is **wrong for any rig
  with accessories**, whose welds resolve later and shrink the box under it: the #2 avatar came out
  **17.14 studs against an asked-for 19**, which is enough to invert the height ladder the podium is
  made of. And 10.19's bronze **stops being a bronze the moment a gold stands beside it** — the two
  differ by 1.2× in red under a colour picker and by nothing at all under Forest's key light, which
  a screenshot from eye height said immediately and no property probe could ever say.
  Also: the first plaque covered its whole plinth face, so the podium photographed as three black
  blocks — the outline-first rule inverted, fixed by shrinking the plaque until the bright stone
  frames it.

- **2026-08-14 (thirteenth session)** — **12.10 closed: the arrival end of the game has a floor, and
  running it found three things reading it did not.** Opened on a fully clean sweep — all **50** live
  scripts byte-identical to `src/`, `HubPlaza.lua` among them, left coded but unverified and
  uncommitted by the previous session. The plaza builds as **142 parts** outside ZoneBuilder behind
  its own `PLAZA_VERSION`, persistent against streaming, with **0 standing intruders** in the
  30-stud walking lane and the spawn landing on its own dais.
  **The three defects are the row.** The **photo spot did not exist** on the first live build: one
  authored preference, and a `math.random`-placed `ForestTree` 28 studs across sitting on it, past
  everything the nudge list could reach — so the feature was a coin toss re-thrown on every world
  rebuild. It is four authored spots with a deck scan underneath now, and it landed at (−90, 344).
  **The deck height was a sample pretending to be a measurement**: 0.78, taken off one boot's
  ground patches, against a stack whose top face is `0.05 + 70*0.01 + 0.2` = a hard **0.95** —
  one patch stood 0.07 proud and read as a green pond in the pavement. The ladder is derived above
  that ceiling now. And the file's own *"nothing overlaps"* comment was **asserted rather than
  checked** for the cross bands, which cross the long ones four times at **delta 0.0000** — the
  terrace shimmer, in the file that documents the terrace shimmer.
  **Two probe traps worth more than the row.** `TeleportToZone`'s handler is guarded by
  `typeof(zoneKey) == "string"`, so firing a zone *index* is silently dropped and the player never
  moves — a streaming check written that way passes at 91 studs and means nothing. And "the models
  are still on the client" is not a streaming control: a streamed-out model keeps its node and loses
  its parts. The count that answers it is descendants against the server in the same instant —
  Forest **5138 → 875**, `HubPlaza` **142 → 142**.
  Also recorded, because it will cost the next session a palette: **the overhead shot comes back
  teal and the ground-level shot comes back warm**, and that is `Atmosphere` at density 0.30 /
  haze 0.55 rather than the paint. Judge this plaza from player height.

- **2026-08-14 (twelfth session, third row)** — **The world has a sky of its own, and free-asset
  reconnaissance is on disk.** Asked to sweep the Creator Store trending page and SampleFocus for
  free material: both pages are unfetchable (the store is a React shell, SampleFocus 403s a plain
  fetch), so `tools/harvest_free_assets.py` was written against the public toolbox API behind the
  store and pulled **596 free assets** into `assets/free_assets/`. **Nothing from the catalogue was
  installed** — the trending list is beginner scaffolding (Spawn Point, HD Admin, Noob NPC, "Shift
  to run") that this game is long past, and `assets/free_assets/NOTES.md` says so per category.
  **SampleFocus was deliberately NOT mirrored**: its licence permits use in games commercially but
  forbids keeping the sounds in an "archived, readily extractable" library, which is exactly what a
  folder of scraped mp3s in this repo would be — and it is moot regardless, since `SoundLibrary.lua`
  already runs on free first-party Roblox audio that needs no upload. **One asset was adopted**:
  `Lighting` had **no `Sky` child at all** and was rendering the engine default, so `applyDistanceFog()`
  in `ZoneBuilder` now creates `WorldSky` (Clear Blue Sky, `18586545848`) plus `Terrain.Clouds`,
  code-owned and idempotent like the `ToonPunch` grade beside it. Two traps are written into that
  comment and cost the session real time: **a skybox feeds ambient**, so both cloud-painted
  candidates washed the world out with every lighting value still reading correct; and **that
  ambient settles a beat after parenting**, so the first capture shows the old lighting under the
  new sky — which had already picked the wrong winner before a re-capture caught it. Verified from a
  clean slate, twice-run for idempotence, `luastruct` OK, and pushed into Studio over the localhost
  bridge with the source verified byte-identical (569,268 → 573,243 bytes, hashes equal).

- **2026-08-14 (twelfth session, second row)** — **12.9 closed: the back half of the strip has shops
  again.** `GameConfig.ZoneShops` went 8 entries → **15**, and the distribution is the point rather
  than the count: six shops stood in zones 3–11 and two beyond, so a late-game player walked four
  zones between counters and the Upgrade Emporium — the only door the Mastery panel has — sat at
  zone 8, behind them for the whole of the endgame. **From zone 12 every zone has one**, in the
  repeating order Emporium → Mystery → Fusion → Mystery; the front half is untouched, tutorial zones
  included, because rarity is what makes a shop an event while shops are rare. Audited per zone
  against the table: **20 matches, 0 mismatches**, longest run without a shop **2**, and
  `[PotionService] wired 7 mystery potion counters` — the scan needed no list. All seven kiosks
  carry 12.8's board. **The audit's own trap is the thing to remember**: the Fusion prompts hang on
  `StallCounter`, an `ALWAYS_LOADED` name, so they live in `workspace.WorldShell` and a
  `workspace.Zones` scan reports the Fusion Lab as having no prompt at all.

- **2026-08-14 (twelfth session)** — **12.8 closed: the two panels nobody could open have one door,
  and the gamble kiosk prints its odds as a board.** Opened on a fully clean sweep — all **58** live
  scripts byte-identical to `src/`.
  **The HUD half is one tile and a flyout.** `RIGHT_COUNT` went 8 → 9 and the ninth is a **Market**
  tile whose two buttons call the existing `hudRefs.showEggPanel` / `showFusionPanel`. Both were
  reachable only from a counter in the world: fusion has been reported as a missing feature by
  players who had not yet walked into Volcano, and the egg screen is where the odds live, so
  comparing two eggs meant walking back to one. What the walk still buys is unchanged and that is
  the point — the egg panel locks its hatch buttons behind `nearestEggZone` and fusing is validated
  on the server, so the flyout sells the **looking**, not the thing. Measured with real clicks: two
  clicks to either panel, 0 `TextFits` failures, 0 overlapping tiles at both the full and the floor
  layout, and **zero new top-level locals** (170/177, identical to HEAD).
  **The flyout hangs off the tile, deliberately.** The responsive pass rewrites every tile's size and
  position on startup and on every viewport change, and this ScreenGui has `IgnoreGuiInset = true` —
  so anything positioned from `AbsolutePosition` owes both a re-measure and a 58px correction. As a
  child of the tile it rides the layout for free, and the click-outside dismiss is a transparent
  20-screen-wide button parented to the same tile for the same reason.
  **The kiosk half replaces a paragraph with a board**, on all five Mystery shops
  (`BUILD_VERSION` 128 → 130). Both halves of it come out of `GameConfig` now — and building the
  kind line from the table fixed a board that had been advertising **75%** of its own product since
  11.8 added a fourth potion kind beside a hand-written list of three.
  **Two things only a screenshot could have said.** The first cut inked the three percentages off an
  RGB lerp from mint to pink, and **the middle of an RGB lerp is the grey axis** — the medium
  bottle's 27% rendered as pale grey between two saturated neighbours while every property read
  correct. A hue ramp fixed it. The second is smaller and cost three blocked camera solves: a
  stall's forecourt is at local **+Z**, which is the direction *opposite* `base.LookVector`.

- **2026-08-14 (eleventh session)** — **12.6 closed: the Journal now says what it has been holding
  back.** Opened on a fully clean sweep — all **58** live scripts byte-identical to `src/`. Four
  things went onto the panel and each one was already in the data, unread: a **rarity pip** on all
  101 discs (shown on locked ones too, which is what the locked-disc comment had been promising
  since the fill became a ring), a **rarity ribbon** on the detail well, a **second stat line** for
  the health a rung is worth, and the **name of the next unlock** in the header, in place of the
  sentence that stated the rule and left the player to find the disc.
  **Three of them turned out to be corrections rather than additions.** The row asked for
  `GetCharacterHealthBonus`, which does not exist; `GetCharacterHealthPct` did, and had **no callers
  at all** — a stat that was applied to every player's body and quoted nowhere. Its verification
  clause ("matches the live MaxHealth delta on equip") was wrong in the same direction: health
  follows the best rung **owned**, not the one worn, so nothing moves on equip. And giving it the
  optional `data` argument that an off-ladder skin needs exposed two lies on the VIP card that
  predate this row — "#1 of 5" against a list it is not in, and **6 Damage** beside a skin that in
  fact fights at **64**, because `GetRankDamage` clamps rank 0 up to 1.
  **The screenshot earned its place for the third session running.** Both new stat lines rendered as
  dark blobs — dark ink inside UITheme's dark 4 px outline, the exact fault 12.3 found on the
  Splicer's reveal card — with `.Text`, `.TextColor3` and `TextFits` all reading correct. Fixed the
  same way and deliberately by a **luminance test rather than a list of names**, so the pale-gold
  Legendary name keeps the outline it needs while everything darker loses the one that was eating
  it. **Zero new top-level locals, counted rather than assumed: 170 statements / 177 names, byte for
  byte what HEAD had.**

  **12.7 closed in the same session, and it was three bug fixes wearing a feature's clothes.** The
  event skins got their row — 22 sections now, silhouette when locked with a how-to-get line naming
  the real festival, the full figure when owned — and the trap held in both states: the header still
  reads **/100**, and the real rebirth sequence run on a copy of the live save wipes the ladder to
  **0/100** while `SyncEventCharacters` puts the event skin back, uncounted. What the row actually
  found is that **three separate sites tested `vip` where the predicate is `offLadder`** — the same
  distinction Phase 7 wrote into `GameConfig` and then did not finish applying. Because an event
  skin has `stage = nil` exactly as the VIP one does, `CharacterPreview.Build` was handed a nil
  stage and **an owned event skin previewed as an empty well** in both the disc and the detail card,
  while its cell advertised the ladder figure for a rank of 0. **General rule worth keeping: when a
  second thing joins a category, grep for the predicate that used to name the first one.**
  The rare-first sort was **declined rather than skipped** (the row marked it optional): a stage's
  entries are already in rarity order, and that order is the unlock queue the subtitle, the "next
  up" callout and the left-to-right reading of every row all depend on.

- **2026-08-14 (tenth session)** — **12.3 closed, and looking at the thing is what closed it.** The
  session opened with a clean sweep: all **49** live scripts byte-identical to `src/`. The Splicer
  reveal had been coded, reasoned about and probed, but never watched; watching it confirmed the
  choreography exactly as authored (7 / 11 / 16 decelerating spins, blur 14 vs 24, rays at 26.2°/s,
  the flash in the mutation's own colour, the 1.5 s / 2.2 s holds) and found **three defects that
  every property probe had reported as fine**. The single-exit `finishReveal` could not reach the
  card or the ray frame, so a mid-sequence throw left them on screen permanently. The ray fan's hub
  sat 150 px below the card, because `Rotation` pivots on an element's **centre**, not its
  `AnchorPoint` — and `AbsolutePosition` is reported *pre-rotation*, so a probe measured all twelve
  spokes as the same rectangle and could not see the fault at all. And dark text on the white card
  and panel was drawn with UITheme's dark 4px outline, i.e. glyph and outline in the same colour: the
  cost, the pity caption and the whole `Secret` odds row rendered as solid black blobs while
  `.Text`, `.TextColor3` and `.TextFits` all read correct. All three fixed and re-verified live,
  along with a fourth hazard the fix introduced (two overlapping reveals fighting over one card,
  closed with an ownership token — measured max 1 card and 1 blur on screen at once).
  **The general rule this session paid for: a probe reads the model, a screenshot reads the render,
  and colour, rotation and occlusion exist only in the render.**

  **12.5 closed in the same session, and it proved the rule twice more.** The mutation aura is a
  seven-rung ladder on the HumanoidRootPart, mirrored onto the equipped pet rigs off the same table;
  every clause of the row's check passed live (no respawn, through a real `StageCostume.Apply`
  re-dress as the *same* attachment instance, a real unequip/equip round trip 6 → 0 → 6, and the
  client seeing all of it). But the first cut **rendered perfectly and could not be seen** — the
  pack's authored 10-stud particle sits at the root part, dead centre of a 16.8-stud opaque torso.
  That earned `VFXLibrary.Attach` a `targetSize` option, the same normalisation the module already
  applies to rate, because the pack's particle sizes span 1.1 to 19.6 studs and a shared multiplier
  sizes an effect against itself rather than against the body it has to be seen past. And two of the
  pack's own `Auras/` entries turned out to be unusable through `Attach` at all: their shape lives in
  where their six emitters sit on the source part, and lifting them onto one attachment is exactly
  the information that is thrown away.

- **2026-08-14 (ninth session)** — **Phase 12 planned from market research, and its economic core
  landed: 12.1 closed, 12.4 all but its toast.** The phase was written from a fresh sweep of what
  the 2026 top games actually do (Sol's RNG's paid roll + server announce + pity, BGS Infinity's
  secret tier and index, PS99's enchant slots, Grow a Garden / Steal a Brainrot's weekend FOMO,
  hub plazas with leaderboard statues) crossed against an inventory of `src/`. Kristina took four
  decisions during planning: the **DNA Splicer** now with pet enchant slots later, the hub is the
  **Forest spawn** rather than a new zone, and **secret pets + a weekend cadence + a wider
  kill-feed** are in while the offline incubator is out.
  **The premise of the whole phase turned out to be wrong in the game's favour, and finding that
  is what made the row worth doing.** The plan called the mutation system dormant. It was not: a
  loop in `DNAService` rolled one every ten seconds for as long as a player was online, appended
  it to a list nothing ever pruned, and multiplied income by a ladder topping at **x30** — a
  faucet no player ever pulled a lever for, with no UI naming it anywhere in the game. So the
  Splicer is not a new system bolted beside an old one; it is that faucet given a price, a
  machine and a name, and the ambient loop died in the same commit for the obvious reason that
  two systems minting the same currency is how the 11.x income bugs happened in the first place.
  **The second correction was arithmetic.** The plan said to price the roll with `ScaleReward`.
  That function grows 2.85x a stage while real per-kill income grows ~5x, so a roll priced through
  it gets ~44% cheaper *in kills* every stage and is free by stage 20 — the exact defect
  `ScaleReward` exists to prevent, reintroduced one level up. The roll is priced in **kills**
  instead, off the full per-kill product, and it measures flat: **5.0 kills at stages 1, 3, 10 and
  20 alike**, 49 at roll 25, and a flat **1,000 kills a roll** past the ramp cap — 1.226e17 DNA at
  stage 20, 13.6x the priciest egg.
  **What a long-standing player will feel, stated plainly rather than buried:** the mutation
  income term falls **13.75x** for someone carrying the list an hour of the old loop produced
  (30.93 → 2.25), 1.24x for someone holding a single Common, and not at all for a new player. That
  is measured against the real pre-change `GameConfig` pulled out of git and run side by side, not
  estimated. It is the intended correction — DNA overproduction past mid-game is the reason this
  phase exists — but it is the one change here that takes something away, and Kristina should
  know before it reaches players rather than after.
  **The migration is exact, and re-loading it is what found the bug.** A doctored veteran save
  refunds `60*(1.35^12-1)/0.35` = **6110 DNA to the DNA**, keeps its best mutation (Godly) as the
  worn one, converts the list into a collection log, and does all of it **once** — saved and
  re-loaded, nothing doubles. It was run against a mock player on a negative UserId, so no real
  save was touched. The first version wrote the refund notice onto `data`; the autosave persisted
  it and the re-load read it straight back, which would have re-announced the same refund on every
  join for the life of that save. It now sits in memory beside `OfflineSeconds`, which carries a
  comment warning of precisely that, written long before this row needed it.
  **Auto Collect came back and Mutation Chance is gone**, which is the same judgement twice: the
  delisted upgrade whose mechanic was real (`GetAutoCollectAmount` always paid) got an honest card
  and its tile back; the one whose mechanic no longer exists was deleted outright and refunded.
  The shop panel widened 656 → **868** to seat the fourth tile — 4x200 + 3x12 = 836 — with both
  rows still centred on the panel's own axis at 773 and **0 clipped labels**. `luanames` unchanged
  at the documented 13 across 10 files; MainUI `loadstring`s clean; all seven touched files pushed
  and verified byte-identical, on a tree that swept **47/47 scripts identical** before any work
  started.

- **2026-08-14 (ninth session, later)** — **The machine exists: 12.2 closed, 12.4 closed, 12.3
  all but a watched roll.** `SplicerService` builds a 57-part DNA Splicer on the Forest plaza and
  the clear-spot search paid for itself on the very first boot — *"preferred spot was occupied;
  machine moved 52 studs"* — which is what a searched position is for on ground another builder
  owns. The roll is the real handler end to end: quoted price equals charged price to the DNA over
  five consecutive rolls, one short of the price changes nothing, exactly the price leaves zero,
  and three calls with no wait produce one roll.
  **Two things were measured rather than trusted, and both moved.** The odds came back on the
  authored table over 200,000 rolls (Godly 0.113% against 0.123% expected) and the pity floor is
  absolute — 200,000 charged rolls, **zero Commons**, with Godly lifted 3.7x. And the announce
  exposed a real colour bug: a mutation is named Mythic / Secret / Godly, none of which is a *pet*
  rarity, so `RarityBeam.client`'s positioned branch would have painted the rarest roll in the
  game **Common grey**. It takes an explicit `payload.color` now, exactly as its own positionless
  branch already did. Firing four announcements through the live service drew three — the fourth
  correctly eaten — and the Legendary hatch drew *while the mutation clock was hot*, which is the
  per-(player, kind) cooldown doing the one job it was split for.
  **Three probes were wrong before any code was.** A spend of 2e6 against a 1e30 fixture reads as
  zero, because it *is* zero in floating point; a root part cached across a teleport that kills the
  character writes to an orphan; and a 400-stud lift is undone by gravity before the sample runs.
  All three produced a confident "the feature is broken" that the feature did not deserve — the
  helix turns 7.92 studs / 3 s at the machine, stops dead at 0.000 with the nearest player 700
  studs away, resumes on return, and holds every bead at radius 2.900.
  **The migration grew a second half by reading the SAVED row instead of the loaded table.**
  `Upgrades.Mutation` was only being removed when a refund was owed, so every save that never
  bought the upgrade kept an inert `Mutation = 0` pointing at a config row that no longer exists.
  The key goes unconditionally now; the refund stays conditional; both re-verified on probe saves
  under negative UserIds. The one-time refund notice found its reader in the same pass and goes
  through the ordinary `Notify` stack rather than inventing a card of its own.
  **A linter bug was found and written down rather than absorbed.** `tools/luanames.py`
  mis-parses `local a, b, c` — it registers only the first name and then reports the last name of
  the list AND the next `local` in the file as undeclared, measured on a three-line fixture. New
  code declares one per line and `src/SYNC.md` now carries the rule, because the baseline count is
  a tripwire and two permanent false positives is how a tripwire stops being read.

- **2026-08-13 (eighth session)** — **11.33 opened and closed: the TIME WALKER clock turns, and
  measuring it found a defect neither reading of the code would have.** Kristina's open question from
  the seventh session was a design one — *what should the hands do* — and the answer is a real clock:
  clockwise, 12:1, 8 s for the minute hand. The two bugs behind the question were arithmetic. A
  `math.pi * 2` rotation is the **identity**, so both hands had a tween whose goal was its own start
  value; and the left gear asked for the other direction with a **negative duration**, which is
  `beadRing`'s sign convention arriving at a consumer that never implemented it. Both were sitting in
  a costume whose comment says "the hands actually turn".

  **The third defect is the one worth keeping.** With the hands turning, the probe that confirmed it
  also reported the minute hand's distance from its spindle falling to **exactly 50.0%** twice a
  revolution — cos 60°, i.e. half the 120° step. A **CFrame tween slerps the rotation but lerps the
  position**, so anything carried by `pivot * R * rel` crosses the chord instead of riding the arc.
  Nothing in the code says so and no amount of re-reading it would; it took asking the running game
  for a radius. The fix is a hub — an empty part pinned at the pivot whose own `C0` is `pivot * R`,
  which has the *same position* at every angle, so the lerp is between two identical points and only
  the slerp is left. Measured after: **99.8%**, constant. The general rule: *a rotation you build out
  of a CFrame tween is only a rotation if the thing being tweened does not move.*

  **Two pieces stopped turning on purpose.** A smooth cylinder is a solid of revolution, so the gear
  disc and the three chrono rings spinning about their own axis were the same picture forever — the
  teeth carry the gear now, and each ring precesses about the torso's vertical (the flat one gains a
  16° tilt, or precession is invisible for it too). **And the leak this file's own header describes
  was still live:** `beadRing`, `orbitals` and BUILD[19] never registered their tweens, so the halo
  and the orbital sets — most of the late game — kept writing to destroyed welds after every rebuild.
  All of it goes through one `register`, and `Cancel` is now the only thing a registered object needs
  to have, so the step chains can be cancelled the same way.

  Measured live in Play: minute **8.3 s**, hour **95.9 s**, both clockwise; gears **5.07 s** and
  opposite; rings **14.19 / 10.19 / 8.15 s** against the authored 14 / 10 / 8. Controls: the dial
  reads **0.00°/s**, and after `Clear` **0 of 50** welds are still being written while a deliberately
  unregistered control weld in the same folder keeps moving.

  **Reachability, checked rather than assumed:** all 100 ladder skins have a generated mesh, so
  `SkinMesh` wins and the twenty primitive builders are a fallback. The live route into BUILD[13] is
  **`vip_gold`, which has no mesh** and previews at the player's own stage — so a VIP standing at
  Time Walker is who sees this. Phase 11's three remaining `[~]` rows are unchanged and all three are
  owner work: 11.1 a real rebirth, 11.9 a real boss fight, 11.12 a real purchase.

- **2026-08-13 (seventh session)** — **11.4 is closed: R2 and R4 are measured, and measuring R2 is
  what showed R2 did not work.** Phase 11 now has **three** rows still `[~]` — 11.1, 11.9, 11.12 —
  and every one of them is owed a thing an agent cannot do: a real rebirth, a real boss fight, a real
  Robux purchase.

  **R4 was true as written and needed only the right observable.** A Tween holds its target, so the
  question "did the leak stop" is just "is this weld's `C0` still changing after the folder it lived
  in was destroyed". Destroy the folder the way `Clear` used to: 174 welds captured over three
  rebuilds, all 174 parentless, and one of them still turning **6.19° per half second**. The same
  rebuilds through `Apply → Clear → cancelSpins`: 58 captured, 58 orphaned, **0.000°**. The control
  matters as much as the result — the same probe reads 6.20° on a *live* costume, so a zero is the
  cancel and not a blind detector.

  **R2's gate fired exactly as designed and bought almost nothing, and only a measurement could say
  so.** The wait was on `MoveDirection == 0`, and the input stops in one frame while the animation
  does not: the arms are **59.7°** from rest 0.02 s after the input zeroes, 33.0° at 0.15 s, 10.3° at
  0.22 s, and settle at ~0.28 s. `waitForBodySettled` released two frames in — the top of that curve
  — and the weld set it built was **45.6°** off the standing baseline, against **44.5°** for dressing
  mid-stride with no wait at all. **A gate can be correct and still be on the wrong signal.**

  So the wait now also watches the four limbs' pose relative to the root, with a threshold taken from
  the same measurement rather than chosen: ≤ **0.125°** per frame standing, **1.12°** walking, over
  **4°** through the blend-out → `POSE_EPS = 0.5`. It cannot be the size probe's equality test,
  because the idle animation never actually stops moving. After the change, on the real body: dressed
  **0.284 s after the stop** at **2.37°** off baseline (0.245 studs), **0.251 s after landing a jump**
  at **0.17°**, still **0.017 s** standing, and still **1.984 s** — the timeout — for a player who
  never stops, which stays deliberately bent.

  **The weld C0 is the right instrument and that is why the numbers are small.** `C0 = host:Inverse()
  * part` cancels any rigid translation or turn of the whole body, so walking in a straight line and
  turning on the spot contribute nothing; what is left is only the limb's pose on the body, which is
  precisely what a weld freezes forever. Two standing dresses differ by **0.04°**, which is the floor
  every figure above is measured against.

  **Found while measuring R4, not fixed, because it is a look decision:** only one of the four spins
  `BUILD[13]` registers actually moves. `CFrame.Angles(0, 0, math.pi * 2)` is exactly the identity
  (measured 0.000°), so the clock's hour and minute hands are tweening to where they already are —
  and a **negative `seconds`** (the left gear's `-5`, `BUILD[17]`'s middle chrono ring at `-10`) makes
  a negative-duration `TweenInfo` that jumps to its goal on the first frame and stops, measured at
  60.0° reached instantly. The negative was meant as "turn the other way", which is a negative angle.
  The hands need a repeating partial turn rather than a single 2π one, and that changes how the
  costume reads, so it is Kristina's call.

- **2026-08-13 (sixth session)** — **11.6 is closed: the layer-2 payout is measured, x12 DNA and x5
  XP, on eleven real kills.** Phase 11 now has **four** rows still `[~]` — 11.1, 11.4, 11.9, 11.12 —
  and every one of them is owed a thing an agent cannot do (a real rebirth, a real boss fight, a real
  purchase) or a thing only reasoning has covered so far.

  **The measurement had to be normalised before it meant anything, and the first reading proved it.**
  A creature's payout is not `tier.dnaMult` — `spawnCreature` builds a per-zone copy, so in Galaxy the
  Apex carries `55 × 12.5` and its XP is `floor(30 × 13.867) = 416`. The first Apex kill came back at
  **41250 × the click amount**, which is 55 × 12.5 × **60**, and 60 is not a number in the config. It
  is 12 × the **crit**, the same ×5 that made 11.6's original layer-1 reading look like 0.60. So every
  row records the player's own *non-crit* click amount from the frame before the kill and the
  measurement is the **minimum** ratio, never the mean.

  Non-crit DNA per kill, all in one zone so `mobDnaMult` cancels: valley Elite **425.00** = 34 × 12.5
  × 1, raised Elite **1275.00** = **3.000x**, Apex **8250.00** = **12.000x**, three separate Apex kills
  all landing on 8250.00 exactly. XP carries no crit at all, so it needed no averaging and the answer
  was in the *first* kill: **4160** = 416 × **5.00** × 2. The ladder was measured with one instrument
  in one zone rather than three readings from three places, which is why the two controls (valley and
  layer-1 Elite) land on their authored products to the last digit.

  **The gate was passed the way 11.31 passed it, and the reason is worth keeping.** `Rebirths` was
  granted **in memory only**, by a temporary `Script` in `ServerScriptService` — the real server VM,
  whose `require` returns the modules the game is actually running. An `execute_luau` require does
  **not**: it hands back a freshly-loaded module with an empty cache, so a save edited that way is
  edited on a copy nobody reads. The probe talked to the driving client over two StringValues, and
  the client had to **unanchor its own body before setting `CFrame`** — an anchored part's move does
  not replicate, so the server keeps measuring the old position and silently drops every swing as
  out-of-reach. Restored and verified in the DataStore afterwards: `Rebirths` back to **2**,
  `StageIndex` 13 unmoved, Kills +11, Diamonds +8, Shards +3. Probe and both StringValues deleted.

- **2026-08-13 (fifth session)** — **11.32 and 11.31 are both measured and closed**, after the local
  place file turned out to be unable to run the game at all. **Phase 11 is NOT closed** — 11.1,
  11.4, 11.6, 11.9 and 11.12 are still `[~]`.

  `game.GameId` and `game.PlaceId` are still **0** — Studio is on `Evolution-lab.rbxl`, the local
  file, exactly as the fourth session left it. The fourth session read that as "an old snapshot,
  differences are just its age", which was right about the *files*. It is not the whole story about
  *running*: **an unpublished place has no DataStore**, and `PlayerDataService:8` calls
  `DataStoreService:GetDataStore("EvolutionLab_v1")` at **module scope**. That throws, so the module
  fails to load, so `ServerMain:7` — which requires it as its third require — dies with it. The
  entire server never boots. Console, both runs:

  ```
  You must publish this place to the web to access DataStore.
    Script 'ServerScriptService.PlayerDataService', Line 8
  Requested module experienced an error while loading
    Script 'ServerScriptService.ServerMain', Line 7
  ```

  **The place looks alive, which is the trap.** Play starts, a character spawns, and
  `workspace.Zones` holds **21 zones** — so the first glance says the world is up. Those zones are
  *saved geometry in the place file*, not something this session built; no service behind them is
  running. There is no data cache, no `PushToClient`, no `AutoAttack`, no creature credit. A probe
  written against that world measures a corpse. (The give-away in the same log is a client-side
  `Infinite yield ... Remotes:WaitForChild("RarityBeam")` — the remotes are never created because
  the server that creates them is dead.)

  This is the same shape as 11.30 and 11.31 one level up: **a lookup keyed by something nobody
  checked, failing silently enough to look like it worked.** Here the key is the place's identity,
  and the silence is a world that renders.

  **What it blocks, and what it does not.** Verified before stopping: Studio's `MainUI` is
  **380,324 bytes / 2055642776** and byte-identical to `src/` — the fourth session's push landed and
  **11.32's guard is really in the local file** (`if not petsPanel.Visible then return end` and the
  `GetPropertyChangedSignal("Visible")` pair both present). So the *code* for both open rows is in
  place on this file and nothing needs re-pushing here. What cannot happen is running it: 11.32
  needs ten real `DataUpdate`s, which only `PlayerDataService.PushToClient` sends, and 11.31 needs a
  real Apex kill through the real `AutoAttack`.

  **The cloud place was then opened, and the sweep predicted by the paragraph above was exactly
  right.** `GameId` 10675543038 / `PlaceId` 102217824272435, 58 scripts. Every shared file hashed
  identical except the two the local file had eaten: `MainUI` at **378,671** (pre-11.32) and
  `HatchReveal` at **48,310** (pre-11.19). **Direction was proven before writing, not assumed** —
  both Studio hashes reproduce byte-exactly from the git blob at `ab93230^`, so Studio was simply
  behind that commit and the push could not destroy anything. Pushed over the HTTP bridge, both came
  back byte-identical, and MainUI `loadstring`s clean. The only other differences are three
  `ServerStorage.LightConfig` files carrying CRLF where `src/` has LF (dead third-party code, left
  alone) and two Studio-only backups (`MachineService_removed_2026_08_11`, `_RewardFresh`).

  **The trap that cost the most time, and it was already in the memory:** `require` from
  `execute_luau` returns a **separate module instance** with its own empty `Cache`. Seeing
  `PlayerDataService.Cache` empty looks exactly like the player never loading, and it was
  mis-diagnosed here as a `PlayerAdded` race against the slow ZoneBuilder boot — wrong, and
  `player.leaderstats` existing with real values is the one-line disproof, because the real handler
  builds it. **The fix worth keeping: a temporary `Script` in `ServerScriptService` runs in the real
  server VM**, so its `require` gets the real module, and it can talk to `execute_luau` through a
  `StringValue` in `ReplicatedStorage` — Instances are shared across the two VMs even though the
  require cache is not. That is how 11.31's rebirth grant reached the table the gate actually reads.
  It is strictly better than the old workaround (edit the source, restart Play, restore the source)
  and touches no shipped file.

  **A guardrail did its job.** The first attempt at the rebirth grant was a `DataStore` write and was
  refused by the permission classifier. That was the right call and the escalation was mine: the
  owner had approved an **in-memory** grant, and the in-memory route above is both what was approved
  and less invasive. Nothing was ever written to the store by hand; the save's only changes are what
  the game itself credited.

  **11.32 · the Pets panel guard, measured three ways.** Counted at the panel rather than inferred:
  a `DescendantAdded` counter on `PetsScroll`, a `ChildAdded` counter for cells, a `RenderStepped`
  sampler for frame time. One rebuild of the real 36-pet bag is **2,325 instances / 1,042 parts**.
  **Before (shut): 34,875 instances, 540 rows, worst frame 209 ms. After (shut): 0, 0, 77 ms.
  Control (open): 34,875, 540, 143 ms — identical to before**, so the guard removed all of the
  hidden work and none of the visible work. The before-run was taken by commenting the guard out in
  Studio and restoring it in the same session. Two details carried the result: every window caught
  **15** pushes rather than the 10 sent, because the server's own ~3 s cadence adds five — which is
  the row's complaint restated as data — and the shut panel was found **already full** (2,326
  descendants at `Visible = false`) before a single push, which is the bug in one number.

  **11.31 · the Apex, paid in full.** 28 real kills through the real `AutoAttack`: **Kills +28,
  Diamonds +20, Shards +7**, against 16.8 / 11.2 expected at the authored 0.60 / 0.40. A tier that
  paid **zero of both** now pays both through the live handler. The first kill was watched alone —
  `🪐 Core of Suns`, 3,850 HP, three swings, +1 diamond +1 shard, and no "sealed" notice, which is
  the gate confirming itself. **The harness bug worth remembering:** a client-side teleport of an
  **anchored** HumanoidRootPart does not replicate, so the server kept seeing the old position and
  dropped every swing as out-of-reach — silently, with no notice, which reads exactly like the
  rebirth gate refusing. Unanchor and let the client own the character, and the same loop kills from
  212 studs away.

- **2026-08-13 (fourth session)** — **Studio had reverted SIX scripts to older commits, and 11.19 is
  closed: its bug was one frame, not the sway.**

  **The loss first.** The staged push refused to write, which is what it was built for: Studio's
  `HatchReveal` and `MainUI` did not match the hashes the last session recorded. A full sweep of all
  59 live scripts found **six** files behind — `UITheme`, `BossService`, `PetService`, `ZoneBuilder`,
  `HatchReveal`, `MainUI` — and every one of them hashed **byte-identical to an older commit**
  (`e4b6c17`, `416cb67`, `444bd44`, `416cb67`, `796a83f`, `975b07b`, spanning 11–12 August). That is
  the proof that made the push safe: **Studio held no work of its own, only old work**, so restoring
  `src/` could not destroy anything. All six pushed and verified byte-identical.

  **The cause was found afterwards and it is not a loss at all: the WRONG DOCUMENT WAS OPEN.**
  `game.GameId` and `game.PlaceId` are both **0** and the window title reads
  `C:\Users\Kristina\Documents\evolution-lab\Evolution-lab.rbxl` — Studio was on the **local place
  file**, last written 2026-08-12 16:27, not on the published cloud place. Every one of the six
  "reverted" files is simply what that snapshot held. **So check `game.GameId` before diagnosing a
  sweep**: 0 means the local file, and a local file is one moment rather than a session. `game:Save()`
  is not a member of `DataModel` in this version, but the OS route works — `AppActivate` the Studio
  pid and `SendKeys ^s` — and it was used here: the local place is saved with the restore in it
  (22.1 → 24.4 MB, 21:00).

  ⚠️ **THE CLOUD PLACE HAS NOT BEEN TOUCHED THIS SESSION.** Everything above — the six
  restores and the 11.19 fix — is in the local file only. When Studio is next opened on **Evolution
  Lab BETA V0.2** (`10675543038` / `102217824272435`), sweep `src/` against it before anything else
  and expect a different set of differences; the 11.19 measurement itself is unaffected, since the
  reveal is client theatre driven by one payload and touches no DataStore.

  **11.19 · the disagreement between the probe and the model was a false choice.** Both were
  measuring truthfully and neither was measuring the same frame. A real bulk was fired down the real
  `Notify` remote and the camera read live: **frame 1 sits at `(0, 20, 20)`, 45° down, 27.24 studs
  out, and slots 4, 9 and 2 put their centres at 1.146 / 1.146 / 1.095** — the row's three eggs.
  **Frame 2 onward is the solved 46.26 and everything is inside.** `(0, 20, 20)` is the CFrame Roblox
  hands a fresh `Camera`; `RenderStepped` does not fire until after the first frame is drawn, and the
  camera was only ever written from inside that loop. **A camera driven by a per-frame loop must also
  be posed once before the loop.** Fixed in both reveals — the single egg had the identical hole.
  After the fix, 181 samples across the full sway: **worst corner 0.900 x / 0.764 y, worst centre
  0.744 x / 0.613 y, all ten inside**, matching the previous session's modelled 0.900 / 0.764 to
  three decimals. The projection rewrite was right; it was simply never reached in time.

  **Probe technique that made this cheap:** the reveal is pure client theatre driven by one payload,
  so it needs no egg, no DNA and no purchase — arm a watcher in the **Client** datamodel, then
  `Remotes.Notify:FireClient` a synthetic `petBulk` built from ten real `GameConfig.Pets` defs from
  the **Server** datamodel. Four reveals were run this way in a few minutes. Sampling per frame is
  what found it: a probe that aggregates over the whole reveal reports "out of frame" and hides the
  fact that it is true for 16 milliseconds.

- **2026-08-13 (third session)** — **No code changed. The session was blocked on the MCP handshake,
  and the diagnosis is worth keeping because it is not the failure it looks like.** Studio was
  running, `StudioMCP.exe` was running, and the proxy reported itself healthy on
  `http://127.0.0.1:13469/health` — **`Studios: 1 / Proxies: 1 / Tools cached: 25`**. The bridge to
  Studio was up the whole time; what was missing was the `mcp__roblox-studio__*` tools on the
  *Claude* side, which are bound once at session start and cannot be attached mid-session.
  **So "the Studio MCP is not connected" is two different faults, and `/health` tells them apart:**
  a dead proxy shows `Studios: 0`, while this one shows a live Studio and a client that never got
  the tool list. The fix is on Kristina's side — reconnect MCP or restart Claude Code — not a
  Studio restart, and **not** re-opening the place, which would lose the unsaved session.

  Probing the proxy for a way in from Bash is a dead end worth not repeating: every path 404s
  except `/health`, and `/studio` and `/proxy` answer **400 on GET / 405 on POST**, i.e. they are
  WebSocket upgrade endpoints, not a JSON-RPC surface. There is no HTTP route that invokes a tool.

  **Staged and ready, so the next session's first move is one call:** the file server is up
  (`python -m http.server 8731`, repo root) and the push script is written with the before/after
  hashes baked in — Studio must still read `HatchReveal` **48,310 / 169269412** and `MainUI`
  **378,671 / 120848007**, and must come back **52,514 / 909702846** and **380,324 / 144286258**.
  It refuses to write on drift rather than overwriting blind. `git status` is clean.

- **2026-08-13 (second session)** — **Phase 11's last two open pieces of CODE are written and
  neither is measured: the Studio MCP is not connected this session, so nothing could be run.**
  `src/` is now ahead of Studio on two files — `HatchReveal.client.lua` and `MainUI.client.lua`.
  **Push both before anything else**, over the HTTP bridge, and verify byte-identity.

  **11.19 · the framing.** `frameCluster` was a closed form fitted to the cluster's bounding box at
  rest; it is now a projection — every corner of every figure, at nine yaw samples across the sway,
  asked "how far back must the camera be for me to land inside 90% of the half frame", and the
  distance is the largest answer. The horizontal half-angle comes off `vp.AbsoluteSize` instead of
  the authored `VP_ASPECT`, which survives as the fallback for the frame before layout has run, and
  the sway is one constant read by both the solve and the camera loop. Modelled worst corner **0.900
  x / 0.764 y** across the whole sway; the camera comes 3.9% closer, so the eggs are drawn *larger*.

  **The row's measured failure did not reproduce, and that has to be settled live.** The same
  projection against the OLD code puts the worst centre at 0.716 and the worst corner at 0.867 —
  inside. It picks out the same slots the probe named (4 and 9 tie on x; 2 leads on y if the focus
  is left at the origin), so both are looking at the same ring; the reported figures imply a camera
  **~29.7 studs** out where the code's formula gives **48.11**. The disagreement is about the lens,
  not the layout, and one read of the live `cam.CFrame` during a real bulk decides it. The rewrite
  holds either way.

  **11.32 · the Pets panel.** `refreshPetsPanel` now returns early when the panel is shut, and a
  `GetPropertyChangedSignal("Visible")` connection rebuilds it on open — fresher than the dirty flag
  the row specified, and hung on the property so that no fourth way in can open stale. Every write
  the function makes is parented inside `petsPanel`, which is what makes the skip safe. No new
  top-level local, so MainUI's register cap is untouched. The per-cell diff is still not built.

  **The `luanames` tripwire in this file said 9 and `src/SYNC.md` says 13.** Re-measured across all
  58 scripts: it is **13**, and unchanged by both edits above. The stale line has been corrected in
  the traps section.

- **2026-08-13** — **The push landed and the verification pass ran. Thirteen of the fourteen open
  rows are closed on measurement; 11.19 is the one that failed a check.** The five ahead-on-disk
  files went disk → Studio over the HTTP bridge and came back **byte-identical on the first
  attempt** (UITheme 62,024 / 1743064440; BossService 155,664 / 2118278806; PetService 44,412 /
  1476532768; HatchReveal 48,310 / 169269412; MainUI 378,671 / 120848007), and a full sweep of all
  **58 live scripts** now matches `src/` on every one — the `src/SYNC.md` invariant is restored.

  **11.19's failure is the only thing left to code in Phase 11:** the ten eggs are framed against
  the cluster's bounding box **at rest**, and nothing widens that solve for the ±15° camera rock,
  so three of the ten eggs put their CENTRES outside the viewport at the extremes of the sway
  (|ndc| 1.146 on x for slots 4 and 9, 1.095 on y for slot 2) and six put a corner out. Everything
  else in that row passes, including the part it was built for — a single hatch fired 1.5 s into a
  bulk takes the world path instead of seizing the screen, and is still delivered.

  **Six things this pass paid for, all reusable:**

  1. **Half the world is not in `workspace.Zones`.** `ALWAYS_LOADED` names are reparented into
     `workspace.WorldShell` at the end of the build, so a geometry scan of `Zones` alone reports
     every mound name, `TerraceTop` and `PoolRim` as **absent** — which reads as "the fix never
     landed" rather than as the wrong search. It cost an hour and a wrong conclusion. Scan
     `workspace`.
  2. **`RunService.RenderStepped` never fires for a connection made from `execute_luau`.** It
     connects without error and is simply never invoked; `Heartbeat` and `Stepped` both run at
     60 Hz. Any row whose check is written against RenderStepped needs rewording.
  3. **A frame-time claim needs an idle control on the same machine.** Max Heartbeat dt during a
     10x hatch was 0.1455 s — against 0.1299 s doing nothing with the same probe running. The
     absolute number measures Studio, not the feature; only the delta (~16 ms) is about the code.
  4. **`Lighting` already holds a `BlurEffect`.** A probe asserting "the count peaks at 1" reports
     a failure that is not there. Measure the delta.
  5. **`user_mouse_input`: use `mouseButtonClick`, never a bare `mouseButtonDown`.** A Down with no
     matching Up leaves the virtual input in `duplicate button state` — every later click is
     rejected, the tool call itself hangs past 120 s into the background, and the game stops
     receiving input for the rest of the session. Recovered by sending a lone `mouseButtonUp`.
  6. **The fresh-require trap held again**, verified rather than assumed: `require`ing
     `PlayerDataService` from `execute_luau` in the **Server** datamodel of a live Play session
     returns a module whose `Cache` is empty. Drive the real remotes from the Client instead.

  **What the measurements cost the owner's save**, all of it ordinary gameplay and none of it
  reversible: 3 duplicate `Cinder` pets released (11.17's confirm step), ~172 B DNA spent by
  **Auto Hatch** the moment the character walked into range of a Nebula podium with the pass on
  (19 Premium eggs in a few seconds — the feature working, but worth knowing before walking into a
  shop), and 33 further cheap hatches driving the bag from 19 to **69 of 100** pets.

- **2026-08-12 (session end)** — **`src/` IS AHEAD OF STUDIO ON FIVE FILES. Push before doing
  anything else.** Only `ZoneBuilder` is in sync (560,420 B, hash 1774987081, world rebuilt at
  `BUILD_VERSION` 128). Ahead on disk and NOT yet in Studio: `MainUI.client.lua` (349,206 →
  378,671), `HatchReveal.client.lua` (32,767 → 48,310), `UITheme.lua` (59,872 → 62,024),
  `BossService.lua` (154,024 → 155,664), `PetService.lua` (45,105 → 44,412). All five were
  compile-checked by `loadstring` over the HTTP bridge but never written into Studio, because a
  subagent held Studio and then the session hit its token limit. **This suspends `src/SYNC.md`'s
  "byte-identical" invariant until that push happens** — do not trust a hash sweep to mean Studio
  is right; `src/` is right, and the direction is disk → Studio.
  Rows 11.14–11.27 are all `[~]`: coded, committed, and none of them measured. **Nothing needs
  re-coding — the whole outstanding job is one verification pass.** Each row's own cell lists what
  to measure and its control case.

- **2026-08-12** — **11.12's owner block was removed by doing it, not by waiting for it.** Kristina
  granted browser access, so the three shard products were created on the Creator Dashboard from
  inside the session: `25 / 125 / 750 Evolution Shards` at 49 / 199 / 999 R$, ids **3707419817**,
  **3707425807**, **3707431292**, each with Managed Pricing **Disabled** so the dashboard charges
  exactly what `GameConfig` prints. Three rungs and not five, because a shard is spent 25 at a time
  on one machine and three price points already cover "one go", "an evening" and "stop thinking
  about it"; the amounts are the Diamond ladder x2.5 so the value curve keeps the shape a buyer
  already learned on the Diamond tiles.

  **The wiring had a hole the row did not mention**: `GetValuePerRobux` lists the grant fields it
  knows, so a new one missing from it makes its whole tier group silently ribbon-less — which a
  player reads as "no bonus", not as "not implemented". With `grantShards` added, value per Robux
  rises 0.5102 → 0.6281 → 0.7508 and the ribbons derive to +0% / +23% / BEST VALUE.

  **What still cannot be tested, and now we know exactly why.** `ProcessReceipt` is a Roblox
  **callback member**: it can be assigned but not read. So the live handler cannot be pulled out and
  invoked with a synthetic receipt, and `require` would hand back a fresh service whose cache is
  empty. The grant needs the same **one real purchase** that 1.7 / 2.11 / 3.8 have been waiting on,
  and closes with them. That is worth writing down — three sessions have now looked for a way round
  it.

- **2026-08-12** — **11.13 closed: the shops were not missing cards, they were missing headers.**
  The row asked for cards modelled on `ui_kits/evolution-lab/RobuxShopModal.jsx`, so the first thing
  checked was whether the game's cards already were — and they are: that reference is a cream panel
  with a thick outline and a hard shadow, which is what `UITheme`'s `applyShell` draws on every tile
  in all four panels. The fourth time a row's premise had to be tested before building what it asked
  for. What the four panels actually shared was a bare left-aligned TextLabel for a title and side
  margins of 14, 16, 18 and 24 depending on which day each was written.

  One new `UITheme.PanelHeader` — accent band, drawn icon, title, **subtitle** — carries all four.
  The subtitle is the part that earns the band: the Upgrades panel spends **two currencies** in two
  rows and nothing on it said which row was which; the Robux panel's "pick resets in 3h 04m" was
  being appended to its own *title* every second, so the panel's name changed length continuously
  and had to drop its icon to make room. New code went into `UITheme`, never MainUI — and removing
  three now-unused title locals took that file from **179 registers to 176**.

  **The captures found two things no measurement would have.** The Upgrades panel was 900 px wide
  for 624 px of content, so a third of the board was empty shell on either side — 656 now, with both
  rows on one 200 px tile width so they line up into a grid. And every value ribbon in the Robux
  grid hangs 6 px above its own card, which a ScrollingFrame clips at canvas zero: nine rows were
  fine and the two the player sees first were cut in half. **Measure and look; they answer different
  questions.** Measured: 245 labels, 0 clipped (the sweep found three pre-existing, including a
  level badge sized for its `"Lv 0"` placeholder while the refresh writes `"Lv 100/100"`); every
  child of all four panels at L16/R16; tab daylight 2.00 → **14.00**. And the Upgrades panel's close
  was traced on a real mouse click — `V/1.000 → V/0.968 → h/1.000`, a shrink while still visible,
  which the `Visible = false` it used to do cannot produce.

- **2026-08-12** — **11.11 closed: the diamond upgrades were priced for a game where diamonds had no
  gameplay source.** `baseCost = 5, costMult = 1.6` for "+10% permanent income per level, forever"
  dates from when every diamond came from a daily login, a playtime milestone or a Robux product
  whose id was still 0. 10.x made a kill the source and none of the three numbers moved.

  **The rate had to be measured before anything could be repriced**, and it was, by driving the real
  `AutoAttack` remote at the client's own 0.34 s cadence and reading the diamond balance off the real
  `DataUpdate`: **~260 an hour roaming, ~82 an hour parked** in the densest cluster waiting on
  respawns. The roaming run's own tier mix predicts 12.05 diamonds against `DiamondDropChance` and it
  paid 13, so the two agree and the number is not one lucky sample. Priced against 120/hour, near the
  bottom of the band: the OLD first level of Mega Income was **two and a half minutes** of play.

  New: 25 / 40 / 75 with multipliers 1.75 / 1.75 / 2.5. **The multiplier had to move as well as the
  base** — the effect is linear in the level while the price is geometric, so the multiplier is the
  only term that decides where the upgrade stops being worth buying; raising the base alone shifts
  the ladder sideways and leaves the tenth level at 12x the first. No cap was added anywhere: a cap
  says "you are finished", a price says "not yet". Stage Mastery was deliberately left alone — its
  ceiling is the climb, not the wallet.

  **Two probe runs were thrown away rather than reported.** A walking navigator spent 158 s of 173
  chasing creatures it could not reach, because "nearest creature" kept selecting a raised one
  standing on a shelf. A probe that measures its own pathfinding is not a measurement of the game —
  the same rule as the four probes in the Phase 10 notes. What replaced it needed no navigation at
  all: park in the densest cluster and let the respawn timers do the work, which is also what
  auto-attack farming actually looks like.

  **And measuring it found 11.31 (E4), now fixed in the same session:** 200,000 rolls per tier
  returned Apex **0.0000**. Both drop tables are keyed by tier name, and 11.6 added a fifth tier
  without adding a row to either — so the creature behind the three-rebirth gate paid no diamonds
  and no shards, less than the Critter at the bottom of its own cliff. That is 11.30 in a different
  table, and the fix is 11.30's lesson applied in the only direction available: **GameConfig cannot
  read `CreatureService.TIERS`**, because it is required by that file, so CreatureService hands its
  own tier lists to `GameConfig.AssertTierCoverage` at load and that warns by table and tier name.
  A warn and not an error — the thing being guarded against is silence, not a crash. Proven with a
  control: the real lists warn nothing, an invented sixth tier names both tables. The credit path
  itself was proven on 169 real raised kills paying +40 diamonds against 38.6 expected and +27
  shards against 27.17. **One real Apex kill is still owed** and needs 3 rebirths — the same wall as
  11.6's layer-2 payout and 11.1.

- **2026-08-12 (end of session)** — **11.7 and 11.8 closed, each having found a hardcoded value
  that would have shipped a lie.** Both rows were about adding or repricing content, and in both the
  content was the easy half; what took the time was finding the place that had a copy of the number
  typed into it.

  **11.7.** `FuseRequirement` 4 → 3, so Celestial costs 27 copies against a 100-pet cap instead of
  64 — the comment over `MaxOwnedPets` has said "27 copies at the 3-per-fuse requirement" since
  11.10, so this was the constant catching up with a decision already made. The Catalyst turned out
  to be **half in the fusion panel already** — every pet row carries a purchase button for it — and
  that button printed a literal `"R$ 99"`, so repricing to 49 alone would have advertised one number
  and charged another. Only the x3 bundle got a card of its own. Boss Revive is **`delisted`, not
  deleted**: a deleted row means a retried receipt resolves to nothing forever, so the row survives
  and now grants 10 diamonds — exactly what `Diamonds_1` sells for the same 49 R$.

  **11.8.** A fourth potion kind, twelve bottles from four kinds x three sizes with no bottle
  written by hand. Then the HUD timer strip turned out to be `local KINDS = { "dna", "xp", "luck" }`,
  typed out (**11.30**), so the new kind reached the config, the shop, the panel, the save and the
  server and had no countdown anywhere. **A `LABEL[kind] or kind` fallback is a tell: a default that
  quietly prints a lowercase key is a list that expects to be incomplete.**

  **Two probe runs lied before the code did, again, and both times the lie looked like a bug in the
  new feature.** A regen measurement came back at 1.0%/sec against a target of 5%, and the expiry
  undo appeared not to fire — both because the *live* loop reads the *live*
  `PlayerDataService.Cache` and the fixture was in a freshly-required one. The 1% was **Roblox's own
  default humanoid regeneration**, which is exactly 1% of MaxHealth per second and therefore looks
  precisely like a feature working at the wrong strength. The fix was to export the loop
  (`PotionService.DriveHealthPotions`) so the *real* one can be started in the probe's context
  against the fixture, rather than reimplementing its body in the probe where two copies can agree
  with each other while the shipped one is wrong.

  **Also: `require` in the EDIT datamodel is CACHED across `execute_luau` calls.** A push followed
  immediately by `require(GameConfig)` reported **9 potions** after the fourth kind was already in
  the file. Nothing was wrong — the module had been required earlier in the same Edit session and
  the old table came back. Verify config changes from a **fresh Play VM**, not from Edit.

  **AND 11.7'S TWO OWNER ITEMS WERE DONE FROM HERE, ON THE CREATOR DASHBOARD.** Kristina said to
  go ahead, so the three products were edited directly in the browser and read back off the
  Developer Products list afterwards: Rainbow Catalyst (`3702254553`) **99 → 49**, Catalyst x3
  (`3702254989`) **249 → 129**, Boss Revive (`3702254100`) **→ Offsale**. Nothing else on the
  seventeen-product list was touched. **A developer product does carry an `Item for sale` toggle**,
  which is worth writing down because the assumption behind 11.7's design was that only passes do —
  the withdrawal is a real offsale now, not merely a product with no UI pointing at it. The
  `delisted` row and its diamond conversion stay exactly as they are: an offsale product still
  retries receipts that were already in flight, which is the case that row exists for.

  **State at end of session: `main` and `origin/main` level at the 11.8 commit, all 51 scripts in
  Studio byte-identical to `src/`, world at `BUILD_VERSION` 127.** The next open row in order is
  **11.11** (diamond upgrades are too cheap), then the C rows 11.13–11.20, then the D rows
  11.21–11.27. Everything owed rather than open is listed on the rows themselves: 11.1 and 11.6 both
  want a real rebirth, 11.4 wants R2/R4 measured, 11.9 wants one real boss fight.

- **2026-08-12 (later still)** — **11.6 built and verified as far as one rebirth allows, and it
  cost three of its own bugs plus two rows.** The terraces now carry a rebirth ladder: the existing
  Brutes and Elites are layer 1 behind one rebirth, and a new **Apex** tier stands on the highest
  shelf of every zone behind three, dropping one species per zone that no egg contains.

  **The row's premise had to be checked against the code three times — the fifth, sixth and seventh
  time that has paid off in this project.** `GrantPetFromDrop` could not "reuse `rollAndInsert`" as
  written, because that function bakes in an egg's `luckBonus` and 11.5's *Egg Luck* upgrade, and a
  kill is not a hatch; what the row actually wanted — one pet shape, one cap — is held by a new
  `insertPet` instead. "A new creep tier per rebirth" is one tier, which is what the row's own two
  layers describe. And `raised` became a layer number rather than growing a sibling parameter.

  **A new creature tier is 11.9 waiting to happen, and the fix is algebra, not vigilance.** A creep
  tougher than its zone's boss is the exact defect 11.9 existed to remove. Rather than trust a
  chosen number, `ApexBaseHealth = math.min(350, BossEliteFloor * EliteBaseHealth)` — which is
  precisely the condition for a farmed Apex to stay inside the boss floor, with the generation cap
  and `mobHealthMult` cancelling from both sides so it cannot rot when either is tuned. Measured
  across 20 zones: worst boss / farmed Apex **1.00**, and **no boss's health moved by a point**.
  Pricing the floor on the Apex instead was tried first and reverted — it would have raised every
  floor-bound boss (zones 2–17) by 25%, a balance change nobody asked for.

  **`local` ORDER IS A SILENT BUG IN BOTH DIRECTIONS, and it was written twice in one session.** A
  `local` declared below a function is not an upvalue of it — it resolves as a nil GLOBAL, and the
  throw lands at runtime, at the rare moment the new path first runs. `MAX_PETS` sat below the new
  drop function in PetService, and the lock-notice table sat below `onHit` in CreatureService.
  Both were caught by reading, not by the compiler, which is the point: **it compiles either way.**

  **A cache is the wrong shape for anything at the streaming boundary.** The plate paint was modelled
  on `RebirthShrineClient`, which caches each part's original look — correct for four shrines that
  never move, wrong for a creature whose parts leave and come back. The cache missed, the rebuild
  recorded the *already painted* look as the original, and one Apex's plate ended up reading its own
  lock line **34 times over**; the same bug would have restored the body to grey on unlock. Rewritten
  with nothing remembered off to the side: the pristine name is published by the server
  (`PlateName`) and each part carries its own original colour in an attribute. A part that streams
  out and back is a *new* part with its true colour and no attribute — exactly the right state. The
  guard is per part, not per model, or parts that stream in behind a painted model stay bright.

  **"Quiet presentation" was not the same flag as "no egg".** The drop first reused the hatch payload
  with `auto = true`, which does not mean quiet — it means *play the egg sequence*, so HatchReveal
  animated an egg on a podium in the shop while the player stood on a terrace hundreds of studs away.
  Measured: zero visible feedback. It has its own `petDrop` kind now, drawn on the player.

  **Two probes lied before the code did**, both worth remembering. A drop-rate run reported 0.25% on
  both layers because the fixture's bag filled to 100 pets and the cap correctly refused the rest —
  the *test* accumulated, not the game. And the first payout reading came back at 0.60x against a
  target of 3.00x, which is 3/5: the valley control had rolled a 5x crit. Both were arithmetic on the
  probe, not defects, and both looked exactly like defects. **Sample more than once before believing
  a ratio.**

- **2026-08-12 (later)** — **11.2 closed and 11.28 opened and closed with it.** Kristina moved
  Studio onto the published place, so `GameId` is right and the server boots — but the sweep
  immediately earned its keep again. 50 of 51 scripts were byte-identical to `src/`; **MainUI was
  99 bytes and one line short**, matching neither `src/` nor HEAD. Reverting a single candidate hunk
  out of the `src/` copy reproduced Studio's hash exactly, which proves what was missing rather than
  merely that something was: the functional 11.5 change had survived and **one comment hunk had
  not**. That loss happened *after* a byte-verified push, across the publish-and-reopen. **Verify
  byte identity again after any publish or reopen, not only after a push.**

  **A one-shot guard is not a wall.** 11.2's Daily row had never drawn in two sessions because
  `LastRewardClaim` is always today's and `maybeWelcomeBack` fires only on the payload where
  `currentData == nil`. Both halves turned out to be reachable without touching the save: the
  readiness test is client-side arithmetic on the payload, and **destroying the HUD and parenting a
  fresh clone of MainUI into `PlayerScripts` resets every first-payload flag in the file**. With a
  0.05 s payload loop running on the server, the first thing the new HUD sees is always the probe's.
  That combination — synthetic payload plus a re-run of the client script — reaches any
  join-only branch in the game, and it is cheaper and safer than a save edit. (A DataStore read was
  attempted first and refused by the harness classifier; it turned out not to be needed.)

  **Drawing the branch that had never been drawn is what found the bug.** With a missed day the card
  read `Day 1 is ready` over `🔥 4 day streak — claim to keep it going`. The head was right and the
  note was lying, one line apart, and the lie is the exact one the comment above the head was written
  to prevent. Recorded as **11.28** and fixed. **When a row says a branch has never run, the row is
  not finished when the branch finally runs — it is finished when somebody reads what it printed.**

- **2026-08-12** — **11.5 closed: the shop's Luck upgrade now pays eggs and nothing else.** Like
  last session the code was already in the working tree, uncommitted and unverified, so this was a
  measuring session. The sweep again proved the *direction* and not just the difference: 47 of 51
  live scripts were byte-identical to `src/`, and the four that were not were exactly the four
  carrying the uncommitted work — each matching **HEAD** byte for byte, so Studio sat on the last
  commit and the push could only add.

  **The split's real argument is legibility, and it is worth keeping.** One `Upgrades.Luck` purchase
  used to move crit DNA, the mutation roll, the egg roll, the mystery potion and the wheel; the card
  advertised the two of those it moved least. That also capped how strong it could ever be — any
  number big enough to be felt on an egg was a crit-chance clamp on the DNA click. Split out, it
  went +2 → +5 a level in the same breath.

  **A negative result needs a control or it is just a dead function.** "Crit and mutation do not
  move" was proven by running 60k draws of `RollMutation`, `RollMysteryPotion` and `RollSpin` at
  upgrade level 0 and 25 (identical), *and* by running the same three at a forced luck of 125, where
  every one of them moves hard — mutation Common 61.1 → 44.5%, Secret 0.25 → 0.76%. Same rule as the
  four probes in Phase 10.

  **The row did not know about the cap, and the cap is the interesting number.**
  `GetUpgradeMaxLevel` is 5 levels per unlocked zone, so +5/level is +25 at one zone and **+500** at
  twenty. That sounds alarming and is not: the egg curve is strongly damped, so on the endgame egg
  (which carries +272 of its own) the whole 100 levels move Legendary from 2.1% to **2.5%**. The
  raise lands almost entirely on new players — Forest basic goes Common 62.8 → 50.0% at ten levels —
  which is where a 40-DNA upgrade should be felt. **Check a stat's own cap before judging a per-level
  number; the cap is where the number is actually spent.**

  **Note for existing saves:** anyone who already owns Luck levels loses `2 × level` points of crit
  and mutation luck. That is the row's intent, not a regression, and no save needs repairing.

  ⚠️ **`GameId` was 0 again — the Studio session is on the unassociated local `Evolution-lab.rbxl`,
  not the published place**, so `PlayerDataService` threw at module scope, `ServerMain` died at line
  7 and no gameplay could be exercised at all. **The workaround retires that wall for every
  client-side row**: `ReplicatedStorage.Remotes.DataUpdate` exists in the place file even when the
  server is dead, so firing a synthetic save payload at it from the Server datamodel drives the
  **real** MainUI through its real refresh path — which is how the egg panel above was measured with
  only one field differing between two runs. Cleaner than a real save, in fact: no purchase, no
  mutation, and a perfect A/B. Every C-row (11.13–11.20) is verifiable this way.

- **2026-08-11 (later still)** — **11.3 closed, 11.2 half closed, and both were already written
  before this session began** — coded, uncommitted and unverified in the working tree. The session
  was therefore verification, not construction, and two of the three findings came out of measuring
  rather than out of reading.

  **The sweep proved the direction, not just the difference.** 49 of 51 live scripts were
  byte-identical to `src/`; the two that were not were exactly the two files carrying the
  uncommitted work, and both matched **HEAD** byte for byte — so Studio sat on the last commit,
  `src/` was ahead by exactly the working-tree diff, and the push could not overwrite anything. A
  hash comparison alone would only have said "different".

  **A row's own numbers are worth re-measuring even when they look precise.** 11.3 predicted a
  17.2 px overlap and the live HUD gave **17.20**. The same row predicted "~25 of ~30 action
  buttons" and the real figure was **69** — so a control was run before letting the shrink touch
  them, and it showed all 69 are lone action buttons inside their own row cards, with `EggPanel`
  the only parent holding hand-positioned siblings. That is the parent the row converts.

  **The first fix passed the row's own criterion and was still wrong, which reopened it.** With no
  overlap the two buttons were 12 px apart and looked like one merged bar: `styleCard`'s `UIStroke`
  is 5 px and draws *outside* its frame, so 12 px of frame gap is **2 px** of daylight. **A gap of N
  between two stroked siblings shows as N − 2×thickness.** Padding 24 gives 14. The same shape was
  then found sitting in `makeTab` at `MainUI:4192` and recorded on 11.13, which owns that panel.

  **11.2's Season half is proven in both directions and its Daily half has never drawn.** The card
  opened by itself on a fresh join reading `3 to claim` with the tile badge agreeing at `3`;
  Kristina claimed all three mid-session and the next join drew nothing with the badge at `0` — a
  zero recomputed independently from the raw save (level 2 fully claimed, the two dailies now
  claimed, `w_creatures` 321 of 500). The Daily row hid on every run because `LastRewardClaim` was
  today's, which a control confirmed is correct behaviour rather than a silent failure. It needs the
  next rollover or a temporary rewind of that one field, so the row stays `[~]`.

  Studio was stuck in Play for the first half of the session — five `start_stop_play(false)` calls
  answered `Game Stopped` while the state stayed Play — which cost nothing only because the static
  checks (register cap 173 → 173, every free symbol in the new block resolving top-level and
  earlier, the badge path, the `LoadingScreen` name) and the "before" measurements were all
  reachable from the `Client` datamodel without Edit.

  **Count top-level registers as VARIABLES, not as `local` lines.** A line count says 173 and is
  stable for the wrong reason — `local a, b` is one line and two registers. The real figure is
  **179 → 179** across this work, unchanged because everything went inside a
  `;(function() … end)()`, and 179 is the number the roadmap has been carrying all along.

- **2026-08-11 (later)** — **Phase 11 opened from the BETA V0.2 test pass: 27 rows, and the first
  four are in.** 11.10 (pet cap 30 → 100, the missing `data` argument in the panel's sort, and the
  "5/3" title) is closed and verified live. 11.1, 11.4 and 11.9 are coded, pushed and verified as far
  as this environment allows.

  **Two of the four findings were not what the plan said they were, and the difference mattered.**

  *The rebirth bug was a guard firing on the wrong path.* The save was always correct — zones really
  did lock. `OnReturnHome` called `ReturnToCurrentZone`, which returns early on `"Forest"` because the
  game's one `SpawnLocation` is already there, and rebirth had set `CurrentZone = "Forest"` *before*
  asking. Reproduced live before fixing it: from Quantum Realm at X = 20,900 the old call moved the
  body **not at all**; the new `SendToZoneSpawn` landed it at X = 0.0.

  *The boss balance finding was worse than reported, and the plan's analysis of it was stale.* The
  plan described hand-typed boss health; 10.x had already replaced that with a derivation. The
  derivation was priced against the **Brute** (70 base, 14 blows) as "about four Brutes" — but the
  **Elite** is 280 base, i.e. 56 blows, so a boss was one Elite, and a farmed spawn point brings an
  Elite back at up to double, i.e. **112 blows against its own zone's 60**. Measured across all
  twenty zones: boss/Elite 0.84–1.07 fresh and **0.42–0.54 farmed**. Eighteen of twenty bosses had
  less health than a creep standing a hundred studs away. `BossTargetHits` 60 → 150 plus a floor tied
  to the Elite; `EliteBaseHealth` and the generation cap moved into `GameConfig` so `CreatureService`
  reads them back instead of keeping the private copy that let the two curves drift. Every boss
  gained **at least 2.50x**, and the worst boss/farmed-Elite ratio went 0.42 → **1.25**.

  The skin work found four separate causes and one absence: the whole skin path had a single `warn`
  in it, and five silent `return`s produced exactly the "stock avatar, no parts, no errors" signature
  recorded in `src/STATUS.md`. The race (R1) is proven live in both directions and the duplicated
  transparency attribute (R3) is gone from the running character.

  Eight files pushed to Studio over the localhost bridge, every one byte-identical afterwards;
  Studio was byte-identical to git HEAD before the push, so nothing of anyone else's was overwritten.
  59 scripts compile, MainUI still **173** top-level locals, `luastruct` clean.

- **2026-08-11** — **The place is published, and `GameId = 0` was the whole bug report.** Three
  symptoms came in from Play — spawning as the player's own Roblox avatar instead of Cell 1, a
  stale "Use the DNA Machine" tip, and a kick a few seconds in. They were **two causes, neither a
  code defect.**
  (a) The place open in Studio had **no place association at all** (`game.GameId = 0`,
  `game.PlaceId = 0`), so every DataStore call returned *"You must publish this place to the web"*.
  That is fatal earlier than it looks: `PlayerDataService` calls `GetDataStore` at module scope, so
  the **`require` itself threw and `ServerMain` crashed at line 7** — no remotes were ever created
  (`RarityBeam` infinite yield, `UseBossRevive` and `DeletePets` "never appeared"), nothing was
  dressed, and the HUD read zero because there was no server. The visible kick was the *only*
  correct part of it: `Load` distinguishes "never played" from "could not read" and refuses to
  start a session on a blank save. **General rule: a service that touches a DataStore at module
  scope turns a configuration problem into a total boot failure — the failure surface is the whole
  server, not the save.**
  (b) The tip was simply **stale code**: the `.rbxl` on disk was saved 08-10 23:32 while the
  previous session ran to 04:31, so the place was missing 16 files' worth of work that only existed
  in `src/`. Proof without diffing: Studio still held `MachineService` (deleted in `src/`) and had
  no `FirstEvolveXp` anywhere.
  Fixed by publishing to **Evolution Lab BETA V0.2** (universe `10675543038`, place
  `102217824272435`) — verified live: DataStore reads succeed and the owner's save loads
  (`Stage 1`, `DNA 6844`, `Worn = cell_amber`). Then all **14 changed files were pushed `src/` →
  Studio** over the localhost bridge and `MachineService` was moved to `ServerStorage._PushBackup`
  (moved, not deleted; the only remaining mention of it anywhere is one comment in `MainUI`). A
  full sweep now reports **48/49 scripts byte-identical between Studio and `src/`, 0 differing.**
  1.7 / 2.11 / 3.8 move to `[~]`: all **26 ids exist and resolve** on the published universe, but
  each row's own verification is a *purchase*, and none has been made — that is a new owner row.
  **Still open and measured today:** the `[Streaming]` warns still fire, so 0.4 is untouched; and
  the skin is not applied to the live character even on a save that names one
  (`Worn = cell_amber`, yet the body is a stock R15 avatar with zero costume parts and no error in
  the console) — under investigation, retest pending.
- **2026-08-10** — **7.4 decided, and the branch merged into `main`.** The owner confirmed the
  Prism Festival's authored window **is** the launch weekend — 4–7 September 2026, Friday noon to
  Monday noon UTC — so the row closes with no edit. That is the point of writing a window as
  arithmetic on a timestamp rather than storing it: nothing had to be migrated for the decision to
  become true. **7.4 was the last outstanding item that was not an id, an upload or a published
  place**; everything still open now needs the Roblox dashboard or two real clients.
  `sync/place-mirror-and-monetization` fast-forwarded into `main` (39 commits, `main` had not moved
  since the place-file backup, so there was nothing to reconcile). **Not pushed** — that is an
  outward-facing step and is the owner's to take.

- **2026-08-10** — **Phase 9's last four rows closed, and the tree swept clean.** 9.6 (the climb
  routes worked, they just could not be seen — `ZoneBuilder`), 9.7 and 9.8 (closed by 10.17 and
  10.19 respectively, which had already fixed exactly what they asked for) and 9.10 (the guide named
  the verb but never the noun — `FirstJoin.client`) all went `[x]`. **With that there is no `[ ]` row
  left anywhere in the roadmap that is not owner-blocked**, and 0.5 was stale bookkeeping: the
  branch has 38 commits carrying `src/` and this file, with no place binary in the history.
  **A hash sweep of all 52 live scripts came back byte-identical between Studio and `src/`** — the
  first fully clean sweep, and the check that keeps [[evolution-lab-studio-work-is-volatile]] from
  costing another session's work. Two things it taught:
  **`script_grep` cannot be trusted as a presence check.** It reported *no matches* for
  `PROMPT_STACK` in a datamodel whose `PetService.Source` contains it at byte 27,835 — it appears to
  read a stale index rather than the live source. `d.Source:find(needle, 1, true)` over the
  descendants is the check that answers the question actually asked; a grep miss is not evidence of
  absence. (Fifth entry in this file's running list of probes that answered a different question.)
  **The egg podium's prompt overlap is fixed and was the one uncommitted thing on disk.** Two
  ProximityPrompts on one part draw at one point: everything that made the x10 clone faithful — same
  parent, same anchor, same default `UIOffset` of `(0,0)` — also landed it exactly on top of the
  original. Neither prompt was broken; they were invisible to each other. `PROMPT_STACK = 44` pushes
  the single up and the bulk down by the same amount, so the pair stays centred on the point the
  lone prompt used to occupy (the podium and the egg's billboard were both composed around it) and a
  flipped sign costs nothing but reading order. **44 is measured, not chosen:** the default prompt UI
  turns `UIOffset` into `SizeOffset = UIOffset / Size` and builds a **72 px** card, so the value is
  HALF the separation — 34 left the two cards overlapping by 4 px, which looks exactly like the bug
  it was meant to fix. Verified live at 60/60 podiums, 16 px of gap. Distance does not enter into it:
  `SizeOffset` is a fraction of the same size that shrinks with range, so the gap stays proportional.
  **0.4 re-confirmed genuinely owner-only, not merely untried.** `StreamingMinRadius` is not a valid
  member of `Workspace` from a script in this Studio version — it cannot even be *read*, let alone
  set — and the `[Streaming]` warn fired twice on this session's boot. The Properties panel is the
  only route.

- **2026-08-10** — **10.18 + 10.19 close Phase 10's non-owner work.**
  **10.18 was a vocabulary problem, not a styling one.** The HUD spoke in **ten corner radii** and
  **eight stroke widths** — 14 and 16 and 12 and 20 and 10 and 22 px, each whatever the person
  writing that panel typed. Ten words that differ by two pixels is not a vocabulary; the eye cannot
  learn it. `UITheme.Radius` names four steps by what they are FOR (Pill / Tile / Card / Chip) and
  `UITheme.Stroke` three weights. **Snapped rather than enforced**: every radius and ink stroke
  entering the theme rounds to the nearest step, so the system becomes true without touching ~300
  call sites — a caller asking for 14 gets Card and looks identical. Two exceptions left alone: a
  radius far above the scale (a 40 px panel corner is a decision) and `outlineText`, which is type
  weight rather than shell shape. Routed through **both** funnels, because `applyShell` and
  MainUI's `styleCard` build the same object by two routes and snapping one would be a new way for
  them to diverge. Result: radii 10 → 5, ink widths 7 → 4.
  **The "readable text" half needed nothing, and the probe said otherwise twice.** A first count
  reported **86 runs at 8 px including the Evolve button** — which would have been a serious defect.
  They are the ORIGINAL `TextButton` strings, transparent because `styleButton` mirrors them into a
  `Label` proxy that draws above the gloss. Counting only text that is visible *and* on an open
  panel: 20 runs, all 16–32 px, none below 11. **Fixing the first number would have been fixing text
  nobody can see** — the fourth time this session a probe answered a different question than the one
  asked, and the pattern is always the same: a result that looks like a pass needs a control.
  **10.19's statue is cast from the real player** and the interesting part is the ORDER, which is
  silent when wrong in both directions. A model from `CreateHumanoidModelFromUserId` is held
  together by Motor6Ds that have not resolved yet: anchor before they settle and every limb freezes
  where it was authored (measured — a 21-stud bounding box around a 2.5-stud torso, a hand 10.8
  studs off centre, and no later `PivotTo` can gather them because anchored parts do not follow a
  joint). Anchor too late and the model is parented, unanchored and in the workspace for several
  frames, so gravity acts during the careful seating and it lands **13.6 studs underground**. The
  order that works is parent → let the joints settle → anchor → scale → seat → recolour.
  Two smaller rules it paid for: capture the old model **before** parenting the new one, because
  both are called `TopStatue` for the moment they coexist and `FindFirstChild` can hand you the new
  one and leave the old standing inside it forever; and the figure is **bronze on a cream plinth**,
  because the zone-statue rule ("pale stone, never tinted to the biome") inverts here — a pale
  figure on a pale base is the same disappearing act in miniature. **An object contrasts with what
  it stands on, not with the field it is in** — the third time this session that exact rule has
  decided a colour, after the village trim and the path verge.

- **2026-08-10** — **10.13: the collision audit found that the collisions were mostly right.** The
  row was written from a grep — 418 `CanCollide = false` sites — and a grep cannot tell a bug from a
  decision. Checked against the *running engine* instead, with ray and box queries, almost every one
  of them turns out to be defensible: the drawn cliff faces and rubble sit against `CliffJut`,
  `CliffBlock` and `TerraceTop`, which are solid, so the rock is scenery on a collision hull, which
  is the right way round; the `EggShell` is intangible for a reason already written in the source (a
  Block wearing a sphere mesh collides as its BOX, whose corners stick out at head height beside the
  podium); mesh props already carry a per-spec `collide` flag with canopies, boulders and structures
  solid and flora not; and tufts, flowers, mushrooms, coins and waterfall spray are correctly
  intangible.
  **The street fence is the one I nearly "fixed".** 434 mesh segments line the walk and none of them
  collides, which looks exactly like the reported bug — until you read the line above it: the fence
  dresses the street rather than penning the player into it. Making it solid would have turned the
  main road into a 48-stud corridor. Left alone.
  What was genuinely wrong is the rocks: a `GroundRock` is a 12-stud boulder standing on open ground
  with nothing behind it. Fixed with a short explicit list in `newPart`, the same shape of
  centralisation the shadow rule uses — but keyed on the NAME, because **solidity is a property of
  what a thing is, not of how big it is**: a bush and a boulder measure the same and only one should
  stop you. Verified first that none of the newly-solid props sits on the route.
  **The probe was wrong twice before it was right, and that is the reusable part.** Driving a real
  character into a rock measured "stopped outside it" — from a character that had not moved at all.
  A control walk over open ground measured 0 studs too, which is what exposed it: `Humanoid:Move`
  and `MoveTo` are both overridden from this context, and a raw `CFrame` write is pulled back to
  spawn by the server. **Always run the control case**; without it the first probe would have been
  read as a pass. The answer was to stop simulating a player and ask physics directly —
  `workspace:Blockcast` sweeping a player-sized box needs no character, no control module and no
  server cooperation.

- **2026-08-10** — **10.20: the icons were flat, and the set had thirty holes in it.** 9.9 built the
  asset layer and drew 44 icons; they were competent FLAT art — a few solid shapes inside a thin
  contour — which is the generic flat-icon look and not what this game looks like. Every other
  surface in Evolution Lab is a painted toy with a light side, a shadow side and a wet highlight.
  The icons alone were not, and next to a HUD tile they read as stickers on a toy.
  **The fix is a pipeline, not 44 edits.** `tools/iconkit.py` runs five passes over the *finished*
  colour layer, so it applies to every icon — including ones drawn next year — without a single
  icon body knowing it exists: a volume gradient down the icon's own bounding box, a light rim band
  inside the top edge, a dark band inside the bottom, a soft gloss, and one thicker ink contour.
  **The numbers are taken from `UITheme`, not invented**: the gradient is `gradientFor`'s three
  stops and the gloss is `addGloss`'s 0.28, so an icon and the button under it are lit by one
  decision. That duplication is deliberate and is cheaper than teaching Lua to draw PNGs.
  **Ink had to be protected from all of it.** Passes 1–4 skip pixels near INK, softly, by distance —
  lightening the top half of a deliberate black line turns a drawn mouth or facet into a grey
  smudge. That one guard is the difference between "shaded icon" and "shaded icon with mud in it".
  **A coverage audit of the whole interface found 30 emoji still falling back to a platform glyph.**
  Seventeen were zones, which is the biggest hole possible here: the same drawing is used on the
  zone row, the unlock toast, the boss bar **and** `ZoneTransition`'s full-screen card at 190×190,
  where everything else in the set is read at forty pixels. The other thirteen were chrome, and
  several cost a table row and no art at all — a bare `✔` with no variation selector, a second tick
  glyph `✅`, a dagger where the rest of the game uses crossed swords. The audit also caught a real
  bug: **`CodesService` printed shards with a crystal ball**, which is the Mystery Potion shop's
  mark, so a code that paid shards named something the game does not have.
  **Eight icons had to be drawn twice, and the failures are the reusable part** — each is recorded
  in its own body's comment. `blackhole` was a hat (a tilted ring-plus-ball is a brim and a crown).
  `ocean` took four passes and taught the general rule: **a polygon whose return path runs near its
  outgoing path is a BAND, and a band reads as a rope or a tap however you bend it** — rebuilt from
  overlapping solid masses, which is free here because the silhouette is a union of the whole layer.
  `absolute` was a sailboat, and no adjustment could have fixed it: plinth = hull, triangle = sail,
  centre ridge = mast, so the read came from the *arrangement* and two of the three had to go.
  `bag` was a cake — **a light horizontal band across the top third of anything turns it into
  furniture**, and the handle *is* the silhouette of a bag, so nothing may be drawn in front of it.
  `speed` was a fish: twice as wide as tall, tapering to a point, fin on the back. Proportion, not
  detail. `handshake` was a boomerang (both arms rising into a V), then a bone (arms as thick as the
  clasp). And `egg` had a face, which produced the sharpest rule of the lot: **a face is not a
  decoration you add to an object, it REPLACES the object.** Two dark discs in a pale oval are read
  as eyes before anything else in the drawing is read at all, and the speckles were then recruited
  into cheeks. `pet` and `boss` are meant to be faces; an egg is a thing you hatch.
  **Process notes worth keeping.** Six agents drew in parallel, one file each, and all six were
  killed mid-run by a session limit — but every file had already been written, so nothing was lost
  and the work resumed by rendering what was on disk. Splitting the bodies out of the orchestrator
  is what made that survivable, and `--sheet` takes a path for the same reason: the PNGs several
  renders write are disjoint, but a shared contact sheet is the one file they would race on.
  **And judge icons as a family, not one at a time** — the contact sheet is where a mismatched
  weight or light direction shows, and it is invisible when you open them individually.

- **2026-08-10** — **10.17: the boost strip was not too tall, it was in the wrong lane.** 9.7 had
  measured the fault as 297 px of content in a 250 px frame with clipping off, and that framing is
  what made it look like a sizing problem. It is two problems, and the bigger one is horizontal: the
  strip and the left tile column both start at **x = 20**, the strip is bottom-aligned so its
  overflow grows *upward*, and upward is where the buttons are. Seen live at 1546x793 with every
  boost running, the gold pass card did not merely clip the Rebirth tile — it **covered it whole**,
  and Rebirth is the only way into that panel. No amount of shrinking cards fixes a strip that is
  standing on top of a button.
  So the strip moved **beside** the column instead, and the x is read from the tile's own live
  `AbsoluteSize`. That last detail is the real lesson: the responsive pass at the bottom of MainUI
  shrinks the tiles from 82 px to as little as 40 on a short viewport, so a hard-coded 82 would have
  restored the overlap on precisely the screens that were already worst off. **Ask the object, do not
  recompute what another pass already decided.**
  The height is now a budget rather than a constant — bottom edge up to `TOP_CLEAR`, the same 121 the
  tile columns respect — and it is computed in **authored offsets off `ViewportSize`, never from
  `AbsolutePosition`**, which in this ScreenGui reports 58 px up from where offsets are measured.
  When the content still does not fit, whole cards are hidden **lowest urgency first**: passes (a
  pass is permanent, it has nothing to miss), then the event (server-wide and announced elsewhere),
  then potions with the most time left, so the last card standing is always the one about to expire.
  **Clipping was the obvious alternative and is worse** — a card sliced in half reads as a broken
  HUD, and the slice would fall on the stroke `styleCard` draws *outside* the frame.
  Verified at exactly 1280x720 (the row's own check): four cards, none dropped, nothing over the
  tile, and `GetGuiObjectsAtPosition` at the tile's centre returns only the tile's own children. Then
  verified at a 345 px viewport, where the drop order is visible doing its job: passes and event
  gone, and the single card kept is Luck at 2:35 against DNA at 30:47 and XP at 10:23.
  Two things worth reusing beyond this row. **Injecting a payload is how you reach a state the save
  cannot produce** — nine owned passes and three running potions, pushed at 0.15 s so the probe wins
  the race against the real 3 s service push (6.4's technique, unchanged). And **resizing the Studio
  window is how you test a responsive layout**: `MoveWindow` to a chosen height, measure, restore.
  A viewport is not something to reason about from a spreadsheet when it can be produced.

- **2026-08-10** — **10.14: the mountain creatures were never missing, they were lying in the
  valley — and an absolute altitude had been hiding inside a relative offset since the meshes
  landed.** `meshRig` computes where a generated figure's torso sits relative to the rig's origin,
  and that offset is applied by the idle driver as `origin * offset`. The lift was written
  `footDrop - ctx.origin.Position.Y + MESH_GROUND_CLEAR`, so `origin.Y` appears twice with opposite
  signs and **cancels**: the six mesh segments were pinned to absolute `y = 0.5` regardless of where
  the creature stood. For as long as every creature stood on a valley floor at y = 0 that is
  indistinguishable from correct, which is why it survived the whole mesh rollout. 9.4 then put four
  Elites and six Brutes per zone on the terraces, 30 to 107 studs up, and the invisible `Body` (which
  carries the health plate) and the `GroundRing` (drawn at `floorY + 0.35`) went up with them while
  the visible creature stayed on the ground: **a health bar and a gold disc on a cliff with nothing
  under them.** Exactly the report.
  The fix threads `floorY` — already computed by `spawnCreature`, already stored on the rig for the
  roam picker — into `buildRig`'s context, and subtracts the body's height **above its own floor**
  instead of its world altitude. On the flat that is `base.size * 0.56`, the same number the old
  expression produced, so this is provably a no-op in every valley: measured, **1199/1199** flat
  creatures unmoved and **201/201** raised ones now standing on their shelf, worst clearance error
  0.70 studs.
  **The hit box was a second symptom of the same cause and needed no fix of its own.** It is sized
  and placed from `model:GetBoundingBox()`, which was straddling a body 92 studs up and geometry at
  ground level — 44 studs across, centred 43 studs below the creature you were trying to click.
  Worst `|hitbox − body|` is now 2.04 studs. *A bounding box is a symptom, never a cause: fix what is
  in the box.*
  **`BossService` carries the identical line and is correct by accident**, because a boss arena floor
  is always y = 0 (verified: the ray under `Boss_Forest` hits `Floor` at 0.00 and its soles are at
  exactly 1.00). It now says so in a comment, with the condition under which it would become the same
  bug — the cheapest possible insurance against fixing this twice.

- **2026-08-10** — **Studio had silently lost four files' worth of shipped work, and `src/` is what
  got it back.** Studio came up in Edit with the place at an older state than the repo: a
  hash sweep of all **49** mirrored scripts found **six** different, and a per-line
  prefix/suffix compare proved every one of them was Studio == `src/` *minus* a contiguous block —
  i.e. `src/` ahead, nothing authored in Studio that was not on disk. Two of the six were the
  uncommitted 10.12 / 10.15 / 10.16 work, which is expected. **The other four were not**:
  `BossService`, `CreatureService`, `EvolutionVisuals` and `DNAService` were behind **HEAD** — Studio
  was missing `DNAService.AutoEvolveIfReady` **entirely** along with both of its call sites and
  10.11's spawn-hook sweep. That is 10.10 and 10.11, both marked `[x]` after live verification, both
  absent from the place. The place file had never been saved after those sessions;
  `MainUI` and `ServerMain` matched HEAD byte for byte, so the loss was partial rather than a clean
  revert to an old file.
  **The lesson is the one [[evolution-lab-studio-work-is-volatile]] already states and this is the
  first time it cost shipped rows: a push into Studio is not persistence.** Ctrl+S is. The
  countermeasure that actually worked is the mirror — `src/` was complete and current, so recovery
  was two `UpdateSourceAsync` batches and a hash check rather than a re-implementation.
  **And the save no longer has to wait for a human.** Every in-Studio route is blocked — there is no
  `game:Save()`, `game:SavePlace()` refuses from the Edit datamodel, and calling it under Play would
  persist the *runtime* state (1,400 spawned creatures and all), so that one is not a fallback but a
  hazard. Sending Ctrl+S to the Studio window from the OS works, and this session's work was
  committed that way. **This place is cloud-backed, so Ctrl+S is "Save to Roblox", not a file
  write**: the repo's `Evolution-lab.rbxl` is *not* the document being edited, its timestamp says
  nothing about whether a save happened, and the only honest confirmation is the newest
  `%LOCALAPPDATA%\Roblox\logs\*.log` — `Saving to Roblox…` → `Saved new changes in "Evolution Lab" to
  Roblox.` → `SaveToCloudTime : 7.6096 sec`. Note also that **the document tab carries no dirty
  marker in Studio 0.733** (verified by dirtying the place and re-screenshotting), so "no asterisk"
  is not evidence of anything; a Ctrl+S on an already-clean document logs `Action savePlaceAction is
  not handled` and nothing more, which is how "already saved" is told apart from "the keystroke never
  arrived".
  **Never assume a hash difference means Studio is ahead.** Direction was proved before anything was
  overwritten, by the longest-common-prefix/suffix test on per-line hashes: a `studioBlock` of 0
  (BossService, CreatureService) is proof the push is purely additive, and a small non-zero one
  (ServerMain 9 → 6, EvolutionVisuals 8 → 28) matches a known rewrite in the diff. Serving `src/`
  and a generated line-hash file over two `python -m http.server` ports makes the whole comparison
  three `execute_luau` calls and no script bodies in context.

- **2026-08-10** — **10.15 and 10.16 verified live and closed; 10.17's blocker is gone.** Both had
  been written and left `[!]` because the push was wedged; a Studio restart cleared it, all six files
  went in with no timeout, and both rows were then driven through the real game rather than read.
  The quest sort was tested by **firing the real `ClaimQuest` remote from the Client datamodel** —
  10.10's rule again, that a sandbox which cannot reach the server's cache can still play the game —
  and reading `LayoutOrder` off the live rows: a claimed daily fell 2 → 5, a claimed weekly 7 → 9,
  the two headers never moved off 1 and 6, the panel stayed open, and Diamonds went 71 → 74 for a
  weekly worth exactly 3. **A daily paying no diamonds is not a bug** — `QuestPool`'s dailies carry
  only `xp`, which is why the first claim showed no diamond change and why the row correctly prints
  `250 Season XP as you go` with no `Claim:` half. 10.16 was verified structurally in the same
  session: `InventoryPanel` holds one section and no `Resource*` child, and a full `PlayerGui` sweep
  finds no `DNACard`.

- **2026-08-10** — **10.12: the tutorial ended on the fifth evolve, and it was 9.5's fault.** The
  report was "the tutorial does not properly disappear", which sounds like a persistence problem and
  is not one: the save field, the `Load` migration and the client's gate were all correct and all
  stay untouched. `TutorialDone` was simply flipped in the wrong place — `ServerMain`'s
  `DNAService.OnEvolve` hook, which only fires when an evolve **advances the stage**.
  That was right when 6.3 wrote it. Then 9.5 made every skin its own evolve, and a stage advance
  became every *fifth* press. So a new player was told "⭐ You are ready! Press EVOLVE", pressed it,
  evolved — and the banner and the arrow stayed on screen telling them to press it four more times.
  Measured on a fresh-save fixture: `advancesStage` is **false** on the first press, and the old rule
  did not end the guide until press **5**.
  **10.10 was about to make it worse**, which is the argument for fixing it now rather than later:
  with auto-evolve the player is not pressing anything, so the arrow would have hung over a button
  nobody needs to touch while the rungs went by on their own.
  Moved into `DNAService.HandleEvolve`, where "an evolve succeeded" is actually known — still on the
  server, because a client that could report this could also report having never played, and still
  one line. Verified live: the flag is `true` after the first evolve, an already-done save is
  undisturbed by later evolves, `RebirthService` never touches the flag (so a veteran who rebirths
  back to stage 1 is not handed the first-join guide again — the same trap 6.3's migration exists
  for), and that migration is intact.

- **2026-08-10** — **10.15 and 10.16 are written and cannot be shipped: Studio's script-push is
  wedged (10.17).** Both are lint-clean on disk; neither has been seen running, so both stay `[!]`.
  **The Season Pass bar was never broken, and that is the whole of 10.15's second half.**
  `SeasonPassService.Track` pays a quest's Season XP **pro rata as the quest advances** — an earlier
  deliberate fix, because the XP used to arrive in one lump at the button and the level bar sat
  frozen for the entire time the player was doing the work. The consequence nobody wrote down: by
  the time a quest is claimable, every point of its XP has already been paid, so the claim adds
  nothing to the bar **and cannot be made to without paying twice**. The bar was telling the truth.
  What lied was the row, which printed `+1200 Season XP` beside a Claim button — a sentence any
  player reads as "press this to get 1200". It now says where each half really comes from:
  `Claim: +2 💎` and `1200 Season XP as you go`. That is the honest fix and it costs nothing; moving
  the payment back to the button would re-break the thing the pro-rata change fixed.
  **The "random CTA at the bottom of the Quest UI" does not exist**, and it was worth enumerating
  rather than guessing: `QuestPage` has exactly one child, `QuestScroll`. Nothing was removed. The
  only button in that panel that could read as unexplained is `Get Premium`, which lives on the
  Season Pass tab and sells the premium track — a real purpose, so it stays.
  **Claimable-first sorting is banded rather than sorted by one key**: claimable → still running →
  claimed, with the authored order preserved *inside* each band. That last part matters more than
  the sort does — rows are re-placed on every data push, and a comparator that could reorder within
  a band would shuffle the list under the player's cursor several times a second. A claimed quest
  sinks to the bottom, because it is the one row with nothing left to do. `LayoutOrder` is measured
  from each period's own header (`periodBase`), so daily rows land at 2–5 and weekly at 7–9 and the
  two categories can never interleave however their contents move.
  **10.16 returned eight registers to a file that is short of them.** The Potion modal's `Resources`
  section held a 💎 `x0` card duplicating the HUD capsule that is permanently on screen — diamonds
  are not a potion ingredient and nothing in that panel spends one — and a 🧪 `x0` card that was
  simply the sum of the nine bottles listed directly above it, each with its own count. A sum of the
  rows you are already looking at is arithmetic, not a resource. The top-right `DNACard` went the
  same way: the bottom-left stack is where this HUD decided currencies live (all three in one
  column, with 3.7's `+` shop buttons on two), and the card was a leftover from when DNA was the
  only currency — same number, different shape, opposite corner, nothing to press. **MainUI went 181
  → 173 top-level locals**, the first time this phase a change has *paid registers back*.
  **10.17 is the blocker and it is the owner's to clear.** `UpdateSourceAsync` hung past 120 s on
  four consecutive calls this session while a plain `GetAsync` from the same place returned in
  0.02 s. The fallback — assigning `.Source` directly — works and is now the routine for every other
  file, but it is **hard-capped at 200,000 characters**, measured exactly: `Provided string length
  (292351) is greater than or equal to max length (200000)`. MainUI is 292 KB, so it is the one file
  in the repo that has no route in until Studio is restarted.

- **2026-08-10** — **10.10 closes: the fresh-require trap does not block an end-to-end test, and
  `UpdateSourceAsync` was never hanging.** Two corrections to the entry below, both worth more than
  the row they close.
  **The wall was real and the conclusion drawn from it was not.** A fixture written into the MCP
  sandbox's `PlayerDataService.Cache` is genuinely invisible to the live server — that instance is a
  different module table, measured again here (`Cache` came back with **0 entries** while a player
  was standing in the world). But that only rules out *reaching in*. It says nothing about **driving
  the game from outside**, which is what a player does: fire the REAL remotes from the Client
  datamodel and read the REAL `DataUpdate` and `Notify` payloads coming back. No cache, no fixture,
  no required service anywhere on the path. The end-to-end test needed no fresh save and no hand
  play: `TeleportToZone` to the player's own zone (Forest pays ~1 XP a kill against Multiverse's 33,
  so the zone choice is the difference between 39 kills and 1,277), then a loop that walks to the
  nearest live creature and fires `AutoAttack` — **and nothing else. `Remotes.Evolve` is never
  touched, which is the whole claim.** 14 hits, 16 seconds, and the bar crossed: XP 2414 → **15**,
  rank 45 → 46, stage 9 → 10, `stage=Cosmic Being advanced=true step=1/5`, damage 9275 → 9856
  exactly as the fixture predicted for that rung. The general rule: **a sandbox that cannot reach the
  server's state can still play the game.**
  **Two smaller things the test paid for.** `workspace.Creatures` holds loose `Part`s (`DeathBurst`)
  as well as rigs, so `m.PrimaryPart` errors on a bare part — filter `IsA("Model")` first. And a
  creature's health is a **replicated attribute**, `model:GetAttribute("Health")`, not a `Humanoid`:
  a probe looking for `Humanoid.Health` reports **0 live creatures in a world holding 1,400**, which
  reads exactly like an empty world rather than like a wrong question.
  **`ScriptEditorService:UpdateSourceAsync` did not hang.** It timed out at the MCP layer at 120 s
  and the write had **already landed** — re-hashing all three files afterwards showed them byte-
  identical to `src/`. Treat a 120 s timeout on a large push as "verify, do not retry"; retrying is
  what would have been dangerous, and abandoning it for direct `.Source` assignment gives up the one
  method that gets past the 200 KB write limit for nothing.
  **A push may only be trusted after proving what it will overwrite.** Studio's copies of the three
  files were shown to be byte-identical to `src/` **minus exactly three contiguous hunks**
  (`DNAService:411-453`, `CreatureService:3266-3272`, `BossService:2388-2392`) — found by searching
  for the removal that reproduces Studio's hash, not by reading a diff. Those three hunks *are*
  10.10, so the push could not have destroyed anything. The line-count arithmetic is off by one if
  you take it from `lines` rather than from newline counts, which is why the first search found
  nothing.

- **2026-08-10** — **10.10 and 10.11: the bar evolves you, and the first player into a server keeps
  their body.** 10.11 is the more interesting of the two, because the reported symptom and the actual
  defect were in different places.
  **The costume system was not broken.** Measured on a save with progress: six `SkinMesh` segments
  welded on, all fifteen stock limbs at transparency 1, all three accessories hidden, and the same
  again after a real death and respawn. Two suspects were cleared on the way — a regex made `BUILD`
  look empty when it is populated by twenty later assignments, and **all 100 characters have a
  generated mesh**, so the primitive-builder fallback is dead code rather than a hole a fresh save
  could fall through.
  **What is broken is who gets hooked.** `EvolutionVisuals.Init` connected `PlayerAdded` and nothing
  else. `PlayerAdded` only fires for players who join *after* that line runs — so a player already in
  the game when `Init()` is reached never has `CharacterAdded` connected at all, and every spawn they
  make for the rest of the session is a bare Roblox avatar. That is exactly the report. It is not a
  theoretical race either: `ServerMain` initialises a dozen services in order and `ZoneBuilder`
  rebuilds twenty zones and pins 2,617 parts before this one is reached, so the player who wins it is
  the **first one into a fresh server** — which is also the one most likely to be new. The fix is the
  standard shape: connect first, then sweep `GetPlayers()`, in that order so a player joining
  mid-sweep is caught by the connection rather than missed by both.
  **10.10 is checked where XP is paid, not on a loop**, and that is the whole design decision. XP
  enters a save in exactly two places — a creature kill and a boss kill — and cannot arrive any other
  way: there is no idle XP, no offline XP, nothing purchasable. A poll would therefore be a timer
  asking a question whose answer only ever changes at two call sites, and would land the evolve up to
  a second after the kill that earned it. Called from those two sites, the reveal fires on the same
  frame. It is placed **before** each site's `PushToClient`, so the payload already carries the new
  rung instead of the HUD drawing the old one and correcting itself.
  **It loops, bounded at 25**, and both halves matter: a save that banked XP before this existed can
  cover several rungs at once and would otherwise evolve once per kill for the next twenty kills,
  while an unbounded loop inside a kill handler is a hung server. There is also a no-progress guard —
  if `HandleEvolve` refuses on its own terms and the save does not move, the loop stops rather than
  spinning.
  Verified live on all five branches: one XP short is 0 steps; exactly enough is one step with the XP
  spent to zero; three times a rung's cost is three steps; 1e9 XP stops at 25 in 0.001 s; max rank
  does nothing. Both call sites were then confirmed present in the **running** source at the right
  position. **The full real-kill chain is not yet verified end to end and 10.10 stays `[~]`** — the
  MCP sandbox's `PlayerDataService` is a different module instance from the live server's, so a
  fixture written into the sandbox cache is invisible to the live kill handler (the fresh-require
  trap, in its third variant this phase). It needs a fresh save played by hand.
  **A Studio note:** `ScriptEditorService:UpdateSourceAsync` began hanging indefinitely this session
  after many pushes — three calls in a row timed out at 120 s while a plain `HttpService:GetAsync`
  from the same place returned in 0.02 s. Direct `.Source` assignment works and is the fallback for
  anything under the 200 KB write limit that made `UpdateSourceAsync` necessary for `GameConfig` and
  `MainUI` in the first place.

- **2026-08-10** — **10.8 and 10.9: the boss stopped watching you, and a farmed spawn point fights
  back.** Both rows deleted more than they added.
  **The boss turn was a real feature and it is deliberately gone.** It tracked whoever was fighting
  it within 320 studs, lerped at 1.9 rad/s, and the code around it is some of the most carefully
  reasoned in the file — the snap at 0.004 that stops a lerp parking two degrees off and re-posing
  the statics forever is a genuinely good fix. None of that was wrong; the premise was. A zone boss
  is 75 to 121 studs of architecture standing at the head of an arena whose disc, plinth and banner
  masts are all authored facing the arrival gate, and a 121-stud statue swivelling to follow one
  player reads as scenery on a turntable rather than as something enormous. `want` is unconditionally
  `home` now.
  **Removing the turn made two other things dead, and the second one was worth finding.**
  `yawTowards` and `BOSS_TURN_RADIUS` are gone. But so is the nearest-player search in the driver:
  it existed *only* to feed the turn, it ran for every boss on every frame, and because it had to
  find the minimum it could never break early. The gate it shares that loop with only asks "is
  anybody within `RIG_ANIMATE_RADIUS`", which stops at the first hit — so the loop got shorter and
  strictly cheaper as a side effect of the feature being cut.
  **10.9's growth belongs to the PLACE, not the player**, and that is forced rather than chosen:
  health is one number on one model that everyone in the zone can see, so a per-player version of it
  would be a lie to every other player standing there. `generation` therefore rides the respawn call
  exactly the way `raised` already does.
  **The payout deliberately does not move with it**, per the owner's decision, and this was the one
  genuine tension in the brief: *"the same creature should get stronger"* and *"a kill must never pay
  more just because you have killed more"* point in opposite directions, and paying more for a
  tougher creature is precisely the auto-increment the second rule exists to remove, however it is
  dressed up. So farming one spot slowly gets worse and moving up a zone is always the better play —
  which is what the growth is *for*. Verified structurally rather than by eye: of the thirteen fields
  on the per-spawn `tier` table, **only `health`** references the generation, and neither payout line
  mentions it. The one kill-count term in the file, `data.Kills`, is **written in three places and
  read in none** — it is the lifetime leaderboard counter from 5.3, not a reward input.
  Measured live at a single spawn point across repeated kills: **408 → 428 → 489**, which is base
  x1.05 and base x1.20 exactly. The cap is reached at clearance 20 and holds at x2.00 for 40 and 500.

- **2026-08-10** — **9.9: the interface has an asset layer, and three bugs only a screenshot could
  find.** Every icon in the game was an emoji in a `TextLabel` — zero `ImageLabel`, zero
  `rbxassetid` anywhere in the HUD. That is not a style choice: Windows, Android, iOS and console
  each ship their own emoji font, so the same tile rendered four different ways and not one of them
  shared the thick dark outline and flat pastel fill everything else in this game is built from.
  **The art is generated rather than drawn by hand** (`tools/make_icons.py`, 44 icons, ~9 seconds),
  and regeneration is the reason: change `OUTLINE` or a palette entry and all forty-four move
  together, which is the argument `UITheme` already makes about buttons. Two things it taught. A
  house-style icon is ONE silhouette, so every shape is drawn with **no stroke** and the contour
  comes from **dilating the finished layer's alpha** — stroking each shape gives four rings inside a
  clover instead of one around it. And `ImageFilter.MaxFilter` is unusable for that: at this
  supersample the kernel is ~75px and one icon took minutes, where the union of 96 offset copies of
  the mask reaches the same contour in milliseconds.
  **The lookup key is the emoji itself, and that is the whole design.** Emoji are written into
  twenty stage rows, a hundred pet species, nine passes, seventeen products, thirty season rewards,
  MainUI, and payloads the server sends. Threading an `iconKey` field through all of that would be a
  hundred edits and a hundred chances to miss one. So a call site still writes the glyph and gets a
  drawing — the emoji stays in the source as what it always was, a legible name for the thing, and
  becomes the key as well. **An unmapped emoji returns nil and renders as the glyph**, which is what
  makes 44 icons enough instead of 128: the ~90 species and stage emoji are identity rather than
  chrome (a Swarmer is a bug, a pet is a fox), they are exactly the ones a type foundry already
  draws well, and an emoji added next year renders as it does today rather than as an empty square.
  Four `UITheme` surfaces cover the HUD chrome, but panel CONTENT is built straight out of
  `Instance.new`, so it needed `UITheme.IconSlot`, `IconifyLabel`, `SetIcon` and `HasIcon`. **All
  four live in `UITheme` rather than in MainUI, and that is a register decision**: MainUI is at
  Luau's 200-local cap and already holds a reference to that module, so the whole phase cost it
  **zero** top-level locals (181 before and after).
  **Three real bugs, none visible to a structural probe, all caught by a capture.**
  (1) `SizeConstraint = RelativeYY` makes the **X** scale relative to the parent's height as well,
  so the obvious `UDim2.new(0, 0, 0.62, 0)` — "take the height and let the constraint work out the
  width" — is a slot **zero pixels wide**. Every probe reported an ImageLabel that was loaded,
  positioned and correct; the screen showed tiles with no icons at all.
  (2) Day 7's gold sparkle on the gold Day 7 card was a pale ghost — the same gold-on-gold mistake
  6.4 made with the boost chips. Fixed once for everything rather than per tile: a **drop shadow
  that is the same PNG**, tinted flat to the outline colour and offset behind, so it is exactly the
  icon's silhouette whatever colour it lands on. It has to be a **sibling**, because this ScreenGui
  runs `ZIndexBehavior.Sibling` under which a child always draws above its parent — and it is
  **skipped when the parent runs a layout**, or the currency pills' `UIListLayout` would hand the
  shadow the next cell and push the value along.
  (3) `IconifyLabel` drew the title icon **on top of the title**: its resize handler re-read
  `label.Position` after the label had been stepped right to clear the icon, so the icon walked onto
  the words — "[icon]ily Rewards!" with the "Da" underneath it. Capture the original position once
  and never read the moved one.
  **A verification note worth keeping.** `ContentProvider:PreloadAsync` reported `Failure` for all
  44 icons — and then for a **known-good Roblox asset used as a control**, which is the only reason
  the ids were not thrown away and re-uploaded. The probe was broken in that Studio session, not the
  assets. `ImageLabel.IsLoaded` is the measurement that matters anyway and reported 44/44. Its own
  trap: a texture is not fetched until it actually **renders**, so icons inside a scrolled region
  read as unloaded until they come on screen — demonstrated by walking the shop scroll and watching
  the count climb 4 → 17.

- **2026-08-10** — **10.6 and 10.7: the auto-attack bug was a targeting bug, and the aggro radius was
  measured from the wrong point.** The report — *"auto attack does not work when I stand next to a
  creature"*, with a suspicion about Tutorial Mode — turned out to have nothing to do with the
  tutorial, which never touches input, and nothing to do with combat, which was correct throughout.
  **`nearestTarget` had no liveness test.** A killed creature stays parented for its 0.42 s death
  animation, and `playDeath` has already removed it from `hitHandlers` — so the server correctly
  discards every blow aimed at it. The client, meanwhile, picks the nearest model, and a fresh corpse
  at your feet is nearer than the live creature behind it. Measured in a three-creature cluster:
  **5 of 8 swings went at a corpse 13.8 studs away while a live Swarmer stood at 20.7**, i.e. the
  player is standing in front of something and it loses no health. One `Health > 0` test fixes it,
  and the same test rejects two other things for free — the deathBurst confetti hosts that get
  parented straight into `workspace.Creatures`, and the ~1,190 creature models whose parts are
  streamed out. Checked before shipping that bosses also carry `Health`, or the filter would have
  silently disabled boss auto-attack.
  **Finding it needed the right save and nearly did not happen.** The owner's save is eight rebirths
  deep and one-shots a 6,720-health Elite, so on that character every creature dies the instant auto
  is switched on and the defect is invisible — the first two probes read `LANDING` and `hp 0` and
  looked like a working feature. What exposed it was sampling *what the client would aim at* over
  time rather than *whether the target lost health*.
  **10.7 was two changes, and the test found the second one.** `LOOK_RADIUS` 120 was most of the
  visible platform, so entering a zone turned its whole population to face you at once — which reads
  as the map watching you rather than as a creature noticing you. It is 32 now, sized against
  numbers that already exist rather than picked: the client's auto scan is 34 studs, so a creature
  squares up just *before* you are close enough to hit it, which is the order those two events have
  to happen in. But the first sweep showed a creature at 28 studs still facing its idle direction —
  because `closestDist` is the distance to `rig.origin`, the point the creature was *placed* at, and
  a roaming creature is up to `roamRadius` away from it. Harmless at 120, where a roam is a rounding
  error; at 32 it is most of the radius, so the reaction distance a player actually experienced was
  neither 32 nor the same for two creatures standing side by side. The look test reads the live body
  now; the animate gate deliberately still uses `origin`, since it decides whether to run the rig at
  all, wants to be stable as the creature wanders, and is checked against a radius seven times
  larger. Re-measured: ignores at 90 / 61 / 39 studs, turns at 30 / 26 / 14.
  **A Studio note that cost several runs:** every Play start rebuilds the whole world (the place is
  stamped 115 against `BUILD_VERSION` 117, and Play-mode changes never persist back to the Edit
  datamodel, so the stamp can never advance in Studio). That is 2,617 pinned parts plus twenty zones
  on every single boot, and this session repeatedly reported `Game Started` while remaining in Edit,
  or dropped out of Play mid-probe. Stop-then-start recovers it; probes that must not be interrupted
  should be written as one call.

- **2026-08-10** — **10.4 and 10.5: ten at a time, and a loop that can stop.** The obvious x10 —
  call `HandleBuyEgg` ten times — does not work, and the reason is worth writing down: each call
  fires its own `pet` notification, and `HatchReveal.busy` deliberately keeps one sequence per egg
  (6.1, so Auto Hatch's twice-a-second buying cannot save an already-shaken pivot as "home"). Nine
  of the ten reveals would be dropped and the player would watch a single hatch after paying for
  ten. So a batch needs its own payload, and the roll moved into a shared `rollAndInsert` so the two
  paths cannot drift about what an egg is worth.
  **It buys what fits.** 25/30 pets and a x10 press gets five, and is charged for five; DNA for six
  gets six. Refusing outright is defensible and worse — the whole point of the button is not doing
  arithmetic at the podium. One cooldown stamp, one deduction, one Season counter, one push and one
  notification for the batch, because ten of each is ten replications of the entire save on the most
  expensive action in the game.
  **The reveal is one billboard, not ten.** Ten billboards at a podium overlap into a pile whose
  layout depends on where the player happens to stand; one host laid out in GUI space is stable from
  every angle. One shake, one burst in the best pull's colour, then ten cards arriving 0.09 s apart
  with the header naming the best of them — measured live at **3.48 s, 10 cells, 0 objects left**.
  **10.5's real work was making the loop able to stop and say so.** With the ceiling at 600 a full
  inventory was a state nobody reached; at 30 it is one every pass owner meets in a session, and a
  loop that quietly does nothing twice a second is indistinguishable from a pass that does not work.
  The reason is now reported **once per transition** — `autoStop[userId]` holds the last reason
  announced and is cleared on a successful hatch or on walking away — which is the same spam problem
  2.3 solved by checking silently, solved this time without also making a paid feature mute. The OFF
  switch is a player attribute, mirroring the free auto-attack toggle, and deliberately **not
  saved**: a preference that survived a rejoin would have players logging in already spending.
  **The test found a bug I had just written, and it was the interesting kind.** Guarding the whole
  wiring block with a once-only `Wired` attribute looked right and was wrong: `autoEggPoints` is
  cleared at the top of `WireKiosks` and refilled inside that block, so a **second** call would empty
  the list and never refill it — Auto Hatch would then find no egg anywhere in the world and stop
  silently for the rest of that server's life. Invisible on the first call, which is the only one a
  real server makes today. The two jobs are now guarded differently: connections once, the anchor
  list every time. **The hazard the guard exists for is real and predates x10** — nothing stopped
  `WireKiosks` connecting `Triggered` twice on every egg in the game, i.e. one press charging twice.
  Cloning a prompt is simply what made it visible, because a duplicated prompt can be *seen* where a
  duplicated connection cannot. Verified: 60/60 prompts before and after a re-wire, and a third pass
  adds nothing.
  **A new variant of the fresh-require trap, worth recording.** The MCP sandbox returns a fresh
  module instance **per `execute_luau` call**, not per Play session — so `WireKiosks()` in one call
  and `DriveAutoHatch()` in the next operate on different tables, and the second sees an empty world.
  Anything stateful must be set up and exercised in a single call. Two runs were lost to this before
  it was spotted, and both looked exactly like the feature being broken.

- **2026-08-10** — **10.2 and 10.3: a ceiling, and the door that has to come with it.** These are one
  job. The cap was 600, which was a DataStore protection rather than a design (a save past 4 MB stops
  saving forever with only a warning), and at 600 there was never a reason to remove a pet — so
  nothing was ever built to. A live save reached **207**. Dropping the cap to 30 without a release
  would just be a wall, and a release without a cap is a button nobody presses.
  **The number stopped being private, and that was the actual bug waiting to happen.** `PetService`
  and `TradeService` each held their own `MAX_PETS = 600`, deliberately, on the grounds that the two
  services must not require each other. True, and beside the point: both already require GameConfig,
  so the shared home was always there and the duplication only bought a way for a trade to keep
  accepting pets after a hatch had started refusing them. One `GameConfig.MaxOwnedPets` now.
  **The migration is the part that could destroy a save, so it is guarded four ways.** It runs once
  (`PetsTrimmedAt` stores the ceiling it trimmed to, not `true`, so a future cap change is visibly a
  different rule rather than silently blocked); it never touches a save already under the cap, so
  almost every player pays nothing and gets no flag; it ranks with `data`, so 10.1's zone axis
  applies and it keeps what is strongest *now* rather than what was strongest in the zone it hatched
  in; and **equipped pets are seeded first, unconditionally**. That last one is not a nicety — the
  fixture was built with the weakest pet in the collection deliberately equipped, scoring +3.9%
  against a rank-30 cutoff of +50.5%, and a plain "keep the top 30" dismantles the team the player
  built with no way for them to tell a migration from a bug.
  Verified on the real save, not a fixture: **`trimmed 5746881443 (OGLightninggXD): 58 pets -> 30
  (released 28)`**, and the HUD came back **30/30 in red** with 25 release buttons against 5 equipped
  rows.
  **The release handler takes a list, always.** A single delete is a list of one, because the
  alternative is two handlers with two sets of guards about equipped pets, unknown ids and the empty
  case — which would agree right up until one of them changed. An equipped pet is **refused, not
  auto-unequipped**: unequipping on the player's behalf would make the destructive path the quiet
  one. Unknown ids are dropped silently rather than failing the batch, since a stale row naming a pet
  that was just fused is an ordinary race and not an attack.
  **`PetService:137`'s ordering was already right and is now written down as load-bearing.** Capacity
  is checked before the DNA is deducted fifteen lines later, so the brief's "never consume currency
  and then fail to give the pet" needed no fix — it needs only to keep being true, which means
  nothing that yields may ever be introduced between the two. Measured: at 30/30 a buy is refused and
  charges **0 DNA**; at 29/30 it charges 500 and succeeds; a grandfathered 58-pet save refuses and
  charges 0; release one and the buy goes through.
  Junk payloads were swept and all change nothing (empty, numeric, boolean, a 500-character string,
  a bare string instead of a table), and 5,000 submitted ids hit the 60-id batch cap while still
  sparing the equipped pet. **MainUI gained 0 top-level locals** (181 before and after) — the dialog
  is inside `;(function() … end)()` with one handle on `hudRefs`, per the rule that has deleted this
  HUD twice. `luastruct` clean on 44, `luanames` at its 9-file baseline.
  **The click path is still not click-tested**: `getconnections` is unavailable here, so the button's
  own event cannot be fired. Same limit recorded at 2.10, 3.7, 4.4 and 4.6. What was verified is the
  geometry a click reveals — centred, **CANCEL 210 px against RELEASE 152 px with an 18 px gap**, both
  inside the card, 0 clipped labels — and the handler behind it, driven directly.

- **2026-08-10** — **Phase 10 opens. 10.1: a pet is a combat stat, and an egg's zone finally means
  something.** The report was two sentences and they turned out to be one bug seen from two sides:
  *"every Legendary is +240% however expensive the egg"* and *"DNA was about 60, then I got my first
  pet and it was about 1,000"*.
  **`GetPetBonus(tier, rarity)` took no egg and no zone.** A Forest Basic-egg Legendary and an
  Absolute Plane Premium-egg Legendary were byte-identical — `1 + (1.3-1) * (1 * 8.0) = 3.40`, i.e.
  the reported +240% exactly — across a 1.8e13x difference in price. The egg tier decided only which
  rarities could *roll* (`rarityMin/Max/Bias`), never what a rarity was *worth*.
  **And the DNA half was the larger one.** The same pet carried `incomeMult 4.2` **and**
  `dnaMult 9.0`, both stacked **multiplicatively per slot** in `GetEquippedBonus` — so one pet
  multiplied every click and every kill by **x37.8**, and five by x1307 x x59049. That is the fourth
  time this repo has made the same correction (`GetMutationIncomeMult` reached x5,000,000, idle
  income paid 80 clicks a second, pet damage was a product until 9.1), so it is worth stating as the
  rule it has become: *a quantity that multiplies once per item, over a collection that only grows,
  is not a bonus — it is an exponential in the number of slots.* Both fields are a hard 1 now. The
  DNA curve was authored for a player with **no pets** (14–20 kills per stage), so removing them
  restores the pacing it was tuned for rather than needing a second retune.
  **The progression axis needed no new save field and no migration**, which is the part worth
  keeping. Every species already carries its `zone` from the `ZONE_PETS` flatten, so the zone of any
  pet ever hatched is recoverable from its key — verified live: `Draco → Forest → 1`,
  `Stellara → Nebula → 10`, `TheFirst → AbsolutePlane → 20`.
  **The first cut of the zone factor was wrong, and the balance sweep is what caught it.** It was
  `math.clamp(ratio, 0.25, 1)`, and because damage is geometric the ratio collapses fast: at rank 96
  a zone-1 pet scores 0.0009 and a zone-10 pet 0.026, so **both clamped to the floor and an
  early-egg Legendary was worth exactly as much as a mid-game one** — the brief's own requirement,
  reintroduced at the end of the game by the fix meant to remove it. It is `floor + (1-floor) *
  sqrt(ratio)` now: monotonic over the whole domain, so the ordering cannot flatten however far
  apart the zones are.
  **A third DNA channel survived the first two fixes and only the live test found it.** With the
  multipliers gone the mean click still ran **3.38 → 5.15 → 10.40** across zero, one and five pets:
  `luckAdd` was `5 x tier x rarity` = 40 points for one Legendary and 180 for five, luck drives crit
  (`clamp(5 + luck*0.5, 0, 75)` for x5), and 180 points pins crit at its cap. One free pet was also
  out-earning the **249 R$ Lucky pass** (40 against 50) and five beat it fourfold — out of band
  whatever it did to DNA. Luck rides the damage share now, so one ladder moves a pet's whole
  contribution and none of it can drift.
  Verified live in Play against the pushed source, not read: one Legendary is **DNA x1.17, damage
  x1.83**; five are DNA x1.68, damage x5.00 — damage outpaces DNA three to one, which is the whole
  design. Ordering at rank 96 is **+21.8% / +29.6% / +80.0%** for zone 1 / 10 / 20. The live HUD
  draws it: **Draco +36% beside Pyrodrake +48%**, same rarity, same tier, different egg.
  `luastruct` clean on all 44; `luanames` at its 9-file baseline (the new `stop` warning at
  `MainUI:2550` is 9.3's uncommitted rebirth beacon, same legal-upvalue false positive as the other
  nine). HUD rebuilt whole — **0 top-level locals added**, 56 pet rows drawn, server booted clean.
  **A tooling note:** `loadstring` is disabled in this place, so the roadmap's
  `loadstring(inst.Source)` recipe for testing an edit **does not work here**. The route that does is
  the 9.1 HTTP bridge — `python -m http.server` on 127.0.0.1, `UpdateSourceAsync` from Edit mode,
  then `require` in a fresh Play session, which reads the new source without the Edit-mode require
  cache lying about it.

- **2026-08-10** — **9.4: the terraces finally mint something, and the shard stopped being a stat.**
  Shards had no gameplay source at all after 9.2 took them off the rebirth reward. What was left was
  three time gates and a code — a daily login, the Season Pass premium track, a 7% slice of the
  wheel — and **not one of them is something a player can go and do.** They are a drop now, and the
  one drop in this game with a *place* attached: a creature on the valley floor never pays one,
  however long it is farmed. Only the Brutes and Elites standing on the terrace shelves do. That
  gives the climb the shelves were built for the one thing it never had, which is a reason.
  **The flag is carried on the spawn, and the respawn is the part that mattered.** A Brute on the
  floor and a Brute on a shelf are the same tier, the same rig and the same table of stats — the
  only difference is which of `CreatureService.Init`'s two loops placed them — so `raised` is passed
  to `spawnCreature` rather than inferred from the ground under it. Forgetting to pass it through
  the `task.delay` respawn would have paid the shelves exactly once per server and then never again,
  which is why the verification insisted on kills the ten shelf spots could not have supplied:
  **38 raised kills against 10 spots** means at least 28 of them were respawns.
  **The sink is the wheel that already existed.** `GrantSpin` was made public in Phase 3 for the
  free daily spin, and this is the third door into one implementation rather than a copy that would
  need balancing twice; everything 3.3 measured about the odds still describes it. The price is 25,
  which is exactly what the wheel's own `shards` segment pays, so seven spins in a hundred hand back
  the next one and that segment needed no rebalancing to mean it.
  **And one thing had to be removed for the sink to be usable at all.** `GetShardIncomeBonusPct` was
  still multiplying `GetIncomeMult` by the player's shard *balance* at +2% each. That was harmless
  only while nothing in the game could spend a shard: the moment something can, every spin
  permanently cuts the spinner's income, so the optimal play is to never touch the sink — and a sink
  nobody can afford to use is not a sink. **That income was moved onto the rebirth counter by 9.2
  and this function was the half of the move that never happened**, so nothing is being taken away
  twice. Saves holding shards keep them; what they lose is a bonus the counter is already paying.
  Sized against its sink the way `DiamondDropChance` was sized against the upgrades: Elite 25%,
  Brute 12%, so one sweep of a zone's four Elites and six Brutes pays 1.72 shards and a spin is
  about a quarter of an hour of deliberate cliff work — above the floor where a random drop becomes
  indistinguishable from a bug, and far enough below a diamond's rate that the two never read as the
  same reward.
  The pickup gets **no HUD toast, and that is the one deliberate exception to what the diamond
  does**: a crystal that tears out of the creature and flies into you says both what dropped and
  what killed it, where a banner in the corner says only the first. It is drawn from the house
  recipe for a crystal — a hard block body with a smaller, paler tip, the same two pieces
  `ZoneBuilder` cuts its geodes from, because Roblox blocks do not taper and that tip is the entire
  reason a rectangle reads as faceted. Gold, to match the pill it lands in. No `Highlight` anywhere
  near it.
  **A verification note worth keeping.** The first floor control proved nothing and looked like it
  had: enumerating creatures on the *client* under StreamingEnabled returns far-away models as empty
  shells whose `GetPivot()` is the identity, so a "Y ≤ 30 means valley floor" filter selected 325
  **streamed-out** models at (0,0,0) and the run killed two things by accident. Enumerate on the
  server, hand the client real positions, and re-acquire locally by demanding the model actually has
  a `BasePart`.

- **2026-08-09** — **9.5: an evolve costs XP and nothing else.** It charged **both** DNA and XP, and
  two gates on one button is one gate too many: whichever ran out first was the real requirement and
  the other was noise, so the most important button in the game could refuse for a reason the player
  was not watching. They also pull in opposite directions — **DNA is earned by idle collection as
  well as by fighting**, so a player standing still could unblock an evolve without swinging at
  anything, which is precisely the opposite of what the loop is meant to teach. One currency, one
  sentence: fight → XP → evolve → stronger.
  **The pacing did not need retuning, because XP was already the binding half.** `xpCost` is
  `50 * 1.55^(i-1) * (1 + (i-1)*0.06)` and `zone.mobXpMult` is `1.55^(i-1)` — the same constant, on
  purpose — so kills per evolve ramp gently instead of exploding: **Critter 25 → 53, Brute 10 → 21,
  Elite 4 → 8** from zone 1 to zone 20.
  That same pairing is also what already answers the brief's "you should not be able to unlock the
  endgame from Zone 1", and it answers it by arithmetic rather than by a rule: `xpCost` is a function
  of the STAGE you are at while `mobXpMult` is a function of the ZONE you are standing in, so
  grinding a stage-10 evolve on Forest creatures costs **1,988 Critters against 38** in the zone that
  matches it — 52x — with nothing anywhere forbidding it.
  The client mirror collapsed with it. The progress bar drew `math.min(dnaPct, xpPct)` and then had
  to work out which of the two the label underneath should name, so **the bar could jump backwards
  when the binding requirement swapped and the label changed units under the player**; it is one bar
  and one unit now. `FirstJoin`'s hint lost its unreachable "collect DNA" branch. `step.cost` is left
  on the table and documented as informational — `stage.cost` doubles as the `math.huge` sentinel for
  the end of the chain — with a note that anything checking it is re-adding the gate.
  Verified live at ranks 1, 5, 10, 25, 50, 75 and 99: **DNA = 0 evolved every time**; **DNA = 1e15
  and one XP short was refused every time**; overkill carries (164 banked against 82 leaves 82); and
  rank 100 reports `isMax` with a further press doing nothing.

- **2026-08-09** — **9.2 and 9.3: a rebirth is four events, not an errand.** It was a repeatable
  reset — reach stage 5 and cash in as often as you liked, at whichever of the four statues you had
  passed. That shape has no "next" to point at, unlocks nothing, and its honest optimum is farming
  the cheapest tier forever, which is the least interesting thing the mechanic can do. It is now
  four milestones — stages 5, 10, 15, 20 — **spent strictly in order, once each, and then the ladder
  ends** (the owner chose the hard stop over an endless tier 4).
  **It needed no new save field, and that was worth an hour of not adding one.** `data.Rebirths`
  already counts what has been spent, and because the milestones are consumed in order the count IS
  the position on the ladder — a separate "tiers used" set would be a second source of truth that
  could disagree with the counter, and every save in existence would have needed repairing to build
  it. `GetNextRebirthTier` / `CanRebirthNow` are the only two functions that decide anything, and the
  server, the HUD and the shrine all read them, so the button cannot offer what `HandleRebirth` will
  refuse.
  **Saves that predate the rule keep everything.** The owner's has eight rebirths against a ladder
  four long; it holds x23.00 damage and has simply nothing left to spend. Never take something away
  to enforce a new rule — and the panel drops the denominator past the cap rather than printing
  "8 / 4", which reads as broken arithmetic rather than as a grandfathered save.
  **`tier` stopped being a choice and became a claim.** Four statues used to be four prices for one
  transaction, with the reward going as tier², so choosing was a trap the UI had to warn about. Now
  the argument is only the client asserting which statue it touched; it is **checked against the one
  live milestone and refused otherwise, never clamped** — a client asking for the wrong one is stale
  or lying, and both deserve the same answer. The NaN guard is still load-bearing and still the only
  test that works (`n ~= n`): every comparison against NaN is false, so it slid past the old guards
  and a NaN in the save makes every future DataStore write throw forever, swallowed by a pcall.
  **Shards left the rebirth loop**, per the owner's design: they become a rare drop off the raised
  creatures with the wheel as their only sink (9.4). A currency that is *spent* cannot also be the
  permanent reward for the hardest thing in the game — so the income it used to pay moved onto the
  counter as `GetRebirthIncomeMult`, +150% a run, where it cannot be spent away by accident. Four
  rebirths now end at **x8.00 damage and x7.00 income**, both permanent.
  The panel was rewritten to answer the six questions it never answered — how many, which is next,
  where am I, what do I get, what do I lose, how far off — because the old one listed a Shard price
  and never once named the thing being bought, which is why a rebirth read as a punishment. And 9.3
  adds a beacon that exists **only** while a milestone is live: one Heartbeat for the whole thing,
  connected while showing and disconnected otherwise, reading `AbsolutePosition` every frame because
  the responsive pass moves that tile on any resize and a cached position aims the arrow at empty
  screen.
  **Testing note worth reusing.** `require` from the MCP sandbox in Play returns a **different module
  instance** than ServerMain's — which is why `PlayerDataService.Get` came back nil earlier, and it
  is also a safety property: a fixture written into the sandbox's `Cache` cannot reach the live
  server's. `Save` was stubbed and counted anyway (6 interceptions, 0 writes), because `HandleRebirth`
  saves immediately by design and the cache is keyed by the real user id. The corollary is that
  `RebirthService.OnRebirth` reading as `nil` from a probe proves nothing — check `ServerMain` in
  source (it is wired at :168 and :186).

- **2026-08-09** — **Phase 9 opens, and 9.1 is done: evolving finally does something.** The report
  was "the Journal says an evolution gives more damage and the number over the creature never
  changes", and the damage function was never the problem — it was correct and it was the only one.
  **Three things stood between it and the screen, and two of them were the same mistake.**
  `CreatureService` clamped every blow to `tier.health / minHits` and `BossService` clamped every
  blow to `boss.health / BOSS_MIN_HITS`; in both cases **the clamp then became the number the FX
  drew**, so a fresh save and a save eight rebirths deep saw the identical figure. In Forest that
  cap is 4 on a Swarmer and 7 on a Critter — and a brand-new stage-1 player already hit for 8, which
  means *no player had ever once seen their own damage*. Both are gone.
  The third was `PetService`: `damageMult` multiplied per pet, and on the owner's own save five
  ordinary pets came to **x652** against **x1394** for the whole hundred-step ladder — so even with
  the caps removed, an evolve's step would have been noise. Summed now (**x14.32** for the same five).
  **This is the third time this repo has made exactly this correction** — `GetMutationIncomeMult`
  reached x5,000,000 as a product, and idle income paid eighty clicks a second — so it is worth
  stating as a rule: *a quantity that multiplies once per item, over a collection that only grows,
  is not a bonus, it is an exponential in the number of slots.* `incomeMult` and `dnaMult` were
  deliberately left alone; that is an economy rebalance, not a combat fix.
  **The curve underneath was also wrong, and in the opposite direction at the other end.** Damage was
  `8 + (stage - 1) * 6` — linear, x15 across the whole game — against creature health's geometric
  x1050. That is why the late zones were passable only through Rebirth damage, and why *"after
  rebirthing I progress far too slowly"* kept coming back: a mechanic meant to be a choice was
  load-bearing. It is now geometric in the **character rung**, which is the thing the player is
  actually doing: 100 rungs, five to a stage, one per evolve, at `1.076` each — and `1.076^5 =
  1.4425` is `mobHealthMult`'s own per-zone ratio (measured, 1050^(1/19) = 1.442). **The two are one
  curve now, and the property worth protecting is that kills per creature are FLAT**: zone 1 rank 1
  and zone 20 rank 96 both give Swarmer 2.4 / Critter 6.0 / Brute 14.0 hits, while inside a stage the
  five evolves cut a Critter from 6 hits to 4. Boss health stopped being twenty authored numbers
  spanning x86,000 and became `BossTargetHits * GetZoneReferenceDamage(i)`.
  **One design rule had to be reversed to make it work, and it is an improvement:** damage reads the
  best rung **owned**, not the one **worn**. At a linear +3% a rung, wearing something fifty rungs
  back cost 150% — a real trade the Journal advertised honestly. Geometric, that same choice costs a
  factor of forty, which no cosmetic is worth and which would read as a broken save rather than as a
  decision. **Progress pays; appearance is free.** Health follows damage onto the same rung so the
  two can never disagree about what the player is.
  Verified live in Play, not read: evolution 1→100 = **5 → 7,053**; 2x Damage **x2.00**, VIP
  **x1.50**, both **x3.00**, 1 rebirth **x2.00**, 4 rebirths **x8.00**, Income 50 **x1.50**, 5 pets
  **x14.32**. **There is no damage potion in the game** — the nine bottles are dna/xp/luck only, so
  the brief's "check potions feed the damage calculation" has no hook to check. The end-to-end proof
  is the `CombatFx` payload off a real kill: **`k=kill d=3768`**, exactly `GetCombatDamage` for that
  save, where the same swing drew **`7`** before.
  **A tooling note that will pay for itself all through Phase 9:** Studio's `HttpService` will fetch
  `http://127.0.0.1`, so `src/` can be pushed into the place *whole* over a one-line local file
  server plus `ScriptEditorService:UpdateSourceAsync` — instead of replaying every changed comment
  block through `multi_edit`, which for `GameConfig` (200 KB) and `MainUI` (269 KB) is thousands of
  tokens per edit. Six files went across byte-identical on the first attempt, hashed on both sides.

- **2026-08-09** — **Phase 8's server core: 8.2, 8.3 and 8.4 done and verified, 8.1 and 8.5 half
  done, and the gate is still shut.** `TradeService` exists, compiles and is tested, and **nothing
  can reach it** — ServerMain does not require it, `Init()` is never called, no remote is created.
  The half that was written is the half the gate is actually about (the exploit surface) and the
  half that can be proven without a second client; the half that was not is everything needing two
  real clients, which is the same wall 5.4 hit.
  **8.3's own premise turned out to be wrong about Roblox, which is the fourth time this has
  happened (3.5, 6.4, 7.1).** The row asked for "both saves written before either is acknowledged".
  That is a two-phase commit, and no DataStore offers one: `SetAsync` yields, so any gap between the
  two writes is a window in which the pets exist in both inventories. The argument had to be built
  the other way round — **in-memory `Cache` is the authority for a live session and the DataStore is
  a backup of it**, so the swap is made atomically in memory (no wait, no SetAsync, no event between
  validation and the two mutations) and the writes follow. A failed write cannot then duplicate
  anything; it can only lose, and losing is the only acceptable direction to fail in.
  **The proximity requirement turns out to be load-bearing twice.** It reads as an anti-scam rule,
  and it is one — but it is also what guarantees both save tables are on the same machine, which is
  what makes the whole "trade with yourself across two servers" class inexpressible rather than
  guarded against.
  **And the anti-scam rule that matters is three lines.** Any change to either offer clears BOTH
  confirmations. The 3-second hold and the summary card everyone thinks of as the anti-scam feature
  are decoration on top of that line.
  Verified against two synthetic saves (negative user ids — Roblox ids are positive, so the owner's
  save could not be touched, and with no Player object on either side `PlayerDataService.Save` was
  never reached): **5 pets in, 5 out, 0 duplicated, 0 lost**, reservations back to 0 on every exit
  path, a pet destroyed mid-trade refused with both inventories unmoved, the cap refusing 600+1 while
  allowing an even swap at 600, the 7th trade in a minute refused, and 11 log entries actually read
  back out of the DataStore.

- **2026-08-09** — **Phase 7 is code-complete: 7.1, 7.2 and 7.3, all verified live. Only 7.4
  (owner, two dates) is left.** The three rows collapsed into one idea used three times — something
  that is true right now, derived from the clock and never stored — so 7.2 is a single row in a
  config table and 7.3 changed no reset logic whatsoever.
  **The UTC trap is the one worth carrying.** `os.date("*t")` is local time and `os.date("!*t")` is
  UTC. A Roblox server runs UTC, so the two agree in production and a window written against local
  time is wrong **only in Studio** — i.e. only on the machine anyone ever tests on, where this one
  measured two hours out. Everything here is `!`. And rather than assume which way Roblox reads
  `os.time(table)`, the offset is **measured** with an expression that is correct whether it is read
  as UTC (it is: verified, so the correction is 0) or as local — a branch there would have had to
  guess which host it was on.
  **Two things a probe cannot see, and one it wrongly reported.** The board's first home passed a
  centre-count occupancy scan and was wrong: a brazier bowl from the boss-gate idol pad **overlapped
  the top of the panel by 4.1 studs** and the posts stood on that pad at y=7 rather than on the
  floor. A cell-occupancy count cannot see a big part whose centre is in the next cell. The spot was
  then *searched for* rather than chosen — every 5-stud position scored by separating-axis gap
  against 612 anchored parts, plus a downward ray demanding `Floor` — and the first pass of that
  scored 2.2 studs against a `head_geom`, because **creatures walk and a clearance measured against
  one is not a fact about a place**. Anchored parts only.
  **And the capture lied first this time.** The photograph appeared to show the sign printing
  "Double DNA and double XP everyone" with a word missing — the word was behind the HUD's DNA
  capsule. Worth recording because the reflex by now is to trust the picture over the probe: the
  fix was a second capture from an angle the HUD did not cover, not an edit. What the picture *did*
  find was real, though — the layout used 440 of 720 pixels and left the bottom third of the board
  blank, with every label reporting `TextFits = true`.
  **The migration was the dangerous half again**, as in 6.3. Two of them: `data.EventCharacters`
  defaults to `{}`, which is true of every save ever written and therefore needs no repair beside it
  — but the skin it protects would otherwise be destroyed by a rebirth, because `data.Characters` is
  cleared wholesale and an ended event has nothing live to re-grant from. And the season epoch is
  picked so that today still generates the id **`S1`**, byte for byte what every existing save holds:
  a different answer there is a wipe, not a bug report.

- **2026-08-09** — **6.3, the first-join sequence. Phase 6 is code-complete; only 6.5 (owner) is
  left.** The game now explains itself: a camera pan, a banner that names the next thing to do, an
  arrow at the EVOLVE button, and an ending that says what comes after.
  **The dangerous part was not the tutorial, it was the migration.** `Load`'s generic backfill copies
  every new default onto every save ever written, so shipping `TutorialDone = false` would have
  handed the first-join sequence to every existing player at once. A save with progress is repaired
  to `true` explicitly — and the flag has to be a **field**, because the obvious test ("stage 1")
  is exactly what a rebirth produces, and a veteran would get the tutorial again on every reset.
  **Two layout facts worth keeping.** `AbsolutePosition` is reported **below the topbar**, while a
  Position offset inside a ScreenGui with `IgnoreGuiInset = true` is measured **from the top of the
  screen** — the two differ by the inset (58 px here), so mixing them puts an element exactly one
  inset out. Matching MainUI's `IgnoreGuiInset` is the intuitive fix and the wrong one; leaving it
  false is what makes the arithmetic agree. And the capture earned its keep for the third time this
  phase: the arrow, correctly placed above the button, **covered the DNA bar that explains why the
  player is being told to press it**. It points from the side now.
  Verification note: with no fresh save available, the server half was proved by **pulling the
  shipped lines out of `.Source` and running them** — 5.7's technique, and the reason it is worth
  repeating is that a test that reimplements the rule can agree with itself while the real one is
  wrong.

- **2026-08-09** — **6.4, the boost strip.** The row as written asked for "pass icons and
  countdowns", and **half of that request was wrong about this game**: every pass is permanent, so
  there is no countdown to draw and a clock on one would invite the player to worry about an expiry
  that does not exist. It shipped as a split strip — cards with bars and clocks for the things that
  are running out, chips for the things that are not — which is the third time this phase's premise
  has had to be checked against the code before building it (see 3.5 and 6.2).
  **Two verification notes worth reusing.** The injected-payload technique from 2.10 needs a rate:
  the real service pushes `DataUpdate` about every three seconds and **the last payload to arrive is
  what the HUD holds**, so a probe reading a single instant kept catching the real one and reporting
  nothing. Pushing at 0.15 s made the injection 36 pushes to 2 over six seconds, and the probe
  **samples across three seconds and keeps the strongest state seen** rather than trusting one read.
  And `TextFits` was meaningful this session — the viewport reported a real 1546×793, not the 1×1
  the earlier notes warn about — so it is worth *checking* the viewport before dismissing that
  property rather than assuming it is useless.
  **The capture found the bug the probe could not, again**: `styleCard` paints a card in whatever
  colour it is handed, so gold chips on a gold card were structurally perfect and visually invisible.
  Dark discs on gold now, which is the potion row inverted — and the inversion carries meaning, one
  glance says these two rows are different kinds of thing.

- **2026-08-09** — **6.2, the Legendary beam.** Two new files, `AnnounceService` on the server and
  `RarityBeam.client`, plus one row in `GameConfig` and one in `SoundLibrary`. Nothing in `MainUI`.
  **The lesson worth carrying: a `BillboardGui` shrinks with distance no matter how its size is
  authored.** The first build put the naming on a 320x96 card floating on the column, on the
  reasoning that offset units are pixels — and at 177 studs it measured about a hundred pixels wide,
  which at the 500-stud range the feature exists for is a smudge. There is no constant-screen-size
  mode for a billboard. So the announcement was split along the axis each half is good at: the
  **column** is a physical object and reads from anywhere, the **words** are a HUD toast and are the
  same size for everyone in the server. That toast is exactly the "one client toast" 5.4 needs, and
  it is where a cross-server message — which has no position and therefore no beam — will land.
  **Two Studio facts confirmed the hard way, both worth remembering.** First, `require` from
  `execute_luau` in **Play** returns a *different* module instance from the one the running scripts
  hold, and that is true for `ReplicatedStorage` modules too, not only services: a stub pushed onto
  `GameConfig.RollPetForEgg` had no effect whatsoever on the running `PetService`, which went on
  rolling normally. Anything that must exercise the live game has to go through a **remote**.
  Second, `screen_capture`'s `camera_position` override does **not** survive in Play — the game snaps
  the camera back to the player before the frame is taken. Put the thing being photographed where the
  player is already looking, and read `workspace.CurrentCamera.CFrame` from the **Client** datamodel
  first to find out where that is.
  Because of the first fact, 6.2 was verified by **buying fifteen real Forest Premium eggs** through
  the real remote until a Legendary came up (it took 15; the egg advertises 3.76%). **Side effect on
  the owner's save, recorded here rather than hidden: 15 junk Forest pets (34 → 49 of 600), about
  68,000 DNA of 3.9T, and +15 on the Season Pass egg counter.** A third, smaller trap: a `[==[ ]==]`
  literal already drops the newline after its opening bracket, so the `:sub(2)` used when pushing a
  file into Studio ate the first character of two scripts. Both compiled clean only after it was put
  back — always `loadstring` the result.

- **2026-08-09** — **Phase 6 opens with 6.1, the hatch sequence.** The most repeated purchase in the
  game had a small card over the player's head and the egg they were looking at did not react.
  **The bug this cost an hour to find is worth remembering: `RunService.RenderStepped:Wait()` never
  returns on a client that is not rendering.** The three animation loops used it, the whole sequence
  hung inside its own `pcall`, and every outward sign — no error, no warning, no output, script
  present and enabled, handler demonstrably receiving the event — was of code that had simply decided
  not to run. It took a `print` at each step to see that execution stopped at the first `:Wait()`.
  **Use `Heartbeat` for anything that must not wedge**; it runs on the simulation step, is
  independent of rendering, and is just as smooth at 60 Hz. This is the same root cause as the 1x1
  viewport that makes `TextFits` meaningless and stops TweenService stepping in probes — that Studio
  client is not drawing anything.
  Two shape notes. The hatch presentation now lives in **one** file: MainUI's `pet` branch is silent
  and `SoundLibrary.PlayNotify` no longer handles `pet`, because only `HatchReveal` knows when the
  reveal moment is — the notification arrives the instant the server pays out, which is a second
  before the egg has finished moving. And because the egg is a **replicated** object being animated
  locally, the whole thing is one `PivotTo` against one saved pivot with a restore on every path: a
  client-side CFrame change is never corrected by the server, so a failure halfway leaves that egg
  permanently crooked for that player and nobody else.

- **2026-08-09** — **Phase 5 closes at 5.1, 5.2, 5.3, 5.6a and 5.7 — all verified live. 5.4 is
  deferred on purpose.** `MessagingService` cannot be exercised from Studio: there is no second
  server for a message to reach, so the code would compile, sit there, and nobody could show it
  works. Writing it blind was offered and declined. Every other row in this phase was proved
  against the running game, and one unverifiable feature is worth less than the doubt it casts on
  the ones beside it — it unblocks the moment a test place is published, and is a small job then.
  What is left in Phase 5 is therefore **owner-blocked only**: publishing (5.4), the group id (5.5)
  and Rewarded Ads (5.6b).
  **5.7's verification technique is the one to reuse.** The rarity line lives in a local function
  inside MainUI and the Journal only renders it for a *selected* disc, which is a mouse click this
  environment cannot make. Rather than reimplement the function in the test — where a second copy
  can agree with itself while the shipped one is wrong — the **shipped source was extracted from
  `MainUI.Source`, `loadstring`-ed and run** against every bracket. That found a real bug: a
  character nobody owns printed `<0.1% own it`. Note `loadstring` is available in the **Edit**
  datamodel only, so this runs with Play stopped.

- **2026-08-08** — **5.3 leaderboards and 5.6's free spin are in. Phase 5 is now 5.4, 5.7 and two
  owner rows.** The free spin reuses `RobuxShopService.GrantSpin`, which Phase 3 made public for
  exactly this — the wheel is luck-shifted, weight-normalised and priced below the flat DNA pack, and
  a second copy would have been a second thing to keep balanced.
  **The leaderboards deliberately avoid `ZoneBuilder`.** Scenery normally belongs to the world
  builder, but that file is 480 KB and its `BUILD_VERSION` guard regenerates all twenty zones when it
  moves. `RebirthShrine` had already set the alternative: a service that builds its own furniture and
  owns its own version stamp. **Placement was measured** — an occupancy scan of Forest found the
  street at x=0 carrying 75–100 parts per cell and x=±65 carrying 25–40, while x=−130 is completely
  empty from z=140 to z=300. That is where the signs went, facing the street.
  **Four `OrderedDataStore` traps are written up in that file's header.** The one that would have
  cost a day: it stores **integers only**, and `data.DNA` is a float in the trillions — handed over
  raw it is refused and the board simply stays empty with nothing logged anywhere. Values are floored
  and clamped below 2^53, past which a double cannot represent consecutive integers and the ranking
  would be noise. Also: a zero is never published, so an empty board beats one full of people who
  have never done the thing it measures.
  **`data.Kills` starts at 0 for everyone**, including existing saves — there is nothing in an old
  save to reconstruct it from — and a rebirth does **not** clear it, or the board would rank players
  by how recently they reset.
  Verification worth copying: the kill counter was proved by **actually killing three creatures**
  through the real `AutoAttack` remote (hop to the creature, attack, hop back), not by reading the
  increment. `data.Kills` went 0 → 3 and the sign followed 56 seconds later through the real loops.

- **2026-08-08** — **5.1's redeem bar landed; 5.1 and 5.2 are both done.** It went into the **Daily
  panel** rather than onto a tile of its own, because the right-hand cluster is a full 2x4 grid since
  the Audio tile took order 8 and a ninth tile would push the column to five rows and move every
  button on screen. The panel grew 480 → 536 to make room, which costs nothing that was already
  there. MainUI is **still at 179 top-level locals** — the fourth feature in a row to add none.
  **Note for whoever tests codes next: the six launch codes were all spent on the owner's own save
  while verifying this**, so that save will refuse them. Nothing else was affected.

- **2026-08-08** — **Phase 5 started: 5.2 done, 5.1 needs only its panel.** Two new services,
  `CodesService` and `OfflineService`, and the config and save fields behind them.
  **The one thing worth carrying forward is where the offline seconds live.** They are computed in
  `PlayerDataService.Load` — before `LastSeen` is overwritten — and kept in
  `PlayerDataService.OfflineSeconds`, a plain in-memory table, then *consumed before the payout is
  computed*. Every other shape was worse: a field on `data` is written by the 60-second autosave, so
  a crash between that write and the payout is a payout collected twice; reading the seconds and
  clearing them afterwards leaves a window that a double `PlayerAdded` walks straight through. The
  same reasoning made `LastSeen` stamp on **every** save rather than only the leave-save — a server
  that dies never runs its leave-save, and its players would each come back owed eight hours.
  Offline income is safe to build on this codebase only because `GetAutoCollectAmount` is already
  expressed as a fraction of one click per second and capped at 1.2 (see the note over it, which
  exists because idle income once paid eighty clicks a second). Offline is that capped rate × bounded
  seconds × 0.5, so **playing > idling > being away** holds by construction rather than by tuning.
  Codes are the opposite of every other id table here: `RobuxProducts` and `GamePasses` hold ids that
  must never be invented, while a code is invented on purpose and only becomes real when it is
  published. The one thing that needed care is that `RedeemedCodes` is marked **before** the grant
  with no yield in between — that gap is the entire double-redeem exploit.
  Two verification notes for the next session. **Order the probes recorder-first**: firing from the
  Server datamodel and *then* installing a Client watcher loses the event, because the tool
  round-trip is longer than any delay worth setting — install a listener that writes into a
  `StringValue`, fire, then read it. And the **Play viewport reports 1x1**, so `TextFits` and every
  `AbsoluteSize` inside a panel are meaningless; the welcome-back card's line length had to be
  checked by counting characters against `celebratePurchase`'s 300x56 label and `themeLabel`'s 14px
  floor instead.

- **2026-08-08** — **Phase 4: the game has audio.** It had exactly one `Sound` in the whole place;
  it now has 26 catalogued entries across combat, economy, interface and ambience, and **every asset
  id was loaded in this place before it was written into the table** (38 of 38 passed). That check is
  the phase's main reusable lesson: a bad audio id is not an error, it is silence, and silence looks
  exactly like code that never ran.
  Three decisions worth carrying forward. **(1) A shared module can protect MainUI's register cap.**
  The Notify handler needed a sound per kind; putting the twenty-row table in `SoundLibrary` and
  calling one `PlayNotify(payload)` cost MainUI **one** top-level local instead of twenty-plus, and
  the file went 178 → **179** while taking the whole phase. **(2) The one guard that is load-bearing
  is `RunService:IsClient()` in `UITheme`** — that module is required on the *server* by
  CreatureService and BossService, and a server-created `Sound` replicates, so an unguarded click
  would have played a button press in every player's ears from a server that pressed nothing.
  **(3) `data.AudioVolumes` is the first field in the game the client may write directly**, and so
  the first that needed real validation: 99 clamps, unknown keys are refused, and NaN is rejected
  explicitly because `math.clamp` passes it straight through.
  **A real bug was found only because the test read a property rather than trusted a call.** The
  ambience bed came up correctly created, grouped, loaded, playing and looping — at Volume 0.000, and
  still 0.000 eight seconds later; `TweenService:Create(...):Play()` had run and nothing had moved,
  while a direct write to the same property stuck instantly. The fade is now a task that **always
  writes its final value**, because the end state is the entire point: a bed that never reaches its
  target is a silent soundtrack that still costs a stream, and nothing anywhere would report it.
  A second, smaller find from the same session: `flatParent()` created its folder without looking for
  an existing one, so a second module instance silently split the game's audio across two folders of
  the same name.
  **4.6's control landed in the same session: Phase 4 is complete.** An Audio panel with four
  sliders and a mute button, on a new right-column tile — and the whole panel cost MainUI **zero**
  top-level locals (still 179), which is the third time the `;(function() … end)()` shape has paid
  for itself.
  **Two things the live read caught that reading the file could not.** First, the tile was placed at
  right-column order 5 on the reasoning that the slot looked empty in the run of `columnTile` calls —
  it is the **Season Pass tile**, which is built inside its own immediately-called block further
  down and therefore does not appear in that list. The two overlapped exactly. It moved to order 8,
  the genuinely empty bottom-right corner, which also fills the hole that left order 7 sitting alone.
  *Never infer a free slot from one run of `columnTile` calls — read the live column.* Second, the
  slider track overlapped its own percentage readout by 4px (8 once the `UIStroke`, which draws
  outside the frame, is counted).
  **A note for anyone probing the HUD through MCP:** the Play viewport reported **1x1**, so the
  responsive pass had squeezed every panel to a 0.35 scale and *every* label answered
  `TextFits = false`. That is not a layout bug and chasing it is wasted time — force the panel's
  `UIScale` to 1 before measuring, and the same 11 labels all fit.

- **2026-08-08** — **Phase 3 is code-complete; only 3.8 (owner) is left.** The shop went 7 products
  → 17: five DNA tiers, five Diamond tiers, the Lucky Spin, the Boss Revive and two Catalyst packs,
  all verified live in Play rather than read.
  Three things worth carrying forward. **(1) 3.5's specification was wrong about this game** —
  Rainbow and Celestial have always been free to fuse, so "Rainbow Fusion" would have sold shipped
  content. It became a Rainbow Catalyst that sells the 16-copy grind instead and stops below
  Celestial; the reasoning is in `GameConfig.RobuxProducts` and the row above. **(2) Both new
  consumables are counted charges, not moments**, because `ProcessReceipt` is retried on Roblox's
  schedule, can land on another server, and writes to the DataStore before acknowledging — anything
  that had to be spent at the instant of purchase would have a tail of buyers who paid for nothing.
  **(3) The screen capture earned its place.** A structural probe reported 17 healthy cards while
  every DNA tile was clipping its own name: `themeLabel` floors text at 14 px, so a wrapped name in
  a 24 px box is cut, not shrunk. Only the picture showed it. `TextLabel.TextFits` is the cheap
  check that would have caught it — worth using after any tile-layout change.
  Also new, and reusable: `RobuxShopService.GrantSpin` is public so 5.6's free daily spin does not
  copy the wheel; `BossService` gained the game's **first `Humanoid.Died` hook**; and MainUI took
  four new features while staying at **178 top-level locals** — everything went inside
  `;(function() … end)()` with handles on `hudRefs`.
  One thing found and deliberately NOT fixed, because it is outside this phase: the free fusion
  rows in `MainUI` label every fuse `+100%`, because they divide `GetPetPower` (raw tier × rarity)
  rather than the affine bonus it feeds. A Common's real income gain from Golden to Rainbow is
  **+44%**. The new Catalyst rows quote `GetPetBonus` and are honest; the old rows still overstate.

- **2026-08-08** — **Phase 2 is code-complete.** The Journal gained its 21st section for the VIP
  skin (built by the same code as every other disc, and it does not inflate `Discovered n / 100`),
  and the stacked-balance check passed with nothing to change: passes are a flat ×3.00 on income
  and damage, hit counts are protected by `BOSS_MIN_HITS`, crit is saved by its 75% cap, and the
  luck-shifted roll tables are far more damped than expected. **Only owner tasks remain in Phase 2**
  (2.11, the dashboard) plus 0.4 and 1.7. Next code is Phase 3.
  Note for whoever probes the client next: the server pushes its own `DataUpdate` about every three
  seconds, so a one-shot probe payload gets overwritten before it can be read. Re-fire it in a loop
  for the duration of the read — two apparent "bugs" this session were only that.
- **2026-08-08** — **All nine passes done.** VIP's visible half (aura, [VIP] chat tag, 5 Diamonds a
  day) and Auto Hatch landed. The aura is particles and a light, never a `Highlight` — CreatureService
  rents 14 of the ~31 Roblox renders and one per VIP would strip every creature outline in the world.
  Auto Hatch reuses `HandleBuyEgg` rather than reimplementing the shop. Only the two `MainUI` jobs
  (2.9b, 2.10), the owner's dashboard step (2.11) and the balance check (2.12) remain in Phase 2.
- **2026-08-08** — **Phase 2: all seven multiplier passes hooked and measured.** 2x DNA, 2x Damage,
  2x XP, Lucky, +3 Pet Slots, Fast Auto Attack and 2x Speed all move their own stat and nothing
  else — isolation checked pass by pass in Play. Two decisions the owner made along the way:
  **2x Speed lifts the walk cap to 260**, because against the 150 streaming cap it was only a true
  2x through stage 7 of 20 and delivered 1.18x at the top; and the **VIP skin will be a 201st
  golden skin inside the Journal**, unlocked only by VIP (see 2.9a for why it must stay out of
  `CHARACTERS_BY_STAGE`). Still open in this phase: Auto Hatch, VIP's non-multiplier extras, the
  VIP skin, and the shop UI.
- **2026-08-08** — **Phase 1.1–1.6 done; 1.7 is owner-blocked.** The monetisation foundation is in
  and verified in Play. The DNA packs no longer pay a rounding error late game. `GameConfig` gained
  the 9-pass table and the four accessors; `PassService` is new; `PlayerDataService` clears
  `data.Passes` on load so a stale save can never grant a free pass; `ServerMain` wires it before
  `RobuxShopService`. **Note the passes do not DO anything yet** — the call-site hooks are Phase
  2.1–2.9. `src/` was kept in step with every edit and re-verified byte-identical to Studio.
  Also confirmed still open: 0.4, the streaming radii, which warn on every boot.
- **2026-08-08** — **Phase 0.1–0.3 done.** Studio's Save As offers only the binary `.rbxl` in
  this install, so `tools/rbxl_extract.py` was written to parse the binary place format
  directly (zstd chunks, interleaved zigzag referents). All 44 scripts extracted into `src/`
  and verified byte-identical against the live Edit datamodel. `src/` had been 14 stale files;
  it is now the whole place. `.gitignore` added so no place binary can enter git history.
  Remaining in Phase 0: 0.4 (owner, Properties panel) and 0.5 (commit).
- **2026-08-08** — Roadmap created from a gap analysis of the live Studio datamodel. Findings that
  set the phase order: no game passes exist anywhere in the place; all 7 developer products have
  `productId = 0`; `RobuxShopService` grants fixed DNA in an exponential economy; the game has no
  audio; no `OrderedDataStore`, no `MessagingService`, no codes, no offline earnings, no trading.
  Nothing implemented yet.
