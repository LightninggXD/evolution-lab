# Where the rebuild stands — 2026-08-03, evening

## A deeper map, a smaller player, nine potions and eight shops — 2026-08-04, latest

**Unsaved Studio session. `ZoneBuilder.BUILD_VERSION` is 47.** None of it is in `src/`.

### The platform is 1250 × 1150 (it was 900 × 860)

The X pass earlier today is written up below; this one is the Z half, which the note in
`ZoneBuilder` had been warning against for two sessions. **Widening on X is free — a deeper
platform is not**, because the street runs down Z and every piece of furniture on it sits at a
hand-written Z. All of them were multiplied by 1150/860 = 1.337: the welcome arch and its banners,
beam and name board (306 → 426), the lamp / picket / rail / bunting loop bounds, the planter and
bench spot tables, the arrival signpost (232 → 310), the landmark default (-360 → -480) and the
edge-rock cluster ranges. With them: `ARRIVAL_Z` 366 → 490, `ARRIVAL_CLEAR` 68 → 90, `BOSS_Z`
-240 → -320, `DECO_SPREAD_Z` 410 → 548, `BossService.GATE_APPROACH_Z` -372 → -502, and
`CreatureService`'s Z keep-out 372 → 500 with its arrival and boss circles moved to match.

Creature counts went 48 → **70 per zone (1400 in the world)** — 46% for 86% more ground, on
purpose: the server holds every rig at once and only the *client* is spared by streaming, so this
is the number to walk back first if it costs frames.

Verified after the rebuild: every zone 1568–1585 deep, neighbours 324–343 studs apart, all twenty
`Complete` with 3 eggs.

### The character is half the size it was, and jumps like a tycoon

`GameConfig.Stages[].scale` ran **1.0 → 9.0**, which at the top made a whole platform read as a
small room and every prop beside the player look like doll's-house furniture. The *growth* is
halved — `new = 1 + (old - 1) * 0.5` — so the curve now runs **1.0 → 5.0**, is still monotonic and
still moves at every evolve. Measured live at Star Weaver: the character went from ~51 studs tall
to **29.6**.

Jump came down with it: `BaseJumpPower` 66 → **44** (below Roblox's own default) and
`MaxJumpPower` 170 → **92**. Measured live: 14.6 studs of height, against a plaza deck of 3, a
podium of 6 and shop steps of 2. It used to clear 73.

### Nine potions instead of one

There was one potion — a five-minute x2 on income, held as a single integer. Now three effects in
three sizes:

| | Small (5 min) | Medium (10 min) | Large (20 min) |
|---|---|---|---|
| 🧬 DNA | x2 | x3 | x5 |
| ⭐ XP | x2 | x3 | x5 |
| 🍀 Luck | +25% | +55% | +120% |

Luck is **additive** because every other luck source in the game is (upgrades +2 a level, pets
`luckAdd`) — a multiplier on a stat that starts at zero does nothing for the player who buys the
first one. It goes through `DNAService.GetLuckPercent`, which is the one function eggs, pets,
characters, mutations and crit chance all read.

**One active bottle per kind, three kinds at once.** A second bottle of a kind already running does
not multiply — it takes the stronger effect and **adds the remaining time**. Stacking multipliers
collapses the whole thing into "drink the shelf at once", and it is also how a x2 and a x5 quietly
become a x10 no number in the config predicts.

- `data.Potions` is now a table keyed by potion id (`dna_s`), `data.PotionBoosts` by *kind*
  (`dna`). Both string-keyed on purpose — sparse integer keys are silently dropped crossing a
  RemoteEvent, which is the bug that ate `EquippedCharacters`.
- `PlayerDataService.Load` migrates the old number one-way into bottles of the default kind, and
  carries a still-running old boost over as a DNA boost. **Verified live** on the existing save:
  firing `UsePotion` with no id drank a migrated Small DNA Potion.
- Expiry is checked inside `GameConfig.GetPotionBoost`, so a boost that ran out while the player
  was offline is simply never returned and nothing has to clean up.
- Every grant path (Daily, playtime, Robux, shop) goes through `GameConfig.AddPotions`, so the
  migration only had to be got right once. The reward tables carry a `potionId`, so the later days
  give *bigger* bottles rather than more of the smallest.
- The Inventory panel is the shelf: nine rows built once, each with its count, effect, duration and
  a USE that drinks that exact bottle, plus a live three-line strip of what is running. A bottle
  you do not own is greyed but still listed — the list doubles as the reference for what the
  mystery shop can hand over.

### Eight shops in the strip, instead of three in every zone

Every village carried the same market stall + supply stall + cauldron, which made the shop the
least interesting thing on the street. `GameConfig.ZoneShops` now places, by zone index:

| zones | shop |
|---|---|
| 3, 7, 11, 15, 19 | 🔮 **Mystery Potions** — one sealed bottle, any of the nine |
| 5, 10 | 🧬 **Pet Fusion Lab** — two pods and a beam; opens the Pets panel |
| 8 | 💎 **Upgrade Emporium** — two counters, Diamonds and Robux |

Twelve of the twenty zones have no shop at all. That is the point.

The mystery roll is weighted 66 / 27 / 7 by size with the kind rolled evenly, and **the player's
own luck shifts it toward the bigger bottles** — the same shape the egg pools use. Priced at 3× the
zone's mid-tier egg (the old guaranteed cauldron was 2.5×), which per DNA makes it the better buy,
as it has to be when there are five of them in the game and reaching one is a walk.

**Two ways a counter does its work**, and the difference is which side owns the transaction:

- `MysteryCost` — the server's business, wired by `PotionService` on start, price on the prompt so
  it is validated against the counter the player is standing at.
- `ShopPanel` — the client's business. Fusion and the two upgrade counters only need to *open* a
  panel the HUD already builds, so `MainUI` listens for `ProximityPromptService.PromptTriggered`
  itself. There is no remote and no server handler for them, and walking up feels instant because
  nothing round-trips. It filters on `playerWhoTriggered ~= player` — the event fires on every
  client for every player.

Fusion is deliberately **not** gated to the lab: the Pets panel keeps its Fuse buttons, so a player
holding four duplicates at stage 3 is not blocked.

### The Mastery tile came off the HUD

`RIGHT_COUNT` 5 → 4, and the right column is Journal / Zones / Daily / Robux. The Mastery *panel*
is untouched — only its entry point moved, to the Upgrade Emporium's diamond counter. `masteryBadge`
stays declared as nil and the refresh that sets it was already nil-guarded.

### Still to do by hand

`workspace.StreamingMinRadius` / `StreamingTargetRadius` / `StreamingIntegrityMode` are **not
reachable from the Studio MCP sandbox** — they error as "not a valid member of Workspace" while
`StreamingEnabled` reads fine. The map failing to draw when the player moves is the default
64-stud minimum / 1024-stud target against a platform this size. Set in the Properties panel:
**MinRadius 512, TargetRadius 3000, IntegrityMode MinimumRadiusPause.**

## The zones really stopped overlapping, and the map got wider — 2026-08-04

**Unsaved Studio session. `ZoneBuilder.BUILD_VERSION` is 46.** None of it is in `src/`.

### The spacing fix from earlier today had never reached the world

`GameConfig.ZoneSpacing` said 1500 and `PLATFORM_WIDTH` said 900, and the platforms in `Workspace`
were 900 wide standing 630 apart — overlapping by ~580 studs of model. Two separate reasons, both
worth knowing:

1. **The world is baked.** `Build()` has a version guard *and* a per-zone skip, so with
   `BUILD_VERSION` unchanged a spacing edit rebuilds nothing at all. It reported `ok = true`.
2. **The GameConfig require cache.** A fresh `ZoneBuilder` clone still calls
   `require(RS.Modules.GameConfig)` and gets the *stale* table — which is exactly how the platforms
   came out at the new width and the offsets at the old spacing in the first place. The fix is to
   replace the instance (clone → destroy original → rename the clone → reparent).

### The map is 39% wider per zone

`PLATFORM_WIDTH` **900 → 1250**, `ZoneSpacing` **1500 → 1900**. Measured after the rebuild:
neighbouring zone models are **316–351 studs apart**, no pair touching, strip runs 0 → 36,100.
Moving with it: `DECO_SPREAD_X` 430 → 595, `BossService.PLATFORM_HALF_X` 450 → 625,
`CreatureService`'s keep-out `|x| > 400 → 575`, its scatter range ±396 → ±570, and its counts
(Elite 4→5, Brute 8→11, Critter 15→20, swarm hubs 7→9) = **63 per zone, 1260 in the world**.
Verified by replaying the generator: every tier fills without starvation and the furthest point is
at |x| = 570, inside the rampart's inner edge at 587.

### Widening the platform was making the zones look *emptier*

`DECO_SPREAD_X` is only the **default**. About seventy biome scatter calls pass their own spread,
and every one of those numbers (~205 on x, ~255 on z) was authored against the 450 × 550 platform
the game started on — so all the scatter piled into the middle third and the new ground came out
bare down both sides. `scatterPoint` now reads an explicitly-passed spread as a fraction of the
platform it was written for and rescales it onto the current one
(`spreadX * (DECO_SPREAD_X / LEGACY_SPREAD_X)`, clamped, floored — `math.random` wants integers).
`DENSITY` 1.28 → 1.78 with the area. **51,418 zone parts.**

### One zone had no eggs — and it was not a content bug

QuantumRealm came out at 1,525 parts against ~2,600 everywhere else: Studio dropped the MCP
connection **mid-build**, leaving that zone truncated, and the per-zone skip then trusted the name
and preserved it. The egg plaza is the last thing built per zone, so what a truncated zone is
missing is its eggs.

The loop body now ends with `model:SetAttribute("Complete", true)` and the skip requires it — a
zone without the stamp is destroyed and rebuilt. A part count per zone is the cheap way to spot it.

## Creatures heal, the zones stopped overlapping, 200 characters — 2026-08-04, latest

**Unsaved Studio session. `ZoneBuilder.BUILD_VERSION` is 43.** Everything below is live in Studio
and none of it is in `src/`.

### Nothing can be worn down by running away any more

Damage was permanent until death, so the cheapest way to kill anything above your own zone was to
chip it, walk off, heal yourself, walk back, repeat — a fight decided by how fast the *player*
recovers rather than by whether they can beat the creature, and the further above its weight the
player was punching the better it worked.

A creature nobody has touched for **7 s** now closes the wound over **8 s** (`CreatureService`), a
zone boss over **20 s** after **14 s** (`BossService`). The delay is the whole balance of it: a
swing lands every 0.34 s, so it can never interfere with a fight in progress, and it is shorter
than the walk back from a spawn point, which is the case it exists to close. The **event boss is
deliberately exempt** — it is chipped down by a whole server over fifteen minutes and already
resets itself by withdrawing.

Implementation: one module-level `hurt` table per service holding *only* creatures that are
actually damaged (the one or two being fought, never the 960 standing in the world) and one loop,
called at the top of the existing `driveCreatures` / `driveRigs` **before their no-players early
return** — a creature left at 3 % has to heal even when the player who hurt it has left the zone.
The precise value lives on the entry and only the rounded one is published: healing 12 health over
8 seconds is 0.025 a frame, and rounding the attribute itself would round every step away and heal
nothing. `playDeath` drops the entry, like it does the auto-attack handler.

Verified live: a 30-health Critter taken to 7.5 by three auto-attacks was back at 30 inside 8 s.

### The zones were standing inside each other

`GameConfig.ZoneSpacing` was **630** — correct when a platform was 450 studs wide. The platforms
were later widened to 700 × 860 and the spacing never moved with them, so from Desert onward every
platform overlapped its neighbour by **70 studs of floor**, and the zone *models* — ~1030 studs wide
once the rock rampart and the two rows of backdrop mesas behind each wall are counted — overlapped
by ~400.

That one number was the cause of all three complaints raised about the world:

| symptom | why |
|---|---|
| "you can walk through some walls" | the *next* zone's backdrop mesas stood on this platform, and mesas are `CanCollide = false` |
| "the monsters are inside the wall" | creature spawn points out at \|x\| ≈ 300 landed inside those mesas |
| the map read as a pile from the air | two zones' walls, ramparts and mesas interpenetrating |

Spacing is **1500** now and the platform was widened **700 → 900** while the constraint was being
fixed properly (measured: neighbouring zone models are 280 studs apart). Only X moved — the street
runs down Z and every piece of furniture on it sits at a fixed Z, so a *deeper* platform would
leave the street ending short of the wall; a wider one just adds ground either side of it. The
offsets are still written per row in the table, but a loop under it now derives them from
`ZoneSpacing`, so a hand-edited row can never disagree again.

Moved with it: `ZoneBuilder.DECO_SPREAD_X` 330 → 430, `BossService.PLATFORM_HALF_X` 350 → 450,
scatter density ×1.28 (a fixed count over 24 % more ground reads as a zone that was emptied), the
mound/glow-post spreads 190 → 300, and the creature counts per zone 39 → 48 (**960 in the world**).

**The default 2048² `Baseplate` was deleted** — it was a grey apron sticking out from under Forest
and the Colosseum in every wide shot — and `FallenPartsDestroyHeight` moved -500 → -120 so anything
that leaves a platform is destroyed and respawned rather than falling past the world.

### A creature is no longer built inside a rock

The spawn points are generated against four keep-out rules (street, arrival, boss, plaza) and
ZoneBuilder scatters its boulders, ramparts and props against its own set; neither has ever been
told about the other. `ZoneBuilder.Build()` runs before `CreatureService.Init`, so the world can
simply be **asked**: `clearOfScenery` probes an `OverlapParams` box at the spawn point (excluding
Creatures / Bosses / EquippedPets, and ignoring anything whose top is below the creature's feet —
which is how the floor is never a hit) and walks the point out in rings of eight, falling back to
walking it toward the middle of its own platform when every ring fails, which is what happens in a
corner. The same probe runs when a roaming creature picks a target and, at 4 Hz per moving rig near
a player, on the step it is about to take — the keep-out rules say where it *may* walk and knew
nothing about what is standing there.

Also: the keep-out edge went 338/412 → **400/372**, because the boundary rampart reaches up to 38
studs in from the X wall and 48 from the Z wall (measured across all twenty zones) and the old
margin placed creatures inside it.

Measured: creatures whose bounding box clips solid scenery went **187 → 22 of 960** (2 %), and the
remainder are horns brushing crates.

### Two hundred characters

`GameConfig.StageCharacters` went from five per stage to **ten** — a second full set on the same
rarity ladder (2 Common, 2 Uncommon, 2 Rare, 2 Epic, 2 Legendary per stage). The roll weights by
rarity and sums, so the *chance* of a Legendary is exactly where it was and only which Legendary it
is changes; what moves is how long the collection takes to finish, which at five a stage was over
after two rebirths. Verified: 200 entries, no duplicate keys, stage-5 roll still 61.9 / 26.0 / 9.2 /
2.4 / 0.5 %.

The Journal row is no longer hard-coded to five: cells wrap five to a line (`CHAR_PER_LINE`), the
row is as tall as its stage needs, and the scroll uses `AutomaticCanvasSize` instead of a counted
one.

## The Character Journal, and feedback moved into the world — 2026-08-04

**`ZoneBuilder.BUILD_VERSION` was 40 at this point.**

### The swing no longer folds the character up

`resolveJoint` captures a joint's rest pose at the moment it is called, and `playSwing` called it
fresh on every swing. A re-cut swing — which is *every* swing once auto-attack is running, since the
loop fires before the previous one has recovered — captured the joints while they were still rotated
from the swing before and treated that mid-pose as the new rest. The error compounded a few degrees
per hit until the rig had twisted into a pile of blocks.

Joints are now resolved **once** into a set carried on the swing state and reused by any swing that
cuts into it; the set is dropped when a swing ends cleanly, and on `BodyScale` changing (an evolve
moves every attachment, so a pose captured before it is stale). Only the swing that still owns the
character restores it. Measured: **0.0000° drift after 10 s of continuous auto-attack.**

### 100 characters — five per stage

`GameConfig.StageCharacters`, on the same rarity ladder and weights the pets use. They are **skins**:
a character changes what the body is painted and nothing else, so the twenty evolve steps stay the
only thing deciding how strong a player is.

- Evolving into a stage rolls one of that stage's five (`DNAService.RollCharacter`), including after
  a Rebirth — that is what fills the hundred in over repeat runs. Luck lifts the rare end.
- `data.Characters` (set of owned keys) and `data.EquippedCharacters` both survive Rebirth. A
  collection wiped by the mechanic designed to be repeated is not a collection.
- A newly rolled character is worn immediately **unless** the player has already chosen one for that
  stage in the Journal — a random roll must not override a deliberate choice.
- `EvolutionVisuals` stamps `CharacterKey` on the character and passes the entry to
  `StageCostume.Apply(character, stageIndex, stage, entry)`, which paints the whole build with it.
- New `Remotes.EquipCharacter` (created on demand). The server checks ownership; equipping a
  character for a stage you are not standing at is legal and takes effect next time you are.
- New **Journal** HUD tile → a 20 × 5 panel, one row per stage, locked cells showing a padlock over
  the rarity colour. All 120 instances built once; refresh only writes text, colour and visibility.
- Backfill in `ServerMain`: a save from before this existed gets one roll for the stage it is
  actually at, and only when it owns nothing — a stage-20 player never evolves again.

**The trap:** `EquippedCharacters` was keyed by stage *number*. A table whose only key is `[11]` is a
sparse array, and **Roblox silently drops those crossing a RemoteEvent** — the server had the right
value, the client's copy arrived empty, so the Journal showed nothing equipped while the body was
correctly painted. Keyed by `tostring(stageIndex)` everywhere now.

### Feedback happens where the thing happened

Three banners were covering the middle of the screen — the one place the player is actually looking.

| was | now |
|---|---|
| `"👾 Defeated a creature! +N DNA"` banner | gone. The DNA already floats off the creature that died. |
| `"💢 Ouch! -N HP"` banner | a red `-N` above the player's own head, beside the health bar |
| egg hatch / fuse as a full-screen card | `worldPopup` — a 210 px card floating up off the player |

Damage taken is driven off `HealthChanged`, not off the remote, so it catches every source (Brute
retaliation, Elite aura, boss, falling) without any of them knowing about it — and only for the
local player, since a number for every hit every *other* player takes is someone else's fight
reported on your screen.

What is left on screen is smaller and out of the way: the notification stack is 300 px (was 420) at
y=66 (was 100) and **capped at 4** — a fight fires kills and damage faster than the 2.5 s timer
cleared them. `celebratePurchase` is 330 px at 24% screen height (was 460 px at 42%), and destroys
any previous copy so a multi-hatch cannot stack cards on one spot.

## You become the thing you evolved into — 2026-08-04, latest

**Unsaved Studio session. `ZoneBuilder.BUILD_VERSION` is 40.**

### Nothing dies in one hit any more

Player damage is `8 + (stage - 1) * 6` times Income / pets / Stage Mastery; creature health is the
tier's base times the zone's `mobHealthMult`, which runs 1× in Forest to 1050× on the Absolute
Plane. The two only line up in the zone that matches the player's stage, and a player is *usually*
somewhere else, because every earlier zone stays walkable. A Cyborg (stage 8, 50 damage before a
single upgrade) in Forest deleted a 12-health Swarmer on the frame they clicked — the balloon-pop
complaint back by another route, with none of the flinch, recoil or spark ever seen.

Each tier now declares the fewest hits it may die in (`minHits`: Swarmer 3, Critter 4, Brute 6,
Elite 8; `BOSS_MIN_HITS` 12, `EVENT_MIN_HITS` 40) and a blow is capped at that fraction of full
health. Deliberately a cap on the **damage**, not a floor under the health: an over-levelled player
still clears a low zone as fast as they can click, the payout is untouched, and nothing needs to
know how strong the attacker is. Verified live: a 19-health Swarmer takes exactly 3 hits.

### The character is the creature now

`StageCostume` decorated an avatar. That was the whole design and it was wrong — at Cyborg you were
a default Roblox avatar, thin dark stick legs and all, with a reactor bolted on. Two changes:

1. **`EvolutionVisuals` no longer sets all four scale values to the same number.** Equal values are
   just a bigger default avatar: tall, narrow, small-headed. There is now a `PROPORTION` table of
   per-axis multipliers on top of the stage's own scale (`BodyHeightScale` 0.92, width/depth 1.22,
   `HeadScale` 1.32) plus `BodyProportionScale = 0` for the classic blocky build.
2. **`StageCostume.dressBody` clothes every limb** — cube head, torso, shoulder yoke, neck, belly,
   upper/lower arms, mitts, thighs, shins, boots — and `setBodyHidden` makes the avatar's own parts
   (and its face decals, which render through a transparent part) invisible underneath. One shell
   welded per limb, so the animation engine walks, runs and swings the whole body for free.

Stage 7 (Human) is the one stage that skips both: it is supposed to be a person.

Three things this broke and how:

- **Every one of the 20 builders sizes details in fractions of the host limb** (`ctx.head.Size` etc.),
  which is now inside a shell up to 1.7× bigger — visors inside skulls, eyes inside heads. `ctx` now
  carries `headSize` / `torsoSize` / `lowerSize` / `armLSize`, the *outer* dimensions of the dressed
  body, and all 43 references were switched to them. Undressed they equal the limb sizes exactly, so
  Human is unchanged. **`multi_edit`'s `replace_all` silently did not apply** — it reported success
  and changed nothing; the replacement was done with a `gsub` on `.Source` instead. Check the count.
- **The eyes were balls centred on a guessed fraction of the head's depth** (0.45–0.5), which was
  roughly the old head's surface and is well inside the new cube. All twenty faces were two pinholes
  in a blank block. `eyes()` measures the face plane off the head and stands flat eyes proud of it —
  the pair `PetModel` already drew. There is also a fallback: after a stage builds, if nothing named
  `StageEye` exists, a default pair is added, so no stage can have a blank face.
- **The swing was authored for a thin arm.** A 4.35-radian sweep with an inward roll across the chest
  puts a shell two-thirds the width of the torso *through* the torso — with auto-attack running it
  read as a body chewing itself. The throw is now 2.35 radians, the roll is **outward**, waist and
  neck are halved, and `AUTO_INTERVAL` went 0.2 → 0.34 so a swing finishes before the next starts.

## Auto-attack, a swing you can see, real name boards — 2026-08-04, latest

Seven complaints in one pass. **All of it is live in an unsaved Studio session and NONE of it is in
`src/` — the place still has to be saved (File → Save).** `ZoneBuilder.BUILD_VERSION` is now **40**.

### Auto-attack (on/off)

The state is one thing: **`player:GetAttribute("AutoAttack")`**. `MainUI` draws the "Auto ON/OFF"
tile in the bottom-right quick row and flips it; `CombatClient` reads it, also toggles it on **T**,
and does the fighting. Neither script knows the other exists.

A `ClickDetector` cannot be fired by code, so auto-attack could not reuse the click path. New
remote **`Remotes.AutoAttack`**: the client names the model it wants hit, and *both*
`CreatureService` and `BossService` listen on it, each ignoring any model it has no handler for.
Each service now keeps `hitHandlers[model] = { fn, body, reach }` and the click detector and the
remote land in the **same** `onHit`, so cooldowns, retaliation and DNA are identical either way.
The server validates: the model must be one it spawned, and the attacker must be within `reach`.

Two traps:

1. **`workspace.Creatures` is not only creatures.** `deathBurst` parents its confetti host and
   ground shockwave straight in beside the corpse, and `somePart.PrimaryPart` is a hard *error*,
   not nil — so the target scan threw on the first kill anywhere in the server and auto-attack was
   dead for the session with no symptom but a toggle that did nothing. Guarded with `IsA("Model")`,
   and the whole scan is `pcall`ed because an unattended loop gets no second chance.
2. `table.clear(hitHandlers)` in `BossService.Init` has to run **before** the spawn loop, not after.

The per-kill "Defeated a creature!" toast is suppressed while auto-attack is on — two kills a second
turned the top of the screen into a wall of identical green cards that buried the toasts that matter.

### The swing moves the whole body now

"When I hit, the character stands still and only the ground shakes." Two causes, both real:

* the swing wrote **one joint** (a shoulder, plus a thirteenth of the angle at the waist). On a body
  scaled to 3.8× that is a small thing at the far end of a large silhouette;
* it very often **did not play at all**. It is gated on the mouse ray hitting a creature, and only
  the torso and head of a rig were queryable — aim at a horn, a wing or a paw and the ray came back
  empty, so the click did damage and drew nothing. The new hit box below is what fixed that half.

Now: both shoulders (the off arm counter-swings), both elbows, the waist twisting into the blow and
back, the neck leading it, the trailing hip stepping under it, plus a `Trail` off the swinging hand
for the swoosh. Everything is a rotation, so it stays scale-free. Verified live: 22 distinct poses
sampled over 1.6 s on shoulder + waist + elbow, on an **AnimationConstraint** rig.

`SWING_TIME` 0.26 → 0.30, and a swing may now be **re-cut after 55 %** of the previous one — the old
"one at a time" rule meant auto-attack's 0.2 s loop had every second swing silently dropped. Each
swing carries a token; a superseded loop returns without touching the joints and lets the newer one
own the restore. Camera kick 0.22 → 0.34.

### One hit box round the whole creature

`CreatureService` built two ClickDetectors, on the torso and the head, with every other rig part
`CanQuery = false`. That works on a ball and fails on what the rigs became — a Swarmer *is* its head,
a Brute is mostly horns and paws. One `HitBox` part now wraps the model's own bounding volume (+16 %),
carries the only detector, and rides the body's frame through `driveCreatures` — same shape
`BossService` already used. Measured: a Swarmer's clickable volume went from a 4×3×5 torso to
15×13×17.

While doing it, the ring/hit-box slots in the bulk arrays became **recorded indices**
(`rig.ringIndex`, `rig.hitboxIndex`) instead of `#atts + 2` arithmetic at the far end of the loop.

### HUD tiles: two edges, not three

`UITheme.IconTile` was outline → rim → face. The rim was Cream (a white ring round every button),
then a dark shade of the tile's own hue — which fixed the colour and kept the fault, because it was
still a third edge. `INSET` is now **0** and the outer shell is the **same colour** as the body: the
shell still exists (it is the TextButton, and owns the click, the stroke and the shadow) but is not
visible as a layer. `UITheme.SetColor` keeps both in step.

### The name boards stand on things now

Three `makeSign` billboards were replaced with real boards carrying `addPlankText` on both faces —
the treatment the "Desert" walkway sign already had, which is the one that was liked:

| was | now |
|---|---|
| 34-stud billboard at `(cx, 34, 307)`, over the arch | `ZoneNameBoard`, 58 × 17, resting on the arch beam trim |
| billboard 26 studs above the portal lintel | `PortalNameBoard`, 104 × 34, standing on the gate cap |
| billboard at `(cx-104, 12, 232)` with nothing under it | `ArrivalSignPost` + board + lamp, on the ground |

A billboard turns to face the camera, so from any angle but straight on all three read as cards
hovering in mid-air beside the thing they belonged to, and from behind a wall they faced you through
it. `addPlankText` takes `{ maxDistance, pixelsPerStud }` now.

**Two sizing rules learned here.** `TextScaled` fills by *height*, so a board five times wider than
it is tall buys nothing but empty plate either side of a short word (the gate board went 132 × 27 →
104 × 34). And a SurfaceGui canvas is `PixelsPerStud ×` the part — on boards this size the walkway's
32 px/stud is a 3,300-pixel texture for one word, so these run at 8–20.

The remaining `makeSign` billboards are the shop titles, stall odds boards and egg prices. Those are
all mounted on a structure and stay.

### Buying something is visible

`PotionService` fires `{ kind = "reward" }` for both village stalls and the cauldron and **MainUI had
never handled that kind** — the DNA came off the counter and the screen did not change. Same for
`{ kind = "bossDefeated" }`. Both are handled now, through a new `celebratePurchase()`: a card that
punches in past its own size at screen centre, a ring running out past it, and a confetti burst on
the player in the world (sized off `BodyScale`, so it is not a firework at stage one and dust at
stage twenty). Egg hatches, fuses and Robux purchases were upgraded from toast to celebration too.

## ⚠️ Studio is well ahead of this tree — 2026-08-04, late

The world was rearranged in Studio after everything below was written, and **almost none of it is
in `src/`**. Do not patch these files from this tree; pull them whole (File → Save As → `.rbxlx`,
see `SYNC.md`) before touching them.

| File | Studio bytes | `src/` bytes |
|---|---|---|
| `ZoneBuilder` | 273k, `BUILD_VERSION = 36` | 163k, `BUILD_VERSION = 15` |
| `CreatureService` | 132k | 27k |
| `BossService` | 106k | 74k |
| `GameConfig` | 60k | 53k |
| `UITheme` | 27k | 24k |
| `EvolutionVisuals` (9,985 B) | exists | **missing entirely** |
| `ZoneTransition` (new client script) | exists | **missing entirely** |
| `PetFollowService`, `PetFollowClient` | rewritten below | old fixed-scale version |
| `StageCostume` (new, 45k) | exists | **missing entirely** |
| `ZoneService`, `PlayerDataService`, `PotionService`, `Systems/*` | exist | **missing entirely** |

**`CombatClient` (21,623 B) is the one file that IS in sync** —
`src/StarterPlayer/StarterPlayerScripts/CombatClient.client.lua`, verified byte-identical.

## Combat feel, movement pace and signage — 2026-08-04, late

Four complaints, in the order they were raised: hitting a creature felt like popping a balloon,
the character moved sluggishly, the zone name boards looked bad, and the HUD tiles had a white
border. Plus: a health bar over the head during a fight.

### Combat now has a visible cause and a visible effect

New client script **`StarterPlayerScripts/CombatClient`**, and one new remote **`Remotes.CombatFx`**
(created on demand by whichever of CreatureService / BossService requires first). The server still
owns every number; it sends one small description per hit and draws nothing.

The split is deliberate. A billboard or emitter *created on the server* replicates at a throttled
rate, so a damage number meant to punctuate a click lands visibly after it — and the attacker's own
swing has to start **on the frame they clicked**, which a ~100 ms round trip cannot do inside a
260 ms animation. So the local player's swing fires straight off their own mouse button, and the
remote only plays *other* people's swings and the impact effects.

What a hit now does:

| Where | What |
|---|---|
| attacker | procedural arm swing (alternating hands, waist follow-through), camera kick, floating damage number |
| creature | white flash, backwards recoil + pitch + shiver (`rig.hitUntil`, `HIT_TIME` 0.14 s), body squash, health bar drawn on top for 5 s |
| on death | knock-back tumble: spins, arcs, shrinks to nothing over `DEATH_TIME` 0.42 s, plus falling confetti and a ground shockwave |

Three traps this hit, all silent:

1. **This place's avatars have no `Motor6D`.** Roblox is midway through replacing them with
   `AnimationConstraint`, and the test character had zero Motor6Ds anywhere. The static offset a
   procedural animation writes lives in a different place on each — `Motor6D.C0`, versus
   **`Attachment0.CFrame` on the parent side** for an AnimationConstraint (a shoulder's sits in
   `UpperTorso`, not in the arm). `resolveJoint` returns a uniform handle for both. Written against
   Motor6D alone the arm never moved and *nothing errored*.
2. **`Mouse.Target` was the atmosphere sheet, everywhere in the game.** `addAtmosphere` hangs a
   640 × 800 invisible slab at head height over each platform to carry one emitter, and it was
   `CanQuery = true` — so every mouse ray from every camera struck it first. It is now
   `CanQuery = false`, and `CombatClient` casts its own ray with an **include** filter of
   `workspace.Creatures` + `workspace.Bosses` so nothing else can ever be the answer again.
3. **`playDeath` must drop the rig out of `live` before it touches it.** `Model:PivotTo` and
   `Model:ScaleTo` write every part's CFrame, and the idle driver writes them all back from its own
   maths on the next Heartbeat — with the rig still registered, the corpse just stands there while
   the two fight sixty times a second.

Also fixed while in there: **the head `ClickDetector` was never connected to anything.** It has
existed since the rigs were built — the taller rigs showed a hand cursor over the head and did
nothing at all when clicked, which on a Swarmer is most of the creature.

### Pace scales with the body

`GameConfig.BaseWalkSpeed` 26 → **34**, and — the actual fix — speed is now multiplied by
`GetSizeSpeedMultiplier(bodyScale)` = `scale ^ 0.82`, capped at `MaxWalkSpeed = 150`.

A player's body runs 1× → 9× across the twenty stages while the walk speed was one constant, so a
Human-stage character nineteen studs tall crossed the ground at the studs/second a one-stud Cell
did. Apparent speed is studs-per-second *divided by body height*: at 3.8× that is a quarter of the
pace the same number gives at 1×, which is exactly what wading feels like. Measured in Play at
stage Human: **26 → 101.6 studs/s.**

Jump takes the same multiplier at `^0.5`, not `^1`: jump *height* goes as the square of jump power,
so scaling power with the body one-for-one makes a giant leap several of its own heights. Base 62 →
66, cap 170 (= 73 studs of height, comfortably under the 180-stud zone walls — a jump that clears a
boundary drops the player into the gap between platforms, where there is no floor at all).

`EvolutionVisuals.ApplyStage` now stamps **`character:GetAttribute("BodyScale")`**, which is what
`applyMastery` reads for the multiplier and what the health plate and camera kick size themselves
off. **Shift sprints** at ×1.4 of whatever the server last set, re-reading the base whenever the
server moves it so an evolve mid-sprint is not clamped back on release.

### Health bar over the head

Roblox's built-in humanoid bar is a thin red strip with none of this game's outline, radius or
palette; it is switched to `AlwaysOff` and replaced by a `UITheme.ProgressBar` on the head. It
appears when the character is hurt and hides four seconds after it is full again — a bar that is
always up is chrome. Green → amber → red, and the offset is measured off the **head's own size**
so it works at every stage.

The creatures' own plates were also wrong: `MaxDistance` was **45**, tuned when the player was a
one-stud Cell. The camera sits behind a head that is nineteen studs up by mid-game, so nobody past
Lizard had ever seen a creature health bar. Now 150, with a `n / max` readout, and `AlwaysOnTop`
for five seconds after each hit so the thing you are fighting draws through the scenery — but not
the other 519 creatures in the world.

### The zone name boards

`makeSign` was a single flat `TextLabel`: 35 %-transparent near-black, white Gotham, one 12 px
corner, floating in front of the plank. The rebuild is the sticker shape the rest of the game uses
— ink outline, cream rim, coloured face, gloss, hard shadow, outlined display text — coloured by
the zone's own accent.

**Every layer is sized in scale, never in pixels.** These billboards are sized in *studs*, so their
pixel size changes with distance: a 4 px `UIStroke` or a 12 px `UICorner` is a hairline up close and
a fat crayon border from across the platform. The border is three stacked rounded rectangles for
exactly that reason.

The two direction signs on the walkway went further: **the plank IS the sign now.** The name is
painted onto both faces with a `SurfaceGui`, so the floating second object is gone entirely and the
text can never overhang the thing it is written on (which is what made "Desert" look cut off). The
old 45°-rotated cube "arrow" — which read as a diamond finial pointing nowhere — is now a real
arrowhead plus a shaft; the shaft has to **reach into** the board at one end and the chevron at the
other, or it hangs between the two with daylight at both ends.

### The white border on the HUD tiles

`UITheme.IconTile`'s outer rim was `Color.Cream`, which put a white ring around every HUD button.
Against the bright outdoor zones that read as an unfinished border rather than as moulding — rim,
then dark outline, then pastel body is one light edge too many. The rim is now a darker shade of
the tile's **own** colour (`shade(color, -0.42)`), so the tile reads as one moulded object with a
lip. `UITheme.SetColor` re-shades the rim with the body, or a recoloured tile keeps the old hue's
lip.

What changed in the world since this tree was written:

- **The portal gates moved from the X walls into the Z walls.** A zone is now one straight
  street: you arrive at `z = +212`, walk `-Z` past the egg plaza at `z ~ 0`, and leave by the
  gate at `z = -275`. `ZoneBuilder.GetZoneSpawnCFrame(zoneKey, fromZoneKey)` decides which end
  you come out of. Zones are still spaced 630 apart on X, and **there is no floor at all in the
  gap between two platforms** — anything that lets a player past a boundary drops them off the
  world.
- **The gate sheet is solid** (`PortalGate.CanCollide = true`). Traversal is by `Touched` →
  `ZoneService.HandleTeleportRequest`, which refuses while the destination is locked; with the
  sheet passable, that refusal used to be followed by the player walking straight through the
  opening and falling out of the map. A blocked contact still fires `Touched`, so an open gate
  behaves exactly as before. Verified in Play: Forest → Desert → Ocean all teleport, and the
  locked Ocean → Volcano gate stops the character dead at `z = -272` with no fall.
- **Every boss stands on the street at `(zone.offset, 0, -132)`**, between the shop and the exit
  gate it guards — beating it is what unlocks that gate (`GameConfig.requiresBossKey`). It used
  to sit off at `(+175, 0, 0)`, beside the shop, where a player could reach the exit without ever
  meeting it. `spawnBoss` now measures the finished rig on Z as well as X and walks it back if it
  would reach past `z = -218` into the portal's approach steps.
- **`scatterPoint` reserves the walkway** (`STREET_HALF = 48`) over the platform's whole depth,
  plus a `BOSS_CLEAR = 116` circle round the arena. Without it the scatter dropped trees, crates,
  banner poles and glow posts into the walk from the arrival gate to the eggs.
- **Pets are sized off their owner.** `PetFollowService.PET_SCALE` (0.95) is multiplied by
  `sqrt(BodyHeightScale)`, and the owner's scale is folded into the rebuild signature so evolving
  re-sizes the pack. The player's own body runs 1x → 9x across the twenty stages, so the old flat
  0.72 rig came up to a Human-stage player's ankle. At 3.8x the pets now stand ~9 studs, about
  45% of the player's height. The finished scale rides on each model as a `PetScale` attribute.
- **Pets stand on the floor, found by a downward ray**, not on a constant offset from the owner's
  root. `PetFollowClient` measures each rig's own lowest solid part (skipping the rarity ring,
  which is meant to lie *in* the floor) and puts that on whatever the ray hits, with
  `RespectCanCollide` so a pet never stands on a bush. That is what makes a pet walk up the shop
  steps, and stay on the ground when its owner jumps. The trail distance scales with the owner
  and the row spacing with the pet.
- **The two village market stalls are shops now.** Each carries a ProximityPrompt with
  `StallCost` / `StallKind` attributes; `PotionService.HandleBuyStallPotion` charges DNA and rolls
  a potion count off `GameConfig.PotionStalls` (market: cheap, x1 74% … x5 2%; supplies: dearer,
  x1 30% … x5 12%). Both average slightly worse per DNA than the cauldron's guaranteed bottle, so
  the sure thing stays the efficient buy. The odds are on a board under each awning, built from
  the same table that rolls them.
- **Every shop prompt reaches 42 studs** (`PROMPT_REACH`), up from 17/18. A prompt measures to the
  character's root, which at the top stages floats close to thirty studs above the counter — an
  endgame player physically could not trigger the stalls or the cauldron.

## The look pass — 2026-08-04

### The street (`ZoneBuilder`, `BUILD_VERSION` 25)

A shared soft-prop vocabulary — `addKnob`, `addScallops`, `addBunting`, `addPlanter`, plus the
fixed `CANDY` palette — forward-declared beside `addLight`/`scatterPoint` so `addZoneProps` (written
above the village section) can use it too. Everything on the street is built from those four, which
is what makes it read as one set. Bunting runs lamp-to-lamp down both sides and across the arch,
the picket fence is painted cream and capped, flower boxes sit between the lamps, crates got lids /
battens / corner blocks and a piece of fruit on the top of each stack, and the stalls got a
scalloped valance, corked bottles on the counter, a striped runner and two planters.

Two things were replaced outright because they were the worst-looking objects in the game: the
**banner cloth** (one flat untextured accent-coloured slab on a stick — a green rectangle floating
in the air) and the **arch pennons** (the same, twice, either side of the welcome arch). Both are
now crossbar + two-tone fabric + stripe + emblem + scalloped or swallow-tailed hem.

Two gotchas worth keeping:
- A Roblox **Wedge** is a triangle with the apex UP. A bunting flag needs it rolled 180° about Z
  (`CFrame.Angles(0, 0, math.pi)`), not 90° — rolled 90° every flag lies flat and the street looks
  strung with coloured drinking straws.
- The crate band used to roll its own jitter separately from the crate, putting it up to six studs
  away from the box it was strapping shut.

The world is now ~45k parts across 20 zones. **Studio drops the MCP connection fairly often right
after a full `Build()`** and comes back with only 5–7 zones; the build itself is fine, just
re-run it. Reconnect with `list_roblox_studios` → `set_active_studio`.

### Evolution-stage costumes (`ReplicatedStorage/Modules/StageCostume`, new)

Twenty builders, one per stage, welded onto the character and rebuilt by
`EvolutionVisuals.ApplyStage` (immediately on spawn, 0.7 s after an evolve so the 0.6 s scale tween
has landed first — a weld keeps the offset it was given, so a costume built mid-tween stays the
size the body was passing through).

**Every dimension is read off the host limb's own `Size`, never off a constant.** The body runs 1x
→ 9x across the stages, so a costume in fixed studs is a hat at one end of the game and a house at
the other; "0.34 of the head's width" is right at every scale and survives an R6 avatar too.
Pieces that move (haloes, orbiting shards, gears, clock hands) tween their weld's `C0` on a repeat
covering exactly one step of the arrangement's symmetry — no heartbeat connection anywhere.

Three findings that shaped the result, in order of how much they mattered:
1. **The dark outline is most of it.** A `Highlight` (occluded, `FillTransparency = 1`) over the
   character is why the pets read as drawn and a 30-part costume read as debris. One per character.
2. **Fewer, bigger shapes.** The Absolute first had wings + two haloes + crown + mask + pauldrons +
   six orbitals + a lit core, all in one yellow, and had no silhouette at all. It is now four
   features. A costume reads by its outline, and an outline needs gaps between the shapes making it.
3. **There is no torus primitive.** A halo built from a `Cylinder` is a solid disc — it put a
   thirteen-stud dinner plate over every late-stage player. `beadRing` builds rings from a circle
   of small blocks instead, which also suits the chunky art.

Hair and hats are hidden (never destroyed — `Clear` restores them) for every stage except Human,
which is the one stage that *is* a person.

## Arrival fix, bigger gates, and the Colosseum — 2026-08-04

### Arrival is always the +Z end now

`GetZoneSpawnCFrame` used to mirror to `z = -212` when you walked *back* down the strip, on the
reasoning that you should step out of the gate you stepped into. That stopped being true the moment
the boss moved onto the street: the boss stands at `z = -132` inside a 116-stud clearing, so
arriving from any later zone dropped the player straight onto its dais. Every arrival is now the
front gate, facing down the street — the walk is always gate → village → eggs → boss → exit rather
than being run backwards half the time. `fromZoneKey` is still in the signature (ZoneService passes
it) but no longer changes the answer.

### The gateways got bigger

`WALL_HEIGHT` 140 → 180 to make room; `PORTAL_GAP` 78 → 100, `PORTAL_OPEN_H` 104 → 138, columns
116 → 146. New on every gate: a keystone gem in the lintel, two hanging drapes with swallow tails,
four slowly turning crystals in the mouth, and a pair of horned guardian statues on plinths
flanking the approach. `PORTAL_CLEAR_HALF` 104 → 132 so the ramparts still keep clear of it.

### The Colosseum (`GameConfig.EventArena` / `EventBoss`)

A round arena at `(0, 0, 900)` — straight through a new gate in Forest's +Z wall, which is the one
boundary in the game with nothing behind it, and which stands directly behind the spawn clearing.
Sand pit, glowing dais with a sigil ring, three stepped tiers of stand with an opening at the gate,
twelve torch pylons with banners, and a countdown board high over the middle.

**One enormous boss every 30 minutes** (`intervalSeconds = 1800`, first one 120 s after server
start so early players find out what the place is for). 124 studs, 25 M health, borrows the
Antimatter Horror's rig via a new `zone.rigKey`, withdraws after 15 minutes if nobody finishes it.
**Every player who landed a hit is paid the full 60 M**, not a split — an event that pays less the
more people turn up is an event nobody turns up to. It gates nothing: no `requiresBossKey` points
at it.

The arena is deliberately **not a zone** — no unlock, no eggs, no place in the strip order — so it
never enters `UnlockedZones` and `CurrentZone` keeps naming the zone the player belongs to.
`ZoneService.SendToArena` stashes `data.EventReturnZone` and the return gate reads it.

Two geometry traps this hit, both worth remembering:
- `buildPortal` is written with **local +X pointing at the interior**. Standing it through
  `ACTIVE_FRAME` needs yaw **-90** to face +Z (180 sends the interior to -X: the gate stood in the
  right place but its steps, mat, runes and guardians all faced sideways out of the arena).
- Everything has to stand on **one ground disc sized to the outermost thing built on it**. Sized to
  the pit alone, the stand's outer tier and the return gate both hung over the void, and a player
  walking toward the way home stopped at the sand's edge with the gate out of reach.

## Loading screen, bigger platforms, four mob tiers — 2026-08-04

### Every teleport is a loading screen now

**`workspace.StreamingEnabled` is on**, which is the whole reason this was needed: the strip is
12,000 studs long, so a player moved across it arrived *before* their client had the destination and
watched a grey void fill in around them. Teleports now go through `ZoneService.travel` (nothing
writes `HumanoidRootPart.CFrame` directly any more) as a handshake:

1. freeze the character, fire `ZoneTransition` `phase = "start"` to the client
2. the client covers the screen, calls `Player:RequestStreamAroundAsync(destination)`, and answers
   on `ZoneTransitionReady` (both remotes are created on demand by `ensureRemote`)
3. **only then** does the server move the character, and fires `phase = "arrived"`
4. the client holds the cover until a downward ray finds ground, then wipes

Freezing matters as much as the cover: without it a player mid-jump keeps their velocity across the
move and falls through a floor that has not streamed yet. The client script is
`StarterPlayerScripts/ZoneTransition` — zone emoji, name card in the zone's accent, a progress bar
and a rotating tip, all built through UITheme. It enforces `MIN_SHOW = 1.15 s`: a neighbouring zone
can stream in inside one frame and a cover that flashes past reads as a glitch, not a transition.
There is a 14-second self-wipe so a lost packet can never trap a player behind it.

### The platforms are 700 x 860 (were 450 x 550)

~2.4x the area. Derived constants that moved with it: `ARRIVAL_Z` 212 → 366, `BOSS_Z` -132 → -240,
`DECO_SPREAD` 205/255 → 330/410, the landmark to z = -360, the whole street (lamps, fence, bunting,
benches, planters, arch at z = 306) extended down the longer walk, and in `BossService`
`PLATFORM_HALF_X` 225 → 350 / `GATE_APPROACH_Z` -218 → -372.

Part budget: the naive version came out at 60.7k and the boundary was eating it, so the rampart step
went 25 → 42, backdrop mesas 78 → 132, fence pickets every 9 studs with a cap on every other, one
crate corner post instead of two, two lamp roof tiers instead of three. **55.4k across 21 models.**
That is fine at runtime (streaming means a client only ever holds one corner of it) but Studio still
tends to drop the MCP connection right after a full `Build()` — just reconnect and re-run.

### Four creature tiers instead of two

`Swarmer` (12 hp, 4 s respawn, spawned in clusters of three) and `Elite` (280 hp, 55 s respawn, 34x
DNA, hits back hard) join Critter and Brute. Per zone: 12 + 8 + 4 + 2 = **26 spawns, up from 8** —
520 across the strip. All 20 zones have names and emoji for all four tiers.

Two things this forced, both improvements on their own:
- `tierName == "Brute"` checks became tier properties (`heavy`, `xp`, `plateColor`). With four tiers
  a string comparison would have had to be repeated in every rig.
- **The idle animation is one Heartbeat loop with a proximity gate and `BulkMoveTo`**, the same shape
  BossService already used. It was a `task.spawn` loop per creature at 20 Hz, which was survivable at
  160 creatures and emphatically not at 520 — 6,000 CFrame writes a tick across a strip a player can
  only see one corner of. Verified in play: a creature next to the player animates, one 900 studs
  away is perfectly still.

## Earlier that day: per-egg pet pools, rarities, and pets that follow you

All of it is live in Studio and was play-tested. **The place still has to be saved (File → Save).**

### New files

| Path | What it is |
|---|---|
| `ReplicatedStorage/Modules/PetModel.lua` | The chunky blocky pet rig (pet-simulator style): oversized cube head, flat cartoon eyes, thick dark `Highlight` outline. One builder shared by the follower pets and the pets on display over the eggs, so the same species always looks the same. Five archetypes (cat / dog / bunny / dragon / blob) chosen by a hash of the species key, coloured per species. |
| `ServerScriptService/PetFollowService.lua` | Spawns/despawns a rig per equipped pet into `workspace.EquippedPets/<userId>`, stamps `OwnerUserId` / `Slot` / `SlotCount`. It never moves them. |
| `StarterPlayer/StarterPlayerScripts/PetFollowClient.client.lua` | Does all the motion, on every client: trailing, the diagonal-gait leg swing, tail wag, ear flop, run hop and lean. Also spins the `PetDisplay`-tagged pets over the egg podiums. |

Why the split: a server that CFrames anchored parts every Heartbeat replicates at a throttled
rate and the pets visibly stutter for everyone. Moving them locally costs no bandwidth, and other
players' pets still follow *them* because the models themselves replicate normally. Part offsets
travel on the parts as `PetOffset` CFrame attributes so the client never re-derives the rig.

### Changed

- **`GameConfig`** — `PetRarities` (Common → Legendary, `bonusMult` 1.0 → 8.0), `ZONE_PETS`:
  **100 species, five per zone, one per rarity**. `GetPetBonus(tier, rarity)` multiplies tier by
  rarity, so **rarer is strictly stronger**. Egg tiers now carry a `rarityMin`/`rarityMax` window,
  so the three eggs on a podium hold three *different* lists: Basic = Common..Epic, Better = all
  five, Premium = Uncommon..Legendary. `GetEggPool`, `RollPetForEgg` and `GetEggOdds` all read the
  same `poolWeights`, so the advertised odds can never drift from the roll.
- **The eggs themselves** — one smooth stretched ball plus a cap sphere whose equator hides
  *inside* it, so only the dome pokes out: that is the pointed end, and the shell has no seam.
  Four stacked lobes were tried first and read as a beehive; two read as a snowman. Eight fat
  speckles sit half-out of the surface, biased to **+Z** (the side with the stairs and the price
  cards — the first two passes put them where nobody stands and they may as well not have existed).
  Each egg is a Model tagged `EggIdle` and floats and rocks on the client.
- **No `Highlight` on decorative rigs.** Roblox renders roughly 31 Highlights at once. With 60
  eggs plus 60 podium pets the budget was gone before the player's own pets got one, which is why
  the dark outline never appeared on anything. `PetModel.Build` takes `outline` (default on) and
  the podium pets and eggs pass it off.
- **The plaza is lit.** Its own canopy, pylons and back wall were shadowing the deck at every
  ClockTime; they no longer cast shadows, and two warm fills sit under the beam.
- **`ZoneBuilder`** (`BUILD_VERSION` 3 → 13) — each egg gets its zone's rarest reachable pet
  floating over the podium and an odds board listing every species it can give with its chance.
  The board is sized **in studs** (a pixel-sized billboard keeps its screen size at range, so the
  three boards grew into each other from across the plaza) and `MaxDistance = 34`, so it only
  appears when you walk up to the egg.
- **`PetService`** — rolls `GameConfig.RollPetForEgg(eggDef, luck)`, sends `rarity` in the hatch
  and fuse notifications.
- **`MainUI`** — pet rows show rarity: the stripe is the rarity colour, the sub-line reads
  `Legendary · Golden` with the rarity word colour-tagged via RichText. Hatch/fuse toasts are
  tinted by the rarity rolled.
- **`ServerMain`** — `PetFollowService.Init()` after `PetService.Init()`.

### Verified live

- `require` clean on all six modules; world rebuilt at `BuildVersion = 5`, no console errors.
- Forest odds, straight from the running server:
  `Basic 500 DNA` → Pebble 62.8 / Mossy 25.1 / Sparky 9.4 / Finn 2.6 (no Draco at all)
  `Better 1750` → Pebble 39.8 / Mossy 36.9 / Sparky 17.1 / Finn 5.2 / Draco 1.0
  `Premium 4500` → Mossy 29.0 / Sparky 48.9 / Finn 18.3 / Draco 3.8 (no Pebble)
- Forest shop carries 3 feature pets + 3 odds boards; screenshots show the boards hidden from
  outside the plaza and legible up close, and two equipped pets running on the ground behind the
  player, across a zone change.

### Note on the tooling

`screen_capture` drops Studio out of Play mode — it captures the edit-time viewport. Plan on one
capture per play session: start play, set up, capture, restart. Module `require` results are also
cached per Edit session, so a config edit will not be visible to an Edit-mode probe that already
required it; probe in Play instead.

## src/ vs Studio

Byte-identical (verified by `bytes` + rolling sum): `GameConfig`, `PetModel`, `PetService`,
`PetFollowService`, `PetFollowClient`, `ZoneBuilder`, `ServerMain`.

**Two files are still ahead in Studio and are NOT in this tree:**

| File | Studio | src | What is missing |
|---|---|---|---|
| `MainUI` | 71257 B / sum 1151273571 | 70433 B / sum 489215873 | the HUD-collision pass: captions inside the tiles, right column anchored to the screen bottom (it used to be buried under the Roblox player list), the pastel palette names |
| `UITheme` | 26541 B / sum 642864438 | 23858 B / sum 1521331748 | the pastel colours (`Mint`, `Sunny`, `Bubblegum`, `Lavender`, `Aqua`, `Peach`, `Coral`) and the `IconTile` caption-inside layout those depend on |

They cannot be resolved by patching — pull them whole. The cheap way is **File → Save As →
`.rbxlx`** (XML) once: every script's source is then readable straight off disk, no token cost,
and it doubles as a real backup. See `SYNC.md`.

## Still open (asked for, not yet built)

1. More detail on the action buttons per the reference art (badge ribbons, sub-labels, timers,
   count pills, glow rims).
2. Bottom bar shows the wrong stage ("Cell 0/50 DNA" while the player is Lizard).
3. The 11 lost reference screenshots (256 KB transfer-cap truncation) still need re-sending
   before visual fidelity can be judged against the original targets.
