local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)

local PlaytimeGiftService = {}

local sessionStart = {} -- [userId] = os.time() when they joined this session

-- WHAT WAS CLAIMED, KEPT IN THE SAVE AND STAMPED WITH A DAY.
--
-- This used to be a module-level table cleared on PlayerRemoving, so the entire gift ladder came
-- back every time a player rejoined. The time gate reset with it, which throttled the exploit
-- rather than stopping it -- but the early milestones are cheap, so a rejoin loop was a free and
-- repeatable DNA and Diamond faucet with no daily cap anywhere.
--
-- Kept in `data.PlaytimeClaims` instead: a set of claimed indices plus the day it belongs to.
-- Rejoining the same day changes nothing; a new day hands the ladder back, which is the intent --
-- these are DAILY playtime gifts, not once-per-account ones.
local function dayStamp()
	return math.floor(os.time() / 86400)
end

local function claimSet(data)
	if type(data.PlaytimeClaims) ~= "table" or data.PlaytimeClaims.day ~= dayStamp() then
		data.PlaytimeClaims = { day = dayStamp() }
	end
	return data.PlaytimeClaims
end

local function pushStatus(player)
	local data = PlayerDataService.Get(player)
	local claimedList = {}
	if data then
		for k in pairs(claimSet(data)) do
			-- keys are tostring(index): a table whose only key is [3] is a sparse array and Roblox
			-- silently drops those crossing a RemoteEvent -- the bug that once ate EquippedCharacters
			local idx = tonumber(k)
			if idx then table.insert(claimedList, idx) end
		end
	end
	Remotes.PlaytimeStatus:FireClient(player, {
		sessionStart = sessionStart[player.UserId],
		claimed = claimedList,
	})
end

function PlaytimeGiftService.HandleClaim(player, milestoneIndex)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local milestone = GameConfig.PlaytimeGifts[milestoneIndex]
	if not milestone then return end

	local userId = player.UserId
	local claims = claimSet(data)
	local slot = tostring(milestoneIndex)
	if claims[slot] then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Already claimed that gift today!" })
		return
	end

	local elapsedMinutes = (os.time() - (sessionStart[userId] or os.time())) / 60
	if elapsedMinutes < milestone.minutes then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Keep playing! Not ready yet." })
		return
	end

	claims[slot] = true

	-- see GameConfig.ScaleReward: a flat 35,000 stops being a gift about fifteen minutes in
	if milestone.dna then data.DNA += GameConfig.ScaleReward(milestone.dna, data) end
	if milestone.potions then GameConfig.AddPotions(data, milestone.potionId, milestone.potions) end
	if milestone.diamonds then data.Diamonds = (data.Diamonds or 0) + milestone.diamonds end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, { kind = "playtimeGift", minutes = milestone.minutes })
	pushStatus(player)
end

function PlaytimeGiftService.Init()
	Players.PlayerAdded:Connect(function(player)
		sessionStart[player.UserId] = os.time()
		-- the save may still be loading; pushStatus reads it and simply reports nothing claimed
		-- until it is there, and the client re-reads on its next DataUpdate
		task.wait(0.5)
		pushStatus(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessionStart[player.UserId] = nil
	end)

	Remotes.ClaimPlaytimeGift.OnServerEvent:Connect(function(player, milestoneIndex)
		if typeof(milestoneIndex) == "number" then
			PlaytimeGiftService.HandleClaim(player, milestoneIndex)
		end
	end)
end

return PlaytimeGiftService
