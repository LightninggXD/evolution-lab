-- TradePanel -- the whole of player-to-player trading on the client: the invite pop-in, the
-- partner picker, the two-sided offer board, the confirm countdown and the four remotes behind
-- them (Phase 8.6).
--
-- WHY THIS IS ITS OWN FILE (18.9)
-- ------------------------------
-- It was 968 lines at the bottom of `MainUI`, and it was ALREADY a closed
-- `;(function() ... end)()` block -- written that way because that file sits on Luau's 200-local
-- ceiling and one more top-level local deletes the entire HUD. That wrapper is what makes this
-- extraction safe: a closure that escapes nothing has a knowable set of captured upvalues, and
-- for this block that set is seven names. So the move is a change of wrapper, not of code --
-- everything below the `return function(hud)` line is byte-for-byte what was in MainUI.
--
-- THE ONE THING THAT COULD NOT MOVE VERBATIM is `currentData`. MainUI REBINDS it
-- (`currentData = data`) every time the server pushes a DataUpdate, roughly every three seconds,
-- and a module cannot see another script's local being reassigned -- it would have captured the
-- value that happened to be there when this file first ran, which for a player who opens a trade
-- in their first seconds is `nil`. It reads `hud.getData()` instead, which is MainUI's own
-- closure over the live local.
--
-- WHAT `hud` IS: the HUD context table -- MainUI's `hudRefs`, the table it was already using to
-- get handles out of these closures. See the block that fills it in MainUI, and `docs/SPLIT.md`
-- for the contract every module in this folder is held to.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
-- 30.7: a collection relic is drawn from the icon library, by NAME, the same way `RelicsPanel`
-- draws it -- see the note in `makeSlotCard`.
local IconLibrary = require(RS.Modules:WaitForChild("IconLibrary"))
-- 30.7: the offer grammar, shared with `TradeService`. Both halves of a trade now describe the
-- same two kinds of line, and describing them twice is how the two halves drift apart.
local TradeItems = require(RS.Modules.TradeItems)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local player = Players.LocalPlayer

local corner, stroke = UIKit.corner, UIKit.stroke
local styleCard, themeLabel = UIKit.styleCard, UIKit.themeLabel
local PANEL_SHELL, PET_ROW_SHELL = UIKit.PANEL_SHELL, UIKit.PET_ROW_SHELL

return function(hud)
	local screenGui = hud.screenGui
	local registerPanel, panelClose, toggleOnly = hud.registerPanel, hud.panelClose, hud.toggleOnly
	local showNotification, flatText = hud.showNotification, hud.flatText

	-- `currentTradeId` MUST BE CLEARED EVERYWHERE THE TRADE ENDS, and for most of this file's life
	-- nothing noticed that it was not. It was assigned once (in the `TradeUpdate` handler) and read
	-- by nobody -- a dead write, invisible. 21.1's tag poll gave it its FIRST reader, and inherited a
	-- variable that had never had to be correct: `muted` went true on the first trade and stayed
	-- true, so the trade tag vanished for the rest of the session after a player's first trade.
	-- Measured live 2026-08-20, two clients 7 studs apart: modal closed, distance fine, heads fine,
	-- no tag on either side, and it never came back. See ROADMAP 21.1.
	local currentTradeId = nil
	local currentSession = nil
	-- 30.7: a list of TYPED LINES -- `{kind="pet", id=...}` or `{kind="relic", key=..., n=...}` --
	-- where it used to be a list of pet id strings. It is what goes on the wire, unchanged, so the
	-- shape here and the shape the server parses are one decision in one file (`TradeItems`).
	local myOffer = {}
	-- Which half of the inventory the picker is showing. Pets, because that is what trading was
	-- for two phases and what a returning player expects to see when the window opens.
	local invTab = "pets"
	local countdownActive = false

	-- Index of a line in `myOffer`, by identity rather than by position: the server re-orders
	-- nothing, but a line is removed by what it IS, and two relic lines differ only by key.
	local function offerIndexOf(item)
		local key = TradeItems.Key(item)
		for i, held in ipairs(myOffer) do
			if TradeItems.Key(held) == key then return i end
		end
		return nil
	end

	local function sendOffer()
		local offerRemote = Remotes:FindFirstChild("TradeSetOffer")
		if offerRemote then offerRemote:FireServer(myOffer) end
	end

	-- 1. TRADE INVITE PROMPT (HUD Pop-in)
	local inviteFrame = Instance.new("Frame")
	inviteFrame.Name = "TradeInvitePrompt"
	inviteFrame.Size = UDim2.new(0, 360, 0, 90)
	inviteFrame.Position = UDim2.new(0.5, -180, 0, 80)
	inviteFrame.BackgroundTransparency = 1
	inviteFrame.Visible = false
	inviteFrame.ZIndex = 50
	inviteFrame.Parent = screenGui

	local inviteCard = UITheme.Card(inviteFrame, {
		size = UDim2.new(1, 0, 1, 0),
		color = UITheme.Color.PanelWhite,
		border = UITheme.Color.Gold,
		padding = 10,
		zIndex = 50,
	})

	local inviteLabel = Instance.new("TextLabel")
	inviteLabel.Name = "InviteText"
	inviteLabel.Size = UDim2.new(1, 0, 0, 26)
	inviteLabel.Position = UDim2.new(0, 0, 0, 0)
	inviteLabel.BackgroundTransparency = 1
	inviteLabel.Text = "🤝 Trade Request"
	inviteLabel.ZIndex = 51
	inviteLabel.Parent = inviteCard
	-- through themeLabel, like every other readable string in this file. It was authored at a fixed
	-- TextSize of 16 (and its subtitle at 13) -- the one thing the helper exists to prevent.
	themeLabel(inviteLabel, 22, UITheme.Color.Outline)

	local inviteSub = Instance.new("TextLabel")
	inviteSub.Name = "InviteSub"
	inviteSub.Size = UDim2.new(1, 0, 0, 18)
	inviteSub.Position = UDim2.new(0, 0, 0, 24)
	inviteSub.BackgroundTransparency = 1
	inviteSub.Text = "Player wants to trade with you"
	inviteSub.ZIndex = 51
	inviteSub.Parent = inviteCard
	themeLabel(inviteSub, 17, UITheme.Color.Grey)

	local acceptBtn = UITheme.Button(inviteCard, {
		text = "Accept",
		color = UITheme.Color.Green,
		size = UDim2.new(0, 120, 0, 30),
		position = UDim2.new(0.5, -130, 1, -34),
		fontSize = 14,
		zIndex = 52,
	})

	local declineBtn = UITheme.Button(inviteCard, {
		text = "Decline",
		color = UITheme.Color.Red,
		size = UDim2.new(0, 120, 0, 30),
		position = UDim2.new(0.5, 10, 1, -34),
		fontSize = 14,
		zIndex = 52,
	})

	local inviteTimer = 0
	local pendingTradeId = nil

	acceptBtn.Activated:Connect(function()
		inviteFrame.Visible = false
		if pendingTradeId then
			local acceptRemote = Remotes:FindFirstChild("TradeAccept")
			if acceptRemote then
				acceptRemote:FireServer(pendingTradeId)
			end
			pendingTradeId = nil
		end
	end)

	declineBtn.Activated:Connect(function()
		inviteFrame.Visible = false
		pendingTradeId = nil
	end)

	-- Spawned + WaitForChild -- see the OpenGroupRewards connect for the full reason. This one is the
	-- worst of the three to lose: an invite that never arrives looks exactly like a friend who never
	-- sent one, so the failure is indistinguishable from normal play and nobody would ever report it.
	task.spawn(function()
		local tradeInviteRemote = Remotes:WaitForChild("TradeInvite", 30)
		if not tradeInviteRemote then return end
		tradeInviteRemote.OnClientEvent:Connect(function(payload)
			if not payload or not payload.tradeId then return end
			pendingTradeId = payload.tradeId
			inviteSub.Text = ("%s wants to trade with you"):format(payload.fromName or "Player")
			inviteFrame.Visible = true
			inviteTimer = os.clock()
			task.delay(15, function()
				if inviteFrame.Visible and os.clock() - inviteTimer >= 14.5 then
					inviteFrame.Visible = false
					pendingTradeId = nil
				end
			end)
		end)
	end)

	-- 2. MAIN TRADE MODAL
	local tradeModal = Instance.new("Frame")
	tradeModal.Name = "TradeModal"
	tradeModal.Size = UDim2.new(0, 680, 0, 520)
	tradeModal.Visible = false
	tradeModal.ZIndex = 40
	tradeModal.Parent = screenGui
	-- A panel is not a panel until it has been through styleCard: this one shipped with no shell at
	-- all, which is Roblox's default grey rectangle with square corners and no border, behind a
	-- header and two columns that were all styled correctly. Same line every other panel in the file
	-- uses, and it is what gives registerPanel below a UIStroke to put the cyan rim on.
	styleCard(tradeModal, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(tradeModal)
	panelClose(tradeModal)

	local header, topY = UITheme.PanelHeader(tradeModal, {
		title = "🤝 Secure Trading",
		subtitle = "Trade pets and spare relics safely with other players (Anti-scam verified)",
		accent = UITheme.Color.PanelBlue,
		maxTextSize = 26,
		margin = 16,
		top = 12,
	})

	-- Left Column: My Offer
	local leftCol = Instance.new("Frame")
	leftCol.Name = "MyOfferCol"
	leftCol.Size = UDim2.new(0.5, -22, 0, 200)
	leftCol.Position = UDim2.new(0, 16, 0, topY)
	leftCol.BackgroundTransparency = 1
	leftCol.ZIndex = 41
	leftCol.Parent = tradeModal

	local leftCard = UITheme.Card(leftCol, {
		size = UDim2.new(1, 0, 1, 0),
		color = UITheme.Color.PanelWhite,
		border = UITheme.Color.Locked,
		padding = 8,
		zIndex = 41,
	})

	local myHeader = Instance.new("TextLabel")
	myHeader.Size = UDim2.new(1, 0, 0, 22)
	myHeader.BackgroundTransparency = 1
	myHeader.Text = "You (Your Offer)"
	myHeader.ZIndex = 42
	myHeader.Parent = leftCard
	-- EVERY STRING IN THIS PANEL GOES THROUGH themeLabel. It was authored against the pre-redesign
	-- HUD -- fixed 11-15px TextSizes, no outline, dark navy tiles -- and then parented to a white
	-- panel, so it was both unreadable and from a different game. The helper is the whole style.
	themeLabel(myHeader, 20, UITheme.Color.Gold)

	local myStatus = Instance.new("TextLabel")
	myStatus.Size = UDim2.new(1, 0, 0, 18)
	myStatus.Position = UDim2.new(0, 0, 0, 22)
	myStatus.BackgroundTransparency = 1
	myStatus.Text = "⏳ Deciding..."
	myStatus.ZIndex = 42
	myStatus.Parent = leftCard
	themeLabel(myStatus, 16, UITheme.Color.Grey)

	local mySlotsGrid = Instance.new("Frame")
	mySlotsGrid.Name = "MySlots"
	mySlotsGrid.Size = UDim2.new(1, 0, 1, -44)
	mySlotsGrid.Position = UDim2.new(0, 0, 0, 44)
	mySlotsGrid.BackgroundTransparency = 1
	mySlotsGrid.ZIndex = 42
	mySlotsGrid.Parent = leftCard

	local myGridLayout = Instance.new("UIGridLayout")
	myGridLayout.CellSize = UDim2.new(0, 56, 0, 64)
	myGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	myGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	myGridLayout.Parent = mySlotsGrid

	-- Right Column: Partner Offer
	local rightCol = Instance.new("Frame")
	rightCol.Name = "PartnerOfferCol"
	rightCol.Size = UDim2.new(0.5, -22, 0, 200)
	rightCol.Position = UDim2.new(0.5, 6, 0, topY)
	rightCol.BackgroundTransparency = 1
	rightCol.ZIndex = 41
	rightCol.Parent = tradeModal

	local rightCard = UITheme.Card(rightCol, {
		size = UDim2.new(1, 0, 1, 0),
		color = UITheme.Color.PanelWhite,
		border = UITheme.Color.Locked,
		padding = 8,
		zIndex = 41,
	})

	local partnerHeader = Instance.new("TextLabel")
	partnerHeader.Size = UDim2.new(1, 0, 0, 22)
	partnerHeader.BackgroundTransparency = 1
	partnerHeader.Text = "Partner's Offer"
	partnerHeader.ZIndex = 42
	partnerHeader.Parent = rightCard
	themeLabel(partnerHeader, 20, UITheme.Color.Blue)

	local partnerStatus = Instance.new("TextLabel")
	partnerStatus.Size = UDim2.new(1, 0, 0, 18)
	partnerStatus.Position = UDim2.new(0, 0, 0, 22)
	partnerStatus.BackgroundTransparency = 1
	partnerStatus.Text = "⏳ Deciding..."
	partnerStatus.ZIndex = 42
	partnerStatus.Parent = rightCard
	themeLabel(partnerStatus, 16, UITheme.Color.Grey)

	local partnerSlotsGrid = Instance.new("Frame")
	partnerSlotsGrid.Name = "PartnerSlots"
	partnerSlotsGrid.Size = UDim2.new(1, 0, 1, -44)
	partnerSlotsGrid.Position = UDim2.new(0, 0, 0, 44)
	partnerSlotsGrid.BackgroundTransparency = 1
	partnerSlotsGrid.ZIndex = 42
	partnerSlotsGrid.Parent = rightCard

	local partnerGridLayout = Instance.new("UIGridLayout")
	partnerGridLayout.CellSize = UDim2.new(0, 56, 0, 64)
	partnerGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	partnerGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	partnerGridLayout.Parent = partnerSlotsGrid

	-- Middle Section: My Inventory Picker
	local invLabel = Instance.new("TextLabel")
	-- narrower since 30.7: the two picker tabs stand at the right-hand end of this row
	invLabel.Size = UDim2.new(1, -252, 0, 20)
	invLabel.Position = UDim2.new(0, 16, 0, topY + 208)
	invLabel.BackgroundTransparency = 1
	invLabel.Text = "Your Pet Inventory (Click to offer/remove):"
	invLabel.TextXAlignment = Enum.TextXAlignment.Left
	invLabel.ZIndex = 41
	invLabel.Parent = tradeModal
	themeLabel(invLabel, 18, UITheme.Color.Outline)

	local invScroll = Instance.new("ScrollingFrame")
	invScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	invScroll.ScrollBarThickness = 12
	invScroll.Name = "InvPickerScroll"
	invScroll.Size = UDim2.new(1, -32, 0, 110)
	invScroll.Position = UDim2.new(0, 16, 0, topY + 232)
	-- a light inset, not a hole. rgb(15,18,26) at half transparency was a navy well cut into a
	-- white panel; PET_ROW_SHELL is the colour the Pets panel already uses for exactly this job.
	invScroll.BackgroundTransparency = 0
	invScroll.BackgroundColor3 = PET_ROW_SHELL
	invScroll.BorderSizePixel = 0
	invScroll.ZIndex = 42
	invScroll.ScrollBarThickness = 12
	invScroll.ScrollBarImageColor3 = UITheme.Color.Locked
	invScroll.Parent = tradeModal

	local invCorner = Instance.new("UICorner")
	invCorner.CornerRadius = UDim.new(0, 8)
	invCorner.Parent = invScroll

	local invGrid = Instance.new("UIGridLayout")
	invGrid.CellSize = UDim2.new(0, 64, 0, 84)
	invGrid.CellPadding = UDim2.new(0, 6, 0, 6)
	invGrid.Parent = invScroll

	local invPadding = Instance.new("UIPadding")
	invPadding.PaddingLeft = UDim.new(0, 6)
	invPadding.PaddingTop = UDim.new(0, 6)
	invPadding.PaddingRight = UDim.new(0, 6)
	invPadding.PaddingBottom = UDim.new(0, 6)
	invPadding.Parent = invScroll

	-- Bottom Action Bar
	local cancelTradeBtn = UITheme.Button(tradeModal, {
		text = "❌ Cancel Trade",
		color = UITheme.Color.Red,
		size = UDim2.new(0, 200, 0, 42),
		position = UDim2.new(0, 16, 1, -56),
		fontSize = 15,
		zIndex = 43,
	})

	local confirmTradeBtn = UITheme.Button(tradeModal, {
		text = "✅ Confirm Trade",
		color = UITheme.Color.Green,
		size = UDim2.new(0, 240, 0, 42),
		position = UDim2.new(1, -256, 1, -56),
		fontSize = 15,
		zIndex = 43,
	})

	local countdownBanner = Instance.new("TextLabel")
	countdownBanner.Name = "CountdownBanner"
	countdownBanner.Size = UDim2.new(0, 300, 0, 30)
	countdownBanner.Position = UDim2.new(0.5, -150, 1, -50)
	countdownBanner.BackgroundTransparency = 1
	countdownBanner.Text = "🔒 Locking in trade: 3..."
	countdownBanner.Visible = false
	countdownBanner.ZIndex = 44
	countdownBanner.Parent = tradeModal
	themeLabel(countdownBanner, 24, UITheme.Color.Gold)

	-- Helper to render one line of an offer, or one pickable thing in the inventory strip.
	--
	-- 30.7: IT DRAWS BOTH KINDS, off `item.kind`, and the difference is deliberately small -- a
	-- relic borrows the same tile, the same rarity border and the same name line, and adds a count
	-- badge when the line is a stack. A collection relic has no rarity in `GameConfig.GetRarity`'s
	-- table (the relic layer keeps its own ladder), so a relic paints its border with its SET'S
	-- TINT, which is the colour the Relics panel identifies it by everywhere else.
	local function makeSlotCard(pet, parent, isRemovable, onRemove)
		local tile = Instance.new("TextButton")
		tile.Size = UDim2.new(1, 0, 1, 0)
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.ZIndex = parent.ZIndex + 1
		tile.Parent = parent

		-- RARITY OFF GameConfig, NOT off the palette. `UITheme.Color[pet.rarity]` indexes the theme
		-- with "Common"/"Legendary"/... -- keys that table has never held -- so every tile in the
		-- window fell to the same grey and the rarity border said nothing. `GetRarity` is what the
		-- Pets panel, the Journal and the hatch reveal all read.
		local isRelic = (pet.kind == TradeItems.RELIC)
		local rarityColor = (isRelic and typeof(pet.tint) == "Color3")
			and pet.tint
			or GameConfig.GetRarity(pet.rarity).color
		local border = styleCard(tile, UITheme.Color.PanelWhite, UDim.new(0, 10), 3)
		border.Color = rarityColor

		-- A RELIC IS AN IMAGE, NOT A GLYPH, and this is the one that would have shipped. A
		-- collection relic's `icon` is an `IconLibrary` NAME ("relic_shard"); `IconLibrary`
		-- resolves BY EMOJI and returns nil for it, so `UITheme.IconSlot` would have laid the
		-- literal string `relic_shard` across the tile -- text that fits, in the right colour, in
		-- the right place, and completely wrong. Resolved through the fallback exactly as
		-- `RelicsPanel` does, for the reason written there: a bare `Id[icon]` gives `Image = ""`,
		-- which is a hole and not a placeholder.
		if isRelic then
			local art = Instance.new("ImageLabel")
			art.Name = "Icon"
			art.Size = UDim2.new(0, 30, 0, 30)
			art.Position = UDim2.new(0.5, 0, 0, 5)
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.BackgroundTransparency = 1
			art.Image = IconLibrary.Id[pet.icon]
				or IconLibrary.Id[GameConfig.RelicSetFallbackIcon]
				or ""
			-- `ImageColor3` MULTIPLIES, and the set art is drawn white on purpose: the zone's tint
			-- is what gives two hundred relics twenty looks out of ten uploads.
			art.ImageColor3 = (typeof(pet.tint) == "Color3") and pet.tint or Color3.new(1, 1, 1)
			art.ScaleType = Enum.ScaleType.Fit
			art.ZIndex = tile.ZIndex + UITheme.Z.Content
			art.Parent = tile
		else
			local icon = UITheme.IconSlot(tile, {
				name = "Icon", icon = pet.emoji or "🐾", maxTextSize = 30,
				size = UDim2.new(1, 0, 0, 34), position = UDim2.new(0, 0, 0, 3),
			})
			icon.ZIndex = tile.ZIndex + UITheme.Z.Content
		end

		-- THE COUNT IS ON THE CARD OR IT IS NOWHERE. A relic line is a stack, and a tile that
		-- reads "Forest Shard" whether it moves one or six is the card 8.5's summary rule exists to
		-- prevent -- the player has to be able to read what they are giving away.
		if isRelic and (pet.n or 1) > 1 then
			local count = Instance.new("TextLabel")
			count.Name = "Count"
			count.Size = UDim2.new(0, 26, 0, 16)
			count.Position = UDim2.new(1, -28, 0, 2)
			count.BackgroundTransparency = 1
			count.Text = ("x%d"):format(pet.n)
			count.ZIndex = tile.ZIndex + UITheme.Z.Content + 1
			count.Parent = tile
			themeLabel(count, 15, UITheme.Color.Gold)
		end

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -4, 0, 24)
		name.Position = UDim2.new(0, 2, 0, 36)
		name.BackgroundTransparency = 1
		-- `short` on a relic is its FORM ("Shard", "Sigil"); the zone is already said by the tint,
		-- and the full name does not fit a 56 px tile -- see the note where the server sets it.
		name.Text = pet.short or pet.name or pet.key
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = tile.ZIndex + UITheme.Z.Content
		name.Parent = tile
		themeLabel(name, 15, rarityColor)

		if isRemovable and onRemove then
			tile.Activated:Connect(function()
				onRemove(pet)
			end)
		end
		return tile
	end

	-- Render offers
	local function refreshTradeUI()
		if not currentSession then return end

		partnerHeader.Text = ("%s's Offer"):format(currentSession.partnerName or "Partner")

		-- Clear slots
		for _, c in ipairs(mySlotsGrid:GetChildren()) do
			if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
		end
		for _, c in ipairs(partnerSlotsGrid:GetChildren()) do
			if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
		end
		for _, c in ipairs(invScroll:GetChildren()) do
			if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
		end

		-- Populate My Offer. A card here is REMOVED by clicking it -- one press takes the whole
		-- line, stack and all, because a card that shed one relic per press would need a second
		-- affordance to say so and this side of the window is for reviewing, not for building.
		for _, item in ipairs(currentSession.myOffer or {}) do
			makeSlotCard(item, mySlotsGrid, not currentSession.myConfirmed, function(clicked)
				local idx = offerIndexOf(clicked)
				if idx then table.remove(myOffer, idx) end
				sendOffer()
			end)
		end

		-- Populate Partner Offer
		for _, item in ipairs(currentSession.partnerOffer or {}) do
			makeSlotCard(item, partnerSlotsGrid, false)
		end

		-- Populate the picker -- pets or spare relics, whichever tab is up.
		local data = hud.getData()
		local shown = 0
		if data and invTab == "relics" then
			invLabel.Text = "Your spare relics (click to add one, click again for another):"
			-- WALKED IN SET ORDER rather than over `data.SetRelics`, so the strip is stable
			-- between refreshes: a pairs() walk of the save would re-order itself every push and
			-- the tile under the player's finger would move while they were clicking it.
			for _, set in ipairs(GameConfig.RelicSets) do
				for _, relic in ipairs(set.relics) do
					local spare = GameConfig.GetSpareSetRelics(data, relic.key)
					if spare > 0 then
						-- The badge here is HOW MANY YOU HOLD SPARE; the badge on an offer card is
						-- how many you are giving. Same tile, two questions, and they are the two
						-- an inventory strip and a review card respectively have to answer.
						local card = {
							kind = TradeItems.RELIC,
							key = relic.key,
							n = spare,
							name = relic.name,
							rarity = relic.rarity,
							icon = relic.icon,
							tint = relic.tint,
							short = (GameConfig.RelicSetForms[relic.order] or {}).name or relic.name,
						}
						local offered = offerIndexOf(card)
						local btn = makeSlotCard(card, invScroll, true, function(clicked)
							local idx = offerIndexOf(clicked)
							if not idx then
								if #myOffer < TradeItems.MaxLines then
									table.insert(myOffer, { kind = TradeItems.RELIC, key = clicked.key, n = 1 })
								end
							elseif myOffer[idx].n < spare then
								-- one more of the same, up to what is actually spare
								myOffer[idx].n = myOffer[idx].n + 1
							else
								-- past the top of the stack the next press takes the line away, so
								-- one tile can both build and clear a line with the single input a
								-- phone has
								table.remove(myOffer, idx)
							end
							sendOffer()
						end)
						if offered then
							btn.BackgroundColor3 = Color3.fromRGB(40, 55, 75)
						end
						shown = shown + 1
					end
				end
			end
		elseif data and data.Pets then
			invLabel.Text = "Your Pet Inventory (Click to offer/remove):"
			local equippedSet = {}
			for _, eqId in ipairs(data.EquippedPetIds or {}) do equippedSet[eqId] = true end

			for _, pet in ipairs(data.Pets) do
				if not equippedSet[pet.id] then
					local def = GameConfig.GetPetDef(pet.key)
					local pObj = {
						kind = TradeItems.PET,
						id = pet.id,
						key = pet.key,
						name = def and def.name or pet.key,
						rarity = def and def.rarity or "Common",
						emoji = def and def.emoji or "🐾",
					}
					local isOffered = offerIndexOf(pObj) ~= nil
					local btn = makeSlotCard(pObj, invScroll, true, function(clicked)
						local idx = offerIndexOf(clicked)
						if idx then
							table.remove(myOffer, idx)
						elseif #myOffer < TradeItems.MaxLines then
							table.insert(myOffer, { kind = TradeItems.PET, id = clicked.id })
						end
						sendOffer()
					end)
					if isOffered then
						btn.BackgroundColor3 = Color3.fromRGB(40, 55, 75)
					end
					shown = shown + 1
				end
			end
		end
		invScroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(shown / 8) * 90 + 10)

		-- Status labels
		if currentSession.myConfirmed then
			myStatus.Text = "✅ Ready!"
			myStatus.TextColor3 = UITheme.Color.Green
		else
			myStatus.Text = "⏳ Deciding..."
			myStatus.TextColor3 = UITheme.Color.Grey
		end

		if currentSession.partnerConfirmed then
			partnerStatus.Text = "✅ Ready!"
			partnerStatus.TextColor3 = UITheme.Color.Green
		else
			partnerStatus.Text = "⏳ Deciding..."
			partnerStatus.TextColor3 = UITheme.Color.Grey
		end

		-- Countdown banner
		if currentSession.state == "countdown" then
			countdownBanner.Visible = true
			confirmTradeBtn.Visible = false
		else
			countdownBanner.Visible = false
			confirmTradeBtn.Visible = true
			if currentSession.myConfirmed then
				UITheme.SetText(confirmTradeBtn, "Waiting...")
				UITheme.SetColor(confirmTradeBtn, UITheme.Color.Locked)
			else
				UITheme.SetText(confirmTradeBtn, "✅ Confirm Trade")
				UITheme.SetColor(confirmTradeBtn, UITheme.Color.Green)
			end
		end
	end

	-- ========================================================================
	-- THE PICKER'S TWO TABS (30.7)
	-- ========================================================================
	-- Built here, below `refreshTradeUI`, and not up with the rest of the modal: a button created
	-- earlier that called `refreshTradeUI` would capture a GLOBAL of that name rather than the
	-- local declared afterwards -- the exact fault `tools/luascope.py` exists to catch, and one
	-- Luau compiles happily.
	-- `= nil` is not decoration: `tools/luanames.py` swallows a RUN of assignment-free `local`
	-- lines into one match and then binds none of them, so the `local function` under two bare
	-- forward declarations reads to it as an undefined global.
	local relicTabBtn = nil
	local petTabBtn = nil
	local function setTab(name)
		invTab = name
		UITheme.SetColor(petTabBtn, name == "pets" and UITheme.Color.Blue or UITheme.Color.Locked)
		UITheme.SetColor(relicTabBtn, name == "relics" and UITheme.Color.Blue or UITheme.Color.Locked)
		refreshTradeUI()
	end

	-- ===== 28 TALL, NOT 24, AND IT GROWS UPWARDS (33.36) =====
	--
	-- `fontSize = 14` reaches `UITheme.AutoSize(label, math.min(14, 14), 26)`, so these captions are
	-- FLOORED at 14 px -- `TextScaled` cannot take them any smaller. The button's own label child is
	-- inset 6 px top and bottom, so a 24-tall button gave it a **12 px box for 14 px of text**:
	-- measured box 90x12 against `TextBounds` 26x14 for "Pets" and 34x14 for "Relics", both with
	-- `TextFits` false. Four characters overflowing a 90 px-wide box is the giveaway that the width
	-- was never the problem.
	--
	-- 28 gives the label 16 and two pixels of slack. THE POSITION MOVES UP BY THE FOUR IT GAINS:
	-- `InvPickerScroll` starts at `topY + 232` and shares this row's right-hand edge, so growing
	-- downward would have laid both tabs over the top of the list. 202..230 keeps the bottom edge
	-- where it was and still clears the two 200-tall offer columns above at `topY`.
	petTabBtn = UITheme.Button(tradeModal, {
		text = "Pets",
		color = UITheme.Color.Blue,
		size = UDim2.new(0, 106, 0, 28),
		position = UDim2.new(1, -232, 0, topY + 202),
		fontSize = 14,
		zIndex = 43,
	})
	relicTabBtn = UITheme.Button(tradeModal, {
		text = "Relics",
		color = UITheme.Color.Locked,
		size = UDim2.new(0, 106, 0, 28),
		position = UDim2.new(1, -122, 0, topY + 202),
		fontSize = 14,
		zIndex = 43,
	})
	petTabBtn.Activated:Connect(function() setTab("pets") end)
	relicTabBtn.Activated:Connect(function() setTab("relics") end)

	-- Cancel button
	cancelTradeBtn.Activated:Connect(function()
		local cancelRemote = Remotes:FindFirstChild("TradeCancel")
		if cancelRemote then cancelRemote:FireServer() end
		tradeModal.Visible = false
		currentSession = nil
		currentTradeId = nil
		myOffer = {}
	end)

	-- Confirm button
	confirmTradeBtn.Activated:Connect(function()
		if not currentSession or currentSession.myConfirmed then return end
		local confirmRemote = Remotes:FindFirstChild("TradeConfirm")
		if confirmRemote then confirmRemote:FireServer(currentSession.tradeId) end
	end)

	-- Remote event listener for TradeUpdate. Spawned + WaitForChild -- see the OpenGroupRewards
	-- connect for the full reason. Losing this one strands a trade that has already STARTED: the
	-- modal opens off the invite, both sides put pets in, and no state ever comes back.
	task.spawn(function()
		local tradeUpdateRemote = Remotes:WaitForChild("TradeUpdate", 30)
		if not tradeUpdateRemote then return end
		tradeUpdateRemote.OnClientEvent:Connect(function(payload)
			if not payload then return end
			if payload.state == "cancelled" or payload.state == "completed" then
				tradeModal.Visible = false
				currentSession = nil
				-- the one the tag poll reads. Cleared HERE rather than only on the cancel button,
				-- because most trades do not end on this client's own button: the other side
				-- cancels, somebody walks out of range, or the trade completes.
				currentTradeId = nil
				myOffer = {}
				return
			end

			currentSession = payload
			currentTradeId = payload.tradeId

			-- Re-seeded from what the SERVER says this side is offering, never from what this
			-- client last sent. 30.7 makes that matter: `resolveOffer` clamps a relic line to the
			-- spares actually held, so a line the server shrank has to shrink here too or the next
			-- press would send the old number back and be refused.
			myOffer = {}
			for _, line in ipairs(payload.myOffer or {}) do
				if line.kind == TradeItems.RELIC then
					table.insert(myOffer, { kind = TradeItems.RELIC, key = line.key, n = line.n })
				else
					table.insert(myOffer, { kind = TradeItems.PET, id = line.id })
				end
			end

			if not tradeModal.Visible then
				toggleOnly(tradeModal)
			end
			refreshTradeUI()
		end)
	end)

	-- ========================================================================
	-- 4. THE PLAYER PICKER -- the entry point the feature never had (15.11)
	-- ========================================================================
	-- NOTHING IN THIS FILE HAS EVER FIRED `TradeRequest`. The server has listened for it since 8.6
	-- (`TradeService.Init` wires `reqRemote.OnServerEvent` straight into `TradeService.Request`),
	-- the invite prompt at the top of this block has always been able to answer one, and the modal
	-- above draws whatever a session pushes at it -- but no button anywhere in the HUD ever SENT
	-- one. So no trade could be started, and therefore no invite could ever arrive either: every
	-- part of the feature worked and the whole of it was unreachable. `grep -rn TradeRequest src/`
	-- returned exactly one line, and it was the server's.
	--
	-- This is 15.9's shape at one remove. There the client looked for a remote that did not exist
	-- yet; here the client owns the only half of the conversation nothing speaks. Neither is
	-- visible to luascope.py, luastruct.py or a Luau compile -- every name involved is in scope and
	-- correct, it is simply never called. The check that finds this class is the row's own: open
	-- the feature the way a player would.
	local pickerPanel = Instance.new("Frame")
	pickerPanel.Name = "TradePickerPanel"
	pickerPanel.Size = UDim2.new(0, 460, 0, 420)
	pickerPanel.Visible = false
	pickerPanel.ZIndex = 40
	pickerPanel.Parent = screenGui
	styleCard(pickerPanel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(pickerPanel)
	panelClose(pickerPanel)

	local _, pickerTopY = UITheme.PanelHeader(pickerPanel, {
		title = "🤝 Trade",
		subtitle = ("Walk up to a player and ask -- both of you must be within %d studs")
			:format(GameConfig.TradeProximityStuds),
		accent = UITheme.Color.PanelBlue,
		maxTextSize = 26,
		margin = 16,
		top = 12,
	})

	local pickerScroll = Instance.new("ScrollingFrame")
	pickerScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	pickerScroll.ScrollBarThickness = 12
	pickerScroll.Name = "PlayerList"
	pickerScroll.BackgroundTransparency = 1
	pickerScroll.BorderSizePixel = 0
	pickerScroll.Position = UDim2.new(0, 16, 0, pickerTopY)
	pickerScroll.Size = UDim2.new(1, -32, 1, -pickerTopY - 16)
	pickerScroll.ZIndex = pickerPanel.ZIndex + UITheme.Z.Content
	pickerScroll.ScrollBarThickness = 12
	pickerScroll.ScrollBarImageColor3 = UITheme.Color.Locked
	pickerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	pickerScroll.Parent = pickerPanel

	local pickerLayout = Instance.new("UIListLayout")
	pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickerLayout.Padding = UDim.new(0, 8)
	pickerLayout.Parent = pickerScroll

	-- Parented to the PANEL, not the scroll: inside the UIListLayout it would be laid out as a row
	-- and push the first player down. Same reason petsEmptyLabel sits where it does.
	local pickerEmpty = Instance.new("TextLabel")
	pickerEmpty.Name = "EmptyLabel"
	pickerEmpty.Size = UDim2.new(1, -60, 0, 80)
	pickerEmpty.Position = UDim2.new(0, 30, 0, pickerTopY + 50)
	pickerEmpty.BackgroundTransparency = 1
	pickerEmpty.TextWrapped = true
	pickerEmpty.Text = "Nobody else is here yet — trading needs a second player in the server."
	pickerEmpty.ZIndex = pickerPanel.ZIndex + UITheme.Z.Content
	pickerEmpty.Parent = pickerPanel
	flatText(themeLabel(pickerEmpty, 22, Color3.fromRGB(150, 154, 168)))

	local function studsTo(other)
		local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local theirs = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if not mine or not theirs then return nil end
		return (mine.Position - theirs.Position).Magnitude
	end

	-- Distance is repainted in place rather than by rebuilding the rows: players walk while the
	-- panel is open, and a list that rebuilt itself every tick would destroy the button under the
	-- cursor between the press and the release.
	local function repaintDistances()
		for _, row in ipairs(pickerScroll:GetChildren()) do
			-- THE ID IS AN ATTRIBUTE, NOT A SUBSTRING OF THE NAME (15.19). It was
			-- `row.Name:match("^Player_(%d+)$")`, with a comment arguing that an attribute "would do
			-- the same job with one more step". The one step was the job: **Studio's test players
			-- have NEGATIVE UserIds** -- Player1 is -1 and Player2 is -2 -- and `%d+` does not match
			-- a minus sign, so every row resolved to nil and the distance label read "…" forever.
			-- It would have worked in production, where ids are positive, and failed in every test
			-- anyone could run, which is the worst way round. Found on the first live two-client run.
			local uid = row:IsA("Frame") and row:GetAttribute("TradeUserId")
			local label = uid and row:FindFirstChild("Distance")
			local other = uid and Players:GetPlayerByUserId(uid)
			if label and other then
				local d = studsTo(other)
				if not d then
					label.Text = "waiting for them to spawn…"
					label.TextColor3 = UITheme.Color.Grey
				elseif d <= GameConfig.TradeProximityStuds then
					label.Text = ("%d studs away — in range"):format(math.floor(d))
					label.TextColor3 = UITheme.Color.Green
				else
					label.Text = ("%d studs away — walk closer"):format(math.floor(d))
					label.TextColor3 = UITheme.Color.Coral
				end
			end
		end
	end

	local function refreshPicker()
		for _, child in ipairs(pickerScroll:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end

		local shown = 0
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				shown += 1
				local row = Instance.new("Frame")
				-- The name is for reading in the explorer; the ATTRIBUTE is what repaintDistances
				-- resolves against, because a userId is not always a run of digits -- see the note
				-- there, and 15.19.
				row.Name = "Player_" .. other.UserId
				row:SetAttribute("TradeUserId", other.UserId)
				row.Size = UDim2.new(1, -6, 0, 62)
				row.LayoutOrder = shown
				row.ZIndex = pickerScroll.ZIndex + 1
				row.Parent = pickerScroll
				styleCard(row, UITheme.Color.PanelWhite, UDim.new(0, 12), 3)

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "PlayerName"
				nameLabel.Size = UDim2.new(1, -160, 0, 26)
				nameLabel.Position = UDim2.new(0, 12, 0, 7)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Text = "👤 " .. other.DisplayName
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.ZIndex = row.ZIndex + UITheme.Z.Content
				nameLabel.Parent = row
				themeLabel(nameLabel, 20, UITheme.Color.Outline)

				local distLabel = Instance.new("TextLabel")
				distLabel.Name = "Distance"
				distLabel.Size = UDim2.new(1, -160, 0, 20)
				distLabel.Position = UDim2.new(0, 12, 0, 34)
				distLabel.BackgroundTransparency = 1
				distLabel.Text = "…"
				distLabel.TextXAlignment = Enum.TextXAlignment.Left
				distLabel.ZIndex = row.ZIndex + UITheme.Z.Content
				distLabel.Parent = row
				-- authored Grey (mid-luminance) so themeLabel gives it the chunky dark outline;
				-- repaintDistances only ever changes the FILL, and Green/Coral sit either side of
				-- the same cut, so the outline decision stays correct for every state it takes
				themeLabel(distLabel, 16, UITheme.Color.Grey)

				local askBtn = UITheme.Button(row, {
					name = "AskBtn",
					text = "🤝 Ask",
					size = UDim2.new(0, 118, 0, 40),
					position = UDim2.new(1, -12, 0.5, 0),
					anchorPoint = Vector2.new(1, 0.5),
					color = UITheme.Color.Green,
					radius = 12,
					maxTextSize = 18,
					zIndex = row.ZIndex + UITheme.Z.Content,
				})
				-- FIRED EVEN WHEN THE ROW SAYS "walk closer". The server owns that rule and answers
				-- a refusal with its own Notify ("Stand closer to trade", "They are already in a
				-- trade", the rate limit), which is a real answer -- a button greyed out by the
				-- client's own guess at the distance would instead be a silent one, and the client
				-- measures from a character that may not have replicated yet.
				askBtn.MouseButton1Click:Connect(function()
					local reqRemote = Remotes:FindFirstChild("TradeRequest")
					if not reqRemote then
						showNotification("❌ Trading is not available here", Color3.fromRGB(200, 60, 60), 2)
						return
					end
					reqRemote:FireServer(other.UserId)
				end)
			end
		end

		pickerEmpty.Visible = shown == 0
		pickerScroll.CanvasSize = UDim2.new(0, 0, 0, shown * 70)
		repaintDistances()
	end

	-- ========================================================================
	-- 5. THE DOOR IS THE OTHER PLAYER (16.2)
	-- ========================================================================
	-- The HUD tile that used to open the picker is gone. Trading is the one feature in this game
	-- that is ABOUT a specific person, and a permanent button on the screen edge asked the player to
	-- go and find that person's name in a list while they were already looking straight at them.
	--
	-- So: click anybody in the world and a small card opens over the click with their headshot, their
	-- display name, how far away they are, and one green Trade button. The picker panel is still here
	-- and still correct -- it is the answer to "who else is even in this server" and it survives a
	-- crowd better than aiming at a moving avatar on a phone -- so the card carries a second, quieter
	-- button into it. Both markets do it one way each (Adopt Me clicks the player, Pet Simulator 99
	-- uses a list); this ships both, with the click as the front door.
	--
	-- CLIENT RAYCAST, NOT A ClickDetector PER CHARACTER. A ClickDetector means one instance per
	-- player, added on every CharacterAdded, and a server round trip just to draw a card that only
	-- one client will ever see. The raycast costs nothing and is not a security question: the client
	-- decides what to DRAW, and the server re-checks identity, distance, rate limit and trade state
	-- when TradeRequest actually arrives (TradeService.Request) exactly as it did before.
	local UIS = game:GetService("UserInputService")

	local card = Instance.new("Frame")
	card.Name = "PlayerCard"
	card.Size = UDim2.new(0, 250, 0, 184)
	-- Bottom-centre anchored, so the card grows UPWARD out of the point that was clicked and its
	-- lower edge stays pinned just above the avatar rather than covering them.
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0, 0, 0, 0)
	card.Visible = false
	-- Over every panel: this opens from a click in the WORLD, so it must not be able to appear
	-- underneath a menu that happened to be open when the player clicked past it.
	card.ZIndex = 60
	card.Parent = screenGui
	styleCard(card, PANEL_SHELL, UDim.new(0, 18), 5)

	-- Its own UIScale rather than registerPanel's: registerPanel exists to FIT panels bigger than a
	-- phone screen, and this one is 250 wide -- it fits everywhere. All that is wanted here is the pop.
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	local cardTarget = nil

	-- The headshot, and the fallback that is not an accident. `GetUserThumbnailAsync` cannot resolve
	-- a NEGATIVE userId, and every Studio test player has one (Player1 is -1) -- the same trap that
	-- cost LeaderboardService a permanently re-queued fetch. So the emoji is drawn FIRST and the
	-- image is layered over it only once a real URL comes back; a failure leaves a deliberate-looking
	-- avatar disc instead of an empty hole, in Studio and for a deleted account alike.
	local face = Instance.new("TextLabel")
	face.Name = "Face"
	face.Size = UDim2.new(0, 56, 0, 56)
	face.Position = UDim2.new(0, 14, 0, 14)
	face.BackgroundColor3 = UITheme.Color.PanelBlue
	face.Text = "\u{1F464}"
	face.ZIndex = card.ZIndex + UITheme.Z.Content
	face.Parent = card
	corner(face, UDim.new(0.5, 0))
	stroke(face, 3, UITheme.Color.Outline)
	themeLabel(face, 28)

	local faceImage = Instance.new("ImageLabel")
	faceImage.Name = "FaceImage"
	faceImage.Size = UDim2.new(1, 0, 1, 0)
	faceImage.BackgroundTransparency = 1
	faceImage.Image = ""
	faceImage.Visible = false
	faceImage.ZIndex = face.ZIndex + 1
	faceImage.Parent = face
	corner(faceImage, UDim.new(0.5, 0))

	local cardName = Instance.new("TextLabel")
	cardName.Name = "CardName"
	cardName.Size = UDim2.new(1, -92, 0, 26)
	cardName.Position = UDim2.new(0, 80, 0, 16)
	cardName.BackgroundTransparency = 1
	cardName.TextXAlignment = Enum.TextXAlignment.Left
	cardName.TextTruncate = Enum.TextTruncate.AtEnd
	cardName.Text = ""
	cardName.ZIndex = card.ZIndex + UITheme.Z.Content
	cardName.Parent = card
	themeLabel(cardName, 21, UITheme.Color.Outline)

	local cardDist = Instance.new("TextLabel")
	cardDist.Name = "CardDistance"
	cardDist.Size = UDim2.new(1, -92, 0, 20)
	cardDist.Position = UDim2.new(0, 80, 0, 44)
	cardDist.BackgroundTransparency = 1
	cardDist.TextXAlignment = Enum.TextXAlignment.Left
	cardDist.Text = ""
	cardDist.ZIndex = card.ZIndex + UITheme.Z.Content
	cardDist.Parent = card
	-- authored Grey so themeLabel gives it the chunky dark outline; only the FILL is repainted below,
	-- and Green/Coral sit the same side of themeLabel's luminance cut, so that decision stays right
	themeLabel(cardDist, 15, UITheme.Color.Grey)

	local cardTradeBtn = UITheme.Button(card, {
		name = "CardTrade",
		text = "\u{1F91D} Trade",
		size = UDim2.new(1, -28, 0, 44),
		position = UDim2.new(0, 14, 0, 84),
		color = UITheme.Color.Green,
		radius = 14,
		maxTextSize = 22,
		zIndex = card.ZIndex + UITheme.Z.Content,
	})

	local cardListBtn = UITheme.Button(card, {
		name = "CardList",
		text = "\u{1F4CB} Everyone in server",
		size = UDim2.new(1, -28, 0, 32),
		position = UDim2.new(0, 14, 0, 136),
		color = UITheme.Color.PanelBlue,
		radius = 12,
		maxTextSize = 16,
		zIndex = card.ZIndex + UITheme.Z.Content,
	})

	local function hideCard()
		cardTarget = nil
		card.Visible = false
	end

	-- Repaints the one line that changes while the card is open. Same three states and the same
	-- wording as the picker's rows, deliberately: a player who has seen one should not have to learn
	-- the other.
	local function repaintCard()
		if not cardTarget then return end
		local d = studsTo(cardTarget)
		if not d then
			cardDist.Text = "waiting for them to spawn\u{2026}"
			cardDist.TextColor3 = UITheme.Color.Grey
		elseif d <= GameConfig.TradeProximityStuds then
			cardDist.Text = ("%d studs away \u{2014} in range"):format(math.floor(d))
			cardDist.TextColor3 = UITheme.Color.Green
		else
			cardDist.Text = ("%d studs away \u{2014} walk closer"):format(math.floor(d))
			cardDist.TextColor3 = UITheme.Color.Coral
		end
	end

	local function showCard(other, px, py)
		cardTarget = other
		cardName.Text = other.DisplayName
		repaintCard()

		faceImage.Visible = false
		faceImage.Image = ""
		-- Spawned and pcall'd: this yields on a web request, and a card that waited for it would open
		-- a beat after the click on a good connection and not at all on a bad one. `cardTarget` is
		-- re-checked on the way back so a slow fetch cannot paint player A's face onto player B's card.
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(other.UserId,
					Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and url and cardTarget == other then
				faceImage.Image = url
				faceImage.Visible = true
			end
		end)

		-- CLAMPED INTO THE VIEWPORT, both axes. Clicking somebody standing at the edge of the screen
		-- is the normal case, not the corner case, and half a card hanging off the side is the sort of
		-- thing that reads as broken rather than as tight.
		--
		-- The GUI inset is subtracted because input positions are measured from the top of the WINDOW
		-- while this ScreenGui's offsets are measured from under Roblox's topbar. Mixing the two is
		-- how an element lands exactly one inset out of place -- see the note on the potion strip.
		local inset = game:GetService("GuiService"):GetGuiInset()
		local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local x = math.clamp(px, 135, math.max(v.X - 135, 135))
		local y = math.clamp(py - inset.Y - 14, 194, math.max(v.Y - inset.Y - 10, 194))
		card.Position = UDim2.new(0, x, 0, y)

		card.Visible = true
		cardScale.Scale = 0.82
		TweenService:Create(cardScale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	local function playerUnder(pos)
		local cam = workspace.CurrentCamera
		if not cam then return nil end
		local ray = cam:ViewportPointToRay(pos.X, pos.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		-- your own body only. Everything else stays in, INCLUDING the world: a click that lands on a
		-- wall in front of somebody must not reach through it and open their card.
		params.FilterDescendantsInstances = { player.Character }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 800, params)
		if not hit or not hit.Instance then return nil end
		-- Walk UP through ancestors rather than testing the hit part's immediate parent: accessories,
		-- tools and the costume models StageCostume dresses a character in are all extra Model layers
		-- between a hat and the character, and a player wearing one would otherwise be unclickable.
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		while model do
			local other = Players:GetPlayerFromCharacter(model)
			if other and other ~= player then return other end
			model = model:FindFirstAncestorOfClass("Model")
		end
		return nil
	end

	UIS.InputBegan:Connect(function(input, gameProcessed)
		-- `gameProcessed` is what keeps this from firing behind the card's own buttons, behind every
		-- panel in the game, and behind the chat bar. It is not defensive padding: without it, clicking
		-- the Trade button would immediately re-run this handler, find no player under the cursor, and
		-- close the card underneath the press.
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local other = playerUnder(input.Position)
		if other then
			showCard(other, input.Position.X, input.Position.Y)
		elseif card.Visible then
			-- a click anywhere in the world that is not a player is the close gesture; there is no X in
			-- the corner because on a phone "tap away" is the one dismissal everybody already knows
			hideCard()
		end
	end)

	cardTradeBtn.MouseButton1Click:Connect(function()
		local other = cardTarget
		hideCard()
		if not other then return end
		local reqRemote = Remotes:FindFirstChild("TradeRequest")
		if not reqRemote then
			showNotification("\u{274C} Trading is not available here", Color3.fromRGB(200, 60, 60), 2)
			return
		end
		-- Fired even when the line above says "walk closer", for the reason spelled out on the picker's
		-- Ask button: the server owns that rule and answers a refusal with a real message, where a
		-- button greyed out by the client's own guess at the distance would refuse silently.
		reqRemote:FireServer(other.UserId)
	end)

	cardListBtn.MouseButton1Click:Connect(function()
		hideCard()
		refreshPicker()
		toggleOnly(pickerPanel)
	end)

	-- The card is about somebody who is standing there. Three ways that stops being true, and all
	-- three close it rather than leaving a card describing a player who has walked off or left.
	Players.PlayerRemoving:Connect(function(leaving)
		if cardTarget == leaving then hideCard() end
	end)

	task.spawn(function()
		while true do
			task.wait(0.35)
			if card.Visible and cardTarget then
				if cardTarget.Parent ~= Players then
					hideCard()
				else
					local d = studsTo(cardTarget)
					-- 120 studs: far enough that it never closes on somebody you are walking toward,
					-- close enough that a card cannot survive a zone teleport
					if d and d > 120 then
						hideCard()
					else
						repaintCard()
					end
				end
			end
		end
	end)

	Players.PlayerAdded:Connect(function()
		if pickerPanel.Visible then refreshPicker() end
	end)
	Players.PlayerRemoving:Connect(function()
		if pickerPanel.Visible then task.defer(refreshPicker) end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			if pickerPanel.Visible then
				repaintDistances()
			end
		end
	end)
	-- ========================================================================
	-- 6. THE PROMPT OVER A NEARBY PLAYER (21.1)
	-- ========================================================================
	-- 16.2 put the door on the person and it was the right move -- but a door nobody can SEE is the
	-- state 21.1 opened against: "trading is fully built and invisible", seven live remotes and
	-- 1,011 lines of client behind a gesture the game never mentions. Clicking another player is not
	-- something Roblox teaches, and nothing on this screen implies it does anything.
	--
	-- So the affordance is drawn where the door already is: a small `Trade` tag over the head of any
	-- other player inside `GameConfig.TradeProximityStuds`, which is the SERVER's own range rule
	-- (`TradeService` reads the same constant), so a tag can never appear over somebody the server
	-- would then refuse. Tapping the tag opens the same card the click opens -- it is one more way
	-- in, not a second implementation.
	--
	-- WHY A TAG AND NOT A HUD TILE, which is the other half of what 21.1 asked for. The tile existed
	-- and 16.2 deleted it on the owner's own reasoning: trading means nothing until somebody is
	-- standing next to you, and a permanent button spent a fifth of the left edge asking the player
	-- to find a name in a list while they were looking straight at the person. Putting it back would
	-- undo a closed row, break the left column's 2x2 block, and cost a register in a file that has
	-- none (MainUI is at Luau's 200-local ceiling). The tag answers the actual complaint -- nothing
	-- tells you the feature is there -- at the only moment it is true, and it carries the picker in
	-- behind it through the card's second button. See the note in ROADMAP 21.1.
	--
	-- NOT AlwaysOnTop, on purpose, and it is the same rule the raycast above follows: a tag that
	-- shines through a wall advertises a trade with somebody you cannot reach. `MaxDistance` is belt
	-- and braces on top of the range test -- it culls the tag at the engine level on a frame the
	-- poll has not caught up with yet.
	local prompts = {}          -- [Player] = BillboardGui
	local taughtThisSession = false

	-- WHERE THE TAG SITS. THE FIRST VERSION PUT IT INSIDE THE PLAYER'S OWN BODY.
	--
	-- It shipped as `ExtentsOffsetWorldSpace = (0, 1.8, 0)`, written and reviewed as "1.8 head
	-- heights above the head" -- measured off the body so it would hold across the twenty stages.
	-- It does hold across the stages, and it was never 1.8 head heights:
	--
	--     `ExtentsOffset` IS MEASURED IN THE ADORNEE'S HALF-SIZE, NOT ITS SIZE.
	--
	-- Measured on the live client at stage 20, three billboards side by side on the same Head: one
	-- at `ExtentsOffsetWorldSpace = 2.0` rendered at exactly the height of one at
	-- `StudsOffset = head.Size.Y`, and far below one at `StudsOffset = head.Size.Y * 2`. So the
	-- shipped tag sat at 0.9 x the head's height, half of what the number reads as.
	--
	-- That put it under the one thing already over every head: `CombatClient`'s `HealthPlate`, the
	-- player's name plus their bar when they are hurt, on the Head of every player, `AlwaysOnTop`,
	-- 52 px tall, anchored at `head.Size.Y * 1.35 + 1.6`. That anchor is where the COSTUME ends --
	-- the 1.35 clears the shell and the +1.6 clears the crowns and horns the late stages wear, and
	-- the comment there records what it cost to find. The tag sat
	--
	--     0.9H - (1.35H + 1.6)  =  -0.45H - 1.6
	--
	-- below it, which is negative at every stage and grows worse as the body does: 2.6 studs under
	-- the costume line at Cell, 4.7 at Alien, and 6.8 at The Absolute (measured: anchor 10.36 vs
	-- the plate's 17.13). Inside the silhouette, on a tag that is deliberately NOT `AlwaysOnTop`,
	-- which means the body itself occludes it. The affordance built so trading would stop being
	-- invisible was being swallowed by the player it was pointing at.
	--
	-- AND IT COULD NOT HAVE BEEN FIXED BY A BIGGER NUMBER, because the two are measured in
	-- different units. The plate is anchored in studs and sized in PIXELS -- that is its own fix
	-- for "the bar is over my head" -- so the number of studs it covers GROWS as the camera pulls
	-- back, and `CameraFit` alone moves that from 12.5 studs at stage 1 to 46 at stage 20 before
	-- the other player's own 40 studs of range are added. Any constant stud offset slides through
	-- it at some distance.
	--
	-- So the tag is stacked on the plate IN THE PLATE'S OWN SPACE: same anchor, then pushed clear
	-- in pixels by `SizeOffset`, which is measured in multiples of the tag's own size and therefore
	-- holds the same gap at every distance and every stage. Both numbers are READ OFF THE PLATE
	-- rather than copied from it -- the anchor formula and the 52 belong to `CombatClient`, and this
	-- must not become a second place that has to be edited when they move. The literal fallback is
	-- only for the frames before `attachHealthPlate`'s `WaitForChild` has returned.
	local function alignPrompt(gui, head)
		local plate = head:FindFirstChild("HealthPlate")
		local anchor = plate and plate.StudsOffset or Vector3.new(0, head.Size.Y * 1.35 + 1.6, 0)
		if gui.StudsOffset ~= anchor then
			gui.StudsOffset = anchor
		end
		-- How far the plate reaches ABOVE that anchor, in pixels: its own pixel height times the
		-- fraction of itself that its `SizeOffset` pushed up, plus the half it would otherwise be
		-- centred on. 6 px of air, so the two read as a stack rather than as one block.
		local top = plate and plate.Size.Y.Offset * (plate.SizeOffset.Y + 0.5) or 52
		local h = gui.Size.Y.Offset
		local want = Vector2.new(0, (top + 6 + h / 2) / h)
		if gui.SizeOffset ~= want then
			gui.SizeOffset = want
		end
	end

	local function dropPrompt(other)
		local gui = prompts[other]
		if gui then
			prompts[other] = nil
			gui:Destroy()
		end
	end

	local function makePrompt(other, head)
		local gui = Instance.new("BillboardGui")
		gui.Name = "TradePrompt"
		gui.Adornee = head
		gui.Size = UDim2.fromOffset(132, 40)
		-- Set before it is parented, so the tag is never drawn for one frame at the head's own
		-- origin. See `alignPrompt` above for why this is not an offset of its own.
		alignPrompt(gui, head)
		gui.AlwaysOnTop = false
		gui.MaxDistance = GameConfig.TradeProximityStuds + 6
		gui.ResetOnSpawn = false
		gui.Parent = screenGui

		local btn = Instance.new("TextButton")
		btn.Name = "Tag"
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundColor3 = UITheme.Color.Green
		btn.AutoButtonColor = true
		btn.Text = "\u{1F91D} Trade"
		btn.Font = Enum.Font.FredokaOne
		btn.TextSize = 20
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Parent = gui
		corner(btn, UDim.new(0.5, 0))
		stroke(btn, 3, UITheme.Color.Outline)

		btn.MouseButton1Click:Connect(function()
			-- The card is positioned from a SCREEN point, the same space an input position arrives
			-- in -- `WorldToScreenPoint` includes the topbar inset and `WorldToViewportPoint` does
			-- not, and `showCard` subtracts the inset itself. Mixing those two is how an element
			-- lands exactly one inset out of place.
			local cam = workspace.CurrentCamera
			local px, py = 0, 0
			if cam then
				local pt = cam:WorldToScreenPoint(head.Position)
				px, py = pt.X, pt.Y
			end
			showCard(other, px, py)
		end)

		prompts[other] = gui
		return gui
	end

	Players.PlayerRemoving:Connect(dropPrompt)

	task.spawn(function()
		while true do
			task.wait(0.4)
			-- Every prompt goes away while a trade is actually open. The modal is the conversation;
			-- a row of tags floating behind it invites a second one the server would refuse anyway.
			local muted = tradeModal.Visible or currentTradeId ~= nil
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player then
					local head = other.Character and other.Character:FindFirstChild("Head")
					local d = studsTo(other)
					local want = (not muted) and head and d and d <= GameConfig.TradeProximityStuds
					local gui = prompts[other]
					if want then
						if not gui then
							makePrompt(other, head)
							-- ONE toast, the first time it is ever true in a session, and never
							-- again. The tag teaches the gesture on its own once it is on screen;
							-- what it cannot do is catch the eye of somebody looking at their own
							-- HUD. After that this would be a banner about a thing already visible.
							if not taughtThisSession then
								taughtThisSession = true
								showNotification(
									("\u{1F91D} %s is nearby \u{2014} tap the tag above them to trade")
										:format(other.DisplayName),
									UITheme.Color.Green, 4)
							end
						else
							if gui.Adornee ~= head then
								-- they respawned, or StageCostume rebuilt the body: re-adorn rather
								-- than leaving a tag pinned to a Head no longer in the character
								gui.Adornee = head
							end
							-- Re-aligned every pass, not only on re-adorn: an evolve grows the head
							-- and moves the plate underneath a tag whose Adornee never changed.
							-- Both writes are guarded on the value, so a still player costs nothing.
							alignPrompt(gui, head)
						end
					elseif gui then
						dropPrompt(other)
					end
				end
			end
		end
	end)
end

