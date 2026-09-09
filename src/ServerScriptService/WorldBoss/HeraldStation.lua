--[==[
	HeraldStation -- the ground the village's world boss stands on, and the board that says who is
	hitting it (22.4).

	===== THE ROW =====

	22.4: *"The world boss leaves the arena ... it is behind a teleport into a separate room on a
	30-minute timer. Put it -- or a sibling -- in the hub, visible from spawn, with a countdown on
	the HUD and a live contribution board."* The countdown on the HUD already exists (11.20). This
	file is the PLACE, and `HeraldService` is the fight.

	===== WHERE, AND WHY IT IS NOT CHOSEN BUT MEASURED =====

	Probed live on a booted server 2026-09-09, exactly the way `SprintTrack`'s lane was:

	  * the flat lawn north of the plaza gate runs x -150..135 by z 460..545 at y = 0.0, and the
	    flanking hills (`HorizonHillCollider`, ground y 274) start at x <= -155 and x >= 150;
	  * `SprintTrack` owns z 419..451 across the whole of it -- the running lane;
	  * `Zones.Forest.ZonePad` (0, 490) and `PortalMat` (x -17..17, z 470..568) are the Colosseum
	    gate's own approach and must stay walkable, so the middle is not available;
	  * `Map.MinigameTerminals` stands at (96, 452) and `Map.ExpeditionDoor` at (200, 440), which is
	    what pushes this west rather than east.

	So the Herald stands at **(-106, 0, 502)**: 172 studs from `ForestSpawn` (0, 1, 366), clear of
	the lane by 4 studs and of the hill by 4, and off the gate's approach entirely. A 38-unit rig is
	about 79 studs across and 62 tall, which subtends 20 degrees from the spawn pad -- the row's
	"visible from spawn" is a measurement, not a hope.

	===== WHY THERE IS ALMOST NO FURNITURE HERE =====

	`BossService.buildRig` already lays a boss its own arena -- dais, kerb, rubble and four pylons,
	scaled off the rig (`arenaDetail`), built with the boss and destroyed with it. Building a second
	dais under it would be two coplanar discs, which is the z-fighting patchwork the terrace pass
	spent a session on. So the permanent half is only what has to outlive the fight: a flush stone
	ring that says something stands here, and the board.

	Everything flush is stated by its TOP face and grown down to a buried bottom -- `HubPlaza` and
	`SprintTrack` both do this and both give the same reason. The rig's own dais rim lands at
	y -0.4..2.3, so the ring at 0.36 is simply covered while the Herald is up.

	===== THE BOARD IS A BillboardGui, NOT A SurfaceGui =====

	It has to be readable from the spawn pad 170 studs to the south AND from underneath the boss's
	feet while fighting, and a SurfaceGui is only ever legible from in front. Sized in STUDS (the
	arena's countdown board does the same) so it keeps its size at range instead of growing into
	the sky as you walk away.

	AND THEREFORE IT HANGS ON POSTS WITH NOTHING BEHIND IT. The first cut mounted the panel on a
	36 x 21 stone slab the same size as itself, which is right in front of the board and wrong from
	anywhere else: the slab is a fixed plane and the panel turns to face the camera, so at 40
	degrees off the face the two came apart and the shot showed a grey plank sticking out of the
	left of the panel. Anything solid the size of a camera-facing GUI does this. The posts are 1.8
	studs wide and the crossbar is a line, so there is nothing left to come apart.
]==]

local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local GameConfig = require(RS.Modules.GameConfig)

local HeraldStation = {}

-- Bumped whenever the geometry below changes, the same stamp shape as `PLAZA_VERSION` and
-- `TRACK_VERSION`: a server booting against an older number destroys what is there and rebuilds.
local STATION_VERSION = 2

local MODEL_NAME = "HeraldStation"

-- Measured; see the header. Exported because `HeraldService` stands the boss on it and nothing
-- should ever retype a coordinate -- that is how the invisible mountain happened.
HeraldStation.Centre = Vector3.new(-106, 0, 502)

-- The permanent ring. Comfortably inside the rig's own dais (57.8 studs across at u = 38) so the
-- two never fight for the same plane, and flush enough to walk over.
local RING_D = 52
local RING_TOP = 0.36
local RIM_TOP = 0.50
local MARK_COUNT = 8
local MARK_R = 30

-- The board stands EAST of the ring, between the Herald and the gate's approach, so a player
-- walking north out of the plaza reads it before the boss is on top of them. x -62 is clear of
-- `PortalMat` (x >= -17) by 45 studs.
local BOARD_OFFSET = Vector3.new(44, 0, -6)
local BOARD_W, BOARD_H = 36, 21
local POST_H = 13

local OUTLINE = Color3.fromRGB(26, 18, 36)
local STONE = Color3.fromRGB(150, 140, 132)
local STONE_DARK = Color3.fromRGB(104, 96, 92)

-- A local part vocabulary, for the reason `HubPlaza`, `SprintTrack` and `RebirthShrine` all give
-- for having their own: `ZoneBuilder` is thousands of lines behind a stamp that rebuilds the world.
-- This builds about twenty parts.
local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- Stated by its top face and grown down to a common buried bottom, so no two flush layers here can
-- ever share a horizontal plane with each other or with the lawn.
local function pave(model, name, centre, sx, sz, top, colour, round)
	local bottom = -1.2
	local thickness = top - bottom
	local p = newPart({
		Name = name,
		Size = Vector3.new(sx, thickness, sz),
		Position = Vector3.new(centre.X, top - thickness * 0.5, centre.Z),
		Color = colour,
		CanCollide = true,
		Parent = model,
	})
	if round then
		local mesh = Instance.new("CylinderMesh")
		mesh.Parent = p
	end
	return p
end

-- ============================================================================
-- THE BOARD
-- ============================================================================
-- Four contributor rows and no more, and that is a decision rather than a limit: a shared fight
-- has a top of the board and a long tail, and eight names at this size are unreadable from the
-- spawn. The tail is counted in the footer instead.
local ROW_COUNT = 4

local function styleText(label, colour)
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font.Display
	label.TextColor3 = colour or Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(14, 10, 22)
	label.TextStrokeTransparency = 0.15
	label.TextXAlignment = Enum.TextXAlignment.Left
end

local function buildBoard(model, centre, accent)
	local at = centre + BOARD_OFFSET
	newPart({
		Name = "BoardFoot", Size = Vector3.new(14, 1.4, 8),
		Position = Vector3.new(at.X, 0.7, at.Z), Color = OUTLINE, Parent = model,
	})
	for _, dx in ipairs({ -5, 5 }) do
		newPart({
			Name = "BoardPost", Size = Vector3.new(1.8, POST_H, 1.8),
			Position = Vector3.new(at.X + dx, POST_H * 0.5 + 1.2, at.Z), Color = OUTLINE, Parent = model,
		})
	end
	newPart({
		Name = "BoardBar", Size = Vector3.new(BOARD_W + 3, 1.6, 1.6),
		Position = Vector3.new(at.X, POST_H + BOARD_H + 0.8, at.Z),
		Color = OUTLINE, CanCollide = false, Parent = model,
	})
	-- An invisible anchor, exactly as the arena's countdown board uses: the panel is the board.
	local slab = newPart({
		Name = "BoardSlab", Size = Vector3.new(2, 2, 2),
		Position = Vector3.new(at.X, POST_H + BOARD_H * 0.5, at.Z),
		Transparency = 1, CanCollide = false, CanQuery = false, Parent = model,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "ContributionBoard"
	-- studs, not pixels: a pixel-sized board keeps its screen size at range, which is what makes
	-- this legible from the spawn pad and not a wall of text at the boss's feet
	gui.Size = UDim2.new(BOARD_W, 0, BOARD_H, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 520
	gui.Adornee = slab
	gui.Parent = slab

	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = Color3.fromRGB(24, 18, 30)
	shell.BackgroundTransparency = 0.08
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Thickness = 4
	stroke.Color = accent
	stroke.Parent = shell

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.94, 0.17)
	title.Position = UDim2.fromScale(0.03, 0.04)
	styleText(title, accent)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Text = "\u{2694}\u{FE0F} WORLD BOSS"
	title.Parent = shell

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.fromScale(0.94, 0.11)
	sub.Position = UDim2.fromScale(0.03, 0.22)
	styleText(sub, Color3.fromRGB(214, 208, 226))
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.Text = ""
	sub.Parent = shell

	-- The health bar is drawn as two frames rather than as text, because the one thing a player
	-- glancing at this from 170 studs can read at all is a bar getting shorter.
	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Size = UDim2.fromScale(0.94, 0.1)
	barBack.Position = UDim2.fromScale(0.03, 0.345)
	barBack.BackgroundColor3 = Color3.fromRGB(44, 36, 54)
	barBack.BorderSizePixel = 0
	barBack.Parent = shell
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBack

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = accent
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill

	local barLabel = Instance.new("TextLabel")
	barLabel.Name = "BarLabel"
	barLabel.Size = UDim2.fromScale(1, 1)
	styleText(barLabel, Color3.fromRGB(255, 255, 255))
	barLabel.TextXAlignment = Enum.TextXAlignment.Center
	barLabel.ZIndex = 3
	barLabel.Text = ""
	barLabel.Parent = barBack

	-- TWO LABELS PER ROW, not one padded string. `FredokaOne` is proportional, so "%-14s" aligns
	-- nothing at all -- the column has to be a second label pinned to the right edge.
	local rows = {}
	for i = 1, ROW_COUNT do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.fromScale(0.76, 0.105)
		row.Position = UDim2.fromScale(0.03, 0.47 + (i - 1) * 0.115)
		styleText(row, Color3.fromRGB(240, 236, 248))
		row.Text = ""
		row.Parent = shell

		local pct = Instance.new("TextLabel")
		pct.Name = "Pct"
		pct.Size = UDim2.fromScale(0.16, 1)
		pct.Position = UDim2.fromScale(1.02, 0)
		styleText(pct, accent)
		pct.TextXAlignment = Enum.TextXAlignment.Right
		pct.Text = ""
		pct.Parent = row

		rows[i] = { name = row, pct = pct }
	end

	local footer = Instance.new("TextLabel")
	footer.Name = "Footer"
	footer.Size = UDim2.fromScale(0.94, 0.1)
	footer.Position = UDim2.fromScale(0.03, 0.885)
	styleText(footer, Color3.fromRGB(178, 172, 196))
	footer.TextXAlignment = Enum.TextXAlignment.Center
	footer.Text = "everyone who lands a hit is paid in full"
	footer.Parent = shell

	return {
		gui = gui, shell = shell, edge = stroke, title = title, sub = sub,
		barBack = barBack, barFill = barFill, barLabel = barLabel,
		rows = rows, footer = footer,
	}
end

-- ============================================================================
-- BUILD
-- ============================================================================
-- Idempotent BY REPLACEMENT and not by skipping, for the reason `SprintTrack` states: a
-- half-built station from an interrupted run would otherwise survive for ever behind an
-- "already there" check.
function HeraldStation.Ensure()
	local existing = workspace:FindFirstChild(MODEL_NAME)
	if existing and existing:GetAttribute("StationVersion") == STATION_VERSION then
		local slab = existing:FindFirstChild("BoardSlab")
		local gui = slab and slab:FindFirstChild("ContributionBoard")
		local shell = gui and gui:FindFirstChild("Shell")
		if shell then
			local rows = {}
			for i = 1, ROW_COUNT do
				local row = shell:FindFirstChild("Row" .. i)
				rows[i] = row and { name = row, pct = row:FindFirstChild("Pct") } or nil
			end
			return {
				model = existing, centre = HeraldStation.Centre,
				board = {
					gui = gui, shell = shell, edge = shell:FindFirstChild("Edge"),
					title = shell:FindFirstChild("Title"), sub = shell:FindFirstChild("Sub"),
					barBack = shell:FindFirstChild("BarBack"),
					barFill = shell.BarBack and shell.BarBack:FindFirstChild("BarFill"),
					barLabel = shell.BarBack and shell.BarBack:FindFirstChild("BarLabel"),
					rows = rows, footer = shell:FindFirstChild("Footer"),
				},
			}
		end
	end
	if existing then existing:Destroy() end

	local accent = GameConfig.EventArena.accentColor
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("StationVersion", STATION_VERSION)

	local centre = HeraldStation.Centre
	pave(model, "HeraldRing", centre, RING_D + 6, RING_D + 6, RING_TOP, STONE_DARK, true)
	pave(model, "HeraldFloor", centre, RING_D, RING_D, RIM_TOP, STONE, true)
	for i = 1, MARK_COUNT do
		local a = (i - 1) / MARK_COUNT * math.pi * 2
		newPart({
			Name = "HeraldMark",
			Size = Vector3.new(3.2, 2.4, 3.2),
			Position = centre + Vector3.new(math.cos(a) * MARK_R, 1.0, math.sin(a) * MARK_R),
			Color = OUTLINE, CanCollide = true, Parent = model,
		})
	end

	local board = buildBoard(model, centre, accent)
	model.Parent = workspace
	-- Persistent for the reason the plaza and the track are: this stands in the arrival zone, and
	-- a board that streams out is a board that is not there when the boss arrives.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	CollectionService:AddTag(model, "HeraldStation")

	return { model = model, centre = centre, board = board }
end

HeraldStation.RowCount = ROW_COUNT
HeraldStation.Version = STATION_VERSION

return HeraldStation
