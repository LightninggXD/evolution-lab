--[==[
	HeraldBoard -- what the village board says, once a second (22.4).

	Split from `HeraldStation` (which builds it) and from `HeraldService` (which runs the fight) for
	the reason the whole feature is four small files rather than one: the drawing is the half most
	likely to be re-read and re-tuned, and it should be openable without loading a boss fight.

	IT DRAWS WHICHEVER FIGHT IS LIVE, NOT ITS OWN. `BossLedger` holds one fight at a time -- the
	Devourer in the Colosseum or the Herald here -- because the two are staggered half an interval
	apart and never overlap. So this board is the village's window onto both: it names the boss, it
	says where it is standing, and it ranks the people hitting it. That is the point of 22.4 -- the
	Colosseum was a room nobody could see into.

	WITH NOTHING LIVE IT IS A CLOCK, and the clock counts to whichever of the two arrives next,
	naming it. "NEXT: THE HERALD IN 6:12" is a reason to stay where you are; "NEXT BOSS IN 6:12"
	is not.
]==]

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)

local HeraldBoard = {}

local IDLE_COLOR = Color3.fromRGB(146, 152, 178)

local function clock(seconds)
	seconds = math.max(math.floor(seconds), 0)
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

--- `board` is the handle table `HeraldStation.Ensure` returns.
-- `snap` is `BossLedger.Snapshot()` or nil.
-- `next` is { emoji, name, where, seconds } -- what is coming when nothing is live.
function HeraldBoard.Draw(board, snap, nextUp)
	if not board or not board.shell then return end

	if not snap then
		board.title.Text = ("%s NEXT: %s"):format(nextUp.emoji or "\u{2694}\u{FE0F}", (nextUp.name or "WORLD BOSS"):upper())
		board.sub.Text = nextUp.where or ""
		board.barBack.Visible = true
		board.barFill.Size = UDim2.fromScale(1, 1)
		board.barFill.BackgroundColor3 = IDLE_COLOR
		board.barLabel.Text = clock(nextUp.seconds or 0)
		for _, row in ipairs(board.rows) do row.name.Text = "" row.pct.Text = "" end
		board.footer.Text = "everyone who lands a hit is paid in full"
		return
	end

	board.title.Text = ("%s %s"):format(snap.emoji, snap.name:upper())
	board.barFill.BackgroundColor3 = board.edge and board.edge.Color or Color3.fromRGB(255, 96, 72)

	if snap.live then
		board.sub.Text = snap.where
		board.barFill.Size = UDim2.fromScale(math.clamp(snap.hp / math.max(snap.max, 1), 0, 1), 1)
		board.barLabel.Text = ("%s / %s"):format(UITheme.FormatNumber(snap.hp), UITheme.FormatNumber(snap.max))
	else
		-- The fight is over and the board holds the result for a few seconds -- see `BossLedger`.
		board.sub.Text = snap.result or "the fight is over"
		board.barFill.Size = UDim2.fromScale(snap.hp > 0 and math.clamp(snap.hp / math.max(snap.max, 1), 0, 1) or 0, 1)
		board.barLabel.Text = snap.hp > 0 and "WITHDRAWN" or "DEFEATED"
	end

	-- The ranking. A share rather than a raw damage figure, and that is not decoration: the two
	-- world bosses clamp every blow into a narrow band precisely so that turning up matters more
	-- than gear (see `HeraldService`), and a percentage is what makes that visible. Raw numbers
	-- would also be four different orders of magnitude down one board.
	for i, row in ipairs(board.rows) do
		local entry = snap.ranked[i]
		if entry then
			row.name.Text = ("%d.  %s"):format(i, entry.name)
			row.pct.Text = ("%d%%"):format(math.floor(entry.share * 100 + 0.5))
		else
			row.name.Text = ""
			row.pct.Text = ""
		end
	end

	if snap.count == 0 then
		-- The empty state is the one that has to sell the fight, so it says what is on offer rather
		-- than reporting that nothing has happened.
		board.footer.Text = snap.live and "every hit is paid in full -- be the first" or "nobody hit it"
	elseif snap.count <= #board.rows then
		board.footer.Text = ("%d challenger%s"):format(snap.count, snap.count == 1 and "" or "s")
	else
		board.footer.Text = ("%d challengers  (+%d more)"):format(snap.count, snap.count - #board.rows)
	end
end

return HeraldBoard
