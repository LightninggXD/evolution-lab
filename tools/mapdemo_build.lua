-- tools/mapdemo_build.lua -- the layout demo Kristina asked for on 2026-08-21, in one file.
--
-- WHAT IT IS. A standalone hub built at x = -2400 (clear of zone 1, which spans x -625..625) out of
-- props CLONED from the free map she inserted into `workspace.Model`. It is a LOOK TEST, not a
-- zone: nothing requires it, nothing spawns in it, and `ZoneBuilder.Build()` neither creates nor
-- destroys it. Run it in EDIT, in two passes, from `execute_luau`.
--
-- WHY IT IS ON DISK AT ALL. An MCP build lives only in the unsaved Studio session and this one is
-- ~2,300 parts of hand-placed layout. If the demo is approved it becomes ZoneBuilder code; until
-- then this file is the only durable copy.
--
-- ===== THE FOUR RULES THE DEMO IS ACTUALLY DEMONSTRATING =====
--
-- 1. A CLEARING, NOT A FIELD. The plot is the real zone footprint (1250 x 1150) but the open middle
--    is an ellipse of only 320 x 285. v1 used 430 x 385 and the middle read as a lawn with a
--    fountain dropped on it; the enclosure is what makes it a place.
-- 2. SIX OVERLAPPING TREE BANDS, GROWING OUTWARD. Trees get bigger with every ring, so the belt has
--    a near and a far instead of being a wall of one size. Bands overlap on purpose: a band whose
--    trees merely touch still shows sky between them from a player-height camera.
-- 3. GROUPED BY KIND. Houses west, stall row east, all four stalls facing the plaza. A stall
--    standing between two houses reads as a mistake even when every object in frame is well made.
-- 4. CLUSTERS, NEVER SPRINKLE. Small props go in blobs at the foot of something big. Even scatter
--    is what the live zones do today and it is why their ground reads flat -- with nothing grouped
--    there is no near and no far, only texture.
--
-- ===== AND ONE THING THAT IS NOT LAYOUT AT ALL =====
-- `Atmosphere.Density` was 0.35 with `Haze` 0.55 and that, not the geometry, is what makes the
-- world look pale. Density is a PLACE PROPERTY -- no line in `src/` sets it, so it is exactly the
-- class of thing 18.x moved into code for `Ambient` and `ClockTime`. Measured at 0.18 / 0.16 the
-- same frame is crisp, with the shipped fog pair (1100..1900) untouched -- so the neighbouring zone
-- stays hidden. See ROADMAP 30.13.

local SRC = workspace:FindFirstChild("Model")

-- ============================ shared, needed by both passes ============================
local function prep(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ValueBase") then
			-- the free map's props carry their own scripts, prompts and BoolValues; a clone that
			-- keeps them is a second copy of somebody else's game running inside ours (30.0)
			d:Destroy()
		end
	end
	if inst:IsA("BasePart") then inst.Anchored = true end
end

-- SEATED ON THE GROUND BY MEASUREMENT, NOT BY PIVOT. A model's pivot is wherever the asset author
-- left it -- for these props it is usually the bounding-box centre, but not always -- so placing by
-- pivot buries half of them and floats the rest. Pivot once to get the yaw, measure the bounding
-- box, then lift by whatever the bottom is short of the ground.
local function place(tpl, pos, yaw, scale, collide, parent)
	local c = tpl:Clone()
	prep(c)
	if c:IsA("Model") then
		if scale and scale ~= 1 then c:ScaleTo(scale) end
		c:PivotTo(CFrame.new(pos.X, pos.Y, pos.Z) * CFrame.Angles(0, yaw, 0))
		local cf, size = c:GetBoundingBox()
		c:PivotTo(c:GetPivot() + Vector3.new(0, pos.Y - (cf.Y - size.Y / 2), 0))
	else
		if scale and scale ~= 1 then c.Size = c.Size * scale end
		c.CFrame = CFrame.new(pos + Vector3.new(0, c.Size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = collide and true or false end
	end
	if c:IsA("BasePart") then c.CanCollide = collide and true or false end
	c.Parent = parent
	return c
end

local CX, CZ = -2400, 0     -- demo centre, clear of zone 1
local W, D = 1250, 1150     -- the real zone footprint
local A, B = 320, 285       -- the clearing, and rule 1 above

-- ============================ PASS A: ground, roads, belt, backdrop ============================
local function passA()
	local rng = Random.new(30411)
	local T = { round = {}, conifer = {}, tall = {}, gora = {}, pine = {} }
	-- The map's trees have no useful names -- 256 of its children are called "Model" -- so they are
	-- identified by the SHAPE of their child list, which is stable and is what actually
	-- distinguishes them: {Top,Top} is the round tree, {Leaves,Branch} the conifer, {Bottom,Top}
	-- the tall one, {Meshes/gora,...} a mountain.
	for _, c in ipairs(SRC:GetChildren()) do
		if c:IsA("Model") then
			local s = {}
			for _, k in ipairs(c:GetChildren()) do s[k.Name] = (s[k.Name] or 0) + 1 end
			if c.Name == "Model" then
				if s["Top"] == 2 and #c:GetChildren() == 2 then table.insert(T.round, c)
				elseif s["Leaves"] and s["Branch"] then table.insert(T.conifer, c)
				elseif s["Bottom"] and s["Top"] then table.insert(T.tall, c)
				elseif s["Meshes/gora"] then table.insert(T.gora, c) end
			elseif c.Name == "Pine Tree 02" then table.insert(T.pine, c) end
		end
	end

	local old = workspace:FindFirstChild("MapDemo")
	if old then old:Destroy() end
	local root = Instance.new("Model") root.Name = "MapDemo" root.Parent = workspace
	local belt = Instance.new("Folder") belt.Name = "TreeBelt" belt.Parent = root

	local function slab(name, sx, sy, sz, x, y, z, color, mat)
		local p = Instance.new("Part")
		p.Name = name p.Anchored = true p.Size = Vector3.new(sx, sy, sz)
		p.Position = Vector3.new(x, y, z) p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = root
		return p
	end

	slab("Apron", 2600, 10, 2400, CX, -9, CZ, Color3.fromRGB(58, 138, 68), Enum.Material.Grass)
	slab("Ground", W, 10, D, CX, -5, CZ, Color3.fromRGB(101, 201, 96), Enum.Material.Grass)

	-- THE PLAZA AND THE ROADS OUT OF IT. One focal point with roads leaving it is the difference
	-- between props on a field and a place; every other position below is relative to these.
	local plaza = Instance.new("Part")
	plaza.Name = "Plaza" plaza.Anchored = true plaza.Shape = Enum.PartType.Cylinder
	plaza.Size = Vector3.new(1.2, 200, 200)
	plaza.CFrame = CFrame.new(CX, 0.3, CZ) * CFrame.Angles(0, 0, math.rad(90))
	plaza.Color = Color3.fromRGB(198, 192, 176) plaza.Material = Enum.Material.Concrete
	plaza.Parent = root
	local rim = plaza:Clone()
	rim.Name = "PlazaRim" rim.Size = Vector3.new(1.0, 224, 224)
	rim.CFrame = CFrame.new(CX, 0.15, CZ) * CFrame.Angles(0, 0, math.rad(90))
	rim.Color = Color3.fromRGB(162, 154, 138) rim.Parent = root

	slab("RoadSouth", 62, 1.0, 420, CX, 0.25, CZ + 300, Color3.fromRGB(190, 184, 168), Enum.Material.Concrete)
	slab("RoadSouthRim", 80, 0.8, 420, CX, 0.12, CZ + 300, Color3.fromRGB(156, 148, 132), Enum.Material.Concrete)
	slab("RoadEast", 230, 1.0, 50, CX + 205, 0.25, CZ, Color3.fromRGB(190, 184, 168), Enum.Material.Concrete)
	slab("RoadWest", 230, 1.0, 50, CX - 205, 0.25, CZ, Color3.fromRGB(190, 184, 168), Enum.Material.Concrete)

	local placed = 0
	local function beltBand(rFactor, count, scaleLo, scaleHi, mix, jitter)
		local step = math.pi * 2 / count
		for i = 0, count - 1 do
			local theta = i * step + rng:NextNumber(-step * 0.45, step * 0.45)
			local r = rFactor + rng:NextNumber(-(jitter or 0.05), (jitter or 0.05))
			local u, v = A * r * math.cos(theta), B * r * math.sin(theta)
			-- the avenue and the two side roads are kept clear by REJECTION rather than by drawing
			-- the belt as arcs: a rejected slot leaves a gap, and the gaps are where a road is
			local blocked = (math.abs(u) < 82 and v > 0 and r < 2.2)
				or (math.abs(v) < 48 and math.abs(u) < 330)
			if not blocked and math.abs(u) < W / 2 - 26 and math.abs(v) < D / 2 - 26 then
				local pool, roll = T.round, rng:NextNumber()
				if roll < mix[1] then pool = T.conifer
				elseif roll < mix[1] + mix[2] then pool = T.tall end
				if #pool > 0 then
					place(pool[rng:NextInteger(1, #pool)], Vector3.new(CX + u, 0, CZ + v),
						rng:NextNumber(0, 6.28), rng:NextNumber(scaleLo, scaleHi), false, belt)
					placed += 1
				end
			end
		end
	end

	beltBand(1.04, 30, 1.30, 1.70, { 0.34, 0.08 }, 0.04)
	beltBand(1.20, 34, 1.55, 2.00, { 0.32, 0.14 }, 0.05)
	beltBand(1.38, 38, 1.80, 2.30, { 0.30, 0.20 }, 0.05)
	beltBand(1.58, 42, 2.05, 2.60, { 0.28, 0.24 }, 0.06)
	beltBand(1.80, 46, 2.30, 2.90, { 0.26, 0.26 }, 0.06)
	beltBand(2.04, 44, 2.40, 3.10, { 0.24, 0.28 }, 0.07)

	-- small dark pines in the corners, where a 130-stud round tree would hang off the plot
	for _ = 1, 34 do
		local theta, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(1.9, 2.3)
		local u, v = A * r * math.cos(theta), B * r * math.sin(theta)
		if math.abs(u) < W / 2 - 18 and math.abs(v) < D / 2 - 18 and #T.pine > 0 then
			place(T.pine[rng:NextInteger(1, #T.pine)], Vector3.new(CX + u, 0, CZ + v),
				rng:NextNumber(0, 6.28), rng:NextNumber(2.6, 4.0), false, belt)
			placed += 1
		end
	end

	-- FOUR OVERSIZED TREES AT THE FRONT CORNERS. This is the reference photo's framing and it is
	-- the one placement here that is hand-picked rather than generated: a screenshot with nothing
	-- in its near plane has no depth however good the middle distance is.
	for _, spec in ipairs({ { -520, 470, 3.6 }, { -430, 530, 4.0 }, { 470, 500, 3.8 }, { 545, 430, 3.4 } }) do
		local pool = (rng:NextNumber() < 0.5) and T.conifer or T.round
		if #pool > 0 then
			place(pool[rng:NextInteger(1, #pool)], Vector3.new(CX + spec[1], 0, CZ + spec[2]),
				rng:NextNumber(0, 6.28), spec[3], false, belt)
			placed += 1
		end
	end

	-- THE BACKDROP IS OFF THE PLOT ENTIRELY, on the apron, and only behind and to the sides. It is
	-- a silhouette the clearing is read against; nothing here is ever walked on.
	local back = Instance.new("Folder") back.Name = "Backdrop" back.Parent = root
	if #T.gora > 0 then
		for _, spec in ipairs({
			{ -0.72, 1000, 2.4 }, { -0.30, 1080, 2.8 }, { 0.12, 1020, 2.5 }, { 0.55, 1120, 3.0 },
			{ 1.05, 980, 2.2 }, { 1.62, 1060, 2.7 }, { 2.20, 1000, 2.4 }, { 2.75, 1100, 2.9 },
			{ 3.30, 1020, 2.6 }, { 3.85, 1080, 2.8 },
		}) do
			place(T.gora[rng:NextInteger(1, #T.gora)],
				Vector3.new(CX + math.cos(spec[1]) * spec[2], -6, CZ + math.sin(spec[1]) * spec[2] * 0.9),
				rng:NextNumber(0, 6.28), spec[3], false, back)
		end
	end

	return ("pass A: %d trees, %d parts"):format(placed, #root:GetDescendants())
end

-- ============================ PASS B: the hub ============================
local function passB()
	local root = workspace:FindFirstChild("MapDemo")
	if not root then return "pass A did not run" end
	local rng = Random.new(77219)

	local T = { fence = {}, barrel = {}, bush = {}, stump = {}, rock = {}, flower = {},
		well = {}, stall = {}, crate = {}, house = nil, fountain = nil, sign = {} }
	for _, c in ipairs(SRC:GetChildren()) do
		if c:IsA("Model") then
			if c.Name == "Fence1" then table.insert(T.fence, c)
			elseif c.Name == "Barrel1" then table.insert(T.barrel, c)
			elseif c.Name == "Bush2" then table.insert(T.bush, c)
			elseif c.Name == "Stump" then table.insert(T.stump, c)
			elseif c.Name == "Well" then table.insert(T.well, c)
			elseif c.Name == "Sign1" then table.insert(T.sign, c)
			elseif c.Name == "Fountain" then T.fountain = c
			elseif c.Name:match("^Flower") then table.insert(T.flower, c)
			elseif c.Name == "Shop" then
				-- two different assets share the name "Shop": the 41-stud house (50 descendants)
				-- and the 12-stud market stall (23). Descendant count is what tells them apart.
				local n = #c:GetDescendants()
				if n > 40 then T.house = c elseif n > 15 then table.insert(T.stall, c) end
			end
		elseif c:IsA("BasePart") and c.Name:match("^Rock") then table.insert(T.rock, c)
		elseif c:IsA("MeshPart") and c.Name:match("^Meshes/Sell") then table.insert(T.crate, c) end
	end

	local hub = Instance.new("Folder") hub.Name = "Hub" hub.Parent = root
	local dress = Instance.new("Folder") dress.Name = "Dressing" dress.Parent = root

	if T.fountain then place(T.fountain, Vector3.new(CX, 0.4, CZ), 0, 2.2, true, hub) end

	-- NOTHING IS SQUARE TO THE ROAD. Every building below is a few degrees off axis, and that is
	-- most of why the reference does not read as placed by a script.
	if T.house then
		place(T.house, Vector3.new(CX - 232, 0, CZ - 92), math.rad(84), 2.6, true, hub)
		place(T.house, Vector3.new(CX - 244, 0, CZ + 96), math.rad(99), 2.3, true, hub)
	end
	if #T.stall > 0 then
		for i, spec in ipairs({ { -118, 0 }, { -40, 10 }, { 40, -8 }, { 118, 6 } }) do
			place(T.stall[((i - 1) % #T.stall) + 1],
				Vector3.new(CX + 214 + spec[2], 0, CZ + spec[1]), math.rad(-88 + (i - 2) * 3), 2.6, true, hub)
		end
	end
	if #T.well > 0 then
		place(T.well[1], Vector3.new(CX - 112, 0, CZ + 148), math.rad(24), 3.4, true, hub)
		place(T.well[math.min(2, #T.well)], Vector3.new(CX + 120, 0, CZ + 166), math.rad(-30), 3.4, true, hub)
	end

	-- A ROAD WITH NOTHING AT ITS EDGE IS A STRIPE ON GRASS. The fence is what makes it a road, and
	-- it is also the cheapest way to say "do not wander off here".
	if #T.fence > 0 then
		for i = 0, 9 do
			local z = CZ + 140 + i * 42
			for _, side in ipairs({ -1, 1 }) do
				place(T.fence[rng:NextInteger(1, #T.fence)],
					Vector3.new(CX + side * 48, 0, z), 0, 2.8, false, dress)
			end
		end
		-- a paddock in the north-east quarter, which gives that corner a reason to be empty
		for i = 0, 8 do
			local a = math.rad(186 + i * 21)
			place(T.fence[rng:NextInteger(1, #T.fence)],
				Vector3.new(CX + 250 + math.cos(a) * 96, 0, CZ - 250 + math.sin(a) * 96),
				a + math.pi / 2, 2.8, false, dress)
		end
	end

	local pond = Instance.new("Part")
	pond.Name = "Pond" pond.Anchored = true pond.CanCollide = false pond.Shape = Enum.PartType.Cylinder
	pond.Size = Vector3.new(1.4, 148, 104)
	pond.CFrame = CFrame.new(CX - 268, 0.5, CZ + 236) * CFrame.Angles(0, math.rad(18), math.rad(90))
	pond.Color = Color3.fromRGB(72, 168, 236) pond.Material = Enum.Material.SmoothPlastic
	pond.Parent = hub
	local pr = pond:Clone()
	pr.Name = "PondRim" pr.Size = Vector3.new(1.1, 172, 128)
	pr.CFrame = CFrame.new(CX - 268, 0.25, CZ + 236) * CFrame.Angles(0, math.rad(18), math.rad(90))
	pr.Color = Color3.fromRGB(142, 188, 124) pr.Parent = hub

	-- CLUSTERS -- rule 4, and the whole layout argument. sqrt() on the radius is what keeps a blob
	-- from piling up in its own middle: without it a uniform random radius is denser at the centre.
	local function cluster(x, z, n, radius, pools)
		for _ = 1, n do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = radius * math.sqrt(rng:NextNumber())
			local pool = pools[rng:NextInteger(1, #pools)]
			if #pool.t > 0 then
				place(pool.t[rng:NextInteger(1, #pool.t)],
					Vector3.new(x + math.cos(a) * d, 0, z + math.sin(a) * d),
					rng:NextNumber(0, 6.28), rng:NextNumber(pool.lo, pool.hi), false, dress)
			end
		end
	end

	local SMALL = { { t = T.bush, lo = 2.4, hi = 3.6 }, { t = T.flower, lo = 3.4, hi = 5.4 },
		{ t = T.rock, lo = 2.2, hi = 3.8 }, { t = T.stump, lo = 2.2, hi = 3.2 } }
	local YARD = { { t = T.barrel, lo = 2.6, hi = 3.6 }, { t = T.crate, lo = 2.2, hi = 3.2 },
		{ t = T.bush, lo = 2.2, hi = 3.0 } }

	cluster(CX - 160, CZ - 92, 7, 44, YARD)     -- what a shop has at its back door
	cluster(CX - 170, CZ + 100, 6, 42, YARD)
	cluster(CX + 172, CZ - 120, 5, 32, YARD)
	cluster(CX + 174, CZ + 48, 6, 34, YARD)
	for i = 0, 13 do                             -- the rim, where grass meets trees
		local a = math.rad(12 + i * 26)
		local u, v = math.cos(a) * 300, math.sin(a) * 268
		if not (math.abs(u) < 95 and v > 0) then
			cluster(CX + u, CZ + v, rng:NextInteger(5, 9), rng:NextInteger(30, 52), SMALL)
		end
	end
	cluster(CX - 268, CZ + 236, 12, 88, { { t = T.rock, lo = 2.6, hi = 4.4 }, { t = T.bush, lo = 2.4, hi = 3.2 } })
	for _ = 1, 6 do                              -- flower islands, so the open grass is not bare
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(130, 250)
		cluster(CX + math.cos(a) * d, CZ + math.sin(a) * d * 0.9, rng:NextInteger(4, 7), 26,
			{ { t = T.flower, lo = 3.6, hi = 5.8 } })
	end
	if #T.sign > 0 then
		place(T.sign[1], Vector3.new(CX + 66, 0, CZ + 126), math.rad(-150), 2.8, false, dress)
		place(T.sign[math.min(2, #T.sign)], Vector3.new(CX - 138, 0, CZ - 30), math.rad(70), 2.8, false, dress)
	end

	return ("pass B: hub=%d dressing=%d total=%d parts")
		:format(#hub:GetChildren(), #dress:GetChildren(), #root:GetDescendants())
end

return { PassA = passA, PassB = passB }
