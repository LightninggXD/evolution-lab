-- LevelBar -- the level-up toast, and nothing else since 33.26. It WAS the level bar (32.7).
--
-- A HUD MODULE, i.e. a FUNCTION and not a table (`docs/SPLIT.md` §2). MainUI gains exactly one
-- line and zero top-level locals -- the whole constraint that file lives under
-- ([[evolution-lab-mainui-register-limit]]), and the reason this is still a require rather than a
-- branch in MainUI's notify handler.
--
-- ===== THE BAR IT IS NAMED AFTER IS GONE, AND THE NAME IS KEPT ON PURPOSE =====
--
-- 32.7 built a 470 x 32 SkyBlue ProgressBar six pixels above the evolve card, reading
-- `LV 28 - 202 / 786 - 8 at LV 41` off the `Level` / `LevelXp` player attributes on their 0.4 s
-- sweep. 33.26 deleted it on her call -- *"znaci imam xp bar 2 puta, mergaj nekako sa onim gore nek
-- pise na jednom i lvl jer se levelupam kad se 1 napuni"* -- because the screen held two 470-wide
-- bars that both fill by themselves and neither of which is ever pressed.
--
-- WHERE THE NUMBERS WENT: `MainUI.refreshUI` prints `LV n` and the rebirth door on the EVOLVE bar's
-- own caption. That is now the one writer of the one bar, and the note there says why the FILL
-- stayed the evolve ladder's rather than this one's. What was given up, stated rather than left to
-- be found: the level's own progress WITHIN a level (`202 / 786`) is not drawn anywhere on the main
-- screen any more -- only the level it has reached.
--
-- The two attribute listeners went with the bar. Nothing in this file redraws per blow now.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)

local Remotes = RS.Remotes

return function(hud)
	-- ===== THIS MODULE NO LONGER DRAWS A BAR, AND THAT IS THE WHOLE OF 33.26 IN IT =====
	--
	-- It used to build a 470 x 32 SkyBlue ProgressBar six pixels above the evolve card and write
	-- `LV 28 - 202 / 786 - 8 at LV 41` into it. Her call, with a capture of the two bars stacked:
	-- *"znaci imam xp bar 2 puta, mergaj nekako sa onim gore nek pise na jednom i lvl jer se
	-- levelupam kad se 1 napuni"* -- two bars that fill by themselves and are never pressed, one of
	-- which is enough.
	--
	-- The level and the rebirth door are printed by `MainUI.refreshUI` on the EVOLVE bar's own
	-- caption now. That is the one writer, and the note there says why the fill stayed the evolve
	-- ladder's rather than this one's.
	--
	-- WHAT IS LEFT HERE IS THE LEVEL-UP TOAST, and it is why this file is still required rather than
	-- orphaned beside `SwordSlot` and `QuickBuyRow`. Moving it into MainUI would be a twenty-first
	-- branch in that file's notify handler, in a file at Luau's register ceiling -- exactly the cost
	-- this module was split out to avoid.
	--
	-- The two attribute listeners went with the bar: nothing here redraws per blow any more, and the
	-- toast arrives on its own remote.
	Remotes.Notify.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or payload.kind ~= "level" then return end
		if not hud.showNotification then return end
		local text = ("\u{2B50} LEVEL %d!  \u{2694}\u{FE0F} x%.2f damage")
			:format(payload.level or 1, payload.mult or 1)
		if payload.nextRebirthLevel then
			text = text .. ("  \u{2022}  Rebirth at LV %d"):format(payload.nextRebirthLevel)
		end
		hud.showNotification(text, UITheme.Color.SkyBlue, UITheme.NotifyRank("level"))
	end)
end
