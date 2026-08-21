-- GameConfig.Minigames -- the four arcade games, what they pay, and how often they may be played.
--
-- ONE OF THE PARTS OF `GameConfig` (18.9). It is handed the shared config table and writes into it;
-- see the loader in `GameConfig` itself for why the order of the parts is load-bearing. This one is
-- required LAST because it reads `GameConfig.Zones` (to check every zone has a game) and quotes
-- `GameConfig.ScaleReward` at call time.
--
-- =====================================================================================
-- WHY FOUR SCREEN GAMES AND NOT FOUR WORLD ARENAS (28.1, owner's steer)
-- =====================================================================================
-- The first design was world-based -- collect orbs in the zone, survive a collapsing floor. Both
-- die on the same measurement: the player body is `BodyScale 5` at stage 20, a 45 x 42 x 35 stud
-- box that walks at 280 stud/s and covers 172 studs in one jump. An arena that a stage-1 Cell can
-- cross in eight seconds is one hop for a stage-20 body, so every world minigame would have needed
-- either a per-player arena scale (impossible -- the arena is shared geometry) or a temporary body
-- normalisation (a teleport, a costume rebuild and a restore path, all of it fragile).
--
-- The owner's steer was Animal Jam Classic, and the whole AJ Classic arcade is 2D SCREEN games.
-- A screen game does not care how big the body is. That single property is why all four of these
-- are drawn in a `ScreenGui` and why none of them needed a stud of new world geometry beyond the
-- terminal that opens them.
--
-- Each is a direct lift of an AJ Classic game, reskinned to the lab:
--   Double Up      -> DNA Match     (memory pairs)
--   Spider Zapper  -> Phantom Purge (tap the targets before they split)
--   Super Sort     -> Sample Sort   (route falling samples into the right beaker)
--   Falling Phantoms -> Containment (slide a dish, dodge what falls)
--
-- =====================================================================================
-- WHAT A GAME PAYS, AND WHY IT IS AUTHORED IN STAGE-1 CLICKS
-- =====================================================================================
-- `payoutClicks` is how many stage-1 clicks a PERFECT run is worth, and the payout runs through
-- `GameConfig.ScaleReward` exactly as the daily board's DNA does. That is the only reward shape
-- that survives this economy: income doubles per upgrade tier across twenty stages, so any flat
-- number is overpowered at stage 3 and invisible at stage 12. Authored this way, a minigame is
-- worth the same number of KILLS at stage 20 as it was at stage 1.
--
-- Sizing, against the numbers already in the game: a stage-1 click is 1.3 DNA, day 1 of the daily
-- board is 200 DNA and day 7 is 23,000. A perfect run here is 900 clicks (~1,170 DNA), a par run
-- about half that. At the daily cap of twelve plays that is roughly a day-6 login -- worth crossing
-- the map for, and not a replacement for the tycoon loop it sits beside.
--
-- DIAMONDS ARE FLAT AND CAPPED, for the reason 21.2 gives for keeping them out of `ScaleReward`:
-- they buy fixed-price permanent upgrades (5/8/15), so a scaled diamond is a broken diamond. One
-- per run that beats par, three a day, and that is the whole faucet.
--
-- =====================================================================================
-- THE COOLDOWN IS PER ZONE, THE CAP IS PER DAY
-- =====================================================================================
-- Per zone, because twenty terminals with one shared cooldown is nineteen terminals that are always
-- dark -- and walking to a different zone to find a ready one is the reason the terminals are spread
-- across the map rather than standing in a row at spawn. Per day for the cap, because that is the
-- number that decides what the feature is worth to the economy, and it has to be one number rather
-- than twenty.

return function(GameConfig)

-- Seconds before the same zone's terminal will run again for the same player.
GameConfig.MinigameCooldown = 300

-- Runs per UTC day across ALL zones. Twelve is the economy number -- see the sizing note above.
GameConfig.MinigameDailyPlays = 12

-- Diamonds a player may earn from minigames in one UTC day, however many par runs they post.
GameConfig.MinigameDailyDiamonds = 3

-- ===== THE FOUR GAMES =====
--
-- `seconds` is the clock the client counts down and the server bills against. `minSeconds` is the
-- floor an honest run cannot come in under and is the cheap half of the anti-cheat (see
-- `GameConfig.ClampMinigameScore`). `maxScore` is the other half: the highest score the game can
-- physically produce, so a client that reports more is clamped rather than believed.
--
-- `par` is a good run, not a perfect one. It is what the terminal advertises, what earns the
-- diamond, and what the payout curve is bent around -- a player who never beats par still gets a
-- fair share of the DNA, which is what stops the arcade being a wall.
GameConfig.MinigameKinds = {
	{
		key = "Match",
		name = "DNA Match",
		emoji = "\u{1F9EC}",
		blurb = "Flip the samples two at a time and pair them up before the clock runs out.",
		howTo = "Tap two cards. A pair stays face up.",
		seconds = 60,
		minSeconds = 10,
		-- Six pairs. 100 a pair, plus up to 300 for finishing early (5 a second remaining).
		pairs = 6,
		pairPoints = 100,
		timeBonusPerSecond = 5,
		maxScore = 900,
		par = 620,
		payoutClicks = 900,
	},
	{
		key = "Purge",
		name = "Phantom Purge",
		emoji = "\u{2622}",
		blurb = "Contaminated cells surface one at a time. Tap each one before it divides.",
		howTo = "Tap the glowing cell. Miss one and it splits.",
		seconds = 40,
		minSeconds = 10,
		-- A cell is up for `showFor` and the next arrives after `gap`, both shrinking toward the
		-- floors as the run goes on. `maxScore` is the whole clock spent at the fastest cadence:
		-- 40 / (0.62 + 0.30) = 43 cells at 25 points, rounded up to a round number the server can
		-- clamp against without a simulation.
		showForStart = 1.25,
		showForFloor = 0.62,
		gapStart = 0.75,
		gapFloor = 0.30,
		hitPoints = 25,
		missPenalty = 10,
		maxScore = 1100,
		par = 620,
		payoutClicks = 900,
	},
	{
		key = "Sort",
		name = "Sample Sort",
		emoji = "\u{1F9EA}",
		blurb = "Samples drop from the centrifuge. Send each one to the beaker of its own colour.",
		howTo = "Tap the beaker that matches the falling sample.",
		seconds = 45,
		minSeconds = 10,
		-- Three beakers. A sample falls in `fallStart` seconds and speeds up to `fallFloor`.
		beakers = 3,
		fallStart = 1.9,
		fallFloor = 0.85,
		hitPoints = 45,
		missPenalty = 20,
		maxScore = 1350,
		par = 700,
		payoutClicks = 900,
	},
	{
		key = "Containment",
		name = "Containment",
		emoji = "\u{1F6E1}",
		blurb = "Hold the sample dish steady while the phantoms rain down. Three hits and it breaks.",
		howTo = "Slide the dish. Dodge the phantoms, catch the green DNA.",
		seconds = 45,
		minSeconds = 10,
		-- 15 a second survived is 675 for a clean run; a caught orb is 45 on top, and the run ends
		-- early at three hits. `maxScore` allows a generous number of catches over the clock.
		lives = 3,
		survivePointsPerSecond = 15,
		catchPoints = 45,
		spawnStart = 0.90,
		spawnFloor = 0.34,
		maxScore = 1500,
		par = 760,
		payoutClicks = 900,
	},
}

GameConfig.MinigameKindsByKey = {}
for _, kind in ipairs(GameConfig.MinigameKinds) do
	GameConfig.MinigameKindsByKey[kind.key] = kind
end

-- ===== WHICH GAME STANDS IN WHICH ZONE =====
--
-- The four cycle across the twenty zones, and the cycle is OFFSET rather than in order: a player
-- walking the strip meets all four inside the first four zones, and no two adjacent zones ever run
-- the same game. Written out by zone key rather than computed with a modulo so a zone can be
-- re-themed later without anybody having to work out what `(i - 1) % 4` was protecting.
GameConfig.MinigameByZone = {
	Forest          = "Match",
	Desert          = "Purge",
	Ocean           = "Sort",
	Volcano         = "Containment",
	Moon            = "Match",
	Mars            = "Purge",
	Galaxy          = "Sort",
	BlackHole       = "Containment",
	Multiverse      = "Match",
	Nebula          = "Purge",
	Wormhole        = "Sort",
	QuantumRealm    = "Containment",
	TimeRift        = "Match",
	AntimatterZone  = "Purge",
	DreamDimension  = "Sort",
	MirrorUniverse  = "Containment",
	VoidExpanse     = "Match",
	CelestialThrone = "Purge",
	Singularity     = "Sort",
	AbsolutePlane   = "Containment",
}

-- The game standing in a zone, or nil if that zone has none. Returns the KIND table itself, so
-- every caller reads the same row -- the terminal that advertises it, the client that plays it and
-- the server that pays for it.
function GameConfig.GetMinigame(zoneKey)
	local key = GameConfig.MinigameByZone[zoneKey]
	return key and GameConfig.MinigameKindsByKey[key] or nil
end

-- UTC day number, the same boundary `LastRewardClaim` and the free spin roll over on. One
-- definition, quoted by the cap below and by the service that writes the ledger.
--
-- `os.time()`, NOT `GameConfig.UtcTimestamp()`. That function is a SPEC CONVERTER -- it turns an
-- authored `{year, month, day, hour, min}` into a timestamp (see `GameConfig.Events`) -- and
-- calling it with no argument indexes a nil, which is exactly the shape of `os.time`'s optional
-- table argument and exactly why the name reads like a clock. `os.time()` already returns Unix
-- UTC seconds and is what every other day-boundary in this game is measured with:
-- `RewardService.dayNumber`, `PlaytimeGiftService.today`, `PassService`.
function GameConfig.MinigameDayNumber(timestamp)
	return math.floor((timestamp or os.time()) / 86400)
end

-- ===== THE LEDGER =====
--
-- `data.Minigames` is `{ Plays = {zoneKey -> lastFinishedTimestamp}, Day = <day number>,
-- DayPlays = n, DayDiamonds = n, Best = {kindKey -> best score} }`.
--
-- Shaped HERE rather than in `defaultData`, for the reason `Season` and `Quests` are shaped by
-- their own services: which day a save belongs to is decided by the clock at read time, so an empty
-- table is the correct starting value and the first touch fills it in. Every reader goes through
-- this function, so a save written before the arcade existed is repaired by being looked at.
--
-- IT ROLLS THE DAY OVER ITSELF, and that is why it is not a plain accessor: a player who left
-- yesterday holding twelve plays must find twelve waiting, and the only moment anybody can notice
-- the date changed is the moment they ask.
function GameConfig.GetMinigameLedger(data, now)
	data.Minigames = data.Minigames or {}
	local ledger = data.Minigames
	ledger.Plays = ledger.Plays or {}
	ledger.Best = ledger.Best or {}

	local today = GameConfig.MinigameDayNumber(now)
	if ledger.Day ~= today then
		ledger.Day = today
		ledger.DayPlays = 0
		ledger.DayDiamonds = 0
	end
	ledger.DayPlays = ledger.DayPlays or 0
	ledger.DayDiamonds = ledger.DayDiamonds or 0
	return ledger
end

-- ===== WHAT THE TERMINAL SAYS, AND WHAT THE SERVER BILLS -- ONE FUNCTION =====
--
-- Pure over the save, the `GetSplicerRollCost` shape and for the same reason: the client draws this
-- panel from the payload the server just pushed, so the cooldown on screen is not a client-side
-- estimate of the cooldown, it IS the server's answer. The two cannot drift.
--
-- Returns a table rather than a bare boolean because every refusal has to be worded differently --
-- "come back in 3:20" and "you have played twelve today" are not the same message, and a panel that
-- says "not ready" to both is the panel players ask about in the group chat.
function GameConfig.GetMinigameStatus(data, zoneKey, now)
	now = now or os.time()
	local kind = GameConfig.GetMinigame(zoneKey)
	if not kind then
		return { ready = false, reason = "none" }
	end
	if not data then
		return { ready = false, reason = "none", kind = kind }
	end

	local ledger = GameConfig.GetMinigameLedger(data, now)
	local playsLeft = math.max(GameConfig.MinigameDailyPlays - ledger.DayPlays, 0)
	local last = ledger.Plays[zoneKey] or 0
	local elapsed = now - last
	local wait = math.max(GameConfig.MinigameCooldown - elapsed, 0)

	local status = {
		kind = kind,
		best = ledger.Best[kind.key] or 0,
		playsLeft = playsLeft,
		dailyPlays = GameConfig.MinigameDailyPlays,
		diamondsLeft = math.max(GameConfig.MinigameDailyDiamonds - ledger.DayDiamonds, 0),
		secondsLeft = wait,
	}

	if playsLeft <= 0 then
		status.ready = false
		status.reason = "capped"
	elseif wait > 0 then
		status.ready = false
		status.reason = "cooldown"
	else
		status.ready = true
		status.reason = "ready"
	end
	return status
end

-- ===== THE HALF OF THE ANTI-CHEAT THAT LIVES IN THE CONFIG =====
--
-- A screen game is played on the client and the score arrives over a remote, so the honest reading
-- is: this is BOUNDED, not proven. Two bounds, both cheap and both here so the client can quote the
-- same ceiling it will be judged against:
--   * the score is clamped to what the game can physically produce in its own clock, and
--   * a run that comes back faster than `minSeconds` is refused outright.
-- Everything past that is paid for by the cooldown and the daily cap: the worst a perfect forgery
-- can win is the same twelve runs an honest player gets.
function GameConfig.ClampMinigameScore(kind, score)
	local n = tonumber(score) or 0
	if n ~= n then return 0 end -- NaN survives every comparison below; it does not survive this
	return math.clamp(math.floor(n), 0, kind.maxScore)
end

-- What a run pays. Linear in the score up to par, then the last stretch to a perfect run is worth
-- the same again -- so par is a target rather than a ceiling, and the difference between a scrappy
-- run and a clean one is visible without the scrappy run being worthless.
--
-- `data` is threaded through only to reach `ScaleReward`; the SHAPE of the reward is the same at
-- every stage, which is the property the whole payout design rests on.
function GameConfig.GetMinigameReward(kind, score, data)
	local clamped = GameConfig.ClampMinigameScore(kind, score)
	local par = math.max(kind.par, 1)

	-- Half the payout is earned on the way to par, the other half between par and perfect.
	local share
	if clamped <= par then
		share = 0.5 * (clamped / par)
	else
		local over = (clamped - par) / math.max(kind.maxScore - par, 1)
		share = 0.5 + 0.5 * math.clamp(over, 0, 1)
	end

	local clicks = math.floor(kind.payoutClicks * share)
	return {
		dna = GameConfig.ScaleReward(clicks, data),
		beatPar = clamped >= par,
		score = clamped,
		share = share,
	}
end

-- ===== A ZONE WITHOUT A GAME IS A BUG, AND IT SAYS SO AT LOAD =====
--
-- The map above is written out by hand precisely so a zone can be re-themed, and the cost of that
-- choice is that adding a twenty-first zone silently leaves it with a dark terminal. This is the
-- tripwire: it runs once, at load, costs twenty table lookups, and names the zone.
for _, zone in ipairs(GameConfig.Zones) do
	if not GameConfig.MinigameByZone[zone.key] then
		warn(("[GameConfig.Minigames] zone %q has no minigame -- its terminal will not build")
			:format(zone.key))
	end
end

end
