-- ShopPanel -- the Robux store, in the new panel design.
--
-- WHAT IT REPLACED, and this is the one that mattered most: the first version drew two hard-coded
-- cards ("OP Magic" at 899 and "GM Commond" at 1999) whose buy buttons called
-- `print("Prompt Purchase OP Magic")`. Neither product exists in `GameConfig.RobuxProducts`,
-- neither has a `productId`, and nothing in the file could ever have taken a payment. This is the
-- screen the game earns on, so it is wired to the real ladder.
--
-- THE CARDS ARE `GameConfig.RobuxProducts`, and the button fires `Remotes.PromptRobuxPurchase`,
-- which is the same door `ProductTiles` in the old HUD uses. **The client never prompts
-- MarketplaceService directly**: the server holds the product id, and `ProcessReceipt` is what
-- grants. A client that picked its own id could be made to prompt for the wrong product.
--
-- THE PRICE GOES ON THE BUTTON, which is a rule the old shop already paid for: every tile once read
-- "Buy with R$", so a 49 and a 999 looked like the same decision and the player had to open a
-- Roblox modal to find out which was which.
--
-- THE RIBBON IS ARITHMETIC, NOT A CLAIM. `GetTierBonusPct` divides this tier's payout per Robux by
-- the cheapest tier's, so "+48% BONUS" is something this table actually contains. Nothing here says
-- "most popular" -- that is a claim about other players and nothing in this game measures it.
--
-- WHAT IS NOT HERE: the game passes, which are a different purchase with a different door
-- (`PromptGamePassPurchase`) and a different question -- "do I already own it" rather than "what
-- does it cost". They keep their own panel.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))

local ShopPanel = {}
local panel = nil

local WHITE = Color3.fromRGB(255, 255, 255)
local ROBUX = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }

-- One pastel per product family, so the ladder reads as groups rather than as a flat list of
-- twenty. Keyed on `tierGroup`, with the one-off products falling through to a neutral.
local FAMILY = {
	DNA = Color3.fromRGB(96, 200, 255),
	Diamonds = Color3.fromRGB(126, 226, 255),
	Shards = Color3.fromRGB(255, 206, 92),
	TierUp = Color3.fromRGB(255, 150, 200),
}
local OTHER = Color3.fromRGB(190, 170, 255)

local function pastel(c)
	return { c:Lerp(WHITE, 0.30), c:Lerp(WHITE, 0.62) }
end

--- What this product actually hands over, as a sentence. Read off the grant fields rather than
--- written per product, so a product added to the config cannot arrive here with no description.
local function grantLine(p)
	local bits = {}
	if p.grantDNA then bits[#bits + 1] = ("%s DNA"):format(p.grantDNA) end
	if p.grantDiamonds then bits[#bits + 1] = ("%d Diamonds"):format(p.grantDiamonds) end
	if p.grantShards then bits[#bits + 1] = ("%d Evolution Shards"):format(p.grantShards) end
	if p.grantPotions then bits[#bits + 1] = ("%d Potions"):format(p.grantPotions) end
	if p.grantSpin then bits[#bits + 1] = "1 Lucky Spin" end
	return #bits > 0 and table.concat(bits, "  ·  ") or (p.blurb or "")
end

function ShopPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Store",
		Title = "STORE",
		HeaderIcon = "rbxassetid://17009547085", -- her shopping basket
		HeaderColors = { Color3.fromRGB(220, 150, 255), Color3.fromRGB(150, 50, 255) },
		EmptyText = "The store is unavailable right now",
	})

	for i, product in ipairs(GameConfig.RobuxProducts) do
		-- A product with no id cannot be charged for, and a card that cannot be bought is worse
		-- than an absent one -- it is the exact failure this file was written to remove.
		if product.productId then
			local bonus = GameConfig.GetTierBonusPct and GameConfig.GetTierBonusPct(product) or 0
			panel.AddCard({
				Name = product.key,
				LayoutOrder = i,
				Title = product.name,
				Subtitle = grantLine(product),
				Description = bonus > 0 and ("+" .. math.floor(bonus) .. "% BONUS VALUE") or nil,
				Icon = product.imageId or "",
				BackgroundColors = pastel(FAMILY[product.tierGroup] or OTHER),
				Buttons = {
					{
						Name = "Buy",
						Price = "R$ " .. tostring(product.price or "?"),
						Icon = "",
						Colors = ROBUX,
						-- the KEY, never the product id: the server looks the id up itself, so a
						-- tampered client can only ever name a product that exists
						Callback = function()
							Remotes.PromptRobuxPurchase:FireServer(product.key)
						end,
					},
				},
			})
		end
	end

	return panel
end

function ShopPanel.Toggle()
	if panel then panel.Toggle() end
end

return ShopPanel
