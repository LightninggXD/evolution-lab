-- ChestService -- the relic chest at the end of the passage behind the waterfall (34.53 + 34.58).
--
-- ===== WHAT THIS OWNS, AND THE MUCH LARGER LIST OF WHAT IT DOES NOT =====
--
-- It owns a PROP and a CLOCK. It stands the owner's own 3D chest at the back of the grotto, puts a
-- ProximityPrompt on it, and remembers when each player last opened it. That is all.
--
-- It owns NO roll, NO table, NO currency and NO second cooldown. Opening the chest is exactly two
-- calls into `RelicService`, in this order and with nothing between them:
--
--     RelicService.GiveChest(player, 1)          -- the world hands over an UNOPENED chest
--     RelicService.HandleOpenChest(player, "banked")   -- and the forge is what opens it
--
-- `GiveChest`'s own header names this seam -- *"the seam for every future source -- boss drops,
-- hidden passages, a season reward"* -- and the passage behind the falls is the hidden passage it
-- was written for. Going through it rather than reaching for `GameConfig.RollRelic` directly is what
-- makes 34.53, 34.54 and the 40-diamond buy provably one roll: the luck bend, the collection-relic
-- grant, the auto-equip-into-an-empty-slot, the telemetry row and the two toasts all live in
-- `HandleOpenChest` and none of them is duplicated here. THE SERVER DECIDES THE PRIZE; this file
-- never learns what it was and has no way to influence it.
--
-- ===== WHY THE BANK-THEN-OPEN PAIR RATHER THAN A DIRECT OPEN =====
--
-- `HandleOpenChest` refuses every source outside the closed set { "diamonds", "banked" } (34.55
-- rebuilt that guard on purpose -- read the block over its `else` branch before adding a third).
-- "banked" is the only string that means *something in the world gave you this*, so the chest has to
-- exist in `data.RelicChests` before it can be spent. Handing it over and immediately spending it is
-- one synchronous block with no yield in it.
--
-- IT ALSO GIVES THE STAGE GATE SOMEWHERE SAFE TO LAND. `HandleOpenChest` runs `forgeOpen` first and
-- refuses below stage `GameConfig.RelicUnlockStage`. Because the chest was BANKED a line earlier,
-- a player who finds the grotto early is not robbed: they keep an unopened chest, the forge tells
-- them why it will not open yet, and they spend it from the Relics panel the day it unlocks. The
-- cooldown is still stamped, which is correct -- they took the prize, they just cannot unwrap it.
--
-- ===== THE CLOCK, AND WHY IT IS A FIELD THAT ALREADY EXISTS =====
--
-- `data.LastRelicChest` is the free-relic timer's old stamp. 34.55 deleted the timer and recorded
-- that the field *"stays in the save defaults, unread"*. This is what re-reads it, and re-using it
-- is deliberate rather than lazy:
--
--   * it is already in `PlayerDataService`'s defaults, so every existing save and every generic
--     backfill already carries it -- a brand-new field would need an edit to a file this row does
--     not own, and a save written before that edit would arrive as nil,
--   * it means exactly what it always meant -- *the last time the world gave this player a relic
--     chest for free* -- so nothing about the name has to be re-learned, and
--   * the instruction on this row is "one roll, one source string, ONE COOLDOWN CLOCK". A second
--     timestamp beside a dead one is two answers to the same question.
--
-- The only cost is that a save carrying a stamp from the free-timer era starts this chest partly
-- through its first cooldown. That is at most one cooldown, once, and it errs towards the player
-- waiting rather than towards a double payout.
--
-- ===== THE RATE, STATED RATHER THAN DISCOVERED LATER =====
--
-- 34.55 shut the only faucet a non-paying player had: *"a player who never spends a diamond used to
-- gain four relics an hour by standing still, and that is now ZERO"*. The old timer was 15 minutes,
-- so this chest is the number that replaces four-an-hour.
--
-- `CHEST_COOLDOWN = 1200` -> **3.0 chests an hour**, and a chest pays on both relic layers (one
-- equippable roll plus one collection relic), so 3 equippable and 3 collection relics an hour is the
-- ceiling. It is deliberately UNDER the deleted faucet's four, and unlike that faucet every one of
-- them costs a walk: out of the village, up to the falls, through the water curtain and back. A
-- number that pays more than standing still did would have made 34.55 a buff.
--
-- It is a local rather than a `GameConfig` value because nothing else reads it -- no panel quotes
-- it, no countdown is drawn from it. The moment a screen needs to print it, it moves to
-- `GameConfig.Relics` beside the diamond cost and this local goes.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local RelicService = require(script.Parent.RelicService)

local ChestService = {}

-- ===== THE ART IS HERS, AND IT IS LOOKED FOR BY NAME IN FOUR PLACES =====
--
-- 34.58: *"ubacila sam i 2d i 3d za chest pa ti napravi da funkcionise"*. The model she inserted is
-- `workspace["coin chest"].chest`, seen in her Explorer beside `WaterfallParkour`.
-- [[evolution-lab-map-owns-the-furniture]] is why that placement is the source of truth for what a
-- chest looks like, and [[evolution-lab-hud-tile-prefabs]] is why a COPY is seated here and her
-- original is left exactly where she put it: adopt the art, never consume it.
--
-- FOUR CANDIDATES, IN ORDER, because a prop parked by hand moves. `ServerStorage.SourceProps` is
-- tried FIRST and is where this should eventually live -- it is where `TrainingDummyModel` parks her
-- dummy rig, and for the reason that file states at length: nothing in `Workspace` should run.
-- Failing all four the service warns and builds nothing. It never errors: a missing prop must not
-- take `ServerMain` down with it, because a dangling require aborts the rest of the boot silently
-- ([[evolution-lab-pushing-into-another-lane]]).
-- ===== WHAT THE OWNER ACTUALLY INSERTED, MEASURED ON THE LIVE SERVER (34.58) =====
--
-- She wrote *"ubacila sam i 2d i 3d za chest"*, and the first boot of this file printed
-- `no chest art found`. The reason, read off the running datamodel rather than guessed:
--
--     Workspace["coin chest"]  is a **Decal**, texture rbxassetid://79295568252541
--       └─ chest               is a **Decal**, texture rbxassetid://8281320680
--
-- Both halves of what landed are 2D. There is no inserted MODEL, so the first four paths below can
-- never resolve and the row's 3D half had no art at all.
--
-- `Workspace.GroupChest` IS a real chest and it is ours: `Base` / `Trim` / `Lid` / `Lock`, 4.2 x 3.6
-- x 3.4 studs, standing at (48, 3, 335) as the group-reward prop. It is the fallback rather than the
-- first choice -- if she parks a model of her own at `ServerStorage.SourceProps.RelicChest` it wins
-- on the next boot with no edit here -- but a grotto with a working chest in the game's own art
-- beats a grotto with a warning in the log. It also happens to carry a part literally named `Lid`,
-- which is what the hinge below looks for, so the open animation works on it without a guess.
--
-- ===== THE TWO TEXTURE IDS MOVED TO `GameConfig` (34.54) =====
--
-- They were declared here as literals, on the grounds that this was the only record of them in
-- `src/`. That stopped being true the moment a CLIENT needed to draw one: 34.54 puts a chest on the
-- lucky wheel that the player presses, and a client cannot require a module in `ServerScriptService`
-- -- so keeping them here would have meant a second copy of the same two strings on the far side,
-- which is exactly the shape that lets the grotto chest and the wheel chest drift into two different
-- pictures of one object. They live on `GameConfig.RelicChestIcon` now, which both sides already
-- read. The two fields below are kept as ALIASES rather than deleted: 34.58 published them by name
-- and this file is still the place a reader looks for "what art does the chest use".
ChestService.Icon2D = GameConfig.RelicChestIcon
ChestService.Icon2DAlt = GameConfig.RelicChestIconAlt
local SOURCE_PATHS = {
	{ "ServerStorage", "SourceProps", "RelicChest" },
	{ "ServerStorage", "SourceProps", "coin chest", "chest" },
	{ "Workspace", "coin chest", "chest" },
	{ "Workspace", "coin chest" },
	{ "Workspace", "GroupChest" },
}

local FOLDER_NAME = "Chests"
local MODEL_NAME = "GrottoRelicChest"

-- ===== THE SCALE =====
-- [[evolution-lab-scale-is-the-body]]: 8.4 studs is the ruler. A chest is furniture you crouch to,
-- not a landmark -- about half a player is right, and the grotto has 20 studs of headroom so there
-- is no ceiling pressure either way. Her model's authored size is UNKNOWN to this file (it cannot be
-- read off disk), so the scale is computed from the measured world AABB instead of typed: whatever
-- she inserted, it ends up `TARGET_HEIGHT` tall. A typed `ScaleTo(2)` would be a guess about art
-- nobody in this lane can see.
local TARGET_HEIGHT = 4.6
local MIN_SCALE, MAX_SCALE = 0.05, 40   -- a sane band, so a degenerate AABB cannot ask for x9000

-- ===== THE SEAT, DERIVED OFF `RelicAnchor` AND NEVER TYPED =====
--
-- `MapWaterfall.buildRelic` creates a 1-stud invisible part named `RelicAnchor` at
-- `centre + Vector3.new(0, PLINTH_TOP + 0.2, 0)` -- i.e. on the plinth's top face, four studs under
-- the floating gem. Every piece of that room is measured off `GameConfig.Secrets[1].offset` and this
-- anchor is the room's own published copy of it, so seating from the anchor is what stops a
-- hand-typed world position drifting the first time the grotto moves. It is the same rule
-- `TrainingDummyModel.SeatFor` follows one prop over.
--
-- ===== AND THE OFFSET IS THE ONLY NUMBER HERE THAT IS NOT FREE =====
--
-- Three things already stand in this 44 x 40 room and the chest has to clear all of them:
--
--   * THE SECRET'S TRIGGER, at (291, 6, -281). `SecretsService.reportBlocked` sweeps a 4 x 6 x 4
--     humanoid box there and prints `ForestWaterfall IS UNREACHABLE` if ANY collidable part is
--     inside it. That box is x 289..293, y 3..9, z -283..-279. A chest dropped in front of the
--     plinth lands squarely in it, which is the whole reason this offset goes sideways.
--   * THE PLINTH AND ITS SHRINE, a 12-stud disc at z -300..-288 with a gem, eight turning stones at
--     radius 5.8 and a mutation aura above it.
--   * THE TRAINING DUMMY, seated by `TrainingDummyModel.SEAT_OFFSET = (-15, 0, 6)` and measured at
--     x 271.8..280.2 -- the WEST half of the room.
--
-- So the chest takes the EAST half, mirroring the dummy, and sits back beside the plinth rather than
-- level with the doorway: `+15` on x puts it at about x 306 against an inner wall at 313, and `+2`
-- on z puts it at -292, three studs behind the trigger box's near face. It is the last thing in the
-- room, which is what "at the end of the passage" means, and it is on the opposite side from the
-- thing you punch.
--
-- The arithmetic is not the authority -- `assertClearOfSecret` below re-runs the engine's own box
-- test after the build and warns by name if it is wrong.
local SEAT_OFFSET = Vector3.new(9, 0, -9)

-- Facing +Z, out through the mouth at whoever walks in. A part's LookVector is -Z by default, hence
-- the half turn rather than a quarter ([[roblox-yaw-lowers-atan2-bearing]] is the standing note on
-- getting this backwards, and the dummy two files over uses the same `math.pi`).
local YAW = math.pi

-- ===== THE PROMPT'S REACH, SET SECOND =====
-- `Model:ScaleTo()` multiplies `ProximityPrompt.MaxActivationDistance` along with everything else
-- ([[roblox-scaleto-scales-prompt-reach]] -- 18 silently becomes 9 at ScaleTo(0.5)). The prompt
-- below is therefore CREATED AFTER the scale, so this number is literal studs and stays literal.
local PROMPT_REACH = 14
local PROMPT_HOLD = 0.35

local CHEST_COOLDOWN = 1200   -- seconds; see the rate block at the top of this file

-- The reveal is drawn WHERE IT HAPPENS ([[evolution-lab-feedback-placement]]) -- no screen-centre
-- banner. This is the channel; `ChestReveal.client.lua` is the only listener.
local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local ChestFx = ensureRemote("ChestFx")

local chest = nil          -- the seated model, or nil if nothing was built
local lidPart = nil        -- the hinging piece, or nil if her art does not name one
local lidBaseCF = nil      -- its closed pose, so a re-open cannot stack on a half-open one
local lidHinge = nil       -- the world-space hinge, computed once at build time
local chestPivot = nil     -- the model's closed pivot, same reason as lidBaseCF
local chestTop = nil       -- where the floating word is drawn; measured once, at build
local animating = false
local lastTrigger = {}     -- UserId -> os.clock(), the double-fire debounce

-- ===== THE TRUE WORLD AABB =====
-- `GetBoundingBox` / `GetExtentsSize` cannot be used: both are PIVOT-frame
-- ([[roblox-model-box-getters-are-pivot-frame]]) and a prop inserted at any yaw but zero reports its
-- box with the axes swapped. `TrainingDummyModel` carries the same helper for the same reason -- it
-- is duplicated rather than shared because that module is another lane's file this week.
local function worldBox(model)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local any = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			any = true
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
	if not any then return nil, nil end
	return lo, hi
end

-- One part's full extent along an arbitrary world direction. `Size` alone cannot answer this: it is
-- in the part's OWN frame, so a lid authored on its side reports its depth on the axis nobody asked
-- about ([[roblox-part-size-is-in-its-own-frame]]).
local function extentAlong(part, dir)
	local cf, sz = part.CFrame, part.Size
	return math.abs(cf.RightVector:Dot(dir)) * sz.X
		+ math.abs(cf.UpVector:Dot(dir)) * sz.Y
		+ math.abs(cf.LookVector:Dot(dir)) * sz.Z
end

-- ===== SANITISE, AND THIS IS NOT BELT-AND-BRACES HERE =====
--
-- Her chest came out of the toolbox and this place has already shipped THREE live backdoors in
-- inserted art ([[evolution-lab-free-model-backdoor]], and the `EZConfig` script that arrived
-- welded into the training dummy). A `Script` parented under `Workspace` RUNS. So the clone is
-- stripped of every `LuaSourceContainer`, `SpawnLocation`, prompt and detector before it is parented
-- anywhere -- the prompt this file wants is built fresh afterwards, so an authored one is a
-- duplicate as well as a risk.
--
-- NOTE THE ORIGINAL IS NOT TOUCHED. If her `workspace["coin chest"]` carries a live script, this
-- does not disarm it -- it only guarantees the copy in the grotto is inert. Say so out loud rather
-- than let the sweep read as a fix: the main agent has to look at the original in Studio.
local function sanitise(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("SpawnLocation") or d:IsA("Humanoid")
			-- ===== AND ITS SIGN, WHICH IS THE ONE THE FIRST LIVE TEST CAUGHT (34.58) =====
			-- The art this falls back to is `Workspace.GroupChest`, and a chest model does not
			-- arrive as bare geometry -- it arrives wearing whatever it was built to advertise.
			-- Measured on the running server: the seated grotto chest was drawing
			-- `👥 GROUP REWARDS` and `+10% DNA & Daily Chest` over itself, because the clone
			-- carried the source's `ChestLabel` BillboardGui with it. A relic chest telling players
			-- it pays a group bonus is worse than a chest with no sign at all, and no amount of
			-- reading the code would have found it -- only pressing the thing did
			-- ([[evolution-lab-press-the-button]]).
			--
			-- Both Gui classes go, not just the one seen: a `SurfaceGui` on the lid is the same
			-- fault with a different class name. This file draws its own floating word at open time
			-- and the prompt carries the chest's name, so nothing here loses anything a borrowed
			-- sign was providing.
			--
			-- `Decal` and `Texture` are deliberately KEPT. They carry no words -- they are the wood
			-- grain and the metal banding a chest is made of -- and stripping them would strip the
			-- look off the next model the owner parks at `SourceProps.RelicChest`, which is the
			-- whole point of adopting her art rather than building our own.
			or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d:Destroy()
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- CanQuery stays TRUE on the visible shell. [[roblox-canquery-ignored-when-collides]] is
			-- the trap this repo has hit a dozen times: a non-queryable prop is open air to every
			-- spatial sweep, and the very next thing this file does is ask the engine whether the
			-- chest is standing in the secret's trigger.
			d.CanQuery = true
		elseif d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			-- dead weight once everything is anchored, and a joint between two anchored parts warns
			d:Destroy()
		end
	end
end

-- ===== THE LID, AND WHY IT IS FOUND BY NAME ONLY =====
--
-- The open animation would rather hinge a lid than bounce a box, but this lane cannot see her model:
-- no Studio tools, no part list, no capture. A heuristic that guesses which part is the lid (the
-- topmost? the second largest?) is a heuristic that, on the wrong art, tips the whole chest over on
-- its face every time a player opens it and looks like a bug rather than a style.
--
-- So it hinges ONLY on an unambiguous name. Everything else falls back to the pop in `playOpen`,
-- which cannot look wrong on any geometry. If the main agent finds her lid is called something else,
-- the fix is one string in this list.
local LID_NAMES = { "lid", "top", "cover", "cap", "hatch", "poklopac" }

local function findLid(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local lower = d.Name:lower()
			for _, want in ipairs(LID_NAMES) do
				if lower == want or lower:find(want, 1, true) then
					return d
				end
			end
		end
	end
	return nil
end

-- Where the room's floor actually is under a spot, rather than where a config says y is.
-- `TrainingDummyModel.floorAt`'s note is the reason: the secret's offset carries a Y of 6 because a
-- 12-stud trigger centred on the floor is half buried in it, and a prop seated at that number floats
-- six studs. Cast from under the roof (underside y 20) and above head height.
local function floorAt(x, z, fallbackY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local hit = workspace:Raycast(Vector3.new(x, 15, z), Vector3.new(0, -30, 0), params)
	return hit and hit.Position.Y or fallbackY
end

local function resolveInstance(path)
	local node = game:GetService(path[1])
	for i = 2, #path do
		if not node then return nil end
		node = node:FindFirstChild(path[i])
	end
	return node
end

local function findSource()
	for _, path in ipairs(SOURCE_PATHS) do
		local ok, node = pcall(resolveInstance, path)
		if ok and node and (node:IsA("Model") or node:IsA("BasePart")) then
			return node, table.concat(path, ".")
		end
	end
	return nil, nil
end

-- The anchor `MapWaterfall` published, found down the path the map is actually built at rather than
-- by a recursive sweep of a 105,000-part Workspace.
local function findAnchor()
	local zones = workspace:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild("Forest")
	local map = zone and zone:FindFirstChild("VillageMap")
	local grotto = map and map:FindFirstChild("WaterfallGrotto")
	if not grotto then return nil, "no Zones.Forest.VillageMap.WaterfallGrotto -- has MapWaterfall run?" end
	local anchor = grotto:FindFirstChild("RelicAnchor", true)
	if not anchor then return nil, "the grotto has no RelicAnchor part" end
	return anchor, nil
end

-- ===== THE CHECK THAT MATTERS MORE THAN THE ARITHMETIC ABOVE =====
--
-- Replays `SecretsService.reportBlocked`'s own test after the chest is standing, and names this
-- model if it is the thing in the way. A guard that has to be re-derived to be acted on is half a
-- guard -- that sentence is `SecretsService`'s and it was written after exactly this failure
-- (33.19, when the answer turned out to be `GrottoPlinth` and had to be found by hand).
--
-- IT TESTS THE REAL TRIGGER PART WHERE ONE EXISTS, rather than re-deriving its position. The
-- trigger is `Map.Secrets.Secret_<id>` and `reportBlocked` sweeps a 4 x 6 x 4 box at its CFrame; a
-- second copy of that arithmetic here is a second thing to keep in step. The arithmetic is only the
-- fallback, for a boot where this runs before `SecretsService` has built the holder.
local BODY_BOX = Vector3.new(4, 6, 4)

local function secretTriggerCFrame(secret)
	local map = workspace:FindFirstChild("Map")
	local holder = map and map:FindFirstChild("Secrets")
	local trigger = holder and holder:FindFirstChild("Secret_" .. tostring(secret.id))
	if trigger and trigger:IsA("BasePart") then return trigger.CFrame end

	local zoneIndex = GameConfig.GetZoneIndex(secret.zoneKey)
	local zone = GameConfig.Zones[zoneIndex]
	if not zone then return nil end
	local at = secret.triggerOffset or secret.offset
	if not at then return nil end
	return CFrame.new(Vector3.new(zone.offset, 0, 0) + at)
end

local function assertClearOfSecret()
	if not chest then return true end
	for _, secret in ipairs(GameConfig.Secrets or {}) do
		if secret.zoneKey == "Forest" then
			local cf = secretTriggerCFrame(secret)
			if cf then
				for _, part in ipairs(workspace:GetPartBoundsInBox(cf, BODY_BOX)) do
					if part.CanCollide and part:IsDescendantOf(chest) then
						warn(("[ChestService] THE CHEST IS BLOCKING %s: %s is inside the secret's "
							.. "humanoid box at %s. Move SEAT_OFFSET further east -- SecretsService "
							.. "prints that secret UNREACHABLE on every boot until it is.")
							:format(tostring(secret.id), part.Name, tostring(cf.Position)))
						return false
					end
				end
			end
		end
	end
	return true
end

-- ===== THE OPEN =====
--
-- Two halves, and the second one is the only one that is guaranteed to exist.
--
--   * THE LID hinges about its own rear edge, in WORLD space. The chest's facing is known (this file
--     posed it at `YAW`), so the hinge line is the model's RightVector through a point set back from
--     the lid's centre by half its depth. Computing it that way needs nothing about the art's own
--     local frame, which is the thing this lane cannot see -- an `Attachment` or a local-axis
--     rotation would depend on how she happened to author the part.
--   * THE POP lifts and tips the whole model a little and puts it straight back. It is what plays
--     when there is no named lid, and it cannot look wrong on any geometry.
--
-- Both restore to the pose captured at BUILD time rather than to wherever the prop currently is, so
-- two players opening it a second apart cannot walk the chest across the floor.
local LID_OPEN_DEG = 78
local POP_LIFT = 0.55

local function playOpen()
	if not chest or animating then return end
	animating = true

	if lidPart and lidBaseCF and lidHinge then
		local open = lidHinge * CFrame.Angles(math.rad(-LID_OPEN_DEG), 0, 0) * lidHinge:Inverse() * lidBaseCF
		local up = TweenService:Create(lidPart,
			TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = open })
		up:Play()
		task.delay(1.5, function()
			if lidPart and lidPart.Parent and lidBaseCF then
				TweenService:Create(lidPart,
					TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
					{ CFrame = lidBaseCF }):Play()
			end
		end)
	elseif chestPivot then
		-- No lid to hinge: the whole box jumps instead. `PivotTo` on an anchored model is the same
		-- trick `TrainingDummyModel.Recoil` uses, and for the same reason -- there is no physics
		-- assembly here to push.
		task.spawn(function()
			local steps = 14
			for i = 1, steps do
				if not chest or not chest.Parent then return end
				local t = i / steps
				local lift = math.sin(t * math.pi) * POP_LIFT
				local tip = math.sin(t * math.pi) * math.rad(9)
				chest:PivotTo(chestPivot * CFrame.new(0, lift, 0) * CFrame.Angles(tip, 0, 0))
				task.wait(0.03)
			end
			if chest and chest.Parent then chest:PivotTo(chestPivot) end
		end)
	end

	-- The burst, out of the chest's own mouth. Emitters are built at BUILD time and only fired here:
	-- creating one per open is how a prop ends up with forty emitters on it after an evening.
	local fxHost = chest:FindFirstChild("ChestFxAnchor", true)
	if fxHost then
		-- DESCENDANTS, not children: the emitter hangs on an `Attachment` under this part, for the
		-- reason in the block over `ChestFxAnchor` in `build`.
		for _, d in ipairs(fxHost:GetDescendants()) do
			if d:IsA("ParticleEmitter") then d:Emit(26) end
		end
		local light = fxHost:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = true
			TweenService:Create(light, TweenInfo.new(1.1), { Brightness = 0 }):Play()
			task.delay(1.2, function()
				if light and light.Parent then
					light.Enabled = false
					light.Brightness = 4
				end
			end)
		end
	end

	task.delay(1.6, function() animating = false end)
end

-- Where the floating word is drawn: over the chest, in the room, never on the middle of the screen.
--
-- MEASURED ONCE AT BUILD, not per press. Two reasons and the second is the real one: a full AABB
-- sweep of the model on every trigger is work nobody needs, and while the POP is playing the model
-- is a third of a stud off its seat -- so a box taken mid-animation would put the word somewhere
-- slightly different every time it is read.
local function tell(player, text, colour, big)
	if not chestTop then return end
	ChestFx:FireClient(player, { p = chestTop, text = text, color = colour, big = big == true })
end

-- ===== THE ONE HANDLER =====
--
-- SHARED GEOMETRY, PER-PLAYER CLOCK. There is no instancing in this game, so the chest in the grotto
-- is one prop that everybody can see and everybody can press. Two players standing at it both open
-- it, both roll, and neither one's cooldown touches the other's -- the state that decides is
-- `data.LastRelicChest`, which lives in a save. Nothing about "is the chest open right now" is
-- allowed to gate a payout; `animating` guards the TWEEN and nothing else, or the second player at a
-- busy chest would silently get nothing.
local function onTriggered(player)
	if not player or not player.Parent then return end

	-- The prompt can fire twice on one press on a laggy client. Cheap, local, and it is NOT the
	-- cooldown -- it only collapses a double-fire into one.
	local now = os.clock()
	if lastTrigger[player.UserId] and now - lastTrigger[player.UserId] < 0.6 then return end
	lastTrigger[player.UserId] = now

	local data = PlayerDataService.Get(player)
	if not data then return end

	local stamped = tonumber(data.LastRelicChest) or 0
	local wait = CHEST_COOLDOWN - (os.time() - stamped)
	if wait > 0 then
		local mins = math.floor(wait / 60)
		local secs = math.floor(wait % 60)
		tell(player, ("\u{1F512} Sealed  \u{00B7}  %dm %02ds"):format(mins, secs),
			Color3.fromRGB(150, 150, 165), false)
		return
	end

	-- ===== CHARGE BEFORE GRANT, WITH NO YIELD BETWEEN =====
	-- The stamp goes down FIRST, in the same synchronous block as the two calls below. It is the rule
	-- `RelicService`, `RewardService`, `CodesService` and `RobuxShopService` each carry their own note
	-- about, and [[evolution-lab-charge-before-check]] is what it costs to get backwards.
	data.LastRelicChest = os.time()

	local before = tonumber(data.RelicChests) or 0
	RelicService.GiveChest(player, 1)
	RelicService.HandleOpenChest(player, "banked")
	-- Did the forge actually open it? If it refused (below `GameConfig.RelicUnlockStage`) the chest
	-- is still sitting in the bank, and the honest word for that is not "relic".
	local opened = (tonumber(data.RelicChests) or 0) <= before

	playOpen()

	if opened then
		-- The chest says a chest opened; the RELIC is named by `RelicService`'s own `relic` toast,
		-- which already draws the big card for a first Legendary or Mythic and pitches the sting by
		-- rarity. Two writers naming the same prize is how one of them ends up wrong.
		tell(player, "\u{2728} RELIC CHEST", Color3.fromRGB(255, 198, 45), true)
	else
		tell(player, "\u{1F381} Chest banked", Color3.fromRGB(255, 198, 45), false)
	end
end

-- ===== BUILD =====
--
-- Returns the model or nil plus a reason. IDEMPOTENT: any chest already standing in the folder is
-- destroyed first, so a second call cannot leave two.
local function build()
	local source, sourcePath = findSource()
	if not source then
		local looked = {}
		for _, path in ipairs(SOURCE_PATHS) do
			table.insert(looked, table.concat(path, "."))
		end
		return nil, ("no chest art found -- looked for %s"):format(table.concat(looked, ", "))
	end

	local anchor, why = findAnchor()
	if not anchor then return nil, why end

	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = workspace
	end
	local existing = folder:FindFirstChild(MODEL_NAME)
	if existing then existing:Destroy() end

	-- A COPY. Her original stays exactly where she put it -- see the SOURCE_PATHS block.
	--
	-- `Clone()` RETURNS NIL ON A NON-ARCHIVABLE INSTANCE, silently, and that is the one failure here
	-- that would otherwise surface as "attempt to index nil" fifteen lines down rather than as a
	-- sentence naming the prop.
	local model
	if source:IsA("BasePart") then
		local part = source:Clone()
		if not part then return nil, ("%s is not Archivable -- Clone() returned nil"):format(sourcePath) end
		model = Instance.new("Model")
		part.Parent = model
		model.PrimaryPart = part
	else
		model = source:Clone()
		if not model then return nil, ("%s is not Archivable -- Clone() returned nil"):format(sourcePath) end
	end
	model.Name = MODEL_NAME
	sanitise(model)

	local lo, hi = worldBox(model)
	if not lo then
		model:Destroy()
		return nil, ("%s has no BasePart in it"):format(tostring(sourcePath))
	end

	if not model.PrimaryPart then
		-- Needed for `PivotTo` to behave predictably and for anything downstream that reads it. The
		-- biggest part is the body of a chest on any art that is recognisably a chest.
		local best, bestVol = nil, -1
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local vol = d.Size.X * d.Size.Y * d.Size.Z
				if vol > bestVol then best, bestVol = d, vol end
			end
		end
		model.PrimaryPart = best
	end

	-- ===== SCALE FIRST, DRESS SECOND =====
	-- [[roblox-scaleto-scales-prompt-reach]]. Every prompt, light and emitter below is created AFTER
	-- this line, so none of their numbers is silently multiplied.
	--
	-- `ScaleTo` IS ABSOLUTE, NOT A MULTIPLIER. It sets `Model.Scale`, so a source she had already
	-- scaled in Studio would be RESET by a bare `ScaleTo(ratio)` rather than adjusted by it. The
	-- ratio is measured against the box as it stands and then applied on top of whatever scale the
	-- clone arrived carrying.
	local height = hi.Y - lo.Y
	if height > 0.01 then
		local ratio = math.clamp(TARGET_HEIGHT / height, MIN_SCALE, MAX_SCALE)
		local ok = pcall(function()
			model:ScaleTo(model:GetScale() * ratio)
		end)
		if not ok then model:ScaleTo(ratio) end
	end

	-- Seat it: pose at the offset, then settle onto the MEASURED floor rather than an assumed y.
	local seat = Vector3.new(anchor.Position.X, 0, anchor.Position.Z) + SEAT_OFFSET
	model:PivotTo(CFrame.new(seat) * CFrame.Angles(0, YAW, 0))
	local groundY = floorAt(seat.X, seat.Z, anchor.Position.Y - 3)
	lo = select(1, worldBox(model))
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - lo.Y, 0))

	model.Parent = folder
	chest = model
	chestPivot = model:GetPivot()

	-- ===== THE HINGE, COMPUTED ONCE =====
	-- The lid's rear edge in world space: back from its centre by half its depth along the chest's
	-- own facing, with the hinge line running along the chest's RightVector. See the block over
	-- `playOpen` for why this is world-space arithmetic and not a local-axis rotation.
	lidPart = findLid(model)
	lidBaseCF, lidHinge = nil, nil
	if lidPart then
		-- How deep the lid is ALONG THE CHEST'S FACING, which is not `lidPart.Size.Z`: `Size` is in
		-- the part's own frame and an authored prop is rarely axis-aligned with the pose this file
		-- gave it ([[roblox-part-size-is-in-its-own-frame]] -- a flat union authored standing up
		-- reads 143 studs tall). Projecting the part's three half-extents onto the facing is the
		-- frame-independent answer.
		local depth = extentAlong(lidPart, chestPivot.LookVector)
		local back = chestPivot.LookVector * -(math.max(depth, 0.5) / 2)
		lidBaseCF = lidPart.CFrame
		lidHinge = CFrame.fromMatrix(lidPart.Position + back,
			chestPivot.RightVector, chestPivot.UpVector, -chestPivot.LookVector)
	end

	-- ===== THE BURST, BUILT ONCE AND FIRED ON DEMAND =====
	-- Its own anchor part rather than an attachment on the body, for the reason
	-- [[evolution-lab-vfx-attach-rules]] states: `Attachment.Position` is in the PARENT's frame, and
	-- an offset written on a part authored at any rotation goes sideways. An unrotated 1-stud part
	-- cannot lie about where it is.
	local nlo, nhi = worldBox(model)
	local fxHost = Instance.new("Part")
	fxHost.Name = "ChestFxAnchor"
	fxHost.Size = Vector3.new(1, 1, 1)
	fxHost.Transparency = 1
	fxHost.Anchored = true
	fxHost.CanCollide = false
	fxHost.CanQuery = false
	fxHost.CanTouch = false
	fxHost.CastShadow = false
	fxHost.Position = Vector3.new((nlo.X + nhi.X) / 2, nhi.Y - 0.2, (nlo.Z + nhi.Z) / 2)
	fxHost.Parent = model

	local att = Instance.new("Attachment")
	att.Parent = fxHost

	local spray = Instance.new("ParticleEmitter")
	spray.Name = "ChestBurst"
	-- The engine's own sparkle, which is what `EggPlaza`, `EvolutionVisuals` and `ZoneGate` all use.
	-- Set explicitly: an emitter left on the default texture is a well-known way to build an effect
	-- that emits nothing visible and reports no error.
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Enabled = false
	spray.Rate = 0
	spray.Lifetime = NumberRange.new(0.7, 1.3)
	spray.Speed = NumberRange.new(8, 16)
	spray.SpreadAngle = Vector2.new(38, 38)
	spray.Rotation = NumberRange.new(0, 360)
	spray.RotSpeed = NumberRange.new(-140, 140)
	spray.Acceleration = Vector3.new(0, -22, 0)
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Gold, and it is the room's own gold: `MapWaterfall`'s `RELIC_GOLD` lights this cave and the gem
	-- on the plinth is painted two steps down from it. A burst in some other hue would be the one
	-- effect in the room promising a different prize.
	spray.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 176, 48))
	-- Brightness and LightEmission are two different levers and only one of them lifts a sprite off
	-- a dark ground ([[roblox-particle-tint-clipping]]): LightEmission is the one that stops this
	-- reading as grey confetti in a cave lit at brightness 1.5.
	spray.LightEmission = 0.85
	spray.Parent = att

	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 224, 130)
	flash.Brightness = 4
	flash.Range = 22
	flash.Shadows = false   -- the same note the grotto's key light carries: a cast shadow in this
	                        -- room draws a floating grey slab on the back wall
	flash.Enabled = false
	flash.Parent = fxHost

	-- ===== THE PROMPT, ON A PART AND NOT ON THE MODEL =====
	-- A `ProximityPrompt` parented to a Model never shows -- `MapCounters` carries that note. It goes
	-- on the PrimaryPart, and it deliberately carries NO `ShopPanel` attribute: `MainUI`'s global
	-- `PromptTriggered` handler returns immediately on a prompt without one, so this prompt is
	-- answered by the server handler below and by nothing else.
	local host = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RelicChestPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Relic Chest"
	prompt.HoldDuration = PROMPT_HOLD
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = PROMPT_REACH   -- literal studs: created AFTER the ScaleTo above
	prompt.Parent = host
	prompt.Triggered:Connect(onTriggered)

	assertClearOfSecret()

	local flo, fhi = worldBox(model)
	chestTop = Vector3.new((flo.X + fhi.X) / 2, fhi.Y + 1.6, (flo.Z + fhi.Z) / 2)

	return model, nil, {
		seat = Vector3.new((flo.X + fhi.X) / 2, flo.Y, (flo.Z + fhi.Z) / 2),
		size = fhi - flo,
		source = sourcePath,
		lid = lidPart and lidPart.Name or nil,
	}
end

-- ===== INIT =====
--
-- EVERY connection is made in here and none at require time -- the rule `TrainingDummyService`'s
-- header states after an `OnServerEvent:Connect` at module top level fired before the model it
-- dereferenced existed.
--
-- ORDERING: it reads `Zones.Forest.VillageMap.WaterfallGrotto.RelicAnchor` and raycasts onto the
-- grotto floor, so it must run after `ForestMapService.Init` (which is what runs `MapWaterfall`) --
-- i.e. after `ZoneBuilder.Build()`. It sits beside `TrainingDummyService.Init()` because that call
-- has the identical constraint for the identical reason. It reads no other service's state.
-- ===== THE ART CAN ARRIVE AFTER THIS SERVICE DOES, AND IT DOES (34.58) =====
--
-- The first two boots both printed `no chest art found`, and the second one printed it while
-- listing `Workspace.GroupChest` -- a model that a probe found sitting in the running workspace a
-- few seconds later. So the lookup was not wrong, it was EARLY: `ChestService.Init` is
-- `ServerMain:254` and that prop is not parented until something further down finishes.
--
-- This is [[evolution-lab-placement-search-ordering]] with the roles reversed. The usual failure is
-- a search that cannot see what is built after it; here it is a search that gives up on art that is
-- about to appear. A one-shot lookup at Init can only ever be right for props that exist before
-- `ServerMain` line 254, which is a promise no hand-placed model makes and no future source
-- (a boss drop's prop, a season prop, a model the owner parks mid-session) will keep either.
--
-- So the lookup RETRIES on a bounded clock rather than being reordered: moving the `Init` call down
-- ServerMain would fix this one prop and break the next one, and the ordering constraint in this
-- file's own header (the grotto must exist first) is a LOWER bound, not an upper one. 15 seconds at
-- half-second steps is 30 tries -- long past the whole boot, and short enough that a genuinely
-- missing prop still says so while a player is reading the loading screen.
--
-- IT NEVER ERRORS AND IT NEVER YIELDS `Init`. The retry runs in its own `task.spawn`, so a missing
-- prop cannot take the rest of `ServerMain` down with it and cannot delay a single line below it
-- ([[evolution-lab-pushing-into-another-lane]]: a dangling require aborts the rest of the boot
-- silently, and this is one line under that in the same file).
local WAIT_FOR_ART = 15
local WAIT_STEP = 0.5

local function announce(seated)
	print(("[ChestService] grotto chest from %s seated at (%.0f, %.1f, %.0f), %.1f x %.1f x %.1f, "
		.. "lid %s, prompt reach %d, cooldown %ds (%.1f chests/hour)")
		:format(tostring(seated.source), seated.seat.X, seated.seat.Y, seated.seat.Z,
			seated.size.X, seated.size.Y, seated.size.Z, tostring(seated.lid or "none -- pop only"),
			PROMPT_REACH, CHEST_COOLDOWN, 3600 / CHEST_COOLDOWN))
end

function ChestService.Init()
	-- Connected once, whether or not the art ever turns up: it costs nothing and it must not be
	-- inside the retry, or a chest that arrives late would leave stale trigger stamps behind it.
	Players.PlayerRemoving:Connect(function(player)
		lastTrigger[player.UserId] = nil
	end)

	local model, why, seated = build()
	if model then
		announce(seated)
		return
	end

	task.spawn(function()
		local waited = 0
		while waited < WAIT_FOR_ART do
			task.wait(WAIT_STEP)
			waited += WAIT_STEP
			local m, w, s = build()
			if m then
				announce(s)
				print(("[ChestService] ...the art turned up %.1fs after Init, not at it"):format(waited))
				return
			end
			why = w
		end
		warn(("[ChestService] no grotto chest after %ds -- %s"):format(WAIT_FOR_ART, tostring(why)))
	end)
end

return ChestService
