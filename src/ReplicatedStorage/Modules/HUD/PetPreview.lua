-- PetPreview -- the rig of one pet in a ViewportFrame, with the camera SOLVED to fit it.
--
-- ===== WHY THIS IS ITS OWN FILE =====
--
-- It was `PetTile`'s, and the bag grid was the only screen in the game that drew a pet. Then
-- Kristina opened the enchant-transfer picker (34.5) and said the obvious thing: *"treba da ima
-- slike ljubimaca kao i pet panel, iste takve ljubimce treba da player vidi kome ide a ne da
-- nagadja"* -- a list of a hundred pets showing only their NAMES is a list you choose from by
-- guessing.
--
-- The camera solve below is not two lines of arithmetic; it is four captures' worth of finding out
-- that **no fixed camera can serve a hundred species**, and the reasoning is written out because it
-- is the part that looks arbitrary to the next reader. Copying that into a second panel is how this
-- repo ends up with two cameras that disagree the first time a rig changes size -- so `PetTile`
-- calls this too, and there is exactly one copy.
--
-- Sibling of `HUD/SwordPreview`, deliberately the same shape (`Attach(parent, thing, opts)`).

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local PetModel = require(RS.Modules:WaitForChild("PetModel"))

local PetPreview = {}

--- Hangs a live rig for `pet` on `parent`.
---
--- Returns `preview, rigRoot, rigPieces`. The last two are what a turntable needs, and are nil when
--- the pet's key names no definition -- a save carrying a species a later build removed. Nothing is
--- animated here: whoever wants a spin owns the one Heartbeat that drives it, which is `PetsGrid`'s
--- rule and the reason this does not start a second one per panel.
function PetPreview.Attach(parent, pet, opts)
	opts = opts or {}
	local px = opts.size or 84

	local preview = Instance.new("ViewportFrame")
	preview.Name = opts.name or "Preview"
	preview.Size = UDim2.new(0, px, 0, px)
	preview.Position = opts.position or UDim2.new(0.5, 0, 0, 2)
	preview.AnchorPoint = opts.anchorPoint or Vector2.new(0.5, 0)
	preview.BackgroundTransparency = 1
	preview.BorderSizePixel = 0
	preview.Ambient = Color3.fromRGB(206, 206, 220)
	preview.LightColor = Color3.fromRGB(255, 255, 255)
	preview.LightDirection = Vector3.new(-0.4, -1, -0.55)
	preview.ZIndex = opts.zIndex or (parent.ZIndex + UITheme.Z.Content)
	preview.Parent = parent

	local def = GameConfig.GetPetDef(pet and pet.key)
	if not def then
		return preview, nil, nil
	end

	-- Same build as the world rig, no nameplate, no outline, no sparkle -- at this size an outline
	-- is a smear and a sparkle is noise.
	local rig, rigRoot, rigPieces = PetModel.Build(def, pet.tier, {
		scale = 1,
		nameplate = false,
		outline = false,
		sparkle = false,
	})
	PetModel.Place(rigRoot, rigPieces, CFrame.new())
	rig.Parent = preview

	-- ===== THE CAMERA IS FITTED TO THE RIG, AND A FIXED ONE CANNOT BE RIGHT =====
	--
	-- Three captures were spent moving a hard-coded camera in and out -- 40 deg at 6.9 studs cropped
	-- every pet through the head, 44 deg at 10.4 shrank them to a speck, and the card's own proven
	-- 45 deg at 8.3 landed between the two and STILL read wrong. The fourth capture named the real
	-- fault: **there is no single right distance, because the hundred species are not one size.**
	-- `Absolon` is a wide flat rig and `TheFirst` is a tall one; the same camera makes one a stripe
	-- across the frame and the other a dot in the middle of it.
	--
	-- So the distance is SOLVED from the rig instead. `FieldOfView` is the vertical angle and the
	-- viewport is square, so the horizontal one matches and a single solve covers both:
	--     distance = (extent / 2) / tan(fov / 2)
	--
	-- **The extent is the LARGEST axis, not the height**, because the bag grid spins this rig a full
	-- +/-0.55 rad on Y -- a fit taken on the depth axis lets a long tail swing outside the frame a
	-- second after it was measured.
	--
	-- `GetExtentsSize` IS TAKEN AFTER `Place` AND AFTER PARENTING, which is not fussiness: a
	-- bounding box read one frame early is the exact fault [[roblox-model-facing-and-scaling]]
	-- records, and it reads as a camera that is right for some pets and wrong for others.
	local extents = rig:GetExtentsSize()
	local span = math.max(extents.X, extents.Y, extents.Z)
	local fov = 45
	-- PADDING IS THE CALLER'S, because the frame it sits in is. The grid's tile is a CIRCLE and a
	-- disc has no corners for a wing to occupy, so its subject must fit the inscribed circle: 1.25.
	-- A card's slot is a rounded square that can use its corners, so it asks for less and the pet
	-- comes out bigger. Defaulted to the grid's number so an omitted option cannot crop anything.
	local dist = (span * 0.5) / math.tan(math.rad(fov) * 0.5) * (opts.padding or 1.25)
	-- A floor, because a genuinely tiny rig would otherwise pull the camera inside itself and render
	-- the inside of its own head.
	dist = math.max(dist, 3.5)
	local centre = rig:GetPivot().Position

	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	-- Off-axis (a touch right, a touch above) so the rig reads as three-dimensional rather than as a
	-- mugshot -- scaled to whatever distance the fit asked for rather than typed as magic numbers.
	cam.CFrame = CFrame.new(centre + Vector3.new(0.36, 0.32, -0.88).Unit * dist, centre)
	cam.Parent = preview
	preview.CurrentCamera = cam

	return preview, rigRoot, rigPieces
end

return PetPreview
