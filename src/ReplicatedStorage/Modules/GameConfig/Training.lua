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
--   1. a MULTIPLIER on the player's rank, capped at x3.00,
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
	return math.clamp(math.floor(reps), 0, GameConfig.TrainingRepCap)
end

-- x1.00 at nothing, x3.00 at the cap. THE ONLY READERS ARE `DNAService.GetCombatDamage` and the
-- boss divisor that cancels it -- the same one-caller rule the blade and the level follow.
function GameConfig.GetTrainingDamageMult(data)
	return 1 + GameConfig.GetTrainingReps(data) * GameConfig.TrainingRepPct / 100
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

-- Nothing left to earn. The dummy still sparks when a capped player hits it -- a blow that produces
-- no feedback at all reads as a broken dummy -- it just pays nothing and says so once.
function GameConfig.IsTrainingCapped(data)
	return GameConfig.GetTrainingReps(data) >= GameConfig.TrainingRepCap
end

-- Whether this save may use the dummy at all. Split out rather than inlined at the call site for
-- the reason `CanFightRaised` was: the server, the client's targeting filter and the HUD all have to
-- agree, and three copies of `>=` is three chances to drift.
function GameConfig.CanUseTrainingDummy(data)
	return ((data and data.Rebirths) or 0) >= GameConfig.TrainingDummyMinRebirths
end

end
