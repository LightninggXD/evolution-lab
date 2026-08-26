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
--       BillboardGui > Name          the title -- correct per board, and REWRITTEN for a repoint
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
local MapRing = require(script.Parent.MapRing)

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

-- ===== NINE STATS, EIGHT SLOTS (31.12) =====
-- The map ships EIGHT board positions on one arc, and `LeaderboardService` has NINE things worth
-- ranking. Two of the nine -- DNA and Kills -- had no map child at all, so `Has` was false for both
-- and neither has been displayed anywhere in the world since the map went in. They are the two
-- numbers this game is actually about: DNA is the currency the whole loop pays out and Kills is the
-- loop. A leaderboard hall that ranks Robux Spent and Time Played while showing neither of them is
-- ranking the wrong things.
--
-- MEASURED, so the arithmetic is not a guess: the seven real boards sit on a circle of radius 33.5
-- about (121, 5) at a 33-degree step, `Suffixes` sits in the EIGHTH slot on that same circle, and
-- slots nine and ten are full of bushes, a stump and a pine. There is no ninth position to be had
-- without clearing the artist's planting, so one of the nine goes without a board.
--
-- `RobuxSpent` is the one that goes. Its counter keeps banking -- nothing is lost and a ninth slot
-- would light it up immediately -- it simply has no surface, and a public ranking of who has spent
-- the most real money is the one board this hall is better off without.
MapBoards.REPOINT = {
	-- the legend's slot, rebuilt below as a real board
	Suffixes = { key = "DNA", title = "\u{1F9EC} MOST DNA" },
	RobuxSpent = { key = "Kills", title = "\u{2694}\u{FE0F} KILLS" },
}

-- A repointed board is still physically labelled with the map's own word for it, and that label is
-- a BillboardGui on the posts rather than anything the draw path touches -- so without this a board
-- ranks kills under the heading ROBUX SPENT and looks, precisely, like a bug in the sorting.
--
-- The title is spelled here rather than read from `LeaderboardService.Boards` because that file
-- already requires this one, and a cycle to save two strings is a bad trade. They are checked
-- against each other by eye in one place: the table above.
local function retitle(model, text)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") then
			local label = d:FindFirstChild("Name")
			if label and label:IsA("TextLabel") then
				label.Text = text
				return true
			end
		end
	end
	return false
end

-- `Suffixes` is not a board. It is the asset's static legend of number suffixes (K, M, B, ...) and
-- it has no `Show` part, no `Players`, no `Stats` and no row template -- which is why `findParts`
-- has always returned nil for it and `Adopt` has always bound seven of eight.
--
-- So it is not repointed, it is REPLACED: a clone of a board that does have all of that, turned
-- onto the legend's own bearing about the ring the other seven stand on. Cloning rather than
-- building means the row structure, the fonts and the art are the map's own and cannot drift from
-- its neighbours -- and turning rather than positioning means the artist's facing rule is carried,
-- which is `MapRing`'s whole reason for existing.
--
-- The legend itself is destroyed rather than hidden. It is 12 studs tall where a board is 19, so
-- left standing it would poke out from behind its replacement.
local function rebuildLegend(map, legend, donor, ring)
	-- Idempotent, because `Adopt` destroys the legend: a second call would find no prop to replace
	-- and would silently leave DNA unbound for the rest of the server's life.
	local already = map and map:FindFirstChild("DNABoard")
	if already then
		if legend then legend:Destroy() end
		return already
	end
	if not (legend and donor and ring) then return nil end
	local bearing = MapRing.Bearing(legend, ring)
	local clone = donor:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	clone.Name = "DNABoard"
	clone.Parent = map
	MapRing.PlaceAt(clone, ring, bearing)
	clone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	legend:Destroy()
	return clone
end

-- Binds every board and podium step the map published. Returns how many boards were bound; 0 means
-- the caller should build its own, which is what an unmapped zone always does.
function MapBoards.Adopt(zoneKey)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end
	boards, podium = {}, {}

	-- ONE PROP AT A TIME, and the order matters: the legend can only be rebuilt from a board that
	-- has already been proved to have the row structure, so the real props are collected first and
	-- the replacement is made out of one of them afterwards.
	local props, real = {}, {}
	for _, name in ipairs(MapAnchors.BOARDS) do
		local anchor = MapAnchors.Get(zoneKey, "board", name)
		if anchor and anchor.inst and anchor.inst.Parent then
			props[name] = anchor.inst
			if findParts(anchor.inst) then real[#real + 1] = anchor.inst end
		end
	end

	-- The legend's slot, turned into a real board on the ring the other seven stand on. `MapRing.Fit`
	-- needs three props and returns nil for a straight row, in which case there is simply no eighth
	-- board and DNA keeps the podium as its only surface -- which is what 31.12 offered as the other
	-- answer, reached by measurement rather than by giving up.
	local map = #real > 0 and real[1].Parent or nil
	local ring = MapRing.Fit(real)
	for name, spec in pairs(MapBoards.REPOINT) do
		local prop = props[name]
		if prop and not findParts(prop) then
			local rebuilt = rebuildLegend(map, prop, real[1], ring)
			if rebuilt then
				props[name] = rebuilt
			else
				props[name] = nil
				warn(("[MapBoards] %s: '%s' is not a board and could not be rebuilt -- %s has no "
					.. "surface in the world"):format(zoneKey, name, spec.key))
			end
		end
	end

	local bound = 0
	for _, name in ipairs(MapAnchors.BOARDS) do
		local prop = props[name]
		if prop then
			local stats, template = findParts(prop)
			if stats then
				clearRows(stats)
				stats.AutomaticCanvasSize = Enum.AutomaticSize.Y
				stats.CanvasSize = UDim2.new()
				stats.ScrollBarThickness = 12
				-- A pale bar on a pale surface is the fault the scroll-affordance sweep found in
				-- nine of fifteen lists. These boards are bright, so the bar is dark.
				stats.ScrollBarImageColor3 = Color3.fromRGB(40, 40, 55)
				stats.ScrollBarImageTransparency = 0.25
				-- ...under the key the GAME asks for, which is not always the map's own word for it
				local spec = MapBoards.REPOINT[name]
				if spec then retitle(prop, spec.title) end
				boards[spec and spec.key or name] = { stats = stats, template = template }
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
-- ===== THE ROW TEMPLATE IS SIZED FOR A HUNDRED ROWS, AND WE DRAW TEN =====
-- Measured on the live build: the template's height is `{0.01, 0}` -- ONE PERCENT of the Stats
-- frame, 5.9 pixels of a 586-pixel canvas. That is not a mistake in the asset, it is the asset's own
-- design: the free model shipped a hundred demo rows, and a hundred rows at one percent fill the
-- board exactly. `LeaderboardService` publishes `TOP_N` = 10, so ten of them stack into a 59-pixel
-- sliver at the very top and the rest of the board is blank.
--
-- AND IT DOES NOT LOOK EMPTY, WHICH IS WHY IT SURVIVED A CAPTURE IN 31.5. The cells inside a row are
-- much bigger than the row and nothing clips them, so all ten draw at full size on top of each
-- other and the LAST one wins. The board shows one perfectly legible row -- `#4 Player -2 1.6K` --
-- and the nine above it are behind it. A board that renders one plausible row is indistinguishable
-- in a screenshot from a board with one entry, which is exactly what 31.5's "a capture shows a live
-- row" recorded.
--
-- So the height is set from the COUNT, at draw time, rather than trusted from the template. Sized
-- against `SLOTS` and not against `#rows`, so a board with three entries draws three rows the same
-- height as a full board's -- rows that grow as the leaderboard empties would be the other bug.
local SLOTS = 10
local ROW_GAP = 0.004

local function fitRow(clone)
	clone.Size = UDim2.new(clone.Size.X.Scale, clone.Size.X.Offset, 1 / SLOTS - ROW_GAP, 0)
end

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
		fitRow(clone)
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
	fitRow(clone)
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
