-- NavBlock -- a wall that ONLY THE PATHFINDER can see.
--
-- ===== WHY IT EXISTS (32.35, 2026-09-08) =====
--
-- `PathfindingService` builds its navmesh out of collision geometry and it cannot tell a stepping
-- stone from a floor, or a 3-stud slot between two boulders from a doorway. Where the world puts a
-- picket line of separated blocks across open ground -- `WaterfallParkour`'s five approach stones
-- are the case this was written for -- the mesh threads the slots between them and hands back a
-- route that is 4 studs wide for a body that is 8.6, or that steps 7.5 studs up a face a humanoid
-- can climb 3 of. A driven body walks into it and stops dead. Measured on 2026-09-08: a walk from
-- `ForestSpawn` to the waterfall grotto chest stalled TWICE at (254, 4.2, -230), on the north face
-- of `ParkourStone3`, which is the same coordinate 32.34's walk reported three weeks before.
--
-- ===== EVERY OTHER MECHANISM FOR SAYING "DO NOT WALK HERE" WAS TRIED FIRST, AND ALL OF THEM FAIL =====
--
-- Measured in a Play boot on 2026-09-08 against a control wall on open shore, reading the path's
-- maximum lateral deviation:
--
--   * `PathfindingModifier` with `PassThrough = false` on a NON-COLLIDABLE part -- no effect
--     (deviation 0.0). A part that is not collidable contributes nothing to the navmesh, and a
--     modifier cannot conjure a region out of one that is not there. This is the fix the roadmap
--     row itself prescribed, and it does nothing.
--   * `PathfindingModifier` with a `Label`, and `Costs = { Label = math.huge }` in the agent
--     parameters -- no effect on a non-collidable part either, for the same reason.
--   * The same label on a COLLIDABLE part does work (deviation 24.1 against 0.0 uncosted) -- but
--     only with `PassThrough = true`, i.e. only once the part has stopped being an obstacle, and
--     only for a caller that remembers to pass the `Costs` table. Nothing in this repo calls
--     `ComputeAsync` in shipped code, so "the caller opts in" means the fault is still armed for
--     whoever writes the first escort.
--   * AND A MODIFIER IS ONLY READ WHEN THE PART ENTERS THE NAVMESH. Setting `PassThrough` or
--     `Label` on a part already parented to the workspace changes nothing, at any wait -- the same
--     wall answered identically before and after. The modifier has to be parented to the part
--     BEFORE the part is parented to the world. Two runs were spent proving the feature was broken
--     before that was the answer.
--
-- ===== WHAT ACTUALLY WORKS: A COLLIDABLE PART THAT COLLIDES WITH NOTHING =====
--
-- The navmesh reads `CanCollide`. It does NOT read the collision GROUP. So a part with
-- `CanCollide = true` in a group registered non-collidable against every other group is a full
-- navmesh obstacle (deviation 29.5, identical to a plain wall) and is physically inert: nothing
-- touches it, nothing stands on it, and a player jumps straight through it. `CanQuery = false`
-- and `CanTouch = false` take it out of raycasts and out of `GetPartsInPart` as well, so the walk
-- probes and `SecretsService.reportBlocked` never see it either.
--
-- THE ONE TRAP THIS LEAVES, AND IT IS WORTH THE PRICE: a `NavBlock` reads `CanCollide == true` to
-- any code that looks at the property instead of at the spatial query. Anything walking the
-- workspace by property -- a clearance pass, a footprint audit -- must skip a part whose
-- `CollisionGroup` is `PathBlock`. Every spatial query in the repo goes through `GetPartsInPart` or
-- a raycast, both of which honour `CanQuery`, so nothing today has to change.
--
-- ===== WHAT IT IS NOT FOR =====
--
-- This does not make a world passable; it makes the PATHFINDER honest about a world that is not.
-- Fencing off ground a player can genuinely walk would hand every future escort a longer route for
-- no reason. Block only geometry a body cannot cross -- a face taller than its step-up, or a slot
-- narrower than its shoulders -- and say so in the caller.

local PhysicsService = game:GetService("PhysicsService")

local NavBlock = {}

-- The group every block lives in. Registered on first use rather than in the place file, because
-- nothing else in this game uses collision groups at all and a runtime registration keeps the whole
-- mechanism inside the module that depends on it.
NavBlock.GROUP = "PathBlock"

local ready = false

local function ensureGroup()
	if ready then return end
	-- `RegisterCollisionGroup` throws on a name that already exists, which is the normal case on a
	-- second server or after a soft rebuild.
	pcall(function() PhysicsService:RegisterCollisionGroup(NavBlock.GROUP) end)
	-- Non-collidable against everything, ITSELF INCLUDED. A pair that is not set stays collidable,
	-- so this has to walk the live registry rather than name Default and stop.
	for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		PhysicsService:CollisionGroupSetCollidable(NavBlock.GROUP, group.name, false)
	end
	ready = true
end

-- One block. `cframe` and `size` describe the volume the pathfinder must treat as solid.
--
-- The part is anchored, invisible, un-queryable and un-touchable; the only property that carries
-- meaning is `CanCollide`, and it means "the navmesh sees this".
function NavBlock.New(name, cframe, size, parent)
	ensureGroup()

	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true      -- the navmesh reads this, and only this
	part.CanQuery = false       -- ...so no raycast and no GetPartsInPart ever returns it
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = cframe
	part.CollisionGroup = NavBlock.GROUP
	part:SetAttribute("NavBlock", true)
	part.Parent = parent
	return part
end

return NavBlock
