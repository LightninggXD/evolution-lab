--[[
	EventService -- limited-time events: the window, the exclusive skin, and the board that counts
	down to the next one (Phase 7.1, and 7.2 rides on it as a single row in GameConfig.Events).

	The game had no notion anywhere in it that right now might be different from yesterday. That is
	the one structural gap between this and the games in the reference list: Grow a Garden and Steal
	a Brainrot are both driven by limited windows, and a player's reason to open the game TODAY is
	almost always that something is on.

	=========================================================================================
	THE RULES ARE IN GameConfig. THIS FILE ONLY WATCHES THE CLOCK AND TELLS PEOPLE.
	=========================================================================================
	Whether an event is live, what it multiplies and when the next one starts are all pure functions
	of a timestamp, and they live in GameConfig beside the table that authors them -- so the income
	hook, the XP hook, the HUD and this service all get the same answer without asking each other.
	What is left here is the three things a pure function cannot do: publish the state, hand over the
	skin, and put a sign in the world.

	=========================================================================================
	TRANSITIONS ARE POLLED, NOT SCHEDULED
	=========================================================================================
	The obvious build is `task.delay(secondsUntilEnd, closeIt)`. A timer is wrong here in four
	separate ways: it is lost when the server restarts, it fires once so a recurring window needs it
	rescheduled correctly forever, it drifts over the many hours a 48-hour window lasts, and a server
	that started INSIDE a window never had one set at all.

	A five-second poll comparing "what is live now" against "what was live last time" is correct
	after a restart at any point in any window, needs no bookkeeping and costs a table walk. It is
	the same reasoning as SeasonPassService's lazy resets: derive the state from the clock, never
	schedule the moment it changes.

	=========================================================================================
	THE CLIENT IS TOLD WHAT TIME IT IS
	=========================================================================================
	The state is published as JSON in a `StringValue`, which replicates by itself -- no remote, and a
	late joiner gets the current answer for free (5.7's GlobalStats set the precedent).

	The payload carries `now`, the SERVER's clock, and the client feeds it to
	GameConfig.SetEventClock. Without it a player whose machine is set a day fast is shown a weekend
	that is not running and a countdown to the wrong minute, and then watches their DNA arrive at the
	normal rate while the HUD insists it is doubled. The client never decides what is live.

	=========================================================================================
	THE SKIN IS EARNED AT THE TOP OF A LADDER (26.1), AND IS THEN NEVER TAKEN BACK
	=========================================================================================
	It used to be granted to anyone who happened to be online while the window was open -- the fault
	Phase 26 was opened on. It is now the last rung of GameConfig.EventQuests: four ordered tasks on
	the counters SeasonPassService.Track already feeds, claimed through HandleClaimEventQuest.

	What did not change is what happens after. It is written to `data.EventCharacters` -- a permanent
	record no reset touches -- and copied into `data.Characters`, which a rebirth wipes.
	GameConfig.SyncEventCharacters is what puts it back afterwards; without that a player who
	rebirthed in October would silently lose a September skin, and there would be nothing left
	anywhere to give it back from.

	That repair still runs on join and on every poll rather than once, because a rebirth can happen
	at any moment and it is idempotent, so both paths are free. See EventService.SyncCharacters --
	which is what this file's old GrantRewards became once it stopped granting anything.
--]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)

local PlayerDataService = require(script.Parent.PlayerDataService)
local AnnounceService = require(script.Parent.AnnounceService)
-- For the ladder's payout and its toast line only (26.1) -- `GrantReward` / `RewardText`, which are
-- the season board's own and are exported rather than copied here. A ONE-WAY EDGE: SeasonPassService
-- requires GameConfig and PlayerDataService and nothing else, so it cannot reach back and there is no
-- cycle to break. Progress does not come through this require -- it goes the other way, from
-- SeasonPassService.Track into GameConfig.AdvanceEventQuests, which knows about no service at all.
local SeasonPassService = require(script.Parent.SeasonPassService)

local EventService = {}

-- how often "what is live" is recomputed and compared against the last answer
local POLL_INTERVAL = 5
-- how often the published payload is refreshed even when nothing changed. It exists so a client
-- that has been connected for hours re-syncs its clock, and so a countdown cannot drift.
local PUBLISH_INTERVAL = 30
-- the sign redraws on its own, faster, because a countdown that only moves every thirty seconds
-- reads as broken to somebody standing in front of it
local BOARD_TICK = 1

-- Bumping this rebuilds the sign on the next server start -- same shape as LeaderboardService's
-- BOARD_VERSION, RebirthShrine's SHRINE_VERSION and ZoneBuilder's BUILD_VERSION.
local SIGN_VERSION = 4

-- ===== WHERE IT STANDS, AND WHY IT IS NOT WHERE IT WAS FIRST PUT =====
--
-- The three leaderboards took the west verge (x=-130, z=140..300), so the event board takes the
-- east one and a player reads them off either side of the same walk down from the spawn at
-- (0, 1, 366). That much was chosen; the z was measured, twice.
--
-- 5.3's occupancy scan counts part CENTRES per grid cell, and by that measure x=130, z=300 was a
-- fine empty cell. It was not empty. A boss-gate idol pad sits at (227, 3.5, 322) and its brazier
-- reaches back west: the bowl's box overlaps the top of a 34-stud panel by 4.1 studs, and the posts
-- would have stood on the pad at y=7 rather than on the floor. A centre-count cannot see either --
-- a big part whose centre is in the next cell still occupies this one.
--
-- So the spot was not picked at all in the end, it was SEARCHED FOR. Every 5-stud position in
-- x 85..185, z 110..350 was scored by separating-axis gap against all 612 anchored parts in the
-- area (positive = clear; the largest per-axis gap is the true separation) and rejected unless a
-- downward ray landed on `Floor`. 108 positions clear 8 studs; this one clears 21.0, its nearest
-- neighbour being a GlintPlinth, and it sits directly across the street from the middle
-- leaderboard so the two kinds of board read as a pair.
--
-- ANCHORED PARTS ONLY, and that filter is not a convenience. The first pass measured 2.2 studs and
-- named a `head_geom`: creatures walk, so a clearance measured against one is a fact about where
-- something was standing, not about the place.
local SIGN_X = 150
local SIGN_Z = 215
local SIGN_W, SIGN_H, SIGN_T = 34, 30, 3
local POST_H = 8

-- [eventKey] = true, as of the previous poll. This is the entire transition-detection state.
local wasLive = {}
local valueObject
local board   -- { title, name, clock, blurb, panel }

-- ============================================================================
-- THE CLOCK
-- ============================================================================
function EventService.Now()
	return GameConfig.EventNow()
end

-- THE ONE TEST SEAM, and it is the only way a launch festival can be exercised before the launch.
-- Every window in GameConfig is measured against GameConfig.EventNow(), so moving that forward
-- makes a future window live without editing an authored date -- which is what a test must not do,
-- since a test that rewrites the config proves the config it wrote rather than the one that ships.
--
-- Server-side only and reachable from no remote: a client that could move this clock could hand
-- itself a permanent weekend.
function EventService.SetClock(serverNow)
	local offset = GameConfig.SetEventClock(serverNow)
	EventService.Poll()
	return offset
end

function EventService.ResetClock()
	return EventService.SetClock(os.time())
end

-- ============================================================================
-- PUBLISHING
-- ============================================================================
-- Only what a client needs to draw: names, colours, the two timestamps and the effects. Not the
-- authored tables -- a Color3 does not survive JSON, so it goes over as three numbers and the HUD
-- rebuilds it.
local function describe(event, window, now)
	return {
		key = event.key,
		name = event.name,
		emoji = event.emoji,
		blurb = event.blurb,
		rgb = { math.floor(event.color.R * 255 + 0.5), math.floor(event.color.G * 255 + 0.5),
			math.floor(event.color.B * 255 + 0.5) },
		startTs = window.startTs,
		endTs = window.endTs,
		nextStart = window.nextStart,
		effects = event.effects or {},
		seconds = window.active and (window.endTs - now) or (window.nextStart and window.nextStart - now),
	}
end

function EventService.Publish()
	if not valueObject or not valueObject.Parent then return false end
	local now = EventService.Now()

	local payload = { now = now, active = {}, next = nil }
	for _, live in ipairs(GameConfig.GetActiveEvents(now)) do
		table.insert(payload.active, describe(live.event, live.window, now))
	end
	local upcoming = GameConfig.GetNextEvent(now)
	if upcoming then
		payload.next = describe(upcoming.event, upcoming.window, now)
	end

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not ok then return false end
	valueObject.Value = encoded
	return true
end

-- ============================================================================
-- THE EXCLUSIVE SKIN
-- ============================================================================
-- The ordinary "new character" card, so an event skin arrives looking like every other thing the
-- game has ever handed anyone -- same remote, same branch in MainUI, no new client code.
--
-- `damagePct` is deliberately NOT sent. That branch prints "⚔️ +N% Damage" from it, and an
-- off-ladder skin's rank is 0, so the honest figure would read "+0% Damage" under a reward -- which
-- is both wrong (it is worth the best rank the player owns; see GetEffectiveRank) and dispiriting.
-- Omitted, the card prints the name alone.
local function notifyGrant(player, entry)
	local remotes = RS:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("Notify")
	if not remote then return end
	remote:FireClient(player, {
		kind = "character",
		key = entry.key,       -- the card is tinted with the character's own colour
		name = entry.name,
		emoji = entry.emoji,
		isNew = true,
	})
end

-- =========================================================================================
-- THE SKIN IS NO LONGER HANDED TO WHOEVER IS ONLINE (26.1)
-- =========================================================================================
-- This function used to BE the grant: it walked every live event, resolved the occurrence's skin
-- and wrote it into `data.EventCharacters` for anyone who happened to be logged in. That is the
-- fault Phase 26 was opened on -- the headline exclusive cost nothing but presence, in a market
-- where every game at the top of it charges an ordered ladder for exactly this item.
--
-- The grant moved to HandleClaimEventQuest, at the top of the ladder. What is left here is the
-- half that was never about earning anything: HEALING A SAVE WHOSE REBIRTH CLEARED `Characters`
-- while `EventCharacters` -- the permanent record -- survived it. That still has to run on join and
-- on every poll, because a rebirth can happen at any moment and there is nothing live to re-grant
-- an ended event from.
--
-- It is deliberately NOT named GrantRewards any more. A function that grants nothing and is called
-- from the join hook under that name is the shape of defect this project has been bitten by before
-- (see the note in `GetPetBonus` about a safety net nothing passes): the name is what stops anyone
-- reading it.
--
-- Returns how many characters were put back, so a probe can drive one call and see the repair.
function EventService.SyncCharacters(player)
	local data = PlayerDataService.Get(player)
	if not data then return 0 end

	data.EventCharacters = data.EventCharacters or {}
	local restored = GameConfig.SyncEventCharacters(data)
	if restored > 0 then
		PlayerDataService.PushToClient(player)
	end
	return restored
end

-- ============================================================================
-- THE LADDER (26.1)
-- ============================================================================
-- The rules are in GameConfig, like every other rule about an event: which rungs exist, what they
-- ask for, which occurrence a board belongs to and when a board is thrown away are all pure
-- functions of the save and the clock (GameConfig.EventQuests / GetEventBoard /
-- AdvanceEventQuests). What is here is the three things a pure function cannot do -- check the
-- window, pay the reward, and hand over the skin.
--
-- PROGRESS IS NOT WIRED HERE EITHER. It rides SeasonPassService.Track, which already fires on all
-- four counters from the five gameplay call sites, so this file has no hook into combat, hatching
-- or fusion at all.

local function notify(player, payload)
	local remotes = RS:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("Notify")
	if remote then remote:FireClient(player, payload) end
end

-- THE WINDOW IS THE DOOR, AND THERE IS NO GRACE PERIOD AFTER IT.
--
-- A rung finished at 23:59 on Sunday and not pressed is lost, and that is a decision rather than an
-- oversight. The board is bucketed by `window.startTs` and only live events advance -- so honouring
-- a late claim would mean keeping a closed occurrence's board addressable, which is the same shape
-- as the stale-multiplier bug the header of GameConfig.Events exists to prevent, and it would
-- contradict the one thing this market agrees on: MM2 removes the seasonal quests, the boxes and
-- the reward track together when the window shuts. The urgency IS the board going away.
--
-- If that lands too hard, it is one condition in this function and one in the panel -- not a save
-- change -- because `GetEventWindow` still reports the last occurrence's `startTs` all week.
function EventService.HandleClaimEventQuest(player, eventKey, questKey)
	local data = PlayerDataService.Get(player)
	if not data then return false end

	local event = GameConfig.GetEvent(eventKey)
	if not event then return false end

	local now = EventService.Now()
	local window = GameConfig.GetEventWindow(event, now)
	if not (window and window.active) then
		notify(player, { kind = "error", message = "That event isn't running right now!" })
		return false
	end

	local quest, index = GameConfig.GetEventQuestDef(eventKey, questKey)
	if not quest then return false end

	local board = GameConfig.GetEventBoard(data, eventKey, window)
	if not board then return false end

	if board.claimed[questKey] then
		notify(player, { kind = "error", message = "Already claimed that one!" })
		return false
	end
	if (board.progress[questKey] or 0) < quest.target then
		notify(player, { kind = "error", message = "That step isn't finished yet!" })
		return false
	end
	-- IN ORDER -- see the note over GameConfig.EventQuests for why the order is enforced at the
	-- button and not at the counter. One step back is enough: rung N cannot be claimed unless N-1
	-- was, so by induction the whole ladder below it has been.
	if index > 1 then
		local previous = GameConfig.GetEventQuests(eventKey)[index - 1]
		if previous and not board.claimed[previous.key] then
			notify(player, { kind = "error", message = ("Claim %s %s first!"):format(previous.emoji, previous.name) })
			return false
		end
	end

	-- MARKED BEFORE ANYTHING IS PAID, AND NOTHING BETWEEN THEM YIELDS. Same rule 5.1's code
	-- redemption is built on: the gap between "decide it is allowed" and "record that it happened"
	-- is the whole of a double-claim exploit, and two claims arriving on the same frame would
	-- otherwise both pass the check above.
	board.claimed[questKey] = true

	-- The SAME payout the season quests use, exported rather than copied: a second implementation of
	-- "what a reward table means" is how one board learns to scale DNA and the other forgets to.
	SeasonPassService.GrantReward(data, quest, player)

	-- THE SKIN, ON THE LAST RUNG ONLY.
	--
	-- Resolved from the window that is being claimed, never from `event.reward` directly -- that is
	-- 12.13's rule and it is what makes a rotation correct: the board is stamped with this
	-- occurrence's start, `GetEventRewardKey` reads the same start, so the champion a player earns
	-- is the champion of the weekend they earned it in, however late in that weekend they press it.
	local grantedEntry
	if quest.character then
		local key = GameConfig.GetEventRewardKey(event, window)
		local entry = key and GameConfig.GetCharacter(key)
		-- an unknown key is a config mistake, not a runtime one: it is skipped rather than written,
		-- because a save holding a key nothing resolves is a body the costume code cannot paint
		if entry then
			data.EventCharacters = data.EventCharacters or {}
			if not data.EventCharacters[key] then
				data.EventCharacters[key] = true
				grantedEntry = entry
			end
			-- copies it into the working `Characters` table the Journal and the costume read
			GameConfig.SyncEventCharacters(data)
		end
	end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)

	notify(player, {
		kind = "reward",
		message = ("%s %s\n%s"):format(quest.emoji, quest.name,
			SeasonPassService.RewardText(quest, data)),
	})
	-- The character card comes SECOND and on its own, because it is the thing the ladder was for.
	-- Folding it into the line above would print the weekend's exclusive as one more "+15 diamonds".
	if grantedEntry then
		notifyGrant(player, grantedEntry)
	end
	return true
end

-- ============================================================================
-- ANNOUNCING
-- ============================================================================
-- Through AnnounceService, which is where 6.2 put the decision about what is worth telling the room
-- about. An event has no position in the world, so there is no beam -- only the toast, which is
-- exactly the shape 5.4's cross-server message will arrive in.
local function announce(event, opening, window, now)
	AnnounceService.Broadcast({
		kind = "event",
		color = event.color,
		headline = opening
			and ("%s  %s IS LIVE!"):format(event.emoji, event.name:upper())
			or ("%s  %s HAS ENDED"):format(event.emoji, event.name:upper()),
		subline = opening
			and ("%s -- %s left"):format(event.blurb, GameConfig.FormatDuration(window.endTs - now))
			or "Thanks for playing -- the next one is on the board",
	})
end

-- ============================================================================
-- THE SIGN
-- ============================================================================
local function paint(part, color)
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
end

local function buildSign(parent)
	local model = Instance.new("Model")
	model.Name = "EventBoard"

	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Size = Vector3.new(SIGN_T, SIGN_H, SIGN_W)
	panel.CFrame = CFrame.new(SIGN_X, POST_H + SIGN_H * 0.5, SIGN_Z)
	paint(panel, UITheme.Color.Outline)
	panel.Parent = model

	for _, dz in ipairs({ -SIGN_W * 0.35, SIGN_W * 0.35 }) do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Size = Vector3.new(SIGN_T, POST_H + 2, 3)
		post.CFrame = CFrame.new(SIGN_X, (POST_H + 2) * 0.5, SIGN_Z + dz)
		paint(post, UITheme.Color.Outline)
		post.Parent = model
	end

	-- The leaderboards stand at x=-130 and read from +X; this one stands at x=+130 on the other side
	-- of the same street, so its reading face is the OPPOSITE one. A board a player has to walk
	-- behind to read is a board nobody reads.
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.AlwaysOnTop = false
	gui.Parent = panel

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(244, 242, 252)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -16, 0, 84)
	header.Position = UDim2.new(0, 8, 0, 8)
	header.BackgroundColor3 = UITheme.Color.Lavender
	header.BorderSizePixel = 0
	header.Parent = bg
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 12)
	hCorner.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 1, -10)
	title.Position = UDim2.new(0.5, 0, 0.5, 0)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Font = UITheme.Font.Display
	title.Text = "EVENTS"
	title.TextColor3 = UITheme.Color.White
	title.TextScaled = true
	title.Parent = header
	UITheme.OutlineText(title, 3)

	-- THE LAYOUT BELOW FILLS THE PANEL, and the first version did not. At 24 pixels a stud a
	-- 34 x 30 board is an 816 x 720 canvas; the first pass ended at y=440 and left the bottom 280
	-- pixels -- more than a third of the sign -- blank. Nothing reported it, because every label
	-- fitted its own box perfectly. Only a photograph shows a sign that is two-thirds used.
	local name = Instance.new("TextLabel")
	name.Name = "EventName"
	name.Size = UDim2.new(1, -20, 0, 86)
	name.Position = UDim2.new(0, 10, 0, 104)
	name.BackgroundTransparency = 1
	name.Font = UITheme.Font.Display
	name.Text = ""
	name.TextColor3 = UITheme.Color.Outline
	name.TextScaled = true
	name.Parent = bg

	-- The countdown is the biggest thing on the sign on purpose: the name tells you what, the clock
	-- is the reason to do something about it now rather than later.
	local clock = Instance.new("TextLabel")
	clock.Name = "Clock"
	clock.Size = UDim2.new(1, -20, 0, 210)
	clock.Position = UDim2.new(0, 10, 0, 200)
	clock.BackgroundTransparency = 1
	clock.Font = UITheme.Font.Display
	clock.Text = ""
	clock.TextColor3 = UITheme.Color.Outline
	clock.TextScaled = true
	clock.Parent = bg
	-- NO HALO ON THIS ONE (15.15). The colour above IS `Color.Outline` -- the very colour
	-- `OutlineText` draws with -- so a stroke here wrapped the countdown in a 3px band of its own
	-- ink. `UITheme.IsDarkInk` is the shared test; it is spelled out rather than called because
	-- this label's colour is the outline colour by name, which is the clearest possible case.
	UITheme.OutlineText(clock, 0)

	local blurb = Instance.new("TextLabel")
	blurb.Name = "Blurb"
	blurb.Size = UDim2.new(1, -24, 0, 250)
	blurb.Position = UDim2.new(0, 12, 0, 440)
	blurb.BackgroundTransparency = 1
	blurb.Font = UITheme.Font.Body
	blurb.Text = ""
	blurb.TextColor3 = Color3.fromRGB(96, 92, 118)
	blurb.TextWrapped = true
	blurb.TextScaled = true
	blurb.Parent = bg

	model.Parent = parent
	-- Persistent, so the sign does not stream out from under a player reading it. On the Model
	-- rather than through ZoneBuilder's ALWAYS_LOADED list -- see LeaderboardService's header for
	-- why scenery like this is built outside that file.
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	return { model = model, header = header, title = title, name = name, clock = clock, blurb = blurb }
end

local function ensureSign()
	local existing = workspace:FindFirstChild("EventBoard")
	if existing then
		-- IDEMPOTENT BY REPLACEMENT, never by skipping: a half-built sign from an interrupted run
		-- would otherwise survive forever behind an "already there" check. That failure left a zone
		-- permanently truncated once already.
		if existing:GetAttribute("SignVersion") == SIGN_VERSION and board then
			return board
		end
		existing:Destroy()
	end
	board = buildSign(workspace)
	board.model.Name = "EventBoard"
	board.model:SetAttribute("SignVersion", SIGN_VERSION)
	return board
end

-- Every state the board can be in is drawn, including having nothing to say. A blank sign looks
-- broken, and "no event" is a real and common answer on four days out of seven.
function EventService.DrawBoard()
	if not board or not board.model.Parent then return "no board" end
	local now = EventService.Now()
	local active = GameConfig.GetActiveEvents(now)

	if #active > 0 then
		-- `active[1]` is the HEADLINER, and since 12.13 that is a decided fact rather than table
		-- order -- GetActiveEvents sorts by priority. See the note over ColosseumClash.
		local live = active[1]
		board.title.Text = "\u{1F389}  LIVE NOW"
		board.header.BackgroundColor3 = live.event.color
		board.name.Text = ("%s %s"):format(live.event.emoji, live.event.name)
		board.clock.Text = GameConfig.FormatDuration(live.window.endTs - now)

		-- THE CO-RUNNERS ARE NAMED, because the sign is the one surface with room to name them.
		-- Two windows overlapping is the normal weekend now, not the one-in-a-hundred case a
		-- festival landing on a weekend used to be, and a board that headlines one of them and says
		-- nothing about the other is a board telling a player their DNA is NOT doubled. The HUD chip
		-- solves the same problem the other way, by summing every live effect onto one line -- it has
		-- 244 pixels and cannot spell out a name.
		local also = {}
		for i = 2, #active do
			table.insert(also, ("%s %s"):format(active[i].event.emoji, active[i].event.name))
		end
		local blurbText = live.event.blurb
		if live.event.key == "GlobalGoal" then
			local progressVal = RS:FindFirstChild("GlobalKillsProgress")
			if progressVal then
				local current = progressVal.Value
				local targetGoal = live.event.target or 5000000
				local formattedCurrent = GameConfig.FormatNumber and GameConfig.FormatNumber(current) or tostring(current)
				local formattedTarget = GameConfig.FormatNumber and GameConfig.FormatNumber(targetGoal) or tostring(targetGoal)
				blurbText = ("%s\n\n\u{1F3AF} Community Progress: %s / %s"):format(blurbText, formattedCurrent, formattedTarget)
			end
		end

		if #also > 0 then
			board.blurb.Text = ("%s\n\u{2795} also live: %s"):format(blurbText, table.concat(also, ", "))
		else
			board.blurb.Text = blurbText
		end
		return "live:" .. live.event.key
	end

	-- The same two-part answer as above, for the five days a week nothing is on: the headliner names
	-- itself and anything opening in the same instant is named under it. Both halves of the weekend
	-- start at 00:00 Saturday, so this branch is where a player standing here on a Wednesday decides
	-- whether Saturday is worth coming back for -- and it was the branch that used to name the wrong
	-- one of the two.
	local upcomingAll = GameConfig.GetUpcomingEvents(now)
	local upcoming = upcomingAll[1]
	if upcoming then
		board.title.Text = "\u{23F3}  NEXT EVENT"
		board.header.BackgroundColor3 = UITheme.Color.Lavender
		board.name.Text = ("%s %s"):format(upcoming.event.emoji, upcoming.event.name)
		board.clock.Text = GameConfig.FormatDuration(upcoming.window.nextStart - now)
		local with = {}
		for i = 2, #upcomingAll do
			table.insert(with, ("%s %s"):format(upcomingAll[i].event.emoji, upcomingAll[i].event.name))
		end
		if #with > 0 then
			board.blurb.Text = ("%s\n\u{2795} starting with it: %s"):format(upcoming.event.blurb, table.concat(with, ", "))
		else
			board.blurb.Text = upcoming.event.blurb
		end
		return "next:" .. upcoming.event.key
	end

	board.title.Text = "EVENTS"
	board.header.BackgroundColor3 = UITheme.Color.Lavender
	board.name.Text = "Nothing scheduled"
	board.clock.Text = "--"
	board.blurb.Text = "Check back soon."
	return "idle"
end

-- ============================================================================
-- THE POLL
-- ============================================================================
-- Returns a small report so a test can drive one cycle without waiting out the interval.
function EventService.Poll()
	local now = EventService.Now()
	local nowLive = {}
	local opened, closed = {}, {}

	for _, live in ipairs(GameConfig.GetActiveEvents(now)) do
		nowLive[live.event.key] = true
		if not wasLive[live.event.key] then
			table.insert(opened, live.event.key)
			announce(live.event, true, live.window, now)
		end
	end

	for key in pairs(wasLive) do
		if not nowLive[key] then
			local event = GameConfig.GetEvent(key)
			table.insert(closed, key)
			-- an event deleted from the table between two polls closes silently rather than erroring
			if event then
				announce(event, false, nil, now)
			end
		end
	end

	wasLive = nowLive

	-- On every poll, not only on a transition. This used to be the grant, and the comment here used
	-- to explain why a player already online when the window OPENED needed it (26.1 moved the grant
	-- to the ladder). It stays on the poll for the reason that outlived the grant: a rebirth clears
	-- `Characters` at an arbitrary moment, and this is the only thing that puts the event skins back.
	for _, player in ipairs(Players:GetPlayers()) do
		EventService.SyncCharacters(player)
	end

	if #opened > 0 or #closed > 0 then
		EventService.Publish()
	end
	return { opened = opened, closed = closed, live = nowLive }
end

-- ============================================================================
-- INIT
-- ============================================================================
function EventService.Init()
	valueObject = RS:FindFirstChild("LiveEvents")
	if not valueObject then
		valueObject = Instance.new("StringValue")
		valueObject.Name = "LiveEvents"
		valueObject.Value = ""
		valueObject.Parent = RS
	end

	ensureSign()

	-- The ladder's one door (26.1). Created rather than assumed, like every remote newer than the
	-- authored Remotes folder -- same helper shape as SeasonPassService and PetService.
	--
	-- NO RATE LIMIT, AND IT NEEDS NONE: `board.claimed[questKey]` is set before anything is paid and
	-- is checked before anything is decided, so a flood of claims for the same rung pays once and
	-- refuses the rest. A flood across four rungs is four legitimate presses.
	local remotes = RS:FindFirstChild("Remotes")
	if remotes then
		local claim = remotes:FindFirstChild("ClaimEventQuest")
		if not claim then
			claim = Instance.new("RemoteEvent")
			claim.Name = "ClaimEventQuest"
			claim.Parent = remotes
		end
		claim.OnServerEvent:Connect(function(player, eventKey, questKey)
			if typeof(eventKey) == "string" and typeof(questKey) == "string" then
				EventService.HandleClaimEventQuest(player, eventKey, questKey)
			end
		end)
	end

	-- SEEDED, NOT EMPTY. Starting with `wasLive = {}` on a server that boots inside a weekend would
	-- announce "WEEKEND RUSH IS LIVE" to everyone on the first poll -- once per server restart, and
	-- to players who have been in the middle of it for a day. A transition is a change, and a server
	-- that has just started has not seen one.
	for _, live in ipairs(GameConfig.GetActiveEvents(EventService.Now())) do
		wasLive[live.event.key] = true
	end

	EventService.Publish()
	EventService.DrawBoard()

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local data
			repeat
				task.wait(0.25)
				data = PlayerDataService.Get(player)
			until data or not player.Parent
			if data then
				EventService.SyncCharacters(player)
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			EventService.Poll()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL)
			EventService.Publish()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(BOARD_TICK)
			EventService.DrawBoard()
		end
	end)
end

return EventService
