--[==[
	VivariumSteal -- what a thief actually takes out of an open case, and what it costs the owner
	(24.3).

	===== THE ROW NAMES ITS OWN MECHANIC, AND IT IS NOT THE ONE THE PHASE HEADER WARNS ABOUT =====

	Phase 24's header is about the genre risk of a steal, and it is right to be: a game where another
	player can take your pet is a different game, and this one has spent thirty-five phases teaching
	that nothing is ever lost. **This row is deliberately not that.** Its own words are *"the income
	stream, not the save item"* -- carrying a specimen out diverts a share of that case's passive DNA
	for a window, and *"the original never leaves the owner's collection"*.

	So read what this file can and cannot do, because it is the whole argument for shipping it:

	  * `data.Pets` is never written. Not moved, not marked, not copied. Nothing in this file has a
	    reference to a save's pet list at all -- the specimen it carries is the DISPLAY RIG the
	    plaza built, and the rig goes back on the shelf when the carry resolves.
	  * The owner keeps their case, their slots, their collection and their rank. What they lose is
	    a **share of a rate, for five minutes**, and it is paid to the thief rather than burned.
	  * A player who never goes near the gallery cannot lose anything to this file at all.

	The drama is real and the loss is not permanent, which is exactly what the row asked for.

	===== THE STREAM IS `GetAutoCollectAmount`, WHICH IS 0 MORE OFTEN THAN YOU WOULD GUESS =====

	24.1 settled what "that plot's passive DNA" means and paid for the answer: the case board states
	`DNAService.GetAutoCollectAmount(data)`, because that is the only passive DNA this game has and
	`OfflineService` pays out of the same function -- inventing a second rate here would put the two
	in an argument. That decision carries straight into this row: the diversion is a share of the
	owner's auto-collect, taken at the moment it is paid, in `DNAService`'s own per-second loop.

	**And that number is 0 until the AutoCollect upgrade is bought** -- it was 0 on the owner's own
	nine-rebirth save when 24.1 measured it. A steal off a case whose board reads *"no passive
	income yet"* therefore pays exactly nothing, and that is correct rather than broken: the board
	is the target-selection surface, it states the rate in public, and a thief who reads it before
	spending sixty seconds on a lock is a thief playing the game properly. It is 23.2's rule about
	rarity one object over -- the flex IS the information a raider acts on.

	===== THE SHAPE OF ONE STEAL =====

	    the lock is broken (24.2)      -- the case stands open for OPEN_WINDOW seconds
	    F on the case                  -- the best specimen standing in it comes off the shelf
	    carry it ESCAPE_DIST studs     -- CARRY_LIMIT seconds to get clear of the case
	    the diversion runs             -- SHARE of the owner's passive DNA, for WINDOW seconds

	Four numbers, and each one is a decision:

	  * `SHARE` **0.25**. A quarter is enough to be worth a lock break and small enough that an
	    owner who was farming through it still out-earns the thief on their own case. It is a
	    TRANSFER, not a burn -- every DNA the owner does not receive is received by the thief -- so
	    the economy's total is untouched and `evolution-lab-idle-income-runaway` stays satisfied.
	  * `WINDOW` **300 s**. Long enough to be felt (the owner's HUD tile drops for five minutes),
	    short enough that a player who logs off angry has it back before they log in again.
	  * `CARRY_LIMIT` **45 s**, the same as the lock's open window on purpose: a thief cannot hold a
	    specimen hostage, and 24.4's clip -- the speed drop, the drop-on-hit -- has a fixed length
	    to be designed against.
	  * `ESCAPE_DIST` **110 studs**, measured from the case's own pad. The banks are 100-110 wide,
	    so it means "out of this bank", which is the reading of *"carrying a specimen out"* that a
	    player can see themselves doing.

	===== WHY THERE IS ONE PROMPT AND NOT SIX =====

	A case has six slots and the obvious build puts a prompt on each, so a thief picks the specimen.
	Two things kill it. The top shelf sits **12.44 studs** over the pad, and
	`roblox-a-prompt-off-screen-is-a-dead-prompt` is exactly that fault: reach is half the rule, and
	a prompt above the top of the screen when you are standing under it is dead however close you
	are. And the choice buys nothing -- the diversion is a share of the CASE's rate, so which rig
	you carry does not change the payout by a single DNA.

	So it is one prompt, low and inside the case, and it takes the best specimen standing there. It
	is on **F**, not E, and that is not cosmetic: `Exclusivity` is per BUTTON, so a take prompt on E
	and the lock's prompt on E would hide each other, and the one the player wants is whichever
	happens to be nearer. Different key, both visible, no ambiguity.

	===== THE SEAMS, PUT HERE ON PURPOSE FOR 24.4 AND 24.5 =====

	  * **`VivariumSteal.DropCarry(player, reason)`** is 24.4's single seam. *"Anyone can hit the
	    thief to drop it"* is one call to this function from the damage path, and everything else
	    the row lists (the speed drop, the disabled items, the kill feed) hangs off `Carries`.
	  * **`VivariumLock.CanTarget`** is 24.5's, and it is checked here too -- so every anti-grief
	    clause added to that one function guards the lock AND the take, with no second copy.
	  * **`VivariumSteal.Step(dt)` takes its own delta**, which is 24.2's lesson repeated: a probe
	    drives 45 synthetic seconds of carry and 300 of diversion in one call instead of waiting
	    them out. A timer feature that can only be verified by waiting is a feature that will not
	    be verified.
	  * `Carries` and `Diverts` are FIELDS, for the reason `VivariumPlaza.Anchors` is one.

	===== WHAT THIS FILE DOES NOT REQUIRE, AND WHY IT MATTERS =====

	`DNAService` requires this module (it is the one place that pays passive DNA), so this module
	must not require `DNAService` -- and it does not need to. The owner's current rate is read off
	`data.__autoPerSec`, which that same loop stamps every second for the HUD tile. It reaches the
	plaza through a registered provider rather than a require for the same reason.
]==]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = RS.Remotes
local UITheme = require(RS.Modules.UITheme)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local Telemetry = require(ServerScriptService.Telemetry)
local VivariumCase = require(script.Parent.VivariumCase)
local VivariumLock = require(script.Parent.VivariumLock)

local VivariumSteal = {}

-- ============================================================================
-- THE NUMBERS -- see the header for what each one is defending
-- ============================================================================
local SHARE = 0.25
local WINDOW = 300
local CARRY_LIMIT = 45
local ESCAPE_DIST = 110

local PROMPT_DISTANCE = 12
-- Inside the case and low, so it is on screen from the aisle and never above the player's head.
-- The lock's prompt is at the door on E; this one is a step further in on F.
local PROMPT_Y = VivariumCase.PadTop + 3.4

-- Where the specimen rides while it is being carried. Off the character's root rather than off the
-- head: `evolution-lab-body-settles-late` and `evolution-lab-scale-is-the-body` both say a body's
-- limbs are still growing after `CharacterAdded`, and the root is the one part whose size is a fact
-- about the stage rather than about the frame you asked in.
local CARRY_LIFT = 1.5
local CARRY_AHEAD = 2.6

-- ============================================================================
-- STATE
-- ============================================================================
-- [caseIndex] = { model, ownerId, centre, prompt }
local cases = {}
-- [caseIndex] = { thiefId, rig, label, held, height }
local carries = {}
-- [caseIndex] = { thiefId, left, paid }
local diverts = {}
local byOwner = {}    -- [ownerUserId] = caseIndex
local busyThief = {}  -- [thiefUserId] = caseIndex, for a carry
local provider = nil  -- set by VivariumPlaza.Init; see Bind
local heartbeat = nil

local function notify(userId, kind, message)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		Remotes.Notify:FireClient(player, { kind = kind, message = message })
	end
end

--- Flat distance from a player to a point, or `math.huge` while they have no body. The Y is thrown
--- away for the reason the lock throws it away: the gallery is on a lawn and a thief on a terrace
--- above it is not further from the case in any sense a player would recognise.
local function distanceTo(player, centre)
	local char = player and player.Character
	local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
	if not root then return math.huge end
	local p = root.Position
	return math.sqrt((p.X - centre.X) ^ 2 + (p.Z - centre.Z) ^ 2)
end

local function ensureLoop()
	if heartbeat then return end
	heartbeat = RunService.Heartbeat:Connect(function(dt)
		VivariumSteal.Step(dt)
	end)
end

--- Ask the plaza to redraw one case NOW. The board is this row's only surface and the tick is 4
--- seconds: a theft whose sign arrives four seconds late has already stopped being a theft anybody
--- watched. Measured -- the first cut relied on the tick and the board read "3/4 slots" through the
--- whole carry, never once saying who was running with it.
local function redraw(index)
	if provider and provider.redraw then
		provider.redraw(index)
	end
end

local function mmss(seconds)
	local s = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(s // 60, s % 60)
end

-- ============================================================================
-- THE PROMPT
-- ============================================================================
--- What the case's take prompt should say right now. `ActionText` is a property of the PART, so
--- there is no per-player version of it -- 24.2's header says the same thing about the lock -- and
--- the specific refusal a presser gets is said back through `Remotes.Notify` instead.
local function paintPrompt(index)
	local case = cases[index]
	if not case or not case.prompt then return end
	local open = case.model:GetAttribute("LockOpen") == true
	local label = case.model:GetAttribute("TopSpecimen")
	local carry = carries[index]

	if carry then
		case.prompt.Enabled = false
		return
	end
	case.prompt.Enabled = open and label ~= nil
	case.prompt.ActionText = label and ("Take %s"):format(label) or "Take a specimen"
end

-- ============================================================================
-- THE DIVERSION
-- ============================================================================
local function startDivert(index, thiefId)
	local case = cases[index]
	if not case then return end
	diverts[index] = { thiefId = thiefId, left = WINDOW, paid = 0 }
	ensureLoop()
	redraw(index)

	-- The rate the owner is actually being paid, read off the stamp `DNAService` leaves every
	-- second for the HUD tile rather than by requiring that service back (see the header).
	local owner = Players:GetPlayerByUserId(case.ownerId)
	local ownerData = owner and PlayerDataService.Get(owner)
	local rate = (ownerData and ownerData.__autoPerSec or 0) * SHARE

	if rate > 0 then
		notify(thiefId, "reward", ("Clean getaway -- %s DNA/s diverted to you for %s."):format(
			UITheme.FormatNumber(rate), mmss(WINDOW)))
	else
		-- Said plainly rather than pretending: this case had nothing passive to divert, and the
		-- board said so before the lock was ever touched.
		notify(thiefId, "error", ("Clean getaway -- but this case has no passive income to divert."))
	end
	notify(case.ownerId, "error", ("\u{1FA78} A specimen was carried out -- %d%% of your passive DNA for %s."):format(
		SHARE * 100, mmss(WINDOW)))

	local thief = Players:GetPlayerByUserId(thiefId)
	if thief then
		Telemetry.Custom(thief, "VivariumStealLanded", index)
	end
end

local function endDivert(index, quiet)
	local d = diverts[index]
	if not d then return end
	diverts[index] = nil
	local case = cases[index]
	if quiet or not case then return end
	redraw(index)
	notify(case.ownerId, "party", "Your passive DNA is yours again.")
	if d.paid > 0 then
		notify(d.thiefId, "party", ("The stream dried up -- %s DNA in all."):format(
			UITheme.FormatNumber(d.paid)))
	end
end

-- ============================================================================
-- THE CARRY
-- ============================================================================
--- Put the specimen back on its shelf and forget the carry. `reason` is what the thief is told;
--- pass nil for a silent end (the case itself is going away).
local function endCarry(index, reason, landed)
	local carry = carries[index]
	if not carry then return end
	carries[index] = nil
	busyThief[carry.thiefId] = nil
	if carry.rig then
		carry.rig:Destroy()
	end
	-- The rig is rebuilt by the plaza rather than re-seated here: it owns the shelf, the signature
	-- and the ordering, and a specimen put back by a second author would drift from the one the
	-- next refresh draws.
	if provider and provider.restore then
		provider.restore(index)
	end
	paintPrompt(index)
	if reason and not landed then
		notify(carry.thiefId, "error", reason)
		local case = cases[index]
		if case then
			notify(case.ownerId, "party", ("Your %s is back on its shelf."):format(carry.label or "specimen"))
		end
	end
end

--- 24.4's seam: anything that should knock a specimen out of a thief's hands calls this.
function VivariumSteal.DropCarry(player, reason)
	local index = player and busyThief[player.UserId]
	if not index then return false end
	endCarry(index, reason or "You dropped the specimen.")
	return true
end

--- The prompt's handler, and the one entry point a probe drives. Every refusal answers the presser
--- rather than failing silently -- a door that does nothing and says nothing reads as broken.
function VivariumSteal.Take(index, player)
	local case = cases[index]
	if not case or not player then return false, "no case" end

	if player.UserId == case.ownerId then
		notify(player.UserId, "error", "You cannot rob your own case.")
		return false, "owner"
	end
	-- The SAME gate the lock uses, so 24.5's clauses land on both halves of the steal at once.
	local allowed, why = VivariumLock.CanTarget(player, case.ownerId)
	if not allowed then
		notify(player.UserId, "error", why or "You cannot target this case.")
		return false, "cannotTarget"
	end
	if case.model:GetAttribute("LockOpen") ~= true then
		notify(player.UserId, "error", "The case is locked -- break the lock first.")
		return false, "locked"
	end
	if carries[index] then
		notify(player.UserId, "error", "Somebody is already carrying a specimen from this case.")
		return false, "carrying"
	end
	if diverts[index] then
		notify(player.UserId, "error", "This case is already being drained.")
		return false, "diverting"
	end
	if busyThief[player.UserId] then
		notify(player.UserId, "error", "You are already carrying a specimen.")
		return false, "handsFull"
	end

	local rig, label = nil, nil
	if provider and provider.take then
		rig, label = provider.take(index)
	end
	if not rig then
		notify(player.UserId, "error", "There is nothing on the shelves.")
		return false, "empty"
	end

	-- ===== THE TAG COMES OFF, AND IT IS NOT OPTIONAL =====
	-- `PetFollowClient` places every model tagged `PetDisplay` at its `SpinAnchor` on RenderStepped.
	-- A carried rig that kept the tag would be dragged back onto the shelf by every client in the
	-- server sixty times a second, on top of whatever the server writes. The tag goes, the rig is
	-- destroyed when the carry ends, and the plaza builds a fresh tagged one on the shelf.
	game:GetService("CollectionService"):RemoveTag(rig, "PetDisplay")
	rig:SetAttribute("SpinAnchor", nil)
	rig.Name = "CarriedSpecimen"

	local size = rig:GetExtentsSize()
	carries[index] = {
		thiefId = player.UserId,
		rig = rig,
		label = label,
		held = 0,
		height = size.Y,
	}
	busyThief[player.UserId] = index
	paintPrompt(index)
	ensureLoop()
	-- AFTER the carry is registered, and that ordering is the whole point: `provider.take` above
	-- already redrew the case to open the gap on the shelf, but it ran before this table knew
	-- anything, so that redraw could not name the thief. This one can.
	redraw(index)

	notify(player.UserId, "party", ("You lifted %s -- get %d studs clear within %ds."):format(
		label or "a specimen", ESCAPE_DIST, CARRY_LIMIT))
	notify(case.ownerId, "error", ("\u{1F513} %s is carrying %s out of your case!"):format(
		player.DisplayName, label or "a specimen"))
	Telemetry.Custom(player, "VivariumSpecimenTaken", index)
	return true
end

-- ============================================================================
-- ATTACH / DETACH -- called by VivariumPlaza on a claim and a release
-- ============================================================================
function VivariumSteal.Attach(index, model, frame, ownerId)
	VivariumSteal.Detach(index)

	local anchor = Instance.new("Part")
	anchor.Name = "TakeAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = frame * CFrame.new(0, PROMPT_Y, 0)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakePrompt"
	prompt.ObjectText = "Specimen"
	prompt.ActionText = "Take a specimen"
	-- A hold, unlike the lock's press: taking something out of somebody's case should not be
	-- possible by walking past with a finger on a key.
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- See the header: a different BUTTON is what lets this and the lock's prompt both be visible.
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = false
	prompt.Parent = anchor

	cases[index] = {
		model = model,
		ownerId = ownerId,
		centre = frame.Position,
		prompt = prompt,
	}
	byOwner[ownerId] = index

	prompt.Triggered:Connect(function(player)
		VivariumSteal.Take(index, player)
	end)
	-- The lock owns `LockOpen`; this is the only thing that has to happen when it moves, so it is
	-- read off the attribute rather than through a require in either direction.
	model:GetAttributeChangedSignal("LockOpen"):Connect(function()
		paintPrompt(index)
	end)
	model:GetAttributeChangedSignal("TopSpecimen"):Connect(function()
		paintPrompt(index)
	end)
	paintPrompt(index)
end

function VivariumSteal.Detach(index)
	local case = cases[index]
	endCarry(index, nil)
	endDivert(index, true)
	if case then
		byOwner[case.ownerId] = nil
	end
	cases[index] = nil
end

-- ============================================================================
-- THE PAYOUT SEAM -- called once a second by DNAService, for every player
-- ============================================================================
--- How much of `amount` the owner actually keeps. The thief's share is credited here, so the two
--- halves of the transfer can never disagree: there is exactly one subtraction and one addition and
--- they are the same number.
---
--- It is a TRANSFER and not a burn, which is why the thief's side is a `Source` and the owner's is
--- simply a smaller `autoCollect` accrual rather than a `Sink` -- inventing a sink here would make
--- the economy report show DNA being destroyed that never was.
function VivariumSteal.Split(player, amount)
	local index = player and byOwner[player.UserId]
	local d = index and diverts[index]
	if not d or amount <= 0 then return amount end

	local thief = Players:GetPlayerByUserId(d.thiefId)
	if not thief then
		-- A thief who left the server stops being paid immediately. The owner gets the whole
		-- stream back rather than having a quarter of it vanish into nobody.
		endDivert(index)
		return amount
	end
	local tdata = PlayerDataService.Get(thief)
	if not tdata then return amount end

	local take = amount * SHARE
	tdata.DNA += take
	d.paid += take
	Telemetry.Accrue(thief, "Source", Telemetry.Currency.DNA, take, Telemetry.Tx.Gameplay, "vivariumSteal")
	PlayerDataService.UpdateLeaderstats(thief)
	return amount - take
end

--- The line the case board shows while a steal is running, or nil. The board is the only surface
--- this row draws on: `MainUI` is at its 200-local cap (`evolution-lab-mainui-register-limit`), and
--- 22.5's note is that a feature with no HUD tile is a feature one agent can still test.
function VivariumSteal.BoardNote(index)
	local carry = carries[index]
	if carry then
		local thief = Players:GetPlayerByUserId(carry.thiefId)
		return ("\u{1F513} %s is running with %s"):format(
			thief and thief.DisplayName or "somebody", carry.label or "a specimen")
	end
	local d = diverts[index]
	if d then
		local thief = Players:GetPlayerByUserId(d.thiefId)
		return ("\u{1FA78} %s is draining %d%% \u{00B7} %s"):format(
			thief and thief.DisplayName or "somebody", SHARE * 100, mmss(d.left))
	end
	return nil
end

-- ============================================================================
-- THE STEP
-- ============================================================================
--- One frame of every carry and every diversion. Exposed with its own delta so a probe can drive
--- 45 seconds of carry or 300 of diversion inside a single call -- see the header.
function VivariumSteal.Step(dt)
	local busy = false

	for index, carry in pairs(carries) do
		busy = true
		local case = cases[index]
		local thief = Players:GetPlayerByUserId(carry.thiefId)
		local char = thief and thief.Character
		local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")

		if not case then
			endCarry(index, nil)
		elseif not thief then
			endCarry(index, nil)
		elseif not root or (humanoid and humanoid.Health <= 0) then
			-- Dying drops it. 24.4 turns this into the clip -- the speed drop and anyone being able
			-- to hit the thief -- but the consequence is already here so a death cannot carry a
			-- specimen into the respawn.
			endCarry(index, "You dropped the specimen.")
		else
			carry.held += dt
			if carry.rig and carry.rig.Parent then
				carry.rig:PivotTo(root.CFrame
					* CFrame.new(0, root.Size.Y * 0.5 + CARRY_LIFT + carry.height * 0.5, -CARRY_AHEAD))
			end
			if distanceTo(thief, case.centre) >= ESCAPE_DIST then
				endCarry(index, nil, true)
				notify(carry.thiefId, "reward", ("You got clear with %s."):format(carry.label or "a specimen"))
				startDivert(index, carry.thiefId)
			elseif carry.held >= CARRY_LIMIT then
				endCarry(index, "You ran out of time -- the specimen slipped back.")
			end
		end
	end

	for index, d in pairs(diverts) do
		busy = true
		d.left -= dt
		if d.left <= 0 then
			endDivert(index)
		end
	end

	-- ONE GATED LOOP, the same rule the lock states: it disconnects the moment nothing is being
	-- carried and nothing is being drained, so sixty idle cases cost no per-frame work at all.
	if not busy and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- ============================================================================
-- THE PROVIDER -- how this file reaches the plaza without requiring it
-- ============================================================================
--- `VivariumPlaza.Init` registers two functions:
---   take(index)    -> rig, label   -- lifts the best specimen off its shelf and marks the slot out
---   restore(index) -- clears the out slot and redraws the case
---   redraw(index)  -- redraws the case where it stands, changing nothing
---
--- A require in this direction would be a cycle: the plaza requires this file to hang the prompt,
--- and `DNAService` requires this file to split the payout while the plaza requires `DNAService`.
--- Two functions registered at boot is the cheapest way through, and it is the same shape 22.5 used
--- for `PartyService.PositionOf`.
function VivariumSteal.Bind(p)
	provider = p
end

VivariumSteal.Share = SHARE
VivariumSteal.Window = WINDOW
VivariumSteal.CarryLimit = CARRY_LIMIT
VivariumSteal.EscapeDistance = ESCAPE_DIST
VivariumSteal.Carries = carries -- probe seams, for the reason `VivariumPlaza.Anchors` is one
VivariumSteal.Diverts = diverts
VivariumSteal.Cases = cases
-- The owner index in particular, because `Split` is reached through it: a probe with ONE client has
-- to be able to see that the payout seam is looking the case up by the right player.
VivariumSteal.ByOwner = byOwner

return VivariumSteal
