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
		cap.CFrame = CFrame.new(cx + e[1], y, e[2]) * CFrame.Angles(0, 0, math.pi / 2)
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
function MapPaint.Taper(a, b, wA, wB, parent, cx, colour, y, thick, n, capA, capB)
	n = n or 8
	if capA == nil then capA = true end
	if capB == nil then capB = true end
	local made = 0
	for i = 0, n - 1 do
		local t0, t1 = i / n, (i + 1) / n
		local p0 = a:Lerp(b, t0)
		local p1 = a:Lerp(b, t1)
		-- cap the far end of every quad, plus the near end of the first one when the road wants it
		local caps = "b"
		if i == 0 and capA then caps = "both" end
		if i == n - 1 and not capB then caps = (caps == "both") and "a" or "none" end
		made += MapPaint.Segment({
			x1 = p0.X, z1 = p0.Y, x2 = p1.X, z2 = p1.Y,
			w = wA + (wB - wA) * ((t0 + t1) / 2),
		}, parent, cx, colour, y, thick, caps)
	end
	return made
end

return MapPaint
