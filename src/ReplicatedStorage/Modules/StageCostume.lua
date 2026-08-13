--[[
	StageCostume - the outfit a player wears for their current evolution stage.

	Until this existed, evolving changed exactly two things: the avatar got bigger and the aura
	light changed colour. Twenty stages, one silhouette. Every stage now gets a built costume --
	ears and a tail at Wolf, a visor and a reactor at Cyborg, orbiting crystals and wings at The
	Absolute -- so the thing you are looks different from the thing you were.

	EVERY DIMENSION IS READ OFF THE HOST LIMB, never off a constant. The player's body scales from
	1x at Cell to 9x at The Absolute (EvolutionVisuals drives it from GameConfig.Stages), so a
	costume built from fixed stud sizes is a hat at one end of the game and a house at the other.
	Sizing an ear as "0.34 of the head's width" is correct at every scale, and it also survives a
	player joining on an R6 rig, where the limbs are different sizes entirely.

	Pieces are welded, not anchored: a `Weld` with `Part0` on the limb and the offset in `C0`.
	That means the animation engine carries the whole costume for free -- ears turn with the head,
	a tail swings with the hips -- with no per-frame work anywhere. Anything that has to move on
	its own (a halo, an orbiting shard, a gear) gets its Weld's `C0` tweened on a repeat, which
	stays free in the same way: one tween object, no heartbeat connection.

	Rebuild, don't resize. EvolutionVisuals calls Apply again after the scale tween lands, because
	a welded part keeps the C0 it was given and would otherwise stay the size it was built at.
]]

local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local SkinMesh = require(RS.Modules.SkinMesh)

local StageCostume = {}

local FOLDER_NAME = "StageCostume"
local INK = Color3.fromRGB(20, 14, 28)

local function lighten(c, t) return c:Lerp(Color3.new(1, 1, 1), t) end
local function darken(c, t) return c:Lerp(INK, t) end

-- Stage colours are chosen to read as a *tint on a body*, so several are muted enough to look
-- like dead paint on a Neon part. Anything meant to actually glow gets pushed to full saturation
-- first -- the same fix ZoneBuilder makes for its portal accents.
local function vivid(c)
	local k = math.min(1 / math.max(c.R, c.G, c.B, 0.001), 3)
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

-- ===== BUILD VOCABULARY ======================================================

local function mk(name, size, color, material, transparency, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then p.Shape = shape end
	-- Roblox refuses parts under 0.05 on any axis, and a Cell-stage player is 1x: without this
	-- clamp the smallest details (a pupil, a rivet) throw at the very first stage.
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true -- a costume must never change how the character moves
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- EVERY SPIN BELOW IS AN INFINITE TWEEN, AND DESTROYING A WELD DOES NOT STOP ONE.
--
-- `att` starts `TweenInfo.new(..., -1)` on the weld; `Clear` destroys the folder those welds live
-- in and never cancels a thing. A Tween holds a strong reference to its target, so a destroyed weld
-- keeps having its C0 written forever and can never be collected -- and the part it carries goes
-- with it. Every rebuild of a spinning costume leaked another set, and until the generation token in
-- EvolutionVisuals landed, a single equip could rebuild several times.
--
-- WEAK KEYS: a character that leaves takes its list with it, so this needs no PlayerRemoving hook --
-- which a shared module running on every client has no good place to register anyway.
local spinTweens = setmetatable({}, { __mode = "k" })

-- Everything that moves forever goes through here or `cancelSpins` cannot reach it, and the note
-- above is describing a leak that is still live. Three sites -- `beadRing`, `orbitals` and
-- BUILD[19] -- started their tweens straight off TweenService and registered nothing, so the halo
-- and the orbital sets, which is most of the late game, kept writing to destroyed welds after every
-- rebuild. Anything with a `Cancel` method may be registered, not only a Tween: the turn chains
-- below hand in a table.
local function register(ctx, canceller)
	local list = spinTweens[ctx.character]
	if not list then
		list = {}
		spinTweens[ctx.character] = list
	end
	table.insert(list, canceller)
	return canceller
end

local function cancelSpins(character)
	local list = spinTweens[character]
	if not list then return end
	for _, tween in ipairs(list) do
		tween:Cancel()
	end
	spinTweens[character] = nil
end

-- A FULL TURN CANNOT BE ONE REPEATING TWEEN, and both ways of writing it fail in silence.
-- `CFrame.Angles(0, 0, math.pi * 2)` is the IDENTITY, so the tween's goal is its own start value and
-- the piece never moves at all -- which is precisely what the stage 13 clock hands did. Overshooting
-- is worse than useless: a CFrame tween interpolates the rotation the SHORT way, so a goal of 4pi/3
-- runs backwards by 2pi/3. So a full circle is walked in THIRDS, each third its own tween, the next
-- one starting from where the last one landed. Three keyframes a revolution, and still no per-frame
-- work anywhere -- which is the promise at the top of this file and the reason this is not a
-- Heartbeat loop.
--
-- `symmetry` is the escape hatch and the cheaper path: an arrangement that repeats every 2pi/n
-- (six gear teeth, fourteen halo beads) only ever has to travel one gap, and one gap is under a
-- half turn for any n >= 3, so a single repeating tween is exact and the jump back is invisible.
-- That is `orbitals`' trick, taught to turn around a pivot.
--
-- `pivot` is the frame the piece turns AROUND, which is not the frame the piece IS AT. A clock hand
-- is a bar whose offset already carries it half its own length off the spindle; post-multiplying a
-- rotation onto that offset -- what `spin` does -- turns it about its own middle instead, which
-- reads as a bar wobbling in place rather than as a hand sweeping the dial.
-- AND A CARRIED PIECE MUST NEVER BE TWEENED DIRECTLY, because a CFrame tween is not a rotation:
-- it slerps the rotation but LERPS THE POSITION, in a straight line between the two keyframes. A
-- piece whose C0 is `pivot * R * rel` therefore crosses the CHORD instead of riding the arc, and its
-- distance from the pivot collapses to cos(half the step) at the midpoint. Measured on the shipped
-- build before this: the minute hand fell to exactly **50.0%** of its own reach every third of a
-- turn (a 120-degree step) and the gear teeth to 86.6% (60 degrees) -- a clock hand telescoping in
-- and out of its own spindle, which is worse than the dead hand it replaced.
--
-- So what turns is a HUB: an empty part pinned at the pivot, whose own C0 is `pivot * R`. That has
-- the SAME position component at every angle, so the lerp is between two identical points and only
-- the slerp is left -- an exact circle at constant speed. The pieces hang off the hub with fixed
-- offsets and are carried perfectly. One hub serves every piece sharing a pivot and a period, which
-- is also what keeps six gear teeth in lockstep rather than in six independent tweens.
local TURN_STEPS = 3

local function driveHub(ctx, weld, pivot, axis, seconds, symmetry)
	local n = math.max(symmetry or 1, 1)
	-- negative seconds means the other way round, the convention `beadRing` already uses. It is
	-- read HERE rather than handed to TweenInfo, where a negative duration is simply invalid.
	local dir = seconds < 0 and -1 or 1
	local period = math.abs(seconds)

	if n >= TURN_STEPS then
		local tween = TweenService:Create(weld,
			TweenInfo.new(period / n, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ C0 = pivot * CFrame.fromAxisAngle(axis, dir * math.pi * 2 / n) })
		tween:Play()
		register(ctx, tween)
		return
	end

	local goals = {}
	for k = 0, TURN_STEPS - 1 do
		goals[k] = pivot * CFrame.fromAxisAngle(axis, dir * k * math.pi * 2 / TURN_STEPS)
	end

	local chain = { k = 0 }
	function chain:Cancel()
		self.stopped = true
		if self.tween then self.tween:Cancel() end
	end

	local function play()
		if chain.stopped or not weld.Parent then return end
		chain.k = (chain.k + 1) % TURN_STEPS
		local tween = TweenService:Create(weld, TweenInfo.new(period / TURN_STEPS, Enum.EasingStyle.Linear),
			{ C0 = goals[chain.k] })
		chain.tween = tween
		-- A cancelled tween reports `Cancelled` here, and that is the only way this chain ever
		-- learns to stop: `Clear` destroys the welds and would otherwise leave it starting a fresh
		-- tween on a dead one every third of a turn, forever.
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then play() end
		end)
		tween:Play()
	end

	register(ctx, chain)
	play()
end

-- The turning hub for one (host, pivot, axis, period) group, made once and shared.
local function turnHub(ctx, hostPart, turn)
	local pivot = turn.pivot or CFrame.new()
	local axis = turn.axis or Vector3.new(0, 0, 1)
	local seconds = turn.seconds or 6
	local key = ("%s|%s|%s|%s|%s"):format(hostPart:GetFullName(), tostring(pivot), tostring(axis),
		tostring(seconds), tostring(turn.symmetry))
	ctx.turnHubs = ctx.turnHubs or {}
	local hub = ctx.turnHubs[key]
	if hub then return hub, pivot end

	-- Transparent and 0.05 on every axis: it is a frame, not a shape. It still has to be a real Part
	-- because a Weld needs two of them, and it is parented into the costume folder like everything
	-- else so `Clear` takes it with the rest.
	hub = mk("StageTurnHub", Vector3.new(0.05, 0.05, 0.05), Color3.new(1, 1, 1), nil, 1)
	hub.CFrame = hostPart.CFrame * pivot
	hub.Parent = ctx.folder

	local weld = Instance.new("Weld")
	weld.Name = "CostumeWeld"
	weld.Part0 = hostPart
	weld.Part1 = hub
	weld.C0 = pivot
	weld.Parent = hub

	driveHub(ctx, weld, pivot, axis, seconds, turn.symmetry)
	ctx.turnHubs[key] = hub
	return hub, pivot
end

-- Hangs `part` off `hostPart` at `offset`. `spin` is { rx, ry, rz, seconds } and makes the piece
-- turn forever by tweening the weld. The rotation has to be exactly one step of the arrangement's
-- own symmetry, or the tween's jump back to its start value is visible as a stutter -- so orbiting
-- sets are always built evenly spaced and spun by one full gap.
local function att(ctx, part, hostPart, offset, spin, turn)
	if not hostPart then
		part:Destroy()
		return nil
	end
	part.CFrame = hostPart.CFrame * offset
	part.Parent = ctx.folder

	-- A turning piece is welded to the hub instead of to the limb, at the offset that puts it exactly
	-- where it would have been -- so a builder writes the piece's place in the limb's frame either
	-- way and never has to know a hub exists.
	local anchorPart, anchorOffset = hostPart, offset
	if turn then
		local hub, pivot = turnHub(ctx, hostPart, turn)
		anchorPart, anchorOffset = hub, pivot:Inverse() * offset
	end

	local weld = Instance.new("Weld")
	weld.Name = "CostumeWeld"
	weld.Part0 = anchorPart
	weld.Part1 = part
	weld.C0 = anchorOffset
	weld.Parent = part

	if spin then
		local tween = TweenService:Create(weld, TweenInfo.new(spin[4] or 6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
			C0 = anchorOffset * CFrame.Angles(spin[1] or 0, spin[2] or 0, spin[3] or 0),
		})
		tween:Play()
		-- registered so Clear can cancel it; see the note above cancelSpins
		register(ctx, tween)
	end
	return part
end

-- The one call every builder below uses. opts: { mat, tr, shape, spin, turn }
--
-- `spin` turns the piece about its OWN centre by a fixed angle and loops there; `turn` carries it
-- around a pivot for a whole revolution. Use `spin` only where the angle is a real symmetry step of
-- the arrangement -- it is the older of the two and half its uses were a rotation nobody can see.
local function P(ctx, hostPart, name, size, offset, color, opts)
	opts = opts or {}
	return att(ctx, mk(name, size, color, opts.mat, opts.tr, opts.shape), hostPart, offset, opts.spin, opts.turn)
end

-- A flat disc lying in the XZ plane: haloes, rings, clock faces, gears. Cylinders point along
-- their own X, so every one of them needs the same 90-degree roll to lie down.
local FLAT = CFrame.Angles(0, 0, math.rad(90))
-- ... and the same disc stood up facing forward, for chest plates and clock dials.
local FACE = CFrame.Angles(0, math.rad(90), 0)

local function ring(ctx, hostPart, name, diameter, thickness, y, color, opts)
	return P(ctx, hostPart, name, Vector3.new(thickness, diameter, diameter),
		CFrame.new(0, y, 0) * FLAT, color, opts)
end

-- Evenly spaced copies around a circle. `fn(i, angle, offsetCF)` builds one.
local function orbit(ctx, count, radius, y, fn)
	for i = 1, count do
		local a = (i - 1) * math.pi * 2 / count
		fn(i, a, CFrame.new(math.cos(a) * radius, y, math.sin(a) * radius) * CFrame.Angles(0, -a, 0))
	end
end

local function emitter(parent, color, size, rate, speed, lifetime)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color, lighten(color, 0.6))
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Parent = parent
	return e
end

-- ===== THE BODY ITSELF =======================================================
--
-- Everything above this line decorates an avatar. That was the whole design and it was wrong: a
-- player at Cyborg was a default Roblox avatar -- thin dark stick legs and all -- with a reactor
-- and some pauldrons bolted to it, which is not "you turn into the thing you evolved into", it is
-- a costume rental. Screenshot of it: a box with two sticks under it, and the report was blunt --
-- "there aren't even legs here".
--
-- So every stage now REPLACES the body. Each limb gets a chunky shell welded to it, the avatar's
-- own parts are made invisible, and the stage's own details (above) go on top of the result.
--
-- Welding one shell per limb rather than building one rigid creature is the entire trick: the
-- animation engine already moves the limbs, so the shells walk, run, jump and swing for free with
-- no per-frame work anywhere. It also keeps the Humanoid's real collision box untouched, which is
-- what stops a wider body from catching on doorways it used to fit through.
--
-- Growth factors, and why they are what they are:
--   * the HEAD becomes a cube off its own largest dimension. Roblox's head is a wide flat block,
--     and scaling it uniformly keeps it a wide flat block; the reference art (and this game's own
--     PetModel) is an oversized cube, which is most of what makes a rig read as drawn.
--   * arms and legs grow only in X and Z. Growing them in Y would push hands through the floor.
--   * legs stop at 1.3: two 1.55-wide shells on hips one stud apart merge into a single slab.
-- Tuned against a screenshot, not derived. The first pass at 1.3 / 1.2 / 1.5 / 1.3 produced a
-- correct body that still read as an avatar in a coat: the head was smaller than the shoulders and
-- the limbs were pencils. Big head, thick limbs -- that is the entire difference between this and
-- the reference art, and it is the same note already written down about the pets.
-- These sit on top of EvolutionVisuals' own PROPORTION pass, which already makes the rig short,
-- wide and big-headed. They are therefore smaller than they look: the head is 1.35 of a head that
-- is already 1.55x, and the torso 1.18 of one already 1.28x wide.
local HEAD_GROW = 1.18  -- of the head's LARGEST axis, as a cube
local TORSO_W, TORSO_D = 1.18, 1.45
-- how far down the torso shell reaches, as a multiple of the UPPER torso's height. It deliberately
-- does NOT swallow the whole lower torso: covered to the hips, the legs disappear into the chest
-- and the character is a box on two stubs -- which is the thing this rewrite exists to fix.
local TORSO_H = 1.3
-- 1.7 read as two planks stuck out of the shoulders: the classic build already has short arms, so
-- a shell wider than the arm is long stops being an arm and becomes a wing.
local ARM_GROW = 1.45
local LEG_GROW = 1.4

-- Per-stage overrides. Sparse on purpose -- the default chunky body is right for most of the
-- twenty, and the stages that differ differ for a reason, not for variety's sake.
local BODY = {
	-- the single-celled stages are blobs, not bodies
	[1] = { shape = Enum.PartType.Ball, tr = 0.35, headGrow = 1.15 },
	[2] = { shape = Enum.PartType.Ball, tr = 0.2 },
	[3] = { shape = Enum.PartType.Ball },
	-- Human: the one stage that IS a person. No shell at all -- see Apply.
	[8] = { mat = Enum.Material.Metal, limbMat = Enum.Material.Metal },   -- Cyborg
	[9] = { headGrow = 1.5 },                                            -- Alien: the head takes over
	[13] = { mat = Enum.Material.Metal, limbMat = Enum.Material.Metal },  -- machine stages
	[17] = { tr = 0.25 },
	[18] = { mat = Enum.Material.Marble },
	[19] = { tr = 0.2 },
	[20] = { mat = Enum.Material.Neon, tr = 0.12 },
}

-- One shell over `hostName`, sized as a multiple of that host. `spanName` lets a shell swallow the
-- limb below it (forearm + hand, upper torso + lower torso) so the body reads as few big shapes
-- rather than as a stack of segments -- the first rule in this game's art notes.
local function shell(ctx, hostName, spanName, name, gx, gy, gz, color, opts, dy)
	local host = ctx.character:FindFirstChild(hostName)
	if not host then return nil end
	local span = spanName and ctx.character:FindFirstChild(spanName)
	local extra = span and span.Size.Y or 0
	return P(ctx, host, name,
		Vector3.new(host.Size.X * gx, host.Size.Y * gy + extra, host.Size.Z * gz),
		-- a swallowed limb hangs below the host, so the pair's centre drops by half its height
		CFrame.new(0, -extra / 2 + (dy or 0) * host.Size.Y, 0), color, opts)
end

local function dressBody(ctx, spec)
	spec = spec or {}
	local body = spec.body or ctx.color
	-- The limbs have to be clearly darker than the torso or the whole thing is one silhouette with
	-- no arms or legs in it -- which is exactly how the first build came out.
	local limbColor = spec.limb or darken(body, 0.4)
	local belly = spec.belly or lighten(body, 0.45)
	local opts = { mat = spec.mat, tr = spec.tr, shape = spec.shape }
	local limbOpts = { mat = spec.limbMat or spec.mat, tr = spec.tr, shape = spec.shape }

	-- HEAD: a cube off the head's largest axis, so it is a cube at every rig and every scale
	local h = ctx.head
	local k = math.max(h.Size.X, h.Size.Y, h.Size.Z) * (spec.headGrow or HEAD_GROW)
	-- lifted clear of the shoulders: a cube this size centred on the head reaches down into the
	-- chest, and a head growing out of the ribs reads as a mistake rather than as no-neck styling
	P(ctx, h, "BodyHead", Vector3.new(k, k, k), CFrame.new(0, k * 0.1, 0), spec.headColor or body, opts)

	-- TORSO: one shell over both halves. Welded to the UPPER torso, because that is the part the
	-- waist joint turns -- hung off the lower one the whole chest would stay square to the hips.
	local upperName = ctx.character:FindFirstChild("UpperTorso") and "UpperTorso" or "Torso"
	-- reaches PAST the upper torso and part way down the lower one, rather than swallowing it whole
	shell(ctx, upperName, nil, "BodyTorso", TORSO_W, TORSO_H, TORSO_D, body, opts, -(TORSO_H - 1) * 0.5)
	local ts = ctx.torsoSize
	-- A shoulder yoke across the top in the limb colour. Without it the arms grow straight out of
	-- the chest in one unbroken block and the body has no shoulders at all -- this is the line that
	-- separates "torso" from "arms" at a glance, which no amount of shading does on its own.
	P(ctx, ctx.torso, "BodyYoke", Vector3.new(ts.X * 1.04, ts.Y * 0.3, ts.Z * 1.04),
		CFrame.new(0, ts.Y * 0.4, 0), limbColor, opts)
	-- and a neck to close the gap the lifted head cube opens over the shoulders. Without it the head
	-- floats: the shells are two separate boxes with daylight between them from every low angle.
	P(ctx, ctx.torso, "BodyNeck", Vector3.new(ts.X * 0.44, ts.Y * 0.5, ts.Z * 0.6),
		CFrame.new(0, ts.Y * 0.6, 0), limbColor, opts)
	P(ctx, ctx.torso, "BodyBelly", Vector3.new(ts.X * 0.66, ts.Y * 1.05, ts.Z * 0.2),
		CFrame.new(0, -ts.Y * 0.1, -ts.Z * 0.46), belly, { mat = spec.mat, tr = spec.tr })

	for _, side in ipairs({ "Left", "Right" }) do
		if ctx.character:FindFirstChild(side .. "UpperArm") then
			-- EVERY LIMB TAPERS. Upper arm wider than forearm, thigh wider than shin, and a mitt and a
			-- boot wider than either -- which is the shape a drawn character has and a stack of equal
			-- tubes does not. It is the same rule as the creature rigs: the silhouette carries it.
			shell(ctx, side .. "UpperArm", nil, "BodyArm", ARM_GROW, 1.04, ARM_GROW, limbColor, limbOpts)
			shell(ctx, side .. "LowerArm", nil, "BodyForearm", ARM_GROW * 0.86, 1.02, ARM_GROW * 0.86, limbColor, limbOpts)
			-- the mitt. A hand this size on a thin wrist is most of what sells a chunky rig, and it is
			-- also what the swing animation is actually throwing -- the Trail comes off this part.
			shell(ctx, side .. "Hand", nil, "BodyHand", 2.1, 1.5, 2.1, darken(limbColor, 0.16), limbOpts)
			shell(ctx, side .. "UpperLeg", nil, "BodyThigh", LEG_GROW, 1.02, LEG_GROW, limbColor, limbOpts)
			shell(ctx, side .. "LowerLeg", nil, "BodyShin", LEG_GROW * 0.88, 1.02, LEG_GROW * 0.88, limbColor, limbOpts)
			-- the foot is deliberately out of proportion: a chunky rig with dainty feet reads as
			-- unbalanced, and a big flat boot is what plants it on the ground instead of over it
			shell(ctx, side .. "Foot", nil, "BodyFoot", 1.7, 1.7, 1.5, darken(limbColor, 0.22), limbOpts)
		else
			-- R6: two limbs a side instead of five, same idea
			shell(ctx, side .. " Arm", nil, "BodyArm", ARM_GROW, 1.02, ARM_GROW, limbColor, limbOpts)
			shell(ctx, side .. " Leg", nil, "BodyLeg", LEG_GROW, 1.02, LEG_GROW, limbColor, limbOpts)
		end
	end
end

-- Hides (or restores) the player's own avatar under the shells. Only the parts parented DIRECTLY
-- to the character, so it can never touch the costume, the pets or anything else living inside it.
--
-- Decals need doing by hand: a Decal on a fully transparent part still renders, so without this
-- the avatar's face floats inside the new head.
--
-- THE ATTRIBUTE NAME IS SHARED WITH SkinMesh, and it is cleared on restore. Both modules hide the
-- same avatar parts, and while they used two different names neither ever removed, each could record
-- the other's hidden 1 as the "original" transparency -- a player left permanently invisible. See the
-- longer note above SkinMesh's copy of this sweep; the two must keep the same string.
local BASE_TRANSPARENCY = "BodyBaseTransparency"

local function setBodyHidden(character, hidden)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if hidden and part:GetAttribute(BASE_TRANSPARENCY) == nil then
				part:SetAttribute(BASE_TRANSPARENCY, part.Transparency)
			end
			part.Transparency = hidden and 1 or (part:GetAttribute(BASE_TRANSPARENCY) or 0)
			part.LocalTransparencyModifier = hidden and 1 or 0
			if not hidden then part:SetAttribute(BASE_TRANSPARENCY, nil) end
			for _, d in ipairs(part:GetChildren()) do
				if d:IsA("Decal") or d:IsA("Texture") then
					if hidden and d:GetAttribute(BASE_TRANSPARENCY) == nil then
						d:SetAttribute(BASE_TRANSPARENCY, d.Transparency)
					end
					d.Transparency = hidden and 1 or (d:GetAttribute(BASE_TRANSPARENCY) or 0)
					if not hidden then d:SetAttribute(BASE_TRANSPARENCY, nil) end
				end
			end
		end
	end
end

-- ===== SHARED FEATURES =======================================================
-- Bits that recur across several stages. Each is written once and parameterised, because a wolf's
-- ears and a lizard's frill are the same three lines with different numbers.

-- FLAT eyes, standing PROUD of the face -- the same pair PetModel draws, and for the same reason:
-- two big flat eyes are most of what makes a blocky head read as a character rather than a crate.
--
-- They used to be balls centred on `-headDepth * forward`, with `forward` a fraction each caller
-- guessed at (0.45 to 0.5). Against a bare avatar head that was roughly its surface. The head is a
-- cube half again that size now, so every one of those guesses landed INSIDE it and all twenty
-- faces came out as two pinholes in a blank block. The face plane is measured off the head rather
-- than guessed at, and `forward` only nudges it outward from there.
local function eyes(ctx, whiteColor, pupilColor, size, spread, forward)
	local h, hs = ctx.head, ctx.headSize
	local faceZ = -hs.Z * (0.5 + math.max((forward or 0.5) - 0.5, 0))
	local w = hs.X * size * 1.5
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, h, "StageEye", Vector3.new(w, hs.Y * size * 2.0, hs.Z * 0.08),
			CFrame.new(side * hs.X * spread * 1.15, hs.Y * 0.1, faceZ - hs.Z * 0.03), whiteColor)
		P(ctx, h, "StagePupil", Vector3.new(w * 0.44, hs.Y * size * 1.05, hs.Z * 0.06),
			CFrame.new(side * hs.X * spread * 1.15, hs.Y * 0.08, faceZ - hs.Z * 0.06), pupilColor)
	end
end

local function pointedEars(ctx, color, innerColor, height, tilt)
	local h, hs = ctx.head, ctx.headSize
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, h, "StageEar", Vector3.new(hs.X * 0.3, hs.Y * height, hs.Z * 0.28),
			CFrame.new(side * hs.X * 0.32, hs.Y * (0.45 + height * 0.5), 0) * CFrame.Angles(0, 0, side * tilt), color)
		P(ctx, h, "StageEarInner", Vector3.new(hs.X * 0.15, hs.Y * height * 0.6, hs.Z * 0.12),
			CFrame.new(side * hs.X * 0.32, hs.Y * (0.45 + height * 0.45), -hs.Z * 0.12) * CFrame.Angles(0, 0, side * tilt), innerColor)
	end
end

local function snout(ctx, color, noseColor, length)
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageSnout", Vector3.new(hs.X * 0.42, hs.Y * 0.34, hs.Z * length),
		CFrame.new(0, -hs.Y * 0.1, -hs.Z * (0.4 + length * 0.4)), color)
	P(ctx, h, "StageNose", Vector3.new(hs.X * 0.2, hs.Y * 0.16, hs.Z * 0.16),
		CFrame.new(0, -hs.Y * 0.04, -hs.Z * (0.4 + length * 0.85)), noseColor, { shape = Enum.PartType.Ball })
end

-- A tapering tail off the hips. Segments shrink and droop, so it reads as hanging rather than as
-- a plank bolted on the back.
local function tail(ctx, color, tipColor, segments, thickness, droop)
	local l, ls = ctx.lower, ctx.lowerSize
	local cf = CFrame.new(0, -ls.Y * 0.1, ls.Z * 0.5)
	for i = 1, segments do
		local t = 1 - (i - 1) / segments * 0.55
		local len = ls.Z * 0.55 * t
		cf = cf * CFrame.Angles(-droop, 0, 0) * CFrame.new(0, 0, len * 0.5)
		P(ctx, l, "StageTail", Vector3.new(ls.X * thickness * t, ls.Y * thickness * t, len),
			cf, i == segments and tipColor or color)
		cf = cf * CFrame.new(0, 0, len * 0.5)
	end
end

local function backSpines(ctx, color, count, height)
	local t, ts = ctx.torso, ctx.torsoSize
	for i = 1, count do
		local f = (i - 1) / math.max(count - 1, 1)
		P(ctx, t, "StageSpine", Vector3.new(ts.X * 0.1, ts.Y * height * (1 - f * 0.45), ts.Z * 0.3),
			CFrame.new(0, ts.Y * (0.4 - f * 0.7), ts.Z * 0.42) * CFrame.Angles(math.rad(-18), 0, 0), color)
	end
end

local function pauldrons(ctx, color, trimColor, size, mat)
	local t, ts = ctx.torso, ctx.torsoSize
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, t, "StagePauldron", Vector3.new(ts.X * size, ts.Y * size * 0.55, ts.Z * size * 1.5),
			CFrame.new(side * ts.X * 0.6, ts.Y * 0.34, 0) * CFrame.Angles(0, 0, side * math.rad(-14)), color, { mat = mat })
		P(ctx, t, "StagePauldronTrim", Vector3.new(ts.X * size * 1.06, ts.Y * size * 0.12, ts.Z * size * 1.56),
			CFrame.new(side * ts.X * 0.6, ts.Y * (0.34 + size * 0.3), 0) * CFrame.Angles(0, 0, side * math.rad(-14)), trimColor, { mat = Enum.Material.Neon })
	end
end

-- A crown sits on the FRONT half of the head only. A full ring of spikes is mostly invisible (it
-- is behind the skull) and the ones at the back poke through whatever hair the avatar is wearing.
local function crown(ctx, color, spikes, height)
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageCrownBand", Vector3.new(hs.X * 1.1, hs.Y * 0.16, hs.Z * 1.1),
		CFrame.new(0, hs.Y * 0.54, 0), color, { mat = Enum.Material.Neon })
	for i = 1, spikes do
		-- spread across the front 200 degrees, tallest in the middle
		local t = spikes > 1 and ((i - 1) / (spikes - 1) - 0.5) or 0
		local a = t * math.rad(200)
		local tall = height * (1 - math.abs(t) * 0.85)
		P(ctx, h, "StageCrownSpike", Vector3.new(hs.X * 0.13, hs.Y * tall, hs.Z * 0.13),
			CFrame.new(0, hs.Y * 0.6, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -hs.Z * 0.5)
				* CFrame.Angles(math.rad(-9), 0, 0) * CFrame.new(0, hs.Y * tall * 0.5, 0),
			color, { mat = Enum.Material.Neon })
	end
end

-- A halo, built as a RING OF BEADS rather than as a cylinder. A Roblox cylinder is solid, so the
-- first version of this put a thirteen-stud dinner plate over every late-stage player's head. There
-- is no torus primitive, so a circle of small blocks is the ring -- and it has the side benefit of
-- reading as a chain of lights rather than as a smooth band, which suits the chunky art.
local function beadRing(ctx, hostPart, name, count, radius, bead, color, opts, centreCF)
	opts = opts or {}
	local step = math.pi * 2 / count
	for i = 1, count do
		local a = (i - 1) * step
		local off = (centreCF or CFrame.new()) * CFrame.Angles(0, a, 0) * CFrame.new(radius, 0, 0)
		local p = P(ctx, hostPart, name, Vector3.new(bead * 0.8, bead * 0.8, bead * 2.1), off * CFrame.Angles(0, math.rad(90), 0),
			color, { mat = opts.mat or Enum.Material.Neon, tr = opts.tr or 0.15 })
		if p and opts.seconds then
			local weld = p:FindFirstChild("CostumeWeld")
			local tween = TweenService:Create(weld, TweenInfo.new(math.abs(opts.seconds), Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				C0 = (centreCF or CFrame.new()) * CFrame.Angles(0, a + (opts.seconds > 0 and step or -step), 0)
					* CFrame.new(radius, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
			})
			tween:Play()
			register(ctx, tween)
		end
	end
end

local function halo(ctx, color, diameter, y, seconds, tilt)
	local h, hs = ctx.head, ctx.headSize
	local radius = hs.X * diameter * 0.5
	beadRing(ctx, h, "StageHalo", 14, radius, hs.X * 0.13, color,
		{ seconds = seconds, tr = 0.1 },
		CFrame.new(0, hs.Y * y, 0) * CFrame.Angles(tilt or 0, 0, 0))
end

-- A set of shapes orbiting the torso. The signature of every late stage, and the reason they all
-- read as "powerful" without any of them needing more parts than a hat.
local function orbitals(ctx, count, color, size, radius, seconds, shape, mat, yFrac)
	local t, ts = ctx.torso, ctx.torsoSize
	local step = math.pi * 2 / count
	local lift = CFrame.new(0, ts.Y * (yFrac or 0.1), 0)
	for i = 1, count do
		local a = (i - 1) * step
		local off = lift * CFrame.Angles(0, a, 0) * CFrame.new(ts.X * radius, 0, 0)
		local p = P(ctx, t, "StageOrbital", Vector3.new(ts.X * size, ts.X * size, ts.X * size),
			off, color, { mat = mat or Enum.Material.Neon, shape = shape, tr = 0.05 })
		-- Each piece is carried one full gap around the torso and the tween loops there. Because
		-- the set is evenly spaced, the position it snaps back to is the position its neighbour
		-- just left -- so the ring appears to turn forever with no per-frame work and no visible
		-- jump. Spinning them individually (rather than parenting to one turning anchor) is what
		-- keeps the whole thing to one weld per piece.
		if p then
			local weld = p:FindFirstChild("CostumeWeld")
			local tween = TweenService:Create(weld, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				C0 = lift * CFrame.Angles(0, a + step, 0) * CFrame.new(ts.X * radius, 0, 0),
			})
			tween:Play()
			register(ctx, tween)
		end
	end
end

-- Wings. `kind` is "feather" (stacked tapering blades), "bat" (a membrane on two struts) or
-- "energy" (translucent neon sheets). All three hang off the upper torso and sweep back, so they
-- never clip through the arms during a walk cycle.
local function wings(ctx, kind, color, trimColor, span)
	local t, ts = ctx.torso, ctx.torsoSize
	for _, side in ipairs({ -1, 1 }) do
		local rootCF = CFrame.new(side * ts.X * 0.3, ts.Y * 0.28, ts.Z * 0.55) * CFrame.Angles(0, side * math.rad(-32), 0)
		if kind == "feather" then
			-- Three broad blades, not four narrow ones. Narrow blades at this scale read as a handful
			-- of sticks; the silhouette has to be a wing before any detail on it matters.
			for i = 1, 3 do
				local f = (i - 1) / 2
				P(ctx, t, "StageWing", Vector3.new(ts.X * 0.14, ts.Y * (1.35 - f * 0.42) * span, ts.Z * (0.86 - f * 0.2) * span),
					rootCF * CFrame.new(side * ts.X * (0.45 + f * 0.62) * span, ts.Y * (0.24 - f * 0.42) * span, 0)
						* CFrame.Angles(0, 0, side * math.rad(-16 - i * 12)),
					i == 2 and trimColor or color)
			end
		elseif kind == "bat" then
			for i = 1, 3 do
				P(ctx, t, "StageWingStrut", Vector3.new(ts.X * 0.09, ts.Y * 1.5 * span, ts.Z * 0.09),
					rootCF * CFrame.new(side * ts.X * (0.4 + i * 0.4) * span, ts.Y * (0.4 - i * 0.3) * span, 0)
						* CFrame.Angles(0, 0, side * math.rad(-20 - i * 16)), trimColor)
			end
			P(ctx, t, "StageWingMembrane", Vector3.new(ts.X * 0.06, ts.Y * 1.5 * span, ts.Z * 1.7 * span),
				rootCF * CFrame.new(side * ts.X * 0.9 * span, -ts.Y * 0.1 * span, 0) * CFrame.Angles(0, 0, side * math.rad(-30)),
				color, { tr = 0.15 })
		else
			for i = 1, 3 do
				P(ctx, t, "StageWing", Vector3.new(ts.X * 0.07, ts.Y * (1.7 - i * 0.35) * span, ts.Z * 0.34 * span),
					rootCF * CFrame.new(side * ts.X * (0.35 + i * 0.42) * span, ts.Y * (0.3 - i * 0.34) * span, 0)
						* CFrame.Angles(0, 0, side * math.rad(-16 - i * 13)),
					i == 2 and trimColor or color, { mat = Enum.Material.Neon, tr = 0.3 })
			end
		end
	end
end

-- A cloak: two long panels off the shoulders that meet at the back. Cheap, and it is the single
-- fastest way to make a humanoid silhouette read as a sovereign rather than as a person.
local function cloak(ctx, color, trimColor, length)
	local t, ts = ctx.torso, ctx.torsoSize
	-- collar first: a raised band across the shoulders, which is what makes the cape read as worn
	-- rather than as a board leaning against someone's back
	P(ctx, t, "StageCloakCollar", Vector3.new(ts.X * 1.22, ts.Y * 0.26, ts.Z * 0.9),
		CFrame.new(0, ts.Y * 0.44, ts.Z * 0.3), trimColor)
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, t, "StageCloakWing", Vector3.new(ts.X * 0.34, ts.Y * 0.5, ts.Z * 0.34),
			CFrame.new(side * ts.X * 0.56, ts.Y * 0.4, ts.Z * 0.28) * CFrame.Angles(0, 0, side * math.rad(-22)), trimColor)
	end

	-- ONE cape, not two panels. Two panels at +/-0.3 of the torso width overlapped into a single
	-- slab down the middle and read as a plank. A single sheet that widens as it falls is a cape.
	local drop = ts.Y * length
	for i = 1, 3 do
		local f = (i - 1) / 2
		P(ctx, t, "StageCloak", Vector3.new(ts.X * (1.05 + f * 0.5), drop / 3 + ts.Y * 0.04, ts.Z * 0.16),
			CFrame.new(0, ts.Y * 0.34 - drop * (f / 3 + 1 / 6) - ts.Y * 0.06, ts.Z * (0.6 + f * 0.06))
				* CFrame.Angles(math.rad(3 + f * 4), 0, 0),
			i == 1 and color or color:Lerp(trimColor, f * 0.22))
	end
	-- a hem, so the cape ends in an edge instead of stopping dead
	P(ctx, t, "StageCloakHem", Vector3.new(ts.X * 1.6, ts.Y * 0.14, ts.Z * 0.22),
		CFrame.new(0, ts.Y * 0.28 - drop, ts.Z * 0.72), trimColor, { mat = Enum.Material.Neon, tr = 0.2 })
end

-- ===== WHAT SEPARATES ONE CHARACTER FROM ANOTHER =============================
-- Every stage has ten characters, and until now the ONLY thing that told them apart was
-- `entry.color` -- BUILD[stageIndex] draws the same body for all ten. So picking a different one
-- in the Journal re-tinted the player and did nothing else, and where two of a stage's colours sit
-- close together (Amber Blob 248,226,128 against Prime Seed 255,226,130 against Golden Ovum
-- 255,214,140) the swap was invisible. "It doesn't change me" was an accurate report.
--
-- Authoring ten costumes for each of twenty stages is two hundred costumes. This is one pass
-- instead: it runs AFTER the stage's own builder and decorates whatever that made, out of the same
-- vocabulary every builder above already uses -- so it works on all twenty bodies with nothing
-- authored per stage and nothing per character.
--
-- Two things vary, and they vary from DIFFERENT inputs on purpose:
--   PATTERN comes from the character KEY, so it is fixed for that character forever (a skin that
--   reshuffles on respawn is not a skin) and two characters of the same rarity still differ.
--   FLOURISH comes from the RARITY, so it escalates. A Legendary has to be readable as a Legendary
--   from across the street, and no colour swap can carry that.
local function keyHash(key)
	local h = 7
	for i = 1, #key do
		h = (h * 31 + key:byte(i)) % 1048576
	end
	return h
end

local SKIN_PATTERNS = { "plain", "spots", "bands", "belly", "freckles", "back" }

-- A UNIFORM ball. Anything else would be silently drawn as a sphere of its smallest axis -- Roblox
-- discards a non-uniform Size on Shape = Ball without a word -- so a "flattened patch" has to be a
-- round ball sunk into the surface rather than a squashed one lying on it.
local function patch(ctx, host, size, offset, color)
	return P(ctx, host, "SkinPatch", Vector3.new(size, size, size), offset, color,
		{ shape = Enum.PartType.Ball })
end

local function skinMarks(ctx, entry)
	if not entry then return end
	local h = keyHash(entry.key)
	local pattern = SKIN_PATTERNS[(h % #SKIN_PATTERNS) + 1]
	-- Half the characters wear a LIGHTER mark and half a DARKER one. That single bit doubles the
	-- number of visibly different results without adding a seventh pattern, and it is what keeps a
	-- pale shell's spots from vanishing into it.
	local mark = (h % 2 == 0) and lighten(ctx.color, 0.55) or darken(ctx.color, 0.42)
	local t, ts = ctx.torso, ctx.torsoSize
	local hd, hs = ctx.head, ctx.headSize

	if pattern == "spots" then
		for _, s in ipairs({ { -0.30, 0.22 }, { 0.26, -0.02 }, { -0.10, -0.26 } }) do
			patch(ctx, t, ts.X * 0.34, CFrame.new(ts.X * s[1], ts.Y * s[2], ts.Z * 0.34), mark)
		end
		patch(ctx, hd, hs.X * 0.26, CFrame.new(hs.X * 0.28, hs.Y * 0.22, hs.Z * 0.40), mark)
	elseif pattern == "bands" then
		for i = 1, 3 do
			P(ctx, t, "SkinBand", Vector3.new(ts.X * 1.04, ts.Y * 0.09, ts.Z * 1.04),
				CFrame.new(0, ts.Y * (0.26 - (i - 1) * 0.24), 0), mark)
		end
	elseif pattern == "belly" then
		patch(ctx, t, ts.X * 0.78, CFrame.new(0, ts.Y * -0.04, ts.Z * 0.30), mark)
	elseif pattern == "freckles" then
		-- golden angle: six points on the face that are provably never close together
		for i = 1, 6 do
			local a = i * 2.399963
			patch(ctx, hd, hs.X * 0.13,
				CFrame.new(math.cos(a) * hs.X * 0.30, hs.Y * (0.10 + math.sin(a) * 0.22), hs.Z * 0.46), mark)
		end
	elseif pattern == "back" then
		backSpines(ctx, mark, 3, 0.34)
	end
	-- "plain" is a real result, not a gap. If every character carries a marking then carrying one
	-- stops meaning anything, and a clean shell is the right look for a Common.

	if entry.rarity == "Uncommon" then
		ring(ctx, t, "SkinRarityRing", ts.X * 1.12, ts.Y * 0.07, ts.Y * -0.30, mark, { mat = Enum.Material.Neon })
	elseif entry.rarity == "Rare" then
		orbitals(ctx, 2, ctx.glow, 0.16, 0.85, 7, Enum.PartType.Ball, Enum.Material.Neon, 0.22)
	elseif entry.rarity == "Epic" then
		orbitals(ctx, 3, ctx.glow, 0.19, 0.90, 6, Enum.PartType.Ball, Enum.Material.Neon, 0.22)
		emitter(t, ctx.glow, ts.X * 0.30, 6, 1.4, 1.1)
	elseif entry.rarity == "Legendary" then
		halo(ctx, ctx.glow, 1.5, 0.92, 9, math.rad(12))
		orbitals(ctx, 4, ctx.glow, 0.20, 0.95, 6, Enum.PartType.Ball, Enum.Material.Neon, 0.22)
		emitter(t, ctx.glow, ts.X * 0.38, 10, 1.8, 1.3)
	end
end

-- ===== THE TWENTY STAGES =====================================================
-- Read down the list and the arc is the point: the first five are animals and get bodies, the
-- middle five are built things and get hardware, and the last ten stop being bodies at all and
-- become haloes, orbits and light. Each one takes the stage's own colour, so the palette walks
-- with the player without a single colour being hand-written per stage.

local BUILD = {}

-- 1 CELL: a membrane you can see through with a nucleus floating in it. The one stage where the
-- costume is bigger than the body it is on -- you are the blob, not something wearing it.
BUILD[1] = function(ctx)
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageMembrane", Vector3.new(ts.X * 2.3, ts.Y * 2.1, ts.Z * 3.4), CFrame.new(0, ts.Y * 0.1, 0),
		lighten(ctx.glow, 0.35), { shape = Enum.PartType.Ball, tr = 0.62 })
	P(ctx, t, "StageNucleus", Vector3.new(ts.X * 0.7, ts.X * 0.7, ts.X * 0.7), CFrame.new(0, ts.Y * 0.05, -ts.Z * 0.2),
		ctx.glow, { shape = Enum.PartType.Ball, mat = Enum.Material.Neon, tr = 0.15 })
	orbit(ctx, 8, ts.X * 1.05, 0, function(i, a, off)
		P(ctx, t, "StageCilium", Vector3.new(ts.X * 0.07, ts.X * 0.07, ts.Z * 0.9),
			CFrame.new(0, ts.Y * 0.1, 0) * CFrame.Angles(0, -a, 0) * CFrame.new(ts.X * 1.15, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
			lighten(ctx.glow, 0.5), { mat = Enum.Material.Neon, tr = 0.3 })
	end)
end

-- 2 BACTERIA: the same idea grown a skin and a means of moving. Three flagella, and they whip.
BUILD[2] = function(ctx)
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageCapsule", Vector3.new(ts.X * 2, ts.Y * 1.9, ts.Z * 3.8), CFrame.new(0, ts.Y * 0.1, 0),
		lighten(ctx.color, 0.2), { shape = Enum.PartType.Ball, tr = 0.42 })
	for i = -1, 1 do
		local cf = CFrame.new(i * ts.X * 0.34, ts.Y * 0.1, ts.Z * 1.4)
		for s = 1, 4 do
			cf = cf * CFrame.Angles(0, math.rad(i * 13), 0) * CFrame.new(0, 0, ts.Z * 0.42)
			P(ctx, t, "StageFlagellum", Vector3.new(ts.X * 0.09, ts.X * 0.09, ts.Z * 0.44), cf,
				s % 2 == 0 and ctx.glow or lighten(ctx.color, 0.4), { mat = Enum.Material.Neon, tr = 0.2 })
		end
	end
	eyes(ctx, Color3.fromRGB(250, 250, 255), INK, 0.2, 0.24, 0.5)
end

-- 3 WORM: segments. Nothing else -- the read is entirely in the banding.
BUILD[3] = function(ctx)
	local t, ts = ctx.torso, ctx.torsoSize
	for i = 0, 4 do
		local f = i / 4
		ring(ctx, t, "StageSegment", ts.X * (1.9 - f * 0.35), ts.Y * 0.19, ts.Y * (0.42 - f * 0.36),
			i % 2 == 0 and ctx.color or lighten(ctx.color, 0.34), { shape = Enum.PartType.Cylinder })
	end
	local h, hs = ctx.head, ctx.headSize
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, h, "StageFeeler", Vector3.new(hs.X * 0.09, hs.Y * 0.5, hs.Z * 0.09),
			CFrame.new(side * hs.X * 0.2, hs.Y * 0.66, -hs.Z * 0.1) * CFrame.Angles(0, 0, side * math.rad(19)), ctx.color)
		P(ctx, h, "StageFeelerTip", Vector3.new(hs.X * 0.17, hs.X * 0.17, hs.X * 0.17),
			CFrame.new(side * hs.X * 0.29, hs.Y * 0.9, -hs.Z * 0.1), ctx.glow,
			{ shape = Enum.PartType.Ball, mat = Enum.Material.Neon })
	end
	eyes(ctx, Color3.fromRGB(250, 250, 255), INK, 0.19, 0.23, 0.48)
end

-- 4 LIZARD: the first stage with a back, a snout and a tail -- a real animal silhouette.
BUILD[4] = function(ctx)
	backSpines(ctx, lighten(ctx.color, 0.3), 5, 0.3)
	snout(ctx, ctx.color, darken(ctx.color, 0.5), 0.5)
	tail(ctx, ctx.color, lighten(ctx.color, 0.3), 4, 0.42, math.rad(9))
	local h, hs = ctx.head, ctx.headSize
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, h, "StageBrow", Vector3.new(hs.X * 0.26, hs.Y * 0.14, hs.Z * 0.5),
			CFrame.new(side * hs.X * 0.26, hs.Y * 0.32, -hs.Z * 0.28), darken(ctx.color, 0.25))
	end
	eyes(ctx, Color3.fromRGB(250, 226, 120), INK, 0.17, 0.27, 0.45)
end

-- 5 WOLF: ears, muzzle, ruff, brush tail. The most familiar shape in the whole list, so it has
-- to be the most correct one -- anything off reads as wrong rather than as stylised.
BUILD[5] = function(ctx)
	local fur, pale = ctx.color, lighten(ctx.color, 0.45)
	pointedEars(ctx, fur, lighten(Color3.fromRGB(255, 160, 190), 0.15), 0.55, math.rad(13))
	snout(ctx, fur, INK, 0.55)
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageRuff", Vector3.new(ts.X * 1.36, ts.Y * 0.5, ts.Z * 1.6), CFrame.new(0, ts.Y * 0.38, 0),
		pale, { shape = Enum.PartType.Ball })
	P(ctx, t, "StageChestFur", Vector3.new(ts.X * 0.5, ts.Y * 0.8, ts.Z * 0.24), CFrame.new(0, -ts.Y * 0.06, -ts.Z * 0.5), pale)
	tail(ctx, fur, pale, 3, 0.62, math.rad(13))
	eyes(ctx, Color3.fromRGB(250, 250, 255), Color3.fromRGB(240, 190, 60), 0.19, 0.26, 0.45)
end

-- 6 GORILLA: mass. Shoulders wider than the head, a chest slab, a heavy brow.
BUILD[6] = function(ctx)
	local fur, dark = ctx.color, darken(ctx.color, 0.42)
	local t, ts = ctx.torso, ctx.torsoSize
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, t, "StageShoulderFur", Vector3.new(ts.X * 0.8, ts.Y * 0.8, ts.Z * 1.5),
			CFrame.new(side * ts.X * 0.56, ts.Y * 0.3, 0), fur, { shape = Enum.PartType.Ball })
		local arm = side < 0 and ctx.armL or ctx.armR
		if arm then
			-- clears the arm shell (1.5x), not the bare avatar arm it used to be measured against
			P(ctx, arm, "StageArmFur", arm.Size * 1.85, CFrame.new(0, 0, 0), fur, { shape = Enum.PartType.Ball })
		end
	end
	P(ctx, t, "StageChestPlate", Vector3.new(ts.X * 0.86, ts.Y * 0.86, ts.Z * 0.26),
		CFrame.new(0, ts.Y * 0.02, -ts.Z * 0.52), lighten(ctx.color, 0.35))
	backSpines(ctx, dark, 3, 0.22)
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageBrow", Vector3.new(hs.X * 1.02, hs.Y * 0.2, hs.Z * 0.44),
		CFrame.new(0, hs.Y * 0.3, -hs.Z * 0.3), dark)
	P(ctx, h, "StageCrest", Vector3.new(hs.X * 0.16, hs.Y * 0.36, hs.Z * 0.9),
		CFrame.new(0, hs.Y * 0.62, 0), dark)
	snout(ctx, lighten(ctx.color, 0.2), INK, 0.36)
end

-- 7 HUMAN: the pivot of the whole list -- the last stage that is only a person. Explorer kit
-- rather than armour, so the jump to Cyborg lands.
BUILD[7] = function(ctx)
	local cloth = ctx.color
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageCap", Vector3.new(hs.X * 1.08, hs.Y * 0.34, hs.Z * 1.08), CFrame.new(0, hs.Y * 0.48, 0), cloth)
	P(ctx, h, "StageCapBrim", Vector3.new(hs.X * 1.1, hs.Y * 0.1, hs.Z * 0.7), CFrame.new(0, hs.Y * 0.34, -hs.Z * 0.72), darken(cloth, 0.3))
	P(ctx, h, "StageCapButton", Vector3.new(hs.X * 0.16, hs.X * 0.16, hs.X * 0.16), CFrame.new(0, hs.Y * 0.68, 0),
		lighten(cloth, 0.5), { shape = Enum.PartType.Ball })
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageScarf", Vector3.new(ts.X * 1.16, ts.Y * 0.26, ts.Z * 1.2), CFrame.new(0, ts.Y * 0.4, 0), lighten(cloth, 0.4))
	P(ctx, t, "StageScarfTail", Vector3.new(ts.X * 0.3, ts.Y * 0.8, ts.Z * 0.14),
		CFrame.new(-ts.X * 0.24, -ts.Y * 0.06, -ts.Z * 0.55) * CFrame.Angles(0, 0, math.rad(7)), lighten(cloth, 0.4))
	P(ctx, t, "StagePack", Vector3.new(ts.X * 0.9, ts.Y * 0.9, ts.Z * 0.6), CFrame.new(0, ts.Y * 0.04, ts.Z * 0.74),
		Color3.fromRGB(150, 106, 62))
	P(ctx, t, "StagePackFlap", Vector3.new(ts.X * 0.94, ts.Y * 0.34, ts.Z * 0.66), CFrame.new(0, ts.Y * 0.4, ts.Z * 0.76),
		Color3.fromRGB(104, 72, 42))
	P(ctx, t, "StagePackRoll", Vector3.new(ts.X * 0.92, ts.Z * 0.34, ts.Z * 0.34),
		CFrame.new(0, ts.Y * 0.56, ts.Z * 0.78) * CFrame.Angles(0, 0, math.rad(90)), lighten(cloth, 0.25),
		{ shape = Enum.PartType.Cylinder })
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, t, "StageStrap", Vector3.new(ts.X * 0.17, ts.Y * 1, ts.Z * 0.1),
			CFrame.new(side * ts.X * 0.3, 0, -ts.Z * 0.52), Color3.fromRGB(104, 72, 42))
	end
end

-- 8 CYBORG: the first stage that is *built*. Hard edges, a lit core, and one asymmetric piece --
-- the arm cannon -- because perfect symmetry reads as clothing and asymmetry reads as machinery.
BUILD[8] = function(ctx)
	local steel, glow = Color3.fromRGB(150, 158, 172), ctx.glow
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageVisor", Vector3.new(hs.X * 1.04, hs.Y * 0.3, hs.Z * 0.24), CFrame.new(0, hs.Y * 0.14, -hs.Z * 0.46), INK)
	P(ctx, h, "StageVisorLens", Vector3.new(hs.X * 0.88, hs.Y * 0.14, hs.Z * 0.14), CFrame.new(0, hs.Y * 0.14, -hs.Z * 0.56),
		glow, { mat = Enum.Material.Neon })
	P(ctx, h, "StageSkullPlate", Vector3.new(hs.X * 1.04, hs.Y * 0.4, hs.Z * 0.86), CFrame.new(0, hs.Y * 0.44, hs.Z * 0.08), steel,
		{ mat = Enum.Material.Metal })
	P(ctx, h, "StageAntenna", Vector3.new(hs.X * 0.08, hs.Y * 0.6, hs.Z * 0.08), CFrame.new(hs.X * 0.4, hs.Y * 0.9, 0), steel,
		{ mat = Enum.Material.Metal })
	pauldrons(ctx, steel, glow, 0.46, Enum.Material.Metal)
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageCoreHousing", Vector3.new(ts.X * 0.62, ts.Y * 0.62, ts.Z * 0.3), CFrame.new(0, ts.Y * 0.06, -ts.Z * 0.5), steel,
		{ mat = Enum.Material.Metal })
	P(ctx, t, "StageCore", Vector3.new(ts.X * 0.36, ts.X * 0.36, ts.X * 0.36), CFrame.new(0, ts.Y * 0.06, -ts.Z * 0.62), glow,
		{ shape = Enum.PartType.Ball, mat = Enum.Material.Neon })
	for i = -1, 1, 2 do
		P(ctx, t, "StageCircuit", Vector3.new(ts.X * 0.07, ts.Y * 0.9, ts.Z * 0.06), CFrame.new(i * ts.X * 0.42, -ts.Y * 0.1, -ts.Z * 0.52),
			glow, { mat = Enum.Material.Neon, tr = 0.15 })
	end
	if ctx.armL then
		P(ctx, ctx.armL, "StageCannon", ctx.armLSize * Vector3.new(1.5, 0.9, 1.5), CFrame.new(0, -ctx.armLSize.Y * 0.2, 0), steel,
			{ mat = Enum.Material.Metal })
		P(ctx, ctx.armL, "StageCannonMuzzle", ctx.armLSize * Vector3.new(1.1, 0.24, 1.1),
			CFrame.new(0, -ctx.armLSize.Y * 0.66, 0), glow, { mat = Enum.Material.Neon })
	end
end

-- 9 ALIEN: cranium and eyes. The head stops being a head.
BUILD[9] = function(ctx)
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageCranium", Vector3.new(hs.X * 1.5, hs.Y * 1.5, hs.Z * 1.6), CFrame.new(0, hs.Y * 0.42, hs.Z * 0.06),
		lighten(ctx.color, 0.28), { shape = Enum.PartType.Ball })
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, h, "StageAlienEye", Vector3.new(hs.X * 0.44, hs.Y * 0.62, hs.Z * 0.3),
			CFrame.new(side * hs.X * 0.3, hs.Y * 0.16, -hs.Z * 0.46) * CFrame.Angles(0, 0, side * math.rad(-16)), INK,
			{ shape = Enum.PartType.Ball })
		P(ctx, h, "StageAlienGlint", Vector3.new(hs.X * 0.12, hs.Y * 0.16, hs.Z * 0.1),
			CFrame.new(side * hs.X * 0.38, hs.Y * 0.3, -hs.Z * 0.56), Color3.fromRGB(255, 255, 255), { shape = Enum.PartType.Ball })
		P(ctx, h, "StageAntenna", Vector3.new(hs.X * 0.08, hs.Y * 0.66, hs.Z * 0.08),
			CFrame.new(side * hs.X * 0.28, hs.Y * 1.16, 0) * CFrame.Angles(0, 0, side * math.rad(17)), lighten(ctx.color, 0.28))
		P(ctx, h, "StageAntennaBulb", Vector3.new(hs.X * 0.2, hs.X * 0.2, hs.X * 0.2),
			CFrame.new(side * hs.X * 0.42, hs.Y * 1.48, 0), ctx.glow, { shape = Enum.PartType.Ball, mat = Enum.Material.Neon })
	end
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageSuit", Vector3.new(ts.X * 1.08, ts.Y * 1.06, ts.Z * 1.1), CFrame.new(0, 0, 0), ctx.color, { tr = 0.25 })
	ring(ctx, t, "StageSuitRing", ts.X * 1.2, ts.Y * 0.12, ts.Y * 0.3, ctx.glow,
		{ shape = Enum.PartType.Cylinder, mat = Enum.Material.Neon })
end

-- 10 COSMIC BEING: the first stage that leaves the body behind. A halo, and things in orbit.
BUILD[10] = function(ctx)
	halo(ctx, ctx.glow, 1.6, 1.7, 9)
	orbitals(ctx, 3, ctx.glow, 0.3, 1.5, 7)
	cloak(ctx, darken(ctx.color, 0.3), ctx.glow, 1.4)
	local t, ts = ctx.torso, ctx.torsoSize
	local star = P(ctx, t, "StageStar", Vector3.new(ts.X * 0.44, ts.X * 0.44, ts.X * 0.44),
		CFrame.new(0, ts.Y * 0.1, -ts.Z * 0.6) * CFrame.Angles(0, 0, math.rad(45)), ctx.glow, { mat = Enum.Material.Neon })
	if star then emitter(star, ctx.glow, ts.X * 0.2, 8, ts.X * 0.7, 1.6) end
end

-- 11 UNIVERSE GOD: two haloes turning against each other and planets in orbit. The first crown.
BUILD[11] = function(ctx)
	crown(ctx, ctx.glow, 5, 0.5)
	halo(ctx, ctx.glow, 1.8, 1.7, 11)
	orbitals(ctx, 4, lighten(ctx.color, 0.3), 0.36, 1.7, 12, Enum.PartType.Ball, Enum.Material.Neon)
	cloak(ctx, ctx.color, ctx.glow, 1.6)
end

-- 12 STAR WEAVER: a constellation carried on the back, and threads of light off the shoulders.
BUILD[12] = function(ctx)
	local t, ts = ctx.torso, ctx.torsoSize
	for i, node in ipairs({ { -0.5, 0.5 }, { 0.4, 0.65 }, { 0.7, 0 }, { -0.2, -0.15 }, { -0.75, -0.5 }, { 0.35, -0.6 } }) do
		P(ctx, t, "StageNode", Vector3.new(ts.X * 0.16, ts.X * 0.16, ts.X * 0.16),
			CFrame.new(node[1] * ts.X * 1.2, node[2] * ts.Y, ts.Z * 0.76), ctx.glow,
			{ shape = Enum.PartType.Ball, mat = Enum.Material.Neon })
		if i > 1 then
			local prev = ({ { -0.5, 0.5 }, { 0.4, 0.65 }, { 0.7, 0 }, { -0.2, -0.15 }, { -0.75, -0.5 } })[i - 1]
			local a = Vector3.new(prev[1] * ts.X * 1.2, prev[2] * ts.Y, ts.Z * 0.76)
			local b = Vector3.new(node[1] * ts.X * 1.2, node[2] * ts.Y, ts.Z * 0.76)
			P(ctx, t, "StageThread", Vector3.new(ts.X * 0.04, ts.X * 0.04, (b - a).Magnitude),
				CFrame.lookAt((a + b) / 2, b), lighten(ctx.glow, 0.4), { mat = Enum.Material.Neon, tr = 0.35 })
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, t, "StageShoulderStar", Vector3.new(ts.X * 0.34, ts.X * 0.34, ts.X * 0.34),
			CFrame.new(side * ts.X * 0.62, ts.Y * 0.4, 0) * CFrame.Angles(0, 0, math.rad(45)), ctx.glow, { mat = Enum.Material.Neon })
	end
	halo(ctx, ctx.glow, 1.5, 1.7, 13)
	orbitals(ctx, 5, lighten(ctx.glow, 0.35), 0.2, 1.9, 16)
end

-- 13 TIME WALKER: a clock worn on the chest, gears on the shoulders, and the hands actually turn --
-- clockwise, at a true 12:1, one minute-hand revolution every 8 seconds. [decision 2026-08-13]
--
-- NOTHING ON THIS COSTUME USED TO MOVE, and every piece of it looked like it should. Both hands were
-- `spin = { 0, 0, math.pi * 2, n }`, i.e. a tween whose goal is the identity; and a gear asked for
-- the other direction with a NEGATIVE DURATION, which is `beadRing`'s convention arriving at a
-- consumer that never implemented it. See `startTurn` for both.
--
-- The gear DISC is not what turns now. A smooth cylinder is a solid of revolution: spinning one
-- about its own axis is bit-for-bit the same picture at every angle, so that tween was invisible
-- even in the frames where it worked. The six teeth are what read as rotation, and they were the
-- one part of the gear standing still -- so the disc is now static and the teeth go round it.
BUILD[13] = function(ctx)
	local brass, face = Color3.fromRGB(206, 168, 88), Color3.fromRGB(244, 236, 214)
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageDialRim", Vector3.new(ts.Z * 0.2, ts.X * 1.02, ts.X * 1.02), CFrame.new(0, ts.Y * 0.04, -ts.Z * 0.5) * FACE,
		brass, { shape = Enum.PartType.Cylinder, mat = Enum.Material.Metal })
	P(ctx, t, "StageDial", Vector3.new(ts.Z * 0.12, ts.X * 0.86, ts.X * 0.86), CFrame.new(0, ts.Y * 0.04, -ts.Z * 0.58) * FACE,
		face, { shape = Enum.PartType.Cylinder })
	for i = 1, 12 do
		local a = i * math.pi / 6
		P(ctx, t, "StageHourMark", Vector3.new(ts.X * 0.05, ts.X * (i % 3 == 0 and 0.14 or 0.08), ts.Z * 0.06),
			CFrame.new(0, ts.Y * 0.04, -ts.Z * 0.62) * CFrame.Angles(0, 0, -a) * CFrame.new(0, ts.X * 0.35, 0), brass)
	end
	-- The dial's own axis, and the sign of "clockwise". The chest faces the torso's -Z, so a viewer
	-- standing in front of a player is looking down +Z with the torso's +X on their LEFT -- and a
	-- POSITIVE rotation about +Z carries the tip from 12 towards where they see 3. Clockwise is
	-- therefore the positive direction here, which is the opposite of what it would be on a piece
	-- worn on the back.
	local axis = Vector3.new(0, 0, 1)
	local hourPivot = CFrame.new(0, ts.Y * 0.04, -ts.Z * 0.64)
	local minutePivot = CFrame.new(0, ts.Y * 0.04, -ts.Z * 0.66)
	P(ctx, t, "StageHourHand", Vector3.new(ts.X * 0.07, ts.X * 0.5, ts.Z * 0.06),
		hourPivot * CFrame.new(0, ts.X * 0.2, 0), INK,
		{ turn = { pivot = hourPivot, axis = axis, seconds = 96 } })
	P(ctx, t, "StageMinuteHand", Vector3.new(ts.X * 0.05, ts.X * 0.72, ts.Z * 0.06),
		minutePivot * CFrame.new(0, ts.X * 0.3, 0), ctx.glow,
		{ mat = Enum.Material.Neon, turn = { pivot = minutePivot, axis = axis, seconds = 8 } })
	for _, side in ipairs({ -1, 1 }) do
		local hub = CFrame.new(side * ts.X * 0.66, ts.Y * 0.34, 0)
		P(ctx, t, "StageGear", Vector3.new(ts.Z * 0.24, ts.X * 0.6, ts.X * 0.6), hub * FACE, brass,
			{ shape = Enum.PartType.Cylinder, mat = Enum.Material.Metal })
		for g = 1, 6 do
			local a = g * math.pi / 3
			-- Six teeth are a six-fold arrangement, so one tween of one tooth-gap loops seamlessly
			-- and no chain is needed; `seconds` is still the period of a WHOLE turn, and its sign is
			-- what makes the two gears counter-rotate the way a real pair has to.
			P(ctx, t, "StageGearTooth", Vector3.new(ts.Z * 0.2, ts.X * 0.14, ts.X * 0.14),
				hub * CFrame.Angles(0, 0, a) * CFrame.new(0, ts.X * 0.32, 0), brass,
				{ mat = Enum.Material.Metal, turn = { pivot = hub, axis = axis, seconds = side * 5, symmetry = 6 } })
		end
	end
	cloak(ctx, darken(ctx.color, 0.2), brass, 1.5)
end

-- 14 VOID SOVEREIGN: subtraction. A hood, a heavy cloak, and a crown whose only light is its edge.
BUILD[14] = function(ctx)
	local void, edge = Color3.fromRGB(28, 22, 42), ctx.glow
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageHood", Vector3.new(hs.X * 1.3, hs.Y * 1.25, hs.Z * 1.35), CFrame.new(0, hs.Y * 0.3, hs.Z * 0.12), void,
		{ shape = Enum.PartType.Ball })
	P(ctx, h, "StageHoodShade", Vector3.new(hs.X * 0.9, hs.Y * 0.6, hs.Z * 0.2), CFrame.new(0, hs.Y * 0.06, -hs.Z * 0.5), INK)
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, h, "StageVoidEye", Vector3.new(hs.X * 0.16, hs.Y * 0.1, hs.Z * 0.08),
			CFrame.new(side * hs.X * 0.22, hs.Y * 0.08, -hs.Z * 0.58), edge, { mat = Enum.Material.Neon })
	end
	crown(ctx, edge, 3, 0.62)
	cloak(ctx, void, edge, 1.9)
	orbitals(ctx, 4, void, 0.26, 1.5, 14, Enum.PartType.Ball, Enum.Material.SmoothPlastic)
	local t, ts = ctx.torso, ctx.torsoSize
	local core = P(ctx, t, "StageVoidCore", Vector3.new(ts.X * 0.5, ts.X * 0.5, ts.X * 0.5),
		CFrame.new(0, ts.Y * 0.04, -ts.Z * 0.56), INK, { shape = Enum.PartType.Ball })
	if core then emitter(core, edge, ts.X * 0.22, 10, ts.X * 0.5, 1.8) end
end

-- 15 REALITY ARCHITECT: blueprint and building blocks. Cubes, not orbs -- this one makes things.
BUILD[15] = function(ctx)
	local t, ts = ctx.torso, ctx.torsoSize
	orbitals(ctx, 4, ctx.glow, 0.32, 1.6, 10, Enum.PartType.Block, Enum.Material.Neon, 0.35)
	orbitals(ctx, 3, lighten(ctx.color, 0.4), 0.22, 1.15, -14, Enum.PartType.Block, Enum.Material.Neon, -0.25)
	P(ctx, t, "StageBlueprint", Vector3.new(ts.X * 1.24, ts.Y * 1.1, ts.Z * 0.12), CFrame.new(0, ts.Y * 0.06, ts.Z * 0.66),
		darken(ctx.color, 0.45), { tr = 0.2 })
	for i = -1, 1 do
		P(ctx, t, "StageGridLine", Vector3.new(ts.X * 1.26, ts.Y * 0.04, ts.Z * 0.06), CFrame.new(0, ts.Y * (0.06 + i * 0.3), ts.Z * 0.72),
			ctx.glow, { mat = Enum.Material.Neon, tr = 0.3 })
		P(ctx, t, "StageGridLine", Vector3.new(ts.X * 0.04, ts.Y * 1.1, ts.Z * 0.06), CFrame.new(i * ts.X * 0.38, ts.Y * 0.06, ts.Z * 0.72),
			ctx.glow, { mat = Enum.Material.Neon, tr = 0.3 })
	end
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageVisor", Vector3.new(hs.X * 1.06, hs.Y * 0.26, hs.Z * 0.16), CFrame.new(0, hs.Y * 0.16, -hs.Z * 0.52), ctx.glow,
		{ mat = Enum.Material.Neon, tr = 0.2 })
	for _, side in ipairs({ -1, 1 }) do
		P(ctx, t, "StageBracket", Vector3.new(ts.X * 0.1, ts.Y * 0.5, ts.Z * 0.1),
			CFrame.new(side * ts.X * 0.66, ts.Y * 0.36, -ts.Z * 0.5), ctx.glow, { mat = Enum.Material.Neon })
		P(ctx, t, "StageBracket", Vector3.new(ts.X * 0.36, ts.Y * 0.1, ts.Z * 0.1),
			CFrame.new(side * ts.X * 0.54, ts.Y * 0.58, -ts.Z * 0.5), ctx.glow, { mat = Enum.Material.Neon })
	end
end

-- 16 DIMENSIONAL TITAN: armour, at the scale the name promises. Everything oversized on purpose.
BUILD[16] = function(ctx)
	local plate, edge = darken(ctx.color, 0.28), ctx.glow
	pauldrons(ctx, plate, edge, 0.78, Enum.Material.Metal)
	local t, ts = ctx.torso, ctx.torsoSize
	P(ctx, t, "StageBreastplate", Vector3.new(ts.X * 1.12, ts.Y * 1.02, ts.Z * 0.32), CFrame.new(0, ts.Y * 0.04, -ts.Z * 0.5), plate,
		{ mat = Enum.Material.Metal })
	P(ctx, t, "StageBeltBuckle", Vector3.new(ts.X * 0.42, ts.Y * 0.3, ts.Z * 0.2), CFrame.new(0, -ts.Y * 0.48, -ts.Z * 0.55), edge,
		{ mat = Enum.Material.Neon })
	ring(ctx, t, "StageBelt", ts.X * 1.2, ts.Y * 0.2, -ts.Y * 0.48, plate, { shape = Enum.PartType.Cylinder, mat = Enum.Material.Metal })
	for i = -1, 1, 2 do
		P(ctx, t, "StageBackPlate", Vector3.new(ts.X * 0.4, ts.Y * 1.2, ts.Z * 0.24),
			CFrame.new(i * ts.X * 0.34, ts.Y * 0.1, ts.Z * 0.62) * CFrame.Angles(0, i * math.rad(9), 0), plate, { mat = Enum.Material.Metal })
	end
	orbitals(ctx, 3, edge, 0.42, 1.9, 9, Enum.PartType.Wedge)
	local h, hs = ctx.head, ctx.headSize
	P(ctx, h, "StageFaceguard", Vector3.new(hs.X * 1.04, hs.Y * 0.56, hs.Z * 0.24), CFrame.new(0, -hs.Y * 0.06, -hs.Z * 0.48), plate,
		{ mat = Enum.Material.Metal })
	P(ctx, h, "StageFaceguardSlit", Vector3.new(hs.X * 0.8, hs.Y * 0.1, hs.Z * 0.1), CFrame.new(0, hs.Y * 0.06, -hs.Z * 0.58), edge,
		{ mat = Enum.Material.Neon })
end

-- 17 CHRONOS BEING: three rings turning at three speeds, and an hourglass where a chest was.
--
-- The rings had the SAME PAIR OF DEFECTS as stage 13's clock and were written a hundred lines apart
-- from it: the middle ring asked to turn the other way with a negative DURATION, and all three were
-- spun about their own axis -- which for a smooth cylinder is no picture change at all. So the row's
-- one promise, "three rings turning at three speeds", was the one thing it did not do.
--
-- A ring can only be SEEN to turn about an axis that is not its own, so each one now precesses about
-- the torso's vertical while tilted out of that plane -- a gyroscope, which is also what the name
-- wants. That requires the first ring to gain a tilt (it lay perfectly flat, and a flat ring
-- precessing about the vertical is again the same picture forever); 16 degrees is enough to read and
-- small enough that the stack still stands as three level bands from the front.
BUILD[17] = function(ctx)
	local t, ts = ctx.torso, ctx.torsoSize
	-- { diameter, y, seconds (sign = direction), tilt }
	for i, spec in ipairs({ { 2.5, 0.4, 14, math.rad(16) }, { 2.0, 0.1, -10, math.rad(38) }, { 1.5, -0.2, 8, math.rad(-30) } }) do
		-- the pivot carries the height but NOT the tilt: the tilt has to sit inside the piece's own
		-- offset, or the axis it precesses about would tilt with it and we are back to a ring
		-- turning about itself.
		local pivot = CFrame.new(0, ts.Y * spec[2], 0)
		P(ctx, t, "StageChronoRing", Vector3.new(ts.X * 0.08, ts.X * spec[1], ts.X * spec[1]),
			pivot * CFrame.Angles(spec[4], 0, 0) * FLAT,
			i == 2 and lighten(ctx.glow, 0.4) or ctx.glow,
			{ shape = Enum.PartType.Cylinder, mat = Enum.Material.Neon, tr = 0.28,
				turn = { pivot = pivot, axis = Vector3.new(0, 1, 0), seconds = spec[3] } })
	end
	for _, dy in ipairs({ 0.26, -0.26 }) do
		P(ctx, t, "StageHourglass", Vector3.new(ts.X * 0.5, ts.Y * 0.3, ts.Z * 0.5),
			CFrame.new(0, ts.Y * dy, -ts.Z * 0.5) * CFrame.Angles(dy > 0 and 0 or math.pi, 0, 0), lighten(ctx.color, 0.3),
			{ shape = Enum.PartType.Wedge, tr = 0.25 })
	end
	local sand = P(ctx, t, "StageSand", Vector3.new(ts.X * 0.16, ts.Y * 0.5, ts.Z * 0.16), CFrame.new(0, 0, -ts.Z * 0.5), ctx.glow,
		{ mat = Enum.Material.Neon })
	if sand then emitter(sand, ctx.glow, ts.X * 0.14, 12, ts.X * 0.3, 1.4) end
	halo(ctx, ctx.glow, 1.7, 1.7, 20)
	crown(ctx, lighten(ctx.glow, 0.3), 5, 0.36)
end

-- 18 OMNISCIENT ENTITY: eyes, all the way round. Nothing else is needed and nothing else would land.
BUILD[18] = function(ctx)
	local h, hs = ctx.head, ctx.headSize
	local white = Color3.fromRGB(250, 248, 255)
	orbit(ctx, 6, hs.X * 1.15, 0, function(i, a, off)
		local at = CFrame.new(0, hs.Y * 0.78, 0) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -hs.X * 1.15)
		P(ctx, h, "StageEyeball", Vector3.new(hs.X * 0.34, hs.X * 0.34, hs.X * 0.34), at, white, { shape = Enum.PartType.Ball })
		P(ctx, h, "StageEyeIris", Vector3.new(hs.X * 0.19, hs.X * 0.19, hs.X * 0.14), at * CFrame.new(0, 0, -hs.X * 0.12), ctx.glow,
			{ shape = Enum.PartType.Ball, mat = Enum.Material.Neon })
		P(ctx, h, "StageEyePupil", Vector3.new(hs.X * 0.1, hs.X * 0.1, hs.X * 0.08), at * CFrame.new(0, 0, -hs.X * 0.18), INK,
			{ shape = Enum.PartType.Ball })
	end)
	halo(ctx, ctx.glow, 1.9, 1.8, 24)
	cloak(ctx, darken(ctx.color, 0.3), ctx.glow, 1.7)
end

-- 19 PRIMORDIAL FORCE: the elements themselves, orbiting a body that is cracking open.
BUILD[19] = function(ctx)
	local t, ts = ctx.torso, ctx.torsoSize
	local elements = {
		Color3.fromRGB(255, 122, 48), Color3.fromRGB(96, 178, 255), Color3.fromRGB(140, 240, 150),
		Color3.fromRGB(200, 180, 160), Color3.fromRGB(255, 226, 110),
	}
	local step = math.pi * 2 / #elements
	for i, col in ipairs(elements) do
		local a = (i - 1) * step
		local off = CFrame.new(0, ts.Y * 0.1, 0) * CFrame.Angles(0, a, 0) * CFrame.new(ts.X * 1.7, 0, 0)
		local chunk = P(ctx, t, "StageElement", Vector3.new(ts.X * 0.4, ts.X * 0.34, ts.X * 0.44), off, col,
			{ mat = Enum.Material.Neon, tr = 0.1 })
		if chunk then
			local weld = chunk:FindFirstChild("CostumeWeld")
			local tween = TweenService:Create(weld, TweenInfo.new(11, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				C0 = CFrame.new(0, ts.Y * 0.1, 0) * CFrame.Angles(0, a + step, 0) * CFrame.new(ts.X * 1.7, 0, 0),
			})
			tween:Play()
			register(ctx, tween)
			if i == 1 then emitter(chunk, col, ts.X * 0.18, 14, ts.X * 0.5, 1.3) end
		end
	end
	for i, crack in ipairs({ { -0.3, 0.3, 22 }, { 0.25, 0, -30 }, { -0.1, -0.35, 14 } }) do
		P(ctx, t, "StageMagmaCrack", Vector3.new(ts.X * 0.1, ts.Y * 0.6, ts.Z * 0.08),
			CFrame.new(crack[1] * ts.X, crack[2] * ts.Y, -ts.Z * 0.52) * CFrame.Angles(0, 0, math.rad(crack[3])),
			Color3.fromRGB(255, 140, 60), { mat = Enum.Material.Neon })
	end
	local h, hs = ctx.head, ctx.headSize
	for i = -1, 1 do
		P(ctx, h, "StageFlameCrest", Vector3.new(hs.X * 0.14, hs.Y * (0.7 - math.abs(i) * 0.24), hs.Z * 0.2),
			CFrame.new(i * hs.X * 0.26, hs.Y * (0.8 - math.abs(i) * 0.12), 0) * CFrame.Angles(0, 0, math.rad(i * -16)),
			i == 0 and Color3.fromRGB(255, 226, 110) or Color3.fromRGB(255, 130, 54), { mat = Enum.Material.Neon, tr = 0.15 })
	end
	wings(ctx, "energy", Color3.fromRGB(255, 150, 70), Color3.fromRGB(255, 226, 130), 1)
end

-- 20 THE ABSOLUTE: everything, in gold. This is the end of the game and it is allowed to be loud.
BUILD[20] = function(ctx)
	local gold, pale = Color3.fromRGB(255, 205, 60), Color3.fromRGB(255, 248, 214)
	-- Four features, not eight. The first pass stacked wings, a halo, a second halo, a crown, a
	-- mask, pauldrons, six orbitals and a lit core, all in the same yellow, and the result was a
	-- cloud of rectangles with no silhouette at all. A costume reads by its outline, and an outline
	-- needs empty space between the shapes making it.
	wings(ctx, "feather", gold, pale, 0.95)
	cloak(ctx, pale, gold, 1.35)
	crown(ctx, gold, 5, 0.45)
	halo(ctx, gold, 1.7, 1.75, 16)
	local t, ts = ctx.torso, ctx.torsoSize
	local core = P(ctx, t, "StageAbsoluteCore", Vector3.new(ts.X * 0.44, ts.X * 0.44, ts.X * 0.44),
		CFrame.new(0, ts.Y * 0.06, -ts.Z * 0.58), pale, { shape = Enum.PartType.Ball, mat = Enum.Material.Neon })
	if core then emitter(core, gold, ts.X * 0.2, 10, ts.X * 0.6, 1.8) end
end

-- ===== PUBLIC API ============================================================

-- Hair and hats belong to the avatar, not to the creature. A Cell with a fringe or a Void
-- Sovereign wearing a baseball cap under its hood undoes the whole costume, so everything on the
-- head is hidden for every stage except Human -- which is the one stage that IS a person, and
-- where the player's own avatar is the point.
--
-- Hidden, never destroyed: these are the player's real accessories, and a costume has no business
-- deleting them. Clear() puts them straight back.
local function setAccessoriesHidden(character, hidden)
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			local kind = acc.AccessoryType
			if kind == Enum.AccessoryType.Hair or kind == Enum.AccessoryType.Hat or kind == Enum.AccessoryType.Unknown then
				for _, d in ipairs(acc:GetDescendants()) do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = hidden and 1 or 0
						d.Transparency = hidden and 1 or (d:GetAttribute(BASE_TRANSPARENCY) or 0)
						if hidden and d:GetAttribute(BASE_TRANSPARENCY) == nil then
							d:SetAttribute(BASE_TRANSPARENCY, 0)
						end
						if not hidden then d:SetAttribute(BASE_TRANSPARENCY, nil) end
					end
				end
			end
		end
	end
end

function StageCostume.Clear(character)
	if not character then return end
	-- BEFORE the folder goes, not after: once the weld is destroyed the tween is still running and
	-- still holding it, and there is nothing left to look it up from
	cancelSpins(character)
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then existing:Destroy() end
	-- a generated skin is the other half of the same wardrobe; leaving one behind would show two
	-- creatures welded to the same body
	SkinMesh.Clear(character)
	setAccessoriesHidden(character, false)
	-- the avatar comes back before anything else touches it. Clear runs at the top of every Apply,
	-- so a stage that fails to build leaves a visible player rather than an invisible one.
	setBodyHidden(character, false)
end

-- Builds the costume for `stageIndex` onto `character`, replacing whatever was there.
-- `stage` is the GameConfig.Stages entry, passed in rather than required so this module stays
-- usable from the client too (the same costume has to exist on every machine).
-- `entry` is the GameConfig.StageCharacters row being worn, or nil for the stage's default look.
-- It is one of the stage's five, so it changes the COLOUR of the whole build and nothing else --
-- a Cinder Wolf and a Frost Wolf have the same ears, muzzle, ruff and tail.
--
-- EVERY BAIL-OUT BELOW SAYS SO. The whole skin path used to have a single `warn` in it, and the
-- failure it produces -- a stock R15 avatar, zero costume parts, zero errors in the console -- is
-- indistinguishable from the code never having run at all. That signature is written up in
-- `src/STATUS.md`, and it cost two sessions of looking in the wrong place. A silent `return` in a
-- visual path is not a cheap guard, it is a bug report that never gets filed.
function StageCostume.Apply(character, stageIndex, stage, entry)
	if not (character and character.Parent) then
		warn(("[StageCostume] no character to dress (stage %s) -- caller kept a reference to a body that has left the workspace")
			:format(tostring(stageIndex)))
		return
	end
	StageCostume.Clear(character)

	-- A GENERATED MODEL WINS, WHEN THERE IS ONE.
	--
	-- The bosses are the standard the characters are being held to, and the bosses are not built
	-- from primitives -- BossService.meshRig hangs a generated model off the rig, which is the whole
	-- reason they read as finished creatures while a thirty-part costume read as a stack of boxes.
	--
	-- Rollout is two hundred separate generations, so this cannot be a switch that is thrown once:
	-- a character with a mesh wears it, a character without one falls straight through to the twenty
	-- builders below and looks exactly as it did. The game is playable at every point in between.
	if entry and SkinMesh.Apply(character, entry.key) then
		return
	end

	local builder = BUILD[stageIndex]
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (builder and root) then
		warn(("[StageCostume] %s: builder=%s root=%s -- the player is left on a stock avatar")
			:format(tostring(character.Name), tostring(builder ~= nil), tostring(root ~= nil)))
		return
	end

	-- R15 first, R6 names as the fallback: a player on an R6 avatar still gets a costume, just
	-- hung off the two parts R6 actually has.
	local head = character:FindFirstChild("Head")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root
	local lower = character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso") or root
	if not head then
		warn(("[StageCostume] %s has no Head -- costume for stage %s abandoned")
			:format(tostring(character.Name), tostring(stageIndex)))
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local color = (entry and entry.color) or (stage and stage.color) or Color3.fromRGB(190, 190, 210)

	-- Stage 7 is Human: the one stage a player is supposed to look like a person, so it keeps its
	-- own avatar and gets details only. Every other stage replaces the body outright.
	local dressed = stageIndex ~= 7
	local spec = dressed and (BODY[stageIndex] or {}) or nil

	local armL = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
	local ctx = {
		character = character,
		folder = folder,
		root = root,
		head = head,
		torso = torso,
		lower = lower,
		armL = armL,
		armR = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm"),
		legL = character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg"),
		legR = character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("Right Leg"),
		color = color,
		glow = vivid(color),
	}

	-- The dimensions every builder and shared feature below sizes and places against. They are the
	-- OUTER dimensions of the dressed body, not the bare avatar's -- a visor placed at "half the
	-- head's depth" has to clear the head shell, or it is inside the skull. Undressed (Human) they
	-- are exactly the limb sizes, which is what the whole file assumed before the body existed.
	local headCube = math.max(head.Size.X, head.Size.Y, head.Size.Z) * ((spec and spec.headGrow) or HEAD_GROW)
	ctx.headSize = dressed and Vector3.new(headCube, headCube, headCube) or head.Size
	-- X and Z only. Vertical offsets are measured from the limb's own centre and must not move, or
	-- a chest plate at 0.4 of the torso's height climbs off the top of the shoulders.
	ctx.torsoSize = dressed and Vector3.new(torso.Size.X * TORSO_W, torso.Size.Y, torso.Size.Z * TORSO_D) or torso.Size
	ctx.lowerSize = dressed and Vector3.new(lower.Size.X * TORSO_W, lower.Size.Y, lower.Size.Z * TORSO_D) or lower.Size
	if armL then
		ctx.armLSize = dressed and Vector3.new(armL.Size.X * ARM_GROW, armL.Size.Y, armL.Size.Z * ARM_GROW) or armL.Size
	end

	-- parented before building: att() puts each piece straight into the folder, and a piece
	-- created into nil parent would be collected before its weld ever ran
	folder.Parent = character

	local ok, err = pcall(function()
		if dressed then
			dressBody(ctx, spec)
		end
		builder(ctx)
		-- A FACE, ALWAYS. Most stages place their own eyes -- with their own colours, spacing and
		-- pupils -- and those are better than any default. But several (Cell, and every stage whose
		-- character is carried by a mask, a visor or a cranium) never did, and on a bare avatar that
		-- was fine because the avatar had a face of its own. It does not any more: the head is a
		-- blank cube unless something puts eyes on it. Detected rather than declared, so a stage that
		-- grows its own eyes later stops getting these automatically.
		if dressed and not folder:FindFirstChild("StageEye") then
			eyes(ctx, Color3.fromRGB(250, 250, 255), INK, 0.17, 0.24, 0.5)
		end
		-- AFTER the builder, never before: this decorates the body that was just made, and several
		-- builders replace the very torso shell the marks hang on. Inside the same pcall, so a bad
		-- mark takes the costume down the same visible way a bad builder does instead of leaving a
		-- half-dressed player.
		skinMarks(ctx, entry)
	end)
	if not ok then
		warn(("[StageCostume] stage %d failed: %s"):format(stageIndex, tostring(err)))
		folder:Destroy()
		return
	end

	-- THE OUTLINE. This is the difference between a costume and a pile of coloured boxes, and it
	-- was the single biggest thing missing: the pets have worn this same dark rim since PetModel
	-- was written, which is exactly why a 12-part pet reads as drawn while a 30-part costume read
	-- as debris. One Highlight covers the character and everything welded to it.
	--
	-- Occluded rather than always-on-top, so a player behind a wall does not glow through it, and
	-- one per character -- Roblox draws roughly 31 Highlights at once and the pets need theirs.
	local outline = Instance.new("Highlight")
	outline.Name = "StageOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Adornee = character
	outline.Parent = folder

	-- and the avatar goes away underneath it. Last, so that a builder that threw above has already
	-- returned and left the player visible rather than invisible inside a costume that never built.
	setAccessoriesHidden(character, dressed)
	setBodyHidden(character, dressed)
end

return StageCostume
