-- MapProps/MapPortalArt -- the owner's inserted portal island stays as decoration, and the paid
-- ad unit hiding inside it does not ship armed.
--
-- ===== WHAT SHE ACTUALLY INSERTED (32.28) =====
-- The owner dropped `Workspace.Forest Portal Template` (200 x 165 x 143 at (138, 379, -412), a
-- floating island) meaning it as a better portal for the gate at the -Z edge. Its three scripts
-- were scanned on arrival and are clean (`AdPortalEffectsController` + two
-- `AttributesController`s -- no JobId, no require-by-id, no HttpService, no Teleport). BUT THE
-- MODEL IS ROBLOX'S PAID *PORTAL AD* UNIT: `BasePortal.Door.AdPortal` and its `AdGui` display
-- another experience's advert and TELEPORT THE PLAYER OUT OF THIS GAME when touched. That is
-- not decoration, it is a monetised exit we did not buy.
--
-- So this file does two things, every boot:
--   1. STRIP the ad plumbing -- every `AdPortal` / `AdGui` descendant, by class first and by
--      name as a fallback (a re-authored template may rename parts but rarely classes). It
--      prints its count even when that count is 0: a sanitiser that goes silent is one nobody
--      notices has stopped working.
--   2. SEAT the surviving `Decorative` island against the corridor mouth `MapPass.Cut` opened,
--      so it frames HER OWN gate (`MapPortals`' door, which keeps the zone teleport). The ad
--      door never becomes walkable because it no longer exists.
--
-- 👤 OPEN QUESTION FOR THE OWNER: the island's POSE. The z/x below put it just behind her gate,
-- centred on the lane, sunk so nothing floats; if she wants it flanking rather than behind,
-- those are two constants to move, not code.

local MapPortalArt = {}

local TEMPLATE_NAME = "Forest Portal Template"
local ISLAND_NAME = "Decorative"

-- Seated against the pass MapPass opens, NOT left at the arbitrary (138, 379, -412) it was
-- dropped at. x rides cx so a moved zone drags its gate dressing with it; y puts the island's
-- 143-stud body from y -35 up to y 108, i.e. skirt buried in the void past the wall and crown
-- rising over the gate stonework -- a mount behind the door, not a floater over one.
local ISLAND_X_OFFSET = 0
local ISLAND_Z = -676
local ISLAND_Y = 36

local AD_CLASSES = { AdPortal = true, AdGui = true }

function MapPortalArt.Init(zoneKey, cx)
	local tpl = workspace:FindFirstChild(TEMPLATE_NAME)
		or workspace:FindFirstChild(TEMPLATE_NAME, true)

	local stripped, names = 0, {}
	if tpl then
		for _, d in ipairs(tpl:GetDescendants()) do
			-- Collect before destroying: killing a parent invalidates the rest of the iteration.
			if AD_CLASSES[d.ClassName]
				or d.Name:lower():find("adportal", 1, true)
				or d.Name:lower():find("adgui", 1, true) then
				local orphaned = false
				for _, kept in ipairs(names) do
					if d:IsDescendantOf(kept.inst) then orphaned = true break end
				end
				if not orphaned then
					stripped += 1
					names[stripped] = { inst = d, label = ("%s (%s)"):format(d.Name, d.ClassName) }
				end
			end
		end
		for _, n in ipairs(names) do n.inst:Destroy() end

		local island = tpl:FindFirstChild(ISLAND_NAME, true)
		if island then
			island:PivotTo(CFrame.new(cx + ISLAND_X_OFFSET, ISLAND_Y, ISLAND_Z))
		end
		local shown = {}
		for i = 1, math.min(#names, 3) do shown[i] = names[i].label end
		print(("[MapPortalArt] %s: stripped %d ad unit(s) (%s); island %s"):format(
			zoneKey, stripped,
			#shown > 0 and table.concat(shown, ", ") or "-",
			island and ("seated at (%.0f, %.0f, %.0f)")
				:format(cx + ISLAND_X_OFFSET, ISLAND_Y, ISLAND_Z) or "not found"))
	else
		print(("[MapPortalArt] %s: stripped 0 ad unit(s); template %s not found")
			:format(zoneKey, TEMPLATE_NAME))
	end
	return stripped
end

return MapPortalArt
