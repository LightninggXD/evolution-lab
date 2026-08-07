local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local DNAService = require(script.Parent.DNAService)

local PotionService = {}

-- ONE ACTIVE BOTTLE PER KIND, and the three kinds run independently.
--
-- Drinking a second bottle of a kind that is already running does NOT multiply the two together:
-- it takes the STRONGER effect and adds the remaining time. Stacking multipliers collapses a
-- consumable economy into a single "drink the whole shelf at once" decision, and it is also how a
-- x2 and a x5 quietly become a x10 that no number in the config ever predicted. Adding the time
-- instead means a shelf full of small bottles is a long boost and a large one is a strong boost,
-- which is the choice the three sizes exist to offer.
local function applyBoost(data, potion)
	data.PotionBoosts = data.PotionBoosts or {}
	local live = GameConfig.GetPotionBoost(data, potion.kind)
	local remaining = live and math.max((live.untilTs or 0) - os.time(), 0) or 0

	local boost = {
		untilTs = os.time() + remaining + potion.seconds,
		-- What the HUD counter draws its bar from. `untilTs` alone gives a countdown but no sense of
		-- proportion -- a bar needs to know what full looks like, and because drinking a second
		-- bottle ADDS time (see the note above), full is not the bottle's own duration. Recorded
		-- here, where the sum is actually known.
		totalSecs = remaining + potion.seconds,
		startTs = os.time(),
		-- whichever of the two is stronger; nil for the field this kind does not use
		mult = potion.mult and math.max(potion.mult, (live and live.mult) or 0) or nil,
		luckAdd = potion.luckAdd and math.max(potion.luckAdd, (live and live.luckAdd) or 0) or nil,
	}
	data.PotionBoosts[potion.kind] = boost
	return boost
end

function PotionService.HandleUsePotion(player, potionId)
	local data = PlayerDataService.Get(player)
	if not data then return end

	-- An empty call is the HUD's quick tile: drink whatever is nearest to hand rather than making
	-- the player open a panel to use the one bottle they own.
	local potion = GameConfig.GetPotion(potionId)
	if not potion then
		for _, p in ipairs(GameConfig.Potions) do
			if (data.Potions and data.Potions[p.id] or 0) > 0 then potion = p break end
		end
	end
	if not potion then
		Remotes.Notify:FireClient(player, { kind = "error", message = "No Potions to use!" })
		return
	end

	local held = (data.Potions and data.Potions[potion.id]) or 0
	if held <= 0 then
		Remotes.Notify:FireClient(player, { kind = "error", message = "You have no " .. potion.name .. "!" })
		return
	end

	data.Potions[potion.id] = held - 1
	if data.Potions[potion.id] <= 0 then data.Potions[potion.id] = nil end

	local boost = applyBoost(data, potion)

	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "potion",
		potionId = potion.id,
		untilTs = boost.untilTs,
		message = ("%s %s  -  %s"):format(potion.emoji, potion.name, potion.effectText),
	})
end

-- THE MYSTERY POTION SHOP. Five of these in the whole strip (GameConfig.ZoneShops), and the
-- product is the roll: one sealed bottle, any of the nine. The prompt carries its own price as a
-- `MysteryCost` attribute so the purchase is validated against the counter the player is standing
-- at rather than against a number the client sent -- the same shape the egg prompts use.
function PotionService.HandleBuyMystery(player, cost)
	local data = PlayerDataService.Get(player)
	if not data then return end

	if data.DNA < cost then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough DNA for a Mystery Potion!" })
		return
	end

	data.DNA -= cost
	-- the player's own luck reaches the shop: it shifts the roll toward the bigger bottles
	local potionId = GameConfig.RollMysteryPotion(DNAService.GetLuckPercent(data))
	local potion = GameConfig.AddPotions(data, potionId, 1)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("%s %s %s!  %s"):format(potion.sizeEmoji, potion.emoji, potion.name, potion.effectText),
	})
end

-- Wired fresh on every server start rather than stored: ZoneBuilder regenerates the whole Zones
-- folder whenever BUILD_VERSION changes, which destroys every prompt built by the previous one.
local function wireShops()
	local zones = workspace:FindFirstChild("Zones")
	if not zones then return 0 end
	local wired = 0
	for _, d in ipairs(zones:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			local cost = d:GetAttribute("MysteryCost")
			if cost then
				wired += 1
				d.Triggered:Connect(function(player)
					PotionService.HandleBuyMystery(player, cost)
				end)
			end
		end
	end
	return wired
end

function PotionService.Init()
	Remotes.UsePotion.OnServerEvent:Connect(function(player, potionId)
		-- never trust the id: GetPotion returns nil for anything that is not one of the nine, and
		-- the handler then falls back to the first bottle actually held
		PotionService.HandleUsePotion(player, type(potionId) == "string" and potionId or nil)
	end)
	local wired = wireShops()
	print(("[PotionService] wired %d mystery potion counters"):format(wired))
end

return PotionService
