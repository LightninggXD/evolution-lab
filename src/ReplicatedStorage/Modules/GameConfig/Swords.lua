-- GameConfig.Swords -- the weapon ladder: ten blades, bought with Diamonds, worn on the body.
--
-- ONE OF THE PARTS OF `GameConfig` (18.9). It is handed the shared config table and writes into
-- it; see the loader in `GameConfig` itself for why the order of the parts is load-bearing.
-- Appended LAST, and that is the safe position for the same reason `Relics`, `Minigames`,
-- `Expeditions` and `Adventures` each took it in turn: nothing above reads `GameConfig.Swords` at
-- load time, and this part reads nothing above it at load time either -- the two functions that
-- quote other parts (`GetSwordDamageMult` is quoted BY `Rebirth`'s boss divisor) are called at
-- runtime, never while the table is still being built.

return function(GameConfig)

-- ===== THE GAME HAD NO WEAPON AT ALL =====
--
-- Exhaustively grepped before this was written: no `Tool`, no `StarterPack`, no equipped-item save
-- field, and the Backpack CoreGui is disabled at boot (`LoadingScreen.client.lua:155`). The swing
-- is procedural and client-side (`CombatClient`), and the "blade" a player saw was a **Trail off
-- the hand** (`handTrail`), explicitly sized *"roughly a weapon's length rather than a finger's"*.
-- So the swoosh was drawing a sword that did not exist. This ladder is that sword.
--
-- Her decision, not a proposal: *"pravi vidljivi mac sa tierovima, kupuje se Dijamantima, krece
-- se od loseg"* -- a real visible sword with tiers, bought with Diamonds, starting from a bad one.
--
-- ===== TIER 1 IS OWNED, FREE, AND WORTH NOTHING, AND ALL THREE ARE THE POINT =====
--
-- `data.SwordLevel` defaults to 1 and the count IS the position, exactly as `data.Rebirths` is --
-- no second "owned" set that could disagree with the counter. Tier 1 is the bad one she asked to
-- start from: it is a rusted stub at x1.00, so a player who has never spent a Diamond is holding
-- something, the geometry path is exercised from the first spawn, and the ladder's first rung is a
-- visible UPGRADE of a thing on screen rather than the sudden appearance of a mechanic.
--
-- ===== THE PRICES ARE DERIVED FROM 32.5's MEASUREMENT, NOT TYPED =====
--
-- 32.5 measured real diamonds per hour in the place -- `AutoAttack` fired at the client's own
-- 0.34 s cadence, parked at one camp, balance read off the real `DataUpdate` payload:
--
--     NW1 swarm      (layer 0)   101 kills / 110.0 s /  4 diamonds =  131/h
--     NW3 brute      (layer 0)    79 kills / 100.2 s /  2 diamonds =   72/h
--     SW2 raidBrute  (layer 1)    39 kills / 190.3 s / 18 diamonds =  341/h
--     SW4<->SW5 apex (layer 2)     2 kills / 110.2 s / 14 diamonds =  457/h
--
-- So the band is **~130/h on open ground and ~450/h in a rebirth-gated camp**, and the gate is the
-- late-game farm. The ladder is priced against those two numbers and nothing else:
--
--     tier 2      40      ~18 min at 131/h   -- inside a first session, the anchor she asked for
--     tier 3      80      ~37 min
--     tier 4     160      ~73 min
--     tier 5     320      ~2.4 h
--     tier 6     640      ~1.4 h at 457/h    -- from here the gated camps are the honest rate
--     tier 7   1,280      ~2.8 h
--     tier 8   2,560      ~5.6 h
--     tier 9   5,120     ~11.2 h
--     tier 10 10,240     ~22.4 h
--                        --------
--     the whole ladder   20,440 diamonds
--
-- **The cost DOUBLES every rung and nothing else decides the wall.** No `maxLevel` past the tenth
-- blade and no soft cap: the same argument the DiamondUpgrades block makes -- a cap says "you are
-- finished", a price says "not yet" -- and doubling is the one growth curve a player can read off
-- the card without doing arithmetic.
--
-- **THIS IS A LARGE NEW SINK ON A CURRENCY THAT ONLY JUST GOT A SOURCE, AND THAT IS DELIBERATE.**
-- Before 32.5 the three DiamondUpgrades plus twenty Stage Masteries were the whole demand side, and
-- 32.5 multiplied the gated supply by a measured 4.2x. 20,440 is roughly what that increase is
-- worth over a long climb, so the gate now has something to be spent ON -- which is the other half
-- of "a rebirth-gated camp should be worth walking to".
--
-- ===== THE DAMAGE CURVE IS GEOMETRIC AND STOPS AT x5 =====
--
-- x1.20 a rung, ten rungs, x5.00 at the end. It is geometric for the reason the character ladder
-- is (see the DAMAGE LADDER block in `Evolution`): a linear +X% per tier is worth less and less
-- against a stack that is itself multiplying, so the last blade -- the one that costs half the
-- ladder -- would be the least exciting purchase in it.
--
-- x5 is chosen against the two multipliers already in the game that are of the same KIND, i.e.
-- bought rather than climbed to: the full Stage Mastery set is x3.4 for ~700 diamonds, and four
-- rebirths are x8.0. The sword sits between them, which is where the headline Diamond purchase
-- belongs -- clearly bigger than the checklist, clearly smaller than the reset.
--
-- ===== AND IT IS CANCELLED AGAINST BOSSES. READ `GetBossDamageDivisor` BEFORE CHANGING THIS =====
--
-- `GameConfig.GetBossDamageDivisor` now divides by the sword term as well as the rebirth term.
-- Without that line this ladder ships twenty trivial bosses: boss health is derived from a BARE
-- player (`BossTargetHits x GetZoneReferenceDamage`, pure rank) and knows about no multiplier the
-- player owns, so an uncancelled x5 turns a ~21-blow endgame boss into a ~4-blow one.
--
-- **What that costs, stated here rather than left to be discovered:** the sword shortens every
-- creature fight in the game by its full amount and shortens a BOSS fight by nothing. That is the
-- same deal a rebirth already has, and the reversal is one term in one line if she would rather
-- feel the blade on a boss.
GameConfig.Swords = {
	{ key = "rusty",    displayName = "Rusty Stub",     emoji = "\u{2694}\u{FE0F}", damageMult = 1.00, cost = 0,
	  color = Color3.fromRGB(126,  96,  70), trim = Color3.fromRGB( 82,  62,  46), material = Enum.Material.Slate,
	  reach = 1.8, blurb = "Somebody else threw this away." },
	{ key = "iron",     displayName = "Iron Cleaver",   emoji = "\u{2694}\u{FE0F}", damageMult = 1.20, cost = 40,
	  color = Color3.fromRGB(150, 156, 165), trim = Color3.fromRGB( 74,  78,  86), material = Enum.Material.Metal,
	  reach = 2.0 },
	{ key = "bronze",   displayName = "Bronze Fang",    emoji = "\u{2694}\u{FE0F}", damageMult = 1.45, cost = 80,
	  color = Color3.fromRGB(196, 138,  72), trim = Color3.fromRGB(108,  72,  36), material = Enum.Material.Metal,
	  reach = 2.2 },
	{ key = "steel",    displayName = "Steel Edge",     emoji = "\u{2694}\u{FE0F}", damageMult = 1.75, cost = 160,
	  color = Color3.fromRGB(206, 214, 226), trim = Color3.fromRGB( 64,  70,  84), material = Enum.Material.Metal,
	  reach = 2.4 },
	{ key = "crystal",  displayName = "Crystal Shard",  emoji = "\u{2694}\u{FE0F}", damageMult = 2.10, cost = 320,
	  color = Color3.fromRGB(126, 226, 236), trim = Color3.fromRGB( 40, 118, 148), material = Enum.Material.Glass,
	  reach = 2.6 },
	{ key = "gold",     displayName = "Gilded Saber",   emoji = "\u{2694}\u{FE0F}", damageMult = 2.50, cost = 640,
	  color = Color3.fromRGB(255, 202,  74), trim = Color3.fromRGB(146,  92,  20), material = Enum.Material.Metal,
	  reach = 2.8 },
	{ key = "venom",    displayName = "Venom Reaver",   emoji = "\u{2694}\u{FE0F}", damageMult = 3.00, cost = 1280,
	  color = Color3.fromRGB(126, 232, 108), trim = Color3.fromRGB( 34,  92,  40), material = Enum.Material.Neon,
	  reach = 3.0, glow = true },
	{ key = "ember",    displayName = "Ember Brand",    emoji = "\u{2694}\u{FE0F}", damageMult = 3.60, cost = 2560,
	  color = Color3.fromRGB(255, 122,  56), trim = Color3.fromRGB(126,  34,  16), material = Enum.Material.Neon,
	  reach = 3.2, glow = true },
	{ key = "void",     displayName = "Void Splitter",  emoji = "\u{2694}\u{FE0F}", damageMult = 4.30, cost = 5120,
	  color = Color3.fromRGB(176, 108, 255), trim = Color3.fromRGB( 58,  22, 106), material = Enum.Material.Neon,
	  reach = 3.4, glow = true, spark = true },
	{ key = "absolute", displayName = "Absolute Edge",  emoji = "\u{2694}\u{FE0F}", damageMult = 5.00, cost = 10240,
	  color = Color3.fromRGB(255, 246, 190), trim = Color3.fromRGB(212, 150,  30), material = Enum.Material.Neon,
	  reach = 3.6, glow = true, spark = true },
}

GameConfig.MaxSwordLevel = #GameConfig.Swords

-- The save's level, clamped into the ladder. A save written before this feature has no field at
-- all, and a save written by a future build with more rungs must not index off the end of a table
-- an older server is holding -- both resolve to a real blade rather than to nil.
function GameConfig.GetSwordLevel(data)
	local level = (data and data.SwordLevel) or 1
	return math.clamp(math.floor(level), 1, GameConfig.MaxSwordLevel)
end

-- The row being worn. Never nil: GetSwordLevel already clamped.
function GameConfig.GetSwordTier(data)
	return GameConfig.Swords[GameConfig.GetSwordLevel(data)]
end

-- The one damage term. Quoted from `DNAService.GetCombatDamage` (which is the only thing in the
-- game that computes damage) and from `GetBossDamageDivisor` (which cancels it) -- those two call
-- sites are the whole surface, and they must stay in step or a boss is priced against a blade the
-- player is not holding.
function GameConfig.GetSwordDamageMult(data)
	local tier = GameConfig.GetSwordTier(data)
	return tier and tier.damageMult or 1
end

-- What the NEXT blade costs, given the level held now. `math.huge` when the ladder is finished --
-- the house sentinel, the same one `GetDiamondUpgradeCost` returns, so every caller that already
-- knows how to draw a maxed upgrade needs no new branch.
function GameConfig.GetSwordCost(level)
	level = math.floor(tonumber(level) or 1)
	if level >= GameConfig.MaxSwordLevel then return math.huge end
	local nextTier = GameConfig.Swords[level + 1]
	return nextTier and nextTier.cost or math.huge
end

end
