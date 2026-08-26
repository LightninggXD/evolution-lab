-- GameConfig.Rebirth -- the rebirth curve, the four milestones and what a rebirth pays.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

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
-- ⚠️ THAT ROW IS THE FOUR-RUNG LADDER AND IS KEPT ONLY FOR THE ARGUMENT ABOVE IT, WHICH STILL
-- HOLDS. The numbers are stale: 32.7 re-tuned both constants for a twenty-rung ladder and the live
-- row is the one printed over `RebirthDamagePct` below. Read that one.
--
-- The first rebirth alone (x2.0) does not replace a full collection, and it is not meant to: the
-- collection is re-earned from kills as you climb, so the two stack back up together.
-- ===== RE-TUNED FOR TWENTY RUNGS IN 32.7, AND IT IS A REAL CUT =====
--
-- Every number in the block above was solved against a FOUR-rung ladder: 100 / 25 put the fourth
-- rebirth at x8.00, which is the figure the whole economy is written around. 32.7 made the ladder
-- twenty rungs (the gate is a level now, not a stage), and leaving these constants alone would have
-- ended it at **x116.00 damage and x31.00 income** -- which is not a rebalance, it is a different
-- game, and it is the exact `GetMutationIncomeMult` shape this repo has unwound three times.
--
-- 25 / 0.5 lands the twentieth rebirth at **x7.90 damage**, i.e. five times as many rungs each
-- worth about a fifth -- the anchor the plan set, and the same total power the four-rung ladder
-- delivered. Income follows it: 150 -> 30 puts r=20 at x7.00, unchanged from the old fourth rung.
--
-- **WHAT IT COSTS AN EXISTING SAVE, STATED BECAUSE IT IS A LOSS AND SHE APPROVED IT KNOWING THAT.**
-- A rebirth count is worth less than it was: r=4 goes x8.00 -> x2.06, r=8 goes x23.00 -> x3.28.
-- Nothing is TAKEN from the save -- `Rebirths` is untouched and every one still counts -- but the
-- multiplier a count buys is smaller, because a rung on a twenty-rung ladder is a smaller thing
-- than a rung on a four-rung one. What replaces it: those saves now have sixteen or twelve rungs
-- LEFT to spend instead of none, plus the level ladder (x4.80 at the last gate) and the sword
-- (x5.00), neither of which existed when 100 / 25 were chosen. (Measured off the live HUD on
-- 2026-08-23: her save reads `Rebirths = 4`, not the 8 an older note in this repo claims.)
--
-- THE CURVE IS STILL QUADRATIC, and the 9.2 argument for that is unchanged: the last zones are the
-- hardest by a long way, so a flat per-rung bonus falls further behind every run. It is simply much
-- flatter now, because twenty accelerating rungs compound where four did not.
--
--   1 -> x1.25    2 -> x1.51    4 -> x2.06    8 -> x3.28    14 -> x5.01    20 -> x7.90
GameConfig.RebirthDamagePct = 25         -- the linear term, per rebirth
GameConfig.RebirthDamageAccelPct = 0.5   -- the quadratic term, what makes each one worth more

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
-- ===== AND SINCE 32.6 THE SWORD IS CANCELLED HERE TOO =====
--
-- The paragraph above says only the rebirth term is cancelled, and the sword joining it is not a
-- change of mind -- it is the same test applied to a second term that passes it. The four
-- multipliers 14.1 deliberately left ALONE are each bounded and each gated on something other than
-- time: Stage Mastery caps at x3.4 the moment you reach stage 20, the pets and the passes cap at
-- what is on sale. The weapon ladder is not like those. It is x5.00, always on, bought with a
-- currency whose only limit is how long you farm, and every player will end the game holding the
-- last blade -- which is the exact shape of the rebirth term, and the exact shape this divisor was
-- built for.
--
-- Without this line the phase ships twenty trivial bosses. Measured against the reading 14.1 took:
-- the endgame stack was x166.6 with the rebirth term (x23 at eight rebirths) cancelled out of it,
-- leaving a ~21-blow fight. An uncancelled x5 makes that ~4 blows -- back inside the "died on the
-- first blow" band this function exists to have fixed.
--
-- **WHAT IT COSTS, STATED SO IT IS A DECISION AND NOT A DISCOVERY:** the sword shortens every
-- creature fight in the game by its full amount and shortens a boss fight by nothing. If she would
-- rather feel the blade on a boss, deleting the second factor below is the whole reversal -- and
-- the boss curve then has to be re-tuned against it, which is 32.7's job and not a one-liner.
-- ===== AND SINCE 32.7 THE LEVEL IS CANCELLED HERE TOO =====
--
-- Third term, same test, and it passes it for the same two reasons the blade did: it is always on,
-- and its ceiling is time rather than money -- every player who keeps playing ends a run holding
-- the whole of it. The level term is x1.00 at level 1 and x4.80 at the last rebirth gate (77), so
-- an uncancelled one would take the endgame boss fight this function exists to have fixed and cut
-- it by another four fifths, on top of the blade.
--
-- **THIS IS THE ONE LINE PHASE 32 TURNS ON**, and it is worth saying plainly why: boss health is
-- DERIVED from a bare player (`BossTargetHits x GetZoneReferenceDamage`, pure rank) and learns
-- about no multiplier anybody owns. Every term added to the player's stack without being added
-- here is a boss the phase quietly deletes.
--
-- It costs exactly what the other two cost, stated so it is a decision and not a discovery: a
-- level shortens every creature fight in the game by its full amount and shortens a boss fight by
-- nothing. Deleting a factor below is the whole reversal, and the boss curve then has to be
-- re-tuned against whatever is left.
function GameConfig.GetBossDamageDivisor(data)
	-- >= 1 for every rebirth count, every blade and every level, so this can never turn a blow
	-- into a heal
	return math.max(GameConfig.GetRebirthDamageMult(data)
		* GameConfig.GetSwordDamageMult(data)
		* GameConfig.GetLevelDamageMult(data)
		-- FOURTH TERM (33.21), and it passes the same test the three above it pass: the training
		-- ladder is always on, its ceiling is TIME rather than money, and every player who keeps
		-- playing ends a run holding the whole of it. x1.00 untrained and x3.00 at the cap, so an
		-- uncancelled one would cut the endgame boss fight this function exists to have fixed by
		-- two thirds -- on top of the blade and the level.
		--
		-- It is also the line that lets 33.21 ship WITHOUT the mob rebalance its own row demanded.
		-- Training is a uniform multiplier, so creatures keep their flat blows-to-fell across all
		-- twenty zones and simply fall three times faster; cancelling it here means the boss curve
		-- never moves, so `MobDepthGrowth` and `mobHealthMult` are untouched by the whole feature.
		* GameConfig.GetTrainingDamageMult(data), 1)
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
-- ===== TWENTY RUNGS SINCE 32.7, AND THE GATE IS A LEVEL (see `GameConfig.Levels`) =====
--
-- It was `MaxRebirthTier`, i.e. one rung per five stages, four in total -- and that number was
-- forced by the gate rather than chosen: a stage requirement cannot carry more rungs than there
-- are stages, and a rebirth resets the stage, so two rungs could never sit inside one band. A
-- LEVEL gate has no such problem. The level is its own axis, it also resets, and each rung simply
-- asks for a higher one -- which is exactly how the `+1` family does it.
--
-- `MaxRebirthTier` is deliberately NOT this number and has not moved. It still means "one per five
-- stages" and it is what the Rebirth Shrine builds its FOUR monuments from, one standing in each
-- of zones 5 / 10 / 15 / 20. The two were the same number for as long as the gate was a stage;
-- they are two different facts now and conflating them again would put twenty statues on the map.
GameConfig.MaxRebirths = 20

-- The milestone this save may use next, or nil when the ladder is finished. Everything else about
-- rebirth availability is derived from this one function, so the HUD, the shrine and the server can
-- never disagree about which statue is live.
function GameConfig.GetNextRebirthTier(data)
	local done = (data and data.Rebirths) or 0
	if done >= GameConfig.MaxRebirths then return nil end
	return done + 1
end

-- The stage that milestone USED to be gated behind (5, 10, 15, 20), or nil when there is none
-- left. 32.7 moved the gate onto the level (`GetNextRebirthLevel`) and this is no longer asked by
-- anything that decides whether a rebirth may happen -- it survives because it is still the right
-- answer to a different question: which of the four shrine monuments stands for a tier, and which
-- creature's statue that is. `RebirthService`'s notify payload carries it for the same reason.
function GameConfig.GetNextRebirthStage(data)
	local tier = GameConfig.GetNextRebirthTier(data)
	return tier and GameConfig.GetRebirthTierStageIndex(tier) or nil
end

-- The single question the button asks. Returns `false, reason` so the UI never has to reconstruct
-- why it is locked out of the numbers.
--
-- THE REASON CHANGED FROM "stage" TO "level" IN 32.7 and the shape did not, which is what kept
-- that change to one line here: every caller in the game takes only the first return value
-- (`(GameConfig.CanRebirthNow(data))`, parenthesised, in RebirthService, MainUI, RebirthPanel and
-- RebirthShrineClient alike), so nothing switches on the string and nothing had to be repaired.
function GameConfig.CanRebirthNow(data)
	local tier = GameConfig.GetNextRebirthTier(data)
	if not tier then return false, "done" end
	if GameConfig.GetLevel(data) < GameConfig.RebirthLevelFor(tier) then
		return false, "level"
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
-- Linear against damage's accelerating curve, on purpose: income is the currency the
-- upgrades, eggs and shops run on and it is already geometric in the stage, while damage is the one
-- thing the late zones are actually short of. TWENTY rebirths therefore end at x7 income and x8
-- damage.
-- 150 -> 30 IN 32.7, for the reason written over `RebirthDamagePct`: the ladder went from four
-- rungs to twenty, and 150 would have ended it at x31.00 income. 30 puts the twentieth rung at
-- **x7.00**, which is exactly where the old fourth rung landed -- so the end of the ladder is worth
-- what it always was, and it is reached in twenty steps instead of four.
GameConfig.RebirthIncomePct = 30

function GameConfig.GetRebirthIncomeMult(data)
	local r = (data and data.Rebirths) or 0
	return 1 + r * GameConfig.RebirthIncomePct / 100
end

end
