-- UIKit -- the HUD's drawing kit: every helper that turns a bare Roblox instance into a
-- piece of this game's interface.
--
-- WHY THIS IS ITS OWN FILE (18.9)
-- ------------------------------
-- These 540 lines were the top of `StarterPlayerScripts.MainUI`, which had grown to 11,743 --
-- ~149k tokens to read whole, for the sake of changing one label. The kit is the part of that
-- file that depends on NOTHING in it: it references `UITheme` and its own constants and not
-- `screenGui`, `currentData`, `player` or any remote, which is what makes it the one seam that
-- could be cut without threading state through the cut. Everything below is byte-for-byte what
-- was there, comments included -- no drawing behaviour was changed by the move.
--
-- WHO MAY REQUIRE IT: any client script. It is in `ReplicatedStorage.Modules` rather than under
-- `MainUI` so the next HUD-adjacent LocalScript (HatchReveal, EvolveReveal, SplicerUI ...) can
-- stop re-deriving `themeLabel` and use this one.
--
-- THE CONTRACT WITH `UITheme`, WHICH IS NOT THE SAME THING: `UITheme` owns the design tokens --
-- colours, radii, fonts, the shared PanelHeader/IconSlot widgets. This owns the *application* of
-- them to an instance the HUD just made. When in doubt: a value goes in UITheme, a verb goes here.
--
-- Where the rest of MainUI went: `docs/CODEMAP.md`.

local RS = game:GetService("ReplicatedStorage")

-- ================= helpers =================
local function formatNumber(n)
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp"}
	local mag = 0
	while n >= 1000 and mag < #suffixes do
		n = n / 1000
		mag += 1
	end
	-- THE ROUNDING CARRIES, and the loop above has already stopped looking. 999,999 divides once to
	-- 999.999, which is under the loop's threshold and so is accepted -- and "%.2f" then prints it
	-- as "1000.00", i.e. "1000.00K" for a number one short of a million. The threshold is 999.995
	-- and not 999.95 because this one prints TWO decimals; the carry happens wherever the format
	-- rounds up to 1000, so the constant has to match the precision beside it.
	if n >= 999.995 and mag < #suffixes then
		n = n / 1000
		mag += 1
	end
	return string.format("%.2f%s", n, suffixes[mag])
end

-- `corner` is defined AFTER the UITheme require further down, not here, and that is not tidiness:
-- Lua binds an upvalue where a function is WRITTEN, so a version written above the require would
-- resolve `UITheme` to a nil global and blow up on the first corner the HUD draws. Same trap the
-- ZoneBuilder forward-declarations exist for.

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or Color3.fromRGB(255,255,255)
	s.Transparency = 0.4
	s.Parent = parent
	return s
end

local function gradient(parent, colorSequence, rotation)
	local g = Instance.new("UIGradient")
	g.Color = colorSequence
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- ================= shared design system (ReplicatedStorage.Modules.UITheme) =================
local UITheme = require(RS.Modules.UITheme)

-- THROUGH THE SHAPE SCALE (10.18). This helper draws most of the HUD's corners and it used to take
-- whatever number the call site typed, which is how the interface came to speak in ten different
-- radii that differ by two pixels each. `SnapRadius` rounds to the nearest named step and leaves
-- pills and deliberately-large panel corners alone, so no call site had to change.
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UITheme.SnapRadius(radius or UITheme.Radius.Card)
	c.Parent = parent
	return c
end

local OUTLINE_COLOR = UITheme.Color.Outline
local DISPLAY_FONT = UITheme.Font.Display
-- LIGHT, AND THE ONE PLACE IT HAS TO CHANGE. Every panel in the game reads this one value --
-- Daily, Zones, Journal, Rebirth, Pets, Fusion, Inventory, Character, Shop, Season -- so the whole
-- UI moves together or not at all. It started at rgb(48,42,72), which was near enough to black
-- that the panels read as a debug overlay dropped on a bright cartoon world; rgb(92,86,128) was a
-- step and still read dark.
--
-- THE WHITE TEXT SURVIVES ON A LIGHT SHELL BECAUSE OF THE OUTLINE, not because of the fill. Every
-- display label in the kit is white with a 4px near-black stroke (Color.Outline, rgb(26,18,36)),
-- and that stroke is what carries it -- which is exactly how the reference games put white text on
-- cream panels. The gradient helps too: GradientFor lifts the top stop to rgb(244,243,251) and
-- drops the bottom to rgb(163,160,176), so the panel has a lit top and a shaded foot rather than
-- one flat wash.
local PANEL_SHELL = Color3.fromRGB(255, 255, 255)

-- Roblox's own TextLabel default. A label still carrying it never picked a colour -- see themeLabel.

-- Modern high-contrast clean card surface for inner list rows and items.
local PET_ROW_SHELL = Color3.fromRGB(222, 226, 242)

local function shade(c, amt)
	return UITheme.Shade(c, amt)
end

local function gradientForColor(baseColor)
	return UITheme.GradientFor(baseColor)
end

-- Bright rim painted on whatever is actionable right now -- the one "come here" signal, shared
-- by the Daily board and the Stage Mastery list. Declared up here with the other constants
-- because both readers are functions defined further down, and a `local` introduced after them
-- would resolve to a nil global inside those closures rather than to this value.
local READY_RIM = shade(UITheme.Color.Green, 0.5)

-- Every readable label: display font + thick dark outline + autosized (never a fixed 11-13px).
local function themeLabel(label, maxSize, color)
	if not (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
		return label
	end
	if label:GetAttribute("Themed") then
		return label
	end
	label:SetAttribute("Themed", true)
	label.Font = DISPLAY_FONT
	label.TextStrokeTransparency = 1
	-- DARK INK AND ITS OUTLINE ARE ONE DECISION. `OutlineText` wraps every label in Color.Outline
	-- (rgb 26,18,36) at 4px, which is right for the white-on-colour text this HUD is made of and is
	-- a solid black blob for dark text on a white card -- the glyph and its halo are then the same
	-- colour. Every property reads correct while it happens (`Text`, `TextColor3`, `TextFits`), so
	-- it survives any probe; it is only visible in a capture. It shipped on the Daily board's day
	-- pills and reward names. A colour passed in on purpose is trusted -- what changes is that a
	-- dark one now DROPS the stroke, because the light surface it was chosen for already separates
	-- it. Anything at or above the cut keeps the chunky outline, so nothing white moves.
	local darkInk = false
	if color then
		label.TextColor3 = color
		-- THE THRESHOLD MOVED INTO UITheme (15.15) and this reads it rather than repeating it. It
		-- was written here first, and the copy is exactly what let the Group panel ship the same
		-- defect through `UITheme.Label` -- the other constructor that applies a halo, which never
		-- learned the rule. One palette, one number, both constructors.
		darkInk = UITheme.IsDarkInk(color)
	else
		-- A label that never picked a colour still carries Roblox's near-black default, and
		-- OutlineText below wraps it in a dark stroke -- dark on dark, which is how every panel
		-- title, the pet/zone row names and the toast message ended up unreadable.
		--
		-- This used to test `label.TextColor3 == ROBLOX_DEFAULT_TEXT` and that comparison is
		-- ALWAYS false: the engine's default is a different float from the one Color3.fromRGB
		-- computes for the same 27,42,53, so the branch never ran and the bug was never actually
		-- fixed. Luminance is the honest test, and every colour this UI sets on purpose is bright.
		--
		-- AND IT READS UITheme's CUT NOW, NOT ITS OWN 0.35 (17.x). The branch above already learned
		-- that lesson in 15.15 and this one did not, so the two halves of the same function disagreed
		-- by 0.10 -- and the gap was not harmless. A label whose colour was set somewhere else at
		-- luminance 0.35..0.45 fell between them: too light to be whitened here, and `darkInk` stays
		-- FALSE in this branch, so it was handed the full 4 px Color.Outline halo. Dark ink inside a
		-- dark halo is exactly the blob 15.1 was written to kill, wearing the fix's own clothes.
		-- One palette, one number, and now genuinely one number.
		darkInk = UITheme.IsDarkInk(label.TextColor3)
		if darkInk then
			label.TextColor3 = UITheme.Color.White
		end
	end
	if not label:FindFirstChildOfClass("UIStroke") then
		UITheme.OutlineText(label, darkInk and 0 or 4) -- matches UITheme's own default; see the note there
	end
	if not label:FindFirstChildOfClass("UITextSizeConstraint") then
		local maxT = maxSize
		if not maxT then
			local h = label.Size.Y.Offset
			if h <= 0 then h = 26 end
			maxT = math.clamp(math.floor(h * 0.85), 14, 30)
		end
		UITheme.AutoSize(label, math.min(14, maxT), maxT)
	end
	return label
end

--[[
	HARD INVARIANT (this is the bug that started the redesign): the gloss sheen must never
	paint over content. Content children of a themed surface are pushed to Shell+3, strictly
	above the gloss at Shell+1. Nested surfaces keep their own relative stacking via `delta`.
]]
local function liftChildren(inst)
	-- ===== THE BASE IS READ ON EVERY LIFT, NEVER CAPTURED (15.28) =====
	--
	-- A surface styled at ZIndex 1 and then parented into a surface that is ITSELF lifted has its
	-- whole subtree shifted by the parent's lift. A target measured against the ZIndex this surface
	-- had at styleCard time is then stale by exactly that shift, every later child already clears
	-- it, and the `child.ZIndex >= target` guard below turns into an unconditional return -- so
	-- content added after styling never rises above the surface's own opaque ShadowBody.
	--
	-- That is the whole "the Daily Rewards cards are empty" report: Day1's own lift captured 1, the
	-- panel's lift then moved the card to 24 with everything under it, and AmountLabel/BonusLabel
	-- stayed at 24 underneath a ShadowBody drawn at 28. Only the pieces that set an explicit ZIndex
	-- (the day pill, the claimed tick) were ever visible. Reading `inst.ZIndex` live is also order
	-- independent: it lands on the right number whether the parent's lift runs before or after.
	local function lift(child)
		if not child:IsA("GuiObject") then return end
		-- `IconShadow` joined this list in 11.15, and it was a real bug rather than a tidy-up.
		-- `iconSlot` draws an icon's hard shadow as a SIBLING one ZIndex below the icon (it has to
		-- be a sibling: under ZIndexBehavior.Sibling a child always draws above its parent). That
		-- puts it at `target - 1`, so this function lifted it to exactly `target` -- level with the
		-- icon it is shadowing -- and a tie under Sibling is broken by tree order, where the shadow
		-- is the LATER child. So the dark silhouette was drawn ON TOP of the drawing, offset a few
		-- pixels down-right at 55% transparency: a muddy edge on every icon sitting inside a
		-- styleCard surface. Skipped by name here rather than fixed at the call sites, because it is
		-- one bug with one cause and the toast chip is only the newest of the places it reaches.
		--
		-- ===== AND `ShadowBody`, WHICH IS WHY THE WHOLE HUD LOOKED MUDDY (15.28) =====
		--
		-- styleCard authors it at `inst.ZIndex + Z.Shell`, and Z.Shell is 0 -- the lip is MEANT to sit
		-- at the surface's own level, one under the `InnerBody` that carries the actual colour, so all
		-- you ever see of it is the 6px sticking out below. It was not on this list, so it was lifted
		-- to Content (+4) like ordinary content and ended up FOUR ABOVE the body it is the shadow of.
		--
		-- It is full size and opaque, so every styleCard surface in this file was painting itself in
		-- `shade(colour, -0.4)` with a 6px sliver of its real colour along the top edge. That is the
		-- entire "everything is grey and murky" look: the shell is pure white and rendered mid-grey,
		-- Lavender rendered as slate, Gold as bronze. UITheme's own widgets (the sidebar tiles, the
		-- toasts) never went through this function, which is exactly why they were the only bright
		-- things on screen and looked like they belonged to a different kit.
		--
		-- ===== AND `DropShadow`, WHICH WOULD OTHERWISE ARRIVE ON TOP OF THE THING IT SHADOWS (18.5) =====
		--
		-- `UITheme.DropShadow` authors its sprite at `inst.ZIndex + Z.Shadow`, i.e. one BELOW the
		-- shell, and parents it as a child so it scales with the press. This function's `ChildAdded`
		-- hook is live by then, and a child one below the shell is exactly what it exists to lift --
		-- so without this name the soft shadow would be raised four above the shell and drawn over the
		-- card's own face, at 62% transparency, as a grey haze on every surface in the file. Same
		-- shape of bug as `ShadowBody` above, one row later.
		if child.Name == "Gloss" or child.Name == "Shadow" or child.Name == "IconShadow"
			or child.Name == "InnerBody" or child.Name == "ShadowBody"
			or child.Name == "DropShadow" then return end
		local target = inst.ZIndex + UITheme.Z.Content
		if child.ZIndex >= target then return end
		local delta = target - child.ZIndex
		child.ZIndex = target
		for _, d in ipairs(child:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = d.ZIndex + delta
			end
		end
	end
	for _, child in ipairs(inst:GetChildren()) do
		lift(child)
	end
	inst.ChildAdded:Connect(lift)
end

--[[
	Chunky glossy surface applied to an EXISTING instance (the ~30 legacy call sites).
	Thick dark outline + moulded vertical gradient + hard bottom lip (drop shadow that is
	safe inside UIListLayout/UIGridLayout parents) + a FAINT sheen that can never cover text.
	Returns the UIStroke, same as the old helper.
]]
local LIP_DEPTH = 6

local function styleCard(inst, baseColor, radius, thickness)
	baseColor = baseColor or UITheme.Color.Blue
	-- THROUGH THE LADDER, the way the thickness below already goes through `SnapStroke` (2026-08-16).
	-- This builder made most of the HUD and it was the one surface builder in the game that did NOT
	-- snap its radius, so the shape scale in `UITheme` governed everything except the screen you
	-- actually look at. The snap only ever rounds UP, so nothing here can come out squarer than it
	-- was authored.
	local cornerRadius = UITheme.SnapRadius((typeof(radius) == "UDim") and radius or UDim.new(0, radius or 16))

	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0
	inst:SetAttribute("BaseColor", baseColor)

	local oldCorner = inst:FindFirstChild("UICorner")
	if oldCorner then oldCorner:Destroy() end
	local oldStroke = inst:FindFirstChild("UIStroke")
	if oldStroke then oldStroke:Destroy() end

	local strokeT = UITheme.SnapStroke(thickness or UITheme.Stroke.Heavy)

	-- NO LIP UNDER A PILL -- see `applyShell` in UITheme for the geometry. Short version: the lip is
	-- this shape shifted down 6 px, and a stadium shifted down pokes its flanks out at both ends
	-- exactly where the body has curved away, so every capsule on this HUD wore two dark caps.
	local lipDepth = (cornerRadius.Scale >= 0.5) and 0 or LIP_DEPTH

	local shadowBody = inst:FindFirstChild("ShadowBody") or Instance.new("Frame")
	shadowBody.Name = "ShadowBody"
	shadowBody.Size = UDim2.new(1, 0, 1, 0)
	shadowBody.Position = UDim2.new(0, 0, 0, lipDepth)
	-- THE FOOT HAS TO KNOW HOW LIGHT ITS OWN SURFACE IS (17.x). A flat -0.4 under a WHITE card is
	-- rgb(153) -- a mid grey slab, not a shadow -- while UITheme's own shells now step the lip to
	-- -0.22 on light fills and land at rgb(199). This file builds most of the HUD through
	-- styleCard, so leaving the literal here is what makes half the panels look like they came
	-- from a different kit. LipShade is the shared decision; the chromatic case is unchanged.
	shadowBody.BackgroundColor3 = UITheme.LipShade(baseColor)
	shadowBody.BackgroundTransparency = 0
	shadowBody.BorderSizePixel = 0
	shadowBody.ZIndex = inst.ZIndex + UITheme.Z.Shell
	corner(shadowBody, cornerRadius)
	
	local shadowStroke = shadowBody:FindFirstChild("UIStroke") or Instance.new("UIStroke")
	shadowStroke.Name = "UIStroke"
	shadowStroke.Thickness = strokeT
	shadowStroke.Color = OUTLINE_COLOR
	shadowStroke.Transparency = 0
	shadowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	shadowStroke.LineJoinMode = Enum.LineJoinMode.Round
	shadowStroke.Parent = shadowBody
	shadowBody.Parent = inst

	local body = inst:FindFirstChild("InnerBody") or Instance.new("Frame")
	body.Name = "InnerBody"
	body.Size = UDim2.new(1, 0, 1, 0)
	body.Position = UDim2.new(0, 0, 0, 0)
	body.BackgroundColor3 = baseColor
	body.BackgroundTransparency = 0
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.ZIndex = inst.ZIndex + UITheme.Z.Body
	corner(body, cornerRadius)
	
	local bodyStroke = body:FindFirstChild("UIStroke") or Instance.new("UIStroke")
	bodyStroke.Name = "UIStroke"
	bodyStroke.Thickness = strokeT
	bodyStroke.Color = OUTLINE_COLOR
	bodyStroke.Transparency = 0
	bodyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bodyStroke.LineJoinMode = Enum.LineJoinMode.Round
	bodyStroke.Parent = body
	body.Parent = inst

	local grad = body:FindFirstChild("Gradient") or Instance.new("UIGradient")
	grad.Name = "Gradient"
	grad.Rotation = 90
	grad.Color = UITheme.GradientFor(baseColor)
	grad.Parent = body

	local gloss = inst:FindFirstChild("Gloss") or Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = UITheme.Color.White
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = inst.ZIndex + UITheme.Z.Gloss

	local gc = gloss:FindFirstChild("UICorner")
	if gc then gc:Destroy() end

	gloss.AnchorPoint = Vector2.new(0, 0)
	gloss.Position = UDim2.new(0, 0, 0, 0)
	
	if cornerRadius.Scale >= 0.5 then
		gloss.Size = UDim2.new(1, 0, 0.40, 0)
	else
		gloss.Size = UDim2.new(1, 0, 0.35, 0)
	end

	local glossGrad = gloss:FindFirstChild("UIGradient") or gradient(gloss, ColorSequence.new(UITheme.Color.White), 90)
	glossGrad.Name = "UIGradient"
	glossGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.7, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	gloss.Parent = body

	-- ===== A TEXTLABEL HANDED TO A SHELL LOSES ITS OWN CAPTION (17.13 / 18.6) =====
	--
	-- A `TextLabel` draws its text at its OWN ZIndex, and since 15.28 the fill this function paints
	-- lives in an `InnerBody` child one rung ABOVE it, with `Gloss` a rung above that. So every
	-- text-bearing host that comes through here is painted over and ships as a blank coloured pill.
	-- Measured live on the pet cards' `EnchantChip`: host at ZIndex 32, InnerBody at 33, Gloss at 34,
	-- `TextFits = true`, `TextBounds = 66x15`, and nothing on screen -- which is the screenshot
	-- Kristina sent as "the pills are empty" (ROADMAP 17.13).
	--
	-- `UITheme.applyShell` already does this for the widgets the kit builds itself. `styleCard` is
	-- the SECOND copy of applyShell and 77 of the 78 surface builds in this file go through it, so
	-- the fix has to be here or it only covers the kit. Four hosts in this file were affected and
	-- only one of them had ever been reported: `EnchantChip` (the pill), `SelectBox` (the ✔ on a
	-- pet card in select mode), `SecretBadge` ("SECRET" on a journal cell) and the world beacon's
	-- "REBIRTH READY". Three of the four had been invisible since 15.28 with nobody noticing,
	-- because every property still reads correct and only a capture shows it.
	--
	-- ===== AND WHY THE MIRROR HAS TO BE RE-SYNCED HERE =====
	--
	-- `MirrorText` copies `Font`, `TextColor3` and the halo decision at the moment it runs. At every
	-- one of the four call sites `themeLabel` runs AFTER `styleCard`, so at mirror time the host is
	-- still carrying Roblox's default font and its near-black default ink -- which reads as dark ink,
	-- so the mirror is built with a 0px halo and the wrong face. The kit watches `Text` and
	-- `TextColor3`; it does not watch `Font`, and its `TextColor3` hook moves the stroke's
	-- transparency without moving its thickness, so a caption that turns white afterwards gets a
	-- stroke that is opaque and 0 px wide -- i.e. still no halo. Both are re-synced here, and the
	-- size constraint `themeLabel` adds a few lines later is copied across when it arrives, so the
	-- mirror is capped where the author asked rather than at MirrorText's generic 22.
	if inst:IsA("TextLabel") and not inst:GetAttribute("Mirrored") then
		inst:SetAttribute("Mirrored", true)
		local mirror = UITheme.MirrorText(inst)
		if mirror then
			local function syncFace()
				mirror.Font = inst.Font
				local mstroke = mirror:FindFirstChildOfClass("UIStroke")
				if mstroke then
					-- ink and halo are ONE decision (rule 7): a near-black halo under dark ink draws
					-- the word as a blob that measures perfectly. Same cut `themeLabel` uses.
					local darkInk = UITheme.IsDarkInk(inst.TextColor3)
					mstroke.Thickness = darkInk and 0 or 4
					mstroke.Transparency = darkInk and 1 or 0
				end
			end
			syncFace()
			inst:GetPropertyChangedSignal("Font"):Connect(syncFace)
			inst:GetPropertyChangedSignal("TextColor3"):Connect(syncFace)
			inst.ChildAdded:Connect(function(child)
				if child:IsA("UITextSizeConstraint") then
					local mc = mirror:FindFirstChildOfClass("UITextSizeConstraint")
					if mc then
						mc.MinTextSize = child.MinTextSize
						mc.MaxTextSize = child.MaxTextSize
					end
				end
			end)
		end
	end

	-- ===== THE SURFACE CASTS (18.5) =====
	--
	-- `UITheme.applyShell` calls `UITheme.DropShadow` for the widgets the kit builds itself. This
	-- function is the SECOND copy of applyShell and it builds most of the HUD -- every panel, every
	-- Daily tile, every card in this file -- so without this line "nothing in this UI casts a shadow"
	-- would still be true of everything she actually photographed. One implementation and one set of
	-- numbers, whichever builder the surface came from.
	--
	-- Passed the same `cornerRadius` computed at the top rather than the raw `radius` argument, so the
	-- sprite's own round-shell opt-out (`Scale >= 0.5` -> no shadow, see the note in UITheme) reads
	-- the shape that was actually drawn after `SnapRadius`, not the one that was asked for.
	--
	-- BEFORE `liftChildren`, and it makes no difference which side it goes on: the sprite is named
	-- `DropShadow`, which is on the skip list above for exactly this reason. Anything that is a chip
	-- lying flat ON another card rather than a raised object sets `NoShadow` before it is styled.
	UITheme.DropShadow(inst, cornerRadius)

	liftChildren(inst)
	return bodyStroke
end

local function styleButton(btn, baseColor, radius, thickness)
	btn.AutoButtonColor = false
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextStrokeTransparency = 1

	-- ===== EVERY ACTION BUTTON IN THE GAME LOST SIX PIXELS, IN ONE PLACE =====
	--
	-- Asked for as "the buttons are too big". Done here rather than at the ~25 sites that author
	-- one, because a height typed in 25 places drifts the moment somebody writes the 26th -- which
	-- is the same reasoning that put the egg panel's two action buttons into a list layout below.
	--
	-- KEYED ON THE EXACT AUTHORED HEIGHT, NOT A SCALE FACTOR. 50 is the primary action on a panel
	-- and 46 is everything else; they become 44 and 40, and the gap between the two tiers survives
	-- so the hierarchy still reads. Everything else in this file is sized against something other
	-- than "an action button" -- the close X is 42, a tier chip is 34, the Robux hero cards are 60+
	-- -- and a blanket multiplier would drag every one of them off its own grid. Anything not one
	-- of those two numbers comes out exactly as it was authored.
	--
	-- A Y.Scale term means the parent owns the height, so those are left alone too.
	-- Mirrored in UITheme.Button, which is the other way a button in this game gets built.
	do
		local h = btn.Size.Y.Offset
		if btn.Size.Y.Scale == 0 and (h == 50 or h == 46) then
			btn.Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset, 0, h == 50 and 44 or 40)
		end
	end

	local strokeInst = styleCard(btn, baseColor, radius, thickness)

	if btn:IsA("TextButton") then
		-- A TextButton's own text draws at the button's ZIndex, i.e. UNDER the gloss. Mirror it
		-- into a child label above the gloss so `btn.Text = ...` keeps working at every call site.
		-- ===== THE MIRROR IS FOUND BY ITS MARK, NOT BY ITS NAME (33.13) =====
		--
		-- Reusing the existing mirror is the right call -- a second `styleButton` pass over the same
		-- button used to leave two stacked TextLabels and two property connections behind, and the
		-- doubled glyph reads as a smeared caption rather than as a bug. But `FindFirstChild("Label")`
		-- is not how to find it: **"Label" is the house name for a caption in three other places**.
		-- `UITheme`'s tile names its icon slot "Label" and that slot is an **ImageLabel** whenever the
		-- icon resolves to art (the note there says the name is kept deliberately, because six call
		-- sites reach in by it), and `InventoryTabs` builds its own "Label" caption on each tab. Adopt
		-- one of those and the caption is overwritten with the button's own `Text` -- or the write
		-- throws outright, since an ImageLabel has no `TextColor3`.
		--
		-- The attribute is set on the line below and nowhere else in the codebase, so it can only
		-- ever match a mirror this function made.
		local proxy
		for _, child in ipairs(btn:GetChildren()) do
			if child:GetAttribute("UIKitTextMirror") then
				proxy = child
				break
			end
		end
		if not proxy then
			proxy = Instance.new("TextLabel")
			proxy.Name = "Label"
			proxy:SetAttribute("UIKitTextMirror", true)
			proxy.BackgroundTransparency = 1
			proxy.Size = UDim2.new(1, -14, 1, -10)
			proxy.Position = UDim2.new(0.5, 0, 0.5, 0)
			proxy.AnchorPoint = Vector2.new(0.5, 0.5)
			proxy.ZIndex = btn.ZIndex + UITheme.Z.Content
			proxy.Parent = btn
			btn:GetPropertyChangedSignal("Text"):Connect(function()
				proxy.Text = btn.Text
			end)
			btn:GetPropertyChangedSignal("TextColor3"):Connect(function()
				proxy.TextColor3 = btn.TextColor3
			end)
		end
		proxy.TextColor3 = btn.TextColor3
		proxy.TextWrapped = true
		proxy.Text = btn.Text
		themeLabel(proxy, 24)
		btn.TextTransparency = 1

		-- PRESS FEEDBACK THAT SURVIVES A LAYOUT.
		--
		-- The sink was `btn.Position = resting + 3px`, and a UIListLayout or UIGridLayout parent
		-- rewrites Position on every layout pass -- so it was reverted before it could be seen. Every
		-- button inside a list was silently dead on click: the bottom-right quick row, the Pets
		-- action row, the Pets/Potions tabs, the Season track. AutoButtonColor is off too, so there
		-- was no fallback tint either -- half the game's buttons simply did not respond.
		--
		-- A UIScale is not a layout property, so nothing overwrites it. Squashing to 0.96 reads as
		-- the same push as a 3px sink and works identically in a list, in a grid and free-positioned.
		-- The lip that used to shrink from 6px to 3px alongside the squash is gone (see styleCard),
		-- so the UIScale is the whole of the press now. It was always the part that actually read
		-- as a press -- and unlike the old sibling shadow it scales WITH the button, which is why
		-- pressing no longer makes a dark edge pop out around the shell.
		local squash = btn:FindFirstChildOfClass("UIScale")
		if not squash then
			squash = Instance.new("UIScale")
			squash.Parent = btn
		end
		local pressed = false
				local TweenService = game:GetService("TweenService")
		local GuiService = game:GetService("GuiService")
		btn.MouseButton1Down:Connect(function()
			if pressed then return end
			pressed = true
			local t = GuiService.ReducedMotionEnabled and 0 or 0.06
			TweenService:Create(squash, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.96}):Play()
		end)
		local function release()
			if not pressed then return end
			pressed = false
			local t = GuiService.ReducedMotionEnabled and 0 or 0.12
			TweenService:Create(squash, TweenInfo.new(t, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		end
		btn.MouseButton1Up:Connect(release)
		btn.MouseLeave:Connect(release)
	end

	return strokeInst
end

-- ===== RE-TINT AN ALREADY-STYLED SURFACE -- AND ACTUALLY REPAINT IT (15.28) =====
--
-- `UITheme.SetColor` paints `inst.BackgroundColor3` and `inst.Gradient`, which is correct for the
-- shells UITheme builds itself. `styleCard` above -- this file's own helper, and the ~30 legacy
-- call sites' -- does NOT keep the colour there: it sets the host fully transparent and moves the
-- fill into an `InnerBody` child carrying its own gradient, with a `ShadowBody` for the lip.
--
-- So SetColor on a styleCard surface wrote a colour nothing draws, and returned quietly. Every
-- state recolour in this file was dead on arrival: the CLAIM! buttons, the Auto toggle, the Robux
-- tabs, the potion rows, the Season track's nodes. Only the UIStroke recolours beside them ever
-- showed, which is why so many states here are told apart by their rim alone.
--
-- Fixed here rather than in UITheme, because the two structures are genuinely different and
-- UITheme's own widgets still want its version -- which is still called first, so the `BaseColor`
-- attribute and the tile-body case keep working exactly as before.
local function setButtonColor(btn, baseColor)
	UITheme.SetColor(btn, baseColor)
	local body = btn:FindFirstChild("InnerBody")
	if not body then return end
	body.BackgroundColor3 = baseColor
	local grad = body:FindFirstChild("Gradient")
	if grad and grad:IsA("UIGradient") then
		grad.Color = UITheme.GradientFor(baseColor)
	end
	-- the same -0.4 styleCard built the lip with, so a recoloured card keeps its moulded edge
	local lip = btn:FindFirstChild("ShadowBody")
	if lip then
		lip.BackgroundColor3 = UITheme.LipShade(baseColor)
	end
end

-- `gradientForColor` and `LIP_DEPTH` are exported for completeness but had NO caller outside
-- these lines when the kit was cut out -- `gradientForColor` had none at all. They are kept
-- rather than deleted because a dead helper is cheap and rule 10 of GEMINI.md is that nothing
-- gets removed on the side of a job that was not about removing it.
return {
	formatNumber = formatNumber,
	stroke = stroke,
	gradient = gradient,
	corner = corner,
	shade = shade,
	gradientForColor = gradientForColor,
	themeLabel = themeLabel,
	liftChildren = liftChildren,
	styleCard = styleCard,
	styleButton = styleButton,
	setButtonColor = setButtonColor,

	OUTLINE_COLOR = OUTLINE_COLOR,
	DISPLAY_FONT = DISPLAY_FONT,
	PANEL_SHELL = PANEL_SHELL,
	PET_ROW_SHELL = PET_ROW_SHELL,
	READY_RIM = READY_RIM,
	LIP_DEPTH = LIP_DEPTH,
}
