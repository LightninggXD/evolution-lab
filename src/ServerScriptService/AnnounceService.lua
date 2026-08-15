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

	=========================================================================================
	THE KILL FEED (Phase 12.14) IS WORDS, NOT COLUMNS
	=========================================================================================
	The publishers below the pet/mutation pair -- an Apex going down, a zone boss falling for the
	first time, a rebirth, the Colosseum giant -- all send a payload with NO `position`, which
	`RarityBeam.client` renders as a HUD toast and nothing else. That is a decision, not a shortcut.

	A 420-stud pillar is the game's way of saying "a 1-in-50,000 just happened over there". These
	four are frequent by comparison: an Apex respawns every 120 s and there are four per zone, every
	player clears twenty bosses, the Colosseum runs every 30 minutes. Beaming them would turn the
	beam into scenery, which is the exact failure the rate limit above exists to prevent -- and it
	would do it by making the beam MEAN less rather than by drawing too many of them.

	The second reason is that a kill feed has to work for events with no place in this server at all.
	5.4's cross-server message has no position by construction, and everything below is already in
	the shape that arrives in.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local AnnounceService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- seconds between two beams from the same player, see the header
local PLAYER_COOLDOWN = 6

-- ...and the kinds that want a different one. A hatch or a splice is a moment; an Apex kill is a
-- FARM -- four per zone on a 120 s respawn, so one player working a terrace produces one every
-- 30 seconds forever. Six seconds would let that single player hold the feed. Boss firsts and
-- rebirths are naturally rare (twenty and four per run) and keep the default: their cooldown is
-- there to catch a double-fire, not a loop.
local KIND_COOLDOWN = {
	apex = 45,
}

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
	if last and now - last < (KIND_COOLDOWN[kind] or PLAYER_COOLDOWN) then return true end
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

local TOPIC = "GlobalAnnouncements_v1"

-- The one send. Broadcasts locally, and publishes to MessagingService for other servers.
function AnnounceService.Broadcast(payload, fromMessaging)
	remote():FireAllClients(payload)

	if not fromMessaging and type(payload) == "table" and (payload.kind == "hatch" or payload.kind == "mutation" or payload.kind == "boss" or payload.kind == "rebirth") then
		task.spawn(function()
			pcall(function()
				local crossPayload = {
					kind = payload.kind,
					headline = payload.headline,
					subline = payload.subline,
					rarity = payload.rarity,
					color = payload.color and { payload.color.R, payload.color.G, payload.color.B } or nil,
					jobId = game.JobId,
				}
				local json = HttpService:JSONEncode(crossPayload)
				MessagingService:PublishAsync(TOPIC, json)
			end)
		end)
	end
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

-- ============================================================================
-- THE KILL FEED (Phase 12.14)
-- ============================================================================
-- Three publishers that are not about an item at all, and the first ones with no position -- see
-- the header block for why that is the design rather than a limitation. Everything they have in
-- common lives here: no character is required (a rebirth rebuilds the body, and a payload that had
-- to wait for it would arrive after the reset it is announcing), the cooldown is the shared one,
-- and the wording is composed server-side so 5.4 needs no second phrasing path.

-- Trailing zeros off a multiplier: "x3.5" and "x4", never "x3.50" or "x4.00". A rebirth's reward is
-- the one number the card exists to show, and a player reads a tidy one as a rounder promise.
local function fmtMult(n)
	if type(n) ~= "number" or n ~= n then return "1" end
	local s = ("%.2f"):format(n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s
end

-- THE APEX. Called at the drop-roll site rather than at the death, because that is the one place
-- that already knows the tier, the zone and the label -- and because the pet drop announced beside
-- it (PetObtained, above) is the other half of the same moment.
function AnnounceService.ApexKilled(player, label, zone)
	if not player or type(label) ~= "string" then return end
	if onCooldown(player, "apex") then return end

	AnnounceService.Broadcast({
		kind = "apex",
		-- the Apex plate's own colour (CreatureService's TIERS.Apex.plateColor), so the feed line and
		-- the crown over the creature's head are recognisably the same thing
		color = UITheme.Color.Purple,
		headline = "\u{1F451} APEX SLAIN!",
		subline = ("%s brought down %s in %s"):format(
			player.DisplayName, label, zone and zone.name or "the wild"),
	})
end

-- THE BOSS, AND ONLY SOMETIMES. Two gates, both here rather than at the call site:
--
-- `firstTime` cannot be derived here -- only the caller holds the before-state of `markDefeated`,
-- which is idempotent per zone and so has forgotten by the time it returns. It is passed in.
--
-- The zone floor CAN be derived and therefore is. Every player kills all twenty bosses, so an
-- unfiltered feed would be a wall of Forest clears from whoever joined a minute ago; the last six
-- zones are where a first clear is genuinely worth a room's attention. `GetZoneIndex` returns 1 for
-- a key it does not know, which fails CLOSED here -- an unrecognised zone announces nothing.
local BOSS_MIN_ZONE = 15

function AnnounceService.BossKilled(player, boss, zoneKey, firstTime)
	if not player or not boss or not firstTime then return end
	if GameConfig.GetZoneIndex(zoneKey) < BOSS_MIN_ZONE then return end
	if onCooldown(player, "boss") then return end

	local zone = GameConfig.GetZoneByKey(zoneKey)
	AnnounceService.Broadcast({
		kind = "boss",
		color = UITheme.Color.Orange,
		headline = ("%s %s DEFEATED!"):format(boss.emoji or "\u{1F480}", (boss.name or "The boss"):upper()),
		subline = ("%s cleared %s for the first time"):format(
			player.DisplayName, zone and zone.name or "a late zone"),
	})
end

-- THE REBIRTH. The hardest voluntary thing in the game and, until now, the quietest: it wiped a
-- climb, a zone list and a whole skin collection and nobody but the player ever knew. No zone gate
-- and no rarity gate -- there are only four of these per account, ever.
function AnnounceService.Rebirthed(player, rebirths, damageMult)
	if not player then return end
	if onCooldown(player, "rebirth") then return end

	AnnounceService.Broadcast({
		kind = "rebirth",
		color = UITheme.Color.Gold,   -- the shrine's own gold
		headline = ("\u{2728} REBIRTH %d!"):format(rebirths or 1),
		subline = ("%s started over -- x%s damage forever"):format(
			player.DisplayName, fmtMult(damageMult)),
	})
end

-- THE TOP ENCHANT (13.4). Positionless by the same rule as the four above: an enchant is bought at
-- a button in a panel, so there is no place in the world for a column to stand -- and unlike a
-- hatch, the thing that happened is a number on a pet nobody else can see. Words are the whole of
-- what is shareable about it.
--
-- GATED ON THE LADDER'S OWN `announce` FLAG, not on a rung name spelled out here. That is the
-- `IsBeaconRarity` pattern: the table that knows which rungs are rare is the table that decides,
-- so a future rung is a row in GameConfig and nothing in this file.
function AnnounceService.EnchantRolled(player, petDef, enchant)
	if not player or not enchant or not enchant.announce then return end
	if onCooldown(player, "enchant") then return end

	AnnounceService.Broadcast({
		kind = "enchant",
		color = enchant.color,
		headline = ("\u{2728} %s ENCHANT!"):format(enchant.name:upper()),
		subline = ("%s enchanted %s -- x%.2f damage share"):format(
			player.DisplayName, petDef and petDef.name or "a pet", enchant.mult),
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

	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local ok, data = pcall(function()
					return HttpService:JSONDecode(message.Data)
				end)
				if ok and type(data) == "table" and data.jobId ~= game.JobId then
					local col = nil
					if type(data.color) == "table" and #data.color == 3 then
						col = Color3.new(data.color[1], data.color[2], data.color[3])
					end
					AnnounceService.Broadcast({
						kind = data.kind,
						headline = data.headline,
						subline = data.subline,
						rarity = data.rarity,
						color = col,
					}, true)
				end
			end)
		end)
	end)
end

return AnnounceService
