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
local BOARD_VERSION = 2

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
-- THE #1 STATUE (10.19)
-- ============================================================================
-- The boards say who is winning; the statue is what makes it feel like winning. It is cast from the
-- REAL avatar of whoever is first, via `Players:CreateHumanoidModelFromUserId` -- measured at 0.75 s
-- for a 17-part R15 rig, so it is a yield and lives on its own task, never on the refresh loop.
--
-- IT FOLLOWS ONE BOARD, AND THAT BOARD IS DNA. Three statues would be three-quarters of a wall of
-- statues nobody reads; one is a landmark. DNA is the headline number -- it is what the topbar shows
-- and what every other system pays out in -- so it is the one worth carving.
--
-- z = 95, at the end of the row of boards (they run 280 -> 140), on the same x = -130 strip. Probed
-- before choosing: the only things in a 30x48x30 box there are `Floor` and a ground decal, which is
-- exactly what a plinth wants to stand on.
local STATUE_BOARD = "DNA"
local STATUE_X, STATUE_Z = -130, 95
local STATUE_HEIGHT = 22          -- the avatar itself, plinth excluded
local PLINTH_H = 9
-- BRONZE ON A CREAM PLINTH. The zone statues are pale stone on purpose -- a statue tinted to its
-- biome is a green lump on green grass -- but this one stands on its own pale plinth, so pale-on-
-- pale is the same mistake in miniature: the first build put a cream figure on a cream base and it
-- read as a smudge. The figure contrasts with the thing it stands on, not with the field it is in,
-- and bronze says "trophy" for free.
local STATUE_TONE = Color3.fromRGB(196, 138, 74)

-- What is standing there now, so a refresh that does not change the leader does no work at all --
-- rebuilding the same avatar every minute would be a web call and a model swap for nothing, and the
-- flicker would be visible to anyone standing in front of it.
local statueUserId = nil

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

local function buildStatue(userId, name, value)
	local folder = workspace:FindFirstChild("Leaderboards")
	if not folder then return false end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then
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
	-- Captured BEFORE the new one is parented. Both are called "TopStatue" for the moment they
	-- coexist, and `FindFirstChild` returns whichever it reaches first -- ask afterwards and you can
	-- be handed the new model and leave the old one standing inside it forever.
	local old = folder:FindFirstChild("TopStatue")

	model.Name = "TopStatue"
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
	local _, size = model:GetBoundingBox()
	if size.Y > 0.1 then
		model:ScaleTo(STATUE_HEIGHT / size.Y)
	end

	-- SEAT IT BY ITS OWN BOUNDING BOX, in two steps, exactly the way ZoneBuilder seats a model whose
	-- pivot it does not control: put it down first, read where the bottom actually landed, then lift
	-- by that much. Guessing the drop from the pivot is what once left the Forest trees hovering.
	-- Yawed a quarter turn so the figure faces +X, the street the boards read toward.
	model:PivotTo(CFrame.new(STATUE_X, 0, STATUE_Z) * CFrame.Angles(0, math.pi * 0.5, 0))
	local cf, s2 = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, PLINTH_H - (cf.Position.Y - s2.Y * 0.5), 0))

	-- ...and only now is it furniture.
	stoneify(model, STATUE_TONE)
	if old then old:Destroy() end

	local plate = folder:FindFirstChild("StatuePlate")
	if plate then
		local label = plate:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = ("#1  %s\n%s DNA"):format(name or "?", shorten(value or 0))
		end
	end
	statueUserId = userId
	return true
end

-- The plinth is built once with the signs; only the figure on top is ever replaced.
local function buildPlinth(folder)
	local model = Instance.new("Model")
	model.Name = "StatuePlinth"

	for _, spec in ipairs({
		{ Vector3.new(26, 3, 26), PLINTH_H - 7.5, UITheme.Color.Outline },
		{ Vector3.new(22, 6, 22), PLINTH_H - 3, UITheme.Color.Cream },
	}) do
		local p = Instance.new("Part")
		p.Name = "PlinthTier"
		p.Size = spec[1]
		p.CFrame = CFrame.new(STATUE_X, spec[2], STATUE_Z)
		paint(p, spec[3])
		p.CastShadow = true
		p.Parent = model
	end
	model.Parent = folder

	-- the nameplate, on its own part so replacing the figure never touches it
	local plate = Instance.new("Part")
	plate.Name = "StatuePlate"
	plate.Size = Vector3.new(1, 5, 20)
	plate.CFrame = CFrame.new(STATUE_X + 11.4, PLINTH_H - 3, STATUE_Z)
	paint(plate, UITheme.Color.Outline)
	plate.Parent = folder

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right          -- at the street, exactly as the boards do
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = plate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "#1"
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = UITheme.Font.Display
	label.Parent = gui
	UITheme.OutlineText(label)
end

-- Called after every DNA refresh. Cheap and silent when the leader has not changed.
local function refreshStatue()
	local rows = LeaderboardService.Top[STATUE_BOARD]
	local first = rows and rows[1]
	if not first or not first.userId then return end
	if first.userId == statueUserId then return end
	task.spawn(buildStatue, first.userId, first.name, first.value)
end

-- ============================================================================
-- INIT
-- ============================================================================
function LeaderboardService.Init()
	local folder = buildSigns()
	if folder and not folder:FindFirstChild("StatuePlinth") then
		buildPlinth(folder)
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
					refreshStatue()
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
	-- SYNCHRONOUS here, unlike the loop's fire-and-forget: a test that returns before the avatar has
	-- been fetched cannot check what it just asked for. This is the only caller that waits.
	local rows = LeaderboardService.Top[STATUE_BOARD]
	local first = rows and rows[1]
	if first and first.userId and first.userId ~= statueUserId then
		report.statue = buildStatue(first.userId, first.name, first.value)
	else
		report.statue = "unchanged"
	end
	return report
end

return LeaderboardService
