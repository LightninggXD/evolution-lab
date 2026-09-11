# CONTENT-CALENDAR — what changes for the player, week by week and month by month

**Roadmap row 25.1.** Every number below was read out of the running game on **2026-09-11**, not
typed from memory: the weekly grid at one-minute resolution over a clear week, the season and
champion cycles walked forward seventy days, and the one hole at the end of §4 found by the sweep
rather than by a hunch.

This is a calendar and not a backlog, and the difference is the whole point of the row. A backlog is
a list of things somebody would like to build. A calendar says **what a player who logs in on a
given day finds different**, and it keeps saying it after everyone has stopped maintaining it.

---

## 0. The one rule: a beat is generated, or it rots

Two kinds of content are scheduled in this game and only one of them survives neglect.

| | shape | what happens when nobody touches it for a year |
|:--|:--|:--|
| **Generated** | `recurring = { wday, hour, hours }`, `SeasonEpoch + n x 30 days` | keeps producing beats, for ever, on every server, with no live-ops job to miss |
| **Authored** | `fixed = { from = {...}, to = {...} }` | happens once and then is silently over |

`GameConfig.SeasonEpoch` already carries this argument in full — *"a season that only rotates when
somebody remembers is not a season, it is a permanent pass with an optimistic name"* — and the four
recurring events were written the same way. **Everything in §1 and §2 therefore needs no
maintenance at all.** It is §4 that needs a person.

**The guard (25.1).** `GameConfig.GetDeadEvents(now)` returns every authored event that has already
happened and has no occurrence left, and `EventService.Init` reads it once per boot and `warn`s.
It is a `warn` and not an `error` on purpose: a lapsed festival is a live-ops omission, not a broken
server, and an `error` there would take out every service booted after it (21.11's watchdog). It
does not repair the date, because which weekend the festival lands on is the owner's decision.

---

## 1. The weekly beat — **72 of 168 hours**, and where the other 96 are

Measured minute by minute across the week of Mon 2026-10-05, a week clear of any authored window:

| UTC | length | what turns on | lever |
|:--|--:|:--|:--|
| **Wed 12:00** | 24 h | **Splice Surge** — every splice rolls with a charged roll's luck (`mutationLuck 150`) | `Events[SpliceSurge].recurring` |
| **Sat 00:00** | 48 h | **Weekend Rush** (2x DNA, 2x XP) · **Colosseum Clash** (2x giant loot + *this week's* champion) · **Global Challenge** (server goal, 500 diamonds) | three rows, **one window** |

```
Mon 00:00  ---------------- 60 h dark ----------------
Wed 12:00  ###### Splice Surge, 24 h ######
Thu 12:00  ---------- 36 h dark ----------
Sat 00:00  ############ the weekend, 48 h ############
Mon 00:00  -------------------------------------------
```

**The 60-hour stretch from Monday 00:00 to Wednesday 12:00 is the largest hole in the week, and it
is where the next recurring beat belongs.** Splice Surge was added (23.6) for exactly this reason
and against exactly this arithmetic — *"a second beat mid-week is what a calendar is; a fourth thing
stacked onto Saturday would just be a bigger weekend"* — and the measurement says the same job is
now half done. A Monday or Tuesday window would cut 60 h to under 40 h and give the players who
cannot be here at the weekend a **second** day that is theirs.

**Why three events share one window and that is not a mistake.** Weekend Rush, Colosseum Clash and
the Global Challenge open together so a Saturday player finds everything on at once instead of
learning a schedule. `priority` decides which one headlines the board — Global Challenge 20,
Splice Surge 15, Colosseum 10, Weekend Rush 0 — and the HUD card sums every live effect onto one
line, so nothing is lost by not headlining.

---

## 2. The monthly beat — **two cycles that deliberately do not line up**

| cycle | length | next turnovers (measured) |
|:--|--:|:--|
| **Season** — new id, wiped track, new theme | **30 days** | S2 *Deep Currents* -> **2026-09-30** S3 *Ashfall* -> **2026-10-30** S4 *Frostbloom* |
| **Colosseum champion** — four exclusive skins, one a weekend | **28 days** | ember -> frost -> verdant -> onyx, resolved off `window.startTs` |
| **Season Festival** (25.2) — 72 h, double damage, one exclusive Herald | **rides the season** | opens with every turnover above; the Herald is the season's own theme — see §4a |

30 days against 28 means the two never fall on the same day twice running, so **a month reliably has
two separate large beats rather than one loud one.** Six themes at 30 days each means a season
*name* repeats after 180 days while the *number* never repeats.

The season track is **30 levels x 1500 XP = 45,000 Season XP**, fed only by completed quests.

---

## 3. The dated grid

Generated columns are measured. The **ship** column is the commitment: *small weekly, large
monthly*. A slot that cannot be met **slides to the next week — it never empties**, because the
generated beat runs regardless and a missed ship slot costs the update, not the week.

| week opens (UTC) | generated | champion | ship — *small weekly* |
|:--|:--|:--|:--|
| **Sat 2026-09-12** | weekend + Wed 09-16 surge | verdant | ✅ **25.3 SHIPPED 2026-09-11** — rotating weekend offers with the visible timer, in the slot ahead of the weekend it serves. The deal this weekend is **`Shards_2` at +40%** (125 → 175 Evolution Shards for the usual R$ 199); the rotation is five entries against the champion's four, so a pairing repeats after twenty weeks |
| **Sat 2026-09-19** | weekend + Wed 09-23 surge | onyx | **34.58** chests — the 2D and 3D art is already inserted and unused |
| **Sat 2026-09-26** | weekend + Wed 09-30 surge | ember | **30.12** one zone dressed by layout instead of even scatter |
| **Wed 2026-09-30** | *season turnover* + **Season Festival** | — | ✅ **25.2 SHIPPED 2026-09-11** — **LARGE — S3 *Ashfall* opens** and the Season Festival opens with it, 00:00 Wed to 00:00 Sat 10-03, double damage, paying the **Cinder Herald**. It is generated off `SeasonEpoch`, so every later turnover row below carries one too and none of them needed writing down (see §4) |
| **Sat 2026-10-03** | weekend + Wed 10-07 surge | frost | **23.1** mutations become multiplicative |
| **Sat 2026-10-10** | weekend + Wed 10-14 surge | verdant | *champion cycle closes — all four seen once* |
| **Sat 2026-10-17** | weekend + Wed 10-21 surge | onyx | **17.2** first person at the last stage |
| **Sat 2026-10-24** | weekend + Wed 10-28 surge | ember | a Monday/Tuesday recurring beat (§1's 60-hour hole) |
| **Fri 2026-10-30** | *season turnover* + **Season Festival** (Rime Herald) | — | **LARGE — S4 *Frostbloom* opens.** **24.6** hard steal, if and only if 24.3's live numbers justify it |
| **Sat 2026-10-31** | weekend + Wed 11-04 surge | frost | — |
| **Sat 2026-11-07** | weekend + Wed 11-11 surge | verdant | **34.9** fishing — the low-stakes idle activity, held since Phase 34 for a day of live data |
| **Sat 2026-11-14** | weekend + Wed 11-18 surge | onyx | — |

**Defects do not take a slot.** `32.12` — the boss damage divisor that deletes the endgame boss —
ships the day it is fixed. A broken fight is not an update.

**The grid is anchored on weekends, not on launch day.** If launch moves, slide the ship column by
whole weeks; the generated columns need no edit at all, which is the §0 rule paying for itself.

---

## 4. The hole the sweep found, and the one decision that is the owner's

**`PrismFest` closed at 2026-09-07 12:00 UTC with no future occurrence.** It was the only authored
event in the game and the only exclusive skin outside the Colosseum rotation, so as of four days
before this document was written:

- **`event_prism` — the Prism Herald — cannot be earned by anybody, ever.**
- Its four-rung ladder (eggs 60 -> creatures 750 -> fuse 12 -> eggs 180) is still built underneath it.
- The Journal still draws it as a locked row.
- **Nothing anywhere said so.** That is the whole reason §0's guard now exists.

This is the exact fault Phase 26 was opened to close — *"kako se uopste otkljucaju ovi event
likovi"* — reopened by nothing but a date passing.

**OWNER — two lines, and they are a design decision rather than an id.** Unlike a product or a
pass there is nothing to paste from a dashboard; the comment over the row says so and says the dates
are safe to edit. In `src/ReplicatedStorage/Modules/GameConfig/Events.lua`:

```lua
fixed = { from = { 2026, 9, 4, 12, 0 }, to = { 2026, 9, 7, 12, 0 } },
```

Set it to the launch weekend. Nothing breaks while it stays in the past — no effect and no skin is
handed out — but the boot log will keep saying it is gone until it is moved.

**And a rule for the next festival (25.2), so this cannot happen twice:** an authored window is
*allowed* to be one-off, because a limited item is only worth owning if the window shuts (Steal a
Brainrot's 24 retired characters; MM2 removing the lobby, the boxes and the track together). What is
not allowed is the window shutting on the **last** one. A festival ships with the next festival's
dates already authored, or it ships as a `recurring` with a `rotation` like the Colosseum's.

---

### 4a. How 25.2 answered that rule — the Season Festival (shipped 2026-09-11)

**It took the second half of the rule and moved it from the week to the season.** Authoring the next
festival's dates is the first half and it only moves the cliff one month: the month after that, some
person has to remember again. The Colosseum's answer is better because there is nobody to remember
— the window is arithmetic and the skin is a list index — and §0's table already names
`SeasonEpoch + n x 30 days` as a generated shape sitting right beside `recurring`. So the festival
is a **third window shape** on the event engine, `seasonal = { hours = 72 }`, opening the instant a
season turns over.

| | |
|:--|:--|
| **window** | opens at every season turnover, runs **72 hours** — the same length as PrismFest's |
| **effect** | **`damageMult = 2`**, the one effect field the game already routed and no event had ever set |
| **ladder** | four rungs — 300 creatures → 100 eggs → 20 bosses → **1,500 creatures**, which pays the skin |
| **exclusive** | **one Herald per season theme, in the same order**: Dawn, Tide, Cinder, Rime, Astral, Bramble |
| **dies when** | never. `GetDeadEvents` cannot name it, for the same reason it cannot name Weekend Rush |

**Why the effect is damage, when the note over Weekend Rush refuses exactly that.** That note is
about a *weekly* event, and its reason is that damage is the pacing of the game — doubling it every
Saturday means the game is only ever half-paced. Seventy-two hours twelve times a year is the
opposite case: the pacing is intact for twenty-seven days and the three it is suspended are the ones
the player remembers. `DNAService` did not change; its damage chain has carried the hook and a
comment saying *the day one does, it is a row in that table and not an edit in this file* since the
event engine was built.

**The one new thing that can rot, and the guard on it.** The rotation and `GameConfig.SeasonThemes`
are two parallel lists indexed by the same season number, so the Herald is named for its season only
while they are the same length. A seventh theme would break nothing visible — the game keeps running
and pays out the *wrong* Herald. `GameConfig.GetSeasonFestivalMismatch` compares them (and checks
every key resolves to a real character), and `EventService.Init` warns on it at boot, beside the
dead-event sweep. 32.24's rule: a comment saying "keep these in step" is a census, not a guard.

**A Herald returns after 180 days**, six themes at 30 days each. That is the Colosseum's own argument
at a longer wavelength — a rotation is limited because the window shuts, not because the item is
never offered again.

**`PrismFest` was left exactly where it is.** It is still the only dead event in the boot log and
`event_prism` is still unearnable, because the two dates above are 👤 hers and 25.1 was right that
inventing one is the same class of mistake as inventing a product id. What changed is that it is no
longer the *last* festival — the rule this section wrote is now satisfied by the calendar rather
than by that one row being fixed.

---

## 5. Filling a slot: what counts as small, and what counts as large

- **Small / weekly.** A player logging in that week sees it in one session without being told to
  look: a number they already watch changes, or a row appears in a panel they already open. Chests,
  weekend offers, a dressed zone, a multiplicative mutation. **No new panel, no new tab.**
- **Large / monthly.** A system: a new surface, a new loop, or a new thing to own. It lands on the
  season turnover, where the track has already reset and there is a reason to open the game anyway.

The reference set is unanimous that cadence — not size — is what engagement tracks. **Two thin weeks
in a row cost more than one thin month.**

---

## 6. Adding a beat

1. **Author it recurring unless it is meant to be limited.** A new row in `GameConfig.Events` with
   `recurring = { wday, hour, hours }` needs nothing else — the sign, the HUD card, the board, the
   announcement and the countdown all read `GetActiveEvents` and pick it up.
2. **Pick `priority` deliberately.** Every consumer draws `active[1]` and only `active[1]`. Higher
   wins; the rarer occasion should headline.
3. **Give it a ladder only if there is an exclusive at the end of it.** `GameConfig.EventQuests`
   with four rungs off the counters `SeasonPassService.Track` already feeds — `creatures`, `bosses`,
   `eggs`, `fuse`. An event with no entry simply has no board, which is correct for a rate boost.
4. **A rotation, if the same window recurs.** `rotation = { ... }` resolved off `window.startTs` and
   never off `now`, so every player in every server agrees which skin this occurrence pays.
5. **`fixed` only for a festival, and then re-read §4.**
