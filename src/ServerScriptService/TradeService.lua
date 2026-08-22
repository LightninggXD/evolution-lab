--[[
	TradeService -- the server core of player-to-player trading (Phase 8.2, 8.3, 8.4, and the
	server half of 8.1 and 8.5).

	=========================================================================================
	THIS IS FULLY WIRED AND REACHABLE. The paragraph that used to stand here said the opposite.
	=========================================================================================
	`ServerMain` requires this file at line 34 and calls `Init()` at line 135; `Init` creates all
	seven remotes -- TradeUpdate, TradeInvite, TradeRequest, TradeAccept, TradeCancel,
	TradeSetOffer, TradeConfirm -- and connects the five inbound ones. The client half is
	`ReplicatedStorage.Modules.HUD.TradePanel`, required by MainUI. Row 8.6 is `[x]`.

	The old text was accurate when it was written: Phase 8 was gated behind "do not start until the
	game is live and stable", and only the server core -- the exploit surface the gate is actually
	about -- existed, because that is the half provable against two save tables on one server with
	no second client. The gate was opened when the place was published and the rest was built. The
	comment was simply never updated, and it went on telling every reader the feature was inert.

	Corrected 2026-08-19 (roadmap 19.10), together with the identical claim in ROADMAP's Phase 8
	preamble. WHAT IS STILL TRUE: there is no HUD tile for trading. The only door is clicking
	another player in the world, which is roadmap row 21.1 -- shipped and undiscoverable is a
	different problem from unwired, and worth keeping the two apart.

	=========================================================================================
	ONLY PETS, AND WHY NOT CURRENCY
	=========================================================================================
	DNA is scaled to the holder's stage everywhere in this game (GameConfig.ScaleReward exists for
	exactly that), so "10,000 DNA" is not a quantity two players can agree on -- it is worth a
	different number of clicks to each of them, and the whole economy assumes it. Diamonds and
	Evolution Shards are the deliberately un-inflatable currencies; making them tradeable turns
	every one of them into a bot's day job. A pet is the one thing in the save that is a discrete,
	individually-identified object with no exchange rate, which is what makes it tradeable at all.

	=========================================================================================
	WHY DUPLICATION IS STRUCTURALLY IMPOSSIBLE HERE, RATHER THAN GUARDED AGAINST
	=========================================================================================
	Four separate properties, and the argument needs all four:

	1. BOTH PLAYERS ARE ON THIS SERVER. The proximity requirement (8.1) is not only anti-scam --
	   it means one machine holds both save tables, so there is exactly one authority. The entire
	   class of "trade with yourself across two servers" cannot be expressed.

	2. A PET CAN BE IN ONE LIVE TRADE. `reserved[petId]` is a server-wide claim taken when a pet is
	   put in an offer and released on every exit path. Without it a player in two windows can
	   offer the same pet twice and be paid twice for it.

	3. THE SWAP DOES NOT YIELD. Validation and the two table mutations run with no `task.wait`, no
	   `SetAsync` and no event fired between them. Anything that yields mid-swap is a window in
	   which a fuse, a hatch or a second trade can see one pet in two inventories, and Roblox will
	   happily schedule exactly that.

	4. THE SAVE HAPPENS AFTER, NOT DURING. In-memory `Cache` is the authority for a live session
	   and the DataStore is a backup of it, so a failed write cannot duplicate anything -- it can
	   only lose. A crash inside the write window costs the pet rather than copying it, and losing
	   in a system like this is the only acceptable direction to fail in. Both writes are still
	   issued and both are checked; a failure is logged loudly and the 60-second autosave retries
	   from the correct in-memory state.

	=========================================================================================
	LOCK AND RECHECK (8.2), AND WHY THE RECHECK IS NOT PARANOIA
	=========================================================================================
	An offer is a list of pet ids captured when the player picked them. Between that moment and the
	commit the player can fuse (which destroys four pets), buy an egg, tier one up, or rebirth. So
	every id is re-resolved against the owner's CURRENT `data.Pets` at commit time and the trade is
	refused if any of them has gone. The reservation in (2) stops a second TRADE taking the pet; it
	does not stop the owner from destroying it themselves, and nothing should -- a player must not
	be locked out of their own inventory because somebody opened a window at them.

	=========================================================================================
	THE ANTI-SCAM RULE THAT LIVES ON THE SERVER (8.5)
	=========================================================================================
	The oldest trade scam in the genre is: both sides confirm, then the scammer swaps the good item
	for a worthless one in the half-second before commit. `SetOffer` therefore clears BOTH
	confirmations, unconditionally, on every change to either side. It is three lines and it is the
	entire defence; the 3-second hold and the summary card are decoration on top of it.
--]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)
local AnnounceService = require(script.Parent.AnnounceService)
-- 30.7: the offer grammar, shared with `TradePanel` so the two halves cannot disagree about what a
-- relic line looks like, and the policy check Roblox requires in front of the whole feature.
local TradeItems = require(RS.Modules.TradeItems)
local TradePolicy = require(script.Parent.Systems.TradePolicy)

local TradeService = {}

-- Ten a side. Not a storage limit -- a REVIEWABILITY limit: 8.5's summary card exists so a player
-- can read what they are giving away, and a window holding forty pets is a window nobody reads.
-- 30.7: it moved into `TradeItems` with the rest of the grammar, and it now counts LINES rather
-- than pets -- a relic line can be a stack of four, and "Forest Shard x4" is one thing to read.
local MAX_OFFER = TradeItems.MaxLines
-- Both characters must be within this of each other, at the request AND at the commit. It is the
-- anti-scam half of 8.1 (a stranger cannot open a window at you from across the map) and the
-- reason property 1 above holds.
--
-- It moved into GameConfig when the trade player picker was built (15.11): the picker labels every
-- player in the server "in range" or "walk closer", so the client needs the same number this file
-- enforces. Same move MAX_PETS made below, for the same reason.
local PROXIMITY_STUDS = GameConfig.TradeProximityStuds
-- Cheap spam control on top of the per-minute cap: one request every few seconds per player.
local REQUEST_COOLDOWN = 4
local TRADES_PER_MINUTE = 6
-- The same ceiling PetService enforces on a hatch, and now literally the same number: it moved into
-- GameConfig (30, down from 600 -- see the note there). This used to be a private copy on the
-- grounds that these two services must not require each other, which was true and beside the point,
-- since both already require GameConfig. All the duplication ever bought was a way for a trade to
-- keep accepting pets after a hatch had started refusing them.
local MAX_PETS = GameConfig.MaxOwnedPets
-- A window nobody finishes has to expire, or its reservations are held until the server restarts.
local SESSION_TIMEOUT = 180

local logStore = DataStoreService:GetDataStore("EvolutionLab_TradeLog_v1")

-- [tradeId] = session
local sessions = {}
-- [userId] = tradeId -- one live trade per player, enforced here rather than searched for
local sessionOf = {}
-- [petId] = tradeId -- property 2 above
local reserved = {}
-- [userId] = { os.clock() ... } -- the rate limiter's sliding window
local recent = {}
local lastRequest = {}

-- The last N trades this server committed, for support and for a test to read. The DataStore copy
-- is the durable one; this is what a live investigation looks at without a web call.
TradeService.Log = {}
local LOG_KEEP = 50

-- ============================================================================
-- SMALL PIECES
-- ============================================================================
-- Every message to a client goes through here, resolved BY USER ID rather than held as a Player
-- reference. Two reasons, and the second is the important one: a player who left mid-trade must
-- not error the commit for the one still standing there, and the whole dangerous path below can
-- then be driven in a test against user ids that have no Player object at all.
local function tell(userId, payload)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return false end
	local remotes = RS:FindFirstChild("Remotes")
	local notify = remotes and remotes:FindFirstChild("Notify")
	if not notify then return false end
	notify:FireClient(player, payload)
	return true
end

local function dataOf(userId)
	return PlayerDataService.Cache[userId]
end

local function ensureRemote(name, class)
	class = class or "RemoteEvent"
	local remotes = RS:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = RS
	end
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
	end
	return r
end

-- ABOVE `resolveOfferPets`, AND THAT IS THE FIX, not a tidy-up. It was declared 71 lines lower,
-- which in Lua means the call below it was reading a GLOBAL of the same name -- nil -- so every
-- `pushSession` threw "attempt to call a nil value" and no offer could ever be drawn. Every path
-- in this file that shows or commits a trade goes through here, so nothing worked; and it is
-- invisible to a compile check, to `luastruct.py` and to `luanames.py` alike (the name exists, it
-- is simply not in scope yet). `tools/luascope.py` is the instrument that found it.
local function petIndexById(data, petId)
	for i, pet in ipairs(data.Pets or {}) do
		if pet.id == petId then return i, pet end
	end
	return nil
end

-- RESOLVED FRESH ON EVERY PUSH, and that is what makes the board honest: a pet fused away or a
-- relic spent since the offer was built simply stops being drawn, on both screens, rather than
-- lingering as a card the commit is going to refuse.
--
-- 30.7: it resolves both kinds now, and every card carries `kind` -- the client has to draw them
-- differently and must never have to guess from which fields happen to be present.
local function resolveOffer(userId, offer)
	local data = dataOf(userId)
	if not data then return {} end
	local list = {}
	for _, item in ipairs(offer or {}) do
		if item.kind == TradeItems.RELIC then
			local relic = GameConfig.GetSetRelic(item.key)
			-- Clamped to what is SPARE right now rather than to what was offered: a player who
			-- spends a spare mid-window watches their own card shrink instead of watching a
			-- promise the commit is about to break.
			local spare = GameConfig.GetSpareSetRelics(data, item.key)
			local n = math.min(item.n, spare)
			if relic and n > 0 then
				table.insert(list, {
					kind = TradeItems.RELIC,
					key = relic.key,
					n = n,
					name = relic.name,
					rarity = relic.rarity,
					-- `icon`, NOT `emoji`: it is an `IconLibrary` name and the client resolves it
					-- as an image. Naming the field `emoji` is what would put the literal string
					-- "relic_shard" on a tile.
					icon = relic.icon,
					tint = relic.tint,
					zoneName = relic.zoneName,
					-- THE NAME DOES NOT FIT AND THE HALF THAT SURVIVES IS THE WRONG HALF. A tile is
					-- 56 px: "Forest Shard" truncates to "Forest...", and "Desert Sigil" and
					-- "Desert Shard" then read identically -- photographed 2026-08-22, two tiles
					-- side by side saying "Desert" and "Volcano" for a Sigil and a Core. The ZONE
					-- is already said by the tint, which is the whole reason the sets are tinted,
					-- so the form is what the label has to carry.
					short = (GameConfig.RelicSetForms[relic.order] or {}).name or relic.name,
				})
			end
		else
			local _, pet = petIndexById(data, item.id)
			if pet then
				local def = GameConfig.GetPetDef(pet.key)
				table.insert(list, {
					kind = TradeItems.PET,
					id = pet.id,
					key = pet.key,
					tier = pet.tier or 1,
					name = def and def.name or pet.key,
					rarity = def and def.rarity or "Common",
					emoji = def and def.emoji or "🐾",
				})
			end
		end
	end
	return list
end

local function pushSession(session, stateOverride)
	if not session then return end
	local updateRemote = ensureRemote("TradeUpdate")

	local pA = Players:GetPlayerByUserId(session.a.userId)
	local pB = Players:GetPlayerByUserId(session.b.userId)

	local petsA = resolveOffer(session.a.userId, session.a.offer)
	local petsB = resolveOffer(session.b.userId, session.b.offer)

	local state = stateOverride or session.state

	if pA then
		updateRemote:FireClient(pA, {
			tradeId = session.id,
			state = state,
			partnerName = pB and pB.Name or "Partner",
			partnerUserId = session.b.userId,
			myOffer = petsA,
			partnerOffer = petsB,
			myConfirmed = session.a.confirmed,
			partnerConfirmed = session.b.confirmed,
		})
	end

	if pB then
		updateRemote:FireClient(pB, {
			tradeId = session.id,
			state = state,
			partnerName = pA and pA.Name or "Partner",
			partnerUserId = session.a.userId,
			myOffer = petsB,
			partnerOffer = petsA,
			myConfirmed = session.b.confirmed,
			partnerConfirmed = session.a.confirmed,
		})
	end
end

local function rootOf(userId)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Returns true when the two are close enough, and ALSO true when neither has a character to
-- measure -- which only happens in a test, and refusing there would make the dangerous path
-- untestable while proving nothing about the real one. A live trade always has two characters,
-- because the request that opened it required them.
local function withinReach(userIdA, userIdB)
	local a, b = rootOf(userIdA), rootOf(userIdB)
	if not a or not b then return not (a or b) end
	return (a.Position - b.Position).Magnitude <= PROXIMITY_STUDS
end

local function describe(pet)
	local def = pet and GameConfig.GetPetDef(pet.key)
	if not def then return tostring(pet and pet.key) end
	return ("%s %s %s"):format(def.emoji or "", pet.tier or "Normal", def.name or pet.key)
end

-- The same sentence for a relic line, for the trade log. The count is part of the description
-- because a relic line is a stack: "Forest Shard" and "Forest Shard x6" are different trades and
-- a support investigation reading the log has nothing else to tell them apart by.
--
-- THE GLYPH IS THE ZONE'S, NOT `relic.icon`. A collection relic's `icon` is an `IconLibrary` NAME
-- ("relic_shard") and not an emoji -- the first run of this row's probe printed
-- `relic_shard Forest Shard x2` into the log, which is how the same mistake was caught on the
-- client tile before anybody photographed it. The set carries the zone's emoji.
local function describeRelic(key, n)
	local relic = GameConfig.GetSetRelic(key)
	if not relic then return ("%s x%d"):format(tostring(key), n) end
	local set = GameConfig.RelicSetsByZone[relic.zoneKey]
	return ("%s %s x%d"):format((set and set.emoji) or "", relic.name or key, n)
end

-- ============================================================================
-- THE RATE LIMIT (8.4)
-- ============================================================================
local function underRateLimit(userId)
	local now = os.clock()
	local window = recent[userId]
	if not window then
		window = {}
		recent[userId] = window
	end
	-- drop anything older than a minute, then count what is left
	local kept = {}
	for _, t in ipairs(window) do
		if now - t < 60 then table.insert(kept, t) end
	end
	recent[userId] = kept
	return #kept < TRADES_PER_MINUTE
end

-- Counted on COMPLETION, while `underRateLimit` gates the REQUEST. Two different taps on purpose:
-- REQUEST_COOLDOWN bounds how fast somebody can pester strangers with windows, and this bounds how
-- many trades actually go through -- which is the number a bot farm cares about.
local function noteTrade(userId)
	recent[userId] = recent[userId] or {}
	table.insert(recent[userId], os.clock())
end

-- ============================================================================
-- SESSIONS
-- ============================================================================
local function side(session, userId)
	if session.a.userId == userId then return session.a, session.b end
	if session.b.userId == userId then return session.b, session.a end
	return nil, nil
end

-- ONLY PETS ARE RESERVED, and 30.7 deliberately did not add a second table for relics. A pet is a
-- unique object two windows could name at once; a relic line is a COUNT taken out of one player's
-- pile, and `sessionOf` already allows that player exactly one live window. What protects the count
-- is the recheck at commit -- `GetSpareSetRelics` re-read against the save as it stands at that
-- instant -- which is the same protection a pet has, and the only one that survives the owner
-- spending it themselves in the meantime.
local function releaseReservations(session)
	for _, s in ipairs({ session.a, session.b }) do
		for _, petId in ipairs(TradeItems.PetIds(s.offer)) do
			if reserved[petId] == session.id then reserved[petId] = nil end
		end
	end
end

-- ONE EXIT PATH. Every refusal, cancel, timeout, disconnect and successful commit ends here, so a
-- reservation cannot survive its session -- which would take the pet out of circulation for the
-- rest of the server's life with nothing anywhere reporting why.
local function closeSession(session, reason)
	if not session or session.closed then return end
	session.closed = true
	session.reason = reason
	releaseReservations(session)
	sessions[session.id] = nil
	if sessionOf[session.a.userId] == session.id then sessionOf[session.a.userId] = nil end
	if sessionOf[session.b.userId] == session.id then sessionOf[session.b.userId] = nil end
end

function TradeService.GetSession(userId)
	local id = sessionOf[userId]
	return id and sessions[id] or nil
end

-- ============================================================================
-- 8.1 (SERVER HALF) -- REQUEST AND ACCEPT
-- ============================================================================
-- Returns session, or nil plus a reason string.
--
-- EVERY REFUSAL A PLAYER CAN CAUSE NOW SAYS SO (15.18). The header here used to read "the reason is
-- returned rather than notified, so a test reads the same answer the player would be shown" -- and
-- the second half of that sentence was not true: only the cooldown, the rate limit and the reach
-- check called `tell`, so the four branches above them refused in complete silence. Found on the
-- live two-client run: an invite timed out, leaving a session pending, and every further press of
-- Ask did nothing whatsoever -- no window, no message, nothing to distinguish "the server refused
-- you" from "the button is broken". It cost a run to diagnose from the outside, which is what a
-- player would have to do. `refuse` both tells and returns, so tests still read the same string.
local function refuse(userId, message)
	tell(userId, { kind = "error", message = message })
	return nil, message
end

function TradeService.Request(fromUserId, toUserId)
	if fromUserId == toUserId then return refuse(fromUserId, "You cannot trade with yourself") end
	if not dataOf(fromUserId) or not dataOf(toUserId) then return refuse(fromUserId, "That player is not ready") end
	if TradeService.GetSession(fromUserId) then return refuse(fromUserId, "You are already in a trade") end
	if TradeService.GetSession(toUserId) then return refuse(fromUserId, "They are already in a trade") end

	-- 20.3: TRADE OPENED, counted on the REQUESTER and only once every guard above has passed --
	-- a request refused for self-trading or for an already-open session never opened anything.
	local fromPlayer = Players:GetPlayerByUserId(fromUserId)
	if fromPlayer then Telemetry.Custom(fromPlayer, "TradeOpened") end

	local now = os.clock()
	if lastRequest[fromUserId] and now - lastRequest[fromUserId] < REQUEST_COOLDOWN then
		tell(fromUserId, { kind = "error", message = "Slow down" })
		return nil, "Slow down"
	end
	if not underRateLimit(fromUserId) then
		tell(fromUserId, { kind = "error", message = "Too many trades -- wait a minute" })
		return nil, "Too many trades -- wait a minute"
	end
	if not withinReach(fromUserId, toUserId) then
		tell(fromUserId, { kind = "error", message = "Stand closer to trade" })
		return nil, "Stand closer to trade"
	end

	-- ===== 30.7: ROBLOX'S OWN GATE, IN FRONT OF THE WHOLE FEATURE =====
	--
	-- Both sides, because a trade moves goods in both directions and the receiver is acquiring
	-- exactly as much as the sender is giving. It is here rather than at the commit for two
	-- reasons. `TradePolicy.Allows` CAN YIELD -- only on the path where the join-time fetch failed,
	-- but the commit block must never yield at all, so the check cannot live there. And a window
	-- that opens, fills up and then refuses at the last second is a worse thing to do to somebody
	-- than one that never opens.
	--
	-- The yield is why the two session tests are taken AGAIN below: everything above ran before it,
	-- and a second press arriving during the round trip would otherwise open a second window.
	local okFrom, whyFrom = TradePolicy.Allows(fromUserId)
	if not okFrom then return refuse(fromUserId, whyFrom) end
	local okTo = TradePolicy.Allows(toUserId)
	if not okTo then return refuse(fromUserId, "They cannot trade right now") end
	if TradeService.GetSession(fromUserId) then return refuse(fromUserId, "You are already in a trade") end
	if TradeService.GetSession(toUserId) then return refuse(fromUserId, "They are already in a trade") end

	lastRequest[fromUserId] = now

	local session = {
		id = HttpService:GenerateGUID(false),
		openedAt = os.time(),
		state = "pending",
		a = { userId = fromUserId, offer = {}, confirmed = false },
		b = { userId = toUserId, offer = {}, confirmed = false },
	}
	sessions[session.id] = session
	sessionOf[fromUserId] = session.id
	sessionOf[toUserId] = session.id

	local inviteRemote = ensureRemote("TradeInvite")
	local pFrom = Players:GetPlayerByUserId(fromUserId)
	local pTo = Players:GetPlayerByUserId(toUserId)
	if pTo and pFrom then
		inviteRemote:FireClient(pTo, {
			fromUserId = fromUserId,
			fromName = pFrom.Name,
			tradeId = session.id,
		})
		tell(fromUserId, { kind = "reward", message = ("Trade request sent to %s!"):format(pTo.Name) })
	end

	return session
end

function TradeService.Accept(userId, tradeId)
	local session = sessions[tradeId]
	-- ...and the same for Accept (15.18). "That trade has gone" is the one a player actually meets:
	-- the invite prompt hides itself after 15 seconds, so pressing Accept a moment late used to be
	-- indistinguishable from pressing a dead button.
	if not session or session.closed then return refuse(userId, "That trade has gone") end
	-- only the RECEIVER accepts: the sender accepting their own request would open a window the
	-- other player never agreed to
	if session.b.userId ~= userId then return refuse(userId, "That request is not yours to accept") end
	if session.state ~= "pending" then return refuse(userId, "Already open") end
	session.state = "open"
	pushSession(session, "open")
	return session
end

function TradeService.Cancel(userId, reason)
	local session = TradeService.GetSession(userId)
	if not session then return false end
	pushSession(session, "cancelled")
	closeSession(session, reason or "cancelled")
	for _, s in ipairs({ session.a, session.b }) do
		tell(s.userId, { kind = "error", message = "Trade cancelled" })
	end
	return true
end

-- ============================================================================
-- 8.5 (SERVER HALF) -- THE OFFER, AND THE CONFIRMATION RESET
-- ============================================================================
-- 30.7 ROUTES EVERY REFUSAL HERE THROUGH `refuse`, which is 15.18's fix arriving one function
-- late. `SetOffer`'s reasons were returned to a caller that throws them away -- the remote handler
-- at the bottom of this file ignores the second return -- so a rejected offer did nothing visible
-- whatsoever. That was survivable while the only reachable refusals were "you do not own that pet"
-- (a tampered client) and "unequip that pet first" (which the picker already hides). It stops being
-- survivable now: "that is your only one" is a sentence a normal player meets on their first
-- attempt to trade a relic, and meeting it in silence is a dead button.
function TradeService.SetOffer(userId, items)
	local session = TradeService.GetSession(userId)
	if not session then return refuse(userId, "You are not in a trade") end
	-- covers "pending" (not accepted yet) and "committing" (too late) in one test
	if session.state ~= "open" then return refuse(userId, "The trade is not open") end

	-- The grammar check, and the ONLY place the wire's shape is interpreted. Everything below this
	-- line works on canonical items and never has to ask what type a field is.
	local offered, badShape = TradeItems.Normalise(items)
	if not offered then return refuse(userId, badShape) end
	if #offered > MAX_OFFER then return refuse(userId, ("At most %d things each"):format(MAX_OFFER)) end

	local me = side(session, userId)
	if not me then return refuse(userId, "You are not in this trade") end

	local data = dataOf(userId)
	if not data then return refuse(userId, "Your data is not loaded") end

	-- Validated into a NEW list first and only swapped in once the whole thing is legal, so a
	-- rejected offer leaves the previous one standing rather than half-applied.
	local accepted = {}
	for _, item in ipairs(offered) do
		if item.kind == TradeItems.RELIC then
			-- ===== ONLY THE COLLECTION LAYER, AND ONLY A SPARE =====
			--
			-- The fifteen worn relics get their own sentence rather than falling through this
			-- lookup, because "that relic does not exist" about the Melon Slice in your second slot
			-- reads as the game being broken. `SetRelicsByKey` and `RelicsByKey` are disjoint by
			-- construction -- see the header of `GameConfig/Relics.lua` -- so the test is exact
			-- rather than a guess at the shape of the key.
			local relic = GameConfig.GetSetRelic(item.key)
			if not relic then
				if GameConfig.RelicsByKey[item.key] then
					return refuse(userId, "Equipped relics are not tradeable")
				end
				return refuse(userId, "That relic does not exist")
			end
			-- A SPARE IS `copies - 1`, and that rule is written down in `GameConfig/Relics.lua`
			-- with 30.7 named in it: a trade that could hand over your only copy would break the
			-- set you are collecting, which is the one thing the collection layer promises. It also
			-- means a traded key can never leave `data.SetRelics` -- so no trade can un-complete a
			-- set, and the commit below leans on exactly that.
			local spare = GameConfig.GetSpareSetRelics(data, item.key)
			if spare < item.n then
				if spare <= 0 then
					return refuse(userId, ("%s is your only one"):format(relic.name))
				end
				return refuse(userId, ("You have %d spare %s"):format(spare, relic.name))
			end
			table.insert(accepted, item)
		else
			local petId = item.id
			local _, pet = petIndexById(data, petId)
			if not pet then return refuse(userId, "You do not own that pet") end
			-- reserved by SOMEBODY ELSE'S session, or by this one already -- the second is fine
			if reserved[petId] and reserved[petId] ~= session.id then
				return refuse(userId, "That pet is in another trade")
			end
			-- An equipped pet is refused rather than silently unequipped. Unequipping somebody's
			-- loadout as a side effect of opening a window is the sort of thing that reads as the
			-- game stealing from you, and the fix is one deliberate press on their side.
			for _, equippedId in ipairs(data.EquippedPetIds or {}) do
				if equippedId == petId then return refuse(userId, "Unequip that pet first") end
			end
			-- 30.5: AND NOT ONE THAT IS AWAY. The same blind spot as the equipped check above it,
			-- one step worse: a trade COMMITS by moving the pet into somebody else's save, so an
			-- away pet traded out leaves its owner holding a dispatch entry for a pet that is now
			-- another player's -- and the claim would pay the wrong person's collection.
			if GameConfig.IsPetAway(data, petId) then
				return refuse(userId, "That pet is away on an adventure")
			end
			table.insert(accepted, item)
		end
	end

	-- release what this side had claimed, then claim the new list. Pets only -- see the note over
	-- `releaseReservations` for why a relic line needs no claim of its own.
	for _, petId in ipairs(TradeItems.PetIds(me.offer)) do
		if reserved[petId] == session.id then reserved[petId] = nil end
	end
	for _, petId in ipairs(TradeItems.PetIds(accepted)) do
		reserved[petId] = session.id
	end
	me.offer = accepted

	-- THE ANTI-SCAM RULE. Both sides, unconditionally, on every change to either offer. Without
	-- this line the whole feature is a scam delivery mechanism -- see the header.
	session.a.confirmed = false
	session.b.confirmed = false

	pushSession(session, "open")
	return session
end

function TradeService.Confirm(userId, tradeId)
	local session = TradeService.GetSession(userId)
	if not session or (tradeId and session.id ~= tradeId) then return nil, "You are not in a trade" end
	if session.state ~= "open" then return nil, "The trade is not open" end
	local me = side(session, userId)
	if not me then return nil, "You are not in this trade" end
	-- an empty-both trade is not a trade; one empty side is a gift and is allowed
	if #session.a.offer == 0 and #session.b.offer == 0 then return nil, "Nobody has offered anything" end
	me.confirmed = true

	if session.a.confirmed and session.b.confirmed then
		session.state = "countdown"
		pushSession(session, "countdown")
		task.delay(3, function()
			if not session.closed and session.state == "countdown" and session.a.confirmed and session.b.confirmed then
				local res, err = TradeService.Commit(session.id)
				if res then
					pushSession(session, "completed")
				else
					pushSession(session, "cancelled")
				end
			end
		end)
		return session
	end

	pushSession(session, "open")
	return session
end

-- ============================================================================
-- 8.2 + 8.3 -- THE COMMIT
-- ============================================================================
-- The only function here that can lose somebody something, and the only one written to be read
-- line by line. Everything above it is bookkeeping.
function TradeService.Commit(tradeId)
	local session = sessions[tradeId]
	if not session or session.closed then return nil, "That trade has gone" end
	if session.state == "committing" then return nil, "Already committing" end
	if not (session.a.confirmed and session.b.confirmed) then return nil, "Both sides must confirm" end

	local dataA, dataB = dataOf(session.a.userId), dataOf(session.b.userId)
	if not dataA or not dataB then
		closeSession(session, "data missing")
		return nil, "Somebody's data went away"
	end

	-- Proximity is checked AGAIN, not only at the request. A trade window that survives one player
	-- walking to another zone is a trade with somebody who is no longer standing in front of you,
	-- which is most of what the requirement was for.
	if not withinReach(session.a.userId, session.b.userId) then
		return nil, "You have moved too far apart"
	end

	-- ===== THE RECHECK =====
	-- Resolved fresh against the current inventories. An id captured when the offer was built can
	-- have been fused away, and the reservation deliberately does not stop its owner doing that.
	--
	-- 30.7: A RELIC LINE IS RE-CHECKED THE SAME WAY AND FOR A STRONGER REASON. It has no
	-- reservation at all -- there is nothing unique to reserve -- so this test is the only thing
	-- standing between an offer of four spares and an owner who spent three of them at the forge
	-- while the window was open. `GetSpareSetRelics` is re-read here rather than trusted from
	-- `SetOffer`, exactly as `petIndexById` is.
	local takeA, takeB = {}, {}
	local function gather(data, offer, out)
		for _, item in ipairs(offer) do
			if item.kind == TradeItems.RELIC then
				local relic = GameConfig.GetSetRelic(item.key)
				if not relic then return "One of those relics is gone" end
				if GameConfig.GetSpareSetRelics(data, item.key) < item.n then
					return ("One of those relics is no longer spare (%s)"):format(relic.name)
				end
				table.insert(out, { kind = TradeItems.RELIC, key = item.key, n = item.n, relic = relic })
			else
				local index, pet = petIndexById(data, item.id)
				if not index then return "One of those pets is gone" end
				table.insert(out, { kind = TradeItems.PET, index = index, pet = pet })
			end
		end
		return nil
	end
	local gone = gather(dataA, session.a.offer, takeA) or gather(dataB, session.b.offer, takeB)
	if gone then return nil, gone end

	-- Neither side may be pushed past the collection cap. Counted as a net change, because an even
	-- swap at exactly the cap is legal and refusing it would be wrong.
	--
	-- COUNTS PETS, NOT LINES. `MAX_PETS` is the pet collection's ceiling and a relic line has
	-- nothing to do with it -- counting `#takeA` here after 30.7 would have made a trade of four
	-- relics look like four pets arriving and refused a legal swap near the cap.
	local function petCount(list)
		local n = 0
		for _, entry in ipairs(list) do
			if entry.kind == TradeItems.PET then n = n + 1 end
		end
		return n
	end
	local petsFromA, petsFromB = petCount(takeA), petCount(takeB)
	if #dataA.Pets - petsFromA + petsFromB > MAX_PETS then return nil, "Their collection is full" end
	if #dataB.Pets - petsFromB + petsFromA > MAX_PETS then return nil, "Your collection is full" end

	-- Equipped is refused at SetOffer, so this should never fire -- it is here because "should
	-- never" and "cannot" are different, and a pet that left an inventory while still listed in
	-- EquippedPetIds is a permanent phantom bonus.
	for _, s in ipairs({ { session.a.userId, dataA, session.a.offer }, { session.b.userId, dataB, session.b.offer } }) do
		for _, equippedId in ipairs(s[2].EquippedPetIds or {}) do
			for _, petId in ipairs(TradeItems.PetIds(s[3])) do
				if equippedId == petId then return nil, "A pet in the trade is equipped" end
			end
		end
	end

	session.state = "committing"

	-- =========================================================================
	-- FROM HERE TO THE END OF THE SWAP, NOTHING YIELDS. No wait, no SetAsync, no event fired.
	-- This is property 3 in the header and it is the whole reason duplication is impossible
	-- rather than unlikely: any yield in this block is a moment when one pet is in two
	-- inventories, and Roblox schedules a fuse or a hatch into exactly that moment eventually.
	-- =========================================================================
	local movedA, movedB = {}, {}

	local function moveOut(data, list, moved)
		-- PETS FIRST AND BY DESCENDING INDEX, so earlier removals cannot shift the ones still to
		-- come. The relic lines are separated out rather than sorted with them: they carry no
		-- index at all, and `table.sort` over a mixed list would compare a number with nil.
		local petEntries = {}
		for _, entry in ipairs(list) do
			if entry.kind == TradeItems.PET then table.insert(petEntries, entry) end
		end
		table.sort(petEntries, function(x, y) return x.index > y.index end)
		for _, entry in ipairs(petEntries) do
			table.remove(data.Pets, entry.index)
			table.insert(moved, { kind = TradeItems.PET, pet = entry.pet })
		end
		for _, entry in ipairs(list) do
			if entry.kind == TradeItems.RELIC then
				-- Never below 1, because only spares were offered and the recheck above re-proved
				-- it a few lines ago. The key therefore stays in the table and the giver's set
				-- stays complete -- which is the whole reason the spare rule exists.
				data.SetRelics[entry.key] = (tonumber(data.SetRelics[entry.key]) or 0) - entry.n
				table.insert(moved, { kind = TradeItems.RELIC, key = entry.key, n = entry.n, relic = entry.relic })
			end
		end
	end

	local function moveIn(data, moved)
		for _, entry in ipairs(moved) do
			if entry.kind == TradeItems.PET then
				table.insert(data.Pets, entry.pet)
			else
				-- **NOT `GameConfig.AddSetRelic`**, and this is the one line in the row where the
				-- obvious call is the wrong one. `AddSetRelic` pays `RelicDust` for every copy past
				-- the first -- which is right for a DROP, where the dust is the whole value of a
				-- duplicate, and is currency MINTING here. Two players with a spare each could
				-- trade it back and forth and print dust forever. A trade moves goods; it does not
				-- pay anybody.
				if type(data.SetRelics) ~= "table" then data.SetRelics = {} end
				data.SetRelics[entry.key] = (tonumber(data.SetRelics[entry.key]) or 0) + entry.n
			end
		end
	end

	moveOut(dataA, takeA, movedA)
	moveOut(dataB, takeB, movedB)
	moveIn(dataB, movedA)
	moveIn(dataA, movedB)
	-- =========================================================================
	-- ...and the swap is done. Everything below may yield freely.
	-- =========================================================================

	local record = {
		id = session.id,
		at = os.time(),
		jobId = game.JobId ~= "" and game.JobId or "studio",
		a = { userId = session.a.userId, gave = {} },
		b = { userId = session.b.userId, gave = {} },
	}
	local function line(entry)
		if entry.kind == TradeItems.RELIC then
			return { kind = TradeItems.RELIC, key = entry.key, n = entry.n, text = describeRelic(entry.key, entry.n) }
		end
		local pet = entry.pet
		return { kind = TradeItems.PET, id = pet.id, key = pet.key, tier = pet.tier, text = describe(pet) }
	end
	for _, entry in ipairs(movedA) do table.insert(record.a.gave, line(entry)) end
	for _, entry in ipairs(movedB) do table.insert(record.b.gave, line(entry)) end

	closeSession(session, "committed")
	noteTrade(record.a.userId)
	noteTrade(record.b.userId)

	-- SAVED AFTER THE SWAP, and both writes checked. In-memory Cache is the authority for a live
	-- session, so a failed write here cannot duplicate anything -- it can only lose, and the
	-- 60-second autosave retries from the state that is already correct. A failure is recorded on
	-- the log entry rather than swallowed, because "the trade went through and one save did not"
	-- is exactly the report support will be handed.
	local playerA = Players:GetPlayerByUserId(record.a.userId)
	local playerB = Players:GetPlayerByUserId(record.b.userId)
	record.savedA = playerA and PlayerDataService.Save(playerA) or nil
	record.savedB = playerB and PlayerDataService.Save(playerB) or nil
	if record.savedA == false or record.savedB == false then
		warn(("[Trade] %s committed but a save failed (a=%s b=%s) -- autosave will retry")
			:format(record.id, tostring(record.savedA), tostring(record.savedB)))
	end

	TradeService.Record(record)

	if playerA then PlayerDataService.PushToClient(playerA) end
	if playerB then PlayerDataService.PushToClient(playerB) end
	-- 20.3: TRADE COMPLETED, once per SIDE, so the number is comparable with TradeOpened above
	-- (which is also per-player). A trade that committed is the only one that counts.
	if playerA then Telemetry.Custom(playerA, "TradeCompleted") end
	if playerB then Telemetry.Custom(playerB, "TradeCompleted") end
	tell(record.a.userId, { kind = "reward", message = "\u{1F91D} Trade complete!" })
	tell(record.b.userId, { kind = "reward", message = "\u{1F91D} Trade complete!" })

	-- ===== 30.7: THE ONE THING IN A TRADE WORTH TELLING THE OTHER SERVERS ABOUT =====
	--
	-- A Mythic collection relic is the top of a twenty-set, two-hundred-relic chase, and
	-- `AnnounceService` is the only cross-server channel this game has. Announcing it is what makes
	-- a rare relic worth trading FOR rather than only worth owning -- the point is that other
	-- people hear about it.
	--
	-- Fired for the RECEIVER, because that is who now has it, and after the saves rather than
	-- inside the swap, because `Broadcast` publishes to MessagingService and therefore yields.
	-- One per side: `AnnounceService` holds its own per-player cooldown and would swallow the rest
	-- anyway, and a trade of six Mythics is one event, not six.
	local function announceMythic(player, moved)
		if not player then return end
		for _, entry in ipairs(moved) do
			if entry.kind == TradeItems.RELIC and entry.relic and entry.relic.rarity == "Mythic" then
				AnnounceService.RelicObtained(player, entry.relic, "TRADE")
				return
			end
		end
	end
	announceMythic(playerB, movedA)
	announceMythic(playerA, movedB)

	return record
end

-- ============================================================================
-- 8.4 -- THE LOG
-- ============================================================================
-- Kept in memory for this server and written to its own DataStore for support. Public so a test
-- can read it back, and pcall'd throughout: a scoreboard-grade write must never be able to break
-- a trade that has already happened in the only place that counts.
function TradeService.Record(record)
	table.insert(TradeService.Log, record)
	while #TradeService.Log > LOG_KEEP do table.remove(TradeService.Log, 1) end

	task.spawn(function()
		pcall(function()
			-- keyed by day so one key never grows without bound, and appended with UpdateAsync
			-- rather than SetAsync so two servers trading in the same minute do not overwrite
			-- each other -- the same reasoning as StatsService's flush
			local key = "trades_" .. os.date("!%Y%m%d")
			logStore:UpdateAsync(key, function(old)
				old = (type(old) == "table") and old or {}
				table.insert(old, record)
				-- a day's key is capped: a DataStore value has a size limit and a log that grows
				-- past it stops accepting writes entirely, which loses the newest entries -- the
				-- ones an investigation is actually about
				while #old > 400 do table.remove(old, 1) end
				return old
			end)
		end)
	end)
end

-- ============================================================================
-- INIT
-- ============================================================================
function TradeService.Init()
	-- 30.7: the policy cache warms itself from here rather than from `ServerMain`, because this is
	-- the only file that asks it anything -- a second wiring point is a second thing to forget.
	TradePolicy.Init()

	-- A player leaving is a cancel, not a pause. Their reservations have to go back or the pets
	-- are locked out of every future trade until the server restarts, and the other side has to be
	-- told rather than left looking at a window that will never resolve.
	Players.PlayerRemoving:Connect(function(player)
		TradeService.Cancel(player.UserId, "left")
		recent[player.UserId] = nil
		lastRequest[player.UserId] = nil
	end)

	-- Timeouts, for the window somebody opened and walked away from.
	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.time()
			for _, session in pairs(sessions) do
				if now - session.openedAt > SESSION_TIMEOUT then
					closeSession(session, "timed out")
					for _, s in ipairs({ session.a, session.b }) do
						tell(s.userId, { kind = "error", message = "Trade timed out" })
					end
				end
			end
		end
	end)

	-- THE TWO OUTBOUND REMOTES HAVE TO EXIST BEFORE ANY CLIENT LOOKS FOR THEM, and until now they
	-- did not. `pushSession` and `Request` call `ensureRemote("TradeUpdate")` / `("TradeInvite")`
	-- at the moment they first need to send -- which is the first trade anyone starts. `MainUI`
	-- binds with `Remotes:FindFirstChild("TradeUpdate")` at startup and wraps the connection in
	-- `if tradeUpdateRemote then`, so on a fresh server it found nil, skipped the connect without a
	-- word, and no trade update could ever reach a client. Measured live 2026-08-15: a real
	-- `TradeUpdate` payload fired at a joined client left `TradeModal.Visible = false`, because
	-- nothing was listening. 15.5 fixed the server half of "no offer could ever be drawn"; this is
	-- the client half of the same sentence.
	ensureRemote("TradeUpdate")
	ensureRemote("TradeInvite")

	-- Wire Remotes for client communication
	local reqRemote = ensureRemote("TradeRequest")
	reqRemote.OnServerEvent:Connect(function(player, targetUserId)
		local targetId = tonumber(targetUserId)
		if not targetId and typeof(targetUserId) == "Instance" and targetUserId:IsA("Player") then
			targetId = targetUserId.UserId
		end
		if targetId then
			TradeService.Request(player.UserId, targetId)
		end
	end)

	local acceptRemote = ensureRemote("TradeAccept")
	acceptRemote.OnServerEvent:Connect(function(player, tradeId)
		TradeService.Accept(player.UserId, tradeId)
	end)

	local cancelRemote = ensureRemote("TradeCancel")
	cancelRemote.OnServerEvent:Connect(function(player)
		TradeService.Cancel(player.UserId, "cancelled")
	end)

	local offerRemote = ensureRemote("TradeSetOffer")
	-- `items` since 30.7, not `petIds`: the payload is a list of typed lines now and the old name
	-- would tell the next reader the wrong thing about what arrives here. A bare string is still
	-- read as a pet id -- see `TradeItems.Normalise` -- so a client that has not reloaded keeps
	-- working through the update.
	offerRemote.OnServerEvent:Connect(function(player, items)
		TradeService.SetOffer(player.UserId, items)
	end)

	local confirmRemote = ensureRemote("TradeConfirm")
	confirmRemote.OnServerEvent:Connect(function(player, tradeId)
		TradeService.Confirm(player.UserId, tradeId)
	end)
end

-- Public for tests and for a support investigation: what is live right now.
function TradeService.Debug()
	local live, held = 0, 0
	for _ in pairs(sessions) do live += 1 end
	for _ in pairs(reserved) do held += 1 end
	return { sessions = live, reservedPets = held, logged = #TradeService.Log }
end

return TradeService
