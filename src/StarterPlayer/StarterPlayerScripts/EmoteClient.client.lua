local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local localPlayer = Players.LocalPlayer
local currentTrack = nil
local currentEmoteKey = nil

local function updateEmote()
	local emote = localPlayer:GetAttribute("WornEmote")
	local character = localPlayer.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	if currentTrack then
		currentTrack:Stop()
		currentTrack = nil
	end
	currentEmoteKey = nil
	
	if not emote or emote == "" then return end
	
	-- Find animation ID
	local animId = nil
	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.key == emote and c.type == "Emote" then
			animId = c.animId
			break
		end
	end
	
	if animId then
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		currentTrack = humanoid.Animator:LoadAnimation(anim)
		currentTrack.Priority = Enum.AnimationPriority.Action
		currentTrack.Looped = true
		currentTrack:Play()
		currentEmoteKey = emote
	end
end

localPlayer:GetAttributeChangedSignal("WornEmote"):Connect(updateEmote)
localPlayer.CharacterAdded:Connect(function()
	task.wait(0.5) -- wait for Rig to build
	updateEmote()
end)

-- Stop emote on movement
local function checkMovement()
	local character = localPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	if root.Velocity.Magnitude > 1 and currentTrack then
		currentTrack:Stop()
		currentTrack = nil
		-- Un-equip emote to reset state so they can equip it again later
		ReplicatedStorage.Remotes.CosmeticEquip:InvokeServer("Emote", "")
	end
end
game:GetService("RunService").Heartbeat:Connect(checkMovement)