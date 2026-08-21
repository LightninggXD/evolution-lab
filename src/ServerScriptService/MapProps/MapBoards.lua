-- MapProps/MapBoards -- painting the map's own leaderboard boards and podium instead of building
-- ours next to them.
--
-- The owner's words with the screenshot: *"hocu da ovaj leaderbboard postane funkcionalan umesto
-- starog"*. The map ships eight finished boards and a three-step podium, standing in the village and
-- doing nothing, while `LeaderboardService` builds three 34 x 40 slabs at world x = -130 and a
-- separate plinth row at z = 95 -- which is why her screenshots show our boards floating among the
-- map's trees. This adopts hers and leaves ours unbuilt.
--
-- ===== WHAT A BOARD IS, MEASURED OFF THE SOURCE =====
--   <Board>                          e.g. `TotalClicks`, 2 x 17 x 14 before the 1.45
--     topka (MeshPart) x3            the posts
--       BillboardGui > Name          the title, already correct per board -- never rewritten
--     Show (Part)
--       SurfaceGui > Frame > Players
--         Template (Folder) > Frame  ONE prototype row
--         Stats (ScrollingFrame)     the live rows, plus a UIListLayout
--
-- and a row is `Frame` (ImageLabel) holding three cells, each an ImageLabel wrapping an ImageLabel
-- `Top` wrapping a TextLabel `Label`:
--     Tier -> "#1"      PlayerName -> "CV10K"      Val -> "974.98qdD"
--
-- ===== THREE THINGS THAT WOULD GO WRONG WITHOUT SAYING THEM =====
--
-- 1. THE BOARDS ARRIVE FULL OF SOMEBODY ELSE'S PLAYERS. The free model was saved with live demo
--    data in it -- `TotalClicks` carries a hundred rows naming CV10K and Diablo19812. Those are not
--    placeholders that get overwritten: `Stats` is cleared on adoption, or the first refresh writes
--    ten real rows above ninety fictional ones and the board is a lie from row eleven down.
--
-- 2. THE PROTOTYPE ROW IS A SIBLING OF THE THING BEING CLEARED, NOT INSIDE IT. `Template` is a
--    Folder beside `Stats`, so clearing Stats leaves it alone -- but it is the ONLY copy, and a
--    clear pass that walked `Players` instead of `Stats` would take it and leave the board
--    permanently unpaintable with nothing logged.
--
-- 3. A UIListLayout DOES NOT SIZE ITS OWN CANVAS. `AutomaticCanvasSize` is set here rather than
--    computing one from `AbsoluteContentSize`, which is the trap in
--    `roblox-canvas-size-vs-uiscale`: a canvas measured that way double-counts any UIScale and comes
--    out right on one screen and unscrollable on another.

local MapAnchors = require(script.Parent.MapAnchors)

local MapBoards = {}

-- [boardName] = { stats = ScrollingFrame, template = GuiObject }
local boards = {}
-- [rank] = { name = TextLabel, rank = TextLabel or nil }
local podium = {}

local ROW_CELLS = { rank = "Tier", name = "PlayerName", value = "Val" }

-- The TextLabel inside one cell. It lives two levels down (cell > Top > Label) but is found by
-- search rather than by path: `Top` is decoration, and a board authored without it should render a
-- flatter row rather than report as broken art.
local function cellLabel(row, cellName)
	local cell = row:FindFirstChild(cellName)
	if not cell then return nil end
	return cell:FindFirstChildWhichIsA("TextLabel", true)
end

local function findParts(model)
	local show = model:FindFirstChild("Show", true)
	local gui = show and show:FindFirstChildOfClass("SurfaceGui")
	if not gui then return nil end
	local players = gui:FindFirstChild("Players", true)
	if not players then return nil end
	local stats = players:FindFirstChild("Stats")
	local templateFolder = players:FindFirstChild("Template")
	local template = templateFolder and templateFolder:FindFirstChildWhichIsA("GuiObject")
	if not (stats and template) then return nil end
	return stats, template
end

-- Everything in `Stats` that is not the layout. See note 1: the demo rows go on adoption, not on the
-- first paint, because a board whose first refresh fails would otherwise sit naming strangers until
-- the next one succeeds.
local function clearRows(stats)
	for _, c in ipairs(stats:GetChildren()) do
		if not c:IsA("UILayout") then
			c:Destroy()
		end
	end
end

-- Binds every board and podium step the map published. Returns how many boards were bound; 0 means
-- the caller should build its own, which is what an unmapped zone always does.
function MapBoards.Adopt(zoneKey)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end
	boards, podium = {}, {}

	local bound = 0
	for _, name in ipairs(MapAnchors.BOARDS) do
		local anchor = MapAnchors.Get(zoneKey, "board", name)
		if anchor then
			local stats, template = findParts(anchor.inst)
			if stats then
				clearRows(stats)
				stats.AutomaticCanvasSize = Enum.AutomaticSize.Y
				stats.CanvasSize = UDim2.new()
				stats.ScrollBarThickness = 6
				-- A pale bar on a pale surface is the fault the scroll-affordance sweep found in
				-- nine of fifteen lists. These boards are bright, so the bar is dark.
				stats.ScrollBarImageColor3 = Color3.fromRGB(40, 40, 55)
				stats.ScrollBarImageTransparency = 0.25
				boards[name] = { stats = stats, template = template }
				bound += 1
			end
		end
	end

	for rank = 1, 3 do
		local anchor = MapAnchors.Get(zoneKey, "podium", rank)
		if anchor then
			local nameLabel = anchor.inst:FindFirstChild("PlayerName", true)
			local rankLabel = anchor.inst:FindFirstChild("Rank", true)
			if nameLabel and nameLabel:IsA("TextLabel") then
				podium[rank] = { name = nameLabel, rank = rankLabel }
				-- BLANKED ON ADOPTION, for the same reason `Stats` is cleared: the podium arrives
				-- carrying the free model's demo winners (CV10K, Diablo19812, "252.34Sx Rebirths").
				-- Measured 2026-08-22 -- they survived a full boot, because `clearStatue` only runs
				-- for a slot this server has already filled, and on a fresh server it never has. So
				-- an empty top three read as a real top three naming two strangers.
				nameLabel.Text = "---"
				if rankLabel and rankLabel:IsA("TextLabel") then rankLabel.Text = "" end
			end
		end
	end

	return bound
end

function MapBoards.Has(boardName)
	return boards[boardName] ~= nil
end

function MapBoards.HasPodium()
	return next(podium) ~= nil
end

-- `rows` is an array of { name = ..., text = ... }, already sorted and ALREADY FORMATTED. The caller
-- owns the number formatting because it owns the per-board short/long flag; this file owns nothing
-- but the drawing.
function MapBoards.Draw(boardName, rows)
	local b = boards[boardName]
	if not b then return false end
	clearRows(b.stats)
	for i, row in ipairs(rows or {}) do
		local clone = b.template:Clone()
		clone.LayoutOrder = i
		clone.Name = "Row" .. i
		local rankLabel = cellLabel(clone, ROW_CELLS.rank)
		local nameLabel = cellLabel(clone, ROW_CELLS.name)
		local valLabel = cellLabel(clone, ROW_CELLS.value)
		if rankLabel then rankLabel.Text = "#" .. i end
		if nameLabel then nameLabel.Text = row.name or "?" end
		if valLabel then valLabel.Text = row.text or "" end
		clone.Visible = true
		clone.Parent = b.stats
	end
	return true
end

-- An empty board says so rather than standing blank, which is indistinguishable from broken.
function MapBoards.DrawStatus(boardName, message)
	local b = boards[boardName]
	if not b then return false end
	clearRows(b.stats)
	local clone = b.template:Clone()
	clone.LayoutOrder = 1
	clone.Name = "RowStatus"
	local rankLabel = cellLabel(clone, ROW_CELLS.rank)
	local nameLabel = cellLabel(clone, ROW_CELLS.name)
	local valLabel = cellLabel(clone, ROW_CELLS.value)
	if rankLabel then rankLabel.Text = "" end
	if nameLabel then nameLabel.Text = message end
	if valLabel then valLabel.Text = "" end
	clone.Visible = true
	clone.Parent = b.stats
	return true
end

-- The three figures on the podium. An empty slot is written rather than left holding the previous
-- holder's name, which is how a public board goes stale without anyone noticing.
function MapBoards.SetPodium(rank, name, text)
	local p = podium[rank]
	if not p then return false end
	p.name.Text = name or "---"
	if p.rank then
		p.rank.Text = text or ""
	end
	return true
end

return MapBoards
