-- EggPlaza -- the three eggs a zone sells and the stall they stand on.
--
-- One per zone, in the middle of the street where the shop is: a planked deck, three stone podiums,
-- a shell on each, an odds board behind them and a price card in front. It is the first thing a
-- player walks into in every zone and the reason they are in the zone at all, so it gets a built
-- stage rather than three props on the floor.
--
-- WHERE THE LINE IS: this file builds the plaza. `ZoneBuilder` decides WHERE it goes -- `Build()`
-- stands each zone's shop at cx - 150 and calls in once per zone with the eggs that zone sells,
-- read from `GameConfig`. Nothing about the layout of a zone is in here.
--
-- WHY IT IS ONE FILE AND NOT TWO. The eggs and the plaza are one screen: the plaza is what the
-- eggs stand on and is the only caller of `buildEgg`, `addEggShowcase`, `buildEggOddsBoard` and
-- `makePriceCard`. A boundary between them would run through the middle of the thing a player
-- looks at.
--
-- IT WAS ALSO THIRTY-FOUR TOP-LEVEL NAMES IN A FILE THAT LIVES UNDER LUAU'S 200-REGISTER CEILING,
-- and one of them escaped. An egg is built out of a dozen small pieces and each is read only by the
-- next one along, which is exactly the shape that should be behind a require.
--
-- WHO MAY REQUIRE IT: any server script standing an egg stall. `ZoneBuilder` today. `HubPlaza`
-- builds its own and is deliberately untouched.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)

local ZoneKit = require(script.Parent.ZoneKit)

local newPart, addLight, lighten = ZoneKit.newPart, ZoneKit.addLight, ZoneKit.lighten
local pulseForever, SIGN_FONT = ZoneKit.pulseForever, ZoneKit.SIGN_FONT

-- ===== EGGS =====
-- Big, bright, speckled procedural eggs (built from parts, not the old re-tinted mesh whose
-- baked-in texture never actually showed the tier color) so every tier reads as a distinct,
-- colorful reward. Basic/Better get a matte speckled shell; Premium glows with a gem crown.
-- `band` is the stripe around the waist. It is the single strongest cue that this is a toy egg
-- and not a boulder, so every tier gets one, in a colour that fights its own shell rather than
-- blending into it -- Better's first speckle set was three pale blues on a violet shell and the
-- pattern simply vanished.
-- ONE SPOT COLOUR PER EGG, and that is the whole difference between this and what was here before.
-- `speckles` used to be a list of four colours and every patch picked from it at random, so each
-- shell came out covered in red, blue, yellow and green blotches of differing size -- which does
-- not read as a pattern, it reads as a rash. The reference eggs are one clean shell colour plus
-- one strong accent, five or six patches, all the same size.
local EGG_TIER_STYLE = {
	-- One saturated shell colour and ONE accent for its marks, in a clean rarity ladder:
	-- blue -> purple -> gold. The old set was near-white for Basic and near-cream for Better, so on
	-- a bright wooden deck two of the three eggs read as grey blobs and the spot colour was left
	-- carrying the whole tier on its own. Not tinted per zone, same argument as PODIUM_STONE below.
	Basic = {
		base = Color3.fromRGB(72, 178, 246),
		spot = Color3.fromRGB(255, 255, 255),
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Better = {
		base = Color3.fromRGB(168, 96, 255),
		spot = Color3.fromRGB(255, 222, 104),
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Premium = {
		-- THE TOP TIER IS AN EGG. It used to be a cluster of gold blades on a green rock, on the
		-- theory that a different silhouette is what separates it at a glance -- and it did, but it
		-- separated it right out of the set: three podiums under an EGGS sign with two eggs and a
		-- crystal on them reads as a bug, not as a rarity.
		-- What carries the tier instead, without touching the shape:
		--   `facet` turns the round marks into cut DIAMONDS, so the pattern reads as gemstone,
		--   `nest`  grows short amber shards round the foot, so it sits in crystal rather than
		--           being made of it.
		base = Color3.fromRGB(255, 206, 40),
		-- Light AMBER, not near-white. At (255,246,190) the facets read as white paper squares
		-- taped onto a gold egg: a cut face catches more light than the body it is cut into, it does
		-- not change material. Staying inside the gold family is what makes them read as cuts.
		spot = Color3.fromRGB(255, 234, 128),
		shellMaterial = Enum.Material.SmoothPlastic,
		facet = true,
		nest = true,
		crystalDark = Color3.fromRGB(238, 150, 20),
	},
}

-- ===== WHY THE SHELL IS A MESH AND NOT A BALL PART =====
-- A Part with Shape = Ball IGNORES a non-uniform Size: it renders a SPHERE of the SMALLEST axis.
-- Every egg here used to be a Ball sized (11.5, 14.8, 11.5) and was therefore drawn as an 11.5
-- sphere -- which is why the shells read as blobs, and why a cap sphere had to be stacked on top to
-- fake a point, and that cap is what read as a snowman head. The flattened "paint" spots had the
-- same problem: sized (5.4, 5.4, 2.2) they were drawn as 2.2 pellets, not as patches.
-- A Block carrying a SpecialMesh of MeshType Sphere DOES scale on all three axes, so the shell is a
-- true ellipsoid and the marks are true flat discs. Anything round in here goes through eggBall().
local EGG_A, EGG_B = 5.9, 9.0         -- body ellipsoid: half width, half height
local EGG_CAP_A, EGG_CAP_B = 4.2, 6.8 -- the taper that turns an ellipsoid into an egg
local EGG_CAP_Y = 4.4                 -- it is narrower than the body below +6.6 and wider above it,
                                      -- so it takes over the silhouette exactly where an egg points
-- 11.8 wide by 20.2 tall, i.e. 1 : 1.71. It was 1 : 1.44 and read as rounded rather than as an egg;
-- the width came DOWN as well as the height going up, because at a fixed width a taller shell just
-- reads as a bigger egg.
local EGG_BODY = Vector3.new(EGG_A * 2, EGG_B * 2, EGG_A * 2)
local EGG_CAP = Vector3.new(EGG_CAP_A * 2, EGG_CAP_B * 2, EGG_CAP_A * 2)
-- What the plaza measures the egg by: eggY = podiumTop + Y/2 stands the shell on the stone, and
-- addEggShowcase runs the same subtraction backwards to find the podium again.
local EGG_SHELL_SIZE = Vector3.new(EGG_A * 2, EGG_B * 2, EGG_A * 2)
local EGG_PIVOT_Y = 13

-- Shape stays Block: the sphere comes from the mesh, which is the only thing here that scales on
-- all three axes.
local function eggBall(props, parent)
	props.Parent = parent
	local p = newPart(props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Point and outward normal on the body ellipsoid: u walks -1..1 up the axis, a turns around it.
-- The NORMAL is what makes a mark lie flush. Pushing a disc in along the radius instead leaves it
-- tilted everywhere except the equator, and a tilted disc on a shell reads as a chip knocked out
-- of the paint rather than as a mark on it.
local function eggSurface(u, a)
	local r = math.sqrt(math.max(0, 1 - u * u))
	local p = Vector3.new(EGG_A * r * math.cos(a), EGG_B * u, EGG_A * r * math.sin(a))
	return p, Vector3.new(p.X / (EGG_A * EGG_A), p.Y / (EGG_B * EGG_B), p.Z / (EGG_A * EGG_A)).Unit
end

-- The Premium foot: short amber blades leaning out from around the base, each yawed by the golden
-- angle so no two line up and the ring reads as grown rather than as a collar. Short on purpose --
-- they stop below the widest point of the shell, so the egg's outline is never broken by them, and
-- the pale tip is the one thing that makes a plain tapered block read as a faceted crystal.
-- `piece` is buildEgg's helper: it records the PetOffset attribute the client animates against, so
-- every shard rises and turns with the egg.
local function buildCrystalNest(piece, center, style)
	local BLADES = 7
	local GOLD_ANGLE = math.pi * (3 - math.sqrt(5))
	for i = 1, BLADES do
		local f = (i - 1) / BLADES
		local h = 5.4 + math.sin(f * math.pi) * 2.6
		local w = 2.4 - f * 0.5
		local off = CFrame.Angles(0, i * GOLD_ANGLE, 0)
			* CFrame.new(0, -EGG_B + 2.2, 0)
			* CFrame.Angles(math.rad(26 + f * 12), 0, 0)
			* CFrame.new(0, h * 0.5, 0)
		piece({ Name = "EggShard", Size = Vector3.new(w, h, w), CFrame = CFrame.new(center) * off,
			Color = (i % 2 == 0) and style.base or style.crystalDark,
			Material = Enum.Material.SmoothPlastic }, off)
		local tip = off * CFrame.new(0, h * 0.40, 0)
		piece({ Name = "EggShardTip", Size = Vector3.new(w * 0.6, h * 0.26, w * 0.6),
			CFrame = CFrame.new(center) * tip, Color = style.spot,
			Material = Enum.Material.SmoothPlastic }, tip)
	end
end

-- Builds one egg as a Model and returns the shell, which is what the caller hangs the
-- ProximityPrompt on.
--
-- Every piece carries its offset from the shell as a PetOffset attribute and the model is tagged
-- EggIdle, so PetFollowClient can float, rock and spin it on each client without the server sending
-- a CFrame per frame. See the note at the top of PetFollowService.
--
-- NO Highlight and NO PointLight are created here, both on purpose. Roblox draws about 31
-- Highlights at once and a running game already carries 42 of them before a single egg, so an
-- outline baked in here would silently steal the outline off the player's own pets -- the one place
-- it actually matters. The outline is added CLIENT-SIDE to the nearest stall only; see the
-- egg-outline block at the end of PetFollowClient. The light is already there too: addEggShowcase
-- lights the disc the egg stands on.
-- A GENERATED EGG, when one exists for this tier.
--
-- Same idea as the bosses and the player skins: the shell below is a sphere-meshed block with
-- spots laid on a Fibonacci spiral, which is a good painted egg and still reads as a primitive
-- next to a generated boss. Three meshes -- Basic / Better / Premium -- live in
-- ReplicatedStorage.Assets.EggMeshes and stand in for the whole assembly when present.
--
-- Falls through to the built shell when a mesh is missing, so nothing breaks mid-rollout.
--
-- The PetOffset attribute is what the client's hatch animation reads to fly pieces apart; a
-- generated egg is one piece, so it carries a single zero offset and simply rises and spins.
-- ONE SET OF THREE EGGS FOR THE WHOLE GAME WAS THE PROBLEM. Every zone's stall showed the same
-- Basic, Better and Premium shells, so walking twenty platforms you passed the same three objects
-- twenty times -- and the stall is one of the few things a player stands still in front of.
--
-- `EggMesh_<ZoneKey>_<Tier>` wins when it is filed and `EggMesh_<Tier>` is the fallback, which is
-- the same graceful-degradation rule the landmarks, the boss rigs and the idols follow: a zone
-- with no set of its own keeps the shared three and nothing anywhere reports an error. That also
-- means the sixty zone eggs can be filed a few at a time without the world ever being half-built.
local function buildEggMesh(shop, ex, tierSuffix, pivotY, style, zoneKey)
	local assets = RS:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("EggMeshes")
	if not folder then return nil end
	local template = (zoneKey and folder:FindFirstChild("EggMesh_" .. zoneKey .. "_" .. tierSuffix))
		or folder:FindFirstChild("EggMesh_" .. tierSuffix)
	if not template then return nil end

	local model = Instance.new("Model")
	model.Name = "Egg"
	local clone = template:Clone()
	clone.Parent = model

	-- scaled to the shell it replaces, so the podium, the sign clearance and the showcase pet all
	-- keep measuring the same egg they were laid out against
	local _, tSize = clone:GetBoundingBox()
	if tSize.Y < 0.01 then
		model:Destroy()
		return nil
	end
	clone:ScaleTo(EGG_SHELL_SIZE.Y / tSize.Y)

	local center = Vector3.new(ex, pivotY or EGG_PIVOT_Y, 0)
	local cf = clone:GetBoundingBox()
	clone:TranslateBy(center - cf.Position)

	-- One invisible shell part carrying the name and the collision rules the rest of the system
	-- expects, with the mesh pieces parented beside it. CanCollide false for the reason written on
	-- the primitive shell below: the corners of the collision box stick out at head height right
	-- where a player walks past the podium.
	local shell = newPart({
		Name = "EggShell",
		Size = EGG_SHELL_SIZE,
		Position = center,
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	model.PrimaryPart = shell

	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			-- offsets are relative to the SHELL, because the shell is the part the client moves
			-- and everything else hangs off it -- see the note on the primitive egg's `piece`
			p:SetAttribute("PetOffset", CFrame.new(p.Position - center))
			p.Parent = model
		end
	end
	clone:Destroy()

	-- THE SAME FOUR ATTRIBUTES AND THE SAME TAG THE BUILT EGG CARRIES.
	--
	-- PetFollowClient drives every egg in the game off `EggIdle` -- the bob, the rock, the spin and
	-- the proximity outline all key off it. A generated egg without this tag is a rock sitting on a
	-- podium: correct geometry, completely dead, and nothing anywhere would report an error.
	model:SetAttribute("IdleAnchor", shell.CFrame)
	model:SetAttribute("IdlePhase", (ex % 7) * 0.9)
	model:SetAttribute("SpinSpeed", 0.5 + (ex % 3) * 0.09)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "EggIdle")

	model.Parent = shop
	return shell
end

local function buildEgg(shop, ex, tierSuffix, pivotY, zoneKey)
	local style = EGG_TIER_STYLE[tierSuffix] or EGG_TIER_STYLE.Basic
	local center = Vector3.new(ex, pivotY or EGG_PIVOT_Y, 0)

	local meshShell = buildEggMesh(shop, ex, tierSuffix, pivotY, style, zoneKey)
	if meshShell then return meshShell end

	local model = Instance.new("Model")
	model.Name = "Egg"

	-- CanCollide = false, and that is a consequence of the mesh. A Ball part collides as a sphere,
	-- but this is a Block wearing a sphere mesh, so its collision is the BOX -- and the corners of
	-- that box stick two and a half studs out of the shell at head height, right where a player
	-- walks past the podium. The ProximityPrompt does not need collision to be reachable.
	local shell = eggBall({
		Name = "EggShell",
		Size = EGG_BODY,
		Position = center,
		Color = style.base,
		Material = style.shellMaterial,
		CanCollide = false,
	}, model)
	model.PrimaryPart = shell

	-- offsets are relative to the shell, because the shell is what the client moves and everything
	-- else hangs off it. `offset` may be a Vector3 or a full CFrame (marks and shards are both
	-- rotated, and the rotation has to survive into the attribute too).
	local function piece(props, offset, ball)
		props.CanCollide = false
		local p
		if ball then
			p = eggBall(props, model)
		else
			props.Parent = model
			p = newPart(props)
		end
		p:SetAttribute("PetOffset", typeof(offset) == "CFrame" and offset or CFrame.new(offset))
		return p
	end

	piece({
		Name = "EggCap",
		Size = EGG_CAP,
		Position = center + Vector3.new(0, EGG_CAP_Y, 0),
		Color = style.base,
		Material = style.shellMaterial,
	}, Vector3.new(0, EGG_CAP_Y, 0), true)

	-- ===== THE MARKS =====
	-- ONE colour, TWO sizes, laid on a FIBONACCI SPIRAL. Random directions clump -- that is what
	-- random does, and retrying does not fix it -- while the golden angle is the standard
	-- construction for points that are provably never close together. That matters here because the
	-- eggs SPIN (see PetFollowClient): a pattern biased to one face was survivable on a static egg
	-- and is obviously wrong on a turning one. Seven large marks keep three or four facing the
	-- street at any moment; the five small ones ride a second spiral offset from the first, and two
	-- deliberate sizes read as a pattern where one size reads as a golf ball.
	--
	-- `style.facet` swaps the round disc for a square block turned 45 degrees IN THE SURFACE PLANE
	-- (the mark's local Z is the surface normal, so the roll happens flat against the shell). That
	-- is the whole of what makes the Premium shell read as cut gemstone instead of as paint.
	local GOLDEN = math.pi * (3 - math.sqrt(5))
	local function mark(u, ang, d, thick)
		local p, n = eggSurface(u, ang)
		p = p - n * (thick * 0.34) -- sunk, so it reads as paint rather than as a berry
		local off = CFrame.new(p, p + n)
		if style.facet then
			off = off * CFrame.Angles(0, 0, math.rad(45))
			d = d * 0.70 -- a square across its diagonal covers more shell than a disc of the same width
		end
		piece({
			Name = "EggSpot",
			Size = Vector3.new(d, d, thick),
			CFrame = CFrame.new(center) * off,
			Color = style.spot,
			Material = Enum.Material.SmoothPlastic,
		}, off, not style.facet)
	end
	for i = 1, 7 do
		mark(0.68 - (i - 0.5) * (1.32 / 7), i * GOLDEN, 5.0, 2.2)
	end
	for i = 1, 5 do
		mark(0.48 - (i - 0.5) * (1.04 / 5), i * GOLDEN + GOLDEN * 0.5 + 1.2, 2.7, 1.5)
	end

	if style.nest then
		buildCrystalNest(piece, center, style)
	end

	-- The cartoon shine: one long streak high on the shoulder, one small dot below it. Both are flush
	-- discs on the same surface the marks use -- a ball sunk into the shell bulges, and a bulge on a
	-- highlight reads as a bubble stuck to the paint instead of as light on it.
	local function gloss(u, ang, w, h, tr)
		local p, n = eggSurface(u, ang)
		p = p - n * 0.4
		local off = CFrame.new(p, p + n)
		piece({
			Name = "EggGloss",
			Size = Vector3.new(w, h, 1.6),
			CFrame = CFrame.new(center) * off,
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.SmoothPlastic,
			Transparency = tr,
		}, off, true)
	end
	gloss(0.42, 2.45, 3.0, 5.6, 0.22)
	gloss(0.05, 2.05, 1.7, 2.4, 0.30)

	-- Twinkle. ONE camera-facing emitter, not a ring of little neon blocks: a block only reads as a
	-- sparkle from the angle it was rotated for, and from every other angle it is a scrap of paper
	-- floating beside the egg. Parented to the shell so it rides the bob.
	local twinkle = Instance.new("ParticleEmitter")
	twinkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	twinkle.Rate = style.nest and 9 or 5
	twinkle.Lifetime = NumberRange.new(0.7, 1.3)
	twinkle.Speed = NumberRange.new(0.5, 1.6)
	twinkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 3.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	twinkle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	twinkle.Color = ColorSequence.new(Color3.fromRGB(255, 252, 214))
	twinkle.LightEmission = 1
	twinkle.LightInfluence = 0
	twinkle.Rotation = NumberRange.new(0, 360)
	twinkle.RotSpeed = NumberRange.new(-60, 60)
	twinkle.SpreadAngle = Vector2.new(180, 180)
	twinkle.Parent = shell

	-- the egg floats, and without a shadow it reads as pasted onto the sky rather than resting over
	-- its podium. Parented to the shop, not to the model, so it stays put while the egg rocks.
	-- ON TOP OF THE PODIUM CAP, NOT INSIDE IT. This disc spanned y 4.42-4.62 while PodiumTop spans
	-- 3.15-4.65 -- so the shadow ended a third of a stud BELOW the surface it was supposed to be
	-- cast on, and either vanished or flickered against the cap. Sixty of them, one per podium in
	-- the game, on the prop the player stands closest to.
	--
	-- `pivotY - EGG_SHELL_SIZE.Y/2` IS the podium's rest height (that is how the caller computes
	-- eggY), so the clearance is expressed against it rather than against PLAZA_PODIUM_TOP -- that
	-- constant is declared three hundred lines below this function and would be nil here.
	-- 0.37 clears the cap, whose top face is a quarter of a stud above the rest height.
	newPart({
		Name = "EggShadow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 11, 11),
		Orientation = Vector3.new(0, 0, 90),
		Position = Vector3.new(ex, (pivotY or EGG_PIVOT_Y) - EGG_SHELL_SIZE.Y / 2 + 0.37, 0),
		Color = Color3.fromRGB(12, 10, 20),
		Transparency = 0.62,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CastShadow = false,
		Parent = shop,
	})

	model:SetAttribute("IdleAnchor", shell.CFrame)
	model:SetAttribute("IdlePhase", (ex % 7) * 0.9)
	-- three eggs turning at the same rate look mechanical; a few percent apart they never line up
	model:SetAttribute("SpinSpeed", 0.5 + (ex % 3) * 0.09)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "EggIdle")

	model.Parent = shop
	return shell
end

-- ===== WHAT IS INSIDE AN EGG =====
-- Every zone hatches its own five species, so the only thing that tells two eggs apart is that
-- list -- which means it belongs on the egg itself, not buried in a menu. The percentages come
-- from GameConfig.GetEggOdds, the same weights the roll uses, so the board can never advertise
-- odds the roll does not honour. Luck is passed as 0: this is the shop's baseline, and a player's
-- own luck only ever moves it in their favour.
local function buildEggOddsBoard(shop, egg, ex, y)
	local anchor = newPart({
		Name = "EggOddsAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(ex, y, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = shop,
	})

	local odds = GameConfig.GetEggOdds(egg, 0)

	local gui = Instance.new("BillboardGui")
	gui.Name = "EggOdds"
	-- Sized in STUDS, not pixels: a pixel-sized billboard keeps its screen size at any range, so
	-- from the far end of the plaza the three boards grew into each other and covered the eggs.
	-- In studs each strip stays over its own podium, and MaxDistance does the rest -- you get the
	-- odds when you walk up to the egg and the stall reads clean from the street.
	-- WIDE AND SHORT, one cell per species. The old board was a portrait card with a title line and
	-- five full-width rows of "name .... 12%", i.e. a menu -- three of them side by side across the
	-- stall was more text than the whole rest of the zone put together, and none of it was legible
	-- until you were standing under it anyway. The only thing a shopper actually compares between
	-- two eggs is WHICH FIVE and HOW LIKELY, and both fit on one line each.
	gui.Size = UDim2.new(3.7 * #odds, 0, 5.3, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 52
	gui.Parent = anchor

	-- The pill is WHITE. Every earlier board in this place was dark navy on the theory that it
	-- matches the HUD, and it does -- but it is hung in the open air over a bright wooden stall,
	-- where a dark slab reads as a hole punched in the scene. White with a heavy outline is the
	-- shape a price tag has.
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(1, 0, 1, 0)
	pill.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
	pill.BorderSizePixel = 0
	pill.Parent = gui
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0.42, 0)
	pillCorner.Parent = pill
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Thickness = 4
	pillStroke.Color = Color3.fromRGB(28, 38, 58)
	pillStroke.Parent = pill

	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, 0, 1, 0)
	strip.BackgroundTransparency = 1
	strip.Parent = pill
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip

	for i, entry in ipairs(odds) do
		local rarity = GameConfig.GetRarity(entry.def.rarity)

		local cell = Instance.new("Frame")
		cell.Size = UDim2.new(1 / #odds, 0, 0.82, 0)
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = i
		cell.Parent = strip

		-- the species, on its own rounded tile. A pale tile behind the emoji is what stops five
		-- glyphs in a row reading as one word.
		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(0.40, 0, 0.88, 0)
		tile.Position = UDim2.new(0.03, 0, 0.06, 0)
		tile.BackgroundColor3 = Color3.fromRGB(206, 232, 252)
		tile.BorderSizePixel = 0
		tile.Parent = cell
		local tileCorner = Instance.new("UICorner")
		tileCorner.CornerRadius = UDim.new(0.28, 0)
		tileCorner.Parent = tile
		local tileStroke = Instance.new("UIStroke")
		tileStroke.Thickness = 2
		tileStroke.Color = Color3.fromRGB(28, 38, 58)
		tileStroke.Parent = tile

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0.86, 0, 0.86, 0)
		icon.Position = UDim2.new(0.07, 0, 0.07, 0)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.FredokaOne
		icon.TextScaled = true
		icon.Text = entry.def.emoji
		icon.Parent = tile

		-- The percentage is in the RARITY colour, not in one house colour. It is the only number on
		-- the stall and its job is to say "this one basically never happens" before it is read.
		local chance = Instance.new("TextLabel")
		chance.Size = UDim2.new(0.50, 0, 0.66, 0)
		chance.Position = UDim2.new(0.46, 0, 0.17, 0)
		chance.BackgroundTransparency = 1
		chance.Font = Enum.Font.FredokaOne
		chance.TextScaled = true
		chance.TextXAlignment = Enum.TextXAlignment.Center
		chance.TextColor3 = rarity.color
		-- White stroke, not the usual dark one: these sit on a white pill, and a dark outline on a
		-- yellow Legendary number turns it into a smudge at the size a 3-stud cell allows.
		chance.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		chance.TextStrokeTransparency = 0
		-- Below 1% the integer form rounds a real 0.5 chance to "0%", which advertises something
		-- that cannot be won. Two decimals only where it takes two. `textShort` overrides both for
		-- the 12.12 Secret cell, whose real figure (0.002%) no percentage form can print here.
		chance.Text = entry.textShort or (entry.chance < 1 and string.format("%.1f%%", entry.chance)
			or string.format(entry.chance < 10 and "%.1f%%" or "%.0f%%", entry.chance))
		chance.Parent = cell
	end

	return anchor
end

-- The rarest species of the five, floating over the podium: the pet people are actually buying
-- the egg for. Tagged rather than animated here -- a server that CFrames it every frame would
-- replicate the spin to every client at a throttled rate and stutter; PetFollowClient spins it
-- locally instead. See the note at the top of PetFollowService.
local function buildEggFeaturePet(shop, egg, ex, y)
	local pool = GameConfig.GetEggPool(egg)
	if not pool or #pool == 0 then return nil end

	local def = pool[#pool]
	local model, root, pieces = PetModel.Build(def, "Normal", { scale = 1.5, plateDistance = 110, outline = false })
	model.Name = "FeaturePet"
	PetModel.Place(root, pieces, CFrame.new(ex, y, 0))
	model:SetAttribute("SpinAnchor", CFrame.new(ex, y, 0))
	model:SetAttribute("SpinSpeed", 0.7)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "PetDisplay")
	model.Parent = shop
	return model
end

-- Orbit a part around an arbitrary pivot with no per-frame Lua, by the same trick spinForever
-- uses: the repeating tween covers exactly one step of the arrangement's rotational symmetry, so
-- the jump back to the start value at the end of each cycle lands on an identical pose.
local function orbitForever(part, pivot, radius, startDeg, stepDeg, seconds)
	local function poseAt(deg)
		return pivot * CFrame.Angles(0, math.rad(deg), 0) * CFrame.new(radius, 0, 0)
	end
	part.CFrame = poseAt(startDeg)
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		CFrame = poseAt(startDeg + stepDeg),
	}):Play()
end

-- Everything around the shell that is NOT part of the shell: the light column it stands in, a
-- turning starburst behind it, orbiting gems and sparkle. It is parented to the shop rather than
-- to the egg model, so the egg can bob and rock on the client without dragging its own halo
-- around, and none of it needs a PetOffset attribute.
local function addEggShowcase(shop, ex, eggY, accent, style)
	local ring = style.band or accent
	local core = style.spot or style.gemColor or lighten(ring, 0.35)

	-- No light column here any more. A neon cylinder wrapped round the shell blew out to solid
	-- white the moment bloom touched it, and in a bright zone the egg -- the one thing the player
	-- came to look at -- was the least visible object on the podium.
	-- podium top derived from the egg height rather than read from PLAZA_PODIUM_TOP: that constant
	-- is declared below this function, so naming it here would resolve to a nil global
	local podiumTop = eggY - EGG_SHELL_SIZE.Y / 2
	-- NARROWER than the podium top (12) and nearly clear. At 17 studs and 0.6 it overhung the stone
	-- and painted the whole pedestal in the zone accent -- on Mars that is orange, so every stand
	-- read as a raw slab under a blue egg. It is a glow on the stone, not a plate on top of it.
	local disc = newPart({ Name = "EggDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 11.5, 11.5), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, podiumTop + 0.5, 0), Color = ring, Material = Enum.Material.Neon, Transparency = 0.82, CanCollide = false, CastShadow = false, Parent = shop })
	addLight(disc, ring, 17, 0.9)

	-- THE STARBURST IS GONE. Four crossed neon blades behind the shell is the "shiny thing on a
	-- pedestal" cue, and it works against a dark backdrop -- which is what the old plaza was. The
	-- stall that replaced it puts a bright wooden BOARD 11 studs behind the eggs, and four dark
	-- spokes drawn across grain read as cracks in the plank, not as light behind the egg.

	-- Three gems on one orbit -- a 120 degree step is one full symmetry of the set. Pale, and small:
	-- at 3.6 studs in the zone accent they read as red stickers parked beside the shell rather than
	-- as sparkle, and three of them at egg height competed with the spots for the same glance.
	local pivot = CFrame.new(ex, eggY + 3, 0)
	for i = 0, 2 do
		local gem = newPart({ Name = "EggOrbGem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.7, 1.7, 1.7), Color = i == 1 and Color3.fromRGB(255, 255, 255) or core, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = shop })
		orbitForever(gem, pivot, 12.5, i * 120, 120, 6)
		pulseForever(gem, 0.5, 1.4 + i * 0.3)
	end

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), core)
	sparkle.Size = NumberSequence.new(1.5, 0)
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Lifetime = NumberRange.new(1.2, 2.2)
	sparkle.Rate = 9
	sparkle.Speed = NumberRange.new(1, 4)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Acceleration = Vector3.new(0, 3, 0)
	sparkle.Parent = disc
end

-- THE PRICE PLATE, and it is a PLATE ON THE PEDESTAL, not a card floating in front of it.
-- The reference art puts one small rounded tile on the face of each stand carrying nothing but an
-- icon and a number -- no tier name, no second row, no header bar. That is the whole design, and
-- it is why the eggs above it are what the eye lands on: the previous card was 14 studs wide and 7
-- tall with a colour-filled header, i.e. a poster, and three of them across the front of the stall
-- competed with the shells they were advertising.
--
-- Dropping the tier name here loses nothing -- it is the title of the odds board directly above
-- each egg, which is where somebody asking "what IS this one" is already looking.
local PRICE_PLATE_FACE = Color3.fromRGB(226, 232, 240)
local PRICE_PLATE_INK = Color3.fromRGB(28, 38, 58)

local function makePriceCard(shop, ex, y, egg, tierColor)
	-- Sized in studs, not pixels. A pixel-sized billboard keeps its screen size at range, so three
	-- of them 32 studs apart grew into each other -- and into the eggs -- from the plaza steps.
	local anchor = newPart({ Name = "PriceCardAnchor", Size = Vector3.new(1, 1, 1), Position = Vector3.new(ex, y, 7.4), Transparency = 1, CanCollide = false, CastShadow = false, Parent = shop })

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(11, 0, 4, 0) -- BillboardGui scale is studs; offset would be pixels
	bb.StudsOffset = Vector3.new(0, 0.6, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0 -- half the zones are lit near-black; a price must never go unreadable
	bb.MaxDistance = 95
	bb.Parent = anchor

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = PRICE_PLATE_FACE
	card.BorderSizePixel = 0
	card.Parent = bb
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0.34, 0) -- in SCALE, so the pill survives any board size
	cardCorner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = PRICE_PLATE_INK
	stroke.Parent = card

	-- A hairline of the tier's own colour down the left edge. The reference plate is plain grey,
	-- but three identical grey pills say nothing about which egg is the expensive one; this is the
	-- smallest cue that keeps them apart without turning the plate back into a poster.
	local tab = Instance.new("Frame")
	tab.Size = UDim2.new(0.05, 0, 0.56, 0)
	tab.Position = UDim2.new(0.05, 0, 0.5, 0)
	tab.AnchorPoint = Vector2.new(0, 0.5)
	tab.BackgroundColor3 = tierColor
	tab.BorderSizePixel = 0
	tab.Parent = card
	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(1, 0)
	tabCorner.Parent = tab

	local cost = Instance.new("TextLabel")
	cost.Size = UDim2.new(0.8, 0, 0.62, 0)
	cost.Position = UDim2.new(0.56, 0, 0.5, 0)
	cost.AnchorPoint = Vector2.new(0.5, 0.5)
	cost.BackgroundTransparency = 1
	cost.Font = Enum.Font.FredokaOne
	cost.TextScaled = true
	cost.TextColor3 = PRICE_PLATE_INK
	cost.Text = "🧬 " .. egg.cost
	cost.Parent = card

	return anchor
end

-- ===== EGG PLAZA =====
-- The shop is the first thing a player walks into in every zone, so it gets a built stage instead
-- of the old flat 54x26 slab: a two-step lit dais, a back wall carrying the EGGS banner and one
-- nameplate per tier, four pylons holding a canopy beam, and a spotlit podium under every egg.
-- Everything is laid out from the egg row on z = 0 outward, and stays inside the reserved centre
-- square (CLEAR_HALF), so no biome decoration can land on top of it.

-- A WOODEN MARKET STALL, NOT A CIVIC PLAZA. This had grown into a 138-stud stage: a two-step dais
-- with walk-up stairs, a 42-stud back wall, four 45-stud pylons carrying a canopy beam, four lamps
-- and a pair of bollards. That is a monument, and it read as one -- the three eggs the whole thing
-- exists to sell were the smallest objects in it.
--
-- The reference is a stall you walk up to: planks on the ground, a leaning board behind them, a
-- painted EGGS sign, and the eggs big and forward on little pedestals. The eggs are the tallest
-- thing on the stall now, which is the entire point of the stall.
local PLAZA_Z = -4            -- deck centre; the egg row sits 4 studs forward of it
local PLAZA_DECK_TOP = 1.2    -- the planks lie ON the ground now: no dais, no stairs
local PLAZA_PODIUM_TOP = 4.4  -- what each egg actually rests on
local EGG_SPACING = 32 -- was 21; the shells are 40% bigger and their haloes were overlapping

-- Warm timber, deliberately NOT tinted per zone: a wooden stall says "shop" in every biome, where
-- a Volcano-red or a Void-black one says nothing at all.
local STALL_WOOD = Color3.fromRGB(178, 126, 76)
local STALL_WOOD_DARK = Color3.fromRGB(139, 94, 54)
local STALL_PLANK = Color3.fromRGB(198, 148, 96)

-- ===== THE STALL IS A BUILT KIOSK NOW, NOT A LEANING BOARD =====
--
-- What stood behind the eggs was a counter, a tilted plank board and two posts -- flat carpentry
-- that reads as a fence from anywhere but dead-on. The reference the whole plaza was built from is
-- a proper market kiosk: a timber counter you walk up to, four posts and a striped canopy over it.
-- That model exists (`ServerStorage.SourceProps.Shops.Model`), so the stall is three clones of it
-- standing in a row -- one behind each egg -- instead of a wall pretending to be one.
--
-- SCALE, AND WHY IT IS NOT THE EGG SPACING. The kiosk ships 13.4 studs wide, which is one player
-- wide and vanishes on a 120-stud deck; at 2.3x (30.8 wide, aligned to the 32-stud egg spacing) the
-- eggs still towered over it and it read as three garden sheds. 2.9x is 38.9 wide and 32 tall,
-- which is a building you walk up to -- so the row spaces itself at 38 rather than at the eggs' 32
-- and the outer stalls sit six studs wide of their egg. That is invisible on a continuous row and
-- it is the whole reason the stalls can be this size: 3 x 38.9 on 38 centres spans 115 studs, and
-- 120 (i.e. ScatterKit's CLEAR_HALF of 60 either side of the centre line) is all the width the
-- plaza is allowed before biome decoration is free to land on it.
local KIOSK_TEMPLATE = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("PetStallKiosk")
local KIOSK_SCALE = 2.9
local KIOSK_SPACING = 38   -- wider than EGG_SPACING on purpose -- see above
local KIOSK_Z = -28        -- centre of the row; its back lands on the back edge of the deck
local KIOSK_FRONT_Z = -10  -- where its counter faces the player; the sign hangs off this
local SIGN_Y = 29          -- see the sign block in buildEggPlaza for why it is not on the roofline

-- The deck grew with them: 40 studs deep was cut for a flat board, and a kiosk 28 studs deep
-- standing on it would have had its back half hanging over bare ground.
local DECK_DEPTH = 62
local DECK_Z = -15

-- One kiosk per egg, aligned to the same X the podiums use so each shell stands in its own stall.
local function buildKioskRow(shop, cx, eggCount)
	if not KIOSK_TEMPLATE then return end
	local startX = cx - KIOSK_SPACING * (eggCount - 1) / 2
	for i = 1, eggCount do
		local kiosk = KIOSK_TEMPLATE:Clone()
		kiosk.Name = "StallKiosk"
		kiosk:ScaleTo(KIOSK_SCALE)
		kiosk.Parent = shop
		-- the template's pivot is its own base centre, so this stands it ON the planks
		kiosk:PivotTo(CFrame.new(startX + KIOSK_SPACING * (i - 1), PLAZA_DECK_TOP, KIOSK_Z))
		-- generated/inserted geometry arrives unanchored and shadow-casting: unanchored is a stall
		-- that falls through the world on the first physics step, and this is the one spot in a zone
		-- where players stand still, so nothing structural here casts a shadow either
		for _, d in ipairs(kiosk:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CastShadow = false
			end
		end
	end
end

-- The pedestals are a FIXED SLATE BLUE, not the zone accent. They used to be tinted from
-- zone.accentColor like everything else on the stall, which meant a Volcano stand was orange under
-- an orange egg and a Desert one was sand under a cream egg -- the stand and the thing it displays
-- disappeared into each other exactly where the player is meant to be comparing three of them.
-- The reference uses one cool dark stone under every egg for that reason: it is the neutral the
-- shells read against, in all twenty biomes. Same argument as STALL_WOOD above.
local PODIUM_STONE = Color3.fromRGB(64, 82, 104)
local PODIUM_STONE_DARK = Color3.fromRGB(42, 56, 74)
local PODIUM_STONE_LIT = Color3.fromRGB(124, 146, 170)

-- ---- WHAT MAKES IT A MARKET STALL AND NOT A DISPLAY CASE.
-- The deck is 120 studs wide and holds three podiums 32 apart, which leaves about 14 studs of bare
-- plank at each end and a bare strip along the front. Bare deck reads as an unfinished set, so both
-- get dressed: a crate stack and a barrel at the ends, a basket of loose eggs where a shopper
-- stands, and a lantern hung off each post.
--
-- Fixed timber and stone colours, no zone tinting, for the same reason STALL_WOOD has one -- and
-- the mini eggs in the basket take the three TIER colours, which is the one place the stall says
-- what it sells without a word on it.
--
-- Everything here is CanCollide = false on purpose. It sits on the walkway a player crosses to
-- reach a ProximityPrompt, and a crate you can get wedged behind is worse than no crate at all.
local function addStallDressing(shop, cx, halfW, backZ, accent)
	local CRATE = Color3.fromRGB(170, 122, 70)
	local CRATE_DARK = Color3.fromRGB(126, 86, 48)
	local IRON = Color3.fromRGB(74, 66, 62)
	local MINI = {
		EGG_TIER_STYLE.Basic.base,
		EGG_TIER_STYLE.Better.base,
		EGG_TIER_STYLE.Premium.base,
	}

	for _, side in ipairs({ -1, 1 }) do
		local ex = cx + side * (halfW - 11)

		-- Crate stack: two boxes, the upper one turned off-axis and set back. Two boxes squared up
		-- read as one tall box; a few degrees of yaw is the whole difference between cargo and
		-- furniture.
		local crateCF = CFrame.new(ex, PLAZA_DECK_TOP + 4.5, -12) * CFrame.Angles(0, math.rad(side * 9), 0)
		newPart({ Name = "StallCrate", Size = Vector3.new(9, 9, 9), CFrame = crateCF,
			Color = CRATE, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })
		newPart({ Name = "StallCrateBand", Size = Vector3.new(9.4, 1.5, 9.4), CFrame = crateCF,
			Color = CRATE_DARK, Material = Enum.Material.Wood, CanCollide = false, CastShadow = false, Parent = shop })
		newPart({ Name = "StallCrate", Size = Vector3.new(6.6, 6.6, 6.6),
			CFrame = CFrame.new(ex - side * 1.4, PLAZA_DECK_TOP + 12.3, -13.2) * CFrame.Angles(0, math.rad(-side * 22), 0),
			Color = CRATE_DARK, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })

		-- Barrel standing on its end. A Cylinder is extruded along X, so the roll of 90 degrees is
		-- what stands it up; its Y and Z are the cross-section.
		local barrelX = cx + side * (halfW - 5.5)
		newPart({ Name = "StallBarrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8.6, 7.4, 7.4),
			CFrame = CFrame.new(barrelX, PLAZA_DECK_TOP + 4.3, 2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CRATE, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })
		for _, dy in ipairs({ -2.2, 2.2 }) do
			newPart({ Name = "StallBarrelHoop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 7.8, 7.8),
				CFrame = CFrame.new(barrelX, PLAZA_DECK_TOP + 4.3 + dy, 2) * CFrame.Angles(0, 0, math.rad(90)),
				Color = IRON, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false, Parent = shop })
		end

		-- A basket of loose eggs, at the front where a shopper stands. Mini shells go through
		-- eggBall for the same reason the big ones do: a Ball part would draw each one as a sphere
		-- of its smallest axis, i.e. as a pea.
		local bx = cx + side * (halfW - 18)
		newPart({ Name = "StallBasket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 12, 12),
			CFrame = CFrame.new(bx, PLAZA_DECK_TOP + 1.8, 9) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CRATE_DARK, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })
		newPart({ Name = "StallBasketRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 12.8, 12.8),
			CFrame = CFrame.new(bx, PLAZA_DECK_TOP + 3.4, 9) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CRATE, Material = Enum.Material.Wood, CanCollide = false, CastShadow = false, Parent = shop })
		for i = 1, 3 do
			local ang = i * (math.pi * 2 / 3) + side
			eggBall({
				Name = "StallBasketEgg",
				Size = Vector3.new(4.2, 5.4, 4.2),
				CFrame = CFrame.new(bx + math.cos(ang) * 2.9, PLAZA_DECK_TOP + 5.1, 9 + math.sin(ang) * 2.9)
					* CFrame.Angles(math.rad(16), ang, math.rad(11)),
				Color = MINI[i],
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CastShadow = false,
			}, shop)
		end

		-- Lantern hung off the inside face of each post, level with the sign.
		local px = cx + side * (halfW - 1.4) - side * 2.6
		newPart({ Name = "StallLanternRope", Size = Vector3.new(0.5, 3.2, 0.5),
			Position = Vector3.new(px, 24.4, backZ + 1), Color = IRON, Material = Enum.Material.Metal,
			CanCollide = false, CastShadow = false, Parent = shop })
		local lamp = newPart({ Name = "StallLantern", Size = Vector3.new(3.4, 4.4, 3.4),
			Position = Vector3.new(px, 20.6, backZ + 1), Color = Color3.fromRGB(255, 226, 150),
			Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = shop })
		for _, dy in ipairs({ -2.5, 2.5 }) do
			newPart({ Name = "StallLanternCap", Size = Vector3.new(4.2, 1.0, 4.2),
				Position = Vector3.new(px, 20.6 + dy, backZ + 1), Color = IRON, Material = Enum.Material.Metal,
				CanCollide = false, CastShadow = false, Parent = shop })
		end
		addLight(lamp, Color3.fromRGB(255, 220, 150), 24, 1.1)
	end
end

local function buildEggPlaza(shop, zone, cx, eggs)
	local accent = zone.accentColor
	-- Was rgb(38,38,46). Under its own canopy that read as a black hole in the middle of a bright
	-- zone: every darken() below starts from this, so the deck, the wall and the pylons all went
	-- near-black together. A mid slate keeps the neon trim and the eggs popping without the shop
	-- swallowing the light.
	-- Was rgb(92,88,112). Once the world was lit properly that mid-slate was the darkest thing in
	-- any zone -- the shop read as a black box parked in a bright biome. A warm near-white tinted
	-- toward the zone accent keeps it bright and still tells the zones apart.
	local stone = Color3.fromRGB(226, 219, 205):Lerp(accent, 0.24)
	local deckW = EGG_SPACING * (#eggs - 1) + 56
	local halfW = deckW / 2
	local backZ = PLAZA_Z - 20
	local frontZ = PLAZA_Z + 20

	-- ---- the deck: planks laid ON the ground. No dais and no stairs -- the reference stall is
	-- something you walk onto without noticing, and four rises of stair in front of a shop is three
	-- more decisions than buying an egg deserves.
	newPart({ Name = "StallDeck", Size = Vector3.new(deckW, 1.2, DECK_DEPTH), Position = Vector3.new(cx, 0.6, DECK_Z), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
	-- individual boards, so it reads as carpentry instead of one brown rectangle
	local boards = math.max(6, math.floor(deckW / 9))
	local boardW = deckW / boards
	for i = 0, boards - 1 do
		newPart({ Name = "StallPlank", Size = Vector3.new(boardW - 0.8, 0.5, DECK_DEPTH - 1),
			Position = Vector3.new(cx - deckW / 2 + boardW * (i + 0.5), PLAZA_DECK_TOP, DECK_Z),
			Color = i % 2 == 0 and STALL_PLANK or STALL_WOOD, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	end
	-- the glowing lip around the edge -- the one piece of neon the stall keeps, because it is what
	-- says "this patch of ground is a shop" from fifty studs out
	for _, dz in ipairs({ -DECK_DEPTH / 2, DECK_DEPTH / 2 }) do
		newPart({ Name = "StallTrim", Size = Vector3.new(deckW + 2, 0.7, 1.8), Position = Vector3.new(cx, PLAZA_DECK_TOP, DECK_Z + dz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "StallTrim", Size = Vector3.new(1.8, 0.7, DECK_DEPTH), Position = Vector3.new(cx + side * halfW, PLAZA_DECK_TOP, DECK_Z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end

	-- ---- the row of kiosks the eggs stand in front of. See buildKioskRow: this replaced a counter
	-- slab, a tilted plank board and nothing else, which read as a fence from every angle but one.
	buildKioskRow(shop, cx, #eggs)
	-- The two end posts stay, and they are no longer holding a board up: they are what the lanterns
	-- hang off, and they book-end the row at the ends of the deck where the kiosks stop.
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "StallPost", Size = Vector3.new(2.8, 27, 2.8), Position = Vector3.new(cx + side * (halfW - 1.4), 13.5, backZ + 1), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
		newPart({ Name = "StallPostCap", Shape = Enum.PartType.Ball, Size = Vector3.new(4.2, 4.2, 4.2), Position = Vector3.new(cx + side * (halfW - 1.4), 27.4, backZ + 1), Color = STALL_WOOD, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	end

	addStallDressing(shop, cx, halfW, backZ, accent)

	-- ---- THE EGGS PANEL: A REAL PART, NOT A BILLBOARD.
	-- It was a makeSign BillboardGui, and a billboard always turns to face the camera and always
	-- draws in front of whatever is behind it in screen space -- so from the front of the stall the
	-- sign sat squarely across the middle egg, which is the one object it exists to advertise. As
	-- two slabs bolted to the board it occludes correctly: walk round and the eggs pass in front of
	-- it, exactly as the reference shows.
	--
	-- WHITE FACE, DARK BORDER, in every biome. makeSign defaults to the zone's colour, which put a
	-- dark purple plate on a dark purple board in half the strip. This is the one piece of the stall
	-- that has to be readable from the arrival gate, so it takes the highest contrast available and
	-- no zone tinting at all -- same argument as the timber and the pedestals.
	-- 10.2, not 7.6: the shells top out around 19-20 studs and the panel's lower half was sitting
	-- right behind the middle egg's crown, so from dead-on the word was half eaten. This lands the
	-- panel at ~23 and its text clear of everything on the counter.
	-- Hung across the middle kiosk's awning rather than on a board, and upright rather than tilted:
	-- there is no board any more, and a sign leaning off a canopy reads as a sign that fell.
	--
	-- IT IS AT AWNING HEIGHT AND NOT ABOVE THE ROOF. Clearing the roofline (34) put it exactly where
	-- the middle egg's featured-pet billboard draws -- and a BillboardGui always wins in screen
	-- space, so the word EGGS was covered by a Draco from the one angle the stall is read from. At 27
	-- it reads as the stall's fascia, which is where a market stall's name goes anyway.
	local signCF = CFrame.new(cx, SIGN_Y, KIOSK_FRONT_Z + 1.5)
	-- Proportion matters here and it is not free to pick: a SurfaceGui TextLabel with TextScaled
	-- fits by whichever axis binds first, and on a 5:1 panel that is always the HEIGHT -- so the
	-- word came out as a small line floating in a wide white bar. About 3:1 is where the text
	-- actually fills the panel, which is the proportion the reference sign uses.
	-- 33 wide, not 40: on a 120-stud plank board it was a banner across the back, on a 39-stud
	-- kiosk it is that kiosk's own fascia, and at 40 it hid the whole middle stall behind itself.
	newPart({ Name = "StallSignFrame", Size = Vector3.new(33, 12, 1.2), CFrame = signCF,
		Color = Color3.fromRGB(28, 38, 58), Material = Enum.Material.SmoothPlastic,
		CanCollide = false, Parent = shop })
	local signFace = newPart({ Name = "StallSignFace", Size = Vector3.new(29, 8.6, 1.2),
		CFrame = signCF * CFrame.new(0, 0, 0.5), Color = Color3.fromRGB(248, 250, 252),
		Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = shop })

	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "StallSignText"
		gui.Face = face
		gui.LightInfluence = 0 -- half the late zones are lit almost to black
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 36
		gui.MaxDistance = 260
		gui.Parent = signFace

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, 0)
		label.Size = UDim2.new(0.88, 0, 0.72, 0)
		label.Font = SIGN_FONT
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(28, 38, 58)
		label.Text = "\u{1F95A} EGGS"
		label.Parent = gui
	end

	-- ---- one podium per egg, each lit from above so the shell reads against the dark deck
	local startX = cx - EGG_SPACING * (#eggs - 1) / 2
	local built = {}
	for i, egg in ipairs(eggs) do
		local ex = startX + EGG_SPACING * (i - 1)

		-- THE PEDESTAL, built to the reference: a wide dark plinth, a narrow waisted column, and a
		-- pale cap wider than the column it stands on. The waist is the part that matters -- three
		-- discs each narrower than the last is a wedding cake, and a wedding cake reads as scenery.
		-- A column that pinches in and flares back out reads as a STAND, i.e. as something whose only
		-- job is to hold the thing above it, which is exactly what it is.
		-- Everything stays narrower than the egg, so the shell overhangs its stand and keeps the
		-- silhouette -- the old 19-stud podium was wider than the egg and stole it.
		newPart({ Name = "PodiumBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 15, 15), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 0.8, 0), Color = PODIUM_STONE_DARK, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumStep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 12.6, 12.6), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 2.1, 0), Color = PODIUM_STONE, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumWaist", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 9.4, 9.4), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 3.2, 0), Color = PODIUM_STONE, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 12, 12), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_PODIUM_TOP - 0.5, 0), Color = PODIUM_STONE_LIT, Material = Enum.Material.Slate, Parent = shop })
		-- a thin accent ring under the cap, so the egg does not float on grey. This is the ONE place
		-- the zone's colour is allowed onto the stand -- a lit line, not a surface.
		newPart({ Name = "PodiumGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 12.9, 12.9), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_PODIUM_TOP - 1.4, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })

		local eggY = PLAZA_PODIUM_TOP + EGG_SHELL_SIZE.Y / 2
		-- the zone is threaded through so the stall can show this zone's own eggs; buildEggPlaza is
		-- called after ACTIVE_ZONE_KEY has been cleared, so the global is not available here
		local shell = buildEgg(shop, ex, egg.tierSuffix, eggY, zone and zone.key or nil)
		local style = EGG_TIER_STYLE[egg.tierSuffix] or EGG_TIER_STYLE.Basic
		addEggShowcase(shop, ex, eggY, accent, style)

		-- the rarest pet this egg can give, hovering between the shell and the halo, with the
		-- full five-species list above it. Together they are the whole answer to "what is in
		-- this egg", which is the question the three eggs on a podium exist to ask.
		-- RAISED TO CLEAR THE EGGS SIGN. These two are BillboardGuis: they always face the camera and
		-- always draw over whatever is behind them in screen space, so at their old heights the middle
		-- egg's featured pet sat squarely across the painted panel on the board -- from the front, the
		-- one angle the stall is designed to be seen from, the word EGGS was simply gone. The sign is
		-- a physical part and cannot be moved above them without floating off the board, so the
		-- billboards move instead. (They also had to clear the shells, which grew 40% earlier.)
		-- The odds strip goes ABOVE the featured pet, not between it and the egg. The pet is a real
		-- model about seven studs tall, so anything hung at +22 gets stood in front of by it.
		buildEggFeaturePet(shop, egg, ex, eggY + 19)
		buildEggOddsBoard(shop, egg, ex, eggY + 29)

		-- halo above the egg doubles as the spotlight source: a bare PointLight with nothing
		-- visible making it reads as the shell glowing on its own. It sits above the featured
		-- pet so the pet reads as lit from over its head rather than clipping through the disc.
		local halo = newPart({ Name = "PodiumHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 13, 13), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, eggY + 33, 0), Color = lighten(accent, 0.3), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = shop })
		addLight(halo, lighten(accent, 0.3), 20, 1.1)

		-- one price card per podium, tier and cost on two lines. Both were nearly put on the back
		-- wall, but a billboard 21 studs behind the egg renders *behind* it in screen space and
		-- the shell hides the tier name -- in front of the podium it reads like a real price tag.
		makePriceCard(shop, ex, PLAZA_DECK_TOP + 1.6, egg, (EGG_TIER_STYLE[egg.tierSuffix] or EGG_TIER_STYLE.Basic).base)

		built[i] = shell
	end

	-- The canopy, the pylons and the back wall were dropping the whole shop into shadow at every
	-- ClockTime -- and this is the one spot in a zone where players stand still and look at
	-- things. Nothing structural here casts a shadow any more, and two warm fills under the beam
	-- lift the eggs off the deck -- gently: at 1.9 they blew the shells out to flat white and the
	-- speckles disappeared, which is the opposite of the point.
	-- The name prefix changed with the rebuild (Plaza* -> Stall*), and a shadow flag that silently
	-- matches nothing is worse than no flag at all -- the board and posts would have started
	-- casting again with nothing in the diff to say why.
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:sub(1, 5) == "Stall" or d.Name:sub(1, 6) == "Podium") then
			d.CastShadow = false
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local fill = newPart({
			Name = "StallFill",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(cx + side * 14, 27, PLAZA_Z + 6),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = shop,
		})
		addLight(fill, Color3.fromRGB(255, 246, 220), 40, 0.4)
	end

	return built
end

-- One name. The dozen builders above are all reached through this, which is the single line in
-- `ZoneBuilder.Build()` that reads this file -- see the header for why the surface is not twelve
-- verbs wide.
return {
	buildEggPlaza = buildEggPlaza,
	-- exported for the in-place restall of zones that were built before the kiosks existed --
	-- swapping the geometry beats a full 50k-part world rebuild for a change this local
	buildKioskRow = buildKioskRow,
	KIOSK_SCALE = KIOSK_SCALE,
	KIOSK_Z = KIOSK_Z,
	KIOSK_FRONT_Z = KIOSK_FRONT_Z,
	SIGN_Y = SIGN_Y,
	DECK_DEPTH = DECK_DEPTH,
	DECK_Z = DECK_Z,
}
