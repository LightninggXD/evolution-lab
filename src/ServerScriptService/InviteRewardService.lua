local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local InviteInbox = DataStoreService:GetDataStore("InviteInbox")

local PlayerDataService = require(script.Parent.PlayerDataService)
local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)
local PetService = require(script.Parent.PetService)
local Remotes = game:GetService("ReplicatedStorage").Remotes

local InviteRewardService = {}

function InviteRewardService.Init()
	Players.PlayerAdded:Connect(function(player)
		local joinData = player:GetJoinData()
		local inviterIdStr = joinData and joinData.LaunchData or ""
		local inviterId = tonumber(inviterIdStr)
		
		-- Validate LaunchData
		if inviterId and inviterId ~= player.UserId then
			-- Let data load
			local data = nil
			for i = 1, 10 do
				data = PlayerDataService.Get(player)
				if data then break end
				task.wait(1)
			end
			
			-- Payout the joiner
			if data and not data.WasInvited then
				if player.AccountAge >= (GameConfig.InviteMinAccountAgeDays or 14) then
					data.WasInvited = true
					
					-- Insert the reward pet directly
					table.insert(data.Pets, { 
						id = game:GetService("HttpService"):GenerateGUID(false), 
						key = GameConfig.InviteRewardPetKey or "Amicus", 
						tier = "Normal" 
					})
					
					Remotes.Notify:FireClient(player, {
						kind = "inviteReward",
						message = "Welcome! You received an exclusive pet for joining a friend!"
					})
					
					-- Record for inviter (cross-server safe via DataStore UpdateAsync)
					pcall(function()
						InviteInbox:UpdateAsync(tostring(inviterId), function(oldList)
							local list = oldList or {}
							if #list < (GameConfig.InviteMaxPaid or 5) then
								table.insert(list, player.UserId)
							end
							return list
						end)
					end)
				end
			end
		end
		
		-- Check inbox for this player
		local data = nil
		for i = 1, 10 do
			data = PlayerDataService.Get(player)
			if data then break end
			task.wait(1)
		end
		
		if data then
			local inbox = nil
			pcall(function()
				inbox = InviteInbox:GetAsync(tostring(player.UserId))
			end)
			
			if inbox and type(inbox) == "table" and #inbox > 0 then
				local paidList = data.InvitesPaid or {}
				local granted = 0
				
				for _, joinedId in ipairs(inbox) do
					if not table.find(paidList, joinedId) and #paidList < (GameConfig.InviteMaxPaid or 5) then
						table.insert(paidList, joinedId)
						table.insert(data.Pets, { 
							id = game:GetService("HttpService"):GenerateGUID(false), 
							key = GameConfig.InviteRewardPetKey or "Amicus", 
							tier = "Normal" 
						})
						granted += 1
					end
				end
				
				data.InvitesPaid = paidList
				
				if granted > 0 then
					Remotes.Notify:FireClient(player, {
						kind = "inviteReward",
						message = "An invited friend joined! You received " .. granted .. " exclusive pet(s)!"
					})
					-- Push to client so they see the new pets immediately
					PlayerDataService.PushToClient(player)
				end
				
				-- Clear inbox
				pcall(function() InviteInbox:RemoveAsync(tostring(player.UserId)) end)
			end
		end
	end)
end

return InviteRewardService