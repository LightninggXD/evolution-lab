local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)
local ZoneBuilder = require(script.Parent.ZoneBuilder)

local Players = game:GetService("Players")

local ZoneService = {}

-- ===== TRAVEL =====
-- Every teleport in the game goes through `travel` below rather than writing HumanoidRootPart.CFrame
-- directly. The reason is StreamingEnabled: the zone strip is 12,000 studs long and a player who is
-- moved across it arrives *before* the destination has streamed to their client. What they saw was
-- a grey void that filled in around them over the next second or two -- "it just passes through"
-- rather than "I went somewhere".
--
-- So the move is now a handshake:
--   1. freeze the character and tell the client to cover the screen
--   2. the client calls Player:RequestStreamAroundAsync on the destination and answers when the
--      region is in
--   3. only then does the character actually move
--   4. the client holds the cover until there is ground under the player, then wipes
--
-- Freezing matters as much as the cover: without it a player mid-jump keeps their velocity across
-- the move, and with the floor not yet streamed they fall straight through the world.
local TRAVEL_TIMEOUT = 8

-- created on demand so a place that has never run this code still works -- the rest of the Remotes
-- folder is saved instances, and a missing one here would be a hard error at the first gate
local function ensureRemote(name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = Remotes
	return ev
end

local TransitionRemote = ensureRemote("ZoneTransition")
local ReadyRemote = ensureRemote("ZoneTransitionReady")

-- [player] = the token the server is currently waiting on; the client echoes it back so a stale
-- reply from an abandoned transition cannot release the next one early
local awaitedToken = {}
local clientReady = {}
local travelToken = 0

ReadyRemote.OnServerEvent:Connect(function(player, token)
	if awaitedToken[player] and awaitedToken[player] == token then
		clientReady[player] = true
	end
end)

-- ONE TRAVEL AT A TIME PER PLAYER, and the reason is a permanent softlock rather than tidiness.
--
-- `travel` remembers whether the root part was anchored, anchors it, waits up to TRAVEL_TIMEOUT
-- for the client, then restores what it remembered. Two overlapping calls -- a player clicking a
-- second zone in the menu before the first has finished, which is what an impatient player does
-- every time -- means the second one captures `wasAnchored = true`, because the first one set it.
-- It then dutifully restores that: the player is anchored in place for the rest of the session
-- with no way out but rejoining.
local travelling = {}   -- [player] = true while a transition is in flight

local function travel(player, targetCFrame, label)
	if travelling[player] then return false end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	travelling[player] = true

	travelToken += 1
	local token = travelToken
	awaitedToken[player] = token
	clientReady[player] = nil

	local wasAnchored = hrp.Anchored
	hrp.Anchored = true

	TransitionRemote:FireClient(player, {
		phase = "start",
		token = token,
		name = label.name,
		emoji = label.emoji,
		color = label.color,
		position = targetCFrame.Position,
	})

	local t0 = os.clock()
	while not clientReady[player] and os.clock() - t0 < TRAVEL_TIMEOUT do
		if not player.Parent then break end
		task.wait(0.1)
	end
	awaitedToken[player] = nil
	clientReady[player] = nil

	-- the character can die, respawn or leave while the client is streaming
	character = player.Character
	hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		travelling[player] = nil
		return false
	end

	hrp.CFrame = targetCFrame
	hrp.Anchored = wasAnchored
	travelling[player] = nil
	TransitionRemote:FireClient(player, { phase = "arrived", token = token })
	return true
end

local function labelForZone(zoneKey)
	local zone = GameConfig.GetZoneByKey(zoneKey)
	if zone then
		return { name = zone.name, emoji = zone.emoji, color = zone.accentColor }
	end
	return { name = "Somewhere", emoji = "\u{1F300}", color = Color3.fromRGB(140, 140, 180) }
end

local function hasZone(data, zoneKey)
	for _, k in ipairs(data.UnlockedZones) do
		if k == zoneKey then return true end
	end
	return false
end

-- Checks the player's current evolution stage against all zones and unlocks
-- any newly-reachable ones. Returns a list of newly unlocked zone configs.
function ZoneService.CheckUnlocks(player, data)
	local newlyUnlocked = {}
	for _, zone in ipairs(GameConfig.Zones) do
		if GameConfig.IsZoneUnlocked(zone, data) and not hasZone(data, zone.key) then
			table.insert(data.UnlockedZones, zone.key)
			table.insert(newlyUnlocked, zone)
		end
	end
	if #newlyUnlocked > 0 then
		for _, zone in ipairs(newlyUnlocked) do
			Remotes.Notify:FireClient(player, { kind = "zone", name = zone.name, emoji = zone.emoji })
		end
		PlayerDataService.PushToClient(player)
	end
	return newlyUnlocked
end

-- `fromZoneKey` is the zone the player is leaving. Passing it is what makes you come out of the
-- gate you walked into rather than at a fixed pad on the far side of the platform -- see the note
-- on ZoneBuilder.GetZoneSpawnCFrame. The Zones menu passes nothing and lands you at the zone's
-- front gate instead.
function ZoneService.HandleTeleportRequest(player, zoneKey, fromZoneKey)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if not hasZone(data, zoneKey) then
		-- The gate is a solid sheet now (see ZoneBuilder's PortalGate), so this notification is the
		-- only thing that tells a player why they were stopped -- and "locked" on its own does not
		-- say what to do about it. Name the boss whose door this is, since that is the answer.
		local zone = GameConfig.GetZoneByKey(zoneKey)
		local message = "Zone is locked!"
		if zone then
			local defeated = false
			for _, k in ipairs(data.DefeatedBosses or {}) do
				if k == zone.requiresBossKey then
					defeated = true
					break
				end
			end
			local guard = zone.requiresBossKey and GameConfig.GetZoneByKey(zone.requiresBossKey)
			if data.StageIndex < zone.unlockStageIndex then
				message = "Evolve further to unlock " .. zone.name .. "!"
			elseif guard and guard.boss and not defeated then
				message = "Defeat " .. guard.boss.emoji .. " " .. guard.boss.name .. " to open this gate!"
			end
		end
		Remotes.Notify:FireClient(player, { kind = "error", message = message })
		return
	end
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- the whole CFrame, not just the point: you have to come out of the gate already turned to
	-- look down the street, or you arrive staring sideways at the boundary wall
	local target = ZoneBuilder.GetZoneSpawnCFrame(zoneKey, fromZoneKey or data.CurrentZone)
	-- AFTER the move, not before. `travel` returns false when the body is gone -- the player died
	-- or left mid-transition -- and writing CurrentZone first left the save claiming they were in
	-- a zone they never reached. ReturnToCurrentZone reads exactly this field on every respawn, so
	-- the wrong answer here teleports them somewhere they have never been, on every death.
	if travel(player, target, labelForZone(zoneKey)) then
		data.CurrentZone = zoneKey
		-- FUNNEL STEP 7. Inside the `travel` guard for the same reason the write is: a transition
		-- that failed did not move anybody, and the funnel must not claim it did.
		Telemetry.Funnel(player, "firstZone", data)
	end
end

-- ===== THE EVENT ARENA =====
-- Two extra gates that are not zone-to-zone: the one at the Forest spawn, which leads to the
-- Colosseum, and the one in the arena rim, which leads back. The arena is deliberately NOT a zone
-- -- it has no unlock, no eggs, no creatures and no place in the strip order -- so it never goes
-- into UnlockedZones and `CurrentZone` keeps naming the zone the player actually belongs to. That
-- is what the way home is read from, and it is why walking in never costs a player their place.
local ARENA_KEY = GameConfig.EventArena.key
local RETURN_KEY = "ReturnFromArena"
-- The expedition maps carry their exit gate under `workspace.Zones` precisely so the one-shot scan
-- in Init below finds it. That is also why `ExpeditionService.Init()` runs BEFORE this file's.
local EXPEDITION_RETURN_KEY = "ReturnFromExpedition"

function ZoneService.SendToArena(player)
	local data = PlayerDataService.Get(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (data and hrp) then return end

	-- remembered before the move, so the return gate can put them back exactly where they were
	-- even if they walk in from a zone they later lose access to
	data.EventReturnZone = data.CurrentZone or "Forest"
	local arena = GameConfig.EventArena
	travel(player, ZoneBuilder.GetArenaSpawnCFrame(), { name = arena.name, emoji = arena.emoji, color = arena.accentColor })
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = arena.emoji .. " Welcome to the " .. arena.name .. "!",
	})
end

function ZoneService.SendHomeFromArena(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local home = data.EventReturnZone or data.CurrentZone or "Forest"
	if not hasZone(data, home) then home = "Forest" end
	data.EventReturnZone = nil
	ZoneService.HandleTeleportRequest(player, home, home)
end

-- Roblox only ever respawns at a SpawnLocation, and ZoneBuilder deliberately keeps exactly one
-- (in Forest) because the engine picks between multiple at random. So a player who dies in zone
-- fourteen would wake up at the start of the strip with thirteen platforms to walk back across.
-- Put them back at their own zone's gate the moment the new character exists.
-- ===== EXPEDITIONS =====
-- The same two functions the arena has, and deliberately a SEPARATE pair rather than a shared one
-- taking a key: the two places are entered on different terms (the arena by walking into a gate,
-- an expedition by spending one of two daily runs) and a single generalised function would have to
-- be told which it was on every call anyway. `EventReturnZone` and `ExpeditionReturnZone` are also
-- kept apart so a player who walks from one into the other cannot lose their way home.
--
-- `CurrentZone` IS DELIBERATELY NOT CHANGED, exactly as the arena leaves it alone, and three
-- behaviours fall out of that one property for free: a player who disconnects inside the map loads
-- back into their real zone, `ReturnToCurrentZone` below ejects anyone who dies in there, and
-- nobody ever loses their place in the strip by going on an expedition.
function ZoneService.SendToExpedition(player, cframe, label)
	local data = PlayerDataService.Get(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (data and hrp) then return false end

	-- remembered before the move, for the reason the arena remembers it: the way home has to work
	-- even if they entered from a zone they later lose access to
	data.ExpeditionReturnZone = data.CurrentZone or "Forest"
	return travel(player, cframe, label)
end

function ZoneService.SendHomeFromExpedition(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local home = data.ExpeditionReturnZone or data.CurrentZone or "Forest"
	if not hasZone(data, home) then home = "Forest" end
	data.ExpeditionReturnZone = nil
	ZoneService.HandleTeleportRequest(player, home, home)
end

-- ===== ADVENTURES =====
-- A THIRD PAIR, and the argument against folding all three into one function taking a key is the
-- same one the expedition pair makes above -- plus one that is specific to this feature. An
-- adventure course rewrites the player's WalkSpeed and JumpPower (`AdventureMap`'s header: the
-- geometry is cut against a fixed movement profile, because a stage-one body and a stage-twenty
-- body cannot both be served by one set of gaps), so the way home is the only moment anybody has to
-- put the real numbers back. `AdventureService` owns that call; a shared generic teleport would
-- have to be told which of the three places it was leaving in order to know whether to make it.
--
-- `CurrentZone` is deliberately NOT changed, exactly as the arena and the expedition leave it
-- alone, and the same three behaviours fall out for free -- a disconnect mid-course loads back into
-- the real zone, `ReturnToCurrentZone` ejects anyone who respawns out there, and nobody loses their
-- place in the strip by running an obby.
local ADVENTURE_RETURN_KEY = "ReturnFromAdventure"

function ZoneService.SendToAdventure(player, cframe, label)
	local data = PlayerDataService.Get(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (data and hrp) then return false end

	data.AdventureReturnZone = data.CurrentZone or "Forest"
	return travel(player, cframe, label)
end

function ZoneService.SendHomeFromAdventure(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local home = data.AdventureReturnZone or data.CurrentZone or "Forest"
	if not hasZone(data, home) then home = "Forest" end
	data.AdventureReturnZone = nil
	ZoneService.HandleTeleportRequest(player, home, home)
end

function ZoneService.ReturnToCurrentZone(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local zoneKey = data.CurrentZone
	if not zoneKey or zoneKey == "Forest" then return end
	if not hasZone(data, zoneKey) then return end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	travel(player, ZoneBuilder.GetZoneSpawnCFrame(zoneKey), labelForZone(zoneKey))
end

-- Rebirth's way home, and it is deliberately NOT ReturnToCurrentZone. That one returns early on
-- `zoneKey == "Forest"` because the game's single SpawnLocation is already in Forest, so a respawn
-- there needs no move. But a rebirth has written `CurrentZone = "Forest"` BEFORE it asks to be sent
-- home, while the body is still standing in zone twelve -- so that early return fired on the one
-- path that needs the teleport most, and the most expensive action in the game left the player on
-- ground whose creatures hit for x8.4 at stage 1.
--
-- No Forest branch here, and no respawn timing to protect: it goes straight through the same
-- `travel` handshake, so streaming, the anchor and the transition card all behave exactly as they
-- do for a gate walk.
function ZoneService.SendToZoneSpawn(player, zoneKey)
	local data = PlayerDataService.Get(player)
	if not data then return false end
	zoneKey = zoneKey or data.CurrentZone or "Forest"
	-- a zone the save no longer lists is not a place to be dropped; Forest is always unlocked
	if not hasZone(data, zoneKey) then zoneKey = "Forest" end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	return travel(player, ZoneBuilder.GetZoneSpawnCFrame(zoneKey), labelForZone(zoneKey))
end

function ZoneService.Init()
	-- NO ZoneBuilder.Build() HERE. `ServerMain` builds the world before it inits any service --
	-- it has to, because CreatureService, BossService, LeaderboardService and HubPlaza all place
	-- things relative to geometry that must already exist. This call was a second, redundant pass
	-- that built nothing and only cost a 105,000-part sweep plus a false SOLID_PROPS audit warning
	-- every server start; see the note over ZoneBuilder.Build.

	Remotes.TeleportToZone.OnServerEvent:Connect(function(player, zoneKey)
		if typeof(zoneKey) == "string" then
			ZoneService.HandleTeleportRequest(player, zoneKey)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			-- the HumanoidRootPart exists before the character is parented into the workspace, and
			-- moving it any earlier is silently undone by the spawn placement that follows
			task.wait(0.35)
			ZoneService.ReturnToCurrentZone(player)
		end)
	end)

	-- Wire up the big portal gates ZoneBuilder placed in each zone's walls: walking
	-- into the glowing gate teleports you to its target zone (still gated by unlock state).
	local lastTeleport = {}
	for _, gate in ipairs(workspace.Zones:GetDescendants()) do
		if gate.Name == "PortalGate" then
			local targetKey = gate:GetAttribute("TargetZone")
			gate.Touched:Connect(function(hit)
				local character = hit.Parent
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player or not targetKey then return end
				local now = os.clock()
				if lastTeleport[player] and now - lastTeleport[player] < 1.5 then return end
				lastTeleport[player] = now

				if targetKey == ARENA_KEY then
					ZoneService.SendToArena(player)
				elseif targetKey == RETURN_KEY then
					ZoneService.SendHomeFromArena(player)
				elseif targetKey == ADVENTURE_RETURN_KEY then
					-- REACHED ONLY IF AN ADVENTURE COURSE IS EVER BUILT BEFORE THIS SCAN RUNS, and
					-- today none is: they are built lazily on first entry and `AdventureService`
					-- connects its own gates at build time, in `wireMap`. The branch is here so the
					-- two halves cannot drift -- if 30.6 ever pre-builds a course at Init, the way
					-- home already works instead of silently doing nothing.
					local AdventureService = require(script.Parent.AdventureService)
					AdventureService.HandleLeave(player)
				elseif targetKey == EXPEDITION_RETURN_KEY then
					-- The way out of an expedition map. There is deliberately no matching "in"
					-- branch: an expedition is entered through a ProximityPrompt and a briefing
					-- panel, not by walking into a gate, because it spends one of two daily runs
					-- and that is not something to do by accident. See ExpeditionService.
					local ExpeditionService = require(script.Parent.ExpeditionService)
					ExpeditionService.HandleLeave(player)
				else
					-- the gate knows which zone it belongs to, so the arrival side is unambiguous
					local fromKey = gate:FindFirstAncestorWhichIsA("Model")
					ZoneService.HandleTeleportRequest(player, targetKey, fromKey and fromKey.Name or nil)
				end
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
		awaitedToken[player] = nil
		clientReady[player] = nil
		travelling[player] = nil
	end)
end

return ZoneService
