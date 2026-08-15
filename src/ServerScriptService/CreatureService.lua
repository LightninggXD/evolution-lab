local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local PlayerDataService = require(script.Parent.PlayerDataService)
local DNAService = require(script.Parent.DNAService)
local SeasonPassService = require(script.Parent.SeasonPassService)
-- 11.6: the terraces drop pets, so the kill path needs the one function that creates one. No cycle
-- -- PetService requires PlayerDataService, SeasonPassService and AnnounceService, none of which
-- reaches back here, and DNAService above already pulls PetService in anyway.
local PetService = require(script.Parent.PetService)
local AnnounceService = require(script.Parent.AnnounceService)
local Remotes = RS.Remotes

local CreatureService = {}

-- ===== COMBAT FEEDBACK CHANNEL ================================================
-- Every *visible* consequence of a hit -- the attacker's swing, the impact spark, the damage
-- number, the kill burst -- is drawn by StarterPlayerScripts.CombatClient on each machine. The
-- server stays the only authority on the damage itself and sends nothing but a description of
-- what just happened.
--
-- Two reasons it is not built server-side. A billboard or a particle emitter created on the server
-- replicates to every client at a throttled rate, so the number that is supposed to punctuate the
-- click arrives visibly after it. And the attacker's own swing has to start on the frame they
-- pressed the button -- a round trip is 100 ms, which is longer than the swing.
--
-- Created on demand rather than assumed: the rest of the Remotes folder is saved instances, and a
-- place that has never run this build would hard-error on the first punch. BossService opens the
-- same remote the same way, so whichever service initialises first makes it.
local function ensureRemote(name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = Remotes
	return ev
end

local CombatFx = ensureRemote("CombatFx")

-- ===== AUTO-ATTACK ============================================================
-- A ClickDetector can only be fired by an actual click, so auto-attack cannot reuse one: the
-- client asks over this remote instead, naming the model it wants hit.
--
-- That makes it the one path into combat a client controls, so it validates rather than trusts:
-- the model has to be a creature THIS server spawned (a live entry in `hitHandlers`, not merely
-- something parented under workspace.Creatures) and the attacker has to be standing next to it.
-- Beyond that there is nothing to gain by spamming it -- every hit still goes through the same
-- per-player `tier.hitCooldown` the mouse path uses, and the server still owns the damage.
local AutoAttack = ensureRemote("AutoAttack")

-- weak keys: a rig that dies drops out of here on the next collection instead of pinning a
-- destroyed Model and its whole closure forever. 520 creatures respawn on 4-55 second timers.
local hitHandlers = setmetatable({}, { __mode = "k" })

-- Past this a spark is sub-pixel and the packet is waste. The zone strip is 12,000 studs long and
-- a hit landed in Forest is not an event in Ocean.
local FX_RADIUS = 280

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

-- 24 187 -> "24.2K". A health bar that reads "24187 / 31000" at 14 px is a smear.
--
-- Below 10 000 the number is printed exactly, which is deliberate and is why the cutoff is 1e4 and
-- not 1e3: a Swarmer with 1 500 health should say so.
--
-- The three-branch ladder this replaces (K / M / B, and nothing above) was ADEQUATE for the range
-- it is actually given: an Elite in the last zone has 294 000 health, so nothing here has ever got
-- past "K". It is replaced anyway for two reasons, neither of them a live bug --
--
--   * the carry below. "%.1f" of 999.999 prints "1000.0", so 999 999 would read "1000.0K". Out of
--     range today, and it is the same defect that WAS visible on the DNA counter.
--   * it is now the same loop and the same suffix table as every other readout in the game, so a
--     later bump to `mobHealthMult` cannot quietly run a plate off the end of the ladder.
--
-- If you are looking for the numbers that genuinely need the tail of the table, they are DNA
-- (trillions, see MainUI) rather than anything on a creature.
local SHORT_SUFFIX = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
local function shortNumber(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	if n < 1e4 then return tostring(n) end
	local mag = 0
	while n >= 1000 and mag < #SHORT_SUFFIX do
		n = n / 1000
		mag += 1
	end
	-- and the rounding carries past the loop, which has already stopped looking: 999,999 divides
	-- once to 999.999, is accepted, and "%.1f" prints "1000.0K" one short of a million.
	if n >= 999.95 and mag < #SHORT_SUFFIX then
		n = n / 1000
		mag += 1
	end
	return string.format("%.1f%s", n, SHORT_SUFFIX[mag])
end

-- ===== base tier definitions (Forest baseline -- scaled per zone by mobHealthMult/
-- mobDamageMult/mobDnaMult in GameConfig.Zones, so creatures get stronger zone by zone) =====
-- Four of them, not two. A zone used to hold five Critters and three Brutes and nothing else, so
-- the whole strip was one easy mob and one hard mob wearing twenty sets of names. The two new
-- tiers sit at the ends of the range rather than between the old pair, which is what actually
-- adds variety: a Swarmer is barely worth stopping for but there are lots of them and they come
-- back fast, and an Elite is a small boss you have to decide to fight.
--
-- `heavy` drives the darker, meaner palette and the extra spikes/limbs in every rig (see
-- buildPalette). `xp` and `plateColor` used to be `tierName == "Brute"` checks scattered through
-- spawnCreature; with four tiers those had to become properties.
-- ===== NOTHING DIES IN ONE HIT ================================================
--
-- Player damage and creature health are on different curves and always will be. Damage is
-- `8 + (stage - 1) * 6` times whatever Income, pets and Stage Mastery have grown to; creature
-- health is the tier's base times the zone's `mobHealthMult`, which runs 1x in Forest to 1050x on
-- the Absolute Plane. The two only line up when a player is standing in the zone that matches
-- their stage -- and a player is *usually* somewhere else, because every zone before their own
-- stays walkable and is where the eggs they can afford are.
--
-- A Cyborg (stage 8, 50 damage before a single upgrade) in Forest therefore deletes a 12-health
-- Swarmer, a 30-health Critter and a 70-health Brute on the frame they click, which is the
-- "it disappears like a balloon" complaint back again by a different route: none of the flinch,
-- recoil, health bar or hit spark this game spent so much effort on is ever seen.
--
-- So each tier declares the fewest hits it may be killed in, and a blow is capped at that
-- fraction of the tier's full health. Deliberately a cap on the DAMAGE rather than a floor under
-- the health: an over-levelled player still clears a low zone as fast as they can click, the
-- payout is untouched, and nothing anywhere in the game needs to know how strong the attacker is.
-- The counts rise with the tier, so a Swarmer stays a thing you brush aside and an Elite stays a
-- fight.
local TIERS = {
	Swarmer = {
		health = 12,
		minHits = 3,
		hitCooldown = 0.15,
		respawnDelay = 4,
		dnaMult = 1.8,
		size = 6.5,
		colors = { Color3.fromRGB(240, 200, 90), Color3.fromRGB(150, 220, 120), Color3.fromRGB(230, 140, 190) },
		label = "\u{1F41B} Swarmer",
		retaliateChance = 0,
		retaliateDamage = { 0, 0 },
		auraRange = 0,
		heavy = false,
		-- THE ONE XP THE WHOLE CURVE IS ANCHORED ON: the weakest creature in the first zone is worth
		-- exactly 1. Every other tier is a multiple of it, and every other zone multiplies the lot by
		-- `mobXpMult`. See the XP block in GameConfig.
		xp = 1,
		plateColor = "Sunny",
	},
	Critter = {
		health = 30,
		minHits = 4,
		hitCooldown = 0.22,
		respawnDelay = 9,
		dnaMult = 4.5,
		size = 11,
		colors = { Color3.fromRGB(210, 70, 70), Color3.fromRGB(90, 170, 90), Color3.fromRGB(200, 150, 60) },
		label = "\u{1F47E} Critter",
		retaliateChance = 0, -- doesn't fight back
		retaliateDamage = { 0, 0 },
		auraRange = 0, -- doesn't passively attack
		heavy = false,
		xp = 2,
		plateColor = "Green",
	},
	Brute = {
		health = 70,
		minHits = 6,
		hitCooldown = 0.22,
		respawnDelay = 16,
		dnaMult = 9,
		size = 16,
		colors = { Color3.fromRGB(90, 30, 110), Color3.fromRGB(40, 40, 50) },
		label = "\u{1F480} Brute",
		retaliateChance = 0.55, -- 55% chance to hit back when you attack it
		retaliateDamage = { 6, 12 },
		auraRange = 9, -- also periodically attacks anyone who lingers close
		auraDamage = { 4, 8 },
		auraInterval = 1.6,
		heavy = true,
		xp = 5,
		plateColor = "Red",
	},
	Elite = {
		-- Four times a Brute's health and nearly four times its payout, on a minute-long respawn:
		-- one per zone-ish, worth going out of your way for, and genuinely able to kill you.
		--
		-- READ FROM GameConfig, not typed here, because the BOSS curve has to know this number: a
		-- boss's health is floored at a multiple of a farmed Elite. While this was a private 280 the
		-- two curves had no connection at all, and the boss table -- built at GameConfig load, long
		-- before this file runs -- ended up under it in eighteen of twenty zones. See the
		-- BossTargetHits block in GameConfig for the measurement.
		health = GameConfig.EliteBaseHealth,
		minHits = 8,
		hitCooldown = 0.22,
		respawnDelay = 55,
		dnaMult = 34,
		size = 26,
		colors = { Color3.fromRGB(255, 160, 40), Color3.fromRGB(120, 40, 160) },
		label = "\u{2B50} Elite",
		retaliateChance = 0.8,
		retaliateDamage = { 18, 34 },
		auraRange = 16,
		auraDamage = { 12, 22 },
		auraInterval = 1.2,
		-- An Elite is a fight you choose to take, so it is worth more than the four Brutes it costs
		-- you in time: 14 against 5, on a 55-second respawn.
		heavy = true,
		xp = 14,
		plateColor = "Gold",
	},
	-- ===== THE APEX (11.6): THE THING ON THE HIGHEST SHELF =====
	--
	-- Spawned only by the raised loop, only on layer 2, and only fightable after three rebirths. It
	-- is the one creature in the game that drops a species no egg contains.
	--
	-- IT IS BARELY TOUGHER THAN AN ELITE AND THAT IS THE DESIGN. 1.25x health, and the number is not
	-- even authored here -- `GameConfig.ApexBaseHealth` is clamped against the boss floor so that a
	-- farmed Apex can never out-last its own zone's boss, which is 11.9 happening again in a new
	-- costume. Read that block before raising anything here.
	--
	-- What makes it dangerous is the retaliation, not the health bar: it hits back on 95% of blows
	-- for 40-70, with a 20-stud aura at 26-44 every second. A player who wandered up without three
	-- rebirths' worth of damage would lose the trade badly -- which is the point of a gate you can
	-- see from below. Size stays at the Elite's 26 deliberately: `raisedSpots` clears its candidate
	-- shelves with a 26-stud probe, so a bigger Apex would need that probe widened and would quietly
	-- cost some zones their spots. The crown, the colour and the name carry the distinction instead.
	Apex = {
		health = GameConfig.ApexBaseHealth,
		minHits = 10,
		hitCooldown = 0.22,
		respawnDelay = 120,
		dnaMult = 55,
		size = 26,
		colors = { Color3.fromRGB(255, 90, 200), Color3.fromRGB(45, 15, 70) },
		label = "\u{1F451} Apex",
		retaliateChance = 0.95,
		retaliateDamage = { 40, 70 },
		auraRange = 20,
		auraDamage = { 26, 44 },
		auraInterval = 1.0,
		heavy = true,
		xp = 30,
		plateColor = "Purple",
	},
}

-- Relative (dx, dz) offsets from each zone's center (zone.offset) -- reused for every
-- zone so every zone gets the same layout of creatures, just shifted and scaled up.
-- Every point stays off the street (|dx| >= 48, the walkway from the arrival gate past the eggs to
-- the exit gate) and out of the boss arena at (0, -132). A brute used to spawn at (0, 220), which
-- is the spot a player materialises on when they walk in, and a critter at (-70, -150) stood
-- inside the boss's dais.
-- The platform is 700 x 860 now (it was 450 x 550), so these spread much wider than they used to
-- and there are 24 of them instead of 8. Every point still stays off the street (|dx| >= 60, the
-- walkway from the arrival gate past the eggs to the exit gate), out of the egg plaza, clear of
-- the arrival circle at z = 366, and outside the boss's clearing at z = -240.
--
-- Swarmers cluster in threes on purpose -- a swarm that is evenly spaced is not a swarm.
-- Where creatures stand, relative to each zone's centre (zone.offset).
--
-- These used to be twenty-six hand-placed points. Thirty-nine per zone is more than can be placed
-- by eye without something ending up inside the boss's dais or in the middle of the walkway, and
-- every one of those mistakes has been made here before: a brute at (0, 220) stood exactly where
-- players materialise, a critter at (-70, -150) stood inside the boss arena. So the points are
-- generated against the four keep-out rules instead, and the seed is fixed -- every server has to
-- lay its creatures out identically or two players comparing notes are describing different games.
--
--   1. the street:   |x| >= 62      the walk from the arrival gate past the eggs to the exit
--   2. arrival:      84 studs clear of (0, 366)
--   3. the boss:     132 studs clear of (0, -240) -- its clearing is 116 and the rig is big
--   4. the egg plaza: 96 studs clear of (0, -4)
--
-- Swarmers come in threes around a cluster point on purpose: a swarm that is evenly spaced is not
-- a swarm.
local SPAWN_RNG = Random.new(20260804)

-- The four keep-out tests, in zone-relative coordinates. Shared by the spawn placer below and by
-- the roaming target picker in the idle driver -- one definition, so the two can never drift.
local function insideKeepOut(x, z)
	if math.abs(x) < 62 then return true end                                        -- the street
	if (Vector2.new(x, z) - Vector2.new(0, 490)).Magnitude < 110 then return true end -- arrival
	if (Vector2.new(x, z) - Vector2.new(0, -320)).Magnitude < 132 then return true end -- the boss
	if (Vector2.new(x, z) - Vector2.new(0, -4)).Magnitude < 96 then return true end   -- egg plaza
	-- and the platform's own edge. NOT the floor's edge: the boundary wall has a rock rampart
	-- standing in front of it on the playable side, and it reaches up to 38 studs in from the X
	-- wall (350) and 48 from the Z wall (430) -- measured across all twenty zones. At the old 338 /
	-- 412 a creature at the fringe was placed inside that rampart, which is most of what "the
	-- monsters are in the wall" was. These leave room for the rig's own half-width on top.
	if math.abs(x) > 575 or math.abs(z) > 500 then return true end
	return false
end

local function pointIsClear(x, z, placed, minGap)
	if insideKeepOut(x, z) then return false end
	for _, p in ipairs(placed) do
		if (Vector2.new(x, z) - Vector2.new(p.X, p.Z)).Magnitude < minGap then return false end
	end
	return true
end

-- THE VALLEY, NOT THE WHOLE PLATFORM. ZoneBuilder's flat ground ends at TERRAIN_INNER = 415 and
-- everything past it is terraced cliff, so the scatter used to reach 155 studs into a hillside it
-- knew nothing about. The floor tiers are now kept inside the valley with 20 studs of margin; the
-- band beyond it belongs to the raised Brutes and Elites placed in Init, which resolve their own
-- ground height because they are placed after the world exists and can simply ask it.
local VALLEY_X = 395

local function scatterPoints(count, minGap, placed)
	local out = {}
	local guard = 0
	while #out < count and guard < count * 400 do
		guard += 1
		local x = SPAWN_RNG:NextNumber(-VALLEY_X, VALLEY_X)
		local z = SPAWN_RNG:NextNumber(-492, 492)
		if pointIsClear(x, z, placed, minGap) then
			local v = Vector3.new(math.floor(x), 0, math.floor(z))
			table.insert(out, v)
			table.insert(placed, v)
		end
	end
	return out
end

local RELATIVE_SPAWN_POINTS = {}
do
	-- Placed biggest first: an Elite needs the most room, and letting the swarm claim the space
	-- first would push the tiers that actually matter out to the fringes.
	local placed = {}
	-- Counts went up with the platform: it is 900 x 860 now (it was 700), and the extra ground is
	-- all off the street where the creatures live. Same density, more of it.
	-- The platform went 900 x 860 -> 1250 x 1150, which is 86% more ground, almost all of it off
	-- the street where the creatures live. The counts went up 46% rather than 86%: the server holds
	-- every rig in the world at once (only the CLIENT is spared by streaming), and 960 was the last
	-- count this ran comfortably at. 1400 is the step being taken; if it costs frames, this is the
	-- line to walk back.
	-- ===== THE HEAVY TIERS ARE SPLIT BETWEEN THE FLOOR AND THE CLIFFS =====
	--
	-- The zone laid every tier out on one flat plane, so the only thing separating a Swarmer from an
	-- Elite was which direction you happened to walk. Nothing about the map said "that one is
	-- dangerous" before you were already in range of it.
	--
	-- Height says it before anything else does. Half the Brutes and two thirds of the Elites now
	-- stand up on the terraced shelves in the outer band -- see RAISED below, which picks their spots
	-- in Init once the terrain actually exists -- and they are ranked by altitude, so the Elites take
	-- the top shelf and the Brutes the ones under it. You can see them from the valley, you have to
	-- walk up to reach them, and the climb is a decision rather than a wall.
	--
	-- Deliberately NOT all of them. A cliff line of nothing but Elites is a raid boss row and it
	-- empties the valley of anything worth hitting; six Brutes and two Elites stay down on the flat
	-- so the ground floor is still a place where a fight happens.
	RELATIVE_SPAWN_POINTS.Elite = scatterPoints(2, 200, placed)
	RELATIVE_SPAWN_POINTS.Brute = scatterPoints(6, 130, placed)
	RELATIVE_SPAWN_POINTS.Critter = scatterPoints(22, 78, placed)

	local swarm = {}
	for _, hub in ipairs(scatterPoints(10, 88, placed)) do
		for i = 1, 3 do
			local a = (i - 1) * (math.pi * 2 / 3) + SPAWN_RNG:NextNumber(0, 1)
			-- The HUB passes the keep-out test; the three members sit 17 studs off it and have to
			-- pass it too. Before this they did not, and it put two Swarmers per zone -- the same
			-- two, forty across the strip -- inside the boss's clearing and in the middle of the
			-- street. Pulled in against the ring rather than dropped, so a swarm is still three.
			local m = hub + Vector3.new(math.cos(a) * 17, 0, math.sin(a) * 17)
			for pull = 1, 4 do
				if not insideKeepOut(m.X, m.Z) then break end
				m = hub:Lerp(m, 1 - pull * 0.25)
			end
			table.insert(swarm, m)
		end
	end
	RELATIVE_SPAWN_POINTS.Swarmer = swarm
end

local creaturesFolder = workspace:FindFirstChild("Creatures")
if not creaturesFolder then
	creaturesFolder = Instance.new("Folder")
	creaturesFolder.Name = "Creatures"
	creaturesFolder.Parent = workspace
end

-- ===== NOT STANDING INSIDE THE SCENERY ========================================
-- The spawn points above are generated against four keep-out rules -- street, arrival, boss, plaza
-- -- and ZoneBuilder scatters its boulders, ramparts, landmarks and biome props against a set of
-- its own. Neither has ever been told about the other, so wherever the two happen to agree on a
-- spot the creature is built standing inside a rock, which from the street reads as exactly what
-- it is: a monster in a wall.
--
-- ZoneBuilder.Build() runs before CreatureService.Init (see ServerMain), so by the time anything
-- here spawns, the world it has to fit into is already standing and can simply be asked.
local sceneryParams = OverlapParams.new()
sceneryParams.FilterType = Enum.RaycastFilterType.Exclude
sceneryParams.MaxParts = 12

-- ===== HOW HIGH THE GROUND ACTUALLY IS AT A POINT =============================
--
-- Everything in this file used to assume the floor was at y = 0, and for a long time it was:
-- ZoneBuilder keeps the middle of every zone dead flat on purpose, precisely so that props
-- scattered onto it can be placed without asking what is underneath.
--
-- The OUTER band is not flat. It is two to four terraced shelves climbing 20 to 128 studs (see
-- TERRAIN_INNER / TERRAIN_PROFILE in ZoneBuilder), and the spawn scatter has always been allowed
-- out to |x| = 575 -- well inside it. Every creature that landed there was built at valley height,
-- which is to say inside the cliff, and its ground ring was drawn at y = 0.35 out in the open air
-- under the shelf. One ray answers it for any point and is what the elevated tiers below stand on.
--
-- `RespectCanCollide` is the load-bearing flag here: nearly every piece of dressing in a zone is
-- CanCollide = false, so without it a creature gets stood on top of a banner cloth or a fern.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function refreshSceneryFilter()
	local skip = { creaturesFolder }
	local bosses = workspace:FindFirstChild("Bosses")
	if bosses then table.insert(skip, bosses) end
	local pets = workspace:FindFirstChild("EquippedPets")
	if pets then table.insert(skip, pets) end
	sceneryParams.FilterDescendantsInstances = skip
	-- the same exclusions: a creature must never be stood on another creature's shoulders, and a
	-- boss rig is 75-121 studs of "ground" that walks away when it dies
	groundParams.FilterDescendantsInstances = skip
end
refreshSceneryFilter()

-- Starts at 300, which clears the tallest thing standing inside a zone (the portal keystone, at
-- 166) and stays under the boundary wall's 180 without ever beginning inside anything. Falls back
-- to the caller's own guess rather than to 0 -- a ray that hits nothing means the point is off the
-- platform, and dropping such a creature to y = 0 would be a worse answer than leaving it be.
--
-- Returns WHAT it landed on as well as how high. Every caller but one ignores the second value;
-- the one that does not is raisedSpots, which has to tell a terrace shelf apart from the top of a
-- rock spire, and no height on its own can say which of those a surface is.
local function floorAt(x, z, fallback)
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -320, 0), groundParams)
	if not hit then return (fallback or 0), nil end
	return hit.Position.Y, hit.Instance
end

-- The box is measured in tier size, which is the rig's UNIT and not its extents: a Critter is 10
-- units and stands 22 studs tall with its horns, ears and paws well outside a 10-wide column. So
-- the probe is deliberately bigger than the number it is given -- clearing a spot that is only just
-- big enough is what leaves a banner pole through a creature's shoulder.
local function blockedAt(x, y, z, size)
	local feet = y - size * 0.5
	local hits = workspace:GetPartBoundsInBox(
		CFrame.new(x, feet + size * 0.75, z),
		Vector3.new(size * 1.8, size * 1.6, size * 1.8),
		sceneryParams
	)
	for _, p in ipairs(hits) do
		-- only things you could walk into. Every one of these queries catches the zone floor and it
		-- is never in the way: its top surface is at the creature's feet, not through its body.
		if p.CanCollide and (p.Position.Y + p.Size.Y * 0.5) > feet + 2 then
			return true
		end
	end
	return false
end

-- Walks a point out of whatever it landed in, in rings of eight. Gives up after six rings and
-- returns the original: a creature standing in a rock is still better than a creature that does
-- not exist, and the zone it belongs to would otherwise be one spawn short for the whole session.
local function clearOfScenery(position, size, zoneX)
	if not blockedAt(position.X, position.Y, position.Z, size) then return position end
	for ring = 1, 6 do
		local r = size * 0.9 + ring * 16
		for i = 0, 7 do
			local a = (i / 8) * math.pi * 2 + ring * 0.4
			local x = position.X + math.cos(a) * r
			local z = position.Z + math.sin(a) * r
			if not insideKeepOut(x - zoneX, z) and not blockedAt(x, position.Y, z, size) then
				return Vector3.new(x, position.Y, z)
			end
		end
	end
	-- Every ring failed, which in practice means a corner: out by the boundary most directions are
	-- either inside the rampart or outside the keep-out, so the rings have nowhere to land. Walk the
	-- point in toward the middle of its own platform instead -- the one direction that is always
	-- more open than where it started.
	local inward = Vector3.new(zoneX, position.Y, 0)
	for step = 1, 5 do
		local p = position:Lerp(inward, step * 0.16)
		if not insideKeepOut(p.X - zoneX, p.Z) and not blockedAt(p.X, p.Y, p.Z, size) then
			return p
		end
	end
	return position
end

-- A BLOW YOU TAKE IS CAPPED THE SAME WAY A BLOW YOU LAND IS.
--
-- `minHits` already stops a player one-shotting a creature by capping OUTGOING damage at a
-- fraction of the target's health. Nothing did the mirror of that, and the arithmetic is why every
-- Elite in the game was unkillable -- in ANY zone, including Forest.
--
-- An Elite needs 8 landed hits and swings back on 80% of them for 18-34 x the zone multiplier, on
-- a 0.22 s cooldown. In zone 1 that is 20.8 health per hit you land, against a stage-1 player's
-- 100 maximum: you survive 4.8 of the 8 hits the tier floor requires. By zone 19 it is 1.9. The
-- fight was arithmetically lost before it started, and the Elites are the best content in the
-- world -- 4x a Brute's XP, 34x its DNA, six per zone, never once killed.
--
-- Same shape as the outgoing cap: a ceiling on the DAMAGE, not a floor under the player's health.
-- An over-levelled player still walks through a low zone untouched, the payout is unchanged, and
-- nothing here needs to know how strong the attacker is. `requiredHits` is what makes it honest --
-- a tier that demands more hits may hurt less per hit, so the whole fight fits in one health bar
-- with room to spare rather than each tier being tuned by hand against twenty zone multipliers.
local function hurtPlayer(player, amount, requiredHits)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if requiredHits and requiredHits > 0 and humanoid.MaxHealth > 0 then
		-- half a health bar spent on the whole exchange, at worst
		amount = math.min(amount, humanoid.MaxHealth / (requiredHits * 2))
	end
	-- never rounds to nothing: a hit that takes 0 reads as the creature failing to connect
	amount = math.max(amount, 1)
	humanoid:TakeDamage(amount)
	Remotes.Notify:FireClient(player, { kind = "playerHurt", amount = math.floor(amount) })
end

-- ===== CREATURE RIG FACTORY ===================================================
-- Every creature used to be one coloured ball. Now each biome gets a hand-built rig
-- of anchored primitives (Block / Ball / Cylinder / Wedge) with its own silhouette,
-- tinted from that zone's palette so a Forest wolf and a Volcano wolf read as two
-- completely different animals. Rigs run 20-36 parts and are driven by exactly one
-- animation loop for the whole game (see driveCreatures).
--
-- The face is what the parts are for. Every creature used to get one flat Neon ball per
-- socket, which reads as machinery rather than as an animal, so the rigs now share the
-- face PetModel and BossService build: pale sclera, glowing iris, dark pupil, a glint,
-- and a brow tilted down toward the nose. Fangs, paws, bellies, ear linings and segment
-- bands do the rest. That, plus the fact that they now LOOK at something (see the yaw in
-- spawnCreature and driveCreatures), is the whole difference between a mob and a prop.

local IDENTITY = CFrame.new()
local INK = Color3.fromRGB(26, 18, 36) -- the same near-black the UI outlines use
local SIDES = { -1, 1 }
local BONE = Color3.fromRGB(248, 244, 232) -- fangs and claws, kept constant across all 20 zones

local function lighten(c, f) return c:Lerp(Color3.fromRGB(255, 255, 255), f) end
local function darken(c, f) return c:Lerp(INK, f) end

-- ===== THE PALETTE =====
-- Every colour on a rig used to be derived from `zone.accentColor`: skin, belly, ears, trim and
-- glow were all the same hue at four brightnesses. In Forest that produced a green animal with a
-- green stomach, green ears and a green collar. Correct, consistent, and completely flat -- the
-- creature disappeared into the grass it was standing on.
--
-- So a rig now takes exactly TWO things from its zone -- the skin and the shadow -- and everything
-- else comes from a curated bright set that has nothing to do with the biome. The skin still says
-- "you are in Forest"; the coat, trim and iris say "this is a Bristleback", and they are what
-- carries the creature off the background.
local COATS = {
	Color3.fromRGB(255, 122, 150), -- bubblegum
	Color3.fromRGB(255, 186, 74),  -- amber
	Color3.fromRGB(120, 206, 255), -- sky
	Color3.fromRGB(176, 138, 255), -- violet
	Color3.fromRGB(122, 232, 160), -- mint
	Color3.fromRGB(255, 240, 128), -- lemon
	Color3.fromRGB(255, 138, 92),  -- coral
	Color3.fromRGB(126, 236, 232), -- aqua
	Color3.fromRGB(255, 160, 210), -- orchid
}
local IRISES = {
	Color3.fromRGB(64, 220, 255), Color3.fromRGB(255, 208, 64), Color3.fromRGB(150, 255, 160),
	Color3.fromRGB(255, 120, 190), Color3.fromRGB(178, 148, 255), Color3.fromRGB(255, 108, 84),
}
-- The SKIN used to be the zone accent itself, which is how a Forest Brute came out near-black and
-- a Void anything came out as a smudge. A pet is a bright saturated species colour with no biome
-- in it at all (PetModel just uses `def.color`); a creature is that colour with a quarter of the
-- biome mixed back in, so it still belongs to the zone it is standing in but is never mud.
local BODIES = {
	Color3.fromRGB(255, 138, 168), -- rose
	Color3.fromRGB(126, 196, 255), -- cornflower
	Color3.fromRGB(150, 232, 148), -- apple
	Color3.fromRGB(255, 196, 96),  -- honey
	Color3.fromRGB(196, 156, 255), -- lilac
	Color3.fromRGB(120, 226, 226), -- turquoise
	Color3.fromRGB(255, 158, 118), -- peach
	Color3.fromRGB(246, 232, 132), -- butter
	Color3.fromRGB(238, 148, 220), -- fuchsia
	Color3.fromRGB(160, 214, 255), -- ice
}

-- djb2 over the zone key and the tier name. Deterministic on purpose: the same species has to look
-- the same on every server and after every restart, so this cannot be math.random.
local function keyHash(...)
	local h = 5381
	for _, str in ipairs({ ... }) do
		for i = 1, #str do
			h = (h * 33 + str:byte(i)) % 2147483647
		end
	end
	return h
end

local function buildPalette(zone, tierName, tierColors)
	local accent = zone.accentColor
	local ground = zone.groundColor
	-- Read off the tier rather than compared against the string "Brute": Elites are heavy too, and
	-- with four tiers a name comparison would have had to be repeated in every rig below.
	local isBrute = (TIERS[tierName] and TIERS[tierName].heavy) or false
	local h = keyHash(zone.key, tierName)
	local bodyColor = BODIES[(math.floor(h / 11) % #BODIES) + 1]
	-- heavy tiers take more of the biome and lose a little brightness: still a saturated colour,
	-- just a deeper one, so "meaner" never means "grey"
	local skin = bodyColor:Lerp(accent, isBrute and 0.42 or 0.24)
	if not isBrute then skin = lighten(skin, 0.08) end
	local coat = COATS[(h % #COATS) + 1]
	-- a second, different bright hue for the hardware. Stepping by a prime keeps it off the coat
	-- for every zone/tier pair rather than only usually.
	local trim = COATS[((h + 4) % #COATS) + 1]
	local iris = IRISES[(math.floor(h / 7) % #IRISES) + 1]

	return {
		skin = skin,
		-- the pale underside is a tint of the COAT, not of the skin: that one change is what puts a
		-- second hue on every rig in the game without touching a single rig builder
		belly = lighten(coat, 0.55),
		coat = coat, -- ear linings, markings, spots, cheeks, fin webbing
		trim = trim, -- collars, bands, plates, fin rays, hardware
		light = lighten(skin, 0.2),
		dark = darken(skin, 0.6),
		-- the near-black the brows, paws, noses and bands are painted in. Derived from the zone
		-- accent rather than a constant so a Volcano rig's shadow is warm and an Ocean rig's cold.
		ink = darken(accent, 0.84),
		metal = lighten(ground:Lerp(accent, 0.35), 0.2),
		-- energy (cracks, cores, stingers, exhausts) stays tied to the biome; the EYES do not, and
		-- get their own hue -- an eye is where a player looks first
		glow = isBrute and Color3.fromRGB(255, 96, 62) or lighten(accent, 0.5),
		iris = iris,
		isBrute = isBrute,
		isElite = tierName == "Elite",
	}
end

-- which archetype each of the 20 zones spawns
local ZONE_ARCHETYPE = {
	Forest          = "BEAST",
	Desert          = "ARACHNID",
	Ocean           = "AQUATIC",
	Volcano         = "MAGMA",
	Moon            = "DRIFTER",
	Mars            = "MECH",
	Galaxy          = "AVIAN",
	BlackHole       = "WRAITH",
	Multiverse      = "SLIME",
	Nebula          = "JELLY",
	Wormhole        = "IMP",
	QuantumRealm    = "CRYSTAL",
	TimeRift        = "MECH",
	AntimatterZone  = "ARACHNID",
	DreamDimension  = "FUNGAL",
	MirrorUniverse  = "CRYSTAL",
	VoidExpanse     = "WRAITH",
	CelestialThrone = "AVIAN",
	Singularity     = "DRIFTER",
	AbsolutePlane   = "PLANT",
}

-- Every creature used to be "👾 Critter (Forest)" or "💀 Brute (Desert)": two names and a zone in
-- brackets, so all 40 spawns across the strip read as the same two animals wearing name tags.
-- Each zone/tier pair now has its own name and emoji. The tier still shows in the stats -- the
-- Brute of a zone is the bigger, angrier one -- but it no longer has to show in the name.
local CREATURE_NAMES = {
	Forest          = { Swarmer = { "\u{1F41D}", "Thornbee" },      Critter = { "\u{1F417}", "Bristleback" },   Brute = { "\u{1F43A}", "Dire Warg" },      Elite = { "\u{1F98C}", "Grovelord" } },
	Desert          = { Swarmer = { "\u{1F997}", "Sand Locust" },   Critter = { "\u{1F982}", "Dust Scorpion" }, Brute = { "\u{1FAB2}", "Sand Tyrant" },    Elite = { "\u{1F40D}", "Dune Serpent" } },
	Ocean           = { Swarmer = { "\u{1F990}", "Reef Skitter" },  Critter = { "\u{1F421}", "Spinefish" },     Brute = { "\u{1F988}", "Reef Ripper" },    Elite = { "\u{1F419}", "Abyss Kraken" } },
	Volcano         = { Swarmer = { "\u{1F525}", "Cinder Fly" },    Critter = { "\u{1F9E8}", "Ember Imp" },     Brute = { "\u{1F30B}", "Cinder Brute" },   Elite = { "\u{1F409}", "Magma Wyrm" } },
	Moon            = { Swarmer = { "\u{1F9A0}", "Regolith Mite" }, Critter = { "\u{1F319}", "Dust Mite" },     Brute = { "\u{1FAA8}", "Crater Hulk" },    Elite = { "\u{1F311}", "Lunar Colossus" } },
	Mars            = { Swarmer = { "\u{1F41C}", "Rust Mite" },     Critter = { "\u{1F529}", "Rust Crawler" },  Brute = { "\u{2699}\u{FE0F}", "Iron Marauder" }, Elite = { "\u{1F6F8}", "Red Sentinel" } },
	Galaxy          = { Swarmer = { "\u{2734}\u{FE0F}", "Spark Mote" }, Critter = { "\u{2728}", "Star Mote" },  Brute = { "\u{2604}\u{FE0F}", "Comet Stalker" }, Elite = { "\u{1F30C}", "Arm Devourer" } },
	BlackHole       = { Swarmer = { "\u{1F32B}\u{FE0F}", "Dim Fleck" }, Critter = { "\u{1F56F}\u{FE0F}", "Gloom Wisp" }, Brute = { "\u{26AB}", "Event Horror" }, Elite = { "\u{1F573}\u{FE0F}", "Accretion King" } },
	Multiverse      = { Swarmer = { "\u{1F4AD}", "Splinter Self" }, Critter = { "\u{1F300}", "Echo Spawn" },    Brute = { "\u{1F3AD}", "Paradox Warden" }, Elite = { "\u{1F5FF}", "Divergence" } },
	Nebula          = { Swarmer = { "\u{2747}\u{FE0F}", "Dust Wisp" }, Critter = { "\u{1F4AB}", "Glimmer Drift" }, Brute = { "\u{1F320}", "Nebula Maw" },  Elite = { "\u{1F3D4}\u{FE0F}", "Pillar Titan" } },
	Wormhole        = { Swarmer = { "\u{1FAB1}", "Rift Gnat" },     Critter = { "\u{1FAB1}", "Rift Worm" },     Brute = { "\u{1F573}\u{FE0F}", "Tunnel Hulk" }, Elite = { "\u{1F30A}", "Throat Devourer" } },
	QuantumRealm    = { Swarmer = { "\u{1F4A0}", "Probability" },   Critter = { "\u{269B}\u{FE0F}", "Quark Sprite" }, Brute = { "\u{1F52C}", "Entangler" },  Elite = { "\u{1F9EC}", "Superposition" } },
	TimeRift        = { Swarmer = { "\u{23F1}\u{FE0F}", "Tick" },   Critter = { "\u{1F55B}", "Second Hand" },   Brute = { "\u{23F3}", "Hourglass Beast" }, Elite = { "\u{1F570}\u{FE0F}", "Aeon Warden" } },
	AntimatterZone  = { Swarmer = { "\u{26A1}", "Static Fleck" },   Critter = { "\u{1F4A2}", "Charge Fleck" },  Brute = { "\u{1F4A5}", "Annihilator" },   Elite = { "\u{2622}\u{FE0F}", "Null Reactor" } },
	DreamDimension  = { Swarmer = { "\u{1FAB6}", "Dozer Mote" },    Critter = { "\u{1F4A4}", "Lullaby Wisp" },  Brute = { "\u{1F631}", "Night Terror" },  Elite = { "\u{1F32B}\u{FE0F}", "Dream Eater" } },
	MirrorUniverse  = { Swarmer = { "\u{1F53B}", "Splinter" },      Critter = { "\u{1F539}", "Shard Shade" },   Brute = { "\u{1FA9E}", "Mirror Tyrant" }, Elite = { "\u{1F5FF}", "Reflection" } },
	VoidExpanse     = { Swarmer = { "\u{25AB}\u{FE0F}", "Null Speck" }, Critter = { "\u{1F311}", "Void Speck" }, Brute = { "\u{1F441}\u{FE0F}", "Hollow Watcher" }, Elite = { "\u{1F573}\u{FE0F}", "The Unmade" } },
	CelestialThrone = { Swarmer = { "\u{1FAB6}", "Gilded Moth" },   Critter = { "\u{1F54A}\u{FE0F}", "Gilded Cherub" }, Brute = { "\u{2694}\u{FE0F}", "Throne Sentinel" }, Elite = { "\u{1F451}", "Seraph Captain" } },
	Singularity     = { Swarmer = { "\u{1F4A0}", "Infall Speck" },  Critter = { "\u{1F4A0}", "Infall Mote" },   Brute = { "\u{1F30C}", "Collapse Herald" }, Elite = { "\u{1F320}", "Final Density" } },
	AbsolutePlane   = { Swarmer = { "\u{25AA}\u{FE0F}", "Axiom Chip" }, Critter = { "\u{1F53B}", "Axiom Shard" }, Brute = { "\u{1F53A}", "Absolute Warden" }, Elite = { "\u{1F781}", "The Postulate" } },
}

-- ===== APEX TIER =====
-- A fifth creature tier. One Apex per zone: the strongest and rarest thing in the strip, standing
-- alone on the zone's highest terrace shelf and locked behind 3 rebirths. Shaped exactly like a
-- CREATURE_NAMES tier entry -- { emoji, name } -- so creatureLabel() can read it unchanged. Each
-- name is written to out-rank that zone's Elite by one step: the Elite is the boss of the zone,
-- the Apex is the thing the Elite is afraid of.
local APEX_NAMES = {
	Forest          = { "\u{1F332}", "Heartwood Ancient" },
	Desert          = { "\u{1F3DC}\u{FE0F}", "Glass Pharaoh" },
	Ocean           = { "\u{1F531}", "Tidefather" },
	Volcano         = { "\u{1F479}", "Caldera Sovereign" },
	Moon            = { "\u{1F315}", "Selene Undying" },
	Mars            = { "\u{1F916}", "Ares Prime" },
	Galaxy          = { "\u{1FA90}", "Core of Suns" },
	BlackHole       = { "\u{1F300}", "The Hunger" },
	Multiverse      = { "\u{267E}\u{FE0F}", "Every Outcome" },
	Nebula          = { "\u{1F52E}", "Stellar Matriarch" },
	Wormhole        = { "\u{1F6AA}", "Mouth of Elsewhere" },
	QuantumRealm    = { "\u{1F3B2}", "Observer Zero" },
	TimeRift        = { "\u{23EE}\u{FE0F}", "The Last Hour" },
	AntimatterZone  = { "\u{1F4A3}", "Unmaker Core" },
	DreamDimension  = { "\u{1F47B}", "The Waking" },
	MirrorUniverse  = { "\u{1F464}", "Your Other" },
	VoidExpanse     = { "\u{1F5A4}", "Unbecoming" },
	CelestialThrone = { "\u{269C}\u{FE0F}", "The Enthroned" },
	Singularity     = { "\u{26AB}", "Zero Radius" },
	AbsolutePlane   = { "\u{1F31F}", "First Cause" },
}

-- MERGED IN rather than typed into the twenty rows above, which are one long line each. Keeping the
-- Apex names as their own block is what made 11.6 a readable diff instead of twenty rewritten lines,
-- and `creatureLabel` below needs no change at all -- it looks up CREATURE_NAMES[zone][tier] and by
-- the time it runs, `Apex` is simply one of the tiers that are there.
for zoneKey, entry in pairs(APEX_NAMES) do
	local byZone = CREATURE_NAMES[zoneKey]
	if byZone then
		byZone.Apex = entry
	end
end

-- Falls back to the tier's own generic label for any zone missing an entry, so a zone added to
-- GameConfig without a name here still spawns rather than erroring on a nil index.
local function creatureLabel(tierName, zone)
	local byZone = CREATURE_NAMES[zone.key]
	local named = byZone and byZone[tierName]
	if not named then
		return TIERS[tierName].label .. " (" .. zone.name .. ")"
	end
	return named[1] .. " " .. named[2]
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
	-- Detail parts are invisible to the mouse. A ClickDetector only fires for the part the cursor
	-- ray actually hits, and a rig is thirty pieces now -- with eyes, fangs, paws and antennae in
	-- front of the torso, half the clicks on a creature would land on a tooth and do nothing.
	-- buildRig turns CanQuery back on for the two parts that carry a detector.
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.model
	return p
end

-- pivot = the JOINT (pure translation from the body centre); rest = the part's own
-- offset/rotation out from that joint. The animation is applied BETWEEN the two, so a
-- leg swings around its hip instead of spinning around its own middle.
-- `chain` (optional) = { mid = CFrame, amp, speed, phase }. It inserts a SECOND hinge between the
-- pivot and the part: the frame becomes pivot -> rotate -> mid -> rotate -> rest. That is what a
-- knee is, and without it a leg is one rigid block swinging off the hip -- a pendulum, not a walk.
local function att(ctx, part, pivot, rest, motion, amp, speed, phase, chain)
	rest = rest or IDENTITY
	local a = {
		part = part,
		pivot = pivot,
		rest = rest,
		offset = pivot * (chain and chain.mid or IDENTITY) * rest,
		motion = motion,
		amp = amp or 0,
		speed = speed or 1,
		phase = phase or 0,
		chain = chain,
	}
	table.insert(ctx.atts, a)
	-- An orbiting part's angle lives in its phase rather than in its rest offset, so building it
	-- at `offset` stacks every bead of a ring at one point. The idle driver corrects that on its
	-- first tick -- but it only ticks near a player, so a zone nobody has walked into yet stood
	-- there with its rings collapsed into a single stick.
	if motion == "orbit" then
		part.CFrame = ctx.origin * pivot * CFrame.Angles(0, a.phase, 0) * rest
	else
		part.CFrame = ctx.origin * a.offset
	end
	return part
end

-- left/right mirror: a rig writes one side and gets the pair
local function pairUp(fn)
	for _, side in ipairs(SIDES) do
		fn(side)
	end
end

-- `count` parts spaced evenly around Y, each handed a joint whose +X already points outward
local function ringOf(ctx, count, radius, y, build)
	for i = 1, count do
		local a = (i - 1) * (math.pi * 2 / count)
		build(i, a, CFrame.new(math.cos(a) * radius, y, math.sin(a) * radius) * CFrame.Angles(0, -a, 0))
	end
end

-- ===== EXPRESSIONS =====
-- Rotate a brow block by +theta about Z and its +X end rises. On the right eye +X is the OUTER end,
-- so `side * theta` with theta POSITIVE lifts the outer corners and drops the inner ones: angry.
-- Negative does the reverse -- inner corners up over the nose -- which is the universal drawing of
-- *sad*. Every creature in this game was built at -12, and every heavy tier at -26, so the entire
-- world was pulling a hurt face. That one sign is most of what was wrong with them.
--
-- Six faces, hashed per species, driving brow angle, brow height, mouth curve and whether there is
-- a tongue in it. Heavy tiers draw from a meaner set -- a Brute that beams at you is funny once.
local FACES = {
	{ key = "grin",  brow = 10, lift = 0.62, curve = 1.0, teeth = 5 },
	{ key = "beam",  brow = 4,  lift = 0.8,  curve = 1.5, teeth = 0, tongue = true },
	{ key = "goofy", brow = 15, lift = 0.7,  curve = 0.9, teeth = 2, tongue = true, wonky = true },
	{ key = "wide",  brow = 2,  lift = 0.88, curve = 0.45, teeth = 0, round = true },
	{ key = "smug",  brow = 19, lift = 0.6,  curve = 0.85, teeth = 0, smirk = true },
	{ key = "snarl", brow = 27, lift = 0.55, curve = -0.4, teeth = 7 },
}
local HEAVY_FACES = { FACES[6], FACES[5], FACES[1], FACES[3] }

local function pickFace(zoneKey, tierName, isBrute)
	local list = isBrute and HEAVY_FACES or FACES
	return list[(keyHash(zoneKey, tierName, "face") % #list) + 1]
end

-- A mouth drawn as an arc of small ink blocks. `curve` > 0 smiles, < 0 scowls. One stretched black
-- block is what a mouth used to be here, and a flat black bar is the most miserable thing you can
-- put on a face -- it is the second half of the same bug as the brows.
local function grinArc(ctx, width, y, z, thick, curve, speed, phase)
	local n = ctx.detail >= 1 and 7 or 5
	for i = 1, n do
		local f = (i - 1) / (n - 1) - 0.5
		-- the corners rise (or fall) away from the centre on a parabola
		local lift = curve * width * 0.24 * (f * f * 4)
		local seg = mk(ctx, "MouthSeg", Enum.PartType.Block, Vector3.new(width / n * 1.5, thick, thick * 0.85), INK)
		att(ctx, seg, CFrame.new(f * width, y + lift, z), CFrame.Angles(0, 0, math.rad(-curve * f * 84)), "float", ctx.u * 0.022, speed or 1.9, phase or 0.4)
	end
	-- a round O instead of a line: the whole point of the "wide" face
	if ctx.face and ctx.face.round then
		local o = mk(ctx, "MouthO", Enum.PartType.Ball, Vector3.new(width * 0.42, width * 0.46, thick * 1.4), INK)
		att(ctx, o, CFrame.new(0, y - width * 0.06, z), IDENTITY, "float", ctx.u * 0.022, speed or 1.9, phase or 0.4)
	end
end

-- THE FACE, built the way PetModel and BossService build theirs: a pale sclera, a coloured iris, a
-- dark pupil and a glint, stacked front to back, under a brow.
--
-- Rigs face -Z, so each layer steps further along -Z to sit in FRONT of the last. Those offsets are
-- not decorative: these are spheres, and a layer only shows at all if it breaks the surface of the
-- one behind it.
--
-- The brow does the most work of anything here. Tilted down toward the nose it turns the same eye
-- from blank into a glare, and it is the one piece of the face still readable from across the
-- platform. Heavy tiers get a steeper tilt, which is most of why a Brute looks angrier than a
-- Critter wearing the same colours.
--
-- `ctx.detail` (0 Swarmer / 1 Critter / 2 Brute+Elite) decides how many layers get built.
local function eyePair(ctx, x, y, z, d, iris, speed, phase)
	local amp, sp, ph = ctx.u * 0.014, speed or 1.9, phase or 0.4
	local det = ctx.detail
	pairUp(function(side)
		local joint = CFrame.new(side * x, y, z)

		local face = ctx.face or FACES[1]
		-- "goofy" gives one eye a fifth more diameter than the other. Perfect symmetry is what
		-- makes a face read as manufactured, and one wonky eye undoes it for free.
		local ed = d * ((face.wonky and side < 0) and 1.2 or 1)

		local sclera = mk(ctx, "EyeWhite", Enum.PartType.Ball, Vector3.new(ed, ed, ed), BONE)
		att(ctx, sclera, joint, IDENTITY, "float", amp, sp, ph)

		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(ed * 0.72, ed * 0.72, ed * 0.72), iris, Enum.Material.Neon)
		att(ctx, eye, joint, CFrame.new(0, 0, -ed * 0.28), "float", amp, sp, ph)

		if det >= 1 then
			local pupil = mk(ctx, "Pupil", Enum.PartType.Block, Vector3.new(ed * 0.24, ed * 0.6, ed * 0.26), INK)
			att(ctx, pupil, joint, CFrame.new(0, 0, -ed * 0.58), "float", amp, sp, ph)
		end

		-- the smug half-lid: a slab of skin over the top third of the eye
		if face.smirk and det >= 1 then
			local lid = mk(ctx, "Eyelid", Enum.PartType.Ball, Vector3.new(ed * 1.02, ed * 0.52, ed * 1.02), ctx.pal.skin)
			att(ctx, lid, joint, CFrame.new(0, ed * 0.36, -ed * 0.06), "float", amp, sp, ph)
		end

		local brow = mk(ctx, "Brow", Enum.PartType.Block, Vector3.new(ed * 0.94, ed * 0.15, ed * 0.2), ctx.pal.ink)
		att(ctx, brow, joint, CFrame.new(0, ed * (0.3 + face.lift * 0.3), -ed * 0.4) * CFrame.Angles(0, 0, math.rad(side * face.brow)), "float", amp, sp, ph)

		if det >= 1 then
			-- the lid is parked just clear of the eye and drops over it on the blink cycle. Every
			-- species blinks on its own offset so a crowd never blinks in unison.
			local lid = mk(ctx, "Lid", Enum.PartType.Ball, Vector3.new(ed * 1.04, ed * 0.58, ed * 1.04), ctx.pal.skin)
			att(ctx, lid, joint, CFrame.new(0, ed * 1.0, -ed * 0.04), "blink", ed * 1.02, 1.05 + (ctx.u % 7) * 0.06, side * 0.12 + (ctx.u % 5))
		end

		if det >= 2 then
			-- two of them, a big one and a small one. One dot reads as a stray pixel; a pair reads
			-- as gloss, which is what every drawn eye in this style has.
			local glint = mk(ctx, "Glint", Enum.PartType.Ball, Vector3.new(ed * 0.26, ed * 0.26, ed * 0.26), Color3.fromRGB(255, 255, 255))
			att(ctx, glint, joint, CFrame.new(-side * ed * 0.19, ed * 0.2, -ed * 0.55), "float", amp, sp, ph)
			local spark = mk(ctx, "Glint", Enum.PartType.Ball, Vector3.new(ed * 0.13, ed * 0.13, ed * 0.13), Color3.fromRGB(255, 255, 255))
			att(ctx, spark, joint, CFrame.new(side * ed * 0.22, -ed * 0.18, -ed * 0.52), "float", amp, sp, ph)
		end
	end)
end

-- a row of fangs across a mouth, alternating up and down like a comic snarl. A Wedge's apex points
-- +Y, so the downward ones are rolled 180 degrees about X.
local function fangRow(ctx, count, width, y, z, len, motion, amp, speed, phase)
	for i = 1, count do
		local f = (count == 1) and 0 or ((i - 1) / (count - 1) - 0.5)
		local down = (i % 2 == 1)
		local tooth = mk(ctx, "Fang", Enum.PartType.Wedge, Vector3.new(len * 0.34, len, len * 0.42), BONE)
		att(ctx, tooth, CFrame.new(f * width, y, z),
			CFrame.Angles(math.rad(down and 180 or 0), 0, 0) * CFrame.new(0, len * 0.4, 0),
			motion, amp, speed, phase)
	end
end

-- A foot at the bottom of a limb, riding the limb's own joint so it swings with it. The dark paw is
-- what stops a leg looking like a stick pushed into the ground -- the same trick as the ink brow:
-- one near-black shape at the end of a light one reads as a drawn outline.
local function pawAt(ctx, joint, rest, w, motion, amp, speed, phase, claws, chain)
	local foot = mk(ctx, "Paw", Enum.PartType.Block, Vector3.new(w, w * 0.46, w * 1.2), ctx.pal.ink)
	att(ctx, foot, joint, rest, motion, amp, speed, phase, chain)
	if claws then
		for i = -1, 1 do
			local claw = mk(ctx, "Claw", Enum.PartType.Wedge, Vector3.new(w * 0.2, w * 0.34, w * 0.3), BONE)
			att(ctx, claw, joint, rest * CFrame.new(i * w * 0.3, -w * 0.06, -w * 0.6) * CFrame.Angles(math.rad(90), 0, 0), motion, amp, speed, phase, chain)
		end
	end
	return foot
end

-- A limb in four pieces off one hip: thigh, knee ball, shin, foot. The shin and the foot hang off
-- the SECOND hinge (see att's `chain`) and lag the thigh by about a third of a cycle, which is what
-- a knee does and what turns a swinging stick into a stride. The knee ball is in the trim colour on
-- purpose -- a bright bead at the bend is the cheapest way to show there is a bend at all.
local function limbAt(ctx, joint, o)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	local w = o.w
	local thigh, shin = o.thigh, o.shin
	local amp, speed, phase = o.amp or 0.45, o.speed or 3.0, o.phase or 0
	local skin = o.color or pal.dark
	local chain = { mid = CFrame.new(0, -thigh, 0), amp = amp * 0.55, speed = speed, phase = phase + 2.1 }

	local upper = mk(ctx, o.name or "Leg", Enum.PartType.Block, Vector3.new(w, thigh, w * 0.94), skin, o.material)
	att(ctx, upper, joint, CFrame.new(0, -thigh * 0.5, 0), "swing", amp, speed, phase)

	local lower = mk(ctx, "Shin", Enum.PartType.Block, Vector3.new(w * 0.84, shin, w * 0.8), o.shinColor or skin, o.material)
	att(ctx, lower, joint, CFrame.new(0, -shin * 0.5, 0), "swing", amp, speed, phase, chain)

	if det >= 1 then
		local knee = mk(ctx, "Joint", Enum.PartType.Ball, Vector3.new(w * 1.06, w * 1.06, w * 1.06), o.jointColor or pal.trim, o.material)
		att(ctx, knee, joint, CFrame.new(0, -thigh, 0), "swing", amp, speed, phase)
	end

	if o.foot ~= false then
		pawAt(ctx, joint, CFrame.new(0, -shin - w * 0.2, -w * 0.14), o.footWidth or (w * 1.18),
			"swing", amp, speed, phase, o.claws, chain)
	end
end

-- There is no torus primitive in Roblox and a Cylinder ring renders as a solid disc, so every ring
-- in this file is a circle of small blocks. `spin` makes it revolve (signed, so two rings can
-- counter-rotate); without it the ring just breathes in place.
local function beadRing(ctx, count, radius, y, bead, color, material, spin)
	for i = 1, count do
		local a = (i - 1) * (math.pi * 2 / count)
		local b = mk(ctx, "Bead", Enum.PartType.Block, Vector3.new(bead * 0.72, bead, bead), color, material)
		if spin then
			att(ctx, b, CFrame.new(0, y, 0), CFrame.new(radius, 0, 0), "orbit", 0, spin, a)
		else
			att(ctx, b, CFrame.new(math.cos(a) * radius, y, math.sin(a) * radius) * CFrame.Angles(0, -a, 0), IDENTITY, "float", ctx.u * 0.012, 1.6, a)
		end
	end
end

-- shared Brute dressing: a symmetric pair of shoulder spikes
local function bruteSpikes(ctx, x, y, z, len)
	local u, pal = ctx.u, ctx.pal
	pairUp(function(side)
		local spike = mk(ctx, "Spike", Enum.PartType.Wedge, Vector3.new(u * 0.09, len, u * 0.16), pal.dark, Enum.Material.Slate)
		att(ctx, spike, CFrame.new(side * x, y, z), CFrame.Angles(math.rad(-18), 0, math.rad(side * 26)), "float", u * 0.015, 1.9, 0.4)
	end)
end

-- The Elite tell. It used to be a ring of six spikes around the BODY at a hand-tuned radius per
-- rig, which on anything narrower than the dog meant six flat gold slabs hanging in mid-air beside
-- the creature with nothing under them -- by some distance the noisiest thing in the world.
--
-- A crown instead, on the one place every rig already declares (`ctx.top`). It reads instantly at
-- any distance, it never floats, and it costs seven parts on the 60 creatures that wear it.
local function eliteCrown(ctx)
	if not ctx.pal.isElite or not ctx.top then return end
	local u = ctx.u
	local gold = Color3.fromRGB(255, 205, 70)
	local band = mk(ctx, "CrownBand", Enum.PartType.Ball, Vector3.new(u * 0.38, u * 0.13, u * 0.38), gold, Enum.Material.Metal)
	att(ctx, band, ctx.top, CFrame.new(0, u * 0.05, 0), "float", u * 0.02, 1.9, 0.4)
	for i = -2, 2 do
		local h = u * (0.17 - math.abs(i) * 0.03)
		local spike = mk(ctx, "CrownSpike", Enum.PartType.Wedge, Vector3.new(u * 0.06, h, u * 0.075), gold, Enum.Material.Metal)
		att(ctx, spike, ctx.top, CFrame.new(i * u * 0.095, u * 0.1 + h * 0.5, -math.abs(i) * u * 0.016), "float", u * 0.02, 1.9, 0.4)
	end
	local jewel = mk(ctx, "CrownJewel", Enum.PartType.Ball, Vector3.new(u * 0.11, u * 0.11, u * 0.07), Color3.fromRGB(255, 240, 160), Enum.Material.Neon)
	att(ctx, jewel, ctx.top, CFrame.new(0, u * 0.06, -u * 0.18), "float", u * 0.02, 1.9, 0.4)
end

-- ===== the cartoon dressing =====
-- These are what separate "a shape with eyes stuck on it" from a character, and they are the
-- cheapest parts in the file. The reference art this game is chasing is all oversized head,
-- oversized eye and two or three flat colour accents -- never rendering, never texture.

-- flat colour discs on the cheeks. Balls squashed on Z so they sit ON the face instead of bulging
-- out of it.
local function cheeks(ctx, x, y, z, d, color, speed, phase)
	pairUp(function(side)
		local c = mk(ctx, "Cheek", Enum.PartType.Ball, Vector3.new(d, d * 0.78, d * 0.5), color)
		att(ctx, c, CFrame.new(side * x, y, z), IDENTITY, "float", ctx.u * 0.014, speed or 1.9, phase or 0.4)
	end)
end

-- a tongue lolling out of a mouth. Two parts, and the single most effective goofy detail there is.
local function tongue(ctx, y, z, w, speed, phase)
	local t = mk(ctx, "Tongue", Enum.PartType.Block, Vector3.new(w, w * 0.34, w * 1.5), Color3.fromRGB(255, 122, 150))
	att(ctx, t, CFrame.new(0, y, z), CFrame.Angles(math.rad(-34), 0, 0) * CFrame.new(0, 0, -w * 0.6), "swing", 0.14, speed or 2.2, phase or 0.9)
	local tip = mk(ctx, "TongueTip", Enum.PartType.Ball, Vector3.new(w, w * 0.4, w * 0.8), Color3.fromRGB(255, 152, 174))
	att(ctx, tip, CFrame.new(0, y, z), CFrame.Angles(math.rad(-34), 0, 0) * CFrame.new(0, 0, -w * 1.3), "swing", 0.14, speed or 2.2, phase or 0.9)
end

-- flat patches laid over a back. Balls squashed on Y, placed on the golden angle so three of them
-- never come out in a straight row.
local function spots(ctx, n, color, y, z0, spread, d)
	for i = 1, n do
		local a = i * 2.399963
		local p = mk(ctx, "Spot", Enum.PartType.Ball, Vector3.new(d * (0.85 + (i % 3) * 0.16), d * 0.4, d), color)
		att(ctx, p, CFrame.new(math.cos(a) * spread, y, z0 + math.sin(a) * spread * 1.6), IDENTITY, nil)
	end
end

-- ===== toppers =====
-- One hash-picked accessory sitting on top of whatever each rig declared as the crown of its head.
-- Five kinds in the coat and trim hues, so two creatures of the same archetype are not just the
-- same animal in two colours -- one is wearing a bow and the other a cap. This is the cheapest
-- per-species identity in the file: three or four parts.
local TOPPERS = { "bow", "cap", "star", "gem", "leaf" }

local function addTopper(ctx, zoneKey, tierName)
	local top = ctx.top
	if not top or ctx.detail < 1 or ctx.pal.isElite then return end
	local u, pal = ctx.u, ctx.pal
	local kind = TOPPERS[(keyHash(zoneKey, tierName, "topper") % #TOPPERS) + 1]
	local F, FP = 1.9, 0.4

	if kind == "bow" then
		pairUp(function(side)
			local loop = mk(ctx, "BowLoop", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.2, u * 0.24), pal.coat)
			att(ctx, loop, top, CFrame.new(side * u * 0.16, u * 0.05, 0) * CFrame.Angles(0, 0, math.rad(side * 90)), "float", u * 0.02, F, FP)
		end)
		local knot = mk(ctx, "BowKnot", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.13, u * 0.13), pal.trim)
		att(ctx, knot, top, CFrame.new(0, u * 0.05, 0), "float", u * 0.02, F, FP)
	elseif kind == "cap" then
		local crown = mk(ctx, "CapCrown", Enum.PartType.Ball, Vector3.new(u * 0.4, u * 0.24, u * 0.4), pal.coat)
		att(ctx, crown, top, CFrame.new(0, u * 0.06, 0), "float", u * 0.02, F, FP)
		local brim = mk(ctx, "CapBrim", Enum.PartType.Block, Vector3.new(u * 0.34, u * 0.04, u * 0.26), pal.trim)
		att(ctx, brim, top, CFrame.new(0, u * 0.02, -u * 0.22), "float", u * 0.02, F, FP)
		local button = mk(ctx, "CapButton", Enum.PartType.Ball, Vector3.new(u * 0.1, u * 0.1, u * 0.1), pal.trim)
		att(ctx, button, top, CFrame.new(0, u * 0.19, 0), "float", u * 0.02, F, FP)
	elseif kind == "star" then
		-- five points on a ring plus a hub: a Wedge apex points +Y, so each one is rolled to its
		-- own angle around the hub rather than all pointing up
		local hub = mk(ctx, "StarHub", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.13, u * 0.08), pal.coat, Enum.Material.Neon)
		att(ctx, hub, top, CFrame.new(0, u * 0.2, 0), "float", u * 0.03, 1.4, 0.2)
		for i = 1, 5 do
			local a = (i - 1) * (math.pi * 2 / 5)
			local point = mk(ctx, "StarPoint", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.14, u * 0.1), pal.coat, Enum.Material.Neon)
			att(ctx, point, top, CFrame.new(math.sin(a) * u * 0.11, u * 0.2 + math.cos(a) * u * 0.11, 0) * CFrame.Angles(0, 0, -a), "float", u * 0.03, 1.4, 0.2)
		end
	elseif kind == "gem" then
		local stalk = mk(ctx, "GemStalk", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.14, u * 0.05), pal.trim)
		att(ctx, stalk, top, CFrame.new(0, u * 0.07, 0), "float", u * 0.02, F, FP)
		local stone = mk(ctx, "GemStone", Enum.PartType.Ball, Vector3.new(u * 0.19, u * 0.24, u * 0.19), pal.coat, Enum.Material.Neon)
		att(ctx, stone, top, CFrame.new(0, u * 0.24, 0), "float", u * 0.034, 1.5, 0.8)
		for i = 1, 3 do
			local a = (i - 1) * (math.pi * 2 / 3)
			local spark = mk(ctx, "GemSpark", Enum.PartType.Ball, Vector3.new(u * 0.06, u * 0.06, u * 0.06), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
			att(ctx, spark, top * CFrame.new(0, u * 0.24, 0), CFrame.new(u * 0.2, 0, 0), "orbit", 0, 1.4, a)
		end
	else -- leaf
		pairUp(function(side)
			local leaf = mk(ctx, "Leaf", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.24, u * 0.14), pal.coat)
			att(ctx, leaf, top, CFrame.new(side * u * 0.08, u * 0.1, 0) * CFrame.Angles(math.rad(-14), 0, math.rad(side * -38)), "flap", 0.14, 2.1, side > 0 and 0 or 1.2)
		end)
		local stem = mk(ctx, "LeafStem", Enum.PartType.Block, Vector3.new(u * 0.04, u * 0.12, u * 0.04), pal.trim)
		att(ctx, stem, top, CFrame.new(0, u * 0.06, 0), "float", u * 0.02, F, FP)
	end
end

-- ===== GENERATED MESH RIGS ====================================================================
-- A creature whose figure was GENERATED (ReplicatedStorage.Assets.CreatureMeshes.
-- CreatureMesh_<ARCHETYPE>_<Tier>) instead of assembled below out of primitives. Exactly the
-- shape BossService.meshRig already uses, and for the same reason: the bosses read as finished
-- creatures while a 30-part primitive rig reads as a stack of coloured boxes.
--
-- The template is a Model of six MeshParts named `head_geom` / `torso_geom` / `left arm_geom` /
-- `right arm_geom` / `left leg_geom` / `right leg_geom` -- the segmentation asked for at
-- generation time, and the whole reason a generated creature can still move: the idle driver
-- poses whole PARTS, so six pieces is six joints. Ask for one undivided mesh and it is a statue.
--
-- Falls through to the primitive rigs below when a mesh for this archetype/tier does not exist,
-- so the rollout is safe at every point during a run of 56 generations.
local MESH_GROUND_CLEAR = 0.5

-- Which joint each limb swings around, and on what phase. Diagonal gait: the left arm and the
-- right leg carry the same phase, which is what stops the walk reading as a hop.
local MESH_LIMB = {
	["head_geom"]      = { motion = "float", amp = 0.020, speed = 1.4, phase = 0.3,     joint = "bottom" },
	["left arm_geom"]  = { motion = "swing", amp = 0.24,  speed = 1.9, phase = 0,       joint = "top" },
	["right arm_geom"] = { motion = "swing", amp = 0.24,  speed = 1.9, phase = math.pi, joint = "top" },
	["left leg_geom"]  = { motion = "swing", amp = 0.15,  speed = 1.9, phase = math.pi, joint = "top" },
	["right leg_geom"] = { motion = "swing", amp = 0.15,  speed = 1.9, phase = 0,       joint = "top" },
}

-- CASE-INSENSITIVE ON THE TIER, deliberately.
--
-- The archetype is upper case everywhere (see ZONE_ARCHETYPE), but the tier is written `Brute` in
-- TIERS while the generation agents filed their models as `BEAST_BRUTE`. An exact lookup found
-- nothing, so every creature in the game quietly fell back to primitives -- which looks exactly
-- like the meshes never having been generated, with no error anywhere to say otherwise.
--
-- Matching on the upper-cased name accepts either spelling, so a later batch filed as `Brute`
-- works too and nobody has to remember which way round it was.
local function creatureMeshTemplate(archetype, tierName)
	local assets = RS:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("CreatureMeshes")
	if not folder then return nil end
	local want = string.upper(("CreatureMesh_%s_%s"):format(archetype, tierName))
	for _, m in ipairs(folder:GetChildren()) do
		if string.upper(m.Name) == want then return m end
	end
	return nil
end

-- Returns the part to be used as the rig's body, or nil to fall through to the primitive rig.
local function meshRig(ctx, template)
	local clone = template:Clone()
	-- RECURSIVE: the generator wraps every segment in its own sub-Model (`torso` holding
	-- `torso_geom`). A non-recursive lookup finds nothing, this returns nil, and the creature
	-- silently falls back to primitives -- which looks exactly like the mesh never existing.
	local torso = clone:FindFirstChild("torso_geom", true)
	if not torso then
		clone:Destroy()
		return nil
	end

	-- SCALED ON ITS LARGEST AXIS, NOT ON ITS HEIGHT.
	--
	-- `tier.size` feeds the hit box, the aura range, the name plate height and the spacing the
	-- spawner keeps between creatures, and the primitive rigs measure roughly 1.2u across their
	-- widest point. Scaling a generated mesh so its HEIGHT is u looked right and was wrong for the
	-- shape these actually are: a beast is a low four-legged animal, longer nose to tail than it is
	-- tall, so height-matching blew it up sideways -- a 6.5-stud Swarmer measured 15.5 studs wide,
	-- two and a half times its own footprint, and a clearing meant to hold six of them held two.
	--
	-- Matching the largest dimension instead means a tall creature and a long one both occupy the
	-- ground the game budgeted for them, whatever proportions the generator chose.
	local _, tSize = clone:GetBoundingBox()
	local widest = math.max(tSize.X, tSize.Y, tSize.Z)
	if widest < 0.01 then
		clone:Destroy()
		return nil
	end
	clone:ScaleTo((ctx.u * 1.15) / widest)

	-- WHERE THE FEET ARE. `origin` is a body CENTRE -- the primitive rigs hang their legs below it,
	-- so the ground sits well beneath. Dropping a generated figure's torso straight onto origin
	-- buries it to the belly. Measure how far the torso centre stands above the lowest point of the
	-- finished mesh and lift the whole figure by that, so it stands ON the ground.
	--
	-- SUBTRACT HOW HIGH THE BODY SITS ABOVE ITS OWN FLOOR, NOT ITS WORLD ALTITUDE (10.14).
	--
	-- This line used to read `footDrop - ctx.origin.Position.Y + MESH_GROUND_CLEAR`, and everything
	-- built here is an offset that the driver applies as `origin * offset` -- so `origin.Y` went in
	-- once with a plus and once with a minus and CANCELLED. Every generated figure in the game was
	-- therefore drawn with its feet at absolute `y = MESH_GROUND_CLEAR` whatever the creature's own
	-- altitude, which was invisible for as long as every creature stood in a valley whose floor is
	-- y = 0, and became the reported bug the moment 9.4 put four Elites and six Brutes per zone up on
	-- the terraces: the invisible Body carried the health plate up to 92 studs, `GroundRing` drew
	-- itself on the shelf at `floorY + 0.35` -- and the six mesh segments stayed lying in the valley
	-- 78 studs below. A health plate and a gold disc on a cliff with no creature under them.
	--
	-- The quantity that was always meant here is the body's height above the ground it is standing
	-- on. `spawnCreature` puts the body at `floorY + base.size * 0.56`, so on the valley floor
	-- (floorY = 0) this is arithmetically identical to the old line and nothing on the flat moves by
	-- a stud; on a shelf it is the whole fix.
	local bbCF, bbSize = clone:GetBoundingBox()
	local footDrop = torso.Position.Y - (bbCF.Position.Y - bbSize.Y * 0.5)
	local bodyAboveFloor = ctx.origin.Position.Y - (ctx.floorY or 0)
	local lift = CFrame.new(0, footDrop - bodyAboveFloor + MESH_GROUND_CLEAR, 0)

	-- The body is an INVISIBLE ANCHOR rather than the torso itself: buildRig plants the body
	-- exactly on origin and the torso has to sit above it by `lift`, so the torso becomes one more
	-- attachment like the limbs and the thing pinned to origin carries no geometry. It stays
	-- collidable -- it is what a player walks into.
	local anchor = mk(ctx, "Body", Enum.PartType.Block,
		Vector3.new(ctx.u * 0.42, ctx.u * 0.42, ctx.u * 0.42), ctx.pal.skin, nil, 1)

	local base = torso.CFrame
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false

			-- TINTED BY THE ZONE, because fourteen archetypes have to cover twenty zones.
			--
			-- Six pairs share one: Desert and Antimatter are both ARACHNID, Moon and Singularity both
			-- DRIFTER, Mars and TimeRift both MECH, and so on. Untinted, those pairs are the same
			-- animal twice -- and the whole reason the primitive rigs took a palette was that a Forest
			-- wolf and a Volcano wolf should read as two different creatures.
			--
			-- A Color on a textured MeshPart MULTIPLIES the texture rather than replacing it, so the
			-- generated detail survives and only the hue moves. Kept light (a lerp toward the zone's
			-- skin, not a flat repaint) for exactly that reason: at full strength the texture's own
			-- shading is crushed and the creature goes back to reading as one solid lump.
			if part:IsA("MeshPart") and ctx.pal and ctx.pal.skin then
				part.Color = part.Color:Lerp(ctx.pal.skin, 0.55)
			end

			part.Parent = ctx.model
			local offset = lift * (base:Inverse() * part.CFrame)
			local spec = MESH_LIMB[part.Name]
			if spec then
				-- A limb rotated about its own middle spins; about its shoulder it swings. Put the
				-- joint at the end the body holds and hand the part the other half back as `rest`,
				-- so pivot * rest still lands on the offset measured above.
				local half = part.Size.Y * 0.5 * (spec.joint == "top" and 1 or -1)
				att(ctx, part, offset * CFrame.new(0, half, 0), CFrame.new(0, -half, 0),
					spec.motion, spec.motion == "float" and ctx.u * spec.amp or spec.amp,
					spec.speed, spec.phase)
			else
				-- the torso, and anything the generator named unexpectedly: no motion of its own,
				-- but it still has to travel with the body when the creature turns to face a player
				att(ctx, part, offset, IDENTITY, "none", 0, 1, 0)
			end
		end
	end
	clone:Destroy()
	return anchor
end

local RIGS = {}

-- BEAST (Forest) -- the cartoon dog, and the proportion study for every other rig here. The head is
-- WIDER than the body and the eyes are more than a third of the head: that ratio is the whole
-- difference between a character and an animal, and no amount of extra parts substitutes for it.
-- Big head, stubby legs, open mouth, one flat accent per feature. 32 / 58 / 66 parts by tier.
function RIGS.BEAST(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	local F, FP = 1.9, 0.4 -- the head bob every facial part has to share, or the face comes apart

	ctx.top = CFrame.new(0, u * 0.86, -u * 0.6)
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.64, u * 0.52, u * 0.78), pal.skin)

	local belly = mk(ctx, "Belly", Enum.PartType.Block, Vector3.new(u * 0.5, u * 0.2, u * 0.62), pal.belly)
	att(ctx, belly, CFrame.new(0, -u * 0.19, 0), IDENTITY, nil)

	local haunch = mk(ctx, "Haunch", Enum.PartType.Ball, Vector3.new(u * 0.62, u * 0.58, u * 0.54), pal.skin)
	att(ctx, haunch, CFrame.new(0, u * 0.05, u * 0.28), IDENTITY, "float", u * 0.012, F, FP)

	local ruff = mk(ctx, "Ruff", Enum.PartType.Ball, Vector3.new(u * 0.72, u * 0.62, u * 0.44), pal.dark)
	att(ctx, ruff, CFrame.new(0, u * 0.16, -u * 0.28), IDENTITY, "float", u * 0.016, F, FP)

	-- THE HEAD: 0.78u across against a 0.64u body. Bigger than the thing carrying it.
	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.78, u * 0.68, u * 0.62), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.52, -u * 0.6), IDENTITY, "float", u * 0.022, F, FP)

	if det >= 1 then
		pairUp(function(side)
			local jowl = mk(ctx, "Jowl", Enum.PartType.Ball, Vector3.new(u * 0.3, u * 0.28, u * 0.32), pal.skin)
			att(ctx, jowl, CFrame.new(side * u * 0.28, u * 0.3, -u * 0.8), IDENTITY, "float", u * 0.022, F, FP)
		end)
	end

	-- a muzzle PATCH flush against the lower face, rather than a snout sticking out of it. Built
	-- level with the eyes first time round, where -- being a solid block 0.3u proud of the head --
	-- it stood squarely in front of them and hid the best thing on the rig.
	local snout = mk(ctx, "Snout", Enum.PartType.Block, Vector3.new(u * 0.42, u * 0.24, u * 0.2), pal.belly)
	att(ctx, snout, CFrame.new(0, u * 0.34, -u * 0.98), IDENTITY, "float", u * 0.022, F, FP)

	local nose = mk(ctx, "Nose", Enum.PartType.Ball, Vector3.new(u * 0.2, u * 0.17, u * 0.16), pal.ink)
	att(ctx, nose, CFrame.new(0, u * 0.4, -u * 1.06), IDENTITY, "float", u * 0.022, F, FP)
	if det >= 1 then
		local shine = mk(ctx, "NoseShine", Enum.PartType.Ball, Vector3.new(u * 0.07, u * 0.06, u * 0.05), Color3.fromRGB(255, 255, 255))
		att(ctx, shine, CFrame.new(-u * 0.05, u * 0.44, -u * 1.11), IDENTITY, "float", u * 0.022, F, FP)
	end

	-- an open mouth is worth more than any number of teeth on a closed one
	grinArc(ctx, u * 0.38, u * 0.22, -u * 0.97, u * 0.07, ctx.face.curve, F, FP)
	if det >= 1 and ctx.face.tongue then
		tongue(ctx, u * 0.17, -u * 0.98, u * 0.11, F, 0.9)
	end
	if ctx.face.teeth > 0 then
		fangRow(ctx, det >= 1 and ctx.face.teeth or 3, u * 0.26, u * 0.26, -u * 1.02, u * 0.12, "float", u * 0.022, F, FP)
	end

	-- THE EYES: 0.3u across on a 0.78u head, sitting proud of a face 0.91u deep. They own the top
	-- two thirds of the head; nothing else goes up there.
	eyePair(ctx, u * 0.21, u * 0.63, -u * 0.94, u * 0.3, pal.iris, F, FP)
	if det >= 1 then
		cheeks(ctx, u * 0.34, u * 0.42, -u * 0.88, u * 0.2, lighten(pal.coat, 0.18), F, FP)
	end

	pairUp(function(side)
		if pal.isBrute then
			-- rolled OUTWARD. Rolled inward (which is what the sign says at a glance) the pair meet
			-- over the skull and the creature wears a pitched roof.
			local hj = CFrame.new(side * u * 0.3, u * 0.82, -u * 0.5)
			local horn = mk(ctx, "Horn", Enum.PartType.Wedge, Vector3.new(u * 0.15, u * 0.5, u * 0.22), pal.dark, Enum.Material.Slate)
			att(ctx, horn, hj, CFrame.Angles(math.rad(-14), 0, math.rad(side * -36)) * CFrame.new(0, u * 0.25, 0), "float", u * 0.026, F, FP)
			local band = mk(ctx, "HornBand", Enum.PartType.Block, Vector3.new(u * 0.17, u * 0.06, u * 0.22), pal.trim, Enum.Material.Metal)
			att(ctx, band, hj, CFrame.Angles(math.rad(-14), 0, math.rad(side * -36)) * CFrame.new(0, u * 0.14, 0), "float", u * 0.026, F, FP)
		else
			-- ears flop on Z ("flap"), not yaw on Y: a yawing ear looks like a radar dish
			local ej = CFrame.new(side * u * 0.32, u * 0.8, -u * 0.5)
			-- "flap" is the constant sway; the flick underneath it is what makes an ear read as
			-- attached to something alive rather than to a hinge
			local ear = mk(ctx, "Ear", Enum.PartType.Wedge, Vector3.new(u * 0.13, u * 0.42, u * 0.26), pal.dark)
			att(ctx, ear, ej, CFrame.Angles(0, 0, math.rad(side * -32)) * CFrame.new(0, u * 0.21, 0), "flick", 0.34, 0.7 + side * 0.09, side * 1.7)
			if det >= 1 then
				local inner = mk(ctx, "EarInner", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.3, u * 0.18), lighten(pal.coat, 0.16))
				att(ctx, inner, ej, CFrame.Angles(0, 0, math.rad(side * -32)) * CFrame.new(0, u * 0.18, -u * 0.05), "flick", 0.34, 0.7 + side * 0.09, side * 1.7)
			end
		end
	end)

	if det >= 1 then
		local collar = mk(ctx, "Collar", Enum.PartType.Block, Vector3.new(u * 0.68, u * 0.14, u * 0.5), pal.trim)
		att(ctx, collar, CFrame.new(0, u * 0.2, -u * 0.3), IDENTITY, "float", u * 0.016, F, FP)
		local tag = mk(ctx, "CollarTag", Enum.PartType.Ball, Vector3.new(u * 0.18, u * 0.18, u * 0.07), Color3.fromRGB(255, 205, 70), Enum.Material.Metal)
		att(ctx, tag, CFrame.new(0, u * 0.1, -u * 0.52), IDENTITY, "trail", 0.3, 2.4, 0.5)
		spots(ctx, 4, pal.coat, u * 0.26, u * 0.04, u * 0.16, u * 0.22)

		-- pale chest bib: it breaks the run of skin colour between the collar and the front legs,
		-- which is the biggest single-tone area left on the rig
		local bib = mk(ctx, "Bib", Enum.PartType.Ball, Vector3.new(u * 0.42, u * 0.36, u * 0.26), pal.belly)
		att(ctx, bib, CFrame.new(0, u * 0.02, -u * 0.36), IDENTITY, "float", u * 0.012, F, FP)

		pairUp(function(side)
			local tuft = mk(ctx, "BrowTuft", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.13, u * 0.11), pal.coat)
			att(ctx, tuft, CFrame.new(side * u * 0.22, u * 0.8, -u * 0.84), CFrame.Angles(0, 0, math.rad(side * -20)), "float", u * 0.022, F, FP)
			for i = 1, 2 do
				local freckle = mk(ctx, "Freckle", Enum.PartType.Ball, Vector3.new(u * 0.055, u * 0.05, u * 0.03), pal.coat)
				att(ctx, freckle, CFrame.new(side * (u * 0.2 + i * u * 0.07), u * 0.3 - i * u * 0.04, -u * 0.94), IDENTITY, "float", u * 0.022, F, FP)
			end
		end)
	end

	-- diagonal gait: front-left + back-right swing together. Stubby and thick -- long thin legs are
	-- the fastest way to undo a big head.
	local legPhase = { 0, math.pi, math.pi, 0 }
	local n = 0
	for _, dz in ipairs({ -u * 0.24, u * 0.26 }) do
		for _, dx in ipairs({ -u * 0.22, u * 0.22 }) do
			n += 1
			local joint = CFrame.new(dx, -u * 0.17, dz)
			-- claws on the front pair only: twelve wedges to draw something behind the animal
			limbAt(ctx, joint, {
				w = u * 0.19, thigh = u * 0.17, shin = u * 0.17,
				amp = 0.5, speed = 3.2, phase = legPhase[n],
				color = pal.dark, shinColor = pal.belly, jointColor = pal.coat,
				footWidth = u * 0.24, claws = det >= 2 and n <= 2,
			})
		end
	end

	local tailJoint = CFrame.new(0, u * 0.2, u * 0.4)
	local tail = mk(ctx, "Tail", Enum.PartType.Block, Vector3.new(u * 0.16, u * 0.16, u * 0.42), pal.skin)
	att(ctx, tail, tailJoint, CFrame.Angles(math.rad(-46), 0, 0) * CFrame.new(0, 0, u * 0.21), "trail", 0.5, 2.6, 0)
	local tuft = mk(ctx, "TailTuft", Enum.PartType.Ball, Vector3.new(u * 0.3, u * 0.3, u * 0.32), pal.belly)
	att(ctx, tuft, tailJoint, CFrame.Angles(math.rad(-46), 0, 0) * CFrame.new(0, 0, u * 0.46), "trail", 0.5, 2.6, 0)
	if det >= 1 then
		for i = 1, 2 do
			local ring = mk(ctx, "TailRing", Enum.PartType.Block, Vector3.new(u * 0.19, u * 0.19, u * 0.06), pal.coat)
			att(ctx, ring, tailJoint, CFrame.Angles(math.rad(-46), 0, 0) * CFrame.new(0, 0, u * (0.12 + i * 0.14)), "trail", 0.5, 2.6, 0)
		end
	end

	if pal.isBrute then
		for i = 1, 3 do
			local ridge = mk(ctx, "SpineSpike", Enum.PartType.Wedge, Vector3.new(u * 0.1, u * 0.26 - i * u * 0.04, u * 0.18), pal.dark, Enum.Material.Slate)
			att(ctx, ridge, CFrame.new(0, u * 0.28, -u * 0.04 + i * u * 0.17), CFrame.new(0, u * 0.12, 0), "float", u * 0.014, F, FP)
		end
		bruteSpikes(ctx, u * 0.3, u * 0.32, -u * 0.22, u * 0.32)
	end
	eliteCrown(ctx)

	return body
end

-- ARACHNID (Desert, AntimatterZone) -- a banded abdomen behind a big-eyed cephalothorax, six or
-- eight KNEED legs (a straight stick per side reads as a table leg; the knee is what makes it an
-- insect), mandibles, and a scorpion tail curling up over the back.
function RIGS.ARACHNID(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.42, -u * 0.5)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.52, u * 0.5, u * 0.56), pal.skin)

	local abdomen = mk(ctx, "Abdomen", Enum.PartType.Ball, Vector3.new(u * 0.58, u * 0.52, u * 0.62), pal.skin)
	att(ctx, abdomen, CFrame.new(0, u * 0.04, u * 0.34), IDENTITY, "float", u * 0.012, 2.2, 0.6)

	-- the bands are most of why it reads as a bug instead of as two balls stuck together
	if det >= 1 then
		for i = 1, 3 do
			local band = mk(ctx, "Band", Enum.PartType.Block, Vector3.new(u * 0.52 - i * u * 0.055, u * 0.44 - i * u * 0.05, u * 0.05), pal.ink)
			att(ctx, band, CFrame.new(0, u * 0.05, u * 0.18 + i * u * 0.14), IDENTITY, "float", u * 0.012, 2.2, 0.6)
		end
		-- the marking every real spider is recognised by, and the only warm colour on the back
		for i = 1, 3 do
			local mark = mk(ctx, "AbdomenMark", Enum.PartType.Ball, Vector3.new(u * (0.3 - i * 0.06), u * 0.07, u * (0.24 - i * 0.05)), pal.coat)
			att(ctx, mark, CFrame.new(0, u * 0.28, u * (0.18 + i * 0.13)), IDENTITY, "float", u * 0.012, 2.2, 0.6)
		end
	end

	local head = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.6, u * 0.54, u * 0.58), pal.dark)
	att(ctx, head, CFrame.new(0, u * 0.12, -u * 0.5), IDENTITY, "float", u * 0.015, 2.2, 0.6)

	eyePair(ctx, u * 0.17, u * 0.22, -u * 0.76, u * 0.26, pal.iris, 2.2, 0.6)
	if det >= 1 then
		-- the extra pair low and wide: a spider's tell, and it stops the big two reading as a face
		-- borrowed from the dog
		pairUp(function(side)
			local small = mk(ctx, "EyeSmall", Enum.PartType.Ball, Vector3.new(u * 0.11, u * 0.11, u * 0.11), pal.iris, Enum.Material.Neon)
			att(ctx, small, CFrame.new(side * u * 0.26, u * 0.02, -u * 0.66), IDENTITY, "float", u * 0.015, 2.2, 0.6)
		end)
		cheeks(ctx, u * 0.3, u * 0.06, -u * 0.66, u * 0.16, lighten(pal.coat, 0.2), 2.2, 0.6)
	end
	grinArc(ctx, u * 0.3, -u * 0.08, -u * 0.72, u * 0.06, ctx.face.curve, 2.2, 0.6)
	if ctx.face.teeth > 0 then
		fangRow(ctx, det >= 1 and 4 or 2, u * 0.2, -u * 0.09, -u * 0.78, u * 0.1, "float", u * 0.015, 2.2, 0.6)
	end
	if det >= 1 and ctx.face.tongue then
		tongue(ctx, -u * 0.13, -u * 0.74, u * 0.09, 2.2, 0.6)
	end

	pairUp(function(side)
		local mand = mk(ctx, "Mandible", Enum.PartType.Wedge, Vector3.new(u * 0.09, u * 0.26, u * 0.12), BONE)
		att(ctx, mand, CFrame.new(side * u * 0.14, -u * 0.06, -u * 0.72),
			CFrame.Angles(math.rad(180), 0, math.rad(side * 18)) * CFrame.new(0, u * 0.13, 0),
			"swing", 0.16, 2.6, side > 0 and 0 or math.pi)
	end)

	local rows = pal.isBrute and { -u * 0.3, -u * 0.1, u * 0.1, u * 0.3 } or { -u * 0.24, -u * 0.02, u * 0.2 }
	local n = 0
	for _, dz in ipairs(rows) do
		pairUp(function(side)
			n += 1
			local joint = CFrame.new(side * u * 0.2, u * 0.06, dz)
			local ph = n * 0.8
			local femur = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.34, u * 0.07, u * 0.07), pal.dark)
			att(ctx, femur, joint, CFrame.Angles(0, 0, math.rad(side * -30)) * CFrame.new(side * u * 0.17, 0, 0), "swing", 0.26, 3.6, ph)
			local shin = mk(ctx, "Shin", Enum.PartType.Block, Vector3.new(u * 0.06, u * 0.42, u * 0.06), pal.dark)
			att(ctx, shin, joint, CFrame.new(side * u * 0.3, -u * 0.13, 0) * CFrame.Angles(0, 0, math.rad(side * 10)), "swing", 0.26, 3.6, ph)
			if det >= 1 then
				local knee = mk(ctx, "Knee", Enum.PartType.Ball, Vector3.new(u * 0.11, u * 0.11, u * 0.11), pal.trim)
				att(ctx, knee, joint, CFrame.new(side * u * 0.31, u * 0.04, 0), "swing", 0.26, 3.6, ph)
				local foot = mk(ctx, "Foot", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.11, u * 0.13), pal.ink)
				att(ctx, foot, joint, CFrame.new(side * u * 0.34, -u * 0.33, -u * 0.04) * CFrame.Angles(math.rad(90), 0, 0), "swing", 0.26, 3.6, ph)
			end
		end)
	end

	if pal.isBrute then
		pairUp(function(side)
			local palp = mk(ctx, "Pedipalp", Enum.PartType.Block, Vector3.new(u * 0.09, u * 0.09, u * 0.3), pal.skin)
			att(ctx, palp, CFrame.new(side * u * 0.26, -u * 0.04, -u * 0.48), CFrame.new(0, 0, -u * 0.15), "trail", 0.2, 2.2, side > 0 and 0 or 1.6)
			local pincer = mk(ctx, "Pincer", Enum.PartType.Wedge, Vector3.new(u * 0.1, u * 0.24, u * 0.2), pal.dark, Enum.Material.Slate)
			att(ctx, pincer, CFrame.new(side * u * 0.26, -u * 0.04, -u * 0.48), CFrame.new(0, u * 0.06, -u * 0.36) * CFrame.Angles(math.rad(90), 0, 0), "trail", 0.2, 2.2, side > 0 and 0 or 1.6)
		end)
	end

	local tailJoint = CFrame.new(0, u * 0.22, u * 0.3)
	for i = 1, 3 do
		local seg = mk(ctx, "Tail", Enum.PartType.Block, Vector3.new(u * 0.14 - i * u * 0.015, u * 0.17, u * 0.14 - i * u * 0.015), pal.skin)
		att(ctx, seg, tailJoint, CFrame.Angles(math.rad(-38 - i * 9), 0, 0) * CFrame.new(0, u * (0.1 + i * 0.16), 0), "trail", 0.28, 1.8, 0)
	end
	local bulb = mk(ctx, "Stinger", Enum.PartType.Ball, Vector3.new(u * 0.18, u * 0.18, u * 0.18), pal.dark)
	att(ctx, bulb, tailJoint, CFrame.Angles(math.rad(-65), 0, 0) * CFrame.new(0, u * 0.66, 0), "trail", 0.28, 1.8, 0)
	local barb = mk(ctx, "StingerTip", Enum.PartType.Wedge, Vector3.new(u * 0.1, u * 0.22, u * 0.1), pal.glow, Enum.Material.Neon)
	att(ctx, barb, tailJoint, CFrame.Angles(math.rad(-65), 0, 0) * CFrame.new(0, u * 0.78, 0) * CFrame.Angles(math.rad(-55), 0, 0), "trail", 0.28, 1.8, 0)

	eliteCrown(ctx)
	return body
end

-- AQUATIC (Ocean, MirrorUniverse) -- a big-headed grinning fish: a mouth the full width of the
-- head, a pale belly, coat-coloured back stripes, gill slits, paired fins and a forked tail.
function RIGS.AQUATIC(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.47, -u * 0.4)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.62, u * 0.6, u * 0.68), pal.skin)

	local belly = mk(ctx, "Belly", Enum.PartType.Ball, Vector3.new(u * 0.52, u * 0.36, u * 0.62), pal.belly)
	att(ctx, belly, CFrame.new(0, -u * 0.16, u * 0.02), IDENTITY, "float", u * 0.02, 2.4, 0.5)

	local head = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.76, u * 0.68, u * 0.52), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.1, -u * 0.4), IDENTITY, "float", u * 0.02, 2.4, 0.5)

	-- a wide mouth is the cheapest expression there is
	grinArc(ctx, u * 0.6, -u * 0.1, -u * 0.61, u * 0.08, ctx.face.curve, 2.4, 0.5)
	local jaw = mk(ctx, "Jaw", Enum.PartType.Block, Vector3.new(u * 0.58, u * 0.16, u * 0.3), pal.dark)
	att(ctx, jaw, CFrame.new(0, -u * 0.2, -u * 0.5), IDENTITY, "float", u * 0.02, 2.4, 0.5)
	fangRow(ctx, det >= 1 and math.max(4, ctx.face.teeth) or 4, u * 0.46, -u * 0.09, -u * 0.66, u * 0.14, "float", u * 0.02, 2.4, 0.5)
	if det >= 1 then
		if ctx.face.tongue then tongue(ctx, -u * 0.14, -u * 0.62, u * 0.12, 2.4, 0.7) end
		cheeks(ctx, u * 0.3, u * 0.02, -u * 0.58, u * 0.2, lighten(pal.coat, 0.2), 2.4, 0.5)
	end

	eyePair(ctx, u * 0.23, u * 0.26, -u * 0.6, u * 0.27, pal.iris, 2.4, 0.5)

	if det >= 1 then
		pairUp(function(side)
			for i = 1, 3 do
				local gill = mk(ctx, "Gill", Enum.PartType.Block, Vector3.new(u * 0.035, u * 0.17, u * 0.05), pal.ink)
				att(ctx, gill, CFrame.new(side * u * 0.29, u * 0.02, -u * 0.2 + i * u * 0.08), CFrame.Angles(math.rad(14), 0, 0), "float", u * 0.02, 2.4, 0.5)
			end
		end)
		for i = 1, 3 do
			local stripe = mk(ctx, "Stripe", Enum.PartType.Block, Vector3.new(u * 0.52, u * 0.07, u * 0.08), pal.coat)
			att(ctx, stripe, CFrame.new(0, u * 0.27, -u * 0.1 + i * u * 0.14), CFrame.Angles(0, 0, math.rad(4)), "float", u * 0.02, 2.4, 0.5)
		end
	end

	pairUp(function(side)
		local fin = mk(ctx, "SideFin", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.22, u * 0.28), pal.trim)
		att(ctx, fin, CFrame.new(side * u * 0.26, -u * 0.04, -u * 0.04),
			CFrame.Angles(0, 0, math.rad(side * 70)) * CFrame.new(0, u * 0.14, 0),
			"flap", 0.4, 3.4, side > 0 and 0 or math.pi)
		if det >= 1 then
			local pelvic = mk(ctx, "PelvicFin", Enum.PartType.Wedge, Vector3.new(u * 0.04, u * 0.14, u * 0.18), pal.trim)
			att(ctx, pelvic, CFrame.new(side * u * 0.16, -u * 0.24, u * 0.18),
				CFrame.Angles(0, 0, math.rad(side * 46)) * CFrame.new(0, u * 0.09, 0),
				"flap", 0.3, 3.4, side > 0 and 0.7 or math.pi + 0.7)
		end
	end)

	local dorsal = mk(ctx, "Dorsal", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.32, u * 0.38), pal.trim)
	att(ctx, dorsal, CFrame.new(0, u * 0.3, u * 0.04), CFrame.Angles(0, math.rad(180), 0), "float", u * 0.02, 2.4, 0.5)
	if det >= 1 then
		local dorsal2 = mk(ctx, "DorsalSmall", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.16, u * 0.2), pal.trim)
		att(ctx, dorsal2, CFrame.new(0, u * 0.26, u * 0.34), CFrame.Angles(0, math.rad(180), 0), "float", u * 0.02, 2.4, 0.5)
	end

	local stalk = mk(ctx, "Stalk", Enum.PartType.Block, Vector3.new(u * 0.18, u * 0.2, u * 0.4), pal.skin)
	att(ctx, stalk, CFrame.new(0, 0, u * 0.26), CFrame.new(0, 0, u * 0.2), "trail", 0.3, 3.0, 0)

	for _, dir in ipairs({ 1, -1 }) do
		local tailFin = mk(ctx, "TailFin", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.32, u * 0.28), pal.trim)
		att(ctx, tailFin, CFrame.new(0, 0, u * 0.26),
			CFrame.new(0, dir * u * 0.15, u * 0.5) * CFrame.Angles(0, 0, dir > 0 and 0 or math.rad(180)),
			"trail", 0.3, 3.0, 0)
	end

	if pal.isBrute then
		bruteSpikes(ctx, u * 0.18, u * 0.3, -u * 0.02, u * 0.26)
	end
	eliteCrown(ctx)
	return body
end

-- MAGMA (Volcano, CelestialThrone) -- a hunched rock body split by glowing cracks, a gem set in the
-- crust, heavy arms ending in fists, a jaw full of fangs and vents smoking off its back.
function RIGS.MAGMA(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.86, -u * 0.06)
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.72, u * 0.58, u * 0.52), pal.dark, Enum.Material.Slate)

	local chest = mk(ctx, "Chest", Enum.PartType.Block, Vector3.new(u * 0.5, u * 0.34, u * 0.12), pal.skin, Enum.Material.Slate)
	att(ctx, chest, CFrame.new(0, u * 0.06, -u * 0.27), IDENTITY, nil)
	-- one cut stone in the crust. A rock creature is otherwise the hardest of the seven to give any
	-- colour to at all.
	local gem = mk(ctx, "Gem", Enum.PartType.Ball, Vector3.new(u * 0.22, u * 0.26, u * 0.13), pal.coat, Enum.Material.Neon)
	att(ctx, gem, CFrame.new(0, u * 0.08, -u * 0.32), IDENTITY, "float", u * 0.012, 1.7, 0.3)
	local bezel = mk(ctx, "GemBezel", Enum.PartType.Ball, Vector3.new(u * 0.28, u * 0.32, u * 0.1), pal.trim, Enum.Material.Metal)
	att(ctx, bezel, CFrame.new(0, u * 0.08, -u * 0.31), IDENTITY, "float", u * 0.012, 1.7, 0.3)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.64, u * 0.56, u * 0.5), pal.dark, Enum.Material.Slate)
	att(ctx, head, CFrame.new(0, u * 0.56, -u * 0.06), IDENTITY, "float", u * 0.02, 1.7, 0.3)

	-- on a creature made of rock the mouth has to be a crack that glows, not a hole
	-- the lit crack behind the arc, so a rock creature's grin glows from inside it
	local maw = mk(ctx, "Mouth", Enum.PartType.Block, Vector3.new(u * 0.44, u * 0.12, u * 0.1), pal.glow, Enum.Material.Neon)
	att(ctx, maw, CFrame.new(0, u * 0.4, -u * 0.27), IDENTITY, "float", u * 0.02, 1.7, 0.3)
	grinArc(ctx, u * 0.46, u * 0.4, -u * 0.32, u * 0.06, ctx.face.curve, 1.7, 0.3)
	local jaw = mk(ctx, "Jaw", Enum.PartType.Block, Vector3.new(u * 0.5, u * 0.16, u * 0.34), pal.ink, Enum.Material.Slate)
	att(ctx, jaw, CFrame.new(0, u * 0.32, -u * 0.16), IDENTITY, "float", u * 0.02, 1.7, 0.3)
	fangRow(ctx, det >= 1 and 5 or 3, u * 0.36, u * 0.4, -u * 0.34, u * 0.13, "float", u * 0.02, 1.7, 0.3)

	eyePair(ctx, u * 0.18, u * 0.64, -u * 0.28, u * 0.24, pal.iris, 1.7, 0.3)

	pairUp(function(side)
		local shoulder = mk(ctx, "Shoulder", Enum.PartType.Ball, Vector3.new(u * 0.3, u * 0.28, u * 0.3), pal.dark, Enum.Material.Slate)
		att(ctx, shoulder, CFrame.new(side * u * 0.44, u * 0.32, 0), IDENTITY, "float", u * 0.014, 1.7, 0.3)

		limbAt(ctx, CFrame.new(side * u * 0.44, u * 0.18, 0), {
			name = "Arm", w = u * 0.21, thigh = u * 0.24, shin = u * 0.22,
			amp = 0.45, speed = 2.4, phase = side > 0 and 0 or math.pi,
			color = pal.skin, shinColor = darken(pal.skin, 0.2), jointColor = pal.coat,
			material = Enum.Material.Slate, footWidth = u * 0.27,
		})
		limbAt(ctx, CFrame.new(side * u * 0.22, -u * 0.24, 0), {
			w = u * 0.22, thigh = u * 0.14, shin = u * 0.13,
			amp = 0.22, speed = 2.4, phase = side > 0 and math.pi or 0,
			color = pal.skin, shinColor = darken(pal.skin, 0.25), jointColor = pal.coat,
			material = Enum.Material.Slate, footWidth = u * 0.26,
		})
	end)

	-- lava under a crust only works if the crust is what you see first, so these are thin and few
	for i, dy in ipairs({ u * 0.12, -u * 0.08 }) do
		local crack = mk(ctx, "Crack", Enum.PartType.Block, Vector3.new(u * 0.48, u * 0.06, u * 0.03), pal.glow, Enum.Material.Neon)
		att(ctx, crack, CFrame.new(0, dy, -u * 0.28), CFrame.Angles(0, 0, math.rad(i == 1 and 9 or -12)), nil)
	end
	if det >= 1 then
		local seam = mk(ctx, "Crack", Enum.PartType.Block, Vector3.new(u * 0.04, u * 0.4, u * 0.03), pal.glow, Enum.Material.Neon)
		att(ctx, seam, CFrame.new(u * 0.08, u * 0.02, -u * 0.28), CFrame.Angles(0, 0, math.rad(-8)), nil)

		for _, dx in ipairs({ -u * 0.2, u * 0.04, u * 0.24 }) do
			local vent = mk(ctx, "Vent", Enum.PartType.Cylinder, Vector3.new(u * 0.14, u * 0.14, u * 0.14), pal.ink, Enum.Material.Slate)
			att(ctx, vent, CFrame.new(dx, u * 0.3, u * 0.24), CFrame.Angles(0, 0, math.rad(90)), "float", u * 0.012, 1.7, 0.3)
			local mouthGlow = mk(ctx, "VentGlow", Enum.PartType.Ball, Vector3.new(u * 0.11, u * 0.11, u * 0.11), pal.glow, Enum.Material.Neon)
			att(ctx, mouthGlow, CFrame.new(dx, u * 0.38, u * 0.24), IDENTITY, "float", u * 0.02, 2.3, dx)
		end
	end

	if pal.isBrute then
		bruteSpikes(ctx, u * 0.4, u * 0.4, 0, u * 0.3)
	end
	eliteCrown(ctx)
	return body
end

-- DRIFTER (Moon, Nebula, DreamDimension) -- no legs at all, so everything has to happen in the
-- silhouette: a translucent shell over a lit core, two bead rings turning opposite ways in two
-- different hues, shards outside them, and a face big enough to carry the whole read.
function RIGS.DRIFTER(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.34, 0)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.58, u * 0.58, u * 0.58), pal.skin, Enum.Material.SmoothPlastic, 0.32)

	local core = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.32, u * 0.32, u * 0.32), pal.glow, Enum.Material.Neon)
	att(ctx, core, IDENTITY, IDENTITY, "float", u * 0.03, 1.4, 0)

	eyePair(ctx, u * 0.18, u * 0.1, -u * 0.32, u * 0.27, pal.iris, 1.4, 0)
	if det >= 1 then
		cheeks(ctx, u * 0.28, -u * 0.06, -u * 0.28, u * 0.17, lighten(pal.coat, 0.16), 1.4, 0)
		-- a floating orb with eyes and nothing else reads as a balloon
		grinArc(ctx, u * 0.3, -u * 0.2, -u * 0.31, u * 0.06, ctx.face.curve, 1.4, 0)
		if ctx.face.tongue then tongue(ctx, -u * 0.24, -u * 0.32, u * 0.09, 1.4, 0) end
	end

	beadRing(ctx, det >= 1 and 10 or 6, u * 0.42, u * 0.06, u * 0.09, pal.trim, Enum.Material.Metal, 0.8)
	if det >= 2 then
		beadRing(ctx, 8, u * 0.3, -u * 0.24, u * 0.08, pal.coat, Enum.Material.Neon, -1.1)
	end

	local shardCount = pal.isBrute and 6 or 4
	for i = 1, shardCount do
		local shard = mk(ctx, "Shard", Enum.PartType.Wedge, Vector3.new(u * 0.11, u * 0.28, u * 0.11), pal.trim, Enum.Material.Metal)
		att(ctx, shard, CFrame.new(0, (i % 2 == 0) and u * 0.2 or -u * 0.16, 0),
			CFrame.new(u * 0.52, 0, 0) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 26 or -26)),
			"orbit", 0, (i % 2 == 0) and -0.9 or 0.7, (i - 1) * (math.pi * 2 / shardCount))
	end

	eliteCrown(ctx)
	return body
end

-- MECH (Mars, QuantumRealm, Singularity) -- a plated helmet with a painted crest and real eyes
-- behind the visor (a lit bar on its own is a machine; eyes inside it are a character), pistoned
-- limbs with hands and feet, an antenna, and a backpack venting light.
function RIGS.MECH(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.8, -u * 0.2)
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.58, u * 0.54, u * 0.4), pal.skin, Enum.Material.Metal)

	local plate = mk(ctx, "ChestPlate", Enum.PartType.Block, Vector3.new(u * 0.44, u * 0.3, u * 0.08), pal.trim, Enum.Material.Metal)
	att(ctx, plate, CFrame.new(0, u * 0.06, -u * 0.22), IDENTITY, nil)
	local coreLamp = mk(ctx, "CoreLamp", Enum.PartType.Ball, Vector3.new(u * 0.14, u * 0.14, u * 0.14), pal.glow, Enum.Material.Neon)
	att(ctx, coreLamp, CFrame.new(0, u * 0.08, -u * 0.26), IDENTITY, "float", u * 0.01, 2.6, 0.9)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.6, u * 0.5, u * 0.44), pal.dark, Enum.Material.Metal)
	att(ctx, head, CFrame.new(0, u * 0.54, -u * 0.02), IDENTITY, "float", u * 0.015, 2.0, 0.2)

	local crest = mk(ctx, "Crest", Enum.PartType.Block, Vector3.new(u * 0.11, u * 0.52, u * 0.45), pal.coat, Enum.Material.Metal)
	att(ctx, crest, CFrame.new(0, u * 0.54, -u * 0.02), IDENTITY, "float", u * 0.015, 2.0, 0.2)

	local visor = mk(ctx, "Visor", Enum.PartType.Block, Vector3.new(u * 0.5, u * 0.22, u * 0.05), INK, Enum.Material.Metal)
	att(ctx, visor, CFrame.new(0, u * 0.58, -u * 0.24), IDENTITY, "float", u * 0.015, 2.0, 0.2)
	eyePair(ctx, u * 0.14, u * 0.58, -u * 0.26, u * 0.2, pal.iris, 2.0, 0.2)
	if det >= 1 then
		for i = -1, 1 do
			local slat = mk(ctx, "Grille", Enum.PartType.Block, Vector3.new(u * 0.3, u * 0.035, u * 0.04), pal.metal, Enum.Material.Metal)
			att(ctx, slat, CFrame.new(0, u * 0.42 + i * u * 0.055, -u * 0.23), IDENTITY, "float", u * 0.015, 2.0, 0.2)
		end
	end

	local rod = mk(ctx, "Antenna", Enum.PartType.Cylinder, Vector3.new(u * 0.26, u * 0.05, u * 0.05), pal.dark, Enum.Material.Metal)
	att(ctx, rod, CFrame.new(0, u * 0.78, 0), CFrame.new(0, u * 0.13, 0) * CFrame.Angles(0, 0, math.rad(90)), "trail", 0.22, 2.2, 0)
	local tip = mk(ctx, "AntennaTip", Enum.PartType.Ball, Vector3.new(u * 0.1, u * 0.1, u * 0.1), pal.glow, Enum.Material.Neon)
	att(ctx, tip, CFrame.new(0, u * 0.78, 0), CFrame.new(0, u * 0.3, 0), "trail", 0.22, 2.2, 0)

	if det >= 1 then
		local pack = mk(ctx, "Backpack", Enum.PartType.Block, Vector3.new(u * 0.4, u * 0.34, u * 0.16), pal.dark, Enum.Material.Metal)
		att(ctx, pack, CFrame.new(0, u * 0.14, u * 0.26), IDENTITY, nil)
		for _, dx in ipairs({ -u * 0.12, u * 0.12 }) do
			local exhaust = mk(ctx, "Exhaust", Enum.PartType.Cylinder, Vector3.new(u * 0.16, u * 0.11, u * 0.11), pal.ink, Enum.Material.Metal)
			att(ctx, exhaust, CFrame.new(dx, u * 0.34, u * 0.26), CFrame.Angles(0, 0, math.rad(90)), "float", u * 0.012, 2.0, 0.2)
			local flame = mk(ctx, "ExhaustGlow", Enum.PartType.Ball, Vector3.new(u * 0.09, u * 0.09, u * 0.09), pal.glow, Enum.Material.Neon)
			att(ctx, flame, CFrame.new(dx, u * 0.42, u * 0.26), IDENTITY, "float", u * 0.024, 3.1, dx)
		end
	end

	pairUp(function(side)
		local pad = mk(ctx, "Shoulder", Enum.PartType.Block, Vector3.new(u * 0.17, u * 0.15, u * 0.28), pal.dark, Enum.Material.Metal)
		att(ctx, pad, CFrame.new(side * u * 0.36, u * 0.24, 0), IDENTITY, nil)

		limbAt(ctx, CFrame.new(side * u * 0.36, u * 0.14, 0), {
			name = "Arm", w = u * 0.14, thigh = u * 0.2, shin = u * 0.19,
			amp = 0.4, speed = 2.8, phase = side > 0 and 0 or math.pi,
			color = pal.trim, shinColor = pal.metal, jointColor = pal.coat,
			material = Enum.Material.Metal, footWidth = u * 0.19,
		})
		local legJoint = CFrame.new(side * u * 0.18, -u * 0.22, 0)
		limbAt(ctx, legJoint, {
			w = u * 0.16, thigh = u * 0.15, shin = u * 0.15,
			amp = 0.35, speed = 2.8, phase = side > 0 and math.pi or 0,
			color = pal.dark, shinColor = pal.metal, jointColor = pal.coat,
			material = Enum.Material.Metal, footWidth = u * 0.21,
		})
		if det >= 1 then
			local piston = mk(ctx, "Piston", Enum.PartType.Cylinder, Vector3.new(u * 0.2, u * 0.07, u * 0.07), pal.metal, Enum.Material.Metal)
			att(ctx, piston, legJoint, CFrame.new(0, -u * 0.12, u * 0.11) * CFrame.Angles(0, 0, math.rad(90)), "swing", 0.35, 2.8, side > 0 and math.pi or 0)
		end
	end)

	if pal.isBrute then
		bruteSpikes(ctx, u * 0.34, u * 0.36, 0, u * 0.28)
	end
	eliteCrown(ctx)
	return body
end

-- WRAITH (Galaxy, BlackHole, Multiverse, Wormhole, TimeRift, VoidExpanse, AbsolutePlane) -- the one
-- rig with no body to speak of. A hood over a black void with a face floating in it, a lit brim, a
-- core in the chest, shoulder shrouds for width, claws, and tendrils where the legs would be.
function RIGS.WRAITH(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.68, -u * 0.06)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.6, u * 0.6, u * 0.6), pal.skin, Enum.Material.SmoothPlastic, 0.4)

	local cowl = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.72, u * 0.7, u * 0.6), pal.dark, Enum.Material.SmoothPlastic, 0.2)
	att(ctx, cowl, CFrame.new(0, u * 0.3, -u * 0.06), IDENTITY, "float", u * 0.035, 1.3, 0)

	-- the void inside the hood. The face reads because it sits on black, not on the hood colour.
	local hollow = mk(ctx, "Hollow", Enum.PartType.Ball, Vector3.new(u * 0.54, u * 0.52, u * 0.46), INK)
	att(ctx, hollow, CFrame.new(0, u * 0.3, -u * 0.24), IDENTITY, "float", u * 0.035, 1.3, 0)

	if det >= 1 then
		-- a brim of shards around the hood opening, in the two bright hues, so the hood has an edge
		-- instead of fading out
		for i = 1, 7 do
			local a = math.pi * (0.15 + (i - 1) * 0.12)
			local shard = mk(ctx, "HoodShard", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.18, u * 0.1), i % 2 == 0 and pal.coat or pal.trim, Enum.Material.SmoothPlastic, 0.05)
			att(ctx, shard, CFrame.new(math.cos(a) * u * 0.36, u * 0.3 + math.sin(a) * u * 0.36, -u * 0.18),
				CFrame.Angles(0, 0, math.rad(90) - a), "float", u * 0.035, 1.3, 0)
		end
	end

	eyePair(ctx, u * 0.16, u * 0.34, -u * 0.4, u * 0.24, pal.iris, 1.3, 0)
	-- a grin floating in the dark under them. Nothing else is in the hood, so it has to carry.
	grinArc(ctx, u * 0.34, u * 0.14, -u * 0.42, u * 0.06, ctx.face.curve, 1.3, 0)
	if ctx.face.teeth > 0 then
		fangRow(ctx, det >= 1 and 6 or 3, u * 0.3, u * 0.14, -u * 0.43, u * 0.12, "float", u * 0.035, 1.3, 0)
	end

	local core = mk(ctx, "Core", Enum.PartType.Ball, Vector3.new(u * 0.24, u * 0.24, u * 0.24), pal.glow, Enum.Material.Neon)
	att(ctx, core, IDENTITY, IDENTITY, "float", u * 0.04, 1.1, 1.2)
	if det >= 2 then
		beadRing(ctx, 8, u * 0.34, 0, u * 0.06, pal.coat, Enum.Material.Neon, 0.6)
	end

	pairUp(function(side)
		local shroud = mk(ctx, "Shroud", Enum.PartType.Ball, Vector3.new(u * 0.28, u * 0.24, u * 0.26), pal.dark, Enum.Material.SmoothPlastic, 0.25)
		att(ctx, shroud, CFrame.new(side * u * 0.3, u * 0.16, 0), IDENTITY, "float", u * 0.03, 1.3, 0.5)
		if det >= 1 then
			local joint = CFrame.new(side * u * 0.34, u * 0.02, -u * 0.04)
			local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.08, u * 0.26, u * 0.08), pal.skin, Enum.Material.SmoothPlastic, 0.25)
			att(ctx, arm, joint, CFrame.new(0, -u * 0.13, 0), "swing", 0.3, 1.9, side > 0 and 0 or math.pi)
			for i = -1, 1 do
				local claw = mk(ctx, "Claw", Enum.PartType.Wedge, Vector3.new(u * 0.04, u * 0.14, u * 0.05), BONE)
				att(ctx, claw, joint, CFrame.new(i * u * 0.05, -u * 0.32, -u * 0.03) * CFrame.Angles(math.rad(160), 0, 0), "swing", 0.3, 1.9, side > 0 and 0 or math.pi)
			end
		end
	end)

	local tendrils = pal.isBrute and 7 or 5
	for i = 1, tendrils do
		local a = (i - 1) * (math.pi * 2 / tendrils)
		local joint = CFrame.new(math.cos(a) * u * 0.18, -u * 0.1, math.sin(a) * u * 0.18)
		local tendril = mk(ctx, "Tendril", Enum.PartType.Block, Vector3.new(u * 0.09, u * 0.4, u * 0.09), pal.skin, Enum.Material.SmoothPlastic, 0.25)
		att(ctx, tendril, joint, CFrame.new(0, -u * 0.2, 0), "trail", 0.5, 2.0 + i * 0.13, i * 0.9)
		if det >= 2 then
			local wisp = mk(ctx, "TendrilTip", Enum.PartType.Ball, Vector3.new(u * 0.1, u * 0.1, u * 0.1), pal.coat, Enum.Material.Neon, 0.3)
			att(ctx, wisp, joint, CFrame.new(0, -u * 0.42, 0), "trail", 0.5, 2.0 + i * 0.13, i * 0.9)
		end
	end

	eliteCrown(ctx)
	return body
end

-- SLIME (Multiverse, MirrorUniverse) -- a translucent wobbling blob with something it swallowed
-- still visible inside it. The inner object is the whole joke and the whole silhouette: without
-- it a slime is a coloured bubble.
function RIGS.SLIME(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.5, 0)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.86, u * 0.72, u * 0.8), pal.skin, Enum.Material.SmoothPlastic, 0.28)

	-- the puddle it is sitting in, and the dome on top: three balls at different squashes read as
	-- a body under gravity, one ball reads as a marble
	local base = mk(ctx, "Puddle", Enum.PartType.Ball, Vector3.new(u * 0.96, u * 0.3, u * 0.86), pal.skin, Enum.Material.SmoothPlastic, 0.3)
	att(ctx, base, CFrame.new(0, -u * 0.3, 0), IDENTITY, "float", u * 0.02, 1.5, 0.3)
	local dome = mk(ctx, "Dome", Enum.PartType.Ball, Vector3.new(u * 0.5, u * 0.42, u * 0.5), lighten(pal.skin, 0.25), Enum.Material.SmoothPlastic, 0.22)
	att(ctx, dome, CFrame.new(0, u * 0.32, u * 0.06), IDENTITY, "float", u * 0.036, 1.5, 0.9)

	if det >= 1 then
		-- the swallowed thing, tumbling slowly
		local prize = mk(ctx, "Swallowed", Enum.PartType.Block, Vector3.new(u * 0.24, u * 0.24, u * 0.24), pal.coat, Enum.Material.Metal)
		att(ctx, prize, CFrame.new(0, -u * 0.06, u * 0.04), CFrame.Angles(math.rad(24), 0, math.rad(18)), "orbit", 0, 0.5, 0)
		-- a lit streak down the left of the body: the only thing that makes a translucent part
		-- read as wet rather than as fogged
		local streak = mk(ctx, "Sheen", Enum.PartType.Ball, Vector3.new(u * 0.12, u * 0.34, u * 0.1), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 0.45)
		att(ctx, streak, CFrame.new(-u * 0.28, u * 0.12, -u * 0.3), CFrame.Angles(0, 0, math.rad(14)), "float", u * 0.03, 1.5, 0.3)
		-- drips running off the rim
		for i = 1, 5 do
			local a = (i - 1) * (math.pi * 2 / 5) + 0.5
			local drip = mk(ctx, "Drip", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.22, u * 0.13), pal.skin, Enum.Material.SmoothPlastic, 0.26)
			att(ctx, drip, CFrame.new(math.cos(a) * u * 0.4, -u * 0.22, math.sin(a) * u * 0.38), CFrame.new(0, -u * 0.1, 0), "float", u * 0.05, 2.1 + i * 0.2, i)
		end
	end

	eyePair(ctx, u * 0.21, u * 0.22, -u * 0.42, u * 0.3, pal.iris, 1.5, 0.3)
	if det >= 1 then
		cheeks(ctx, u * 0.36, u * 0.02, -u * 0.36, u * 0.2, lighten(pal.coat, 0.18), 1.5, 0.3)
	end
	grinArc(ctx, u * 0.4, -u * 0.06, -u * 0.42, u * 0.07, ctx.face.curve, 1.5, 0.3)
	if ctx.face.teeth > 0 then
		fangRow(ctx, det >= 1 and 4 or 2, u * 0.28, -u * 0.04, -u * 0.44, u * 0.11, "float", u * 0.03, 1.5, 0.3)
	end
	if det >= 1 and ctx.face.tongue then tongue(ctx, -u * 0.1, -u * 0.44, u * 0.1, 1.5, 0.3) end

	-- nub arms, because a blob with no limbs cannot gesture at anything
	pairUp(function(side)
		local nub = mk(ctx, "Nub", Enum.PartType.Ball, Vector3.new(u * 0.2, u * 0.2, u * 0.2), pal.skin, Enum.Material.SmoothPlastic, 0.24)
		att(ctx, nub, CFrame.new(side * u * 0.42, -u * 0.04, 0), CFrame.new(0, 0, 0), "swing", 0.35, 2.6, side > 0 and 0 or math.pi)
	end)

	if pal.isBrute then bruteSpikes(ctx, u * 0.3, u * 0.34, u * 0.1, u * 0.3) end
	eliteCrown(ctx)
	return body
end

-- AVIAN (Nebula, CelestialThrone) -- a round fluffed bird. Two things carry it: a bright beak in a
-- colour nothing else on the rig uses, and wings that actually beat -- a folded wing is a flat
-- wedge glued to a ball.
function RIGS.AVIAN(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.9, -u * 0.16)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.6, u * 0.64, u * 0.56), pal.skin)

	local breast = mk(ctx, "Breast", Enum.PartType.Ball, Vector3.new(u * 0.46, u * 0.46, u * 0.3), pal.belly)
	att(ctx, breast, CFrame.new(0, -u * 0.04, -u * 0.3), IDENTITY, "float", u * 0.016, 2.0, 0.3)

	local head = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.66, u * 0.62, u * 0.6), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.55, -u * 0.16), IDENTITY, "float", u * 0.024, 2.0, 0.3)

	-- upper and lower mandible, hinged apart. A Wedge apex points +Y, so the lower one is rolled.
	local beakColor = pal.trim
	local upper = mk(ctx, "Beak", Enum.PartType.Wedge, Vector3.new(u * 0.2, u * 0.22, u * 0.3), beakColor)
	att(ctx, upper, CFrame.new(0, u * 0.5, -u * 0.5), CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, u * 0.1, 0), "float", u * 0.024, 2.0, 0.3)
	local lower = mk(ctx, "BeakLower", Enum.PartType.Wedge, Vector3.new(u * 0.17, u * 0.14, u * 0.24), darken(beakColor, 0.25))
	att(ctx, lower, CFrame.new(0, u * 0.42, -u * 0.48), CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, -u * 0.06, 0), "swing", 0.14, 1.8, 0.8)

	eyePair(ctx, u * 0.2, u * 0.66, -u * 0.42, u * 0.26, pal.iris, 2.0, 0.3)
	if det >= 1 then
		cheeks(ctx, u * 0.3, u * 0.5, -u * 0.4, u * 0.17, lighten(pal.coat, 0.18), 2.0, 0.3)
		-- crest: three feathers standing up, the tallest in the middle
		for i = -1, 1 do
			local h = u * (0.3 - math.abs(i) * 0.08)
			local plume = mk(ctx, "Crest", Enum.PartType.Wedge, Vector3.new(u * 0.06, h, u * 0.16), pal.coat)
			att(ctx, plume, CFrame.new(i * u * 0.13, u * 0.86, -u * 0.14), CFrame.Angles(math.rad(-16), 0, math.rad(i * 12)) * CFrame.new(0, h * 0.5, 0), "flap", 0.1, 2.2, i + 1)
		end
	end

	pairUp(function(side)
		local joint = CFrame.new(side * u * 0.28, u * 0.1, 0)
		local wing = mk(ctx, "Wing", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.44, u * 0.52), pal.coat)
		att(ctx, wing, joint, CFrame.Angles(0, 0, math.rad(side * 96)) * CFrame.new(0, u * 0.24, 0), "flap", 0.55, 3.1, side > 0 and 0 or math.pi)
		if det >= 1 then
			local tipFeather = mk(ctx, "WingTip", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.22, u * 0.3), pal.trim)
			att(ctx, tipFeather, joint, CFrame.Angles(0, 0, math.rad(side * 96)) * CFrame.new(0, u * 0.52, u * 0.06), "flap", 0.55, 3.1, side > 0 and 0 or math.pi)
		end

		-- thin legs and a three-toe foot: the one place a bird gets to look spindly
		local legJoint = CFrame.new(side * u * 0.15, -u * 0.3, 0)
		local shank = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.07, u * 0.24, u * 0.07), pal.trim)
		att(ctx, shank, legJoint, CFrame.new(0, -u * 0.12, 0), "swing", 0.42, 3.0, side > 0 and 0 or math.pi)
		for t = -1, 1 do
			local toe = mk(ctx, "Toe", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.05, u * 0.16), pal.trim)
			att(ctx, toe, legJoint, CFrame.new(t * u * 0.06, -u * 0.25, -u * 0.06) * CFrame.Angles(0, math.rad(t * 22), 0), "swing", 0.42, 3.0, side > 0 and 0 or math.pi)
		end
	end)

	-- tail fan
	for i = -2, 2 do
		local feather = mk(ctx, "TailFeather", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.34, u * 0.16), i % 2 == 0 and pal.coat or pal.trim)
		att(ctx, feather, CFrame.new(0, u * 0.06, u * 0.3), CFrame.Angles(math.rad(74), 0, math.rad(i * 15)) * CFrame.new(0, u * 0.2, 0), "trail", 0.2, 2.4, 0)
	end

	if pal.isBrute then bruteSpikes(ctx, u * 0.2, u * 0.34, u * 0.06, u * 0.28) end
	eliteCrown(ctx)
	return body
end

-- FUNGAL (DreamDimension) -- a walking mushroom. The cap is nearly the whole silhouette and the
-- body underneath is deliberately small, which is the same proportion trick the dog uses.
function RIGS.FUNGAL(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.72, 0)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.44, u * 0.5, u * 0.42), pal.belly)

	local cap = mk(ctx, "Cap", Enum.PartType.Ball, Vector3.new(u * 0.98, u * 0.6, u * 0.94), pal.coat)
	att(ctx, cap, CFrame.new(0, u * 0.42, 0), IDENTITY, "float", u * 0.024, 1.6, 0.4)
	local capLip = mk(ctx, "CapLip", Enum.PartType.Ball, Vector3.new(u * 1.02, u * 0.16, u * 0.98), darken(pal.coat, 0.2))
	att(ctx, capLip, CFrame.new(0, u * 0.26, 0), IDENTITY, "float", u * 0.024, 1.6, 0.4)

	if det >= 1 then
		-- pale blotches on the cap: the recognition cue for the whole thing
		for i = 1, 6 do
			local a = i * 2.399963
			local r = u * (0.14 + (i % 3) * 0.14)
			local d = u * (0.14 + (i % 2) * 0.06)
			local blot = mk(ctx, "CapSpot", Enum.PartType.Ball, Vector3.new(d, d * 0.5, d), lighten(pal.belly, 0.3))
			att(ctx, blot, CFrame.new(math.cos(a) * r, u * 0.6, math.sin(a) * r), IDENTITY, "float", u * 0.024, 1.6, 0.4)
		end
		-- gills under the cap, radiating
		for i = 1, 10 do
			local a = (i - 1) * (math.pi * 2 / 10)
			local gill = mk(ctx, "Gill", Enum.PartType.Block, Vector3.new(u * 0.34, u * 0.05, u * 0.04), darken(pal.belly, 0.2))
			att(ctx, gill, CFrame.new(math.cos(a) * u * 0.3, u * 0.2, math.sin(a) * u * 0.3) * CFrame.Angles(0, -a, 0), IDENTITY, "float", u * 0.024, 1.6, 0.4)
		end
		-- spores drifting up off the cap
		for i = 1, 4 do
			local a = i * 1.7
			local spore = mk(ctx, "Spore", Enum.PartType.Ball, Vector3.new(u * 0.08, u * 0.08, u * 0.08), pal.trim, Enum.Material.Neon, 0.3)
			att(ctx, spore, CFrame.new(0, u * 0.8, 0), CFrame.new(u * 0.34, 0, 0), "orbit", 0, 0.5 + i * 0.12, a)
		end
	end

	eyePair(ctx, u * 0.16, u * 0.02, -u * 0.3, u * 0.24, pal.iris, 1.6, 0.4)
	if det >= 1 then
		cheeks(ctx, u * 0.26, -u * 0.14, -u * 0.26, u * 0.16, lighten(pal.coat, 0.22), 1.6, 0.4)
	end
	grinArc(ctx, u * 0.28, -u * 0.18, -u * 0.3, u * 0.06, ctx.face.curve, 1.6, 0.4)
	if det >= 1 and ctx.face.tongue then tongue(ctx, -u * 0.22, -u * 0.31, u * 0.09, 1.6, 0.4) end

	pairUp(function(side)
		limbAt(ctx, CFrame.new(side * u * 0.16, -u * 0.22, 0), {
			w = u * 0.15, thigh = u * 0.11, shin = u * 0.11,
			amp = 0.44, speed = 3.0, phase = side > 0 and 0 or math.pi,
			color = pal.belly, shinColor = lighten(pal.belly, 0.2), jointColor = pal.coat,
			footWidth = u * 0.19,
		})
		limbAt(ctx, CFrame.new(side * u * 0.24, u * 0.04, 0), {
			name = "Arm", w = u * 0.11, thigh = u * 0.12, shin = u * 0.11,
			amp = 0.4, speed = 3.0, phase = side > 0 and math.pi or 0,
			color = pal.belly, shinColor = lighten(pal.belly, 0.2), jointColor = pal.coat,
			footWidth = u * 0.13,
		})
	end)

	if pal.isBrute then bruteSpikes(ctx, u * 0.34, u * 0.5, 0, u * 0.3) end
	eliteCrown(ctx)
	return body
end

-- CRYSTAL (Galaxy... no: QuantumRealm, MirrorUniverse) -- faceted, not round. Every ball on this
-- rig is a rotated block instead, because the one thing a crystal must not look like is soft.
function RIGS.CRYSTAL(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.62, 0)
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.52, u * 0.66, u * 0.52), pal.skin, Enum.Material.Glass, 0.12)
	body.Reflectance = 0.25

	-- two more prisms through the first at odd angles: that is the whole "faceted" read
	for i, rot in ipairs({ Vector3.new(0, 45, 12), Vector3.new(18, 20, -14) }) do
		local facet = mk(ctx, "Facet", Enum.PartType.Block, Vector3.new(u * 0.42, u * 0.58, u * 0.42), lighten(pal.skin, 0.16), Enum.Material.Glass, 0.16)
		facet.Reflectance = 0.3
		att(ctx, facet, CFrame.new(0, u * 0.02 * i, 0), CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z)), "float", u * 0.014, 1.5, i * 0.6)
	end

	local core = mk(ctx, "Core", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.3, u * 0.22), pal.coat, Enum.Material.Neon)
	att(ctx, core, IDENTITY, CFrame.Angles(0, math.rad(45), 0), "float", u * 0.028, 1.2, 0.5)

	local hood = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.5, u * 0.4, u * 0.4), pal.skin, Enum.Material.Glass, 0.1)
	hood.Reflectance = 0.2
	att(ctx, hood, CFrame.new(0, u * 0.44, -u * 0.06), CFrame.Angles(0, math.rad(12), 0), "float", u * 0.02, 1.5, 0.2)

	eyePair(ctx, u * 0.15, u * 0.48, -u * 0.28, u * 0.22, pal.iris, 1.5, 0.2)
	grinArc(ctx, u * 0.26, u * 0.3, -u * 0.28, u * 0.05, ctx.face.curve, 1.5, 0.2)
	if ctx.face.teeth > 0 then
		fangRow(ctx, det >= 1 and 4 or 2, u * 0.2, u * 0.32, -u * 0.29, u * 0.09, "float", u * 0.02, 1.5, 0.2)
	end

	-- limbs are shards, not sticks
	pairUp(function(side)
		local joint = CFrame.new(side * u * 0.3, u * 0.06, 0)
		local arm = mk(ctx, "Arm", Enum.PartType.Wedge, Vector3.new(u * 0.1, u * 0.34, u * 0.14), lighten(pal.skin, 0.1), Enum.Material.Glass, 0.14)
		att(ctx, arm, joint, CFrame.Angles(math.rad(180), 0, math.rad(side * -18)) * CFrame.new(0, u * 0.17, 0), "swing", 0.4, 2.4, side > 0 and 0 or math.pi)
		limbAt(ctx, CFrame.new(side * u * 0.18, -u * 0.28, 0), {
			w = u * 0.13, thigh = u * 0.13, shin = u * 0.12,
			amp = 0.3, speed = 2.4, phase = side > 0 and math.pi or 0,
			color = pal.trim, shinColor = lighten(pal.skin, 0.1), jointColor = pal.coat,
			material = Enum.Material.Glass, footWidth = u * 0.17,
		})
	end)

	if det >= 1 then
		-- a ring of splinters turning round it, catching the light at different angles
		for i = 1, 6 do
			local a = (i - 1) * (math.pi / 3)
			local shard = mk(ctx, "Splinter", Enum.PartType.Wedge, Vector3.new(u * 0.08, u * 0.24, u * 0.1), pal.coat, Enum.Material.Neon)
			att(ctx, shard, CFrame.new(0, u * 0.16 + (i % 2) * u * 0.16, 0), CFrame.new(u * 0.54, 0, 0) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 30 or -30)), "orbit", 0, i % 2 == 0 and 0.7 or -0.9, a)
		end
	end

	if pal.isBrute then bruteSpikes(ctx, u * 0.28, u * 0.36, 0, u * 0.34) end
	eliteCrown(ctx)
	return body
end

-- IMP (Wormhole, TimeRift) -- small, horned and pleased with itself. Bat wings and a forked tail
-- do most of the work; the body underneath is barely there.
function RIGS.IMP(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.86, -u * 0.1)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.46, u * 0.46, u * 0.42), pal.skin)

	local belly = mk(ctx, "Belly", Enum.PartType.Ball, Vector3.new(u * 0.34, u * 0.3, u * 0.24), pal.belly)
	att(ctx, belly, CFrame.new(0, -u * 0.06, -u * 0.22), IDENTITY, "float", u * 0.016, 2.0, 0.4)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.62, u * 0.54, u * 0.5), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.5, -u * 0.1), IDENTITY, "float", u * 0.024, 2.0, 0.4)

	eyePair(ctx, u * 0.17, u * 0.58, -u * 0.38, u * 0.25, pal.iris, 2.0, 0.4)
	if det >= 1 then
		cheeks(ctx, u * 0.27, u * 0.42, -u * 0.34, u * 0.17, lighten(pal.coat, 0.2), 2.0, 0.4)
	end
	grinArc(ctx, u * 0.36, u * 0.34, -u * 0.37, u * 0.06, ctx.face.curve, 2.0, 0.4)
	fangRow(ctx, det >= 1 and math.max(4, ctx.face.teeth) or 3, u * 0.3, u * 0.35, -u * 0.38, u * 0.11, "float", u * 0.024, 2.0, 0.4)
	if det >= 1 and ctx.face.tongue then tongue(ctx, u * 0.3, -u * 0.39, u * 0.1, 2.0, 0.4) end

	pairUp(function(side)
		-- horns curling back, in bone rather than in the skin tone
		local hj = CFrame.new(side * u * 0.22, u * 0.76, -u * 0.06)
		for seg = 1, 2 do
			local horn = mk(ctx, "Horn", Enum.PartType.Wedge, Vector3.new(u * 0.09, u * 0.2, u * 0.12), BONE)
			att(ctx, horn, hj, CFrame.Angles(math.rad(18 * seg), 0, math.rad(side * -22)) * CFrame.new(0, u * (0.1 + (seg - 1) * 0.18), 0), "float", u * 0.026, 2.0, 0.4)
		end

		-- bat wing: a membrane wedge plus two ribs, which is the difference between a wing and a
		-- triangle
		local wj = CFrame.new(side * u * 0.24, u * 0.18, u * 0.14)
		local membrane = mk(ctx, "Wing", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.5, u * 0.56), pal.coat, Enum.Material.SmoothPlastic, 0.12)
		att(ctx, membrane, wj, CFrame.Angles(0, math.rad(side * -24), math.rad(side * 100)) * CFrame.new(0, u * 0.26, 0), "flap", 0.6, 3.4, side > 0 and 0 or math.pi)
		if det >= 1 then
			for r = 0, 1 do
				local rib = mk(ctx, "WingRib", Enum.PartType.Block, Vector3.new(u * 0.04, u * 0.44, u * 0.04), darken(pal.coat, 0.4))
				att(ctx, rib, wj, CFrame.Angles(0, math.rad(side * -24), math.rad(side * (100 - r * 18))) * CFrame.new(0, u * 0.24, u * (0.1 + r * 0.14)), "flap", 0.6, 3.4, side > 0 and 0 or math.pi)
			end
		end

		limbAt(ctx, CFrame.new(side * u * 0.16, -u * 0.2, 0), {
			w = u * 0.13, thigh = u * 0.13, shin = u * 0.12,
			amp = 0.46, speed = 3.0, phase = side > 0 and 0 or math.pi,
			color = pal.dark, shinColor = pal.skin, jointColor = pal.coat,
			footWidth = u * 0.18, claws = det >= 2,
		})
		limbAt(ctx, CFrame.new(side * u * 0.26, u * 0.14, -u * 0.04), {
			name = "Arm", w = u * 0.1, thigh = u * 0.13, shin = u * 0.12,
			amp = 0.42, speed = 3.0, phase = side > 0 and math.pi or 0,
			color = pal.skin, shinColor = pal.belly, jointColor = pal.coat,
			footWidth = u * 0.13, claws = det >= 1,
		})
	end)

	-- forked tail
	local tj = CFrame.new(0, -u * 0.02, u * 0.26)
	for i = 1, 3 do
		local seg = mk(ctx, "Tail", Enum.PartType.Block, Vector3.new(u * 0.09, u * 0.09, u * 0.2), pal.skin)
		att(ctx, seg, tj, CFrame.Angles(math.rad(-18 * i), 0, 0) * CFrame.new(0, 0, u * (0.1 + (i - 1) * 0.18)), "trail", 0.5, 2.4, 0)
	end
	for _, dir in ipairs({ -1, 1 }) do
		local barb = mk(ctx, "TailBarb", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.2, u * 0.1), pal.coat)
		att(ctx, barb, tj, CFrame.Angles(math.rad(-54), 0, math.rad(dir * 34)) * CFrame.new(0, 0, u * 0.56) * CFrame.Angles(math.rad(-90), 0, 0), "trail", 0.5, 2.4, 0)
	end

	if pal.isBrute then bruteSpikes(ctx, u * 0.24, u * 0.26, u * 0.04, u * 0.28) end
	eliteCrown(ctx)
	return body
end

-- PLANT (AbsolutePlane) -- a carnivorous flower in a pot. The head IS the flower: petals ring a
-- toothed mouth, and the eyes sit on the petals rather than on a face, which is what keeps it from
-- reading as a dog wearing a hat.
function RIGS.PLANT(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.92, -u * 0.06)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.6, u * 0.44, u * 0.6), pal.trim, Enum.Material.Slate)

	local rim = mk(ctx, "PotRim", Enum.PartType.Ball, Vector3.new(u * 0.68, u * 0.16, u * 0.68), lighten(pal.trim, 0.24), Enum.Material.Slate)
	att(ctx, rim, CFrame.new(0, u * 0.2, 0), IDENTITY, "float", u * 0.012, 1.6, 0.3)
	local soil = mk(ctx, "Soil", Enum.PartType.Ball, Vector3.new(u * 0.54, u * 0.1, u * 0.54), Color3.fromRGB(84, 58, 44))
	att(ctx, soil, CFrame.new(0, u * 0.24, 0), IDENTITY, "float", u * 0.012, 1.6, 0.3)

	local stalk = mk(ctx, "Stalk", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.42, u * 0.14), Color3.fromRGB(96, 176, 86))
	att(ctx, stalk, CFrame.new(0, u * 0.26, 0), CFrame.Angles(math.rad(-8), 0, 0) * CFrame.new(0, u * 0.21, 0), "trail", 0.24, 1.8, 0)

	local headJ = CFrame.new(0, u * 0.66, -u * 0.06)
	local maw = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.46, u * 0.4, u * 0.4), darken(pal.coat, 0.35))
	att(ctx, maw, headJ, IDENTITY, "float", u * 0.026, 1.8, 0.5)

	-- the petals: eight, ringed round the mouth and tilted outward
	for i = 1, 8 do
		local a = (i - 1) * (math.pi / 4)
		local petal = mk(ctx, "Petal", Enum.PartType.Ball, Vector3.new(u * 0.3, u * 0.1, u * 0.22), i % 2 == 0 and pal.coat or lighten(pal.coat, 0.22))
		att(ctx, petal, headJ, CFrame.Angles(0, -a, 0) * CFrame.new(u * 0.34, 0, 0) * CFrame.Angles(0, 0, math.rad(16)), "float", u * 0.03, 1.8, 0.5 + i * 0.1)
	end

	eyePair(ctx, u * 0.19, u * 0.78, -u * 0.3, u * 0.24, pal.iris, 1.8, 0.5)
	grinArc(ctx, u * 0.3, u * 0.6, -u * 0.28, u * 0.06, ctx.face.curve, 1.8, 0.5)
	fangRow(ctx, det >= 1 and math.max(5, ctx.face.teeth) or 3, u * 0.28, u * 0.62, -u * 0.29, u * 0.12, "float", u * 0.026, 1.8, 0.5)
	if det >= 1 and ctx.face.tongue then tongue(ctx, u * 0.56, -u * 0.3, u * 0.1, 1.8, 0.5) end

	-- two big leaves for arms, and a pair of stubby roots for feet
	pairUp(function(side)
		local leaf = mk(ctx, "Leaf", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.4, u * 0.24), Color3.fromRGB(112, 196, 96))
		att(ctx, leaf, CFrame.new(side * u * 0.14, u * 0.36, 0), CFrame.Angles(0, 0, math.rad(side * -74)) * CFrame.new(0, u * 0.2, 0), "flap", 0.4, 2.2, side > 0 and 0 or math.pi)
		local root = mk(ctx, "Root", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.16, u * 0.2), darken(pal.trim, 0.3), Enum.Material.Slate)
		att(ctx, root, CFrame.new(side * u * 0.2, -u * 0.24, 0), CFrame.new(0, -u * 0.08, 0), "swing", 0.3, 2.6, side > 0 and 0 or math.pi)
	end)

	if det >= 1 then
		-- vines curling off the pot
		for i = 1, 3 do
			local a = i * 2.1
			local vine = mk(ctx, "Vine", Enum.PartType.Block, Vector3.new(u * 0.05, u * 0.26, u * 0.05), Color3.fromRGB(96, 176, 86))
			att(ctx, vine, CFrame.new(math.cos(a) * u * 0.3, -u * 0.02, math.sin(a) * u * 0.3), CFrame.Angles(math.rad(28), 0, math.rad(20)) * CFrame.new(0, u * 0.13, 0), "trail", 0.45, 2.0 + i * 0.2, i)
		end
	end

	if pal.isBrute then bruteSpikes(ctx, u * 0.26, u * 0.5, 0, u * 0.3) end
	eliteCrown(ctx)
	return body
end

-- JELLY (Nebula) -- a bell with a lit core and long trailing tentacles. Everything is translucent
-- except the face and the rim beads, which is what stops it disappearing against a bright sky.
function RIGS.JELLY(ctx)
	local u, pal, det = ctx.u, ctx.pal, ctx.detail
	ctx.top = CFrame.new(0, u * 0.5, 0)
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.84, u * 0.72, u * 0.84), pal.skin, Enum.Material.SmoothPlastic, 0.36)

	local dome = mk(ctx, "Dome", Enum.PartType.Ball, Vector3.new(u * 0.6, u * 0.5, u * 0.6), lighten(pal.skin, 0.3), Enum.Material.SmoothPlastic, 0.3)
	att(ctx, dome, CFrame.new(0, u * 0.2, 0), IDENTITY, "float", u * 0.04, 1.2, 0)

	local core = mk(ctx, "Core", Enum.PartType.Ball, Vector3.new(u * 0.3, u * 0.26, u * 0.3), pal.coat, Enum.Material.Neon)
	att(ctx, core, IDENTITY, IDENTITY, "float", u * 0.05, 1.0, 0.7)

	-- the rim beads: opaque, bright, and the only hard edge on the whole rig
	beadRing(ctx, det >= 1 and 14 or 8, u * 0.42, -u * 0.1, u * 0.1, pal.trim, Enum.Material.Neon, 0.35)

	eyePair(ctx, u * 0.19, u * 0.06, -u * 0.4, u * 0.26, pal.iris, 1.2, 0)
	if det >= 1 then
		cheeks(ctx, u * 0.3, -u * 0.1, -u * 0.36, u * 0.18, lighten(pal.coat, 0.18), 1.2, 0)
	end
	grinArc(ctx, u * 0.3, -u * 0.14, -u * 0.4, u * 0.06, ctx.face.curve, 1.2, 0)

	-- four short frilled arms inside a ring of long tentacles: two lengths is what makes it read
	-- as a jellyfish rather than as a mop
	for i = 1, 4 do
		local a = (i - 1) * (math.pi / 2) + 0.4
		local frill = mk(ctx, "Frill", Enum.PartType.Wedge, Vector3.new(u * 0.07, u * 0.3, u * 0.16), lighten(pal.skin, 0.2), Enum.Material.SmoothPlastic, 0.25)
		att(ctx, frill, CFrame.new(math.cos(a) * u * 0.2, -u * 0.24, math.sin(a) * u * 0.2),
			CFrame.Angles(math.rad(180), -a, 0) * CFrame.new(0, u * 0.15, 0), "trail", 0.4, 2.2, i * 0.8)
	end
	local strands = pal.isBrute and 8 or 6
	for i = 1, strands do
		local a = (i - 1) * (math.pi * 2 / strands)
		local joint = CFrame.new(math.cos(a) * u * 0.32, -u * 0.24, math.sin(a) * u * 0.32)
		local strand = mk(ctx, "Tentacle", Enum.PartType.Block, Vector3.new(u * 0.06, u * 0.52, u * 0.06), pal.skin, Enum.Material.SmoothPlastic, 0.28)
		att(ctx, strand, joint, CFrame.new(0, -u * 0.26, 0), "trail", 0.6, 1.6 + i * 0.11, i * 0.9)
		if det >= 1 then
			local bead = mk(ctx, "TentacleTip", Enum.PartType.Ball, Vector3.new(u * 0.09, u * 0.09, u * 0.09), pal.coat, Enum.Material.Neon)
			att(ctx, bead, joint, CFrame.new(0, -u * 0.54, 0), "trail", 0.6, 1.6 + i * 0.11, i * 0.9)
		end
	end

	eliteCrown(ctx)
	return body
end

-- Builds the rig for a zone and returns the primary body plus the flat attachments
-- list the idle loop drives. Every rig keeps its body part at the model origin so
-- body.Position stays the spawn position (aura range + billboard depend on that).
local function buildRig(model, position, tierName, zone, tier, yaw, floorY)
	local base = TIERS[tierName]
	local ctx = {
		model = model,
		-- The yaw is baked into the build frame rather than applied afterwards. A creature in a
		-- corner of the platform that no player has walked near is never touched by the idle driver
		-- at all, and it still has to be standing the right way round.
		origin = CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0),
		-- The height of the ground THIS creature stands on -- 0 in the valley, 30 to 107 on the
		-- terraces. Only `meshRig` reads it (the primitive rigs are relative to `origin` throughout
		-- and never had the bug), but it belongs on the context rather than in a parameter list that
		-- every rig builder would have to carry and ignore. Defaults to 0, which is what every
		-- caller before the terraces meant.
		floorY = floorY or 0,
		u = tier.size,
		pal = buildPalette(zone, tierName, tier.colors),
		-- 0 Swarmer / 1 Critter / 2 Brute+Elite. Every optional piece below is gated on this: a
		-- Swarmer is 6.5 studs and 240 of the 520 creatures in the world are Swarmers, so the
		-- layers that only read from close up are not built on one at all.
		detail = (base and base.heavy) and 2 or (tierName == "Swarmer" and 0 or 1),
		atts = {},
	}
	ctx.face = pickFace(zone.key, tierName, ctx.pal.isBrute)
	local archetype = ZONE_ARCHETYPE[zone.key] or "BEAST"

	-- A GENERATED FIGURE WINS IF THIS ARCHETYPE AND TIER HAS ONE.
	--
	-- It is NOT given the face or the topper: those exist to stop a primitive stack of blocks
	-- reading as debris, and a generated creature has a face, a silhouette and its own decoration
	-- already -- the same pass bolted on top reads as clutter welded to a finished model. Same
	-- decision BossService makes about bossDetail.
	local template = creatureMeshTemplate(archetype, tierName)
	local body = template and meshRig(ctx, template)
	if body then
		body.Name = "Body"
		body.CanCollide = true
		body.CFrame = ctx.origin
		model.PrimaryPart = body
		model:SetAttribute("Archetype", archetype)
		return body, ctx.atts
	end

	local builder = RIGS[archetype] or RIGS.BEAST
	body = builder(ctx)
	addTopper(ctx, zone.key, tierName)
	body.Name = "Body"
	body.CanCollide = true
	body.CFrame = ctx.origin
	model.PrimaryPart = body
	model:SetAttribute("Archetype", archetype)
	return body, ctx.atts
end

-- ===== IDLE DRIVER ============================================================
-- One Heartbeat drives every creature in the game, and only the ones a player is standing near
-- are posed at all.
--
-- This used to be a `task.spawn` loop per creature at 20 Hz, which was fine at 160 of them and is
-- not fine at 520: the platform grew to 700 x 860 and each zone went from 8 spawns to 26, so the
-- old shape meant 520 coroutines writing roughly 6,000 CFrames a tick across a 12,000-stud strip
-- that a player can only ever see one corner of. Same fix BossService already uses -- proximity
-- gate plus BulkMoveTo, which is one engine call per creature instead of one per part.
local ANIMATE_RADIUS = 220
-- Inside this a creature stops facing its home direction and turns onto the player. Deliberately
-- smaller than ANIMATE_RADIUS: the far half of the animated set keeps bobbing and keeps facing the
-- middle of its zone, so the platform reads as inhabited from the gate, and only what you are
-- actually near singles you out.
--
-- 32, DOWN FROM 120, and 120 was most of the visible platform. Every creature within two thirds of
-- a screen turned to stare the moment a player entered the zone, so the whole population tracked
-- one walking player at once -- which reads as the map watching you rather than as a creature
-- noticing you, and it removed any sense that walking up to something was an event.
--
-- Sized against the numbers that already exist rather than picked: the client's auto-attack scan is
-- 34 studs and the server validates a blow at `max(clickReach, 34) + tier.size`. At 32 a creature
-- turns onto you just BEFORE you are close enough to hit it, which is the order those two things
-- have to happen in -- a creature that noticed you only once you were already swinging would look
-- oblivious, and one that noticed you at 120 was never not looking.
local LOOK_RADIUS = 32
-- Radians a second. Fast enough that circling a Brute keeps its glare on you, slow enough that the
-- turn is something you watch happen instead of a snap.
local TURN_RATE = math.rad(200)
-- how long a counter-attack lunge takes, start to finish
-- 0.32 -> 0.5. The old figure was the whole of a symmetric shove; this one has to hold a wind-up,
-- a strike and a recovery (see the three-phase curve in driveCreatures), and at 0.32 the telegraph
-- was nine hundredths of a second -- too short to be seen, let alone reacted to.
local LUNGE_TIME = 0.5
-- and how long the flinch off a hit taken lasts. Deliberately shorter than the shortest hit
-- cooldown in TIERS (0.15) so a fast clicker sees a *new* flinch on every blow rather than one
-- long smear -- a recoil that never restarts reads as a creature that is simply leaning.
local HIT_TIME = 0.14

-- How far a creature wanders from where it spawned, and how fast. Small things range further and
-- move quicker; an Elite barely shifts, which is what makes it read as guarding that corner rather
-- than passing through it.
local ROAM = {
	Swarmer = { radius = 42, speed = 12 },
	Critter = { radius = 30, speed = 9 },
	Brute = { radius = 22, speed = 6.5 },
	Elite = { radius = 16, speed = 5 },
}

local live = {} -- [model] = { body, home, pos, size, clock, homeYaw, yaw, atts, parts, cframes, ... }

-- ===== the dark rim, rented rather than owned =====
-- A thick occluded Highlight is the single biggest reason the pets read as drawn and a thirty-part
-- creature reads as debris -- it is the first thing in the notes on this game's art. It could never
-- be put on a creature before because Roblox renders only about 31 Highlights at a time and there
-- are 520 creatures in the world.
--
-- So the creatures do not own their outlines: fourteen Highlights are built once and re-adorned to
-- whichever creatures are nearest a player. A player can only look at a handful at a time, and the
-- ones they are looking at are exactly the ones worth the budget. The sweep runs every 0.4 s --
-- per-frame re-adorning makes the rim flicker on anything sitting near the cut-off.
local OUTLINE_BUDGET = 14
local OUTLINE_INTERVAL = 0.4
local outlinePool = {}
local outlineCandidates = {}
local lastOutlineSweep = 0

local function ensureOutlinePool()
	if #outlinePool > 0 then return end
	local holder = workspace:FindFirstChild("CreatureOutlines")
	if holder then holder:Destroy() end
	holder = Instance.new("Folder")
	holder.Name = "CreatureOutlines"
	holder.Parent = workspace
	for i = 1, OUTLINE_BUDGET do
		local hl = Instance.new("Highlight")
		hl.Name = "Outline" .. i
		hl.FillTransparency = 1
		hl.OutlineColor = INK
		hl.OutlineTransparency = 0
		-- Occluded, not AlwaysOnTop: a creature behind a rock should not glow through it
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = nil
		hl.Parent = holder
		outlinePool[i] = hl
	end
end

-- Every rig in this file is built facing -Z, so the yaw that puts the FRONT of one onto a target is
-- the arctangent of the NEGATED delta. Getting that sign wrong is silent -- the creature simply
-- looks the other way, which is the bug this whole block exists to fix.
local function yawToward(fromX, fromZ, toX, toZ)
	local dx, dz = toX - fromX, toZ - fromZ
	if dx * dx + dz * dz < 1e-4 then return 0 end
	return math.atan2(-dx, -dz)
end

-- shortest signed way round from a to b
local function angleDelta(a, b)
	return (b - a + math.pi) % (math.pi * 2) - math.pi
end

local function registerCreature(model, body, position, attachments, size, homeYaw, tierName, ring, zoneX, hitbox, hitboxOffset, floorY)
	-- Built once. Every attachment is listed, moving or not: the whole rig rides the body's bob and
	-- sway, so a part with no motion of its own still has to be re-placed against the new base.
	local parts = { body }
	for _, a in ipairs(attachments) do
		table.insert(parts, a.part)
	end
	-- The ground ring and the hit box ride along at the end of the bulk arrays, and their slots are
	-- recorded rather than derived. They used to be indexed as `#atts + 2` at the far end of
	-- driveCreatures, which is the sort of arithmetic that is silently wrong the moment a third
	-- trailing part joins the list -- and the wrong slot means writing the ring's CFrame over a limb.
	local ringIndex, hitboxIndex
	if ring then
		table.insert(parts, ring)
		ringIndex = #parts
	end
	if hitbox then
		table.insert(parts, hitbox)
		hitboxIndex = #parts
	end
	local roam = ROAM[tierName] or ROAM.Critter
	live[model] = {
		-- the centre line of the zone this belongs to; the keep-out tests are relative to it
		zoneX = zoneX,
		body = body,
		-- `home` is where it was spawned and never moves; `pos` is where it is right now. Splitting
		-- the two is what lets a creature wander and still be tied to the corner it belongs to.
		home = position,
		pos = position,
		origin = position, -- kept for the proximity test, which measures from the spawn point
		ring = ring,
		ringIndex = ringIndex,
		-- the height of the ground THIS creature is standing on. Not derivable from `pos`, which is
		-- the body centre and moves with the tier's size, and not a constant, because half the heavy
		-- tiers now live twenty to a hundred studs up on the terraces.
		floorY = floorY or 0,
		hitboxIndex = hitboxIndex,
		-- where the box sits in the BODY's frame, so it follows the bob, the turn, the flinch and
		-- the lunge without any of that being recomputed for it
		hitboxOffset = hitboxOffset,
		roamRadius = roam.radius,
		roamSpeed = roam.speed,
		target = nil,
		waitUntil = 0,
		-- its own animation clock, advanced by dt * gait rather than read off os.clock(). Speeding
		-- up a shared wall clock jumps the phase of every limb the instant the gait changes.
		clock = position.X % 6.28,
		gait = 1,
		lungeUntil = 0,
		hitUntil = 0,
		size = size,
		-- the old loop offset its clock by the spawn's X so a row of creatures never bobbed in
		-- lockstep; keep that, it is the difference between a crowd and a chorus line
		phase = position.X % 6.28,
		-- where it looks when nobody is close, and where it is looking right now
		homeYaw = homeYaw or 0,
		yaw = homeYaw or 0,
		atts = attachments,
		parts = parts,
		cframes = table.create(#parts),
	}
end

-- ===== HEALING BACK UP =======================================================
-- Damage used to be permanent until death, which made the cheapest way to kill anything above your
-- own zone: chip it, walk off, heal yourself, walk back, repeat. That is a fight decided by how
-- fast the PLAYER recovers rather than by whether they can beat the creature -- and it is worse the
-- further above its weight the player is punching, which is exactly backwards.
--
-- A creature nobody has touched for REGEN_DELAY closes the wound over REGEN_TIME, whether or not
-- anyone is still in the zone to see it. The delay is the whole balance of it: it is long enough
-- that it never interferes with a fight in progress (a swing lands every 0.34 s), and short enough
-- that a round trip to a spawn point does not pay.
--
-- One table and one loop, and the table only ever holds creatures that are actually hurt -- the one
-- or two being fought right now, never the 520 standing in the world.
-- ===== WHY THIS READ AS "CREATURES DO NOT HEAL" (10.19) =====
--
-- The regeneration was implemented, wired to Heartbeat and provably working -- and no player could
-- ever see it happen. The health plate is only drawn over the scenery for **5 seconds** after a hit
-- (`plateHotUntil` in onHit), and healing did not begin until **7**. So the bar stopped being
-- visible two full seconds before it started moving, every single time. The report was right about
-- the experience and wrong about the cause, which is why the fix is timing and visibility rather
-- than logic.
--
-- DELAY 7 -> 3: healing now starts while the plate is still hot, so the first thing a player sees
-- after walking away is the bar climbing. Still comfortably longer than the 0.34 s auto-attack
-- interval, so it cannot interfere with a fight in progress -- which was the whole point of the
-- delay and has not changed.
--
-- TIME 8 -> 5: a full heal that takes eight seconds to watch is not feedback, it is a screensaver.
local REGEN_DELAY = 3
local REGEN_TIME = 5
local hurt = {} -- [model] = { max, hp, lastHit, draw, plate }

local function driveRegen(dt)
	if not next(hurt) then return end
	local now = os.clock()
	for model, e in pairs(hurt) do
		if not model.Parent then
			hurt[model] = nil
		elseif now - e.lastHit >= REGEN_DELAY then
			-- the precise value lives on the entry and only the rounded one is published: healing
			-- 12 health over 5 seconds is 0.04 a frame, and a floor() applied to the attribute
			-- itself would round every one of those steps away and heal nothing at all
			e.hp = math.min(e.hp + e.max * (dt / REGEN_TIME), e.max)
			local shown = math.floor(e.hp)
			model:SetAttribute("Health", shown)
			e.draw(shown)
			-- HOLD THE PLATE UP FOR AS LONG AS IT IS HEALING. Without this the bar is occluded again
			-- 5 s after the last hit and the last two seconds of the climb happen behind the scenery
			-- -- which is the bug above, just two seconds smaller.
			if e.plate and e.plate.Parent then
				e.plate.AlwaysOnTop = true
			end
			if e.hp >= e.max then
				model:SetAttribute("Health", e.max)
				e.draw(e.max)
				-- back to occluded now it is whole again: 520 creatures drawing a full bar through
				-- the walls is exactly the wall of labels AlwaysOnTop = false exists to prevent
				if e.plate and e.plate.Parent then
					e.plate.AlwaysOnTop = false
				end
				hurt[model] = nil
			end
		end
	end
end

local function driveCreatures(dt)
	-- before the early return below: a creature left at 3 % health has to heal back up even if the
	-- player who hurt it has left the zone entirely, which is the single most likely way it happens
	driveRegen(dt or (1 / 60))

	local positions = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			table.insert(positions, hrp.Position)
		end
	end
	if #positions == 0 then return end

	local now = os.clock()
	-- capped so a Studio hitch cannot spin every creature in the game a full turn in one frame
	local step = math.min(dt or (1 / 60), 0.1) * TURN_RATE
	local sweepOutlines = (now - lastOutlineSweep) >= OUTLINE_INTERVAL
	if sweepOutlines then
		table.clear(outlineCandidates)
	end

	for model, rig in pairs(live) do
		if not model.Parent then
			live[model] = nil
		else
			local origin = rig.origin
			local near = false
			local closest, closestDist = nil, math.huge
			for _, p in ipairs(positions) do
				local d = (p - origin).Magnitude
				if d <= ANIMATE_RADIUS then
					near = true
					if d < closestDist then
						closestDist, closest = d, p
					end
				end
			end

			if near then
				if sweepOutlines and #outlineCandidates < 96 then
					table.insert(outlineCandidates, { model = model, d = closestDist })
				end

				local frame = dt or (1 / 60)

				-- ---- where it is going, and which way it is looking
				local want = rig.homeYaw
				local moving = false

				-- ===== MEASURED FROM THE BODY, NOT FROM THE SPAWN POINT =====
				--
				-- `closestDist` above is the distance to `rig.origin`, which is where this creature was
				-- placed rather than where it is standing -- it roams up to `roamRadius` away from it.
				-- That was harmless at LOOK_RADIUS 120, where a roam is a rounding error, and is not at
				-- 32, where it is most of the radius: measured live, a creature 28 studs from the player
				-- kept facing its idle direction because its ORIGIN was further off, so the reaction
				-- distance the player actually experienced was neither 32 nor consistent between two
				-- creatures standing side by side.
				--
				-- The animate gate above deliberately keeps using `origin`: it decides whether to run
				-- this rig at all, wants to be stable as the creature wanders, and is checked against a
				-- radius seven times larger. Only the look test needs the live position, and it costs
				-- one subtraction on rigs that are already near a player.
				local lookDist = closest and (Vector3.new(closest.X, rig.pos.Y, closest.Z) - rig.pos).Magnitude or math.huge
				if closest and lookDist <= LOOK_RADIUS then
					-- someone is close: stop wandering, square up to them, and do not set off again
					-- until they have been gone a moment
					want = yawToward(rig.pos.X, rig.pos.Z, closest.X, closest.Z)
					rig.waitUntil = now + 1.4
				elseif now >= rig.waitUntil then
					local target = rig.target
					local toGo = target and Vector3.new(target.X - rig.pos.X, 0, target.Z - rig.pos.Z)
					if not toGo or toGo.Magnitude < 2 then
						-- arrived, or never had a target: stand about for a beat, then pick a new
						-- spot inside the patch this creature belongs to. Up to six tries against
						-- the keep-out rules, and the home point if none of them pass -- a creature
						-- boxed in against the street simply stays where it was put.
						local newTarget = rig.home
						for _ = 1, 6 do
							local a = math.random() * math.pi * 2
							local r = rig.roamRadius * (0.35 + math.random() * 0.65)
							local cx = rig.home.X + math.cos(a) * r
							local cz = rig.home.Z + math.sin(a) * r
							-- the rules say where it MAY go; the overlap query says what is actually
							-- standing there; the ray says whether it is the same FLOOR. Only run when a
							-- target is picked (every few seconds, and only for creatures near a player),
							-- never per frame.
							--
							-- The floor test is what keeps a shelf creature on its shelf. `pos.Y` never
							-- changes while roaming -- the rigs are anchored and walked by hand, they do not
							-- fall -- so a target one tread over means an Elite strolling off a 30-stud drop
							-- and standing in mid-air, or wading through the shelf above it up to its chest.
							-- Two studs of tolerance covers the ground's own small dressing, nothing more.
							-- Cheapest test first: a ray costs less than the box query behind it.
							if not insideKeepOut(cx - rig.zoneX, cz)
								and math.abs(floorAt(cx, cz, rig.floorY) - rig.floorY) <= 2
								and not blockedAt(cx, rig.home.Y, cz, rig.size) then
								newTarget = Vector3.new(cx, rig.home.Y, cz)
								break
							end
						end
						rig.target = newTarget
						rig.waitUntil = now + 0.7 + math.random() * 2.6
					else
						local nextPos = rig.pos + toGo.Unit * math.min(rig.roamSpeed * frame, toGo.Magnitude)
						-- The keep-out rules say where it may walk; they know nothing about what is
						-- actually standing there, so a creature with a clear target still walked
						-- straight into a boulder or the boundary rampart on the way to it. Probed
						-- four times a second per MOVING rig near a player, not per frame: the step is
						-- a couple of studs and the things it can hit are tens of studs across.
						local solid = false
						if now >= (rig.probeAt or 0) then
							rig.probeAt = now + 0.25
							solid = blockedAt(nextPos.X, nextPos.Y, nextPos.Z, rig.size)
						end
						if solid or insideKeepOut(nextPos.X - rig.zoneX, nextPos.Z) then
							rig.target = nil
							rig.waitUntil = now + 0.4
						else
							rig.pos = nextPos
							want = yawToward(rig.pos.X, rig.pos.Z, target.X, target.Z)
							moving = true
						end
					end
				end

				local delta = angleDelta(rig.yaw, want)
				if math.abs(delta) <= step then
					rig.yaw = want
				else
					rig.yaw += (delta > 0 and step or -step)
				end

				-- ---- the gait. Legs swing further and faster while walking, and the change is
				-- eased rather than switched: a creature that snaps from idle to a run looks like
				-- it teleported into the animation.
				rig.gait += math.clamp((moving and 2.15 or 1) - rig.gait, -4 * frame, 4 * frame)
				-- its OWN clock, advanced by dt * gait. Scaling a shared wall clock instead would
				-- jump the phase of every limb the instant the gait changed.
				rig.clock += frame * rig.gait
				local swingScale = 1 + (rig.gait - 1) * 0.45

				local t = rig.clock + rig.phase
				-- the bounce grows with the gait. A creature crossing the ground at the same
				-- height it stands at reads as sliding, whatever its legs are doing.
				local bob = math.sin(t * 1.6) * (rig.size * 0.05) * (1 + (rig.gait - 1) * 0.9)
				-- the idle waver is small and rides ON TOP of the facing. It used to BE the facing,
				-- which is exactly why every creature in the game swung slowly between two
				-- directions it had no reason to be looking in.
				local sway = math.sin(t * 0.6) * 0.09
				-- the counter-attack, thrown forward along the rig's own -Z. Every heavy tier
				-- already hit back; without this it did it invisibly, and being taken to half
				-- health by something standing perfectly still reads as a bug, not as a fight.
				-- ===== WIND UP, STRIKE, RECOVER -- NOT ONE SYMMETRIC SHOVE (10.19) =====
				--
				-- This was `sin(k * pi)`: an equal glide out and back, with no pitch on it. A push
				-- that leaves at the same speed it returns has no moment of impact in it, so at any
				-- distance it read as the creature drifting rather than hitting -- which is the
				-- "creatures need an animation when they attack" report.
				--
				-- Three phases against the clock, because that is what an attack is made of:
				--   0-28%  pull BACK and rear up, which is the telegraph -- it is what makes the
				--          strike legible before it lands, and gives the player the beat to react in
				--   28-55% snap FORWARD, four times faster than the wind-up, pitching down into it
				--   55-100% ease home on a squared falloff, so it settles instead of stopping dead
				--
				-- Position AND pitch move together. Pitch is most of what sells it: the same travel
				-- with a level body is a lunge by a creature that is not looking at you.
				local lunge, lungePitch = 0, 0
				if now < rig.lungeUntil then
					local p = 1 - (rig.lungeUntil - now) / LUNGE_TIME -- 0 at the start, 1 at the end
					-- explicitly initialised: an uninitialised `local` is the one shape
					-- tools/luanames.py does not reliably bind, and the baseline is worth keeping clean
					local surge = 0
					if p < 0.28 then
						-- eased, so the telegraph is a gather rather than a jerk
						local k = math.sin((p / 0.28) * math.pi * 0.5)
						surge, lungePitch = -0.35 * k, 0.24 * k
					elseif p < 0.55 then
						local k = (p - 0.28) / 0.27
						surge, lungePitch = -0.35 + 1.35 * k, 0.24 - 0.58 * k
					else
						local k = (p - 0.55) / 0.45
						local e = (1 - k) * (1 - k)
						surge, lungePitch = 1.00 * e, -0.34 * e
					end
					lunge = surge * rig.size * 0.42
				end
				-- The flinch: the same throw as the lunge but BACKWARDS, with a pitch back and a shiver
				-- on top of the facing. Taking damage used to change a number on a bar and nothing else
				-- in the world, which is the whole of why the fight read as popping a balloon.
				local recoil, flinch, shiver = 0, 0, 0
				if now < rig.hitUntil then
					local k = (rig.hitUntil - now) / HIT_TIME
					local arc = math.sin(k * math.pi)
					recoil = arc * rig.size * 0.34
					flinch = arc * 0.40
					-- off a wall clock, not the rig's own: a shiver is a vibration, and the rig clock is
					-- deliberately smooth and gait-scaled
					shiver = math.sin(now * 54) * 0.055 * k
				end
				-- and it leans into the walk. Two degrees of pitch is barely visible on a still
				-- frame and is most of what sells the movement in motion.
				local lean = (rig.gait - 1) * 0.075
				-- every rig in this file is built facing -Z, so the lunge is -Z and the recoil is +Z
				local base = CFrame.new(rig.pos.X, rig.pos.Y + bob, rig.pos.Z)
					* CFrame.Angles(0, rig.yaw + sway + shiver, 0)
					-- `lungePitch` rides the same axis as the flinch: positive rears the body back
					-- (the wind-up), negative drives it down and forward (the strike)
					* CFrame.Angles(-lean + flinch + lungePitch, 0, 0)
					* CFrame.new(0, 0, recoil - lunge)

				local parts, cframes = rig.parts, rig.cframes
				cframes[1] = base
				for i, a in ipairs(rig.atts) do
					local anim
					local motion = a.motion
					if motion == "orbit" then
						-- the one continuous kind: it ignores amp and revolves at `speed` (signed, so
						-- counter-rotating rings read as two shells)
						anim = CFrame.Angles(0, t * a.speed + a.phase, 0)
					elseif motion == "flick" then
						-- the same one-shot shape as the blink, but as a roll: a twitch, then
						-- nothing for several seconds
						local cycle = (t * a.speed + a.phase) % 6.2831853
						anim = CFrame.Angles(0, 0, cycle < 0.5 and math.sin(cycle / 0.5 * math.pi * 2) * a.amp or 0)
					elseif motion == "blink" then
						-- one short dip per cycle, not a sine. An eyelid easing continuously up
						-- and down is a creature falling asleep; a blink is 0.4 s of movement in
						-- every six seconds of stillness.
						local cycle = (t * a.speed + a.phase) % 6.2831853
						anim = CFrame.new(0, -a.amp * (cycle < 0.42 and math.sin(cycle / 0.42 * math.pi) or 0), 0)
					elseif motion and a.amp ~= 0 then
						-- limbs reach further at a walk; the face and the trailing bits do not
						local wave = math.sin(t * a.speed + a.phase) * a.amp
							* ((motion == "swing") and swingScale or 1)
						if motion == "float" then
							anim = CFrame.new(0, wave, 0)
						elseif motion == "swing" then
							anim = CFrame.Angles(wave, 0, 0)
						elseif motion == "trail" then
							anim = CFrame.Angles(0, wave, 0)
						elseif motion == "flap" then
							anim = CFrame.Angles(0, 0, wave)
						end
					end
					-- the motion sits BETWEEN pivot and rest, so a leg swings from its hip instead of
					-- spinning around its own middle
					local chain = a.chain
					if chain then
						-- hip -> thigh swing -> knee -> shin swing -> the part's own offset
						local bend = math.sin(t * chain.speed + chain.phase) * chain.amp * swingScale
						cframes[i + 1] = base * a.pivot * (anim or IDENTITY) * chain.mid
							* CFrame.Angles(bend, 0, 0) * a.rest
					else
						cframes[i + 1] = anim and (base * a.pivot * anim * a.rest) or (base * a.offset)
					end
				end
				if rig.ringIndex then
					-- follows on the ground, inherits neither the bob nor the yaw. `floorY` rather than a
					-- constant: a creature up on a shelf has to drag its disc up there with it.
					cframes[rig.ringIndex] = CFrame.new(rig.pos.X, rig.floorY + 0.35, rig.pos.Z) * CFrame.Angles(0, 0, math.rad(90))
				end
				if rig.hitboxIndex then
					-- the opposite of the ring: the box IS the rig as far as the mouse is concerned,
					-- so it takes the body's frame whole
					cframes[rig.hitboxIndex] = base * rig.hitboxOffset
				end
				workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end

	if sweepOutlines then
		lastOutlineSweep = now
		table.sort(outlineCandidates, function(a, b) return a.d < b.d end)
		for i = 1, OUTLINE_BUDGET do
			local c = outlineCandidates[i]
			-- nil is a valid Adornee and is what releases one back to the pool
			outlinePool[i].Adornee = c and c.model or nil
		end
	end
end

-- ===== TAKING A HIT, AND DYING OF ONE ========================================

-- A white wash over the whole rig for four frames. It is rented, not owned: Roblox renders roughly
-- 31 Highlights at a time and the outline pool below already holds fourteen of them, so this one is
-- created per hit and taken away by Debris rather than kept on 520 creatures forever.
local function flashHit(model)
	local hl = Instance.new("Highlight")
	hl.Name = "HitFlash"
	hl.FillColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.32
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = model
	Debris:AddItem(hl, 0.09)
end

-- Chunky square confetti and a ground shockwave, not a smoke puff: everything else in this game is
-- hard-edged, and a soft grey cloud is the one effect that would read as borrowed from another one.
local function deathBurst(parent, position, color, size)
	local host = Instance.new("Part")
	host.Name = "DeathBurst"
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(position)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Parent = parent

	local att = Instance.new("Attachment")
	att.Parent = host

	local bits = Instance.new("ParticleEmitter")
	bits.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	bits.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.17),
		NumberSequenceKeypoint.new(0.7, size * 0.11),
		NumberSequenceKeypoint.new(1, 0),
	})
	bits.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	bits.Lifetime = NumberRange.new(0.35, 0.75)
	bits.Speed = NumberRange.new(size * 0.9, size * 2.2)
	bits.SpreadAngle = Vector2.new(180, 180)
	bits.Rate = 0
	bits.RotSpeed = NumberRange.new(-280, 280)
	-- they fall: confetti that drifts is smoke, confetti that drops is debris
	bits.Acceleration = Vector3.new(0, -size * 3.6, 0)
	bits.LightEmission = 0.35
	bits.Parent = att
	bits:Emit(18)

	Debris:AddItem(host, 1.8)

	-- the shockwave on the floor, where the ground ring was
	local wave = Instance.new("Part")
	wave.Name = "DeathWave"
	wave.Shape = Enum.PartType.Cylinder
	wave.Size = Vector3.new(0.3, size * 0.5, size * 0.5)
	wave.CFrame = CFrame.new(position.X, 0.5, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	wave.Color = color
	wave.Material = Enum.Material.Neon
	wave.Transparency = 0.25
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CastShadow = false
	wave.Parent = parent
	TweenService:Create(wave, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, size * 2.7, size * 2.7),
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.6)
end

-- A creature used to be Destroy()ed on the frame its health reached zero. That is exactly the "it
-- vanishes like a balloon" the fight was accused of: the thing you were fighting stopped existing
-- between two frames, with no beat of it losing.
--
-- The FIRST thing this does is drop the rig out of `live`, and it has to. Model:PivotTo and
-- Model:ScaleTo write every part's CFrame, and the idle driver writes them all back from its own
-- maths on the very next Heartbeat -- with the rig still registered the corpse just stands there,
-- unmoved and wrongly sized, while this loop fights it sixty times a second.
local DEATH_TIME = 0.42

local function playDeath(model, rig, size, knockDir, color)
	live[model] = nil
	-- and out of the regen set, for the same reason as the handler below: the entry holds a closure
	-- over this model's health bar, and a corpse must not go on healing
	hurt[model] = nil
	-- and out of the auto-attack registry, explicitly. The table has weak keys as a backstop, but
	-- its VALUE holds the body part -- which holds the model alive on the engine side -- so waiting
	-- for the key to be collected would keep every corpse in the game resident forever.
	hitHandlers[model] = nil

	local pivot = model:GetPivot()
	local yaw = rig and rig.yaw or 0
	local folder = model.Parent

	-- nothing on a corpse should still be interactive, lit, emitting or labelled
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ClickDetector") then
			d:Destroy()
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("Light") then
			d.Enabled = false
		end
	end
	-- the ground disc stays on the ground. It is the one part of the rig that never rode the bob,
	-- and a neon plate cartwheeling into the air with the body would give that away.
	local ring = model:FindFirstChild("GroundRing")
	if ring then
		ring:Destroy()
	end

	deathBurst(folder, pivot.Position, color, size)

	task.spawn(function()
		local t0 = os.clock()
		while model.Parent do
			local k = (os.clock() - t0) / DEATH_TIME
			if k >= 1 then
				break
			end
			-- knocked along the blow, up over an arc, spinning, shrinking to nothing
			local ease = 1 - (1 - k) * (1 - k)
			local pos = pivot.Position
				+ knockDir * (size * 0.85 * ease)
				+ Vector3.new(0, size * 0.6 * math.sin(k * math.pi), 0)
			model:PivotTo(CFrame.new(pos)
				* CFrame.Angles(0, yaw + k * 5.4, 0)
				* CFrame.Angles(-k * 2.1, 0, k * 1.3))
			-- ScaleTo is absolute against the rig's built size, so passing the current value every
			-- frame is the whole animation -- it does not compound
			model:ScaleTo(math.max(1 - ease * 0.94, 0.06))
			RunService.Heartbeat:Wait()
		end
		model:Destroy()
	end)
end

-- The colour of the disc a creature stands on. Same job as the pets' rarity ring: it plants the
-- rig on the floor instead of leaving it hovering over its own shadow, and it says which tier this
-- is from further away than a health bar or a name ever could.
local TIER_RING = {
	Swarmer = Color3.fromRGB(255, 226, 96),
	Critter = Color3.fromRGB(126, 236, 160),
	Brute = Color3.fromRGB(255, 96, 84),
	Elite = Color3.fromRGB(255, 205, 70),
}

-- `raised` marks a cliff-dweller: one of the Brutes and Elites that Init puts on the terrace
-- shelves rather than on the valley floor. It decides exactly one thing -- whether this creature
-- can drop an Evolution Shard (9.4) -- and it is carried on the spawn rather than worked out from
-- the position, because the two are the same rig at the same tier and nothing about the creature
-- itself knows which loop placed it. It has to be threaded through the respawn below as well, or
-- the shelves would pay shards exactly once per server and never again.
-- ===== A CREATURE THAT HAS BEEN KILLED BEFORE COMES BACK TOUGHER =====
--
-- `generation` is how many times this spawn point has been cleared. It rides the respawn call the
-- same way `raised` does, and for the same reason: it belongs to the SPAWN, not to the creature
-- object, which stops existing every time it dies.
--
-- IT IS A PROPERTY OF THE PLACE, NOT OF THE PLAYER, and it has to be -- health is one number on one
-- model that every player in the zone is looking at, so there is no per-player version of this that
-- is not a lie to everyone else standing there.
--
-- ===== AND THE PAYOUT DELIBERATELY DOES NOT MOVE =====
--
-- DNA and XP per kill are untouched by this, on the owner's decision (2026-08-10). The pull was
-- between two rules that point opposite ways: "the same creature should get stronger" and "a kill
-- must never pay more just because you have killed more" -- and paying more for a tougher creature
-- is exactly the auto-increment the second rule exists to remove, however it is dressed up. So
-- farming one spot gets slowly worse and moving up a zone is always the better play, which is the
-- pressure the growth is FOR. There is no hidden reward ramp anywhere in the kill path.
-- ===== THE "THIS ONE IS SEALED" NOTICE (11.6) =====
--
-- Per-player rather than per-creature: the message is about the player's own save, so a second
-- locked creature two seconds later has nothing new to say. Declared UP HERE, above `spawnCreature`,
-- because the gate that reads it lives in `onHit` inside that function -- a `local` further down the
-- file is not an upvalue of a closure defined above it and would read as a nil global, which throws
-- on the index at exactly the moment an under-rebirthed player swings at an Apex.
local lockNoticeAt = {}
local LOCK_NOTICE_COOLDOWN = 6

local HEALTH_GROWTH = 0.05   -- +5% of base per clearance
-- ...and never more than double, however long a spot is farmed. FROM GameConfig for the same reason
-- Elite health is: the boss floor is priced against a creature at this cap, so a private copy here
-- would let the two curves drift the moment either was tuned.
local HEALTH_GROWTH_MAX = GameConfig.CreatureGenerationMax

-- Kept as a function rather than inlined so the cap is stated once and the HUD, a test or a future
-- Journal line can ask the same question and get the same answer.
local function generationHealthMult(generation)
	return math.min(1 + (generation or 0) * HEALTH_GROWTH, HEALTH_GROWTH_MAX)
end

local function spawnCreature(position, tierName, zone, raised, generation)
	local base = TIERS[tierName]
	-- before anything is built: the rig, the ground ring, the hit box and the roam home are all
	-- placed from this one point, so moving it afterwards would mean moving all four
	position = clearOfScenery(position, base.size, zone.offset)
	-- ...and clearOfScenery can walk a point up to 110 studs sideways to get it out of a boulder,
	-- which for anything standing on a shelf is easily far enough to walk it off the edge. So the
	-- ground is asked AFTER the point is final, never before. Every rig reaches about half its size
	-- below the body centre, so 0.56 of the tier size is where the feet meet whatever is down there.
	local floorY = floorAt(position.X, position.Z, position.Y - base.size * 0.56)
	position = Vector3.new(position.X, floorY + base.size * 0.56, position.Z)
	-- effective (zone-scaled) stats for this specific spawn
	local tier = {
		-- ...times how many times this spot has been cleared, capped at x2 -- see generationHealthMult.
		-- Floored to at least 1: a rounding path that produced a 0-health creature would be dead on
		-- arrival and respawn forever.
		health = math.max(1, math.floor(base.health * zone.mobHealthMult * generationHealthMult(generation))),
		hitCooldown = base.hitCooldown,
		respawnDelay = base.respawnDelay,
		dnaMult = base.dnaMult * zone.mobDnaMult,
		-- floored to a whole number, and never below 1: XP is a counter a player reads off a bar, and
		-- a kill that adds 0.7 of a point reads as a kill that paid nothing
		xp = math.max(1, math.floor(base.xp * zone.mobXpMult)),
		size = base.size,
		colors = base.colors,
		label = creatureLabel(tierName, zone),
		retaliateChance = base.retaliateChance,
		retaliateDamage = { math.floor(base.retaliateDamage[1] * zone.mobDamageMult), math.floor(base.retaliateDamage[2] * zone.mobDamageMult) },
		auraRange = base.auraRange,
		auraDamage = base.auraDamage and { math.floor(base.auraDamage[1] * zone.mobDamageMult), math.floor(base.auraDamage[2] * zone.mobDamageMult) } or nil,
		auraInterval = base.auraInterval,
	}
	-- derived from the SCALED health, so the cap is worth more in a late zone exactly as the
	-- creature is: the hit count stays the same everywhere, which is the point of it
	-- `damageCap` used to live here and is deliberately gone: it clamped every outgoing blow to
	-- `health / minHits`, which made the number over a creature a constant per tier and hid the
	-- entire evolution ladder behind it. `minHits` itself stays -- it is still what bounds the
	-- damage the creature deals BACK (see hurtPlayer), which is a different and still-valid guard.

	local model = Instance.new("Model")
	model.Name = tierName

	-- Which way it stands when nobody is near. A zone is one street running along Z with the egg
	-- plaza in the middle of it, so facing the middle turns the whole platform inward: a creature
	-- 300 studs out in a corner now looks at the place players actually walk instead of at the
	-- boundary wall behind it.
	local homeYaw = yawToward(position.X, position.Z, zone.offset, 0)

	-- per-biome rig: `body` is the torso/core and stays the PrimaryPart; `attachments`
	-- is every other part paired with its joint, motion kind and animation phase
	local body, attachments = buildRig(model, position, tierName, zone, tier, homeYaw, floorY)
	local bodyBaseSize = body.Size

	-- chunky comic health bar, built from the shared design system. Instance names are
	-- deliberately kept identical to the pre-restyle billboard (the fill is still "Fill")
	-- so anything walking this hierarchy keeps working.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CreaturePlate"
	billboard.Size = UDim2.new(0, 186, 0, 58)
	-- off the rig's own size: the tiers run 6.5 to 26 studs and a constant offset wears the plate
	-- through an Elite's chest
	billboard.StudsOffset = Vector3.new(0, tier.size * 0.95, 0)
	billboard.AlwaysOnTop = false
	-- Unreadable in the dark half of the strip without this, exactly where the fights are hardest
	billboard.LightInfluence = 0
	-- Was 45. A player's body scales 1x -> 9x and the camera sits behind the head, so at the later
	-- stages the creature you are actually punching is further than 45 studs from the lens: the
	-- health bar existed but nobody past Lizard had ever seen one.
	billboard.MaxDistance = 150
	billboard.Parent = body

	local _barBg, barFill, barLabel = UITheme.ProgressBar(billboard, {
		name = "Frame",
		size = UDim2.new(1, -14, 0, 20),
		position = UDim2.new(0, 7, 1, -24),
		radius = UDim.new(1, 0),
		thickness = 3,
		progress = 1,
		color = UITheme.Color[base.plateColor] or UITheme.Color.Green,
		text = shortNumber(tier.health) .. " / " .. shortNumber(tier.health),
		minTextSize = 10,
		maxTextSize = 15,
	})

	local nameLabel = UITheme.Label(billboard, {
		name = "TextLabel",
		text = tier.label,
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.new(0, 0, 0, -2),
		minTextSize = 14,
		maxTextSize = 22,
	})

	-- ===== A CLICK IS MELEE. It used to be artillery. =====
	--
	-- This was `math.max(26, tier.size * 2.2)`, which put an Elite at 57 studs and a Swarmer at 26 --
	-- so creatures could be picked off from most of the way across a clearing without ever walking
	-- up to one. That is the "range for fighting creatures is too big" report.
	--
	-- The shape changed as well as the number. `size * 2.2` grows the reach FASTER than the body,
	-- so the biggest creatures were the ones you could hit from furthest away; `size * 0.6` grows it
	-- slower, so every tier ends up at roughly the same standing gap and the reach only covers the
	-- part of the distance the creature's own body occupies. 16 is that standing gap.
	--
	-- Resulting reach: Swarmer 19.9, Critter 22.6, Brute 25.6, Elite 31.6 -- against bodies of
	-- 6.5 / 11 / 16 / 26, i.e. you have to be next to it.
	--
	-- 15.21 RESTORED THIS FROM `tier.size * 0.4 + 10`, and the number that settles it is the PLAYER's
	-- body, which nothing on this path has ever measured. A max-stage character's bounding box is
	-- 30.7 x 42.9 x 27.1 studs, so its half-width from the HumanoidRootPart -- which is the point
	-- both reaches are measured from -- is 15.4. Against a Critter whose own box is 22 wide, a
	-- 14.4-stud reach means the two bodies have to OVERLAP by 12 studs before a blow is legal.
	-- Any reach at all under ~27 is unreachable for a late-stage player standing outside the rig.
	local clickReach = tier.size * 0.6 + 16
	-- the ground disc. Not registered as an attachment on purpose: the rig bobs, the ring does
	-- not, and a ring that bobs with the creature stops reading as something on the floor.
	local ringColor = TIER_RING[tierName] or TIER_RING.Critter
	local ring = Instance.new("Part")
	ring.Name = "GroundRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, tier.size * 1.45, tier.size * 1.45)
	-- ON THIS CREATURE'S OWN FLOOR, not on y = 0.35. Hard-coding the valley height put a 38-stud
	-- gold disc out in mid-air below every creature standing on a shelf -- "something yellow and
	-- round hanging in the air", reported from a screenshot, and the ring is one of the two things
	-- that was.
	ring.CFrame = CFrame.new(position.X, floorY + 0.35, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = ringColor
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = model

	if base.heavy then
		-- only the two tiers worth walking over to get light the ground. Twelve lights a zone is
		-- already more than the biome dressing uses.
		local glow = Instance.new("PointLight")
		glow.Color = ringColor
		glow.Range = tier.size * 1.6
		glow.Brightness = 1.6
		glow.Parent = ring
	end

	if tierName == "Elite" then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(ringColor)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new(tier.size * 0.06)
		sparkle.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Rate = 7
		sparkle.Speed = NumberRange.new(1, 2.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = body
	end

	-- ONE BOX ROUND THE WHOLE RIG, which is what the mouse actually hits.
	--
	-- It used to be two ClickDetectors, on the torso and on the head, and every other part of a rig
	-- was CanQuery = false so it could not swallow the ray. That works on a ball and fails on
	-- everything the rigs became: a Swarmer IS its head, a Brute is mostly horns, spikes, wings and
	-- paws, and on those the clickable region was a small block somewhere behind all of it. The
	-- complaint was exact -- on some creatures only the head answered.
	--
	-- Same fix BossService already uses. The box is the model's own bounding volume, so it fits the
	-- rig rather than a guess at it, with a margin on top: a target you have to be precise about is
	-- the wrong kind of difficulty in a game whose whole verb is clicking.
	-- ...AND CAPPED, which the `math.max` floor on its own is not.
	--
	-- `boxSize` is the model's bounding volume in the PrimaryPart's frame, and on a rig whose parts
	-- are placed at a yaw it comes back considerably wider than the creature actually is: a 6.1-stud
	-- Swarmer measured 13.3, so its hit box was built at 15.4 -- two and a half times the creature,
	-- overlapping its neighbours, so clicking one of a pair could answer for the other.
	--
	-- The generous margin is still deliberate (see above) -- a target you have to be precise about
	-- is the wrong difficulty for a game whose whole verb is clicking. It just has an upper bound
	-- now: no wider than 1.7 of the size the tier is authored at, whatever the box claims.
	local boxCF, boxSize = model:GetBoundingBox()
	local hitMin, hitMax = tier.size * 1.3, tier.size * 1.7
	local hitbox = Instance.new("Part")
	hitbox.Name = "HitBox"
	hitbox.Size = Vector3.new(
		math.clamp(boxSize.X * 1.16, hitMin, hitMax),
		math.clamp(boxSize.Y * 1.1, hitMin, hitMax),
		math.clamp(boxSize.Z * 1.16, hitMin, hitMax)
	)
	hitbox.CFrame = boxCF
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false -- it must never push the player around or block a pet's ground ray
	hitbox.CanTouch = false
	hitbox.CanQuery = true -- it exists precisely to catch the mouse ray
	hitbox.CastShadow = false
	hitbox.Parent = model
	-- measured against the BODY, because that is the frame driveCreatures poses everything from
	local hitboxOffset = body.CFrame:ToObjectSpace(boxCF)

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = clickReach
	clickDetector.Parent = hitbox

	-- ===== AUTO-ATTACK REACHES FURTHER THAN A CLICK, AND NOW IT HAS TO =====
	--
	-- "Auto-attack does not work at all" was measured, not a bug: the wiring is fine end to end (a
	-- 70 HP Brute died in two seconds once something was in range), but the floor was 34 studs
	-- centre-to-centre and the nearest creature to the Forest spawn is 109. It simply never found a
	-- target during ordinary play, and it says nothing when it does not, so it read as dead.
	--
	-- The floor is 60 now and tracks the client's AUTO_REACH.Creatures exactly -- keep the two in
	-- step, or the server accepts blows an honest client can never nominate, which is the difference
	-- between a generous feature and a hole. `+ tier.size` is slack for the body, not extra range:
	-- the client measures to the model's centre and the server to the body part's.
	--
	-- Deliberately looser than the click reach, and more so than before, because the two are now
	-- different controls. A click is aimed and should be melee (see clickReach); an auto-attack is
	-- the convenience feature and is meant to pick up whatever you walk past.
	--
	-- Resulting reach: Swarmer 66.5, Critter 71, Brute 76, Elite 86.
	--
	-- 15.21 restored this from `math.max(clickReach + 3, 22) + tier.size * 0.35`. That floor was
	-- BELOW the player's own half-width (15.4 studs at max stage) plus the creature's, so the server
	-- would have refused blows a player could see land -- and the client, cut to 22 in the same pass,
	-- could not nominate them in the first place. Both halves are back at 60.
	local autoReach = math.max(clickReach + 4, 60) + tier.size

	model:SetAttribute("Health", tier.health)
	-- ===== WHAT THE CLIENT IS ALLOWED TO KNOW ABOUT THIS CREATURE (11.6) =====
	--
	-- Until now `Health` was the only attribute on a creature, and a client genuinely could not tell
	-- a terrace Brute from a valley Brute -- same model name, same rig, same tier -- except by
	-- comparing world Y against terrain it cannot see. So the lock could not be drawn at all.
	--
	-- These two are replicated state, not a decision: `MinRebirths` is the number the client compares
	-- against its own save to grey the plate and drop the creature from auto-attack, and the server
	-- re-derives the same answer from `raised` in `onHit` without ever reading them back. Publishing
	-- them tells an exploiter only what the plate above the creature's head already says.
	--
	-- `PlateName` is the third, and it exists because of a bug the first version of the client paint
	-- shipped with. That code read the plate's CURRENT text to remember the creature's name before
	-- overwriting it with the lock line -- and under streaming the plate goes away and comes back, so
	-- the remembering happened again on text that had already been decorated. The label grew a fresh
	-- padlock every pass: measured at 34 of them on one Apex. Publishing the pristine name makes the
	-- repaint idempotent by construction rather than by being careful.
	local raisedLayer = GameConfig.GetRaisedLayer(raised)
	if raisedLayer then
		model:SetAttribute("Raised", raised)
		model:SetAttribute("MinRebirths", raisedLayer.minRebirths)
		model:SetAttribute("PlateName", tier.label)
	end
	model.Parent = creaturesFolder

	-- gentle idle bob + sway so creatures read as alive instead of frozen statues.
	-- On top of that whole-body motion each attachment animates around its OWN joint:
	-- the wave goes BETWEEN pivot and rest, so a leg swings from the hip instead of
	-- spinning around its own middle. `orbit` is the one continuous kind -- it ignores
	-- amp and revolves at `speed` (signed, so counter-rotating rings read as two shells).
	registerCreature(model, body, position, attachments, tier.size, homeYaw, tierName, ring, zone.offset, hitbox, hitboxOffset, floorY)

	local lastHitByPlayer = {}
	local dead = false
	local auraConnection

	if tier.auraRange and tier.auraRange > 0 then
		local lastAuraHit = {}
		local accum = 0
		auraConnection = RunService.Heartbeat:Connect(function(dt)
			if dead or not model.Parent then return end
			accum += dt
			if accum < tier.auraInterval then return end
			accum = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				local character = plr.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - body.Position).Magnitude <= tier.auraRange then
					-- an aura ticks on a timer whether or not you are fighting, so it is held to a
					-- much tighter share than a retaliation: standing next to something must cost
					-- less than trading blows with it
					hurtPlayer(plr, math.random(tier.auraDamage[1], tier.auraDamage[2]), (tier.minHits or 4) * 6)
					local rig = live[model]
					if rig then rig.lungeUntil = os.clock() + LUNGE_TIME end
				end
			end
		end)
	end

	-- how long the plate is still allowed to draw through walls after the last blow
	local plateHotUntil = 0

	-- the one place the plate is written, so a hit and a regen tick can never disagree about it
	local function drawHealth(health)
		barFill.Size = UDim2.new(math.clamp(health / tier.health, 0, 1), 0, 1, 0)
		barLabel.Text = shortNumber(health) .. " / " .. shortNumber(tier.health)
	end

	-- ===== THE TWO PATHS ARE GATED SEPARATELY NOW =====
	--
	-- This used to be one figure (`strikeReach = autoReach`) on the reasoning that the server cannot
	-- tell a click from an auto-attack and must not refuse a legitimate one of either. That was true
	-- of the old code and it is what made tightening the click impossible: `MaxActivationDistance`
	-- is enforced on the CLIENT, so a modified one could still land a click from auto-attack range.
	--
	-- The server can tell them apart -- they arrive through two different doors. `MouseClick` calls
	-- `onHit(player)`; the AutoAttack remote calls `entry.fn(player, true)`. So the flag is passed
	-- rather than inferred, and each door is held to its own reach. A click now has to be melee on
	-- an honest client AND on a modified one.
	--
	-- `+ 6` is float/lag slack on the click gate: the client checks activation distance a frame or
	-- two before the server measures it, and a player walking backwards out of range must not have
	-- an honest click swallowed.
	local clickGate = clickReach + 6
	local autoGate = autoReach

	local function onHit(player, viaAuto)
		if dead or not model.Parent then return end
		-- A DEAD PLAYER DOES NOT SWING, AND NEITHER DOES ONE ACROSS THE ZONE.
		--
		-- Both of these were true of auto-attack alone. The click path arrives through a
		-- ClickDetector, and a ClickDetector's MaxActivationDistance is enforced on the CLIENT --
		-- so the server had never once asked how far away the player was, nor whether they were
		-- alive. A corpse could keep farming the creature that killed it, and a click could be
		-- made to land from anywhere on the strip.
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp) or humanoid.Health <= 0 then return end
		if (hrp.Position - body.Position).Magnitude > (viaAuto and autoGate or clickGate) then return end
		local data = PlayerDataService.Get(player)
		if not data then return end

		-- ===== THE REBIRTH GATE, AND THIS IS THE REAL ONE (11.6) =====
		--
		-- The client greys these creatures out and drops them from auto-attack, and none of that is
		-- authoritative -- the click path arrives through a ClickDetector whose reach is enforced
		-- client-side, so a hand-fired remote reaches this line with no UI involved at all. Same
		-- split, and same reasoning, as the rebirth shrine: the paint is a courtesy, this is the
		-- check. `CanFightRaised` is the one predicate both sides ask.
		--
		-- Refused BEFORE the hit cooldown is stamped, so a locked creature does not silently put the
		-- player on cooldown against the one standing next to it.
		if not GameConfig.CanFightRaised(data, raised) then
			local layer = GameConfig.GetRaisedLayer(raised)
			local last = lockNoticeAt[player.UserId]
			-- one line every few seconds, not one per swing: auto-attack would otherwise fire this
			-- at the tick rate for as long as the player stood there
			if layer and (not last or os.clock() - last > LOCK_NOTICE_COOLDOWN) then
				lockNoticeAt[player.UserId] = os.clock()
				Remotes.Notify:FireClient(player, { kind = "error", message =
					("%s is sealed -- it takes %d %s to touch it"):format(
						tier.label, layer.minRebirths, layer.minRebirths == 1 and "rebirth" or "rebirths") })
			end
			return
		end

		local now = os.clock()
		if lastHitByPlayer[player.UserId] and now - lastHitByPlayer[player.UserId] < tier.hitCooldown then
			return
		end
		lastHitByPlayer[player.UserId] = now

		-- THE REAL NUMBER, UNCLAMPED. This used to be `math.min(..., tier.damageCap)`, and that
		-- single `min` was the whole "evolving does nothing" report: the cap is `tier.health /
		-- minHits`, which in Forest is 4 on a Swarmer and 7 on a Critter -- and a brand new stage-1
		-- save already hit for more than that on its first click. So every player, from their first
		-- swing to their hundredth evolve, saw the same two numbers, and the FX below drew the cap
		-- because the cap WAS the damage. See the DAMAGE LADDER block in GameConfig.
		local playerDamage = DNAService.GetCombatDamage(data)
		local health = math.max((model:GetAttribute("Health") or tier.health) - playerDamage, 0)
		model:SetAttribute("Health", health)
		drawHealth(health)

		-- register (or re-arm) the regeneration above. Entered on every blow rather than only on the
		-- first, because `lastHit` is what holds the healing off while the fight is still going on.
		if health > 0 then
			local entry = hurt[model]
			if entry then
				entry.hp = health
				entry.lastHit = now
			else
				-- `plate` so the regen loop can hold the bar above the scenery while it climbs --
				-- see the note over REGEN_DELAY for why healing was invisible without it
				hurt[model] = { max = tier.health, hp = health, lastHit = now, draw = drawHealth, plate = billboard }
			end
		end

		-- In a fight the plate goes on top of everything. Out of one it does not: 520 creatures each
		-- drawing a name through the scenery is a wall of labels, and the whole point of the bar is
		-- that it tells you about the thing you are hitting.
		billboard.AlwaysOnTop = true
		plateHotUntil = now + 5
		task.delay(5.05, function()
			if billboard.Parent and os.clock() >= plateHotUntil then
				billboard.AlwaysOnTop = false
			end
		end)

		-- which way the blow came from, flattened onto the ground plane: it aims the flinch, the
		-- death tumble and the spark, and a knock with a vertical component throws a corpse at the sky
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local knockDir = Vector3.new(0, 0, 1)
		if hrp then
			local flat = Vector3.new(body.Position.X - hrp.Position.X, 0, body.Position.Z - hrp.Position.Z)
			if flat.Magnitude > 0.1 then
				knockDir = flat.Unit
			end
		end

		local rig = live[model]
		if rig then rig.hitUntil = now + HIT_TIME end
		flashHit(model)

		-- punch feedback tweens off the rig's OWN body size. It used to hardcode a
		-- tier.size cube, which was right when every creature was a sphere -- against a
		-- rig torso that squashed it into a cube on the first hit and never came back.
		TweenService:Create(body, TweenInfo.new(0.06), { Size = bodyBaseSize * 1.12 }):Play()
		task.delay(0.06, function()
			-- `dead` matters here: playDeath shrinks the whole model with ScaleTo, and a restore tween
			-- landing mid-collapse pops the torso back to full size inside the death animation
			if body and body.Parent and not dead then
				TweenService:Create(body, TweenInfo.new(0.09), { Size = bodyBaseSize }):Play()
			end
		end)

		local impact = body.Position + Vector3.new(0, tier.size * 0.3, 0) - knockDir * (tier.size * 0.35)

		-- retaliation: tougher creatures can hit back when attacked
		if health > 0 and tier.retaliateChance > 0 and math.random() < tier.retaliateChance then
			-- held to the tier's own hit floor: the fight it forces has to be survivable
			hurtPlayer(player, math.random(tier.retaliateDamage[1], tier.retaliateDamage[2]), tier.minHits)
			if rig then rig.lungeUntil = os.clock() + LUNGE_TIME end
		end

		if health > 0 then
			broadcastFx({
				k = "hit",
				p = impact,
				d = math.floor(playerDamage + 0.5),
				a = player.UserId,
				s = tier.size,
				c = ringColor,
				n = knockDir,
			})
		else
			dead = true
			if auraConnection then auraConnection:Disconnect() end
			-- ===== THE TERRACE MULTIPLIER (11.6) =====
			--
			-- The one place in the kill path where WHERE a creature stands changes what it pays. Note
			-- what this is not: it is not the generation ramp, which deliberately pays nothing extra
			-- for a creature you have killed before (see the header over `spawnCreature`). This pays
			-- for a gate -- a climb, and now a rebirth that cost the player their entire run -- and a
			-- gate you have to pay to pass is the opposite of an auto-increment.
			local layer = GameConfig.GetRaisedLayer(raised)
			local layerDna = layer and layer.dnaMult or 1
			local layerXp = layer and layer.xpMult or 1

			-- THE SECOND RETURN IS THE CRIT, AND IT WAS THROWN AWAY HERE (15.14).
			-- `GetClickAmount` rolls `clamp(5 + luck * 0.5, 0, 75)` percent for a **x5** payout, and
			-- this line took only the number. The one place in the game that announced a crit was
			-- `DNAService.HandleClick`, behind `Remotes.CollectClick` -- which nothing has fired for
			-- as long as combat has paid the DNA (see 15.12), so `MainUI`'s `kind == "crit"` toast
			-- and `SoundLibrary`'s crit row have both been unreachable the whole time. A player can
			-- buy Luck up to a 75% crit rate and never once be told a crit happened.
			local amount, wasCrit = DNAService.GetClickAmount(data)
			amount = amount * tier.dnaMult * layerDna
			data.DNA += amount
			data.XP = (data.XP or 0)
				+ math.max(1, math.floor(tier.xp * layerXp * GameConfig.GetXPMult(data)))

			-- DIAMONDS, THE ONLY GAMEPLAY SOURCE THERE IS. Every other one is a time gate (daily,
			-- playtime, Season Pass) or a Robux product whose id is still 0. Odds are per tier and
			-- live in GameConfig.DiamondDropChance -- see the note there for how they were sized.
			--
			-- Rolled and credited BEFORE the PushToClient below, on purpose: that push carries the
			-- whole save down and is happening anyway, so the diamond rides out on it instead of
			-- costing a second replication on the most frequent event in the game.
			local gems = GameConfig.RollDiamondDrop(tierName)
			if gems > 0 then
				data.Diamonds = (data.Diamonds or 0) + gems
			end

			-- EVOLUTION SHARDS, AND ONLY FROM UP HERE (9.4). `raised` is the flag the spawner set on
			-- the cliff-dwellers; RollShardDrop returns 0 for anything without it, so a creature on
			-- the valley floor never pays one however long it is farmed. That is the whole mechanic:
			-- the terraces are the only place in the game that mints this currency, so the climb the
			-- shelves were built for finally has something on the other end of it.
			--
			-- Credited beside the diamond and for the same reason -- it rides out on the PushToClient
			-- below rather than costing a second replication on the most frequent event in the game.
			local shards = GameConfig.RollShardDrop(tierName, raised)
			if shards > 0 then
				data.EvolutionShards = (data.EvolutionShards or 0) + shards
			end

			-- ===== AND THE ROOM IS TOLD, IF THIS WAS AN APEX (12.14) =====
			--
			-- Here rather than at the death a few lines up, because this is the site that already
			-- holds everything the line needs -- the tier, the zone and the label -- and because the
			-- pet the next block may hand over is the other half of the same moment.
			--
			-- Nothing is decided here on purpose: whether an Apex is worth announcing, how often one
			-- player may do it, and what the words are all live in AnnounceService, which is the
			-- whole reason that module exists. This call site only knows that an Apex died.
			if tierName == "Apex" then
				AnnounceService.ApexKilled(player, creatureLabel(tierName, zone), zone)
			end

			-- ===== AND A PET, WHICH ONLY THE SHELVES DROP (11.6) =====
			--
			-- The second thing the terraces mint that nothing else does. Layer 1 pays one of the
			-- zone's ordinary five; the layer-2 Apex pays the species that is in no egg -- see
			-- GameConfig's ExclusivePetsByZone. `GrantPetFromDrop` owns the chance, the pool and the
			-- cap, so this call site cannot disagree with the egg paths about any of them.
			--
			-- Rolled here beside the diamond and the shard, and for the same reason: it rides out on
			-- the PushToClient a few lines below instead of costing its own replication.
			--
			-- A FULL BAG DROPS THE PET RATHER THAN THE KILL. The DNA, XP and shard above are already
			-- credited by this point; unwinding them would be far worse than missing one drop, and
			-- refusing the kill outright would mean a full inventory made a creature invincible. The
			-- player is told, once, because a silent loss of the rarest item in the game is the kind
			-- of thing that reads as a bug.
			local droppedPet, dropFail = PetService.GrantPetFromDrop(data, zone.key, raised)
			if droppedPet then
				-- ITS OWN KIND, NOT `pet`. The first cut sent the hatch payload with `auto = true`,
				-- on the reasoning that auto means "the quiet presentation". It does not: it means
				-- "play the EGG sequence instead of the full-screen one", and HatchReveal duly
				-- shakes an egg on a podium in the zone's shop -- several hundred studs from the
				-- terrace where the kill happened, on an egg nobody bought. Measured live: a drop
				-- produced no visible feedback whatsoever where the player was standing. `petDrop`
				-- is drawn by MainUI on the player, like a fusion. See the note there.
				Remotes.Notify:FireClient(player, {
					kind = "petDrop",
					key = droppedPet.key,
					name = droppedPet.name,
					emoji = droppedPet.emoji,
					rarity = droppedPet.rarity,
					exclusive = droppedPet.exclusive == true,
				})
				AnnounceService.PetObtained(player, droppedPet, "DROP")
			elseif dropFail == "full" then
				Remotes.Notify:FireClient(player, { kind = "error",
					message = "A pet dropped and your inventory is full -- release or fuse one!" })
			end

			-- CHARACTERS COME FROM FIGHTING NOW. One per evolve could never keep up with the stage --
			-- twenty evolves against a hundred characters -- so a stage's list is finished by playing
			-- that stage instead. RollCharacter is the same ordered hand-over the evolve uses and it
			-- pushes its own notification; it returns nil once everything up to the player's stage is
			-- complete, which costs one table walk and nothing else.
			--
			-- Placed with the diamond roll and for the same reason: it rides out on the PushToClient
			-- below rather than costing a second replication on the most frequent event in the game.
			-- THE STAGE YOU ARE STANDING AT, NOT THE LOWEST INCOMPLETE ONE.
			--
			-- GetCollectionStage returns the lowest stage still missing a character, which was right
			-- when characters came from evolving. Against the evolve gate it DEADLOCKS: the gate asks
			-- "is stage N complete" while the drops fill stage 1, so a save with a hole anywhere below
			-- N can never open the gate at N. That is exactly what a save carrying leftovers from the
			-- old base-character rule looks like -- Cell 2/5, Bacteria 1/5, Worm 1/5, standing at Worm
			-- and gated on Worm while every drop went to Cell.
			--
			-- Targeting the current stage makes the two rules one rule: the gate guarantees you cannot
			-- BE at stage N until N-1 is complete, so filling N is filling them in order by
			-- construction -- and it heals an old save instead of being trapped by it.
			-- NO CHARACTER DROP HERE ANY MORE. Skins are evolves now (GameConfig.GetEvolveStep):
			-- a kill that handed one over would either skip a step the player is paying DNA and XP
			-- for, or arrive at a stage whose list is already complete and do nothing at all.
			-- What a kill pays is DNA, XP, the diamond roll above and Season quest progress.
			-- Season quest progress. Deliberately placed BEFORE the push below: this is the most
			-- frequent event in the game and Track does not replicate on its own, so the counter
			-- rides out on the push that was happening anyway.
			SeasonPassService.Track(player, "creatures", 1)
			-- Lifetime kill count, for the global leaderboard (5.3). Placed with the Season counter and
			-- for the same reason: it is a single integer add on the most frequent event in the game and
			-- it rides out on the PushToClient below rather than costing its own replication.
			-- Deliberately NOT reset by a rebirth -- a lifetime board that a rebirth zeroed would rank
			-- players by how recently they reset rather than by how much they have played.
			data.Kills = (data.Kills or 0) + 1
			-- ...and if that XP filled the bar, evolve NOW rather than waiting for a button press
			-- (10.10). Placed before the push below so the payload the client receives already carries
			-- the new rung -- otherwise the HUD would draw the old one for a frame and then correct
			-- itself, which reads as a flicker on the most important moment in the game. HandleEvolve
			-- pushes and celebrates on its own; this does nothing at all when the bar is not full,
			-- which is the overwhelmingly common case.
			DNAService.AutoEvolveIfReady(player)
			PlayerDataService.UpdateLeaderstats(player)
			PlayerDataService.PushToClient(player)
			Remotes.Notify:FireClient(player, { kind = "creature", amount = math.floor(amount) })
			if gems > 0 then
				Remotes.Notify:FireClient(player, { kind = "diamond", amount = gems })
			end

			broadcastFx({
				k = "kill",
				p = impact,
				d = math.floor(playerDamage + 0.5),
				dna = math.floor(amount),
				a = player.UserId,
				s = tier.size,
				c = ringColor,
				n = knockDir,
				-- The shard is DRAWN WHERE IT WAS EARNED and gets no HUD toast (the diamond has one,
				-- and this is the exception on purpose): a crystal that tears out of the creature and
				-- flies into you says both what dropped and what killed it, and a banner in the corner
				-- of the screen says only the first. `sh` reaches every client inside FX range but only
				-- the killer's draws it -- the same `mine` test the DNA pop already uses -- and it is
				-- nil on the ordinary kill, so the commonest payload in the game is not a field wider
				-- for everybody.
				sh = shards > 0 and shards or nil,
				-- ...and the crit rides the same payload, for the same reason the shard does: it is
				-- a fact about THIS kill, so it belongs on the number already being drawn over the
				-- corpse rather than in a banner in the corner. It is `nil` on an ordinary kill, so
				-- the commonest packet in the game does not grow a field for everybody.
				cr = wasCrit or nil,
			})

			playDeath(model, rig, tier.size, knockDir, ringColor)
			task.delay(tier.respawnDelay, function()
				-- one clearance older, so the next one standing here is a little harder to put down
				spawnCreature(position, tierName, zone, raised, (generation or 0) + 1)
			end)
		end
	end

	-- Wrapped rather than connected directly, so the `viaAuto` flag can only ever be false here:
	-- MouseClick's own signature is (player), which would leave the second argument nil and take the
	-- click gate by accident rather than on purpose. It is the tighter of the two gates -- an
	-- accident in the other direction would be a silent hole.
	clickDetector.MouseClick:Connect(function(player)
		onHit(player, false)
	end)
	-- and the same function, reachable by name, for the auto-attack remote. Both paths land in
	-- exactly one place, so the cooldown, the retaliation, the DNA and the death are identical
	-- whether the player clicked or the loop did -- only the reach they are held to differs.
	hitHandlers[model] = { fn = onHit, body = body, reach = autoReach }

	return model
end

-- ===== WHERE THE CLIFF DWELLERS STAND =========================================
--
-- Found rather than declared. The terraces are cut per zone with a meandering inner edge and a
-- per-zone tier count and rise (ZoneBuilder's `edges` / TERRAIN_PROFILE), so there is no table of
-- shelf coordinates to read and copying the generator here would be a second copy to keep in step.
-- Sampling the band with the same downward ray everything else uses costs a few hundred rays once
-- at boot and cannot drift out of agreement with the terrain, because it IS the terrain.
-- ===== WHO STANDS WHERE, AND IN WHICH ORDER (11.6) =====
--
-- `raisedSpots` returns its shelves sorted DESCENDING BY ALTITUDE, so this list is also the
-- allocation order: whatever is written first gets the highest ground there is. The Apexes are
-- therefore first, which is what makes "the new higher points" of the rebirth ladder literally
-- higher rather than just differently labelled -- you can see them from the valley floor and cannot
-- reach them for three rebirths.
--
-- That does move the Elites down: they used to take shelves 1-4 and now take 5-8. The shelves are
-- the same shelves and the Elites are still above every Brute; only the four best in each zone
-- changed hands. 14 raised creatures a zone now against 10, and `raisedSpots` samples up to 24, so
-- there is still slack for a zone whose terraces are awkward.
local RAISED_LAYOUT = {
	{ tier = "Apex",  count = 4, layer = 2 },
	{ tier = "Elite", count = 4, layer = 1 },
	{ tier = "Brute", count = 6, layer = 1 },
}
-- ...and the moment both lists exist, hand them to GameConfig so the two drop tables can be checked
-- against what this file REALLY spawns (11.31). It has to happen from here: GameConfig is required
-- by this file, so it cannot reach back for `TIERS` without a cycle -- which is precisely how the
-- Apex ended up in every spawn loop and in neither drop table. See GameConfig.AssertTierCoverage.
do
	local all, raisedTiers = {}, {}
	for name in pairs(TIERS) do all[#all + 1] = name end
	for _, band in ipairs(RAISED_LAYOUT) do raisedTiers[#raisedTiers + 1] = band.tier end
	GameConfig.AssertTierCoverage(all, raisedTiers)
end

-- inside the band (TERRAIN_INNER is 415) and inside the spawn keep-out's own 575 edge limit
local RAISED_IN, RAISED_OUT = 432, 566
local FLAT_PROBE = { Vector2.new(13, 0), Vector2.new(-13, 0), Vector2.new(0, 13), Vector2.new(0, -13) }

local function raisedSpots(zone)
	-- Its own generator, seeded off the zone, rather than SPAWN_RNG -- that one is consumed at
	-- module load and drawing from it here would make the layout depend on when Init happened. Two
	-- servers of the same place have to lay their creatures out identically.
	local rng = Random.new(20260809 + math.floor(zone.offset))
	local found, guard = {}, 0

	while #found < 24 and guard < 1500 do
		guard += 1
		local rel = (rng:NextInteger(1, 2) == 1 and -1 or 1) * rng:NextNumber(RAISED_IN, RAISED_OUT)
		local z = rng:NextNumber(-470, 470)
		if insideKeepOut(rel, z) then continue end

		local x = zone.offset + rel
		local y, on = floorAt(x, z, 0)
		-- 12 is above anything the valley floor does to itself (a pool lip, a ground patch) and below
		-- the shortest terrace rise in the game, which is 20. Under it, this point is not on a shelf.
		if y < 12 then continue end

		-- IT HAS TO BE A SHELF, AND NOTHING ELSE WILL DO. Height plus flatness is not enough, and
		-- the first run proved it: of 202 raised creatures, 14 came out standing on the CAP OF A ROCK
		-- SPIRE, on a boulder, or in the middle of a staircase. A 40-stud crag base passes a flatness
		-- probe taken at 13 studs perfectly well -- it is genuinely flat, it is simply not a floor --
		-- and a creature balanced on a spire is exactly the "why is that up there" this whole pass
		-- exists to remove. Naming the one part that IS the tread cannot be fooled by any of them.
		if not (on and on.Name == "TerraceTop") then continue end

		-- and there has to be enough of it to stand on. The treads run 30 to 54 studs deep and a rig
		-- set down at the lip is half out over the drop, so all four sides are probed at 13 studs --
		-- half an Elite, which is the widest thing sent up here.
		local flat = true
		for _, d in ipairs(FLAT_PROBE) do
			if math.abs(floorAt(x + d.X, z + d.Y, -999) - y) > 1.5 then
				flat = false
				break
			end
		end
		if not flat then continue end

		-- NOT ON THE STAIRS. The flight is the only way onto the shelf, and its top steps ARE at
		-- tread height, so a spot at the head of one passes every test above and then parks an Elite
		-- across the single route up. Named rather than inferred, and queried only for a candidate
		-- that has already survived everything else -- roughly thirty times a zone, once at boot.
		local onStairs = false
		for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(x, y, z), Vector3.new(64, 40, 64))) do
			if part.Name == "TerraceRamp" then
				onStairs = true
				break
			end
		end
		if onStairs then continue end

		-- Tested here as well as in spawnCreature, and that is not belt-and-braces. clearOfScenery
		-- walks a blocked point up to 110 studs sideways to get it out of a boulder or off a ramp,
		-- which from a 30-to-54-stud tread is easily far enough to walk it clean off the shelf --
		-- and the ground query afterwards would then honestly report the valley floor. Rejecting the
		-- spot outright and taking the next one keeps the creature up where it was put.
		local x2 = zone.offset + rel
		if blockedAt(x2, y + 26 * 0.56, z, 26) then continue end

		local clear = true
		for _, p in ipairs(found) do
			if (Vector2.new(rel, z) - Vector2.new(p.rel, p.z)).Magnitude < 90 then
				clear = false
				break
			end
		end
		if clear then
			table.insert(found, { rel = rel, z = z, y = y })
		end
	end

	-- Highest first, and that ordering is the whole feature: the Elites take the top shelf and the
	-- Brutes the ones under them, so the danger climbs with the altitude and is legible from the
	-- valley floor before you are anywhere near it. Ties broken on z so the sort is stable -- whole
	-- shelves are exactly level with each other and there are a lot of ties.
	table.sort(found, function(a, b)
		if a.y == b.y then return a.z < b.z end
		return a.y > b.y
	end)
	return found
end

function CreatureService.Init()
	for _, existing in ipairs(creaturesFolder:GetChildren()) do
		existing:Destroy()
	end
	table.clear(live)
	-- again here, not only at require time: the Bosses and EquippedPets folders are created by
	-- modules whose bodies run after this one's, and a respawn an hour later must not read a boss
	-- or somebody's pet as a rock to walk out of
	refreshSceneryFilter()
	ensureOutlinePool()
	-- Fixed order rather than pairs(): a Lua table's iteration order is not stable, and the spawn
	-- order decides which rigs land in the Creatures folder first -- worth keeping deterministic
	-- so two servers of the same place look the same.
	for _, zone in ipairs(GameConfig.Zones) do
		-- Resolved here and not at module load, because it needs the terrain to be standing:
		-- ZoneBuilder.Build() runs before CreatureService.Init (see ServerMain).
		-- `spots`, not `raised`: since 11.6 `raised` is a layer number carried on a creature, and
		-- having the shelf list share the name three lines from the call that consumes it was one
		-- rename away from a very quiet bug.
		local spots = raisedSpots(zone)
		local taken = 0

		for _, tierName in ipairs({ "Swarmer", "Critter", "Brute", "Elite" }) do
			for _, rel in ipairs(RELATIVE_SPAWN_POINTS[tierName] or {}) do
				-- The Y column in the table is ignored, and so is the one passed here: spawnCreature
				-- asks the ground how high it is once the point is final. Every rig reaches about half
				-- its size below the body centre, which is where the 0.56 comes from.
				local pos = Vector3.new(zone.offset + rel.X, TIERS[tierName].size * 0.56, rel.Z)
				spawnCreature(pos, tierName, zone)
			end
		end

		-- ...and then the cliffs, highest shelf first -- see RAISED_LAYOUT for the order and why the
		-- Apexes are at the top of it.
		for _, band in ipairs(RAISED_LAYOUT) do
			local tierName = band.tier
			for _ = 1, band.count do
				taken += 1
				local spot = spots[taken]
				-- A zone whose shelves are all too narrow or too full of boulders simply gets fewer
				-- creatures up high. Backfilling onto the valley floor is the wrong answer: those
				-- points are already claimed, and two Elites in one spot is worse than one missing.
				if not spot then break end
				-- ...and `band.layer` is what makes this creature able to drop an Evolution Shard, pay
				-- its multiplier and refuse a player who has not rebirthed enough. It is the only
				-- difference between the two spawn loops in this function.
				spawnCreature(
					Vector3.new(zone.offset + spot.rel, spot.y + TIERS[tierName].size * 0.56, spot.z),
					tierName, zone, band.layer)
			end
		end
	end

	-- the one loop that poses every creature; without it they stand frozen in their build pose
	RunService.Heartbeat:Connect(driveCreatures)

	AutoAttack.OnServerEvent:Connect(function(player, model)
		if typeof(model) ~= "Instance" then return end
		local entry = hitHandlers[model]
		-- not a creature this server is holding a handler for -- a stale model, a boss (BossService
		-- listens on the same remote for its own), or something the client made up
		if not entry or not entry.body.Parent then return end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		if (hrp.Position - entry.body.Position).Magnitude > entry.reach then return end
		-- `true` = this arrived by auto-attack, so onHit measures against the loose gate rather than
		-- the melee one a click is held to. Without it every auto-attack past ~26 studs is silently
		-- dropped by the server and the feature looks dead again.
		entry.fn(player, true)
	end)
end

return CreatureService

