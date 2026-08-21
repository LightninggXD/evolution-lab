--[[
	LeaderboardService -- three global boards, and the physical signs that show them.

	The game had no cross-player comparison of any kind. These are the cheapest kind to add and the
	one players check without being asked, because they are standing in front of them.

	WHY THIS DOES NOT TOUCH ZoneBuilder. The obvious home for scenery is the world builder, but that
	file is 480 KB, its `BUILD_VERSION` guard regenerates all twenty zones when it moves, and it has
	its own documented edit hazards. `RebirthShrine` already set the precedent for the alternative:
	a standalone service that builds its own furniture in Forest and owns its own version stamp. A
	board is scenery, not terrain, and nothing else needs to know it exists.

	WHERE THEY STAND, and it was measured rather than chosen. A part-occupancy scan of the Forest
	zone on a 65x50 grid found the street at x=0 carrying 75-100 parts per cell and its lamp-and-
	bench verge at x=+-65 carrying 25-40, while **x = -130 is completely empty from z=140 to z=300**
	-- which is beside the walk from the spawn at (0, 366) down to the shop. So the boards stand in
	a row along that empty strip, facing +X, and a player reads them side-on as they walk past.

	=========================================================================================
	THE FOUR THINGS THAT GO WRONG WITH AN OrderedDataStore
	=========================================================================================
	1. IT ONLY STORES INTEGERS. `data.DNA` is a float and reaches the trillions; handed over raw it
	   is rejected and the board stays empty with no error anyone sees. Floored, and clamped below
	   2^53 -- past that a Lua double cannot represent consecutive integers anyway, so a rank order
	   built from them would be arbitrary.
	2. A FAILED WRITE MUST NOT BREAK A SAVE. Every call here is pcall'd and a failure is dropped.
	   This is a scoreboard; it is never worth a player's progress.
	3. THE READ IS A LOOP, NOT A REQUEST. `GetSortedAsync` is a web call with its own budget. It
	   runs on a timer for the whole server and every client reads the same cached answer, so a
	   hundred players cost exactly as much as one.
	4. USER IDs ARE NOT NAMES. The store holds ids; `GetNameFromUserIdAsync` is another web call, so
	   the answers are cached forever -- a display name that changes mid-session is not worth a
	   request per row per minute.

	In Studio this needs **Game Settings > Security > Enable Studio Access to API Services**. Without
	it every call fails, every pcall swallows it, and the boards read "warming up" rather than
	breaking anything.
--]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

-- UITheme only, for the palette and the outlined display font -- the signs are chrome and have to
-- match the HUD rather than inventing a second look. No GameConfig: nothing here reads game rules.
local UITheme = require(RS.Modules.UITheme)

local PlayerDataService = require(script.Parent.PlayerDataService)
local MapBoards = require(script.Parent.MapProps.MapBoards)
local BoardStats = require(script.Parent.MapProps.BoardStats)

local LeaderboardService = {}

-- Bumping this rebuilds the signs on the next server start, the same shape as RebirthShrine's
-- SHRINE_VERSION and ZoneBuilder's BUILD_VERSION.
local BOARD_VERSION = 3

-- 2^53. Above it a double stops being able to represent consecutive integers, so two players
-- 1 DNA apart would compare equal and the ordering would be noise.
local MAX_ORDERED = 9007199254740992

local TOP_N = 10
local REFRESH_INTERVAL = 60
local PUBLISH_INTERVAL = 60

local BOARDS = {
	{
		key = "Rebirths", field = "Rebirths",
		title = "\u{267B}\u{FE0F}  REBIRTHS", color = UITheme.Color.Lavender, short = false,
	},
	{
		key = "DNA", field = "DNA",
		title = "\u{1F9EC}  MOST DNA", color = UITheme.Color.Mint, short = true,
	},
	{
		key = "Kills", field = "Kills",
		title = "\u{2694}\u{FE0F}  KILLS", color = UITheme.Color.Coral, short = false,
	},

	-- ===== THE FIVE THE MAP ASKED FOR (31.5) =====
	-- The village map ships EIGHT boards, and `key` is deliberately the map child's own name: that
	-- is what `MapBoards` looks them up by, so a board added to the map and a board added here can
	-- never drift apart by a spelling. `field` is the save field `BoardStats` counts into.
	--
	-- TWO OF THEM ARE THE SAME STAT UNDER A DIFFERENT NAME. The map calls Diamonds "Total Gems", and
	-- Rebirths matches ours outright -- so those two were live from the moment the map went in and
	-- the other five needed counters written (see MapProps/BoardStats).
	--
	-- `short` is on wherever the number is an economy figure: DNA, Diamonds and click counts run to
	-- 1e17 in this game and a comma-grouped 1e17 does not fit a 20-stud board. Rebirths, eggs and
	-- secrets are small integers and read better in full.
	{
		key = "TotalGems", field = BoardStats.Field.TotalGems,
		title = "\u{1F48E}  TOTAL GEMS", color = UITheme.Color.Aqua, short = true,
	},
	{
		key = "TotalClicks", field = BoardStats.Field.TotalClicks,
		title = "\u{1F5B1}\u{FE0F}  TOTAL CLICKS", color = UITheme.Color.Sunny, short = true,
	},
	{
		key = "EggsOpened", field = BoardStats.Field.EggsOpened,
		title = "\u{1F95A}  EGGS OPENED", color = UITheme.Color.Lavender, short = false,
	},
	{
		key = "SecretsHatched", field = BoardStats.Field.SecretsHatched,
		title = "\u{2728}  SECRETS HATCHED", color = UITheme.Color.Coral, short = false,
	},
	{
		key = "TimePlayed", field = BoardStats.Field.TimePlayed,
		-- SECONDS in the save, hours on the board: see `formatValue`.
		title = "\u{23F1}\u{FE0F}  TIME PLAYED", color = UITheme.Color.Mint, short = false,
		clock = true,
	},
	{
		key = "RobuxSpent", field = BoardStats.Field.RobuxSpent,
		title = "\u{1F4B0}  ROBUX SPENT", color = UITheme.Color.Mint, short = false,
	},
}
LeaderboardService.Boards = BOARDS

-- [boardKey] = { { userId, name, value }, ... } -- read by the signs, and safe to read at any time
LeaderboardService.Top = {}

local stores = {}
local nameCache = {}
local rowLabels = {}   -- [boardKey] = { TextLabel, ... }
local statusLabels = {} -- [boardKey] = TextLabel

-- ============================================================================
-- NUMBERS
-- ============================================================================
local SUFFIX = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }

-- DNA reaches the trillions and a board is read at a glance from several studs away, so the DNA
-- column is shortened and the other two are not -- "14 rebirths" and "9,204 kills" are numbers a
-- player wants exactly.
local function shorten(n)
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	local mag = 0
	while n >= 1000 and mag < #SUFFIX do
		n = n / 1000
		mag += 1
	end
	-- THE ROUNDING CARRIES past the loop, which has already stopped looking: 999,999 divides once to
	-- 999.999, is accepted, and "%.1f" prints "1000.0K" for a number one short of a million. On a
	-- board that is read at a glance that is worse than the long form, because it looks like a real
	-- reading. 999.95 matches the ONE decimal this one prints.
	if n >= 999.95 and mag < #SUFFIX then
		n = n / 1000
		mag += 1
	end
	return ("%.1f%s"):format(n, SUFFIX[mag])
end

local function withCommas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- ============================================================================
-- THE STORES
-- ============================================================================
local function storeFor(board)
	if not stores[board.key] then
		-- versioned in the name: a board whose meaning changes needs a clean set of numbers rather
		-- than a mix of old and new ones that cannot be told apart
		stores[board.key] = DataStoreService:GetOrderedDataStore("EvolutionLab_LB_" .. board.key .. "_v1")
	end
	return stores[board.key]
end

local function publishOne(player, data)
	for _, board in ipairs(BOARDS) do
		local raw = tonumber(data[board.field]) or 0
		local value = math.floor(raw)
		-- 0 is not published at all: an empty board is better than one filled with people who have
		-- never done the thing it measures
		if value > 0 and value < MAX_ORDERED then
			pcall(function()
				storeFor(board):SetAsync(tostring(player.UserId), value)
			end)
		end
	end
end

-- Public so the leave-save can push a final figure, and so it can be driven in a test.
function LeaderboardService.Publish(player)
	local data = PlayerDataService.Get(player)
	if not data then return false end
	publishOne(player, data)
	return true
end

local function nameFor(userId)
	if nameCache[userId] then return nameCache[userId] end
	-- already on this server? then no web call at all
	local live = Players:GetPlayerByUserId(userId)
	if live then
		nameCache[userId] = live.DisplayName
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = ok and name or ("Player " .. userId)
	return nameCache[userId]
end

local function refreshOne(board)
	local ok, pages = pcall(function()
		return storeFor(board):GetSortedAsync(false, TOP_N)
	end)
	if not ok then return false end

	local ok2, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not ok2 then return false end

	local rows = {}
	for rank, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		if userId then
			rows[rank] = { userId = userId, name = nameFor(userId), value = entry.value }
		end
	end
	LeaderboardService.Top[board.key] = rows
	return true
end

-- ============================================================================
-- THE SIGNS
-- ============================================================================
local BOARD_X = -130          -- the empty strip beside the street; see the header
local BOARD_Z = { 280, 210, 140 }
local BOARD_W, BOARD_H, BOARD_T = 34, 40, 3
local POST_H = 8

local function paint(part, color)
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
end

local function buildSign(parent, board, z)
	local model = Instance.new("Model")
	model.Name = "Board_" .. board.key

	local baseY = POST_H + BOARD_H * 0.5

	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Size = Vector3.new(BOARD_T, BOARD_H, BOARD_W)
	panel.CFrame = CFrame.new(BOARD_X, baseY, z)
	paint(panel, UITheme.Color.Outline)
	panel.Parent = model

	for _, dz in ipairs({ -BOARD_W * 0.35, BOARD_W * 0.35 }) do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Size = Vector3.new(BOARD_T, POST_H + 2, 3)
		post.CFrame = CFrame.new(BOARD_X, (POST_H + 2) * 0.5, z + dz)
		paint(post, UITheme.Color.Outline)
		post.Parent = model
	end

	-- The reading face points at +X, i.e. at the street. A board a player has to walk behind to
	-- read is a board nobody reads.
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Right
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
	header.Size = UDim2.new(1, -16, 0, 84)
	header.Position = UDim2.new(0, 8, 0, 8)
	header.BackgroundColor3 = board.color
	header.BorderSizePixel = 0
	header.Parent = bg
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 12)
	hCorner.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 1, -10)
	title.Position = UDim2.new(0.5, 0, 0.5, 0)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Font = UITheme.Font.Display
	title.Text = board.title
	title.TextColor3 = UITheme.Color.White
	title.TextScaled = true
	title.Parent = header
	UITheme.OutlineText(title, 3)

	-- "warming up" rather than an empty board: an empty board looks broken, and the first read is
	-- a web call that has genuinely not happened yet on a server that has just started
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, -20, 0, 40)
	status.Position = UDim2.new(0, 10, 0, 100)
	status.BackgroundTransparency = 1
	status.Font = UITheme.Font.Body
	status.Text = "warming up..."
	status.TextColor3 = Color3.fromRGB(120, 116, 140)
	status.TextScaled = true
	status.Parent = bg
	statusLabels[board.key] = status

	local labels = {}
	for i = 1, TOP_N do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.new(1, -20, 0, 62)
		row.Position = UDim2.new(0, 10, 0, 100 + (i - 1) * 66)
		row.BackgroundTransparency = (i % 2 == 0) and 1 or 0.86
		row.BackgroundColor3 = UITheme.Color.Outline
		row.BorderSizePixel = 0
		row.Font = UITheme.Font.Body
		row.Text = ""
		row.TextColor3 = UITheme.Color.Outline
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextScaled = true
		row.Visible = false
		row.Parent = bg
		labels[i] = row
	end
	rowLabels[board.key] = labels

	model.Parent = parent
	-- Persistent, so the boards do not stream out from under a player who walks a little way off.
	-- Set on the Model rather than by adding names to ZoneBuilder's ALWAYS_LOADED list, which is
	-- the whole point of building this outside that file.
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	return model
end

local MEDAL = { "\u{1F947}", "\u{1F948}", "\u{1F949}" }

-- ONE FORMATTER FOR BOTH SURFACES (31.5). The generated sign and the map's board have to agree
-- about what a number looks like, and they will not if each formats its own -- which is exactly how
-- a "Time Played" board ends up reading 5184000 next to a podium reading 60d.
local function formatValue(board, value)
	if board.clock then
		local secs = math.max(math.floor(tonumber(value) or 0), 0)
		local d = math.floor(secs / 86400)
		local h = math.floor(secs % 86400 / 3600)
		local m = math.floor(secs % 3600 / 60)
		-- Days only once there are any: "0d 3h" reads as a bug on a board about how long you played.
		if d > 0 then return ("%dd %dh"):format(d, h) end
		if h > 0 then return ("%dh %dm"):format(h, m) end
		return ("%dm"):format(m)
	end
	return board.short and shorten(value) or withCommas(value)
end

-- The map's own boards, when the zone has them. Returns true when it drew, so the generated-sign
-- path below is skipped rather than run into nil label handles.
local function drawMapBoard(board)
	if not MapBoards.Has(board.key) then return false end
	local rows = LeaderboardService.Top[board.key]
	if not rows then return MapBoards.DrawStatus(board.key, "warming up...") end
	if #rows == 0 then return MapBoards.DrawStatus(board.key, "nobody yet") end
	local out = {}
	for i, row in ipairs(rows) do
		out[i] = { name = row.name, text = formatValue(board, row.value) }
	end
	return MapBoards.Draw(board.key, out)
end

local function drawBoard(board)
	if drawMapBoard(board) then return end
	local labels = rowLabels[board.key]
	local status = statusLabels[board.key]
	if not labels then return end

	local rows = LeaderboardService.Top[board.key]
	if not rows then
		if status then status.Text = "warming up..." status.Visible = true end
		return
	end
	if #rows == 0 then
		if status then status.Text = "nobody on the board yet" status.Visible = true end
		for _, l in ipairs(labels) do l.Visible = false end
		return
	end
	if status then status.Visible = false end

	for i, label in ipairs(labels) do
		local row = rows[i]
		if row then
			local rank = MEDAL[i] or ("#" .. i)
			label.Text = ("%s  %s   %s"):format(rank, row.name, formatValue(board, row.value))
			label.Visible = true
		else
			label.Visible = false
		end
	end
end

local function buildSigns()
	local existing = workspace:FindFirstChild("Leaderboards")
	if existing then
		-- IDEMPOTENT BY REPLACEMENT, not by skipping. A half-built set from an interrupted run would
		-- otherwise survive forever behind a "already there" check -- the failure mode that left a
		-- zone permanently truncated once already.
		if existing:GetAttribute("BoardVersion") == BOARD_VERSION then
			return existing
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder:SetAttribute("BoardVersion", BOARD_VERSION)
	for i, board in ipairs(BOARDS) do
		buildSign(folder, board, BOARD_Z[i] or (140 + i * 70))
	end
	folder.Parent = workspace
	return folder
end

-- ============================================================================
-- THE PODIUM: #1, #2 AND #3 (10.19, generalised in 12.11)
-- ============================================================================
-- The boards say who is winning; the statues are what make it feel like winning. Each is cast from
-- the REAL avatar of whoever holds that rank, via `Players:CreateHumanoidModelFromUserId` --
-- measured at 0.75 s for a 17-part R15 rig, so it is a yield and lives on its own task, never on
-- the refresh loop.
--
-- IT FOLLOWS ONE BOARD, AND THAT BOARD IS DNA. DNA is the headline number -- it is what the topbar
-- shows and what every other system pays out in -- so it is the one worth carving.
--
-- WHY THREE NOW, WHEN 10.19 DELIBERATELY BUILT ONE. Its reason was that "three statues would be
-- three-quarters of a wall of statues nobody reads", and that is true of three statues spaced out
-- along a row of signs, which is what the row of signs already is. A PODIUM is a different object:
-- one composition read at a glance, where second and third exist to say how far ahead first is, and
-- where the empty plinth beside the leader is the thing that makes a player want to be on it. So
-- the three stand together, gold in the middle on the tallest plinth, and the group reads as one
-- monument rather than as three landmarks.
--
-- THEY FACE +Z, AND THAT IS A FIX RATHER THAN A CHOICE. 10.19 yawed the figure by `math.pi * 0.5`
-- with a comment saying it faces +X, the street the boards read toward. It does not: a model's
-- facing is its pivot's LookVector, which is -Z at identity, and a yaw of t sends it to
-- (-sin t, 0, -cos t) -- so a quarter turn points it at **-X**, i.e. away from the street and away
-- from its own nameplate. Measured on the live statue before this row touched it: pivot LookVector
-- (-1, 0, 0), right hand at z = 90 against a centre of 95, which is where a figure's right hand
-- goes when it is facing -X. A half turn (t = pi) is the one that gives +Z.
-- +Z is also what the composition wants now: a player walks DOWN the boulevard from the spawn at
-- z = 366, so a row spread along x meets them face-on, where a row facing +X would queue the three
-- of them up one behind another and the nearest would hide the other two.
--
-- WHERE THEY STAND, measured against the live world rather than chosen. All three sit at z = 95 on
-- the plaza deck (x -172..172, z 80..416), gold keeping 10.19's proven spot at x = -130. The only
-- standing thing anywhere near is HubPlaza's lamp at (-84, 112) with a 10x26x10 footprint, so the
-- silver plinth stops at x = -92 and the bronze at x = -168, leaving 3 studs to the lamp and 4 to
-- the deck's west edge. HubPlaza's `standAt` pads nothing, so those gaps are the whole margin --
-- and `LeaderboardService.Init` runs BEFORE `HubPlaza.Init`, which means these plinths are in the
-- world when the lamp search runs and a plinth that grew would silently push the lamp instead.
local STATUE_BOARD = "DNA"
local PODIUM_Z = 95

-- EACH PLINTH IS edged/capped, THE VOCABULARY THE SPLICER MACHINE PAID FOR. A bright mass with a
-- dark lip under it and a dark cap over it: the cap is what the figure stands on, so a bright metal
-- figure has a near-black plane under it and the "contrast with what you stand on" rule is
-- satisfied by construction -- which is the rule 10.19 discovered when a cream figure on a cream
-- base read as a smudge. `metal` is always brighter than `stone` so the figure, not the plinth, is
-- the brightest thing in the composition.
--
-- THE TONES WERE PHOTOGRAPHED, NOT PICKED, AND THE FIRST SET FAILED. 10.19's bronze (196, 138, 74)
-- was a good #1 tone when there was only one statue; put it beside gold under Forest's very bright
-- key light and BOTH clip to the same lemon yellow -- gold and bronze differed by 1.2x in red and
-- 1.4x in green, which survives a colour picker and does not survive the light. Photographed from
-- eye height at 30 studs, the two were indistinguishable. Bronze is now genuinely copper
-- (170, 92, 44), i.e. pulled 26 points down and hard toward red, and it separates. Same lesson as
-- the plaza's stone ramp: the light decides, not the paint -- do not "correct" these back toward
-- what reads as bronze in a picker.
local OUTLINE_TONE = Color3.fromRGB(26, 22, 42)

local STATUE_SLOTS = {
	{   -- gold
		x = -130, figureH = 22, plinthTop = 9.0, base = 26, body = 22, cap = 24,
		metal = Color3.fromRGB(245, 205, 105),
		stone = Color3.fromRGB(150, 112, 44),
	},
	{   -- silver, on the viewer's right as they come down the boulevard
		x = -102, figureH = 19, plinthTop = 7.5, base = 20, body = 16, cap = 18,
		metal = Color3.fromRGB(214, 219, 232),
		stone = Color3.fromRGB(112, 118, 138),
	},
	{   -- bronze -- see the note above: this is NOT 10.19's #1 tone, and it cannot be
		x = -158, figureH = 17, plinthTop = 6.0, base = 20, body = 16, cap = 18,
		metal = Color3.fromRGB(170, 92, 44),
		stone = Color3.fromRGB(140, 84, 42),
	},
}

-- Who is standing on each plinth now, so a refresh that does not change a rank does no work at all
-- -- rebuilding the same avatar every minute would be a web call and a model swap for nothing, and
-- the flicker would be visible to anyone standing in front of it.
local statueUserIds = {}   -- [slot] = userId
local statueValues = {}    -- [slot] = the DNA figure its plate is quoting
local plateLabels = {}     -- [slot] = TextLabel
-- One worker for the whole podium, never one per slot: a rank shuffle can dirty all three at once
-- and three simultaneous avatar fetches is three web calls in one frame for a piece of scenery.
local statueWorking = false

-- ===== A USERID THIS SERVER CANNOT TURN INTO A FIGURE, SO THE PODIUM STOPS ASKING (2026-08-15) ==
--
-- `buildStatue` returns false on a failed fetch WITHOUT writing `statueUserIds`, so the next
-- refresh sees "the person on this plinth changed" all over again and re-queues the identical
-- failing web call. Nothing ever converges: a Studio playtest printed
--     could not fetch avatar for -2: Players:CreateHumanoidFromUserId() got invalid userId
-- on every single refresh for the whole session, and on a live server a deleted account in the top
-- three would do the same thing forever, one web call at a time.
--
-- STUDIO TEST PLAYERS HAVE A NEGATIVE USERID and no web call will ever resolve one, so those are
-- not even attempted -- there is nothing to warn about and nothing to retry. A real id that fails
-- is warned about ONCE and then joins them.
--
-- The degraded state is deliberate and is not an empty plinth: the plate still carries the name and
-- the DNA figure, so the board stays truthful and only the carved figure is missing.
local statueUnavailable = {}   -- [userId] = true

local function canFetchAvatar(userId)
	return type(userId) == "number" and userId > 0 and not statueUnavailable[userId]
end

local function stoneify(model, tone)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CastShadow = true
			d.Color = tone
			d.Material = Enum.Material.Sand
			-- A MeshPart keeps its avatar texture unless the texture is cleared, and a statue wearing
			-- a printed t-shirt is not a statue. `Color` alone only tints the print.
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			-- the face is a Decal; carved stone has no eyes drawn on it
			d:Destroy()
		elseif d:IsA("Humanoid") then
			-- keep the rig, drop the actor: a live Humanoid tries to stand, plays an idle animation
			-- and prints state warnings for a thing that is meant to be furniture
			d:Destroy()
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

-- The plate is repainted on its own, without touching the figure, because the common case by far is
-- "the same player, a bigger number" -- an avatar fetch for that would be a web call to redraw text.
local function drawPlate(slotIndex, name, value)
	-- The map's own podium, when the zone has one. Written BEFORE the early return below, because
	-- on a mapped zone `plateLabels` is empty by design -- `buildPlinths` never ran -- and putting
	-- this after the return is how the whole podium silently stops updating.
	if MapBoards.HasPodium() then
		local board = nil
		for _, b in ipairs(BOARDS) do
			if b.key == STATUE_BOARD then board = b break end
		end
		MapBoards.SetPodium(slotIndex, name,
			name and board and formatValue(board, value or 0) or nil)
	end

	local label = plateLabels[slotIndex]
	if not label then return end
	local medal = MEDAL[slotIndex] or ("#" .. slotIndex)
	if not name then
		label.Text = ("%s  #%d\nunclaimed"):format(medal, slotIndex)
	else
		label.Text = ("%s  %s\n%s DNA"):format(medal, name, shorten(value or 0))
	end
end

local function statueName(slotIndex)
	return "TopStatue" .. slotIndex
end

-- A rank that empties out -- three players on the board yesterday, two today -- has to take its
-- figure down, or the plinth keeps a player who is no longer on it.
local function clearStatue(slotIndex)
	local folder = workspace:FindFirstChild("Leaderboards")
	local old = folder and folder:FindFirstChild(statueName(slotIndex))
	if old then old:Destroy() end
	statueUserIds[slotIndex] = nil
	statueValues[slotIndex] = nil
	drawPlate(slotIndex, nil)
end

local function buildStatue(slotIndex, userId, name, value)
	local folder = workspace:FindFirstChild("Leaderboards")
	local slot = STATUE_SLOTS[slotIndex]
	if not folder or not slot then return false end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then
		-- once, and never again for this player -- see canFetchAvatar
		statueUnavailable[userId] = true
		warn("[LeaderboardService] could not fetch avatar for " .. tostring(userId) .. ": " .. tostring(model))
		return false
	end

	-- ===== ORDER MATTERS, AND GETTING IT WRONG IS SILENT =====
	--
	-- ANCHOR LAST. The first version anchored and recoloured before positioning, and the statue came
	-- out as a scatter of limbs: measured, a 21-stud bounding box around a torso 2.5 studs tall, with
	-- a hand 10.8 studs off centre. A model straight from this API is held together by Motor6Ds that
	-- have not resolved yet -- anchoring each part first freezes every limb wherever it happened to
	-- be authored, and no later `PivotTo` can gather them, because anchored parts do not follow a
	-- joint. Parent it, let the joints settle, THEN freeze it.
	-- Captured BEFORE the new one is parented. Both carry this slot's name for the moment they
	-- coexist, and `FindFirstChild` returns whichever it reaches first -- ask afterwards and you can
	-- be handed the new model and leave the old one standing inside it forever.
	local old = folder:FindFirstChild(statueName(slotIndex))

	model.Name = statueName(slotIndex)
	model.Parent = folder
	task.wait()

	-- ...BUT ANCHOR AS SOON AS THE JOINTS HAVE. The second version waited until the very end and the
	-- statue came out **13.6 studs underground**: between the wait above and the recolour below the
	-- model is parented to the workspace and unanchored, so gravity has several frames to act on it
	-- and the careful seating lands on a figure that is already falling. Freeze it here -- after the
	-- joints have gathered the limbs, before anything is measured or moved.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	-- Scale to a fixed height rather than trusting the rig. Avatar scaling is a player setting, so
	-- two winners can differ by a third of their height, and a landmark that changes size when the
	-- leaderboard changes reads as a bug.
	-- ...and the three heights are a ladder, not a constant: 22 / 19 / 17 studs on plinths of
	-- 9.0 / 7.5 / 6.0, so the podium reads as a ranking from any distance at which the plates are
	-- already too small to read. Which means the height has to be RIGHT, and one pass does not get
	-- it right.
	--
	-- MEASURE, SCALE, MEASURE AGAIN. A rig's ACCESSORIES are welded a frame or two after the model
	-- is parented, and until they are, the bounding box is taller than the figure that settles out
	-- of it -- so a single `ScaleTo` scales against a height that is about to shrink. Measured on
	-- the live board: the #1 avatar carries no accessories and came out at 22.000 studs exactly,
	-- while the #2 avatar carries three and came out at **17.14 against an asked-for 19**, a tenth
	-- short, which is enough to put second and third the wrong way round in the silhouette. The
	-- second pass costs one frame and a multiply, and is a no-op on a rig that was already settled.
	-- The `task.wait` is safe here in a way it is not fifteen lines above: everything is already
	-- anchored, so nothing can fall during it.
	for _ = 1, 2 do
		local _, size = model:GetBoundingBox()
		if size.Y > 0.1 then
			model:ScaleTo(model:GetScale() * (slot.figureH / size.Y))
		end
		task.wait()
	end

	-- SEAT IT BY ITS OWN BOUNDING BOX, in two steps, exactly the way ZoneBuilder seats a model whose
	-- pivot it does not control: put it down first, read where the bottom actually landed, then lift
	-- by that much. Guessing the drop from the pivot is what once left the Forest trees hovering.
	-- Yawed a HALF turn so the figure faces +Z, up the boulevard the player walks down. See the
	-- section header: a quarter turn is what 10.19 wrote and it points the figure at -X.
	model:PivotTo(CFrame.new(slot.x, 0, PODIUM_Z) * CFrame.Angles(0, math.pi, 0))
	local cf, s2 = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, slot.plinthTop - (cf.Position.Y - s2.Y * 0.5), 0))

	-- ...and only now is it furniture.
	stoneify(model, slot.metal)
	if old then old:Destroy() end

	drawPlate(slotIndex, name, value)
	statueUserIds[slotIndex] = userId
	statueValues[slotIndex] = value
	return true
end

-- A square slab stated by the plane its TOP sits on, exactly as HubPlaza states its paving. Every
-- tier is grown down INTO the one below it by 0.3, so no two of them ever share a horizontal plane
-- -- the terrace-shimmer trap, which is a real hazard here because the tiers are concentric.
local function tier(parent, name, cx, cz, w, bottom, top, colour)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(w, top - bottom, w)
	p.CFrame = CFrame.new(cx, (top + bottom) * 0.5, cz)
	paint(p, colour)
	p.CastShadow = true
	p.Parent = parent
	return p
end

-- The plinths are built once with the signs; only the figures on top are ever replaced.
local function buildPlinths(folder)
	for i, slot in ipairs(STATUE_SLOTS) do
		local model = Instance.new("Model")
		model.Name = "Plinth" .. i

		-- Above the deck (top 1.04) but never below 2.0, so the bronze plinth's lip is still a lip
		-- and not a line scratched on the pavement.
		local baseTop = math.max(2.0, slot.plinthTop * 0.3)
		local capBottom = slot.plinthTop - 1.0

		tier(model, "PlinthBase", slot.x, PODIUM_Z, slot.base, -1.0, baseTop, OUTLINE_TONE)
		tier(model, "PlinthBody", slot.x, PODIUM_Z, slot.body, baseTop - 0.3, capBottom, slot.stone)
		tier(model, "PlinthCap", slot.x, PODIUM_Z, slot.cap, capBottom - 0.3, slot.plinthTop, OUTLINE_TONE)

		-- The nameplate hangs on the plinth's +Z face, the one the figure is looking over, and is its
		-- own part so replacing the figure never touches it. 0.55 proud of the body so it reads as a
		-- plaque bolted on rather than as paint.
		--
		-- IT IS DELIBERATELY SMALL, AND THE FIRST CUT WAS NOT. At 0.84 of the body's width and 0.86
		-- of its height the plaque covered essentially the whole front face, so from the one angle
		-- the podium is meant to be read from -- head on -- each plinth was a dark base, a dark
		-- plaque and a dark cap, with the bright stone visible only from the sides. Photographed,
		-- all three read as black blocks. That is the outline-first rule inverted: the mass has to
		-- be the bright thing. At 0.62 x 0.52 the stone frames the plaque on all four sides and the
		-- plinths read gold / silver / copper from across the plaza.
		local plateH = (capBottom - baseTop) * 0.52
		local plate = Instance.new("Part")
		plate.Name = "Plate"
		plate.Size = Vector3.new(slot.body * 0.62, plateH, 1)
		plate.CFrame = CFrame.new(slot.x, baseTop + (capBottom - baseTop) * 0.46, PODIUM_Z + slot.body * 0.5 + 0.55)
		paint(plate, OUTLINE_TONE)
		plate.Parent = model

		local gui = Instance.new("SurfaceGui")
		-- +Z IS `Back`, NOT `Front`. NormalId.Front is the -Z face, because a part's LookVector is
		-- its -Z axis -- the same off-by-a-face that cost 12.8 three blocked camera solves.
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.Parent = plate

		local label = Instance.new("TextLabel")
		label.Name = "PlateLabel"
		label.Size = UDim2.new(1, -8, 1, -6)
		label.Position = UDim2.new(0.5, 0, 0.5, 0)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Font = UITheme.Font.Display
		label.Parent = gui
		UITheme.OutlineText(label)
		plateLabels[i] = label
		drawPlate(i, nil)

		model.Parent = folder
	end
end

-- Called after every DNA refresh. Cheap and silent when nothing has changed rank, and it does the
-- least work each slot needs: nothing at all when the same player holds the same figure, a plate
-- repaint when only the number moved, and an avatar fetch only when the PERSON changed. That is
-- what makes "a rank change swaps only the changed statue" true by construction.
--
-- A player who slides from #1 to #2 is fetched a second time rather than having their model moved
-- across. Reusing it would mean re-scaling and re-seating a stoneified rig for one saved web call
-- on the rarest event this system has, and the swap is already invisible behind one task.
local function refreshStatues()
	local rows = LeaderboardService.Top[STATUE_BOARD]
	if not rows then return end

	local jobs = {}
	for i in ipairs(STATUE_SLOTS) do
		local row = rows[i]
		if not row or not row.userId then
			if statueUserIds[i] then clearStatue(i) end
		elseif row.userId ~= statueUserIds[i] then
			if canFetchAvatar(row.userId) then
				table.insert(jobs, { i, row.userId, row.name, row.value })
			else
				-- Plate only. Recording the id here is the whole point: it is what makes this slot
				-- settled rather than permanently dirty.
				if statueUserIds[i] then clearStatue(i) end
				statueUserIds[i] = row.userId
				statueValues[i] = row.value
				drawPlate(i, row.name, row.value)
			end
		elseif row.value ~= statueValues[i] then
			statueValues[i] = row.value
			drawPlate(i, row.name, row.value)
		end
	end

	if #jobs == 0 or statueWorking then return end
	statueWorking = true
	task.spawn(function()
		-- ONE EXIT PATH. The flag is cleared before anything else can throw, or a single failed
		-- fetch would leave the podium frozen for the life of the server with nothing reporting it.
		local ok, err = pcall(function()
			for _, job in ipairs(jobs) do
				buildStatue(job[1], job[2], job[3], job[4])
			end
		end)
		statueWorking = false
		if not ok then
			warn("[LeaderboardService] statue pass failed: " .. tostring(err))
		end
	end)
end

-- ============================================================================
-- INIT
-- ============================================================================
function LeaderboardService.Init()
	-- ===== THE MAP'S BOARDS COME FIRST (31.5) =====
	-- `ForestMapService` runs at ServerMain:79 and this at :145, so the census is already published
	-- by the time we get here. When it has boards, ours are never built at all -- not built and
	-- hidden: an unbuilt slab cannot be found floating in the trees behind the village, which is
	-- what the owner photographed.
	local adopted = MapBoards.Adopt("Forest")
	if adopted > 0 then
		print(("[LeaderboardService] adopted %d map boards, podium=%s -- generated signs not built")
			:format(adopted, tostring(MapBoards.HasPodium())))
		LeaderboardService.Adopted = adopted
	end

	local folder = adopted == 0 and buildSigns() or nil
	if folder then
		if not folder:FindFirstChild("Plinth1") then
			buildPlinths(folder)
		elseif not plateLabels[1] then
			-- The folder outlived this module's state -- `buildSigns` returns an existing folder of
			-- the right version untouched, so a second Init would leave every plate handle nil and
			-- `drawPlate` would no-op forever with nothing reporting it. Re-bind rather than rebuild.
			for i = 1, #STATUE_SLOTS do
				local p = folder:FindFirstChild("Plinth" .. i)
				plateLabels[i] = p and p:FindFirstChild("PlateLabel", true) or nil
			end
		end
	end

	-- a final figure on the way out, so a player who logs off after a big session is on the board
	-- before the next refresh rather than a minute later
	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.Publish(player)
	end)

	task.spawn(function()
		while true do
			for _, board in ipairs(BOARDS) do
				refreshOne(board)
				drawBoard(board)
				-- THE STATUE IS DRIVEN FROM THE SAME DATA THE SIGN WAS JUST PAINTED FROM, on the same
				-- pass, which is what makes "the board and the statue agree" true by construction
				-- rather than by two schedules happening to line up.
				if board.key == STATUE_BOARD then
					refreshStatues()
				end
				-- spread across the interval rather than three web calls in one frame
				task.wait(REFRESH_INTERVAL / #BOARDS)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				LeaderboardService.Publish(player)
			end
		end
	end)
end

-- Public for testing: forces one full cycle without waiting out the timers.
function LeaderboardService.RefreshNow()
	local report = {}
	for _, board in ipairs(BOARDS) do
		local ok = refreshOne(board)
		drawBoard(board)
		report[board.key] = ok and #(LeaderboardService.Top[board.key] or {}) or false
	end
	-- SYNCHRONOUS here, unlike the loop's fire-and-forget: a test that returns before the avatars
	-- have been fetched cannot check what it just asked for. This is the only caller that waits.
	local rows = LeaderboardService.Top[STATUE_BOARD] or {}
	local statues = {}
	for i in ipairs(STATUE_SLOTS) do
		local row = rows[i]
		if not row or not row.userId then
			clearStatue(i)
			statues[i] = "empty"
		elseif row.userId ~= statueUserIds[i] then
			statues[i] = buildStatue(i, row.userId, row.name, row.value)
		else
			if row.value ~= statueValues[i] then
				statueValues[i] = row.value
				drawPlate(i, row.name, row.value)
			end
			statues[i] = "unchanged"
		end
	end
	report.statues = statues
	return report
end

return LeaderboardService
