-- MapSettle -- the last pass over a built zone: anything left standing in mid-air is put back on the
-- floor (32.21).
--
-- ===== THE COMPLAINT, AND WHY IT IS A PASS RATHER THAN A FIX IN ONE BUILDER =====
--
-- The owner, 2026-08-27, selecting one tree in the Explorer: *"kad kazem na zemlji mislim bas na podu
-- gde se hoda"* -- when I say on the ground I mean on the floor you actually walk on. The tree she had
-- selected was `Zones.HuntForest.HuntTree` with its foot at **y 7.41** and nothing under it but
-- `WorldShell.Floor` at **y 0.00**.
--
-- Roadmap 32.21 already knew the cause and named it: **`MapRidge.Clear` takes the artist's mountains
-- out, and whatever was standing on one stays exactly where it was.** That is not the only producer,
-- though -- `MapPass` cuts hills out of the portal corridor and `MapHorizon` shrinks them for the gate
-- lane, and each of those can strand whatever the forest planted on top. Fixing it inside each
-- builder means three fixes, three chances to miss the fourth, and every one of them has to re-derive
-- "where is the ground here".
--
-- So it is a **corrective pass that runs last**, which is the shape this map already uses for exactly
-- this class of problem (`MapPass`, `MapPassDress`, `MapWaterfall` are all late passes that measure
-- the finished world and correct it). It cares about the OUTCOME -- nothing floats -- rather than
-- about which builder let go of it.
--
-- ===== MEASURED BEFORE IT WAS WRITTEN =====
--
-- On the built Forest, 6,336 props checked one raycast each:
--   * `HuntForest` -- **40 floating** of 8,129 children, worst a `HuntTree` **22.5 studs** up at
--     (-63, -512), and the only thing under it is `WorldShell.Floor`.
--   * `WaterfallRidge` -- **24 floating** of 117, worst a `SkirtTree` **28.9 studs** up at (218, -260).
--   * `Jungle` -- **0**. The camps lay their own floors and never lost one.
-- 64 props, i.e. one prop in a hundred. Small enough that nobody noticed it as a class, big enough
-- that she found one by looking at the skyline.

local MapSettle = {}

-- Under this and it is not worth moving: props are seated with a deliberate quarter-stud bite into
-- the ground all over this map, and a slope means a wide prop's lowest corner is legitimately clear
-- of the point its centre casts from.
local TOLERANCE = 1.5

-- ===== IT ONLY EVER DROPS, NEVER LIFTS =====
-- A prop whose foot is BELOW the surface is half-buried, and half-buried is how most of the rocks and
-- stumps in this map are deliberately seated -- `MapForest` sinks them on purpose. Lifting those
-- would be a second bug wearing the first one's clothes.
local MAX_DROP = 400

-- The walk down stops at the first surface that is not itself something this pass is settling. A tree
-- resting on a floating rock is still floating; landing it on that rock would look settled for one
-- frame and then the rock would move.
local function groundUnder(x, z, yFrom, ignore, settling)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local filter = { ignore }
	for _ = 1, 8 do
		params.FilterDescendantsInstances = filter
		local hit = workspace:Raycast(Vector3.new(x, yFrom, z), Vector3.new(0, -MAX_DROP, 0), params)
		if not hit then return nil end
		local owner = hit.Instance
		-- climb to the child of the folder, which is what `settling` is keyed by
		local node = owner
		while node and node.Parent and settling[node] == nil and node.Parent ~= workspace do
			node = node.Parent
		end
		if settling[node] then
			table.insert(filter, node)
		else
			return hit.Position.Y, owner
		end
	end
	return nil
end

-- The TRUE world AABB and horizontal centre. Model box getters are PIVOT-frame and half these props
-- are seated at a random yaw, so `GetBoundingBox` reports a box that is not the one gravity sees
-- (`roblox-model-box-getters-are-pivot-frame`).
local function measure(inst)
	local lo = math.huge
	local sx, sz, n = 0, 0, 0
	local list = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then
			local cf, sz2 = d.CFrame, d.Size
			local ey = math.abs(cf.RightVector.Y) * sz2.X / 2
				+ math.abs(cf.UpVector.Y) * sz2.Y / 2
				+ math.abs(cf.LookVector.Y) * sz2.Z / 2
			lo = math.min(lo, cf.Position.Y - ey)
			sx += cf.Position.X; sz += cf.Position.Z; n += 1
		end
	end
	if n == 0 then return nil end
	return lo, sx / n, sz / n
end

local function moveDown(inst, drop)
	if inst:IsA("BasePart") then
		inst.CFrame = inst.CFrame - Vector3.new(0, drop, 0)
	else
		inst:PivotTo(inst:GetPivot() - Vector3.new(0, drop, 0))
	end
end

-- `spec` is a list of { folder = <Instance>, names = <set or nil> }. `nil` names means every child.
--
-- IDEMPOTENT BY CONSTRUCTION, and that matters because `ForestMapService.Init` is not the only thing
-- that can run a build: a settled prop measures a gap under `TOLERANCE` on the next pass and is left
-- alone, so running this three times settles the same 64 props once.
function MapSettle.Run(spec)
	local settling = {}
	for _, set in ipairs(spec) do
		if set.folder then
			for _, c in ipairs(set.folder:GetChildren()) do
				if (c:IsA("Model") or c:IsA("BasePart")) and (not set.names or set.names[c.Name]) then
					settling[c] = true
				end
			end
		end
	end

	local dropped, checked, worst, worstName = 0, 0, 0, ""
	for inst in pairs(settling) do
		local foot, mx, mz = measure(inst)
		if foot then
			checked += 1
			local groundY = groundUnder(mx, mz, foot + 1, inst, settling)
			if groundY then
				local gap = foot - groundY
				if gap > TOLERANCE then
					moveDown(inst, gap)
					dropped += 1
					if gap > worst then
						worst = gap
						worstName = ("%s (%.0f, %.0f)"):format(inst.Name, mx, mz)
					end
				end
			end
		end
	end
	return dropped, checked, worst, worstName
end

-- The Forest set, named here rather than at the call site so the one place that knows WHICH props
-- stand on the ground is this file. `Jungle` is included even though it measured 0 floating: it costs
-- one raycast per camp prop and it is the folder most likely to gain a floating prop the next time
-- the camps move.
function MapSettle.Forest(map)
	return MapSettle.Run({
		{ folder = map:FindFirstChild("HuntForest"), names = { HuntTree = true } },
		{ folder = map:FindFirstChild("WaterfallRidge"),
			names = { SkirtTree = true, SkirtRock = true, FlankTree = true, SkirtPlate = true } },
		{ folder = map:FindFirstChild("Jungle"), names = nil },
	})
end

return MapSettle
