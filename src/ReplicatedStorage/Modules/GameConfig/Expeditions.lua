-- GameConfig.Expeditions -- the adventure runs: their route, their stations, and what they pay.
--
-- ONE OF THE PARTS OF `GameConfig` (18.9). It is handed the shared config table and writes into it;
-- see the loader in `GameConfig` itself for why the order of the parts is load-bearing. This one is
-- required LAST, AFTER `Minigames`: it reads `GameConfig.MinigameKindsByKey` at load time to check
-- that every station names a game that exists, and it quotes `ScaleReward` at call time.
--
-- =====================================================================================
-- WHAT AN EXPEDITION IS, AND WHY IT EXISTS (29.1, owner's steer)
-- =====================================================================================
-- Phase 28 shipped four arcade minigames. Each is a ninety-second island: you press a terminal, you
-- play, you are paid, nothing connects to anything. The owner asked for "male avanture" -- several
-- games chained inside one longer run, with a story -- and named Animal Jam Classic's **Adventures**
-- as the model.
--
-- An Expedition is the container. One run is: go through a door, cross a themed map on foot, clear
-- three stations, use what they gave you to open a locked door, and take what is behind it.
--
-- =====================================================================================
-- THE MAP IS SHARED. THE RUN IS PRIVATE. (and instancing is why)
-- =====================================================================================
-- The owner asked for a private instanced map and is NOT getting one, and the reason is worth
-- stating where the design lives rather than in a commit message. This codebase has no instancing of
-- any kind: no `ReserveServer`, no `TeleportService`, no parties, no per-player geometry, and not
-- one Humanoid created server-side. Private instances are a new infrastructure layer.
--
-- The Colosseum is the precedent that gives almost all of it anyway: `EventArena` is a real walkable
-- place 1,400 studs off the zone strip, reached only by teleport, carrying its own version stamp. An
-- Expedition map is built exactly the same way, mirrored to -Z.
--
-- So two players in the map at once see each other, and each runs their own progress. Everything in
-- here is per-player state; the only thing the shared world forces a design decision about is the
-- symbol door, and that is solved on the client -- see `ExpeditionService`.
--
-- =====================================================================================
-- WHAT A RUN PAYS, AND THE CEILING THAT MATTERS
-- =====================================================================================
-- Same rule as the arcade: every reward is authored in STAGE-1 CLICKS and paid through
-- `GameConfig.ScaleReward`, so a run is worth the same number of kills at stage 1 and at stage 20.
-- A flat number is overpowered at stage 3 and invisible at stage 12.
--
-- Sized against the anchors already in the game -- a stage-1 click is 1.3 DNA, a perfect arcade run
-- is 900 clicks, the arcade cap is 12 runs a day, the day-7 login pays 23,000 DNA (~17,700 clicks):
--
--   three stations, perfect          2,700 clicks
--   the Core                           900 clicks   (built in stage 2; the row is authored now)
--   ------------------------------------------------
--   a perfect expedition             3,600 clicks
--   two runs a day                   7,200 clicks
--
-- **An expedition pays LESS per day than the arcade does** (7,200 against 10,800), and that is the
-- answer to "what stops this replacing the tycoon loop". Its draw is the chest, not the currency.
--
-- THE NUMBER TO WATCH IS THE COMBINED ONE. An expedition burns no arcade plays, so a player who
-- grinds both ceilings takes 18,000 clicks a day -- almost exactly one day-7 login. That is a
-- reasonable ceiling for somebody playing every minigame in the game to exhaustion, and it is the
-- number to re-measure first if the economy ever feels loose. Both caps are one line each.

return function(GameConfig)

-- Runs per UTC day, across ALL expeditions. The whole limiter in v1 -- there is only one expedition,
-- so a per-expedition cooldown would be a second lock on the same door. It arrives with number two.
GameConfig.ExpeditionDailyRuns = 2

-- What the Core pays when it dies. Authored here rather than inside the expedition row because
-- every expedition's Core is worth the same: it is the ending, not a difficulty tier.
GameConfig.ExpeditionCoreClicks = 900

-- Relic chests for finishing, and for finishing well. `RelicService.GiveChest` is documented in its
-- own file as "the seam for every future source -- boss drops, hidden passages", which is exactly
-- what this is. Beating par doubles it; nothing else in the run does.
GameConfig.ExpeditionChest = 1
GameConfig.ExpeditionChestParBonus = 1

-- ===== BELOW THE FORGE, A CHEST IS AN IOU =====
--
-- `RelicService.HandleOpenChest` refuses until `GameConfig.RelicUnlockStage` (10), so a stage-4
-- player banks a chest they cannot open for six stages. The chest is still granted -- it waits, and
-- finding a pile of them at stage 10 is a good moment -- but diamonds are paid alongside it so the
-- reward is never invisible to the player who earned it. Flat and small, for the reason 21.2 keeps
-- diamonds out of `ScaleReward`: they buy fixed-price permanent upgrades (5/8/15).
GameConfig.ExpeditionDiamondsBeforeForge = 2

-- ===== THE EXPEDITIONS =====
--
-- `stations` is the route in order. Each names a `kind` from `GameConfig.MinigameKinds` -- the games
-- are reused whole, not reimplemented -- and carries the symbol it awards.
--
-- SYMBOLS ARE AWARDED ON COMPLETION, NOT ON SCORE. A weak player still reaches the door; they are
-- simply paid less on the way. Par is a target, not a wall, which is the rule the arcade already
-- follows and the reason its payout curve pays below par at all.
--
-- ===== EVERY GLYPH HERE IS U+1F300 OR ABOVE, AND THAT IS A RULE NOT A PREFERENCE =====
-- 27.7 found `UITheme.Button` drawing a blank red ball because **FredokaOne has no glyph for
-- U+2715** -- and nothing reported it: `.Text`, `.TextColor3` and even `.TextFits` all read correct,
-- because the character was laid out and simply not drawn. Characters in the U+2600-27BF dingbat
-- range are text-default and fall back to the display font, where they may not exist. Characters
-- from U+1F300 up are emoji-presentation and are drawn by the system emoji font.
-- The three below are all already drawn on the DNA Match board, so they are proven in this place.
--
-- NOTE FOR LATER, NOT FIXED HERE: `MinigameKinds` carries two glyphs from the risky range --
-- Purge's `\u{2622}` and Containment's `\u{1F6E1}`. They may be rendering as blanks on the terminal
-- signs. That is Phase 28's art to change, and changing it from here would be this file reaching
-- into another one's decision; it is written up as a roadmap row instead.
GameConfig.ExpeditionList = {
	{
		key = "ForestOutbreak",
		name = "Forest Outbreak",
		emoji = "\u{1F9EC}",
		zoneKey = "Forest",
		-- Entry is not gated on stage: this is the one piece of content a brand-new player can be
		-- shown that is not a number going up, and gating it would hide it from exactly the cohort
		-- the first ten minutes are being tuned for (Phase 21).
		minStageIndex = 1,
		blurb = "Specimens got out of the Forest vault. Clear the containment line, seal the breach, "
			.. "and bring back whatever the team left behind.",
		-- One line per chamber, painted on a board by `ZoneKit.addPlankText`. There is no NPC and no
		-- dialogue system in this game -- zero Humanoids are created server-side -- so the story is
		-- told by the walls, which is what every sign in the world already does.
		story = {
			"CONTAINMENT LINE 1 -- the vault door held. Nothing else did.",
			"CONTAINMENT LINE 2 -- specimen trails lead deeper. Keep the seals.",
			"CONTAINMENT LINE 3 -- three seals open the vault. You have two.",
			"THE VAULT -- whatever got out first, got out here.",
		},
		stations = {
			{
				kind = "Match",
				symbol = "\u{1F9EC}",
				symbolName = "Helix Seal",
				color = Color3.fromRGB(120, 235, 150),
			},
			{
				kind = "Purge",
				symbol = "\u{1F9A0}",
				symbolName = "Purge Seal",
				color = Color3.fromRGB(190, 130, 255),
			},
			{
				kind = "Sort",
				symbol = "\u{1F9EA}",
				symbolName = "Sample Seal",
				color = Color3.fromRGB(110, 210, 250),
			},
		},
		core = {
			name = "Contamination Core",
			emoji = "\u{1F9A0}",
			color = Color3.fromRGB(190, 130, 255),
		},
	},
}

GameConfig.ExpeditionsByKey = {}
for _, expedition in ipairs(GameConfig.ExpeditionList) do
	GameConfig.ExpeditionsByKey[expedition.key] = expedition
end

function GameConfig.GetExpedition(key)
	return GameConfig.ExpeditionsByKey[key]
end

-- The kind table a station plays, resolved through the arcade's own registry so there is exactly
-- one definition of what "DNA Match" is. Returns nil for a station naming a game that does not
-- exist, which the load-time check below turns into a warning rather than a runtime crash.
function GameConfig.GetStationKind(expedition, index)
	local station = expedition and expedition.stations[index]
	return station and GameConfig.MinigameKindsByKey[station.kind] or nil
end

-- What a clean run is worth, summed from the stations' own pars. Data-driven on purpose: swapping a
-- station's game re-prices the run without anybody editing a second number, and the two numbers are
-- never allowed to disagree because there is only one.
function GameConfig.GetExpeditionPar(expedition)
	local par = 0
	for index in ipairs(expedition.stations) do
		local kind = GameConfig.GetStationKind(expedition, index)
		if kind then
			par += kind.par
		end
	end
	return par
end

-- ===== THE LEDGER =====
--
-- `data.Expeditions` is `{ Day = <day number>, DayRuns = n, Best = {key -> score},
-- Cleared = {key -> times finished} }`.
--
-- Shaped HERE rather than in `defaultData`, and it ROLLS THE DAY OVER ITSELF -- the same shape as
-- `GetMinigameLedger`, for the same reason: which day a save belongs to is decided by the clock at
-- read time, and the only moment anybody can notice the date changed is the moment they ask. A save
-- written before Expeditions existed is therefore repaired by being looked at.
--
-- `os.time()`, NOT `GameConfig.UtcTimestamp()`. That one is a SPEC CONVERTER -- it turns an authored
-- `{year, month, day}` into a timestamp -- and calling it bare indexes a nil. Phase 28 shipped that
-- bug and it is the reason this note exists on both ledgers.
function GameConfig.GetExpeditionLedger(data, now)
	data.Expeditions = data.Expeditions or {}
	local ledger = data.Expeditions
	ledger.Best = ledger.Best or {}
	ledger.Cleared = ledger.Cleared or {}

	local today = math.floor((now or os.time()) / 86400)
	if ledger.Day ~= today then
		ledger.Day = today
		ledger.DayRuns = 0
	end
	ledger.DayRuns = ledger.DayRuns or 0
	return ledger
end

-- ===== WHAT THE DOOR SAYS AND WHAT THE SERVER BILLS -- ONE FUNCTION =====
--
-- Pure over the save, the `GetSplicerRollCost` / `GetMinigameStatus` shape and for the same reason:
-- the briefing panel is drawn from the payload the server just pushed, so the runs-left on screen is
-- not a client-side estimate of it -- it IS the call the server refuses an entry with.
--
-- Returns a table rather than a boolean because every refusal is worded differently, and a panel
-- that says "not ready" to all of them is the panel players ask about in the group chat.
function GameConfig.GetExpeditionStatus(data, key, now)
	local expedition = GameConfig.GetExpedition(key)
	if not expedition then
		return { ready = false, reason = "none" }
	end
	if not data then
		return { ready = false, reason = "none", expedition = expedition }
	end

	local ledger = GameConfig.GetExpeditionLedger(data, now)
	local runsLeft = math.max(GameConfig.ExpeditionDailyRuns - ledger.DayRuns, 0)

	local status = {
		expedition = expedition,
		best = ledger.Best[key] or 0,
		cleared = ledger.Cleared[key] or 0,
		par = GameConfig.GetExpeditionPar(expedition),
		runsLeft = runsLeft,
		dailyRuns = GameConfig.ExpeditionDailyRuns,
		stations = #expedition.stations,
	}

	if (data.StageIndex or 1) < (expedition.minStageIndex or 1) then
		status.ready = false
		status.reason = "stage"
	elseif runsLeft <= 0 then
		status.ready = false
		status.reason = "capped"
	else
		status.ready = true
		status.reason = "ready"
	end
	return status
end

-- What one STATION pays. The arcade's own curve, quoted rather than copied: `GetMinigameReward` is
-- pure over `(kind, score, data)` and knows nothing about where the score came from, so a station
-- and a terminal pay identically for identical play. That is the property that makes the expedition
-- feel like the same game rather than a second economy.
function GameConfig.GetStationReward(expedition, index, score, data)
	local kind = GameConfig.GetStationKind(expedition, index)
	if not kind then
		return { dna = 0, beatPar = false, score = 0, share = 0 }
	end
	return GameConfig.GetMinigameReward(kind, score, data)
end

-- What the RUN pays on top, once, at the end. The stations have already paid for themselves; this is
-- the completion bonus and the chest, and it is the only thing a player forfeits by dying or leaving
-- -- which is what makes the last chamber worth walking into.
function GameConfig.GetExpeditionFinishReward(expedition, totalScore, data)
	local par = GameConfig.GetExpeditionPar(expedition)
	local beatPar = totalScore >= par

	local chests = GameConfig.ExpeditionChest
	if beatPar then
		chests += GameConfig.ExpeditionChestParBonus
	end

	-- Diamonds only below the forge stage, where a chest cannot be opened yet. Above it the chest IS
	-- the reward and a diamond on top would be paying twice for one ending.
	local diamonds = 0
	if not GameConfig.IsRelicForgeUnlocked(data) then
		diamonds = GameConfig.ExpeditionDiamondsBeforeForge
	end

	return {
		chests = chests,
		diamonds = diamonds,
		beatPar = beatPar,
		par = par,
		totalScore = totalScore,
	}
end

-- ===== A STATION NAMING A GAME THAT DOES NOT EXIST IS A BUG, AND IT SAYS SO AT LOAD =====
--
-- The station list is written out by hand precisely so a route can be re-themed, and the cost of
-- that choice is that a typo leaves a station that can never be played. This runs once, at load,
-- costs a handful of lookups, and names the expedition and the index.
for _, expedition in ipairs(GameConfig.ExpeditionList) do
	for index, station in ipairs(expedition.stations) do
		if not GameConfig.MinigameKindsByKey[station.kind] then
			warn(("[GameConfig.Expeditions] %s station %d names an unknown minigame %q")
				:format(expedition.key, index, tostring(station.kind)))
		end
	end
end

end
