-- SwordModel -- the blade itself: four parts a hand, welded to the body the costume just built.
--
-- A LEAF (`docs/SPLIT.md` §2): one job, one entry point, required by two files. It knows nothing
-- about saves, Diamonds or remotes -- it is handed a `GameConfig.Swords` row and a character, and
-- it puts that blade on that body. `SwordService` owns the money and `EvolutionVisuals` owns the
-- moment; both call `Apply` and neither has to know what a weld is.

local SwordModel = {}

-- Its own folder on the character, NOT the costume's. `StageCostume.Clear` destroys its folder
-- wholesale on every dress, and the sword has a different lifetime: it also has to be rebuilt when
-- a blade is BOUGHT, with no stage change and no costume rebuild behind it. A folder of its own
-- means each side can clear its own work without reaching into the other's, and `Apply` below is
-- idempotent because it clears this folder first.
local FOLDER_NAME = "SwordModel"

-- ===== FINDING THE HAND IS THE ONLY HARD PART OF THIS FILE =====
--
-- The host is `BodyHand`, the costume's MITT, not the avatar's hand. `StageCostume.dressBody`
-- welds a 2.1 x 1.5 x 2.1 shell over each hand and its own comment says it is "what the swing
-- animation is actually throwing -- the Trail comes off this part". Hanging the blade off the
-- avatar's `RightHand` instead would bury it inside the mitt, and the mitt is opaque.
--
-- **BOTH MITTS CARRY THE SAME NAME AND NEITHER IS A CHILD OF THE CHARACTER.** `shell()` passes the
-- literal string `"BodyHand"` for the left hand and for the right, and `att()` parents every
-- costume part into the `StageCostume` folder -- so `character:FindFirstChild("BodyHand")` is nil
-- and `costume:FindFirstChild("BodyHand")` is a coin toss between the two. The only thing that
-- distinguishes them is the limb their `CostumeWeld` is anchored to, which is what `hostsFor`
-- reads. Getting this wrong is silent: both blades land on one arm and the other hand swings bare.
local COSTUME_FOLDER = "StageCostume"
local HOST_NAME = "BodyHand"

-- ===== ONE BLADE PER HAND, AND THAT IS NOT A FLOURISH =====
--
-- `CombatClient.playSwing` ALTERNATES hands (`nextHand[character]`, "alternating reads as a
-- flurry, not a tic") and `handTrail` draws the swoosh off whichever hand is currently swinging.
-- The game already shows a weapon coming out of both hands; arming only one of them would make
-- every second blow an unarmed punch trailing a sword-shaped ribbon, which reads as a bug rather
-- than as a design. Arming both keeps the flurry and keeps the player armed in every frame of it.
--
-- If she wants a single blade, this table is the whole change -- and `CombatClient`'s alternation
-- would have to be pinned to the armed side in the same breath, or half the swings go back to
-- being punches.
local SIDES = { "Left", "Right" }

-- WHAT A BARE HAND HAS TO BE MULTIPLIED BY TO MEASURE LIKE A MITT.
--
-- Two bodies in this game have no `BodyHand` at all: stage 7 (Human, the one stage that keeps its
-- own avatar -- see `StageCostume.Apply`) and any character wearing a generated `SkinMesh`, which
-- returns before the shells are built. Both fall back to the avatar's own hand, which is 2.1 x 1.5
-- x 2.1 SMALLER than the mitt the rest of the ladder is sized against -- so without this the same
-- blade is half-size on those bodies and nothing says why. These are `dressBody`'s own numbers,
-- copied rather than required, because reaching into StageCostume for three constants would make a
-- leaf depend on the largest module in ReplicatedStorage.
local BARE_HAND_TO_MITT = Vector3.new(2.1, 1.5, 2.1)

-- Everything a costume part obeys, and for the same reasons `StageCostume.mk` lists: a weapon must
-- never collide with the world, never be raycast (`CombatClient` aims through a mouse ray and the
-- server's hit box walks the rig -- a blade sticking four hand-lengths out would be hit by both),
-- never be touched, never cast a shadow, and never change how the character moves.
local function dressPart(p, size, color, material)
	-- Roblox refuses parts under 0.05 on any axis. A Cell-stage player is small and the guard is a
	-- fraction of a mitt, so without this clamp the first stage in the game throws.
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function mk(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	return dressPart(p, size, color, material)
end

local function weldTo(part, host, offset, folder)
	part.CFrame = host.CFrame * offset
	part.Parent = folder
	local weld = Instance.new("Weld")
	weld.Name = "SwordWeld"
	weld.Part0 = host
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	return part
end

-- The two mitts, and the ruler each blade is sized against. Returns
-- `{ Left = {part, ruler}, Right = {part, ruler} }`; a side may be missing and the caller checks.
local function hostsFor(character)
	local hosts = {}

	local costume = character:FindFirstChild(COSTUME_FOLDER)
	if costume then
		for _, child in ipairs(costume:GetChildren()) do
			if child.Name == HOST_NAME and child:IsA("BasePart") then
				local weld = child:FindFirstChildOfClass("Weld")
				local limb = weld and weld.Part0
				-- `LeftHand` / `RightHand` on R15, `Left Arm` / `Right Arm` on R6 -- a substring
				-- test covers both without a second table, and the mitt is only ever welded to a
				-- hand, so there is nothing else on the character these two words could match.
				if limb and string.find(limb.Name, "Left", 1, true) then
					hosts.Left = { part = child, ruler = child.Size }
				elseif limb and string.find(limb.Name, "Right", 1, true) then
					hosts.Right = { part = child, ruler = child.Size }
				end
			end
		end
	end

	for _, side in ipairs(SIDES) do
		if not hosts[side] then
			local bare = character:FindFirstChild(side .. "Hand")
				or character:FindFirstChild(side .. " Arm")
			if bare then
				hosts[side] = { part = bare, ruler = bare.Size * BARE_HAND_TO_MITT }
			end
		end
	end

	return hosts
end

function SwordModel.Clear(character)
	if not character then return end
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then existing:Destroy() end
end

-- ===== THE BLADE IS SIZED AS A MULTIPLE OF ITS HOST, NEVER IN STUDS =====
--
-- The player runs from a one-stud Cell to a twenty-eight-stud Absolute and any character can be
-- worn at any stage, so a blade authored in absolute studs is a toothpick at one end of the strip
-- and a telegraph pole at the other. Every number below is a fraction of `ruler` -- StageCostume's
-- own rule, and the same one `SkinMesh`'s `ScaleTo` follows.
--
-- IT POINTS DOWN THE HOST'S -Y, which is where `handTrail` already puts its far attachment
-- (`Vector3.new(0, -part.Size.Y * 1.7, 0)`, "reaches PAST the hand, so the ribbon is roughly a
-- weapon's length"). So the steel traces the arc the swoosh has always traced: with the arm
-- hanging the blade points at the floor, and through a swing it sweeps forward ahead of the fist.
-- Anything else would put the ribbon and the sword on two different paths.
--
-- `tier.reach` is the blade's length in mitt-heights and climbs 1.8 -> 3.6 across the ladder, so a
-- tier is legible from across the clearing before its colour is: the rusty stub is a shank and the
-- Absolute Edge is a greatsword.
--
-- **THE LADDER WAS 2.6 -> 5.4 AND IT WAS MEASURED WRONG, ON A REAL BODY.** A blade hangs down the
-- hand's -Y, and the hand's clearance to the floor is small -- 2.17 studs on the owner's own save,
-- because a generated `SkinMesh` can be a QUADRUPED and a quadruped's hands are at ankle height.
-- At 5.4 the tier-10 point finished **6.66 studs below the floor** (measured in Play, not judged
-- off the picture). Halving the ladder puts the worst case near 3 and keeps the full 2x spread
-- between the first blade and the last, which is what makes a tier readable at a glance.
--
-- IT CANNOT BE DRIVEN TO ZERO AND SHOULD NOT BE. A sword that points at the ground touches the
-- ground; the fault was the DEGREE. Changing the axis instead would break the swing, because the
-- arc `CombatClient` throws is exactly this axis (see below).
local function buildBlade(host, ruler, tier, folder, side)
	local h = ruler
	local reach = tier.reach or 3.0
	local mirror = (side == "Left") and -1 or 1

	-- EVERYTHING HANGS OFF THE FIST'S TWO FACES, NOT OFF A FRACTION INSIDE THEM.
	--
	-- This was `h.Y * 0.45` and the first capture is why it is not: the mitt's own half-height IS
	-- 0.5, so a guard centred at 0.45 sat almost entirely INSIDE an opaque box and a pommel centred
	-- at +0.45 was swallowed whole -- four parts a hand of which one was invisible and one showed a
	-- 0.17-stud sliver. A structural probe reports all four welded correctly; only the picture says
	-- two of them cannot be seen.
	local face = h.Y * 0.5

	-- WIDE ENOUGH TO BE A BLADE. 0.44 of the mitt read as a stick against a fist three times its
	-- width -- "fewer big shapes" is the first rule in this game's art notes and a sword that is
	-- thinner than the hand holding it breaks it. Thin in Z so it still reads as an edge from the
	-- side and as a line from the front, which is what makes a swing look like a cut.
	local bw = h.X * 0.62
	local bt = h.Z * 0.22

	-- THE CROSSGUARD, fully below the fist and wider than it. It is the one part that says "this is
	-- a sword and not a stick", and it is drawn before the blade because the blade starts where it
	-- ends -- so the two can never separate however `reach` changes.
	-- 1.38 of the mitt, not 1.55. At 1.55 the guard was as wide as the tier-1 blade was long, and
	-- a fist with a wide flat slab under it reads as a HAMMER HEAD rather than as a hilt -- seen in
	-- the probe capture, not reasoned about. It still has to be clearly wider than the fist or it
	-- stops separating the hand from the steel, which is the only job it has.
	local guardH = h.Y * 0.30
	weldTo(mk("Guard", Vector3.new(h.X * 1.38, guardH, h.Z * 0.55), tier.trim, tier.material),
		host, CFrame.new(0, -(face + guardH * 0.5), 0), folder)

	-- THE POMMEL, fully above the fist, for the same reason: without it the blade appears to grow
	-- out of the back of the hand, which is exactly the fault the row's own check is looking for.
	local pommelH = h.Y * 0.34
	weldTo(mk("Pommel", Vector3.new(h.X * 0.52, pommelH, h.Z * 0.52), tier.trim, tier.material),
		host, CFrame.new(0, face + pommelH * 0.5, 0), folder)

	-- THE BLADE. One big shape, not a stack of segments.
	local bladeTop = -(face + guardH)
	local bladeLen = h.Y * reach
	weldTo(mk("Blade", Vector3.new(bw, bladeLen, bt), tier.color, tier.material),
		host, CFrame.new(0, bladeTop - bladeLen * 0.5, 0), folder)

	-- ===== THE POINT IS TWO WEDGES, AND ONE WEDGE IS WHY =====
	--
	-- A WedgePart is a right triangle in its own YZ plane, uniform along its own X, and its
	-- surviving thin edge is at **y = -Y/2, z = +Z/2** -- one corner, not the middle. So a single
	-- wedge across the whole blade width does not come to a point: it comes to an edge at one SIDE
	-- of the blade, i.e. a chisel end, and that is exactly what the first capture showed. The
	-- picture is what settled it; the part list looked perfect.
	--
	-- Two half-width wedges, mirrored about the blade's centre line, each leaving its surviving edge
	-- at x = 0, is a symmetric point. The two bases below are the same basis turned a half-turn
	-- about the taper axis, and both are right-handed (determinant +1 -- checked, not assumed):
	--
	--     wedge X (uniform thickness) -> host  Z    the blade's thickness
	--     wedge Y (triangle height)   -> host -X for the left half, host +X for the right
	--     wedge Z (taper direction)   -> host -Y    away from the hand, so the taper runs down
	--
	-- Written as an explicit basis rather than as a stack of `CFrame.Angles` nobody can check.
	local tipLen = bladeLen * 0.28
	local tipY = bladeTop - bladeLen - tipLen * 0.5
	for _, half in ipairs({ 1, -1 }) do
		local w = dressPart(Instance.new("WedgePart"),
			Vector3.new(bt, bw * 0.5, tipLen), tier.color, tier.material)
		w.Name = "Tip"
		weldTo(w, host, CFrame.fromMatrix(
			Vector3.new(-half * bw * 0.25, tipY, 0),
			Vector3.new(0, 0, half),        -- wedge X
			Vector3.new(-half, 0, 0),       -- wedge Y
			Vector3.new(0, -1, 0)), folder) -- wedge Z
	end

	-- THE GLOWING EDGE, tiers 7 and up. A thin Neon strip laid ON the blade rather than the blade
	-- being made Neon: Neon takes no shading at all, so a fully Neon blade is a flat self-lit
	-- cut-out with no form -- the exact fault 15.31 had to undo on stage 20's body.
	--
	-- **PROUD OF THE BLADE IN Z (1.3x its thickness), NOT FLUSH WITH IT.** Two coplanar faces
	-- z-fight, and this game has already paid for that twice on the ground
	-- ([[roblox-coplanar-paint-zfights]]); a strip that is thicker than what it lies on can never
	-- share a plane with it. Offset to one side by `mirror` so both blades light their outward face.
	if tier.glow then
		weldTo(mk("Edge", Vector3.new(bw * 0.26, bladeLen * 0.94, bt * 1.3), tier.color, Enum.Material.Neon),
			host, CFrame.new(mirror * bw * 0.28, bladeTop - bladeLen * 0.5, 0), folder)
	end

	-- THE SPARKS, top two tiers only. Parented to the blade so they ride the swing, and rated low:
	-- this runs on every armed player in the server at once, and the rule this repo already paid
	-- for is one cheap emitter, never a per-frame loop.
	if tier.spark then
		local blade = folder:FindFirstChild("Blade")
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(tier.color, tier.trim)
		e.Size = NumberSequence.new(bw, 0)
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(0.25, 0.5)
		e.Rate = 9
		e.Speed = NumberRange.new(0.4, 1.6)
		e.SpreadAngle = Vector2.new(70, 70)
		-- LightEmission ALONE, and `Brightness` is deliberately left at its default: the two levers
		-- do different jobs -- one hides the sprite's black background, the other clips the tint
		-- toward white -- and capping both is what produced a black slab once
		-- ([[roblox-particle-tint-clipping]]).
		e.LightEmission = 0.85
		e.Parent = blade or folder
	end
end

-- ===== THE ONE ENTRY POINT =====
--
-- Idempotent: it clears its own folder first, so calling it twice in a row leaves one sword, not
-- two. That matters because it has two callers with no ordering between them -- the dress hook
-- (every spawn, every evolve, every skin change) and the buy handler (any time at all).
--
-- IT MUST RUN AFTER `StageCostume.Apply`, NEVER BEFORE. The mitt it welds to is built by that
-- call, and a weld whose Part0 is destroyed does not error -- the blade simply detaches and hangs
-- in the air where the hand used to be. `EvolutionVisuals.dress` is the only place that knows when
-- the costume has finished, which is why the hook lives there and not on a timer
-- ([[evolution-lab-body-settles-late]]).
--
-- Returns true when a blade was actually built, so a caller can log a miss rather than assume.
function SwordModel.Apply(character, tier, level)
	if not (character and character.Parent) then
		-- SAID OUT LOUD, like every other bail-out in the dress path. The signature of a silent
		-- return here -- an armed player who is not armed, no parts, no errors -- is the one
		-- written up in `src/STATUS.md` that cost two sessions of looking in the wrong place.
		warn("[SwordModel] no character to arm -- the body left the workspace before Apply ran")
		return false
	end
	SwordModel.Clear(character)
	if not tier then
		warn(("[SwordModel] %s: no tier row handed in -- the player is left unarmed")
			:format(tostring(character.Name)))
		return false
	end

	local hosts = hostsFor(character)
	if not (hosts.Left or hosts.Right) then
		warn(("[SwordModel] %s: no %s and no avatar hand -- sword skipped")
			:format(tostring(character.Name), HOST_NAME))
		return false
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character

	for _, side in ipairs(SIDES) do
		local host = hosts[side]
		if host then
			buildBlade(host.part, host.ruler, tier, folder, side)
		end
	end

	-- ===== THE SWOOSH HAS TO LEARN WHAT IT IS DRAWING =====
	--
	-- `CombatClient.handTrail` builds the ribbon on EVERY machine, for every player it can see, and
	-- it has no access to anyone's save. An attribute on the character is the one channel that
	-- reaches all of them -- the same trick `EvolutionVisuals` uses for `BodyScale` and
	-- `CharacterKey` -- so the trail can take its colour and its length from the blade actually in
	-- the hand instead of staying the hard-coded white-and-gold it has been since the swing was
	-- written. Stamped LAST, after the parts exist, so a client that reacts to the attribute finds
	-- something to react to.
	character:SetAttribute("SwordColor", tier.color)
	character:SetAttribute("SwordReach", tier.reach or 3.0)
	character:SetAttribute("SwordLevel", level or 1)
	return true
end

return SwordModel
