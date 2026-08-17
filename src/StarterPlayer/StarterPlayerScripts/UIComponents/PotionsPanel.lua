-- PotionsPanel -- the potion bag, in the new panel design.
--
-- WHAT IT REPLACED: a version that listed all twelve potions whether you owned them or not and
-- whose USE button called `print("Use Potion dna_s")`. The button has to reach
-- `Remotes.UsePotion`, and the list has to be the BAG rather than the catalogue -- twelve rows of
-- things you do not have is not an inventory.
--
-- THIS IS THE ONE LIST WHOSE MEMBERSHIP CHANGES, so it is the one that rebuilds. Drinking the last
-- Small DNA bottle removes that row; the zone list, whose twenty-one rows are fixed, keeps its
-- cards and updates them instead. Rebuilding costs the scroll position, which is why it is not the
-- default.
--
-- THE ORDER IS THE CATALOGUE'S, NOT THE BAG'S. `GameConfig.Potions` is walked in its own order and
-- rows are skipped where the count is zero, so the bag reads the same way every time you open it:
-- a bottle drunk to zero and bought again comes back where it was rather than at the end.
--
-- WHAT AN ACTIVE POTION LOOKS LIKE: `data.PotionBoosts[kind]` is the live effect, and a kind that
-- is already running says so with its remaining time. **The button stays enabled**, and that is
-- worth being explicit about because the obvious guess is wrong: drinking a second bottle of a
-- running kind ADDS its time (`applyBoost` sums the remainder) and takes the STRONGER multiplier,
-- so it is never a wasted bottle. Greying it out would be the panel refusing something the game
-- allows.
--
-- EXPIRY IS `GameConfig.GetPotionBoost`'s JOB, not this file's. It returns nil for a boost whose
-- `untilTs` has passed, so nothing here has to know the field name or run a cleanup -- and the
-- panel can never disagree with the HUD's timers about what is running.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local PotionsPanel = {}
local panel = nil

local WHITE = Color3.fromRGB(255, 255, 255)
local USE = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local FALLBACK_ICON = "rbxassetid://138146402871393"

local function pastel(c)
	return { c:Lerp(WHITE, 0.30), c:Lerp(WHITE, 0.62) }
end

--- Seconds left on this kind's active boost, or 0. Routed through `GameConfig.GetPotionBoost` so
--- the expiry rule lives in one place -- it returns nil once `untilTs` has passed.
local function activeSeconds(data, kind)
	local boost = GameConfig.GetPotionBoost(data, kind)
	if not boost then return 0 end
	return math.max(0, (boost.untilTs or 0) - os.time())
end

local function refresh(p)
	local data = PlayerData.Get()
	if not data then return end

	p.Clear()
	local held = data.Potions or {}
	local any = false

	for _, potion in ipairs(GameConfig.Potions) do
		local count = held[potion.id] or 0
		if count > 0 then
			any = true
			local left = activeSeconds(data, potion.kind)
			local card = p.AddCard({
				Name = potion.id,
				Title = potion.shortName,
				Subtitle = ("%d min  ·  x%d held"):format(potion.minutes, count),
				Description = left > 0
					and ("Active — %d:%02d left, drinking adds more"):format(left // 60, left % 60)
					or potion.blurb,
				Icon = potion.imageId or FALLBACK_ICON,
				BackgroundColors = pastel(potion.color),
				Buttons = {
					{
						Name = "Use",
						Price = "USE",
						Icon = "",
						Colors = USE,
						Callback = function()
							-- the id is sent, but the server re-reads the bag and refuses a bottle
							-- that is not there -- so a stale card cannot conjure a potion
							Remotes.UsePotion:FireServer(potion.id)
						end,
					},
				},
			})
			-- Still pressable while one is running -- see the header. The label changes so the
			-- player can see the kind is live, not so the button can refuse.
			if left > 0 then
				card.Buttons.Use.SetPrice("+TIME")
			end
		end
	end

	p.SetEmptyText("No potions yet — buy them at a zone shop")
	p.ShowEmpty(not any)
end

function PotionsPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Potions",
		Title = "POTIONS",
		HeaderIcon = FALLBACK_ICON,
		HeaderColors = { Color3.fromRGB(100, 200, 255), Color3.fromRGB(50, 150, 255) },
		EmptyText = "No potions yet — buy them at a zone shop",
	})

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		-- the bag rebuilds, so this is more expensive than the zone list's restyle -- only ever
		-- while the panel is actually on screen
		if panel.IsOpen() then refresh(panel) end
	end)
	refresh(panel)
	return panel
end

function PotionsPanel.Toggle()
	if panel then panel.Toggle() end
end

return PotionsPanel
