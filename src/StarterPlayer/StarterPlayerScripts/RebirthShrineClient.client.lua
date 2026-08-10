--[[
	RebirthShrineClient -- the per-player half of the Rebirth Shrine.

	The shrine's four statues are built once, on the server, and every player in the server is
	looking at the same four Instances. Whether a statue is REACHABLE is not shared: it depends on
	the stage the player looking at it has climbed to. A ProximityPrompt has no per-player Enabled
	and a Part has no per-player Color, so the lock has to live on the client -- these are local
	property writes, they do not replicate, and each machine paints its own view of the plaza.

	NOTHING HERE IS AUTHORITATIVE. Disabling a prompt stops the player triggering it by accident; it
	does not stop an exploiter firing the Rebirth remote by hand. RebirthService re-checks the tier
	against the server's own copy of the save on every trigger, and that check is the real one.

	A locked statue is turned to stone -- grey, Slate, no glow, no particles -- and an unlocked one
	is the creature in its own colours. That contrast is the whole point of putting rebirth in the
	world: from the gateway you can see how far along the row you have earned your way.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS:WaitForChild("Remotes")

local player = Players.LocalPlayer

local STONE      = Color3.fromRGB(138, 134, 146)
local STONE_DARK = Color3.fromRGB(104, 100, 112)
local GOLD       = Color3.fromRGB(255, 205, 90)
local LOCKED_EDGE = Color3.fromRGB(120, 116, 128)

-- [monument] = { parts = { [part] = { color, material } }, tier, prompt, ... }
local statues = {}
local latestData = nil

-- Everything the statue is made of EXCEPT the masonry it stands on: the plinth is stone whether
-- the statue on it is earned or not, and greying it out with the rest would leave a locked
-- monument as one undifferentiated grey block with no shape in it.
local MASONRY = {
	PlinthBase = true, Plinth = true, PlinthCap = true,
}

-- STREAMING MAKES THIS A POLL, NOT AN EVENT. A tagged Model replicates to the client long before
-- its parts do -- at join all four monuments exist as empty Models tens of thousands of studs away
-- -- so a one-shot `WaitForChild("Plinth", 10)` on the tag-added signal times out on every one of
-- them, and nothing ever runs again when the player finally walks into the zone and the parts
-- arrive. This is therefore non-yielding and re-runnable: it returns nil while the statue is still
-- a shell, and re-caches from scratch if the parts have been swapped out and back by streaming.
local function tryRegister(monument)
	local tier = monument:GetAttribute("RebirthTier")
	if not tier then return nil end

	local cached = statues[monument]
	if cached and cached.plinth.Parent then return cached end

	local plinth = monument:FindFirstChild("Plinth")
	if not plinth then return nil end

	local entry = {
		plinth = plinth,
		tier = tier,
		stageIndex = monument:GetAttribute("RequiredStageIndex") or GameConfig.GetRebirthTierStageIndex(tier),
		-- may still be nil on the frame the plinth arrives; paint() guards, and the next pass fills it
		prompt = plinth:FindFirstChild("RebirthPrompt"),
		glow = monument:FindFirstChild("PlinthGlow"),
		parts = {},
		emitters = {},
		lights = {},
	}

	-- Cached BEFORE anything is repainted, so the "unlocked" look is restored to what the server
	-- actually built rather than to a guess. A model that streams out and back in arrives with its
	-- original colours again and is re-registered from scratch, which is why this is keyed by
	-- instance and thrown away with the model.
	for _, d in ipairs(monument:GetDescendants()) do
		if d:IsA("BasePart") and not MASONRY[d.Name] then
			entry.parts[d] = { color = d.Color, material = d.Material, transparency = d.Transparency }
		elseif d:IsA("ParticleEmitter") then
			table.insert(entry.emitters, d)
		elseif d:IsA("PointLight") then
			table.insert(entry.lights, d)
		end
	end

	-- the board hangs on a BoardAnchor parented beside the monument's own parts
	local board
	for _, d in ipairs(monument:GetDescendants()) do
		if d:IsA("BillboardGui") and d.Name == "StatueBoard" then
			board = d
			break
		end
	end
	entry.title = board and board:FindFirstChild("Card") and board.Card:FindFirstChild("Title")
	entry.status = board and board:FindFirstChild("Card") and board.Card:FindFirstChild("Status")
	entry.edge = board and board:FindFirstChild("Card") and board.Card:FindFirstChild("Edge")

	statues[monument] = entry
	return entry
end

local function short(n)
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local function paint(entry, unlocked, data)
	for part, original in pairs(entry.parts) do
		if part.Parent then
			if unlocked then
				part.Color = original.color
				part.Material = original.material
			else
				-- Two greys, not one: the costume is built as a body colour with darker limbs and
				-- details on top, and flattening all of it to a single value erases the silhouette
				-- that makes a Wolf recognisable as a Wolf.
				local lum = (original.color.R + original.color.G + original.color.B) / 3
				part.Color = lum > 0.45 and STONE or STONE_DARK
				part.Material = Enum.Material.Slate
			end
		end
	end
	for _, e in ipairs(entry.emitters) do
		if e.Parent then e.Enabled = unlocked end
	end
	for _, l in ipairs(entry.lights) do
		if l.Parent then l.Enabled = unlocked end
	end
	if entry.glow and entry.glow.Parent then
		entry.glow.Color = unlocked and GameConfig.Stages[entry.stageIndex].color or STONE_DARK
	end
	if entry.prompt and entry.prompt.Parent then
		entry.prompt.Enabled = unlocked
	end

	if entry.edge then
		entry.edge.Color = unlocked and GOLD or LOCKED_EDGE
	end
	if entry.status then
		-- Two lines of nothing but the number that matters. The title above already names the tier and
		-- the creature, so repeating "Reach Wolf (Stage 5)" here filled a 38-stud sign with words the
		-- player has just read and pushed the one figure they came for down to unreadable.
		-- THREE STATES, NOT TWO. A statue is a milestone spent once and in order now, so "spent" is a
		-- state of its own: the tier below the next one is not locked and not available, it is
		-- FINISHED, and painting it the same grey as a tier never reached would read as having lost
		-- something. See the REBIRTH IS A LADDER block in GameConfig.
		local nextTier = data and GameConfig.GetNextRebirthTier(data) or 1
		if unlocked then
			entry.status.TextColor3 = GOLD
			entry.status.Text = ("\u{267B}\u{FE0F} REBIRTH %d  \u{2022}  READY"):format(entry.tier)
		elseif nextTier == nil or entry.tier < nextTier then
			entry.status.TextColor3 = Color3.fromRGB(150, 210, 160)
			entry.status.Text = ("\u{2713} REBIRTH %d  \u{2022}  DONE"):format(entry.tier)
		else
			entry.status.TextColor3 = Color3.fromRGB(196, 192, 204)
			entry.status.Text = ("\u{1F512} Needs Stage %d"):format(entry.stageIndex)
		end
	end
end

-- The tag list is the source of truth for what exists; `statues` is only the cache of what has been
-- measured. Registering is folded into the same pass so a statue that finished streaming in a
-- moment ago is picked up here rather than needing an event of its own.
local function refresh()
	local data = latestData
	-- ONE statue is live at a time now: the next milestone on the ladder, and only once the stage
	-- behind it is reached. `tier <= earnedTier` used to light every statue the player had ever
	-- passed, which was right when a rebirth was repeatable at any tier and is exactly wrong now --
	-- it would offer three spent milestones alongside the one real one.
	local nextTier = data and GameConfig.GetNextRebirthTier(data) or 1
	local ready = data and (GameConfig.CanRebirthNow(data)) or false
	for _, monument in ipairs(CollectionService:GetTagged("RebirthStatue")) do
		local entry = tryRegister(monument)
		if entry then
			paint(entry, ready and entry.tier == nextTier, data)
		end
	end
end

CollectionService:GetInstanceRemovedSignal("RebirthStatue"):Connect(function(monument)
	statues[monument] = nil
end)

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
	latestData = data
	refresh()
end)

-- The heartbeat. DataUpdate lands often enough on its own (income ticks push it), but rebirth
-- eligibility must not depend on the economy happening to fire -- and a statue whose parts arrive
-- during a quiet moment would otherwise sit unpainted with its prompt off. Two seconds over four
-- models is nothing, and it is the only thing that makes walking into a zone reliable.
task.spawn(function()
	while true do
		refresh()
		task.wait(2)
	end
end)
