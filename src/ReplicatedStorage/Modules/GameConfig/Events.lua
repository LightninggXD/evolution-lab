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
		blurb = "Double giant loot, and this week's champion skin for everyone who shows up",
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
		key = "PrismFest",
		name = "Prism Festival",
		emoji = "\u{1F308}",
		blurb = "+50% luck, and the Prism Herald skin for everyone who shows up",
		color = Color3.fromRGB(158, 120, 255),
		fixed = { from = { 2026, 9, 4, 12, 0 }, to = { 2026, 9, 7, 12, 0 } },
		effects = { luckAdd = 50 },
		-- Granted while the window is open and NEVER taken back -- see GameConfig.EventCharacters.
		reward = { characterKey = "event_prism" },
	},
}

-- What the HUD chip calls each multiplicative effect field. It lives here rather than in MainUI for
-- two reasons: MainUI is at Luau's 200-local ceiling and a new top-level table there costs the
-- whole HUD, and a new effect field is authored three lines up in GameConfig.Events -- so the
-- reader that would otherwise silently omit it is the one that should be edited in the same file.
-- `luckAdd` is deliberately absent: it is additive and is formatted as a percentage, not an "x".
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
	local index = 1 + math.floor(window.startTs / EVENT_WEEK) % #rotation
	return rotation[index], index
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
					for _ = 1, #rotation + 1 do
						if not probeStart then break end
						if probeStart > now and GameConfig.GetEventRewardKey(event, { startTs = probeStart }) == characterKey then
							nextStart = probeStart
							break
						end
						probeStart += EVENT_WEEK
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

end
