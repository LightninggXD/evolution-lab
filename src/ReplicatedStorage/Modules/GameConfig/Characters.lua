-- GameConfig.Characters -- the 100 skins by stage, the VIP wardrobe, the event-exclusive skins and everything that reads damage or health off a costume.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

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
-- ===== THE VIP WARDROBE IS NINE SKINS, AND IT IS THE ONE COSTUME THAT PAYS =====
--
-- Everything above this line obeys one rule -- progress pays, appearance is free (see
-- GetProgressRank). The VIP wardrobe is the deliberate, single exception, asked for in as many
-- words: `vipDamageMult` is a flat multiplier on the whole damage chain and `vipIncomeMult` one on
-- the whole DNA chain. These nine are the only place in the game where what a player is WEARING
-- decides what they hit for and what they earn.
--
-- Written as TWO evenly spaced ladders rather than eighteen hand-picked numbers:
--   damage  3.0 + 1.5  per rung, ending exactly on 15.0
--   income  1.10 + 0.05 per rung, ending exactly on 1.50
-- Nine equal steps means no rung is ever a trap -- every skin further along the row is strictly
-- better than the one before it by the same amount -- and the row can be re-tuned by moving the two
-- ends rather than by re-balancing nine independent figures.
--
-- IT MULTIPLIES THE CHAIN, IT DOES NOT REPLACE THE LADDER. The wearer still scores as the best rung
-- they have EARNED (GetEffectiveRank, unchanged), so a VIP who has climbed further hits harder than
-- a VIP who has not -- the pass multiplies a player's own progress instead of standing in for it.
-- That is the answer to "a VIP skin should hit like my best unlocked character": it hits like the
-- best character this save has ever unlocked, times the rung of the wardrobe it is wearing.
--
-- ALL NINE ARE ONE PURCHASE. They are granted and revoked together by SyncVipCharacter, so the row
-- is a wardrobe to pick a look from and a power curve to grow into, not nine separate sales.
--
-- WHERE THE BODIES COME FROM (this is the part that is not like anything else in this file): every
-- one of them is a real Roblox catalog bundle, baked into ReplicatedStorage.Assets.SkinMeshes as
-- `SkinMesh_<key>` by Players:CreateHumanoidModelFromDescription, so SkinMesh.Has finds them exactly
-- as it finds the 200 generated skins and nothing else in the pipeline had to learn a new case.
-- Their parts keep their R15 limb names, which is what SkinMesh's `directHost` rule is for -- see
-- the note there. `tools/build_vip_skins.lua` is the script that bakes them and it is the ONLY
-- record of how: the models are instances in the place, not files, so a lost place means re-running
-- that script and nothing else.
--
-- `bundleId` IS READ BY THAT SCRIPT AND BY NOTHING ELSE AT RUNTIME. It is the whole recipe: change
-- the id, re-run the builder, and the skin is a different character with the same key, the same
-- rung and the same save entry.
--
-- WHY THESE NINE BUNDLES. The row is what a 499-Robux pass is buying, so it is chosen to LOOK like
-- it: all nine are Roblox's own catalog bundles rather than free classics, they escalate from a
-- gold suit to the Korblox Deathspeaker (the most expensive avatar Roblox sells), and the middle of
-- the row is where the monsters are -- a demon king, a skeletal dragon and a dragon lord. The row
-- this replaced was eight free bundles (Junkbot, a vampire, a paladin...) and it read as a bin of
-- starter avatars, which is the opposite of what the most expensive thing in the shop should read
-- as. See GameConfig.RetiredVipKeys for what happens to the keys it dropped.
--
-- `vip_gold` keeps its key and its place at the front: it is the one every existing save already
-- owns, so deleting it would strip a skin out of live saves to no purpose. Its BODY is new -- the
-- Golden Suit of Bling Squared, a 3,150 Robux bundle -- because the thing that was wrong with it
-- was never the key.
GameConfig.VipCharacters = {
	{
		key = "vip_gold",
		-- NAMED FOR THE BODY IT WEARS AND NOT FOR ITS KEY. `vip_gold` is the one key in this table a
		-- live save already holds, so it cannot be renamed; the skin it names has been a gold-tinted
		-- primitive costume, then a generated mesh, and is now Sunstar. A key is an identity, a name
		-- is a description, and only one of the two is allowed to be wrong.
		name = "Sunstar Patron",
		emoji = "\u{2600}\u{FE0F}",
		rarity = "Legendary",
		-- ===== EVERY DISC COLOUR IN THIS TABLE IS READ OFF THE BODY =====
		-- The rim of a Journal disc is what tells two skins apart at a glance, so it is the bundle's
		-- own dominant colour rather than a hue picked for the row: Sunstar is crimson and gold, the
		-- Shogun is gold and white, the Demon King is orange. They are also checked against EACH
		-- OTHER -- the nine sit in one row two lines deep, and two discs that read the same are two
		-- skins a player cannot choose between without clicking both.
		color = Color3.fromRGB(236, 84, 76),
		vip = true,
		-- See the note over GameConfig.EventCharacters: `offLadder` is what the rank arithmetic reads,
		-- `vip` is what the pass sync and the Journal's section title read. They were one field until
		-- there was a second kind of skin that is not on the ladder.
		offLadder = true,
		-- ===== NO `regalia`, AND THAT IS THE POINT =====
		--
		-- 16.10 gave every off-ladder skin a head piece -- a crown, a laurel or turning shards -- so
		-- that a paid skin would read as paid against a ladder Legendary it otherwise only differed
		-- from by colour. That reason expired the moment these nine became real catalog bundles: a
		-- Bull Demon King and a Korblox Deathspeaker do not need a hat to look bought. What was left
		-- was a flat yellow crown floating over characters that already had horns, helmets and
		-- antlers of their own -- *"ove krunice bolje napravi sta ce im to, likovi su vec dobri"*
		-- (Kristina, 2026-08-16, with a screenshot of one).
		--
		-- The field is simply absent rather than set to a "none" string: StageCostume.Regalia already
		-- does nothing when the entry has none, so this needs no code change, and the EVENT skins
		-- keep theirs -- they are still costumes rather than bundles, and the argument that put the
		-- hardware there in the first place is still true of them.
		-- Sunstar, a 756-Robux solar knight, and NOT the Golden Suit of Bling Squared this key reads
		-- like it should be. That bundle is a classic R6 package: converted to R15 it is a yellow
		-- suit with the head buried inside the torso -- a headless man in a jacket, a worse first
		-- impression than the primitive costume this whole wardrobe replaced. The entry rung of a
		-- paid row cannot be the ugliest thing in it.
		--
		-- THE RULE THAT COST TWO CAPTURES TO FIND, and it is not "expensive is better": a bundle
		-- whose `BundledItems` numbers about SIX is a classic R6 package and will convert badly,
		-- because R6 has one torso where R15 has five parts and the conversion buries the head. The
		-- Rthro-era bundles carry 16-20 items -- five limbs' worth of parts, seven Rthro animations,
		-- two outfits -- and those are the ones that come out looking like the catalog picture.
		-- Golden Suit of Bling Squared is 7 items at 3,150 Robux; Cyborg Shogun is 18 at 158.
		vipDamageMult = 3.00, vipIncomeMult = 1.10, bundleId = 344,
	},
	{
		key = "vip_shogun", name = "Cyber Shogun", emoji = "\u{1F916}", rarity = "Legendary",
		color = Color3.fromRGB(255, 208, 96), vip = true, offLadder = true,
		vipDamageMult = 4.50, vipIncomeMult = 1.15, bundleId = 790, robuxPrice = 149,
	},
	{
		key = "vip_valkyrie", name = "Skyfall Valkyrie", emoji = "\u{1FA7D}", rarity = "Legendary",
		color = Color3.fromRGB(130, 176, 255), vip = true, offLadder = true,
		vipDamageMult = 6.00, vipIncomeMult = 1.20, bundleId = 452, robuxPrice = 199,
	},
	{
		-- Bull Demon King (604) held this rung and had to go for a third reason the other two do not
		-- cover: its collar is taller than its head. The bundle is drawn with an enormous black
		-- shoulder piece and a small gold bull face, and because a skin keeps the template's own
		-- proportions (see the block in SkinMesh above `placed`), from the front the collar swallows
		-- the face and the character reads as headless armour. Nothing is broken about the bake --
		-- it is simply a silhouette that does not survive being someone's avatar.
		key = "vip_demon", name = "Borock the Conqueror", emoji = "\u{1FA93}", rarity = "Legendary",
		color = Color3.fromRGB(126, 200, 86), vip = true, offLadder = true,
		vipDamageMult = 7.50, vipIncomeMult = 1.25, bundleId = 497, robuxPrice = 249,
	},
	{
		key = "vip_dragon", name = "Skeletal Dragon", emoji = "\u{1F409}", rarity = "Legendary",
		color = Color3.fromRGB(228, 220, 176), vip = true, offLadder = true,
		vipDamageMult = 9.00, vipIncomeMult = 1.30, bundleId = 577, robuxPrice = 299,
	},
	{
		key = "vip_overseer", name = "Overseer Overlord", emoji = "\u{1F441}\u{FE0F}", rarity = "Legendary",
		color = Color3.fromRGB(96, 226, 120), vip = true, offLadder = true,
		vipDamageMult = 10.50, vipIncomeMult = 1.35, bundleId = 385, robuxPrice = 349,
	},
	-- ===== THE TWO THAT ONLY A CAPTURE COULD REJECT =====
	--
	-- These rungs held Sea Serpent (673) and Cythrex (590) first. Both are Rthro-era, both baked
	-- without error, both passed every count this file can take -- and photographed side by side
	-- with the other seven they were the two nobody would buy: Cythrex's head is an untextured dark
	-- cylinder with no face on it, and the Serpent's is a pale rounded blob over bare arms. Nothing
	-- in the metadata says so. The item-count rule over `vip_gold` filters out the R6 packages that
	-- bake headless; there is no rule that filters out a head that is simply featureless, and there
	-- will not be one -- the check is a screenshot.
	{
		key = "vip_lion", name = "Guardian Lion", emoji = "\u{1F981}", rarity = "Legendary",
		color = Color3.fromRGB(86, 200, 196), vip = true, offLadder = true,
		vipDamageMult = 12.00, vipIncomeMult = 1.40, bundleId = 599, robuxPrice = 399,
	},
	{
		key = "vip_crystal", name = "Crystello", emoji = "\u{1F48E}", rarity = "Legendary",
		color = Color3.fromRGB(150, 110, 235), vip = true, offLadder = true,
		vipDamageMult = 13.50, vipIncomeMult = 1.45, bundleId = 468, robuxPrice = 449,
	},
	{
		key = "vip_tenko", name = "Tenko the Nine-Tailed", emoji = "\u{1F98A}", rarity = "Legendary",
		color = Color3.fromRGB(255, 120, 150), vip = true, offLadder = true,
		vipDamageMult = 15.00, vipIncomeMult = 1.50, bundleId = 451, robuxPrice = 499,
	},
}

-- ===== THE KEYS THE WARDROBE USED TO HAND OUT =====
--
-- A key that leaves GameConfig.VipCharacters stops resolving -- CHARACTER_BY_KEY never learns it,
-- so GetCharacter returns nil and the Journal cannot draw it. That is fine for a save that only
-- OWNS it (a dead key in `data.Characters` is ignored by everything that iterates the real tables),
-- and it is NOT fine for a save that is WEARING it: `WornCharacter` would keep naming a skin that
-- resolves to nothing, so the body falls back to bare and the player's own reflex is that the game
-- forgot their purchase.
--
-- So the retired keys are listed rather than deleted, and SyncVipCharacter sweeps them out of both
-- fields on the next load. Nothing here was ever published -- the eight-bundle row lived only in an
-- unsaved Studio session -- so in practice this list will find nothing in a real save. It exists
-- because the next time the row is re-cut it will not be free, and the sweep should already be
-- there when that happens.
-- The first seven are the free-bundle row this wardrobe replaced. The last three are from the
-- re-cut itself and were never published either: Dragon Lord, The Doombringer and Korblox
-- Deathspeaker are all CLASSIC R6 packages, and the rule written over `vip_gold` is why they had to
-- go -- baked to R15 each one came out with a blank white default head and its real head floating
-- beside the body as a loose accessory. Korblox is the most recognisable expensive avatar Roblox
-- sells and it still could not stay: a 17,000-Robux name on a headless body sells nothing.
GameConfig.RetiredVipKeys = {
	"vip_junkbot", "vip_vampire", "vip_paladin", "vip_samurai",
	"vip_mech", "vip_reaper", "vip_golden",
	"vip_dragonlord", "vip_doom", "vip_korblox",
	"vip_wyrm", "vip_cythrex",
}

-- The entry-level skin, and the alias every reader that predates the wardrobe still uses. Kept
-- pointing at `vip_gold` on purpose: it is the one that has always existed, so a caller written
-- against the single-skin era keeps naming the same skin it always named.
GameConfig.VipCharacter = GameConfig.VipCharacters[1]

for _, c in ipairs(GameConfig.VipCharacters) do
	CHARACTER_BY_KEY[c.key] = c
end

-- ===== EVENT-EXCLUSIVE SKINS: THE SAME SEPARATION, WITH ONE DIFFERENCE =====
--
-- Registered in CHARACTER_BY_KEY and never in CHARACTERS_BY_STAGE, for every reason written over
-- GameConfig.VipCharacter above -- the collection count, the evolve chain and the rank ladder must
-- not be able to see them, or the Journal could never read 200/200 again.
--
-- `offLadder = true` is the field the rank functions test. It used to be `vip`, which was fine
-- while there was exactly one skin outside the ladder; a second one would have had to be called
-- VIP to score correctly, and the next reader would have believed it.
--
-- THE DIFFERENCE IS THAT THESE ARE NEVER TAKEN BACK. The VIP skin is synced to a pass and revoked
-- the moment it lapses, because it is a subscription's badge. An event skin is a receipt for having
-- been there, and the only thing that makes a limited item worth owning is that the window it came
-- from is shut. EventService grants it while the window is open and nothing anywhere removes it --
-- not a rebirth, which clears data.Characters wholesale and is healed by the same sweep the VIP
-- skin uses, and not the event ending.
--
-- There is no generated SkinMesh for these and that is intended: SkinMesh.Has() falls through to
-- StageCostume painted in the colour below, i.e. a Prism version of whatever stage you are standing
-- at -- which is also why they preview at the player's own stage in the Journal rather than at a
-- stage of their own.
GameConfig.EventCharacters = {
	{
		key = "event_prism",
		name = "Prism Herald",
		emoji = "\u{1F308}",
		rarity = "Legendary",
		color = Color3.fromRGB(158, 120, 255),
		event = "PrismFest",
		offLadder = true,
		-- Not a crown: this one is light rather than metal, so it carries three turning shards over
		-- the head instead. See the note on GameConfig.VipCharacter.regalia.
		regalia = "shards",
		regaliaColor = Color3.fromRGB(206, 178, 255),
	},
	-- ===== THE FOUR COLOSSEUM CHAMPIONS (12.13) =====
	--
	-- One per week of ColosseumClash's rotation, and the ORDER OF THIS LIST IS NOT WHAT PICKS THEM:
	-- the rotation is the list on the event itself, and this table is only the registry that makes
	-- each key resolve to a name and a colour. They are two lists on purpose -- a skin can be
	-- retired from the rotation without deleting the entry that a save which already owns it needs
	-- (see SyncEventCharacters, which drops keys nothing resolves).
	--
	-- FOUR DISTINCT HUES, chosen against each other and against the two skins already outside the
	-- ladder. Prism Herald is violet and the VIP skin is gold, so the champions take orange, ice
	-- blue, green and slate -- there is no mesh for any of them, so the whole of a champion IS its
	-- colour on the player's own stage costume, and two that read the same from across the plaza are
	-- two weekends that felt like one.
	--
	-- ALL FOUR SHARE ONE HEAD PIECE, and deliberately: the gold laurel is what says "champion", the
	-- colour is what says WHICH champion. Giving each of them its own would have made four unrelated
	-- items where the point is a set. The VIP skin takes a crown so a pass is never mistaken for an
	-- arena prize.
	{
		key = "event_clash_ember",
		name = "Ember Gladiator",
		emoji = "\u{1F525}",
		rarity = "Legendary",
		color = Color3.fromRGB(238, 96, 54),
		event = "ColosseumClash",
		offLadder = true,
		regalia = "wreath",
	},
	{
		key = "event_clash_frost",
		name = "Frost Sentinel",
		emoji = "\u{2744}\u{FE0F}",
		rarity = "Legendary",
		color = Color3.fromRGB(118, 208, 255),
		event = "ColosseumClash",
		offLadder = true,
		regalia = "wreath",
	},
	{
		key = "event_clash_verdant",
		name = "Verdant Colossus",
		emoji = "\u{1F33F}",
		rarity = "Legendary",
		color = Color3.fromRGB(96, 200, 118),
		event = "ColosseumClash",
		offLadder = true,
		regalia = "wreath",
	},
	{
		key = "event_clash_onyx",
		name = "Onyx Praetor",
		emoji = "\u{1F311}",
		rarity = "Legendary",
		color = Color3.fromRGB(96, 90, 124),
		event = "ColosseumClash",
		offLadder = true,
		regalia = "wreath",
	},
}
for _, c in ipairs(GameConfig.EventCharacters) do
	CHARACTER_BY_KEY[c.key] = c
end

function GameConfig.GetEventCharacter(key)
	for _, c in ipairs(GameConfig.EventCharacters) do
		if c.key == key then return c end
	end
	return nil
end

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
	-- An off-ladder skin -- the VIP one, an event one -- has no rung. It is not in CHARACTERS_BY_STAGE
	-- and counting it as one would put it either at the bottom (worthless) or the top (bought or
	-- date-of-birth power). What it is worth is decided per WEARER instead; see GetEffectiveRank.
	if entry.offLadder then return 0 end
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
		if entry and not entry.offLadder then
			local rank = GameConfig.GetCharacterRank(entry)
			if rank > best then best = rank end
		end
	end
	return best
end

function GameConfig.GetEffectiveRank(data, entry)
	if entry and entry.offLadder then return GameConfig.GetBestOwnedRank(data) end
	return GameConfig.GetCharacterRank(entry)
end

-- ===== HOW FAR UP THE LADDER THIS SAVE HAS CLIMBED =====
--
-- The rung the player's DAMAGE is read off. It is the best rung they OWN, not the one they have on
-- -- and that is a deliberate reversal of the older rule, forced by the curve above.
--
-- Rank used to be worth a linear +3% each, so wearing something fifty rungs back cost 150% and was
-- a real but survivable trade the Journal advertised honestly. Geometric, the same choice costs a
-- factor of forty, and no cosmetic is worth that: it would not read as a trade, it would read as a
-- broken save. The collection also fills strictly in order and every evolve auto-wears the newest
-- entry, so the trade was one almost nobody was making on purpose in the first place.
--
-- So progress pays and appearance is free. Wear whatever you like; you keep what you climbed to.
--
-- ONE COSTUME IS NOT FREE, and it is the only one: a VIP skin multiplies this by 2x to 8x through
-- GetVipDamageMult below. It is an exception to the sentence above rather than a hole in it -- the
-- rung a VIP scores is still this one, so the pass multiplies what the player climbed to instead of
-- replacing it.
function GameConfig.GetProgressRank(data)
	return math.max(1, GameConfig.GetBestOwnedRank(data))
end

-- THE BASE OF THE DAMAGE CHAIN, and the number the Journal prints beside the rung that grants it.
-- Everything else in `DNAService.GetCombatDamage` is a multiplier on this.
function GameConfig.GetBaseDamage(data)
	return GameConfig.GetRankDamage(GameConfig.GetProgressRank(data))
end

-- Kept because saves, tools and the Journal's older rows still call it, and it is still true of
-- what a rung is WORTH -- it just no longer decides what the body standing in the world hits for.
-- Returns 1 unconditionally so the damage chain is unchanged by a costume.
function GameConfig.GetCharacterDamageMult(_data)
	return 1
end

-- ===== THE ONE COSTUME THAT DECIDES DAMAGE =====
--
-- A term in DNAService.GetCombatDamage, and the only one that reads `data.WornCharacter`. See the
-- wardrobe block over GameConfig.VipCharacters for why this exception exists at all.
--
-- OWNERSHIP IS RE-CHECKED HERE and not taken from `WornCharacter` alone. That field is a key the
-- client last asked for; the pass behind it can lapse between the ask and this call, and
-- SyncVipCharacter clears the key but only runs on a pass refresh and on rebirth. Reading the grant
-- set instead means a lapsed pass loses the multiplier on the very next blow rather than on the
-- next sync -- and it costs one table lookup on a path that already does several.
function GameConfig.GetVipDamageMult(data)
	local entry = GameConfig.GetWornCharacter(data)
	if not (entry and entry.vipDamageMult) then return 1 end
	if not (data and data.Characters and data.Characters[entry.key]) then return 1 end
	return entry.vipDamageMult
end

-- The DNA half of the same idea, and a term in DNAService.GetIncomeMult. Written as its own
-- function rather than as a second return value because the two chains are computed in different
-- places and a caller of one has no business holding the other's number.
--
-- The ownership re-check is the same one, for the same reason: a lapsed pass must stop paying on
-- the next click and not on the next sync.
function GameConfig.GetVipIncomeMult(data)
	local entry = GameConfig.GetWornCharacter(data)
	if not (entry and entry.vipIncomeMult) then return 1 end
	if not (data and data.Characters and data.Characters[entry.key]) then return 1 end
	return entry.vipIncomeMult
end

-- The strongest rung of the wardrobe this save can actually put on, or 1 when it can put on none.
-- The shop and the pass card quote it ("up to x15 damage"), so the figure advertised is read off the
-- same table the damage is read off and cannot drift from it.
--
-- `field` picks which ladder is being asked about and defaults to damage, so every existing caller
-- keeps its meaning; the pass card asks for both.
function GameConfig.GetBestVipDamageMult(data, field)
	field = field or "vipDamageMult"
	local best = 1
	for _, c in ipairs(GameConfig.VipCharacters) do
		if data and data.Characters and data.Characters[c.key] and (c[field] or 1) > best then
			best = c[field]
		end
	end
	return best
end

-- The top of each ladder as authored, with no save involved -- what the shop can promise before it
-- knows who is reading. Quoted by the pass description and by the VIP card, so raising the last row
-- of the wardrobe raises the advertisement with it.
function GameConfig.GetVipLadderTop(field)
	field = field or "vipDamageMult"
	local best = 1
	for _, c in ipairs(GameConfig.VipCharacters) do
		if (c[field] or 1) > best then best = c[field] end
	end
	return best
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

-- WHAT ONE RUNG IS WORTH IN HEALTH, and the Journal's second stat line quotes it rather than
-- re-deriving "1% a rung" in the UI -- a second copy of the rate is a promise that goes stale the
-- day the rate moves, which is the exact bug the damage figure on the same card was rescued from.
--
-- `data` is optional and only matters for an OFF-LADDER skin. The VIP and event skins have no rung
-- of their own -- GetCharacterRank returns 0 for them on purpose -- and score as the best one the
-- save has earned, which is what GetEffectiveRank exists for. Without the second argument this
-- printed "+0% Max Health" beside a skin that in fact carries the wearer's whole collection.
function GameConfig.GetCharacterHealthPct(entry, data)
	if not entry then return 0 end
	return GameConfig.GetEffectiveRank(data, entry) * GameConfig.CharacterHealthPerRank
end

-- Health follows damage onto the PROGRESS rung for the same reason (see GetProgressRank): the two
-- have to agree about what the player is, or a costume would change how long they survive while
-- leaving what they hit for alone. Still linear at 1% a rung -- health multiplies how long a fight
-- lasts and damage how fast it ends, so this side deliberately does NOT go geometric; +99% at the
-- top of the collection, against a damage ladder that has grown by a factor of 1,394.
function GameConfig.GetCharacterHealthMult(data)
	return 1 + GameConfig.GetProgressRank(data) * GameConfig.CharacterHealthPerRank / 100
end

-- Grants or REVOKES the VIP skin so it always matches the pass. Called on every pass refresh and
-- again after a rebirth, because RebirthService clears `data.Characters` wholesale -- without the
-- second call a VIP who rebirthed would lose the skin until they next rejoined.
function GameConfig.SyncVipCharacter(data)
	if not data then return end
	data.Characters = data.Characters or {}

	-- FIRST, THE KEYS THE WARDROBE NO LONGER HAS. Unconditional -- a retired key is retired whether
	-- or not the pass is still owned -- and it clears `WornCharacter` too, because a worn key that
	-- resolves to nothing puts the player in no skin at all with nothing on screen to say why. The
	-- grant below then re-dresses them in the entry skin. See GameConfig.RetiredVipKeys.
	for _, key in ipairs(GameConfig.RetiredVipKeys) do
		data.Characters[key] = nil
		if data.WornCharacter == key then
			data.WornCharacter = GameConfig.VipCharacters[1].key
		end
	end

	-- THE WHOLE WARDROBE MOVES TOGETHER. Nine skins, one pass: granting them one at a time would
	-- mean nine places for a lapse to be half-applied, and there is nothing a player could do to own
	-- one of them without owning all nine.
	if GameConfig.OwnsPass(data, "VIP") then
		for _, c in ipairs(GameConfig.VipCharacters) do
			data.Characters[c.key] = true
		end
		return
	end

	local wasWearing = false
	for _, c in ipairs(GameConfig.VipCharacters) do
		if data.WornCharacter == c.key then wasWearing = true end
		data.Characters[c.key] = nil
	end

	-- Still wearing it after the pass went away would leave the body in a skin the player no longer
	-- owns, and GetWornCharacter would happily keep resolving it -- and with the wardrobe carrying a
	-- damage multiplier, it would keep PAYING for it too. Fall back to the best thing they actually
	-- earned, which is also exactly what the VIP skin had been scoring as.
	if wasWearing then
		local best, bestRank = nil, -1
		for owned in pairs(data.Characters) do
			local entry = GameConfig.GetCharacter(owned)
			-- offLadder rather than vip: an event skin also scores 0 here, so falling back onto one
			-- would put the player in a costume that is not the best thing they earned.
			if entry and not entry.offLadder then
				local rank = GameConfig.GetCharacterRank(entry)
				if rank > bestRank then best, bestRank = owned, rank end
			end
		end
		data.WornCharacter = best
	end
end

-- ===== AN EVENT SKIN HAS TO SURVIVE A REBIRTH, AND data.Characters DOES NOT =====
--
-- `RebirthService` clears `data.Characters` wholesale and the collection is then re-granted from
-- the stage lists. The VIP skin survives that because SyncVipCharacter puts it back from the pass,
-- which is a live fact that can be re-asked at any time. An event skin has no such source: the
-- window it came from is shut, so once it is gone it is gone -- a player who rebirths in October
-- would silently lose a September festival skin and nothing anywhere could give it back.
--
-- So `data.EventCharacters` is the permanent record and `data.Characters` is only ever the working
-- copy. Same shape and same reasoning as StatsService's `CountedCharacters`: a set that no reset
-- touches, from which the thing a reset destroys is rebuilt. Called on the rebirth hook beside
-- SyncVipCharacter and by EventService's own sweep, and it is idempotent, so extra calls are free.
function GameConfig.SyncEventCharacters(data)
	if not data then return 0 end
	data.Characters = data.Characters or {}
	local restored = 0
	for key, earned in pairs(data.EventCharacters or {}) do
		-- only keys that still resolve: a skin removed from the table in a later build must not
		-- reappear on a body as a nil entry the costume code then tries to paint with
		if earned == true and CHARACTER_BY_KEY[key] and not data.Characters[key] then
			data.Characters[key] = true
			restored += 1
		end
	end
	return restored
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

	-- `step.cost` IS INFORMATIONAL NOW AND NOTHING GATES ON IT. An evolve costs XP and only XP -- see
	-- DNAService.HandleEvolve for why two gates on one button is one gate too many. It is still
	-- filled in because `stage.cost` doubles as the `math.huge` sentinel that marks the end of the
	-- chain, and because a tool reading it should get the answer it always did. If you are adding a
	-- check against it, you are re-adding the DNA gate.
	if stage.cost == math.huge then
		step.cost = GameConfig.FinalStageStepCost
		step.xpCost = GameConfig.FinalStageStepXp
	else
		step.cost = stage.cost
		step.xpCost = stage.xpCost
	end

	-- ===== THE VERY FIRST EVOLVE COSTS ONE KILL =====
	--
	-- Stage 1 costs 50 XP and the weakest creature in the first zone is worth exactly 1, so a new
	-- player used to be told "Click a creature to attack it" and then had to do it FIFTY TIMES
	-- before anything happened. That is the whole "the tutorial lasts too long" report: the banner
	-- is not on a timer, it is the else-branch of the XP test (see FirstJoin.stepFor), so it sat
	-- there for the entire grind.
	--
	-- Only the FIRST step is discounted -- Speck -> Amber Blob, the one the tutorial points at.
	-- Step two onwards pays the full 50, so the curve, the ramp and every stage above are untouched.
	--
	-- Gated on `TutorialDone` rather than on a new save field: the flag already exists, it is set
	-- server-side on the first successful evolve of any kind (DNAService.HandleEvolve), and both
	-- sides of the wire have it -- so the client's button and the server's charge agree without
	-- anything new having to replicate. A rebirth does not reopen it, because rebirthing is not
	-- being new.
	if stageIndex == 1 and step.entryIndex == 2 and not (data and data.TutorialDone) then
		step.xpCost = GameConfig.FirstEvolveXp
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

end
