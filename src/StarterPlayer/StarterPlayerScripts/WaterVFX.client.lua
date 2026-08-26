local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WATER_SPEED_U = 0.5
local WATER_SPEED_V = 0.2
local FALL_SPEED_U = 0
local FALL_SPEED_V = 1.5

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	
	for _, tex in ipairs(CollectionService:GetTagged("AnimatedWaterTex")) do
		tex.OffsetStudsU = (t * WATER_SPEED_U) % tex.StudsPerTileU
		tex.OffsetStudsV = (t * WATER_SPEED_V) % tex.StudsPerTileV
	end
	
	for _, tex in ipairs(CollectionService:GetTagged("AnimatedFallTex")) do
		tex.OffsetStudsU = (t * FALL_SPEED_U) % tex.StudsPerTileU
		tex.OffsetStudsV = (t * FALL_SPEED_V) % tex.StudsPerTileV
	end
end)