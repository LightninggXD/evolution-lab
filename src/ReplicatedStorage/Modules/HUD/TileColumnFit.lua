-- TileColumnFit -- the responsive pass that tightens the two HUD tile columns to the viewport.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

return function(hud)
	local RIGHT_COLS, screenGui = hud.RIGHT_COLS, hud.screenGui

	local cam = workspace.CurrentCamera
	if not cam then return end

	local columns = { L = {}, R = {} }
	for _, child in ipairs(screenGui:GetChildren()) do
		local side = child:GetAttribute("ColumnSide")
		if side and columns[side] then
			table.insert(columns[side], child)
		end
	end
	for _, list in pairs(columns) do
		table.sort(list, function(a, b)
			return (a:GetAttribute("ColumnOrder") or 0) < (b:GetAttribute("ColumnOrder") or 0)
		end)
	end

	-- what the columns may not grow into: the topbar and the stage card above, and the evolve card
	-- and XP bar below. BOTTOM_CLEAR came down 122 -> 46 when the quick-action row it was reserving
	-- space for became rows 3 and 4 of this cluster -- that dead strip is now cluster.
	-- 121, up from 96: the TopBar carrying the stage card ends at y = 32 and the first tile started
	-- at 38, which after both strokes is no gap at all -- the card and the Shop tile were touching.
	local TOP_CLEAR, BOTTOM_CLEAR = 121, 46

	-- THE GAP IS NOT THE GAP YOU SEE, and this is why raising it to 18 did not visibly separate
	-- anything. Every tile carries a UIStroke of 5 drawn in Border mode -- OUTSIDE the frame's own
	-- bounds -- so between two tiles a nominal gap loses 5 to the upper tile's stroke and 5 to the
	-- lower tile's.
	--
	-- THE ARITHMETIC CHANGED ON 2026-08-11: it used to lose a third 5 to the sibling drop shadow
	-- addShadow parked below every tile, i.e. `visible = GAP - 15`. That shadow is gone (see
	-- UITheme.addShadow for why), so it is **`visible = GAP - 10`** now -- and GAP came 31 -> 26 to
	-- hold the same 16px of actual daylight. Leaving it at 31 would have quietly opened the column
	-- to 21px and pushed the bottom row into BOTTOM_CLEAR on a short viewport.
	--
	-- 26 for 16px of daylight. The number to change is this one.
	local GAP_MAX, GAP_MIN = 26, 8
	-- ...and the gap closes BEFORE the tiles shrink, which is what the note at the top of this block
	-- promises and what the old fixed gap never actually did. At 31 a four-row cluster needs 93px of
	-- pure spacing, and on a short viewport that pushed the tiles under their 40px floor and
	-- overflowed the screen. Spacing is the first thing a cramped screen can afford to lose.
	-- how many tiles wide each side is. BOTH sides are two wide as of 16.2: the left column lost its
	-- Trade tile and the four that remain read as a 2x2 block rather than a four-tall ladder down the
	-- edge. Half the height means the tiles keep their authored 82px on viewports where the ladder was
	-- being shrunk to fit, and it hands the whole bottom-left quarter of the screen back.
	local WIDTH = { L = 2, R = RIGHT_COLS }

	local function layout()
		local avail = math.max(cam.ViewportSize.Y - TOP_CLEAR - BOTTOM_CLEAR, 140)
		for side, list in pairs(columns) do
			local n = #list
			if n > 0 then
				-- SIZE IS DRIVEN BY THE ROW COUNT, NOT THE TILE COUNT. That is the whole benefit of
				-- the grid: seven tiles in two columns is four rows, so each tile gets the height
				-- budget of a quarter of the screen instead of a seventh, and stays at its authored
				-- 82px on any ordinary viewport instead of shrinking toward the 40px floor and
				-- dragging every caption down to its minimum size with it.
				local cols = WIDTH[side] or 1
				local rows = math.ceil(n / cols)
				local gap = GAP_MAX
				local size = math.clamp(math.floor((avail - (rows - 1) * gap) / rows), 40, 82)
				if rows * size + (rows - 1) * gap > avail and rows > 1 then
					gap = math.clamp(math.floor((avail - rows * size) / (rows - 1)), GAP_MIN, GAP_MAX)
					size = math.clamp(math.floor((avail - (rows - 1) * gap) / rows), 40, 82)
				end
				local pitch = size + gap
				for i, tile in ipairs(list) do
					tile.Size = UDim2.new(0, size, 0, size)
					local col = (i - 1) % cols
					local row = math.floor((i - 1) / cols)
					if side == "L" then
						tile.Position = UDim2.new(0, 20 + col * pitch, 0, TOP_CLEAR + row * pitch)
					else
						-- anchored (1, 1), i.e. positioned by its bottom-RIGHT corner: the cluster
						-- fills upward from the bottom edge and leftward from the right one, so the
						-- last row and the last column are the ones pinned to the corner.
						tile.Position = UDim2.new(
							1, -20 - (cols - 1 - col) * pitch,
							1, -(BOTTOM_CLEAR + (rows - 1 - row) * pitch))
					end
				end
			end
		end
	end

	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	layout()
end
