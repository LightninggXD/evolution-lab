--[[
	PartyFlair -- the part of a party that other people can see (22.5).

	A chip over the head of everybody who is in one: the party's colour, the party's name, and the
	live "+N% together" that member is actually being paid this second. It is the whole visible
	treatment the row asks for.

	DRAWN ENTIRELY ON THE CLIENT off the attributes `PartyService` stamps -- `PartyId`, `PartyColor`,
	`PartyName`, `PartyNear`, `PartyPct`. An attribute replicates to every client on its own, so
	there is no remote here, no join handshake, and a client that arrives in the middle of somebody
	else's party reads the current state for free. It is the same no-remote trick 11.20's countdown
	and 7.1's live events use, and `VipFlair` is the precedent for the shape of this whole file.

	NOT A `Highlight`, for the reason `VipFlair` writes out at length: Roblox renders about 31 at
	once and `CreatureService` already rents fourteen for creature outlines. A party of six would
	take the outlines off the world. A `BillboardGui` costs nothing from that pool.

	IT IS DRAWN OVER YOUR OWN HEAD TOO. Roblox's default camera is third person, so you can see your
	own chip -- which is what makes the treatment provable without a second player in the server,
	and is also just correct: you should be able to see which party you are in.
]]

local Players = game:GetService("Players")

local TAG_NAME = "PartyChip"

local function clearChip(character)
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head then return end
	local existing = head:FindFirstChild(TAG_NAME)
	if existing then existing:Destroy() end
end

local function buildChip(player, character)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then return nil end
	local existing = head:FindFirstChild(TAG_NAME)
	if existing then return existing end

	-- SIZED OFF THE BODY, like everything else in this game. `BodyScale` is stamped on the
	-- character by `EvolutionVisuals.ApplyStage`; the player's own body stopped growing in 30.14,
	-- but a costume can still change the number and a chip parked inside a head is worse than none.
	local scale = character:GetAttribute("BodyScale") or 1

	local gui = Instance.new("BillboardGui")
	gui.Name = TAG_NAME
	gui.Size = UDim2.new(0, 168, 0, 46)
	gui.StudsOffset = Vector3.new(0, 3.4 * scale, 0)
	gui.MaxDistance = 220
	-- NOT AlwaysOnTop: a party chip is world information, not a HUD, and a tag that draws through
	-- the terrain would follow six people around the map through every wall between you and them.
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.Parent = head

	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = Color3.fromRGB(24, 22, 34)
	shell.BackgroundTransparency = 0.12
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
	name.Name = "PartyName"
	name.Size = UDim2.fromScale(0.92, 0.5)
	name.Position = UDim2.fromScale(0.04, 0.04)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextStrokeColor3 = Color3.fromRGB(14, 10, 22)
	name.TextStrokeTransparency = 0.2
	name.Parent = shell

	local bonus = Instance.new("TextLabel")
	bonus.Name = "Bonus"
	bonus.Size = UDim2.fromScale(0.92, 0.38)
	bonus.Position = UDim2.fromScale(0.04, 0.56)
	bonus.BackgroundTransparency = 1
	bonus.Font = Enum.Font.FredokaOne
	bonus.TextScaled = true
	bonus.TextColor3 = Color3.fromRGB(216, 212, 228)
	bonus.TextStrokeColor3 = Color3.fromRGB(14, 10, 22)
	bonus.TextStrokeTransparency = 0.2
	bonus.Parent = shell

	return gui
end

local function paint(player)
	local character = player.Character
	if not character then return end

	local partyId = player:GetAttribute("PartyId")
	if not partyId then
		clearChip(character)
		return
	end

	local gui = buildChip(player, character)
	if not gui then return end
	local shell = gui:FindFirstChild("Shell")
	if not shell then return end

	local colour = player:GetAttribute("PartyColor") or Color3.fromRGB(96, 176, 255)
	shell.Edge.Color = colour
	shell.PartyName.TextColor3 = colour
	shell.PartyName.Text = player:GetAttribute("PartyName") or "Party"

	-- `PartyNear` is republished once a second by the service; nil simply means it has not ticked
	-- yet, which is a different thing from zero and must not be drawn as "alone".
	local near = player:GetAttribute("PartyNear")
	local pct = player:GetAttribute("PartyPct") or 0
	if near == nil then
		shell.Bonus.Text = ("%d in party"):format(player:GetAttribute("PartyCount") or 1)
	elseif near <= 0 then
		shell.Bonus.Text = "alone -- regroup"
	else
		shell.Bonus.Text = ("+%d%% together"):format(pct)
	end
end

local function watch(player)
	-- Five things can change what this chip says, and every one of them is an attribute or a
	-- respawn. Nothing polls.
	for _, attr in ipairs({ "PartyId", "PartyColor", "PartyName", "PartyCount", "PartyNear", "PartyPct" }) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			paint(player)
		end)
	end

	local function hookCharacter(character)
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
