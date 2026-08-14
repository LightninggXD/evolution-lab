--[[
	AnnounceService -- the one place the server decides that something is worth telling the room
	about (Phase 6.2).

	Right now it does one thing: a Legendary hatch fires `Remotes.RarityBeam` at every client, and
	`RarityBeam.client` draws the pillar. That is deliberately more machinery than one FireAllClients
	needs, because of what is queued behind it.

	=========================================================================================
	WHY THIS IS A SERVICE AND NOT THREE LINES IN PetService
	=========================================================================================
	Roadmap 6.2 is paired with 5.4, cross-server announcements, which is blocked only on a published
	place: `MessagingService` cannot be exercised from Studio at all -- there is no second server for
	a message to arrive at. When it unblocks, 5.4 is a `PublishAsync` inside `Broadcast` below and a
	`SubscribeAsync` that calls the same function. That is one edit in one file, and no publish site
	has to learn what a topic is.

	The other reason is that "what counts as an announcement" is a policy, and policy that lives at
	the call site gets copied. There will be a second publisher (a Colosseum boss kill is the one 5.4
	names) and a third, and each one deciding for itself what is rare enough is how a feature ends up
	firing on Uncommons.

	=========================================================================================
	THE RATE LIMIT IS THE LOAD-BEARING PART
	=========================================================================================
	Auto Hatch buys twice a second and never stops. A Legendary is a 0.5% roll before luck, and luck
	reaches +385 points in the worst honest case measured in 2.12 -- so a full server of auto-hatchers
	is a steady trickle of these, not the once-an-hour event the odds suggest at a glance. Without a
	cooldown, one player standing on a podium with a Lucky pass could hold a permanent 420-stud
	column over their own head, which stops being a celebration and becomes scenery.

	The cooldown is PER PLAYER rather than per server: two different people getting a Legendary in the
	same second is exactly the moment worth showing, while the same person doing it twice in four
	seconds is the Auto Hatch loop. The client has its own `MAX_ACTIVE` cap on top; neither is
	sufficient alone.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local AnnounceService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- seconds between two beams from the same player, see the header
local PLAYER_COOLDOWN = 6

-- PER PLAYER **AND PER KIND**, not per player alone. With one publisher the distinction did not
-- exist; with two it decides whether a Godly mutation can eat the Legendary hatch that happened
-- four seconds earlier. They are different events and neither is the other's spam, so they hold
-- separate clocks -- the thing the cooldown exists to stop is the SAME event repeating, which is
-- the Auto Hatch loop described above.
local lastBeam = {}

local function onCooldown(player, kind)
	local key = player.UserId .. "|" .. kind
	local now = os.clock()
	local last = lastBeam[key]
	if last and now - last < PLAYER_COOLDOWN then return true end
	lastBeam[key] = now
	return false
end

local function remote()
	-- created on demand, like every remote added since the place was last saved by hand
	local r = Remotes:FindFirstChild("RarityBeam")
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = "RarityBeam"
		r.Parent = Remotes
	end
	return r
end

-- The one send. 5.4 adds a MessagingService PublishAsync beside this line and a SubscribeAsync that
-- calls straight back into it with `position` swapped for the receiving server's own landmark.
function AnnounceService.Broadcast(payload)
	remote():FireAllClients(payload)
end

-- ============================================================================
-- PUBLISHERS
-- ============================================================================

-- Called on every hatch, not only on the rare ones: the rarity test belongs here, with the rest of
-- the policy, and a caller that has to ask first is a caller that can forget to.
function AnnounceService.PetHatched(player, petDef)
	return AnnounceService.PetObtained(player, petDef, "HATCH")
end

-- Same policy, different verb. 11.6 made a pet obtainable by killing something, and "LEGENDARY
-- HATCH!" over a creature that was never in an egg is the sort of small wrongness that makes a
-- player distrust the rest of the text. Everything that matters -- the rarity gate, the per-player
-- cooldown, the "no position, no beam" rule -- stays in one body, because that is the whole reason
-- this module exists; only the word changes.
function AnnounceService.PetObtained(player, petDef, verb)
	if not player or not petDef then return end
	if not GameConfig.IsBeaconRarity(petDef.rarity) then return end

	-- The beam is a thing that happens in the world, so it needs somewhere to happen. A player whose
	-- character is between respawns has no position and gets no beam -- silently, because there is
	-- nothing wrong: they still got the pet, and the card that names it comes from HatchReveal.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Checked AFTER the position test on purpose: a hatch that cannot be drawn must not spend the
	-- cooldown that the next one, which can be, is going to need.
	if onCooldown(player, "hatch") then return end

	local rarity = GameConfig.GetRarity(petDef.rarity)
	AnnounceService.Broadcast({
		kind = "hatch",
		position = root.Position,
		rarity = petDef.rarity,
		-- Both lines are composed here rather than on the client, so that when 5.4 sends this same
		-- payload between servers the receiving client needs no second code path to phrase it.
		headline = ("%s %s!"):format(rarity.name:upper(), verb or "HATCH"),
		subline = ("%s got %s %s"):format(player.DisplayName, petDef.emoji or "", petDef.name or "a pet"),
	})
end

-- THE SECOND PUBLISHER (Phase 12), and the first that is not a pet. The rarity gate lives at the
-- call site for this one rather than here, because "rare enough to announce" is a property of the
-- Splicer's own ladder (`GameConfig.Splicer.announceMinIndex`) and this module has no business
-- knowing where Mythic sits in it -- what belongs here is the cooldown, the position rule and the
-- wording, which is everything below.
--
-- `color` is passed EXPLICITLY. Mutation names -- Mythic, Secret, Godly -- are not pet rarities,
-- so the client's `GetRarity` fallback would paint the rarest roll in the game Common grey.
function AnnounceService.MutationRolled(player, mutation)
	if not player or not mutation then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if onCooldown(player, "mutation") then return end

	AnnounceService.Broadcast({
		kind = "mutation",
		position = root.Position,
		color = mutation.color,
		headline = ("%s MUTATION!"):format(mutation.name:upper()),
		subline = ("%s spliced %s at the DNA Splicer"):format(player.DisplayName, mutation.name),
	})
end

function AnnounceService.Init()
	remote()
	Players.PlayerRemoving:Connect(function(player)
		-- keyed per (player, kind) now, so the whole player's set has to go
		local prefix = player.UserId .. "|"
		for key in pairs(lastBeam) do
			if key:sub(1, #prefix) == prefix then
				lastBeam[key] = nil
			end
		end
	end)
end

return AnnounceService
