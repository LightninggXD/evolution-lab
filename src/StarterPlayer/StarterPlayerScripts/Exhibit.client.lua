--[[
	Exhibit -- the half of the plaza's fourteen plinths that has to be drawn per player (26.5).

	HubPlaza stands the nine VIP bundles and the five event skins on plinths either side of the walk
	down from the spawn, in their true colours, with a plaque under each one naming what it costs or
	which ladder pays it out. This file is the other half of that: **an unowned figure is painted out
	to a silhouette**, and the plaque's last line says what this player would have to do about it.

	WHY IT CANNOT BE DONE ON THE SERVER. The plaza is one shared set of parts and ownership is a fact
	about a save -- one player owning VIP would otherwise light the row up for everybody in the
	server. The seam is deliberately thin: the server stamps `CharacterKey` and `ExhibitKind` on each
	stand and writes a readable plaque; this file reads those two attributes and nothing else about
	how the plinth was built.

	LOCKED IS THE DEFAULT AND THAT IS ON PURPOSE. The figures replicate in their real colours, so a
	client that fails to reach a DataUpdate would show fourteen unlocked skins -- the one wrong answer
	that costs a sale. Every stand is silhouetted the moment it is found, before any data arrives, and
	only a payload can unlock one.

	THE TEXTURE IS THE HALF A TINT DOES NOT COVER. These are catalog bundles: `Color` alone leaves a
	fully textured Korblox-grade body standing there in a dark tint, which reads as a lighting bug
	rather than as a locked item. Clearing `MeshPart.TextureID` is what makes it a shape. It is a
	LOCAL write on a replicated part -- it never leaves this machine -- and the original is kept so a
	pass bought mid-session repaints the row without a rejoin.
]]

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)

-- Dark, and NOT the plaza's near-black outline: a silhouette that matches the kerb it stands over
-- disappears into it from any distance. This sits a little above it and a little blue, so the shape
-- still reads against both the stone deck and the dark plinth.
local SILHOUETTE = Color3.fromRGB(46, 42, 66)

local INK_OWNED = Color3.fromRGB(58, 150, 84)
local INK_LIVE = Color3.fromRGB(58, 150, 84)
local INK_WAIT = Color3.fromRGB(126, 134, 156)
local INK_PRICE = Color3.fromRGB(168, 120, 24)

local stands = {}
-- The last payload, kept rather than consumed. A player can be standing in the plaza before it has
-- replicated to them -- the model is Persistent, not instant -- so the first DataUpdate routinely
-- lands with nothing to paint, and a stand found afterwards has to be able to ask what it missed.
local lastData = nil

-- ============================================================================
-- THE SILHOUETTE
-- ============================================================================
local function remember(rec, part)
	if rec.colour[part] ~= nil then return end
	rec.colour[part] = part.Color
	rec.material[part] = part.Material
	if part:IsA("MeshPart") then
		rec.texture[part] = part.TextureID
	end
end

local function setLocked(rec, locked)
	if rec.locked == locked then return end
	rec.locked = locked
	for _, part in ipairs(rec.parts) do
		if part.Parent then
			remember(rec, part)
			if locked then
				part.Color = SILHOUETTE
				part.Material = Enum.Material.SmoothPlastic
				if part:IsA("MeshPart") then
					part.TextureID = ""
				end
			else
				part.Color = rec.colour[part]
				part.Material = rec.material[part]
				if part:IsA("MeshPart") then
					part.TextureID = rec.texture[part] or ""
				end
			end
		end
	end
end

-- ============================================================================
-- WHAT THE LAST LINE OF A PLAQUE SAYS
-- ============================================================================
-- Owned is owned, for both kinds. Everything below it is the answer to "so how do I get this",
-- which is a price for the wardrobe and a clock for an event.
local function statusFor(rec)
	if rec.owned then
		return "\u{2713} YOURS", INK_OWNED
	end

	if rec.kind ~= "event" then
		-- The door itself is the Journal's VIP portrait (26.4). A plaque that opened a Robux prompt
		-- would be a second till for the same pass standing in the middle of the world, and the one
		-- in the Journal is beside the nine portraits it sells.
		return "\u{1F512} Unlock in the Journal", INK_PRICE
	end

	local entry = GameConfig.GetCharacter(rec.key)
	local now = GameConfig.EventNow()

	-- A rotation champion is up for grabs on ONE of its event's weekends, so "the event is running"
	-- is not the same question as "this skin is being handed out" -- the same distinction 26.3's
	-- Journal card is built on.
	local rot = GameConfig.GetRotationInfo(rec.key, now)
	if rot then
		if rot.live then
			return "\u{1F7E2} LIVE NOW", INK_LIVE
		end
		if rot.nextStart then
			return ("\u{23F3} its turn in %s"):format(GameConfig.FormatDuration(rot.nextStart - now)), INK_WAIT
		end
	end

	local event = entry and GameConfig.GetEvent(entry.event)
	local window = event and GameConfig.GetEventWindow(event, now)
	if window then
		if window.active then
			return "\u{1F7E2} LIVE NOW", INK_LIVE
		end
		if window.nextStart then
			return ("\u{23F3} runs in %s"):format(GameConfig.FormatDuration(window.nextStart - now)), INK_WAIT
		end
	end
	return "\u{1F512} LOCKED", INK_WAIT
end

local function paint(rec)
	setLocked(rec, not rec.owned)
	if not rec.status then return end
	local text, ink = statusFor(rec)
	if rec.status.Text ~= text then
		rec.status.Text = text
	end
	rec.status.TextColor3 = ink
end

-- ============================================================================
-- OWNERSHIP
-- ============================================================================
-- `data.Characters` is the working copy and `data.EventCharacters` is the permanent record; a
-- rebirth empties the first and SyncEventCharacters refills it, so both are read and either counts.
--
-- THE WARDROBE IS TESTED ON THE PASS, NOT ON THE SKIN, and the two disagree for the length of one
-- join: PassService fills `data.Passes` on its own connection with retries, and SyncVipCharacter
-- only writes the nine keys once it has. Testing the skin alone would silhouette a paying VIP's own
-- row for the first seconds of their session, which is 26.4's finding in a different file.
local function ownershipFor(rec)
	local data = lastData
	if type(data) ~= "table" then return false end

	local chars = type(data.Characters) == "table" and data.Characters or {}
	if rec.kind == "vip" then
		return GameConfig.OwnsPass(data, "VIP") or chars[rec.key] == true
	end

	local events = type(data.EventCharacters) == "table" and data.EventCharacters or {}
	return chars[rec.key] == true or events[rec.key] == true
end

-- ============================================================================
-- FINDING THE STANDS
-- ============================================================================
local function adopt(stand)
	local key = stand:GetAttribute("CharacterKey")
	if not key then return end

	local figure = stand:FindFirstChild("Figure")
	if not figure then return end

	local rec = {
		key = key,
		kind = stand:GetAttribute("ExhibitKind") or "vip",
		parts = {},
		colour = {},
		material = {},
		texture = {},
		owned = false,
		-- nil rather than false, so the first `setLocked(rec, true)` actually runs
		locked = nil,
	}
	for _, part in ipairs(figure:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(rec.parts, part)
		end
	end
	if #rec.parts == 0 then return end

	local plaque = stand:FindFirstChild("Plaque")
	local gui = plaque and plaque:FindFirstChild("PlaqueSign")
	local shell = gui and gui:FindFirstChild("Shell")
	rec.status = shell and shell:FindFirstChild("Status")

	rec.owned = ownershipFor(rec)
	table.insert(stands, rec)
	paint(rec)
end

local function onData(data)
	if type(data) ~= "table" then return end
	lastData = data
	for _, rec in ipairs(stands) do
		rec.owned = ownershipFor(rec)
		paint(rec)
	end
end

-- ============================================================================
-- BOOT
-- ============================================================================
local remotes = RS:WaitForChild("Remotes", 30)
local dataUpdate = remotes and remotes:WaitForChild("DataUpdate", 30)
if dataUpdate then
	dataUpdate.OnClientEvent:Connect(onData)
end

task.spawn(function()
	local plaza = workspace:WaitForChild("HubPlaza", 120)
	local exhibit = plaza and plaza:WaitForChild("Exhibit", 60)
	if not exhibit then return end

	for _, stand in ipairs(exhibit:GetChildren()) do
		adopt(stand)
	end
	-- A rebuild behind a bumped PLAZA_VERSION replaces the whole model, and a player standing in the
	-- plaza while a fresh server boots is the ordinary case rather than the exotic one.
	exhibit.ChildAdded:Connect(function(stand)
		task.wait()
		adopt(stand)
	end)

	-- The clocks. One loop for all fourteen plaques rather than a timer each, on the same second the
	-- Season panel's own countdowns tick -- a window that shuts has to take the plaque's offer with
	-- it, and the next DataUpdate is not soon enough to be the thing that notices.
	while true do
		task.wait(1)
		for _, rec in ipairs(stands) do
			if rec.kind == "event" and not rec.owned then
				paint(rec)
			end
		end
	end
end)
