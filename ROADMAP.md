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
| 5.4 | `[!]` | 📢 **Cross-server announcements** — `MessagingService` on Legendary hatches and Colosseum kills. **BLOCKED: it cannot be verified in Studio.** There is no second server for a message to arrive at, and `PublishAsync` / `SubscribeAsync` do not carry between a Studio session and anything else — so the code would compile, sit there, and nobody could show that it works. Deliberately deferred rather than written blind: every other row in this phase was proved live, and a single unverifiable feature is worth less than the doubt it casts on the ones beside it. **Unblocks the moment a test place is published** — then it is a small job (one topic, two publish sites, one client toast) | to verify: publish, join the same place from two clients, hatch a Legendary on one and see the toast on the other |
| 5.5 | `[ ]` | 👥 **Group / Like / Favourite rewards** | grows the group, which is the update-notification channel |
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
| 8.1 | `[~]` | Request / accept with a **proximity requirement**. Server half done: one live trade per player, a 4s request cooldown, a 40-stud reach checked at the request **and again at the commit** (a window that survives one player walking to another zone is a trade with somebody who is not in front of you), and only the *receiver* may accept. **The UI half is deliberately not written** — and no client message is sent from `Request` either, because "somebody wants to trade" is a prompt that has to be answerable, and routing it through the error channel because that channel happens to exist is how a UI ends up shaped by its plumbing | refusals returned as text, so a test reads what the player would: self-trade, an unknown player, a second trade while already in one, and the 4s cooldown all refused with their own reason |
| 8.2 | `[x]` | **Two-sided confirm with lock-and-recheck.** Every offered id is re-resolved against the owner's *current* `data.Pets` at commit time, because a pet can be fused away between the offer and the confirm — and the reservation deliberately does **not** stop an owner destroying their own pet, since being locked out of your inventory because a stranger opened a window at you is worse than a refused trade | a pet removed behind the trade's back after one side had confirmed: refused with "One of those pets is gone" and **both inventories unchanged, A=2 B=2 before and after**. One-sided confirm moves nothing; a direct `Commit` refuses with "Both sides must confirm" |
| 8.3 | `[x]` | **Duplication defence — and the row's own premise was wrong about Roblox.** It asked for "both saves written before either is acknowledged", which is a two-phase commit no DataStore offers: `SetAsync` yields, and any yield between the two writes is a window in which the pets exist twice. So the argument is built the other way round and needs four properties: both players are **on one server** (the proximity rule is what guarantees it, so "trade with yourself across two servers" cannot be expressed), a pet can be in **one live trade** (`reserved[petId]`, released on every exit path), **the swap does not yield** (validation and both table mutations run with no wait, no SetAsync and no event between them), and **the save happens after** — in-memory `Cache` is the authority for a live session, so a failed write cannot duplicate, only lose, and losing is the only acceptable direction to fail in. Both writes are still issued, both are checked, and a failure is recorded on the log entry rather than swallowed | **conservation measured: started 5 pets, ended 5, 0 duplicated, 0 lost**, and each of the three traded ids in exactly the opposite inventory. Reservations: held while an offer stands (`reservedPets 1`) and **0 after cancel, after commit, and at the end of every run**. Collection cap: 600+1 refused with nothing moved, an **even** swap at exactly 600 allowed. Equipped pets refused at the offer, with a second guard at the commit for the phantom-bonus case |
| 8.4 | `[x]` | **Trade log and rate limit.** The log keeps 50 in memory for a live investigation and writes to its own `EvolutionLab_TradeLog_v1`, keyed by UTC day, appended with `UpdateAsync` (not `SetAsync`, or two servers trading in the same minute overwrite each other) and capped at 400 a day — past a DataStore value's size limit the writes stop entirely, which loses the newest entries, i.e. the ones an investigation is about. The rate limit is **two taps**: a 4s request cooldown bounds pestering strangers, and 6 completed trades a minute bounds what a bot farm cares about | **11 entries actually persisted and read back** from the store, matching the last trade's ids and counts. Rate limit: trades 1–6 went through and **#7 refused** with "Too many trades". The log's human line resolves a real pet: `🪨 Rainbow Pebble` |
| 8.5 | `[~]` | **Anti-scam.** The server half is done and it is the load-bearing half: **any change to either offer clears BOTH confirmations, unconditionally.** That is the oldest scam in the genre — both sides confirm, then the scammer swaps the good item in the half-second before commit — and it is three lines. The 3-second confirm hold and the "you are giving / you are getting" summary are the UI half and wait for a second client; `MAX_OFFER = 10` is already in place for the summary's sake, since a window holding forty pets is a window nobody reads | A confirms (`a=true b=false`), A switches its offer → **`a=false b=false`**; A re-confirms and **B** changes its side → both false again. The reset fires from either direction |
| 8.6 | `[ ]` | Wire it up: the remotes, the trade window, the confirm hold and the summary. **Needs two clients**, and therefore a published test place — the same wall as 5.4 | two players in one server complete a trade and both saves survive a rejoin |

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
| 11.4 | `[~]` | **A4 · Skins glitch — four causes, and one of them was diagnostics.** **R1** `dress()` had no generation token: it sleeps up to 2 s in `waitForBodySettled` and its only guard was "same character", so two equips inside that window raced and the **older** one could land last — with the evolve path's `task.delay(0.7)` giving stale data a head start. Now a monotonic `DressGeneration` attribute on the character, plus the worn skin re-read from the save *inside* `dress`. **R2** `SkinMesh` welds with `host.CFrame:Inverse() * part.CFrame` — world CFrames — while the settle wait only watched *size*, so dressing mid-stride welded the arms into that stride forever; the wait now also requires `MoveDirection == 0` and a non-airborne state. **R3** two `setBodyHidden` implementations wrote two different attributes (`SkinBaseTransparency` / `StageBaseTransparency`), neither ever cleared, so each could record the other's hidden `1` as the original — a permanently invisible player, held off only by the order inside `Clear`. One name (`BodyBaseTransparency`), cleared on restore. **R4** `att`'s infinite spin tweens were never cancelled; a destroyed weld does not stop a Tween, so every rebuild leaked its spinning parts. **Plus the missing half:** the whole skin path had **one** `warn` in it, and five silent `return`s produced exactly the signature in `src/STATUS.md` — stock avatar, zero costume parts, zero errors. Every one of them now says what it did | **R1 proven live, in both directions.** Two `ApplyStage` calls 0.1 s apart — well inside the 2 s settle window — with different skins: `DressGeneration` went **1 → 3** and the body ended up wearing **B**; run again with the order reversed it ended up wearing **A**, which rules out "the later one wins by luck". The real skin was restored afterwards. **R3 proven on the running character**: 15 hidden limbs all carry the single `BodyBaseTransparency`, and **zero** instances anywhere on the body still carry either old attribute name. All 59 scripts compile; `GameConfig` / `SkinMesh` / `StageCostume` load clean. **Owed: R2 (dressing while running) and R4 (the tween leak) are reasoned and coded, not measured** |
| 11.5 | `[x]` | <!-- verified live 2026-08-12 --> **B1 · Luck splits into pet luck and everything else.** `GetLuckPercent` was the one sum and the shop `Upgrades.Luck` entered it at `x2`/level, feeding five consumers (crit DNA, mutation, egg roll, mystery potion, wheel) — so one purchase quietly moved five unrelated things, the card named the two it moved least, and no number was safe to raise: anything big enough to be felt on an egg was a crit-chance clamp on the DNA click. The upgrade leaves that sum; new `GetPetLuckPercent(data)` = `GetLuckPercent + Upgrades.Luck * GameConfig.PetLuckPerUpgradeLevel`, with **exactly two readers** — `PetService.rollAndInsert` (what you get) and the egg panel's odds table (what you were promised), which is why neither computes it itself. Upgrade strengthens +2 → **+5**/level, `displayName` "Luck" → **"Egg Luck"**, description rewritten. **The cap is the thing the row did not know**: `GetUpgradeMaxLevel` is 5 levels per unlocked zone, so this is +25 at one zone and **+500** at twenty | **live on the shipped client, driven by a real `DataUpdate` payload with only `Upgrades.Luck` differing.** Egg panel: `🍀 0% luck` → **`🍀 50% luck`** at level 10 (exactly +5/level) and the Forest basic odds moved with it — Common **62.8 → 50.0**, Epic **2.6 → 4.1**. The odds table and the roll agree: 60k real `RollPetForEgg` draws came back 38.84/43.91/15.68/1.57 against the panel's 38.67/43.87/15.83/1.63. **The negative half has a control, so "unchanged" means something**: the shared total is flat at **0.00** at upgrade levels 0/1/5/10/25 (crit chance `clamp(5+luck*0.5,0,75)` = 5.00 at every one), and 60k draws each of `RollMutation`, `RollMysteryPotion` and `RollSpin` are identical at level 0 vs 25 — while the same three at a forced luck 125 move hard (mutation Common 61.1 → 44.5, Secret 0.25 → 0.76). Exactly **one** live read of `Upgrades.Luck` remains in the repo and it is inside `GetPetLuckPercent`. Card renders `Egg Luck` with `TextFits` true; the cap message still fires above it. **No saturation at the cap**: on the endgame egg (+272 own bonus) 100 levels is luck 772 and Legendary only 2.1% → 2.5%, so the raise is felt by a new player and is nearly free at the top |
| 11.6 | `[~]` | <!-- verified live 2026-08-12; layer-2 payout owed --> **B2 · Terrace creeps behind a rebirth wall.** The creeps "up on the sides" already exist — raised Brutes and Elites, 4+6 per zone, the `raised` flag already threaded through respawn and already paying shards. **Nothing in the codebase gates on `data.Rebirths`** (5 reads, none a lock), so this is a new system. **[decision] Two layers:** existing terraces at `Rebirths >= 1` (stronger DNA, shards, small chance of a pet from the zone pool); new higher points at `Rebirths >= 3` (much stronger DNA, **exclusive pets in no egg**). Pets from kills are a new path — `PetService.GrantPetFromDrop` **reusing `rollAndInsert`** so the roll and the 100-pet cap cannot drift. Exclusive species cost no assets (`PetModel.Build` is procedural) and enter `GameConfig.Pets` but **not** `PetsByZone`, so `RollPetForEgg` cannot reach them. **[decision] A new creep tier per rebirth**, not a new pet. Locking is per-player against a shared creep, so it follows `RebirthShrineClient`: the client greys and delists locally, the server refuses independently. **BUILT AS SPECIFIED WITH THREE DELIBERATE DEPARTURES.** (a) `raised` became the LAYER NUMBER (1 or 2, nil on the floor) rather than gaining a second parameter — it is already threaded through the respawn and one thing threaded correctly beats two threaded nearly correctly; every existing `if raised` keeps its meaning. (b) `GrantPetFromDrop` does **not** reuse `rollAndInsert`: two of that function's three lines are wrong for a kill — it adds an egg's `luckBonus` when there is no egg, and it rolls against `GetPetLuckPercent`, which since 11.5 includes an upgrade *called Egg Luck* whose card promises "rarer pets from every hatch". A kill is not a hatch. What the row wanted protected is held instead by a new `insertPet`, now the only place in the game a pet is created, and by the one `MAX_PETS`. (c) The new tier is **one** Apex tier at `Rebirths >= 3`, not one per rebirth, which is what the row's own "two layers" decision describes. **The trap this row walks straight into is 11.9**: a new, stronger creep can out-last its zone's boss again. `ApexBaseHealth` is therefore `math.min(350, BossEliteFloor * EliteBaseHealth)` — algebraically the exact condition for a farmed Apex to stay inside the boss floor, with the generation cap and `mobHealthMult` cancelling from both sides, so it cannot go stale when either moves | **measured live on the published place, and on Kristina's own save.** Spawning: **80 Apexes, 4 per zone**, on the highest shelves — Apex ≥ Elite ≥ Brute altitude in **20 of 20 zones**, and one Apex sampled at y = 92.6 with `Health=350 Raised=2 MinRebirths=3`. Gate: 12 real `AutoAttack` fires at an Apex moved its health **3850 → 3850** with the notice `🪐 Core of Suns is sealed -- it takes 3 rebirths to touch it`; a client pushed a payload claiming 3 rebirths painted itself unlocked and the server **still refused**, which is the split working. Payout on real kills in Forest: raised Brute **7.599e6** DNA against a valley Brute's non-crit **2.533e6** = **3.000x** exactly (two of three valley samples came back 5x — the crit — which is also why the first reading looked like 0.60), XP **10 → 20 = 2.00x**. Exclusivity is structural: **20,040 real egg rolls across all 60 eggs at luck 500 produced 0 exclusives while touching all 100 eggable species**, and 20,000 more down the malformed-egg fallback produced 0. Drop rates over 60k calls: **1.98%** (target 2) and **4.93%** (target 5); a full 100-pet bag refuses with `"full"` and the bag stays at 100. Boss invariant re-measured across 20 zones: worst boss / farmed Apex **1.00**, worst / fresh Apex **2.00**, and no boss's health moved. Plate: locked reads `🔒 🪐 Core of Suns — 3 rebirths` with 48/48 parts in Slate, unlocks to `🪐 Core of Suns` with **0** parts still carrying a lock-original, and re-locks — with exactly **one** padlock each way. MainUI registers **179 → 179**. **Owed: the layer-2 payout (x12 DNA, x5 XP) and an Apex kill have never been run**, because the save doing the testing has 1 rebirth and reaching 3 costs a real run — the same wall as 11.1 |
| 11.7 | `[x]` | <!-- verified live 2026-08-12 --> **B3 · Fusion, Rainbow Catalyst, Boss Revive.** **[decision]** fusion 4 → **3** copies (Rainbow 9, Celestial 27 — reachable against the new 100 cap); Catalyst 99/249 → **49/129 R$** and its card **moves out of the Robux grid into the fusion panel** (product id untouched); **Boss Revive is removed**. ⚠️ **The one item here that can take money and give nothing back:** Roblox retries `ProcessReceipt` forever until it is acknowledged, so the receipt branch **stays** and converts an in-flight purchase into diamonds. Only the product listing and the revive UI go. **THE CATALYST WAS ALREADY HALF IN THE FUSION PANEL and the row did not know**: every pet row there carries a `CatalystRow` R$ button, which is the single catalyst's real storefront — and that button printed a **hardcoded `"R$ 99"`**, so the reprice alone would have made it advertise one number and charge another. So only the **x3 bundle** gets a card of its own (`panelCard`), the single stays on the pet rows, and that button now reads `product.price` like the grid always has. Boss Revive is `delisted` rather than deleted — a deleted row means a retried receipt resolves to nothing, forever — and its grant became `grantDiamonds = 10`, which is exactly what `Diamonds_1` sells for the same 49 R$, so an in-flight buyer is made whole at the shop's own rate. The revive card itself survives for anyone holding a charge and is simply never offered to anyone who is not: the server checks `held > 0` before sending it, and the client's "buy one" arm is gone | **live.** `FuseRequirement` **4 → 3**, so Celestial is 27 copies against a 100 cap instead of 64 — reachable for the first time — and all four in-world fusion signs rebuilt to read **"Bring 3 of the same pet"** (`BUILD_VERSION` 126 → 127, since a sign is baked at build time). Robux grid: **14 cards, no `BossRevive`, no `TierUp_1`, no `TierUp_3`**. Fusion panel: 6 per-pet rows all reading **`R$ 49`** (was the literal 99) and one bundle card `R$ 129` / "3 catalysts — raise 3 pets a tier, no copies needed"; **0** clipped button labels. Product ids all unchanged and verified: `3702254100`, `3702254553`, `3702254989`. **Owner half outstanding: turn the Boss Revive product's sale off on the dashboard, and match the two Catalyst prices there** |
| 11.8 | `[ ]` | **B4 · Health potions.** **[decision] A fourth kind** beside the three: `GameConfig.PotionKinds` gains `health` and nine potions become twelve, because the loop below builds the size combinations itself — so a size cannot be added to one and forgotten on the other. Effect multiplies `MaxHealth` (which already scales per stage through `EvolutionVisuals.applyMaxHealth`, so it multiplies that rather than inventing its own) and speeds regen while it runs | 12 potions built; a live drink raises `Humanoid.MaxHealth` and it returns on expiry |
| 11.9 | `[~]` | **B5 · Bosses are weaker than the creeps — and it was true in every zone.** The plan's own analysis was out of date (it described hand-typed boss health, which 10.x had already replaced with a derivation), and **the real state was worse than the report**. Boss health is `BossTargetHits × GetZoneReferenceDamage(zone)`, and 60 hits was chosen as "about four Brutes" — correct, but the **Elite** is 280 base, i.e. **56 hits**, so a boss was one Elite. With `generationHealthMult` bringing a farmed spawn back at up to **x2**, an Elite reached 112 hits — twice its own zone's boss. Measured across all twenty zones: boss/Elite **0.84–1.07** fresh and **0.42–0.54** farmed. Fix keeps the derivation (it is what makes a boss the same fight on every rung) and ties it to the creature curve: `BossTargetHits` 60 → **150**, plus a floor of `BossEliteFloor × EliteBaseHealth × CreatureGenerationMax × mobHealthMult`. `EliteBaseHealth` and the generation cap **move into `GameConfig`** and `CreatureService` reads them back — the private copy is what let the two curves drift in the first place | measured live on the pushed code, all 20 zones: **worst boss/farmed-Elite 1.25** (was 0.42), boss/fresh-Elite flat at **2.50** (was 0.84–1.07), and **every boss gained at least 2.50x health** — the "at least double" decision satisfied in every zone. **Owed: one real boss fight** |
| 11.10 | `[x]` | **B6 · Pet cap, sorting and the "5/3" counter.** <!-- verified live 2026-08-11 --> Three separate one-line defects. (a) `MaxOwnedPets` 30 → **100**: 30 put Celestial (27 copies at the new fuse requirement) out of reach of an inventory that also has to hold a collection. Raising is safe for every existing save — `PlayerDataService`'s trim only fires on `#Pets > cap`, true for nobody after a raise, and the `PetsTrimmedAt = 30` stamp simply never matches again. (b) `SortedPetsByPower(data.Pets)` was called **without `data`**, so the drawn order dropped the zone axis and quoted every pet at its home zone's strength — a zone-matched Epic drawn beneath a Forest Legendary it beats four times over, while both server callers passed `data`. (c) The panel title read `Pets (%d/%d equipped)` against the raw `MaxEquippedPets` constant, ignoring the diamond slots and the pass — hence "5/3", a fraction that reads as a broken save. **[decision] The title is just `Pets`**; the capsule below already prints the pair correctly | **live in Play.** The HUD's own capsules read **`7/100`** (the new cap) and **`6/6`** (slots counted through `GetMaxEquippedPets`, no more "5/3"); the panel title is the literal **`Pets`** with `TextFits = true` and it is the only such label in the tree. Sorting checked on a rank-100 fixture holding pets from Forest and the Antimatter Zone: the shipped order is **0 pairs out of order** in real `GetPetPower(pet, data)`, while the old dataless order has **1** — a Forest Epic (0.121) drawn above the Antimatter Epic (0.210) that beats it, which is the defect exactly |
| 11.11 | `[ ]` | **B7 · Diamond upgrades are too cheap for what they give.** `MegaIncome` base 5 / mult 1.6 for **+10% permanent income per level** with no level cap, since 10.x made kills the one gameplay diamond source. Raise the bases and the multipliers; `PetSlot` keeps its `maxLevel = 3` | cumulative cost of the first 10 levels before and after, against measured diamonds/hour from `RollDiamondDrop` |
| 11.12 | `[!]` | **B8 · Shard packs for Robux.** Shards have one source (raised creeps) and one sink (the wheel at 25). A pack joins `RobuxProducts` modelled on the diamond tiers, which are **deliberately unscaled** — a shard is a fixed 25-cost item that does not ride the stage curve. **BLOCKED on 👤 OWNER**: needs a real `productId` from the Creator Dashboard. Until then `RobuxShopService:88` correctly refuses with "This item isn't set up yet" — code can be written and tested, the row cannot close (same rule as 1.7 / 3.8) | the id resolves via `GetProductInfo` and a purchase grants shards |
| 11.13 | `[ ]` | **C1 · The shops look plain.** Accent header with icon and subtitle, even margins, cards modelled on `ui_kits/evolution-lab/RobuxShopModal.jsx`, across Upgrades / Robux / Mastery / fusion. Also: the main shop is the **only** panel in the game that closes by setting `Visible = false` instead of calling `animatePanel`. **Found while closing 11.3:** `makeTab` (`MainUI:4192`) builds the Robux panel's two tabs at `0.5, -6` with hand positioning, i.e. a 12 px frame gap — which is the same 2 px of *visible* space 11.3 had to fix, because each stroke draws 5 px outward. **A gap of N between two stroked siblings shows as N − 2×thickness**; use the `UIListLayout` shape 11.3 settled on rather than repeating the arithmetic | captured at `UIScale` 1.6; no clipped labels; the two shop tabs show ≥ 10 px of daylight |
| 11.14 | `[ ]` | **C2 · The Journal looks plain.** Same rules; the 100-disc grid needs a clear locked state | captured; locked and unlocked discs distinguishable at native size |
| 11.15 | `[ ]` | **C3 · Better notifications.** Today a 46 px pill with an emoji chip. New: a card with an `IconLibrary` icon, a duration bar, and ordering by importance. `SoundLibrary.PlayNotify` already exists and is not touched | each notification kind drawn with its real icon; the stack orders by importance and cleans to zero |
| 11.16 | `[ ]` | **C4 · Progress bars everywhere.** `UITheme.ProgressBar` exists and is used in exactly 3 places. Add to the Season level, quest rows, mastery, the rebirth ladder and the Journal collection | each new bar's fill width matches its own ratio |
| 11.17 | `[ ]` | **C5 · Multi-delete for pets.** **The server is already done** — `HandleDeletePets` takes a list (10.3). Client only: a SELECT mode, a checkbox per card, a counter, one `DeletePets` call. Equipped pets are refused by the server, so they are not offered in select mode | 3 selected pets deleted in one call; an equipped pet cannot be selected |
| 11.18 | `[ ]` | **C6 · The egg screen belongs on the egg.** **[decision] One prompt per egg, "View Eggs", opens the screen; every purchase happens from there.** The Eggs HUD tile (R9) is deleted and the right column drops from 5 rows to 4 (`RIGHT_COUNT` 9 → 8). The panel itself stays — `hudRefs.refreshEggPanel` is called from `refreshUI`. The prompt gets a `ShopPanel` attribute so it enters the existing handler rather than a new path, and `nearestEggZone()` already gates the buttons on proximity | prompt opens the panel; buying from it still respects range and cost |
| 11.19 | `[ ]` | **C7 · A real 10x hatch.** Today: one shake, one crack, one burst and a 74×46 grid of emoji squares on a billboard by the podium. **10 eggs shaking and opening at once**, in the same `screenReveal` shell the single hatch uses (dim + blur + `RelativeYY` stage), reusing `buildEggFigure` ten times. `screenBusy` must be consulted — `playBulk` does not look at it today | 10 figures drawn and cleaned up; no overlap with a single hatch fired during it |
| 11.20 | `[ ]` | **C8 · The Colosseum boss countdown is invisible.** The countdown exists but its board is in the world above the arena entrance — visible only to someone already there, which is backwards. `eventState.nextSpawn` lives on the server only; publish it as a replicated attribute and draw a HUD strip. Boss interval back to **30 min** | the HUD strip counts down outside the arena and matches the board inside it |
| 11.21 | `[ ]` | **D1 · The solid-prop whitelist is keyed to names 18 zones do not use.** 10.13 introduced `SOLID_PROPS` in `newPart`; `addGroundLitter` and `addMounds` write `CanCollide = false` and rely on it to put them back. But the biome configs rename them — `LavaRock`, `MoonRock`, `Meteorite`, `VoidGrit`, `GildedStone` (18 of 20), `AshMound`, `DustRidge`, `VoidMound` (17 of 19) — and `SOLID_PROPS.MushroomCap` never matches the real `TerraceShroomCap`. Add the names, **and warn at the end of the build for any `SOLID_PROPS` entry never seen**, or the next biome reintroduces it | the unseen-name warn is silent after the fix; a `Blockcast` sweep hits each renamed prop |
| 11.22 | `[ ]` | **D2 · Solid base, walk-through top.** `boulder()` makes `ValleyRock` solid and `ValleyRockCap` — which sits *on* it — not. Same for `CliffCragMid`/`CliffCragCap`, `addRockRampart`'s `CliffCap`, and `addLandmark`'s `GreatCanopy` / `SpireTip` | `Blockcast` from above stops at the cap, not through it |
| 11.23 | `[ ]` | **D3 · Rocks buried inside the terraces, both sides solid.** The X wall stands at `cx ± 625` and `TERRAIN_OUTER = 625`, so terrace slabs reach the wall exactly; every `CliffBlock` from `addRockRampart` occupies x ≈ 600–626 against a solid `TerraceTop` at y 66–128. The Z wall is worse — it sweeps `cx ± 617` straight through the terrace belt on both sides. A second source at `ZoneBuilder:8240` (Desert) uses raw `math.random` instead of `scatterPoint`, lands in `[415, 625]`, and those clones are never anchored and never given a `CanCollide` — unlike every other `:Clone()` in the file | `GetPartsInPart` on the `TerraceTop` slabs counts intersecting solid bodies; must fall to zero |
| 11.24 | `[ ]` | **D4 · Waterfalls have no reservation.** The file has exactly one keep-out inside a slope and it is only for the stairs (`stairSeg` / `inStairwell`), deliberately computed *before* any prop so every prop can test it. The waterfall's `fz` is chosen ~600 lines later and **nothing tests it**, so `FallSpillway`, `FallHead` and `FallBasin` run full tread depth through crags, boulders, conifers and mushrooms already placed. Fix: choose `fz` on the same pattern as `stairSeg` — before the props, and tested by them. This is also half of D3 | no prop intersects the fall corridor in any of the 20 zones |
| 11.25 | `[ ]` | **D5 · `FallSheet` cuts through the solid `CliffJut`.** `CliffJut` is the one solid thing in the riser plane and is deliberately sunk into the hill (`innerX-2 … innerX+d-2`); `FallSheet` is 4 wide centred on `innerX - 1.8`, i.e. `innerX-3.8 … innerX+0.2` — **~2.2 studs of overlap**. `FallCurtain` is additionally scaled by `math.max(byH, byW)` — max, not min, so it is deliberately oversized on one axis | the two no longer intersect; the curtain still covers the drop |
| 11.26 | `[ ]` | **D6 · `PoolRim` against `PoolStone`, both solid.** The rim is 6 wide at `poolX ± 27` (so `|dx|` 24–30); stones land at `poolX ± random(20,30)` at sizes 7–14, so a 14-stud stone centred at 24 rides over it. `PoolStone` is authored `CanCollide = false` but is in `SOLID_PROPS`, so `newPart` turns it back on — two solid bodies interpenetrating exactly where the player walks up to the water | zero intersections at the pool edge |
| 11.29 | `[x]` | <!-- found and fixed 2026-08-12 --> **E2 · Two creatures fell off CelestialThrone's shelves, and a "quiet" drop was silent.** Both found by measuring 11.6. (a) The raised roster went 10 → 14 per zone, and `raisedSpots` samples real terrain — **CelestialThrone yields only 12 valid shelves**, so it now stands 4 Apex + 4 Elite + **4** Brute instead of 6. That is the documented "a zone with too few shelves simply gets fewer" path behaving correctly, and it is recorded here rather than fixed because backfilling onto the valley floor is the wrong answer for exactly the reason the code comment gives. It costs that one zone ~0.24 shards a sweep. (b) The pet drop first shipped as `kind = "pet"` with `auto = true`, on the reading that `auto` means "the quiet presentation". **It does not — it means "play the EGG sequence instead of the full-screen one"**, so HatchReveal shook an egg on a podium in the zone's shop, several hundred studs from the terrace, on an egg nobody bought. The drop produced **no visible feedback at all** where the player stood. It has its own `petDrop` kind now, drawn on the player like a fusion | **(a) counted live**: 198 layer-1 creatures against an expected 200, the two missing both in CelestialThrone, whose Brutes number 4. **(b) measured live before and after**: before, firing the real payload produced **0** labels naming the pet anywhere in the PlayerGui; after, `🌳 Sylvan King` over `APEX DROP — EGGS CANNOT HATCH THIS`, and an ordinary drop over `DROPPED` |
| 11.28 | `[x]` | <!-- found and fixed 2026-08-12 --> **E1 · The welcome-back card promised to keep a streak it was about to break.** Found by measuring 11.2's missed-a-day branch, which had never been drawn. The card's *head* deliberately quotes the streak the claim will **produce** — there is a comment over that line calling "Day 6 is ready" followed by a Day 1 payout "the kind of small lie that makes the whole board look broken". The *note* one line below then told exactly that lie: it tested only `streak > 0`, so a player who missed a day read `🎁 Daily reward — Day 1 is ready` over `🔥 4 day streak — claim to keep it going`, when claiming resets the streak to 1. Both lines now ask the same question (`continuing`), and a broken streak is **said out loud** rather than hidden — it is the only thing on the card that asks the player to come back tomorrow | **all three branches measured live on the shipped HUD**, before and after. Before: missed-a-day drew `Day 1 is ready` / `🔥 4 day streak — claim to keep it going`. After: `Day 1 is ready` / `💔 Your streak ended — this one starts a new run`, while the continuing branch is unchanged at `Day 5 is ready` / `🔥 4 day streak` and the never-claimed branch at `Day 1 is ready` / `Claim it to start a streak`. MainUI recompiles (`loadstring` clean) and is byte-identical to `src/` |
| 11.27 | `[ ]` | **D7 · The reservation system exists and almost nothing uses it.** `scatterPoint` and `reserveScatter` are correct. Of ~100 calls, about ten pass a `halfSize` and reserve; **all ~90 calls between lines 5818 and 7249** — the entire `decorationBuilders.<Zone>` block, i.e. every zone's signature props — look like `scatterPoint(cx, 200, 250)`: they declare no size and claim no ground, so they land on each other. The tool that can actually check this is `CreatureService.clearOfScenery` / `floorAt`, which probes the **live** world with `OverlapParams` + `RaycastParams.RespectCanCollide` after `Build()` — `scatterBlocks` is a set of 2D circles with no Y axis and cannot describe a terrace. **Also:** `src/ServerScriptService/ZoneDecor.lua` (2,829 lines) is a **dead outdated copy** of the terrain section with an older `TERRAIN_PROFILE` — nothing requires it. Delete it or mark it, because it misleads everyone who touches terrain | overlap count per zone before and after |

---

## 👤 Owner action checklist

Collect these once; each one blocks agents until it exists.

| | Action | Blocks |
|---|---|---|
| `[x]` | Publish a test place — `MessagingService` cannot be exercised from Studio at all, and neither can two clients trading | 5.4, 8.6 — **done 2026-08-11**: published to **Evolution Lab BETA V0.2**, universe `10675543038`, place `102217824272435`. Both rows are now buildable |
| `[ ]` | **One real Robux purchase** on the published place — the only thing that exercises `ProcessReceipt` and Roblox's billing. Studio's `IsStudio()` pass grant tests effects, never purchases | 1.7, 2.11, 3.8 |
| `[ ]` | Roblox group id, for the Group / Like / Favourite rewards | 5.5 |
| `[ ]` | Rewarded Ads set up on the dashboard (the free spin half of 5.6 is done) | 5.6 |
| `[x]` | Save the place into the repo (binary `.rbxl` is fine — `tools/rbxl_extract.py` reads it) | 0.1 — done 2026-08-08 |
| `[ ]` | `StreamingMinRadius` / `TargetRadius` / `IntegrityMode` in Properties | 0.4 |
| `[x]` | Create the 7 existing developer products, paste ids | 1.7 — done 2026-08-11 |
| `[x]` | Create the 9 game passes, paste ids | 2.11 — done 2026-08-11, all with "Item for sale" on |
| `[x]` | Create the 10 new developer products, paste ids (the shop is 17 rows now — see 3.8) | 3.8 — done 2026-08-11, 26 ids in total |
| `[ ]` | Game icon and thumbnail | 6.5 |
| `[ ]` | **Turn off the Boss Revive product's sale** on the dashboard. The receipt branch stays in code on purpose so in-flight purchases are still honoured — see 11.7 | 11.7 |
| `[ ]` | **Create a shard pack** developer product and paste the real `productId` | 11.12 |
| `[ ]` | **Match the two Catalyst prices on the dashboard** — 11.7 moved them to **49** (`TierUp_1`, id 3702254553) and **129** (`TierUp_3`, id 3702254989). The number in `GameConfig` is only what the card prints; the dashboard is what actually charges | 11.7 |
| `[ ]` | **One real rebirth** from a late zone on the published place, to close 11.1 end-to-end. It costs the runner their progress, which is why no agent has done it | 11.1 |
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
