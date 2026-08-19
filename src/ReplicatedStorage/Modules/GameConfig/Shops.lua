-- GameConfig.Shops -- the boss arena, which shop stands in which zone, the mystery potion kiosk and the lucky spin.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

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
-- are fifteen shops in the whole strip now -- eight of them in the last nine zones, five zones with
-- none at all -- so which shop a zone carries is information rather than scenery.
--
-- Keyed by zone INDEX (= evolution stage), which is how the strip is actually ordered. The zone
-- named beside each entry is what that index resolves to today; the index is what decides.
-- ===== THE BACK HALF OF THE STRIP USED TO HAVE FOUR SHOPS IN NINE ZONES (12.9) =====
--
-- Eight shops was the right correction to twenty identical market rows and the wrong DISTRIBUTION:
-- six of the eight stood in zones 3-11, so a player past the Wormhole walked four zones at a time
-- between counters and the Upgrade Emporium -- the only door to the Mastery panel -- was at zone 8,
-- i.e. behind them for the whole of the late game. Fifteen entries now, and the rule that replaces
-- "one every four" is: **from zone 12 on, every zone has a shop**, in the repeating order
-- Emporium -> Mystery -> Fusion -> Mystery. The front half is unchanged, including the two plain
-- tutorial zones -- arriving somewhere with a shop is still meant to be an event where it is rare,
-- and the late game is where a player has the currency to spend and no reason to walk past.
GameConfig.ZoneShops = {
	-- Mystery Potions: one every four zones to begin with, first at 3 (the first two are the
	-- tutorial stretch and stay deliberately plain, which is where the old cauldron started too),
	-- then every other zone from 13.
	[3]  = "mystery",  -- Ocean
	[7]  = "mystery",  -- Galaxy
	[11] = "mystery",  -- Wormhole
	[13] = "mystery",  -- Time Rift
	[15] = "mystery",  -- Dream Dimension
	[17] = "mystery",  -- Void Expanse
	[19] = "mystery",  -- Singularity
	-- Pet Fusion, at the points where a player has been hatching long enough to be holding
	-- duplicates worth fusing.
	-- MOVED 5 -> 4. The Fusion panel had exactly ONE door in the whole game -- this counter -- so
	-- until a player reached the zone holding it, the feature did not appear to exist. That is how
	-- it was reported: "am I missing pet fusion, where is it, I am already on stage 4". By Volcano
	-- you have walked three egg stalls and are holding duplicates worth fusing. (12.8 gave it a
	-- second door in the HUD; the counters are still what the panel is FOR.)
	[4]  = "fusion",   -- Volcano
	[10] = "fusion",   -- Nebula
	[14] = "fusion",   -- Antimatter Zone
	[18] = "fusion",   -- Celestial Throne
	-- The one place in the game that sells permanent power, for the two currencies that buy it --
	-- and the only entry point the Mastery panel has, which is why one copy at zone 8 was not
	-- enough: everything it sells is bought with the money the LAST zones make.
	[8]  = "upgrades", -- Black Hole
	[12] = "upgrades", -- Quantum Realm
	[16] = "upgrades", -- Mirror Universe
	[20] = "upgrades", -- The Absolute Plane
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
	-- there are seven of these in the whole game and reaching the first of them is a walk.
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

-- ===== WHAT THE KIOSK'S ODDS BOARD IS BUILT FROM (12.8) =====
--
-- The same shape `GetEggOdds` returns, for the same reason: the board on the counter is drawn from
-- the table `RollMysteryPotion` reads, so it can never advertise a chance the roll does not honour.
-- Luck is deliberately not a parameter -- this is the shop's BASELINE, printed on a board that is
-- built once at world-build time and read by every player who walks past it, and a player's own
-- luck only ever moves the big bottle up from what is written.
--
-- The percentages sum to 100 by construction (they are shares of the weight total), which is what
-- the row's check measures.
function GameConfig.GetMysterySizeOdds()
	local rolls = GameConfig.MysteryShop.sizeRolls
	local total = 0
	for _, r in ipairs(rolls) do total += r.weight end
	local out = {}
	for i, r in ipairs(rolls) do
		local size
		for _, s in ipairs(GameConfig.PotionSizes) do if s.key == r.size then size = s end end
		out[i] = {
			key = r.size,
			size = size,
			name = (size and size.name) or r.size,
			emoji = (size and size.emoji) or "\u{1F9EA}",
			minutes = size and size.minutes or 0,
			chance = total > 0 and (r.weight / total * 100) or 0,
		}
	end
	return out
end

-- Every kind is equally likely -- the roll picks one with `math.random(1, #kinds)` -- so the board's
-- kind line is a list of every kind that EXISTS plus one share. Written out by hand it was wrong:
-- it named three kinds beside a "%d%% each" computed over four (11.8 added Health), i.e. a board
-- advertising 75% of its own product. Built from the table it cannot drift again.
function GameConfig.GetMysteryKindsText()
	local kinds = GameConfig.PotionKinds
	local parts = {}
	for _, k in ipairs(kinds) do
		table.insert(parts, ("%s %s"):format(k.emoji, k.name))
	end
	return ("%s  \u{2022}  %d%% each"):format(table.concat(parts, "   "),
		math.floor(100 / math.max(#kinds, 1) + 0.5))
end

-- "7% chance of the twenty-minute one" is the part of a gamble a player actually wants to see, so
-- the shop's board is built from the same table the roll reads.
-- KEPT, and still the one-line form: the kiosk draws the graphical board above instead (12.8), but
-- this is what any future text sign should print rather than a second hand-written copy.
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

-- ===== THE LUCKY SPIN =====
--
-- One spin, twelve outcomes, and which one it lands on IS the product. It sits on the shelf beside
-- the flat DNA packs deliberately: the pack is the safe buy and the wheel is the gamble, so the
-- wheel's EXPECTED DNA IS SET BELOW the pack at the same price (2,191 against 2,500 authored
-- stage-one clicks). What the buyer is paying that difference for is the tail -- diamonds, potions,
-- shards, a relic chest, a pet and a jackpot that no pack sells at any price. A wheel whose average
-- beat the guaranteed product would simply retire the guaranteed product, and then there would be
-- one product again.
--
-- The weights sum to exactly 100, so at zero luck a weight IS its percentage. That is not a
-- coincidence to preserve for its own sake -- GetSpinOddsText divides by the real total either way
-- -- but while it holds, the table can be read as the odds board without doing any arithmetic.
--
-- ORDERED COMMON FIRST, and the order is load-bearing: luck lifts the later segments, the same
-- shape RollMysteryPotion uses, so the luck economy reaches this wheel too. Move a row and you have
-- changed what luck does to it.
--
-- =========================================================================================
-- THE 2026-08-17 REBALANCE: 8 SEGMENTS -> 12, AND WHY EVERY WEIGHT MOVED
-- =========================================================================================
-- The owner asked for relic chests, a pet and a free re-spin on the wheel, plus "malo vise dna" --
-- a DNA prize bigger than the two that were already there. Four new segments cost 18.5 points of
-- weight and the four rows below funded them, so the table still sums to 100 and the odds board is
-- still readable without arithmetic:
--
--   dna_splash  34 -> 30    the commonest row pays for the commonest new one (the re-spin)
--   potion      24 -> 21
--   dna_surge   18 -> 11    THE BIG CUT, and the deliberate one. `dna_flood` below is the DNA the
--                           owner asked for, and the wheel's DNA budget was already spent -- so the
--                           middle of the DNA ladder shrinks and the money moves into a rarer,
--                           larger payout. The wheel's DNA now arrives as a longer tail rather than
--                           as a fat middle, which is what makes a 20,000 row worth landing on.
--   diamonds    12 -> 10
--   shards       7 -> 7     unchanged: this row IS the shard price of a spin (SpinCostShards), so
--                           moving it would quietly change how often the wheel refunds itself
--   luck_l     3.5 -> 3
--   vault        1 -> 1     unchanged
--   jackpot    0.5 -> 0.5   unchanged -- the marquee does not get cheaper because the wheel grew
--
-- ===== WHY `respin` SITS AT POSITION 2 AND NOT WHEREVER ITS WEIGHT WOULD PUT IT =====
--
-- Every other row is in descending weight order, which is what makes the luck ramp legible. This
-- one is not, and the exception is the whole reason it is safe.
--
-- A re-spin is not a prize, it is a MULTIPLIER ON THE WHOLE TABLE: at probability p, every payout
-- on this wheel is worth 1/(1-p) of its face value, because 6 spins in 100 come back for another
-- go. At p = 0.06 that is x1.064 on everything, which is why the raw DNA figure below (2,060) had
-- to be set under the 2,260 the old wheel paid rather than at it -- 2,060 / 0.94 = 2,191, and 2,191
-- is the number that has to stay under the pack.
--
-- Luck must therefore NOT lift this row, or a lucky player would not merely win better prizes, they
-- would win MORE SPINS, and the multiplier would compound with the same luck that already bent the
-- prizes. Position 2 gives it a spread of 1/11 -- the smallest non-zero lift on the wheel -- so at
-- the game's worst honest luck (385%) the re-spin goes 6% -> 4.0% of the table rather than up.
-- Luck makes the re-spin RARER as a share, which is exactly right: it is being crowded out by the
-- real prizes it is there to hand you another shot at.
--
-- ===== THE FOUR NEW ROWS =====
--
--   respin      6     Another spin. Granted by chaining server-side, capped -- see SpinMaxChain.
--   relic       5     One UNOPENED Relic Chest, banked through `RelicService.GiveChest`. A bought
--                     chest costs 40 Diamonds, so at 5% this row is worth ~2 Diamonds a spin, and
--                     the `diamonds` row it was funded from was cut by exactly 2 points. It banks
--                     even for a player under the forge's stage-10 gate: the chest waits in
--                     `data.RelicChests` and opens the day the forge does, which is a better answer
--                     than refusing a prize the wheel already showed them landing on.
--   pet         4     One pet, rolled out of the player's CURRENT zone's mid-tier egg. Not a fixed
--                     species: a wheel that always paid the same creature would be a duplicate
--                     generator within a day, and a pet from a zone the player has not reached
--                     would be worth nothing to them (see GetPetZoneFactor).
--   dna_flood   1.5   20,000 DNA. Ten times the commonest row and a third of the jackpot -- the
--                     rung the DNA ladder was missing between "nice" and "once a fortnight".
--
-- ===== `colors` AND `short` ARE HERE ON PURPOSE =====
--
-- The wheel is DRAWN now (`SpinReveal.client.lua`), and a pod's colour and its two-word caption are
-- facts about the prize, not about the panel. Putting them anywhere else means the surface that
-- shows the odds and the surface that shows the wheel can disagree about what a jackpot looks like
-- -- the same rule `GameConfig.Potions` already follows with its own `colors` pair, and for the
-- same reason. A row without them draws grey and still works; nothing here may ever be REQUIRED by
-- the drawing code, or a segment added in a hurry crashes the reveal instead of looking plain.
GameConfig.SpinWheel = {
	{ key = "dna_splash", emoji = "\u{1F9EC}", name = "DNA Splash",     short = "2K DNA",   weight = 30,  dna = 2000,
	  colors = { Color3.fromRGB(120, 210, 255), Color3.fromRGB(56, 138, 226) } },
	{ key = "respin",     emoji = "\u{1F3A1}", name = "FREE SPIN",      short = "SPIN AGAIN", weight = 6, respin = 1,
	  colors = { Color3.fromRGB(255, 226, 120), Color3.fromRGB(245, 160, 40) } },
	{ key = "potion",     emoji = "\u{1F9EA}", name = "Potion",         short = "POTION",   weight = 21,  potionId = "dna_m", potions = 1,
	  colors = { Color3.fromRGB(150, 250, 200), Color3.fromRGB(46, 190, 130) } },
	{ key = "dna_surge",  emoji = "\u{1F9EC}", name = "DNA Surge",      short = "6K DNA",   weight = 11,  dna = 6000,
	  colors = { Color3.fromRGB(140, 190, 255), Color3.fromRGB(70, 110, 235) } },
	{ key = "diamonds",   emoji = "\u{1F48E}", name = "25 Diamonds",    short = "25 GEMS",  weight = 10,  diamonds = 25,
	  colors = { Color3.fromRGB(170, 235, 255), Color3.fromRGB(70, 180, 240) } },
	{ key = "shards",     emoji = "\u{1F31F}", name = "25 Shards",      short = "25 SHARDS", weight = 7,  shards = 25,
	  colors = { Color3.fromRGB(255, 235, 150), Color3.fromRGB(240, 190, 55) } },
	{ key = "relic",      emoji = "\u{1F52E}", name = "Relic Chest",    short = "RELIC",    weight = 5,   relicChests = 1,
	  colors = { Color3.fromRGB(210, 170, 255), Color3.fromRGB(140, 85, 235) } },
	{ key = "pet",        emoji = "\u{1F43E}", name = "Mystery Pet",    short = "PET",      weight = 4,   pet = 1,
	  colors = { Color3.fromRGB(255, 175, 220), Color3.fromRGB(235, 90, 175) } },
	{ key = "luck_l",     emoji = "\u{1F340}", name = "2x Large Luck",  short = "2x LUCK",  weight = 3,   potionId = "luck_l", potions = 2,
	  colors = { Color3.fromRGB(180, 255, 165), Color3.fromRGB(80, 200, 90) } },
	{ key = "dna_flood",  emoji = "\u{1F30A}", name = "DNA FLOOD",      short = "20K DNA",  weight = 1.5, dna = 20000,
	  colors = { Color3.fromRGB(120, 165, 255), Color3.fromRGB(48, 70, 210) } },
	{ key = "vault",      emoji = "\u{1F48E}", name = "120 Diamonds",   short = "120 GEMS", weight = 1,   diamonds = 120,
	  colors = { Color3.fromRGB(190, 245, 255), Color3.fromRGB(40, 150, 225) } },
	{ key = "jackpot",    emoji = "\u{1F308}", name = "JACKPOT",        short = "JACKPOT",  weight = 0.5, dna = 100000, diamonds = 60,
	  colors = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(255, 120, 60) } },
}

-- HOW MANY TIMES ONE PRESS MAY CHAIN THROUGH `respin` BEFORE THE LAST ONE IS FORCED TO PAY.
--
-- 12 is not a balance figure, it is a fuse. At a 6% re-spin the chance of twelve in a row is
-- 0.06^12 ~= 2e-15, which is not a path any player will ever walk -- so this constant does not
-- change what the wheel is worth to anyone. What it does is make the grant loop in `RobuxShopService`
-- structurally unable to run forever: a config edit that pushed the re-spin weight to something
-- absurd, or a future segment that also chains, would otherwise hang a server thread inside a
-- receipt handler with the player's Robux already taken. A bounded loop cannot do that.
--
-- The client also reads this: a chain arrives as an ordered list of segments and the reveal plays
-- one spin per entry, so the bound is also the longest piece of theatre the wheel can ever ask a
-- player to sit through.
GameConfig.SpinMaxChain = 12

-- Where a segment sits in the table, by key. The wheel is DRAWN from this order and the pointer
-- lands by INDEX, so the client needs the index and the server has to send it -- but neither side
-- may hard-code it, because inserting a row would then silently point every prize at its neighbour.
-- Returns nil for an unknown key, which the caller is expected to treat as "do not animate", not as
-- an error: a segment key from a newer server than this client is a thing that will happen.
function GameConfig.GetSpinIndex(key)
	for i, seg in ipairs(GameConfig.SpinWheel) do
		if seg.key == key then return i end
	end
	return nil
end

-- How hard luck bends the wheel. NORMALISED BY SEGMENT COUNT -- (i-1)/(n-1), where
-- RollMysteryPotion uses a raw (i-1) -- and that difference is the whole reason this constant
-- exists. That table has three rows and this one has twelve, so under a raw index the same luck
-- would bend this wheel four times as hard, and adding a thirteenth segment one day would
-- silently make every existing player luckier without a line of code changing. Normalised, the
-- strength of luck is a property of this constant alone.
--
-- THE 8 -> 12 GROWTH ABOVE IS THE PROOF THAT THIS WORKS, and it is worth writing down because it
-- is the only test this design has ever had. Nothing here changed when four rows were added, and
-- the luck curve came out where it was: at the game's worst honest luck (385%, measured in the
-- ROADMAP 2.12 balance pass) the jackpot moves 0.5% -> 1.32% where the eight-row wheel gave 1.4%,
-- and the commonest segment moves 30% -> 14.1% where it used to go 34% -> 17%. Same shape, same
-- verdict: luck is worth having here and does not take the wheel over.
GameConfig.SpinLuckSpread = 1.2

-- What one spin costs in Evolution Shards, for the door into this wheel that takes no Robux (9.4).
-- 25 is exactly what the wheel's own `shards` segment pays, so 7 spins in 100 come back as the
-- price of the next one and that segment needed no rebalancing to say so. Everything the 3.3
-- balance pass measured about this wheel still holds unchanged: it is the same table, the same
-- roll and the same luck bend, reached through a third door.
GameConfig.SpinCostShards = 25

-- Returns the winning SEGMENT TABLE, not an index or a key -- the caller grants straight off it, so
-- there is no second lookup that could disagree with the roll.
function GameConfig.RollSpin(luckPercent)
	local wheel = GameConfig.SpinWheel
	local n = #wheel
	local weights, total = {}, 0
	for i, seg in ipairs(wheel) do
		-- i = 1 is the commonest segment and is never boosted; what luck buys is the step up the list
		local spread = (n > 1) and ((i - 1) / (n - 1)) or 0
		local w = seg.weight * (1 + ((luckPercent or 0) / 100) * spread * GameConfig.SpinLuckSpread)
		weights[i] = w
		total += w
	end
	local pick = math.random() * total
	for i, seg in ipairs(wheel) do
		pick -= weights[i]
		if pick <= 0 then return seg end
	end
	return wheel[1]
end

-- The odds board, built from the same table the roll reads -- the rule the Mystery shop already
-- follows. A gamble the player cannot see the odds of is not a product, it is a trick.
function GameConfig.GetSpinOddsText()
	local total = 0
	for _, seg in ipairs(GameConfig.SpinWheel) do total += seg.weight end
	local parts = {}
	for _, seg in ipairs(GameConfig.SpinWheel) do
		table.insert(parts, ("%s %s %.4g%%"):format(seg.emoji, seg.name, seg.weight / total * 100))
	end
	return table.concat(parts, "   ")
end

end
