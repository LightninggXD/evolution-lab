-- SwordPanel using ScrollingPanelBuilder
local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local SwordPreview = require(RS.Modules:WaitForChild("HUD"):WaitForChild("SwordPreview"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local formatNumber = UIKit.formatNumber

local SwordPanel = {}
local panel = nil
local rows = {}

local READY = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local DONE = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }
local LOCKED = { Color3.fromRGB(180, 180, 180), Color3.fromRGB(100, 100, 100) }

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local level = GameConfig.GetSwordLevel(data)
	local diamonds = data.Diamonds or 0
	local maxLevel = GameConfig.MaxSwordLevel
	local nextCost = GameConfig.GetSwordCost(level)
	local maxed = (nextCost == math.huge)

	panel.SetTitle("WEAPON")
	
	for i, tier in ipairs(GameConfig.Swords) do
		local refs = rows[i]
		if refs then
			if i < level then
				refs.card.SetSubtitle("✓ Forged")
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("✓")
				refs.card.Button.SetEnabled(false, DONE)
				refs.card.SetColors({ tier.color:Lerp(Color3.new(1,1,1), 0.5), tier.color:Lerp(Color3.new(1,1,1), 0.7) })
			elseif i == level then
				refs.card.SetSubtitle("EQUIPPED")
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("⚔️")
				refs.card.Button.SetEnabled(false, DONE)
				refs.card.SetColors({ tier.color, tier.color:Lerp(Color3.new(0,0,0), 0.2) })
			elseif i == level + 1 then
				local affordable = diamonds >= tier.cost
				refs.card.SetSubtitle("Next Upgrade")
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("💎 " .. formatNumber(tier.cost))
				refs.card.Button.SetEnabled(affordable, affordable and READY or LOCKED)
				refs.card.SetColors({ tier.color, tier.color:Lerp(Color3.new(0,0,0), 0.2) })
			else
				refs.card.SetSubtitle(string.format("After %d more", i - level - 1))
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("💎 " .. formatNumber(tier.cost))
				refs.card.Button.SetEnabled(false, LOCKED)
				refs.card.SetColors({ Color3.fromRGB(150, 150, 150), Color3.fromRGB(100, 100, 100) })
			end
		end
	end
end

function SwordPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Sword",
		-- NO EMOJI IN THE TITLE. `HeaderIcon` already draws the crossed blades beside it, so a glyph
		-- here renders the panel as "(swords) (swords) WEAPON" -- measured in the capture. Every
		-- other builder panel passes a plain word for the same reason.
		Title = "WEAPON",
		HeaderIcon = "rbxassetid://115197317627143", -- swords
		HeaderColors = { Color3.fromRGB(255, 215, 0), Color3.fromRGB(200, 150, 0) },
	})

	for i, tier in ipairs(GameConfig.Swords) do
		local card = panel.AddCard({
			Name = "Blade" .. i,
			LayoutOrder = i,
			Title = i .. ". " .. tier.displayName,
			Subtitle = "",
			Description = "",
			Icon = "", -- We will attach the preview below
			BackgroundColors = { tier.color, tier.color:Lerp(Color3.new(0,0,0), 0.2) },
			Buttons = {
				{
					Name = "Do",
					Price = "LOCKED",
					Icon = "",
					Colors = READY,
					Callback = function()
						Remotes.BuySword:FireServer()
					end,
				},
			},
		})
		
		-- Attach the 3D preview
		SwordPreview.Attach(card.Instance, tier, {
			size = 68,
			position = UDim2.new(0, 12, 0.5, 0),
			anchorPoint = Vector2.new(0, 0.5),
			zIndex = card.Instance.ZIndex + 5,
		})
		
		-- ===== THE GUTTER IS ONE FRAME, AND IT IS NOT NAMED WHAT THIS ASKED FOR =====
		--
		-- This used to shift three labels found by `FindFirstChild("TitleLabel")` /
		-- `"SubtitleLabel"` / `"DescriptionLabel"`. The builder names them `CardTitle`,
		-- `CardSubtitle` and `CardDescription` and parents all three to a `Text` frame -- so all
		-- three lookups returned nil, nothing moved, and the 68-stud sword preview drew straight
		-- over the card's own text. A name that exists, just not here: the shape that has cost this
		-- repo more silent bugs than any other.
		--
		-- Moving the ONE frame is also what the builder itself does (`SetIcon`), and its arithmetic
		-- is copied rather than re-invented: a left gutter of `g`, a right margin of 170 for the
		-- action button. 92 = the preview's 12-stud inset plus its 68 width plus 12 of air.
		local txtFrame = card.Instance:FindFirstChild("Text")
		if txtFrame then
			txtFrame.Size = UDim2.new(1, -(92 + 170), 1, -20)
			txtFrame.Position = UDim2.new(0, 92, 0.5, 0)
		end

		rows[i] = { card = card }
	end

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		if panel.IsOpen() then refresh() end
	end)
	refresh()
	return panel
end

function SwordPanel.Toggle()
	if panel then panel.Toggle() end
end

return SwordPanel
