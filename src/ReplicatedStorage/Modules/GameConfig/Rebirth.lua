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

end
