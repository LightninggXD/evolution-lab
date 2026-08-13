local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)

local RebirthService = {}
RebirthService.OnRebirth = nil -- optional callback(player, data) set by ServerMain to avoid circular requires
-- callback(player), also set by ServerMain: teleports the body home. Separate from OnRebirth
-- because it must run AFTER the rebuild that one triggers -- see the call site.
RebirthService.OnReturnHome = nil

-- One question, one answer, and it lives in GameConfig so the shrine, the HUD and this file cannot
-- drift apart about which milestone is live. See the REBIRTH IS A LADDER block there.
function RebirthService.CanRebirth(data)
	return (GameConfig.CanRebirthNow(data))
end

-- `tier` is which of the shrine's four statues was triggered (see RebirthShrine). It is optional:
-- the HUD's Rebirth panel has no statues in it and passes nothing.
--
-- THERE IS NO LONGER A CHOICE OF TIER, AND THAT IS THE POINT OF THE REWRITE. The four statues used
-- to be four prices for the same repeatable transaction -- you could cash in at the Wolf forever,
-- and the reward went as tier^2, so choosing was a trap the UI had to warn about. They are four
-- MILESTONES now, spent strictly in order and never again: the Wolf at stage 5 is the first rebirth
-- and only the first, and once it is spent the ladder points at stage 10.
--
-- So `tier` stops being a choice and becomes an assertion the client is making about which statue
-- it touched. It is checked against the one milestone that is actually live and refused otherwise,
-- rather than clamped -- a client that asks for the wrong one is either stale or lying, and both
-- deserve the same answer.
function RebirthService.HandleRebirth(player, tier)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local nextTier = GameConfig.GetNextRebirthTier(data)
	if not nextTier then
		Remotes.Notify:FireClient(player, { kind = "error",
			message = ("You have completed all %d Rebirths -- there are no more."):format(GameConfig.MaxRebirths) })
		return
	end

	local reqStageIndex = GameConfig.GetRebirthTierStageIndex(nextTier)
	if data.StageIndex < reqStageIndex then
		local reqStage = GameConfig.Stages[reqStageIndex]
		Remotes.Notify:FireClient(player, { kind = "error",
			message = ("Reach %s (Stage %d) to unlock Rebirth %d!"):format(reqStage.name, reqStageIndex, nextTier) })
		return
	end

	-- THE CLIENT'S CLAIM IS CHECKED, NOT TRUSTED AND NOT CLAMPED.
	--
	-- `tonumber` + `floor` first, because this arrives straight off a RemoteEvent and can be a
	-- string, a table or 2.5. Then the NaN test, which is still load-bearing and still the only one
	-- that works: `Rebirth:FireServer(0/0)` gives a value where every comparison is false, so it slid
	-- past the old guards, and a NaN written into the save makes every future DataStore write throw
	-- forever -- swallowed by a pcall as a warning nobody reads. The account dies silently.
	-- `n ~= n` is the only test for it: NaN is the one value not equal to itself.
	--
	-- nil is allowed and means "the HUD button, which has no statue to name".
	if tier ~= nil then
		local claimed = tonumber(tier)
		claimed = claimed and math.floor(claimed) or nil
		if claimed ~= claimed then return end -- NaN
		if claimed ~= nextTier then
			local reqStage = GameConfig.Stages[reqStageIndex]
			Remotes.Notify:FireClient(player, { kind = "error",
				message = ("That milestone is spent. Your next Rebirth is at %s (Stage %d)."):format(reqStage.name, reqStageIndex) })
			return
		end
	end

	-- NO SHARDS. A rebirth used to pay Evolution Shards, worth +2% income each; shards are a rare
	-- drop with the wheel as their only sink now, and a currency that is spent cannot also be the
	-- permanent reward for the hardest thing in the game. What it pays is permanent damage AND
	-- permanent income, both read straight off the counter incremented on the next line --
	-- see GetRebirthDamageMult and GetRebirthIncomeMult.
	local tierReached = nextTier
	data.Rebirths += 1

	-- reset run-specific progress; Pets and EvolutionShards/Rebirths persist across rebirths
	data.DNA = 0
	data.XP = 0
	data.StageIndex = 1
	for key in pairs(data.Upgrades) do
		data.Upgrades[key] = 0
	end
	-- THE SPLICER MUTATION SURVIVES A REBIRTH, and so does `SplicerRolls` (Phase 12). They are
	-- one decision, not two: the roll ramp is priced off the lifetime counter, so wiping the
	-- mutation while keeping the counter would take away something the player paid DNA for and
	-- price its replacement at the cap. The upgrades reset above is where a run's power goes.
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
		tier = tierReached,
		-- WHAT IT BOUGHT, as the two multipliers the player now permanently carries rather than as a
		-- counter going up by one. Both are totals, not deltas: after a reset that wiped the stage,
		-- the zones and the whole skin collection, "you are now x3.5 income and x3.5 damage forever"
		-- is the only framing under which the trade reads as a gain.
		damageMult = GameConfig.GetRebirthDamageMult(data),
		incomeMult = GameConfig.GetRebirthIncomeMult(data),
		-- and where the ladder points next, so the reset ends by naming its own sequel
		nextTier = GameConfig.GetNextRebirthTier(data),
		nextStageIndex = GameConfig.GetNextRebirthStage(data),
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
