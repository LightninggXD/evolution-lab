--[[
	UITheme - shared "chunky comic" design system for Evolution Lab.

	Every interactive surface = thick dark outline + rounded corners + vertical body
	gradient + hard drop shadow + faint glossy sheen + outlined display text.

	HARD INVARIANT (this is the bug that started the redesign):
		Gloss BackgroundTransparency >= 0.72 AND every text/content child renders at a
		strictly HIGHER ZIndex than the gloss.
		Layering, as the `Z` table below actually defines it -- this line used to read
		"Shell(0) < Gloss(+1) < Content(+3) < Badge(+5)", which has not been true since the
		`Body` level was inserted, and `Z` is the authority:
			Shadow(-1) < Shell(0) < Body(1) < Gloss(2) < Content(4) < Badge(6) < Overlay(8)

	THEME: bright pastel and white surfaces inside a near-black outline (17.18). The outline
	(`Color.Outline`) is the signature of the style and is never a fill; the pastel pass replaced
	the dark chrome that call sites had been building out of `Shade(Color.Outline, n)`. Three
	things follow from a near-white fill and all three are handled off one constant -- see
	`LIGHT_SURFACE`: the ink flips dark (and drops its halo in the same branch), the body gradient
	runs downward instead of upward, and the shadow lip softens.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundLibrary = require(script.Parent:WaitForChild("SoundLibrary"))
local IconLibrary = require(script.Parent:WaitForChild("IconLibrary"))

local UITheme = {}

-- ============================================================================
-- MICRO-INTERACTION TWEEN CONFIGURATIONS
-- ============================================================================
local HOVER_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEAVE_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_DOWN_INFO  = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- 0.12, DOWN FROM 0.20 (18.1, research §2.3). The press is two different events wearing one number
-- in `readme.md` ("~120-200 ms"), and only the RELEASE wants the slow half of that range: a press
-- that takes a fifth of a second to come back up is still visibly travelling when the finger has
-- already moved on. §2.3's split is 0.06 s down / 0.12 s back, and 0.06 was already what
-- PRESS_DOWN_INFO shipped with, so this is the one half that was wrong.
local PRESS_UP_INFO    = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE_TWEEN_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- ============================================================================
-- ACCESSIBILITY: THE MOTION KILL-SWITCH (18.1, research §2.6)
-- ============================================================================
--
-- `GuiService.ReducedMotionEnabled` is a player setting, not a device capability, and Roblox's own
-- remedy for it is one sentence: "set the `TweenInfo.Time` parameter of a `TweenInfo` to `0`".
-- (https://create.roblox.com/docs/production/publishing/accessibility)
--
-- So this is the one place a duration is allowed to be decided, and every tween in the kit -- and
-- every tween in `MainUI` that routes through `UITheme.Tween` -- is covered by the two functions
-- below rather than by 60 call sites remembering.
--
-- ===== WHY "TIME = 0" IS NOT ALWAYS ENOUGH, AND THE RULE THAT FALLS OUT OF IT =====
--
-- A tween at time 0 lands on its TARGET instantly. That is exactly right for a transition -- a panel
-- opening to `FitScale`, a progress bar moving to 62%, a press dropping to 0.94 -- because arriving
-- is the correct end state and all the player loses is the travel.
--
-- It is exactly WRONG for a tween whose target is not a resting state: an idle attention pulse
-- targets 1.05 and relies on `reverses` to come back, so a zero-time version leaves the tile
-- permanently 5% too big, and a `repeatCount = -1` at time 0 is an infinite loop of instant
-- completions. Those two facts are why this exposes a READABLE FLAG as well as a rewriter:
--
--   * a tween that ENDS where it should rest       -> just play it through `UITheme.Tween`
--   * a tween that only looks right while moving   -> ask `UITheme.ReducedMotion()` and skip it
--
-- `Celebrate` and `Attention` below are the two that ask; everything else plays.
--
-- Read through pcall and cached, for two reasons. The property is engine-version dependent (it did
-- not exist before 2023 and this module is required by three SERVER scripts, where GuiService is
-- inert), and reading it per tween would be a property read on every button press for a value that
-- changes about once a session. The subscription keeps the cache honest without polling.
local GuiService do
	local ok, svc = pcall(function()
		return game:GetService("GuiService")
	end)
	GuiService = ok and svc or nil
end

local reducedMotion = false
local preferredTransparency = 1

local function readAccessibility()
	if not GuiService then
		return
	end
	pcall(function()
		reducedMotion = GuiService.ReducedMotionEnabled == true
	end)
	pcall(function()
		local v = GuiService.PreferredTransparency
		if type(v) == "number" then
			preferredTransparency = math.clamp(v, 0, 1)
		end
	end)
end

if RunService:IsClient() and GuiService then
	readAccessibility()
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(readAccessibility)
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(readAccessibility)
	end)
end

-- TRUE when the player has asked for less motion. Ask this before starting anything that is only
-- correct while it is moving -- see the rule above.
function UITheme.ReducedMotion()
	return reducedMotion
end

-- Same argument list as `TweenInfo.new`, so it is a drop-in: `UITheme.Motion(0.22,
-- Enum.EasingStyle.Back, Enum.EasingDirection.Out)`. Under reduced motion it returns the same curve
-- with the TIME, the REPEAT and the DELAY all taken out -- a repeat of -1 at zero time would spin
-- the scheduler forever, so it cannot simply zero the duration and keep the rest.
function UITheme.Motion(time, style, direction, repeatCount, reverses, delayTime)
	if reducedMotion then
		return TweenInfo.new(0, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, 0)
	end
	return TweenInfo.new(
		time or 1,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out,
		repeatCount or 0,
		reverses or false,
		delayTime or 0
	)
end

-- The other door in, for the ~60 places that already hold a TweenInfo built at file scope (this
-- module's own five constants, `MainUI`'s OPEN/SHUT pair). Rewrites the info at PLAY time rather
-- than at build time, which is the only correct moment: a constant built when the module loaded
-- cannot know about a setting the player flips ten minutes later.
--
-- Returns the Tween so a caller that has to `:Cancel()` it -- `PanelMotion`, `CountTo` -- still can.
function UITheme.Tween(inst, info, goal)
	if not inst or not info or not goal then
		return nil
	end
	local use = info
	if reducedMotion then
		use = TweenInfo.new(0, info.EasingStyle, info.EasingDirection, 0, false, 0)
	end
	local tween = TweenService:Create(inst, use, goal)
	tween:Play()
	return tween
end

-- ===== THE SCRIM, WHICH IS THE ONE THING THIS HUD ACTIVELY FIGHTS (research §5.2) =====
--
-- `GuiService.PreferredTransparency`: "A value of 1 indicates the player prefers the default
-- background transparency, while a value of 0 indicates the player prefers fully opaque." So a
-- player who has asked for opaque backgrounds should get a SOLID scrim behind a modal, not a 45%
-- one -- and the formula is a multiply rather than a branch so every value in between works too.
--
-- Takes the alpha you would have used and returns the one to use. `UITheme.ScrimTransparency(0.45)`
-- is 0.45 at the default setting and 0 at the fully-opaque end.
function UITheme.ScrimTransparency(base)
	return math.clamp((base or 0.45) * preferredTransparency, 0, 1)
end

function UITheme.PreferredTransparency()
	return preferredTransparency
end


-- THE CLICK, IN THE ONE PLACE EVERY BUTTON ALREADY GOES THROUGH.
--
-- Every interactive surface in the game is a UITheme.Button or a UITheme.IconTile, so Phase 4.4 is
-- two lines here rather than a Play() beside a couple of hundred separate MouseButton1Click
-- connections -- and a button added next year gets its click without anyone remembering to ask.
--
-- Guarded on IsClient, and that guard is not defensive padding: this module is NOT client-only.
-- CreatureService and BossService both require it on the server for colours and label styling, and
-- a Sound created on the server REPLICATES -- so an unguarded click here would fire a button press
-- into every player's ears at once, from a server that never pressed anything.
local function clickSound()
	if RunService:IsClient() then
		SoundLibrary.PlayLocal("click")
	end
end

-- ============================================================================
-- PALETTE
-- ============================================================================
local Color = {
	Outline    = Color3.fromRGB(26, 18, 36),
	Shadow     = Color3.fromRGB(18, 12, 26),
	White      = Color3.fromRGB(255, 255, 255),
	Cream      = Color3.fromRGB(255, 248, 235),
	PanelWhite  = Color3.fromRGB(255, 255, 255),
	PanelBorder = Color3.fromRGB(0, 180, 255),
	PanelBlue   = Color3.fromRGB(80, 168, 245),
	Gold        = Color3.fromRGB(255, 198, 45),
	Orange      = Color3.fromRGB(250, 148, 38),
	Blue        = Color3.fromRGB(68, 162, 235),
	SkyBlue     = Color3.fromRGB(105, 205, 250),
	Green       = Color3.fromRGB(46, 204, 113),
	Red         = Color3.fromRGB(245, 68, 85),
	Purple      = Color3.fromRGB(165, 105, 245),
	Pink        = Color3.fromRGB(255, 105, 195),
	Grey        = Color3.fromRGB(150, 150, 165),
	Locked      = Color3.fromRGB(163, 161, 180),

	-- ===== THE BRIGHT PASTEL / WHITE CHROME (17.18) =====
	--
	-- Asked for in as many words: "nemoj te crne vec bright pastel i beli theme". The complaint is
	-- about SURFACES, not about the outline -- `Color.Outline` above is the signature of the whole art
	-- style and every one of these tokens is drawn inside it.
	--
	-- The kit could produce exactly four dark surfaces before this and three of them were built by
	-- CALL SITES out of `Shade(Color.Outline, 0.22)` -- rgb(76,70,84), a near-black capsule -- because
	-- there was no light chip token to reach for. These four are that token, plus the ink that has to
	-- come with it: a light fill under a white glyph is the one combination this kit CANNOT draw,
	-- since `outlineText` always haloes in `Color.Outline` and a white word on a near-white plate is
	-- then read entirely off its halo.
	--
	--   Ink      the dark glyph for a light surface. Same hue family as Outline (both a warm
	--            violet-black) but 22 points lighter, so a word set in it beside a shell outlined in
	--            Outline reads as ink rather than as more border. lum 0.17.
	--   InkSoft  secondary text on a light surface -- subtitles, units, "of 100". lum 0.37, still
	--            under the `isDarkInk` cut, so it drops its halo like any other dark ink.
	--   Frost    THE CHIP FILL. What a price capsule, a level badge and a currency capsule are made
	--            of now. A hair off pure white (a cool 240/243/252) so a chip sitting ON a white
	--            panel still has an edge of its own beyond the outline. lum 0.95.
	--   Cloud    one step deeper: an inset rather than a raised chip -- progress-bar tracks, wells,
	--            list backings. lum 0.89, still comfortably a light surface.
	Ink         = Color3.fromRGB(48, 38, 66),
	InkSoft     = Color3.fromRGB(104, 96, 132),
	Frost       = Color3.fromRGB(240, 243, 252),
	Cloud       = Color3.fromRGB(222, 228, 244),
	-- "you cannot afford this YET" -- NOT the same state as Locked, and it had been drawn with the
	-- same swatch since the shop was written. Locked means the row is unavailable: zone-gated, maxed,
	-- nothing selected. This means the button works, the price is real, and you are short. A dead
	-- neutral grey says "do not press me"; this keeps the hue and the value so the tile still reads as
	-- a live button whose price is out of reach. Used by BOTH upgrade rows on ShopFrame -- the DNA row
	-- did it too and was only ever photographed green because those four were affordable.
	--
	-- LIGHTENED 108,122,156 -> 132,148,200 for the pastel pass (17.18), and NOT merged into `Locked`.
	-- At lum 0.48 it was the darkest fill the kit could produce on purpose and it read as slate
	-- against a screen of candy. The two still have to be told apart at a glance and value alone
	-- cannot do it any more (Locked is 0.64, this is 0.59), so the separation moved to CHROMA: Locked
	-- is a neutral lilac grey (max channel minus min = 19), this is unmistakably blue (68). "Grey and
	-- dead" vs "blue and live, just out of reach" survives the lightening; a single merged token
	-- would have lost the distinction the swatch was added for.
	-- Lightened twice. rgb(108,122,156) at luminance 0.48 was the darkest deliberate fill in the kit;
	-- 132,148,200 took it to 0.58, and photographed against three green tiles it still read as a
	-- navy block -- the one dark rectangle left on the screen, which is the thing this pass exists
	-- to remove. 178,190,230 is luminance 0.73: unmistakably a periwinkle, unmistakably quieter than
	-- the Green it sits under, and no longer dark.
	--
	-- White ink with its 4 px halo is still correct at 0.73 and does NOT want the dark-ink flip: in
	-- this HUD the outline is what carries the contrast, and the InkOn cut sits at 0.86 precisely so
	-- that chromatic fills like this one keep the chunky white-on-colour look.
	Unaffordable = Color3.fromRGB(178, 190, 230),

	-- Bright pastel set -- used by the HUD tiles so the columns read as candy
	-- buttons rather than the darker panel chrome.
	Mint       = Color3.fromRGB(68, 225, 145),
	Sunny      = Color3.fromRGB(255, 212, 75),
	Bubblegum  = Color3.fromRGB(255, 130, 200),
	Lavender   = Color3.fromRGB(175, 138, 250),
	Aqua       = Color3.fromRGB(105, 205, 250),
	Peach      = Color3.fromRGB(255, 160, 95),
	Coral      = Color3.fromRGB(255, 95, 105),
}
UITheme.Color = Color

-- ============================================================================
-- Z ORDER CONTRACT
-- ============================================================================
local Z = {
	Shadow  = -1,
	Shell   = 0,
	Body    = 1,
	Gloss   = 2,
	Content = 4,
	Badge   = 6,
	Overlay = 8,
}
UITheme.Z = Z

-- ============================================================================
-- FONTS (guarded: FredokaOne may not exist on older Studio builds)
-- ============================================================================
local function probeFont(name, fallback)
	local ok, resolved = pcall(function()
		local probe = Instance.new("TextLabel")
		probe.Font = Enum.Font[name]
		local f = probe.Font
		probe:Destroy()
		return f
	end)
	if ok and typeof(resolved) == "EnumItem" and resolved.Name == name then
		return resolved
	end
	return fallback
end

local DisplayFont = probeFont("FredokaOne", Enum.Font.GothamBlack)
local BodyFont = probeFont("GothamBold", Enum.Font.GothamBlack)

UITheme.Font = {
	Display = DisplayFont,
	Body = BodyFont,
}

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

-- amt > 0 lightens toward white, amt < 0 darkens. (Same maths as MainUI.)
local function shade(c, amt)
	if amt >= 0 then
		return Color3.new(
			math.clamp(c.R + (1 - c.R) * amt, 0, 1),
			math.clamp(c.G + (1 - c.G) * amt, 0, 1),
			math.clamp(c.B + (1 - c.B) * amt, 0, 1)
		)
	end
	local k = 1 + amt
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end
UITheme.Shade = shade

-- ============================================================================
-- LIGHT SURFACES: ONE NUMBER, THREE DECISIONS (17.18)
-- ============================================================================
--
-- The pastel/white pass makes near-white a normal fill for the first time, and three separate things
-- in this file break silently on one:
--
--   1. the LABEL. `outlineText` always haloes in `Color.Outline`, so white-on-white is a word you
--      read entirely off its outline -- fine at 30pt, mush at the 13pt HUD caption floor.
--   2. the GRADIENT. `gradientFor` lightens the top by 0.4, and 0.4 of the way from rgb(240) to
--      white is rgb(246): a white card's three stops land within six values of each other and the
--      moulding disappears. See the light curve below.
--   3. the LIP. `applyShell` drops the ShadowBody 40%, which under a white card is rgb(153) -- a
--      grey slab, i.e. exactly the dark chrome this pass exists to remove.
--
-- All three ask the same question, so they ask it once, of one constant.
--
-- ===== WHY 0.86, FOR THIS PALETTE =====
--
-- Measured, not copied -- a cut carried over from another kit is what twice put white ink on
-- mid-tone fills at ~2.8:1. This palette has two clearly separated populations and the cut goes in
-- the gap between them:
--
--   CHROMATIC FILLS, every saturated and pastel token: Red 0.48, Purple 0.55, Blue 0.56, Coral 0.57,
--   Green 0.57, PanelBlue 0.59, Grey 0.60, Lavender 0.64, Locked 0.64, Orange 0.65, Mint 0.66,
--   Pink 0.63, Bubblegum 0.69, SkyBlue/Aqua 0.71, Peach 0.71, Gold 0.78, **Sunny 0.82** (the top).
--   Every one of these is a white-ink surface today and stays one -- white plus a 4px near-black
--   halo IS the chunky sticker look, and flipping the HUD tiles to dark ink would trade the whole
--   aesthetic for a contrast score.
--
--   LIGHT NEUTRALS: Cloud 0.89, Frost 0.95, Cream 0.97, PanelWhite/White 1.00. These are the ones
--   a white glyph vanishes into.
--
-- The band between 0.82 and 0.89 is empty, so any cut inside it behaves identically on everything
-- that exists; 0.86 is its middle, which is the most room on both sides for a token added later.
-- The one value that lands near the line by construction is `shade(Sunny, 0.4)` = 0.88, the TOP STOP
-- of Sunny's own gradient -- and a caller who hands that in as a base fill genuinely does want dark
-- ink on it, so the answer there is right rather than merely tolerated.
local function luminance(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end
UITheme.Luminance = luminance

local LIGHT_SURFACE = 0.86

local function isLightSurface(c)
	return c ~= nil and luminance(c) >= LIGHT_SURFACE
end
UITheme.IsLightSurface = isLightSurface

-- THE INK RULE, and the reason it is a function rather than a habit. Six constructors in this file
-- hardcoded `Color.White` for their label because every surface they could be given was chromatic.
-- Each of them knows the fill it is printing on, so each of them can ask -- and a seventh added next
-- year inherits the answer instead of inheriting the habit.
--
-- Returns the INK ONLY. The halo is the caller's second half of the same decision and must be made
-- in the same branch (see `outlineText`): dark ink inside a `Color.Outline` stroke is a solid blob
-- that reads correct in every property and fails only in a capture.
local function inkOn(fill)
	if isLightSurface(fill) then
		return Color.Ink
	end
	return Color.White
end
UITheme.InkOn = inkOn

-- ============================================================================
-- A FINISHED THING IS NOT A DISABLED THING (18.5)
-- ============================================================================
--
-- The kit has one swatch for *off* -- `Color.Locked`, a neutral lilac grey -- and four different
-- states reach for it: locked, unaffordable, spent, and DONE. The first three are refusals and grey
-- is right for them. The fourth is the record of something the player achieved, and painting it in
-- the refusal colour is what made the Daily Rewards panel read as *"kao da dobijam rewards sto radim
-- u mrtvacnici"*: six days collected, six grey slabs, one bright tile at the end.
--
-- `DoneShade` is the third state the kit was missing. It keeps the hue EXACTLY -- so a claimed DNA
-- day is still green and a claimed potion day is still purple, and the panel keeps the colour
-- variety it earned -- and takes the chroma down to about a third while holding the value in the
-- light-surface band. The result is a pastel of the reward's own colour: unmistakably quieter than
-- the live tile beside it, unmistakably not the grey of a thing you cannot have.
--
-- The three states are then separated on three different axes, which is what keeps them tellable
-- apart at a glance and in a screenshot:
--
--   claimable  full chroma, full weight -- the loudest object on the panel
--   done       the same HUE, a third of the chroma        (this function)
--   locked     no hue at all                              (`Color.Locked`)
--
-- ===== AND WHY IT FINISHES ON A MEASURED LUMINANCE RATHER THAN ON AN HSV VALUE =====
--
-- Desaturating in HSV alone lands the six reward hues on wildly different luminances -- measured,
-- Green 0.77 against Gold 0.90 -- and `LIGHT_SURFACE` cuts at 0.86 right through the middle of that
-- spread. Two claimed tiles side by side would then take DIFFERENT INK, one dark and one white,
-- from the same function: exactly the unreadable-caption family this file has already paid for
-- three times. So the last step lifts every result to luminance 0.90 by blending toward white,
-- which is exact rather than iterative (`luminance` is linear in RGB, so a blend of `t` moves it to
-- `l + (1-l)*t`) and preserves hue. Every done shade is therefore a light surface **by
-- construction**, takes `Color.Ink`, and cannot flip.
local function doneShade(c)
	local h, s, v = Color3.toHSV(c)
	local pale = Color3.fromHSV(h, s * 0.34, math.max(v, 0.85))
	local l = luminance(pale)
	if l < 0.90 then
		pale = shade(pale, (0.90 - l) / (1 - l))
	end
	return pale
end
UITheme.DoneShade = doneShade

-- ============================================================================
-- THE BUTTON GRADIENT -- ONE CURVE, EVERY SURFACE IN THE GAME
-- ============================================================================
-- This function is the single lever for the whole UI's look: UITheme's own applyShell, the
-- progress bars, the icon tiles AND MainUI's `styleCard` (via UITheme.GradientFor) all read it.
-- Change the four numbers here and every button, card, panel and tile changes together.
--
-- The curve is measured off the reference art rather than invented: the top edge is a strong
-- lighten toward white, the middle sits just above the base colour, and the bottom is a DEEPER
-- version of the same hue -- not a dark one.
--
-- That last stop is the whole difference. It used to be shade(c, -0.70), i.e. 30% of the colour,
-- which is nearly black: every button faded from candy at the top to mud at the bottom and read as
-- plastic lit from above rather than as a painted toy. -0.28 keeps the bottom recognisably blue,
-- yellow, green -- the button stays one colour with a light and a shadow side, which is what the
-- reference does.
--
-- The stops are also weighted toward the top (0.42 rather than 0.55) so the light half is slightly
-- larger than the dark half. Even split reads as a two-tone stripe; uneven reads as a curved
-- surface.
--
-- ===== A NEAR-WHITE FILL NEEDS THE CURVE RUN THE OTHER WAY (17.18) =====
--
-- The stops above are all expressed as a LIGHTENING (+0.4, +0.05) with one small darkening at the
-- foot (-0.1), which is the right shape for a chromatic fill: there is somewhere to go in both
-- directions. On a near-white fill there is nowhere to go up. rgb(240,243,252) lightened by 0.4 is
-- rgb(246,248,253) and by 0.05 is rgb(241,244,252) -- the top two thirds of the card are the same
-- six values, and the whole moulding is a single -0.1 nudge at the very bottom. That is a flat white
-- rectangle with a slightly grubby foot, which is what "a white card reads flat" means.
--
-- So the light curve spends its whole range downward: pure white at the crown, the fill itself just
-- above the middle, and a real -0.20 at the foot. rgb(240,243,252) then runs 255 -> 240 -> 192,
-- which is a lit dome rather than a wash, and it is the SAME optical story the chromatic curve tells
-- (bright top, base colour just above centre, deeper version of itself at the bottom) drawn with the
-- only headroom a light fill has.
--
-- CHOSEN BY THE FILL, NEVER BY THE CALLER. `gradientFor` is read by `applyShell`, `SetColor`,
-- `ProgressBar`, `IconTile` and MainUI's own `styleCard`; a `light = true` option would be five call
-- sites that have to remember, and the one that forgets is a flat card nobody notices for a month.
-- 0.38 rather than 0.35 for the middle stop, so the light half stays the larger one -- same reason
-- the chromatic curve is weighted toward the top.
local function gradientFor(c)
	if isLightSurface(c) then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color.White),
			ColorSequenceKeypoint.new(0.38, c),
			ColorSequenceKeypoint.new(1.00, shade(c, -0.20)),
		})
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, shade(c, 0.4)),
		ColorSequenceKeypoint.new(0.35, shade(c, 0.05)),
		ColorSequenceKeypoint.new(1.00, shade(c, -0.1)),
	})
end

-- There used to be a second, softer curve here for the HUD tiles, because the main one was too
-- dark for them. Now that gradientFor IS the soft curve, keeping two would mean two subtly
-- different button looks in one screen -- which is exactly what "every button identical" rules
-- out. Kept as a name so the four call sites that ask for it still read as intentional.
local pastelGradientFor = gradientFor

-- ============================================================================
-- THE LIP, AND WHY IT HAD TO LEARN ABOUT LIGHT FILLS TOO (17.18)
-- ============================================================================
-- `ShadowBody` is the shell's own rectangle shifted down 6 px and painted darker; all you ever see
-- of it is a 6 px band along the bottom edge, and that band is what makes a card read as a thing
-- with thickness rather than a decal.
--
-- It was a flat `shade(c, -0.4)`, i.e. 60% of the fill, which is correct on a chromatic surface --
-- Mint's foot is a deep green and still recognisably Mint. Under a WHITE card 60% is rgb(153): a mid
-- grey slab, on a screen whose whole complaint is dark chrome. -0.22 puts a white card's foot at
-- rgb(199) instead, which still steps clearly away from the -0.20 the light gradient ends on and is
-- still drawn inside the same near-black outline, so nothing about the sticker silhouette changes.
--
-- Public because MainUI's `styleCard` builds the identical lip on the identical geometry and the two
-- must not drift -- that pair has already been the cause of two separate "half the HUD looks
-- different" reports.
local function lipShade(c)
	return shade(c, isLightSurface(c) and -0.22 or -0.4)
end
UITheme.LipShade = lipShade

-- ============================================================================
-- THE SHAPE SCALE (10.18)
-- ============================================================================
-- Measured on the live HUD before this existed: **ten distinct corner radii** and **eight stroke
-- widths**. Not ten deliberate shapes -- 14, 16, 12, 20, 10 and 22 px alongside two scale-based
-- pills, each one whatever the person writing that panel happened to type. A radius is the main
-- thing that says what KIND of object you are looking at, so ten of them says nothing at all: the
-- eye cannot learn a vocabulary with ten words that differ by two pixels.
--
-- Four steps, named for what they are FOR rather than how big they are:
--
--   Pill  a capsule -- progress bars, currency capsules, anything read as a single value
--   Tile  the big pressable things: HUD tiles, action buttons
--   Card  a surface that holds content: panels, rows, list cells
--   Chip  small inline marks: badges, counters, tags
--
-- SNAPPED RATHER THAN ENFORCED. Three hundred call sites pass their own number and rewriting them
-- all would be a very large diff for a two-pixel change, with a real chance of breaking a layout
-- that depends on its radius. Instead every radius entering the theme is snapped to a step, so the
-- vocabulary becomes true without a single call site changing.
--
-- ROUNDER, AND ROUNDER IS A DIRECTION RATHER THAN A NEAREST VALUE (2026-08-16, asked for as "sve
-- nek bude ovalno" -- the whole button and HUD aesthetic). Two things changed together and they
-- have to: the ladder moved up 10/16/20 -> 14/22/30, and the snap stopped being symmetrical. The
-- nearest-step rule rounded a quarter of the HUD DOWN -- a call site asking for 24 got 20 -- which
-- is the system making a surface squarer than its author wrote it. It snaps UP now: every radius
-- lands on the first step at least as round as the one asked for. Nothing can get squarer, most
-- things get rounder, and no call site changes.
UITheme.Radius = {
	Pill = UDim.new(1, 0),
	Tile = UDim.new(0, 30),
	Card = UDim.new(0, 22),
	Chip = UDim.new(0, 14),
}

local RADIUS_STEPS = { 14, 22, 30 }

-- The same argument for the outline. Measured: **eight distinct stroke widths** -- 4, 3, 5, 0, 3.5,
-- 2, 2.5 and 6. The border is the loudest thing about this style, so half-pixel differences in it
-- are not subtlety, they are noise. Three weights, and zero stays zero because "no outline at all"
-- is a real choice rather than a thin one.
--
--   Heavy  panels and anything that frames other content
--   Base   buttons, cards, tiles -- the overwhelming majority
--   Fine   small inline marks where Base would swallow the fill
UITheme.Stroke = { Heavy = 5, Base = 4, Fine = 3 }

local STROKE_STEPS = { 3, 4, 5 }

local function snapStroke(t)
	if type(t) ~= "number" or t <= 0 then
		return t
	end
	local best, bestD = STROKE_STEPS[1], math.huge
	for _, step in ipairs(STROKE_STEPS) do
		local d = math.abs(t - step)
		if d < bestD then best, bestD = step, d end
	end
	return best
end
UITheme.SnapStroke = snapStroke

local function snapRadius(u)
	-- a scale-based radius is already a pill and has no pixel value to snap
	if u.Scale > 0 then
		return u
	end
	local px = u.Offset
	if px <= 0 then
		return u
	end
	-- the first step at least as round as what was asked for -- never a step below it
	for _, step in ipairs(RADIUS_STEPS) do
		if px <= step then
			return UDim.new(0, step)
		end
	end
	-- past the top of the ladder is a deliberate large shape (a panel corner) and is left alone;
	-- snapping a 40 px panel down to 30 would be the system overriding a real decision.
	return u
end
UITheme.SnapRadius = snapRadius

local function toUDim(radius, default)
	if typeof(radius) == "UDim" then
		return snapRadius(radius)
	end
	if type(radius) == "number" then
		return snapRadius(UDim.new(0, radius))
	end
	return default or UITheme.Radius.Card
end

local LIP_DEPTH = 6

-- ============================================================================
-- THE DROP SHADOW, THIRD ATTEMPT AND THE FIRST ONE THAT IS NOT A FRAME (18.5)
-- ============================================================================
--
-- Asked for in as many words on 2026-08-16: *"da ima neku dimenziju da izgleda 3d senke neke"*. The
-- kit has had no shadow since 2026-08-11, when both Frame-based variants were removed on her own
-- play-test report ("an ugly line at the bottom of the button that even sticks out"). Both deserved
-- it, and the reason was never taste -- it is that **a Frame cannot be soft**. Alpha falling off
-- over a distance is the whole of what a shadow is, and `UICorner` + `BackgroundTransparency` can
-- express exactly one hard edge. Every offset copy of a rounded shell therefore pokes a hard dark
-- crescent out of the corners the shell has already curved away from, which is what she saw twice.
--
-- So this one is a sprite: `assets/ui/shadow.png`, drawn by `tools/make_shadow.py` -- a rounded
-- rectangle blurred at sigma 14, black, with the entire falloff in the ALPHA channel so the game
-- can tint and fade it without fighting the art. Nine-sliced, so one 192 px image serves a 640 px
-- panel and an 82 px tile without deforming its corners.
--
-- THE FOUR NUMBERS, AND WHY EACH IS WHAT IT IS
--
--   SLICE_SCALE 0.5   the corner slice is 78 px of art; at 0.5 it renders 39 px, of which ~15 is
--                     the rounded shape and ~21 the blur. Corners bigger than the shell they sit
--                     under is how a soft shadow starts reading as a halo.
--   PAD 24            = the art's own 48 px of transparent margin at that scale. The sprite's solid
--                     rectangle then lands EXACTLY on the shell's own rectangle -- the image is
--                     inflated by `2*PAD` and offset by `-PAD` -- so the shadow's shape is the
--                     shell's shape and only the falloff extends past it. This is the number that
--                     makes it look attached rather than placed.
--   DROP 6            the same 6 px the lip uses. One light source for the whole interface, and it
--                     is directly above: everything in this kit is lit from the top (`gradientFor`
--                     is a bright-top vertical, `addGloss` sits on the top edge).
--   0.62              measured against the brightest ground in the game rather than chosen. Any
--                     denser and a HUD tile over the pale Absolute Plane grows a visible black
--                     puddle; any lighter and it is gone over the Forest's mid-green.
--
-- SCOPE, deliberately narrow on both axes:
--   * ROUND SHELLS ARE SKIPPED -- pills, circles, capsules, every progress bar. A nine-slice keeps
--     its corner radius in PIXELS while a pill's radius is half its own height, so under a 46 px
--     capsule the sprite's corners are the wrong shape by construction. Those surfaces already
--     carry their depth in the gradient and the outline, which is the same conclusion `applyShell`
--     reached about the lip one shape earlier.
--   * CLIENT ONLY -- `UITheme` is required on the SERVER by CreatureService and BossService, and a
--     shadow behind a creature's billboard is a smudge on the world rather than depth on a screen.
--     Same guard that already keeps `UITheme` from creating Sounds on the server.
local SHADOW_ASSET       = "rbxassetid://105729101275739"
local SHADOW_SLICE       = Rect.new(78, 78, 114, 114)
local SHADOW_SLICE_SCALE = 0.5
local SHADOW_PAD         = 24
local SHADOW_DROP        = 6
local SHADOW_ALPHA       = 0.62

-- Forward declaration: `applyShell` is defined below this line and calls it, while the definition
-- itself wants `toUDim` and the constants above. Assigned before anything can call either.
local dropShadow

-- Thick dark outline + rounded corners + moulded vertical gradient.
local function applyShell(inst, color, radius, thickness)
	local cornerRadius = toUDim(radius)
	
	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0

	local oldCorner = inst:FindFirstChild("UICorner")
	if oldCorner then oldCorner:Destroy() end
	local oldStroke = inst:FindFirstChild("UIStroke")
	if oldStroke then oldStroke:Destroy() end

	-- ===== A SMALL LIGHT CHIP IN A 5 px RIM IS MOSTLY RIM (17.18) =====
	--
	-- The outline stays -- it is the single most recognisable thing about this style and none of the
	-- pastel pass touches it. What changes is only the DEFAULT weight, and only where the geometry
	-- makes Heavy self-defeating: a 26 px price capsule with 5 px of near-black on every side has
	-- 16 px of fill left down the middle, so the chip reads as a black lozenge with a pale seam
	-- rather than as a white chip with a border. On a chromatic chip that is survivable because the
	-- fill is loud; on a Frost one the rim outweighs the surface it is framing.
	--
	-- Down the existing ladder (`STROKE_STEPS` = {3,4,5}) rather than to an invented width, and only
	-- when ALL THREE hold: the caller passed no thickness at all, the surface is light, and it was
	-- authored short in pixels. Nothing in the kit today satisfies all three -- every short surface
	-- is currently dark chrome, which is the thing being replaced -- so this changes nothing until a
	-- chip is actually made light, and then it is already right.
	local strokeT = thickness
	if strokeT == nil then
		local h = inst.Size.Y
		local shortChip = (h.Scale == 0 and h.Offset > 0 and h.Offset <= 34)
		strokeT = (shortChip and isLightSurface(color)) and UITheme.Stroke.Fine or UITheme.Stroke.Heavy
	end
	strokeT = snapStroke(strokeT)

	-- A PILL HAS NO ROOM FOR A LIP, AND THAT IS WHAT THE BLACK BEHIND THE HEALTH BAR WAS.
	-- The lip is the body's own rectangle, shifted down LIP_DEPTH and painted dark. On a card that
	-- reads as thickness: the shell's straight sides hide it and only the bottom edge shows. On a
	-- STADIUM the sides ARE the curve -- shift that shape down and its flanks swing outwards into
	-- exactly the part of the bounding box the body has already curved away from, so a dark crescent
	-- appears at both ends of every pill in the game. `ProgressBar` sets ClipsDescendants, which
	-- squares those crescents off into two black blocks capping the bar: that is the health bar
	-- Kristina photographed on 2026-08-16 ("ima nesto crno iza, lose izgleda").
	--
	-- Nothing is lost by dropping it on a round shell. The moulded depth there is carried by the
	-- body's own vertical gradient and the heavy outline -- which is the same conclusion `addShadow`
	-- reached above, for the same geometry, one shape earlier.
	local lipDepth = (cornerRadius.Scale >= 0.5) and 0 or LIP_DEPTH

	local shadowBody = inst:FindFirstChild("ShadowBody") or Instance.new("Frame")
	shadowBody.Name = "ShadowBody"
	shadowBody.Size = UDim2.new(1, 0, 1, 0)
	shadowBody.Position = UDim2.new(0, 0, 0, lipDepth)
	shadowBody.BackgroundColor3 = lipShade(color)
	shadowBody.BackgroundTransparency = 0
	shadowBody.BorderSizePixel = 0
	shadowBody.ZIndex = inst.ZIndex + Z.Shell
	
	local shadowCorner = shadowBody:FindFirstChild("UICorner") or Instance.new("UICorner")
	shadowCorner.Name = "UICorner"
	shadowCorner.CornerRadius = cornerRadius
	shadowCorner.Parent = shadowBody

	local shadowStroke = shadowBody:FindFirstChild("UIStroke") or Instance.new("UIStroke")
	shadowStroke.Name = "UIStroke"
	shadowStroke.Thickness = strokeT
	shadowStroke.Color = Color.Outline
	shadowStroke.Transparency = 0
	shadowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	shadowStroke.LineJoinMode = Enum.LineJoinMode.Round
	shadowStroke.Parent = shadowBody
	shadowBody.Parent = inst

	local body = inst:FindFirstChild("InnerBody") or Instance.new("Frame")
	body.Name = "InnerBody"
	body.Size = UDim2.new(1, 0, 1, 0)
	body.Position = UDim2.new(0, 0, 0, 0)
	body.BackgroundColor3 = color
	body.BackgroundTransparency = 0
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.ZIndex = inst.ZIndex + Z.Body
	
	local bodyCorner = body:FindFirstChild("UICorner") or Instance.new("UICorner")
	bodyCorner.Name = "UICorner"
	bodyCorner.CornerRadius = cornerRadius
	bodyCorner.Parent = body

	local bodyStroke = body:FindFirstChild("UIStroke") or Instance.new("UIStroke")
	bodyStroke.Name = "UIStroke"
	bodyStroke.Thickness = strokeT
	bodyStroke.Color = Color.Outline
	bodyStroke.Transparency = 0
	bodyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bodyStroke.LineJoinMode = Enum.LineJoinMode.Round
	bodyStroke.Parent = body
	body.Parent = inst

	local grad = body:FindFirstChild("Gradient") or Instance.new("UIGradient")
	grad.Name = "Gradient"
	grad.Rotation = 90
	grad.Color = gradientFor(color)
	grad.Parent = body

	inst:SetAttribute("BaseColor", color)

	-- The shell casts. `dropShadow` decides for itself whether this shape is allowed one (18.5), and
	-- an `inst` carrying the `NoShadow` attribute opts out -- which is how a surface that is already
	-- inside another shell (a chip on a card) says it is not a raised object.
	if dropShadow then
		dropShadow(inst, cornerRadius)
	end

	return bodyCorner, bodyStroke, grad
end

--[[
	THE DROP SHADOW IS GONE, ON PURPOSE (2026-08-11 play-test feedback).

	It had two variants and both drew outside the shell they belonged to:

	  * the SIBLING variant was a full-size opaque `Color.Shadow` rectangle parented next to the
	    button and offset 5px down. On a rounded shell that leaves a hard dark crescent poking out
	    of the bottom corners, and on the HUD tiles it is the "ugly line at the bottom of the
	    button that even sticks out" in the report. It also never shrank with the press: the squash
	    is a UIScale on the BUTTON, and the shadow is not a child of the button, so pressing made
	    the button smaller and left the shadow at full size popping out around it.
	  * the LIP variant was a full-width 6px bar anchored at the bottom carrying the shell's FULL
	    corner radius. A bar as wide as the shell, at a height where the shell has already curved
	    inwards, is wider than the shell is there -- so it stuck out of both bottom corners, and on
	    a circular shell (the Journal discs) it stuck out badly.

	Nothing replaces them. The moulded depth now comes entirely from the shell's own vertical
	gradient (see `gradientFor`: bright top, -0.28 bottom) plus the heavy dark outline, which is
	what actually carries the sticker look -- and neither of those can cross an edge, because they
	ARE the edge. Press feedback is the UIScale squash in `styleButton`, which was always the thing
	doing the visible work.

	Kept as a function with its old signature so the four call sites and their `opts.shadow ~= false`
	guards keep working. Returns: nil, no-op pressFn.
]]
local function addShadow(_inst, _radius)
	return nil, function() end
end

-- The sprite shadow promised by the constants at the top of this file (18.5).
--
-- Idempotent: it finds its own child before making one, so a surface re-shelled by a state change
-- (`SetColor` does not call this, but `styleCard` and `applyShell` both may run twice on the same
-- instance) gets one shadow rather than a stack of them.
--
-- A child of the shell, NOT a sibling. That is the fix for the half of the 2026-08-11 complaint
-- nobody has written down since: the old sibling variant never shrank with the press, because the
-- squash is a `UIScale` on the button and a sibling is not inside it -- so pressing made the button
-- smaller and left a full-size shadow poking out around it. A child scales, moves, hides and dies
-- with the thing casting it, automatically and for every caller.
dropShadow = function(inst, radius, opts)
	if not RunService:IsClient() then
		return nil
	end
	if inst:GetAttribute("NoShadow") then
		return nil
	end

	local cornerRadius = toUDim(radius)
	-- a round shell (a pill, a circle) is skipped -- see the note on the constants
	if cornerRadius.Scale >= 0.5 then
		local stale = inst:FindFirstChild("DropShadow")
		if stale then
			stale:Destroy()
		end
		return nil
	end

	opts = opts or {}
	local pad = opts.pad or SHADOW_PAD
	local drop = opts.drop or SHADOW_DROP

	local shadow = inst:FindFirstChild("DropShadow")
	if not shadow or not shadow:IsA("ImageLabel") then
		shadow = Instance.new("ImageLabel")
		shadow.Name = "DropShadow"
	end
	shadow.BackgroundTransparency = 1
	shadow.BorderSizePixel = 0
	shadow.Image = SHADOW_ASSET
	shadow.ImageColor3 = opts.color or Color.Shadow
	shadow.ImageTransparency = opts.transparency or SHADOW_ALPHA
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = SHADOW_SLICE
	shadow.SliceScale = opts.sliceScale or SHADOW_SLICE_SCALE
	shadow.Size = UDim2.new(1, pad * 2, 1, pad * 2)
	shadow.Position = UDim2.new(0, -pad, 0, -pad + drop)
	-- Below every body this shell owns. `Z.Shadow` is -1 and has been in the contract since the kit
	-- was written; this is the first thing that has ever used it.
	shadow.ZIndex = inst.ZIndex + Z.Shadow
	shadow.Active = false
	shadow.Parent = inst
	return shadow
end

-- Public, because `MainUI.styleCard` is a second copy of `applyShell` and builds most of the HUD.
-- One implementation, one set of numbers, whichever builder the surface came from.
UITheme.DropShadow = dropShadow

-- Faint top sheen. NEVER opaque, NEVER above content, and since 2026-08-11 never outside the
-- shell either.
--
-- ===== WHY IT USED TO STICK OUT, AND WHY IT CANNOT NOW =====
--
-- The old geometry was a fixed 0.88 x 0.4 box at (0.06, 0.06) with its corner radius HARDCODED to
-- `UDim.new(1, 0)` -- the function took a `radius` argument and ignored it. `ClipsDescendants` is
-- deliberately false on themed surfaces (badges are meant to hang outside an IconTile), so nothing
-- caught the overflow: on a low-radius button the pill's ends bulged past the shell's corners, and
-- on a CIRCULAR shell a rectangle inset only 6% from the bounding box has its top corners outside
-- the circle entirely. That is half of "the buttons look cut off at the sides".
--
-- The fix is geometric rather than a clip, so it holds at every size and needs no extra instance.
-- The sheen is inset by the shell's OWN corner radius, which is exactly where the shell's straight
-- top edge begins -- so a box inset by `r` (plus a little) spans only the part of the shell that is
-- flat, and cannot reach a curve. Two cases, because the two radius kinds mean different things:
--
--   * ROUND (Scale >= 0.5 -- a circle or a pill): inset to the middle 56% and start 10% down. A
--     circle's half-width at 10% of its height is 0.30 of its diameter, i.e. a 0.60 span, so a 0.56
--     span centred on it clears the rim with room at the tightest point and more everywhere below.
--   * RECTANGULAR: inset `r + 4` on each side and 5px from the top, with its own corner radius one
--     step under the shell's.
--
-- Transparency floor RAISED 0.72 -> 0.78. 0.72 is still the documented invariant and this respects
-- it; the sheen was reading as a white pill painted on the button rather than as light falling on
-- it, which is the other half of the complaint. It must never go BELOW 0.72 -- that number is a
-- contract, not a preference: any stronger and it starts washing out the white label under it.
local function addGloss(inst, radius)
	local cornerRadius = toUDim(radius)
	local round = cornerRadius.Scale >= 0.5

	local body = inst:FindFirstChild("InnerBody")
	
	local gloss = inst:FindFirstChild("Gloss") or Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color.White
	gloss.BackgroundTransparency = 0.72 -- invariant: >= 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = inst.ZIndex + Z.Gloss

	local corner = gloss:FindFirstChild("UICorner")
	if corner then corner:Destroy() end

	gloss.AnchorPoint = Vector2.new(0, 0)
	gloss.Position = UDim2.new(0, 0, 0, 0)
	
	if round then
		gloss.Size = UDim2.new(1, 0, 0.40, 0)
	else
		gloss.Size = UDim2.new(1, 0, 0.35, 0)
	end

	local grad = gloss:FindFirstChild("UIGradient") or Instance.new("UIGradient")
	grad.Name = "UIGradient"
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.7, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = gloss

	gloss.Parent = body or inst
	return gloss
end

-- The single most recognisable feature of the reference art. 4px to match the thicker shell
-- border above -- a heavy button frame around a thinly outlined word reads as two different
-- drawings sharing a rectangle.
-- DARK INK AND ITS HALO ARE ONE DECISION, AND THIS IS WHERE THE THRESHOLD LIVES (15.15).
--
-- `outlineText` always draws in `Color.Outline`, rgb(26,18,36). That is right for the white-on-
-- colour text this HUD is mostly made of and it is a solid blob around anything dark: the glyph and
-- its halo are then the same colour, and every property reads correct while it happens (`Text`,
-- `TextColor3`, `TextFits`), so it survives any probe and is only visible in a capture.
--
-- Phase 15.1 fixed this once, in `MainUI`'s own `themeLabel`, and the codebase then had the rule in
-- one of the two constructors that apply a halo. `UITheme.Label` is the other one, and the Group &
-- Community panel -- three card titles at ink 0.14 and three descriptions at 0.36, each inside a
-- 4px stroke at 0.09 -- is what that cost. The threshold belongs to a PALETTE rather than to a
-- file, so it is published here and both constructors read it instead of each carrying a copy.
--
-- ===== TWO CUTS, AND THEY ANSWER DIFFERENT QUESTIONS (17.18) =====
--
-- This one is about the GLYPH: "is the ink I was handed dark enough that a near-black halo round it
-- would be a blob". `LIGHT_SURFACE` (0.86, up the file) is about the FILL: "is the plate so pale
-- that a white glyph disappears into it". They are not the same number and neither is derivable from
-- the other -- a Sunny tile at 0.82 takes white ink, and ink at 0.82 would be absurd.
--
-- 0.45 SURVIVES THE PASTEL PASS UNCHANGED, and that was checked rather than assumed. The new tokens
-- put three deliberate dark inks in the palette -- Outline 0.08, Ink 0.17, InkSoft 0.37 -- and the
-- lightest thing this UI ever sets as ink on purpose is Locked at 0.64, with White at 1.00 above it.
-- Between 0.37 and 0.64 the palette holds nothing that is used as ink at all, so every cut in
-- [0.40, 0.60] behaves identically on every call site in the game and 0.45 is already inside it.
-- Moving it would be churn with a regression surface and no effect.
--
-- The thing that changed is what it is asked ABOUT. Until now the answer came from a colour a caller
-- had chosen by hand; six constructors below now derive their ink from the fill via `inkOn` and then
-- ask this, so the two halves of "dark ink drops its stroke" are made in one branch by construction
-- rather than by each author remembering.
local function isDarkInk(color)
	return luminance(color) < 0.45
end

local function outlineText(label, thickness)
	local t = thickness or 4
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = t
	stroke.Color = Color.Outline
	-- ===== A DROPPED HALO IS DROPPED TWICE, AND THAT IS NOT BELT-AND-BRACES (17.18) =====
	--
	-- Every site that suppresses the halo does it by passing thickness 0 -- `UITheme.Label`, `Pill`,
	-- MainUI's `themeLabel`, and now four more constructors below. Thickness is the one property a
	-- later pass is likely to write BACK: a responsive tier, a "make the outlines chunkier" sweep, or
	-- anything that walks `GetDescendants()` looking for UIStrokes and normalises them to the ladder.
	-- Any of those silently re-arms a near-black halo around dark ink -- the blob that reads correct
	-- in every property and is only visible in a capture.
	--
	-- Transparency is the property nothing else in this codebase writes on a text stroke, so setting
	-- both means the suppression survives a caller that only knows about width. Set HERE rather than
	-- at the seven call sites, so a site added later cannot forget the second half.
	stroke.Transparency = (t <= 0) and 1 or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

-- Big text, always. Never an 11-13px fixed TextSize on the HUD.
-- ⚠ `TextScaled = true` TURNS `TextWrapped` ON, and it does it silently. Measured on a live client
-- (15.16): a fresh TextLabel reads `TextWrapped = false`, setting `TextScaled = true` makes it read
-- **true**, and only an assignment placed AFTER that one sticks. So any caller that turns wrapping
-- off and then reaches a helper that scales has had its decision reversed one line later, with
-- every property still reading correct.
--
-- That is not hypothetical: the potion rows in `MainUI` carry a ten-line comment explaining that
-- their sub-label must never stack two lines into a 22px box, set `TextWrapped = false`, and then
-- called `themeLabel` -- which lands here. The three Luck bottles and the large Health bottle wrap
-- to 28px inside 22 and have their second line cut. `UITheme.Label`'s own `wrapped` option was
-- inert for the same reason, being applied before this call rather than after it.
local function autoSize(label, minSize, maxSize)
	label.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize or 14
	c.MaxTextSize = maxSize or 28
	c.Parent = label
	return c
end

UITheme.GradientFor = gradientFor
UITheme.OutlineText = outlineText
UITheme.AutoSize = autoSize
UITheme.IsDarkInk = isDarkInk

-- Shared body used by Button and Card.
local function buildSurface(inst, parent, opts, defaultRadius)
	opts = opts or {}
	local color = opts.color or Color.Blue
	local base = opts.zIndex or Z.Shell

	inst.Name = opts.name or inst.Name
	inst.Size = opts.size or UDim2.new(0, 180, 0, 56)
	inst.ZIndex = base
	if opts.anchorPoint then
		inst.AnchorPoint = opts.anchorPoint
	end
	if opts.position then
		inst.Position = opts.position
	end
	if opts.layoutOrder then
		inst.LayoutOrder = opts.layoutOrder
	end
	if opts.visible ~= nil then
		inst.Visible = opts.visible
	end

	local radius = toUDim(opts.radius, defaultRadius or UDim.new(0, 16))
	applyShell(inst, color, radius, opts.thickness)
	inst.Parent = parent

	local shadow, press = nil, function() end
	if opts.shadow ~= false then
		shadow, press = addShadow(inst, radius)
	end

	if opts.gloss ~= false then
		addGloss(inst, radius)
	end

	return color, base, press
end

-- ============================================================================
-- ICONS (ROADMAP 9.9)
-- ============================================================================
--
-- FOUR CALL SITES DECIDE WHAT AN ICON IS in this whole game -- Button, Card, IconTile and Pill --
-- which is why 9.9 is one abstraction rather than a hundred and fifty edits. Every one of them
-- routes through the two helpers below.
--
-- The contract is that an icon is DRAWN IF WE HAVE ONE and rendered as its emoji if we do not, so
-- nothing can ever come out as an empty square. See the IconLibrary header for why the lookup key
-- is the emoji itself.
--
-- `Image` is a property of TextLabel too, but a TextLabel cannot show one -- so an icon slot is an
-- ImageLabel when there is art and a TextLabel when there is not, and `iconSlot` hands back
-- whichever it built. Callers only ever set position and size on it, never `.Text`.

-- Rendered a shade darker than the plate so a white icon on a pale tile still has a body. Not a
-- UIStroke: an ImageLabel's stroke traces the IMAGE BOX, not the drawing inside it, so it would
-- put a rectangle round every icon. The PNGs carry their own contour instead (see make_icons.py).
local function iconSlot(parent, emoji, zIndex, minText, maxText)
	local asset = IconLibrary.Resolve(emoji)
	if asset then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = asset
		img.ScaleType = Enum.ScaleType.Fit -- never distort: the art is square and the slot may not be
		img.ZIndex = zIndex
		img.Parent = parent

		-- ===== THE SAME-HUE PROBLEM, SOLVED ONCE INSTEAD OF PER TILE =====
		--
		-- Every icon carries its own dark contour, which is enough on a tile of a different colour
		-- and is NOT enough when the two match: the gold shard on the gold Day 7 card came out as a
		-- pale ghost, which is exactly the mistake 6.4 made with gold chips on a gold card. Tinting
		-- an icon to fit its background would mean 44 icons x every tile colour they can land on.
		--
		-- A drop shadow fixes all of it with one instance and no knowledge of either colour: the
		-- SAME image, tinted flat to the outline colour and offset down-right behind the real one.
		-- Because it is the same PNG it is exactly the icon's silhouette, so the icon reads as a
		-- solid object sitting ON the tile whatever the tile happens to be -- which is also the
		-- hard-shadow rule every other surface in this kit already follows.
		-- ...UNLESS THE PARENT IS RUNNING A LAYOUT. A UIListLayout or UIGridLayout gives every child
		-- a cell, so a shadow sibling would not sit behind the icon -- it would be handed the NEXT
		-- CELL and push everything after it along. That is the currency pills (icon then value in a
		-- horizontal list), and they sit on the dark HUD backdrop where the contour is already
		-- enough. Detected rather than passed in, so a layout added to some parent later cannot
		-- quietly break its row.
		local laidOut = parent:FindFirstChildWhichIsA("UIListLayout")
			or parent:FindFirstChildWhichIsA("UIGridLayout")
			or parent:FindFirstChildWhichIsA("UIPageLayout")
			or parent:FindFirstChildWhichIsA("UITableLayout")
		if laidOut then
			return img, true
		end

		-- A SIBLING, NOT A CHILD, and that is forced rather than chosen: this ScreenGui runs
		-- `ZIndexBehavior.Sibling`, under which a child ALWAYS draws above its parent whatever its
		-- ZIndex -- so a shadow parented to the icon would cover the icon it is shadowing. As a
		-- sibling one ZIndex lower it lands where it belongs, at the cost of having to mirror the
		-- layout the caller sets afterwards.
		local shade = Instance.new("ImageLabel")
		shade.Name = "IconShadow"
		shade.BackgroundTransparency = 1
		shade.Image = asset
		shade.ScaleType = Enum.ScaleType.Fit
		shade.ImageColor3 = Color.Outline
		shade.ImageTransparency = 0.55
		shade.ZIndex = zIndex - 1
		shade.Parent = parent

		-- Every caller sets Size/Position on the slot AFTER it is handed back, so the mirror is a
		-- subscription rather than a copy. The offset is in SCALE, so it stays proportional as the
		-- responsive pass drives a tile from 82 px down toward its 40 px floor.
		local function mirror()
			shade.Size = img.Size
			shade.SizeConstraint = img.SizeConstraint
			shade.AnchorPoint = img.AnchorPoint
			shade.LayoutOrder = img.LayoutOrder
			shade.Visible = img.Visible
			shade.Image = img.Image -- SetIcon can swap the drawing; the shadow has to follow it
			shade.Position = img.Position + UDim2.new(0.05, 0, 0.055, 0)
		end
		for _, prop in ipairs({ "Size", "Position", "AnchorPoint", "SizeConstraint", "LayoutOrder", "Visible", "Image" }) do
			img:GetPropertyChangedSignal(prop):Connect(mirror)
		end
		mirror()

		return img, true
	end

	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.BackgroundTransparency = 1
	label.Font = DisplayFont
	label.TextColor3 = Color.White
	label.Text = emoji or ""
	label.ZIndex = zIndex
	outlineText(label)
	autoSize(label, minText or 16, maxText or 34)
	label.Parent = parent
	return label, false
end

-- PUBLIC, because the four kit surfaces are not the only places an icon appears. Panel CONTENT --
-- the 17 shop cards, the 9 pass rows, the potion bottles, the boost chips -- is built directly out
-- of Instance.new in MainUI rather than through Button/Card/IconTile/Pill, so those sites need the
-- same either-kind slot without being rewritten into kit components.
--
-- It lives here rather than in MainUI on purpose: MainUI is at Luau's 200-local register cap (see
-- its own header), and a helper declared there would cost one of the last registers. Declared here
-- it costs none -- MainUI already holds a reference to this module.
function UITheme.IconSlot(parent, opts)
	opts = opts or {}
	local slot = iconSlot(parent, opts.icon or "", opts.zIndex or Z.Content,
		opts.minTextSize or 16, opts.maxTextSize or 34)
	if opts.size then
		slot.Size = opts.size
	end
	if opts.position then
		slot.Position = opts.position
	end
	if opts.anchorPoint then
		slot.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		slot.LayoutOrder = opts.layoutOrder
	end
	if opts.name then
		slot.Name = opts.name
	end
	return slot
end

-- Turns an EXISTING left-aligned label whose text begins with a mapped emoji into an icon plus
-- text: the glyph is stripped, a drawing is placed at the label's left edge, and the label is
-- inset to clear it. Returns true when it did something.
--
-- This shape exists for the panel HEADERS, which are a dozen plain TextLabels built individually
-- and positioned by hand across MainUI ("\u{1F4C5} Daily Rewards!", "\u{1F6CD}\u{FE0F} Robux
-- Shop"). Rewriting each into a kit component would move every panel's title by a few pixels and
-- risk the layout of twelve screens; adjusting one that is already correct costs one line and
-- moves nothing but the glyph.
--
-- LEFT-ALIGNED ONLY, and it refuses rather than guessing otherwise: a centred title has no fixed
-- left edge to hang an icon off -- the text starts wherever its own width puts it -- so an icon
-- placed at the frame's left would float away from the words it belongs to.
function UITheme.IconifyLabel(label, gap)
	if not label or not label:IsA("TextLabel") then
		return false
	end
	if label.TextXAlignment ~= Enum.TextXAlignment.Left then
		return false
	end
	local asset = IconLibrary.Resolve(label.Text)
	if not asset then
		return false
	end
	local stripped = IconLibrary.StripLeading(label.Text)
	if stripped == label.Text then
		return false
	end

	gap = gap or 6
	-- CAPTURED BEFORE ANYTHING MOVES, and this is the whole trick. The icon goes where the label
	-- USED to start; the label then steps right to clear it. A resize handler that re-read
	-- `label.Position` would read the position after that step and walk the icon onto the words --
	-- which is exactly what the first version did, and what a screen capture caught: the panel
	-- title rendered as "[icon]ily Rewards!" with the "Da" underneath the drawing.
	local basePos = label.Position
	local baseSize = label.Size

	local img = iconSlot(label.Parent, label.Text, label.ZIndex)
	img.Name = "TitleIcon"
	img.AnchorPoint = label.AnchorPoint

	local function fit()
		-- square, off the label's rendered height -- a title box is 28..44 px depending on the panel
		local d = label.AbsoluteSize.Y
		if d < 4 then return end
		img.Size = UDim2.new(0, d, 0, d)
		img.Position = basePos
		-- The label keeps its own anchor and simply starts further along. Offset only -- a scale
		-- term here would make the inset depend on the parent's width, which an icon's width is not.
		label.Position = basePos + UDim2.new(0, d + gap, 0, 0)
		label.Size = baseSize - UDim2.new(0, d + gap, 0, 0)
	end
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	label.Text = stripped
	fit()
	return true
end

-- Re-exported so a call site that has to branch on "is there art for this" does not have to
-- require IconLibrary itself. That matters for exactly one caller and it is the important one:
-- MainUI is at the 200-local register cap, and a second `local X = require(...)` there costs a
-- register this phase has promised not to spend.
function UITheme.HasIcon(emoji)
	return IconLibrary.Has(emoji)
end

-- ============================================================================
-- PUBLIC: NotifyRank - how much a toast is worth keeping (11.15)
-- ============================================================================
--
-- The toast stack holds four. Everything past that is destroyed, and until now the victim was
-- simply the OLDEST -- which during a fight means the newest four are all `crit` and `diamond`,
-- because those fire several times a second while a NEW ZONE UNLOCKED fires once in an hour. The
-- one message a player cannot afford to miss was reliably the one thrown away.
--
-- Ranked by WHAT IS LOST IF IT SCROLLS PAST, not by how exciting the event is:
--
--   3  An answer to something the player just pressed. A refusal is the only message whose absence
--      is itself a bug report -- "I clicked and nothing happened" is what an evicted error looks
--      like from the outside. Never dropped.
--   2  One-off progress, and anything that was paid for. A zone unlock, an evolve, a rebirth, a
--      Robux purchase, a daily claim: none of these will be said again.
--   1  The default, and what an unlisted kind gets. Repeatable but deliberate -- an upgrade
--      bought, a potion drunk.
--   0  Combat chatter. `crit` and `diamond` are the two kinds that fire on a timer rather than on
--      a decision, and they are the reason this table exists at all.
--
-- Keyed by notify `kind`, the same key `SoundLibrary.NOTIFY_SOUND` uses, so a new kind is a row in
-- two tables rather than an edit inside MainUI's twenty-branch handler. It lives here rather than
-- there for the register reason every shared table in this file cites.
local NOTIFY_RANK = {
	error = 3,
	zone = 2,          evolve = 2,          character = 2,       rebirth = 2,
	bossDefeated = 2,  robuxPurchase = 2,   dailyReward = 2,     playtimeGift = 2,
	offline = 2,       reward = 2,          questComplete = 2,   stageMastery = 2,
	fuse = 2,          spin = 2,            bossRevive = 2,
	upgrade = 1,       diamondUpgrade = 1,  potion = 1,
	crit = 0,          diamond = 0,
}

function UITheme.NotifyRank(kind)
	return NOTIFY_RANK[kind] or 1
end

-- ============================================================================
-- PUBLIC: FormatNumber -- 1.23M, and the carry that is easy to get wrong
-- ============================================================================
-- ⚠️ MainUI HAS AN IDENTICAL LOCAL COPY OF THIS (`formatNumber`, near the top of that file) AND
-- CANNOT DELEGATE TO IT. That copy is written ABOVE MainUI's `require` of this module, and Lua
-- binds an upvalue where a function is WRITTEN -- so a body calling `UITheme.FormatNumber` there
-- would resolve `UITheme` as a nil global and error on the first number the HUD prints. It is the
-- same trap the comment beside MainUI's `corner` describes. **Change one, change the other**:
-- moving MainUI's declaration below its require is the fix and is a row of its own, not a
-- side-effect of whatever is being built today.
--
-- The threshold is 999.995 rather than 999.95 because this prints TWO decimals: 999,999 divides
-- once to 999.999, which is under the loop's own test and so is accepted, and "%.2f" then renders
-- it "1000.00K" -- a number one short of a million printed as a thousand thousand. The constant
-- has to match the precision beside it.
function UITheme.FormatNumber(n)
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	local suffixes = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
	local mag = 0
	while n >= 1000 and mag < #suffixes do
		n = n / 1000
		mag += 1
	end
	if n >= 999.995 and mag < #suffixes then
		n = n / 1000
		mag += 1
	end
	return string.format("%.2f%s", n, suffixes[mag])
end

local function buildLabelChild(inst, opts, base, text, maxText)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 1, -12)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = DisplayFont
	-- ===== THE INK COMES OFF THE SURFACE, NOT OFF A HABIT (17.18) =====
	--
	-- `BaseColor` rather than `opts.color`, and that is the whole reason this can be done here at
	-- all: `buildSurface` has already run `applyShell`, which stamps the fill it actually painted
	-- onto the host as an attribute (see invariant 3 -- `inst.BackgroundColor3` is Roblox's default
	-- grey on a shell and reading it here would have inked every button as if it were mid-grey).
	-- `opts.textColor` still wins, for the caller who means a specific colour.
	--
	-- BOTH HALVES IN ONE BRANCH. A dark ink chosen here and haloed two lines down in `Color.Outline`
	-- is the blob that reads correct in every property and only fails in a capture, so the halo is
	-- decided from the same value in the same statement, never inferred later.
	local ink = opts.textColor or inkOn(inst:GetAttribute("BaseColor") or opts.color)
	label.TextColor3 = ink
	label.Text = text
	label.TextWrapped = opts.wrapped == true
	label.ZIndex = base + Z.Content -- strictly above the gloss
	outlineText(label, isDarkInk(ink) and 0 or nil)
	autoSize(label, opts.minTextSize or 14, opts.maxTextSize or opts.textSize or maxText or 26)
	label.Parent = inst
	return label
end

-- ============================================================================
-- ONE UISCALE PER SURFACE, AND THE FOUR PLACES THAT HAD THEIR OWN COPY OF THAT RULE
-- ============================================================================
-- `pressMotion`, `Pulse`, `Attention` and `PanelMotion` all want "the UIScale on this thing", and
-- three of them had written the same eight lines. That is not a tidiness complaint: a second UIScale
-- added under an existing one is the documented cause of a surface settling at a random size, since
-- Roblox honours ONE UIScale per GuiObject and which one it honours is not a promise. Named `Scale`
-- because that is the name `pressMotion` shipped with and the name `Pulse` looks for; found by class
-- as a fallback because `registerPanel` in MainUI creates an unnamed one.
local function scaleOf(inst)
	local scale = inst:FindFirstChild("Scale")
	if not (scale and scale:IsA("UIScale")) then
		scale = inst:FindFirstChildOfClass("UIScale")
	end
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "Scale"
		scale.Scale = 1
		scale.Parent = inst
	end
	return scale
end

-- ============================================================================
-- PUBLIC: Attention - the idle "there is something here" pulse (18.1, research §2.5)
-- ============================================================================
--
-- ===== NO RunService LOOP, AND THAT IS THE WHOLE MECHANISM =====
--
-- `TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)` already is an idle
-- pulser: `repeatCount = -1` "repeats indefinitely", `reverses = true` returns it to the start
-- value, and `delayTime` is the gap between beats. One tween, zero per-frame Lua, and the engine
-- stops it when the instance dies. The common mistake §2.5 names is writing a Heartbeat for this.
--
-- ===== THE CADENCE, AND WHY IT DOES NOT BECOME WALLPAPER =====
--
-- The failure mode of an attention-getter is that it stops being one. Three numbers, and each is
-- picked against something rather than chosen for feel:
--
--   PEAK 1.05.  Below §2.5's 1.06 ceiling, and deliberately below the 1.08 the currency readout
--               pulses at for a REAL event (§1.5 / NumberSpinnerV2's shipped `BounceScale`). An idle
--               nudge must never out-shout something that actually happened; if the two ever read as
--               the same size, the player learns to ignore both.
--   BEAT 0.35 s per half-swing, so 0.70 s of movement per cycle -- §2.5's figure.
--   GAP  3.2 s. §2.5 gives 2.5-4 s and this sits in the middle of it, which makes the duty cycle
--               0.70 / 3.90 = 18%: the tile is STILL for 82% of the time a player is looking at it.
--               That is the number that decides wallpaper-or-not, not the peak. Under ~2.5 s the gap
--               closes up and it reads as a looping animation (a thing the UI does) rather than a
--               nudge (a thing the UI is telling you); over ~4 s the player has looked elsewhere and
--               will never see one.
--
-- ===== AT MOST ONE, ENFORCED HERE RATHER THAN ASKED OF CALLERS =====
--
-- §2.5's last rule is "at most one pulsing tile on screen at a time", and a rule like that survives
-- exactly as long as nobody adds a thirteenth tile. So the kit holds ONE slot: starting a pulse
-- stops whatever was pulsing. `priority` is the tie-break -- a Daily Rewards tile with an unclaimed
-- day (priority 2) is not displaced by a shop tile with a sale on (priority 0), because the last
-- caller to run is an accident of build order rather than a statement about importance.
--
-- ===== IT SHARES `Scale` WITH THE PRESS, AND THAT IS A REAL COLLISION =====
--
-- Every HUD tile is a `pressMotion` surface, so hovering a pulsing tile would put the hover tween
-- and an infinite reversing tween on the SAME UIScale in the same frame -- two tweens writing one
-- property, which is the bug this codebase has already paid for elsewhere. A second UIScale is not
-- an escape (Roblox honours one). So the press SUSPENDS the pulse instead: `pressMotion` calls the
-- two hooks below, the pulse is cancelled and the scale handed back at 1.0, and it restarts when the
-- pointer leaves. The suspend is the reason this block sits above `pressMotion` in the file.
local ATTENTION_PEAK = 1.05
local ATTENTION_BEAT = 0.35
local ATTENTION_GAP = 3.2

local activeAttention = nil -- { inst, scale, tween, peak, beat, gap, priority, suspended }

local function attentionPlay(entry)
	if entry.tween then
		entry.tween:Cancel()
		entry.tween = nil
	end
	entry.scale.Scale = 1
	entry.tween = UITheme.Tween(entry.scale, TweenInfo.new(
		entry.beat, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true, entry.gap
	), { Scale = entry.peak })
end

-- Cancelling an infinite REVERSING tween lands it wherever the swing happened to be, so the rest
-- value has to be written back by hand. Without this line a tile stopped mid-beat keeps 2% of a
-- pulse forever and nothing on screen says why it is the wrong size.
local function attentionStop()
	local entry = activeAttention
	if not entry then
		return
	end
	activeAttention = nil
	if entry.tween then
		entry.tween:Cancel()
	end
	if entry.scale and entry.scale.Parent then
		entry.scale.Scale = 1
	end
end

local function attentionSuspend(inst)
	local entry = activeAttention
	if entry and entry.inst == inst and not entry.suspended then
		entry.suspended = true
		if entry.tween then
			entry.tween:Cancel()
			entry.tween = nil
		end
		entry.scale.Scale = 1
	end
end

local function attentionResume(inst)
	local entry = activeAttention
	if entry and entry.inst == inst and entry.suspended then
		entry.suspended = false
		attentionPlay(entry)
	end
end

-- `UITheme.Attention(tile, true, { priority = 2 })` to start, `UITheme.Attention(tile, false)` to
-- stop, `UITheme.Attention(nil, false)` to stop whatever is pulsing. Returns true when the tile is
-- the one now pulsing.
--
-- TURNING IT OFF IS THE HALF THAT MATTERS. §2.5: "kill the tween the moment the state clears, don't
-- just hide the badge" -- a tile still asking to be pressed after you pressed it is worse than one
-- that never asked. So the off path is a single call with the same name, it is safe to call on a
-- tile that was never pulsing, and it is safe to call every refresh.
function UITheme.Attention(inst, on, opts)
	opts = opts or {}
	if not on then
		if inst == nil or (activeAttention and activeAttention.inst == inst) then
			attentionStop()
		end
		return false
	end
	if not inst or not inst:IsA("GuiObject") or not RunService:IsClient() then
		return false
	end
	-- An attention-getter is motion and nothing else: there is no static end state that carries the
	-- meaning, so under ReducedMotionEnabled it simply does not run. See the rule in the
	-- accessibility block -- this is one of the two functions that asks rather than plays.
	if reducedMotion then
		return false
	end

	local priority = opts.priority or 0
	if activeAttention then
		if activeAttention.inst == inst then
			activeAttention.priority = priority
			return true
		end
		-- a quieter request never takes the slot off a louder one that is still valid
		if priority < activeAttention.priority then
			return false
		end
		attentionStop()
	end

	local entry = {
		inst = inst,
		scale = scaleOf(inst),
		peak = opts.peak or ATTENTION_PEAK,
		beat = opts.beat or ATTENTION_BEAT,
		gap = opts.gap or ATTENTION_GAP,
		priority = priority,
		suspended = false,
	}
	activeAttention = entry
	-- the slot must not survive the tile: a destroyed host leaves `activeAttention` pointing at a
	-- dead instance, and the next real request would be refused by a pulse nobody can see
	inst.Destroying:Connect(function()
		if activeAttention == entry then
			activeAttention = nil
		end
	end)
	attentionPlay(entry)
	return true
end

-- ============================================================================
-- PUBLIC: PressMotion - the press, taken out of the two constructors that had it
-- ============================================================================
--
-- IT WAS NOT MISSING, IT WAS UNREACHABLE. `Button` and `IconTile` each carried their own copy of
-- the same forty lines -- a UIScale, a `pressed`/`hovered` pair, four closures and four
-- connections -- differing only in three numbers (2 vs 3 px of travel, 0.94 vs 0.92 squash, 1.04 vs
-- 1.06 hover). Anything built any other way (a Pill, a Card promoted to a button, a hand-rolled
-- TextButton in a panel) had no way to ask for it short of copying the block a third time. This is
-- that block, once, with the three numbers as options.
--
-- THE HOUSE MOTION, from this repo's own `readme.md` -> "Visual foundations" and
-- `tokens/effects.css` (`--transition-fast: .12s ease-out`): the surface translates DOWN a couple
-- of pixels and the hard shadow COMPRESSES by the same amount, over ~120 ms, with no bounce on the
-- way down. Both halves matter -- a body that moves down while its shadow moves with it is a button
-- sliding across the screen; a body that moves down onto a shadow that stayed put is a button being
-- pushed into the page.
--
-- The shadow here is the `ShadowBody` lip `applyShell` builds, and it is a CHILD of the surface --
-- so it travels with the press for free, which is the wrong thing. Compressing it means moving it
-- UP inside the parent by exactly what the parent moved down, which leaves it on the same screen
-- pixel while the gap between the body's bottom edge and it closes. Clamped at 0: past that the lip
-- would climb out of the top of the shell. A capsule has no lip at all (`applyShell` sets
-- `lipDepth = 0` on a round shell -- see the note there about the black crescents) so this is a
-- no-op there rather than a special case.
--
-- HOVER IS A PRESS PREVIEW, NOT AN EFFECT. This is a touch/console-first game, so the hover state
-- exists mostly for the Studio session it is being tuned in; the default is 1.03. `Button` and
-- `IconTile` pass the 1.04 and 1.06 they shipped with rather than being quietly restyled by this
-- refactor -- moving twelve HUD tiles is a decision, not a side effect of moving some code.
--
-- IT CANNOT FIGHT THE PANEL-OPEN ANIMATION, for two reasons and both are needed: it only ever
-- drives a UIScale named `Scale` that it REUSES if one is already there (so it can never add a
-- second multiplier under an existing one), and panel-open animates `ModalScale` on the panel,
-- which is an ancestor of any button rather than the same instance.
--
-- NOTHING LEAKS. Every connection is to an event ON `inst` itself and every upvalue is `inst` or one
-- of its children, so destroying the surface releases all of them; there is no external signal, no
-- Heartbeat and no registry to unsubscribe from.
local function pressMotion(inst, opts)
	opts = opts or {}
	local drop = opts.drop or 2
	local pressScale = opts.pressScale or 0.94
	local hoverScale = opts.hoverScale or 1.03

	local scale = scaleOf(inst)

	-- TWO LIPS ON A TILE, AND THE ONE YOU FIND FIRST IS THE ONE YOU CANNOT SEE. An IconTile is two
	-- `applyShell` surfaces of the same colour stacked exactly on top of each other (the outer one is
	-- the TextButton, the inner `Body` is the face -- see IconTile), so it has two `ShadowBody`
	-- children at the same 6 px offset and the INNER one draws over the outer. Compressing only the
	-- one that `FindFirstChild` hands back would be a press with no visible shadow response at all.
	-- The same pair `UITheme.SetColor` has to repaint together, for the same reason.
	local lips = {}
	local function collectLip(host)
		if not host then
			return
		end
		local lip = host:FindFirstChild("ShadowBody")
		if lip and lip:IsA("GuiObject") then
			table.insert(lips, { lip = lip, rest = lip.Position })
		end
	end
	collectLip(inst)
	collectLip(inst:FindFirstChild("Body"))

	local pressed = false
	local hovered = false
	local restPos = inst.Position

	local function down()
		if pressed then
			return
		end
		pressed = true
		-- the idle pulse and the press drive the SAME UIScale, so one has to give way -- see the
		-- collision note in the Attention block. The press wins: it is a thing the player did.
		attentionSuspend(inst)
		-- re-read rather than trusting the value captured at build time: a responsive pass or a
		-- layout can have moved the surface since, and restoring to a stale position on release is
		-- how a pressed button walks up the screen.
		restPos = inst.Position
		inst.Position = restPos + UDim2.new(0, 0, 0, drop)
		for _, entry in ipairs(lips) do
			local rest = entry.rest
			entry.lip.Position = UDim2.new(
				rest.X.Scale, rest.X.Offset,
				rest.Y.Scale, math.max(rest.Y.Offset - drop, 0)
			)
		end
		if RunService:IsClient() then
			UITheme.Tween(scale, PRESS_DOWN_INFO, { Scale = pressScale })
		end
		-- on DOWN, with the sink, not on the click release: the sound is feedback for the press and
		-- has to land on the same frame the button visibly moves
		if opts.sound ~= false then
			clickSound()
		end
	end

	local function up()
		if not pressed then
			return
		end
		pressed = false
		inst.Position = restPos
		for _, entry in ipairs(lips) do
			entry.lip.Position = entry.rest
		end
		if RunService:IsClient() then
			TweenService:Create(scale, PRESS_UP_INFO, { Scale = hovered and hoverScale or 1.0 }):Play()
		end
	end

	local function enter()
		hovered = true
		if not pressed and RunService:IsClient() and inst.Active and inst.Selectable ~= false then
			TweenService:Create(scale, HOVER_TWEEN_INFO, { Scale = hoverScale }):Play()
		end
	end

	local function leave()
		hovered = false
		-- THE TORN STATE, and the only place it can be repaired. A pointer that leaves mid-press
		-- never sends the Up, so without this the surface keeps the 2 px offset and the squashed
		-- scale forever -- a button that looks held down by nobody.
		if pressed then
			up()
		end
		if RunService:IsClient() then
			TweenService:Create(scale, LEAVE_TWEEN_INFO, { Scale = 1.0 }):Play()
		end
	end

	if opts.connect ~= false then
		if inst:IsA("GuiButton") then
			inst.MouseButton1Down:Connect(down)
			inst.MouseButton1Up:Connect(up)
		end
		inst.MouseEnter:Connect(enter)
		inst.MouseLeave:Connect(leave)
		-- A FINGER LIFTED OFF THE EDGE SENDS NEITHER Up NOR MouseLeave on some devices, which is the
		-- other half of the torn state and the half a mouse never shows you.
		inst.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				up()
			end
		end)
	end

	return down, up
end
UITheme.PressMotion = pressMotion

-- ============================================================================
-- PUBLIC: Button
-- ============================================================================
function UITheme.Button(parent, opts)
	opts = opts or {}
	local button = Instance.new("TextButton")
	button.Name = opts.name or "Button"
	button.AutoButtonColor = false
	button.Text = "" -- visible text lives in the child Label (own stroke, above gloss)
	button.TextTransparency = 1

	local _, base = buildSurface(button, parent, opts, UDim.new(0, 16))

	-- ===== THE SAME SIX PIXELS MainUI's `styleButton` TAKES OFF (11.3) =====
	--
	-- Two builders make every button in this game and a shrink applied to only one of them is a
	-- HUD where half the buttons are 44 tall and half are 50 -- which is worse than leaving both
	-- alone. The rule is identical and deliberately narrow: the two authored action-button heights
	-- (50 primary, 46 secondary) become 44 and 40, and nothing else is touched, because everything
	-- else built through here -- a 42 close button, a 68 HUD tile, a 60+ Robux card -- is sized
	-- against its own grid rather than against "an action button".
	--
	-- AFTER buildSurface, not inside it: Card, IconTile and Modal all go through that function and
	-- none of them is an action button. Doing it there would resize the tile columns.
	if button.Size.Y.Scale == 0 then
		local h = button.Size.Y.Offset
		if h == 50 or h == 46 then
			button.Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset, 0, h == 50 and 44 or 40)
		end
	end

	local text = opts.text or ""
	-- ICON AND TEXT ARE STILL ONE LABEL WHEN THERE IS NO ART FOR THE ICON, and that is deliberate:
	-- a button's text is centred, so splitting the row unconditionally would move every existing
	-- caption a few pixels right for the ~90 emojis this game will never draw. When there IS art,
	-- the glyph comes out of the string and a square ImageLabel takes the left end of the button.
	local iconAsset = (opts.icon and opts.icon ~= "") and IconLibrary.Resolve(opts.icon) or nil
	if opts.icon and opts.icon ~= "" and not iconAsset then
		text = opts.icon .. " " .. text
	end
	-- MOST BUTTONS IN THIS GAME PUT THE EMOJI IN THE TEXT, not in `icon` -- "\u{1F3A1} FREE SPIN",
	-- "\u{2694}\u{FE0F} REVIVE". Those are the same thing written a different way, so a LEADING
	-- mapped glyph is promoted to the icon slot and stripped from the string. Only leading: a
	-- trailing glyph is part of a sentence ("SPIN 25\u{1F31F}" is a price) and has no slot to go to.
	if not iconAsset then
		iconAsset = IconLibrary.Resolve(text)
		if iconAsset then
			text = IconLibrary.StripLeading(text)
		end
	end
	local label = buildLabelChild(button, opts, base, text, 26)

	if iconAsset then
		local img = iconSlot(button, opts.icon or opts.text, base + Z.Content)
		-- Sized off the button's own height, so one rule covers a 42px shop row and a 68px HUD
		-- button. 0.62 leaves the icon visually the same weight as the cap height beside it.
		--
		-- BOTH SCALES ARE 0.62, and that is what RelativeYY means: it makes the X scale relative to
		-- the parent's HEIGHT as well, which is the whole point (a square, whatever the aspect of
		-- the button). Writing the X term as 0 -- the obvious way to say "take the height and let
		-- the constraint work it out" -- gives a slot 0 pixels wide, and an ImageLabel that is
		-- loaded, positioned, correct in every structural probe, and invisible on screen.
		img.Size = UDim2.new(0.62, 0, 0.62, 0)
		img.SizeConstraint = Enum.SizeConstraint.RelativeYY
		img.Position = UDim2.new(0, 10, 0.5, 0)
		img.AnchorPoint = Vector2.new(0, 0.5)
		-- and the text gives up exactly the room the icon took, on BOTH sides -- a label inset only
		-- on the left is still centred on the whole button, so its text would sit under the icon
		label.Size = UDim2.new(1, -16 - 2 * (label.AbsoluteSize.Y * 0.62 + 10), 1, -12)
		-- AbsoluteSize is 0 for a frame that has not been laid out yet, which is every frame on the
		-- first pass. Bind the real measurement to the button's own resize instead of guessing.
		local function fit()
			local d = button.AbsoluteSize.Y * 0.62 + 10
			-- ...AND THE RESERVATION IS CAPPED, BECAUSE IT IS COMPUTED FROM THE HEIGHT (15.17).
			--
			-- `d` is the icon's own width plus its margin, taken off BOTH sides so the text stays
			-- centred on the button rather than centred under the icon. On a wide button that is
			-- free. On a SHORT, TALL one it is most of the button: the Group & Community cards
			-- carry a 115 x 42 action button, where d is 36 and the label was left **27px** -- too
			-- narrow for any word in the language, so "Claim" rendered as "Clai" over "m" and
			-- "Claim Chest" lost its second line entirely. Every property read correct
			-- (`TextFits` was **true**, because two 14px lines do fit a 30px box); only the capture
			-- showed it.
			--
			-- The floor is 55% of the button. Below that the inset gives way instead of the words:
			-- the text may then sit a little closer to the icon than the symmetric rule wanted,
			-- which is a cosmetic loss where the alternative is an unreadable button.
			local w = button.AbsoluteSize.X
			local floor = w * 0.55
			if w - 16 - 2 * d < floor then
				d = math.max(0, (w - 16 - floor) / 2)
			end
			label.Size = UDim2.new(1, -16 - 2 * d, 1, -12)
		end
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end

	-- press and hover feedback -- the shared motion, with the two numbers this surface shipped with
	pressMotion(button, { drop = 2, pressScale = 0.94, hoverScale = 1.04 })

	if opts.badge then
		UITheme.Badge(button, opts.badge, opts.badgeColor)
	end

	return button
end

-- ============================================================================
-- PUBLIC: Card (Button without the interaction)
-- ============================================================================
function UITheme.Card(parent, opts)
	opts = opts or {}
	local card = Instance.new("Frame")
	card.Name = opts.name or "Card"

	local color, base = buildSurface(card, parent, opts, UDim.new(0, 16))

	if opts.text and opts.text ~= "" then
		local text = opts.text
		-- same split as Button, and the same reason it is conditional -- see the note there
		local iconAsset = (opts.icon and opts.icon ~= "") and IconLibrary.Resolve(opts.icon) or nil
		if opts.icon and opts.icon ~= "" and not iconAsset then
			text = opts.icon .. " " .. text
		end
		local label = buildLabelChild(card, opts, base, text, 26)
		if iconAsset then
			local img = iconSlot(card, opts.icon, base + Z.Content)
			-- both scales 0.62 -- see the note in Button
			img.Size = UDim2.new(0.62, 0, 0.62, 0)
			img.SizeConstraint = Enum.SizeConstraint.RelativeYY
			img.Position = UDim2.new(0, 10, 0.5, 0)
			img.AnchorPoint = Vector2.new(0, 0.5)
			local function fit()
				local d = card.AbsoluteSize.Y * 0.62 + 10
				label.Size = UDim2.new(1, -16 - 2 * d, 1, -12)
			end
			card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			fit()
		end
	end

	if opts.badge then
		UITheme.Badge(card, opts.badge, opts.badgeColor)
	end

	return card
end

-- ============================================================================
-- PUBLIC: IconTile - square tile, big icon on top, caption inside the bottom strip
-- ============================================================================
function UITheme.IconTile(parent, opts)
	opts = opts or {}
	local tile = Instance.new("TextButton")
	tile.Name = opts.name or "IconTile"
	tile.AutoButtonColor = false
	tile.Text = ""
	tile.TextTransparency = 1

	local color = opts.color or Color.Blue
	-- The big pressable squares take the roundest step in the ladder rather than a number of their
	-- own (2026-08-16). A HUD tile is the shape the eye reads the aesthetic off -- there are twelve of
	-- them down both edges of the screen -- so this is where "everything rounder" is actually visible.
	local radius = toUDim(opts.radius, UITheme.Radius.Tile)

	-- TWO EDGES, NOT THREE. A tile is the dark outline and the coloured face, and nothing between.
	--
	-- It has been wrong twice in the same place. First the rim between them was Cream, which put a
	-- white ring around every HUD button; replacing that with a darker shade of the tile's own hue
	-- fixed the colour and kept the fault -- the ring was still a third edge, just a dark one, and
	-- against the bright zones it read as a border somebody had left half-finished.
	--
	-- The outer shell still exists because it is the TextButton: it owns the click, the stroke and
	-- the shadow. It is simply the SAME colour as the body and inset by nothing, so the two are one
	-- surface. Anything that recolours a tile has to keep them in step -- see UITheme.SetColor.
	local tileOpts = {}
	for k, v in pairs(opts) do
		tileOpts[k] = v
	end
	tileOpts.size = opts.size or UDim2.new(0, 82, 0, 82)
	tileOpts.color = color
	tileOpts.radius = radius
	tileOpts.gloss = false -- the gloss belongs to the body, which is what is actually visible

	local _, base = buildSurface(tile, parent, tileOpts, UDim.new(0, 18))
	tile.ClipsDescendants = false -- the badge still hangs outside the tile

	local ringGrad = tile:FindFirstChild("Gradient")
	if ringGrad and ringGrad:IsA("UIGradient") then
		-- matched to the body's, so the corners cannot show a seam where the two roundings differ
		ringGrad.Color = pastelGradientFor(color)
	end

	local INSET = 0
	local bodyRadius = UDim.new(radius.Scale, math.max(radius.Offset - INSET, 6))
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -INSET * 2, 1, -INSET * 2)
	body.Position = UDim2.new(0, INSET, 0, INSET)
	body.ZIndex = base + 1
	applyShell(body, color, bodyRadius, 0)
	local bodyGrad = body:FindFirstChild("Gradient")
	if bodyGrad and bodyGrad:IsA("UIGradient") then
		bodyGrad.Color = pastelGradientFor(color)
	end
	body.Parent = tile
	addGloss(body, bodyRadius)

	local hasCaption = opts.caption ~= nil and opts.caption ~= ""

	-- KEPT AS "Label", whichever kind it turns out to be. Six places outside this module reach into
	-- a tile by that name (the responsive pass, refreshAutoTile, the potion strip and others), and
	-- renaming it because the class changed would break all of them silently -- a FindFirstChild
	-- that misses returns nil, and every one of those call sites is nil-guarded.
	local icon, isImage = iconSlot(body, opts.icon or opts.text or "", body.ZIndex + Z.Content,
		20, opts.maxTextSize or 38)
	icon.Name = "Label"
	if hasCaption then
		-- 0.54, down from 0.60. The icon was taking six tenths of the tile and the word underneath it
		-- was taking three, and the word is the half a player actually reads -- an emoji at 38pt is
		-- legible at any size, "Inventory" at 10pt is not. See the caption block below.
		icon.Size = UDim2.new(1, -12, 0.54, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 5)
		icon.AnchorPoint = Vector2.new(0.5, 0)
	else
		icon.Size = UDim2.new(1, -14, 1, -14)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	-- A DRAWN ICON GETS A SQUARE SLOT, and this is the one place it matters most. `ScaleType.Fit`
	-- keeps the art's aspect inside whatever box it is given, so a 1.0-wide by 0.54-high slot draws
	-- the icon at 54% of the tile height and leaves the rest as empty margin -- correct, but small.
	-- Constraining the WIDTH to the height instead gives the drawing the whole band it was allotted.
	-- A TextLabel needs the opposite (its glyph is already centred in a wide box), so this only
	-- applies to the image case.
	if isImage and hasCaption then
		-- both scales 0.60 -- see the note in Button about what RelativeYY does to the X term
		icon.Size = UDim2.new(0.60, 0, 0.60, 0)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	end

	if hasCaption then
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		-- THE THREE NUMBERS THAT MADE THE HUD CAPTIONS UNREADABLE, and why each one moved.
		--
		-- TextScaled picks the largest size that fits BOTH the band's height and its width, then the
		-- UITextSizeConstraint clamps the result. The old band was 0.30 of the tile with 8px of
		-- horizontal padding, and the clamp floor was 10 -- so a long word like "Inventory" or
		-- "Auto OFF" bound on WIDTH and dropped all the way to that floor while the icon above it sat
		-- at 38. On a short viewport the tile itself shrinks toward 40px, the band with it, and every
		-- caption in the HUD pinned at 10pt.
		--
		--   0.30 -> 0.34   a taller band, paid for out of the icon's 0.60 -> 0.54 above
		--   -8   -> -4     4px of padding instead of 8, which is 8px of extra width for the word
		--                  that is binding on width in the first place
		--   10   -> 13     the floor. Worth checking against the smallest tile the responsive pass
		--                  will build: at its 40px minimum the band is 0.34 * 40 = 13.6px, so 13 is
		--                  the largest floor that still fits inside its own band there.
		caption.Size = UDim2.new(1, -4, 0.34, 0)
		caption.Position = UDim2.new(0.5, 0, 1, -4)
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Font = DisplayFont
		-- Off the tile's own fill. Every HUD tile today is a chromatic pastel (Mint 0.66 up to Sunny
		-- 0.82, all below the 0.86 cut) so this returns White for all twelve of them and the strip is
		-- unchanged -- it exists for the Frost/white tile the pastel pass makes possible, where the
		-- caption is the SMALLEST text in the kit (13 pt floor) and therefore the first thing a
		-- white-on-near-white read destroys.
		local capInk = inkOn(color)
		caption.TextColor3 = capInk
		caption.Text = opts.caption
		caption.ZIndex = body.ZIndex + Z.Content
		-- 3.5, up from 2.5. These sit on saturated pastel tiles and the caption is the one label in
		-- the kit small enough for a thin outline to stop separating it from what is behind it.
		-- ...and 0 when the ink went dark, in this same statement -- see `inkOn`.
		outlineText(caption, isDarkInk(capInk) and 0 or 3.5)
		autoSize(caption, 13, 22)
		caption.Parent = body
	end

	if opts.badge then
		UITheme.Badge(tile, opts.badge, opts.badgeColor)
	end

	-- 3 px and 0.92/1.06 rather than the Button's 2 and 0.94/1.04: a tile is twice the area, and the
	-- same travel on a bigger surface reads as less movement. These are the numbers it shipped with.
	pressMotion(tile, { drop = 3, pressScale = 0.92, hoverScale = 1.06 })

	return tile
end

-- ============================================================================
-- PUBLIC: Label
-- ============================================================================
function UITheme.Label(parent, opts)
	opts = opts or {}
	local label = Instance.new("TextLabel")
	label.Name = opts.name or "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = opts.size or UDim2.new(1, 0, 0, 28)
	label.Font = DisplayFont
	-- ===== `on`: THE SURFACE THIS LABEL IS PRINTED ON (17.18) =====
	--
	-- A bare TextLabel is the one constructor here that genuinely cannot look its own fill up -- it is
	-- parented onto somebody else's frame and `opts.color` is the only thing it has ever been told.
	-- The default therefore stays White, so none of the 23 existing call sites moves.
	--
	-- `on` is how a caller hands it the missing fact instead of hand-computing the ink, which is the
	-- pattern that has already put a dark word inside a dark halo twice (15.1 in MainUI's themeLabel,
	-- 15.15 in this constructor). Note the precedence: an EXPLICIT `color` still wins over `on` --
	-- `on` answers "what should this be", not "what must this be".
	label.TextColor3 = opts.color or (opts.on and inkOn(opts.on)) or Color.White
	label.Text = opts.text or ""
	label.ZIndex = opts.zIndex or Z.Content
	if opts.position then
		label.Position = opts.position
	end
	if opts.anchorPoint then
		label.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		label.LayoutOrder = opts.layoutOrder
	end
	if opts.visible ~= nil then
		label.Visible = opts.visible
	end

	if opts.xAlign == "Left" then
		label.TextXAlignment = Enum.TextXAlignment.Left
	elseif opts.xAlign == "Right" then
		label.TextXAlignment = Enum.TextXAlignment.Right
	elseif typeof(opts.xAlign) == "EnumItem" then
		label.TextXAlignment = opts.xAlign
	else
		label.TextXAlignment = Enum.TextXAlignment.Center
	end

	-- The colour is set above, so the decision can be made here rather than guessed at. A caller
	-- that asked for a thickness on dark ink still loses it: `strokeThickness` says how thick the
	-- halo should be, never that a blob is wanted.
	outlineText(label, isDarkInk(label.TextColor3) and 0 or opts.strokeThickness)
	autoSize(label, opts.minTextSize or 14, opts.maxTextSize or opts.textSize or 30)
	-- AFTER `autoSize`, because that is the only position where it survives -- see the note over it.
	-- Only an EXPLICIT `wrapped = false` is honoured: `TextScaled` has been turning wrapping on for
	-- all 23 call sites since this constructor was written, three of which ask for it by name and
	-- none of which asks for it off, so defaulting to "off" here would silently unwrap twenty
	-- labels that are laid out around wrapping today. The option is now real without being a change.
	if opts.wrapped ~= nil then
		label.TextWrapped = opts.wrapped == true
	end
	label.Parent = parent
	return label
end

-- ============================================================================
-- PUBLIC: Pill - currency readout, with or without a capsule behind it
-- ============================================================================
--
-- ===== `shellColor` (17.13), AND WHY IT COULD NOT SIMPLY BE `applyShell(frame, ...)` =====
--
-- This constructor draws the three most-looked-at numbers in the game -- DNA, Diamonds and
-- Evolution Shards, bottom-left, on screen at all times -- and until now it drew NO BODY AT ALL: a
-- transparent frame, an icon and an outlined number floating directly on the 3D world, in a HUD
-- where every other element is a chunky outlined capsule. Photographed live 2026-08-16; it is the
-- largest single visual defect on the screen.
--
-- `shellColor` is opt-in and nothing else about the pill changes when it is nil -- same instance,
-- same children, same names, same transparency -- because a Pill is still the right shape for a
-- readout that sits ON something already (a panel row, a card) and would only gain a second
-- outline from a capsule.
--
-- THE CAPSULE IS A PARENT, NOT THE FRAME ITSELF, and that is forced by the UIListLayout this pill
-- has always been built out of. `applyShell` works by adding two full-size children -- `ShadowBody`
-- and `InnerBody` -- to whatever it is handed. A UIListLayout gives EVERY GuiObject child a cell,
-- so shelling the frame directly would hand the lip and the body two full-width cells at the head
-- of a horizontal row and shove the icon and the number off the end of it. That is the exact trap
-- `iconSlot` documents for its own drop shadow one screen up, and the reason it declines to draw
-- one inside a laid-out parent.
--
-- So the capsule is a shelled frame that OWNS the layout frame: it takes the size, position and
-- layout order the caller asked for, and the returned pill becomes a transparent full-size child of
-- it at `Z.Content`. Everything a caller reaches for is untouched by that -- `pill.Value.Text`,
-- `pill.Icon`, `pill:SetAttribute("PrevVal", ...)`, `UITheme.Pulse(pill)` and
-- `plusButton.Parent = pill` all still mean what they meant, because they are all about the
-- returned frame and the returned frame still has exactly the children it had.
--
-- Z: the content frame sits at `base + Z.Content`, above `InnerBody` at `base + Z.Body`. Getting
-- that backwards is what shipped two blank Inventory tabs -- `InnerBody` is opaque and paints over
-- anything at or below its own level.
function UITheme.Pill(parent, opts)
	opts = opts or {}
	local shellColor = opts.shellColor
	local base = opts.zIndex or Z.Content

	local shell
	if shellColor then
		shell = Instance.new("Frame")
		-- The returned frame keeps `opts.name`, so a caller that looks its pill up by name finds the
		-- same object it always did; the capsule is named off it rather than taking it.
		shell.Name = (opts.name or "Pill") .. "Shell"
		shell.Size = opts.size or UDim2.new(0, 210, 0, 42)
		shell.ZIndex = base
		if opts.position then
			shell.Position = opts.position
		end
		if opts.anchorPoint then
			shell.AnchorPoint = opts.anchorPoint
		end
		if opts.layoutOrder then
			shell.LayoutOrder = opts.layoutOrder
		end
		if opts.visible ~= nil then
			shell.Visible = opts.visible
		end
		-- Radius.Pill is UDim.new(1, 0) -- a true capsule, ends fully rounded at half the height,
		-- which is what the shape ladder means by "anything read as a single value". It also puts
		-- `applyShell` on its round path: no 6 px lip, so none of the dark crescents that the health
		-- bar grew at both ends before that case existed.
		applyShell(shell, shellColor, UITheme.Radius.Pill, opts.thickness)
		shell.Parent = parent
		if opts.gloss ~= false then
			addGloss(shell, UITheme.Radius.Pill)
		end
	end

	local frame = Instance.new("Frame")
	frame.Name = opts.name or "Pill"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	if shell then
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.ZIndex = base + Z.Content
	else
		frame.Size = opts.size or UDim2.new(0, 210, 0, 42)
		frame.ZIndex = base
		if opts.position then
			frame.Position = opts.position
		end
		if opts.anchorPoint then
			frame.AnchorPoint = opts.anchorPoint
		end
		if opts.layoutOrder then
			frame.LayoutOrder = opts.layoutOrder
		end
		if opts.visible ~= nil then
			frame.Visible = opts.visible
		end
	end
	frame.Parent = shell or parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	if shell then
		-- A capsule's ends curve away from its bounding box, so a 40 px icon starting at x = 0 would
		-- be drawn half inside the rim. UIPadding rather than an offset on the icon: it is not a
		-- GuiObject, so it cannot pick up a layout cell of its own, and it shrinks the region every
		-- `Scale` size in the row is measured against -- which is what keeps `Value`'s `1, -46`
		-- (and the `1, -84` MainUI rewrites it to when it hangs a `+` on the end) exact.
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = frame

		-- ...and the pointer back out, so `UITheme.Pulse(pill)` jumps the capsule rather than the two
		-- children rattling around inside a capsule that never moved. See the note in `Pulse`.
		-- An ObjectValue is not a GuiObject, so the layout above cannot hand it a cell.
		local pulseHost = Instance.new("ObjectValue")
		pulseHost.Name = "PulseHost"
		pulseHost.Value = shell
		pulseHost.Parent = frame
	end

	-- The pill is a UIListLayout, so the slot only has to declare its size and order -- the layout
	-- puts the value beside it either way, and a drawn icon and an emoji occupy the same 40px box.
	local icon = iconSlot(frame, opts.icon or "", frame.ZIndex, 16, opts.maxTextSize or 34)
	icon.Size = UDim2.new(0, 40, 1, 0)
	icon.LayoutOrder = 1

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(1, -46, 1, 0)
	value.LayoutOrder = 2
	value.Font = DisplayFont
	-- ===== THE NUMBER FOLLOWS THE CAPSULE (17.18) =====
	--
	-- A pill with NO capsule is printed on the 3D world, and nothing can be inferred about that -- it
	-- stays White plus a halo, which is the only thing that survives an arbitrary backdrop. A pill
	-- WITH one is printed on a colour we chose, so the ink comes off it. That is what lets the three
	-- currency capsules become Frost without the three most-looked-at numbers in the game turning
	-- into white-on-white outlines.
	value.TextColor3 = opts.color or (shellColor and inkOn(shellColor)) or Color.White
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = opts.text or "0"
	value.ZIndex = frame.ZIndex
	-- ===== THE INK AND ITS HALO ARE ONE DECISION, AND THE SURFACE UNDER THEM JUST CHANGED =====
	--
	-- Same rule as UITheme.Label: dark ink drops its stroke, because `outlineText` always draws in
	-- `Color.Outline` and a dark glyph inside a dark halo is a blob that reads correct in every
	-- property and only fails in a capture.
	--
	-- What `shellColor` adds is the second half of it. Without a capsule the backdrop is the 3D
	-- world, so dark ink is simply unreadable and losing the halo costs nothing. WITH a capsule the
	-- ink is sitting on a known colour, and dark ink on a DARK capsule is the one case where the
	-- halo is the only thing separating the number from the surface it is printed on -- so it stays.
	-- One branch, both decisions, reading the colour the ink is actually on.
	local darkInk = isDarkInk(value.TextColor3)
	local dropHalo = darkInk and not (shellColor ~= nil and isDarkInk(shellColor))
	outlineText(value, dropHalo and 0 or nil)
	autoSize(value, 16, opts.maxTextSize or 34)
	value.Parent = frame

	return frame
end

-- ============================================================================
-- PUBLIC: Modal
-- ============================================================================
function UITheme.Modal(parent, opts)
	opts = opts or {}
	local base = opts.zIndex or 50

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.Position = UDim2.new(0, 0, 0, 0)
	dim.ZIndex = base - 1
	dim.Visible = false
	dim.Parent = parent

	local modal = Instance.new("Frame")
	modal.Name = opts.name or "Modal"
	modal.Size = opts.size or UDim2.new(0, 520, 0, 380)
	modal.Position = opts.position or UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = opts.anchorPoint or Vector2.new(0.5, 0.5)
	modal.ZIndex = base
	modal.Visible = false

	local radius = toUDim(opts.radius, UDim.new(0, 22))
	local _, modalStroke = applyShell(modal, opts.color or Color.PanelWhite, radius, 5)
	-- The cyan rim, asked for explicitly. A modal IS a panel, so this is one of the two places
	-- entitled to it -- see the note in applyShell about why it cannot be decided from the fill.
	if modalStroke and (opts.color == nil or opts.color == Color.PanelWhite) then
		modalStroke.Thickness = 6
		modalStroke.Color = Color.PanelBorder
	end
	modal.Parent = parent

	if opts.shadow ~= false then
		addShadow(modal, radius)
	end

	-- white frame around a coloured inner area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -28, 1, -28)
	content.Position = UDim2.new(0, 14, 0, 14)
	content.ZIndex = base + Z.Content
	applyShell(content, opts.accent or Color.PanelBlue, UDim.new(0, 16), 4)
	content.Parent = modal

	if opts.gloss ~= false then
		local gloss = addGloss(content, UDim.new(0, 16))
		gloss.ZIndex = content.ZIndex + Z.Gloss
	end

	local title = UITheme.Label(modal, {
		name = "Title",
		text = opts.title or "",
		size = UDim2.new(0.62, 0, 0, 44),
		position = UDim2.new(0, 22, 0, -12),
		xAlign = "Left",
		maxTextSize = 40,
		zIndex = base + Z.Badge,
	})
	title.ZIndex = base + Z.Badge

	local closeButton = UITheme.Button(modal, {
		name = "Close",
		text = "X",
		color = Color.Red,
		radius = 12,
		size = UDim2.new(0, 44, 0, 44),
		position = UDim2.new(1, -6, 0, -6),
		anchorPoint = Vector2.new(1, 0),
		zIndex = base + Z.Badge,
		maxTextSize = 30,
	})

	local modalScale = Instance.new("UIScale")
	modalScale.Name = "ModalScale"
	modalScale.Scale = 1
	modalScale.Parent = modal

	modal:GetPropertyChangedSignal("Visible"):Connect(function()
		dim.Visible = modal.Visible
		if modal.Visible and RunService:IsClient() then
			modalScale.Scale = 0.88
			TweenService:Create(modalScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
		end
	end)
	modal.Destroying:Connect(function()
		dim:Destroy()
	end)

	return modal, content, closeButton
end

-- ============================================================================
-- PUBLIC: PanelHeader - the accent bar every shop-side panel opens with (11.13)
-- ============================================================================
--
-- Every floating panel in MainUI used to open with a bare left-aligned TextLabel sitting on the
-- panel's own cream shell: no band, no rule, no subtitle, and side margins of 14, 16, 18 and 24
-- depending on which panel was written on which day. That reads as a document with a heading rather
-- than a shop with a counter, and it is most of what "the shops look plain" is describing.
--
-- One accent band, drawn with the same `applyShell` + `addGloss` every button and card in the game
-- already uses, so it inherits the chunky look wholesale -- thick outline, hard shadow, glossy top --
-- rather than restating it. That is also why this is NOT a new visual language: the reference kit
-- (`ui_kits/evolution-lab/RobuxShopModal.jsx`) is a cream card with a 3 px outline and
-- `--shadow-panel`, which is exactly what `applyShell` draws.
--
-- THE SUBTITLE IS THE POINT, not the band. A shop panel has to answer "what am I spending, and on
-- what" before the player reads a single tile, and none of the four did -- "Upgrades" over a row of
-- DNA tiles and a row of Diamond tiles says nothing about which currency buys which. The band is
-- what gives the subtitle somewhere to live.
--
-- `closeGap` reserves the top-right corner for `panelClose`'s 42 px X. The title is clipped to that
-- width rather than the header being shortened, so the band still runs the full width of the panel
-- and the X sits ON it -- shortening the band instead leaves a notch that reads as a mistake.
--
-- Returns the header AND the y offset content should start at, because the caller's next line is
-- always positioning something under it and computing that by hand is how the four panels drifted
-- apart in the first place.
function UITheme.PanelHeader(panel, opts)
	opts = opts or {}
	local base = panel.ZIndex or 20
	local margin = opts.margin or 16
	local top = opts.top or 14
	local subtitle = opts.subtitle
	local height = opts.height or (subtitle and 68 or 52)
	local closeGap = opts.closeGap or 62
	local accent = opts.accent or Color.PanelBlue

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -(margin * 2), 0, height)
	header.Position = UDim2.new(0, margin, 0, top)
	header.ZIndex = base + Z.Content
	applyShell(header, accent, UDim.new(0, 16), 4)
	header.Parent = panel

	local gloss = addGloss(header, UDim.new(0, 16))
	gloss.ZIndex = header.ZIndex + Z.Gloss

	local title = UITheme.Label(header, {
		name = "Title",
		text = opts.title or "",
		size = UDim2.new(1, -(14 + closeGap), 0, subtitle and 32 or (height - 12)),
		position = UDim2.new(0, 14, 0, subtitle and 6 or 6),
		xAlign = "Left",
		maxTextSize = opts.maxTextSize or 30,
		zIndex = header.ZIndex + Z.Content,
		-- the band's own fill, so a panel given a Frost or Cream accent gets an inked title instead
		-- of a white one dissolving into it. PanelBlue is 0.59, so every existing header is untouched.
		on = accent,
	})
	-- 9.9's pipeline, unchanged: a mapped leading emoji becomes a drawing at the label's left edge
	-- and everything else stays a glyph. Called on the header's own title so a panel converted to
	-- this component keeps the icon it already had.
	UITheme.IconifyLabel(title)

	local sub
	if subtitle then
		sub = UITheme.Label(header, {
			name = "Subtitle",
			text = subtitle,
			size = UDim2.new(1, -(14 + closeGap), 0, 22),
			position = UDim2.new(0, 14, 0, 38),
			xAlign = "Left",
			maxTextSize = 18,
			minTextSize = 12,
			-- Cream is a 0.97 ink and it was the right answer on a blue band and only on a blue band:
			-- on a light accent it is invisible AND it keeps its near-black halo, so the subtitle
			-- would render as a hollow outline. `InkSoft` is the light-surface partner -- one tier
			-- quieter than `Ink`, which is what a subtitle is for.
			color = isLightSurface(accent) and Color.InkSoft or Color.Cream,
			zIndex = header.ZIndex + Z.Content,
		})
	end

	return header, top + height + (opts.gap or 12), title, sub
end

-- ============================================================================
-- PUBLIC: ProgressBar
-- ============================================================================
function UITheme.ProgressBar(parent, opts)
	opts = opts or {}
	local base = opts.zIndex or Z.Shell
	local radius = toUDim(opts.radius, UDim.new(1, 0))

	local bar = Instance.new("Frame")
	bar.Name = opts.name or "ProgressBar"
	bar.Size = opts.size or UDim2.new(1, 0, 0, 30)
	bar.ZIndex = base
	if opts.position then
		bar.Position = opts.position
	end
	if opts.anchorPoint then
		bar.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		bar.LayoutOrder = opts.layoutOrder
	end
	if opts.visible ~= nil then
		bar.Visible = opts.visible
	end
	-- ===== THE TRACK IS AN INSET, NOT A SECOND WHITE PANEL (17.18) =====
	--
	-- It was `PanelWhite`. Every panel shell in this game is also white, so an XP or health bar at 5%
	-- was a white capsule on a white card with a sliver of colour at one end -- the empty part of the
	-- bar and the surface behind it were literally the same value, and the only thing saying where
	-- the bar ended was its outline. `Cloud` is one step down the light neutrals (lum 0.89, still a
	-- light surface by every rule in this file) and reads as a groove the fill sits IN.
	applyShell(bar, opts.trackColor or Color.Cloud, radius, opts.thickness or 4)
	-- ===== THE HOST MUST NOT CLIP, AND THAT IS THE OTHER HALF OF THE BLACK CAPS (18.1) =====
	--
	-- 17.8 found the lip and removed it on round shells. It was right and it was not the whole fault:
	-- this line was. `ClipsDescendants` on a frame with no `UICorner` of its own clips to a SQUARE,
	-- while both bodies `applyShell` puts inside it are pills carrying a `UIStroke` drawn OUTSIDE
	-- their curve. The region inside the square and outside the pill is exactly the four corners --
	-- which is where those strokes still are -- so at `Radius.Pill` the two at each end merge into
	-- one near-black crescent capping the bar. That is the boss bar Kristina photographed on
	-- 2026-08-16 ("ovaj health bar ne treba ove tamne stvari iza nema smisla to"), and it is why the
	-- bar had no visible outline along its top and bottom: those parts of the stroke WERE clipped.
	--
	-- Rounding the clip (a `UICorner` on the host) is the obvious fix and is wrong: the host and its
	-- `InnerBody` are the same rectangle, so a rounded clip cuts the outline off the entire bar
	-- instead of only its ends. The fill is clipped one level down instead -- `InnerBody` already
	-- sets `ClipsDescendants` and already carries the right radius -- and the host clips nothing, so
	-- every stroke on it is drawn whole. Proved live before it was written: with these two lines
	-- changed on the running boss bar, the caps disappear and the outline closes round the ends.
	bar.ClipsDescendants = false
	bar.Parent = parent

	if opts.shadow ~= false then
		addShadow(bar, radius)
	end

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(opts.progress or 0, 0, 1, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	-- Inside `InnerBody`, not beside it (18.1). Two things follow and both are wanted: the pill's own
	-- clip trims the fill at both curved ends -- which is what the host's square clip was there to
	-- do, badly -- and the fill can no longer cover the outline, because the stroke is drawn outside
	-- the body the fill now lives in. Its ZIndex is relative to that body for the same reason.
	fill.ZIndex = (bar:FindFirstChild("InnerBody") and bar.InnerBody.ZIndex or (base + Z.Body)) + 1
	fill.BackgroundColor3 = opts.color or Color.Green
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = radius
	fillCorner.Parent = fill
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Name = "Gradient"
	fillGrad.Rotation = 90
	fillGrad.Color = gradientFor(opts.color or Color.Green)
	fillGrad.Parent = fill
	fill:SetAttribute("BaseColor", opts.color or Color.Green)
	fill.Parent = bar:FindFirstChild("InnerBody") or bar

	if opts.gloss ~= false then
		local gloss = addGloss(bar, radius)
		-- base + 3, not base + 2: the fill sits at the body's ZIndex + 1 now (18.1), so the old value
		-- tied with it. A tie is not a draw order, it is whichever the engine happens to walk last.
		gloss.ZIndex = base + 3 -- above the fill, still below the label at base + Z.Content (4)
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -12, 1, -6)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = DisplayFont
	label.TextColor3 = Color.White
	label.Text = opts.text or ""
	label.ZIndex = base + Z.Content
	-- ===== THE ONE LABEL IN THE KIT THAT MUST NOT ASK `inkOn` (17.18) =====
	--
	-- It is centred across the WHOLE bar, so at 40% progress its left half is printed on `opts.color`
	-- and its right half on the track -- two fills, one word, and no single answer. White with the
	-- full halo is the only ink that survives both, which is why this constructor keeps the hardcode
	-- every other one just gave up. Deliberate, and it belongs here because this is the only place
	-- that knows a progress label straddles two surfaces (rule 7).
	outlineText(label)
	autoSize(label, opts.minTextSize or 14, opts.maxTextSize or 22)
	label.Parent = bar

	return bar, fill, label
end

-- ============================================================================
-- PUBLIC: Badge
-- ============================================================================
function UITheme.Badge(parent, text, color)
	local base = (parent and parent:IsA("GuiObject") and parent.ZIndex) or Z.Shell
	local badgeColor = color or Color.Red
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.new(0, 46, 0, 22)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 6, 0, -8)
	badge.ZIndex = base + Z.Badge
	applyShell(badge, badgeColor, UDim.new(0, 8), 3)
	badge.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -6, 1, -4)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = DisplayFont
	-- 10-15 pt inside a 22 px capsule: the smallest text the kit draws, so a Frost badge with white
	-- ink would be legible only as a black outline of a number. Same one-branch rule as everywhere
	-- else -- ink and halo decided from the same value.
	local badgeInk = inkOn(badgeColor)
	label.TextColor3 = badgeInk
	label.Text = text or ""
	label.ZIndex = badge.ZIndex + Z.Content
	outlineText(label, isDarkInk(badgeInk) and 0 or 2)
	autoSize(label, 10, 15)
	label.Parent = badge

	return badge
end

-- ============================================================================
-- PUBLIC: SetColor / SetText
-- ============================================================================
-- ===== THE COLOUR IS NOT ON THE FRAME YOU WERE GIVEN (16.3, found live 2026-08-16) =====
--
-- `applyShell` above stopped painting its host at 15.28: the host goes fully transparent and the
-- fill, its gradient and the moulded bottom lip move into `InnerBody` and `ShadowBody` children.
-- Every helper that repaints by writing `BackgroundColor3` on the host therefore writes a colour
-- nothing draws, and returns quietly -- there is no error and no warning, and the surface simply
-- keeps the hue it was built with.
--
-- Measured on the running HUD: **631 shells on screen**, and a `SetColor` to magenta moved the
-- host's invisible colour while the drawn fill, its gradient and the lip all stayed put. That is
-- roughly 25 state recolours across the client -- the Robux tabs, the mute toggle, the Auras
-- `Wear` buttons, the shard button, the potion rows, every Locked/Green claim button, `SplicerUI`'s
-- roll button, `ZoneTransition`'s name card -- all of them dead, and all of them told apart by
-- their UIStroke alone, which is why so many states here read as "nearly the same button".
--
-- `paintable` is the whole fix: ask the surface where its colour lives. A shell answers
-- `InnerBody`; a plain frame -- a `ProgressBar` fill, which is what `CombatClient` recolours for
-- the boss bar -- answers itself, and behaves exactly as it did before.
-- Public, because `registerPanel` in MainUI has the same question about the same surfaces: the
-- panel rim it sets is a UIStroke that is no longer a child of the panel either (16.4).
function UITheme.FaceOf(inst)
	if not inst then
		return nil
	end
	local body = inst:FindFirstChild("InnerBody")
	if body and body:IsA("GuiObject") then
		return body
	end
	return inst
end
local paintable = UITheme.FaceOf

function UITheme.SetColor(inst, color)
	if not inst or not color then
		return
	end
	-- An IconTile is two shells of the SAME colour (see IconTile: the outer one is the button, the
	-- inner one is the face). Both have to move together, or a recoloured tile shows the old hue in
	-- the one pixel of corner where the two roundings do not exactly coincide. Both are `applyShell`
	-- surfaces, so both are painted through `paintable`.
	local isTileBody = false
	local tileBody = inst:FindFirstChild("Body")
	if tileBody and tileBody:IsA("Frame") and tileBody:GetAttribute("BaseColor") then
		local shell = inst
		inst = tileBody
		isTileBody = true
		local shellFace = paintable(shell)
		shellFace.BackgroundColor3 = color
		shell:SetAttribute("BaseColor", color)
		local shellGrad = shellFace:FindFirstChild("Gradient")
		if shellGrad and shellGrad:IsA("UIGradient") then
			shellGrad.Color = pastelGradientFor(color)
		end
		local shellLip = shell:FindFirstChild("ShadowBody")
		if shellLip and shellLip:IsA("GuiObject") then
			shellLip.BackgroundColor3 = lipShade(color)
		end
	end
	local face = paintable(inst)
	face.BackgroundColor3 = color
	local grad = face:FindFirstChild("Gradient")
	if not grad or not grad:IsA("UIGradient") then
		grad = face:FindFirstChildOfClass("UIGradient")
	end
	if grad then
		grad.Color = isTileBody and pastelGradientFor(color) or gradientFor(color)
	end
	-- The lip, through the same `lipShade` `applyShell` built it with -- including its light-fill
	-- branch, or a surface recoloured TO white keeps the -0.4 grey foot of the colour it used to be.
	-- Without this the recoloured face sits on a moulded edge in the previous colour, which is more
	-- visible than no lip at all.
	local lip = inst:FindFirstChild("ShadowBody")
	if lip and lip:IsA("GuiObject") then
		lip.BackgroundColor3 = lipShade(color)
	end
	-- The pre-15.28 lip. Kept only because a surface built before that change can still be on screen
	-- in a session that hot-reloaded UITheme; new surfaces never have the child, so this never runs.
	local oldLip = inst:FindFirstChild("Shadow")
	if oldLip and oldLip:IsA("Frame") and oldLip:GetAttribute("IsLip") then
		oldLip.BackgroundColor3 = shade(color, -0.30)
	end
	inst:SetAttribute("BaseColor", color)
end

function UITheme.SetText(inst, text)
	if not inst then
		return
	end
	local host = inst:FindFirstChild("Body") or inst
	local label = host:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		-- THE GLYPH COMES OUT WHEN THERE IS ALREADY A DRAWING OF IT (9.9). Dozens of call sites
		-- rewrite a caption with the emoji baked into the new string -- `SetText(btn, "🎡 SPIN 25🌟")`
		-- -- and on a button whose icon is now an ImageLabel that would put the emoji back beside
		-- the picture of itself. Stripping only a LEADING mapped glyph is deliberate: the trailing
		-- 🌟 in that same string is part of a price and has no icon slot to move into.
		local slot = inst:FindFirstChild("Icon")
		if slot and slot:IsA("ImageLabel") then
			-- ...AND THE PICTURE FOLLOWS THE WORDS. A control's leading glyph is not decoration, it
			-- is part of what the control currently SAYS: the shard spin button reads
			-- "🎡 SPIN 25🌟" when it can be pressed and "🌟 4 / 25" when it cannot. An icon frozen
			-- at build time would keep offering a wheel next to a progress count. Only updated when
			-- the new text actually leads with a mapped glyph -- otherwise the existing icon stands,
			-- because "REVIVE  (2 left)" is the same button as "⚔️ REVIVE" with a different caption.
			local nextAsset = IconLibrary.Resolve(text)
			if nextAsset then
				slot.Image = nextAsset
			end
			text = IconLibrary.StripLeading(text)
		end
		label.Text = text
		return
	end
	-- An IconTile whose icon is drawn has an ImageLabel called "Label" and no text at all. Setting
	-- `.Text` on it would error, and the caption is a different child anyway -- so this is a no-op
	-- by design rather than by accident.
	if label and label:IsA("ImageLabel") then
		return
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Text = text
	end
end

-- Swaps the drawing in an icon slot, for the handful of places that change what a control MEANS
-- rather than what it says -- the potion strip's kind, a tab's state. Takes an emoji, like
-- everything else in this system, and falls back to writing the glyph when there is no art.
function UITheme.SetIcon(inst, emoji)
	if not inst then
		return
	end
	local host = inst:FindFirstChild("Body") or inst
	local slot = host:FindFirstChild("Icon") or host:FindFirstChild("Label")
	if not slot then
		return
	end
	local asset = IconLibrary.Resolve(emoji)
	if slot:IsA("ImageLabel") then
		-- An unmapped emoji cannot be shown by an ImageLabel, so it clears rather than leaving the
		-- PREVIOUS icon standing -- a stale picture is a worse answer than an empty slot, because it
		-- is the one a player would believe.
		slot.Image = asset or ""
	elseif slot:IsA("TextLabel") then
		slot.Text = emoji or ""
	end
end

-- ============================================================================
-- A BUTTON THAT IS SOMETIMES A PICTURE AND SOMETIMES A WORD (10.20)
-- ============================================================================
-- The zone list's Go button is the case this exists for: locked it is a padlock, unlocked it is
-- the word "Go". Both cannot be shown at once and neither can be built lazily -- a slot created on
-- first use leaves the very first draw of a fresh save showing whatever the other state left
-- behind.
--
-- So the caller builds the ImageLabel once, at construction, and flips between the two here. The
-- icon is HIDDEN rather than blanked: clearing `Image` would make the next flip re-fetch the
-- texture, and a texture that is re-fetched is a texture that can be missing for a frame.
--
-- IN UITheme RATHER THAN IN MainUI, deliberately. MainUI's top level is one Luau function with a
-- 200-register ceiling and this would be one more named local there for no benefit -- the same
-- reason IconSlot, IconifyLabel and SetIcon all live here. See the register note in MainUI.
function UITheme.ShowIconOrText(button, useIcon, text, iconName)
	if not button then return end
	local icon = button:FindFirstChild(iconName or "LockIcon", true)
	if icon then
		icon.Visible = useIcon
	end
	-- When there is no icon slot at all -- an unmapped emoji, or a build that skipped it -- fall
	-- back to text in BOTH states rather than showing an empty button. An icon that does not exist
	-- must never be able to produce a button with nothing on it.
	button.Text = (useIcon and icon) and "" or (text or "")
end

-- ============================================================================
-- JUICY INTERACTION HELPERS: Pulse & SetProgress
-- ============================================================================
function UITheme.Pulse(inst, maxScale)
	if not inst or not RunService:IsClient() then
		return
	end
	-- ===== A SHELLED SURFACE IS TWO INSTANCES AND THE CALLER HOLDS THE INNER ONE (17.13) =====
	--
	-- `UITheme.Pill(..., { shellColor = ... })` returns the transparent content frame and hangs the
	-- capsule around it as a parent, because `applyShell`'s two body children cannot live inside a
	-- UIListLayout (see the note there). Every caller still says `UITheme.Pulse(pill)` and means
	-- "make the thing I can see jump" -- so a pulse landing on the inner frame would scale the number
	-- and the icon out of a capsule that stayed perfectly still.
	--
	-- An ObjectValue rather than an attribute, because attributes cannot hold an Instance, and rather
	-- than walking up to `inst.Parent`, because a Pill with no shell has a parent that is somebody
	-- else's layout frame and pulsing THAT would jump the whole currency stack. The constructor that
	-- knows about the pairing is the one that records it; nothing else in the codebase uses the name.
	local host = inst:FindFirstChild("PulseHost")
	if host and host:IsA("ObjectValue") and host.Value and host.Value:IsA("GuiObject") then
		inst = host.Value
	end
	local scale = inst:FindFirstChild("Scale")
	if not scale or not scale:IsA("UIScale") then
		scale = inst:FindFirstChildOfClass("UIScale")
	end
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "Scale"
		scale.Scale = 1
		scale.Parent = inst
	end
	scale.Scale = maxScale or 1.15
	TweenService:Create(scale, PULSE_TWEEN_INFO, { Scale = 1.0 }):Play()
end

function UITheme.SetProgress(bar, progress, animated)
	if not bar then
		return
	end
	-- Recursive since 18.1: the fill is a child of the bar's `InnerBody` now, not of the bar. A
	-- non-recursive lookup returns nil there and this function's early `return` is silent, so every
	-- bar in the game would simply stop moving with nothing in the console.
	local fill = bar:FindFirstChild("Fill", true)
	if not fill or not fill:IsA("Frame") then
		return
	end
	local target = math.clamp(progress or 0, 0, 1)
	if animated ~= false and RunService:IsClient() then
		TweenService:Create(fill, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(target, 0, 1, 0)
		}):Play()
	else
		fill.Size = UDim2.new(target, 0, 1, 0)
	end
end

return UITheme
