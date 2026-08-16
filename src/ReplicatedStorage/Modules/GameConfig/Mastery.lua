-- GameConfig.Mastery -- stage mastery, how speed scales with the body, and the playtime gifts.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

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

end
