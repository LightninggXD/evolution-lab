--[[
	PetFollowService - spawns a world model for each of a player's equipped pets.

	Split of responsibility, and it matters: this service only creates and destroys the rigs and
	stamps them with who owns them. It never moves them. The per-frame trailing is done by
	StarterPlayerScripts.PetFollowClient on every client, because a server that CFrames anchored
	parts every Heartbeat replicates at a throttled rate and the pets visibly stutter for
	everyone. Moving them locally instead costs no bandwidth and every player still sees every
	other player's pets, since the models themselves are replicated normally.

	Pets live in workspace.EquippedPets, never inside the character: nothing here can affect
	Humanoid physics or be destroyed by a respawn.

	The equipped list is polled rather than event-driven. PetService mutates the data table and
	calls PushToClient; there is no server-side "equipped changed" signal to subscribe to, and
	adding one would couple the two services. A half-second poll comparing a joined id string is
	cheap and cannot miss an edit.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)
local PlayerDataService = require(script.Parent.PlayerDataService)

local PetFollowService = {}

local POLL_INTERVAL = 0.5
-- Pets are sized off their owner, not off a constant. The player's own body scales from 1x at Cell
-- to 9x at The Absolute (EvolutionVisuals drives it from GameConfig.Stages), so any fixed pet size
-- is either a speck at the end of the game or a monster at the start of it -- at Human, 3.8x, the
-- old 0.72 rig came up to about the player's ankle, which is the complaint this fixes.
--
-- sqrt rather than a straight multiply: the pet keeps growing with its owner without matching them
-- stride for stride. 0.95 beside a Cell (already bigger than the old flat 0.72), ~2.9 beside The
-- Absolute -- always a pet trotting alongside, never a second player.
local PET_SCALE = 0.95

-- R15 body scale lives as NumberValue children of the Humanoid, not as properties -- see the note
-- in EvolutionVisuals, which is what sets them.
local function ownerScaleOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local value = humanoid and humanoid:FindFirstChild("BodyHeightScale")
	return (value and value.Value) or 1
end

local function petScaleFor(ownerScale)
	return PET_SCALE * math.sqrt(ownerScale)
end

local petsFolder = workspace:FindFirstChild("EquippedPets")
if not petsFolder then
	petsFolder = Instance.new("Folder")
	petsFolder.Name = "EquippedPets"
	petsFolder.Parent = workspace
end

-- player.UserId -> { signature = "key:tier|...", folder = Folder }
local active = {}

local function clearFor(userId)
	local entry = active[userId]
	if entry then
		if entry.folder.Parent then entry.folder:Destroy() end
		active[userId] = nil
	end
	-- also catch a folder left behind by a crashed rebuild
	local stale = petsFolder:FindFirstChild(tostring(userId))
	if stale then stale:Destroy() end
end

-- the tier can change under a fixed id set (fusing), so fold it into the signature -- and so does
-- the owner's body scale, since the rigs are built to match it and an evolution has to rebuild
-- them. Rounded to a tenth: EvolutionVisuals *tweens* the scale over 0.6s, and comparing the raw
-- value would rebuild the whole set on every poll for the length of the tween.
local function signatureOf(player, data)
	local parts = {}
	for _, id in ipairs(data.EquippedPetIds or {}) do
		for _, p in ipairs(data.Pets or {}) do
			if p.id == id then
				table.insert(parts, p.key .. ":" .. p.tier)
				break
			end
		end
	end
	-- THE WORN MUTATION IS NO LONGER IN THE SIGNATURE (34.40). It was here because the rigs carried
	-- the owner's aura (12.5) and a rebuild was the only thing that put one on -- without it a splice
	-- aura'd the body and left the pets bare. The pets carry no aura now, so the only thing the term
	-- still did was tear down and rebuild the whole row every time the owner changed mutation.
	return table.concat(parts, "|")
		.. ("@%.1f"):format(ownerScaleOf(player))
end

local function rebuild(player, data)
	clearFor(player.UserId)

	local equipped = {}
	for _, id in ipairs(data.EquippedPetIds or {}) do
		for _, p in ipairs(data.Pets or {}) do
			if p.id == id then
				table.insert(equipped, p)
				break
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder:SetAttribute("OwnerUserId", player.UserId)

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local ownerScale = ownerScaleOf(player)
	local petScale = petScaleFor(ownerScale)

	for slot, saved in ipairs(equipped) do
		local def = GameConfig.GetPetDef(saved.key)
		if def then
			-- the nameplate has to stay legible from a big player's eye height too, hence the
			-- scale term on its draw distance
			-- `fx` asks for the mesh species' own sparkle rig, which the library parks by default:
			-- these are the pets a player actually looks at, and there are at most a handful of them
			-- per player -- unlike the sixty standing on egg podiums across the strip.
			local model, root = PetModel.Build(def, saved.tier, { scale = petScale, plateDistance = 34 + 30 * ownerScale, fx = true })
			model:SetAttribute("OwnerUserId", player.UserId)
			model:SetAttribute("Slot", slot)
			model:SetAttribute("SlotCount", #equipped)
			-- the client spaces the row off this instead of re-deriving the scale from the parts
			model:SetAttribute("PetScale", petScale)
			-- spawn it where it belongs rather than at the origin, so a joining client never
			-- sees a pet streak in from (0, 0, 0) on its first frame
			if hrp then
				root.CFrame = hrp.CFrame * CFrame.new((slot - (#equipped + 1) / 2) * 5 * petScale, 0, 5 * ownerScale)
			end
			-- NO MUTATION AURA ON THE FOLLOWERS (34.40, owner's call). Every pet used to get a full
			-- copy of the owner's aura, sized off the rig rather than the body. Measured on her save
			-- with 8 pets equipped: 8 enabled emitters on the character and 68 across the row, i.e.
			-- the same effect drawn NINE times. Each `Windspin` particle lives 1s at speed 10.4 and
			-- grows to 8.31 studs, so the row laid a continuous golden ribbon across the middle of
			-- the frame -- the shopfronts, the arena door and the NPC stands were all behind it.
			--
			-- The part that made it a bug rather than a preference: the density is a function of the
			-- SLOT COUNT, so it got worse the further a player progressed. An aura is a reward; a
			-- reward that hides the game it is a reward in is priced backwards.
			--
			-- The aura stays on the OWNER's body, which is where it reads as theirs. Pets keep their
			-- own species sparkles (`fx` above) -- those are per-rig and small, and they are not
			-- what the capture showed.
			model.Parent = folder
		end
	end

	folder.Parent = petsFolder
	active[player.UserId] = { signature = signatureOf(player, data), folder = folder }
end

function PetFollowService.Init()
	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataService.Get(player)
				if data then
					local sig = signatureOf(player, data)
					local entry = active[player.UserId]
					if not entry or entry.signature ~= sig or not entry.folder.Parent then
						rebuild(player, data)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearFor(player.UserId)
	end)
end

return PetFollowService
