-- SwordPreview -- a blade in a disc, for the Weapon ladder's rows (33.26).
--
-- ===== WHERE IT COMES FROM =====
--
-- Her call, with a capture of the Weapon panel: *"ovde treba biti slika maca koji equipas, nesto
-- kao s petovima i da panel izgleda kao rebirth panel"* -- a picture of the blade on the row, drawn
-- the way the pet grid draws a pet, on rows that read like the rebirth ladder's rungs.
--
-- The pets' answer is `HUD/PetTile`: a saturated circular disc with a live `ViewportFrame` sitting
-- over it and the model's own rig inside. This is that, for a blade, and the disc is what carries
-- the rebirth-panel resemblance -- every rung on that ladder is a big round emblem beside two lines
-- of text.
--
-- ===== IT DOES NOT USE `SwordModel`, AND THAT IS DELIBERATE =====
--
-- `ServerScriptService.Sword.SwordModel` is the real blade: 612 lines that weld to a character's
-- hand, raycast a stand-off out of the costume shell, hang spark emitters and pose two mitts. It is
-- in `ServerScriptService`, so a client cannot reach it at all, and moving it would drag the whole
-- character-welding apparatus into `ReplicatedStorage` to draw a 56-pixel picture.
--
-- So this builds a CHUNKY BLADE FROM THE SAME CONFIG ROW instead -- `tier.color`, `tier.trim`,
-- `tier.material` and `tier.glow`, which is where a blade's identity actually lives. What is drawn
-- is the ladder's colour ladder, in one silhouette, ten times.
--
-- **AND THE TWO MESH BLADES ARE DELIBERATELY NOT USED EITHER.** Two of the ten rungs (`rusty` and
-- `crystal`) carry a `mesh` table and the other eight do not. Drawing those two as meshes and the
-- rest as boxes would make two rows of a ten-row ladder a different shape -- which reads as two
-- rows being special rather than as two rows having art, and a ladder's whole job is to look like
-- one ladder. See [[evolution-lab-chunky-look-rules]]: fewer big shapes, one silhouette.

local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))
local UITheme = require(script.Parent.Parent.UITheme)

local SwordPreview = {}

local WHITE = Color3.fromRGB(255, 255, 255)

-- The blade lies along +Y and is measured in studs the camera solve below reads back off the model,
-- so these are proportions rather than pixels: a 7.4-stud silhouette that is roughly one part grip
-- to three parts steel, which is the chunky read.
local function mk(name, size, cframe, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

--- Builds the blade for one `GameConfig.Swords` row as an anchored Model centred on the origin.
--- Nothing is parented until the caller does it.
function SwordPreview.Build(tier)
	local model = Instance.new("Model")
	model.Name = "BladePreview"

	local steel = tier.color
	local trim = tier.trim or steel
	-- `glow` is the config's own flag for the late rungs and it is the one property worth honouring
	-- here: at 56 px a Neon fill is the difference between "a green sword" and "a sword that is lit".
	local material = tier.glow and Enum.Material.Neon or (tier.material or Enum.Material.Metal)

	local pommel = mk("Pommel", Vector3.new(0.9, 0.6, 0.9), CFrame.new(0, -2.6, 0), trim,
		Enum.Material.Metal, model)
	mk("Grip", Vector3.new(0.7, 2.0, 0.7), CFrame.new(0, -1.4, 0), trim, Enum.Material.Wood, model)
	mk("Guard", Vector3.new(3.0, 0.55, 1.0), CFrame.new(0, -0.3, 0), trim, Enum.Material.Metal, model)
	mk("Blade", Vector3.new(1.3, 4.4, 0.36), CFrame.new(0, 2.1, 0), steel, material, model)
	-- The point is a WEDGE, not a smaller box: a flat-topped blade at this size reads as a spanner.
	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.Size = Vector3.new(0.36, 1.1, 1.3)
	-- A WedgePart's slope runs down its own -Z, so it is laid on its side and turned to point up +Y.
	tip.CFrame = CFrame.new(0, 4.85, 0) * CFrame.Angles(0, math.rad(90), math.rad(90))
	tip.Color = steel
	tip.Material = material
	tip.Parent = model

	model.PrimaryPart = pommel
	return model
end

--- Hangs a finished disc + viewport on `parent`, returns the disc.
--- `opts`: size (px), position, anchorPoint, zIndex.
function SwordPreview.Attach(parent, tier, opts)
	opts = opts or {}
	local px = opts.size or 56

	-- 0.22 toward white, PetTile's own number and for its own reason: the blade inside is already
	-- saturated, and a full-strength tier colour behind a full-strength tier blade is one colour
	-- twice. The row underneath is repainted per state by `SwordPanel.refresh`, so this disc is the
	-- one thing on the row that always states the BLADE's colour rather than the row's state.
	local disc = Instance.new("Frame")
	disc.Name = "BladeDisc"
	disc.Size = UDim2.new(0, px, 0, px)
	disc.Position = opts.position or UDim2.new(0, 10, 0.5, 0)
	disc.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0.5)
	disc.ZIndex = opts.zIndex or (parent.ZIndex + UITheme.Z.Content)
	disc.Parent = parent
	UIKit.styleCard(disc, tier.color:Lerp(WHITE, 0.22), UDim.new(1, 0), 3)

	-- PARENTED TO THE ROW AND NOT TO THE DISC, PetTile's rule: a full-radius corner CLIPS, and a
	-- blade is the one silhouette whose interesting end is at the edge of the frame.
	local preview = Instance.new("ViewportFrame")
	preview.Name = "BladePreviewFrame"
	preview.Size = UDim2.new(0, px - 4, 0, px - 4)
	preview.Position = disc.Position
	preview.AnchorPoint = disc.AnchorPoint
	preview.BackgroundTransparency = 1
	preview.BorderSizePixel = 0
	preview.Ambient = Color3.fromRGB(206, 206, 220)
	preview.LightColor = WHITE
	preview.LightDirection = Vector3.new(-0.4, -1, -0.55)
	preview.ZIndex = disc.ZIndex + 1
	preview.Parent = parent

	local model = SwordPreview.Build(tier)
	model.Parent = preview

	-- ===== THE CAMERA IS SOLVED FROM THE MODEL, NOT TYPED =====
	--
	-- PetTile's argument, and it applies here for the opposite reason: every blade in this ladder is
	-- the SAME size, so a fixed camera would in fact work -- right up to the first time somebody
	-- changes a proportion above and every one of the ten rows crops silently. Solving it costs two
	-- lines and cannot go stale.
	--
	--     distance = (extent / 2) / tan(fov / 2)
	--
	-- The extent is the LARGEST axis (the blade is far taller than it is wide).
	--
	-- PADDED BY 1.05, AND THE FIRST CAPTURE IS WHY IT IS NOT 1.3. PetTile pads by 1.25 because a pet
	-- is roughly as wide as it is tall and a disc has no corners to put a wing in, so the subject
	-- has to fit the INSCRIBED circle. A blade is the opposite shape: it is a diagonal line, and the
	-- tilt below lays it corner-to-corner, which is the one arrangement that USES the square the
	-- solve is for. At 1.3 the ten rows photographed as ten small daggers in big empty circles --
	-- see [[evolution-lab-chunky-look-rules]], fewer and bigger.
	--
	-- Read AFTER parenting ([[roblox-model-facing-and-scaling]]).
	local cam = Instance.new("Camera")
	cam.FieldOfView = 42
	local extents = model:GetExtentsSize()
	local reach = math.max(extents.X, extents.Y, extents.Z) * 1.05
	local dist = (reach / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
	local centre = model:GetBoundingBox().Position
	-- Tilted rather than square-on: a sword photographed dead upright is a vertical line, and a
	-- vertical line in a circle is the one composition that wastes the whole frame.
	cam.CFrame = CFrame.new(centre + Vector3.new(0, 0, dist)) * CFrame.Angles(0, 0, math.rad(-28))
	cam.CFrame = CFrame.new(cam.CFrame.Position, centre) * CFrame.Angles(0, 0, math.rad(-28))
	cam.Parent = preview
	preview.CurrentCamera = cam

	return disc, preview
end

return SwordPreview
