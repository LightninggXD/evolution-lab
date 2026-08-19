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
	local diamondPill, dnaPill = hud.diamondPill, hud.dnaPill

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
			-- ===== THROUGH `openStore`, NOT AT A PANEL (18.12) =====
			--
			-- This used to be `toggleOnly(hud.robuxPanel)` plus `selectRobuxTab(false)` -- a handle
			-- on an instance MainUI built, and a request for that instance's Packs tab. Both are
			-- gone with the panel. `UIComponents.ShopPanel` is one scrolling list with the products
			-- first, so "always the Packs tab" is now the default rather than an instruction: a `+`
			-- on a currency is a request for that currency, never for a pass, and no pass hint is
			-- passed here for exactly that reason.
			--
			-- Read at PRESS time, not captured as an upvalue at build time. MainUI does assign
			-- `openStore` before this module is required, so an upvalue would work today -- and
			-- that is the whole argument against it. The old line broke the moment the instance it
			-- named stopped existing; a field read on press is indifferent to require order, which
			-- is the property that was missing when this was `toggleOnly(robuxPanel)`.
			if hud.openStore then hud.openStore() end
		end)
	end

	addPlus(dnaPill, UITheme.Color.Green)
	addPlus(diamondPill, UITheme.Color.SkyBlue)
	-- deliberately NOT on the Shard pill: Evolution Shards are not sold for Robux anywhere, so a `+`
	-- there would open a shop that has nothing to answer it with. They are earned off the raised
	-- creatures on the terraces (9.4), and the place to spend them is the Daily panel's wheel.
end
