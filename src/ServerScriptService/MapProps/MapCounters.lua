-- MapProps/MapCounters -- putting a working door on the map's shop, upgrades, potion and spin props.
--
-- The owner's list, with a screenshot for each: *"ovaj shop isto napravi funkcionalnim ... i ove
-- upgrades i top 3 igraca ... ovde ce biti potions ... ovaj wheel treba napraviti da radi"*. The
-- podium and the boards are `MapBoards`; these four are the ones a player walks up to and presses.
--
-- ===== NOTHING NEW IS INVENTED HERE, AND THAT IS THE DESIGN =====
-- Every door in this game is already a `ProximityPrompt` carrying an ATTRIBUTE, and the client's one
-- `PromptTriggered` handler in `MainUI` reads that attribute and opens the panel. So three of the
-- four are a prompt and an attribute -- no remote, no client change, no panel written. The fourth,
-- the wheel, has no attribute route because the free spin was never a world object at all: it lives
-- on a HUD tile and fires `ClaimFreeSpin`. It is wired server-side to the SAME
-- `RewardService.HandleFreeSpin` that tile calls, so the prop and the tile cannot drift apart or
-- both pay out.
--
-- ===== WHERE THIS SITS IN THE BOOT, WHICH IS NOT NEGOTIABLE =====
--   ForestMapService.Init()   the map is placed and MapAnchors publishes it
--   MapCounters.Init()        <- here
--   PotionService.Init()      scans workspace.Zones for the `MysteryCost` attribute
-- The potion pad is a `MysteryCost` prompt and PotionService FINDS ITS COUNTERS BY SCANNING, once,
-- at its own Init. Run this after that scan and the pad is a prompt that does nothing, with no error
-- anywhere -- the same shape as the doors 30.17 found searching for ground that was not there yet.
--
-- ===== TWO THINGS MEASURED OFF THE MAP =====
-- The pads are 21 x 1 x 21 and 26 x 1 x 26 before the 1.45, so ~30 and ~38 studs across. A prompt on
-- a pad you STAND ON wants a reach about the pad's own half-width, not the game's 42-stud
-- `PROMPT_REACH`, or two adjacent pads both offer themselves in the middle of the square. And the
-- prompt goes on a PART, never on the Model: a `ProximityPrompt` parented to a Model never shows.

local MapAnchors = require(script.Parent.MapAnchors)

local MapCounters = {}

-- Reach, in studs, from the pad's centre. Generous enough to catch a player standing on the far
-- corner of a 38-stud pad, tight enough that the shop and the upgrades pads do not overlap -- they
-- are 100 studs apart in the placed map.
local PAD_REACH = 34

-- One row per counter. `panel` is the `ShopPanel` attribute the client's handler dispatches on; the
-- wheel has none because it is wired here instead. The pads' own BillboardGui captions are NEVER
-- rewritten -- the map already says Shop, Upgrades and Potions in its own lettering, and our text
-- lives on the prompt where a player is already looking when she presses it.
local COUNTERS = {
	{
		role = "shop", panel = "robux",
		action = "Open", object = "\u{1F6D2} Shop",
		-- "robux" is the Robux store, which is what a village Shop building sells in this game: the
		-- eggs have their own row on the north edge and their own prompts (see EggPlaza), and the
		-- pets panel is a HUD tile. Handled ahead of the panel table in MainUI's dispatch, so it
		-- opens the store rather than a panel instance.
	},
	{
		role = "upgrades", panel = "mastery",
		action = "Open", object = "\u{2B06}\u{FE0F} Upgrades",
	},
}

local function findPart(anchor)
	if not anchor then return nil end
	local inst = anchor.inst
	if inst:IsA("BasePart") then return inst end
	-- The largest part in the prop, because a pad's Model holds a plinth, a sign post and a glow and
	-- a prompt on the glow is a prompt you have to stand inside a particle to see.
	local best
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and (not best or d.Size.Magnitude > best.Size.Magnitude) then
			best = d
		end
	end
	return best
end

local function addPrompt(part, name, action, object, attrs)
	if not part then return nil end
	local existing = part:FindFirstChild(name)
	if existing then existing:Destroy() end   -- idempotent: a second Init must not stack two prompts
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PAD_REACH
	prompt.RequiresLineOfSight = false   -- the pad's own sign stands between you and its centre
	for k, v in pairs(attrs or {}) do
		prompt:SetAttribute(k, v)
	end
	prompt.Parent = part
	return prompt
end

function MapCounters.Init(zoneKey)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end
	local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)

	local made = {}

	for _, counter in ipairs(COUNTERS) do
		local part = findPart(MapAnchors.Get(zoneKey, counter.role))
		if addPrompt(part, "MapPrompt_" .. counter.role, counter.action, counter.object,
			{ ShopPanel = counter.panel }) then
			made[#made + 1] = counter.role
		end
	end

	-- ===== THE POTION PAD =====
	-- Forest had no mystery counter at all: `GameConfig.ZoneShops` starts at zone 3, so zone 1 has
	-- never sold a potion. The pad is the owner's *"ovde ce biti potions"*, and the cost comes from
	-- the same `GetMysteryCost` every other zone's dispenser uses -- derived from that zone's second
	-- egg, so zone 1's is the cheapest in the game by construction rather than by a number typed
	-- here. `PotionService` picks this up by attribute scan; see the boot-order note in the header.
	local potionPart = findPart(MapAnchors.Get(zoneKey, "potions"))
	local cost = GameConfig.GetMysteryCost(zoneKey)
	-- `cost .. " DNA"` and nothing cleverer, because that is exactly what every other zone's
	-- dispenser prompt says (ZoneBuilder's `addPrompt` call) and two shops in one game that write
	-- the same price two ways is the kind of seam a player notices and a test never does.
	if addPrompt(potionPart, "MapPrompt_potions", "Buy Mystery Potion", cost .. " DNA",
		{ MysteryCost = cost }) then
		made[#made + 1] = "potions(" .. tostring(cost) .. ")"
	end

	-- ===== THE WHEEL =====
	-- No attribute route: the daily spin has never been a world object, only a HUD tile firing
	-- `ClaimFreeSpin`. Wired straight to the handler that remote calls, so the prop and the tile are
	-- one feature -- HandleFreeSpin owns the readiness check, the timestamp and the payout, and a
	-- second copy of any of those is a second daily spin.
	--
	-- THE PROMPT SAYS "OPEN" NOW (34.46), and the wording is the feature: this used to spin the wheel
	-- where the player stood, and it now banks the day's free spin and opens the lobby, where the
	-- prizes, the countdown and the spin balance are all on screen before anything turns. A prompt
	-- reading "Spin" over a door that opens a panel is the kind of half-truth a player only ever
	-- notices by being disappointed by it.
	--
	-- REQUIRED INSIDE THE CALLBACK, not at the top of this file. `RewardService.Init` runs well after
	-- this one and requiring it at module scope would pull a half-built service into the boot order
	-- for no reason; by the time anyone can press a prompt, everything is up.
	local wheelPart = findPart(MapAnchors.Get(zoneKey, "wheel"))
	local wheelPrompt = addPrompt(wheelPart, "MapPrompt_wheel", "Open", "\u{1F3A1} Lucky Wheel")
	if wheelPrompt then
		wheelPrompt.Triggered:Connect(function(player)
			local RewardService = require(script.Parent.Parent.RewardService)
			RewardService.HandleFreeSpin(player)
		end)
		made[#made + 1] = "wheel"
	end

	print(("[MapCounters] %s: %d counters wired (%s)")
		:format(zoneKey, #made, table.concat(made, ", ")))
	return #made
end

return MapCounters
