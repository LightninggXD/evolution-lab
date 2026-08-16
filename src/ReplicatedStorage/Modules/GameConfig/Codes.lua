-- GameConfig.Codes -- promo codes and the offline earnings window.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ============================================================================
-- CODES (Phase 5.1)
-- ============================================================================
-- The cheapest traffic channel this genre has, and the game had none. Dexerto, Gamerant and
-- Game.Guide publish a codes article for any game that has codes, refresh it monthly, and the
-- article is what people search for -- so a code is not a giveaway, it is the reason a page about
-- this game exists at all.
--
-- A CODE IS AN ARBITRARY STRING THE OWNER PUBLISHES, which is what makes this table different from
-- `RobuxProducts` and `GamePasses`: those hold ids that must be created on the dashboard first and
-- must never be invented, whereas these are made up on purpose and only become real when Kristina
-- posts them. Edit the list freely; the redeem path does not care what is in it.
--
-- Rewards use exactly the field names `DailyRewards` uses (`dna`, `diamonds`, `shards`, `potions`,
-- `potionId`) so `CodesService` grants them with the same four lines `RewardService` already does,
-- and `dna` goes through `ScaleReward` for the reason every authored figure in this game does: a
-- flat 1,000 is a fortune at stage 1 and less than one kill from stage 6 on.
--
-- `expires` is an os.time() stamp or nil for "runs forever". Checked at redeem rather than by a
-- timer, the same way `GetPotionBoost` handles its expiry -- nothing has to clean up.
GameConfig.Codes = {
	{ code = "LAUNCH",     dna = 1500, diamonds = 10, potions = 2, note = "launch day" },
	{ code = "EVOLUTION",  dna = 1000, diamonds = 5,               note = "evergreen, in the description" },
	{ code = "WELCOME",    dna = 750,  potions = 1,                note = "evergreen, for first-timers" },
	{ code = "BRAINROT",   dna = 1000, diamonds = 5,               note = "evergreen, genre search term" },
	{ code = "THANKYOU",   dna = 2000, diamonds = 15, shards = 1,  note = "milestone / apology code" },
	{ code = "LABRAT",     dna = 500,  potions = 1,  potionId = "luck_s", note = "evergreen" },
}

-- Typed by hand off a web page, so it arrives with stray spaces and whatever case the reader used.
-- Upper-cased and stripped of ALL whitespace rather than just trimmed: "launch day" and "LAUNCHDAY"
-- are the same keystrokes to a player and refusing one of them reads as a broken code.
GameConfig.CodeMaxLength = 24

function GameConfig.NormaliseCode(text)
	if type(text) ~= "string" then return nil end
	local cleaned = text:gsub("%s", ""):upper()
	if #cleaned == 0 or #cleaned > GameConfig.CodeMaxLength then return nil end
	return cleaned
end

-- Returns the entry and its normalised key, or nil. A linear scan over six rows is not worth an
-- index, and building one would be one more thing to keep in step with the table above.
function GameConfig.GetCode(text)
	local key = GameConfig.NormaliseCode(text)
	if not key then return nil end
	for _, entry in ipairs(GameConfig.Codes) do
		if GameConfig.NormaliseCode(entry.code) == key then
			return entry, key
		end
	end
	return nil
end

function GameConfig.IsCodeExpired(entry)
	return entry ~= nil and entry.expires ~= nil and os.time() >= entry.expires
end

-- ============================================================================
-- OFFLINE EARNINGS (Phase 5.2)
-- ============================================================================
-- The strongest single reason to come back, and it is safe to build here for one specific reason:
-- the idle rate is ALREADY capped in units of clicks (see the long note over
-- `DNAService.GetAutoCollectAmount`, which exists because idle income once paid eighty clicks a
-- second and broke every price in the game). Offline income is that same capped rate multiplied by
-- a bounded number of seconds, so it cannot invent a rate that playing cannot beat.
--
-- Two bounds, and they answer different questions:
--
--   * `OfflineMaxHours` bounds the WINDOW. Eight hours is a night's sleep -- long enough that
--     logging off deliberately feels rewarded, short enough that a player returning after a month
--     does not arrive holding the rest of the game.
--   * `OfflineRate` bounds the RATE against being online. At 0.5 an hour away is worth half an hour
--     idling, which keeps the ordering the auto-collect note fought for: playing beats idling, and
--     idling beats being gone.
--
-- `OfflineMinSeconds` is not a balance number, it is a UI one: without it every rejoin, every test
-- restart and every server hop pops a "welcome back" card for four seconds of absence.
GameConfig.OfflineMaxHours = 8
GameConfig.OfflineRate = 0.5
GameConfig.OfflineMinSeconds = 120

-- Seconds of absence that actually pay, given the cap. Split out so the "welcome back" card can
-- say how long it credited rather than how long the player was gone -- claiming credit for a week
-- and paying eight hours is the kind of small lie players notice immediately.
function GameConfig.GetOfflineSeconds(elapsed)
	elapsed = math.max(tonumber(elapsed) or 0, 0)
	if elapsed < GameConfig.OfflineMinSeconds then return 0 end
	return math.min(elapsed, GameConfig.OfflineMaxHours * 3600)
end

end
