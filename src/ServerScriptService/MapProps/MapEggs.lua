-- MapProps/MapEggs -- Modern, spacious egg showcase layout.
--
-- Replaces cramped circular arrangement with modern simulator-style presentation:
-- - Generously spaced 3-egg row/arc facing the village arrival path.
-- - Clean, sleek low-profile tiered pedestals with golden/neon accent trim.
-- - Leftover fountain fences removed for open, unobstructed player movement.
-- - Price cards and odds boards aligned cleanly for immediate readability.

local MapAnchors = require(script.Parent.MapAnchors)
local MapPaint = require(script.Parent.MapPaint)

local MapEggs = {}

local STALL_PREFIX = {
	"Deck", "Plank", "Post", "Counter", "Sign", "Crate", "Barrel", "Basket", "Lantern",
	"Stall", "EggPodium", "EggDisc", "EggOrbGem", "EggShadow",
}

local KEEP = {
	Egg = true, PriceCardAnchor = true, EggOddsAnchor = true, FeaturePet = true,
}

-- ===== MODERN SPACIOUS EGG SLOTS =====
-- Wide 24-stud spacing in an elegant welcoming arc facing the village square entrance
local EGG_SLOTS = {
	{ x = -24, z = -4 },
	{ x = 0, z = 0 },
	{ x = 24, z = -4 },
}

local PODIUM_CLEAR = 1.6
local PODIUM_MIN_H = 2.0
local PODIUM_MARGIN = 1.0
local CIRCLE_D = 120
local CIRCLE_Y = 0.10
local CIRCLE_THICK = 1.4
local RIM_EXTRA = 6
local RIM_Y = -0.06
local RIM_SHADE = 0.42

local function isStall(name)
	if KEEP[name] then return false end
	for _, p in ipairs(STALL_PREFIX) do
		if name:sub(1, #p) == p then return true end
	end
	return false
end

local function centreOf(inst)
	if inst:IsA("Model") then
		return inst:GetBoundingBox().Position
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

local function halfHeight(inst)
	if inst:IsA("Model") then
		local _, size = inst:GetBoundingBox()
		return size.Y / 2
	elseif inst:IsA("BasePart") then
		return inst.Size.Y / 2
	end
	return 0
end

local function eggSize(inst)
	if inst:IsA("Model") then
		local _, size = inst:GetBoundingBox()
		return math.max(size.X, size.Z)
	elseif inst:IsA("BasePart") then
		return math.max(inst.Size.X, inst.Size.Z)
	end
	return 0
end

-- ===== SLEEK MODERN PODIUM =====
-- Clean tiered showcase base with a subtle gold accent ring
local function modernPodium(parent, x, z, groundY, topY, radius, dirtColour)
	local totalH = math.max(topY - groundY, 1.8)
	local baseH = totalH * 0.35
	local ringH = totalH * 0.15
	local capH = totalH * 0.50

	local function cylinderPart(name, r, h, centerY, color, mat)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(h, r * 2, r * 2)
		p.CFrame = CFrame.new(x, centerY, z) * CFrame.Angles(0, 0, math.pi / 2)
		p.Anchored = true
		p.CanCollide = true
		p.CastShadow = false
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Parent = parent
		return p
	end

	-- 1. Dark bottom plinth
	cylinderPart("EggPodiumBase", radius + 1.6, baseH, groundY + baseH / 2,
		MapPaint.Shade(dirtColour, 0.45), Enum.Material.Slate)

	-- 2. Golden accent ring
	cylinderPart("EggPodiumRing", radius + 1.0, ringH, groundY + baseH + ringH / 2,
		Color3.fromRGB(255, 215, 0), Enum.Material.Neon)

	-- 3. Sleek top surface
	cylinderPart("EggPodiumTop", radius + 0.4, capH, groundY + baseH + ringH + capH / 2,
		dirtColour:Lerp(Color3.new(1, 1, 1), 0.25), Enum.Material.SmoothPlastic)

	return 3
end

-- Position price cards cleanly facing front (+Z)
local function seatPriceCard(pieces, wantX, wantZ, podiumRadius, podiumTop)
	for _, c in ipairs(pieces) do
		if c.Name == "PriceCardAnchor" and c:IsA("BasePart") then
			c.CFrame = CFrame.new(wantX, podiumTop + 0.8, wantZ + podiumRadius + 2.2)
			return 1
		end
	end
	return 0
end

local ANCHOR_ATTR = { Egg = "IdleAnchor", FeaturePet = "SpinAnchor" }

local function moveBy(inst, delta)
	if inst:IsA("Model") then
		inst:PivotTo(inst:GetPivot() + delta)
	elseif inst:IsA("BasePart") then
		inst.CFrame = inst.CFrame + delta
	end
	local attr = ANCHOR_ATTR[inst.Name]
	if attr then
		local cf = inst:GetAttribute(attr)
		if typeof(cf) == "CFrame" then
			inst:SetAttribute(attr, cf + delta)
		end
	end
end

function MapEggs.Reseat(zoneKey, zoneModel)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end
	local shop = zoneModel and zoneModel:FindFirstChild("PetShop")
	if not shop then return 0 end

	for _, c in ipairs(shop:GetChildren()) do
		if c.Name:sub(1, 9) == "EggPodium" then c:Destroy() end
	end

	local columns, order = {}, {}
	local dropped = 0
	for _, c in ipairs(shop:GetChildren()) do
		if isStall(c.Name) then
			c:Destroy()
			dropped += 1
		else
			local pos = centreOf(c)
			if pos then
				local key = math.floor(pos.X / 4 + 0.5) * 4
				if not columns[key] then
					columns[key] = {}
					order[#order + 1] = key
				end
				table.insert(columns[key], c)
			end
		end
	end
	table.sort(order)

	local fountain = MapAnchors.Get(zoneKey, "fountain")
	local removed = 0
	if fountain and fountain.inst then
		fountain.inst:Destroy()
		removed += 1
	end
	for _, name in ipairs(MapAnchors.EGGS) do
		local anchor = MapAnchors.Get(zoneKey, "egg", name)
		if anchor and anchor.inst and anchor.inst.Parent then
			anchor.inst:Destroy()
			removed += 1
		end
	end

	-- Remove any leftover fences in the plaza to keep the egg area open and clean
	local villageMap = zoneModel:FindFirstChild("VillageMap")
	if villageMap and fountain then
		for _, c in ipairs(villageMap:GetChildren()) do
			if c.Name:lower():find("fence") then
				local cf = c:IsA("Model") and c:GetBoundingBox() or c.CFrame
				if cf and ((cf.Position.X - fountain.pos.X)^2 + (cf.Position.Z - fountain.pos.Z)^2) < 45^2 then
					c:Destroy()
					removed += 1
				end
			end
		end
	end

	local dirtColour = villageMap and MapPaint.DirtColour(villageMap) or MapPaint.DIRT_FALLBACK
	local fountainTop = fountain and fountain.top or nil
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { shop }
	rayParams.IgnoreWater = true

	local moved, cards, seated = 0, 0, {}
	if fountain then
		for i, key in ipairs(order) do
			local slot = EGG_SLOTS[i] or { x = (i - 2) * 24, z = 0 }
			local pieces = columns[key]
			local egg = nil
			for _, c in ipairs(pieces) do
				if c.Name == "Egg" then egg = c break end
			end
			local eggPos = egg and centreOf(egg)
			if eggPos then
				local wantX = fountain.pos.X + slot.x
				local wantZ = fountain.pos.Z + slot.z

				local columnLow = math.huge
				for _, c in ipairs(pieces) do
					local cp = centreOf(c)
					if cp then columnLow = math.min(columnLow, cp.Y - halfHeight(c)) end
				end

				local hit = workspace:Raycast(Vector3.new(wantX, 300, wantZ),
					Vector3.new(0, -600, 0), rayParams)
				local groundY = hit and hit.Position.Y or fountainTop or 0
				local lift = math.max(groundY + PODIUM_CLEAR - columnLow, PODIUM_MIN_H)

				local eggBottom = eggPos.Y - halfHeight(egg) + lift
				local bob = egg:GetAttribute("BobHeight") or 0
				local delta = Vector3.new(wantX - eggPos.X, lift, wantZ - eggPos.Z)
				for _, c in ipairs(pieces) do
					moveBy(c, delta)
				end

				local podiumRadius = eggSize(egg) / 2 + PODIUM_MARGIN
				local podiumTop = eggBottom - bob
				modernPodium(shop, wantX, wantZ, groundY, podiumTop, podiumRadius, dirtColour)

				cards += seatPriceCard(pieces, wantX, wantZ, podiumRadius, podiumTop)
				moved += 1
				seated[#seated + 1] = ("%.1f/+%.1f"):format(groundY, lift)
			end
		end
	else
		warn("[MapEggs] " .. zoneKey .. ": no fountain anchor -- the eggs were left where they were")
	end

	-- Paint the clean plaza disc under the eggs
	local circle = 0
	if fountain then
		local map = zoneModel:FindFirstChild("VillageMap")
		if map then
			local old = map:FindFirstChild("EggCircle")
			if old then old:Destroy() end
			local folder = Instance.new("Folder")
			folder.Name = "EggCircle"
			folder.Parent = map
			local dirt = MapPaint.DirtColour(map)
			circle += MapPaint.Disc(fountain.pos.X, fountain.pos.Z, CIRCLE_D + RIM_EXTRA, folder, 0,
				MapPaint.Shade(dirt, RIM_SHADE), RIM_Y, CIRCLE_THICK, true)
			circle += MapPaint.Disc(fountain.pos.X, fountain.pos.Z, CIRCLE_D, folder, 0, dirt,
				CIRCLE_Y, CIRCLE_THICK, true)
			for _, part in ipairs(folder:GetChildren()) do
				part.CanQuery = false
			end
		end
	end

	print(("[MapEggs] %s: dropped %d stall pieces, seated %d egg columns in modern row (ground/lift %s), placed %d price cards, removed %d props, painted %d circle parts")
		:format(zoneKey, dropped, moved, table.concat(seated, " "), cards, removed, circle))
	return moved
end

return MapEggs
