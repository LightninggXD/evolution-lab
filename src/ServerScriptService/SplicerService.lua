--[[
	SplicerService -- the DNA Splicer: the machine mutations are bought at, and the sink DNA
	needed (Phase 12.2).

	=========================================================================================
	WHAT THIS REPLACED, WHICH IS THE REASON IT EXISTS
	=========================================================================================
	Mutations were not a feature before this: they were a loop in DNAService that fired every ten
	seconds for as long as a player was online, appended a name to a list nothing ever pruned, and
	multiplied income by a ladder topping at x30. No screen in the game named it, no action
	triggered it, and nobody ever chose to have one. The whole system was a faucet.

	It is a machine you walk up to and pay for now. The roll itself is unchanged
	(`GameConfig.RollMutation`) -- what is new is that it costs something, that exactly one
	mutation is worn at a time, and that the rare end of the ladder is worth telling the server
	about.

	=========================================================================================
	THE PRICE IS IN KILLS, AND THAT IS NOT A FIGURE OF SPEECH
	=========================================================================================
	`GameConfig.GetSplicerRollCost` is the one implementation and this file does not do its own
	arithmetic anywhere -- the client panel quotes the same function, so the number on the screen
	and the number charged cannot drift. See the block over it in GameConfig for why it is priced
	off per-kill income rather than through `ScaleReward`.

	=========================================================================================
	THREE THINGS THE SERVER DOES NOT TRUST THE CLIENT FOR
	=========================================================================================
	* THE PRICE. Recomputed here from the save, never read off the request.
	* THE PITY. `SplicerRolls` is incremented on the server and the charged roll is decided from
	  the incremented value. The client PREDICTS which roll is charged so it can draw the meter;
	  a client that predicts wrong gets a correct roll and a wrong meter, which is the right way
	  round for a disagreement.
	* THE RATE. One roll per `ROLL_INTERVAL` per player. The reveal alone is longer than that, so
	  it never fires for an honest player and always fires for a loop.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local SplicerService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Bump to force the machine to be rebuilt on the next server start. Stamped on the model, the
-- same trick RebirthShrine and ZoneBuilder use -- without it no change to the geometry below
-- would ever appear on a place that has already been played.
-- 1 -> 2: the look pass (dark outline geometry, indigo body, two-hue helix). A version that does
-- not move means the machine already standing in a played world is never replaced, so the change
-- is invisible -- the same silent no-op ZoneBuilder's BUILD_VERSION exists to prevent.
-- 4 -> 5 (12.13): NOT a geometry change. The machine was standing INSIDE the event board -- its
-- bounding box spanned x 132..160 against a sign panel at x 148.5..151.5 on the same z -- because
-- SplicerService.Init ran BEFORE EventService.Init, so `findClearSpot` searched a Forest that did
-- not have the sign in it yet. The ordering is fixed in ServerMain; this bump is what makes an
-- already-built world re-run the search instead of keeping the machine where it is. A placement
-- search only ever answers about the world that exists at the moment it runs, so moving the call
-- and moving the version are ONE change -- either alone does nothing.
-- 5 -> 6 (2026-08-17): the machine is TWICE THE SIZE and its prompt reaches four times as far.
-- Both halves are the same bug and it is a bug about the PLAYER, not about this file. A max-stage
-- body is BodyScale 5, i.e. a bounding box of 45 x 42 x 35 studs -- bigger than the whole machine,
-- which measured 27 x 25 x 27. Standing next to it the player could not see it, and could not reach
-- it either: `MaxActivationDistance` was 16 while the character's own half-width is ~22, so its
-- collision stopped it further out than the prompt could ever fire. The machine was not broken; it
-- had simply become unreachable as the bodies around it grew. Same rule as the boss reach note in
-- `CombatClient`: reach > (structure half-width + player half-width).
local MACHINE_VERSION = 6

-- ===== HOW BIG =====
-- Applied with `Model:ScaleTo` at the end of `buildMachine` rather than by rewriting the sixty-odd
-- authored dimensions below, so the geometry stays readable and the outline lips keep their exact
-- proportion to the masses they rim. Everything downstream that cares about the size reads it back
-- off the model with `:GetScale()` instead of assuming 1.
--
-- 2 puts it at 55 x 50 x 55 -- a head taller than a max-stage player rather than knee-high to one --
-- and keeps the footprint clear of both the street (STREET_HALF) and the rebirth plaza at x 225.
local MACHINE_SCALE = 2

-- Seconds between two rolls from one player. The client's own reveal runs ~2.4 s.
local ROLL_INTERVAL = 1.2

-- ===== WHERE IT STANDS =====
-- Forest, whose platform is centred on x = 0 with its top face at y = 0. The street runs down Z
-- at x = +-38 (lamps, benches, planters), the three leaderboard boards stand at x = -130 over
-- z = 140..300, and the rebirth plaza occupies x = 225..375. This is the gap between the street
-- and that plaza, in plain sight of the spawn walk-down and standing on nothing.
--
-- The exact spot is SEARCHED rather than asserted (see `findClearSpot`): Forest's scatter props
-- are placed by a builder that does not know this file exists, and a machine standing inside a
-- conifer is the kind of thing that only ever gets noticed in a screenshot.
-- z MOVED 215 -> 290 (12.13). 215 is the event sign's own z, so the preferred spot was on the one
-- line the sign is read along -- see SIGN_CLEAR below, which now rejects it outright. Left at 215
-- the search would still find somewhere legal, but every legal answer inside two rings is either
-- behind the sign or 52 studs out, and neither is a spot anybody chose. 290 is the same east verge,
-- 75 studs nearer the spawn at (0, 1, 366): more of the walk-down, not less, which is the reason
-- this machine is on this side of the street in the first place.
local PREFERRED = Vector3.new(120, 0, 290)
-- The footprint the placement search has to find empty, and it has to grow WITH the machine or the
-- search happily clears a 30-stud box and then a 60-stud machine is built through a conifer.
local FOOTPRINT = Vector3.new(30, 26, 30) * MACHINE_SCALE

-- How close a player has to be for the helix to turn. Squared, because this is compared in a
-- loop and a square root per player per tick buys nothing. Scaled too: this is a distance to a
-- landmark, and a bigger landmark is legible from further away.
local ANIMATE_RANGE_SQ = (90 * MACHINE_SCALE) * (90 * MACHINE_SCALE)

-- ===== PALETTE =====
-- The first build of this machine was pale steel and light blue, and against Forest's bright green
-- lawn it read as a flat pastel box -- the exact failure the world look pass was run to fix. Two
-- things were wrong and they are the project's own rules: the body had no dark value anywhere in
-- it, and nothing carried an outline.
--
-- Scenery CANNOT use a Highlight for that outline. Roblox draws about 31 at once and the running
-- game already spends them on the player's own pets and characters, so a machine that took one
-- would silently steal it from the one place it matters (the note over `buildEggPlaza` in
-- ZoneBuilder says exactly this). Scenery outlines are built from GEOMETRY -- see `edged` in
-- buildMachine for the shape that actually works, and for the two that did not.
--
-- AND THE OUTLINE ONLY WORKS IF THE BODY IS BRIGHT. The dark build got this backwards: a deep
-- indigo body (56, 52, 104) against a near-black edge are the same VALUE, so the two merged and
-- the machine read as one black blob -- worse than the pale version it replaced. An outline is a
-- boundary between two values; it needs something light on the other side of it. The body is a
-- vivid violet from the same candy family the HUD tiles use.
local OUTLINE    = Color3.fromRGB(18, 16, 34)    -- near-black, never pure black
local BODY       = Color3.fromRGB(146, 116, 240) -- vivid violet: the mass the outline draws around
local BODY_LITE  = Color3.fromRGB(186, 160, 250)
local STEEL_LITE = Color3.fromRGB(198, 202, 224)
local GLASS_TINT = Color3.fromRGB(150, 225, 255)
local ACCENT     = Color3.fromRGB(90, 240, 255)  -- cyan strand + trim
local ACCENT2    = Color3.fromRGB(255, 96, 205)  -- magenta strand, the other half of the helix

local lastRoll = {}
-- every part of the helix, with the offset it sits at when the machine is unturned
local helix = {}
local helixPivot = nil
local machineModel = nil

-- ===== PART VOCABULARY =====
-- A local copy rather than a require of ZoneBuilder's, for the reason RebirthShrine gives for
-- having its own: that module is thousands of lines and rebuilds tens of thousands of parts
-- behind a version stamp of its own. This one builds under a hundred and owns them.
local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- ===== FINDING GROUND NOTHING IS STANDING ON =====
-- Steps out from `PREFERRED` along a widening ring and takes the first spot whose footprint is
-- empty of anything solid. Returns the preferred spot if every candidate is occupied, because a
-- machine in the wrong place is recoverable and no machine at all is not.
--
-- EMPTY IS NOT THE SAME AS AVAILABLE (found 12.10, on a rebuilt world). Forest's props are placed
-- with math.random, so a rebuild moves them and this search answers differently each time -- and on
-- one of those worlds every candidate inside four rings was occupied and the machine walked 104
-- studs to x = 16, i.e. into the middle of the street. It was a legal answer: the path slabs are
-- 0.16 high and the fence run has gaps, so that footprint really was clear of anything solid. The
-- street is not clear GROUND, it is the line every player walks, so it is ruled out by name rather
-- than left to the occupancy test. Same constant and same reasoning as HubPlaza's CORRIDOR_HALF.
local STREET_HALF = 30

-- A SIGN IS NOT ITS PANEL, IT IS ITS PANEL PLUS THE LINE YOU READ IT ALONG (12.13). Fixing the
-- init order stopped the machine from being built INSIDE the event board, and the very next build
-- put it 30 studs west of the board instead -- on the board's own -X reading face, between the sign
-- and the street it was sited to be read from. The occupancy test cannot object: standing in front
-- of something is not touching it, and every part of both structures is exactly where it was asked
-- to go.
--
-- So the sightline is reserved BY NAME, the same way the street is above and for the same reason:
-- some space is unavailable for a reason no geometric test can discover. x stops at the panel
-- because behind the sign is not in front of it, and the z band is the panel's own 34-stud width
-- pulled in two studs at each end -- clipping the far corner of a sign you are reading head-on
-- costs nothing, and a rule that rejects that too pushes the machine 52 studs for no gain.
local SIGN_CLEAR = { xMin = 40, xMax = 150, zMin = 200, zMax = 230 }

local function findClearSpot()
	local candidates = { Vector3.new(0, 0, 0) }
	for ring = 1, 6 do
		-- the step is one footprint wide, so consecutive rings do not overlap each other
		local step = ring * 26 * MACHINE_SCALE
		table.insert(candidates, Vector3.new(step, 0, 0))
		table.insert(candidates, Vector3.new(-step, 0, 0))
		table.insert(candidates, Vector3.new(0, 0, step))
		table.insert(candidates, Vector3.new(0, 0, -step))
		table.insert(candidates, Vector3.new(step, 0, step))
		table.insert(candidates, Vector3.new(-step, 0, step))
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { machineModel }

	for _, offset in ipairs(candidates) do
		local centre = PREFERRED + offset
		local blocked = math.abs(centre.X) - FOOTPRINT.X * 0.5 < STREET_HALF
		-- the event sign's sightline, rejected before the occupancy test because no occupancy test
		-- can see it -- see SIGN_CLEAR
		if not blocked then
			local x0, x1 = centre.X - FOOTPRINT.X * 0.5, centre.X + FOOTPRINT.X * 0.5
			local z0, z1 = centre.Z - FOOTPRINT.Z * 0.5, centre.Z + FOOTPRINT.Z * 0.5
			blocked = x0 < SIGN_CLEAR.xMax and x1 > SIGN_CLEAR.xMin
				and z0 < SIGN_CLEAR.zMax and z1 > SIGN_CLEAR.zMin
		end
		if not blocked then
			local box = CFrame.new(centre + Vector3.new(0, FOOTPRINT.Y / 2, 0))
			local hits = workspace:GetPartBoundsInBox(box, FOOTPRINT, params)
			for _, part in ipairs(hits) do
				-- The floor is not an obstruction; everything standing ON it is.
				if part.CanCollide and part.Position.Y > 0.5 then
					blocked = true
					break
				end
			end
		end
		if not blocked then
			return centre, offset.Magnitude
		end
	end
	return PREFERRED, -1
end

-- ===== THE MACHINE =====
local function buildMachine(centre)
	local model = Instance.new("Model")
	model.Name = "DNASplicer"

	-- The outline helper: a near-black slab `grow` studs bigger on the two axes that face the
	-- camera, sitting exactly where the mass does. One call per mass, so nothing can be added
	-- later without one and quietly read as flat.
	-- ===== HOW A DARK EDGE IS ACTUALLY DRAWN ON A ROBLOX PART =====
	-- NOT by wrapping the mass in a bigger dark shell. That was the second attempt and it is
	-- geometrically hopeless: a part 0.4 studs bigger on all three axes ENCLOSES the one it is
	-- meant to outline, so every face you can see belongs to the shell and the body colour is
	-- never drawn at all. Both dark builds of this machine were that mistake -- the palette was
	-- fine and invisible.
	--
	-- The village crates and lamps do it the way that works: a bright mass with dark TRIM at its
	-- extremities -- a lip wider than the body under it, a cap over it. The dark reads as an edge
	-- because it is at the boundary, and the body keeps every face in between.
	local function edged(props, lip)
		local body = newPart(props)
		local g = lip or 0.9
		-- the lip: wider in X and Z, thin in Y, sunk just under the mass so it peeks out as a rim
		newPart({
			Name = (props.Name or "Part") .. "Lip",
			Size = Vector3.new(props.Size.X + g, 0.7, props.Size.Z + g),
			Position = props.Position - Vector3.new(0, props.Size.Y / 2, 0),
			Color = OUTLINE, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = props.Parent,
		})
		return body
	end
	-- a matching cap, for masses that want an edge on top as well as underneath
	local function capped(props, lip)
		local body = edged(props, lip)
		local g = lip or 0.9
		newPart({
			Name = (props.Name or "Part") .. "Cap",
			Size = Vector3.new(props.Size.X + g, 0.7, props.Size.Z + g),
			Position = props.Position + Vector3.new(0, props.Size.Y / 2, 0),
			Color = OUTLINE, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = props.Parent,
		})
		return body
	end

	-- ---- plinth: a wide violet base with a dark rim under it, then the lit deck stepped in on top
	edged({ Name = "PlinthRim", Size = Vector3.new(26, 1.4, 26),
		Position = centre + Vector3.new(0, 0.7, 0), Color = BODY,
		Material = Enum.Material.Metal, Parent = model }, 1.4)
	local deck = edged({ Name = "Plinth", Size = Vector3.new(22, 1.6, 22),
		Position = centre + Vector3.new(0, 1.9, 0), Color = BODY_LITE,
		Material = Enum.Material.Metal, Parent = model }, 1.0)
	model.PrimaryPart = deck

	-- a ring of lit floor tiles, so the machine has a footprint at night
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		newPart({ Name = "DeckLamp", Size = Vector3.new(2.6, 0.5, 2.6),
			Position = centre + Vector3.new(math.cos(a) * 8.6, 2.9, math.sin(a) * 8.6),
			Color = ACCENT, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- ---- the two pillars the tube stands between
	for _, sx in ipairs({ -7.5, 7.5 }) do
		capped({ Name = "Pillar", Size = Vector3.new(5, 19, 7),
			Position = centre + Vector3.new(sx, 12.2, 0), Color = BODY,
			Material = Enum.Material.Metal, Parent = model }, 1.0)
		newPart({ Name = "PillarTrim", Size = Vector3.new(5.4, 1.8, 7.4),
			Position = centre + Vector3.new(sx, 21.6, 0), Color = ACCENT,
			Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		newPart({ Name = "PillarBand", Size = Vector3.new(5.4, 1.2, 7.4),
			Position = centre + Vector3.new(sx, 14.0, 0), Color = ACCENT2,
			Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		edged({ Name = "PillarFoot", Size = Vector3.new(6.4, 1.8, 8.4),
			Position = centre + Vector3.new(sx, 3.6, 0), Color = BODY_LITE,
			Material = Enum.Material.Metal, Parent = model }, 1.0)
	end

	-- ---- canopy
	capped({ Name = "Canopy", Size = Vector3.new(23, 2, 10),
		Position = centre + Vector3.new(0, 23.4, 0), Color = BODY,
		Material = Enum.Material.Metal, Parent = model }, 1.2)
	newPart({ Name = "CanopyLip", Size = Vector3.new(24.4, 1.1, 11.4),
		Position = centre + Vector3.new(0, 22.2, 0), Color = ACCENT,
		Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	-- ---- the glass tube. Shape = Cylinder is drawn along its X axis, so it is turned upright
	-- rather than sized as if the axis were Y -- sizing it the other way makes a flat disc and is
	-- the same class of mistake as a non-uniform Ball.
	local tube = newPart({ Name = "Tube", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(17, 9.4, 9.4), Color = GLASS_TINT, Material = Enum.Material.Glass,
		Transparency = 0.62, CanCollide = false, CastShadow = false,
		CFrame = CFrame.new(centre + Vector3.new(0, 12.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })
	newPart({ Name = "TubeCapLower", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 10.6, 10.6), Color = STEEL_LITE, Material = Enum.Material.Metal,
		CFrame = CFrame.new(centre + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })
	newPart({ Name = "TubeCapUpper", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 10.6, 10.6), Color = STEEL_LITE, Material = Enum.Material.Metal,
		CFrame = CFrame.new(centre + Vector3.new(0, 20.8, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })

	-- ---- the helix. Two strands and the rungs between them, which is the thing that makes the
	-- machine legible as a DNA splicer from across the plaza rather than as a lamp.
	-- Beads at 2.4 rather than 1.7: at the smaller size they vanished inside the tinted glass from
	-- more than a few studs away, which took the one shape that says "DNA" out of the silhouette.
	local BEADS, TURNS, RADIUS, SPAN = 13, 2.1, 3.0, 14.4
	helix = {}
	helixPivot = CFrame.new(centre + Vector3.new(0, 12.6, 0))
	for i = 0, BEADS - 1 do
		local t = i / (BEADS - 1)
		local a = t * math.pi * 2 * TURNS
		local y = (t - 0.5) * SPAN
		for strand = 0, 1 do
			local ang = a + strand * math.pi
			local bead = newPart({ Name = "HelixBead", Shape = Enum.PartType.Ball,
				Size = Vector3.new(2.4, 2.4, 2.4),
				-- two strongly separated hues, so the double helix reads as two strands rather
				-- than as a column of beads
				Color = strand == 0 and ACCENT or ACCENT2,
				Material = Enum.Material.Neon, CanCollide = false, CastShadow = false,
				Parent = model })
			-- Stored as an OFFSET from the pivot, not as a world CFrame: the driver below rebuilds
			-- every frame from `pivot * turn * offset`, which is an exact rotation. A tween would
			-- lerp the position and walk each bead across the chord instead of around the axis.
			local offset = CFrame.new(math.cos(ang) * RADIUS, y, math.sin(ang) * RADIUS)
			bead.CFrame = helixPivot * offset
			table.insert(helix, { part = bead, offset = offset })
		end
		-- a rung every other bead pair, or the tube fills up with bars
		if i % 2 == 0 then
			local rung = newPart({ Name = "HelixRung", Size = Vector3.new(RADIUS * 2, 0.42, 0.42),
				Color = STEEL_LITE, Material = Enum.Material.Neon, CanCollide = false,
				CastShadow = false, Parent = model })
			local offset = CFrame.new(0, y, 0) * CFrame.Angles(0, -a, 0)
			rung.CFrame = helixPivot * offset
			table.insert(helix, { part = rung, offset = offset })
		end
	end

	-- ---- the console you actually walk up to
	local console = edged({ Name = "Console", Size = Vector3.new(11, 4.6, 5),
		Position = centre + Vector3.new(0, 5.2, 8.6), Color = BODY,
		Material = Enum.Material.Metal, Parent = model }, 1.0)
	newPart({ Name = "ConsoleLip", Size = Vector3.new(11.6, 1.0, 5.6),
		Position = centre + Vector3.new(0, 7.6, 8.6), Color = ACCENT,
		Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	-- The screen takes NO lip: it is already near-black, so it is its own dark edge against the
	-- violet console it is mounted on, and anything laid in front of its face hides the SurfaceGui.
	local screen = newPart({ Name = "Screen", Size = Vector3.new(9.4, 3.2, 0.4),
		Position = centre + Vector3.new(0, 5.6, 11.2), Color = Color3.fromRGB(16, 20, 30),
		Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(360, 120)
	sg.LightInfluence = 0
	sg.Parent = screen
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0.62, 0)
	title.Position = UDim2.new(0, 6, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = "DNA SPLICER"
	title.TextColor3 = ACCENT
	title.TextScaled = true
	title.Parent = sg
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -12, 0.34, 0)
	sub.Position = UDim2.new(0, 6, 0.62, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.Text = "Splice a mutation into your DNA"
	sub.TextColor3 = Color3.fromRGB(210, 226, 245)
	sub.TextScaled = true
	sub.Parent = sg

	local light = Instance.new("PointLight")
	light.Color = ACCENT
	light.Range = 34
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = tube

	-- ---- the prompt. `ShopPanel` is the same grammar every other counter in the game uses, and
	-- MainUI's handler looks the key up in a table that has no "splicer" row, so it falls through
	-- there and is picked up by SplicerUI instead.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SplicerPrompt"
	prompt.ActionText = "Splice"
	prompt.ObjectText = "DNA Splicer"
	prompt.HoldDuration = 0
	-- ===== 16 -> 70, AND 70 IS MEASURED, NOT PICKED =====
	-- `MaxActivationDistance` is NOT scaled by `Model:ScaleTo` -- prompts are not geometry -- so it
	-- has to be written here. The plinth rim is 27.4 studs across as authored, so 54.8 at scale 2 --
	-- a half-width of 27.4. A max-stage player's own half-width is ~22 and the rim's collision stops
	-- it before it can stand any closer than the sum, so nothing under 49.4 can EVER fire, which is
	-- exactly how 16 came to be unreachable. 70 clears that with margin and shows the prompt while
	-- the player is still walking in rather than snapping on at the last step. The other landmark
	-- prompts in this game sit in the same band (Pet Shop 42, PhotoPad 46) for smaller structures.
	prompt.MaxActivationDistance = 70
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopPanel", "splicer")
	prompt.Parent = console

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	-- ===== THE SCALE PASS, AND THE THREE THINGS IT HAS TO PUT BACK =====
	--
	-- `Model:ScaleTo` does the geometry -- every part's Size, every offset between them, the light
	-- range and the particle sizes -- and that is the only reason the sixty-odd authored dimensions
	-- above are still written at their true scale-1 proportions instead of being multiplied by hand.
	--
	-- 1. IT DOES NOT LEAVE THE MACHINE ON THE GROUND. It scales about the model's pivot, and setting
	--    `WorldPivot` to the ground square under the machine was NOT enough on its own -- measured
	--    afterwards, the whole model came out 1.9 studs low and its base was 2.6 studs under the
	--    lawn. So the drop is MEASURED and undone rather than reasoned about: whatever the pivot
	--    turns out to be, the bottom of the bounding box ends up exactly where it started.
	-- 2. THE HELIX OFFSETS ARE STALE. They were captured above as `pivot:Inverse() * world`, from a
	--    world the scale has just moved. Left alone, the first heartbeat of `driveHelix` slams every
	--    bead back to its unscaled offset and the strands sit in a tight knot inside a tube twice
	--    their size. They are re-read from the geometry that now exists, which is exact.
	--    `helixPivot` IS the tube's centre -- that is what the authored 12.6 was -- so it is taken
	--    from the part instead of from an arithmetic that a future edit could silently invalidate.
	-- 3. IT DOES SCALE `MaxActivationDistance`, which was a surprise: prompts are not geometry, but
	--    the engine scales this one anyway, and the 70 set above came out as 140. Written again here,
	--    after the scale, so the number in the source is the number in the world.
	if MACHINE_SCALE ~= 1 then
		local cfBefore, sizeBefore = model:GetBoundingBox()
		local groundedAt = cfBefore.Position.Y - sizeBefore.Y * 0.5

		model.WorldPivot = CFrame.new(centre.X, 0, centre.Z)
		model:ScaleTo(MACHINE_SCALE)

		local cfAfter, sizeAfter = model:GetBoundingBox()
		local drop = (cfAfter.Position.Y - sizeAfter.Y * 0.5) - groundedAt
		if math.abs(drop) > 0.001 then
			model:TranslateBy(Vector3.new(0, -drop, 0))
		end

		local tube = model:FindFirstChild("Tube")
		helixPivot = CFrame.new(tube.Position)
		for _, entry in ipairs(helix) do
			entry.offset = helixPivot:Inverse() * entry.part.CFrame
		end

		prompt.MaxActivationDistance = 70
	end

	model:SetAttribute("MachineVersion", MACHINE_VERSION)
	return model
end

-- ===== THE HELIX TURNS, ON ONE HEARTBEAT, ONLY WHEN SOMEBODY IS THERE =====
-- One connection for the whole machine rather than one per part, and it does nothing at all while
-- the plaza is empty -- the rule every animated set in this game is held to.
local function driveHelix()
	local angle = 0
	local sinceCheck = 0
	local nearby = false
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= 0.5 then
			sinceCheck = 0
			nearby = false
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and helixPivot and (root.Position - helixPivot.Position).Magnitude ^ 2 <= ANIMATE_RANGE_SQ then
					nearby = true
					break
				end
			end
		end
		if not nearby or not helixPivot then return end
		angle = (angle + dt * 0.9) % (math.pi * 2)
		local turn = CFrame.Angles(0, angle, 0)
		for _, entry in ipairs(helix) do
			entry.part.CFrame = helixPivot * turn * entry.offset
		end
	end)
end

-- ===== THE ROLL =====
-- The ONE place a mutation is written onto a save, for the reason `insertPet` is the one place a
-- pet is created: two writers is how two rules drift apart.
local function applyMutation(data, mutation)
	data.SplicerFound = data.SplicerFound or {}
	data.SplicerFound[mutation.name] = (data.SplicerFound[mutation.name] or 0) + 1

	local current = data.SplicerMutation and GameConfig.GetMutationByName(data.SplicerMutation)
	local equipped = false
	-- Index order IS rarity order in GameConfig.Mutations, so "better" is a plain index compare.
	local newIdx, curIdx = 0, 0
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == mutation.name then newIdx = i end
		if current and m.name == current.name then curIdx = i end
	end
	if newIdx > curIdx then
		data.SplicerMutation = mutation.name
		equipped = true
	end
	return equipped
end

-- ===== WEARING ONE YOU HAVE ALREADY FOUND (15.27) =====
--
-- The roll is best-kept-wins and was the ONLY writer of `data.SplicerMutation`, so a collection of
-- seven auras had exactly one reachable state: the best one you had ever rolled. The Auras panel
-- adds the other six, and it is a real choice rather than a downgrade button -- both stats rise
-- together with rarity, so the reason to wear a weaker one is the LOOK of it (the particle aura on
-- the body is the mutation's colour). The cost of that choice is never hidden: the row prints the
-- multiplier it is about to cost you, and 15.24's boost card keeps printing the one you are on.
--
-- Best-kept-wins is untouched by this. A later roll still compares against whatever is worn, so a
-- player wearing Common for the look is auto-upgraded by the next Rare -- which is the correct
-- reading of "a roll that lands better than what you have on".
local lastEquip = {}
local EQUIP_INTERVAL = 0.25
function SplicerService.HandleEquipMutation(player, mutationName)
	local PlayerDataService = require(script.Parent.PlayerDataService)
	local EvolutionVisuals = require(script.Parent.Systems.EvolutionVisuals)

	if type(mutationName) ~= "string" then return end
	local now = os.clock()
	local last = lastEquip[player.UserId]
	if last and now - last < EQUIP_INTERVAL then return end
	lastEquip[player.UserId] = now

	local data = PlayerDataService.Get(player)
	if not data then return end

	-- OWNERSHIP IS THE WHOLE GUARD, and it is a count rather than a truthiness test: `SplicerFound`
	-- holds how many of each have been rolled, and a 0 left behind by any future write is "not
	-- found" while `not 0` is false in Luau.
	local found = data.SplicerFound
	if not found or (found[mutationName] or 0) <= 0 then
		warn(("[SplicerService] %s tried to wear an unfound mutation: %s"):format(player.Name, mutationName))
		return
	end
	local mut = GameConfig.GetMutationByName(mutationName)
	if not mut then return end
	if data.SplicerMutation == mutationName then return end

	data.SplicerMutation = mutationName

	-- THE SAME THREE LINES HandleRoll RUNS WHEN A ROLL EQUIPS ITSELF, and each one is load-bearing:
	--  * the ATTRIBUTE is the replication channel, not the save. `EvolutionVisuals.WornMutation`
	--    reads `player:GetAttribute("Mutation")` FIRST and only falls back to the save when it is
	--    nil -- and the join path stamps it -- so writing the save alone leaves the old aura burning
	--    on the body for the rest of the session. Stamping it also fires the attribute hook in
	--    EvolutionVisuals.Init, which is what rebuilds the aura without a respawn.
	--  * RefreshBonuses is the walk speed: `speedPct` is applied by applyMastery, which recomputes
	--    the whole product rather than adding a delta.
	--  * PushToClient is what redraws the Auras panel and 15.24's boost card. Without it the panel
	--    still catches up on the next periodic push, seconds after a button the player just pressed.
	player:SetAttribute("Mutation", mutationName)
	EvolutionVisuals.RefreshBonuses(player, data)
	PlayerDataService.PushToClient(player)

	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("\u{1F9EC} Now wearing the %s aura! x%.2f DNA, +%d%% speed")
			:format(mut.name, mut.incomeMult, mut.speedPct),
	})
end

function SplicerService.HandleRoll(player)
	local PlayerDataService = require(script.Parent.PlayerDataService)
	local EvolutionVisuals = require(script.Parent.Systems.EvolutionVisuals)
	local AnnounceService = require(script.Parent.AnnounceService)

	local data = PlayerDataService.Get(player)
	if not data then return end

	local now = os.clock()
	local last = lastRoll[player.UserId]
	if last and now - last < ROLL_INTERVAL then return end
	lastRoll[player.UserId] = now

	local cost = GameConfig.GetSplicerRollCost(data)
	if (data.DNA or 0) < cost then
		-- Two messages, deliberately: the toast is the WORDING and goes through the same Notify
		-- stack every refusal in the game uses (so it queues, ranks and sounds like the others),
		-- while SpliceResult tells the panel to re-read itself. Neither does the other's job.
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough DNA to splice!" })
		Remotes.SpliceResult:FireClient(player, { ok = false, reason = "poor", cost = cost })
		return
	end

	data.DNA -= cost
	data.SplicerRolls = (data.SplicerRolls or 0) + 1

	-- The pity roll is decided from the INCREMENTED count, so the tenth roll is charged rather
	-- than the eleventh -- the client's meter counts the same way.
	local S = GameConfig.Splicer
	local charged = (data.SplicerRolls % S.pityEvery) == 0
	local mutation = GameConfig.RollMutation(GameConfig.GetSplicerLuck(data, charged))
	if charged then
		-- A charged roll is a floor, not a reroll: it cannot make a result worse than it landed.
		local idx = 0
		for i, m in ipairs(GameConfig.Mutations) do
			if m.name == mutation.name then idx = i end
		end
		if idx < S.pityMinIndex then
			mutation = GameConfig.Mutations[S.pityMinIndex]
		end
	end

	local equipped = applyMutation(data, mutation)
	if equipped then
		-- The one replication channel the aura and the walk speed both read.
		player:SetAttribute("Mutation", mutation.name)
		EvolutionVisuals.RefreshBonuses(player)
	end
	PlayerDataService.PushToClient(player)

	local idx = 0
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == mutation.name then idx = i end
	end

	Remotes.SpliceResult:FireClient(player, {
		ok = true,
		name = mutation.name,
		color = mutation.color,
		index = idx,
		incomeMult = mutation.incomeMult,
		speedPct = mutation.speedPct,
		equipped = equipped,
		spent = cost,
		rollIndex = data.SplicerRolls,
		charged = charged,
		nextCost = GameConfig.GetSplicerRollCost(data),
	})

	if idx >= S.announceMinIndex then
		AnnounceService.MutationRolled(player, mutation)
	end
end

function SplicerService.Init()
	local PlayerDataService = require(script.Parent.PlayerDataService)

	for _, name in ipairs({ "SpliceRoll", "SpliceResult", "EquipMutation" }) do
		if not Remotes:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = Remotes
		end
	end

	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- Rebuilt by replacement rather than patched in place: a stamped model whose version has moved
	-- is not the same machine, and reconciling it piece by piece is how half-old geometry survives.
	local existing = map:FindFirstChild("DNASplicer")
	if existing and existing:GetAttribute("MachineVersion") ~= MACHINE_VERSION then
		existing:Destroy()
		existing = nil
	end

	if existing then
		machineModel = existing
		-- WAS `Plinth.Position + 10.7`, which is the tube's centre expressed as an authored offset
		-- from a different part -- correct at scale 1 and wrong at every other scale, and wrong again
		-- the first time anything moves the plinth. The tube IS the axis the helix turns on, so it is
		-- read directly and the machine's own size never enters into it.
		local pivot = existing:FindFirstChild("Tube")
		if pivot then
			helixPivot = CFrame.new(pivot.Position)
		end
		helix = {}
		for _, d in ipairs(existing:GetDescendants()) do
			if d.Name == "HelixBead" or d.Name == "HelixRung" then
				table.insert(helix, { part = d, offset = helixPivot:Inverse() * d.CFrame })
			end
		end
	else
		local centre, moved = findClearSpot()
		machineModel = buildMachine(centre)
		machineModel.Parent = map
		if moved > 0 then
			warn(("[SplicerService] preferred spot was occupied; machine moved %.0f studs to (%d, %d)")
				:format(moved, centre.X, centre.Z))
		end
	end

	-- Never streamed out: the machine is a landmark and a player who walked to it must find it
	-- there, not arriving a second later.
	machineModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local prompt = machineModel:FindFirstChild("SplicerPrompt", true)
	if prompt then
		prompt.Triggered:Connect(function() end) -- the panel is opened client-side off the same prompt
	end

	Remotes.SpliceRoll.OnServerEvent:Connect(function(player)
		local ok, err = pcall(SplicerService.HandleRoll, player)
		if not ok then
			warn("[SplicerService] roll failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Remotes.EquipMutation.OnServerEvent:Connect(function(player, mutationName)
		local ok, err = pcall(SplicerService.HandleEquipMutation, player, mutationName)
		if not ok then
			warn("[SplicerService] equip failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	driveHelix()

	-- ===== THE ONE-TIME REFUND NOTICE =====
	-- PlayerDataService refunds the deleted Mutation Chance upgrade during load and leaves the
	-- amount in memory (never on the save -- it would be persisted and re-announced forever).
	-- This is its only reader, and it clears the entry so a rejoin on the same server says nothing.
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			player.CharacterAdded:Wait()
			task.wait(3) -- the HUD and SplicerUI are both up well inside this
			local refund = PlayerDataService.SplicerRefunds[player.UserId]
			if refund and refund > 0 then
				PlayerDataService.SplicerRefunds[player.UserId] = nil
				-- Through the ordinary Notify stack rather than a card of its own: it is news, not
				-- an event, and MainUI already owns how news is worded, ranked and sounded.
				Remotes.Notify:FireClient(player, { kind = "reward",
					message = ("🧬 Mutation Chance was replaced by the DNA Splicer -- refunded %d DNA")
						:format(refund) })
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player.UserId] = nil
		lastEquip[player.UserId] = nil
		PlayerDataService.SplicerRefunds[player.UserId] = nil
	end)
end

return SplicerService
