-- DamageStat -- the one number the whole game is about, as a capsule in the wallet (33.26).
--
-- A HUD MODULE, i.e. a FUNCTION and not a table (`docs/SPLIT.md` §2). It hangs one pill off the
-- existing `CurrencyStack` and listens to one player attribute plus `DataUpdate`, so **MainUI gains
-- exactly one line and zero top-level locals** ([[evolution-lab-mainui-register-limit]]).
--
-- ===== IT REPLACES A PROGRESS BAR, AND THAT IS THE WHOLE POINT =====
--
-- 33.21 drew the training ladder as a third stacked bar under the level bar -- `💪 0 / 1.00K •
-- ⚔️ x1.00 • x4.5 gain`. The owner refused it twice in one session, and the two sentences are the
-- spec for this file:
--
--   *"a ovo zlatno mi ne treba tu"* -- the gold bar is not wanted on the screen at all, and
--   *"dmg se ne skuplja ovako vec samo da pise damage: pa koliko imam i kako skupljam povecava se"*
--   -- damage is not a thing you fill a bar with. It is a number you HAVE, it is written down, and
--   it goes up as you collect.
--
-- So there is no bar, no denominator, no cap and no multiplier printed anywhere on the main screen.
-- One figure, in the wallet, beside the three currencies -- because that column is already what
-- this HUD uses for "what you have", and it is the one place on the screen that is a readout rather
-- than a control.
--
-- The training ladder is NOT gone -- it is `TrainingReps` in the save, `TrainingDummyService` still
-- banks it, and it is one of the multipliers inside the number drawn here. What is gone is the
-- ladder's own widget. The cap is announced by the toast the dummy already fires, which is the only
-- moment the ANSWER changes rather than the number.
--
-- ===== THE CHANNEL IS AN ATTRIBUTE, FOR `LevelBar`'s REASON =====
--
-- `LevelService.Publish` stamps `CombatDamage` on its existing 0.4 s sweep, beside `Level`,
-- `LevelXp` and `TrainingReps`. It is NOT a second publisher and NOT `DataUpdate`: a push carries
-- the whole save table, and this number moves on every evolve, every blade, every pet, every level
-- and every rep. `DataUpdate` is still listened to because the join payload is what draws the pill
-- the first time, before the first sweep has run.
--
-- ===== WHY IT DOES NOT COMPUTE THE NUMBER ITSELF =====
--
-- `DNAService.GetCombatDamage` is still the only thing in this game that decides damage, and it is
-- server-side by design -- it reads pets, mastery, the blade, the level and the training rank. A
-- client-side re-derivation would be a second formula that drifts silently from the one the blows
-- actually use, which is exactly the "evolving changes nothing" class of bug the damage ladder was
-- unwound to fix. This file draws what the server says and knows nothing.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local formatNumber = UIKit.formatNumber

return function(hud)
	local player = Players.LocalPlayer
	local stack = hud.screenGui:FindFirstChild("CurrencyStack")
	-- Found back by name rather than passed on `hud`: MainUI is at the register ceiling and the
	-- frame is already named. If it is ever renamed this draws nothing rather than throwing into
	-- the middle of the HUD build.
	if not stack then
		warn("[DamageStat] no CurrencyStack -- the damage readout is not drawn this session")
		return
	end

	-- LayoutOrder 4, i.e. the BOTTOM of the stack (the layout is bottom-aligned and sorts by order),
	-- so the three currencies keep the exact positions they have had since 18.2 and this arrives
	-- under them rather than pushing them about.
	--
	-- ROSE-WHITE, and the choice is the same negative one the other three made: Mint is DNA, Aqua is
	-- Diamonds, Lavender is Shards. 16% of Frost toward `Color.Red` -- the identical lerp and the
	-- identical 16%, so this is a member of that wallet and not a new colour on the screen -- is the
	-- fourth tint none of them can be confused with, and warm is the hue every damage figure in this
	-- game is already drawn in.
	local pill = UITheme.Pill(stack, {
		name = "DamagePill", icon = "\u{2694}\u{FE0F}", text = "0", layoutOrder = 4,
		size = UDim2.new(1, 0, 0, 40), maxTextSize = 30,
		shellColor = UITheme.Color.Frost:Lerp(UITheme.Color.Red, 0.16), color = UITheme.Color.Ink,
	})

	local function refresh()
		-- THE ATTRIBUTE WINS AND THE SAVE IS THE FALLBACK, `LevelBar`'s order and its reason: the
		-- attribute is up to 0.4 s fresher than the last push, so reading them the other way round
		-- would make the number jump backwards every time a push landed mid-fight.
		local dmg = tonumber(player:GetAttribute("CombatDamage"))
		if not dmg then return end
		pill.Value.Text = formatNumber(math.floor(dmg))
	end

	player:GetAttributeChangedSignal("CombatDamage"):Connect(refresh)
	Remotes.DataUpdate.OnClientEvent:Connect(refresh)
	refresh()
end
