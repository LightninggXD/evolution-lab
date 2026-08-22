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
-- ===== 30.30: IT IS A BAND NOW, NOT A NUDGE, AND THE OLD REASONING WAS WRONG =====
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
-- THE BODY IS FROZEN NOW, AND THAT IS WHY THE BAND HAD TO BE RE-CUT. 30.14 pinned every stage to
-- `FIXED_BODY_SCALE = 1.0` (`EvolutionVisuals.lua:397`), so the 39.7-stud character the top of this
-- file was written for does not exist any more: at MAX STAGE the drawn body measures **7.58 studs**.
-- A fitted floor of 1.15x that is 8.7, under `DEFAULT_ZOOM` -- so `math.max` threw the fit away and
-- what the owner was actually handed was a band of 12.5 to 14.4, a fifteen per cent range she could
-- barely feel. The ratios below are cut against the body that is drawn; see the note over `MIN_FIT`.
--
-- What survives the freeze is the shrink branch, because the drawn height still moves: the costume
-- is rebuilt on every skin change and 200 generated skins are not all the same height.
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
-- ...AND "SETTLED" IS NOT ENOUGH ON ITS OWN, which is the 30.30 fault. Before the wardrobe is
-- welded on, the drawn body is the RAW R15 AVATAR -- a real body, 8.4 studs to the dressed one's
-- 7.6, and PERFECTLY STILL while it waits, so two readings agree on it immediately and the fit
-- locks onto the wrong character. Measured on a fresh boot 2026-08-22: the band came out
-- 13.84 / 20.97 where a respawn in the same session gave 12.55 / 19.01. It is only ever a fresh
-- JOIN, because a respawn is already dressed 0.12 s in -- which is exactly what made it look like
-- jitter for three sessions. So the wait is for the WARDROBE first and the settle second.
--

local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- Roblox's own default, and the floor of the fit: at stage 1 the body is under 8 studs tall and
-- 1.15x of that is closer than the camera has ever been, which would be a change nobody asked for.
local DEFAULT_ZOOM = 12.5

-- How much of the frame the character should take. Both are multiples of the body's OWN height, so
-- the band is a statement about the character rather than about the stage it happens to be at.
--
-- RE-MEASURED ON THE FROZEN BODY, 2026-08-22 -- 1.15 / 1.9 were cut against a 39.7-stud character.
-- Three photographs of the live client standing in the village at max stage, drawn height 7.58, the
-- camera driven to each distance by the ceiling and the frame judged rather than computed:
--   * 12.5 studs -- the floor, and it is the view in the screenshot she pointed at: the character
--     is the subject, the ground it stands on is legible, none of it leaves the frame.
--   * 19 studs -- the square, the boards, the shop row and the pets are all in frame and the
--     character is still unmistakably the thing you are looking at. This is *"malo odzumirati"*.
--   * 25 studs -- too far: the body is a smudge among its own pets' name plates.
-- 1.65 x 7.58 = 12.5 and 2.5 x 7.58 = 19.0, so both ends of the band are the photograph rather than
-- a ratio inherited from a body that no longer exists.
local MIN_FIT = 1.65
local MAX_FIT = 2.5

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

-- The two wardrobes. A character has one or the other -- `SkinMesh` when the stage has a generated
-- mesh filed for it, `StageCostume` when it falls through to the primitive builders -- and
-- `CostumeVisibility` names them the same way, for the same reason.
local COSTUME_FOLDERS = { "SkinMesh", "StageCostume" }

local function dressed(character)
	for _, name in ipairs(COSTUME_FOLDERS) do
		if character:FindFirstChild(name) then return true end
	end
	return false
end

-- Two readings that agree to within 1% mean the tween has landed and the costume has stopped being
-- rebuilt. Bounded, because a character that never settles must not stop the camera being fitted
-- at all -- the last reading is still far better than the default.
local function settledHeight(character)
	-- DRESSED FIRST. Six seconds is a ceiling and not a delay: a respawn passes this on the first
	-- poll. Falling through it un-dressed still fits, off the avatar -- wrong by a stud, which is
	-- what the old code did every time and is still better than Roblox's 12.5 on a 40-stud body if
	-- the freeze is ever lifted.
	for _ = 1, 60 do
		if dressed(character) then break end
		task.wait(0.1)
		if not character.Parent then return nil end
	end
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
	--
	-- A REAL SHRINK, NOT MEASUREMENT NOISE -- the 3% is not decoration. `drawnHeight` settles to
	-- within 1% by construction, so two fits on the SAME body land hundredths of a stud apart, and
	-- a bare `<` made every one of them a shrink. Measured live 2026-08-22: a re-fit moved the
	-- floor 12.53 -> 12.51 and the pull-in slammed the camera from 19.55 straight back to 13.11,
	-- throwing away the zoom-out the player had chosen -- on every evolve and every skin change.
	-- The observed spread on one unchanged body is ~2% (floors of 12.74, 12.53 and 12.50 across
	-- three fits), and the smallest event this branch actually has to catch is a whole-body swap,
	-- so 8% is wide enough to never fire on noise and far too narrow to miss a real one.
	if near < lastMin * 0.92 then
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
