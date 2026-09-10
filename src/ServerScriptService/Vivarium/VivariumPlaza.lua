--[==[
	VivariumPlaza -- every player gets a display in the hub, and it states their collection and
	their passive DNA/second where other people can read it (24.1).

	===== WHAT THE ROW IS FOR, AND WHAT IT IS DELIBERATELY NOT =====

	Phase 24's header says the Vivarium changes what genre this game is, and that the steal is the
	risky half. **This row is the half that is not**: its own text says it "is worth shipping even if
	the steal never does", so nothing here takes anything from anybody. A case is a shop window.
	`24.2` (the lock), `24.3` (soft steal) and `24.5` (anti-grief) are the rows that make it a
	contested object, and the two things they will need from this file are already here on purpose:
	a case knows its owner (`OwnerUserId` on the model) and a specimen stands on a NAMED slot anchor.

	It answers Phase 23's standing complaint -- "nothing today lets one player see what another
	has". 23.2 made a mutation visible at 300 studs; this makes the COLLECTION visible at 30.

	===== WHERE, AND WHY IT IS THREE BANKS INSTEAD OF ONE GALLERY =====

	**Forest has no clear ground left at the scale a gallery wants.** Measured on a booted server
	2026-09-10, on a 50-stud grid over the whole zone (x -625..625, z -575..575) with HubPlaza's own
	obstruction test -- `CanCollide` and a world AABB topping out above `GROUND_CLEAR` 1.4 -- **not
	one 50 x 50 cell in Forest is free**, anywhere. A single 60-case gallery was never an option and
	no amount of choosing a nicer centre would have found one.

	What does exist, measured the same way at 5 studs over the arrival lawn, is a short list of
	genuinely empty rectangles. The gallery is the biggest of them that are DISJOINT and clear of the
	walking lane (`HubPlaza.CORRIDOR_HALF` is 30, and the street furniture already owns |x| < 40):

	    WEST    x -195..-85   z 365..470     110 x 105
	    EAST    x   70..170   z 370..430     100 x  60
	    NORTH   x   40..140   z 465..525     100 x  60

	All three are north of `ForestSpawn` (0, 366), so a player arriving walks into the aisles rather
	than past them. Their neighbours, so a later session knows what it is standing next to: the
	exhibit plinths and the plaza's lamps and poles flank the walk south of z 360, `SprintTrack`'s
	arch posts and `HeraldStation`'s mark sit around x -140..-90 above z 470, the expedition doors
	and the minigame terminals are the clutter at x 60..120 below z 410, and the jungle trail heads
	come in at (-150, 390) and (150, 390).

	**THE EAST BANK IS 60 DEEP RATHER THAN THE 70 THAT MEASURED FREE, AND THE NORTH BANK EXISTS TO
	REPLACE WHAT THAT COST.** The survey said x 70..170, z 370..440 was empty and the survey was
	right -- and the first build still stood seven cases in the middle of the sprint track. See
	`RESERVED` below: the running surface is z 419..451 and every part of it is under the 1.4 line,
	so "empty" and "free" are not the same question. The east bank stops at 430 now.

	**THE BIGGEST RECTANGLE OF ALL IS NOT USED.** x -55..80, z 410..525 is 135 x 115 -- larger than
	any bank here -- and it straddles the arrival corridor directly north of the spawn. Filling it
	would put cases across the one line every player in this game walks down. It is recorded here so
	the next reader does not "find" it and think nobody looked.

	**THE THIRD RECTANGLE WAS THE BIGGEST AND IS NOT USED.** x -55..80, z 410..525 is 135 x 115 --
	larger than either bank -- and it straddles the arrival corridor directly north of the spawn.
	Filling it would put sixty cases across the one line every player in this game walks down. It is
	recorded here so the next reader does not "find" it and think nobody looked.

	===== SIXTY ANCHORS, BUILT LAZILY, FILLED FROM THE FRONT =====

	`Players.MaxPlayers` is 60 (checked 2026-09-09 by `PartyService`), so sixty is the count that
	makes "every player gets one" true rather than nearly true. Three consequences, all deliberate:

	  1. **Nothing is built until it is claimed.** Sixty empty cases is sixty times the part cost of
	     an empty mall. An unclaimed anchor is a position in a table and no instances at all.
	  2. **Claims take the LOWEST free index**, so five players in a server occupy the five cases at
	     the front of the west bank rather than five scattered ones. A gallery that fills from one
	     end always looks populated; one that fills at random always looks abandoned.
	  3. The three banks offer more positions at this pitch than 60, and only the first 60 are
	     generated. That spare depth is not slack -- it is what absorbs a blocked anchor (see below)
	     without a player losing their case, and it has already been spent once.

	**EVERY ANCHOR IS STILL TESTED AGAINST THE LIVE WORLD, even though the rectangles were measured
	empty.** The rectangles are a fact about one boot, and `HubPlaza`'s own header is the argument:
	four services search this same lawn minutes earlier in the same boot and two of them land in
	positions that are themselves searched. A blocked anchor is SKIPPED rather than nudged -- a case
	shoved 14 studs out of its row is no longer in the row, and a gallery with a gap in it reads
	better than one with a kink.

	===== SLOTS SCALE WITH REBIRTHS, AND THE LADDER SPANS THE WHOLE AXIS =====

	`SLOT_BASE` 2, one more every `SLOT_PER` 4 rebirths, capped at the case's six shelf positions:

	    rebirth  0 -> 2 slots      8 -> 4      16 -> 6
	             4 -> 3           12 -> 5      20 -> 6 (GameConfig.MaxRebirths)

	Reaching the cap at 16 of a possible 20 is the point: the top of the ladder has to be visibly
	reachable, and a sixth pet in the case is a thing you can only have by having rebirthed sixteen
	times. The pets themselves are ranked by `GameConfig.SortedPetsByPower` -- the same number the
	pets panel prints and the same one "Equip Best" uses -- so a case can never disagree with the UI
	about which of a player's pets are the best ones.

	===== THE BOARD IS REDRAWN ON A TICK, THE CASE IS REBUILT ONLY ON A CHANGE =====

	The passive rate is `DNAService.GetAutoCollectAmount(data)`, which is the number this game
	already means by idle income: it is what `OfflineService` pays out of, and it moves whenever the
	AutoCollect level, the stage or anything in `GetIncomeMult` moves. So the board's text is cheap
	and is refreshed every `TICK` seconds for everybody.

	Rebuilding the RIGS is not cheap, so it is keyed off a signature -- the slot count plus the ids
	of the pets that should be standing there. Equal signature, no work at all. That is the whole
	reason this does not cost anything on a full server: sixty boards of text a tick, and rigs only
	when somebody hatches, fuses, releases or rebirths.

	===== THE JOIN HANDLER GOES THROUGH PlayerJoin.onEach =====

	Never `Players.PlayerAdded:Connect` -- `roblox-playeradded-fires-before-a-late-init` is a class
	bug that has been found in eleven files in this repo, and this one initialises at the very end of
	the boot, which is the worst possible place to connect one by hand.
]==]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)
local UITheme = require(RS.Modules.UITheme)
local VivariumCase = require(script.Parent.VivariumCase)
local VivariumLock = require(script.Parent.VivariumLock)
-- Only for `RoadClearance`. No cycle: `JungleLayout` reaches `JungleTrails`, `MapGates`,
-- `SplicerService` and `ExpeditionService`, and nothing it touches reaches this file.
local JungleLayout = require(ServerScriptService.MapProps.JungleLayout)
local PlayerJoin = require(ServerScriptService.Systems.PlayerJoin)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local DNAService = require(ServerScriptService.DNAService)
local Telemetry = require(ServerScriptService.Telemetry)

local VivariumPlaza = {}

-- The same stamp shape as `PLAZA_VERSION`, `STAND_VERSION` and `TRACK_VERSION`: an older number is
-- destroyed and rebuilt rather than skipped, so a half-built gallery from an interrupted run cannot
-- survive behind an "already there".
local VIVARIUM_VERSION = 1
local MODEL_NAME = "Vivarium"

-- ============================================================================
-- THE BANKS -- authored off the live probe in the header
-- ============================================================================
-- A bank is laid out in MODULES: a row of cases facing -Z, an aisle, a row facing +Z, then a thin
-- gap before the next module. Two rows back onto each other, which is what lets a 105-deep
-- rectangle hold six rows and still have an aisle in front of every case.
local CASE_W = VivariumCase.Width   -- 9
local CASE_D = VivariumCase.Depth   -- 8
local PITCH_X = CASE_W + 1          -- 10 along a row
local AISLE = 10                    -- the walkway the two rows of a module FACE
local MODULE_GAP = 2                -- back to back with the next module
local MODULE_D = CASE_D * 2 + AISLE + MODULE_GAP -- 28

local BANKS = {
	{ name = "West", x0 = -195, x1 = -85, z0 = 365, z1 = 470 },
	{ name = "East", x0 = 70, x1 = 170, z0 = 370, z1 = 430 },
	-- ===== THE THIRD BANK EXISTS BECAUSE THE SECOND ONE LOST A ROW (see RESERVED below) =====
	-- Rectangle 4 of the same 5-stud survey -- x 25..140, z 465..525 -- trimmed on X because 25 is
	-- inside the walking lane: a pad's half-width is 6, so the first centre has to sit at 36 or
	-- more and the bank starts at 40. It is north of the running track rather than across it.
	{ name = "North", x0 = 40, x1 = 140, z0 = 465, z1 = 525 },
}

-- ===== FLAT IS NOT THE SAME AS FREE, AND THE GALLERY'S FIRST BUILD PROVED IT =====
--
-- `occupied` asks whether anything COLLIDABLE stands above `GROUND_CLEAR` here, which is the right
-- question for a lamp post and the wrong one for a running track. `SprintTrack` states every layer
-- by its top face and grows it down -- kerb 0.30, surface 0.44, stripes 0.52, boost pads 0.68 --
-- so all of it is under the 1.4 line and **the whole lane reads as bare lawn**. The east bank's
-- back row came out at z 432 with the running surface at z 419..451, i.e. seven display cases
-- standing in the middle of the sprint lane, and nothing in the boot log said a word.
--
-- It is the fault `HubPlaza`'s own header describes one object over -- the jungle trails are paint
-- too, "so every road on this deck reads as empty ground" -- and the answer is the same: the test
-- cannot be about height, it has to be about OWNERSHIP. A part belonging to one of these models
-- blocks an anchor whatever its height and whether or not it collides.
local RESERVED = { SprintTrack = true, HeraldStation = true, PartyStand = true }

-- Roads are the other flat thing, and they are handled the way HubPlaza handles them rather than by
-- name: a case is a POST -- you walk around it, you do not walk over it -- so it passes its own
-- half-width and is refused anywhere the painted road is nearer than that.
local ZONE_KEY = "Forest"

-- What an anchor has to find free before a case is stood on it. Taller than the case so a low
-- branch over the roof is caught too, and a shade wider than the pad so two neighbours can never
-- both pass on the same stud.
local FOOT = Vector3.new(CASE_W + 1, 19, CASE_D + 1)
local GROUND_CLEAR = 1.4 -- HubPlaza's number, and for its reason

local SLOT_BASE = 2
local SLOT_PER = 4

local TICK = 4

-- ============================================================================
-- STATE
-- ============================================================================
local anchors = {}     -- [i] = { cf = CFrame, bank = string }
local cases = {}       -- [i] = { handles..., ownerId = number, signature = string, rigs = {Model} }
local byUserId = {}    -- [userId] = index
local root = nil

-- ============================================================================
-- PLACEMENT
-- ============================================================================
local function queryParams()
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	-- Creatures walk, so a clearance measured against one is a fact about an instant rather than
	-- about a place -- HubPlaza's constraint 3, and the gallery stands on the same lawn they cross.
	local ignore = { workspace:FindFirstChild("Creatures"), workspace:FindFirstChild("EquippedPets"),
		workspace:FindFirstChild("Eggs"), workspace:FindFirstChild("Bosses"), root }
	local list = {}
	for _, inst in ipairs(ignore) do
		if inst then table.insert(list, inst) end
	end
	p.FilterDescendantsInstances = list
	return p
end

local function worldTop(part)
	local cf, sz = part.CFrame, part.Size
	local hy = math.abs(cf.UpVector.Y) * sz.Y * 0.5
		+ math.abs(cf.RightVector.Y) * sz.X * 0.5
		+ math.abs(cf.LookVector.Y) * sz.Z * 0.5
	return cf.Position.Y + hy
end

--- True if `part` belongs to something whose ground is reserved whatever its height. See RESERVED.
local function isReserved(part)
	local node = part
	while node and node ~= workspace do
		if RESERVED[node.Name] then return true end
		node = node.Parent
	end
	return false
end

local function occupied(cf)
	local box = CFrame.new(cf.Position.X, FOOT.Y * 0.5, cf.Position.Z)
	for _, part in ipairs(workspace:GetPartBoundsInBox(box, FOOT, queryParams())) do
		-- the ownership test FIRST, because it is the one that does not care about height
		if isReserved(part) then
			return true, part
		end
		if part.CanCollide and worldTop(part) > GROUND_CLEAR then
			return true, part
		end
	end
	-- `RoadClearance` measures to the road's painted edge, is negative on it, and answers
	-- `math.huge` where the zone has no jungle layout at all.
	if JungleLayout.RoadClearance(ZONE_KEY, cf.Position.X, cf.Position.Z) <= CASE_W * 0.5 then
		return true, "road"
	end
	return false
end

-- The anchor grid, bank by bank and module by module, front row first. The ORDER is the feature --
-- see point 2 in the header -- so this walks a bank from its south edge northward and a row from
-- its west edge eastward, which is the order a player arriving at the spawn reads them in.
local function layOutAnchors(limit)
	local built, skipped = 0, 0
	for _, bank in ipairs(BANKS) do
		local spanX = bank.x1 - bank.x0
		local cols = spanX // PITCH_X
		-- centre the row in its rectangle rather than hanging it off the west edge
		local padX = (spanX - cols * PITCH_X) * 0.5
		local spanZ = bank.z1 - bank.z0
		local modules = spanZ // MODULE_D
		local padZ = (spanZ - modules * MODULE_D) * 0.5
		for m = 0, modules - 1 do
			local mz = bank.z0 + padZ + m * MODULE_D
			-- ===== BOTH ROWS FACE THE AISLE, WHICH IS THE WHOLE POINT OF HAVING ONE =====
			--
			-- The first cut had the near row facing -Z and the far row +Z, i.e. both facing OUTWARD
			-- with their backs to the ten studs between them. That put the walkway behind the cases
			-- and left the fronts looking at the two-stud gap to the next module -- a gallery whose
			-- every window faces a wall. The near row turns to face +Z and the far row -Z, so the
			-- aisle has a shopfront down both sides and the module gap is back-to-back.
			local rowsHere = {
				{ z = mz + CASE_D * 0.5, yaw = 180 },
				{ z = mz + CASE_D + AISLE + CASE_D * 0.5, yaw = 0 },
			}
			for _, row in ipairs(rowsHere) do
				for c = 0, cols - 1 do
					if built >= limit then
						return built, skipped
					end
					local x = bank.x0 + padX + PITCH_X * (c + 0.5)
					local cf = CFrame.new(x, 0, row.z) * CFrame.Angles(0, math.rad(row.yaw), 0)
					local blocked = occupied(cf)
					if blocked then
						skipped += 1
					else
						built += 1
						anchors[built] = { cf = cf, bank = bank.name }
					end
				end
			end
		end
	end
	return built, skipped
end

-- ============================================================================
-- A CASE
-- ============================================================================
local function slotsFor(rebirths)
	return math.clamp(SLOT_BASE + (rebirths or 0) // SLOT_PER, SLOT_BASE, VivariumCase.MaxSlots)
end

--- The pets that should be standing in `player`'s case, strongest first.
local function topPets(data)
	local n = slotsFor(data.Rebirths)
	local ranked = GameConfig.SortedPetsByPower(data.Pets or {}, data)
	local out = {}
	for i = 1, math.min(n, #ranked) do
		out[i] = ranked[i]
	end
	return out, n
end

--- What has to change before the rigs are worth rebuilding. The slot count and the identity of
-- every pet in it -- the tier and the enchant are in there because both change a rig's look.
local function signature(pets, n)
	local parts = { tostring(n) }
	for _, p in ipairs(pets) do
		table.insert(parts, ("%s:%s:%s"):format(tostring(p.id), tostring(p.tier), tostring(p.enchant)))
	end
	return table.concat(parts, "|")
end

local function clearRigs(case)
	for _, rig in ipairs(case.rigs) do
		rig:Destroy()
	end
	case.rigs = {}
end

local function fillCase(case, data)
	local pets, n = topPets(data)
	local sig = signature(pets, n)
	if sig == case.signature then
		return false
	end
	case.signature = sig
	clearRigs(case)
	for i, pet in ipairs(pets) do
		local slot = case.slots[i]
		local def = GameConfig.GetPetDef(pet.key)
		if slot and def then
			-- ===== BOTH OF THESE ARE OFF, AND THE FIRST ONE IS NOT OPTIONAL =====
			--
			-- `outline` is a `Highlight`, and `PetModel`'s own comment records the budget: Roblox
			-- renders only about THIRTY-ONE at a time, which is why the egg podiums' sixty pets
			-- already pass `outline = false`. A full gallery is up to 360 rigs. Leaving the default
			-- on here would not make the cases prettier -- it would silently delete the outline from
			-- the player's own followers and from 23.2's rented pool, game-wide, by exhausting the
			-- renderer before they asked. The dark `FIELD` back wall is what the rigs read against
			-- instead, and it is in `VivariumCase` for this reason.
			--
			-- `nameplate` is off for a geometry reason rather than a budget one: the plate sits
			-- 3.1 studs over the body, the shelves are 4.6 apart, so a lower shelf's labels would
			-- land in the upper shelf's rigs. The case's own board carries the reading.
			local rig, rigRoot, pieces = PetModel.Build(def, pet.tier,
				{ scale = 1, outline = false, nameplate = false })
			rig.Name = "Specimen" .. i
			local seated = VivariumCase.SeatOnShelf(rig, rigRoot, pieces, slot)
			-- Spun and bobbed by the CLIENT, for the reason `EggPlaza.buildEggFeaturePet` writes
			-- out: a server that CFrames sixty cases' worth of rigs every frame would replicate all
			-- of it at a throttled rate and stutter. `PetFollowClient` already animates anything
			-- carrying this tag.
			rig:SetAttribute("SpinAnchor", seated)
			rig:SetAttribute("SpinSpeed", 0.5)
			rig:SetAttribute("BobHeight", 0.25)
			CollectionService:AddTag(rig, "PetDisplay")
			rig.Parent = case.model
			table.insert(case.rigs, rig)
		end
	end
	return true, n, #pets
end

-- ===== THE ZERO STATE IS THE COMMON CASE, NOT AN EDGE CASE (measured) =====
--
-- The first board this row ever drew read **"0 DNA/s"**, on the owner's own save: nine rebirths,
-- a hundred pets, stage 5 -- and `data.Upgrades.AutoCollect` at **0**. That is not a fault in the
-- arithmetic. `GetAutoCollectAmount` returns exactly 0 until the upgrade is bought, passive DNA in
-- this game comes from nowhere else, and inventing a number here would put the case into an
-- argument with `OfflineService`, which pays out of the same function.
--
-- So the number stays honest and the WORDING changes. A flagship figure reading "0" is read as a
-- broken sign; the same fact spelled out points at the one upgrade that moves it, which is the
-- lesson 15.22 wrote down about Auto Collect in the first place -- a player should never have to
-- pay to find out what something does.
local function drawBoard(case, player, data)
	local board = case.board
	local n = slotsFor(data.Rebirths)
	board.title.Text = ("%s  \u{2022}  R%d"):format(player.DisplayName, data.Rebirths or 0)

	local rate = DNAService.GetAutoCollectAmount(data)
	-- Per SECOND, spelled out, because "DNA" alone on a board in this game reads as a balance.
	board.rate.Text = rate > 0
		and ("\u{1F9EC} %s DNA/s"):format(UITheme.FormatNumber(rate))
		or "\u{1F9EC} no passive income yet"

	-- The income multiplier is on the board because it is the number the COLLECTION drives -- the
	-- equipped pets are most of it -- so it is never zero and it is the figure a case full of
	-- Rainbow Absolons is actually a flex about. Short tokens: the line is 0.22 of the board and
	-- `TextScaled` shrinks the whole string to fit the longest one.
	board.sub.Text = rate > 0
		and ("%d/%d slots \u{00B7} %d pets \u{00B7} \u{00D7}%.1f"):format(
			math.min(#case.rigs, n), n, #(data.Pets or {}), DNAService.GetIncomeMult(data))
		or ("%d/%d slots \u{00B7} %d pets \u{00B7} buy Auto Collect"):format(
			math.min(#case.rigs, n), n, #(data.Pets or {}))
end

local function release(userId)
	local i = byUserId[userId]
	if not i then return end
	byUserId[userId] = nil
	local case = cases[i]
	if case then
		-- BEFORE the Destroy: the lock holds a running break and an open-window timer, both keyed
		-- off this index. Freeing the index without freeing them leaves a heartbeat ticking over a
		-- model that is already gone.
		VivariumLock.Detach(i)
		case.model:Destroy()
		cases[i] = nil
	end
end

local function claim(player)
	if byUserId[player.UserId] then return end
	local idx
	for i = 1, #anchors do
		if cases[i] == nil then
			idx = i
			break
		end
	end
	if not idx then
		-- Only reachable if the anchor count came out under the player count, which is what the
		-- skip branch in `layOutAnchors` can do. Said once, with the number, rather than silently.
		warn(("[Vivarium] no free case for %s -- %d anchors, %d claimed"):format(
			player.Name, #anchors, #Players:GetPlayers()))
		return
	end

	local anchor = anchors[idx]
	local handles = VivariumCase.Build(anchor.cf, ("Case%02d"):format(idx))
	handles.model:SetAttribute("OwnerUserId", player.UserId)
	handles.model:SetAttribute("CaseIndex", idx)
	handles.model:SetAttribute("Bank", anchor.bank)
	handles.model.Parent = root

	local case = {
		model = handles.model,
		slots = handles.slots,
		board = handles.board,
		ownerId = player.UserId,
		signature = nil,
		rigs = {},
	}
	cases[idx] = case
	byUserId[player.UserId] = idx

	local data = PlayerDataService.Get(player)
	if data then
		fillCase(case, data)
		drawBoard(case, player, data)
	else
		case.board.title.Text = player.DisplayName
		case.board.rate.Text = "\u{2026}"
	end

	-- 24.2. Hung after the save is read so the grille arms at the owner's real strength rather than
	-- at R0 and then jumping on the first tick; `SetStrength` in `refresh` keeps it honest after.
	-- A case whose data has not arrived gets the R0 lock, which is the safe way round.
	VivariumLock.Attach(idx, case.model, handles.frame, player.UserId, data and data.Rebirths or 0)

	Telemetry.Custom(player, "VivariumCaseClaimed", idx)
end

-- ============================================================================
-- THE TICK
-- ============================================================================
local function refresh()
	for userId, i in pairs(byUserId) do
		local case = cases[i]
		local player = Players:GetPlayerByUserId(userId)
		if case and player then
			local data = PlayerDataService.Get(player)
			if data then
				fillCase(case, data)
				drawBoard(case, player, data)
				VivariumLock.SetStrength(i, data.Rebirths)
			end
		end
	end
end

-- ============================================================================
-- INIT
-- ============================================================================
function VivariumPlaza.Init()
	local existing = workspace:FindFirstChild(MODEL_NAME)
	if existing then existing:Destroy() end

	root = Instance.new("Model")
	root.Name = MODEL_NAME
	root:SetAttribute("VivariumVersion", VIVARIUM_VERSION)
	root.Parent = workspace

	-- EMPTIED, NOT TRUSTED TO BE EMPTY. `Init` is idempotent by replacement like the plaza's and the
	-- stand's, so it can run twice in one session -- and `layOutAnchors` fills from index 1 upward.
	-- A second run that found FEWER honest spots than the first (a newly built neighbour, a prop
	-- that settled) would otherwise leave the tail of the previous run's list in place, and those
	-- entries point at ground something is now standing on.
	table.clear(anchors)
	local limit = Players.MaxPlayers
	local built, skipped = layOutAnchors(limit)

	PlayerJoin.onEach(claim)
	-- `PlayerRemoving` does NOT unparent the player (`roblox-playerremoving-parent-is-players`), so
	-- the userId is still readable here and the release is keyed off it rather than off the object.
	Players.PlayerRemoving:Connect(function(player)
		release(player.UserId)
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			refresh()
		end
	end)

	print(("[Vivarium] built v%d -- %d anchors of a possible %d (%d blocked), %d..%d slots a case, %ds tick; lock %d+%ds a rebirth, open %ds, reach %d"):format(
		VIVARIUM_VERSION, built, limit, skipped, SLOT_BASE, VivariumCase.MaxSlots, TICK,
		VivariumLock.Base, VivariumLock.PerRebirth, VivariumLock.OpenWindow, VivariumLock.BreakRadius))
end

-- ============================================================================
-- READ-ONLY, for the probe and for 24.2/24.3
-- ============================================================================
function VivariumPlaza.CaseOf(userId)
	local i = byUserId[userId]
	return i and cases[i] or nil, i
end

function VivariumPlaza.AnchorCount()
	return #anchors
end

-- ===== THE ANCHOR LIST IS A FIELD ON PURPOSE, AND IT IS THE PROBE SEAM =====
--
-- `PartyService.PositionOf` is the precedent and 22.5's note says what it bought: a feature whose
-- state is reachable from outside can be verified by one agent on one client, and one that hides it
-- in a closure needs a second player nobody can supply. A gallery is a worse case than a party --
-- fifty-nine of its sixty positions are empty on any server an agent can boot -- so the LAYOUT can
-- only be checked by reading where the anchors are and standing something on them.
--
-- It is the same table `layOutAnchors` fills rather than a copy, because `anchors` is only ever
-- MUTATED and never reassigned -- which is also why `Init` has to empty it (see there). Read it;
-- never write it.
VivariumPlaza.Anchors = anchors

VivariumPlaza.SlotsFor = slotsFor

return VivariumPlaza
