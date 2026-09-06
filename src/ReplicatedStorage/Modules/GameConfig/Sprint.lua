-- GameConfig.Sprint -- the Sprint Track's ladder and its economy (17.5).
--
-- ONE OF THE PARTS OF `GameConfig` (18.9): `return function(GameConfig)`, writing into the table it
-- is handed. Appended LAST, and it is the same argument every part above it made in turn -- nothing
-- in here is read at load time by anything above it, every constant below is literal, and the one
-- thing it quotes off the table (`GameConfig.MinigameDayNumber`) is quoted at CALL time from a part
-- that loads several names earlier. Appending is the only move that cannot produce the silent nil
-- the loader's own header warns about.
--
-- ===== WHAT 17.5 ASKED FOR, AND WHICH HALF OF IT WAS ALREADY BUILT =====
--
-- Her words, 2026-08-16: *"pogledaj malo +1 ili evolution roblox igre pa iskopiraj speed ima i one
-- trake za trcanje"* -- look at the +1 / evolution games, copy the speed, they have those running
-- strips.
--
-- THE SPEED HALF SHIPPED UNDER ANOTHER ROW AND MUST NOT BE BUILT TWICE. 34.29 deleted
-- `GameConfig.Upgrades.Speed` outright and made the five trails in `Cosmetics` the speed ladder,
-- priced in Evolution Shards -- her call, *"nema vise speed u shopu da se kupi vec nek bude vise
-- ovih trails i one ce da upgradaju speed"*. So by the time this row came up its first sentence
-- ("this game has a Speed upgrade in a shop panel") had expired, exactly the way 19.1's terms had.
--
-- WHAT WAS STILL MISSING IS THE PLACE. There was nothing in the world that was ABOUT moving. The
-- waterfall climb and the twenty adventure courses are obstacle courses -- they are about not
-- falling -- and neither of them is a thing you go to in order to run.
--
-- ===== WHY THE TRACK PAYS SHARDS AND NOT SPEED =====
--
-- The obvious design is a permanent walk-speed ladder banked by running laps, and it is wrong here
-- for a reason that is already written down twice in this codebase. `GameConfig.MaxWalkSpeed` is
-- NOT A BALANCE NUMBER -- `EvolutionVisuals.applyMastery` says so at the clamp -- it is the speed
-- past which a player outruns StreamingEnabled. And the two sources that are allowed to exceed it
-- (a worn mutation aura and a worn trail) are BOUNDED TOGETHER AT 20% at that same clamp,
-- deliberately, after a note explaining that 32% was already too much. A third permanent source
-- would either have to break that bound or be invisible under it.
--
-- So the track pays the currency the speed ladder is PRICED IN. Running is how you afford the next
-- trail, and the trail is what makes you permanently faster -- which is the same loop the genre
-- runs, one step of indirection longer, and it needs no new term anywhere near the walk clamp.
--
-- SIZED AGAINST THE ONLY OTHER SHARD SOURCE IN THE GAME. Shards are minted by raised creatures and
-- nothing else (`ShardDropChance`, 9.4 / 11.31): a full sweep of one zone's shelves pays 3.32 for a
-- 3-rebirth player, a wheel spin costs 25 and the trail ladder runs 5 / 40 / 110 / 250 / 500. Eight
-- runs a day at 1-3 shards is at most 24 -- about one spin, or a third of the second trail rung --
-- so the track is a real second tap on a currency that had one, and it is nowhere near a bypass of
-- the terraces. The one-off first-finish bonus is 10, which buys the first trail twice over: that
-- is the point, because the first trail is what tells a new player the ladder exists at all.
--
-- ===== AND WHY THE PROFILE IS FIXED RATHER THAN THE PLAYER'S OWN SPEED =====
--
-- `AdventureMap`'s header already settled this for the only other timed movement in the game: the
-- course is cut against a FIXED walk and jump "so the same course is playable by a stage-one body
-- and a stage-twenty one", and `AdventureService` forces both onto the humanoid for the duration
-- of a run. A time trial needs it for a second reason on top: the payout bands below are the same
-- seconds for everybody, so if the speed came from the body then a stage-one player could never
-- reach the top band however well they ran, and a stage-twenty one could never miss it however
-- badly. The track is a test of the strips you hit, not of the stage you are at.
--
-- The ramp tops out at 124, which is under both walk ceilings the game ships (150, and 260 for the
-- 2x Speed pass) and just under the 127 an unbought stage-20 body already runs. Nobody is made
-- faster than the game already allows by standing here.

return function(GameConfig)

-- ===== THE RUN =====
--
-- `SprintBaseSpeed` is what the humanoid is set to on GO, `SprintPadStep` is what each boost strip
-- adds, and `SprintMaxSpeed` is the clamp. Six strips at +14 on a base of 40 reaches 124 exactly,
-- so the clamp is the ladder's own top rather than a cut-off -- a seventh strip would be the first
-- one that paid nothing, which is the shape a ladder should have when somebody adds to it.
GameConfig.SprintBaseSpeed = 40
GameConfig.SprintPadStep = 14
GameConfig.SprintMaxSpeed = 124

-- The stock jump, unchanged from `GameConfig.BaseJumpPower`, and stated here rather than read from
-- there so a jump change made for the world at large cannot silently retime this race. R15 needs
-- `UseJumpPower` flipped before either number is worth anything -- the trap
-- `EvolutionVisuals.applyMastery` documents and `AdventureService` repeats.
GameConfig.SprintJumpPower = 44

-- Seconds of "3 .. 2 .. 1 .. GO", frozen on the line. It exists so the clock starts for everybody
-- at the same moment relative to their first step, which a race timed from a prompt press does not.
GameConfig.SprintCountdown = 3

-- The leash. A run that neither finishes nor leaves the box is ended here, and refunded nothing --
-- the run was billed at the start (see the note over `GetSprintStatus`). Generous on purpose: a
-- zero-strip run down the whole lane at the base speed takes about six seconds.
GameConfig.SprintTimeout = 45

-- Runs per UTC day. Eight against the arcade's twelve, because a run is under ten seconds and an
-- arcade game is sixty: the two come out at roughly the same minutes of play, which is the number
-- the daily caps are actually rationing.
GameConfig.SprintDailyRuns = 8

-- ===== WHAT A FINISH PAYS =====
--
-- Bands rather than a curve, because the number has to be legible on an arch from forty studs away
-- and "you were 0.31 s off gold" is a thing a player can act on where "you earned 2.4 shards" is
-- not. They are the same seconds for every player, for the reason the fixed profile exists.
--
-- ===== THE SECONDS ARE MEASURED, AND THERE ARE TWO LEVERS WORTH THE SAME =====
--
-- Two runs were driven end to end down the built lane on 2026-09-06 and timed by the server:
--
--                          no sprint      holding Shift
--   all six strips           4.55 s          3.25 s
--   not one strip            6.39 s          4.56 s
--
-- The right-hand column is EXACT rather than estimated: `CombatClient`'s sprint multiplies whatever
-- the server set by 1.4, every segment of the lane scales by the same factor and the path does not
-- change, so the time divides by 1.4 precisely.
--
-- Read the table and the design falls out of it. **The strips are worth 6.39 / 4.55 = 1.40, and the
-- sprint key is worth 1.40 -- the two levers are worth the same to three figures.** That was not
-- arranged and it is what the bands are cut against: GOLD needs BOTH (3.25 clears 3.60 with 10% of
-- slack; either lever alone lands at 4.55 / 4.56 and misses), SILVER needs ONE (both of those clear
-- 5.00 with about 9%), and doing neither is 6.39 and takes the BRONZE that every finisher gets.
--
-- Retune these first when there is a day of real players, and retune them TOGETHER: moving one
-- without the other collapses a three-band ladder into a two-band one.
--
-- Ordered fastest first; `GetSprintBand` returns the first one the time fits, so the last row must
-- always be the catch-all.
GameConfig.SprintBands = {
	{ key = "gold",   name = "GOLD",   emoji = "\u{1F947}", maxSeconds = 3.60, shards = 3,
	  color = Color3.fromRGB(255, 200, 60) },
	{ key = "silver", name = "SILVER", emoji = "\u{1F948}", maxSeconds = 5.00, shards = 2,
	  color = Color3.fromRGB(214, 222, 235) },
	{ key = "bronze", name = "BRONZE", emoji = "\u{1F949}", maxSeconds = math.huge, shards = 1,
	  color = Color3.fromRGB(214, 138, 80) },
}

-- Paid once ever, on the first finish, and deliberately worth two rungs of the trail ladder: a
-- player who has never opened the Trails tab is told it exists by being handed enough to shop in
-- it. `PhotoTaken` is the precedent for a once-forever gift that a rebirth does not clear.
GameConfig.SprintFirstFinishShards = 10

function GameConfig.GetSprintBand(seconds)
	for _, band in ipairs(GameConfig.SprintBands) do
		if seconds <= band.maxSeconds then return band end
	end
	return GameConfig.SprintBands[#GameConfig.SprintBands]
end

-- ===== THE LEDGER =====
--
-- `data.Sprint` is `{ Day = <day number>, DayRuns = n, Finishes = n, Best = seconds }`.
--
-- Shaped HERE and not in `defaultData`, which is the shape `GetMinigameLedger` established and for
-- the same reason: which day a save belongs to is decided by the clock at READ time, so an empty
-- table is the correct starting value and the first touch fills it in. Every reader goes through
-- this function, so a save written before the track existed is repaired by being looked at.
--
-- IT ROLLS THE DAY OVER ITSELF. A player who left yesterday holding eight runs must find eight
-- waiting, and the only moment anybody can notice the date changed is the moment they ask.
--
-- The day number is `MinigameDayNumber` rather than a second copy of `floor(t / 86400)`: two
-- definitions of "today" in one save is how a feature ends up rolling over an hour after the one
-- beside it.
function GameConfig.GetSprintLedger(data, now)
	data.Sprint = data.Sprint or {}
	local ledger = data.Sprint

	local today = GameConfig.MinigameDayNumber(now)
	if ledger.Day ~= today then
		ledger.Day = today
		ledger.DayRuns = 0
	end
	ledger.DayRuns = ledger.DayRuns or 0
	ledger.Finishes = ledger.Finishes or 0
	-- 0 means "no time set". A best time is a MINIMUM, so it cannot be initialised to zero and then
	-- compared with `<` -- every reader below treats 0 as absent instead.
	ledger.Best = ledger.Best or 0
	return ledger
end

-- Pure over the save, the `GetMinigameStatus` shape and for the identical reason: the arch and the
-- prompt draw what the SERVER will bill, not a client-side guess at it, so the two cannot drift.
--
-- A RUN IS BILLED AT THE START, NOT AT THE FINISH -- the arcade's decision, taken again here for a
-- sharper reason: this race is scored on time, so a player who could abandon a bad start for free
-- would restart until the clock suited them and the best time would mean nothing.
function GameConfig.GetSprintStatus(data, now)
	now = now or os.time()
	if not data then
		return { ready = false, reason = "none", runsLeft = 0,
			dailyRuns = GameConfig.SprintDailyRuns, best = 0, finishes = 0 }
	end
	local ledger = GameConfig.GetSprintLedger(data, now)
	local runsLeft = math.max(GameConfig.SprintDailyRuns - ledger.DayRuns, 0)
	return {
		ready = runsLeft > 0,
		reason = runsLeft > 0 and "ok" or "capped",
		runsLeft = runsLeft,
		dailyRuns = GameConfig.SprintDailyRuns,
		best = ledger.Best or 0,
		finishes = ledger.Finishes or 0,
	}
end

-- Two decimals and a unit, in one place, because the arch, the result card and the toast all print
-- it and a race whose three surfaces round differently is a race players argue about.
function GameConfig.FormatSprintTime(seconds)
	if not seconds or seconds <= 0 then return "--.--s" end
	return ("%.2fs"):format(seconds)
end

end
