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
		--
		-- ===== AND ONLY WHILE THE SCROLL ITSELF IS ON SCREEN (34.57) =====
		--
		-- The fade is a SIBLING of the scroll, not a child of it -- it has to be, because
		-- ZIndexBehavior is Sibling here and a child could not cover the scroll's own contents. The
		-- cost of that is the one this guard pays: hiding the scroll does NOT hide the fade, because
		-- the fade is not inside it. On a panel with one list that never showed, since the panel and
		-- its list are hidden together and the panel's own `Visible` is watched below.
		--
		-- MEASURED ON THE RELICS PANEL, which swaps between TWENTY-ONE sibling `ScrollingFrame`s in
		-- one parent: after opening the Forge tab and then Forest, `Page_forgeFade` and
		-- `Page_ForestFade` were BOTH visible at exactly (768, 470.5), 264 x 30, ZIndex 25 -- two
		-- gradients stacked on the same pixels, so the darkening doubled. Walk all twenty-one tabs
		-- and the bottom of that list wears twenty-one of them, which is not a fade any more, it is
		-- a bar.
		--
		-- The guard is on the SCROLL rather than a rule in the panel, because it is true of every
		-- caller: a fade over a list nobody can see is never right, and a panel that swaps lists
		-- should not have to know this module exists.
		local function refresh()
			if not scroll.Visible then
				fade.Visible = false
				return
			end
			local below = scroll.AbsoluteCanvasSize.Y - (scroll.CanvasPosition.Y + scroll.AbsoluteWindowSize.Y)
			fade.Visible = below > 4
		end
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh)
		scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(refresh)
		scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refresh)
		scroll:GetPropertyChangedSignal("Visible"):Connect(refresh)
		panel:GetPropertyChangedSignal("Visible"):Connect(function()
			if panel.Visible then task.defer(refresh) end
		end)
		task.defer(refresh)
	end

	local function polish(scroll)
		-- A visible bar on a white shell. Outline is the kit's near-black; at 0.35 it reads as a
		-- grip rather than a black stripe. This half applies whichever way the list runs.
		--
		-- THE CONSTANT IS SAFE BECAUSE EVERY LIST IN THE GAME IS ON A LIGHT GROUND, and that is worth
		-- stating rather than assuming. 31.22 briefly added a `ScrollInk` attribute here for the one
		-- exception -- the Auras panel, then drawn on a plum well -- and 31.23 repainted that panel
		-- white at Kristina's instruction, which left an attribute nothing set. It came back out in
		-- the same pass: a branch with no caller is a safety net that is only discovered by falling
		-- into it. If a dark board is ever drawn again, this is the line, and one attribute is still
		-- the right shape for it.
		scroll.ScrollBarImageColor3 = UITheme.Color.Outline
		scroll.ScrollBarImageTransparency = 0.35

		-- ===== EVERYTHING BELOW IS A VERTICAL-LIST ASSUMPTION (30.2) =====
		--
		-- This pass was written when every `ScrollingFrame` in the game ran down the page, and all
		-- three of the things it does after this line quietly assume that:
		--
		--   * a 10 px bar is a comfortable grip beside a 400 px column and is a THIRD OF THE HEIGHT
		--     of a 34 px tab strip -- measured on the relic panel's set tabs, where it pushed the
		--     28 px tabs into the clip and cut their outlines off;
		--   * `TAIL` buys trailing space UNDER the last row, which a sideways list does not have;
		--   * `attachFade` pins a fade to the scroll's BOTTOM EDGE and shows it when content is
		--     below the fold. On a horizontal scroll there is never anything below the fold, so it
		--     is dead weight parented over the strip forever.
		--
		-- Two lists are horizontal today -- the relic set tabs and the Season track -- and both are
		-- fixed-height rows whose whole content is already on screen vertically. The honest fix is
		-- for the pass to say what it is for rather than to be worked around at each call site.
		if scroll.ScrollingDirection == Enum.ScrollingDirection.X then return end

		if scroll.ScrollBarThickness < 10 then scroll.ScrollBarThickness = 12 end

		-- ===== AND THE BAR IS NO LONGER DRAWN ON TOP OF THE LIST (research 4.3) =====
		--
		-- `VerticalScrollBarInset` "defaults to `ScrollBarInset.None`", which means the scrollbar is
		-- painted OVER the content rather than beside it. That was survivable at the 6 px this pass
		-- replaced and is not survivable at 12: the line above tripled the width of a grip that sits
		-- on top of whatever occupies the right-hand column -- a price chip, a count, a lock badge.
		-- The fattening and the inset are one decision and must never be shipped apart.
		--
		-- `Always`, not `ScrollBar`. `ScrollBar` reserves the gutter only while the list is actually
		-- scrollable, so a list that crosses that threshold -- one more pet, one more relic -- gets
		-- 12 px narrower mid-session and re-flows under the player. `Always` costs the same 12 px on
		-- a short list and never moves.
		--
		-- The cost is real and is why the check for this row counts cells: every list is now 12 px
		-- narrower, and a `UIGridLayout` with a fixed `CellSize` can lose a column to that.
		scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always

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
