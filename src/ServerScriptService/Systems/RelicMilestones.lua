-- RelicMilestones -- the before/after pair that turns a relic grant into "a set was COMPLETED".
--
-- ===== WHY A MODULE AT ALL, FOR ONE TELEMETRY EVENT (30.8) =====
--
-- `RelicSetCompleted` is the one beat in 30.8 that is not a single call site. A collection relic
-- reaches a save from THREE faucets and the answer has to be the same from all three, or the
-- number on the dashboard is "sets completed by the routes somebody remembered to instrument":
--
--   * an adventure roll        -- `AdventureReward.PayFinish`, one or two rolls per finish
--   * a relic chest            -- `RelicService.HandleOpenChest`, the collection half of the grant
--   * a trade                  -- `TradeService`'s commit, on the RECEIVING side
--
-- ===== WHY IT IS NOT INSIDE `GameConfig.AddSetRelic`, WHERE IT WOULD BE SHORTER =====
--
-- Two reasons, either of which is enough. `GameConfig` is a SHARED module -- MainUI and every panel
-- require it -- and it cannot see `Telemetry`, which is `ServerScriptService`-only; a require the
-- other way is a client trying to reach the server's tree, which fails at load. And `AddSetRelic`
-- is not only a faucet: `PlayerDataService`'s migration path calls it too, and a save being healed
-- on load would report a completion the player did not just earn.
--
-- The trade's receive path does not call `AddSetRelic` at all (it must not -- see the note over
-- `moveIn`: that function pays dust, which in a trade is currency minting), so a hook inside it
-- would have missed that faucet anyway.
--
-- ===== WHY BEFORE/AFTER AND NOT A SAVE FLAG =====
--
-- The obvious shape is `data.RelicSetsAnnounced = { Forest = true }`, and it buys nothing here. The
-- answer is already derivable from `data.SetRelics` in O(relics held) -- `CountCompletedRelicSets`
-- was written that way for the DNA path, which asks it on every click -- so a flag would be a new
-- save field, a new migration, and a second thing that can disagree with the collection it
-- describes. The count is taken a few lines before the grant instead, in the same function, with
-- nothing between them that yields.
--
-- **A SET NEVER UN-COMPLETES**, which is what makes a plain count safe. Only SPARES are tradeable
-- (`copies - 1`, enforced twice in `TradeService`), so a giver's set stays complete by construction
-- and `after < before` cannot happen. Nothing else removes a collection relic: merging spends
-- `RelicDust`, releasing is pets-only, and a rebirth does not touch `SetRelics`.
--
-- ===== THE VALUE IS THE RUNNING TOTAL, ON PURPOSE =====
--
-- Roblox graphs a custom event's value as a DISTRIBUTION. Sending `1` every time would make the
-- chart a bar at 1 and throw away the only interesting question -- how deep does a collector get --
-- so the n-th set a player completes is sent as `n`. Two sets completed by one grant (possible: a
-- finish under par rolls twice) therefore arrive as two events, `n` and `n + 1`, rather than as one
-- event that hides the second.

local RelicMilestones = {}

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)

--- How many relic sets this save has finished. Take it BEFORE the grant.
function RelicMilestones.Count(data)
	if type(data) ~= "table" then return 0 end
	return GameConfig.CountCompletedRelicSets(data)
end

--- Fires one `RelicSetCompleted` per set finished since `before`, and returns how many that was.
--- Safe to call with a nil player (a probe driving the grant path) and with an unchanged count --
--- both are the no-op case, which is the overwhelmingly common one.
function RelicMilestones.Report(player, data, before)
	local after = RelicMilestones.Count(data)
	before = tonumber(before) or after
	if after <= before then return 0 end

	-- Lazy, like every other caller of this file: `Telemetry` requires `GameConfig` and the whole
	-- economy table, and this module is required by three services that already hold both.
	local Telemetry = require(script.Parent.Parent.Telemetry)
	for n = before + 1, after do
		Telemetry.Custom(player, "RelicSetCompleted", n)
	end
	return after - before
end

return RelicMilestones
