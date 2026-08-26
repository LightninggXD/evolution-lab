-- TrainingDummyModel -- the grotto dummy's geometry, and nothing else (33.21).
--
-- A LEAF. It builds one prop and hands it back; it knows nothing about reps, remotes, cooldowns or
-- who is allowed to hit it. `TrainingDummyService` owns all of that. The split is the one
-- `evolution-lab-small-modules-rule` asks for, and it earns itself here: the seat, the scale and the
-- hitbox are the three things that will be re-measured against a capture, and re-measuring them
-- should not mean opening the payout logic.
--
-- ===== THE ART IS HERS, AND IT ARRIVED WITH A LIVE BACKDOOR IN IT =====
--
-- She dropped an R15 mesh dummy into `Workspace` and asked for it in the game. It carried two
-- scripts, and one of them was armed:
--
--   * `EZConfig` -- an ENABLED server `Script` sitting in `Workspace` doing
--     `require(<NumberPose>.Value)` where the value was the asset id `131988988057913`. That is
--     `evolution-lab-free-model-backdoor`'s signature exactly, and the third time this place has
--     shipped one (see roadmap 32.25 and the `Workspace.Decorations.Waterfall` find).
--   * `Animate` -- the legacy R6 `Animate`, which `waitForChild`s `Torso["Right Shoulder"]`. An R15
--     MeshPart rig has no Motor6D at all, so it yields forever and warns.
--
-- Both were destroyed and the rig was parked in `ServerStorage.SourceProps` with the rest of the raw
-- art, which is also why this module CLONES rather than reparents: nothing in `Workspace` should run,
-- and a clone means a rebuild cannot consume the source.
--
-- ===== WHAT WAS MEASURED, SO THE NUMBERS BELOW ARE NOT TASTE =====
--
-- Taken on the built Edit world, 2026-08-27:
--   * the rig's TRUE world AABB is 4.74 x 5.52 x 4.04 -- and note `GetExtentsSize` reported
--     5.5 x 4.5 x 3.0 for the same rig, because its root sits at yaw -25 and every model box getter
--     is PIVOT-frame (`roblox-model-box-getters-are-pivot-frame`). The 5.52 is the height.
--   * the grotto floor's top face is at y **0.20** at every x across the room (`GrottoFloor`, laid
--     0.2 clear of `WorldShell.Floor` to stop the two coplanar surfaces z-fighting).
--   * a 4x6x4 humanoid box at the secret trigger `(291, 6, -281)` reports **0** solid parts, and
--     must keep reporting 0 -- `SecretsService.reportBlocked` prints the secret UNREACHABLE
--     otherwise. An 8-stud box at the seat below reports 0 parts of any kind.

local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)

local TrainingDummyModel = {}

local SOURCE_FOLDER = "SourceProps"
local SOURCE_NAME = "TrainingDummy"
TrainingDummyModel.FolderName = "Training"
TrainingDummyModel.ModelName = "TrainingDummy"

-- ===== THE SCALE, AGAINST THE ONE RULER THIS GAME HAS =====
-- `evolution-lab-scale-is-the-body`: 8.4 studs is the player. Her rig is 5.52, i.e. two thirds of a
-- player and reading as a desk toy in a room with 20 studs of headroom. x2 puts it at **11.0 studs**
-- -- a head taller than the player who punches it, which is what a heavy bag should be, and still
-- 9 studs clear of the roof.
local SCALE = 2.0

-- ===== THE SEAT, DERIVED AND NEVER TYPED =====
-- Off `GameConfig.Secrets[1].offset`, for the reason 33.7 split `offset` from `triggerOffset` in the
-- first place: every piece of this room is measured from that one anchor, so a hand-typed world
-- position is a second source of truth that drifts the first time the grotto moves.
--
-- x -15 puts it against the west half of the room (inner wall at x 269; the scaled body is 9.5 wide,
-- so 276 leaves 2.3 studs of daylight behind it and the player can still walk round the front).
-- z +6 puts it level with the doorway rather than back beside the plinth (which occupies
-- z -300..-288) -- so it is the first thing you see when you come through the water, and the plinth
-- keeps the back of the room.
--
-- IT CLEARS THE SECRET TRIGGER, and here is the measurement rather than the estimate: seated and
-- scaled, the body spans x 271.8..280.2 and the (grown) hitbox spans x 270.7..281.3, against a
-- trigger box of x 285..297 -- so 4.8 studs of daylight on the body and 3.7 on the hitbox. The
-- authoritative check is not the arithmetic but the overlap test, and it reports **0 solid parts**
-- in the trigger after the build.
--
-- That is the number not to spend. A collidable body inside that box makes the secret unreachable
-- and prints a boot warning nobody would ever connect to a dummy.
local SEAT_OFFSET = Vector3.new(-15, 0, 6)

-- Looking at +Z, i.e. out through the mouth at whoever walks in -- and the `biceps` Decal she put on
-- it is on `Face = Front`, so this is the yaw that shows it. A part's LookVector is -Z by default,
-- hence the half turn rather than a quarter (`roblox-yaw-lowers-atan2-bearing` is the standing note
-- on getting this backwards).
local YAW = math.pi

-- The hitbox is grown past the body on purpose, the same way `CreatureService` grows a creature's:
-- a click has to land on the silhouette the player SEES, and a mesh rig's arms and base are thinner
-- than they look. 1.25 is the low end of that file's 1.3..1.7 clamp -- a dummy stands still, so it
-- needs no lead.
local HITBOX_GROW = 1.25

-- ===== WHY EVERY PART IS ANCHORED AND WELDED TO NOTHING =====
-- The rig arrived as a half-jointed R15 shell (10 parts, 2 WeldConstraints) whose Humanoid we
-- removed. Left unanchored it would collapse into a pile the first time a player walked into it, and
-- welding it properly would buy a physics assembly this prop has no use for -- it never moves except
-- for the recoil below, which is driven by `PivotTo` and works on anchored parts.
local function freeze(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- CanQuery must stay TRUE on the visible shell. `roblox-canquery-ignored-when-collides`
			-- is the trap: the whole reason a dozen sweeps in this repo reported open air where a
			-- prop stands is that the visible half of a model is invisible to spatial queries. A
			-- dummy nothing can raycast is a dummy the swing animation will not point at.
			d.CanQuery = true
		elseif d:IsA("WeldConstraint") then
			-- dead weight once everything is anchored, and a weld between two anchored parts is a
			-- warning in the output on some builds
			d:Destroy()
		end
	end
end

-- The true world AABB. `GetBoundingBox`/`GetExtentsSize` cannot be used for this -- both are
-- PIVOT-frame and this rig's root sits at yaw -25, which is what made the first measurement read
-- 5.5 x 4.5 x 3.0 for a body that is really 4.74 x 5.52 x 4.04.
local function worldBox(model)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, sz = d.CFrame, d.Size
			local ex = Vector3.new(
				math.abs(cf.RightVector.X) * sz.X / 2 + math.abs(cf.UpVector.X) * sz.Y / 2
					+ math.abs(cf.LookVector.X) * sz.Z / 2,
				math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2
					+ math.abs(cf.LookVector.Y) * sz.Z / 2,
				math.abs(cf.RightVector.Z) * sz.X / 2 + math.abs(cf.UpVector.Z) * sz.Y / 2
					+ math.abs(cf.LookVector.Z) * sz.Z / 2)
			lo = Vector3.new(math.min(lo.X, cf.Position.X - ex.X), math.min(lo.Y, cf.Position.Y - ex.Y),
				math.min(lo.Z, cf.Position.Z - ex.Z))
			hi = Vector3.new(math.max(hi.X, cf.Position.X + ex.X), math.max(hi.Y, cf.Position.Y + ex.Y),
				math.max(hi.Z, cf.Position.Z + ex.Z))
		end
	end
	return lo, hi
end

-- Where the room's floor actually is under a spot, rather than where the config says y is. The
-- secret's own offset carries a Y of 6 because a 12-stud trigger centred on the floor is half buried
-- in it -- that number is about the TRIGGER, and a prop seated at it would float six studs.
local function floorAt(x, z, fallbackY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	-- from inside the room, under the roof (whose underside is y 20) and above head height
	local hit = workspace:Raycast(Vector3.new(x, 15, z), Vector3.new(0, -30, 0), params)
	return hit and hit.Position.Y or fallbackY
end

-- The anchor this whole prop is measured from. Returns nil when the zone has no secret, which is
-- every zone but Forest -- the caller treats that as "no dummy here", not as an error.
function TrainingDummyModel.SeatFor(zoneKey, cx)
	for _, secret in ipairs(GameConfig.Secrets or {}) do
		if secret.zoneKey == zoneKey and secret.offset then
			local centre = Vector3.new(cx or 0, 0, 0) + secret.offset
			return Vector3.new(centre.X, 0, centre.Z) + SEAT_OFFSET, centre
		end
	end
	return nil
end

-- ===== THE NAMEPLATE =====
-- Static text, and that is a constraint rather than a shortcut: a BillboardGui in the world is seen
-- by EVERY player, so it cannot show one player's rep count. The per-player number lives on the HUD
-- bar, which is the only place it can be honest.
local function addPlate(model, host, gate)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TrainingPlate"
	billboard.Size = UDim2.new(0, 190, 0, 54)
	-- HALF-SIZE, and every ExtentsOffset number in this repo is double what it reads as
	-- (`roblox-extentsoffset-is-half-size`). StudsOffset is the honest one, so it is what is used.
	billboard.StudsOffset = Vector3.new(0, 7.5, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
	billboard.Parent = host

	UITheme.Label(billboard, {
		name = "TextLabel",
		text = ("\u{1F4AA} TRAINING DUMMY\n+%d reps \u{2022} needs %d rebirth")
			:format(GameConfig.TrainingDummyReps, gate),
		minTextSize = 11,
		maxTextSize = 18,
	})
	return billboard
end

-- ===== BUILD =====
--
-- Returns `model, hitbox` or nil plus a reason. IDEMPOTENT: it destroys any dummy already standing
-- in its folder first, so a second call cannot leave two, which is the trap `MapWaterfall.Seat` and
-- `keepShellLoaded` both carry warnings about.
function TrainingDummyModel.Build(zoneKey, cx, parent)
	local source = ServerStorage:FindFirstChild(SOURCE_FOLDER)
	source = source and source:FindFirstChild(SOURCE_NAME)
	if not source then
		return nil, ("no %s.%s to clone -- the rig was never parked"):format(SOURCE_FOLDER, SOURCE_NAME)
	end

	local seat, centre = TrainingDummyModel.SeatFor(zoneKey, cx)
	if not seat then return nil, ("no secret anchor in %s"):format(tostring(zoneKey)) end

	local existing = parent:FindFirstChild(TrainingDummyModel.ModelName)
	if existing then existing:Destroy() end

	local model = source:Clone()
	model.Name = TrainingDummyModel.ModelName
	freeze(model)

	-- A root to measure and pivot from. The rig arrived with NO PrimaryPart, and the client's
	-- `nearestTarget` reads `model.PrimaryPart or model:FindFirstChild("Body")` -- so without this
	-- the dummy is invisible to auto-attack however close you stand.
	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then return nil, "the rig has no BasePart" end
	model.PrimaryPart = root

	-- SCALE FIRST, DRESS SECOND (`roblox-scaleto-scales-prompt-reach`). `ScaleTo` scales a
	-- ClickDetector's MaxActivationDistance along with everything else, so a hitbox built before
	-- this line would have its reach quietly multiplied and a plate built before it would be sized
	-- against the small rig.
	model:ScaleTo(SCALE)

	-- Face the mouth, then settle onto the floor by MEASUREMENT rather than arithmetic. Two pivots:
	-- the first orients and puts it roughly right, the second corrects by the gap the world AABB
	-- actually shows -- which is the only way to seat a rig whose pivot is not its centre and whose
	-- root is off-axis.
	model:PivotTo(CFrame.new(seat) * CFrame.Angles(0, YAW, 0))
	local groundY = floorAt(seat.X, seat.Z, centre.Y)
	local lo = select(1, worldBox(model))
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - lo.Y, 0))

	local low, high = worldBox(model)
	local size = high - low
	local mid = (low + high) / 2

	-- ===== THE HITBOX, THE SAME SHAPE `CreatureService` USES =====
	-- Invisible, non-colliding, QUERYABLE, and it carries the ClickDetector. It is a separate part
	-- rather than a detector on the torso because the torso of this rig is 4 studs across inside an
	-- 11-stud silhouette -- clicking the visible arms would miss.
	local hitbox = Instance.new("Part")
	hitbox.Name = "HitBox"
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Transparency = 1
	hitbox.Size = size * HITBOX_GROW
	hitbox.CFrame = CFrame.new(mid)
	hitbox.Parent = model

	-- ===== THE TWO REPLICATED ATTRIBUTES THE CLIENT NEEDS =====
	--
	-- `Health` is the LIVENESS FLAG, not a health pool. `CombatClient.nearestTarget` skips any model
	-- whose `Health` attribute is missing or <= 0 -- that filter exists because a corpse is nearer
	-- than the thing that killed it, and because `deathBurst` parents confetti into the same folders.
	-- A dummy never dies, so this is set once and never written again.
	model:SetAttribute("Health", 1)
	-- The gate, published so the client can grey it out and drop it from auto-attack. NOT
	-- authoritative -- the server re-derives it on every blow -- and it reuses the raised-creature
	-- attribute NAME on purpose, because `creatureLocked()` already reads exactly that and needs no
	-- edit to lock this too.
	model:SetAttribute("MinRebirths", GameConfig.TrainingDummyMinRebirths)

	addPlate(model, root, GameConfig.TrainingDummyMinRebirths)

	model.Parent = parent
	return model, hitbox, {
		seat = Vector3.new(mid.X, low.Y, mid.Z),
		size = size,
		scale = SCALE,
	}
end

-- ===== THE RECOIL =====
--
-- The whole feel of a `+1` game is that the thing you hit reacts, and this is the cheapest honest
-- version: a short backward tilt off the base pivot and out again.
--
-- ONE COROUTINE AT A TIME, guarded by the returned closure's own state. Overlapping recoils would
-- each restore the pivot they captured, and the second one to finish would put the model back where
-- the first one had already moved it -- the same class of fault as
-- `probe-restore-must-be-read-back`. It is NOT a Heartbeat: `evolution-lab-streaming-and-scale` asks
-- for one gated loop per animated SET, and a set that animates for 0.18 s every quarter second
-- should not hold a connection open for the life of the server.
function TrainingDummyModel.Recoil(model)
	local base = model:GetPivot()
	local busy = false
	return function()
		if busy or not model.Parent then return end
		busy = true
		task.spawn(function()
			local T = 0.18
			local t0 = os.clock()
			while model.Parent do
				local t = (os.clock() - t0) / T
				if t >= 1 then break end
				-- out and back in one sine, so it never has to be un-tilted separately
				local a = math.sin(t * math.pi) * math.rad(11)
				model:PivotTo(base * CFrame.Angles(-a, 0, 0))
				task.wait()
			end
			if model.Parent then model:PivotTo(base) end
			busy = false
		end)
	end
end

return TrainingDummyModel
