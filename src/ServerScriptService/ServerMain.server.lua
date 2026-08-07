local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local DNAService = require(ServerScriptService.DNAService)
local ZoneBuilder = require(ServerScriptService.ZoneBuilder)
local ZoneService = require(ServerScriptService.ZoneService)
local EvolutionVisuals = require(ServerScriptService.Systems.EvolutionVisuals)
local VFXService = require(ServerScriptService.Systems.VFXService)
local PetService = require(ServerScriptService.PetService)
local PetFollowService = require(ServerScriptService.PetFollowService)
local MachineService = require(ServerScriptService.MachineService)
local CreatureService = require(ServerScriptService.CreatureService)
local BossService = require(ServerScriptService.BossService)
local RebirthService = require(ServerScriptService.RebirthService)
local RebirthShrine = require(ServerScriptService.RebirthShrine)
local RewardService = require(ServerScriptService.RewardService)
local PotionService = require(ServerScriptService.PotionService)
local PassService = require(ServerScriptService.PassService)
local RobuxShopService = require(ServerScriptService.RobuxShopService)
local PlaytimeGiftService = require(ServerScriptService.PlaytimeGiftService)
local SeasonPassService = require(ServerScriptService.SeasonPassService)

-- ===== STREAMING =====
-- The two radii that decide how much world a client is holding. Roblox's defaults (min 64,
-- target 1024) are sized for a place you walk around; this one is a 36,000-stud strip of 1250 x
-- 1150 platforms, and at 64 studs of guaranteed detail a player standing still can watch the far
-- half of their own zone leave.
--
-- These may be read-only outside Studio's Properties panel depending on the client version, which
-- is why this is guarded and noisy rather than assumed: if the warning below ever fires, set them
-- by hand on Workspace (StreamingMinRadius 512, StreamingTargetRadius 3000, StreamingIntegrity
-- Mode PauseOutsideLoadedArea) and this block goes quiet on its own.
do
	local wanted = {
		StreamingMinRadius = 512,
		StreamingTargetRadius = 3000,
	}
	for prop, value in pairs(wanted) do
		local ok = pcall(function()
			workspace[prop] = value
		end)
		if not ok then
			warn(("[Streaming] could not set workspace.%s = %d from a script -- set it in the Properties panel")
				:format(prop, value))
		end
	end
	-- Stops the character being simulated into a region the client has not got yet, which is the
	-- other half of "I fell through the world after a teleport".
	pcall(function()
		workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.PauseOutsideLoadedArea
	end)
end

-- World geometry first, and before anyone can join: CreatureService and BossService place their
-- spawns relative to the zone platforms, and EnsureSpawn has to move the SpawnLocation off the
-- Forest shop footprint. Build() is also what trips the BUILD_VERSION guard that regenerates
-- zone geometry left over from an older version of this file.
ZoneBuilder.Build()

PlayerDataService.Init()
DNAService.Init()
ZoneService.Init()
EvolutionVisuals.Init()
-- before BossService: it owns the proximity gate the boss auras register themselves with, and
-- Init() wipes the previous run's ZoneVFX folder
VFXService.Init()
PetService.Init()
PetFollowService.Init()
MachineService.Init()
CreatureService.Init()
BossService.Init()
RebirthService.Init()
-- after RebirthService (it wires each statue's prompt straight into HandleRebirth) and after
-- ZoneBuilder.Build() above, which is what puts the Forest decor the plaza has to clear back
RebirthShrine.Init()
RewardService.Init()
PotionService.Init()
-- before RobuxShopService: both take a Robux purchase path, and PassService owns the one that has
-- to be answered on join (a pass is permanent and is read by the stat functions on the first click,
-- where a developer product is a one-off receipt that can arrive whenever)
PassService.Init()
RobuxShopService.Init()
PlaytimeGiftService.Init()
SeasonPassService.Init()

-- Hook evolution -> zone unlock checks + visual update (kept out of DNAService to avoid circular requires)
DNAService.OnEvolve = function(player, data)
	ZoneService.CheckUnlocks(player, data)
	EvolutionVisuals.ApplyStage(player, data.StageIndex, { animate = true, burst = true })
end

-- Stage Mastery raises walk speed and max health, which live on the Humanoid -- push them onto
-- the live character the moment one is bought instead of waiting for the next respawn.
DNAService.OnMasteryChanged = function(player, data)
	EvolutionVisuals.RefreshBonuses(player, data)
end

-- The 2x Speed pass lands on the Humanoid too, and it can arrive at any point in a session: on the
-- join refresh, on a purchase, or on a background re-check that finally got an answer out of the
-- ownership API. Same treatment as Stage Mastery above, for the same reason -- otherwise the player
-- pays for speed and does not move any faster until they next die.
PassService.OnPassesChanged = function(player, data)
	EvolutionVisuals.RefreshBonuses(player, data)
end

-- Wearing a different character from the Journal. The body is rebuilt rather than recoloured: the
-- character's colour is what StageCostume paints every shell and every detail with, and there is no
-- cheaper way to re-run that than the build itself. Not animated -- nothing is changing size, and a
-- 0.6s scale tween on a costume swap would read as a second evolve.
DNAService.OnCharacterChanged = function(player, data)
	EvolutionVisuals.ApplyStage(player, data.StageIndex, { animate = false, burst = false })
end

-- Rebirth resets stage/zones, so re-run the same unlock + visual reset logic as evolving does
RebirthService.OnRebirth = function(player, data)
	ZoneService.CheckUnlocks(player, data)
	EvolutionVisuals.ApplyStage(player, data.StageIndex, { animate = true, burst = true })
end

-- The body, not just the save. RebirthService resets CurrentZone/UnlockedZones to Forest, but a
-- player who triggered the shrine in zone 12 was left STANDING in zone 12 at stage 1 -- on ground
-- whose creatures hit for x8.4, in a zone their own unlock list no longer contains. Called last,
-- after OnRebirth above has rebuilt the body at its new size, so the teleport moves a finished
-- character rather than one halfway through a 0.6s scale tween.
RebirthService.OnReturnHome = function(player)
	task.delay(0.8, function()
		if player.Parent then
			ZoneService.ReturnToCurrentZone(player)
		end
	end)
end

-- Check zone unlocks for returning players once their data has loaded
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local data
		repeat
			task.wait(0.2)
			data = PlayerDataService.Get(player)
		until data or not player.Parent
		if data then
			ZoneService.CheckUnlocks(player, data)
			-- A save from before the Journal existed has an empty collection and a stage index well
			-- past 1, so it would show a locked grid until the player next evolved -- and a player at
			-- stage 20 never evolves again. One roll for the stage they are actually standing at, and
			-- only when they own nothing at all, so it can never top up an ordinary collection.
			-- THERE IS ALWAYS A SELECTED CHARACTER. Rank 1 is not a reward, it is the default body --
			-- without it the Journal opens on a grid with no tile selected and the player is standing
			-- in a look that belongs to no entry. Granted directly rather than through RollCharacter
			-- so it makes no noise: this is the starting state, not a find. Rebirth does the same thing
			-- at its own reset; see RebirthService.
			data.Characters = data.Characters or {}
			local first = GameConfig.GetBaseCharacterForStage(1)
			if first and not data.Characters[first.key] then
				data.Characters[first.key] = true
				PlayerDataService.PushToClient(player)
			end
			if data.WornCharacter == nil and first then
				data.WornCharacter = first.key
				PlayerDataService.PushToClient(player)
			end
		end
	end)
end)

print("[Evolution Lab Tycoon] Server systems initialized.")
