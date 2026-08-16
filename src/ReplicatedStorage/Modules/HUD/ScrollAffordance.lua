-- ScrollAffordance -- the generic pass that gives all 15 ScrollingFrames a visible bar and a fade at the cut.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local PANEL_SHELL = UIKit.PANEL_SHELL

return function(hud)
	local screenGui = hud.screenGui

	local FADE_H = 30      -- tall enough to swallow a sliced row, short enough not to dim a full one
	local TAIL = 14        -- trailing space under the last row, so it never touches the clip line

	-- The fade has to sit ABOVE the scroll's own children. ZIndexBehavior is Sibling here (checked
	-- live), so a sibling one rung up covers the whole subtree and the children's own ZIndex does
	-- not enter into it.
	local function attachFade(scroll)
		local panel = scroll.Parent
		if not panel or not panel:IsA("GuiObject") then return end
		if panel:FindFirstChild(scroll.Name .. "Fade") then return end

		-- The panel does not paint its own background any more -- applyShell moved the fill into an
		-- InnerBody child and left only the BaseColor attribute behind. Reading BackgroundColor3
		-- here would return Roblox's default frame grey and paint a grey smear over a white panel.
		local base = panel:GetAttribute("BaseColor")
		if typeof(base) ~= "Color3" then base = PANEL_SHELL end

		local fade = Instance.new("Frame")
		fade.Name = scroll.Name .. "Fade"
		fade.BackgroundColor3 = base
		fade.BorderSizePixel = 0
		fade.ZIndex = scroll.ZIndex + 1
		-- A Frame that is not Active does not eat the wheel or a touch drag, so the bottom strip of
		-- the list stays scrollable through it.
		fade.Active = false
		fade.Visible = false

		-- Pin to the scroll's bottom edge in the scroll's own units, so this survives every resize
		-- and the panel-open UIScale without any absolute-pixel maths. Written to respect a
		-- non-zero AnchorPoint because TrackScroll has one (0, 0.5).
		fade.AnchorPoint = Vector2.new(scroll.AnchorPoint.X, 1)
		fade.Size = UDim2.new(scroll.Size.X.Scale, scroll.Size.X.Offset, 0, FADE_H)
		fade.Position = UDim2.new(
			scroll.Position.X.Scale,
			scroll.Position.X.Offset,
			scroll.Position.Y.Scale + scroll.Size.Y.Scale * (1 - scroll.AnchorPoint.Y),
			scroll.Position.Y.Offset + scroll.Size.Y.Offset * (1 - scroll.AnchorPoint.Y)
		)

		local grad = Instance.new("UIGradient")
		grad.Rotation = 90   -- default 0 runs left-to-right; the cut is horizontal
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		grad.Parent = fade
		fade.Parent = panel

		-- Show it only when something is actually below the fold, or a short list wears a permanent
		-- smudge along its bottom edge for no reason.
		local function refresh()
			local below = scroll.AbsoluteCanvasSize.Y - (scroll.CanvasPosition.Y + scroll.AbsoluteWindowSize.Y)
			fade.Visible = below > 4
		end
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh)
		scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(refresh)
		scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refresh)
		panel:GetPropertyChangedSignal("Visible"):Connect(function()
			if panel.Visible then task.defer(refresh) end
		end)
		task.defer(refresh)
	end

	local function polish(scroll)
		-- A visible bar on a white shell. Outline is the kit's near-black; at 0.35 it reads as a
		-- grip rather than a black stripe.
		scroll.ScrollBarImageColor3 = UITheme.Color.Outline
		scroll.ScrollBarImageTransparency = 0.35
		if scroll.ScrollBarThickness < 10 then scroll.ScrollBarThickness = 10 end

		-- Trailing space has to be bought differently depending on who owns the canvas. Padding on
		-- an AutomaticCanvasSize scroll grows the canvas with it; on a fixed canvas it would only
		-- push the content up and clip the last row harder, so that case buys the space on the
		-- canvas directly.
		if scroll.AutomaticCanvasSize == Enum.AutomaticSize.Y then
			local pad = scroll:FindFirstChildOfClass("UIPadding")
			if not pad then
				pad = Instance.new("UIPadding")
				pad.Parent = scroll
			end
			if pad.PaddingBottom.Offset < TAIL then
				pad.PaddingBottom = UDim.new(0, TAIL)
			end
		elseif scroll.CanvasSize.Y.Offset > 0 then
			scroll.CanvasSize = UDim2.new(
				scroll.CanvasSize.X.Scale, scroll.CanvasSize.X.Offset,
				scroll.CanvasSize.Y.Scale, scroll.CanvasSize.Y.Offset + TAIL
			)
		end

		attachFade(scroll)
	end

	for _, d in ipairs(screenGui:GetDescendants()) do
		if d:IsA("ScrollingFrame") then polish(d) end
	end
	-- Panels whose scroll is built lazily on first open would otherwise never be reached.
	screenGui.DescendantAdded:Connect(function(d)
		if d:IsA("ScrollingFrame") then task.defer(polish, d) end
	end)
end
