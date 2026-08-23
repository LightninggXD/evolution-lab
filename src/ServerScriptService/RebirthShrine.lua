--[[
	RebirthShrine -- the Rebirth plaza, and the four statues standing in it.

	Rebirth used to live entirely on the HUD: a Lavender tile on the sidebar opened a panel with a
	button on it. That works, and it is also the least memorable thing in the game -- the single
	biggest decision a player makes was a rectangle. The reference game (Duck Evolution) puts it in
	the WORLD: you walk to a statue and the statue is the button.

	FOUR STATUES, ONE PER TIER, AND THE TIER IS THE STATUE YOU CHOOSE. GameConfig.RebirthTierSize is
	5, so the checkpoints are stages 5 / 10 / 15 / 20 -- Wolf, Cosmic Being, Reality Architect, The
	Absolute. Each statue IS that creature, built from the same StageCostume the player wears at that
	stage, and triggering it rebirths you AT THAT TIER. Walking past the Wolf to reach the Absolute is
	the whole risk/reward decision made physical: the reward goes as tier^2, so the far statue is
	sixteen times the near one.

	WHAT IS SERVER-SIDE AND WHAT IS NOT. The geometry and the actual rebirth are server-side (a
	client must never be trusted with "I earned 80 shards"). The LOCK is not, and cannot be: a
	ProximityPrompt is one object shared by everyone in the server, and whether the Reality Architect
	is reachable depends on who is looking at it. RebirthShrineClient (StarterPlayerScripts) does the
	per-player half -- greying out a statue, disabling its prompt, writing the reward on its board --
	against the same GameConfig rules the server re-checks on trigger. The client half is cosmetic
	only; every path through HandleRebirth validates the tier again.

	ONE SHRINE PER TIER, EACH IN ITS OWN ZONE -- NOT FOUR IN A ROW IN THE FOREST. Zones map to
	stages 1:1 (GameConfig.Zones[i].unlockStageIndex == i), so zone 5 opens exactly when you become a
	Wolf: the Moon is where the Wolf statue stands, Nebula has the Cosmic Being, DreamDimension the
	Reality Architect, AbsolutePlane the Absolute. Reaching the statue and earning the rebirth are
	then the same act of travel, and each shrine is a landmark of the zone it belongs to rather than
	four monuments crowded onto the starting platform.

	Every zone platform has the same layout (the street down Z at x = cx, the shop at cx - 150, the
	well at cx + 150), so one set of local coordinates works in all four -- offset by the zone's own
	`offset` on X, which is the only thing that differs.
]]

local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(RS.Modules.GameConfig)
local StageCostume = require(RS.Modules.StageCostume)

local RebirthShrine = {}

-- Bump to force a rebuild of the plaza on the next server start. Stamped on the model rather than
-- compared piece by piece, the same trick ZoneBuilder uses -- without it no change to the geometry
-- below would ever be visible again on a place that has already been played.
local SHRINE_VERSION = 6

-- ===== WHERE ONE SHRINE STANDS, IN ITS ZONE'S LOCAL SPACE =====
-- A zone platform is 1250 (X) x 1150 (Z) centred on (offset, *, 0) with its top face at y = 0. The
-- street runs down Z at x = offset +- 38 (lamps, benches, planters); the shop is at offset - 150
-- and the well at (offset + 150, -168). This block of ground is the largest piece of any zone with
-- nothing built on it, and it is in sight of the street rather than off behind the scenery.
local LOCAL_CENTRE = Vector3.new(300, 0, 60)
local PLAZA_X, PLAZA_Z = 150, 200
-- The statue stands at the back (east) edge and faces the street, so you walk in through the
-- gateway and it is looking at you.
local STATUE_DX = 34

-- Stone, in three values, so every slab in here is one of the same three greys.
local STONE      = Color3.fromRGB(150, 146, 158)
local STONE_LITE = Color3.fromRGB(184, 180, 192)
local STONE_DARK = Color3.fromRGB(96, 92, 106)
local GOLD       = Color3.fromRGB(255, 205, 90)

-- ===== PART VOCABULARY =====
-- Deliberately a local copy rather than a require of ZoneBuilder's: that module is 4,000 lines and
-- rebuilds 60,000 parts behind a version stamp of its own. This one builds ~200 and owns them.
local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function addLight(part, color, range, brightness)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	return light
end

-- A slow breathing pulse, driven by one repeating tween rather than a heartbeat connection.
local function pulseForever(part, minTransparency, seconds)
	local base = part.Transparency
	part.Transparency = minTransparency
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = base,
	}):Play()
end

-- ===== THE STATUE ITSELF =====
-- An R15-NAMED ARMATURE, NOT A LOADED AVATAR. StageCostume.Apply looks up its host limbs by name
-- (UpperTorso, LeftUpperArm, ...) and sizes every piece of the costume off the limb it hangs on, so
-- a model with the right names and the right proportions is dressed exactly like a player is --
-- with no HumanoidDescription, no asset download, and nothing that can fail offline in Studio.
--
-- Sizes are the default R15 rig's, in studs, with the feet at y = 0. They are then multiplied by
-- EvolutionVisuals' own PROPORTION pass (short, wide, big-headed) so the statue is the same shape
-- as the character it is a statue OF -- a rig scaled evenly is just a tall thin default avatar.
local RIG = {
	{ "HumanoidRootPart", Vector3.new(2, 2, 1),    Vector3.new(0, 3.6, 0) },
	{ "LowerTorso",       Vector3.new(2, 0.4, 1),  Vector3.new(0, 3.4, 0) },
	{ "UpperTorso",       Vector3.new(2, 1.6, 1),  Vector3.new(0, 4.4, 0) },
	{ "LeftUpperArm",     Vector3.new(1, 1.4, 1),  Vector3.new(-1.5, 4.5, 0) },
	{ "LeftLowerArm",     Vector3.new(1, 1.2, 1),  Vector3.new(-1.5, 3.2, 0) },
	{ "LeftHand",         Vector3.new(1, 0.3, 1),  Vector3.new(-1.5, 2.45, 0) },
	{ "RightUpperArm",    Vector3.new(1, 1.4, 1),  Vector3.new(1.5, 4.5, 0) },
	{ "RightLowerArm",    Vector3.new(1, 1.2, 1),  Vector3.new(1.5, 3.2, 0) },
	{ "RightHand",        Vector3.new(1, 0.3, 1),  Vector3.new(1.5, 2.45, 0) },
	{ "LeftUpperLeg",     Vector3.new(1, 1.4, 1),  Vector3.new(-0.5, 2.5, 0) },
	{ "LeftLowerLeg",     Vector3.new(1, 1.5, 1),  Vector3.new(-0.5, 1.05, 0) },
	{ "LeftFoot",         Vector3.new(1, 0.3, 1),  Vector3.new(-0.5, 0.15, 0) },
	{ "RightUpperLeg",    Vector3.new(1, 1.4, 1),  Vector3.new(0.5, 2.5, 0) },
	{ "RightLowerLeg",    Vector3.new(1, 1.5, 1),  Vector3.new(0.5, 1.05, 0) },
	{ "RightFoot",        Vector3.new(1, 0.3, 1),  Vector3.new(0.5, 0.15, 0) },
}
-- Same four numbers as EvolutionVisuals.PROPORTION. Duplicated rather than required because that
-- module is server-side and reaches into PlayerDataService; this needs the shape, not the service.
local W, H, D, HEAD = 1.22, 0.92, 1.22, 1.32
-- The top of the UpperTorso in un-scaled rig units -- where the head sits on.
local TORSO_TOP = 5.2

-- Builds one dressed, anchored statue of `stageIndex` standing at `baseCF` (feet on the ground,
-- local -Z pointing where it faces). Returns the model.
local function buildStatue(stageIndex, scale, baseCF)
	local stage = GameConfig.Stages[stageIndex]
	local model = Instance.new("Model")
	model.Name = "StatueRig"

	for _, spec in ipairs(RIG) do
		local name, size, pos = spec[1], spec[2], spec[3]
		local part = newPart({
			Name = name,
			Size = Vector3.new(size.X * W, size.Y * H, size.Z * D) * scale,
			CFrame = baseCF * CFrame.new(pos.X * W * scale, pos.Y * H * scale, pos.Z * D * scale),
			Color = stage.color,
			Material = Enum.Material.SmoothPlastic,
			-- The costume shells are what the player sees and what they walk into; the armature under
			-- them is hidden by StageCostume and must not also be a wall.
			CanCollide = false,
			Parent = model,
		})
		if name == "HumanoidRootPart" then
			model.PrimaryPart = part
		end
	end

	-- The head is scaled by HeadScale on all three axes, not by the body's per-axis pass, so its
	-- height is not TORSO_TOP + 0.5 any more -- it is the torso top plus half of whatever the head
	-- grew to. Placed after the loop for that reason.
	local headSize = Vector3.new(2, 1, 1) * HEAD * scale
	newPart({
		Name = "Head",
		Size = headSize,
		CFrame = baseCF * CFrame.new(0, TORSO_TOP * H * scale + headSize.Y / 2, 0),
		Color = stage.color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	-- Apply needs the model already in the tree: att() parents each piece into a folder that is
	-- itself parented to the character, and a piece built into nil is collected before its weld runs.
	model.Parent = workspace
	-- THE STAGE'S OWN CHARACTER, not nil.
	--
	-- `nil` used to mean "the stage's default look", which was right while a character was only a
	-- colour. It is not any more: StageCostume tries SkinMesh first and SkinMesh needs a character
	-- key, so passing nil quietly kept every statue on the old primitive build -- a monument to the
	-- creature you become, that no longer looks like the creature you become.
	--
	-- The BASE character is the right one: it is the plain version each stage starts you as, so the
	-- statue shows the stage rather than somebody's favourite skin of it.
	local baseChar = GameConfig.GetBaseCharacterForStage(stageIndex)
	StageCostume.Apply(model, stageIndex, stage, baseChar)

	-- Costume pieces are welded, not anchored, and their Part0 here is an anchored armature limb --
	-- which anchors the whole assembly for free while leaving the tweened welds (haloes, orbiting
	-- shards, the Absolute's crystals) still turning. That motion is most of what makes a statue of
	-- a cosmic entity read as a statue OF something rather than as a grey lump.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	return model
end

-- ===== THE PLINTH AND THE BOARD =====
local function buildBoard(host, tier, stageIndex, height)
	local stage = GameConfig.Stages[stageIndex]

	local anchor = newPart({
		Name = "BoardAnchor",
		Size = Vector3.new(2, 2, 2),
		CFrame = host.CFrame * CFrame.new(0, height, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = host.Parent,
	})

	local board = Instance.new("BillboardGui")
	board.Name = "StatueBoard"
	-- Scale is studs on a BillboardGui, so this is a 38 x 17 stud sign that keeps a constant screen
	-- size at range -- readable from the street, which is 300 studs away. It was 60 x 26 and that
	-- was wrong twice: stood next to it the sign was wider than the statue, and four of them in a
	-- row overlapped into one wall of text seen from the gateway.
	board.Size = UDim2.new(38, 0, 17, 0)
	board.AlwaysOnTop = false
	board.LightInfluence = 0
	board.MaxDistance = 620
	board.Parent = anchor

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(26, 20, 34)
	card.BackgroundTransparency = 0.12
	card.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Thickness = 4
	edge.Color = GOLD
	edge.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0.44, 0)
	title.Position = UDim2.new(0, 8, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	-- TextScaled alone shrinks to fit the HEIGHT and then runs off the sides. Wrapped, it uses both.
	title.TextWrapped = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(16, 12, 26)
	title.TextStrokeTransparency = 0
	title.Text = ("TIER %d  \u{2022}  %s %s"):format(tier, stage.emoji, stage.name)
	title.Parent = card

	-- Filled in per player by RebirthShrineClient. The server text is the honest fallback for the
	-- half second before the first DataUpdate lands, not a placeholder that stays wrong.
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, -16, 0.46, 0)
	status.Position = UDim2.new(0, 8, 0.48, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextWrapped = true
	status.TextColor3 = GOLD
	status.TextStrokeColor3 = Color3.fromRGB(16, 12, 26)
	status.TextStrokeTransparency = 0.2
	-- THE GATE IS A LEVEL SINCE 32.7, not a stage. This is the server-side fallback for the half
	-- second before the first DataUpdate lands, so it names the tier's own requirement --
	-- `RebirthShrineClient` overwrites it per player, and it is the only one that can, because
	-- past rung four the statue stands for whichever rung the player is actually on.
	status.Text = ("\u{1F512} Level %d"):format(GameConfig.RebirthLevelFor(tier))
	status.Parent = card

	return anchor
end

-- One statue, its plinth, its board and its prompt. `tier` is 1..MaxRebirthTier, `centre` the
-- plaza's world centre in the zone it belongs to.
local function buildMonument(parent, tier, centre)
	local stageIndex = GameConfig.GetRebirthTierStageIndex(tier)
	local stage = GameConfig.Stages[stageIndex]
	local monument = Instance.new("Model")
	monument.Name = "RebirthStatue" .. tier

	-- A MONUMENT, NOT A GARDEN ORNAMENT. This row was 26 -> 44 studs, which is a big statue next to
	-- a stage-1 player and a knee-high figurine next to the stage-20 player who is actually standing
	-- here -- a rebirth is only reachable from stage 5 up. The rig is ~5.7 studs tall per unit of
	-- scale, so this now runs 68 -> 120 studs: taller than the 60-stud gateway you walk in through,
	-- clear under the zone's own 180-stud boundary wall, and read from the far end of the plaza.
	local scale = 12 + tier * 3

	-- FACING THE GATE. This was math.rad(-90), whose LookVector is +X -- and the statue stands at
	-- centre.X + STATUE_DX while the steps, the piers and the lintel are all at centre.X - halfX.
	-- So every statue in the game had its back to the doorway every player walks in through, which
	-- is exactly what was reported. +90 points it at -X, down the plaza and at whoever arrives.
	local at = CFrame.new(centre.X + STATUE_DX, 0, centre.Z) * CFrame.Angles(0, math.rad(90), 0)

	-- the plinth grows with what stands on it: a 120-stud figure on a 32-stud drum is a pin in a
	-- pincushion, and the cap has to be wider than the statue's own stance or the feet overhang it
	local plinthH = 14 + tier * 3
	local plinthW = 42 + tier * 7

	-- ---- the plinth: base slab, drum, cap. Three parts is the fewest that reads as masonry rather
	-- than as a box, and the cap overhangs the drum so it casts a line of shadow around itself.
	newPart({ Name = "PlinthBase", Size = Vector3.new(plinthW + 8, 2.4, plinthW + 8),
		CFrame = at * CFrame.new(0, 1.2, 0), Color = STONE_DARK, Material = Enum.Material.Slate, Parent = monument })
	local plinth = newPart({ Name = "Plinth", Size = Vector3.new(plinthW, plinthH, plinthW),
		CFrame = at * CFrame.new(0, 2.4 + plinthH / 2, 0), Color = STONE, Material = Enum.Material.Slate, Parent = monument })
	newPart({ Name = "PlinthCap", Size = Vector3.new(plinthW + 5, 2, plinthW + 5),
		CFrame = at * CFrame.new(0, 3.4 + plinthH, 0), Color = STONE_LITE, Material = Enum.Material.Slate, Parent = monument })

	-- the tier's colour burning in a groove around the plinth, so a locked statue still has a
	-- colour on it and an unlocked one has something for the client to brighten
	local groove = newPart({ Name = "PlinthGlow", Size = Vector3.new(plinthW + 5.6, 1.1, plinthW + 5.6),
		CFrame = at * CFrame.new(0, 2.9 + plinthH, 0), Color = stage.color, Material = Enum.Material.Neon,
		Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = monument })
	addLight(groove, stage.color, 34, 2)
	pulseForever(groove, 0.6, 2.6 + tier * 0.2)

	-- ---- the statue, standing on the cap and facing the street
	local top = 4.4 + plinthH
	local rig = buildStatue(stageIndex, scale, at * CFrame.new(0, top, 0))
	rig.Parent = monument

	-- ---- the board, above the head. Measured off the finished model rather than computed from the
	-- rig's own height: what actually reaches highest is the COSTUME -- The Absolute's halo stands a
	-- third of a body above its crown -- and a board placed at the head sat across the statue's face.
	local rigCF, rigSize = rig:GetBoundingBox()
	local boardY = rigCF.Y + rigSize.Y / 2 + 9 - plinth.Position.Y
	buildBoard(plinth, tier, stageIndex, boardY)

	-- ---- the prompt. It hangs on the plinth, not on the statue: a ProximityPrompt measures to the
	-- character's root, and a player at stage 20 is nine times normal size -- the thing they walk up
	-- to has to be the thing at ground level. MaxActivationDistance matches ZoneBuilder's shop reach
	-- for the same reason.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RebirthPrompt"
	prompt.ActionText = ("Rebirth \u{2022} Tier %d"):format(tier)
	prompt.ObjectText = stage.emoji .. " " .. stage.name
	-- A full second of hold. Rebirth wipes DNA, stage, upgrades, mutations and zone unlocks -- it is
	-- the one prompt in the game that must not be triggerable by walking past and tapping E.
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 42
	prompt.RequiresLineOfSight = false
	-- OFF UNTIL A CLIENT TURNS IT ON. Whether this statue is usable is a per-player question and only
	-- RebirthShrineClient can answer it; shipped enabled, a stage-1 player walking past the Wolf gets
	-- an "E to Rebirth" offer that the server then refuses. Off by default the worst case is a statue
	-- that says nothing, and the HUD's Rebirth panel still works either way.
	prompt.Enabled = false
	prompt.Parent = plinth

	monument.PrimaryPart = plinth
	monument:SetAttribute("RebirthTier", tier)
	monument:SetAttribute("RequiredStageIndex", stageIndex)
	monument.Parent = parent
	-- How the client finds these without knowing where they are or how many there are.
	CollectionService:AddTag(monument, "RebirthStatue")

	return monument, prompt
end

-- ===== THE PLAZA =====
-- Everything in the zone standing where the plaza goes. Zones are dense -- crates, rocks, ground
-- patches, a banner -- and none of it was placed with a 150 x 200 stone terrace in mind. Cleared by
-- footprint rather than by name so it keeps working when the decor changes, and so it works the
-- same in all four zones without knowing what any of them is made of.
local KEEP = {
	Floor = true, Wall = true, CliffBlock = true, CliffCap = true, CliffRubble = true,
}

local function clearFootprint(zoneKey, centre, shrine)
	local zone = workspace:FindFirstChild("Zones") and workspace.Zones:FindFirstChild(zoneKey)
	if not zone then return end

	local box = CFrame.new(centre + Vector3.new(0, 60, 0))
	local removed = {}
	for _, part in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(PLAZA_X, 120, PLAZA_Z))) do
		if part:IsDescendantOf(zone) and not (shrine and part:IsDescendantOf(shrine)) then
			-- Walk up to the piece of decor that is a direct child of the zone: a tree is a Model of
			-- many parts, and destroying one of them leaves half a tree standing in the terrace.
			local top = part
			while top.Parent ~= zone and top.Parent ~= nil and top ~= zone do
				top = top.Parent
			end
			if top ~= zone and not KEEP[top.Name] then
				removed[top] = true
			end
		end
	end
	for inst in pairs(removed) do
		inst:Destroy()
	end
end

-- The whole shrine for one tier, standing in `zone`. `accent` is the zone's own accent colour, so
-- the braziers and the gate flames belong to the biome they are burning in rather than making every
-- shrine the same gold in a place that is otherwise green, or red, or void.
local function buildShrine(zone, tier)
	local centre = Vector3.new(zone.offset + LOCAL_CENTRE.X, 0, LOCAL_CENTRE.Z)
	local accent = zone.accentColor or GOLD
	local shrine = Instance.new("Model")
	shrine.Name = "RebirthShrine_" .. zone.key

	local halfX = PLAZA_X / 2

	-- ---- the terrace. Two slabs: a wide dark base a stud proud of the ground and the paved deck on
	-- top of it, so the plaza has an edge you can see you are standing on.
	local deck = newPart({ Name = "Terrace", Size = Vector3.new(PLAZA_X, 2, PLAZA_Z),
		Position = centre + Vector3.new(0, 1, 0), Color = STONE, Material = Enum.Material.Slate, Parent = shrine })
	newPart({ Name = "TerraceRim", Size = Vector3.new(PLAZA_X + 10, 1.2, PLAZA_Z + 10),
		Position = centre + Vector3.new(0, 0.6, 0), Color = STONE_DARK, Material = Enum.Material.Slate, Parent = shrine })
	shrine.PrimaryPart = deck

	-- paving: a checker of slightly lighter flags laid on the deck. Free, and it is the difference
	-- between a stone floor and one flat grey rectangle.
	for gx = -2, 2 do
		for gz = -2, 2 do
			if (gx + gz) % 2 == 0 then
				newPart({ Name = "Flag", Size = Vector3.new(PLAZA_X / 5.4, 0.3, PLAZA_Z / 5.4),
					Position = centre + Vector3.new(gx * PLAZA_X / 5, 2.1, gz * PLAZA_Z / 5),
					Color = STONE_LITE, Material = Enum.Material.Slate, CanCollide = false, CastShadow = false, Parent = shrine })
			end
		end
	end

	-- ---- steps up from the street side, the width of the entrance rather than of the terrace: a
	-- 330-stud staircase reads as a ramp, and the plaza wants a doorway.
	for i = 1, 3 do
		newPart({ Name = "Step", Size = Vector3.new(4, 0.8, 90),
			Position = Vector3.new(centre.X - halfX - (i - 0.5) * 4, 2.2 - i * 0.7, centre.Z),
			Color = STONE_LITE, Material = Enum.Material.Slate, Parent = shrine })
	end

	-- ---- the gateway you walk in through, so arriving at the plaza has a threshold the same way
	-- arriving in a zone does. Two piers, a lintel, and the word on it.
	for _, sz in ipairs({ -1, 1 }) do
		local z = centre.Z + sz * 46
		newPart({ Name = "GatePier", Size = Vector3.new(9, 46, 9),
			Position = Vector3.new(centre.X - halfX + 5, 25, z), Color = STONE, Material = Enum.Material.Slate, Parent = shrine })
		newPart({ Name = "GatePierCap", Size = Vector3.new(13, 3, 13),
			Position = Vector3.new(centre.X - halfX + 5, 49.5, z), Color = STONE_DARK, Material = Enum.Material.Slate, CanCollide = false, Parent = shrine })
		local flame = newPart({ Name = "GateFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 8, 7),
			Position = Vector3.new(centre.X - halfX + 5, 55, z), Color = accent, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false, Parent = shrine })
		addLight(flame, accent, 46, 2.6)
		pulseForever(flame, 0.45, 2.2)
	end
	local lintel = newPart({ Name = "GateLintel", Size = Vector3.new(11, 12, 104),
		Position = Vector3.new(centre.X - halfX + 5, 56, centre.Z), Color = STONE_LITE, Material = Enum.Material.Slate,
		CanCollide = false, Parent = shrine })

	-- The name, painted onto both faces of the lintel rather than hung in the air beside it -- a
	-- BillboardGui turns to face the camera and from the side it is a card floating in the sky.
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local sign = Instance.new("SurfaceGui")
		sign.Name = "GateSign"
		sign.Face = face
		sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sign.PixelsPerStud = 16
		sign.LightInfluence = 0
		sign.MaxDistance = 620
		sign.Parent = lintel
		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, 0, 1, 0)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = GOLD
		text.TextStrokeColor3 = Color3.fromRGB(30, 22, 12)
		text.TextStrokeTransparency = 0
		text.Text = "\u{267B}\u{FE0F} REBIRTH SHRINE"
		text.Parent = sign
	end

	-- ---- braziers down both long edges, marking the walk up to the statue
	for i = -1, 1 do
		for _, sx in ipairs({ -1, 1 }) do
			local at = Vector3.new(centre.X + sx * (halfX - 14), 0, centre.Z + i * 62)
			newPart({ Name = "BrazierPost", Size = Vector3.new(4, 16, 4), Position = at + Vector3.new(0, 10, 0),
				Color = STONE_DARK, Material = Enum.Material.Slate, Parent = shrine })
			local bowl = newPart({ Name = "BrazierFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 7, 6),
				Position = at + Vector3.new(0, 20, 0), Color = accent, Material = Enum.Material.Neon,
				CanCollide = false, CastShadow = false, Parent = shrine })
			addLight(bowl, accent, 30, 1.8)
			pulseForever(bowl, 0.5, 1.8 + (i + 1) * 0.25)
		end
	end

	local _, prompt = buildMonument(shrine, tier, centre)

	shrine:SetAttribute("ShrineVersion", SHRINE_VERSION)
	shrine:SetAttribute("RebirthTier", tier)
	return shrine, prompt, centre
end

-- ===== PUBLIC API =====

function RebirthShrine.Init()
	local RebirthService = require(script.Parent.RebirthService)

	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- Parented to Workspace.Map, not into the zone models: ZoneBuilder drops and regenerates the
	-- whole Zones folder whenever its own BUILD_VERSION moves, and a shrine has no business being
	-- deleted by a change to a tree.
	local holder = map:FindFirstChild("RebirthShrines")
	if holder and holder:GetAttribute("ShrineVersion") ~= SHRINE_VERSION then
		holder:Destroy()
		holder = nil
	end
	-- Version 1 and 2 put all four statues on one Forest plaza under a differently named model.
	-- Left alone it would still be standing there, unreferenced, next to the new Moon shrine.
	local legacy = map:FindFirstChild("RebirthShrine")
	if legacy then
		legacy:Destroy()
	end

	local fresh = not holder
	if fresh then
		holder = Instance.new("Folder")
		holder.Name = "RebirthShrines"
		holder:SetAttribute("ShrineVersion", SHRINE_VERSION)
		holder.Parent = map
	end

	for tier = 1, GameConfig.MaxRebirthTier do
		-- Zones and stages run 1:1, so the tier's checkpoint stage IS its zone index: tier 1's Wolf
		-- stands on the Moon (zone 5), which is the zone that opens the moment you become a Wolf.
		local zoneIndex = GameConfig.GetRebirthTierStageIndex(tier)
		local zone = GameConfig.Zones[zoneIndex]
		if zone then
			local prompt
			local centre = Vector3.new(zone.offset + LOCAL_CENTRE.X, 0, LOCAL_CENTRE.Z)
			local shrine = holder:FindFirstChild("RebirthShrine_" .. zone.key)
			if shrine then
				local monument = shrine:FindFirstChild("RebirthStatue" .. tier)
				prompt = monument and monument.PrimaryPart and monument.PrimaryPart:FindFirstChild("RebirthPrompt")
			else
				shrine, prompt = buildShrine(zone, tier)
				shrine.Parent = holder
			end

			-- Every start, built or not: ZoneBuilder may have regenerated the zone's decor underneath
			-- a shrine that itself did not change.
			clearFootprint(zone.key, centre, shrine)

			if prompt then
				prompt.Triggered:Connect(function(player)
					-- The client disables the prompt on a statue the player has not earned, so this is
					-- the second check and not the first -- but it is the only one that counts.
					-- HandleRebirth re-validates against the player's own saved level.
					--
					-- NIL, NOT `tier` (32.7). There are twenty rungs on the ladder now and four
					-- monuments on the map, so a statue can no longer BE a milestone -- it is an
					-- altar, and what it performs is "the next rebirth, whichever that is". Passing
					-- the statue's own number would refuse every rung past the fourth with "that
					-- milestone is spent", on the only four doors in the world. `nil` is the value
					-- HandleRebirth already documents for exactly this -- it is what the HUD button
					-- sends -- and it gives up nothing: the tier argument was never a permission,
					-- only an assertion the server checked and could equally well not be told.
					RebirthService.HandleRebirth(player, nil)
				end)
			end
		end
	end
end

return RebirthShrine
