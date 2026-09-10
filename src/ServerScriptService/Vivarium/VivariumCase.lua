--[==[
	VivariumCase -- the geometry of ONE display case in the Vivarium, and nothing about who owns it
	(24.1).

	Split from `VivariumPlaza` for the reason `evolution-lab-small-modules-rule` gives: that file
	owns the LAND (where sixty anchors are, which player holds which one, and what the board says),
	this one owns the OBJECT. The seam is one call -- `Build(frame)` returns handles and never reads
	a save -- which is also what makes a case testable on its own, standing in open ground with no
	player attached to it.

	===== IT IS A NICHE, NOT A BOX, AND NOT A BILLBOARD ON A POST =====

	Three shapes were considered and two are wrong here:

	  * A glassed box is what a vivarium actually looks like and it is the one shape this game
	    cannot afford: `evolution-lab-animated-water` measured that three transparencies COMPOUND,
	    and a pane in front of a rig that already carries a tinted outline reads as fog. The front
	    is open.
	  * A plain board on posts is what `PartyStand` is, and it is right there -- but a board states
	    a number where this has to state a COLLECTION. The pets are the content, so they need a
	    shelf to stand on and a dark field behind them to read against.

	So: a flush pad, a dark back wall, three lit shelves, a lid, and an open front with a low sill.
	Five big shapes and an outline, which is `evolution-lab-chunky-look-rules` applied literally.

	===== EVERY PIECE IS PLACED THROUGH THE FRAME, NEVER ROTATED AFTERWARDS =====

	`Build` takes a CFrame and every part is `frame * CFrame.new(local)`. That is deliberate and it
	is the trap in `roblox-model-facing-and-scaling`: a quarter-turn yaw faces MINUS X, not plus X,
	so a case built at world coordinates and spun afterwards ends up with its open front against a
	wall on half the rows. Here the front is **local -Z** in every case, and the half of the gallery
	that faces the other way is handed a frame that is already turned round. Nothing in this file
	knows which half it is building.

	===== THE RIG'S FEET ARE MEASURED, NOT ASSUMED =====

	`PetModel.Place` puts the rig's ROOT at the CFrame it is given, and the root is not the foot --
	`roblox-authored-scenery-foot-floats` is the same fault one object over. A rig dropped at a
	shelf's top surface therefore sinks into it by whatever that species' root offset happens to be,
	and it differs per archetype. `SeatOnShelf` places once, reads the real bounding box, and places
	again lifted by the gap it measured, so a blob and a dragon both stand ON the shelf.

	Slot pitch is 4.2 and that is derived: a rig measures 2.90 x 2.86 x 3.28 at scale 1 (measured
	live on one of each of the five archetypes, 2026-09-10), so 4.2 leaves 1.3 between neighbours
	and 8.0 of shelf holds exactly two. See the GEOMETRY block for why it is two and not three.
]==]

local RS = game:GetService("ReplicatedStorage")

local PetModel = require(RS.Modules.PetModel)
local UITheme = require(RS.Modules.UITheme)

local VivariumCase = {}

-- The plaza's own palette, because a case stands on the plaza's lawn and a second scheme beside it
-- would read as a different game's furniture. See `HubPlaza`'s GEOMETRY block.
local OUTLINE = Color3.fromRGB(26, 22, 42)
local STONE = Color3.fromRGB(178, 152, 116)
local STONE_DARK = Color3.fromRGB(104, 76, 52)
local ACCENT = Color3.fromRGB(146, 116, 240)
local FIELD = Color3.fromRGB(34, 28, 52) -- the dark field a bright rig reads against

-- ============================================================================
-- GEOMETRY -- all local, front is -Z
-- ============================================================================
-- ===== THE CASE IS TALL AND NARROW BECAUSE THE LAND SAID SO =====
--
-- It was 12 x 10 with two shelves of three. That case is fine and the GALLERY of it is not: at a
-- 14-stud pitch the three measured banks offer 70 positions and the live world refuses 32 of them
-- (9 in a horizon-hill collider, 7 on the sprint track, 16 in a jungle trail), which leaves 38 for
-- a server that seats 60. Widening the banks cannot help -- the mountains and the roads are INSIDE
-- the rectangles, not at their edges -- so the only lever that moves the count is the footprint.
--
-- Six slots are kept exactly as they were, because the rebirth ladder in `VivariumPlaza` is written
-- against that number. They are re-stacked **three shelves of two** instead of two of three, which
-- takes the case from 12 x 10 to 9 x 8: at a 10-stud pitch the same three banks now offer enough
-- positions for the same 60 (measured: 60 of 60 found). It is also the better object -- a tall
-- narrow vitrine reads as a
-- display case, where a wide shallow one reads as a bus shelter.
--
-- ===== THE CLEARANCES ARE DERIVED FROM THE TALLEST RIG, AND THE FIRST NUMBER WAS THE WRONG RIG =====
--
-- A rig measures 2.90 x 2.86 x 3.28 at scale 1 -- **at tier Normal**, which is the only tier the
-- first survey built. Every tier above it is TALLER: measured across all four on one of each of the
-- five archetypes, Golden, Rainbow and Celestial all come out at **3.50**, and only Normal is 2.86.
-- An endgame collection is mostly not Normal, so 3.50 is the number this case has to hold.
--
-- Spacing 4.0 on a 0.6 shelf leaves 3.40 of clear air, and 3.40 - 3.50 is **-0.10**: a Golden pet
-- on the lower shelf pokes through the one above it. Built and measured live before it was caught,
-- which is the only reason it was -- and the probe that first looked at it reported "+0.20" because
-- it compared the rig's top against the shelf's CENTRE instead of its underside. Two wrong numbers
-- agreeing is not a confirmation.
--
-- So: shelves **4.4** apart, which is 3.80 of clear air and 0.30 of real headroom over a 3.50 rig,
-- and the wall grew with them. The top shelf's rig tops out at 15.94 under a roof whose underside
-- is at 16.74. None of these numbers is round and none of them may be rounded.
local PAD_W, PAD_D = 9, 8
local PAD_TOP = 0.34 -- the pad states its TOP face and is grown downward, so it never shares the
                     -- lawn's plane -- the rule HubPlaza and SprintTrack both write out
local WALL_H = 16.4
local BACK_T = 0.7
local FIN_T = 0.7
local ROOF_T = 0.8

local SHELF_W, SHELF_T, SHELF_D = 8.0, 0.6, 5.4
local SHELF_Y = { 3.0, 7.4, 11.8 } -- above PAD_TOP, 4.4 apart; see the block above
local SHELF_Z = 0.6                -- spans -2.1..3.3, meeting the back wall's inner face exactly

-- 4.2 apart for a rig 2.90 wide: 1.3 of daylight between two specimens, and the pair spans 7.1 of
-- an 8.0 shelf.
local SLOT_X = { -2.1, 2.1 }
VivariumCase.SlotsPerShelf = #SLOT_X
VivariumCase.MaxSlots = #SLOT_X * #SHELF_Y

local BOARD_W, BOARD_H = 10, 5
local BOARD_Y = PAD_TOP + WALL_H + ROOF_T + 3.0

VivariumCase.Width = PAD_W
VivariumCase.Depth = PAD_D

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function styleText(label, colour, align)
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font.Display
	label.TextColor3 = colour or Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(14, 10, 22)
	label.TextStrokeTransparency = 0.15
	label.TextXAlignment = align or Enum.TextXAlignment.Center
end

-- ============================================================================
-- BUILD
-- ============================================================================
--- Stand one empty case at `frame`. Returns the handles `VivariumPlaza` needs and no state.
-- @param frame CFrame -- position and facing; the open front is the frame's -Z
function VivariumCase.Build(frame, name)
	local model = Instance.new("Model")
	model.Name = name or "VivariumCase"

	local function at(x, y, z)
		return frame * CFrame.new(x, y, z)
	end

	newPart({
		Name = "CasePad", Size = Vector3.new(PAD_W, PAD_TOP + 1.2, PAD_D),
		CFrame = at(0, PAD_TOP - (PAD_TOP + 1.2) * 0.5, 0),
		Color = STONE, CanCollide = true, Parent = model,
	})
	-- The sill is what gives the open front an edge. Low enough to step over, which matters for
	-- 24.2 and 24.3 later -- a case you cannot walk into is not a plot.
	newPart({
		Name = "CaseSill", Size = Vector3.new(PAD_W, 0.4, 0.7),
		CFrame = at(0, PAD_TOP + 0.2, -(PAD_D * 0.5 - 0.35)),
		Color = OUTLINE, CanCollide = false, Parent = model,
	})
	newPart({
		Name = "CaseBack", Size = Vector3.new(PAD_W, WALL_H, BACK_T),
		CFrame = at(0, PAD_TOP + WALL_H * 0.5, PAD_D * 0.5 - BACK_T * 0.5),
		Color = FIELD, CanCollide = true, Parent = model,
	})
	for _, sx in ipairs({ -1, 1 }) do
		newPart({
			Name = "CaseFin", Size = Vector3.new(FIN_T, WALL_H, PAD_D - 0.7),
			CFrame = at(sx * (PAD_W * 0.5 - FIN_T * 0.5), PAD_TOP + WALL_H * 0.5, 0.35),
			Color = OUTLINE, CanCollide = true, Parent = model,
		})
	end
	newPart({
		Name = "CaseRoof", Size = Vector3.new(PAD_W + 1.0, ROOF_T, PAD_D + 1.0),
		CFrame = at(0, PAD_TOP + WALL_H + ROOF_T * 0.5, 0.35),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})

	-- The shelves, and the slot anchors on them. An anchor is an invisible part rather than a bare
	-- CFrame because `SeatOnShelf` needs something to measure against and 24.3 will need something
	-- to name when it takes a specimen off one.
	local slots = {}
	for si, sy in ipairs(SHELF_Y) do
		newPart({
			Name = "CaseShelf" .. si, Size = Vector3.new(SHELF_W, SHELF_T, SHELF_D),
			CFrame = at(0, PAD_TOP + sy, SHELF_Z),
			Color = STONE_DARK, CanCollide = false, Parent = model,
		})
		-- A thin lit strip under each shelf's front lip. It is the one piece of light in the case
		-- and it is what stops the dark field reading as a hole from the aisle.
		newPart({
			Name = "CaseGlow" .. si, Size = Vector3.new(SHELF_W, 0.2, 0.28),
			CFrame = at(0, PAD_TOP + sy - SHELF_T * 0.5 - 0.1, SHELF_Z - SHELF_D * 0.5),
			Color = ACCENT, Material = Enum.Material.Neon,
			CanCollide = false, CanQuery = false, Parent = model,
		})
		for xi, sx in ipairs(SLOT_X) do
			local anchor = newPart({
				Name = ("Slot%d_%d"):format(si, xi),
				Size = Vector3.new(1, 1, 1),
				CFrame = at(sx, PAD_TOP + sy + SHELF_T * 0.5, SHELF_Z),
				Transparency = 1, CanCollide = false, CanQuery = false, Parent = model,
			})
			table.insert(slots, { anchor = anchor, topY = anchor.Position.Y })
		end
	end

	-- NOTHING BEHIND THE NAMEPLATE, which is `roblox-billboard-and-its-backing-board` applied: a
	-- BillboardGui turns to face the camera and a slab does not, so a backing plank the size of
	-- this panel comes apart the moment you look at the case off-axis.
	local boardAnchor = newPart({
		Name = "BoardAnchor", Size = Vector3.new(2, 2, 2),
		CFrame = at(0, BOARD_Y, 0),
		Transparency = 1, CanCollide = false, CanQuery = false, Parent = model,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "CaseBoard"
	-- Studs, not pixels: a case is furniture you walk up to, so its sign should shrink with
	-- distance the way the plaza's signs do. (A pixel-sized plate is for the other job -- a marker
	-- that has to survive 900 studs, which is what `RarityBeam`'s label is for.)
	gui.Size = UDim2.new(BOARD_W, 0, BOARD_H, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Adornee = boardAnchor
	gui.Parent = boardAnchor

	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = Color3.fromRGB(24, 22, 34)
	shell.BackgroundTransparency = 0.08
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = ACCENT
	stroke.Parent = shell

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.94, 0.34)
	title.Position = UDim2.fromScale(0.03, 0.06)
	styleText(title, Color3.fromRGB(240, 238, 250))
	title.Text = ""
	title.Parent = shell

	-- The passive rate, given its own line and the accent colour because it is the one number on
	-- this board the row asks for by name.
	local rate = Instance.new("TextLabel")
	rate.Name = "Rate"
	rate.Size = UDim2.fromScale(0.94, 0.30)
	rate.Position = UDim2.fromScale(0.03, 0.40)
	styleText(rate, ACCENT)
	rate.Text = ""
	rate.Parent = shell

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.fromScale(0.94, 0.22)
	sub.Position = UDim2.fromScale(0.03, 0.72)
	styleText(sub, Color3.fromRGB(186, 180, 206))
	sub.Text = ""
	sub.Parent = shell

	-- Atomic rather than Persistent, and that is a considered difference from `PartyStand` and the
	-- plaza: those are DOORS, and a door that streams out is a door that is not there. A case is
	-- something you read from the aisle, so ordinary streaming is correct -- but it should arrive
	-- as one object rather than assembling itself shelf by shelf in front of the player.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	return {
		model = model,
		slots = slots,
		board = { shell = shell, title = title, rate = rate, sub = sub },
	}
end

-- ============================================================================
-- SEATING A RIG
-- ============================================================================
--- The lowest point of a model in WORLD space, derived from each part's own rotation.
--
-- `Model:GetBoundingBox` is not used here and that is deliberate: it answers in the PIVOT's frame
-- (`roblox-model-box-getters-are-pivot-frame`), so reading `.Y` off it is only accidentally right
-- while every frame in this gallery happens to be yaw-only. This is the same world-AABB arithmetic
-- the placement census used, and it cannot be wrong about which way is up.
local function worldBottom(model)
	local lowest = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, sz = d.CFrame, d.Size
			local hy = math.abs(cf.UpVector.Y) * sz.Y * 0.5
				+ math.abs(cf.RightVector.Y) * sz.X * 0.5
				+ math.abs(cf.LookVector.Y) * sz.Z * 0.5
			lowest = math.min(lowest, cf.Position.Y - hy)
		end
	end
	return lowest
end

--- Stand `rig` on the slot so its lowest point rests on the shelf. See the header: the root is not
-- the foot, and the offset differs per archetype, so it is measured rather than assumed.
function VivariumCase.SeatOnShelf(rig, root, pieces, slot)
	local base = slot.anchor.CFrame
	PetModel.Place(root, pieces, base)
	local lift = slot.topY - worldBottom(rig)
	-- `+ Vector3` rather than `* CFrame`: a world-space lift, so a turned-round case in the far
	-- half of the gallery raises its rigs rather than pushing them sideways.
	local seated = base + Vector3.new(0, lift, 0)
	PetModel.Place(root, pieces, seated)
	return seated
end

return VivariumCase
