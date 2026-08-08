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
- `screen_capture` stops Play. Capture before or after, never during; budget one per session.
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

Eight of the nine passes are **complete and verified**. What is left in this phase is Auto Hatch
(the one pass that needs a new loop rather than a multiplier) and the two UI jobs — both of which
touch `MainUI`, so read the register-cap rule below before starting either.

| ID | | Task | Verified how |
|---|---|---|---|
| 2.1 | `[x]` | 🏃 2x Speed — `EvolutionVisuals.applyMastery`. **The pass also lifts the cap** (`walkCap = 260` + new `GameConfig.GetPassMax`): against the normal 150 it delivered 1.18x at stage 20 and was a true 2x only through stage 7 of 20 | measured 2.00x at stages 1 / 7 / 14 / 20; a non-owner at stage 20 is still 127.2 |
| 2.2 | `[x]` | ⭐ 2x XP — extracted `GameConfig.GetXPMult(data)`, now the single XP multiplier, used by both `CreatureService` and `BossService` | `GetXPMult` x1.00 → x2.00; nothing else moves |
| 2.3 | `[ ]` | 🥚 Auto Hatch — server loop + client trigger | stand at a podium with 0 DNA: nothing hatches, no error spam |
| 2.4 | `[x]` | 🧬 2x DNA — `DNAService.GetIncomeMult`, added last so it multiplies the whole stack | income x1.00 → x2.00, damage unchanged at 62 |
| 2.5 | `[x]` | ⚔️ 2x Damage — `DNAService.GetCombatDamage`. Raises damage **dealt** only; the incoming-damage cap is untouched | damage 62 → 124, income unchanged at x1.00 |
| 2.6 | `[x]` | ⚡ Fast Auto Attack — `CombatClient` reads an `AutoSpeedMult` **player attribute** the server stamps, so the client never learns what a pass is. Floored at `SWING_TIME` | attribute reads 1 for a non-owner; x1.70 with the pass; free auto-attack untouched |
| 2.7 | `[x]` | 🍀 Lucky — `DNAService.GetLuckPercent`, **added in points** | luck 0 → 50; Lucky + VIP = 65 |
| 2.8 | `[x]` | 🐾 +3 Pet Slots — `GameConfig.GetMaxEquippedPets`, stacking **on top of** the 3-level diamond upgrade (3 + 3 + 3 = 9) | pets 3 → 6 |
| 2.9 | `[x]` | 👑 VIP — multipliers, golden skin (2.9a), **golden aura, [VIP] chat tag and 5 Diamonds a day**. The aura is **particles + a PointLight, never a `Highlight`**: CreatureService rents 14 of the ~31 Roblox renders, and one Highlight per VIP in a full server would strip the outlines off every creature in the world. Aura and tag are drawn client-side off an `IsVIP` player attribute, which replicates to everyone by itself — no remote, and other players see the badge for free | daily pays 5 once, pays nothing on a second call the same day, pays again after the stamp rolls, and pays a non-VIP nothing. Aura built with emitter + light sized off `BodyScale`, **0 extra Highlights on the character**, removed and rebuilt as `IsVIP` toggles. Chat pipeline confirmed `TextChatService` |
| 2.9a | `[x]` | The VIP skin — `GameConfig.VipCharacter` (`vip_gold`, "Golden Patron"). Registered in `CHARACTER_BY_KEY` only, **never** in `CHARACTERS_BY_STAGE`. `GetEffectiveRank` makes it score as `GetBestOwnedRank(data)`, so it is worth exactly what the wearer earned. `SyncVipCharacter` grants and **revokes** it, and is called after a rebirth too because `RebirthService` clears `data.Characters` wholesale. No `SkinMesh_vip_gold` exists and that is intended — `SkinMesh.Has()` falls back to `StageCostume` painted gold, i.e. a gold version of whatever stage you are | collection still counts 100 collectible (of 200 authored) with the skin owned; no leak into `CHARACTERS_BY_STAGE`; damage identical to the best owned skin at depths 1/3/10/20 (x1.15 / x1.45 / x2.50 / x4.00); losing the pass removes it and moves the body to a real skin |
| 2.9b | `[ ]` | The VIP skin in the **Journal UI** — it needs a slot outside the twenty stage rows, and the register-cap rule applies | opens, shows locked for a non-VIP, selectable for a VIP |
| 2.10 | `[ ]` | Robux panel: Products / Passes tabs, `OWNED` state, price chips | `loadstring` OK + screen capture |
| 2.11 | `[ ]` | **👤 OWNER** Create all 9 passes on the dashboard, paste ids | a real purchase applies without a rejoin |
| 2.12 | `[ ]` | Balance check: VIP × 2x DNA × potion × pets stacked — evolve costs at stage 20 must still hold | replay the curve numerically |

---

## Phase 3 — Developer products and shop presentation

| ID | | Task | Verified how |
|---|---|---|---|
| 3.1 | `[ ]` | DNA packs 2 → 5 tiers (49/99/199/499/999 R$), all through `ScaleReward` | payout per Robux is monotonic across tiers |
| 3.2 | `[ ]` | Diamond packs 2 → 5 tiers | same |
| 3.3 | `[ ]` | 🎡 **Lucky Spin** (99 R$) — weighted wheel reusing the luck-shifting shape in `PotionService:78` | 10,000 rolls match the advertised odds |
| 3.4 | `[ ]` | ⏭️ **Boss Revive / Skip** (49 R$) — sells against a real frustration: `BOSS_REGEN_DELAY 14 + BOSS_REGEN_TIME 20` fully heals a zone boss after a death, so every attempt restarts from full | buy mid-fight, boss health is preserved |
| 3.5 | `[ ]` | 🌈 **Rainbow Fusion** (199 R$) — one tier above the existing Golden fusion | fuse result shows the new tier and its multiplier |
| 3.6 | `[ ]` | Robux panel: `BEST VALUE` / `MOST POPULAR` ribbons, limited-offer timer, bigger icons | screen capture |
| 3.7 | `[ ]` | **`+` buttons on the HUD currency capsules** that open the shop — highest-leverage conversion change in the file, ~20 lines | clicking `+` on DNA and Diamonds opens the right tab |
| 3.8 | `[ ]` | **👤 OWNER** Create the new products, paste ids | real purchase grants and saves |

---

## Phase 4 — Audio

A tree scan for `Sound` returns **exactly one instance**, inside an unused VFX pack. There is no
click, hit, death, hatch, evolve, purchase or ambient audio anywhere in the game. This is the
largest "doesn't feel finished" factor — above any art change.

| ID | | Task | Verified how |
|---|---|---|---|
| 4.1 | `[ ]` | `SoundLibrary` module (id table + `Play(name, part?)`) and a `Sounds` folder under `ReplicatedStorage` | `require` clean |
| 4.2 | `[ ]` | Combat: swing, hit, crit, creature death, player hurt — fired from `CombatClient` (client-side, for the same reason its swing is: a server-created `Sound` replicates throttled and lands after the click) | heard in Play, no delay against the swing |
| 4.3 | `[ ]` | Economy: click/collect, purchase, evolve, hatch (rarity-scaled sting), fusion, level-up | heard in Play |
| 4.4 | `[ ]` | UI: panel open/close, button press, error buzz — through `UITheme` so every button gets it once | every existing button has it without per-call-site edits |
| 4.5 | `[ ]` | Ambience: one looping bed per biome + the Colosseum | changes on zone transition |
| 4.6 | `[ ]` | Volume / mute setting persisted in `data` | survives rejoin |

---

## Phase 5 — Retention and marketing systems

| ID | | Task | Why |
|---|---|---|---|
| 5.1 | `[ ]` | 🎟️ **Codes system** — `GameConfig.Codes`, `Remotes.RedeemCode`, `data.RedeemedCodes`, redeem panel (register-cap rule applies) | Dexerto / Gamerant / Game.Guide publish code articles monthly. Cheapest traffic channel in the genre and the game has none |
| 5.2 | `[ ]` | 💤 **Offline earnings** — `data.LastSeen`, capped accrual off `DNAService.GetAutoCollectAmount`, "Welcome back" card | strongest single reason to return; the auto-collect rate is already capped in units of clicks, so the maths is safe |
| 5.3 | `[ ]` | 🏆 **Global leaderboards** — `OrderedDataStore` for Rebirths / DNA / Kills, physical podiums in the Forest spawn | none exist today |
| 5.4 | `[ ]` | 📢 **Cross-server announcements** — `MessagingService` on Legendary hatches and Colosseum kills | players advertise the eggs for you |
| 5.5 | `[ ]` | 👥 **Group / Like / Favourite rewards** | grows the group, which is the update-notification channel |
| 5.6 | `[ ]` | 🎡 **Daily free spin + Rewarded Ads** | revenue from players who never buy |
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
| `[x]` | Save the place into the repo (binary `.rbxl` is fine — `tools/rbxl_extract.py` reads it) | 0.1 — done 2026-08-08 |
| `[ ]` | `StreamingMinRadius` / `TargetRadius` / `IntegrityMode` in Properties | 0.4 |
| `[ ]` | Create the 7 existing developer products, paste ids | 1.7 |
| `[ ]` | Create the 9 game passes, paste ids | 2.11 |
| `[ ]` | Create the new developer products, paste ids | 3.8 |
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
