--[[
	SpinLobby -- the controls around the lucky wheel (34.46).

	THE WHEEL USED TO BE A CUTSCENE. A press somewhere else in the HUD charged the player, the screen
	dimmed, the wheel appeared already turning, it paid out and it closed. The owner's note on it, on
	a capture of the reference: *"ovo treba da izgleda kad se otvori spin, znaci ne odma da vrti, vec
	da ima opcija da se spina, da pokaze koliko player ima spinova i opcija da kupi"* -- opening the
	wheel must show you the wheel, not start it.

	So this file is everything that is NOT the wheel: the close button, the free-spin countdown, the
	spin balance, the SPIN button, and the four packs that top it up. `SpinWheelArt` draws the wheel
	itself and `SpinReveal.client.lua` owns the shell both of them live in.

	THE TWO STATUS LINES ARE FOUR LABELS IN TWO SLOTS, and that is the whole layout trick here. Idle,
	they read "Next free spin in: 04:12:37" and "Spins : 3"; while a spin plays they are the prize
	name and its detail. One pair is visible at a time in exactly the same two positions, so the
	panel never grows, never reflows, and the eye that was reading the balance is already looking at
	where the prize is about to be announced.
--]]

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local CardKit = require(RS.Modules.HUD.CardKit)

local WHITE = Color3.fromRGB(255, 255, 255)
local CREAM = Color3.fromRGB(255, 240, 205)
local GOLD = Color3.fromRGB(255, 226, 120)

-- The row is authored in PIXELS, like every other button in this game's HUD, and then scaled down
-- as one piece if the viewport cannot hold it. Four packs and a spin button is 844 px of controls;
-- a phone in portrait is ~640 px wide, so without this the two outer packs would sit off-screen.
local PACK_W, PACK_H = 152, 62
local SPIN_W, SPIN_H = 236, 72
local ROW_PAD = 12
local ROW_W = PACK_W * 4 + SPIN_W + ROW_PAD * 4

local SpinLobby = {}

-- "04:12:37". Hours-minutes-seconds rather than the HUD's usual "4h 12m", because this one is read
-- while you are deciding whether to wait for it -- and a countdown you are watching has to visibly
-- move. The daily boundary means the hours field never passes 23, so two digits is always enough.
local function clock(seconds)
	seconds = math.max(math.floor(seconds or 0), 0)
	return ("%02d:%02d:%02d"):format(seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

local function statusLabel(parent, name, y, textSize, color)
	local l = CardKit.Text(parent, {
		name = name,
		text = "",
		size = UDim2.new(1, -40, 0, textSize + 12),
		position = UDim2.fromScale(0.5, y),
		textSize = textSize,
		color = color,
		xAlign = "Center",
		zIndex = 22,
		strokeThickness = 4,
		truncate = false,
	})
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	return l
end

-- One pack tile. TWO LABELS, NOT ONE STRING: the amount and the price are different sizes and
-- different colours because they answer different questions, and a single "+20 Spins  R$699" line
-- makes the buyer read a price before they have decided they want the thing.
local function packTile(parent, pack, amount, product, order, onBuy)
	local _, handle = CardKit.Button(parent, {
		name = "Pack_" .. tostring(pack.productKey),
		text = "",
		size = UDim2.new(0, PACK_W, 0, PACK_H),
		layoutOrder = order,
		radius = 12,
		zIndex = 22,
		colors = { pack.color, pack.color:Lerp(Color3.new(0, 0, 0), 0.32) },
		callback = function() onBuy(pack.productKey) end,
	})

	CardKit.Text(handle.Instance, {
		name = "Amount",
		text = ("\u{1F3A1} +%d Spins"):format(amount),
		size = UDim2.new(1, -10, 0, 24),
		position = UDim2.new(0, 5, 0, 8),
		textSize = 19,
		xAlign = "Center",
		zIndex = 23,
		truncate = false,
	})

	CardKit.Text(handle.Instance, {
		name = "Price",
		text = ("R$ %d"):format(product.price or 0),
		size = UDim2.new(1, -10, 0, 20),
		position = UDim2.new(0, 5, 0, 33),
		textSize = 15,
		color = CREAM,
		xAlign = "Center",
		zIndex = 23,
		truncate = false,
	})

	return handle
end

-- `gui` is the shell's ScreenGui and `stage` is the wheel's own square frame. Almost everything here
-- goes on the GUI rather than inside the stage, because the stage is a RelativeYY square and the
-- control row is wider than it is -- the ONE exception is the close button, which belongs to the
-- wheel and has to travel with it (see its own note).
--
-- `callbacks.onSpin`, `.onBuy(productKey)` and `.onClose` are the only things this file asks the
-- world for. It never touches a remote itself: the shell owns the remotes, this owns the pixels.
function SpinLobby.Build(gui, stage, callbacks)
	local root = Instance.new("Frame")
	root.Name = "Lobby"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = 20
	root.Parent = gui

	-- ===== THE TWO SLOTS =====
	--
	-- THE PLATE IS NOT DECORATION. These two lines sit exactly where the HUD keeps its damage stat
	-- and its evolve bar, and the shell's scrim is a flat wash over the whole screen -- it dims those
	-- but cannot delete them, so a stroked bright-yellow "Damage 4.13K" was still legible straight
	-- through "Spins : 0". Deepening the scrim until it was gone would have blacked out the world as
	-- well. A local darkening under the text costs one frame, is invisible against the dim it sits
	-- on, and only removes the pixels this panel actually needs.
	local plate = Instance.new("Frame")
	plate.Name = "StatusPlate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.825)
	plate.Size = UDim2.new(0, 560, 0, 104)
	plate.BackgroundColor3 = Color3.fromRGB(10, 8, 22)
	plate.BackgroundTransparency = 0.28
	plate.BorderSizePixel = 0
	plate.ZIndex = 21
	plate.Parent = root
	CardKit.Corner(plate, 22)
	-- Faded at both ends rather than edged: a hard rectangle here would read as a panel the wheel is
	-- standing on, and there is no panel -- only a patch of extra dark.
	local plateFade = Instance.new("UIGradient")
	plateFade.Rotation = 0
	plateFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 0),
		NumberSequenceKeypoint.new(0.78, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	plateFade.Parent = plate

	local timerLine = statusLabel(root, "FreeSpinTimer", 0.795, 26, CREAM)
	local balanceLine = statusLabel(root, "SpinBalance", 0.855, 32, WHITE)
	local prizeLine = statusLabel(root, "PrizeName", 0.795, 34, WHITE)
	local prizeDetail = statusLabel(root, "PrizeDetail", 0.855, 22, CREAM)
	prizeLine.Visible = false
	prizeDetail.Visible = false

	-- ===== THE CONTROL ROW =====
	local row = Instance.new("Frame")
	row.Name = "Controls"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.930)
	row.Size = UDim2.new(0, ROW_W, 0, SPIN_H)
	row.BackgroundTransparency = 1
	row.ZIndex = 21
	row.Parent = root

	local rowScale = Instance.new("UIScale")
	rowScale.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ROW_PAD)
	layout.Parent = row

	-- The packs are split around the SPIN button -- gold and green on the left, blue and red on the
	-- right -- so the thing the player came to press sits in the middle of the row and the upsells
	-- are reached by moving away from it. `GetSpinPackAmount` returns nil for a product row that is
	-- missing or delisted, and those draw NO tile: a shop button that cannot be pressed teaches a
	-- player the shop is broken.
	--
	-- A ROW WITH `productId = 0` STILL DRAWS, and that is not the same case. Delisted means "this is
	-- not for sale"; zero means "the id has not been pasted in yet", and `PromptRobuxPurchase`
	-- already answers that with "This item isn't set up yet -- check back soon!". Hiding it would
	-- hide the fact that it is waiting on the dashboard, which is exactly what the owner needs to
	-- see. Every real id must be in `RobuxProducts` before this ships.
	local packHandles = {}
	local order = 0
	for i, pack in ipairs(GameConfig.SpinPacks or {}) do
		if i == 3 then order = 10 end   -- the SPIN button takes LayoutOrder 5
		local amount, product = GameConfig.GetSpinPackAmount(pack)
		if amount then
			order += 1
			packHandles[#packHandles + 1] = packTile(row, pack, amount, product, order, callbacks.onBuy)
		end
	end

	local _, spinHandle = CardKit.Button(row, {
		name = "Spin",
		text = "SPIN",
		size = UDim2.new(0, SPIN_W, 0, SPIN_H),
		layoutOrder = 5,
		textSize = 38,
		radius = 14,
		zIndex = 22,
		colors = { Color3.fromRGB(112, 216, 96), Color3.fromRGB(46, 156, 60) },
		callback = function() callbacks.onSpin() end,
	})

	-- ===== THE CLOSE BUTTON =====
	--
	-- PARENTED TO THE STAGE, not to the screen, and that is the whole reason `stage` is an argument.
	-- Placed as a fraction of the viewport it drifted away from the wheel as the window got wider --
	-- measured at 1576 px it sat 130 px clear of the bezel, floating in dimmed scenery with nothing
	-- to belong to. On the stage it is a point just outside the rim at 45 degrees, so it is in the
	-- same place at every aspect ratio, and it rides the open/win scale tweens with the wheel.
	local closeBtn = CardKit.Button(stage, {
		name = "Close",
		text = "\u{2716}",
		size = UDim2.new(0, 58, 0, 58),
		position = UDim2.fromScale(0.955, 0.065),
		anchorPoint = Vector2.new(0.5, 0.5),
		textSize = 30,
		radius = 14,
		zIndex = 24,
		colors = { Color3.fromRGB(255, 108, 118), Color3.fromRGB(214, 44, 58) },
		callback = function() callbacks.onClose() end,
	})

	-- ===== FITTING THE ROW =====
	-- Recomputed on resize rather than once at build: a Roblox client can change viewport mid-session
	-- (a phone rotating, a window dragged), and a row measured only at open would then hang off the
	-- side for the rest of the session.
	local function fit()
		local w = gui.AbsoluteSize.X
		if w <= 0 then return end
		rowScale.Scale = math.min(1, (w * 0.94) / ROW_W)
	end
	fit()
	local fitConn = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local lobby = { Instance = root, CloseButton = closeBtn }
	local busy = false
	local tickets = 0
	local freeSeconds = 0
	local freeReady = false

	local function paintSpinButton()
		if busy then
			spinHandle.SetText("SPINNING")
			spinHandle.SetEnabled(false)
		elseif tickets > 0 then
			spinHandle.SetText("SPIN")
			spinHandle.SetEnabled(true)
		else
			-- ENABLED WITH NOTHING TO SPEND, deliberately. `SetEnabled(false)` would make the press do
			-- nothing at all, and a player with no spins pressing a dead button learns only that the
			-- game ignored them. The press goes through, the server answers "you have no spins left --
			-- wait for the free one or grab a pack", and that sentence is the one that sells a pack.
			spinHandle.SetText("SPIN")
			spinHandle.SetEnabled(true, { Color3.fromRGB(150, 154, 172), Color3.fromRGB(96, 100, 120) })
		end
	end

	-- Called on every DataUpdate and once at open. Cheap on purpose: four string writes, and the
	-- countdown is the only one of them that changes between pushes.
	function lobby.SetStatus(spinTickets, secondsToFree, isReady)
		tickets = math.max(math.floor(spinTickets or 0), 0)
		freeSeconds = secondsToFree or 0
		freeReady = isReady and true or false

		if freeReady then
			-- Only reachable in the gap between opening the lobby and the server's push landing:
			-- opening BANKS the free spin, so the steady state is a countdown and a balance that
			-- already contains it.
			timerLine.Text = "Free spin ready!"
			timerLine.TextColor3 = GOLD
		else
			timerLine.Text = "Next free spin in: " .. clock(freeSeconds)
			timerLine.TextColor3 = CREAM
		end
		balanceLine.Text = ("Spins : %d"):format(tickets)
		paintSpinButton()
	end

	-- One second off the countdown, without waiting for a push. Driven by the shell's tick.
	function lobby.Tick()
		if freeReady then return end
		freeSeconds = math.max(freeSeconds - 1, 0)
		timerLine.Text = "Next free spin in: " .. clock(freeSeconds)
	end

	-- The four-labels-in-two-slots swap. A nil name puts the idle pair back.
	function lobby.ShowPrize(name, detail, big)
		local showing = name ~= nil
		timerLine.Visible = not showing
		balanceLine.Visible = not showing
		prizeLine.Visible = showing
		prizeDetail.Visible = showing
		if showing then
			prizeLine.Text = name
			prizeLine.TextColor3 = big and GOLD or WHITE
			prizeDetail.Text = detail or ""
		end
	end

	function lobby.SetBusy(on)
		busy = on and true or false
		paintSpinButton()
		-- THE CLOSE BUTTON STAYS LIVE while the wheel turns. A player who wants out mid-animation has
		-- already been paid -- the server granted before the client drew a frame -- so trapping them
		-- for five seconds protects nothing, and is exactly the feeling this rewrite exists to remove.
		for _, h in ipairs(packHandles) do
			h.SetEnabled(not busy)
		end
	end

	function lobby.Destroy()
		if fitConn.Connected then fitConn:Disconnect() end
		-- Two roots, because the close button lives on the stage: destroying `root` alone would leave
		-- an X floating over the wheel for as long as the shell's fade-out lasts.
		closeBtn:Destroy()
		root:Destroy()
	end

	paintSpinButton()
	return lobby
end

return SpinLobby
