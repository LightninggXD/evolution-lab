-- DailyPanel
local Builder = require(script.Parent.ScrollingPanelBuilder)
local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")

local DailyPanel = {}
local currentPanel = nil
local lastUpdateData = nil

function DailyPanel.Init(screenGui)
    if currentPanel then return end
    
    currentPanel = Builder.CreatePanel({
        Parent = screenGui,
        Name = "Daily",
        Title = "DAILY REWARDS",
        -- The gift, and the SAME id the Daily sidebar tile carries -- a panel whose header art
        -- differs from the tile that opens it reads as a different screen. (Was a red potion
        -- marked "placeholder", which is what a health bottle was doing on the rewards calendar.)
        HeaderIcon = "rbxassetid://111576444061359",
        HeaderColors = {Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 150, 0)},
        FooterHeight = 60
    })
    
    -- Setup Footer Buttons
    local footer = currentPanel.Footer
    
    local freeSpinBtn = Instance.new("TextButton")
    freeSpinBtn.Name = "FreeSpinBtn"
    freeSpinBtn.Size = UDim2.new(0.48, 0, 1, -10)
    freeSpinBtn.Position = UDim2.new(0, 0, 0.5, 0)
    freeSpinBtn.AnchorPoint = Vector2.new(0, 0.5)
    freeSpinBtn.BackgroundColor3 = Color3.fromRGB(255, 220, 50)
    freeSpinBtn.Text = "FREE SPIN"
    freeSpinBtn.Font = Enum.Font.FredokaOne
    freeSpinBtn.TextSize = 22
    freeSpinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    freeSpinBtn.Parent = footer
    local uic1 = Instance.new("UICorner")
    uic1.CornerRadius = UDim.new(0, 12)
    uic1.Parent = freeSpinBtn
    local uis1 = Instance.new("UIStroke")
    uis1.Color = Color3.fromRGB(150, 100, 0)
    uis1.Thickness = 3
    uis1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    uis1.Parent = freeSpinBtn
    
    freeSpinBtn.MouseButton1Click:Connect(function()
        Remotes.ClaimDailyReward:FireServer()
    end)
    
    local shardSpinBtn = freeSpinBtn:Clone()
    shardSpinBtn.Name = "ShardSpinBtn"
    shardSpinBtn.Position = UDim2.new(1, 0, 0.5, 0)
    shardSpinBtn.AnchorPoint = Vector2.new(1, 0.5)
    shardSpinBtn.BackgroundColor3 = Color3.fromRGB(150, 150, 170)
    shardSpinBtn.Text = "SPIN 25 SHARDS"
    shardSpinBtn.Parent = footer
    
    shardSpinBtn.MouseButton1Click:Connect(function()
        Remotes.BuyResource:FireServer("shard_spin", 1)
    end)
    
    -- Build Cards
    for i, reward in ipairs(GameConfig.DailyRewards) do
        local desc = ""
        if reward.dna then desc = desc .. reward.dna .. " DNA\n" end
        if reward.potions then desc = desc .. reward.potions .. "x " .. (reward.potionId or "Potion") .. "\n" end
        if reward.diamonds then desc = desc .. reward.diamonds .. " Diamonds\n" end
        if reward.shards then desc = desc .. reward.shards .. " Shards\n" end
        
        currentPanel.AddCard({
            Title = "Day " .. i,
            Description = desc,
            BackgroundColors = {Color3.fromRGB(255, 255, 255), Color3.fromRGB(240, 240, 240)},
            Buttons = {
                {
                    Price = "CLAIM",
                    Colors = {Color3.fromRGB(100, 255, 150), Color3.fromRGB(20, 200, 100)},
                    Callback = function() Remotes.ClaimDailyReward:FireServer() end
                }
            }
        })
    end
end

function DailyPanel.Toggle()
    if currentPanel then
        currentPanel.Toggle()
    end
end

return DailyPanel
