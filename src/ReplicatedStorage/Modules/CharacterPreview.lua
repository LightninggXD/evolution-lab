--[[
	CharacterPreview - the hundred Journal characters, drawn as themselves.

	The Journal used to be a hundred coloured discs with an emoji on each. Half the roster shares
	the same emoji, so the panel that exists to show a player what they have collected showed them
	twenty rows of the same handful of symbols. This builds the ACTUAL rig instead -- the same
	StageCostume that dresses the body in the world, on a stand-in body, inside a ViewportFrame.
	What you see in the Journal is exactly what you turn into when you press it.

	Three things a ViewportFrame does NOT do, all of which shape this file:

	  * IT DOES NOT SIMULATE. Welds never resolve, so a costume built the normal way would render
	    as a heap of parts at the origin. StageCostume happens to place each piece with an explicit
	    `part.CFrame = host.CFrame * offset` BEFORE welding it, so the geometry is already correct
	    the moment it is built -- the welds are then dead weight and are destroyed, which also
	    stops the C0 tweens the moving pieces (haloes, orbitals, gears) leave running forever.
	  * IT DOES NOT DRAW HIGHLIGHTS. The dark rim that makes a costume read as drawn rather than as
	    a pile of boxes is a Highlight, and it is invisible here. The lighting is set to compensate
	    -- strong key, bright ambient -- and the cells carry their own outline in the UI instead.
	  * IT DOES NOT ANIMATE. The stand-in is stored in a rest pose, and the turntable in MainUI
	    turns the whole model rather than any joint.

	The stand-in (`ReplicatedStorage.Assets.PreviewRig`) is a real R15 rig built from a
	HumanoidDescription carrying EvolutionVisuals' own PROPORTION values -- 0.92 height, 1.22 wide
	and deep, 1.32 head, classic build -- so the costume sits on the same shape it sits on in the
	world. Built once and stored rather than made here, because the API that makes one is not
	available on the client.
]]

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local StageCostume = require(RS.Modules.StageCostume)
local SkinMesh = require(RS.Modules.SkinMesh)

local CharacterPreview = {}

local TEMPLATE = RS:WaitForChild("Assets"):WaitForChild("PreviewRig", 20)

-- An R15 rig's identity CFrame looks down -Z, so a camera that wants to see its face stands on
-- the -Z side of it. Hard-won: on +Z every preview in the panel was the back of a head.
local FACE_AXIS = -1

-- A dressed stage comes out at 240-270 parts -- rivets, beads, pupils, orbiting shards, skin
-- marks. That is right on a character you stand next to and absurd in an 84-pixel disc, and a
-- panel showing twenty of them at once is five thousand parts being rendered behind a scroll.
--
-- So a cell keeps only its biggest pieces. Biggest BY VOLUME, which is the same rule this game's
-- art notes already state twice: a costume reads by its outline, the outline is made of the few
-- big shapes, and at this size the small ones are a smudge whatever they are. The big preview
-- passes no cap and gets the whole build.
local function cullToSilhouette(rig, maxParts)
	local folder = rig:FindFirstChild("StageCostume")
	if not folder then return end

	local parts = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts <= maxParts then return end

	table.sort(parts, function(a, b)
		local av = a.Size.X * a.Size.Y * a.Size.Z
		local bv = b.Size.X * b.Size.Y * b.Size.Z
		if av == bv then return a.Name < b.Name end
		return av > bv
	end)
	for i = maxParts + 1, #parts do
		-- the eyes are the exception and they are worth the exception: two flat 0.17-of-a-head
		-- squares are near the bottom of any sort by volume, and a blank cube is not a character
		if parts[i].Name ~= "StageEye" and parts[i].Name ~= "StageEyePupil" then
			parts[i]:Destroy()
		end
	end
end

-- Builds the rig for one Journal entry into `parent` (a ViewportFrame). Returns the model, or nil
-- if the stage or the stand-in is missing -- callers fall back to the emoji.
--
-- `parent` is required rather than optional: StageCostume.Apply refuses a character with no
-- parent, because every piece it makes is created straight into a folder under it.
--   opts.maxParts - cap on costume parts, biggest kept (default: no cap)
function CharacterPreview.Build(parent, stageIndex, entry, opts)
	opts = opts or {}
	if not (TEMPLATE and parent) then return nil end
	local stage = GameConfig.Stages[stageIndex]
	if not stage then return nil end

	local rig = TEMPLATE:Clone()
	rig.Name = entry and entry.key or ("Stage" .. stageIndex)
	rig.Parent = parent

	-- A generated skin, if this character has one -- and ANCHORED, because a ViewportFrame never
	-- runs the physics that would resolve a weld, so a welded copy renders as a heap of parts at
	-- the origin. StageCostume gets away without this only because it happens to place every piece
	-- with an explicit CFrame before welding it.
	local meshed = entry and SkinMesh.Apply(rig, entry.key, { anchored = true })
	if not meshed then
		local ok, err = pcall(StageCostume.Apply, rig, stageIndex, stage, entry)
		if not ok then
			warn(("[CharacterPreview] %s failed to dress: %s"):format(rig.Name, tostring(err)))
		end
	end

	-- A generated model is six segments, not two hundred parts, so there is nothing to cull -- and
	-- culling it by volume would delete a limb.
	if opts.maxParts and not meshed then
		cullToSilhouette(rig, opts.maxParts)
	end

	-- Everything static and self-contained: no welds to resolve, no tweens left running, no
	-- Highlight to look for a renderer that is not there.
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Highlight") or d:IsA("ParticleEmitter")
			or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") then
			-- particles and lights do not render in a ViewportFrame either; keeping them is a
			-- hundred emitters ticking behind a panel that cannot show any of them
			d:Destroy()
		end
	end

	-- The stand-in itself goes once it is covered. Apply has already made every one of its parts
	-- invisible for a dressed stage, so these are seventeen parts being submitted to the renderer
	-- to draw nothing. Human (stage 7) is the stage that IS the avatar and keeps them.
	if (rig:FindFirstChild("StageCostume") or rig:FindFirstChild("SkinMesh")) and stageIndex ~= 7 then
		for _, d in ipairs(rig:GetChildren()) do
			if d:IsA("BasePart") and d.Transparency >= 1 then
				d:Destroy()
			end
		end
	end

	-- Centred on what was actually BUILT, not on the stand-in inside it. A costume can be twice
	-- the height of the body it hangs on (crowns, haloes, wings), and a preview framed on the
	-- avatar puts all of that off the top of the frame.
	local cf = rig:GetBoundingBox()
	rig:TranslateBy(-cf.Position)
	return rig
end

-- Points `viewport`'s camera at whatever is in it. Separated from Build so the big preview and
-- the cells can frame the same rig differently.
--   opts.zoom      - >1 pulls back, <1 pushes in (default 1)
--   opts.yaw       - radians round the model, for the three-quarter view (default 0.36)
--   opts.pitch     - how far above eye level the camera sits, as a fraction of the model (0.16)
function CharacterPreview.Frame(viewport, model, opts)
	opts = opts or {}
	if not (viewport and model) then return nil end

	local _, size = model:GetBoundingBox()
	-- the sphere the whole build fits inside, so a wide character and a tall one are both framed
	-- by the same rule and no stage can grow out of its own cell
	local radius = math.max(size.Magnitude * 0.5, 0.5)

	local fov = 40
	local dist = (radius / math.tan(math.rad(fov * 0.5))) * (opts.zoom or 1)
	local yaw = opts.yaw or 0.36
	local at = Vector3.new(0, 0, 0)
	local eye = Vector3.new(
		math.sin(yaw) * dist * FACE_AXIS,
		radius * (opts.pitch or 0.16),
		math.cos(yaw) * dist * FACE_AXIS
	)

	local cam = viewport:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera")
		cam.Parent = viewport
	end
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(eye, at)
	viewport.CurrentCamera = cam
	return cam
end

-- The lighting every preview in the game uses. Bright and frontal on purpose: there is no
-- Highlight in here to carry the silhouette, so the shapes have to separate on shading alone.
function CharacterPreview.Light(viewport)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(188, 192, 208)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.35, -0.9, -0.6)
	return viewport
end

return CharacterPreview
