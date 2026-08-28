-- GameConfig.Pets -- the whole pet system: rarities, the per-zone species, eggs and their odds, enchants, bag size and what an equipped team is worth.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

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
	-- WEIGHT 8 -> 4 (2026-08-11). "Legendary pops out of the egg far too easily" -- and measured, it
	-- did: the Premium egg was handing one over 3.8% of the time in Forest and 4.4% by AbsolutePlane,
	-- i.e. about one in 22, for the rarity the whole collection is supposed to be chasing. Halving
	-- the weight is the lever that moves every pool at once; the per-tier `rarityBias` in EGG_TIERS
	-- came down with it (see the note there), because bias was doing most of the lifting.
	--
	-- These weights feed exactly one function -- `poolWeights`, which serves the egg roll and the
	-- odds board that advertises it -- so this changes what eggs produce and nothing else.
	{ name = "Legendary", weight = 4,    bonusMult = 8.0, color = Color3.fromRGB(255, 190, 60) },

	-- ===== SECRET (12.12), AND WHY ITS WEIGHT IS ZERO =====
	--
	-- A Secret is not drawn from the weighted pool at all -- it is a separate 1-in-50,000 pre-roll in
	-- `rollAndInsert`, and only on a Premium egg. The zero here is the SECOND lock on that, behind
	-- `EggablePets` excluding them and `PetsByZone` never holding one: if a future pool ever did
	-- contain a Secret by accident, `poolWeights` would give it weight `0 * boost` = 0 and the roll
	-- could still never land on it. A rarity that must not be rollable is worth defending twice.
	--
	-- `bonusMult = 12` sits above Legendary's 8 by half again, not by an order of magnitude. The
	-- thing being sold here is that you have one, and a species 10x the game's best pet would make
	-- the 49,999 hatches that did not produce it feel like a punishment rather than a lottery.
	{ name = "Secret",    weight = 0,    bonusMult = 12,  color = Color3.fromRGB(255, 64, 160) },
}

-- FIVE LONG, DELIBERATELY, and Secret is not in it. This table is POSITIONAL -- entry i of a zone's
-- species list is `PetRarityOrder[i]` -- so appending to it would silently ask every zone for a
-- sixth species and shift nothing else. It indexes the egg pools; `PetRarities` describes what a
-- rarity is worth. The two stopped being the same list the moment a rarity existed that no egg pool
-- can contain.
GameConfig.PetRarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- Which rarities are worth a 420-stud pillar of light and everybody's attention (Phase 6.2's beam,
-- and 5.4's cross-server toast when that unblocks). A set rather than a threshold on
-- `PetRarityOrder`, because the question "is this announceable" is not the same question as "is this
-- high up the ladder" -- a future event species could be worth announcing without being a Legendary.
--
-- ONE ROW IS DELIBERATE. Epic is a 42/1600 roll, i.e. one hatch in 38 before luck; adding it here
-- would mean a beam every few seconds in a busy server, and a beam that common announces nothing.
-- Secret joined it in 12.12 and needs no cooldown thought at all: at 1 in 50,000 Premium hatches it
-- is roughly four orders of magnitude rarer than the roll this table's cooldown was written for.
GameConfig.BeaconRarities = {
	Legendary = true,
	Secret = true,
}

function GameConfig.IsBeaconRarity(name)
	return GameConfig.BeaconRarities[name] == true
end

function GameConfig.GetRarity(name)
	for _, r in ipairs(GameConfig.PetRarities) do
		if r.name == name then return r end
	end
	return GameConfig.PetRarities[1]
end

-- Every zone has its own five species -- one per rarity -- so the egg you buy in Volcano can
-- never hand you a Forest pet. Forest deliberately keeps the five original keys (Pebble, Sparky,
-- Mossy, Finn, Draco) so pets in existing saves still resolve to a real definition.
-- All emojis must be in the safe fallback band U+1F300 .. U+1F9FF.
-- Emojis outside this band either fall back to text-presentation mode (rendering as monochrome
-- outlines or standard text) or are too new and might fail to render entirely on older systems.
-- The icon layer keys off the literal emoji bytes, so do not reuse emojis across pets.
local ZONE_PETS = {
	Forest = {
		{ key = "Pebble",     name = "Pebble",      emoji = "🗻", color = Color3.fromRGB(160, 160, 160) },
		{ key = "Mossy",      name = "Mossy",       emoji = "🍀", color = Color3.fromRGB(100, 200, 100) },
		{ key = "Sparky",     name = "Sparky",      emoji = "🌩️", color = Color3.fromRGB(255, 220, 80) },
		{ key = "Finn",       name = "Finn",        emoji = "🐟", color = Color3.fromRGB(80, 160, 255) },
		{ key = "Draco",      name = "Draco",       emoji = "🐉", color = Color3.fromRGB(220, 60, 60) },
	},
	Desert = {
		{ key = "Scarab",     name = "Scarab",      emoji = "🐞", color = Color3.fromRGB(180, 150, 90) },
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
		{ key = "Cinder",     name = "Cinder",      emoji = "🕯️", color = Color3.fromRGB(84, 62, 58) },
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
		{ key = "Selenith",   name = "Selenith",    emoji = "🌛", color = Color3.fromRGB(236, 244, 255) },
	},
	Mars = {
		{ key = "Rustling",   name = "Rustling",    emoji = "🏔️", color = Color3.fromRGB(178, 88, 56) },
		{ key = "Roverpup",   name = "Roverpup",    emoji = "🤖", color = Color3.fromRGB(214, 206, 186) },
		{ key = "Dustdevil",  name = "Dustdevil",   emoji = "🌪️", color = Color3.fromRGB(226, 152, 104) },
		{ key = "Olympus",    name = "Olympus",     emoji = "🌄", color = Color3.fromRGB(140, 66, 44) },
		{ key = "Warlord",    name = "Warlord",     emoji = "🔴", color = Color3.fromRGB(226, 62, 42) },
	},
	Galaxy = {
		{ key = "Twinkle",    name = "Twinkle",     emoji = "🎇", color = Color3.fromRGB(255, 240, 190) },
		{ key = "Cometail",   name = "Cometail",    emoji = "🚀", color = Color3.fromRGB(150, 200, 255) },
		{ key = "Orbiton",    name = "Orbiton",     emoji = "🌍", color = Color3.fromRGB(206, 160, 110) },
		{ key = "Starforge",  name = "Starforge",   emoji = "🌟", color = Color3.fromRGB(255, 214, 120) },
		{ key = "Galactus",   name = "Galactus",    emoji = "🌌", color = Color3.fromRGB(150, 100, 230) },
	},
	BlackHole = {
		{ key = "Speck",      name = "Speck",       emoji = "🌗", color = Color3.fromRGB(52, 44, 66) },
		{ key = "Gravlet",    name = "Gravlet",     emoji = "🌀", color = Color3.fromRGB(120, 70, 170) },
		{ key = "Accretia",   name = "Accretia",    emoji = "💫", color = Color3.fromRGB(255, 170, 90) },
		{ key = "Horizon",    name = "Horizon",     emoji = "🕳️", color = Color3.fromRGB(24, 18, 32) },
		{ key = "Devourer",   name = "Devourer",    emoji = "😈", color = Color3.fromRGB(186, 80, 246) },
	},
	Multiverse = {
		{ key = "Gliph",      name = "Gliph",       emoji = "🔷", color = Color3.fromRGB(120, 190, 255) },
		{ key = "Echo",       name = "Echo",        emoji = "🔭", color = Color3.fromRGB(226, 226, 246) },
		{ key = "Splitpaw",   name = "Splitpaw",    emoji = "🐾", color = Color3.fromRGB(255, 120, 210) },
		{ key = "Paradox",    name = "Paradox",     emoji = "🔂", color = Color3.fromRGB(160, 120, 255) },
		{ key = "Everykind",  name = "Everykind",   emoji = "🌈", color = Color3.fromRGB(255, 100, 220) },
	},
	Nebula = {
		{ key = "Mistling",   name = "Mistling",    emoji = "🌥️", color = Color3.fromRGB(206, 168, 236) },
		{ key = "Gasbub",     name = "Gasbub",      emoji = "💨", color = Color3.fromRGB(180, 200, 255) },
		{ key = "Protostar",  name = "Protostar",   emoji = "🌠", color = Color3.fromRGB(255, 236, 190) },
		{ key = "Pillarion",  name = "Pillarion",   emoji = "🗼", color = Color3.fromRGB(224, 120, 236) },
		{ key = "Stellara",   name = "Stellara",    emoji = "💜", color = Color3.fromRGB(200, 120, 255) },
	},
	Wormhole = {
		{ key = "Loopling",   name = "Loopling",    emoji = "🔄", color = Color3.fromRGB(140, 130, 200) },
		{ key = "Throatlet",  name = "Throatlet",   emoji = "🌀", color = Color3.fromRGB(150, 100, 245) },
		{ key = "Warpcat",    name = "Warpcat",     emoji = "🐈", color = Color3.fromRGB(200, 180, 255) },
		{ key = "Tunneler",   name = "Tunneler",    emoji = "🚇", color = Color3.fromRGB(110, 90, 190) },
		{ key = "Eventide",   name = "Eventide",    emoji = "🔮", color = Color3.fromRGB(215, 200, 255) },
	},
	QuantumRealm = {
		{ key = "Quark",      name = "Quark",       emoji = "🔬", color = Color3.fromRGB(120, 220, 220) },
		{ key = "Blink",      name = "Blink",       emoji = "👁️", color = Color3.fromRGB(150, 255, 245) },
		{ key = "Superpaw",   name = "Superpaw",    emoji = "🐾", color = Color3.fromRGB(80, 220, 220) },
		{ key = "Entangle",   name = "Entangle",    emoji = "🧬", color = Color3.fromRGB(60, 190, 210) },
		{ key = "Schrodin",   name = "Schrodin",    emoji = "🐱", color = Color3.fromRGB(190, 255, 250) },
	},
	TimeRift = {
		{ key = "Tickling",   name = "Tickling",    emoji = "🕐" , color = Color3.fromRGB(200, 168, 100) },
		{ key = "Sandglass",  name = "Sandglass",   emoji = "🕛" , color = Color3.fromRGB(238, 208, 130) },
		{ key = "Cogsworth",  name = "Cogsworth",   emoji = "🔧", color = Color3.fromRGB(160, 124, 64) },
		{ key = "Rewind",     name = "Rewind",      emoji = "🔁", color = Color3.fromRGB(190, 214, 236) },
		{ key = "Chronos",    name = "Chronos",     emoji = "📼", color = Color3.fromRGB(255, 214, 110) },
	},
	AntimatterZone = {
		{ key = "Ionling",    name = "Ionling",     emoji = "🔋", color = Color3.fromRGB(180, 90, 80) },
		{ key = "Flarepup",   name = "Flarepup",    emoji = "💥", color = Color3.fromRGB(255, 140, 110) },
		{ key = "Contain",    name = "Contain",     emoji = "🧨", color = Color3.fromRGB(248, 208, 40) },
		{ key = "Nullion",    name = "Nullion",     emoji = "🚫", color = Color3.fromRGB(255, 70, 70) },
		{ key = "Annihil",    name = "Annihil",     emoji = "💣", color = Color3.fromRGB(255, 40, 40) },
	},
	DreamDimension = {
		{ key = "Napkin",     name = "Napkin",      emoji = "😴", color = Color3.fromRGB(226, 208, 246) },
		{ key = "Fluffle",    name = "Fluffle",     emoji = "🌤️", color = Color3.fromRGB(255, 206, 236) },
		{ key = "Sleepaw",    name = "Sleepaw",     emoji = "🐑", color = Color3.fromRGB(240, 240, 255) },
		{ key = "Reverie",    name = "Reverie",     emoji = "💭", color = Color3.fromRGB(200, 160, 255) },
		{ key = "Sandman",    name = "Sandman",     emoji = "🌜", color = Color3.fromRGB(214, 150, 255) },
	},
	MirrorUniverse = {
		{ key = "Shardlet",   name = "Shardlet",    emoji = "🔹", color = Color3.fromRGB(200, 214, 238) },
		{ key = "Reflekt",    name = "Reflekt",     emoji = "💽", color = Color3.fromRGB(226, 232, 250) },
		{ key = "Twinpaw",    name = "Twinpaw",     emoji = "👯", color = Color3.fromRGB(180, 200, 255) },
		{ key = "Inverso",    name = "Inverso",     emoji = "🔃", color = Color3.fromRGB(150, 170, 220) },
		{ key = "Mirrorch",   name = "Mirrorch",    emoji = "💠", color = Color3.fromRGB(240, 248, 255) },
	},
	VoidExpanse = {
		{ key = "Nibble",     name = "Nibble",      emoji = "🕸️", color = Color3.fromRGB(60, 50, 78) },
		{ key = "Hollow",     name = "Hollow",      emoji = "🌑", color = Color3.fromRGB(38, 30, 52) },
		{ key = "Unraveler",  name = "Unraveler",   emoji = "🧵", color = Color3.fromRGB(148, 62, 228) },
		{ key = "Nihil",      name = "Nihil",       emoji = "🌚" , color = Color3.fromRGB(20, 16, 28) },
		{ key = "Voidmaw",    name = "Voidmaw",     emoji = "👾", color = Color3.fromRGB(170, 80, 255) },
	},
	CelestialThrone = {
		{ key = "Cherub",     name = "Cherub",      emoji = "👼", color = Color3.fromRGB(255, 238, 200) },
		{ key = "Haloling",   name = "Haloling",    emoji = "😇", color = Color3.fromRGB(255, 226, 150) },
		{ key = "Seraphim",   name = "Seraphim",    emoji = "🕊️", color = Color3.fromRGB(255, 250, 226) },
		{ key = "Regalia",    name = "Regalia",     emoji = "👑", color = Color3.fromRGB(255, 218, 128) },
		{ key = "Throneus",   name = "Throneus",    emoji = "🏆", color = Color3.fromRGB(255, 200, 70) },
	},
	Singularity = {
		{ key = "Point",      name = "Point",       emoji = "🔵", color = Color3.fromRGB(226, 230, 244) },
		{ key = "Collapse",   name = "Collapse",    emoji = "🌐", color = Color3.fromRGB(190, 200, 226) },
		{ key = "Infinion",   name = "Infinion",    emoji = "🔀", color = Color3.fromRGB(255, 255, 255) },
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

-- ===== APEX-ONLY PETS =====
-- One species per zone that no egg can ever hatch. The only source is a kill on that zone's Apex,
-- so a player who has not cleared 3 rebirths cannot hold one. Shaped like a ZONE_PETS entry and
-- keyed by zone, but deliberately kept OUT of ZONE_PETS so the egg roll can never reach it -- the
-- rarity of these is the whole point. Every key is unique against the 100 in ZONE_PETS, and the
-- colours are the prestige read of each zone's palette: brighter and cleaner than the egg pets,
-- never the muddy version.
local EXCLUSIVE_PETS = {
	Forest          = { key = "Sylvanking", name = "Sylvan King", emoji = "\u{1F333}",         color = Color3.fromRGB(90, 235, 120) },
	Desert          = { key = "Vitreon",    name = "Vitreon",     emoji = "\u{1F3FA}",         color = Color3.fromRGB(255, 198, 72) },
	Ocean           = { key = "Leviathan",  name = "Leviathan",   emoji = "\u{1F40B}",         color = Color3.fromRGB(64, 232, 255) },
	Volcano         = { key = "Moltenking", name = "Molten King", emoji = "🌫️",  color = Color3.fromRGB(255, 128, 24) },
	Moon            = { key = "Lunarch",    name = "Lunarch",     emoji = "\u{1F320}",         color = Color3.fromRGB(222, 240, 255) },
	Mars            = { key = "Ironcrown",  name = "Iron Crown",  emoji = "\u{1F6E1}\u{FE0F}", color = Color3.fromRGB(255, 96, 64) },
	Galaxy          = { key = "Spiralux",   name = "Spiralux",    emoji = "\u{1F300}",         color = Color3.fromRGB(196, 148, 255) },
	BlackHole       = { key = "Abyssos",    name = "Abyssos",     emoji = "\u{1F480}",         color = Color3.fromRGB(172, 72, 255) },
	Multiverse      = { key = "Manifold",   name = "Manifold",    emoji = "\u{1F9FF}",         color = Color3.fromRGB(255, 110, 235) },
	Nebula          = { key = "Nebulark",   name = "Nebulark",    emoji = "\u{1F30C}",         color = Color3.fromRGB(236, 126, 255) },
	Wormhole        = { key = "Elsewhere",  name = "Elsewhere",   emoji = "\u{1F573}\u{FE0F}", color = Color3.fromRGB(186, 130, 255) },
	QuantumRealm    = { key = "Quanton",    name = "Quanton",     emoji = "\u{1F4A0}",         color = Color3.fromRGB(86, 255, 240) },
	TimeRift        = { key = "Aeonis",     name = "Aeonis",      emoji = "\u{1F570}\u{FE0F}", color = Color3.fromRGB(255, 220, 96) },
	AntimatterZone  = { key = "Positron",   name = "Positron",    emoji = "🔌",          color = Color3.fromRGB(255, 172, 48) },
	DreamDimension  = { key = "Oneiros",    name = "Oneiros",     emoji = "\u{1F984}",         color = Color3.fromRGB(218, 140, 255) },
	MirrorUniverse  = { key = "Silverself", name = "Silver Self", emoji = "\u{1F48E}",         color = Color3.fromRGB(238, 248, 255) },
	VoidExpanse     = { key = "Nullarch",   name = "Nullarch",    emoji = "\u{1F7E3}",         color = Color3.fromRGB(190, 88, 255) },
	CelestialThrone = { key = "Empyrean",   name = "Empyrean",    emoji = "\u{1F31E}",         color = Color3.fromRGB(255, 230, 130) },
	Singularity     = { key = "Zeropoint",  name = "Zero Point",  emoji = "🎯",  color = Color3.fromRGB(198, 240, 255) },
	AbsolutePlane   = { key = "Primordia",  name = "Primordia",   emoji = "🌅",  color = Color3.fromRGB(255, 246, 196) },
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

-- ===== THE SPECIES NO EGG CAN REACH (11.6) =====
--
-- One per zone, dropped only by that zone's Apex, which stands on the highest shelf behind three
-- rebirths. **The unreachability is structural, not a rule somebody has to remember**: every egg
-- path bottoms out in `GetEggPool`, which reads `PetsByZone`, and these are inserted into
-- `GameConfig.Pets` and `ExclusivePetsByZone` and into neither of those. There is no flag to check
-- and no branch to forget -- the roll simply has nowhere to find them.
--
-- They still enter `GameConfig.Pets` on purpose: that is the table the Journal walks, so an
-- exclusive shows in the collection as a locked slot with a name. A goal you cannot see is not a
-- goal. It is also what `GetPetDef` scans, so a save holding one resolves normally everywhere else
-- in the game -- power, fusion, trading, the follower rig.
--
-- Rarity is Legendary rather than a sixth tier. A new rarity would mean a new weight, a new colour,
-- a new Journal section and a new beam rule, for a distinction the player already reads off "this
-- came out of an Apex". `exclusive = true` carries that meaning for the code that needs it.
GameConfig.ExclusivePetsByZone = {}
for _, zone in ipairs(GameConfig.Zones) do
	local p = EXCLUSIVE_PETS[zone.key]
	if p then
		local def = {
			key = p.key,
			name = p.name,
			emoji = p.emoji,
			color = p.color,
			zone = zone.key,
			rarity = "Legendary",
			exclusive = true,
		}
		table.insert(GameConfig.Pets, def)
		GameConfig.ExclusivePetsByZone[zone.key] = { def }
	end
end

-- ===== THE SPECIES ALMOST NOBODY WILL EVER SEE (12.12) =====
--
-- One per zone, and the ONLY way to get one is a Premium egg landing a 1-in-50,000 pre-roll that
-- happens before the ordinary weighted roll is even reached. They are not in `PetsByZone`, so no
-- pool contains them; they are not in `EggablePets`, so no fallback reaches them; and their rarity
-- carries `weight = 0`, so a pool that somehow did contain one still could not roll it. Three
-- independent locks, because the whole product here is scarcity and a leak is unrecoverable -- a
-- Secret handed out by accident cannot be taken back without touching saves.
--
-- WHY THEY ARE STILL IN `GameConfig.Pets`: that is what `GetPetDef` scans, and a save holding one
-- has to resolve everywhere else in the game -- the follower rig, fusion, the damage arithmetic,
-- trading, the inventory card. A species the code cannot name is a species that breaks the panel
-- it appears in.
--
-- Colours are the zone's palette pushed to its most saturated reading, and every key is unique
-- against the 100 in ZONE_PETS and the 20 in EXCLUSIVE_PETS -- `GetPetDef` is a linear scan over
-- one flat list, so a duplicate key would resolve to whichever was inserted first and the loser
-- would silently become invisible. Rigs cost nothing: `PetModel.Build` hashes the key to one of
-- five archetypes and paints it with `color`, so twenty new species are twenty rows, not assets.
local SECRET_PETS = {
	Forest          = { key = "Thornheart", name = "Thorn Heart", emoji = "\u{1F340}",         color = Color3.fromRGB(128, 255, 170) },
	Desert          = { key = "Mirageon",   name = "Mirageon",    emoji = "\u{1F3DC}\u{FE0F}", color = Color3.fromRGB(255, 222, 150) },
	Ocean           = { key = "Tidewraith", name = "Tide Wraith", emoji = "\u{1F30A}",         color = Color3.fromRGB(110, 255, 238) },
	Volcano         = { key = "Ashenmaw",   name = "Ashen Maw",   emoji = "\u{1F525}",         color = Color3.fromRGB(255, 150, 60) },
	Moon            = { key = "Eclipsyl",   name = "Eclipsyl",    emoji = "\u{1F311}",         color = Color3.fromRGB(200, 215, 255) },
	Mars            = { key = "Rustwake",   name = "Rust Wake",   emoji = "\u{1F6F0}\u{FE0F}", color = Color3.fromRGB(255, 130, 96) },
	Galaxy          = { key = "Starweaver", name = "Star Weaver", emoji = "\u{1F9F6}",          color = Color3.fromRGB(210, 170, 255) },
	BlackHole       = { key = "Umbrion",    name = "Umbrion",     emoji = "🌘",          color = Color3.fromRGB(190, 110, 255) },
	Multiverse      = { key = "Paradoxa",   name = "Paradoxa",    emoji = "\u{1F3AD}",         color = Color3.fromRGB(255, 140, 240) },
	Nebula          = { key = "Auroran",    name = "Auroran",     emoji = "\u{1F386}",         color = Color3.fromRGB(255, 160, 255) },
	Wormhole        = { key = "Loopwalker", name = "Loop Walker", emoji = "\u{1F517}",         color = Color3.fromRGB(200, 150, 255) },
	QuantumRealm    = { key = "Superposit", name = "Superposit",  emoji = "🎲",  color = Color3.fromRGB(120, 255, 246) },
	TimeRift        = { key = "Chronaught", name = "Chronaught",  emoji = "🎱",          color = Color3.fromRGB(255, 230, 130) },
	AntimatterZone  = { key = "Antiphase",  name = "Antiphase",   emoji = "🔫",  color = Color3.fromRGB(255, 190, 80) },
	DreamDimension  = { key = "Somnivore",  name = "Somnivore",   emoji = "\u{1F4AD}",         color = Color3.fromRGB(232, 170, 255) },
	MirrorUniverse  = { key = "Inversal",   name = "Inversal",    emoji = "💿",         color = Color3.fromRGB(245, 252, 255) },
	VoidExpanse     = { key = "Voidsong",   name = "Void Song",   emoji = "\u{1F5A4}",         color = Color3.fromRGB(206, 120, 255) },
	CelestialThrone = { key = "Divinark",   name = "Divinark",    emoji = "\u{1F531}",         color = Color3.fromRGB(255, 240, 180) },
	Singularity     = { key = "Kernel",     name = "Kernel",      emoji = "🌰",          color = Color3.fromRGB(230, 240, 255) },
	AbsolutePlane   = { key = "Genesis",    name = "Genesis",     emoji = "\u{1F31F}",         color = Color3.fromRGB(255, 252, 220) },
}

GameConfig.SecretPetsByZone = {}
for _, zone in ipairs(GameConfig.Zones) do
	local p = SECRET_PETS[zone.key]
	if p then
		local def = {
			key = p.key,
			name = p.name,
			emoji = p.emoji,
			color = p.color,
			zone = zone.key,
			rarity = "Secret",
			secret = true,
		}
		table.insert(GameConfig.Pets, def)
		GameConfig.SecretPetsByZone[zone.key] = def
	end
end

-- ===== THE PRE-ROLL =====
--
-- Priced as one number rather than as a weight, because it is not competing with the other species
-- for share -- it happens first, and the ordinary roll runs only when it does not. That is also why
-- luck is capped here: the shared luck total reaches ~400 in the worst honest case (2.12's
-- measurement), and an uncapped `1 + luck/1000` on a future luck ceiling would quietly turn a
-- 1-in-50,000 into a 1-in-a-few-thousand. At the cap this is 1 in 35,714 -- luck is worth having and
-- is not the feature.
GameConfig.Secret = {
	chance = 1 / 50000,
	luckCap = 400,
	luckDiv = 1000,
}

function GameConfig.GetSecretChance(luckPercent)
	local s = GameConfig.Secret
	return s.chance * (1 + math.min(luckPercent or 0, s.luckCap) / s.luckDiv)
end

-- PREMIUM ONLY. The tier is what the whole thing hangs off -- the expensive egg has to be worth its
-- 9x over the Basic one for a reason the player can name, and "it is the only egg that can do this"
-- is a better reason than a third of a percent of Legendary. One predicate, read by the roll and by
-- both odds boards, so the advertisement and the behaviour cannot drift.
function GameConfig.CanEggHatchSecret(egg)
	return egg ~= nil and egg.tierSuffix == "Premium" and GameConfig.SecretPetsByZone[egg.zone] ~= nil
end

function GameConfig.GetSecretPetForEgg(egg)
	return egg and GameConfig.SecretPetsByZone[egg.zone] or nil
end

-- ===== AND THE FALLBACK POOL HAD TO STOP BEING `GameConfig.Pets` =====
--
-- `RollFromPool` and `GetEggPool` both fall back to the flat list when they are handed a malformed
-- or empty pool -- an egg with no `zone`, a zone with no species. That fallback is now the ONE way
-- an exclusive could still come out of an egg, so it points at this list instead: everything that is
-- not exclusive, built once. The hole is closed at the bottom of the funnel rather than at each of
-- the three call sites above it, which is the only version of this that a future egg type cannot
-- reopen by accident.
--
-- `not def.secret` joined it in 12.12 for exactly the same reason and in the same commit as the
-- species themselves: a Secret reachable through the malformed-egg fallback would be a Secret with
-- a 1-in-120 chance instead of a 1-in-50,000 one, which is the failure this list exists to prevent.
GameConfig.EggablePets = {}
for _, def in ipairs(GameConfig.Pets) do
	if not def.exclusive and not def.secret then
		table.insert(GameConfig.EggablePets, def)
	end
end

-- The pool a terrace kill rolls against: the zone's ordinary five on layer 1, its one exclusive on
-- layer 2. Returns nil when the layer pays no pet at all, so the caller's `if pool` is the whole
-- test -- there is no second question about whether this creature drops.
function GameConfig.GetTerracePetPool(zoneKey, raised)
	local layer = GameConfig.GetRaisedLayer(raised)
	if not layer then return nil end
	if layer.exclusive then
		return GameConfig.ExclusivePetsByZone[zoneKey]
	end
	return GameConfig.PetsByZone[zoneKey]
end

function GameConfig.GetPetDef(key)
	for _, p in ipairs(GameConfig.Pets) do
		if p.key == key then return p end
	end
	return nil
end

-- ===== WHAT A PET IS WORTH: DAMAGE AND LUCK, AND NOTHING ELSE =====
--
-- `incomeMult` and `dnaMult` are GONE from this table, and their removal is the single largest
-- economy fix in this phase. They were 1.4 and 2 here, scaled by tier x rarity and then stacked
-- MULTIPLICATIVELY across every equipped slot in PetService.GetEquippedBonus -- so one Legendary
-- Normal pet was worth incomeMult 4.2 x dnaMult 9.0 = **x37.8 on every kill and every click**.
-- That is the reported "DNA was ~60, then I got my first pet and it was ~1,000", and it is the
-- same defect this repo has now corrected four times: a quantity that multiplies once per item,
-- over a collection that only grows, is not a bonus, it is an exponential in the number of slots
-- (see GetMutationIncomeMult, the idle-income cap, and the damage half of this same function in
-- 9.1). The economy is now what it was tuned to be -- 14 to 20 kills per stage -- because that
-- curve was authored against a player with no pets at all.
--
-- A pet pays DAMAGE, and the player earns more DNA because creatures die faster. That is the
-- whole design: pets are a combat stat, not an income stat. `luckAdd` stays because luck is
-- additive everywhere in this game and cannot compound.
--
-- `luckAdd` 5 -> 12, AND it is now scaled by the damage SHARE rather than by the raw tier x rarity
-- product. That reads like a raise and is a large cut, and the live test is what found it.
--
-- With incomeMult and dnaMult gone, luck was the last surviving pet -> DNA channel and it was not a
-- small one: luck feeds crit chance (`clamp(5 + luck * 0.5, 0, 75)` for a x5 payout), one Legendary
-- paid 40 luck points, and five paid 180 -- which pins crit at its 75% cap and multiplies the mean
-- click by 3.3x. Measured: with the multipliers already removed, the mean click still ran 3.38 ->
-- 5.15 -> 10.40 DNA across zero, one and five pets. That is the reported bug arriving by a third
-- route, quieter and bounded, but the same sentence: "I got a pet and my DNA jumped."
--
-- One pet was also worth 40 points against the 249 R$ Lucky pass's 50, so a free first hatch nearly
-- matched a premium purchase and five of them beat it four times over -- out of band whatever it
-- did to DNA. On the share scale a Legendary Normal is 9.6 points and a full first-egg team sits
-- under one Lucky pass, while a maxed nine-slot endgame team reaches ~360, inside the worst honest
-- case Phase 2.12 already swept and found bounded.
GameConfig.PetBaseBonus = { luckAdd = 12, incomeMult = 1, dnaMult = 1 }

-- ===== EGG TIER x RARITY x PROGRESSION =====
--
-- A pet's damage contribution is a SHARE OF THE PLAYER'S OWN BARE DAMAGE, summed across the
-- equipped slots. Expressing it as a share rather than as an absolute number is what makes the
-- three axes composable and what keeps the whole team bounded however many slots open up.
--
-- Share per pet = PetRarityShare(rarity) x PetTierShare(tier) x zone factor.
--
-- PetRarityShare reuses the authored `bonusMult` ladder divided by ten, so rarity ordering has
-- exactly one source of truth and a future rarity row needs no second edit here: Common 0.10 up
-- to Legendary 0.80.
GameConfig.PetRarityShareScale = 0.1

-- ...and the tier ladder is 1 / 1.6 / 2.6 / 4.2 rather than the old 1 / 2 / 4 / 8. The old
-- doubling was authored for a MULTIPLICATIVE stat, where a x8 top tier is one factor among
-- several; against a SUM it would put nine max-tier Legendaries at x58 the player's own damage.
-- The shape here is the rarity ladder's own, which keeps a fuse feeling like a real step (+60%
-- of that pet's share) without the top of the ladder swallowing the game.
GameConfig.PetTierShare = { Normal = 1, Golden = 1.6, Rainbow = 2.6, Celestial = 4.2 }

-- ===== ENCHANTS: THE FOURTH FACTOR ON THE SHARE, AND THE FIRST REPEATABLE DIAMOND SINK (13.1) =====
--
-- Share per pet is PetRarityShare x PetTierShare x zone factor x ENCHANT, and this is the only one
-- of the four a player can buy repeatedly. It exists because the Diamond economy has no terminal
-- sink: DiamondUpgrades is three tiles (one capped at level 3) and StageMastery is twenty one-shot
-- purchases totalling ~700 diamonds, so a player who has bought both has nothing left to want while
-- every kill keeps paying. An enchant is permanent, per-pet and repeatable, which is the shape a
-- sink has to have to absorb an income that never stops.
--
-- ===== SIZED AGAINST A NINE-SLOT TEAM, NOT AGAINST ONE PET =====
--
-- The shares SUM (see GetEquippedBonus), so a multiplier here is felt nine times over at the top of
-- the game. A maxed endgame team of nine Celestial Legendaries sits at 9 x 0.8 x 4.2 = 30.2 shares,
-- i.e. x31.2 the player's own damage; putting the top rung on all nine takes that to x50.9. That is
-- the ceiling this ladder is chosen against, and it is why the top rung is x1.65 rather than the
-- x3 the name "Eternal" invites. The same arithmetic is what killed the old mutation ladder in 12.1
-- -- a multiplier that stacks with nothing to stop it is not a reward, it is an inflation faucet.
--
-- ===== WEIGHTS SUM TO 100 ON PURPOSE =====
--
-- The panel prints them as percentages and the roll walks them as weights, so the two can never
-- disagree about what the game is actually doing. A future rung is a row here plus nothing else --
-- as long as the column still sums to 100, which GameConfig.AssertEnchantWeights checks at load.
--
-- ===== LUCK DOES NOT ENTER THIS ROLL, AND THAT IS A DESIGN DECISION =====
--
-- Every other roll in this game is loot and every one of them reads luck. This one is a permanent
-- stat multiplier bought with a currency no pass produces, so paying luck into it would let a
-- 249 R$ purchase buy a permanent team multiplier more cheaply than a player who farmed for it --
-- the pay-to-win line the pass table has stayed behind since Phase 2. The lever on this ladder is
-- the PRICE, which is the same lever the Splicer uses and the one a player can see.
GameConfig.Enchants = {
	{ key = "keen",      name = "Keen",      mult = 1.06, weight = 44,  color = Color3.fromRGB(150, 200, 240) },
	{ key = "fierce",    name = "Fierce",    mult = 1.14, weight = 26,  color = Color3.fromRGB(120, 210, 140) },
	{ key = "savage",    name = "Savage",    mult = 1.24, weight = 15,  color = Color3.fromRGB(240, 176, 84)  },
	{ key = "radiant",   name = "Radiant",   mult = 1.36, weight = 9,   color = Color3.fromRGB(246, 122, 96)  },
	{ key = "prismatic", name = "Prismatic", mult = 1.48, weight = 4.5, color = Color3.fromRGB(196, 118, 246) },
	-- `announce` is this ladder's `IsBeaconRarity`: the table that knows which rung is rare is the
	-- table AnnounceService asks, so a new top rung is a row here and no edit there.
	{ key = "eternal",   name = "Eternal",   mult = 1.65, weight = 1.5, color = Color3.fromRGB(255, 214, 92), announce = true },
}

-- Keyed view, built once. Every reader goes through GetEnchantDef so a bad key from a save or from
-- a client message resolves to nil rather than to an error.
local ENCHANT_BY_KEY = {}
for i, e in ipairs(GameConfig.Enchants) do
	e.rank = i
	ENCHANT_BY_KEY[e.key] = e
end

function GameConfig.GetEnchantDef(key)
	return key and ENCHANT_BY_KEY[key] or nil
end

-- The one number the damage chain reads. Takes the KEY (not the def) and answers 1 for nil, for an
-- unknown key and for a pet minted before enchants existed -- which is every pet in every save on
-- the day this ships, and is the whole reason no Load repair is needed (the 6.3 rule).
function GameConfig.GetEnchantMult(key)
	local def = GameConfig.GetEnchantDef(key)
	return def and def.mult or 1
end

-- Strictly better, never "at least as good": the caller keeps what it has on a tie, so a re-roll
-- that lands on the same rung cannot churn the save or claim an upgrade that is not one.
function GameConfig.IsEnchantBetter(candidate, current)
	return GameConfig.GetEnchantMult(candidate) > GameConfig.GetEnchantMult(current)
end

function GameConfig.RollEnchant()
	local total = 0
	for _, e in ipairs(GameConfig.Enchants) do total += e.weight end
	local roll = math.random() * total
	for _, e in ipairs(GameConfig.Enchants) do
		roll -= e.weight
		if roll <= 0 then return e.key end
	end
	-- float dust only; the loop above consumes the whole range
	return GameConfig.Enchants[#GameConfig.Enchants].key
end

-- ===== THE PRICE, AND WHY IT IS FLAT IN DIAMONDS =====
--
-- Priced by TIER and by nothing else. Tier is exactly what makes an enchant worth more -- the share
-- is a product, so the same rung on a Celestial is worth 4.2x what it is worth on a Normal -- and a
-- price that tracked the player's stage instead would make the sink cheapest for the players who
-- have the most diamonds. Diamonds are deliberately raw (see the note over the Diamond products):
-- "45 Diamonds" is true at every stage of the game, which is what lets the button quote a number a
-- player can plan against.
--
-- Reaching the top rung on one Celestial costs roughly 46 rolls at 50/50 odds, i.e. ~3,200 diamonds
-- against ~700 for the entire Stage Mastery set. That is deliberate: this is the sink that is meant
-- to still be there after everything else is bought.
GameConfig.EnchantCost = { Normal = 20, Golden = 30, Rainbow = 45, Celestial = 70 }

function GameConfig.GetEnchantCost(pet)
	return GameConfig.EnchantCost[pet and pet.tier or "Normal"] or GameConfig.EnchantCost.Normal
end

-- ===== MOVING AN ENCHANT, AND WHY THE PRICE IS 1,000 (34.5) =====
--
-- The transfer's worth to a player is exactly what RE-ROLLING that enchant on the target pet would
-- cost, so the price has to sit between the two ends of that range or the feature is dead:
-- too cheap and it replaces enchanting, too dear and nobody ever presses it.
--
-- The arithmetic. `eternal` is weight 1.5 of 100, so it takes ~67 rolls in expectation -- 1,330
-- diamonds on a Normal, ~4,670 on a Celestial. `prismatic` is 4.5, ~22 rolls, ~1,550 on a
-- Celestial. `keen` is 44, ~2 rolls, ~160. **1,000 is under every re-roll worth moving and over
-- every one that is not**, which makes this the button you press when a Celestial finally hatches
-- and your Eternal is sitting on a Normal -- and never the button you press instead of enchanting.
--
-- It is also the top vanity price (34.2's 1,000-diamond trail), so the two endgame sinks quote the
-- same headline number and a player can weigh them against each other without arithmetic.
--
-- ONE constant, read by the server that charges it and by the button that quotes it, for the same
-- reason `GetEnchantCost` is: a price written twice is a price that will disagree with itself.
GameConfig.EnchantTransferCost = 1000

-- Same defence as AssertTierCoverage: a weights column that quietly stops summing to 100 turns
-- every printed percentage into a lie, and nothing else in the game would notice.
function GameConfig.AssertEnchantWeights()
	local total = 0
	for _, e in ipairs(GameConfig.Enchants) do total += e.weight end
	if math.abs(total - 100) > 1e-6 then
		warn(("[GameConfig] Enchant weights sum to %.4f, not 100 -- the odds table is now a lie"):format(total))
	end
	return total
end

-- THE PROGRESSION AXIS, and the reason an early Legendary is no longer a late Legendary.
--
-- GetPetBonus used to take only (tier, rarity), so a Forest Basic-egg Legendary and an Absolute
-- Plane Premium-egg Legendary were byte-identical -- both +240% damage, at a 1.8e13x difference in
-- egg price. The egg tier decided only WHICH rarities could roll, never what a rarity was worth.
--
-- The zone factor is the ratio of what the pet's own zone hits for to what the PLAYER hits for
-- now, so a pet is at full strength in the zone it came from and fades as the player climbs past
-- it. It needs NO new save field and NO migration: every species already carries `zone` (see the
-- ZONE_PETS flatten above), so the zone of any pet ever hatched is recoverable from its key.
--
-- FLOORED at 0.25 rather than allowed to reach zero. An old pet that decayed to nothing would
-- make a veteran's collection worthless overnight, which is the kind of change that reads as a
-- broken save rather than as a rebalance -- the rule this repo already followed when the rebirth
-- ladder grandfathered eight spent rebirths.
--
-- ===== BUT THE FLOOR IS APPROACHED, NEVER CLAMPED TO, AND THE TEST IS WHY =====
--
-- The first cut of this was `math.clamp(ratio, 0.25, 1)`, and the balance sweep found it wrong in
-- exactly the place the whole rebalance exists to fix. Damage is geometric, so the ratio collapses
-- fast: at rank 96 a zone-1 pet scores 0.0009 and a zone-10 pet 0.026 -- BOTH below the floor, so
-- both clamped to 0.25 and an early-egg Legendary was worth precisely as much as a mid-game one.
-- The brief's requirement is Early < Mid < Late, and a clamp satisfies it only until the floor is
-- reached, after which it silently reintroduces the bug at the end of the game.
--
-- Compressed instead: floor + (1 - floor) * sqrt(ratio). Monotonic over the whole domain, so the
-- ordering can never flatten however far apart the two zones are, while the square root keeps the
-- decay gentle enough that walking into the next zone does not visibly weaken the team the player
-- just built. At rank 96 that reads 0.27 / 0.37 / 1.00 for a zone-1 / zone-10 / zone-20 Legendary.
GameConfig.PetZoneFloor = 0.25

GameConfig.PetTiers = { "Normal", "Golden", "Rainbow", "Celestial" }
-- Kept for PetModel, which sizes the rendered rig off it. Deliberately NOT used by any stat any
-- more -- PetTierShare above is the stat ladder. A bigger Celestial is a visual promise, and the
-- two numbers are allowed to disagree because they answer different questions.
GameConfig.PetTierMultiplier = { Normal = 1, Golden = 2, Rainbow = 4, Celestial = 8 }
GameConfig.PetTierColor = {
	Normal = Color3.fromRGB(220, 220, 220),
	Golden = Color3.fromRGB(255, 215, 60),
	Rainbow = Color3.fromRGB(255, 120, 220),
	Celestial = Color3.fromRGB(120, 220, 255),
}
-- ===== THREE COPIES, NOT FOUR (11.7) =====
--
-- The whole ladder is this number raised to a power: a Rainbow costs `n^2` Normals of one species
-- and a Celestial `n^3`. At four that is 16 and **64**, against an inventory ceiling of 100 that also
-- has to hold a collection -- so Celestial was not really reachable, it was theoretically reachable.
-- At three it is 9 and **27**, which is what the MaxOwnedPets note above was already written against
-- when 11.10 raised the cap to 100: that comment has said "27 copies at the 3-per-fuse requirement"
-- since before this constant moved. This is the line catching up with a decision already made.
--
-- Everything reads it: PetService's refusal and its loop, the fusion panel's counter and button, and
-- the world sign at the fusion pad. That last one is baked at BUILD time, so ZoneBuilder's
-- BUILD_VERSION has to move with this or the sign in the world keeps advertising four.
GameConfig.FuseRequirement = 3
GameConfig.MaxEquippedPets = 3

-- ===== HOW MANY PETS A SAVE MAY HOLD =====
--
-- 100. It was 600 first — a figure set to protect the DataStore (a save past 4 MB stops saving
-- forever with nothing but a warning) rather than to shape play, and at 600 it did neither: a live
-- save reached **207 pets**, which is not an inventory, it is a spreadsheet nobody scrolls. It then
-- went to 30, which shaped play too hard: fusion needs identical copies, so a ceiling of 30 put
-- Celestial (27 copies at the 3-per-fuse requirement) out of reach of an inventory that also has to
-- hold anything a player wants to keep.
--
-- 100 is the number where both are true: far under the DataStore wall, and roomy enough that the
-- fusion ladder can actually be climbed while keeping a collection beside it.
--
-- RAISING THIS IS SAFE FOR EXISTING SAVES and lowering it is not. `PlayerDataService`'s trim only
-- runs on `#data.Pets > MaxOwnedPets`, which after a raise is true for nobody; the `PetsTrimmedAt`
-- stamp left at 30 on already-trimmed saves simply never matches again and goes inert. No save is
-- touched a second time.
--
-- IT LIVES HERE so `PetService`, `TradeService` and `MainUI` all read one number. Both services
-- kept private copies before, deliberately, because "these two files must not require each other" —
-- but they both already require GameConfig, so the shared dependency was always available and the
-- duplication only bought a way for the two ceilings to drift apart.
GameConfig.MaxOwnedPets = 100

-- How close two players have to stand to open a trade, and to still be standing when it commits.
-- It is the anti-scam half of 8.1: a stranger cannot open a window at you from across the map.
--
-- IT LIVES HERE for the same reason MaxOwnedPets does, and it moved here the moment a SECOND
-- reader appeared. `TradeService` enforces it; the trade player picker in `MainUI` has to tell the
-- player which of the people in the server are close enough to ask, and a client that prints "in
-- range" off its own copy of the number is a client that will eventually promise a request the
-- server refuses. One number, one meaning, two files that already require this one.
GameConfig.TradeProximityStuds = 40

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
-- BIASES HALVED 2026-08-11, with the Legendary weight 8 -> 4 (see the Rarities table). Between them
-- the Premium egg went from ~3.8-4.4% Legendary to ~1.6-2.1% and the Better egg from ~1.0-1.4% to
-- ~0.4-0.7%. Bias was doing most of the work: at the old 2.8 the Premium egg multiplied a
-- Legendary's weight by nearly seven before luck was counted at all.
--
-- The ORDER of the two levers matters if you re-tune. `rarityBias` is scaled by `rarityFactor`, so
-- it lifts the rarest species hardest and barely touches the commonest; the weight is flat. Reach
-- for the weight to move the floor and for the bias to move how much the expensive egg is worth
-- over the cheap one. Basic stays at 0 and `rarityMax = 4`, which is what makes a Legendary
-- structurally impossible out of it -- that is a feature, not a number to tune.
local EGG_TIERS = {
	{ suffix = "Basic",   emoji = "🥚", costMult = 1,   luckAdd = 0,  rarityBias = 0,    rarityMin = 1, rarityMax = 4 },
	{ suffix = "Better",  emoji = "🐣", costMult = 3.5, luckAdd = 10, rarityBias = 0.55, rarityMin = 1, rarityMax = 5 },
	{ suffix = "Premium", emoji = "🌟", costMult = 9,   luckAdd = 22, rarityBias = 1.4,  rarityMin = 2, rarityMax = 5 },
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

-- HOW MUCH OF ITS SHARE THIS PET STILL DELIVERS, given where the player now stands.
--
-- 1.0 in the pet's own zone and falling as the player climbs past it, floored at PetZoneFloor.
-- `data` is optional: with no save to compare against there is no progression axis to apply, so it
-- returns 1 and the pet is quoted at full strength -- which is the right answer for the Journal and
-- for any preview that is describing a species rather than a player's loadout.
--
-- Clamped at the TOP as well as the bottom. A pet from a zone ahead of the player cannot normally
-- exist (HandleBuyEgg refuses an egg from a locked zone), but a trade, an old save or a future
-- reward could hand one over, and a factor above 1 would make it pay more than its own zone's
-- reference damage for as long as the player stayed behind it.
function GameConfig.GetPetZoneFactor(petKey, data)
	if not data then return 1 end
	local def = GameConfig.GetPetDef(petKey)
	if not def or not def.zone then return 1 end
	local petRef = GameConfig.GetZoneReferenceDamage(GameConfig.GetZoneIndex(def.zone))
	local playerDamage = GameConfig.GetRankDamage(GameConfig.GetProgressRank(data))
	if playerDamage <= 0 then return 1 end
	-- clamped to [0,1] FIRST -- a pet from a zone ahead of the player would otherwise push the root
	-- above 1 and pay more than its own zone's reference damage
	local ratio = math.clamp(petRef / playerDamage, 0, 1)
	local floor = GameConfig.PetZoneFloor
	return floor + (1 - floor) * math.sqrt(ratio)
end

-- `rarity` is optional so old call sites keep working; omitted means Common. `petKey` and `data`
-- are both optional and are the progression axis -- pass them and the answer is what this pet is
-- worth to THIS player right now; omit them and it is what the species is worth at its own zone.
-- `enchant` is the fifth and last axis and it is a KEY, not a def -- every call site already holds
-- the pet entry, so passing `pet.enchant` is a one-token change and no caller has to learn what an
-- enchant is. Omitted, nil, or a key this build does not know all resolve to x1.
function GameConfig.GetPetBonus(tier, rarity, petKey, data, enchant)
	local rarityShare = GameConfig.GetRarity(rarity).bonusMult * GameConfig.PetRarityShareScale
	local tierShare = GameConfig.PetTierShare[tier] or 1
	local zoneFactor = petKey and GameConfig.GetPetZoneFactor(petKey, data) or 1
	local share = rarityShare * tierShare * zoneFactor * GameConfig.GetEnchantMult(enchant)
	local base = GameConfig.PetBaseBonus
	return {
		-- Both hard 1. Kept as fields rather than deleted so every existing call site keeps
		-- reading a number instead of a nil -- and so that the day someone reaches for a pet
		-- income bonus again, the one-line answer is here with the reasoning above it.
		incomeMult = base.incomeMult,
		dnaMult = base.dnaMult,
		-- Luck rides the SAME share as damage -- see the note over PetBaseBonus for why it had to
		-- come off the raw tier x rarity product. One number now moves a pet's whole contribution,
		-- so a rebalance of the share ladder can never leave luck behind pointing somewhere else.
		luckAdd = base.luckAdd * share,
		damageMult = 1 + share,
		-- exposed for the UI: the row prints the share, and the fusion/catalyst preview compares
		-- two of them without having to re-derive the arithmetic
		share = share,
	}
end

-- ===== WHAT THE EQUIPPED TEAM IS WORTH =====
--
-- LIVED IN PetService UNTIL 2026-08-11, and it moved here because it is pure: it reads `data` and
-- this module and touches nothing else. Sitting on the server meant the CLIENT could not compute
-- luck, which is what the egg panel needs to show honest odds -- and a UI that recomputes a formula
-- by hand is exactly how `rollAndInsert` ended up advertising luck it was not using.
--
-- `PetService.GetEquippedBonus` is kept as an alias, so every existing call site is unchanged.
function GameConfig.GetEquippedBonus(data)
	-- `damageAdd` accumulates each pet's share ABOVE 1 and becomes the multiplier at the end, so an
	-- empty team returns exactly 1 and nothing downstream has to special-case "no pets".
	local incomeMult, luckAdd, dnaMult, damageAdd = 1, 0, 1, 0
	if not data or not data.EquippedPetIds or not data.Pets then
		return { incomeMult = incomeMult, luckAdd = luckAdd, dnaMult = dnaMult, damageMult = 1 }
	end
	local equippedLookup = {}
	for _, id in ipairs(data.EquippedPetIds) do
		equippedLookup[id] = true
	end
	for _, pet in ipairs(data.Pets) do
		if equippedLookup[pet.id] then
			-- rarity is a property of the species, not of the save, so it is looked up rather
			-- than stored -- pets hatched before rarities existed still resolve correctly
			local def = GameConfig.GetPetDef(pet.key)
			-- `pet.key` and `data` are the progression axis: what this pet is worth to THIS player
			-- at the rung they are standing on, not what its species is worth in the abstract.
			local bonus = GameConfig.GetPetBonus(pet.tier, def and def.rarity, pet.key, data, pet.enchant)
			-- Both of these are hard 1 now (see PetBaseBonus) so these two lines are no-ops, and
			-- they are kept as lines rather than deleted because the shape of this loop is the thing
			-- that was wrong: `*=` over a growing collection is the bug, and leaving the operators
			-- visible beside the summed damage below is the clearest statement of the rule.
			incomeMult *= bonus.incomeMult
			dnaMult *= bonus.dnaMult
			luckAdd += bonus.luckAdd
			damageAdd += (bonus.damageMult - 1)
		end
	end
	return { incomeMult = incomeMult, luckAdd = luckAdd, dnaMult = dnaMult, damageMult = 1 + damageAdd }
end

-- ===== THE TWO LUCK TOTALS, AND WHY THERE ARE TWO =====
--
-- Every luck source is additive percentage points, and this is the only place they are summed.
-- It used to live in DNAService, which the client cannot reach and PetService could not require
-- (DNAService requires PetService) -- so the egg roll grew its OWN copy with two of these six terms
-- and a Luck Potion did nothing at all to what came out of an egg. Both now call this.
--
-- Luck starts at zero, so every source ADDS points rather than multiplying: a multiplier would pay
-- a first-time buyer exactly nothing.
--
-- SPLIT ON 2026-08-12 (11.5). The shop's `Upgrades.Luck` used to enter this sum, which made one
-- purchase quietly raise FIVE unrelated things at once: crit DNA, the mutation roll, the egg roll,
-- the mystery potion and the Robux wheel. That is unreadable at the point of sale -- the card said
-- "Critical DNA & rare mutations" and the biggest thing it actually moved was hatching -- and it is
-- also the reason the upgrade could never be made strong: any number big enough to be felt on an
-- egg was a crit-chance clamp on the DNA click.
--
-- So the upgrade LEAVES this sum and becomes a pet-luck-only stat, at +5 a level instead of +2.
-- Everything else -- pets, MegaLuck, potions, passes, events -- stays shared, because those are
-- sold as "luck" flat and players expect them everywhere. Read `GetPetLuckPercent` for anything
-- that opens an egg and this one for everything else.
function GameConfig.GetLuckPercent(data)
	if not data then return 0 end
	local megaLevel = data.DiamondUpgrades and data.DiamondUpgrades.MegaLuck or 0
	local megaAdd = megaLevel * GameConfig.DiamondUpgrades.MegaLuck.effectAdd
	return GameConfig.GetEquippedBonus(data).luckAdd
		+ megaAdd
		+ GameConfig.GetPotionLuckAdd(data)
		+ GameConfig.GetPassAdd(data, "luckAdd")
		-- Relics add points like everything else in this sum. `Relics` is loaded AFTER this part, and
		-- that is fine and not luck: the name is resolved off `GameConfig` when this function RUNS,
		-- not when it is written, and nothing calls it at load time. Adding rather than multiplying
		-- is not a style choice here -- luck starts at zero, so a relic that multiplied it would be
		-- worth exactly nothing to the player opening their first chest.
		+ GameConfig.GetRelicAdd(data, "luckAdd")
		+ GameConfig.GetEventAdd("luckAdd")
end

-- Percentage points the shop's Luck upgrade is worth PER LEVEL, and only to an egg. Raised from
-- the old shared +2 when the split above took it out of everything else -- the same spend has to
-- stay worth making, and it now buys one clearly-named thing instead of five vague ones.
GameConfig.PetLuckPerUpgradeLevel = 5

-- The luck an EGG rolls against: the shared total plus the shop upgrade. Two callers only, and
-- they are the two halves of one promise -- `PetService.rollAndInsert` (what you get) and the egg
-- panel's odds table (what you were told you would get). They must never diverge, which is why
-- neither computes this itself.
function GameConfig.GetPetLuckPercent(data)
	if not data then return 0 end
	local upgrades = (data.Upgrades and data.Upgrades.Luck or 0) * GameConfig.PetLuckPerUpgradeLevel
	return GameConfig.GetLuckPercent(data) + upgrades
end

-- The highest tier a paid Rainbow Catalyst may PRODUCE. Fusing is unaffected and still reaches
-- Celestial for free -- this caps the bought shortcut, not the ladder. One constant, read by both
-- the server that validates the spend and the panel that decides which pets to offer, so the two
-- can never disagree about what is buyable. See the product comment in RobuxProducts for why the
-- cap exists at all: equipped bonuses multiply across up to nine slots.
GameConfig.CatalystMaxTier = "Rainbow"

-- The next tier a catalyst is allowed to take this pet to, or nil if there is none -- either because
-- the pet is already at the top of the whole ladder, or because the step would cross the cap above.
function GameConfig.GetCatalystNextTier(tier)
	local nextTier = GameConfig.GetNextTier(tier)
	if not nextTier then return nil end
	local capIndex, nextIndex
	for i, t in ipairs(GameConfig.PetTiers) do
		if t == GameConfig.CatalystMaxTier then capIndex = i end
		if t == nextTier then nextIndex = i end
	end
	if not (capIndex and nextIndex) or nextIndex > capIndex then return nil end
	return nextTier
end

function GameConfig.GetNextTier(tier)
	for i, t in ipairs(GameConfig.PetTiers) do
		if t == tier then return GameConfig.PetTiers[i + 1] end
	end
	return nil
end

-- ===== HOW STRONG IS THIS PET =====
-- The pet's damage share -- i.e. exactly what GetPetBonus hands to the damage chain -- so the row
-- that prints the power chip, the Equip Best that picks the top three and the fusion preview that
-- shows what the next tier is worth can never disagree with what the pet actually does. It lives
-- here, once; three private copies of it would drift the first time a ladder changed.
--
-- `data` IS LOAD-BEARING FOR EQUIP BEST and is why it was threaded through. Ranking without it
-- ignores the zone axis, so a collection would be sorted as though every pet were still standing
-- in the zone it hatched in -- and Equip Best would keep putting a Forest Legendary in a slot that
-- a zone-matched Epic now beats four times over. Optional, because a species preview has no player
-- to rank against; omitted, every pet is quoted at its own zone's full strength.
-- Takes a SAVED pet ({ key, tier }), not a species def: tier is per-instance.
function GameConfig.GetPetPower(pet, data)
	if not pet then return 0 end
	local def = GameConfig.GetPetDef(pet.key)
	return GameConfig.GetPetBonus(pet.tier, def and def.rarity, pet.key, data, pet.enchant).share
end

-- ONE PET OUT OF A SAVE, BY ITS ID (30.4).
--
-- Three services now take a pet id off a client and have to turn it into the pet: the adventure
-- door, the dispatch that sends it away, and the claim that brings it back. Every one of them was
-- about to write the same four-line loop over `data.Pets`, which is the shape this file already
-- refuses everywhere else -- `GetPetPower` and `GetPetDef` exist for exactly that reason.
--
-- It resolves against THIS player's own collection and nothing else, so an id that names somebody
-- else's pet, a released pet or a fused one comes back `nil` rather than a table the caller then
-- has to re-check. The id is compared as a string because `HttpService:GenerateGUID` makes one and
-- a RemoteEvent will happily deliver a number that looks like it.
function GameConfig.GetPetById(data, petId)
	if not (data and petId) then return nil end
	local want = tostring(petId)
	for _, pet in ipairs(data.Pets or {}) do
		if tostring(pet.id) == want then return pet end
	end
	return nil
end

-- Strongest first. Ties are broken by key, then tier, then id -- not left to table.sort -- so a
-- list of duplicates keeps the same order every refresh instead of shuffling under the cursor
-- while the player is reaching for a button.
function GameConfig.SortedPetsByPower(pets, data)
	local list = table.create(#pets)
	for _, p in ipairs(pets) do
		table.insert(list, p)
	end
	-- Scored ONCE per pet before the sort rather than inside the comparator. GetPetPower walks the
	-- species table and the rank ladder, and table.sort calls a comparator O(n log n) times -- at 30
	-- pets that is ~150 calls against 30, and the trim in PlayerDataService runs it over a save that
	-- can still hold 600.
	local score = {}
	for _, p in ipairs(list) do
		score[p] = GameConfig.GetPetPower(p, data)
	end
	table.sort(list, function(a, b)
		local pa, pb = score[a], score[b]
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
	-- An egg with no zone rolls against every species in the game, which since 11.6 would have
	-- included the Apex exclusives -- so it falls back to the eggable list. `PetsByZone` itself never
	-- holds one, so the slice below is already safe; this is the malformed-egg path only.
	if not zonePool or #zonePool == 0 then return GameConfig.EggablePets end
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
	-- `EggablePets`, not `Pets` -- see the note over that list. An empty pool arriving here is a bug
	-- somewhere else, and the safe thing to hand back is a species the player could have got anyway.
	if not pool or #pool == 0 then pool = GameConfig.EggablePets end
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

-- Thousands separators, for the one figure in the game that is quoted as "1 in N" rather than as a
-- percentage. Local because that is its only caller; MainUI's own `formatNumber` abbreviates
-- (50K), which is the wrong read for odds -- the digits ARE the boast.
local function withCommas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Odds a given egg actually presents, as percentages -- what the podium board shows.
--
-- THE SECRET ROW IS APPENDED HERE RATHER THAN AT EACH BOARD (12.12). There are two boards -- the
-- billboard over the podium and the egg panel in the HUD -- and a rule written twice is a rule that
-- will be right in one place. It rides on the same function the roll shares, so the "?????" line
-- appears on precisely the eggs that can actually produce one and moves with luck exactly as the
-- roll does.
--
-- It carries `text` because neither board's number formatter can print this honestly: both fall
-- back to two decimals under 1%, and 0.002% renders as "0.00%" -- the same "advertising something
-- that cannot be won" bug the two-decimal rule was written to fix, one order of magnitude further
-- down. "1 in 50,000" is the only form of this figure a player can read. `chance` is still the real
-- percentage, so anything that sums or sorts these keeps working.
function GameConfig.GetEggOdds(egg, luckPercent)
	local pool = GameConfig.GetEggPool(egg)
	local weights, total = poolWeights(pool, luckPercent, egg and egg.rarityBias)
	local out = {}
	for i, p in ipairs(pool) do
		out[i] = { def = p, chance = weights[i] / total * 100 }
	end

	if GameConfig.CanEggHatchSecret(egg) then
		local chance = GameConfig.GetSecretChance(luckPercent)
		table.insert(out, {
			-- A DEF-SHAPED STAND-IN, not the real species. Both boards read `def.name`, `def.emoji`
			-- and `def.rarity` straight out of this entry, and naming the pet on the shop sign is
			-- the one thing a secret must not do -- what is advertised is that the Premium egg can
			-- do something the others cannot.
			def = { key = "Secret", name = "?????", emoji = "🔒", rarity = "Secret" },
			chance = chance * 100,
			-- TWO STRINGS, because the two boards are two different sizes and neither can render the
			-- other's. The HUD row is 96 px of a scrolling panel and gets the digits in full; the
			-- billboard cell is a 3.7-stud square of TextScaled label sitting beside "12.5%", and
			-- eleven characters in it are a grey smear at any range you would read it from.
			text = ("1 in %s"):format(withCommas(math.floor(1 / chance + 0.5))),
			textShort = ("1/%dK"):format(math.max(1, math.floor(1 / chance / 1000 + 0.5))),
			secret = true,
		})
	end

	return out
end

-- ===== A GLYPH THAT DOES NOT DRAW IS INVISIBLE TO EVERY PROPERTY PROBE =====
--
-- 30.22 photographed `Pebble  •  tier 1  •  luck x1.00` with no rock in front of it. The
-- label was correct in every way a probe can read: `.Text` held the character, `.TextColor3` was
-- right and `.TextFits` said true. The glyph was laid out and drawn as NOTHING, because the
-- system emoji font does not carry U+1FAA8. Only a screenshot finds that, which is why the band
-- is checked here at load instead of being left to the next person with a camera.
--
-- The band is U+1F300 .. U+1F9FF, and both ends of it cost this file a defect:
--   BELOW it (U+26A1, U+2728, U+2B50, U+2604 ...) the codepoint is text-presentation by default,
--   so the renderer falls back to the display font and draws a monochrome outline or a box --
--   27.7's fault, and it is what `Starweaver` was still doing after the 33.12 sweep.
--   ABOVE it (U+1FA70+) the codepoint is a later Unicode addition the font here does not have at
--   all -- `Pebble`, `Cinder`, `Rustling`, `Scarab`, `Orbiton`, `Echo`, `Gasbub`, `Fluffle`.
-- `Adventures.lua` checks only the lower bound; the upper one is half of what this file needed.
--
-- The second check is the SHARED glyph, and it is here because a sweep that fixes the first one
-- causes it: 17 of 33.12's 41 replacements landed on a glyph another pet already wore. The icon
-- layer keys off the literal emoji bytes, so two pets on one glyph collapse to one icon and the
-- away card, the bag and the odds board all draw the wrong animal. It reports once, in a single
-- line, because fourteen warn lines at every boot is a log nobody reads.
do
	local SAFE_LO, SAFE_HI = 0x1F300, 0x1F9FF
	local wornBy, shared = {}, {}

	local function checkGlyph(who, emoji)
		local ok, cp = pcall(utf8.codepoint, emoji, 1)
		if not ok or type(cp) ~= "number" then
			warn(("[GameConfig.Pets] %s has a missing or unreadable emoji -- it will draw as nothing")
				:format(who))
		elseif cp < SAFE_LO then
			warn(("[GameConfig.Pets] %s has glyph U+%04X, BELOW U+1F300 -- text presentation, it draws as an outline or a box (27.7)")
				:format(who, cp))
		elseif cp > SAFE_HI then
			warn(("[GameConfig.Pets] %s has glyph U+%04X, ABOVE U+1F9FF -- too new for the system emoji font, it draws as nothing at all (30.22)")
				:format(who, cp))
		end

		local owner = wornBy[emoji]
		if owner then
			table.insert(shared, ("%s=%s"):format(owner, who))
		else
			wornBy[emoji] = who
		end
	end

	for zone, list in pairs(ZONE_PETS) do
		for _, def in ipairs(list) do
			checkGlyph(("pet %s (%s)"):format(tostring(def.key), zone), def.emoji)
		end
	end
	for zone, def in pairs(EXCLUSIVE_PETS) do
		checkGlyph(("exclusive %s (%s)"):format(tostring(def.key), zone), def.emoji)
	end
	for zone, def in pairs(SECRET_PETS) do
		checkGlyph(("secret %s (%s)"):format(tostring(def.key), zone), def.emoji)
	end
	for _, tier in ipairs(EGG_TIERS) do
		checkGlyph(("egg tier %s"):format(tostring(tier.suffix)), tier.emoji)
	end

	if #shared > 0 then
		-- `pairs` gives no order, so sort before printing or the line churns between boots and
		-- two runs of the same file look like two different faults.
		table.sort(shared)
		warn(("[GameConfig.Pets] %d glyph(s) are worn twice, so those entries collapse to one icon: %s")
			:format(#shared, table.concat(shared, ", ")))
	end
end

end
