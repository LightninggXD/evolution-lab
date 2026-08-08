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
| 0.5 | `[ ]` | Commit the synced tree + this file to git on a branch. `.gitignore` now excludes `*.rbxl*` — a 20 MB binary that rewrites wholesale on every save must never enter the history | `.gitignore` | `git log` |

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
| 1.7 | `[ ]` | **👤 OWNER** Create the 7 existing developer products on the dashboard, paste real ids | `GameConfig.RobuxProducts` | a real purchase in a published test place grants and saves |

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
| 2.11 | `[ ]` | **👤 OWNER** Create all 9 passes on the dashboard, paste ids | a real purchase applies without a rejoin |
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
| 3.8 | `[ ]` | **👤 OWNER** Create the **10 new** developer products on the dashboard and paste the ids (`DNA_1`…`DNA_5`, `Diamonds_1`…`Diamonds_5` replace the old four; plus `LuckySpin`, `BossRevive`, `TierUp_1`, `TierUp_3`) — 17 rows in total with the two potion packs and the Season Pass | real purchase grants and saves |

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
| 5.3 | `[ ]` | 🏆 **Global leaderboards** — `OrderedDataStore` for Rebirths / DNA / Kills, physical podiums in the Forest spawn | none exist today |
| 5.4 | `[ ]` | 📢 **Cross-server announcements** — `MessagingService` on Legendary hatches and Colosseum kills | players advertise the eggs for you |
| 5.5 | `[ ]` | 👥 **Group / Like / Favourite rewards** | grows the group, which is the update-notification channel |
| 5.6 | `[~]` | 🎡 **Free daily spin** — done. `data.LastFreeSpin`, `RewardService.GetFreeSpinStatus` / `HandleFreeSpin`, `Remotes.ClaimFreeSpin`, and a gold button in the Daily panel that becomes a countdown. **It calls `RobuxShopService.GrantSpin`, which Phase 3 made public for exactly this** — the wheel is luck-shifted, its weights are normalised by segment count and its expected value sits below the 99 R$ flat pack, and a second copy here would be a second thing to keep balanced. Same UTC day boundary as the login reward, so both roll over together. **The stamp is written before the grant** with no yield between, the rule the code redemption follows. Rewarded Ads are the other half and are 👤 OWNER | live: button read **FREE SPIN!**, a claim rolled a real segment (`🧬 DNA Surge`), stamped `LastFreeSpin` and flipped the button to **`🎡 5h 11m`**; a second claim the same day was refused and did **not** re-roll. Geometry at authored size: streak card x22..262, button x458..678, day grid from y=100 — no collision, nothing clipped. The countdown ticks only while the panel is open |
| 5.7 | `[ ]` | 📖 **Journal rarity percentages** ("0.3% of players own this") via a global counter | the Journal grid already exists; this is a data layer on top |

---

## Phase 6 — Juice and onboarding

| ID | | Task | Verified how |
|---|---|---|---|
| 6.1 | `[ ]` | **Hatch sequence**: egg shakes → cracks → rarity flash → pet rises. Currently a popup card; reuse `worldPopup` / `celebratePurchase` | screen capture |
| 6.2 | `[ ]` | **Rarity beam** into the sky on Legendary, paired with 5.4 | visible from across the platform |
| 6.3 | `[ ]` | **First-join sequence**: camera pan → "TAP TO EVOLVE" arrow → first evolve celebrated. Zones 1–2 are already designed as the tutorial stretch but nothing guides the player | fresh save in Play |
| 6.4 | `[ ]` | **Boost strip with timers** — extend the potion strip (`hudRefs.potionTimers`, `MainUI:1298`) with pass icons and countdowns | `loadstring` OK + capture |
| 6.5 | `[ ]` | **👤 OWNER** Game icon and thumbnail — chunky character, big number, high contrast. Decides ~70% of clicks and is not code | uploaded |

---

## Phase 7 — Live ops

| ID | | Task |
|---|---|---|
| 7.1 | `[ ]` | Limited-time event framework: a window, an exclusive skin/pet, a countdown board |
| 7.2 | `[ ]` | Weekend server-wide 2x events (reuses the potion multiplier plumbing) |
| 7.3 | `[ ]` | Seasonal rotation for the Season Pass (`SeasonPassService` already resets by clock) |

---

## Phase 8 — Trading · **do not start until the game is live and stable**

Highest-value retention system in the genre and the largest exploit surface in it. Gated
deliberately.

| ID | | Task |
|---|---|---|
| 8.1 | `[ ]` | Trade request / accept flow with a proximity requirement |
| 8.2 | `[ ]` | Two-sided confirm with a lock-and-recheck step (both inventories re-validated server-side at commit) |
| 8.3 | `[ ]` | Duplication defence: server-authoritative pet ids, atomic swap, both saves written before either is acknowledged |
| 8.4 | `[ ]` | Trade log for support, and a per-player rate limit |
| 8.5 | `[ ]` | Anti-scam: 3-second confirm hold and a final "you are giving / you are getting" summary |

---

## 👤 Owner action checklist

Collect these once; each one blocks agents until it exists.

| | Action | Blocks |
|---|---|---|
| `[ ]` | Roblox group id, for the Group / Like / Favourite rewards | 5.5 |
| `[ ]` | Rewarded Ads set up on the dashboard (the free spin half of 5.6 is done) | 5.6 |
| `[x]` | Save the place into the repo (binary `.rbxl` is fine — `tools/rbxl_extract.py` reads it) | 0.1 — done 2026-08-08 |
| `[ ]` | `StreamingMinRadius` / `TargetRadius` / `IntegrityMode` in Properties | 0.4 |
| `[ ]` | Create the 7 existing developer products, paste ids | 1.7 |
| `[ ]` | Create the 9 game passes, paste ids | 2.11 |
| `[ ]` | Create the 10 new developer products, paste ids (the shop is 17 rows now — see 3.8) | 3.8 |
| `[ ]` | Game icon and thumbnail | 6.5 |

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
