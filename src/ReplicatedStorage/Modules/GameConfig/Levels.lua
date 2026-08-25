-- GameConfig.Levels -- the level ladder: what fills it, what it is worth, and what it unlocks.
--
-- ONE OF THE PARTS OF `GameConfig` (18.9). It is handed the shared config table and writes into
-- it; see the loader in `GameConfig` itself for why the order of the parts is load-bearing.
-- Appended LAST, after `Swords`, and for the same reason that one was: it reads nothing off the
-- table at load time (every constant here is literal), and nothing above it reads
-- `GameConfig.MaxLevel` at load time either. The functions that quote other parts --
-- `GetLevelXpForDamage` calls `GetZoneReferenceDamage` (from `Evolution`), and `Rebirth`'s boss
-- divisor and rebirth gate quote `GetLevelDamageMult` / `RebirthLevelFor` from here -- are called
-- at RUNTIME, never while the table is still being built.

return function(GameConfig)

-- ===== HER DECISION, QUOTED =====
--
-- *"moze 1 ali da ne bude cena vec da uvedemo da se skuplja level pa tipa level brze dobijas sto
-- vise damagea radis ... takodje onda bi se trebao vise ravnopravni sistem ... da ne bude prelagano
-- da se predje"* -- a rebirth stops being a stage you reach and becomes a LEVEL you climb, the
-- level fills from the damage you deal, and the curve is what stops it being too easy.
--
-- The `+1` family (`+1 Speed Evolve`, `+1 Speed Keyboard Escape`) is one consistent shape and it
-- is the shape copied here: the counter fills from the core verb itself, a rebirth resets the
-- counter and pays a permanent multiplier, and **the rebirth gate is a level, not a stage**. That
-- last one is what makes twenty rungs possible at all: two rebirths inside one stage band cannot
-- both be gated on that stage, because a rebirth RESETS the stage. A level is its own axis, it
-- also resets, and each rung simply asks for a higher one.
--
-- ===== WHAT FILLS THE BAR, AND WHY IT IS NORMALISED =====
--
-- Damage dealt -- her *"sto vise damagea radis"* literally -- but **divided by what a bare player
-- standing in that zone hits for** (`GetZoneReferenceDamage`, the same yardstick the bosses are
-- priced against). One blow from a player with no bonuses at all is worth exactly 1 XP, anywhere
-- on the strip.
--
-- THE DIVISION IS THE WHOLE DESIGN AND IT IS NOT A DETAIL. Raw damage dealt spans a factor of
-- roughly a MILLION between a fresh save in Forest and a geared one on the Absolute Plane -- the
-- bare ladder alone is x1394 (`GetRankDamage` 1 -> 100) and the bought stack multiplies that
-- again. A level curve fed raw damage is therefore either unreachable in Forest or instant in
-- zone 20, and no single geometric cost curve can be both. Normalised, the reward and the
-- yardstick move together and the ladder means the same thing in every zone -- which is exactly
-- the relationship `XpPerLevelGrowth` already has with `zone.mobXpMult` on the EVOLVE bar, and the
-- same property `GetRankDamage` was tuned to protect: **kills per creature are flat across all
-- twenty zones.**
--
-- WHAT THAT MAKES A KILL WORTH: the XP for a whole creature is the damage it absorbed over its
-- zone's reference, i.e. **the number of blows it takes a bare player to fell it** -- ~2.4 for a
-- Swarmer, ~6 for a Critter, ~14 for a Brute -- times the zone bonus below. A zone boss is
-- `BossTargetHits` (150) times the same bonus. The blow that overkills is worth only the health
-- that was actually there, because the award is taken from the health the target LOST and not from
-- the swing -- so there is no "hit the weakest thing in the game with the biggest number" farm.
--
-- ===== AND A DEEPER ZONE PAYS MORE, WHICH IS HER CORRECTION AND NOT A REFINEMENT =====
--
-- The first cut of this file normalised and stopped, so a kill was worth the same everywhere. She
-- played it and reported the exact hole that leaves: *"leveli se jako tesko dobijaju posle. veca
-- zona mora davati vise xpa valjda za level"* -- the levels get very hard later, a bigger zone has
-- to pay more XP. She is right, and the reason is arithmetic rather than feel: the COST curve is
-- geometric in the level while a flat payout is constant, so kills-per-level climbs forever and the
-- ladder stops being a ladder somewhere around level 60. Nothing a player does in the late game
-- could move it, which is the opposite of "go deeper".
--
-- `LevelZoneGrowth ^ (i - 1)`, and the constant is DERIVED rather than picked: it is
-- `LevelXpGrowth ^ 3` (1.10^3 = 1.331), i.e. one zone deeper is worth exactly what three more
-- levels cost. Measured against the two ends of the strip: the level cost grows x255 from level 1
-- to level 60, and this payout grows x229 from zone 1 to zone 20 -- so a player who gains about
-- three levels per zone as they climb sees **kills-per-level stay flat**, which is the property
-- `GetRankDamage` and `mobXpMult` are both tuned to protect and the one this file must not break.
--
-- It is still normalised UNDERNEATH the bonus, and that is what stops this being the runaway the
-- first cut was written to avoid: raw damage spans a factor of a million across the strip, and
-- 1.331 against `GetZoneReferenceDamage`'s own 1.4425 a zone means the net denominator still GROWS
-- with depth (by 1.0838 a zone) -- it simply grows slower than the damage does. Per kill the award
-- is still capped by the creature's own health, so nothing here scales with the swinger's stack.
--
-- AND SO "MORE DAMAGE" STILL MEANS "FASTER", through the only channel that cannot run away: a
-- bigger number kills the same creature in fewer blows, so it kills MORE creatures an hour. The
-- ceiling is the hit cadence and the respawn timer, both of which are fixed.
--
-- ===== WHY THE REWARD IS SUMMED AND NEVER MULTIPLIED =====
--
-- A level that comes FROM damage and gives damage is a closed feedback loop, and it is the single
-- most runaway-prone thing anyone has added to this repo. This same correction has already been
-- made three times, each time on a real shipped bug: `GetMutationIncomeMult` reached x5,000,000,
-- `PetService.GetEquippedBonus` multiplied per pet and measured x652 against x1394 for the entire
-- 100-step character ladder, and idle income once paid eighty clicks a second.
--
-- `1 + (level - 1) * k`, on the OUTSIDE of the product. Level 1 is worth exactly x1.00, so a save
-- that has never fought is unchanged.
GameConfig.LevelDamagePct = 5   -- +5% damage a level, summed, reset by a rebirth

-- ===== THE COST CURVE =====
--
-- Geometric at x1.10 a level against a linear reward -- the same relationship `GetUpgradeCost` and
-- `GetDiamondUpgradeCost` already use, and her *"da ne bude prelagano"* lives here rather than in
-- the reward. `LevelXpStart` is what level 1 -> 2 costs.
--
-- **DERIVED FROM THE TWO ANCHORS, NOT TYPED.** Cumulative XP to reach level L is
-- `LevelXpStart * (g^(L-1) - 1) / (g - 1)`, i.e. 600 * (1.1^(L-1) - 1) with these constants:
--
--     level 20     3,070 XP    -- rung 1. A fresh save lands ~1 XP a blow and ~2.4 a Swarmer, so
--                                 this is under an hour of a first session: the `+1 Speed Evolve`
--                                 level-25 anchor, in this game's units
--     level 30     8,900 XP
--     level 44    35,544 XP    -- rung 9, which is where the owner's 8-rebirth save picks up
--     level 60   165,481 XP
--     level 77   838,851 XP    -- rung 20, the last one
--     level 100  7,516,098 XP  -- the ceiling, and a trophy rather than a gate
--
-- Against a measured farm: 32.5 clocked 101 Swarmer kills in 110 s at one camp and 79 Brutes in
-- 100 s at another, so the honest band **in Forest** is ~8,000 XP an hour on a swarm camp and
-- ~40,000 on a brute camp. Rung 1 is therefore under an hour.
--
-- EVERY FIGURE ABOVE IS A ZONE-1 FIGURE, and the whole point of `LevelZoneGrowth` is that they do
-- not stay that way: the same camp twenty zones deep pays x229. So the cumulative column is what a
-- rung COSTS, not what it takes -- the time it takes depends on how deep the player has got, which
-- is exactly the shape she asked for. Each rung costs 1.1^3 = 1.331x the one before it, and one
-- zone of depth pays exactly that much more, which is the two curves being the same curve.
GameConfig.LevelXpStart = 60
GameConfig.LevelXpGrowth = 1.10

-- ===== WHAT ONE ZONE OF DEPTH IS WORTH ON THE LEVEL BAR =====
--
-- The TARGET is `LevelXpGrowth ^ 3` = 1.331: one zone deeper pays exactly what three more levels
-- cost, which is what makes kills-per-level flat while the cost curve is geometric. See the block
-- above for why that target is the right one.
--
-- **BUT THE TARGET IS NOT THE CONSTANT, AND THE DIVISION IS THE WHOLE POINT OF THIS LINE.** 32.7
-- also made creatures and bosses tougher with depth (`GameConfig.MobDepthGrowth`, x1.06 a zone),
-- and `GetLevelXpForDamage` awards the health a target actually LOST -- so a creature with 3x the
-- health is already worth 3x the XP, with nothing here asked. Setting this to the target directly
-- would count depth TWICE and pay x693 in zone 20 against the x229 intended, which is the shape of
-- every runaway this file's header lists.
--
-- Derived rather than typed, so the two constants cannot drift: whatever `MobDepthGrowth` becomes,
-- the product of the two stays 1.331. Zone 1 is x1.00 by construction; zone 20 is x229 all in.
GameConfig.LevelZoneGrowth = GameConfig.LevelXpGrowth ^ 3 / GameConfig.MobDepthGrowth

-- A CEILING, NOT A WALL. It sits well above the last rebirth gate (77), so nothing on the ladder
-- is ever locked behind it; what it is for is arithmetic hygiene -- `GetLevelXpCost` returns the
-- house sentinel `math.huge` at the top, exactly as `GetSwordCost` does, so every caller that
-- already knows how to draw a maxed ladder needs no new branch, and no save can accumulate an
-- unbounded number in `LevelXp`.
GameConfig.MaxLevel = 100

-- The save's level, clamped into the ladder. A save written before this feature has no field at
-- all and resolves to 1, which is worth x1.00 -- so nothing about a legacy save changes until its
-- owner lands their first blow. `math.floor` first, because this value reaches here straight off a
-- DataStore read, and the NaN test because that is the one value a comparison cannot catch.
function GameConfig.GetLevel(data)
	local level = tonumber(data and data.Level) or 1
	if level ~= level then return 1 end
	return math.clamp(math.floor(level), 1, GameConfig.MaxLevel)
end

function GameConfig.GetLevelXp(data)
	local xp = tonumber(data and data.LevelXp) or 0
	if xp ~= xp or xp < 0 then return 0 end
	return xp
end

-- What the NEXT level costs, given the level held now. `math.huge` at the ceiling.
function GameConfig.GetLevelXpCost(level)
	level = tonumber(level) or 1
	if level ~= level then return math.huge end
	level = math.max(math.floor(level), 1)
	if level >= GameConfig.MaxLevel then return math.huge end
	return math.floor(GameConfig.LevelXpStart * GameConfig.LevelXpGrowth ^ (level - 1))
end

-- What a zone of depth multiplies the bar by. Zone 1 is x1.00 by construction, so the first rung of
-- the ladder is untouched by this and only the late game moves.
function GameConfig.GetLevelZoneMult(zoneIndex)
	local i = math.max(math.floor(tonumber(zoneIndex) or 1), 1)
	return GameConfig.LevelZoneGrowth ^ (i - 1)
end

-- ===== REBIRTH XP MULTIPLIER =====
-- Each completed rebirth makes leveling up faster by +25% per rebirth milestone,
-- so players climb back up to higher gates smoothly and feel permanent momentum.
GameConfig.RebirthXpBonusPct = 25

function GameConfig.GetRebirthXpMult(data)
	local r = (data and data.Rebirths) or 0
	return 1 + r * (GameConfig.RebirthXpBonusPct / 100)
end

-- The one place damage becomes XP. damage is the health the target actually LOST, not the swing
-- -- see the note above on why overkill pays nothing.
function GameConfig.GetLevelXpForDamage(damage, zoneIndex, data)
	damage = tonumber(damage) or 0
	if damage ~= damage or damage <= 0 then return 0 end
	local reference = GameConfig.GetZoneReferenceDamage(zoneIndex)
	if not (reference > 0) then return 0 end
	local rebirthMult = GameConfig.GetRebirthXpMult(data)
	return (damage / reference * GameConfig.GetLevelZoneMult(zoneIndex)) * rebirthMult
end

-- The one damage term. Quoted from `DNAService.GetCombatDamage` (the only thing in the game that
-- computes damage) and from `GetBossDamageDivisor` (which cancels it) -- those two call sites are
-- the whole surface and they must stay in step, or a boss is priced against a level the player is
-- not standing on.
function GameConfig.GetLevelDamageMult(data)
	return 1 + (GameConfig.GetLevel(data) - 1) * GameConfig.LevelDamagePct / 100
end

-- ===== THE REBIRTH LADDER IS A LADDER OF LEVELS NOW =====
--
-- Rung r asks for `RebirthLevelBase + (r-1) * RebirthLevelStep`. Linear in the level and therefore
-- geometric in the WORK, because the cost curve above is: +3 levels is x1.331 the cumulative XP,
-- every rung, all the way up. That is the whole reason the step can be a small round number.
--
-- THE STAGE REQUIREMENT IS GONE, and that is the point rather than a side effect. It could never
-- have carried twenty rungs -- there are only twenty stages and a rebirth resets you to the first
-- one -- and it is what made a rebirth a thing you arrived at instead of a thing you climbed to.
GameConfig.RebirthLevelBase = 20
GameConfig.RebirthLevelStep = 3

function GameConfig.RebirthLevelFor(tier)
	tier = math.max(math.floor(tonumber(tier) or 1), 1)
	return GameConfig.RebirthLevelBase + (tier - 1) * GameConfig.RebirthLevelStep
end

-- The level the next milestone is gated behind, or nil when the ladder is finished. The shrine,
-- the HUD and the server all read this one function so they cannot drift about what the door asks.
function GameConfig.GetNextRebirthLevel(data)
	local tier = GameConfig.GetNextRebirthTier(data)
	return tier and GameConfig.RebirthLevelFor(tier) or nil
end

end
