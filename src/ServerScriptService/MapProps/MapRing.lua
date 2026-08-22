-- MapProps/MapRing -- the arc maths every hand-placed ring of props in this map needs.
--
-- The village asset likes rings. The twenty zone doors stand on one (radius 44), the seven
-- leaderboards stand on another (radius 33.5), and both were placed by hand around a centre the
-- artist never wrote down. Every question either file asks is the same three: where is the centre,
-- what bearing is this prop at, and how do I move a prop to a different bearing without inventing a
-- facing rule of my own.
--
-- ===== WHY TURNING BEATS PLACING =====
-- `Spin` rotates a prop ABOUT THE RING'S CENTRE rather than setting its CFrame. That is the whole
-- value of this file: a rotation preserves the radius and the prop's own facing together, so the
-- artist's answer to "which way does a door look" is carried rather than re-derived from a number
-- typed in a service. Measured on the placed map, every zone door's LookVector is tangential to a
-- thousandth, and no line of code anywhere had to know that.
--
-- ===== AND THE THING THAT WENT WRONG WITHOUT IT =====
-- `MapPortals` extended its arc by repeatedly stepping one more door off the last one. An arc built
-- that way has no idea how far round it has come, and twenty 18.3-degree steps is 366 degrees: the
-- ring closed, and sealed the owner inside it. Anything laid out through this file is placed from a
-- COUNT and a SPAN, which cannot overrun.

local MapRing = {}

-- XZ only. Everything here works in Vector2 (x, z) because a ring of props on a floor has no
-- opinion about height, and mixing the two is how a bearing ends up measured against Y.
function MapRing.Flat(model)
	local cf = model:GetBoundingBox()
	return Vector2.new(cf.Position.X, cf.Position.Z)
end

-- The circle through three points. nil when they are collinear, which is the caller's cue that the
-- artist drew a straight colonnade and there is no ring to reason about.
function MapRing.CircleThrough(a, b, c)
	local d = 2 * (a.X * (b.Y - c.Y) + b.X * (c.Y - a.Y) + c.X * (a.Y - b.Y))
	if math.abs(d) < 1e-4 then return nil end
	local a2, b2, c2 = a.X ^ 2 + a.Y ^ 2, b.X ^ 2 + b.Y ^ 2, c.X ^ 2 + c.Y ^ 2
	return Vector2.new(
		(a2 * (b.Y - c.Y) + b2 * (c.Y - a.Y) + c2 * (a.Y - b.Y)) / d,
		(a2 * (c.X - b.X) + b2 * (a.X - c.X) + c2 * (b.X - a.X)) / d)
end

-- Centre from a circumcircle through three props spread across the chain; radius as the MEAN of all
-- of them. The mean and not that triple's own radius because the props are hand-placed -- the zone
-- doors sit between 44.0 and 45.1 studs out -- so taking one triple as gospel tilts everything laid
-- out afterwards by whatever slop those three happen to carry.
function MapRing.Fit(models)
	local n = #models
	if n < 3 then return nil end
	local centre = MapRing.CircleThrough(
		MapRing.Flat(models[1]), MapRing.Flat(models[math.ceil(n / 2)]), MapRing.Flat(models[n]))
	if not centre then return nil end
	local sum = 0
	for _, m in ipairs(models) do sum += (MapRing.Flat(m) - centre).Magnitude end
	return centre, sum / n
end

function MapRing.Bearing(model, centre)
	local d = MapRing.Flat(model) - centre
	return math.atan2(d.Y, d.X)
end

-- Turn a prop about the ring's centre by `delta` radians of BEARING.
--
-- The sign is the one thing here worth checking rather than believing: `CFrame.Angles(0, t, 0)`
-- sends a point at bearing b to bearing b - t, so increasing a bearing by delta means turning by
-- MINUS delta. Getting it backwards puts every prop on the far side of the ring, which looks like a
-- layout bug and is a sign error.
function MapRing.Spin(model, centre, delta)
	local c3 = Vector3.new(centre.X, 0, centre.Y)
	model:PivotTo(CFrame.new(c3) * CFrame.Angles(0, -delta, 0) * CFrame.new(-c3) * model:GetPivot())
end

-- Move a prop to an absolute bearing on the ring, by turning it there from wherever it is now.
function MapRing.PlaceAt(model, centre, bearing)
	MapRing.Spin(model, centre, bearing - MapRing.Bearing(model, centre))
end

return MapRing
