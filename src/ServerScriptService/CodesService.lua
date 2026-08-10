--[[
	CodesService -- redeeming the codes in GameConfig.Codes.

	Why this is worth building at all: Dexerto, Gamerant and Game.Guide publish a codes article for
	any Roblox game that has codes and refresh it monthly. That article is a search result pointing
	at this game, for free, forever. A game with no codes gets no article.

	THE SHAPE OF THE VALIDATION, and why each guard is here rather than assumed:

	  * A code arrives as whatever the player typed into a TextBox, which is an arbitrary string from
	    an untrusted client. `GameConfig.NormaliseCode` caps its length and strips it before anything
	    compares it, so a 4 MB string costs one length check rather than six string comparisons.
	  * `data.RedeemedCodes` is checked and written in the SAME synchronous block as the grant. There
	    is no yield anywhere between them on purpose -- a yield there is the whole exploit, because
	    two remotes fired on consecutive frames would both read "not redeemed" and both pay out.
	  * The rate limit exists for guessing, not for spam. Six real codes in a space of short
	    upper-case strings is guessable at a few hundred attempts a second and is not guessable at
	    one; and every refusal costs the same work, so the timing of a reply says nothing about
	    whether a code exists.

	Every failure path returns a STATUS STRING as well as notifying the player. That is what makes
	this testable without a keyboard -- the same reason `PassService.GrantVipDaily` and
	`PetService.DriveAutoHatch` are public.
--]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)

local CodesService = {}

-- One attempt a second. A person typing a code off a web page takes several seconds over it; a
-- script working through a dictionary does not.
local REDEEM_INTERVAL = 1.0
local lastAttempt = {} -- [userId] = os.clock()

local function refuse(player, message)
	Remotes.Notify:FireClient(player, { kind = "error", message = message })
end

-- Turns a code row into the line the player is shown. Built from what was ACTUALLY granted rather
-- than from the row, so the message can never promise a reward the grant did not make.
local function describe(granted)
	local parts = {}
	if granted.dna and granted.dna > 0 then
		table.insert(parts, ("+%d \u{1F9EC}"):format(granted.dna))
	end
	if granted.diamonds and granted.diamonds > 0 then
		table.insert(parts, ("+%d \u{1F48E}"):format(granted.diamonds))
	end
	if granted.shards and granted.shards > 0 then
		-- \u{1F31F} 🌟, THE MARK SHARDS ACTUALLY CARRY. This line printed \u{1F52E} 🔮, a crystal
		-- ball, which is the Mystery Potion shop's glyph and nothing to do with shards -- so a code
		-- that paid shards told the player it had paid them something the game does not have. The
		-- three lines around it all use the real currency mark, which is what made it stand out.
		table.insert(parts, ("+%d \u{1F31F}"):format(granted.shards))
	end
	if granted.potions and granted.potions > 0 then
		table.insert(parts, ("+%d \u{1F9EA}"):format(granted.potions))
	end
	return table.concat(parts, "   ")
end

-- Returns a status string: "ok", "used", "expired", "unknown", "throttled", "invalid", "nodata".
function CodesService.Redeem(player, text)
	local data = PlayerDataService.Get(player)
	if not data then return "nodata" end

	local now = os.clock()
	local previous = lastAttempt[player.UserId]
	if previous and (now - previous) < REDEEM_INTERVAL then
		refuse(player, "Slow down a moment, then try again.")
		return "throttled"
	end
	lastAttempt[player.UserId] = now

	local key = GameConfig.NormaliseCode(text)
	if not key then
		refuse(player, "Enter a code first!")
		return "invalid"
	end

	local entry = GameConfig.GetCode(key)
	if not entry then
		refuse(player, "That code doesn't exist.")
		return "unknown"
	end
	if GameConfig.IsCodeExpired(entry) then
		refuse(player, "That code has expired.")
		return "expired"
	end

	data.RedeemedCodes = data.RedeemedCodes or {}
	if data.RedeemedCodes[key] then
		refuse(player, "You've already used that code!")
		return "used"
	end

	-- ===== FROM HERE TO THE END OF THE GRANT THERE IS NO YIELD =====
	-- Marked BEFORE the rewards are added, so that even if something below were ever changed into
	-- something that yields, the second redemption of the same code finds it already used rather
	-- than paying out twice.
	data.RedeemedCodes[key] = true

	local granted = {
		dna = (entry.dna and entry.dna > 0) and GameConfig.ScaleReward(entry.dna, data) or 0,
		diamonds = entry.diamonds or 0,
		shards = entry.shards or 0,
		potions = entry.potions or 0,
	}
	if granted.dna > 0 then
		data.DNA += granted.dna
	end
	if granted.diamonds > 0 then
		data.Diamonds = (data.Diamonds or 0) + granted.diamonds
	end
	if granted.shards > 0 then
		data.EvolutionShards = (data.EvolutionShards or 0) + granted.shards
	end
	if granted.potions > 0 then
		-- same call the daily reward uses; falls back to the default bottle when the row names none
		GameConfig.AddPotions(data, entry.potionId, granted.potions)
	end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("\u{1F39F}\u{FE0F} Code %s redeemed!\n%s"):format(
			GameConfig.NormaliseCode(entry.code), describe(granted)),
		color = GameConfig.GetRarity("Legendary").color,
	})
	return "ok"
end

-- How many of the live codes this save has left. Drawn by the redeem panel so a player who has
-- used everything sees "0 left" rather than typing into a box that can only ever refuse them.
function CodesService.CountUnused(data)
	local redeemed = (data and data.RedeemedCodes) or {}
	local n = 0
	for _, entry in ipairs(GameConfig.Codes) do
		if not GameConfig.IsCodeExpired(entry) and not redeemed[GameConfig.NormaliseCode(entry.code)] then
			n += 1
		end
	end
	return n
end

function CodesService.Init()
	-- created on demand, like every remote added after the place was last saved by hand
	local remote = Remotes:FindFirstChild("RedeemCode")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "RedeemCode"
		remote.Parent = Remotes
	end
	remote.OnServerEvent:Connect(function(player, text)
		-- the type check is here rather than inside Redeem so the rate limiter is never even
		-- consulted for a payload that was never a code
		if type(text) ~= "string" then return end
		CodesService.Redeem(player, text)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAttempt[player.UserId] = nil
	end)
end

return CodesService
