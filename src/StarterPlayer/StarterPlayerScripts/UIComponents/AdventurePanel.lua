-- UIComponents/AdventurePanel -- the twenty routes, and the two buttons on each of them (30.6).
--
-- =====================================================================================
-- WHY THERE ARE TWO BUTTONS AND NOT ONE
-- =====================================================================================
-- `GetAdventureStatus` answers for both at once -- `ready`/`reason` for PLAY and `canSend`/
-- `sendReason` for SEND -- and 30.1 wrote it that way because the two refuse for genuinely
-- different reasons: a spent daily run stops PLAY and leaves SEND ready, a full dispatch slot stops
-- SEND and leaves PLAY ready. A single `ready` boolean would grey out the wrong button half the
-- time, which is worse than no state at all.
--
-- =====================================================================================
-- A REFUSED BUTTON IS GREYED AND STILL PRESSABLE, AND THAT IS THE DESIGN
-- =====================================================================================
-- The builder's own `SetEnabled(false)` greys a button AND swallows its click. That is right for a
-- shop tile whose price is printed beside it and wrong here, because the reason a route refuses is
-- a SENTENCE -- "Overgrowth Trail wants a pet of power 2.81 -- yours is 1.20" -- and there is
-- nowhere on a 604 x 140 card to print one. Measured: the card's text column is 414 px wide, which
-- is about 46 characters of the 18 pt description font, and that sentence is 62. Printing it there
-- would truncate, and `roblox-textbounds-reports-the-truncation` is the standing note that a
-- truncated label reports bounds that FIT -- no probe would ever catch it, only a capture.
--
-- So the button is greyed with the builder's own disabled pair and left live, and pressing it
-- writes the refusal into the footer line, WRAPPED, at 630 px. The string is
-- `GameConfig.GetAdventureRefusal`'s, never rewritten here -- it is the same sentence the server
-- would have sent down `Remotes.Notify` had the press been allowed through, which is the whole
-- reason 30.6 moved those five strings out of `AdventureService` and `AdventureDispatch`.
--
-- AND THE PRESS DOES NOT REACH THE SERVER. Both doors carry a 0.6 s per-player cooldown
-- (`AdventureRemotes`), so firing a request the client already knows will be refused would spend
-- the window the real press needs.
--
-- =====================================================================================
-- THE CARDS ARE BUILT ONCE AND UPDATED, NEVER REBUILT
-- =====================================================================================
-- Membership is fixed at twenty -- one route per zone, derived from the strip at load -- and the
-- server pushes a DataUpdate about every three seconds. `ZonePanel`'s rule: a rebuild on every push
-- throws the scroll position away while the player is reaching for a button.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local SoundLibrary = require(RS.Modules.SoundLibrary)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Common = require(script.Parent:WaitForChild("AdventureCommon"))

local AdventurePanel = {}

local panel = nil
local rows = {}
local petButton, petButtonColors = nil, nil
local awayButton = nil
local footLine = nil

-- The three lines a card carries, at the three sizes the builder draws them.
local function subtitleFor(route)
	return ("T%d  \u{2022}  luck x%.2f  \u{2022}  par %s  \u{2022}  trip %dm")
		:format(route.tier, route.luckMult, Common.Clock(route.parSeconds), route.autoMinutes)
end

-- STATS, NOT A REFUSAL. Every number on this line is one `GetAdventureStatus` already returns, so
-- it is not a second wording of anything -- a player who can read "pet 2.81+ (you 1.20)" knows why
-- PLAY is grey before they press it, and pressing it still prints the sentence.
local function descriptionFor(status)
	local parts = {}
	parts[#parts + 1] = status.best > 0
		and ("best " .. Common.ClockTenths(status.best))
		or "no time yet"
	if status.cleared > 0 then
		parts[#parts + 1] = ("x%d"):format(status.cleared)
	end
	if status.minPetPower > 0 then
		parts[#parts + 1] = ("pet %.2f+ (you %.2f)"):format(status.minPetPower, status.petPower)
	else
		parts[#parts + 1] = "any pet"
	end
	return table.concat(parts, "  \u{2022}  ")
end

-- The footer's own line, and the only place a refusal SENTENCE is drawn. Cleared back to the
-- counters by the next refresh, so it never sits there describing a state that has passed.
local function say(text, color)
	if not footLine then return end
	footLine.Text = text or ""
	footLine.TextColor3 = color or Color3.fromRGB(255, 236, 236)
end

local function counterLine(status)
	if not status then return "" end
	return ("%d of %d adventures left today  \u{2022}  %d of %d pets can still be sent  \u{2022}  %d/%d away")
		:format(status.runsLeft, status.dailyRuns, status.dispatchLeft, status.dailyDispatch,
			status.slotsUsed, status.slots)
end

-- ===== ONE PRESS, BOTH DOORS =====
-- `which` is "play" or "send", and it is the same word `GetAdventureRefusal` takes -- so the branch
-- that decides which remote to fire and the branch that decides which sentence to print cannot
-- drift apart.
local function press(route, which)
	local data = PlayerData.Get()
	if not data then return end
	local pet = Common.Resolve(data)
	local status = GameConfig.GetAdventureStatus(data, route.key, pet)

	local allowed = (which == "send") and status.canSend or status.ready
	if not allowed then
		SoundLibrary.PlayLocal("error")
		say(GameConfig.GetAdventureRefusal(status, which))
		return
	end

	SoundLibrary.PlayLocal("click")
	if which == "send" then
		Remotes.AdventureSend:FireServer(route.key, pet.id)
		-- STAYS OPEN. Sending is a thing you do several times in a row -- up to three slots and five
		-- a day -- and a panel that shut after each one would make the second send four clicks.
		say(("%s %s is on the way to %s."):format(route.emoji, Common.PetName(pet), route.name),
			Color3.fromRGB(214, 255, 226))
	else
		Remotes.AdventureEnter:FireServer(route.key, pet.id)
		-- SHUTS. The next thing that happens is a screen cover and a course, and a panel left open
		-- over it is what the player lands looking at.
		panel.SetOpen(false)
	end
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end
	local pet = Common.Resolve(data)

	local last = nil
	for _, row in ipairs(rows) do
		local status = GameConfig.GetAdventureStatus(data, row.route.key, pet)
		last = status

		row.card.SetSubtitle(subtitleFor(row.route))
		row.card.SetDescription(descriptionFor(status))

		local playTag = Common.Tag(status.reason)
		row.play.SetPrice(playTag or "PLAY")
		row.play.SetColors(playTag and Common.Color.Off or Common.Color.Go)

		local sendTag = Common.Tag(status.sendReason)
		row.send.SetPrice(sendTag or "SEND")
		row.send.SetColors(sendTag and Common.Color.Off or Common.Color.Send)
	end

	-- The footer, and it is deliberately painted AFTER the rows: `Resolve` may have moved the
	-- selection to a different pet on this very push (the old one was fused, or came home), and the
	-- caption has to name the pet the buttons above it would actually send.
	if pet then
		petButton.Text = ("PET:  %s  \u{2022}  %.2f"):format(
			Common.PetName(pet), GameConfig.GetPetPower(pet, data))
		petButtonColors(Common.Color.Neutral)
	else
		petButton.Text = "PET:  none available"
		petButtonColors(Common.Color.Off)
	end

	awayButton.Text = ("AWAY  %d/%d"):format(last and last.slotsUsed or 0, last and last.slots or 1)
	say(counterLine(last), Color3.fromRGB(236, 236, 250))
end

local function build(screenGui)
	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Adventure",
		Title = "\u{1F5FA} Adventures",
		EmptyText = "No routes are open yet.",
		-- 44 for the two buttons, 8 of air, 44 for two lines of a wrapped refusal, plus the 10 px
		-- the builder takes off the frame's own height. See the header for why that sentence needs
		-- two lines at this width.
		FooterHeight = 106,
	})

	local footer = panel.Footer

	petButton, petButtonColors = Common.Button(footer, {
		name = "PetPicker",
		text = "PET:  ...",
		size = UDim2.new(0, 340, 0, 44),
		colors = Common.Color.Neutral,
		textSize = 22,
	})
	petButton.MouseButton1Click:Connect(function()
		SoundLibrary.PlayLocal("open")
		Common.Open("pets")
	end)

	awayButton = Common.Button(footer, {
		name = "Away",
		text = "AWAY  0/1",
		size = UDim2.new(0, 180, 0, 44),
		position = UDim2.new(1, 0, 0, 0),
		anchorPoint = Vector2.new(1, 0),
		colors = Common.Color.Claim,
		textSize = 22,
	})
	awayButton.MouseButton1Click:Connect(function()
		SoundLibrary.PlayLocal("open")
		Common.Open("away")
	end)

	footLine = Common.Line(footer, {
		name = "Status",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.new(0, 0, 0, 52),
		textSize = 20,
		color = Color3.fromRGB(236, 236, 250),
	})
	-- WRAPPED AND NOT TRUNCATED, which is the whole point of the footer existing. `Common.Line`
	-- truncates by default because every other caller of it is a single fixed line.
	footLine.TextTruncate = Enum.TextTruncate.None
	footLine.TextWrapped = true

	for _, route in ipairs(GameConfig.AdventureList) do
		local card = panel.AddCard({
			Name = route.key,
			LayoutOrder = route.tier,
			Title = route.emoji .. "  " .. route.name,
			Subtitle = subtitleFor(route),
			Description = "",
			-- The route paints itself out of the zone it is themed on, exactly as the course does.
			BackgroundColors = Common.Pastel(route.accentColor),
			Buttons = {
				{ Name = "Play", Price = "PLAY", Colors = Common.Color.Go,
					Callback = function() press(route, "play") end },
				{ Name = "Send", Price = "SEND", Colors = Common.Color.Send,
					Callback = function() press(route, "send") end },
			},
		})
		rows[#rows + 1] = {
			route = route,
			card = card,
			play = card.Buttons.Play,
			send = card.Buttons.Send,
		}
	end

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		if panel.IsOpen() then refresh() end
	end)
	-- The picker writes the selection and this panel is what it writes it FOR, so the caption and
	-- all forty buttons have to move with it whether or not a push happens to be due.
	Common.OnPetChanged(function()
		if panel.IsOpen() then refresh() end
	end)
end

function AdventurePanel.Init(screenGui)
	if panel then return AdventurePanel end
	build(screenGui)
	Common.Register("routes", AdventurePanel)
	return AdventurePanel
end

function AdventurePanel.SetOpen(open)
	if panel then panel.SetOpen(open) end
end

function AdventurePanel.IsOpen()
	return panel ~= nil and panel.IsOpen()
end

function AdventurePanel.Refresh()
	if panel then panel.Refresh() end
end

return AdventurePanel
