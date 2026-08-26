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
-- `CosmeticService`, `CosmeticsPanel` and `EmoteClient` all walk `ipairs(GameConfig.Cosmetics)`.
-- NOT ONE ROW OF THE CATALOGUE WAS TOUCHED.

return function(GameConfig)

GameConfig.Cosmetics = {
	-- Trails
	{ key = "Trail_Rainbow", type = "Trail", name = "Rainbow Trail", emoji = "\u{1F308}", priceDiamonds = 100, priceRobux = 49, productId = 0, path = "Trails/Rainbow-01" },
	{ key = "Trail_Fire", type = "Trail", name = "Fire Trail", emoji = "\u{1F525}", priceDiamonds = 300, priceRobux = 99, productId = 0, path = "Trails/Fire-01" },
	{ key = "Trail_Galaxy", type = "Trail", name = "Galaxy Trail", emoji = "\u{1F30C}", priceDiamonds = 1000, priceRobux = 199, productId = 0, path = "Trails/Galaxy-01" },

	-- Name Plates
	{ key = "NamePlate_Gold", type = "NamePlate", name = "Golden Plate", emoji = "\u{1F7E8}", priceDiamonds = 50, priceRobux = 49, productId = 0, color = Color3.fromRGB(255, 215, 0) },
	{ key = "NamePlate_Neon", type = "NamePlate", name = "Neon Plate", emoji = "\u{1F7EA}", priceDiamonds = 250, priceRobux = 99, productId = 0, color = Color3.fromRGB(0, 255, 255) },
	{ key = "NamePlate_Dark", type = "NamePlate", name = "Dark Plate", emoji = "\u{26AB}", priceDiamonds = 800, priceRobux = 199, productId = 0, color = Color3.fromRGB(30, 30, 30) },

	-- Emotes (using placeholder catalog animation ids)
	{ key = "Emote_Wave", type = "Emote", name = "Wave", emoji = "\u{1F44B}", priceDiamonds = 25, priceRobux = 0, productId = 0, animId = "rbxassetid://507770239" },
	{ key = "Emote_Dance", type = "Emote", name = "Dance", emoji = "\u{1F483}", priceDiamonds = 150, priceRobux = 99, productId = 0, animId = "rbxassetid://507771019" },
	{ key = "Emote_Cheer", type = "Emote", name = "Cheer", emoji = "\u{1F389}", priceDiamonds = 500, priceRobux = 149, productId = 0, animId = "rbxassetid://507770677" },
}

end
