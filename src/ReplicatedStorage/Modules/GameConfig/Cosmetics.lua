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
	-- Trails. `colors` rather than a `path`: the three rows authored for 34.2 pointed at
	-- "Trails/Rainbow-01", an asset that exists nowhere in this repo, so the headline
	-- 1,000-Diamond item bought nothing at all. A Trail is drawn from a ColorSequence and needs
	-- no texture and no id -- `StarterPlayerScripts/CosmeticTrail.client.lua` is what reads these.
	{ key = "Trail_Rainbow", type = "Trail", name = "Rainbow Trail", emoji = "\u{1F308}", priceDiamonds = 100, priceRobux = 49, productId = 0,
		colors = { Color3.fromRGB(255, 76, 76), Color3.fromRGB(255, 176, 46), Color3.fromRGB(255, 232, 74), Color3.fromRGB(96, 220, 118), Color3.fromRGB(84, 168, 255), Color3.fromRGB(178, 118, 255) } },
	{ key = "Trail_Fire", type = "Trail", name = "Fire Trail", emoji = "\u{1F525}", priceDiamonds = 300, priceRobux = 99, productId = 0,
		colors = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 168, 46), Color3.fromRGB(226, 62, 32) } },
	{ key = "Trail_Galaxy", type = "Trail", name = "Galaxy Trail", emoji = "\u{1F30C}", priceDiamonds = 1000, priceRobux = 199, productId = 0,
		colors = { Color3.fromRGB(126, 84, 255), Color3.fromRGB(70, 132, 255), Color3.fromRGB(236, 108, 220) } },

	-- Name Plates
	{ key = "NamePlate_Gold", type = "NamePlate", name = "Golden Plate", emoji = "\u{1F7E8}", priceDiamonds = 50, priceRobux = 49, productId = 0, color = Color3.fromRGB(255, 215, 0) },
	{ key = "NamePlate_Neon", type = "NamePlate", name = "Neon Plate", emoji = "\u{1F7EA}", priceDiamonds = 250, priceRobux = 99, productId = 0, color = Color3.fromRGB(0, 255, 255) },
	{ key = "NamePlate_Dark", type = "NamePlate", name = "Dark Plate", emoji = "\u{1F311}", priceDiamonds = 800, priceRobux = 199, productId = 0, color = Color3.fromRGB(30, 30, 30) },

	-- Emotes (using placeholder catalog animation ids)
	{ key = "Emote_Wave", type = "Emote", name = "Wave", emoji = "\u{1F44B}", priceDiamonds = 25, priceRobux = 0, productId = 0, animId = "rbxassetid://507770239" },
	{ key = "Emote_Dance", type = "Emote", name = "Dance", emoji = "\u{1F483}", priceDiamonds = 150, priceRobux = 99, productId = 0, animId = "rbxassetid://507771019" },
	{ key = "Emote_Cheer", type = "Emote", name = "Cheer", emoji = "\u{1F389}", priceDiamonds = 500, priceRobux = 149, productId = 0, animId = "rbxassetid://507770677" },
}


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
