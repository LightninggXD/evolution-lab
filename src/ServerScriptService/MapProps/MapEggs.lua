-- MapProps/MapEggs -- the egg row moves onto the map's own egg spots, and the stall around it goes.
--
-- The owner, with a screenshot: *"a ova jaja su ogromna naspram ovog modela i mene"*. Measured, the
-- eggs are not the problem: ours are 18 studs and the map's own egg props are 17.2, against an
-- 8.4-stud player. THE STALL IS. `EggPlaza` builds a 123 x 47 x 45 market stand -- deck, planks,
-- posts, counter, sign board, crates, barrels, baskets, lanterns and three lit podiums -- and drops
-- it at (0, -6), which is the middle of the village square. That is what makes the eggs read as
-- enormous: they are standing on a structure five houses wide.
--
-- This is row 30.20, which 30.19 left open with the note "the PetShop is still standing in the map's
-- own market row".
--
-- ===== WHAT IT DOES =====
-- Keeps the eggs and everything welded to their meaning -- the shell, its ProximityPrompt, the
-- feature pet, the odds board and the price card -- and moves each of them, as a column, onto one of
-- the four egg spots the map's artist already chose along the northern edge of the square, where the
-- entrance road arrives. Then it deletes the stall and our podiums, because the map's egg prop was
-- the podium all along.
--
-- ===== THE ONE THING THAT MUST NOT CHANGE, AND WHY =====
-- `PetService.WireKiosks` finds the eggs by walking `zoneModel.PetShop` BY NAME and rewrites every
-- prompt it finds there. Rename that model, or reparent the eggs out of it, and egg buying and Auto
-- Hatch both die silently -- no error, no log, just a prompt that opens nothing. So the model keeps
-- its name and its parent, and only its CONTENTS move. Everything here is a `PivotTo` or a
-- `Destroy`; nothing is created and nothing is renamed.
--
-- ===== 30.24: AND THEN THE FOUNTAIN WENT AND THEY TOOK THE MIDDLE =====
-- *"i fontana nam ne treba tu nek jaja stoje umesto fontane znaci"*, and it is the centre circle in
-- the owner's own drawing of the zone: a round plaza where the four roads meet, with the eggs
-- standing in it. So the three columns move a second time -- off the artist's egg row on the
-- northern edge and onto a 32-stud ring around the `fountain` anchor -- the fountain is destroyed,
-- and the four map egg props go with it, because three real eggs and four decorative ones in two
-- different places is a player walking up to the wrong egg.
--
-- THE MOVE IS XZ ONLY. 31.7 took a full 3D delta because it was landing a column on another prop's
-- own spot; the fountain's centre is 12 studs up inside a 52-stud basin, and a 3D delta onto it
-- would hang all three eggs in the air. Their height is already right -- it was measured in 31.7
-- and the square is one flat floor -- so only two of the three axes move.
--
-- ===== COLUMNS, NOT PARTS =====
-- The stall's pieces are FLAT children of `PetShop` -- `EggOddsAnchor` and `PriceCardAnchor` are
-- siblings of the egg, not children of it -- so moving "the egg" alone would leave its own odds
-- board and price card hanging in the air over an empty deck. The pieces are grouped into columns by
-- X first (the generated row sits at x = -32, 0, +32) and a column is moved as one thing.

local MapAnchors = require(script.Parent.MapAnchors)
local MapPaint = require(script.Parent.MapPaint)

local MapEggs = {}

-- Stall furniture: scenery the map replaces. Prefix-matched, and anchored at the START of the name
-- for the same reason `ForestMapService.isDressing` is -- a substring match on "Egg" would take
-- `Egg` itself, which is the one thing here that must survive.
local STALL_PREFIX = {
	"Stall", "Podium", "EggDisc", "EggOrbGem",
}

-- ...and the names that must never be dropped whatever a prefix says. `Egg` is the shell and the
-- model's own meaning; the other three ride with it.
local KEEP = {
	Egg = true, FeaturePet = true, EggOddsAnchor = true, PriceCardAnchor = true,
}

-- ===== THE CENTRE CIRCLE =====
-- The eggs stand on a ring inside it, the first of them facing NORTH -- the way the entrance road
-- arrives -- so a player walking in from the plaza meets an egg head on with the other two behind
-- it to either side, rather than three in profile.
-- 18, not 32. The map draws a low fence ring of radius ~28 about the square's centre and at 32 the
-- eggs stood just OUTSIDE it, which is what *"jaja u centar ove ograde staviti"* is about. At 18
-- all three are inside the pen, and three 18-stud eggs on that ring still stand 37 studs apart.
local EGG_RING = 18
local EGG_ANGLES = { math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6 }
-- The paint under them. The disc is what makes the junction a roundabout instead of a hole where a
-- fountain used to be -- `MapGates` deliberately stops its south lane at z = -30 and `MapRoad` its
-- approach at z = 40, both to avoid painting under the fountain, and this is what now joins them.
--
-- ITS PLANE IS THE VILLAGE'S, NOT THE JUNGLE'S, and that is the one number here that cannot be
-- guessed: `MapPaint.Y` (0.25, top at 0.45) is drawn on bare platform at y = 0 and would be BURIED
-- under the map's own 0.6-stud ground union. `MapGates` paints the village at top 0.80 with 1.4 of
-- depth, i.e. a centre of 0.10, and the rim below it at 0.72. Same two planes, same reason.
-- ===== THE EGGS STAND ON A PODIUM, AND IT IS NOT DECORATION (30.31) =====
-- 30.25 seated each egg's own bottom on the ground, which was right about the egg and wrong about
-- everything welded to it. A COLUMN is an egg plus a `PriceCardAnchor` and an `EggOddsAnchor`, and
-- those offsets were authored while the egg stood on a 17-stud incubator -- the price card hangs
-- 1.6 studs BELOW the egg's own bottom. Drop the egg to the floor and the price card goes under it:
-- measured on the live build at **y = -0.56**, buried, which is exactly the owner's *"i cene"*.
--
-- Her own suggestion is the fix -- *"i ako vec malo lebde, nesto na cemu lebde"*. The egg is lifted
-- onto a podium instead of being pushed into the dirt, so the whole column rides up with it and the
-- price card clears the ground by two studs. The lift is DERIVED from the column rather than typed:
-- it is whatever it takes to put the lowest piece of the column at `PODIUM_CLEAR` above the floor,
-- so a re-authored egg prop moves its own podium without anybody re-measuring.
local PODIUM_CLEAR = 2.0
-- ...and the podium is at least this tall whatever the column asks for, because a 0.5-stud plinth
-- reads as an egg sunk in the ground rather than as an egg standing on something.
local PODIUM_MIN_H = 4.0
-- 2.0, and the floor under it was dropped. Measured on the live build the egg shells are only
-- 10..12 studs across -- not the 17 the stall-era comments assume -- so a margin of 4 over a floor
-- of 12 gave a 20-stud plinth under an 11-stud egg: the egg read as a pebble left on a table, and
-- from the square the nearest podium looked empty. The podium should be read as the egg's own base.
local PODIUM_MARGIN = 2.0
local CIRCLE_D = 132
local CIRCLE_Y = 0.10
local CIRCLE_THICK = 1.4
-- 6, not 14. A rim is an OUTLINE: seven studs of it on the radius of a 132-stud circle is the wide
-- dark band the owner photographed lying across the square, because the three village lanes stop
-- at the circle's edge and the rim carries on past them. Same arithmetic as the camp clearings and
-- the approach road, all three fixed together in 30.26.
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

-- The half-height of a piece, so a column can be seated by its FEET rather than by its centre.
local function halfHeight(inst)
	if inst:IsA("Model") then
		local _, size = inst:GetBoundingBox()
		return size.Y / 2
	elseif inst:IsA("BasePart") then
		return inst.Size.Y / 2
	end
	return 0
end

-- The wider of a piece's two horizontal extents, so a podium is sized off the shell it carries
-- rather than off a number typed here.
local function eggSize(inst)
	if inst:IsA("Model") then
		local _, size = inst:GetBoundingBox()
		return math.max(size.X, size.Z)
	elseif inst:IsA("BasePart") then
		return math.max(inst.Size.X, inst.Size.Z)
	end
	return 0
end

-- ===== THE PODIUM =====
-- Two cylinders: a dark plinth and a brighter cap sitting a little proud of it. That is the outline
-- tier from `evolution-lab-chunky-look-rules` -- draw the dark edge first and the bright mass inside
-- it -- and it is the same two-part recipe the camp clearings use, at a different scale.
--
-- It CARRIES the egg, so unlike everything else this file touches it collides: an egg standing on a
-- plinth you can walk through is an egg standing in mid-air. `CanQuery` stays on for the same
-- reason -- a placement search should see this as occupied ground, because it is.
local PODIUM_LIP = 1.2        -- how far the dark plinth stands out past the cap
local PODIUM_SHADE = 0.42

local function podium(parent, x, z, groundY, topY, radius, colour)
	local height = math.max(topY - groundY, 0.6)
	local function tier(name, r, h, centreY, c)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(h, r * 2, r * 2)
		-- a Cylinder's length runs down its X axis, so it is stood on end by a quarter turn on Z
		p.CFrame = CFrame.new(x, centreY, z) * CFrame.Angles(0, 0, math.pi / 2)
		p.Anchored = true
		p.CanCollide = true
		p.CastShadow = false
		p.Color = c
		p.Material = Enum.Material.Slate
		p.Parent = parent
		return p
	end
	tier("EggPodiumBase", radius + PODIUM_LIP, height, groundY + height / 2,
		MapPaint.Shade(colour, PODIUM_SHADE))
	-- the cap is shorter, so the dark plinth shows as a rim beneath it rather than around it
	tier("EggPodiumTop", radius, height * 0.72, groundY + height * 0.72 / 2 + height * 0.28, colour)
	return 2
end

-- ===== THE PRICE CARD IS PLACED OFF THE PODIUM, NOT CARRIED FROM THE STALL (30.29) =====
-- The card is the one piece of a column whose authored offset cannot survive the move, and 30.31
-- made that worse rather than better. `EggPlaza` builds it at `z = +7.4` from its egg because the
-- stall was a straight row facing +Z: every card sat 7.4 studs in FRONT of its shell. Out on a ring
-- that offset is not radial at all. Measured on the live client before this fix, the three cards
-- were 7.4 studs from their own egg's axis on a bearing of +Z regardless of where the egg stood --
-- radial distances of 25.4, 15.7 and 15.7 from a ring of 18 -- so the north card pointed outward
-- and the other two pointed sideways, INTO the circle.
--
-- And 7.4 is now inside the furniture. The plinth is sized off the shell (`eggSize / 2 +
-- PODIUM_MARGIN`, plus `PODIUM_LIP`) and measured 8.2 .. 9.1 studs of radius, with its cap top at
-- y = 7.95; the anchors were at y = 6.80, a full stud BELOW the cap and well within it. The
-- billboard is `AlwaysOnTop = false` on purpose, so geometry occludes it -- what the capture showed
-- was the top sliver of a 4-stud pill poking out of the plinth. That is 30.31's own fault at a new
-- radius, the same class of stale constant as the height 30.25 paid for, so the offset is DERIVED
-- here from the podium that was just built rather than inherited from the stall.
--
-- Two numbers, both relative to the podium, so a re-authored egg carries its card with it:
-- outward along the egg's own bearing from the ring centre, clear of the plinth's outer edge...
local PRICE_CARD_GAP = 1.5
-- ...and lifted so the pill's bottom edge grazes the cap. The billboard is 4 studs tall with a
-- `StudsOffset` of +0.6, so its bottom sits at `anchor + 0.6 - 2`: at +1.6 the card spans the cap
-- top to four studs above it, alongside the egg's lower third rather than across its face.
local PRICE_CARD_LIFT = 1.6
-- The lift is also what settles the fence. `EGG_RING + 9.1 + 1.5` lands the card at a radius of
-- ~28.6 and the map's own fence ring measures r 27.6 .. 29.6 -- the card hangs directly over it.
-- That is fine, and it is why this is a lift rather than a bigger gap: every piece of that ring,
-- fence, posts and all, tops out at y = 6.3 while the card starts at ~8. Pushing it further out
-- instead would only walk it into the road beyond.
--
-- `EggOddsAnchor` is deliberately left on the delta: it is authored on the egg's own centre line
-- (z = 0) with no radial component to be wrong about, and it rides at y = 39.6, far above all of
-- this. A piece that was already right does not need a second rule.
local function seatPriceCard(pieces, cx, cz, angle, outerRadius, podiumTop)
	for _, c in ipairs(pieces) do
		if c.Name == "PriceCardAnchor" and c:IsA("BasePart") then
			local r = EGG_RING + outerRadius + PRICE_CARD_GAP
			c.CFrame = CFrame.new(cx + math.cos(angle) * r,
				podiumTop + PRICE_CARD_LIFT,
				cz + math.sin(angle) * r)
			return 1
		end
	end
	return 0
end

-- ===== 30.32: AND THE ANCHOR ATTRIBUTE MOVES WITH THE PIECE, OR NOTHING MOVED AT ALL =====
-- `PetFollowClient` does not READ an egg's CFrame. It WRITES it, on every client, on every frame,
-- from the model's own `IdleAnchor` attribute -- the bob, the rock and the turntable spin are all
-- layered on that one stored CFrame, and a `FeaturePet` is driven the same way off `SpinAnchor`.
-- So a column moved by `PivotTo` alone is moved on the server and put straight back by every client
-- on the next frame.
--
-- THAT IS WHY 30.31 MEASURED PERFECT AND SHE PHOTOGRAPHED THREE EGGS BESIDE THEIR PODIUMS. On the
-- server every egg bottom sat on its podium top to within two hundredths of a stud; on her screen
-- the eggs were still standing in the old stall row at x = -32 / 0 / +32, z = 0, with three empty
-- plinths out on the ring. The price cards, the odds boards and the podiums are plain parts and had
-- all replicated correctly, which is exactly what made it read as "the eggs are not on the pads"
-- rather than as "nothing moved".
--
-- No server-side measurement can ever see this. `evolution-lab-probe-routes-blocked` is the standing
-- note and this is a new instance of it: the only datamodel that holds the truth is the CLIENT, and
-- the one-line check is `workspace.Zones.Forest.PetShop` read in the Client datamodel.
local ANCHOR_ATTR = { Egg = "IdleAnchor", FeaturePet = "SpinAnchor" }

local function moveBy(inst, delta)
	if inst:IsA("Model") then
		inst:PivotTo(inst:GetPivot() + delta)
	elseif inst:IsA("BasePart") then
		inst.CFrame = inst.CFrame + delta
	end
	-- Shifted rather than recomputed from the piece: the anchor is the SHELL's CFrame and not the
	-- model's pivot (`EggPlaza` stamps `shell.CFrame`), so re-deriving it here would need to know
	-- which part the client places from. A delta needs to know nothing.
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

	-- 1. group what survives into columns by X. Rounded to the nearest 4 studs because the pieces of
	--    one column are not all exactly on its centre line -- a price card sits forward of its egg.
	-- Idempotent: a second call must not stand a second podium inside the first. Same rule
	-- `ForestMapService.Init` follows and for the same reason.
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

	-- ===== 2. THE FOUNTAIN AND THE MAP'S EGG PROPS GO FIRST =====
	-- BEFORE the seating and not after, and the ordering is the whole reason step 3 works. The
	-- fountain is a 55 x 52 x 55 prop standing at the exact point the eggs are about to be seated
	-- against, so a ray cast down there while it is still standing measures its rim, not the ground,
	-- and all three eggs end up on top of a fountain that is then deleted out from under them.
	-- `evolution-lab-placement-search-ordering` is this same lesson from the other side: a pass only
	-- ever knows the world that existed when it ran.
	--
	-- The fountain is the one landmark in this village nothing is wired to: no prompt, no anchor
	-- consumer but this line, no service that walks it by name (checked across `src/` --
	-- `evolution-lab-repointing-a-door` is the standing note that one grep over the instance NAME is
	-- what separates a move from a silent breakage). The four egg props are the artist's incubators;
	-- 31.7 stood our columns on three of them and left `King` as scenery. With the real eggs in the
	-- middle of the square, all four are a second egg row for a player to walk to by mistake.
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

	-- ===== 3. SEAT EACH COLUMN ON THE GROUND IT NOW STANDS OVER (30.25) =====
	-- 30.24 moved these in XZ and KEPT the Y they had, and the owner photographed three eggs hanging
	-- in the air. That Y was never a height above the ground: 31.7 landed each egg on the CENTRE of
	-- a 17.2-stud incubator prop, so it only ever looked right because something solid was under it,
	-- and this pass deletes exactly those props. A remembered height is not a height.
	--
	-- So the floor is ASKED rather than assumed -- one ray per column, at the point the egg is going
	-- to, with the shop itself excluded so an egg cannot measure its own neighbour. The delta is
	-- taken from the EGG and applied to every piece in the column, which is what preserves a price
	-- card sitting in front and a feature pet floating above; and it is a full 3D delta now, where
	-- 30.24's was XZ only.
	local villageMap = zoneModel:FindFirstChild("VillageMap")
	local dirtColour = villageMap and MapPaint.DirtColour(villageMap) or MapPaint.DIRT_FALLBACK
	local fountainTop = fountain and fountain.top or nil
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { shop }
	rayParams.IgnoreWater = true

	local moved, cards, seated = 0, 0, {}
	if fountain then
		for i, key in ipairs(order) do
			local a = EGG_ANGLES[i]
			if a then
				local pieces = columns[key]
				local egg = nil
				for _, c in ipairs(pieces) do
					if c.Name == "Egg" then egg = c break end
				end
				local eggPos = egg and centreOf(egg)
				if eggPos then
					local wantX = fountain.pos.X + math.cos(a) * EGG_RING
					local wantZ = fountain.pos.Z + math.sin(a) * EGG_RING
					-- the lowest piece in the whole column, which is what decides the lift
					local columnLow = math.huge
					for _, c in ipairs(pieces) do
						local cp = centreOf(c)
						if cp then columnLow = math.min(columnLow, cp.Y - halfHeight(c)) end
					end
					-- Started well above the square and thrown far enough to pass through it: the
					-- village floor is near y = 0 and the ray has to clear the tallest thing it may
					-- legitimately land on.
					local hit = workspace:Raycast(Vector3.new(wantX, 300, wantZ),
						Vector3.new(0, -600, 0), rayParams)
					-- Falls back to the fountain's own measured surface, then to the map floor. A
					-- ray that finds nothing means the square is not where this thinks it is, and
					-- an egg dropped to y = 0 is a visible fault rather than a silent one.
					local groundY = hit and hit.Position.Y or fountainTop or 0
					-- Lift the COLUMN, not the egg: whatever puts its lowest piece `PODIUM_CLEAR`
					-- above the floor, and never less than `PODIUM_MIN_H`. See the header -- this is
					-- the number that stopped the price cards being buried.
					local lift = math.max(groundY + PODIUM_CLEAR - columnLow, PODIUM_MIN_H)
					-- The egg's REST bottom. It does not stay there: the client bobs it through
					-- +/- `BobHeight` about this, so a podium topped out exactly here is a podium
					-- the egg sinks half a stud into twice a second. The plinth stops one bob
					-- short and the egg kisses it at the bottom of the cycle, which is also her
					-- own note on what the podium was for -- *"ako vec malo lebde, nesto na cemu
					-- lebde"*. Read off the model rather than typed, because `EggPlaza` owns it.
					local eggBottom = eggPos.Y - halfHeight(egg) + lift
					local bob = egg:GetAttribute("BobHeight") or 0
					local delta = Vector3.new(wantX - eggPos.X, lift, wantZ - eggPos.Z)
					for _, c in ipairs(pieces) do
						moveBy(c, delta)
					end
					local podiumRadius = eggSize(egg) / 2 + PODIUM_MARGIN
					local podiumTop = eggBottom - bob
					podium(shop, wantX, wantZ, groundY, podiumTop, podiumRadius, dirtColour)
					-- ...and the card goes where THIS podium ended up, not where the stall left it.
					-- The bearing is taken about `fountain.pos` rather than about the egg, because
					-- it has to be measured from the ring centre -- the one point every column
					-- shares -- and the radius passed is the PLINTH edge (`+ PODIUM_LIP`), which is
					-- the widest thing the card has to clear.
					cards += seatPriceCard(pieces, fountain.pos.X, fountain.pos.Z, a,
						podiumRadius + PODIUM_LIP, podiumTop)
					moved += 1
					seated[#seated + 1] = ("%.1f/+%.1f"):format(groundY, lift)
				end
			end
		end
	else
		warn("[MapEggs] " .. zoneKey .. ": no fountain anchor -- the eggs were left where they were")
	end

	-- 4. the circle itself, painted where the fountain stood. Parented into the map so a rebuild
	--    takes it with everything else.
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
			-- outline first, mass second: `evolution-lab-world-look-pass`
			circle += MapPaint.Disc(fountain.pos.X, fountain.pos.Z, CIRCLE_D + RIM_EXTRA, folder, 0,
				MapPaint.Shade(dirt, RIM_SHADE), RIM_Y, CIRCLE_THICK)
			circle += MapPaint.Disc(fountain.pos.X, fountain.pos.Z, CIRCLE_D, folder, 0, dirt,
				CIRCLE_Y, CIRCLE_THICK)
			for _, part in ipairs(folder:GetChildren()) do
				part.CanQuery = false
			end
		end
	end

	-- `cards` is counted apart from `moved` on purpose: a column that seats correctly and silently
	-- loses its price card is exactly what 30.29 was, and one number cannot report both.
	print(("[MapEggs] %s: dropped %d stall pieces, seated %d egg columns on podiums on the %d-stud "
		.. "ring inside the fence (ground/lift %s), placed %d price cards off the podium, removed "
		.. "%d props (fountain + the map's egg row), painted %d circle parts")
		:format(zoneKey, dropped, moved, EGG_RING, table.concat(seated, " "), cards, removed,
			circle))
	return moved
end

return MapEggs
