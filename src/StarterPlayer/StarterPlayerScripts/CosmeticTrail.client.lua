--[[
	CosmeticTrail -- the part of the vanity shop that anyone can actually see.

	34.2 sold three trails and NOTHING DREW THEM. `CosmeticService` wrote a `WornTrail` attribute
	and a grep for that name across `src/` found exactly one hit: the write. The catalogue rows
	carried `path = "Trails/Rainbow-01"`, an asset that exists nowhere in this repo, so the
	1,000-Diamond Galaxy Trail was a purchase that changed nothing on screen. This file is the
	reader, and the rows now carry a `colors` list instead of that path -- a Trail is a ribbon
	drawn from a ColorSequence, so it needs no texture and no asset id to be a real trail.

	DRAWN ENTIRELY ON THE CLIENT, off the attribute, exactly like `VipFlair`: an attribute
	replicates to every client on its own, so there is no remote here and every player sees every
	other player's trail for free. That also makes the second-client check the only honest test.

	SIZED OFF THE BODY -- AND THE BODY IS ONE SIZE NOW. `BodyScale` is the attribute
	`EvolutionVisuals.ApplyStage` stamps, and since her 2026-08-21 call (*"nemoj da igrac raste"*)
	that is `FIXED_BODY_SCALE = 1.0` at every one of the twenty stages, so this term is 1 today and
	the ribbon is a constant 3.2 studs against a body measured at 8.8. Measured and photographed at
	that ratio on 2026-08-28: it reads as a ribbon, not a thread. The term stays because it is the
	right shape if the body ever grows again -- it is not dead code, it is a scale that currently
	has one value. The two attachments are pushed apart rather than the trail being widened,
	because a Trail's width IS the distance between its attachments.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)

local TRAIL_NAME = "CosmeticTrail"
local A0_NAME = "CosmeticTrailTop"
local A1_NAME = "CosmeticTrailBase"

-- Keyed once. `GameConfig.Cosmetics` is an array and this runs on every respawn of every player.
local TRAILS = {}
for _, c in ipairs(GameConfig.Cosmetics) do
	if c.type == "Trail" then TRAILS[c.key] = c end
end

-- A ColorSequence needs its keypoints at 0 and 1 and strictly increasing in between, so the list
-- is spread evenly rather than each colour choosing a time. One colour is a legal sequence too.
local function sequenceFor(colors)
	if not colors or #colors == 0 then return ColorSequence.new(Color3.fromRGB(255, 255, 255)) end
	if #colors == 1 then return ColorSequence.new(colors[1]) end
	local keys = {}
	for i, col in ipairs(colors) do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), col))
	end
	return ColorSequence.new(keys)
end

local function clearTrail(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	for _, name in ipairs({ TRAIL_NAME, A0_NAME, A1_NAME }) do
		local existing = root:FindFirstChild(name)
		if existing then existing:Destroy() end
	end
end

local function buildTrail(character, row)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	clearTrail(character)

	local scale = character:GetAttribute("BodyScale") or 1
	local reach = 1.6 * scale

	local top = Instance.new("Attachment")
	top.Name = A0_NAME
	top.Position = Vector3.new(0, reach, -0.4 * scale)
	top.Parent = root

	local base = Instance.new("Attachment")
	base.Name = A1_NAME
	base.Position = Vector3.new(0, -reach, -0.4 * scale)
	base.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = top
	trail.Attachment1 = base
	trail.Color = sequenceFor(row.colors)
	-- Bright but not white: LightEmission 1 would clip every colour in the ribbon to white, which
	-- is the trap the particle notes already record for tints.
	trail.LightEmission = 0.55
	trail.LightInfluence = 0
	trail.Lifetime = 0.55
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- MinLength keeps a standing player from painting a smear where they stand; FaceCamera keeps
	-- the ribbon readable when it is seen edge-on, which is most of the time from behind.
	trail.MinLength = 0.2
	trail.FaceCamera = true
	trail.Parent = root
end

local function refresh(player)
	local character = player.Character
	if not character then return end
	local worn = player:GetAttribute("WornTrail")
	local row = worn and worn ~= "" and TRAILS[worn] or nil
	if row then
		buildTrail(character, row)
	else
		clearTrail(character)
	end
end

local function watch(player)
	-- The same three invalidations VipFlair catches: the item changing, a respawn (new root part),
	-- and an evolve (the ribbon is now the wrong size for the body).
	player:GetAttributeChangedSignal("WornTrail"):Connect(function()
		refresh(player)
	end)

	local function hookCharacter(character)
		character:GetAttributeChangedSignal("BodyScale"):Connect(function()
			refresh(player)
		end)
		refresh(player)
	end

	player.CharacterAdded:Connect(hookCharacter)
	if player.Character then hookCharacter(player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
