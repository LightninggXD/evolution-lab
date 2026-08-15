local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
-- the arena's countdown board is found by tag rather than by path, so ZoneBuilder can move it
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local DNAService = require(script.Parent.DNAService)
local SeasonPassService = require(script.Parent.SeasonPassService)
local UITheme = require(RS.Modules.UITheme)
local VFXLibrary = require(RS.Modules.VFXLibrary)
local VFXService = require(script.Parent.Systems.VFXService)
-- 12.14's kill feed. Safe at module scope: AnnounceService requires GameConfig and UITheme and
-- nothing else, so there is no cycle back into this file.
local AnnounceService = require(script.Parent.AnnounceService)

local BossService = {}

-- The same channel CreatureService opens: the swing, the impact spark and the damage number are
-- drawn by StarterPlayerScripts.CombatClient on each machine. Opened here the same way (find or
-- create) so neither service depends on the other having initialised first.
local function ensureRemote(name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = Remotes
	return ev
end

local CombatFx = ensureRemote("CombatFx")
local FX_RADIUS = 420 -- wider than the creatures': a 124-stud event boss is visible from further

-- Auto-attack. Same remote CreatureService opens, and for the same reason a ClickDetector cannot
-- serve it: nothing can fire one but a real click. Both services listen on it and each ignores
-- any model it has no handler for, so one channel covers creatures and bosses without either
-- service knowing the other exists.
--
-- The stage gate, the 0.25 s cooldown and the retaliation all live inside the handler below, so
-- routing a request into it is exactly as safe as routing a click into it.
local AutoAttack = ensureRemote("AutoAttack")
local hitHandlers = {} -- [model] = { fn, body, reach }; cleared explicitly on death/despawn

-- THE REVIVE REMOTE TAKES NO ARGUMENTS, AND THAT IS THE POINT.
--
-- The server picks the target out of its own per-player snapshot below. A client-supplied model
-- would hand every exploiter a "set any boss to any health" primitive, which is a strictly worse
-- thing to own than the product itself is worth.
local UseBossRevive = ensureRemote("UseBossRevive")

-- The fewest blows a boss may be killed in. See the note above TIERS in CreatureService: player
-- damage and enemy health are on curves that only meet in the zone matching the player's stage,
-- and every earlier zone stays walkable -- so a boss seven zones back would otherwise die to one
-- click, which is the whole of a boss fight replaced by a sound effect.
-- BOSS_MIN_HITS is gone: it clamped every blow to a twelfth of the boss's health, so a boss died
-- in exactly twelve hits in every zone no matter who was hitting it, and no progression could show
-- against one. Boss health is derived from the damage ladder now (GameConfig.BossTargetHits), which
-- is the same guarantee expressed as arithmetic instead of as a clamp.
--
-- EVENT_MIN_HITS stays and means something different: the event boss is one shared target for a
-- whole server, so a ceiling on what ONE player may contribute is what keeps it a group fight
-- rather than a race won by whoever is furthest ahead.
local EVENT_MIN_HITS = 40

local function broadcastFx(payload)
	local at = payload.p
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - at).Magnitude <= FX_RADIUS then
			CombatFx:FireClient(plr, payload)
		end
	end
end

local bossesFolder = workspace:FindFirstChild("Bosses")
if not bossesFolder then
	bossesFolder = Instance.new("Folder")
	bossesFolder.Name = "Bosses"
	bossesFolder.Parent = workspace
end

-- Where the boss stands, relative to its zone's centre. The gates live in the Z walls now, so a
-- zone is one straight street: you arrive at +Z, buy eggs in the middle, and leave by the gate at
-- -Z. The boss belongs on that line, between the shop and the exit -- it is the thing standing in
-- front of the next door, and beating it is exactly what opens that door (GameConfig's
-- requiresBossKey). Parked off at (175, 0, 0) it stood beside the shop, and a player could walk
-- the whole street and leave without ever meeting it.
--
-- THE Z COMES FROM GameConfig, NOT FROM A CONSTANT HERE. It was a local `-240` while ZoneBuilder
-- reserved its clearing at `-320`: a platform-depth rescale moved one and missed the other, so
-- scattered props grew straight through the arena while the cleared ground sat empty 80 studs
-- away. One number, one file, both readers.
local BOSS_RELATIVE_OFFSET = Vector3.new(0, 0, GameConfig.BossStationZ)

-- Half of ZoneBuilder's PLATFORM_WIDTH (1250), and how far down the street the exit gate's
-- approach steps begin. spawnBoss measures each finished rig against both and walks the oversized
-- ones back in, so a boss never hangs over the drop at the sides nor buries the gate it guards.
local PLATFORM_HALF_X = 625
local GATE_APPROACH_Z = -502
local EDGE_MARGIN = 6

-- ===== WHICH WAY A BOSS LOOKS =====
-- Every rig is authored facing its own local -Z (heads sit at -u*0.66, see the builders below) and
-- the origin used to be a plain CFrame.new(position) -- no rotation at all. Standing on a street
-- that runs down -Z, that pointed all twenty of them at the exit gate, so a player walking up from
-- the arrival plaza fought the back of the boss's head.
--
-- Making the origin a ROTATED CFrame is all it takes: `att` places each part at `origin * offset`
-- and the idle driver poses at `origin * pivot * motion * rest`, so a rotation there turns the rig,
-- its arena disc and its banner masts together. And it is free -- the driver already rebuilds every
-- attachment of a nearby boss each frame, so a boss that TRACKS THE PLAYER costs the same as one
-- that stares straight ahead. CFrame.lookAt puts local -Z on the target, which is the same axis the
-- faces are built on.
-- ...and everything above is still true of how a rig is BUILT and posed. What is gone is the boss
-- turning to track a player: `yawTowards` and `BOSS_TURN_RADIUS` went with it (10.8, and the
-- reasoning is at the driver). The rate survives because the driver still lerps toward `home`,
-- which is what makes an off-facing rig walk back to the gate instead of snapping.
local BOSS_TURN_RATE = 1.9    -- radians/sec. Deliberate, not a snap: a boss is heavy.

-- Same abbreviation MainUI uses for every other number in the game. Boss health reaches
-- 43,000,000 by the last zone, so the health plate has to read "43.00M", not fifteen digits.
-- Duplicated rather than shared because MainUI is a LocalScript this server module cannot require.
local function formatNumber(n)
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	local suffixes = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
	local mag = 0
	while n >= 1000 and mag < #suffixes do
		n = n / 1000
		mag += 1
	end
	-- THE ROUNDING CARRIES past the loop, which has already stopped looking: 999,999 divides once to
	-- 999.999, is accepted, and "%.2f" prints "1000.00K" for a number one short of a million. 999.995
	-- and not 999.95 because this prints TWO decimals -- the constant has to match the precision it
	-- guards, or it fires a place too early.
	if n >= 999.995 and mag < #suffixes then
		n = n / 1000
		mag += 1
	end
	return string.format("%.2f%s", n, suffixes[mag])
end

-- THE CAP THAT MAKES HALF THE GAME REACHABLE. See the longer note on CreatureService.hurtPlayer.
--
-- A boss takes GameConfig.BossTargetHits blows to fell, and it swings back on most of them. The
-- player's maximum health is additive across the twenty stages -- 100 + 40 per stage, doubled at
-- most by Stage Mastery, so 1720 at the very top -- while boss retaliation is multiplied zone by
-- zone at roughly 1.18x. Those two curves cross at zone 9, and from zone 11 the fight is lost
-- arithmetically: the Wormhole Horror deals 250 per blow you land, so you survive 6.9 of the 12
-- the floor requires. Everything past it, up to and including The Absolute, was unreachable by any
-- build, with any pets, at any stage. That is half the game behind a wall no player could pass.
--
-- Capping incoming damage at a share of the player's own maximum makes the two curves the same
-- curve. It does not make bosses easy -- the blows the fight requires are still the blows it
-- requires -- it makes them finishable.
--
-- ===== 14.2: THIS CAP WAS NEVER ARMED =====
--
-- `requiredHits` was optional and NOT ONE of the four call sites passed it, so the branch below
-- never ran and raw `retaliateDamage` / `auraDamage` were applied in every fight in the game. The
-- wall the block above says was removed was therefore still standing: The Absolute retaliates for
-- 1,248-1,638 on 98% of your blows against a measured player maximum of 2,924, i.e. **2.0 landed
-- blows survived** for a fight that needs more than five. It went unseen for exactly one reason --
-- until 14.1 the player one-shot the boss, so it never got a turn. Fixing the one-shot is what made
-- the older bug reachable, and the two are one change: on its own, 14.1 turns every boss from
-- trivially winnable into arithmetically unwinnable.
--
-- WHAT IS PASSED NOW is the length of THIS player's fight -- `blowsToFell` below -- rather than a
-- constant. That is what makes the cap scale-free, and the arithmetic is worth writing down because
-- it is the whole design. Per blow the cap is `MaxHealth / (blows * 2)`, so over a whole fight:
--
--   retaliation:  0.98 * blows * MaxHealth / (blows * 2)   = 0.49 * MaxHealth
--   aura:         (0.34/auraInterval) * blows * that       ~ 0.21 * MaxHealth
--
-- The `blows` term cancels in both. A player finishes any boss in any zone at any point on the
-- ladder with roughly 30% of their health left, whether the fight took six blows or a hundred and
-- fifty -- and a player who stands still, mistimes it or arrives under-geared still dies, because
-- none of that is what the cap protects against.
local function hurtPlayer(player, amount, requiredHits)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if requiredHits and requiredHits > 0 and humanoid.MaxHealth > 0 then
		amount = math.min(amount, humanoid.MaxHealth / (requiredHits * 2))
	end
	amount = math.max(amount, 1)
	humanoid:TakeDamage(amount)
	Remotes.Notify:FireClient(player, { kind = "playerHurt", amount = math.floor(amount) })
end

-- How many landed blows this player needs to fell this boss -- the `requiredHits` every call to
-- `hurtPlayer` above is held to. Floored at 1 so a one-shot still leaves the cap meaningful, and
-- ceil'd because a fight that needs 5.4 blows is a six-blow fight.
local function blowsToFell(bossHealth, playerDamage)
	return math.max(1, math.ceil(bossHealth / math.max(playerDamage, 1)))
end

local function hasDefeated(data, zoneKey)
	for _, k in ipairs(data.DefeatedBosses) do
		if k == zoneKey then return true end
	end
	return false
end

-- Marks this zone's boss as defeated for the player, syncs their data/leaderstats, and
-- re-checks zone unlocks (ZoneService.CheckUnlocks handles the "new zone!" notification).
local function markDefeated(player, data, zoneKey)
	if not hasDefeated(data, zoneKey) then
		table.insert(data.DefeatedBosses, zoneKey)
	end
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	-- required lazily to avoid a circular require with ZoneService
	local ZoneService = require(script.Parent.ZoneService)
	ZoneService.CheckUnlocks(player, data)
end

-- ===== BOSS RIG FACTORY =======================================================
-- Every boss used to be the same Neon ball with a cylinder crown, so the climax of a zone
-- looked like a beach ball. Each of the 20 bosses is now a hand-built rig of anchored
-- primitives, using the same vocabulary CreatureService's creature rigs use: `mk` makes a
-- part, `att` hangs it off a joint with an idle motion, `buildPalette` derives the colours
-- from the zone. Bosses are 10-32 studs -- far bigger than creatures -- so they run heavier
-- (roughly 18-30 parts): layered torso, real limbs or tendrils, a face you can read, and a
-- silhouette that still says what it is from the far end of the platform. Rigs escalate
-- along the zone order the same way the stats do: Forest is an animal, the last few are
-- barely bodies at all.

local IDENTITY = CFrame.new()
local INK = Color3.fromRGB(26, 18, 36) -- the same near-black the UI outlines use
local SIDES = { -1, 1 }
local BONE = Color3.fromRGB(248, 244, 232) -- fangs/claws, kept constant across all zones

-- Cylinder length runs along X, so a disc has to be rolled into place: FLAT lies down like
-- a halo or an accretion ring, FACE stands up like a maw or a clock face.
local DISC_FLAT = CFrame.Angles(0, 0, math.rad(90))
local DISC_FACE = CFrame.Angles(0, math.rad(90), 0)

local function lighten(c, f) return c:Lerp(Color3.fromRGB(255, 255, 255), f) end
local function darken(c, f) return c:Lerp(INK, f) end

-- zone.accentColor + zone.groundColor -> the boss palette. A boss takes the deeper, angrier
-- end of its zone's colour than the creatures do; `rage` (the old boss eye red) and `gold`
-- stay constant across all 20 so every boss still reads as royalty of its zone.
local function buildPalette(zone)
	local accent, ground = zone.accentColor, zone.groundColor
	local skin = darken(accent, 0.26)
	return {
		skin = skin,
		light = lighten(skin, 0.32),
		belly = lighten(accent, 0.5),
		dark = darken(skin, 0.5),
		ink = darken(accent, 0.84),
		trim = darken(ground:Lerp(accent, 0.45), 0.22),
		metal = lighten(ground:Lerp(accent, 0.35), 0.2),
		glow = lighten(accent, 0.5),
		rage = Color3.fromRGB(255, 46, 40),
		gold = Color3.fromRGB(255, 205, 70),
	}
end

local function mk(ctx, name, shape, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.model
	return p
end

-- pivot = the JOINT (a translation from the body centre, plus a yaw when the joint sits on
-- a ring); rest = the part's own offset/rotation out from that joint. The idle motion is
-- applied BETWEEN the two, so an arm swings around its shoulder instead of spinning around
-- its own middle.
-- `ctx.fixed` marks everything placed while it is set as SCENERY rather than as part of the
-- creature: it is positioned once against the build facing and is never turned again, however far
-- the boss swings round. See the note on arenaDetail.
local function att(ctx, part, pivot, rest, motion, amp, speed, phase)
	rest = rest or IDENTITY
	local a = {
		part = part,
		pivot = pivot,
		rest = rest,
		offset = pivot * rest,
		motion = motion,
		amp = amp or 0,
		speed = speed or 1,
		phase = phase or 0,
		fixed = ctx.fixed or nil,
	}
	table.insert(ctx.atts, a)
	part.CFrame = ctx.origin * a.offset
	return part
end

-- The idle pose of one attachment at time t. "float"/"pulse" amplitudes are in studs, every
-- other kind is in radians. "pulse" pushes along the joint's own X, which is the OUTWARD
-- axis for anything ringOf placed -- that is what makes a tooth circle breathe.
local function motionOf(a, t)
	local phase = t * a.speed + a.phase
	if a.motion == "swing" then
		return CFrame.Angles(math.sin(phase) * a.amp, 0, 0)
	elseif a.motion == "flap" then
		return CFrame.Angles(0, 0, math.sin(phase) * a.amp)
	elseif a.motion == "trail" then
		return CFrame.Angles(math.sin(phase) * a.amp, 0, math.cos(phase * 0.7) * a.amp * 0.5)
	elseif a.motion == "orbit" then
		return CFrame.Angles(0, phase, 0)
	elseif a.motion == "float" then
		return CFrame.new(0, math.sin(phase) * a.amp, 0)
	elseif a.motion == "pulse" then
		return CFrame.new(math.sin(phase) * a.amp, 0, 0)
	end
	return IDENTITY
end

-- left/right mirror: fn gets -1 then +1, so a rig writes one limb and gets the pair
local function pairUp(fn)
	for _, side in ipairs(SIDES) do
		fn(side)
	end
end

-- a disc built out of a Cylinder -- craters, haloes, accretion rings, portals, maws
local function disc(ctx, name, diameter, thick, color, material, transparency)
	return mk(ctx, name, Enum.PartType.Cylinder, Vector3.new(thick, diameter, diameter), color, material, transparency)
end

-- The face. Built the way ReplicatedStorage.Modules.PetModel builds a pet's: a pale sclera, a
-- glowing iris, a dark pupil and a highlight glint, stacked front to back. The pets read as drawn
-- characters rather than stacked blocks almost entirely because of this -- a boss used to get one
-- flat Neon ball per socket and came out looking like machinery instead of a creature.
--
-- The brow is the piece doing the most work: tilted down toward the nose it turns the same eye
-- from blank into a glare, which is what a boss silhouette needs to sell across a platform.
-- Every layer shares one joint and one motion phase so the whole face floats as a unit.
local function eyePair(ctx, x, y, z, d, color, speed)
	local amp, sp, phase = ctx.u * 0.012, speed or 1.5, 0.4
	pairUp(function(side)
		local joint = CFrame.new(side * x, y, z)

		-- Rigs face -Z, so each layer steps further along -Z to sit in front of the last. The
		-- offsets are not decorative: these are spheres, so a layer only shows if it breaks the
		-- surface of the one behind it. The iris front sits at -0.62d, and everything in front of
		-- it is placed to clear that -- the first cut had the pupil at -0.44d, buried inside the
		-- iris where it rendered as nothing at all.
		local sclera = mk(ctx, "EyeWhite", Enum.PartType.Ball, Vector3.new(d, d, d), BONE)
		att(ctx, sclera, joint, IDENTITY, "float", amp, sp, phase)

		local iris = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(d * 0.68, d * 0.68, d * 0.68), color, Enum.Material.Neon)
		att(ctx, iris, joint, CFrame.new(0, 0, -d * 0.28), "float", amp, sp, phase)

		-- a slit rather than a dot: it survives being viewed from across a platform, and it is
		-- what makes the eye read as a predator's instead of a cartoon's
		local pupil = mk(ctx, "Pupil", Enum.PartType.Block, Vector3.new(d * 0.18, d * 0.6, d * 0.26), INK)
		att(ctx, pupil, joint, CFrame.new(0, 0, -d * 0.58), "float", amp, sp, phase)

		local glint = mk(ctx, "Glint", Enum.PartType.Ball, Vector3.new(d * 0.2, d * 0.2, d * 0.2), Color3.fromRGB(255, 255, 255))
		att(ctx, glint, joint, CFrame.new(-side * d * 0.19, d * 0.19, -d * 0.55), "float", amp, sp, phase)

		local brow = mk(ctx, "Brow", Enum.PartType.Block, Vector3.new(d * 1.3, d * 0.26, d * 0.28), ctx.pal.ink)
		att(ctx, brow, joint, CFrame.new(0, d * 0.62, -d * 0.3) * CFrame.Angles(0, 0, math.rad(side * -22)), "float", amp, sp, phase)
	end)
end

-- a mirrored limb swinging around its joint; the sides run half a cycle apart so legs
-- alternate and arms counter-swing
local function limbPair(ctx, name, size, joint, drop, color, material, tilt, amp, speed)
	pairUp(function(side)
		local limb = mk(ctx, name, Enum.PartType.Block, size, color, material)
		att(ctx, limb, CFrame.new(side * joint.X, joint.Y, joint.Z),
			CFrame.Angles(0, 0, math.rad(side * (tilt or 0))) * CFrame.new(0, -drop, 0),
			"swing", amp or 0.2, speed or 1.7, side > 0 and 0 or math.pi)
	end)
end

-- `count` parts spaced evenly around the Y axis, each handed a joint whose +X already
-- points outward -- tentacle crowns, tooth circles, capes and accretion rings all come out
-- of this one loop
local function ringOf(ctx, count, radius, y, build)
	for i = 1, count do
		local a = (i - 1) * (math.pi * 2 / count)
		build(i, a, CFrame.new(math.cos(a) * radius, y, math.sin(a) * radius) * CFrame.Angles(0, -a, 0))
	end
end

-- a circle of fangs leaning inward over a maw
local function toothRing(ctx, count, radius, y, len, color)
	ringOf(ctx, count, radius, y, function(i, _, joint)
		local tooth = mk(ctx, "Tooth", Enum.PartType.Wedge, Vector3.new(len * 0.34, len, len * 0.34), color)
		att(ctx, tooth, joint, CFrame.Angles(0, 0, math.rad(108)) * CFrame.new(0, len * 0.4, 0), "pulse", ctx.u * 0.012, 2.2, i * 0.6)
	end)
end

-- gold crown spikes -- reserved for the bosses that actually rule something
local function crownOf(ctx, count, radius, y, len, color)
	ringOf(ctx, count, radius, y, function(i, _, joint)
		local spike = mk(ctx, "CrownSpike", Enum.PartType.Wedge, Vector3.new(len * 0.3, len, len * 0.42), color, Enum.Material.Metal)
		att(ctx, spike, joint, CFrame.new(0, len * 0.45, 0) * CFrame.Angles(0, 0, math.rad(-9)), "float", ctx.u * 0.012, 1.3, i * 0.4)
	end)
end

-- ===== GENERATED MESH RIGS ====================================================================
-- A boss whose figure was GENERATED (ServerStorage.BossMeshes.BossMesh_<zoneKey>) instead of
-- assembled below out of primitives. The template is a Model of six MeshParts named
-- `head_geom` / `torso_geom` / `left arm_geom` / `right arm_geom` / `left leg_geom` /
-- `right leg_geom` -- the segmentation asked for at generation time, and the whole reason a
-- generated boss can still move: this driver poses whole PARTS, so six pieces is six joints.
-- Ask for one undivided mesh and the boss is a statue.
--
-- Held as a TEMPLATE and cloned per spawn: twenty zones each stand up their own boss, and a
-- MeshPart cannot be in two places at once.
local MESH_HEIGHT_MULT = 1.56 -- ctx.u is 75 here, so this is the ~117 studs the primitive rig stood at
local MESH_GROUND_CLEAR = 1  -- studs of daylight under the soles, so feet rest ON the dais not in it

-- Which joint each limb swings around, and on what phase. Diagonal gait: the left arm and the
-- right leg carry the same phase, which is what stops the walk reading as a hop.
local MESH_LIMB = {
	["head_geom"]      = { motion = "float", amp = 0.016, speed = 1.2, phase = 0.3,      joint = "bottom" },
	["left arm_geom"]  = { motion = "swing", amp = 0.20,  speed = 1.6, phase = 0,        joint = "top" },
	["right arm_geom"] = { motion = "swing", amp = 0.20,  speed = 1.6, phase = math.pi,  joint = "top" },
	["left leg_geom"]  = { motion = "swing", amp = 0.13,  speed = 1.6, phase = math.pi,  joint = "top" },
	["right leg_geom"] = { motion = "swing", amp = 0.13,  speed = 1.6, phase = 0,        joint = "top" },
}

-- Returns the part to be used as the rig's body, or nil to fall through to the primitive rig.
local function meshRig(ctx, template)
	local clone = template:Clone()
	-- The generator wraps every segment in its own sub-Model (`torso` holding `torso_geom`), so
	-- both this and the sweep below have to be RECURSIVE. A non-recursive lookup finds nothing,
	-- meshRig returns nil, and the boss silently falls back to the primitive rig -- which looks
	-- exactly like the mesh never having been generated.
	local torso = clone:FindFirstChild("torso_geom", true)
	if not torso then
		clone:Destroy()
		return nil
	end

	-- Scale to the height the rest of the system already assumes. `boss.size` feeds the arena, the
	-- name-plate height and the platform-clearance measurement in spawnBoss, while a generated mesh
	-- arrives at whatever size the generator felt like -- so the mesh moves, not the numbers.
	local _, tSize = clone:GetBoundingBox()
	clone:ScaleTo((ctx.u * MESH_HEIGHT_MULT) / tSize.Y)

	-- WHERE THE SOLES ARE. `origin` is a body CENTRE: the primitive rigs hang their legs below it,
	-- so the arena floor sits well beneath. Dropping a generated figure's torso straight onto
	-- origin buries it to the belly, which is exactly how the first bear came out. Measure how far
	-- the torso centre stands above the lowest point of the finished mesh, and lift the whole
	-- figure by the difference so the feet land on the floor instead.
	--
	-- `- ctx.origin.Position.Y` IS A DELIBERATE PIN TO ABSOLUTE y = MESH_GROUND_CLEAR, and it is only
	-- correct because a boss arena floor is always y = 0 (`BossStationClear` levels it, verified: the
	-- ray under Boss_Forest hits `Floor` at 0.00 and its soles sit at exactly 1.00). Everything built
	-- here is an offset the driver applies as `origin * offset`, so origin.Y goes in once with a plus
	-- and once with a minus and CANCELS -- the figure is drawn at a fixed world altitude rather than
	-- at the rig's own. The identical line in `CreatureService.meshRig` was a real bug the moment
	-- creatures started standing on terraces 30 to 107 studs up (10.14), where it left the health
	-- plate and the ground ring on the shelf and the body lying in the valley. **If a boss is ever
	-- placed on ground that is not y = 0, this line has to subtract the body's height above ITS OWN
	-- floor**, the way CreatureService now does.
	local bbCF, bbSize = clone:GetBoundingBox()
	local footDrop = torso.Position.Y - (bbCF.Position.Y - bbSize.Y * 0.5)
	local lift = CFrame.new(0, footDrop - ctx.origin.Position.Y + MESH_GROUND_CLEAR, 0)

	-- The body is an INVISIBLE ANCHOR rather than the torso itself. buildRig plants the body
	-- exactly on origin and the torso has to sit above origin by `lift`, so the torso becomes one
	-- more attachment like the limbs and the thing pinned to origin carries no geometry. It stays
	-- collidable: it is what a player walks into.
	local anchor = mk(ctx, "Body", Enum.PartType.Block,
		Vector3.new(ctx.u * 0.5, ctx.u * 0.5, ctx.u * 0.5), ctx.pal.skin, nil, 1)

	local base = torso.CFrame
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = false
			part.Parent = ctx.model
			local offset = lift * (base:Inverse() * part.CFrame)
			local spec = MESH_LIMB[part.Name]
			if spec then
				-- An arm rotated about its own middle spins; about its shoulder it swings. Put the
				-- joint at the end of the limb the body holds and hand the part back the other half
				-- as `rest`, so pivot * rest still lands on the offset measured above.
				local half = part.Size.Y * 0.5 * (spec.joint == "top" and 1 or -1)
				att(ctx, part, offset * CFrame.new(0, half, 0), CFrame.new(0, -half, 0),
					spec.motion, spec.motion == "float" and ctx.u * spec.amp or spec.amp,
					spec.speed, spec.phase)
			else
				-- the torso, and anything the generator named unexpectedly: no motion of its own,
				-- but it still has to travel with the body when the boss turns to face a player
				att(ctx, part, offset, IDENTITY, "none", 0, 1, 0)
			end
		end
	end
	clone:Destroy()

	-- SOMETHING TO WALK INTO.
	--
	-- Every part above is `CanCollide = false`, and the only solid thing was the small invisible
	-- anchor at the body centre -- so a 117-stud bear was thin air and the player stood inside it,
	-- between its legs, which is what the screenshot showed.
	--
	-- Not by making the mesh parts collidable: a generated MeshPart collides against its own
	-- triangle soup, which is expensive at this size and gives a snagging surface a player gets
	-- caught on halfway up a leg. One invisible block over the central mass instead -- the torso and
	-- the legs, not the arms, so walking under a swinging arm still works and nothing invisible
	-- blocks the approach.
	--
	-- CanQuery stays FALSE. The combat ray uses an include filter on the Bosses folder and would
	-- otherwise stop on this block rather than on `HitBox`, and the ClickDetector lives on HitBox --
	-- so a solid volume that answers rays would quietly become the thing every swing hits.
	local collide = Instance.new("Part")
	collide.Name = "BossCollision"
	-- 58% of the footprint: wide enough that you cannot slip between the legs, narrow enough that
	-- the invisible box never sticks out past the silhouette a player can see
	collide.Size = Vector3.new(bbSize.X * 0.58, bbSize.Y, bbSize.Z * 0.58)
	collide.CFrame = ctx.origin * CFrame.new(0, MESH_GROUND_CLEAR + bbSize.Y * 0.5 - ctx.origin.Position.Y, 0)
	collide.Transparency = 1
	collide.Anchored = true
	collide.CanCollide = true
	collide.CanQuery = false
	collide.CanTouch = false
	collide.CastShadow = false
	collide.Parent = ctx.model

	-- how far the silhouette reaches above the body centre -- what the name plate hangs off
	ctx.top = math.max(ctx.top, MESH_GROUND_CLEAR + bbSize.Y - ctx.origin.Position.Y)
	return anchor
end

local RIGS = {}

-- Forest / Alpha Bear -- the one boss that has to read as an ANIMAL: shoulder hump, blunt
-- muzzle, four planted paws, mass instead of glow.
function RIGS.Forest(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.74, u * 0.6, u * 1.02), pal.skin)

	local hump = mk(ctx, "Hump", Enum.PartType.Ball, Vector3.new(u * 0.7, u * 0.5, u * 0.62), pal.light)
	att(ctx, hump, CFrame.new(0, u * 0.28, -u * 0.2), IDENTITY, "float", u * 0.012, 1.2, 0)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.5, u * 0.44, u * 0.44), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.3, -u * 0.66), IDENTITY, "float", u * 0.018, 1.2, 0.3)

	local muzzle = mk(ctx, "Muzzle", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.22, u * 0.26), pal.belly)
	att(ctx, muzzle, CFrame.new(0, u * 0.24, -u * 0.86), IDENTITY, "float", u * 0.018, 1.2, 0.3)

	local nose = mk(ctx, "Nose", Enum.PartType.Ball, Vector3.new(u * 0.15, u * 0.12, u * 0.12), pal.ink)
	att(ctx, nose, CFrame.new(0, u * 0.29, -u * 0.97), IDENTITY, "float", u * 0.018, 1.2, 0.3)

	eyePair(ctx, u * 0.16, u * 0.42, -u * 0.85, u * 0.1, pal.rage, 1.2)

	pairUp(function(side)
		local ear = mk(ctx, "Ear", Enum.PartType.Ball, Vector3.new(u * 0.19, u * 0.19, u * 0.09), pal.dark)
		att(ctx, ear, CFrame.new(side * u * 0.2, u * 0.52, -u * 0.6), IDENTITY, "float", u * 0.018, 1.2, 0.3)

		local fang = mk(ctx, "Fang", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.13, u * 0.07), BONE)
		att(ctx, fang, CFrame.new(side * u * 0.1, u * 0.16, -u * 0.9), CFrame.Angles(math.rad(180), 0, 0), "float", u * 0.018, 1.2, 0.3)
	end)

	-- diagonal gait: front-left and back-right carry the same phase
	local gait = { 0, math.pi, math.pi, 0 }
	local n = 0
	for _, dz in ipairs({ -u * 0.34, u * 0.36 }) do
		for _, dx in ipairs({ -u * 0.26, u * 0.26 }) do
			n += 1
			local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.38, u * 0.24), pal.dark)
			att(ctx, leg, CFrame.new(dx, -u * 0.2, dz), CFrame.new(0, -u * 0.15, 0), "swing", 0.24, 1.9, gait[n])

			local paw = mk(ctx, "Paw", Enum.PartType.Block, Vector3.new(u * 0.26, u * 0.12, u * 0.3), pal.ink)
			att(ctx, paw, CFrame.new(dx, -u * 0.2, dz), CFrame.new(0, -u * 0.3, -u * 0.03), "swing", 0.24, 1.9, gait[n])
		end
	end

	local tail = mk(ctx, "Tail", Enum.PartType.Ball, Vector3.new(u * 0.19, u * 0.19, u * 0.19), pal.light)
	att(ctx, tail, CFrame.new(0, u * 0.14, u * 0.52), IDENTITY, "trail", 0.2, 1.6, 0)

	return body
end

-- Desert / Sand Wyrm -- a serpent caught mid-breach: the coil tapers back down into the
-- crater it burst from, hood plates fan out behind the skull, no legs anywhere.
function RIGS.Desert(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.62, u * 0.7, u * 0.62), pal.skin)

	local crater = disc(ctx, "Crater", u * 1.5, u * 0.12, pal.trim, Enum.Material.Slate)
	att(ctx, crater, CFrame.new(0, -u * 0.52, u * 0.85), DISC_FLAT, nil)

	-- each coil segment sinks further back and down than the last
	for i, seg in ipairs({ { 0.06, -0.08, 0.42, 0.56 }, { -0.1, -0.22, 0.74, 0.48 }, { -0.03, -0.36, 1.02, 0.38 }, { 0.1, -0.48, 1.26, 0.28 } }) do
		local coil = mk(ctx, "Coil", Enum.PartType.Ball, Vector3.new(u * seg[4], u * seg[4], u * seg[4] * 1.25), pal.light)
		att(ctx, coil, CFrame.new(u * seg[1], u * seg[2], u * seg[3]), IDENTITY, "float", u * 0.02, 1.3, i * 0.7)
	end

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.46, u * 0.34, u * 0.62), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.44, -u * 0.4), IDENTITY, "float", u * 0.025, 1.3, 0)

	local jaw = mk(ctx, "Jaw", Enum.PartType.Block, Vector3.new(u * 0.4, u * 0.16, u * 0.52), pal.dark)
	att(ctx, jaw, CFrame.new(0, u * 0.44, -u * 0.4), CFrame.new(0, -u * 0.24, -u * 0.06) * CFrame.Angles(math.rad(13), 0, 0), "swing", 0.11, 1.1, 0)

	eyePair(ctx, u * 0.17, u * 0.55, -u * 0.6, u * 0.11, pal.rage, 1.3)

	pairUp(function(side)
		local hood = mk(ctx, "Hood", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.52, u * 0.46), pal.belly)
		att(ctx, hood, CFrame.new(side * u * 0.22, u * 0.46, -u * 0.2),
			CFrame.Angles(0, math.rad(180), math.rad(side * 44)) * CFrame.new(0, u * 0.24, 0), "flap", 0.14, 1.4, side > 0 and 0 or math.pi)

		local fang = mk(ctx, "Fang", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.21, u * 0.08), BONE)
		att(ctx, fang, CFrame.new(side * u * 0.13, u * 0.32, -u * 0.66), CFrame.Angles(math.rad(180), 0, 0), "float", u * 0.025, 1.3, 0)
	end)

	-- ridge plates running from the skull down the coil
	for i, seg in ipairs({ { -0.05, 0.34 }, { 0.26, 0.26 }, { 0.58, 0.18 } }) do
		local plate = mk(ctx, "Plate", Enum.PartType.Wedge, Vector3.new(u * 0.08, u * seg[2], u * 0.34), pal.dark, Enum.Material.Slate)
		att(ctx, plate, CFrame.new(0, u * (0.32 - i * 0.11), u * seg[1]),
			CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, u * seg[2] * 0.5, 0), "float", u * 0.02, 1.3, i * 0.7)
	end

	ctx.top = u * 1.0
	return body
end

-- Ocean / Kraken -- mantle over a beak, eight tentacles splayed out and curling back up.
-- The tentacle ring IS the silhouette, so every arm gets two parts.
function RIGS.Ocean(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.72, u * 0.64, u * 0.78), pal.skin)

	local mantle = mk(ctx, "Mantle", Enum.PartType.Ball, Vector3.new(u * 0.52, u * 0.62, u * 0.72), pal.light)
	att(ctx, mantle, CFrame.new(0, u * 0.32, u * 0.14), CFrame.Angles(math.rad(-16), 0, 0), "float", u * 0.02, 1.1, 0)

	local head = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.6, u * 0.42, u * 0.5), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.06, -u * 0.32), IDENTITY, "float", u * 0.022, 1.1, 0.4)

	pairUp(function(side)
		local white = mk(ctx, "EyeBall", Enum.PartType.Ball, Vector3.new(u * 0.24, u * 0.24, u * 0.24), pal.belly)
		att(ctx, white, CFrame.new(side * u * 0.24, u * 0.12, -u * 0.4), IDENTITY, "float", u * 0.022, 1.1, 0.4)

		-- slit pupil, sitting proud of the eyeball so it stays visible from the side
		local pupil = mk(ctx, "Eye", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.17, u * 0.05), pal.rage, Enum.Material.Neon)
		att(ctx, pupil, CFrame.new(side * u * 0.27, u * 0.12, -u * 0.5), IDENTITY, "float", u * 0.022, 1.1, 0.4)
	end)

	-- upper and lower half of the beak, snapping on the same clock
	for _, dir in ipairs(SIDES) do
		local beak = mk(ctx, "Beak", Enum.PartType.Wedge, Vector3.new(u * 0.18, u * 0.2, u * 0.22), pal.ink)
		att(ctx, beak, CFrame.new(0, -u * 0.12, -u * 0.44),
			CFrame.new(0, dir * u * 0.09, 0) * CFrame.Angles(dir > 0 and math.rad(180) or 0, 0, 0), "swing", 0.1, 1.4, dir > 0 and 0 or math.pi)
	end

	ringOf(ctx, 8, u * 0.32, -u * 0.3, function(i, _, joint)
		local arm = mk(ctx, "Tentacle", Enum.PartType.Block, Vector3.new(u * 0.16, u * 0.46, u * 0.16), pal.light)
		att(ctx, arm, joint, CFrame.Angles(0, 0, math.rad(-118)) * CFrame.new(0, u * 0.23, 0), "trail", 0.2, 1.4 + i * 0.06, i * 0.75)

		local tip = mk(ctx, "TentacleTip", Enum.PartType.Block, Vector3.new(u * 0.1, u * 0.34, u * 0.1), pal.belly)
		att(ctx, tip, joint,
			CFrame.Angles(0, 0, math.rad(-118)) * CFrame.new(0, u * 0.46, 0) * CFrame.Angles(0, 0, math.rad(62)) * CFrame.new(0, u * 0.17, 0),
			"trail", 0.2, 1.4 + i * 0.06, i * 0.75)
	end)

	return body
end

-- Volcano / Magma Titan -- slate boulder-golem, Neon cracks bleeding through the seams,
-- knuckles planted on the ground, a caldera venting off its back.
function RIGS.Volcano(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.86, u * 0.66, u * 0.62), pal.dark, Enum.Material.Slate)

	for i, row in ipairs({ { 0.17, 11 }, { 0.0, -8 }, { -0.17, 13 } }) do
		local crack = mk(ctx, "Crack", Enum.PartType.Block, Vector3.new(u * (0.62 - i * 0.07), u * 0.07, u * 0.04), pal.glow, Enum.Material.Neon)
		att(ctx, crack, CFrame.new(0, u * row[1], -u * 0.32), CFrame.Angles(0, 0, math.rad(row[2])), "float", u * 0.008, 2.4, i)
	end

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.4, u * 0.3, u * 0.36), pal.dark, Enum.Material.Slate)
	att(ctx, head, CFrame.new(0, u * 0.44, -u * 0.08), IDENTITY, "float", u * 0.014, 1.2, 0.5)

	eyePair(ctx, u * 0.12, u * 0.46, -u * 0.26, u * 0.12, pal.glow, 1.2)

	pairUp(function(side)
		local boulder = mk(ctx, "Shoulder", Enum.PartType.Ball, Vector3.new(u * 0.46, u * 0.44, u * 0.44), pal.skin, Enum.Material.Slate)
		att(ctx, boulder, CFrame.new(side * u * 0.46, u * 0.3, 0), IDENTITY, "float", u * 0.012, 1.2, side > 0 and 0 or 1.6)

		local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.26, u * 0.5, u * 0.26), pal.skin, Enum.Material.Slate)
		att(ctx, arm, CFrame.new(side * u * 0.5, u * 0.2, 0), CFrame.new(0, -u * 0.25, 0), "swing", 0.3, 1.5, side > 0 and 0 or math.pi)

		local fist = mk(ctx, "Fist", Enum.PartType.Block, Vector3.new(u * 0.32, u * 0.28, u * 0.32), pal.dark, Enum.Material.Slate)
		att(ctx, fist, CFrame.new(side * u * 0.5, u * 0.2, 0), CFrame.new(0, -u * 0.58, 0), "swing", 0.3, 1.5, side > 0 and 0 or math.pi)

		local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.3, u * 0.32), pal.skin, Enum.Material.Slate)
		att(ctx, leg, CFrame.new(side * u * 0.24, -u * 0.32, 0), CFrame.new(0, -u * 0.08, 0), "swing", 0.12, 1.5, side > 0 and math.pi or 0)

		local vein = mk(ctx, "Crack", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.3, u * 0.04), pal.glow, Enum.Material.Neon)
		att(ctx, vein, CFrame.new(side * u * 0.5, u * 0.2, -u * 0.14), CFrame.new(0, -u * 0.26, 0), "swing", 0.3, 1.5, side > 0 and 0 or math.pi)
	end)

	local vent = disc(ctx, "Vent", u * 0.36, u * 0.12, pal.ink, Enum.Material.Slate)
	att(ctx, vent, CFrame.new(0, u * 0.36, u * 0.18), DISC_FLAT, "float", u * 0.01, 1.2, 0)

	local plume = mk(ctx, "Plume", Enum.PartType.Ball, Vector3.new(u * 0.3, u * 0.4, u * 0.3), pal.glow, Enum.Material.Neon, 0.4)
	att(ctx, plume, CFrame.new(0, u * 0.5, u * 0.18), IDENTITY, "float", u * 0.05, 1.0, 0)

	return body
end

-- Moon / Lunar Colossus -- a pale statue that stands a head taller than anything before it:
-- cratered chest, crescent visor faked from two overlapping discs, rubble in orbit.
function RIGS.Moon(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.6, u * 0.72, u * 0.44), pal.light, Enum.Material.Slate)

	for i, spot in ipairs({ { -0.16, 0.2, 0.2 }, { 0.18, 0.06, 0.16 }, { -0.04, -0.16, 0.24 } }) do
		local crater = disc(ctx, "Crater", u * spot[3], u * 0.05, pal.dark, Enum.Material.Slate)
		att(ctx, crater, CFrame.new(u * spot[1], u * spot[2], -u * 0.23), DISC_FACE, "float", u * 0.006, 1.1, i)
	end

	local neck = mk(ctx, "Neck", Enum.PartType.Block, Vector3.new(u * 0.2, u * 0.14, u * 0.2), pal.dark, Enum.Material.Slate)
	att(ctx, neck, CFrame.new(0, u * 0.44, 0), IDENTITY, "float", u * 0.012, 1.0, 0.2)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.38, u * 0.32, u * 0.34), pal.light, Enum.Material.Slate)
	att(ctx, head, CFrame.new(0, u * 0.64, 0), IDENTITY, "float", u * 0.016, 1.0, 0.2)

	-- crescent: a glowing disc with a dark one eclipsing most of it
	local moonEye = disc(ctx, "Visor", u * 0.26, u * 0.05, pal.glow, Enum.Material.Neon)
	att(ctx, moonEye, CFrame.new(0, u * 0.64, -u * 0.18), DISC_FACE, "float", u * 0.016, 1.0, 0.2)

	local eclipse = disc(ctx, "Eclipse", u * 0.22, u * 0.05, pal.dark, Enum.Material.Slate)
	att(ctx, eclipse, CFrame.new(u * 0.07, u * 0.66, -u * 0.2), DISC_FACE, "float", u * 0.016, 1.0, 0.2)

	pairUp(function(side)
		local horn = mk(ctx, "Horn", Enum.PartType.Wedge, Vector3.new(u * 0.09, u * 0.34, u * 0.14), pal.dark, Enum.Material.Slate)
		att(ctx, horn, CFrame.new(side * u * 0.16, u * 0.78, 0), CFrame.Angles(math.rad(-16), 0, math.rad(side * 26)) * CFrame.new(0, u * 0.16, 0), "float", u * 0.016, 1.0, 0.2)

		local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.17, u * 0.46, u * 0.19), pal.light, Enum.Material.Slate)
		att(ctx, arm, CFrame.new(side * u * 0.38, u * 0.24, 0), CFrame.new(0, -u * 0.23, 0), "swing", 0.26, 1.2, side > 0 and 0 or math.pi)

		local hand = mk(ctx, "Hand", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.2, u * 0.22), pal.dark, Enum.Material.Slate)
		att(ctx, hand, CFrame.new(side * u * 0.38, u * 0.24, 0), CFrame.new(0, -u * 0.56, 0), "swing", 0.26, 1.2, side > 0 and 0 or math.pi)
	end)

	limbPair(ctx, "Leg", Vector3.new(u * 0.22, u * 0.3, u * 0.24), Vector3.new(u * 0.19, -u * 0.28, 0), u * 0.12, pal.light, Enum.Material.Slate, 0, 0.12, 1.2)
	limbPair(ctx, "Foot", Vector3.new(u * 0.26, u * 0.1, u * 0.32), Vector3.new(u * 0.19, -u * 0.28, -u * 0.03), u * 0.24, pal.dark, Enum.Material.Slate, 0, 0.12, 1.2)

	-- rubble caught in its gravity well
	for i = 1, 5 do
		local rock = mk(ctx, "Rubble", Enum.PartType.Block, Vector3.new(u * 0.12, u * 0.1, u * 0.12), pal.trim, Enum.Material.Slate)
		att(ctx, rock, IDENTITY,
			CFrame.new(u * 0.72, u * (0.1 + (i % 3) * 0.18), 0) * CFrame.Angles(math.rad(i * 24), 0, math.rad(i * 17)),
			"orbit", 0, (i % 2 == 0) and 0.5 or -0.4, (i - 1) * (math.pi * 2 / 5))
	end

	ctx.top = u * 1.15
	return body
end

-- Mars / War Golem -- a siege machine, not a creature: armour slab, exhaust stacks, piston
-- legs planted wide, and one fist / one shoulder cannon so the silhouette is asymmetric.
function RIGS.Mars(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.8, u * 0.6, u * 0.5), pal.metal, Enum.Material.Metal)

	local plate = mk(ctx, "ChestPlate", Enum.PartType.Block, Vector3.new(u * 0.62, u * 0.44, u * 0.1), pal.dark, Enum.Material.Metal)
	att(ctx, plate, CFrame.new(0, u * 0.06, -u * 0.28), IDENTITY, "float", u * 0.008, 1.6, 0)

	local reactor = mk(ctx, "Reactor", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.08, u * 0.06), pal.rage, Enum.Material.Neon)
	att(ctx, reactor, CFrame.new(0, u * 0.1, -u * 0.34), IDENTITY, "float", u * 0.01, 2.6, 0)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.34, u * 0.24, u * 0.3), pal.dark, Enum.Material.Metal)
	att(ctx, head, CFrame.new(0, u * 0.44, -u * 0.04), IDENTITY, "float", u * 0.012, 1.6, 0.4)

	local visor = mk(ctx, "Visor", Enum.PartType.Block, Vector3.new(u * 0.28, u * 0.07, u * 0.05), pal.rage, Enum.Material.Neon)
	att(ctx, visor, CFrame.new(0, u * 0.45, -u * 0.2), IDENTITY, "float", u * 0.012, 1.6, 0.4)

	pairUp(function(side)
		local pauldron = mk(ctx, "Pauldron", Enum.PartType.Block, Vector3.new(u * 0.24, u * 0.22, u * 0.34), pal.trim, Enum.Material.Metal)
		att(ctx, pauldron, CFrame.new(side * u * 0.46, u * 0.26, 0), IDENTITY, "float", u * 0.01, 1.6, 0.2)

		local stack = mk(ctx, "Stack", Enum.PartType.Cylinder, Vector3.new(u * 0.3, u * 0.12, u * 0.12), pal.dark, Enum.Material.Metal)
		att(ctx, stack, CFrame.new(side * u * 0.2, u * 0.3, u * 0.22), CFrame.new(0, u * 0.15, 0) * DISC_FLAT, "float", u * 0.012, 1.6, 0.2)

		local exhaust = mk(ctx, "Exhaust", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.13, u * 0.13), pal.glow, Enum.Material.Neon, 0.45)
		att(ctx, exhaust, CFrame.new(side * u * 0.2, u * 0.48, u * 0.22), IDENTITY, "float", u * 0.05, 1.1, side > 0 and 0 or 1.4)
	end)

	limbPair(ctx, "Leg", Vector3.new(u * 0.24, u * 0.3, u * 0.26), Vector3.new(u * 0.24, -u * 0.3, 0), u * 0.12, pal.metal, Enum.Material.Metal, 0, 0.14, 1.6)
	limbPair(ctx, "Foot", Vector3.new(u * 0.3, u * 0.12, u * 0.38), Vector3.new(u * 0.24, -u * 0.3, -u * 0.04), u * 0.2, pal.dark, Enum.Material.Metal, 0, 0.14, 1.6)

	-- left arm: piston and wrecking fist
	local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.2, u * 0.42, u * 0.2), pal.metal, Enum.Material.Metal)
	att(ctx, arm, CFrame.new(-u * 0.46, u * 0.14, 0), CFrame.new(0, -u * 0.21, 0), "swing", 0.28, 1.6, 0)

	local fist = mk(ctx, "Fist", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.26, u * 0.3), pal.trim, Enum.Material.Metal)
	att(ctx, fist, CFrame.new(-u * 0.46, u * 0.14, 0), CFrame.new(0, -u * 0.52, 0), "swing", 0.28, 1.6, 0)

	-- right arm: the cannon, held level and barely moving
	local mount = mk(ctx, "CannonMount", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.26, u * 0.26), pal.metal, Enum.Material.Metal)
	att(ctx, mount, CFrame.new(u * 0.46, u * 0.14, 0), CFrame.new(0, -u * 0.16, 0), "swing", 0.1, 1.6, math.pi)

	local barrel = mk(ctx, "Barrel", Enum.PartType.Cylinder, Vector3.new(u * 0.6, u * 0.24, u * 0.24), pal.dark, Enum.Material.Metal)
	att(ctx, barrel, CFrame.new(u * 0.46, u * 0.14, 0), CFrame.new(0, -u * 0.18, -u * 0.34) * DISC_FACE, "swing", 0.1, 1.6, math.pi)

	local muzzle = disc(ctx, "Muzzle", u * 0.2, u * 0.06, pal.rage, Enum.Material.Neon)
	att(ctx, muzzle, CFrame.new(u * 0.46, u * 0.14, 0), CFrame.new(0, -u * 0.18, -u * 0.65) * DISC_FACE, "swing", 0.1, 1.6, math.pi)

	return body
end

-- Galaxy / Nebula Wraith -- the first boss with no ground contact at all: a hollow cowl
-- over a burning core, a shroud that frays into six trailing shreds, stars in orbit.
function RIGS.Galaxy(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.66, u * 0.72, u * 0.66), pal.skin, Enum.Material.SmoothPlastic, 0.35)

	local cowl = mk(ctx, "Cowl", Enum.PartType.Ball, Vector3.new(u * 0.56, u * 0.56, u * 0.56), pal.dark, Enum.Material.SmoothPlastic, 0.1)
	att(ctx, cowl, CFrame.new(0, u * 0.34, u * 0.02), IDENTITY, "float", u * 0.04, 1.1, 0)

	local hollow = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.34, u * 0.34, u * 0.34), pal.ink)
	att(ctx, hollow, CFrame.new(0, u * 0.32, -u * 0.16), IDENTITY, "float", u * 0.04, 1.1, 0)

	eyePair(ctx, u * 0.1, u * 0.34, -u * 0.3, u * 0.11, pal.glow, 1.1)

	local core = mk(ctx, "Core", Enum.PartType.Ball, Vector3.new(u * 0.28, u * 0.28, u * 0.28), pal.glow, Enum.Material.Neon)
	att(ctx, core, IDENTITY, IDENTITY, "float", u * 0.05, 0.9, 1.2)

	pairUp(function(side)
		local sleeve = mk(ctx, "Sleeve", Enum.PartType.Block, Vector3.new(u * 0.16, u * 0.42, u * 0.18), pal.skin, Enum.Material.SmoothPlastic, 0.25)
		att(ctx, sleeve, CFrame.new(side * u * 0.36, u * 0.16, 0), CFrame.Angles(0, 0, math.rad(side * 14)) * CFrame.new(0, -u * 0.21, 0), "swing", 0.32, 1.3, side > 0 and 0 or math.pi)

		local claw = mk(ctx, "Claw", Enum.PartType.Wedge, Vector3.new(u * 0.08, u * 0.2, u * 0.1), pal.glow, Enum.Material.Neon)
		att(ctx, claw, CFrame.new(side * u * 0.36, u * 0.16, 0), CFrame.Angles(0, 0, math.rad(side * 14)) * CFrame.new(0, -u * 0.5, 0), "swing", 0.32, 1.3, side > 0 and 0 or math.pi)
	end)

	-- the shroud frays: six shreds hanging where legs would be
	ringOf(ctx, 6, u * 0.22, -u * 0.22, function(i, _, joint)
		local shred = mk(ctx, "Shred", Enum.PartType.Block, Vector3.new(u * 0.12, u * 0.46, u * 0.12), pal.skin, Enum.Material.SmoothPlastic, 0.3 + (i % 3) * 0.1)
		att(ctx, shred, joint, CFrame.new(0, -u * 0.23, 0), "trail", 0.4, 1.2 + i * 0.09, i * 0.9)
	end)

	for i = 1, 5 do
		local star = mk(ctx, "Star", Enum.PartType.Wedge, Vector3.new(u * 0.1, u * 0.2, u * 0.1), pal.belly, Enum.Material.Neon)
		att(ctx, star, IDENTITY,
			CFrame.new(u * 0.66, u * (0.36 - (i % 3) * 0.24), 0) * CFrame.Angles(0, 0, math.rad(i * 33)),
			"orbit", 0, (i % 2 == 0) and 0.8 or -0.6, (i - 1) * (math.pi * 2 / 5))
	end

	ctx.top = u * 0.95
	return body
end

-- BlackHole / Void Devourer -- barely a creature: a pitch-black sphere with a lit accretion
-- ring cutting through it and a fanged maw opened straight at the player.
function RIGS.BlackHole(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.78, u * 0.78, u * 0.78), pal.ink)

	local ring = disc(ctx, "Accretion", u * 1.5, u * 0.06, pal.glow, Enum.Material.Neon, 0.25)
	att(ctx, ring, IDENTITY, CFrame.Angles(math.rad(-14), 0, math.rad(9)) * DISC_FLAT, "orbit", 0, 0.5, 0)

	-- the disc is dust, not a solid plate: chunks riding the same orbit sell the spin
	ringOf(ctx, 10, u * 0.68, 0, function(i, _, joint)
		local chunk = mk(ctx, "Dust", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.07, u * 0.2), pal.belly, Enum.Material.Neon, 0.15)
		att(ctx, chunk, IDENTITY,
			CFrame.Angles(math.rad(-14), 0, math.rad(9)) * joint * CFrame.Angles(0, 0, math.rad((i % 2 == 0) and 12 or -12)),
			"orbit", 0, 0.5, 0)
	end)

	local throat = disc(ctx, "Throat", u * 0.46, u * 0.08, pal.rage, Enum.Material.Neon)
	att(ctx, throat, CFrame.new(0, u * 0.04, -u * 0.36), DISC_FACE, "float", u * 0.01, 1.6, 0)

	-- fangs stood around the maw in the XY plane, all leaning into the throat
	for i = 1, 9 do
		local a = (i - 1) * (math.pi * 2 / 9)
		local fang = mk(ctx, "Tooth", Enum.PartType.Wedge, Vector3.new(u * 0.08, u * 0.22, u * 0.09), BONE)
		att(ctx, fang, CFrame.new(0, u * 0.04, -u * 0.34),
			CFrame.Angles(0, 0, -a) * CFrame.new(0, u * 0.3, 0) * CFrame.Angles(0, 0, math.rad(180)) * CFrame.new(0, u * 0.11, -u * 0.04),
			"pulse", u * 0.012, 1.6, i * 0.5)
	end

	eyePair(ctx, u * 0.2, u * 0.38, -u * 0.3, u * 0.12, pal.rage, 1.4)

	-- gravity spikes: everything nearby is being pulled in and stretched
	for i = 1, 4 do
		local a = (i - 1) * (math.pi * 0.5) + math.pi * 0.25
		local spike = mk(ctx, "Spire", Enum.PartType.Block, Vector3.new(u * 0.06, u * 0.06, u * 0.7), pal.trim, Enum.Material.Neon, 0.4)
		att(ctx, spike, IDENTITY, CFrame.Angles(0, -a, 0) * CFrame.new(0, u * 0.34, u * 0.62) * CFrame.Angles(math.rad(24), 0, 0), "orbit", 0, -0.3, 0)
	end

	ctx.top = u * 0.9
	return body
end

-- Multiverse / Multiverse Sovereign -- the first boss that is openly royalty: four arms, a
-- shard crown, two counter-spinning haloes and a robe that never touches the floor.
function RIGS.Multiverse(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.5, u * 0.56, u * 0.36), pal.skin, Enum.Material.Metal)

	local sigil = disc(ctx, "Sigil", u * 0.26, u * 0.06, pal.glow, Enum.Material.Neon)
	att(ctx, sigil, CFrame.new(0, u * 0.1, -u * 0.2), DISC_FACE, "float", u * 0.012, 1.4, 0)

	-- robe: two tapering blocks instead of legs
	for i, seg in ipairs({ { 0.42, 0.5, -0.28 }, { 0.28, 0.42, -0.5 } }) do
		local robe = mk(ctx, "Robe", Enum.PartType.Block, Vector3.new(u * seg[1], u * 0.3, u * seg[2] * 0.62), pal.dark, Enum.Material.SmoothPlastic, 0.1)
		att(ctx, robe, CFrame.new(0, u * seg[3], 0), IDENTITY, "float", u * 0.018, 1.0, i * 0.6)
	end

	local cape = mk(ctx, "Cape", Enum.PartType.Wedge, Vector3.new(u * 0.66, u * 0.9, u * 0.16), pal.trim, Enum.Material.SmoothPlastic, 0.08)
	att(ctx, cape, CFrame.new(0, u * 0.1, u * 0.24), CFrame.Angles(0, math.rad(180), 0), "flap", 0.1, 0.9, 0)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.28, u * 0.3, u * 0.28), pal.light, Enum.Material.Metal)
	att(ctx, head, CFrame.new(0, u * 0.48, 0), IDENTITY, "float", u * 0.014, 1.2, 0.3)

	eyePair(ctx, u * 0.08, u * 0.5, -u * 0.16, u * 0.08, pal.glow, 1.2)

	local thirdEye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.09, u * 0.09, u * 0.09), pal.rage, Enum.Material.Neon)
	att(ctx, thirdEye, CFrame.new(0, u * 0.6, -u * 0.15), IDENTITY, "float", u * 0.014, 1.2, 0.3)

	crownOf(ctx, 6, u * 0.17, u * 0.66, u * 0.26, pal.gold)

	-- two pairs of arms, the lower pair holding wider
	for _, set in ipairs({ { 0.26, 0.3, 0.34, 0 }, { 0.06, 0.42, 0.28, math.pi * 0.5 } }) do
		pairUp(function(side)
			local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.13, u * set[3], u * 0.15), pal.skin, Enum.Material.Metal)
			att(ctx, arm, CFrame.new(side * u * set[2], u * set[1], 0),
				CFrame.Angles(0, 0, math.rad(side * 22)) * CFrame.new(0, -u * set[3] * 0.5, 0), "swing", 0.24, 1.1, set[4] + (side > 0 and 0 or math.pi))

			local hand = mk(ctx, "Hand", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.13, u * 0.13), pal.glow, Enum.Material.Neon)
			att(ctx, hand, CFrame.new(side * u * set[2], u * set[1], 0),
				CFrame.Angles(0, 0, math.rad(side * 22)) * CFrame.new(0, -u * set[3] - u * 0.06, 0), "swing", 0.24, 1.1, set[4] + (side > 0 and 0 or math.pi))
		end)
	end

	for i, halo in ipairs({ { 1.1, 0.14, 0.4 }, { 0.86, -0.1, -0.55 } }) do
		local band = disc(ctx, "Halo", u * halo[1], u * 0.05, pal.gold, Enum.Material.Neon, 0.2)
		att(ctx, band, IDENTITY, CFrame.Angles(math.rad(i == 1 and 18 or -24), 0, math.rad(i == 1 and -12 or 16)) * CFrame.new(0, u * halo[2], 0) * DISC_FLAT, "orbit", 0, halo[3], 0)
	end

	ctx.top = u * 1.0
	return body
end

-- Nebula / Nebula Devourer -- the soft counterpart to the Void Devourer: layered gas shells
-- instead of a solid body, comet debris falling in, and far too many small eyes.
function RIGS.Nebula(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.62, u * 0.62, u * 0.62), pal.skin, Enum.Material.Neon, 0.15)

	for i, shell in ipairs({ { 0.86, 0.55 }, { 1.08, 0.72 }, { 1.28, 0.84 } }) do
		local gas = mk(ctx, "Shell", Enum.PartType.Ball, Vector3.new(u * shell[1], u * shell[1] * 0.86, u * shell[1]), pal.belly, Enum.Material.SmoothPlastic, shell[2])
		att(ctx, gas, IDENTITY, IDENTITY, "float", u * (0.02 + i * 0.012), 0.7 + i * 0.15, i * 1.1)
	end

	local maw = disc(ctx, "Maw", u * 0.62, u * 0.1, pal.rage, Enum.Material.Neon)
	att(ctx, maw, CFrame.new(0, -u * 0.02, -u * 0.34), DISC_FACE, "float", u * 0.02, 1.2, 0)

	for i = 1, 10 do
		local a = (i - 1) * (math.pi * 2 / 10)
		local tooth = mk(ctx, "Tooth", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.24, u * 0.08), pal.light)
		att(ctx, tooth, CFrame.new(0, -u * 0.02, -u * 0.32),
			CFrame.Angles(0, 0, -a) * CFrame.new(0, u * 0.36, 0) * CFrame.Angles(0, 0, math.rad(180)) * CFrame.new(0, u * 0.12, -u * 0.03),
			"pulse", u * 0.016, 1.2, i * 0.5)
	end

	-- a cluster of eyes scattered over the upper shells, no two the same height
	for i, spot in ipairs({ { -0.26, 0.3, 0.11 }, { 0.2, 0.38, 0.09 }, { -0.06, 0.5, 0.13 }, { 0.32, 0.16, 0.08 }, { -0.36, 0.1, 0.1 } }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * spot[3], u * spot[3], u * spot[3]), pal.rage, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(u * spot[1], u * spot[2], -u * 0.34), IDENTITY, "float", u * 0.03, 0.9 + i * 0.1, i * 0.7)
	end

	-- comet debris spiralling in toward the maw
	for i = 1, 8 do
		local comet = mk(ctx, "Comet", Enum.PartType.Block, Vector3.new(u * 0.07, u * 0.07, u * 0.42), pal.glow, Enum.Material.Neon, 0.3)
		att(ctx, comet, IDENTITY,
			CFrame.new(u * (0.8 + (i % 3) * 0.1), u * (0.32 - (i % 4) * 0.2), 0) * CFrame.Angles(0, math.rad(58), math.rad(i * 21)),
			"orbit", 0, (i % 2 == 0) and 0.75 or -0.55, (i - 1) * (math.pi * 2 / 8))
	end

	ctx.top = u * 0.95
	return body
end

-- Wormhole / Wormhole Horror -- a lamprey leaning out of the hole it lives in: the portal
-- ring stands on the ground behind it, the neck arcs forward, the mouth is a sucker of rings.
function RIGS.Wormhole(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.44, u * 0.44, u * 0.5), pal.skin)

	local portal = disc(ctx, "Portal", u * 1.06, u * 0.1, pal.ink, Enum.Material.Neon, 0.12)
	att(ctx, portal, CFrame.new(0, 0, u * 0.32), DISC_FACE, nil)

	-- the ring stands in the XY plane, so it is built by hand rather than by ringOf
	for i = 1, 12 do
		local a = (i - 1) * (math.pi * 2 / 12)
		local slab = mk(ctx, "RingSlab", Enum.PartType.Block, Vector3.new(u * 0.15, u * 0.26, u * 0.18), pal.trim, Enum.Material.Slate)
		att(ctx, slab, CFrame.new(0, 0, u * 0.34), CFrame.Angles(0, 0, -a) * CFrame.new(0, u * 0.55, 0), "pulse", u * 0.014, 1.0, i * 0.5)
	end

	local glow = disc(ctx, "PortalGlow", u * 0.94, u * 0.05, pal.glow, Enum.Material.Neon, 0.45)
	att(ctx, glow, CFrame.new(0, 0, u * 0.28), DISC_FACE, "float", u * 0.014, 1.0, 0)

	-- neck arcing out of the portal toward whoever is standing there
	for i, seg in ipairs({ { 0.06, 0.44, 0.4 }, { 0.14, 0.1, 0.36 }, { 0.1, -0.26, 0.32 } }) do
		local neck = mk(ctx, "Neck", Enum.PartType.Ball, Vector3.new(u * seg[3], u * seg[3], u * seg[3] * 1.3), pal.light)
		att(ctx, neck, CFrame.new(0, u * seg[1], u * seg[2]), IDENTITY, "trail", 0.14, 1.2, i * 0.8)
	end

	local head = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.4, u * 0.4, u * 0.42), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.04, -u * 0.58), IDENTITY, "trail", 0.14, 1.2, 3.2)

	local mouth = disc(ctx, "Mouth", u * 0.34, u * 0.08, pal.rage, Enum.Material.Neon)
	att(ctx, mouth, CFrame.new(0, u * 0.04, -u * 0.76), DISC_FACE, "float", u * 0.012, 1.8, 0)

	-- two concentric rings of rasping teeth around the sucker
	for _, ring in ipairs({ { 8, 0.24, 0.16 }, { 6, 0.13, 0.11 } }) do
		for i = 1, ring[1] do
			local a = (i - 1) * (math.pi * 2 / ring[1])
			local tooth = mk(ctx, "Tooth", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * ring[3], u * 0.07), BONE)
			att(ctx, tooth, CFrame.new(0, u * 0.04, -u * 0.74),
				CFrame.Angles(0, 0, -a) * CFrame.new(0, u * ring[2], 0) * CFrame.Angles(0, 0, math.rad(180)) * CFrame.new(0, u * ring[3] * 0.5, -u * 0.03),
				"pulse", u * 0.012, 1.8, i * 0.6)
		end
	end

	eyePair(ctx, u * 0.15, u * 0.2, -u * 0.62, u * 0.09, pal.glow, 1.6)

	-- grasping tendrils hauling it out of the hole
	ringOf(ctx, 4, u * 0.5, -u * 0.06, function(i, _, joint)
		local tendril = mk(ctx, "Tendril", Enum.PartType.Block, Vector3.new(u * 0.09, u * 0.44, u * 0.09), pal.dark)
		att(ctx, tendril, joint, CFrame.Angles(0, 0, math.rad(-128)) * CFrame.new(0, u * 0.22, 0), "trail", 0.34, 1.1 + i * 0.12, i * 1.1)
	end)

	return body
end

-- QuantumRealm / Quantum Phantom -- one body that cannot decide where it is: two fainter
-- copies of itself drift beside the real one, electron shells tilt through the lot.
function RIGS.QuantumRealm(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.46, u * 0.56, u * 0.32), pal.skin, Enum.Material.SmoothPlastic, 0.25)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.28, u * 0.28), pal.light, Enum.Material.SmoothPlastic, 0.2)
	att(ctx, head, CFrame.new(0, u * 0.46, 0), IDENTITY, "float", u * 0.02, 1.5, 0.3)

	local visor = mk(ctx, "Visor", Enum.PartType.Block, Vector3.new(u * 0.24, u * 0.07, u * 0.05), pal.glow, Enum.Material.Neon)
	att(ctx, visor, CFrame.new(0, u * 0.47, -u * 0.16), IDENTITY, "float", u * 0.02, 1.5, 0.3)

	eyePair(ctx, u * 0.07, u * 0.47, -u * 0.18, u * 0.06, pal.rage, 1.5)

	local nucleus = mk(ctx, "Nucleus", Enum.PartType.Ball, Vector3.new(u * 0.26, u * 0.26, u * 0.26), pal.glow, Enum.Material.Neon)
	att(ctx, nucleus, IDENTITY, IDENTITY, "float", u * 0.03, 1.9, 0)

	pairUp(function(side)
		local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.12, u * 0.4, u * 0.14), pal.skin, Enum.Material.SmoothPlastic, 0.25)
		att(ctx, arm, CFrame.new(side * u * 0.3, u * 0.2, 0), CFrame.Angles(0, 0, math.rad(side * 18)) * CFrame.new(0, -u * 0.2, 0), "swing", 0.3, 1.7, side > 0 and 0 or math.pi)

		local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.34, u * 0.16), pal.dark, Enum.Material.SmoothPlastic, 0.25)
		att(ctx, leg, CFrame.new(side * u * 0.15, -u * 0.26, 0), CFrame.new(0, -u * 0.14, 0), "swing", 0.22, 1.7, side > 0 and math.pi or 0)

		-- the phase echoes: the same silhouette, half faded, sliding in and out of phase
		local echo = mk(ctx, "Echo", Enum.PartType.Block, Vector3.new(u * 0.44, u * 0.54, u * 0.3), pal.belly, Enum.Material.Neon, 0.82)
		att(ctx, echo, CFrame.new(side * u * 0.3, 0, u * 0.06), IDENTITY, "float", u * 0.09, 0.8, side > 0 and 0 or math.pi)

		local echoHead = mk(ctx, "EchoHead", Enum.PartType.Block, Vector3.new(u * 0.28, u * 0.26, u * 0.26), pal.belly, Enum.Material.Neon, 0.82)
		att(ctx, echoHead, CFrame.new(side * u * 0.3, u * 0.44, u * 0.06), IDENTITY, "float", u * 0.09, 0.8, side > 0 and 0 or math.pi)
	end)

	for i, shell in ipairs({ { 1.2, 22, -16, 0.9 }, { 1.0, -34, 28, -0.7 }, { 0.8, 8, 74, 1.2 } }) do
		local orbitRing = disc(ctx, "Shell", u * shell[1], u * 0.04, pal.glow, Enum.Material.Neon, 0.35)
		att(ctx, orbitRing, IDENTITY, CFrame.Angles(math.rad(shell[2]), 0, math.rad(shell[3])) * DISC_FLAT, "orbit", 0, shell[4], i)

		local electron = mk(ctx, "Electron", Enum.PartType.Ball, Vector3.new(u * 0.1, u * 0.1, u * 0.1), pal.rage, Enum.Material.Neon)
		att(ctx, electron, IDENTITY, CFrame.Angles(math.rad(shell[2]), 0, math.rad(shell[3])) * CFrame.new(u * shell[1] * 0.5, 0, 0), "orbit", 0, shell[4] * 1.6, i * 2)
	end

	ctx.top = u * 0.95
	return body
end

-- TimeRift / Chronos Beast -- a ram-shouldered brute wearing a clock: spiral horns, an
-- hourglass burning over its spine, sand bleeding out of it. Quadruped like the Alpha Bear
-- but front-heavy and armoured, so the two never read as the same animal.
function RIGS.TimeRift(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.66, u * 0.5, u * 0.96), pal.skin, Enum.Material.Slate)

	local withers = mk(ctx, "Withers", Enum.PartType.Block, Vector3.new(u * 0.72, u * 0.42, u * 0.44), pal.dark, Enum.Material.Slate)
	att(ctx, withers, CFrame.new(0, u * 0.26, -u * 0.24), IDENTITY, "float", u * 0.01, 1.1, 0)

	local clock = disc(ctx, "ClockFace", u * 0.44, u * 0.06, pal.gold, Enum.Material.Metal)
	att(ctx, clock, CFrame.new(0, u * 0.06, -u * 0.5), DISC_FACE, "float", u * 0.01, 1.1, 0.4)

	for i, hand in ipairs({ { 0.18, 0.5 }, { 0.13, -1.4 } }) do
		local needle = mk(ctx, "Hand", Enum.PartType.Block, Vector3.new(u * 0.03, u * hand[1], u * 0.03), pal.ink, Enum.Material.Metal)
		att(ctx, needle, CFrame.new(0, u * 0.06, -u * 0.54), CFrame.new(0, u * hand[1] * 0.5, 0), "orbit", 0, hand[2], i)
	end

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.4, u * 0.36, u * 0.5), pal.skin, Enum.Material.Slate)
	att(ctx, head, CFrame.new(0, u * 0.18, -u * 0.74), CFrame.Angles(math.rad(12), 0, 0), "float", u * 0.02, 1.1, 0.4)

	eyePair(ctx, u * 0.13, u * 0.28, -u * 0.96, u * 0.1, pal.gold, 1.1)

	-- spiral horns: three shortening segments per side, each curling further back
	pairUp(function(side)
		for i, seg in ipairs({ { 0.3, 26, 0.34 }, { 0.24, 62, 0.26 }, { 0.18, 104, 0.2 } }) do
			local horn = mk(ctx, "Horn", Enum.PartType.Block, Vector3.new(u * seg[3] * 0.4, u * seg[1], u * seg[3] * 0.4), pal.light, Enum.Material.Slate)
			att(ctx, horn, CFrame.new(side * u * 0.2, u * 0.38, -u * 0.6),
				CFrame.Angles(math.rad(seg[2]), 0, math.rad(side * 24)) * CFrame.new(0, u * (0.1 + i * 0.18), 0), "float", u * 0.02, 1.1, 0.4)
		end
	end)

	-- mane of time-worn plates down the spine
	for i = 1, 4 do
		local plate = mk(ctx, "Plate", Enum.PartType.Wedge, Vector3.new(u * 0.09, u * (0.3 - i * 0.05), u * 0.28), pal.gold, Enum.Material.Metal)
		att(ctx, plate, CFrame.new(0, u * 0.3, u * (-0.06 + i * 0.18)), CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, u * 0.12, 0), "float", u * 0.014, 1.1, i * 0.6)
	end

	local gait = { 0, math.pi, math.pi, 0 }
	local n = 0
	for _, dz in ipairs({ -u * 0.3, u * 0.34 }) do
		for _, dx in ipairs({ -u * 0.24, u * 0.24 }) do
			n += 1
			local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.2, u * 0.38, u * 0.22), pal.dark, Enum.Material.Slate)
			att(ctx, leg, CFrame.new(dx, -u * 0.18, dz), CFrame.new(0, -u * 0.17, 0), "swing", 0.22, 1.4, gait[n])

			local hoof = mk(ctx, "Hoof", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.1, u * 0.24), pal.gold, Enum.Material.Neon)
			att(ctx, hoof, CFrame.new(dx, -u * 0.18, dz), CFrame.new(0, -u * 0.33, 0), "swing", 0.22, 1.4, gait[n])
		end
	end

	-- the hourglass it is bleeding, hung over the hips
	for _, dy in ipairs(SIDES) do
		local bulb = mk(ctx, "Hourglass", Enum.PartType.Wedge, Vector3.new(u * 0.24, u * 0.16, u * 0.24), pal.gold, Enum.Material.Neon, 0.25)
		att(ctx, bulb, CFrame.new(0, u * 0.6, u * 0.3), CFrame.new(0, dy * u * 0.1, 0) * CFrame.Angles(dy > 0 and 0 or math.rad(180), 0, 0), "float", u * 0.03, 0.9, 0)
	end

	local sand = mk(ctx, "Sand", Enum.PartType.Block, Vector3.new(u * 0.04, u * 0.5, u * 0.04), pal.gold, Enum.Material.Neon, 0.4)
	att(ctx, sand, CFrame.new(0, u * 0.34, u * 0.3), IDENTITY, "float", u * 0.02, 1.6, 0)

	ctx.top = u * 1.05
	return body
end

-- AntimatterZone / Antimatter Horror -- an explosion that never finished: a white-hot core
-- with its own black shell frozen mid-burst around it. The only boss whose eyes are dark.
function RIGS.AntimatterZone(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.66, u * 0.66, u * 0.66), Color3.fromRGB(255, 250, 240), Enum.Material.Neon)

	local halo = mk(ctx, "Flash", Enum.PartType.Ball, Vector3.new(u * 0.86, u * 0.86, u * 0.86), pal.glow, Enum.Material.Neon, 0.62)
	att(ctx, halo, IDENTITY, IDENTITY, "float", u * 0.03, 2.1, 0)

	-- negative eyes: holes punched in the light rather than lights in the dark
	pairUp(function(side)
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.16, u * 0.16, u * 0.16), pal.ink)
		att(ctx, eye, CFrame.new(side * u * 0.15, u * 0.12, -u * 0.3), IDENTITY, "float", u * 0.02, 1.8, 0.4)

		local brow = mk(ctx, "Brow", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.1, u * 0.22), pal.ink)
		att(ctx, brow, CFrame.new(side * u * 0.17, u * 0.26, -u * 0.28), CFrame.Angles(0, math.rad(side * 90), math.rad(side * -22)), "float", u * 0.02, 1.8, 0.4)
	end)

	local maw = mk(ctx, "Maw", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.14, u * 0.08), pal.ink)
	att(ctx, maw, CFrame.new(0, -u * 0.14, -u * 0.3), IDENTITY, "float", u * 0.02, 1.8, 0.4)

	-- shell fragments hanging where the blast threw them
	ringOf(ctx, 8, u * 0.66, 0, function(i, _, joint)
		local shard = mk(ctx, "Shard", Enum.PartType.Wedge, Vector3.new(u * 0.16, u * 0.36, u * 0.2), pal.dark, Enum.Material.Slate)
		att(ctx, shard, joint, CFrame.Angles(math.rad(i * 27), 0, math.rad(-96 + (i % 2) * 24)) * CFrame.new(0, u * 0.18, 0), "pulse", u * 0.05, 1.3 + i * 0.07, i * 0.8)
	end)

	for _, cap in ipairs(SIDES) do
		local plate = mk(ctx, "Shard", Enum.PartType.Wedge, Vector3.new(u * 0.34, u * 0.28, u * 0.34), pal.dark, Enum.Material.Slate)
		att(ctx, plate, CFrame.new(0, cap * u * 0.5, 0), CFrame.Angles(cap > 0 and 0 or math.rad(180), 0, 0), "float", u * 0.04, 1.1, cap > 0 and 0 or 1.7)
	end

	-- annihilation ring: the blast front, still expanding
	local front = disc(ctx, "BlastRing", u * 1.5, u * 0.05, pal.rage, Enum.Material.Neon, 0.35)
	att(ctx, front, IDENTITY, CFrame.Angles(math.rad(9), 0, math.rad(-7)) * DISC_FLAT, "orbit", 0, 1.1, 0)

	for i = 1, 4 do
		local bolt = mk(ctx, "Bolt", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.05, u * 0.8), pal.rage, Enum.Material.Neon)
		att(ctx, bolt, IDENTITY, CFrame.Angles(0, math.rad(i * 45), math.rad(i * 19)) * CFrame.new(0, 0, u * 0.4), "orbit", 0, -0.9, i)
	end

	ctx.top = u * 0.95
	return body
end

-- DreamDimension / Nightmare Weaver -- the body hangs low between eight stilted legs, with
-- a cluster of unmatched eyes and silk trailing off the abdomen.
function RIGS.DreamDimension(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.6, u * 0.56, u * 0.72), pal.skin, Enum.Material.SmoothPlastic, 0.12)

	local abdomen = mk(ctx, "Abdomen", Enum.PartType.Ball, Vector3.new(u * 0.54, u * 0.5, u * 0.6), pal.dark, Enum.Material.SmoothPlastic, 0.12)
	att(ctx, abdomen, CFrame.new(0, u * 0.08, u * 0.46), IDENTITY, "float", u * 0.02, 1.0, 0)

	local mark = mk(ctx, "Mark", Enum.PartType.Wedge, Vector3.new(u * 0.02, u * 0.3, u * 0.26), pal.glow, Enum.Material.Neon)
	att(ctx, mark, CFrame.new(0, u * 0.3, u * 0.46), CFrame.Angles(0, math.rad(180), 0), "float", u * 0.02, 1.0, 0)

	local head = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.4, u * 0.34, u * 0.42), pal.light, Enum.Material.SmoothPlastic, 0.12)
	att(ctx, head, CFrame.new(0, u * 0.02, -u * 0.44), IDENTITY, "float", u * 0.024, 1.0, 0.5)

	-- six eyes, none of them the same size, none of them level
	for i, spot in ipairs({ { -0.14, 0.14, 0.12 }, { 0.14, 0.14, 0.12 }, { -0.2, 0.02, 0.08 }, { 0.2, 0.02, 0.08 }, { -0.08, -0.08, 0.07 }, { 0.08, -0.08, 0.07 } }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * spot[3], u * spot[3], u * spot[3]), pal.rage, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(u * spot[1], u * spot[2], -u * 0.62), IDENTITY, "float", u * 0.024, 1.0 + i * 0.06, i * 0.5)
	end

	pairUp(function(side)
		local fang = mk(ctx, "Fang", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.26, u * 0.09), BONE)
		att(ctx, fang, CFrame.new(side * u * 0.11, -u * 0.14, -u * 0.56), CFrame.Angles(math.rad(166), 0, math.rad(side * 10)), "swing", 0.14, 1.4, side > 0 and 0 or math.pi)
	end)

	-- eight legs: a knee thrown up and out, then a long shin dropping to the floor
	local n = 0
	for _, dz in ipairs({ -0.3, -0.1, 0.12, 0.34 }) do
		pairUp(function(side)
			n += 1
			local joint = CFrame.new(side * u * 0.22, u * 0.1, u * dz)
			local knee = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.08, u * 0.42, u * 0.08), pal.dark)
			att(ctx, knee, joint, CFrame.Angles(0, 0, math.rad(side * -52)) * CFrame.new(0, u * 0.21, 0), "swing", 0.14, 1.5, n * 0.7)

			local shin = mk(ctx, "Shin", Enum.PartType.Block, Vector3.new(u * 0.06, u * 0.9, u * 0.06), pal.light)
			att(ctx, shin, joint,
				CFrame.Angles(0, 0, math.rad(side * -52)) * CFrame.new(0, u * 0.42, 0) * CFrame.Angles(0, 0, math.rad(side * -128)) * CFrame.new(0, u * 0.45, 0),
				"swing", 0.14, 1.5, n * 0.7)
		end)
	end

	-- silk it never finished spinning
	for i = 1, 3 do
		local silk = mk(ctx, "Silk", Enum.PartType.Block, Vector3.new(u * 0.03, u * 0.44, u * 0.03), pal.belly, Enum.Material.Neon, 0.5)
		att(ctx, silk, CFrame.new(u * (i - 2) * 0.14, -u * 0.12, u * 0.6), CFrame.new(0, -u * 0.22, 0), "trail", 0.3, 0.8 + i * 0.2, i * 1.2)
	end

	ctx.top = u * 0.9
	return body
end

-- MirrorUniverse / Mirror Tyrant -- a knight assembled out of mirror: one half of it pale,
-- one half its own dark reflection, with loose panes still orbiting the seam.
function RIGS.MirrorUniverse(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.56, u * 0.6, u * 0.34), pal.light, Enum.Material.Metal)

	-- the reflected half, laid straight over the right side of every surface
	local shadowHalf = mk(ctx, "DarkHalf", Enum.PartType.Block, Vector3.new(u * 0.28, u * 0.61, u * 0.35), pal.ink, Enum.Material.Metal)
	att(ctx, shadowHalf, CFrame.new(u * 0.14, 0, 0), IDENTITY, nil)

	local seam = mk(ctx, "Seam", Enum.PartType.Block, Vector3.new(u * 0.03, u * 0.62, u * 0.37), pal.glow, Enum.Material.Neon)
	att(ctx, seam, IDENTITY, IDENTITY, "float", u * 0.008, 1.6, 0)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.32, u * 0.28), pal.light, Enum.Material.Metal)
	att(ctx, head, CFrame.new(0, u * 0.5, 0), IDENTITY, "float", u * 0.014, 1.4, 0.3)

	local darkFace = mk(ctx, "DarkHalf", Enum.PartType.Block, Vector3.new(u * 0.15, u * 0.33, u * 0.29), pal.ink, Enum.Material.Metal)
	att(ctx, darkFace, CFrame.new(u * 0.075, u * 0.5, 0), IDENTITY, "float", u * 0.014, 1.4, 0.3)

	local crest = mk(ctx, "Crest", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.3, u * 0.3), pal.belly, Enum.Material.Metal)
	att(ctx, crest, CFrame.new(0, u * 0.66, u * 0.02), CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, u * 0.14, 0), "float", u * 0.014, 1.4, 0.3)

	-- one eye burns, the reflected one is cold
	local hotEye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.09, u * 0.09, u * 0.09), pal.rage, Enum.Material.Neon)
	att(ctx, hotEye, CFrame.new(-u * 0.08, u * 0.53, -u * 0.16), IDENTITY, "float", u * 0.014, 1.4, 0.3)

	local coldEye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.09, u * 0.09, u * 0.09), pal.glow, Enum.Material.Neon)
	att(ctx, coldEye, CFrame.new(u * 0.08, u * 0.53, -u * 0.16), IDENTITY, "float", u * 0.014, 1.4, 0.3)

	pairUp(function(side)
		local pauldron = mk(ctx, "Pauldron", Enum.PartType.Wedge, Vector3.new(u * 0.1, u * 0.24, u * 0.3), side > 0 and pal.ink or pal.belly, Enum.Material.Metal)
		att(ctx, pauldron, CFrame.new(side * u * 0.34, u * 0.26, 0), CFrame.Angles(0, math.rad(side * 90), math.rad(side * -18)), "float", u * 0.012, 1.4, 0.2)

		local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.13, u * 0.4, u * 0.15), side > 0 and pal.ink or pal.light, Enum.Material.Metal)
		att(ctx, arm, CFrame.new(side * u * 0.34, u * 0.16, 0), CFrame.new(0, -u * 0.2, 0), "swing", 0.26, 1.4, side > 0 and 0 or math.pi)

		-- a shard blade in each hand, mirrored point for point
		local blade = mk(ctx, "Blade", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.52, u * 0.16), side > 0 and pal.glow or pal.belly, Enum.Material.Metal)
		att(ctx, blade, CFrame.new(side * u * 0.34, u * 0.16, 0), CFrame.new(0, -u * 0.42, -u * 0.12) * CFrame.Angles(math.rad(-70), 0, 0), "swing", 0.26, 1.4, side > 0 and 0 or math.pi)

		local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.16, u * 0.34, u * 0.18), side > 0 and pal.ink or pal.light, Enum.Material.Metal)
		att(ctx, leg, CFrame.new(side * u * 0.16, -u * 0.3, 0), CFrame.new(0, -u * 0.13, 0), "swing", 0.16, 1.4, side > 0 and math.pi or 0)
	end)

	-- loose panes: still-unplaced pieces of the reflection
	for i = 1, 6 do
		local pane = mk(ctx, "Pane", Enum.PartType.Block, Vector3.new(u * 0.03, u * 0.32, u * 0.22), i % 2 == 0 and pal.belly or pal.metal, Enum.Material.Metal, 0.15)
		att(ctx, pane, IDENTITY,
			CFrame.new(u * 0.68, u * (0.42 - (i % 3) * 0.3), 0) * CFrame.Angles(0, math.rad(i * 14), math.rad(i * 23)),
			"orbit", 0, (i % 2 == 0) and 0.45 or -0.35, (i - 1) * (math.pi * 2 / 6))
	end

	ctx.top = u * 1.05
	return body
end

-- VoidExpanse / Void Colossus -- the biggest solid thing in the game: a black slab of a
-- giant, faceless except for the rift where a face should be, cracked open along the chest.
function RIGS.VoidExpanse(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.72, u * 0.66, u * 0.46), pal.ink, Enum.Material.Slate)

	local chest = mk(ctx, "ChestRift", Enum.PartType.Block, Vector3.new(u * 0.1, u * 0.4, u * 0.06), pal.glow, Enum.Material.Neon)
	att(ctx, chest, CFrame.new(0, u * 0.04, -u * 0.24), CFrame.Angles(0, 0, math.rad(7)), "float", u * 0.01, 1.0, 0)

	for i, crack in ipairs({ { -0.22, 0.18, 34 }, { 0.24, 0.02, -28 }, { -0.16, -0.2, 18 } }) do
		local line = mk(ctx, "Crack", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.04, u * 0.04), pal.glow, Enum.Material.Neon, 0.15)
		att(ctx, line, CFrame.new(u * crack[1], u * crack[2], -u * 0.24), CFrame.Angles(0, 0, math.rad(crack[3])), "float", u * 0.008, 0.9, i)
	end

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.34, u * 0.3, u * 0.3), pal.ink, Enum.Material.Slate)
	att(ctx, head, CFrame.new(0, u * 0.52, 0), IDENTITY, "float", u * 0.012, 1.0, 0.4)

	-- no eyes, one rift: the void is looking back through the gap
	local rift = mk(ctx, "Visor", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.06, u * 0.05), pal.glow, Enum.Material.Neon)
	att(ctx, rift, CFrame.new(0, u * 0.53, -u * 0.16), IDENTITY, "float", u * 0.012, 1.0, 0.4)

	pairUp(function(side)
		local shoulder = mk(ctx, "Shoulder", Enum.PartType.Block, Vector3.new(u * 0.28, u * 0.3, u * 0.4), pal.dark, Enum.Material.Slate)
		att(ctx, shoulder, CFrame.new(side * u * 0.46, u * 0.26, 0), IDENTITY, "float", u * 0.01, 1.0, 0.2)

		local upper = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.2, u * 0.36, u * 0.22), pal.ink, Enum.Material.Slate)
		att(ctx, upper, CFrame.new(side * u * 0.48, u * 0.16, 0), CFrame.Angles(0, 0, math.rad(side * 8)) * CFrame.new(0, -u * 0.18, 0), "swing", 0.22, 1.0, side > 0 and 0 or math.pi)

		local fore = mk(ctx, "Forearm", Enum.PartType.Block, Vector3.new(u * 0.24, u * 0.3, u * 0.26), pal.dark, Enum.Material.Slate)
		att(ctx, fore, CFrame.new(side * u * 0.48, u * 0.16, 0), CFrame.Angles(0, 0, math.rad(side * 8)) * CFrame.new(0, -u * 0.5, 0), "swing", 0.22, 1.0, side > 0 and 0 or math.pi)

		local palm = mk(ctx, "Palm", Enum.PartType.Block, Vector3.new(u * 0.06, u * 0.14, u * 0.14), pal.glow, Enum.Material.Neon)
		att(ctx, palm, CFrame.new(side * u * 0.48, u * 0.16, 0), CFrame.Angles(0, 0, math.rad(side * 8)) * CFrame.new(-side * u * 0.11, -u * 0.5, 0), "swing", 0.22, 1.0, side > 0 and 0 or math.pi)
	end)

	limbPair(ctx, "Leg", Vector3.new(u * 0.26, u * 0.32, u * 0.28), Vector3.new(u * 0.2, -u * 0.3, 0), u * 0.12, pal.ink, Enum.Material.Slate, 0, 0.1, 1.0)
	limbPair(ctx, "Foot", Vector3.new(u * 0.3, u * 0.12, u * 0.36), Vector3.new(u * 0.2, -u * 0.3, -u * 0.03), u * 0.22, pal.dark, Enum.Material.Slate, 0, 0.1, 1.0)

	-- the expanse itself, tearing off it in slow flakes
	for i = 1, 5 do
		local flake = mk(ctx, "VoidShard", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.3, u * 0.16), pal.dark, Enum.Material.Slate)
		att(ctx, flake, IDENTITY,
			CFrame.new(u * 0.8, u * (0.5 - (i % 3) * 0.34), 0) * CFrame.Angles(math.rad(i * 31), 0, math.rad(i * 18)),
			"orbit", 0, (i % 2 == 0) and 0.3 or -0.24, (i - 1) * (math.pi * 2 / 5))
	end

	ctx.top = u * 1.0
	return body
end

-- CelestialThrone / Throne Guardian -- gold sentinel seated in front of its own throne:
-- six wings, a halo, a crown and a scepter. The most ornate rig in the game.
function RIGS.CelestialThrone(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.54, u * 0.6, u * 0.36), pal.gold, Enum.Material.Metal)

	-- the throne it guards, standing behind it
	for i, post in ipairs({ { -0.44, 0.9 }, { 0, 1.2 }, { 0.44, 0.9 } }) do
		local pillar = mk(ctx, "ThronePost", Enum.PartType.Block, Vector3.new(u * 0.16, u * post[2], u * 0.16), pal.trim, Enum.Material.Metal)
		att(ctx, pillar, CFrame.new(u * post[1], u * (post[2] * 0.5 - 0.5), u * 0.52), IDENTITY, "float", u * 0.006, 0.8, i)

		local finial = mk(ctx, "Finial", Enum.PartType.Ball, Vector3.new(u * 0.16, u * 0.16, u * 0.16), pal.glow, Enum.Material.Neon)
		att(ctx, finial, CFrame.new(u * post[1], u * (post[2] - 0.44), u * 0.52), IDENTITY, "float", u * 0.02, 0.8, i)
	end

	local sash = mk(ctx, "Sash", Enum.PartType.Block, Vector3.new(u * 0.4, u * 0.42, u * 0.08), pal.belly, Enum.Material.Metal)
	att(ctx, sash, CFrame.new(0, u * 0.04, -u * 0.2), CFrame.Angles(0, 0, math.rad(9)), "float", u * 0.008, 1.2, 0)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.28, u * 0.3, u * 0.28), pal.light, Enum.Material.Metal)
	att(ctx, head, CFrame.new(0, u * 0.5, 0), IDENTITY, "float", u * 0.012, 1.2, 0.3)

	local mask = mk(ctx, "Visor", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.14, u * 0.05), pal.glow, Enum.Material.Neon)
	att(ctx, mask, CFrame.new(0, u * 0.5, -u * 0.16), IDENTITY, "float", u * 0.012, 1.2, 0.3)

	eyePair(ctx, u * 0.07, u * 0.52, -u * 0.19, u * 0.06, pal.rage, 1.2)

	crownOf(ctx, 5, u * 0.16, u * 0.66, u * 0.3, pal.gold)

	local halo = disc(ctx, "Halo", u * 0.68, u * 0.05, pal.glow, Enum.Material.Neon, 0.2)
	att(ctx, halo, CFrame.new(0, u * 0.92, 0), DISC_FLAT, "orbit", 0, 0.5, 0)

	-- three feathers a side, longest at the top
	pairUp(function(side)
		for i, wing in ipairs({ { 0.34, 0.9, 34 }, { 0.16, 0.74, 8 }, { -0.02, 0.56, -18 } }) do
			local feather = mk(ctx, "Wing", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * wing[2], u * 0.26), i == 2 and pal.belly or pal.gold, Enum.Material.Metal)
			att(ctx, feather, CFrame.new(side * u * 0.26, u * wing[1], u * 0.24),
				CFrame.Angles(math.rad(wing[3]), math.rad(side * 108), math.rad(side * 62)) * CFrame.new(0, u * wing[2] * 0.5, 0),
				"flap", 0.16, 0.9, side > 0 and 0 or math.pi)
		end

		local pauldron = mk(ctx, "Pauldron", Enum.PartType.Block, Vector3.new(u * 0.2, u * 0.18, u * 0.28), pal.trim, Enum.Material.Metal)
		att(ctx, pauldron, CFrame.new(side * u * 0.36, u * 0.26, 0), IDENTITY, "float", u * 0.01, 1.2, 0.2)

		local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.13, u * 0.4, u * 0.15), pal.gold, Enum.Material.Metal)
		att(ctx, arm, CFrame.new(side * u * 0.36, u * 0.16, 0), CFrame.Angles(0, 0, math.rad(side * 12)) * CFrame.new(0, -u * 0.2, 0), "swing", 0.2, 1.2, side > 0 and 0 or math.pi)

		local greave = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.17, u * 0.34, u * 0.19), pal.trim, Enum.Material.Metal)
		att(ctx, greave, CFrame.new(side * u * 0.17, -u * 0.3, 0), CFrame.new(0, -u * 0.13, 0), "swing", 0.12, 1.2, side > 0 and math.pi or 0)
	end)

	-- the scepter, held out in the right hand
	local shaft = mk(ctx, "Scepter", Enum.PartType.Cylinder, Vector3.new(u * 0.86, u * 0.07, u * 0.07), pal.trim, Enum.Material.Metal)
	att(ctx, shaft, CFrame.new(u * 0.36, u * 0.16, 0), CFrame.new(0, -u * 0.14, -u * 0.14) * DISC_FLAT, "swing", 0.2, 1.2, 0)

	local orb = mk(ctx, "ScepterOrb", Enum.PartType.Ball, Vector3.new(u * 0.2, u * 0.2, u * 0.2), pal.glow, Enum.Material.Neon)
	att(ctx, orb, CFrame.new(u * 0.36, u * 0.16, 0), CFrame.new(0, u * 0.36, -u * 0.14), "swing", 0.2, 1.2, 0)

	ctx.top = u * 1.3
	return body
end

-- Singularity / The Singularity -- no body left at all: a blinding core inside a dark event
-- shell, three rings collapsing through each other, matter still falling in.
function RIGS.Singularity(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.42, u * 0.42, u * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)

	local shell = mk(ctx, "Shell", Enum.PartType.Ball, Vector3.new(u * 0.86, u * 0.86, u * 0.86), pal.ink, Enum.Material.SmoothPlastic, 0.28)
	att(ctx, shell, IDENTITY, IDENTITY, "float", u * 0.02, 0.7, 0)

	local corona = mk(ctx, "Corona", Enum.PartType.Ball, Vector3.new(u * 0.62, u * 0.62, u * 0.62), pal.glow, Enum.Material.Neon, 0.55)
	att(ctx, corona, IDENTITY, IDENTITY, "float", u * 0.03, 1.7, 1.1)

	-- the face is two slits burnt through the shell
	pairUp(function(side)
		local slit = mk(ctx, "Eye", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.05, u * 0.05), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
		att(ctx, slit, CFrame.new(side * u * 0.14, u * 0.12, -u * 0.42), CFrame.Angles(0, 0, math.rad(side * -16)), "float", u * 0.012, 1.4, 0.3)
	end)

	local mouth = mk(ctx, "Maw", Enum.PartType.Block, Vector3.new(u * 0.24, u * 0.04, u * 0.05), pal.rage, Enum.Material.Neon)
	att(ctx, mouth, CFrame.new(0, -u * 0.1, -u * 0.42), IDENTITY, "float", u * 0.012, 1.4, 0.3)

	for i, ring in ipairs({ { 1.44, 26, -12, 0.7 }, { 1.16, -38, 22, -0.95 }, { 0.94, 12, 78, 1.3 } }) do
		local band = disc(ctx, "Ring", u * ring[1], u * 0.05, i == 2 and pal.belly or pal.glow, Enum.Material.Neon, 0.22)
		att(ctx, band, IDENTITY, CFrame.Angles(math.rad(ring[2]), 0, math.rad(ring[3])) * DISC_FLAT, "orbit", 0, ring[4], i)
	end

	-- matter stretched into threads on its way in
	ringOf(ctx, 10, u * 0.78, 0, function(i, _, joint)
		local thread = mk(ctx, "Infall", Enum.PartType.Block, Vector3.new(u * 0.42, u * 0.05, u * 0.05), pal.metal, Enum.Material.Neon, 0.3)
		att(ctx, thread, IDENTITY,
			joint * CFrame.Angles(0, 0, math.rad((i % 2 == 0) and 26 or -26)) * CFrame.new(0, u * (i % 3 - 1) * 0.22, 0),
			"orbit", 0, 1.4, i * 0.4)
	end)

	for i = 1, 4 do
		local spear = mk(ctx, "Spear", Enum.PartType.Wedge, Vector3.new(u * 0.08, u * 0.5, u * 0.12), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, 0.15)
		att(ctx, spear, IDENTITY, CFrame.Angles(0, math.rad(i * 90), 0) * CFrame.new(0, u * 0.66, 0) * CFrame.Angles(math.rad(i * 12), 0, 0), "orbit", 0, -0.6, i)
	end

	ctx.top = u * 1.05
	return body
end

-- AbsolutePlane / The Absolute -- the endgame is not an animal, it is a monument: a gold
-- monolith standing inside its own triangle, one great eye, two counter-rotating tetra
-- shells and three haloes. Nothing about it moves like something alive.
function RIGS.AbsolutePlane(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.34, u * 1.0, u * 0.34), pal.gold, Enum.Material.Metal)

	-- the 🔺 silhouette: two mirrored wedges leaning on the monolith
	pairUp(function(side)
		local slope = mk(ctx, "Face", Enum.PartType.Wedge, Vector3.new(u * 0.3, u * 0.9, u * 0.34), pal.metal, Enum.Material.Metal)
		att(ctx, slope, CFrame.new(side * u * 0.18, -u * 0.06, 0), CFrame.Angles(0, math.rad(side * 90), 0), nil)

		local edge = mk(ctx, "Edge", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.05, u * 0.36), pal.glow, Enum.Material.Neon)
		att(ctx, edge, CFrame.new(side * u * 0.18, -u * 0.06, 0), CFrame.Angles(0, 0, math.rad(side * 62)) * CFrame.new(0, u * 0.5, 0), "float", u * 0.006, 0.8, 0)
	end)

	local base = mk(ctx, "Plinth", Enum.PartType.Block, Vector3.new(u * 0.96, u * 0.12, u * 0.62), pal.trim, Enum.Material.Metal)
	att(ctx, base, CFrame.new(0, -u * 0.48, 0), IDENTITY, nil)

	-- the great eye: a lens sunk into the monolith, and it is the only face it has
	local socket = disc(ctx, "Socket", u * 0.36, u * 0.07, pal.ink, Enum.Material.Metal)
	att(ctx, socket, CFrame.new(0, u * 0.22, -u * 0.19), DISC_FACE, "float", u * 0.006, 0.7, 0)

	local iris = disc(ctx, "Iris", u * 0.26, u * 0.06, pal.gold, Enum.Material.Neon)
	att(ctx, iris, CFrame.new(0, u * 0.22, -u * 0.22), DISC_FACE, "float", u * 0.008, 0.7, 0)

	local pupil = mk(ctx, "Eye", Enum.PartType.Block, Vector3.new(u * 0.06, u * 0.18, u * 0.06), pal.ink)
	att(ctx, pupil, CFrame.new(0, u * 0.22, -u * 0.25), IDENTITY, "float", u * 0.01, 0.7, 0)

	crownOf(ctx, 3, u * 0.14, u * 0.52, u * 0.32, pal.gold)

	-- two tetra shells, counter-rotating, one above and one below the monolith
	for _, tier in ipairs({ { 1.0, 0.34, 0.45 }, { -0.66, 0.3, -0.35 } }) do
		for i = 1, 4 do
			local a = (i - 1) * (math.pi * 0.5)
			local facet = mk(ctx, "Facet", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.34, u * 0.4), pal.gold, Enum.Material.Metal, 0.1)
			att(ctx, facet, CFrame.new(0, u * tier[1], 0),
				CFrame.Angles(0, -a, 0) * CFrame.new(u * tier[2], 0, 0) * CFrame.Angles(0, math.rad(90), math.rad(62)),
				"orbit", 0, tier[3], 0)
		end
	end

	for i, halo in ipairs({ { 1.7, 0.16, 0.3 }, { 1.4, -0.1, -0.42 }, { 1.1, 0.5, 0.55 } }) do
		local band = disc(ctx, "Halo", u * halo[1], u * 0.05, i == 2 and pal.glow or pal.gold, Enum.Material.Neon, 0.25)
		att(ctx, band, IDENTITY, CFrame.Angles(math.rad(i * 11 - 16), 0, math.rad(i * -9)) * CFrame.new(0, u * halo[2], 0) * DISC_FLAT, "orbit", 0, halo[3], i)
	end

	-- a sunburst of beams, because there is nothing after this
	for i = 1, 8 do
		local beam = mk(ctx, "Beam", Enum.PartType.Block, Vector3.new(u * 0.04, u * 0.9, u * 0.04), pal.gold, Enum.Material.Neon, 0.4)
		att(ctx, beam, IDENTITY,
			CFrame.Angles(0, math.rad(i * 45), 0) * CFrame.new(u * 0.86, u * 0.2, 0) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 22 or -22)),
			"orbit", 0, 0.22, 0)
	end

	ctx.top = u * 1.55
	return body
end

-- ===== ARENA =================================================================
-- Static furniture laid around every boss: a raised dais, a kerb of studs, scattered rubble and
-- four corner pylons. None of it is attached with a motion, so driveRigs filters the whole lot
-- out of its per-frame list -- this is detail that costs one CFrame write at spawn and nothing
-- afterwards, which is exactly why a boss can afford thirty pieces of it.
--
-- Everything is placed by index rather than math.random: two players looking at the same boss
-- must see the same rubble, and a boss that respawns must come back to the same arena.
local function arenaDetail(ctx)
	local u, pal = ctx.u, ctx.pal
	local ground = -u * 0.55 -- spawnBoss lifts the body this far, so this lands on the zone floor

	-- Dark plate first, glowing pool on top of it. The pool alone read as a light stain on the
	-- grass; the plate under it gives the dais an edge and makes it a built thing.
	local rim = disc(ctx, "DaisRim", u * 1.52, u * 0.07, pal.trim, Enum.Material.Slate)
	att(ctx, rim, CFrame.new(0, ground + u * 0.025, 0), DISC_FLAT, nil)

	local pool = disc(ctx, "Dais", u * 1.34, u * 0.05, pal.glow, Enum.Material.Neon, 0.5)
	att(ctx, pool, CFrame.new(0, ground + u * 0.07, 0), DISC_FLAT, nil)

	-- contact shadow: without it a rig this big visually floats off its own dais
	local shade = disc(ctx, "Contact", u * 0.82, u * 0.03, INK, Enum.Material.SmoothPlastic, 0.45)
	att(ctx, shade, CFrame.new(0, ground + u * 0.1, 0), DISC_FLAT, nil)

	-- kerb running round the plate's edge
	ringOf(ctx, 16, u * 0.71, 0, function(_, _, joint)
		local stud = mk(ctx, "Kerb", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.08, u * 0.13), pal.metal, Enum.Material.Metal)
		att(ctx, stud, CFrame.new(0, ground + u * 0.07, 0), joint, nil)
	end)

	-- rubble, tumbled off the kerb and out onto the floor. The three magic numbers per entry are
	-- angle turns, radius as a fraction of u, and chunk size -- spread by hand so the ring never
	-- reads as evenly spaced.
	for i, chunk in ipairs({
		{ 0.04, 0.62, 0.13 }, { 0.19, 0.80, 0.09 }, { 0.31, 0.58, 0.16 }, { 0.44, 0.86, 0.07 },
		{ 0.53, 0.66, 0.11 }, { 0.67, 0.77, 0.14 }, { 0.78, 0.60, 0.08 }, { 0.91, 0.83, 0.12 },
	}) do
		local a = chunk[1] * math.pi * 2
		local size = u * chunk[3]
		local rock = mk(ctx, "Rubble", Enum.PartType.Block, Vector3.new(size, size * 0.62, size * 0.84),
			i % 3 == 0 and pal.dark or pal.trim, Enum.Material.Slate)
		att(ctx, rock, CFrame.new(math.cos(a) * u * chunk[2], ground + size * 0.3, math.sin(a) * u * chunk[2]),
			CFrame.Angles(0, a * 1.7, math.rad(i * 4 - 14)), nil)
	end

	-- four pylons marking the corners of the arena, each with a lit tip. Kept low and pushed out
	-- past the rig so they frame the silhouette instead of crowding it.
	for i = 1, 4 do
		local a = (i - 0.5) * (math.pi * 0.5)
		local at = CFrame.new(math.cos(a) * u * 0.82, ground, math.sin(a) * u * 0.82)

		local post = mk(ctx, "Pylon", Enum.PartType.Block, Vector3.new(u * 0.1, u * 0.42, u * 0.1), pal.trim, Enum.Material.Slate)
		att(ctx, post, at, CFrame.new(0, u * 0.21, 0), nil)

		local collar = mk(ctx, "PylonCollar", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.05, u * 0.14), pal.metal, Enum.Material.Metal)
		att(ctx, collar, at, CFrame.new(0, u * 0.4, 0), nil)

		local flame = mk(ctx, "PylonLight", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.17, u * 0.13), pal.glow, Enum.Material.Neon, 0.15)
		att(ctx, flame, at, CFrame.new(0, u * 0.5, 0), nil)
	end

	-- A ring of glyphs burned into the plate, alternating long and short so it reads as writing
	-- rather than as tick marks. Placed by index like everything else here: two players must see
	-- the same arena.
	ringOf(ctx, 12, u * 0.5, 0, function(i, _, joint)
		local glyph = mk(ctx, "Rune", Enum.PartType.Block,
			Vector3.new(u * 0.03, u * 0.012, u * (i % 2 == 0 and 0.15 or 0.08)), pal.glow, Enum.Material.Neon, 0.2)
		att(ctx, glyph, CFrame.new(0, ground + u * 0.1, 0), joint, nil)
	end)

	-- Banner masts pushed outside the pylons. They are the tallest thing in the arena, so the boss
	-- reads as a guarded site from across the platform instead of a monster standing on a coin --
	-- and they give the silhouette a frame at every viewing angle, which four low pylons did not.
	--
	-- ON THE DIAGONALS, like the pylons, and that is not cosmetic. At i * pi/2 the four masts land
	-- on +X, -X, +Z and -Z -- and +Z is the arrival gate, i.e. the one direction every player walks
	-- in from. The result was a 1.5x-boss-height black pole standing dead centre in front of the
	-- boss, straight through its face, in every screenshot anyone ever took of a fight. Offsetting
	-- by half a step puts the gap where the player is and the masts at the corners, framing the rig
	-- instead of hiding it.
	for i = 1, 4 do
		local a = (i - 0.5) * (math.pi * 0.5)
		local at = CFrame.new(math.cos(a) * u * 1.24, ground, math.sin(a) * u * 1.24)

		local mast = mk(ctx, "Mast", Enum.PartType.Block, Vector3.new(u * 0.06, u * 1.45, u * 0.06), pal.dark, Enum.Material.Metal)
		att(ctx, mast, at, CFrame.new(0, u * 0.72, 0), nil)

		-- The cloth is turned to face the arena centre and given a slow sway. Turned into a proper
		-- banner rather than the plain red slab it was: a crossbar it hangs from, gold bands top and
		-- bottom, and a swallowtail. At the sizes the bosses now run this thing is nearly 50 studs
		-- tall -- a flat single-colour rectangle that big is the most conspicuous object in the zone
		-- and it read as a placeholder.
		local face = CFrame.Angles(0, -a, 0)
		local function onMast(part, offset, motion)
			att(ctx, part, at, face * offset, motion or "float", u * 0.02, 0.7, i)
		end

		local crossbar = mk(ctx, "MastArm", Enum.PartType.Block, Vector3.new(u * 0.04, u * 0.04, u * 0.36), pal.metal, Enum.Material.Metal)
		onMast(crossbar, CFrame.new(0, u * 1.3, u * 0.02))

		local cloth = mk(ctx, "MastBanner", Enum.PartType.Block, Vector3.new(u * 0.02, u * 0.58, u * 0.3), pal.rage, Enum.Material.Fabric)
		onMast(cloth, CFrame.new(0, u * 1, u * 0.02))

		for _, band in ipairs({ { 1.26, 0.05 }, { 0.76, 0.04 } }) do
			local stripe = mk(ctx, "MastBannerBand", Enum.PartType.Block,
				Vector3.new(u * 0.025, u * band[2], u * 0.31), pal.gold, Enum.Material.Metal)
			onMast(stripe, CFrame.new(0, u * band[1], u * 0.02))
		end

		-- the swallowtail: two wedges leaving a notch in the middle of the bottom edge, which is the
		-- one silhouette cue that says "banner" and not "sign"
		for _, dz in ipairs({ -1, 1 }) do
			local tail = mk(ctx, "MastBannerTail", Enum.PartType.Wedge,
				Vector3.new(u * 0.02, u * 0.14, u * 0.15), pal.rage, Enum.Material.Fabric)
			onMast(tail, CFrame.new(0, u * 0.64, u * 0.02 + dz * u * 0.075) * CFrame.Angles(math.rad(dz * 90), 0, 0))
		end

		local tip = mk(ctx, "MastTip", Enum.PartType.Ball, Vector3.new(u * 0.11, u * 0.14, u * 0.11), pal.glow, Enum.Material.Neon)
		att(ctx, tip, at, CFrame.new(0, u * 1.5, 0), nil)
	end

	-- embers lifting off the plate. One emitter for the whole arena -- it is the cheapest way to
	-- put motion in the dead space around a rig whose own parts are all busy holding a pose.
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(pal.glow, pal.rage)
	embers.Size = NumberSequence.new(u * 0.05, 0)
	embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	embers.Lifetime = NumberRange.new(1.8, 3.4)
	embers.Rate = 16
	embers.Speed = NumberRange.new(u * 0.12, u * 0.3)
	embers.SpreadAngle = Vector2.new(22, 22)
	embers.LightEmission = 1
	embers.Acceleration = Vector3.new(0, u * 0.1, 0)
	embers.Parent = pool
end

-- ===== SHARED ARMOUR PASS =====
-- Every rig gets this on top of whatever its own builder made, so twenty bosses gain the same
-- "this thing was forged, not grown" read without twenty separate edits.
--
-- IT IS WRITTEN AGAINST THE BODY PART'S OWN `Size`, NOT AGAINST `u`. The twenty builders disagree
-- wildly about how much of the unit their torso occupies -- 0.6u for the Sand Wyrm's coil against
-- 1.02u for the Alpha Bear's barrel -- so a plate placed at a fixed fraction of u sits correctly
-- on about half of them and floats a dozen studs off the rest. Sizing off the host is the same
-- rule the costumes and pets follow.
--
-- Five pieces, all LARGE: pauldrons, a chest plate with a lit core, a spine ridge, a waist band
-- and a slow ring of orbiting shards. These rigs are 75-120 studs and are read from across a
-- platform, so a scattering of small greebles would vanish at the distance the boss is actually
-- looked at and cost draw calls for nothing. What reads is a few big plates in a different
-- MATERIAL to the skin -- Metal and Neon against SmoothPlastic -- plus one moving element, which
-- is what the eye catches first at range.
local function bossDetail(ctx, body)
	local u, pal = ctx.u, ctx.pal
	local b = body.Size
	local halfX, halfY, halfZ = b.X * 0.5, b.Y * 0.5, b.Z * 0.5

	-- PAULDRONS -- the single biggest change to the silhouette. Two slabs wider than the shoulder
	-- they sit on give the top of the rig a hard horizontal instead of letting the torso taper
	-- straight into the head, and that horizontal is what makes a shape read as armoured.
	pairUp(function(side)
		local w = b.X * 0.44
		local joint = CFrame.new(side * (halfX + w * 0.3), halfY * 0.66, 0)
		local lean = CFrame.Angles(0, 0, math.rad(side * -15))
		local phase = side > 0 and 0 or 1.7

		local pad = mk(ctx, "Pauldron", Enum.PartType.Block, Vector3.new(w, b.Y * 0.34, b.Z * 0.56), pal.metal, Enum.Material.Metal)
		att(ctx, pad, joint, lean, "float", u * 0.01, 1.15, phase)

		-- a lit lip along the top edge: on a plate this size a flat metal slab reads as a grey box
		local lip = mk(ctx, "PauldronEdge", Enum.PartType.Block, Vector3.new(w * 1.04, b.Y * 0.075, b.Z * 0.6), pal.glow, Enum.Material.Neon, 0.12)
		att(ctx, lip, joint, lean * CFrame.new(0, b.Y * 0.2, 0), "float", u * 0.01, 1.15, phase)

		-- and a spike off the outer corner, so the shoulder has a point rather than a corner
		local spike = mk(ctx, "PauldronSpike", Enum.PartType.Wedge, Vector3.new(w * 0.34, b.Y * 0.42, b.Z * 0.3), pal.dark, Enum.Material.Metal)
		att(ctx, spike, joint, lean * CFrame.new(side * w * 0.36, b.Y * 0.34, 0) * CFrame.Angles(0, 0, math.rad(side * -26)),
			"float", u * 0.01, 1.15, phase)
	end)

	-- CHEST PLATE. Rigs are built facing -Z, so the front of the torso is -halfZ and everything
	-- here steps further along -Z to clear the plate behind it -- the same stacking rule the eyes
	-- use, and for the same reason: a core buried inside its own plate renders as nothing.
	local plate = mk(ctx, "ChestPlate", Enum.PartType.Block, Vector3.new(b.X * 0.66, b.Y * 0.52, b.Z * 0.16), pal.metal, Enum.Material.Metal)
	att(ctx, plate, CFrame.new(0, halfY * 0.1, -(halfZ + b.Z * 0.05)), IDENTITY, "float", u * 0.008, 1.1, 0.5)

	local core = disc(ctx, "ChestCore", b.X * 0.3, b.Z * 0.14, pal.glow, Enum.Material.Neon, 0.1)
	att(ctx, core, CFrame.new(0, halfY * 0.1, -(halfZ + b.Z * 0.14)), DISC_FACE, "float", u * 0.008, 1.1, 0.5)

	local coreRim = disc(ctx, "ChestRim", b.X * 0.42, b.Z * 0.1, pal.gold, Enum.Material.Metal)
	att(ctx, coreRim, CFrame.new(0, halfY * 0.1, -(halfZ + b.Z * 0.11)), DISC_FACE, "float", u * 0.008, 1.1, 0.5)

	-- SPINE RIDGE along the back (+Z). Wedges, because a Roblox wedge's apex points UP -- which is
	-- the one thing about that primitive that works in your favour: a row of them is a dorsal ridge
	-- with no rotation at all. Tapering front to back so it reads as a spine and not as a fence.
	for i = 1, 5 do
		local f = (i - 1) / 4
		local h = b.Y * (0.4 - f * 0.22)
		local fin = mk(ctx, "SpineFin", Enum.PartType.Wedge, Vector3.new(b.X * 0.14, h, b.Z * (0.3 - f * 0.12)), pal.dark, Enum.Material.Slate)
		att(ctx, fin, CFrame.new(0, halfY * (0.86 - f * 0.3), -halfZ * 0.3 + f * b.Z * 0.85),
			CFrame.new(0, h * 0.4, 0), "float", u * 0.012, 1.4, i * 0.5)
	end

	-- WAIST BAND. A thin solid disc slightly wider than the torso: it cuts the body in two, which
	-- stops a big single-colour mass reading as one undifferentiated lump, and it gives the legs
	-- somewhere to come out of.
	local beltR = math.max(b.X, b.Z) * 1.06
	local belt = disc(ctx, "WaistBand", beltR, b.Y * 0.1, pal.trim, Enum.Material.Metal)
	att(ctx, belt, CFrame.new(0, -halfY * 0.42, 0), DISC_FLAT, nil)

	local buckle = mk(ctx, "Buckle", Enum.PartType.Block, Vector3.new(b.X * 0.24, b.Y * 0.18, b.Z * 0.14), pal.gold, Enum.Material.Metal)
	att(ctx, buckle, CFrame.new(0, -halfY * 0.42, -(halfZ + b.Z * 0.03)), IDENTITY, nil)

	-- ORBITING SHARDS. One moving element high on the rig, which is what the eye finds first from
	-- across a platform -- everything else up there is holding a pose. `orbit` turns between joint
	-- and rest, so each shard sweeps a circle around the rig's own axis rather than spinning on the
	-- spot. Placed off ctx.top, so a tall rig gets its ring at its own head height.
	local ringY = (ctx.top or u * 0.9) * 0.82
	for i = 1, 5 do
		local shard = mk(ctx, "Shard", Enum.PartType.Block, Vector3.new(u * 0.07, u * 0.17, u * 0.07), pal.glow, Enum.Material.Neon, 0.2)
		att(ctx, shard, CFrame.new(0, ringY, 0), CFrame.new(u * 0.62, 0, 0) * CFrame.Angles(0, 0, math.rad(22)),
			"orbit", 0, 0.35, i * (math.pi * 2 / 5))
	end
end

-- Builds the rig for a zone's boss and hands back the main body, the flat attachment list
-- the idle loop drives, and how high the name plate should float. Body stays at the model
-- origin because spawnBoss positions, tweens and hangs the billboard/ClickDetector on it.
-- `origin` is a CFRAME, not a position: its rotation is the direction the finished rig faces, and
-- every part is placed at `origin * offset` so passing a turned one turns the whole thing -- rig,
-- arena disc and banner masts together. See the facing note at the top of the file.
local function buildRig(model, origin, zone, boss)
	local ctx = {
		model = model,
		origin = origin,
		u = boss.size,
		pal = buildPalette(zone),
		atts = {},
		top = boss.size * 0.9, -- rigs that stand taller than one body raise this themselves
	}
	-- `rigKey` lets a caller borrow another zone's rig. Only the event boss uses it: its zone is
	-- synthetic and has no rig of its own, and falling through to RIGS.Forest gave the Colosseum a
	-- 124-stud woodland animal.
	-- A generated figure wins if this zone has one. It is NOT given bossDetail: that pass bolts
	-- armour plates, a spine ridge and orbiting shards onto a primitive torso to stop it reading as
	-- a stack of blocks, and a generated boss has a face, fur and a silhouette of its own -- the
	-- same plates on top of it read as clutter welded to a finished model.
	local meshFolder = game:GetService("ServerStorage"):FindFirstChild("BossMeshes")
	local template = meshFolder and meshFolder:FindFirstChild("BossMesh_" .. (zone.rigKey or zone.key))
	local body = template and meshRig(ctx, template)

	if not body then
		local builder = RIGS[zone.rigKey or zone.key] or RIGS.Forest
		body = builder(ctx)

		-- armour, spine and orbiting shards -- shared across all twenty rigs, and sized off whatever
		-- torso the builder above happened to make. Called AFTER the builder because it reads both
		-- `body.Size` and the `ctx.top` the builder may have raised.
		bossDetail(ctx, body)
	end

	-- The arena the rig stands in -- ground-level detail every boss gets regardless of which face
	-- its own builder gave it, and the thing that stops a 60-stud rig reading as hovering.
	--
	-- BUILT AS SCENERY, NOT AS PART OF THE BOSS. Everything `att` records while ctx.fixed is set is
	-- excluded from the re-pose that follows the rig's facing, so the dais, the kerb, the rune ring,
	-- the pylons and the banner masts stay planted where they were built. They used to turn with the
	-- boss -- four masts taller than the rig itself sweeping round the arena every time somebody
	-- walked past it, which reads as the ground rotating rather than as the monster looking at you.
	ctx.fixed = true
	arenaDetail(ctx)
	ctx.fixed = nil

	body.Name = "Body"
	body.CanCollide = true
	body.CFrame = ctx.origin
	model.PrimaryPart = body
	model:SetAttribute("BossRig", zone.key)
	return body, ctx.atts, ctx.top
end

-- ===== IDLE DRIVER ============================================================
-- buildRig hands back a flat list of attachments; this is what actually poses them. The rest
-- pose a rig is built in is dead still -- without this a boss is a pile of parts, and the
-- "swing"/"orbit"/"trail" motions each rig carefully sets up never happen.
--
-- One Heartbeat drives all 20 bosses, but a rig is only posed while somebody is near enough to
-- see it. Twenty rigs of ~25 parts is 500 CFrame writes a frame, and the zone strip is 12,000
-- studs long -- a player can only ever be looking at one of them. The near ones go through
-- BulkMoveTo, which is one engine call per boss instead of one per part.
local RIG_ANIMATE_RADIUS = 300
local rigs = {}

local function registerRig(model, origin, atts, outline)
	-- TWO LISTS, DRIVEN ON DIFFERENT SCHEDULES.
	-- `moving` is re-posed every frame a player is near, because that is what the idle animation is.
	-- `statics` were placed once by `att` and would never need touching again -- except that turning
	-- the rig moves them too, and leaving them behind would tear the boss apart: the head would
	-- swing round while the plinth, the horns and the banner masts stayed facing the old way.
	-- So they are kept, and re-posed ONLY on the frames the facing actually changed. A boss that has
	-- settled on its target costs exactly what it did before this existed.
	-- A third case sits underneath both: `a.fixed` parts (the arena) belong to the GROUND. Ones with
	-- no motion of their own are simply dropped here -- they were placed by `att` and nothing will
	-- ever move them again -- and the few that do animate (the banner cloth) are left in `moving`,
	-- where the driver poses them against `home` instead of the current facing.
	local moving, statics = {}, {}
	for _, a in ipairs(atts) do
		if a.motion then
			table.insert(moving, a)
		elseif not a.fixed then
			table.insert(statics, a)
		end
	end

	rigs[model] = {
		-- `origin` carries the CURRENT facing and is rewritten as the boss turns; `home` is the one
		-- it was built at and is what it settles back to once the last player leaves. Keeping both
		-- means the rest pose is never lost to whichever direction somebody last stood in.
		origin = origin,
		home = origin,
		atts = moving,
		parts = table.create(#moving),
		cframes = table.create(#moving),
		statics = statics,
		staticParts = table.create(#statics),
		staticCFrames = table.create(#statics),
		outline = outline,
	}
end

-- ===== HEALING BACK UP ========================================================
-- The same rule the creatures got, and it matters more here: a zone boss is what unlocks the next
-- gate, so "chip it, die, walk back, chip it again" was a way past every gate in the game that had
-- nothing to do with being strong enough to pass it. A boss nobody has touched for BOSS_REGEN_DELAY
-- closes the wound over BOSS_REGEN_TIME.
--
-- The delay is longer than the creatures' because a boss fight has longer pauses in it -- a player
-- backing out of the aura to let their own health come back is still in the fight. The walk back
-- from a spawn point is not, and that is the case this exists to close.
--
-- The event boss deliberately does NOT register here: it is a thing a whole server chips down
-- together over fifteen minutes and it already resets itself by withdrawing.
local BOSS_REGEN_DELAY = 14
local BOSS_REGEN_TIME = 20
local hurt = {} -- [model] = { max, hp, lastHit, draw, frozenUntil }

-- ===== WHAT A BOSS REVIVE REMEMBERS =====
--
-- [userId] = { model, hp, max, draw, name, t }. One entry per player, holding the LOWEST health
-- they have personally driven this boss to, and when. Written on every landed blow -- see onHit,
-- which is the only place all of those values are in scope at once.
--
-- Keyed by userId and holding the MODEL INSTANCE, not a zone key: a respawned boss is a brand new
-- model, so a stale snapshot is inert by construction rather than by a timestamp check (there is a
-- timestamp too, but it is the second line of defence, not the first).
--
-- The boss is SHARED -- `hurt` is keyed by model and Health is a model attribute, so two players on
-- one boss are chipping one pool. That is why restoring is clamped to "only ever lower, never
-- raise": if A revives while B is beating the same boss, B's damage is never undone. Without that
-- clamp this would be a heal button pointed at someone else's fight.
local reviveSnapshot = {}

local function driveBossRegen(dt)
	if not next(hurt) then return end
	local now = os.clock()
	for model, e in pairs(hurt) do
		if not model.Parent then
			hurt[model] = nil
		elseif now - e.lastHit >= BOSS_REGEN_DELAY and now >= (e.frozenUntil or 0) then
			-- the precise value lives on the entry; only the rounded one is published, or the
			-- rounding would eat every per-frame step and nothing would ever heal
			e.hp = math.min(e.hp + e.max * (dt / BOSS_REGEN_TIME), e.max)
			local shown = math.floor(e.hp)
			model:SetAttribute("Health", shown)
			e.draw(shown)
			if e.hp >= e.max then
				model:SetAttribute("Health", e.max)
				e.draw(e.max)
				hurt[model] = nil
			end
		end
	end
end

local function driveRigs(dt)
	-- ahead of the early return below: a boss left at 2 % has to heal back even when the player who
	-- hurt it has left the zone, which is the exact case this is for
	driveBossRegen(dt or (1 / 60))

	local anyone = false
	local positions = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			table.insert(positions, hrp.Position)
			anyone = true
		end
	end
	if not anyone then return end

	local t = os.clock()
	for model, rig in pairs(rigs) do
		if not model.Parent then
			rigs[model] = nil
		else
			local origin = rig.origin.Position
			local near = false
			-- ONE QUESTION NOW, NOT TWO: is anybody close enough for this rig to be worth animating.
			-- This used to also track the nearest player, because that was what the boss turned to
			-- face; with the turn gone (10.8) that search was pure cost on every boss every frame,
			-- and it could not stop early. This one breaks the moment it finds anyone in range.
			for _, p in ipairs(positions) do
				if (p - origin).Magnitude <= RIG_ANIMATE_RADIUS then
					near = true
					break
				end
			end

			-- Highlights are a hard-capped resource -- Roblox renders about 31 at once and silently
			-- drops the rest. Twenty bosses plus every player's pets would blow that budget and the
			-- outlines would start vanishing at random, so a boss only claims one while in range.
			if rig.outline and rig.outline.Enabled ~= near then
				rig.outline.Enabled = near
			end

			if near then
				-- ===== A BOSS DOES NOT TURN. IT IS FACED. =====
				--
				-- This used to track whoever was fighting it, within BOSS_TURN_RADIUS. That was a
				-- deliberate feature and it is now deliberately gone (10.8, owner's call): a zone boss
				-- is 75 to 121 studs of architecture standing at the head of its own arena, and a
				-- 121-stud statue swivelling to follow one player around reads as scenery on a
				-- turntable rather than as something enormous. The arena is built to be walked INTO --
				-- the rig, its disc and its banner masts are all authored facing the arrival gate --
				-- so the boss looking down the approach is the composition the whole space was made
				-- for, and it stays that way whichever way the player circles.
				--
				-- `want` is unconditionally `home`, rather than deleting the machinery below, and that
				-- is worth a line: the lerp-and-snap is what makes this SELF-HEALING. Any rig that is
				-- somehow off-facing -- a restart mid-turn on a live server, a future feature that
				-- rotates one -- walks back to the gate and then costs nothing, because the `> 1e-5`
				-- guard stops the re-pose the instant it settles. A boss that has never moved pays one
				-- Lerp and one comparison per frame and writes nothing.
				local want = rig.home
				-- Lerped rather than snapped: at these sizes an instant 90-degree turn reads as the
				-- rig teleporting. CFrame:Lerp carries the rotation and keeps the position, which is
				-- the same on both sides anyway.
				local turned = rig.origin:Lerp(want, math.min(1, (dt or 1 / 60) * BOSS_TURN_RATE))
				-- A LERP ONLY EVER APPROACHES ITS TARGET. Left alone this parks the rig about two
				-- degrees off whatever it was aiming at -- six studs of miss at arm's length -- and,
				-- worse, it never stops moving, so the statics below would be re-posed every frame for
				-- the rest of the boss's life. Close enough is snapped exactly on, which both fixes the
				-- aim and lets the next frame's delta fall to zero. 0.004 is about a fifth of a degree.
				if (want.LookVector - turned.LookVector).Magnitude < 0.004 then
					turned = want
				end
				-- ...so this only fires while the facing is actually changing. A boss that has settled
				-- costs exactly what it did before any of this existed.
				if (turned.LookVector - rig.origin.LookVector).Magnitude > 1e-5 then
					rig.origin = turned
					local parts, cframes = rig.staticParts, rig.staticCFrames
					for i, a in ipairs(rig.statics) do
						parts[i] = a.part
						cframes[i] = rig.origin * a.offset
					end
					if #parts > 0 then
						workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
					end
				end
			end

			if near and #rig.atts > 0 then
				local parts, cframes = rig.parts, rig.cframes
				for i, a in ipairs(rig.atts) do
					parts[i] = a.part
					-- motion sits BETWEEN joint and rest, so a limb turns about its shoulder
					-- rather than spinning around its own middle -- see the note on `att`.
					-- `home` for the arena pieces: they animate, but they do not follow the facing.
					cframes[i] = (a.fixed and rig.home or rig.origin) * a.pivot * motionOf(a, t) * a.rest
				end
				workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
end

-- ===== BOSS VFX ===============================================================
-- Two particle effects per boss, lifted off the pack in ReplicatedStorage.VFX: `body` wraps the
-- torso, `top` sits above it so the silhouette reads as haloed rather than just smoky. Colours
-- are only forced where the source effect is generic white (sparkles, charge, stars) -- the fire
-- and water effects keep their own gradients, which are better than a flat tint.
--
-- Everything routes through VFXService.Register: all 20 bosses exist at once across a 12,000-stud
-- strip, and a player can only ever see one of them.
local BOSS_VFX = {
	Forest          = { body = { "Anime/Wind-01" },           top = { "Anime/Stars-01", color = Color3.fromRGB(120, 220, 120) } },
	Desert          = { body = { "Anime/Wind-02", color = Color3.fromRGB(226, 200, 140) }, top = { "Anime/Smoke-01", color = Color3.fromRGB(214, 186, 128) } },
	Ocean           = { body = { "Anime/Water-01" },          top = { "Anime/Splash-01" } },
	Volcano         = { body = { "Anime/Fire-02" },           top = { "Anime/Smoke-01", color = Color3.fromRGB(70, 50, 45) } },
	Moon            = { body = { "Anime/Shiny-01", color = Color3.fromRGB(215, 215, 230) }, top = { "Anime/Stars-01", color = Color3.fromRGB(230, 230, 245) } },
	Mars            = { body = { "Anime/Smoke-01", color = Color3.fromRGB(180, 95, 60) },  top = { "Anime/Crack-01", color = Color3.fromRGB(220, 110, 70) } },
	Galaxy          = { body = { "Anime/Charge-01", color = Color3.fromRGB(150, 100, 230) }, top = { "Anime/Stars-01", color = Color3.fromRGB(170, 120, 245) } },
	BlackHole       = { body = { "Big/Ball-01", color = Color3.fromRGB(70, 20, 110) },     top = { "Anime/Portal-01", color = Color3.fromRGB(120, 50, 175) } },
	Multiverse      = { body = { "Anime/Charge-01", color = Color3.fromRGB(255, 100, 220) }, top = { "Anime/Portal-Enter-01", color = Color3.fromRGB(255, 130, 230) } },
	Nebula          = { body = { "Anime/Shiny-01", color = Color3.fromRGB(205, 130, 240) }, top = { "Anime/Stars-01", color = Color3.fromRGB(190, 110, 230) } },
	Wormhole        = { body = { "Big/Tornado-01", color = Color3.fromRGB(120, 80, 200) }, top = { "Anime/Portal-01", color = Color3.fromRGB(140, 95, 215) } },
	QuantumRealm    = { body = { "Anime/ForceField-01", color = Color3.fromRGB(90, 230, 230) }, top = { "Anime/Lighting-02", color = Color3.fromRGB(130, 245, 245) } },
	TimeRift        = { body = { "Anime/Charge-01", color = Color3.fromRGB(235, 195, 90) }, top = { "Anime/Shiny-01", color = Color3.fromRGB(248, 220, 130) } },
	AntimatterZone  = { body = { "Anime/Fire-03", color = Color3.fromRGB(255, 70, 70) },   top = { "Big/Explosion-01", color = Color3.fromRGB(255, 110, 90) } },
	DreamDimension  = { body = { "Anime/Smoke-01", color = Color3.fromRGB(160, 110, 220) }, top = { "Anime/Stars-01", color = Color3.fromRGB(210, 150, 255) } },
	MirrorUniverse  = { body = { "Anime/ForceField-01", color = Color3.fromRGB(225, 225, 255) }, top = { "Anime/Shiny-01", color = Color3.fromRGB(245, 245, 255) } },
	VoidExpanse     = { body = { "Anime/Smoke-01", color = Color3.fromRGB(55, 25, 85) },   top = { "Anime/Portal-01", color = Color3.fromRGB(140, 60, 220) } },
	CelestialThrone = { body = { "Anime/Shiny-01", color = Color3.fromRGB(255, 225, 140) }, top = { "Anime/Stars-01", color = Color3.fromRGB(255, 238, 175) } },
	Singularity     = { body = { "Big/Ball-01", color = Color3.fromRGB(255, 255, 255) },   top = { "Anime/Lighting-01", color = Color3.fromRGB(235, 235, 255) } },
	AbsolutePlane   = { body = { "Anime/Charge-01", color = Color3.fromRGB(255, 215, 0) }, top = { "Big/Lighting-01", color = Color3.fromRGB(255, 235, 130) } },
}

-- The pack is authored for a 5-stud R6 dummy; bosses run 18-60, so effects are scaled off body
-- size or they disappear inside the rig entirely.
local function bossVfxScale(boss)
	return boss.size / 9
end

-- Hangs the zone's aura on the boss body and returns the attachments, so the click handler can
-- pulse them on a hit. Returns an empty list for any zone without an entry rather than erroring:
-- a boss with no aura is a cosmetic gap, not a reason to fail the spawn.
--
-- `top` is the rig's own height, so the upper effect crowns whatever silhouette the rig actually
-- has instead of floating at a fixed fraction of body size through a wing or a halo.
local function applyBossVFX(body, zone, boss, top)
	local spec = BOSS_VFX[zone.key]
	if not spec then return {} end

	local scale = bossVfxScale(boss)
	local atts = {}

	for slot, offset in pairs({ body = 0, top = top * 0.75 }) do
		local entry = spec[slot]
		if entry and VFXLibrary.Exists(entry[1]) then
			local att = VFXLibrary.Attach(body, entry[1], {
				name = "BossVFX_" .. slot,
				offset = Vector3.new(0, offset, 0),
				scale = scale,
				-- Normalised, not multiplied: the pack ranges from Smoke-01 at 5 particles/second to
				-- Ball-01 at 427, so a multiplier would make half the bosses bare and half opaque.
				-- Richer than ambient decor -- the boss is what the player is looking at, and the
				-- proximity gate means only the one they stand next to is ever simulating.
				targetRate = slot == "body" and 55 or 30,
				color = entry.color,
			})
			if att then
				table.insert(atts, att)
				VFXService.Register(att, body.Position, 260)
			end
		end
	end

	return atts
end

-- The death blast. Parented to the folder rather than the model because the model is destroyed
-- on the same frame; VFXLibrary.BurstAt cleans the leftover carrier up on a Debris timer.
local function burstOnDeath(parent, zone, boss, position)
	local path = "Big/Explosion-01"
	if not VFXLibrary.Exists(path) then return end
	VFXLibrary.BurstAt(parent, path, CFrame.new(position), {
		name = "BossDeath_" .. zone.key,
		scale = bossVfxScale(boss) * 1.4,
		color = zone.accentColor,
		count = 40,
		lifetime = 5,
	})
end

local function spawnBoss(zone)
	local boss = zone.boss
	if not boss then return end

	local position = Vector3.new(zone.offset, 0, 0) + BOSS_RELATIVE_OFFSET + Vector3.new(0, boss.size * 0.55, 0)
	-- Built facing +Z, i.e. back up the street toward the arrival gate, so the first thing a player
	-- coming into the zone sees is the boss's face. The rigs are authored facing local -Z and the
	-- street runs down -Z, so an unrotated origin pointed every one of them at the exit instead.
	local origin = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))

	local model = Instance.new("Model")
	model.Name = "Boss_" .. zone.key

	-- The zone's hand-built rig -- animal, golem, wraith or throne, depending on how far down the
	-- strip you are. `top` is how high above the body the finished silhouette reaches, which is
	-- what the name plate hangs off.
	local body, atts, top = buildRig(model, origin, zone, boss)

	-- The last few rigs are far wider than their bodies -- the Absolute's sunburst beams and the
	-- Singularity's collapsing rings orbit well past the torso -- and at these sizes the widest of
	-- them hung 12 studs off the platform. Measure what actually got built and pull it back inside
	-- rather than deriving a clearance from boss.size, which would guess wrong the moment a rig
	-- gains an outer ring.
	local builtCF, builtSize = model:GetBoundingBox()
	local overhangX = (math.abs(builtCF.Position.X - zone.offset) + builtSize.X * 0.5) - PLATFORM_HALF_X
	-- ...and the same measurement again toward the gate, now that the arena stands on the street:
	-- the widest rigs would otherwise plant their banner masts in the portal's own steps.
	local overhangZ = GATE_APPROACH_Z - (builtCF.Position.Z - builtSize.Z * 0.5)
	local shift = Vector3.new(
		overhangX > 0 and -(overhangX + EDGE_MARGIN) or 0,
		0,
		overhangZ > 0 and (overhangZ + EDGE_MARGIN) or 0
	)
	if shift.Magnitude > 0 then
		model:TranslateBy(shift)
		-- the idle driver poses off this origin, so it has to move too
		position += shift
		origin = origin + shift
	end

	-- The same thick dark rim the pets wear (see ReplicatedStorage.Modules.PetModel). Occluded
	-- rather than always-on-top, so a boss behind a zone wall does not glow through it. Starts
	-- off; driveRigs switches it on for whichever boss the player is actually near.
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Enabled = false
	outline.Parent = model

	registerRig(model, origin, atts, outline)

	-- One hit box around the whole rig rather than a ClickDetector on the torso. A boss is mostly
	-- limbs, wings, haloes and orbiting rubble, and at these sizes the torso is a small target in
	-- the middle of all of it -- without this you have to hunt for the one block that responds.
	--
	-- SQUARED OFF ON THE GROUND PLANE and left unrotated, because the rig turns to face whoever is
	-- fighting it: a box cut to the rig's exact depth would stop covering the arms the moment it
	-- swung side-on. Using the larger of the two horizontal extents costs a little dead space at
	-- the corners and never leaves a limb unclickable.
	local boxCF, boxSize = model:GetBoundingBox()
	local span = math.max(boxSize.X, boxSize.Z)
	local hitbox = Instance.new("Part")
	hitbox.Name = "HitBox"
	hitbox.Size = Vector3.new(span, boxSize.Y, span)
	hitbox.CFrame = CFrame.new(boxCF.Position)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true -- it exists precisely to catch the mouse ray
	hitbox.Parent = model

	-- A PRIMITIVE RIG IS SOLID TOO. The generated bosses get their collision volume inside
	-- meshRig; the twenty hand-built ones hang everything off `body`, which buildRig makes
	-- collidable -- but `body` is one block in the middle of a rig made mostly of limbs, so the
	-- legs and the chest were walk-through in exactly the same way. Only added when meshRig did not
	-- already do it, so a generated boss does not end up with two.
	if not model:FindFirstChild("BossCollision") then
		local collide = Instance.new("Part")
		collide.Name = "BossCollision"
		collide.Size = Vector3.new(boxSize.X * 0.58, boxSize.Y, boxSize.Z * 0.58)
		collide.CFrame = CFrame.new(boxCF.Position)
		collide.Transparency = 1
		collide.Anchored = true
		collide.CanCollide = true
		collide.CanQuery = false -- see the note in meshRig: it must never answer the combat ray
		collide.CanTouch = false
		collide.CastShadow = false
		collide.Parent = model
	end

	-- Boss plate, routed through UITheme so it carries the same outline/gradient/gloss/shadow as
	-- every panel in MainUI. LightInfluence = 0 matters here: half the late zones (Black Hole,
	-- Void Expanse, Singularity) are lit almost to black, and a light-influenced billboard goes
	-- unreadable exactly where the hardest bosses stand.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossPlate"
	billboard.Size = UDim2.new(0, 300, 0, 110)
	-- off the rig's own height, not a guess from boss.size: the tall rigs (throne, monolith,
	-- singularity) reach well past one body and would wear their name plate through the chest
	billboard.StudsOffset = Vector3.new(0, top + boss.size * 0.18, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	-- a 60-stud boss has to be legible from further away than a 10-stud ball did
	billboard.MaxDistance = 140 + boss.size * 4
	billboard.Parent = body

	UITheme.Card(billboard, {
		name = "NamePlate",
		size = UDim2.new(1, -10, 0, 52),
		position = UDim2.new(0.5, 0, 0, 0),
		anchorPoint = Vector2.new(0.5, 0),
		color = UITheme.Color.Gold,
		icon = "👑",
		text = boss.emoji .. " " .. boss.name,
		maxTextSize = 22,
	})

	local _, barFill, barLabel = UITheme.ProgressBar(billboard, {
		name = "HealthBar",
		size = UDim2.new(1, -26, 0, 34),
		position = UDim2.new(0.5, 0, 1, -4),
		anchorPoint = Vector2.new(0.5, 1),
		color = UITheme.Color.Red,
		progress = 1,
		text = formatNumber(boss.health) .. " / " .. formatNumber(boss.health),
		maxTextSize = 18,
	})

	-- measured from the hit box centre, so it has to clear the rig's own half-width before a
	-- player standing at its feet is in range at all
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = math.max(16, boss.size * 0.75)
	clickDetector.Parent = hitbox

	model:SetAttribute("Health", boss.health)
	model.Parent = bossesFolder

	local vfxAtts = applyBossVFX(body, zone, boss, top)

	local dead = false
	local lastHitByPlayer = {}
	local auraConnection
	local restSize = body.Size

	if boss.auraRange and boss.auraRange > 0 then
		-- The configured ranges (12-20) were tuned against 10-32 stud balls. A 52-stud Void
		-- Colossus is wider than its own aura, so a player could stand against its leg and take
		-- nothing: the damage field has to clear the body before it can threaten anybody.
		local auraRange = math.max(boss.auraRange, boss.size * 0.85)
		local accum = 0
		auraConnection = RunService.Heartbeat:Connect(function(dt)
			if dead or not model.Parent then return end
			accum += dt
			if accum < boss.auraInterval then return end
			accum = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				local character = plr.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				-- THE AURA HONOURS THE SAME GATE THE HITS DO.
				--
				-- `minStageIndex` exists so "a player under this stage can walk in and watch" -- that is
				-- the comment on it in GameConfig. onHit checked it; this loop never did. The Colosseum
				-- gate is directly behind the Forest spawn, so a brand-new player wandering over to look
				-- at the giant took 60-110 damage every 1.4 seconds against 100 max health and died to
				-- something they had no way to fight, twice, before working out what was hitting them.
				local plrData = PlayerDataService.Get(plr)
				if hrp and (plrData and plrData.StageIndex or 1) >= (boss.minStageIndex or 1)
					and (hrp.Position - body.Position).Magnitude <= auraRange then
					-- the same fight length the retaliation is held to, computed off the same two
					-- numbers, so the aura and the blows cannot disagree about how long this is
					local plrDamage = DNAService.GetCombatDamage(plrData)
						/ GameConfig.GetBossDamageDivisor(plrData)
					hurtPlayer(plr, math.random(boss.auraDamage[1], boss.auraDamage[2]),
						blowsToFell(boss.health, plrDamage))
				end
			end
		end)
	end

	-- the one place the plate is written, so a hit and a regen tick can never disagree about it
	local function drawHealth(health)
		barFill.Size = UDim2.new(math.clamp(health / boss.health, 0, 1), 0, 1, 0)
		barLabel.Text = formatNumber(health) .. " / " .. formatNumber(boss.health)
	end

	-- the reach the remote below is held to, hoisted so the click path can be held to it too --
	-- a ClickDetector's MaxActivationDistance is enforced on the client and proves nothing here
	local strikeReach = math.max(30, boss.size * 1.1)

	local function onHit(player)
		if dead or not model.Parent then return end
		-- alive, and standing in front of it. See the longer note in CreatureService.onHit.
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp) or humanoid.Health <= 0 then return end
		if (hrp.Position - body.Position).Magnitude > strikeReach then return end
		local data = PlayerDataService.Get(player)
		if not data then return end
		if data.StageIndex < zone.unlockStageIndex then
			Remotes.Notify:FireClient(player, { kind = "error", message = "You're too weak for " .. boss.name .. " yet!" })
			return
		end
		local now = os.clock()
		if lastHitByPlayer[player.UserId] and now - lastHitByPlayer[player.UserId] < 0.25 then
			return
		end
		lastHitByPlayer[player.UserId] = now

		-- UNCLAMPED, like the creatures. `math.min(..., boss.health / BOSS_MIN_HITS)` stood here and
		-- it made every boss in the game a twelve-hit fight -- the first one and the last one, for a
		-- fresh save and for a player eight rebirths deep. The bar moved a twelfth per blow whatever
		-- was thrown at it, which is the same defect the creature `damageCap` had: the cap was the
		-- damage, so no progression could ever show against a boss either.
		--
		-- What replaces it is arithmetic rather than a clamp: boss health is now DERIVED from the
		-- damage ladder at `GameConfig.BossTargetHits` blows for the zone it guards, so a boss is
		-- roughly sixty swings for a player who has just arrived and fewer for one who has geared.
		-- See the BOSS HEALTH IS DERIVED block in GameConfig.
		--
		-- Divided by the player's own rebirth multiplier (14.1). The blow a creature takes is
		-- untouched; only a boss asks what a reset was worth, and the answer is "nothing, so that
		-- the fight survives one". The reasoning, and why it is a divisor here rather than a
		-- multiplier on the health, is written out over GameConfig.GetBossDamageDivisor.
		-- floored, and floored at 1: the divisor keeps the health attribute an integer the way every
		-- other write to it is, and a rebirth deep enough to round a blow to zero would be a boss
		-- that cannot be hurt at all
		local playerDamage = math.max(
			math.floor(DNAService.GetCombatDamage(data) / GameConfig.GetBossDamageDivisor(data)), 1)
		local health = math.max((model:GetAttribute("Health") or boss.health) - playerDamage, 0)
		model:SetAttribute("Health", health)
		drawHealth(health)

		-- THE BAR YOU CAN ACTUALLY SEE WHILE FIGHTING.
		--
		-- The overhead plate hangs at `top + boss.size * 0.18` -- around 145 studs up on the Forest
		-- bear -- which is right when you are walking toward it and useless the moment you are close
		-- enough to hit it, because at that range it is off the top of the screen. Lowering it does
		-- not work either: a plate low enough to see from the feet is buried inside the rig.
		--
		-- So the fight gets a screen-space bar, the way every game with a boss in it does it. Sent
		-- only to the player who landed the blow and only while they are fighting -- a bar across the
		-- top of the screen for somebody else's fight is chrome.
		CombatFx:FireClient(player, {
			k = "bossBar",
			name = boss.emoji .. " " .. boss.name,
			hp = health,
			max = boss.health,
		})

		-- re-armed on every blow, not only the first: `lastHit` is what keeps the healing off while
		-- the fight is still going on
		if health > 0 then
			local entry = hurt[model]
			if entry then
				entry.hp = health
				entry.lastHit = now
			else
				hurt[model] = { max = boss.health, hp = health, lastHit = now, draw = drawHealth }
			end

			-- The revive snapshot, written here because this is the one place the model, the health,
			-- the bar's own draw function and the boss's name are all in scope together.
			--
			-- It keeps the LOWEST health this player has driven THIS model to, not the latest. The
			-- difference is the whole feature: a player who died at 40 %, walked back and landed one
			-- blow on a boss that had healed to 99 % would otherwise have overwritten their own best
			-- with a worse number a fraction of a second before deciding to buy.
			local snap = reviveSnapshot[player.UserId]
			if snap and snap.model == model then
				snap.hp = math.min(snap.hp, health)
				snap.t = now
			else
				reviveSnapshot[player.UserId] = {
					model = model, hp = health, max = boss.health, draw = drawHealth,
					name = boss.emoji .. " " .. boss.name, t = now,
				}
			end
		end

		-- flinch off the torso's own dimensions: a rig body is a slab or an egg, not the cube the
		-- old placeholder ball was, and tweening it toward a cube visibly deformed it
		local grow = TweenService:Create(body, TweenInfo.new(0.08), { Size = restSize * 1.06 })
		grow:Play()
		task.delay(0.08, function()
			if body and body.Parent then
				TweenService:Create(body, TweenInfo.new(0.1), { Size = restSize }):Play()
			end
		end)

		-- a puff off the aura on every hit, so damage reads on the boss and not only on the bar
		for _, att in ipairs(vfxAtts) do
			VFXLibrary.Burst(att, 6)
		end

		-- and the swing, the spark and the damage number, drawn on every nearby client. A boss took
		-- damage identically to a creature and showed none of the same feedback, so a player who had
		-- just learned what a hit looks like out on the platform got nothing back from the fight that
		-- actually matters.
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local knockDir = Vector3.new(0, 0, 1)
		if hrp then
			local flat = Vector3.new(body.Position.X - hrp.Position.X, 0, body.Position.Z - hrp.Position.Z)
			if flat.Magnitude > 0.1 then
				knockDir = flat.Unit
			end
		end
		broadcastFx({
			k = health > 0 and "hit" or "kill",
			p = body.Position - knockDir * (boss.size * 0.4),
			d = math.floor(playerDamage + 0.5),
			dna = health > 0 and nil or boss.dnaReward,
			a = player.UserId,
			-- capped: the spark is authored against a creature and a 124-stud event boss would throw
			-- shards the size of the arena
			s = math.min(boss.size * 0.5, 34),
			c = UITheme.Color.Gold,
			n = knockDir,
		})

		if health > 0 and math.random() < boss.retaliateChance then
			hurtPlayer(player, math.random(boss.retaliateDamage[1], boss.retaliateDamage[2]),
				blowsToFell(boss.health, playerDamage))
		end

		if health <= 0 and not dead then
			dead = true
			if auraConnection then auraConnection:Disconnect() end

			data.DNA += boss.dnaReward
			-- half a level for THIS zone's stage -- GameConfig derives it, because a flat 25 was a third
			-- of the first level and a rounding error by the tenth
			data.XP = (data.XP or 0) + math.floor((boss.xpReward or 25) * GameConfig.GetXPMult(data))
			-- counted before markDefeated, which is what pushes. Note this fires on EVERY kill, not
			-- only the first: markDefeated is idempotent per zone, but the quest asks for a number of
			-- bosses beaten, and a boss that respawns is a boss you can beat again.
			-- DIAMONDS. A boss had no diamond source at all, so the hardest fight in a zone paid less
			-- of this currency than farming Swarmers did. Guaranteed rather than rolled: a boss is a
			-- scheduled, expensive fight and a 1-in-N payout on something you meet once every 45
			-- seconds reads as nothing happening. Credited BEFORE markDefeated, which is what pushes.
			local gems = GameConfig.RollBossDiamonds(false)
			data.Diamonds = (data.Diamonds or 0) + gems
			SeasonPassService.Track(player, "bosses", 1)
			-- a boss is a kill too, and counts on the same lifetime board (5.3)
			data.Kills = (data.Kills or 0) + 1
			-- The other of the two places XP enters a save, so the other half of 10.10's auto-evolve.
			-- It matters most here: a boss pays 25+ XP against a creature's 1, so a boss kill is the
			-- likeliest single event to fill the bar -- and it is the one a player is most obviously
			-- watching. Before markDefeated, which pushes, so the payload already carries the new rung.
			DNAService.AutoEvolveIfReady(player)
			-- READ BEFORE markDefeated, which is the only moment it is knowable (12.14). That
			-- function inserts the zone key and is idempotent per zone, so one line later a first
			-- clear and a thousandth are the same save. AnnounceService owns what to do with it --
			-- including the zone floor, which it derives for itself.
			local firstClear = not hasDefeated(data, zone.key)
			markDefeated(player, data, zone.key)
			Remotes.Notify:FireClient(player, { kind = "bossDefeated", name = boss.name, amount = boss.dnaReward, diamonds = gems })
			AnnounceService.BossKilled(player, boss, zone.key, firstClear)

			burstOnDeath(bossesFolder, zone, boss, body.Position)
			hitHandlers[model] = nil
			hurt[model] = nil
			-- A dead boss is nobody's saved progress. Swept for every player, not just the killer: the
			-- ones who softened it up hold snapshots too, and a charge spent on a corpse is a refund
			-- request. (The model check in TryConsumeRevive would catch it a moment later anyway --
			-- this is the same answer arrived at deliberately rather than by accident.)
			for userId, snap in pairs(reviveSnapshot) do
				if snap.model == model then reviveSnapshot[userId] = nil end
			end
			model:Destroy()
			task.delay(boss.respawnDelay or 45, function()
				spawnBoss(zone)
			end)
		end
	end

	clickDetector.MouseClick:Connect(onHit)
	-- and the same function by name for auto-attack. The reach is measured from the hit box centre
	-- to the player's root, so it has to clear the rig's own half-width before anyone standing at
	-- its feet counts as in range at all.
	hitHandlers[model] = { fn = onHit, body = body, reach = strikeReach }

	return model
end

-- ===== THE EVENT BOSS =========================================================
-- One enormous boss standing on the dais in the Colosseum, back every 30 minutes whether or not
-- the last one was beaten. It reuses the whole rig pipeline above -- the same buildRig, the same
-- idle driver, the same VFX and name plate -- by handing it a synthetic "zone": that is all a rig
-- needs, and writing a second one would mean maintaining two.
--
-- Three things make it an event rather than a twenty-first boss:
--   * it is far too much health for one player, so it is a thing a server does together;
--   * every player who landed a hit is paid in full when it dies, not just the one who finished
--     it -- an event that pays less the more people turn up is an event nobody turns up to;
--   * it does not gate anything. Nothing in GameConfig.requiresBossKey points at it, so missing
--     one costs a player nothing but the DNA.

local EVENT_MODEL_NAME = "Boss_Event"
local eventState = { nextSpawn = 0, model = nil }

-- The synthetic zone. `unlockStageIndex` is what spawnBoss checks before letting a player hit it,
-- and `offset`/`accentColor` drive the palette and the edge clamp.
local function eventZone()
	local arena = GameConfig.EventArena
	return {
		key = arena.key,
		name = arena.name,
		emoji = arena.emoji,
		offset = arena.centre.X,
		accentColor = arena.accentColor,
		groundColor = arena.groundColor,
		unlockStageIndex = GameConfig.EventBoss.minStageIndex,
		boss = GameConfig.EventBoss,
		-- the Antimatter Horror's rig: all teeth, spines and burning cracks, which is the one in the
		-- set that reads as a devourer rather than as a beast or a monument
		rigKey = "AntimatterZone",
	}
end

-- THROUGH AnnounceService NOW (12.14), not through a loop over Players firing Notify.
--
-- The old version was a hand-rolled FireAllClients wearing a Notify card, which meant the Colosseum
-- -- the one thing in this game a whole server does together -- was the only server-wide
-- announcement that did not go through the module that exists to make those. Two things follow from
-- the move: 5.4 will carry it between servers for free, because `Broadcast` is the single send; and
-- it draws as the same top-of-screen toast an event opening and a cross-server hatch do, so the
-- three server-wide messages a player can see all look like each other instead of like three
-- features. `kind = "reward"` also gave it a cash register on arrival, which was never right for a
-- giant walking into an arena.
--
-- The headline/subline split is the toast's own shape. `sound` is optional and only the arrival
-- names one -- see the note at each call.
-- THE ARENA IS RED, and that was decided by looking at the feed rather than at the palette. The
-- first cut painted the arrival gold, which is also the rebirth's colour -- and the two cards sit in
-- the same 3-high stack, so a rebirth during a Colosseum window drew two identical gold blocks that
-- read as one repeated message. Every kind in the feed now owns a hue nobody else uses: Apex purple,
-- boss-first orange, rebirth gold, the arena red, and the withdrawal the muted grey below.
local function announce(headline, subline, color, sound)
	AnnounceService.Broadcast({
		kind = "colosseum",
		color = color or UITheme.Color.Red,
		headline = headline,
		subline = subline or "",
		sound = sound,
	})
end

local function despawnEventBoss()
	if eventState.model then
		-- the withdrawal path as well as the death path: a boss that leaves on its timer must not
		-- leave an auto-attack handler pointing at a destroyed model
		hitHandlers[eventState.model] = nil
		if eventState.model.Parent then
			eventState.model:Destroy()
		end
	end
	eventState.model = nil
end

local function spawnEventBoss()
	despawnEventBoss()

	local zone = eventZone()
	local boss = zone.boss
	local arena = GameConfig.EventArena
	local position = arena.centre + Vector3.new(0, 8 + boss.size * 0.55, 0)
	-- The Colosseum's gate is on the +Z rim (ZoneBuilder's PortalGate at z = 1182 against a centre
	-- of 1400), so the giant faces +Z too -- toward the mouth every challenger walks in through.
	-- It turns to track them once they are on the sand; this is only where it starts.
	local origin = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))

	local model = Instance.new("Model")
	model.Name = EVENT_MODEL_NAME

	local body, atts, top = buildRig(model, origin, zone, boss)

	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Enabled = false
	outline.Parent = model
	registerRig(model, origin, atts, outline)

	-- squared off and unrotated for the same reason the zone bosses' box is -- see spawnBoss
	local boxCF, boxSize = model:GetBoundingBox()
	local span = math.max(boxSize.X, boxSize.Z)
	local hitbox = Instance.new("Part")
	hitbox.Name = "HitBox"
	hitbox.Size = Vector3.new(span, boxSize.Y, span)
	hitbox.CFrame = CFrame.new(boxCF.Position)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossPlate"
	billboard.Size = UDim2.new(0, 420, 0, 150)
	billboard.StudsOffset = Vector3.new(0, top + boss.size * 0.2, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	-- readable from the gate on the far rim, which is the whole width of the arena away
	billboard.MaxDistance = 900
	billboard.Parent = body

	UITheme.Card(billboard, {
		name = "NamePlate",
		size = UDim2.new(1, -10, 0, 72),
		position = UDim2.new(0.5, 0, 0, 0),
		anchorPoint = Vector2.new(0.5, 0),
		color = UITheme.Color.Red,
		icon = "\u{2694}\u{FE0F}",
		text = boss.emoji .. " " .. boss.name,
		maxTextSize = 30,
	})

	local _, barFill, barLabel = UITheme.ProgressBar(billboard, {
		name = "HealthBar",
		size = UDim2.new(1, -26, 0, 46),
		position = UDim2.new(0.5, 0, 1, -4),
		anchorPoint = Vector2.new(0.5, 1),
		color = UITheme.Color.Red,
		progress = 1,
		text = formatNumber(boss.health) .. " / " .. formatNumber(boss.health),
		maxTextSize = 24,
	})

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = math.max(24, boss.size * 0.8)
	clickDetector.Parent = hitbox

	model:SetAttribute("Health", boss.health)
	model.Parent = bossesFolder
	eventState.model = model

	local vfxAtts = applyBossVFX(body, { key = "AntimatterZone", accentColor = zone.accentColor }, boss, top)

	local dead = false
	local lastHitByPlayer = {}
	local contributors = {} -- [userId] = true; everyone here is paid when it dies
	local restSize = body.Size

	local auraConnection
	do
		local auraRange = math.max(boss.auraRange, boss.size * 0.7)
		local accum = 0
		auraConnection = RunService.Heartbeat:Connect(function(dt)
			if dead or not model.Parent then return end
			accum += dt
			if accum < boss.auraInterval then return end
			accum = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				local character = plr.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - body.Position).Magnitude <= auraRange then
					-- the arena's own EVENT_MIN_HITS floor, mirrored here: this loop has no `data`
					-- of its own and the clamp is what the fight length is bounded by anyway
					hurtPlayer(plr, math.random(boss.auraDamage[1], boss.auraDamage[2]), EVENT_MIN_HITS)
				end
			end
		end)
	end

	local strikeReach = math.max(34, boss.size * 1.05)

	local function onHit(player)
		if dead or not model.Parent then return end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp) or humanoid.Health <= 0 then return end
		if (hrp.Position - body.Position).Magnitude > strikeReach then return end
		local data = PlayerDataService.Get(player)
		if not data then return end
		if (data.StageIndex or 1) < boss.minStageIndex then
			Remotes.Notify:FireClient(player, { kind = "error", message = "You're far too weak for " .. boss.name .. "!" })
			return
		end
		local now = os.clock()
		if lastHitByPlayer[player.UserId] and now - lastHitByPlayer[player.UserId] < 0.25 then return end
		lastHitByPlayer[player.UserId] = now
		contributors[player.UserId] = true

		-- the event boss is a thing a whole server does together, so it gets a much higher floor
		local playerDamage = math.min(DNAService.GetCombatDamage(data), boss.health / EVENT_MIN_HITS)
		local health = math.max((model:GetAttribute("Health") or boss.health) - playerDamage, 0)
		model:SetAttribute("Health", health)
		barFill.Size = UDim2.new(math.clamp(health / boss.health, 0, 1), 0, 1, 0)
		-- the same screen-space bar the zone bosses got -- see the note in the zone boss onHit
		CombatFx:FireClient(player, {
			k = "bossBar",
			name = boss.emoji .. " " .. boss.name,
			hp = health,
			max = boss.health,
		})
		barLabel.Text = formatNumber(health) .. " / " .. formatNumber(boss.health)

		TweenService:Create(body, TweenInfo.new(0.08), { Size = restSize * 1.05 }):Play()
		task.delay(0.08, function()
			if body and body.Parent then
				TweenService:Create(body, TweenInfo.new(0.1), { Size = restSize }):Play()
			end
		end)
		for _, att in ipairs(vfxAtts) do
			VFXLibrary.Burst(att, 8)
		end

		if health > 0 and math.random() < boss.retaliateChance then
			-- EVENT_MIN_HITS already floors this at 40 blows, so the arena's fight length is bounded
			-- from below whatever the player brings; the cap is still computed from the real number
			-- rather than from the constant, because a shared target is longer for a lone player
			hurtPlayer(player, math.random(boss.retaliateDamage[1], boss.retaliateDamage[2]),
				blowsToFell(boss.health, playerDamage))
		end

		if health <= 0 and not dead then
			dead = true
			if auraConnection then auraConnection:Disconnect() end

			local paid = 0
			-- ===== THE WEEKEND COLOSSEUM'S DOUBLE (12.13) =====
			--
			-- Read ONCE, outside the loop, and that is not micro-optimisation: it is the same
			-- multiplier for everybody who was in this fight, by definition -- GetEventMult takes no
			-- `data`, which is the whole difference between an event and a pass. Reading it per player
			-- would also let a window that shut mid-loop pay the first contributor double and the last
			-- one single, for the same kill.
			--
			-- It multiplies the giant's own payout and nothing else. Weekend Rush's incomeMult never
			-- reached here (this is a flat reward, not click income), so the two do not compound into
			-- a 4x weekend.
			local eventBossMult = GameConfig.GetEventMult("bossMult")
			for _, plr in ipairs(Players:GetPlayers()) do
				if contributors[plr.UserId] then
					local d = PlayerDataService.Get(plr)
					if d then
						d.DNA += boss.dnaReward * eventBossMult
						-- CLAMPED TO TWO OF THE RECEIVER'S OWN LEVELS. The event boss pays a flat 20,000 so
						-- that it is worth turning up to at any stage, but the XP curve spans four orders of
						-- magnitude -- unclamped, a stage-2 player who lands a single hit banks enough to
						-- skip half the evolution chain.
						local dStage = GameConfig.Stages[d.StageIndex]
						local dCap = (dStage and dStage.xpCost ~= math.huge) and dStage.xpCost * 2 or boss.xpReward
						d.XP = (d.XP or 0) + math.floor(math.min(boss.xpReward, dCap) * GameConfig.GetPotionMult(d, "xp"))
						-- the Colosseum giant counts for the same quest as a zone boss
						-- the giant's own diamond band, several times a zone boss's: it is on a 30-minute
						-- timer and turning up for it is the point. Credited before the push below.
						-- Diamonds are an integer currency everywhere else in this file, so the doubled
						-- roll is floored rather than left as a float -- a fractional gem would reach
						-- the HUD, the save and eventually the OrderedDataStore, which refuses floats
						-- silently. `math.floor` and not `math.round`: the mult is 1 or 2 today, and
						-- rounding a whole number is a no-op either way, but flooring cannot invent a
						-- gem out of a future 1.5.
						local gems = math.floor(GameConfig.RollBossDiamonds(true) * eventBossMult)
						d.Diamonds = (d.Diamonds or 0) + gems
						SeasonPassService.Track(plr, "bosses", 1)
						d.Kills = (d.Kills or 0) + 1
						PlayerDataService.UpdateLeaderstats(plr)
						PlayerDataService.PushToClient(plr)
						-- the card quotes what was actually paid, doubled included, rather than the
						-- authored figure -- a "you got 20,000" toast beside a 40,000 balance jump is
						-- the event failing to be visible at the one moment it is happening
						Remotes.Notify:FireClient(plr, { kind = "bossDefeated", name = boss.name, amount = boss.dnaReward * eventBossMult, diamonds = gems })
						paid += 1
					end
				end
			end
			-- No sound named: everyone who was in the fight already gets `bossDeath` off their own
			-- `bossDefeated` card a few lines up, and a second sting on top of it is one boss dying
			-- twice.
			-- the lighter end of the arena's own red: the same event, resolved
			announce(
				("%s %s HAS FALLEN!"):format(boss.emoji, boss.name:upper()),
				("%d challenger%s paid"):format(paid, paid == 1 and "" or "s"),
				UITheme.Color.Coral)

			burstOnDeath(bossesFolder, zone, boss, body.Position)
			hitHandlers[model] = nil
			despawnEventBoss()
		end
	end

	clickDetector.MouseClick:Connect(onHit)
	hitHandlers[model] = { fn = onHit, body = body, reach = strikeReach }

	-- The one announcement in the game that is a CALL TO ACTION rather than a report: the giant is
	-- standing on the dais for a bounded number of seconds and a player reading their inventory has
	-- to look up. That is what earns it a sound where the other two get none.
	announce(
		("%s %s HAS ENTERED THE COLOSSEUM!"):format(boss.emoji, boss.name:upper()),
		"Get to the arena -- it will not wait",
		UITheme.Color.Red, "levelUp")

	-- it leaves on its own if nobody finishes it, so a dead server never leaves a corpse standing
	-- on the dais until the next spawn
	task.delay(boss.despawnSeconds, function()
		if eventState.model == model and not dead then
			despawnEventBoss()
			-- Muted deliberately, and in the Locked grey rather than the gold: nothing happened. It is
			-- said at all only so a player who saw the arrival is not left wondering whether the
			-- fight is still on somewhere.
			announce(
				("%s %s HAS WITHDRAWN"):format(boss.emoji, boss.name:upper()),
				"Nobody finished it -- the next one is on the board",
				UITheme.Color.Locked)
		end
	end)

	return model
end

-- Rewrites the board over the arena entrance once a second. It is the only thing telling a player
-- whether it is worth waiting, so it says either how long is left or that the fight is on.
local function driveCountdown()
	local boss = GameConfig.EventBoss
	local live = eventState.model ~= nil and eventState.model.Parent ~= nil
	local hp = live and (eventState.model:GetAttribute("Health") or 0) or 0
	local left = math.max(eventState.nextSpawn - os.clock(), 0)

	-- ===== PUBLISHED TO EVERY CLIENT, NOT JUST TO THE BOARD (11.20) =====
	--
	-- The board hangs over the arena entrance, so the only player it can inform is one who has
	-- already walked to the arena -- which is backwards: the countdown exists to make somebody
	-- decide to GO. Attributes on ReplicatedStorage rather than a remote, the same no-request trick
	-- 5.7's GlobalStats and 7.1's LiveEvents use: a client that joins late reads the current value
	-- for free and there is no handler to answer.
	--
	-- SECONDS REMAINING, NOT A TIMESTAMP, and that is what makes it immune to the clock problem 7.1
	-- had to solve with SetEventClock. `eventState.nextSpawn` is `os.clock()`, which is monotonic
	-- time since THIS server process started and is meaningless on any other machine; publishing it
	-- raw would have every client counting down to a moment in its own past. A remainder is the same
	-- number everywhere. It is republished every second, which is exactly the granularity of the
	-- mm:ss the HUD draws, so the client never has to interpolate.
	--
	-- BEFORE the board lookup below, deliberately. That lookup returns early when the arena has not
	-- been built yet -- and a HUD strip that silently never appears because a sign is missing in
	-- another zone is precisely the class of failure this row is fixing.
	RS:SetAttribute("ArenaBossLive", live)
	RS:SetAttribute("ArenaBossHealth", live and hp or 0)
	RS:SetAttribute("ArenaBossSeconds", live and 0 or math.floor(left))

	local label
	for _, anchor in ipairs(CollectionService:GetTagged("ArenaCountdown")) do
		local board = anchor:FindFirstChild("CountdownBoard")
		label = board and board:FindFirstChild("Countdown")
	end
	if not label then return end

	-- the board says the same thing the HUD does, off the same three values, so the two cannot drift
	if live then
		label.Text = ("%s %s  \u{2764}\u{FE0F} %s"):format(boss.emoji, boss.name:upper(), formatNumber(hp))
	else
		label.Text = ("\u{2694}\u{FE0F} NEXT BOSS IN  %d:%02d"):format(left // 60, left % 60)
	end
end

-- ===== SPENDING A REVIVE =====
--
-- Returns true only when a charge was actually spent on a restore that actually happened. Every
-- other answer leaves the charge in the player's pocket, which is what makes the product safe to
-- sell against an unreliable receipt: the worst case is "saved for your next attempt", never a
-- purchase that evaporated.
--
-- Called from two places -- the client's revive button, and RobuxShopService the instant a receipt
-- lands, so a purchase made mid-fight applies without the player pressing anything.
function BossService.TryConsumeRevive(player)
	local data = PlayerDataService.Get(player)
	if not data then return false, "nodata" end
	if (data.BossRevives or 0) <= 0 then return false, "nocharge" end

	local snap = reviveSnapshot[player.UserId]
	if not snap then return false, "nosnapshot" end
	if not snap.model or not snap.model.Parent then
		reviveSnapshot[player.UserId] = nil
		return false, "gone"
	end
	if os.clock() - snap.t > GameConfig.BossReviveTTL then
		reviveSnapshot[player.UserId] = nil
		return false, "expired"
	end

	-- ONLY EVER LOWER. If the boss is already at or below where this player left it -- because it
	-- has not healed yet, or because someone else has been hitting it since -- there is nothing to
	-- restore, so nothing is charged. This single comparison is what stops a revive being usable as
	-- a heal on another player's fight.
	local current = snap.model:GetAttribute("Health") or snap.max
	if snap.hp >= current then return false, "nothingtorestore" end

	-- spent before the effect and with no yield in between, so two clicks in the same frame cannot
	-- both pass the check above
	data.BossRevives -= 1

	local now = os.clock()
	local restored = math.floor(snap.hp)
	snap.model:SetAttribute("Health", restored)
	local entry = hurt[snap.model]
	if entry then
		entry.hp = snap.hp
		entry.lastHit = now
		entry.frozenUntil = now + GameConfig.BossReviveFreeze
	else
		hurt[snap.model] = {
			max = snap.max, hp = snap.hp, lastHit = now, draw = snap.draw,
			frozenUntil = now + GameConfig.BossReviveFreeze,
		}
	end
	snap.draw(restored)

	-- the screen-space bar, the same payload a landed blow sends, so the number the buyer is
	-- looking at moves at the moment they pay for it
	CombatFx:FireClient(player, { k = "bossBar", name = snap.name, hp = restored, max = snap.max })
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "bossRevive",
		name = snap.name,
		pct = math.floor(restored / math.max(snap.max, 1) * 100 + 0.5),
		left = data.BossRevives,
	})
	return true
end

function BossService.Init()
	for _, existing in ipairs(bossesFolder:GetChildren()) do
		existing:Destroy()
	end
	table.clear(rigs)
	-- before the spawn loop below, not after it: everything spawned here registers a handler
	table.clear(hitHandlers)
	eventState.model = nil
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.boss then
			spawnBoss(zone)
		end
	end

	-- the one loop that poses every rig; without it the bosses stand frozen in their build pose
	RunService.Heartbeat:Connect(driveRigs)

	AutoAttack.OnServerEvent:Connect(function(player, model)
		if typeof(model) ~= "Instance" then return end
		local entry = hitHandlers[model]
		-- a creature, a stale model or something invented: CreatureService's own listener on this
		-- remote answers for its half, and neither ever sees the other's models
		if not entry or not entry.body.Parent then return end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		if (hrp.Position - entry.body.Position).Magnitude > entry.reach then return end
		entry.fn(player)
	end)

	UseBossRevive.OnServerEvent:Connect(function(player)
		local ok, why = BossService.TryConsumeRevive(player)
		if ok then return end
		-- Only the two answers a player can act on are worth a message. "nosnapshot" and "gone" mean
		-- the button was pressed with no fight behind it, which is not an error worth interrupting
		-- anyone over.
		if why == "nocharge" then
			Remotes.Notify:FireClient(player, { kind = "error", message = "You have no Boss Revive!" })
		elseif why == "nothingtorestore" then
			Remotes.Notify:FireClient(player, { kind = "error", message = "That boss hasn't healed yet -- keep hitting it!" })
		end
	end)

	-- ===== THE ONE MOMENT THE OFFER MAKES SENSE =====
	--
	-- Nothing on this server watched a player die before this line -- there was no Humanoid.Died
	-- connection anywhere in the game. It is added here rather than somewhere more general because
	-- this is the only feature that needs it, and because the answer is only interesting when a
	-- snapshot is standing behind it: a player who dies to a creature, or to a boss they never hurt,
	-- is shown nothing at all. An offer that appears on every death is an advertisement; one that
	-- appears when you actually lost something is a service.
	local function watchCharacter(player, character)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		humanoid.Died:Connect(function()
			local snap = reviveSnapshot[player.UserId]
			if not snap or not snap.model or not snap.model.Parent then return end
			if os.clock() - snap.t > GameConfig.BossReviveTTL then return end
			local data = PlayerDataService.Get(player)
			-- ===== ONLY FOR SOMEBODY WHO ALREADY HOLDS ONE (11.7) =====
			--
			-- The Boss Revive product is withdrawn, and this card is the thing that sold it: with no
			-- charge in the save it used to read "REVIVE BOSS" and open a purchase prompt. That is the
			-- "revive UI" the row removes. The card itself stays for the one case that must keep
			-- working -- a player who owns a charge, because a receipt that landed before the
			-- withdrawal is a thing somebody paid for and Roblox will retry until it is honoured.
			-- Nobody can reach this branch by buying any more; they can only reach it by having.
			local held = (data and data.BossRevives) or 0
			if held <= 0 then return end
			CombatFx:FireClient(player, {
				k = "reviveOffer",
				name = snap.name,
				pct = math.floor(snap.hp / math.max(snap.max, 1) * 100 + 0.5),
				held = held,
			})
		end)
	end
	local function watchPlayer(player)
		-- task.spawn because watchCharacter can yield on WaitForChild, and a yielding CharacterAdded
		-- handler holds up every other listener on that signal
		if player.Character then task.spawn(watchCharacter, player, player.Character) end
		player.CharacterAdded:Connect(function(character)
			task.spawn(watchCharacter, player, character)
		end)
	end
	for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end
	Players.PlayerAdded:Connect(watchPlayer)

	-- A snapshot is a live model reference and a leaving player will never spend it. The CHARGE is
	-- in data.BossRevives and saves normally, which is the other half of why the product is a
	-- counted item: nothing paid for is tied to this table's lifetime.
	Players.PlayerRemoving:Connect(function(player)
		reviveSnapshot[player.UserId] = nil
	end)

	-- The event clock. Deliberately started a short way in rather than at a full interval: a server
	-- that has just come up should not make its first players wait half an hour to find out what
	-- the arena is for.
	task.spawn(function()
		local boss = GameConfig.EventBoss
		eventState.nextSpawn = os.clock() + 120
		while true do
			task.wait(1)
			driveCountdown()
			if os.clock() >= eventState.nextSpawn then
				eventState.nextSpawn = os.clock() + boss.intervalSeconds
				local ok, err = pcall(spawnEventBoss)
				if not ok then warn("[BossService] event spawn failed: " .. tostring(err)) end
			end
		end
	end)
end

-- Exposed for testing: forces the event boss in now and resets the clock.
function BossService.ForceEventBoss()
	eventState.nextSpawn = os.clock() + GameConfig.EventBoss.intervalSeconds
	return spawnEventBoss()
end

return BossService

