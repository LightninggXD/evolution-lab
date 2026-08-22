-- TradePolicy -- the one place that asks Roblox whether a given player is allowed to trade at all.
--
-- ===== WHY THIS EXISTS, AND WHY IT IS NOT OPTIONAL (30.7) =====
--
-- `PolicyService:GetPolicyInfoForPlayerAsync` returns, among other things, `IsPaidItemTradingAllowed`
-- -- false for players whose account or region is not permitted to exchange items that were paid
-- for. Roblox requires the check; it is not a nicety, and a game that trades without it is trading
-- on behalf of players who are not allowed to. It gates the WHOLE window rather than only the relic
-- lines 30.7 adds, because a pet comes out of an egg that can be bought with Robux.
--
-- ===== IT IS A CACHE BECAUSE THE CALL IS A WEB REQUEST =====
--
-- `GetPolicyInfoForPlayerAsync` yields and can throw. Calling it from `TradeService.Request` would
-- put a network round trip in front of every press of a button, and -- worse -- a yield in a
-- function whose first act is to look up "is this player already in a trade": two presses could
-- both pass that test while the first was still waiting. So it is asked ONCE at join and answered
-- from memory afterwards.
--
-- ===== AN UNKNOWN ANSWER IS A NO, AND IT IS ALSO NOT PERMANENT =====
--
-- If the call fails there are two wrong things to do. Treating unknown as "allowed" trades on
-- behalf of somebody who may not be permitted to, which is the failure this check exists to
-- prevent. Treating unknown as a permanent "denied" bricks the feature for a whole session on one
-- transient web error. So: unknown refuses THIS request, and the next request tries the call again
-- -- the player presses the button a second time and it works, which is the mildest possible way
-- for a network blip to show up.
--
-- The retry is bounded by `RETRY_COOLDOWN` so a player holding the button down cannot turn a
-- refusal into a request flood at Roblox.
--
-- ===== AND STUDIO'S TEST PLAYERS ARE LET THROUGH, ON PURPOSE AND NARROWLY =====
--
-- `PolicyService` takes a **Player**, so a userId with no Player object cannot be answered at all.
-- The only way one reaches this module is a test driving `TradeService` against synthetic parties
-- planted in `PlayerDataService.Cache` -- the technique 30.5 used, and the only way the commit path
-- can be exercised without moving a real player's goods into a real player's save. Refusing there
-- would make the dangerous half of trading untestable while proving nothing about the real half,
-- which is the argument `TradeService.withinReach` already makes about two players with no
-- characters.
--
-- The carve-out is **negative userIds only**, because that is what it is for: Studio's test players
-- are -1 and -2 (see the two-client note), synthetic parties are numbered from -101, and no real
-- Roblox account has a negative id. A POSITIVE userId with no Player is still refused -- which is
-- also how the refusal branch gets exercised by a test at all.
--
-- It is not a hole in the gate either way. In production `TradeService.Request` has already refused
-- anybody with no `PlayerDataService.Cache` entry two guards earlier, and a userId with no Player
-- has no cache entry: both sides of a real trade always resolve to a Player, and both are asked.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local TradePolicy = {}

-- [userId] = true / false. A key that is absent has never been answered; a key that is `false` was
-- answered, by Roblox, with a no.
local allowed = {}
-- [userId] = os.clock() of the last attempt that FAILED, so a retry is not a flood
local lastTry = {}
local RETRY_COOLDOWN = 5

TradePolicy.Refusal = "Trading is not available on your account"
TradePolicy.Unknown = "Trading is unavailable right now -- try again"

-- Returns true/false, or nil when Roblox could not be reached. `nil` and `false` are deliberately
-- different: one is "ask again", the other is "stop asking".
local function fetch(player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok or type(info) ~= "table" then return nil end
	-- Present and false is a no. ABSENT is also a no: an SDK that stops returning the field is not
	-- permission, and this is the one place in the game where guessing costs somebody a policy
	-- violation rather than a stat.
	return info.IsPaidItemTradingAllowed == true
end

local function warm(player)
	local verdict = fetch(player)
	if verdict == nil then
		lastTry[player.UserId] = os.clock()
		warn(("[TradePolicy] could not read the trading policy for %s -- refusing until it answers")
			:format(player.Name))
		return
	end
	allowed[player.UserId] = verdict
end

-- The question every caller actually asks. Returns ok, reason.
--
-- YIELDS, but only on the path where the join-time fetch failed -- which is why it must never be
-- called from inside the commit's no-yield block. `TradeService` calls it at Request, for both
-- sides, and that is the only call site.
function TradePolicy.Allows(userId)
	-- `x and nil or y` CANNOT YIELD nil, and the first cut of this file used it twice: with
	-- `cached == true` it evaluates `true and nil` -> nil -> `nil or Refusal`, so a player who is
	-- ALLOWED to trade was handed the sentence "Trading is not available on your account" beside
	-- their `true`. Harmless only because every caller reads the reason under `if not ok`; measured
	-- on the live server 2026-08-22 and written out longhand rather than left as a trap for the
	-- next caller that logs it.
	local cached = allowed[userId]
	if cached == true then return true, nil end
	if cached == false then return false, TradePolicy.Refusal end

	local player = Players:GetPlayerByUserId(userId)
	if not player then
		-- see the header: negative ids are Studio's own test players and synthetic test parties,
		-- and there is no Player for Roblox to answer about
		if type(userId) == "number" and userId < 0 then return true, nil end
		return false, TradePolicy.Unknown
	end

	local last = lastTry[userId]
	if last and os.clock() - last < RETRY_COOLDOWN then
		return false, TradePolicy.Unknown
	end

	warm(player)
	local now = allowed[userId]
	if now == nil then return false, TradePolicy.Unknown end
	if now then return true, nil end
	return false, TradePolicy.Refusal
end

-- What is known right now, for a probe and for a support question. Never fetches.
function TradePolicy.Debug()
	local yes, no = 0, 0
	for _, v in pairs(allowed) do
		if v then yes += 1 else no += 1 end
	end
	return { allowed = yes, refused = no, pending = #Players:GetPlayers() - (yes + no) }
end

function TradePolicy.Init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(warm, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		allowed[player.UserId] = nil
		lastTry[player.UserId] = nil
	end)
	-- Anyone who joined before this ran -- in Studio that is always the local player, because Play
	-- starts the client before the last server script has finished requiring.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(warm, player)
	end
end

return TradePolicy
