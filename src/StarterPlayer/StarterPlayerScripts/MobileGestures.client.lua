local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local gestureEvent = Remotes:FindFirstChild("ClientGesture")
if not gestureEvent then
	gestureEvent = Instance.new("BindableEvent")
	gestureEvent.Name = "ClientGesture"
	gestureEvent.Parent = Remotes
end

-- Must not fight joystick or world-space prompts, which run in gameProcessedEvent
UserInputService.TouchSwipe:Connect(function(swipeDirection, numberOfTouches, gameProcessedEvent)
	if gameProcessedEvent then return end

	if swipeDirection == Enum.SwipeDirection.Down then
		gestureEvent:Fire("Down")
	elseif swipeDirection == Enum.SwipeDirection.Left then
		gestureEvent:Fire("Left")
	elseif swipeDirection == Enum.SwipeDirection.Right then
		gestureEvent:Fire("Right")
	end
end)