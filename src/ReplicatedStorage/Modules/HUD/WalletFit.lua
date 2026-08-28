-- WalletFit -- the wallet column is as wide as the numbers in it, and no wider (2026-08-28).
--
-- A HUD MODULE, i.e. a FUNCTION and not a table (`docs/SPLIT.md` section 2), so **MainUI gains
-- exactly one line and zero top-level locals** ([[evolution-lab-mainui-register-limit]]).
--
-- ===== WHAT THIS FIXES, MEASURED IN A LIVE PLAY =====
--
-- Reported by the owner off her own screen -- *"ovo belo iza treba skloniti"*, with a crop of the
-- Diamond and Shard capsules. It is not a colour fault and there is nothing drawn behind them: the
-- capsules were **250 px wide, fixed**, and the number is left-aligned inside them. Measured on the
-- running client with `TextService:GetTextSize` at the authored `MaxTextSize`:
--
--   "319.35K"  104 px in a 142 px box   -- the DNA pill is nearly full
--   "130"       ~30 px in a 142 px box   -- ~110 px of empty pale capsule
--   "46"        ~20 px in a 180 px box   -- ~160 px, and the Shard pill has no `+` to fill it
--
-- That empty tail IS the white she is pointing at. So the fix is not a repaint, it is a width.
--
-- ===== ONE WIDTH FOR ALL THREE, AND WHY IT IS NOT PER-PILL =====
--
-- The obvious version -- `AutomaticSize.X` on each capsule -- gives three ragged widths that
-- disagree by 80 px and jump apart on every income tick. 18.2's note over the three pills is
-- explicit that they are ONE wallet (same capsule, same rim, same ink, same treatment), and a
-- ragged column throws that away to solve a problem only two of the three have. So the column keeps
-- a single width and that width is **recomputed from the widest current pill**. When the numbers
-- are small the whole wallet is small; when DNA reaches into the suffixes all three grow together.
--
-- ===== THE OVERHEAD IS READ, NOT ASSUMED =====
--
-- `UITheme.Pill` puts a `UIPadding` of 12/12 on the content frame and lays the row out with a
-- 40 px icon and `Value` at `UDim2.new(1, -46, ...)` -- which MainUI rewrites to `1, -84` on the
-- two pills that hang a `+` disc on the end. Both numbers are in that file for reasons of their
-- own, so this module reads `Value.Size.X.Offset` back instead of copying either: overhead is
-- `24 + (-offset)`, exact by construction and immune to the day one of them moves.
--
-- `MaxTextSize` likewise comes off the label's own `UITextSizeConstraint` (`autoSize` parents one
-- to every Pill value), not from a second copy of the 34/30/30 authored in MainUI. A duplicated
-- constant here would drift silently and the column would size itself against a font nobody draws.
--
-- ===== THE TRIGGER IS THE TEXT, NOT THE PAYLOAD =====
--
-- `GetPropertyChangedSignal("Text")` on the three `Value` labels rather than a second
-- `DataUpdate` listener. Two reasons, and the second is the load-bearing one:
--   * it cannot race MainUI's own handler -- there is no connection-order question, because the
--     text is already written by the time this runs;
--   * it survives whatever ends up writing that text. A count-up animation (33.11 §1.5) rewrites
--     `Text` many times per update, and this re-fits with it instead of sizing to a stale number.
--
-- The width is tweened rather than snapped for the same reason: a spinning count-up would otherwise
-- step the whole column sideways once per frame. Under `UITheme.ReducedMotion()` it is set outright,
-- with no tween, per the kit's accessibility rule.

local RS = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local UITheme = require(RS.Modules:WaitForChild("UITheme"))

-- Never wider than the 250 it was authored at, and never so narrow that a one-digit wallet stops
-- reading as the same object -- 150 keeps the icon, three digits and the `+` disc with room to
-- spare, and it is the width at which the capsule still looks like a capsule rather than a chip.
local MIN_W = 150
local MAX_W = 250
-- 4 px so the last glyph never sits against the `+`. The layout's own 6 px cell padding is between
-- the cells, not inside the text box.
local SLACK = 4

return function(hud)
	local screenGui = hud.screenGui
	local stack = screenGui:FindFirstChild("CurrencyStack")
	if not stack then
		return
	end

	local pills = {}
	for _, shell in ipairs(stack:GetChildren()) do
		if shell:IsA("GuiObject") and shell.Name:match("PillShell$") then
			local value = shell:FindFirstChild("Value", true)
			if value and value:IsA("TextLabel") then
				table.insert(pills, value)
			end
		end
	end
	if #pills == 0 then
		return
	end

	local function neededFor(value)
		local constraint = value:FindFirstChildOfClass("UITextSizeConstraint")
		local size = constraint and constraint.MaxTextSize or value.TextSize
		local w = TextService:GetTextSize(value.Text, size, value.Font, Vector2.new(10000, 100)).X
		-- 24 is the content frame's 12/12 UIPadding; the offset is the icon + the `+` slot the Pill
		-- reserved for itself. Negative in the property, so it is subtracted here.
		return w + 24 - value.Size.X.Offset + SLACK
	end

	local applied = nil
	local function fit()
		local want = MIN_W
		for _, value in ipairs(pills) do
			local n = neededFor(value)
			if n > want then
				want = n
			end
		end
		want = math.clamp(math.floor(want + 0.5), MIN_W, MAX_W)
		if applied == want then
			return
		end
		applied = want
		local goal = UDim2.new(0, want, stack.Size.Y.Scale, stack.Size.Y.Offset)
		if UITheme.ReducedMotion() then
			stack.Size = goal
		else
			UITheme.Tween(stack, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = goal,
			})
		end
	end

	for _, value in ipairs(pills) do
		value:GetPropertyChangedSignal("Text"):Connect(fit)
	end
	fit()
end
