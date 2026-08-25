local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local SkinMesh = require(RS.Modules.SkinMesh)

local MapVIP = {}

function MapVIP.Init()
	local mapFolder = workspace:FindFirstChild("Map")
	if not mapFolder then return end

	local vipFolder = mapFolder:FindFirstChild("VIP")
	if not vipFolder then
		vipFolder = Instance.new("Folder")
		vipFolder.Name = "VIP"
		vipFolder.Parent = mapFolder
	end

	local forestOffset = GameConfig.Zones[1].offset
	-- Center of VIP podiums
	local basePosition = Vector3.new(forestOffset, 0, 0) + Vector3.new(-80, 0, 70)
	
	-- We have 9 VIP characters, let's arrange them in a 3x3 grid or an arc
	local cols = 3
	local spacing = 20
	
	for i, c in ipairs(GameConfig.VipCharacters) do
		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		
		local position = basePosition + Vector3.new(col * spacing, 0.5, row * spacing)
		
		-- Podium
		local podium = Instance.new("Part")
		podium.Name = "Podium_" .. c.key
		podium.Size = Vector3.new(12, 1, 12)
		podium.Position = position
		podium.Anchored = true
		podium.Shape = Enum.PartType.Cylinder
		podium.BrickColor = BrickColor.new("Bright yellow")
		podium.Material = Enum.Material.Neon
		podium.Orientation = Vector3.new(0, 0, 90) -- Cylinder lies on its side, wait cylinder orientation is weird in roblox
		-- A flat cylinder is Z-oriented. To make it a platform, we need rotation
		podium.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi/2)
		podium.Parent = vipFolder
		
		-- Center platform
		local core = Instance.new("Part")
		core.Name = "Core"
		core.Size = Vector3.new(11, 1.1, 11)
		core.Position = position
		core.Anchored = true
		core.Shape = Enum.PartType.Cylinder
		core.BrickColor = BrickColor.new("Dark stone grey")
		core.Material = Enum.Material.DiamondPlate
		core.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi/2)
		core.Parent = podium
		
		-- Billboard
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.new(0, 200, 0, 60)
		board.StudsOffset = Vector3.new(0, 10, 0)
		board.MaxDistance = 100
		
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "VIP\n" .. c.name
		label.TextColor3 = Color3.fromRGB(255, 215, 0)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Parent = board
		board.Parent = podium

		-- Prompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Buy VIP"
		prompt.ObjectText = c.name
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.Parent = podium
		
		prompt.Triggered:Connect(function(player)
			RS.Remotes.PromptGamePassPurchase:FireClient(player, "VIP")
		end)
		
		-- Model
		local template = SkinMesh.TemplateFor(c.key)
		if template then
			local model = template:Clone()
			
			-- Position the model on top of the podium
			-- We have to move all parts
			-- Let's just create a Model instance, put parts inside, and set PrimaryPart to Torso
			local torso = model:FindFirstChild("Torso") or model:FindFirstChild("torso")
			if torso then
				model.PrimaryPart = torso
				-- Rotate to face forward (-X axis maybe?)
				model:PivotTo(CFrame.new(position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.pi, 0))
				
				-- Anchor all parts
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
					end
				end
				
				model.Parent = podium
			end
		end
	end
end

return MapVIP
