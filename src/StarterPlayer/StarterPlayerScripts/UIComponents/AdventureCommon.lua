-- UIComponents/AdventureCommon -- the four adventure screens' shared vocabulary (30.6).
--
-- =====================================================================================
-- WHY THIS EXISTS AT ALL, GIVEN THE RULE IS "SEVERAL SMALL MODULES"
-- =====================================================================================
-- 30.6 draws FOUR things -- the route list, the pet picker, the away list and the run capsule --
-- and three of them need the same five answers: which pet is chosen, what a pet is called, what a
-- duration reads as, what a refusal's one-word tag is, and how a footer button is drawn. Three
-- private copies of "the chosen pet" in particular is not a style question: the picker sets it and
-- the route list reads it, so a copy each means pressing CHOOSE changes nothing on the screen that
-- sent you there.
--
-- Nothing here draws a panel and nothing here talks to the server.
--
-- =====================================================================================
-- THE CHOSEN PET IS CLIENT STATE, AND IT IS ALLOWED TO BE
-- =====================================================================================
-- The server never remembers which pet you were looking at -- `HandleEnter` and `Send` both take a
-- `petId` on the call and re-derive everything from it. So a selection that is wrong (fused,
-- traded, sent out while the panel was open) costs a refusal and nothing else, which is why this
-- is a client-side `local` rather than a save field.
--
-- IT IS RE-VALIDATED ON EVERY READ rather than on every push. `Resolve` is what every screen calls,
-- and it drops a selection whose pet has left the save or gone away and falls back to the strongest
-- pet that is still here. That fallback is deliberate: with no pet chosen EVERY route on the list
-- refuses with `nopet`, and a player opening the board for the first time would read twenty
-- greyed-out rows and conclude the feature is locked. `nopet` is still reachable -- a save with no
-- pets, or every pet away -- which is the state it actually describes.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)

local AdventureCommon = {}

-- ===== THE PALETTE =====
-- Written out rather than imported from `UITheme`, the same decision `ScrollingPanelBuilder` makes
-- and for the same reason: these four screens are drawn by that builder, which deliberately does
-- not depend on the kit, and a footer button that took its gradient from UITheme while the card
-- buttons beside it took theirs from the builder would be two looks on one panel.
local INK = Color3.fromRGB(0, 0, 50)
local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)

AdventureCommon.Color = {
	Go      = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) },
	Send    = { Color3.fromRGB(140, 200, 255), Color3.fromRGB(40, 120, 235) },
	Claim   = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) },
	Diamond = { Color3.fromRGB(190, 160, 255), Color3.fromRGB(120, 70, 220) },
	Leave   = { Color3.fromRGB(255, 138, 148), Color3.fromRGB(214, 40, 56) },
	Neutral = { Color3.fromRGB(210, 212, 232), Color3.fromRGB(152, 156, 186) },
	-- The builder's own `DISABLED` pair, written out for the same reason as the rest. A refused
	-- button is greyed and STILL PRESSABLE here -- see `AdventurePanel` for why.
	Off     = { Color3.fromRGB(178, 178, 190), Color3.fromRGB(128, 128, 142) },
}

-- A card's background out of the route's zone accent. `zone.accentColor` is a WORLD colour and
-- terrain is allowed to be near-black -- handed straight to a card it makes a list of twenty
-- near-black bars. This is `ZonePanel`'s `pastel`, quoted rather than re-derived.
function AdventureCommon.Pastel(c)
	return { c:Lerp(WHITE, 0.52), c:Lerp(WHITE, 0.74) }
end

-- ===== TIME =====
--
-- THREE FORMATS, AND THE SPLIT IS NOT COSMETIC. A course is scored in seconds and tenths ("1:20.4"
-- is a time you beat by a tenth); a par is authored as a whole number of seconds, so printing one
-- with a tenth would read as more precision than the target has; a dispatch is eight to twenty
-- minutes and tenths on one are noise.
function AdventureCommon.Clock(seconds)
	seconds = math.max(seconds or 0, 0)
	return ("%d:%02d"):format(seconds // 60, math.floor(seconds % 60))
end

function AdventureCommon.ClockTenths(seconds)
	seconds = math.max(seconds or 0, 0)
	return ("%d:%04.1f"):format(seconds // 60, seconds % 60)
end

-- "4m 12s" -- the dispatch's own unit. `AdventureDispatch`'s `clock` prints the same shape
-- server-side for the "still exploring" refusal, so the countdown and that toast agree.
function AdventureCommon.Countdown(seconds)
	seconds = math.max(math.floor((seconds or 0) + 0.5), 0)
	return ("%dm %02ds"):format(seconds // 60, seconds % 60)
end

-- ===== PETS =====
function AdventureCommon.PetDef(pet)
	return pet and GameConfig.GetPetDef(pet.key) or nil
end

-- Emoji AND name, because the picker is a list of rows whose art column is collapsed (see
-- `AdventurePetPicker`) so the glyph is the only picture a row gets. A pet with no definition
-- still prints its key rather than an empty row: that is a save carrying a pet from a build where
-- the key existed, and a blank line is what makes it look like the panel is broken instead.
function AdventureCommon.PetName(pet)
	if not pet then return "no pet" end
	local def = AdventureCommon.PetDef(pet)
	if not def then return tostring(pet.key) end
	local text = ((def.emoji or "") .. " " .. (def.name or pet.key))
	return (text:gsub("^%s+", ""))
end

-- ===== THE CHOSEN PET =====
local selectedId = nil
local petListeners = {}

local function announce()
	for _, fn in ipairs(petListeners) do
		local ok, err = pcall(fn, selectedId)
		if not ok then warn("[AdventureCommon] pet listener failed: " .. tostring(err)) end
	end
end

function AdventureCommon.OnPetChanged(fn)
	petListeners[#petListeners + 1] = fn
end

function AdventureCommon.SetPetId(id)
	if selectedId == id then return end
	selectedId = id
	announce()
end

function AdventureCommon.GetPetId()
	return selectedId
end

--- The chosen pet as a TABLE, re-validated against this push of the save, with the fallback
--- described in the header. Returns nil only when the player genuinely has nobody to send.
--- Never cache what this returns: `data` is replaced wholesale on every DataUpdate, so a pet table
--- held from one push is a different object from the one in the next.
function AdventureCommon.Resolve(data)
	if not data then return nil end

	local pet = GameConfig.GetPetById(data, selectedId)
	if pet and not GameConfig.IsPetAway(data, pet.id) then return pet end

	-- The old selection is gone or is out on a route. Fall back, and WRITE THE FALLBACK BACK, so
	-- every screen agrees about what is chosen -- a fallback computed fresh on each read would let
	-- the picker's tick and the route list's caption disagree the moment the ordering changed.
	local ranked = GameConfig.SortedPetsByPower(data.Pets, data)
	for _, candidate in ipairs(ranked) do
		if not GameConfig.IsPetAway(data, candidate.id) then
			AdventureCommon.SetPetId(candidate.id)
			return candidate
		end
	end

	-- Nobody. The id is KEPT rather than cleared: the pet is most likely simply away, and clearing
	-- it would silently re-pick somebody else the moment it comes home.
	return nil
end

-- ===== WHAT A REFUSAL SAYS ON A BUTTON =====
--
-- The SENTENCE is `GameConfig.GetAdventureRefusal` and is never rewritten here -- 30.6 moved those
-- five strings out of two services precisely so there would be one copy of each. What this adds is
-- the other half of the same problem: a card button is ~160 px wide and cannot hold "That is both
-- adventures for today -- come back tomorrow!", so it needs a TAG, and a tag invented per screen
-- would be three vocabularies for one set of states.
--
-- `nil` for anything that is not a refusal, so a caller can write `Tag(reason) or "PLAY"`.
local TAGS = {
	nopet  = "NO PET",
	away   = "AWAY",
	power  = "TOO WEAK",
	slots  = "NO SLOT",
	capped = "USED UP",
	none   = "CLOSED",
}

function AdventureCommon.Tag(reason)
	return TAGS[reason]
end

-- ===== A BUTTON THAT IS NOT ON A CARD =====
--
-- The builder draws buttons INSIDE its cards and nowhere else. All three panels here need one or
-- two in a footer as well, and hand-rolling the gradient / corner / border / ink stack three times
-- is how two of them end up looking like a different game. Same four layers in the same order as
-- the builder's own card button.
--
-- Returns the button AND a setter for its gradient, because every one of these has a refused state
-- and reaching back into a child called "UIGradient" from three files is the fragile way to do it.
function AdventureCommon.Button(parent, opts)
	local btn = Instance.new("TextButton")
	btn.Name = opts.name or "Button"
	btn.Size = opts.size or UDim2.new(0, 200, 0, 44)
	btn.Position = opts.position or UDim2.new(0, 0, 0, 0)
	btn.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	btn.BackgroundColor3 = WHITE
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = opts.textSize or 24
	btn.TextColor3 = WHITE
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	btn.Text = opts.text or ""
	btn.ZIndex = opts.zIndex or 56
	btn.Parent = parent

	local grad = Instance.new("UIGradient")
	local colors = opts.colors or AdventureCommon.Color.Neutral
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(1, colors[2]),
	})
	grad.Parent = btn

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, opts.radius or 6)
	corner.Parent = btn

	local border = Instance.new("UIStroke")
	border.Color = INK
	border.Thickness = 3
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = btn

	local ink = Instance.new("UIStroke")
	ink.Color = BLACK
	ink.Thickness = 2
	ink.Parent = btn

	local function setColors(next)
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, next[1]),
			ColorSequenceKeypoint.new(1, next[2]),
		})
	end

	return btn, setColors
end

-- A plain outlined line of text, for the footers and the capsule. White on a black stroke, because
-- every one of these sits either on a pastel board or on a dark capsule and neither can be assumed
-- -- which is the exact fault `roblox-gui-probe-blind-spots` records as dark text in its own dark
-- halo, invisible to every property probe.
function AdventureCommon.Line(parent, opts)
	local l = Instance.new("TextLabel")
	l.Name = opts.name or "Line"
	l.BackgroundTransparency = 1
	l.Size = opts.size or UDim2.new(1, 0, 0, 22)
	l.Position = opts.position or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	l.Font = Enum.Font.FredokaOne
	l.TextSize = opts.textSize or 20
	l.TextColor3 = opts.color or WHITE
	l.TextXAlignment = opts.xAlign or Enum.TextXAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = opts.text or ""
	l.ZIndex = opts.zIndex or 55
	l.Parent = parent

	local ink = Instance.new("UIStroke")
	ink.Color = BLACK
	ink.Thickness = opts.strokeThickness or 3
	ink.Parent = l

	return l
end

-- ===== THE FOUR SCREENS FIND EACH OTHER THROUGH HERE =====
--
-- The route list opens the picker, the picker comes back to the route list, the footer opens the
-- away list, and the run capsule has to shut all three. Requiring each other directly would be a
-- cycle in three of the four directions, so each screen REGISTERS itself under a name at Init and
-- asks for the others by name. A name with nothing behind it is a no-op rather than an error --
-- which is what makes the capsule safe to build before the panels are.
local screens = {}

function AdventureCommon.Register(name, api)
	screens[name] = api
end

function AdventureCommon.Open(name)
	local api = screens[name]
	if api and api.SetOpen then api.SetOpen(true) end
end

function AdventureCommon.CloseAll()
	for _, api in pairs(screens) do
		if api.SetOpen then api.SetOpen(false) end
	end
end

--- Every OPEN screen redrawn. Hidden ones are skipped on the builder's own rule -- refreshing a
--- panel nobody is looking at is the cost this game already has twenty of.
function AdventureCommon.RefreshAll()
	for _, api in pairs(screens) do
		if api.Refresh and api.IsOpen and api.IsOpen() then api.Refresh() end
	end
end

return AdventureCommon
