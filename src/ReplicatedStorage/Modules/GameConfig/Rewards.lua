-- GameConfig.Rewards -- the seven-day daily board, its week tiers, and the group/community rewards.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== DAILY REWARDS =====
-- 7-day cycle. Potions are introduced starting Day 3. Day 6 gives a bonus Shard, Day 7 is
-- the big one (DNA + Potions + Shards). The cycle repeats -- day 8 is day 1 again -- but it repeats
-- AT A HIGHER TIER since 21.2; the numbers below are week one, see GameConfig.DailyTiers.
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

-- ===== THE WEEK TIERS (21.2) =====
--
-- The board loops -- day 8 is day 1 again -- and until this row it looped at the SAME value, so a
-- player holding a fourteen-day streak was handed 200 DNA on day 8 after 23,000 the night before.
-- Past day 7 the ladder stopped meaning anything, which is the whole of what 21.2 opens with.
--
-- Each completed week now moves the entire board up a tier. `mult` scales **the DNA only**, and
-- that is a deliberate line rather than an oversight: DNA is the one reward here that runs through
-- `ScaleReward`, so it is authored in stage-1 clicks and a multiplier on it means the same thing at
-- stage 1 and at stage 20. Diamonds, Shards and potions are FLAT numbers aimed at fixed sinks -- a
-- diamond upgrade costs 5/8/15 and never moves -- which is exactly why 1.1 kept them out of
-- `ScaleReward`. Multiplying those by 8 would buy every permanent upgrade in the game off one month
-- of logins. So a tier pays them as `bonusDiamonds` instead: a small fixed add on the HERO DAY
-- ONLY, +3 a week at the top against the 3 the week already pays.
--
-- Four tiers and the last one repeats for ever. A ladder with no top is a promise the economy
-- cannot keep, and by then the daily is worth eight of what it was, which is the point.
GameConfig.DailyTiers = {
	{ name = "Week 1",  mult = 1, bonusDiamonds = 0 },
	{ name = "Week 2",  mult = 2, bonusDiamonds = 1 },
	{ name = "Week 3",  mult = 4, bonusDiamonds = 2 },
	{ name = "Veteran", mult = 8, bonusDiamonds = 3 },
}

-- Which tier a streak stands on: 1-7 is tier 1, 8-14 is tier 2, and anything past the last row
-- stays on the last row. Returns the index and the row itself.
function GameConfig.GetDailyTier(streak)
	local n = math.max(math.floor(tonumber(streak) or 1), 1)
	local index = math.floor((n - 1) / #GameConfig.DailyRewards) + 1
	if index > #GameConfig.DailyTiers then index = #GameConfig.DailyTiers end
	return index, GameConfig.DailyTiers[index]
end

-- What a streak actually pays, tier applied. ONE function for the server that grants it, the board
-- that draws it and the welcome-back card that advertises it -- the day-index arithmetic
-- (`((streak - 1) % 7) + 1`) had been written out by hand in five places before this, and a tier
-- added to four of them would have been a board that promises what the server does not pay.
--
-- `dayIndex` is optional and is what lets the board ask "what would day 3 of THIS week pay" for a
-- cell that is not today's.
function GameConfig.GetDailyReward(streak, dayIndex)
	local n = math.max(math.floor(tonumber(streak) or 1), 1)
	local tierIndex, tier = GameConfig.GetDailyTier(n)
	local day = dayIndex or (((n - 1) % #GameConfig.DailyRewards) + 1)
	local base = GameConfig.DailyRewards[day]
	local out = {
		day = day,
		tier = tierIndex,
		tierName = tier.name,
		tierMult = tier.mult,
		dna = math.floor(base.dna * tier.mult),
		potions = base.potions,
		potionId = base.potionId,
		shards = base.shards,
		diamonds = base.diamonds,
	}
	-- the tier's diamonds land on the hero day and nowhere else: it is the day the week climbs
	-- towards, and one extra diamond spread across seven cards is invisible on every one of them
	if day == #GameConfig.DailyRewards and tier.bonusDiamonds > 0 then
		out.diamonds = (out.diamonds or 0) + tier.bonusDiamonds
	end
	return out
end

-- ===== GROUP & COMMUNITY REWARDS (Phase 5.5) =====
-- Group membership gives permanent +10% DNA and unlocks a daily chest.
-- Liking and Favoriting reward one-time diamond and potion boosts.
GameConfig.RobloxGroupId = 0 -- Configurable group id (default 0; in Studio always grants access)
GameConfig.GroupIncomeMult = 1.10 -- +10% DNA permanent income boost for group members
-- ===== THE FRIENDS-IN-SERVER BONUS, AND IT IS ONE RULE IN THREE PLACES (22.1) =====
--
-- +5% income a friend, capped at 4 friends (+20%). Both numbers lived as literals in
-- `DNAService.GetIncomeMult`, in MainUI's HUD pill and in the invite button's badge, and the third
-- copy had already drifted: the badge multiplied UNCAPPED, so a player with six friends in the
-- server was promised **+30%** beside a server paying +20%. All three read these two now.
--
-- THE CAP IS NOT A FEEL NUMBER. `IsFriendsWith` is a real friendship, but a server can be filled
-- with them deliberately, so this is the ceiling that keeps a full lobby from being a free x2 on
-- the whole economy. `GetIncomeMult` applies it before the bought multipliers, beside the group
-- bonus, because it is earned rather than paid for -- and it is skipped for offline earnings, which
-- is what `excludeEvents` is doing on that branch.
GameConfig.FriendBonusPct = 5
GameConfig.FriendBonusCap = 4

-- The multiplier itself, so no caller composes it from the two constants and gets the cap wrong.
-- Returns 1.00 at zero friends, 1.20 at the cap and above.
function GameConfig.GetFriendBonusMult(friendCount)
	local n = math.min(math.max(tonumber(friendCount) or 0, 0), GameConfig.FriendBonusCap)
	return 1 + n * (GameConfig.FriendBonusPct / 100)
end

-- What the HUD prints beside the count: the whole percent, already capped.
function GameConfig.GetFriendBonusPct(friendCount)
	local n = math.min(math.max(tonumber(friendCount) or 0, 0), GameConfig.FriendBonusCap)
	return n * GameConfig.FriendBonusPct
end

-- ===== THE PARTY, AND WHY ITS BONUS IS NOT THE FRIEND BONUS AGAIN (22.5) =====
--
-- The friends-in-server bonus pays for who is LOGGED IN. It asks nothing of either player: two
-- friends on opposite ends of a twenty-zone strip who never see each other are paid the same +5%
-- as two standing shoulder to shoulder. That is correct for what it is -- a reason to bring a
-- friend -- and it is not co-play.
--
-- A party is the other half: it costs something to hold. The bonus counts only party members
-- **within `PartyRadiusStuds` of you right now**, so it is paid for actually playing together, and
-- it is bigger than the friend bonus precisely because it is conditional. The two multiply -- a
-- party of friends gets both -- which is the stack Phase 22 is trying to produce.
--
-- AND IT IS OPEN TO STRANGERS, which the friend bonus cannot be. `IsFriendsWith` is a fact about
-- two accounts; standing on the same ground is a fact about two people playing. The party stand
-- puts anyone who presses it into the smallest open party, so a new player with no friends on the
-- platform can still be in one within a minute of arriving.
--
-- THE NUMBERS. +8% a nearby member, capped at 5 of them (+40%) -- one short of a full party of six,
-- so the cap is the whole party minus yourself and nobody is ever carrying a member who does not
-- count. 80 studs is the radius: `TradeProximityStuds` is 40 and that is arm's length for a trade,
-- while a hunting group spreads across a clearing -- measured against the jungle camps, whose floors
-- are 20-30 studs across with 20 studs between them.
GameConfig.PartySize = 6
GameConfig.PartyBonusPct = 8
GameConfig.PartyBonusCap = 5
GameConfig.PartyRadiusStuds = 80

-- The multiplier itself, so no caller composes it from the constants and gets the cap wrong -- the
-- exact mistake the friend bonus's third copy made before 22.1 collapsed it into one function.
-- Returns 1.00 alone, 1.40 at the cap.
function GameConfig.GetPartyBonusMult(nearCount)
	local n = math.min(math.max(tonumber(nearCount) or 0, 0), GameConfig.PartyBonusCap)
	return 1 + n * (GameConfig.PartyBonusPct / 100)
end

-- What a board or a tag prints beside the count: the whole percent, already capped.
function GameConfig.GetPartyBonusPct(nearCount)
	local n = math.min(math.max(tonumber(nearCount) or 0, 0), GameConfig.PartyBonusCap)
	return n * GameConfig.PartyBonusPct
end

-- One colour per party, taken in order and reused when they run out. They have to be legible as a
-- tag over a head against Forest's very bright key light AND distinguishable from the game's own
-- semantic colours -- green is a trade tag (21.1), gold is VIP and rebirth, red is the Colosseum --
-- so these are the four that are left, at a tone that survives the outline.
GameConfig.PartyColors = {
	Color3.fromRGB(96, 176, 255),   -- blue
	Color3.fromRGB(190, 130, 255),  -- violet
	Color3.fromRGB(255, 150, 90),   -- orange
	Color3.fromRGB(90, 226, 200),   -- teal
}

-- ===== THE INVITE REWARD'S TWO ANTI-FARM NUMBERS (22.2) =====
--
-- `InviteRewardService` pays an exclusive pet to BOTH ends of a game invite, and alt accounts are
-- the failure mode of every referral system ever shipped. These are the only two levers against
-- that, and they were never written down: the service read `GameConfig.InviteMinAccountAgeDays or
-- 14` and `GameConfig.InviteMaxPaid or 5` against constants that DID NOT EXIST, so the numbers
-- were real but invisible -- nothing could find them, and changing them meant editing a fallback
-- inside a boolean expression. The `or` is gone from all three call sites with this.
--
-- 14 DAYS is the account age a joiner must clear before the invite pays anything. A farm can make
-- accounts freely but it cannot make them old, so age is the one gate that costs the attacker time
-- rather than clicks. It is deliberately above Roblox's own 24-hour new-account marks: the pet is
-- permanent and tradable-adjacent, and a fortnight is cheap to wait out honestly (a real friend
-- invited today is on an account made years ago) while being useless to run at scale.
--
-- 5 IS A LIFETIME CAP, not a daily one, and it bounds a save field as well as the payout:
-- `data.InvitesPaid` is a list of the UserIds an inviter has been paid for, and a list that only
-- ever grows is a save-size bug. The cap is what keeps it five entries long forever. Five pets is
-- a real reward for bringing real friends and a poor return on building a farm.
GameConfig.InviteMinAccountAgeDays = 14
GameConfig.InviteMaxPaid = 5
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

end
