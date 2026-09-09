--[==[
	PartyService -- who is playing WITH whom, and the one bonus that is paid for standing together
	(22.5).

	===== THE ROW =====

	22.5: *"Party support -- up to six friends land in one server; give a party a visible treatment
	and a shared bonus."*

	**The first clause was already true and is a measurement, not a build.** This place is a
	60-slot server (`Players.MaxPlayers = 60`, checked 2026-09-09), and the thing that lands friends
	in the same one is the platform's own invite -- `SocialService:PromptGameInvite`, which
	`FriendInviteButton` has called since 22.2, with `InviteRewardService` paying both sides for the
	join. Six friends fitting in one server needed nothing from this file. The treatment and the
	bonus are what it owed.

	===== WHY A PARTY IS NOT THE FRIENDS-IN-SERVER BONUS AGAIN =====

	`FriendBonusService` pays for who is LOGGED IN: two friends at opposite ends of a twenty-zone
	strip who never see each other are paid the same +5% as two standing shoulder to shoulder. This
	pays only for members **within `GameConfig.PartyRadiusStuds` of you right now**, so it costs
	something to hold, and it is open to strangers -- which a friendship test can never be. The two
	multiply; a party of friends gets both. See the note over the constants in `GameConfig/Rewards`.

	===== THE MODEL =====

	One flat table of parties per server, keyed by a rising id, plus `partyOf[userId]`. A party has
	a leader only so that it has a name (`Ana's party`); nothing is gated on being one. Membership
	is NOT saved and must never be: a party is a fact about right now, and a save field would put a
	player back in a party of people who logged off in June -- the same argument
	`FriendBonusService` makes in its own first paragraph.

	Everything a client needs to DRAW a party is stamped on the `Player` as attributes -- `PartyId`,
	`PartyColor`, `PartyName`, `PartyCount`, `PartyNear`, `PartyPct`. Attributes replicate to every
	client on their own, so there is no remote here at all and no join handshake: `PartyFlair` on
	each machine draws every party it can see, including one it is not in.

	===== THE ONE SEAM, AND IT IS DELIBERATE =====

	`PartyService.PositionOf(userId)` is a FIELD on this table, not a local function, for the reason
	22.1's verification recorded: a feature that needs a second player cannot be tested in a solo
	Studio session unless something in it can be stood in for. Overriding this one function lets a
	probe put a synthetic member 30 studs away and drive the REAL `NearbyCount`, the REAL
	`GetIncomeMult` and the REAL client. It has exactly one production implementation, below.
]==]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)

local PartyService = {}

-- [id] = { id, colour, name, leader (userId), members = { userId, ... } }
local parties = {}
-- [userId] = id
local partyOf = {}
local nextId = 1
local nextColour = 1

--- Where a member is, or nil if they are not standing anywhere yet. THE SEAM -- see the header.
function PartyService.PositionOf(userId)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function nameOf(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return "Someone" end
	return player.DisplayName ~= "" and player.DisplayName or player.Name
end

-- ============================================================================
-- WHAT THE CLIENTS SEE
-- ============================================================================
-- Stamped on the Player rather than sent, the no-remote trick 11.20's countdown, 5.7's GlobalStats
-- and 7.1's LiveEvents all use: a client that joins late reads the current value for free and there
-- is no handler to answer.
local function stamp(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	local party = parties[partyOf[userId] or 0]
	if not party then
		player:SetAttribute("PartyId", nil)
		player:SetAttribute("PartyColor", nil)
		player:SetAttribute("PartyName", nil)
		player:SetAttribute("PartyCount", nil)
		player:SetAttribute("PartyNear", nil)
		player:SetAttribute("PartyPct", nil)
		return
	end
	player:SetAttribute("PartyId", party.id)
	player:SetAttribute("PartyColor", party.colour)
	player:SetAttribute("PartyName", party.name)
	player:SetAttribute("PartyCount", #party.members)
end

local function stampParty(party)
	for _, userId in ipairs(party.members) do
		stamp(userId)
	end
end

-- ============================================================================
-- THE BONUS
-- ============================================================================
--- How many of `userId`'s party are close enough to count, right now. Excludes the player
--- themselves, so a party of one is worth nothing and the cap is the rest of a full party.
function PartyService.NearbyCount(userId)
	local party = parties[partyOf[userId] or 0]
	if not party then return 0 end
	local mine = PartyService.PositionOf(userId)
	if not mine then return 0 end

	local radius = GameConfig.PartyRadiusStuds
	local n = 0
	for _, other in ipairs(party.members) do
		if other ~= userId then
			local theirs = PartyService.PositionOf(other)
			-- A member who has not spawned, or who is between zones, simply does not count this
			-- second. Nothing is remembered: the bonus is a fact about where people are standing.
			if theirs and (theirs - mine).Magnitude <= radius then
				n += 1
			end
		end
	end
	return n
end

-- ============================================================================
-- JOIN / LEAVE
-- ============================================================================
local function openParty()
	-- The SMALLEST party with a free slot, so pressing the stand fills a half-empty party before
	-- starting a new one. A party of strangers that fills up is the outcome this row wants; six
	-- parties of one are the failure mode of every "create a party" button.
	local best = nil
	for _, party in pairs(parties) do
		if #party.members < GameConfig.PartySize then
			if not best or #party.members < #best.members
				or (#party.members == #best.members and party.id < best.id) then
				best = party
			end
		end
	end
	return best
end

local function disband(party)
	parties[party.id] = nil
end

--- Puts `player` in the smallest open party, or starts one. Returns the party and whether it was
--- created. Idempotent: a player already in a party is left where they are.
function PartyService.Join(player)
	local existing = parties[partyOf[player.UserId] or 0]
	if existing then return existing, false end

	local party = openParty()
	local created = false
	if not party then
		local colour = GameConfig.PartyColors[(nextColour - 1) % #GameConfig.PartyColors + 1]
		nextColour += 1
		party = {
			id = nextId,
			colour = colour,
			leader = player.UserId,
			name = nameOf(player.UserId) .. "'s party",
			members = {},
		}
		parties[nextId] = party
		nextId += 1
		created = true
	end

	table.insert(party.members, player.UserId)
	partyOf[player.UserId] = party.id
	stampParty(party)
	return party, created
end

--- Takes `player` out of whatever party they are in. Safe to call for somebody in none.
function PartyService.Leave(player)
	local userId = typeof(player) == "number" and player or player.UserId
	local party = parties[partyOf[userId] or 0]
	partyOf[userId] = nil
	stamp(userId)
	if not party then return nil end

	for i, member in ipairs(party.members) do
		if member == userId then
			table.remove(party.members, i)
			break
		end
	end

	if #party.members == 0 then
		disband(party)
		return nil
	end

	-- The leader leaving passes the name on rather than dissolving the party underneath five
	-- people. Nothing is gated on being the leader, so this is only ever a label.
	if party.leader == userId then
		party.leader = party.members[1]
		party.name = nameOf(party.leader) .. "'s party"
	end
	stampParty(party)
	return party
end

function PartyService.GetParty(userId)
	return parties[partyOf[userId] or 0]
end

--- Every live party, newest last. The stand's board reads this.
function PartyService.All()
	local out = {}
	for _, party in pairs(parties) do
		table.insert(out, party)
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

function PartyService.MemberNames(party)
	local names = {}
	for _, userId in ipairs(party.members) do
		table.insert(names, nameOf(userId))
	end
	return names
end

-- ============================================================================
-- INIT
-- ============================================================================
function PartyService.Init()
	-- No join handler at all, and that is not an oversight: a player arrives in no party, which is
	-- the state a Player with no attributes already represents. (The already-here `PlayerAdded`
	-- trap that has bitten ten files in this repo needs a handler to bite.)
	Players.PlayerRemoving:Connect(function(player)
		PartyService.Leave(player)
	end)

	-- The live half of the treatment: how many of your party are close enough to be paying you,
	-- republished once a second. Same cadence and the same argument as the arena countdown -- the
	-- number is drawn as a whole percent and nothing needs to be smoother than that.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				if partyOf[player.UserId] then
					local near = PartyService.NearbyCount(player.UserId)
					player:SetAttribute("PartyNear", near)
					player:SetAttribute("PartyPct", GameConfig.GetPartyBonusPct(near))
				end
			end
		end
	end)
end

return PartyService
