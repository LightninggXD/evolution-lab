local GameConfig = {}

-- ===== EVOLUTION CHAIN =====
-- Each stage: name, emoji, DNA cost to evolve INTO the NEXT stage, scale (visual size multiplier), color
-- 20 stages total. Rebirth checkpoints land every 5 stages (5, 10, 15, 20) -- see the
-- REBIRTH section below. cost = math.huge only on the very last stage (true end of the loop).
GameConfig.Stages = {
	{ name = "Cell",              emoji = "🧭",  cost = 12,       scale = 1.0, color = Color3.fromRGB(180, 255, 180) }, -- was 0: the first evolve fired instantly, at spawn
	{ name = "Bacteria",          emoji = "🦠",  cost = 50,       scale = 1.15, color = Color3.fromRGB(140, 220, 140) },
	{ name = "Worm",              emoji = "🐛",  cost = 250,      scale = 1.35, color = Color3.fromRGB(200, 160, 90) },
	{ name = "Lizard",            emoji = "🦎",  cost = 1200,     scale = 1.55, color = Color3.fromRGB(90, 200, 90) },
	{ name = "Wolf",              emoji = "🐺",  cost = 6000,     scale = 1.8, color = Color3.fromRGB(150, 150, 160) }, -- Rebirth Tier 1
	{ name = "Gorilla",           emoji = "🦧",  cost = 30000,    scale = 2.1, color = Color3.fromRGB(90, 70, 60) },
	{ name = "Human",             emoji = "👤",  cost = 150000,   scale = 2.4, color = Color3.fromRGB(230, 190, 150) },
	{ name = "Cyborg",            emoji = "🤖",  cost = 800000,   scale = 2.7, color = Color3.fromRGB(120, 200, 230) },
	{ name = "Alien",             emoji = "👽",  cost = 4000000,  scale = 3.0, color = Color3.fromRGB(140, 255, 140) },
	{ name = "Cosmic Being",      emoji = "☀️",  cost = 20000000, scale = 3.3, color = Color3.fromRGB(255, 220, 100) }, -- Rebirth Tier 2
	{ name = "Universe God",      emoji = "🌌",  cost = 100000000,        scale = 3.6, color = Color3.fromRGB(190, 120, 255) },
	{ name = "Star Weaver",       emoji = "🕸️",  cost = 500000000,        scale = 3.75, color = Color3.fromRGB(120, 200, 255) },
	{ name = "Time Walker",       emoji = "⏳",  cost = 2500000000,       scale = 3.9, color = Color3.fromRGB(200, 220, 255) },
	{ name = "Void Sovereign",    emoji = "🕳️",  cost = 12000000000,      scale = 4.05, color = Color3.fromRGB(60, 50, 80) },
	{ name = "Reality Architect", emoji = "🔷",  cost = 60000000000,      scale = 4.2, color = Color3.fromRGB(80, 180, 255) }, -- Rebirth Tier 3
	{ name = "Dimensional Titan", emoji = "🌐",  cost = 300000000000,     scale = 4.35, color = Color3.fromRGB(100, 220, 220) },
	{ name = "Chronos Being",     emoji = "♾️",  cost = 1500000000000,    scale = 4.5, color = Color3.fromRGB(255, 215, 150) },
	{ name = "Omniscient Entity", emoji = "👁️",  cost = 7000000000000,    scale = 4.65, color = Color3.fromRGB(255, 240, 200) },
	{ name = "Primordial Force",  emoji = "🌑",  cost = 35000000000000,   scale = 4.8, color = Color3.fromRGB(40, 20, 60) },
	{ name = "The Absolute",      emoji = "🔺",  cost = math.huge,        scale = 5.0, color = Color3.fromRGB(255, 255, 255) }, -- Rebirth Tier 4 (true max)
}

-- Every evolve cost is multiplied by this. The literal table above keeps the original readable
-- numbers, and the scale exists so the whole curve can be retuned from one place. It is set to 10
-- because the un-scaled costs were small enough that a readable per-kill reward (~6 DNA, rather
-- than the 0.58 an unscaled curve produced -- which the client floors to a demoralising "+0")
-- would have cleared the first several stages in two or three kills.
GameConfig.EvolveCostScale = 10

for _, stage in ipairs(GameConfig.Stages) do
	if stage.cost ~= math.huge then
		stage.cost = math.floor(stage.cost * GameConfig.EvolveCostScale)
	end
end

-- ===== XP: THE LEVEL BAR =====
-- XP is earned ONLY by fighting (creatures and bosses -- never from clicking or from DNA), and
-- unlike the old design it IS SPENT: evolving takes the stage's `xpCost` off the total and the bar
-- starts again from zero. `xpCost` is therefore a PER-LEVEL requirement, not a running lifetime
-- total -- "fill the bar, evolve, fill it again" -- which is the only reading of it that survives
-- twenty stages. As a cumulative threshold the last stage asked for 26,650 XP at 1 XP a kill.
--
-- Three numbers set the whole pace, and they are meant to be read together with the zone XP
-- multiplier derived further down:
--   * growth 1.55 is ALSO the per-zone creature XP multiplier. Because the requirement and the
--     payout grow by the same factor, kills-per-level is a flat number across the whole game
--     instead of drifting -- change one and you must change the other.
--   * start 50 puts the first evolve at ~25 Critters (or 50 Swarmers, or 10 Brutes).
--   * ramp adds 6 % of a level's worth of kills per stage on top, so a stage near the end of the
--     chain is about twice the commitment of the first one. Progression is deliberately
--     XP-gated rather than DNA-gated: DNA is multiplied by pets, mutations, potions and zone
--     bonuses and can be inflated by a factor of thousands, so a DNA-paced chain collapses the
--     moment a player has a good collection. Nothing multiplies XP except the XP potion.
GameConfig.XpPerLevelStart = 50
GameConfig.XpPerLevelGrowth = 1.55
GameConfig.XpPerLevelRamp = 0.06

for i, stage in ipairs(GameConfig.Stages) do
	if stage.cost == math.huge then
		stage.xpCost = math.huge
	else
		stage.xpCost = math.floor(GameConfig.XpPerLevelStart
			* GameConfig.XpPerLevelGrowth ^ (i - 1)
			* (1 + (i - 1) * GameConfig.XpPerLevelRamp))
	end
end

-- ===== THE LAST STAGE STILL HAS FOUR EVOLVES INSIDE IT =====
-- `cost = math.huge` on stage 20 means "there is no stage after this one", and every max-evolution
-- check in the game reads it that way. It therefore cannot double as the PRICE of the steps taken
-- inside that stage (see GameConfig.GetEvolveStep -- every skin is its own evolve now), so the
-- final stage's step price is extrapolated off the curve it sits at the end of: the chain
-- multiplies by ~5 a stage and stage 19 holds the last real number.
GameConfig.FinalStageStepMult = 5
GameConfig.FinalStageStepCost = math.floor(
	GameConfig.Stages[#GameConfig.Stages - 1].cost * GameConfig.FinalStageStepMult)
GameConfig.FinalStageStepXp = math.floor(GameConfig.XpPerLevelStart
	* GameConfig.XpPerLevelGrowth ^ (#GameConfig.Stages - 1)
	* (1 + (#GameConfig.Stages - 1) * GameConfig.XpPerLevelRamp))

-- Mutations used to multiply together, and the list only ever grows -- one roll every 10s,
-- forever, with nothing ever removed. A player who had been testing for a while accumulated
-- enough that income was multiplied by ~5,000,000, and a single Forest creature paid 66.66M DNA
-- at stage 4. Now only the BEST mutation applies in full; every other one contributes a small
-- additive share, so a large collection is still worth having but can never compound.
GameConfig.MutationStackBonus = 0.05

function GameConfig.GetMutationIncomeMult(mutationNames)
	local best, rest = 1, 0
	for _, name in ipairs(mutationNames or {}) do
		for _, m in ipairs(GameConfig.Mutations) do
			if m.name == name then
				rest = rest + (m.incomeMult - 1)
				if m.incomeMult > best then best = m.incomeMult end
				break
			end
		end
	end
	rest = rest - (best - 1) -- the best one is counted in full below, not twice
	return best + rest * GameConfig.MutationStackBonus
end

-- ===== INCOME CURVE =====
-- DNA earned per click and per creature kill has to grow at the same rate as the evolve costs,
-- or progression drifts apart. The old base -- `1 + (stageIndex - 1) * 0.5` -- grew about 2x per
-- stage against a ~5x cost curve, so leaving Cell took 5 kills while leaving Star Weaver took
-- 30,812. Too generous at the start, impossible at the end, which is the same defect twice.
--
-- Costs rise ~5x per stage. Two multipliers already ride along with progression: the zone DNA
-- multiplier (~1.45x per zone) and the cumulative zone income bonus (~1.22x per zone). So the
-- click base only has to supply the remainder, 5 / (1.45 * 1.22) ~= 2.85x. Anchoring the start
-- at 0.13 lands every stage between 14 and 20 creature kills, from Cell to Primordial Force.
--
-- Verify after changing either constant -- kills per stage should stay flat:
--   perKill(i) = GetClickBase(i) * (1 + GetTotalZoneBonusPct(zones 1..i)/100) * 4.5 * Zones[i].mobDnaMult
--   kills(i)   = Stages[i].cost / perKill(i)
-- 1.3 pairs with EvolveCostScale = 10 above: it puts the very first creature kill at ~5.9 DNA
-- (readable -- the client floors the notification, so anything under 1 shows as "+0") and the
-- first evolve at ~21 kills.
GameConfig.ClickBaseStart = 1.3
GameConfig.ClickBaseGrowth = 2.85

function GameConfig.GetClickBase(stageIndex)
	return GameConfig.ClickBaseStart * (GameConfig.ClickBaseGrowth ^ ((stageIndex or 1) - 1))
end

-- ===== UPGRADES =====
-- baseCost grows by costMult per level. effect described per stat.
GameConfig.Upgrades = {
	Speed = {
		displayName = "Speed",
		emoji = "👟",
		baseCost = 25,
		costMult = 1.14,
		description = "Moves you faster around the lab",
	},
	Income = {
		displayName = "Income",
		emoji = "💰",
		baseCost = 20,
		costMult = 1.15,
		description = "+DNA per click and per second",
	},
	Luck = {
		displayName = "Luck",
		emoji = "🍀",
		baseCost = 40,
		costMult = 1.18,
		description = "Higher chance of Critical DNA & rare mutations",
	},
	Mutation = {
		displayName = "Mutation Chance",
		emoji = "🧬",
		baseCost = 60,
		costMult = 1.2,
		description = "More frequent mutation rolls",
	},
	AutoCollect = {
		displayName = "Auto Collect",
		emoji = "⚙️",
		baseCost = 100,
		costMult = 1.22,
		description = "Passively collects DNA every second",
	},
}

-- ===== MUTATIONS =====
GameConfig.Mutations = {
	{ name = "Common",    weight = 500, incomeMult = 1.3,  speedMult = 1.1,  color = Color3.fromRGB(200,200,200) },
	{ name = "Rare",      weight = 200, incomeMult = 1.8,  speedMult = 1.25, color = Color3.fromRGB(90,160,255) },
	{ name = "Epic",      weight = 80,  incomeMult = 3.0,  speedMult = 1.5,  color = Color3.fromRGB(170,90,255) },
	{ name = "Legendary", weight = 25,  incomeMult = 5.0,  speedMult = 2.0,  color = Color3.fromRGB(255,180,50) },
	{ name = "Mythic",    weight = 8,   incomeMult = 8.0,  speedMult = 2.75, color = Color3.fromRGB(255,80,80) },
	{ name = "Secret",    weight = 2,   incomeMult = 15.0, speedMult = 3.5,  color = Color3.fromRGB(20,20,20) },
	{ name = "Godly",     weight = 1,   incomeMult = 30.0, speedMult = 5.0,  color = Color3.fromRGB(255,240,150) },
}

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

-- The bosses were tuned as a speed bump on the way to the next portal, and at 18-60 studs they
-- read as a big mob rather than the raid monster the art brief asks for. Applied as one pass over
-- the finished table instead of retyping twenty rows, which is also the only way the three curves
-- below stay in step with each other by construction.
--
-- health and dnaReward move by the SAME factor on purpose: the fight gets longer and the payout
-- gets bigger in proportion, so DNA per second is untouched and no zone's progression shifts.
-- Retaliation is raised on its own -- that is the part that makes a boss feel dangerous rather
-- than merely slow.
local BOSS_SIZE_MULT = 4.2
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
local function scaledBossSize(size)
	return math.floor(math.min(size * BOSS_SIZE_MULT, 70 + size * 0.85))
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

-- ===== PETS =====
-- Two independent axes, which is worth stating plainly because they are easy to confuse:
--   RARITY  is the species you rolled (Common .. Legendary). Fixed at hatch, never changes.
--   TIER    is how many copies you fused together (Normal .. Celestial). See PetTiers below.
-- A Legendary Normal and a Common Celestial are both strong, for different reasons.
GameConfig.PetRarities = {
	{ name = "Common",    weight = 1000, bonusMult = 1.0, color = Color3.fromRGB(198, 202, 214) },
	{ name = "Uncommon",  weight = 400,  bonusMult = 1.6, color = Color3.fromRGB(110, 224, 130) },
	{ name = "Rare",      weight = 150,  bonusMult = 2.6, color = Color3.fromRGB(90, 170, 255) },
	{ name = "Epic",      weight = 42,   bonusMult = 4.5, color = Color3.fromRGB(190, 110, 255) },
	{ name = "Legendary", weight = 8,    bonusMult = 8.0, color = Color3.fromRGB(255, 190, 60) },
}

GameConfig.PetRarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

function GameConfig.GetRarity(name)
	for _, r in ipairs(GameConfig.PetRarities) do
		if r.name == name then return r end
	end
	return GameConfig.PetRarities[1]
end

-- Every zone has its own five species -- one per rarity -- so the egg you buy in Volcano can
-- never hand you a Forest pet. Forest deliberately keeps the five original keys (Pebble, Sparky,
-- Mossy, Finn, Draco) so pets in existing saves still resolve to a real definition.
local ZONE_PETS = {
	Forest = {
		{ key = "Pebble",     name = "Pebble",      emoji = "🪨", color = Color3.fromRGB(160, 160, 160) },
		{ key = "Mossy",      name = "Mossy",       emoji = "🍀", color = Color3.fromRGB(100, 200, 100) },
		{ key = "Sparky",     name = "Sparky",      emoji = "⚡", color = Color3.fromRGB(255, 220, 80) },
		{ key = "Finn",       name = "Finn",        emoji = "🐟", color = Color3.fromRGB(80, 160, 255) },
		{ key = "Draco",      name = "Draco",       emoji = "🐉", color = Color3.fromRGB(220, 60, 60) },
	},
	Desert = {
		{ key = "Scarab",     name = "Scarab",      emoji = "🪲", color = Color3.fromRGB(180, 150, 90) },
		{ key = "Cactuso",    name = "Cactuso",     emoji = "🌵", color = Color3.fromRGB(96, 170, 96) },
		{ key = "Fennec",     name = "Fennec",      emoji = "🦊", color = Color3.fromRGB(238, 202, 140) },
		{ key = "Sandwyrm",   name = "Sandwyrm",    emoji = "🐍", color = Color3.fromRGB(214, 172, 104) },
		{ key = "Sphinx",     name = "Sphinx",      emoji = "🗿", color = Color3.fromRGB(236, 208, 128) },
	},
	Ocean = {
		{ key = "Shelly",     name = "Shelly",      emoji = "🐚", color = Color3.fromRGB(248, 220, 206) },
		{ key = "Bubbles",    name = "Bubbles",     emoji = "🐠", color = Color3.fromRGB(255, 168, 92) },
		{ key = "Inky",       name = "Inky",        emoji = "🦑", color = Color3.fromRGB(168, 112, 255) },
		{ key = "Chomps",     name = "Chomps",      emoji = "🦈", color = Color3.fromRGB(96, 150, 190) },
		{ key = "Kraklet",    name = "Kraklet",     emoji = "🐙", color = Color3.fromRGB(226, 78, 128) },
	},
	Volcano = {
		{ key = "Cinder",     name = "Cinder",      emoji = "🪨", color = Color3.fromRGB(84, 62, 58) },
		{ key = "Emberling",  name = "Emberling",   emoji = "🔥", color = Color3.fromRGB(255, 148, 60) },
		{ key = "Magmite",    name = "Magmite",     emoji = "🌋", color = Color3.fromRGB(255, 96, 40) },
		{ key = "Obsidion",   name = "Obsidion",    emoji = "🖤", color = Color3.fromRGB(48, 32, 44) },
		{ key = "Pyrodrake",  name = "Pyrodrake",   emoji = "🐲", color = Color3.fromRGB(255, 72, 40) },
	},
	Moon = {
		{ key = "Dustbun",    name = "Dustbun",     emoji = "🐇", color = Color3.fromRGB(212, 212, 220) },
		{ key = "Cratercub",  name = "Cratercub",   emoji = "🌕", color = Color3.fromRGB(180, 180, 190) },
		{ key = "Lunamoth",   name = "Lunamoth",    emoji = "🦋", color = Color3.fromRGB(196, 220, 255) },
		{ key = "Tidalux",    name = "Tidalux",     emoji = "🌙", color = Color3.fromRGB(150, 200, 255) },
		{ key = "Selenith",   name = "Selenith",    emoji = "✨", color = Color3.fromRGB(236, 244, 255) },
	},
	Mars = {
		{ key = "Rustling",   name = "Rustling",    emoji = "🪨", color = Color3.fromRGB(178, 88, 56) },
		{ key = "Roverpup",   name = "Roverpup",    emoji = "🤖", color = Color3.fromRGB(214, 206, 186) },
		{ key = "Dustdevil",  name = "Dustdevil",   emoji = "🌪️", color = Color3.fromRGB(226, 152, 104) },
		{ key = "Olympus",    name = "Olympus",     emoji = "⛰️", color = Color3.fromRGB(140, 66, 44) },
		{ key = "Warlord",    name = "Warlord",     emoji = "🔴", color = Color3.fromRGB(226, 62, 42) },
	},
	Galaxy = {
		{ key = "Twinkle",    name = "Twinkle",     emoji = "⭐", color = Color3.fromRGB(255, 240, 190) },
		{ key = "Cometail",   name = "Cometail",    emoji = "☄️", color = Color3.fromRGB(150, 200, 255) },
		{ key = "Orbiton",    name = "Orbiton",     emoji = "🪐", color = Color3.fromRGB(206, 160, 110) },
		{ key = "Starforge",  name = "Starforge",   emoji = "🌟", color = Color3.fromRGB(255, 214, 120) },
		{ key = "Galactus",   name = "Galactus",    emoji = "🌌", color = Color3.fromRGB(150, 100, 230) },
	},
	BlackHole = {
		{ key = "Speck",      name = "Speck",       emoji = "⚫", color = Color3.fromRGB(52, 44, 66) },
		{ key = "Gravlet",    name = "Gravlet",     emoji = "🌀", color = Color3.fromRGB(120, 70, 170) },
		{ key = "Accretia",   name = "Accretia",    emoji = "💫", color = Color3.fromRGB(255, 170, 90) },
		{ key = "Horizon",    name = "Horizon",     emoji = "🕳️", color = Color3.fromRGB(24, 18, 32) },
		{ key = "Devourer",   name = "Devourer",    emoji = "😈", color = Color3.fromRGB(186, 80, 246) },
	},
	Multiverse = {
		{ key = "Gliph",      name = "Gliph",       emoji = "🔷", color = Color3.fromRGB(120, 190, 255) },
		{ key = "Echo",       name = "Echo",        emoji = "🪞", color = Color3.fromRGB(226, 226, 246) },
		{ key = "Splitpaw",   name = "Splitpaw",    emoji = "🐾", color = Color3.fromRGB(255, 120, 210) },
		{ key = "Paradox",    name = "Paradox",     emoji = "♾️", color = Color3.fromRGB(160, 120, 255) },
		{ key = "Everykind",  name = "Everykind",   emoji = "🌈", color = Color3.fromRGB(255, 100, 220) },
	},
	Nebula = {
		{ key = "Mistling",   name = "Mistling",    emoji = "☁️", color = Color3.fromRGB(206, 168, 236) },
		{ key = "Gasbub",     name = "Gasbub",      emoji = "🫧", color = Color3.fromRGB(180, 200, 255) },
		{ key = "Protostar",  name = "Protostar",   emoji = "🌠", color = Color3.fromRGB(255, 236, 190) },
		{ key = "Pillarion",  name = "Pillarion",   emoji = "🗼", color = Color3.fromRGB(224, 120, 236) },
		{ key = "Stellara",   name = "Stellara",    emoji = "💜", color = Color3.fromRGB(200, 120, 255) },
	},
	Wormhole = {
		{ key = "Loopling",   name = "Loopling",    emoji = "➰", color = Color3.fromRGB(140, 130, 200) },
		{ key = "Throatlet",  name = "Throatlet",   emoji = "🌀", color = Color3.fromRGB(150, 100, 245) },
		{ key = "Warpcat",    name = "Warpcat",     emoji = "🐈", color = Color3.fromRGB(200, 180, 255) },
		{ key = "Tunneler",   name = "Tunneler",    emoji = "🚇", color = Color3.fromRGB(110, 90, 190) },
		{ key = "Eventide",   name = "Eventide",    emoji = "🔮", color = Color3.fromRGB(215, 200, 255) },
	},
	QuantumRealm = {
		{ key = "Quark",      name = "Quark",       emoji = "⚛️", color = Color3.fromRGB(120, 220, 220) },
		{ key = "Blink",      name = "Blink",       emoji = "👁️", color = Color3.fromRGB(150, 255, 245) },
		{ key = "Superpaw",   name = "Superpaw",    emoji = "🐾", color = Color3.fromRGB(80, 220, 220) },
		{ key = "Entangle",   name = "Entangle",    emoji = "🧬", color = Color3.fromRGB(60, 190, 210) },
		{ key = "Schrodin",   name = "Schrodin",    emoji = "🐱", color = Color3.fromRGB(190, 255, 250) },
	},
	TimeRift = {
		{ key = "Tickling",   name = "Tickling",    emoji = "⏱️", color = Color3.fromRGB(200, 168, 100) },
		{ key = "Sandglass",  name = "Sandglass",   emoji = "⌛", color = Color3.fromRGB(238, 208, 130) },
		{ key = "Cogsworth",  name = "Cogsworth",   emoji = "⚙️", color = Color3.fromRGB(160, 124, 64) },
		{ key = "Rewind",     name = "Rewind",      emoji = "⏪", color = Color3.fromRGB(190, 214, 236) },
		{ key = "Chronos",    name = "Chronos",     emoji = "⏳", color = Color3.fromRGB(255, 214, 110) },
	},
	AntimatterZone = {
		{ key = "Ionling",    name = "Ionling",     emoji = "🔋", color = Color3.fromRGB(180, 90, 80) },
		{ key = "Flarepup",   name = "Flarepup",    emoji = "💥", color = Color3.fromRGB(255, 140, 110) },
		{ key = "Contain",    name = "Contain",     emoji = "🧨", color = Color3.fromRGB(248, 208, 40) },
		{ key = "Nullion",    name = "Nullion",     emoji = "⚠️", color = Color3.fromRGB(255, 70, 70) },
		{ key = "Annihil",    name = "Annihil",     emoji = "☢️", color = Color3.fromRGB(255, 40, 40) },
	},
	DreamDimension = {
		{ key = "Napkin",     name = "Napkin",      emoji = "😴", color = Color3.fromRGB(226, 208, 246) },
		{ key = "Fluffle",    name = "Fluffle",     emoji = "🫧", color = Color3.fromRGB(255, 206, 236) },
		{ key = "Sleepaw",    name = "Sleepaw",     emoji = "🐑", color = Color3.fromRGB(240, 240, 255) },
		{ key = "Reverie",    name = "Reverie",     emoji = "💭", color = Color3.fromRGB(200, 160, 255) },
		{ key = "Sandman",    name = "Sandman",     emoji = "🌜", color = Color3.fromRGB(214, 150, 255) },
	},
	MirrorUniverse = {
		{ key = "Shardlet",   name = "Shardlet",    emoji = "🔹", color = Color3.fromRGB(200, 214, 238) },
		{ key = "Reflekt",    name = "Reflekt",     emoji = "🪞", color = Color3.fromRGB(226, 232, 250) },
		{ key = "Twinpaw",    name = "Twinpaw",     emoji = "👯", color = Color3.fromRGB(180, 200, 255) },
		{ key = "Inverso",    name = "Inverso",     emoji = "🔃", color = Color3.fromRGB(150, 170, 220) },
		{ key = "Mirrorch",   name = "Mirrorch",    emoji = "💠", color = Color3.fromRGB(240, 248, 255) },
	},
	VoidExpanse = {
		{ key = "Nibble",     name = "Nibble",      emoji = "🕸️", color = Color3.fromRGB(60, 50, 78) },
		{ key = "Hollow",     name = "Hollow",      emoji = "🌑", color = Color3.fromRGB(38, 30, 52) },
		{ key = "Unraveler",  name = "Unraveler",   emoji = "🧵", color = Color3.fromRGB(148, 62, 228) },
		{ key = "Nihil",      name = "Nihil",       emoji = "⬛", color = Color3.fromRGB(20, 16, 28) },
		{ key = "Voidmaw",    name = "Voidmaw",     emoji = "👾", color = Color3.fromRGB(170, 80, 255) },
	},
	CelestialThrone = {
		{ key = "Cherub",     name = "Cherub",      emoji = "👼", color = Color3.fromRGB(255, 238, 200) },
		{ key = "Haloling",   name = "Haloling",    emoji = "😇", color = Color3.fromRGB(255, 226, 150) },
		{ key = "Seraphim",   name = "Seraphim",    emoji = "🕊️", color = Color3.fromRGB(255, 250, 226) },
		{ key = "Regalia",    name = "Regalia",     emoji = "👑", color = Color3.fromRGB(255, 218, 128) },
		{ key = "Throneus",   name = "Throneus",    emoji = "⚜️", color = Color3.fromRGB(255, 200, 70) },
	},
	Singularity = {
		{ key = "Point",      name = "Point",       emoji = "⚪", color = Color3.fromRGB(226, 230, 244) },
		{ key = "Collapse",   name = "Collapse",    emoji = "🌐", color = Color3.fromRGB(190, 200, 226) },
		{ key = "Infinion",   name = "Infinion",    emoji = "♾️", color = Color3.fromRGB(255, 255, 255) },
		{ key = "Densita",    name = "Densita",     emoji = "🔘", color = Color3.fromRGB(150, 156, 180) },
		{ key = "Omegapoint", name = "Omega Point", emoji = "💫", color = Color3.fromRGB(255, 255, 255) },
	},
	AbsolutePlane = {
		{ key = "Gilder",     name = "Gilder",      emoji = "🔸", color = Color3.fromRGB(255, 232, 170) },
		{ key = "Monolith",   name = "Monolith",    emoji = "🗿", color = Color3.fromRGB(248, 248, 244) },
		{ key = "Aurelian",   name = "Aurelian",    emoji = "🏅", color = Color3.fromRGB(255, 215, 0) },
		{ key = "Absolon",    name = "Absolon",     emoji = "🔺", color = Color3.fromRGB(255, 226, 120) },
		{ key = "TheFirst",   name = "The First",   emoji = "🥇", color = Color3.fromRGB(255, 240, 190) },
	},
}

-- Flattened lookup. Each species carries its zone and its rarity; the rarity is positional --
-- entry i in a zone's list is PetRarityOrder[i] -- so a zone list is always exactly five long.
GameConfig.Pets = {}
GameConfig.PetsByZone = {}
for _, zone in ipairs(GameConfig.Zones) do
	local pool = ZONE_PETS[zone.key]
	if pool then
		GameConfig.PetsByZone[zone.key] = {}
		for i, p in ipairs(pool) do
			local def = {
				key = p.key,
				name = p.name,
				emoji = p.emoji,
				color = p.color,
				zone = zone.key,
				rarity = GameConfig.PetRarityOrder[i] or "Common",
			}
			table.insert(GameConfig.Pets, def)
			table.insert(GameConfig.PetsByZone[zone.key], def)
		end
	end
end

function GameConfig.GetPetDef(key)
	for _, p in ipairs(GameConfig.Pets) do
		if p.key == key then return p end
	end
	return nil
end

-- Base bonus a single Common, Normal-tier pet grants while equipped. Rarity and tier both
-- scale it -- see GetPetBonus.
GameConfig.PetBaseBonus = { incomeMult = 1.4, luckAdd = 5, dnaMult = 2, damageMult = 1.3 }

-- Fusing N copies of the same pet+tier produces one pet of the next tier, which
-- multiplies the base bonus by PetTierMultiplier.
GameConfig.PetTiers = { "Normal", "Golden", "Rainbow", "Celestial" }
GameConfig.PetTierMultiplier = { Normal = 1, Golden = 2, Rainbow = 4, Celestial = 8 }
GameConfig.PetTierColor = {
	Normal = Color3.fromRGB(220, 220, 220),
	Golden = Color3.fromRGB(255, 215, 60),
	Rainbow = Color3.fromRGB(255, 120, 220),
	Celestial = Color3.fromRGB(120, 220, 255),
}
GameConfig.FuseRequirement = 4
GameConfig.MaxEquippedPets = 3

-- Each zone's Pet Shop sells 3 eggs -- Basic/Better/Premium -- built by tiering that
-- zone's base cost/luckBonus (same numbers the old single-egg-per-zone design used).
local ZONE_EGG_BASE = {
	{ zone = "Forest",          baseCost = 500,                baseLuck = 0 },
	{ zone = "Desert",          baseCost = 2500,               baseLuck = 6 },
	{ zone = "Ocean",           baseCost = 12000,              baseLuck = 12 },
	{ zone = "Volcano",         baseCost = 60000,              baseLuck = 18 },
	{ zone = "Moon",            baseCost = 300000,             baseLuck = 24 },
	{ zone = "Mars",            baseCost = 1500000,            baseLuck = 30 },
	{ zone = "Galaxy",          baseCost = 8000000,            baseLuck = 40 },
	{ zone = "BlackHole",       baseCost = 40000000,           baseLuck = 55 },
	{ zone = "Multiverse",      baseCost = 200000000,          baseLuck = 75 },
	{ zone = "Nebula",          baseCost = 1000000000,         baseLuck = 90 },
	{ zone = "Wormhole",        baseCost = 5000000000,         baseLuck = 105 },
	{ zone = "QuantumRealm",    baseCost = 25000000000,        baseLuck = 120 },
	{ zone = "TimeRift",        baseCost = 125000000000,       baseLuck = 135 },
	{ zone = "AntimatterZone",  baseCost = 600000000000,       baseLuck = 150 },
	{ zone = "DreamDimension",  baseCost = 3000000000000,      baseLuck = 165 },
	{ zone = "MirrorUniverse",  baseCost = 15000000000000,     baseLuck = 180 },
	{ zone = "VoidExpanse",     baseCost = 75000000000000,     baseLuck = 195 },
	{ zone = "CelestialThrone", baseCost = 375000000000000,    baseLuck = 210 },
	{ zone = "Singularity",     baseCost = 1800000000000000,   baseLuck = 225 },
	{ zone = "AbsolutePlane",   baseCost = 9000000000000000,   baseLuck = 250 },
}

-- Two separate levers, and both matter:
--   rarityMin/rarityMax slice the zone's five species, so the three eggs on one podium hold
--   three *different* lists -- the cheap egg cannot hand you the Legendary at all, and the
--   Premium one has stopped wasting rolls on the Common.
--   rarityBias then shifts the odds inside whatever slice is left.
local EGG_TIERS = {
	{ suffix = "Basic",   emoji = "🥚", costMult = 1,   luckAdd = 0,  rarityBias = 0,   rarityMin = 1, rarityMax = 4 },
	{ suffix = "Better",  emoji = "🐣", costMult = 3.5, luckAdd = 10, rarityBias = 1.1, rarityMin = 1, rarityMax = 5 },
	{ suffix = "Premium", emoji = "🌟", costMult = 9,   luckAdd = 22, rarityBias = 2.8, rarityMin = 2, rarityMax = 5 },
}

GameConfig.Eggs = {}
for _, zb in ipairs(ZONE_EGG_BASE) do
	for _, tier in ipairs(EGG_TIERS) do
		table.insert(GameConfig.Eggs, {
			key = zb.zone .. tier.suffix .. "Egg",
			name = zb.zone .. " " .. tier.suffix .. " Egg",
			emoji = tier.emoji,
			cost = math.floor(zb.baseCost * tier.costMult),
			zone = zb.zone,
			tierSuffix = tier.suffix,
			luckBonus = zb.baseLuck + tier.luckAdd,
			rarityBias = tier.rarityBias,
			rarityMin = tier.rarityMin,
			rarityMax = tier.rarityMax,
		})
	end
end

function GameConfig.GetEggsForZone(zoneKey)
	local list = {}
	for _, egg in ipairs(GameConfig.Eggs) do
		if egg.zone == zoneKey then table.insert(list, egg) end
	end
	return list
end

-- `rarity` is optional so old call sites keep working; omitted means Common.
function GameConfig.GetPetBonus(tier, rarity)
	local mult = (GameConfig.PetTierMultiplier[tier] or 1) * GameConfig.GetRarity(rarity).bonusMult
	local base = GameConfig.PetBaseBonus
	return {
		incomeMult = 1 + (base.incomeMult - 1) * mult,
		luckAdd = base.luckAdd * mult,
		dnaMult = 1 + (base.dnaMult - 1) * mult,
		damageMult = 1 + (base.damageMult - 1) * mult,
	}
end

function GameConfig.GetNextTier(tier)
	for i, t in ipairs(GameConfig.PetTiers) do
		if t == tier then return GameConfig.PetTiers[i + 1] end
	end
	return nil
end

-- ===== HOW STRONG IS THIS PET =====
-- Every number GetPetBonus hands out is the same base bonus scaled by ONE product: the tier
-- multiplier times the rarity multiplier. So that product IS the pet's strength, and it is the
-- only honest key to rank a collection by. It lives here, once, because three call sites need the
-- same answer -- the row that prints "x12.8", the Equip Best that picks the top three, and the
-- fusion preview that shows what the next tier is worth -- and three private copies of it would
-- drift the first time the tier table changed.
-- Takes a SAVED pet ({ key, tier }), not a species def: tier is per-instance.
function GameConfig.GetPetPower(pet)
	if not pet then return 0 end
	local def = GameConfig.GetPetDef(pet.key)
	return (GameConfig.PetTierMultiplier[pet.tier] or 1) * GameConfig.GetRarity(def and def.rarity).bonusMult
end

-- Strongest first. Ties are broken by key, then tier, then id -- not left to table.sort -- so a
-- list of duplicates keeps the same order every refresh instead of shuffling under the cursor
-- while the player is reaching for a button.
function GameConfig.SortedPetsByPower(pets)
	local list = table.create(#pets)
	for _, p in ipairs(pets) do
		table.insert(list, p)
	end
	table.sort(list, function(a, b)
		local pa, pb = GameConfig.GetPetPower(a), GameConfig.GetPetPower(b)
		if pa ~= pb then return pa > pb end
		if a.key ~= b.key then return a.key < b.key end
		if a.tier ~= b.tier then return a.tier < b.tier end
		return tostring(a.id) < tostring(b.id)
	end)
	return list
end

-- The species one specific egg can hatch: its zone's five, sliced by the tier's rarity window.
-- Zone lists are positional (entry i is PetRarityOrder[i]), so the window is a plain index range.
function GameConfig.GetEggPool(egg)
	local zonePool = egg and GameConfig.PetsByZone[egg.zone]
	if not zonePool or #zonePool == 0 then return GameConfig.Pets end
	local out = {}
	for i, p in ipairs(zonePool) do
		if i >= (egg.rarityMin or 1) and i <= (egg.rarityMax or #zonePool) then
			table.insert(out, p)
		end
	end
	return #out > 0 and out or zonePool
end

-- Shared by the roll and by the odds the shop advertises, so the two can never disagree.
-- `luckPercent` and `rarityBias` (from the egg tier) both push toward the rarer end, scaled by
-- how rare a species already is -- luck lifts a Legendary far more than it lifts a Common.
local function poolWeights(pool, luckPercent, rarityBias)
	local maxWeight = 0
	for _, p in ipairs(pool) do
		maxWeight = math.max(maxWeight, GameConfig.GetRarity(p.rarity).weight)
	end

	local weights, total = {}, 0
	for i, p in ipairs(pool) do
		local base = GameConfig.GetRarity(p.rarity).weight
		local rarityFactor = 1 - (base / maxWeight) -- 0 for the commonest, ->1 for the rarest
		local boost = 1 + ((luckPercent or 0) / 100 + (rarityBias or 0)) * rarityFactor * 2
		weights[i] = base * boost
		total += weights[i]
	end
	return weights, total
end

function GameConfig.RollFromPool(pool, luckPercent, rarityBias)
	if not pool or #pool == 0 then pool = GameConfig.Pets end
	local weights, total = poolWeights(pool, luckPercent, rarityBias)
	local roll = math.random() * total
	local acc = 0
	for i, w in ipairs(weights) do
		acc += w
		if roll <= acc then return pool[i] end
	end
	return pool[1]
end

-- Kept for any caller that only knows a zone, with no egg in hand.
function GameConfig.RollPet(luckPercent, zoneKey, rarityBias)
	return GameConfig.RollFromPool(zoneKey and GameConfig.PetsByZone[zoneKey], luckPercent, rarityBias)
end

function GameConfig.RollPetForEgg(egg, luckPercent)
	return GameConfig.RollFromPool(GameConfig.GetEggPool(egg), luckPercent, egg and egg.rarityBias)
end

-- Odds a given egg actually presents, as percentages -- what the podium board shows.
function GameConfig.GetEggOdds(egg, luckPercent)
	local pool = GameConfig.GetEggPool(egg)
	local weights, total = poolWeights(pool, luckPercent, egg and egg.rarityBias)
	local out = {}
	for i, p in ipairs(pool) do
		out[i] = { def = p, chance = weights[i] / total * 100 }
	end
	return out
end

-- ===== REBIRTH =====
-- Rebirth unlocks every 5 stages (5, 10, 15, 20 -- "Tier" 1 through 4) instead of only at the
-- very end: you can cash in early for a small reward, or push further for a much bigger one.
-- It resets DNA, stage, upgrades, mutations, zones and boss kills, but keeps Pets, and grants
-- permanent Evolution Shards which give a small permanent income bonus that stacks forever.
GameConfig.RebirthTierSize = 5
GameConfig.RebirthRequirementStageIndex = GameConfig.RebirthTierSize -- stage 5 = earliest possible rebirth
GameConfig.MaxRebirthTier = math.floor(#GameConfig.Stages / GameConfig.RebirthTierSize) -- 20 / 5 = 4
GameConfig.ShardIncomeBonusPct = 2 -- each Evolution Shard = +2% income, forever

function GameConfig.GetShardIncomeBonusPct(shards)
	return (shards or 0) * GameConfig.ShardIncomeBonusPct
end

-- WHAT A REBIRTH IS ACTUALLY FOR.
--
-- It used to pay only Evolution Shards, worth +2% income each -- and income is DNA, which is never
-- the thing standing between a player and the next stage (XP is). So the whole mechanic cost a
-- full climb and bought a number that did not gate anything: a pure loss at every tier.
--
-- It pays PERMANENT DAMAGE now, which is the one currency the late game is short of -- the zone
-- bosses outscale the player's health curve, and damage is what shortens those fights. It also has
-- to be worth what the reset costs: the character collection is re-collected from scratch, and a
-- full collection is worth up to +600%, so a rebirth that paid less than that would be a trap in
-- a second costume.
--
-- +50% a run, permanent, stacking, and it is kept through every later rebirth.
-- ===== WHAT A REBIRTH IS WORTH, AND WHY IT ACCELERATES =====
--
-- It was a flat +50% a rebirth. That is not enough, and the reason is arithmetic rather than
-- taste: a rebirth WIPES the character collection, which is the damage ladder, worth up to +600%.
-- Trading a x7 for a x1.5 makes the second climb slower than the first, which is the opposite of
-- what the mechanic is for -- and it was reported that way, "after rebirthing I progress far too
-- slowly".
--
-- Quadratic, so each rebirth is worth MORE than the one before it. The last zones are the hardest
-- by a very long way (creature health runs x1 in Forest to x1050 on the Absolute Plane), so a
-- linear bonus falls further behind the wall every run; an accelerating one is what lets rebirth
-- number five actually reach the end of the strip.
--
--   1 -> x2.0    2 -> x3.0 (+1.0)    3 -> x4.5 (+1.5)    4 -> x6.5 (+2.0)    5 -> x9.0 (+2.5)
--
-- The first rebirth alone (x2.0) does not replace a full collection, and it is not meant to: the
-- collection is re-earned from kills as you climb, so the two stack back up together.
GameConfig.RebirthDamagePct = 100        -- the linear term, per rebirth
GameConfig.RebirthDamageAccelPct = 25    -- the quadratic term, what makes each one worth more

function GameConfig.GetRebirthDamageMult(data)
	if not data then return 1 end
	local r = data.Rebirths or 0
	return 1 + r * GameConfig.RebirthDamagePct / 100
		+ r * (r - 1) * GameConfig.RebirthDamageAccelPct / 100
end

-- Which rebirth tier (1-4) a given stage index has reached. Tier 0 = not eligible yet.
function GameConfig.GetRebirthTier(stageIndex)
	return math.floor((stageIndex or 0) / GameConfig.RebirthTierSize)
end

-- The inverse: the stage a given tier's checkpoint sits on, which is the creature whose statue
-- stands for that tier in the Rebirth Shrine (5 = Wolf, 10 = Cosmic Being, 15 = Reality
-- Architect, 20 = The Absolute). Clamped so a tier past the end of the chain still names a stage.
function GameConfig.GetRebirthTierStageIndex(tier)
	return math.clamp((tier or 1) * GameConfig.RebirthTierSize, 1, #GameConfig.Stages)
end

-- Shards earned by rebirthing right now, given the stage reached and how many rebirths the
-- player already has. Reward scales with the SQUARE of the tier reached, so pushing from
-- tier 1 (stage 5) to tier 4 (stage 20) is dramatically more rewarding than rebirthing early.
function GameConfig.GetRebirthShardReward(stageIndex, currentRebirths)
	local tier = GameConfig.GetRebirthTier(stageIndex)
	return tier * tier * 5 + (currentRebirths or 0) * 3
end

-- ===== DAILY REWARDS =====
-- 7-day cycle. Potions are introduced starting Day 3. Day 6 gives a bonus Shard, Day 7 is
-- the big one (DNA + Potions + Shards). Cycle repeats (day 8 = day 1 again).
-- Each day's DNA is ~2.2x the previous (even, predictable growth). Potions scale by +1
-- per day starting Day 3 (1,2,3,4,5), Diamonds by +1 starting Day 6 (1,2) -- no jumps.
GameConfig.DailyRewards = {
	{ day = 1, dna = 200 },
	{ day = 2, dna = 450 },
	-- `potionId` names which of the nine bottles the day hands over; the later days give bigger
	-- ones rather than simply more of the smallest, so the week reads as an escalation.
	{ day = 3, dna = 1000,  potions = 1, potionId = "dna_s" },
	{ day = 4, dna = 2200,  potions = 2, potionId = "xp_s" },
	{ day = 5, dna = 4800,  potions = 2, potionId = "luck_m" },
	{ day = 6, dna = 10500, potions = 2, potionId = "dna_m", diamonds = 1 },
	{ day = 7, dna = 23000, potions = 1, potionId = "dna_l", diamonds = 2, shards = 3 },
}

-- ===== POTIONS =====
-- There used to be ONE potion: a five-minute x2 on income, held as a single integer on the save.
-- Three effects in three sizes now -- nine bottles -- because a consumable with no choice in it is
-- just a delayed number, and because the three things a player actually wants to hurry are not the
-- same thing: DNA is the currency, XP is the evolve gate, and Luck is the whole egg/pet economy.
--
-- ONE ACTIVE BOTTLE PER KIND. Drinking a second DNA potion while one is running does not stack the
-- multiplier -- it takes the HIGHER of the two and adds the remaining time -- but a DNA, an XP and
-- a Luck potion all run at once. Stacking multipliers is how a consumable economy turns into a
-- single 'drink everything at hour three' decision; running three different effects together is a
-- choice about what to hurry.
--
-- `data.Potions` is a table keyed by potion id ('dna_s'), and `data.PotionBoosts` is keyed by KIND
-- ('dna'). Both are string-keyed on purpose: a table whose only keys are integers is a sparse array
-- and Roblox silently drops those crossing a RemoteEvent -- the bug that ate EquippedCharacters.
GameConfig.PotionKinds = {
	{ key = "dna",  name = "DNA",  emoji = "\u{1F9EC}", color = Color3.fromRGB(96, 200, 255),  blurb = "DNA from every source" },
	{ key = "xp",   name = "XP",   emoji = "\u{2B50}",   color = Color3.fromRGB(255, 206, 92),  blurb = "Evolution XP" },
	{ key = "luck", name = "Luck", emoji = "\u{1F340}", color = Color3.fromRGB(126, 226, 132), blurb = "egg, pet, character and mutation luck" },
}

-- Luck is an ADDITIVE percentage everywhere else in the game (upgrades give +2 a level, pets give
-- luckAdd), so a luck potion has to add too -- a multiplier on a stat that starts at zero does
-- nothing at all for a new player, which is exactly who buys the first one.
GameConfig.PotionSizes = {
	{ key = "s", name = "Small",  emoji = "\u{1F9EA}", minutes = 5,  mult = 2, luckAdd = 25,  costMult = 1 },
	{ key = "m", name = "Medium", emoji = "\u{2697}\u{FE0F}", minutes = 10, mult = 3, luckAdd = 55,  costMult = 2.8 },
	{ key = "l", name = "Large",  emoji = "\u{1F36F}", minutes = 20, mult = 5, luckAdd = 120, costMult = 7 },
}

-- The nine, built from the two lists above so a size or an effect can never be added to one and
-- forgotten in the other.
GameConfig.Potions = {}
GameConfig.PotionsById = {}
for _, kind in ipairs(GameConfig.PotionKinds) do
	for _, size in ipairs(GameConfig.PotionSizes) do
		local potion = {
			id = kind.key .. "_" .. size.key,
			kind = kind.key,
			size = size.key,
			name = size.name .. " " .. kind.name .. " Potion",
			shortName = size.name .. " " .. kind.name,
			emoji = kind.emoji,
			sizeEmoji = size.emoji,
			color = kind.color,
			minutes = size.minutes,
			seconds = size.minutes * 60,
			-- a luck bottle carries luckAdd and no multiplier; the other two carry the multiplier
			mult = (kind.key ~= "luck") and size.mult or nil,
			luckAdd = (kind.key == "luck") and size.luckAdd or nil,
			costMult = size.costMult,
			blurb = kind.blurb,
		}
		potion.effectText = potion.mult
			and ("x%d %s"):format(potion.mult, kind.blurb)
			or ("+%d%% %s"):format(potion.luckAdd, kind.blurb)
		table.insert(GameConfig.Potions, potion)
		GameConfig.PotionsById[potion.id] = potion
	end
end

-- What a grant with no id attached hands over (old saves, Daily Rewards, Robux bundles).
GameConfig.DefaultPotionId = "dna_s"

function GameConfig.GetPotion(id)
	return GameConfig.PotionsById[id]
end

-- The live boost for one kind, or nil. Expiry is checked HERE rather than by a timer, so a boost
-- that ran out while the player was offline is simply never returned and nothing has to clean up.
function GameConfig.GetPotionBoost(data, kind)
	local boost = data and data.PotionBoosts and data.PotionBoosts[kind]
	if not boost then return nil end
	if (boost.untilTs or 0) <= os.time() then return nil end
	return boost
end

-- 1 when nothing is running, so every caller can multiply unconditionally.
function GameConfig.GetPotionMult(data, kind)
	local boost = GameConfig.GetPotionBoost(data, kind)
	return (boost and boost.mult) or 1
end

-- Additive percentage points, matching every other luck source.
function GameConfig.GetPotionLuckAdd(data)
	local boost = GameConfig.GetPotionBoost(data, "luck")
	return (boost and boost.luckAdd) or 0
end

-- The one place a potion is added to a save. Every grant path -- shop, Daily Reward, playtime
-- gift, Robux bundle -- goes through it, so the number->table migration only had to be got right
-- once and an unknown id can never quietly create a bottle that does not exist.
function GameConfig.AddPotions(data, potionId, count)
	local potion = GameConfig.PotionsById[potionId] or GameConfig.PotionsById[GameConfig.DefaultPotionId]
	if type(data.Potions) ~= "table" then data.Potions = {} end
	data.Potions[potion.id] = (data.Potions[potion.id] or 0) + (count or 1)
	return potion
end

-- How many of everything a player is holding, for the HUD badge.
function GameConfig.CountPotions(data)
	local n = 0
	for _, count in pairs((data and data.Potions) or {}) do
		if type(count) == "number" then n += count end
	end
	return n
end

-- ===== BOSS EVENT ARENA =====
-- A separate arena reached through its own gate at the Forest spawn, holding one enormous boss
-- that returns on a timer. It exists because every other boss in the game is a solo wall you grind
-- past once: this one is far too big for any single player's damage, comes back whether or not it
-- was beaten, and pays every player who landed a hit rather than only the one who finished it.
--
-- The arena is parked straight through that gate, beyond the Forest platform's +Z boundary and
-- clear of its backdrop mesas.
--
-- THAT CLEARANCE IS THE WHOLE REASON FOR THE NUMBER. It was 900 on the strength of a comment
-- saying the mesas reach z ~ 389, which stopped being true when Forest got its backdrop: they
-- now top out at z = 723, and the arena's ground disc starts at centre - 302. At 900 that put a
-- row of 288-stud teal mesas standing INSIDE the Colosseum, directly behind the way home -- the
-- "the arena overlaps the portal" report. 1400 clears the tallest of them by ~375 studs, and
-- costs nothing: the only way in or out is a teleport, so distance is free.
GameConfig.EventArena = {
	key = "EventArena",
	name = "Colosseum",
	emoji = "\u{2694}\u{FE0F}",
	accentColor = Color3.fromRGB(255, 96, 72),
	groundColor = Color3.fromRGB(196, 176, 148),
	centre = Vector3.new(0, 0, 1400),
	radius = 210,
	-- where a player lands coming in, and which way they are turned: at the near edge, looking
	-- across the sand at the dais
	arrivalZ = 1400 - 168,
}

GameConfig.EventBoss = {
	name = "The Devourer",
	emoji = "\u{1F479}",
	-- Nearly twice the last zone boss (68) and four times the first. The whole point of the event
	-- is a silhouette you can see from the gate.
	size = 124,
	health = 25000000,
	dnaReward = 60000000,
	-- Paid to EVERY player who landed a hit, not split between them -- an event that pays less the
	-- more people turn up is an event nobody turns up to. Generous on purpose: a 25M-health raid is
	-- worth several levels to anyone strong enough to be there. BossService clamps it to two of the
	-- RECEIVING player's levels, so a stage-2 player who lands one hit does not skip half the chain.
	xpReward = 20000,
	retaliateChance = 0.5,
	retaliateDamage = { 240, 420 },
	auraRange = 60,
	auraDamage = { 60, 110 },
	auraInterval = 1.4,
	-- how often it returns, and how long it stays if nobody finishes it
	intervalSeconds = 1800, -- 30 minutes
	despawnSeconds = 900,   -- 15 minutes on the sand, then it leaves
	-- a player under this stage can walk in and watch, but cannot hit it
	minStageIndex = 4,
}

-- ===== WHICH SHOP STANDS IN WHICH ZONE =====
-- Every one of the twenty villages used to carry the same three potion counters -- a market stall,
-- a supply stall and a cauldron -- which meant the shop was never a reason to go anywhere. There
-- are eight shops in the whole strip now and each is the only one of its kind you will pass for a
-- while, so walking into a zone that has one is an event.
--
-- Keyed by zone INDEX (= evolution stage), which is how the strip is actually ordered. The zone
-- named beside each entry is what that index resolves to today; the index is what decides.
GameConfig.ZoneShops = {
	-- Mystery Potions: one every four zones, first at 3 (the first two are the tutorial stretch
	-- and stay deliberately plain, which is where the old cauldron started too).
	[3]  = "mystery",  -- Ocean
	[7]  = "mystery",  -- Galaxy
	[11] = "mystery",  -- Wormhole
	[15] = "mystery",  -- Dream Dimension
	[19] = "mystery",  -- Singularity
	-- Pet Fusion, at the two points where a player has been hatching long enough to be holding
	-- duplicates worth fusing.
	-- MOVED 5 -> 4. The Fusion panel has exactly ONE door in the whole game -- this counter -- so
	-- until a player reaches the zone holding it, the feature does not appear to exist. That is how
	-- it was reported: "am I missing pet fusion, where is it, I am already on stage 4". By Volcano
	-- you have walked three egg stalls and are holding duplicates worth fusing.
	[4]  = "fusion",   -- Volcano
	[10] = "fusion",   -- Nebula
	-- The one place in the game that sells permanent power, for the two currencies that buy it.
	[8]  = "upgrades", -- Black Hole
}

-- `panel` is the MainUI panel a shop's counter opens; nil means the shop does its own work through
-- a server prompt instead (the mystery shop charges DNA and rolls a bottle).
GameConfig.ShopKinds = {
	mystery = {
		name = "Mystery Potions", emoji = "\u{1F52E}", title = "\u{1F52E} MYSTERY POTIONS",
		color = Color3.fromRGB(168, 96, 240),
		tagline = "One sealed bottle. You find out what it is when you drink it.",
	},
	fusion = {
		name = "Pet Fusion Lab", emoji = "\u{1F9EC}", title = "\u{1F9EC} PET FUSION LAB",
		color = Color3.fromRGB(255, 108, 168),
		panel = "pets",
		tagline = "Fuse duplicate pets into their next tier.",
	},
	upgrades = {
		name = "Upgrade Emporium", emoji = "\u{1F48E}", title = "\u{1F48E} UPGRADES",
		color = Color3.fromRGB(120, 200, 255),
		-- two counters, one per currency -- see ZoneBuilder
		counters = {
			{ panel = "mastery", actionText = "Diamond Upgrades", objectText = "\u{1F48E} Stage Mastery" },
			{ panel = "robux",   actionText = "Robux Upgrades",   objectText = "\u{1F6CD}\u{FE0F} Robux Shop" },
		},
		tagline = "Permanent power, in Diamonds and in Robux.",
	},
}

function GameConfig.GetZoneShop(zoneIndex)
	local key = GameConfig.ZoneShops[zoneIndex]
	if not key then return nil end
	return key, GameConfig.ShopKinds[key]
end

-- ===== THE MYSTERY POTION SHOP =====
-- One price, one sealed bottle, and which of the nine it turns out to be is the whole product.
-- The kind is rolled evenly across the three -- a player who wants a specific effect is buying the
-- wrong shop, and that is the point of it being the cheap one.
--
-- `costMult` multiplies the zone's mid-tier egg price, so the shop stays meaningful at every point
-- along the strip rather than being free by zone six.
GameConfig.MysteryShop = {
	-- 3x the mid-tier egg, where the old guaranteed cauldron bottle was 2.5x. The roll averages
	-- about 1.6 small-bottles' worth, so per DNA this is the better buy -- which it has to be:
	-- there are five of these in the whole game and reaching one is a walk.
	costMult = 3,
	minCost = 1200,
	-- Weighted toward the small bottle, with the twenty-minute one rare enough to be worth the
	-- walk. Luck shifts this -- see RollMysteryPotion -- so the luck economy reaches the shop too.
	sizeRolls = {
		{ size = "s", weight = 66 },
		{ size = "m", weight = 27 },
		{ size = "l", weight = 7 },
	},
}

-- Returns the potion id and how many bottles. Luck lifts the bigger sizes only -- the same shape
-- the egg pools use, where the rarer an outcome already is the more luck moves it.
function GameConfig.RollMysteryPotion(luckPercent)
	local rolls = GameConfig.MysteryShop.sizeRolls
	local weights, total = {}, 0
	for i, r in ipairs(rolls) do
		-- i = 1 is the small bottle and is never boosted; the step up per size is what luck buys
		local w = r.weight * (1 + ((luckPercent or 0) / 100) * (i - 1) * 0.6)
		weights[i] = w
		total += w
	end
	local pick = math.random() * total
	local size = rolls[1].size
	for i, r in ipairs(rolls) do
		pick -= weights[i]
		if pick <= 0 then size = r.size break end
	end
	local kinds = GameConfig.PotionKinds
	local kind = kinds[math.random(1, #kinds)].key
	return kind .. "_" .. size
end

function GameConfig.GetMysteryCost(zoneKey)
	local eggs = GameConfig.GetEggsForZone(zoneKey)
	local base = (eggs[2] and eggs[2].cost) or 1500
	return math.max(GameConfig.MysteryShop.minCost, math.floor(base * GameConfig.MysteryShop.costMult))
end

-- "7% chance of the twenty-minute one" is the part of a gamble a player actually wants to see, so
-- the shop's board is built from the same table the roll reads.
function GameConfig.GetMysteryOddsText()
	local rolls = GameConfig.MysteryShop.sizeRolls
	local total = 0
	for _, r in ipairs(rolls) do total += r.weight end
	local parts = {}
	for _, r in ipairs(rolls) do
		local size
		for _, s in ipairs(GameConfig.PotionSizes) do if s.key == r.size then size = s end end
		table.insert(parts, ("%s %d%%"):format(size and size.name or r.size, math.floor(r.weight / total * 100 + 0.5)))
	end
	return table.concat(parts, "   ")
end

-- ===== DIAMONDS =====
-- Premium currency, separate from DNA and Evolution Shards. Earned from Daily Rewards
-- (Day 6+) and spent on the 3 Diamond Upgrades below -- permanent, powerful, and priced
-- in Diamonds instead of DNA so they stay a long-term grind, not an early-game shortcut.
GameConfig.DiamondUpgrades = {
	MegaIncome = { displayName = "Mega Income", emoji = "💎", baseCost = 5,  costMult = 1.6, effectPct = 10, description = "+10% permanent income per level" },
	MegaLuck   = { displayName = "Mega Luck",   emoji = "🍀", baseCost = 8,  costMult = 1.6, effectAdd = 5,  description = "+5% Luck per level" },
	PetSlot    = { displayName = "Pet Slot",    emoji = "🐾", baseCost = 15, costMult = 2.2, effectAdd = 1, maxLevel = 3, description = "+1 equipped pet slot per level (max 3)" },
}

-- ===== DIAMONDS FROM PLAYING =====
--
-- Until now Diamonds had no gameplay source at all. Every one of them came from a time gate --
-- the daily reward, a playtime milestone, a Season Pass tier -- or from a Robux product, and every
-- RobuxProducts entry still has `productId = 0`, so that route does not work either. A player who
-- simply plays the game could not earn the currency that three permanent upgrades and twenty Stage
-- Masteries are priced in.
--
-- A per-kill roll fixes that without touching any existing balance: it adds a currency rather than
-- multiplying an existing one.
--
-- WEIGHTED BY TIER, NOT BY STAGE. Deliberately: kill RATE already rises steeply with stage, so a
-- flat per-kill chance pays out faster and faster on its own. Tying the odds to the target instead
-- makes the tougher creature the one worth hunting and keeps the curve honest.
--
-- ===== THESE ODDS WERE TOO LOW TO BE A FEATURE =====
--
-- The first cut was sized purely against the sink: 0.003-0.040 by tier, an expected 0.0068 diamonds
-- a kill, "one every five minutes". The arithmetic was right and the design was wrong, and the
-- report was the flat sentence "I never get diamonds, I cannot earn them at all".
--
-- A 0.3% drop is invisible. A player kills two hundred Swarmers, sees nothing, and correctly
-- concludes the mechanic does not exist -- there is no partial credit and no counter ticking up, so
-- below some floor a random drop is indistinguishable from a bug. The floor is roughly "often
-- enough to happen inside one session at one spot", and 0.3% is nowhere near it.
--
-- 10x across the board. At the same 30 kills a minute and the same tier mix that is ~0.068 a kill,
-- i.e. **two a minute**: a Swarmer pays about one time in thirty, an Elite one time in three. The
-- mechanic is now legible from the first few minutes of play, which is what it has to be to read as
-- a reward at all. The sink is what should absorb this, not the source -- see DiamondUpgrades.
GameConfig.DiamondDropChance = {
	Swarmer = 0.03,
	Critter = 0.06,
	Brute    = 0.15,
	Elite    = 0.40,
}

-- ===== BOSSES ALWAYS PAY, AND THEY PAY A HANDFUL =====
--
-- A boss had NO diamond source at all -- neither the zone bosses nor the Colosseum giant -- so the
-- one fight in the game that takes real effort was worth less in this currency than farming
-- Swarmers. That is backwards, and it is the other half of what was reported.
--
-- A boss is not a roll. It is a rare, scheduled, expensive fight, so it is a GUARANTEED payout and
-- the variance lives in the amount. Zone bosses give 3-6; the Colosseum giant, which is on a
-- 30-minute timer and shared between everyone present, gives 12-20.
GameConfig.BossDiamondReward = { 3, 6 }
GameConfig.EventBossDiamondReward = { 12, 20 }

function GameConfig.RollDiamondDrop(tierName)
	local chance = GameConfig.DiamondDropChance[tierName or ""] or 0
	return math.random() < chance and 1 or 0
end

-- `event` picks the Colosseum giant's band instead of a zone boss's. Guaranteed, never zero.
function GameConfig.RollBossDiamonds(event)
	local band = event and GameConfig.EventBossDiamondReward or GameConfig.BossDiamondReward
	return math.random(band[1], band[2])
end

function GameConfig.GetDiamondUpgradeCost(key, level)
	local def = GameConfig.DiamondUpgrades[key]
	if not def then return math.huge end
	if def.maxLevel and level >= def.maxLevel then return math.huge end
	return math.floor(def.baseCost * (def.costMult ^ level))
end

function GameConfig.GetMaxEquippedPets(data)
	local petSlotLevel = data.DiamondUpgrades and data.DiamondUpgrades.PetSlot or 0
	-- The +3 Pet Slots pass stacks ON TOP of the diamond upgrade rather than replacing it: the
	-- upgrade is capped at 3 levels, so a player who bought all three and then bought the pass has
	-- spent in both currencies and should get both. 3 base + 3 diamond + 3 pass = 9.
	return GameConfig.MaxEquippedPets + petSlotLevel + GameConfig.GetPassAdd(data, "petSlots")
end

-- ===== STAGE MASTERY =====
-- One permanent, Diamond-priced unlock per evolution stage: reach a stage and you may buy its
-- Mastery, once, forever. Where the three Diamond Upgrades above are levelled infinitely, these
-- are twenty separate one-shot purchases -- a checklist that fills in as you climb.
--
-- Deliberately NOT reset by Rebirth (see RebirthService, which clears stages, zones and bosses).
-- That is the whole point: Rebirth throws you back to Cell, and Mastery is what makes the second
-- climb faster than the first.
--
-- Every Mastery grants the same bonus no matter which stage it belongs to; only the price scales.
-- That keeps the early ones worth mopping up late -- they are the cheap ones still on the board --
-- instead of the list collapsing into "only the last three matter".
-- Roblox's default 16 is a crawl on a 450x550 platform with a shop at one end and a boss at the
-- other, and it made the whole strip feel like wading. Mastery stacks on top of this.
GameConfig.BaseWalkSpeed = 34
-- Deliberately BELOW Roblox's default 50. The character used to leave the ground higher than the
-- shop awnings, which reads as a platformer rather than a tycoon and made every fall off the
-- platform edge the player's own doing. Everything a player has to get on top of is low: the plaza
-- deck is 3 studs, the podium 6, the shop steps 2 each. 44 clears 4.9 studs at stage one and, with
-- the size multiplier at the top stage, about 11 -- enough for every step in the game and nothing
-- more.
GameConfig.BaseJumpPower = 44

-- ===== SPEED SCALES WITH THE BODY =====
-- The single biggest reason movement read as sluggish. A player's body runs 1x -> 9x across the
-- twenty stages (see GameConfig.Stages[].scale) while the walk speed stayed at one constant, so a
-- Human-stage character nineteen studs tall was crossing the ground at the same studs/second a
-- one-stud Cell did. Apparent speed is studs per second divided by body height: at 3.8x that is a
-- quarter of the pace the same number gives at 1x, which is exactly what "wading" feels like.
--
-- Strict proportionality (speed = base * scale) would put the last stage at over 300 studs/second,
-- which outruns StreamingEnabled and turns the strip into a slideshow of ungenerated ground. The
-- exponent keeps the early stages honest and flattens the top, and the caps are the hard ceiling.
-- The caps are set where they are because of what sits under them. 150 studs/s crosses the 860-stud
-- platform in under six seconds, which StreamingEnabled keeps up with; much past that and a player
-- outruns the ground they are running on. 92 of jump power is 21 studs of height, nowhere near
-- the 180-stud zone walls -- a jump that clears a boundary drops the player into the gap between
-- two platforms, where there is no floor at all.
--
-- THE BODY SCALE CURVE WAS HALVED at the same time: GameConfig.Stages[].scale now runs 1.0 -> 5.0
-- where it used to run 1.0 -> 9.0. A late-stage player was tall enough that a whole platform read
-- as a small room, and every prop beside them looked like furniture in a doll's house. The growth
-- is still monotonic and every evolve is still visible; it is the top of the curve that came down.
GameConfig.SpeedScaleExponent = 0.82
GameConfig.MaxWalkSpeed = 150
GameConfig.MaxJumpPower = 92

-- How much of the size a character actually gets back as pace. Shared by walk and jump so a giant
-- that covers ground quickly can also still clear its own shop steps.
function GameConfig.GetSizeSpeedMultiplier(bodyScale)
	local s = math.max(tonumber(bodyScale) or 1, 1)
	return s ^ GameConfig.SpeedScaleExponent
end

GameConfig.StageMastery = {
	baseCost = 3,
	costGrowth = 1.22, -- stage 1 costs 3 diamonds, stage 20 costs 135; ~700 for the full set
	damagePct = 12,    -- +12% combat damage each
	-- Was 0.8. One Mastery took you from 16.0 to 16.8 studs/second, which nobody can feel -- the
	-- button read as broken even though it was working, because the only visible effect was a
	-- number in a tooltip. At 1.8 a single purchase is unmistakable and the full set roughly
	-- doubles the base again.
	walkSpeed = 1.8,   -- +1.8 studs/second each (all 20 = +36)
	jumpPower = 1.2,   -- +1.2 each (all 20 = +24), so mastery is felt vertically too
	healthPct = 5,     -- +5% max health each
}

function GameConfig.GetStageMasteryCost(stageIndex)
	local m = GameConfig.StageMastery
	return math.floor(m.baseCost * (m.costGrowth ^ (stageIndex - 1)))
end

-- Stored as a list of stage indices rather than a keyed set, matching DefeatedBosses: DataStore
-- round-trips arrays cleanly, where a table with sparse integer keys comes back with string keys.
function GameConfig.HasStageMastery(data, stageIndex)
	for _, i in ipairs(data.MasteredStages or {}) do
		if i == stageIndex then return true end
	end
	return false
end

-- Combined effect of everything mastered so far. One table because the three callers -- combat
-- damage, walk speed and max health -- each want a different field off the same count.
function GameConfig.GetStageMasteryBonus(data)
	local owned = #(data.MasteredStages or {})
	local m = GameConfig.StageMastery
	return {
		owned = owned,
		damageMult = 1 + owned * (m.damagePct / 100),
		walkSpeed = owned * m.walkSpeed,
		jumpPower = owned * (m.jumpPower or 0),
		healthMult = 1 + owned * (m.healthPct / 100),
	}
end

-- ===== PLAYTIME GIFTS =====
-- Session-based (not persisted): the longer a player stays connected in one sitting, the
-- better the gift waiting for them. Resets to Day-1-style milestones each time they rejoin.
GameConfig.PlaytimeGifts = {
	{ minutes = 10, dna = 1000 },
	{ minutes = 20, dna = 2500,  potions = 1, potionId = "dna_s" },
	{ minutes = 30, dna = 6000,  potions = 1, potionId = "xp_m" },
	{ minutes = 45, dna = 15000, diamonds = 1 },
	{ minutes = 60, dna = 35000, potions = 1, potionId = "luck_l", diamonds = 2 },
}

-- ===== ROBUX SHOP =====
-- Real-money packages bought with Robux via MarketplaceService Developer Products.
-- IMPORTANT: productId = 0 is a placeholder. Each of these must be created for real as a
-- Developer Product on the Roblox Creator Dashboard (Create > this game > Monetization >
-- Developer Products) -- that step can't be done from a script, only from the website by
-- the game owner. Once created, replace the matching productId below with the real numeric ID.
GameConfig.RobuxProducts = {
	{ key = "DNA_Small",   productId = 0, name = "1,000 DNA",   emoji = "🧬", grantDNA = 1000 },
	{ key = "DNA_Large",   productId = 0, name = "10,000 DNA",  emoji = "🧬", grantDNA = 10000 },
	{ key = "Potions_3",   productId = 0, name = "Potion Pack",   emoji = "🧪", grantPotions = 3, grantPotionId = "dna_m" },
	{ key = "Potions_10",  productId = 0, name = "Potion Crate",  emoji = "🧪", grantPotions = 4, grantPotionId = "dna_l" },
	{ key = "Diamonds_10", productId = 0, name = "10 Diamonds", emoji = "💎", grantDiamonds = 10 },
	{ key = "Diamonds_50", productId = 0, name = "50 Diamonds", emoji = "💎", grantDiamonds = 50 },
	-- The Season Pass premium track. `grantSeasonPremium` is read by RobuxShopService's
	-- ProcessReceipt; buying it late is safe, because every premium reward already reached stays
	-- claimable (see SeasonPassService.GrantPremium).
	{ key = "SeasonPremium", productId = 0, name = "Premium Season Pass", emoji = "\u{1F39F}\u{FE0F}", grantSeasonPremium = true },
}

function GameConfig.GetRobuxProduct(key)
	for _, p in ipairs(GameConfig.RobuxProducts) do
		if p.key == key then return p end
	end
	return nil
end

-- THE ONE XP MULTIPLIER. The creature kill and the boss kill each called GetPotionMult(data, "xp")
-- directly, so the 2x XP pass would have had to be added in two places and kept in step with itself
-- forever -- and a third XP source added later would have quietly missed both. Everything that
-- scales XP goes through here now.
function GameConfig.GetXPMult(data)
	return GameConfig.GetPotionMult(data, "xp") * GameConfig.GetPassMult(data, "xpMult")
end

-- ===== GAME PASSES =====
-- One-off, permanent, account-wide Robux purchases -- as opposed to the consumable Developer
-- Products above. Same placeholder rule: `passId = 0` until the pass is created for real on the
-- Creator Dashboard (Create > this game > Monetization > Passes) and its numeric id pasted in.
-- PassService refuses to prompt on a zero id rather than opening a dialog that cannot complete.
--
-- EVERY EFFECT IS A FIELD READ BY GetPassMult / GetPassAdd BELOW, never a special case at the call
-- site. That is what lets the 2x DNA pass and the VIP bundle both raise income without either hook
-- knowing the other exists, and it is why a tenth pass needs no new code anywhere -- only a row.
--
-- Three decisions worth not re-litigating:
--
-- 1. LUCK IS ADDITIVE, NOT A MULTIPLIER. Every other luck source in this game adds percentage
--    points (the Luck upgrade +2 a level, pet `luckAdd`, the Luck potion) and luck starts at ZERO.
--    A "2x Luck" pass would therefore do literally nothing for a new player -- the exact person
--    most likely to buy it. See DNAService.GetLuckPercent, which is the one function eggs, pets,
--    characters, mutations and crit chance all read.
--
-- 2. AUTO-ATTACK ITSELF STAYS FREE. It already ships free on the `AutoAttack` attribute and the T
--    key. Paywalling something players already have is the fastest way to lose them, so FastAuto
--    sells the swing RATE instead -- new value rather than confiscated value.
--
-- 3. ORDERED CHEAPEST FIRST, and the cheapest is deliberately a small quality-of-life pass. Across
--    the genre the entry pass is what converts a non-payer into a payer; the multipliers are where
--    the money actually is, but almost nobody buys one first.
GameConfig.GamePasses = {
	-- `walkCap` lifts GameConfig.MaxWalkSpeed for this player. Without it the pass is a lie for most
	-- of the game: the cap is 150, and an unbought stage-20 body already runs 127, so a 2x would have
	-- delivered 1.18x at the top and a true 2x only through stage 7 of 20. 260 covers the doubled
	-- top-stage speed (254.5) with a little headroom. The cap exists to stop a player outrunning
	-- StreamingEnabled, which is why lifting it is a deliberate, measured decision and not a default.
	{ key = "Speed2x",   passId = 0, price = 99,  emoji = "🏃", name = "2x Speed",
	  desc = "Move twice as fast, in every zone.", walkMult = 2, walkCap = 260 },

	{ key = "XP2x",      passId = 0, price = 149, emoji = "⭐", name = "2x XP",
	  desc = "Every kill fills the evolve bar twice as fast.", xpMult = 2 },

	{ key = "AutoHatch", passId = 0, price = 149, emoji = "🥚", name = "Auto Hatch",
	  desc = "Eggs keep hatching while you stand at the stall.", autoHatch = true },

	{ key = "DNA2x",     passId = 0, price = 199, emoji = "🧬", name = "2x DNA",
	  desc = "Double DNA from clicks, kills and idle income.", incomeMult = 2 },

	{ key = "Damage2x",  passId = 0, price = 199, emoji = "⚔️", name = "2x Damage",
	  desc = "Hit twice as hard. Bosses die in half the swings.", damageMult = 2 },

	{ key = "FastAuto",  passId = 0, price = 199, emoji = "⚡", name = "Fast Auto Attack",
	  desc = "Your auto attack swings 70% faster.", autoSpeedMult = 1.7 },

	{ key = "Lucky",     passId = 0, price = 249, emoji = "🍀", name = "Lucky",
	  desc = "+50% Luck on every egg, pet and mutation roll.", luckAdd = 50 },

	{ key = "PetSlots3", passId = 0, price = 299, emoji = "🐾", name = "+3 Pet Slots",
	  desc = "Equip three more pets at once.", petSlots = 3 },

	{ key = "VIP",       passId = 0, price = 499, emoji = "👑", name = "VIP",
	  desc = "1.5x DNA and damage, +15% Luck, a golden aura, a chat tag and 5 Diamonds a day.",
	  incomeMult = 1.5, damageMult = 1.5, luckAdd = 15, dailyDiamonds = 5, vip = true },
}

function GameConfig.GetGamePass(key)
	for _, p in ipairs(GameConfig.GamePasses) do
		if p.key == key then return p end
	end
	return nil
end

-- `data.Passes` is a RUNTIME cache written by PassService on join and on purchase. It is never
-- trusted out of the save -- PlayerDataService clears it on load -- so a missing or empty table
-- means "owns nothing", which is the correct fail-closed answer when the ownership check could not
-- be completed. Reading it here rather than taking a `player` is the whole reason none of the stat
-- functions had to change signature: GetIncomeMult, GetLuckPercent, GetCombatDamage and
-- GetMaxEquippedPets all already take `data`.
function GameConfig.OwnsPass(data, key)
	return (data and data.Passes and data.Passes[key]) == true
end

-- Product of `field` across every owned pass, or 1 when none of them carries it. Multiplicative on
-- purpose: a player holding both 2x DNA and VIP gets 3x, which is the entire reason to own two.
function GameConfig.GetPassMult(data, field)
	if not (data and data.Passes) then return 1 end
	local mult = 1
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] then
			mult = mult * p[field]
		end
	end
	return mult
end

-- Highest `field` across every owned pass, or `fallback`. BEST-ONE-APPLIES, the same rule
-- GetMutationIncomeMult uses -- for a value that is a ceiling rather than a contribution, summing
-- two of them would be meaningless and multiplying them would be worse.
function GameConfig.GetPassMax(data, field, fallback)
	local best = fallback or 0
	if not (data and data.Passes) then return best end
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] and p[field] > best then
			best = p[field]
		end
	end
	return best
end

-- Sum of `field` across every owned pass, or 0. For the stats measured in points rather than in
-- factors -- luck and pet slots today.
function GameConfig.GetPassAdd(data, field)
	if not (data and data.Passes) then return 0 end
	local total = 0
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] then
			total = total + p[field]
		end
	end
	return total
end

-- ============================================================================
-- SEASON PASS
-- ============================================================================
-- A thirty-level track that fills with Season XP, and Season XP comes from ONE place: completing
-- daily and weekly quests. Nothing else pays it. That is the whole design -- the pass is the
-- reason to come back tomorrow, and the quests are the reason to play today.
--
-- Two rows of rewards per level, exactly like the board this is modelled on: a FREE row everybody
-- collects, and a PREMIUM row that unlocks in one purchase and pays out retroactively for every
-- level already reached.
--
-- `id` is the reset switch. Bump it and every player's progress, claims and premium flag start
-- over on their next join -- see SeasonPassService, which migrates lazily rather than needing a
-- scheduled job or a live server at the moment a season turns over.
GameConfig.Season = {
	id = "S1",
	name = "Season 1: First Light",
	emoji = "\u{1F39F}\u{FE0F}",
	maxLevel = 30,
	-- flat, not a curve. A rising per-level cost makes the back half of a pass feel like a wall,
	-- and the quests already scale the income side.
	xpPerLevel = 1500,
}

-- Level from total XP. Level 1 is the floor -- a pass at 0 XP is "Level 1, 0/1500", never level 0.
function GameConfig.GetSeasonLevel(xp)
	local level = 1 + math.floor((xp or 0) / GameConfig.Season.xpPerLevel)
	return math.min(level, GameConfig.Season.maxLevel)
end

-- XP into the current level, and how much that level needs. At max level both are the same
-- number, so the bar reads full instead of dividing by a level that does not exist.
function GameConfig.GetSeasonLevelProgress(xp)
	xp = xp or 0
	local per = GameConfig.Season.xpPerLevel
	if GameConfig.GetSeasonLevel(xp) >= GameConfig.Season.maxLevel then
		return per, per
	end
	return xp % per, per
end

-- The thirty rows, generated rather than hand-typed for the same reason the eggs are: thirty
-- literal tables drift the moment one number in the ramp changes.
--
-- DNA is the filler and is deliberately the WEAKEST part of the reward -- income scales so hard
-- across twenty stages that any fixed DNA figure is either trivial or game-breaking depending on
-- who reads it. The things worth having are the ones the economy cannot inflate: potions,
-- Diamonds and Evolution Shards.
GameConfig.SeasonRewards = {}
do
	local POTION_BY_BAND = { "dna_s", "xp_s", "luck_m", "dna_m", "xp_m", "luck_l" }
	for level = 1, GameConfig.Season.maxLevel do
		local band = math.min(math.ceil(level / 5), #POTION_BY_BAND)
		local dna = math.floor(400 * (1.95 ^ (level - 1)))

		local free = { dna = dna }
		-- one bottle every fourth level, and a Diamond payout at each of the three round numbers
		if level % 4 == 0 then
			free.potions, free.potionId = 1, POTION_BY_BAND[band]
		end
		if level == 10 then free.diamonds = 2 end
		if level == 20 then free.diamonds = 3 end
		if level == 30 then free.diamonds = 5 end

		-- Premium is the same shape, three times the DNA, a bottle twice as often, Diamonds every
		-- fifth level and the only Shards on the board.
		local premium = { dna = dna * 3 }
		if level % 2 == 0 then
			premium.potions, premium.potionId = 2, POTION_BY_BAND[band]
		end
		if level % 5 == 0 then premium.diamonds = 3 + math.floor(level / 5) end
		if level == 15 then premium.shards = 5 end
		if level == 30 then premium.shards = 15 end

		GameConfig.SeasonRewards[level] = {
			level = level,
			free = free,
			premium = premium,
			-- every tenth level is drawn bigger on the track
			milestone = (level % 10 == 0),
		}
	end
end

function GameConfig.GetSeasonReward(level)
	return GameConfig.SeasonRewards[level]
end

-- ===== QUESTS =====
-- Every player gets the SAME list every period. No random draw and no per-player seed to store:
-- a rolled quest board means somebody opens the panel to three tasks they cannot do from where
-- they are standing, and it makes the save a great deal more fragile for nothing.
--
-- `counter` is the name SeasonPassService.Track is called with. All four already happen on paths
-- that write to the save anyway -- a creature dying, a boss falling, an egg hatching, a fusion --
-- so tracking costs no new events and no extra replication.
GameConfig.QuestPool = {
	daily = {
		{ key = "d_creatures", counter = "creatures", target = 50, emoji = "\u{2694}\u{FE0F}", name = "Defeat 50 creatures",   xp = 250 },
		{ key = "d_eggs",      counter = "eggs",      target = 10, emoji = "\u{1F95A}",        name = "Hatch 10 eggs",          xp = 300 },
		{ key = "d_bosses",    counter = "bosses",    target = 3,  emoji = "\u{1F451}",        name = "Defeat 3 bosses",        xp = 350 },
		{ key = "d_fuse",      counter = "fuse",      target = 2,  emoji = "\u{1F9EC}",        name = "Fuse 2 pets",            xp = 200 },
	},
	weekly = {
		{ key = "w_creatures", counter = "creatures", target = 500, emoji = "\u{2694}\u{FE0F}", name = "Defeat 500 creatures", xp = 1200, diamonds = 2 },
		{ key = "w_bosses",    counter = "bosses",    target = 20,  emoji = "\u{1F451}",        name = "Defeat 20 bosses",    xp = 1500, diamonds = 3 },
		{ key = "w_eggs",      counter = "eggs",      target = 60,  emoji = "\u{1F95A}",        name = "Hatch 60 eggs",       xp = 1400, diamonds = 2 },
	},
}

GameConfig.QuestPeriods = {
	-- Bucket arithmetic, not a stored timer: the period a moment belongs to is a pure function of
	-- the clock, so a reset needs no live server and cannot be missed by a player who was offline
	-- when it happened. (The Unix epoch was a Thursday, so the weekly bucket turns over on a
	-- Thursday at 00:00 UTC.)
	daily  = { seconds = 86400,  label = "Daily",  emoji = "\u{2600}\u{FE0F}" },
	weekly = { seconds = 604800, label = "Weekly", emoji = "\u{1F4C5}" },
}

function GameConfig.GetQuests(period)
	return GameConfig.QuestPool[period] or {}
end

function GameConfig.GetQuestPeriodId(period, now)
	local def = GameConfig.QuestPeriods[period]
	if not def then return 0 end
	return math.floor((now or os.time()) / def.seconds)
end

-- When the current period rolls over, as a unix timestamp -- the countdown the panel prints.
function GameConfig.GetQuestPeriodEnd(period, now)
	local def = GameConfig.QuestPeriods[period]
	if not def then return 0 end
	return (GameConfig.GetQuestPeriodId(period, now) + 1) * def.seconds
end

function GameConfig.GetQuestDef(period, questKey)
	for _, q in ipairs(GameConfig.GetQuests(period)) do
		if q.key == questKey then return q end
	end
	return nil
end

-- ===== HELPER FUNCTIONS =====

-- A FIXED DNA REWARD IS MEANINGLESS IN AN ECONOMY THAT SPANS 1e2 TO 1e17.
--
-- The daily login track tops out at 23,000 DNA and the playtime ladder at 35,000. One Mars
-- creature pays 24,150 -- so from stage 6, about fifteen minutes in, the ENTIRE seven-day login
-- cycle is worth less than a single kill, and every login reward after that is a rounding error
-- dressed up as a prize. The Season track has the opposite half of the same problem: its early
-- levels hand a brand-new player one or two whole stages instantly, and its level-30 payout is
-- 0.003 of one creature by the time anyone reaches it.
--
-- The authored numbers are not wrong -- they are a well-shaped ladder AT STAGE ONE, and each
-- reward's size relative to the others is the design. What is missing is the same growth curve
-- everything else in the game is on. So the authored figure is read as "how many stage-1 clicks
-- this is worth" and converted to what that is worth where the player actually stands.
--
-- Scaled RELATIVE TO STAGE ONE, which is what the tables were authored against: at stage 1 the
-- multiplier is exactly 1 and every reward pays precisely what its card says, and from there it
-- rides the same GetClickBase curve the rest of the income does. A reward is therefore worth the
-- same number of KILLS at stage 20 as it was at stage 1, which is the property that was missing.
--
-- A square root was tried first and is wrong: it decays against the curve it is meant to follow,
-- so the day-7 login still fell from 1,681 kills to 0.1 across the twenty stages -- a smaller
-- version of the same bug rather than a fix for it.
--
-- Floored at 1 so nothing can ever pay LESS than it says on the card.
function GameConfig.ScaleReward(amount, data)
	local stageIndex = (data and data.StageIndex) or 1
	local mult = math.max(GameConfig.GetClickBase(stageIndex) / GameConfig.GetClickBase(1), 1)
	return math.floor((amount or 0) * mult)
end

-- WHAT THE SPEED UPGRADE DOES. Until this existed: nothing.
--
-- `Speed` is the cheapest upgrade in the game (25 DNA) and the first one in the shop's order, so
-- it is the first purchase almost every new player makes -- and no line anywhere in the game ever
-- read `data.Upgrades.Speed`. The level went up, the cost went up, and the character moved at
-- exactly the same pace. The first thing a player buys cannot be the thing that teaches them
-- buying does nothing.
--
-- Flat studs per level rather than a multiplier: it is applied BEFORE the body-size multiplier in
-- EvolutionVisuals.applyMastery, so a level bought at Cell is worth proportionally more later,
-- which is the same shape every other early upgrade in this game has.
GameConfig.SpeedPerLevel = 1.5

function GameConfig.GetSpeedUpgradeBonus(data)
	local level = data and data.Upgrades and data.Upgrades.Speed or 0
	return level * GameConfig.SpeedPerLevel
end

function GameConfig.GetUpgradeCost(upgradeKey, currentLevel)
	local def = GameConfig.Upgrades[upgradeKey]
	if not def then return math.huge end
	return math.floor(def.baseCost * (def.costMult ^ currentLevel))
end

function GameConfig.RollMutation(luckPercent)
	-- luckPercent: 0 = base, higher = better odds for rare mutations
	local totalWeight = 0
	local weights = {}
	for i, m in ipairs(GameConfig.Mutations) do
		-- luck boosts rarer (later) entries more
		local boost = 1 + (luckPercent / 100) * (i - 1) * 0.5
		local w = m.weight * boost
		weights[i] = w
		totalWeight = totalWeight + w
	end
	local roll = math.random() * totalWeight
	local acc = 0
	for i, w in ipairs(weights) do
		acc = acc + w
		if roll <= acc then
			return GameConfig.Mutations[i]
		end
	end
	return GameConfig.Mutations[1]
end

-- ===== STAGE CHARACTERS =======================================================
-- TEN characters for every one of the twenty stages -- two hundred in all -- so "what am I" stops
-- being one fixed look per stage and becomes something collected. (It was five a stage; the second
-- five of each are in the block at the bottom of the table, on the same rarity spread.)
--
-- The axis is deliberately the SAME rarity ladder the pets use (Common .. Legendary, and the same
-- weights), because a player already knows what those five words mean and what the colours are.
-- What it is NOT is a power axis: a character is a skin. Two players at Void Sovereign hit exactly
-- as hard as each other whichever one they are wearing. Making the rarest look also the strongest
-- would mean the twenty evolve steps -- the actual progression -- stop deciding anything.
--
-- How one is obtained: every time you EVOLVE INTO a stage you roll one of that stage's five. A
-- stage reached again after a Rebirth rolls again, so the collection fills in over repeat runs
-- rather than being finished the first time through. See DNAService.HandleEvolve.
--
-- `color` is what StageCostume paints the body with, replacing the stage's own single colour.
-- Everything else about the costume -- the ears, the visor, the wings -- is the stage's, so a
-- Cinder Wolf and a Frost Wolf are unmistakably both Wolves.
GameConfig.StageCharacters = {
	-- 1 CELL
	{ stage = 1, key = "cell_speck",     name = "Speck",          emoji = "\u{1F535}", rarity = "Common",    color = Color3.fromRGB(180, 240, 180) },
	{ stage = 1, key = "cell_amber",     name = "Amber Blob",     emoji = "\u{1F7E1}", rarity = "Uncommon",  color = Color3.fromRGB(248, 226, 128) },
	{ stage = 1, key = "cell_azure",     name = "Azure Spore",    emoji = "\u{1F4A0}", rarity = "Rare",      color = Color3.fromRGB(132, 214, 255) },
	{ stage = 1, key = "cell_violet",    name = "Violet Mote",    emoji = "\u{1F7E3}", rarity = "Epic",      color = Color3.fromRGB(196, 142, 255) },
	{ stage = 1, key = "cell_prime",     name = "Prime Seed",     emoji = "\u{2728}", rarity = "Legendary", color = Color3.fromRGB(255, 226, 130) },
	-- 2 BACTERIA
	{ stage = 2, key = "bact_rod",       name = "Rodling",        emoji = "\u{1F9A0}", rarity = "Common",    color = Color3.fromRGB(168, 220, 150) },
	{ stage = 2, key = "bact_coil",      name = "Coilspore",      emoji = "\u{1F300}", rarity = "Uncommon",  color = Color3.fromRGB(126, 214, 186) },
	{ stage = 2, key = "bact_toxin",     name = "Toxinlash",      emoji = "\u{2623}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(158, 232, 96) },
	{ stage = 2, key = "bact_plague",    name = "Plaguebloom",    emoji = "\u{1F9EA}", rarity = "Epic",      color = Color3.fromRGB(186, 120, 232) },
	{ stage = 2, key = "bact_ancient",   name = "Ancient Strain", emoji = "\u{1F31F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 108) },
	-- 3 WORM
	{ stage = 3, key = "worm_soil",      name = "Soilcrawl",      emoji = "\u{1FAB1}", rarity = "Common",    color = Color3.fromRGB(206, 152, 128) },
	{ stage = 3, key = "worm_glow",      name = "Glowgut",        emoji = "\u{1F41B}", rarity = "Uncommon",  color = Color3.fromRGB(160, 232, 148) },
	{ stage = 3, key = "worm_iron",      name = "Ironring",       emoji = "\u{2699}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(150, 170, 196) },
	{ stage = 3, key = "worm_bore",      name = "Deepbore",       emoji = "\u{1F573}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(178, 128, 240) },
	{ stage = 3, key = "worm_devour",    name = "Devourer Grub",  emoji = "\u{1F396}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 190, 96) },
	-- 4 LIZARD
	{ stage = 4, key = "liz_sand",       name = "Sandscale",      emoji = "\u{1F98E}", rarity = "Common",    color = Color3.fromRGB(214, 190, 132) },
	{ stage = 4, key = "liz_moss",       name = "Mossback",       emoji = "\u{1F33F}", rarity = "Uncommon",  color = Color3.fromRGB(118, 190, 108) },
	{ stage = 4, key = "liz_ember",      name = "Emberfrill",     emoji = "\u{1F525}", rarity = "Rare",      color = Color3.fromRGB(244, 132, 78) },
	{ stage = 4, key = "liz_storm",      name = "Stormtongue",    emoji = "\u{26A1}", rarity = "Epic",      color = Color3.fromRGB(140, 176, 255) },
	{ stage = 4, key = "liz_basilisk",   name = "Basilisk",       emoji = "\u{1F409}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 112) },
	-- 5 WOLF
	{ stage = 5, key = "wolf_grey",      name = "Greyfang",       emoji = "\u{1F43A}", rarity = "Common",    color = Color3.fromRGB(168, 172, 184) },
	{ stage = 5, key = "wolf_timber",    name = "Timberpelt",     emoji = "\u{1F332}", rarity = "Uncommon",  color = Color3.fromRGB(158, 128, 96) },
	{ stage = 5, key = "wolf_frost",     name = "Frostmane",      emoji = "\u{2744}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(196, 232, 255) },
	{ stage = 5, key = "wolf_cinder",    name = "Cinderhowl",     emoji = "\u{1F525}", rarity = "Epic",      color = Color3.fromRGB(238, 118, 92) },
	{ stage = 5, key = "wolf_moon",      name = "Moonwarden",     emoji = "\u{1F319}", rarity = "Legendary", color = Color3.fromRGB(255, 232, 168) },
	-- 6 GORILLA
	{ stage = 6, key = "gor_ash",        name = "Ashknuckle",     emoji = "\u{1F98D}", rarity = "Common",    color = Color3.fromRGB(150, 142, 138) },
	{ stage = 6, key = "gor_jungle",     name = "Junglebrow",     emoji = "\u{1F33F}", rarity = "Uncommon",  color = Color3.fromRGB(110, 156, 100) },
	{ stage = 6, key = "gor_silver",     name = "Silverback",     emoji = "\u{1F948}", rarity = "Rare",      color = Color3.fromRGB(206, 212, 224) },
	{ stage = 6, key = "gor_thunder",    name = "Thunderfist",    emoji = "\u{1F44A}", rarity = "Epic",      color = Color3.fromRGB(150, 154, 248) },
	{ stage = 6, key = "gor_titan",      name = "Titan Ape",      emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 202, 96) },
	-- 7 HUMAN
	{ stage = 7, key = "hum_wander",     name = "Wanderer",       emoji = "\u{1F9CD}", rarity = "Common",    color = Color3.fromRGB(214, 190, 168) },
	{ stage = 7, key = "hum_scout",      name = "Scout",          emoji = "\u{1F9ED}", rarity = "Uncommon",  color = Color3.fromRGB(140, 196, 156) },
	{ stage = 7, key = "hum_scholar",    name = "Scholar",        emoji = "\u{1F4DA}", rarity = "Rare",      color = Color3.fromRGB(132, 172, 232) },
	{ stage = 7, key = "hum_champion",   name = "Champion",       emoji = "\u{2694}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(196, 140, 244) },
	{ stage = 7, key = "hum_ascendant",  name = "Ascendant",      emoji = "\u{1F31F}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 140) },
	-- 8 CYBORG
	{ stage = 8, key = "cyb_rust",       name = "Rustframe",      emoji = "\u{1F529}", rarity = "Common",    color = Color3.fromRGB(180, 150, 126) },
	{ stage = 8, key = "cyb_chrome",     name = "Chromeshell",    emoji = "\u{1F916}", rarity = "Uncommon",  color = Color3.fromRGB(196, 204, 216) },
	{ stage = 8, key = "cyb_neon",       name = "Neondrive",      emoji = "\u{1F4A1}", rarity = "Rare",      color = Color3.fromRGB(96, 226, 255) },
	{ stage = 8, key = "cyb_reactor",    name = "Reactorcore",    emoji = "\u{2622}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(176, 128, 255) },
	{ stage = 8, key = "cyb_singular",   name = "Singular Unit",  emoji = "\u{1F52E}", rarity = "Legendary", color = Color3.fromRGB(255, 212, 118) },
	-- 9 ALIEN
	{ stage = 9, key = "ali_grey",       name = "Grey Visitor",   emoji = "\u{1F47D}", rarity = "Common",    color = Color3.fromRGB(186, 200, 190) },
	{ stage = 9, key = "ali_verdant",    name = "Verdant Scout",  emoji = "\u{1F6F8}", rarity = "Uncommon",  color = Color3.fromRGB(126, 224, 158) },
	{ stage = 9, key = "ali_hive",       name = "Hive Envoy",     emoji = "\u{1F41D}", rarity = "Rare",      color = Color3.fromRGB(120, 186, 255) },
	{ stage = 9, key = "ali_psion",      name = "Psion",          emoji = "\u{1F300}", rarity = "Epic",      color = Color3.fromRGB(198, 128, 255) },
	{ stage = 9, key = "ali_progenitor", name = "Progenitor",     emoji = "\u{1F441}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 124) },
	-- 10 COSMIC BEING
	{ stage = 10, key = "cos_dust",      name = "Dustform",       emoji = "\u{1F30C}", rarity = "Common",    color = Color3.fromRGB(178, 186, 216) },
	{ stage = 10, key = "cos_comet",     name = "Cometborn",      emoji = "\u{2604}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(132, 216, 232) },
	{ stage = 10, key = "cos_pulsar",    name = "Pulsarheart",    emoji = "\u{1F4AB}", rarity = "Rare",      color = Color3.fromRGB(126, 176, 255) },
	{ stage = 10, key = "cos_quasar",    name = "Quasarborn",     emoji = "\u{1F52E}", rarity = "Epic",      color = Color3.fromRGB(200, 132, 255) },
	{ stage = 10, key = "cos_sunforged", name = "Sunforged",      emoji = "\u{2600}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 216, 118) },
	-- 11 UNIVERSE GOD
	{ stage = 11, key = "ugod_warden",   name = "Warden",         emoji = "\u{1F30C}", rarity = "Common",    color = Color3.fromRGB(170, 178, 220) },
	{ stage = 11, key = "ugod_shaper",   name = "Shaper",         emoji = "\u{1FA90}", rarity = "Uncommon",  color = Color3.fromRGB(136, 214, 200) },
	{ stage = 11, key = "ugod_arbiter",  name = "Arbiter",        emoji = "\u{2696}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(122, 172, 255) },
	{ stage = 11, key = "ugod_creator",  name = "Creator",        emoji = "\u{1F31F}", rarity = "Epic",      color = Color3.fromRGB(204, 138, 255) },
	{ stage = 11, key = "ugod_allfather", name = "All-Maker",     emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 220, 128) },
	-- 12 STAR WEAVER
	{ stage = 12, key = "swv_thread",    name = "Threadling",     emoji = "\u{1F578}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(190, 190, 214) },
	{ stage = 12, key = "swv_loom",      name = "Loomtender",     emoji = "\u{1F9F5}", rarity = "Uncommon",  color = Color3.fromRGB(140, 214, 190) },
	{ stage = 12, key = "swv_constell",  name = "Constellar",     emoji = "\u{2728}", rarity = "Rare",      color = Color3.fromRGB(128, 180, 255) },
	{ stage = 12, key = "swv_nebular",   name = "Nebular",        emoji = "\u{1F30C}", rarity = "Epic",      color = Color3.fromRGB(206, 136, 255) },
	{ stage = 12, key = "swv_firstlight", name = "First Light",   emoji = "\u{1F31F}", rarity = "Legendary", color = Color3.fromRGB(255, 228, 142) },
	-- 13 TIME WALKER
	{ stage = 13, key = "twk_second",    name = "Secondhand",     emoji = "\u{23F1}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(188, 184, 172) },
	{ stage = 13, key = "twk_hourglass", name = "Hourglass",      emoji = "\u{23F3}", rarity = "Uncommon",  color = Color3.fromRGB(224, 196, 128) },
	{ stage = 13, key = "twk_paradox",   name = "Paradox",        emoji = "\u{1F504}", rarity = "Rare",      color = Color3.fromRGB(124, 190, 244) },
	{ stage = 13, key = "twk_eternal",   name = "Eternal Loop",   emoji = "\u{267E}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(190, 134, 252) },
	{ stage = 13, key = "twk_epoch",     name = "Epoch",          emoji = "\u{1F570}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 212, 120) },
	-- 14 VOID SOVEREIGN
	{ stage = 14, key = "vsv_hollow",    name = "Hollow",         emoji = "\u{26AB}", rarity = "Common",    color = Color3.fromRGB(120, 122, 140) },
	{ stage = 14, key = "vsv_umbral",    name = "Umbral",         emoji = "\u{1F311}", rarity = "Uncommon",  color = Color3.fromRGB(120, 168, 172) },
	{ stage = 14, key = "vsv_abyssal",   name = "Abyssal",        emoji = "\u{1F30A}", rarity = "Rare",      color = Color3.fromRGB(104, 148, 232) },
	{ stage = 14, key = "vsv_devouring", name = "Devouring",      emoji = "\u{1F573}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(174, 116, 244) },
	{ stage = 14, key = "vsv_endless",   name = "Endless",        emoji = "\u{1F5A4}", rarity = "Legendary", color = Color3.fromRGB(255, 198, 112) },
	-- 15 REALITY ARCHITECT
	{ stage = 15, key = "rar_drafter",   name = "Drafter",        emoji = "\u{1F4D0}", rarity = "Common",    color = Color3.fromRGB(186, 194, 206) },
	{ stage = 15, key = "rar_mason",     name = "Axiom Mason",    emoji = "\u{1F9F1}", rarity = "Uncommon",  color = Color3.fromRGB(138, 206, 176) },
	{ stage = 15, key = "rar_prism",     name = "Prismwright",    emoji = "\u{1F53A}", rarity = "Rare",      color = Color3.fromRGB(122, 178, 250) },
	{ stage = 15, key = "rar_lattice",   name = "Latticelord",    emoji = "\u{1F536}", rarity = "Epic",      color = Color3.fromRGB(198, 134, 255) },
	{ stage = 15, key = "rar_firstdraw", name = "First Draft",    emoji = "\u{1F4D8}", rarity = "Legendary", color = Color3.fromRGB(255, 218, 126) },
	-- 16 DIMENSIONAL TITAN
	{ stage = 16, key = "dtn_stride",    name = "Stridebearer",   emoji = "\u{1F463}", rarity = "Common",    color = Color3.fromRGB(174, 178, 194) },
	{ stage = 16, key = "dtn_fold",      name = "Foldbreaker",    emoji = "\u{1F4C0}", rarity = "Uncommon",  color = Color3.fromRGB(132, 208, 196) },
	{ stage = 16, key = "dtn_rift",      name = "Riftcolossus",   emoji = "\u{1F30D}", rarity = "Rare",      color = Color3.fromRGB(116, 172, 252) },
	{ stage = 16, key = "dtn_planar",    name = "Planar Tyrant",  emoji = "\u{1F52E}", rarity = "Epic",      color = Color3.fromRGB(196, 128, 255) },
	{ stage = 16, key = "dtn_worldsp",   name = "Worldspine",     emoji = "\u{1F3D4}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 210, 116) },
	-- 17 CHRONOS BEING
	{ stage = 17, key = "chr_tick",      name = "Tickborn",       emoji = "\u{23F0}", rarity = "Common",    color = Color3.fromRGB(188, 186, 178) },
	{ stage = 17, key = "chr_ageless",   name = "Ageless",        emoji = "\u{1F55B}", rarity = "Uncommon",  color = Color3.fromRGB(146, 210, 186) },
	{ stage = 17, key = "chr_unwound",   name = "Unwound",        emoji = "\u{1F9F5}", rarity = "Rare",      color = Color3.fromRGB(124, 184, 250) },
	{ stage = 17, key = "chr_forever",   name = "Forevermind",    emoji = "\u{267E}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(200, 134, 255) },
	{ stage = 17, key = "chr_zerohour",  name = "Zero Hour",      emoji = "\u{1F551}", rarity = "Legendary", color = Color3.fromRGB(255, 220, 124) },
	-- 18 OMNISCIENT ENTITY
	{ stage = 18, key = "omn_watcher",   name = "Watcher",        emoji = "\u{1F441}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(190, 196, 210) },
	{ stage = 18, key = "omn_seer",      name = "Seer",           emoji = "\u{1F52E}", rarity = "Uncommon",  color = Color3.fromRGB(142, 212, 192) },
	{ stage = 18, key = "omn_oracle",    name = "Oracle",         emoji = "\u{1F4AD}", rarity = "Rare",      color = Color3.fromRGB(126, 182, 252) },
	{ stage = 18, key = "omn_allseeing", name = "All-Seeing",     emoji = "\u{1F31F}", rarity = "Epic",      color = Color3.fromRGB(202, 136, 255) },
	{ stage = 18, key = "omn_theknown",  name = "The Known",      emoji = "\u{1F4D6}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 132) },
	-- 19 PRIMORDIAL FORCE
	{ stage = 19, key = "pri_spark",     name = "First Spark",    emoji = "\u{1F4A5}", rarity = "Common",    color = Color3.fromRGB(184, 178, 188) },
	{ stage = 19, key = "pri_flood",     name = "Elder Flood",    emoji = "\u{1F30A}", rarity = "Uncommon",  color = Color3.fromRGB(134, 208, 210) },
	{ stage = 19, key = "pri_flame",     name = "Elder Flame",    emoji = "\u{1F525}", rarity = "Rare",      color = Color3.fromRGB(248, 148, 104) },
	{ stage = 19, key = "pri_silence",   name = "Elder Silence",  emoji = "\u{1F5A4}", rarity = "Epic",      color = Color3.fromRGB(190, 130, 250) },
	{ stage = 19, key = "pri_origin",    name = "The Origin",     emoji = "\u{1F30B}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 110) },
	-- 20 THE ABSOLUTE
	{ stage = 20, key = "abs_axiom",     name = "Axiom",          emoji = "\u{25AB}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(214, 214, 220) },
	{ stage = 20, key = "abs_theorem",   name = "Theorem",        emoji = "\u{1F53B}", rarity = "Uncommon",  color = Color3.fromRGB(146, 216, 198) },
	{ stage = 20, key = "abs_absolute",  name = "Absolute",       emoji = "\u{1F53A}", rarity = "Rare",      color = Color3.fromRGB(128, 186, 255) },
	{ stage = 20, key = "abs_infinite",  name = "The Infinite",   emoji = "\u{1F781}", rarity = "Epic",      color = Color3.fromRGB(206, 140, 255) },
	{ stage = 20, key = "abs_thefinal",  name = "The Final",      emoji = "\u{1F4A0}", rarity = "Legendary", color = Color3.fromRGB(255, 232, 150) },

	-- ===== THE SECOND FIVE ====================================================
	-- A second full set, same twenty stages, same rarity ladder: two Commons, two Uncommons, two
	-- Rares, two Epics and two Legendaries per stage. The roll is unchanged -- it weights by rarity
	-- and sums, so doubling the entries at each rarity leaves the CHANCE of rolling a Legendary
	-- exactly where it was and only decides which Legendary it is. What it changes is how long the
	-- collection takes to finish, which is the point: at five a stage a player who rebirths twice
	-- has usually seen everything their stage can be.
	-- 1 CELL
	{ stage = 1, key = "cell_pale",      name = "Pale Nucleus",   emoji = "\u{26AA}", rarity = "Common",    color = Color3.fromRGB(222, 228, 214) },
	{ stage = 1, key = "cell_coral",     name = "Coral Cyst",     emoji = "\u{1F7E0}", rarity = "Uncommon",  color = Color3.fromRGB(255, 168, 132) },
	{ stage = 1, key = "cell_mint",      name = "Mint Vesicle",   emoji = "\u{1F7E2}", rarity = "Rare",      color = Color3.fromRGB(150, 236, 190) },
	{ stage = 1, key = "cell_cobalt",    name = "Cobalt Blob",    emoji = "\u{1F535}", rarity = "Epic",      color = Color3.fromRGB(120, 150, 255) },
	{ stage = 1, key = "cell_ovum",      name = "Golden Ovum",    emoji = "\u{1F95A}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 140) },
	-- 2 BACTERIA
	{ stage = 2, key = "bact_dust",      name = "Dustcoccus",     emoji = "\u{1F4A8}", rarity = "Common",    color = Color3.fromRGB(196, 200, 180) },
	{ stage = 2, key = "bact_bloom",     name = "Bloomrod",       emoji = "\u{1F338}", rarity = "Uncommon",  color = Color3.fromRGB(255, 176, 206) },
	{ stage = 2, key = "bact_frost",     name = "Frostspore",     emoji = "\u{2744}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(186, 232, 255) },
	{ stage = 2, key = "bact_venom",     name = "Venomcoil",      emoji = "\u{1F40D}", rarity = "Epic",      color = Color3.fromRGB(150, 110, 236) },
	{ stage = 2, key = "bact_primal",    name = "Primal Culture", emoji = "\u{1F9EB}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 132) },
	-- 3 WORM
	{ stage = 3, key = "worm_pale",      name = "Palecrawler",    emoji = "\u{1F41B}", rarity = "Common",    color = Color3.fromRGB(226, 206, 196) },
	{ stage = 3, key = "worm_marsh",     name = "Marshgut",       emoji = "\u{1F33E}", rarity = "Uncommon",  color = Color3.fromRGB(150, 190, 120) },
	{ stage = 3, key = "worm_amber",     name = "Amberburrow",    emoji = "\u{1F7E7}", rarity = "Rare",      color = Color3.fromRGB(240, 176, 96) },
	{ stage = 3, key = "worm_shadow",    name = "Shadowcoil",     emoji = "\u{1F311}", rarity = "Epic",      color = Color3.fromRGB(140, 120, 200) },
	{ stage = 3, key = "worm_titan",     name = "Titan Grub",     emoji = "\u{1F41E}", rarity = "Legendary", color = Color3.fromRGB(255, 208, 120) },
	-- 4 LIZARD
	{ stage = 4, key = "liz_dune",       name = "Dunebask",       emoji = "\u{1F3DC}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(226, 204, 158) },
	{ stage = 4, key = "liz_reed",       name = "Reedskin",       emoji = "\u{1F343}", rarity = "Uncommon",  color = Color3.fromRGB(130, 204, 140) },
	{ stage = 4, key = "liz_glacier",    name = "Glacierfrill",   emoji = "\u{1F9CA}", rarity = "Rare",      color = Color3.fromRGB(168, 224, 255) },
	{ stage = 4, key = "liz_venom",      name = "Venomtongue",    emoji = "\u{2620}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(168, 132, 248) },
	{ stage = 4, key = "liz_sunking",    name = "Sun Basilisk",   emoji = "\u{2600}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 104) },
	-- 5 WOLF
	{ stage = 5, key = "wolf_dusk",      name = "Duskpelt",       emoji = "\u{1F31A}", rarity = "Common",    color = Color3.fromRGB(140, 138, 152) },
	{ stage = 5, key = "wolf_river",     name = "Riverfang",      emoji = "\u{1F4A7}", rarity = "Uncommon",  color = Color3.fromRGB(132, 196, 214) },
	{ stage = 5, key = "wolf_ash",       name = "Ashcoat",        emoji = "\u{1F32B}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(196, 190, 186) },
	{ stage = 5, key = "wolf_storm",     name = "Stormhowl",      emoji = "\u{26C8}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(150, 150, 244) },
	{ stage = 5, key = "wolf_sun",       name = "Sunfang Alpha",  emoji = "\u{1F31E}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 150) },
	-- 6 GORILLA
	{ stage = 6, key = "gor_stone",      name = "Stonefist",      emoji = "\u{1FAA8}", rarity = "Common",    color = Color3.fromRGB(166, 160, 152) },
	{ stage = 6, key = "gor_vine",       name = "Vinebrawler",    emoji = "\u{1F33F}", rarity = "Uncommon",  color = Color3.fromRGB(126, 176, 110) },
	{ stage = 6, key = "gor_iron",       name = "Ironback",       emoji = "\u{1F6E1}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(168, 182, 200) },
	{ stage = 6, key = "gor_ember",      name = "Emberchest",     emoji = "\u{1F525}", rarity = "Epic",      color = Color3.fromRGB(240, 140, 104) },
	{ stage = 6, key = "gor_primarch",   name = "Primarch",       emoji = "\u{1F3C6}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 120) },
	-- 7 HUMAN
	{ stage = 7, key = "hum_farmhand",   name = "Farmhand",       emoji = "\u{1F33E}", rarity = "Common",    color = Color3.fromRGB(208, 180, 150) },
	{ stage = 7, key = "hum_smith",      name = "Smith",          emoji = "\u{1F528}", rarity = "Uncommon",  color = Color3.fromRGB(176, 166, 150) },
	{ stage = 7, key = "hum_ranger",     name = "Ranger",         emoji = "\u{1F3F9}", rarity = "Rare",      color = Color3.fromRGB(128, 186, 150) },
	{ stage = 7, key = "hum_knight",     name = "Knight",         emoji = "\u{1F6E1}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(172, 150, 236) },
	{ stage = 7, key = "hum_sovereign",  name = "Sovereign",      emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 220, 140) },
	-- 8 CYBORG
	{ stage = 8, key = "cyb_scrap",      name = "Scrapframe",     emoji = "\u{1F5D1}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(168, 160, 150) },
	{ stage = 8, key = "cyb_carbon",     name = "Carbonshell",    emoji = "\u{26AB}", rarity = "Uncommon",  color = Color3.fromRGB(110, 116, 128) },
	{ stage = 8, key = "cyb_plasma",     name = "Plasmadrive",    emoji = "\u{1F535}", rarity = "Rare",      color = Color3.fromRGB(110, 200, 255) },
	{ stage = 8, key = "cyb_quantum",    name = "Quantum Core",   emoji = "\u{269B}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(168, 140, 255) },
	{ stage = 8, key = "cyb_omega",      name = "Omega Chassis",  emoji = "\u{2699}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 206, 120) },
	-- 9 ALIEN
	{ stage = 9, key = "ali_drone",      name = "Drone",          emoji = "\u{1F47E}", rarity = "Common",    color = Color3.fromRGB(176, 190, 182) },
	{ stage = 9, key = "ali_ochre",      name = "Ochre Envoy",    emoji = "\u{1F7E4}", rarity = "Uncommon",  color = Color3.fromRGB(206, 150, 110) },
	{ stage = 9, key = "ali_crystal",    name = "Crystal Kin",    emoji = "\u{1F48E}", rarity = "Rare",      color = Color3.fromRGB(140, 220, 236) },
	{ stage = 9, key = "ali_overmind",   name = "Overmind",       emoji = "\u{1F9E0}", rarity = "Epic",      color = Color3.fromRGB(196, 132, 248) },
	{ stage = 9, key = "ali_starseed",   name = "Starseed",       emoji = "\u{2734}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 224, 150) },
	-- 10 COSMIC BEING
	{ stage = 10, key = "cos_ember",     name = "Emberdrift",     emoji = "\u{1F320}", rarity = "Common",    color = Color3.fromRGB(196, 176, 168) },
	{ stage = 10, key = "cos_aurora",    name = "Auroraform",     emoji = "\u{1F30C}", rarity = "Uncommon",  color = Color3.fromRGB(140, 226, 206) },
	{ stage = 10, key = "cos_nova",      name = "Novaheart",      emoji = "\u{1F4A5}", rarity = "Rare",      color = Color3.fromRGB(255, 158, 120) },
	{ stage = 10, key = "cos_voidglow",  name = "Voidglow",       emoji = "\u{26AB}", rarity = "Epic",      color = Color3.fromRGB(170, 130, 255) },
	{ stage = 10, key = "cos_eclipse",   name = "Eclipsebound",   emoji = "\u{1F31A}", rarity = "Legendary", color = Color3.fromRGB(255, 226, 140) },
	-- 11 UNIVERSE GOD
	{ stage = 11, key = "ugod_herald",   name = "Herald",         emoji = "\u{1F4EF}", rarity = "Common",    color = Color3.fromRGB(186, 190, 214) },
	{ stage = 11, key = "ugod_keeper",   name = "Keeper",         emoji = "\u{1F5DD}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(146, 204, 196) },
	{ stage = 11, key = "ugod_judge",    name = "Judge",          emoji = "\u{1F3DB}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(140, 180, 244) },
	{ stage = 11, key = "ugod_fate",     name = "Fatespinner",    emoji = "\u{1F9F6}", rarity = "Epic",      color = Color3.fromRGB(198, 140, 252) },
	{ stage = 11, key = "ugod_eternal",  name = "The Eternal",    emoji = "\u{267E}\u{FE0F}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 136) },
	-- 12 STAR WEAVER
	{ stage = 12, key = "swv_spindle",   name = "Spindle",        emoji = "\u{1F4AB}", rarity = "Common",    color = Color3.fromRGB(192, 192, 208) },
	{ stage = 12, key = "swv_dawn",      name = "Dawnthread",     emoji = "\u{1F305}", rarity = "Uncommon",  color = Color3.fromRGB(255, 196, 150) },
	{ stage = 12, key = "swv_pulse",     name = "Pulseweft",      emoji = "\u{1F4A0}", rarity = "Rare",      color = Color3.fromRGB(130, 196, 255) },
	{ stage = 12, key = "swv_darkloom",  name = "Dark Loom",      emoji = "\u{1F578}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(170, 120, 240) },
	{ stage = 12, key = "swv_lastthread", name = "Last Thread",   emoji = "\u{1F3B6}", rarity = "Legendary", color = Color3.fromRGB(255, 230, 150) },
	-- 13 TIME WALKER
	{ stage = 13, key = "twk_minute",    name = "Minutewalk",     emoji = "\u{1F55C}", rarity = "Common",    color = Color3.fromRGB(190, 186, 176) },
	{ stage = 13, key = "twk_sundial",   name = "Sundial",        emoji = "\u{1F31E}", rarity = "Uncommon",  color = Color3.fromRGB(232, 200, 132) },
	{ stage = 13, key = "twk_rewind",    name = "Rewind",         emoji = "\u{23EA}", rarity = "Rare",      color = Color3.fromRGB(130, 196, 240) },
	{ stage = 13, key = "twk_fracture",  name = "Fracture Hour",  emoji = "\u{1F52E}", rarity = "Epic",      color = Color3.fromRGB(186, 138, 250) },
	{ stage = 13, key = "twk_finalhour", name = "Final Hour",     emoji = "\u{1F553}", rarity = "Legendary", color = Color3.fromRGB(255, 216, 126) },
	-- 14 VOID SOVEREIGN
	{ stage = 14, key = "vsv_ashen",     name = "Ashen",          emoji = "\u{1F32B}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(128, 128, 142) },
	{ stage = 14, key = "vsv_dim",       name = "Dimlight",       emoji = "\u{1F56F}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(126, 160, 168) },
	{ stage = 14, key = "vsv_nulltide",  name = "Null Tide",      emoji = "\u{1F535}", rarity = "Rare",      color = Color3.fromRGB(110, 150, 226) },
	{ stage = 14, key = "vsv_starless",  name = "Starless",       emoji = "\u{2B50}", rarity = "Epic",      color = Color3.fromRGB(168, 120, 240) },
	{ stage = 14, key = "vsv_crown",     name = "Crown of Nothing", emoji = "\u{1F451}", rarity = "Legendary", color = Color3.fromRGB(255, 204, 120) },
	-- 15 REALITY ARCHITECT
	{ stage = 15, key = "rar_sketch",    name = "Sketchwright",   emoji = "\u{270F}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(192, 196, 204) },
	{ stage = 15, key = "rar_frame",     name = "Framesmith",     emoji = "\u{1F5BC}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(142, 204, 180) },
	{ stage = 15, key = "rar_vault",     name = "Vaultbuilder",   emoji = "\u{1F3E6}", rarity = "Rare",      color = Color3.fromRGB(128, 182, 250) },
	{ stage = 15, key = "rar_render",    name = "Renderlord",     emoji = "\u{1F5A5}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(196, 140, 252) },
	{ stage = 15, key = "rar_blueprint", name = "The Blueprint",  emoji = "\u{1F4DC}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 132) },
	-- 16 DIMENSIONAL TITAN
	{ stage = 16, key = "dtn_step",      name = "Stepwalker",     emoji = "\u{1F45F}", rarity = "Common",    color = Color3.fromRGB(176, 180, 196) },
	{ stage = 16, key = "dtn_gate",      name = "Gatebreaker",    emoji = "\u{1F6AA}", rarity = "Uncommon",  color = Color3.fromRGB(136, 206, 198) },
	{ stage = 16, key = "dtn_echo",      name = "Echo Colossus",  emoji = "\u{1F310}", rarity = "Rare",      color = Color3.fromRGB(120, 176, 250) },
	{ stage = 16, key = "dtn_prism",     name = "Prism Tyrant",   emoji = "\u{1F53A}", rarity = "Epic",      color = Color3.fromRGB(198, 132, 255) },
	{ stage = 16, key = "dtn_worldend",  name = "Worldbreaker",   emoji = "\u{1F30B}", rarity = "Legendary", color = Color3.fromRGB(255, 212, 120) },
	-- 17 CHRONOS BEING
	{ stage = 17, key = "chr_grain",     name = "Sandgrain",      emoji = "\u{231B}", rarity = "Common",    color = Color3.fromRGB(190, 188, 180) },
	{ stage = 17, key = "chr_dawn",      name = "Dawnkeeper",     emoji = "\u{1F304}", rarity = "Uncommon",  color = Color3.fromRGB(150, 212, 190) },
	{ stage = 17, key = "chr_loop",      name = "Loopbound",      emoji = "\u{1F501}", rarity = "Rare",      color = Color3.fromRGB(128, 188, 252) },
	{ stage = 17, key = "chr_still",     name = "Stillpoint",     emoji = "\u{23F8}\u{FE0F}", rarity = "Epic", color = Color3.fromRGB(202, 138, 255) },
	{ stage = 17, key = "chr_enddays",   name = "End of Days",    emoji = "\u{1F556}", rarity = "Legendary", color = Color3.fromRGB(255, 222, 128) },
	-- 18 OMNISCIENT ENTITY
	{ stage = 18, key = "omn_listener",  name = "Listener",       emoji = "\u{1F442}", rarity = "Common",    color = Color3.fromRGB(192, 198, 212) },
	{ stage = 18, key = "omn_archivist", name = "Archivist",      emoji = "\u{1F5C3}\u{FE0F}", rarity = "Uncommon", color = Color3.fromRGB(146, 214, 194) },
	{ stage = 18, key = "omn_prophet",   name = "Prophet",        emoji = "\u{1F4FF}", rarity = "Rare",      color = Color3.fromRGB(130, 186, 254) },
	{ stage = 18, key = "omn_mind",      name = "The Mind",       emoji = "\u{1F9E0}", rarity = "Epic",      color = Color3.fromRGB(204, 140, 255) },
	{ stage = 18, key = "omn_truth",     name = "The Truth",      emoji = "\u{1F4A1}", rarity = "Legendary", color = Color3.fromRGB(255, 228, 136) },
	-- 19 PRIMORDIAL FORCE
	{ stage = 19, key = "pri_dust",      name = "First Dust",     emoji = "\u{1F4A8}", rarity = "Common",    color = Color3.fromRGB(186, 180, 190) },
	{ stage = 19, key = "pri_stone",     name = "Elder Stone",    emoji = "\u{1FAA8}", rarity = "Uncommon",  color = Color3.fromRGB(150, 150, 160) },
	{ stage = 19, key = "pri_storm",     name = "Elder Storm",    emoji = "\u{26C8}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(140, 190, 246) },
	{ stage = 19, key = "pri_night",     name = "Elder Night",    emoji = "\u{1F311}", rarity = "Epic",      color = Color3.fromRGB(150, 120, 230) },
	{ stage = 19, key = "pri_firstdawn", name = "The First Dawn", emoji = "\u{1F305}", rarity = "Legendary", color = Color3.fromRGB(255, 214, 120) },
	-- 20 THE ABSOLUTE
	{ stage = 20, key = "abs_null",      name = "Null",           emoji = "\u{25FB}\u{FE0F}", rarity = "Common", color = Color3.fromRGB(216, 216, 222) },
	{ stage = 20, key = "abs_proof",     name = "Proof",          emoji = "\u{1F9EE}", rarity = "Uncommon",  color = Color3.fromRGB(150, 220, 202) },
	{ stage = 20, key = "abs_limit",     name = "The Limit",      emoji = "\u{267E}\u{FE0F}", rarity = "Rare", color = Color3.fromRGB(132, 190, 255) },
	{ stage = 20, key = "abs_paradox",   name = "Paradox Prime",  emoji = "\u{1F300}", rarity = "Epic",      color = Color3.fromRGB(208, 144, 255) },
	{ stage = 20, key = "abs_omega",     name = "Omega",          emoji = "\u{1F3C1}", rarity = "Legendary", color = Color3.fromRGB(255, 236, 158) },
}

-- key -> entry, and stage -> its five, both built once. A hundred-entry linear scan runs on every
-- Journal refresh and on every costume build otherwise.
-- ===== NO TWO CHARACTERS IN A STAGE MAY SHARE A COLOUR =====
-- `color` is the whole of what the authored table above varies, and it was authored one row at a
-- time, so a stage could end up with three of them on the same swatch: Amber Blob (248,226,128),
-- Prime Seed (255,226,130) and Golden Ovum (255,214,140) were 7 and 16 apart in RGB. Picking one
-- over another in the Journal then changed NOTHING a player could see. Across the twenty stages
-- there were 127 pairs closer than 55 apart and the worst was 3.
--
-- Separated here rather than by hand in the table because the table is where a designer works: a
-- new character can be given whatever colour reads right for its NAME, and this guarantees it will
-- still be distinguishable from its stagemates without anyone having to check.
--
-- VALUE AND SATURATION DO THE WORK, HUE BARELY MOVES (0.01 per step, capped by how few steps are
-- ever needed). That ordering is the whole trick: a gold pushed darker and richer is still a gold,
-- while a gold pushed around the hue wheel is a lime -- the first attempt at this turned "Golden
-- Ovum" green and "Titan" into a leaf. A character has to keep looking like its own name.
--
-- Deterministic, and seeded from the AUTHORED colour rather than from the previous iteration, so a
-- given key always lands on the same shade -- a skin that shifts between sessions is not a skin.
do
	local MIN_DIST = 30 -- RGB units. Below this two shells read as the same colour in play.
	local function dist(a, b)
		return math.sqrt(((a.R - b.R) * 255) ^ 2 + ((a.G - b.G) * 255) ^ 2 + ((a.B - b.B) * 255) ^ 2)
	end

	local placed = {}
	for _, c in ipairs(GameConfig.StageCharacters) do
		placed[c.stage] = placed[c.stage] or {}
		local taken = placed[c.stage]
		local col = c.color
		local idx = #taken + 1
		for step = 1, 10 do
			local clash = false
			for _, other in ipairs(taken) do
				if dist(col, other) < MIN_DIST then
					clash = true
					break
				end
			end
			if not clash then break end
			local h, s, v = Color3.toHSV(c.color)
			-- alternating direction by position in the stage, so a run of similar colours spreads
			-- both lighter and darker instead of all marching one way into black
			local dir = (idx % 2 == 0) and 1 or -1
			v = math.clamp(v - dir * 0.13 * step, 0.30, 1)
			s = math.clamp(s + 0.09 * step, 0.15, 1)
			h = (h + dir * 0.010 * step) % 1
			col = Color3.fromHSV(h, s, v)
		end
		c.color = col
		taken[#taken + 1] = col
	end
end

-- ===== HOW MANY OF EACH STAGE'S LIST ARE ACTUALLY IN PLAY =====
--
-- The table above authors ten per stage, two hundred in all. That is too many to be COLLECTED:
-- a stage's whole list has to be finished before the next stage's opens (see
-- NextCharacterForStage and the evolve gate in DNAService), so ten per stage means ten unlocks
-- of standing in one zone before the game moves on -- and the report was exactly that, a player
-- at Bacteria still holding Cell 1/10.
--
-- Five. Applied as a CAP on the lookup rather than by deleting rows, for three reasons: the
-- authored table stays the designer's document, the meshes for all ten are already generated and
-- filed so raising this is one number rather than a regeneration, and `GetCharacterRank` counts
-- off the lists it is given -- so the ladder renumbers itself to 1..100 automatically and the
-- damage/health curves keep their shape without a single other edit.
--
-- A save holding a character past the cap keeps it (CHARACTER_BY_KEY is not capped, so it still
-- resolves, still wears and still scores); it simply stops being handed out.
GameConfig.CharactersPerStage = 5

local CHARACTER_BY_KEY, CHARACTERS_BY_STAGE = {}, {}
for _, c in ipairs(GameConfig.StageCharacters) do
	-- keyed lookup is UNCAPPED on purpose -- see the note above
	CHARACTER_BY_KEY[c.key] = c
	local list = CHARACTERS_BY_STAGE[c.stage]
	if not list then
		list = {}
		CHARACTERS_BY_STAGE[c.stage] = list
	end
	if #list < GameConfig.CharactersPerStage then
		table.insert(list, c)
	end
end

-- ===== THE VIP SKIN: A 201st ENTRY THAT IS NOT PART OF THE COLLECTION =====
--
-- Registered in CHARACTER_BY_KEY so it resolves, wears and paints like any other skin -- and
-- DELIBERATELY NOT in CHARACTERS_BY_STAGE. That table is what CountCharactersForStage, GetEvolveStep
-- and GetCollectionStage all count off; a 201st entry inside it would add a sixth step to some
-- stage's evolve chain, move every rank above it, and make the Journal unable to ever read 200/200.
-- Kept outside, it is visible and wearable while the collection arithmetic never sees it.
--
-- There is no generated SkinMesh_vip_gold, and that is fine: SkinMesh.Has() is what callers use to
-- choose between the mesh and StageCostume, so this falls back to the costume painted in the colour
-- below -- i.e. a gold version of whatever stage the player is standing at, at any stage.
GameConfig.VipCharacter = {
	key = "vip_gold",
	name = "Golden Patron",
	emoji = "👑",
	rarity = "Legendary",
	color = Color3.fromRGB(255, 205, 74),
	vip = true,
}
CHARACTER_BY_KEY[GameConfig.VipCharacter.key] = GameConfig.VipCharacter

function GameConfig.GetCharacter(key)
	return key and CHARACTER_BY_KEY[key] or nil
end

function GameConfig.GetCharactersForStage(stageIndex)
	return CHARACTERS_BY_STAGE[stageIndex] or {}
end

-- ===== A CHARACTER IS EARNED BY EVOLVING, AND NOTHING ELSE =====
--
-- Kills used to hand them over at 1 in 5 while the evolve was BLOCKED until all five of a stage
-- had dropped. That is the same wait written twice, and the half of it the player could see was
-- the wrong half: what stood between them and the button was a dice roll rather than anything
-- they were doing.
--
-- Every character is its own evolve now -- see GameConfig.GetEvolveStep. Kept at 0 rather than
-- deleted because the roll is called from CreatureService's hot path and from the shrine, and a
-- number is a safer thing to leave behind than a missing function.
GameConfig.CharacterDropChance = 0

function GameConfig.RollCharacterDrop()
	return math.random() < GameConfig.CharacterDropChance
end

-- ===== A CHARACTER IS A DAMAGE TIER, AND IT IS UNLOCKED IN ORDER =====
-- This replaces a random weighted roll. The reason is what the Journal turned into: a grid of
-- padlocks with a percentage under each one, where a player could grind a stage for an hour and
-- keep re-rolling the same Common. Unlocking left to right means every evolve into a stage hands
-- over the next character in that stage's list, so progress is visible and nothing is ever wasted.
--
-- With the order fixed, POSITION IN THE LIST IS THE POWER LADDER -- 1st is the weakest, 10th the
-- strongest -- so the honest number to print under a character is what it does, not what it cost
-- to find. `rarity` stays in the data: it is what StageCostume's skinMarks reads to decide how
-- much flourish a character wears, and it now describes the same ladder from the other end.
GameConfig.CharacterDamageStep = 6 -- kept for saves and tools that still read it

-- ONE LADDER ACROSS THE WHOLE COLLECTION, NOT TEN RUNGS PER STAGE.
--
-- A character used to be worn per stage, and its damage was its position within its own stage --
-- so the tenth Cell and the tenth Absolute were both "+60%", and choosing between them was not a
-- decision anyone could make because you could only ever wear the one belonging to the stage you
-- were standing at.
--
-- Any character can be worn at any time now, anywhere. That only means something if they are
-- ranked against EACH OTHER: rank 1 is the first Cell, rank 200 is the last Absolute, and wearing
-- something from further back in the collection is a real trade -- you look like what you want and
-- you hit for less. The Journal prints the figure on every entry so the trade is never a guess.
--
-- 3% a rung, so the spread inside one stage is 30% (a choice you can feel) and the whole ladder
-- tops out at +600%. Deliberately generous at the top: the collection fills strictly bottom-up, so
-- a player deep enough to own a rank-200 character has earned every one of the 199 below it.
GameConfig.CharacterDamagePerRank = 3

-- The Nth character of its stage, 1-based. Kept as a lookup rather than stored on the entry so the
-- authored table above stays a plain list that a designer can reorder freely.
function GameConfig.GetCharacterIndex(entry)
	if not entry then return 1 end
	local list = CHARACTERS_BY_STAGE[entry.stage] or {}
	for i, c in ipairs(list) do
		if c.key == entry.key then return i end
	end
	return 1
end

-- Where this character stands in the whole collection, 1-based. Counted off the stages BELOW it
-- rather than off a constant ten per stage, so a stage with a different number of characters does
-- not silently shift everything after it.
function GameConfig.GetCharacterRank(entry)
	if not entry then return 0 end
	-- The VIP skin has no rung on the ladder -- it is not in CHARACTERS_BY_STAGE and counting it as
	-- one would put it either at the bottom (worthless) or the top (bought power). What it is worth
	-- is decided per WEARER instead; see GetEffectiveRank.
	if entry.vip then return 0 end
	local rank = 0
	for stageIndex = 1, (entry.stage or 1) - 1 do
		rank += #(CHARACTERS_BY_STAGE[stageIndex] or {})
	end
	return rank + GameConfig.GetCharacterIndex(entry)
end

function GameConfig.GetCharacterDamagePct(entry)
	if not entry then return 0 end
	return GameConfig.GetCharacterRank(entry) * GameConfig.CharacterDamagePerRank
end

-- WHAT IS ON THE BODY, wherever the player happens to be standing. One character, not one per
-- stage. Returns a MULTIPLIER so it drops straight into the damage chain.
--
-- `EquippedCharacters` is still read as the fallback so a save written before this change keeps
-- whatever it was wearing at its own stage until the player next picks something.
function GameConfig.GetWornCharacter(data)
	if not data then return nil end
	local key = data.WornCharacter
	if not key and data.EquippedCharacters then
		key = data.EquippedCharacters[tostring(data.StageIndex or 1)]
	end
	return key and CHARACTER_BY_KEY[key] or nil
end

-- The best rung this player has actually EARNED. The VIP skin ignores the entry it is worn as and
-- scores as this instead, which is the whole reason it is not pay-to-win: wearing it never costs a
-- player damage they had, and never hands them damage they did not climb to. It also means the
-- skin stays worth wearing for the rest of the game instead of being abandoned the moment the
-- collection passes it, which is what any fixed rank would have caused.
function GameConfig.GetBestOwnedRank(data)
	local best = 0
	for key in pairs((data and data.Characters) or {}) do
		local entry = CHARACTER_BY_KEY[key]
		if entry and not entry.vip then
			local rank = GameConfig.GetCharacterRank(entry)
			if rank > best then best = rank end
		end
	end
	return best
end

function GameConfig.GetEffectiveRank(data, entry)
	if entry and entry.vip then return GameConfig.GetBestOwnedRank(data) end
	return GameConfig.GetCharacterRank(entry)
end

function GameConfig.GetCharacterDamageMult(data)
	local entry = GameConfig.GetWornCharacter(data)
	if not entry then return 1 end
	return 1 + GameConfig.GetEffectiveRank(data, entry) * GameConfig.CharacterDamagePerRank / 100
end

-- ===== A SKIN GIVES HEALTH AS WELL AS DAMAGE =====
--
-- The ladder only paid offence: rank 200 hit for +600% and had exactly the same hit points as rank
-- 1. That makes late characters strictly a damage stat, and it makes the trade the Journal offers --
-- "wear what you like and hit for less" -- much sharper than it should be, because dropping back
-- fifty ranks cost damage and nothing was gained in return.
--
-- 1% a rung against damage's 3%, so the whole ladder tops out at +200% health where damage tops out
-- at +600%. Deliberately the smaller number of the two: health multiplies how long a fight lasts
-- and damage multiplies how fast it ends, so equal rates would make the late game trivially safe.
-- It stacks MULTIPLICATIVELY with Stage Mastery's healthMult, exactly as the damage side stacks.
GameConfig.CharacterHealthPerRank = 1

function GameConfig.GetCharacterHealthPct(entry)
	if not entry then return 0 end
	return GameConfig.GetCharacterRank(entry) * GameConfig.CharacterHealthPerRank
end

function GameConfig.GetCharacterHealthMult(data)
	local entry = GameConfig.GetWornCharacter(data)
	if not entry then return 1 end
	return 1 + GameConfig.GetEffectiveRank(data, entry) * GameConfig.CharacterHealthPerRank / 100
end

-- Grants or REVOKES the VIP skin so it always matches the pass. Called on every pass refresh and
-- again after a rebirth, because RebirthService clears `data.Characters` wholesale -- without the
-- second call a VIP who rebirthed would lose the skin until they next rejoined.
function GameConfig.SyncVipCharacter(data)
	if not data then return end
	data.Characters = data.Characters or {}
	local key = GameConfig.VipCharacter.key

	if GameConfig.OwnsPass(data, "VIP") then
		data.Characters[key] = true
		return
	end

	data.Characters[key] = nil
	-- Still wearing it after the pass went away would leave the body in a skin the player no longer
	-- owns, and GetWornCharacter would happily keep resolving it. Fall back to the best thing they
	-- actually earned, which is also exactly what the VIP skin had been scoring as.
	if data.WornCharacter == key then
		local best, bestRank = nil, -1
		for owned in pairs(data.Characters) do
			local entry = GameConfig.GetCharacter(owned)
			if entry and not entry.vip then
				local rank = GameConfig.GetCharacterRank(entry)
				if rank > bestRank then best, bestRank = owned, rank end
			end
		end
		data.WornCharacter = best
	end
end

-- THE NEXT ONE TO HAND OVER: the first entry of this stage the player does not already own.
-- Returns nil once the stage is complete, which is what tells the caller there is nothing left to
-- give here -- the old roll could only signal that by handing back a duplicate.
function GameConfig.NextCharacterForStage(owned, stageIndex)
	local list = CHARACTERS_BY_STAGE[stageIndex]
	if not list then return nil end
	for _, c in ipairs(list) do
		if not (owned and owned[c.key]) then return c end
	end
	return nil
end

-- KEPT because RebirthShrine and the mystery-shop path still call it, but it is no longer how
-- characters are earned. `luck` is ignored: with the order fixed there is no curve for it to lift.
function GameConfig.RollCharacterForStage(stageIndex, luck)
	local list = CHARACTERS_BY_STAGE[stageIndex]
	if not list or #list == 0 then return nil end
	local weights, total = {}, 0
	for i, c in ipairs(list) do
		local rarity = GameConfig.GetRarity(c.rarity)
		-- the rarer the entry the more luck moves it, so luck is felt at the top of the ladder
		-- rather than spread flat across all five
		local w = rarity.weight * (1 + (luck or 0) * 0.01 * (rarity.bonusMult - 1))
		weights[i] = w
		total = total + w
	end
	local roll = math.random() * total
	local acc = 0
	for i, w in ipairs(weights) do
		acc = acc + w
		if roll <= acc then return list[i] end
	end
	return list[1]
end

-- What the Journal prints at the top: how many of the collection are owned.
--
-- COUNTED OFF THE CAPPED LISTS, NOT OFF THE AUTHORED TABLE. `StageCharacters` still holds ten a
-- stage; only five of each are in play (see CharactersPerStage). Walking the raw table printed
-- "1/200" on a collection whose real total is 100, i.e. a bar that could never pass halfway.
function GameConfig.CountCharacters(owned)
	local total, have = 0, 0
	for stageIndex = 1, #GameConfig.Stages do
		for _, c in ipairs(CHARACTERS_BY_STAGE[stageIndex] or {}) do
			total += 1
			if owned and owned[c.key] then have += 1 end
		end
	end
	return have, total
end

-- How many of ONE stage's list are owned, and how many there are.
function GameConfig.CountCharactersForStage(owned, stageIndex)
	local list = CHARACTERS_BY_STAGE[stageIndex] or {}
	local have = 0
	for _, c in ipairs(list) do
		if owned and owned[c.key] then have = have + 1 end
	end
	return have, #list
end

-- ===== ONE EVOLVE IS ONE SKIN, AND FIVE SKINS ARE ONE STAGE =====
--
-- The chain the player actually walks is 100 steps long, not 20. Each press hands over the next
-- character in collection order; four presses in five change only what the body looks like, and
-- the fifth also changes what it IS -- stage, size, income curve, and the zone that opens with it.
--
-- ONE FUNCTION, BECAUSE THE SERVER AND THE HUD MUST NEVER DISAGREE ABOUT WHAT THE BUTTON DOES.
-- DNAService charges exactly what this returns and MainUI prints exactly what this returns, so a
-- button that says "EVOLVE" can never be answered by a red error toast.
--
-- WHAT A STEP COSTS: the current stage's own `cost` and `xpCost`, charged on every one of its five
-- steps -- so a stage is five evolves at the price the whole stage used to be. DNA is not the
-- binding requirement (pets, mutations, potions and zone bonuses multiply it by thousands); XP is,
-- and nothing multiplies XP, so this makes a stage five levels of fighting instead of one.
function GameConfig.GetEvolveStep(data)
	local stageIndex = math.clamp((data and data.StageIndex) or 1, 1, #GameConfig.Stages)
	local stage = GameConfig.Stages[stageIndex]
	local owned = (data and data.Characters) or {}
	local have, stageTotal = GameConfig.CountCharactersForStage(owned, stageIndex)

	local step = {
		stageIndex = stageIndex,
		stage = stage,
		have = have,           -- how many of THIS stage are already collected: the "(2/5)" on the HUD
		stageTotal = stageTotal,
		entry = GameConfig.NextCharacterForStage(owned, stageIndex),
		advancesStage = false,
		isMax = false,
	}

	if not step.entry then
		-- this stage is finished, so the next press is the stage jump -- and it hands over the
		-- first skin of the stage it arrives at, which is what keeps the collection in order
		-- without a single special case anywhere else
		local nextIndex = stageIndex + 1
		local nextStage = GameConfig.Stages[nextIndex]
		if not nextStage then
			step.isMax = true
			return step
		end
		step.advancesStage = true
		step.nextStageIndex = nextIndex
		step.nextStage = nextStage
		step.entry = GameConfig.NextCharacterForStage(owned, nextIndex)
	end

	-- where the skin being handed over sits in ITS OWN stage's list, which is not the current
	-- stage's count on the fifth step
	local entryStage = step.entry and step.entry.stage or stageIndex
	step.entryIndex = step.entry and GameConfig.GetCharacterIndex(step.entry) or stageTotal
	step.entryTotal = #GameConfig.GetCharactersForStage(entryStage)

	if stage.cost == math.huge then
		step.cost = GameConfig.FinalStageStepCost
		step.xpCost = GameConfig.FinalStageStepXp
	else
		step.cost = stage.cost
		step.xpCost = stage.xpCost
	end
	return step
end

-- WHICH STAGE THE NEXT CHARACTER ROLL BELONGS TO.
--
-- Rolls used to target whatever stage the player was standing on, which spread a collection at
-- random across all twenty lists -- a player at Star Weaver owned four characters, on stages 2, 3,
-- 11 and 12, and the Journal read as twenty rows of padlocks with no way to finish any of them.
-- The roll now fills the lists IN ORDER: every Cell character, then every Bacteria one, and so on.
--
-- Capped at the stage the player has actually reached, so it can never hand out a character from
-- a stage they have not seen; once everything up to there is complete it rolls at that stage,
-- where it can only produce duplicates until the next evolve opens a new list.
function GameConfig.GetCollectionStage(owned, currentStageIndex)
	local cap = math.clamp(currentStageIndex or 1, 1, #GameConfig.Stages)
	for stageIndex = 1, cap do
		local have, total = GameConfig.CountCharactersForStage(owned, stageIndex)
		if have < total then
			return stageIndex
		end
	end
	return cap
end

-- The plain one a stage starts you as -- its Common, the first entry in the list. Rebirth puts
-- everyone back to these; see RebirthService.
function GameConfig.GetBaseCharacterForStage(stageIndex)
	local list = CHARACTERS_BY_STAGE[stageIndex]
	return list and list[1] or nil
end

return GameConfig

