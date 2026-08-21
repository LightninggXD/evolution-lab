--[[
	ExpeditionUI -- the briefing at the door, the seal tracker while you are inside, and the card at
	the end (Phase 29).

	=========================================================================================
	WHY THIS IS ITS OWN LOCALSCRIPT AND NOT A BLOCK IN MainUI
	=========================================================================================
	MainUI is AT Luau's 200 top-level register cap. One more top-level local there deletes the whole
	HUD, silently, at load -- it has happened twice. SplicerUI, HatchReveal, EvolveReveal and
	MinigameUI are the same decision made four times before this one.

	=========================================================================================
	THE PANEL QUOTES THE SERVER'S OWN FUNCTION
	=========================================================================================
	`GameConfig.GetExpeditionStatus` is pure over the save, so the runs-left on the briefing is not a
	client-side estimate of it -- it is the same call the server refuses an entry with, against the
	same payload the server just pushed. The two cannot drift.

	=========================================================================================
	IT DOES NOT DRAW THE GAMES, AND IT DOES NOT DRAW THE STATION RESULT EITHER
	=========================================================================================
	A station plays through `MinigameUI` untouched -- the server hands it the arcade's own session
	shape with `channel = "expedition"` on it. What comes back here is the OUTCOME: a seal lights up
	on the tracker. Two panels, one each, and neither reaches into the other.

	=========================================================================================
	THE DOOR IS DISSOLVED HERE, AND THAT IS THE WHOLE TRICK
	=========================================================================================
	The expedition map is shared -- there is no instancing in this game -- so the sealed door is one
	part that two players with different progress are both standing in front of. The server builds it
	solid and never touches it again. This file sets `CanCollide = false` on the LOCAL copy once the
	server says the seals are held, which works because an anchored part's collision against your own
	character is resolved on your machine. Nothing replicates; the player beside you still sees a
	wall.

	It is an illusion and it is allowed to be one: `ExpeditionService.HandleOpenChest` re-checks the
	seals on the server, so walking through early lands you in a room with a chest that refuses you.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SoundLibrary = require(ReplicatedStorage.Modules.SoundLibrary)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Declared one per line rather than as `local a, b, c`. That comma form is valid Luau and reads
-- better, but `tools/luanames.py` MIS-PARSES it -- see the same note in SplicerUI.
local currentData = nil
local expeditionKey = nil
local runState = nil
local modal = nil
local content = nil
local briefing = nil
local resultPane = nil
local briefLines = nil
local resultLines = nil
local enterButton = nil
local againButton = nil
local tracker = nil
local trackerRows = nil
local trackerTotal = nil
local leaveButton = nil

local ZB = 0

local gui = Instance.new("ScreenGui")
gui.Name = "ExpeditionUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9
gui.Parent = playerGui

local function label(parent, text, size, position, opts)
	opts = opts or {}
	return UITheme.Label(parent, {
		text = text,
		size = size,
		position = position,
		zIndex = opts.zIndex or (ZB + 2),
		xAlign = opts.xAlign,
		color = opts.color,
		maxTextSize = opts.maxTextSize or 24,
		wrapped = opts.wrapped,
	})
end

-- ============================================================================
-- THE PANEL
-- ============================================================================
local function build()
	local m, c, close = UITheme.Modal(gui, {
		name = "ExpeditionPanel",
		title = "\u{1F5FA} Expedition",
		size = UDim2.new(0, 620, 0, 500),
		accent = Color3.fromRGB(30, 34, 46),
	})
	modal, content = m, c
	ZB = content.ZIndex + UITheme.Z.Content

	close.Activated:Connect(function()
		SoundLibrary.PlayLocal("close")
		modal.Visible = false
	end)

	briefing = Instance.new("Frame")
	briefing.Name = "Briefing"
	briefing.BackgroundTransparency = 1
	briefing.Size = UDim2.new(1, -32, 1, -32)
	briefing.Position = UDim2.new(0, 16, 0, 16)
	briefing.ZIndex = ZB
	briefing.Parent = content

	briefLines = {}
	briefLines.title = label(briefing, "", UDim2.new(1, 0, 0, 46), UDim2.new(0, 0, 0, 4),
		{ maxTextSize = 36 })
	briefLines.blurb = label(briefing, "", UDim2.new(1, 0, 0, 88), UDim2.new(0, 0, 0, 56),
		{ maxTextSize = 20, wrapped = true, color = Color3.fromRGB(226, 224, 244) })
	briefLines.route = label(briefing, "", UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 152),
		{ maxTextSize = 22, color = UITheme.Color.Aqua })
	briefLines.best = label(briefing, "", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 192),
		{ maxTextSize = 20, color = UITheme.Color.Gold })
	briefLines.status = label(briefing, "", UDim2.new(1, 0, 0, 58), UDim2.new(0, 0, 0, 228),
		{ maxTextSize = 20, wrapped = true, color = Color3.fromRGB(206, 204, 232) })

	enterButton = UITheme.Button(briefing, {
		name = "Enter",
		text = "ENTER",
		color = UITheme.Color.Green,
		size = UDim2.new(0, 260, 0, 50),
		position = UDim2.new(0.5, 0, 1, -70),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = ZB + 2,
		maxTextSize = 30,
	})

	resultPane = Instance.new("Frame")
	resultPane.Name = "Result"
	resultPane.BackgroundTransparency = 1
	resultPane.Size = UDim2.new(1, -32, 1, -32)
	resultPane.Position = UDim2.new(0, 16, 0, 16)
	resultPane.ZIndex = ZB
	resultPane.Visible = false
	resultPane.Parent = content

	resultLines = {}
	resultLines.title = label(resultPane, "", UDim2.new(1, 0, 0, 48), UDim2.new(0, 0, 0, 10),
		{ maxTextSize = 38 })
	resultLines.score = label(resultPane, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 72),
		{ maxTextSize = 30, color = UITheme.Color.White })
	resultLines.best = label(resultPane, "", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 118),
		{ maxTextSize = 22, color = UITheme.Color.Gold })
	resultLines.chest = label(resultPane, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 160),
		{ maxTextSize = 28, color = UITheme.Color.Lavender })
	resultLines.diamonds = label(resultPane, "", UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 206),
		{ maxTextSize = 24, color = UITheme.Color.SkyBlue })
	resultLines.status = label(resultPane, "", UDim2.new(1, 0, 0, 54), UDim2.new(0, 0, 0, 248),
		{ maxTextSize = 20, wrapped = true, color = Color3.fromRGB(206, 204, 232) })

	againButton = UITheme.Button(resultPane, {
		name = "Close",
		text = "DONE",
		color = UITheme.Color.Blue,
		size = UDim2.new(0, 260, 0, 50),
		position = UDim2.new(0.5, 0, 1, -70),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = ZB + 2,
		maxTextSize = 30,
	})
end

-- ============================================================================
-- THE SEAL TRACKER
-- ============================================================================
-- Always on screen while a run is live, and deliberately NOT inside the modal: the whole point of it
-- is to be readable while walking between chambers, which is exactly when a modal is shut. Top
-- centre, the band 16.2 established as idle (currencies top-left, tiles down both sides) and where
-- the world event clock already lives -- it is hidden whenever this is up, since a run is short and
-- nothing else about the world matters during one.
local function buildTracker()
	tracker = Instance.new("Frame")
	tracker.Name = "SealTracker"
	tracker.AnchorPoint = Vector2.new(0.5, 0)
	tracker.Position = UDim2.new(0.5, 0, 0, 148)
	tracker.Size = UDim2.new(0, 300, 0, 84)
	tracker.BackgroundColor3 = Color3.fromRGB(26, 24, 40)
	tracker.BackgroundTransparency = 0.15
	tracker.BorderSizePixel = 0
	tracker.ZIndex = 40
	tracker.Visible = false
	tracker.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = tracker

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(12, 10, 20)
	stroke.Parent = tracker

	trackerTotal = Instance.new("TextLabel")
	trackerTotal.Name = "Total"
	trackerTotal.BackgroundTransparency = 1
	trackerTotal.Size = UDim2.new(1, -16, 0, 24)
	trackerTotal.Position = UDim2.new(0, 8, 0, 6)
	trackerTotal.Font = UITheme.Font.Display
	trackerTotal.TextScaled = true
	trackerTotal.TextColor3 = Color3.fromRGB(255, 255, 255)
	trackerTotal.Text = ""
	trackerTotal.ZIndex = 42
	trackerTotal.Parent = tracker

	local row = Instance.new("Frame")
	row.Name = "Seals"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -16, 0, 44)
	row.Position = UDim2.new(0, 8, 0, 34)
	row.ZIndex = 41
	row.Parent = tracker

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row

	trackerRows = row
end

-- Rebuilt rather than reconciled: a run has three seals and rebuilding three frames costs nothing,
-- while a reconcile has to know what changed. The panel-refresh rule the whole HUD follows.
local function refreshTracker()
	if not runState or not runState.running then
		tracker.Visible = false
		return
	end
	tracker.Visible = true

	local expedition = GameConfig.GetExpedition(runState.key)
	if not expedition then return end

	trackerRows:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = trackerRows

	for index, station in ipairs(expedition.stations) do
		local held = runState.symbols and runState.symbols[index]
		local chip = Instance.new("TextLabel")
		chip.Name = "Seal" .. index
		chip.Size = UDim2.new(0, 44, 0, 44)
		chip.BackgroundColor3 = held and station.color or Color3.fromRGB(52, 48, 72)
		chip.BorderSizePixel = 0
		chip.Font = UITheme.Font.Display
		chip.Text = station.symbol
		chip.TextScaled = true
		-- An unearned seal is shown at low contrast rather than hidden, so the route's LENGTH is
		-- legible from the first chamber -- the same choice the Auras panel makes for tiers the
		-- player has not found.
		chip.TextTransparency = held and 0 or 0.62
		chip.LayoutOrder = index
		chip.ZIndex = 42
		chip.Parent = trackerRows

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = chip
	end

	trackerTotal.Text = ("%d  \u{2022}  %d / %d seals")
		:format(runState.total or 0, runState.sealsHeld or 0, #expedition.stations)
end

-- ============================================================================
-- THE DOOR
-- ============================================================================
-- Local-only. See the header for why this is allowed to be an illusion.
local function applyDoor()
	local zones = workspace:FindFirstChild("Zones")
	if not zones then return end

	for _, map in ipairs(zones:GetChildren()) do
		local key = map:GetAttribute("ExpeditionKey")
		if key then
			local door = map:FindFirstChild("SymbolDoor", true)
			if door then
				local open = runState ~= nil and runState.running == true
					and runState.key == key and runState.sealed == true
				door.CanCollide = not open
				-- LocalTransparencyModifier rather than Transparency: it is a client-only property
				-- by design, so nothing here can be replicated back by a later server write, and
				-- the server's own authored 0.25 stays the thing every other player sees.
				door.LocalTransparencyModifier = open and 0.85 or 0
			end
		end
	end
end

-- ============================================================================
-- SCREENS
-- ============================================================================
local function showBriefing()
	briefing.Visible = true
	resultPane.Visible = false

	local status = GameConfig.GetExpeditionStatus(currentData, expeditionKey)
	local expedition = status.expedition
	if not expedition then return end

	UITheme.SetText(briefLines.title, expedition.emoji .. "  " .. expedition.name)
	UITheme.SetText(briefLines.blurb, expedition.blurb)

	local route = {}
	for index, station in ipairs(expedition.stations) do
		local kind = GameConfig.GetStationKind(expedition, index)
		route[#route + 1] = station.symbol .. " " .. (kind and kind.name or station.kind)
	end
	UITheme.SetText(briefLines.route, table.concat(route, "   \u{2192}   "))

	UITheme.SetText(briefLines.best, ("Your best: %d   \u{2022}   Par: %d   \u{2022}   Cleared %dx")
		:format(status.best, status.par, status.cleared))

	if status.ready then
		UITheme.SetText(briefLines.status,
			("Clear all %d stations to seal the vault.\n%d of %d expeditions left today.")
				:format(status.stations, status.runsLeft, status.dailyRuns))
		enterButton.Visible = true
	else
		enterButton.Visible = false
		if status.reason == "capped" then
			UITheme.SetText(briefLines.status,
				("That is both expeditions for today.\nThe board resets at midnight UTC."))
		elseif status.reason == "stage" then
			UITheme.SetText(briefLines.status,
				("%s opens at stage %d."):format(expedition.name, expedition.minStageIndex or 1))
		else
			UITheme.SetText(briefLines.status, "That expedition is not available.")
		end
	end
end

-- ============================================================================
-- WIRING
-- ============================================================================
build()
buildTracker()

enterButton.Activated:Connect(function()
	SoundLibrary.PlayLocal("click")
	modal.Visible = false
	Remotes.ExpeditionEnter:FireServer(expeditionKey)
end)

againButton.Activated:Connect(function()
	SoundLibrary.PlayLocal("click")
	modal.Visible = false
end)

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
	currentData = data
	-- Only while the briefing is what is on screen. A push landing mid-run must not redraw a panel
	-- the player is not looking at, and must never reopen one.
	if modal.Visible and briefing.Visible then
		showBriefing()
	end
end)

Remotes.ExpeditionState.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	runState = payload.running and payload or nil
	if runState then
		-- `sealsHeld` is derived here rather than sent, because the server already sends the whole
		-- symbol table and two numbers that can disagree is a bug waiting to happen.
		local held = 0
		for _, got in pairs(payload.symbols or {}) do
			if got then held += 1 end
		end
		runState.sealsHeld = held
	end
	refreshTracker()
	applyDoor()
end)

-- A station's OUTCOME. `MinigameUI` has already torn its own panel down off this same remote (it
-- listens for the start half); all that is left here is the sound and the seal, and the seal itself
-- arrives separately on `ExpeditionState` because the server is the only thing that counts them.
Remotes.ExpeditionStation.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.ok and payload.finished then
		SoundLibrary.PlayLocal(payload.beatPar and "levelUp" or "collect")
	end
end)

Remotes.ExpeditionResult.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or not payload.ok then return end
	runState = nil
	refreshTracker()
	applyDoor()

	briefing.Visible = false
	resultPane.Visible = true
	modal.Visible = true

	UITheme.SetText(resultLines.title, payload.beatPar and "\u{2B50} Vault cleared!" or "Vault opened")
	UITheme.SetText(resultLines.score, ("Total  %d"):format(payload.total))
	UITheme.SetText(resultLines.best, payload.newBest
		and ("\u{1F3C6} New personal best!  \u{2022}  Par %d"):format(payload.par)
		or ("Best %d  \u{2022}  Par %d"):format(payload.best or 0, payload.par))
	UITheme.SetText(resultLines.chest, ("+%d Relic Chest%s")
		:format(payload.chests, payload.chests == 1 and "" or "s"))
	UITheme.SetText(resultLines.diamonds, payload.diamonds > 0
		and ("+%d Diamonds"):format(payload.diamonds)
		or "")
	UITheme.SetText(resultLines.status, payload.runsLeft > 0
		and ("%d expedition%s left today."):format(payload.runsLeft, payload.runsLeft == 1 and "" or "s")
		or "That is both expeditions for today.")

	SoundLibrary.PlayLocal(payload.newBest and "levelUp" or "purchase")
end)

-- ===== THE THREE PROMPTS =====
-- One handler, three attribute values, on the contract SplicerUI established and the arcade reused.
-- The station and the chest go straight to the server rather than opening a panel first: there is
-- nothing to decide at either one, and a confirm box in front of a button the player walked across a
-- room to press is a second press for no information.
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local panel = prompt:GetAttribute("ShopPanel")

	if panel == "expedition" then
		expeditionKey = prompt:GetAttribute("ExpeditionKey")
		if not expeditionKey then return end
		SoundLibrary.PlayLocal("open")
		showBriefing()
		modal.Visible = true

	elseif panel == "expedition_station" then
		local index = prompt:GetAttribute("StationIndex")
		if not index then return end
		SoundLibrary.PlayLocal("click")
		Remotes.StationStart:FireServer(index)

	elseif panel == "expedition_chest" then
		SoundLibrary.PlayLocal("click")
		Remotes.ExpeditionChest:FireServer()
	end
end)

-- The map is built before any client exists, but a client that streams it in late -- or respawns --
-- would otherwise find a door still solid from before its seals were pushed. Re-applying on
-- CharacterAdded costs one loop over a handful of models and closes that window.
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	applyDoor()
end)
