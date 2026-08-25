-- ZoneGate -- the doorway between two zones.
--
-- Twenty-one platforms in a line, and the only way from one to the next is through the gap in the
-- wall between them. That gap is the most-looked-at object in the game after the egg stall: every
-- player walks through forty of them on the way to the end, so it is built as real stonework --
-- jambs, a lintel, a keystone, a lit arch and a name board -- instead of a hole.
--
-- WHERE THE LINE IS: this file builds a gateway. `ZoneBuilder` decides which walls have one and
-- what is on the other side. `buildPortal` is written in the plane x = wallX with local +X pointing
-- at the interior; `buildPortalInZWall` is the same gateway turned a quarter and stood in a Z wall,
-- and it is a separate function only because that rotation is easy to get backwards.
--
-- WHO REQUIRES IT: `ZoneBuilder`, for the walls -- and `EventArena`, whose way home is the same
-- gateway. That second caller is why this is a file of its own rather than more of `ZoneBuilder`:
-- the arena is not part of a zone and should not have to reach into the zone builder for a door.
--
-- `PORTAL_CLEAR_HALF` IS EXPORTED AND IS NOT USED IN HERE. It is how far the boundary boulders stay
-- off the centre line, read by `addRockRampart` in `ZoneBuilder`. It lives here because it is the
-- GATE's width that decides it.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ZoneKit = require(script.Parent.ZoneKit)

local newPart, addPlankText, vivid = ZoneKit.newPart, ZoneKit.addPlankText, ZoneKit.vivid
local spinForever, pulseForever = ZoneKit.spinForever, ZoneKit.pulseForever
local addLight, PORTAL_GAP = ZoneKit.addLight, ZoneKit.PORTAL_GAP

-- ===== portal gateway =====
-- The gate is the landmark on every zone boundary, so it is built as real stonework instead of
-- a lit hole in the wall: two flanking columns with diamond inlays and a stepped capital, a
-- rune-studded frame hugging the opening, a lintel under an overhanging cap, and a swirling
-- energy sheet. It all lives in the YZ plane at x = wallX, so "width" runs along Z and "depth"
-- along X, and detail parts are only built on the one face a player can ever stand in front of.
local PORTAL_OPEN_H = 138     -- height of the energy sheet; its width is PORTAL_GAP
local PORTAL_CLEAR_HALF = 132 -- how far boulders stay off the centre line, see addCliffLine
local PORTAL_STONE = Color3.fromRGB(129, 154, 184)
local PORTAL_STONE_DARK = Color3.fromRGB(92, 114, 145)
local PORTAL_STONE_LITE = Color3.fromRGB(163, 185, 211)
local PORTAL_FRAME = Color3.fromRGB(45, 84, 145)
local PORTAL_DEEP = Color3.fromRGB(20, 38, 74)

-- One gateway, centred on (wallX, 0) in the wall plane. `target` is the zone it leads to, and its
-- accent colour drives every glowing element so the gate still tells you where it goes.
local function buildPortal(model, wallX, target, faceOverride)
	-- the far side of a boundary wall is the empty gap between platforms and is never walkable,
	-- so only the interior face needs runes and inlays -- that halves the part count per gate.
	-- A gate stood through ACTIVE_FRAME passes its facing in, since in that case the target's
	-- world offset says nothing about which side of the *local* plane the zone is on.
	local face = faceOverride or ((target.offset < wallX) and 1 or -1)
	local accent = vivid(target.accentColor)
	local glow = accent:Lerp(Color3.new(1, 1, 1), 0.4)
	local gapHalf = PORTAL_GAP / 2
	local openH = PORTAL_OPEN_H
	local midY = openH / 2

	-- Every gate used to be cut from the same blue stone, so from across a zone the two exits were
	-- indistinguishable and neither told you where it went. Tinting the masonry toward the
	-- destination's accent keeps it reading as stone while making the gate itself the signpost.
	local stone = PORTAL_STONE:Lerp(accent, 0.3)
	local stoneDark = PORTAL_STONE_DARK:Lerp(accent, 0.3)
	local stoneLite = PORTAL_STONE_LITE:Lerp(accent, 0.22)
	local frame = PORTAL_FRAME:Lerp(target.accentColor, 0.55)

	-- ENERGY: the sheet you walk into. Opaque neon, so it hints at the destination colour
	-- without ever showing the zone behind it.
	local gate = newPart({
		Name = "PortalGate",
		Size = Vector3.new(2, openH, PORTAL_GAP),
		Position = Vector3.new(wallX, midY, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.05,
		-- Solid, not a curtain. Walking into the sheet fires Touched and ZoneService teleports you --
		-- but it refuses while the destination is still locked, and with the sheet passable that same
		-- step carried the player straight on through the opening and off the world: there is no
		-- floor at all in the gap between two platforms. A blocked contact still fires Touched, so
		-- an open gate works exactly as before.
		CanCollide = true,
		CanTouch = true,
		CastShadow = false,
		Parent = model,
	})
	gate:SetAttribute("TargetZone", target.key)

	-- two counter-rotating pinwheels in front of the sheet give it the swirl. Each blade is a
	-- diameter through the centre, so a set at 0/60/120 deg is unchanged by a 60 deg turn.
	-- Thin and mostly transparent on purpose. The first pass used five fat opaque blades and the
	-- gate read as a white asterisk painted on a yellow board rather than as moving light.
	for i = 0, 2 do
		local base = CFrame.new(wallX + face * 1.6, midY, 0) * CFrame.Angles(math.rad(i * 60), 0, 0)
		local blade = newPart({ Name = "PortalBlade", Size = Vector3.new(0.6, 2.4, 74), CFrame = base, Color = glow, Material = Enum.Material.Neon, Transparency = 0.74, CanCollide = false, CastShadow = false, Parent = model })
		spinForever(blade, base, 60, 13)
	end
	for i = 0, 1 do
		local base = CFrame.new(wallX + face * 2.3, midY, 0) * CFrame.Angles(math.rad(45 + i * 90), 0, 0)
		local blade = newPart({ Name = "PortalBlade", Size = Vector3.new(0.6, 4.5, 50), CFrame = base, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Transparency = 0.85, CanCollide = false, CastShadow = false, Parent = model })
		spinForever(blade, base, -90, 8)
	end

	-- the eye of the vortex: three nested discs, each brighter and smaller, so the blades read as
	-- spinning *into* something instead of crossing in empty space
	for i, d in ipairs({ 34, 21, 11 }) do
		local core = newPart({ Name = "PortalCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, d, d), Orientation = Vector3.new(0, 90, 0), Position = Vector3.new(wallX + face * (1.2 + i * 0.35), midY, 0), Color = i == 3 and Color3.new(1, 1, 1) or glow, Material = Enum.Material.Neon, Transparency = 0.62 - i * 0.14, CanCollide = false, CastShadow = false, Parent = model })
		pulseForever(core, 0.82 - i * 0.16, 2.4 + i * 0.7)
	end

	-- vertical streaks breathing out of phase: the "liquid light" read of the reference art
	for i, z in ipairs({ -27, -10, 10, 27 }) do
		local streak = newPart({ Name = "PortalStreak", Size = Vector3.new(0.5, openH - 18, 3.4), Position = Vector3.new(wallX + face * 3, midY, z), Color = glow, Material = Enum.Material.Neon, Transparency = 0.42, CanCollide = false, CastShadow = false, Parent = model })
		pulseForever(streak, 0.85, 1.5 + i * 0.5)
	end

	-- LIP: a dark rebate right against the glow so the sheet has a crisp edge instead of
	-- bleeding straight into the stonework
	local lipT, lipD = 6, 16
	newPart({ Name = "PortalLip", Size = Vector3.new(lipD, openH + lipT, lipT), Position = Vector3.new(wallX, midY + lipT / 2, -(gapHalf + lipT / 2)), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalLip", Size = Vector3.new(lipD, openH + lipT, lipT), Position = Vector3.new(wallX, midY + lipT / 2, gapHalf + lipT / 2), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalLip", Size = Vector3.new(lipD, lipT, PORTAL_GAP + lipT * 2), Position = Vector3.new(wallX, openH + lipT / 2, 0), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, Parent = model })
	-- ... and a sill, because the sheet never touches the floor in the reference art. It has to
	-- be non-colliding: it stands in the walkway, and the gate must stay reachable by a player.
	newPart({ Name = "PortalSill", Size = Vector3.new(lipD + 2, 9, PORTAL_GAP + lipT * 2), Position = Vector3.new(wallX, 4.5, 0), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })

	-- FRAME: the blue band that carries the runes. Its top piece doubles as the wall above the
	-- opening, so there is never a line of sight between the sheet and the lintel.
	local bandT, bandD = 14, 22
	local bandZ = gapHalf + lipT + bandT / 2
	local bandH = openH + lipT + bandT
	local bandTopY = bandH - bandT / 2
	newPart({ Name = "PortalFrame", Size = Vector3.new(bandD, bandH, bandT), Position = Vector3.new(wallX, bandH / 2, -bandZ), Color = frame, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalFrame", Size = Vector3.new(bandD, bandH, bandT), Position = Vector3.new(wallX, bandH / 2, bandZ), Color = frame, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalFrame", Size = Vector3.new(bandD, bandT, PORTAL_GAP + (lipT + bandT) * 2), Position = Vector3.new(wallX, bandTopY, 0), Color = frame, Material = Enum.Material.SmoothPlastic, Parent = model })

	-- Runes, not rivets. Square neon tiles in a near-white glow read as a row of light bulbs
	-- around a cinema sign; a rotated diamond with a darker keeper behind it reads as carved.
	local runeX = wallX + face * (bandD / 2 + 0.4)
	local function rune(y, z)
		newPart({ Name = "PortalRuneKeeper", Size = Vector3.new(1, 9, 9), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(runeX, y, z), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "PortalRune", Size = Vector3.new(1.6, 5.4, 5.4), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(runeX + face * 0.5, y, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
	end
	for _, z in ipairs({ -bandZ, bandZ }) do
		for row = 0, 5 do
			rune(16 + row * 22, z)
		end
	end
	for _, z in ipairs({ -30, 0, 30 }) do
		rune(bandTopY, z)
	end

	-- LINTEL + CAP: the heavy beam that makes the gate read as built rather than carved
	local lintelY = bandH + 8
	newPart({ Name = "PortalLintel", Size = Vector3.new(bandD + 4, 17, 150), Position = Vector3.new(wallX, lintelY, 0), Color = PORTAL_STONE, Material = Enum.Material.Concrete, Parent = model })
	newPart({ Name = "PortalCap", Size = Vector3.new(bandD + 12, 9, 164), Position = Vector3.new(wallX, lintelY + 13, 0), Color = PORTAL_STONE_LITE, Material = Enum.Material.Concrete, Parent = model })

	-- KEYSTONE: a cut gem sitting in the middle of the lintel. A gateway this wide needs a centre
	-- or the eye slides straight off the beam -- and it is the one piece that is pure jewellery.
	newPart({ Name = "PortalKeystoneSetting", Size = Vector3.new(bandD + 6, 26, 26), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX, lintelY, 0), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
	local keystone = newPart({ Name = "PortalKeystone", Size = Vector3.new(bandD + 9, 15, 15), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX + face * 1.5, lintelY, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
	addLight(keystone, accent, 40, 3)
	pulseForever(keystone, 0.35, 2.6)

	-- DRAPES: two banners hanging off the lintel, either side of the keystone. Cloth against all
	-- that stone is what stops the gate reading as a tomb entrance.
	for _, sz in ipairs({ -52, 52 }) do
		newPart({ Name = "PortalDrape", Size = Vector3.new(1.2, 46, 26), Position = Vector3.new(wallX + face * (bandD / 2 + 1), lintelY - 30, sz), Color = frame, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "PortalDrapeTrim", Size = Vector3.new(1.6, 5, 27), Position = Vector3.new(wallX + face * (bandD / 2 + 1.4), lintelY - 12, sz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "PortalDrapeTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(1.2, 12, 26),
			CFrame = CFrame.new(wallX + face * (bandD / 2 + 1), lintelY - 59, sz) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
			Color = frame, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	end

	-- COLUMNS: free-standing either side with a visible reveal, so the silhouette reads as
	-- column / gate / column rather than one slab
	local colW, colD, colH = 30, 26, 146
	local colZ = bandZ + bandT / 2 + 4 + colW / 2
	for _, sz in ipairs({ -colZ, colZ }) do
		newPart({ Name = "PortalColumnBase", Size = Vector3.new(colD + 6, 9, colW + 6), Position = Vector3.new(wallX, 4.5, sz), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "PortalColumn", Size = Vector3.new(colD, colH, colW), Position = Vector3.new(wallX, colH / 2 + 4, sz), Color = stone, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "PortalColumnCap", Size = Vector3.new(colD + 6, 12, colW + 6), Position = Vector3.new(wallX, colH + 10, sz), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "PortalColumnCap", Size = Vector3.new(colD + 11, 6, colW + 11), Position = Vector3.new(wallX, colH + 19, sz), Color = stoneLite, Material = Enum.Material.Concrete, Parent = model })
		-- diamond inlays: a dark lozenge with a lighter core, the signature detail of the art
		for row = 0, 3 do
			local y = 28 + row * 34
			newPart({ Name = "ColumnInlay", Size = Vector3.new(1.6, 13, 13), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX + face * (colD / 2 + 0.5), y, sz), Color = stoneDark, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
			newPart({ Name = "ColumnInlay", Size = Vector3.new(1.6, 7, 7), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX + face * (colD / 2 + 1.4), y, sz), Color = row == 1 and accent or stoneLite, Material = row == 1 and Enum.Material.Neon or Enum.Material.Concrete, CanCollide = false, Parent = model })
		end
		-- a lit brazier on each capital, so the gate is legible at any ClockTime and from the far
		-- side of the platform
		local flame = newPart({ Name = "PortalFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(13, 15, 13), Position = Vector3.new(wallX, colH + 28, sz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		addLight(flame, accent, 52, 4)
		pulseForever(flame, 0.4, 1.9)
	end

	-- CRYSTALS: four shards turning slowly in the mouth of the gate, two either side. They are the
	-- only moving thing at the boundary that is not the sheet itself, and they sell the gate as
	-- charged rather than merely lit.
	for i, spec in ipairs({ { -1, 34, 74 }, { 1, 34, 74 }, { -1, 96, 58 }, { 1, 96, 58 } }) do
		local base = CFrame.new(wallX + face * 7, spec[2], spec[1] * spec[3]) * CFrame.Angles(0, 0, math.rad(spec[1] * 16))
		local shard = newPart({ Name = "PortalCrystal", Size = Vector3.new(5, 19, 5), CFrame = base, Color = glow, Material = Enum.Material.Neon, Transparency = 0.22, CanCollide = false, CastShadow = false, Parent = model })
		addLight(shard, accent, 26, 2)
		spinForever(shard, base, 360, 9 + i)
	end

	-- GUARDIANS: a squat statue on a plinth either side of the steps. Two of them turn a doorway
	-- into a threshold somebody built and meant, which is the whole difference between a gate and
	-- a hole in a wall.
	for _, sz in ipairs({ -1, 1 }) do
		local gz = sz * (PORTAL_GAP / 2 + 46)
		local gx = wallX + face * 46
		newPart({ Name = "GuardianPlinth", Size = Vector3.new(26, 12, 26), Position = Vector3.new(gx, 6, gz), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "GuardianPlinthTrim", Size = Vector3.new(29, 2.4, 29), Position = Vector3.new(gx, 13, gz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		newPart({ Name = "GuardianBody", Size = Vector3.new(19, 26, 17), Orientation = Vector3.new(0, face * -90, 0), Position = Vector3.new(gx, 26, gz), Color = stone, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "GuardianHead", Size = Vector3.new(15, 14, 14), Orientation = Vector3.new(0, face * -90, 0), Position = Vector3.new(gx, 45, gz), Color = stoneLite, Material = Enum.Material.Concrete, Parent = model })
		for _, ex in ipairs({ -1, 1 }) do
			newPart({ Name = "GuardianEye", Size = Vector3.new(2, 3, 3), Position = Vector3.new(gx + face * 7.4, 47, gz + ex * 3.6), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		end
		-- folded arms, and a horn either side of the head: a readable silhouette at four parts
		newPart({ Name = "GuardianArms", Size = Vector3.new(21, 6, 12), Orientation = Vector3.new(0, face * -90, 0), Position = Vector3.new(gx + face * 2, 24, gz), Color = stoneDark, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
		for _, ex in ipairs({ -1, 1 }) do
			newPart({ Name = "GuardianHorn", Size = Vector3.new(4, 12, 4), Orientation = Vector3.new(0, 0, ex * 24), Position = Vector3.new(gx, 55, gz + ex * 6), Color = stoneDark, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
		end
		local bowl = newPart({ Name = "GuardianBrazier", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 12, 11), Position = Vector3.new(gx, 64, gz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		addLight(bowl, accent, 44, 3)
		pulseForever(bowl, 0.4, 2.2 + (sz > 0 and 0.5 or 0))
	end

	-- APPROACH: a lit mat and three steps in front of the opening. Without them the gate is a door
	-- with no doorstep -- the ground just runs into it and there is nothing telling you to walk in.
	-- tallest against the wall, shortest furthest out, so the run actually climbs toward the gate
	for i = 1, 4 do
		local h = 6.4 - (i - 1) * 1.6
		newPart({ Name = "PortalStep", Size = Vector3.new(12, h, PORTAL_GAP + 34 - i * 6), Position = Vector3.new(wallX + face * (9 + (i - 1) * 11), h / 2, 0), Color = i == 1 and stoneLite or stone, Material = Enum.Material.Concrete, Parent = model })
	end
	newPart({ Name = "PortalMat", Size = Vector3.new(34, 0.4, PORTAL_GAP - 2), Position = Vector3.new(wallX + face * 56, 0.4, 0), Color = accent, Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, CastShadow = false, Parent = model })

	-- Rich dimensional particle vortex
	local vortex = Instance.new("ParticleEmitter")
	vortex.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	-- 32.31: these keypoints were NumberSequenceKeypoints carrying Color3 values, which throws
	-- "invalid argument #2 to 'new' (number expected, got Color3)" -- and buildPortal dies at the
	-- first gate, taking the WHOLE ZoneBuilder.Build with it (found 2026-08-25 by forcing Forest's
	-- first fresh rebuild since the file was last touched; every boot in between had skipped the
	-- zones as already-built, so a crash this loud sat latent for that whole time). A color
	-- gradient takes ColorSequenceKeypoints.
	vortex.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, glow),
		ColorSequenceKeypoint.new(1, accent),
	})
	vortex.Rate = 28
	vortex.Lifetime = NumberRange.new(2.0, 4.0)
	vortex.Speed = NumberRange.new(2, 8)
	vortex.SpreadAngle = Vector2.new(45, 45)
	vortex.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.3, 3.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	vortex.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	vortex.LightEmission = 1
	vortex.LightInfluence = 0
	vortex.Rotation = NumberRange.new(0, 360)
	vortex.RotSpeed = NumberRange.new(-80, 80)
	vortex.Parent = gate

	-- Ambient cosmic mist drifting outward
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(accent, glow)
	mist.Rate = 12
	mist.Lifetime = NumberRange.new(3.0, 5.5)
	mist.Speed = NumberRange.new(1, 4)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Size = NumberSequence.new(6, 16)
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.4, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.LightEmission = 0.8
	mist.LightInfluence = 0
	mist.Parent = gate

	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 64
	light.Brightness = 6
	light.Shadows = false
	light.Parent = gate

	local surfLight = Instance.new("SurfaceLight")
	surfLight.Color = glow
	surfLight.Face = Enum.NormalId.Front
	surfLight.Range = 45
	surfLight.Brightness = 4
	surfLight.Parent = gate

	-- THE NAME BOARD, BOLTED TO THE GATE.
	--
	-- It was a BillboardGui hanging 26 studs over the lintel, and a billboard turns to face the
	-- camera: from anywhere except straight on it read as a sign hovering in mid-air beside the
	-- gate rather than as part of it, and from behind the wall it still faced you, through solid
	-- stone. A player asked for exactly this and was right -- it should sit ON the gateway, the way
	-- the walkway direction signs sit on their posts.
	--
	-- So: a real board standing on the cap, with the name painted onto both broad faces. Built with
	-- a 90-degree yaw because buildPortal works in the plane x = wallX -- the board's own length has
	-- to run along Z (the wall) and its faces have to look along X (out of the zone and into it).
	-- 104 x 34 rather than the full 164 of the cap it stands on. A board matched to the stonework
	-- came out five times wider than it was tall, and the name is one short word: TextScaled fills
	-- by HEIGHT, so all the extra width bought was empty plate either side of a small word.
	local boardY = lintelY + 33
	local boardHalf = 52
	local boardWood = Color3.fromRGB(122, 84, 50)
	local boardTurn = CFrame.Angles(0, math.rad(90), 0)
	local board = newPart({ Name = "PortalNameBoard", Size = Vector3.new(boardHalf * 2, 34, 4),
		CFrame = CFrame.new(wallX + face * 2, boardY, 0) * boardTurn,
		Color = boardWood, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	-- a batten across each end, so it reads as joined boards rather than one slab -- the same
	-- detail the walkway signs use, which is what makes the two read as the same set of objects
	for _, sz in ipairs({ -1, 1 }) do
		newPart({ Name = "PortalNameBatten", Size = Vector3.new(5, 39, 5.4),
			CFrame = CFrame.new(wallX + face * 2, boardY, sz * (boardHalf - 2)) * boardTurn,
			Color = stoneDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
		newPart({ Name = "PortalNameKnob", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8),
			Position = Vector3.new(wallX + face * 2, boardY + 19.5, sz * (boardHalf - 2)),
			Color = stoneLite, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
	end
	-- Long reach and a MUCH coarser canvas than the walkway signs get. Both halves of that matter,
	-- and the second one is not an optimisation -- it is the difference between the board having
	-- text on it and not. A SurfaceGui's canvas is PixelsPerStud x the part, so on a board this size
	-- the walkway's 32 px/stud is a 3,300 x 1,000 texture for one word, and a canvas that large
	-- stops being drawn well before MaxDistance -- measured: blank from 250 studs, which is exactly
	-- the range this sign exists to be read at. 8 still leaves the word ~670 px wide.
	addPlankText(board, "🌀 " .. target.emoji .. " " .. target.name, vivid(target.accentColor),
		{ maxDistance = 700, pixelsPerStud = 8 })
end

-- The same gateway, stood in a Z wall. buildPortal is written in the plane x = wallX with +X
-- pointing into the zone, so all this does is hand it that plane: yaw +90 for the far (+Z) wall,
-- -90 for the near one, and the interior is local +X in both cases.
--
-- The gates moved off the X walls for one reason: arriving in a zone, walking the street, buying
-- an egg and leaving by the next gate now happen along one straight line down the middle of the
-- platform. On the X walls they sat at right angles to that line, so the shop and its walkway
-- read as rotated ninety degrees from the way the player was actually facing.
local function buildPortalInZWall(model, cx, wallZ, target)
	local previous = ZoneKit.getFrame()
	ZoneKit.setFrame(CFrame.new(cx, 0, wallZ) * CFrame.Angles(0, math.rad(wallZ > 0 and 90 or -90), 0))
	buildPortal(model, 0, target, 1)
	ZoneKit.setFrame(previous)
end

return {
	buildPortal = buildPortal,
	buildPortalInZWall = buildPortalInZWall,
	PORTAL_CLEAR_HALF = PORTAL_CLEAR_HALF,
}
