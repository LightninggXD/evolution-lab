-- ChestReveal -- a chest the player presses on a screen, and the burst when it opens (34.54).
--
-- ===== WHY THIS EXISTS AT ALL, GIVEN THE GRANT WAS ALREADY RIGHT =====
--
-- The owner, over the lucky wheel: *"i na weelu isto kad stane na relic opciju nek player otvori
-- chest pa koji relic dobije"*. The row was opened believing the wheel handed over a relic directly
-- and needed re-plumbing onto the chest roll. It does not -- `GameConfig.SpinWheel`'s `relic` wedge
-- has always banked an UNOPENED chest through `RelicService.GiveChest`, and 34.55 made a banked
-- chest one of the only two doors a relic can come through. So the GRANT was already exactly what
-- she asked for.
--
-- What was missing is the half the sentence is actually about: *seeing* a chest and opening it. The
-- wheel landed on a purple pod and printed **"1 Relic Chest -- open it in the Forge"**, which is a
-- homework assignment, not a prize. This file is the chest.
--
-- ===== WHAT IT OWNS: PIXELS. NOTHING ELSE =====
--
-- No remote, no roll, no table, no currency, and it never learns what the relic was. It draws a
-- chest, it shakes it when told, and it calls back when the player presses OPEN. `SpinLobby` states
-- the same rule about itself -- *"It never touches a remote itself: the shell owns the remotes, this
-- owns the pixels"* -- and it is worth more here than there, because the thing on the other side of
-- this button is a ROLL. A client that could open a chest is a client that could open two.
--
-- THE SERVER DECIDES THE PRIZE AND THE SERVER NAMES IT. The caller shows the relic afterwards from
-- the server's own `Notify` payload; nothing in here composes a prize string, for the reason
-- `ChestService` states over its own `tell`: two writers naming one prize is how one of them ends
-- up wrong.
--
-- ===== THE ART IS HERS, AND IT IS FLAT =====
--
-- `GameConfig.RelicChestIcon` is the decal the owner inserted for 34.58. It is 2D -- measured, not
-- assumed: both halves of what she parked in `Workspace["coin chest"]` are Decals and there is no
-- Model. So there is no lid to hinge here the way `ChestService` hinges one in the world, and the
-- open cannot be a lid lifting. It is a SHAKE that builds, then a flash, rays, and the chest
-- blowing up and out of frame -- an animation that cannot look wrong on a single flat image,
-- which is the same reasoning `ChestService`'s POP fallback is built on.
--
-- A missing id draws the gift glyph through `IconLibrary` rather than an empty `ImageLabel`: an
-- unmapped image is a HOLE, and a hole in the middle of the screen reads as a broken game
-- ([[evolution-lab-icon-system]]).

local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local GameConfig = require(RS.Modules.GameConfig)
local IconLibrary = require(RS.Modules.IconLibrary)
local CardKit = require(RS.Modules.HUD.CardKit)

local ChestReveal = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local CREAM = Color3.fromRGB(255, 240, 205)
local GOLD = Color3.fromRGB(255, 226, 120)

-- Gold, the same pair the Relics panel's own OPEN CHEST button wears, so pressing a chest is one
-- colour wherever the chest is standing.
local OPEN_COLORS = { Color3.fromRGB(255, 246, 190), Color3.fromRGB(238, 176, 30) }
local LATER_COLORS = { Color3.fromRGB(150, 154, 172), Color3.fromRGB(96, 100, 120) }

-- The stage is a RelativeYY square so the chest is the same size on a phone in portrait as on a
-- 1440p window -- the rule the wheel's own stage follows. 0.34 rather than the wheel's 0.60 because
-- this is drawn OVER the wheel and has to read as a thing standing in front of it.
local STAGE_SCALE = 0.34

-- ============================================================================
-- BUILD
-- ============================================================================
--
-- `parent` is a ScreenGui (or any full-screen frame). `opts`:
--
--     zIndex      the band this whole overlay sits in; every child is z .. z+5
--     title       the line over the chest
--     hint        the line under it
--     openText    the caption on the action button ("OPEN")
--     locked      draw the chest as banked-but-unopenable, with no action button
--     onOpen      pressed OPEN
--     onSkip      pressed LATER, or the caller's own dismiss
--
-- Returns a handle. Nothing here yields except `PlayOpen`.
function ChestReveal.Build(parent, opts)
	opts = opts or {}
	local z = opts.zIndex or 60

	local root = Instance.new("Frame")
	root.Name = "ChestReveal"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = z
	root.Parent = parent

	-- ===== THE VEIL IS NEARLY SOLID, AND THAT IS A LAYOUT DECISION, NOT A MOOD =====
	--
	-- This overlay is drawn over the lucky wheel's lobby, and that lobby is not empty underneath: its
	-- status plate sits at y 0.825 and its 72 px control row at 0.930, which is exactly where a chest
	-- with a caption and two buttons wants to be. A 35% wash left "Spins : 0" and four Robux packs
	-- legible THROUGH the OPEN button. The alternative -- teaching `SpinLobby` to hide itself -- is a
	-- new API on a file that has one job, for one caller. At 0.05 the panel behind is simply gone and
	-- the chest is the whole screen, which is also the better beat.
	--
	-- 0.35 -> 0.12 -> 0.05, and the last step was MEASURED off the first live capture rather than
	-- chosen. At 0.12 the row underneath was still legible -- "SPINNING", "+2 Spins  R$99", and
	-- worst of all the lobby's own leftover detail line, which reads *"open it in the Relics panel"*
	-- directly behind an OPEN button. A sentence sending the player somewhere else, printed under
	-- the button that does the thing right here, is the exact confusion this row exists to remove.
	--
	-- `Active = true` IS THE OTHER HALF AND IT IS THE LOAD-BEARING ONE. A Roblox Frame does not eat
	-- input unless it is Active, so without this the lobby's SPIN button, its four packs and the
	-- wheel's own close X are all still pressable through an opaque black sheet. Two of those three
	-- are already guarded by the shell's busy flag; the third would close the wheel out from under a
	-- chest the player is holding.
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.fromRGB(8, 6, 18)
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.Active = true
	veil.ZIndex = z
	veil.Parent = root
	TweenService:Create(veil, TweenInfo.new(0.28), { BackgroundTransparency = 0.05 }):Play()

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.44)
	stage.Size = UDim2.fromScale(STAGE_SCALE, STAGE_SCALE)
	stage.SizeConstraint = Enum.SizeConstraint.RelativeYY
	stage.BackgroundTransparency = 1
	stage.ZIndex = z + 1
	stage.Parent = root

	-- ONE UIScale FOR THE WHOLE STAGE. The entrance, the shake's pulse and the burst's kick all
	-- write this one property rather than each tweening the chest's Size -- which is how a piece
	-- ends up half a frame out of step with the rays behind it.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.35
	scale.Parent = stage

	-- ===== THE RAYS =====
	-- Built dark and invisible, revealed by `PlayOpen`. Built ONCE rather than per open, the rule
	-- `ChestService` pays for in the world: an emitter created per press is how a prop ends up with
	-- forty of them.
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromScale(1.7, 1.7)
	rays.BackgroundTransparency = 1
	rays.Visible = false
	rays.ZIndex = z + 1
	rays.Parent = stage

	local rayBars = {}
	for i = 1, 14 do
		local reach = (i % 2 == 0) and 1.25 or 0.95
		local ray = Instance.new("Frame")
		ray.Name = "Ray" .. i
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(reach, 0.05)
		ray.Rotation = (i - 1) * (360 / 14)
		ray.BackgroundColor3 = GOLD
		ray.BackgroundTransparency = 0.3
		ray.BorderSizePixel = 0
		ray.ZIndex = z + 1
		ray.Parent = rays
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ray
		-- Faded at both ends so a ray reads as light rather than as a gold stick.
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
		-- THE REACH IS CARRIED, NOT RE-DERIVED. `PlayOpen` grows every ray out of the middle and has to
		-- put it back to the length it was authored at; reading that back off the instance's name is
		-- the kind of trick that works until a ray is renamed.
		rayBars[#rayBars + 1] = { bar = ray, reach = reach }
	end

	-- ===== THE CHEST =====
	local chest
	local image = GameConfig.RelicChestIcon
	if type(image) == "string" and image ~= "" then
		chest = Instance.new("ImageLabel")
		chest.Image = image
		chest.ScaleType = Enum.ScaleType.Fit
		chest.BackgroundTransparency = 1
	else
		-- The fallback is a GLYPH, not an empty ImageLabel. See the header.
		chest = Instance.new("TextLabel")
		chest.BackgroundTransparency = 1
		chest.Text = "\u{1F381}"
		chest.Font = Enum.Font.FredokaOne
		chest.TextScaled = true
		chest.TextColor3 = WHITE
		local resolved = IconLibrary.Resolve("\u{1F381}")
		if resolved then
			chest:Destroy()
			chest = Instance.new("ImageLabel")
			chest.Image = resolved
			chest.ScaleType = Enum.ScaleType.Fit
			chest.BackgroundTransparency = 1
		end
	end
	chest.Name = "Chest"
	chest.AnchorPoint = Vector2.new(0.5, 0.5)
	chest.Position = UDim2.fromScale(0.5, 0.5)
	chest.Size = UDim2.fromScale(0.9, 0.9)
	chest.ZIndex = z + 3
	chest.Parent = stage

	-- ===== THE TWO LINES =====
	-- Above and below the stage rather than inside it: the stage is square and scaled by RelativeYY,
	-- so text parented into it would grow and shrink with the aspect ratio instead of staying at a
	-- readable pixel size.
	local title = CardKit.Text(root, {
		name = "Title",
		text = opts.title or "RELIC CHEST",
		size = UDim2.new(1, -40, 0, 46),
		position = UDim2.fromScale(0.5, 0.185),
		textSize = 38,
		color = GOLD,
		xAlign = "Center",
		zIndex = z + 4,
		strokeThickness = 4,
		truncate = false,
	})
	title.AnchorPoint = Vector2.new(0.5, 0.5)

	local hint = CardKit.Text(root, {
		name = "Hint",
		text = opts.hint or "Open it!",
		size = UDim2.new(1, -40, 0, 30),
		position = UDim2.fromScale(0.5, 0.70),
		textSize = 24,
		color = CREAM,
		xAlign = "Center",
		zIndex = z + 4,
		strokeThickness = 4,
		truncate = false,
	})
	hint.AnchorPoint = Vector2.new(0.5, 0.5)

	-- ===== THE BUTTONS =====
	--
	-- THE CHEST ITSELF IS NOT THE BUTTON, and that is deliberate. A press target with no caption is a
	-- press target a player has to guess at, and this screen appears at most once every twenty spins
	-- -- there is no habit to lean on. The chest is the picture; the word OPEN is the affordance.
	local row = Instance.new("Frame")
	row.Name = "Actions"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.815)
	row.Size = UDim2.new(0, 420, 0, 68)
	row.BackgroundTransparency = 1
	row.ZIndex = z + 4
	row.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = row

	local openHandle
	if not opts.locked then
		local _, h = CardKit.Button(row, {
			name = "Open",
			text = opts.openText or "OPEN",
			size = UDim2.new(0, 236, 0, 68),
			layoutOrder = 1,
			textSize = 34,
			radius = 14,
			zIndex = z + 5,
			colors = OPEN_COLORS,
			callback = function()
				if opts.onOpen then opts.onOpen() end
			end,
		})
		openHandle = h
	end

	-- LATER IS ALWAYS DRAWN, INCLUDING WHEN THE CHEST CANNOT BE OPENED. A reveal with no way out is a
	-- reveal that traps a player who wants to keep spinning, and the chest is banked either way --
	-- walking away from this screen costs nothing at all, which the hint says out loud.
	local _, laterHandle = CardKit.Button(row, {
		name = "Later",
		text = opts.locked and "OK" or "LATER",
		size = UDim2.new(0, opts.locked and 236 or 148, 0, 68),
		layoutOrder = 2,
		textSize = opts.locked and 34 or 26,
		radius = 14,
		zIndex = z + 5,
		colors = LATER_COLORS,
		callback = function()
			if opts.onSkip then opts.onSkip() end
		end,
	})

	-- ===== THE IDLE BOB =====
	--
	-- A chest that stands perfectly still reads as a picture of a chest. This is one sine on the
	-- stage's own Position, ~2 px of travel at a typical viewport, and it is DISCONNECTED in
	-- `Destroy` -- a Heartbeat left running against a destroyed frame is the leak this panel would
	-- otherwise open every twenty spins for the rest of the session.
	local baseY = 0.44
	local bobbing = true
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not bobbing or not stage.Parent then return end
		local t = os.clock()
		stage.Position = UDim2.fromScale(0.5, baseY + math.sin(t * 2.2) * 0.008)
		chest.Rotation = math.sin(t * 1.5) * 1.6
	end)

	TweenService:Create(scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()

	local handle = { Instance = root }
	local opened = false

	function handle.SetHint(text)
		hint.Text = tostring(text or "")
	end

	function handle.SetBusy(on)
		if openHandle then openHandle.SetEnabled(not on) end
		laterHandle.SetEnabled(not on)
	end

	-- ===== THE OPEN =====
	--
	-- YIELDS, and the caller is meant to wait on it: the burst is the beat between pressing the chest
	-- and being told what was in it, and playing it in a spawned thread would let the prize line
	-- appear over a chest that has not moved yet.
	--
	-- Three shakes that get faster and wider, then the chest goes. `Rotation` and `UIScale` only --
	-- nothing here writes Size or Position on the image, so the animation is identical whatever the
	-- art turns out to be, including the emoji fallback.
	function handle.PlayOpen()
		if opened then return end
		opened = true
		bobbing = false
		handle.SetBusy(true)

		for i = 1, 3 do
			local amp = 4 + i * 3
			local step = 0.16 - i * 0.03
			for _, angle in ipairs({ -amp, amp, 0 }) do
				chest.Rotation = angle
				scale.Scale = 1 + i * 0.03
				task.wait(step / 3)
			end
		end
		chest.Rotation = 0

		rays.Visible = true
		for _, entry in ipairs(rayBars) do
			entry.bar.BackgroundTransparency = 0.3
			entry.bar.Size = UDim2.fromScale(0.2, 0.05)
			TweenService:Create(entry.bar,
				TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(entry.reach, 0.05) }):Play()
		end

		-- The flash is a white frame over the whole overlay for a fifth of a second. It is what makes
		-- the chest look like it BURST rather than like it faded.
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = WHITE
		flash.BackgroundTransparency = 0.25
		flash.BorderSizePixel = 0
		flash.ZIndex = z + 4
		flash.Parent = root
		TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()

		TweenService:Create(scale, TweenInfo.new(0.30, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.45 }):Play()
		if chest:IsA("ImageLabel") then
			TweenService:Create(chest, TweenInfo.new(0.34), { ImageTransparency = 1 }):Play()
		else
			TweenService:Create(chest, TweenInfo.new(0.34), { TextTransparency = 1 }):Play()
		end

		task.wait(0.40)
		if flash.Parent then flash:Destroy() end
	end

	function handle.Destroy()
		bobbing = false
		if conn and conn.Connected then conn:Disconnect() end
		if not root.Parent then return end
		TweenService:Create(veil, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.20), { Scale = 0.35 }):Play()
		local dying = root
		task.delay(0.24, function()
			if dying and dying.Parent then dying:Destroy() end
		end)
	end

	return handle
end

return ChestReveal
