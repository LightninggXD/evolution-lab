-- MapProps/MapPaint -- the flat paint every mapped zone draws its ground with.
--
-- Two things, and they were both `MapJungle`'s until the village road needed the same two. That is
-- the whole reason this file exists: `evolution-lab-zone-geometry-constants` is the standing note
-- about a single decision written in two files, and "how wide is a road and what colour is dirt in
-- this map" is exactly that decision. The jungle's trunk roads and the village's approach road are
-- the same road seen at two ends, so they are painted by the same function or they drift apart.
--
-- ===== THE PAINT IS PAINT, NOT GEOMETRY =====
-- Everything here is thin, `CanCollide = false`, and sits a fraction of a stud above the floor it
-- is drawn on. A road you can trip on is worse than no road; `roblox-moving-platform-needs-velocity`
-- and the terrace-stair work are both records of what happens when scenery carries the player. It
-- also means paint can be laid straight over the map's own ground with nothing to reconcile: where
-- it crosses the artist's dirt it disappears into it, and where it crosses lawn it is the road.

local MapPaint = {}

-- Fallback is the colour measured off `ForestVillage`'s ground union, so a map with no dirt in it
-- still gets roads that match this one.
MapPaint.DIRT_FALLBACK = Color3.fromRGB(213, 160, 116)

MapPaint.Y = 0.25            -- clear of a 0.6-stud ground union and under the 0.95 patch ceiling
MapPaint.THICK = 0.4

-- ===== NO TWO PAINTED SURFACES MAY SHARE A PLANE (30.26) =====
-- The owner, on a capture of a junction in the wood: *"put je ne jednak"*. It is not the widths and
-- it is not the colour -- every road here is the same dirt at the same width it was authored at.
-- It is Z-FIGHTING. A junction stacks a trunk road, a spur, two end caps and a camp floor on top of
-- one another AT EXACTLY THE SAME Y, and the depth buffer picks a different winner per pixel per
-- frame, which renders as patches of slightly different tan with ragged edges between them. It is
-- the terrace shimmer from `evolution-lab-terrace-zfighting`, in a file whose entire job is drawing
-- coplanar sheets -- so that file's own rule applies: overlapping surfaces get their own plane.
--
-- `STEP` is the separation. Big enough for the depth buffer to be certain at any camera distance,
-- far too small to read as a step underfoot on a 0.4-stud sheet, and the whole ladder still fits
-- under the 0.95 ceiling `MapPaint.Y` was chosen against.
MapPaint.STEP = 0.04

-- The colour of the village's ground path, read off the map. A flat, wide UnionOperation is what
-- that asset uses for its dirt; anything thicker than two studs is a building and anything narrower
-- than eighty is a plank.
function MapPaint.DirtColour(map)
	local best, bestArea = nil, 0
	for _, c in ipairs(map:GetDescendants()) do
		if c:IsA("UnionOperation") and c.Size.Y <= 2 and c.Size.X >= 80 and c.Size.Z >= 80 then
			local area = c.Size.X * c.Size.Z
			if area > bestArea then best, bestArea = c, area end
		end
	end
	return best and best.Color or MapPaint.DIRT_FALLBACK
end

-- A colour stepped down toward black by `f`. The outline tier from `evolution-lab-chunky-look-rules`
-- -- draw the dark edge first and the bright mass inside it -- expressed against whatever colour the
-- map turned out to be, rather than as a second swatch that would have to be re-picked per map.
function MapPaint.Shade(c, f)
	return Color3.new(c.R * (1 - f), c.G * (1 - f), c.B * (1 - f))
end

local function slab(parent, name, cf, size, colour, t)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(size.X, t, size.Y)
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- A disc of paint on its own, which `Segment` cannot draw: a segment with both ends in the same
-- place has zero length and is refused. Added for 30.23's camp clearings -- the floor of a camp is
-- a round patch of the same dirt its road is made of, and that is what makes an opening in the wood
-- read as somewhere rather than as a gap.
function MapPaint.Disc(x, z, d, parent, cx, colour, y, thick)
	y = y or MapPaint.Y
	thick = thick or MapPaint.THICK
	local p = Instance.new("Part")
	p.Name = "PaintDisc"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(thick, d, d)
	p.CFrame = CFrame.new(cx + x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return 1
end

-- One road segment as a single rotated slab, plus a disc at each end. The discs are what make a
-- corner a corner: two slabs meeting at an angle leave a wedge of bare ground on the outside of the
-- turn, and a round cap covers it whatever the angle is.
--
-- `seg` is `{ x1, z1, x2, z2, w }` in zone-relative studs; `cx` shifts it onto the zone's platform.
-- `y` defaults to `MapPaint.Y`, and is an argument so a kerb can be drawn UNDER a road without the
-- two of them fighting for the same plane -- which is the terrace shimmer, in a file that draws
-- nothing but coplanar sheets.
--
-- `thick` is the OTHER half of that, and it is what a road crossing more than one floor needs.
-- `y` is the slab's CENTRE, so a thin one laid at a single height is either buried under the taller
-- floor it crosses or hanging in the air over the shorter one -- and the approach road crosses a
-- 1.04-stud stone deck, a 0.6-stud ground union and bare lawn at 0.0 within eighty studs. Given
-- depth instead, one slab reaches down past the lowest of them while its TOP -- the only face
-- anybody sees -- stays at one height the whole way. That is also why it reads as a kerb over the
-- lawn and as paint over the deck, which is what a road actually does.
--
-- `caps` says which ends get their disc: "both" (the default), "a", "b" or "none". The discs exist
-- to cover the notch where two quads of different widths butt, so an INTERIOR join always wants one
-- -- but the two ends of a finished road do not, and the outermost one is very visible when it is
-- not wanted: a 44-stud disc on the end of a 44-stud road is a lollipop, and the first capture of
-- the approach road is a warm blob sitting on the plaza with a road leading out of it.
function MapPaint.Segment(seg, parent, cx, colour, y, thick, caps)
	y = y or MapPaint.Y
	thick = thick or MapPaint.THICK
	caps = caps or "both"
	local dx, dz = seg.x2 - seg.x1, seg.z2 - seg.z1
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1 then return 0 end
	local mid = Vector3.new(cx + (seg.x1 + seg.x2) / 2, y, (seg.z1 + seg.z2) / 2)

	slab(parent, "PaintRoad", CFrame.new(mid) * CFrame.Angles(0, math.atan2(dx, dz), 0),
		Vector2.new(seg.w, len), colour, thick)

	local made = 1
	local ends = {}
	if caps == "both" or caps == "a" then ends[#ends + 1] = { seg.x1, seg.z1 } end
	if caps == "both" or caps == "b" then ends[#ends + 1] = { seg.x2, seg.z2 } end
	for _, e in ipairs(ends) do
		local cap = Instance.new("Part")
		cap.Name = "PaintCap"
		cap.Shape = Enum.PartType.Cylinder
		cap.Size = Vector3.new(thick, seg.w, seg.w)
		-- HALF A STEP BELOW ITS OWN SLAB. A cap is a patch for the notch at a join, so it is always
		-- overlapped by the road it belongs to -- and a disc coplanar with the slab lying on top of
		-- it is the single most common z-fight in this file, one per road end, every road.
		cap.CFrame = CFrame.new(cx + e[1], y - MapPaint.STEP / 2, e[2])
			* CFrame.Angles(0, 0, math.pi / 2)
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanTouch = false
		cap.CastShadow = false
		cap.Color = colour
		cap.Material = Enum.Material.SmoothPlastic
		cap.Parent = parent
		made += 1
	end
	return made
end

-- A road that CHANGES WIDTH along its length, which a single rotated slab cannot do. Drawn as `n`
-- butted quads, each one a `Segment` at its own width -- so the taper is what makes a funnel read as
-- an entrance rather than as a corridor, which is `ForestMapService`'s own argument for the shape of
-- the cut it makes here.
--
-- The caps do the work at the joins: successive quads differ in width, so their corners do not line
-- up and a straight butt would leave a notch down both edges of the road.
-- `capA` / `capB` default true and are the ROAD's two ends, not each quad's -- every interior join
-- is capped regardless, because that is the notch the discs are there for.
--
-- ===== `y2`: A ROAD MAY DESCEND, AND 30.26 IS WHY IT HAS TO =====
-- `y` is one plane for the whole ribbon unless `y2` is given, in which case the quads walk from one
-- to the other. That is not a flourish. The approach road crosses HubPlaza's stone deck at the
-- plaza end -- where it has to top out at 1.30 to clear the 1.18 cross band -- and the village's own
-- 0.6-stud ground union at the other, where `MapGates` paints at 0.80. At ONE plane it is either
-- buried at the plaza or standing 0.5 studs proud of the village with its dark rim drawn OVER the
-- gate roads, which is exactly the band the owner photographed. A road that descends is the only
-- shape that is flush at both ends, and the rim descends with it because it is drawn by the same
-- call.
function MapPaint.Taper(a, b, wA, wB, parent, cx, colour, y, thick, n, capA, capB, y2)
	n = n or 8
	if capA == nil then capA = true end
	if capB == nil then capB = true end
	y2 = y2 or y
	local made = 0
	for i = 0, n - 1 do
		local t0, t1 = i / n, (i + 1) / n
		local p0 = a:Lerp(b, t0)
		local p1 = a:Lerp(b, t1)
		-- cap the far end of every quad, plus the near end of the first one when the road wants it
		local caps = "b"
		if i == 0 and capA then caps = "both" end
		if i == n - 1 and not capB then caps = (caps == "both") and "a" or "none" end
		local mid = (t0 + t1) / 2
		made += MapPaint.Segment({
			x1 = p0.X, z1 = p0.Y, x2 = p1.X, z2 = p1.Y,
			w = wA + (wB - wA) * mid,
		}, parent, cx, colour, y + (y2 - y) * mid, thick, caps)
	end
	return made
end

return MapPaint
