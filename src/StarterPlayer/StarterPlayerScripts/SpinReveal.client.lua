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
	if d.relicChests then
		table.insert(bits, ("%d Relic Chest -- open it in the Forge"):format(d.relicChests))
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
