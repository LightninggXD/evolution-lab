-- MapProps/MapAdventureBoard -- the door into 30.6, standing in the village.
--
-- =====================================================================================
-- WHAT IT IS
-- =====================================================================================
-- A notice board with a `ProximityPrompt` carrying `ShopPanel = "adventure"`. That is the whole
-- mechanism: the attribute contract SplicerUI established, which `AdventureUI` picks up because
-- MainUI's own prompt table has no "adventure" row and falls through. Nothing here knows what a
-- route is, and nothing here talks to `AdventureService`.
--
-- =====================================================================================
-- IT IS BUILT, NOT ADOPTED, AND THAT MAKES IT THE ODD ONE OUT IN THIS FOLDER
-- =====================================================================================
-- Every other module here paints the map's OWN furniture -- the map ships eight leaderboard boards,
-- a podium, a wheel, an egg row, shop pads -- and `MapAnchors` publishes where they stand. There is
-- no adventure board in that map, and there was never going to be: the feature is three days old.
-- So this one builds its own out of primitives, and it takes its cue from the map rather than from
-- `MapAnchors.Get` -- there is no anchor to ask for.
--
-- =====================================================================================
-- IT FACES +X BY CONSTRUCTION AND IS NEVER ROTATED
-- =====================================================================================
-- Every part below is axis-aligned and the sign is painted on `Enum.NormalId.Right`. That is not a
-- shortcut -- it is the fix for a bug this project has already paid for twice
-- (`roblox-model-facing-and-scaling`): a quarter-turn yaw faces **-X**, not +X, because a CFrame's
-- LookVector starts at (0, 0, -1). A board built to face +X and then turned by `math.rad(90)` shows
-- the player its back, and a screenshot from the wrong side is the only thing that finds it.
--
-- The board's broad faces are therefore its **X** faces, so `ZoneKit.addPlankText` -- which paints
-- Front and Back, i.e. the Z faces -- cannot be used and the SurfaceGui is written out here.
--
-- =====================================================================================
-- REBUILT BY REPLACEMENT, ON A STAMP
-- =====================================================================================
-- `BOARD_VERSION` on the model, checked at Init: a stamped model whose version has moved is not the
-- same board, and reconciling one piece by piece is how half-old geometry survives a change.
-- `evolution-lab-rebuild-mechanics` is the standing note -- the stamp has to BEAT the world's, or
-- the rebuild is a silent no-op.

local ZoneKit = require(script.Parent.Parent.ZoneKit)
local MapSquare = require(script.Parent.MapSquare)

local MapAdventureBoard = {}

local BOARD_VERSION = 2
local MODEL_NAME = "AdventureBoard"

-- ===== WHERE IT STANDS =====
--
-- Zone-relative, exactly as `MapArcade`'s spot is: world X is `zoneOffset + x`, and Z is the zone's
-- own. Y = 0 is the village floor, and every part below is positioned against that rather than
-- against another part, so nothing here drifts if one piece changes size.
--
-- WRITTEN AS STUDS AND NOT AS A FRACTION OF THE FLOOR, which is the opposite of the choice
-- `MapArcade` documents. That module's -150 was a measurement taken on the 1.45 map and left
-- standing when 31.14 took it to 1.15, which moved every house 21% inward and left a hand-typed
-- coordinate in open field. This one is not derived from a house: it is the near side of the square,
-- picked against the placed map, and a rescale would move the houses past it rather than away from
-- it. If the map is ever rescaled again, THIS IS THE LINE TO RE-MEASURE.
--
-- ===== z 28 -> 10, AND THE 18 STUDS ARE THE WHOLE STORY =====
--
-- The spot was authored as (-80, 0, 28) and MEASURED CLEAR in the Edit datamodel: four parts in a
-- 26 x 30 x 32 box, all of them floor. It is not clear. The live build stands the map's leaderboard
-- podium there, and the board came up seated at **y = 12.79 -- on top of the step-3 mannequin's
-- hat**, floating over the square with a prompt nobody could reach.
--
-- The Edit world was running BUILD stamp 135 while Play rebuilds to 137
-- (`evolution-lab-edit-world-stamp-lag`), so the podium simply was not there to be found. THE ONLY
-- PLACE A VILLAGE COORDINATE CAN BE CHECKED IS A RUNNING SERVER.
--
-- z = 10 is the nearest spot on the same X that a footprint scan finds clear -- 18 studs south,
-- ground at 0.64, with the strip a player stands in to read it clear as well. It also happens to
-- point the board straight across the square at the fountain, which is what the +X facing was for.
--
-- ===== 30.32: AND IT WAS STANDING IN A ROAD, WHICH THAT SCAN COULD NOT SEE =====
-- *"avanture su na putu"*, and measured she is exactly right: a ray at (-80, 10) lands on
-- `VillageMap.Union` in a colour that matches `MapPaint.DirtColour` to 0.000, and so does every
-- neighbour sampled 16 studs out in four directions. This is the artist's own dirt road, and the
-- footprint scan that cleared this spot only ever asked whether anything was STANDING here -- open
-- road is the most open ground in the village and passes that test better than anywhere else.
--
-- The village already owns the answer. `MapSquare` rings the shops about the eggs and its
-- `clearOfRoads` is three tests, not one: the generated lanes, the artist's dirt read off the
-- surface by colour, and whether a building is already there. The board is a door like the other
-- three, so it asks for a spot on the SAME RING with the SAME TESTS instead of carrying a
-- hand-measured coordinate that goes stale the next time the map moves. `evolution-lab-zone-geometry
-- -constants` is the standing note -- one decision, one file.
--
-- The entry below is now a FALLBACK and nothing else: where the board goes if the ring is full. A
-- board on a road is still better than no board, and the log says which one happened.
local SPOTS = {
	Forest = { x = -80, z = 10 },
}

-- Where on the ring it asks to stand. 45 degrees is the north-east quarter -- between the shop's
-- own bearing (0) and the mouth the approach road arrives through (90), so it is the first corner
-- of the square a player walking in from the plaza turns to look at.
local RING_BEARING = 45
-- The footprint it reserves. The board is 12 x 19.2 on the ground, so 9.6 is its widest half-extent
-- -- but it is TURNED to face the middle now, and a turned box reaches its half-DIAGONAL, which is
-- 11.3. Rounded up. `evolution-lab-relocating-a-prop`'s first rule is to measure the thing that
-- actually has to fit, and after a rotation that is the corner, not the side.
local RING_HALF_WIDTH = 11.5

local PROMPT_DISTANCE = 46 -- the band the other walk-up landmarks sit in (PhotoPad 46, Pet Shop 42)

-- ===== THE FLOOR IS NOT AT y = 0 =====
--
-- Measured on the placed map 2026-08-22: the village's paving is a rotated Union whose top face is
-- at **y = 0.81**, over `MainPart` at -0.00 and `WorldShell.Floor` at 0.00. Every part below is
-- authored with the base's underside at y = 0, and the whole model is then lifted by whatever the
-- ground actually turns out to be -- so a 0.81-stud plinth does not sit three quarters buried, and
-- a future map at a different scale or seat needs no edit here.
--
-- FROM WELL ABOVE, AND DOWNWARD. `roblox-raycast-from-inside-a-part` is the standing note: a ray
-- that starts inside a part does not hit it, and a probe that started at the board's own height
-- would have called the paving open air.
local GROUND_PROBE_Y = 200

-- ===== AND THE SEAT IS A TRIPWIRE, NOT JUST A LIFT =====
--
-- The village floor is under a stud of paving. Anything materially above that means the ray landed
-- on a PROP -- which is exactly how this board first shipped standing on a mannequin's hat at
-- y = 12.79, and the log line it printed read as an ordinary success. A silent seat is what let
-- that survive a boot; naming what was hit is what makes the next one a one-line fix.
local SEAT_WARN = 4

local function groundAt(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Never seat the board on the board. Init is idempotent, and the second run of a version bump
	-- happens with the previous model still standing for the moment the ray is cast.
	local map = workspace:FindFirstChild("Map")
	params.FilterDescendantsInstances = map and { map } or {}
	local hit = workspace:Raycast(Vector3.new(x, GROUND_PROBE_Y, z), Vector3.new(0, -GROUND_PROBE_Y * 2, 0), params)
	if not hit then
		warn(("[MapAdventureBoard] nothing under (%d, %d) at all -- board seated at y = 0"):format(x, z))
		return 0
	end
	if hit.Position.Y > SEAT_WARN then
		warn(("[MapAdventureBoard] (%d, %d) is NOT open ground: the ray landed on %s at y = %.2f. "
			.. "The board is standing on a prop -- re-measure the spot on a RUNNING server, not in Edit.")
			:format(x, z, hit.Instance:GetFullName(), hit.Position.Y))
	end
	return hit.Position.Y
end

-- Ink, cream and a warm timber. The board reads as a thing standing in a village rather than as a
-- kiosk, and the ink rim is the outline tier `evolution-lab-chunky-look-rules` puts first.
local INK = ZoneKit.SIGN_INK
local CREAM = Color3.fromRGB(255, 247, 230)
local TIMBER = Color3.fromRGB(112, 76, 48)
local TIMBER_DARK = Color3.fromRGB(76, 50, 32)
local STONE = Color3.fromRGB(150, 148, 142)
local ACCENT = Color3.fromRGB(120, 210, 255)

-- ===== THE FACE =====
--
-- `PixelsPerStud` sizing rather than a fixed canvas, the reason `addPlankText` gives: a SurfaceGui's
-- canvas is pixels-per-stud times the part, so every fixed offset drifts the moment the board
-- changes size. All five rows below are in SCALE for the same reason.
local function paintFace(face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardText"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 34
	-- Half the village is in shade under the trees, and a light-influenced board goes unreadable
	-- exactly where the player is standing when they read it.
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Parent = face

	local function row(name, text, y, height, size, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(0.88, 0, height, 0)
		l.Position = UDim2.new(0.5, 0, y, 0)
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Font = ZoneKit.SIGN_FONT
		l.Text = text
		l.TextColor3 = color
		l.TextScaled = true
		l.TextWrapped = true
		l.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = size
		stroke.Color = INK
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = l
		return l
	end

	-- `\u{1F5FA}` is the world-map glyph the routes' own fallback uses, and it is above U+1F300 --
	-- which is the whole of 27.7's finding: from there up a character is emoji-presentation and is
	-- drawn by the system emoji font, while U+2600-27BF is text-default and can be laid out by
	-- FredokaOne and simply NOT DRAWN. Nothing on this board is below that line.
	row("Title", "\u{1F5FA} ADVENTURES", 0.05, 0.22, 4, CREAM)

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Size = UDim2.new(0.82, 0, 0.02, 0)
	rule.Position = UDim2.new(0.5, 0, 0.30, 0)
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.BackgroundColor3 = INK
	rule.BorderSizePixel = 0
	rule.Parent = gui

	row("Line1", "Run a route yourself", 0.36, 0.15, 3, Color3.fromRGB(255, 226, 150))
	row("Line2", "or send a pet to bring back relics", 0.53, 0.13, 3, CREAM)
	row("Line3", "20 routes \u{2022} one per world", 0.72, 0.12, 3, ACCENT)
end

-- ===== THE BOARD =====
--
-- Four solids and two lamps. `evolution-lab-chunky-look-rules`: fewer big shapes, outline first --
-- so the rim is a part rather than a UIStroke, and the cap is what stops the board reading as a
-- flat rectangle stuck to two sticks.
local function buildBoard(cx, cz)
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("BoardVersion", BOARD_VERSION)

	ZoneKit.newPart({
		Name = "BoardBase",
		Size = Vector3.new(12, 1.6, 18),
		Position = Vector3.new(cx, 0.8, cz),
		Color = STONE,
		Material = Enum.Material.Slate,
		Parent = model,
	})

	for _, dz in ipairs({ -6.6, 6.6 }) do
		ZoneKit.newPart({
			Name = "BoardPost",
			Size = Vector3.new(2.2, 15, 2.2),
			Position = Vector3.new(cx - 0.4, 9.1, cz + dz),
			Color = TIMBER_DARK,
			Material = Enum.Material.WoodPlanks,
			Parent = model,
		})
	end

	-- THE RIM IS THE OUTLINE, and it is 0.6 studs proud of the face on every side. A UIStroke on the
	-- SurfaceGui would only outline the TEXT; what makes a chunky board read as an object is a dark
	-- edge around the board itself.
	ZoneKit.newPart({
		Name = "BoardRim",
		Size = Vector3.new(1.6, 13.6, 17.2),
		Position = Vector3.new(cx, 13.6, cz),
		Color = INK,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	local face = ZoneKit.newPart({
		Name = "BoardFace",
		Size = Vector3.new(1.0, 12.4, 16.0),
		-- Half a stud proud of the rim on +X, so the rim shows as a border from in front rather than
		-- z-fighting with it. `evolution-lab-terrace-zfighting` is the same rule in the world: two
		-- coplanar faces shimmer, and the fix is always a real gap rather than a smaller number.
		Position = Vector3.new(cx + 0.5, 13.6, cz),
		Color = TIMBER,
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
		Parent = model,
	})
	paintFace(face)

	ZoneKit.newPart({
		Name = "BoardCap",
		Size = Vector3.new(3.0, 1.4, 19.2),
		Position = Vector3.new(cx - 0.1, 20.8, cz),
		Color = TIMBER_DARK,
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
		Parent = model,
	})

	for _, dz in ipairs({ -7.6, 7.6 }) do
		local lamp = ZoneKit.newPart({
			Name = "BoardLamp",
			Size = Vector3.new(1.4, 1.4, 1.4),
			Position = Vector3.new(cx + 1.2, 19.6, cz + dz),
			Color = ACCENT,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
		ZoneKit.addLight(lamp, ACCENT, 26, 1.4)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AdventurePrompt"
	prompt.ActionText = "Adventures"
	prompt.ObjectText = "Adventure Board"
	prompt.HoldDuration = 0
	-- WRITTEN HERE AND NOT SCALED. `MaxActivationDistance` is not geometry and `Model:ScaleTo` never
	-- touches it (`roblox-scaleto-scales-prompt-reach`); nothing scales this model today, and if
	-- anything ever does, this is the line that has to move by hand.
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopPanel", "adventure")
	-- ON THE BASE, not on the face. The prompt's marker is drawn at its parent's centre, and a marker
	-- floating at head height over a 12-stud board reads as belonging to the sky behind it.
	prompt.Parent = model.BoardBase

	return model
end

--- Build (or rebuild) the board for a zone. `zoneOffset` is the zone's X offset, exactly as
--- `MapArcade.Init` takes it, and `zoneModel` is what the ring search needs to read the map off.
--- Returns the model, or nil for a zone with no authored spot -- which is every zone but the mapped
--- one, and is not a fault.
function MapAdventureBoard.Init(zoneKey, zoneOffset, zoneModel)
	local spot = SPOTS[zoneKey]
	if not spot then return nil end

	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- PARENTED TO `workspace.Map` AND NOT TO THE ZONE. `ZoneBuilder` rebuilds `workspace.Zones` on a
	-- version bump and takes every child with it; the Splicer sits in `Map` for the same reason.
	local name = MODEL_NAME .. "_" .. zoneKey
	local existing = map:FindFirstChild(name)
	if existing and existing:GetAttribute("BoardVersion") ~= BOARD_VERSION then
		existing:Destroy()
		existing = nil
	end
	if existing then
		existing.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		return existing
	end

	-- THE RING FIRST, THE AUTHORED SPOT ONLY IF IT IS FULL. Asked before anything is built, because
	-- the ground has to be measured where the board actually ends up -- the square's floor is 0.64
	-- and the bare platform beyond it 0.00, and seating a board on a height taken somewhere else is
	-- the whole reason `groundAt` exists.
	local ringX, ringZ, bearing, sqX, sqZ =
		MapSquare.FindSpot(zoneKey, zoneModel, RING_BEARING, RING_HALF_WIDTH)
	local x = ringX or ((zoneOffset or 0) + spot.x)
	local z = ringZ or spot.z

	local model = buildBoard(x, z)
	model.Name = name
	-- Lifted as ONE model rather than by adding the ground to every authored Y above: the parts are
	-- positioned against each other and a per-part offset is one place for one of them to be missed.
	local ground = groundAt(x, z)
	if ground ~= 0 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, ground, 0))
	end

	-- ===== AND NOW IT IS TURNED, WHICH THE HEADER SPENT A PARAGRAPH REFUSING TO DO =====
	-- That paragraph is still right about the trap and wrong about the conclusion once the board can
	-- stand anywhere on a ring: a spot at bearing 300 with a face pointed at +X shows the square the
	-- board's back. The yaw is derived rather than guessed, and it is derived from the FACE's own
	-- axis and not from a LookVector -- `roblox-model-facing-and-scaling` is a note about
	-- LookVector starting at (0, 0, -1), which is exactly why nothing here goes near it.
	--
	-- `CFrame.Angles(0, yaw, 0)` sends local +X to `(cos yaw, 0, -sin yaw)`. The board's face has to
	-- point from the ring INWARD, i.e. along `(-cos b, 0, -sin b)`. Those are equal at `yaw = pi - b`
	-- -- and the sanity check that costs nothing: at b = 0 (due east of the middle) that is a half
	-- turn, which points the face west, back at the eggs.
	if bearing then
		local p = model:GetPivot().Position
		model:PivotTo(CFrame.new(p) * CFrame.Angles(0, math.pi - bearing, 0))
	end

	model.Parent = map
	-- Never streamed out: this is a landmark a player walks toward, and a board that arrives a
	-- second after they get there is a prompt that was not on the screen when they pressed E.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	print(("[MapAdventureBoard] %s: board at (%.0f, %.2f, %.0f) %s, prompt reach %d")
		:format(zoneKey, x, ground, z,
			bearing and ("on the square's ring at %.0f deg facing (%.0f, %.0f)")
				:format(math.deg(bearing), sqX, sqZ)
				or "on the AUTHORED FALLBACK spot facing +X -- the ring was full",
			PROMPT_DISTANCE))
	return model
end

return MapAdventureBoard
