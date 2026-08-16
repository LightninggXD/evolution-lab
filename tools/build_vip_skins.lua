--!strict
-- Bakes the VIP wardrobe's bodies out of the Roblox catalog and into the place.
--
-- WHY THIS FILE EXISTS. The 200 ladder skins are generated meshes and the six event/VIP skins used
-- to be too, so "how was that model made" was always answerable by re-running `generate_mesh`. The
-- VIP wardrobe is not: each of its nine bodies is a real catalog BUNDLE, turned into a model by
-- Players:CreateHumanoidModelFromDescription at author time and parked in
-- ReplicatedStorage.Assets.SkinMeshes as `SkinMesh_<key>`. Those models are INSTANCES IN THE PLACE.
-- They are not files, no commit carries them, and `src/` cannot mirror them -- so without this
-- script the only record of how the wardrobe was built would be a Studio session that a crash ends.
-- Losing the place now costs one run of this, and nothing else.
--
-- HOW TO RUN IT. Paste the whole file into the Studio MCP's `execute_luau` with
-- `datamodel_type = "Edit"` (Play has no Assets folder to write into that survives). It is
-- idempotent: an existing `SkinMesh_<key>` is destroyed and rebuilt, so re-running after changing a
-- `bundleId` in GameConfig.VipCharacters is the whole update procedure.
--
-- IT READS GameConfig AND NOTHING ELSE. The roster, the keys and the bundle ids all come from
-- GameConfig.VipCharacters, and the retired list comes from GameConfig.RetiredVipKeys -- so this
-- script never has to be edited when the wardrobe changes, only re-run. `FIRST` and `LAST` exist
-- because nine bundles do not download inside the MCP call's 120-second window; run it in slices of
-- three or four.
--
-- WHAT IT STRIPS, AND WHY EACH ONE. `CreateHumanoidModelFromDescription` hands back a playable
-- character: a Humanoid, a HumanoidRootPart, an Animate script and the default sounds. SkinMesh.Apply
-- welds the parts of this model onto the player's own limbs, so every one of those is either dead
-- weight or an active fault -- a second Humanoid inside a character is the loud one. What is
-- deliberately KEPT is the limb NAMES (SkinMesh's `directHost` rule welds 1:1 by name, which is what
-- makes a bundle body animate instead of moving in six lumps) and the Accessories, whose Handles
-- fall through to the position-based host rule and land on the head or the back where they belong.
local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FIRST, LAST = 1, 9

-- REQUIRED THROUGH A CLONE, NOT DIRECTLY. Edit mode caches a ModuleScript's return value for the
-- lifetime of the Studio session, so a `require` here would hand back whatever GameConfig said the
-- first time anything asked -- which, on the run that matters, is the wardrobe from BEFORE the push
-- that changed it. A clone is a different instance and therefore a different cache entry.
local sourceClone = ReplicatedStorage.Modules.GameConfig:Clone()
sourceClone.Parent = ReplicatedStorage
local GameConfig = require(sourceClone)
sourceClone:Destroy()
local folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("SkinMeshes")
assert(folder, "ReplicatedStorage.Assets.SkinMeshes is missing -- nothing to bake into")

-- The outfit is the part of a bundle that carries the whole look; the other bundled items are the
-- individual body parts, which a HumanoidDescription would have to be assembled from by hand.
--
-- A MODERN BUNDLE HAS TWO OUTFITS AND ONLY ONE OF THEM IS A BODY. Every Rthro-era bundle ships
-- `<Name>` and `<Name> - Head`, both typed UserOutfit, and the head one describes a head and
-- nothing else: `GetHumanoidDescriptionFromOutfitId` on it returns `Torso = 0`, so
-- CreateHumanoidModelFromDescription builds the DEFAULT grey Roblox body and the bundle is not in
-- the result at all. It does not error and it does not warn -- it hands back a complete, plausible,
-- entirely wrong character, which is exactly the shape of bug that survives a code review and dies
-- to a screenshot. Measured on Bec the Fire God: the main outfit gives `Torso = 4201587439` and one
-- accessory, the head outfit gives `Torso = 0` and none.
--
-- So the outfit is chosen BY NAME -- the one called exactly what the bundle is called -- and the
-- first UserOutfit is only the fallback, for the classic bundles that ship a single one.
local function outfitOf(bundleId: number): number?
	local details = AvatarEditorService:GetItemDetails(bundleId, Enum.AvatarItemType.Bundle)
	local fallback = nil
	for _, item in ipairs(details.BundledItems or {}) do
		if tostring(item.Type) == "UserOutfit" then
			if tostring(item.Name) == tostring(details.Name) then
				return item.Id
			end
			fallback = fallback or item.Id
		end
	end
	return fallback
end

-- ===== AN ACCESSORY IS NOT WHERE IT LOOKS LIKE IT IS =====
--
-- A hat sits on a head because the Humanoid matched an Attachment inside its Handle to the
-- identically named Attachment on a limb, every frame, at runtime. In a baked model there is no
-- Humanoid -- SkinMesh.Apply welds the parts of this model straight onto the player's limbs at
-- whatever offsets they were saved with -- so an Accessory whose Handle was never snapped stays at
-- whatever the asset happened to load at. Measured on Korblox Deathspeaker: its head accessory sat
-- a couple of studs to the SIDE of the body, which on the character reads as a floating purple mask
-- beside a blank white head.
--
-- So the snap is done here, once, permanently, by the same arithmetic the Humanoid uses: put the
-- Handle where its own attachment lands on the limb's attachment of the same name. Accessories with
-- no matching pair are left alone rather than guessed at -- they fall through to SkinMesh's
-- position-based host rule, which is what the generated skins already rely on.
local function snapAccessories(model: Model)
	local attachmentOn = {}
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			for _, a in ipairs(part:GetChildren()) do
				if a:IsA("Attachment") then attachmentOn[a.Name] = a end
			end
		end
	end
	for _, accessory in ipairs(model:GetChildren()) do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				for _, a in ipairs(handle:GetChildren()) do
					local host = a:IsA("Attachment") and attachmentOn[a.Name]
					if host then
						handle.CFrame = host.WorldCFrame * a.CFrame:Inverse()
						break
					end
				end
			end
		end
	end
end

local function bake(key: string, bundleId: number): string
	local outfitId = outfitOf(bundleId)
	if not outfitId then return ("%s: bundle %d has no outfit"):format(key, bundleId) end

	local description = Players:GetHumanoidDescriptionFromOutfitId(outfitId)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	snapAccessories(model)

	-- ===== THE RIG HARDWARE HAS TO COME OFF, AND THIS IS THE BUG THAT PROVED IT =====
	--
	-- A bundle body arrives as a working R15 rig: 15 AnimationConstraints, 14 BallSocketConstraints,
	-- 19 NoCollisionConstraints, 52 Attachments, 15 WrapTargets, a FaceControls and a BodyColors --
	-- 99 instances on the entry skin alone. Every one of them is dead weight once SkinMesh welds the
	-- parts onto the player's own limbs, and together they break the one call the whole pipeline
	-- rests on: **`Model:PivotTo` moves ONLY the root part of a constrained, unanchored rig.**
	--
	-- Measured on a real PreviewRig through the shipped module: `SkinMesh.Apply` returned true, the
	-- SkinMesh folder held all 16 parts, and **15 of the 16 were still at the world origin** while
	-- UpperTorso alone stood on the character. On a player that is a floating torso and no head,
	-- arms or legs -- which is exactly what the owner reported seeing. Strip the hardware and the
	-- same call puts all 16 on the body: `stuck=0`, measured immediately after.
	--
	-- It also explains why 200 generated skins never hit this: they are plain bags of MeshParts with
	-- no constraints at all. Stripping makes a bundle structurally identical to one of them, which is
	-- the property the rest of the pipeline was written against.
	--
	-- ORDER MATTERS: this runs AFTER snapAccessories, because the snap reads the Attachments it
	-- destroys.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("LuaSourceContainer") or d:IsA("Sound")
			or d:IsA("Camera") or d.Name == "HumanoidRootPart"
			or d:IsA("Constraint") or d:IsA("JointInstance") or d:IsA("WrapTarget")
			or d:IsA("FaceControls") or d:IsA("BodyColors") or d:IsA("Attachment") then
			d:Destroy()
		end
	end
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	if parts == 0 then
		model:Destroy()
		return ("%s: bundle %d baked to an empty model"):format(key, bundleId)
	end

	local name = "SkinMesh_" .. key
	local old = folder:FindFirstChild(name)
	if old then old:Destroy() end
	model.Name = name
	model.Parent = folder

	local size = model:GetExtentsSize()
	return ("%s: %d parts, %.2f x %.2f x %.2f, bundle %d"):format(name, parts, size.X, size.Y, size.Z, bundleId)
end

local report = {}

-- Retired keys first, so a rebuild also takes away the bodies of the skins the wardrobe dropped.
-- Left behind they are 16 MeshParts each of a character nothing can wear or name.
for _, key in ipairs(GameConfig.RetiredVipKeys or {}) do
	local old = folder:FindFirstChild("SkinMesh_" .. key)
	if old then
		old:Destroy()
		table.insert(report, "removed SkinMesh_" .. key)
	end
end

-- RETRIED, BECAUSE THE CATALOG FAILS TRANSIENTLY AND A FAILED BAKE IS SILENT AFTERWARDS.
-- `GetHumanoidDescriptionFromOutfitId` returned an HTTP 500 for one of the nine on a run where the
-- other eight succeeded; the old model survives that (it is only destroyed once the new one is
-- built), so the folder still holds nine and nothing downstream complains -- the place just keeps
-- one skin at the previous build's state, which is precisely the kind of drift that gets blamed on
-- the next change instead of on this one. Three attempts with a pause, and the report says plainly
-- which attempt won.
for index, entry in ipairs(GameConfig.VipCharacters) do
	if index >= FIRST and index <= LAST and entry.bundleId then
		local ok, result
		for attempt = 1, 3 do
			ok, result = pcall(bake, entry.key, entry.bundleId)
			if ok then
				if attempt > 1 then result = result .. (" (attempt %d)"):format(attempt) end
				break
			end
			task.wait(2)
		end
		table.insert(report, ok and result or ("%s: ERROR after 3 attempts %s"):format(entry.key, tostring(result)))
	end
end

table.insert(report, ("SkinMeshes now holds %d models"):format(#folder:GetChildren()))
return table.concat(report, "\n")
