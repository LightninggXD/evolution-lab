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
-- ===== 30.29: IT IS A BAND NOW, NOT A NUDGE, AND THE OLD REASONING WAS WRONG =====
-- The owner, on a screenshot of her character at the fitted distance: *"vodi se logikom da player
-- uvek treba biti ovoliko zumiran, eventualno da moze malo da odzumira charactera"* -- this is the
-- view, permanently, with a little room to pull back and none to push in.
--
-- What was here before set the floor for one frame and handed the whole range straight back, so a
-- player could scroll to 0.5 and stand inside their own eyes. The stated reason not to keep the
-- floor was that *"the evolve and hatch reveals both drive the camera themselves"* -- and that is
-- not a conflict, because **both close-ups in this game set `CameraType.Scriptable`**
-- (`FirstJoin.client:200`, `PhotoSpot.client:213`), which writes the camera's CFrame directly and
-- ignores `CameraMinZoomDistance` and `CameraMaxZoomDistance` entirely. A permanent floor cannot
-- reach them. So the floor stays, and the range is a band: `MIN_FIT` to `MAX_FIT` of the body's own
-- height.
--
-- WHAT IS STILL TRUE, AND IS WHY THE SHRINK NEEDS ITS OWN LINE. Raising the floor pushes the live
-- camera out immediately; LOWERING it does not pull the camera back in (measured: min 62.5 put the
-- camera at 64.7, and dropping min to 30 left it at 67.4). A rebirth takes a stage-20 body back to
-- stage 1, so without help the player would keep a camera fitted to a body eight times the size of
-- the one they now have. The CEILING is what pulls a camera in, so a shrink clamps the max to the
-- new fit for a frame and then opens it back up.
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

-- How much of the frame the character should take. Both are multiples of the body's OWN height, so
-- the band is a statement about the character rather than about the stage it happens to be at.
--
-- 1.15 is the measured fit: a 39.7-stud body at 45.6 studs fills about a third of the frame height
-- at the game's 70 degree FOV, which is the screenshot she pointed at. 1.9 is *"malo odzumirati"* --
-- about a fifth of the frame height at the far end, enough to read the zone around you and not
-- enough to lose the character you are looking at.
local MIN_FIT = 1.15
local MAX_FIT = 1.9

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
-- What the floor was set to last time, so a SHRINK can be told from a growth. Starts at zero, which
-- makes the first fit of a session a growth and never triggers the pull-in.
local lastMin = 0

local function fit(character)
	fitToken += 1
	local token = fitToken

	local height = settledHeight(character)
	-- A newer evolve started while this one was settling: that fit is the current one, and two
	-- fits racing would set the band off the older body.
	if token ~= fitToken or not height or not character.Parent then return end

	local near = math.max(DEFAULT_ZOOM, height * MIN_FIT)
	local far = math.max(near, height * MAX_FIT)

	-- ORDER MATTERS BOTH WAYS. The max is a ceiling on the min, so raising the floor through a
	-- lower ceiling silently clamps it (measured -- a min of 30 read back as a max of 30); and the
	-- ceiling is the only thing that pulls a live camera IN. So on a growth the ceiling goes up
	-- first and on a shrink it goes down first, which is also exactly the pull-in a rebirth needs.
	if near < lastMin then
		-- shrink: drop the ceiling onto the new fit to drag the camera in, then open the band
		player.CameraMaxZoomDistance = near
		player.CameraMinZoomDistance = near
		task.wait(0.2)
		if token ~= fitToken or not character.Parent then return end
		player.CameraMaxZoomDistance = far
	else
		player.CameraMaxZoomDistance = far
		player.CameraMinZoomDistance = near
	end
	lastMin = near
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
