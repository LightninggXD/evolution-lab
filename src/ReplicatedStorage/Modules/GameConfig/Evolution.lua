-- GameConfig.Evolution -- the 20-stage chain, the XP curve, the damage ladder, the raised layers and the income curve -- the numbers everything else is priced against.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== EVOLUTION CHAIN =====
-- Each stage: name, emoji, DNA cost to evolve INTO the NEXT stage, scale (visual size multiplier), color
-- 20 stages total. Rebirth checkpoints land every 5 stages (5, 10, 15, 20) -- see the
-- REBIRTH section below. cost = math.huge only on the very last stage (true end of the loop).
GameConfig.Stages = {
	{ name = "Cell",              emoji = "🧭",  cost = 12,       scale = 1.0, color = Color3.fromRGB(180, 255, 180) }, -- was 0: the first evolve fired instantly, at spawn
	{ name = "Bacteria",          emoji = "🦠",  cost = 50,       scale = 1.15, color = Color3.fromRGB(140, 220, 140) },
	{ name = "Worm",              emoji = "🐛",  cost = 250,      scale = 1.35, color = Color3.fromRGB(200, 160, 90) },
	{ name = "Lizard",            emoji = "🦎",  cost = 1200,     scale = 1.55, color = Color3.fromRGB(90, 200, 90) },
	{ name = "Wolf",              emoji = "🐺",  cost = 6000,     scale = 1.8, color = Color3.fromRGB(150, 150, 160) }, -- Rebirth Tier 1
	{ name = "Gorilla",           emoji = "🦧",  cost = 30000,    scale = 2.1, color = Color3.fromRGB(90, 70, 60) },
	{ name = "Human",             emoji = "👤",  cost = 150000,   scale = 2.4, color = Color3.fromRGB(230, 190, 150) },
	{ name = "Cyborg",            emoji = "🤖",  cost = 800000,   scale = 2.7, color = Color3.fromRGB(120, 200, 230) },
	{ name = "Alien",             emoji = "👽",  cost = 4000000,  scale = 3.0, color = Color3.fromRGB(140, 255, 140) },
	{ name = "Cosmic Being",      emoji = "☀️",  cost = 20000000, scale = 3.3, color = Color3.fromRGB(255, 220, 100) }, -- Rebirth Tier 2
	{ name = "Universe God",      emoji = "🌌",  cost = 100000000,        scale = 3.6, color = Color3.fromRGB(190, 120, 255) },
	{ name = "Star Weaver",       emoji = "🕸️",  cost = 500000000,        scale = 3.75, color = Color3.fromRGB(120, 200, 255) },
	{ name = "Time Walker",       emoji = "⏳",  cost = 2500000000,       scale = 3.9, color = Color3.fromRGB(200, 220, 255) },
	{ name = "Void Sovereign",    emoji = "🕳️",  cost = 12000000000,      scale = 4.05, color = Color3.fromRGB(60, 50, 80) },
	{ name = "Reality Architect", emoji = "🔷",  cost = 60000000000,      scale = 4.2, color = Color3.fromRGB(80, 180, 255) }, -- Rebirth Tier 3
	{ name = "Dimensional Titan", emoji = "🌐",  cost = 300000000000,     scale = 4.35, color = Color3.fromRGB(100, 220, 220) },
	{ name = "Chronos Being",     emoji = "♾️",  cost = 1500000000000,    scale = 4.5, color = Color3.fromRGB(255, 215, 150) },
	{ name = "Omniscient Entity", emoji = "👁️",  cost = 7000000000000,    scale = 4.65, color = Color3.fromRGB(255, 240, 200) },
	{ name = "Primordial Force",  emoji = "🌑",  cost = 35000000000000,   scale = 4.8, color = Color3.fromRGB(40, 20, 60) },
	{ name = "The Absolute",      emoji = "🔺",  cost = math.huge,        scale = 5.0, color = Color3.fromRGB(255, 255, 255) }, -- Rebirth Tier 4 (true max)
}

-- Every evolve cost is multiplied by this. The literal table above keeps the original readable
-- numbers, and the scale exists so the whole curve can be retuned from one place. It is set to 10
-- because the un-scaled costs were small enough that a readable per-kill reward (~6 DNA, rather
-- than the 0.58 an unscaled curve produced -- which the client floors to a demoralising "+0")
-- would have cleared the first several stages in two or three kills.
GameConfig.EvolveCostScale = 10

for _, stage in ipairs(GameConfig.Stages) do
	if stage.cost ~= math.huge then
		stage.cost = math.floor(stage.cost * GameConfig.EvolveCostScale)
	end
end

-- ===== XP: THE LEVEL BAR =====
-- XP is earned ONLY by fighting (creatures and bosses -- never from clicking or from DNA), and
-- unlike the old design it IS SPENT: evolving takes the stage's `xpCost` off the total and the bar
-- starts again from zero. `xpCost` is therefore a PER-LEVEL requirement, not a running lifetime
-- total -- "fill the bar, evolve, fill it again" -- which is the only reading of it that survives
-- twenty stages. As a cumulative threshold the last stage asked for 26,650 XP at 1 XP a kill.
--
-- Three numbers set the whole pace, and they are meant to be read together with the zone XP
-- multiplier derived further down:
--   * growth 1.55 is ALSO the per-zone creature XP multiplier. Because the requirement and the
--     payout grow by the same factor, kills-per-level is a flat number across the whole game
--     instead of drifting -- change one and you must change the other.
--   * start 50 puts the first evolve at ~25 Critters (or 50 Swarmers, or 10 Brutes).
--   * ramp adds 6 % of a level's worth of kills per stage on top, so a stage near the end of the
--     chain is about twice the commitment of the first one. Progression is deliberately
--     XP-gated rather than DNA-gated: DNA is multiplied by pets, mutations, potions and zone
--     bonuses and can be inflated by a factor of thousands, so a DNA-paced chain collapses the
--     moment a player has a good collection. Nothing multiplies XP except the XP potion.
GameConfig.XpPerLevelStart = 50
GameConfig.XpPerLevelGrowth = 1.55
GameConfig.XpPerLevelRamp = 0.06

-- What the FIRST evolve of a brand new player costs, in XP. 1 = a single kill of anything, because
-- the weakest creature in the first zone is worth exactly 1 and every other tier is a multiple of
-- it. Applied in GetEvolveStep, to the first step only -- see the block there for why this is not
-- a change to the curve.
GameConfig.FirstEvolveXp = 1

for i, stage in ipairs(GameConfig.Stages) do
	if stage.cost == math.huge then
		stage.xpCost = math.huge
	else
		stage.xpCost = math.floor(GameConfig.XpPerLevelStart
			* GameConfig.XpPerLevelGrowth ^ (i - 1)
			* (1 + (i - 1) * GameConfig.XpPerLevelRamp))
	end
end

-- ===== THE LAST STAGE STILL HAS FOUR EVOLVES INSIDE IT =====
-- `cost = math.huge` on stage 20 means "there is no stage after this one", and every max-evolution
-- check in the game reads it that way. It therefore cannot double as the PRICE of the steps taken
-- inside that stage (see GameConfig.GetEvolveStep -- every skin is its own evolve now), so the
-- final stage's step price is extrapolated off the curve it sits at the end of: the chain
-- multiplies by ~5 a stage and stage 19 holds the last real number.
GameConfig.FinalStageStepMult = 5
GameConfig.FinalStageStepCost = math.floor(
	GameConfig.Stages[#GameConfig.Stages - 1].cost * GameConfig.FinalStageStepMult)
GameConfig.FinalStageStepXp = math.floor(GameConfig.XpPerLevelStart
	* GameConfig.XpPerLevelGrowth ^ (#GameConfig.Stages - 1)
	* (1 + (#GameConfig.Stages - 1) * GameConfig.XpPerLevelRamp))

-- ===== THE DAMAGE LADDER: ONE CURVE, AND IT IS THE EVOLUTION CHAIN ITSELF =====
--
-- WHAT WAS WRONG, MEASURED RATHER THAN GUESSED (2026-08-09). Damage was
-- `8 + (stageIndex - 1) * 6` -- LINEAR, running 8 at stage 1 to 122 at stage 20, a factor of 15
-- across the whole game. Creature health is GEOMETRIC: the tier base times `mobHealthMult`, which
-- runs 1x in Forest to 1050x on the Absolute Plane. Fifteen against a thousand.
--
-- Both ends broke, in opposite directions, and the reported symptom was the first one:
--
--   * AT THE BOTTOM the player was already past the cap on the first click of a new save.
--     `CreatureService` clamped a blow to `tier.health / minHits`, so in Forest that is 4 on a
--     Swarmer and 7 on a Critter -- for a stage-1 player AND for a stage-20 one. The Journal
--     promised more damage per evolution and the number over the creature never moved, because
--     nothing the player did could push it below a ceiling they had already been over since their
--     first swing. That is the "evolving does nothing" bug, and it was a display of the cap.
--   * AT THE TOP the same linear curve fell 17x short of the health it was fighting, so the late
--     zones were only passable through Rebirth damage. A mechanic meant to be a choice was load
--     bearing, which is why "after rebirthing I progress far too slowly" kept coming back.
--
-- THE FIX IS TO MAKE DAMAGE GEOMETRIC IN THE ONE THING THE PLAYER IS ACTUALLY DOING: the 100-step
-- character ladder. Rank 1 is the first Cell, rank 100 the last Absolute, five rungs to a stage,
-- one rung per evolve. So `1.076^5 = 1.4425`, which is `mobHealthMult`'s own per-zone ratio
-- (1050^(1/19) = 1.442, measured). The two curves are now the same curve.
--
-- What that buys, and it is the property worth protecting when tuning either constant: KILLS PER
-- CREATURE ARE FLAT ACROSS THE WHOLE GAME. Checked at both ends --
--
--   zone  1, rank  1:  Swarmer 2.4 hits | Critter  6 hits | Brute 14 hits
--   zone 20, rank 96:  Swarmer 2.4 hits | Critter  6 hits | Brute 14 hits
--
-- and inside one stage the five evolves cut a Critter from 6 hits to 4, which is the whole point:
-- the step is felt, and then the next zone hands the difficulty back. This is exactly the shape
-- `GetClickBase` already uses for DNA (see the INCOME CURVE block) -- one growth constant chosen so
-- that a unit of progress means the same thing at every point on the curve.
--
-- Verify after changing either constant -- these must stay flat, not merely finite:
--   hits(zone i, rank r) = TIERS[t].health * Zones[i].mobHealthMult / GetRankDamage(r)
GameConfig.DamageBase = 5             -- what rank 1 hits for, bare: a 12hp Forest Swarmer in 3
GameConfig.DamageGrowthPerRank = 1.076 -- ^5 = 1.4425 = the per-zone creature health ratio

-- A boss is a gate, so it is priced in the same unit everything else is: how many honest blows it
-- takes at the reference damage for its own zone -- and every multiplier the player has bought or
-- climbed to cuts into that.
--
-- 150, UP FROM 60, AND THE OLD FIGURE WAS PRICED AGAINST THE WRONG CREATURE.
--
-- 60 blows was chosen as "roughly four times a Brute", which it is: a Brute is 70 base, i.e. 14
-- blows, in every zone. But the Brute is not the toughest thing in the valley -- the Elite is, at
-- **280 base, i.e. 56 blows**. So a boss was one Elite. And a creature that has been cleared before
-- comes back tougher (CreatureService's generation growth, +5% per clearance to a hard x2), which
-- puts a farmed Elite at 112 blows -- **twice its own zone's boss**.
--
-- Measured across all twenty zones before the change, boss health against the Elite guarding the
-- same ground: 0.84x to 1.07x fresh, and **0.42x to 0.54x** once the Elite had been farmed. Eighteen
-- of the twenty bosses in this game had less health than an ordinary creep standing a hundred studs
-- away. That is the bug report "bosses are weaker than the creeps" as arithmetic, and it was not a
-- feeling: it was true in every zone.
--
-- The derivation itself was never the problem and stays -- pricing a boss in blows is what keeps it
-- the same fight on every rung of the ladder. What was missing is that it knew about one creature
-- tier and not the other. See BossEliteFloor below for the half that makes it stay fixed.
GameConfig.BossTargetHits = 150

-- ===== THE TWO CREATURE NUMBERS THE BOSS CURVE HAS TO KNOW ABOUT =====
--
-- These are `CreatureService`'s, and they live here because the boss table is built at module load
-- in this file and has to be able to ask. CreatureService reads them back rather than keeping its
-- own copies -- the same rule MaxOwnedPets follows, and for the same reason: two private copies of
-- one number is just a way for them to drift, and this particular drift is what produced a boss
-- weaker than a creep.
GameConfig.EliteBaseHealth = 280
-- CreatureService's generation growth cap: a spawn point that has been cleared enough times brings
-- its creature back at double health, and never more.
GameConfig.CreatureGenerationMax = 2.0

-- THE FLOOR, and it is what stops this inverting again the next time a curve is tuned.
--
-- A boss must be worth at least this many WORST-CASE Elites -- worst case meaning one that has been
-- farmed to the generation cap, because that is the creature the player is actually comparing it
-- against after an hour in the zone. Expressed as a multiple rather than as twenty more hand-typed
-- numbers, so `mobHealthMult`, `EliteBaseHealth` and the generation cap can all move and the two
-- curves stay tied by construction.
--
-- THE TWO TERMS ARE VERY NEARLY THE SAME CURVE, and that is worth knowing before tuning either.
-- The damage ladder climbs 1.076^5 = 1.4425 per zone and `mobHealthMult` climbs 1050^(1/19) = 1.442
-- -- deliberately identical, see the note at the top of this file. So the blows term and the Elite
-- term run parallel, and which one wins in a given zone comes down to rounding. Measured at 150
-- hits: the floor binds in zones 2-17 and the blows term binds at both ends, and the ratio the
-- player experiences is flat at 2.50x a fresh Elite either way. The floor is therefore not a
-- correction to the shape of the curve -- it is the thing that keeps the boss curve ATTACHED to the
-- creature curve, so that moving one without the other cannot silently invert them again.
GameConfig.BossEliteFloor = 1.25

-- ===== A DEEPER ZONE IS ACTUALLY HARDER NOW (32.7), AND THAT IS A DELIBERATE BREAK =====
--
-- Her instruction, given while she was playing 32.7: *"samo nek bossovi i creaturi na vecim
-- stagevima budu jaci"* -- the bosses and creatures on the higher stages should be stronger. They
-- were not, and that was BY CONSTRUCTION rather than by accident: read the paragraph above this
-- one. The damage ladder climbs 1.4425 a zone and `mobHealthMult` climbs 1.442 a zone, deliberately
-- identical, so blows-to-fell was FLAT from Forest to the Absolute Plane -- a Swarmer was 2.4 blows
-- in zone 1 and 2.4 blows in zone 20, and the boss was a flat 150 everywhere.
--
-- That flatness was the right answer to the bug it was written for (a cap that made every creature
-- die in the same number of hits whatever you brought) and it is the wrong answer to the question
-- "does the last zone feel like the last zone". It made the strip twenty reskins of one fight.
--
-- x1.06 a zone, geometric, so zone 1 is untouched at x1.00 and zone 20 is x3.03. What that buys, in
-- blows for a BARE player: Swarmer 2.4 -> 7.3, Brute 14 -> 42, zone boss 150 -> 455. A geared
-- player still shreds the creatures, because the sword (x5), the level (x4.8) and the rebirths all
-- apply to a creature in full -- it is only a BOSS that feels the whole of this, since
-- `GetBossDamageDivisor` cancels those three.
--
-- ===== THREE THINGS THIS DELIBERATELY DOES NOT DO =====
--
-- 1. **It does not touch `mobDamageMult`.** Health is the only safe lever here: `retaliateDamage`
--    scales off `mobDamageMult` and `hurtPlayer` then caps a blow at `MaxHealth / (requiredHits*2)`
--    -- so raising HEALTH raises `requiredHits` too and the cap falls by the same factor. The whole
--    exchange still costs at most half a health bar, it just lasts longer. Raising the damage term
--    instead would make deep zones lethal rather than long, which is not what was asked for.
-- 2. **It is applied to the boss's FINAL health, both terms of the `math.max` at once** (see
--    `Zones`), never to one of them. The two terms are the blows curve and the Elite floor, and the
--    entire point of that floor is that the boss curve stays ATTACHED to the creature curve --
--    scaling one side only is precisely the silent inversion 11.9 was written about.
-- 3. **It does not change what anything PAYS.** `mobDnaMult` and `mobXpMult` are untouched. The
--    level bar does move with it, and automatically: `GetLevelXpForDamage` awards the health a
--    target actually lost, so a creature with 3x the health is worth 3x the XP. That is why
--    `GameConfig.LevelZoneGrowth` DIVIDES this factor back out -- see the note over it.
GameConfig.MobDepthGrowth = 1.06

-- What a zone's depth multiplies creature and boss health by. Zone 1 is x1.00 by construction, so
-- nothing a new player meets changes at all.
function GameConfig.GetZoneDepthMult(zoneIndex)
	local i = math.max(math.floor(tonumber(zoneIndex) or 1), 1)
	return GameConfig.MobDepthGrowth ^ (i - 1)
end

-- ===== AND THE APEX IS CAPPED BY THAT FLOOR, BY CONSTRUCTION (11.6) =====
--
-- 11.6 adds a third raised tier, the Apex, on the highest shelf of every zone behind three
-- rebirths. A new creature tier is exactly the move that produced 11.9 -- a creep the zone's own
-- boss could not match -- so this number is not authored freely. Read the floor above: a boss is at
-- least `BossEliteFloor * EliteBaseHealth * CreatureGenerationMax * mobHealthMult`. A farmed Apex is
-- `ApexBaseHealth * CreatureGenerationMax * mobHealthMult`. Setting the second below the first
-- reduces to `ApexBaseHealth <= BossEliteFloor * EliteBaseHealth`, with the generation cap and the
-- zone multiplier cancelling out of both sides -- so the clamp needs neither of them and cannot go
-- stale when they move. **Every boss in the game stays at least as tough as the toughest creep in
-- its zone, in every zone, for any authored value below.**
--
-- The authored 350 is 1.25x an Elite, and it is deliberately modest, because health is the wrong
-- lever and 11.9 is the proof: a spongy creature is not a frightening one, it is a slow one. What
-- makes the Apex dangerous is that it hits back nearly every time and hits hard (see the Apex row in
-- CreatureService's TIERS), and what makes it worth finding is the payout multiplier below -- not
-- the size of its health bar.
GameConfig.ApexBaseHealth = math.min(350, GameConfig.BossEliteFloor * GameConfig.EliteBaseHealth)

-- ===== THE TERRACES ARE A REBIRTH REWARD NOW (11.6) =====
--
-- Until this row, `raised` was a boolean and bought exactly one thing: the right to drop an
-- Evolution Shard (9.4). It is now the LAYER INDEX into this table -- 1 or 2, still nil on the
-- valley floor, so every `if raised` in the codebase keeps meaning what it meant. That was chosen
-- over a second parameter because `raised` already has to be threaded through `spawnCreature`'s
-- respawn, and one thing threaded correctly beats two things threaded nearly correctly.
--
-- WHY THE PAYOUT MAY MOVE HERE WHEN GENERATION MAY NOT. There is a rule in CreatureService that a
-- kill must never pay more just because you have killed more, and the generation growth deliberately
-- obeys it. This is a different axis and does not touch it: a terrace creature pays more because it
-- is gated -- behind a climb, and now behind a rebirth that cost the player their whole run -- not
-- because it has been farmed. Farming an Apex still gets slowly worse, exactly like farming anything
-- else.
--
-- `petChance` is per kill, and layer 2's pool is species that exist in NO egg. That is the actual
-- reward: layer 1 pays better and can hand over a pet you could also have hatched, layer 2 hands
-- over one you could not have obtained any other way.
--
-- ===== AND THE DIAMOND WAS THE ONE CURRENCY THE GATE DID NOT PAY (32.5) =====
--
-- Her ask was *"neki mobovi zahtevaju rebirth ... daju vise dna i dijamanata"* -- more DNA **and**
-- more diamonds. Only the first half was ever built: `RollDiamondDrop` took a tier name and nothing
-- else, so a rebirth-gated creature rolled the same odds as the one standing on the open ground
-- next to it.
--
-- AND THE EFFECT WAS NOT "NO BONUS", IT WAS A PENALTY -- which is why the plan's framing ("the
-- diamonds half is missing") understates it. A camp's diamond rate is `sum(count / respawn) x
-- chance`, and the gated camps are deliberately SPARSE and SLOW: three Brutes on a 16 s timer, two
-- Elites on 55 s, ONE Apex on 120 s, against a swarm camp's four Critters on 9 s plus three
-- Swarmers on 4 s. The rarer tier's higher odds come nowhere near covering that respawn -- a player
-- who spent three rebirths to be let into the Apex clearing farmed diamonds at a fraction of the
-- rate of the first camp outside the village. The gate did not merely fail to reward: it charged
-- for the privilege of earning less. Same defect 11.31 found one level down inside the tier table
-- -- an axis was added and the payout was never asked about it.
--
-- ===== MEASURED IN THE PLACE, 2026-08-23, PARKED AT ONE CAMP AND LETTING THE RESPAWNS COME =====
-- The real AutoAttack remote fired from the Client datamodel at the client's own 0.34 s cadence,
-- diamonds and kills read off the real DataUpdate payload -- the technique the 11.11 band above was
-- measured with. Each row is one uninterrupted parked run with this row's code live:
--
--     camp             layer  kills  seconds  diamonds  per kill  per hour
--     NW1 swarm          0      101    110.0       4      0.040      131
--     NW3 brute          0       79    100.2       2      0.025       72
--     SW2 raidBrute      1       39    190.3      18      0.462      341
--     SW3 raidElite      1        4    110.3       4      1.000      131
--     SW4/SW5 apex       2        2    110.2      14      7.000      457
--
-- THE PER-KILL COLUMN IS THE PROOF AND THE PER-HOUR COLUMN IS THE POINT. 0.462 / 1.000 / 7.000
-- against the 0.45 / 1.20 / 7.20 this table asks for; pooled, the 45 gated kills paid 36 diamonds
-- against 36.75 predicted -- a 2% match on the multiplier itself. The same 45 kills under the old
-- tier-only roll predict **8.65**, so the gate is worth a measured 4.2x more than it was, and the
-- open ground moved by nothing: 180 layer-0 kills paid 6 against 6.7 predicted, which is the
-- control this row needed, since `RollDiamondDrop` with no layer is the old function exactly.
--
-- `diamondMult` MIRRORS `dnaMult`, and that is the design rather than a coincidence. One number per
-- layer governs what the gate is worth, both currencies read it, and a third layer cannot be added
-- with one of them silently missing (`AssertTierCoverage` checks this table now too). The ceiling
-- it moves is one the prices can absorb: the diamond ladder is written against ~120/h (see the
-- Diamonds part) and the fastest thing on this map is now 457/h in a clearing you must have
-- rebirthed three times to be allowed to stand in.
--
-- The layer-1 raidBrute camp out-earning the layer-1 raidElite camp per HOUR (341 against 131) is
-- real and is left alone: per KILL an Elite pays 2.2x a Brute, and the inversion is the map's own
-- density -- three bodies on a 16 s timer against two on 55 s -- not the drop table's. It is
-- identical in DNA today. A roster question, not this row's.
--
-- The two gated samples are small (4 kills and 2 kills) because that IS the camp: a 55 s and a
-- 120 s respawn cannot be sampled faster by any probe, and pushing for n would have measured a
-- walk between clearings instead of a farm. The per-kill figures carry the weight.
GameConfig.RaisedLayers = {
	{ minRebirths = 1, dnaMult = 3.0,  xpMult = 2.0, diamondMult = 3.0,  petChance = 0.02, exclusive = false },
	{ minRebirths = 3, dnaMult = 12.0, xpMult = 5.0, diamondMult = 12.0, petChance = 0.05, exclusive = true },
}

-- The layer a creature belongs to, or nil for the valley floor. Takes the raw `raised` value so
-- every caller asks the same question of it and nothing indexes the table by hand.
function GameConfig.GetRaisedLayer(raised)
	return GameConfig.RaisedLayers[raised or 0]
end

-- Whether this save may fight a creature of that layer. The CLIENT greys the creature out with this
-- and the SERVER refuses with it -- one predicate, two independent uses, which is the same shape the
-- rebirth shrine uses (see RebirthShrineClient's header on why the client copy is never the real
-- check). A valley creature has no layer and is therefore always fightable.
function GameConfig.CanFightRaised(data, raised)
	local layer = GameConfig.GetRaisedLayer(raised)
	if not layer then return true end
	return ((data and data.Rebirths) or 0) >= layer.minRebirths
end

-- Raw damage at a rung of the ladder. Takes a NUMBER, not a save, so it is safe to call at module
-- load (the boss table below does) and safe on the client (the Journal prints it under every
-- entry). This is the single place the curve exists.
function GameConfig.GetRankDamage(rank)
	rank = math.max(1, math.floor(tonumber(rank) or 1))
	return GameConfig.DamageBase * GameConfig.DamageGrowthPerRank ^ (rank - 1)
end

-- What a player standing at the front of zone `i` hits for, bare. Zone i unlocks at stage i and a
-- stage is five rungs, so the first rung of stage i is rank 5(i-1)+1. Used to price the bosses and
-- to sanity-check the creature tiers; nothing at runtime reads it.
function GameConfig.GetZoneReferenceDamage(zoneIndex)
	local i = math.max(1, math.floor(tonumber(zoneIndex) or 1))
	return GameConfig.GetRankDamage((i - 1) * 5 + 1)
end

-- ===== WHAT THE ZONE EXPECTS YOU TO BE CARRYING (33.33) =====
--
-- `GetZoneReferenceDamage` above is the BARE player, and for a long time it was the only reference
-- state the config had. That is the hole every "the boss died in two blows" measurement falls into:
-- boss health is priced off a player with no pets, no upgrades and no mastery, and the real player
-- who reaches that boss is carrying all three.
--
-- MEASURED, not invented. The three terms are read off the same tables the game charges for:
--
--   income    `Upgrades.Income` caps at 5 levels a zone at +1% each -> `1 + 0.05 * z`
--   mastery   one Stage Mastery rung a stage at +12% each          -> `1 + 0.12 * z`
--   pets      six slots (3 free + 3 diamond), climbing in rarity and tier with depth
--
-- The pet term is the only one that is not a config identity, because what a player has EQUIPPED
-- is a behaviour rather than a rule. It is a smoothed geometric fit through a measured ladder --
-- x1.96 with six Uncommon Normals in Forest, x21.16 with six Legendary Celestials on the Absolute
-- Plane -- and it is deliberately a SMOOTH curve rather than a twenty-row table: the mid-strip
-- reads about a third under the measured stack (x6.1 against x8.0 at Nebula), which errs toward
-- treating a player as UNDER-geared, and every consumer of this number must be safe in that
-- direction. It is an expectation. It is never a description of a particular save.
--
-- WHAT IT IS FOR: content priced against this number keeps its length for the player it was built
-- for, gets slower for one who arrives under-geared, and faster for one who arrives over-geared --
-- which is the shape the whole `+1` genre gates on, and the shape the owner asked for in 33.34.
-- `GetBossBlowDivisor` is the first caller.
GameConfig.ExpectedPetMultBase = 1.96
GameConfig.ExpectedPetMultGrowth = 1.133

function GameConfig.GetZoneExpectedGear(zoneIndex)
	-- `Zones` is composed into GameConfig by a later file, so the count is read defensively: this
	-- function is safe to call at module load the way `GetRankDamage` above it is.
	local last = GameConfig.Zones and #GameConfig.Zones or 20
	local z = math.clamp(math.floor(tonumber(zoneIndex) or 1), 1, last)
	local income = 1 + 0.05 * z
	local mastery = 1 + 0.12 * z
	local pets = GameConfig.ExpectedPetMultBase * GameConfig.ExpectedPetMultGrowth ^ (z - 1)
	return income * mastery * pets
end

-- ===== AND THE WHOLE STACK THAT ZONE EXPECTS, WHICH IS WHAT A CREATURE IS PRICED AGAINST (33.34) =====
--
-- `GetZoneExpectedGear` above is the part a BOSS cares about, because the boss divisor already
-- cancels the blade, the level and the rebirth. A CREATURE cancels nothing: every multiplier the
-- player owns lands on it in full. So a creature has to be priced against the whole expected stack,
-- and that is the difference between the two functions.
--
-- **THE MEASUREMENT THIS EXISTS TO FIX (2026-08-27).** Creature health climbs x1.53 a zone
-- (`mobHealthMult` 1.442 x `MobDepthGrowth` 1.06) and the geared player's damage climbs **x2.08** a
-- zone. The player outgrows the content every zone, twenty times over, and the result was measured:
-- a normally geared player ONE-SHOTS a Critter from zone 2 and a farmed Elite from zone 6. The
-- damage ladder had stopped meaning anything long before the Absolute Plane.
--
-- **AND A STEEPER HEALTH CURVE CANNOT FIX IT** -- that was measured too. A curve making zone-20
-- mobs 14.5x heavier still leaves the geared player at 0.02 blows; restoring a six-blow Critter
-- would take x288 on today's health. `guidelines/plus-one-progression-2026.md` has the genre
-- evidence for why steepening is the wrong lever anyway: every successful game in the sample holds
-- its per-area ratio FLAT, and the two that steepen it are the two with famous endgame walls.
--
-- So the health curve is not steepened. It is priced against the player the zone expects, which
-- holds blows-to-fell FLAT -- the genre's actual target -- and produces the owner's `+1` loop for
-- free: arrive under-geared and the same creature takes many times longer, upgrade and it comes
-- back down. Her words: *"mogu i sa manje ali dugo traje pa je poenta da se upgradea"*.
--
-- ===== WHAT IS IN THE EXPECTATION, AND WHAT IS DELIBERATELY LEFT OUT =====
--
-- IN, because a normal player holds all of it by the time they stand there: the gear above
-- (income, pets, mastery), the blade, the level ladder and the rebirth count.
--
-- OUT, on purpose, and this is the whole reward structure: **training, potions, passes, relics and
-- the VIP wardrobe are NOT expected.** Everything left out is a multiplier that makes the player
-- FASTER THAN THE ZONE EXPECTS -- which is exactly what a x3.00 trained ladder or a bought pass
-- should buy. If they were folded in here, the content would rise to meet them and the purchase
-- would buy nothing, which is the mistake that made this row necessary in the first place.
--
-- The blade, the level and the rebirth are read from the same tables the game charges for; only
-- WHICH rung a player is expected to be on is authored, and it is authored as a straight line
-- through the ladder (one blade every other zone, level 8 -> 38, a rebirth every fifth zone).
function GameConfig.GetZoneExpectedStack(zoneIndex)
	local last = GameConfig.Zones and #GameConfig.Zones or 20
	local z = math.clamp(math.floor(tonumber(zoneIndex) or 1), 1, last)
	local gear = GameConfig.GetZoneExpectedGear(z)
	-- ten blades over twenty zones
	local swordLevel = math.clamp(math.floor((z + 1) / 2), 1, GameConfig.MaxSwordLevel or 10)
	local sword = (GameConfig.Swords and GameConfig.Swords[swordLevel]
		and GameConfig.Swords[swordLevel].damageMult) or 1
	-- the rebirth gates sit at levels 20/23/26/29, so the expected level runs 8 at the first zone
	-- to 38 at the last
	local level = 8 + 30 * (z - 1) / (last - 1)
	local levelMult = 1 + (level - 1) * (GameConfig.LevelDamagePct or 5) / 100
	-- four milestones, at stages 5/10/15/20
	local rebirthMult = GameConfig.GetRebirthDamageMult({ Rebirths = math.clamp(math.floor(z / 5), 0, 4) })
	return gear * sword * levelMult * rebirthMult
end

-- The factor a creature's health is multiplied by, NORMALISED TO ZONE 1 -- so Forest is untouched
-- to the studs and the first ten minutes of the game are exactly what they were. Everything after
-- Forest rises to meet the player the zone expects.
--
-- It is a MULTIPLIER ON TOP of `mobHealthMult` and `GetZoneDepthMult` rather than a replacement for
-- either: those two are the authored shape of the strip (which zones feel like a step up) and this
-- is the correction that makes the shape mean the same thing at both ends of it.
function GameConfig.GetZoneMobScale(zoneIndex)
	return GameConfig.GetZoneExpectedStack(zoneIndex) / GameConfig.GetZoneExpectedStack(1)
end

-- ===== AND WHAT THE LONGER FIGHT COSTS THE FARM, PAID BACK EXACTLY (33.34) =====
--
-- The scale above makes a creature take more blows, and blows are TIME. Left alone, that is a
-- silent nerf to every DNA price in the game: a player who used to fell a Nebula Critter in one
-- blow now needs four, so DNA an hour falls by four and every evolve, egg and upgrade priced
-- against the old rate quietly costs four times as long.
--
-- The owner's call, taken with the fork: *"DNA po killu raste istim faktorom"* -- the farm rate is
-- held where it is. This is the factor that does it, and it is deliberately NOT `GetZoneMobScale`:
-- paying x1,348 at the Absolute Plane would inflate the economy by two hundred times. What is owed
-- is the ratio of the fight that WAS to the fight that IS -- and the fight that was is one blow,
-- because that is the floor: you cannot fell a creature in less than a single swing, and that floor
-- is the whole reason a x1,348 health scale does not cost x1,348 of time.
--
--     zone  1  x1.00  (Forest never changed -- the scale is normalised there)
--     zone  5  x2.92
--     zone 10  x4.10
--     zone 20  x5.82
--
-- XP IS DELIBERATELY NOT COMPENSATED. A level is meant to get harder -- *"ostali leveli tj zone
-- moraju biti tezi"* and, in 33.32, *"dosta dosta tezi"* -- and a longer fight for the same XP is
-- precisely that, arrived at without touching the XP curve. This is the one place the two rows
-- pull in the same direction and it is worth being explicit that it is on purpose.
function GameConfig.GetZoneMobDnaScale(zoneIndex)
	local last = GameConfig.Zones and #GameConfig.Zones or 20
	local z = math.clamp(math.floor(tonumber(zoneIndex) or 1), 1, last)
	if z == 1 then return 1 end
	-- blows-to-fell for the player the zone expects, which is the bare curve divided by the stack
	-- the first zone already expects -- see the derivation over `GetZoneMobScale`
	local zone = GameConfig.Zones[z]
	if not zone then return 1 end
	local bare = 30 * zone.mobHealthMult * GameConfig.GetZoneDepthMult(z)
		/ GameConfig.GetZoneReferenceDamage(z)
	local now = bare * GameConfig.GetZoneMobScale(z) / GameConfig.GetZoneExpectedStack(z)
	local before = math.max(bare / GameConfig.GetZoneExpectedStack(z), 1)
	return math.max(now / before, 1)
end

-- ===== MUTATIONS ARE ROLLED AT THE DNA SPLICER (Phase 12) =====
-- They used to roll THEMSELVES: a server loop fired every ~10 seconds for as long as a player
-- was online, nothing was ever removed, and the ladder topped at x30 income -- a hidden faucet
-- the player never pulled. Two patches in a row (best-one-applies, then a capped additive
-- tail) stopped it compounding, but the shape stayed wrong: income moved while the player did
-- nothing, and the whole system was invisible -- no UI named it, no action triggered it.
--
-- Now a mutation exists only because the player PAID for a roll at the Splicer machine
-- (GameConfig.Splicer, below RollMutation), and exactly ONE is active at a time
-- (`data.SplicerMutation`). One active mutation deletes the stacking questions outright, so
-- MutationStackBonus / MutationStackCap died with the ambient loop.

function GameConfig.GetMutationByName(name)
	for _, m in ipairs(GameConfig.Mutations) do
		if m.name == name then return m end
	end
	return nil
end

-- Takes the SAVE, not a list of names -- the caller has it in hand and the active mutation is
-- a field of it. The legacy branch covers a save still in a live server's memory when this
-- code arrives: the best of the old rolled list counts until PlayerDataService converts it to
-- `SplicerMutation` on that save's next load. (Index order IS rarity order in `Mutations`.)
function GameConfig.GetMutationIncomeMult(data)
	local name = data and data.SplicerMutation
	if not name and data and data.Mutations then
		local bestIdx = 0
		for _, owned in ipairs(data.Mutations) do
			for i, m in ipairs(GameConfig.Mutations) do
				if m.name == owned and i > bestIdx then bestIdx = i end
			end
		end
		if bestIdx > 0 then name = GameConfig.Mutations[bestIdx].name end
	end
	local m = name and GameConfig.GetMutationByName(name)
	return m and m.incomeMult or 1
end

-- A PERCENTAGE OF THE WALK CAP, NOT FLAT STUDS (15.30). It used to be flat studs added beside
-- GetSpeedUpgradeBonus, INSIDE the clamp -- and measured on the owner's max-stage save the term
-- before the clamp was 581.58 against a cap of 260, so the whole seven-stud ladder (52 studs after
-- the size multiplier) fell off the end and no aura choice moved the character by one stud, while
-- both the Auras panel and the boost card kept printing the bonus. The ladder is now a share of
-- whatever ceiling that player has, added AFTER the clamp by applyMastery, so it lands in full at
-- every stage -- at 1x, at max, and with or without the 2x Speed pass. Renamed rather than
-- redefined in place: a reader still asking for `speedBonus` gets nil and fails loudly instead of
-- quietly printing studs that are now percent.
function GameConfig.GetMutationSpeedPct(data)
	local m = data and data.SplicerMutation and GameConfig.GetMutationByName(data.SplicerMutation)
	return (m and m.speedPct) or 0
end

-- ===== INCOME CURVE =====
-- DNA earned per click and per creature kill has to grow at the same rate as the evolve costs,
-- or progression drifts apart. The old base -- `1 + (stageIndex - 1) * 0.5` -- grew about 2x per
-- stage against a ~5x cost curve, so leaving Cell took 5 kills while leaving Star Weaver took
-- 30,812. Too generous at the start, impossible at the end, which is the same defect twice.
--
-- Costs rise ~5x per stage. Two multipliers already ride along with progression: the zone DNA
-- multiplier (~1.45x per zone) and the cumulative zone income bonus (~1.22x per zone). So the
-- click base only has to supply the remainder, 5 / (1.45 * 1.22) ~= 2.85x. Anchoring the start
-- at 0.13 lands every stage between 14 and 20 creature kills, from Cell to Primordial Force.
--
-- Verify after changing either constant -- kills per stage should stay flat:
--   perKill(i) = GetClickBase(i) * (1 + GetTotalZoneBonusPct(zones 1..i)/100) * 4.5 * Zones[i].mobDnaMult
--   kills(i)   = Stages[i].cost / perKill(i)
-- 1.3 pairs with EvolveCostScale = 10 above: it puts the very first creature kill at ~5.9 DNA
-- (readable -- the client floors the notification, so anything under 1 shows as "+0") and the
-- first evolve at ~21 kills.
GameConfig.ClickBaseStart = 1.3
GameConfig.ClickBaseGrowth = 2.85

function GameConfig.GetClickBase(stageIndex)
	return GameConfig.ClickBaseStart * (GameConfig.ClickBaseGrowth ^ ((stageIndex or 1) - 1))
end

end
