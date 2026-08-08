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

local LeaderboardService = {}

-- Bumping this rebuilds the signs on the next server start, the same shape as RebirthShrine's
-- SHRINE_VERSION and ZoneBuilder's BUILD_VERSION.
local BOARD_VERSION = 1

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

local function drawBoard(board)
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
			label.Text = ("%s  %s   %s"):format(rank, row.name,
				board.short and shorten(row.value) or withCommas(row.value))
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
-- INIT
-- ============================================================================
function LeaderboardService.Init()
	buildSigns()

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
	return report
end

return LeaderboardService
