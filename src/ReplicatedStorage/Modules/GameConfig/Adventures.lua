-- GameConfig.Adventures -- the pet adventures: their routes, the luck ladder, and the ledger that
-- remembers a pet is away.
--
-- ONE OF THE PARTS OF `GameConfig` (18.9). It is handed the shared config table and writes into it;
-- see the loader in `GameConfig` itself for why the order of the parts is load-bearing. This one is
-- required LAST, AFTER `Expeditions`, and that is a hard dependency rather than a convention: it
-- walks `GameConfig.Zones` at load time to derive one route per zone, and it quotes `GetPetPower`,
-- `GetLuckPercent` and `PetBaseBonus` from `Pets` at call time.
--
-- =====================================================================================
-- WHY IT IS "ADVENTURE" AND NOT "EXPEDITION" (30.1)
-- =====================================================================================
-- `Expedition` is taken, eight ways: `GameConfig/Expeditions.lua`, `ExpeditionService`,
-- `ExpeditionMap`, `ExpeditionUI`, `data.Expeditions` and eight remotes. Remotes live FLAT in one
-- folder with ~46 siblings and there is no namespacing anywhere in this game, so the `Adventure*`
-- prefix is load-bearing rather than cosmetic -- two remotes that collide on a name are one silent
-- overwrite at Init and a feature with no door.
--
-- =====================================================================================
-- THE LOOP, IN ONE LINE
-- =====================================================================================
--   Pick a pet -> pick a route -> RUN the obby yourself (~90 s, best reward) or SEND the pet
--   (8-20 min, you keep playing) -> the pet comes back with a relic -> the relic completes a zone
--   set -> the set pays a permanent bonus -> the spare copies are what you trade.
--
-- This part is the numbers half of that. The map is 30.3, running it is 30.4, the dispatch is 30.5,
-- the panel is 30.6 and the relics themselves are 30.2.
--
-- =====================================================================================
-- ANY PET MAY GO, AND THE ROUTE'S TIER IS THE ONLY GATE
-- =====================================================================================
-- The owner asked for "send a better pet, get a better relic". That is expressed here as ONE
-- comparison -- `GetPetPower(pet, data) >= route.minPetPower` -- and deliberately NOT as a rarity
-- gate, a stage gate or a new stat axis:
--
--   * `GetPetPower` is already the single scalar for "how good is this pet" (`Pets.lua:949`). It is
--     the pet's damage share, so it moves automatically with any future pet rebalance, and it reads
--     the ZONE axis through `data` -- an in-zone Epic really does beat an out-of-zone Legendary,
--     which is the same ranking `Equip Best` uses.
--   * THERE IS NO STAGE GATE ON A ROUTE, on purpose. A better pet UNLOCKS a better route; it never
--     locks anybody out of the feature. Route 1 wants power 0, so the first pet a player ever
--     hatches clears it. That is the same argument that left `minStageIndex = 1` on the Forest
--     expedition: this is content a brand-new player can be shown that is not a number going up.
--
-- =====================================================================================
-- THE LUCK LADDER, AND THE DOUBLE-COUNT IT WOULD HAVE SHIPPED
-- =====================================================================================
-- The ladder the owner asked for is one line: `luckMult = 1 + (tier - 1) * AdventureLuckStep`, so
-- route 1 is 1.00x and route 20 is 4.00x, applied to the player's own luck stack.
--
-- THE PLAN SAID "the pet adds on top" AND THAT IS THE ONE THING CHANGED HERE, because written that
-- way it is a defect in two directions at once. A pet's luck is `PetBaseBonus.luckAdd * share`, and
-- when the pet is EQUIPPED that exact term is already inside `GetLuckPercent(data)` through
-- `GetEquippedBonus`. So `GetLuckPercent(data) * luckMult + petLuck` would:
--
--   1. count an equipped pet TWICE, and
--   2. pay more for equipping the pet before sending it than for sending it bare -- a free
--      micro-optimisation that every player finds and nobody enjoys.
--
-- `GetAdventureLuck` therefore adds the pet's term ONLY if it is not already in the sum, and
-- multiplies the WHOLE stack. The result is identical whether the pet was equipped or not, which is
-- the property that makes it explainable on the panel: "your luck, times the route's ladder".
--
-- =====================================================================================
-- THE LEDGER IS ON THE SAVE, AND THAT IS WHAT MAKES AUTOPLAY A RETENTION HOOK
-- =====================================================================================
-- `ExpeditionService` keeps `runs[userId]` in memory and it dies on rejoin, which is correct for a
-- run you are standing inside. A DISPATCH must not: the whole point of sending a pet for 8-20
-- minutes is that you close the game and it is waiting when you come back. So the dispatch list is
-- a save field, and a dispatch that ends while you are offline is claimable at next login.
--
-- `os.time()`, NEVER `GameConfig.UtcTimestamp()`. That one is a SPEC CONVERTER -- it turns an
-- authored `{year, month, day}` into a timestamp -- and calling it bare indexes a nil. Phase 28
-- shipped that bug; every ledger in the game now carries this note.

return function(GameConfig)

-- ===== THE CAPS, AND THE ONE NUMBER THAT MATTERS =====
--
-- 2 manual runs + 5 dispatches = at most 7 relic rolls a day, and a manual finish that beats par
-- rolls twice, so the true ceiling is 9. That is the number row 30.9 retunes and the first thing to
-- re-measure if the relic economy feels loose -- exactly the role `ExpeditionDailyRuns` plays for
-- the expedition and the arcade cap plays for Phase 28.
GameConfig.AdventureDailyRuns = 2
GameConfig.AdventureDailyDispatch = 5

-- How many pets may be away AT ONCE. One at the start, one more per rebirth, hard stop at three.
-- Slots are a rebirth reward rather than a purchase because rebirth is the progression axis that
-- currently pays in numbers only (Phase 27's complaint), and because a Robux door on "send more
-- pets" would be selling the relic ceiling, which is the one thing 30.2 argues must stay a chase.
GameConfig.AdventureBaseSlots = 1
GameConfig.AdventureMaxSlots = 3

-- The ladder. One number, and it is the whole "better route = better relic" promise:
--   tier 1 -> 1.000x      tier 10 -> 2.422x      tier 20 -> 4.002x
GameConfig.AdventureLuckStep = 0.158

-- The top of the `GetPetPower` scale a route may ask for.
--
-- MEASURED, NOT ESTIMATED, and the plan's estimate was wrong at the floor. Walking all 140 species
-- x 4 tiers x 6 enchants against a live `GameConfig` (30.1, 2026-08-21):
--
--   0.100   Pebble, Normal, Common          -- the floor; the first pet anybody owns
--   5.040   Thornheart, Celestial, Secret   -- the best pet in the game with NO enchant
--   8.316   the same pet with `eternal`     -- the true ceiling, x1.65 off the enchant ladder
--
-- 5.5 is chosen to sit in the gap between the last two, and that placement is the design rather
-- than a round number: route 19 (4.883) is the top route a player can enter on raw pet quality
-- alone, and **route 20 is the only one that asks for an enchant**. It is the endgame chase and it
-- is reachable at `keen` x1.06 (5.342 -- just short) or `fierce` x1.14 (5.746), so it wants the
-- second rung of a six-rung ladder, not the top of it.
--
-- If this is ever raised, check it against 5.040 first: anything above that silently makes the top
-- route enterable by nobody who has not also won the enchant roll, and a route nobody can enter
-- looks exactly like a bug in the panel.
GameConfig.AdventureTopPetPower = 5.5

-- How long a dispatch takes, tier 1 -> tier 20. Eight minutes is short enough to be worth doing
-- once while the shop panel is open; twenty is long enough that the top route is an "I will be
-- back" rather than a second grind.
GameConfig.AdventureAutoMinutesMin = 8
GameConfig.AdventureAutoMinutesMax = 20

-- Skipping the wait costs DIAMONDS, and FLAT. Diamonds buy fixed-price permanent things in this
-- game (5/8/15 upgrades, a 40-diamond relic chest) and 21.2's rule is that they never go through
-- `ScaleReward` -- a scaled diamond price is meaningless to the player who has 12 of them.
GameConfig.AdventureFinishNowDiamonds = 40

-- ===== THE ROUTES =====
--
-- ONE ROUTE PER ZONE, AND THE LIST IS DERIVED FROM `GameConfig.Zones` RATHER THAN AUTHORED BESIDE
-- IT. Every numeric field below is a function of the zone's INDEX, so `tier` cannot disagree with
-- the strip, no zone can be missed, no tier can be duplicated, and a 21st zone gets a route for
-- free. Only the flavour -- name, glyph, blurb -- is hand-written, because that is the only part a
-- formula cannot produce.
--
-- ===== EVERY GLYPH HERE IS U+1F300 OR ABOVE, AND IT IS CHECKED AT LOAD =====
-- 27.7 found `UITheme.Button` drawing a blank because FredokaOne has no glyph for U+2715, and
-- NOTHING reported it: `.Text`, `.TextColor3` and even `.TextFits` all read correct, because the
-- character is laid out and simply not drawn. Characters in U+2600-27BF are text-default and fall
-- back to the display font; from U+1F300 up they are emoji-presentation and drawn by the system
-- emoji font. The zones' own glyphs are NOT reused for that reason -- three of them (`\u{26AB}`,
-- `\u{269B}`, `\u{23F3}`) sit in the risky range. The tripwire at the bottom of this file is the
-- first check in the game that can catch this class of bug before a capture does.
local FLAVOUR = {
	Forest          = { name = "Overgrowth Trail",   emoji = "\u{1F33F}", blurb = "Something is nesting past the treeline. Follow the trail and bring back what it hoards." },
	Desert          = { name = "Sunken Caravan",     emoji = "\u{1F3DC}", blurb = "A supply caravan went under the dunes a season ago. The sand shifted. Go and look." },
	Ocean           = { name = "Reef Descent",       emoji = "\u{1F30A}", blurb = "The shelf drops away into the dark. Everything worth having sank past the ledge." },
	Volcano         = { name = "Ashfall Ridge",      emoji = "\u{1F30B}", blurb = "The ridge is venting again. Cross it between the vents and take the vault at the caldera." },
	Moon            = { name = "Crater Relay",       emoji = "\u{1F315}", blurb = "A relay station stopped answering. Its cargo bay is still sealed." },
	Mars            = { name = "Red Dust Run",       emoji = "\u{1F680}", blurb = "The dig site was abandoned mid-shift. Whatever they found is still in the crate." },
	Galaxy          = { name = "Starlane Drift",     emoji = "\u{1F30C}", blurb = "Jump the drifting lanes. Miss one and the current takes you the long way round." },
	BlackHole       = { name = "Event Horizon",      emoji = "\u{1F573}", blurb = "Everything that ever fell in is stacked at the edge. Reach in and pull one out." },
	Multiverse      = { name = "Forked Path",        emoji = "\u{1F300}", blurb = "The same corridor forty times over, none of them quite matching. One of them has the door." },
	Nebula          = { name = "Dust Cathedral",     emoji = "\u{1F320}", blurb = "A cloud that took a shape it should not have. Walk in far enough to see the middle." },
	Wormhole        = { name = "Throat Crossing",    emoji = "\u{1F32A}", blurb = "The tunnel moves while you are inside it. Time the crossing or it moves you." },
	QuantumRealm    = { name = "Probability Steps",  emoji = "\u{1F52C}", blurb = "Each step is there until it is looked at. Do not look down." },
	TimeRift        = { name = "Rewound Ascent",     emoji = "\u{1F570}", blurb = "The climb undoes itself behind you. Reach the top before it reaches you." },
	AntimatterZone  = { name = "Annihilation Line",  emoji = "\u{1F4A5}", blurb = "Two halves of the same corridor that must never touch. Run the seam between them." },
	DreamDimension  = { name = "Sleepwalk",          emoji = "\u{1F4AD}", blurb = "The floor is whatever you last remembered standing on. Keep remembering." },
	MirrorUniverse  = { name = "Reflected Gauntlet", emoji = "\u{1F52E}", blurb = "Something is running the same course on the other side of the glass, and it is faster." },
	VoidExpanse     = { name = "Nothing At All",     emoji = "\u{1F311}", blurb = "No floor, no ceiling, no marks. The only thing out here is the thing you came for." },
	CelestialThrone = { name = "The Long Stair",     emoji = "\u{1F451}", blurb = "Every step is a court that has to be crossed. Nobody has ever been invited." },
	Singularity     = { name = "Final Approach",     emoji = "\u{1F4AB}", blurb = "One point, and everything else is the distance to it. Close the distance." },
	AbsolutePlane   = { name = "The Absolute Run",   emoji = "\u{1F53A}", blurb = "There is no route here. There is only whether you are the kind of thing that arrives." },
}

-- How many sections a course is cut into, and it is the ONE field 30.3 reads as difficulty. Three
-- for the first third, four for the middle, five at the top -- more checkpoints AND more course,
-- because a longer obby with the same number of pads is a punishment rather than a step up.
local function sectionsForTier(tier)
	return 3 + math.floor((tier - 1) / 7)
end

local function round(x, places)
	local m = 10 ^ (places or 0)
	return math.floor(x * m + 0.5) / m
end

-- The minimum pet a route will accept. GEOMETRIC, not linear, and the exponent is the design:
-- routes 1-8 are cleared by whatever a player already owns, and the ask only bites in the last
-- third, which is where "send a better pet" is supposed to become a decision instead of a
-- formality.
--   tier 1 -> 0      tier 5 -> 0.178      tier 10 -> 1.063      tier 15 -> 2.809      tier 20 -> 5.5
-- Against the measured scale above: the floor pet (0.100) clears routes 1-4, and the best
-- un-enchanted pet in the game (5.040) clears 1-19.
local function minPowerForTier(tier, topTier)
	if tier <= 1 then return 0 end
	return round(GameConfig.AdventureTopPetPower * (((tier - 1) / (topTier - 1)) ^ 2.2), 3)
end

GameConfig.AdventureList = {}
GameConfig.AdventuresByKey = {}

local topTier = #GameConfig.Zones
for tier, zone in ipairs(GameConfig.Zones) do
	local flavour = FLAVOUR[zone.key] or {}
	local sections = sectionsForTier(tier)
	local route = {
		key = zone.key,
		zoneKey = zone.key,
		tier = tier,
		name = flavour.name or (zone.name .. " Route"),
		-- `\u{1F5FA}` (world map) is the fallback rather than an empty string, because
		-- `RelicsPanel:419` already proved that an unmapped icon renders as a HOLE and nobody
		-- notices a hole in a list they have never seen full.
		emoji = flavour.emoji or "\u{1F5FA}",
		blurb = flavour.blurb or ("An unmapped route out past " .. zone.name .. "."),
		-- Painted on the course boards by 30.3, the way the expedition tells its story on the walls:
		-- this game creates zero Humanoids server-side and has no dialogue system, so signs are it.
		sections = sections,
		luckMult = round(1 + (tier - 1) * GameConfig.AdventureLuckStep, 3),
		minPetPower = minPowerForTier(tier, topTier),
		autoMinutes = round(
			GameConfig.AdventureAutoMinutesMin
				+ (tier - 1) * (GameConfig.AdventureAutoMinutesMax - GameConfig.AdventureAutoMinutesMin)
					/ math.max(topTier - 1, 1)
		),
		-- A TARGET, NOT A WALL -- the arcade's rule, and the reason its payout curve pays below par
		-- at all. Beating it is the second relic roll; missing it still finishes the run.
		parSeconds = 26 * sections + 2 * tier,
		-- The course paints itself out of the zone it is themed on, so a route can never drift away
		-- from the zone whose name it is wearing.
		groundColor = zone.groundColor,
		accentColor = zone.accentColor,
	}
	GameConfig.AdventureList[tier] = route
	GameConfig.AdventuresByKey[route.key] = route
end

function GameConfig.GetAdventure(key)
	return GameConfig.AdventuresByKey[key]
end

-- ===== THE LEDGER =====
--
-- `data.Adventures` is
--   { Day = <day number>, DayRuns = n, DayDispatch = n,
--     Best = {key -> best finish time in seconds}, Cleared = {key -> times finished},
--     Dispatch = { { petId, routeKey, tier, startedAt, endsAt }, ... } }
--
-- Shaped HERE rather than in `defaultData`, and it ROLLS THE DAY OVER ITSELF, the same shape as
-- `GetExpeditionLedger` and `GetMinigameLedger` for the same reason: which day a save belongs to is
-- decided by the clock at READ time, and the only moment anybody can notice the date changed is the
-- moment they ask. A save written before Adventures existed is therefore repaired by being looked
-- at -- there is no migration to write and no version field to bump.
--
-- `Dispatch` IS NOT ROLLED. A pet sent at 23:58 is still away at 00:02, and the day counter moving
-- must not strand it; only the two counters reset.
function GameConfig.GetAdventureLedger(data, now)
	data.Adventures = data.Adventures or {}
	local ledger = data.Adventures
	ledger.Best = ledger.Best or {}
	ledger.Cleared = ledger.Cleared or {}
	ledger.Dispatch = ledger.Dispatch or {}

	local today = math.floor((now or os.time()) / 86400)
	if ledger.Day ~= today then
		ledger.Day = today
		ledger.DayRuns = 0
		ledger.DayDispatch = 0
	end
	ledger.DayRuns = ledger.DayRuns or 0
	ledger.DayDispatch = ledger.DayDispatch or 0
	return ledger
end

-- How many pets may be away at once. Rebirths, clamped -- one call, so the panel that draws the
-- slots and the server that refuses the fourth can never disagree.
function GameConfig.GetAdventureSlots(data)
	local rebirths = data and data.Rebirths or 0
	return math.clamp(
		GameConfig.AdventureBaseSlots + rebirths,
		GameConfig.AdventureBaseSlots,
		GameConfig.AdventureMaxSlots
	)
end

-- The dispatch a given pet is on, or nil. THE ONE FUNCTION EVERY REFUSAL IN 30.5 IS BUILT ON:
-- fusing, releasing, equip-best, tier-up, enchanting and offering an away pet in a trade all have
-- to say no, and six private copies of this loop would drift the first time the shape changed.
function GameConfig.GetPetDispatch(data, petId)
	if not (data and petId) then return nil end
	local ledger = data.Adventures
	if not (ledger and ledger.Dispatch) then return nil end
	for _, entry in ipairs(ledger.Dispatch) do
		if entry.petId == petId then return entry end
	end
	return nil
end

function GameConfig.IsPetAway(data, petId)
	return GameConfig.GetPetDispatch(data, petId) ~= nil
end

-- Seconds left on a dispatch; 0 once it is claimable. Never negative, because the panel divides by
-- the total to draw a bar and a negative remainder draws a bar pointing backwards off its frame.
function GameConfig.GetDispatchRemaining(entry, now)
	if not entry then return 0 end
	return math.max((entry.endsAt or 0) - (now or os.time()), 0)
end

-- The pet's OWN luck contribution -- the same term `GetEquippedBonus` adds for it, quoted from
-- `PetBaseBonus` rather than written as `12` so a pet rebalance moves this with it.
function GameConfig.GetAdventurePetLuck(pet, data)
	if not pet then return 0 end
	return GameConfig.PetBaseBonus.luckAdd * GameConfig.GetPetPower(pet, data)
end

-- ===== WHAT THE ROUTE ROLLS AGAINST =====
--
-- The whole luck stack, times the route's ladder. See the header for why the pet's term is added
-- only when it is not already inside `GetLuckPercent` -- an equipped pet is counted once, and the
-- answer is the same either way, which is the property that makes it explainable on the panel.
function GameConfig.GetAdventureLuck(data, route, pet)
	if not data then return 0 end
	local luck = GameConfig.GetLuckPercent(data)
	if pet then
		local equipped = false
		for _, id in ipairs(data.EquippedPetIds or {}) do
			if id == pet.id then
				equipped = true
				break
			end
		end
		if not equipped then
			luck += GameConfig.GetAdventurePetLuck(pet, data)
		end
	end
	return luck * ((route and route.luckMult) or 1)
end

-- ===== WHAT A FINISH IS WORTH (30.4) =====
--
-- ONE RELIC ROLL FOR ARRIVING, A SECOND FOR BEATING PAR -- the whole of the manual run's reward,
-- and the reason the cap note at the top of this file says "at most 9". It is a pure function of
-- the route and the clock so the panel can promise it before the run and the server can pay it
-- after, out of the same line.
--
-- `seconds` IS ALLOWED TO BE NIL, and that is what the panel passes: no time yet means no par
-- bonus yet, i.e. one roll, which is exactly what a briefing should quote as the floor.
--
-- PAR IS INCLUSIVE. Finishing on the second is beating it -- a strictly-less comparison would make
-- the one finish a player can actually feel proud of look like a bug.
function GameConfig.GetAdventureRolls(route, seconds)
	if not route then return 0, false end
	local par = tonumber(route.parSeconds) or 0
	local underPar = seconds ~= nil and par > 0 and seconds <= par
	return underPar and 2 or 1, underPar
end

-- ===== WHAT THE PANEL SAYS AND WHAT THE SERVER REFUSES -- ONE FUNCTION =====
--
-- Pure over the save, the `GetExpeditionStatus` / `GetSplicerRollCost` shape and for the same
-- reason: the briefing is drawn from the payload the server just pushed, so the runs-left on screen
-- is not a client-side estimate of it -- it IS the call the server refuses an entry with.
--
-- It answers for BOTH buttons at once. The panel draws PLAY and SEND side by side and they refuse
-- for different reasons -- a full slot stops SEND and not PLAY, a spent daily run stops PLAY and
-- not SEND -- so a single `ready` boolean would grey out the wrong button half the time.
--
-- Returns a table rather than a boolean because every refusal is worded differently, and a panel
-- that says "not ready" to all of them is the panel players ask about in the group chat.
function GameConfig.GetAdventureStatus(data, key, pet, now)
	local route = GameConfig.GetAdventure(key)
	if not route then
		return { ready = false, reason = "none", canSend = false, sendReason = "none" }
	end
	if not data then
		return { route = route, ready = false, reason = "none", canSend = false, sendReason = "none" }
	end

	local ledger = GameConfig.GetAdventureLedger(data, now)
	local slots = GameConfig.GetAdventureSlots(data)
	local slotsUsed = #ledger.Dispatch
	local runsLeft = math.max(GameConfig.AdventureDailyRuns - ledger.DayRuns, 0)
	local dispatchLeft = math.max(GameConfig.AdventureDailyDispatch - ledger.DayDispatch, 0)
	local petPower = pet and GameConfig.GetPetPower(pet, data) or 0

	local status = {
		route = route,
		tier = route.tier,
		best = ledger.Best[key] or 0,
		cleared = ledger.Cleared[key] or 0,
		par = route.parSeconds,
		sections = route.sections,
		luckMult = route.luckMult,
		minPetPower = route.minPetPower,
		autoMinutes = route.autoMinutes,
		petPower = petPower,
		luck = GameConfig.GetAdventureLuck(data, route, pet),
		runsLeft = runsLeft,
		dailyRuns = GameConfig.AdventureDailyRuns,
		dispatchLeft = dispatchLeft,
		dailyDispatch = GameConfig.AdventureDailyDispatch,
		slots = slots,
		slotsUsed = slotsUsed,
	}

	-- The pet gate is first for both buttons, because it is the one refusal that names something the
	-- player can act on right now: pick a different pet.
	local petOk, petReason
	if not pet then
		petOk, petReason = false, "nopet"
	elseif GameConfig.IsPetAway(data, pet.id) then
		petOk, petReason = false, "away"
	elseif petPower < route.minPetPower then
		petOk, petReason = false, "power"
	else
		petOk, petReason = true, nil
	end

	if not petOk then
		status.ready, status.reason = false, petReason
	elseif runsLeft <= 0 then
		status.ready, status.reason = false, "capped"
	else
		status.ready, status.reason = true, "ready"
	end

	if not petOk then
		status.canSend, status.sendReason = false, petReason
	elseif slotsUsed >= slots then
		status.canSend, status.sendReason = false, "slots"
	elseif dispatchLeft <= 0 then
		status.canSend, status.sendReason = false, "capped"
	else
		status.canSend, status.sendReason = true, "ready"
	end

	return status
end

-- ===== THREE THINGS THAT ARE BUGS, AND THEY SAY SO AT LOAD =====
--
-- All three run once, cost a couple of dozen lookups, and name the route. They exist because each
-- one has already shipped in this project at least once:
--
--   * a route naming a zone that does not exist -- the shape of the "no eggs in this zone" bug,
--     where a per-zone skip keeps a truncated build forever;
--   * a glyph below U+1F300 -- 27.7 and 29.10, invisible to every property probe;
--   * a minimum pet power that goes DOWN with tier, which would make a later route EASIER to enter
--     than an earlier one and is exactly the kind of thing a retune in 30.9 does by accident.
for tier, route in ipairs(GameConfig.AdventureList) do
	local found = false
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.key == route.zoneKey then
			found = true
			break
		end
	end
	if not found then
		warn(("[GameConfig.Adventures] route %q names a zone that does not exist"):format(tostring(route.key)))
	end

	local ok, cp = pcall(utf8.codepoint, route.emoji, 1)
	if not ok or type(cp) ~= "number" or cp < 0x1F300 then
		warn(("[GameConfig.Adventures] route %q has glyph U+%s, BELOW U+1F300 -- it may draw as nothing at all (27.7)")
			:format(tostring(route.key), type(cp) == "number" and string.format("%04X", cp) or "?"))
	end

	local previous = GameConfig.AdventureList[tier - 1]
	if previous and route.minPetPower < previous.minPetPower then
		warn(("[GameConfig.Adventures] route %q (tier %d) asks for LESS pet power than %q before it")
			:format(tostring(route.key), tier, tostring(previous.key)))
	end
end

end
