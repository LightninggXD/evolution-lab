-- VillageKit -- what the village is MADE OF: the per-zone palette every hand-placed structure is
-- dressed in, the four soft shapes that turn a box into a toy, and the prop library itself -- the
-- lamp, the shop kiosk, the well and the mesh loader they are all built through.
--
-- WHERE THE LINE IS: this file owns what a village is made of; `ZoneBuilder` owns where each piece
-- goes. `addZoneVillage` still decides that the lamps run every 30 studs from z = 420 and that the
-- shop stands at cx - 150; `buildZoneShop` still hangs the ProximityPrompts and reads `GameConfig`.
-- None of that moved. What moved is the vocabulary those three functions speak.
--
-- WHY IT IS BIGGER THAN "THE VILLAGE PROP LIBRARY" (18.10)
-- --------------------------------------------------------
-- `docs/SPLIT.md` §6 names the prop library as the first leaf out of `ZoneBuilder` and describes
-- each leaf as "a section that only reads the kit". The prop library nearly is, and the gap is the
-- whole reason this file has a palette in it: `addLamp`, `addWell` and `addPlanter` paint
-- themselves out of colours that are **reassigned per zone**. A module that copied those at require
-- time would be frozen on the Forest set forever, with no error anywhere -- `docs/SPLIT.md` §3
-- rule 2, which `ACTIVE_FRAME` already paid for once in `ZoneKit`. So the palette comes with the
-- props, and the soft-prop vocabulary comes with the palette because three of its five read it.
--
-- Cutting only the 231 lines §6 named would also have been register-NEGATIVE -- five names out,
-- five re-localised back, plus one for the require -- and the 200-register ceiling is the reason
-- this file is being split at all. This cut takes `ZoneBuilder` from 189 registers to 169.
--
-- NOTHING IS RE-LOCALISED ON THE BUILDER'S SIDE, and that is the opposite of what `ZoneKit` did.
-- `ZoneKit` kept its names local there because `newPart` has 534 call sites and rewriting them
-- would have been 534 chances to break the world for nothing visible. The village verbs have
-- **fifteen** call sites between them. At fifteen, spelling out `VillageKit.addKnob(...)` costs one
-- afternoon of nothing and buys back the registers, and it tells the next reader where the thing
-- lives -- which is the entire point of the split.
--
-- WHO MAY REQUIRE IT: any server script standing village furniture. Nothing but `ZoneBuilder` does
-- today. `HubPlaza` and `RebirthShrine` build their own and are deliberately untouched.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ServerStorage = game:GetService("ServerStorage")

-- The kit is required here and not handed in, so this file stands on its own: `newPart` and the
-- placement frame, plus the four verbs that came down to `ZoneKit` in 18.10 precisely because the
-- village needed them -- `seatModel` for the mesh props, `stoneTones` for the well's cobbles,
-- `makeSign` for the shop's board and `addLight` for everything that glows out here.
local ZoneKit = require(script.Parent.ZoneKit)

local newPart = ZoneKit.newPart
local seatModel, makeSign = ZoneKit.seatModel, ZoneKit.makeSign
local stoneTones, addLight = ZoneKit.stoneTones, ZoneKit.addLight

-- ===== THE PALETTE IS ONE TABLE, AND THE TABLE IS THE POINT =====
--
-- Six live values dress every hand-placed structure in a zone. They were six top-level `local`s in
-- `ZoneBuilder`, reassigned per zone, and that shape cost BUILD_VERSION 133. The note written at
-- the time, kept because it is the reason this is not six re-localised names:
--
--   > These four were authored ~170 lines below, beside the VILLAGE_STYLE table that reassigns them
--   > per zone, which reads well and compiled fine -- and meant the three uses in addZoneProps below
--   > (the crate lid, a knob and the banner emblem) resolved to a nil GLOBAL, so those parts took
--   > Roblox's default grey instead of cream. A `local` is only visible BELOW its own line no matter
--   > where the function is called from. If you move this block, it has to stay above addZoneProps.
--
-- A TABLE HAS NO LINE. Both files hold this one by reference, so all six fields are readable
-- wherever either file is written, and "read above its own declaration" stops being a thing that
-- can happen. It is also the only shape that survives the require at all: the values are
-- reassigned per zone, so a copy taken on the other side would be frozen on Forest forever
-- (`docs/SPLIT.md` §3 rule 2).
--
-- THE FIELDS ARE GUARDED, because the failure they replace is silent. `VILLAGE.crem` is nil, a nil
-- `Color3` paints Roblox's default grey, and nothing errors or logs -- which is exactly how 133
-- survived long enough to ship. `__index` only fires on a field that is not there, so it costs
-- nothing on the six that always are, and it turns a typo into a build-time error instead of a grey
-- part in twenty villages that nobody photographs.
--
-- Live values the builders read. The values here are the Forest set and are the documented
-- fallback; `applyVillageStyle` overwrites all six per zone and is still the only writer.
local VILLAGE = setmetatable({
	wood  = Color3.fromRGB(154, 108, 62),
	dark  = Color3.fromRGB(101, 69, 40),
	cloth = Color3.fromRGB(240, 235, 222),
	cream = Color3.fromRGB(252, 244, 226),
	post  = Enum.Material.Wood,
	board = Enum.Material.WoodPlanks,
}, {
	__index = function(_, key)
		error(("VILLAGE has no field %q -- a nil colour paints default grey and never errors"):format(tostring(key)), 2)
	end,
})

-- ===== THE VILLAGE IS BUILT OF DIFFERENT STUFF IN EVERY ZONE =====
--
-- These six values dress EVERY hand-placed structure in a zone: the street fence, the welcome
-- arch, the name board, the benches, the planters, the well, the stalls and the shop. They began
-- as four colour constants, so all twenty zones were furnished in the same brown pine and the
-- same cream paint -- and that is most of what "every zone is the same template" actually is. The layout was
-- never the loudest part; the MATERIAL was. A pine picket fence with cream caps on the Moon, in
-- the Void and inside a black hole is the same village dropped twenty times.
--
-- They are REASSIGNED per zone rather than threaded through as parameters: fifty-nine lines
-- across a dozen builders read them, and none of those builders is handed the zone. The write
-- happens in one place -- `applyVillageStyle`, called from `ZoneBuilder`'s zone loop right where
-- ACTIVE_ZONE_KEY is set -- so the mutation has exactly one owner and one lifetime.
--
-- Material matters as much as colour here: Wood and WoodPlanks are what say "cottage", and a
-- zone whose village is cut from Basalt, Ice, Marble or Neon reads as a different civilisation
-- without a single part moving.
-- The six values themselves are the `VILLAGE` table at the top of this file -- see the note there
-- for why a table and not six locals. This is where they are documented and where they are
-- reassigned; it is not where they are introduced.

-- The defaults are the Forest set, kept as the fallback so a zone with no entry here builds
-- exactly as it always did.
local VILLAGE_DEFAULT = {
	wood = VILLAGE.wood, dark = VILLAGE.dark,
	cloth = VILLAGE.cloth, cream = VILLAGE.cream,
}

-- ===== THE RULE IS CONTRAST WITH THE GROUND, NOT AGREEMENT WITH THE THEME =====
--
-- The obvious way to write this table is to theme each village to its biome: charred timber in the
-- Volcano, pale stone on the Moon, chrome in the Mirror Universe. That was the first cut and it is
-- WRONG, and the Moon proved it in one screenshot -- a silver-grey fence, arch, benches and name
-- board standing on a 170-grey lunar floor under a white sky simply vanished. The zone came back
-- as a white field with nothing built on it, which is worse than the repeated brown village it
-- replaced: repetition is boring, invisibility is broken.
--
-- The village's job is to be the BUILT thing on the natural ground. So it is picked against the
-- ground's luminance and only then tinted toward the biome:
--
--   ground bright (Desert .78, CelestialThrone .70, Moon .67, MirrorUniverse .60,
--                  AbsolutePlane 1.00) -> DARK village
--   ground dark   (VoidExpanse .02, BlackHole .04, Singularity .06, Multiverse .08,
--                  AntimatterZone .10 ... TimeRift .28) -> BRIGHT village
--   ground mid    (Nebula .35, QuantumRealm .39, Forest .44, Mars .46, Ocean .48) -> either,
--                  chosen for hue contrast instead
--
-- The theme then lives in the HUE and in VILLAGE_MATERIAL below, which is where it can be read
-- without costing legibility: a bone-and-ember village in the Volcano, a charcoal-and-cyan one on
-- the Moon, deep blue and gold on the Celestial Throne.
local VILLAGE_STYLE = {
	-- ---- mid ground: brown timber on green is the original and it works
	Forest         = VILLAGE_DEFAULT,
	Ocean          = { wood = Color3.fromRGB(224, 208, 178), dark = Color3.fromRGB(152, 132, 102), cloth = Color3.fromRGB(250, 244, 226), cream = Color3.fromRGB(252, 250, 240) },
	Mars           = { wood = Color3.fromRGB(232, 214, 182), dark = Color3.fromRGB(160, 140, 108), cloth = Color3.fromRGB(250, 236, 210), cream = Color3.fromRGB(252, 244, 226) },
	Nebula         = { wood = Color3.fromRGB(252, 224, 240), dark = Color3.fromRGB(186, 138, 178), cloth = Color3.fromRGB(150, 240, 236), cream = Color3.fromRGB(252, 240, 250) },
	QuantumRealm   = { wood = Color3.fromRGB(206, 246, 252), dark = Color3.fromRGB(124, 190, 210), cloth = Color3.fromRGB(232, 250, 254), cream = Color3.fromRGB(244, 253, 255) },

	-- ---- BRIGHT ground -> DARK village
	Desert         = { wood = Color3.fromRGB(122, 80, 48),   dark = Color3.fromRGB(74, 48, 28),    cloth = Color3.fromRGB(244, 222, 178), cream = Color3.fromRGB(250, 238, 206) },
	-- charcoal and cyan: a moonbase, not a moon rock
	Moon           = { wood = Color3.fromRGB(72, 76, 92),    dark = Color3.fromRGB(40, 44, 56),    cloth = Color3.fromRGB(150, 226, 250), cream = Color3.fromRGB(198, 232, 248) },
	MirrorUniverse = { wood = Color3.fromRGB(58, 64, 84),    dark = Color3.fromRGB(32, 36, 50),    cloth = Color3.fromRGB(196, 216, 244), cream = Color3.fromRGB(214, 230, 250) },
	-- deep royal blue carrying gold. Gold on gold sand is invisible; gold on navy is a throne room.
	CelestialThrone= { wood = Color3.fromRGB(56, 62, 116),   dark = Color3.fromRGB(32, 36, 74),    cloth = Color3.fromRGB(250, 226, 150), cream = Color3.fromRGB(248, 214, 118) },
	-- the only pure-white ground in the game, so the only truly black village
	AbsolutePlane  = { wood = Color3.fromRGB(44, 40, 58),    dark = Color3.fromRGB(22, 20, 32),    cloth = Color3.fromRGB(196, 150, 246), cream = Color3.fromRGB(126, 112, 168) },

	-- ---- DARK ground -> BRIGHT village
	-- bone and ember. The charred-timber version of this was dark-on-dark and disappeared exactly
	-- the way the Moon did.
	Volcano        = { wood = Color3.fromRGB(214, 190, 178), dark = Color3.fromRGB(150, 124, 114), cloth = Color3.fromRGB(255, 148, 92),  cream = Color3.fromRGB(248, 234, 224) },
	Galaxy         = { wood = Color3.fromRGB(200, 186, 250), dark = Color3.fromRGB(142, 126, 200), cloth = Color3.fromRGB(232, 222, 255), cream = Color3.fromRGB(242, 236, 255) },
	BlackHole      = { wood = Color3.fromRGB(186, 176, 214), dark = Color3.fromRGB(124, 116, 156), cloth = Color3.fromRGB(190, 142, 255), cream = Color3.fromRGB(224, 218, 244) },
	Multiverse     = { wood = Color3.fromRGB(220, 200, 244), dark = Color3.fromRGB(158, 136, 190), cloth = Color3.fromRGB(252, 226, 250), cream = Color3.fromRGB(248, 240, 254) },
	Wormhole       = { wood = Color3.fromRGB(154, 240, 222), dark = Color3.fromRGB(92, 176, 166),  cloth = Color3.fromRGB(224, 252, 244), cream = Color3.fromRGB(236, 253, 248) },
	TimeRift       = { wood = Color3.fromRGB(232, 202, 130), dark = Color3.fromRGB(172, 142, 76),  cloth = Color3.fromRGB(250, 238, 194), cream = Color3.fromRGB(252, 244, 214) },
	AntimatterZone = { wood = Color3.fromRGB(230, 226, 236), dark = Color3.fromRGB(164, 160, 178), cloth = Color3.fromRGB(255, 118, 222), cream = Color3.fromRGB(252, 248, 254) },
	DreamDimension = { wood = Color3.fromRGB(230, 210, 252), dark = Color3.fromRGB(172, 150, 208), cloth = Color3.fromRGB(198, 250, 240), cream = Color3.fromRGB(250, 246, 255) },
	VoidExpanse    = { wood = Color3.fromRGB(158, 154, 190), dark = Color3.fromRGB(102, 98, 134),  cloth = Color3.fromRGB(146, 134, 210), cream = Color3.fromRGB(196, 192, 220) },
	Singularity    = { wood = Color3.fromRGB(166, 188, 240), dark = Color3.fromRGB(102, 124, 182), cloth = Color3.fromRGB(210, 228, 255), cream = Color3.fromRGB(228, 240, 255) },
}

-- Which material the "timber" of a village is actually cut from. Absent = Wood/WoodPlanks, i.e.
-- unchanged. Two entries per zone because the code uses Wood for posts and WoodPlanks for boards
-- and boxes, and swapping only one of them leaves a plank fence with metal legs.
local VILLAGE_MATERIAL = {
	Ocean          = { post = Enum.Material.Slate,     board = Enum.Material.Slate },
	Volcano        = { post = Enum.Material.Basalt,    board = Enum.Material.Basalt },
	Moon           = { post = Enum.Material.Metal,     board = Enum.Material.DiamondPlate },
	Mars           = { post = Enum.Material.Sandstone, board = Enum.Material.Sandstone },
	Galaxy         = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	BlackHole      = { post = Enum.Material.Slate,     board = Enum.Material.Slate },
	Multiverse     = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	Nebula         = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	Wormhole       = { post = Enum.Material.Metal,     board = Enum.Material.DiamondPlate },
	QuantumRealm   = { post = Enum.Material.Glass,     board = Enum.Material.Glass },
	TimeRift       = { post = Enum.Material.Metal,     board = Enum.Material.CorrodedMetal },
	AntimatterZone = { post = Enum.Material.Metal,     board = Enum.Material.DiamondPlate },
	DreamDimension = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	MirrorUniverse = { post = Enum.Material.Metal,     board = Enum.Material.Metal },
	VoidExpanse    = { post = Enum.Material.Slate,     board = Enum.Material.Slate },
	CelestialThrone= { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	Singularity    = { post = Enum.Material.Metal,     board = Enum.Material.Metal },
	AbsolutePlane  = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
}

-- ===== THE OUTLINE TIER, AND WHY IT IS NOT SIMPLY "DARKER" =====
--
-- Measured across 443 street-level props in Forest: **not one** was near-ink. The darkest thing on
-- the whole street was a glow post at value 0.35, and the structural colour every prop hangs off
-- (`VILLAGE.dark`) sat at 0.40. So the world had no outline tier at all -- everything from the
-- fence to the lamp to the bench was a mid-tone against a mid-tone ground, which is exactly what
-- "flat and pastel" is made of. The house style's first rule is the dark contour (see the chunky
-- look notes); the HUD has it, the icons have it, the props did not.
--
-- The seventeen sites that read `VILLAGE.dark` are all skeleton -- lamp foot, post, bracket
-- and roof, fence rail, arch pillar, bench leg, planter rim, sign post and batten. Pushing that one
-- colour is therefore a whole-world outline pass for one line, with no new parts anywhere.
--
-- IT IS A CONTRAST TRIM, NOT A DARK TRIM, and that distinction is what keeps it from repeating the
-- mistake the village palette above already paid for: a silver village on the Moon's pale ground
-- vanished, so villages are picked AGAINST THE GROUND. If the trim were unconditionally dark it
-- would vanish the same way -- on the bright-ground zones the village body is itself dark, and
-- ink-on-ink is invisible.
--
-- The trim contrasts with the THING IT OUTLINES rather than with the background, which is the whole
-- point of an outline and is also why it can be decided here from one colour: a light body gets a
-- near-ink trim, and a body already dark gets a bone one. Either way the prop reads as drawn.
-- THE FLIP POINT IS 0.32, AND 0.42 WAS WRONG -- Forest is the case that proves it. Its wood-dark
-- is a mid brown at value 0.396, which is not "already dark" in any useful sense: it carries an ink
-- trim perfectly well. At 0.42 it took the flip instead and every fence rail, bench leg and planter
-- rim in the starting zone came out CREAM. Below 0.32 are the five genuinely dark bodies (Absolute
-- 0.13, Mirror 0.20, Moon 0.22, Desert and Celestial 0.29) -- the bright-ground zones, which is
-- exactly the set the flip exists for.
--
-- The audit that missed this checked all nineteen palettes in `VILLAGE_STYLE` and passed. Forest is
-- not in that table -- it is `VILLAGE_DEFAULT`, the fallback -- so the one zone every player starts
-- in was the one zone the check did not cover. **A table-driven audit has to include the default.**
local function trimFor(body)
	local h, s, v = Color3.toHSV(body)
	if v > 0.32 then
		-- room to go down: genuine ink, hue kept so oak trims brown and marble trims blue-grey
		return Color3.fromHSV(h, math.min(s * 1.08, 1), math.max(v * 0.34, 0.13))
	end
	-- already dark; going darker would erase it, so the outline goes the other way
	return Color3.fromHSV(h, s * 0.5, math.min(v * 2.5 + 0.12, 0.93))
end

local function applyVillageStyle(key)
	local s = VILLAGE_STYLE[key] or VILLAGE_DEFAULT
	VILLAGE.wood = s.wood
	-- `s.dark` is the authored mid-tone shade of the body, and it stays available as that; what the
	-- skeleton wants is a step further than "a bit darker", so it is derived rather than authored --
	-- twenty hand-picked ink colours would be twenty chances for one of them to be wrong.
	VILLAGE.dark = trimFor(s.dark)
	VILLAGE.cloth, VILLAGE.cream = s.cloth, s.cream
	local m = VILLAGE_MATERIAL[key]
	VILLAGE.post = m and m.post or Enum.Material.Wood
	VILLAGE.board = m and m.board or Enum.Material.WoodPlanks
end

-- The candy palette every soft prop below picks from. Deliberately not derived from the zone
-- accent: the accent already colours the neon, the trim and the lights, and when the bunting and
-- the flowers took it too every zone collapsed into one hue. A fixed sweet-shop set of colours
-- against the biome's own greens and rusts is what reads as *decoration* rather than as more biome.
local CANDY = {
	Color3.fromRGB(255, 128, 158), -- bubblegum
	Color3.fromRGB(255, 206, 92),  -- butter
	Color3.fromRGB(126, 220, 232), -- sky
	Color3.fromRGB(180, 152, 255), -- lilac
	Color3.fromRGB(140, 226, 148), -- mint
	Color3.fromRGB(255, 158, 110), -- peach
}

local function candy(i)
	return CANDY[((i - 1) % #CANDY) + 1]
end

-- ---- shared soft-prop vocabulary ----
-- Four shapes that turn a box into a toy: a rounded cap, a scalloped skirt, a pennant string and
-- a planter. Everything on the street is built out of these, which is what makes the street read
-- as one set rather than as a pile of unrelated props.

-- A ball sitting on top of a post. One part, and it is the single biggest difference between a
-- fence that looks like a row of stakes and one that looks drawn.
local function addKnob(model, pos, size, color, material)
	return newPart({
		Name = "Knob", Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size), Position = pos,
		Color = color, Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false, CastShadow = false, Parent = model,
	})
end

-- The scalloped skirt hanging off an awning or a roof: a row of half-domes, alternating two
-- colours. Squashed balls rather than real semicircles -- at this chunky scale the silhouette is
-- all that carries, and a ball costs one part where a proper scallop costs three.
local function addScallops(model, base, width, count, y, z, colorA, colorB, size)
	size = size or 3.4
	for i = 0, count - 1 do
		local t = count > 1 and (i / (count - 1) - 0.5) or 0
		newPart({
			Name = "Scallop", Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.85, size * 0.5),
			CFrame = base * CFrame.new(t * width, y, z),
			Color = (i % 2 == 0) and colorA or colorB,
			Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = model,
		})
	end
end

-- A string of triangular pennants between two points. Each flag is a single Wedge, mirrored turn
-- and turn about so the row reads as alternating triangles -- one part per flag, because a
-- properly symmetric pennant costs two and this runs the length of the street on both sides.
-- The line sags: `droop` is how far the middle of the run hangs below its ends.
local function addBunting(model, fromPos, toPos, count, droop, seed)
	local span = toPos - fromPos
	local dir = span.Unit
	local yaw = math.atan2(-dir.X, -dir.Z)

	-- the cord itself, in two straight segments meeting at the lowest point: a real catenary is
	-- not worth the parts, and two segments already sell the sag
	local mid = fromPos + span * 0.5 - Vector3.new(0, droop, 0)
	for _, seg in ipairs({ { fromPos, mid }, { mid, toPos } }) do
		local a, b = seg[1], seg[2]
		newPart({
			Name = "BuntingCord", Size = Vector3.new(0.3, 0.3, (b - a).Magnitude),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = VILLAGE.dark, Material = Enum.Material.Fabric,
			CanCollide = false, CastShadow = false, Parent = model,
		})
	end

	for i = 1, count do
		local t = i / (count + 1)
		-- height on whichever of the two cord segments this flag hangs from
		local sag = droop * (1 - math.abs(t - 0.5) * 2)
		local at = fromPos + span * t - Vector3.new(0, sag, 0)
		-- A Wedge is a right triangle standing on its long edge -- apex UP, which is a bunting flag
		-- upside down. Rolling it 180 degrees about Z puts the point at the bottom where it belongs
		-- and keeps the height on Y and the width on Z. (Rolling 90, which is what this did first,
		-- laid every flag flat and the street looked strung with coloured drinking straws.)
		newPart({
			Name = "Pennant", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.26, 4.6, 3.4),
			CFrame = CFrame.new(at - Vector3.new(0, 2.3, 0))
				* CFrame.Angles(0, yaw + (i % 2 == 0 and math.pi or 0), 0)
				* CFrame.Angles(0, 0, math.pi),
			Color = candy(i + (seed or 0)), Material = Enum.Material.Fabric,
			CanCollide = false, CastShadow = false, Parent = model,
		})
	end
end

-- A window box of flowers. Three blooms, each a ball on a stem with a paler centre, in a wooden
-- trough. Placed along the street and in front of the stalls.
-- `scale` is for the shop, which is built several times life size: a natural-size window box in
-- front of a 70-stud stall reads as a dropped matchbox. Every other caller passes three arguments
-- and gets exactly what it always got.
local function addPlanter(model, base, seed, scale)
	local s = scale or 1
	newPart({ Name = "PlanterBox", Size = Vector3.new(11, 4, 5.4) * s, CFrame = base * CFrame.new(0, 2 * s, 0), Color = VILLAGE.wood, Material = Enum.Material.WoodPlanks, Parent = model })
	newPart({ Name = "PlanterRim", Size = Vector3.new(12, 0.9, 6.2) * s, CFrame = base * CFrame.new(0, 4.2 * s, 0), Color = VILLAGE.dark, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	newPart({ Name = "PlanterSoil", Size = Vector3.new(10, 1, 4.6) * s, CFrame = base * CFrame.new(0, 4.4 * s, 0), Color = Color3.fromRGB(88, 62, 44), Material = Enum.Material.Ground, CanCollide = false, Parent = model })
	for i = -1, 1 do
		local bloom = candy(i + 2 + (seed or 0))
		newPart({ Name = "FlowerStem", Size = Vector3.new(0.5, 3.2, 0.5) * s, CFrame = base * CFrame.new(i * 3.4 * s, 6.2 * s, 0), Color = Color3.fromRGB(96, 168, 92), Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "FlowerHead", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 2.6, 3.4) * s, CFrame = base * CFrame.new(i * 3.4 * s, 8.2 * s, 0), Color = bloom, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "FlowerHeart", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.3, 1.5) * s, CFrame = base * CFrame.new(i * 3.4 * s, 8.7 * s, 0), Color = VILLAGE.cream, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
	end
end

-- ===== THE VILLAGE PROP LIBRARY =====
--
-- `ServerStorage.PropMeshes.Vill_<Thing>` -- stall, well, cart, lamp, signpost, barrel, planter,
-- fence, bench, crates, anvil, banner post. Twelve models SHARED by all twenty zones, so they are
-- deliberately biome-neutral: wood, stone, cloth and brass, nothing that ties them to one place.
--
-- The street is the one part of the map a player stands right next to, and it was the last thing
-- still made of primitives -- a cube for a crate, a cylinder for a barrel, stacked slabs for a
-- lamp. Next to a meshed boss walking past, that is what read as unfinished.
--
-- Returns nil when nothing is filed, and every caller keeps its primitive path behind that check,
-- so a missing model is a slightly plainer village and never a broken one.
-- `model` IS A PARAMETER, not an upvalue. It was written without one first time round and Lua
-- resolved it to a nil global, so `clone.Parent = nil` -- every lamp in the game silently vanished:
-- the mesh went nowhere AND the primitive path had already been skipped because the mesh "worked".
-- Nothing errored and nothing was logged; the only evidence was a count of zero on both sides.
local function villMesh(model, name, height, base, yawJitter)
	local lib = ServerStorage:FindFirstChild("PropMeshes")
	local template = lib and lib:FindFirstChild("Vill_" .. name)
	if not template then return nil end
	local clone = template:Clone()
	-- measured BEFORE parenting: GetBoundingBox covers every descendant, so measuring after it is
	-- inside the zone model measures the zone
	local _, raw = clone:GetBoundingBox()
	clone:ScaleTo(height / math.max(raw.Y, 0.1))
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			-- generated meshes arrive UNANCHORED; newPart anchors what it makes, nothing anchors these
			part.Anchored = true
			part.CanCollide = false
		end
	end
	clone.Name = "Vill" .. name
	-- ACTIVE_FRAME is what lets a builder written for one spot be re-used anywhere (see newPart);
	-- a mesh placed with a raw CFrame would ignore it and land outside the zone that is being built.
	local active = ZoneKit.getFrame()
	local frame = active and (active * base) or base
	clone.Parent = model
	local pos = frame.Position
	-- seatModel, not PivotTo: these were authored by the generator with their pivots wherever they
	-- landed, and guessing the drop is what once left the Forest trees hovering over the grass.
	seatModel(clone, pos.X, pos.Z, math.atan2(-frame.LookVector.X, -frame.LookVector.Z) + math.rad(yawJitter or 0))
	return clone
end

-- A lantern on a post, hung off the +Z side of `base`. Used along the street and beside every
-- structure below: a settlement reads as a settlement mostly by being lit.
local function addLamp(model, base, color, h)
	h = h or 21

	-- The mesh lamp carries its own post, bracket, housing and glass, so the whole primitive build
	-- below is skipped -- but NOT the light itself. A PointLight is not geometry and the street is
	-- lit by these; dropping it would leave twenty zones dark at the same moment they got prettier.
	local meshLamp = villMesh(model, "Lamp", h + 4, base)
	if meshLamp then
		local glowPart = meshLamp:FindFirstChildWhichIsA("BasePart", true)
		if glowPart then
			addLight(glowPart, color, 20, 0.9)
		end
		return glowPart
	end
	-- a flared foot, so the post meets the ground in something rather than being pushed into it
	newPart({ Name = "LampFoot", Size = Vector3.new(4.2, 1.6, 4.2), CFrame = base * CFrame.new(0, 0.8, 0), Color = VILLAGE.dark, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "LampFootTrim", Size = Vector3.new(3, 0.8, 3), CFrame = base * CFrame.new(0, 2, 0), Color = VILLAGE.cream, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	newPart({ Name = "LampPost", Size = Vector3.new(1.5, h, 1.5), CFrame = base * CFrame.new(0, h / 2, 0), Color = VILLAGE.dark, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "LampBracket", Size = Vector3.new(1, 1, 5), CFrame = base * CFrame.new(0, h - 1.2, 2), Color = VILLAGE.dark, Material = Enum.Material.Metal, CanCollide = false, Parent = model })

	-- The lantern head: a tapered stack instead of one flat plate. Three courses shrinking upward
	-- give the roof a pitch, which is the whole difference between a street lamp and a box on a
	-- stick -- and it gets a knob on top, like everything else out here.
	for i, tier in ipairs({ { 5.6, 1.2 }, { 3.4, 1.1 } }) do
		newPart({ Name = "LampRoof", Size = Vector3.new(tier[1], tier[2], tier[1]), CFrame = base * CFrame.new(0, h - 1.4 + (i - 1) * 1.1, 3.4), Color = i == 1 and VILLAGE.dark or VILLAGE.wood, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	end
	addKnob(model, (base * CFrame.new(0, h + 1.6, 3.4)).Position, 1.8, color, Enum.Material.Neon)

	local glass = newPart({ Name = "LampGlass", Size = Vector3.new(3.8, 4.8, 3.8), CFrame = base * CFrame.new(0, h - 4, 3.4), Color = color, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = model })
	-- a cream collar under the glass, so the light sits in a housing rather than floating
	newPart({ Name = "LampCollar", Size = Vector3.new(4.4, 0.7, 4.4), CFrame = base * CFrame.new(0, h - 6.6, 3.4), Color = VILLAGE.cream, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	addLight(glass, color, 20, 0.9)
	return glass
end

-- HOW BIG EVERY SHOP IS BUILT.
--
-- The stall was authored at 30 x 20 x 23 studs back when the player was a one-stud creature. The
-- character now runs 1.0 -> 5.0 through the chain and stands ~30 studs tall at the top of it, so
-- the only building in the village that actually SELLS anything had become a knee-high box you
-- walked straight past -- reported as "I cannot even see the shop". Everything in `addStall` and
-- in the counters `buildZoneShop` puts on it is multiplied by this one number, so the shop grows
-- as a single object and nothing drifts out of proportion with anything else on it: deck, posts,
-- awning, sign board, bottles, the lamps beside it and the planters in front.
--
-- 2.6 puts the awning ridge at ~57 studs and the name board at ~59 -- taller than the welcome
-- arch (36) and the zone name board (55), which is deliberate: the shop should be the tallest
-- thing on the street, because it is the only one worth walking to. Raising it further starts
-- pushing the front lip toward the walkway (see the clearance note at the call site).
local SHOP_SCALE = 2.6

-- A MODERN KIOSK, not a market stall.
--
-- This was a wooden market stall -- striped canvas awning, scalloped valance, crates, a barrel and
-- flower boxes -- and scaling it up just made a big rustic stall. The shop is the one piece of the
-- village that should read as BUILT rather than pitched, so it is now a white panel-and-glass
-- kiosk: a flat cantilevered canopy, a dark stone counter on a bright shell, a glass back wall and
-- zone-accent light strips doing the decorating the bunting and the flowers used to do.
--
-- Every number is still authored at the old stall's scale and multiplied by SHOP_SCALE on the way
-- out through `at` and `vs`, so one constant still moves the whole thing.
--
-- THE PALETTE IS DELIBERATELY NOT THE VILLAGE'S. Two fixed tones -- a near-white panel and a
-- near-black frame -- with the zone accent used only as light. That pair reads against every
-- ground in the strip; a dark modern shell would disappear in Void and Singularity and a cream one
-- would disappear on Moon. See the village contrast note.
--
-- Returns the counter, which is what a caller hangs a ProximityPrompt on.
local function addStall(model, base, accent, title, wares)
	local S = SHOP_SCALE
	local function at(x, y, z) return base * CFrame.new(x * S, y * S, z * S) end
	local function vs(x, y, z) return Vector3.new(x * S, y * S, z * S) end
	local function pt(x, y, z) return (base * CFrame.new(x * S, y * S, z * S)).Position end

	local PANEL = Color3.fromRGB(244, 247, 252)
	local FRAME = Color3.fromRGB(41, 45, 58)
	local FRAME_LITE = Color3.fromRGB(88, 96, 118)
	local GLASS = accent:Lerp(Color3.new(1, 1, 1), 0.5)

	-- one light strip: neon, never collides, never casts, and carries its own PointLight. Every
	-- accent-coloured thing on this building is one of these, which is what keeps the kiosk two
	-- tones plus light instead of a third painted colour.
	local function strip(name, size, cf, bright, range)
		local p = newPart({ Name = name, Size = size, CFrame = cf, Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		if bright then addLight(p, accent, range or 22, bright) end
		return p
	end

	-- ===== the plinth the whole thing stands on =====
	newPart({ Name = "StallDeck", Size = vs(32, 2, 22), CFrame = at(0, 1, 0), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "StallDeckTop", Size = vs(30, 0.7, 20), CFrame = at(0, 2.3, 0), Color = PANEL, Material = Enum.Material.SmoothPlastic, Parent = model })
	-- the light line around the base. A glowing seam at floor level is the single cheapest thing
	-- that separates "modern building" from "big white box".
	strip("StallPlinthLight", vs(32.6, 0.5, 0.6), at(0, 2.1, 11.2))
	strip("StallPlinthLight", vs(32.6, 0.5, 0.6), at(0, 2.1, -11.2))
	for _, sx in ipairs({ -1, 1 }) do
		strip("StallPlinthLight", vs(0.6, 0.5, 22.4), at(sx * 16.2, 2.1, 0))
	end
	-- a step, because the plinth lip is over five studs off the ground at this scale
	newPart({ Name = "StallStep", Size = vs(20, 1.2, 3.6), CFrame = at(0, 0.6, 12.4), Color = FRAME_LITE, Material = Enum.Material.Metal, Parent = model })

	-- ===== frame columns =====
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			newPart({ Name = "StallPost", Size = vs(1.4, 20, 1.4), CFrame = at(sx * 14.6, 12.3, sz * 9.6), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
			strip("StallPostLight", vs(1.7, 0.6, 1.7), at(sx * 14.6, 6, sz * 9.6))
		end
	end

	-- ===== glass back wall, and the stock lit behind it =====
	newPart({ Name = "StallBack", Size = vs(31, 18, 0.9), CFrame = at(0, 12.5, -9.9), Color = FRAME, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	for i = -1, 1 do
		newPart({ Name = "StallGlass", Size = vs(9, 15, 0.4), CFrame = at(i * 9.7, 12.6, -9.3), Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false, CastShadow = false, Parent = model })
	end
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "StallMullion", Size = vs(0.8, 16, 1), CFrame = at(sx * 4.85, 12.6, -9.2), Color = PANEL, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	end
	newPart({ Name = "StallShelf", Size = vs(28, 0.8, 3.2), CFrame = at(0, 10.4, -7.8), Color = PANEL, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	strip("StallShelfLight", vs(27, 0.35, 0.5), at(0, 9.9, -6.4), 0.7, 16)
	for i, c in ipairs(wares) do
		-- uniform on all three axes: a Shape=Ball with unequal sides is silently drawn as a sphere
		-- of its SMALLEST one, which is how the old wares came out flatter than they were built
		newPart({ Name = "StallWare", Shape = Enum.PartType.Ball, Size = vs(3.6, 3.6, 3.6), CFrame = at(-11 + (i - 1) * 5.5, 12.6, -7.8), Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		newPart({ Name = "StallWarePad", Shape = Enum.PartType.Cylinder, Size = vs(0.4, 4.2, 4.2), CFrame = at(-11 + (i - 1) * 5.5, 10.9, -7.8) * CFrame.Angles(0, 0, math.rad(90)), Color = c, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ===== the counter: white body, dark top, one light line along the front =====
	local counter = newPart({ Name = "StallCounter", Size = vs(30, 6.2, 4), CFrame = at(0, 5.8, 9.4), Color = PANEL, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "StallCounterTop", Size = vs(31.4, 1, 5.4), CFrame = at(0, 9.4, 9.4), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
	strip("StallCounterLight", vs(30.6, 0.8, 0.5), at(0, 7.9, 11.5), 0.9, 20)

	-- ===== the canopy: one flat slab on a dark fascia, lit from underneath =====
	newPart({ Name = "StallCanopy", Size = vs(35, 1.6, 25), CFrame = at(0, 21.4, 1.5), Color = PANEL, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	newPart({ Name = "StallFascia", Size = vs(35.6, 2.8, 1.1), CFrame = at(0, 20.6, 13.6), Color = FRAME, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	strip("StallFasciaLight", vs(33, 0.7, 0.5), at(0, 20.6, 14.3), 1.1, 26)
	for i = -1, 1 do
		strip("StallCanopyLight", vs(24, 0.3, 0.7), at(0, 20.5, i * 6 + 1.5), 0.5, 14)
	end

	-- ===== the pylons, which are what you actually see from the far end of the street =====
	--
	-- The billboard turns to face the camera and is readable from 640 studs, but a sign with no
	-- building under it reads as UI floating over the map. These two lit blades give the shop a
	-- silhouette above every roof in the village, which is what makes it a place rather than a
	-- label.
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ShopPylon", Size = vs(1.6, 32, 2.4), CFrame = at(sx * 16.8, 18, 9), Color = FRAME, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		strip("ShopPylonLight", vs(0.8, 26, 1.4), at(sx * 17.6, 20, 9), 1.4, 30)
		local cap = addKnob(model, pt(sx * 16.8, 34.6, 9), 3 * S, accent, Enum.Material.Neon)
		addLight(cap, accent, 30, 1.6)
	end

	-- ===== the forecourt: lit pads instead of a striped runner, and two bollards =====
	for i = 0, 2 do
		newPart({ Name = "StallPad", Size = vs(26 - i * 3, 0.3, 6.4), CFrame = at(0, 0.2, 15.5 + i * 7), Color = i % 2 == 0 and PANEL or accent, Material = i % 2 == 0 and Enum.Material.SmoothPlastic or Enum.Material.Neon, Transparency = i % 2 == 0 and 0 or 0.35, CanCollide = false, CastShadow = false, Parent = model })
	end
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ShopBollard", Size = vs(2.4, 8, 2.4), CFrame = at(sx * 20, 4, 13), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
		strip("ShopBollardLight", vs(2.8, 0.9, 2.8), at(sx * 20, 8.4, 13), 1.2, 22)
	end

	-- CLEAR OF THE CANOPY. The canopy's top face is at 22.2 and the billboard's own StudsOffset is a
	-- fixed 3 studs that does not scale, so the board is placed on the geometry rather than on that
	-- offset: at 28 the whole board sits above the slab at any SHOP_SCALE.
	makeSign(model, title, at(0, 28, 6), UDim2.new(24 * S, 0, 7 * S, 0), { maxDistance = 640 })
	return counter
end

-- The village well: a cobbled rim, a roof on two posts, a bucket on a rope.
-- ===== THE OTHER SHOP SHELL: A TIMBER MARKET KIOSK =====
--
-- `addStall` above is a white panel-and-glass kiosk and it is right for a potion dispenser. The
-- Fusion Lab and the Upgrade Emporium get this one instead -- the timber kiosk model in
-- `ServerStorage.Models.PetStallKiosk`: a striped awning on four posts, a plank counter you walk
-- up to and a lantern hung off the corner. It is a shop with a shopkeeper's side and a customer's
-- side, which is what those two counters actually are.
--
-- WHY THE GAME CARRIES TWO SHELLS. It is information: from the far end of the street a timber
-- awning is a Fusion Lab or an Emporium and a white slab is a Mystery counter, before either sign
-- is close enough to read.
--
-- SCALE. The model ships 12.4 x 11 x 13.4 studs and a late-chain character stands about 30, so at
-- 1x it is a doll's house. 5.5x puts the awning ridge at ~62 and the counter rail at ~19, which is
-- the same read `addStall` has at SHOP_SCALE -- see the note there for why the shop has to be the
-- tallest thing on the street.
local WOOD_KIOSK_SCALE = 5.5

-- Returns the counter, same as `addStall`: it is what a caller hangs a ProximityPrompt on.
local function addWoodKiosk(model, base, accent, title, wares)
	local template = ServerStorage:FindFirstChild("Models")
		and ServerStorage.Models:FindFirstChild("PetStallKiosk")
	-- An inserted model can simply be missing, and a shop with no shell is a shop nobody finds --
	-- so the fallback is the shell that is built out of parts and cannot go anywhere.
	if not template then
		return addStall(model, base, accent, title, wares)
	end

	local F = WOOD_KIOSK_SCALE
	local DECK = Color3.fromRGB(112, 78, 46)
	local COUNTER = Color3.fromRGB(139, 94, 54)

	-- The deck goes down first and the kiosk stands on it. The model's floor is its own y = 0 and
	-- the ground under a shop is not flat in every biome, so without this the front posts hang.
	newPart({ Name = "StallDeck", Size = Vector3.new(14 * F, 1.6, 15 * F), CFrame = base * CFrame.new(0, 0.8, 0), Color = DECK, Material = Enum.Material.WoodPlanks, Parent = model })

	local kiosk = template:Clone()
	kiosk.Name = "ShopKiosk"
	kiosk:ScaleTo(F)
	kiosk.Parent = model
	-- the template's pivot is its own base centre, and the model faces +Z -- which is the customer
	-- side of `base` for every shop in the game (see the forecourt pads at +Z below)
	kiosk:PivotTo(base * CFrame.new(0, 1.6, 0))
	for _, d in ipairs(kiosk:GetDescendants()) do
		if d:IsA("BasePart") then
			-- inserted geometry arrives unanchored and shadow-casting: unanchored is a shop that
			-- falls through the world on the first physics step, and this is a spot where players
			-- stand still and look at things
			d.Anchored = true
			d.CastShadow = false
		end
	end

	-- The counter cap, laid along the model's own counter rail (3.1 in template units). Prompts
	-- hang on this: a prompt needs one part, and it should be the one the player is standing at.
	local counter = newPart({ Name = "StallCounter", Size = Vector3.new(9.4 * F, 0.5 * F, 1.3 * F), CFrame = base * CFrame.new(0, 1.6 + 3.35 * F, 6.1 * F), Color = COUNTER, Material = Enum.Material.Wood, Parent = model })

	-- The timber has no accent colour of its own, and the zone's is what tells one shop from the
	-- next on a dark street -- so it arrives as light rather than as paint, exactly as it does on
	-- the panel kiosk.
	local function strip(name, size, cf, bright, range)
		local p = newPart({ Name = name, Size = size, CFrame = cf, Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		if bright then addLight(p, accent, range or 24, bright) end
		return p
	end
	strip("StallCounterLight", Vector3.new(9.4 * F, 0.16 * F, 0.22 * F), base * CFrame.new(0, 1.6 + 3.1 * F, 6.78 * F), 1, 26)
	strip("StallPlinthLight", Vector3.new(14.2 * F, 0.4, 0.6), base * CFrame.new(0, 1.7, 7.5 * F))

	-- the forecourt: two lit treads leading up to the counter, so the ground in front of the shop
	-- says "walk here" the way the panel kiosk's pads do. Cut to two and to half the depth the
	-- panel kiosk uses: this shell is 68 studs wide against that one's 83, and three full-width
	-- pads in front of it read as a runway rather than as a doorstep.
	for i = 0, 1 do
		newPart({ Name = "StallPad", Size = Vector3.new((11 - i * 1.6) * F, 0.3, 2.2 * F), CFrame = base * CFrame.new(0, 0.2, (9.4 + i * 2.6) * F), Color = i % 2 == 0 and Color3.fromRGB(228, 214, 190) or accent, Material = i % 2 == 0 and Enum.Material.SmoothPlastic or Enum.Material.Neon, Transparency = i % 2 == 0 and 0 or 0.55, CanCollide = false, CastShadow = false, Parent = model })
	end

	-- three wares standing on the counter, in the colours the panel kiosk shelves them in
	for i, c in ipairs(wares or {}) do
		if i <= 3 then
			newPart({ Name = "StallWare", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1 * F, 1.1 * F, 1.1 * F), CFrame = base * CFrame.new((-3.2 + (i - 1) * 3.2) * F, 1.6 + 4.2 * F, 5.6 * F), Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		end
	end

	-- clear of the awning (top ~62), the same way the panel kiosk's board clears its canopy
	makeSign(model, title, base * CFrame.new(0, 1.6 + 12.4 * F, 3 * F), UDim2.new(24 * 2.6, 0, 7 * 2.6, 0), { maxDistance = 640 })

	return counter
end

local function addWell(model, base, zone)
	local tones = stoneTones(zone)
	for i = 0, 11 do
		local a = i * math.pi / 6
		newPart({ Name = "WellStone", Size = Vector3.new(4.6, 5, 3.2), CFrame = base * CFrame.new(math.cos(a) * 8, 2.5, math.sin(a) * 8) * CFrame.Angles(0, -a, 0), Color = tones[(i % 2) + 1], Material = Enum.Material.Cobblestone, Parent = model })
	end
	newPart({ Name = "WellWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 13, 13), CFrame = base * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(86, 176, 226), Material = Enum.Material.Glass, Transparency = 0.32, CanCollide = false, Parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "WellPost", Size = Vector3.new(1.8, 17, 1.8), CFrame = base * CFrame.new(sx * 7, 13, 0), Color = VILLAGE.dark, Material = Enum.Material.Wood, Parent = model })
	end
	for _, sz in ipairs({ -1, 1 }) do
		newPart({ Name = "WellRoof", Size = Vector3.new(20, 1.4, 9), CFrame = base * CFrame.new(0, 22, sz * 3.6) * CFrame.Angles(math.rad(sz * 26), 0, 0), Color = VILLAGE.wood, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	end
	newPart({ Name = "WellRope", Size = Vector3.new(0.4, 8, 0.4), CFrame = base * CFrame.new(0, 16.5, 0), Color = Color3.fromRGB(206, 188, 150), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	newPart({ Name = "WellBucket", Size = Vector3.new(4.2, 4.2, 4.2), CFrame = base * CFrame.new(0, 10.5, 0), Color = VILLAGE.wood, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
end

-- `villMesh` and `trimFor` are deliberately NOT exported. Nothing outside this file has ever called
-- either, and a library's surface should be the things somebody asks it for.
return {
	palette = VILLAGE,
	applyVillageStyle = applyVillageStyle,

	candy = candy,
	addKnob = addKnob,
	addScallops = addScallops,
	addBunting = addBunting,
	addPlanter = addPlanter,

	addLamp = addLamp,
	addStall = addStall,

	addWoodKiosk = addWoodKiosk,
	addWell = addWell,
	SHOP_SCALE = SHOP_SCALE,

	WOOD_KIOSK_SCALE = WOOD_KIOSK_SCALE,
}
