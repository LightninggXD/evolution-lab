--[[
	SpinReveal -- the lucky wheel's shell: it opens the lobby, plays the spins, and owns the remotes
	that both halves talk through (Phase 5.6 + 18.23, rebuilt as a lobby in 34.46).

	===== WHAT 34.46 CHANGED, AND WHY IT IS A DIFFERENT SHAPE OF FILE =====

	This used to be a CUTSCENE. A `SpinResult` arrived, a shell was built, the wheel was already
	turning by the time it faded in, it announced a prize and it closed itself three seconds later.
	The player never chose to spin from in here -- they had pressed something on another panel, been
	charged, and then been shown a result.

	The owner's note, over the reference capture: *"ovo treba da izgleda kad se otvori spin, znaci ne
	odma da vrti, vec da ima opcija da se spina, da pokaze koliko player ima spinova i opcija da
	kupi"*. So the wheel is a PLACE now. It opens idle, showing the prizes, the free-spin countdown
	and how many spins are in the bank; the player presses SPIN; the wheel turns; the prize is
	announced in the same two lines the countdown was using; and it goes back to idle so they can
	spin again without the screen ever being torn down and rebuilt.

	THREE CONSEQUENCES WORTH KNOWING BEFORE EDITING:

	  1. THE SHELL OUTLIVES THE SPIN. `busy` used to mean "a shell exists" and now means "a spin is
	     animating". A shell that exists is just a panel the player is looking at, and closing it is
	     their business, not a `task.delay`.
	  2. EVERY DOOR ENDS UP HERE. A `SpinResult` with no lobby open -- a `LuckySpin` receipt, a spin
	     bought while the panel was shut -- OPENS one and plays into it, rather than building a
	     second, different piece of theatre. One code path, so the wheel cannot look like two things.
	  3. THE ART MOVED OUT to `Modules.HUD.SpinWheelArt` and the chrome to `Modules.HUD.SpinLobby`.
	     Nothing in either changed; they were split because the wheel is now drawn in two states.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local Modules = RS:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local UIKit = require(Modules:WaitForChild("UIKit"))
local SoundLibrary = require(Modules:WaitForChild("SoundLibrary"))
local HUD = Modules:WaitForChild("HUD")
local Art = require(HUD:WaitForChild("SpinWheelArt"))
local SpinLobby = require(HUD:WaitForChild("SpinLobby"))
local ChestReveal = require(HUD:WaitForChild("ChestReveal"))

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")

local STEP = RunService.Heartbeat

local BIG_WINS = {
	jackpot = true, vault = true, relic = true, pet = true, dna_flood = true,
}

-- How long ONE spin's animation may take before the busy flag is force-cleared. It is a fuse, not a
-- schedule: the sequence is `Art.SPIN_TIME` plus a windup, a settle and a prize pause, and the whole
-- chain is bounded by `SpinMaxChain`. If a builder throws in a way the pcall around it does not see,
-- this is what stops the SPIN button reading "SPINNING" for the rest of the session.
local SPIN_WATCHDOG = math.max(24, (GameConfig.SpinMaxChain or 12) * 5.6)
local MAX_QUEUE = 3
local PRIZE_HOLD = 2.6

-- ===== THE CHEST REVEAL (34.54) =====
--
-- How long the chest stands there waiting to be pressed before the wheel gives up and goes back to
-- idle. It is not a deadline on the PRIZE -- the chest is already banked in the save the moment the
-- wedge lands, so a player who walks away has lost nothing and opens it in the Relics panel later.
-- It is a fuse on the SHELL: `animating` is true while the chest is up, so a reveal nobody ever
-- answers would leave the SPIN button reading "SPINNING" until `SPIN_WATCHDOG` (67 s) fired.
local CHEST_WAIT = 25

-- After the press: how long to wait for the save to come back with the chest SPENT, and then for the
-- server's own relic message to land. Two separate waits because they are two separate facts -- the
-- data push proves the chest opened, the `Notify` says what was in it -- and folding them into one
-- timer means a slow second message reads as a failed open.
local CHEST_SPEND_WAIT = 5
local CHEST_NOTICE_WAIT = 1.4

-- 0.30 -> 0.08, measured against the live HUD (34.46) rather than chosen. The lobby's two status
-- lines sit across the bottom of the screen and so do the damage stat (y 545..625) and the evolve
-- bar (y 657..725); the HUD is DisplayOrder 0 and this scrim is 95, so it is drawn over them, but at
-- 0.30 their bright yellow read straight through it and "Damage 4.13K" crossed "Spins : 0". 0.16
-- halved that and did not kill it -- a stroked yellow label survives a 16% veil. This is the number
-- at which the HUD behind stops competing with the panel in front for the same pixels, and the panel
-- is the one the player opened.
local DIM_ALPHA = 0.08

local WHITE = Art.WHITE
local formatNumber = UIKit.formatNumber

local function detailText(spin)
	local d = spin.detail
	if type(d) ~= "table" then return "" end
	local bits = {}
	if d.dna then table.insert(bits, ("+%s DNA"):format(formatNumber(d.dna))) end
	if d.diamonds then table.insert(bits, ("+%d \u{1F48E}"):format(d.diamonds)) end
	if d.shards then table.insert(bits, ("+%d \u{1F31F}"):format(d.shards)) end
	if d.potion then table.insert(bits, ("%dx %s"):format(d.potions or 1, d.potion)) end
	-- ===== THE RELIC LINE IS THE FALLBACK NOW, NOT THE ANSWER (34.54) =====
	--
	-- This used to be the whole prize: the pod stopped on the purple wedge and the lobby printed
	-- *"1 Relic Chest -- open it in the Forge"*, which is a homework assignment rather than a reward.
	-- The owner's note -- *"nek player otvori chest pa koji relic dobije"* -- is about SEEING a chest
	-- and opening it, so `revealChest` below draws one and the relic is announced from the server's
	-- own message afterwards. This string still exists because `playChain`'s pcall falls back to
	-- `detailText` for the last segment when the sequence throws, and in that state there is no chest
	-- on the screen -- so it has to tell the player where the thing they won actually went.
	if d.relicChests then
		table.insert(bits, ("%d Relic Chest -- open it in the Relics panel"):format(d.relicChests))
	end
	if d.petName then
		table.insert(bits, ("%s %s%s"):format(d.petEmoji or "\u{1F43E}", d.petName,
			d.petRarity and (" (" .. d.petRarity .. ")") or ""))
	end
	if d.substituted then table.insert(bits, "(" .. d.substituted .. ")") end
	return table.concat(bits, "   ")
end

-- ============================================================================
-- THE SAVE, AS THIS SCRIPT SEES IT
-- ============================================================================
--
-- `DataUpdate` carries the whole table and every panel in the game reads its own fields off it, so
-- the lobby needs no status remote of its own: the spin balance and the free-spin stamp are already
-- being pushed on every change. The two things derived from it are kept here rather than in
-- `SpinLobby`, because the day boundary is a rule about the SAVE and the lobby only draws.
local SECONDS_PER_DAY = 86400
local latestData = nil

local function dayNumber(t)
	return math.floor((t or 0) / SECONDS_PER_DAY)
end

-- Returns (spinTickets, secondsUntilFree, isReady) -- the same day boundary
-- `RewardService.GetFreeSpinStatus` uses on the server, so the countdown under the wheel and the
-- moment the server credits the ticket are one rule rather than two that drift.
local function spinStatus()
	if not latestData then return 0, 0, false end
	local now = os.time()
	local ready = dayNumber(now) > dayNumber(latestData.LastFreeSpin)
	local remaining = ready and 0 or math.max((dayNumber(now) + 1) * SECONDS_PER_DAY - now, 0)
	return latestData.SpinTickets or 0, remaining, ready
end

-- ============================================================================
-- THE SHELL
-- ============================================================================
local shell = nil        -- the one open lobby, or nil
local animating = false  -- a spin is turning right now

local function buildShell()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpinReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 8, 22)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 1
	dim.Parent = gui

	-- 0.70 -> 0.60 and the centre lifted, because the wheel is no longer the only thing on screen:
	-- two status lines and a 72 px control row now sit under it, and at 0.70 the row was drawn over
	-- the bottom of the pie.
	local root = Instance.new("Frame")
	root.Name = "Stage"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.41)
	root.Size = UDim2.fromScale(0.60, 0.60)
	root.SizeConstraint = Enum.SizeConstraint.RelativeYY
	root.BackgroundTransparency = 1
	root.ZIndex = 2
	root.Parent = gui

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.2
	uiScale.Parent = root

	local conns = {}
	local s = {
		gui = gui, blur = blur, dim = dim, root = root, uiScale = uiScale,
		done = false, rot = 0, lastPod = nil,
	}

	function s.track(conn)
		table.insert(conns, conn)
		return conn
	end

	-- Everything `finish` does EXCEPT the fade, because there is nothing left to fade. Split out for
	-- the one caller that needs it: a shell whose ScreenGui was destroyed underneath it (see
	-- `openLobby`), where tweening the corpse throws and the blur would otherwise be left on the
	-- Lighting service for the rest of the session.
	function s.abandon()
		if s.done then return end
		s.done = true
		if shell == s then shell = nil end
		for _, c in ipairs(conns) do
			if c.Connected then c:Disconnect() end
		end
		blur:Destroy()
	end

	function s.finish()
		if s.done then return end
		s.done = true
		if shell == s then shell = nil end
		for _, c in ipairs(conns) do
			if c.Connected then c:Disconnect() end
		end
		TweenService:Create(blur, TweenInfo.new(0.25), { Size = 0 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.22), { Scale = 0.2 }):Play()
		task.delay(0.3, function()
			gui:Destroy()
			blur:Destroy()
		end)
	end

	function s.open()
		blur.Enabled = true
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = 20 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.28), { BackgroundTransparency = DIM_ALPHA }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		SoundLibrary.PlayLocal("open", { volume = 0.45 })
	end

	return s
end

-- ============================================================================
-- OPENING THE LOBBY
-- ============================================================================

-- Fire-and-forget, and it is what BANKS the day's free spin: the server credits a ticket, pushes,
-- and the `DataUpdate` below repaints the balance the lobby is already showing. Deliberately not a
-- RemoteFunction -- a panel that cannot draw until the server answers is a panel that opens late.
local function tellServerLobbyIsOpen()
	local remote = Remotes:FindFirstChild("RequestSpinLobby")
	if remote then remote:FireServer() end
end

local function fireSpin()
	local remote = Remotes:FindFirstChild("UseSpinTicket")
	if remote then remote:FireServer() end
end

local function buyPack(productKey)
	local remote = Remotes:FindFirstChild("PromptRobuxPurchase")
	if remote then remote:FireServer(productKey) end
end

-- Puts the wheel back the way an idle lobby wants it: the won sector shrunk back into the pie, the
-- sunburst off, the prize lines swapped out for the countdown and the balance. Called after every
-- spin rather than on close, because the lobby stays open and the NEXT spin has to start from a
-- wheel that does not still have last time's winner sticking out of it.
local function returnToIdle(s)
	if s.done then return end
	if s.lastPod then
		local scale = s.lastPod:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 1 }):Play()
		end
		s.lastPod = nil
	end
	if s.burst then s.burst.Visible = false end
	TweenService:Create(s.uiScale, TweenInfo.new(0.25), { Scale = 1 }):Play()
	if s.lobby then
		s.lobby.ShowPrize(nil)
		local tickets, remaining, ready = spinStatus()
		s.lobby.SetStatus(tickets, remaining, ready)
	end
end

-- ============================================================================
-- THE CHEST (34.54)
-- ============================================================================
--
-- ===== WHAT THIS ROW TURNED OUT TO BE =====
--
-- The owner, over the wheel: *"i na weelu isto kad stane na relic opciju nek player otvori chest pa
-- koji relic dobije"*. The row was written believing the wheel handed a relic over directly and had
-- to be re-plumbed onto the chest roll. It does not and never did: `GameConfig.SpinWheel`'s `relic`
-- wedge calls `RelicService.GiveChest`, which BANKS an unopened chest, and 34.55 made a banked chest
-- one of only two doors a relic can arrive through. So the grant was already right, and everything
-- this row needed was on this side of the wire -- what the player SAW was a sentence telling them to
-- go and find the forge.
--
-- ===== THE ONE RULE THIS CODE MUST NOT BREAK =====
--
-- **It must not add a second grant.** Pressing OPEN fires the same `OpenRelicChest` remote the Relics
-- panel's own button fires, with the same `"banked"` source, so the wheel's chest, the grotto's chest
-- and the 40-diamond buy are provably one roll -- the luck bend, the collection relic, the auto-equip
-- and the telemetry all stay inside `RelicService.HandleOpenChest`. Nothing here learns what the
-- relic was except by being told, and it is told by the server.
--
-- ===== WHY THE PRIZE IS RE-DRAWN HERE RATHER THAN LEFT TO THE HUD =====
--
-- `RelicService` already announces the relic through `Notify` and MainUI draws it properly -- a big
-- card for a first Legendary or Mythic, a toast for everything else, pitched by rarity. But MainUI is
-- DisplayOrder 0 and this shell is 95 over a scrim at 0.08 transparency, so that announcement lands
-- UNDERNEATH a nearly solid black sheet: a player opening a chest in here would watch it burst and
-- then be told nothing at all. So the lobby repeats it -- using the server's own `message` string and
-- never a sentence composed on this side.
local relicNotices = {}
local capturingRelics = false

-- Yields until the chest is opened, skipped, or the fuse burns out. Called from inside `playChain`'s
-- pcall, so a throw in here is caught exactly the way a throw in the wheel animation is.
--
-- THE RELIC WEDGE IS ALWAYS THE LAST SEGMENT OF A CHAIN, and that is what makes blocking here safe:
-- only `respin` chains, so nothing can follow a `relic`. If a future segment ever chained as well,
-- this call would have to move after the loop rather than sit inside it.
local function revealChest(s)
	if s.done then return end

	local remote = Remotes:FindFirstChild("OpenRelicChest")
	-- THE GATE IS READ OFF THE SAVE, NOT ASSUMED. `IsRelicForgeUnlocked` is the same test the server
	-- runs, and it is a STICKY FLAG as well as a stage check -- so a rebirthed player back at stage 1
	-- still opens chests, and a check that only compared `StageIndex` would call this shut and be
	-- wrong (the trap 34.53 already records).
	local canOpen = remote ~= nil and GameConfig.IsRelicForgeUnlocked(latestData)
	local before = tonumber(latestData and latestData.RelicChests) or 0

	local pressed, skipped = false, false
	local reveal = ChestReveal.Build(s.gui, {
		zIndex = 60,
		-- A PLAIN WORD. The crystal ball drew as a grey-purple blob beside the chest on the first
		-- live capture -- an emoji typed into a label is whatever glyph the platform happens to ship
		-- ([[evolution-lab-icon-system]]), and here it was a SECOND, different picture of the very
		-- prize the chest underneath it is already drawing. Same fault 34.20 fixed on the Sword
		-- panel's title, one screen over.
		title = "RELIC CHEST",
		hint = canOpen and "You won a chest -- open it!"
			or ("Banked \u{00B7} the Relic Forge opens at stage %d")
				:format(GameConfig.RelicUnlockStage),
		locked = not canOpen,
		onOpen = function() pressed = true end,
		onSkip = function() skipped = true end,
	})

	local deadline = os.clock() + CHEST_WAIT
	while not pressed and not skipped and not s.done and os.clock() < deadline do
		task.wait(0.1)
	end

	if pressed and not s.done then
		reveal.SetBusy(true)
		reveal.SetHint("Opening...")

		-- The capture window opens BEFORE the remote is fired. The server grants, pushes and notifies
		-- inside one synchronous block, so the reply can be on the wire before this thread resumes.
		relicNotices = {}
		capturingRelics = true
		remote:FireServer("banked")

		-- THE PROOF THE CHEST OPENED IS THE SAVE, NOT THE MESSAGE. `HandleOpenChest` decrements
		-- `data.RelicChests` and pushes; if it refused -- a stale client whose forge is not actually
		-- open, a save that lost the chest -- the count does not move, and nothing here pretends it
		-- did.
		local until1 = os.clock() + CHEST_SPEND_WAIT
		local spent = false
		while os.clock() < until1 and not s.done do
			if (tonumber(latestData and latestData.RelicChests) or 0) < before then
				spent = true
				break
			end
			task.wait(0.1)
		end

		if spent then
			SoundLibrary.PlayLocal("open", { volume = 0.5 })
			reveal.PlayOpen()

			-- The relic's own sting is MainUI's (`PlayHatch`, pitched by rarity) and it has already
			-- played by the time the lid goes. Nothing here plays a second one over it.
			local until2 = os.clock() + CHEST_NOTICE_WAIT
			while os.clock() < until2 and #relicNotices == 0 and not s.done do
				task.wait(0.05)
			end
			capturingRelics = false

			-- TWO MESSAGES CAN ARRIVE FROM ONE CHEST and they arrive in this order: the equippable
			-- relic, then the collection relic 30.2 pays beside it. The first is the headline, the
			-- second is the detail line -- folding them into one string would hide whichever lost.
			local first, second = relicNotices[1], relicNotices[2]
			if first and not s.done and s.lobby then
				local big = first.rarity == "Legendary" or first.rarity == "Mythic"
				s.lobby.ShowPrize("\u{1F52E} " .. tostring(first.message or "Relic"),
					(second and tostring(second.message))
						or (first.equipped and "equipped" or "in your Relics panel"),
					big)
			elseif not s.done and s.lobby then
				-- It opened, but the message never arrived. Say the half that is true rather than
				-- inventing the half that is not.
				s.lobby.ShowPrize("\u{1F52E} RELIC CHEST", "opened -- check your Relics panel", true)
			end
		else
			capturingRelics = false
			if not s.done and s.lobby then
				s.lobby.ShowPrize("\u{1F381} Chest banked", "open it in the Relics panel", false)
			end
		end
	elseif not s.done and s.lobby then
		-- Skipped, or nobody answered. The chest is in the save either way, so this is not a loss and
		-- the line does not read as one.
		s.lobby.ShowPrize("\u{1F381} Relic Chest banked",
			"open it any time in the Relics panel", false)
	end

	capturingRelics = false
	reveal.Destroy()
end

local function openLobby()
	-- ===== A SHELL IS ONLY OPEN IF ITS GUI IS STILL ON THE SCREEN (34.46) =====
	--
	-- MEASURED, not theorised: destroy `PlayerGui.SpinReveal` from anywhere -- a client-side sweep, a
	-- future `ResetOnSpawn`, a developer console -- and `shell` was left pointing at it with
	-- `shell.done` still false, so this returned the corpse and the wheel could never be opened again
	-- for the rest of the session. The old file could not have this bug because its shell lived four
	-- seconds and a `task.delay` cleared the flag; this one is meant to stay open, so the flag needs
	-- a fact behind it rather than a timer.
	if shell and not shell.done then
		if shell.gui.Parent then return shell end
		shell.abandon()
	end

	local s = buildShell()
	if not s then return nil end
	shell = s

	local wheel, pods, arc, bulbs = Art.Wheel(s.root)
	local _, pointer = Art.Furniture(s.root)
	local burst = Art.Burst(s.root)
	s.wheel, s.pods, s.arc, s.bulbs, s.pointer, s.burst = wheel, pods, arc, bulbs, pointer, burst

	-- The celebration rays and the LED strobe, gated on the burst being visible -- so an idle lobby
	-- costs one comparison a frame rather than two rotations and 24 colour writes.
	local innerRays = burst:FindFirstChild("InnerRays")
	local outerRays = burst:FindFirstChild("OuterRays")
	s.track(STEP:Connect(function(dt)
		if burst.Visible then
			if innerRays then innerRays.Rotation = (innerRays.Rotation + dt * 24) % 360 end
			if outerRays then outerRays.Rotation = (outerRays.Rotation - dt * 16) % 360 end
			Art.UpdateLEDs(bulbs, 0, true)
		end
	end))

	-- The idle rim chase. The wheel does not turn until SPIN is pressed, but 24 dead bulbs read as a
	-- broken machine, so the lights run on their own clock while nothing else moves.
	--
	-- THROTTLED TO ~12 Hz, and that is not a micro-optimisation. `UpdateLEDs` writes 24 colours; at
	-- Heartbeat on a 144 Hz display that is 3,456 property writes a second for a panel that is doing
	-- nothing, and the chase is a four-bulb-wide band moving one step at a time -- it does not read
	-- any smoother above about 12 steps a second than it does at 144.
	local nextChase = 0
	s.track(STEP:Connect(function()
		if burst.Visible or animating then return end
		local now = os.clock()
		if now < nextChase then return end
		nextChase = now + (1 / 12)
		Art.UpdateLEDs(bulbs, now * 90, false)
	end))

	s.lobby = SpinLobby.Build(s.gui, s.root, {
		onSpin = function()
			if animating then return end
			local tickets = select(1, spinStatus())
			-- The press goes to the server EITHER WAY. With no tickets the server answers with the
			-- toast that explains how to get one; what the client does differently is skip the
			-- "SPINNING" state, so a refusal does not flicker the button through a lie.
			if tickets >= 1 then
				animating = true
				s.lobby.SetBusy(true)
				-- The fuse. `SpinResult` clears this by playing; if the server refuses after all --
				-- a throttle, a balance the client's copy was stale about -- nothing else would.
				task.delay(6, function()
					if animating and not s.playing then
						animating = false
						if not s.done then s.lobby.SetBusy(false) end
					end
				end)
			end
			fireSpin()
		end,
		onBuy = buyPack,
		onClose = function() s.finish() end,
	})

	local tickets, remaining, ready = spinStatus()
	s.lobby.SetStatus(tickets, remaining, ready)

	-- One second, and only while this lobby is up. A countdown nobody is looking at is a string
	-- rebuild a second, forever, on every client in the server -- the rule `WheelEntry` already
	-- follows for the same clock on the daily panel.
	task.spawn(function()
		while not s.done do
			task.wait(1)
			if not s.done and s.lobby then s.lobby.Tick() end
		end
	end)

	s.open()
	tellServerLobbyIsOpen()
	return s
end

-- ============================================================================
-- PLAYING A CHAIN INTO THE OPEN LOBBY
-- ============================================================================
--
-- `payload.spins` is an ORDERED LIST, not one prize: a `respin` segment chains server-side and the
-- whole chain arrives in one message, already paid for. See `notifySpin` in RobuxShopService for
-- why it must never be handed one segment at a time.
local function playChain(payload)
	local spins = payload.spins
	local s = openLobby()
	if not s then return false end

	animating = true
	s.playing = true
	s.lobby.SetBusy(true)

	local ok, err = pcall(function()
		for i, spin in ipairs(spins) do
			local index = tonumber(spin.index)

			if index and s.pods[index] then
				s.rot = Art.SpinTo(s, s.wheel, s.pointer, s.bulbs, index, s.arc, s.rot)
			else
				task.wait(0.25)
			end
			if s.done then return end

			local isRespin = spin.key == "respin"
			local big = BIG_WINS[spin.key] == true

			if isRespin then
				if s.pods[index] then Art.RevealPod(s.pods[index], false) end
				s.lobby.ShowPrize("\u{1F3A1} SPIN AGAIN!", ("free re-spin (%d)"):format(i), true)
				SoundLibrary.PlayLocal("levelUp", { volume = 0.55 })
				task.wait(1.1)
				if s.done then return end
				local scale = s.pods[index] and s.pods[index]:FindFirstChildOfClass("UIScale")
				if scale then
					TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 1 }):Play()
				end
			else
				s.lastPod = s.pods[index]
				s.lobby.ShowPrize(("%s %s"):format(spin.emoji or "", spin.name or "?"),
					detailText(spin), big)

				s.burst.Visible = true
				if s.pods[index] then Art.RevealPod(s.pods[index], big) end
				SoundLibrary.PlayLocal(big and "evolve" or "purchase", { volume = big and 0.70 or 0.55 })

				TweenService:Create(s.uiScale,
					TweenInfo.new(0.40, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = big and 1.08 or 1.04 }):Play()

				-- ===== THE RELIC WEDGE HANDS OVER A CHEST, AND NOW YOU OPEN IT (34.54) =====
				--
				-- Placed AFTER the pod reveal on purpose: the wheel has to finish saying what you
				-- landed on before the chest covers it, or the chest reads as having come from
				-- nowhere. `revealChest` yields until the player answers it or its fuse burns out,
				-- and it is the one thing in this loop that does -- which is safe only because a
				-- `relic` segment can never be followed by another (see its own header).
				--
				-- GATED ON `detail.relicChests`, NOT ON THE KEY. The key names the WEDGE; the detail
				-- is what the server says it actually paid, and a future wedge that also banks a
				-- chest should get the same screen without a second condition being remembered here.
				if type(spin.detail) == "table" and spin.detail.relicChests then
					task.wait(0.7)
					if s.done then return end
					revealChest(s)
				end
			end
		end
	end)

	if not ok then
		warn("[SpinReveal] sequence failed: " .. tostring(err))
		local last = spins[#spins]
		if last and not s.done and s.lobby then
			s.lobby.ShowPrize(("%s %s"):format(last.emoji or "", last.name or "?"), detailText(last), false)
		end
	end

	-- THE PRIZE IS HELD, NOT DISMISSED. The lobby stays open, so this is the one pause in the whole
	-- sequence whose job is purely to let the player read the thing they won before the countdown
	-- takes its two lines back.
	task.wait(PRIZE_HOLD)
	returnToIdle(s)
	s.playing = false
	animating = false
	if not s.done and s.lobby then s.lobby.SetBusy(false) end
	return true
end

-- ============================================================================
-- QUEUE MANAGEMENT
-- ============================================================================
--
-- Two spins can genuinely be in flight at once -- a receipt landing while a ticket spin is turning,
-- or a fast second press the throttle let through -- and each has already been PAID FOR, so neither
-- may be dropped for being inconvenient. The queue is what makes them play one after the other into
-- the same lobby.
local queue = {}
local draining = false

local function drain()
	if draining then return end
	draining = true
	task.spawn(function()
		-- `draining` MUST be cleared on every exit, and it used to be cleared on exactly one: the
		-- line after a `while` that ran unprotected. Anything that threw inside took the thread with
		-- it and left the flag true forever, so every later `SpinResult` was queued and `drain()`
		-- returned at its first line. The player kept paying and saw nothing at all.
		local ok, err = pcall(function()
			while #queue > 0 do
				-- Peek rather than pop: the payload only leaves the queue once it has been played,
				-- so a failure has nothing to put back and cannot lose one by forgetting to.
				local played = playChain(queue[1])
				table.remove(queue, 1)
				if not played then
					warn("[SpinReveal] dropped a spin payload (no PlayerGui to draw it in)")
				end
			end
		end)
		draining = false
		if not ok then warn("[SpinReveal] drain loop failed: " .. tostring(err)) end
	end)
end

-- ============================================================================
-- THE DOORS
-- ============================================================================
Remotes:WaitForChild("SpinResult").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if type(payload.spins) ~= "table" or #payload.spins == 0 then return end
	if #queue >= MAX_QUEUE then return end
	table.insert(queue, payload)
	drain()
end)

-- The server asking for the lobby: the world wheel prop, and anything else that wants the player
-- looking at this screen. `openLobby` is idempotent, so a second trigger while it is up does
-- nothing rather than stacking a second dimmed overlay.
task.spawn(function()
	local openRemote = Remotes:WaitForChild("OpenSpinLobby", 30)
	if openRemote then
		openRemote.OnClientEvent:Connect(openLobby)
	end
end)

-- The HUD's own buttons, on a BindableEvent rather than a round trip through the server -- the
-- `ClientGesture` pattern. `WheelEntry` fires this; the server never needs to hear about a panel
-- being opened, only about the free spin it should bank (`RequestSpinLobby`, fired from `openLobby`).
local openLocal = Remotes:FindFirstChild("OpenSpinLobbyLocal")
if not openLocal then
	openLocal = Instance.new("BindableEvent")
	openLocal.Name = "OpenSpinLobbyLocal"
	openLocal.Parent = Remotes
end
openLocal.Event:Connect(openLobby)

-- ===== THE RELIC MESSAGES, CAUGHT ON THEIR WAY PAST (34.54) =====
--
-- A SECOND LISTENER ON A REMOTE MainUI ALREADY OWNS, and that is deliberate rather than a shortcut:
-- `Notify` is a RemoteEvent, every connection gets every payload, and MainUI's handler is untouched
-- -- it still draws the toast and plays the rarity-pitched sting. This one only remembers, and only
-- while a chest is actually open on the screen.
--
-- `capturingRelics` IS THE WHOLE GUARD. Without it this table would fill with every relic the player
-- ever got -- a forge press, the grotto chest, a diamond buy -- and the next wheel chest would
-- announce a relic won ten minutes earlier. It is set immediately before the remote is fired and
-- cleared on every exit from `revealChest`, including the failure ones.
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(payload)
	if not capturingRelics then return end
	if type(payload) ~= "table" or payload.kind ~= "relic" then return end
	-- A merge fires the same kind and is not a chest opening. It cannot happen inside the capture
	-- window (the forge panel is behind the wheel's own scrim) but the field is free to check.
	if payload.merged then return end
	table.insert(relicNotices, payload)
end)

Remotes:WaitForChild("DataUpdate").OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	latestData = data
	-- NOT WHILE A SPIN IS TURNING: the payout push lands the instant the server rolls, which is five
	-- seconds before the wheel stops, and repainting the balance then would show the prize arriving
	-- before the pointer got to it. `returnToIdle` reads the same status when the spin is over.
	if shell and not shell.done and shell.lobby and not animating then
		local tickets, remaining, ready = spinStatus()
		shell.lobby.SetStatus(tickets, remaining, ready)
	end
end)

-- The fuse of last resort. Nothing in `playChain` can run longer than one chain of spins, but a
-- thread killed between setting `animating` and clearing it would leave the SPIN button reading
-- "SPINNING" for the rest of the session -- and unlike the old shell, there is no auto-close to
-- clean it up, because the lobby is meant to stay open.
task.spawn(function()
	local since = nil
	while true do
		task.wait(2)
		if animating then
			since = since or os.clock()
			if os.clock() - since > SPIN_WATCHDOG then
				warn("[SpinReveal] a spin never finished; releasing the wheel")
				animating = false
				if shell and not shell.done and shell.lobby then
					shell.playing = false
					shell.lobby.SetBusy(false)
				end
				since = nil
			end
		else
			since = nil
		end
	end
end)
