local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)
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
		-- 11.8's health bottle carries a second field, and it takes the stronger one for the same
		-- reason the other two do -- a small bottle drunk during a large one must not slow the regen
		-- it is already getting.
		regenMult = potion.regenMult and math.max(potion.regenMult, (live and live.regenMult) or 0) or nil,
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

	-- THE RISING EDGE (11.8). Max health is a property on the Humanoid, not a number read at the
	-- point of use, so a health bottle does nothing at all until something re-applies it.
	-- `RefreshBonuses` recomputes the whole product -- stage, Stage Mastery, worn skin, potion --
	-- which is also what makes it the correct call on the falling edge, below.
	if potion.kind == "health" then
		PotionService.RefreshHealth(player, data)
	end

	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "potion",
		potionId = potion.id,
		untilTs = boost.untilTs,
		message = ("%s %s  -  %s"):format(potion.emoji, potion.name, potion.effectText),
	})
end

-- ===== THE HEALTH BOTTLE'S TWO EDGES, AND ITS REGENERATION (11.8) =====
--
-- `EvolutionVisuals` is required LAZILY, inside the function. Requiring it at the top of this file
-- would be a cycle -- it requires PlayerDataService and this file is pulled in by ServerMain before
-- the Systems folder -- and the whole point of `RefreshBonuses` is that it recomputes rather than
-- remembers, so calling it late is free.
function PotionService.RefreshHealth(player, data)
	local ok, EvolutionVisuals = pcall(require, script.Parent.Systems.EvolutionVisuals)
	if ok and EvolutionVisuals and EvolutionVisuals.RefreshBonuses then
		EvolutionVisuals.RefreshBonuses(player, data)
	end
end

-- POLL THE TRANSITION, NEVER SCHEDULE IT -- Phase 7's rule, and a health bottle is the case it was
-- written for. `GetPotionBoost` expires lazily, so nothing fires when the twenty minutes are up: a
-- `task.delay` set at drink time would be lost on a server restart, would drift, and would never be
-- set at all for a player who joined with a boost already running (which the save allows, because
-- `untilTs` is an absolute timestamp). Comparing "live now" against "live last tick" is correct
-- after a restart at any point in the window.
--
-- The same tick pays the regeneration, because it already knows the boost is live and already has
-- the Humanoid in hand. 1% of max health a second at the base rate, times the bottle's `regenMult`.
-- EXPORTED, not local, purely so it can be verified. A probe cannot reach the live
-- `PlayerDataService.Cache` (a `require` from outside the server's own tree gets a fresh module with
-- an empty cache), so the only way to test this loop against a fixture is to start a second copy of
-- it in the probe's own context, where every require resolves to the same fresh instance. Testing it
-- by reimplementing the body in the probe would let two copies agree with each other while the
-- shipped one is wrong -- the trap 5.7 wrote down.
function PotionService.DriveHealthPotions()
	local Players = game:GetService("Players")
	local wasLive = {}
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = PlayerDataService.Get(player)
			if data then
				local boost = GameConfig.GetPotionBoost(data, "health")
				local live = boost ~= nil
				if live ~= (wasLive[player.UserId] or false) then
					wasLive[player.UserId] = live
					-- both edges go through the same call: on the way up it multiplies the term in,
					-- on the way down `GetPotionHealthMult` is 1 again and the number simply returns
					PotionService.RefreshHealth(player, data)
				end
				if live then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
						humanoid.Health = math.min(humanoid.MaxHealth,
							humanoid.Health + humanoid.MaxHealth * 0.01 * GameConfig.GetPotionRegenMult(data))
					end
				end
			end
		end
	end
end

-- THE MYSTERY POTION SHOP. Seven of these in the whole strip (GameConfig.ZoneShops), and the
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
	Telemetry.Economy(player, "Sink", Telemetry.Currency.DNA, cost, data.DNA,
		Telemetry.Tx.Shop, "mysteryPotion")
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
	-- one loop for the whole server, not one per player and not one per bottle (11.8)
	task.spawn(PotionService.DriveHealthPotions)
	local wired = wireShops()
	print(("[PotionService] wired %d mystery potion counters"):format(wired))
end

return PotionService
