-- GameConfig.Season -- the season pass track and how a season turns over on its own.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ============================================================================
-- SEASON PASS
-- ============================================================================
-- A thirty-level track that fills with Season XP, and Season XP comes from ONE place: completing
-- daily and weekly quests. Nothing else pays it. That is the whole design -- the pass is the
-- reason to come back tomorrow, and the quests are the reason to play today.
--
-- Two rows of rewards per level, exactly like the board this is modelled on: a FREE row everybody
-- collects, and a PREMIUM row that unlocks in one purchase and pays out retroactively for every
-- level already reached.
--
-- `id` is the reset switch. Bump it and every player's progress, claims and premium flag start
-- over on their next join -- see SeasonPassService, which migrates lazily rather than needing a
-- scheduled job or a live server at the moment a season turns over.
GameConfig.Season = {
	-- `id` and `name` USED TO LIVE HERE and are derived now -- see GetCurrentSeason below (7.3).
	-- What is left in this table is the SHAPE of a pass, which every season shares. The emoji is
	-- the fallback for a caller that wants a season marker without asking which season it is.
	emoji = "\u{1F39F}\u{FE0F}",
	maxLevel = 30,
	-- flat, not a curve. A rising per-level cost makes the back half of a pass feel like a wall,
	-- and the quests already scale the income side.
	xpPerLevel = 1500,
}

-- ===== THE SEASON TURNS OVER ON ITS OWN (7.3) =====
--
-- `Season.id` used to be a hand-edited string, and the comment above said "bump it and every
-- player's progress starts over". That is a live-ops job nobody can do at 3am on the day it is due,
-- and a season that only rotates when somebody remembers is not a season -- it is a permanent pass
-- with an optimistic name.
--
-- It is derived from the clock instead, exactly like an event window, and for exactly the same
-- reasons: two servers cannot disagree, a restart cannot lose it, and there is no scheduled job to
-- miss. SeasonPassService already resets LAZILY off a mismatch in this id, so making the id a
-- function of the date is the entire feature -- that file's reset logic did not change at all.
--
-- THE EPOCH IS CHOSEN SO THAT TODAY IS STILL SEASON 1, and the id it generates for the first
-- season is the string "S1" -- byte for byte what every existing save already holds. So this update
-- rotates nothing: no player loses the pass progress they had when it shipped. Getting that wrong
-- is a wipe, not a bug report.
--
-- THEMES CYCLE, NUMBERS DO NOT. Season 7 is "Season 7: <the 7th theme>", and once the list is
-- exhausted it starts round again while the number keeps climbing -- so the table never runs out
-- and no season is ever nameless. Add a row and the rotation is longer; nothing else changes.
GameConfig.SeasonEpoch = { 2026, 8, 1, 0, 0 }   -- UTC, the moment Season 1 opened
GameConfig.SeasonLengthDays = 30

GameConfig.SeasonThemes = {
	{ name = "First Light",    emoji = "\u{1F39F}\u{FE0F}" },
	{ name = "Deep Currents",  emoji = "\u{1F30A}" },
	{ name = "Ashfall",        emoji = "\u{1F30B}" },
	{ name = "Frostbloom",     emoji = "\u{2744}\u{FE0F}" },
	{ name = "Starfall",       emoji = "\u{1F320}" },
	{ name = "Overgrowth",     emoji = "\u{1F33F}" },
}

-- The season `now` falls in. Everything about it is generated, so there is no list to keep in step
-- with the calendar and no season that can be reached before someone has written it down.
function GameConfig.GetCurrentSeason(now)
	now = now or GameConfig.EventNow()
	local epoch = GameConfig.UtcTimestamp(GameConfig.SeasonEpoch)
	local length = GameConfig.SeasonLengthDays * 86400
	-- clamped at 1: a clock reading before the epoch is a broken clock, not season zero, and it
	-- must not produce an id no save has ever seen
	local index = math.max(1, math.floor((now - epoch) / length) + 1)
	local startTs = epoch + (index - 1) * length
	local theme = GameConfig.SeasonThemes[((index - 1) % #GameConfig.SeasonThemes) + 1]
	return {
		index = index,
		id = "S" .. index,
		name = ("Season %d: %s"):format(index, theme.name),
		emoji = theme.emoji,
		startTs = startTs,
		endTs = startTs + length,
		secondsLeft = math.max(0, startTs + length - now),
	}
end

-- Level from total XP. Level 1 is the floor -- a pass at 0 XP is "Level 1, 0/1500", never level 0.
function GameConfig.GetSeasonLevel(xp)
	local level = 1 + math.floor((xp or 0) / GameConfig.Season.xpPerLevel)
	return math.min(level, GameConfig.Season.maxLevel)
end

-- XP into the current level, and how much that level needs. At max level both are the same
-- number, so the bar reads full instead of dividing by a level that does not exist.
function GameConfig.GetSeasonLevelProgress(xp)
	xp = xp or 0
	local per = GameConfig.Season.xpPerLevel
	if GameConfig.GetSeasonLevel(xp) >= GameConfig.Season.maxLevel then
		return per, per
	end
	return xp % per, per
end

-- The thirty rows, generated rather than hand-typed for the same reason the eggs are: thirty
-- literal tables drift the moment one number in the ramp changes.
--
-- DNA is the filler and is deliberately the WEAKEST part of the reward -- income scales so hard
-- across twenty stages that any fixed DNA figure is either trivial or game-breaking depending on
-- who reads it. The things worth having are the ones the economy cannot inflate: potions,
-- Diamonds and Evolution Shards.
GameConfig.SeasonRewards = {}
do
	local POTION_BY_BAND = { "dna_s", "xp_s", "luck_m", "dna_m", "xp_m", "luck_l" }
	for level = 1, GameConfig.Season.maxLevel do
		local band = math.min(math.ceil(level / 5), #POTION_BY_BAND)
		local dna = math.floor(400 * (1.95 ^ (level - 1)))

		local free = { dna = dna }
		-- one bottle every fourth level, and a Diamond payout at each of the three round numbers
		if level % 4 == 0 then
			free.potions, free.potionId = 1, POTION_BY_BAND[band]
		end
		if level == 10 then free.diamonds = 2 end
		if level == 20 then free.diamonds = 3 end
		if level == 30 then free.diamonds = 5 end

		-- Premium is the same shape, three times the DNA, a bottle twice as often, Diamonds every
		-- fifth level and the only Shards on the board.
		local premium = { dna = dna * 3 }
		if level % 2 == 0 then
			premium.potions, premium.potionId = 2, POTION_BY_BAND[band]
		end
		if level % 5 == 0 then premium.diamonds = 3 + math.floor(level / 5) end
		if level == 15 then premium.shards = 5 end
		if level == 30 then premium.shards = 15 end

		GameConfig.SeasonRewards[level] = {
			level = level,
			free = free,
			premium = premium,
			-- every tenth level is drawn bigger on the track
			milestone = (level % 10 == 0),
		}
	end
end

function GameConfig.GetSeasonReward(level)
	return GameConfig.SeasonRewards[level]
end

-- ===== QUESTS =====
-- Every player gets the SAME list every period. No random draw and no per-player seed to store:
-- a rolled quest board means somebody opens the panel to three tasks they cannot do from where
-- they are standing, and it makes the save a great deal more fragile for nothing.
--
-- `counter` is the name SeasonPassService.Track is called with. All four already happen on paths
-- that write to the save anyway -- a creature dying, a boss falling, an egg hatching, a fusion --
-- so tracking costs no new events and no extra replication.
GameConfig.QuestPool = {
	daily = {
		{ key = "d_creatures", counter = "creatures", target = 50, emoji = "\u{2694}\u{FE0F}", name = "Defeat 50 creatures",   xp = 250 },
		{ key = "d_eggs",      counter = "eggs",      target = 10, emoji = "\u{1F95A}",        name = "Hatch 10 eggs",          xp = 300 },
		{ key = "d_bosses",    counter = "bosses",    target = 3,  emoji = "\u{1F451}",        name = "Defeat 3 bosses",        xp = 350 },
		{ key = "d_fuse",      counter = "fuse",      target = 2,  emoji = "\u{1F9EC}",        name = "Fuse 2 pets",            xp = 200 },
	},
	weekly = {
		{ key = "w_creatures", counter = "creatures", target = 500, emoji = "\u{2694}\u{FE0F}", name = "Defeat 500 creatures", xp = 1200, diamonds = 2 },
		{ key = "w_bosses",    counter = "bosses",    target = 20,  emoji = "\u{1F451}",        name = "Defeat 20 bosses",    xp = 1500, diamonds = 3 },
		{ key = "w_eggs",      counter = "eggs",      target = 60,  emoji = "\u{1F95A}",        name = "Hatch 60 eggs",       xp = 1400, diamonds = 2 },
	},
}

GameConfig.QuestPeriods = {
	-- Bucket arithmetic, not a stored timer: the period a moment belongs to is a pure function of
	-- the clock, so a reset needs no live server and cannot be missed by a player who was offline
	-- when it happened. (The Unix epoch was a Thursday, so the weekly bucket turns over on a
	-- Thursday at 00:00 UTC.)
	daily  = { seconds = 86400,  label = "Daily",  emoji = "\u{2600}\u{FE0F}" },
	weekly = { seconds = 604800, label = "Weekly", emoji = "\u{1F4C5}" },
}

function GameConfig.GetQuests(period)
	return GameConfig.QuestPool[period] or {}
end

function GameConfig.GetQuestPeriodId(period, now)
	local def = GameConfig.QuestPeriods[period]
	if not def then return 0 end
	return math.floor((now or os.time()) / def.seconds)
end

-- When the current period rolls over, as a unix timestamp -- the countdown the panel prints.
function GameConfig.GetQuestPeriodEnd(period, now)
	local def = GameConfig.QuestPeriods[period]
	if not def then return 0 end
	return (GameConfig.GetQuestPeriodId(period, now) + 1) * def.seconds
end

function GameConfig.GetQuestDef(period, questKey)
	for _, q in ipairs(GameConfig.GetQuests(period)) do
		if q.key == questKey then return q end
	end
	return nil
end

end
