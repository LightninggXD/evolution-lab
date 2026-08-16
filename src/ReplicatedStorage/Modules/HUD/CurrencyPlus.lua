-- CurrencyPlus -- the `+` buttons on the DNA and Diamond capsules, which open the Robux shop.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local styleButton = UIKit.styleButton

return function(hud)
	local diamondPill, dnaPill, robuxPanel = hud.diamondPill, hud.dnaPill, hud.robuxPanel
	local toggleOnly = hud.toggleOnly

	local function addPlus(pill, tone)
		-- the pill is a horizontal UIListLayout of Icon (40 wide) + Value; the value gives up the room
		local value = pill:FindFirstChild("Value")
		if not value then return end
		value.Size = UDim2.new(1, -84, 1, 0)

		local plus = Instance.new("TextButton")
		plus.Name = "PlusButton"
		plus.Size = UDim2.new(0, 32, 0, 32)
		plus.LayoutOrder = 3
		plus.Text = "+"
		plus.Parent = pill
		styleButton(plus, tone, UDim.new(1, 0))
		plus.MouseButton1Click:Connect(function()
			toggleOnly(robuxPanel)
			-- always the Packs tab: `+` on a currency is a request for that currency, never for a pass
			if hud.selectRobuxTab then hud.selectRobuxTab(false) end
		end)
	end

	addPlus(dnaPill, UITheme.Color.Green)
	addPlus(diamondPill, UITheme.Color.SkyBlue)
	-- deliberately NOT on the Shard pill: Evolution Shards are not sold for Robux anywhere, so a `+`
	-- there would open a shop that has nothing to answer it with. They are earned off the raised
	-- creatures on the terraces (9.4), and the place to spend them is the Daily panel's wheel.
end
