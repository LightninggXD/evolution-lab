-- DamageStat -- the one number the whole game is about (33.26), over the evolve bar (2026-08-28).
--
-- A HUD MODULE, i.e. a FUNCTION and not a table (`docs/SPLIT.md` section 2). It listens to one
-- player attribute plus `DataUpdate`, so **MainUI gains exactly one line and zero top-level
-- locals** ([[evolution-lab-mainui-register-limit]]).
--
-- ===== IT REPLACES A PROGRESS BAR, AND THAT IS STILL THE POINT =====
--
-- 33.21 drew the training ladder as a third stacked bar under the level bar. The owner refused it
-- twice in one session, and the two sentences remain the spec for this file:
--
--   *"a ovo zlatno mi ne treba tu"* -- the gold bar is not wanted on the screen at all, and
--   *"dmg se ne skuplja ovako vec samo da pise damage: pa koliko imam i kako skupljam povecava se"*
--   -- damage is not a thing you fill a bar with. It is a number you HAVE, it is written down, and
--   it goes up as you collect.
--
-- So there is no bar, no denominator, no cap and no multiplier bar anywhere on the main screen.
-- ONE FIGURE, WRITTEN DOWN. **What changed on 2026-08-28 is only WHERE it is written**: it was a
-- fourth pill in the wallet column and it is now a headline over the evolve bar, off a reference
-- image the owner sent. The refusal above is about the SHAPE (a bar), not the position, so the
-- restyle does not overturn it -- which is exactly why this paragraph is kept rather than deleted
-- along with the code it described.
--
-- The training ladder is NOT gone -- it is `TrainingReps` in the save, `TrainingDummyService`
-- still banks it, and it is one of the multipliers inside the number drawn here. What is gone is
-- the ladder's own widget. The cap is announced by the toast the dummy already fires, which is the
-- only moment the ANSWER changes rather than the number.
--
-- ===== THE CHANNEL IS AN ATTRIBUTE, FOR `LevelBar`'s REASON =====
--
-- `LevelService.Publish` stamps `CombatDamage` on its existing 0.4 s sweep, beside `Level`,
-- `LevelXp` and `TrainingReps`. It is NOT a second publisher and NOT `DataUpdate`: a push carries
-- the whole save table, and this number moves on every evolve, every blade, every pet, every level
-- and every rep. `DataUpdate` is still listened to because the join payload is what draws the
-- figure the first time, before the first sweep has run.
--
-- ===== WHY IT DOES NOT COMPUTE THE NUMBER ITSELF =====
--
-- `DNAService.GetCombatDamage` is still the only thing in this game that decides damage, and it is
-- server-side by design -- it reads pets, mastery, the blade, the level and the training rank. A
-- client-side re-derivation would be a second formula that drifts silently from the one the blows
-- actually use, which is exactly the "evolving changes nothing" class of bug the damage ladder was
-- unwound to fix. This file draws what the server says and knows nothing.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local formatNumber = UIKit.formatNumber

return function(hud)
	local player = Players.LocalPlayer
	local screenGui = hud.screenGui
	
	-- We put the damage text above the EvolveFrame
	local container = Instance.new("Frame")
	container.Name = "DamageStatContainer"
	container.Size = UDim2.new(0, 400, 0, 80)
	-- Position above the EvolveFrame (-10 from bottom + 68 height + some padding)
	container.Position = UDim2.new(0.5, 0, 1, -110)
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundTransparency = 1
	-- Z 5, NOT 50. `ZIndexBehavior` is Sibling here, so a top-level frame at 50 draws over every
	-- panel in the HUD -- and every panel is 20. Measured in the capture: `Damage: 5.18K`
	-- punched straight through the open Goals board. 5 puts it in the wallet's band (the
	-- CurrencyStack is 4, the evolve frame 1), which is what it is: chrome, not an overlay.
	container.ZIndex = 5
	container.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Padding = UDim.new(0, -5)
	listLayout.Parent = container

	-- NO MULTIPLIER LINE. The restyle drew one off a `CombatDamageMult` attribute; grep `src/` for
	-- that name and the only hits were the two lines that READ it. Nothing writes it, so the label
	-- was permanently `x1` and its own `mult > 1` test kept it permanently invisible -- a counter
	-- nobody increments, which looks exactly like a feature that works. The multipliers are already
	-- INSIDE the figure below (that is what `GetCombatDamage` is), so a second line naming one of
	-- them would be the stacked bar the owner refused, wearing a different hat.

	local dmgOuter = Instance.new("TextLabel")
	dmgOuter.Name = "DamageOuter"
	dmgOuter.LayoutOrder = 2
	dmgOuter.Size = UDim2.new(1, 0, 0, 45)
	dmgOuter.BackgroundTransparency = 1
	dmgOuter.Text = "Damage: 0"
	dmgOuter.Font = Enum.Font.FredokaOne
	dmgOuter.TextSize = 36
	dmgOuter.TextColor3 = Color3.fromRGB(255, 180, 0)
	dmgOuter.Parent = container
	local dmgOuterStroke = Instance.new("UIStroke")
	dmgOuterStroke.Color = Color3.fromRGB(0, 0, 0)
	dmgOuterStroke.Thickness = 6
	dmgOuterStroke.Parent = dmgOuter

	local dmgInner = Instance.new("TextLabel")
	dmgInner.Size = UDim2.new(1, 0, 1, 0)
	dmgInner.BackgroundTransparency = 1
	dmgInner.Text = "Damage: 0"
	dmgInner.Font = Enum.Font.FredokaOne
	dmgInner.TextSize = 36
	dmgInner.TextColor3 = Color3.fromRGB(255, 140, 0)
	dmgInner.ZIndex = dmgOuter.ZIndex + 2
	dmgInner.Parent = dmgOuter
	local dmgInnerStroke = Instance.new("UIStroke")
	dmgInnerStroke.Color = Color3.fromRGB(255, 220, 0)
	dmgInnerStroke.Thickness = 3
	dmgInnerStroke.Parent = dmgInner

	local function refresh()
		local dmg = tonumber(player:GetAttribute("CombatDamage"))
		if not dmg then return end
		local dmgText = "Damage: " .. formatNumber(math.floor(dmg))
		dmgOuter.Text = dmgText
		dmgInner.Text = dmgText
	end

	player:GetAttributeChangedSignal("CombatDamage"):Connect(refresh)
	Remotes.DataUpdate.OnClientEvent:Connect(refresh)
	refresh()
end
