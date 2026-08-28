-- WeatherLibrary -- the four weather kinds, as particle numbers plus the geometry that puts them
-- where the camera can actually see them (34.7).
--
-- WEATHER IS DRAWN AROUND THE CAMERA, NOT ACROSS THE ZONE, and that is the whole reason this
-- module exists. The first implementation hung one ParticleEmitter on a 1500 x 1246 stud sheet
-- 120 studs over the zone's crest, at Rate 400 with a 2.5 s lifetime. That is ~1,000 live
-- particles spread over 1,869,000 studs of ground: 0.0005 particles per square stud, or about
-- twenty specks anywhere in a 200 x 200 stud view. It cost a full zone's worth of simulation to
-- draw nothing, and every capture of the Forest from a player's eye showed clear sky.
--
-- A camera-sized volume inverts that trade. 90 x 90 studs held over the camera is a hundredfold
-- denser where it is looked at, and nothing is simulated behind the player, in the next valley, or
-- 900 studs out over the wall.
--
-- AND BOTH OF THE ORIGINAL TEXTURES WERE DEAD. `rbxassetid://6327318357` (rain) and
-- `rbxassetid://243082902` (ash/motes) both report `IsLoaded = false` in this place -- measured
-- 2026-08-28 on the running client with an ImageLabel in an ENABLED ScreenGui (a disabled one
-- never loads its images at all). So even at the right density the sheet would have drawn
-- untextured squares. Everything here uses the engine's own `rbxasset://textures/particles/*`
-- sprites, which ship inside the client and cannot 404.
--
-- ===== THE THREE THINGS THAT DECIDE WHETHER WEATHER IS VISIBLE AT ALL =====
--
-- Every number below was set by looking at a capture, and all three of these cost a round of
-- "the emitter is running at full rate and the screen is empty":
--
-- 1. HEIGHT IS A FUNCTION OF FALL SPEED. Ash drifts down at 6-11 studs/s; emitted from the rain
--    height of 55 studs it needs eight seconds to reach eye level and dies of old age on the way.
--    Each kind carries its own `height`, chosen so a particle crosses the view inside its own
--    lifetime. Rain 55, ash 26, motes 22, dust 16.
--
-- 2. THE PARTICLE HAS TO CONTRAST WITH THE GROUND IT FALLS ON, not with an idea of the weather.
--    Sand-coloured dust over the Desert's sand was invisible at any rate; the grains are a dark
--    brown (125, 95, 60) for exactly that reason. The same is true of ash over the Volcano's own
--    orange light -- what reads there is the DARK end of the ember ramp, not the hot end.
--
-- 3. SIZE AND OPACITY MOVE THE NEEDLE FASTER THAN RATE. Tripling the rate of a 1.5-stud 25%-opaque
--    sprite changed almost nothing on screen; going to 4.5 studs at 50% turned the same emitter
--    into visible weather. Reach for the sprite before the count -- it is also the cheaper half.
--
-- ===== TWO LAYERS, BECAUSE HAZE AND FLECKS ARE DIFFERENT THINGS =====
--
-- Ash and dust each run two emitters on the one volume. A single emitter can be a warm haze that
-- tints the air OR a scatter of distinct flecks, and neither alone reads as weather: the haze
-- with no flecks looks like a colour-grade, the flecks with no haze look like dirt on the lens.
-- Rain and motes are one layer each -- a rain streak is already both.
--
-- BUDGET (rate x mean lifetime = live particles, the only figure that matters for frame time):
-- rain 344, ash 675 + 240 = 915, dust 280 + 990 = 1,270, motes 712. Dust is the heavy one and it
-- is the one to trim first if a device ever struggles. Measured in the Volcano on 2026-08-28,
-- weather on vs off: 60.0 fps / 16.67 ms both ways, worst frame 35.1 vs 35.6 ms -- no difference
-- outside noise, though Studio's 60 fps cap means this measures "does not cost a frame", not the
-- headroom underneath it.

local WeatherLibrary = {}

-- The sprites, both shipped with the client.
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- Each kind is:
--   `height`  studs above the camera the emitting sheet is held
--   `forward` studs ahead of the camera it is pushed, so the weather falls into view rather than
--             only behind the player's shoulder
--   `span`    the side of the square sheet
--   `layers`  one or more emitter specs; `tintable` marks the one a zone's colour replaces
WeatherLibrary.Kinds = {
	-- Rain: near-vertical streaks. `Squash` stretches the sprite along its own axis, which turns
	-- the four-point spark into a drop. Measured against the Forest at midday (the brightest
	-- ground in the game) -- a paler blue or a smaller size vanishes into it.
	rain = {
		height = 55,
		forward = 25,
		span = 90,
		layers = {
			{
				name = "Rain",
				tintable = true,
				texture = SPARK,
				color = Color3.fromRGB(105, 150, 210),
				size = 2.0,
				squash = 2.4,
				transparency = 0.2,
				lightEmission = 0,
				rate = 420,
				speed = NumberRange.new(95, 115),
				lifetime = NumberRange.new(0.7, 0.95),
				acceleration = Vector3.new(0, -25, 0),
				spread = Vector2.new(0, 0),
				rotSpeed = NumberRange.new(0, 0),
			},
		},
	},

	-- Ash: a warm haze with embers turning over inside it. The haze colour runs hot at birth and
	-- dead grey at the end; the embers stay lit for most of their life, which is what separates a
	-- volcanic sky from a dusty one.
	ash = {
		height = 26,
		forward = 22,
		span = 90,
		layers = {
			{
				name = "Ash",
				tintable = true,
				texture = SMOKE,
				color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 160, 70)),
					ColorSequenceKeypoint.new(0.6, Color3.fromRGB(190, 90, 45)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 55, 55)),
				}),
				size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 4.5),
					NumberSequenceKeypoint.new(1, 3.0),
				}),
				squash = 1,
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.12, 0.45),
					NumberSequenceKeypoint.new(0.85, 0.55),
					NumberSequenceKeypoint.new(1, 1),
				}),
				lightEmission = 0.5,
				rate = 90,
				speed = NumberRange.new(6, 11),
				lifetime = NumberRange.new(6, 9),
				acceleration = Vector3.new(2, -2, 0),
				spread = Vector2.new(25, 25),
				rotSpeed = NumberRange.new(-25, 25),
			},
			{
				name = "Embers",
				texture = SPARK,
				color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 120)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 40)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 40, 20)),
				}),
				size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.8),
					NumberSequenceKeypoint.new(1, 0.4),
				}),
				squash = 1,
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.15, 0.1),
					NumberSequenceKeypoint.new(0.8, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				}),
				lightEmission = 0.65,
				rate = 40,
				speed = NumberRange.new(5, 10),
				lifetime = NumberRange.new(5, 7),
				acceleration = Vector3.new(3, -2, 0),
				spread = Vector2.new(30, 30),
				rotSpeed = NumberRange.new(-60, 60),
			},
		},
	},

	-- Dust: the same two-layer shape blown sideways. The acceleration is mostly horizontal on
	-- purpose -- a desert reads as wind, not as weather falling out of the sky -- and the grains
	-- are DARKER than the ground, which is the only reason they can be seen over sand.
	dust = {
		height = 16,
		forward = 16,
		span = 90,
		layers = {
			{
				name = "Dust",
				tintable = true,
				texture = SMOKE,
				color = Color3.fromRGB(225, 200, 150),
				size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 5.0),
					NumberSequenceKeypoint.new(1, 7.0),
				}),
				squash = 1,
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.2, 0.6),
					NumberSequenceKeypoint.new(0.8, 0.7),
					NumberSequenceKeypoint.new(1, 1),
				}),
				lightEmission = 0,
				rate = 80,
				speed = NumberRange.new(14, 22),
				lifetime = NumberRange.new(3, 4),
				acceleration = Vector3.new(-14, -8, 4),
				spread = Vector2.new(18, 18),
				rotSpeed = NumberRange.new(-15, 15),
			},
			{
				name = "Grains",
				texture = SPARK,
				color = Color3.fromRGB(125, 95, 60),
				size = 0.8,
				squash = 2.5,
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.15, 0.2),
					NumberSequenceKeypoint.new(0.85, 0.3),
					NumberSequenceKeypoint.new(1, 1),
				}),
				lightEmission = 0,
				rate = 330,
				speed = NumberRange.new(20, 30),
				lifetime = NumberRange.new(2.5, 3.5),
				acceleration = Vector3.new(-18, -12, 5),
				spread = Vector2.new(12, 12),
				rotSpeed = NumberRange.new(-30, 30),
			},
		},
	},

	-- Motes: slow drifting specks. LightEmission is 0.2 and no higher -- at 0.8 the tint clips to
	-- white and the "gentle sparkle" renders as a screen full of starbursts (measured). Five zones
	-- wear this kind and the tint is what keeps them from being the same gold.
	motes = {
		height = 22,
		forward = 18,
		span = 90,
		layers = {
			{
				name = "Motes",
				tintable = true,
				texture = SPARK,
				color = Color3.fromRGB(255, 226, 150),
				size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.6),
					NumberSequenceKeypoint.new(0.5, 1.05),
					NumberSequenceKeypoint.new(1, 0.4),
				}),
				squash = 1,
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.25, 0.2),
					NumberSequenceKeypoint.new(0.75, 0.28),
					NumberSequenceKeypoint.new(1, 1),
				}),
				lightEmission = 0.2,
				rate = 95,
				speed = NumberRange.new(1, 4),
				lifetime = NumberRange.new(6, 9),
				acceleration = Vector3.new(0, -1.2, 0),
				spread = Vector2.new(40, 40),
				rotSpeed = NumberRange.new(-40, 40),
			},
		},
	},
}

local function asColorSequence(v)
	if typeof(v) == "ColorSequence" then return v end
	return ColorSequence.new(v)
end

local function asNumberSequence(v)
	if typeof(v) == "NumberSequence" then return v end
	return NumberSequence.new(v)
end

-- Builds one kind's emitters under `volume` and returns the kind (for its height/forward/span).
-- `tint` (optional) replaces the colour of the layer marked `tintable` and leaves the other alone:
-- a zone tints its haze, never its contrast layer, or Mars would get sand-coloured sand again.
function WeatherLibrary.Build(volume, kindName, tint)
	local kind = WeatherLibrary.Kinds[kindName]
	if not kind then return nil end

	for _, layer in ipairs(kind.layers) do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = layer.name
		emitter.Texture = layer.texture
		emitter.Color = (tint and layer.tintable) and ColorSequence.new(tint) or asColorSequence(layer.color)
		emitter.Size = asNumberSequence(layer.size)
		emitter.Squash = asNumberSequence(layer.squash)
		emitter.Transparency = asNumberSequence(layer.transparency)
		emitter.LightEmission = layer.lightEmission
		emitter.Rate = layer.rate
		emitter.Speed = layer.speed
		emitter.Lifetime = layer.lifetime
		emitter.Acceleration = layer.acceleration
		emitter.SpreadAngle = layer.spread
		emitter.RotSpeed = layer.rotSpeed
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Orientation = Enum.ParticleOrientation.FacingCamera
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Drag = 0
		emitter.ZOffset = 0
		emitter.Parent = volume
	end

	return kind
end

return WeatherLibrary
