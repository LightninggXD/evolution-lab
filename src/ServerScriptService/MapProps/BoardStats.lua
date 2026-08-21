-- MapProps/BoardStats -- the five counters the map's leaderboard boards ask for and the game never
-- kept.
--
-- The village map ships eight boards: SecretsHatched, TotalGems, TimePlayed, TotalClicks, Rebirths,
-- RobuxSpent, EggsOpened and a static Suffixes legend. `LeaderboardService` ships three, and only
-- two of the eight lined up with a number this game actually stores -- `Rebirths`, and `Diamonds`
-- under the name Total Gems. The owner asked for those boards to be functional
-- (*"hocu da ovaj leaderbboard postane funkcionalan umesto starog"*), and a board with nothing
-- behind it is not functional, so the five missing counters are kept here.
--
-- ===== WHY A MODULE AND NOT FIVE LINES IN FIVE SERVICES =====
-- Every one of these is a single integer add, and five of them scattered across CreatureService,
-- PetService, RobuxShopService and PlaytimeGiftService is five places for a field name to drift and
-- no place that lists what the boards can show. Here, the field names, the rarity test and the
-- clock all sit beside the boards that read them, and each service keeps exactly one call.
--
-- ===== NO MIGRATION, AND THAT IS DELIBERATE =====
-- Every read is `(data.X or 0)`, so a save written before this file existed is already valid and a
-- veteran simply starts counting from today. The alternative -- backfilling from other fields -- is
-- guesswork that would put invented numbers on a public board.
--
-- ===== WHAT IS NOT HERE =====
-- `Kills` and `DNA` already exist and are already published by `LeaderboardService`; they are not
-- counted again. `Suffixes` is not a leaderboard at all -- it is the map's own legend of number
-- suffixes (K, M, B, ...), static art, and nothing writes to it.

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.Parent.PlayerDataService)

local BoardStats = {}

-- Field name per board, so the board table and the counters cannot disagree about a spelling.
BoardStats.Field = {
	SecretsHatched = "SecretsHatched",
	EggsOpened = "EggsOpened",
	TotalClicks = "TotalClicks",
	RobuxSpent = "RobuxSpent",
	TimePlayed = "TimePlayed",
	TotalGems = "Diamonds",   -- already stored; the map's name for it differs from ours
	Rebirths = "Rebirths",
}

-- How often banked playtime is written. Sixty seconds is the whole exposure of a crash, and it is
-- also the interval the boards refresh on, so a player never sees her own row lag by more than one
-- refresh. See BankAll for why this is not done on leave alone.
local BANK_INTERVAL = 60

-- [userId] = os.clock() at the last bank. os.clock rather than os.time because this measures a
-- duration on one machine and never has to survive a restart -- the banked total does that.
local lastBank = {}

local function bump(data, field, n)
	if not data then return end
	data[field] = (data[field] or 0) + (n or 1)
end

-- ===== HATCHING =====
-- One call covers both boards: every hatch is an egg opened, and a hatch of a Secret is also a
-- secret. Called from the two places PetService announces a hatch, which is the only choke point
-- that already sees both the player and the pet definition.
--
-- THE RARITY TEST IS BY STRING AND IT IS CASE-FOLDED. Pet definitions carry `rarity` as authored
-- text, and a definition that says "secret" instead of "Secret" would otherwise count as an
-- ordinary hatch forever, on the one board where a single miss is visible.
function BoardStats.Hatched(data, petDef)
	if not data then return end
	bump(data, BoardStats.Field.EggsOpened, 1)
	local rarity = petDef and petDef.rarity
	if typeof(rarity) == "string" and rarity:lower() == "secret" then
		bump(data, BoardStats.Field.SecretsHatched, 1)
	end
end

-- ===== BLOWS LANDED =====
-- "Total Clicks" is every blow that reaches a creature, whether it came from a click or from
-- auto-attack. Counting only manual clicks would rank players by whether they had bought Auto,
-- which is a board measuring a game pass rather than play.
function BoardStats.Clicked(data)
	bump(data, BoardStats.Field.TotalClicks, 1)
end

-- ===== ROBUX =====
-- Called from ProcessReceipt only, which is the one place Roblox guarantees a purchase actually
-- completed. Anywhere else and a cancelled prompt would show up on a public board.
function BoardStats.RobuxSpent(data, amount)
	if type(amount) ~= "number" or amount <= 0 then return end
	bump(data, BoardStats.Field.RobuxSpent, math.floor(amount))
end

-- ===== TIME PLAYED =====
-- Lifetime seconds. The game already has two playtime clocks (`PlaytimeGiftService`: one per sitting
-- and one per day) and neither survives as a total, which is what a board needs.
--
-- BANKED ON A TIMER RATHER THAN ON LEAVE, and that is the whole design. A server that crashes, or a
-- player whose client dies, never reaches a leave handler -- so a leave-only clock silently pays
-- nothing for the sessions most worth counting, and it does it invisibly because the number it
-- fails to add is exactly the number nobody can check. Sixty seconds is the most that can be lost.
local function bankOne(player, now)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local last = lastBank[player.UserId]
	if not last then
		lastBank[player.UserId] = now
		return
	end
	local elapsed = now - last
	if elapsed <= 0 then return end
	lastBank[player.UserId] = now
	bump(data, BoardStats.Field.TimePlayed, math.floor(elapsed))
end

-- Public so the leave-save can bank a final figure in the same breath it writes the save.
function BoardStats.Bank(player)
	bankOne(player, os.clock())
end

function BoardStats.Init()
	Players.PlayerAdded:Connect(function(player)
		lastBank[player.UserId] = os.clock()
	end)
	Players.PlayerRemoving:Connect(function(player)
		bankOne(player, os.clock())
		lastBank[player.UserId] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		lastBank[player.UserId] = os.clock()
	end

	task.spawn(function()
		while true do
			task.wait(BANK_INTERVAL)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				bankOne(player, now)
			end
		end
	end)
end

return BoardStats
