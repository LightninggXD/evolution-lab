-- GameConfig.Zones -- the 20 zones, their bosses, where a boss stands, boss revive and the zone lookup helpers.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== ZONES =====
-- unlockStageIndex: player must have reached this GameConfig.Stages index to unlock the zone
-- offset: X position offset (studs) along the zone road, each platform is 260 studs wide
-- incomeBonusPct: permanent % income bonus granted once the zone is unlocked (cumulative)
-- mobHealthMult/mobDamageMult/mobDnaMult: how much stronger (and more rewarding) regular
-- creatures in this zone are compared to Forest baseline -- creatures get tougher zone by zone.
-- requiresBossKey: the PREVIOUS zone's boss must be defeated (by this player) before this zone
-- unlocks, on top of reaching unlockStageIndex -- this is what gates progression on boss kills.
-- ZONE SPACING IS A FUNCTION OF HOW WIDE A ZONE ACTUALLY IS. It was 630 when a platform was 450
-- studs wide (a 180-stud gap between them). The platforms were later widened to 700 x 860 and this
-- number was never moved with them -- so from Desert onward every platform OVERLAPPED its
-- neighbour by 70 studs of floor, and the zone MODELS (which run ~1030 studs wide once the rock
-- rampart and the two rows of backdrop mesas behind each wall are counted) overlapped by ~400.
--
-- Everything that looked broken about the boundaries came from that one number:
--   * the next zone's backdrop mesas stood on this zone's platform, and they are CanCollide = false
--     -- so a player walked straight through what looks like a solid white cliff;
--   * creature spawn points out near |x| = 300 landed inside those mesas: a monster in a wall;
--   * two zones' walls, ramparts and mesas interpenetrated, which is what the map reads as from
--     the air.
--
-- The platform was then widened 700 -> 900 (there was finally room for it), which takes the zone
-- model to ~1230. 1500 clears that with ~270 studs of daylight between neighbours. The strip is
-- longer for it (0 -> 28,500) and that costs nothing: travel between zones is a teleport through
-- ZoneService, and StreamingEnabled means a client only ever holds the zone it is standing in.
-- If a platform is ever widened again, this has to move with it.
GameConfig.ZoneSpacing = 1900
-- 20 zones total, one per evolution stage (zone i unlocks at stage i). Zones 10-20 continue
-- the cosmic/abstract escalation started by Galaxy/BlackHole/Multiverse.
GameConfig.Zones = {
	{ key = "Forest",          name = "Forest",            emoji = "🌲", unlockStageIndex = 1,  offset = 0,          groundColor = Color3.fromRGB(74, 140, 74),   accentColor = Color3.fromRGB(40, 100, 40),   incomeBonusPct = 0,   mobHealthMult = 1.0,    mobDamageMult = 1.0,  mobDnaMult = 1.0,    requiresBossKey = nil },
	{ key = "Desert",          name = "Desert",            emoji = "🏜️", unlockStageIndex = 2,  offset = 1500,    groundColor = Color3.fromRGB(230, 200, 120), accentColor = Color3.fromRGB(190, 150, 80),  incomeBonusPct = 5,   mobHealthMult = 1.6,    mobDamageMult = 1.3,  mobDnaMult = 1.7,    requiresBossKey = "Forest" },
	{ key = "Ocean",           name = "Ocean",             emoji = "🌊", unlockStageIndex = 3,  offset = 3000,    groundColor = Color3.fromRGB(60, 140, 200),  accentColor = Color3.fromRGB(30, 90, 150),   incomeBonusPct = 10,  mobHealthMult = 2.4,    mobDamageMult = 1.6,  mobDnaMult = 2.6,    requiresBossKey = "Desert" },
	{ key = "Volcano",         name = "Volcano",           emoji = "🌋", unlockStageIndex = 4,  offset = 4500,    groundColor = Color3.fromRGB(60, 40, 40),    accentColor = Color3.fromRGB(220, 80, 30),   incomeBonusPct = 15,  mobHealthMult = 3.6,    mobDamageMult = 2.0,  mobDnaMult = 4.0,    requiresBossKey = "Ocean" },
	{ key = "Moon",            name = "Moon",              emoji = "🌙", unlockStageIndex = 5,  offset = 6000,    groundColor = Color3.fromRGB(170, 170, 175), accentColor = Color3.fromRGB(120, 120, 130), incomeBonusPct = 20,  mobHealthMult = 5.2,    mobDamageMult = 2.5,  mobDnaMult = 5.8,    requiresBossKey = "Volcano" },
	{ key = "Mars",            name = "Mars",              emoji = "🔴", unlockStageIndex = 6,  offset = 7500,    groundColor = Color3.fromRGB(190, 90, 60),   accentColor = Color3.fromRGB(140, 60, 40),   incomeBonusPct = 25,  mobHealthMult = 7.5,    mobDamageMult = 3.0,  mobDnaMult = 8.5,    requiresBossKey = "Moon" },
	{ key = "Galaxy",          name = "Galaxy",            emoji = "🌌", unlockStageIndex = 7,  offset = 9000,    groundColor = Color3.fromRGB(60, 40, 100),   accentColor = Color3.fromRGB(140, 90, 220),  incomeBonusPct = 35,  mobHealthMult = 11.0,   mobDamageMult = 3.7,  mobDnaMult = 12.5,   requiresBossKey = "Mars" },
	{ key = "BlackHole",       name = "Black Hole",        emoji = "⚫", unlockStageIndex = 8,  offset = 10500,  groundColor = Color3.fromRGB(10, 10, 12),    accentColor = Color3.fromRGB(80, 30, 120),   incomeBonusPct = 50,  mobHealthMult = 16.0,   mobDamageMult = 4.6,  mobDnaMult = 18.0,   requiresBossKey = "Galaxy" },
	{ key = "Multiverse",      name = "Multiverse",        emoji = "🌀", unlockStageIndex = 9,  offset = 12000,  groundColor = Color3.fromRGB(20, 20, 30),    accentColor = Color3.fromRGB(255, 100, 220), incomeBonusPct = 75,  mobHealthMult = 24.0,   mobDamageMult = 5.7,  mobDnaMult = 27.0,   requiresBossKey = "BlackHole" },
	{ key = "Nebula",          name = "Nebula",            emoji = "🌠", unlockStageIndex = 10, offset = 13500,  groundColor = Color3.fromRGB(120, 60, 160),  accentColor = Color3.fromRGB(180, 100, 220), incomeBonusPct = 100, mobHealthMult = 34.0,   mobDamageMult = 6.5,  mobDnaMult = 38.0,   requiresBossKey = "Multiverse" }, -- Rebirth Tier 2 zone
	{ key = "Wormhole",        name = "Wormhole",          emoji = "🕳️", unlockStageIndex = 11, offset = 15000,  groundColor = Color3.fromRGB(30, 30, 50),    accentColor = Color3.fromRGB(120, 80, 200),  incomeBonusPct = 130, mobHealthMult = 48.0,   mobDamageMult = 7.4,  mobDnaMult = 54.0,   requiresBossKey = "Nebula" },
	{ key = "QuantumRealm",    name = "Quantum Realm",     emoji = "⚛️", unlockStageIndex = 12, offset = 16500,  groundColor = Color3.fromRGB(40, 120, 140),  accentColor = Color3.fromRGB(80, 220, 220),  incomeBonusPct = 165, mobHealthMult = 68.0,   mobDamageMult = 8.4,  mobDnaMult = 76.0,   requiresBossKey = "Wormhole" },
	{ key = "TimeRift",        name = "Time Rift",         emoji = "⏳", unlockStageIndex = 13, offset = 18000,  groundColor = Color3.fromRGB(90, 70, 40),    accentColor = Color3.fromRGB(230, 190, 80),  incomeBonusPct = 205, mobHealthMult = 95.0,   mobDamageMult = 9.6,  mobDnaMult = 108.0,  requiresBossKey = "QuantumRealm" },
	{ key = "AntimatterZone",  name = "Antimatter Zone",   emoji = "💥", unlockStageIndex = 14, offset = 19500,  groundColor = Color3.fromRGB(60, 10, 10),    accentColor = Color3.fromRGB(255, 60, 60),   incomeBonusPct = 250, mobHealthMult = 135.0,  mobDamageMult = 11.0, mobDnaMult = 152.0,  requiresBossKey = "TimeRift" },
	{ key = "DreamDimension",  name = "Dream Dimension",   emoji = "💭", unlockStageIndex = 15, offset = 21000,  groundColor = Color3.fromRGB(70, 40, 100),   accentColor = Color3.fromRGB(200, 140, 255), incomeBonusPct = 300, mobHealthMult = 190.0,  mobDamageMult = 12.5, mobDnaMult = 215.0,  requiresBossKey = "AntimatterZone" }, -- Rebirth Tier 3 zone
	{ key = "MirrorUniverse",  name = "Mirror Universe",   emoji = "🪞", unlockStageIndex = 16, offset = 22500,  groundColor = Color3.fromRGB(150, 150, 170), accentColor = Color3.fromRGB(220, 220, 255), incomeBonusPct = 360, mobHealthMult = 265.0,  mobDamageMult = 14.2, mobDnaMult = 300.0,  requiresBossKey = "DreamDimension" },
	{ key = "VoidExpanse",     name = "Void Expanse",      emoji = "🌑", unlockStageIndex = 17, offset = 24000,  groundColor = Color3.fromRGB(5, 5, 10),      accentColor = Color3.fromRGB(140, 60, 220),  incomeBonusPct = 430, mobHealthMult = 375.0,  mobDamageMult = 16.2, mobDnaMult = 420.0,  requiresBossKey = "MirrorUniverse" },
	{ key = "CelestialThrone", name = "Celestial Throne",  emoji = "👑", unlockStageIndex = 18, offset = 25500,  groundColor = Color3.fromRGB(200, 180, 120), accentColor = Color3.fromRGB(255, 225, 140), incomeBonusPct = 510, mobHealthMult = 525.0,  mobDamageMult = 18.5, mobDnaMult = 590.0,  requiresBossKey = "VoidExpanse" },
	{ key = "Singularity",     name = "Singularity",       emoji = "💫", unlockStageIndex = 19, offset = 27000,  groundColor = Color3.fromRGB(15, 15, 20),    accentColor = Color3.fromRGB(255, 255, 255), incomeBonusPct = 600, mobHealthMult = 740.0,  mobDamageMult = 21.0, mobDnaMult = 830.0,  requiresBossKey = "CelestialThrone" },
	{ key = "AbsolutePlane",   name = "The Absolute Plane",emoji = "🔺", unlockStageIndex = 20, offset = 28500,  groundColor = Color3.fromRGB(255, 255, 255), accentColor = Color3.fromRGB(255, 215, 0),   incomeBonusPct = 700, mobHealthMult = 1050.0, mobDamageMult = 24.0, mobDnaMult = 1170.0, requiresBossKey = "Singularity" }, -- Rebirth Tier 4 zone (true endgame)
}

-- The offsets are written out per row because that is how the table reads at a glance, but the
-- SPACING is the thing that has to hold: one row edited by hand to a value that disagrees with
-- ZoneSpacing puts a platform inside its neighbour, and that is a bug you only ever see from the
-- air. Derived here so the two can never drift apart again -- the literals above are documentation.
for i, zone in ipairs(GameConfig.Zones) do
	zone.offset = (i - 1) * GameConfig.ZoneSpacing
	-- What one creature kill in this zone is worth in XP, against the Forest baseline. It is the
	-- SAME growth factor the per-level requirement uses, on purpose: that is what keeps
	-- kills-per-level flat from Forest to the Absolute Plane. Without it a Void Expanse Swarmer
	-- paid the same 1 XP a Forest one did, against a requirement 26,000 times larger.
	-- Deliberately NOT mobDnaMult: that curve is much steeper (1x -> 1170x) because it has to keep
	-- up with an exponential evolve COST, and XP is not spent on anything else.
	zone.mobXpMult = GameConfig.XpPerLevelGrowth ^ (i - 1)
end

-- ===== ZONE BOSSES =====
-- One boss guards the exit of every zone. A player must personally defeat a zone's boss
-- (in addition to reaching the next zone's unlockStageIndex) before the next zone opens for them.
-- Bosses respawn after being defeated so every player gets their own shot at them.
-- size: the rig UNIT, not a diameter -- BossService builds every part as a fraction of it, and a
-- finished rig stands roughly 1.5-2x this tall. At 18 the Forest bear is already five times a
-- player; the Absolute tops out near 120 studs, just under the 140-stud zone walls.
GameConfig.ZoneBosses = {
	Forest          = { name = "Alpha Bear",           emoji = "🐻", health = 500,     retaliateChance = 0.6,  retaliateDamage = {10, 18},    dnaReward = 300,     size = 18, respawnDelay = 40 },
	Desert          = { name = "Sand Wyrm",            emoji = "🐍", health = 1400,    retaliateChance = 0.62, retaliateDamage = {16, 26},    dnaReward = 900,     size = 20, respawnDelay = 42 },
	Ocean           = { name = "Kraken",               emoji = "🐙", health = 3200,    retaliateChance = 0.64, retaliateDamage = {22, 34},    dnaReward = 2200,    size = 22, respawnDelay = 44 },
	Volcano         = { name = "Magma Titan",          emoji = "🌋", health = 6800,    retaliateChance = 0.66, retaliateDamage = {30, 46},    dnaReward = 5200,    size = 24, respawnDelay = 46, auraRange = 12, auraDamage = {6, 10}, auraInterval = 1.5 },
	Moon            = { name = "Lunar Colossus",       emoji = "🌙", health = 13000,   retaliateChance = 0.68, retaliateDamage = {40, 60},    dnaReward = 11000,   size = 26, respawnDelay = 48, auraRange = 12, auraDamage = {8, 14}, auraInterval = 1.5 },
	Mars            = { name = "War Golem",            emoji = "🔴", health = 24000,   retaliateChance = 0.70, retaliateDamage = {55, 80},    dnaReward = 22000,   size = 28, respawnDelay = 50, auraRange = 13, auraDamage = {12, 18}, auraInterval = 1.4 },
	Galaxy          = { name = "Nebula Wraith",        emoji = "🌌", health = 44000,   retaliateChance = 0.72, retaliateDamage = {75, 110},   dnaReward = 42000,   size = 30, respawnDelay = 52, auraRange = 13, auraDamage = {16, 24}, auraInterval = 1.4 },
	BlackHole       = { name = "Void Devourer",        emoji = "⚫", health = 80000,   retaliateChance = 0.74, retaliateDamage = {100, 150},  dnaReward = 78000,   size = 33, respawnDelay = 55, auraRange = 14, auraDamage = {22, 32}, auraInterval = 1.3 },
	Multiverse      = { name = "Multiverse Sovereign", emoji = "🌀", health = 150000,  retaliateChance = 0.76, retaliateDamage = {140, 200},  dnaReward = 150000,  size = 36, respawnDelay = 60, auraRange = 15, auraDamage = {28, 40}, auraInterval = 1.3 },
	Nebula          = { name = "Nebula Devourer",      emoji = "🌠", health = 260000,  retaliateChance = 0.78, retaliateDamage = {170, 240},  dnaReward = 260000,  size = 38, respawnDelay = 62, auraRange = 15, auraDamage = {32, 46}, auraInterval = 1.2 },
	Wormhole        = { name = "Wormhole Horror",      emoji = "🕳️", health = 440000,  retaliateChance = 0.80, retaliateDamage = {200, 280},  dnaReward = 450000,  size = 40, respawnDelay = 64, auraRange = 16, auraDamage = {38, 54}, auraInterval = 1.2 },
	QuantumRealm    = { name = "Quantum Phantom",      emoji = "⚛️", health = 750000,  retaliateChance = 0.82, retaliateDamage = {240, 330},  dnaReward = 780000,  size = 42, respawnDelay = 66, auraRange = 16, auraDamage = {45, 64}, auraInterval = 1.1 },
	TimeRift        = { name = "Chronos Beast",        emoji = "⏳", health = 1250000, retaliateChance = 0.84, retaliateDamage = {290, 390},  dnaReward = 1300000, size = 44, respawnDelay = 68, auraRange = 17, auraDamage = {54, 76}, auraInterval = 1.1 },
	AntimatterZone  = { name = "Antimatter Horror",    emoji = "💥", health = 2100000, retaliateChance = 0.86, retaliateDamage = {350, 470},  dnaReward = 2200000, size = 46, respawnDelay = 70, auraRange = 17, auraDamage = {64, 90}, auraInterval = 1.0 },
	DreamDimension  = { name = "Nightmare Weaver",     emoji = "💭", health = 3500000, retaliateChance = 0.88, retaliateDamage = {420, 560},  dnaReward = 3700000, size = 48, respawnDelay = 72, auraRange = 18, auraDamage = {76, 106}, auraInterval = 1.0 },
	MirrorUniverse  = { name = "Mirror Tyrant",        emoji = "🪞", health = 5800000, retaliateChance = 0.90, retaliateDamage = {500, 660},  dnaReward = 6100000, size = 50, respawnDelay = 74, auraRange = 18, auraDamage = {90, 124}, auraInterval = 0.95 },
	VoidExpanse     = { name = "Void Colossus",        emoji = "🌑", health = 9600000, retaliateChance = 0.92, retaliateDamage = {590, 780},  dnaReward = 10000000, size = 52, respawnDelay = 76, auraRange = 19, auraDamage = {106, 146}, auraInterval = 0.9 },
	CelestialThrone = { name = "Throne Guardian",      emoji = "👑", health = 15800000,retaliateChance = 0.94, retaliateDamage = {700, 920},  dnaReward = 16500000, size = 54, respawnDelay = 78, auraRange = 19, auraDamage = {124, 170}, auraInterval = 0.9 },
	Singularity     = { name = "The Singularity",      emoji = "💫", health = 26000000,retaliateChance = 0.96, retaliateDamage = {820, 1080}, dnaReward = 27000000, size = 56, respawnDelay = 80, auraRange = 20, auraDamage = {144, 198}, auraInterval = 0.85 },
	AbsolutePlane   = { name = "The Absolute",         emoji = "🔺", health = 43000000,retaliateChance = 0.98, retaliateDamage = {960, 1260}, dnaReward = 45000000, size = 60, respawnDelay = 85, auraRange = 20, auraDamage = {168, 230}, auraInterval = 0.8 },
}

-- ===== WHERE A BOSS STANDS =====
-- THIS LIVES HERE BECAUSE TWO FILES NEED IT AND THEY DRIFTED APART. BossService parks the rig at
-- this Z; ZoneBuilder keeps the scatter out of the same circle so decoration never lands on the
-- arena. They were separate constants and a platform-depth rescale updated one and not the other
-- -- the boss ended up 80 studs from the ground that had been cleared for it, so props grew
-- through the fight while the reserved clearing sat empty. Both files read these now.
--
-- The station is close to the exit gate on purpose: the boss is the thing standing in front of
-- the next door, and it should be the first thing you see when you look down the street. The gate
-- itself is at -PLATFORM_DEPTH/2 = -575 and its approach steps begin at -502, so this leaves room
-- for even the largest rig to stand clear of the steps.
GameConfig.BossStationZ = -368
-- Radius kept free of scattered decoration. Sized off the biggest finished rig: a bounding box of
-- ~2.4x the boss size, so ~290 studs across at the top of the table, plus a margin for the biome
-- builders that place two or three parts around one scatter point.
GameConfig.BossStationClear = 178

-- ===== BOSS REVIVE =====
--
-- What the product actually sells, stated plainly because the frustration it addresses is easy to
-- describe wrongly. A boss nobody has touched for BOSS_REGEN_DELAY (14 s) heals fully over
-- BOSS_REGEN_TIME (20 s). The walk back from a respawn is about 31 s -- Roblox's 5 s respawn, the
-- 0.35 s ZoneService wait, then ~858 studs from the arrival gate at Z 490 to the station at Z -368
-- at the base walk speed. So a player does NOT reliably lose everything; they typically come back
-- to a boss that has healed most, not all, of what they took off it. The pitch is "keep your
-- progress", never "you always lose everything", and the code should not pretend otherwise.
--
-- TTL: how long the snapshot of your best health against a boss stays spendable. It has to cover a
-- Robux purchase modal, the respawn and the walk back, and it has to be short enough that nobody
-- banks an hour-old fight. Three minutes clears the first with room and fails the second.
GameConfig.BossReviveTTL = 180
-- After a revive lands, regen is held off for this long REGARDLESS of the 14 s idle delay -- because
-- the buyer is usually still walking back at the moment it lands, and a revive that healed away
-- while they crossed the street would be the same complaint with a receipt attached.
GameConfig.BossReviveFreeze = 30

-- ===== WHERE A BOSS STANDS WHEN THE ZONE IS A MAP (31.4, MOVED AGAIN IN 30.27) =====
-- `BossStationZ` puts every boss on the zone's centre line at -368, which in a valley zone is the
-- middle of the street and is exactly right. In the mapped zone it was not: -368 sat inside the
-- hunting ground the creatures had been folded into, so 31.4 pushed him out into the WESTERN
-- pocket at (-400, -430) on the owner's *"negde dalje da bude"*.
--
-- **30.23 then filled that pocket with camps and the pocket stopped being empty ground.** He ended
-- up standing between the `SW3` and `SW4` camps with wood on all sides and no landmark near him,
-- and the owner photographed exactly that: *"boss stoji random ovde ... boss mora biti kod
-- portala"*. Confirmed with her this session -- the SOUTH GATE, the door to Desert.
--
-- THE Z IS DERIVED AND NOT CHOSEN. The gate stands on the platform's own south wall at
-- `-PLATFORM_DEPTH / 2` = -575 and its approach steps begin at -502, both recorded above.
-- `GATE_STANDOFF` is what keeps the rig off those steps: a Forest boss is ~110 studs across its
-- solid geometry, so 105 studs of standoff leaves its back clear of the stairs while its face is
-- the last thing between the player and the door. Change the platform depth and this follows; it is
-- the same rule `MapRidge.Clear` and `MapForest`'s edges are written to.
--
-- IT IS BACK ON THE CENTRE LINE, WHICH 31.4 CALLED "a wall across the way out", AND THAT IS THE
-- POINT NOW. A boss standing in the lane at -368 blocks a walk to a door 200 studs behind it; a
-- boss standing AT the door is the door's guard, which is what every one of these fights was
-- designed to be (`BossStationZ`'s own comment, forty lines up: *"the boss is the thing standing in
-- front of the next door"*). Nothing is blocked either way -- a boss has exactly ONE colliding
-- part, `BossCollision` at 64 across, so a player walks round it at 32 studs.
--
-- Zone-relative, so `zone.offset` is still added. A zone with no entry here keeps BossStationZ.
local GATE_Z = -575
local GATE_STANDOFF = 105
GameConfig.BossStationOverride = {
	Forest = Vector3.new(0, 0, GATE_Z + GATE_STANDOFF),
}

-- ===== ONE PLACE ASKS, FOUR PLACES USED TO RESTATE =====
-- `CreatureService.insideKeepOut`, `MapProps/MapForest` and `MapProps/JungleLayout` each reserved
-- ground for the boss by writing its coordinates out again -- and all three said `(0, -320)` while
-- the boss had stood at -368 since the platform rescale `BossService.lua:96` records, and at
-- (-400, -430) since 31.4. Three keep-outs, none of them over the boss. That is
-- `evolution-lab-zone-geometry-constants` in its purest form, so they ask this instead.
function GameConfig.GetBossStation(zoneKey)
	return (GameConfig.BossStationOverride or {})[zoneKey]
		or Vector3.new(0, 0, GameConfig.BossStationZ)
end

-- The bosses were tuned as a speed bump on the way to the next portal, and at 18-60 studs they
-- read as a big mob rather than the raid monster the art brief asks for. Applied as one pass over
-- the finished table instead of retyping twenty rows, which is also the only way the three curves
-- below stay in step with each other by construction.
--
-- health and dnaReward move by the SAME factor on purpose: the fight gets longer and the payout
-- gets bigger in proportion, so DNA per second is untouched and no zone's progression shifts.
-- Retaliation is raised on its own -- that is the part that makes a boss feel dangerous rather
-- than merely slow.
-- 31.3: 4.2 -> 1.45. THE MULTIPLIER WAS RIGHT FOR A PLAYER WHO NO LONGER EXISTS. It was chosen
-- when a stage-20 body reached 41 studs; 30.14 froze the body at 8.3 and the Forest boss stayed at
-- 75 units, which is a ~180-stud bounding box -- wider than the village floor is deep and far wider
-- than the hunting ground behind it. That is the owner's "boss je sad preogroman za ovu mapu".
--
-- 1.45 is not a coincidence: it is the same number the map and the body are scaled by, which is what
-- makes Forest's 18 land on 26 -- a ~62-stud rig, about 7.5x the player. Still unmistakably a raid
-- monster, and it now fits in a clearing.
--
-- HEALTH, DNA AND RETALIATION ARE DELIBERATELY NOT TOUCHED. They have their own multipliers below,
-- so this is a purely visual change and no zone's progression moves. What DOES move with it is the
-- damage aura (multiplied by this constant at the bottom of the file) and the click/strike reaches
-- in spawnBoss, which are expressed against `size` -- all three mean "as far as the rig reaches",
-- so shrinking with it is the correct behaviour, not a side effect.
local BOSS_SIZE_MULT = 1.45
local BOSS_HEALTH_MULT = 1.6
local BOSS_HURT_MULT = 1.3

local function scaleRange(range, mult)
	return { math.floor(range[1] * mult), math.floor(range[2] * mult) }
end

-- A FLAT MULTIPLIER WORKS FOR THE EARLY BOSSES AND BREAKS THE LATE ONES, so the gain tapers as
-- the base size grows. A rig's built bounding box runs about 2.4x its `size`, and it has to fit
-- down the street between the egg plaza and the exit gate's approach steps -- roughly 360 studs
-- of room -- so the top of the table is what sets the ceiling, not the bottom.
--
-- 18 -> 75 and 60 -> 121, against 52 and 121 at the last pass. THE GAIN IS ALL IN THE FIRST
-- TWELVE ZONES ON PURPOSE, and it is the cap rather than the multiplier that decides that: the
-- late rigs were already standing on the geometric ceiling. The station is at Z = -368 and the
-- exit gate's approach steps begin at -502, so a rig may reach about 134 studs back before it
-- starts growing through the steps -- and its banner masts sit at 1.16x the boss size. 121 puts
-- them at 140, which is already the margin spent. Raising the cap would bury the gate, so it
-- stays where it is and the multiplier is what moves: Forest 52 -> 75, Ocean 64 -> 88,
-- Galaxy 87 -> 95, and everything from Black Hole on is on the cap and barely changes.
--
-- The min of two increasing terms is increasing, so the curve cannot fold back on itself no
-- matter what the table holds.
--
-- Watch the damage aura when changing this: spawnBoss uses `max(boss.auraRange, boss.size * 0.85)`
-- and the size term is what wins, so a bigger boss also hurts from further out -- Volcano's aura
-- goes 59 -> 76 studs here. That is intended (it means "as far as the rig reaches") but it is a
-- balance change, not just a visual one.
--
-- Two things scale off `size` on their own and therefore move with this: the click reach in
-- spawnBoss, and the damage aura (`math.max(boss.auraRange, boss.size * 0.85)`). Both are meant
-- to mean "as far out as the rig itself reaches", so growing with it is correct -- but it does
-- make the late bosses dangerous from further away than they used to be.
-- The taper moved with the multiplier (31.3). The old cap `70 + size * 0.85` was written to stop
-- the late rigs burying the exit gate at a 4.2x gain and is far above the new linear term
-- everywhere, so leaving it would have made it dead code and let AbsolutePlane reach 87. At
-- `20 + size * 0.47` the cap binds again from the middle of the table on: Forest 18 -> 26,
-- Galaxy 39 -> 38, AbsolutePlane 60 -> 48. The min of two increasing terms is still increasing, so
-- the curve cannot fold back on itself.
local function scaledBossSize(size)
	return math.floor(math.min(size * BOSS_SIZE_MULT, 20 + size * 0.47))
end

for _, boss in pairs(GameConfig.ZoneBosses) do
	boss.size = scaledBossSize(boss.size)
	boss.health = math.floor(boss.health * BOSS_HEALTH_MULT)
	boss.dnaReward = math.floor(boss.dnaReward * BOSS_HEALTH_MULT)
	boss.retaliateDamage = scaleRange(boss.retaliateDamage, BOSS_HURT_MULT)
	if boss.auraDamage then
		boss.auraDamage = scaleRange(boss.auraDamage, BOSS_HURT_MULT)
	end
	if boss.auraRange then
		boss.auraRange = math.floor(boss.auraRange * BOSS_SIZE_MULT)
	end
end

for i, zone in ipairs(GameConfig.Zones) do
	zone.boss = GameConfig.ZoneBosses[zone.key]

	-- ===== BOSS HEALTH IS DERIVED, NOT AUTHORED =====
	--
	-- The twenty numbers in `ZoneBosses` ran 500 to 43,000,000 -- a factor of 86,000 across the
	-- strip, against creature health's 1,050 and the damage ladder's 1,394. Nothing could clear the
	-- late ones: at the reference damage for its own zone, The Absolute took 8,160 blows. It was
	-- passable only because `BossService` clamped every hit to `health / BOSS_MIN_HITS`, which meant
	-- a boss died in exactly twelve blows in every zone from the first to the last -- the same
	-- defect as the creature `damageCap`, and the same reason a boss never felt like it was being
	-- worn down: the bar moved 1/12th whatever the player brought to it.
	--
	-- Priced in blows instead, off the same ladder as everything else, so a boss is the same length
	-- of fight in the zone it guards on every rung. The authored `health` is now only a relative hint
	-- that nothing reads -- `dnaReward` keeps its own authored value and its own scaling, because
	-- what a boss PAYS is a design decision and what it TAKES is arithmetic.
	--
	-- THE MAX IS NOT DECORATION. The blows term alone put every boss in the game under the Elite of
	-- its own zone -- see the note on BossTargetHits, where the measurement is written out. The floor
	-- term is what ties the boss curve to the creature curve, so tuning `mobHealthMult` cannot pull
	-- them apart again in silence.
	--
	-- STILL PRICED ON THE ELITE after 11.6 added a tier above it, and deliberately so. Pricing it on
	-- the Apex instead would have raised every floor-bound boss (zones 2-17) by 25% -- a balance
	-- change nobody asked for -- and it is not needed: `ApexBaseHealth` is clamped to
	-- `BossEliteFloor * EliteBaseHealth`, which is exactly the condition for a farmed Apex to stay
	-- inside this floor. The guarantee lives in the clamp, so this line did not have to move and a
	-- future row cannot break it by editing the Apex either. See the ApexBaseHealth block.
	--
	-- ===== AND THE WHOLE THING IS SCALED BY DEPTH SINCE 32.7 =====
	--
	-- `GetZoneDepthMult(i)` is x1.00 in Forest and x3.03 on the Absolute Plane -- her *"nek bossovi
	-- i creaturi na vecim stagevima budu jaci"*. The full argument, including why it is health and
	-- never damage, is written out over `GameConfig.MobDepthGrowth`.
	--
	-- **APPLIED OUTSIDE THE `math.max`, TO BOTH TERMS AT ONCE, AND THAT IS NOT A STYLE CHOICE.**
	-- The two terms are the blows curve and the Elite floor, and the paragraph above is about the
	-- floor existing precisely to keep this curve ATTACHED to the creature curve. `CreatureService`
	-- multiplies its own spawn health by the same factor, so scaling only one term here -- or
	-- forgetting this line while adding that one -- re-creates 11.9's boss-weaker-than-a-creep
	-- inversion in exactly the way the floor was built to make impossible.
	zone.boss.health = math.floor(GameConfig.GetZoneDepthMult(i) * math.max(
		math.floor(GameConfig.BossTargetHits * GameConfig.GetZoneReferenceDamage(i)),
		math.floor(GameConfig.BossEliteFloor * GameConfig.EliteBaseHealth
			* GameConfig.CreatureGenerationMax * zone.mobHealthMult)))

	-- Exactly HALF a level, in the currency of the stage this zone belongs to (zone i unlocks at
	-- stage i, so the index is the same one the xpCost curve is written against). Boss XP used to be
	-- a flat 25 everywhere, which was a third of the first level and a rounding error by the tenth.
	zone.boss.xpReward = math.floor(25 * GameConfig.XpPerLevelGrowth ^ (i - 1)
		* (1 + (i - 1) * GameConfig.XpPerLevelRamp))
end

-- A zone is unlocked once the player reached its stage requirement AND (if it has one)
-- personally defeated the boss guarding the previous zone's exit.
function GameConfig.IsZoneUnlocked(zone, data)
	if data.StageIndex < zone.unlockStageIndex then
		return false
	end
	if zone.requiresBossKey then
		local defeated = false
		for _, k in ipairs(data.DefeatedBosses or {}) do
			if k == zone.requiresBossKey then
				defeated = true
				break
			end
		end
		if not defeated then
			return false
		end
	end
	return true
end

function GameConfig.GetZoneByKey(key)
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.key == key then return zone end
	end
	return nil
end

-- The zone's POSITION, which is what the damage ladder is indexed by (GetZoneReferenceDamage) --
-- `Zones` is an ordered array and zone i unlocks at stage i, so the index is the progression
-- coordinate. Returns 1 for anything unknown rather than nil: every caller here is arithmetic, and
-- a nil leaking into a multiplication is a hard error at a call site that cannot do anything
-- useful about it anyway.
function GameConfig.GetZoneIndex(key)
	for i, zone in ipairs(GameConfig.Zones) do
		if zone.key == key then return i end
	end
	return 1
end

function GameConfig.GetTotalZoneBonusPct(unlockedZoneKeys)
	local total = 0
	local lookup = {}
	for _, k in ipairs(unlockedZoneKeys) do lookup[k] = true end
	for _, zone in ipairs(GameConfig.Zones) do
		if lookup[zone.key] then
			total += zone.incomeBonusPct
		end
	end
	return total
end

-- ===== SECRETS: A HIDDEN SPOT THAT PAYS A MUTATION =====
--
-- `offset` is ZONE-LOCAL: the trigger is built at `Vector3.new(zone.offset, 0, 0) + offset`, and
-- `MapWaterfall` builds the grotto around the SAME number, so the room and the trigger cannot
-- drift apart.
--
-- THE OLD VALUE WAS `(-32.7, 176.1, -151.2)` AND IT WAS UNREACHABLE. That is the waterfall model's
-- bounding-box CENTRE, measured to 0.1 studs -- the middle of a 217 x 234 x 307 prop, inside five
-- of its own 80-stud rock parts. Nothing could ever touch it, and nothing said so. See 32.26.
--
-- The value below is the grotto behind the falls: the water column lands at x 291 / z -260 and the
-- lowest `Plunge` shelf spans z -276..-244, so z -290 puts the room's doorway directly behind the
-- curtain. Y is 6 rather than 0 because a 12-stud touch part centred on the floor is half buried
-- in it.
GameConfig.Secrets = {
	{
		id = "ForestWaterfall",
		zoneKey = "Forest",
		rewardType = "mutation",
		rewardName = "Godly",
		offset = Vector3.new(291, 6, -290),
	}
}

end
