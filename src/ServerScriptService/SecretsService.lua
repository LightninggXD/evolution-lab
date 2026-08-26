-- ===== SECRETS: A HIDDEN SPOT ON THE MAP THAT PAYS A MUTATION =====
--
-- ONE TOUCH PART PER ENTRY IN `GameConfig.Secrets`, PARENTED UNDER `workspace.Map.Secrets`, and the
-- reward is granted exactly once per save (`data.FoundSecrets[id]`).
--
-- 👤 THIS FILE WAS RESCUED FROM STUDIO ON 2026-08-25. It existed only inside the running Studio
-- place -- no file on disk, no commit, no roadmap row, no HANDOFF-LOG entry, no board step -- along
-- with its three wiring edits (`GameConfig.Secrets` in Zones, `FoundSecrets` in PlayerDataService,
-- the require + Init in ServerMain). Everything below the rescue line is the audit's repair; the
-- shape of the feature is unchanged. See ROADMAP row 32.26.

local SecretsService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

-- Bump this when a secret's OFFSET changes: the holder is rebuilt from scratch on a mismatch, and
-- a trigger that already exists is never repositioned, so without a bump an edited offset is a
-- no-op on any world that has already booted once.
--   3 -- 33.19: the touch point moved off `offset` onto its own `triggerOffset`
local SECRETS_VERSION = 3

local TRIGGER_SIZE = Vector3.new(12, 12, 12)

-- ===== THE REWARD IS NOT THE SAVE FIELD =====
--
-- `SplicerService` says it in its own words at `applyMutation`: *"The ONE place a mutation is
-- written onto a save ... two writers is how two rules drift apart."* The rescued version wrote
-- `data.SplicerMutation` directly and stopped there, which is the exact defect shape the splicer's
-- `SetWorn` comment block was written to warn about -- **the attribute is the replication channel,
-- not the save.** Writing the field alone leaves the old aura burning on the body for the rest of
-- the session, pays none of the mutation's DNA or speed bonus, and never redraws the Auras panel.
--
-- So the collection entry is granted here (that is this feature's own business) and the WEARING is
-- handed to the splicer's public equip path, which owns the attribute, `RefreshBonuses` and
-- `PushToClient` and will keep owning them when those three lines change again.
local function grantMutation(player, data, mutationName)
	local mut = GameConfig.GetMutationByName(mutationName)
	if not mut then
		warn(("[SecretsService] unknown mutation %q -- nothing granted"):format(tostring(mutationName)))
		return false
	end

	data.SplicerFound = data.SplicerFound or {}
	data.SplicerFound[mutationName] = (data.SplicerFound[mutationName] or 0) + 1

	-- Best-kept-wins, the same rule the roll uses: index order IS rarity order in
	-- `GameConfig.Mutations`. Godly is index 7 of 7 so today this never refuses -- it is here so a
	-- future secret paying a lesser aura cannot silently strip a better one off the player.
	local newIdx, curIdx = 0, 0
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == mutationName then newIdx = i end
		if data.SplicerMutation and m.name == data.SplicerMutation then curIdx = i end
	end
	if newIdx > curIdx then
		local SplicerService = require(script.Parent.SplicerService)
		SplicerService.HandleEquipMutation(player, mutationName)
	else
		-- Not worn, but it IS collected, so the panel still has to hear about it.
		PlayerDataService.PushToClient(player)
	end
	return true
end

-- ===== A TRIGGER INSIDE THE ROCK IS AN INVISIBLE NO-OP, SO IT SAYS SO =====
--
-- The rescued `ForestWaterfall` offset was the waterfall model's BOUNDING-BOX CENTRE, measured to
-- 0.1 studs -- i.e. the middle of a 217 x 234 x 307 prop, buried in five of its own 80-stud rock
-- parts. Nothing can ever touch it. That failure is completely silent otherwise: the part is
-- built, the Touched handler is connected, the boot line is cheerful, and the secret simply does
-- not exist. One overlap test at build time turns it into a line in the log.
--
-- THE TEST IS BODY-SIZED, NOT TRIGGER-SIZED, and that is the whole difference between a guard and
-- a false alarm. A 12-stud trigger sitting honestly on the ground overlaps the floor it stands on
-- -- measured, the older `(0, 5, -80)` offset overlaps **4** solid parts (the village union, the
-- WorldShell floor, MainPart) and is perfectly reachable. Asking instead whether a HUMANOID fits
-- at the centre separates them cleanly: that same spot reports **0**, and the waterfall centroid
-- reports **2** eighty-stud rock parts.
local BODY_BOX = Vector3.new(4, 6, 4)

local function reportBlocked(secret, trigger)
	local hits = workspace:GetPartBoundsInBox(trigger.CFrame, BODY_BOX)
	local solid, blame = 0, {}
	for _, part in ipairs(hits) do
		if part ~= trigger and part.CanCollide then
			solid += 1
			if #blame < 5 then table.insert(blame, part:GetFullName()) end
		end
	end
	if solid > 0 then
		-- AND IT NAMES THEM. The first version of this warning reported only a count, and when it
		-- fired for real (33.19) the count said nothing about which of two thousand nearby props
		-- was in the way -- the answer, `GrottoPlinth`, was reached by replaying the box test by
		-- hand. A guard that has to be re-derived to be acted on is half a guard.
		warn(("[SecretsService] %s IS UNREACHABLE: its trigger at %s overlaps %d solid part(s) -- %s. "
			.. "Nothing can touch it -- move triggerOffset to a spot a player can stand in.")
			:format(secret.id, tostring(trigger.Position), solid, table.concat(blame, ", ")))
	end
	return solid
end

function SecretsService.Init()
	local map = workspace:FindFirstChild("Map")
	if not map then return end

	local holder = map:FindFirstChild("Secrets")
	if holder and holder:GetAttribute("SecretsVersion") ~= SECRETS_VERSION then
		holder:Destroy()
		holder = nil
	end

	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "Secrets"
		holder:SetAttribute("SecretsVersion", SECRETS_VERSION)
		holder.Parent = map
	end

	local built, blocked = 0, 0
	for _, secret in ipairs(GameConfig.Secrets or {}) do
		local zoneIndex = GameConfig.GetZoneIndex(secret.zoneKey)
		local zone = GameConfig.Zones[zoneIndex]
		if not zone then
			warn(("[SecretsService] %s names zone %q, which does not exist"):format(secret.id, tostring(secret.zoneKey)))
			continue
		end

		local centre = Vector3.new(zone.offset, 0, 0)

		-- WHERE A PLAYER WALKS, NOT WHERE THE ROOM IS BUILT. `MapWaterfall` measures the whole
		-- grotto -- walls, mouth, floor, plinth -- off `secret.offset`, so that number cannot be
		-- moved to make the trigger reachable without moving the cave with it. `triggerOffset` is
		-- the second decision, and it defaults to the first for any secret that has no scenery
		-- built around it. See the block over `GameConfig.Secrets`.
		local touchAt = secret.triggerOffset or secret.offset or Vector3.new(0, 0, 0)

		local triggerName = "Secret_" .. secret.id
		local trigger = holder:FindFirstChild(triggerName)
		if not trigger then
			trigger = Instance.new("Part")
			trigger.Name = triggerName
			trigger.Size = TRIGGER_SIZE
			trigger.Position = centre + touchAt
			trigger.Anchored = true
			trigger.CanCollide = false
			-- Invisible on purpose -- the point is a hidden passage, not a marked one.
			trigger.Transparency = 1
			trigger.Parent = holder
		end
		built += 1
		blocked += (reportBlocked(secret, trigger) > 0) and 1 or 0

		local db = {}
		trigger.Touched:Connect(function(hit)
			local character = hit.Parent
			if not character then return end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then return end

			if db[player.UserId] then return end
			db[player.UserId] = true
			task.delay(1, function() db[player.UserId] = nil end)

			local data = PlayerDataService.Get(player)
			if not data or not data.FoundSecrets or data.FoundSecrets[secret.id] then return end
			data.FoundSecrets[secret.id] = true

			local paid = true
			if secret.rewardType == "mutation" then
				paid = grantMutation(player, data, secret.rewardName)
			else
				warn(("[SecretsService] %s has rewardType %q, which nothing pays"):format(secret.id, tostring(secret.rewardType)))
				paid = false
			end
			if not paid then
				-- Do not burn the find on a reward that was never handed over.
				data.FoundSecrets[secret.id] = nil
				return
			end

			-- ===== THE TOAST IS A TABLE, AND THAT IS THE WHOLE CONTRACT =====
			-- `Remotes.Notify` takes ONE argument and every handler in the game opens with
			-- `if typeof(payload) ~= "table" or payload.kind ~= ... then return end`. The rescued
			-- version fired four positional values (title, body, icon, colour); indexing a string
			-- for `.kind` returns nil rather than erroring, so it was dropped in silence by every
			-- listener and the player was told nothing at all.
			local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if Remotes and Remotes:FindFirstChild("Notify") then
				Remotes.Notify:FireClient(player, {
					kind = "reward",
					message = ("\u{2728} SECRET FOUND! The %s aura is yours."):format(secret.rewardName),
				})
			end
		end)
	end

	print(("[SecretsService] %d secret(s) placed%s")
		:format(built, blocked > 0 and (", %d UNREACHABLE -- see the warnings above"):format(blocked) or ""))
end

return SecretsService
