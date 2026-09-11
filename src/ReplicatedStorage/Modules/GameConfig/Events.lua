-- GameConfig.Events -- limited-time events: the UTC windows, the effects they reuse and which skin an occurrence hands over.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ============================================================================
-- LIMITED-TIME EVENTS
-- ============================================================================
-- A window in time during which the rules are different for EVERYONE on the server at once. The
-- genre runs on these -- Grow a Garden and Steal a Brainrot are both driven by them -- and this
-- game had no concept anywhere in it of "right now is different from yesterday".
--
-- =========================================================================================
-- AN EVENT IS A FUNCTION OF THE CLOCK. IT IS NEVER A FIELD IN A SAVE.
-- =========================================================================================
-- Pass ownership is cached into `data.Passes` because it comes from a web call that can fail, so
-- the answer has to be kept somewhere. An event is arithmetic on a timestamp: it cannot fail, it
-- cannot disagree between two servers, and every reader works it out for itself without asking.
--
-- Storing it in a save would break at both ends of the window. A player online when it closes keeps
-- the boost until something remembers to refresh them, and a player who logged off inside the
-- window carries a stale multiplier into next week -- which is the free-pass bug `data.Passes` is
-- reset on every load to prevent, except that here there is nothing to reset because nothing was
-- ever written.
--
-- =========================================================================================
-- EVERY WINDOW IS UTC, AND THE `!` IS THE WHOLE FEATURE
-- =========================================================================================
-- `os.date("*t")` is the machine's local time; `os.date("!*t")` is UTC. A live Roblox server runs
-- UTC, so the two agree there and the mistake is invisible in production -- but a Studio session
-- runs on whatever the developer's machine says, and that is the only machine this ever gets tested
-- on. A weekend authored against local time starts two hours early here and on time in production:
-- it looks correct in exactly the place where it is wrong.
--
-- =========================================================================================
-- EFFECTS REUSE THE GAME PASS FIELD NAMES
-- =========================================================================================
-- `incomeMult`, `xpMult`, `damageMult`, `luckAdd` -- the same names GetPassMult and GetPassAdd
-- read. So DNAService.GetIncomeMult gained one line directly beneath its pass line and learned
-- nothing about what an event is, and a new effect is a field on both sides rather than a call site.
GameConfig.Weekday = { Sun = 1, Mon = 2, Tue = 3, Wed = 4, Thu = 5, Fri = 6, Sat = 7 }

local EVENT_DAY = 86400
local EVENT_WEEK = 7 * EVENT_DAY

local eventClockOffset = 0

-- THE ONE CLOCK EVERY WINDOW IN THIS SECTION IS MEASURED AGAINST.
--
-- On the server it is `os.time()` exactly -- a Roblox server's clock is UTC and authoritative, and
-- the offset stays 0 forever.
--
-- On a client it is the SERVER's clock, learned from the payload EventService publishes. A player
-- whose machine is set a day fast would otherwise be shown a weekend that is not running, count
-- down to the wrong minute, and conclude the HUD is lying when their DNA arrives at the normal
-- rate. The client never decides what is live; it is only told, and this is where it keeps the
-- answer.
--
-- It is also the single seam a test moves: shifting it forward makes a future window live without
-- editing an authored date, which is the only way to exercise a launch festival before the launch.
function GameConfig.SetEventClock(serverNow)
	eventClockOffset = (tonumber(serverNow) or os.time()) - os.time()
	return eventClockOffset
end

function GameConfig.GetEventClockOffset()
	return eventClockOffset
end

function GameConfig.EventNow()
	return os.time() + eventClockOffset
end

-- How far this machine's clock is from UTC at `at`, measured rather than assumed.
--
-- Roblox reads the table form of `os.time` as UTC, in which case this returns 0 and the correction
-- below is a no-op. Standard Lua reads it as local time, in which case this returns exactly the
-- offset needed to undo that. The same expression is right in both worlds, which is why it is a
-- measurement and not a branch -- a branch here would have to guess which host it is running on.
local function utcOffsetAt(at)
	local u = os.date("!*t", at)
	u.isdst = false
	return at - os.time(u)
end

-- {year, month, day, hour, min} read as UTC -> a timestamp. A plain number passes through, so a
-- window can be authored either way.
local function utcTimestamp(spec)
	if type(spec) == "number" then return spec end
	local naive = os.time({
		year = spec[1], month = spec[2], day = spec[3],
		hour = spec[4] or 0, min = spec[5] or 0, sec = 0,
	})
	return naive + utcOffsetAt(naive)
end
GameConfig.UtcTimestamp = utcTimestamp

-- ===== THE EVENTS =====
--
-- `recurring` = { wday, hour, hours } in UTC, repeating every week.
-- `fixed`     = { from = {y,m,d,h,mi}, to = {...} } in UTC, happening once.
--
-- WHY THE WEEKEND IS NOT DOUBLE DAMAGE. It doubles what an hour of play PAYS, and leaves how hard
-- a creature hits alone. Damage is the pacing of the game -- how many swings a zone takes is what
-- makes one zone feel different from the last -- and 2.12 already measured that a damage multiplier
-- mostly removes wasted swings anyway, because BOSS_MIN_HITS caps a single blow at a share of the
-- target's health. An event should make the grind worth more, not make it disappear.
--
-- The weekend runs from 00:00 UTC on Saturday for 48 hours. That is Friday evening to Sunday
-- evening in the Americas and the whole of Saturday and Sunday in Europe -- there is no single
-- window that is a weekend everywhere, and UTC is at least the one every server agrees on.
GameConfig.Events = {
	{
		key = "Weekend2x",
		name = "Weekend Rush",
		emoji = "\u{1F525}",
		blurb = "Double DNA and double XP for everyone",
		color = Color3.fromRGB(255, 138, 76),
		recurring = { wday = GameConfig.Weekday.Sat, hour = 0, hours = 48 },
		effects = { incomeMult = 2, xpMult = 2 },
		-- Priority 0 (the default) on purpose, and it is the LOWER of the two weekend events -- see
		-- the note over ColosseumClash for why the one that changes every week is the one that
		-- headlines the board.
	},
	-- ===== THE WEEKEND COLOSSEUM (12.13) =====
	--
	-- The same window as Weekend Rush, deliberately: the two are one weekend, not two occasions, and
	-- a player who logs in on Saturday should find everything on at once rather than learn a
	-- schedule. What it adds is the half the game had no event for -- the Colosseum giant, which is
	-- already the only thing on a timer and the only thing a whole server does together.
	--
	-- WHY IT IS NOT ANOTHER incomeMult. Weekend Rush already doubles what an hour of ordinary play
	-- pays. Stacking a second income multiplier on top of it makes the weekend worth 4x and the week
	-- worth nothing, which is how a two-day window stops being a bonus and becomes the only time
	-- worth playing. `bossMult` touches ONE payout -- the giant's DNA and diamonds -- so the reason
	-- to turn up is a specific fight rather than a blanket rate.
	--
	-- THE SKIN ROTATES, AND THAT IS THE ENTIRE RETENTION ARGUMENT. A permanent weekend hands out one
	-- skin forever, so the second weekend has nothing in it for anyone who came to the first. Four
	-- champions on a four-week cycle mean a returning player is looking at something they cannot
	-- have yet, and a collector has a reason to be here on a particular weekend rather than some
	-- weekend. See GameConfig.GetEventRewardKey for how the week is chosen.
	{
		key = "ColosseumClash",
		name = "Colosseum Clash",
		emoji = "\u{2694}\u{FE0F}",
		blurb = "Double giant loot -- finish the event ladder for this week's champion",
		color = Color3.fromRGB(226, 84, 76),
		recurring = { wday = GameConfig.Weekday.Sat, hour = 0, hours = 48 },
		effects = { bossMult = 2 },
		-- WHICH ONE HEADLINES WHEN BOTH ARE LIVE, decided here rather than left to table order.
		-- Every consumer of GetActiveEvents draws `active[1]` and only `active[1]` -- the sign, the
		-- HUD card and GetEventHeadline all do -- so without this the answer would be "whichever was
		-- authored first", which is not a decision anybody made. Weekend Rush is the same every
		-- weekend and every returning player already knows it; the Colosseum's champion is different
		-- this week and is the only thing on the board worth reading twice. The rate boost is not
		-- lost: the HUD card sums the effects of EVERY live event onto one line, and the sign names
		-- the co-runners under the blurb.
		priority = 10,
		-- One rotation entry per week, resolved from the WINDOW's start -- see GetEventRewardKey.
		rotation = {
			"event_clash_ember",
			"event_clash_frost",
			"event_clash_verdant",
			"event_clash_onyx",
		},
	},
	-- The launch festival, and the one event carrying an exclusive skin.
	--
	-- 👤 OWNER: these two dates are a DESIGN DECISION, not an id -- unlike a product or a pass there
	-- is nothing to paste from the dashboard, so they are authored here and are safe to edit. Set
	-- them to the real launch weekend before publishing. Nothing breaks if they stay: the window is
	-- simply in the past or the future, GetEventWindow says so, and no effect and no skin is handed
	-- out until the moment named below.
	{
		key = "GlobalGoal",
		name = "Global Challenge",
		emoji = "\u{1F30D}",
		blurb = "Server-wide objective",
		color = Color3.fromRGB(80, 200, 120),
		recurring = { wday = GameConfig.Weekday.Sat, hour = 0, hours = 48 },
		priority = 20,
		metric = "Kills",
		target = 5000000,
		reward = { diamonds = 500 },
	},
	-- ===== THE SPLICE SURGE (23.6) =====
	--
	-- THE ONE EVENT THAT IS NOT ON THE WEEKEND, AND THAT IS THE REASON IT EXISTS. Weekend Rush,
	-- Colosseum Clash and the Global Challenge all open at 00:00 UTC on Saturday and all close
	-- 48 hours later -- three events, one occasion. The other five days of the week have nothing
	-- in them at all, so a player who cannot be here at the weekend has never once been shown a
	-- reason to log in on a particular day. A second beat mid-week is what a calendar is; a
	-- fourth thing stacked onto Saturday would just be a bigger weekend.
	--
	-- WHY IT IS THE SPLICER AND NOT ANOTHER RATE. An income or XP multiplier is worth more of
	-- what the player was already going to get, which is the shape every event above already has
	-- and the shape that makes an event forgettable -- it changes a number nobody watches. The
	-- Splicer is the game's only ODDS surface, its output is the one permanent object other
	-- players can see from across the map (23.2's chip and its aura), and the top three tiers
	-- announce server-wide on their own (23.3). So a window on this machine is the only one that
	-- fills a server's feed with other people's luck, which is what makes a window worth turning
	-- up for rather than worth having running.
	--
	-- WHY 12:00 UTC AND NOT 00:00 LIKE THE OTHERS. A 48-hour weekend covers every evening on
	-- earth whatever hour it opens; a 24-hour window does not, and the hour is then the whole
	-- design. From 00:00 UTC this window would run Tuesday 17:00 to Wednesday 17:00 Pacific and
	-- miss the Wednesday evening it is named after. From 12:00 UTC it runs Wednesday 05:00 to
	-- Thursday 05:00 Pacific and Wednesday 14:00 to Thursday 07:00 in central Europe -- one
	-- window, both evenings, which is the most a single day can cover.
	--
	-- WHY 150 IS A LITERAL AND NOT `GameConfig.Splicer.pityLuckAdd`. It is deliberately the same
	-- number -- a surge roll carries exactly the luck bonus the charged roll carries, which is
	-- what the blurb says in words -- but this part loads BEFORE `Helpers`, so reading it from
	-- there at load time is the silent nil this file's own loader warns about. The two are kept
	-- equal by the comment on both sides, not by a reference that cannot exist yet.
	--
	-- Priority 15 sits above the Colosseum's 10 and below the Global Challenge's 20, and today it
	-- decides nothing: Wednesday noon to Thursday noon cannot overlap a Saturday window or the
	-- authored festival. It is set because the ordering is a decision (12.13) and the day this
	-- one does co-run -- the launch festival is two dates the owner may move anywhere -- the
	-- board should headline the rarer occasion rather than whichever was typed first.
	{
		key = "SpliceSurge",
		name = "Splice Surge",
		emoji = "\u{1F9EC}",
		blurb = "Every splice rolls with a charged roll's luck -- rare mutations are far likelier",
		color = Color3.fromRGB(90, 220, 210),
		recurring = { wday = GameConfig.Weekday.Wed, hour = 12, hours = 24 },
		effects = { mutationLuck = 150 },
		priority = 15,
		-- No ladder and no skin, for the reason Weekend2x has neither: a ladder ends on an
		-- exclusive character, and there is nothing here to put at the end of one. See
		-- GameConfig.EventQuests, where an event with no entry simply has no board.
	},
	{
		key = "PrismFest",
		name = "Prism Festival",
		emoji = "\u{1F308}",
		blurb = "+50% luck -- finish the event ladder for the Prism Herald skin",
		color = Color3.fromRGB(158, 120, 255),
		fixed = { from = { 2026, 9, 4, 12, 0 }, to = { 2026, 9, 7, 12, 0 } },
		effects = { luckAdd = 50 },
		-- Paid by the LAST RUNG of this event's ladder (26.1) and NEVER taken back afterwards -- see
		-- GameConfig.EventQuests below and GameConfig.EventCharacters.
		reward = { characterKey = "event_prism" },
	},
	-- ===== THE SEASON FESTIVAL (25.2) =====
	--
	-- THE MONTHLY BEAT THE CALENDAR HAD A SLOT FOR AND THE GAME HAD NOTHING IN. `docs/CONTENT-
	-- CALENDAR.md` §3 puts the month's headline on the season turnover and §2 measures the two
	-- monthly cycles that never line up -- the season at 30 days and the Colosseum champion at 28.
	-- Only one of those two had anything a player could SEE turn over: the champion handed out a
	-- skin, the season silently swapped a name and a track. This is the occasion that makes a
	-- turnover an event.
	--
	-- IT IS GENERATED, AND THAT IS THE ROW'S REAL CONTENT. §4 wrote the rule after the PrismFest
	-- hole: *a festival ships with the next festival's dates already authored, or it ships as a
	-- recurring with a rotation like the Colosseum's.* Authoring the next date only moves the cliff
	-- one month; this takes the second half of the rule and generalises it from the week to the
	-- season, so there is no last festival to fall off the end of. `GetDeadEvents` can never name
	-- it, for the same reason it can never name Weekend Rush.
	--
	-- WHY THE EFFECT IS `damageMult` AND WHY THAT IS NOT A CONTRADICTION OF THE WEEKEND'S NOTE.
	-- The note over Weekend Rush refuses a damage multiplier for a WEEKLY event, and the reason it
	-- gives is that damage is the pacing of the game -- how many swings a zone takes is what makes
	-- one zone feel different from the last -- so doubling it every Saturday would mean the game is
	-- only ever half-paced. Seventy-two hours once a month is the opposite case: it is rare enough
	-- that the pacing is intact for twenty-seven days and the three days it is suspended are the
	-- ones the player is meant to remember. It is also the only effect field the game already
	-- routes and no event has ever set -- DNAService's damage chain carries the hook with a comment
	-- saying *the day one does, it is a row in that table and not an edit in this file*. This is
	-- that row, and DNAService did not change.
	--
	-- PRIORITY 30, ABOVE THE GLOBAL CHALLENGE'S 20, and it is the only event in the table that
	-- needs to outrank it. The festival collides with real windows rather than hypothetically: S1's
	-- occurrence opened 00:00 Saturday 2026-08-01 and covered a whole Weekend Rush, and S3's runs
	-- Wednesday 2026-09-30 to Saturday 2026-10-03, swallowing a Splice Surge and ending in the same
	-- second the weekend opens. Three places draw `active[1]` and nothing else (12.13), and on a
	-- turnover weekend the answer has to be the thing that happens twelve times a year, not the
	-- thing that happens every Saturday.
	--
	-- THE SKIN IS ONE PER SEASON THEME, IN THE SAME ORDER, so the herald is named for the season
	-- that hands it over -- Ashfall pays the Cinder Herald. That makes this list and
	-- `GameConfig.SeasonThemes` two parallel lists, which is exactly the shape that rots quietly,
	-- so it is CHECKED rather than commented: `GameConfig.GetSeasonFestivalMismatch` compares the
	-- two and `EventService.Init` warns on a boot where they have drifted apart.
	--
	-- Six themes at 30 days means a herald comes round again after 180 days. That is deliberate and
	-- it is the Colosseum's own argument at a longer wavelength: a rotation is limited because the
	-- window shuts, not because the item is never offered again -- see the note over
	-- ColosseumClash's four champions.
	{
		key = "SeasonFest",
		name = "Season Festival",
		emoji = "\u{1F386}",
		blurb = "Double damage for the season's first three days -- finish the event ladder for this season's Herald",
		color = Color3.fromRGB(255, 176, 92),
		seasonal = { hours = 72 },
		effects = { damageMult = 2 },
		priority = 30,
		-- One entry per season THEME, resolved from the season the window opens in -- see
		-- GetEventRewardKey. The order is SeasonThemes' order and must stay that way.
		rotation = {
			"event_season_dawn",     -- First Light
			"event_season_tide",     -- Deep Currents
			"event_season_cinder",   -- Ashfall
			"event_season_rime",     -- Frostbloom
			"event_season_astral",   -- Starfall
			"event_season_bramble",  -- Overgrowth
		},
	},
}

-- What the HUD chip calls each multiplicative effect field. It lives here rather than in MainUI for
-- two reasons: MainUI is at Luau's 200-local ceiling and a new top-level table there costs the
-- whole HUD, and a new effect field is authored three lines up in GameConfig.Events -- so the
-- reader that would otherwise silently omit it is the one that should be edited in the same file.
-- `luckAdd` is deliberately absent: it is additive and is formatted as a percentage, not an "x".
-- `mutationLuck` (23.6) is absent for the same reason and one more: it is not a percentage of
-- anything the player has a number for, it is luck POINTS entering one roll on one machine, so the
-- only honest place to print it is the odds table that changes when it is live -- which is where
-- SplicerUI's surge chip puts it.
GameConfig.EventEffectLabels = {
	incomeMult = "DNA",
	xpMult = "XP",
	damageMult = "Damage",
	bossMult = "Giant Loot",
}

function GameConfig.GetEvent(key)
	for _, event in ipairs(GameConfig.Events) do
		if event.key == key then return event end
	end
	return nil
end

-- The occurrence of `event` that matters at `now`: when it started (or starts), when it ends,
-- whether it is live, and when the next one begins if it is not. ONE SHAPE FOR BOTH KINDS OF
-- WINDOW, so nothing downstream ever branches on which sort of event it is holding.
function GameConfig.GetEventWindow(event, now)
	if not event then return nil end
	now = now or GameConfig.EventNow()

	if event.fixed then
		local startTs = utcTimestamp(event.fixed.from)
		local endTs = utcTimestamp(event.fixed.to)
		return {
			startTs = startTs,
			endTs = endTs,
			active = (now >= startTs and now < endTs),
			-- A one-off that has finished has NO next occurrence, and saying nil rather than a date
			-- is what lets the countdown board fall through to whatever is actually coming instead
			-- of counting down to something in the past.
			nextStart = (now < startTs) and startTs or nil,
		}
	end

	-- ===== THE THIRD SHAPE: A WINDOW ON THE SEASON'S OWN CLOCK (25.2) =====
	--
	-- `seasonal = { hours = N }` opens the instant a season turns over and runs for N hours.
	--
	-- WHY IT IS NOT A `fixed` PAIR OF DATES, WHICH IS WHAT A FESTIVAL LOOKS LIKE IN EVERY OTHER
	-- GAME. 25.1 measured what that costs: `PrismFest` was two authored dates, it happened once,
	-- and on the day it closed the ONE exclusive skin outside the Colosseum rotation became
	-- permanently unobtainable with nothing anywhere saying so. `docs/CONTENT-CALENDAR.md` §0
	-- states the rule that came out of it -- *a beat is generated, or it rots* -- and names
	-- `SeasonEpoch + n x 30 days` as a generated shape in the same table as `recurring`. This is
	-- that shape, wired into the event engine, so the monthly festival needs no live-ops job and
	-- cannot run out.
	--
	-- WHY IT REUSES THE SEASON CLOCK RATHER THAN CARRYING A PERIOD OF ITS OWN. A festival that
	-- opened every 30 days from an epoch of its own would drift out of step with the season within
	-- a year of a single edit to either, and the two would then be two unrelated monthly beats
	-- competing for the same attention. Asking `GetCurrentSeason` means the festival IS the season
	-- turnover -- the new track opens and the reason to come and look at it opens with it, in the
	-- same second, on every server, for ever.
	--
	-- `GetCurrentSeason` lives in the `Season` part, which loads AFTER this one. That is safe
	-- precisely because this is a runtime read and not a load-time one: by the time any window is
	-- asked for, every part of `GameConfig` is in the table. A top-level reference here would be
	-- the silent nil this file's loader warns about -- see the note over `SpliceSurge`'s 150.
	local s = event.seasonal
	if s then
		local season = GameConfig.GetCurrentSeason(now)
		local startTs = season.startTs
		local endTs = startTs + (s.hours or 72) * 3600
		-- `now >= startTs` is not redundant even though a season's start is always in the past:
		-- `GetCurrentSeason` CLAMPS its index at 1, so a clock set before the epoch is handed
		-- season 1 with a start that has not happened yet. Without the lower bound that reads as
		-- a live festival, and the same clamp that protects the season id from a broken clock
		-- would hand out an exclusive skin to it.
		local active = (now >= startTs and now < endTs)
		return {
			startTs = startTs,
			endTs = endTs,
			active = active,
			nextStart = (not active) and ((now < startTs) and startTs or season.endTs) or nil,
			seasonIndex = season.index,
		}
	end

	local r = event.recurring
	if not r then return nil end

	local t = os.date("!*t", now)
	local midnight = now - (t.hour * 3600 + t.min * 60 + t.sec)   -- 00:00 UTC today
	local startTs = midnight - ((t.wday - r.wday) % 7) * EVENT_DAY + (r.hour or 0) * 3600
	-- Today IS the day, but the hour has not come round yet: the occurrence that matters is last
	-- week's, which may or may not still be running. Without this line an event whose hour is later
	-- today reads as having started this morning.
	if startTs > now then startTs -= EVENT_WEEK end

	local endTs = startTs + (r.hours or 24) * 3600
	local active = (now < endTs)
	return {
		startTs = startTs,
		endTs = endTs,
		active = active,
		nextStart = (not active) and (startTs + EVENT_WEEK) or nil,
	}
end

-- Every event live at `now`, each paired with its own window so a caller that also wants the
-- countdown does not compute it a second time.
--
-- SORTED BY `priority`, HIGHEST FIRST, AND THAT IS A REAL DECISION RATHER THAN TIDINESS (12.13).
-- Three separate places draw `active[1]` and nothing else -- the sign in Forest, the HUD boost card
-- and GetEventHeadline -- so as soon as two windows can overlap, "which event IS the weekend" is
-- being answered by the order somebody happened to type the table in. It is answered here instead,
-- once, for all three.
--
-- The tie-break is the authored index, not the sort's own idea of equal elements: `table.sort` is
-- NOT stable in Lua, so two events at the same priority would otherwise swap places between calls
-- and the board would flip name every second. Ordinals make equal priorities keep table order.
function GameConfig.GetActiveEvents(now)
	now = now or GameConfig.EventNow()
	local out = {}
	for index, event in ipairs(GameConfig.Events) do
		local window = GameConfig.GetEventWindow(event, now)
		if window and window.active then
			table.insert(out, { event = event, window = window, order = index })
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = a.event.priority or 0, b.event.priority or 0
		if pa ~= pb then return pa > pb end
		return a.order < b.order
	end)
	return out
end

-- ===== WHICH SKIN THIS OCCURRENCE HANDS OVER =====
--
-- THE ONE PLACE THAT ANSWERS IT, for both shapes an event reward can take: a fixed `reward` (the
-- launch festival, which happens once and so has nothing to rotate) and a `rotation` list, which
-- picks one entry per week.
--
-- THE INDEX COMES OFF `window.startTs`, NEVER OFF `now`, and that is the whole correctness of it.
-- The Unix week boundary is a Thursday (the epoch was one), so a Saturday-to-Monday window does not
-- cross one today -- but nothing in this file guarantees the window stays where it is authored, and
-- an index taken from `now` silently changes the answer for a window that ever does cross a
-- boundary. A player online at that instant would watch the reward swap under them and be handed
-- two skins for one weekend; anyone who joined ten minutes later would get a different one from the
-- player standing beside them. Off `startTs` the whole occurrence agrees with itself by
-- construction, and the same window always resolves to the same skin however late it is asked.
function GameConfig.GetEventRewardKey(event, window)
	if not event then return nil end
	if event.reward and event.reward.characterKey then
		return event.reward.characterKey, nil
	end
	local rotation = event.rotation
	if not (rotation and #rotation > 0 and window and window.startTs) then return nil end
	-- A SEASONAL ROTATION IS INDEXED BY THE SEASON, NOT BY THE WEEK, and that is what keeps the
	-- herald's name and the season's name the same word (25.2). Thirty days is 4.28 weeks, so
	-- `startTs / EVENT_WEEK` would step the list by four entries one month and five the next --
	-- the skin would still rotate and would still be limited, but which one you get would have no
	-- relation to the season it belongs to, which is the whole of its identity. The index is
	-- DERIVED from `window.startTs` rather than read off `window.seasonIndex` so that a probe may
	-- ask about an occurrence it has only a start time for -- see GetRotationInfo's forward walk.
	local index
	if event.seasonal then
		index = 1 + (GameConfig.GetCurrentSeason(window.startTs).index - 1) % #rotation
	else
		index = 1 + math.floor(window.startTs / EVENT_WEEK) % #rotation
	end
	return rotation[index], index
end

-- How far apart two consecutive occurrences of `event` are, for the forward walk below. It is a
-- function and not the `EVENT_WEEK` constant the walk used to add because 25.2's festival recurs on
-- the SEASON's period: a week-sized step over a thirty-day cycle would probe six times inside the
-- same occurrence, find the same skin every time, and report that a herald five months away is
-- never coming back.
local function occurrenceStep(event)
	if event.seasonal then
		return (GameConfig.SeasonLengthDays or 30) * EVENT_DAY
	end
	return EVENT_WEEK
end

-- Where a rotation skin sits relative to right now: which slot it is, whether it is the one
-- currently being handed out, and when its own turn next comes round. For the Journal, so an
-- unowned champion can say "three weeks away" instead of the generic "turn up while it is running",
-- which for a rotation is true of only one of the four at a time.
function GameConfig.GetRotationInfo(characterKey, now)
	if not characterKey then return nil end
	now = now or GameConfig.EventNow()
	for _, event in ipairs(GameConfig.Events) do
		local rotation = event.rotation
		if rotation then
			local slot
			for i, key in ipairs(rotation) do
				if key == characterKey then slot = i break end
			end
			if slot then
				local window = GameConfig.GetEventWindow(event, now)
				local currentKey = window and GameConfig.GetEventRewardKey(event, window) or nil
				-- Walk forward one occurrence at a time rather than solving for the week: the window
				-- arithmetic already knows where occurrences fall, and #rotation steps is at most four.
				local nextStart
				if currentKey ~= characterKey or not (window and window.active) then
					local probeStart = window and (window.active and window.startTs or window.nextStart)
					local step = occurrenceStep(event)
					for _ = 1, #rotation + 1 do
						if not probeStart then break end
						if probeStart > now and GameConfig.GetEventRewardKey(event, { startTs = probeStart }) == characterKey then
							nextStart = probeStart
							break
						end
						probeStart += step
					end
				end
				return {
					event = event,
					slot = slot,
					count = #rotation,
					live = (window and window.active and currentKey == characterKey) or false,
					nextStart = nextStart,
				}
			end
		end
	end
	return nil
end

-- ============================================================================
-- THE EVENT LADDER (26.1)
-- ============================================================================
-- WHY THIS EXISTS AT ALL. Until this row an event skin cost nothing but presence:
-- EventService granted it to anyone who happened to be online inside the window, and the blurb
-- said so out loud. Nobody at the top of this genre does that -- Pet Simulator 99 runs event
-- quests that must be completed IN ORDER and pays the limited Huge at the end of them, MM2 pays an
-- event currency from daily quests and spends it on a reward track, Forsaken gates its milestone
-- skins on 25 levels with the character. The skin was already permanent and already survived a
-- rebirth (see GameConfig.EventCharacters); what it never had was a price.
--
-- FOUR RUNGS, AND ONLY THE LAST ONE PAYS THE CHARACTER. The first three pay Diamonds or DNA so the
-- board is worth opening on the way up, and the fourth is the whole reason the board exists.
--
-- IT REUSES THE FOUR COUNTERS SeasonPassService.Track ALREADY FEEDS -- `creatures`, `bosses`,
-- `eggs`, `fuse`. That is not thrift, it is the only design that cannot drift: a kill either counts
-- for both boards or for neither, and there is no second set of call sites to forget when a fifth
-- way to kill something is added. GameConfig.AdvanceEventQuests below is called from inside Track
-- itself, so the event ladder gained exactly zero new call sites in the gameplay services.
--
-- =========================================================================================
-- PROGRESS RUNS IN PARALLEL. THE CLAIM IS WHAT IS ORDERED.
-- =========================================================================================
-- "In order" could mean either "a rung's counter is dead until the one before it is claimed" or
-- "a rung's BUTTON is dead until the one before it is claimed". The first is wrong here and would
-- be invisible: the counters are shared with the season board, so a boss killed before rung 2 was
-- claimed would advance the weekly quest and silently not advance the event -- a player watching
-- two boards move at different rates has no way to find out why. Order is enforced at the button,
-- which is the one place a player can see it.
--
-- Two rungs on the same counter are therefore cumulative, not additive: Colosseum rung 2 lands at
-- 15 bosses and rung 4 at 50 bosses TOTAL, not at 65. Same arithmetic the daily and weekly season
-- quests have always had when they share a counter.
--
-- =========================================================================================
-- HOW THE TARGETS WERE SIZED, AND AGAINST WHAT
-- =========================================================================================
-- The only calibrated board in this game is GameConfig.QuestPool's weekly row -- 500 creatures,
-- 20 bosses, 60 eggs across seven days -- so every target here is quoted as a multiple of it. The
-- rule is: A LADDER ASKS ROUGHLY TWO TO THREE TIMES A WEEK'S QUEST, INSIDE A WINDOW A THIRD AS
-- LONG. That is a real weekend of play rather than a gesture, and it is one constant per rung to
-- move if the owner decides it lands wrong.
--
-- The measured rates behind that (11.11's probe, and the boss table two files over): roaming a
-- dense valley pays 85 kills a minute, and a zone boss respawns in 40-72 s -- so 500 creatures is
-- about six minutes of ideal farming and 20 bosses about twenty. The existing weekly board is far
-- easier than it reads, which is exactly why the event ladder is a MULTIPLE of it and not a copy.
--
-- THE THEME OF EACH LADDER IS ITS EVENT'S OWN. Colosseum Clash doubles giant loot, so its ladder
-- ends on bosses; Prism Festival is a luck event, so its ladder ends on eggs. A ladder that asked
-- for the same four things every time would make the two events one event.
--
-- Weekend2x deliberately has NO ladder. It hands over no skin, so there is nothing to put at the
-- end of one, and an event with no entry here simply has no board -- see GetEventBoard.
GameConfig.EventQuests = {
	-- 48-hour window. Ends on bosses because bossMult is what this event turns on.
	ColosseumClash = {
		{ key = "cc_1", counter = "creatures", target = 400, emoji = "\u{2694}\u{FE0F}", name = "Defeat 400 creatures", diamonds = 4 },
		{ key = "cc_2", counter = "bosses",    target = 15,  emoji = "\u{1F451}",        name = "Defeat 15 bosses",     dna = 12000 },
		{ key = "cc_3", counter = "eggs",      target = 120, emoji = "\u{1F95A}",        name = "Hatch 120 eggs",       diamonds = 8 },
		{ key = "cc_4", counter = "bosses",    target = 50,  emoji = "\u{1F3C6}",        name = "Defeat 50 bosses",     diamonds = 15, character = true },
	},
	-- 72-hour window, and the one event whose skin does not rotate. Ends on eggs because luckAdd is
	-- what this event turns on, and luck is only ever felt at a hatch.
	PrismFest = {
		{ key = "pf_1", counter = "eggs",      target = 60,  emoji = "\u{1F95A}",        name = "Hatch 60 eggs",        diamonds = 4 },
		{ key = "pf_2", counter = "creatures", target = 750, emoji = "\u{2694}\u{FE0F}", name = "Defeat 750 creatures", dna = 15000 },
		{ key = "pf_3", counter = "fuse",      target = 12,  emoji = "\u{1F9EC}",        name = "Fuse 12 pets",         diamonds = 8 },
		{ key = "pf_4", counter = "eggs",      target = 180, emoji = "\u{1F308}",        name = "Hatch 180 eggs",       diamonds = 15, character = true },
	},
	-- 72-hour window, same length as PrismFest's. ENDS ON CREATURES because damageMult is what this
	-- event turns on, and a damage multiplier is only ever felt as a creature dying in fewer swings
	-- -- the same rule that put bosses at the end of the Colosseum's ladder and eggs at the end of
	-- the Prism's. It is also the one counter neither of the other two ladders finishes on, so the
	-- three events ask for three different weekends of play rather than three versions of one.
	--
	-- Sized by the rule above: 1,500 creatures is 3x the calibrated weekly quest (500) inside a
	-- window a third as long, and the rungs are CUMULATIVE, so sf_1's 300 is on the way to it and
	-- not on top of it. 20 bosses is exactly the weekly row -- a side rung here, where the
	-- Colosseum asks 50 because bosses are its whole subject.
	SeasonFest = {
		{ key = "sf_1", counter = "creatures", target = 300,  emoji = "\u{2694}\u{FE0F}", name = "Defeat 300 creatures",  diamonds = 4 },
		{ key = "sf_2", counter = "eggs",      target = 100,  emoji = "\u{1F95A}",        name = "Hatch 100 eggs",        dna = 15000 },
		{ key = "sf_3", counter = "bosses",    target = 20,   emoji = "\u{1F451}",        name = "Defeat 20 bosses",      diamonds = 8 },
		{ key = "sf_4", counter = "creatures", target = 1500, emoji = "\u{1F386}",        name = "Defeat 1500 creatures", diamonds = 15, character = true },
	},
}

-- Shared, never handed out to be written into. Returned by both readers below instead of a fresh
-- `{}` because both run on the creature-kill path, and an empty table allocated per kill is the
-- kind of cost that only shows up as a frame spike on a full server.
local EMPTY_LADDER = table.freeze({})

function GameConfig.GetEventQuests(eventKey)
	return GameConfig.EventQuests[eventKey] or EMPTY_LADDER
end

-- The rung and WHICH RUNG IT IS. The index is not decoration: it is what the claim handler tests
-- to enforce the order, and returning it here is what stops that handler walking the list a second
-- time to find out where it already is.
function GameConfig.GetEventQuestDef(eventKey, questKey)
	for index, quest in ipairs(GameConfig.GetEventQuests(eventKey)) do
		if quest.key == questKey then return quest, index end
	end
	return nil, nil
end

-- This save's board for one occurrence of one event, created on first touch and THROWN AWAY the
-- moment the occurrence changes.
--
-- BUCKETED BY `window.startTs`, WHICH IS THE WHOLE OF 26.1'S SAVE DESIGN. It is the same trick
-- GetQuestPeriod plays with `periodId`: the reset is a comparison against the clock rather than a
-- scheduled wipe, so it is correct after a restart, correct for a player who was offline when the
-- window turned over, and impossible to miss. It matters most for ColosseumClash, whose champion
-- rotates every week -- last weekend's four claims must not hand over this weekend's skin, and
-- storing the start timestamp is what makes each occurrence its own board rather than a running
-- total across every weekend the save has ever seen.
--
-- IT MUTATES `data`, and callers should know it: reading a board is what creates it. Same contract
-- as SeasonPassService.GetQuestPeriod, and harmless on the client's replicated copy of the save --
-- that copy is overwritten by the next DataUpdate anyway.
--
-- Returns nil for an event with no ladder authored, which is the state Weekend2x is permanently in.
function GameConfig.GetEventBoard(data, eventKey, window)
	if not (data and window and window.startTs) then return nil end
	if #GameConfig.GetEventQuests(eventKey) == 0 then return nil end

	if type(data.EventQuests) ~= "table" then data.EventQuests = {} end
	local held = data.EventQuests[eventKey]
	if type(held) ~= "table" or held.window ~= window.startTs then
		held = { window = window.startTs, progress = {}, claimed = {} }
		data.EventQuests[eventKey] = held
	end
	-- the stamp above says nothing about what is inside the table it stamps: a save written by a
	-- build that shaped this differently can hold the right window and the wrong innards, and the
	-- first write would index nil
	if type(held.progress) ~= "table" then held.progress = {} end
	if type(held.claimed) ~= "table" then held.claimed = {} end
	return held
end

-- Advance every LIVE event's ladder by `amount` of `counter`, and hand back whatever finished on
-- this call. Pure over the save and the clock: it grants nothing, replicates nothing and knows no
-- player -- SeasonPassService.Track, its only caller, does all three.
--
-- ONLY LIVE EVENTS ADVANCE, and that is the same rule the rest of this file runs on. An event is
-- arithmetic on a timestamp; a kill on a Wednesday belongs to no weekend, and letting it bank
-- progress toward Saturday's board would make the ladder a stock rather than a window.
function GameConfig.AdvanceEventQuests(data, counter, amount, now)
	if not data then return EMPTY_LADDER end
	now = now or GameConfig.EventNow()
	amount = amount or 1

	local completed
	for _, live in ipairs(GameConfig.GetActiveEvents(now)) do
		local board = GameConfig.GetEventBoard(data, live.event.key, live.window)
		if board then
			for _, quest in ipairs(GameConfig.GetEventQuests(live.event.key)) do
				if quest.counter == counter then
					local before = board.progress[quest.key] or 0
					if before < quest.target then
						local after = math.min(before + amount, quest.target)
						board.progress[quest.key] = after
						if after >= quest.target then
							completed = completed or {}
							table.insert(completed, { event = live.event, window = live.window, quest = quest })
						end
					end
				end
			end
		end
	end
	-- allocated only when something actually finished: this runs on every creature kill in the game
	return completed or EMPTY_LADDER
end

-- Everything that starts at the SOONEST moment anything starts, for the board to count down to when
-- nothing is on. Usually one event; two whenever two windows share an opening instant, which since
-- 12.13 is every week -- the Colosseum and the weekend both open at 00:00 Saturday.
--
-- SORTED BY PRIORITY LIKE GetActiveEvents, AND THAT IS A BUG FIX, NOT SYMMETRY FOR ITS OWN SAKE.
-- The old form kept the first event it found at the soonest start, i.e. authored order -- so on the
-- five days a week nothing is running, the sign counted down to "🔥 Weekend Rush" while the sign on
-- the weekend itself headlined "⚔️ Colosseum Clash". Same instant, same duration, two different
-- names, and the one a player reads while deciding whether to come back is the off-weekend one.
-- Measured on the live board before this was fixed.
function GameConfig.GetUpcomingEvents(now)
	now = now or GameConfig.EventNow()
	local soonest
	local out = {}
	for index, event in ipairs(GameConfig.Events) do
		local window = GameConfig.GetEventWindow(event, now)
		if window and window.nextStart then
			if not soonest or window.nextStart < soonest then
				soonest = window.nextStart
				out = {}
			end
			if window.nextStart == soonest then
				table.insert(out, { event = event, window = window, order = index })
			end
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = a.event.priority or 0, b.event.priority or 0
		if pa ~= pb then return pa > pb end
		return a.order < b.order
	end)
	return out
end

-- The one that headlines. Kept as its own function because every existing caller wants exactly this.
function GameConfig.GetNextEvent(now)
	return GameConfig.GetUpcomingEvents(now)[1]
end

-- ============================================================================
-- THE CALENDAR'S ONE GUARD (25.1)
-- ============================================================================
-- WHAT THE CALENDAR MEASUREMENT FOUND, AND WHY IT IS A FUNCTION RATHER THAN A NOTE. Every recurring
-- event above is generated from the clock, so it cannot run out -- that is the same argument
-- `GameConfig.SeasonEpoch` makes for the season, and it is why neither has ever needed maintaining.
-- A `fixed` event is the opposite: it is two authored dates, it happens once, and when it is over
-- it is over silently. On 2026-09-11 the calendar sweep found `PrismFest` had closed four days
-- earlier with `nextStart = nil`, which made `event_prism` -- the ONE exclusive skin outside the
-- Colosseum rotation -- permanently unobtainable, with the Journal still drawing it as a locked row
-- and 26.1's four-rung ladder still built underneath it. Nothing anywhere said so.
--
-- That is precisely the difference the 25.1 row names: a schedule that produces beats is a
-- calendar, a list of dates that quietly runs out is a backlog. The recurring half needs no guard.
-- The fixed half gets this one, and `EventService.Init` is what reads it, so the warning lands in
-- the server log of every boot after the window closes rather than in a document nobody re-opens.
--
-- IT DOES NOT FIX THE DATE, ON PURPOSE. Which weekend the launch festival lands on is the owner's
-- decision (the OWNER note over `PrismFest` says so) and inventing one here would be the same class
-- of mistake as inventing a product id. The guard's whole job is to make the expiry loud.
function GameConfig.GetDeadEvents(now)
	now = now or GameConfig.EventNow()
	local dead = {}
	for _, event in ipairs(GameConfig.Events) do
		-- A recurring event is never dead: `GetEventWindow` always answers with either the
		-- occurrence running now or the next one, for any `now` at all. A SEASONAL one (25.2) is
		-- never dead for exactly the same reason and is skipped by the same test -- `SeasonEpoch`
		-- keeps producing turnovers for ever, so the festival always has a next occurrence. It is
		-- listed here rather than left to fall through the `nextStart` check below because this is
		-- the one place that states which shapes are generated, and a reader who has to work that
		-- out from the window arithmetic will get it wrong the day a fourth shape is added.
		if not (event.recurring or event.seasonal) then
			local window = GameConfig.GetEventWindow(event, now)
			if window and not window.active and not window.nextStart then
				table.insert(dead, { event = event, endedTs = window.endTs })
			end
		end
	end
	return dead
end

-- ===== THE SECOND GUARD: TWO PARALLEL LISTS THAT MUST STAY THE SAME LENGTH (25.2) =====
--
-- The season festival's rotation is one herald per entry in `GameConfig.SeasonThemes`, and both are
-- indexed by the same expression off the season number -- `1 + (index - 1) % #list`. They agree for
-- ever if and only if the two lists are the same length. Add a seventh theme and say nothing here
-- and the game does not break: it keeps running, keeps handing out heralds, and quietly hands the
-- Cinder Herald to Frostbloom -- a skin named for a volcano paid out by a season named for frost,
-- which is the kind of fault that is only ever noticed by a player.
--
-- 32.24's lesson is the one being applied: a comment saying "keep these in step" is a census, not a
-- guard. This is the guard. It is a `warn` through `EventService.Init` and never an `error`, for
-- 25.1's reason -- 21.11's boot watchdog would take out every service after it, and a mismatched
-- rotation is a live-ops omission rather than a broken server.
function GameConfig.GetSeasonFestivalMismatch()
	local themes = GameConfig.SeasonThemes
	if not themes then return nil end
	for _, event in ipairs(GameConfig.Events) do
		if event.seasonal and event.rotation then
			if #event.rotation ~= #themes then
				return ("%s has %d rotation entries against SeasonThemes' %d -- a herald will be paid out by the wrong season")
					:format(event.key, #event.rotation, #themes)
			end
			-- A key that resolves to nothing is the same fault one step further on: the lengths
			-- agree, the index lands, and `GetEventCharacter` hands back nil for a rung that is
			-- supposed to pay a character.
			for i, key in ipairs(event.rotation) do
				if not GameConfig.GetEventCharacter(key) then
					return ("%s rotation slot %d names '%s', which is not in GameConfig.EventCharacters")
						:format(event.key, i, tostring(key))
				end
			end
		end
	end
	return nil
end

-- The product of `field` across every live event, or 1 so a caller can multiply unconditionally.
--
-- IT TAKES NO `data`, AND THAT IS THE DIFFERENCE BETWEEN AN EVENT AND A PASS IN ONE LINE: an event
-- is the same for everybody on the server, so there is nothing about a player it could depend on.
function GameConfig.GetEventMult(field, now)
	local mult = 1
	for _, live in ipairs(GameConfig.GetActiveEvents(now)) do
		local value = live.event.effects and live.event.effects[field]
		if type(value) == "number" then mult *= value end
	end
	return mult
end

-- Additive points, for luck -- the one stat in this game every source adds to rather than scales.
function GameConfig.GetEventAdd(field, now)
	local add = 0
	for _, live in ipairs(GameConfig.GetActiveEvents(now)) do
		local value = live.event.effects and live.event.effects[field]
		if type(value) == "number" then add += value end
	end
	return add
end

-- "2d 4h" / "5h 12m" / "48m 09s" / "30s". Shared by the countdown board and the HUD chip so the two
-- can never disagree about how long is left.
function GameConfig.FormatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local d = math.floor(seconds / EVENT_DAY)
	local h = math.floor((seconds % EVENT_DAY) / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	if m > 0 then return ("%dm %02ds"):format(m, s) end
	return ("%ds"):format(s)
end

-- One line for the HUD and the board: what is running and how long is left, or what is next.
-- Returns nil when there is neither, which is a state the board draws rather than hides.
function GameConfig.GetEventHeadline(now)
	now = now or GameConfig.EventNow()
	local active = GameConfig.GetActiveEvents(now)
	if #active > 0 then
		local live = active[1]
		return {
			event = live.event,
			live = true,
			seconds = live.window.endTs - now,
			text = ("%s  %s"):format(live.event.emoji, GameConfig.FormatDuration(live.window.endTs - now)),
		}
	end
	local upcoming = GameConfig.GetNextEvent(now)
	if upcoming then
		return {
			event = upcoming.event,
			live = false,
			seconds = upcoming.window.nextStart - now,
			text = ("%s  in %s"):format(upcoming.event.emoji,
				GameConfig.FormatDuration(upcoming.window.nextStart - now)),
		}
	end
	return nil
end

-- ============================================================================
-- THE WEEKEND OFFER (25.3) -- ROTATING, AND IT INVENTS NO PRODUCT
-- ============================================================================
-- The calendar (`docs/CONTENT-CALENDAR.md` S3) put this row on the 2026-09-12 weekend, which is the
-- weekend it serves. What it adds is the one thing the storefront had no version of: a reason to
-- open the shop THIS weekend rather than some weekend.
--
-- ===== IT IS A BONUS, NOT A DISCOUNT, AND THAT IS AN ENGINE CONSTRAINT RATHER THAN A TASTE =====
--
-- A developer product's price lives on the Roblox dashboard and cannot be moved from code. The only
-- way to sell "20% off" is to create a SECOND product at the lower price -- i.e. a new id, i.e. the
-- OWNER row this config forbids any agent from inventing. So the weekend offer pays MORE for the
-- same price, which is what the reference games do for the same reason, and it ships without a
-- single dashboard action.
--
-- ===== THE ROTATION IS FIVE AND THE CHAMPION'S IS FOUR, DELIBERATELY =====
--
-- Both are resolved off the SAME weekend window, so equal lengths would lock them in phase for
-- ever: the Ember weekend would be the DNA weekend and nothing else, at every occurrence, and two
-- cycles that always agree are one cycle. Five against four repeats after twenty weeks. This is the
-- season-vs-champion argument in S2 of the calendar, one layer down.
--
-- ===== EVERY ENTRY IS AN EXISTING 199 R$ PRODUCT =====
--
-- The middle rung of five different shelves, so the deal is the same size of decision every week and
-- what rotates is which shelf it is on. `productKey` is checked against `GameConfig.RobuxProducts`
-- at load time below -- this part loads AFTER `RobuxShop`, which is what makes that check possible
-- here and impossible the other way round.
GameConfig.WeekendOfferEventKey = "Weekend2x"

-- HOW LONG AFTER THE WINDOW SHUTS A RECEIPT STILL PAYS THE BONUS.
--
-- `ProcessReceipt` is retried on Roblox's own schedule and carries no purchase timestamp, so a
-- player who pressed BUY at 23:58 on Sunday can have their receipt land on another server after the
-- window has closed. Evaluating the offer at receipt time with no grace silently short-pays exactly
-- the buyer who bought at the loudest moment of the weekend.
--
-- The grace errs toward PAYING the bonus and never toward withholding it: for fifteen minutes after
-- close a fresh purchase is also paid the bonus, which costs a rounding error of Robux-funded
-- currency and cannot produce a complaint. The reverse mistake produces a refund.
GameConfig.WeekendOfferReceiptGrace = 15 * 60

GameConfig.WeekendOffers = {
	{ productKey = "DNA_3",      bonusPct = 50 },
	{ productKey = "Diamonds_3", bonusPct = 40 },
	{ productKey = "Spins_5",    bonusPct = 40 },
	{ productKey = "Shards_2",   bonusPct = 40 },
	{ productKey = "Potions_10", bonusPct = 50 },
}

-- The COUNTED grant fields, i.e. the ones a percentage means anything against. `grantSpin`,
-- `grantSeasonPremium` and the cosmetic rows are booleans and flags -- 50% of a flag is the flag, so
-- an offer authored against one of those would show a ribbon and pay nothing. The load check at the
-- bottom of this section refuses such a row rather than letting it reach the store.
local OFFER_BONUS_FIELDS = {
	"grantDNA", "grantDiamonds", "grantShards", "grantSpins",
	"grantPotions", "grantTierUps", "grantBossRevives",
}

-- ===== THE RIBBON IS ARITHMETIC, NOT A CLAIM -- THE SAME RULE THE TIER BONUS FOLLOWS =====
--
-- `bonusPct` is what was ASKED for; this returns what is actually PAID and the percentage that
-- actually is. A counted grant has to land on a whole number -- 40% of 5 spins is 2 and 50% of 4
-- potions is 2 -- and a store that rounds down while advertising the authored figure is promising
-- something the receipt refuses. So the extras are computed first, rounded, floored at 1 so an offer
-- can never pay nothing, and the percentage is derived BACK from them. The displayed figure is
-- floored for the same reason: it may under-state the deal, never over-state it.
--
-- The minimum across fields, when a product grants more than one thing: the headline has to be true
-- of every line under it.
function GameConfig.GetWeekendOfferBonus(product, offer)
	local wanted = offer and tonumber(offer.bonusPct) or 0
	if not (product and wanted > 0) then return nil, 0 end
	local extras, pct = nil, nil
	for _, field in ipairs(OFFER_BONUS_FIELDS) do
		local base = tonumber(product[field])
		if base and base > 0 then
			local extra = math.max(1, math.floor(base * wanted / 100 + 0.5))
			extras = extras or {}
			extras[field] = extra
			local real = extra / base * 100
			if not pct or real < pct then pct = real end
		end
	end
	if not extras then return nil, 0 end
	return extras, math.floor(pct + 1e-9)
end

-- Which entry a window carries. OFF `startTs` AND NEVER OFF `now`, for the reason written out in
-- full over `GetEventRewardKey`: an index taken from the clock changes answer underneath a player
-- who is looking at the card, and two players in the same server would be offered different deals.
local function offerForWindowStart(startTs)
	local list = GameConfig.WeekendOffers
	if not (startTs and #list > 0) then return nil end
	local index = 1 + math.floor(startTs / EVENT_WEEK) % #list
	local offer = list[index]
	local product = offer and GameConfig.GetRobuxProduct(offer.productKey)
	if not product then return nil end
	local extras, pct = GameConfig.GetWeekendOfferBonus(product, offer)
	if not extras then return nil end
	return { offer = offer, product = product, index = index, extras = extras, bonusPct = pct }
end

--- The deal running right now, or nil. `live` is always true on what this returns -- a caller that
--- wants the teaser asks `GetNextWeekendOffer` instead, because the two differ in which window's
--- `startTs` resolves the rotation, and conflating them offers LAST weekend's deal as next week's.
function GameConfig.GetWeekendOffer(now)
	now = now or GameConfig.EventNow()
	local event = GameConfig.GetEvent(GameConfig.WeekendOfferEventKey)
	if not event then return nil end
	local window = GameConfig.GetEventWindow(event, now)
	if not (window and window.active) then return nil end
	local resolved = offerForWindowStart(window.startTs)
	if not resolved then return nil end
	resolved.window = window
	resolved.live = true
	return resolved
end

--- The deal the NEXT window will carry, with the window it opens in. For the store's teaser during
--- the 96 hours of the week that carry no event at all (S1 of the calendar) -- an absent card is a
--- shop with nothing to come back for, which is the fault the calendar was written to name.
function GameConfig.GetNextWeekendOffer(now)
	now = now or GameConfig.EventNow()
	local event = GameConfig.GetEvent(GameConfig.WeekendOfferEventKey)
	if not event then return nil end
	local window = GameConfig.GetEventWindow(event, now)
	if not window or window.active or not window.nextStart then return nil end
	local resolved = offerForWindowStart(window.nextStart)
	if not resolved then return nil end
	resolved.window = window
	resolved.live = false
	return resolved
end

--- Everything an offer adds to ONE receipt, at `now`, or nil -- the server's single question.
---
--- The grace is applied here and nowhere else, so `RobuxShopService` does not have to know that
--- receipts are retried and the rule lives beside the constant that states it.
---
--- ===== THE GRACE READS THE WINDOW THAT CLOSED, NOT THE CLOCK SHIFTED BACKWARDS =====
---
--- The first cut of this asked `GetWeekendOffer(now - grace)` and a probe caught what that costs:
--- resolving at a shifted instant resolves the rotation at that instant too, so any shift that
--- crosses a Unix week boundary answers with a DIFFERENT entry -- the key then fails to match and
--- the grace silently pays nothing, which is the exact failure the grace exists to prevent.
---
--- A Saturday window cannot cross that boundary today (the epoch fell on a Thursday, which is why
--- `GetEventRewardKey` says the same thing about its own index), so the first cut was correct for
--- the authored calendar and wrong for any calendar. The window's `startTs` is the fact this needs
--- and `GetEventWindow` already returns it for a closed occurrence; asking it twice at two
--- different clocks was the mistake.
function GameConfig.GetWeekendOfferForReceipt(productKey, now)
	now = now or GameConfig.EventNow()
	local resolved = GameConfig.GetWeekendOffer(now)
	if not resolved then
		local event = GameConfig.GetEvent(GameConfig.WeekendOfferEventKey)
		local window = event and GameConfig.GetEventWindow(event, now)
		local grace = GameConfig.WeekendOfferReceiptGrace or 0
		-- `>= endTs` and not `> endTs`: the instant of closure belongs to the grace, not to neither.
		if window and window.endTs and now >= window.endTs and (now - window.endTs) <= grace then
			resolved = offerForWindowStart(window.startTs)
			if resolved then
				resolved.window = window
				-- NOT `live`. Nothing draws this -- the store asks `GetWeekendOffer` -- but a caller
				-- that ever did must not be told a closed window is open.
				resolved.live = false
			end
		end
	end
	if resolved and resolved.product.key == productKey then return resolved end
	return nil
end

-- A LOAD-TIME CHECK, because every fault this table can carry is silent at runtime: a mistyped key
-- draws no card at all, and a flag-only product draws a ribbon over a bonus of nothing. Both look
-- exactly like "the weekend is not on". `warn` and never `error` -- 21.11's boot watchdog takes out
-- every service after a service that throws, and a wrong shop ribbon must not cost the game.
for index, offer in ipairs(GameConfig.WeekendOffers) do
	local product = GameConfig.GetRobuxProduct(offer.productKey)
	if not product then
		warn(("[GameConfig] WeekendOffers[%d] names %q, which is not a product"):format(
			index, tostring(offer.productKey)))
	elseif product.delisted then
		warn(("[GameConfig] WeekendOffers[%d] offers %q, which is delisted"):format(
			index, tostring(offer.productKey)))
	elseif not GameConfig.GetWeekendOfferBonus(product, offer) then
		warn(("[GameConfig] WeekendOffers[%d] offers %q, which has no counted grant to bonus"):format(
			index, tostring(offer.productKey)))
	end
end

end
