local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local SoundLibrary = require(RS.Modules.SoundLibrary)
local Remotes = RS:WaitForChild("Remotes")

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Common = require(script.Parent:WaitForChild("AdventureCommon"))

local EnchantTransferPicker = {}

local panel = nil
local footLine = nil
local sourcePetId = nil

local SHOWN = 50

local function listFor(data)
	local ranked = GameConfig.SortedPetsByPower(data.Pets, data)
	local total = #ranked
	
	local shown = {}
	local count = 0
	for i = 1, total do
		if ranked[i].id ~= sourcePetId then
			count = count + 1
			if count <= SHOWN then
				shown[count] = ranked[i]
			end
		end
	end
	
	return shown, count
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	panel.Clear()
	local pets, total = listFor(data)

	-- Read ONCE for the whole repaint rather than per card: fifty cards asking the same two
	-- questions fifty times is fifty chances for half a list to disagree with the other half.
	local cost = GameConfig.EnchantTransferCost
	local affordable = (data.Diamonds or 0) >= cost

	-- What is being moved. Read off the save rather than captured when the panel was opened: the
	-- source can be re-rolled from the pet board while this list is up.
	local sourceEnchant, sourcePet
	for _, p in ipairs(data.Pets or {}) do
		if p.id == sourcePetId then sourceEnchant = p.enchant; sourcePet = p break end
	end

	-- THE HEADING NAMES THE ENCHANT AND THE PET IT LEAVES. "Choose a Target" over a list of pets
	-- reads as choosing a pet to send somewhere -- the owner asked *"gde odu i da li se vrate"*,
	-- which is the right question to ask of a screen that says that. No pet moves: the enchant
	-- moves, off one pet in the bag and onto another, and both stay exactly where they are. The
	-- title is the one line with room to say so.
	--
	-- SHORT ON PURPOSE. The first version named the source pet too ("Move Prismatic off Absolon")
	-- and the heading is not wide enough for it: it rendered as "Move Prismatic off ..." with the
	-- pet's name -- the informative half -- cut off. `TextBounds` calls that fitting, so the only
	-- way to know is to look at it. Which pet it leaves is the one the player just clicked; the
	-- enchant's name is the part they cannot see from here.
	local movingDef = GameConfig.GetEnchantDef(sourceEnchant)
	panel.SetTitle(("\u{2728} Move %s"):format(movingDef and movingDef.name or tostring(sourceEnchant)))

	for order, pet in ipairs(pets) do
		local def = Common.PetDef(pet)
		local rarity = GameConfig.GetRarity(def and def.rarity)
		local power = GameConfig.GetPetPower(pet, data)
		local entry = GameConfig.GetPetDispatch(data, pet.id)
		
		local description = ""
		if entry then
			local route = GameConfig.GetAdventure(entry.routeKey)
			local remaining = GameConfig.GetDispatchRemaining(entry, workspace:GetServerTimeNow())
			description = ("away on %s \u{2022} back in %s"):format(route and route.name or tostring(entry.routeKey), Common.Countdown(remaining))
		end

		local wornEnchant = pet.enchant
		if wornEnchant then
			local enchantDef = GameConfig.GetEnchantDef(wornEnchant)
			description = description == "" and ("Wears: %s"):format(enchantDef and enchantDef.name or wornEnchant) or description
		end

		-- WHY A TARGET CAN BE REFUSED, AND THE FOUR ANSWERS ON THE BUTTON. A button that says
		-- TRANSFER and is then refused teaches the player the UI is lying to them -- the same rule
		-- `PetDetail` states over RELEASE. `AWAY` was already here; the PRICE was missing (this was
		-- the only purchase surface in the game that never quoted its own); and `HAS BETTER` is the
		-- one that cost the owner a prismatic and 1,000 diamonds on the day this shipped.
		--
		-- THE ORDER MATTERS AND IT IS NOT ARBITRARY. `HAS BETTER` is tested before `NEED` because a
		-- row that can never be worth pressing should say WHY it is dead, not send the player off
		-- to earn diamonds they would then waste on it. `IsEnchantBetter` is the same strict
		-- comparison the server refuses with, quoted rather than re-derived -- a tie is not better.
		local reason
		if entry then
			reason = "AWAY"
		elseif not GameConfig.IsEnchantBetter(sourceEnchant, pet.enchant) then
			reason = "HAS BETTER"
		elseif not affordable then
			reason = "NEED \u{1F48E}"
		end

		panel.AddCard({
			Name = tostring(pet.id),
			LayoutOrder = order,
			Title = Common.PetName(pet),
			Subtitle = ("power %.2f  \u{2022}  %s  \u{2022}  %s")
				:format(power, pet.tier or "Normal", (def and def.rarity) or "Common"),
			Description = description,
			BackgroundColors = Common.Pastel(rarity.color),
			Buttons = {
				{
					Name = "Transfer",
					Price = reason or ("\u{1F48E} %d"):format(cost),
					Colors = reason and Common.Color.Off or Common.Color.Go,
					Callback = function()
						if reason then return end
						SoundLibrary.PlayLocal("click")
						Remotes.EnchantTransfer:FireServer(sourcePetId, pet.id)
						EnchantTransferPicker.SetOpen(false)
					end,
				},
			},
		})
	end

	-- THE FOOTER IS WHERE THE PRICE LIVES, not the header: the header is the question and this is
	-- what the answer costs. It quotes the balance beside it for the same reason the shop rows do
	-- -- a player eight hundred diamonds short should be able to see that without closing the panel
	-- to go and look at the wallet -- and it states the thing the whole screen was failing to say:
	-- BOTH PETS STAY. Nothing is sent anywhere and nothing has to come back.
	-- The balance is NOT quoted here any more: it did not fit beside the rest, and the wallet is on
	-- screen behind this panel while every button already says `NEED` when it cannot be paid.
	footLine.Text = ("\u{1F48E} %d \u{2022} both pets stay, only the enchant moves"):format(cost)
end

local function build(screenGui)
	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "EnchantTransferPets",
		-- Placeholder only: `refresh` retitles this with the enchant's own name and the pet it is
		-- leaving, which it cannot do here because no source is chosen until the panel is opened.
		Title = "\u{2728} Move an enchant",
		EmptyText = "No other pet can take this enchant right now.",
		FooterHeight = 58,
	})

	local footer = panel.Footer

	local back = Common.Button(footer, {
		name = "Back",
		text = "CANCEL",
		size = UDim2.new(0, 140, 0, 44),
		colors = Common.Color.Neutral,
	})
	back.MouseButton1Click:Connect(function()
		SoundLibrary.PlayLocal("close")
		EnchantTransferPicker.SetOpen(false)
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

function EnchantTransferPicker.Init(screenGui)
	if panel then return EnchantTransferPicker end
	build(screenGui)
	return EnchantTransferPicker
end

function EnchantTransferPicker.SetOpen(open, sid)
	if panel then 
		if open then
			sourcePetId = sid
		end
		panel.SetOpen(open) 
	end
end

function EnchantTransferPicker.IsOpen()
	return panel ~= nil and panel.IsOpen()
end

function EnchantTransferPicker.Refresh()
	if panel then panel.Refresh() end
end

return EnchantTransferPicker