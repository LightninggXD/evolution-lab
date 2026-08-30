-- ===== THE ONLY WATER IN THIS GAME THAT ACTUALLY MOVES =====
--
-- The owner, 2026-08-16, over a screenshot of the "Part To Water [ANIMATED]" toolbox plugin:
-- *"imas i ove pluginove da doradis vodu vodopade i sve da ima animacije i da bude real pretrazi to
-- sve i ubaci da izgleda sto zive zivo"*. Roadmap 17.16, taken as 33.10.
--
-- Everything `ZoneTerrain` builds for water describes the SHAPE of water without any of it going
-- anywhere: `PoolWater` is a glass slab, `FallSheet` is a glass pane with three neon stripes painted
-- down it, `FallBasin` is a blue rectangle lying on a shelf. The emitters that were added later
-- (`FallDrops`, the pool mist, the bottom-step spray) put motion NEAR the water; none of them make
-- the water's own surface move.
--
-- ===== WHY A BEAM AND NOT THE `Texture` THE ROADMAP ROW NAMES =====
--
-- 17.16 asked for "a scrolling `Texture`/`SurfaceAppearance` pair". **A `Texture` cannot scroll.** It
-- has `OffsetStudsU`/`OffsetStudsV` and no speed of any kind, so "scrolling" one means a per-frame
-- loop writing those two numbers on every water surface in the world, forever, on the client -- for
-- 24 pools, 178 fall sheets and their basins. `SurfaceAppearance` does not animate at all.
--
-- A `Beam` has `TextureSpeed`, which the ENGINE advances. No script, no heartbeat connection, no
-- per-frame cost on our side, it replicates from the server like any other instance, and it streams
-- in and out with the part it hangs on. That is the whole reason this file has no `RunService` in it.
--
-- And it is not a guess that it looks right: `Decorations.Waterfall`, the one authored waterfall in
-- the place, is five Beams on `rbxassetid://1190623231` at speeds 0.26 to 1.92. This reuses that
-- exact texture, so the built falls and the authored one are made of the same water.
--
-- ===== THE ONE FACT THAT COSTS A ROUND TRIP TO REDISCOVER =====
--
-- **A Beam's ribbon is WIDE along its attachments' Y axis and runs along their X axis.** Measured
-- 2026-08-30, three lanes side by side photographed from above: attachments left at identity drew a
-- ribbon standing UP on edge (invisible from directly above), and only `CFrame.fromMatrix(p, +Z, +X)`
-- -- Y pointing sideways -- drew one lying flat on the water. So:
--
--   * a flat sheet on a pool wants  fromMatrix(p, <flow dir>, <across dir>)
--   * a curtain hanging down a fall wants fromMatrix(p, -Y, <across dir>)
--
-- Both callers here pass parts that `ZoneTerrain` builds UNROTATED, so an attachment's local frame
-- is the world frame and "across" can be written as a world axis. A rotated host would need the
-- axes taken off `part.CFrame`; nothing rotated has water on it yet.
--
-- ===== AND THE SIDE OF THE SHEET MATTERS =====
--
-- A fall's curtain has to hang in FRONT of `FallSheet`, on the valley side. The first attempt put it
-- at `fx - 2.6` by copying the sheet's own x, which is 0.6 studs INSIDE the cliff -- the beams built
-- fine, replicated fine, and were photographed as nothing at all. `FallStreak` already encodes the
-- answer (`fx - side * 2.6`): the front face is `-side`. Callers pass that as `faceX`.

local WaterFlow = {}

-- The classic Roblox water sheet. Owned by Roblox, so it loads in any place
-- (the same rule an animation follows) and it is already in this place on the authored waterfall.
local FLOW_TEXTURE = "rbxassetid://1190623231"

-- 0.4, not 0: at 0 a beam ignores lighting entirely and the pools stay milk-bright at night, which
-- is the same mistake `LightEmission = 1` makes on a particle. At 1 the falls go grey in every
-- shadow the cliff casts on itself, which is most of them.
local LIGHT_INFLUENCE = 0.4

local function attach(part, position, xAxis, yAxis)
	local a = Instance.new("Attachment")
	a.CFrame = CFrame.fromMatrix(position, xAxis, yAxis)
	a.Parent = part
	return a
end

local function ribbon(host, a0, a1, cfg)
	local b = Instance.new("Beam")
	b.Name = cfg.name
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Texture = FLOW_TEXTURE
	b.TextureMode = cfg.mode
	b.TextureLength = cfg.length
	b.TextureSpeed = cfg.speed
	b.Width0 = cfg.w0
	b.Width1 = cfg.w1
	-- straight, always. A curve control point pulls the ribbon off the slab it is meant to be lying
	-- on, and every surface here is a rectangle.
	b.CurveSize0 = 0
	b.CurveSize1 = 0
	-- THE ONE THAT IS NOT OPTIONAL. Left at the default `true` a Beam turns to face the camera, so a
	-- pool's surface stands up like a wall as you walk past it.
	b.FaceCamera = false
	b.LightInfluence = LIGHT_INFLUENCE
	b.Color = ColorSequence.new(cfg.tint)
	b.Transparency = cfg.transparency
	b.ZOffset = cfg.zOffset or 0
	b.Parent = host
	return b
end

-- Fades a ribbon out at both ends. `Beam.Transparency` runs along the beam's LENGTH, not across its
-- width, which is exactly what is needed: a scrolling sheet that stops dead at the end of a pool
-- draws a hard line across the water, and this is what hides it.
local function fadedEnds(mid, edge)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, edge),
		NumberSequenceKeypoint.new(0.12, mid),
		NumberSequenceKeypoint.new(0.88, mid),
		NumberSequenceKeypoint.new(1, edge),
	})
end

-- ===== A FLAT SHEET SCROLLING ACROSS A HORIZONTAL SLAB =====
--
-- `part` is a water slab built unrotated: pools, fall basins, fall headers. Two lanes, not one: a
-- single ribbon the width of the pool scrolls as one rigid sheet and reads as a conveyor belt. A
-- wide slow lane with a narrower faster one over it, the second running the OTHER way, gives the
-- surface a cross-current that never repeats on a fixed beat.
--
-- opts.axis  "X" or "Z" -- which way the water runs. Defaults to the slab's longer side.
-- opts.sign  +1 / -1 along that axis. A basin has a real downhill direction and must use it.
-- opts.speed the wide lane's speed; the narrow lane is derived from it.
-- opts.lift  how far above the slab's top face the sheet sits.
function WaterFlow.Surface(part, opts)
	opts = opts or {}
	local size = part.Size
	local axis = opts.axis or ((size.Z >= size.X) and "Z" or "X")
	local sign = opts.sign or 1
	local speed = opts.speed or 0.3
	-- 0.2 above the top face. Not 0: a ribbon exactly level with the slab is the coplanar-paint
	-- z-fight that has been chased off this map twice. Not more than a third of a stud either, or
	-- the sheet visibly floats over the pool's own rim.
	local lift = size.Y / 2 + (opts.lift or 0.2)

	local along = (axis == "Z") and Vector3.new(0, 0, sign) or Vector3.new(sign, 0, 0)
	local across = (axis == "Z") and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
	local runLen = (axis == "Z") and size.Z or size.X
	local wide = (axis == "Z") and size.X or size.Z

	local half = runLen / 2
	local a0 = attach(part, -along * half + Vector3.new(0, lift, 0), along, across)
	local a1 = attach(part, along * half + Vector3.new(0, lift, 0), along, across)

	-- tinted off the slab's own colour, lifted towards white. A pool that is teal in one zone and
	-- lilac in another must not both get the same white film -- the same rule the fall curtain mesh
	-- follows a few hundred lines away in ZoneTerrain.
	local tint = opts.tint or part.Color:Lerp(Color3.new(1, 1, 1), 0.45)
	local mid = opts.transparency or 0.62

	-- `wide * 0.9`: inside the slab's own edge. At full width the ribbon's edge lands exactly on the
	-- pool's lip, where `PoolFoam` sits, and the two fight.
	ribbon(part, a0, a1, {
		name = "FlowSheet", mode = Enum.TextureMode.Wrap,
		length = math.max(24, runLen / 5), speed = speed,
		w0 = wide * 0.9, w1 = wide * 0.9,
		tint = tint, transparency = fadedEnds(mid, 1),
	})
	ribbon(part, a0, a1, {
		name = "FlowSheetCross", mode = Enum.TextureMode.Wrap,
		length = math.max(16, runLen / 8), speed = -speed * 0.55,
		w0 = wide * 0.55, w1 = wide * 0.55,
		tint = tint, transparency = fadedEnds(mid + 0.12, 1),
		-- drawn in front of the wide lane, so the two do not flicker against each other where they
		-- overlap down the middle of the slab
		zOffset = 0.05,
	})
	return a0, a1
end

-- ===== A CURTAIN FALLING DOWN A SHEET =====
--
-- `sheet` is a `FallSheet`: 4 thick, `Size.Y` tall, `Size.Z` across, unrotated. `faceX` is +1 or -1,
-- the world X direction the water is seen from -- `-side` at the call site.
--
-- Three ribbons, not one, and each is narrower and faster than the last. A single ribbon at the full
-- width of the drop is a flat pane again, just a moving one; a fall is BRIGHTEST AND FASTEST DOWN ITS
-- MIDDLE and thins towards its edges, and three stacked widths is the cheapest way to say that. The
-- authored waterfall in this place makes the same point with five.
function WaterFlow.Fall(sheet, faceX, tint)
	local size = sheet.Size
	local wide = size.Z
	local height = size.Y
	-- 0.45 proud of the sheet's face. The sheet itself is 4 thick and `FallStreak` stands at 2.6, so
	-- this is in front of the pane and behind nothing.
	local offX = faceX * (size.X / 2 + 0.45)
	local down = Vector3.new(0, -1, 0)
	local across = Vector3.new(0, 0, 1)

	-- The ribbon runs past the sheet at BOTH ends: 1.6 up under the lip so the water does not appear
	-- out of a horizontal seam, and 2.5 below the foot into whatever it lands in, so it does not stop
	-- in mid-air above the basin. Same reasoning as the sheet's own +9 of height in ZoneTerrain.
	local top = Vector3.new(offX, height / 2 + 1.6, 0)
	local foot = Vector3.new(offX, -height / 2 - 2.5, 0)
	local a0 = attach(sheet, top, down, across)
	local a1 = attach(sheet, foot, down, across)

	local water = tint or Color3.fromRGB(206, 244, 255)
	-- Stretch with a length of 1, i.e. ONE copy of the texture pulled over the whole drop, which is
	-- what the authored waterfall does. Wrap was tried first: it tiles the sheet into hard horizontal
	-- bands that read as rungs of a ladder, because the texture has a strong horizontal crest in it.
	--
	-- ===== THE THREE TRANSPARENCIES WERE PHOTOGRAPHED, NOT CHOSEN =====
	--
	-- 0.46 / 0.38 / 0.30 was the first cut and it is what three stacked ribbons actually means:
	-- they COMPOUND, so a 45-stud drop in the Desert came out as a solid white column with no
	-- texture left in it and the blue sheet behind it gone. 0.62 / 0.54 / 0.44 went the other way --
	-- crisp, but the moving layer had receded behind `FallStreak` and the fall read the same as it
	-- did before this file existed. 0.55 / 0.48 / 0.38 is the frame where both are true: the plume
	-- moves down the middle and the sheet is still blue at the edges.
	local lanes = {
		{ name = "FallFlow",     w0 = wide * 0.96, w1 = wide * 1.06, speed = 1.6,  trans = 0.55 },
		{ name = "FallFlowMid",  w0 = wide * 0.62, w1 = wide * 0.72, speed = 0.95, trans = 0.48 },
		{ name = "FallFlowCore", w0 = wide * 0.30, w1 = wide * 0.38, speed = 2.4,  trans = 0.38 },
	}
	for i, lane in ipairs(lanes) do
		ribbon(sheet, a0, a1, {
			name = lane.name, mode = Enum.TextureMode.Stretch, length = 1,
			speed = lane.speed, w0 = lane.w0, w1 = lane.w1,
			tint = (i == 3) and water:Lerp(Color3.new(1, 1, 1), 0.5) or water,
			-- fades at the top only, so the water arrives out of the lip rather than starting on a
			-- ruled line; the bottom stays solid because it is landing in foam that hides it.
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.14, lane.trans),
				NumberSequenceKeypoint.new(0.92, lane.trans),
				NumberSequenceKeypoint.new(1, lane.trans + 0.25),
			}),
			zOffset = i * 0.05,
		})
	end
	return a0, a1
end

return WaterFlow
