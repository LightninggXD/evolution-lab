--[[
	PetModel - builds one chunky, blocky pet rig in the pet-simulator style: an oversized cube
	head, a small body, flat cartoon eyes and a thick dark outline.

	Shared on purpose. The pets trailing behind a player (PetFollowService) and the pets on
	display above each egg (ZoneBuilder) have to be recognisably the same creature, and the only
	way to guarantee that is one builder. Callers differ only in scale.

	Nothing here is welded. Every piece carries its offset from the root in the returned `pieces`
	list, so the caller can place the whole rig from a single CFrame each frame -- which is what
	lets pets float and bob without any physics.

	Species have no per-species geometry: 100 of them would be 100 hand-built rigs. Instead the
	key hashes to one of five archetypes (cat / dog / bunny / dragon / blob) and the species
	colour does the rest, so two pets of the same archetype still read as different animals.
]]

local PetModel = {}

local OUTLINE = Color3.fromRGB(18, 12, 26)

local ARCHETYPES = { "cat", "dog", "bunny", "dragon", "blob" }

-- deterministic: the same species must never change shape between sessions or between the
-- follower rig and the egg display
local function archetypeFor(key)
	local h = 7
	for i = 1, #key do
		h = (h * 31 + key:byte(i)) % 100003
	end
	return ARCHETYPES[(h % #ARCHETYPES) + 1]
end

local function lighten(c, t) return c:Lerp(Color3.new(1, 1, 1), t) end
local function darken(c, t) return c:Lerp(OUTLINE, t) end

function PetModel.ArchetypeFor(key)
	return archetypeFor(key)
end

-- ===== MESH PETS =====
--
-- The blocky rig below is still the fallback and still the thing every caller animates, but the
-- species now WEARS a mesh: `ReplicatedStorage.Assets.PetMeshes` holds 54 finished creature
-- meshes, and a pet that has one is built as an invisible root with that mesh hung off it instead
-- of as thirty coloured blocks.
--
-- WHY THE ROOT STAYS A PART, AND AN INVISIBLE ONE. Every caller in the game takes
-- `(model, root, pieces)` back from Build and drives the rig through `Place`, and the follower
-- client bobs and leans the pieces by their `PetOffset`. Making the mesh the root would have
-- changed the size the nameplate, the ring and the follower's hover height are all measured from.
-- An invisible body of exactly the old dimensions keeps every one of those numbers true and costs
-- one part.
--
-- WHICH MESH A SPECIES GETS: its position in `GameConfig.Pets`, wrapped. 140 species over 54
-- meshes is between two and three species a mesh, and wrapping BY ORDER rather than by a hash of
-- the key is what keeps the seven pets of one zone -- which are consecutive in that list, and the
-- only set a player ever sees side by side -- on seven different meshes.
local meshLib, meshIndex

local function meshFor(key)
	if meshIndex == nil then
		meshIndex = {}
		local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
		meshLib = assets and assets:FindFirstChild("PetMeshes")
		if meshLib then
			local meshes = {}
			for _, m in ipairs(meshLib:GetChildren()) do
				if m:IsA("BasePart") then table.insert(meshes, m) end
			end
			table.sort(meshes, function(a, b) return a.Name < b.Name end)
			if #meshes > 0 then
				local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)
				for i, def in ipairs(GameConfig.Pets) do
					meshIndex[def.key] = meshes[((i - 1) % #meshes) + 1]
				end
			end
		end
	end
	return meshIndex[key]
end

--[[
	def   - a GameConfig pet definition (key, name, emoji, color, rarity)
	tier  - "Normal" / "Golden" / "Rainbow" / "Celestial"
	opts  - { scale = number, nameplate = bool, plateDistance = number, sparkle = bool }
	          -- `sparkle` is now inert: 15.31 removed the rarity glow it used to switch off.

	Returns model, root, pieces. `root` is the PrimaryPart; every entry in `pieces` is
	{ p = Part, cf = CFrame } giving that part's offset from the root.
]]
function PetModel.Build(def, tier, opts)
	opts = opts or {}
	local scale = opts.scale or 1
	local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)
	local rarity = GameConfig.GetRarity(def.rarity)
	local skin = def.color
	local belly = lighten(skin, 0.5)
	local shade = darken(skin, 0.35)
	local kind = archetypeFor(def.key)

	local model = Instance.new("Model")
	model.Name = def.key

	local pieces = {}
	local template = meshFor(def.key)

	-- the offset also goes on the part as a CFrame attribute: the client-side follower has to
	-- place pets built by the server, and re-deriving these numbers there would let the two
	-- copies of the rig drift apart the first time this file changes
	local function addPiece(p, cf)
		table.insert(pieces, { p = p, cf = cf })
		p:SetAttribute("PetOffset", cf)
	end

	local function block(name, size, offset, color, material, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Block
		p.Size = size * scale
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Transparency = transparency or 0
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		if offset then
			local cf = typeof(offset) == "CFrame" and offset or CFrame.new(offset)
			-- scale the translation but never the rotation
			local pos = cf.Position * scale
			addPiece(p, CFrame.new(pos) * (cf - cf.Position))
		end
		return p
	end

	-- ---- body. This is the root: everything else hangs off it, and it is deliberately the
	-- small part of the silhouette -- the head is what you actually see from behind.
	local body = block("Body", Vector3.new(1.75, 1.45, 1.65), nil, skin)

	if template then
		-- ===== the mesh rig: an invisible root, the creature, and nothing else built =====
		body.Transparency = 1

		local geom = template:Clone()
		geom.Name = "Geom"
		-- NORMALISED, NOT USED AT ITS AUTHORED SIZE. The library ranges from 1.8 to 6.2 studs tall
		-- and the rig it replaces is 2.9 -- unnormalised, one species would tower over the egg it
		-- hatched from and the next would vanish into the podium.
		--
		-- BY HEIGHT FIRST, and this is the whole difference between the first cut and this one:
		-- normalising the LONGEST axis meant a long flat creature spent its whole budget on length
		-- and stood half as tall as a boxy one beside it. Height is what the eye compares. The
		-- width clamp is there so the two or three genuinely wide meshes do not end up as a metre
		-- of pet either side of the player.
		--
		-- AND THE SCALE GOES ON THE MESH, NOT ONLY ON THE PART. A `SpecialMesh` renders at its own
		-- `Scale` and ignores the part it hangs on, so resizing the part alone changed the hitbox
		-- and nothing a player can see -- every species came out at whatever size its author left
		-- it. The part is still resized with it, because that is what the rig measures from.
		local fit = math.min(2.7 * scale / geom.Size.Y, 4.2 * scale / math.max(geom.Size.X, geom.Size.Z))
		geom.Size = geom.Size * fit
		local special = geom:FindFirstChildWhichIsA("SpecialMesh")
		if special then
			special.Scale = special.Scale * fit
		end
		geom.Anchored = true
		geom.CanCollide = false
		geom.CanQuery = false
		geom.CanTouch = false
		geom.CastShadow = false
		geom.Parent = model

		-- The sparkles the models shipped with are parked in an `Fx` folder by the library build,
		-- because sixty of these stand on the egg podiums at once and a hundred emitters a pet is
		-- not a decoration budget. A caller that wants a hero pet -- the hatch reveal, the pet
		-- actually following you -- asks for them back.
		local fx = geom:FindFirstChild("Fx")
		if fx then
			if opts.fx then
				for _, e in ipairs(fx:GetChildren()) do e.Parent = geom end
			end
			fx:Destroy()
		end

		-- sat so the creature stands ON the rarity ring rather than hovering over it. The ring is
		-- at -1.5 * scale and this offset is in world studs (addPiece does no scaling of its own --
		-- only `block` does), so the scale has to be carried explicitly.
		addPiece(geom, CFrame.new(0, geom.Size.Y / 2 - 1.45 * scale, 0))
	else
		block("Belly", Vector3.new(1.15, 0.95, 0.2), Vector3.new(0, -0.12, -0.78), belly)
	end

	-- ---- Everything from here to the rarity ring is the BLOCKY rig, and a species with a mesh
	-- skips all of it: legs, head, face and the archetype's ears and tail are what the mesh is
	-- instead of. The ring, the crown, the nameplate and the outline below are common to both.
	if not template then

	-- ---- legs: four stubs. Front pair sits slightly forward of the body so the pet reads as
	-- leaning into the direction it faces.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			block("Leg", Vector3.new(0.52, 0.7, 0.52), Vector3.new(sx * 0.52, -1.02, sz * 0.5), shade)
			block("Paw", Vector3.new(0.56, 0.22, 0.58), Vector3.new(sx * 0.52, -1.32, sz * 0.52), darken(skin, 0.55))
		end
	end

	-- ---- head, oversized on purpose: this is the whole look
	block("Head", Vector3.new(2.15, 1.95, 1.9), Vector3.new(0, 1.5, -0.2), skin)
	block("Muzzle", Vector3.new(0.95, 0.6, 0.4), Vector3.new(0, 1.08, -1.05), belly)
	block("Nose", Vector3.new(0.34, 0.26, 0.22), Vector3.new(0, 1.32, -1.16), OUTLINE)

	for _, side in ipairs({ -1, 1 }) do
		block("Eye", Vector3.new(0.46, 0.56, 0.16), Vector3.new(side * 0.55, 1.72, -1.11), Color3.fromRGB(252, 252, 255))
		block("Pupil", Vector3.new(0.26, 0.34, 0.14), Vector3.new(side * 0.55, 1.68, -1.16), OUTLINE)
		block("Glint", Vector3.new(0.12, 0.14, 0.12), Vector3.new(side * 0.62, 1.83, -1.19), Color3.fromRGB(255, 255, 255))
		block("Cheek", Vector3.new(0.34, 0.22, 0.12), Vector3.new(side * 0.82, 1.28, -1.13), lighten(Color3.fromRGB(255, 130, 170), 0.15), nil, 0.35)
	end

	-- ---- archetype: ears, tail and whatever else that animal needs
	if kind == "cat" then
		for _, side in ipairs({ -1, 1 }) do
			block("Ear", Vector3.new(0.5, 0.62, 0.32), CFrame.new(side * 0.66, 2.62, -0.24) * CFrame.Angles(0, 0, side * 0.22), skin)
			block("EarInner", Vector3.new(0.26, 0.34, 0.12), CFrame.new(side * 0.66, 2.6, -0.44) * CFrame.Angles(0, 0, side * 0.22), lighten(Color3.fromRGB(255, 150, 190), 0.1))
		end
		block("Tail", Vector3.new(0.3, 0.9, 0.3), Vector3.new(0, 0.55, 1.0), shade)
		block("TailTip", Vector3.new(0.32, 0.34, 0.5), Vector3.new(0, 1.05, 1.12), belly)
	elseif kind == "dog" then
		for _, side in ipairs({ -1, 1 }) do
			block("Ear", Vector3.new(0.4, 0.95, 0.42), CFrame.new(side * 1.14, 1.75, -0.28) * CFrame.Angles(0, 0, side * 0.18), shade)
		end
		block("Tail", Vector3.new(0.34, 0.34, 0.85), CFrame.new(0, 0.35, 1.05) * CFrame.Angles(math.rad(28), 0, 0), shade)
		block("Patch", Vector3.new(0.6, 0.5, 0.12), Vector3.new(-0.62, 1.78, -1.13), shade)
	elseif kind == "bunny" then
		for _, side in ipairs({ -1, 1 }) do
			block("Ear", Vector3.new(0.4, 1.5, 0.3), CFrame.new(side * 0.5, 3.05, -0.22) * CFrame.Angles(0, 0, side * 0.14), skin)
			block("EarInner", Vector3.new(0.2, 1.1, 0.12), CFrame.new(side * 0.5, 3.02, -0.4) * CFrame.Angles(0, 0, side * 0.14), lighten(Color3.fromRGB(255, 150, 190), 0.1))
		end
		block("Tail", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.15, 1.0), Color3.fromRGB(250, 250, 252))
	elseif kind == "dragon" then
		for _, side in ipairs({ -1, 1 }) do
			block("Horn", Vector3.new(0.28, 0.7, 0.28), CFrame.new(side * 0.6, 2.65, -0.1) * CFrame.Angles(0, 0, side * 0.3), lighten(Color3.fromRGB(255, 236, 190), 0.1))
			block("Wing", Vector3.new(0.16, 1.05, 1.25), CFrame.new(side * 1.02, 0.55, 0.35) * CFrame.Angles(0, 0, side * 0.35), lighten(skin, 0.3), nil, 0.08)
		end
		block("Snout", Vector3.new(0.7, 0.42, 0.3), Vector3.new(0, 1.02, -1.28), shade)
		block("Tail", Vector3.new(0.42, 0.42, 1.0), CFrame.new(0, 0.3, 1.1) * CFrame.Angles(math.rad(18), 0, 0), skin)
		block("TailSpike", Vector3.new(0.2, 0.55, 0.5), Vector3.new(0, 0.75, 1.6), lighten(Color3.fromRGB(255, 236, 190), 0.1))
		for i = 1, 3 do
			block("Spine", Vector3.new(0.16, 0.32, 0.26), Vector3.new(0, 0.82 + (i - 1) * 0.04, 0.2 + (i - 1) * 0.32), lighten(Color3.fromRGB(255, 236, 190), 0.1))
		end
	else -- blob: no ears, wider grin, one antenna. Reads as the odd one out on purpose.
		block("Antenna", Vector3.new(0.14, 0.6, 0.14), Vector3.new(0, 2.72, -0.2), shade)
		block("AntennaBulb", Vector3.new(0.36, 0.36, 0.36), Vector3.new(0, 3.06, -0.2), lighten(skin, 0.4), Enum.Material.Neon)
		block("Grin", Vector3.new(0.75, 0.12, 0.12), Vector3.new(0, 0.95, -1.15), OUTLINE)
		block("Tail", Vector3.new(0.55, 0.3, 0.5), Vector3.new(0, -0.2, 1.0), shade)
	end

	end -- of the blocky rig

	-- ---- rarity, read at a glance from the ring under the pet rather than from a label you have
	-- to stop and read
	local ring = Instance.new("Part")
	ring.Name = "RarityRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.22, 2.9, 2.9) * scale
	ring.Color = rarity.color
	-- COLOUR, NOT LIGHT (15.31). The ring was Neon and every Epic-and-above pet also carried a
	-- PointLight and a sparkle emitter -- with up to eight pets equipped that is eight self-lit discs
	-- and eight lights orbiting a body that is already lit, and the owner's report is that the
	-- character cannot be seen inside them. The ring keeps the rarity colour, which is the whole point
	-- of it, and lets the world's light decide how bright it is; the PointLight and the sparkle are
	-- gone entirely (see the block that used to follow this one).
	ring.Material = Enum.Material.SmoothPlastic
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = model
	addPiece(ring, CFrame.new(Vector3.new(0, -1.5, 0) * scale) * CFrame.Angles(0, 0, math.rad(90)))

	-- ---- fused pets wear their tier as a crown, so tier and rarity never compete for the same cue
	local tierMult = GameConfig.PetTierMultiplier[tier] or 1
	if tierMult > 1 then
		local crownColor = GameConfig.PetTierColor[tier] or Color3.fromRGB(255, 215, 60)
		-- Sits on the head of whichever rig this is: 2.58 is where the blocky head's crown line is,
		-- and a mesh species is however tall its mesh came out -- `block` multiplies these by scale,
		-- so the mesh's own height has to be divided back out of it.
		local crownY = 2.58
		if template then
			local geom = model:FindFirstChild("Geom")
			if geom then crownY = geom.Size.Y / scale - 1.3 end
		end
		-- Metal, not Neon (15.31): a fused pet's crown is the tier cue and it reads by its shape, which
		-- a self-lit material flattens away. Metal keeps the gold and gains an edge to see it by.
		block("CrownBand", Vector3.new(1.5, 0.24, 1.4), Vector3.new(0, crownY, -0.2), crownColor, Enum.Material.Metal)
		for i = -1, 1 do
			block("CrownSpike", Vector3.new(0.28, 0.44, 0.28), Vector3.new(i * 0.5, crownY + 0.27, -0.2), crownColor, Enum.Material.Metal)
		end
	end

	-- ---- the thick dark rim that makes the whole thing read as a drawing rather than as boxes.
	-- Occluded, not AlwaysOnTop: a pet behind a wall should not glow through it.
	--
	-- Off by default for anything decorative. Roblox renders only ~31 Highlights at a time, and
	-- the 60 pets standing on the egg podiums would eat the whole budget before the player's own
	-- pets -- the ones worth outlining -- ever got one.
	if opts.outline ~= false then
		local outline = Instance.new("Highlight")
		outline.Name = "Outline"
		outline.FillTransparency = 1
		outline.OutlineColor = OUTLINE
		outline.OutlineTransparency = 0
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Parent = model
	end

	if opts.nameplate ~= false then
		local plate = Instance.new("BillboardGui")
		plate.Name = "Nameplate"
		plate.Size = UDim2.new(0, 132, 0, 40)
		plate.StudsOffset = Vector3.new(0, 3.1 * scale, 0)
		plate.AlwaysOnTop = false
		plate.LightInfluence = 0
		plate.MaxDistance = opts.plateDistance or 55
		plate.Parent = body

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0.58, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextColor3 = Color3.fromRGB(255, 255, 255)
		name.TextStrokeColor3 = OUTLINE
		name.TextStrokeTransparency = 0
		name.Text = def.emoji .. " " .. def.name
		name.Parent = plate

		local rank = Instance.new("TextLabel")
		rank.Size = UDim2.new(1, 0, 0.42, 0)
		rank.Position = UDim2.new(0, 0, 0.58, 0)
		rank.BackgroundTransparency = 1
		rank.Font = Enum.Font.FredokaOne
		rank.TextScaled = true
		rank.TextColor3 = rarity.color
		rank.TextStrokeColor3 = OUTLINE
		rank.TextStrokeTransparency = 0
		rank.Text = tierMult > 1 and (tier .. " " .. rarity.name) or rarity.name
		rank.Parent = plate
	end

	model.PrimaryPart = body
	return model, body, pieces
end

-- Places a rig built above from a single CFrame. Kept here so every caller animates pets the
-- same way instead of each one re-deriving the offsets.
function PetModel.Place(root, pieces, cf)
	root.CFrame = cf
	for _, piece in ipairs(pieces) do
		if piece.p.Parent then
			piece.p.CFrame = cf * piece.cf
		end
	end
end

return PetModel
