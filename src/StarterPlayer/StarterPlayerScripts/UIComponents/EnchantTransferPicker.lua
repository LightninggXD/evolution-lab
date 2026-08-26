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
					Price = entry and "AWAY" or "TRANSFER",
					Colors = entry and Common.Color.Off or Common.Color.Go,
					Callback = function()
						if entry then return end
						SoundLibrary.PlayLocal("click")
						Remotes.EnchantTransfer:FireServer(sourcePetId, pet.id)
						EnchantTransferPicker.SetOpen(false)
					end,
				},
			},
		})
	end

	footLine.Text = total > #pets
		and ("Showing %d of %d pets."):format(#pets, total)
		or ("%d pet%s"):format(total, total == 1 and "" or "s")
end

local function build(screenGui)
	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "EnchantTransferPets",
		Title = "\u{1F48E} Choose a Target",
		EmptyText = "You have no other pets to transfer to!",
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