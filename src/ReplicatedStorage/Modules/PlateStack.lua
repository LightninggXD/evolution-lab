--[[
	PlateStack -- two players standing together must still have two readable names.

	The report was "ovo se preklapa", on a two-client capture where Player1's and Player2's name
	plates ran into each other. Measured live at 3.5 studs apart: the two plate boxes came out
	x[561..729] and x[560..728], and y[189..257] against y[196..264]. That is 167 px of 168
	overlapping horizontally and 61 px of 68 vertically -- one smear of two names, not two names.

	The bodies are NOT the problem and are deliberately left alone. Dropped exactly on top of each
	other the two characters separate to 2.03 studs within 1.5 s and hold there: only three parts
	on the rig collide (HumanoidRootPart, UpperTorso, LowerTorso) and they scale with the body, so
	the physics answer is already right at every stage.

	WHAT MAKES THIS CHEAP IS THAT THE PLATE IS SIZED IN OFFSET. A BillboardGui whose Size is pure
	offset is a constant number of PIXELS on screen at every distance, so the overlap test is plain
	2D arithmetic and needs no perspective correction. And the lift is applied through SizeOffset,
	which is measured in the plate's OWN size -- also pixels -- rather than through StudsOffset,
	which is world space and would shrink the separation as the camera pulls back. That is the same
	distinction the plate's own comment in CombatClient pays for.

	Nearest plate wins its natural height; anything behind it that would land on top of it is
	pushed up a row. The push is eased rather than snapped, because a plate that teleports upward
	reads as a glitch.
]]

local RunService = game:GetService("RunService")

local PlateStack = {}

-- how far apart two plates have to be before they are allowed to share a band, and how far a
-- plate may climb before it gives up. Four rows is already a crowd; past that the far ones
-- overlap again, which is better than a name leaving the screen entirely.
local GAP = 6
local MAX_ROWS = 4
-- an anchor this far outside the viewport cannot put anything readable on screen
local MARGIN = 300
local EASE = 14

local entries = {}
local running = false

local function place(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize

	local live = {}
	for i = #entries, 1, -1 do
		local e = entries[i]
		if not (e.gui.Parent and e.part.Parent) then
			table.remove(entries, i)
		else
			e.target = 0
			if e.gui.Enabled then
				local sp = cam:WorldToViewportPoint(e.part.Position + e.gui.StudsOffset)
				if sp.Z > 0 and sp.X > -MARGIN and sp.X < vp.X + MARGIN
					and sp.Y > -MARGIN and sp.Y < vp.Y + MARGIN then
					e.x, e.bottom, e.depth = sp.X, sp.Y, sp.Z
					table.insert(live, e)
				end
			end
		end
	end

	if #live > 1 then
		table.sort(live, function(a, b) return a.depth < b.depth end)
		for i, e in ipairs(live) do
			local lift = 0
			-- greedy, nearest first. Re-run after every push: clearing one plate can drop this one
			-- onto a second one that was never in the way at the old height.
			for _ = 1, MAX_ROWS + 2 do
				local moved = false
				for j = 1, i - 1 do
					local q = live[j]
					if math.abs(e.x - q.x) < (e.w + q.w) * 0.5 then
						local bottom = e.bottom - lift
						if bottom - e.box < q.bottomAt + GAP and bottom > q.topAt - GAP then
							lift = e.bottom - (q.topAt - GAP)
							moved = true
						end
					end
				end
				if not moved then break end
			end
			e.target = math.clamp(lift, 0, MAX_ROWS * (e.box + GAP))
			e.topAt, e.bottomAt = e.bottom - e.box - e.target, e.bottom - e.target
		end
	end

	local a = math.min(1, dt * EASE)
	for _, e in ipairs(entries) do
		local cur, want = e.current, e.target or 0
		if math.abs(want - cur) > 0.5 then
			cur = cur + (want - cur) * a
		else
			cur = want
		end
		if cur ~= e.current then
			e.current = cur
			e.gui.SizeOffset = Vector2.new(e.base.X, e.base.Y + cur / e.h)
		end
	end
end

--[[
	Register a plate. `part` is what it hangs off (its Position is the anchor the StudsOffset is
	measured from), and `extraTop` is any art that is drawn ABOVE the BillboardGui's own box -- the
	health plate's title line sits at -16, so its occupied height is 68 and not 52. Registering the
	same gui twice is a no-op; deregistration is automatic once the gui or its part leaves the tree.
]]
function PlateStack.add(gui, part, extraTop)
	if not (RunService:IsClient() and gui and part) then return end
	for _, e in ipairs(entries) do
		if e.gui == gui then return end
	end
	table.insert(entries, {
		gui = gui,
		part = part,
		base = gui.SizeOffset,
		w = gui.Size.X.Offset,
		h = gui.Size.Y.Offset,
		box = gui.Size.Y.Offset + (extraTop or 0),
		current = 0,
		target = 0,
		topAt = 0,
		bottomAt = 0,
	})
	if not running then
		running = true
		RunService.RenderStepped:Connect(place)
	end
end

return PlateStack
