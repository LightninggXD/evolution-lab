-- GameConfig -- the vanity layer's catalogue (34.2).
--
-- ===== IT IS A PART, NOT A PLAIN MODULE, AND THAT IS WHAT THE PART LIST DEMANDS =====
--
-- This file returned a bare table (`local Cosmetics = {...} return Cosmetics`) while
-- `GameConfig.lua`'s ordered part list already named it -- and that list does
-- `require(script:WaitForChild(part))(GameConfig)`. A table is not callable, so the entry could
-- never have loaded: in a Studio without this file the loader yielded forever on the
-- `WaitForChild`, and with it the call would have hard-errored at GameConfig load and taken every
-- script in the place with it.
--
-- Wrapped in `return function(GameConfig) ... end` and assigned onto the table, which is the shape
-- every other part uses and the shape this feature's own three readers already assume --
-- `CosmeticService`, the four HUD homes (Trails/Sword tabs, Name Plates, Emotes) and `EmoteClient`
-- all walk `ipairs(GameConfig.Cosmetics)`.
-- NOT ONE ROW OF THE CATALOGUE WAS TOUCHED.

return function(GameConfig)

-- ===== THE TRAILS ARE THE SPEED LADDER NOW (34.29) =====
--
-- Her call: *"nema vise speed u shopu da se kupi vec nek bude vise ovih trails i one ce da
-- upgradaju speed, tipa 5 varijanti"*. `GameConfig.Upgrades.Speed` is deleted; the five rows below
-- are what a player buys instead, and the one they WEAR is the one that pays.
--
-- WHY `speedPct` AND NOT A FLAT NUMBER OF STUDS. The Speed upgrade added studs inside the walk
-- clamp, and `EvolutionVisuals`'s own note says the term in there already reaches 581 against a cap
-- of 260 -- so those studs were sawn off entirely for most of the game, which is exactly the fault
-- 15.30 found and fixed for the mutation auras. A share of THIS player's cap lands in full at 1x
-- and at the top, which is the only shape that makes a ladder feel like a ladder. The aura ladder
-- is the precedent and its top rung is 12%; this one tops out at 20 and the two are bounded
-- together where they are applied, so the streaming ceiling cannot be blown past by wearing both.
--
-- **PRICED IN EVOLUTION SHARDS, AND THAT IS THE SECOND HALF OF THE SAME DECISION.** Her words:
-- *"shardovi kostaju samo za wheel ovaj, nek se shardovima kupuje trails"*. Shards had exactly one
-- sink in the whole game -- 25 for a wheel spin -- so every shard past the next spin was worth
-- nothing, while the raised Brute/Elite/Apex drops that pay them went on dropping. A currency with
-- one sink is a currency players stop caring about.
--
-- **AND NO ROBUX BUTTON ON THESE ROWS.** 34.2 admitted the vanity layer only because it was
-- *"cosmetic only, zero power, so it can be sold without touching the pay-to-win bound the passes
-- are held to"*. The moment a trail moves the player it is no longer cosmetic, and a Robux button
-- beside it would be selling movement speed directly. Shards ARE purchasable in packs, so this is
-- not a wall -- it is one step of indirection and a real in-game earn rate behind it, which is the
-- same footing every other power item in this game stands on. Name Plates and Emotes below carry
-- no power at all and keep their Robux prices.
--
-- SIZING, against the one shard price that already existed (a spin, 25). The first rung is FIVE --
-- deliberately under a single spin -- because the thing it replaces was `Upgrades.Speed` at 25 DNA,
-- the cheapest purchase in the game and the first one most players ever made. Shards come from
-- raised creatures, which are gated, so a first rung priced like the top of the ladder would leave
-- a new player with no speed progression at all for days.
GameConfig.Cosmetics = {
	-- Trails -- the speed ladder. `colors` rather than a `path`: the rows authored for 34.2 pointed
	-- at "Trails/Rainbow-01", an asset that exists nowhere in this repo, so the headline item bought
	-- nothing at all. A Trail is drawn from a ColorSequence and needs no texture and no id --
	-- `StarterPlayerScripts/CosmeticTrail.client.lua` is what reads these.
	--
	-- Priced against what the Speed upgrade used to cost to reach the same place: its first five
	-- levels (one zone's worth) ran 25 DNA and change, so the first rung is deliberately cheap
	-- enough to be an early purchase, and the ladder ends dearer than any other Diamond sink except
	-- the enchant transfer.
	{ key = "Trail_Spark", type = "Trail", name = "Spark Trail", emoji = "\u{1F4AB}", priceShards = 5, productId = 0, speedPct = 3,
		colors = { Color3.fromRGB(255, 246, 196), Color3.fromRGB(255, 214, 92) } },
	{ key = "Trail_Rainbow", type = "Trail", name = "Rainbow Trail", emoji = "\u{1F308}", priceShards = 40, productId = 0, speedPct = 6,
		colors = { Color3.fromRGB(255, 76, 76), Color3.fromRGB(255, 176, 46), Color3.fromRGB(255, 232, 74), Color3.fromRGB(96, 220, 118), Color3.fromRGB(84, 168, 255), Color3.fromRGB(178, 118, 255) } },
	{ key = "Trail_Fire", type = "Trail", name = "Fire Trail", emoji = "\u{1F525}", priceShards = 110, productId = 0, speedPct = 10,
		colors = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 168, 46), Color3.fromRGB(226, 62, 32) } },
	{ key = "Trail_Frost", type = "Trail", name = "Frost Trail", emoji = "\u{1F9CA}", priceShards = 250, productId = 0, speedPct = 15,
		colors = { Color3.fromRGB(226, 250, 255), Color3.fromRGB(126, 214, 255), Color3.fromRGB(70, 150, 240) } },
	{ key = "Trail_Galaxy", type = "Trail", name = "Galaxy Trail", emoji = "\u{1F30C}", priceShards = 500, productId = 0, speedPct = 20,
		colors = { Color3.fromRGB(126, 84, 255), Color3.fromRGB(70, 132, 255), Color3.fromRGB(236, 108, 220) } },

	-- Name Plates -- no power, so these keep their Robux prices.
	{ key = "NamePlate_Gold", type = "NamePlate", name = "Golden Plate", emoji = "\u{1F7E8}", priceDiamonds = 50, priceRobux = 49, productId = 0, color = Color3.fromRGB(255, 215, 0) },
	{ key = "NamePlate_Neon", type = "NamePlate", name = "Neon Plate", emoji = "\u{1F7EA}", priceDiamonds = 250, priceRobux = 99, productId = 0, color = Color3.fromRGB(0, 255, 255) },
	{ key = "NamePlate_Dark", type = "NamePlate", name = "Dark Plate", emoji = "\u{1F311}", priceDiamonds = 800, priceRobux = 199, productId = 0, color = Color3.fromRGB(30, 30, 30) },

	-- Emotes -- FREE, all of them (*"to moze i free sve biti"*). `priceDiamonds = 0` rather than a
	-- separate "owned" flag: every reader in this feature already asks the price, and a zero is a
	-- purchase that always succeeds, so nothing anywhere needs a branch for a free row.
	{ key = "Emote_Wave", type = "Emote", name = "Wave", emoji = "\u{1F44B}", priceDiamonds = 0, productId = 0, animId = "rbxassetid://507770239" },
	{ key = "Emote_Dance", type = "Emote", name = "Dance", emoji = "\u{1F483}", priceDiamonds = 0, productId = 0, animId = "rbxassetid://507771019" },
	{ key = "Emote_Cheer", type = "Emote", name = "Cheer", emoji = "\u{1F389}", priceDiamonds = 0, productId = 0, animId = "rbxassetid://507770677" },
}

-- ===== WHAT ONE ROW COSTS, AND IN WHICH CURRENCY (34.29) =====
--
-- Three cases and one function, because there are now three: a trail is priced in Shards, a name
-- plate in Diamonds, and an emote is FREE. Every reader -- the panel that prints the price, the
-- service that charges it, the button that greys itself -- asks this rather than reading a field,
-- so adding a fourth currency is a row here and no edits anywhere else.
--
-- Returns `amount, currency` where currency is "Shards", "Diamonds" or nil for free. A free row
-- returns `0, nil`, and callers must treat that as PURCHASABLE: `CosmeticService` refused any row
-- whose cost was `<= 0`, which made the three free emotes unbuyable and therefore unequippable --
-- found by reading this file's own new prices back against it rather than by anything failing.
function GameConfig.GetCosmeticPrice(c)
	if not c then return 0, nil end
	if c.priceShards and c.priceShards > 0 then return c.priceShards, "Shards" end
	if c.priceDiamonds and c.priceDiamonds > 0 then return c.priceDiamonds, "Diamonds" end
	return 0, nil
end

-- The worn trail's share of the walk cap, or 0. ONE function, read by the code that moves the
-- player and by the panel that prints the number, for the reason every other price in this repo is
-- read from one place: two copies disagree the first time a rung is retuned.
--
-- **IT IS `data.WornCosmetics.Trail`, NOT `data.WornTrail`.** The first version read the latter --
-- a field nothing in this game has ever written -- so it answered 0 for every player forever and
-- the whole speed ladder would have been inert. `CosmeticService.HandleEquip` writes
-- `WornCosmetics[type]` and mirrors it to a `Worn<Type>` ATTRIBUTE; the attribute is the client's
-- channel (see [[evolution-lab-splicer-auras]]) and the table is the save. Server code reads the
-- save. Caught by printing the catalogue back on a live boot, not by reading the code.
function GameConfig.GetTrailSpeedPct(data)
	local worn = data and data.WornCosmetics and data.WornCosmetics.Trail
	if not worn then return 0 end
	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.key == worn then return c.speedPct or 0 end
	end
	return 0
end


do
	local SAFE_LO, SAFE_HI = 0x1F300, 0x1F9FF
	for _, c in ipairs(GameConfig.Cosmetics) do
		local ok, cp = pcall(utf8.codepoint, c.emoji, 1)
		if not ok or type(cp) ~= "number" then
			warn(("[GameConfig.Cosmetics] %s has a missing or unreadable emoji -- it will draw as nothing"):format(c.key))
		elseif cp < SAFE_LO then
			warn(("[GameConfig.Cosmetics] %s has glyph U+%04X, BELOW U+1F300 -- text presentation, it draws as an outline or a box (27.7)"):format(c.key, cp))
		elseif cp > SAFE_HI then
			warn(("[GameConfig.Cosmetics] %s has glyph U+%04X, ABOVE U+1F9FF -- too new for the system emoji font, it draws as nothing at all (30.22)"):format(c.key, cp))
		end
	end
end

end
