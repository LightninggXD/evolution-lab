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
}) do
	require(script:WaitForChild(part))(GameConfig)
end

return GameConfig
