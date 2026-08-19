# Evolution Lab — Viral Readiness Plan · Phases 19–25

## Context

Evolution Lab publishes **4–7 September 2026** (the authored Prism Festival window). Today is
**19 August 2026** — 16 days. Eighteen roadmap phases are closed; the game is genuinely deep:
20 zones, a 100-rung skin ladder, 60 eggs, pet fusion + enchants, relics, a 30-level season pass,
3 leaderboards, codes, offline earnings, live events, a fully-wired trade system, 9 game passes and
19 live developer products.

What has never been designed against is the thing that decides whether a Roblox game in 2026 lives:
**the June 2026 discovery algorithm, which now grades D1 / D2–7 / D8–28 retention, co-play and spend
as separate signals** — and Evolution Lab is, today, a single-player game running in a shared room.
There is no reason for two players to be on the same server. Trading exists and is invisible. There
is no friend bonus, no party, no guild, no PvP, no shared objective except one boss on a 30-minute
timer inside a room you have to teleport to.

**Owner decisions taken 2026-08-19, which this plan is built on:**
1. **Soft launch 4 Sept** — publish without a marketing push, use the first two weeks as the real
   test, then do a **v1.0 relaunch** with icon/thumbnail and the viral mechanic when D1/D7 are good.
2. **All three social directions, phased** — co-play first, mutations second, steal/vivarium third.
3. **Full modernisation** — the core loop is in scope, not just additions.

Because the launch is soft, **Phase 20 (instrumentation) is not optional. A soft launch you cannot
measure is just a quiet launch.**

---

## Part A — What the 2026 market rewards

Researched 2026-08-19; sources at the bottom.

### A1. The algorithm changed toward retention + co-play + spend

Roblox's June 2026 update replaced the single 7-day "qualified play-through rate" with **three
retention windows — D1, D2–7, D8–28** — and split session quality and spend into their own signals.
Official framing: *"creators who build games that create long-term player value through retention,
**co-play**, and spend will have more opportunity."*

- **D8–28 is now first-class.** A game finished in a week is punished. Evolution Lab's depth is its
  structural advantage here — it is the one axis where it already beats most of the market.
- **Co-play is an explicit ranking input.** Sessions with friends are **1.9× longer**. A player who
  adds one friend in week 1 has **3× the 30-day retention**; a guild/community joiner has **4×**.
  This is Evolution Lab's single biggest miss and the cheapest to fix.
- **The 48–72 h launch window sets the ceiling.** New places get one temporary test-audience boost.
  A soft launch deliberately spends that boost on a small cohort to get clean numbers — which only
  works if the funnel is instrumented.

### A2. Benchmarks a simulator is graded against

| | Good | Excellent |
|---|---|---|
| D1 (simulator) | 35% | 40%+ |
| D7 (simulator) | 18% | 20%+ |

Over **80% of lifetime revenue** comes from players who survive week 1. The #1 churn cause is FTUE.

### A3. FTUE rules that are effectively hard numbers

- A simulator player must be **clicking/collecting inside the first 60 seconds**.
- **Every second of non-gameplay in the first 5 minutes costs ~2–3% of the cohort.** A 15-second
  forced cutscene eliminates ~5% before they touch the controls.
- Return drivers by day: **D2** = unfinished business + a visible streak · **D3** = a genuinely new
  zone/ability/mode around 2–3 h playtime (the "Day-3 wall") · **D4–6** = mid-term goals and
  friend/guild joins · **D7** = an exclusive reward **advertised from day 1**.
- End every session with **unfinished business** — a pending reward, a bar at 80%, a timer running.

### A4. What the top games actually do

Fastest-growing categories, Aug 2026: **steal-and-defend tycoons, idle-grow simulators, co-op
horror, anime fighters, fashion social.**

**Steal a Brainrot** (peak 24.8M CCU — the most-played game in history):
- Loop is **acquire → grow → defend → steal**. Value constantly changes hands.
- A base carries a **60 s lock (+10 s per rebirth)**; a thief's movement speed drops hard, their
  items are disabled, **the owner is notified instantly**, and any player can hit them to return it.
- 9 rarity tiers; Legendary guaranteed every 5 min, Mythic every 15 min, Secret/OG random.
- Income is per-second and **visible on the base**: Common $1–14/s → Brainrot God $250K–295K/s.
- **The virality engine is other people's reactions** — tens of millions of clip views of steals and
  of kids crying after losing a unit. The clip *is* the marketing.

**Grow a Garden** (fastest game ever to 1B visits — 33 days):
- **Offline growth** — a 2-minute login feels productive, and there is no penalty for leaving.
- **Mutations are multiplicative value multipliers**, Glossy ×10 → Voidtouched ×135, and **two
  mutations on one item multiply, not add.** Weather events trigger them.
- Trading is the social loop; the flex is that other players **can see your garden**.

**Pet Simulator 99:** eggs → luck → index → prestige → trading → seasonal events, layered.

**Universal across all three: limited-time "admin" events with exclusive characters are the engine
of both engagement and revenue.**

### A5. Monetization shape

- Price ladder everywhere: entry pass **49–99** → core multipliers **149–299** → premium **399+**.
- **A discounted starter pack is the highest-leverage missing product** — ~95% of players who spend
  once spend again. Evolution Lab has 19 products and no starter pack.
- Rotating "this weekend only" offers drive impulse purchases.
- **Roblox Moments** (in-app TikTok-style 30 s clip feed, jump-into-experience from a clip, source
  released to developers) makes *designing for the clip* a first-party distribution channel.

---

## Part B — Honest audit of Evolution Lab

### B1. What is already strong (do not rebuild it)

- **Content depth.** 20 zones × 39 creatures, 100 skin rungs, 60 eggs, 4 pet tiers, 6 enchants,
  15 relics — this is D8–28 fuel most competitors don't have.
- **Reward cadence is complete at every scale**: 15-min relic chest, 10/20/30/45/60-min playtime
  gifts, daily login + free spin + 4 daily quests, 3 weekly quests, weekend event, 30-day season.
- **The economy is honest.** `ScaleReward` keeps flat grants meaningful in an exponential economy;
  `GetAutoCollectAmount` is expressed as a *fraction of one click/sec* so **active > idle > offline
  by construction** (tops out at 2.04 clicks/sec).
- **FTUE is already tuned better than most.** The first evolve costs **1 XP, not 50**
  (`Evolution.lua:75`) — time-to-first-evolve is ~10–20 s after the loading wipe. The camera pan is
  3.4 s, well under the 15 s that costs 5% of a cohort.
- **Server-side authority is clean.** No remote handler anywhere takes a client-supplied numeric
  amount; charge-before-grant with no yield holds in every currency sink checked.

### B2. The gaps, ranked by what they cost

| # | Gap | Why it matters |
|---|---|---|
| **G1** | **No co-play of any kind.** No friend bonus, no party, no guild, no invite reward. `FriendInviteButton.lua` counts friends and opens the invite prompt — that is the whole social layer. | Directly one of three named algorithm signals. Friend = 3× D30, guild = 4×. |
| **G2** | **Trading is fully built and invisible.** All 7 remotes live (`TradeService.lua:687-722`), `TradePanel.lua` is 1,011 lines, row 8.6 is `[x]` — but the only door is clicking another player in the world. **No HUD tile.** | The social loop of every game in the reference set, shipped and unusable. |
| **G3** | **Nothing is contested or shared.** The Colosseum giant (30-min respawn) is the only shared activity and it is behind a teleport into a separate arena. | No reason for two players to co-exist; no clippable moment. |
| **G4** | **No flex surface.** `StatsService` computes global ownership percentages, but you cannot look at another player, see their creature, or see what they own. | Flex is what makes a collection worth collecting. |
| **G5** | **No starter pack**, and no rotating limited offer. | The highest-leverage first-purchase mechanic, absent. |
| **G6** | **Zero analytics.** No `AnalyticsService`, no funnel, no economy events. | You are about to soft-launch to *measure*, with no instrument. |
| **G7** | **Daily ladder does not loop.** 7 days, then it stops escalating. Playtime gifts reset every rejoin, so there is no *daily* playtime ladder. | D8–28 has no daily hook of growing value. |
| **G8** | **`GameConfig.RobloxGroupId = 0`** (`Rewards.lua:29`) — the +10% DNA, the group chest and the whole community reward tree ship against no group. | Owner-blocked, and it is also the guild substitute Roblox gives you for free. |
| **G9** | **Icon + thumbnail do not exist** (row 6.5). | Icons don't affect ranking directly but they set CTR, and CTR is read as a quality signal. Top-of-genre play-through rate is ~3.6%. This is the single gate on every other number in this plan. |
| **G10** | ~~**~600 lines of dead panels** (`zonesPanel`, `rebirthPanel`, `robuxPanel` — row 18.12) still built and refreshed on every `DataUpdate`, opened by nothing.~~ **CLOSED 2026-08-20:** 437 lines and 1,956 instances removed, HUD 12,316 → 10,360 descendants. The estimate was close and the diagnosis was half right — `robuxPanel` was opened by four things, not by nothing; see 18.12. Plus `InventoryPotionsTab.lua`, required by nothing. | Wasted frame time on exactly the low-end device a new player is on. |
| **G11** | **Two documents actively lie.** `ROADMAP.md:309-311` and `TradeService.lua:4-19` both say trading is unwired. It is fully wired. | The next cold agent will believe them. |

---

## Part C — Bugs found (ranked; #1 and #2 re-verified by hand)

| # | Severity | Defect |
|---|---|---|
| **C1** | **Critical — paid content that pays nothing** | **Banked Relic Chests can never be opened.** The Lucky Wheel's `relic` segment (weight **5**, so ~1 in 20 of every 99 R$ spin, 25-shard spin and free daily spin) calls `RelicService.GiveChest` → `data.RelicChests += 1` (`RelicService.lua:87`). `SpinReveal.client.lua:96-98` tells the player *"1 Relic Chest — open it in the Forge."* **`HandleOpenChest`'s `"banked"` branch (`RelicService.lua:113-120`) is sent by nothing** — the only two `OpenRelicChest:FireServer` calls are `RelicsPanel.lua:245` (`"free"`) and `:258` (`"diamonds"`). The panel never reads or displays `data.RelicChests`, and the field is not even in `defaultData()` (`PlayerDataService.lua:100-104`). **Verified by grep: exactly one occurrence of `"banked"` in `src/`, and it is the handler.** Worse, an unknown `source` falls through to the free-timer branch, so the only players who can spend these are exploiters. |
| **C2** | **High — silent loss of a paid moment** | **One error in the spin reveal kills the Lucky Wheel for the whole session while the server keeps charging.** `SpinReveal.client.lua:760-775`: `draining` is cleared only on normal loop exit, and `buildShell`/`buildWheel`/`buildFurniture`/`buildBurst`/`buildCaption` at `:654-689` run **outside any `pcall`** (the `pcall` at `:691` wraps only the animation, in a separate `task.spawn`). Any error there strands `draining == true` permanently: every later `SpinResult` is queued and `drain()` returns at `:761`. Player pays Robux/shards/their free daily, server grants normally, **client shows nothing** — the notify fallback was deliberately removed (`RobuxShopService.lua:181-201`). Unrecoverable without rejoin. |
| **C3** | **High — new-player tutorial can silently never run** | `FirstJoin.client.lua:639-645` falls back to `Remotes.GetData:InvokeServer()`. **There is no `RemoteFunction` and no `OnServerInvoke` anywhere in `src/` — verified by grep, zero hits.** So the fallback is dead code that also blocks the thread for 10 s. What it existed to catch is real: if `PlayerDataService`'s `PushToClient` (`:642`) lands before `FirstJoin` reaches its `DataUpdate` connect at `:637` (after 7 `WaitForChild`s, 5 `require`s and building a ScreenGui + 8 chevron Parts), `state.data` stays `nil`, `runGuide()` never fires, and the banner/arrow/trail/pan never appear. Self-heals only on the next push. |
| **C4** | Medium — latent, brand-new shared kit | `CardKit.Button`/`Card` capture the **raw** `opts.colors` into `baseColors` (`CardKit.lua:182`) while the visual default fills in `{WHITE, WHITE}` at `:144, :176`. A button built without `colors` renders, greys on `SetEnabled(false)`, then throws `attempt to index nil` in `SetGradient` (`:70-75`) the moment it is re-enabled. All six current callers pass `colors`; the next one won't. Same file: `Pill` at `:223` uses `opts.transparency or 0.18`, so an explicit `0` silently becomes `0.18`. |
| **C5** | Medium — perf on exactly the wrong device | `FirstJoin.client.lua:345-348` `findEvolveButton()` does a **recursive** `FindFirstChild` over the whole `EvolutionLabUI` (built by 5,229 lines of MainUI) **every Heartbeat** while the player is in the "ready to evolve" step (`:557`). |
| **C6** | Low-medium | `FirstJoin`'s `marker` (BillboardGui) and `pointHL` (Highlight) are parented to the ScreenGui (`:355, :380`) but are not `GuiObject`s, so `gui.Enabled = false` does not hide them. Open the Store or Relics panel and the creature stays outlined with a beacon floating over it, behind the panel. |
| **C7** | Cosmetic / world | `[SplicerService] preferred spot was occupied; machine moved 260 studs to (120, 30)` — live console, this session. The Splicer is a feature the player is meant to find; 260 studs from its intended spot is a different place. This is the known blind-forward placement-search behaviour. |

**Clean, so nobody re-checks it:** the whole relic feature is otherwise correctly wired (Init called,
all 4 remotes paired, multipliers actually consumed by `DNAService`/`Pets`/`RobuxShop`, save
migration present, rebirth does not wipe relics, all 15 icon keys resolve). `luascope` and
`luastruct` are clean; `luaremotes` finds only C3; MainUI sits at **160/200** registers with real
headroom. `processReceipt` correctly returns `NotProcessedYet` on unknown product and failed save.

---

## Part D — The phased plan

Each phase below becomes a section in `ROADMAP.md` with the project's usual table, and closes only
on **live verification in Studio**, per the roadmap's own rule.

---

### Phase 19 — Launch hygiene · *ship before 4 September*

Nothing here is new design. It is "nothing paid is lost, nothing visible is broken."

| ID | Task | Files |
|---|---|---|
| 19.1 | **Make banked relic chests spendable (C1).** Add `RelicChests = 0` to `defaultData()`; add a third button to the Forge, gated on `data.RelicChests > 0`, sending `"banked"`; show the count on it. Make the unknown-`source` fallthrough **reject** instead of falling into the free timer. | `PlayerDataService.lua:100`, `RelicsPanel.lua:236-260,628`, `RelicService.lua:110-131` |
| 19.2 | **The spin reveal can never wedge (C2).** Wrap `:654-689` in the same `pcall`; clear `draining` in a `finally`-shaped guard so the flag is released on any exit; bound the re-queue retry to N attempts and drop the payload with a toast after that. | `SpinReveal.client.lua:654-775` |
| 19.3 | **Close the FirstJoin data race properly (C3).** Delete the dead `GetData` fallback (and its 10 s block). Replace with the pattern the rest of the client uses: have `PlayerDataService` re-push once ~1 s after `PlayerAdded`, or expose the last payload on a `StringValue` the way `LiveEvents`/`StatsService` already do (no new remote needed). | `FirstJoin.client.lua:637-645`, `PlayerDataService.lua:622-642` |
| 19.4 | **CardKit `baseColors` (C4).** Default `baseColors` to the same `{WHITE, WHITE}` the construction path uses; change `Pill`'s `or 0.18` to an `if opts.transparency ~= nil` test. | `CardKit.lua:144,176,182,223` |
| 19.5 | **Hoist `findEvolveButton` (C5)**, re-resolving only when nil or reparented. **Hide `marker`/`pointHL` on panel open (C6)** — call `pointAt(nil)` from the panel watcher. | `FirstJoin.client.lua:130-145,345-348` |
| 19.6 | **Finish the Phase 18 grey-UI pass.** Rows **18.6** (Season panel's two progress bars), **18.7** (SplicerUI is its own ScreenGui and misses every pass), **18.8** (a caption handed to a shell disappears — the `InnerBody` shell rule, fourth time shipped), **18.10** (the ZoneBuilder split owes a rebuild + capture), **18.12** (delete the three dead panels, ~600 lines — but **move the game-pass column into `ShopPanel` first**, it lives only in the old panel). Also delete `InventoryPotionsTab.lua`. | `SeasonPass.lua`, `SplicerUI.client.lua`, `CardKit`/shell helpers, `MainUI.client.lua`, `ShopPanel.lua` |
| 19.7 | **Fix the two lying documents (G11).** `TradeService.lua:4-19` header and `ROADMAP.md:309-311` both claim trading is unwired. | `TradeService.lua`, `ROADMAP.md` |
| 19.8 | **Splicer placement (C7)** — give the Splicer a reserved spot claimed before the boards, or an explicit authored position, so it stops landing 260 studs away. | `SplicerService.lua` |
| 19.9 | 👤 **OWNER — the launch gates.** Game **icon + thumbnail** (row 6.5, this is G9 and it gates everything else); **Roblox group id** (5.5 / G8); **one real Robux purchase** (closes 1.7 / 2.11 / 3.8 / 11.12); **streaming radii** in Properties (0.4); **save + republish** to make 16.9's six skin meshes and 15.10's backdoor deletion real. | Dashboard / Properties |

---

### Phase 20 — Instrumentation · *ship before 4 September — this is the point of a soft launch*

You chose a soft launch to get clean D1/D7 numbers. Right now the game emits nothing. Roblox's
`AnalyticsService` is free, first-party, and feeds the Creator Analytics dashboard the algorithm
itself reads.

| ID | Task |
|---|---|
| 20.1 | **Onboarding funnel** via `AnalyticsService:LogOnboardingFunnelStepEvent`: `joined → loading done → first swing → first kill → first evolve → tutorial done → first zone change → first egg hatched`. This turns "FTUE is fine" from an opinion into the exact step where the cohort leaves. |
| 20.2 | **Economy events** via `LogEconomyEvent` for every source and sink of DNA / Diamonds / Shards, and for every product and pass. This is how you find the sink that nobody uses and the faucet that inflates. |
| 20.3 | **Custom events** for the moments this plan is about: trade opened / completed, friend in server, world-boss contribution, mutation rolled, spin taken, relic chest opened. Every later phase is judged against a number these produce. |
| 20.4 | **Session-end state** — what the session ended on (bar %, pending reward, timer running). A3 says unfinished business is the D2 driver; this measures whether it exists. |
| 20.5 | **Baseline capture in the first 72 h.** Write D1 / D2–7 / session length / QPTR into `ROADMAP.md` as the number every later phase is compared to. Target: D1 ≥ 35%, D7 ≥ 18%. |

---

### Phase 21 — The first ten minutes and the daily hook · *ship before 4 September if time allows, else launch week*

Cheap, high-yield, no new systems.

| ID | Task |
|---|---|
| 21.1 | **Give trading a door (G2).** An HUD tile that opens the picker, plus a "Trade" ProximityPrompt over nearby players. A shipped 1,011-line panel is currently reachable only by knowing to click a person. |
| 21.2 | **Make the daily ladder loop and escalate (G7).** After day 7 the ladder restarts at a higher tier rather than stopping; the **day-7 reward is shown from day 1** as the aspirational pull (A3). |
| 21.3 | **A persistent daily playtime ladder** beside the session one — the session gifts stay (they correctly reward long sittings), but add a per-UTC-day ladder so a player with three 20-minute sessions is also served. |
| 21.4 | **Guarantee unfinished business at session end.** When a player is about to leave (or on a 10-minute idle), make sure at least one of: a bar over 80%, a claimable pending reward, a running timer. Instrumented by 20.4. |
| 21.5 | **Audit the Day-3 wall (A3).** Chart what is genuinely *new* at 2–3 hours of play. Today that is zone 2 + the first boss key. If the answer is "the same loop with bigger numbers", introduce one new verb there — the terraces already exist but are rebirth-gated, which is far past hour 3. |
| 21.6 | **Starter pack (G5).** One discounted first-purchase bundle at 49–99 R$ — DNA + diamonds + a short potion + a cosmetic — shown once, to players who have never spent, with a visible discount. 👤 needs a dashboard product id. |

---

### Phase 22 — Co-play · *weeks 1–2 after launch*

The cheapest algorithmic win in this document. Directly feeds a named ranking signal.

| ID | Task |
|---|---|
| 22.1 | **Friends-in-server bonus.** +X% DNA per friend on the server, capped (e.g. +10% each to +40%), shown as a live HUD pill: *"3 friends here · +30% DNA"*. Sessions with friends are 1.9× longer; this makes that visible and rewarded. |
| 22.2 | **Invite reward.** `FriendInviteButton.lua` already opens the prompt — pay for the *join*, not the click: when an invited player joins, both get diamonds. |
| 22.3 | **The group is real (G8).** Fill `RobloxGroupId`; the +10% DNA, the daily group chest and the Like/Favourite rewards all activate. This is the guild substitute Roblox gives you free, and the 4× retention number attaches to it. |
| 22.4 | **The world boss leaves the arena.** The Colosseum giant already tracks `contributors` and pays everyone who damaged it (`BossService.lua:2650,2736-2760`). Move it — or a sibling — into the **hub**, visible from spawn, with a countdown on the HUD, a live contribution board, and a server-wide payout. One shared objective everybody can see is what makes a server feel populated. |
| 22.5 | **Party support.** Roblox's Party API groups up to 6 friends into the same server; give a party a visible team treatment and a shared bonus. |

---

### Phase 23 — The flex economy · *weeks 2–4*

The Grow a Garden engine, built on the Splicer that already exists. Zero grief risk, high flex.

| ID | Task |
|---|---|
| 23.1 | **Mutations become multiplicative value multipliers.** Today the Splicer is a gacha priced in kills with pity every 10. Turn its output into a stat that multiplies a creature's or pet's value, and make **two mutations on one thing multiply, not add** — that is precisely what produces Grow a Garden's ×135 outliers and the screenshots that travel. |
| 23.2 | **Mutations are visible from across the map.** The rented-Highlight pool and the VFX attach rules already exist. A mutation nobody can see is not a flex. |
| 23.3 | **Server-wide announce for the top tier.** `AnnounceService` + `RarityBeam` already carry Legendary hatches, Mythic mutations, apex kills and rebirths cross-server. Add the top mutation tier, with the beam, and rate-limit it via the existing `KIND_COOLDOWN`. |
| 23.4 | **Mutated creatures are the tradable prestige object.** Trading is pets-only today for a good reason (DNA is stage-scaled and has no agreed value). A mutation is a fixed multiplier — it *does* have an agreed value, which is what makes a player-driven economy possible. |
| 23.5 | **Turn the Journal into an index with completion rewards.** `StatsService` already publishes "0.3% of players own this". Add set-completion payouts and make the rarest line in a player's index visible to others. |
| 23.6 | **Weather / world events trigger mutations.** `EventService` already polls windows and publishes `LiveEvents`. A live window that makes mutations more likely is the mechanic that makes an event *worth logging in for* rather than just a multiplier. |

---

### Phase 24 — The Vivarium · *weeks 4–8 · the big swing*

This is the acquire → grow → **defend → steal** loop, and it changes what genre this game is.
Flagging that plainly: it is the mechanic with the highest viral ceiling and the highest risk — the
reference game's virality is literally built on clips of children crying.

**Recommendation: build it in two switchable stages, soft first.**

| ID | Task |
|---|---|
| 24.1 | **The Vivarium plot.** Every player gets a display in the hub with N slots (scaling with rebirths, per the reference's floor system), showing their best creatures and a **visible passive DNA/second** above it. This alone delivers G4 (flex) and gives players a reason to look at each other. It is worth shipping even if 24.3 never ships. |
| 24.2 | **The lock.** A plot is locked for 60 s (+10 s per rebirth) and vulnerable after — copied directly from the reference because the number is proven. Locked/unlocked is visible from a distance. |
| 24.3 | **Soft steal (default).** What a thief takes is the **income stream, not the save item**: carrying a specimen out diverts a share of that plot's passive DNA to the thief for a window, and the original stays in the owner's collection. All the drama, none of the permanent loss. |
| 24.4 | **The steal is a designed clip.** Movement speed drops hard, items disable, **the owner is notified instantly**, any player can hit the thief to drop it, and the whole thing lands in the kill feed. Roblox Moments is a first-party feed now — this is the moment that goes into it. |
| 24.5 | **Anti-grief, non-negotiable.** New-player immunity window; one steal per target per N minutes; a per-thief cooldown; nothing stealable below a rebirth threshold; an opt-out that costs the plot's contested bonus rather than being free. |
| 24.6 | **Hard steal, behind a switch.** Only if the numbers from 24.3 justify it, and only as a config flag that can be turned off in one line without a code change. |

---

### Phase 25 — Live ops and the real push · *from week 6, ongoing*

| ID | Task |
|---|---|
| 25.1 | **A content calendar, not a backlog.** Small weekly (a code, a rotating offer, a limited pet), large monthly (a zone, an event, a season). Every reference game's engagement is a function of its update cadence. |
| 25.2 | **Limited-time events with an exclusive character.** The frame exists — `GameConfig.Events` holds both window shapes, effects reuse the pass field names, and event skins already live in `data.EventCharacters` so a rebirth doesn't wipe them. This is the engine of both engagement and revenue in every game in the reference set; it is currently three windows. |
| 25.3 | **Rotating weekend offers** on the existing shop, with a visible timer. |
| 25.4 | **The v1.0 relaunch.** New icon + thumbnail (test more than one — CTR is read as a quality signal), codes seeded to creators, Moments clips cut from 23.3 and 24.4 moments, and the push timed to a live event window. |
| 25.5 | **Re-measure against the Phase 20 baseline** and write both numbers into the roadmap. |

---

## Part E — Verification

Every row closes the way this project always closes rows: **live in Studio, with numbers.**

- **C1** — spin until the relic segment lands (or grant `data.RelicChests` directly on a restored
  test save), confirm the Forge shows a count, open it, confirm the count decrements and a relic
  arrives. Control: confirm the free-timer branch did **not** fire.
- **C2** — deliberately throw inside `buildWheel`, then fire three more `SpinResult` payloads and
  confirm all three still render.
- **C3** — reach the join-only branch with the technique the roadmap already records (a synthetic
  `DataUpdate` plus a fresh `MainUI` clone), and confirm the guide runs when the push wins the race.
- **19.6** — a **screen capture**, not a lint pass. The project's own rule: 236 surfaces reporting
  the right `.Text` is not evidence about a picture.
- **Phase 20** — the funnel must show a non-zero count at every step in the Creator Analytics
  dashboard within 24 h of the soft launch.
- **Phases 21–25** — each row is judged against the Phase 20 baseline, not against an opinion. A row
  that does not move a number it predicted is reported as such, not quietly closed.

Standing rules that apply to every row: run `luascope.py`, `luastruct.py`, `luaremotes.py` and the
register count before pushing; hash-sweep `src/` against Studio at session start; never add a
top-level `local` to `MainUI` (160/200, but the rule stands); read `ZoneBuilder`'s edit wall before
touching it.

---

## Part F — Owner-blocked, in priority order

1. **Game icon + thumbnail** — gates every number in this plan (G9).
2. **One real Robux purchase** — the only thing that exercises `ProcessReceipt`.
3. **Roblox group id** — activates a whole reward tree that already exists (G8).
4. **Save + republish** — 16.9's six generated skin meshes exist only in an unsaved Studio session;
   15.10's backdoor deletion is not real until a republish.
5. **Streaming radii** in Properties (row 0.4) — unreachable from code, measured.
6. **Rewarded Ads** on the dashboard (5.6b).
7. **Product ids** for the starter pack (21.6).

⚠️ **Studio is in Play mode right now.** `GEMINI.md` rule 7: Studio grants every game pass, so VIP
Auto Hatch runs continuously and spends the real save. One session cost 50 Diamonds and filled the
pet bag to its 100 cap. It should be stopped.

---

## Sources

- [Optimizing Discovery: How Great Games Reach Millions of Players on Roblox — Roblox Newsroom, June 2026](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox)
- [How the Roblox Discovery Algorithm Works in 2026 — ROLearn](https://rolearn.dev/insights/roblox-game-discovery-algorithm-2026/)
- [First Week Retention: Optimizing Day-1 Through Day-7 — ROLearn](https://rolearn.dev/guidance/first-week-retention-optimization/)
- [The Algorithm Behind 'Steal a Brainrot' — Andy Hall, Free Systems](https://freesystems.substack.com/p/the-algorithm-behind-steal-a-brainrot)
- [Steal a Brainrot Wiki — base locks, floors, income, rarities](https://steal-a-brainrot.wiki/)
- [Steal a Brainrot — Wikipedia](https://en.wikipedia.org/wiki/Steal_a_Brainrot)
- [Grow a Garden Mechanics — Fandom](https://growagarden.fandom.com/wiki/Mechanics)
- [Roblox trends in gaming: genres, mechanics, platform — Game-Ace](https://game-ace.com/blog/roblox-trends-in-gaming/)
- [Introducing Party on Roblox — Roblox Newsroom](https://about.roblox.com/newsroom/2024/12/join-the-party-on-roblox)
- [Roblox announces short-form video feed (Moments) — TechCrunch](https://techcrunch.com/2025/09/05/roblox-announces-short-form-video-feed-for-gameplay-clips-new-ai-tools-for-creators-and-more)
- [Roblox Game Pass Pricing Guide 2026 — UGCcraft](https://ugccraft.com/blog/roblox-game-passes-pricing-guide/)
- [Roblox Game Monetization Guide 2026 — Obby](https://www.obby.fun/blog/roblox-monetization-guide)
