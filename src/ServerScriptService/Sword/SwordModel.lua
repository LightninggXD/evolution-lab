-- SwordModel -- the blade itself, welded to the body the costume just built. Four generated parts
-- a hand on four of the ten rungs; on the other six, one of the owner's own sword meshes (32.13).
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

-- ===== THE BLADE IS ANGLED OUT OF THE REST POSE, AND THAT IS THE WHOLE OF 32.14 =====
--
-- A blade hung straight down the host's -Y is NEVER VISIBLE ON A PLAYER'S OWN BODY, and the
-- numbers are not close. Measured in Play on the owner's own character (a generated `SkinMesh`,
-- six mesh limbs, no mitts): the fist sits 2.0 studs above the floor and INSIDE a 2.5-stud-thick
-- arm mesh, so walking straight down from it the blade is still inside `left leg_geom` /
-- `right leg_geom` at **2.30 studs** and the floor plane arrives at **1.77**. The shortest rung's
-- tip finished 0.38 studs UNDER the ground and the longest 2.43 under. There is no point on any
-- blade that is both outside the body and above the ground -- the first 40% is in the leg and the
-- rest is in the dirt. 32.6 could not have found this: its captures were taken on a probe rig,
-- which has neither legs nor a floor.
--
-- The owner picked the angled pose over shortening the ladder or hiding the sword between swings,
-- so a rung keeps buying a BIGGER sword and the sword is on the body at all times.
--
-- ===== THE ANGLE IS SET AGAINST THE DEFAULT CAMERA, WHICH IS BEHIND THE PLAYER =====
--
-- **THE FIRST TRY WAS 120/15 AND IT PASSED EVERY NUMBER AND FAILED THE ONLY TEST THAT COUNTS.**
-- A blade angled 30 degrees up and forward is out of the leg, out of the ground, and 2 to 4 studs
-- of it stand in open air -- and from where the player is actually looking it cannot be seen at
-- all, because it points AWAY down the camera's own line and the body covers what is left. The
-- capture is unambiguous: a rung-5 sword, opaque body, default camera, nothing on screen.
--
-- So the grid was re-scored against the real camera rather than against open air: read off this
-- character in Play at `(0, +5.36, +11.99)` from the root, FOV 70, counting the fraction of the
-- blade's OWN visible span that the body does not cover.
--
--     pitch  yaw    rung 1 seen   rung 10 seen
--       120   15         0%            35%      <- clears the body, hides behind it
--       135   35        35%            65%
--       150   35        75%            85%      <- this
--       150   75        60%            80%
--
-- 150 is 60 degrees above the horizontal, and the reason it wins is the shoulder: below about 140
-- the blade travels forward faster than it climbs and spends its length behind the torso from a
-- camera that is behind the torso. Yaw 35 carries the two blades out past the arms; past ~55 they
-- start pointing sideways and lose length to foreshortening rather than gaining visibility. The
-- pair reads as raised blades, one to each side, which is also what the capture shows.
--
-- IT IS APPLIED TO THE WHOLE ASSEMBLY, NOT TO THE BLADE. Every piece below is welded at an offset
-- down the host's -Y, so pre-multiplying each offset by this one CFrame turns guard, grip, pommel,
-- blade, point and glow strip together, about the fist, and nothing can separate from anything
-- else. A rotation with no translation leaves the grip exactly where it was: in the hand.
local REST_PITCH = math.rad(150)
local REST_YAW = math.rad(35)

local function restPose(side)
	local mirror = (side == "Left") and -1 or 1
	return CFrame.Angles(0, -mirror * REST_YAW, 0) * CFrame.Angles(REST_PITCH, 0, 0)
end

-- The right hand's blade direction in host-local studs, and the one number the swoosh needs. The
-- left hand's is this with X negated -- a yaw mirrored about the body's centre line negates
-- exactly that component and nothing else -- so ONE attribute carries both sides.
local REST_DIR_RIGHT = restPose("Right"):VectorToWorldSpace(Vector3.new(0, -1, 0))

-- ===== AND THE GRIP STARTS AT THE BODY'S SKIN, NOT AT THE FIST'S CENTRE =====
--
-- The angled pose alone is not enough on the body the owner actually wears, because of the OTHER
-- half of what 32.14 measured: the fist is not on the outside of that body. On a generated
-- `SkinMesh` the visible limb is one mesh part 2.5 studs thick and the avatar's own hand is buried
-- at its centre, so a sword whose guard sits half a mitt-height from the fist has its guard inside
-- the arm. Sampled along the angled blade, the steel did not leave `right arm_geom` until **1.69
-- studs**, which left the shortest rung **0.34 studs** of visible blade -- a nub, and the capture
-- agreed with the number.
--
-- Everything below is authored against `face` -- half the host's own height, the mitt's outer
-- surface -- so the fix is one term: how much DEEPER than that surface this particular body has
-- buried the fist. On a costume body the mitt IS the skin and the walk stops at `face`, so the
-- term is zero and nothing moves; on stage 7's own avatar hand it is zero for the same reason.
-- Only a body that swallows its hands pays anything, and it pays exactly what it swallowed. On
-- hers it comes out at 2.2 to 2.7 studs, which is why the cap is in mitt-heights and generous.
--
-- ===== IT WALKS SAMPLES. IT MUST NOT RAYCAST, AND THAT COST A ROUND TRIP TO FIND OUT =====
--
-- The first version cast a ray inward from outside the body, which is the textbook way to avoid
-- [[roblox-raycast-from-inside-a-part]] -- and it returned nothing on every body, every time, so
-- the standoff shipped inert and measured zero. **A `SkinMesh` limb is `CanQuery = false`** (and
-- `CanCollide = false` with it, so nothing overrides it): it is decoration hung on the avatar, and
-- the engine will not report it to a raycast, a `GetPartBoundsInBox`, or any other spatial query.
-- The very geometry that hides the sword is the geometry no query can see.
--
-- Reading `CFrame` and `Size` off the part cannot be refused, so the walk is done here in Lua
-- against each part's own box. It is an oriented BOUNDING box, so a limb measures slightly fatter
-- than its mesh and the sword is pushed a fraction further out than strictly needed -- the safe
-- direction, on a body where the hand is invisible anyway.
local PROBE_STEPS = 30
local MAX_PUSH = 2.5

local function insideAny(point, solids)
	for _, part in ipairs(solids) do
		local l = part.CFrame:PointToObjectSpace(point)
		local h = part.Size * 0.5
		if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then
			return true
		end
	end
	return false
end

local function standoff(host, ruler, dir, face, solids)
	if not solids or #solids == 0 then return 0 end
	local cap = ruler.Y * MAX_PUSH
	local far = face + cap
	local origin = host.Position
	-- the LAST sample still inside, not the first one outside: a limb the blade re-enters further
	-- along (an arm crossing a thigh) has to be cleared too, or the push stops at the near surface
	local exit = 0
	for i = 1, PROBE_STEPS do
		local t = far * i / PROBE_STEPS
		if insideAny(origin + dir * t, solids) then exit = t end
	end
	return math.clamp(exit - face, 0, cap)
end

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

-- The sparks, top two tiers only. Parented to the blade so they ride the swing, and rated low:
-- this runs on every armed player in the server at once, and the rule this repo already paid for is
-- one cheap emitter, never a per-frame loop.
--
-- Lifted out of `buildBlade` when the mesh blades arrived (32.13) so the two kinds of sword cannot
-- drift into two different sparkles. `size` is the width the sprite is scaled against -- the built
-- blade passes its own `bw`, a mesh blade passes a fraction of the fist.
local function addSparks(parent, tier, size)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(tier.color, tier.trim)
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Rate = 9
	e.Speed = NumberRange.new(0.4, 1.6)
	e.SpreadAngle = Vector2.new(70, 70)
	-- LightEmission ALONE, and `Brightness` is deliberately left at its default: the two levers do
	-- different jobs -- one hides the sprite's black background, the other clips the tint toward
	-- white -- and capping both is what produced a black slab once
	-- ([[roblox-particle-tint-clipping]]).
	e.LightEmission = 0.85
	e.Parent = parent
	return e
end

-- ===== A ROW WITH A `mesh` WEARS HER SWORD INSTEAD OF THE FOUR BUILT PARTS (32.13) =====
--
-- Six of the ten rungs carry one; the other four fall through to `buildBlade` below and are
-- untouched. Where the ids came from, and why they are ids rather than a folder of models to clone,
-- is written out over `GameConfig.Swords`.
--
-- **THE PART'S `Size` DOES NOTHING HERE**, and that is the trap this function exists to contain. A
-- `SpecialMesh` of type `FileMesh` renders its mesh at `Scale` and ignores the Part it hangs on, so
-- the host part stays at the engine's 0.05 floor and every dimension of the sword comes out of
-- `Scale`. Sizing this the way the rest of the file sizes things -- a `Vector3` into `dressPart` --
-- compiles, welds, and reports perfect in a structural probe, while rendering at exactly whatever
-- size the free-model author happened to pick.
--
-- `want / m.length` is the whole scaling story. `m.length` is the long axis of the Handle as
-- shipped, i.e. what this mesh measures at its authored `scale`; `want` is `ruler.Y * reach`, the
-- same length the generated blade gets at this rung. So rung 5 is one sword-length whether it is
-- her Blue Epicness or four grey boxes, and every body from Cell to Absolute gets a blade in
-- proportion to the fist holding it.
--
-- ===== POINTING IT IS TWO SEPARATE PROBLEMS =====
--
-- (1) **The six do not share a long axis.** Four run down Z, two down Y, and one of the four runs
-- down MINUS Z -- so `axis` names it per row and `AXIS_TO_DOWN` is the rotation that carries that
-- axis onto the host's -Y. -Y is not a preference: it is the axis every other piece of this file
-- is built along, and `restPose` turns all of them together at the end (32.14) -- so a blade that
-- does not arrive on -Y first is the one piece the rest pose turns the wrong way, and the swoosh
-- (which is stamped the same rotation, see `SwordRest`) and the steel travel two different paths.
--
-- (2) **The grip has to land in the fist.** `m.grip` is `Tool.Grip.Position` copied verbatim, and
-- that IS the grip point in handle-local studs: Roblox welds a Tool's Handle with `C1 = Grip`, so
-- `Handle.CFrame * Grip` is the hand. It is scaled by the same factor as the mesh and then
-- subtracted back through the rotation, which is what puts that point on the host's origin. Skip it
-- and the sword hangs a hand-length out of the palm -- by a different amount on every rung, because
-- every row's grip sits somewhere else along its own blade.
--
-- Returns false rather than throwing on an axis it does not know, so a mistyped row costs the
-- player the generated blade for that rung instead of an unarmed body and a stack trace.
-- **`axis` ALONE IS NOT ENOUGH, AND ONLY A CAPTURE FINDS THE REST.** Carrying the long axis onto -Y
-- still leaves the blade free to SPIN about it, and a sword is a flat thing: get that roll wrong and
-- it is drawn edge-on, which renders as a wire hanging off the fist. It is welded perfectly, it
-- measures perfectly, and a structural probe cannot tell it from the ones that look right -- the
-- first probe capture had three of six like that.
--
-- The roll is not derivable from `axis`, because these are six models by six authors and their
-- cross-sections are not aligned with each other: `SwordOfDarkness` and `SwordOfLight` are thin in
-- their handle's Y, `SwordOfBlueEpicness` is thin in its X on the SAME long axis, and the two
-- Y-long blades are thin in X again. So `roll` is stated per row, in quarter turns about the blade's
-- own down axis, and it is applied in HOST space -- which is what makes "flat" mean the same thing
-- for all of them. Zero is the answer for a blade whose cross-section is near square (`Wooden`).
--
-- The target is the host's Z, because that is where the GENERATED blade puts its own thin axis
-- (`bt = h.Z * 0.22`). All ten rungs then present the same face and cut along the same edge.
local AXIS_TO_DOWN = {
	["Z+"] = CFrame.Angles(math.pi / 2, 0, 0),   -- ( 0, 0, 1) -> (0,-1,0)
	["Z-"] = CFrame.Angles(-math.pi / 2, 0, 0),  -- ( 0, 0,-1) -> (0,-1,0)
	["Y+"] = CFrame.Angles(math.pi, 0, 0),       -- ( 0, 1, 0) -> (0,-1,0)
}

local function buildMeshBlade(host, ruler, tier, folder, pose)
	local m = tier.mesh
	local rot = AXIS_TO_DOWN[m.axis]
	if not rot then
		warn(("[SwordModel] %s: unknown mesh axis %s -- falling back to the built blade")
			:format(tostring(tier.key), tostring(m.axis)))
		return false
	end
	-- the roll is applied in HOST space, on the outside, so a quarter turn means the same quarter
	-- turn whichever way the blade's own axes happen to be laid out
	rot = CFrame.Angles(0, (m.roll or 0) * math.pi / 2, 0) * rot

	local scale = (ruler.Y * (tier.reach or 3.0)) / m.length

	-- 0.05 on every axis is the engine's floor, and it is the RIGHT size: nothing about this part
	-- is drawn. `dressPart` still runs it through the same no-collide / no-query / no-touch /
	-- massless rules every other piece of the sword obeys -- a blade must never be raycast, because
	-- `CombatClient` aims through a mouse ray and the server's hit box walks the rig.
	local part = mk("Blade", Vector3.new(0.05, 0.05, 0.05), tier.color, Enum.Material.SmoothPlastic)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = "rbxassetid://" .. m.id
	mesh.TextureId = "rbxassetid://" .. m.texture
	mesh.Scale = Vector3.new(m.scale, m.scale, m.scale) * scale
	mesh.Parent = part

	-- `-rot * (grip * scale)`: the scaled grip point, rotated into host space and then cancelled,
	-- so it lands on the host's origin. `weldTo` uses this same CFrame as the weld's C0, so the
	-- blade cannot drift from the hand afterwards.
	--
	-- `pose` is pre-multiplied on the OUTSIDE, so it turns the finished blade about the fist rather
	-- than about the mesh's own origin (32.14), and then slides it out to the body's skin. The grip
	-- point this line just put on the host's origin is the point the whole thing is turned about,
	-- so her sword swings up into the sword-out pose without leaving the hand.
	local offset = pose * CFrame.new(-rot:VectorToWorldSpace(m.grip * scale)) * rot
	weldTo(part, host, offset, folder)

	-- The tier's own glow, as a light rather than as the Neon edge strip the built blade gets: the
	-- mesh already carries its author's texture, and laying a Neon slab on top of it would hide the
	-- one thing this row exists to show.
	if tier.glow then
		local light = Instance.new("PointLight")
		light.Color = tier.color
		light.Range = math.max(ruler.Y * 2, 6)
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = part
	end

	if tier.spark then
		addSparks(part, tier, ruler.X * 0.3)
	end

	return true
end

-- ===== THE BLADE IS SIZED AS A MULTIPLE OF ITS HOST, NEVER IN STUDS =====
--
-- The player runs from a one-stud Cell to a twenty-eight-stud Absolute and any character can be
-- worn at any stage, so a blade authored in absolute studs is a toothpick at one end of the strip
-- and a telegraph pole at the other. Every number below is a fraction of `ruler` -- StageCostume's
-- own rule, and the same one `SkinMesh`'s `ScaleTo` follows.
--
-- IT IS BUILT DOWN THE HOST'S -Y AND THEN TURNED. Every offset below is measured along -Y, the
-- axis `handTrail` has always drawn down, and `restPose` pre-multiplies the lot into the angled
-- rest pose as the last step (32.14). Building it straight and turning it once is what keeps the
-- ribbon and the steel on ONE path: the client is handed that same rotation as `SwordRest` and
-- swings the swoosh along it. Measure a piece here in -Y; the pose is not this function's problem.
--
-- `tier.reach` is the blade's length in mitt-heights and climbs 1.8 -> 3.6 across the ladder, so a
-- tier is legible from across the clearing before its colour is: the rusty stub is a shank and the
-- Absolute Edge is a greatsword.
--
-- **THE LADDER WAS 2.6 -> 5.4 AND IT WAS MEASURED WRONG, ON A REAL BODY.** A blade hung down the
-- hand's -Y, and the hand's clearance to the floor is small -- 2.17 studs on the owner's own save,
-- because a generated `SkinMesh` can be a QUADRUPED and a quadruped's hands are at ankle height.
-- At 5.4 the tier-10 point finished **6.66 studs below the floor** (measured in Play, not judged
-- off the picture). Halving the ladder puts the worst case near 3 and keeps the full 2x spread
-- between the first blade and the last, which is what makes a tier readable at a glance.
--
-- **HALVING IT WAS NOT ENOUGH AND COULD NOT HAVE BEEN** -- 32.14 measured the SHORTEST rung's tip
-- 0.38 studs under the ground. Length was never the fault; the direction was. The reach ladder is
-- left exactly as it is and `restPose` turns the blade out of the floor instead, which is why a
-- rung still buys a bigger sword.
local function buildBlade(host, ruler, tier, folder, side, solids)
	-- 32.13: six of the ten rungs wear one of her swords instead. `buildMeshBlade` returns false on
	-- a row it cannot read, and then this function finishes the job rather than leaving a bare hand.
	--
	-- ===== 32.14: THE POSE, BUILT ONCE HERE AND HANDED TO EVERY PIECE =====
	--
	-- Turned out of the straight-down rest pose and then pushed out to the body's skin, as ONE
	-- CFrame, applied here rather than inside each piece so guard, blade, point and glow can never
	-- come apart. `CFrame.new(restDir * push) * rest` is a translation ALONG the blade's own line:
	-- a design offset of `(0, -d, 0)` lands at `restDir * (push + d)`, so every piece slides the
	-- same distance down the same axis and their spacing is untouched.
	local h = ruler
	local face = h.Y * 0.5
	local rest = restPose(side)
	local restDir = rest:VectorToWorldSpace(Vector3.new(0, -1, 0))
	local push = standoff(host, ruler, host.CFrame:VectorToWorldSpace(restDir), face, solids)
	local pose = CFrame.new(restDir * push) * rest

	if tier.mesh and buildMeshBlade(host, ruler, tier, folder, pose) then
		return
	end

	local reach = tier.reach or 3.0
	local mirror = (side == "Left") and -1 or 1

	-- EVERYTHING HANGS OFF THE FIST'S TWO FACES, NOT OFF A FRACTION INSIDE THEM.
	--
	-- This was `h.Y * 0.45` and the first capture is why it is not: the mitt's own half-height IS
	-- 0.5, so a guard centred at 0.45 sat almost entirely INSIDE an opaque box and a pommel centred
	-- at +0.45 was swallowed whole -- four parts a hand of which one was invisible and one showed a
	-- 0.17-stud sliver. A structural probe reports all four welded correctly; only the picture says
	-- two of them cannot be seen.
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
		host, pose * CFrame.new(0, -(face + guardH * 0.5), 0), folder)

	-- THE POMMEL, fully above the fist, for the same reason: without it the blade appears to grow
	-- out of the back of the hand, which is exactly the fault the row's own check is looking for.
	local pommelH = h.Y * 0.34
	weldTo(mk("Pommel", Vector3.new(h.X * 0.52, pommelH, h.Z * 0.52), tier.trim, tier.material),
		host, pose * CFrame.new(0, face + pommelH * 0.5, 0), folder)

	-- THE BLADE. One big shape, not a stack of segments.
	local bladeTop = -(face + guardH)
	local bladeLen = h.Y * reach
	weldTo(mk("Blade", Vector3.new(bw, bladeLen, bt), tier.color, tier.material),
		host, pose * CFrame.new(0, bladeTop - bladeLen * 0.5, 0), folder)

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
		weldTo(w, host, pose * CFrame.fromMatrix(
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
			host, pose * CFrame.new(mirror * bw * 0.28, bladeTop - bladeLen * 0.5, 0), folder)
	end

	-- THE SPARKS, top two tiers only. Parented to the blade so they ride the swing, and rated low:
	-- this runs on every armed player in the server at once, and the rule this repo already paid
	-- for is one cheap emitter, never a per-frame loop.
	if tier.spark then
		addSparks(folder:FindFirstChild("Blade") or folder, tier, bw)
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

	-- The body as the standoff ray is allowed to see it: what is DRAWN, never what is merely there.
	-- Gathered once for both hands, and after `Clear`, so no blade from a previous Apply is in it.
	local solids = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			table.insert(solids, d)
		end
	end

	for _, side in ipairs(SIDES) do
		local host = hosts[side]
		if host then
			buildBlade(host.part, host.ruler, tier, folder, side, solids)
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
	-- 32.14: and WHICH WAY the blade now leaves the fist. The ribbon used to be hard-coded down the
	-- hand's -Y, which is where the steel used to hang; with the rest pose angled, a trail still
	-- drawn straight down would run through the leg while the sword pointed forward. Stamped as the
	-- right hand's direction, mirrored on the client for the left (see `restPose`).
	character:SetAttribute("SwordRest", REST_DIR_RIGHT)
	character:SetAttribute("SwordLevel", level or 1)
	return true
end

return SwordModel
