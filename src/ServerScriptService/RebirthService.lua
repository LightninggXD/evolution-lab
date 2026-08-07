local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)

local RebirthService = {}
RebirthService.OnRebirth = nil -- optional callback(player, data) set by ServerMain to avoid circular requires
-- callback(player), also set by ServerMain: teleports the body home. Separate from OnRebirth
-- because it must run AFTER the rebuild that one triggers -- see the call site.
RebirthService.OnReturnHome = nil

function RebirthService.CanRebirth(data)
	return data.StageIndex >= GameConfig.RebirthRequirementStageIndex
end

-- `tier` is which of the shrine's four statues was triggered (see RebirthShrine). It is optional:
-- the HUD's Rebirth panel has no statues in it and passes nothing, which means "cash in at the
-- highest tier I have earned" -- the behaviour this had before the shrine existed.
--
-- CHOOSING A LOWER TIER IS ALLOWED AND IS ALWAYS WORSE. The reward goes as tier^2, so rebirthing
-- at the Wolf when you could have reached The Absolute is a real (bad) decision rather than
-- something to block -- but it must be the player's decision, so a tier ABOVE what they have
-- earned is refused rather than silently clamped down to what they can afford.
function RebirthService.HandleRebirth(player, tier)
	local data = PlayerDataService.Get(player)
	if not data then return end

	if not RebirthService.CanRebirth(data) then
		local reqStage = GameConfig.Stages[GameConfig.RebirthRequirementStageIndex]
		Remotes.Notify:FireClient(player, { kind = "error", message = "Reach " .. reqStage.name .. " before you can Rebirth!" })
		return
	end

	local earnedTier = GameConfig.GetRebirthTier(data.StageIndex)
	-- tonumber + floor before anything else: this value reaches here straight off a RemoteEvent when
	-- the HUD fires it, so it can be a string, a table, or 2.5.
	local tierReached = math.floor(tonumber(tier) or earnedTier)
	-- NaN SURVIVES BOTH GUARDS BELOW, AND IT IS PERMANENT.
	--
	-- `Rebirth:FireServer(0/0)` reaches here as NaN. `NaN < 1` is false and `NaN > earnedTier` is
	-- false, so neither rejection fires; the shard reward comes back NaN, `data.EvolutionShards`
	-- becomes NaN, and a DataStore cannot serialise NaN -- so every save that player makes from
	-- that moment on throws, forever, swallowed by the pcall in PlayerDataService as a warning
	-- nobody reads. The account is dead and there is no symptom until they lose everything.
	--
	-- `n ~= n` is the only test for it: NaN is the one value that is not equal to itself.
	if tierReached ~= tierReached or tierReached < 1 then
		return
	end
	if tierReached > earnedTier then
		local reqStage = GameConfig.Stages[GameConfig.GetRebirthTierStageIndex(tierReached)]
		Remotes.Notify:FireClient(player, { kind = "error",
			message = ("Reach %s (Stage %d) to use this statue!"):format(reqStage.name, GameConfig.GetRebirthTierStageIndex(tierReached)) })
		return
	end

	-- The reward is the CHOSEN tier's, not the stage's: standing at stage 19 and triggering the Wolf
	-- statue pays tier 1, which is the point of having four of them.
	local shardsEarned = GameConfig.GetRebirthShardReward(GameConfig.GetRebirthTierStageIndex(tierReached), data.Rebirths)
	data.Rebirths += 1
	data.EvolutionShards += shardsEarned

	-- reset run-specific progress; Pets and EvolutionShards/Rebirths persist across rebirths
	data.DNA = 0
	data.XP = 0
	data.StageIndex = 1
	for key in pairs(data.Upgrades) do
		data.Upgrades[key] = 0
	end
	data.Mutations = {}
	data.UnlockedZones = { "Forest" }
	data.CurrentZone = "Forest"
	data.DefeatedBosses = {}

	-- THE COLLECTION IS THE RUN, AND THE RUN IS WHAT RESETS.
	--
	-- This used to keep `Characters` on the reasoning that a collection wiped by the mechanic
	-- designed to be repeated is not a collection. That was a defensible read of a different game:
	-- characters were pure skins then. They are the damage ladder now, worth up to +600% -- so
	-- carrying a full collection through a reset means a rebirthed player walks out of the shrine
	-- at stage 1 hitting harder than most of the zones they are about to re-clear, and the reset
	-- costs them nothing they can feel.
	--
	-- Re-collected from scratch instead, and paid for with permanent damage that stacks every run
	-- (GameConfig.GetRebirthDamageMult). The evolves hand the characters straight back in order, so
	-- the second climb is a faster version of the first rather than an empty one.
	data.Characters = {}
	data.EquippedCharacters = {}
	data.WornCharacter = nil

	-- ...EXCEPT THE FIRST ONE, WHICH IS NOT A REWARD, IT IS THE DEFAULT BODY.
	--
	-- A wiped collection leaves a player with nothing owned and nothing worn, so the Journal opens
	-- on a grid where no tile is selected and the character they are standing in belongs to no
	-- entry. Rank 1 is the plain starting look of stage 1; handing it back costs the collection
	-- nothing (it is the first thing the ordered drop would give anyway) and it means there is
	-- always a selected character. New saves get the same thing in ServerMain, for the same reason.
	local first = GameConfig.GetBaseCharacterForStage(1)
	if first then
		data.Characters[first.key] = true
		data.WornCharacter = first.key
	end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	-- SAVED IMMEDIATELY. A rebirth is the single most destructive thing a player can do to their
	-- own save on purpose, and it is irreversible: if the server drops before the 60-second autosave
	-- they lose the climb AND the reward, which is the one loss no player forgives.
	PlayerDataService.Save(player)
	Remotes.Notify:FireClient(player, {
		kind = "rebirth",
		rebirths = data.Rebirths,
		shards = shardsEarned,
		tier = tierReached,
		-- what it actually bought, so the reward is a number the player can see rather than a
		-- counter going up by one
		damagePct = data.Rebirths * GameConfig.RebirthDamagePct,
	})

	if RebirthService.OnRebirth then
		RebirthService.OnRebirth(player, data)
	end

	-- AND PUT THEM BACK IN FOREST. `CurrentZone` and `UnlockedZones` were reset above, but those
	-- are save fields -- nothing moves the body. A player rebirthing at the shrine in zone 12 was
	-- left standing in zone 12 at stage 1, on ground whose creatures hit for x8.4, with a zone list
	-- that no longer contains the zone they are in. Fired last, after OnRebirth has rebuilt the
	-- body at its new size, so the teleport moves the finished character rather than one mid-tween.
	if RebirthService.OnReturnHome then
		RebirthService.OnReturnHome(player)
	end
end

function RebirthService.Init()
	Remotes.Rebirth.OnServerEvent:Connect(function(player, tier)
		RebirthService.HandleRebirth(player, tier)
	end)
end

return RebirthService
