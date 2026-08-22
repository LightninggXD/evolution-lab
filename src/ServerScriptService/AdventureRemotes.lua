-- AdventureRemotes -- the five doors 30.1 through 30.5 deliberately left unbuilt.
--
-- 30.6 SCOPE, SERVER HALF. Nothing decides anything here. Every handler in this file is a name, a
-- type check and a `pcall` into a function that already exists and already refuses everything it
-- has to refuse -- `AdventureService.HandleEnter` / `HandleLeave`, `AdventureDispatch.Send` /
-- `Claim` / `FinishNow`. A second rule written in this file would be the exact fault
-- `evolution-lab-repointing-a-door` is a standing note about.
--
-- =====================================================================================
-- WHY THE DOORS WERE HELD BACK, AND WHAT CHANGED
-- =====================================================================================
-- `AdventureService`'s header says it plainly: *an entry wired to the client before the panel that
-- explains it exists is a door with no frame -- the client cannot say which pet is going, and the
-- pet is the whole of the luck*. `AdventureUI` is that panel, so the doors open now, and by this
-- point each handler's refusals have already been driven from a probe (30.4, 30.5).
--
-- =====================================================================================
-- ITS OWN FILE, AND ITS OWN SMALL ONE
-- =====================================================================================
-- The owner's rule of 2026-08-22: a big file burns tokens on every read, so a new feature ships as
-- several small modules. Five connections and a cooldown is not a thing to bury at the bottom of a
-- 509-line service -- and keeping them out of `AdventureService` is what lets that file stay the
-- one that owns the COURSE.
--
-- =====================================================================================
-- THE TYPE CHECKS ARE NOT CEREMONY
-- =====================================================================================
-- Anything at all comes down a RemoteEvent. `routeKey` is used as a table index and `petId` is
-- compared with `tostring`, so a table or a userdata reaches `GetAdventure` / `GetPetById` and
-- either indexes wrong or throws inside a handler that was written expecting a string. A `nil`
-- petId is NOT rejected here, deliberately: "no pet chosen" is a real state with its own refusal
-- (`nopet`), and swallowing it silently would turn the one refusal a player can act on into a
-- button that does nothing.
--
-- =====================================================================================
-- THE COOLDOWN IS PER PLAYER AND PER DOOR
-- =====================================================================================
-- Not a rate limit against an exploiter -- the ledger and the slot count are what stop those, and
-- they are on the save. It is against the DOUBLE PRESS, which is a real thing a real player does
-- on a laggy client: `Claim` pays a relic table and `FinishNow` spends 40 Diamonds, and both yield
-- (`PayFinish` pushes and toasts). Two presses inside that window are two entries into a function
-- whose guard has not been written back yet. 0.6 s is long enough to cover a push and short enough
-- that nobody feels it.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")

local AdventureService = require(script.Parent.AdventureService)
local AdventureDispatch = require(script.Parent.AdventureDispatch)

local AdventureRemotes = {}

local COOLDOWN = 0.6

-- [player] = { [remoteName] = os.clock() }
local lastFired = {}

-- Find-or-create rather than a plain index, the note `ExpeditionService` carries: which file loads
-- first is a fact about `ServerMain`'s ordering, and `AdventureState` is created by
-- `AdventureService` for its own outbound pushes. Both sides land on the same instance whichever
-- runs first.
local function ensureRemote(name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

local function throttled(player, name)
	local now = os.clock()
	local seen = lastFired[player]
	if not seen then
		seen = {}
		lastFired[player] = seen
	end
	if seen[name] and now - seen[name] < COOLDOWN then return true end
	seen[name] = now
	return false
end

-- One shape for all five. `handler` is called only once the arguments have survived the checks, and
-- it is called inside a `pcall` so a throw in one player's claim cannot take the connection down for
-- everybody -- the failure mode `ExpeditionService.Init` guards the same way.
--
-- =====================================================================================
-- IT RETURNS THE HANDLER RATHER THAN MAKING THE CONNECTION, AND THAT IS FOR THE LINT
-- =====================================================================================
-- This used to be `connect(name, handler)`, which did `ensureRemote(name).OnServerEvent:Connect`
-- with `name` as a PARAMETER. `tools/luaremotes.py` cannot follow that -- its own docstring says so:
-- it resolves a remote through one local or one find-or-create helper, never through a name that is
-- only known at run time. So the moment 30.6's client started firing these five, the lint reported
-- all five as *"a client fires it and NO SERVER LISTENS"* -- five false findings standing in front
-- of the one shape that tool exists to catch, which is a door that genuinely has no other side.
--
-- Written this way the literal name sits next to `.OnServerEvent` at each call site, which is the
-- form the tool reads, and NOTHING about the guarantee changes: the cooldown, both type checks and
-- the pcall are still in one place and still cover all five. The cost is the name appearing twice
-- per door, and that repetition is the part the lint is actually reading.
local function guard(name, handler)
	return function(player, a, b)
		if throttled(player, name) then return end
		if a ~= nil and type(a) ~= "string" then return end
		if b ~= nil and type(b) ~= "string" then return end
		local ok, err = pcall(handler, player, a, b)
		if not ok then
			warn(("[AdventureRemotes] %s failed for %s: %s"):format(name, player.Name, tostring(err)))
		end
	end
end

function AdventureRemotes.Init()
	-- `AdventureEnter` and `AdventureSend` take (routeKey, petId); the other three take (petId).
	-- The pet is second on both of the two-argument doors so the ONE `guard` above can check them
	-- positionally without knowing which door it is wiring.
	ensureRemote("AdventureEnter").OnServerEvent:Connect(
		guard("AdventureEnter", function(player, routeKey, petId)
			AdventureService.HandleEnter(player, routeKey, petId)
		end))

	ensureRemote("AdventureSend").OnServerEvent:Connect(
		guard("AdventureSend", function(player, routeKey, petId)
			AdventureDispatch.Send(player, routeKey, petId)
		end))

	ensureRemote("AdventureClaim").OnServerEvent:Connect(
		guard("AdventureClaim", function(player, petId)
			AdventureDispatch.Claim(player, petId)
		end))

	ensureRemote("AdventureFinishNow").OnServerEvent:Connect(
		guard("AdventureFinishNow", function(player, petId)
			AdventureDispatch.FinishNow(player, petId)
		end))

	-- LEAVING IS A DOOR TOO, and it is not decoration: a course has a `PortalGate` you can walk back
	-- into, but a player who has fallen behind it -- or simply cannot find it on a 5-section course
	-- -- has no other way home, and the game's single SpawnLocation is 4,000 studs away. The run
	-- capsule's LEAVE button fires this. `HandleLeave` refuses anybody not on a course.
	ensureRemote("AdventureLeave").OnServerEvent:Connect(
		guard("AdventureLeave", function(player)
			AdventureService.HandleLeave(player)
		end))

	Players.PlayerRemoving:Connect(function(player)
		lastFired[player] = nil
	end)

	print("[AdventureRemotes] 5 doors open")
end

return AdventureRemotes
