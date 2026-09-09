--[[
	MutationFlair -- what a mutation looks like to somebody who is not wearing it (23.2).

	===== THE ROW, AND THE MEASUREMENT THAT DECIDED THE SHAPE =====

	23.2: *"A mutation is visible from across the map ... A mutation nobody can see is not a flex."*

	The aura is not that. `EvolutionVisuals.AttachMutationAura` hangs a real particle pack on the
	root -- Godly is a seven-emitter tornado up to 11 studs across -- and photographed from **60
	studs** on 2026-09-09 it is a pale patch on the grass you would not name as anything. It is
	correct as the thing you see standing next to somebody; it is not a flex surface, because a
	particle is world-sized and a world-sized thing at 300 studs is a few pixels.

	**THE ONE INSTRUMENT THAT SURVIVES DISTANCE IS A PIXEL-SIZED `BillboardGui`.** A billboard sized
	in studs shrinks exactly like the geometry it hangs over; one sized in PIXELS is the same size
	on screen at 30 studs and at 600, which is why `RarityBeam`'s label is authored that way and why
	the Herald's board is not. So the flex is a chip: the mutation's name, in the mutation's own
	colour, over the head, at a fixed 176 x 44.

	===== RARITY IS THE DISTANCE, NOT A YES/NO =====

	Every mutation gets a chip; what a rarer one buys is being READ FROM FURTHER AWAY. A Common is
	visible at conversational range and a Godly across the whole platform, which is the same ladder
	`GameConfig.Splicer.announceMinIndex` draws for the server-wide announce (23.3) expressed as a
	distance instead of a switch. It also means the top of the ladder is not one more binary badge:
	the thing that makes a Godly worth having is that the other end of the village can see it.

	===== IT STACKS ABOVE THE PARTY CHIP, DELIBERATELY =====

	`PartyFlair` (22.5) owns the chip at +3.4 studs over the head; this one sits at +6.6, so a player
	in a party wearing a mutation reads as two stacked tags rather than two things fighting for one
	spot. Anything else that ever hangs over a head has to take the next rung up and say so here.

	NOT A `Highlight`, and not a beam. `CreatureService` rents 14 of the ~31 Roblox will draw at
	once and one per mutated player would strip the outlines off the world -- the argument
	`VipFlair` and `RarityBeam` both write out. A pillar is what a MOMENT looks like (23.3 fires one
	on the roll); a permanent one per wearer would be a forest.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS:WaitForChild("Modules"):WaitForChild("GameConfig"))

local TAG_NAME = "MutationChip"

-- Studs above the head. See the header: `PartyFlair` owns 3.4.
local CHIP_HEIGHT = 6.6

-- How far away each rung can be read from. The bottom of the ladder is conversational range and
-- the top is the width of a zone platform (1250 studs), which is what "across the map" means here.
-- Index into `GameConfig.Mutations`, so it moves with that table's own rank order.
local READ_DISTANCE = { 90, 130, 190, 280, 420, 620, 900 }

local function rankOf(name)
	if not name then return nil end
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == name then return i, m end
	end
	return nil
end

local function clearChip(character)
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head then return end
	local existing = head:FindFirstChild(TAG_NAME)
	if existing then existing:Destroy() end
end

local function buildChip(character)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then return nil end
	local existing = head:FindFirstChild(TAG_NAME)
	if existing then return existing end

	local scale = character:GetAttribute("BodyScale") or 1

	local gui = Instance.new("BillboardGui")
	gui.Name = TAG_NAME
	-- PIXELS, not studs -- the whole point of the file. See the header.
	gui.Size = UDim2.new(0, 176, 0, 44)
	gui.StudsOffset = Vector3.new(0, CHIP_HEIGHT * scale, 0)
	-- Occluded rather than AlwaysOnTop: a flex you can read through a mountain is not information,
	-- it is a wallhack, and it would also draw for every wearer in the world at once.
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.Parent = head

	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
	shell.BackgroundTransparency = 0.1
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Thickness = 3
	stroke.Parent = shell

	local name = Instance.new("TextLabel")
	name.Name = "MutationName"
	name.Size = UDim2.fromScale(0.92, 0.56)
	name.Position = UDim2.fromScale(0.04, 0.04)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextStrokeColor3 = Color3.fromRGB(12, 10, 20)
	name.TextStrokeTransparency = 0.15
	name.Parent = shell

	local mult = Instance.new("TextLabel")
	mult.Name = "Mult"
	mult.Size = UDim2.fromScale(0.92, 0.34)
	mult.Position = UDim2.fromScale(0.04, 0.6)
	mult.BackgroundTransparency = 1
	mult.Font = Enum.Font.FredokaOne
	mult.TextScaled = true
	mult.TextColor3 = Color3.fromRGB(214, 210, 226)
	mult.TextStrokeColor3 = Color3.fromRGB(12, 10, 20)
	mult.TextStrokeTransparency = 0.2
	mult.Parent = shell

	return gui
end

local function paint(player)
	local character = player.Character
	if not character then return end

	-- The attribute is the channel `SplicerService` stamps and `EvolutionVisuals` re-stamps on the
	-- join path; it is the same one the aura reads, so the chip and the aura can never disagree
	-- about what somebody is wearing.
	local index, mutation = rankOf(player:GetAttribute("Mutation"))
	if not mutation then
		clearChip(character)
		return
	end

	local gui = buildChip(character)
	if not gui then return end
	local shell = gui:FindFirstChild("Shell")
	if not shell then return end

	gui.MaxDistance = READ_DISTANCE[index] or 120
	shell.Edge.Color = mutation.color
	shell.MutationName.TextColor3 = mutation.color
	shell.MutationName.Text = mutation.name:upper()
	-- The multiplier rather than the rarity word twice: what a mutation IS is a number on your
	-- income, and it is the number the wearer is showing off.
	shell.Mult.Text = ("\u{00D7}%.2f income"):format(mutation.incomeMult)
end

local function watch(player)
	player:GetAttributeChangedSignal("Mutation"):Connect(function()
		paint(player)
	end)

	local function hookCharacter(character)
		-- An evolve changes the body's size, and the chip hangs off it: rebuilt rather than moved,
		-- the same rule `VipFlair`'s aura follows.
		character:GetAttributeChangedSignal("BodyScale"):Connect(function()
			clearChip(character)
			paint(player)
		end)
		paint(player)
	end

	player.CharacterAdded:Connect(hookCharacter)
	if player.Character then hookCharacter(player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
