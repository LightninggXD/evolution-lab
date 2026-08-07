--[[
	PetFollowClient - trails every equipped pet in the world behind its owner, and animates it.

	The server (PetFollowService) only spawns and despawns the rigs; all motion happens here, on
	every client independently, so it is frame-smooth and costs no replication. Nothing this
	script writes ever leaves this machine: the parts are anchored, so a local CFrame change is
	purely visual.

	It drives *every* player's pets, not just the local player's, using the OwnerUserId attribute
	the server stamps on each model. That is what makes another player's pets follow them too.
	It also spins the pets on display over the egg podiums (tagged PetDisplay by ZoneBuilder),
	for the same reason: a server-side spin would replicate 60 CFrames a second per egg.

	The animation is per-part rather than a single bob, because a rig that only translates reads
	as a prop being dragged. Legs swing on a diagonal gait, the tail wags, ears flop, and the
	whole body hops and leans into the run -- all driven off the owner's speed, so a pet standing
	still idles and a pet chasing a sprinting player works for it.

	Offsets come off the parts as PetOffset attributes rather than being recomputed here -- see
	the note in PetModel.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Both are multiplied up at use: the owner's body runs from 1x to 9x across the evolution stages,
-- so a fixed trail distance either has the pets inside a big player's shins or strung out fifty
-- studs behind a small one. FOLLOW_BEHIND scales with the owner, SIDE_SPACING with the pet.
local FOLLOW_BEHIND = 6.0   -- studs behind the owner, per unit of the owner's body scale
local SIDE_SPACING = 5.0    -- lateral gap between pets, per unit of pet scale
local BOB_HEIGHT = 0.1      -- barely a breath while idle; the run hop does the visible work
local BOB_SPEED = 2.4
local RESPONSIVENESS = 7.5  -- higher = tighter to the player, lower = floatier trail
local RUN_SPEED = 16        -- the walk speed that counts as a full-effort run

local petsFolder = workspace:WaitForChild("EquippedPets")

-- Pets stand on whatever the player stands on, found by a ray straight down rather than by
-- assuming the pet's floor is the owner's floor -- the two differ constantly: the shop dais, the
-- portal steps, the plaza stairs. RespectCanCollide is what keeps a pet from standing on a
-- decorative bush or a path slab: the ray only sees what the player could also stand on.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local GROUND_RAY = Vector3.new(0, -180, 0)

-- which limb a part is decides how it animates; anything unlisted just rides the body
local PART_KIND = {
	Leg = "leg", Paw = "leg",
	Tail = "tail", TailTip = "tail", TailSpike = "tail",
	Ear = "ear", EarInner = "ear", Antenna = "ear", AntennaBulb = "ear",
	Head = "head", Muzzle = "head", Nose = "head", Eye = "head", Pupil = "head",
	Glint = "head", Cheek = "head", Grin = "head", Snout = "head", Patch = "head",
	Horn = "ear", CrownBand = "head", CrownSpike = "head",
	RarityRing = "ring",
}

-- model -> { root, pieces, phase, cf }. Weak keys: egg and podium rigs are destroyed wholesale
-- whenever ZoneBuilder's version guard regenerates the world, and a strong key here would pin
-- every one of them in memory for the rest of the session.
local state = setmetatable({}, { __mode = "k" })

local function stateFor(model)
	local s = state[model]
	if s then return s end

	local root = model.PrimaryPart
	if not root then return nil end

	local pieces = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local offset = d:GetAttribute("PetOffset")
			if offset then
				local kind = PART_KIND[d.Name] or "body"
				-- a leg's gait phase comes from which corner it stands in: diagonal legs move
				-- together, which is what makes four stubs read as a walk instead of a shuffle
				local diagonal = (offset.X >= 0) ~= (offset.Z >= 0)
				table.insert(pieces, { p = d, cf = offset, kind = kind, phase = diagonal and 0 or math.pi })
			end
		end
	end

	-- How far the lowest point of the rig sits below its root, measured off the parts themselves.
	-- It used to be one hard-coded constant derived by hand from the pet scale, so the moment that
	-- scale changed on the server every pet in the game went back to hovering. The rarity ring is
	-- skipped deliberately: it is a glow meant to lie *in* the floor, and grounding on it would
	-- lift all four paws clear of the ground, which is the exact look being fixed.
	local footDrop = root.Size.Y / 2
	for _, piece in ipairs(pieces) do
		if piece.kind ~= "ring" then
			footDrop = math.max(footDrop, -(piece.cf.Position.Y - piece.p.Size.Y / 2))
		end
	end

	-- the phase staggers the bob so a row of pets never bounces in lockstep
	s = { root = root, pieces = pieces, footDrop = footDrop, phase = (model:GetAttribute("Slot") or 1) * 1.9, cf = root.CFrame }
	state[model] = s
	return s
end

-- Rigid placement: the whole rig from one CFrame, no limb animation. What an egg wants.
local function place(s, cf)
	s.root.CFrame = cf
	for _, piece in ipairs(s.pieces) do
		if piece.p.Parent then
			piece.p.CFrame = cf * piece.cf
		end
	end
end

-- `effort` is 0 for a pet standing still and 1 for one keeping up with a sprint; it scales every
-- part of the animation at once, so one number is the whole difference between idle and run.
local function animate(s, cf, t, effort)
	local gait = t * (6 + effort * 5)
	local hop = effort * math.abs(math.sin(gait)) * 0.5
	local lean = -effort * 0.17 + math.sin(gait * 2) * 0.025
	local wag = math.sin(t * (4.5 + effort * 4)) * (0.3 + effort * 0.3)
	local flop = math.sin(gait + 0.6) * 0.1 * (0.5 + effort)
	local headTilt = math.sin(t * 1.7 + s.phase) * 0.05

	local bodyCf = cf * CFrame.new(0, hop, 0) * CFrame.Angles(lean, 0, math.sin(gait) * 0.05 * effort)
	s.root.CFrame = bodyCf

	for _, piece in ipairs(s.pieces) do
		if piece.p.Parent then
			local local_ = piece.cf
			if piece.kind == "leg" then
				local swing = math.sin(gait + piece.phase) * effort
				local_ = CFrame.new(0, math.max(0, swing) * 0.18, swing * 0.42) * local_
			elseif piece.kind == "tail" then
				local_ = CFrame.Angles(0, wag, 0) * local_
			elseif piece.kind == "ear" then
				local_ = CFrame.Angles(flop, 0, 0) * local_
			elseif piece.kind == "head" then
				local_ = CFrame.Angles(headTilt * 0.4, headTilt, 0) * local_
			end
			piece.p.CFrame = bodyCf * local_
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	-- an exponential step, so the trail feels identical at 30 and at 240 fps
	local alpha = 1 - math.exp(-RESPONSIVENESS * dt)

	for _, folder in ipairs(petsFolder:GetChildren()) do
		local owner = Players:GetPlayerByUserId(folder:GetAttribute("OwnerUserId") or 0)
		local character = owner and owner.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")

		-- an R15 HumanoidRootPart is 2 studs tall at 1x, so its own size is the cheapest reliable
		-- read of how big this player currently is -- no dependency on the Humanoid's scale values
		-- existing, and it is already correct mid-tween during an evolution
		local ownerScale = hrp and (hrp.Size.Y / 2) or 1

		local effort = 0
		if hrp then
			local v = hrp.AssemblyLinearVelocity
			effort = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / RUN_SPEED, 0, 1)
			-- the owner and every pet in the world are excluded, or a pet lands on its own
			-- packmate's head and the row climbs itself. Bosses and creatures too: they walk
			-- around, and a pet that finds one underfoot should not ride it.
			local ignore = { petsFolder, character }
			for _, name in ipairs({ "Creatures", "Bosses" }) do
				local f = workspace:FindFirstChild(name)
				if f then table.insert(ignore, f) end
			end
			groundParams.FilterDescendantsInstances = ignore
		end

		for _, model in ipairs(folder:GetChildren()) do
			local s = model:IsA("Model") and stateFor(model)
			if s and s.root.Parent then
				if hrp then
					local slot = model:GetAttribute("Slot") or 1
					local count = model:GetAttribute("SlotCount") or 1
					local petScale = model:GetAttribute("PetScale") or 1
					local spread = (slot - (count + 1) / 2) * SIDE_SPACING * petScale
					-- the idle bob fades out as the pet starts running: the hop takes over
					local bob = math.sin(t * BOB_SPEED + s.phase) * BOB_HEIGHT * (1 - effort * 0.7)

					-- behind and to the side of the owner, in the owner's own frame, so the row
					-- swings around with them instead of staying world-axis aligned. Height comes
					-- from the floor under *that* spot, not from the owner's own height, so a pet
					-- following a player up the shop steps walks up them, and one following a
					-- player who jumps stays on the ground instead of being towed into the air.
					local flat = (hrp.CFrame * CFrame.new(spread, 0, FOLLOW_BEHIND * ownerScale)).Position
					local hit = workspace:Raycast(Vector3.new(flat.X, hrp.Position.Y + 4 * ownerScale, flat.Z), GROUND_RAY, groundParams)
					-- fallback for a ray that finds nothing (owner over a gap, or mid-fall): the floor
					-- the owner would be standing on, which is hip height plus half the root part
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local groundY = hit and hit.Position.Y
						or (hrp.Position.Y - ((humanoid and humanoid.HipHeight or 2) + hrp.Size.Y / 2))
					local goalPos = Vector3.new(flat.X, groundY + s.footDrop + bob, flat.Z)

					-- face where the owner faces, with a lazy wobble while standing still
					local flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
					local yaw = flatLook.Magnitude > 0.01 and math.atan2(-flatLook.X, -flatLook.Z) or 0
					yaw += math.sin(t * 1.25 + s.phase) * 0.15 * (1 - effort)

					local goal = CFrame.new(goalPos) * CFrame.Angles(0, yaw, 0)
					-- a pet that is far behind (owner teleported / respawned) snaps instead of
					-- flying across the map through everything in between
					if (s.cf.Position - goalPos).Magnitude > 90 then
						s.cf = goal
					else
						s.cf = s.cf:Lerp(goal, alpha)
					end
				end

				animate(s, s.cf, t, effort)
			end
		end
	end

	-- the pets on show over each egg podium: no owner, just a slow turntable so you can see the
	-- thing from every side before you spend on it. They still idle-animate, at a fixed low
	-- effort, so a shop full of pets never looks like a shelf of statues.
	for _, model in ipairs(CollectionService:GetTagged("PetDisplay")) do
		local anchor = model:GetAttribute("SpinAnchor")
		local s = anchor and stateFor(model)
		if s and s.root.Parent then
			local bob = math.sin(t * 1.5) * (model:GetAttribute("BobHeight") or 0.4)
			local cf = anchor * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * (model:GetAttribute("SpinSpeed") or 0.7), 0)
			animate(s, cf, t, 0.28)
		end
	end

	-- THE EGGS: float and TURN. This used to deliberately refuse to spin -- the reasoning was that
	-- a rocking egg reads as something alive inside it while a spinning one reads as a shop
	-- turntable. That is true in the abstract and wrong here: an egg's pattern is on one side of it,
	-- so a shopper looking at the stall from the street only ever saw the back of two of them. It is
	-- a shop, a turntable is what it wants, and the reference stall turns its eggs.
	--
	-- The rock is KEPT and layered under the turn (a small tilt on X/Z on its own timing), so the
	-- egg still wobbles like something is moving inside rather than gliding round like a display
	-- model. `IdlePhase` differs per podium so three eggs never turn in lockstep.
	for _, model in ipairs(CollectionService:GetTagged("EggIdle")) do
		local anchor = model:GetAttribute("IdleAnchor")
		local s = anchor and stateFor(model)
		if s and s.root.Parent then
			local phase = model:GetAttribute("IdlePhase") or 0
			local bob = math.sin(t * 1.15 + phase) * (model:GetAttribute("BobHeight") or 0.4)
			local rock = math.sin(t * 0.85 + phase) * 0.06
			local spin = t * (model:GetAttribute("SpinSpeed") or 0.6) + phase
			place(s, anchor * CFrame.new(0, bob, 0) * CFrame.Angles(rock, spin, rock * 1.4))
		end
	end
end)

petsFolder.DescendantRemoving:Connect(function(d)
	if state[d] then state[d] = nil end
end)

-- ===== THE EGG OUTLINE =====
-- The dark outline is most of the chunky look, but Roblox only draws about 31 Highlights at once
-- and this world has 63 eggs, so baking one into every shell in ZoneBuilder would silently steal
-- the outline off the player's own pets -- the one place it actually matters. It lives here
-- instead: only the eggs of the stall you are actually standing at get one.
--
-- Twice a second, not per frame. Nothing about which stall you are at changes inside 500ms, and
-- creating and destroying Highlights is the expensive half of this.
local OUTLINE_RANGE = 140
local OUTLINE_MAX = 4 -- three eggs to a stall; the fourth covers standing between two of them
local outlined = {}

task.spawn(function()
	while true do
		local cam = workspace.CurrentCamera
		local origin = cam and cam.CFrame.Position
		local near = {}
		if origin then
			for _, model in ipairs(CollectionService:GetTagged("EggIdle")) do
				local shell = model.PrimaryPart
				if shell and shell.Parent then
					local d = (shell.Position - origin).Magnitude
					if d < OUTLINE_RANGE then
						near[#near + 1] = { model = model, d = d }
					end
				end
			end
			table.sort(near, function(x, y) return x.d < y.d end)
		end

		local keep = {}
		for i = 1, math.min(#near, OUTLINE_MAX) do
			local model = near[i].model
			keep[model] = true
			if not outlined[model] then
				local h = Instance.new("Highlight")
				h.FillTransparency = 1
				h.OutlineColor = Color3.fromRGB(24, 20, 34)
				h.OutlineTransparency = 0
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = model
				outlined[model] = h
			end
		end
		for model, h in pairs(outlined) do
			if not keep[model] then
				h:Destroy()
				outlined[model] = nil
			end
		end

		task.wait(0.5)
	end
end)
