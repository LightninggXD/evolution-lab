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

-- Flat tint. Deliberately destroys the source gradient: it is only used on the generic
-- white/grey effects (sparkles, charge, stars) that have to read as a zone's colour.
local function tintOf(color)
	return ColorSequence.new(color)
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
--   targetRate number  combined particles/second for the whole effect; preferred over `rate`
--   rate    number    raw multiplier on Rate, for when the source density is already right
--   color   Color3    flat tint, see tintOf
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

	local scale = opts.scale or 1
	local rate = rateFactor(template, opts, accept)
	local count = 0

	for _, source in ipairs(template:GetDescendants()) do
		if source:IsA("ParticleEmitter") and accept(source) then
			local emitter = source:Clone()
			emitter.Size = scaleSequence(emitter.Size, scale)
			emitter.Speed = scaleRange(emitter.Speed, scale)
			emitter.Rate = emitter.Rate * rate
			if opts.color then
				emitter.Color = tintOf(opts.color)
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
				d.Color = tintOf(opts.color)
			end
		elseif d:IsA("Beam") and opts.color then
			d.Color = tintOf(opts.color)
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
