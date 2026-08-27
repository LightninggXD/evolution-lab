-- GameConfig -- THE TRAINING LADDER (33.21)
--
-- ===== WHAT THIS IS, AND THE FORK IT ANSWERS =====
--
-- The owner asked for the `+1 Strength` loop the charts are full of: a punching dummy you stand at
-- and a damage number that climbs while you hit it -- *"ovde ce biti +1 damage, a damage dobijas kad
-- tuces mobove i udaras ovaj dummy (dummy ce zahtevati 1 rebirth i davati dupli damage playeru dok
-- trenira)"*.
--
-- Roadmap 33.21 held that request open for a day on ONE question, because the request does not
-- answer it: does the dummy pay a PERMANENT damage stat, a SESSION buff, or mastery XP -- and what
-- does it cost? A one-time reward in a one-time secret that scales every later fight is not a
-- training dummy, it is a free rebirth. She answered it on 2026-08-27, and this file is that answer:
--
--   1. a MULTIPLIER on the player's rank, x3.00 at 1,000 reps -- and since 33.32 that number is
--      a KNEE rather than a cap: the ladder keeps climbing past it, +0.55 a doubling, for ever,
--   2. RESET by a rebirth, with the fill rate climbing +50% per rebirth,
--   3. and the dummy itself gated behind 1 rebirth, paying double what a creature pays.
--
-- ===== WHY A MULTIPLIER ON RANK IS THE ONE SHAPE THAT NEEDS NO MOB REBALANCE =====
--
-- She named the consequence herself in the same breath -- *"sto znaci da ce mobovi na ostali
-- stagevima morati biti jaci"* -- and she was right about the general case. A flat additive stat
-- WOULD force it: `base + reps` swamps `GetRankDamage` at the bottom of the strip and vanishes at
-- the top, so every zone would have to be re-measured, and `evolution-lab-mob-depth-curve` records
-- what happens when a factor lands in the wrong place -- the damage ladder climbs 1.076^5 = 1.4425
-- a zone and `mobHealthMult` climbs 1050^(1/19) = 1.442 a zone, and those two were tuned to be
-- IDENTICAL on purpose. Blows-to-fell is flat from Forest to the Absolute Plane by construction.
--
-- A uniform multiplier preserves exactly that. It scales all twenty zones by the same number, so
-- the property the tuning exists to protect survives untouched: `MobDepthGrowth` and
-- `mobHealthMult` are NOT changed by this feature, and nothing in this file reads a zone.
--
-- ===== AND IT IS CANCELLED AGAINST BOSSES, WHICH IS THE OTHER HALF OF THAT =====
--
-- `GetBossDamageDivisor` divides this term straight back out, beside the blade, the level and the
-- rebirth count. The reason is written out over that function and applies here without amendment:
-- boss health is DERIVED from a bare player (`BossTargetHits x GetZoneReferenceDamage`, pure rank)
-- and learns about no multiplier anybody owns, so every term added to the player's stack without
-- being added there is a boss the feature quietly deletes.
--
-- So a creature feels the whole x3.00 and a boss feels none of it. That is the split that lets this
-- ship without the mob half 33.21 demanded: training makes the farm three times faster and leaves
-- every boss fight exactly as long as it was.
--
-- IF THE MEASUREMENT SAYS TRAINED PLAY IS TOO FAST, THE DIAL IS `TrainingRepPct`. Never the mob
-- curve -- see the memory above for why a depth factor moved to compensate inverts the boss.

return function(GameConfig)

-- ===== THE CURVE =====
--
-- 0.2% a rep against a cap of 1000 is x1.00 -> x3.00, and the two numbers are one decision: the
-- product is the ceiling and the cap is how long it takes to get there. x3.00 was chosen to sit
-- level with the two multipliers already in the game that are always on and cost nothing per use --
-- the 2x Damage pass stacked with VIP is exactly x3.00 -- so a fully trained free player stands
-- where a paying one does, which is the bound this game holds its passes to.
GameConfig.TrainingRepPct = 0.2
GameConfig.TrainingRepCap = 1000

-- ===== 33.32 -- THE CAP BECAME A KNEE, AND WHY THAT IS NOT A NUDGE =====
--
-- The owner hit the ceiling above and refused it in the same sentence she refused the gold bar:
-- *"dmg konstanto treba rrasti, sto znaci da ostali leveli traju biti dosta dosta tezi"*. A ladder
-- that answers "nothing left to earn" is the one thing this feature may not say.
--
-- **THE CAP WAS 33.21's WHOLE SAFETY ARGUMENT, so removing it outright was refused.** Everything
-- written above still holds: `MobDepthGrowth` (1.076^5 = 1.4425 a zone) and `mobHealthMult`
-- (1050^(1/19) = 1.442 a zone) were tuned to cancel, blows-to-fell is flat across all twenty zones
-- by construction, and an UNBOUNDED multiplier against that bounded pair ends with every mob in the
-- game dying in one blow -- see [[evolution-lab-mob-depth-curve]].
--
-- So the ladder is LINEAR to the knee and LOGARITHMIC after it. `TrainingRepCap` is no longer a
-- ceiling; it is the point the shape changes at, and the number it produces there -- x3.00 -- is
-- unchanged, so no save that reached it loses anything and the boss divisor keeps cancelling the
-- same term it always did.
--
-- Each DOUBLING of the reps past the knee adds `TrainingSoftStep`:
--
--     1,000 reps  x3.00        16,000 reps  x5.20
--     2,000 reps  x3.55        64,000 reps  x6.30
--     4,000 reps  x4.10       262,144 reps  x7.40
--     8,000 reps  x4.65     6,656,000 reps  x10.00
--
-- The number therefore ALWAYS moves -- which is what she asked for, literally -- and the mob curves
-- are still not touched, which is what 33.21 promised. Doubling is the right unit because the reps
-- themselves arrive linearly (1 a kill, 2 a blow on the dummy, times the rebirth rate), so a
-- doubling costs as much again as everything banked so far: the tail is unreachable in a lifetime
-- of play rather than forbidden by a clamp, and that is the difference between (c) and (a) on the
-- fork she picked.
--
-- 0.55 is a quarter of the linear rate measured across the first doubling past the knee (linear
-- would pay +2.00 over 1,000 -> 2,000). It was picked against the SAME bound x3.00 was: the pass
-- stack. A free player who grinds four doublings stands at x4.65, still inside the x3.00 pass
-- ceiling times the 1.55 a single zone of depth pays, so the passes are not devalued by a grind.
GameConfig.TrainingSoftStep = 0.55

-- The only true ceiling left, and it exists for the save rather than for the design: a corrupt or
-- hand-written `TrainingReps` must not be able to produce an infinity that reaches the damage
-- formula. At 1 rep a kill it is roughly six million kills away, which is to say it is never met.
GameConfig.TrainingRepMax = 10000000

-- ===== THE FILL RATE, AND WHY THE RESET IS NOT A PUNISHMENT =====
--
-- A rebirth wipes the reps (see `RebirthService`, beside `data.Level`), under this repo's standing
-- rule: everything bought with Diamonds is kept, everything climbed to is reset. Training is
-- climbed to.
--
-- On its own that would make every run's first hour identical, which is the flaw in a reset. So the
-- RATE climbs instead: +50% a rebirth, uncapped, against a fixed ceiling. Run one fills 1000 reps
-- at one rep a kill; run five fills the same 1000 at three. The ladder is therefore the same shape
-- as `GetRebirthXpMult` (32.22) rather than a new idea -- a rebirth buys you back the time it cost.
GameConfig.TrainingRebirthGainPct = 50

-- What each source pays before the rate above is applied. The dummy is DOUBLE the creature, which
-- is her spec word for word (*"davati dupli damage playeru dok trenira"*) and is what makes walking
-- to the grotto worth the trip rather than a flavour detour.
GameConfig.TrainingMobReps = 1
GameConfig.TrainingDummyReps = 2

-- The dummy's door, also hers (*"dummy ce zahtevati 1 rebirth"*). It is enforced server-side on
-- every blow and published as a `MinRebirths` attribute for the client, which is the same two-sided
-- shape the raised creatures use -- see `GameConfig.CanFightRaised`, whose client half in
-- `CombatClient` reads that attribute and already refuses to auto-target anything it locks.
GameConfig.TrainingDummyMinRebirths = 1

-- The head start for finding the grotto at all. It replaced the Godly mutation that used to sit on
-- the plinth: the owner cut that on 2026-08-27 (*"bez godly mutacije tu"*), and a free top-tier
-- mutation was always the odd one out in a room whose whole purpose is now a stat you grind. This
-- pays the same currency the room teaches, once, and a rebirth takes it back with the rest.
GameConfig.SecretTrainingReps = 50

-- ===== THE ACCESSORS =====

-- Clamped on the way OUT, not on the way in, and that is deliberate: it means a save that predates
-- this feature (nil), a save a probe wrote by hand, a string, and a number past the cap all answer
-- the same safe thing, and no migration has to run over any of them. `tonumber` first is the house
-- pattern against a string or a NaN in a save -- see `GetRebirthXpMult`.
function GameConfig.GetTrainingReps(data)
	local reps = tonumber(data and data.TrainingReps) or 0
	-- a NaN fails every comparison, so `math.clamp` would hand it straight back
	if reps ~= reps then return 0 end
	-- 33.32: the clamp is `TrainingRepMax`, not `TrainingRepCap`. The cap is a knee in the curve
	-- now and reps run past it; the only thing still clamped here is a save that cannot be trusted.
	return math.clamp(math.floor(reps), 0, GameConfig.TrainingRepMax)
end

-- x1.00 at nothing, x3.00 at the knee, and +0.55 a doubling for ever after (33.32). THE ONLY
-- READERS ARE `DNAService.GetCombatDamage` and the boss divisor that cancels it -- the same
-- one-caller rule the blade and the level follow, and it is what keeps a boss fight the length it
-- was no matter how far this tail is climbed.
function GameConfig.GetTrainingDamageMult(data)
	local reps = GameConfig.GetTrainingReps(data)
	local knee = GameConfig.TrainingRepCap
	local kneeMult = 1 + knee * GameConfig.TrainingRepPct / 100
	if reps <= knee then
		return 1 + reps * GameConfig.TrainingRepPct / 100
	end
	-- `math.log(x, 2)` rather than `math.log2`: the latter does not exist in Luau.
	return kneeMult + GameConfig.TrainingSoftStep * math.log(reps / knee, 2)
end

-- How far this save is through the band it is in -- 0..1 -- so a bar can draw a ladder that has no
-- end. Below the knee that is the old `reps / cap`; above it, it is the progress to the NEXT
-- doubling, which is the only fraction that stays honest when the denominator keeps moving.
-- Returned with the band's two edges so a caption can print them without recomputing the split.
function GameConfig.GetTrainingBand(data)
	local reps = GameConfig.GetTrainingReps(data)
	local knee = GameConfig.TrainingRepCap
	if reps < knee then
		return reps / knee, 0, knee
	end
	-- the band [knee*2^n, knee*2^(n+1)) this rep count falls in
	local n = math.floor(math.log(reps / knee, 2))
	local low = knee * 2 ^ n
	local high = low * 2
	return (reps - low) / (high - low), low, high
end

-- How fast this save fills. Linear in the rebirth count, exactly as `GetRebirthIncomeMult` and
-- `GetRebirthXpMult` are, so all three read the same way at a glance.
function GameConfig.GetTrainingGainMult(data)
	local r = tonumber(data and data.Rebirths) or 0
	if r ~= r or r < 0 then r = 0 end
	return 1 + r * GameConfig.TrainingRebirthGainPct / 100
end

-- ===== THE GAIN IS AN INTEGER, AND THAT IS A DESIGN CONSTRAINT RATHER THAN A TIDINESS ONE =====
--
-- The number this returns is ALSO the number that floats over the target in the world -- one value,
-- one popup, no second computation anywhere. A `+1` drawn over a credit of 1.5 is precisely the
-- class of lie `evolution-lab-feedback-placement` exists to stop, and it compounds invisibly: a
-- fractional bank makes the HUD's "412 / 1000" disagree with the save by an amount that grows all
-- run.
--
-- So it rounds half-UP and floors at 1. The cost is stated rather than discovered: at one rebirth a
-- creature kill pays 2 instead of 1.5, which is 33% generous at exactly one rung and exact at every
-- other. The dummy, which is what this row is about, is clean the whole way -- 2, 3, 4, 5 ... 22 at
-- rebirth 20.
function GameConfig.GetTrainingGain(data, baseReps)
	local gain = (tonumber(baseReps) or 0) * GameConfig.GetTrainingGainMult(data)
	return math.max(1, math.floor(gain + 0.5))
end

-- Nothing left to earn -- which, since 33.32, is a state no player reaches by playing: it is the
-- save-integrity ceiling, six million kills up. The dummy still sparks when a capped player hits it
-- -- a blow that produces no feedback at all reads as a broken dummy -- it just pays nothing and
-- says so once. KEPT rather than deleted because three call sites ask the question, and a feature
-- with no terminal state is exactly where an unbounded number gets into a save.
function GameConfig.IsTrainingCapped(data)
	return GameConfig.GetTrainingReps(data) >= GameConfig.TrainingRepMax
end

-- The knee is still a MOMENT even though it is no longer a wall: it is where the ladder visibly
-- changes gear, and it is the last point the HUD can print a finish line at. `TrainingDummyService`
-- pushes the save and says so once when a blow crosses it, the same way it used to at the cap.
function GameConfig.IsTrainingSoftCapped(data)
	return GameConfig.GetTrainingReps(data) >= GameConfig.TrainingRepCap
end

-- Whether this save may use the dummy at all. Split out rather than inlined at the call site for
-- the reason `CanFightRaised` was: the server, the client's targeting filter and the HUD all have to
-- agree, and three copies of `>=` is three chances to drift.
function GameConfig.CanUseTrainingDummy(data)
	return ((data and data.Rebirths) or 0) >= GameConfig.TrainingDummyMinRebirths
end

end
