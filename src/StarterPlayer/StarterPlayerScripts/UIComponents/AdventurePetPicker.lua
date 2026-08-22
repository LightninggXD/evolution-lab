-- UIComponents/AdventurePetPicker -- which pet goes (30.6).
--
-- =====================================================================================
-- THE ORDER IS `GameConfig.SortedPetsByPower`, AND `data` IS THE SECOND ARGUMENT
-- =====================================================================================
-- 30.6 names that function for the list, and MainUI's pet grid carries the note about why the
-- second argument is not optional: without `data`, `GetPetPower` drops the zone axis and quotes
-- every pet at its own home zone's strength, so the drawn order stops matching the real one. The
-- route gate (`minPetPower`) is compared against the SAME call on the server, so a picker sorted
-- without it would put a pet at the top of the list that the top route then refuses.
--
-- =====================================================================================
-- THE LIST IS CAPPED, AND THE CHOSEN PET IS ALWAYS IN IT
-- =====================================================================================
-- `GameConfig.MaxOwnedPets` is 600. Six hundred cards, each with a gradient, a stud sheet, two
-- strokes and a button, rebuilt every time this opens, is not a list -- it is a stall. The cap is
-- the strongest 50, which is far past the point where a pet is a sensible thing to send: the whole
-- ladder of `minPetPower` runs 0 to 5.5 and the best un-enchanted pet in the game measures 5.040,
-- so anything outside the top of the collection is choosing between two routes it can both clear.
--
-- The current selection is spliced in even when it ranks below the cap, because the one thing a
-- picker must never do is fail to show you what you already picked.
--
-- =====================================================================================
-- REBUILT, NOT UPDATED -- THE OPPOSITE OF THE ROUTE LIST
-- =====================================================================================
-- `AdventurePanel` keeps its twenty handles because its membership is fixed. This one's is not:
-- hatching, fusing, releasing and sending all change the LENGTH of the list, and the builder's own
-- note says a list whose length changes uses `Clear()`. The scroll position lost with it is the
-- correct trade -- a card that stayed behind after its pet was fused is a button that sends a pet
-- that does not exist.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local SoundLibrary = require(RS.Modules.SoundLibrary)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Common = require(script.Parent:WaitForChild("AdventureCommon"))

local AdventurePetPicker = {}

local panel = nil
local footLine = nil

local SHOWN = 50

-- The list this panel draws: strongest first, capped, with the selection spliced back in if the cap
-- cut it. Returns the list AND the true total, because "showing 50 of 214" is the only thing that
-- stops the cap reading as a bug to a player with a big collection.
local function listFor(data)
	local ranked = GameConfig.SortedPetsByPower(data.Pets, data)
	local total = #ranked
	if total <= SHOWN then return ranked, total end

	local shown = {}
	for i = 1, SHOWN do shown[i] = ranked[i] end

	local chosenId = Common.GetPetId()
	if chosenId then
		local present = false
		for _, pet in ipairs(shown) do
			if pet.id == chosenId then present = true break end
		end
		if not present then
			local chosen = GameConfig.GetPetById(data, chosenId)
			if chosen then shown[#shown + 1] = chosen end
		end
	end
	return shown, total
end

-- Where an away pet is and when it is back, or nil for one that is here. `workspace:GetServerTimeNow()`
-- and never `os.time()`, for the reason `AdventureAwayPanel`'s header sets out at length: `endsAt`
-- was written by the SERVER's wall clock and a client's own may be minutes off it.
local function awayLine(entry)
	if not entry then return nil end
	local route = GameConfig.GetAdventure(entry.routeKey)
	local remaining = GameConfig.GetDispatchRemaining(entry, workspace:GetServerTimeNow())
	return ("away on %s \u{2022} back in %s")
		:format(route and route.name or tostring(entry.routeKey), Common.Countdown(remaining))
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	panel.Clear()
	local pets, total = listFor(data)
	local chosenId = Common.GetPetId()

	for order, pet in ipairs(pets) do
		local def = Common.PetDef(pet)
		local rarity = GameConfig.GetRarity(def and def.rarity)
		local power = GameConfig.GetPetPower(pet, data)
		local entry = GameConfig.GetPetDispatch(data, pet.id)
		local isChosen = pet.id == chosenId

		local description = awayLine(entry) or (isChosen and "this is the pet that goes" or "")

		panel.AddCard({
			Name = tostring(pet.id),
			LayoutOrder = order,
			Title = Common.PetName(pet),
			Subtitle = ("power %.2f  \u{2022}  %s  \u{2022}  %s")
				:format(power, pet.tier or "Normal", (def and def.rarity) or "Common"),
			Description = description,
			-- The RARITY tints the card, not the tier: rarity is the axis a player is choosing on
			-- here, and it is the one the twenty routes' own colours never collide with.
			BackgroundColors = Common.Pastel(rarity.color),
			Buttons = {
				{
					Name = "Choose",
					-- A pet that is away cannot be sent anywhere and the description above already
					-- says so in full, so this one IS disabled rather than left live -- the sentence
					-- a press would print is already on the card.
					Price = entry and "AWAY" or (isChosen and "CHOSEN" or "CHOOSE"),
					Colors = entry and Common.Color.Off
						or (isChosen and Common.Color.Claim or Common.Color.Go),
					Callback = function()
						if entry then return end
						SoundLibrary.PlayLocal("click")
						Common.SetPetId(pet.id)
						-- Straight back to the list that sent you here. The builder's `SetOpen`
						-- closes every other stamped panel first, so this is one screen replacing
						-- another rather than two open at once.
						Common.Open("routes")
					end,
				},
			},
		})
	end

	-- No `ShowEmpty` call: `panel.Clear()` above already raised the notice, and `AddCard` lowers it
	-- again on the first card. Saying it a second time here would be a second authority on it.
	footLine.Text = total > #pets
		and ("Showing your %d strongest of %d pets."):format(#pets, total)
		or ("%d pet%s"):format(total, total == 1 and "" or "s")
end

local function build(screenGui)
	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "AdventurePets",
		Title = "\u{1F43E} Choose a pet",
		EmptyText = "You have no pets yet -- hatch one first!",
		FooterHeight = 58,
	})

	local footer = panel.Footer

	local back = Common.Button(footer, {
		name = "Back",
		-- "BACK" AND NOT "\u{25C0}". FredokaOne has no glyph for U+25C0 and 27.7's finding is that a
		-- missing glyph is LAID OUT AND NOT DRAWN -- `.Text`, `.TextColor3` and `.TextFits` all read
		-- correct on a button that photographs blank.
		text = "BACK",
		size = UDim2.new(0, 140, 0, 44),
		colors = Common.Color.Neutral,
	})
	back.MouseButton1Click:Connect(function()
		SoundLibrary.PlayLocal("close")
		Common.Open("routes")
	end)

	footLine = Common.Line(footer, {
		name = "Count",
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
end

function AdventurePetPicker.Init(screenGui)
	if panel then return AdventurePetPicker end
	build(screenGui)
	Common.Register("pets", AdventurePetPicker)
	return AdventurePetPicker
end

function AdventurePetPicker.SetOpen(open)
	if panel then panel.SetOpen(open) end
end

function AdventurePetPicker.IsOpen()
	return panel ~= nil and panel.IsOpen()
end

function AdventurePetPicker.Refresh()
	if panel then panel.Refresh() end
end

return AdventurePetPicker
