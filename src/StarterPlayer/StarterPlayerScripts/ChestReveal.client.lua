-- ChestReveal -- the word that floats out of the chest in the grotto (34.53).
--
-- ===== WHY THIS EXISTS AT ALL, GIVEN THE SERVER ALREADY ANIMATES THE PROP =====
--
-- `ChestService` opens the lid, fires the burst and flashes the light, and every one of those is
-- server-made and therefore seen by EVERYONE in the room -- which is right, because the chest is
-- shared geometry and two players can be standing at it.
--
-- What cannot be server-made is the TEXT. "Sealed - 12m 04s" is one player's cooldown, and a
-- BillboardGui parented in the world is drawn on every screen; the training dummy's nameplate
-- carries the same note one prop over, and it is why that plate says something static. So the
-- per-player half of the feedback comes down a remote and is built here, on the one client it
-- is about.
--
-- ===== AND IT IS DRAWN AT THE CHEST, NOT IN THE MIDDLE OF THE SCREEN =====
--
-- [[evolution-lab-feedback-placement]]: no screen-centre banners, draw it where it happened. The
-- server sends a world POSITION -- the top of the chest's measured box -- and this floats a word up
-- out of it and fades it. The relic itself is NOT named here: `RelicService` already fires its own
-- `relic` notification, which MainUI turns into the big card for a first Legendary or Mythic and a
-- toast for everything else, pitched by rarity. Two writers naming the same prize is how one of them
-- ends up wrong.
--
-- NOTHING IS TRUSTED OFF THE WIRE except by type. The payload is server-authored, but this script
-- type-checks every field anyway and draws nothing at all if one is the wrong shape -- a client
-- script that indexes a malformed payload is a client script that stops running for the session.
--
-- (LINE COMMENTS, NOT A `--[[` BLOCK, and that is not a style choice: a memory reference written
-- `[[like-this]]` inside a block comment CLOSES it at the first `]]`, and the rest of the header
-- then compiles as code. `luastruct.py` caught it here on the first run.)

local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Modules = RS:WaitForChild("Modules")
local UITheme = require(Modules:WaitForChild("UITheme"))
local SoundLibrary = require(Modules:WaitForChild("SoundLibrary"))

local Remotes = RS:WaitForChild("Remotes")
local ChestFx = Remotes:WaitForChild("ChestFx")

-- How far the word climbs and how long it lives. Short: it is an acknowledgement, not a cutscene,
-- and the prize toast is arriving on the HUD in the same second.
local RISE = 3.4
local LIFE = 1.9
local MAX_DIST = 120   -- past this the label is unreadable anyway and the Gui is pure cost

local function draw(p, text, colour, big)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - p).Magnitude > MAX_DIST then return end

	-- Its own host part rather than an attachment on the chest: the chest is a server-owned model
	-- this script must not write to, and a part parented to `camera` is the standard way to hold a
	-- client-only billboard that nothing replicates and nothing else can trip over.
	local host = Instance.new("Part")
	host.Name = "ChestFxLabel"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Position = p
	host.Parent = camera

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ChestFx"
	billboard.Size = UDim2.new(0, big and 260 or 210, 0, big and 62 or 48)
	-- StudsOffset, never ExtentsOffset: every ExtentsOffset number is half-size and therefore double
	-- what it reads as ([[roblox-extentsoffset-is-half-size]]).
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	-- ON TOP, and this is the one place it earns itself: the word is drawn at the back of a cave
	-- whose plinth, gem and stone ring all stand between the chest and the doorway a player reads it
	-- from. A label a rock eats is a label nobody sees.
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = MAX_DIST
	billboard.Parent = host

	UITheme.Label(billboard, {
		name = "TextLabel",
		text = text,
		color = colour,
		minTextSize = big and 18 or 14,
		maxTextSize = big and 34 or 24,
		size = UDim2.new(1, 0, 1, 0),
	})

	local label = billboard:FindFirstChildWhichIsA("TextLabel")
	local born = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - born) / LIFE
		if t >= 1 or not host.Parent then
			conn:Disconnect()
			host:Destroy()
			return
		end
		host.Position = p + Vector3.new(0, RISE * t, 0)
		if label then
			-- Held solid for the first half and faded over the second: a word that starts fading on
			-- frame one reads as a glitch rather than as a rise.
			label.TextTransparency = math.clamp((t - 0.5) * 2, 0, 1)
			label.TextStrokeTransparency = label.TextTransparency
		end
	end)
end

ChestFx.OnClientEvent:Connect(function(fx)
	if type(fx) ~= "table" then return end
	if typeof(fx.p) ~= "Vector3" then return end
	if type(fx.text) ~= "string" or fx.text == "" then return end
	local colour = typeof(fx.color) == "Color3" and fx.color or UITheme.Color.Gold

	draw(fx.p, fx.text, colour, fx.big == true)

	-- POSITIONAL, so it comes from the chest rather than from the middle of the player's head, and
	-- ONLY on a successful open. The prize sting belongs to `RelicService`'s `relic` notification --
	-- `SoundLibrary`'s alias table already routes that to a rarity-pitched `hatch` -- so this is the
	-- lid, not the reward. A refusal is silent on purpose: a locked door that beeps at you every
	-- time you walk past it is worse than one that does not.
	if fx.big == true then
		SoundLibrary.Play("levelUp", fx.p, { volume = 0.45 })
	end
end)
