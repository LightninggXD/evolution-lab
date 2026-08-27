-- TrainingBar -- the training ladder as one bar, sitting above the level bar (33.21).
--
-- A HUD MODULE, i.e. a FUNCTION and not a table (`docs/SPLIT.md` §2). It builds its own bar and its
-- own listeners, so **MainUI gains exactly one line and zero top-level locals** -- the whole
-- constraint that file lives under ([[evolution-lab-mainui-register-limit]]). Written as a direct
-- sibling of `LevelBar` for the same reason `LevelBar` was written as one of `SwordSlot`: three bars
-- that answer three questions should differ only in the question.
--
-- ===== THREE BARS NOW, AND EACH ONE HAS TO SAY A DIFFERENT WORD =====
--
-- Bottom is the EVOLVE bar (`data.XP`, green, SPENT on every evolve). Above it the LEVEL bar
-- (`data.Level`, blue, reset by a rebirth, and the thing a rebirth is gated on). This is the third
-- and it is GOLD: `data.TrainingReps`, filled by creature kills and by the grotto dummy, capped, and
-- also reset by a rebirth.
--
-- The captions are the guard against a misread, exactly as they are between the two below: this one
-- opens with the biceps glyph and quotes a damage multiplier, the level bar says `LV`, the
-- evolve bar says `XP`.
-- Neither of the other two ever says this one's word.
--
-- ===== IT READS A PLAYER ATTRIBUTE, NOT `DataUpdate` =====
--
-- Same channel and same argument as `LevelBar`: the bar has to move on the swing, and `DataUpdate`
-- carries the whole save table. `LevelService.Publish` puts `TrainingReps` on the 0.4 s attribute
-- sweep beside `Level`/`LevelXp`, and `TrainingDummyService` writes the same attribute directly on a
-- blow so a punch lands on this bar in the same frame it lands on the dummy.
--
-- `DataUpdate` is still listened to and is not redundant -- the join payload is what draws the bar
-- the first time, and a rebirth's push is what snaps it back to zero without waiting for a sweep.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local formatNumber = UIKit.formatNumber

-- MEASURED OFF THE BAR BELOW IT, NOT TYPED, which is how `LevelBar` got its own number: that bar is
-- 470 x 32 with its bottom edge 226 px up, so its top edge is at 258 and this sits at 264 -- the
-- same six pixels of daylight it keeps from the evolve card under it. Same width for the same
-- reason: stacked bars of different widths read as unrelated things.
local BAR_W, BAR_H = 470, 32
local BAR_BOTTOM = 264

return function(hud)
	local player = Players.LocalPlayer

	local _, fill, label = UITheme.ProgressBar(hud.screenGui, {
		name = "TrainingBar",
		size = UDim2.new(0, BAR_W, 0, BAR_H),
		position = UDim2.new(0.5, 0, 1, -BAR_BOTTOM),
		anchorPoint = Vector2.new(0.5, 1),
		-- GOLD, and like the level bar's SkyBlue it is a negative choice: green is the evolve bar,
		-- blue is the level bar, red is the boss bar that takes over this band mid-fight. Gold is
		-- the one bright pastel in the kit none of those three can be mistaken for, and it is
		-- already this feature's colour in the world popup.
		color = UITheme.Color.Gold,
		-- THE GLYPH STAYS A GLYPH HERE, and that is not an oversight. `UITheme.IconifyLabel`
		-- refuses any label that is not LEFT-aligned, and a progress-bar caption is centred, so
		-- the drawn icon would silently no-op. Her biceps art is drawn where she actually asked
		-- for it -- on the world popup in `CombatClient`. Every bar in this HUD carries an emoji
		-- in its caption (the level bar draws \u{267B}\u{FE0F} and \u{2694}\u{FE0F} in its own
		-- tail the same way), so this is the consistent choice as well as the working one.
		text = "\u{1F4AA} 0",
		maxTextSize = 19,
		zIndex = 4,
	})

	-- ONE STRING, BUILT IN ONE PLACE, so the bar and its caption can never disagree about which rep
	-- count is being drawn -- the rule `LevelBar.refresh` states for itself.
	local function refresh()
		local data = hud.getData()

		-- THE ATTRIBUTE WINS AND THE SAVE IS THE FALLBACK, in that order and for `LevelBar`'s
		-- reason: the attribute is the live channel and is up to 0.4 s fresher than the last
		-- `DataUpdate`, so reading them the other way round would make the bar jump backwards every
		-- time a push arrived mid-fight.
		local reps = tonumber(player:GetAttribute("TrainingReps"))
		if not reps then reps = GameConfig.GetTrainingReps(data) end
		-- 33.32: the ladder no longer ends, so the denominator moves. `GetTrainingBand` hands back
		-- the band this rep count is in -- `reps / 1000` below the knee, and the progress to the
		-- NEXT doubling above it -- which is the only fraction that stays honest when a bar has no
		-- last rung. Clamping to the old cap here would have frozen this bar full at 1,000.
		reps = math.clamp(math.floor(reps), 0, GameConfig.TrainingRepMax)
		local frac, bandLow, bandHigh = GameConfig.GetTrainingBand({ TrainingReps = reps })
		local cap = GameConfig.TrainingRepCap

		-- `{ TrainingReps = reps }` rather than `data`, the same trick the level bar uses on its own
		-- multiplier: the number drawn must be the multiplier FOR THE REPS DRAWN, and `data` can be
		-- a push behind the attribute.
		local mult = GameConfig.GetTrainingDamageMult({ TrainingReps = reps })

		fill.Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)

		if reps >= cap then
			-- AT THE CAP THE DENOMINATOR IS DROPPED, not printed as "1000 / 1000". Same call the
			-- rebirth panel makes past its own ladder's end: a fraction whose halves are equal reads
			-- as a bar that has stopped working rather than one that is finished. It says what to do
			-- next instead, because a rebirth is the only thing that reopens this.
			-- PAST THE KNEE THE DENOMINATOR IS THE NEXT DOUBLING, not the knee and not a dropped
			-- fraction: the ladder is finished only in the sense that its first shape is, and a bar
			-- that says TRAINED while the number behind it is still climbing is the same lie the
			-- old "1000 / 1000" was. The rebirth is still named, because it is still what refills
			-- the fast part of the curve.
			label.Text = ("\u{1F4AA} %s / %s  \u{2022}  \u{2694}\u{FE0F} x%.2f  \u{2022}  \u{267B}\u{FE0F} refills the climb")
				:format(formatNumber(reps), formatNumber(bandHigh), mult)
			return
		end

		-- THE FILL RATE IS NAMED ON THIS BAR AND NOWHERE ELSE ON THE MAIN SCREEN, for the reason
		-- `LevelBar` names the rebirth door on its own: a rebirth makes this ladder refill faster,
		-- and that is the entire argument for why the reset is not a punishment. A player who cannot
		-- see the rate has been told only about the loss.
		local tail = ""
		local rate = GameConfig.GetTrainingGainMult(data)
		if rate > 1 then
			tail = ("  \u{2022}  x%.1f gain"):format(rate)
		end

		label.Text = ("\u{1F4AA} %s / %s  \u{2022}  \u{2694}\u{FE0F} x%.2f%s"):format(
			formatNumber(reps), formatNumber(cap), mult, tail)
	end

	-- The live channel: one attribute, so one signal.
	player:GetAttributeChangedSignal("TrainingReps"):Connect(refresh)
	-- ...and the save channel, for the join payload and for the rebirth that zeroes it.
	Remotes.DataUpdate.OnClientEvent:Connect(refresh)

	refresh()
end
