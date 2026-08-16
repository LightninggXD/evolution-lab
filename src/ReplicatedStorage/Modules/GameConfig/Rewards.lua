-- GameConfig.Rewards -- the seven-day daily board and the group/community rewards.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

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

end
