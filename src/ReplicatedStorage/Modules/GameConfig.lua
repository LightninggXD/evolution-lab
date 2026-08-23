-- GameConfig -- every number in the game, in sixteen parts.
--
-- WHY IT IS SPLIT (18.9)
-- ----------------------
-- It was 5,205 lines and ~83k tokens to read whole, and it is required by every script in the
-- place, so any session that needed one constant paid for all of them. The parts below are its
-- own section headings, unchanged; `docs/codemap/GameConfig.md` maps them.
--
-- THE PUBLIC SHAPE DID NOT CHANGE. This still returns one table with the same fields, so no call
-- site anywhere in the game changed -- `require(RS.Modules.GameConfig).Zones` is what it always
-- was. Each part is `return function(GameConfig) ... end` and writes into the table it is handed.
--
-- THE CUT IS CLEAN BECAUSE OF A MEASUREMENT, not a hope: the file had 21 top-level locals and
-- every one was used within a few dozen lines of its own definition, none crossing a section
-- heading. The boundaries were chosen so no local has to leave the part it is declared in.
--
-- ORDER IS LOAD-BEARING AND THIS LIST IS THE ORDER. Several parts build tables at load time out
-- of what earlier parts put on the table -- `Characters` reads `GameConfig.Stages`, `Zones` reads
-- the damage ladder -- so they are required in exactly the order they were written in. Moving a
-- name up this list is a silent nil at load time, not an error.
local GameConfig = {}

for _, part in ipairs({
	"Evolution",
	"Upgrades",
	"Zones",
	"Pets",
	"Rebirth",
	"Rewards",
	"Potions",
	"Shops",
	"Diamonds",
	"Mastery",
	"RobuxShop",
	"Events",
	"Season",
	"Helpers",
	"Characters",
	"Codes",
	-- LAST, and it is the safe position rather than an arbitrary one. `Relics` reads `GetPassAdd`
	-- and the rarity/stat conventions the earlier parts establish, and nothing above it reads
	-- `GameConfig.Relics` at load time -- so appending is the only move that cannot produce the
	-- silent nil this list's header warns about.
	"Relics",
	-- AFTER `Relics`, and the same argument that put `Relics` last applies again: `Minigames` reads
	-- `GameConfig.Zones` at load time (its tripwire walks them) and quotes `ScaleReward` at call
	-- time, and nothing above it reads `GameConfig.Minigames` at all. Appending is therefore the
	-- only move that cannot produce the silent nil this list's header warns about.
	"Minigames",
	-- AFTER `Minigames`, and this one is a hard dependency rather than a convention: its
	-- load-time check reads `GameConfig.MinigameKindsByKey` to prove every expedition station
	-- names a game that exists, and its reward functions quote `GetMinigameReward`.
	"Expeditions",
	-- AFTER `Expeditions`, and it is a hard dependency for two reasons at once: it DERIVES its
	-- twenty routes from `GameConfig.Zones` at load time -- one per zone, so `tier` can never
	-- disagree with the strip -- and its luck ladder quotes `GetPetPower`, `GetLuckPercent` and
	-- `PetBaseBonus` from `Pets`. Nothing above it reads `GameConfig.AdventureList`, so appending
	-- is again the only move that cannot produce the silent nil this list's header warns about.
	"Adventures",
	-- LAST, and the same argument that put each of the four above it last in turn applies again:
	-- `Swords` reads nothing from the table at load time (its ladder is literal), and nothing above
	-- it reads `GameConfig.Swords` at load time -- `Rebirth`'s boss divisor quotes
	-- `GetSwordDamageMult` at CALL time, which is why the part it lives in may load after `Rebirth`.
	-- Appending is therefore the only move that cannot produce the silent nil this list's header
	-- warns about.
	"Swords",
}) do
	require(script:WaitForChild(part))(GameConfig)
end

return GameConfig
