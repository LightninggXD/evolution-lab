-- ============================================================================
-- EVOLVE REVEAL -- the card that pops up showing WHAT you just became.
-- ============================================================================
-- Evolving used to print one line of toast in the corner. It is the single biggest moment in the
-- game -- twenty of them in a run, each one gated behind a full XP bar -- and the player never
-- actually saw the thing they had turned into, because their own camera is behind their own back.
--
-- WHY THIS IS ITS OWN SCRIPT AND NOT PART OF MainUI:
-- MainUI is at Luau's 200-register cap. One more top-level local in that file and the ENTIRE HUD
-- stops compiling -- see the note at the top of it. A RemoteEvent supports any number of
-- OnClientEvent connections, so this listens to the same `Notify` alongside MainUI and neither
-- knows about the other.
--
-- WHY A ViewportFrame AND NOT A REAL MODEL IN THE WORLD:
-- A clone parented into Workspace in front of the camera has to be anchored, streamed, kept out of
-- collisions and cleaned up if the player dies mid-animation. A ViewportFrame renders a private
-- scene with none of that. The one thing it costs is the Highlight -- ViewportFrames do not render
-- them -- so the dark rim the costume normally wears is missing here. That is paid back with a
-- bright rim light and a burst behind the figure, which is what carries the silhouette instead.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local Remotes = RS:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HOLD = 2.6            -- seconds the card stays up once it has finished popping in
local RAYS = 12
local INK = Color3.fromRGB(28, 20, 44)

-- One at a time. Two evolves in quick succession (which a stockpiled player can absolutely do)
-- would otherwise stack two full-screen overlays and leave the second one's fade fighting the
-- first one's cleanup.
local active = nil

-- THE BLUR IS NOT DECORATION -- it is what makes the reveal readable at all.
-- Dimming alone leaves the player's own character standing a few studs from a third-person camera,
-- dead centre and dark, exactly where the figure being revealed is drawn. The two silhouettes
-- overlap and neither one is legible. Throwing the world out of focus separates them, and it is
-- also what the reference does.
--
-- ONE instance, created once and reused, never one per reveal: a BlurEffect left behind by a
-- reveal that was interrupted is a permanently out-of-focus game, and that is a bug the player
-- cannot get out of without rejoining.
local blur = Instance.new("BlurEffect")
blur.Name = "EvolveRevealBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local function stroke(inst, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or INK
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

-- CharacterPreview is required LAZILY, not at the top of this file. Its module body does
-- `RS:WaitForChild("Assets"):WaitForChild("PreviewRig", 20)`, so requiring it up here would yield
-- this script for up to twenty seconds before the OnClientEvent connection at the BOTTOM of the
-- file exists -- and an evolve that lands inside that window is a reveal that never appears at all.
-- Resolved once on first use and remembered, including the failure, so a place with no PreviewRig
-- pays the pcall once rather than on every evolve.
local previewModule = nil
local function characterPreview()
	if previewModule == nil then
		local ok, mod = pcall(require, RS.Modules.CharacterPreview)
		previewModule = ok and mod or false
		if not ok then warn("[EvolveReveal] CharacterPreview: " .. tostring(mod)) end
	end
	return previewModule or nil
end

-- THE FIGURE IS THE STAGE, NOT THE PLAYER -- and that is a correction, not a preference.
--
-- This card used to be built from a clone of the player's live character, on the reasoning that a
-- clone is literally what they now look like and so can never drift out of step with StageCostume.
-- That reasoning stopped holding the day a skin became something you WEAR rather than something
-- your stage decides: EvolutionVisuals takes the LOOK from the globally worn character
-- (`lookIndex = entry.stage`) and the SIZE from the stage you just reached, so a player wearing a
-- Wolf who evolves into a Worm is still, correctly, a wolf-shaped body. The notification says
-- "New Worm Discovered!" because that is the stage that was unlocked -- and the clone underneath it
-- was a grey wolf. Two true statements that read as one broken card.
--
-- The caption is the thing that cannot move: it is the reward, and it names a stage. So the figure
-- is built from the stage instead, by exactly the path the Journal already uses for its cells --
-- same stand-in rig, same StageCostume build, same anchored/no-welds/no-Highlight cleanup a
-- ViewportFrame needs. `entry` is nil on purpose: the five characters of a stage are variants of
-- it, and the stage's own default look is the one the stage's own name belongs to.
-- `entry` is the CHARACTER that was just earned, when there was one. It is passed straight through
-- to CharacterPreview, which builds that exact skin rather than the stage's default look.
--
-- WHY THE CHARACTER AND NOT THE STAGE. Unlocks fill the collection in strict order, so the stage
-- you evolved INTO and the skin you were handed are routinely different -- reach Gorilla while the
-- collection is still working through Wolf and the stage figure would be a Gorilla drawn over a
-- player wearing a Wolf. The card has to show what is now on the body. `entry` nil means the
-- collection is complete and there was nothing to earn, and the stage's own look is then correct.
local function stageFigure(parent, stageIndex, entry)
	local CharacterPreview = characterPreview()
	if not (CharacterPreview and stageIndex) then return nil end
	local ok, rig = pcall(CharacterPreview.Build, parent, stageIndex, entry)
	if not ok then
		warn("[EvolveReveal] stage figure: " .. tostring(rig))
		return nil
	end
	return rig
end

-- The fallback, and only the fallback: a clone of the player's OWN character. Kept because a
-- missing PreviewRig or a stage index that does not resolve should cost the card its accuracy, not
-- its existence.
local function snapshotCharacter()
	local character = player.Character
	if not (character and character:FindFirstChild("HumanoidRootPart")) then return nil end

	local clone = Instance.new("Model")
	clone.Name = "RevealFigure"
	-- Copied part by part rather than character:Clone(): a character carries Humanoid, Animator,
	-- Animate, Sound and the whole control stack, all of which would try to RUN inside the viewport.
	-- Welds come too, because the costume shells are welded on and without them every limb would
	-- render at the origin in a heap.
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Archivable then
			local p = d:Clone()
			p:ClearAllChildren() -- decals stay, scripts and emitters do not
			for _, k in ipairs(d:GetChildren()) do
				if k:IsA("Decal") or k:IsA("Texture") or k:IsA("SpecialMesh") then
					k:Clone().Parent = p
				end
			end
			p.Anchored = true
			p.CanCollide = false
			p.Massless = true
			p.Parent = clone
		end
	end
	if #clone:GetChildren() == 0 then
		clone:Destroy()
		return nil
	end
	return clone
end

local function show(stageName, emoji, color, stageIndex, entry)
	if active then
		active:Destroy()
		active = nil
	end

	-- Built into an UNPARENTED WorldModel and hung off the ViewportFrame further down, rather than
	-- the other way round. Both builders refuse a character with no parent (every piece they make is
	-- created straight into a folder under it), so the figure needs a container before the card that
	-- will hold it exists -- and if nothing can be built there is then no half-made viewport to undo.
	local world = Instance.new("WorldModel")
	local figure = stageFigure(world, stageIndex, entry)
	if not figure then
		figure = snapshotCharacter()
		if figure then figure.Parent = world end
	end

	if figure then
		-- FULLY OPAQUE, EXPLICITLY. Transparency comes across from the build itself and is left alone
		-- -- several stages have deliberately translucent pieces and flattening those would be a
		-- different bug -- but LocalTransparencyModifier is set to zero on every part of the copy.
		-- It is not a serialised property, so a clone should arrive at 0 anyway; "should" is doing a
		-- lot of work in a file whose other half exists to write that property every frame, and the
		-- snapshot route in particular clones parts off a live character that a previous reveal may
		-- still have been holding at 1 when this one destroyed it.
		for _, d in ipairs(figure:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
	else
		world:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "EvolveReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90 -- over the HUD, under nothing
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	active = gui

	-- the dim. Not opaque: the reference keeps the world visible behind the reveal, which is what
	-- makes it read as something happening IN the world rather than as a menu opening.
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = INK
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 1
	dim.Parent = gui

	-- everything else lives in one square that is scaled as a unit for the pop -- scaling a dozen
	-- separate elements in step is how you get them drifting apart by a pixel each
	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.46)
	stage.Size = UDim2.fromScale(0.52, 0.72)
	stage.SizeConstraint = Enum.SizeConstraint.RelativeYY
	stage.BackgroundTransparency = 1
	stage.ZIndex = 2
	stage.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = stage

	-- ---- the burst behind the figure: a fan of tapered rays plus a soft core. Built from Frames
	-- rotated about the centre, because a radial gradient is the one thing Roblox UI cannot draw.
	local burst = Instance.new("Frame")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.46)
	burst.Size = UDim2.fromScale(1, 1)
	burst.BackgroundTransparency = 1
	burst.ZIndex = 2
	burst.Parent = stage

	for i = 1, RAYS do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		-- alternating lengths, so the fan reads as a starburst and not as a gear
		ray.Size = UDim2.fromScale(i % 2 == 0 and 1.25 or 0.9, 0.045)
		ray.Rotation = (i - 1) * (360 / RAYS)
		ray.BackgroundColor3 = i % 3 == 0 and UITheme.Color.White or color
		ray.BackgroundTransparency = 0.35
		ray.BorderSizePixel = 0
		ray.ZIndex = 2
		ray.Parent = burst
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ray
		-- fade both ends, so a ray is a beam of light and not a painted spoke
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
	end

	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.62, 0.62)
	core.BackgroundColor3 = color
	core.BackgroundTransparency = 0.62
	core.BorderSizePixel = 0
	core.ZIndex = 2
	core.Parent = burst
	local coreCorner = Instance.new("UICorner")
	coreCorner.CornerRadius = UDim.new(1, 0)
	coreCorner.Parent = core

	-- ---- the figure itself
	if figure then
		local vp = Instance.new("ViewportFrame")
		vp.AnchorPoint = Vector2.new(0.5, 0.5)
		vp.Position = UDim2.fromScale(0.5, 0.44)
		vp.Size = UDim2.fromScale(1, 1)
		vp.BackgroundTransparency = 1
		vp.ZIndex = 3
		-- A ViewportFrame is lit only by these two properties -- it does not see the place's
		-- Lighting at all. Left at the defaults the figure comes out near-black, which is how you
		-- get a silhouette-shaped hole in the middle of a bright reveal.
		-- It WAS pushed nearly to white (238) because several stages are near-black by design (Void
		-- Sovereign, Primordial Force) and at a room-like ambient they came out as a hole in the middle
		-- of the card. That over-corrected. Ambient is flat fill with no direction in it, so at 238 it
		-- swamps the key light and every figure renders pale and unshaded -- which is what "washed out"
		-- meant in the report, and a body with no shading on it reads as insubstantial in exactly the
		-- way a semi-transparent one does.
		--
		-- 210 rather than another guess: the Journal draws the SAME near-black stages through
		-- CharacterPreview.Light at an ambient of 188 and they are legible there, so the floor that
		-- keeps a dark stage off the black is well below this. Staying above the Journal's value keeps
		-- the product-shot feel a reward card wants and gives the key light its shaping back.
		vp.Ambient = Color3.fromRGB(210, 212, 222)
		vp.LightColor = Color3.fromRGB(255, 252, 244)
		vp.LightDirection = Vector3.new(-0.4, -0.7, -1)
		vp.Parent = stage

		world.Parent = vp

		local cam = Instance.new("Camera")
		-- A LONG LENS, not a wide one. At 40 degrees the near shoulder bulges toward the camera and
		-- the figure reads as a fish-eye photo; 30 flattens it into the poster-like portrait the
		-- reference uses, and it costs nothing because the distance is derived from the FOV below.
		cam.FieldOfView = 30
		cam.Parent = vp
		vp.CurrentCamera = cam

		-- Framed off the model's own bounding box, NOT off a fixed distance. The body scales 1x to 9x
		-- across the twenty stages -- a camera parked at a constant range shows a speck at Cell and
		-- the inside of a kneecap at the Absolute.
		--
		-- The 2.4 is headroom, and it is what stops the figure eating the burst behind it: at 1.5 the
		-- body filled two thirds of the viewport's height, which is the whole width of the ray fan, so
		-- the rays only ever peeked out at the corners. Framed at 2.4 the figure sits inside the fan
		-- with the rays radiating past it, which is the shape of the reference.
		local cf, size = figure:GetBoundingBox()
		local reach = math.max(size.X, size.Y, size.Z)
		local dist = reach / (2 * math.tan(math.rad(cam.FieldOfView / 2))) * 1.95
		local focus = cf.Position

		-- a slow turn, so the figure is read in the round rather than as a photograph
		local spin = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not vp.Parent then
				conn:Disconnect()
				return
			end
			spin += dt * 0.55
			cam.CFrame = CFrame.new(focus) * CFrame.Angles(0, spin, 0)
				* CFrame.new(0, reach * 0.06, dist)
			cam.CFrame = CFrame.lookAt(cam.CFrame.Position, focus)
		end)
	end

	-- ---- the caption. Two lines, exactly like the reference: the creature's own name, and the
	-- sentence that tells you it is new. The name is the smaller of the two on purpose -- the line
	-- that carries the feeling is "New ... Discovered!", and the name is the answer to it.
	local caption = Instance.new("Frame")
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.fromScale(0.5, 0.74)
	caption.Size = UDim2.fromScale(1.6, 0.26)
	caption.BackgroundTransparency = 1
	caption.ZIndex = 4
	caption.Parent = stage

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.42)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = UITheme.Font.Display
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = UITheme.Color.White
	nameLabel.Text = emoji .. " " .. stageName
	nameLabel.ZIndex = 4
	nameLabel.Parent = caption
	stroke(nameLabel, 4)

	local discovered = Instance.new("TextLabel")
	discovered.Position = UDim2.fromScale(0, 0.44)
	discovered.Size = UDim2.fromScale(1, 0.56)
	discovered.BackgroundTransparency = 1
	discovered.Font = UITheme.Font.Display
	discovered.TextScaled = true
	discovered.TextColor3 = UITheme.Color.Cream
	discovered.Text = ("New %s Discovered!"):format(stageName)
	discovered.ZIndex = 4
	discovered.Parent = caption
	stroke(discovered, 5)

	-- ---- the animation
	blur.Enabled = true
	TweenService:Create(blur, TweenInfo.new(0.3), { Size = 20 }):Play()
	TweenService:Create(dim, TweenInfo.new(0.28), { BackgroundTransparency = 0.4 }):Play()
	-- Back easing overshoots and settles: the pop is what makes this read as a reward rather than
	-- as a dialog appearing.
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()

	-- The burst keeps turning the whole time it is up, slowly, in the opposite sense to the figure.
	--
	-- The same loop HIDES THE REAL CHARACTER, and that is not a nicety: in third person the player's
	-- own body stands a few studs from the camera, dead centre -- exactly where the reveal figure is
	-- drawn. Blurred and dimmed it becomes a large dark mass directly behind a small lit one, and
	-- the two silhouettes fight. LocalTransparencyModifier is the right tool because it is purely
	-- local (nobody else sees the player vanish) -- but it is REAPPLIED EVERY FRAME on purpose: the
	-- default camera script rewrites it continuously, so a single assignment is undone on the next
	-- frame and the body flickers back.
	local character = player.Character
	-- HANDS THE PROPERTY OVER. CostumeVisibility reasserts LocalTransparencyModifier = 0 on every
	-- costume part after the camera each frame, because Roblox's own TransparencyController fades
	-- the whole character when the camera gets close and the costume is parented inside it. That is
	-- the same property this loop is writing 1 to, for the opposite reason -- so without a flag the
	-- two would take alternate frames and the reveal would show the player standing inside their
	-- own portrait. It stands down while this is set.
	--
	-- A DEADLINE PUSHED FORWARD EVERY FRAME, not a boolean raised once. The clearing code below
	-- lives inside a RenderStepped handler on a card that can be destroyed, interrupted, or replaced
	-- by a second reveal one frame later -- a stockpiled player can evolve twice in a row, and the
	-- first card's cleanup then runs while the second card is still on screen and clears a flag the
	-- second card had just raised. Every path that fails to clear a BOOLEAN leaves the keeper stood
	-- down forever on a character that never respawns, which does not hide the player: it hands the
	-- property back to Roblox's camera controller permanently and restores the exact see-through bug
	-- CostumeVisibility exists to stop. A deadline expires on its own, so the worst a lost cleanup
	-- can cost is the half second below.
	local HIDE_LEASE = 0.5
	local function holdHidden()
		if character then
			character:SetAttribute("CostumeHidden", os.clock() + HIDE_LEASE)
		end
	end
	holdHidden()
	local spinConn
	spinConn = RunService.RenderStepped:Connect(function(dt)
		if not burst.Parent then
			spinConn:Disconnect()
			if character then
				for _, d in ipairs(character:GetDescendants()) do
					if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
				end
				-- Cleared AFTER the restore above, so the keeper never sees a half-hidden body -- and
				-- only if the lease on the attribute is still OURS. A second reveal that started
				-- after this one was destroyed has already pushed the deadline past our own, and
				-- wiping it here is what used to make the player flicker through their own card.
				local held = character:GetAttribute("CostumeHidden")
				if type(held) ~= "number" or held <= os.clock() + HIDE_LEASE then
					character:SetAttribute("CostumeHidden", nil)
				end
			end
			return
		end
		burst.Rotation = (burst.Rotation - dt * 14) % 360
		if character and character.Parent then
			holdHidden()
			for _, d in ipairs(character:GetDescendants()) do
				if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
			end
		end
	end)

	task.delay(HOLD, function()
		-- `active ~= gui` means a SECOND reveal has already taken over and is running its own blur.
		-- Bailing out here rather than clearing the blur is the difference between the two reveals
		-- handing over cleanly and the first one's timer switching the second one's focus back on.
		if gui.Parent == nil or active ~= gui then return end
		TweenService:Create(blur, TweenInfo.new(0.35), { Size = 0 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Scale = 0.15 }):Play()
		task.wait(0.38)
		if active == gui then
			active = nil
			blur.Enabled = false
		end
		gui:Destroy()
	end)
end

Remotes.Notify.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or payload.kind ~= "evolve" then return end

	local stageName = payload.stage or "???"
	local emoji = payload.emoji or "\u{2B50}"
	-- The index as well as the colour, and off the same walk: the payload carries the stage NAME
	-- only, so the name is the key.
	local color = UITheme.Color.Gold
	local stageIndex = nil
	for i, s in ipairs(GameConfig.Stages) do
		if s.name == stageName then
			color = s.color
			stageIndex = i
			break
		end
	end

	-- THE CAPTION NAMES THE SKIN YOU ARE NOW WEARING, not the stage. An evolve hands over the next
	-- character in collection order and puts it on; announcing the stage instead was how the card
	-- ended up saying "New Worm Discovered!" over a body that was visibly something else. When the
	-- collection is complete there is nothing to earn and the stage is the honest answer again.
	local entry = payload.character and GameConfig.GetCharacter(payload.character) or nil
	if entry then
		stageName = entry.name or stageName
		emoji = entry.emoji or emoji
		color = entry.color or color
		stageIndex = entry.stage or stageIndex
	end

	-- THE WAIT. It used to be load-bearing for the figure: the card cloned the player's live body,
	-- the server rebuilds that body a moment after sending this, and snapshotting immediately
	-- captured the OLD one -- a reveal showing you what you had just stopped being. The figure is
	-- built from the stage now and no longer cares, but the wait stays for the two reasons that
	-- outlived it: the FALLBACK route still clones the character, and a third of a second lets the
	-- evolve burst in the world land before the screen dims over it.
	task.delay(0.35, function()
		local ok, err = pcall(show, stageName, emoji, color, stageIndex, entry)
		if not ok then
			warn("[EvolveReveal] " .. tostring(err))
		end
	end)
end)
