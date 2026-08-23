-- MapProps/MapSigns -- the village's signposts, aimed at what they actually name.
--
-- Row 32.3 opened on "signs are orphans": `ServerStorage.Maps.ForestVillage` ships three
-- `ThreeDTextObject`s reading `Top \nPlayers`, `Chest` and `Worlds`, plus three `Sign1` posts, and
-- nothing in `src/` mentioned any of them. That much was true. Everything else about the row was a
-- reading rather than a measurement, and two captures said so:
--
-- ===== A SIGN HERE IS AN ARROW, NOT A PLAQUE =====
-- The art is a carved wooden ARROW on a pole -- the text is cut into the arrow and the arrow has a
-- point. So "the sign stands at the thing it names" is the wrong acceptance for this prop and
-- "the sign POINTS at the thing it names" is the right one, which changes what this file does: it
-- turns signs, it does not move them. The artist stood them on the grass verge at the edge of the
-- paving, which is where a signpost belongs, and no measurement here found a reason to move either.
--
-- ===== WHICH WAY AN ARROW POINTS, MEASURED TWICE =====
-- The post is three parts: a pole (1.1 x 22.5 x 1.5), the arrow board (0.5 x 5.0 x 9.1) and a nail.
-- The board is the widest part by a factor of six, which is how it is found.
--
-- **The arrow points along the board's MINUS LookVector and reads on its MINUS RightVector.** That
-- is not derived from the prop's `Size` -- a `MeshPart`'s size is its mesh's own box and says
-- nothing about which face is painted (`roblox-part-size-is-in-its-own-frame`). It is two screen
-- captures: the `Top Players` post shot from -Right renders the text upright and the point toward
-- screen-right, which is world bearing +14 against a -LookVector bearing of +13.6; the `Worlds`
-- post shot the same way is +/-0.3 of its own -149.3. The text model's own offset agrees with the
-- weaker half of it (it sits 0.3 studs to -Right of the board's plane) and is far too small a
-- number to have settled the question on its own.
--
-- ===== WHY A SIGN CANNOT BE LEFT TO THE ARTIST =====
-- The `Worlds` arrow was RIGHT when the map was drawn and is wrong now, and nothing was broken to
-- make it so. `MapPortals` re-lays the fourteen zone doors onto a twenty-door ring with its mouth
-- turned to face the village floor; measured on the placed map, the arrow points -149.3 deg while
-- the mouth of the hall it names is at -172.5 deg from it -- **23.2 degrees off, aiming at the wood
-- beside the doors** at 77 studs' range. An arrow that points 31 studs wide of a doorway is worse
-- than no arrow. That is the whole argument for this file existing rather than a coordinate being
-- typed into the map: whatever moves the target, the sign is re-aimed at it on the next boot.
--
-- `Top Players` never broke, and it is aimed here anyway: measured 4.7 deg off the middle of the
-- leaderboard arc, which is the artist's own slop, and there is no reason to keep it.
--
-- ===== AND ONE SIGN NAMES NOTHING =====
-- `Chest` is deleted. The game DOES have chests -- `RelicService.GiveChest` grants them and the
-- Relics panel opens them -- but they are a HUD feature with no instance anywhere in the world:
-- grep the service and it never touches `workspace`. There is no point in the village an arrow
-- reading "Chest" could truthfully point at, and an arrow pointing at scenery is a promise the
-- game does not keep.
--
-- ===== IDEMPOTENT BY CONSTRUCTION =====
-- Every aim is computed from where the arrow points NOW to where the target is NOW, so a second
-- call turns nothing; a deleted sign is simply not found. Neither needs a version attribute.

local MapAnchors = require(script.Parent.MapAnchors)
local MapPortals = require(script.Parent.MapPortals)
local MapRing = require(script.Parent.MapRing)

local MapSigns = {}

-- Below this the aim is meaningless -- a bearing to a target you are standing on is noise -- and
-- above it a degree of turn is a stud of error at the far end.
local MIN_RANGE = 15

-- The text is JSON in a StringValue, and the field is one flat string: `"text":"Top \nPlayers"`.
-- The escape arrives LITERAL (backslash then n) because the value is JSON source rather than a Lua
-- string, so both it and a real newline are folded to a space before the label is matched.
local function labelOf(text)
	local params = text:FindFirstChild("ThreeDTextParams")
	if not (params and params:IsA("StringValue")) then return nil end
	local raw = params.Value:match('"text":"(.-)"')
	if not raw then return nil end
	raw = raw:gsub("\\n", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
	return raw:lower(), raw
end

-- The arrow board: the widest part in plan. Measured on this asset it is 9.1 studs against a
-- 1.5-stud pole and a 0.6-stud nail, so the margin is not a close call on any of the three.
local function boardOf(post)
	local board, widest = nil, 0
	for _, d in ipairs(post:GetDescendants()) do
		if d:IsA("BasePart") then
			local w = math.max(d.Size.X, d.Size.Z)
			if w > widest then board, widest = d, w end
		end
	end
	return board
end

-- ...and the pole, which is what a signpost turns about. It is 0.5 studs from the board's centre in
-- plan, so this changes almost nothing and is still the right centre to name.
local function poleOf(post)
	local pole, tallest = nil, 0
	for _, d in ipairs(post:GetDescendants()) do
		if d:IsA("BasePart") and d.Size.Y > tallest then pole, tallest = d, d.Size.Y end
	end
	return pole
end

local function flatBearing(v)
	return math.atan2(v.Z, v.X)
end

-- Wrapped into (-pi, pi], so a 350-degree correction is reported and applied as -10.
local function wrap(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- ===== THE TWO TARGETS =====

-- The middle of the leaderboard arc. Read off the LIVE instances rather than the registry's cached
-- `pos`, which is the trap 30.24 left standing: moving a prop leaves the census's measured position
-- behind, and this file runs after two passes that move props.
--
-- `Suffixes` is a legend rather than a board and `MapBoards` replaces it with `DNABoard` on the
-- legend's own bearing. Whichever of the two is standing when this runs is the one that counts, so
-- both are asked for and a destroyed instance is skipped -- the count comes out at eight either way
-- and the aim does not depend on the order the two files run in.
local function boardsAim(zoneKey, map)
	local sx, sz, n = 0, 0, 0
	local function add(inst)
		if not (inst and inst.Parent) then return end
		local cf = inst:IsA("Model") and inst:GetBoundingBox() or inst.CFrame
		sx += cf.Position.X
		sz += cf.Position.Z
		n += 1
	end
	for _, name in ipairs(MapAnchors.BOARDS) do
		local anchor = MapAnchors.Get(zoneKey, "board", name)
		add(anchor and anchor.inst)
	end
	add(map:FindFirstChild("DNABoard"))
	if n < 3 then return nil end
	return Vector2.new(sx / n, sz / n), ("%d boards"):format(n)
end

-- The mouth of the zone-door hall: the middle of the ring's one deliberate gap.
--
-- MEASURED off the placed doors rather than taken from `MapPortals`' own opening bearing, and the
-- difference matters: what a player walks through is where the doors ACTUALLY are, and a file that
-- re-derived the layout rule would agree with `MapPortals` even on a boot where `MapPortals` warned
-- and left the doors where the artist drew them. The gap is not a close call either -- twenty doors
-- across 288 degrees step 15.2, against a 72-degree mouth.
local function hallAim(_, map)
	local doors = MapPortals.FindDoors(map)
	if #doors < 3 then return nil end
	local centre, radius = MapRing.Fit(doors)
	if not centre then return nil end

	local bearings = {}
	for _, door in ipairs(doors) do bearings[#bearings + 1] = MapRing.Bearing(door, centre) end
	table.sort(bearings)

	local widest, mouth = -1, nil
	for i = 1, #bearings do
		local a = bearings[i]
		local b = (i == #bearings) and (bearings[1] + 2 * math.pi) or bearings[i + 1]
		if b - a > widest then widest, mouth = b - a, a + (b - a) / 2 end
	end

	return Vector2.new(centre.X + math.cos(mouth) * radius, centre.Y + math.sin(mouth) * radius),
		("%d doors, %.0f deg mouth"):format(#doors, math.deg(widest))
end

-- label (lower case, whitespace folded) -> resolver, or `false` for "this names nothing here".
-- A label that is in neither is LEFT ALONE and named in the log: a sign this file does not
-- understand is a sign somebody added, and deleting or turning it on a guess is worse than saying
-- so once a boot.
local TARGET = {
	["top players"] = boardsAim,
	["worlds"] = hallAim,
	["chest"] = false,
}

-- ===== THE ONE ENTRY POINT =====
-- `zone` is passed in rather than looked up: `ServerMain` already holds it, and a fourth copy of
-- "where does the village map live" is the one-decision-in-two-files trap this folder has paid for
-- twice (`evolution-lab-zone-geometry-constants`).
function MapSigns.Init(zoneKey, zone)
	local map = zone and zone:FindFirstChild("VillageMap")
	if not (map and MapAnchors.IsMapped(zoneKey)) then return 0 end

	local signs = MapAnchors.Get(zoneKey, "sign") or {}
	local aimed, deleted, left = 0, 0, 0

	for _, pair in ipairs(signs) do
		local text = pair.text and pair.text.inst
		local post = pair.post and pair.post.inst
		if text and text.Parent then
			local key, shown = labelOf(text)
			local resolver = key and TARGET[key]

			if resolver == false then
				-- Both halves, and the post second so a failure leaves the text as the visible
				-- evidence rather than a bare pole nobody can name.
				if post then post:Destroy() end
				text:Destroy()
				deleted += 1
				print(("[MapSigns] %s: '%s' names nothing this game has -- deleted"):format(zoneKey, shown))
			elseif resolver == nil then
				left += 1
				warn(("[MapSigns] %s: '%s' is not a label this file knows -- left as it is")
					:format(zoneKey, tostring(shown)))
			elseif not (post and post.Parent) then
				-- A label with no post is a label lying on the ground: it is the POST that carries
				-- the arrow, and there is nothing to aim without one.
				left += 1
				warn(("[MapSigns] %s: '%s' has no post beside it -- left as it is"):format(zoneKey, shown))
			else
				local board, pole = boardOf(post), poleOf(post)
				local target, detail = resolver(zoneKey, map)
				if not (board and pole and target) then
					left += 1
					warn(("[MapSigns] %s: '%s' could not be aimed -- board=%s pole=%s target=%s")
						:format(zoneKey, shown, tostring(board ~= nil), tostring(pole ~= nil),
							tostring(target ~= nil)))
				else
					local at = Vector2.new(pole.Position.X, pole.Position.Z)
					local to = target - at
					if to.Magnitude < MIN_RANGE then
						left += 1
						warn(("[MapSigns] %s: '%s' stands %.0f studs from what it names -- left as it is")
							:format(zoneKey, shown, to.Magnitude))
					else
						-- The arrow, then the turn. `MapRing.Spin` about the sign's own pole is a
						-- turn in place, and it carries the text model round with it because the
						-- two are separate top-level children of the map -- the label is NOT a
						-- child of the post it stands on.
						local want = flatBearing(Vector3.new(to.X, 0, to.Y))
						local delta = wrap(want - flatBearing(-board.CFrame.LookVector))
						MapRing.Spin(post, at, delta)
						MapRing.Spin(text, at, delta)
						aimed += 1
						print(("[MapSigns] %s: '%s' -> (%.0f, %.0f) %s, %.0f studs away: turned "
							.. "%+.1f deg, now %.1f off, reads toward %.0f deg")
							:format(zoneKey, shown, target.X, target.Y, detail, to.Magnitude,
								math.deg(delta),
								math.abs(math.deg(wrap(want - flatBearing(-board.CFrame.LookVector)))),
								math.deg(flatBearing(-board.CFrame.RightVector))))
					end
				end
			end
		end
	end

	print(("[MapSigns] %s: %d signs -- %d aimed, %d deleted, %d left alone")
		:format(zoneKey, #signs, aimed, deleted, left))
	return aimed
end

return MapSigns
