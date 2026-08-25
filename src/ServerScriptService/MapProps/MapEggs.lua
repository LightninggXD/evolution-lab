-- MapProps/MapEggs -- the egg row stands in the middle of the square, on its own pedestals.
--
-- ===== THE ONE THING THAT MUST NOT CHANGE, AND WHY =====
-- `PetService.WireKiosks` finds the eggs by walking `zoneModel.PetShop` BY NAME and rewrites every
-- prompt it finds there. Rename that model, or reparent the eggs out of it, and egg buying and
-- Auto Hatch both die SILENTLY -- no error, no log, just a prompt that opens nothing. So the model
-- keeps its name and its parent, and the eggs stay its children. This file may move them, drop the
-- furniture around them and build a base under them; it may not rename or reparent one.
--
-- ===== HOW IT GOT HERE, BECAUSE EVERY STEP WAS THE OWNER CORRECTING THE LAST ONE =====
-- 30.20  *"a ova jaja su ogromna naspram ovog modela i mene"*. The eggs were never the problem --
--        ours are 18 studs, the map's own egg props 17.2, against an 8.4-stud player. THE STALL
--        WAS: `EggPlaza` builds a 123 x 47 x 45 market stand and drops it in the middle of the
--        square, so the eggs read as enormous because they stood on something five houses wide.
-- 30.24  *"i fontana nam ne treba tu nek jaja stoje umesto fontane"* -- the eggs take the centre
--        circle where the four roads meet, and the fountain and the four decorative egg props go.
-- 30.31  *"i ako vec malo lebde, nesto na cemu lebde"* -- a COLUMN is an egg plus its
--        `PriceCardAnchor` and `EggOddsAnchor`, and those offsets were authored while the egg
--        stood on a 17-stud incubator: the price card hangs 1.6 studs BELOW the egg's own bottom.
--        Seating the egg on the floor buried the card at y = -0.56. So the column is LIFTED onto a
--        pedestal instead, and the lift is derived from the column rather than typed.
-- 32.x   this pass: the ring opened out into a wide three-slot arc facing the arrival path, and
--        `EggPlaza`'s stone stumps were replaced by a low tiered pedestal with a lit ring.
--
-- 👤 AND ONE THING HERE IS THE OWNER'S TO CONFIRM, NOT AN AGENT'S TO ASSUME. `Reseat` now deletes
-- every `fence` within 45 studs of the fountain anchor. That ring is the pen 30.24 put the eggs
-- INSIDE, on her instruction -- *"jaja u centar ove ograde staviti"* -- and `EGG_RING` was 18
-- rather than 32 for exactly that reason. Deleting it is a reversal of that instruction, not a
-- tidy-up, and it is flagged here rather than argued away.
--
-- ===== COLUMNS, NOT PARTS =====
-- The stall's pieces are FLAT children of `PetShop` -- `EggOddsAnchor` and `PriceCardAnchor` are
-- siblings of the egg, not children of it -- so moving "the egg" alone would leave its own odds
-- board and price card hanging in the air. The pieces are grouped into columns by X first (the
-- generated row sits at x = -32, 0, +32) and a column is moved as one thing.

local MapAnchors = require(script.Parent.MapAnchors)
local MapPaint = require(script.Parent.MapPaint)

local MapEggs = {}

-- Stall furniture: scenery the map replaces. Prefix-matched, and anchored at the START of the
-- name for the same reason `ForestMapService.isDressing` is -- a substring match on "Egg" would
-- take `Egg` itself, which is the one thing here that must survive.
--
-- `Podium` IS ON THIS LIST AND IT HAS TO BE. `EggPlaza` parents four parts straight onto the
-- shop -- `PodiumStep` (12.6 across), `PodiumWaist`, `PodiumTop`, `PodiumHalo` -- and they are
-- the "glomazni panjevi" this pass exists to replace. Dropped to `EggPodium` only, nothing
-- matched them: they fell through to the column grouping and were MOVED, so every egg stood on
-- the old stone stump with the new pedestal built inside it. `EggPodium` stays as well, and
-- that one is this file's own idempotence -- a second `Reseat` must not stack a second base.
local STALL_PREFIX = {
	"Deck", "Plank", "Post", "Counter", "Sign", "Crate", "Barrel", "Basket", "Lantern",
	"Stall", "Podium", "EggPodium", "EggDisc", "EggOrbGem", "EggShadow",
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

-- How far the LOWEST piece of a column clears the ground. The piece this is for is the price card:
-- it was authored hanging 1.6 studs BELOW the egg's own bottom, so seating the egg on the floor
-- buries the card (30.31, measured at y = -0.56).
local PODIUM_CLEAR = 1.6
-- ...and how far the EGG's own bottom stands up, which is what decides whether there is a pedestal
-- under it at all. 2.0 was the number the modern-podium pass typed in, and it only ever looked
-- right because the lift was accumulating two studs on every rebuild -- seated honestly at 2.0 the
-- base is a yellow ring in the sand and the egg reads as dropped rather than displayed. 6 is the
-- height the three-tier base (0.35 plinth / 0.15 ring / 0.50 cap) needs to read as all three.
local PODIUM_MIN_H = 6.0
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

-- ===== A CARD IN THE WRONG BUCKET IS A CARD LEFT BEHIND =====
-- The columns are grouped by X, and `EggOddsAnchor` / `PriceCardAnchor` are SIBLINGS of the egg,
-- not children of it -- so an anchor authored a few studs off its egg lands in a bucket of its own,
-- which has no `Egg` in it and is skipped. Measured on the built world: 3 egg columns seated, **1
-- price card placed**, and the other two left standing where the stall used to be -- one of them
-- floating in front of the middle egg, which is what the capture shows.
--
-- So the bucket is a hint, not the answer. Anything still unmoved that belongs to an egg is adopted
-- by the nearest seated slot afterwards. Nothing is created and nothing is renamed here either --
-- `PetService.WireKiosks` is watching (see the header).
local ADOPT = { PriceCardAnchor = true, EggOddsAnchor = true }

-- 👤 OWNER DECISION, TAKEN 2026-08-25: `true` -- the fence ring comes OUT of the plaza. It stays a
-- named constant rather than being deleted along with the code, because 30.24 put the eggs inside
-- that pen on her own instruction and `false` is how the pen comes back in one line. Radius 45
-- about the fountain anchor.
local DROP_PLAZA_FENCE = true

local function adoptStrays(shop, claimed, slots)
	if #slots == 0 then return 0 end
	local n = 0
	for _, c in ipairs(shop:GetChildren()) do
		if ADOPT[c.Name] and not claimed[c] then
			local pos = centreOf(c)
			if pos then
				-- ONE CARD PER PODIUM. Nearest-slot alone put two of the three price cards on the
				-- same base and left the third podium bare -- two eggs with a price and one
				-- without, which is the same complaint in a new place. A slot that already holds
				-- this kind of anchor is out of the running.
				local best, bestD = nil, math.huge
				for _, sl in ipairs(slots) do
					if not sl[c.Name] then
						local d = (pos.X - sl.x) ^ 2 + (pos.Z - sl.z) ^ 2
						if d < bestD then best, bestD = sl, d end
					end
				end
				if not best then break end
				best[c.Name] = true
				local want
				if c.Name == "PriceCardAnchor" then
					want = CFrame.new(best.x, best.top + 0.8, best.z + best.r + 2.2)
				else
					-- the odds board reads over the egg's shoulder, not through it
					want = CFrame.new(best.x, best.top + best.eggH + 3.0, best.z - best.r - 1.0)
				end
				if c:IsA("Model") then c:PivotTo(want) else c.CFrame = want end
				n += 1
			end
		end
	end
	return n
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

	-- The plaza fence ring. 👤 SEE THE HEADER: 30.24 put the eggs INSIDE this pen on the owner's
	-- own instruction, and taking it out reverses that. It is one named constant so the answer is
	-- a one-line change either way and so a capture can be taken of both.
	local villageMap = zoneModel:FindFirstChild("VillageMap")
	if villageMap and fountain and DROP_PLAZA_FENCE then
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
	local claimed, slots = {}, {}
	if fountain then
		-- ===== THE SLOT IS COUNTED IN EGGS, NOT IN BUCKETS =====
		-- `order` holds every X bucket the shop's children fell into, and an `EggOddsAnchor` or a
		-- `PriceCardAnchor` a few studs off its egg makes a bucket of its own with no egg in it.
		-- Indexing `EGG_SLOTS` by the bucket number therefore skips slots: measured on the built
		-- world, three eggs came out at x -43 / -19 / +5 instead of -19 / +5 / +29 -- the whole row
		-- slid 24 studs sideways -- and one of them fell past the end of the table onto the
		-- `(i - 2) * 24` fallback. The counter below only moves when an egg is actually seated.
		local slotIndex = 0
		for _, key in ipairs(order) do
			local pieces = columns[key]
			local egg = nil
			for _, c in ipairs(pieces) do
				if c.Name == "Egg" then egg = c break end
			end
			local eggPos = egg and centreOf(egg)
			if eggPos then
				slotIndex += 1
				local slot = EGG_SLOTS[slotIndex] or { x = (slotIndex - 2) * 24, z = 0 }
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
				-- ===== THE LIFT IS A DESTINATION, NOT AN INCREMENT =====
				-- `math.max(..., PODIUM_MIN_H)` made this a RAISE of at least 2 studs however high
				-- the column already stood, and `Reseat` runs on every boot: measured over four
				-- rebuilds in one session the eggs climbed y 18 -> 22 -> 24 -> 26, two studs a
				-- time, with nothing in the log saying so. `MapEggs` destroys the podium at the top
				-- of the pass for exactly this reason; the column has to be seated the same way.
				--
				-- Both floors are absolute now: the lowest piece of the column clears the ground by
				-- `PODIUM_CLEAR` (the price card is the piece this is for -- it hangs 1.6 studs
				-- BELOW the egg's own bottom, see the header), and the egg's own bottom stands at
				-- least `PODIUM_MIN_H` up so the base reads as something rather than as a disc. Run
				-- twice on a seated column both terms are <= 0 and nothing moves.
				local eggLow = eggPos.Y - halfHeight(egg)
				local lift = math.max(groundY + PODIUM_CLEAR - columnLow,
					groundY + PODIUM_MIN_H - eggLow)

				local eggBottom = eggPos.Y - halfHeight(egg) + lift
				local bob = egg:GetAttribute("BobHeight") or 0
				local delta = Vector3.new(wantX - eggPos.X, lift, wantZ - eggPos.Z)
				-- The column rides up and across as one thing, but the two ANCHORS in it are not
				-- claimed here: they are seated by `adoptStrays` below, against the finished
				-- podium, in one pass over all three eggs. Seating them here as well is what put
				-- two price cards on one base -- two code paths writing the same CFrame, and the
				-- loser is whichever ran second.
				for _, c in ipairs(pieces) do
					moveBy(c, delta)
					if not ADOPT[c.Name] then claimed[c] = true end
				end

				local podiumRadius = eggSize(egg) / 2 + PODIUM_MARGIN
				local podiumTop = eggBottom - bob
				modernPodium(shop, wantX, wantZ, groundY, podiumTop, podiumRadius, dirtColour)

				slots[#slots + 1] = {
					x = wantX, z = wantZ, top = podiumTop, r = podiumRadius,
					eggH = halfHeight(egg) * 2,
				}
				moved += 1
				seated[#seated + 1] = ("%.1f/+%.1f"):format(groundY, lift)
			end
		end
		local adopted = adoptStrays(shop, claimed, slots)
		cards += adopted
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
