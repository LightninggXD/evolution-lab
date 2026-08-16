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
