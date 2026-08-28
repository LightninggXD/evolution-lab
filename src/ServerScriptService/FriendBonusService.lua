local Players = game:GetService("Players")

local FriendBonusService = {}
local friendGraph = {} -- [UserId] = { [FriendUserId] = true }

function FriendBonusService.Init()
	Players.PlayerAdded:Connect(function(player)
		friendGraph[player.UserId] = {}
		
		task.spawn(function()
			-- By checking only from the joiner, we avoid duplicate web calls and race conditions.
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and other.Parent then
					local ok, isFriend = pcall(function()
						return player:IsFriendsWith(other.UserId)
					end)
					if ok and isFriend then
						-- Since they are friends, it's symmetric.
						if player.Parent and other.Parent then
							friendGraph[player.UserId][other.UserId] = true
							if friendGraph[other.UserId] then
								friendGraph[other.UserId][player.UserId] = true
							end
						end
					end
				end
			end
		end)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		local friends = friendGraph[player.UserId]
		if friends then
			-- The leaver is excluded: we immediately remove their presence from all their friends' lists.
			for friendId, _ in pairs(friends) do
				if friendGraph[friendId] then
					friendGraph[friendId][player.UserId] = nil
				end
			end
			friendGraph[player.UserId] = nil
		end
	end)
end

function FriendBonusService.GetFriendCount(userId)
	local friends = friendGraph[userId]
	if not friends then return 0 end
	
	local count = 0
	for _ in pairs(friends) do
		count += 1
	end
	return count
end

return FriendBonusService
