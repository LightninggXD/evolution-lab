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
-- outruns the ground they are running on. Jump is capped for a different reason, below.
--
-- ===== THE JUMP CAP CAME 92 -> 60 (2026-08-17), AND THE CAP IS THE ONLY THING THAT MOVED =====
--
-- `BaseJumpPower` is still 44 and the Mastery bonus is still +1.2 a stage, so NOTHING below the
-- top of the curve changes: a stage-one body jumps its authored 4.9 studs exactly as before. The
-- cap is what a max-stage player actually lands on -- (44 + 24) * sizeMult^0.5 reaches 132 at
-- scale 5, i.e. every late player was pinned to the ceiling and the ceiling was the whole spec.
--
-- 92 is 21.6 studs of apex (`power^2 / (2 * 196.2)`), which is what the owner reported as "I can
-- jump onto everything". It was also never the number this file's own comment three lines up
-- describes: BaseJumpPower's note says the top stage should clear "about 11" studs, which is a cap
-- of 66. 60 lands at 9.2 studs -- over the 6-stud podium and the 3-stud plaza deck with room, under
-- anything that is meant to be climbed.
--
-- IT IS ALSO A HORIZONTAL FIX, which is the half that is easy to miss. Air time is `2 * power /
-- gravity`, and a top-stage body runs at 280 studs/second WITH THAT SPEED CARRIED INTO THE AIR --
-- so 92 bought 0.94 s of flight and 263 studs of ground per jump, most of a platform. 60 is 0.61 s
-- and 172 studs. The rest of that distance is walk speed, not jump, and is deliberate.
--
-- Still nowhere near the 180-stud zone walls -- a jump that clears a boundary drops the player into
-- the gap between two platforms, where there is no floor at all -- and still well under the 26-stud
-- terrace riser that `ZoneTerrain` sets as its floor so the climb cannot be skipped.
--
-- THE BODY SCALE CURVE WAS HALVED at the same time: GameConfig.Stages[].scale now runs 1.0 -> 5.0
-- where it used to run 1.0 -> 9.0. A late-stage player was tall enough that a whole platform read
-- as a small room, and every prop beside them looked like furniture in a doll's house. The growth
-- is still monotonic and every evolve is still visible; it is the top of the curve that came down.
--
-- ===== AND 60 -> 52 (2026-08-17, same day, second report) =====
--
-- "i dalje previsoko skacem". Measured on the live character rather than argued about: a max-stage
-- body was sitting at exactly `MaxJumpPower`, so the cap IS the jump for anyone past roughly stage
-- eight and the only number worth moving is this one.
--
--   60 -> 9.17 studs of apex, 0.61 s of air
--   52 -> 6.89 studs of apex, 0.53 s of air
--
-- **6.89 is chosen against the tallest thing a player must get on top of, which is the 6-stud
-- podium** -- see the list in `BaseJumpPower`'s note above (plaza deck 3, podium 6, shop steps 2).
-- It clears that by 0.89 studs and clears everything else by a lot, and it is the lowest cap that
-- still does. Going further means a player cannot mount their own podium, which is a bug rather
-- than a tuning choice, so **52 is the floor: do not lower this without first lowering the podium.**
--
-- The 26-stud terrace riser in `ZoneTerrain` is untouched and is now 19 studs clear rather than 17.
-- Nothing else in the game reads this.
GameConfig.SpeedScaleExponent = 0.82
GameConfig.MaxWalkSpeed = 150
GameConfig.MaxJumpPower = 52

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
-- Measured against ONE SITTING: the clock starts when the player connects and is thrown away when
-- they leave. The claim set is day-stamped and persisted (see PlaytimeGiftService) so rejoining is
-- not a faucet -- but that is also exactly why this ladder alone serves nobody who plays in short
-- visits: a 20-minute session takes the 10 and the 20, and the third visit of the day finds every
-- rung it can reach already spent. `DailyPlaytimeGifts` below is the answer to that, not a
-- replacement for this one -- a long sitting is worth rewarding on its own terms.
GameConfig.PlaytimeGifts = {
	{ minutes = 10, dna = 1000 },
	{ minutes = 20, dna = 2500,  potions = 1, potionId = "dna_s" },
	{ minutes = 30, dna = 6000,  potions = 1, potionId = "xp_m" },
	{ minutes = 45, dna = 15000, diamonds = 1 },
	{ minutes = 60, dna = 35000, potions = 1, potionId = "luck_l", diamonds = 2 },
}

-- ===== THE DAILY PLAYTIME LADDER (21.3) =====
--
-- The same shape, measured against **every minute played today added together**, across as many
-- sessions as it takes. The accumulator lives in the save (`data.DailyPlaytime`) and is stamped
-- with the same UTC day the claim sets use, so it resets once a day and never on a rejoin.
--
-- WHY THE RUNGS START WHERE THE SESSION LADDER'S SECOND ONE DOES. This ladder has to be reachable
-- by the player the row was opened for -- three twenty-minute visits -- and unreachable by accident
-- in a single short one, or it is just the session ladder paying twice for the same ten minutes.
-- 30 minutes is the first rung the fragmented player clears and the first the session ladder can no
-- longer hand them, and the top two rungs are past anything one sitting is expected to reach.
--
-- WHY THE DNA IS BIG AND THE DIAMONDS ARE NOT, which is the same line 21.2 drew on the daily board:
-- `dna` runs through `GameConfig.ScaleReward`, so it is authored in stage-1 clicks and is worth the
-- same fraction of an hour's income at stage 1 and at stage 20. Diamonds and potions are FLAT and
-- aimed at fixed sinks -- a Mega Income level costs 25 and never moves. Four hours of roaming
-- already pays about a thousand diamonds off kills alone (see the measurement in GameConfig.
-- Diamonds), so the three here are a garnish on the card, not a source, and they are deliberately
-- the same three the session ladder pays rather than a second faucet of a different size.
GameConfig.DailyPlaytimeGifts = {
	{ minutes = 30,  dna = 3000 },
	{ minutes = 60,  dna = 8000,   potions = 1, potionId = "dna_m" },
	{ minutes = 120, dna = 25000,  diamonds = 1 },
	{ minutes = 180, dna = 60000,  potions = 1, potionId = "luck_l" },
	{ minutes = 240, dna = 150000, potions = 1, potionId = "xp_l", diamonds = 2 },
}

-- ===== THE DAILY LADDER HAS NO TOP (21.4) =====
--
-- 21.4 asks the game to GUARANTEE unfinished business at the moment a session ends -- a bar over
-- 80%, a pending reward, or a running timer -- because that is what decides whether there is a
-- tomorrow. Two of those three cannot be guaranteed honestly: an evolve bar is wherever the player
-- left it, and the daily reward and the free spin are both once per UTC day, so a player who swept
-- the board in their first minute has nothing pending for the next twenty-three hours.
--
-- THE THIRD ONE CAN BE, AND BY CONSTRUCTION RATHER THAN BY A SPECIAL CASE. The ladder above is a
-- clock every player is already on, all day, whether or not they ever open the panel -- but it
-- STOPS at 240 minutes, and a ladder that stops is a countdown that stops. Past four hours the
-- panel showed five grey `DONE` cards and nothing else: the one player who had given the game the
-- whole day was the one player it had stopped asking anything of.
--
-- So the last rung repeats, on the hour, for ever. This is the same line 21.2 drew on the daily
-- board -- a ladder with no top is a promise the economy cannot keep, so the top REPEATS rather
-- than climbing -- and it is drawn here for the same reason: there is always exactly one rung
-- ahead, and it is never more than an hour away.
--
-- WHY THE REPEAT PAYS LESS THAN THE RUNG IT FOLLOWS, WHICH IS THE LOAD-BEARING NUMBER. The
-- authored five are a CLIMB: 3K, 8K, 25K, 60K, 150K, which is 1,500 a minute at the top against
-- 100 a minute at the bottom. Continuing that curve hourly would pay a marathon player more per
-- hour than the ladder's own summit, for ever, off a clock that needs no skill and no risk. So the
-- repeat FLATTENS: it pays 25,000 -- the two-hour rung's figure, the middle of the ladder and not
-- its end -- and it pays it in DNA only.
--
-- MEASURED RATHER THAN ASSERTED, and the first draft of this comment was wrong about it. An hour of
-- play is worth roughly 18,720 stage-1 clicks (a 4/s cadence for 14,400, plus auto-collect at the
-- 1.2 clicks/s cap `DNAService.GetAutoCollectAmount` enforces, for 4,320), so 25,000 is **1.335x an
-- hour's income** -- not the garnish this note first called it. It is still the right number, for
-- the reason the ratios give: it is **1/6 of the top rung** (0.1667, and identical at stage 1, 10
-- and 20, because `ScaleReward` is a clean multiplier), while the authored five have ALREADY paid
-- 246,000 by the four-hour mark against the 74,880 clicks those four hours are worth -- 3.3x. So
-- the repeat is well below the rate the ladder itself runs at when it hands over, and far below the
-- 8x the top rung alone pays. Twelve straight hours adds 200K, less than one and a half of that
-- single rung. What flattening buys is that the rate stops CLIMBING, which is the only part that
-- could not have been left alone.
--
-- AND NO DIAMONDS, NO POTIONS, deliberately. Both are FLAT and aimed at fixed sinks -- the line 1.1
-- drew when it kept them out of `ScaleReward`, and 21.2 and 21.3 both restated. A flat 2 diamonds
-- an hour for ever is a faucet capped by nothing but the calendar; DNA scales with the player and
-- is the only one of the three that can repeat without repricing something.
--
-- THE SESSION LADDER DELIBERATELY DOES NOT REPEAT. Those are the same minutes this ladder is
-- already counting, and an endless rung on both clocks bills one hour of play twice. One endless
-- countdown is what the guarantee needs; two is a second faucet bought for nothing.
GameConfig.DailyPlaytimeRepeat = { everyMinutes = 60, dna = 25000 }

--- THE ONLY WAY TO TURN AN INDEX INTO A DAILY RUNG, and it is a function rather than a longer list
--- because the list is now infinite. The five authored rungs come back as themselves; everything
--- past them is synthesised from `DailyPlaytimeRepeat`, so the server that pays a rung and the
--- panel that advertises it cannot disagree about what the sixth one is. Same rule `GetDailyReward`
--- carries for the login board: the day-index arithmetic written out by hand in five places was a
--- board that promised what the server did not pay.
---
--- Returns nil for anything that is not a whole number at or above 1 -- this is reached from a
--- RemoteEvent argument. There is no upper bound and there must not be one: the gate on a claim is
--- the CLOCK, in `PlaytimeGiftService.HandleClaim`, so a rung at 900 minutes is simply one nobody
--- will ever have played long enough to take.
function GameConfig.GetDailyPlaytimeGift(index)
	index = tonumber(index)
	if not index or index < 1 or index % 1 ~= 0 then return nil end
	local list = GameConfig.DailyPlaytimeGifts
	if index <= #list then return list[index] end
	local rep = GameConfig.DailyPlaytimeRepeat
	-- Built fresh on each call rather than memoised into a growing table: this is read once a
	-- second by one panel and once per claim by the server, and a cache keyed by an unbounded index
	-- is a table with no reason ever to stop growing.
	return {
		minutes = list[#list].minutes + (index - #list) * rep.everyMinutes,
		dna = rep.dna,
		-- Marks the synthesised rungs for the panel, which titles and describes them differently:
		-- the climb is over and this one is a metronome, and saying so is more honest than drawing
		-- a sixth card that pretends to be a sixth step.
		repeating = true,
	}
end

end
