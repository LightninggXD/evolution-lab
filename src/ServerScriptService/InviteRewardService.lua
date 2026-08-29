-- InviteRewardService -- the exclusive pet on both ends of a game invite.
--
-- Two halves, and they are deliberately not symmetric. The JOINER is here, in this server, with a
-- `LaunchData` stamped by the invite they accepted, so they can be paid on the spot. The INVITER is
-- usually somewhere else entirely -- another server, or offline -- so their half is written to a
-- DataStore inbox and collected the next time they join. `UpdateAsync` rather than
-- `Get`-then-`Set` because two friends can accept the same person's invite on two servers in the
-- same second, and a read-modify-write would drop one of them.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local InviteInbox = DataStoreService:GetDataStore("InviteInbox")

local PlayerDataService = require(script.Parent.PlayerDataService)
local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)
local PetService = require(script.Parent.PetService)
local Remotes = game:GetService("ReplicatedStorage").Remotes

local InviteRewardService = {}

--- The save, once it exists. Ten seconds is well past a normal load and the loop simply gives up
--- rather than paying into a table nothing reads -- the inbox is not cleared on that path, so the
--- grant is still owed and the next join collects it.
local function awaitData(player)
	for _ = 1, 10 do
		local data = PlayerDataService.Get(player)
		if data then return data end
		task.wait(1)
	end
	return nil
end

--- ONE PET, THROUGH `PetService`. `insertPet` is the only place in the game a pet is created (see
--- the note over `GrantWheelPet`); this file used to write its own `table.insert(data.Pets, ...)`
--- twice, which both duplicated the entry shape and skipped `MAX_PETS` -- an invite could push a
--- full bag past the cap and leave `TrimCollection` to pick what to throw away.
--- Returns true only when a pet actually landed.
local function grantInvitePet(data)
	local def = PetService.GrantPetByKey(data, GameConfig.InviteRewardPetKey or "Amicus")
	return def ~= nil
end

--- The joiner's half: they arrived through someone's invite link, so they get the pet once, ever.
local function payJoiner(player, inviterId)
	local data = awaitData(player)
	if not data or data.WasInvited then return end
	-- The account-age gate is the whole anti-farm: an invite loop is only worth running if the
	-- alts it makes can be paid, and a fresh account cannot be.
	if player.AccountAge < (GameConfig.InviteMinAccountAgeDays or 14) then return end
	-- SET BEFORE THE GRANT, not after: everything below yields, and a second PlayerAdded for the
	-- same save (a rejoin inside the load window) must not find this still false.
	data.WasInvited = true
	if not grantInvitePet(data) then
		-- a full bag is the one refusal worth undoing -- nothing has been spent, so the flag goes
		-- back and the next join with room pays it
		data.WasInvited = nil
		Remotes.Notify:FireClient(player, {
			kind = "error",
			message = "Your welcome pet is waiting -- your pet inventory is full!",
		})
		return
	end

	Remotes.Notify:FireClient(player, {
		kind = "inviteReward",
		message = "Welcome! You received an exclusive pet for joining a friend!",
	})
	-- THE PUSH WAS MISSING. Without it the pet is in the save but not on the client, so the Pets
	-- panel stays a card short until something unrelated replicates -- which for a player who has
	-- just been TOLD they were given a pet reads as the reward not arriving.
	PlayerDataService.PushToClient(player)

	-- Record for the inviter, wherever they are.
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

--- The inviter's half: whatever accumulated in their inbox while they were away.
local function collectInbox(player)
	local data = awaitData(player)
	if not data then return end

	local inbox
	pcall(function()
		inbox = InviteInbox:GetAsync(tostring(player.UserId))
	end)
	if type(inbox) ~= "table" or #inbox == 0 then return end

	local paidList = data.InvitesPaid or {}
	local granted, deferred = 0, false

	for _, joinedId in ipairs(inbox) do
		if table.find(paidList, joinedId) then
			-- already settled on an earlier join; nothing owed
		elseif #paidList >= (GameConfig.InviteMaxPaid or 5) then
			-- at the lifetime cap -- this entry is never going to be paid, so it is not deferred
		elseif grantInvitePet(data) then
			table.insert(paidList, joinedId)
			granted += 1
		else
			-- BAG FULL. Not recorded and not thrown away: the inbox is left alone below so the
			-- same entry is still there next time. The old version cleared the inbox
			-- unconditionally at the end, which turned a full bag into invites lost for good.
			deferred = true
			break
		end
	end

	data.InvitesPaid = paidList

	if granted > 0 then
		Remotes.Notify:FireClient(player, {
			kind = "inviteReward",
			message = "An invited friend joined! You received " .. granted .. " exclusive pet(s)!",
		})
		PlayerDataService.PushToClient(player)
	end
	if deferred then
		Remotes.Notify:FireClient(player, {
			kind = "error",
			message = "More invite pets are waiting -- your pet inventory is full!",
		})
		return
	end

	pcall(function() InviteInbox:RemoveAsync(tostring(player.UserId)) end)
end

-- EXACTLY ONCE PER PLAYER PER SERVER. Both halves below yield for up to ten seconds waiting on the
-- save, so two overlapping runs for the same player would each read `WasInvited` as false and each
-- grant a pet. That overlap is reachable: `Init` connects `PlayerAdded` and then sweeps the players
-- already here, and somebody can join between those two lines.
local handled = {}

local function onJoin(player)
	if handled[player.UserId] then return end
	handled[player.UserId] = true
	local joinData = player:GetJoinData()
	local inviterId = tonumber(joinData and joinData.LaunchData or "")
	-- `inviterId ~= player.UserId` is the whole validation the launch data gets: it is player-
	-- supplied, and the only thing it can buy is a pet for somebody, so the one case worth blocking
	-- is inviting yourself.
	if inviterId and inviterId ~= player.UserId then
		payJoiner(player, inviterId)
	end
	collectInbox(player)
end

function InviteRewardService.Init()
	Players.PlayerAdded:Connect(onJoin)

	-- ALREADY HERE WHEN THIS RAN, and that is not a rare case: `ServerMain` reaches this line after
	-- `ZoneBuilder.Build()` has put the whole map down, which is seconds. `PlayerAdded` does not
	-- fire retroactively, so without this sweep the first player on every server -- and the solo
	-- player in every Studio test -- never had their launch data read and never collected their
	-- inbox. Same fault, same shape, as the one `PlaytimeGiftService.Init` carries a note about.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onJoin, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		handled[player.UserId] = nil
	end)
end

return InviteRewardService
