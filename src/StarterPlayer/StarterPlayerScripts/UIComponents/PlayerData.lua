-- PlayerData -- one subscription to `DataUpdate`, shared by every panel in this folder.
--
-- WHY IT EXISTS: the server pushes the player's whole save down `Remotes.DataUpdate` about every
-- three seconds and on every kill. Four panels each wiring their own `OnClientEvent` is four copies
-- of the same table and four places for "we have not received anything yet" to be got wrong.
--
-- `Get()` IS A FUNCTION AND THAT IS THE WHOLE POINT. The table is REPLACED on every push, not
-- mutated, so a module that did `local data = PlayerData.Get()` at build time would hold the first
-- payload forever -- or `nil`, if it was built before the first one arrived, which is exactly the
-- window a player is looking at the screen in. Read it at USE time, every time.
-- (`docs/SPLIT.md` §3 rule 2, in the client's dialect -- this is the same trap `getData` in MainUI
-- is a getter for.)

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")

local PlayerData = {}

local current = nil
local listeners = {}

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
	current = data
	for _, fn in ipairs(listeners) do
		-- one panel's bad refresh must not stop the others being told
		local ok, err = pcall(fn, data)
		if not ok then warn("[PlayerData] listener failed: " .. tostring(err)) end
	end
end)

--- The latest save, or nil if the first push has not landed yet. Call it; never cache it.
function PlayerData.Get()
	return current
end

--- Register a callback for every push. Fires immediately if data has already arrived, so a panel
--- built late is not blank until the next tick.
function PlayerData.OnChanged(fn)
	listeners[#listeners + 1] = fn
	if current then
		local ok, err = pcall(fn, current)
		if not ok then warn("[PlayerData] listener failed: " .. tostring(err)) end
	end
end

return PlayerData
