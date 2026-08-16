-- VFXLibrary -- thin wrapper over ReplicatedStorage.VFX, the particle pack that used to sit
-- loose in Workspace (120 objects rendering in the middle of the map). The pack's assets are
-- all shaped the same way: an anchored Part with one Attachment ("Main") carrying a handful of
-- ParticleEmitters. Nothing here spawns those Parts -- it lifts the emitters off them and hangs
-- copies on whatever you point it at, so a boss gets an aura without gaining a stray part.
--
-- The pack ships everything at demo intensity (Fire-01 emits 125 particles/second, Tornado-01
-- runs seven emitters at once). Anything placed in the world goes through `rate` well under 1.

local RS = game:GetService("ReplicatedStorage")

local VFXLibrary = {}

local VFX = RS:WaitForChild("VFX")

-- ===== sequence maths ========================================================
-- NumberSequence/ColorSequence are immutable, so scaling or tinting one means rebuilding it.

local function scaleSequence(seq, factor)
	if factor == 1 then return seq end
	local keys = {}
	for i, kp in ipairs(seq.Keypoints) do
		keys[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * factor, kp.Envelope * factor)
	end
	return NumberSequence.new(keys)
end

local function scaleRange(range, factor)
	if factor == 1 then return range end
	return NumberRange.new(range.Min * factor, range.Max * factor)
end

-- Raises the FLOOR of a Transparency sequence without changing its shape: v becomes
-- `floor + v * (1 - floor)`, so a keypoint already at 1 (faded out) stays at exactly 1 and only the
-- opaque end of the curve moves. Envelopes shrink with the range they sit inside, which keeps
-- `value ± envelope` inside [0, 1] -- the engine rejects a keypoint that leaves it.
local function raiseTransparency(seq, floor)
	if not floor or floor <= 0 then return seq end
	local span = 1 - floor
	local keys = {}
	for i, kp in ipairs(seq.Keypoints) do
		keys[i] = NumberSequenceKeypoint.new(kp.Time, floor + kp.Value * span, kp.Envelope * span)
	end
	return NumberSequence.new(keys)
end

-- Flat tint. Deliberately destroys the source gradient: it is only used on the generic
-- white/grey effects (sparkles, charge, stars) that have to read as a zone's colour.
local function tintOf(color)
	return ColorSequence.new(color)
end

-- ===== A TINT CANNOT SURVIVE AN ADDITIVE MULTIPLY (17.1) ======================
--
-- A ParticleEmitter's drawn colour is `Color * Brightness`, and with `LightEmission = 1` that
-- product is added straight onto the scene instead of being lit by it. The pack is authored for a
-- dark demo scene and leans on both: measured in the live place, the Epic mutation aura came out of
-- `Auras/RNG-Aura-01` at **Brightness 5, LightEmission 1**, so its rgb(170, 90, 255) was drawn as
-- (850, 450, 1275) and every channel clipped -- a purple aura rendering as **pure white**, on a
-- world that is already white-bright. The whole ladder is affected and unevenly, which is why the
-- rungs never looked like different things: Stars-01 (Rare) ships at Brightness 10, the three
-- RNG-Auras at 5, Smoke-01 (Common) and Tornado-01 (Godly) at 1 or below. The three rungs in the
-- middle were white; the two ends were the colour they were asked for.
--
-- So the cap belongs HERE and not in the callers' tables: `opts.color` is the caller saying "this
-- effect must read as this colour", and every path that honours it has to make the colour
-- survivable. Photographed both ways on the same body from the same camera -- at 5/1.00 the aura is
-- a white smear the world is barely visible through, at 1/0.35 it is a purple swirl you can read
-- the village through.
--
-- 1.0 is the highest brightness that cannot clip a fully-saturated tint. It is a ceiling, never an
-- assignment: `Windspin3` is authored at 0.3 and stays there.
--
-- ===== AND LIGHT EMISSION IS NOT THE SAME LEVER (17.18) ======================
--
-- 17.1 capped LightEmission to 0.35 in the same breath, on the reasoning that it "keeps the glow
-- without washing the hue out". That was wrong, and it cost a second bug report a session later --
-- a long white-and-dark streak trailing the player the length of the street.
--
-- The two properties do different jobs and only ONE of them clips a tint:
--
--   * Brightness multiplies the colour. That is the whole of 17.1's finding and the cap above is
--     the whole of its fix.
--   * LightEmission decides how ADDITIVELY the sprite is blended. These pack textures are drawn on
--     a BLACK background and rely on being added onto the scene to make that background vanish.
--     Lower it and the black stops being free: it is composited as actual black.
--
-- So capping it turned every floor sprite in the mutation aura into an opaque dark quad. Measured
-- live on a max-stage body: four `MutationAura` emitters at sizes up to **24.7 studs** with a
-- minimum Transparency of **0.00**, i.e. a fully opaque slab several times the character's width
-- lying flat on the grass. Photographed from above it is a black diamond on green; from a low
-- camera the same flat quad projects edge-on as a long tapering streak across the frame, which is
-- what her screenshot is.
--
-- Verified by moving nothing but this one property on the live body: at LightEmission 1 with
-- Brightness still capped at 1, the black quad is gone from the capture entirely and the aura is
-- still red rather than white -- so the tint is safe without it and 17.1's result survives.
--
-- The ceiling is therefore only on Brightness. An effect's authored LightEmission is left alone,
-- because it is a property of how the TEXTURE was drawn and not a decision the tint gets to make.
--
-- ===== AND THERE IS A THIRD LEVER, WHICH IS THE ONE THAT DECIDES WHAT YOU CAN SEE THROUGH (17.19)
--
-- Twice now a white-out has been treated as a Brightness/LightEmission question, and twice the
-- answer has been "no". The property that decides how much of the world survives BEHIND a sprite is
-- neither of them -- it is the sprite's own alpha:
--
--     additive draw (LightEmission 1):  dst + src * (1 - Transparency)
--
-- so Transparency is the ONLY term that scales what a layer adds without touching what colour it
-- adds. Brightness changes the colour (and clips it); LightEmission changes whether the texture's
-- black background is drawn (and paints slabs when lowered); Transparency changes only the amount.
--
-- It matters because additive layers STACK. The mutation aura's red is rgb(255, 80, 80) = (1.0,
-- 0.31, 0.31) per layer at full alpha: one layer is red, two is (1.0, 0.63, 0.63) = pink, three is
-- (1.0, 0.94, 0.94) = white. The pack ships these emitters at a minimum Transparency of **0.00**,
-- and the aura hangs three or four of them on one attachment on a body the camera is standing
-- inside -- so the middle of the frame is four layers deep and the rim is one. That is exactly the
-- reported picture: a featureless white body with a red fringe around the outside.
--
-- `minTransparency` (Attach only) lifts the opaque end of the curve, halving what each layer adds
-- while leaving its hue, its motion and its density alone. It CANNOT reproduce 17.18's black slab:
-- an additive layer only ever adds, so drawing less of it moves the result toward the world behind
-- it, never toward black.
--
-- It is opt-in rather than a ceiling like the one above, because the thing that makes it necessary
-- is not the tint -- it is being WORN ON A BODY somebody has to be able to see. A waterfall or a
-- zone mist is allowed to be opaque; it is not standing in front of the player's own creature.
local TINT_MAX_BRIGHTNESS = 1

-- Takes a ParticleEmitter or a Beam -- both carry Color, Brightness and LightEmission, and both
-- clip a tint the same way.
local function applyTint(inst, color)
	inst.Color = tintOf(color)
	if inst.Brightness > TINT_MAX_BRIGHTNESS then
		inst.Brightness = TINT_MAX_BRIGHTNESS
	end
	-- LightEmission is deliberately not touched -- see the block above. It is what makes the pack's
	-- black sprite backgrounds disappear, so lowering it draws them.
end

-- ===== density ===============================================================
-- The pack's effects are authored at wildly different densities -- Smoke-01 runs one emitter at
-- 5 particles/second, Big-Crack-01 runs four totalling 530. A single `rate` multiplier therefore
-- means nothing on its own: x0.6 turns one into a wisp and the other into a wall. `targetRate`
-- asks for a combined particles/second for the whole effect instead and derives the multiplier
-- from the source, so "as dense as a boss aura should be" is one number across the whole pack.

local function totalRateOf(template, accept)
	local total = 0
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("ParticleEmitter") and (not accept or accept(d)) then
			total += d.Rate
		end
	end
	return total
end

-- Resolves opts.targetRate / opts.rate down to the one multiplier to apply. targetRate wins.
local function rateFactor(template, opts, accept)
	if opts.targetRate then
		local total = totalRateOf(template, accept)
		if total > 0 then
			return opts.targetRate / total
		end
	end
	return opts.rate or 1
end

-- ===== footprint =============================================================
-- The same argument as `targetRate`, one axis over. The pack's effects are authored at wildly
-- different SIZES too -- Fire-Aura-01's particles are 1.1 studs and Big/Tornado-01's are 19.6 --
-- so a shared `scale` makes one effect a speck and the next one a wall. `targetSize` asks for how
-- many studs the biggest particle should be and derives the multiplier from the source, so "as big
-- as a player aura should be" is one number across the whole pack.
--
-- Measured against the thing it has to be seen past: a mutation aura hung on a HumanoidRootPart at
-- the pack's authored size is a 10-stud sprite at the centre of a 16-stud-wide body, i.e. entirely
-- INSIDE an opaque torso. It rendered perfectly and was invisible.

local function maxSizeOf(template, accept)
	local m = 0
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("ParticleEmitter") and (not accept or accept(d)) then
			for _, kp in ipairs(d.Size.Keypoints) do
				if kp.Value > m then m = kp.Value end
			end
		end
	end
	return m
end

-- targetSize wins over scale, the same way targetRate wins over rate.
local function scaleFactor(template, opts, accept)
	if opts.targetSize then
		local m = maxSizeOf(template, accept)
		if m > 0 then
			return opts.targetSize / m
		end
	end
	return opts.scale or 1
end

-- ===== lookup ================================================================

-- "Anime/Fire-01" -> the template Part. Errors loudly on a typo: a silent nil here would
-- show up much later as a boss that mysteriously has no aura.
function VFXLibrary.Find(path)
	local node = VFX
	for _, part in ipairs(string.split(path, "/")) do
		node = node:FindFirstChild(part)
		if not node then
			error(("VFXLibrary: no effect at '%s' (missing '%s')"):format(path, part), 2)
		end
	end
	return node
end

function VFXLibrary.Exists(path)
	local node = VFX
	for _, part in ipairs(string.split(path, "/")) do
		node = node:FindFirstChild(part)
		if not node then return false end
	end
	return true
end

-- ===== attaching =============================================================

-- Copies every ParticleEmitter under `path` onto `target` inside one Attachment, so the whole
-- effect can later be found, disabled or destroyed as a unit.
--
-- opts:
--   name    string   Attachment name (default "VFX"). Also what Toggle/Clear look for.
--   offset  Vector3   local position on the target part (default centre)
--   scale   number    multiplies particle Size and Speed -- bosses are 10-32 studs, the pack
--                     is authored for a 5-stud R6 dummy, so this is usually well above 1
--   targetSize number  studs the LARGEST particle should measure; preferred over `scale` when the
--                      effect has to be sized against a body rather than against itself. Attach
--                      only -- `Place` keeps its own carrier and has never needed it.
--   targetRate number  combined particles/second for the whole effect; preferred over `rate`
--   rate    number    raw multiplier on Rate, for when the source density is already right
--   color   Color3    flat tint, see tintOf -- and note it also caps Brightness, see applyTint:
--                     asking for a colour is asking for it to be drawn
--   minTransparency number  floor under the emitter's Transparency curve, 0-1. Use it for anything
--                     hung on a body that has to stay visible through the effect -- see the third
--                     lever note above. Shape-preserving: a fade-out still reaches 1.
--   only    {string}  emitter names to keep (default: all)
--   skip    {string}  emitter names to drop
function VFXLibrary.Attach(target, path, opts)
	opts = opts or {}
	local template = VFXLibrary.Find(path)

	local att = Instance.new("Attachment")
	att.Name = opts.name or "VFX"
	if opts.offset then
		att.Position = opts.offset
	end

	local only, skip
	if opts.only then
		only = {}
		for _, n in ipairs(opts.only) do only[n] = true end
	end
	if opts.skip then
		skip = {}
		for _, n in ipairs(opts.skip) do skip[n] = true end
	end

	-- the filters decide which emitters survive, so density has to be measured over the same set
	local function accept(e)
		return not (only and not only[e.Name]) and not (skip and skip[e.Name])
	end

	local scale = scaleFactor(template, opts, accept)
	local rate = rateFactor(template, opts, accept)
	local count = 0

	for _, source in ipairs(template:GetDescendants()) do
		if source:IsA("ParticleEmitter") and accept(source) then
			local emitter = source:Clone()
			emitter.Size = scaleSequence(emitter.Size, scale)
			emitter.Speed = scaleRange(emitter.Speed, scale)
			emitter.Rate = emitter.Rate * rate
			if opts.minTransparency then
				emitter.Transparency = raiseTransparency(emitter.Transparency, opts.minTransparency)
			end
			if opts.color then
				applyTint(emitter, opts.color)
			end
			emitter.Parent = att
			count += 1
		end
	end

	if count == 0 then
		att:Destroy()
		return nil
	end

	att.Parent = target
	return att
end

-- Places a whole template Part in the world -- the only way to use the Beams pack, whose
-- effects span two attachments (Start/End) and would lose their beams if the emitters were
-- lifted off individually.
function VFXLibrary.Place(parent, path, cframe, opts)
	opts = opts or {}
	local clone = VFXLibrary.Find(path):Clone()
	clone.Name = opts.name or clone.Name

	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.Transparency = 1 -- the pack ships these at 0.75; the carrier itself is never the effect
		clone.CFrame = cframe
	elseif clone:IsA("Model") then
		clone:PivotTo(cframe)
	end

	local scale = opts.scale or 1
	local rate = rateFactor(clone, opts)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Size = scaleSequence(d.Size, scale)
			d.Speed = scaleRange(d.Speed, scale)
			d.Rate = d.Rate * rate
			if opts.color then
				applyTint(d, opts.color)
			end
		elseif d:IsA("Beam") and opts.color then
			-- A Beam carries Brightness too (checked on a fresh one: Brightness 1) and clips a
			-- tint the same way, so it takes the same ceiling.
			applyTint(d, opts.color)
		end
	end

	clone.Parent = parent
	return clone
end

-- ===== control ===============================================================

-- Flips every emitter under an instance. Used by the decor proximity gate: 20 zones of
-- ambient particles are only worth simulating in the one zone somebody is standing in.
function VFXLibrary.SetEnabled(root, enabled)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = enabled
		end
	end
end

-- One-shot: emit `n` particles from an already-attached effect, then leave it idle.
function VFXLibrary.Burst(att, n)
	for _, d in ipairs(att:GetChildren()) do
		if d:IsA("ParticleEmitter") then
			d:Emit(n or 20)
		end
	end
end

-- Fire-and-forget explosion at a point: places the template, emits once, cleans itself up.
function VFXLibrary.BurstAt(parent, path, cframe, opts)
	opts = opts or {}
	local clone = VFXLibrary.Place(parent, path, cframe, opts)
	local emitted = opts.count or 24
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			d:Emit(emitted)
		end
	end
	game:GetService("Debris"):AddItem(clone, opts.lifetime or 4)
	return clone
end

return VFXLibrary
