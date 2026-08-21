-- tools/forest_map_preview.lua -- the Forest zone rebuilt as Kristina's inserted map, 2026-08-21.
--
-- WHAT THIS IS. A preview run in EDIT from `execute_luau`, in four steps, that turns zone 1 into
-- the free village map she inserted, with a hunting glade cut on one side of it. It is NOT the
-- shipping path: `ZoneBuilder.Build()` regenerates the whole zone from code on the next Play and
-- everything below is discarded. That is exactly why it is safe to run -- nothing here destroys
-- anything that exists only in the place.
--
-- ===== THE THREE MEASUREMENTS THE PREVIEW EXISTS TO TAKE =====
--
-- 1. THE MAP FITS, AND 1.45 IS NOT A FIT -- IT IS THE BODY. The map is drawn around a stock 5.7-stud
--    avatar. 30.14 froze our player at 1.45x one (~8.3 studs), so scaling the map by the same 1.45
--    is what makes a doorway, a fence and a market stall read to our player exactly as they read to
--    the avatar the artist drew them for. That the result (1208 x 972) then lands inside the
--    1250 x 1150 platform is luck, not design, and it is what makes the swap possible at all.
--
-- 2. THE MAP HAS ONE CLEARING AND THE ZONE NEEDS TWO. Everything that is not the village is solid
--    forest, so "mobs on one side" is a CUT, not a placement. The glade is an ellipse at (0, -200),
--    600 x 270, and it is cut BY WHOLE PROPS: half a tree left standing because its trunk was
--    outside the ellipse and its canopy inside is the thing that would read as broken. 161 props
--    came out, 452 stayed, and the floor under the whole ellipse is `MainPart` at y = 0 -- verified
--    by five downward rays rather than assumed.
--
-- 3. WHAT IS STILL WRONG IS EVERYTHING SIZED FOR THE OLD BODY. The Guardian Titan is 486 x 545 studs
--    and the zone idols are not much better; against the old 41-stud stage-20 player they were
--    landmarks, against 8.3 studs they ARE the "sve je ogromno naspram mene" complaint. Nineteen of
--    them are dropped here. The boundary wall (138 studs) is next and is not dropped, because
--    without it the zone has no edge at all -- that one belongs to the phase, not the preview.
--
-- ===== WHAT SURVIVES THE STRIP, AND WHY IT IS A NAME LIST =====
-- Anything a service looks up by name or a player has to touch. `ZoneService` finds `PortalGate` by
-- name in a one-shot scan; the eggs, the pet shop, the mystic pad and the zone pad are all touched.
-- Everything else in those 3,693 children is ZoneBuilder's dressing and is what the map replaces.

local KEEP = { "PortalGate", "PortalName", "Wall", "Egg", "Stall", "PetShop", "PropMystic",
	"ZonePad", "ZoneName", "Idol", "GuardianTitan", "Titan", "ArrivalSign", "SignBoard",
	"SignPost", "SignBatten", "SignLamp", "SignArrow", "SpawnLocation", "Atmosphere" }

local SCALE = 1.45              -- the body, not a fit -- see note 1
local GX, GZ, GA, GB = 0, -200, 300, 135   -- the hunting glade

-- ---------------------------------------------------------------- step 1: strip the dressing
local function strip()
	local forest = workspace.Zones:FindFirstChild("Forest")
	if not forest then return "no Forest" end
	local function keeps(name)
		for _, k in ipairs(KEEP) do if name:find(k) then return true end end
		return false
	end
	local removed = 0
	for _, c in ipairs(forest:GetChildren()) do
		if not keeps(c.Name) then removed += 1 c:Destroy() end
	end
	return ("stripped %d scenery children"):format(removed)
end

-- ---------------------------------------------------------------- step 2: drop the map in
local function insertMap()
	local forest = workspace.Zones:FindFirstChild("Forest")
	local SRC = workspace:FindFirstChild("Model")
	if not (forest and SRC) then return "missing Forest or Model" end
	local existing = forest:FindFirstChild("VillageMap")
	if existing then existing:Destroy() end

	local map = SRC:Clone()
	map.Name = "VillageMap"
	-- 30.0's rule: a free model's Scripts EXECUTE where they sit, and this one ships eight
	-- SpawnLocations that would steal every arrival in the game.
	local killed = 0
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			killed += 1 d:Destroy()
		elseif d:IsA("SpawnLocation") then
			d.Enabled = false d.Neutral = true
		end
	end
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	map:ScaleTo(SCALE)

	-- SEATED BY THE VILLAGE FLOOR, NOT BY THE BOUNDING BOX. The bounding box includes a mountain
	-- ring reaching ~100 studs below ground; centring on it sinks the whole village.
	local floor
	for _, c in ipairs(map:GetChildren()) do if c.Name == "MainPart" then floor = c break end end
	if not floor then return "no MainPart in the map" end
	local floorTop = floor.Position.Y + floor.Size.Y / 2
	map:PivotTo(map:GetPivot() + Vector3.new(-floor.Position.X, -floorTop, -floor.Position.Z))
	map.Parent = forest

	local _, size = map:GetBoundingBox()
	return ("VillageMap: %d parts, %.0f x %.0f x %.0f, floor %.0f x %.0f, %d scripts removed")
		:format(#map:GetDescendants(), size.X, size.Y, size.Z, floor.Size.X, floor.Size.Z, killed)
end

-- ---------------------------------------------------------------- step 3: cut the glade
local function cutGlade()
	local map = workspace.Zones.Forest:FindFirstChild("VillageMap")
	if not map then return "no VillageMap" end
	local dropped = 0
	for _, c in ipairs(workspace.Zones.Forest:GetChildren()) do
		if c.Name:find("Titan") or c.Name:find("Idol") then dropped += 1 c:Destroy() end
	end
	local function inGlade(p)
		local dx, dz = (p.X - GX) / GA, (p.Z - GZ) / GB
		return dx * dx + dz * dz <= 1
	end
	local cleared = 0
	for _, c in ipairs(map:GetChildren()) do
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			local cf
			if c:IsA("Model") then cf = c:GetBoundingBox() elseif c:IsA("BasePart") then cf = c.CFrame end
			if cf and inGlade(cf.Position) then c:Destroy() cleared += 1 end
		end
	end
	return ("dropped %d oversized props, cleared %d from the glade"):format(dropped, cleared)
end

-- ---------------------------------------------------------------- step 4: stand the mobs in it
local function mobs()
	local forest = workspace.Zones.Forest
	local old = forest:FindFirstChild("MobSide")
	if old then old:Destroy() end
	local side = Instance.new("Folder") side.Name = "MobSide" side.Parent = forest
	local rng = Random.new(4711)

	local function blob(name, pos, height, body, accent)
		local m = Instance.new("Model") m.Name = name
		local torso = Instance.new("Part")
		torso.Name = "Body" torso.Anchored = true
		torso.Size = Vector3.new(height * 0.78, height * 0.72, height * 0.66)
		torso.Position = pos + Vector3.new(0, height * 0.40, 0)
		torso.Color = body torso.Material = Enum.Material.SmoothPlastic
		torso.Parent = m
		-- Block + SpecialMesh(Sphere), never Shape=Ball: a non-uniform Ball is silently drawn as a
		-- sphere of its SMALLEST axis, so a squat creature comes out round and a third of its size.
		local mesh = Instance.new("SpecialMesh") mesh.MeshType = Enum.MeshType.Sphere mesh.Parent = torso
		for _, sx in ipairs({ -1, 1 }) do
			local eye = Instance.new("Part")
			eye.Name = "Eye" eye.Anchored = true eye.CanCollide = false
			eye.Size = Vector3.new(height * 0.17, height * 0.17, height * 0.17)
			eye.Position = torso.Position + Vector3.new(sx * height * 0.19, height * 0.13, height * 0.30)
			eye.Color = Color3.fromRGB(24, 24, 32) eye.Material = Enum.Material.Neon
			local em = Instance.new("SpecialMesh") em.MeshType = Enum.MeshType.Sphere em.Parent = eye
			eye.Parent = m
		end
		local crest = Instance.new("Part")
		crest.Name = "Crest" crest.Anchored = true crest.CanCollide = false
		crest.Size = Vector3.new(height * 0.11, height * 0.36, height * 0.11)
		crest.Position = torso.Position + Vector3.new(0, height * 0.47, -height * 0.06)
		crest.Color = accent crest.Material = Enum.Material.SmoothPlastic
		crest.Parent = m
	end

	-- THE SIZES ARE THE POINT. The fixed player is 8.3 studs, so a critter is 6, a brute 11, an
	-- elite 16. Nothing out here is a landmark any more, which is the whole complaint 30.14 answers.
	local TIERS = {
		{ name = "Critter", h = 6.0,  n = 16, body = Color3.fromRGB(150, 210, 120), accent = Color3.fromRGB(88, 158, 78) },
		{ name = "Brute",   h = 11.0, n = 7,  body = Color3.fromRGB(120, 170, 220), accent = Color3.fromRGB(68, 108, 178) },
		{ name = "Elite",   h = 16.0, n = 3,  body = Color3.fromRGB(220, 140, 200), accent = Color3.fromRGB(158, 78, 148) },
	}
	local made = 0
	for _, tier in ipairs(TIERS) do
		for _ = 1, tier.n do
			-- rejection against the SAME ellipse the glade was cut with, so nothing stands in a
			-- tree. sqrt on the radius keeps the pack from piling into the middle.
			local a = rng:NextNumber(0, math.pi * 2)
			local r = math.sqrt(rng:NextNumber()) * 0.88
			blob(tier.name, Vector3.new(GX + math.cos(a) * GA * r, 0, GZ + math.sin(a) * GB * r),
				tier.h, tier.body, tier.accent)
			made += 1
		end
	end
	return ("%d creatures inside the glade"):format(made)
end

return { Strip = strip, InsertMap = insertMap, CutGlade = cutGlade, Mobs = mobs }
