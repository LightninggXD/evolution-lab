local GameConfig = {}

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
GameConfig.RaisedLayers = {
	{ minRebirths = 1, dnaMult = 3.0,  xpMult = 2.0, petChance = 0.02, exclusive = false },
	{ minRebirths = 3, dnaMult = 12.0, xpMult = 5.0, petChance = 0.05, exclusive = true },
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

-- Flat studs, the same shape as GetSpeedUpgradeBonus and applied beside it: it lands BEFORE
-- the body-size multiplier, so a bonus rolled at Cell is worth proportionally more later. The
-- column used to be a `speedMult` that NOTHING read -- this is the first time the mutation's
-- second stat is true.
function GameConfig.GetMutationSpeedBonus(data)
	local m = data and data.SplicerMutation and GameConfig.GetMutationByName(data.SplicerMutation)
	return (m and m.speedBonus) or 0
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

-- ===== UPGRADES =====
-- baseCost grows by costMult per level. effect described per stat.
--
-- COST MULTIPLIERS RAISED 2026-08-11 (1.14-1.22 -> 1.28-1.38) on the owner's report that upgrades
-- came far too fast. They are capped now as well -- see GetUpgradeMaxLevel, five levels per unlocked
-- zone -- and the two changes are meant to be read together: the cap decides how FAR you may go,
-- the multiplier decides how long each rung takes.
--
-- Measured against the cap rather than guessed. Full ladder totals at the three points that matter:
--            zone 1 (5 lv)   zone 5 (25 lv)   zone 20 (100 lv)
--   Speed         216            42.7K             4.7T
--   Income        175            40.0K             7.9T
--   Luck          373           129.1K           142.7T
--   AutoCollect   1.1K          826.1K            25.6Qa
-- Cheap enough that a new player can buy the five they are allowed, and a genuine sink at the top
-- against an endgame DNA balance of roughly 1e18.
--
-- `Mutation` ("Mutation Chance") is GONE, not merely delisted (Phase 12): the ambient roll it
-- fed no longer exists -- mutations are bought at the DNA Splicer -- so the upgrade had nothing
-- left to speed up. Paid levels are refunded at their exact geometric sum by the load
-- migration in PlayerDataService, which carries the base 60 / mult 1.35 as literals because
-- this table no longer does.
GameConfig.Upgrades = {
	Speed = {
		displayName = "Speed",
		emoji = "👟",
		baseCost = 25,
		costMult = 1.28,
		description = "Moves you faster around the lab",
	},
	Income = {
		displayName = "Income",
		emoji = "💰",
		baseCost = 20,
		costMult = 1.29,
		description = "+DNA per click and per second",
	},
	Luck = {
		-- Renamed and rewritten with 11.5's split: this is now EGG luck and nothing else, at
		-- +5 points a level (GameConfig.PetLuckPerUpgradeLevel). The old text named crit DNA and
		-- mutations, which stopped being true the moment the upgrade left GetLuckPercent -- see
		-- the note over that function.
		displayName = "Egg Luck",
		emoji = "🍀",
		baseCost = 40,
		costMult = 1.32,
		description = "+5% egg luck a level - rarer pets from every hatch",
	},
	AutoCollect = {
		displayName = "Auto Collect",
		emoji = "⚙️",
		baseCost = 100,
		costMult = 1.38,
		description = "Earns DNA every second, even while you idle",
	},
}

-- ===== MUTATIONS =====
-- Rolled ONLY at the DNA Splicer now. Index order is rarity order -- the pity guarantee, the
-- announce threshold and "which of two is better" all compare indices, so a new entry goes in
-- rank position, never appended out of order. Repriced with the Splicer (was 1.3 .. 30): these
-- are BOUGHT now, and a x30 top end would let one lucky roll outweigh the entire Income
-- upgrade ladder. `speedBonus` is flat studs of walk speed (see GetMutationSpeedBonus).
GameConfig.Mutations = {
	{ name = "Common",    weight = 500, incomeMult = 1.05, speedBonus = 1, color = Color3.fromRGB(200,200,200) },
	{ name = "Rare",      weight = 200, incomeMult = 1.10, speedBonus = 2, color = Color3.fromRGB(90,160,255) },
	{ name = "Epic",      weight = 80,  incomeMult = 1.18, speedBonus = 3, color = Color3.fromRGB(170,90,255) },
	{ name = "Legendary", weight = 25,  incomeMult = 1.30, speedBonus = 4, color = Color3.fromRGB(255,180,50) },
	{ name = "Mythic",    weight = 8,   incomeMult = 1.50, speedBonus = 5, color = Color3.fromRGB(255,80,80) },
	{ name = "Secret",    weight = 2,   incomeMult = 1.80, speedBonus = 6, color = Color3.fromRGB(20,20,20) },
	{ name = "Godly",     weight = 1,   incomeMult = 2.25, speedBonus = 8, color = Color3.fromRGB(255,240,150) },
}

-- ===== ZONES =====
-- unlockStageIndex: player must have reached this GameConfig.Stages index to unlock the zone
-- offset: X position offset (studs) along the zone road, each platform is 260 studs wide
-- incomeBonusPct: permanent % income bonus granted once the zone is unlocked (cumulative)
-- mobHealthMult/mobDamageMult/mobDnaMult: how much stronger (and more rewarding) regular
-- creatures in this zone are compared to Forest baseline -- creatures get tougher zone by zone.
-- requiresBossKey: the PREVIOUS zone's boss must be defeated (by this player) before this zone
-- unlocks, on top of reaching unlockStageIndex -- this is what gates progression on boss kills.
-- ZONE SPACING IS A FUNCTION OF HOW WIDE A ZONE ACTUALLY IS. It was 630 when a platform was 450
-- studs wide (a 180-stud gap between them). The platforms were later widened to 700 x 860 and this
-- number was never moved with them -- so from Desert onward every platform OVERLAPPED its
-- neighbour by 70 studs of floor, and the zone MODELS (which run ~1030 studs wide once the rock
-- rampart and the two rows of backdrop mesas behind each wall are counted) overlapped by ~400.
--
-- Everything that looked broken about the boundaries came from that one number:
--   * the next zone's backdrop mesas stood on this zone's platform, and they are CanCollide = false
--     -- so a player walked straight through what looks like a solid white cliff;
--   * creature spawn points out near |x| = 300 landed inside those mesas: a monster in a wall;
--   * two zones' walls, ramparts and mesas interpenetrated, which is what the map reads as from
--     the air.
--
-- The platform was then widened 700 -> 900 (there was finally room for it), which takes the zone
-- model to ~1230. 1500 clears that with ~270 studs of daylight between neighbours. The strip is
-- longer for it (0 -> 28,500) and that costs nothing: travel between zones is a teleport through
-- ZoneService, and StreamingEnabled means a client only ever holds the zone it is standing in.
-- If a platform is ever widened again, this has to move with it.
GameConfig.ZoneSpacing = 1900
-- 20 zones total, one per evolution stage (zone i unlocks at stage i). Zones 10-20 continue
-- the cosmic/abstract escalation started by Galaxy/BlackHole/Multiverse.
GameConfig.Zones = {
	{ key = "Forest",          name = "Forest",            emoji = "🌲", unlockStageIndex = 1,  offset = 0,          groundColor = Color3.fromRGB(74, 140, 74),   accentColor = Color3.fromRGB(40, 100, 40),   incomeBonusPct = 0,   mobHealthMult = 1.0,    mobDamageMult = 1.0,  mobDnaMult = 1.0,    requiresBossKey = nil },
	{ key = "Desert",          name = "Desert",            emoji = "🏜️", unlockStageIndex = 2,  offset = 1500,    groundColor = Color3.fromRGB(230, 200, 120), accentColor = Color3.fromRGB(190, 150, 80),  incomeBonusPct = 5,   mobHealthMult = 1.6,    mobDamageMult = 1.3,  mobDnaMult = 1.7,    requiresBossKey = "Forest" },
	{ key = "Ocean",           name = "Ocean",             emoji = "🌊", unlockStageIndex = 3,  offset = 3000,    groundColor = Color3.fromRGB(60, 140, 200),  accentColor = Color3.fromRGB(30, 90, 150),   incomeBonusPct = 10,  mobHealthMult = 2.4,    mobDamageMult = 1.6,  mobDnaMult = 2.6,    requiresBossKey = "Desert" },
	{ key = "Volcano",         name = "Volcano",           emoji = "🌋", unlockStageIndex = 4,  offset = 4500,    groundColor = Color3.fromRGB(60, 40, 40),    accentColor = Color3.fromRGB(220, 80, 30),   incomeBonusPct = 15,  mobHealthMult = 3.6,    mobDamageMult = 2.0,  mobDnaMult = 4.0,    requiresBossKey = "Ocean" },
	{ key = "Moon",            name = "Moon",              emoji = "🌙", unlockStageIndex = 5,  offset = 6000,    groundColor = Color3.fromRGB(170, 170, 175), accentColor = Color3.fromRGB(120, 120, 130), incomeBonusPct = 20,  mobHealthMult = 5.2,    mobDamageMult = 2.5,  mobDnaMult = 5.8,    requiresBossKey = "Volcano" },
	{ key = "Mars",            name = "Mars",              emoji = "🔴", unlockStageIndex = 6,  offset = 7500,    groundColor = Color3.fromRGB(190, 90, 60),   accentColor = Color3.fromRGB(140, 60, 40),   incomeBonusPct = 25,  mobHealthMult = 7.5,    mobDamageMult = 3.0,  mobDnaMult = 8.5,    requiresBossKey = "Moon" },
	{ key = "Galaxy",          name = "Galaxy",            emoji = "🌌", unlockStageIndex = 7,  offset = 9000,    groundColor = Color3.fromRGB(60, 40, 100),   accentColor = Color3.fromRGB(140, 90, 220),  incomeBonusPct = 35,  mobHealthMult = 11.0,   mobDamageMult = 3.7,  mobDnaMult = 12.5,   requiresBossKey = "Mars" },
	{ key = "BlackHole",       name = "Black Hole",        emoji = "⚫", unlockStageIndex = 8,  offset = 10500,  groundColor = Color3.fromRGB(10, 10, 12),    accentColor = Color3.fromRGB(80, 30, 120),   incomeBonusPct = 50,  mobHealthMult = 16.0,   mobDamageMult = 4.6,  mobDnaMult = 18.0,   requiresBossKey = "Galaxy" },
	{ key = "Multiverse",      name = "Multiverse",        emoji = "🌀", unlockStageIndex = 9,  offset = 12000,  groundColor = Color3.fromRGB(20, 20, 30),    accentColor = Color3.fromRGB(255, 100, 220), incomeBonusPct = 75,  mobHealthMult = 24.0,   mobDamageMult = 5.7,  mobDnaMult = 27.0,   requiresBossKey = "BlackHole" },
	{ key = "Nebula",          name = "Nebula",            emoji = "🌠", unlockStageIndex = 10, offset = 13500,  groundColor = Color3.fromRGB(120, 60, 160),  accentColor = Color3.fromRGB(180, 100, 220), incomeBonusPct = 100, mobHealthMult = 34.0,   mobDamageMult = 6.5,  mobDnaMult = 38.0,   requiresBossKey = "Multiverse" }, -- Rebirth Tier 2 zone
	{ key = "Wormhole",        name = "Wormhole",          emoji = "🕳️", unlockStageIndex = 11, offset = 15000,  groundColor = Color3.fromRGB(30, 30, 50),    accentColor = Color3.fromRGB(120, 80, 200),  incomeBonusPct = 130, mobHealthMult = 48.0,   mobDamageMult = 7.4,  mobDnaMult = 54.0,   requiresBossKey = "Nebula" },
	{ key = "QuantumRealm",    name = "Quantum Realm",     emoji = "⚛️", unlockStageIndex = 12, offset = 16500,  groundColor = Color3.fromRGB(40, 120, 140),  accentColor = Color3.fromRGB(80, 220, 220),  incomeBonusPct = 165, mobHealthMult = 68.0,   mobDamageMult = 8.4,  mobDnaMult = 76.0,   requiresBossKey = "Wormhole" },
	{ key = "TimeRift",        name = "Time Rift",         emoji = "⏳", unlockStageIndex = 13, offset = 18000,  groundColor = Color3.fromRGB(90, 70, 40),    accentColor = Color3.fromRGB(230, 190, 80),  incomeBonusPct = 205, mobHealthMult = 95.0,   mobDamageMult = 9.6,  mobDnaMult = 108.0,  requiresBossKey = "QuantumRealm" },
	{ key = "AntimatterZone",  name = "Antimatter Zone",   emoji = "💥", unlockStageIndex = 14, offset = 19500,  groundColor = Color3.fromRGB(60, 10, 10),    accentColor = Color3.fromRGB(255, 60, 60),   incomeBonusPct = 250, mobHealthMult = 135.0,  mobDamageMult = 11.0, mobDnaMult = 152.0,  requiresBossKey = "TimeRift" },
	{ key = "DreamDimension",  name = "Dream Dimension",   emoji = "💭", unlockStageIndex = 15, offset = 21000,  groundColor = Color3.fromRGB(70, 40, 100),   accentColor = Color3.fromRGB(200, 140, 255), incomeBonusPct = 300, mobHealthMult = 190.0,  mobDamageMult = 12.5, mobDnaMult = 215.0,  requiresBossKey = "AntimatterZone" }, -- Rebirth Tier 3 zone
	{ key = "MirrorUniverse",  name = "Mirror Universe",   emoji = "🪞", unlockStageIndex = 16, offset = 22500,  groundColor = Color3.fromRGB(150, 150, 170), accentColor = Color3.fromRGB(220, 220, 255), incomeBonusPct = 360, mobHealthMult = 265.0,  mobDamageMult = 14.2, mobDnaMult = 300.0,  requiresBossKey = "DreamDimension" },
	{ key = "VoidExpanse",     name = "Void Expanse",      emoji = "🌑", unlockStageIndex = 17, offset = 24000,  groundColor = Color3.fromRGB(5, 5, 10),      accentColor = Color3.fromRGB(140, 60, 220),  incomeBonusPct = 430, mobHealthMult = 375.0,  mobDamageMult = 16.2, mobDnaMult = 420.0,  requiresBossKey = "MirrorUniverse" },
	{ key = "CelestialThrone", name = "Celestial Throne",  emoji = "👑", unlockStageIndex = 18, offset = 25500,  groundColor = Color3.fromRGB(200, 180, 120), accentColor = Color3.fromRGB(255, 225, 140), incomeBonusPct = 510, mobHealthMult = 525.0,  mobDamageMult = 18.5, mobDnaMult = 590.0,  requiresBossKey = "VoidExpanse" },
	{ key = "Singularity",     name = "Singularity",       emoji = "💫", unlockStageIndex = 19, offset = 27000,  groundColor = Color3.fromRGB(15, 15, 20),    accentColor = Color3.fromRGB(255, 255, 255), incomeBonusPct = 600, mobHealthMult = 740.0,  mobDamageMult = 21.0, mobDnaMult = 830.0,  requiresBossKey = "CelestialThrone" },
	{ key = "AbsolutePlane",   name = "The Absolute Plane",emoji = "🔺", unlockStageIndex = 20, offset = 28500,  groundColor = Color3.fromRGB(255, 255, 255), accentColor = Color3.fromRGB(255, 215, 0),   incomeBonusPct = 700, mobHealthMult = 1050.0, mobDamageMult = 24.0, mobDnaMult = 1170.0, requiresBossKey = "Singularity" }, -- Rebirth Tier 4 zone (true endgame)
}

-- The offsets are written out per row because that is how the table reads at a glance, but the
-- SPACING is the thing that has to hold: one row edited by hand to a value that disagrees with
-- ZoneSpacing puts a platform inside its neighbour, and that is a bug you only ever see from the
-- air. Derived here so the two can never drift apart again -- the literals above are documentation.
for i, zone in ipairs(GameConfig.Zones) do
	zone.offset = (i - 1) * GameConfig.ZoneSpacing
	-- What one creature kill in this zone is worth in XP, against the Forest baseline. It is the
	-- SAME growth factor the per-level requirement uses, on purpose: that is what keeps
	-- kills-per-level flat from Forest to the Absolute Plane. Without it a Void Expanse Swarmer
	-- paid the same 1 XP a Forest one did, against a requirement 26,000 times larger.
	-- Deliberately NOT mobDnaMult: that curve is much steeper (1x -> 1170x) because it has to keep
	-- up with an exponential evolve COST, and XP is not spent on anything else.
	zone.mobXpMult = GameConfig.XpPerLevelGrowth ^ (i - 1)
end

-- ===== ZONE BOSSES =====
-- One boss guards the exit of every zone. A player must personally defeat a zone's boss
-- (in addition to reaching the next zone's unlockStageIndex) before the next zone opens for them.
-- Bosses respawn after being defeated so every player gets their own shot at them.
-- size: the rig UNIT, not a diameter -- BossService builds every part as a fraction of it, and a
-- finished rig stands roughly 1.5-2x this tall. At 18 the Forest bear is already five times a
-- player; the Absolute tops out near 120 studs, just under the 140-stud zone walls.
GameConfig.ZoneBosses = {
	Forest          = { name = "Alpha Bear",           emoji = "🐻", health = 500,     retaliateChance = 0.6,  retaliateDamage = {10, 18},    dnaReward = 300,     size = 18, respawnDelay = 40 },
	Desert          = { name = "Sand Wyrm",            emoji = "🐍", health = 1400,    retaliateChance = 0.62, retaliateDamage = {16, 26},    dnaReward = 900,     size = 20, respawnDelay = 42 },
	Ocean           = { name = "Kraken",               emoji = "🐙", health = 3200,    retaliateChance = 0.64, retaliateDamage = {22, 34},    dnaReward = 2200,    size = 22, respawnDelay = 44 },
	Volcano         = { name = "Magma Titan",          emoji = "🌋", health = 6800,    retaliateChance = 0.66, retaliateDamage = {30, 46},    dnaReward = 5200,    size = 24, respawnDelay = 46, auraRange = 12, auraDamage = {6, 10}, auraInterval = 1.5 },
	Moon            = { name = "Lunar Colossus",       emoji = "🌙", health = 13000,   retaliateChance = 0.68, retaliateDamage = {40, 60},    dnaReward = 11000,   size = 26, respawnDelay = 48, auraRange = 12, auraDamage = {8, 14}, auraInterval = 1.5 },
	Mars            = { name = "War Golem",            emoji = "🔴", health = 24000,   retaliateChance = 0.70, retaliateDamage = {55, 80},    dnaReward = 22000,   size = 28, respawnDelay = 50, auraRange = 13, auraDamage = {12, 18}, auraInterval = 1.4 },
	Galaxy          = { name = "Nebula Wraith",        emoji = "🌌", health = 44000,   retaliateChance = 0.72, retaliateDamage = {75, 110},   dnaReward = 42000,   size = 30, respawnDelay = 52, auraRange = 13, auraDamage = {16, 24}, auraInterval = 1.4 },
	BlackHole       = { name = "Void Devourer",        emoji = "⚫", health = 80000,   retaliateChance = 0.74, retaliateDamage = {100, 150},  dnaReward = 78000,   size = 33, respawnDelay = 55, auraRange = 14, auraDamage = {22, 32}, auraInterval = 1.3 },
	Multiverse      = { name = "Multiverse Sovereign", emoji = "🌀", health = 150000,  retaliateChance = 0.76, retaliateDamage = {140, 200},  dnaReward = 150000,  size = 36, respawnDelay = 60, auraRange = 15, auraDamage = {28, 40}, auraInterval = 1.3 },
	Nebula          = { name = "Nebula Devourer",      emoji = "🌠", health = 260000,  retaliateChance = 0.78, retaliateDamage = {170, 240},  dnaReward = 260000,  size = 38, respawnDelay = 62, auraRange = 15, auraDamage = {32, 46}, auraInterval = 1.2 },
	Wormhole        = { name = "Wormhole Horror",      emoji = "🕳️", health = 440000,  retaliateChance = 0.80, retaliateDamage = {200, 280},  dnaReward = 450000,  size = 40, respawnDelay = 64, auraRange = 16, auraDamage = {38, 54}, auraInterval = 1.2 },
	QuantumRealm    = { name = "Quantum Phantom",      emoji = "⚛️", health = 750000,  retaliateChance = 0.82, retaliateDamage = {240, 330},  dnaReward = 780000,  size = 42, respawnDelay = 66, auraRange = 16, auraDamage = {45, 64}, auraInterval = 1.1 },
	TimeRift        = { name = "Chronos Beast",        emoji = "⏳", health = 1250000, retaliateChance = 0.84, retaliateDamage = {290, 390},  dnaReward = 1300000, size = 44, respawnDelay = 68, auraRange = 17, auraDamage = {54, 76}, auraInterval = 1.1 },
	AntimatterZone  = { name = "Antimatter Horror",    emoji = "💥", health = 2100000, retaliateChance = 0.86, retaliateDamage = {350, 470},  dnaReward = 2200000, size = 46, respawnDelay = 70, auraRange = 17, auraDamage = {64, 90}, auraInterval = 1.0 },
	DreamDimension  = { name = "Nightmare Weaver",     emoji = "💭", health = 3500000, retaliateChance = 0.88, retaliateDamage = {420, 560},  dnaReward = 3700000, size = 48, respawnDelay = 72, auraRange = 18, auraDamage = {76, 106}, auraInterval = 1.0 },
	MirrorUniverse  = { name = "Mirror Tyrant",        emoji = "🪞", health = 5800000, retaliateChance = 0.90, retaliateDamage = {500, 660},  dnaReward = 6100000, size = 50, respawnDelay = 74, auraRange = 18, auraDamage = {90, 124}, auraInterval = 0.95 },
	VoidExpanse     = { name = "Void Colossus",        emoji = "🌑", health = 9600000, retaliateChance = 0.92, retaliateDamage = {590, 780},  dnaReward = 10000000, size = 52, respawnDelay = 76, auraRange = 19, auraDamage = {106, 146}, auraInterval = 0.9 },
	CelestialThrone = { name = "Throne Guardian",      emoji = "👑", health = 15800000,retaliateChance = 0.94, retaliateDamage = {700, 920},  dnaReward = 16500000, size = 54, respawnDelay = 78, auraRange = 19, auraDamage = {124, 170}, auraInterval = 0.9 },
	Singularity     = { name = "The Singularity",      emoji = "💫", health = 26000000,retaliateChance = 0.96, retaliateDamage = {820, 1080}, dnaReward = 27000000, size = 56, respawnDelay = 80, auraRange = 20, auraDamage = {144, 198}, auraInterval = 0.85 },
	AbsolutePlane   = { name = "The Absolute",         emoji = "🔺", health = 43000000,retaliateChance = 0.98, retaliateDamage = {960, 1260}, dnaReward = 45000000, size = 60, respawnDelay = 85, auraRange = 20, auraDamage = {168, 230}, auraInterval = 0.8 },
}

-- ===== WHERE A BOSS STANDS =====
-- THIS LIVES HERE BECAUSE TWO FILES NEED IT AND THEY DRIFTED APART. BossService parks the rig at
-- this Z; ZoneBuilder keeps the scatter out of the same circle so decoration never lands on the
-- arena. They were separate constants and a platform-depth rescale updated one and not the other
-- -- the boss ended up 80 studs from the ground that had been cleared for it, so props grew
-- through the fight while the reserved clearing sat empty. Both files read these now.
--
-- The station is close to the exit gate on purpose: the boss is the thing standing in front of
-- the next door, and it should be the first thing you see when you look down the street. The gate
-- itself is at -PLATFORM_DEPTH/2 = -575 and its approach steps begin at -502, so this leaves room
-- for even the largest rig to stand clear of the steps.
GameConfig.BossStationZ = -368
-- Radius kept free of scattered decoration. Sized off the biggest finished rig: a bounding box of
-- ~2.4x the boss size, so ~290 studs across at the top of the table, plus a margin for the biome
-- builders that place two or three parts around one scatter point.
GameConfig.BossStationClear = 178

-- ===== BOSS REVIVE =====
--
-- What the product actually sells, stated plainly because the frustration it addresses is easy to
-- describe wrongly. A boss nobody has touched for BOSS_REGEN_DELAY (14 s) heals fully over
-- BOSS_REGEN_TIME (20 s). The walk back from a respawn is about 31 s -- Roblox's 5 s respawn, the
-- 0.35 s ZoneService wait, then ~858 studs from the arrival gate at Z 490 to the station at Z -368
-- at the base walk speed. So a player does NOT reliably lose everything; they typically come back
-- to a boss that has healed most, not all, of what they took off it. The pitch is "keep your
-- progress", never "you always lose everything", and the code should not pretend otherwise.
--
-- TTL: how long the snapshot of your best health against a boss stays spendable. It has to cover a
-- Robux purchase modal, the respawn and the walk back, and it has to be short enough that nobody
-- banks an hour-old fight. Three minutes clears the first with room and fails the second.
GameConfig.BossReviveTTL = 180
-- After a revive lands, regen is held off for this long REGARDLESS of the 14 s idle delay -- because
-- the buyer is usually still walking back at the moment it lands, and a revive that healed away
-- while they crossed the street would be the same complaint with a receipt attached.
GameConfig.BossReviveFreeze = 30

-- The bosses were tuned as a speed bump on the way to the next portal, and at 18-60 studs they
-- read as a big mob rather than the raid monster the art brief asks for. Applied as one pass over
-- the finished table instead of retyping twenty rows, which is also the only way the three curves
-- below stay in step with each other by construction.
--
-- health and dnaReward move by the SAME factor on purpose: the fight gets longer and the payout
-- gets bigger in proportion, so DNA per second is untouched and no zone's progression shifts.
-- Retaliation is raised on its own -- that is the part that makes a boss feel dangerous rather
-- than merely slow.
local BOSS_SIZE_MULT = 4.2
local BOSS_HEALTH_MULT = 1.6
local BOSS_HURT_MULT = 1.3

local function scaleRange(range, mult)
	return { math.floor(range[1] * mult), math.floor(range[2] * mult) }
end

-- A FLAT MULTIPLIER WORKS FOR THE EARLY BOSSES AND BREAKS THE LATE ONES, so the gain tapers as
-- the base size grows. A rig's built bounding box runs about 2.4x its `size`, and it has to fit
-- down the street between the egg plaza and the exit gate's approach steps -- roughly 360 studs
-- of room -- so the top of the table is what sets the ceiling, not the bottom.
--
-- 18 -> 75 and 60 -> 121, against 52 and 121 at the last pass. THE GAIN IS ALL IN THE FIRST
-- TWELVE ZONES ON PURPOSE, and it is the cap rather than the multiplier that decides that: the
-- late rigs were already standing on the geometric ceiling. The station is at Z = -368 and the
-- exit gate's approach steps begin at -502, so a rig may reach about 134 studs back before it
-- starts growing through the steps -- and its banner masts sit at 1.16x the boss size. 121 puts
-- them at 140, which is already the margin spent. Raising the cap would bury the gate, so it
-- stays where it is and the multiplier is what moves: Forest 52 -> 75, Ocean 64 -> 88,
-- Galaxy 87 -> 95, and everything from Black Hole on is on the cap and barely changes.
--
-- The min of two increasing terms is increasing, so the curve cannot fold back on itself no
-- matter what the table holds.
--
-- Watch the damage aura when changing this: spawnBoss uses `max(boss.auraRange, boss.size * 0.85)`
-- and the size term is what wins, so a bigger boss also hurts from further out -- Volcano's aura
-- goes 59 -> 76 studs here. That is intended (it means "as far as the rig reaches") but it is a
-- balance change, not just a visual one.
--
-- Two things scale off `size` on their own and therefore move with this: the click reach in
-- spawnBoss, and the damage aura (`math.max(boss.auraRange, boss.size * 0.85)`). Both are meant
-- to mean "as far out as the rig itself reaches", so growing with it is correct -- but it does
-- make the late bosses dangerous from further away than they used to be.
local function scaledBossSize(size)
	return math.floor(math.min(size * BOSS_SIZE_MULT, 70 + size * 0.85))
end

for _, boss in pairs(GameConfig.ZoneBosses) do
	boss.size = scaledBossSize(boss.size)
	boss.health = math.floor(boss.health * BOSS_HEALTH_MULT)
	boss.dnaReward = math.floor(boss.dnaReward * BOSS_HEALTH_MULT)
	boss.retaliateDamage = scaleRange(boss.retaliateDamage, BOSS_HURT_MULT)
	if boss.auraDamage then
		boss.auraDamage = scaleRange(boss.auraDamage, BOSS_HURT_MULT)
	end
	if boss.auraRange then
		boss.auraRange = math.floor(boss.auraRange * BOSS_SIZE_MULT)
	end
end

for i, zone in ipairs(GameConfig.Zones) do
	zone.boss = GameConfig.ZoneBosses[zone.key]

	-- ===== BOSS HEALTH IS DERIVED, NOT AUTHORED =====
	--
	-- The twenty numbers in `ZoneBosses` ran 500 to 43,000,000 -- a factor of 86,000 across the
	-- strip, against creature health's 1,050 and the damage ladder's 1,394. Nothing could clear the
	-- late ones: at the reference damage for its own zone, The Absolute took 8,160 blows. It was
	-- passable only because `BossService` clamped every hit to `health / BOSS_MIN_HITS`, which meant
	-- a boss died in exactly twelve blows in every zone from the first to the last -- the same
	-- defect as the creature `damageCap`, and the same reason a boss never felt like it was being
	-- worn down: the bar moved 1/12th whatever the player brought to it.
	--
	-- Priced in blows instead, off the same ladder as everything else, so a boss is the same length
	-- of fight in the zone it guards on every rung. The authored `health` is now only a relative hint
	-- that nothing reads -- `dnaReward` keeps its own authored value and its own scaling, because
	-- what a boss PAYS is a design decision and what it TAKES is arithmetic.
	--
	-- THE MAX IS NOT DECORATION. The blows term alone put every boss in the game under the Elite of
	-- its own zone -- see the note on BossTargetHits, where the measurement is written out. The floor
	-- term is what ties the boss curve to the creature curve, so tuning `mobHealthMult` cannot pull
	-- them apart again in silence.
	--
	-- STILL PRICED ON THE ELITE after 11.6 added a tier above it, and deliberately so. Pricing it on
	-- the Apex instead would have raised every floor-bound boss (zones 2-17) by 25% -- a balance
	-- change nobody asked for -- and it is not needed: `ApexBaseHealth` is clamped to
	-- `BossEliteFloor * EliteBaseHealth`, which is exactly the condition for a farmed Apex to stay
	-- inside this floor. The guarantee lives in the clamp, so this line did not have to move and a
	-- future row cannot break it by editing the Apex either. See the ApexBaseHealth block.
	zone.boss.health = math.max(
		math.floor(GameConfig.BossTargetHits * GameConfig.GetZoneReferenceDamage(i)),
		math.floor(GameConfig.BossEliteFloor * GameConfig.EliteBaseHealth
			* GameConfig.CreatureGenerationMax * zone.mobHealthMult))

	-- Exactly HALF a level, in the currency of the stage this zone belongs to (zone i unlocks at
	-- stage i, so the index is the same one the xpCost curve is written against). Boss XP used to be
	-- a flat 25 everywhere, which was a third of the first level and a rounding error by the tenth.
	zone.boss.xpReward = math.floor(25 * GameConfig.XpPerLevelGrowth ^ (i - 1)
		* (1 + (i - 1) * GameConfig.XpPerLevelRamp))
end

-- A zone is unlocked once the player reached its stage requirement AND (if it has one)
-- personally defeated the boss guarding the previous zone's exit.
function GameConfig.IsZoneUnlocked(zone, data)
	if data.StageIndex < zone.unlockStageIndex then
		return false
	end
	if zone.requiresBossKey then
		local defeated = false
		for _, k in ipairs(data.DefeatedBosses or {}) do
			if k == zone.requiresBossKey then
				defeated = true
				break
			end
		end
		if not defeated then
			return false
		end
	end
	return true
end

function GameConfig.GetZoneByKey(key)
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.key == key then return zone end
	end
	return nil
end

-- The zone's POSITION, which is what the damage ladder is indexed by (GetZoneReferenceDamage) --
-- `Zones` is an ordered array and zone i unlocks at stage i, so the index is the progression
-- coordinate. Returns 1 for anything unknown rather than nil: every caller here is arithmetic, and
-- a nil leaking into a multiplication is a hard error at a call site that cannot do anything
-- useful about it anyway.
function GameConfig.GetZoneIndex(key)
	for i, zone in ipairs(GameConfig.Zones) do
		if zone.key == key then return i end
	end
	return 1
end

function GameConfig.GetTotalZoneBonusPct(unlockedZoneKeys)
	local total = 0
	local lookup = {}
	for _, k in ipairs(unlockedZoneKeys) do lookup[k] = true end
	for _, zone in ipairs(GameConfig.Zones) do
		if lookup[zone.key] then
			total += zone.incomeBonusPct
		end
	end
	return total
end

-- ===== PETS =====
-- Two independent axes, which is worth stating plainly because they are easy to confuse:
--   RARITY  is the species you rolled (Common .. Legendary). Fixed at hatch, never changes.
--   TIER    is how many copies you fused together (Normal .. Celestial). See PetTiers below.
-- A Legendary Normal and a Common Celestial are both strong, for different reasons.
GameConfig.PetRarities = {
	{ name = "Common",    weight = 1000, bonusMult = 1.0, color = Color3.fromRGB(198, 202, 214) },
	{ name = "Uncommon",  weight = 400,  bonusMult = 1.6, color = Color3.fromRGB(110, 224, 130) },
	{ name = "Rare",      weight = 150,  bonusMult = 2.6, color = Color3.fromRGB(90, 170, 255) },
	{ name = "Epic",      weight = 42,   bonusMult = 4.5, color = Color3.fromRGB(190, 110, 255) },
	-- WEIGHT 8 -> 4 (2026-08-11). "Legendary pops out of the egg far too easily" -- and measured, it
	-- did: the Premium egg was handing one over 3.8% of the time in Forest and 4.4% by AbsolutePlane,
	-- i.e. about one in 22, for the rarity the whole collection is supposed to be chasing. Halving
	-- the weight is the lever that moves every pool at once; the per-tier `rarityBias` in EGG_TIERS
	-- came down with it (see the note there), because bias was doing most of the lifting.
	--
	-- These weights feed exactly one function -- `poolWeights`, which serves the egg roll and the
	-- odds board that advertises it -- so this changes what eggs produce and nothing else.
	{ name = "Legendary", weight = 4,    bonusMult = 8.0, color = Color3.fromRGB(255, 190, 60) },

	-- ===== SECRET (12.12), AND WHY ITS WEIGHT IS ZERO =====
	--
	-- A Secret is not drawn from the weighted pool at all -- it is a separate 1-in-50,000 pre-roll in
	-- `rollAndInsert`, and only on a Premium egg. The zero here is the SECOND lock on that, behind
	-- `EggablePets` excluding them and `PetsByZone` never holding one: if a future pool ever did
	-- contain a Secret by accident, `poolWeights` would give it weight `0 * boost` = 0 and the roll
	-- could still never land on it. A rarity that must not be rollable is worth defending twice.
	--
	-- `bonusMult = 12` sits above Legendary's 8 by half again, not by an order of magnitude. The
	-- thing being sold here is that you have one, and a species 10x the game's best pet would make
	-- the 49,999 hatches that did not produce it feel like a punishment rather than a lottery.
	{ name = "Secret",    weight = 0,    bonusMult = 12,  color = Color3.fromRGB(255, 64, 160) },
}

-- FIVE LONG, DELIBERATELY, and Secret is not in it. This table is POSITIONAL -- entry i of a zone's
-- species list is `PetRarityOrder[i]` -- so appending to it would silently ask every zone for a
-- sixth species and shift nothing else. It indexes the egg pools; `PetRarities` describes what a
-- rarity is worth. The two stopped being the same list the moment a rarity existed that no egg pool
-- can contain.
GameConfig.PetRarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- Which rarities are worth a 420-stud pillar of light and everybody's attention (Phase 6.2's beam,
-- and 5.4's cross-server toast when that unblocks). A set rather than a threshold on
-- `PetRarityOrder`, because the question "is this announceable" is not the same question as "is this
-- high up the ladder" -- a future event species could be worth announcing without being a Legendary.
--
-- ONE ROW IS DELIBERATE. Epic is a 42/1600 roll, i.e. one hatch in 38 before luck; adding it here
-- would mean a beam every few seconds in a busy server, and a beam that common announces nothing.
-- Secret joined it in 12.12 and needs no cooldown thought at all: at 1 in 50,000 Premium hatches it
-- is roughly four orders of magnitude rarer than the roll this table's cooldown was written for.
GameConfig.BeaconRarities = {
	Legendary = true,
	Secret = true,
}

function GameConfig.IsBeaconRarity(name)
	return GameConfig.BeaconRarities[name] == true
end

function GameConfig.GetRarity(name)
	for _, r in ipairs(GameConfig.PetRarities) do
		if r.name == name then return r end
	end
	return GameConfig.PetRarities[1]
end

-- Every zone has its own five species -- one per rarity -- so the egg you buy in Volcano can
-- never hand you a Forest pet. Forest deliberately keeps the five original keys (Pebble, Sparky,
-- Mossy, Finn, Draco) so pets in existing saves still resolve to a real definition.
local ZONE_PETS = {
	Forest = {
		{ key = "Pebble",     name = "Pebble",      emoji = "🪨", color = Color3.fromRGB(160, 160, 160) },
		{ key = "Mossy",      name = "Mossy",       emoji = "🍀", color = Color3.fromRGB(100, 200, 100) },
		{ key = "Sparky",     name = "Sparky",      emoji = "⚡", color = Color3.fromRGB(255, 220, 80) },
		{ key = "Finn",       name = "Finn",        emoji = "🐟", color = Color3.fromRGB(80, 160, 255) },
		{ key = "Draco",      name = "Draco",       emoji = "🐉", color = Color3.fromRGB(220, 60, 60) },
	},
	Desert = {
		{ key = "Scarab",     name = "Scarab",      emoji = "🪲", color = Color3.fromRGB(180, 150, 90) },
		{ key = "Cactuso",    name = "Cactuso",     emoji = "🌵", color = Color3.fromRGB(96, 170, 96) },
		{ key = "Fennec",     name = "Fennec",      emoji = "🦊", color = Color3.fromRGB(238, 202, 140) },
		{ key = "Sandwyrm",   name = "Sandwyrm",    emoji = "🐍", color = Color3.fromRGB(214, 172, 104) },
		{ key = "Sphinx",     name = "Sphinx",      emoji = "🗿", color = Color3.fromRGB(236, 208, 128) },
	},
	Ocean = {
		{ key = "Shelly",     name = "Shelly",      emoji = "🐚", color = Color3.fromRGB(248, 220, 206) },
		{ key = "Bubbles",    name = "Bubbles",     emoji = "🐠", color = Color3.fromRGB(255, 168, 92) },
		{ key = "Inky",       name = "Inky",        emoji = "🦑", color = Color3.fromRGB(168, 112, 255) },
		{ key = "Chomps",     name = "Chomps",      emoji = "🦈", color = Color3.fromRGB(96, 150, 190) },
		{ key = "Kraklet",    name = "Kraklet",     emoji = "🐙", color = Color3.fromRGB(226, 78, 128) },
	},
	Volcano = {
		{ key = "Cinder",     name = "Cinder",      emoji = "🪨", color = Color3.fromRGB(84, 62, 58) },
		{ key = "Emberling",  name = "Emberling",   emoji = "🔥", color = Color3.fromRGB(255, 148, 60) },
		{ key = "Magmite",    name = "Magmite",     emoji = "🌋", color = Color3.fromRGB(255, 96, 40) },
		{ key = "Obsidion",   name = "Obsidion",    emoji = "🖤", color = Color3.fromRGB(48, 32, 44) },
		{ key = "Pyrodrake",  name = "Pyrodrake",   emoji = "🐲", color = Color3.fromRGB(255, 72, 40) },
	},
	Moon = {
		{ key = "Dustbun",    name = "Dustbun",     emoji = "🐇", color = Color3.fromRGB(212, 212, 220) },
		{ key = "Cratercub",  name = "Cratercub",   emoji = "🌕", color = Color3.fromRGB(180, 180, 190) },
		{ key = "Lunamoth",   name = "Lunamoth",    emoji = "🦋", color = Color3.fromRGB(196, 220, 255) },
		{ key = "Tidalux",    name = "Tidalux",     emoji = "🌙", color = Color3.fromRGB(150, 200, 255) },
		{ key = "Selenith",   name = "Selenith",    emoji = "✨", color = Color3.fromRGB(236, 244, 255) },
	},
	Mars = {
		{ key = "Rustling",   name = "Rustling",    emoji = "🪨", color = Color3.fromRGB(178, 88, 56) },
		{ key = "Roverpup",   name = "Roverpup",    emoji = "🤖", color = Color3.fromRGB(214, 206, 186) },
		{ key = "Dustdevil",  name = "Dustdevil",   emoji = "🌪️", color = Color3.fromRGB(226, 152, 104) },
		{ key = "Olympus",    name = "Olympus",     emoji = "⛰️", color = Color3.fromRGB(140, 66, 44) },
		{ key = "Warlord",    name = "Warlord",     emoji = "🔴", color = Color3.fromRGB(226, 62, 42) },
	},
	Galaxy = {
		{ key = "Twinkle",    name = "Twinkle",     emoji = "⭐", color = Color3.fromRGB(255, 240, 190) },
		{ key = "Cometail",   name = "Cometail",    emoji = "☄️", color = Color3.fromRGB(150, 200, 255) },
		{ key = "Orbiton",    name = "Orbiton",     emoji = "🪐", color = Color3.fromRGB(206, 160, 110) },
		{ key = "Starforge",  name = "Starforge",   emoji = "🌟", color = Color3.fromRGB(255, 214, 120) },
		{ key = "Galactus",   name = "Galactus",    emoji = "🌌", color = Color3.fromRGB(150, 100, 230) },
	},
	BlackHole = {
		{ key = "Speck",      name = "Speck",       emoji = "⚫", color = Color3.fromRGB(52, 44, 66) },
		{ key = "Gravlet",    name = "Gravlet",     emoji = "🌀", color = Color3.fromRGB(120, 70, 170) },
		{ key = "Accretia",   name = "Accretia",    emoji = "💫", color = Color3.fromRGB(255, 170, 90) },
		{ key = "Horizon",    name = "Horizon",     emoji = "🕳️", color = Color3.fromRGB(24, 18, 32) },
		{ key = "Devourer",   name = "Devourer",    emoji = "😈", color = Color3.fromRGB(186, 80, 246) },
	},
	Multiverse = {
		{ key = "Gliph",      name = "Gliph",       emoji = "🔷", color = Color3.fromRGB(120, 190, 255) },
		{ key = "Echo",       name = "Echo",        emoji = "🪞", color = Color3.fromRGB(226, 226, 246) },
		{ key = "Splitpaw",   name = "Splitpaw",    emoji = "🐾", color = Color3.fromRGB(255, 120, 210) },
		{ key = "Paradox",    name = "Paradox",     emoji = "♾️", color = Color3.fromRGB(160, 120, 255) },
		{ key = "Everykind",  name = "Everykind",   emoji = "🌈", color = Color3.fromRGB(255, 100, 220) },
	},
	Nebula = {
		{ key = "Mistling",   name = "Mistling",    emoji = "☁️", color = Color3.fromRGB(206, 168, 236) },
		{ key = "Gasbub",     name = "Gasbub",      emoji = "🫧", color = Color3.fromRGB(180, 200, 255) },
		{ key = "Protostar",  name = "Protostar",   emoji = "🌠", color = Color3.fromRGB(255, 236, 190) },
		{ key = "Pillarion",  name = "Pillarion",   emoji = "🗼", color = Color3.fromRGB(224, 120, 236) },
		{ key = "Stellara",   name = "Stellara",    emoji = "💜", color = Color3.fromRGB(200, 120, 255) },
	},
	Wormhole = {
		{ key = "Loopling",   name = "Loopling",    emoji = "➰", color = Color3.fromRGB(140, 130, 200) },
		{ key = "Throatlet",  name = "Throatlet",   emoji = "🌀", color = Color3.fromRGB(150, 100, 245) },
		{ key = "Warpcat",    name = "Warpcat",     emoji = "🐈", color = Color3.fromRGB(200, 180, 255) },
		{ key = "Tunneler",   name = "Tunneler",    emoji = "🚇", color = Color3.fromRGB(110, 90, 190) },
		{ key = "Eventide",   name = "Eventide",    emoji = "🔮", color = Color3.fromRGB(215, 200, 255) },
	},
	QuantumRealm = {
		{ key = "Quark",      name = "Quark",       emoji = "⚛️", color = Color3.fromRGB(120, 220, 220) },
		{ key = "Blink",      name = "Blink",       emoji = "👁️", color = Color3.fromRGB(150, 255, 245) },
		{ key = "Superpaw",   name = "Superpaw",    emoji = "🐾", color = Color3.fromRGB(80, 220, 220) },
		{ key = "Entangle",   name = "Entangle",    emoji = "🧬", color = Color3.fromRGB(60, 190, 210) },
		{ key = "Schrodin",   name = "Schrodin",    emoji = "🐱", color = Color3.fromRGB(190, 255, 250) },
	},
	TimeRift = {
		{ key = "Tickling",   name = "Tickling",    emoji = "⏱️", color = Color3.fromRGB(200, 168, 100) },
		{ key = "Sandglass",  name = "Sandglass",   emoji = "⌛", color = Color3.fromRGB(238, 208, 130) },
		{ key = "Cogsworth",  name = "Cogsworth",   emoji = "⚙️", color = Color3.fromRGB(160, 124, 64) },
		{ key = "Rewind",     name = "Rewind",      emoji = "⏪", color = Color3.fromRGB(190, 214, 236) },
		{ key = "Chronos",    name = "Chronos",     emoji = "⏳", color = Color3.fromRGB(255, 214, 110) },
	},
	AntimatterZone = {
		{ key = "Ionling",    name = "Ionling",     emoji = "🔋", color = Color3.fromRGB(180, 90, 80) },
		{ key = "Flarepup",   name = "Flarepup",    emoji = "💥", color = Color3.fromRGB(255, 140, 110) },
		{ key = "Contain",    name = "Contain",     emoji = "🧨", color = Color3.fromRGB(248, 208, 40) },
		{ key = "Nullion",    name = "Nullion",     emoji = "⚠️", color = Color3.fromRGB(255, 70, 70) },
		{ key = "Annihil",    name = "Annihil",     emoji = "☢️", color = Color3.fromRGB(255, 40, 40) },
	},
	DreamDimension = {
		{ key = "Napkin",     name = "Napkin",      emoji = "😴", color = Color3.fromRGB(226, 208, 246) },
		{ key = "Fluffle",    name = "Fluffle",     emoji = "🫧", color = Color3.fromRGB(255, 206, 236) },
		{ key = "Sleepaw",    name = "Sleepaw",     emoji = "🐑", color = Color3.fromRGB(240, 240, 255) },
		{ key = "Reverie",    name = "Reverie",     emoji = "💭", color = Color3.fromRGB(200, 160, 255) },
		{ key = "Sandman",    name = "Sandman",     emoji = "🌜", color = Color3.fromRGB(214, 150, 255) },
	},
	MirrorUniverse = {
		{ key = "Shardlet",   name = "Shardlet",    emoji = "🔹", color = Color3.fromRGB(200, 214, 238) },
		{ key = "Reflekt",    name = "Reflekt",     emoji = "🪞", color = Color3.fromRGB(226, 232, 250) },
		{ key = "Twinpaw",    name = "Twinpaw",     emoji = "👯", color = Color3.fromRGB(180, 200, 255) },
		{ key = "Inverso",    name = "Inverso",     emoji = "🔃", color = Color3.fromRGB(150, 170, 220) },
		{ key = "Mirrorch",   name = "Mirrorch",    emoji = "💠", color = Color3.fromRGB(240, 248, 255) },
	},
	VoidExpanse = {
		{ key = "Nibble",     name = "Nibble",      emoji = "🕸️", color = Color3.fromRGB(60, 50, 78) },
		{ key = "Hollow",     name = "Hollow",      emoji = "🌑", color = Color3.fromRGB(38, 30, 52) },
		{ key = "Unraveler",  name = "Unraveler",   emoji = "🧵", color = Color3.fromRGB(148, 62, 228) },
		{ key = "Nihil",      name = "Nihil",       emoji = "⬛", color = Color3.fromRGB(20, 16, 28) },
		{ key = "Voidmaw",    name = "Voidmaw",     emoji = "👾", color = Color3.fromRGB(170, 80, 255) },
	},
	CelestialThrone = {
		{ key = "Cherub",     name = "Cherub",      emoji = "👼", color = Color3.fromRGB(255, 238, 200) },
		{ key = "Haloling",   name = "Haloling",    emoji = "😇", color = Color3.fromRGB(255, 226, 150) },
		{ key = "Seraphim",   name = "Seraphim",    emoji = "🕊️", color = Color3.fromRGB(255, 250, 226) },
		{ key = "Regalia",    name = "Regalia",     emoji = "👑", color = Color3.fromRGB(255, 218, 128) },
		{ key = "Throneus",   name = "Throneus",    emoji = "⚜️", color = Color3.fromRGB(255, 200, 70) },
	},
	Singularity = {
		{ key = "Point",      name = "Point",       emoji = "⚪", color = Color3.fromRGB(226, 230, 244) },
		{ key = "Collapse",   name = "Collapse",    emoji = "🌐", color = Color3.fromRGB(190, 200, 226) },
		{ key = "Infinion",   name = "Infinion",    emoji = "♾️", color = Color3.fromRGB(255, 255, 255) },
		{ key = "Densita",    name = "Densita",     emoji = "🔘", color = Color3.fromRGB(150, 156, 180) },
		{ key = "Omegapoint", name = "Omega Point", emoji = "💫", color = Color3.fromRGB(255, 255, 255) },
	},
	AbsolutePlane = {
		{ key = "Gilder",     name = "Gilder",      emoji = "🔸", color = Color3.fromRGB(255, 232, 170) },
		{ key = "Monolith",   name = "Monolith",    emoji = "🗿", color = Color3.fromRGB(248, 248, 244) },
		{ key = "Aurelian",   name = "Aurelian",    emoji = "🏅", color = Color3.fromRGB(255, 215, 0) },
		{ key = "Absolon",    name = "Absolon",     emoji = "🔺", color = Color3.fromRGB(255, 226, 120) },
		{ key = "TheFirst",   name = "The First",   emoji = "🥇", color = Color3.fromRGB(255, 240, 190) },
	},
}

-- ===== APEX-ONLY PETS =====
-- One species per zone that no egg can ever hatch. The only source is a kill on that zone's Apex,
-- so a player who has not cleared 3 rebirths cannot hold one. Shaped like a ZONE_PETS entry and
-- keyed by zone, but deliberately kept OUT of ZONE_PETS so the egg roll can never reach it -- the
-- rarity of these is the whole point. Every key is unique against the 100 in ZONE_PETS, and the
-- colours are the prestige read of each zone's palette: brighter and cleaner than the egg pets,
-- never the muddy version.
local EXCLUSIVE_PETS = {
	Forest          = { key = "Sylvanking", name = "Sylvan King", emoji = "\u{1F333}",         color = Color3.fromRGB(90, 235, 120) },
	Desert          = { key = "Vitreon",    name = "Vitreon",     emoji = "\u{1F3FA}",         color = Color3.fromRGB(255, 198, 72) },
	Ocean           = { key = "Leviathan",  name = "Leviathan",   emoji = "\u{1F40B}",         color = Color3.fromRGB(64, 232, 255) },
	Volcano         = { key = "Moltenking", name = "Molten King", emoji = "\u{2604}\u{FE0F}",  color = Color3.fromRGB(255, 128, 24) },
	Moon            = { key = "Lunarch",    name = "Lunarch",     emoji = "\u{1F320}",         color = Color3.fromRGB(222, 240, 255) },
	Mars            = { key = "Ironcrown",  name = "Iron Crown",  emoji = "\u{1F6E1}\u{FE0F}", color = Color3.fromRGB(255, 96, 64) },
	Galaxy          = { key = "Spiralux",   name = "Spiralux",    emoji = "\u{1F300}",         color = Color3.fromRGB(196, 148, 255) },
	BlackHole       = { key = "Abyssos",    name = "Abyssos",     emoji = "\u{1F480}",         color = Color3.fromRGB(172, 72, 255) },
	Multiverse      = { key = "Manifold",   name = "Manifold",    emoji = "\u{1F9FF}",         color = Color3.fromRGB(255, 110, 235) },
	Nebula          = { key = "Nebulark",   name = "Nebulark",    emoji = "\u{1F30C}",         color = Color3.fromRGB(236, 126, 255) },
	Wormhole        = { key = "Elsewhere",  name = "Elsewhere",   emoji = "\u{1F573}\u{FE0F}", color = Color3.fromRGB(186, 130, 255) },
	QuantumRealm    = { key = "Quanton",    name = "Quanton",     emoji = "\u{1F4A0}",         color = Color3.fromRGB(86, 255, 240) },
	TimeRift        = { key = "Aeonis",     name = "Aeonis",      emoji = "\u{1F570}\u{FE0F}", color = Color3.fromRGB(255, 220, 96) },
	AntimatterZone  = { key = "Positron",   name = "Positron",    emoji = "\u{26A1}",          color = Color3.fromRGB(255, 172, 48) },
	DreamDimension  = { key = "Oneiros",    name = "Oneiros",     emoji = "\u{1F984}",         color = Color3.fromRGB(218, 140, 255) },
	MirrorUniverse  = { key = "Silverself", name = "Silver Self", emoji = "\u{1F48E}",         color = Color3.fromRGB(238, 248, 255) },
	VoidExpanse     = { key = "Nullarch",   name = "Nullarch",    emoji = "\u{1F7E3}",         color = Color3.fromRGB(190, 88, 255) },
	CelestialThrone = { key = "Empyrean",   name = "Empyrean",    emoji = "\u{1F31E}",         color = Color3.fromRGB(255, 230, 130) },
	Singularity     = { key = "Zeropoint",  name = "Zero Point",  emoji = "\u{2733}\u{FE0F}",  color = Color3.fromRGB(198, 240, 255) },
	AbsolutePlane   = { key = "Primordia",  name = "Primordia",   emoji = "\u{2600}\u{FE0F}",  color = Color3.fromRGB(255, 246, 196) },
}

-- Flattened lookup. Each species carries its zone and its rarity; the rarity is positional --
-- entry i in a zone's list is PetRarityOrder[i] -- so a zone list is always exactly five long.
GameConfig.Pets = {}
GameConfig.PetsByZone = {}
for _, zone in ipairs(GameConfig.Zones) do
	local pool = ZONE_PETS[zone.key]
	if pool then
		GameConfig.PetsByZone[zone.key] = {}
		for i, p in ipairs(pool) do
			local def = {
				key = p.key,
				name = p.name,
				emoji = p.emoji,
				color = p.color,
				zone = zone.key,
				rarity = GameConfig.PetRarityOrder[i] or "Common",
			}
			table.insert(GameConfig.Pets, def)
			table.insert(GameConfig.PetsByZone[zone.key], def)
		end
	end
end

-- ===== THE SPECIES NO EGG CAN REACH (11.6) =====
--
-- One per zone, dropped only by that zone's Apex, which stands on the highest shelf behind three
-- rebirths. **The unreachability is structural, not a rule somebody has to remember**: every egg
-- path bottoms out in `GetEggPool`, which reads `PetsByZone`, and these are inserted into
-- `GameConfig.Pets` and `ExclusivePetsByZone` and into neither of those. There is no flag to check
-- and no branch to forget -- the roll simply has nowhere to find them.
--
-- They still enter `GameConfig.Pets` on purpose: that is the table the Journal walks, so an
-- exclusive shows in the collection as a locked slot with a name. A goal you cannot see is not a
-- goal. It is also what `GetPetDef` scans, so a save holding one resolves normally everywhere else
-- in the game -- power, fusion, trading, the follower rig.
--
-- Rarity is Legendary rather than a sixth tier. A new rarity would mean a new weight, a new colour,
-- a new Journal section and a new beam rule, for a distinction the player already reads off "this
-- came out of an Apex". `exclusive = true` carries that meaning for the code that needs it.
GameConfig.ExclusivePetsByZone = {}
for _, zone in ipairs(GameConfig.Zones) do
	local p = EXCLUSIVE_PETS[zone.key]
	if p then
		local def = {
			key = p.key,
			name = p.name,
			emoji = p.emoji,
			color = p.color,
			zone = zone.key,
			rarity = "Legendary",
			exclusive = true,
		}
		table.insert(GameConfig.Pets, def)
		GameConfig.ExclusivePetsByZone[zone.key] = { def }
	end
end

-- ===== THE SPECIES ALMOST NOBODY WILL EVER SEE (12.12) =====
--
-- One per zone, and the ONLY way to get one is a Premium egg landing a 1-in-50,000 pre-roll that
-- happens before the ordinary weighted roll is even reached. They are not in `PetsByZone`, so no
-- pool contains them; they are not in `EggablePets`, so no fallback reaches them; and their rarity
-- carries `weight = 0`, so a pool that somehow did contain one still could not roll it. Three
-- independent locks, because the whole product here is scarcity and a leak is unrecoverable -- a
-- Secret handed out by accident cannot be taken back without touching saves.
--
-- WHY THEY ARE STILL IN `GameConfig.Pets`: that is what `GetPetDef` scans, and a save holding one
-- has to resolve everywhere else in the game -- the follower rig, fusion, the damage arithmetic,
-- trading, the inventory card. A species the code cannot name is a species that breaks the panel
-- it appears in.
--
-- Colours are the zone's palette pushed to its most saturated reading, and every key is unique
-- against the 100 in ZONE_PETS and the 20 in EXCLUSIVE_PETS -- `GetPetDef` is a linear scan over
-- one flat list, so a duplicate key would resolve to whichever was inserted first and the loser
-- would silently become invisible. Rigs cost nothing: `PetModel.Build` hashes the key to one of
-- five archetypes and paints it with `color`, so twenty new species are twenty rows, not assets.
local SECRET_PETS = {
	Forest          = { key = "Thornheart", name = "Thorn Heart", emoji = "\u{1F340}",         color = Color3.fromRGB(128, 255, 170) },
	Desert          = { key = "Mirageon",   name = "Mirageon",    emoji = "\u{1F3DC}\u{FE0F}", color = Color3.fromRGB(255, 222, 150) },
	Ocean           = { key = "Tidewraith", name = "Tide Wraith", emoji = "\u{1F30A}",         color = Color3.fromRGB(110, 255, 238) },
	Volcano         = { key = "Ashenmaw",   name = "Ashen Maw",   emoji = "\u{1F525}",         color = Color3.fromRGB(255, 150, 60) },
	Moon            = { key = "Eclipsyl",   name = "Eclipsyl",    emoji = "\u{1F311}",         color = Color3.fromRGB(200, 215, 255) },
	Mars            = { key = "Rustwake",   name = "Rust Wake",   emoji = "\u{1F6F0}\u{FE0F}", color = Color3.fromRGB(255, 130, 96) },
	Galaxy          = { key = "Starweaver", name = "Star Weaver", emoji = "\u{2728}",          color = Color3.fromRGB(210, 170, 255) },
	BlackHole       = { key = "Umbrion",    name = "Umbrion",     emoji = "\u{26AB}",          color = Color3.fromRGB(190, 110, 255) },
	Multiverse      = { key = "Paradoxa",   name = "Paradoxa",    emoji = "\u{1F3AD}",         color = Color3.fromRGB(255, 140, 240) },
	Nebula          = { key = "Auroran",    name = "Auroran",     emoji = "\u{1F386}",         color = Color3.fromRGB(255, 160, 255) },
	Wormhole        = { key = "Loopwalker", name = "Loop Walker", emoji = "\u{1F517}",         color = Color3.fromRGB(200, 150, 255) },
	QuantumRealm    = { key = "Superposit", name = "Superposit",  emoji = "\u{269B}\u{FE0F}",  color = Color3.fromRGB(120, 255, 246) },
	TimeRift        = { key = "Chronaught", name = "Chronaught",  emoji = "\u{231B}",          color = Color3.fromRGB(255, 230, 130) },
	AntimatterZone  = { key = "Antiphase",  name = "Antiphase",   emoji = "\u{2622}\u{FE0F}",  color = Color3.fromRGB(255, 190, 80) },
	DreamDimension  = { key = "Somnivore",  name = "Somnivore",   emoji = "\u{1F4AD}",         color = Color3.fromRGB(232, 170, 255) },
	MirrorUniverse  = { key = "Inversal",   name = "Inversal",    emoji = "\u{1FA9E}",         color = Color3.fromRGB(245, 252, 255) },
	VoidExpanse     = { key = "Voidsong",   name = "Void Song",   emoji = "\u{1F5A4}",         color = Color3.fromRGB(206, 120, 255) },
	CelestialThrone = { key = "Divinark",   name = "Divinark",    emoji = "\u{1F531}",         color = Color3.fromRGB(255, 240, 180) },
	Singularity     = { key = "Kernel",     name = "Kernel",      emoji = "\u{2B55}",          color = Color3.fromRGB(230, 240, 255) },
	AbsolutePlane   = { key = "Genesis",    name = "Genesis",     emoji = "\u{1F31F}",         color = Color3.fromRGB(255, 252, 220) },
}

GameConfig.SecretPetsByZone = {}
for _, zone in ipairs(GameConfig.Zones) do
	local p = SECRET_PETS[zone.key]
	if p then
		local def = {
			key = p.key,
			name = p.name,
			emoji = p.emoji,
			color = p.color,
			zone = zone.key,
			rarity = "Secret",
			secret = true,
		}
		table.insert(GameConfig.Pets, def)
		GameConfig.SecretPetsByZone[zone.key] = def
	end
end

-- ===== THE PRE-ROLL =====
--
-- Priced as one number rather than as a weight, because it is not competing with the other species
-- for share -- it happens first, and the ordinary roll runs only when it does not. That is also why
-- luck is capped here: the shared luck total reaches ~400 in the worst honest case (2.12's
-- measurement), and an uncapped `1 + luck/1000` on a future luck ceiling would quietly turn a
-- 1-in-50,000 into a 1-in-a-few-thousand. At the cap this is 1 in 35,714 -- luck is worth having and
-- is not the feature.
GameConfig.Secret = {
	chance = 1 / 50000,
	luckCap = 400,
	luckDiv = 1000,
}

function GameConfig.GetSecretChance(luckPercent)
	local s = GameConfig.Secret
	return s.chance * (1 + math.min(luckPercent or 0, s.luckCap) / s.luckDiv)
end

-- PREMIUM ONLY. The tier is what the whole thing hangs off -- the expensive egg has to be worth its
-- 9x over the Basic one for a reason the player can name, and "it is the only egg that can do this"
-- is a better reason than a third of a percent of Legendary. One predicate, read by the roll and by
-- both odds boards, so the advertisement and the behaviour cannot drift.
function GameConfig.CanEggHatchSecret(egg)
	return egg ~= nil and egg.tierSuffix == "Premium" and GameConfig.SecretPetsByZone[egg.zone] ~= nil
end

function GameConfig.GetSecretPetForEgg(egg)
	return egg and GameConfig.SecretPetsByZone[egg.zone] or nil
end

-- ===== AND THE FALLBACK POOL HAD TO STOP BEING `GameConfig.Pets` =====
--
-- `RollFromPool` and `GetEggPool` both fall back to the flat list when they are handed a malformed
-- or empty pool -- an egg with no `zone`, a zone with no species. That fallback is now the ONE way
-- an exclusive could still come out of an egg, so it points at this list instead: everything that is
-- not exclusive, built once. The hole is closed at the bottom of the funnel rather than at each of
-- the three call sites above it, which is the only version of this that a future egg type cannot
-- reopen by accident.
--
-- `not def.secret` joined it in 12.12 for exactly the same reason and in the same commit as the
-- species themselves: a Secret reachable through the malformed-egg fallback would be a Secret with
-- a 1-in-120 chance instead of a 1-in-50,000 one, which is the failure this list exists to prevent.
GameConfig.EggablePets = {}
for _, def in ipairs(GameConfig.Pets) do
	if not def.exclusive and not def.secret then
		table.insert(GameConfig.EggablePets, def)
	end
end

-- The pool a terrace kill rolls against: the zone's ordinary five on layer 1, its one exclusive on
-- layer 2. Returns nil when the layer pays no pet at all, so the caller's `if pool` is the whole
-- test -- there is no second question about whether this creature drops.
function GameConfig.GetTerracePetPool(zoneKey, raised)
	local layer = GameConfig.GetRaisedLayer(raised)
	if not layer then return nil end
	if layer.exclusive then
		return GameConfig.ExclusivePetsByZone[zoneKey]
	end
	return GameConfig.PetsByZone[zoneKey]
end

function GameConfig.GetPetDef(key)
	for _, p in ipairs(GameConfig.Pets) do
		if p.key == key then return p end
	end
	return nil
end

-- ===== WHAT A PET IS WORTH: DAMAGE AND LUCK, AND NOTHING ELSE =====
--
-- `incomeMult` and `dnaMult` are GONE from this table, and their removal is the single largest
-- economy fix in this phase. They were 1.4 and 2 here, scaled by tier x rarity and then stacked
-- MULTIPLICATIVELY across every equipped slot in PetService.GetEquippedBonus -- so one Legendary
-- Normal pet was worth incomeMult 4.2 x dnaMult 9.0 = **x37.8 on every kill and every click**.
-- That is the reported "DNA was ~60, then I got my first pet and it was ~1,000", and it is the
-- same defect this repo has now corrected four times: a quantity that multiplies once per item,
-- over a collection that only grows, is not a bonus, it is an exponential in the number of slots
-- (see GetMutationIncomeMult, the idle-income cap, and the damage half of this same function in
-- 9.1). The economy is now what it was tuned to be -- 14 to 20 kills per stage -- because that
-- curve was authored against a player with no pets at all.
--
-- A pet pays DAMAGE, and the player earns more DNA because creatures die faster. That is the
-- whole design: pets are a combat stat, not an income stat. `luckAdd` stays because luck is
-- additive everywhere in this game and cannot compound.
--
-- `luckAdd` 5 -> 12, AND it is now scaled by the damage SHARE rather than by the raw tier x rarity
-- product. That reads like a raise and is a large cut, and the live test is what found it.
--
-- With incomeMult and dnaMult gone, luck was the last surviving pet -> DNA channel and it was not a
-- small one: luck feeds crit chance (`clamp(5 + luck * 0.5, 0, 75)` for a x5 payout), one Legendary
-- paid 40 luck points, and five paid 180 -- which pins crit at its 75% cap and multiplies the mean
-- click by 3.3x. Measured: with the multipliers already removed, the mean click still ran 3.38 ->
-- 5.15 -> 10.40 DNA across zero, one and five pets. That is the reported bug arriving by a third
-- route, quieter and bounded, but the same sentence: "I got a pet and my DNA jumped."
--
-- One pet was also worth 40 points against the 249 R$ Lucky pass's 50, so a free first hatch nearly
-- matched a premium purchase and five of them beat it four times over -- out of band whatever it
-- did to DNA. On the share scale a Legendary Normal is 9.6 points and a full first-egg team sits
-- under one Lucky pass, while a maxed nine-slot endgame team reaches ~360, inside the worst honest
-- case Phase 2.12 already swept and found bounded.
GameConfig.PetBaseBonus = { luckAdd = 12, incomeMult = 1, dnaMult = 1 }

-- ===== EGG TIER x RARITY x PROGRESSION =====
--
-- A pet's damage contribution is a SHARE OF THE PLAYER'S OWN BARE DAMAGE, summed across the
-- equipped slots. Expressing it as a share rather than as an absolute number is what makes the
-- three axes composable and what keeps the whole team bounded however many slots open up.
--
-- Share per pet = PetRarityShare(rarity) x PetTierShare(tier) x zone factor.
--
-- PetRarityShare reuses the authored `bonusMult` ladder divided by ten, so rarity ordering has
-- exactly one source of truth and a future rarity row needs no second edit here: Common 0.10 up
-- to Legendary 0.80.
GameConfig.PetRarityShareScale = 0.1

-- ...and the tier ladder is 1 / 1.6 / 2.6 / 4.2 rather than the old 1 / 2 / 4 / 8. The old
-- doubling was authored for a MULTIPLICATIVE stat, where a x8 top tier is one factor among
-- several; against a SUM it would put nine max-tier Legendaries at x58 the player's own damage.
-- The shape here is the rarity ladder's own, which keeps a fuse feeling like a real step (+60%
-- of that pet's share) without the top of the ladder swallowing the game.
GameConfig.PetTierShare = { Normal = 1, Golden = 1.6, Rainbow = 2.6, Celestial = 4.2 }

-- ===== ENCHANTS: THE FOURTH FACTOR ON THE SHARE, AND THE FIRST REPEATABLE DIAMOND SINK (13.1) =====
--
-- Share per pet is PetRarityShare x PetTierShare x zone factor x ENCHANT, and this is the only one
-- of the four a player can buy repeatedly. It exists because the Diamond economy has no terminal
-- sink: DiamondUpgrades is three tiles (one capped at level 3) and StageMastery is twenty one-shot
-- purchases totalling ~700 diamonds, so a player who has bought both has nothing left to want while
-- every kill keeps paying. An enchant is permanent, per-pet and repeatable, which is the shape a
-- sink has to have to absorb an income that never stops.
--
-- ===== SIZED AGAINST A NINE-SLOT TEAM, NOT AGAINST ONE PET =====
--
-- The shares SUM (see GetEquippedBonus), so a multiplier here is felt nine times over at the top of
-- the game. A maxed endgame team of nine Celestial Legendaries sits at 9 x 0.8 x 4.2 = 30.2 shares,
-- i.e. x31.2 the player's own damage; putting the top rung on all nine takes that to x50.9. That is
-- the ceiling this ladder is chosen against, and it is why the top rung is x1.65 rather than the
-- x3 the name "Eternal" invites. The same arithmetic is what killed the old mutation ladder in 12.1
-- -- a multiplier that stacks with nothing to stop it is not a reward, it is an inflation faucet.
--
-- ===== WEIGHTS SUM TO 100 ON PURPOSE =====
--
-- The panel prints them as percentages and the roll walks them as weights, so the two can never
-- disagree about what the game is actually doing. A future rung is a row here plus nothing else --
-- as long as the column still sums to 100, which GameConfig.AssertEnchantWeights checks at load.
--
-- ===== LUCK DOES NOT ENTER THIS ROLL, AND THAT IS A DESIGN DECISION =====
--
-- Every other roll in this game is loot and every one of them reads luck. This one is a permanent
-- stat multiplier bought with a currency no pass produces, so paying luck into it would let a
-- 249 R$ purchase buy a permanent team multiplier more cheaply than a player who farmed for it --
-- the pay-to-win line the pass table has stayed behind since Phase 2. The lever on this ladder is
-- the PRICE, which is the same lever the Splicer uses and the one a player can see.
GameConfig.Enchants = {
	{ key = "keen",      name = "Keen",      mult = 1.06, weight = 44,  color = Color3.fromRGB(150, 200, 240) },
	{ key = "fierce",    name = "Fierce",    mult = 1.14, weight = 26,  color = Color3.fromRGB(120, 210, 140) },
	{ key = "savage",    name = "Savage",    mult = 1.24, weight = 15,  color = Color3.fromRGB(240, 176, 84)  },
	{ key = "radiant",   name = "Radiant",   mult = 1.36, weight = 9,   color = Color3.fromRGB(246, 122, 96)  },
	{ key = "prismatic", name = "Prismatic", mult = 1.48, weight = 4.5, color = Color3.fromRGB(196, 118, 246) },
	-- `announce` is this ladder's `IsBeaconRarity`: the table that knows which rung is rare is the
	-- table AnnounceService asks, so a new top rung is a row here and no edit there.
	{ key = "eternal",   name = "Eternal",   mult = 1.65, weight = 1.5, color = Color3.fromRGB(255, 214, 92), announce = true },
}

-- Keyed view, built once. Every reader goes through GetEnchantDef so a bad key from a save or from
-- a client message resolves to nil rather than to an error.
local ENCHANT_BY_KEY = {}
for i, e in ipairs(GameConfig.Enchants) do
	e.rank = i
	ENCHANT_BY_KEY[e.key] = e
end

function GameConfig.GetEnchantDef(key)
	return key and ENCHANT_BY_KEY[key] or nil
end

-- The one number the damage chain reads. Takes the KEY (not the def) and answers 1 for nil, for an
-- unknown key and for a pet minted before enchants existed -- which is every pet in every save on
-- the day this ships, and is the whole reason no Load repair is needed (the 6.3 rule).
function GameConfig.GetEnchantMult(key)
	local def = GameConfig.GetEnchantDef(key)
	return def and def.mult or 1
end

-- Strictly better, never "at least as good": the caller keeps what it has on a tie, so a re-roll
-- that lands on the same rung cannot churn the save or claim an upgrade that is not one.
function GameConfig.IsEnchantBetter(candidate, current)
	return GameConfig.GetEnchantMult(candidate) > GameConfig.GetEnchantMult(current)
end

function GameConfig.RollEnchant()
	local total = 0
	for _, e in ipairs(GameConfig.Enchants) do total += e.weight end
	local roll = math.random() * total
	for _, e in ipairs(GameConfig.Enchants) do
		roll -= e.weight
		if roll <= 0 then return e.key end
	end
	-- float dust only; the loop above consumes the whole range
	return GameConfig.Enchants[#GameConfig.Enchants].key
end

-- ===== THE PRICE, AND WHY IT IS FLAT IN DIAMONDS =====
--
-- Priced by TIER and by nothing else. Tier is exactly what makes an enchant worth more -- the share
-- is a product, so the same rung on a Celestial is worth 4.2x what it is worth on a Normal -- and a
-- price that tracked the player's stage instead would make the sink cheapest for the players who
-- have the most diamonds. Diamonds are deliberately raw (see the note over the Diamond products):
-- "45 Diamonds" is true at every stage of the game, which is what lets the button quote a number a
-- player can plan against.
--
-- Reaching the top rung on one Celestial costs roughly 46 rolls at 50/50 odds, i.e. ~3,200 diamonds
-- against ~700 for the entire Stage Mastery set. That is deliberate: this is the sink that is meant
-- to still be there after everything else is bought.
GameConfig.EnchantCost = { Normal = 20, Golden = 30, Rainbow = 45, Celestial = 70 }

function GameConfig.GetEnchantCost(pet)
	return GameConfig.EnchantCost[pet and pet.tier or "Normal"] or GameConfig.EnchantCost.Normal
end

-- Same defence as AssertTierCoverage: a weights column that quietly stops summing to 100 turns
-- every printed percentage into a lie, and nothing else in the game would notice.
function GameConfig.AssertEnchantWeights()
	local total = 0
	for _, e in ipairs(GameConfig.Enchants) do total += e.weight end
	if math.abs(total - 100) > 1e-6 then
		warn(("[GameConfig] Enchant weights sum to %.4f, not 100 -- the odds table is now a lie"):format(total))
	end
	return total
end

-- THE PROGRESSION AXIS, and the reason an early Legendary is no longer a late Legendary.
--
-- GetPetBonus used to take only (tier, rarity), so a Forest Basic-egg Legendary and an Absolute
-- Plane Premium-egg Legendary were byte-identical -- both +240% damage, at a 1.8e13x difference in
-- egg price. The egg tier decided only WHICH rarities could roll, never what a rarity was worth.
--
-- The zone factor is the ratio of what the pet's own zone hits for to what the PLAYER hits for
-- now, so a pet is at full strength in the zone it came from and fades as the player climbs past
-- it. It needs NO new save field and NO migration: every species already carries `zone` (see the
-- ZONE_PETS flatten above), so the zone of any pet ever hatched is recoverable from its key.
--
-- FLOORED at 0.25 rather than allowed to reach zero. An old pet that decayed to nothing would
-- make a veteran's collection worthless overnight, which is the kind of change that reads as a
-- broken save rather than as a rebalance -- the rule this repo already followed when the rebirth
-- ladder grandfathered eight spent rebirths.
--
-- ===== BUT THE FLOOR IS APPROACHED, NEVER CLAMPED TO, AND THE TEST IS WHY =====
--
-- The first cut of this was `math.clamp(ratio, 0.25, 1)`, and the balance sweep found it wrong in
-- exactly the place the whole rebalance exists to fix. Damage is geometric, so the ratio collapses
-- fast: at rank 96 a zone-1 pet scores 0.0009 and a zone-10 pet 0.026 -- BOTH below the floor, so
-- both clamped to 0.25 and an early-egg Legendary was worth precisely as much as a mid-game one.
-- The brief's requirement is Early < Mid < Late, and a clamp satisfies it only until the floor is
-- reached, after which it silently reintroduces the bug at the end of the game.
--
-- Compressed instead: floor + (1 - floor) * sqrt(ratio). Monotonic over the whole domain, so the
-- ordering can never flatten however far apart the two zones are, while the square root keeps the
-- decay gentle enough that walking into the next zone does not visibly weaken the team the player
-- just built. At rank 96 that reads 0.27 / 0.37 / 1.00 for a zone-1 / zone-10 / zone-20 Legendary.
GameConfig.PetZoneFloor = 0.25

GameConfig.PetTiers = { "Normal", "Golden", "Rainbow", "Celestial" }
-- Kept for PetModel, which sizes the rendered rig off it. Deliberately NOT used by any stat any
-- more -- PetTierShare above is the stat ladder. A bigger Celestial is a visual promise, and the
-- two numbers are allowed to disagree because they answer different questions.
GameConfig.PetTierMultiplier = { Normal = 1, Golden = 2, Rainbow = 4, Celestial = 8 }
GameConfig.PetTierColor = {
	Normal = Color3.fromRGB(220, 220, 220),
	Golden = Color3.fromRGB(255, 215, 60),
	Rainbow = Color3.fromRGB(255, 120, 220),
	Celestial = Color3.fromRGB(120, 220, 255),
}
-- ===== THREE COPIES, NOT FOUR (11.7) =====
--
-- The whole ladder is this number raised to a power: a Rainbow costs `n^2` Normals of one species
-- and a Celestial `n^3`. At four that is 16 and **64**, against an inventory ceiling of 100 that also
-- has to hold a collection -- so Celestial was not really reachable, it was theoretically reachable.
-- At three it is 9 and **27**, which is what the MaxOwnedPets note above was already written against
-- when 11.10 raised the cap to 100: that comment has said "27 copies at the 3-per-fuse requirement"
-- since before this constant moved. This is the line catching up with a decision already made.
--
-- Everything reads it: PetService's refusal and its loop, the fusion panel's counter and button, and
-- the world sign at the fusion pad. That last one is baked at BUILD time, so ZoneBuilder's
-- BUILD_VERSION has to move with this or the sign in the world keeps advertising four.
GameConfig.FuseRequirement = 3
GameConfig.MaxEquippedPets = 3

-- ===== HOW MANY PETS A SAVE MAY HOLD =====
--
-- 100. It was 600 first — a figure set to protect the DataStore (a save past 4 MB stops saving
-- forever with nothing but a warning) rather than to shape play, and at 600 it did neither: a live
-- save reached **207 pets**, which is not an inventory, it is a spreadsheet nobody scrolls. It then
-- went to 30, which shaped play too hard: fusion needs identical copies, so a ceiling of 30 put
-- Celestial (27 copies at the 3-per-fuse requirement) out of reach of an inventory that also has to
-- hold anything a player wants to keep.
--
-- 100 is the number where both are true: far under the DataStore wall, and roomy enough that the
-- fusion ladder can actually be climbed while keeping a collection beside it.
--
-- RAISING THIS IS SAFE FOR EXISTING SAVES and lowering it is not. `PlayerDataService`'s trim only
-- runs on `#data.Pets > MaxOwnedPets`, which after a raise is true for nobody; the `PetsTrimmedAt`
-- stamp left at 30 on already-trimmed saves simply never matches again and goes inert. No save is
-- touched a second time.
--
-- IT LIVES HERE so `PetService`, `TradeService` and `MainUI` all read one number. Both services
-- kept private copies before, deliberately, because "these two files must not require each other" —
-- but they both already require GameConfig, so the shared dependency was always available and the
-- duplication only bought a way for the two ceilings to drift apart.
GameConfig.MaxOwnedPets = 100

-- Each zone's Pet Shop sells 3 eggs -- Basic/Better/Premium -- built by tiering that
-- zone's base cost/luckBonus (same numbers the old single-egg-per-zone design used).
local ZONE_EGG_BASE = {
	{ zone = "Forest",          baseCost = 500,                baseLuck = 0 },
	{ zone = "Desert",          baseCost = 2500,               baseLuck = 6 },
	{ zone = "Ocean",           baseCost = 12000,              baseLuck = 12 },
	{ zone = "Volcano",         baseCost = 60000,              baseLuck = 18 },
	{ zone = "Moon",            baseCost = 300000,             baseLuck = 24 },
	{ zone = "Mars",            baseCost = 1500000,            baseLuck = 30 },
	{ zone = "Galaxy",          baseCost = 8000000,            baseLuck = 40 },
	{ zone = "BlackHole",       baseCost = 40000000,           baseLuck = 55 },
	{ zone = "Multiverse",      baseCost = 200000000,          baseLuck = 75 },
	{ zone = "Nebula",          baseCost = 1000000000,         baseLuck = 90 },
	{ zone = "Wormhole",        baseCost = 5000000000,         baseLuck = 105 },
	{ zone = "QuantumRealm",    baseCost = 25000000000,        baseLuck = 120 },
	{ zone = "TimeRift",        baseCost = 125000000000,       baseLuck = 135 },
	{ zone = "AntimatterZone",  baseCost = 600000000000,       baseLuck = 150 },
	{ zone = "DreamDimension",  baseCost = 3000000000000,      baseLuck = 165 },
	{ zone = "MirrorUniverse",  baseCost = 15000000000000,     baseLuck = 180 },
	{ zone = "VoidExpanse",     baseCost = 75000000000000,     baseLuck = 195 },
	{ zone = "CelestialThrone", baseCost = 375000000000000,    baseLuck = 210 },
	{ zone = "Singularity",     baseCost = 1800000000000000,   baseLuck = 225 },
	{ zone = "AbsolutePlane",   baseCost = 9000000000000000,   baseLuck = 250 },
}

-- Two separate levers, and both matter:
--   rarityMin/rarityMax slice the zone's five species, so the three eggs on one podium hold
--   three *different* lists -- the cheap egg cannot hand you the Legendary at all, and the
--   Premium one has stopped wasting rolls on the Common.
--   rarityBias then shifts the odds inside whatever slice is left.
-- BIASES HALVED 2026-08-11, with the Legendary weight 8 -> 4 (see the Rarities table). Between them
-- the Premium egg went from ~3.8-4.4% Legendary to ~1.6-2.1% and the Better egg from ~1.0-1.4% to
-- ~0.4-0.7%. Bias was doing most of the work: at the old 2.8 the Premium egg multiplied a
-- Legendary's weight by nearly seven before luck was counted at all.
--
-- The ORDER of the two levers matters if you re-tune. `rarityBias` is scaled by `rarityFactor`, so
-- it lifts the rarest species hardest and barely touches the commonest; the weight is flat. Reach
-- for the weight to move the floor and for the bias to move how much the expensive egg is worth
-- over the cheap one. Basic stays at 0 and `rarityMax = 4`, which is what makes a Legendary
-- structurally impossible out of it -- that is a feature, not a number to tune.
local EGG_TIERS = {
	{ suffix = "Basic",   emoji = "🥚", costMult = 1,   luckAdd = 0,  rarityBias = 0,    rarityMin = 1, rarityMax = 4 },
	{ suffix = "Better",  emoji = "🐣", costMult = 3.5, luckAdd = 10, rarityBias = 0.55, rarityMin = 1, rarityMax = 5 },
	{ suffix = "Premium", emoji = "🌟", costMult = 9,   luckAdd = 22, rarityBias = 1.4,  rarityMin = 2, rarityMax = 5 },
}

GameConfig.Eggs = {}
for _, zb in ipairs(ZONE_EGG_BASE) do
	for _, tier in ipairs(EGG_TIERS) do
		table.insert(GameConfig.Eggs, {
			key = zb.zone .. tier.suffix .. "Egg",
			name = zb.zone .. " " .. tier.suffix .. " Egg",
			emoji = tier.emoji,
			cost = math.floor(zb.baseCost * tier.costMult),
			zone = zb.zone,
			tierSuffix = tier.suffix,
			luckBonus = zb.baseLuck + tier.luckAdd,
			rarityBias = tier.rarityBias,
			rarityMin = tier.rarityMin,
			rarityMax = tier.rarityMax,
		})
	end
end

function GameConfig.GetEggsForZone(zoneKey)
	local list = {}
	for _, egg in ipairs(GameConfig.Eggs) do
		if egg.zone == zoneKey then table.insert(list, egg) end
	end
	return list
end

-- HOW MUCH OF ITS SHARE THIS PET STILL DELIVERS, given where the player now stands.
--
-- 1.0 in the pet's own zone and falling as the player climbs past it, floored at PetZoneFloor.
-- `data` is optional: with no save to compare against there is no progression axis to apply, so it
-- returns 1 and the pet is quoted at full strength -- which is the right answer for the Journal and
-- for any preview that is describing a species rather than a player's loadout.
--
-- Clamped at the TOP as well as the bottom. A pet from a zone ahead of the player cannot normally
-- exist (HandleBuyEgg refuses an egg from a locked zone), but a trade, an old save or a future
-- reward could hand one over, and a factor above 1 would make it pay more than its own zone's
-- reference damage for as long as the player stayed behind it.
function GameConfig.GetPetZoneFactor(petKey, data)
	if not data then return 1 end
	local def = GameConfig.GetPetDef(petKey)
	if not def or not def.zone then return 1 end
	local petRef = GameConfig.GetZoneReferenceDamage(GameConfig.GetZoneIndex(def.zone))
	local playerDamage = GameConfig.GetRankDamage(GameConfig.GetProgressRank(data))
	if playerDamage <= 0 then return 1 end
	-- clamped to [0,1] FIRST -- a pet from a zone ahead of the player would otherwise push the root
	-- above 1 and pay more than its own zone's reference damage
	local ratio = math.clamp(petRef / playerDamage, 0, 1)
	local floor = GameConfig.PetZoneFloor
	return floor + (1 - floor) * math.sqrt(ratio)
end

-- `rarity` is optional so old call sites keep working; omitted means Common. `petKey` and `data`
-- are both optional and are the progression axis -- pass them and the answer is what this pet is
-- worth to THIS player right now; omit them and it is what the species is worth at its own zone.
-- `enchant` is the fifth and last axis and it is a KEY, not a def -- every call site already holds
-- the pet entry, so passing `pet.enchant` is a one-token change and no caller has to learn what an
-- enchant is. Omitted, nil, or a key this build does not know all resolve to x1.
function GameConfig.GetPetBonus(tier, rarity, petKey, data, enchant)
	local rarityShare = GameConfig.GetRarity(rarity).bonusMult * GameConfig.PetRarityShareScale
	local tierShare = GameConfig.PetTierShare[tier] or 1
	local zoneFactor = petKey and GameConfig.GetPetZoneFactor(petKey, data) or 1
	local share = rarityShare * tierShare * zoneFactor * GameConfig.GetEnchantMult(enchant)
	local base = GameConfig.PetBaseBonus
	return {
		-- Both hard 1. Kept as fields rather than deleted so every existing call site keeps
		-- reading a number instead of a nil -- and so that the day someone reaches for a pet
		-- income bonus again, the one-line answer is here with the reasoning above it.
		incomeMult = base.incomeMult,
		dnaMult = base.dnaMult,
		-- Luck rides the SAME share as damage -- see the note over PetBaseBonus for why it had to
		-- come off the raw tier x rarity product. One number now moves a pet's whole contribution,
		-- so a rebalance of the share ladder can never leave luck behind pointing somewhere else.
		luckAdd = base.luckAdd * share,
		damageMult = 1 + share,
		-- exposed for the UI: the row prints the share, and the fusion/catalyst preview compares
		-- two of them without having to re-derive the arithmetic
		share = share,
	}
end

-- ===== WHAT THE EQUIPPED TEAM IS WORTH =====
--
-- LIVED IN PetService UNTIL 2026-08-11, and it moved here because it is pure: it reads `data` and
-- this module and touches nothing else. Sitting on the server meant the CLIENT could not compute
-- luck, which is what the egg panel needs to show honest odds -- and a UI that recomputes a formula
-- by hand is exactly how `rollAndInsert` ended up advertising luck it was not using.
--
-- `PetService.GetEquippedBonus` is kept as an alias, so every existing call site is unchanged.
function GameConfig.GetEquippedBonus(data)
	-- `damageAdd` accumulates each pet's share ABOVE 1 and becomes the multiplier at the end, so an
	-- empty team returns exactly 1 and nothing downstream has to special-case "no pets".
	local incomeMult, luckAdd, dnaMult, damageAdd = 1, 0, 1, 0
	if not data or not data.EquippedPetIds or not data.Pets then
		return { incomeMult = incomeMult, luckAdd = luckAdd, dnaMult = dnaMult, damageMult = 1 }
	end
	local equippedLookup = {}
	for _, id in ipairs(data.EquippedPetIds) do
		equippedLookup[id] = true
	end
	for _, pet in ipairs(data.Pets) do
		if equippedLookup[pet.id] then
			-- rarity is a property of the species, not of the save, so it is looked up rather
			-- than stored -- pets hatched before rarities existed still resolve correctly
			local def = GameConfig.GetPetDef(pet.key)
			-- `pet.key` and `data` are the progression axis: what this pet is worth to THIS player
			-- at the rung they are standing on, not what its species is worth in the abstract.
			local bonus = GameConfig.GetPetBonus(pet.tier, def and def.rarity, pet.key, data, pet.enchant)
			-- Both of these are hard 1 now (see PetBaseBonus) so these two lines are no-ops, and
			-- they are kept as lines rather than deleted because the shape of this loop is the thing
			-- that was wrong: `*=` over a growing collection is the bug, and leaving the operators
			-- visible beside the summed damage below is the clearest statement of the rule.
			incomeMult *= bonus.incomeMult
			dnaMult *= bonus.dnaMult
			luckAdd += bonus.luckAdd
			damageAdd += (bonus.damageMult - 1)
		end
	end
	return { incomeMult = incomeMult, luckAdd = luckAdd, dnaMult = dnaMult, damageMult = 1 + damageAdd }
end

-- ===== THE TWO LUCK TOTALS, AND WHY THERE ARE TWO =====
--
-- Every luck source is additive percentage points, and this is the only place they are summed.
-- It used to live in DNAService, which the client cannot reach and PetService could not require
-- (DNAService requires PetService) -- so the egg roll grew its OWN copy with two of these six terms
-- and a Luck Potion did nothing at all to what came out of an egg. Both now call this.
--
-- Luck starts at zero, so every source ADDS points rather than multiplying: a multiplier would pay
-- a first-time buyer exactly nothing.
--
-- SPLIT ON 2026-08-12 (11.5). The shop's `Upgrades.Luck` used to enter this sum, which made one
-- purchase quietly raise FIVE unrelated things at once: crit DNA, the mutation roll, the egg roll,
-- the mystery potion and the Robux wheel. That is unreadable at the point of sale -- the card said
-- "Critical DNA & rare mutations" and the biggest thing it actually moved was hatching -- and it is
-- also the reason the upgrade could never be made strong: any number big enough to be felt on an
-- egg was a crit-chance clamp on the DNA click.
--
-- So the upgrade LEAVES this sum and becomes a pet-luck-only stat, at +5 a level instead of +2.
-- Everything else -- pets, MegaLuck, potions, passes, events -- stays shared, because those are
-- sold as "luck" flat and players expect them everywhere. Read `GetPetLuckPercent` for anything
-- that opens an egg and this one for everything else.
function GameConfig.GetLuckPercent(data)
	if not data then return 0 end
	local megaLevel = data.DiamondUpgrades and data.DiamondUpgrades.MegaLuck or 0
	local megaAdd = megaLevel * GameConfig.DiamondUpgrades.MegaLuck.effectAdd
	return GameConfig.GetEquippedBonus(data).luckAdd
		+ megaAdd
		+ GameConfig.GetPotionLuckAdd(data)
		+ GameConfig.GetPassAdd(data, "luckAdd")
		+ GameConfig.GetEventAdd("luckAdd")
end

-- Percentage points the shop's Luck upgrade is worth PER LEVEL, and only to an egg. Raised from
-- the old shared +2 when the split above took it out of everything else -- the same spend has to
-- stay worth making, and it now buys one clearly-named thing instead of five vague ones.
GameConfig.PetLuckPerUpgradeLevel = 5

-- The luck an EGG rolls against: the shared total plus the shop upgrade. Two callers only, and
-- they are the two halves of one promise -- `PetService.rollAndInsert` (what you get) and the egg
-- panel's odds table (what you were told you would get). They must never diverge, which is why
-- neither computes this itself.
function GameConfig.GetPetLuckPercent(data)
	if not data then return 0 end
	local upgrades = (data.Upgrades and data.Upgrades.Luck or 0) * GameConfig.PetLuckPerUpgradeLevel
	return GameConfig.GetLuckPercent(data) + upgrades
end

-- The highest tier a paid Rainbow Catalyst may PRODUCE. Fusing is unaffected and still reaches
-- Celestial for free -- this caps the bought shortcut, not the ladder. One constant, read by both
-- the server that validates the spend and the panel that decides which pets to offer, so the two
-- can never disagree about what is buyable. See the product comment in RobuxProducts for why the
-- cap exists at all: equipped bonuses multiply across up to nine slots.
GameConfig.CatalystMaxTier = "Rainbow"

-- The next tier a catalyst is allowed to take this pet to, or nil if there is none -- either because
-- the pet is already at the top of the whole ladder, or because the step would cross the cap above.
function GameConfig.GetCatalystNextTier(tier)
	local nextTier = GameConfig.GetNextTier(tier)
	if not nextTier then return nil end
	local capIndex, nextIndex
	for i, t in ipairs(GameConfig.PetTiers) do
		if t == GameConfig.CatalystMaxTier then capIndex = i end
		if t == nextTier then nextIndex = i end
	end
	if not (capIndex and nextIndex) or nextIndex > capIndex then return nil end
	return nextTier
end

function GameConfig.GetNextTier(tier)
	for i, t in ipairs(GameConfig.PetTiers) do
		if t == tier then return GameConfig.PetTiers[i + 1] end
	end
	return nil
end

-- ===== HOW STRONG IS THIS PET =====
-- The pet's damage share -- i.e. exactly what GetPetBonus hands to the damage chain -- so the row
-- that prints the power chip, the Equip Best that picks the top three and the fusion preview that
-- shows what the next tier is worth can never disagree with what the pet actually does. It lives
-- here, once; three private copies of it would drift the first time a ladder changed.
--
-- `data` IS LOAD-BEARING FOR EQUIP BEST and is why it was threaded through. Ranking without it
-- ignores the zone axis, so a collection would be sorted as though every pet were still standing
-- in the zone it hatched in -- and Equip Best would keep putting a Forest Legendary in a slot that
-- a zone-matched Epic now beats four times over. Optional, because a species preview has no player
-- to rank against; omitted, every pet is quoted at its own zone's full strength.
-- Takes a SAVED pet ({ key, tier }), not a species def: tier is per-instance.
function GameConfig.GetPetPower(pet, data)
	if not pet then return 0 end
	local def = GameConfig.GetPetDef(pet.key)
	return GameConfig.GetPetBonus(pet.tier, def and def.rarity, pet.key, data, pet.enchant).share
end

-- Strongest first. Ties are broken by key, then tier, then id -- not left to table.sort -- so a
-- list of duplicates keeps the same order every refresh instead of shuffling under the cursor
-- while the player is reaching for a button.
function GameConfig.SortedPetsByPower(pets, data)
	local list = table.create(#pets)
	for _, p in ipairs(pets) do
		table.insert(list, p)
	end
	-- Scored ONCE per pet before the sort rather than inside the comparator. GetPetPower walks the
	-- species table and the rank ladder, and table.sort calls a comparator O(n log n) times -- at 30
	-- pets that is ~150 calls against 30, and the trim in PlayerDataService runs it over a save that
	-- can still hold 600.
	local score = {}
	for _, p in ipairs(list) do
		score[p] = GameConfig.GetPetPower(p, data)
	end
	table.sort(list, function(a, b)
		local pa, pb = score[a], score[b]
		if pa ~= pb then return pa > pb end
		if a.key ~= b.key then return a.key < b.key end
		if a.tier ~= b.tier then return a.tier < b.tier end
		return tostring(a.id) < tostring(b.id)
	end)
	return list
end

-- The species one specific egg can hatch: its zone's five, sliced by the tier's rarity window.
-- Zone lists are positional (entry i is PetRarityOrder[i]), so the window is a plain index range.
function GameConfig.GetEggPool(egg)
	local zonePool = egg and GameConfig.PetsByZone[egg.zone]
	-- An egg with no zone rolls against every species in the game, which since 11.6 would have
	-- included the Apex exclusives -- so it falls back to the eggable list. `PetsByZone` itself never
	-- holds one, so the slice below is already safe; this is the malformed-egg path only.
	if not zonePool or #zonePool == 0 then return GameConfig.EggablePets end
	local out = {}
	for i, p in ipairs(zonePool) do
		if i >= (egg.rarityMin or 1) and i <= (egg.rarityMax or #zonePool) then
			table.insert(out, p)
		end
	end
	return #out > 0 and out or zonePool
end

-- Shared by the roll and by the odds the shop advertises, so the two can never disagree.
-- `luckPercent` and `rarityBias` (from the egg tier) both push toward the rarer end, scaled by
-- how rare a species already is -- luck lifts a Legendary far more than it lifts a Common.
local function poolWeights(pool, luckPercent, rarityBias)
	local maxWeight = 0
	for _, p in ipairs(pool) do
		maxWeight = math.max(maxWeight, GameConfig.GetRarity(p.rarity).weight)
	end

	local weights, total = {}, 0
	for i, p in ipairs(pool) do
		local base = GameConfig.GetRarity(p.rarity).weight
		local rarityFactor = 1 - (base / maxWeight) -- 0 for the commonest, ->1 for the rarest
		local boost = 1 + ((luckPercent or 0) / 100 + (rarityBias or 0)) * rarityFactor * 2
		weights[i] = base * boost
		total += weights[i]
	end
	return weights, total
end

function GameConfig.RollFromPool(pool, luckPercent, rarityBias)
	-- `EggablePets`, not `Pets` -- see the note over that list. An empty pool arriving here is a bug
	-- somewhere else, and the safe thing to hand back is a species the player could have got anyway.
	if not pool or #pool == 0 then pool = GameConfig.EggablePets end
	local weights, total = poolWeights(pool, luckPercent, rarityBias)
	local roll = math.random() * total
	local acc = 0
	for i, w in ipairs(weights) do
		acc += w
		if roll <= acc then return pool[i] end
	end
	return pool[1]
end

-- Kept for any caller that only knows a zone, with no egg in hand.
function GameConfig.RollPet(luckPercent, zoneKey, rarityBias)
	return GameConfig.RollFromPool(zoneKey and GameConfig.PetsByZone[zoneKey], luckPercent, rarityBias)
end

function GameConfig.RollPetForEgg(egg, luckPercent)
	return GameConfig.RollFromPool(GameConfig.GetEggPool(egg), luckPercent, egg and egg.rarityBias)
end

-- Thousands separators, for the one figure in the game that is quoted as "1 in N" rather than as a
-- percentage. Local because that is its only caller; MainUI's own `formatNumber` abbreviates
-- (50K), which is the wrong read for odds -- the digits ARE the boast.
local function withCommas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Odds a given egg actually presents, as percentages -- what the podium board shows.
--
-- THE SECRET ROW IS APPENDED HERE RATHER THAN AT EACH BOARD (12.12). There are two boards -- the
-- billboard over the podium and the egg panel in the HUD -- and a rule written twice is a rule that
-- will be right in one place. It rides on the same function the roll shares, so the "?????" line
-- appears on precisely the eggs that can actually produce one and moves with luck exactly as the
-- roll does.
--
-- It carries `text` because neither board's number formatter can print this honestly: both fall
-- back to two decimals under 1%, and 0.002% renders as "0.00%" -- the same "advertising something
-- that cannot be won" bug the two-decimal rule was written to fix, one order of magnitude further
-- down. "1 in 50,000" is the only form of this figure a player can read. `chance` is still the real
-- percentage, so anything that sums or sorts these keeps working.
function GameConfig.GetEggOdds(egg, luckPercent)
	local pool = GameConfig.GetEggPool(egg)
	local weights, total = poolWeights(pool, luckPercent, egg and egg.rarityBias)
	local out = {}
	for i, p in ipairs(pool) do
		out[i] = { def = p, chance = weights[i] / total * 100 }
	end

	if GameConfig.CanEggHatchSecret(egg) then
		local chance = GameConfig.GetSecretChance(luckPercent)
		table.insert(out, {
			-- A DEF-SHAPED STAND-IN, not the real species. Both boards read `def.name`, `def.emoji`
			-- and `def.rarity` straight out of this entry, and naming the pet on the shop sign is
			-- the one thing a secret must not do -- what is advertised is that the Premium egg can
			-- do something the others cannot.
			def = { key = "Secret", name = "?????", emoji = "\u{2753}", rarity = "Secret" },
			chance = chance * 100,
			-- TWO STRINGS, because the two boards are two different sizes and neither can render the
			-- other's. The HUD row is 96 px of a scrolling panel and gets the digits in full; the
			-- billboard cell is a 3.7-stud square of TextScaled label sitting beside "12.5%", and
			-- eleven characters in it are a grey smear at any range you would read it from.
			text = ("1 in %s"):format(withCommas(math.floor(1 / chance + 0.5))),
			textShort = ("1/%dK"):format(math.max(1, math.floor(1 / chance / 1000 + 0.5))),
			secret = true,
		})
	end

	return out
end

-- ===== REBIRTH =====
-- Rebirth unlocks every 5 stages (5, 10, 15, 20 -- "Tier" 1 through 4) instead of only at the
-- very end: you can cash in early for a small reward, or push further for a much bigger one.
-- It resets DNA, stage, upgrades, mutations, zones and boss kills, but keeps Pets. What it pays is
-- permanent damage and permanent income, both read straight off the counter -- see
-- GetRebirthDamageMult and GetRebirthIncomeMult. It pays no Evolution Shards at all.
GameConfig.RebirthTierSize = 5
GameConfig.RebirthRequirementStageIndex = GameConfig.RebirthTierSize -- stage 5 = earliest possible rebirth
GameConfig.MaxRebirthTier = math.floor(#GameConfig.Stages / GameConfig.RebirthTierSize) -- 20 / 5 = 4

-- ===== WHY THERE IS NO GetShardIncomeBonusPct HERE ANY MORE (9.4) =====
--
-- A shard used to be worth +2% income forever, and 9.2 moved that income onto the rebirth counter
-- (GetRebirthIncomeMult) when rebirth stopped paying shards. The function itself survived that move
-- and was still multiplying DNAService.GetIncomeMult by the player's shard BALANCE, which was
-- harmless only while nothing in the game could spend a shard -- and becomes a trap the moment
-- something can. Every spin of the wheel would permanently cut the spinner's income, so the correct
-- play would be to never touch the sink, and a sink nobody can afford to use is not a sink.
--
-- A shard is a spendable currency now and nothing else. That is also why the income it used to be
-- worth was moved onto the counter rather than deleted: nothing was taken away from the rebirth,
-- it was moved somewhere it cannot be spent away by accident.

-- WHAT A REBIRTH IS ACTUALLY FOR.
--
-- It used to pay only Evolution Shards, worth +2% income each -- and income is DNA, which is never
-- the thing standing between a player and the next stage (XP is). So the whole mechanic cost a
-- full climb and bought a number that did not gate anything: a pure loss at every tier.
--
-- It pays PERMANENT DAMAGE now, which is the one currency the late game is short of -- the zone
-- bosses outscale the player's health curve, and damage is what shortens those fights. It also has
-- to be worth what the reset costs: the character collection is re-collected from scratch, and a
-- full collection is worth up to +600%, so a rebirth that paid less than that would be a trap in
-- a second costume.
--
-- +50% a run, permanent, stacking, and it is kept through every later rebirth.
-- ===== WHAT A REBIRTH IS WORTH, AND WHY IT ACCELERATES =====
--
-- It was a flat +50% a rebirth. That is not enough, and the reason is arithmetic rather than
-- taste: a rebirth WIPES the character collection, which is the damage ladder, worth up to +600%.
-- Trading a x7 for a x1.5 makes the second climb slower than the first, which is the opposite of
-- what the mechanic is for -- and it was reported that way, "after rebirthing I progress far too
-- slowly".
--
-- Quadratic, so each rebirth is worth MORE than the one before it. The last zones are the hardest
-- by a very long way (creature health runs x1 in Forest to x1050 on the Absolute Plane), so a
-- linear bonus falls further behind the wall every run; an accelerating one is what lets rebirth
-- number five actually reach the end of the strip.
--
--   1 -> x2.0    2 -> x3.0 (+1.0)    3 -> x4.5 (+1.5)    4 -> x6.5 (+2.0)    5 -> x9.0 (+2.5)
--
-- The first rebirth alone (x2.0) does not replace a full collection, and it is not meant to: the
-- collection is re-earned from kills as you climb, so the two stack back up together.
GameConfig.RebirthDamagePct = 100        -- the linear term, per rebirth
GameConfig.RebirthDamageAccelPct = 25    -- the quadratic term, what makes each one worth more

function GameConfig.GetRebirthDamageMult(data)
	if not data then return 1 end
	local r = data.Rebirths or 0
	return 1 + r * GameConfig.RebirthDamagePct / 100
		+ r * (r - 1) * GameConfig.RebirthDamageAccelPct / 100
end

-- ===== A BOSS IS PRICED AGAINST THE PLAYER'S REBIRTHS, AND ONLY AGAINST THOSE =====
--
-- 14.1: boss health is `BossTargetHits * GetZoneReferenceDamage(zone)`, and that reference is the
-- damage of a BARE player standing in the zone -- no pets, no Stage Mastery, no rebirths, no
-- passes. Every one of those four is a permanent multiplier the boss curve never learned about, and
-- on a real endgame save they stacked to x166.6: The Absolute holds 789,272 and the owner's save
-- swung for 1,175,100, so the hardest fight in the game ended on the first blow, with the
-- screen-space health bar removed inside the frame that drew it.
--
-- ONLY THE REBIRTH TERM IS CANCELLED, and that is the whole design. Pricing the boss against the
-- player's entire stack would make it ~150 blows forever whatever you brought to it -- which is
-- exactly the `BOSS_MIN_HITS` clamp 11.9 removed and the `damageCap` 9.1 removed, one system over,
-- for the same reason: when the cap IS the damage, nothing a player ever buys can show against a
-- boss. Pets, Stage Mastery, the Income upgrade and the passes all still shorten the fight by their
-- full amount. A rebirth does not, because a rebirth is the one axis that is permanent, unbounded
-- and already the largest of the four (x8 by the fourth, and it keeps climbing after). Cancelling
-- it is what makes a boss the same fight on the far side of a reset -- New Game+ -- instead of a
-- victory lap that gets shorter until it is a single click.
--
-- APPLIED ON THE DAMAGE SIDE, NOT THE HEALTH SIDE, because a boss is SHARED: `Health` is one model
-- attribute and two players on one boss chip one pool (see the note over `reviveSnapshot`). There is
-- no per-player health to scale. Dividing each player's blow by their own factor is the same
-- arithmetic -- blows = health * factor / damage either way -- and it is the more correct of the two
-- for a shared pool, because each player's contribution is normalised to their own progress rather
-- than to whoever happened to arrive first. It costs nothing on screen: the boss path sends
-- `bossBar` (hp and max) and never a damage number, so there is no figure for a player to read as
-- wrong. The creature beside it is untouched and still shows the full number.
function GameConfig.GetBossDamageDivisor(data)
	-- >= 1 for every rebirth count, so this can never turn a blow into a heal
	return math.max(GameConfig.GetRebirthDamageMult(data), 1)
end

-- Which rebirth tier (1-4) a given stage index has reached. Tier 0 = not eligible yet.
function GameConfig.GetRebirthTier(stageIndex)
	return math.floor((stageIndex or 0) / GameConfig.RebirthTierSize)
end

-- The inverse: the stage a given tier's checkpoint sits on, which is the creature whose statue
-- stands for that tier in the Rebirth Shrine (5 = Wolf, 10 = Cosmic Being, 15 = Reality
-- Architect, 20 = The Absolute). Clamped so a tier past the end of the chain still names a stage.
function GameConfig.GetRebirthTierStageIndex(tier)
	return math.clamp((tier or 1) * GameConfig.RebirthTierSize, 1, #GameConfig.Stages)
end

-- ===== REBIRTH IS A LADDER OF FOUR MILESTONES, EACH SPENT ONCE =====
--
-- It used to be a repeatable reset: reach stage 5 and you could cash in as often as you liked, at
-- whichever of the four statues you had earned, forever. That makes a rebirth a grind decision
-- rather than an event -- there is no "next" to point at, nothing is ever unlocked, and the honest
-- optimum is to farm the cheapest tier over and over, which is the least interesting thing the
-- mechanic can do.
--
-- Four milestones now, strictly in order, each consumed permanently:
--
--   Rebirth 1 -> stage  5     Rebirth 2 -> stage 10
--   Rebirth 3 -> stage 15     Rebirth 4 -> stage 20, and that is the last one.
--
-- IT NEEDS NO NEW SAVE FIELD, and that is deliberate -- `data.Rebirths` already counts exactly how
-- many have been spent, and because they are consumed in order the count IS the position on the
-- ladder. A separate "tiers used" set would be a second source of truth that could disagree with
-- the counter, and every save in existence would need repairing to build it.
--
-- Saves that predate this carry more than four (the owner's test save has eight). They keep every
-- point of what they earned -- GetRebirthDamageMult is unchanged and still reads the raw count --
-- they simply have no milestone left to spend, which is what `GetNextRebirthTier` returning nil
-- means. Never take something away to enforce a new rule.
GameConfig.MaxRebirths = GameConfig.MaxRebirthTier

-- The milestone this save may use next, or nil when the ladder is finished. Everything else about
-- rebirth availability is derived from this one function, so the HUD, the shrine and the server can
-- never disagree about which statue is live.
function GameConfig.GetNextRebirthTier(data)
	local done = (data and data.Rebirths) or 0
	if done >= GameConfig.MaxRebirths then return nil end
	return done + 1
end

-- The stage that milestone is gated behind (5, 10, 15, 20), or nil when there is none left.
function GameConfig.GetNextRebirthStage(data)
	local tier = GameConfig.GetNextRebirthTier(data)
	return tier and GameConfig.GetRebirthTierStageIndex(tier) or nil
end

-- The single question the button asks. Returns `false, reason` so the UI never has to reconstruct
-- why it is locked out of the numbers.
function GameConfig.CanRebirthNow(data)
	local tier = GameConfig.GetNextRebirthTier(data)
	if not tier then return false, "done" end
	if ((data and data.StageIndex) or 1) < GameConfig.GetRebirthTierStageIndex(tier) then
		return false, "stage"
	end
	return true, "ready"
end

-- ===== WHAT A REBIRTH PAYS ON THE INCOME SIDE, NOW THAT IT PAYS NO SHARDS =====
--
-- Rebirth used to hand over Evolution Shards, worth +2% income each and kept forever. Shards are
-- becoming a rare drop off the raised creatures with the wheel as their only sink (see 9.4), and a
-- currency that is SPENT cannot also be a permanent stat -- so the income a rebirth was worth moves
-- here, onto the counter, where it cannot be spent away by accident.
--
-- Linear at +150% a run against damage's accelerating curve, on purpose: income is the currency the
-- upgrades, eggs and shops run on and it is already geometric in the stage, while damage is the one
-- thing the late zones are actually short of. Four rebirths therefore end at x7 income and x8
-- damage.
GameConfig.RebirthIncomePct = 150

function GameConfig.GetRebirthIncomeMult(data)
	local r = (data and data.Rebirths) or 0
	return 1 + r * GameConfig.RebirthIncomePct / 100
end

-- ===== DAILY REWARDS =====
-- 7-day cycle. Potions are introduced starting Day 3. Day 6 gives a bonus Shard, Day 7 is
-- the big one (DNA + Potions + Shards). Cycle repeats (day 8 = day 1 again).
-- Each day's DNA is ~2.2x the previous (even, predictable growth). Potions scale by +1
-- per day starting Day 3 (1,2,3,4,5), Diamonds by +1 starting Day 6 (1,2) -- no jumps.
GameConfig.DailyRewards = {
	{ day = 1, dna = 200 },
	{ day = 2, dna = 450 },
	-- `potionId` names which of the nine bottles the day hands over; the later days give bigger
	-- ones rather than simply more of the smallest, so the week reads as an escalation.
	{ day = 3, dna = 1000,  potions = 1, potionId = "dna_s" },
	{ day = 4, dna = 2200,  potions = 2, potionId = "xp_s" },
	{ day = 5, dna = 4800,  potions = 2, potionId = "luck_m" },
	{ day = 6, dna = 10500, potions = 2, potionId = "dna_m", diamonds = 1 },
	{ day = 7, dna = 23000, potions = 1, potionId = "dna_l", diamonds = 2, shards = 3 },
}

-- ===== GROUP & COMMUNITY REWARDS (Phase 5.5) =====
-- Group membership gives permanent +10% DNA and unlocks a daily chest.
-- Liking and Favoriting reward one-time diamond and potion boosts.
GameConfig.RobloxGroupId = 0 -- Configurable group id (default 0; in Studio always grants access)
GameConfig.GroupIncomeMult = 1.10 -- +10% DNA permanent income boost for group members
GameConfig.GroupChestReward = {
	dna = 1000, -- scaled by GameConfig.ScaleReward
	diamonds = 25,
	potions = 1,
	potionId = "dna_m",
}
GameConfig.LikeReward = {
	diamonds = 15,
	potions = 1,
	potionId = "luck_m",
}
GameConfig.FavoriteReward = {
	diamonds = 15,
	shards = 2,
}

-- ===== POTIONS =====
-- There used to be ONE potion: a five-minute x2 on income, held as a single integer on the save.
-- Three effects in three sizes now -- nine bottles -- because a consumable with no choice in it is
-- just a delayed number, and because the three things a player actually wants to hurry are not the
-- same thing: DNA is the currency, XP is the evolve gate, and Luck is the whole egg/pet economy.
--
-- ONE ACTIVE BOTTLE PER KIND. Drinking a second DNA potion while one is running does not stack the
-- multiplier -- it takes the HIGHER of the two and adds the remaining time -- but a DNA, an XP and
-- a Luck potion all run at once. Stacking multipliers is how a consumable economy turns into a
-- single 'drink everything at hour three' decision; running three different effects together is a
-- choice about what to hurry.
--
-- `data.Potions` is a table keyed by potion id ('dna_s'), and `data.PotionBoosts` is keyed by KIND
-- ('dna'). Both are string-keyed on purpose: a table whose only keys are integers is a sparse array
-- and Roblox silently drops those crossing a RemoteEvent -- the bug that ate EquippedCharacters.
GameConfig.PotionKinds = {
	{ key = "dna",  name = "DNA",  emoji = "\u{1F9EC}", color = Color3.fromRGB(96, 200, 255),  blurb = "DNA from every source" },
	{ key = "xp",   name = "XP",   emoji = "\u{2B50}",   color = Color3.fromRGB(255, 206, 92),  blurb = "Evolution XP" },
	{ key = "luck", name = "Luck", emoji = "\u{1F340}", color = Color3.fromRGB(126, 226, 132), blurb = "egg, pet, character and mutation luck" },
	-- ===== THE FOURTH KIND (11.8) =====
	--
	-- Nine potions become twelve without a single new potion being written, because the loop below
	-- builds every kind x size combination itself -- which is the property the row was protecting:
	-- a size added later cannot be given to three kinds and forgotten on the fourth.
	--
	-- It multiplies MAX HEALTH, and deliberately not by `size.mult`. Max health already scales with
	-- the stage and with Stage Mastery and with the worn skin's rank; a x5 on top of that product for
	-- twenty minutes is not a consumable, it is a different game. `healthMult` is its own column on
	-- the sizes table so the numbers can be gentle (1.5 / 2 / 2.5) while the table still refuses to
	-- let a new size skip it.
	{ key = "health", name = "Health", emoji = "\u{2764}\u{FE0F}", color = Color3.fromRGB(255, 104, 118), blurb = "max health, and faster regeneration" },
}

-- Luck is an ADDITIVE percentage everywhere else in the game (upgrades give +2 a level, pets give
-- luckAdd), so a luck potion has to add too -- a multiplier on a stat that starts at zero does
-- nothing at all for a new player, which is exactly who buys the first one.
GameConfig.PotionSizes = {
	{ key = "s", name = "Small",  emoji = "\u{1F9EA}", minutes = 5,  mult = 2, luckAdd = 25,  healthMult = 1.5, regenMult = 3, costMult = 1 },
	{ key = "m", name = "Medium", emoji = "\u{2697}\u{FE0F}", minutes = 10, mult = 3, luckAdd = 55,  healthMult = 2.0, regenMult = 5, costMult = 2.8 },
	{ key = "l", name = "Large",  emoji = "\u{1F36F}", minutes = 20, mult = 5, luckAdd = 120, healthMult = 2.5, regenMult = 8, costMult = 7 },
}

-- The nine, built from the two lists above so a size or an effect can never be added to one and
-- forgotten in the other.
GameConfig.Potions = {}
GameConfig.PotionsById = {}
for _, kind in ipairs(GameConfig.PotionKinds) do
	for _, size in ipairs(GameConfig.PotionSizes) do
		local potion = {
			id = kind.key .. "_" .. size.key,
			kind = kind.key,
			size = size.key,
			name = size.name .. " " .. kind.name .. " Potion",
			shortName = size.name .. " " .. kind.name,
			emoji = kind.emoji,
			sizeEmoji = size.emoji,
			color = kind.color,
			minutes = size.minutes,
			seconds = size.minutes * 60,
			-- Each kind carries exactly the field it acts through and nils the rest: luck is additive
			-- points, health has its own gentler multiplier plus a regen rate, and DNA and XP take
			-- the shared `size.mult`. `applyBoost` keeps the STRONGER of each field when a second
			-- bottle is drunk, so a field that is nil for a kind simply never enters that comparison.
			mult = (kind.key == "dna" or kind.key == "xp") and size.mult
				or (kind.key == "health") and size.healthMult
				or nil,
			luckAdd = (kind.key == "luck") and size.luckAdd or nil,
			regenMult = (kind.key == "health") and size.regenMult or nil,
			costMult = size.costMult,
			blurb = kind.blurb,
		}
		-- %.15g rather than %d, since 11.8's health multipliers are fractional (1.5) and %d on a
		-- float is an error in Luau, not a rounding. It still prints "x2" for the whole ones.
		potion.effectText = potion.mult
			and ("x%.15g %s"):format(potion.mult, kind.blurb)
			or ("+%d%% %s"):format(potion.luckAdd, kind.blurb)
		table.insert(GameConfig.Potions, potion)
		GameConfig.PotionsById[potion.id] = potion
	end
end

-- What a grant with no id attached hands over (old saves, Daily Rewards, Robux bundles).
GameConfig.DefaultPotionId = "dna_s"

function GameConfig.GetPotion(id)
	return GameConfig.PotionsById[id]
end

-- The live boost for one kind, or nil. Expiry is checked HERE rather than by a timer, so a boost
-- that ran out while the player was offline is simply never returned and nothing has to clean up.
function GameConfig.GetPotionBoost(data, kind)
	local boost = data and data.PotionBoosts and data.PotionBoosts[kind]
	if not boost then return nil end
	if (boost.untilTs or 0) <= os.time() then return nil end
	return boost
end

-- 1 when nothing is running, so every caller can multiply unconditionally.
function GameConfig.GetPotionMult(data, kind)
	local boost = GameConfig.GetPotionBoost(data, kind)
	return (boost and boost.mult) or 1
end

-- ===== THE HEALTH BOTTLE'S TWO NUMBERS (11.8) =====
--
-- Kept as their own accessors rather than letting call sites reach for `GetPotionMult(data,
-- "health")`, because the max-health one is multiplied into a product that already has three terms
-- in it (stage, Stage Mastery, worn skin rank) and the regen one is a rate, not a multiplier on
-- anything. Both return the neutral value when nothing is running, so both are safe to apply
-- unconditionally -- the same contract `GetPotionMult` has.
function GameConfig.GetPotionHealthMult(data)
	return GameConfig.GetPotionMult(data, "health")
end

function GameConfig.GetPotionRegenMult(data)
	local boost = GameConfig.GetPotionBoost(data, "health")
	return (boost and boost.regenMult) or 1
end

-- Additive percentage points, matching every other luck source.
function GameConfig.GetPotionLuckAdd(data)
	local boost = GameConfig.GetPotionBoost(data, "luck")
	return (boost and boost.luckAdd) or 0
end

-- The one place a potion is added to a save. Every grant path -- shop, Daily Reward, playtime
-- gift, Robux bundle -- goes through it, so the number->table migration only had to be got right
-- once and an unknown id can never quietly create a bottle that does not exist.
function GameConfig.AddPotions(data, potionId, count)
	local potion = GameConfig.PotionsById[potionId] or GameConfig.PotionsById[GameConfig.DefaultPotionId]
	if type(data.Potions) ~= "table" then data.Potions = {} end
	data.Potions[potion.id] = (data.Potions[potion.id] or 0) + (count or 1)
	return potion
end

-- How many of everything a player is holding, for the HUD badge.
function GameConfig.CountPotions(data)
	local n = 0
	for _, count in pairs((data and data.Potions) or {}) do
		if type(count) == "number" then n += count end
	end
	return n
end

-- ===== BOSS EVENT ARENA =====
-- A separate arena reached through its own gate at the Forest spawn, holding one enormous boss
-- that returns on a timer. It exists because every other boss in the game is a solo wall you grind
-- past once: this one is far too big for any single player's damage, comes back whether or not it
-- was beaten, and pays every player who landed a hit rather than only the one who finished it.
--
-- The arena is parked straight through that gate, beyond the Forest platform's +Z boundary and
-- clear of its backdrop mesas.
--
-- THAT CLEARANCE IS THE WHOLE REASON FOR THE NUMBER. It was 900 on the strength of a comment
-- saying the mesas reach z ~ 389, which stopped being true when Forest got its backdrop: they
-- now top out at z = 723, and the arena's ground disc starts at centre - 302. At 900 that put a
-- row of 288-stud teal mesas standing INSIDE the Colosseum, directly behind the way home -- the
-- "the arena overlaps the portal" report. 1400 clears the tallest of them by ~375 studs, and
-- costs nothing: the only way in or out is a teleport, so distance is free.
GameConfig.EventArena = {
	key = "EventArena",
	name = "Colosseum",
	emoji = "\u{2694}\u{FE0F}",
	accentColor = Color3.fromRGB(255, 96, 72),
	groundColor = Color3.fromRGB(196, 176, 148),
	centre = Vector3.new(0, 0, 1400),
	radius = 210,
	-- where a player lands coming in, and which way they are turned: at the near edge, looking
	-- across the sand at the dais
	arrivalZ = 1400 - 168,
}

GameConfig.EventBoss = {
	name = "The Devourer",
	emoji = "\u{1F479}",
	-- Nearly twice the last zone boss (68) and four times the first. The whole point of the event
	-- is a silhouette you can see from the gate.
	size = 124,
	health = 25000000,
	dnaReward = 60000000,
	-- Paid to EVERY player who landed a hit, not split between them -- an event that pays less the
	-- more people turn up is an event nobody turns up to. Generous on purpose: a 25M-health raid is
	-- worth several levels to anyone strong enough to be there. BossService clamps it to two of the
	-- RECEIVING player's levels, so a stage-2 player who lands one hit does not skip half the chain.
	xpReward = 20000,
	retaliateChance = 0.5,
	retaliateDamage = { 240, 420 },
	auraRange = 60,
	auraDamage = { 60, 110 },
	auraInterval = 1.4,
	-- how often it returns, and how long it stays if nobody finishes it
	intervalSeconds = 1800, -- 30 minutes
	despawnSeconds = 900,   -- 15 minutes on the sand, then it leaves
	-- a player under this stage can walk in and watch, but cannot hit it
	minStageIndex = 4,
}

-- ===== WHICH SHOP STANDS IN WHICH ZONE =====
-- Every one of the twenty villages used to carry the same three potion counters -- a market stall,
-- a supply stall and a cauldron -- which meant the shop was never a reason to go anywhere. There
-- are fifteen shops in the whole strip now -- eight of them in the last nine zones, five zones with
-- none at all -- so which shop a zone carries is information rather than scenery.
--
-- Keyed by zone INDEX (= evolution stage), which is how the strip is actually ordered. The zone
-- named beside each entry is what that index resolves to today; the index is what decides.
-- ===== THE BACK HALF OF THE STRIP USED TO HAVE FOUR SHOPS IN NINE ZONES (12.9) =====
--
-- Eight shops was the right correction to twenty identical market rows and the wrong DISTRIBUTION:
-- six of the eight stood in zones 3-11, so a player past the Wormhole walked four zones at a time
-- between counters and the Upgrade Emporium -- the only door to the Mastery panel -- was at zone 8,
-- i.e. behind them for the whole of the late game. Fifteen entries now, and the rule that replaces
-- "one every four" is: **from zone 12 on, every zone has a shop**, in the repeating order
-- Emporium -> Mystery -> Fusion -> Mystery. The front half is unchanged, including the two plain
-- tutorial zones -- arriving somewhere with a shop is still meant to be an event where it is rare,
-- and the late game is where a player has the currency to spend and no reason to walk past.
GameConfig.ZoneShops = {
	-- Mystery Potions: one every four zones to begin with, first at 3 (the first two are the
	-- tutorial stretch and stay deliberately plain, which is where the old cauldron started too),
	-- then every other zone from 13.
	[3]  = "mystery",  -- Ocean
	[7]  = "mystery",  -- Galaxy
	[11] = "mystery",  -- Wormhole
	[13] = "mystery",  -- Time Rift
	[15] = "mystery",  -- Dream Dimension
	[17] = "mystery",  -- Void Expanse
	[19] = "mystery",  -- Singularity
	-- Pet Fusion, at the points where a player has been hatching long enough to be holding
	-- duplicates worth fusing.
	-- MOVED 5 -> 4. The Fusion panel had exactly ONE door in the whole game -- this counter -- so
	-- until a player reached the zone holding it, the feature did not appear to exist. That is how
	-- it was reported: "am I missing pet fusion, where is it, I am already on stage 4". By Volcano
	-- you have walked three egg stalls and are holding duplicates worth fusing. (12.8 gave it a
	-- second door in the HUD; the counters are still what the panel is FOR.)
	[4]  = "fusion",   -- Volcano
	[10] = "fusion",   -- Nebula
	[14] = "fusion",   -- Antimatter Zone
	[18] = "fusion",   -- Celestial Throne
	-- The one place in the game that sells permanent power, for the two currencies that buy it --
	-- and the only entry point the Mastery panel has, which is why one copy at zone 8 was not
	-- enough: everything it sells is bought with the money the LAST zones make.
	[8]  = "upgrades", -- Black Hole
	[12] = "upgrades", -- Quantum Realm
	[16] = "upgrades", -- Mirror Universe
	[20] = "upgrades", -- The Absolute Plane
}

-- `panel` is the MainUI panel a shop's counter opens; nil means the shop does its own work through
-- a server prompt instead (the mystery shop charges DNA and rolls a bottle).
GameConfig.ShopKinds = {
	mystery = {
		name = "Mystery Potions", emoji = "\u{1F52E}", title = "\u{1F52E} MYSTERY POTIONS",
		color = Color3.fromRGB(168, 96, 240),
		tagline = "One sealed bottle. You find out what it is when you drink it.",
	},
	fusion = {
		name = "Pet Fusion Lab", emoji = "\u{1F9EC}", title = "\u{1F9EC} PET FUSION LAB",
		color = Color3.fromRGB(255, 108, 168),
		panel = "pets",
		tagline = "Fuse duplicate pets into their next tier.",
	},
	upgrades = {
		name = "Upgrade Emporium", emoji = "\u{1F48E}", title = "\u{1F48E} UPGRADES",
		color = Color3.fromRGB(120, 200, 255),
		-- two counters, one per currency -- see ZoneBuilder
		counters = {
			{ panel = "mastery", actionText = "Diamond Upgrades", objectText = "\u{1F48E} Stage Mastery" },
			{ panel = "robux",   actionText = "Robux Upgrades",   objectText = "\u{1F6CD}\u{FE0F} Robux Shop" },
		},
		tagline = "Permanent power, in Diamonds and in Robux.",
	},
}

function GameConfig.GetZoneShop(zoneIndex)
	local key = GameConfig.ZoneShops[zoneIndex]
	if not key then return nil end
	return key, GameConfig.ShopKinds[key]
end

-- ===== THE MYSTERY POTION SHOP =====
-- One price, one sealed bottle, and which of the nine it turns out to be is the whole product.
-- The kind is rolled evenly across the three -- a player who wants a specific effect is buying the
-- wrong shop, and that is the point of it being the cheap one.
--
-- `costMult` multiplies the zone's mid-tier egg price, so the shop stays meaningful at every point
-- along the strip rather than being free by zone six.
GameConfig.MysteryShop = {
	-- 3x the mid-tier egg, where the old guaranteed cauldron bottle was 2.5x. The roll averages
	-- about 1.6 small-bottles' worth, so per DNA this is the better buy -- which it has to be:
	-- there are seven of these in the whole game and reaching the first of them is a walk.
	costMult = 3,
	minCost = 1200,
	-- Weighted toward the small bottle, with the twenty-minute one rare enough to be worth the
	-- walk. Luck shifts this -- see RollMysteryPotion -- so the luck economy reaches the shop too.
	sizeRolls = {
		{ size = "s", weight = 66 },
		{ size = "m", weight = 27 },
		{ size = "l", weight = 7 },
	},
}

-- Returns the potion id and how many bottles. Luck lifts the bigger sizes only -- the same shape
-- the egg pools use, where the rarer an outcome already is the more luck moves it.
function GameConfig.RollMysteryPotion(luckPercent)
	local rolls = GameConfig.MysteryShop.sizeRolls
	local weights, total = {}, 0
	for i, r in ipairs(rolls) do
		-- i = 1 is the small bottle and is never boosted; the step up per size is what luck buys
		local w = r.weight * (1 + ((luckPercent or 0) / 100) * (i - 1) * 0.6)
		weights[i] = w
		total += w
	end
	local pick = math.random() * total
	local size = rolls[1].size
	for i, r in ipairs(rolls) do
		pick -= weights[i]
		if pick <= 0 then size = r.size break end
	end
	local kinds = GameConfig.PotionKinds
	local kind = kinds[math.random(1, #kinds)].key
	return kind .. "_" .. size
end

function GameConfig.GetMysteryCost(zoneKey)
	local eggs = GameConfig.GetEggsForZone(zoneKey)
	local base = (eggs[2] and eggs[2].cost) or 1500
	return math.max(GameConfig.MysteryShop.minCost, math.floor(base * GameConfig.MysteryShop.costMult))
end

-- ===== WHAT THE KIOSK'S ODDS BOARD IS BUILT FROM (12.8) =====
--
-- The same shape `GetEggOdds` returns, for the same reason: the board on the counter is drawn from
-- the table `RollMysteryPotion` reads, so it can never advertise a chance the roll does not honour.
-- Luck is deliberately not a parameter -- this is the shop's BASELINE, printed on a board that is
-- built once at world-build time and read by every player who walks past it, and a player's own
-- luck only ever moves the big bottle up from what is written.
--
-- The percentages sum to 100 by construction (they are shares of the weight total), which is what
-- the row's check measures.
function GameConfig.GetMysterySizeOdds()
	local rolls = GameConfig.MysteryShop.sizeRolls
	local total = 0
	for _, r in ipairs(rolls) do total += r.weight end
	local out = {}
	for i, r in ipairs(rolls) do
		local size
		for _, s in ipairs(GameConfig.PotionSizes) do if s.key == r.size then size = s end end
		out[i] = {
			key = r.size,
			size = size,
			name = (size and size.name) or r.size,
			emoji = (size and size.emoji) or "\u{1F9EA}",
			minutes = size and size.minutes or 0,
			chance = total > 0 and (r.weight / total * 100) or 0,
		}
	end
	return out
end

-- Every kind is equally likely -- the roll picks one with `math.random(1, #kinds)` -- so the board's
-- kind line is a list of every kind that EXISTS plus one share. Written out by hand it was wrong:
-- it named three kinds beside a "%d%% each" computed over four (11.8 added Health), i.e. a board
-- advertising 75% of its own product. Built from the table it cannot drift again.
function GameConfig.GetMysteryKindsText()
	local kinds = GameConfig.PotionKinds
	local parts = {}
	for _, k in ipairs(kinds) do
		table.insert(parts, ("%s %s"):format(k.emoji, k.name))
	end
	return ("%s  \u{2022}  %d%% each"):format(table.concat(parts, "   "),
		math.floor(100 / math.max(#kinds, 1) + 0.5))
end

-- "7% chance of the twenty-minute one" is the part of a gamble a player actually wants to see, so
-- the shop's board is built from the same table the roll reads.
-- KEPT, and still the one-line form: the kiosk draws the graphical board above instead (12.8), but
-- this is what any future text sign should print rather than a second hand-written copy.
function GameConfig.GetMysteryOddsText()
	local rolls = GameConfig.MysteryShop.sizeRolls
	local total = 0
	for _, r in ipairs(rolls) do total += r.weight end
	local parts = {}
	for _, r in ipairs(rolls) do
		local size
		for _, s in ipairs(GameConfig.PotionSizes) do if s.key == r.size then size = s end end
		table.insert(parts, ("%s %d%%"):format(size and size.name or r.size, math.floor(r.weight / total * 100 + 0.5)))
	end
	return table.concat(parts, "   ")
end

-- ===== THE LUCKY SPIN =====
--
-- One spin, eight outcomes, and which one it lands on IS the product. It sits on the shelf beside
-- the flat DNA packs deliberately: the pack is the safe buy and the wheel is the gamble, so the
-- wheel's EXPECTED DNA IS SET BELOW the pack at the same price (2,260 against 2,500 authored
-- stage-one clicks). What the buyer is paying that difference for is the tail -- diamonds, potions,
-- shards and a jackpot that no pack sells at any price. A wheel whose average beat the guaranteed
-- product would simply retire the guaranteed product, and then there would be one product again.
--
-- The weights sum to exactly 100, so at zero luck a weight IS its percentage. That is not a
-- coincidence to preserve for its own sake -- GetSpinOddsText divides by the real total either way
-- -- but while it holds, the table can be read as the odds board without doing any arithmetic.
--
-- ORDERED COMMON FIRST, and the order is load-bearing: luck lifts the later segments, the same
-- shape RollMysteryPotion uses, so the luck economy reaches this wheel too. Move a row and you have
-- changed what luck does to it.
GameConfig.SpinWheel = {
	{ key = "dna_splash", emoji = "\u{1F9EC}", name = "DNA Splash",     weight = 34,  dna = 2000 },
	{ key = "potion",     emoji = "\u{1F9EA}", name = "Potion",         weight = 24,  potionId = "dna_m", potions = 1 },
	{ key = "dna_surge",  emoji = "\u{1F9EC}", name = "DNA Surge",      weight = 18,  dna = 6000 },
	{ key = "diamonds",   emoji = "\u{1F48E}", name = "25 Diamonds",    weight = 12,  diamonds = 25 },
	{ key = "shards",     emoji = "\u{1F31F}", name = "25 Shards",      weight = 7,   shards = 25 },
	{ key = "luck_l",     emoji = "\u{1F340}", name = "2x Large Luck",  weight = 3.5, potionId = "luck_l", potions = 2 },
	{ key = "vault",      emoji = "\u{1F48E}", name = "120 Diamonds",   weight = 1,   diamonds = 120 },
	{ key = "jackpot",    emoji = "\u{1F308}", name = "JACKPOT",        weight = 0.5, dna = 100000, diamonds = 60 },
}

-- How hard luck bends the wheel. NORMALISED BY SEGMENT COUNT -- (i-1)/(n-1), where
-- RollMysteryPotion uses a raw (i-1) -- and that difference is the whole reason this constant
-- exists. That table has three rows and this one has eight, so under a raw index the same luck
-- would bend this wheel nearly three times as hard, and adding a ninth segment one day would
-- silently make every existing player luckier without a line of code changing. Normalised, the
-- strength of luck is a property of this constant alone.
--
-- At the game's worst honest luck (385%, measured in the ROADMAP 2.12 balance pass) the jackpot
-- moves 0.5% -> 1.4% and the commonest segment 34% -> 17%. Luck is worth having here and does not
-- take the wheel over.
GameConfig.SpinLuckSpread = 1.2

-- What one spin costs in Evolution Shards, for the door into this wheel that takes no Robux (9.4).
-- 25 is exactly what the wheel's own `shards` segment pays, so 7 spins in 100 come back as the
-- price of the next one and that segment needed no rebalancing to say so. Everything the 3.3
-- balance pass measured about this wheel still holds unchanged: it is the same table, the same
-- roll and the same luck bend, reached through a third door.
GameConfig.SpinCostShards = 25

-- Returns the winning SEGMENT TABLE, not an index or a key -- the caller grants straight off it, so
-- there is no second lookup that could disagree with the roll.
function GameConfig.RollSpin(luckPercent)
	local wheel = GameConfig.SpinWheel
	local n = #wheel
	local weights, total = {}, 0
	for i, seg in ipairs(wheel) do
		-- i = 1 is the commonest segment and is never boosted; what luck buys is the step up the list
		local spread = (n > 1) and ((i - 1) / (n - 1)) or 0
		local w = seg.weight * (1 + ((luckPercent or 0) / 100) * spread * GameConfig.SpinLuckSpread)
		weights[i] = w
		total += w
	end
	local pick = math.random() * total
	for i, seg in ipairs(wheel) do
		pick -= weights[i]
		if pick <= 0 then return seg end
	end
	return wheel[1]
end

-- The odds board, built from the same table the roll reads -- the rule the Mystery shop already
-- follows. A gamble the player cannot see the odds of is not a product, it is a trick.
function GameConfig.GetSpinOddsText()
	local total = 0
	for _, seg in ipairs(GameConfig.SpinWheel) do total += seg.weight end
	local parts = {}
	for _, seg in ipairs(GameConfig.SpinWheel) do
		table.insert(parts, ("%s %s %.4g%%"):format(seg.emoji, seg.name, seg.weight / total * 100))
	end
	return table.concat(parts, "   ")
end

-- ===== DIAMONDS =====
-- Premium currency, separate from DNA and Evolution Shards. Earned from Daily Rewards
-- (Day 6+) and spent on the 3 Diamond Upgrades below -- permanent, powerful, and priced
-- in Diamonds instead of DNA so they stay a long-term grind, not an early-game shortcut.
--
-- ===== THE PRICES WERE WRITTEN BEFORE DIAMONDS HAD A GAMEPLAY SOURCE (11.11) =====
--
-- `baseCost = 5, costMult = 1.6` for "+10% permanent income per level, forever" was authored when
-- the only diamonds in the game came from a daily login, a playtime milestone or a Robux product
-- whose id was still 0. Under those rules five diamonds was several days of showing up. Then 10.x
-- made a KILL the source -- see DiamondDropChance below -- and none of these three numbers moved.
--
-- MEASURED, not estimated (2026-08-12), by driving the real AutoAttack remote at the client's own
-- 0.34 s cadence in Galaxy and reading the diamond balance off the real DataUpdate payload:
--
--   * ROAMING the whole valley with no travel cost -- 254 kills in 180 s, 85 a minute -- pays
--     **13 diamonds, i.e. ~260 an hour**. That total is not a lucky sample: the observed tier mix
--     (177 Swarmer / 59 Critter / 16 Brute / 2 Elite) predicts 12.05 against DiamondDropChance
--     below, so the source and the table agree to within noise.
--   * PARKED in the densest valley cluster and letting the respawns come back -- which is what
--     auto-attack farming actually looks like -- pays **4 diamonds in 176 s, ~82 an hour**, with
--     74% of the swing budget spent with nothing alive inside the 60-stud auto-attack reach.
--
-- The band is therefore 80-260 an hour and the only variable is how much the player roams; the
-- kills themselves are not the constraint, since a player standing in their own zone one-shots
-- valley creatures (the minHits damage cap came off in the damage-ladder pass). Everything below
-- is priced against **~120 an hour**, near the bottom of that band. Against it
-- the OLD first level of Mega Income cost about two and a half minutes of play, for a permanent
-- multiplier on every click, every kill, every idle tick and every offline payout in the game --
-- and the whole first ten levels, +100% income forever, cost 903 diamonds, i.e. seven and a half
-- hours. A permanent upgrade that pays for itself before the player has finished reading its card
-- is not a purchase, it is a formality.
--
-- THE FIX IS PRICES ONLY. Nothing about what these grant changes, no cap is added, and PetSlot
-- keeps its maxLevel of 3. Bases go up ~5x and the multipliers up a step:
--
--     Mega Income  5 -> 25   x1.6 -> x1.75    first 10 levels:   903 ->  8,942
--     Mega Luck    8 -> 40   x1.6 -> x1.75    first 10 levels: 1,447 -> 14,310
--     Pet Slot    15 -> 75   x2.2 -> x2.50    all 3 levels:      120 ->    730
--
-- At the measured 120/hour that is: a first Mega Income level in ~12 minutes instead of ~2, five
-- levels (+50% income) in ~4 hours, and the tenth level alone costing ~32 hours -- so the geometric
-- curve, not a `maxLevel`, is still what caps these. That is deliberate and is why the two
-- uncapped upgrades stay uncapped: a cap says "you are finished", a price says "not yet".
--
-- WHY THE MULTIPLIER MOVES TOO AND NOT JUST THE BASE. Raising only the base shifts the whole ladder
-- sideways and leaves the shape alone -- the tenth level would still cost 12x the first, and a
-- player who reached it would still be buying the eleventh the same evening. The effect is LINEAR
-- in the level (+10% each, +5 luck each) while the price is geometric, so the multiplier is the
-- only term that decides where the upgrade stops being worth buying. 1.75 puts that wall somewhere
-- around level 10-12 for a dedicated player, which is where an "endgame" permanent upgrade belongs.
--
-- STAGE MASTERY IS DELIBERATELY NOT REPRICED alongside this. It is twenty ONE-SHOT purchases each
-- gated on reaching its stage, so its ceiling is the climb rather than the wallet; a player cannot
-- rush it with diamonds however many they hold. These three are the unbounded sink and are the
-- ones a diamond income can outrun.
--
-- EXISTING SAVES KEEP EVERY LEVEL THEY BOUGHT. `GetDiamondUpgradeCost` reads the level out of the
-- save and prices the NEXT one, so a reprice is never retroactive and never refunds -- a beta
-- player who bought ten cheap levels keeps them and pays the new rate for the eleventh.
GameConfig.DiamondUpgrades = {
	MegaIncome = { displayName = "Mega Income", emoji = "💎", baseCost = 25, costMult = 1.75, effectPct = 10, description = "+10% permanent income per level" },
	MegaLuck   = { displayName = "Mega Luck",   emoji = "🍀", baseCost = 40, costMult = 1.75, effectAdd = 5,  description = "+5% Luck per level" },
	PetSlot    = { displayName = "Pet Slot",    emoji = "🐾", baseCost = 75, costMult = 2.5,  effectAdd = 1, maxLevel = 3, description = "+1 equipped pet slot per level (max 3)" },
}

-- ===== DIAMONDS FROM PLAYING =====
--
-- Until now Diamonds had no gameplay source at all. Every one of them came from a time gate --
-- the daily reward, a playtime milestone, a Season Pass tier -- or from a Robux product, and at the
-- time every RobuxProducts entry still had `productId = 0`, so that route did not work either. (The
-- ids are real since 2026-08-11, but that does not change the argument below: a player who simply
-- plays must be able to earn the currency that three permanent upgrades and twenty Stage Masteries
-- are priced in, without paying.)
--
-- A per-kill roll fixes that without touching any existing balance: it adds a currency rather than
-- multiplying an existing one.
--
-- WEIGHTED BY TIER, NOT BY STAGE. Deliberately: kill RATE already rises steeply with stage, so a
-- flat per-kill chance pays out faster and faster on its own. Tying the odds to the target instead
-- makes the tougher creature the one worth hunting and keeps the curve honest.
--
-- ===== THESE ODDS WERE TOO LOW TO BE A FEATURE =====
--
-- The first cut was sized purely against the sink: 0.003-0.040 by tier, an expected 0.0068 diamonds
-- a kill, "one every five minutes". The arithmetic was right and the design was wrong, and the
-- report was the flat sentence "I never get diamonds, I cannot earn them at all".
--
-- A 0.3% drop is invisible. A player kills two hundred Swarmers, sees nothing, and correctly
-- concludes the mechanic does not exist -- there is no partial credit and no counter ticking up, so
-- below some floor a random drop is indistinguishable from a bug. The floor is roughly "often
-- enough to happen inside one session at one spot", and 0.3% is nowhere near it.
--
-- 10x across the board. At the same 30 kills a minute and the same tier mix that is ~0.068 a kill,
-- i.e. **two a minute**: a Swarmer pays about one time in thirty, an Elite one time in three. The
-- mechanic is now legible from the first few minutes of play, which is what it has to be to read as
-- a reward at all. The sink is what should absorb this, not the source -- see DiamondUpgrades.
--
-- ===== AND THE APEX WAS WORTH LESS THAN A SWARMER (11.31) =====
--
-- This table is keyed by tier NAME and had four rows. 11.6 added a fifth tier -- the Apex, on the
-- highest shelf of every zone, behind three rebirths, with 1.25x an Elite's health, hitting back on
-- 95% of blows -- and did not add a row here, so `RollDiamondDrop("Apex")` fell through the `or 0`
-- and returned zero. Measured: 200,000 rolls per tier came back 0.0302 / 0.0604 / 0.1510 / 0.4016
-- and **0.0000**. The hardest creature in the game paid nothing in the currency every permanent
-- upgrade is priced in, while the Critter standing at the bottom of the same cliff paid 6%.
--
-- The exclusive pet is not an answer to that: it is a 5% roll, so 95% of the fight paid a
-- rebirth-gated player strictly less than a Swarmer.
--
-- 0.60, above the Elite's 0.40, because it must not merely match the tier below it -- but it is a
-- 120-second respawn and four per zone, so this is 2.4 diamonds a sweep and not a farm.
--
-- THE REAL DEFENCE IS THE ASSERT, NOT THE ROW. See `GameConfig.AssertTierCoverage`, called by
-- CreatureService at load with the tier list it actually spawns: a table keyed by name, read
-- through `or 0`, cannot report its own gaps, and a sixth tier would be silently free again.
GameConfig.DiamondDropChance = {
	Swarmer = 0.03,
	Critter = 0.06,
	Brute    = 0.15,
	Elite    = 0.40,
	Apex     = 0.60,
}

-- ===== BOSSES ALWAYS PAY, AND THEY PAY A HANDFUL =====
--
-- A boss had NO diamond source at all -- neither the zone bosses nor the Colosseum giant -- so the
-- one fight in the game that takes real effort was worth less in this currency than farming
-- Swarmers. That is backwards, and it is the other half of what was reported.
--
-- A boss is not a roll. It is a rare, scheduled, expensive fight, so it is a GUARANTEED payout and
-- the variance lives in the amount. Zone bosses give 3-6; the Colosseum giant, which is on a
-- 30-minute timer and shared between everyone present, gives 12-20.
GameConfig.BossDiamondReward = { 3, 6 }
GameConfig.EventBossDiamondReward = { 12, 20 }

function GameConfig.RollDiamondDrop(tierName)
	local chance = GameConfig.DiamondDropChance[tierName or ""] or 0
	return math.random() < chance and 1 or 0
end

-- ===== EVOLUTION SHARDS: THE ONE DROP YOU HAVE TO CLIMB FOR (9.4) =====
--
-- Shards had no gameplay source at all once 9.2 took them off the rebirth reward. What was left was
-- three time gates (the Day 6/7 login reward, the Season Pass premium track, a 7% segment of the
-- wheel) and a code -- not one of which is something a player can go and DO. They are a drop now.
--
-- And they are deliberately the only drop in this game with a PLACE attached: nothing standing on
-- the valley floor ever pays one, however long it is farmed. Only the Brutes and Elites up on the
-- terrace shelves do -- CreatureService's `raisedSpots`, which already ranks those spots by
-- altitude and puts the Elites on the highest ground there is. So the currency is earned by
-- climbing, which is the one thing the terraces were built for and the one thing nothing else in
-- the game rewards.
--
-- Sized against its sink exactly the way DiamondDropChance was sized against the upgrades. A zone
-- carries 4 raised Elites and 6 raised Brutes, so one full sweep of its shelves pays
-- 4*0.25 + 6*0.12 = 1.72 shards, and one spin of the wheel costs 25 (SpinCostShards) -- roughly a
-- quarter of an hour of deliberate cliff work per spin, against a 55-second Elite respawn. That is
-- above the "is this mechanic even real" floor the diamond note describes and far enough below a
-- diamond's rate that the two can never read as the same reward.
--
-- ===== THE APEX WAS MISSING FROM HERE TOO (11.31) =====
--
-- Same gap as DiamondDropChance, same cause -- a table keyed by tier name that 11.6's new tier was
-- never added to -- and it is worse here, because this is the currency the shelves exist to mint
-- and the Apex stands on the highest shelf of the lot. A player who spent three rebirths to be
-- allowed to fight it was paid less for it than for the Brute two terraces below.
--
-- 0.40 against the Elite's 0.25. The sweep arithmetic above becomes, for a 3-rebirth player,
-- 4*0.40 + 4*0.25 + 6*0.12 = 3.32 shards -- so a spin (25) is about seven and a half sweeps
-- instead of fifteen. That is the gate paying out, which is what a gate is for; and the roster
-- figures are 11.29's, not 9.4's, because the raised set went 10 -> 14 per zone.
GameConfig.ShardDropChance = {
	Brute = 0.12,
	Elite = 0.25,
	Apex  = 0.40,
}

-- `raised` is PASSED IN rather than inferred from anything on the creature. A Brute on the valley
-- floor and a Brute on a shelf are the same tier, the same rig and the same table of stats; the
-- only thing that tells them apart is which loop the spawner placed them from.
function GameConfig.RollShardDrop(tierName, raised)
	if not raised then return 0 end
	local chance = GameConfig.ShardDropChance[tierName or ""] or 0
	return math.random() < chance and 1 or 0
end

-- ===== A TABLE KEYED BY NAME CANNOT REPORT ITS OWN GAPS (11.31) =====
--
-- Both drop tables above are read through `... or 0`, and that fallback is right at the call site:
-- a boss, a loose `DeathBurst` part and a tier that genuinely pays nothing all have to fall through
-- it without throwing. It is also exactly why a MISSING tier is indistinguishable from a deliberate
-- zero -- 11.6 added the Apex, neither table heard about it, and nothing anywhere said so until
-- 200,000 Monte Carlo rolls were run against the tier list by hand.
--
-- So the check is inverted rather than the fallback removed. CreatureService owns the list of tiers
-- it actually spawns and hands it here at load; this file cannot go and read `TIERS` itself, because
-- GameConfig is required BY CreatureService and would be a require cycle.
--
-- Deliberately a `warn` and not an `error`: a missing drop row must never stop a server booting, and
-- the failure it guards against is silence, not a crash. Naming the table and the tier is the whole
-- difference. Returns the list so a probe can assert on it instead of reading the output log.
function GameConfig.AssertTierCoverage(allTiers, raisedTiers)
	local missing = {}
	for _, name in ipairs(allTiers or {}) do
		if GameConfig.DiamondDropChance[name] == nil then
			missing[#missing + 1] = "DiamondDropChance." .. name
		end
	end
	-- Only tiers that can actually stand on a shelf need a shard row -- `RollShardDrop` returns 0 for
	-- anything not raised, so a Swarmer row here would be dead weight that reads as a promise.
	for _, name in ipairs(raisedTiers or {}) do
		if GameConfig.ShardDropChance[name] == nil then
			missing[#missing + 1] = "ShardDropChance." .. name
		end
	end
	if #missing > 0 then
		warn("[GameConfig] no drop row for " .. table.concat(missing, ", ")
			.. " -- those kills pay nothing. See the 11.31 block in GameConfig.")
	end
	return missing
end

-- `event` picks the Colosseum giant's band instead of a zone boss's. Guaranteed, never zero.
function GameConfig.RollBossDiamonds(event)
	local band = event and GameConfig.EventBossDiamondReward or GameConfig.BossDiamondReward
	return math.random(band[1], band[2])
end

function GameConfig.GetDiamondUpgradeCost(key, level)
	local def = GameConfig.DiamondUpgrades[key]
	if not def then return math.huge end
	if def.maxLevel and level >= def.maxLevel then return math.huge end
	return math.floor(def.baseCost * (def.costMult ^ level))
end

function GameConfig.GetMaxEquippedPets(data)
	local petSlotLevel = data.DiamondUpgrades and data.DiamondUpgrades.PetSlot or 0
	-- The +3 Pet Slots pass stacks ON TOP of the diamond upgrade rather than replacing it: the
	-- upgrade is capped at 3 levels, so a player who bought all three and then bought the pass has
	-- spent in both currencies and should get both. 3 base + 3 diamond + 3 pass = 9.
	return GameConfig.MaxEquippedPets + petSlotLevel + GameConfig.GetPassAdd(data, "petSlots")
end

-- ===== STAGE MASTERY =====
-- One permanent, Diamond-priced unlock per evolution stage: reach a stage and you may buy its
-- Mastery, once, forever. Where the three Diamond Upgrades above are levelled infinitely, these
-- are twenty separate one-shot purchases -- a checklist that fills in as you climb.
--
-- Deliberately NOT reset by Rebirth (see RebirthService, which clears stages, zones and bosses).
-- That is the whole point: Rebirth throws you back to Cell, and Mastery is what makes the second
-- climb faster than the first.
--
-- Every Mastery grants the same bonus no matter which stage it belongs to; only the price scales.
-- That keeps the early ones worth mopping up late -- they are the cheap ones still on the board --
-- instead of the list collapsing into "only the last three matter".
-- Roblox's default 16 is a crawl on a 450x550 platform with a shop at one end and a boss at the
-- other, and it made the whole strip feel like wading. Mastery stacks on top of this.
GameConfig.BaseWalkSpeed = 34
-- Deliberately BELOW Roblox's default 50. The character used to leave the ground higher than the
-- shop awnings, which reads as a platformer rather than a tycoon and made every fall off the
-- platform edge the player's own doing. Everything a player has to get on top of is low: the plaza
-- deck is 3 studs, the podium 6, the shop steps 2 each. 44 clears 4.9 studs at stage one and, with
-- the size multiplier at the top stage, about 11 -- enough for every step in the game and nothing
-- more.
GameConfig.BaseJumpPower = 44

-- ===== SPEED SCALES WITH THE BODY =====
-- The single biggest reason movement read as sluggish. A player's body runs 1x -> 9x across the
-- twenty stages (see GameConfig.Stages[].scale) while the walk speed stayed at one constant, so a
-- Human-stage character nineteen studs tall was crossing the ground at the same studs/second a
-- one-stud Cell did. Apparent speed is studs per second divided by body height: at 3.8x that is a
-- quarter of the pace the same number gives at 1x, which is exactly what "wading" feels like.
--
-- Strict proportionality (speed = base * scale) would put the last stage at over 300 studs/second,
-- which outruns StreamingEnabled and turns the strip into a slideshow of ungenerated ground. The
-- exponent keeps the early stages honest and flattens the top, and the caps are the hard ceiling.
-- The caps are set where they are because of what sits under them. 150 studs/s crosses the 860-stud
-- platform in under six seconds, which StreamingEnabled keeps up with; much past that and a player
-- outruns the ground they are running on. 92 of jump power is 21 studs of height, nowhere near
-- the 180-stud zone walls -- a jump that clears a boundary drops the player into the gap between
-- two platforms, where there is no floor at all.
--
-- THE BODY SCALE CURVE WAS HALVED at the same time: GameConfig.Stages[].scale now runs 1.0 -> 5.0
-- where it used to run 1.0 -> 9.0. A late-stage player was tall enough that a whole platform read
-- as a small room, and every prop beside them looked like furniture in a doll's house. The growth
-- is still monotonic and every evolve is still visible; it is the top of the curve that came down.
GameConfig.SpeedScaleExponent = 0.82
GameConfig.MaxWalkSpeed = 150
GameConfig.MaxJumpPower = 92

-- How much of the size a character actually gets back as pace. Shared by walk and jump so a giant
-- that covers ground quickly can also still clear its own shop steps.
function GameConfig.GetSizeSpeedMultiplier(bodyScale)
	local s = math.max(tonumber(bodyScale) or 1, 1)
	return s ^ GameConfig.SpeedScaleExponent
end

GameConfig.StageMastery = {
	baseCost = 3,
	costGrowth = 1.22, -- stage 1 costs 3 diamonds, stage 20 costs 135; ~700 for the full set
	damagePct = 12,    -- +12% combat damage each
	-- Was 0.8. One Mastery took you from 16.0 to 16.8 studs/second, which nobody can feel -- the
	-- button read as broken even though it was working, because the only visible effect was a
	-- number in a tooltip. At 1.8 a single purchase is unmistakable and the full set roughly
	-- doubles the base again.
	walkSpeed = 1.8,   -- +1.8 studs/second each (all 20 = +36)
	jumpPower = 1.2,   -- +1.2 each (all 20 = +24), so mastery is felt vertically too
	healthPct = 5,     -- +5% max health each
}

function GameConfig.GetStageMasteryCost(stageIndex)
	local m = GameConfig.StageMastery
	return math.floor(m.baseCost * (m.costGrowth ^ (stageIndex - 1)))
end

-- Stored as a list of stage indices rather than a keyed set, matching DefeatedBosses: DataStore
-- round-trips arrays cleanly, where a table with sparse integer keys comes back with string keys.
function GameConfig.HasStageMastery(data, stageIndex)
	for _, i in ipairs(data.MasteredStages or {}) do
		if i == stageIndex then return true end
	end
	return false
end

-- Combined effect of everything mastered so far. One table because the three callers -- combat
-- damage, walk speed and max health -- each want a different field off the same count.
function GameConfig.GetStageMasteryBonus(data)
	local owned = #(data.MasteredStages or {})
	local m = GameConfig.StageMastery
	return {
		owned = owned,
		damageMult = 1 + owned * (m.damagePct / 100),
		walkSpeed = owned * m.walkSpeed,
		jumpPower = owned * (m.jumpPower or 0),
		healthMult = 1 + owned * (m.healthPct / 100),
	}
end

-- ===== PLAYTIME GIFTS =====
-- Session-based (not persisted): the longer a player stays connected in one sitting, the
-- better the gift waiting for them. Resets to Day-1-style milestones each time they rejoin.
GameConfig.PlaytimeGifts = {
	{ minutes = 10, dna = 1000 },
	{ minutes = 20, dna = 2500,  potions = 1, potionId = "dna_s" },
	{ minutes = 30, dna = 6000,  potions = 1, potionId = "xp_m" },
	{ minutes = 45, dna = 15000, diamonds = 1 },
	{ minutes = 60, dna = 35000, potions = 1, potionId = "luck_l", diamonds = 2 },
}

-- ===== ROBUX SHOP =====
-- Real-money packages bought with Robux via MarketplaceService Developer Products.
--
-- THE IDS BELOW ARE REAL AS OF 2026-08-11. All seventeen were created on the Creator Dashboard
-- against universe **10675543038 ("Evolution Lab BETA V0.2")** -- the experience the play-testers
-- actually join -- with Managed pricing DISABLED on every one, so the price the dashboard shows is
-- exactly the price in this table and nothing re-prices them per region.
--
-- A PRODUCT ID IS BOUND TO ITS UNIVERSE. If this place is ever published to a different experience
-- these ids stop resolving and every purchase fails, so they have to be re-created and re-pasted
-- there. `productId = 0` is still the "not set up yet" sentinel, and RobuxShopService refuses to
-- prompt on it rather than opening a dialog that cannot complete.
-- ===== FIVE TIERS PER CURRENCY, AND WHY THE LADDER IS SHAPED THIS WAY =====
--
-- There used to be two DNA packs and two Diamond packs. Two price points is not a shop, it is a
-- yes/no question: a player who finds the small one too small and the large one too expensive has
-- nowhere to land, and the whole 199-499 band -- which is where this genre actually earns -- was
-- simply absent. Five tiers at 49 / 99 / 199 / 499 / 999 is the shape every comparable game runs
-- (see the market notes in ROADMAP.md), and it is a LADDER rather than a list: each rung must be
-- better VALUE PER ROBUX than the one below it, never merely bigger. That one rule is what makes
-- trading up read as a discount instead of a bigger bill, and it is not left to trust -- see
-- GetValuePerRobux and GetTierBonusPct below, which the shop UI draws its bonus ribbons from, so a
-- tile can never advertise a discount this table does not actually contain.
--
-- `price` is authored here only so the shop can render a price before Roblox answers, and so the
-- ribbons have something to divide by. It is NOT what the player is charged -- MarketplaceService
-- charges whatever the dashboard says. Keep the two in step when the real ids are pasted in.
--
-- DNA IS SCALED, DIAMONDS ARE NOT. The DNA figures are authored as "what this is worth in stage-one
-- clicks" and RobuxShopService puts them through GameConfig.ScaleReward, so a pack buys the same
-- number of kills at stage 1 and at stage 20. Diamonds are deliberately raw: every diamond sink in
-- the game is a small fixed number (the three DiamondUpgrades at 25 / 40 / 75, Stage Mastery) that
-- does not ride the stage curve, so scaling them would cap every permanent upgrade in one purchase.
-- The full reasoning sits in the grant block of RobuxShopService.
GameConfig.RobuxProducts = {
	{ key = "DNA_1", productId = 3702245508, price = 49,  tierGroup = "DNA", name = "Small DNA Pack",  emoji = "🧬", grantDNA = 1000 },
	{ key = "DNA_2", productId = 3702247541, price = 99,  tierGroup = "DNA", name = "Medium DNA Pack", emoji = "🧬", grantDNA = 2500 },
	{ key = "DNA_3", productId = 3702248045, price = 199, tierGroup = "DNA", name = "Large DNA Pack",  emoji = "🧬", grantDNA = 6000 },
	{ key = "DNA_4", productId = 3702248511, price = 499, tierGroup = "DNA", name = "Huge DNA Pack",   emoji = "🧬", grantDNA = 18000 },
	{ key = "DNA_5", productId = 3702248961, price = 999, tierGroup = "DNA", name = "Mega DNA Pack",   emoji = "🧬", grantDNA = 40000, ribbon = "BEST VALUE" },

	-- Named with their real numbers, unlike the DNA packs above: a diamond count is not scaled, so
	-- "50 Diamonds" is true at every stage, and hiding a true number behind an adjective only costs
	-- the buyer clarity.
	{ key = "Diamonds_1", productId = 3702250279, price = 49,  tierGroup = "Diamonds", name = "10 Diamonds",  emoji = "💎", grantDiamonds = 10 },
	{ key = "Diamonds_2", productId = 3702250748, price = 99,  tierGroup = "Diamonds", name = "22 Diamonds",  emoji = "💎", grantDiamonds = 22 },
	{ key = "Diamonds_3", productId = 3702251204, price = 199, tierGroup = "Diamonds", name = "50 Diamonds",  emoji = "💎", grantDiamonds = 50 },
	{ key = "Diamonds_4", productId = 3702251679, price = 499, tierGroup = "Diamonds", name = "140 Diamonds", emoji = "💎", grantDiamonds = 140 },
	{ key = "Diamonds_5", productId = 3702252142, price = 999, tierGroup = "Diamonds", name = "300 Diamonds", emoji = "💎", grantDiamonds = 300, ribbon = "BEST VALUE" },

	-- ===== EVOLUTION SHARDS (11.12) =====
	--
	-- Named with their real numbers for the same reason the Diamond packs are: a shard is not scaled,
	-- so "125 Evolution Shards" is true at every stage and an adjective would only cost the buyer
	-- clarity.
	--
	-- UNSCALED, LIKE DIAMONDS AND FOR A STRONGER REASON. A shard buys exactly one thing --
	-- `SpinCostShards`, a flat 25 -- so putting these through `ScaleReward` would let a stage-14 buyer
	-- purchase thousands of spins from one tile. The DNA packs are scaled because DNA prices ride the
	-- stage curve; nothing a shard buys does.
	--
	-- THE LADDER IS THE DIAMOND LADDER x2.5, deliberately: 10/22/50/140/300 becomes 25/55/125/350/750
	-- at the same five price points, and only three of those five rungs are cut here. That keeps the
	-- value-per-Robux curve -- which `GetTierBonusPct` derives and the shop's ribbons print -- the
	-- same shape a buyer already learned on the Diamond tiles. 25 is one spin exactly, so the cheapest
	-- rung is legible without arithmetic: it is the wheel, once.
	--
	-- Only 49 / 199 / 999 exist. Five rungs is the right shape for a currency a player spends
	-- continuously; a shard is spent 25 at a time on one machine, and three price points already
	-- cover "one go", "an evening" and "stop thinking about it". Two more rows would be two more ids
	-- to create on the dashboard for a currency with one sink.
	{ key = "Shards_1", productId = 3707419817, price = 49,  tierGroup = "Shards", name = "25 Evolution Shards",  emoji = "\u{1F31F}", grantShards = 25 },
	{ key = "Shards_2", productId = 3707425807, price = 199, tierGroup = "Shards", name = "125 Evolution Shards", emoji = "\u{1F31F}", grantShards = 125 },
	{ key = "Shards_3", productId = 3707431292, price = 999, tierGroup = "Shards", name = "750 Evolution Shards", emoji = "\u{1F31F}", grantShards = 750, ribbon = "BEST VALUE" },

	-- The wheel. Priced against the 99 R$ DNA pack it sits next to -- see the SpinWheel comment for
	-- why its expected DNA is deliberately the lower of the two.
	{ key = "LuckySpin",   productId = 3702253641, price = 99,  name = "Lucky Spin",    emoji = "\u{1F3A1}", grantSpin = true },

	-- A COUNTED CHARGE, not a moment. `grantBossRevives` adds to data.BossRevives and BossService
	-- spends one when there is something to restore; the receipt can therefore arrive late, on
	-- another server, or after a rejoin without the player losing what they paid for. That is not a
	-- nicety -- ProcessReceipt is retried on Roblox's own schedule and does a DataStore write before
	-- it acknowledges, so any design that had to land inside the 34 s heal window would have a tail
	-- of buyers who paid for nothing. Cheapest product in the shop on purpose: it is bought in a
	-- moment of frustration, and a frustrated player will not spend 199.
	--
	-- ===== AND IT IS WITHDRAWN (11.7), WITHOUT DELETING THE RECEIPT =====
	--
	-- `delisted` hides it from every shop surface. The ROW STAYS, and that is the whole point:
	-- ProcessReceipt is retried on Roblox's own schedule until it is acknowledged, so a purchase
	-- already in flight when this shipped -- or one made seconds before the place updated -- still
	-- arrives, and a receipt with no matching product row is a player charged for nothing, forever,
	-- with the retry never stopping. Deleting the row is the one change here that could actually
	-- take money and give nothing back.
	--
	-- `grantDiamonds` instead of `grantBossRevives`, because a charge for a feature whose UI is gone
	-- is worth nothing. 10 diamonds is exactly what Diamonds_1 sells for the same 49 R$, so an
	-- in-flight buyer is made whole at the shop's own rate rather than at a number invented here.
	-- **Turning off the sale on the Creator Dashboard is the owner half** -- see the checklist.
	{ key = "BossRevive",  productId = 3702254100, price = 49,  name = "Boss Revive",   emoji = "\u{2694}\u{FE0F}", grantDiamonds = 10, delisted = true },

	-- ===== THE RAINBOW CATALYST, AND WHY IT IS NOT WHAT THE ROADMAP ASKED FOR =====
	--
	-- ROADMAP 3.5 asked for a "Rainbow Fusion" product, "one tier above the existing Golden fusion".
	-- That premise is simply wrong about this game: PetTiers has run Normal / Golden / Rainbow /
	-- Celestial since long before this phase, GetNextTier has no gate in it, and PetService.HandleFuse
	-- refuses exactly two things -- being at Celestial already, and not holding four copies. A player
	-- with four Goldens gets a Rainbow today, free. Selling it would have been charging 199 R$ for
	-- something already shipped, which is the one thing the GamePasses block above refuses to do (see
	-- the note on auto-attack: sell the RATE, never the thing).
	--
	-- So the product sells the GRIND instead of the tier. The wall is not tier access, it is needing
	-- four identical copies of the same species AND tier: a Rainbow costs 16 Normals of one species
	-- end to end, a Celestial 64. A catalyst raises one owned pet one tier with no copies at all.
	--
	-- IT STOPS BELOW THE TOP. HandleTierUp refuses a step INTO Celestial, and that cap is doing real
	-- work rather than being decoration. Equipped pet bonuses MULTIPLY across slots (up to nine of
	-- them with the PetSlots3 pass), so an unbounded tier-up sold by the token is a compounding
	-- income multiplier priced like a consumable. Capped at Rainbow it sells the tedious middle of the
	-- ladder and leaves the ceiling as something only fusing can reach.
	--
	-- REPRICED AND RE-HOMED (11.7). 99/249 -> 49/129, and `panel = "fusion"` moves both cards out of
	-- the Robux grid and onto the fusion panel. The product ids are untouched -- a price on the
	-- Creator Dashboard is a separate field from the one below, and this number is only what the card
	-- prints; the dashboard is the owner's to match.
	--
	-- Selling it beside the grid was the mistake. A catalyst answers a question the player only has
	-- while looking at "(2/3)" under a pet they cannot fuse yet, and that question is asked on the
	-- fusion panel, not in a wall of currency packs. Cheaper too, because 11.7 also cut the fusion
	-- requirement to three: the grind it shortcuts is now 9 copies rather than 16, so the shortcut
	-- has to cost less than it did when it was worth more.
	--
	-- `panel` hides it from the grid; `panelCard` asks the fusion panel to draw a card of its own.
	-- ONLY THE BUNDLE GETS ONE. The single catalyst is already offered on **every pet row** in that
	-- panel -- that is what `CatalystRow`'s R$ button is -- so a second generic card selling the same
	-- thing two inches below would be the same product twice on one screen. The x3 has nowhere else
	-- to be, because a per-pet row is about one pet and a bundle is not.
	{ key = "TierUp_1", productId = 3702254553, price = 49,  tierGroup = "TierUp", panel = "fusion", name = "Rainbow Catalyst",  emoji = "\u{1F308}", grantTierUps = 1 },
	{ key = "TierUp_3", productId = 3702254989, price = 129, tierGroup = "TierUp", panel = "fusion", panelCard = true, name = "Catalyst x3", emoji = "\u{1F308}", grantTierUps = 3, ribbon = "BEST VALUE" },

	{ key = "Potions_3",   productId = 3702255918, price = 99,  name = "Potion Pack",   emoji = "🧪", grantPotions = 3, grantPotionId = "dna_m" },
	{ key = "Potions_10",  productId = 3702256409, price = 199, name = "Potion Crate",  emoji = "🧪", grantPotions = 4, grantPotionId = "dna_l" },
	-- The Season Pass premium track. `grantSeasonPremium` is read by RobuxShopService's
	-- ProcessReceipt; buying it late is safe, because every premium reward already reached stays
	-- claimable (see SeasonPassService.GrantPremium).
	{ key = "SeasonPremium", productId = 3702256841, price = 399, name = "Premium Season Pass", emoji = "\u{1F39F}\u{FE0F}", grantSeasonPremium = true },
}

function GameConfig.GetRobuxProduct(key)
	for _, p in ipairs(GameConfig.RobuxProducts) do
		if p.key == key then return p end
	end
	return nil
end

-- What one Robux buys on this product, in whatever unit the product pays out. Comparable only
-- WITHIN a tierGroup -- DNA against DNA, Diamonds against Diamonds -- which is exactly how the shop
-- uses it. Returns 0 for products that pay a flag rather than an amount (the Season Pass), so those
-- simply never draw a ribbon.
function GameConfig.GetValuePerRobux(product)
	if not product or not product.price or product.price <= 0 then return 0 end
	-- `grantShards` belongs in this list for the same reason every other grant does: the ribbon a tile
	-- prints is derived here, so a grant field missing from it makes its whole tier group silently
	-- ribbon-less -- which reads as "no bonus", not as "not implemented".
	local amount = product.grantDNA or product.grantDiamonds or product.grantShards
		or product.grantPotions or product.grantTierUps
	if not amount then return 0 end
	return amount / product.price
end

-- How much more this tier pays per Robux than the CHEAPEST tier in its group, as a percentage.
-- DERIVED, never authored: the shop's "+47% BONUS" ribbon comes from here, so the claim on the tile
-- and the numbers in the table cannot drift apart. Returns 0 for the base tier of a group and for
-- anything with no group at all.
function GameConfig.GetTierBonusPct(product)
	if not product or not product.tierGroup then return 0 end
	local base
	for _, p in ipairs(GameConfig.RobuxProducts) do
		if p.tierGroup == product.tierGroup then
			if not base or p.price < base.price then base = p end
		end
	end
	if not base or base == product then return 0 end
	local baseValue = GameConfig.GetValuePerRobux(base)
	if baseValue <= 0 then return 0 end
	return math.floor((GameConfig.GetValuePerRobux(product) / baseValue - 1) * 100 + 0.5)
end

-- THE ONE XP MULTIPLIER. The creature kill and the boss kill each called GetPotionMult(data, "xp")
-- directly, so the 2x XP pass would have had to be added in two places and kept in step with itself
-- forever -- and a third XP source added later would have quietly missed both. Everything that
-- scales XP goes through here now.
function GameConfig.GetXPMult(data)
	-- The event multiplier lands here too, and this is the extraction paying for itself a second
	-- time: the weekend's double XP reached the creature kill AND the boss kill by being written
	-- once, in the one function both of them already went through.
	return GameConfig.GetPotionMult(data, "xp") * GameConfig.GetPassMult(data, "xpMult")
		* GameConfig.GetEventMult("xpMult")
end

-- ===== GAME PASSES =====
-- One-off, permanent, account-wide Robux purchases -- as opposed to the consumable Developer
-- Products above.
--
-- THE IDS BELOW ARE REAL AS OF 2026-08-11. All nine were created against universe
-- **10675543038 ("Evolution Lab BETA V0.2")** and each one was put ON SALE at the price in its row
-- (a pass created without "Item for sale" enabled exists and has an id, but nobody can buy it --
-- that is the single easiest step to miss). Verified through the product-info endpoint: correct
-- name, correct price, `IsForSale = true` on all nine.
--
-- These are **Game Pass ids**, not asset ids. `UserOwnsGamePassAsync` takes the Game Pass id, and
-- an asset id pasted here would make the call return false forever with no error anywhere -- the
-- pass would simply never work for anyone who bought it.
--
-- `passId = 0` remains the "not set up yet" sentinel; PassService refuses to prompt on a zero id
-- rather than opening a dialog that cannot complete.
--
-- EVERY EFFECT IS A FIELD READ BY GetPassMult / GetPassAdd BELOW, never a special case at the call
-- site. That is what lets the 2x DNA pass and the VIP bundle both raise income without either hook
-- knowing the other exists, and it is why a tenth pass needs no new code anywhere -- only a row.
--
-- Three decisions worth not re-litigating:
--
-- 1. LUCK IS ADDITIVE, NOT A MULTIPLIER. Every other luck source in this game adds percentage
--    points (pet `luckAdd`, the Luck potion, the shop's Egg Luck upgrade at +5 a level) and luck
--    starts at ZERO. A "2x Luck" pass would therefore do literally nothing for a new player -- the
--    exact person most likely to buy it. See GameConfig.GetLuckPercent, which mutations, crit
--    chance, the mystery potion and the wheel all read, and GetPetLuckPercent beside it, which is
--    that total plus the shop upgrade and is what an egg rolls against.
--
-- 2. AUTO-ATTACK ITSELF STAYS FREE. It already ships free on the `AutoAttack` attribute and the T
--    key. Paywalling something players already have is the fastest way to lose them, so FastAuto
--    sells the swing RATE instead -- new value rather than confiscated value.
--
-- 3. ORDERED CHEAPEST FIRST, and the cheapest is deliberately a small quality-of-life pass. Across
--    the genre the entry pass is what converts a non-payer into a payer; the multipliers are where
--    the money actually is, but almost nobody buys one first.
GameConfig.GamePasses = {
	-- `walkCap` lifts GameConfig.MaxWalkSpeed for this player. Without it the pass is a lie for most
	-- of the game: the cap is 150, and an unbought stage-20 body already runs 127, so a 2x would have
	-- delivered 1.18x at the top and a true 2x only through stage 7 of 20. 260 covers the doubled
	-- top-stage speed (254.5) with a little headroom. The cap exists to stop a player outrunning
	-- StreamingEnabled, which is why lifting it is a deliberate, measured decision and not a default.
	{ key = "Speed2x",   passId = 1940815736, price = 99,  emoji = "🏃", name = "2x Speed",
	  desc = "Move twice as fast, in every zone.", walkMult = 2, walkCap = 260 },

	{ key = "XP2x",      passId = 1943659639, price = 149, emoji = "⭐", name = "2x XP",
	  desc = "Every kill fills the evolve bar twice as fast.", xpMult = 2 },

	{ key = "AutoHatch", passId = 1940215660, price = 149, emoji = "🥚", name = "Auto Hatch",
	  desc = "Eggs keep hatching while you stand at the stall.", autoHatch = true },

	{ key = "DNA2x",     passId = 1941325697, price = 199, emoji = "🧬", name = "2x DNA",
	  desc = "Double DNA from clicks, kills and idle income.", incomeMult = 2 },

	{ key = "Damage2x",  passId = 1941175630, price = 199, emoji = "⚔️", name = "2x Damage",
	  desc = "Hit twice as hard. Bosses die in half the swings.", damageMult = 2 },

	{ key = "FastAuto",  passId = 1941379666, price = 199, emoji = "⚡", name = "Fast Auto Attack",
	  desc = "Your auto attack swings 70% faster.", autoSpeedMult = 1.7 },

	{ key = "Lucky",     passId = 1940107710, price = 249, emoji = "🍀", name = "Lucky",
	  desc = "+50% Luck on every egg, pet and mutation roll.", luckAdd = 50 },

	{ key = "PetSlots3", passId = 1944156329, price = 299, emoji = "🐾", name = "+3 Pet Slots",
	  desc = "Equip three more pets at once.", petSlots = 3 },

	{ key = "VIP",       passId = 1941409673, price = 499, emoji = "👑", name = "VIP",
	  desc = "1.5x DNA and damage, +15% Luck, a golden aura, a chat tag and 5 Diamonds a day.",
	  incomeMult = 1.5, damageMult = 1.5, luckAdd = 15, dailyDiamonds = 5, vip = true },
}

function GameConfig.GetGamePass(key)
	for _, p in ipairs(GameConfig.GamePasses) do
		if p.key == key then return p end
	end
	return nil
end

-- `data.Passes` is a RUNTIME cache written by PassService on join and on purchase. It is never
-- trusted out of the save -- PlayerDataService clears it on load -- so a missing or empty table
-- means "owns nothing", which is the correct fail-closed answer when the ownership check could not
-- be completed. Reading it here rather than taking a `player` is the whole reason none of the stat
-- functions had to change signature: GetIncomeMult, GetLuckPercent, GetCombatDamage and
-- GetMaxEquippedPets all already take `data`.
function GameConfig.OwnsPass(data, key)
	return (data and data.Passes and data.Passes[key]) == true
end

-- Product of `field` across every owned pass, or 1 when none of them carries it. Multiplicative on
-- purpose: a player holding both 2x DNA and VIP gets 3x, which is the entire reason to own two.
function GameConfig.GetPassMult(data, field)
	if not (data and data.Passes) then return 1 end
	local mult = 1
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] then
			mult = mult * p[field]
		end
	end
	return mult
end

-- Highest `field` across every owned pass, or `fallback`. BEST-ONE-APPLIES, the same rule
-- GetMutationIncomeMult uses -- for a value that is a ceiling rather than a contribution, summing
-- two of them would be meaningless and multiplying them would be worse.
function GameConfig.GetPassMax(data, field, fallback)
	local best = fallback or 0
	if not (data and data.Passes) then return best end
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] and p[field] > best then
			best = p[field]
		end
	end
	return best
end

-- Sum of `field` across every owned pass, or 0. For the stats measured in points rather than in
-- factors -- luck and pet slots today.
function GameConfig.GetPassAdd(data, field)
	if not (data and data.Passes) then return 0 end
	local total = 0
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] then
			total = total + p[field]
		end
	end
	return total
end

-- ============================================================================
-- LIMITED-TIME EVENTS
-- ============================================================================
-- A window in time during which the rules are different for EVERYONE on the server at once. The
-- genre runs on these -- Grow a Garden and Steal a Brainrot are both driven by them -- and this
-- game had no concept anywhere in it of "right now is different from yesterday".
--
-- =========================================================================================
-- AN EVENT IS A FUNCTION OF THE CLOCK. IT IS NEVER A FIELD IN A SAVE.
-- =========================================================================================
-- Pass ownership is cached into `data.Passes` because it comes from a web call that can fail, so
-- the answer has to be kept somewhere. An event is arithmetic on a timestamp: it cannot fail, it
-- cannot disagree between two servers, and every reader works it out for itself without asking.
--
-- Storing it in a save would break at both ends of the window. A player online when it closes keeps
-- the boost until something remembers to refresh them, and a player who logged off inside the
-- window carries a stale multiplier into next week -- which is the free-pass bug `data.Passes` is
-- reset on every load to prevent, except that here there is nothing to reset because nothing was
-- ever written.
--
-- =========================================================================================
-- EVERY WINDOW IS UTC, AND THE `!` IS THE WHOLE FEATURE
-- =========================================================================================
-- `os.date("*t")` is the machine's local time; `os.date("!*t")` is UTC. A live Roblox server runs
-- UTC, so the two agree there and the mistake is invisible in production -- but a Studio session
-- runs on whatever the developer's machine says, and that is the only machine this ever gets tested
-- on. A weekend authored against local time starts two hours early here and on time in production:
-- it looks correct in exactly the place where it is wrong.
--
-- =========================================================================================
-- EFFECTS REUSE THE GAME PASS FIELD NAMES
-- =========================================================================================
-- `incomeMult`, `xpMult`, `damageMult`, `luckAdd` -- the same names GetPassMult and GetPassAdd
-- read. So DNAService.GetIncomeMult gained one line directly beneath its pass line and learned
-- nothing about what an event is, and a new effect is a field on both sides rather than a call site.
GameConfig.Weekday = { Sun = 1, Mon = 2, Tue = 3, Wed = 4, Thu = 5, Fri = 6, Sat = 7 }

local EVENT_DAY = 86400
local EVENT_WEEK = 7 * EVENT_DAY

local eventClockOffset = 0

-- THE ONE CLOCK EVERY WINDOW IN THIS SECTION IS MEASURED AGAINST.
--
-- On the server it is `os.time()` exactly -- a Roblox server's clock is UTC and authoritative, and
-- the offset stays 0 forever.
--
-- On a client it is the SERVER's clock, learned from the payload EventService publishes. A player
-- whose machine is set a day fast would otherwise be shown a weekend that is not running, count
-- down to the wrong minute, and conclude the HUD is lying when their DNA arrives at the normal
-- rate. The client never decides what is live; it is only told, and this is where it keeps the
-- answer.
--
-- It is also the single seam a test moves: shifting it forward makes a future window live without
-- editing an authored date, which is the only way to exercise a launch festival before the launch.
function GameConfig.SetEventClock(serverNow)
	eventClockOffset = (tonumber(serverNow) or os.time()) - os.time()
	return eventClockOffset
end

function GameConfig.GetEventClockOffset()
	return eventClockOffset
end

function GameConfig.EventNow()
	return os.time() + eventClockOffset
end

-- How far this machine's clock is from UTC at `at`, measured rather than assumed.
--
-- Roblox reads the table form of `os.time` as UTC, in which case this returns 0 and the correction
-- below is a no-op. Standard Lua reads it as local time, in which case this returns exactly the
-- offset needed to undo that. The same expression is right in both worlds, which is why it is a
-- measurement and not a branch -- a branch here would have to guess which host it is running on.
local function utcOffsetAt(at)
	local u = os.date("!*t", at)
	u.isdst = false
	return at - os.time(u)
end

-- {year, month, day, hour, min} read as UTC -> a timestamp. A plain number passes through, so a
-- window can be authored either way.
local function utcTimestamp(spec)
	if type(spec) == "number" then return spec end
	local naive = os.time({
		year = spec[1], month = spec[2], day = spec[3],
		hour = spec[4] or 0, min = spec[5] or 0, sec = 0,
	})
	return naive + utcOffsetAt(naive)
end
GameConfig.UtcTimestamp = utcTimestamp

-- ===== THE EVENTS =====
--
-- `recurring` = { wday, hour, hours } in UTC, repeating every week.
-- `fixed`     = { from = {y,m,d,h,mi}, to = {...} } in UTC, happening once.
--
-- WHY THE WEEKEND IS NOT DOUBLE DAMAGE. It doubles what an hour of play PAYS, and leaves how hard
-- a creature hits alone. Damage is the pacing of the game -- how many swings a zone takes is what
-- makes one zone feel different from the last -- and 2.12 already measured that a damage multiplier
-- mostly removes wasted swings anyway, because BOSS_MIN_HITS caps a single blow at a share of the
-- target's health. An event should make the grind worth more, not make it disappear.
--
-- The weekend runs from 00:00 UTC on Saturday for 48 hours. That is Friday evening to Sunday
-- evening in the Americas and the whole of Saturday and Sunday in Europe -- there is no single
-- window that is a weekend everywhere, and UTC is at least the one every server agrees on.
GameConfig.Events = {
	{
		key = "Weekend2x",
		name = "Weekend Rush",
		emoji = "\u{1F525}",
		blurb = "Double DNA and double XP for everyone",
		color = Color3.fromRGB(255, 138, 76),
		recurring = { wday = GameConfig.Weekday.Sat, hour = 0, hours = 48 },
		effects = { incomeMult = 2, xpMult = 2 },
		-- Priority 0 (the default) on purpose, and it is the LOWER of the two weekend events -- see
		-- the note over ColosseumClash for why the one that changes every week is the one that
		-- headlines the board.
	},
	-- ===== THE WEEKEND COLOSSEUM (12.13) =====
	--
	-- The same window as Weekend Rush, deliberately: the two are one weekend, not two occasions, and
	-- a player who logs in on Saturday should find everything on at once rather than learn a
	-- schedule. What it adds is the half the game had no event for -- the Colosseum giant, which is
	-- already the only thing on a timer and the only thing a whole server does together.
	--
	-- WHY IT IS NOT ANOTHER incomeMult. Weekend Rush already doubles what an hour of ordinary play
	-- pays. Stacking a second income multiplier on top of it makes the weekend worth 4x and the week
	-- worth nothing, which is how a two-day window stops being a bonus and becomes the only time
	-- worth playing. `bossMult` touches ONE payout -- the giant's DNA and diamonds -- so the reason
	-- to turn up is a specific fight rather than a blanket rate.
	--
	-- THE SKIN ROTATES, AND THAT IS THE ENTIRE RETENTION ARGUMENT. A permanent weekend hands out one
	-- skin forever, so the second weekend has nothing in it for anyone who came to the first. Four
	-- champions on a four-week cycle mean a returning player is looking at something they cannot
	-- have yet, and a collector has a reason to be here on a particular weekend rather than some
	-- weekend. See GameConfig.GetEventRewardKey for how the week is chosen.
	{
		key = "ColosseumClash",
		name = "Colosseum Clash",
		emoji = "\u{2694}\u{FE0F}",
		blurb = "Double giant loot, and this week's champion skin for everyone who shows up",
		color = Color3.fromRGB(226, 84, 76),
		recurring = { wday = GameConfig.Weekday.Sat, hour = 0, hours = 48 },
		effects = { bossMult = 2 },
		-- WHICH ONE HEADLINES WHEN BOTH ARE LIVE, decided here rather than left to table order.
		-- Every consumer of GetActiveEvents draws `active[1]` and only `active[1]` -- the sign, the
		-- HUD card and GetEventHeadline all do -- so without this the answer would be "whichever was
		-- authored first", which is not a decision anybody made. Weekend Rush is the same every
		-- weekend and every returning player already knows it; the Colosseum's champion is different
		-- this week and is the only thing on the board worth reading twice. The rate boost is not
		-- lost: the HUD card sums the effects of EVERY live event onto one line, and the sign names
		-- the co-runners under the blurb.
		priority = 10,
		-- One rotation entry per week, resolved from the WINDOW's start -- see GetEventRewardKey.
		rotation = {
			"event_clash_ember",
			"event_clash_frost",
			"event_clash_verdant",
			"event_clash_onyx",
		},
	},
	-- The launch festival, and the one event carrying an exclusive skin.
	--
	-- 👤 OWNER: these two dates are a DESIGN DECISION, not an id -- unlike a product or a pass there
	-- is nothing to paste from the dashboard, so they are authored here and are safe to edit. Set
	-- them to the real launch weekend before publishing. Nothing breaks if they stay: the window is
	-- simply in the past or the future, GetEventWindow says so, and no effect and no skin is handed
	-- out until the moment named below.
	{
		key = "PrismFest",
		name = "Prism Festival",
		emoji = "\u{1F308}",
		blurb = "+50% luck, and the Prism Herald skin for everyone who shows up",
		color = Color3.fromRGB(158, 120, 255),
		fixed = { from = { 2026, 9, 4, 12, 0 }, to = { 2026, 9, 7, 12, 0 } },
		effects = { luckAdd = 50 },
		-- Granted while the window is open and NEVER taken back -- see GameConfig.EventCharacters.
		reward = { characterKey = "event_prism" },
	},
}

-- What the HUD chip calls each multiplicative effect field. It lives here rather than in MainUI for
-- two reasons: MainUI is at Luau's 200-local ceiling and a new top-level table there costs the
-- whole HUD, and a new effect field is authored three lines up in GameConfig.Events -- so the
-- reader that would otherwise silently omit it is the one that should be edited in the same file.
-- `luckAdd` is deliberately absent: it is additive and is formatted as a percentage, not an "x".
GameConfig.EventEffectLabels = {
	incomeMult = "DNA",
	xpMult = "XP",
	damageMult = "Damage",
	bossMult = "Giant Loot",
}

function GameConfig.GetEvent(key)
	for _, event in ipairs(GameConfig.Events) do
		if event.key == key then return event end
	end
	return nil
end

-- The occurrence of `event` that matters at `now`: when it started (or starts), when it ends,
-- whether it is live, and when the next one begins if it is not. ONE SHAPE FOR BOTH KINDS OF
-- WINDOW, so nothing downstream ever branches on which sort of event it is holding.
function GameConfig.GetEventWindow(event, now)
	if not event then return nil end
	now = now or GameConfig.EventNow()

	if event.fixed then
		local startTs = utcTimestamp(event.fixed.from)
		local endTs = utcTimestamp(event.fixed.to)
		return {
			startTs = startTs,
			endTs = endTs,
			active = (now >= startTs and now < endTs),
			-- A one-off that has finished has NO next occurrence, and saying nil rather than a date
			-- is what lets the countdown board fall through to whatever is actually coming instead
			-- of counting down to something in the past.
			nextStart = (now < startTs) and startTs or nil,
		}
	end

	local r = event.recurring
	if not r then return nil end

	local t = os.date("!*t", now)
	local midnight = now - (t.hour * 3600 + t.min * 60 + t.sec)   -- 00:00 UTC today
	local startTs = midnight - ((t.wday - r.wday) % 7) * EVENT_DAY + (r.hour or 0) * 3600
	-- Today IS the day, but the hour has not come round yet: the occurrence that matters is last
	-- week's, which may or may not still be running. Without this line an event whose hour is later
	-- today reads as having started this morning.
	if startTs > now then startTs -= EVENT_WEEK end

	local endTs = startTs + (r.hours or 24) * 3600
	local active = (now < endTs)
	return {
		startTs = startTs,
		endTs = endTs,
		active = active,
		nextStart = (not active) and (startTs + EVENT_WEEK) or nil,
	}
end

-- Every event live at `now`, each paired with its own window so a caller that also wants the
-- countdown does not compute it a second time.
--
-- SORTED BY `priority`, HIGHEST FIRST, AND THAT IS A REAL DECISION RATHER THAN TIDINESS (12.13).
-- Three separate places draw `active[1]` and nothing else -- the sign in Forest, the HUD boost card
-- and GetEventHeadline -- so as soon as two windows can overlap, "which event IS the weekend" is
-- being answered by the order somebody happened to type the table in. It is answered here instead,
-- once, for all three.
--
-- The tie-break is the authored index, not the sort's own idea of equal elements: `table.sort` is
-- NOT stable in Lua, so two events at the same priority would otherwise swap places between calls
-- and the board would flip name every second. Ordinals make equal priorities keep table order.
function GameConfig.GetActiveEvents(now)
	now = now or GameConfig.EventNow()
	local out = {}
	for index, event in ipairs(GameConfig.Events) do
		local window = GameConfig.GetEventWindow(event, now)
		if window and window.active then
			table.insert(out, { event = event, window = window, order = index })
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = a.event.priority or 0, b.event.priority or 0
		if pa ~= pb then return pa > pb end
		return a.order < b.order
	end)
	return out
end

-- ===== WHICH SKIN THIS OCCURRENCE HANDS OVER =====
--
-- THE ONE PLACE THAT ANSWERS IT, for both shapes an event reward can take: a fixed `reward` (the
-- launch festival, which happens once and so has nothing to rotate) and a `rotation` list, which
-- picks one entry per week.
--
-- THE INDEX COMES OFF `window.startTs`, NEVER OFF `now`, and that is the whole correctness of it.
-- The Unix week boundary is a Thursday (the epoch was one), so a Saturday-to-Monday window does not
-- cross one today -- but nothing in this file guarantees the window stays where it is authored, and
-- an index taken from `now` silently changes the answer for a window that ever does cross a
-- boundary. A player online at that instant would watch the reward swap under them and be handed
-- two skins for one weekend; anyone who joined ten minutes later would get a different one from the
-- player standing beside them. Off `startTs` the whole occurrence agrees with itself by
-- construction, and the same window always resolves to the same skin however late it is asked.
function GameConfig.GetEventRewardKey(event, window)
	if not event then return nil end
	if event.reward and event.reward.characterKey then
		return event.reward.characterKey, nil
	end
	local rotation = event.rotation
	if not (rotation and #rotation > 0 and window and window.startTs) then return nil end
	local index = 1 + math.floor(window.startTs / EVENT_WEEK) % #rotation
	return rotation[index], index
end

-- Where a rotation skin sits relative to right now: which slot it is, whether it is the one
-- currently being handed out, and when its own turn next comes round. For the Journal, so an
-- unowned champion can say "three weeks away" instead of the generic "turn up while it is running",
-- which for a rotation is true of only one of the four at a time.
function GameConfig.GetRotationInfo(characterKey, now)
	if not characterKey then return nil end
	now = now or GameConfig.EventNow()
	for _, event in ipairs(GameConfig.Events) do
		local rotation = event.rotation
		if rotation then
			local slot
			for i, key in ipairs(rotation) do
				if key == characterKey then slot = i break end
			end
			if slot then
				local window = GameConfig.GetEventWindow(event, now)
				local currentKey = window and GameConfig.GetEventRewardKey(event, window) or nil
				-- Walk forward one occurrence at a time rather than solving for the week: the window
				-- arithmetic already knows where occurrences fall, and #rotation steps is at most four.
				local nextStart
				if currentKey ~= characterKey or not (window and window.active) then
					local probeStart = window and (window.active and window.startTs or window.nextStart)
					for _ = 1, #rotation + 1 do
						if not probeStart then break end
						if probeStart > now and GameConfig.GetEventRewardKey(event, { startTs = probeStart }) == characterKey then
							nextStart = probeStart
							break
						end
						probeStart += EVENT_WEEK
					end
				end
				return {
					event = event,
					slot = slot,
					count = #rotation,
					live = (window and window.active and currentKey == characterKey) or false,
					nextStart = nextStart,
				}
			end
		end
	end
	return nil
end

-- Everything that starts at the SOONEST moment anything starts, for the board to count down to when
-- nothing is on. Usually one event; two whenever two windows share an opening instant, which since
-- 12.13 is every week -- the Colosseum and the weekend both open at 00:00 Saturday.
--
-- SORTED BY PRIORITY LIKE GetActiveEvents, AND THAT IS A BUG FIX, NOT SYMMETRY FOR ITS OWN SAKE.
-- The old form kept the first event it found at the soonest start, i.e. authored order -- so on the
-- five days a week nothing is running, the sign counted down to "🔥 Weekend Rush" while the sign on
-- the weekend itself headlined "⚔️ Colosseum Clash". Same instant, same duration, two different
-- names, and the one a player reads while deciding whether to come back is the off-weekend one.
-- Measured on the live board before this was fixed.
function GameConfig.GetUpcomingEvents(now)
	now = now or GameConfig.EventNow()
	local soonest
	local out = {}
	for index, event in ipairs(GameConfig.Events) do
		local window = GameConfig.GetEventWindow(event, now)
		if window and window.nextStart then
			if not soonest or window.nextStart < soonest then
				soonest = window.nextStart
				out = {}
			end
			if window.nextStart == soonest then
				table.insert(out, { event = event, window = window, order = index })
			end
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = a.event.priority or 0, b.event.priority or 0
		if pa ~= pb then return pa > pb end
		return a.order < b.order
	end)
	return out
end

-- The one that headlines. Kept as its own function because every existing caller wants exactly this.
function GameConfig.GetNextEvent(now)
	return GameConfig.GetUpcomingEvents(now)[1]
end

-- The product of `field` across every live event, or 1 so a caller can multiply unconditionally.
--
-- IT TAKES NO `data`, AND THAT IS THE DIFFERENCE BETWEEN AN EVENT AND A PASS IN ONE LINE: an event
-- is the same for everybody on the server, so there is nothing about a player it could depend on.
function GameConfig.GetEventMult(field, now)
	local mult = 1
	for _, live in ipairs(GameConfig.GetActiveEvents(now)) do
		local value = live.event.effects and live.event.effects[field]
		if type(value) == "number" then mult *= value end
	end
	return mult
end

-- Additive points, for luck -- the one stat in this game every source adds to rather than scales.
function GameConfig.GetEventAdd(field, now)
	local add = 0
	for _, live in ipairs(GameConfig.GetActiveEvents(now)) do
		local value = live.event.effects and live.event.effects[field]
		if type(value) == "number" then add += value end
	end
	return add
end

-- "2d 4h" / "5h 12m" / "48m 09s" / "30s". Shared by the countdown board and the HUD chip so the two
-- can never disagree about how long is left.
function GameConfig.FormatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local d = math.floor(seconds / EVENT_DAY)
	local h = math.floor((seconds % EVENT_DAY) / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	if m > 0 then return ("%dm %02ds"):format(m, s) end
	return ("%ds"):format(s)
end

-- One line for the HUD and the board: what is running and how long is left, or what is next.
-- Returns nil when there is neither, which is a state the board draws rather than hides.
function GameConfig.GetEventHeadline(now)
	now = now or GameConfig.EventNow()
	local active = GameConfig.GetActiveEvents(now)
	if #active > 0 then
		local live = active[1]
		return {
			event = live.event,
			live = true,
			seconds = live.window.endTs - now,
			text = ("%s  %s"):format(live.event.emoji, GameConfig.FormatDuration(live.window.endTs - now)),
		}
	end
	local upcoming = GameConfig.GetNextEvent(now)
	if upcoming then
		return {
			event = upcoming.event,
			live = false,
			seconds = upcoming.window.nextStart - now,
			text = ("%s  in %s"):format(upcoming.event.emoji,
				GameConfig.FormatDuration(upcoming.window.nextStart - now)),
		}
	end
	return nil
end

-- ============================================================================
-- SEASON PASS
-- ============================================================================
-- A thirty-level track that fills with Season XP, and Season XP comes from ONE place: completing
-- daily and weekly quests. Nothing else pays it. That is the whole design -- the pass is the
-- reason to come back tomorrow, and the quests are the reason to play today.
--
-- Two rows of rewards per level, exactly like the board this is modelled on: a FREE row everybody
-- collects, and a PREMIUM row that unlocks in one purchase and pays out retroactively for every
-- level already reached.
--
-- `id` is the reset switch. Bump it and every player's progress, claims and premium flag start
-- over on their next join -- see SeasonPassService, which migrates lazily rather than needing a
-- scheduled job or a live server at the moment a season turns over.
GameConfig.Season = {
	-- `id` and `name` USED TO LIVE HERE and are derived now -- see GetCurrentSeason below (7.3).
	-- What is left in this table is the SHAPE of a pass, which every season shares. The emoji is
	-- the fallback for a caller that wants a season marker without asking which season it is.
	emoji = "\u{1F39F}\u{FE0F}",
	maxLevel = 30,
	-- flat, not a curve. A rising per-level cost makes the back half of a pass feel like a wall,
	-- and the quests already scale the income side.
	xpPerLevel = 1500,
}

-- ===== THE SEASON TURNS OVER ON ITS OWN (7.3) =====
--
-- `Season.id` used to be a hand-edited string, and the comment above said "bump it and every
-- player's progress starts over". That is a live-ops job nobody can do at 3am on the day it is due,
-- and a season that only rotates when somebody remembers is not a season -- it is a permanent pass
-- with an optimistic name.
--
-- It is derived from the clock instead, exactly like an event window, and for exactly the same
-- reasons: two servers cannot disagree, a restart cannot lose it, and there is no scheduled job to
-- miss. SeasonPassService already resets LAZILY off a mismatch in this id, so making the id a
-- function of the date is the entire feature -- that file's reset logic did not change at all.
--
-- THE EPOCH IS CHOSEN SO THAT TODAY IS STILL SEASON 1, and the id it generates for the first
-- season is the string "S1" -- byte for byte what every existing save already holds. So this update
-- rotates nothing: no player loses the pass progress they had when it shipped. Getting that wrong
-- is a wipe, not a bug report.
--
-- THEMES CYCLE, NUMBERS DO NOT. Season 7 is "Season 7: <the 7th theme>", and once the list is
-- exhausted it starts round again while the number keeps climbing -- so the table never runs out
-- and no season is ever nameless. Add a row and the rotation is longer; nothing else changes.
GameConfig.SeasonEpoch = { 2026, 8, 1, 0, 0 }   -- UTC, the moment Season 1 opened
GameConfig.SeasonLengthDays = 30

GameConfig.SeasonThemes = {
	{ name = "First Light",    emoji = "\u{1F39F}\u{FE0F}" },
	{ name = "Deep Currents",  emoji = "\u{1F30A}" },
	{ name = "Ashfall",        emoji = "\u{1F30B}" },
	{ name = "Frostbloom",     emoji = "\u{2744}\u{FE0F}" },
	{ name = "Starfall",       emoji = "\u{1F320}" },
	{ name = "Overgrowth",     emoji = "\u{1F33F}" },
}

-- The season `now` falls in. Everything about it is generated, so there is no list to keep in step
-- with the calendar and no season that can be reached before someone has written it down.
function GameConfig.GetCurrentSeason(now)
	now = now or GameConfig.EventNow()
	local epoch = GameConfig.UtcTimestamp(GameConfig.SeasonEpoch)
	local length = GameConfig.SeasonLengthDays * 86400
	-- clamped at 1: a clock reading before the epoch is a broken clock, not season zero, and it
	-- must not produce an id no save has ever seen
	local index = math.max(1, math.floor((now - epoch) / length) + 1)
	local startTs = epoch + (index - 1) * length
	local theme = GameConfig.SeasonThemes[((index - 1) % #GameConfig.SeasonThemes) + 1]
	return {
		index = index,
		id = "S" .. index,
		name = ("Season %d: %s"):format(index, theme.name),
		emoji = theme.emoji,
		startTs = startTs,
		endTs = startTs + length,
		secondsLeft = math.max(0, startTs + length - now),
	}
end

-- Level from total XP. Level 1 is the floor -- a pass at 0 XP is "Level 1, 0/1500", never level 0.
function GameConfig.GetSeasonLevel(xp)
	local level = 1 + math.floor((xp or 0) / GameConfig.Season.xpPerLevel)
	return math.min(level, GameConfig.Season.maxLevel)
end

-- XP into the current level, and how much that level needs. At max level both are the same
-- number, so the bar reads full instead of dividing by a level that does not exist.
function GameConfig.GetSeasonLevelProgress(xp)
	xp = xp or 0
	local per = GameConfig.Season.xpPerLevel
	if GameConfig.GetSeasonLevel(xp) >= GameConfig.Season.maxLevel then
		return per, per
	end
	return xp % per, per
end

-- The thirty rows, generated rather than hand-typed for the same reason the eggs are: thirty
-- literal tables drift the moment one number in the ramp changes.
--
-- DNA is the filler and is deliberately the WEAKEST part of the reward -- income scales so hard
-- across twenty stages that any fixed DNA figure is either trivial or game-breaking depending on
-- who reads it. The things worth having are the ones the economy cannot inflate: potions,
-- Diamonds and Evolution Shards.
GameConfig.SeasonRewards = {}
do
	local POTION_BY_BAND = { "dna_s", "xp_s", "luck_m", "dna_m", "xp_m", "luck_l" }
	for level = 1, GameConfig.Season.maxLevel do
		local band = math.min(math.ceil(level / 5), #POTION_BY_BAND)
		local dna = math.floor(400 * (1.95 ^ (level - 1)))

		local free = { dna = dna }
		-- one bottle every fourth level, and a Diamond payout at each of the three round numbers
		if level % 4 == 0 then
			free.potions, free.potionId = 1, POTION_BY_BAND[band]
		end
		if level == 10 then free.diamonds = 2 end
		if level == 20 then free.diamonds = 3 end
		if level == 30 then free.diamonds = 5 end

		-- Premium is the same shape, three times the DNA, a bottle twice as often, Diamonds every
		-- fifth level and the only Shards on the board.
		local premium = { dna = dna * 3 }
		if level % 2 == 0 then
			premium.potions, premium.potionId = 2, POTION_BY_BAND[band]
		end
		if level % 5 == 0 then premium.diamonds = 3 + math.floor(level / 5) end
		if level == 15 then premium.shards = 5 end
		if level == 30 then premium.shards = 15 end

		GameConfig.SeasonRewards[level] = {
			level = level,
			free = free,
			premium = premium,
			-- every tenth level is drawn bigger on the track
			milestone = (level % 10 == 0),
		}
	end
end

function GameConfig.GetSeasonReward(level)
	return GameConfig.SeasonRewards[level]
end

-- ===== QUESTS =====
-- Every player gets the SAME list every period. No random draw and no per-player seed to store:
-- a rolled quest board means somebody opens the panel to three tasks they cannot do from where
-- they are standing, and it makes the save a great deal more fragile for nothing.
--
-- `counter` is the name SeasonPassService.Track is called with. All four already happen on paths
-- that write to the save anyway -- a creature dying, a boss falling, an egg hatching, a fusion --
-- so tracking costs no new events and no extra replication.
GameConfig.QuestPool = {
	daily = {
		{ key = "d_creatures", counter = "creatures", target = 50, emoji = "\u{2694}\u{FE0F}", name = "Defeat 50 creatures",   xp = 250 },
		{ key = "d_eggs",      counter = "eggs",      target = 10, emoji = "\u{1F95A}",        name = "Hatch 10 eggs",          xp = 300 },
		{ key = "d_bosses",    counter = "bosses",    target = 3,  emoji = "\u{1F451}",        name = "Defeat 3 bosses",        xp = 350 },
		{ key = "d_fuse",      counter = "fuse",      target = 2,  emoji = "\u{1F9EC}",        name = "Fuse 2 pets",            xp = 200 },
	},
	weekly = {
		{ key = "w_creatures", counter = "creatures", target = 500, emoji = "\u{2694}\u{FE0F}", name = "Defeat 500 creatures", xp = 1200, diamonds = 2 },
		{ key = "w_bosses",    counter = "bosses",    target = 20,  emoji = "\u{1F451}",        name = "Defeat 20 bosses",    xp = 1500, diamonds = 3 },
		{ key = "w_eggs",      counter = "eggs",      target = 60,  emoji = "\u{1F95A}",        name = "Hatch 60 eggs",       xp = 1400, diamonds = 2 },
	},
}

GameConfig.QuestPeriods = {
	-- Bucket arithmetic, not a stored timer: the period a moment belongs to is a pure function of
	-- the clock, so a reset needs no live server and cannot be missed by a player who was offline
	-- when it happened. (The Unix epoch was a Thursday, so the weekly bucket turns over on a
	-- Thursday at 00:00 UTC.)
	daily  = { seconds = 86400,  label = "Daily",  emoji = "\u{2600}\u{FE0F}" },
	weekly = { seconds = 604800, label = "Weekly", emoji = "\u{1F4C5}" },
}

function GameConfig.GetQuests(period)
	return GameConfig.QuestPool[period] or {}
end

function GameConfig.GetQuestPeriodId(period, now)
	local def = GameConfig.QuestPeriods[period]
	if not def then return 0 end
	return math.floor((now or os.time()) / def.seconds)
end

-- When the current period rolls over, as a unix timestamp -- the countdown the panel prints.
function GameConfig.GetQuestPeriodEnd(period, now)
	local def = GameConfig.QuestPeriods[period]
	if not def then return 0 end
	return (GameConfig.GetQuestPeriodId(period, now) + 1) * def.seconds
end

function GameConfig.GetQuestDef(period, questKey)
	for _, q in ipairs(GameConfig.GetQuests(period)) do
		if q.key == questKey then return q end
	end
	return nil
end

-- ===== HELPER FUNCTIONS =====

-- A FIXED DNA REWARD IS MEANINGLESS IN AN ECONOMY THAT SPANS 1e2 TO 1e17.
--
-- The daily login track tops out at 23,000 DNA and the playtime ladder at 35,000. One Mars
-- creature pays 24,150 -- so from stage 6, about fifteen minutes in, the ENTIRE seven-day login
-- cycle is worth less than a single kill, and every login reward after that is a rounding error
-- dressed up as a prize. The Season track has the opposite half of the same problem: its early
-- levels hand a brand-new player one or two whole stages instantly, and its level-30 payout is
-- 0.003 of one creature by the time anyone reaches it.
--
-- The authored numbers are not wrong -- they are a well-shaped ladder AT STAGE ONE, and each
-- reward's size relative to the others is the design. What is missing is the same growth curve
-- everything else in the game is on. So the authored figure is read as "how many stage-1 clicks
-- this is worth" and converted to what that is worth where the player actually stands.
--
-- Scaled RELATIVE TO STAGE ONE, which is what the tables were authored against: at stage 1 the
-- multiplier is exactly 1 and every reward pays precisely what its card says, and from there it
-- rides the same GetClickBase curve the rest of the income does. A reward is therefore worth the
-- same number of KILLS at stage 20 as it was at stage 1, which is the property that was missing.
--
-- A square root was tried first and is wrong: it decays against the curve it is meant to follow,
-- so the day-7 login still fell from 1,681 kills to 0.1 across the twenty stages -- a smaller
-- version of the same bug rather than a fix for it.
--
-- Floored at 1 so nothing can ever pay LESS than it says on the card.
function GameConfig.ScaleReward(amount, data)
	local stageIndex = (data and data.StageIndex) or 1
	local mult = math.max(GameConfig.GetClickBase(stageIndex) / GameConfig.GetClickBase(1), 1)
	return math.floor((amount or 0) * mult)
end

-- WHAT THE SPEED UPGRADE DOES. Until this existed: nothing.
--
-- `Speed` is the cheapest upgrade in the game (25 DNA) and the first one in the shop's order, so
-- it is the first purchase almost every new player makes -- and no line anywhere in the game ever
-- read `data.Upgrades.Speed`. The level went up, the cost went up, and the character moved at
-- exactly the same pace. The first thing a player buys cannot be the thing that teaches them
-- buying does nothing.
--
-- Flat studs per level rather than a multiplier: it is applied BEFORE the body-size multiplier in
-- EvolutionVisuals.applyMastery, so a level bought at Cell is worth proportionally more later,
-- which is the same shape every other early upgrade in this game has.
GameConfig.SpeedPerLevel = 1.5

function GameConfig.GetSpeedUpgradeBonus(data)
	local level = data and data.Upgrades and data.Upgrades.Speed or 0
	return level * GameConfig.SpeedPerLevel
end

-- ===== UPGRADES ARE CAPPED BY HOW FAR YOU HAVE ACTUALLY GOT =====
--
-- Five levels per unlocked zone (owner's decision, 2026-08-11): 5 at the start, 100 with all twenty
-- zones open. Before this there was **no ceiling at all** -- not in the price function, which had no
-- cap path unlike the Diamond upgrades, and not in `HandleBuyUpgrade`, which checked only that the
-- key existed and that the player could pay. A player who parked in zone 1 could buy Speed to
-- level 400 and outrun the entire progression the zones are supposed to gate.
--
-- Tied to ZONES rather than to stage or rebirth because a zone is the thing the player visibly
-- earns and can count, and it is already the gate on every other kind of power in the game.
GameConfig.UpgradeLevelsPerZone = 5

function GameConfig.GetUpgradeMaxLevel(data)
	local zones = (data and data.UnlockedZones) and #data.UnlockedZones or 1
	return math.max(zones, 1) * GameConfig.UpgradeLevelsPerZone
end

-- `data` is optional: without it this is the raw price of the next level, which is what a tool or a
-- test wants. With it, a level at or past the cap costs `math.huge` -- the same sentinel the Diamond
-- upgrades already use for a maxed row, so every "can I afford it" check in the game refuses it for
-- free without a single new branch.
function GameConfig.GetUpgradeCost(upgradeKey, currentLevel, data)
	local def = GameConfig.Upgrades[upgradeKey]
	if not def then return math.huge end
	if data and currentLevel >= GameConfig.GetUpgradeMaxLevel(data) then
		return math.huge
	end
	return math.floor(def.baseCost * (def.costMult ^ currentLevel))
end

function GameConfig.RollMutation(luckPercent)
	-- luckPercent: 0 = base, higher = better odds for rare mutations
	local totalWeight = 0
	local weights = {}
	for i, m in ipairs(GameConfig.Mutations) do
		-- luck boosts rarer (later) entries more
		local boost = 1 + (luckPercent / 100) * (i - 1) * 0.5
		local w = m.weight * boost
		weights[i] = w
		totalWeight = totalWeight + w
	end
	local roll = math.random() * totalWeight
	local acc = 0
	for i, w in ipairs(weights) do
		acc = acc + w
		if roll <= acc then
			return GameConfig.Mutations[i]
		end
	end
	return GameConfig.Mutations[1]
end

-- ===== THE DNA SPLICER (Phase 12) =====
-- The machine on the Forest plaza that mutations are rolled at, and DNA's late-game sink.
--
-- PRICED IN KILLS, NOT THROUGH ScaleReward. ScaleReward grows 2.85x a stage while real
-- per-kill income grows ~5x (the click base times the zone income bonus times mobDnaMult --
-- the same product the income-curve comment above GetClickBase says to verify against), so a
-- ScaleReward-priced roll would get ~44% cheaper IN KILLS every stage and be free by stage 20.
-- Costing the roll as a multiple of the player's own per-kill income keeps it the same number
-- of kills at every stage, which is the property a sink has to have.
--
-- The ramp is per LIFETIME roll (`data.SplicerRolls`) and is deliberately NOT reset by a
-- rebirth -- a reset would turn rebirth into a cost-reset coupon: roll 1 is ~5 kills at any
-- stage, roll 25 is ~49, and from roll ~56 the cap holds every further roll at a flat 1,000
-- kills -- 45-90 minutes of active play per roll, forever. At stage 20 that is ~1.1e17 DNA a
-- roll, 12x the most expensive egg, against an endgame balance of roughly 1e18.
GameConfig.Splicer = {
	baseKills = 5,        -- roll 1, in kills of the player's newest zone
	ramp = 1.10,          -- per lifetime roll
	rampCap = 200,        -- ramp^n stops here: baseKills * 200 = 1,000 kills a roll
	pityEvery = 10,       -- every Nth lifetime roll is "charged"...
	pityMinIndex = 2,     -- ...guaranteed at least Mutations[2] (Rare)...
	pityLuckAdd = 150,    -- ...and rolled with this much extra luck
	luckScale = 0.25,     -- fraction of GetLuckPercent that reaches RollMutation
	luckCap = 400,        -- luck points considered before scaling
	announceMinIndex = 5, -- Mutations[5]+ (Mythic, Secret, Godly) go server-wide
}

-- Pure over `data` for the same reason GetPetLuckPercent is: the client panel must quote the
-- price the server will charge, and two implementations would drift. `4.5` is the same tier
-- constant the income-curve comment uses -- an average kill against the Forest-baseline mix.
-- The newest unlocked zone is found by index, not by #UnlockedZones, so a save whose list is
-- ever out of order still prices against the furthest zone it has actually opened.
function GameConfig.GetSplicerRollCost(data)
	local stageIndex = (data and data.StageIndex) or 1
	local zoneKeys = (data and data.UnlockedZones) or { "Forest" }
	local zi = 1
	for _, k in ipairs(zoneKeys) do
		local i = GameConfig.GetZoneIndex(k)
		if i > zi then zi = i end
	end
	local zone = GameConfig.Zones[zi] or GameConfig.Zones[1]
	local perKill = GameConfig.GetClickBase(stageIndex)
		* (1 + GameConfig.GetTotalZoneBonusPct(zoneKeys) / 100)
		* 4.5 * (zone.mobDnaMult or 1)
	local S = GameConfig.Splicer
	local ramp = math.min(S.ramp ^ ((data and data.SplicerRolls) or 0), S.rampCap)
	return math.max(math.ceil(perKill * S.baseKills * ramp), 1)
end

-- The luck a Splicer roll is made with -- shared by the server handler and the client's odds
-- table, again so the promise and the roll cannot drift. `charged` is "this is the pity roll";
-- the caller decides that from `SplicerRolls`, because the SERVER increments the counter and
-- the client only predicts it.
function GameConfig.GetSplicerLuck(data, charged)
	local S = GameConfig.Splicer
	local luck = math.min(GameConfig.GetLuckPercent(data), S.luckCap) * S.luckScale
	if charged then luck += S.pityLuckAdd end
	return luck
end

-- ===== STAGE CHARACTERS =======================================================
-- TEN characters for every one of the twenty stages -- two hundred in all -- so "what am I" stops
-- being one fixed look per stage and becomes something collected. (It was five a stage; the second
-- five of each are in the block at the bottom of the table, on the same rarity spread.)
--
-- The axis is deliberately the SAME rarity ladder the pets use (Common .. Legendary, and the same
-- weights), because a player already knows what those five words mean and what the colours are.
-- What it is NOT is a power axis: a character is a skin. Two players at Void Sovereign hit exactly
-- as hard as each other whichever one they are wearing. Making the rarest look also the strongest
-- would mean the twenty evolve steps -- the actual progression -- stop deciding anything.
--
-- How one is obtained: every time you EVOLVE INTO a stage you roll one of that stage's five. A
-- stage reached again after a Rebirth rolls again, so the collection fills in over repeat runs
-- rather than being finished the first time through. See DNAService.HandleEvolve.
--
-- `color` is what StageCostume paints the body with, replacing the stage's own single colour.
-- Everything else about the costume -- the ears, the visor, the wings -- is the stage's, so a
-- Cinder Wolf and a Frost Wolf are unmistakably both Wolves.
GameConfig.StageCharacters = {
	-- 1 CELL
	{ stage = 1, key = "cell_speck",     name = "Speck",          emoji = "\u{1F535}", rarity = "Common",    color = Color3.fromRGB(180, 240, 180) },
	{ stage = 1, key = "cell_amber",     name = "Amber Blob",     emoji = "\u{1F7E1}", rarity = "Uncommon",  color = Color3.fromRGB(248, 226, 128) },
	{ stage = 1, key = "cell_azure",     name = "Azure Spore",    emoji = "\u{1F4A0}", rarity = "Rare",      color = Color3.fromRGB(132, 214, 255) },
	{ stage = 1, key = "cell_violet",    name = "Violet Mote",    emoji = "\u{1F7E3}", rarity = "Epic",      color = Color3.fromRGB(196, 142, 255) },
	{ stage = 1, key = "cell_prime",     name = "Prime Seed",     emoji = "\u{2728}", rarity = "Legendary", color = Color3.fromRGB(255, 226, 130) },
	-- 2 BACTERIA
	{ stage = 2, key = "bact_rod",       name = "Rodling",        emoji = "\u{1F9A0}", rarity = "Common",    color = Color3.fromRGB(168, 220, 150) },
	{ stage = 2, key = "bact_coil",      name = "Coilspore",      emoji = "\u{1F300}", rarity = "Uncommon",  color = Color3.fromRGB(126, 214, 186) },
	{ stage = 2, key = "bact_toxin",     name = "Toxinlash",      emoji = "\u{2623}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(158, 232, 96) },
	{ stage = 2, key = "bact_plague",    name = "Plaguebloom",    emoji = "\u{1F9EA}", rarity = "Epic",      color = Color3.fromRGB(186, 120, 232) },
	{ stage = 2, key = "bact_ancient",   name = "Ancient Strain", emoji = "\u{1F31F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 108) },
	-- 3 WORM
	{ stage = 3, key = "worm_soil",      name = "Soilcrawl",      emoji = "\u{1FAB1}", rarity = "Common",    color = Color3.fromRGB(206, 152, 128) },
	{ stage = 3, key = "worm_glow",      name = "Glowgut",        emoji = "\u{1F41B}", rarity = "Uncommon",  color = Color3.fromRGB(160, 232, 148) },
	{ stage = 3, key = "worm_iron",      name = "Ironring",       emoji = "\u{2699}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(150, 170, 196) },
	{ stage = 3, key = "worm_bore",      name = "Deepbore",       emoji = "\u{1F573}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(178, 128, 240) },
	{ stage = 3, key = "worm_devour",    name = "Devourer Grub",  emoji = "\u{1F396}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 190, 96) },
	-- 4 LIZARD
	{ stage = 4, key = "liz_sand",       name = "Sandscale",      emoji = "\u{1F98E}", rarity = "Common",    color = Color3.fromRGB(214, 190, 132) },
	{ stage = 4, key = "liz_moss",       name = "Mossback",       emoji = "\u{1F33F}", rarity = "Uncommon",  color = Color3.fromRGB(118, 190, 108) },
	{ stage = 4, key = "liz_ember",      name = "Emberfrill",     emoji = "\u{1F525}", rarity = "Rare",      color = Color3.fromRGB(244, 132, 78) },
	{ stage = 4, key = "liz_storm",      name = "Stormtongue",    emoji = "\u{26A1}", rarity = "Epic",      color = Color3.fromRGB(140, 176, 255) },
	{ stage = 4, key = "liz_basilisk",   name = "Basilisk",       emoji = "\u{1F409}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 112) },
	-- 5 WOLF
	{ stage = 5, key = "wolf_grey",      name = "Greyfang",       emoji = "\u{1F43A}", rarity = "Common",    color = Color3.fromRGB(168, 172, 184) },
	{ stage = 5, key = "wolf_timber",    name = "Timberpelt",     emoji = "\u{1F332}", rarity = "Uncommon",  color = Color3.fromRGB(158, 128, 96) },
	{ stage = 5, key = "wolf_frost",     name = "Frostmane",      emoji = "\u{2744}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(196, 232, 255) },
	{ stage = 5, key = "wolf_cinder",    name = "Cinderhowl",     emoji = "\u{1F525}", rarity = "Epic",      color = Color3.fromRGB(238, 118, 92) },
	{ stage = 5, key = "wolf_moon",      name = "Moonwarden",     emoji = "\u{1F319}", rarity = "Legendary", color = Color3.fromRGB(255, 232, 168) },
	-- 6 GORILLA
	{ stage = 6, key = "gor_ash",        name = "Ashknuckle",     emoji = "\u{1F98D}", rarity = "Common",    color = Color3.fromRGB(150, 142, 138) },
	{ stage = 6, key = "gor_jungle",     name = "Junglebrow",     emoji = "\u{1F33F}", rarity = "Uncommon",  color = Color3.fromRGB(110, 156, 100) },
	{ stage = 6, key = "gor_silver",     name = "Silverback",     emoji = "\u{1F948}", rarity = "Rare",      color = Color3.fromRGB(206, 212, 224) },
	{ stage = 6, key = "gor_thunder",    name = "Thunderfist",    emoji = "\u{1F44A}", rarity = "Epic",      color = Color3.fromRGB(150, 154, 248) },
	{ stage = 6, key = "gor_titan",      name = "Titan Ape",      emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 202, 96) },
	-- 7 HUMAN
	{ stage = 7, key = "hum_wander",     name = "Wanderer",       emoji = "\u{1F9CD}", rarity = "Common",    color = Color3.fromRGB(214, 190, 168) },
	{ stage = 7, key = "hum_scout",      name = "Scout",          emoji = "\u{1F9ED}", rarity = "Uncommon",  color = Color3.fromRGB(140, 196, 156) },
	{ stage = 7, key = "hum_scholar",    name = "Scholar",        emoji = "\u{1F4DA}", rarity = "Rare",      color = Color3.fromRGB(132, 172, 232) },
	{ stage = 7, key = "hum_champion",   name = "Champion",       emoji = "\u{2694}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(196, 140, 244) },
	{ stage = 7, key = "hum_ascendant",  name = "Ascendant",      emoji = "\u{1F31F}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 140) },
	-- 8 CYBORG
	{ stage = 8, key = "cyb_rust",       name = "Rustframe",      emoji = "\u{1F529}", rarity = "Common",    color = Color3.fromRGB(180, 150, 126) },
	{ stage = 8, key = "cyb_chrome",     name = "Chromeshell",    emoji = "\u{1F916}", rarity = "Uncommon",  color = Color3.fromRGB(196, 204, 216) },
	{ stage = 8, key = "cyb_neon",       name = "Neondrive",      emoji = "\u{1F4A1}", rarity = "Rare",      color = Color3.fromRGB(96, 226, 255) },
	{ stage = 8, key = "cyb_reactor",    name = "Reactorcore",    emoji = "\u{2622}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(176, 128, 255) },
	{ stage = 8, key = "cyb_singular",   name = "Singular Unit",  emoji = "\u{1F52E}", rarity = "Legendary", color = Color3.fromRGB(255, 212, 118) },
	-- 9 ALIEN
	{ stage = 9, key = "ali_grey",       name = "Grey Visitor",   emoji = "\u{1F47D}", rarity = "Common",    color = Color3.fromRGB(186, 200, 190) },
	{ stage = 9, key = "ali_verdant",    name = "Verdant Scout",  emoji = "\u{1F6F8}", rarity = "Uncommon",  color = Color3.fromRGB(126, 224, 158) },
	{ stage = 9, key = "ali_hive",       name = "Hive Envoy",     emoji = "\u{1F41D}", rarity = "Rare",      color = Color3.fromRGB(120, 186, 255) },
	{ stage = 9, key = "ali_psion",      name = "Psion",          emoji = "\u{1F300}", rarity = "Epic",      color = Color3.fromRGB(198, 128, 255) },
	{ stage = 9, key = "ali_progenitor", name = "Progenitor",     emoji = "\u{1F441}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 124) },
	-- 10 COSMIC BEING
	{ stage = 10, key = "cos_dust",      name = "Dustform",       emoji = "\u{1F30C}", rarity = "Common",    color = Color3.fromRGB(178, 186, 216) },
	{ stage = 10, key = "cos_comet",     name = "Cometborn",      emoji = "\u{2604}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(132, 216, 232) },
	{ stage = 10, key = "cos_pulsar",    name = "Pulsarheart",    emoji = "\u{1F4AB}", rarity = "Rare",      color = Color3.fromRGB(126, 176, 255) },
	{ stage = 10, key = "cos_quasar",    name = "Quasarborn",     emoji = "\u{1F52E}", rarity = "Epic",      color = Color3.fromRGB(200, 132, 255) },
	{ stage = 10, key = "cos_sunforged", name = "Sunforged",      emoji = "\u{2600}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 216, 118) },
	-- 11 UNIVERSE GOD
	{ stage = 11, key = "ugod_warden",   name = "Warden",         emoji = "\u{1F30C}", rarity = "Common",    color = Color3.fromRGB(170, 178, 220) },
	{ stage = 11, key = "ugod_shaper",   name = "Shaper",         emoji = "\u{1FA90}", rarity = "Uncommon",  color = Color3.fromRGB(136, 214, 200) },
	{ stage = 11, key = "ugod_arbiter",  name = "Arbiter",        emoji = "\u{2696}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(122, 172, 255) },
	{ stage = 11, key = "ugod_creator",  name = "Creator",        emoji = "\u{1F31F}", rarity = "Epic",      color = Color3.fromRGB(204, 138, 255) },
	{ stage = 11, key = "ugod_allfather", name = "All-Maker",     emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 220, 128) },
	-- 12 STAR WEAVER
	{ stage = 12, key = "swv_thread",    name = "Threadling",     emoji = "\u{1F578}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(190, 190, 214) },
	{ stage = 12, key = "swv_loom",      name = "Loomtender",     emoji = "\u{1F9F5}", rarity = "Uncommon",  color = Color3.fromRGB(140, 214, 190) },
	{ stage = 12, key = "swv_constell",  name = "Constellar",     emoji = "\u{2728}", rarity = "Rare",      color = Color3.fromRGB(128, 180, 255) },
	{ stage = 12, key = "swv_nebular",   name = "Nebular",        emoji = "\u{1F30C}", rarity = "Epic",      color = Color3.fromRGB(206, 136, 255) },
	{ stage = 12, key = "swv_firstlight", name = "First Light",   emoji = "\u{1F31F}", rarity = "Legendary", color = Color3.fromRGB(255, 228, 142) },
	-- 13 TIME WALKER
	{ stage = 13, key = "twk_second",    name = "Secondhand",     emoji = "\u{23F1}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(188, 184, 172) },
	{ stage = 13, key = "twk_hourglass", name = "Hourglass",      emoji = "\u{23F3}", rarity = "Uncommon",  color = Color3.fromRGB(224, 196, 128) },
	{ stage = 13, key = "twk_paradox",   name = "Paradox",        emoji = "\u{1F504}", rarity = "Rare",      color = Color3.fromRGB(124, 190, 244) },
	{ stage = 13, key = "twk_eternal",   name = "Eternal Loop",   emoji = "\u{267E}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(190, 134, 252) },
	{ stage = 13, key = "twk_epoch",     name = "Epoch",          emoji = "\u{1F570}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 212, 120) },
	-- 14 VOID SOVEREIGN
	{ stage = 14, key = "vsv_hollow",    name = "Hollow",         emoji = "\u{26AB}", rarity = "Common",    color = Color3.fromRGB(120, 122, 140) },
	{ stage = 14, key = "vsv_umbral",    name = "Umbral",         emoji = "\u{1F311}", rarity = "Uncommon",  color = Color3.fromRGB(120, 168, 172) },
	{ stage = 14, key = "vsv_abyssal",   name = "Abyssal",        emoji = "\u{1F30A}", rarity = "Rare",      color = Color3.fromRGB(104, 148, 232) },
	{ stage = 14, key = "vsv_devouring", name = "Devouring",      emoji = "\u{1F573}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(174, 116, 244) },
	{ stage = 14, key = "vsv_endless",   name = "Endless",        emoji = "\u{1F5A4}", rarity = "Legendary", color = Color3.fromRGB(255, 198, 112) },
	-- 15 REALITY ARCHITECT
	{ stage = 15, key = "rar_drafter",   name = "Drafter",        emoji = "\u{1F4D0}", rarity = "Common",    color = Color3.fromRGB(186, 194, 206) },
	{ stage = 15, key = "rar_mason",     name = "Axiom Mason",    emoji = "\u{1F9F1}", rarity = "Uncommon",  color = Color3.fromRGB(138, 206, 176) },
	{ stage = 15, key = "rar_prism",     name = "Prismwright",    emoji = "\u{1F53A}", rarity = "Rare",      color = Color3.fromRGB(122, 178, 250) },
	{ stage = 15, key = "rar_lattice",   name = "Latticelord",    emoji = "\u{1F536}", rarity = "Epic",      color = Color3.fromRGB(198, 134, 255) },
	{ stage = 15, key = "rar_firstdraw", name = "First Draft",    emoji = "\u{1F4D8}", rarity = "Legendary", color = Color3.fromRGB(255, 218, 126) },
	-- 16 DIMENSIONAL TITAN
	{ stage = 16, key = "dtn_stride",    name = "Stridebearer",   emoji = "\u{1F463}", rarity = "Common",    color = Color3.fromRGB(174, 178, 194) },
	{ stage = 16, key = "dtn_fold",      name = "Foldbreaker",    emoji = "\u{1F4C0}", rarity = "Uncommon",  color = Color3.fromRGB(132, 208, 196) },
	{ stage = 16, key = "dtn_rift",      name = "Riftcolossus",   emoji = "\u{1F30D}", rarity = "Rare",      color = Color3.fromRGB(116, 172, 252) },
	{ stage = 16, key = "dtn_planar",    name = "Planar Tyrant",  emoji = "\u{1F52E}", rarity = "Epic",      color = Color3.fromRGB(196, 128, 255) },
	{ stage = 16, key = "dtn_worldsp",   name = "Worldspine",     emoji = "\u{1F3D4}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 210, 116) },
	-- 17 CHRONOS BEING
	{ stage = 17, key = "chr_tick",      name = "Tickborn",       emoji = "\u{23F0}", rarity = "Common",    color = Color3.fromRGB(188, 186, 178) },
	{ stage = 17, key = "chr_ageless",   name = "Ageless",        emoji = "\u{1F55B}", rarity = "Uncommon",  color = Color3.fromRGB(146, 210, 186) },
	{ stage = 17, key = "chr_unwound",   name = "Unwound",        emoji = "\u{1F9F5}", rarity = "Rare",      color = Color3.fromRGB(124, 184, 250) },
	{ stage = 17, key = "chr_forever",   name = "Forevermind",    emoji = "\u{267E}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(200, 134, 255) },
	{ stage = 17, key = "chr_zerohour",  name = "Zero Hour",      emoji = "\u{1F551}", rarity = "Legendary", color = Color3.fromRGB(255, 220, 124) },
	-- 18 OMNISCIENT ENTITY
	{ stage = 18, key = "omn_watcher",   name = "Watcher",        emoji = "\u{1F441}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(190, 196, 210) },
	{ stage = 18, key = "omn_seer",      name = "Seer",           emoji = "\u{1F52E}", rarity = "Uncommon",  color = Color3.fromRGB(142, 212, 192) },
	{ stage = 18, key = "omn_oracle",    name = "Oracle",         emoji = "\u{1F4AD}", rarity = "Rare",      color = Color3.fromRGB(126, 182, 252) },
	{ stage = 18, key = "omn_allseeing", name = "All-Seeing",     emoji = "\u{1F31F}", rarity = "Epic",      color = Color3.fromRGB(202, 136, 255) },
	{ stage = 18, key = "omn_theknown",  name = "The Known",      emoji = "\u{1F4D6}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 132) },
	-- 19 PRIMORDIAL FORCE
	{ stage = 19, key = "pri_spark",     name = "First Spark",    emoji = "\u{1F4A5}", rarity = "Common",    color = Color3.fromRGB(184, 178, 188) },
	{ stage = 19, key = "pri_flood",     name = "Elder Flood",    emoji = "\u{1F30A}", rarity = "Uncommon",  color = Color3.fromRGB(134, 208, 210) },
	{ stage = 19, key = "pri_flame",     name = "Elder Flame",    emoji = "\u{1F525}", rarity = "Rare",      color = Color3.fromRGB(248, 148, 104) },
	{ stage = 19, key = "pri_silence",   name = "Elder Silence",  emoji = "\u{1F5A4}", rarity = "Epic",      color = Color3.fromRGB(190, 130, 250) },
	{ stage = 19, key = "pri_origin",    name = "The Origin",     emoji = "\u{1F30B}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 110) },
	-- 20 THE ABSOLUTE
	{ stage = 20, key = "abs_axiom",     name = "Axiom",          emoji = "\u{25AB}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(214, 214, 220) },
	{ stage = 20, key = "abs_theorem",   name = "Theorem",        emoji = "\u{1F53B}", rarity = "Uncommon",  color = Color3.fromRGB(146, 216, 198) },
	{ stage = 20, key = "abs_absolute",  name = "Absolute",       emoji = "\u{1F53A}", rarity = "Rare",      color = Color3.fromRGB(128, 186, 255) },
	{ stage = 20, key = "abs_infinite",  name = "The Infinite",   emoji = "\u{1F781}", rarity = "Epic",      color = Color3.fromRGB(206, 140, 255) },
	{ stage = 20, key = "abs_thefinal",  name = "The Final",      emoji = "\u{1F4A0}", rarity = "Legendary", color = Color3.fromRGB(255, 232, 150) },

	-- ===== THE SECOND FIVE ====================================================
	-- A second full set, same twenty stages, same rarity ladder: two Commons, two Uncommons, two
	-- Rares, two Epics and two Legendaries per stage. The roll is unchanged -- it weights by rarity
	-- and sums, so doubling the entries at each rarity leaves the CHANCE of rolling a Legendary
	-- exactly where it was and only decides which Legendary it is. What it changes is how long the
	-- collection takes to finish, which is the point: at five a stage a player who rebirths twice
	-- has usually seen everything their stage can be.
	-- 1 CELL
	{ stage = 1, key = "cell_pale",      name = "Pale Nucleus",   emoji = "\u{26AA}", rarity = "Common",    color = Color3.fromRGB(222, 228, 214) },
	{ stage = 1, key = "cell_coral",     name = "Coral Cyst",     emoji = "\u{1F7E0}", rarity = "Uncommon",  color = Color3.fromRGB(255, 168, 132) },
	{ stage = 1, key = "cell_mint",      name = "Mint Vesicle",   emoji = "\u{1F7E2}", rarity = "Rare",      color = Color3.fromRGB(150, 236, 190) },
	{ stage = 1, key = "cell_cobalt",    name = "Cobalt Blob",    emoji = "\u{1F535}", rarity = "Epic",      color = Color3.fromRGB(120, 150, 255) },
	{ stage = 1, key = "cell_ovum",      name = "Golden Ovum",    emoji = "\u{1F95A}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 140) },
	-- 2 BACTERIA
	{ stage = 2, key = "bact_dust",      name = "Dustcoccus",     emoji = "\u{1F4A8}", rarity = "Common",    color = Color3.fromRGB(196, 200, 180) },
	{ stage = 2, key = "bact_bloom",     name = "Bloomrod",       emoji = "\u{1F338}", rarity = "Uncommon",  color = Color3.fromRGB(255, 176, 206) },
	{ stage = 2, key = "bact_frost",     name = "Frostspore",     emoji = "\u{2744}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(186, 232, 255) },
	{ stage = 2, key = "bact_venom",     name = "Venomcoil",      emoji = "\u{1F40D}", rarity = "Epic",      color = Color3.fromRGB(150, 110, 236) },
	{ stage = 2, key = "bact_primal",    name = "Primal Culture", emoji = "\u{1F9EB}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 132) },
	-- 3 WORM
	{ stage = 3, key = "worm_pale",      name = "Palecrawler",    emoji = "\u{1F41B}", rarity = "Common",    color = Color3.fromRGB(226, 206, 196) },
	{ stage = 3, key = "worm_marsh",     name = "Marshgut",       emoji = "\u{1F33E}", rarity = "Uncommon",  color = Color3.fromRGB(150, 190, 120) },
	{ stage = 3, key = "worm_amber",     name = "Amberburrow",    emoji = "\u{1F7E7}", rarity = "Rare",      color = Color3.fromRGB(240, 176, 96) },
	{ stage = 3, key = "worm_shadow",    name = "Shadowcoil",     emoji = "\u{1F311}", rarity = "Epic",      color = Color3.fromRGB(140, 120, 200) },
	{ stage = 3, key = "worm_titan",     name = "Titan Grub",     emoji = "\u{1F41E}", rarity = "Legendary", color = Color3.fromRGB(255, 208, 120) },
	-- 4 LIZARD
	{ stage = 4, key = "liz_dune",       name = "Dunebask",       emoji = "\u{1F3DC}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(226, 204, 158) },
	{ stage = 4, key = "liz_reed",       name = "Reedskin",       emoji = "\u{1F343}", rarity = "Uncommon",  color = Color3.fromRGB(130, 204, 140) },
	{ stage = 4, key = "liz_glacier",    name = "Glacierfrill",   emoji = "\u{1F9CA}", rarity = "Rare",      color = Color3.fromRGB(168, 224, 255) },
	{ stage = 4, key = "liz_venom",      name = "Venomtongue",    emoji = "\u{2620}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(168, 132, 248) },
	{ stage = 4, key = "liz_sunking",    name = "Sun Basilisk",   emoji = "\u{2600}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 104) },
	-- 5 WOLF
	{ stage = 5, key = "wolf_dusk",      name = "Duskpelt",       emoji = "\u{1F31A}", rarity = "Common",    color = Color3.fromRGB(140, 138, 152) },
	{ stage = 5, key = "wolf_river",     name = "Riverfang",      emoji = "\u{1F4A7}", rarity = "Uncommon",  color = Color3.fromRGB(132, 196, 214) },
	{ stage = 5, key = "wolf_ash",       name = "Ashcoat",        emoji = "\u{1F32B}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(196, 190, 186) },
	{ stage = 5, key = "wolf_storm",     name = "Stormhowl",      emoji = "\u{26C8}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(150, 150, 244) },
	{ stage = 5, key = "wolf_sun",       name = "Sunfang Alpha",  emoji = "\u{1F31E}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 150) },
	-- 6 GORILLA
	{ stage = 6, key = "gor_stone",      name = "Stonefist",      emoji = "\u{1FAA8}", rarity = "Common",    color = Color3.fromRGB(166, 160, 152) },
	{ stage = 6, key = "gor_vine",       name = "Vinebrawler",    emoji = "\u{1F33F}", rarity = "Uncommon",  color = Color3.fromRGB(126, 176, 110) },
	{ stage = 6, key = "gor_iron",       name = "Ironback",       emoji = "\u{1F6E1}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(168, 182, 200) },
	{ stage = 6, key = "gor_ember",      name = "Emberchest",     emoji = "\u{1F525}", rarity = "Epic",      color = Color3.fromRGB(240, 140, 104) },
	{ stage = 6, key = "gor_primarch",   name = "Primarch",       emoji = "\u{1F3C6}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 120) },
	-- 7 HUMAN
	{ stage = 7, key = "hum_farmhand",   name = "Farmhand",       emoji = "\u{1F33E}", rarity = "Common",    color = Color3.fromRGB(208, 180, 150) },
	{ stage = 7, key = "hum_smith",      name = "Smith",          emoji = "\u{1F528}", rarity = "Uncommon",  color = Color3.fromRGB(176, 166, 150) },
	{ stage = 7, key = "hum_ranger",     name = "Ranger",         emoji = "\u{1F3F9}", rarity = "Rare",      color = Color3.fromRGB(128, 186, 150) },
	{ stage = 7, key = "hum_knight",     name = "Knight",         emoji = "\u{1F6E1}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(172, 150, 236) },
	{ stage = 7, key = "hum_sovereign",  name = "Sovereign",      emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 220, 140) },
	-- 8 CYBORG
	{ stage = 8, key = "cyb_scrap",      name = "Scrapframe",     emoji = "\u{1F5D1}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(168, 160, 150) },
	{ stage = 8, key = "cyb_carbon",     name = "Carbonshell",    emoji = "\u{26AB}", rarity = "Uncommon",  color = Color3.fromRGB(110, 116, 128) },
	{ stage = 8, key = "cyb_plasma",     name = "Plasmadrive",    emoji = "\u{1F535}", rarity = "Rare",      color = Color3.fromRGB(110, 200, 255) },
	{ stage = 8, key = "cyb_quantum",    name = "Quantum Core",   emoji = "\u{269B}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(168, 140, 255) },
	{ stage = 8, key = "cyb_omega",      name = "Omega Chassis",  emoji = "\u{2699}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 120) },
	-- 9 ALIEN
	{ stage = 9, key = "ali_drone",      name = "Drone",          emoji = "\u{1F47E}", rarity = "Common",    color = Color3.fromRGB(176, 190, 182) },
	{ stage = 9, key = "ali_ochre",      name = "Ochre Envoy",    emoji = "\u{1F7E4}", rarity = "Uncommon",  color = Color3.fromRGB(206, 150, 110) },
	{ stage = 9, key = "ali_crystal",    name = "Crystal Kin",    emoji = "\u{1F48E}", rarity = "Rare",      color = Color3.fromRGB(140, 220, 236) },
	{ stage = 9, key = "ali_overmind",   name = "Overmind",       emoji = "\u{1F9E0}", rarity = "Epic",      color = Color3.fromRGB(196, 132, 248) },
	{ stage = 9, key = "ali_starseed",   name = "Starseed",       emoji = "\u{2734}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 150) },
	-- 10 COSMIC BEING
	{ stage = 10, key = "cos_ember",     name = "Emberdrift",     emoji = "\u{1F320}", rarity = "Common",    color = Color3.fromRGB(196, 176, 168) },
	{ stage = 10, key = "cos_aurora",    name = "Auroraform",     emoji = "\u{1F30C}", rarity = "Uncommon",  color = Color3.fromRGB(140, 226, 206) },
	{ stage = 10, key = "cos_nova",      name = "Novaheart",      emoji = "\u{1F4A5}", rarity = "Rare",      color = Color3.fromRGB(255, 158, 120) },
	{ stage = 10, key = "cos_voidglow",  name = "Voidglow",       emoji = "\u{26AB}", rarity = "Epic",      color = Color3.fromRGB(170, 130, 255) },
	{ stage = 10, key = "cos_eclipse",   name = "Eclipsebound",   emoji = "\u{1F31A}", rarity = "Legendary", color = Color3.fromRGB(255, 226, 140) },
	-- 11 UNIVERSE GOD
	{ stage = 11, key = "ugod_herald",   name = "Herald",         emoji = "\u{1F4EF}", rarity = "Common",    color = Color3.fromRGB(186, 190, 214) },
	{ stage = 11, key = "ugod_keeper",   name = "Keeper",         emoji = "\u{1F5DD}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(146, 204, 196) },
	{ stage = 11, key = "ugod_judge",    name = "Judge",          emoji = "\u{1F3DB}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(140, 180, 244) },
	{ stage = 11, key = "ugod_fate",     name = "Fatespinner",    emoji = "\u{1F9F6}", rarity = "Epic",      color = Color3.fromRGB(198, 140, 252) },
	{ stage = 11, key = "ugod_eternal",  name = "The Eternal",    emoji = "\u{267E}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 136) },
	-- 12 STAR WEAVER
	{ stage = 12, key = "swv_spindle",   name = "Spindle",        emoji = "\u{1F4AB}", rarity = "Common",    color = Color3.fromRGB(192, 192, 208) },
	{ stage = 12, key = "swv_dawn",      name = "Dawnthread",     emoji = "\u{1F305}", rarity = "Uncommon",  color = Color3.fromRGB(255, 196, 150) },
	{ stage = 12, key = "swv_pulse",     name = "Pulseweft",      emoji = "\u{1F4A0}", rarity = "Rare",      color = Color3.fromRGB(130, 196, 255) },
	{ stage = 12, key = "swv_darkloom",  name = "Dark Loom",      emoji = "\u{1F578}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(170, 120, 240) },
	{ stage = 12, key = "swv_lastthread", name = "Last Thread",   emoji = "\u{1F3B6}", rarity = "Legendary", color = Color3.fromRGB(255, 230, 150) },
	-- 13 TIME WALKER
	{ stage = 13, key = "twk_minute",    name = "Minutewalk",     emoji = "\u{1F55C}", rarity = "Common",    color = Color3.fromRGB(190, 186, 176) },
	{ stage = 13, key = "twk_sundial",   name = "Sundial",        emoji = "\u{1F31E}", rarity = "Uncommon",  color = Color3.fromRGB(232, 200, 132) },
	{ stage = 13, key = "twk_rewind",    name = "Rewind",         emoji = "\u{23EA}", rarity = "Rare",      color = Color3.fromRGB(130, 196, 240) },
	{ stage = 13, key = "twk_fracture",  name = "Fracture Hour",  emoji = "\u{1F52E}", rarity = "Epic",      color = Color3.fromRGB(186, 138, 250) },
	{ stage = 13, key = "twk_finalhour", name = "Final Hour",     emoji = "\u{1F553}", rarity = "Legendary", color = Color3.fromRGB(255, 216, 126) },
	-- 14 VOID SOVEREIGN
	{ stage = 14, key = "vsv_ashen",     name = "Ashen",          emoji = "\u{1F32B}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(128, 128, 142) },
	{ stage = 14, key = "vsv_dim",       name = "Dimlight",       emoji = "\u{1F56F}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(126, 160, 168) },
	{ stage = 14, key = "vsv_nulltide",  name = "Null Tide",      emoji = "\u{1F535}", rarity = "Rare",      color = Color3.fromRGB(110, 150, 226) },
	{ stage = 14, key = "vsv_starless",  name = "Starless",       emoji = "\u{2B50}", rarity = "Epic",      color = Color3.fromRGB(168, 120, 240) },
	{ stage = 14, key = "vsv_crown",     name = "Crown of Nothing", emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 204, 120) },
	-- 15 REALITY ARCHITECT
	{ stage = 15, key = "rar_sketch",    name = "Sketchwright",   emoji = "\u{270F}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(192, 196, 204) },
	{ stage = 15, key = "rar_frame",     name = "Framesmith",     emoji = "\u{1F5BC}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(142, 204, 180) },
	{ stage = 15, key = "rar_vault",     name = "Vaultbuilder",   emoji = "\u{1F3E6}", rarity = "Rare",      color = Color3.fromRGB(128, 182, 250) },
	{ stage = 15, key = "rar_render",    name = "Renderlord",     emoji = "\u{1F5A5}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(196, 140, 252) },
	{ stage = 15, key = "rar_blueprint", name = "The Blueprint",  emoji = "\u{1F4DC}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 132) },
	-- 16 DIMENSIONAL TITAN
	{ stage = 16, key = "dtn_step",      name = "Stepwalker",     emoji = "\u{1F45F}", rarity = "Common",    color = Color3.fromRGB(176, 180, 196) },
	{ stage = 16, key = "dtn_gate",      name = "Gatebreaker",    emoji = "\u{1F6AA}", rarity = "Uncommon",  color = Color3.fromRGB(136, 206, 198) },
	{ stage = 16, key = "dtn_echo",      name = "Echo Colossus",  emoji = "\u{1F310}", rarity = "Rare",      color = Color3.fromRGB(120, 176, 250) },
	{ stage = 16, key = "dtn_prism",     name = "Prism Tyrant",   emoji = "\u{1F53A}", rarity = "Epic",      color = Color3.fromRGB(198, 132, 255) },
	{ stage = 16, key = "dtn_worldend",  name = "Worldbreaker",   emoji = "\u{1F30B}", rarity = "Legendary", color = Color3.fromRGB(255, 212, 120) },
	-- 17 CHRONOS BEING
	{ stage = 17, key = "chr_grain",     name = "Sandgrain",      emoji = "\u{231B}", rarity = "Common",    color = Color3.fromRGB(190, 188, 180) },
	{ stage = 17, key = "chr_dawn",      name = "Dawnkeeper",     emoji = "\u{1F304}", rarity = "Uncommon",  color = Color3.fromRGB(150, 212, 190) },
	{ stage = 17, key = "chr_loop",      name = "Loopbound",      emoji = "\u{1F501}", rarity = "Rare",      color = Color3.fromRGB(128, 188, 252) },
	{ stage = 17, key = "chr_still",     name = "Stillpoint",     emoji = "\u{23F8}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(202, 138, 255) },
	{ stage = 17, key = "chr_enddays",   name = "End of Days",    emoji = "\u{1F556}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 128) },
	-- 18 OMNISCIENT ENTITY
	{ stage = 18, key = "omn_listener",  name = "Listener",       emoji = "\u{1F442}", rarity = "Common",    color = Color3.fromRGB(192, 198, 212) },
	{ stage = 18, key = "omn_archivist", name = "Archivist",      emoji = "\u{1F5C3}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(146, 214, 194) },
	{ stage = 18, key = "omn_prophet",   name = "Prophet",        emoji = "\u{1F4FF}", rarity = "Rare",      color = Color3.fromRGB(130, 186, 254) },
	{ stage = 18, key = "omn_mind",      name = "The Mind",       emoji = "\u{1F9E0}", rarity = "Epic",      color = Color3.fromRGB(204, 140, 255) },
	{ stage = 18, key = "omn_truth",     name = "The Truth",      emoji = "\u{1F4A1}", rarity = "Legendary", color = Color3.fromRGB(255, 228, 136) },
	-- 19 PRIMORDIAL FORCE
	{ stage = 19, key = "pri_dust",      name = "First Dust",     emoji = "\u{1F4A8}", rarity = "Common",    color = Color3.fromRGB(186, 180, 190) },
	{ stage = 19, key = "pri_stone",     name = "Elder Stone",    emoji = "\u{1FAA8}", rarity = "Uncommon",  color = Color3.fromRGB(150, 150, 160) },
	{ stage = 19, key = "pri_storm",     name = "Elder Storm",    emoji = "\u{26C8}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(140, 190, 246) },
	{ stage = 19, key = "pri_night",     name = "Elder Night",    emoji = "\u{1F311}", rarity = "Epic",      color = Color3.fromRGB(150, 120, 230) },
	{ stage = 19, key = "pri_firstdawn", name = "The First Dawn", emoji = "\u{1F305}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 120) },
	-- 20 THE ABSOLUTE
	{ stage = 20, key = "abs_null",      name = "Null",           emoji = "\u{25FB}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(216, 216, 222) },
	{ stage = 20, key = "abs_proof",     name = "Proof",          emoji = "\u{1F9EE}", rarity = "Uncommon",  color = Color3.fromRGB(150, 220, 202) },
	{ stage = 20, key = "abs_limit",     name = "The Limit",      emoji = "\u{267E}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(132, 190, 255) },
	{ stage = 20, key = "abs_paradox",   name = "Paradox Prime",  emoji = "\u{1F300}", rarity = "Epic",      color = Color3.fromRGB(208, 144, 255) },
	{ stage = 20, key = "abs_omega",     name = "Omega",          emoji = "\u{1F3C1}", rarity = "Legendary", color = Color3.fromRGB(255, 236, 158) },
}

-- key -> entry, and stage -> its five, both built once. A hundred-entry linear scan runs on every
-- Journal refresh and on every costume build otherwise.
-- ===== NO TWO CHARACTERS IN A STAGE MAY SHARE A COLOUR =====
-- `color` is the whole of what the authored table above varies, and it was authored one row at a
-- time, so a stage could end up with three of them on the same swatch: Amber Blob (248,226,128),
-- Prime Seed (255,226,130) and Golden Ovum (255,214,140) were 7 and 16 apart in RGB. Picking one
-- over another in the Journal then changed NOTHING a player could see. Across the twenty stages
-- there were 127 pairs closer than 55 apart and the worst was 3.
--
-- Separated here rather than by hand in the table because the table is where a designer works: a
-- new character can be given whatever colour reads right for its NAME, and this guarantees it will
-- still be distinguishable from its stagemates without anyone having to check.
--
-- VALUE AND SATURATION DO THE WORK, HUE BARELY MOVES (0.01 per step, capped by how few steps are
-- ever needed). That ordering is the whole trick: a gold pushed darker and richer is still a gold,
-- while a gold pushed around the hue wheel is a lime -- the first attempt at this turned "Golden
-- Ovum" green and "Titan" into a leaf. A character has to keep looking like its own name.
--
-- Deterministic, and seeded from the AUTHORED colour rather than from the previous iteration, so a
-- given key always lands on the same shade -- a skin that shifts between sessions is not a skin.
do
	local MIN_DIST = 30 -- RGB units. Below this two shells read as the same colour in play.
	local function dist(a, b)
		return math.sqrt(((a.R - b.R) * 255) ^ 2 + ((a.G - b.G) * 255) ^ 2 + ((a.B - b.B) * 255) ^ 2)
	end

	local placed = {}
	for _, c in ipairs(GameConfig.StageCharacters) do
		placed[c.stage] = placed[c.stage] or {}
		local taken = placed[c.stage]
		local col = c.color
		local idx = #taken + 1
		for step = 1, 10 do
			local clash = false
			for _, other in ipairs(taken) do
				if dist(col, other) < MIN_DIST then
					clash = true
					break
				end
			end
			if not clash then break end
			local h, s, v = Color3.toHSV(c.color)
			-- alternating direction by position in the stage, so a run of similar colours spreads
			-- both lighter and darker instead of all marching one way into black
			local dir = (idx % 2 == 0) and 1 or -1
			v = math.clamp(v - dir * 0.13 * step, 0.30, 1)
			s = math.clamp(s + 0.09 * step, 0.15, 1)
			h = (h + dir * 0.010 * step) % 1
			col = Color3.fromHSV(h, s, v)
		end
		c.color = col
		taken[#taken + 1] = col
	end
end

-- ===== HOW MANY OF EACH STAGE'S LIST ARE ACTUALLY IN PLAY =====
--
-- The table above authors ten per stage, two hundred in all. That is too many to be COLLECTED:
-- a stage's whole list has to be finished before the next stage's opens (see
-- NextCharacterForStage and the evolve gate in DNAService), so ten per stage means ten unlocks
-- of standing in one zone before the game moves on -- and the report was exactly that, a player
-- at Bacteria still holding Cell 1/10.
--
-- Five. Applied as a CAP on the lookup rather than by deleting rows, for three reasons: the
-- authored table stays the designer's document, the meshes for all ten are already generated and
-- filed so raising this is one number rather than a regeneration, and `GetCharacterRank` counts
-- off the lists it is given -- so the ladder renumbers itself to 1..100 automatically and the
-- damage/health curves keep their shape without a single other edit.
--
-- A save holding a character past the cap keeps it (CHARACTER_BY_KEY is not capped, so it still
-- resolves, still wears and still scores); it simply stops being handed out.
GameConfig.CharactersPerStage = 5

local CHARACTER_BY_KEY, CHARACTERS_BY_STAGE = {}, {}
for _, c in ipairs(GameConfig.StageCharacters) do
	-- keyed lookup is UNCAPPED on purpose -- see the note above
	CHARACTER_BY_KEY[c.key] = c
	local list = CHARACTERS_BY_STAGE[c.stage]
	if not list then
		list = {}
		CHARACTERS_BY_STAGE[c.stage] = list
	end
	if #list < GameConfig.CharactersPerStage then
		table.insert(list, c)
	end
end

-- ===== THE VIP SKIN: A 201st ENTRY THAT IS NOT PART OF THE COLLECTION =====
--
-- Registered in CHARACTER_BY_KEY so it resolves, wears and paints like any other skin -- and
-- DELIBERATELY NOT in CHARACTERS_BY_STAGE. That table is what CountCharactersForStage, GetEvolveStep
-- and GetCollectionStage all count off; a 201st entry inside it would add a sixth step to some
-- stage's evolve chain, move every rank above it, and make the Journal unable to ever read 200/200.
-- Kept outside, it is visible and wearable while the collection arithmetic never sees it.
--
-- There is no generated SkinMesh_vip_gold, and that is fine: SkinMesh.Has() is what callers use to
-- choose between the mesh and StageCostume, so this falls back to the costume painted in the colour
-- below -- i.e. a gold version of whatever stage the player is standing at, at any stage.
GameConfig.VipCharacter = {
	key = "vip_gold",
	name = "Golden Patron",
	emoji = "👑",
	rarity = "Legendary",
	color = Color3.fromRGB(255, 205, 74),
	vip = true,
	-- See the note over GameConfig.EventCharacters: `offLadder` is what the rank arithmetic reads,
	-- `vip` is what the pass sync and the Journal's section title read. They were one field until
	-- there was a second kind of skin that is not on the ladder.
	offLadder = true,
}
CHARACTER_BY_KEY[GameConfig.VipCharacter.key] = GameConfig.VipCharacter

-- ===== EVENT-EXCLUSIVE SKINS: THE SAME SEPARATION, WITH ONE DIFFERENCE =====
--
-- Registered in CHARACTER_BY_KEY and never in CHARACTERS_BY_STAGE, for every reason written over
-- GameConfig.VipCharacter above -- the collection count, the evolve chain and the rank ladder must
-- not be able to see them, or the Journal could never read 200/200 again.
--
-- `offLadder = true` is the field the rank functions test. It used to be `vip`, which was fine
-- while there was exactly one skin outside the ladder; a second one would have had to be called
-- VIP to score correctly, and the next reader would have believed it.
--
-- THE DIFFERENCE IS THAT THESE ARE NEVER TAKEN BACK. The VIP skin is synced to a pass and revoked
-- the moment it lapses, because it is a subscription's badge. An event skin is a receipt for having
-- been there, and the only thing that makes a limited item worth owning is that the window it came
-- from is shut. EventService grants it while the window is open and nothing anywhere removes it --
-- not a rebirth, which clears data.Characters wholesale and is healed by the same sweep the VIP
-- skin uses, and not the event ending.
--
-- There is no generated SkinMesh for these and that is intended: SkinMesh.Has() falls through to
-- StageCostume painted in the colour below, i.e. a Prism version of whatever stage you are standing
-- at -- which is also why they preview at the player's own stage in the Journal rather than at a
-- stage of their own.
GameConfig.EventCharacters = {
	{
		key = "event_prism",
		name = "Prism Herald",
		emoji = "\u{1F308}",
		rarity = "Legendary",
		color = Color3.fromRGB(158, 120, 255),
		event = "PrismFest",
		offLadder = true,
	},
	-- ===== THE FOUR COLOSSEUM CHAMPIONS (12.13) =====
	--
	-- One per week of ColosseumClash's rotation, and the ORDER OF THIS LIST IS NOT WHAT PICKS THEM:
	-- the rotation is the list on the event itself, and this table is only the registry that makes
	-- each key resolve to a name and a colour. They are two lists on purpose -- a skin can be
	-- retired from the rotation without deleting the entry that a save which already owns it needs
	-- (see SyncEventCharacters, which drops keys nothing resolves).
	--
	-- FOUR DISTINCT HUES, chosen against each other and against the two skins already outside the
	-- ladder. Prism Herald is violet and the VIP skin is gold, so the champions take orange, ice
	-- blue, green and slate -- there is no mesh for any of them, so the whole of a champion IS its
	-- colour on the player's own stage costume, and two that read the same from across the plaza are
	-- two weekends that felt like one.
	{
		key = "event_clash_ember",
		name = "Ember Gladiator",
		emoji = "\u{1F525}",
		rarity = "Legendary",
		color = Color3.fromRGB(238, 96, 54),
		event = "ColosseumClash",
		offLadder = true,
	},
	{
		key = "event_clash_frost",
		name = "Frost Sentinel",
		emoji = "\u{2744}\u{FE0F}",
		rarity = "Legendary",
		color = Color3.fromRGB(118, 208, 255),
		event = "ColosseumClash",
		offLadder = true,
	},
	{
		key = "event_clash_verdant",
		name = "Verdant Colossus",
		emoji = "\u{1F33F}",
		rarity = "Legendary",
		color = Color3.fromRGB(96, 200, 118),
		event = "ColosseumClash",
		offLadder = true,
	},
	{
		key = "event_clash_onyx",
		name = "Onyx Praetor",
		emoji = "\u{1F311}",
		rarity = "Legendary",
		color = Color3.fromRGB(96, 90, 124),
		event = "ColosseumClash",
		offLadder = true,
	},
}
for _, c in ipairs(GameConfig.EventCharacters) do
	CHARACTER_BY_KEY[c.key] = c
end

function GameConfig.GetEventCharacter(key)
	for _, c in ipairs(GameConfig.EventCharacters) do
		if c.key == key then return c end
	end
	return nil
end

function GameConfig.GetCharacter(key)
	return key and CHARACTER_BY_KEY[key] or nil
end

function GameConfig.GetCharactersForStage(stageIndex)
	return CHARACTERS_BY_STAGE[stageIndex] or {}
end

-- ===== A CHARACTER IS EARNED BY EVOLVING, AND NOTHING ELSE =====
--
-- Kills used to hand them over at 1 in 5 while the evolve was BLOCKED until all five of a stage
-- had dropped. That is the same wait written twice, and the half of it the player could see was
-- the wrong half: what stood between them and the button was a dice roll rather than anything
-- they were doing.
--
-- Every character is its own evolve now -- see GameConfig.GetEvolveStep. Kept at 0 rather than
-- deleted because the roll is called from CreatureService's hot path and from the shrine, and a
-- number is a safer thing to leave behind than a missing function.
GameConfig.CharacterDropChance = 0

function GameConfig.RollCharacterDrop()
	return math.random() < GameConfig.CharacterDropChance
end

-- ===== A CHARACTER IS A DAMAGE TIER, AND IT IS UNLOCKED IN ORDER =====
-- This replaces a random weighted roll. The reason is what the Journal turned into: a grid of
-- padlocks with a percentage under each one, where a player could grind a stage for an hour and
-- keep re-rolling the same Common. Unlocking left to right means every evolve into a stage hands
-- over the next character in that stage's list, so progress is visible and nothing is ever wasted.
--
-- With the order fixed, POSITION IN THE LIST IS THE POWER LADDER -- 1st is the weakest, 10th the
-- strongest -- so the honest number to print under a character is what it does, not what it cost
-- to find. `rarity` stays in the data: it is what StageCostume's skinMarks reads to decide how
-- much flourish a character wears, and it now describes the same ladder from the other end.
GameConfig.CharacterDamageStep = 6 -- kept for saves and tools that still read it

-- ONE LADDER ACROSS THE WHOLE COLLECTION, NOT TEN RUNGS PER STAGE.
--
-- A character used to be worn per stage, and its damage was its position within its own stage --
-- so the tenth Cell and the tenth Absolute were both "+60%", and choosing between them was not a
-- decision anyone could make because you could only ever wear the one belonging to the stage you
-- were standing at.
--
-- Any character can be worn at any time now, anywhere. That only means something if they are
-- ranked against EACH OTHER: rank 1 is the first Cell, rank 200 is the last Absolute, and wearing
-- something from further back in the collection is a real trade -- you look like what you want and
-- you hit for less. The Journal prints the figure on every entry so the trade is never a guess.
--
-- 3% a rung, so the spread inside one stage is 30% (a choice you can feel) and the whole ladder
-- tops out at +600%. Deliberately generous at the top: the collection fills strictly bottom-up, so
-- a player deep enough to own a rank-200 character has earned every one of the 199 below it.
GameConfig.CharacterDamagePerRank = 3

-- The Nth character of its stage, 1-based. Kept as a lookup rather than stored on the entry so the
-- authored table above stays a plain list that a designer can reorder freely.
function GameConfig.GetCharacterIndex(entry)
	if not entry then return 1 end
	local list = CHARACTERS_BY_STAGE[entry.stage] or {}
	for i, c in ipairs(list) do
		if c.key == entry.key then return i end
	end
	return 1
end

-- Where this character stands in the whole collection, 1-based. Counted off the stages BELOW it
-- rather than off a constant ten per stage, so a stage with a different number of characters does
-- not silently shift everything after it.
function GameConfig.GetCharacterRank(entry)
	if not entry then return 0 end
	-- An off-ladder skin -- the VIP one, an event one -- has no rung. It is not in CHARACTERS_BY_STAGE
	-- and counting it as one would put it either at the bottom (worthless) or the top (bought or
	-- date-of-birth power). What it is worth is decided per WEARER instead; see GetEffectiveRank.
	if entry.offLadder then return 0 end
	local rank = 0
	for stageIndex = 1, (entry.stage or 1) - 1 do
		rank += #(CHARACTERS_BY_STAGE[stageIndex] or {})
	end
	return rank + GameConfig.GetCharacterIndex(entry)
end

function GameConfig.GetCharacterDamagePct(entry)
	if not entry then return 0 end
	return GameConfig.GetCharacterRank(entry) * GameConfig.CharacterDamagePerRank
end

-- WHAT IS ON THE BODY, wherever the player happens to be standing. One character, not one per
-- stage. Returns a MULTIPLIER so it drops straight into the damage chain.
--
-- `EquippedCharacters` is still read as the fallback so a save written before this change keeps
-- whatever it was wearing at its own stage until the player next picks something.
function GameConfig.GetWornCharacter(data)
	if not data then return nil end
	local key = data.WornCharacter
	if not key and data.EquippedCharacters then
		key = data.EquippedCharacters[tostring(data.StageIndex or 1)]
	end
	return key and CHARACTER_BY_KEY[key] or nil
end

-- The best rung this player has actually EARNED. The VIP skin ignores the entry it is worn as and
-- scores as this instead, which is the whole reason it is not pay-to-win: wearing it never costs a
-- player damage they had, and never hands them damage they did not climb to. It also means the
-- skin stays worth wearing for the rest of the game instead of being abandoned the moment the
-- collection passes it, which is what any fixed rank would have caused.
function GameConfig.GetBestOwnedRank(data)
	local best = 0
	for key in pairs((data and data.Characters) or {}) do
		local entry = CHARACTER_BY_KEY[key]
		if entry and not entry.offLadder then
			local rank = GameConfig.GetCharacterRank(entry)
			if rank > best then best = rank end
		end
	end
	return best
end

function GameConfig.GetEffectiveRank(data, entry)
	if entry and entry.offLadder then return GameConfig.GetBestOwnedRank(data) end
	return GameConfig.GetCharacterRank(entry)
end

-- ===== HOW FAR UP THE LADDER THIS SAVE HAS CLIMBED =====
--
-- The rung the player's DAMAGE is read off. It is the best rung they OWN, not the one they have on
-- -- and that is a deliberate reversal of the older rule, forced by the curve above.
--
-- Rank used to be worth a linear +3% each, so wearing something fifty rungs back cost 150% and was
-- a real but survivable trade the Journal advertised honestly. Geometric, the same choice costs a
-- factor of forty, and no cosmetic is worth that: it would not read as a trade, it would read as a
-- broken save. The collection also fills strictly in order and every evolve auto-wears the newest
-- entry, so the trade was one almost nobody was making on purpose in the first place.
--
-- So progress pays and appearance is free. Wear whatever you like; you keep what you climbed to.
function GameConfig.GetProgressRank(data)
	return math.max(1, GameConfig.GetBestOwnedRank(data))
end

-- THE BASE OF THE DAMAGE CHAIN, and the number the Journal prints beside the rung that grants it.
-- Everything else in `DNAService.GetCombatDamage` is a multiplier on this.
function GameConfig.GetBaseDamage(data)
	return GameConfig.GetRankDamage(GameConfig.GetProgressRank(data))
end

-- Kept because saves, tools and the Journal's older rows still call it, and it is still true of
-- what a rung is WORTH -- it just no longer decides what the body standing in the world hits for.
-- Returns 1 unconditionally so the damage chain is unchanged by a costume.
function GameConfig.GetCharacterDamageMult(_data)
	return 1
end

-- ===== A SKIN GIVES HEALTH AS WELL AS DAMAGE =====
--
-- The ladder only paid offence: rank 200 hit for +600% and had exactly the same hit points as rank
-- 1. That makes late characters strictly a damage stat, and it makes the trade the Journal offers --
-- "wear what you like and hit for less" -- much sharper than it should be, because dropping back
-- fifty ranks cost damage and nothing was gained in return.
--
-- 1% a rung against damage's 3%, so the whole ladder tops out at +200% health where damage tops out
-- at +600%. Deliberately the smaller number of the two: health multiplies how long a fight lasts
-- and damage multiplies how fast it ends, so equal rates would make the late game trivially safe.
-- It stacks MULTIPLICATIVELY with Stage Mastery's healthMult, exactly as the damage side stacks.
GameConfig.CharacterHealthPerRank = 1

-- WHAT ONE RUNG IS WORTH IN HEALTH, and the Journal's second stat line quotes it rather than
-- re-deriving "1% a rung" in the UI -- a second copy of the rate is a promise that goes stale the
-- day the rate moves, which is the exact bug the damage figure on the same card was rescued from.
--
-- `data` is optional and only matters for an OFF-LADDER skin. The VIP and event skins have no rung
-- of their own -- GetCharacterRank returns 0 for them on purpose -- and score as the best one the
-- save has earned, which is what GetEffectiveRank exists for. Without the second argument this
-- printed "+0% Max Health" beside a skin that in fact carries the wearer's whole collection.
function GameConfig.GetCharacterHealthPct(entry, data)
	if not entry then return 0 end
	return GameConfig.GetEffectiveRank(data, entry) * GameConfig.CharacterHealthPerRank
end

-- Health follows damage onto the PROGRESS rung for the same reason (see GetProgressRank): the two
-- have to agree about what the player is, or a costume would change how long they survive while
-- leaving what they hit for alone. Still linear at 1% a rung -- health multiplies how long a fight
-- lasts and damage how fast it ends, so this side deliberately does NOT go geometric; +99% at the
-- top of the collection, against a damage ladder that has grown by a factor of 1,394.
function GameConfig.GetCharacterHealthMult(data)
	return 1 + GameConfig.GetProgressRank(data) * GameConfig.CharacterHealthPerRank / 100
end

-- Grants or REVOKES the VIP skin so it always matches the pass. Called on every pass refresh and
-- again after a rebirth, because RebirthService clears `data.Characters` wholesale -- without the
-- second call a VIP who rebirthed would lose the skin until they next rejoined.
function GameConfig.SyncVipCharacter(data)
	if not data then return end
	data.Characters = data.Characters or {}
	local key = GameConfig.VipCharacter.key

	if GameConfig.OwnsPass(data, "VIP") then
		data.Characters[key] = true
		return
	end

	data.Characters[key] = nil
	-- Still wearing it after the pass went away would leave the body in a skin the player no longer
	-- owns, and GetWornCharacter would happily keep resolving it. Fall back to the best thing they
	-- actually earned, which is also exactly what the VIP skin had been scoring as.
	if data.WornCharacter == key then
		local best, bestRank = nil, -1
		for owned in pairs(data.Characters) do
			local entry = GameConfig.GetCharacter(owned)
			-- offLadder rather than vip: an event skin also scores 0 here, so falling back onto one
			-- would put the player in a costume that is not the best thing they earned.
			if entry and not entry.offLadder then
				local rank = GameConfig.GetCharacterRank(entry)
				if rank > bestRank then best, bestRank = owned, rank end
			end
		end
		data.WornCharacter = best
	end
end

-- ===== AN EVENT SKIN HAS TO SURVIVE A REBIRTH, AND data.Characters DOES NOT =====
--
-- `RebirthService` clears `data.Characters` wholesale and the collection is then re-granted from
-- the stage lists. The VIP skin survives that because SyncVipCharacter puts it back from the pass,
-- which is a live fact that can be re-asked at any time. An event skin has no such source: the
-- window it came from is shut, so once it is gone it is gone -- a player who rebirths in October
-- would silently lose a September festival skin and nothing anywhere could give it back.
--
-- So `data.EventCharacters` is the permanent record and `data.Characters` is only ever the working
-- copy. Same shape and same reasoning as StatsService's `CountedCharacters`: a set that no reset
-- touches, from which the thing a reset destroys is rebuilt. Called on the rebirth hook beside
-- SyncVipCharacter and by EventService's own sweep, and it is idempotent, so extra calls are free.
function GameConfig.SyncEventCharacters(data)
	if not data then return 0 end
	data.Characters = data.Characters or {}
	local restored = 0
	for key, earned in pairs(data.EventCharacters or {}) do
		-- only keys that still resolve: a skin removed from the table in a later build must not
		-- reappear on a body as a nil entry the costume code then tries to paint with
		if earned == true and CHARACTER_BY_KEY[key] and not data.Characters[key] then
			data.Characters[key] = true
			restored += 1
		end
	end
	return restored
end

-- THE NEXT ONE TO HAND OVER: the first entry of this stage the player does not already own.
-- Returns nil once the stage is complete, which is what tells the caller there is nothing left to
-- give here -- the old roll could only signal that by handing back a duplicate.
function GameConfig.NextCharacterForStage(owned, stageIndex)
	local list = CHARACTERS_BY_STAGE[stageIndex]
	if not list then return nil end
	for _, c in ipairs(list) do
		if not (owned and owned[c.key]) then return c end
	end
	return nil
end

-- KEPT because RebirthShrine and the mystery-shop path still call it, but it is no longer how
-- characters are earned. `luck` is ignored: with the order fixed there is no curve for it to lift.
function GameConfig.RollCharacterForStage(stageIndex, luck)
	local list = CHARACTERS_BY_STAGE[stageIndex]
	if not list or #list == 0 then return nil end
	local weights, total = {}, 0
	for i, c in ipairs(list) do
		local rarity = GameConfig.GetRarity(c.rarity)
		-- the rarer the entry the more luck moves it, so luck is felt at the top of the ladder
		-- rather than spread flat across all five
		local w = rarity.weight * (1 + (luck or 0) * 0.01 * (rarity.bonusMult - 1))
		weights[i] = w
		total = total + w
	end
	local roll = math.random() * total
	local acc = 0
	for i, w in ipairs(weights) do
		acc = acc + w
		if roll <= acc then return list[i] end
	end
	return list[1]
end

-- What the Journal prints at the top: how many of the collection are owned.
--
-- COUNTED OFF THE CAPPED LISTS, NOT OFF THE AUTHORED TABLE. `StageCharacters` still holds ten a
-- stage; only five of each are in play (see CharactersPerStage). Walking the raw table printed
-- "1/200" on a collection whose real total is 100, i.e. a bar that could never pass halfway.
function GameConfig.CountCharacters(owned)
	local total, have = 0, 0
	for stageIndex = 1, #GameConfig.Stages do
		for _, c in ipairs(CHARACTERS_BY_STAGE[stageIndex] or {}) do
			total += 1
			if owned and owned[c.key] then have += 1 end
		end
	end
	return have, total
end

-- How many of ONE stage's list are owned, and how many there are.
function GameConfig.CountCharactersForStage(owned, stageIndex)
	local list = CHARACTERS_BY_STAGE[stageIndex] or {}
	local have = 0
	for _, c in ipairs(list) do
		if owned and owned[c.key] then have = have + 1 end
	end
	return have, #list
end

-- ===== ONE EVOLVE IS ONE SKIN, AND FIVE SKINS ARE ONE STAGE =====
--
-- The chain the player actually walks is 100 steps long, not 20. Each press hands over the next
-- character in collection order; four presses in five change only what the body looks like, and
-- the fifth also changes what it IS -- stage, size, income curve, and the zone that opens with it.
--
-- ONE FUNCTION, BECAUSE THE SERVER AND THE HUD MUST NEVER DISAGREE ABOUT WHAT THE BUTTON DOES.
-- DNAService charges exactly what this returns and MainUI prints exactly what this returns, so a
-- button that says "EVOLVE" can never be answered by a red error toast.
--
-- WHAT A STEP COSTS: the current stage's own `cost` and `xpCost`, charged on every one of its five
-- steps -- so a stage is five evolves at the price the whole stage used to be. DNA is not the
-- binding requirement (pets, mutations, potions and zone bonuses multiply it by thousands); XP is,
-- and nothing multiplies XP, so this makes a stage five levels of fighting instead of one.
function GameConfig.GetEvolveStep(data)
	local stageIndex = math.clamp((data and data.StageIndex) or 1, 1, #GameConfig.Stages)
	local stage = GameConfig.Stages[stageIndex]
	local owned = (data and data.Characters) or {}
	local have, stageTotal = GameConfig.CountCharactersForStage(owned, stageIndex)

	local step = {
		stageIndex = stageIndex,
		stage = stage,
		have = have,           -- how many of THIS stage are already collected: the "(2/5)" on the HUD
		stageTotal = stageTotal,
		entry = GameConfig.NextCharacterForStage(owned, stageIndex),
		advancesStage = false,
		isMax = false,
	}

	if not step.entry then
		-- this stage is finished, so the next press is the stage jump -- and it hands over the
		-- first skin of the stage it arrives at, which is what keeps the collection in order
		-- without a single special case anywhere else
		local nextIndex = stageIndex + 1
		local nextStage = GameConfig.Stages[nextIndex]
		if not nextStage then
			step.isMax = true
			return step
		end
		step.advancesStage = true
		step.nextStageIndex = nextIndex
		step.nextStage = nextStage
		step.entry = GameConfig.NextCharacterForStage(owned, nextIndex)
	end

	-- where the skin being handed over sits in ITS OWN stage's list, which is not the current
	-- stage's count on the fifth step
	local entryStage = step.entry and step.entry.stage or stageIndex
	step.entryIndex = step.entry and GameConfig.GetCharacterIndex(step.entry) or stageTotal
	step.entryTotal = #GameConfig.GetCharactersForStage(entryStage)

	-- `step.cost` IS INFORMATIONAL NOW AND NOTHING GATES ON IT. An evolve costs XP and only XP -- see
	-- DNAService.HandleEvolve for why two gates on one button is one gate too many. It is still
	-- filled in because `stage.cost` doubles as the `math.huge` sentinel that marks the end of the
	-- chain, and because a tool reading it should get the answer it always did. If you are adding a
	-- check against it, you are re-adding the DNA gate.
	if stage.cost == math.huge then
		step.cost = GameConfig.FinalStageStepCost
		step.xpCost = GameConfig.FinalStageStepXp
	else
		step.cost = stage.cost
		step.xpCost = stage.xpCost
	end

	-- ===== THE VERY FIRST EVOLVE COSTS ONE KILL =====
	--
	-- Stage 1 costs 50 XP and the weakest creature in the first zone is worth exactly 1, so a new
	-- player used to be told "Click a creature to attack it" and then had to do it FIFTY TIMES
	-- before anything happened. That is the whole "the tutorial lasts too long" report: the banner
	-- is not on a timer, it is the else-branch of the XP test (see FirstJoin.stepFor), so it sat
	-- there for the entire grind.
	--
	-- Only the FIRST step is discounted -- Speck -> Amber Blob, the one the tutorial points at.
	-- Step two onwards pays the full 50, so the curve, the ramp and every stage above are untouched.
	--
	-- Gated on `TutorialDone` rather than on a new save field: the flag already exists, it is set
	-- server-side on the first successful evolve of any kind (DNAService.HandleEvolve), and both
	-- sides of the wire have it -- so the client's button and the server's charge agree without
	-- anything new having to replicate. A rebirth does not reopen it, because rebirthing is not
	-- being new.
	if stageIndex == 1 and step.entryIndex == 2 and not (data and data.TutorialDone) then
		step.xpCost = GameConfig.FirstEvolveXp
	end

	return step
end

-- WHICH STAGE THE NEXT CHARACTER ROLL BELONGS TO.
--
-- Rolls used to target whatever stage the player was standing on, which spread a collection at
-- random across all twenty lists -- a player at Star Weaver owned four characters, on stages 2, 3,
-- 11 and 12, and the Journal read as twenty rows of padlocks with no way to finish any of them.
-- The roll now fills the lists IN ORDER: every Cell character, then every Bacteria one, and so on.
--
-- Capped at the stage the player has actually reached, so it can never hand out a character from
-- a stage they have not seen; once everything up to there is complete it rolls at that stage,
-- where it can only produce duplicates until the next evolve opens a new list.
function GameConfig.GetCollectionStage(owned, currentStageIndex)
	local cap = math.clamp(currentStageIndex or 1, 1, #GameConfig.Stages)
	for stageIndex = 1, cap do
		local have, total = GameConfig.CountCharactersForStage(owned, stageIndex)
		if have < total then
			return stageIndex
		end
	end
	return cap
end

-- The plain one a stage starts you as -- its Common, the first entry in the list. Rebirth puts
-- everyone back to these; see RebirthService.
function GameConfig.GetBaseCharacterForStage(stageIndex)
	local list = CHARACTERS_BY_STAGE[stageIndex]
	return list and list[1] or nil
end

-- ============================================================================
-- CODES (Phase 5.1)
-- ============================================================================
-- The cheapest traffic channel this genre has, and the game had none. Dexerto, Gamerant and
-- Game.Guide publish a codes article for any game that has codes, refresh it monthly, and the
-- article is what people search for -- so a code is not a giveaway, it is the reason a page about
-- this game exists at all.
--
-- A CODE IS AN ARBITRARY STRING THE OWNER PUBLISHES, which is what makes this table different from
-- `RobuxProducts` and `GamePasses`: those hold ids that must be created on the dashboard first and
-- must never be invented, whereas these are made up on purpose and only become real when Kristina
-- posts them. Edit the list freely; the redeem path does not care what is in it.
--
-- Rewards use exactly the field names `DailyRewards` uses (`dna`, `diamonds`, `shards`, `potions`,
-- `potionId`) so `CodesService` grants them with the same four lines `RewardService` already does,
-- and `dna` goes through `ScaleReward` for the reason every authored figure in this game does: a
-- flat 1,000 is a fortune at stage 1 and less than one kill from stage 6 on.
--
-- `expires` is an os.time() stamp or nil for "runs forever". Checked at redeem rather than by a
-- timer, the same way `GetPotionBoost` handles its expiry -- nothing has to clean up.
GameConfig.Codes = {
	{ code = "LAUNCH",     dna = 1500, diamonds = 10, potions = 2, note = "launch day" },
	{ code = "EVOLUTION",  dna = 1000, diamonds = 5,               note = "evergreen, in the description" },
	{ code = "WELCOME",    dna = 750,  potions = 1,                note = "evergreen, for first-timers" },
	{ code = "BRAINROT",   dna = 1000, diamonds = 5,               note = "evergreen, genre search term" },
	{ code = "THANKYOU",   dna = 2000, diamonds = 15, shards = 1,  note = "milestone / apology code" },
	{ code = "LABRAT",     dna = 500,  potions = 1,  potionId = "luck_s", note = "evergreen" },
}

-- Typed by hand off a web page, so it arrives with stray spaces and whatever case the reader used.
-- Upper-cased and stripped of ALL whitespace rather than just trimmed: "launch day" and "LAUNCHDAY"
-- are the same keystrokes to a player and refusing one of them reads as a broken code.
GameConfig.CodeMaxLength = 24

function GameConfig.NormaliseCode(text)
	if type(text) ~= "string" then return nil end
	local cleaned = text:gsub("%s", ""):upper()
	if #cleaned == 0 or #cleaned > GameConfig.CodeMaxLength then return nil end
	return cleaned
end

-- Returns the entry and its normalised key, or nil. A linear scan over six rows is not worth an
-- index, and building one would be one more thing to keep in step with the table above.
function GameConfig.GetCode(text)
	local key = GameConfig.NormaliseCode(text)
	if not key then return nil end
	for _, entry in ipairs(GameConfig.Codes) do
		if GameConfig.NormaliseCode(entry.code) == key then
			return entry, key
		end
	end
	return nil
end

function GameConfig.IsCodeExpired(entry)
	return entry ~= nil and entry.expires ~= nil and os.time() >= entry.expires
end

-- ============================================================================
-- OFFLINE EARNINGS (Phase 5.2)
-- ============================================================================
-- The strongest single reason to come back, and it is safe to build here for one specific reason:
-- the idle rate is ALREADY capped in units of clicks (see the long note over
-- `DNAService.GetAutoCollectAmount`, which exists because idle income once paid eighty clicks a
-- second and broke every price in the game). Offline income is that same capped rate multiplied by
-- a bounded number of seconds, so it cannot invent a rate that playing cannot beat.
--
-- Two bounds, and they answer different questions:
--
--   * `OfflineMaxHours` bounds the WINDOW. Eight hours is a night's sleep -- long enough that
--     logging off deliberately feels rewarded, short enough that a player returning after a month
--     does not arrive holding the rest of the game.
--   * `OfflineRate` bounds the RATE against being online. At 0.5 an hour away is worth half an hour
--     idling, which keeps the ordering the auto-collect note fought for: playing beats idling, and
--     idling beats being gone.
--
-- `OfflineMinSeconds` is not a balance number, it is a UI one: without it every rejoin, every test
-- restart and every server hop pops a "welcome back" card for four seconds of absence.
GameConfig.OfflineMaxHours = 8
GameConfig.OfflineRate = 0.5
GameConfig.OfflineMinSeconds = 120

-- Seconds of absence that actually pay, given the cap. Split out so the "welcome back" card can
-- say how long it credited rather than how long the player was gone -- claiming credit for a week
-- and paying eight hours is the kind of small lie players notice immediately.
function GameConfig.GetOfflineSeconds(elapsed)
	elapsed = math.max(tonumber(elapsed) or 0, 0)
	if elapsed < GameConfig.OfflineMinSeconds then return 0 end
	return math.min(elapsed, GameConfig.OfflineMaxHours * 3600)
end

return GameConfig

