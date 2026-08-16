--[[
	SkinMesh - the two hundred characters, as generated models rather than as stacks of blocks.

	The bosses are the reference and they are not built from primitives: ServerStorage.BossMeshes
	holds an AI-generated model per zone, segmented head/torso/arms/legs, and BossService.meshRig
	scales it and hangs it off the rig. That is why they read as finished characters while a
	30-part StageCostume read as a pile of coloured boxes.

	This is the same idea for the player. A skin with a mesh in ReplicatedStorage.Assets.SkinMeshes
	wears it; a skin without one falls through to StageCostume exactly as before, so the game is
	playable at every point during a rollout that takes two hundred generations to finish.

	Three things that decide how this file is written:

	  * THE SEGMENT NAMES LIE. The generator is asked for head/torso/left arm/right arm/left leg/
	    right leg and returns models with those names, but what is IN them is whatever it felt like:
	    on the first bacteria the whole face was inside `torso` and `head` held only the antenna. So
	    a segment is assigned to a limb by WHERE IT SITS in the finished model, not by its name.

	  * A WELD PER SEGMENT, NOT A RIGID MODEL. Welding each piece to the R15 limb nearest it means
	    the animation engine walks, runs and swings the whole skin for free -- the same trick
	    StageCostume's shells use, and the reason a skin costs no per-frame work anywhere.

	  * THE AVATAR UNDERNEATH HAS TO GO. Its parts are made invisible, its face decal with them
	    (a Decal on a fully transparent part still draws), and its hats and hair are hidden -- the
	    same sweep StageCostume does, for the same reason.
]]

local RS = game:GetService("ReplicatedStorage")

local SkinMesh = {}

local FOLDER_NAME = "SkinMesh"
local INK = Color3.fromRGB(20, 14, 28)

-- Where the generated models live once they are published. Client-visible on purpose: the costume
-- has to exist on every machine (the Journal previews build it too), so ServerStorage is the wrong
-- home for these even though that is where the boss meshes sit.
local function meshFolder()
	return RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("SkinMeshes") or nil
end

-- Is there a generated model for this character? Cheap enough to call per frame; used by callers
-- to decide between this module and StageCostume without duplicating the lookup rule.
function SkinMesh.TemplateFor(key)
	local folder = meshFolder()
	if not (folder and key) then return nil end
	return folder:FindFirstChild("SkinMesh_" .. key)
end

function SkinMesh.Has(key)
	return SkinMesh.TemplateFor(key) ~= nil
end

-- THE SEGMENT NAME IS THE ANSWER WHEN THERE IS ONE.
--
-- Every model is generated with `segmentation = "explicit"` and exactly these six part names, and
-- the generator honours them: all 145 models produced so far came back with the six. So the name
-- is not a guess, it is what was asked for.
--
-- This file originally ignored the names and placed each segment by measuring where it sat, on the
-- evidence of one early bacteria whose antenna was inside `head` and whose face was inside
-- `torso`. Checking the same rule across the finished set showed how expensive that was:
--
--   wolf_grey   head->Torso  torso->L-Leg  right arm->L-Leg     <- a quadruped: body horizontal
--   hum_knight  head->Torso                                     <- a helmet reaching below 74%
--
-- A wolf's torso welded to its left leg walks apart the moment the player moves. Named assignment
-- is right on every one of those, so geometry drops to being the fallback for a segment the
-- generator names something unexpected.
local BY_NAME = {
	["head"] = "Head",
	["torso"] = "UpperTorso",
	["left arm"] = "LeftUpperArm",
	["right arm"] = "RightUpperArm",
	["left leg"] = "LeftUpperLeg",
	["right leg"] = "RightUpperLeg",
}

-- ===== A TEMPLATE THAT IS ITSELF AN R15 RIG NEEDS NEITHER OF THE RULES BELOW =====
--
-- The VIP skins are not generated: they are real Roblox catalog bundles, baked to a model by
-- Players:CreateHumanoidModelFromDescription, so their parts already carry the EXACT names of the
-- limbs they belong on -- LeftLowerArm, RightFoot, all fifteen. Welding each of those to the limb
-- of the same name is a 1:1 rig rather than a six-way collapse, so a bundle skin walks, swings and
-- turns its head like the avatar it was made as instead of moving in six rigid lumps.
--
-- Safe for the 200 generated skins because FindFirstChild is CASE-SENSITIVE and the generator was
-- asked for lower-case names (`head`, `torso`, ...), which match no limb. Where one did happen to
-- come back capitalised, this resolves it to the same limb BY_NAME would have.
local function directHost(part, character)
	local limb = character:FindFirstChild(part.Name)
	if limb and limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" and limb.Parent == character then
		return limb.Name
	end
	return nil
end

-- Fallback only. The bands are deliberately generous: a generated creature is squat and
-- big-headed, so the head occupies far more than the top sixth a real skeleton would give it.
local function hostFor(part, centre, size)
	local rel = part.Position - centre
	local ny = (rel.Y + size.Y * 0.5) / math.max(size.Y, 0.001) -- 0 at the soles, 1 at the crown
	local nx = rel.X / math.max(size.X, 0.001)
	if ny > 0.74 then return "Head" end
	if ny < 0.30 then return (nx < 0) and "LeftUpperLeg" or "RightUpperLeg" end
	if math.abs(nx) > 0.26 then return (nx < 0) and "LeftUpperArm" or "RightUpperArm" end
	return "UpperTorso"
end

-- A part's own name, or the name of the sub-model the generator wrapped it in (`torso` holding
-- `torso_geom`), whichever is one of the six. Recursive because that wrapping is one level deep.
local function namedHost(part, root)
	local node = part
	while node and node ~= root do
		local key = string.lower(string.gsub(node.Name, "_geom$", ""))
		if BY_NAME[key] then return BY_NAME[key] end
		node = node.Parent
	end
	return nil
end

-- The avatar under the skin. Same sweep StageCostume.setBodyHidden does, kept here so this module
-- can be used on a bare rig (the Journal's stand-in) with no StageCostume involved at all.
--
-- ONE ATTRIBUTE NAME FOR BOTH SWEEPS, AND IT IS CLEARED ON RESTORE. This used to write
-- `SkinBaseTransparency` while StageCostume wrote `StageBaseTransparency`, on the same parts,
-- neither ever removed -- so each sweep could record the OTHER one's hidden 1 as the "original"
-- transparency and hand it back on restore. That is a permanently invisible player, and the only
-- thing keeping it theoretical was the order the two happened to run in inside StageCostume.Clear:
-- one reordering away from shipping. Clearing the attribute is the half that matters -- a value that
-- does not survive a restore cannot be misread by the next hide.
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
			-- a Decal on a fully transparent part still renders, so the avatar's face would
			-- otherwise float inside the new head
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
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			for _, d in ipairs(acc:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = hidden and 1 or 0
					d.Transparency = hidden and 1 or 0
				end
			end
		end
	end
end

function SkinMesh.Clear(character)
	if not character then return end
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then existing:Destroy() end
	setBodyHidden(character, false)
end

-- Dresses `character` in the generated model for `key`. Returns true if it did.
--
-- `opts.anchored` builds a static copy with no welds -- what a ViewportFrame needs, since a
-- viewport never runs the physics that would resolve a weld.
function SkinMesh.Apply(character, key, opts)
	opts = opts or {}
	local template = SkinMesh.TemplateFor(key)
	-- A MISSING TEMPLATE IS NORMAL AND IS NOT WARNED ABOUT: only some of the 200 skins have a
	-- generated mesh, and `false` here is the documented fall-through to StageCostume's primitives.
	-- The other two halves of this test are not normal, and both used to return in silence -- the
	-- exact signature (stock avatar, no parts, no errors) recorded in src/STATUS.md.
	if not template then return false end
	if not (character and character.Parent) then
		warn(("[SkinMesh] no character to dress for '%s' -- the body left the workspace before Apply ran")
			:format(tostring(key)))
		return false
	end

	local head = character:FindFirstChild("Head")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not (head and torso) then
		warn(("[SkinMesh] '%s' on %s: head=%s torso=%s -- skin skipped, the player falls back to a costume or a stock avatar")
			:format(tostring(key), tostring(character.Name), tostring(head ~= nil), tostring(torso ~= nil)))
		return false
	end

	SkinMesh.Clear(character)

	-- MEASURED OFF THE LIMBS, AND ONLY THE LIMBS.
	--
	-- `character:GetBoundingBox()` is the obvious call and it is wrong twice over:
	--
	--   * it covers every DESCENDANT, so taking it after the mesh has been parented in makes the
	--     mesh part of what it is being scaled to fit -- a feedback loop that blew a 4.5-stud
	--     creature up to 3,065 studs the first time this function ran;
	--   * it includes ACCESSORIES. A player wearing hair and a hat measures 9.48 tall against a
	--     7.35-stud body, so the skin came out 32% oversized -- a wolf whose head was a third
	--     bigger than the character it was standing on.
	--
	-- The R15 limbs parented directly to the character are the body and nothing else. Hats, hair
	-- and the skin itself all live outside that set.
	local minV, maxV
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local a, b = part.Position - part.Size * 0.5, part.Position + part.Size * 0.5
			minV = minV and Vector3.new(math.min(minV.X, a.X), math.min(minV.Y, a.Y), math.min(minV.Z, a.Z)) or a
			maxV = maxV and Vector3.new(math.max(maxV.X, b.X), math.max(maxV.Y, b.Y), math.max(maxV.Z, b.Z)) or b
		end
	end
	if not minV then return false end
	local charSize = maxV - minV
	local charCF = CFrame.new((minV + maxV) * 0.5)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character

	local clone = template:Clone()
	clone.Parent = folder

	-- SIZED AGAINST THE BODY IT REPLACES, not against a constant. The player runs 1x to 9x across
	-- the twenty stages and any given skin can now be worn at any of them, so the mesh is scaled to
	-- whatever the avatar currently measures rather than to the stage it was authored for.
	local _, meshSize = clone:GetBoundingBox()
	if meshSize.Y > 0.001 then
		-- ScaleTo is ABSOLUTE, not a multiplier -- it sets the model's scale factor, and the template
		-- is authored at 1, so this is the factor and not a step.
		clone:ScaleTo((charSize.Y * (opts.fill or 1.02)) / meshSize.Y)
	end

	-- NO AUTO-ORIENTING HERE, AND THE REASON IS WORTH KEEPING.
	--
	-- 25 of the first 145 models came back with a bounding box DEEPER than it is wide, and "Z > X
	-- means the generator drew it in profile, so rotate it 90 degrees" looks like an obvious fix.
	-- It is wrong, and a screenshot is what proved it: those models were already facing -Z and the
	-- rotation turned every one of them side-on.
	--
	-- Z > X does not mean "sideways", it means QUADRUPED -- a wolf or a lizard is longer nose to
	-- tail than it is wide across the shoulders, whichever way it is pointing. The generator had
	-- honoured the camera and ignored "standing upright", which is a prompt problem and has to be
	-- fixed by regenerating those characters as bipeds, not by turning them.
	local meshCF, size = clone:GetBoundingBox()

	-- WHICH LIMB EACH PIECE BELONGS TO, DECIDED BEFORE ANYTHING ELSE IS ROTATED.
	--
	-- hostFor reads a part's offset along X and Y, which only means "left/right" and "high/low"
	-- while the model is still axis-aligned. Assign first, move second -- reading it after the yaw
	-- below would swap a creature's arms whenever it happened to be facing east.
	local hostOf, matchedByName = {}, {}
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			local direct = directHost(part, character)
			hostOf[part] = direct or namedHost(part, clone) or hostFor(part, meshCF.Position, size)
			-- The one record of which parts came off a real R15 rig rather than a generated blob.
			-- Nothing downstream reads it today -- see the block below the yaw for the fix that was
			-- built on it, measured, and thrown away -- and it is kept because deriving it later
			-- means re-deriving it AFTER the parts have moved, which no longer gives the same answer.
			if direct then matchedByName[part] = true end
		end
	end

	-- Stood where the body stands, turned the way the body faces. A generated model arrives
	-- axis-aligned and the character can be standing anywhere; `GetPivot` relative to the bounding
	-- centre is the rotation-free handle that lets both happen in one move.
	--
	-- The maths is correct FOR A MODEL AUTHORED FACING -Z, and that is the whole assumption:
	-- CFrame.Angles(0, yaw, 0) maps (0,0,-1) to (-sin yaw, 0, -cos yaw), which with
	-- yaw = atan2(-look.X, -look.Z) is exactly `look`. Verified on a worn character -- the head sits
	-- 1.88 studs ahead of the torso along the facing and 0.01 studs to the side.
	--
	-- SOME OF THE TEMPLATES WERE GENERATED THE OTHER WAY ROUND, and for those the same rotation
	-- points the model's BACK down the character's forward: in third person the camera is behind the
	-- player, so you end up looking at a face where the back of a head belongs.
	--
	-- There is no way to tell which is which from the geometry, and it is not for want of trying.
	-- Head-vs-torso offset carries no information at all on a biped whose head sits over its torso,
	-- and left-arm-vs-right-arm assumes the generator is consistent about whose left it means. Both
	-- were measured across all 200 and both produce false positives that were then confirmed by eye
	-- -- two models each test accused turned out to be facing the right way. The face lives in the
	-- TEXTURE, and nothing a Size or Position query can reach knows where it is.
	--
	-- So the answer is data, not inference: every template that was seen to be backwards carries a
	-- `FaceFlip` attribute, and it costs a half turn on top of the yaw. A template without the
	-- attribute behaves exactly as before, so this is inert until something is marked.
	local root = character:FindFirstChild("HumanoidRootPart") or torso
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	if template:GetAttribute("FaceFlip") then
		yaw = yaw + math.pi
	end
	local localPivot = CFrame.new(meshCF.Position):Inverse() * clone:GetPivot()
	clone:PivotTo(CFrame.new(charCF.Position) * CFrame.Angles(0, yaw, 0) * localPivot)

	-- ===== A BUNDLE'S OWN LAYOUT IS KEPT, AND SNAPPING EACH LIMB TO ITS HOST IS THE TRAP =====
	--
	-- The obvious-looking fix for "this bundle's head sits low" is to move every name-matched part
	-- onto the limb of the same name, so the AVATAR decides the proportions and the mesh decides only
	-- the shape. It was written, run and photographed: it takes the skin apart. A bundle mesh is not
	-- centred on the joint it belongs to -- a hand mesh's centre is not the rig hand's centre, a
	-- forearm's is not the forearm's -- so centre-to-centre snapping scatters the arms a stud or two
	-- out from the body and the character comes apart into floating pieces. The template's own
	-- relative layout is the thing holding it together; scaling it as one piece is what respects it.
	--
	-- So a bundle wears its own proportions on purpose, and the ones whose proportions do not survive
	-- that are rejected at the roster instead -- see the note over GameConfig.VipCharacters. This
	-- comment is here so the next reader does not spend the afternoon rediscovering it.
	--
	-- `matchedByName` is still computed above because it costs nothing and it is the one place that
	-- records WHICH parts came from a real R15 rig; the moment something else needs to know, it is
	-- already there.

	local placed = 0
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			local hostName = hostOf[part] or "UpperTorso"
			local host = character:FindFirstChild(hostName)
				-- R6 has neither UpperTorso nor the split limbs; fall back to what it does have
				or character:FindFirstChild("Torso") or torso
			part.Anchored = opts.anchored == true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Massless = true -- a skin must never change how the character moves
			part.Parent = folder

			if not opts.anchored then
				local weld = Instance.new("Weld")
				weld.Name = "SkinWeld"
				weld.Part0 = host
				weld.Part1 = part
				weld.C0 = host.CFrame:Inverse() * part.CFrame
				weld.Parent = part
			end
			placed += 1
		end
	end
	clone:Destroy()

	if placed == 0 then
		folder:Destroy()
		warn(("[SkinMesh] template for '%s' contains no BaseParts -- generated model is empty"):format(tostring(key)))
		return false
	end

	-- THE OUTLINE. The same dark rim the pets and the costumes wear, and the single biggest reason
	-- a model reads as drawn rather than as geometry. Occluded, so a player behind a wall does not
	-- glow through it. Skipped for a viewport copy: a ViewportFrame does not render Highlights.
	if not opts.anchored then
		local outline = Instance.new("Highlight")
		outline.Name = "SkinOutline"
		outline.FillTransparency = 1
		outline.OutlineColor = INK
		outline.OutlineTransparency = 0
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Adornee = character
		outline.Parent = folder
	end

	-- last, so a failure above leaves a visible player rather than an invisible one
	setBodyHidden(character, true)
	return true
end

return SkinMesh
