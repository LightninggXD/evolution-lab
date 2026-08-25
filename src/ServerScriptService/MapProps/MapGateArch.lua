-- MapProps/MapGateArch -- her stone arch becomes the -Z gate, and the teleport survives the
-- redecoration.
--
-- The owner, 2026-08-25, with the model dropped in Workspace and a screenshot of it standing on
-- the approach road: *"ovo moze biti novi model za portal ili sve portale"* -- then, on scope:
-- Forest's -Z gate only. The model is CLEAN, unlike the paid ad-portal unit 32.28 disarmed: zero
-- scripts, zero ad classes, one SurfaceLight -- a stone arch with a recessed red door.
--
-- ===== THE TELEPORT IS NOT MINE TO REBUILD =====
-- `ZoneService.Init` (ServerMain:182) scans workspace.Zones ONCE for parts named `PortalGate`,
-- wires Touched, and reads the `TargetZone` attribute when somebody touches. This file never
-- renames, re-parents or re-attributes that part: it RESIZES the Forest -Z sheet into the arch's
-- doorway and RECOLORS it to her door's red, so the one-shot scan still finds a `PortalGate` and
-- the touch still fires the same handler. A door the scan can no longer find is the dead
-- `TradeUpdate` remote all over again -- correct-looking code, feature that never fires.
--
-- ===== THE FILM IS THE DOORWAY, MEASURED BEFORE THE SCALE =====
-- First live build measured the doorway off the SCALED clone and the film came out 100 x 131 --
-- the whole mouth, red showing above the arch's curve. The owner: *"malo ti izviruje ova crvena"*.
-- The fault: `ScaleTo` multiplies every part's size, so the post-scale min-dimension test that
-- separates door parts from decorative rocks lets the rocks in, and the rock spread IS the mouth
-- spread. The fix is order, not a better threshold: measure the cluster in TEMPLATE space, where
-- the rocks are still 0.8-3.3 studs thick and fail the 1.25 test, then scale the measured box.
-- The film keeps the sheet's own plane -- the art's face stands ~12 scaled studs in front of it,
-- so the door reads as "part the paint, the portal is here", exactly where the old sheet stood.
--
-- ===== SCALE: HEIGHT, NOT WIDTH =====
-- The wall gap is PORTAL_GAP (100) wide but WALL_HEIGHT (180) tall, and the built gate filled it
-- to ~175 with frame, lintel and cap. Width-fit (scale 7.7) leaves a 42-stud slot of bare gap
-- above the arch; height-fit to the old sheet's 138 reads as a castle gate -- a door lower than
-- the wall it stands in -- and buries the arch's legs ~3.5 studs into the wall segments each
-- side, which HIDES the raw wall end-cuts instead of exposing them. The wall above stays open on
-- purpose: stretching a 16.7-stud model to 180 turns stone into taffy.
--
	-- ===== EVERY BOOT, BECAUSE THE WORLD IS EVERY BOOT =====
	-- ZoneBuilder rebuilds the zone and the vanilla gate with it on every server start, so this runs
	-- every start too: clone the template out of Workspace, seat it on the sheet's floor, strip the
	-- built stonework around that gate (radius 130 -- the lintel alone is 150 long; the next gate is
	-- a platform away), and move the template original to ServerStorage so it stops standing on the
	-- main lane it was dropped on (its parts are CanCollide = true, mid-corridor). Nothing is edited
	-- in ZoneBuilder; delete the wiring line and the built gate comes back whole.
	--
	-- TWO WAYS A SECOND RUN OF THIS FILE USED TO GO WRONG, BOTH FIXED HERE (32.30):
	-- (1) An earlier PortalArch clone left parented to the zone made the next Init stack a SECOND
	-- arch on top of it -- two 138-tall stone models z-fighting over one doorway. The old clone is
	-- destroyed first, so re-seating is idempotent the way MapEggs.Reseat was made idempotent
	-- after 32.20 measured it drifting four studs across three calls.
	-- (2) Once a boot parked the template in ServerStorage -- which is what this file itself does,
	-- and what a save picked up -- every later boot warned "no template" and depended on saved
	-- residue instead. ServerStorage is checked too and the template is moved BACK to Workspace
	-- first: on a live server ServerStorage starts empty and Workspace carries the model, so this
	-- branch only ever fires in a place that was saved after a run, which is exactly the place
	-- that needs it.

local MapGateArch = {}

local TEMPLATE_NAME = "PortalArchTemplate"
local SHEET_HEIGHT = 138     -- the built sheet's own height (PORTAL_OPEN_H in ZoneGate); the arch fills its footprint
local CLEAR_RADIUS = 130     -- one gate's stonework spans +-109 (guardian plinths); the next gate is >1000 away
local FILM_THICK = 0.4
local FILM_PAD_W = 1         -- a stud of film buried inside the arch stone each side
local FILM_PAD_H = 0.5
local CLUSTER_MIN_DIM = 1.25 -- door slab/faces are 1.3-1.8 thick; the decorative rocks are all <= 1.2

local function warnMissing(zoneKey, what)
	warn(("[MapGateArch] %s: %s -- vanilla gate stays"):format(zoneKey, what))
end

-- world AABB of one part (abs-of-components, the probe's method -- parts may be yawed)
local function boxOf(part)
	local c, sz = part.CFrame, part.Size
	local hx = (math.abs(c.RightVector.X) * sz.X + math.abs(c.UpVector.X) * sz.Y + math.abs(c.LookVector.X) * sz.Z) / 2
	local hy = (math.abs(c.RightVector.Y) * sz.X + math.abs(c.UpVector.Y) * sz.Y + math.abs(c.LookVector.Y) * sz.Z) / 2
	local hz = (math.abs(c.RightVector.Z) * sz.X + math.abs(c.UpVector.Z) * sz.Y + math.abs(c.LookVector.Z) * sz.Z) / 2
	local p = c.Position
	return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
end

-- The teleport sheet is the one true `PortalGate` of THIS gate: Forest has a +Z gate too, and the
-- -Z one is the most-negative-Z part of that name in the zone. Exported because the flank
-- dresser has to lean its crags against the same wall line this sheet stands on.
local function findSheet(zoneModel)
	local best, bestZ = nil, math.huge
	for _, d in ipairs(zoneModel:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "PortalGate" and d.Position.Z < bestZ then
			best, bestZ = d, d.Position.Z
		end
	end
	return best
end
MapGateArch.FindSheet = findSheet

-- The door cluster: flat parts thick enough to be door, too small in every dimension to be the
-- arch, and never the arch itself. The arch is simply the largest-volume part of the model.
local function collectCluster(parts)
	local arch, rest = nil, {}
	for _, p in ipairs(parts) do
		if not arch or p.Size.X * p.Size.Y * p.Size.Z > arch.Size.X * arch.Size.Y * arch.Size.Z then
			rest[#rest + 1] = arch
			arch = p
		else
			rest[#rest + 1] = p
		end
	end
	local cluster = {}
	for _, p in ipairs(rest) do
		if math.min(p.Size.X, p.Size.Y, p.Size.Z) >= CLUSTER_MIN_DIM then
			cluster[#cluster + 1] = p
		end
	end
	return arch, cluster
end

function MapGateArch.Init(zoneKey)
	local zones = workspace:FindFirstChild("Zones")
	local zoneModel = zones and zones:FindFirstChild(zoneKey)
	local sheet = zoneModel and findSheet(zoneModel)
	if not sheet then
		warnMissing(zoneKey, "no PortalGate part in the zone")
		return 0
	end

	-- idempotent re-seat (see header, fault 1): the last clone comes down before a new one goes up
	local previous = zoneModel:FindFirstChild("PortalArch")
	if previous and previous:IsA("Model") then
		previous:Destroy()
	end

	local template = workspace:FindFirstChild(TEMPLATE_NAME)
	if not template or not template:IsA("Model") then
		-- recovery after a save picked up this file's own parking step (header, fault 2)
		template = game:GetService("ServerStorage"):FindFirstChild(TEMPLATE_NAME)
		if template and template:IsA("Model") then
			template.Parent = workspace
			print(("[MapGateArch] %s: template recovered from ServerStorage"):format(zoneKey))
		end
	end
	if not template or not template:IsA("Model") then
		warnMissing(zoneKey, "no " .. TEMPLATE_NAME .. " model in Workspace or ServerStorage")
		return 0
	end

	local parts = {}
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") then parts[#parts + 1] = d end
	end
	local arch, cluster = collectCluster(parts)
	if not arch or #cluster == 0 then
		warnMissing(zoneKey, "template anatomy not recognised (arch + door)")
		return 0
	end

	-- The walk-through surgery happens on the TEMPLATE, before the clone, so the clone inherits
	-- it and the identification runs once. The template is parked in ServerStorage afterwards,
	-- where nothing can touch it.
	for _, p in ipairs(cluster) do
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end

	local clone = template:Clone()
	clone.Name = "PortalArch"
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	-- Face the lane: the door's thinnest world axis must be Z (the wall runs along X). The model
	-- as dropped already satisfies this; the guard is for the day she re-drops it turned.
	local dmnX, dmxX, _, _, dmnZ, dmxZ = boxOf(cluster[1])
	local thinAlongX = (dmxX - dmnX) < (dmxZ - dmnZ)
	if thinAlongX then
		clone:PivotTo(clone:GetPivot() * CFrame.Angles(0, math.rad(90), 0))
	end

	local _, tplSize = template:GetBoundingBox()
	local scale = SHEET_HEIGHT / tplSize.Y
	clone:ScaleTo(scale)

	-- Seat by BOUNDS, not by pivot: ScaleTo works about the pivot and these props pivot at their
	-- centre, so the base is read after scaling and the whole model put back onto the sheet's
	-- floor -- the same fix MapPortals.layOut pays for on the village hall doors.
	local floorY = sheet.Position.Y - sheet.Size.Y / 2
	local cf2, sz2 = clone:GetBoundingBox()
	clone:PivotTo(clone:GetPivot() + (Vector3.new(sheet.Position.X, floorY + sz2.Y / 2, sheet.Position.Z) - cf2.Position))
	clone.Parent = zoneModel

	-- Film geometry measured in TEMPLATE space (see header), then scaled: wide/tall enough to
	-- fill the doorway with overlap into the arch stone, never past the arch's own silhouette.
	local tmnX, tmxX, tmnY, tmxY, tmnZ, tmxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(cluster) do
		local a, b, c, d, e, f = boxOf(p)
		tmnX, tmxX = math.min(tmnX, a), math.max(tmxX, b)
		tmnY, tmxY = math.min(tmnY, c), math.max(tmxY, d)
		tmnZ, tmxZ = math.min(tmnZ, e), math.max(tmxZ, f)
	end
	local wallExt = thinAlongX and (tmxZ - tmnZ) or (tmxX - tmnX)
	local filmW = wallExt * scale + FILM_PAD_W
	local filmH = (tmxY - tmnY) * scale + FILM_PAD_H
	local tplCF = template:GetBoundingBox()
	local filmBottom = floorY + (tmnY - (tplCF.Position.Y - tplSize.Y / 2)) * scale - FILM_PAD_H / 2

	local doorColor = cluster[1].Color
	for _, p in ipairs(cluster) do
		if p.Size.X * p.Size.Y * p.Size.Z > cluster[1].Size.X * cluster[1].Size.Y * cluster[1].Size.Z then
			doorColor = p.Color
		end
	end

	sheet.Size = Vector3.new(FILM_THICK, filmH, filmW)
	sheet.CFrame = CFrame.new(sheet.Position.X, filmBottom + filmH / 2, sheet.Position.Z) * sheet.CFrame.Rotation
	sheet.Color = doorColor
	local glow = doorColor:Lerp(Color3.new(1, 1, 1), 0.4)
	for _, d in ipairs(sheet:GetChildren()) do
		if d:IsA("ParticleEmitter") then
			d.Color = d.Texture:find("sparkles") and ColorSequence.new(Color3.new(1, 1, 1), doorColor)
				or ColorSequence.new(doorColor, glow)
		elseif d:IsA("PointLight") or d:IsA("SurfaceLight") then
			d.Color = d:IsA("SurfaceLight") and glow or doorColor
		end
	end

	-- The built gate's stonework, by NAME and by RADIUS: prefixes are unique to ZoneGate's build
	-- (the village hall doors are `ZonePortal_*`, which does not match `Portal`), the radius keeps
	-- Forest's other gate untouched, and the clone is excluded explicitly -- its mesh parts are
	-- named `Meshes/Portal_Plane...` and stand inside the radius.
	local doomed = {}
	for _, d in ipairs(zoneModel:GetDescendants()) do
		if d:IsA("BasePart") and d ~= sheet and not d:IsDescendantOf(clone) then
			local n = d.Name
			if n ~= "PortalGate" and (n:sub(1, 6) == "Portal" or n:sub(1, 8) == "Guardian" or n == "ColumnInlay") then
				if math.abs(d.Position.X - sheet.Position.X) <= CLEAR_RADIUS
					and math.abs(d.Position.Z - sheet.Position.Z) <= CLEAR_RADIUS then
					doomed[#doomed + 1] = d
				end
			end
		end
	end
	for _, d in ipairs(doomed) do d:Destroy() end

	template.Parent = game:GetService("ServerStorage")

	print(("[MapGateArch] %s: arch seated at (%.0f, %.0f, %.0f) scale %.2f, door film %.0f x %.0f, "
		.. "sheet recolored (%.2f, %.2f, %.2f), removed %d built gate parts, template -> ServerStorage")
		:format(zoneKey, sheet.Position.X, floorY, sheet.Position.Z, scale, filmW, filmH,
			doorColor.R, doorColor.G, doorColor.B, #doomed))
	return #doomed
end

return MapGateArch
