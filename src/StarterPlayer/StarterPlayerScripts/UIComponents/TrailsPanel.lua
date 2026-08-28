-- TrailsPanel -- the speed ladder cosmetic shop and equip menu.
-- Built on ScrollingPanelBuilder (S23).

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local IconLibrary = require(RS.Modules:WaitForChild("IconLibrary"))
local formatNumber = UIKit.formatNumber

local TrailsPanel = {}
local panel = nil
local rows = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local READY = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local LOCKED = { Color3.fromRGB(180, 180, 180), Color3.fromRGB(100, 100, 100) }
local WORN = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }

local function pastel(c)
	return { c:Lerp(WHITE, 0.30), c:Lerp(WHITE, 0.62) }
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local owned = data.CosmeticsOwned or {}
	local worn = data.WornCosmetics or {}
	local shards = data.EvolutionShards or 0

	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.type == "Trail" then
			local refs = rows[c.key]
			if refs then
				local isOwned = owned[c.key] == true
				local isWorn = worn.Trail == c.key
				local speed = c.speedPct or 0

				refs.card.SetSubtitle(("+%d%% walk speed"):format(speed))

				if isOwned then
					if isWorn then
						refs.card.SetDescription("Equipped on your character")
						refs.card.Button.SetIcon("")
						refs.card.Button.SetPrice("UNEQUIP")
						-- WORN, not LOCKED. `SetEnabled(true, ...)` leaves the button clickable, and
						-- painting a live button in the DISABLED grey is how a working control reads
						-- as dead -- the same rule the sword ladder follows with its own DONE amber.
						refs.card.Button.SetEnabled(true, WORN)
						refs.card.Button.SetColors(WORN)
					else
						refs.card.SetDescription("Owned")
						refs.card.Button.SetIcon("")
						refs.card.Button.SetPrice("EQUIP")
						refs.card.Button.SetEnabled(true, READY)
						refs.card.Button.SetColors(READY)
					end
				else
					-- ===== THE WALLET THE BUTTON QUOTES IS THE ONE `CosmeticService` TAKES (34.35) =====
					--
					-- `GetCosmeticPrice` returns the currency beside the amount, and this is the only
					-- place a trail's price is printed -- so it prints what it was handed. Typing
					-- "Shards" in here would be the same slip as 34.35, a shop naming one currency
					-- while the charge comes out of another, the day a rung is repriced.
					local price, currency = GameConfig.GetCosmeticPrice(c)
					local wallet = (currency == "Diamonds") and (data.Diamonds or 0) or shards
					local affordable = wallet >= price
					refs.card.SetDescription("Speed boost cosmetic")
					-- ===== AND IT DRAWS THE CURRENCY THE WALLET DRAWS (2026-08-28, owner: "shard je
					-- drugaciji") =====
					--
					-- The first draft typed a literal \u{2728} in front of the number. That is the SPARKLE
					-- glyph, and an Evolution Shard is \u{1F31F} -- `IconLibrary`'s own note at :272 says
					-- the game gives the two stars different meanings, so the shop drew a four-point sparkle
					-- where the wallet pill three inches away draws the shard crystal, for the SAME currency.
					-- That is 34.35 one panel over. The glyph is resolved through `IconLibrary` and placed in
					-- the builder's own `ButtonIcon`, so the button's Image is the pill's Image byte for byte --
					-- and it falls back to the glyph, never to a blank, when a currency has no drawing.
					local glyph = (currency == "Diamonds") and "\u{1F48E}" or "\u{1F31F}"
					local art = IconLibrary.Resolve(glyph)
					refs.card.Button.SetIcon(art or "")
					refs.card.Button.SetPrice(art and formatNumber(price)
						or ("%s %s"):format(glyph, formatNumber(price)))
					refs.card.Button.SetEnabled(affordable, affordable and READY or LOCKED)
					refs.card.Button.SetColors(affordable and READY or LOCKED)
				end
			end
		end
	end
end

function TrailsPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Trails",
		-- A PLAIN WORD, AND NOT HER REBIRTH ARROWS (2026-08-28, owner: "trails ima rebirth znak
		-- gore"). `rbxassetid://17009541315` is the rebirth icon -- `MainUI:1064` and `RebirthPanel`
		-- both name it as such -- and it was copied in here and into `EmotesPanel` as a placeholder,
		-- so two panels wore the rebirth sign. The icon is the tab strip's own Trails art now
		-- (\u{2728} through `IconLibrary`, the same resolve `InventoryTabs` does), and the title
		-- drops the glyph: a `HeaderIcon` plus the same glyph typed into `Title` draws it twice (34.20).
		Title = "TRAILS",
		HeaderIcon = IconLibrary.Resolve("\u{2728}"),
		HeaderColors = { Color3.fromRGB(175, 138, 250), Color3.fromRGB(120, 80, 200) },
	})

	local order = 0
	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.type == "Trail" then
			order = order + 1
			local baseColor = (c.colors and c.colors[1]) or Color3.fromRGB(180, 180, 220)
			local card = panel.AddCard({
				Name = c.key,
				LayoutOrder = order,
				Title = c.name,
				Subtitle = ("+%d%% walk speed"):format(c.speedPct or 0),
				Description = "",
				Icon = "",
				BackgroundColors = pastel(baseColor),
				Buttons = {
					{
						Name = "Do",
						Price = "LOCKED",
						Icon = "",
						Colors = READY,
						Callback = function()
							local data = PlayerData.Get()
							if not data then return end
							local owned = data.CosmeticsOwned or {}
							local worn = data.WornCosmetics or {}
							if owned[c.key] then
								if worn.Trail == c.key then
									Remotes.CosmeticEquip:InvokeServer("Trail", "")
								else
									Remotes.CosmeticEquip:InvokeServer("Trail", c.key)
								end
							else
								Remotes.CosmeticPurchase:InvokeServer(c.key)
							end
						end,
					},
				},
			})
			rows[c.key] = { card = card, c = c }
		end
	end

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		if panel.IsOpen() then refresh() end
	end)
	refresh()
	return panel
end

function TrailsPanel.Toggle()
	if panel then panel.Toggle() end
end

function TrailsPanel.SetOpen(open)
	if panel then panel.SetOpen(open) end
end

function TrailsPanel.IsOpen()
	return panel ~= nil and panel.IsOpen()
end

function TrailsPanel.Refresh()
	if panel then panel.Refresh() end
end

return TrailsPanel
