-- CameraFit -- the camera has to grow with the body, and until 17.2 it never did.
--
-- THE MEASUREMENT THIS FILE EXISTS FOR. A max-stage character is **39.7 studs tall and 35 wide**
-- (`torso_geom` alone is 35x35x35) while Roblox's camera zoom is a fixed number of studs and
-- nothing in this game had ever touched it -- so the camera sits at the default 12.5, i.e. INSIDE
-- the silhouette. Sampled on the live client at the last stage, 45 rays through the viewport in a
-- 9x5 grid: **43 of 45 hit the player's own body**. Ninety-six per cent of the screen is your own
-- character, and the two rays that got out were a corner. From the same position and the same
-- camera pitch at a fitted distance: **3 of 45** own body, 36 world, 6 sky.
--
-- It is not the same bug as the see-through costume, and the two pull in opposite directions:
-- `CostumeVisibility` exists to STOP Roblox fading your own body when the camera is close, which
-- is right -- a half-dissolved player is not a fix -- and the consequence is that an opaque
-- 35-stud body then fills the frame. Fitting the distance is what makes both correct at once.
--
-- WHY THIS IS A NUDGE AND NOT A LOCK.
--
-- `CameraMinZoomDistance` is a floor, and raising it pushes the live camera out immediately;
-- lowering it again does NOT pull the camera back in (measured: min 62.5 put the camera at 64.7,
-- and dropping min to 30 left it at 67.4). So setting the floor for one frame and restoring it
-- moves the camera exactly once and hands the whole range straight back -- somebody who wants to
-- stand in their own eyes at stage 20 can still scroll in, and nobody is fighting the mouse wheel
-- on a timer. A permanent floor would also break the one legitimate close-up the game has: the
-- evolve and hatch reveals both drive the camera themselves.
--
-- It also never pulls anyone IN. The floor only moves a camera that is closer than the fit, so a
-- player who has zoomed out to look at the zone keeps their view.
--
-- SIZED OFF THE DRAWN BODY, NOT OFF `BodyScale` AND NOT OFF `HipHeight`.
--
-- Same rule as 16.10's regalia and `SkinMesh`: measure the thing, do not model it. `BodyScale` is
-- a target the tween is still on its way to, `HipHeight` measured 14.84 on a body 39.7 tall, and
-- the wardrobe is swapped wholesale on every evolve and every skin change -- so the only honest
-- number is the extent of the parts that are currently drawn. 1.15x the height puts the whole
-- character inside the frame with room around it (measured: a 39.7-stud body fitted to 49.4 studs
-- fills about a third of the frame height at the game's 70 degree FOV).
--
-- THE BODY SETTLES LATE, so this waits for it -- see [[evolution-lab-body-settles-late]]. Limbs
-- keep growing for a couple of frames after `CharacterAdded` and the costume is rebuilt after
-- that, so a fit taken on a fixed delay fits whatever the body happened to be passing through.
-- Polling until two readings agree costs nothing and cannot be early.
--

local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- Roblox's own default, and the floor of the fit: at stage 1 the body is under 8 studs tall and
-- 1.15x of that is closer than the camera has ever been, which would be a change nobody asked for.
local DEFAULT_ZOOM = 12.5

-- How much of the frame the character should take. 1.15x the body's own height, so the fit is a
-- statement about the character rather than about the stage it happens to be at.
local FIT = 1.15

-- The authored floor, restored the moment the nudge has landed.
local FREE_MIN = 0.5

-- Height of everything currently DRAWN on the character. Invisible parts are skipped: the
-- HumanoidRootPart is 13 studs of nothing and the R15 limbs under a generated skin are all at
-- Transparency 1, so counting them would fit the camera to a body nobody can see.
local function drawnHeight(character)
	local lo, hi = math.huge, -math.huge
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			lo = math.min(lo, d.Position.Y - d.Size.Y / 2)
			hi = math.max(hi, d.Position.Y + d.Size.Y / 2)
		end
	end
	if lo == math.huge then return nil end
	return hi - lo
end

-- Two readings that agree to within 1% mean the tween has landed and the costume has stopped being
-- rebuilt. Bounded, because a character that never settles must not stop the camera being fitted
-- at all -- the last reading is still far better than the default.
local function settledHeight(character)
	local last = drawnHeight(character)
	for _ = 1, 24 do
		task.wait(0.1)
		if not character.Parent then return nil end
		local now = drawnHeight(character)
		if now and last and math.abs(now - last) <= last * 0.01 then
			return now
		end
		last = now
	end
	return last
end

local fitToken = 0

local function fit(character)
	fitToken += 1
	local token = fitToken

	local height = settledHeight(character)
	-- A newer evolve started while this one was settling: that fit is the current one, and two
	-- nudges racing would set the floor off the older body.
	if token ~= fitToken or not height or not character.Parent then return end

	local target = math.max(DEFAULT_ZOOM, height * FIT)
	if player.CameraMaxZoomDistance < target then
		-- The max is a ceiling on the min; without this the floor is silently clamped down to it
		-- and the nudge does nothing (measured -- a min of 30 read back as a max of 30).
		player.CameraMaxZoomDistance = target
	end
	player.CameraMinZoomDistance = target
	task.wait(0.2) -- one frame is enough for the camera to take it; 0.2 is enough for a slow one
	player.CameraMinZoomDistance = FREE_MIN
end

local function bind(character)
	task.spawn(fit, character)
	-- Every evolve and every rebirth changes the body without changing the character, and
	-- `BodyScale` is what ApplyStage stamps when it does.
	character:GetAttributeChangedSignal("BodyScale"):Connect(function()
		task.spawn(fit, character)
	end)
end

player.CharacterAdded:Connect(bind)
if player.Character then
	bind(player.Character)
end
