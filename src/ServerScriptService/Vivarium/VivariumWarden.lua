--[==[
	VivariumWarden -- the one place a player raises or lowers their raid shield (24.5).

	===== WHY A STAND, AND WHY IT TAKES THE GALLERY'S FIRST ANCHOR =====

	The opt-out needs a control, and the two obvious homes are both closed. A HUD toggle is out:
	`MainUI` is at its 200-local cap (`evolution-lab-mainui-register-limit`). A prompt on every case
	is out too: `ActionText` belongs to the PART, so every case in the aisle would offer every
	passer-by a shield switch that only works for one of them, on a fourth key beside E / F / R.

	So it is ONE stand, 22.5's `PartyStand` shape -- a prompt everybody can press, with the answer
	said back per player through `Notify` -- and an agent can press a `ProximityPrompt`, so the row
	is verifiable solo. It stands on the gallery anchor NEAREST THE SPAWN: honest ground measured by
	the same test every case passes, a case's footprint exactly, and the first slot a player arriving
	can see with nothing in front of it. The plaza lays out one anchor more than it has cases and
	hands that one over. (It was anchor 1 first -- the far west end, backed by forest with a case at
	its shoulder -- and the photographs are what moved it.)
]==]

local RS = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = RS.Remotes
local UITheme = require(RS.Modules.UITheme)
local Telemetry = require(ServerScriptService.Telemetry)
local VivariumCase = require(script.Parent.VivariumCase)
local VivariumGuard = require(script.Parent.VivariumGuard)

local VivariumWarden = {}

local PAD_W, PAD_D = VivariumCase.Width, VivariumCase.Depth
local PAD_TOP = VivariumCase.PadTop
local PLINTH_H = 3.2
-- ===== THE BOARD STANDS ABOVE EVERY CASE'S, AND A PHOTOGRAPH IS WHY =====
-- The first build hung it at y 15.8 on 10-stud posts: every probe passed, and the capture from the
-- aisle showed four letters of it peeking out from behind the neighbouring case, whose 16.4-stud
-- walls stand ten studs away and exactly as tall as the board. It has to clear the case board rung
-- (`VivariumCase` BOARD_Y 23.54, top 26.04), so the posts carry it to a centre of 29.0 and a bottom
-- of 26.7 -- which settles the height, and moving the stand to the spawn end settles the rest.
local POST_H = 23.2
local BOARD_W, BOARD_H = 9, 4.6
local PROMPT_DISTANCE = 22
local PROMPT_HEIGHT = 6

local OUTLINE = Color3.fromRGB(26, 22, 42)
local STONE = Color3.fromRGB(178, 152, 116)
local SHIELD = Color3.fromRGB(120, 190, 255)

local hooks = nil
local prompt = nil

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

local function line(parent, name, text, colour, y, h)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromScale(0.92, h)
	label.Position = UDim2.fromScale(0.04, y)
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font.Display
	label.TextColor3 = colour
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(14, 10, 22)
	label.TextStrokeTransparency = 0.15
	label.Text = text
	label.Parent = parent
	return label
end

--- The press, and the entry point a probe drives. Answers the presser either way.
function VivariumWarden.Press(player)
	local busy = hooks and hooks.busy and hooks.busy(player) or false
	local ok, message, code = VivariumGuard.ToggleShield(player, busy)
	Remotes.Notify:FireClient(player, { kind = ok and "party" or "error", message = message })
	if ok then
		if hooks and hooks.redraw then hooks.redraw(player.UserId) end
		Telemetry.Custom(player, "VivariumShield", code == "raised" and 1 or 0)
	end
	return ok, code
end

--- Stand the Warden at `frame` (a case anchor: open front is -Z) under `parent`.
--- `h.busy(player) -> bool` and `h.redraw(userId)` are the plaza's, passed in rather than required
--- because the plaza requires this file.
function VivariumWarden.Build(frame, parent, h)
	hooks = h
	local function at(x, y, z)
		return frame * CFrame.new(x, y, z)
	end

	local model = Instance.new("Model")
	model.Name = "RaidWarden"

	newPart({
		Name = "WardenPad", Size = Vector3.new(PAD_W, PAD_TOP + 1.2, PAD_D),
		CFrame = at(0, PAD_TOP - (PAD_TOP + 1.2) * 0.5, 0),
		Color = STONE, CanCollide = true, Parent = model,
	})
	local plinth = newPart({
		Name = "WardenPlinth", Size = Vector3.new(5, PLINTH_H, 4),
		CFrame = at(0, PAD_TOP + PLINTH_H * 0.5, 0),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	newPart({
		Name = "WardenCrest", Size = Vector3.new(3.2, 0.5, 2.4),
		CFrame = at(0, PAD_TOP + PLINTH_H + 0.25, 0),
		Color = SHIELD, Material = Enum.Material.Neon, CanCollide = false, Parent = model,
	})
	for _, dx in ipairs({ -3.6, 3.6 }) do
		newPart({
			Name = "BoardPost", Size = Vector3.new(0.9, POST_H, 0.9),
			CFrame = at(dx, PAD_TOP + PLINTH_H + POST_H * 0.5, 1.2),
			Color = OUTLINE, CanCollide = true, Parent = model,
		})
	end
	-- The panel hangs over the posts with nothing solid behind it: a BillboardGui turns to the
	-- camera and a slab does not (`roblox-billboard-and-its-backing-board`).
	local anchor = newPart({
		Name = "BoardAnchor", Size = Vector3.new(1, 1, 1),
		CFrame = at(0, PAD_TOP + PLINTH_H + POST_H + BOARD_H * 0.5, 1.2),
		Transparency = 1, CanCollide = false, CanQuery = false, Parent = model,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "WardenBoard"
	gui.Size = UDim2.new(BOARD_W, 0, BOARD_H, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Adornee = anchor
	gui.Parent = anchor

	local shell = Instance.new("Frame")
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = Color3.fromRGB(20, 17, 28)
	shell.BackgroundTransparency = 0.08
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = SHIELD
	stroke.Parent = shell

	local pct = math.floor(VivariumGuard.Bonus * 100 + 0.5)
	line(shell, "Title", "\u{1F6E1}\u{FE0F} RAID WARDEN", SHIELD, 0.06, 0.24)
	line(shell, "Bonus", ("Contested cases earn +%d%% passive DNA"):format(pct),
		Color3.fromRGB(240, 238, 250), 0.36, 0.16)
	line(shell, "Shield", ("Shield up: safe from raids \u{00B7} no raiding \u{00B7} no +%d%%"):format(pct),
		Color3.fromRGB(212, 208, 226), 0.55, 0.14)
	line(shell, "Rule", ("Press E to switch \u{00B7} once every %dm"):format(VivariumGuard.ShieldSwitch // 60),
		Color3.fromRGB(170, 166, 190), 0.74, 0.13)

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WardenPrompt"
	prompt.ObjectText = "Raid Warden"
	prompt.ActionText = "Raise or lower your shield"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	local promptAt = Instance.new("Attachment")
	promptAt.Name = "PromptAnchor"
	promptAt.Position = Vector3.new(0, PROMPT_HEIGHT - PLINTH_H * 0.5, 0)
	promptAt.Parent = plinth
	prompt.Parent = promptAt
	prompt.Triggered:Connect(function(player)
		VivariumWarden.Press(player)
	end)

	model.Parent = parent
	return model
end

return VivariumWarden
