local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)

local PassService = {}

-- Set by ServerMain rather than required here, to avoid a circular require -- the same shape
-- DNAService.OnMasteryChanged already uses. Called whenever a player's pass set changes, so an
-- effect that lives on the Humanoid (2x Speed) lands immediately instead of at the next respawn.
PassService.OnPassesChanged = nil

local CHECK_ATTEMPTS = 3
local CHECK_BACKOFF = 1.2   -- seconds, multiplied by the attempt number
local RECHECK_DELAY = 30    -- seconds before retrying a check that could not be completed
local RECHECK_LIMIT = 4

-- [userId] = true while a background re-check loop is already running, so a purchase or a fast
-- rejoin cannot start a second one racing the first.
local rechecking = {}

local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

-- Returns true, false, or NIL for "could not be determined".
--
-- Those three answers are kept distinct for exactly the reason PlayerDataService.fetch keeps them
-- distinct: UserOwnsGamePassAsync is a web call, and a web call that failed is not a `false`. If an
-- outage is read as "does not own", a paying player silently loses what they bought; if it is read
-- as "owns", every player in the server gets every pass for free. Neither is acceptable, so the
-- caller is told it does not know and retries.
local function ownsPass(userId, passId)
	for attempt = 1, CHECK_ATTEMPTS do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end)
		if ok then
			return result == true
		end
		if attempt < CHECK_ATTEMPTS then
			task.wait(CHECK_BACKOFF * attempt)
		end
	end
	return nil
end

-- VIP pays a few Diamonds a day. Stamped by UTC day IN THE SAVE, the same way PlaytimeGiftService
-- does it -- and for the same reason: that ladder was re-farmable by rejoining precisely because its
-- claim table lived in module memory and was cleared on leave. A day stamp in `data` cannot be
-- rejoined around.
--
-- Diamonds and not DNA on purpose. Diamond sinks are small fixed numbers that do not ride the stage
-- curve, so five of them is worth the same to a new player and to a stage-20 one; a daily DNA grant
-- would have to be scaled and would still be either trivial or game-breaking at one end.
--
-- Public rather than local so it can be driven directly from a probe: with every passId still 0
-- there is no way to make Refresh see VIP as owned, and "verified by reading" is not verified.
function PassService.GrantVipDaily(player, data)
	if not GameConfig.OwnsPass(data, "VIP") then return end
	local pass = GameConfig.GetGamePass("VIP")
	local amount = pass and pass.dailyDiamonds or 0
	if amount <= 0 then return end

	local today = math.floor(os.time() / 86400)
	if data.VipDailyDay == today then return end
	data.VipDailyDay = today
	data.Diamonds = (data.Diamonds or 0) + amount

	-- Saved immediately. A grant that lives only in memory until the next autosave is a grant the
	-- player loses if the server goes down, and the day stamp would go with it -- so they would be
	-- paid twice tomorrow instead, which is the same bug from the other side.
	PlayerDataService.Save(player)
	PlayerDataService.UpdateLeaderstats(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("\u{1F451} VIP Daily\n+%d \u{1F48E}"):format(amount),
		color = Color3.fromRGB(255, 205, 74),
	})
end

-- Rebuilds `data.Passes` from the live ownership API. Returns true when every pass got a definite
-- answer, false when at least one did not.
--
-- FAILS CLOSED: a pass that could not be verified is not granted. It is written WHOLESALE rather
-- than merged into the existing table, because a refunded or revoked pass has to be able to
-- disappear -- a merge would keep it for the rest of the session.
function PassService.Refresh(player)
	local data = PlayerDataService.Get(player)
	if not data then return false end

	local owned = {}
	local complete = true
	for _, pass in ipairs(GameConfig.GamePasses) do
		-- A pass still on the placeholder id cannot be owned by anyone, and asking the API about id 0
		-- is a guaranteed error and a wasted web call per player per join.
		if (pass.passId or 0) > 0 then
			local has = ownsPass(player.UserId, pass.passId)
			if has == true then
				owned[pass.key] = true
			elseif has == nil then
				complete = false
			end
		end
	end

	data.Passes = owned
	-- Before the push, so the client's copy already carries the diamonds and the day stamp.
	PassService.GrantVipDaily(player, data)
	PlayerDataService.PushToClient(player)
	if PassService.OnPassesChanged then
		PassService.OnPassesChanged(player, data)
	end
	return complete
end

-- A pass that could not be verified is not granted -- but the player must not be stuck without what
-- they paid for until they think to rejoin, either. So an incomplete refresh is retried quietly in
-- the background, which turns a transient outage into a delay instead of a lost purchase, without
-- ever granting anything on a failure.
local function refreshWithRetries(player)
	if rechecking[player.UserId] then return end
	rechecking[player.UserId] = true
	task.spawn(function()
		for attempt = 0, RECHECK_LIMIT do
			if not player.Parent then break end
			if PassService.Refresh(player) then break end
			if attempt < RECHECK_LIMIT then
				task.wait(RECHECK_DELAY)
			end
		end
		rechecking[player.UserId] = nil
	end)
end

function PassService.Has(player, key)
	return GameConfig.OwnsPass(PlayerDataService.Get(player), key)
end

function PassService.Init()
	local promptPass = ensureRemote("PromptGamePassPurchase")

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			-- PlayerDataService loads on its own PlayerAdded connection and there is no ordering
			-- guarantee between two connections to the same event, so wait for the table to exist
			-- rather than assuming it does.
			local data
			repeat
				task.wait(0.2)
				data = PlayerDataService.Get(player)
			until data or not player.Parent
			if data then
				refreshWithRetries(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		rechecking[player.UserId] = nil
	end)

	-- FIRED BY THE ENGINE, ON THE SERVER. Unlike a RemoteEvent this cannot be raised by an exploiter,
	-- which is what makes granting straight from it safe for a PASS. (A developer product is a
	-- different matter and still has to go through ProcessReceipt -- see RobuxShopService.)
	--
	-- Granted directly rather than by re-running Refresh, because UserOwnsGamePassAsync is cached
	-- for a short while on Roblox's side and can still answer "no" for a purchase made seconds ago.
	-- Re-verifying here would take the pass straight back off the player who just paid for it.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then return end
		local data = PlayerDataService.Get(player)
		if not data then return end

		for _, pass in ipairs(GameConfig.GamePasses) do
			if pass.passId == passId and passId > 0 then
				data.Passes = data.Passes or {}
				data.Passes[pass.key] = true
				-- A player who buys VIP mid-session should not wait until tomorrow for the first payout.
				PassService.GrantVipDaily(player, data)
				-- Deliberately NOT saved. `Passes` is a runtime cache rebuilt from the ownership API
				-- on every join (PlayerDataService clears it on load), so writing it to the DataStore
				-- would persist a claim nothing ever reads and that must never be trusted anyway.
				PlayerDataService.PushToClient(player)
				if PassService.OnPassesChanged then
					PassService.OnPassesChanged(player, data)
				end
				Remotes.Notify:FireClient(player, { kind = "robuxPurchase", name = pass.name })
				break
			end
		end
	end)

	promptPass.OnServerEvent:Connect(function(player, passKey)
		if typeof(passKey) ~= "string" then return end
		local pass = GameConfig.GetGamePass(passKey)
		if not pass then return end

		-- The same guard RobuxShopService already has for products. Prompting on id 0 opens a dialog
		-- that cannot complete, which reads to the player as the game being broken rather than as
		-- something not being on sale yet.
		if not pass.passId or pass.passId <= 0 then
			Remotes.Notify:FireClient(player, { kind = "error", message = "This pass isn't set up yet -- check back soon!" })
			return
		end

		if GameConfig.OwnsPass(PlayerDataService.Get(player), passKey) then
			Remotes.Notify:FireClient(player, { kind = "error", message = "You already own " .. pass.name .. "!" })
			return
		end

		MarketplaceService:PromptGamePassPurchase(player, pass.passId)
	end)
end

return PassService
