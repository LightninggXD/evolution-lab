--[[
	PanelFocus -- when a HUD panel opens, the WORLD steps back.

	The problem this exists for: our panels are near-white (luminance 0.89) and they float over a map
	that is deliberately bright and saturated. A 460x510 cream card over a sunlit sand zone has almost
	no separation from what is behind it -- it reads as a rectangle lying on the world rather than as
	the thing you are now looking at. Every genre reference solves this the same way and it is not by
	changing the panel.

	=========================================================================================
	WHY THIS IS NOT A VIOLATION OF "NO TRANSPARENCY / BLUR ON GUI SURFACES"
	=========================================================================================
	It is a different mechanism from the one that rule is about, and the research pass says so
	outright (guidelines/ui-research-2026.md section 5.1, and contradiction #2 at the bottom of that
	file: "right rule, wrong scope"). A BlurEffect under Lighting is a POST-PROCESS on the 3D render.
	It is composited BEFORE any ScreenGui is drawn, so it cannot touch a single pixel of the HUD --
	the panel stays exactly as opaque and as chunky as it was authored. Nothing here is glassy, and
	nothing here puts transparency on a GuiObject. The readme's rule is about GUI surfaces and stays
	intact.

	The recipe is the widely-copied one: blur the camera and pull the saturation down, panel still
	fully opaque above it.
	https://devforum.roblox.com/t/localscript-blur-background-inside-esc-menu/2486466  [FORUM]

	=========================================================================================
	WHAT THIS FILE IS CAREFUL ABOUT
	=========================================================================================
	1. IT OWNS TWO NAMED INSTANCES AND MATCHES ON THE NAME, NEVER ON THE CLASS.
	   Lighting already holds EvolveReveal's BlurEffect (parked at Size 0) and SplicerUI's, and a
	   `FindFirstChildOfClass("BlurEffect")` finds whichever was parented first. A previous session
	   lost an afternoon to exactly that: the blur it was measuring was a different script's, sitting
	   at 0, and the feature was reported dead when it was only the wrong object being read. Ours are
	   `PanelFocusBlur` and `PanelFocusGrade` and every lookup in this file is by that name.

	2. IT COMPOSES WITH THE OTHER TWO BLURS RATHER THAN FIGHTING THEM.
	   EvolveRevealBlur and SpliceRevealBlur are separate instances driven by separate scripts, and
	   nothing here reads, writes, disables or destroys them. IF BOTH ARE ACTIVE AT ONCE -- a
	   Legendary splice landing while the Inventory panel is open -- the world simply gets both: two
	   BlurEffects each apply their own pass, so the world goes softer than either intended, and two
	   ColorCorrectionEffects STACK rather than one winning (ZoneBuilder's own comment at the
	   `ToonPunch` grade records that the hard way). That overlap is visually acceptable -- both
	   moments want the world gone -- and it is self-clearing, because each script releases only its
	   own instance. The failure mode we CANNOT have is one script tidying up another's effect and
	   leaving the game permanently out of focus with no way out but rejoining.

	   Related trap worth writing down: ZoneBuilder deletes every ColorCorrectionEffect in Lighting
	   that is not named `ToonPunch`, on purpose, because grades stack. That sweep runs on the SERVER
	   and a client-created instance is invisible to the server, so ours survives -- but `ensure()`
	   below re-creates a missing effect anyway rather than trusting a cached reference, so if that
	   sweep ever moves client-side this degrades to a flicker instead of a dead feature.

	3. ZERO COST WHEN NO PANEL IS OPEN.
	   No RenderStepped, no Heartbeat. Everything is driven by property signals plus TweenService, and
	   both effects are `Enabled = false` while idle so the engine skips the passes entirely instead of
	   running a Size-0 blur every frame. The only repeating thing in the file is a 2 s audit that
	   exists solely as a safety net and only runs while the world is actually dimmed.

	4. IT IS NOT ALLOWED TO STRAND THE PLAYER IN A BLURRED WORLD.
	   Death, respawn, a zone teleport, the ScreenGui being rebuilt, a signal we never received, or an
	   error inside one of our own handlers -- all of them end at the same place: `recount()` reads the
	   live tree and decides from scratch. Nothing in this file remembers that a panel was open; it
	   only ever asks.

	=========================================================================================
	COST, ON A PHONE, WITH STREAMING ON
	=========================================================================================
	BlurEffect is a real full-screen pass and it is not free. What was considered:

	  - Size 14, not the 20-24 the forum recipe uses. Blur cost scales with radius, and section 5.1
	    calls 14 sufficient for our map anyway.
	  - `Enabled = false` when idle (EvolveReveal does this; SplicerUI parks at Size 0 instead, which
	    still runs the pass). A player who never opens a panel pays nothing at all.
	  - ColorCorrectionEffect is a per-pixel matrix and is close to free; it is the half doing most of
	    the actual "recede" work, which is why the blur can stay small.
	  - REJECTED: DepthOfFieldEffect. More expensive than blur, has to be tuned against the scene, and
	    with StreamingEnabled the focus distance would fight parts popping in behind the player.
	  - REJECTED: a full-screen scrim Frame. That is a GuiObject with a transparency, i.e. the thing
	    the readme actually bans, and it would have to live in MainUI's ScreenGui.
	  - REJECTED: touching Lighting.Ambient / Brightness / the ClockTime. Those are the WORLD's look,
	    they are authored by ZoneBuilder, and ambient settles a frame or two after it is written --
	    the "a skybox is a light source" trap. A post-process changes the picture without touching the
	    scene.
	  - Nothing here reads or writes workspace, so streaming is irrelevant to it.

	KNOWN DEGRADATION: Roblox drops post-processing entirely at the lowest graphics quality levels.
	On such a device this feature simply does not appear. That is a soft failure by design -- the
	panel is fully opaque with a 5-6 px outline either way, so nothing becomes unreadable, it just
	stops being flattered.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== THE TWO NAMES THAT MUST BE RIGHT =====================================
-- `EvolutionLabUI` is MainUI's ScreenGui (MainUI.client.lua:473) and `HudPanel` is the attribute
-- `registerPanel` stamps on every floating panel (MainUI.client.lua:996) precisely so a second
-- script can ask "is a panel open?" without MainUI exporting anything -- MainUI is at Luau's 200
-- top-level local cap and cannot afford to export. FirstJoin already reads the same pair to get its
-- tutorial banner out from under a modal. 19 panels carry it today; this file never counts them.
local GUI_NAME = "EvolutionLabUI"
local PANEL_ATTR = "HudPanel"

local BLUR_NAME = "PanelFocusBlur"
local GRADE_NAME = "PanelFocusGrade"

-- ===== THE NUMBERS AND WHERE EACH ONE COMES FROM =============================
--
-- FADE_IN 0.18 -- section 5.1: tween in over 0.18 s to match the panel's 0.22 s open, NOT the 0.5 s
--                 the forum script uses. The world should already be soft by the time the Back/Out
--                 overshoot settles, or the dim reads as a second, later event.
-- FADE_OUT 0.12 -- MainUI's own close tween is `TweenInfo.new(0.12, Quad, In)` (MainUI:1092). The
--                 world coming back on exactly that curve is what makes the two read as one motion.
--
-- BLUR / SAT: two endpoints, picked by the player's accessibility preference (see below).
--   default (14, -0.6) -- section 5.1 [INFER], for our bright saturated map. -1 is greyscale and
--                         reads as "the game is paused" rather than "a panel is open".
--   opaque  (20, -1.0) -- the sourced forum values, which are also simply the strongest this
--                         mechanism goes. Reserved for a player who has asked for opaque backgrounds.
local FADE_IN = 0.18
local FADE_OUT = 0.12
local BLUR_DEFAULT, BLUR_OPAQUE = 14, 20
local SAT_DEFAULT, SAT_OPAQUE = -0.6, -1

-- How often the safety-net audit re-reads the tree WHILE DIMMED. Nothing depends on it in normal
-- operation; 2 s is slow enough to be free and fast enough that a stranded blur is a blip, not a bug
-- report.
local AUDIT_PERIOD = 2

-- A UIScale sitting within this of its FitScale counts as "fully open". Floating-point slack only:
-- the open tween's final write is the fitted value exactly, and the close tween's first write is
-- meaningfully below it (it targets fit * 0.9), so nothing hinges on the size of this number.
local FIT_EPSILON = 0.001

-- ===== ACCESSIBILITY: PreferredTransparency ==================================
--
-- Section 5.2. `GuiService.PreferredTransparency`: "A value of 1 indicates the player prefers the
-- default background transparency, while a value of 0 indicates the player prefers fully opaque."
-- [DOC] https://create.roblox.com/docs/production/publishing/accessibility
--
-- 5.2 writes the rule for a GUI scrim's alpha. This is the same rule applied to the mechanism we
-- actually use: a player who has asked for opaque backgrounds is asking for the thing behind the UI
-- to stop showing through, so they get the STRONGER recession (blur 20, fully desaturated), and
-- everyone else gets the default. Linear between the two endpoints, so a value of 0.5 is halfway.
--
-- pcall'd because the property is recent and a client that predates it must not take the feature
-- down with it; 1 (the default preference) is the fallback.
local function preferredTransparency()
	local ok, value = pcall(function()
		return GuiService.PreferredTransparency
	end)
	if ok and type(value) == "number" then
		return math.clamp(value, 0, 1)
	end
	return 1
end

local function targets()
	local pref = preferredTransparency()
	return BLUR_OPAQUE + (BLUR_DEFAULT - BLUR_OPAQUE) * pref,
		SAT_OPAQUE + (SAT_DEFAULT - SAT_OPAQUE) * pref
end

-- Section 2.6: `GuiService.ReducedMotionEnabled` is a player setting and Roblox's own remedy is
-- literally to set TweenInfo.Time to 0. A player who has asked for less motion still gets the dim --
-- it is a legibility feature, not decoration -- they just get it instantly.
local function duration(seconds)
	local ok, reduced = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	if ok and reduced then
		return 0
	end
	return seconds
end

-- ===== THE EFFECTS ===========================================================
--
-- Created here, never assumed to exist, and re-created if they go missing. Both are held at neutral
-- AND disabled while idle: `Enabled = false` is what actually makes the pass cost nothing, Size = 0
-- alone does not.

local blurFx, gradeFx
local liveBlur, liveGrade

local function ensure()
	if not blurFx or blurFx.Parent ~= Lighting then
		local found = Lighting:FindFirstChild(BLUR_NAME)
		if found and found:IsA("BlurEffect") then
			blurFx = found
		else
			-- something else has taken the name -- ours is the one that has to work
			if found then
				found:Destroy()
			end
			blurFx = Instance.new("BlurEffect")
			blurFx.Name = BLUR_NAME
			blurFx.Size = 0 -- a fresh BlurEffect does NOT default to 0
			blurFx.Enabled = false
			blurFx.Parent = Lighting
		end
	end

	if not gradeFx or gradeFx.Parent ~= Lighting then
		local found = Lighting:FindFirstChild(GRADE_NAME)
		if found and found:IsA("ColorCorrectionEffect") then
			gradeFx = found
		else
			if found then
				found:Destroy()
			end
			gradeFx = Instance.new("ColorCorrectionEffect")
			gradeFx.Name = GRADE_NAME
			-- Saturation ONLY. Brightness, Contrast and TintColor stay at neutral on purpose: the
			-- zone grade `ToonPunch` owns those (contrast 0.26, saturation 0.38) and grades stack, so
			-- writing a second contrast here would silently double the world's contrast on top of a
			-- look somebody spent a session tuning.
			gradeFx.Saturation = 0
			gradeFx.Brightness = 0
			gradeFx.Contrast = 0
			gradeFx.Enabled = false
			gradeFx.Parent = Lighting
		end
	end
end

local dimmed = false
local auditToken = 0

-- Every write to the two effects goes through here, and it is pcall'd end to end. If a Lighting
-- write ever throws, the caller -- which is a property-change handler on somebody else's panel --
-- must not die with it.
local function applyDim(on)
	local ok, err = pcall(function()
		ensure()

		-- ONE LIVE TWEEN PER EFFECT, cancelled before the next is played. This is the same trap
		-- `animatePanel` documents for the panel's own UIScale: opening a panel while the previous
		-- dim-out is still running otherwise leaves two tweens writing Size in the same frame and the
		-- blur settles wherever the loser stopped.
		if liveBlur then
			liveBlur:Cancel()
			liveBlur = nil
		end
		if liveGrade then
			liveGrade:Cancel()
			liveGrade = nil
		end

		local blurTarget, satTarget = targets()
		local seconds = duration(on and FADE_IN or FADE_OUT)
		local info = TweenInfo.new(
			seconds,
			Enum.EasingStyle.Quad,
			on and Enum.EasingDirection.Out or Enum.EasingDirection.In
		)

		if on then
			-- enabled BEFORE the tween, or the first frames of the fade render nothing
			blurFx.Enabled = true
			gradeFx.Enabled = true
		end

		liveBlur = TweenService:Create(blurFx, info, { Size = on and blurTarget or 0 })
		liveGrade = TweenService:Create(gradeFx, info, { Saturation = on and satTarget or 0 })

		if not on then
			-- Disabled only once the fade has actually finished, and only if nothing re-dimmed in the
			-- meantime. `Cancelled` means a panel opened mid-fade and is now driving these itself --
			-- disabling here would kill the dim the player just asked for.
			liveBlur.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and not dimmed then
					blurFx.Enabled = false
					gradeFx.Enabled = false
				end
			end)
		end

		liveBlur:Play()
		liveGrade:Play()
	end)

	if not ok then
		-- Last resort: if the tween path failed we still must not leave the world soft. Written
		-- outright, no tween, no pcall dependency on the block above.
		warn("[PanelFocus] " .. tostring(err))
		if not on and blurFx and gradeFx then
			blurFx.Size = 0
			blurFx.Enabled = false
			gradeFx.Saturation = 0
			gradeFx.Enabled = false
		end
	end
end

-- ===== WHICH PANELS ARE OPEN =================================================
--
-- `closing` is the interesting half. MainUI's close animation keeps a panel `Visible` for the whole
-- 0.12 s of its shut tween (MainUI:1145-1156, `panel.Visible = false` happens in the tween's
-- Completed handler) -- so a naive "is anything Visible?" test holds the dim for an extra eighth of
-- a second after the panel has visibly gone, and the world comes back late enough to read as a
-- separate event.
--
-- The signal that a close has BEGUN is the UIScale: `animatePanel` opens by tweening Scale up to the
-- panel's published `FitScale` (Back/Out, which overshoots and settles exactly on it) and closes by
-- tweening it down to FitScale * 0.9. So:
--
--     Scale reaches FitScale        -> the panel is fully open   (`reached`)
--     Scale drops below it again    -> the close has started     (`closing`)  -> stop counting it
--     Scale climbs back / reopened  -> the close was cancelled   -> count it again
--
-- `reached` is what stops the OPEN tween being mistaken for a close: the open starts at
-- FitScale * 0.86, which is also below FitScale, and without the gate every panel would be born
-- "closing".
local watched = {}
local closing = {}
local reached = {}

local gui = nil

-- The one place that decides. Reads the live tree every time and remembers nothing, which is why
-- death, a teleport, a rebuilt ScreenGui and a signal we simply never got all heal for free.
local function recount()
	local open = false
	if gui and gui.Parent and gui.Enabled then
		-- Direct children only, exactly like FirstJoin's sweep: `registerPanel` stamps the attribute
		-- on the panel itself and every panel is parented straight to the ScreenGui.
		for _, child in ipairs(gui:GetChildren()) do
			if child:GetAttribute(PANEL_ATTR) and child:IsA("GuiObject") and child.Visible and not closing[child] then
				open = true
				break
			end
		end
	end

	if open == dimmed then
		return
	end
	dimmed = open
	applyDim(open)

	if open then
		-- THE SAFETY NET, AND THE ONLY LOOP IN THE FILE. It starts when the world goes soft and ends
		-- the moment it comes back, so an idle client never runs it. It exists for the case this file
		-- cannot otherwise see: a panel destroyed outright while open, or a handler above that threw
		-- before it could schedule its recount. The token means a second dim never leaves two running.
		auditToken += 1
		local token = auditToken
		task.spawn(function()
			while dimmed and token == auditToken do
				task.wait(AUDIT_PERIOD)
				if token ~= auditToken then
					return
				end
				-- pcall'd: if the audit's own recount ever threw, the loop would die and take the
				-- safety net with it -- which is the exact scenario it is here for.
				pcall(recount)
			end
		end)
	else
		auditToken += 1 -- retire any audit still spinning
	end
end

-- Deferred and coalesced, and this is load-bearing rather than an optimisation.
--
-- `toggleOnly` closes every panel and then opens one, in the same frame. A per-panel listener that
-- acted immediately would see "the last panel closed" (undim), then "a panel opened" (redim) and
-- flash the world back at full brightness for a frame in the middle of a tab switch. task.defer
-- collapses every change made in a frame into ONE reading taken after all of them have landed, so
-- the switch is seen as what it is: a panel was open before and a panel is open after.
local pending = false
local function schedule()
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		recount()
	end)
end

local function watch(panel)
	if watched[panel] then
		return
	end
	watched[panel] = true

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		-- Either edge clears both marks. Visible going true is a fresh open (whatever the scale was
		-- left at); Visible going false is the close completing, and MainUI writes Scale back up to
		-- FitScale immediately afterwards -- a stale `reached` from that write is exactly what would
		-- make the NEXT open look like a close.
		closing[panel] = nil
		reached[panel] = nil
		schedule()
	end)

	-- A panel authored with no pixel size never got a UIScale (registerPanel returns early), so it
	-- has no close tween to detect and simply counts as open until Visible goes false. It gets the
	-- old, slightly-too-long behaviour rather than no behaviour.
	local scale = panel:FindFirstChildOfClass("UIScale")
	if not scale then
		return
	end

	scale:GetPropertyChangedSignal("Scale"):Connect(function()
		local fit = panel:GetAttribute("FitScale") or 1
		if scale.Scale >= fit - FIT_EPSILON then
			reached[panel] = true
			if closing[panel] then
				closing[panel] = nil
				schedule()
			end
		elseif reached[panel] and not closing[panel] then
			closing[panel] = true
			schedule()
		end
	end)
end

-- ===== FINDING THE HUD, AND SURVIVING IT BEING REBUILT =======================

local function attach(newGui)
	gui = newGui

	-- Fresh tables: the old ones are keyed by panels that no longer exist, and their connections
	-- died with them.
	watched = {}
	closing = {}
	reached = {}

	for _, child in ipairs(gui:GetChildren()) do
		if child:GetAttribute(PANEL_ATTR) then
			watch(child)
		end
	end

	-- Several panels are built lazily on first open and do not exist when this file first runs.
	-- ChildAdded rather than DescendantAdded because panels are direct children -- the same shape as
	-- the scroll-affordance sweep at the bottom of MainUI, which uses DescendantAdded only because
	-- ScrollingFrames are nested.
	--
	-- Deferred, because `registerPanel` stamps `HudPanel` AFTER the panel is parented: checking the
	-- attribute inside the signal itself would read nil on every single panel.
	gui.ChildAdded:Connect(function(child)
		task.defer(function()
			if child.Parent == gui and child:GetAttribute(PANEL_ATTR) then
				watch(child)
				schedule()
			end
		end)
	end)

	-- The ScreenGui itself can be switched off (a full-screen takeover, a cutscene). A panel that is
	-- Visible inside a disabled ScreenGui is not on screen and must not hold the world dim.
	gui:GetPropertyChangedSignal("Enabled"):Connect(schedule)

	-- ...and if it is destroyed or reparented, recount reads `gui.Parent` as nil and lets go.
	gui.AncestryChanged:Connect(schedule)

	schedule()
end

task.spawn(function()
	local found = playerGui:WaitForChild(GUI_NAME, 30)
	if found then
		attach(found)
	else
		warn("[PanelFocus] " .. GUI_NAME .. " never appeared -- panels will not dim the world")
	end
end)

-- MainUI's ScreenGui is ResetOnSpawn = false so it normally survives a respawn, but if it is ever
-- rebuilt -- or replaced by a different session's copy -- this picks the new one up and the old
-- one's connections die with it.
playerGui.ChildAdded:Connect(function(child)
	if child.Name == GUI_NAME and child ~= gui then
		attach(child)
	end
end)

-- Death and respawn. Not a recount that expects to find anything different -- the HUD survives a
-- respawn -- but a free re-read at the one moment the player's world visibly changes underneath
-- them, so a dim that got stranded by a death cannot outlive it.
player.CharacterAdded:Connect(schedule)

-- The preference can be changed while the game is running (the Roblox settings menu is open OVER our
-- panels). Re-apply at the new strength only if the world is currently soft; otherwise the next dim
-- reads the new value on its own.
pcall(function()
	GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(function()
		if dimmed then
			applyDim(true)
		end
	end)
end)
