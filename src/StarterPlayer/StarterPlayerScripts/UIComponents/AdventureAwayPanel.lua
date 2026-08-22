-- UIComponents/AdventureAwayPanel -- the pets that are out, and the claim card (30.6).
--
-- =====================================================================================
-- THE COUNTDOWN IS DRAWN OFF `workspace:GetServerTimeNow()`, NEVER `os.time()`
-- =====================================================================================
-- `entry.endsAt` was written by the SERVER's `os.time()`. A client's `os.time()` is its own
-- machine's wall clock, and nothing in Roblox promises the two agree -- a player whose PC clock is
-- four minutes fast would watch every dispatch land four minutes early and then be refused by
-- `AdventureDispatch.Claim`, which is the worst shape this panel could take: a timer that finishes
-- and a button that says no.
--
-- `GetServerTimeNow` is Unix-epoch and synchronised, which is exactly why `AdventureService`'s
-- `pushState` already sends the run's start on it. So `GetDispatchRemaining` is called with an
-- explicit `now` here rather than letting it default.
--
-- =====================================================================================
-- ONE GATED HEARTBEAT FOR THE WHOLE LIST
-- =====================================================================================
-- A dispatch is eight to twenty minutes, so the numbers on this panel change while nobody has
-- pushed anything. That needs a clock of its own -- and it is ONE connection, accumulating, that
-- returns immediately while the panel is shut. The standing rule for animated sets in this project
-- (`evolution-lab-streaming-and-scale`): never one connection per row.
--
-- =====================================================================================
-- REBUILT ONLY WHEN THE MEMBERSHIP CHANGES
-- =====================================================================================
-- Between one and three cards, changing once every eight minutes or so -- so the tick UPDATES the
-- cards it already has and a rebuild happens only when the set of pet ids is genuinely different.
-- A rebuild every second would restart the scroll and flicker the buttons under the cursor.

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local SoundLibrary = require(RS.Modules.SoundLibrary)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Common = require(script.Parent:WaitForChild("AdventureCommon"))

local AdventureAwayPanel = {}

local panel = nil
local footLine = nil
-- [petId] = { card = handle, claim = button, skip = button, entry = ledger entry }
local cards = {}
local builtFor = ""

local TICK = 0.5

local function now()
	return workspace:GetServerTimeNow()
end

-- The membership, as one comparable string. Order comes from the ledger, which only ever has
-- entries appended and removed, so two lists with the same ids in the same order really are the
-- same list.
local function signature(dispatch)
	local ids = {}
	for i, entry in ipairs(dispatch) do
		ids[i] = tostring(entry.petId)
	end
	return table.concat(ids, "|")
end

-- What one card says right now. Split out because BOTH the rebuild and the tick need it, and two
-- copies of this would be two answers to "is it ready yet" on one screen.
local function paint(row)
	local remaining = GameConfig.GetDispatchRemaining(row.entry, now())
	local ready = remaining <= 0

	row.card.SetDescription(ready and "ready to claim!"
		or ("back in %s"):format(Common.Countdown(remaining)))
	row.claim.SetPrice(ready and "CLAIM" or "WAITING")
	row.claim.SetColors(ready and Common.Color.Claim or Common.Color.Off)
	-- NOT a refused state, so not a greyed button: once the pet is home there is no wait left to
	-- buy, and `FinishNow` itself claims for free rather than charging for one. A button offering
	-- to sell you something that has already happened is the one shape of this nobody forgives.
	row.skip.SetVisible(not ready)
end

local function rebuild(data)
	local ledger = GameConfig.GetAdventureLedger(data)
	panel.Clear()
	cards = {}

	for order, entry in ipairs(ledger.Dispatch) do
		local route = GameConfig.GetAdventure(entry.routeKey)
		local pet = GameConfig.GetPetById(data, entry.petId)
		local petId = entry.petId

		local card = panel.AddCard({
			Name = tostring(petId),
			LayoutOrder = order,
			Title = ((route and route.emoji) or "\u{1F5FA}") .. "  "
				.. ((route and route.name) or tostring(entry.routeKey)),
			-- `entry.tier` and not `route.tier`: 30.5 copies the tier onto the entry on purpose, so
			-- a pet that is still out after a change to the zone strip keeps describing the
			-- adventure it was actually sent on.
			Subtitle = ("%s  \u{2022}  tier %d  \u{2022}  luck x%.2f")
				:format(Common.PetName(pet), entry.tier or 1, (route and route.luckMult) or 1),
			Description = "",
			BackgroundColors = Common.Pastel((route and route.accentColor) or Color3.fromRGB(120, 130, 190)),
			Buttons = {
				{
					Name = "Claim",
					Price = "WAITING",
					Colors = Common.Color.Off,
					-- THIS ONE DOES FIRE WHILE IT IS GREY, unlike the route list's two. The sentence
					-- for an early claim ("Still exploring -- back in 4m 12s") lives in
					-- `AdventureDispatch` and NOT in `GetAdventureRefusal`, because it is not one of
					-- the nine states `GetAdventureStatus` decides -- it is a clock. Printing a
					-- client-side copy of it here would be exactly the second wording 30.6 spent the
					-- row deleting, so the server answers instead, in its own words.
					Callback = function()
						SoundLibrary.PlayLocal("click")
						Remotes.AdventureClaim:FireServer(petId)
					end,
				},
				{
					Name = "Skip",
					Price = ("SKIP %d\u{1F48E}"):format(GameConfig.AdventureFinishNowDiamonds),
					Colors = Common.Color.Diamond,
					Callback = function()
						SoundLibrary.PlayLocal("click")
						Remotes.AdventureFinishNow:FireServer(petId)
					end,
				},
			},
		})

		local row = { card = card, claim = card.Buttons.Claim, skip = card.Buttons.Skip, entry = entry }
		cards[tostring(petId)] = row
		paint(row)
	end

	builtFor = signature(ledger.Dispatch)
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local ledger = GameConfig.GetAdventureLedger(data)
	local sig = signature(ledger.Dispatch)
	if sig ~= builtFor then
		rebuild(data)
	else
		-- Same pets, fresh save. The ENTRY TABLES are new objects on every push -- `data` is
		-- replaced wholesale, never mutated -- so the rows have to be re-pointed at them or the
		-- countdown would keep reading a table nothing writes to any more.
		for _, entry in ipairs(ledger.Dispatch) do
			local row = cards[tostring(entry.petId)]
			if row then
				row.entry = entry
				paint(row)
			end
		end
	end

	footLine.Text = ("%d of %d slots in use  \u{2022}  skipping a wait costs %d Diamonds")
		:format(#ledger.Dispatch, GameConfig.GetAdventureSlots(data),
			GameConfig.AdventureFinishNowDiamonds)
end

local function build(screenGui)
	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "AdventureAway",
		Title = "\u{1F9ED} Pets away",
		EmptyText = "No pets are out. Send one from the route list!",
		FooterHeight = 58,
	})

	local footer = panel.Footer

	local back = Common.Button(footer, {
		name = "Back",
		text = "BACK",
		size = UDim2.new(0, 140, 0, 44),
		colors = Common.Color.Neutral,
	})
	back.MouseButton1Click:Connect(function()
		SoundLibrary.PlayLocal("close")
		Common.Open("routes")
	end)

	footLine = Common.Line(footer, {
		name = "Slots",
		size = UDim2.new(1, -160, 0, 44),
		position = UDim2.new(1, 0, 0, 0),
		anchorPoint = Vector2.new(1, 0),
		textSize = 20,
		xAlign = Enum.TextXAlignment.Right,
		color = Color3.fromRGB(236, 236, 250),
	})

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		if panel.IsOpen() then refresh() end
	end)

	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		if not panel.IsOpen() then return end
		since += dt
		if since < TICK then return end
		since = 0
		for _, row in pairs(cards) do
			paint(row)
		end
	end)
end

function AdventureAwayPanel.Init(screenGui)
	if panel then return AdventureAwayPanel end
	build(screenGui)
	Common.Register("away", AdventureAwayPanel)
	return AdventureAwayPanel
end

function AdventureAwayPanel.SetOpen(open)
	if panel then panel.SetOpen(open) end
end

function AdventureAwayPanel.IsOpen()
	return panel ~= nil and panel.IsOpen()
end

function AdventureAwayPanel.Refresh()
	if panel then panel.Refresh() end
end

return AdventureAwayPanel
