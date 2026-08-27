# The `+1` progression loop -- what the genre actually does

Research taken 2026-08-27 on the owner's instruction (*"uzmi agente i vidi kako +1 igre rade ...
takvu bi i ja funkciju"*), for ROADMAP row **33.34**. Sources are fan-maintained wikis pulled
through each site's `api.php` as raw wikitext; every number below is followed by where it came
from. Anything derived by arithmetic rather than quoted is marked **derived**.

The short version, before the tables: **her instinct about the symptom is right and the genre's
answer to it is the opposite of the obvious fix.** Deeper zones should not get a steeper health
curve. The player's multiplier stack should be bounded instead.

---

## 1. The eight findings that decide our design

1. **The per-area content ratio is FLAT or SHRINKING in every successful game in the sample.**
   Arm Wrestle Simulator x8.73 a boss (x8.67 over the first half, x8.79 over the second --
   no trend). Pet Simulator 99 x2.4 an area, *falling* from 2.8 to 2.15 with depth. Muscle
   Legends ranks x3.9, flat. Weight Lifting Simulator 3 ranks x2, flat. Elemental Power
   Simulator x4 exactly, dead flat across 27 tiers. Blox Fruits mob health is *linear in level*
   (~9.7 HP a level from level 5 to 2450), so its ratio falls toward 1.

2. **The two games whose ratio DOES grow are the two with famous endgame walls.** Anime Fighting
   Simulator's requirement ratio climbs x10 -> x100 while its training multiplier climbs only
   x3 -> x6, so each late tier takes ~7.4x longer than the last; Super Power Training Simulator
   is ~5x a tier. Three tiers of that is a 400x grind, and both games answer it with Robux
   boosts and overnight autoclickers.

3. **What grows with depth is the NUMBER OF STEPS, not the size of the wall.** Muscle Legends'
   Legend Beach opens at 2,500 Strength and the top item inside it costs 25,000 -- a x10 climb
   *inside one zone*. A zone is a small ladder, not a single health number.

4. **The soft gate's window is published twice, independently, and both land on ~10x.** Super
   Power Training Simulator lets you train at 1/20 of an area's requirement (you take damage and
   die) and its own guide recommends entering at 1/10; safe/AFK use needs 3.8x the requirement.
   Arm Wrestle Simulator prints a "Recommended Strength" beside every boss and the ratio is
   **exactly 1.15 for all fifteen bosses**, while arrival from the previous boss puts you at
   ~1/8.7 of it. **Arriving at ~1/10 of what the zone expects is the genre's number.**

5. **One exponential axis, everything else bounded.** PS99's pet ladder carries the whole game;
   its 61 area upgrades total about +55%, its damage potions are +15% a tier, and its enchants
   have *published* diminishing returns (100%, 60%, 38.3%, 27.5%). Arm Wrestle Simulator caps
   pet quality at x5 total and makes rebirth a flat +15%.

6. **Muscle Legends documents, on its own wiki, the exact bug we shipped in 32.x:** its rebirth
   multiplier applies only to equipment while pets are a flat term outside it -- *"that's why
   rebirth multipliers barely seem to have an effect on your gains at some point."* A multiplier
   must multiply the whole damage figure, or it is not a multiplier.

7. **Bosses are deliberately taken off the exponential axis.** Anime Fighting Simulator's boss
   health is 1,000-1,400 in *every* dimension and *"you will do base damage on Bosses, so Total
   Power/Stats don't mean much"*; boss damage to you is a fixed % of your max health. Expressing
   boss stats as RATIOS TO THE PLAYER immunises boss content against every multiplier you will
   ever add. **This is what 33.33 shipped, arrived at independently.**

8. **Rebirth never touches enemy health.** It is a small additive gain multiplier (+5% Muscle
   Legends and WLS3, +15% Arm Wrestle) on a LINEAR cost (`10,000 + 5,000n`, `10,000 + 1,000n`),
   and its real reward is ACCESS -- which gyms you may enter (1 / 5 / 15 / 30 / 60 rebirths).
   Where a prestige reward is exponential, the idle-game canon makes the currency a ROOT of
   lifetime progress (Cookie Clicker cube root, Egg Inc `^0.14`).

---

## 2. The numbers, by game

| Game | What | Numbers | Rule |
|---|---|---|---|
| Arm Wrestle Simulator | 15 bosses | 100 -> 700 -> 5k -> 41.5k -> ... -> 1.5Qa | **x8.73 a boss, no depth trend** |
| Arm Wrestle Simulator | "Recommended" vs boss strength | 115/100, 805/700, 5.7k/5k, 47.7k/41.5k ... | **exactly x1.15, whole game** |
| Arm Wrestle Simulator | pet quality | Baby x1 -> Goliath x2.5, Golden +50%, Void +100% | bounded at ~x5 |
| Super Power Training Sim | Body Toughness areas | req 100 / 10k / 100k / 1M / 10M / 1B / 100B / 10T; multiplier x5 / x10 / x20 / x50 / x100 / x2,000 / x40,000 / x800,000 | **min entry = req/20, AFK-safe = req x3.8**; time per tier grows ~x5 |
| Super Power Training Sim | Fist Strength (the damage stat) | same ladder, but *"you can't punch a Fist Strengthening object before you have reached its XP requirement"* | same game SOFT-gates defence, HARD-gates offence |
| Super Power Training Sim | relative combat | x10 higher Fist Strength = instant kill; x10 Body Toughness = 100% reflect, below it 10% | threshold-relative |
| Anime Fighting Simulator | formula | *"Strength gain = Training Zone multiplier x Player's Strength multiplier"* | two-factor product |
| Anime Fighting Simulator | Dimension 1 -> 5 | req x10-x100 a tier against multiplier x3-x6 | **x4 then x7.4 longer a tier -- the wall** |
| Anime Fighting Simulator | bosses | 1,000-1,400 HP in every dimension; player does BASE damage; boss hits for a fixed % of max health | **boss off the curve** |
| Elemental Power Simulator | ~27 hidden areas | requirement **exactly x4** a tier, gain x3.11 | time per tier x1.29 -- the gentlest shipped curve |
| Muscle Legends | 22 Elite ranks | 100K, 10M, 50M ... 250Qa | x3.9 a rank, no trend |
| Muscle Legends | one punchable rock a region | 0, 10, 100, 5K, 150K, 400K, 750K, 1M, 5M, 10M | **ratio SHRINKS with depth** |
| Muscle Legends | rebirth | cost `10,000 + 5,000n` (linear), reward +5% gain, gyms at 1/5/15/30/60 rebirths | access, not power |
| Muscle Legends | Legend Beach | entry 2,500 Str, gear inside 3,000 -> 25,000 | **x10 ramp inside one zone** |
| Muscle Legends | Tiny Island | open 0-1,000 Str only, then you are ejected | an area can have an UPPER bound |
| Weight Lifting Sim 3 | ranks / zones | ranks x2 a rung; the entire zone-multiplier ladder is only **x3** across the game | one bounded axis |
| Weight Lifting Sim 3 | published TTK | Underworld ghosts: *"you can one-shot at 6000 Strength"* | the only TTK number in the genre |
| Blox Fruits | mob health | ~9.7 HP a level to level 2450; 237x health growth over 490x level growth | **mobs become one-shots on purpose** |
| Blox Fruits | anti-farm-down | bounty only within a 25% level range; XP negligible unless the enemy is far above you | reward keyed to the RATIO |
| Pet Simulator 99 | 274 areas | cost x2.4 an area, ratio falling 2.8 -> 2.15 | flat/shrinking |
| Pet Simulator 99 | 61 area upgrades | Pet Damage +10,+10,+10,+10,+5,+5,+5 -- whole set ~+55% | **flat additive, shrinking with depth** |
| Pet Simulator 99 | enchants | stacked same-type: 100%, 60%, 38.3%, 27.5% | published diminishing returns |
| Pet Simulator 99 | prestige | 9 rebirths, and since Update 79 they reset NOTHING | a reset loop deliberately de-fanged |
| Ask a Game Dev | TTK | trash lives "a few seconds"; a boss should stay under ~2 minutes; 6 hits -> 4 hits is the smallest felt improvement | our target band |

---

## 3. What it means for Evolution Lab

### 3.1 The gate is three layers, not one

1. a **hard** floor used once or twice in the whole game, at the act breaks (we have this: the
   rebirth gates and `unlockStageIndex`),
2. a **soft** gate everywhere else -- you may walk into the next zone at ~1/10 of the damage it
   expects and it takes ~10x longer,
3. a **ramp inside the zone** spanning ~x10, so "I got stronger" is legible without crossing a
   border. We have five creature tiers a zone (Swarmer -> Apex) and they span x29 of health,
   which is the right shape already.

### 3.2 Do NOT steepen the deep-zone health curve

The measurement taken the same day (see 33.34's row) says the geared player one-shots a Critter
from **zone 2 onward** and a farmed Elite from zone 6, and that **no reachable health curve fixes
it**: even a curve that makes zone-20 mobs 14.5x heavier leaves the geared+trained player at 0.02
blows. Restoring a 6-blow Critter at zone 20 would need x288 on today's health. That is not a
tuning move; it is a different game.

The reason is arithmetic: our per-zone health ratio is **1.53** (`mobHealthMult` 1.442 x
`MobDepthGrowth` 1.06) and our per-zone *geared damage* ratio is about **2.08**. The player gains
faster than the content does, every zone, for twenty zones.

**So the lever is the stack, not the curve.** Keep the health ratio flat where it is and bound
what a player can multiply by -- which is finding 5 above, and is what PS99 and Arm Wrestle do.

### 3.3 The twenty hidden dummies -- the arithmetic that kills the obvious version

Our grotto dummy pays a permanent **x3**. Twenty of those is `3^20 = 3.5e9`, against a whole-game
health growth of about `1.5e9`. **Twenty x3 dummies is larger than the entire game.** The budget
for a permanent per-zone multiplier, if the whole set is to be worth a ~2-zone lead, is
`ratio^(2/20)` ~ **x1.12 each**, and never above x1.15.

The genre offers four shapes that survive twenty repetitions. In our order of preference:

| # | Shape | Who does it | What it costs us |
|---|---|---|---|
| A | **The multiplier belongs to the PLACE.** The dummy's x3 applies only while you are in that zone; twenty of them never stack. | Anime Fighting Sim, Super Power Training Sim, Elemental Power Sim, Muscle Legends' rocks | The grotto's x3 stops being permanent -- it becomes "this zone's secret makes this zone fast". Keeps the magnitude that already feels good. |
| B | **Diminishing returns on repeats.** #1 x3.00, #2 x1.80, #3 x1.38, #4 x1.28 ... | PS99 enchants (published: 100 / 60 / 38.3 / 27.5%) | Preserves the wow of the one already shipped and quietly defuses the other nineteen. Must be shown in the UI or it reads as a bug. |
| C | **Flat additive percent, shrinking with depth.** +10% in zones 1-5, +5% in 6-12, +3% in 13-17, +2% in 18-20, summed into one pool: ~x2.15 for the whole set. | PS99's 61 area upgrades | Completely safe; individually forgettable. |
| D | **Bake it into the ladder** -- price the next zone assuming the player found the dummy. | AFS, SPTS, EPS | Inverts the problem, at the cost of making a "secret" mandatory. |

In every game in the sample the trainer feeds **the same stat as normal play** -- nobody invents a
parallel currency for it. Our design is genre-correct in kind; only the magnitude and the stacking
rule need fixing.

### 3.4 Time-to-kill targets

* standard creature at the zone's expected gear: **2-4 seconds** (~4-8 blows),
* at first arrival, under-geared: **~10x that, 20-40 seconds**, which is exactly *"mogu i sa manje
  ali dugo traje"*,
* after the zone's upgrades: back to 2-4 seconds, then falling toward a one-shot as you outgrow it,
* boss: under two minutes,
* **drift across the whole game at the intended point: none.** Zone 1 and zone 20 should both be
  2-4 seconds for a player standing where the zone expects. All the difficulty lives in the
  arrival gap and in the number of steps.

One-shotting **old** content is a reward and the genre treats it as one (Blox Fruits, WLS3's
"one-shot the ghosts at 6000 Strength"). One-shotting **current** content is the bug: enemy
lifespan is how a player measures their own power, and with no lifespan there is no ruler.

### 3.5 Where our numbers stand against the genre (2026-08-27)

| | genre | Evolution Lab today |
|---|---|---|
| health ratio a zone | x2.4 - x4, flat | **x1.53, flat** -- inside the band, slightly low |
| geared damage ratio a zone | below the health ratio | **x2.08** -- above it, which is the whole fault |
| arrival gap | ~x10 slower | **x0.05 FASTER** (the geared player one-shots on arrival) |
| non-evolve multiplier stack | bounded, x5 - x50 | **x143 at zone 20 from income/pets/mastery alone, x45 more from passes/relics/VIP** |
| per-zone trainer | x1.12 permanent, or place-bound | **x3.00 permanent, and 19 more planned** |
| boss | off the curve, relative to the player | **relative to the zone's expectation since 33.33** |

---

## 4. What could not be verified

* No published damage formula for Muscle Legends or Weight Lifting Simulator 3 (WLS3's own wiki
  says so and guesses `damage - durability`).
* Strongman Simulator has no maintained wiki; nothing from it is quoted.
* PS99's breakable HEALTH per area is undocumented -- its x2.4 ladder is the area COST.
* No designer in the genre has published a TTK target. The 2-4 second figure is a synthesis of the
  generic Ask a Game Dev guidance, the DevForum "6 hits -> 4 hits" remark, and the ~10x arrival gap.
* The x1.12-per-dummy budget is arithmetic on our own parameters (20 zones, a ~2-zone lead as the
  target). Change the zone count or the health ratio and it moves.
* Fandom blocks direct page fetches; every number came through each wiki's `api.php`. These are
  fan-maintained pages, not developer statements, and at least one arithmetic error was found and
  corrected in Muscle Legends' rebirth table.
