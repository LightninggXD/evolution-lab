local DataModel = game
local assets = {"Arcade Machines", "Dragon Pet", "Biggie Phantom", "Headdress", "Kitsune", "Rainbow Jump", "Rainbow Walk", "Trusses", "bullet"}

local found = {}
for _, name in ipairs(assets) do
    local obj = workspace:FindFirstChild(name)
    if obj then
        table.insert(found, name .. " (" .. obj.ClassName .. ")")
    end
end
return table.concat(found, ", ")