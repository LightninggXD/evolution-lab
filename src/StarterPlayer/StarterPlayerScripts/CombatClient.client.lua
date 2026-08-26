--[[
	CombatClient -- everything a fight LOOKS like.

	The complaint this exists to answer: "I stand next to a creature, I click it, and it disappears
	like it was made of balloon." The server was already doing the fight correctly -- cooldowns,
	scaled damage, retaliation, DNA -- and showing almost none of it. A click produced a number on a
	health bar and, on the last one, an instant Destroy().

	Everything drawn here is drawn LOCALLY, on every machine that is near enough to see it. The
	server sends one small description per hit over Remotes.CombatFx and owns nothing else about
	the presentation. Two reasons:

	  * A billboard or particle emitter created on the server replicates at a throttled rate, so
	    the number meant to punctuate a click lands visibly after it.
	  * The attacker's own swing has to start on the FRAME THEY CLICKED. A round trip is ~100 ms
	    and the whole swing is 260 ms -- routed through the server it would be a third late, which
	    is the difference between "I hit it" and "it reacted to something".

	So the local player's swing is fired straight off their own mouse button, and the remote is
	what plays *other* people's swings and every impact effect.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS:WaitForChild("Modules"):WaitForChild("UITheme"))
local SoundLibrary = require(RS.Modules:WaitForChild("SoundLibrary"))
local IconLibrary = require(RS.Modules:WaitForChild("IconLibrary"))

local player = Players.LocalPlayer
local INK = Color3.fromRGB(26, 18, 36)

-- Local-only scenery. Anything parented here is invisible to the server and to every other
-- client, which is the point: sparks are not game state.
local fxFolder = Instance.new("Folder")
fxFolder.Name = "CombatFxLocal"
fxFolder.Parent = workspace

-- ============================================================================
-- THE SWING
-- ============================================================================
--
-- TWO PATHS, AND THE CANNED ONE IS THE ONE THAT SHIPS ON AN AVATAR RIG (32.9).
--
-- This file was written procedural-only and the comment here argued two reasons for it. The second
-- reason was measured and it is FALSE on the rig this game actually gets:
--
--   * The claim was "it composes -- the Animator drives each joint's Transform, which is applied
--     on top of the joint's own static offset, so writing that offset ADDS a swing". That is true
--     of a `Motor6D` rig. Roblox is midway through replacing Motor6D with `AnimationConstraint`,
--     and the character this game gets has 15 AnimationConstraints and ZERO Motor6Ds.
--   * MEASURED ON THE LIVE BODY, 2026-08-25 -- hand travel in the root's own frame, written every
--     RenderStepped for 0.6s: `Attachment0.CFrame` with the idle track playing moves the hand
--     **0.54 studs**; the identical write with every track stopped moves it **2.31**. Writing
--     `AnimationConstraint.Transform` instead is **0.03** -- the Animator overwrites it the same
--     frame. So the Animator wins and four fifths of the swing this file draws is never seen.
--     That is the "the character stands still and only the ground shakes" complaint, still true.
--   * The first reason -- "a catalog animation id has to be owned by the place's creator" -- is
--     half true, and the missing half is the fix: an animation owned by **Roblox** loads in any
--     place. `rbxassetid://522635514` is the classic sword slash. Loaded and played at `Action4`
--     on this very rig it moves the hand **3.33 studs with the idle track playing** -- six times
--     what the joint writes manage. Nothing is uploaded and nothing waits on the owner.
--
-- So: an `AnimationTrack` above Idle is the swing, and the procedural code below is the FALLBACK --
-- for an R6 avatar, for a Motor6D rig where it always worked, and for the case the asset declines
-- to load. It is not dead code; it is what runs when the Animator is not in the way.
--
-- Both survive the thing that would break a canned animation here: the body scales 1x -> 9x across
-- the twenty stages. A rotation is scale-free, so the same swing reads on a Cell and on a 28-stud
-- Absolute identically.
--
-- ---- two kinds of joint ----
-- Roblox is midway through replacing Motor6D with AnimationConstraint on avatar rigs, and which
-- one a player arrives with is not this game's choice: the character that tested this build had
-- no Motor6D anywhere in it. The static offset lives in a different place on each --
--
--   Motor6D             -> the joint's own C0
--   AnimationConstraint -> Attachment0's CFrame, the PARENT-side attachment (a shoulder's sits in
--                          UpperTorso, not in the arm)
--
-- -- so `resolveJoint` hands back a uniform little handle and the animation below never asks which
-- kind it got. Written against Motor6D alone the arm simply never moved and nothing errored, which
-- is the failure that is hardest to notice.
local SWING_TIME = 0.30
-- ---- the canned swing ----
-- Roblox's own classic-sword slash. Owned by Roblox, so `LoadAnimation` succeeds in this place
-- with nothing uploaded -- see the block above for the measurement that chose it.
--
-- THE ASSET IS 0.50s LONG AND ONLY ITS FIRST 0.30s IS THE BLOW. Sampled at 0.05s steps, the hand
-- sits 2.83 studs from rest at t=0.00 (blades up over the shoulder), reaches rest at t=0.20, and
-- climbs back out to 3.13 by t=0.50. Played whole it reads as chop-then-re-raise and ends with the
-- arms in the air. So the track runs 0.00 -> SWING_ANIM_ARC and is then faded out: the chop plays,
-- and the fade carries the arms back into whatever the Animator was already doing.
--
-- The fade-in IS the wind-up. There is no keyframe for one -- the blend from idle up to the raised
-- first pose is what a player reads as loading the blow, which is why it is not 0.
--
-- ===== AND THE BLEND MUST HAPPEN ON A FROZEN POSE, WHICH COST THE FIRST BUILD ITS PEAK =====
--
-- Built the obvious way -- Play(fade) and let the clock run -- the swing measured **1.81 studs** of
-- hand travel in the live game against the **3.33** the same track reaches in isolation. It is not
-- a blend-priority problem, it is arithmetic: the track's biggest pose is its FIRST frame (2.83
-- studs from rest at t=0.00, already back at rest by t=0.20), and a fade ramps weight 0 -> 1 across
-- the same 0.10s. So the frames where the pose is worth the most are the frames it is worth the
-- least of, and by the time the weight reaches 1 the arm is already 1.78 studs down its own arc --
-- which is 1.81, the number measured. The peak is never drawn at full strength.
--
-- So the track is played FROZEN (`AdjustSpeed(0)`) and only starts moving once the blend is done:
-- the arm rises into the raised pose over SWING_ANIM_WIND, and the chop then plays at full weight.
-- A re-cut skips the hold entirely -- the weight is already 1, so restarting the clock puts the
-- raised pose on screen at full strength on the very first frame.
local SWING_ANIM_ID = "rbxassetid://522635514"
local SWING_ANIM_WIND = 0.08  -- blend in, held on the raised first pose: the wind-up
local SWING_ANIM_ARC = 0.22   -- seconds of the asset then played: the drop, t=0.00 -> ~0.20
local SWING_ANIM_FADE = 0.10  -- blend out: the recovery back into whatever the Animator was doing
-- A new swing may cut into the tail of the one before it. Holding the old "one swing at a time"
-- rule made auto-attack look broken: the loop fires faster than a swing lasts, so every second
-- request was dropped and the character stood still through half its own hits.
local SWING_RECUT = 0.55 -- fraction of a swing that must have played before another may start
local swinging = {}  -- [character] = { token, startedAt }
local nextHand = {}  -- [character] = "Left"/"Right" -- alternating reads as a flurry, not a tic

local function resolveJoint(character, name)
	local found = character:FindFirstChild(name, true)
	if not found then return nil end
	if found:IsA("Motor6D") then
		return { inst = found, prop = "C0", base = found.C0 }
	elseif found:IsA("AnimationConstraint") and found.Attachment0 then
		return { inst = found.Attachment0, prop = "CFrame", base = found.Attachment0.CFrame }
	end
	return nil
end

local function setJoint(joint, cframe)
	joint.inst[joint.prop] = cframe
end

-- ---- the canned track, one per character ----
-- Weak-keyed: a character that despawns takes its track with it, and a respawn gets a fresh one
-- because the cached track's Animator went with the old body.
--
-- `false` is cached for a character whose animator refused the asset, so a failed load is paid for
-- once rather than on every swing of a fight -- and the warning is printed once for the same
-- reason. That character then swings procedurally for its whole life, which is the old behaviour.
local swingAnim = Instance.new("Animation")
swingAnim.AnimationId = SWING_ANIM_ID
local swingTracks = setmetatable({}, { __mode = "k" })

local function swingTrack(character, humanoid)
	local cached = swingTracks[character]
	if cached == false then return nil end
	if cached and cached.Animator and cached.Animator.Parent then return cached end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		swingTracks[character] = false
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(swingAnim)
	end)
	if not ok or not track then
		swingTracks[character] = false
		warn("[CombatClient] the swing animation would not load (" .. SWING_ANIM_ID ..
			") -- falling back to the procedural swing, which barely moves an AnimationConstraint rig")
		return nil
	end
	-- Above Idle and above Movement, or the idle this body is always playing wins the blend and the
	-- whole point of the change is lost. Action4 is the top of the ladder: nothing this game plays
	-- should outrank a blow landing.
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	swingTracks[character] = track
	return track
end

-- Someone else's body is already swinging on our screen without our help: an AnimationTrack played
-- on a player's own client REPLICATES, which the procedural joint writes never did. So the CombatFx
-- handler must not lay a second copy on top of the one that arrived by itself -- it still owes that
-- character its trail and its whoosh, but not its arm.
local function alreadySwinging(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return false end
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
		local a = t.Animation
		if a and a.AnimationId == SWING_ANIM_ID then return true end
	end
	return false
end

-- ---- the shape of the swing ----
-- Three beats, and the whole thing lives or dies on the middle one being much faster than the
-- other two. An arm that travels at one speed reads as waving; an arm that loads slowly, crosses
-- in three frames and then drifts back reads as a blow landing.
--
--   0.00 - 0.30  WIND UP   -- fist drawn back over the shoulder, elbow folded
--   0.30 - 0.56  STRIKE    -- smoothstepped through 4.2 radians, elbow snapping straight
--   0.56 - 1.00  RECOVER   -- a decay, not a return: this is the follow-through
--
-- The numbers were cut hard after seeing it on the finished body. A 4.35-radian sweep is correct
-- on a thin avatar arm and wrong on this one: the limbs are now shells two-thirds the width of the
-- torso, so an arm thrown through 250 degrees passes straight THROUGH the chest and comes out as a
-- jumble of overlapping blocks -- which is exactly what auto-attack looked like, a body chewing
-- itself. A short forward throw reads as a punch and never leaves the silhouette.
local function armAngle(t)
	if t < 0.30 then
		local k = t / 0.30
		return -0.75 * (k * k * (3 - 2 * k))
	elseif t < 0.56 then
		local k = (t - 0.30) / 0.26
		return -0.75 + 2.35 * (k * k * (3 - 2 * k))
	end
	local k = (t - 0.56) / 0.44
	return 1.60 * (1 - k) ^ 1.7
end

-- Elbow folds on the wind-up and snaps straight through the strike. Positive flexes: with the arm
-- hanging, the same axis that raises it at the shoulder brings the forearm forward at the elbow.
local function elbowAngle(t)
	if t < 0.30 then
		local k = t / 0.30
		return 0.85 * (k * k * (3 - 2 * k))
	elseif t < 0.56 then
		local k = (t - 0.30) / 0.26
		return 0.85 * (1 - k) ^ 0.7
	end
	local k = (t - 0.56) / 0.44
	return 0.24 * (1 - k)
end

-- The swoosh. A Trail off the swinging hand rather than a drawn arc: it follows whatever path the
-- hand actually takes, at whatever size the body happens to be, and costs one instance.
local function handTrail(character, hand, isR6)
	local part = character:FindFirstChild(isR6 and (hand .. " Arm") or (hand .. "Hand"))
	if not part then return end

	-- ===== THE RIBBON DRAWS THE BLADE THAT IS ACTUALLY IN THE HAND (32.6) =====
	--
	-- This used to be hard-coded white-into-gold at a fixed 1.7 hand-lengths, and its own comment
	-- said the length was chosen so the ribbon read as "roughly a weapon's length". There is a real
	-- weapon there now, so the guess becomes a reading: `SwordModel` stamps the worn tier's colour
	-- and reach onto the CHARACTER, which is the one channel that reaches this function -- it runs
	-- on every machine for every player it can see and has access to nobody's save.
	--
	-- Both fall back to what was hard-coded before, so a body with no sword yet (the frames between
	-- a spawn and the dress, or a stage the geometry declined) swings exactly as it always did.
	--
	-- MEASURED IN THE HOST'S OWN UNITS, and the host here is the AVATAR's hand while the blade
	-- hangs off the costume's mitt -- which is 1.5x taller. `SwordReach` is in mitt-heights, so it
	-- is multiplied by that 1.5 to land the ribbon's far end on the steel's own tip rather than a
	-- third of the way up it.
	local swordColor = character:GetAttribute("SwordColor")
	local swordReach = character:GetAttribute("SwordReach")
	local ribbon = swordReach and (swordReach * 1.5) or 1.7

	-- ===== AND IT DRAWS ALONG THE ANGLE THE BLADE IS ACTUALLY HELD AT (32.14) =====
	--
	-- The ribbon used to run straight down the hand's -Y because that is where the steel hung. It
	-- does not hang there any more: `SwordModel.restPose` turns the whole sword into a sword-out
	-- pose, 30 degrees above the horizontal and yawed outward, so a trail still drawn down -Y would
	-- run through the leg while the sword pointed forward -- the exact "two different paths" fault
	-- that comment was written to prevent, arriving from the other side.
	--
	-- `SwordRest` carries the RIGHT hand's direction in hand-local studs. The pose is mirrored about
	-- the body's centre line, and a yaw mirrored that way negates the X component and nothing else,
	-- so the left hand's direction is this one with X flipped. Falls back to straight down for a
	-- body with no sword yet -- the frames between a spawn and the dress -- which is exactly how the
	-- swoosh looked before there was a sword to draw.
	local rest = character:GetAttribute("SwordRest")
	local dir = Vector3.new(0, -1, 0)
	if typeof(rest) == "Vector3" and rest.Magnitude > 0.01 then
		dir = (hand == "Left") and Vector3.new(-rest.X, rest.Y, rest.Z).Unit or rest.Unit
	end

	local a0 = Instance.new("Attachment")
	-- the tail end, behind the fist -- the pommel's side of the grip whichever way the blade points
	a0.Position = -dir * (part.Size.Y * 0.6)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	-- reaches PAST the hand, so the ribbon is roughly a weapon's length rather than a finger's
	a1.Position = dir * (part.Size.Y * ribbon)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.17
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.LightEmission = 1
	-- White at the leading edge whatever the blade is -- a swoosh that starts in the tier's own
	-- colour reads as a coloured smear rather than as speed -- and the blade's colour at the tail.
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), swordColor or Color3.fromRGB(255, 224, 128))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = part

	-- created on this machine only, so they are ours to clean up and nobody else ever sees them
	Debris:AddItem(trail, 0.7)
	Debris:AddItem(a0, 0.7)
	Debris:AddItem(a1, 0.7)
end

-- The complaint this rewrite answers: "when I hit, the character stands still and only the ground
-- shakes." Two causes, and both are fixed here and in CreatureService.
--
--   * the swing only ever moved ONE joint -- a shoulder, plus a thirteenth of the angle at the
--     waist. On a body scaled up to nine times human that is a small thing happening at the far
--     end of a large silhouette, and it was the only thing happening.
--   * it very often did not play at all. The swing is gated on the mouse ray finding a creature,
--     and until now only the torso and head of a rig were queryable -- aim at a horn, a wing or a
--     paw and the ray came back empty, so the click did damage (the ClickDetector fired) and drew
--     nothing. The full-rig hit box on the server side is what actually fixes that one.
--
-- Now the whole body commits: both arms (the off arm counter-swings), the elbows, the waist twists
-- INTO the blow and back, the head leads it, and the hips take a short step. Everything is a
-- rotation, so it is scale-free -- a one-stud Cell and a 28-stud Absolute swing identically.
-- Every joint a swing touches, resolved as ONE set and then carried on the swing state.
--
-- THIS IS THE BUG THAT FOLDED THE CHARACTER UP. `resolveJoint` captures a joint's rest pose at the
-- moment it is called, and playSwing called it fresh every time. A re-cut swing -- which is every
-- swing once auto-attack is running, since the loop fires before the previous one has recovered --
-- therefore captured the joints while they were still ROTATED from the swing before, and treated
-- that mid-pose as the new rest. The error compounded a few degrees per hit until the whole rig had
-- twisted into a pile of blocks, which is exactly what it looked like.
--
-- Resolving once and reusing the set means `base` is always the true rest pose, however many swings
-- overlap. The set is dropped when a swing finishes cleanly, so the next one re-reads it -- which is
-- what picks up an evolve, where every attachment moves with the body scale.
local function resolveSet(character, isR6)
	-- R6 names its shoulders with a space ("Right Shoulder"); R15 does not. Everything in this game
	-- is R15 -- the stage scaling needs it -- but an R6 avatar should still swing.
	local suffix = isR6 and " Shoulder" or "Shoulder"
	local set = {
		RightShoulder = resolveJoint(character, "Right" .. suffix),
		LeftShoulder = resolveJoint(character, "Left" .. suffix),
	}
	-- R15 only: R6 has no elbows, no waist and no neck joint worth writing to
	if not isR6 then
		set.RightElbow = resolveJoint(character, "RightElbow")
		set.LeftElbow = resolveJoint(character, "LeftElbow")
		set.Waist = resolveJoint(character, "Waist")
		set.Neck = resolveJoint(character, "Neck")
		set.RightHip = resolveJoint(character, "RightHip")
		set.LeftHip = resolveJoint(character, "LeftHip")
	end
	return set
end

-- Puts every joint back and forgets the set. Called when a swing ends cleanly, and whenever the
-- body changes size under it: a rest pose captured at one scale is not the rest pose at the next,
-- and writing the stale one would leave the new body standing crooked.
local function resetSwing(character)
	local state = swinging[character]
	if not state then return end
	swinging[character] = nil
	-- the canned path owns a track and no joints; the procedural path owns joints and no track
	if state.track then
		pcall(function() state.track:Stop(SWING_ANIM_FADE) end)
	end
	for _, j in pairs(state.joints) do
		if j.inst.Parent then setJoint(j, j.base) end
	end
end

local function playSwing(character)
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local active = swinging[character]
	if active and (os.clock() - active.startedAt) < SWING_TIME * SWING_RECUT then
		return
	end

	local isR6 = humanoid.RigType == Enum.HumanoidRigType.R6

	-- ===== THE CANNED SWING (32.9) =====
	-- Tried first on every rig that is not R6. If the asset loads, this IS the swing and the
	-- procedural block below never runs for this character.
	local track = (not isR6) and swingTrack(character, humanoid) or nil
	if track then
		local swingRoot = character:FindFirstChild("HumanoidRootPart")
		if swingRoot then
			SoundLibrary.Play("swing", swingRoot)
		end
		-- The asset swings the RIGHT arm. The old alternation existed because a procedural swing
		-- could be mirrored for free and a repeated identical throw read as a tic; here the variety
		-- comes from the speed instead, which is the same mitigation `swing` already carries in
		-- SoundLibrary.
		nextHand[character] = "Right"
		handTrail(character, "Right", false)

		if alreadySwinging(humanoid) and character ~= player.Character then
			-- their own client is already playing it and it replicated to us; the trail and the
			-- whoosh above are all this call still owes them
			return
		end

		local token = {}
		swinging[character] = { token = token, startedAt = os.clock(), joints = {}, track = track }

		-- Variety without a mirrored pose: at one swing every 0.20s a fixed-length arc reads as a
		-- stuck loop, the same way a fixed sound sample does.
		local speed = 0.92 + math.random() * 0.16
		local recut = track.IsPlaying
		if recut then
			-- every swing once auto-attack is running. The weight is already 1, so restarting the
			-- clock in place shows the raised pose at full strength immediately -- no second
			-- wind-up, and no Stop/Play whose fade-out would eat the front of this one.
			track.TimePosition = 0
			track:AdjustSpeed(speed)
		else
			track:Play(SWING_ANIM_WIND)
			track.TimePosition = 0
			track:AdjustSpeed(0)
			task.delay(SWING_ANIM_WIND, function()
				local st = swinging[character]
				if st and st.token == token then track:AdjustSpeed(speed) end
			end)
		end

		task.delay((recut and 0 or SWING_ANIM_WIND) + SWING_ANIM_ARC, function()
			local state = swinging[character]
			-- a newer swing has taken over: it owns the track and the stop, exactly as the
			-- procedural loop's token check does below
			if state and state.token == token then
				swinging[character] = nil
				pcall(function() track:Stop(SWING_ANIM_FADE) end)
			end
		end)
		return
	end

	local hand = (nextHand[character] == "Right") and "Left" or "Right"
	local other = (hand == "Right") and "Left" or "Right"
	nextHand[character] = hand

	-- reused from the swing being cut into, or read fresh if nothing is running. NEVER re-read
	-- mid-swing -- see the note on resolveSet.
	local joints = (active and active.joints) or resolveSet(character, isR6)
	local arm = joints[hand .. "Shoulder"]
	if not arm then return end
	local offArm = joints[other .. "Shoulder"]
	local elbow = joints[hand .. "Elbow"]
	local offElbow = joints[other .. "Elbow"]
	local waist, neck = joints.Waist, joints.Neck
	local hip = joints[other .. "Hip"]

	-- every joint this swing owns, so the restore at the end is one loop and can never miss one
	local owned = {}
	for _, j in pairs(joints) do
		table.insert(owned, j)
	end

	local token = {}
	swinging[character] = { token = token, startedAt = os.clock(), joints = joints }
	handTrail(character, hand, isR6)

	-- Positional, on the swinger's own root -- this function plays OTHER players' swings too (see
	-- the CombatFx handler at the bottom), and a whoosh from someone fighting across the platform
	-- must not arrive as if it came out of your own arms.
	--
	-- `swing` is the one entry in SoundLibrary carrying BOTH mitigations: four assets and a random
	-- pitch. At one swing every 0.20s with the Fast Auto Attack pass, a single fixed sample stops
	-- reading as fighting and starts reading as a stuck loop.
	local swingRoot = character:FindFirstChild("HumanoidRootPart")
	if swingRoot then
		SoundLibrary.Play("swing", swingRoot)
	end

	local side = (hand == "Right") and 1 or -1

	task.spawn(function()
		local t0 = os.clock()
		while character.Parent and arm.inst.Parent do
			-- a newer swing has taken over: leave the joints exactly where they are and let the
			-- newer loop own the restore, or the two fight and the arm stutters
			local state = swinging[character]
			if not state or state.token ~= token then return end

			local t = (os.clock() - t0) / SWING_TIME
			if t >= 1 then break end
			local a = armAngle(t)

			if isR6 then
				-- the R6 shoulder's offset carries a 90-degree yaw, which turns its local Z into the
				-- character's left-right axis -- so a forward swing is a roll here, not a pitch
				setJoint(arm, arm.base * CFrame.Angles(0, 0, -side * a))
				if offArm then
					setJoint(offArm, offArm.base * CFrame.Angles(0, 0, side * a * 0.34))
				end
			else
				-- The roll is OUTWARD (+side), away from the chest. Rolled inward -- which is what a
				-- human swing does -- a shell this wide is inside the torso for most of the throw.
				setJoint(arm, arm.base * CFrame.Angles(a, 0, side * math.abs(a) * 0.12))
				if offArm then
					-- the off arm goes the other way. Counter-rotation is most of what makes a swing
					-- look driven by a body rather than performed by an arm.
					setJoint(offArm, offArm.base * CFrame.Angles(-a * 0.34, 0, -side * math.abs(a) * 0.1))
				end
				local bend = elbowAngle(t)
				if elbow then setJoint(elbow, elbow.base * CFrame.Angles(bend, 0, 0)) end
				if offElbow then setJoint(offElbow, offElbow.base * CFrame.Angles(bend * 0.4, 0, 0)) end
				if waist then
					-- pitch with the arm, and TWIST against it and back through it -- the twist is
					-- what carries the weight across. Kept small: the torso shell is most of the
					-- character's mass now, and a big twist swings the whole silhouette.
					setJoint(waist, waist.base * CFrame.Angles(a * 0.14, side * a * 0.18, 0))
				end
				if neck then
					-- the head leads slightly and stays with the blow: a character that swings without
					-- looking at what it is hitting reads as a puppet
					setJoint(neck, neck.base * CFrame.Angles(a * 0.12, -side * a * 0.12, 0))
				end
				if hip then
					-- the short step under it. Only the trailing leg, and only a little -- both legs
					-- would fight the walk animation the Animator is still playing underneath.
					setJoint(hip, hip.base * CFrame.Angles(-a * 0.13, 0, 0))
				end
			end
			RunService.RenderStepped:Wait()
		end
		-- always put them all back, even if the loop bailed out: a joint left rotated is a character
		-- permanently standing with one arm out
		-- only the swing that still owns the character restores it: a superseded loop putting the
		-- joints back would yank the arm mid-throw of the swing that replaced it
		if swinging[character] and swinging[character].token == token then
			swinging[character] = nil
			for _, j in ipairs(owned) do
				if j.inst.Parent then setJoint(j, j.base) end
			end
		end
	end)
end

-- ============================================================================
-- IMPACT
-- ============================================================================

local function invisibleHost(cframe)
	local host = Instance.new("Part")
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = cframe
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Parent = fxFolder
	return host
end

-- Hard-edged shards and one flash, sized off the creature that was hit. Deliberately not a smoke
-- puff: every other object in this game is chunky and flat-shaded, and a soft grey cloud is the
-- one effect that reads as borrowed from a different game.
local function spark(position, color, size, big)
	size = math.clamp(size or 10, 4, 40)
	color = color or Color3.fromRGB(255, 235, 150)

	local host = invisibleHost(CFrame.new(position))
	local att = Instance.new("Attachment")
	att.Parent = host

	local shards = Instance.new("ParticleEmitter")
	shards.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	shards.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	shards.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.65, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shards.Lifetime = NumberRange.new(0.14, 0.3)
	shards.Speed = NumberRange.new(size * 1.3, size * 2.8)
	shards.SpreadAngle = Vector2.new(180, 180)
	shards.Rate = 0
	shards.RotSpeed = NumberRange.new(-420, 420)
	shards.LightEmission = 0.9
	shards.Parent = att
	shards:Emit(big and 22 or 11)

	-- The flash. Six frames of a neon ball is what puts the hit ON the creature rather than in the
	-- air near it -- without it the shards read as something that happened by itself.
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(size * 0.45, size * 0.45, size * 0.45)
	flash.CFrame = CFrame.new(position)
	flash.Color = Color3.new(1, 1, 1)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.1
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Parent = fxFolder
	TweenService:Create(flash, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size * 1.15, size * 1.15, size * 1.15),
		Transparency = 1,
	}):Play()

	-- Modern expanding neon impact shockwave ring for chunky combat feedback
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, size * 0.35, size * 0.35)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = fxFolder
	TweenService:Create(ring, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, size * 1.5, size * 1.5),
		Transparency = 1,
	}):Play()

	Debris:AddItem(host, 0.8)
	Debris:AddItem(flash, 0.2)
	Debris:AddItem(ring, 0.22)
end

-- ============================================================================
-- DAMAGE NUMBERS
-- ============================================================================
--
-- Sized in PIXELS, not studs, and AlwaysOnTop. A number is a readout, not an object in the world:
-- it has to stay legible from wherever the camera happens to be, and it must never end up behind
-- the creature it belongs to.
local NUMBER_TIME = 0.85

-- 10000 IS NOT A NUMBER ANYBODY READS IN 0.85 SECONDS.
--
-- Damage carries the zone multiplier, the stage, the worn skin's rank and every upgrade on top, so
-- a mid-game hit is five digits and a late one is eight. "12000000" thrown off a creature for less
-- than a second is a smear of noughts -- the player sees that a number happened and nothing else.
--
-- One decimal, and only where it earns its place: 10000 -> "10K", 12500 -> "12.5K", 12000000 ->
-- "12M". The trailing ".0" is TRIMMED rather than formatted away, because the choice is per value
-- (the same call has to produce both "12.5M" and "12M") and "%g" would hand back "1.2e+07".
--
-- Every number this file draws goes through here -- the damage you deal, the damage you take, the
-- DNA a kill pays and the boss bar -- so no two of them can ever disagree about how a number looks.
local SUFFIX = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
local function shortNumber(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	if n < 1000 then return tostring(n) end
	local mag = 0
	while n >= 1000 and mag < #SUFFIX do
		n = n / 1000
		mag += 1
	end
	-- THE ROUNDING CAN PUSH IT BACK OVER, and the loop above has already stopped looking. 999,999
	-- divides once to 999.999, which is under the loop's threshold and so is accepted -- and then
	-- "%.1f" prints it as "1000.0", i.e. "1000K" for a number one short of a million. Caught here
	-- rather than by rounding first, because the carry can only ever happen at this one boundary.
	if n >= 999.95 and mag < #SUFFIX then
		n = n / 1000
		mag += 1
	end
	local body = string.format("%.1f", n):gsub("%.0$", "")
	return body .. SUFFIX[mag]
end

-- `iconId` is optional and is an `IconLibrary.Id` VALUE, not an emoji: the training pop draws the
-- owner's own biceps art beside the number (33.21). Everything else about the pop is unchanged, so
-- the ninety-odd existing calls pass four arguments and get exactly what they got before.
local function popNumber(position, text, color, big, iconId)
	local host = invisibleHost(CFrame.new(position))

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, big and 210 or 140, 0, big and 76 or 52)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = host

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = big and 4 or 3
	stroke.Color = INK
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	-- ===== THE OPTIONAL ICON =====
	-- The label keeps its full width and the icon is inset to its LEFT rather than sharing a layout,
	-- because the text is `TextScaled` -- a UIListLayout here would fight the scaler every frame.
	-- The text is nudged right by the same amount so the two do not overlap.
	--
	-- SIZED IN BOTH AXES FROM THE SAME FRACTION. `SizeConstraint = RelativeYY` would be the obvious
	-- way to square it and is the trap in `evolution-lab-icon-system`: it makes the X scale relative
	-- to the parent's HEIGHT too, so the intuitive `UDim2.new(0, 0, 0.8, 0)` is a slot zero pixels
	-- wide, and every structural probe reports it present and correct.
	local iconLabel
	if iconId and iconId ~= "" then
		iconLabel = Instance.new("ImageLabel")
		iconLabel.Name = "Icon"
		iconLabel.BackgroundTransparency = 1
		iconLabel.Image = iconId
		iconLabel.Size = UDim2.new(0, big and 42 or 30, 0, big and 42 or 30)
		iconLabel.Position = UDim2.new(0, 0, 0.5, 0)
		iconLabel.AnchorPoint = Vector2.new(0, 0.5)
		iconLabel.Parent = gui
		label.Size = UDim2.new(1, -(big and 44 or 32), 1, 0)
		label.Position = UDim2.new(0, big and 44 or 32, 0, 0)
	end

	-- Every number gets its own sideways drift, or a burst of them stacks into one illegible
	-- column. The rise is eased out so it decelerates as it fades rather than sliding off screen.
	local drift = Vector3.new((math.random() - 0.5) * 5, 0, (math.random() - 0.5) * 5)
	local rise = big and 11 or 7
	local baseSize = gui.Size

	task.spawn(function()
		local t0 = os.clock()
		while host.Parent do
			local t = (os.clock() - t0) / NUMBER_TIME
			if t >= 1 then break end
			local ease = 1 - (1 - t) * (1 - t)
			host.CFrame = CFrame.new(position + drift * ease + Vector3.new(0, rise * ease, 0))
			-- a pop on the way in: 30% over size in the first eighth of a second, then settle
			local pop = t < 0.12 and (1 + 0.3 * math.sin(t / 0.12 * math.pi)) or 1
			gui.Size = UDim2.new(0, baseSize.X.Offset * pop, 0, baseSize.Y.Offset * pop)
			-- held solid for the first half, then out: a number that starts fading immediately is
			-- never read
			local fade = math.clamp((t - 0.5) / 0.5, 0, 1)
			label.TextTransparency = fade
			stroke.Transparency = fade
			if iconLabel then iconLabel.ImageTransparency = fade end
			RunService.RenderStepped:Wait()
		end
		host:Destroy()
	end)
end

-- ============================================================================
-- THE EVOLUTION SHARD PICKUP (9.4)
-- ============================================================================
--
-- Drawn only on the killer's own screen. `sh` reaches every client inside FX range, but the handler
-- tests `mine` before calling this -- the rule the DNA pop already follows. A drop belongs to one
-- player, and a crystal tearing out of every creature on the platform is everybody else's clutter.
--
-- THE SHAPE IS THE HOUSE RECIPE FOR A CRYSTAL, the same two pieces ZoneBuilder cuts its geodes and
-- egg shells from: a hard block body with a SMALLER, PALER TIP sitting on it. Roblox blocks do not
-- taper, so that tip is the entire reason a rectangle reads as something faceted -- without it this
-- is a floating brick. Gold, because the pill it lands in is a gold star and a pickup whose colour
-- does not match its counter is a pickup nobody connects to their balance.
--
-- No Highlight anywhere near it: CreatureService rents 14 of the ~31 outline renders the engine
-- has, and one per drop would strip the outlines off creatures across the world.
local SHARD_RISE, SHARD_FLY = 0.42, 0.55

local function shardPickup(position, size)
	-- off the creature it fell out of: ~1.7 studs from a Brute, ~3.6 from an Elite, so it is
	-- visible against the thing that dropped it rather than a constant speck beside a 26-stud rig
	local u = math.clamp(size or 12, 6, 30) * 0.14

	local crystal = Instance.new("Model")
	crystal.Name = "ShardDrop"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(u, u * 1.7, u)
	body.CFrame = CFrame.new(position)
	body.Color = Color3.fromRGB(255, 206, 84)
	body.Material = Enum.Material.Neon
	body.Anchored, body.CanCollide, body.CanQuery, body.CanTouch, body.CastShadow = true, false, false, false, false
	body.Parent = crystal
	-- set BEFORE the tip is parented, so the model's pivot is the body rather than a bounding-box
	-- centre that would move as the tip does
	crystal.PrimaryPart = body

	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(u * 0.62, u * 0.72, u * 0.62)
	tip.CFrame = CFrame.new(position + Vector3.new(0, u * 1.2, 0))
	tip.Color = Color3.fromRGB(255, 248, 206)
	tip.Material = Enum.Material.Neon
	tip.Anchored, tip.CanCollide, tip.CanQuery, tip.CanTouch, tip.CastShadow = true, false, false, false, false
	tip.Parent = crystal

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 214, 120)
	glow.Range = u * 7
	glow.Brightness = 2.2
	glow.Parent = body

	crystal.Parent = fxFolder

	local start = os.clock()
	local from = position
	local rise = Vector3.new(0, u * 3.4, 0)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		-- a connection rather than a loop that waits on a render step, and the parent check is the
		-- reason: this is the one path that can outlive its own model (a respawn, a Debris sweep, the
		-- player leaving), and a PivotTo against a destroyed model errors once a frame forever
		if not crystal.Parent then
			conn:Disconnect()
			return
		end
		local t = os.clock() - start
		local spin = t * 7
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")

		if t < SHARD_RISE then
			-- out of the corpse and hanging for a beat: the player has to see WHAT dropped before it
			-- starts moving, or the whole thing reads as one more spark off the death effect
			local a = t / SHARD_RISE
			crystal:PivotTo(CFrame.new(from + rise * (1 - (1 - a) ^ 2)) * CFrame.Angles(0, spin, math.rad(14)))
		elseif hrp and t < SHARD_RISE + SHARD_FLY then
			local a = (t - SHARD_RISE) / SHARD_FLY
			-- THE TARGET IS RE-READ EVERY FRAME, not captured when the flight began. A player is
			-- almost always walking when a creature dies, and a crystal that flies to where they were
			-- half a second ago lands behind them and reads as a miss.
			local target = hrp.Position + Vector3.new(0, 1.5, 0)
			crystal:PivotTo(CFrame.new((from + rise):Lerp(target, a * a)) * CFrame.Angles(0, spin, math.rad(14)))
		else
			conn:Disconnect()
			crystal:Destroy()
			-- the number is drawn at the player, not at the kill: this is the moment the balance
			-- actually changed, and it is where they are looking
			if hrp then
				popNumber(hrp.Position + Vector3.new(0, 3, 0), "+1 \u{1F31F}", Color3.fromRGB(255, 214, 120), false)
				SoundLibrary.PlayLocal("collect")
			end
		end
	end)

	-- belt and braces against a disconnected client leaving a lit crystal in the world; the loop
	-- above disposes of it a second earlier on every normal path
	Debris:AddItem(crystal, SHARD_RISE + SHARD_FLY + 2)
end

-- ============================================================================
-- CAMERA KICK
-- ============================================================================
--
-- Through Humanoid.CameraOffset rather than by moving the camera or pulling the FOV: the offset is
-- a single vector the engine folds into the follow camera, so it cannot fight the player's own
-- control and it cannot leave the camera stranded if this script dies mid-shake. Scaled by the
-- body, because 0.4 studs is a punch at stage one and imperceptible at stage twenty.
local shakeUntil = 0

local function cameraKick(strength)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local scale = character:GetAttribute("BodyScale") or 1
	local amount = 0.34 * strength * scale
	local duration = 0.2 * strength

	local mine = os.clock() + duration
	shakeUntil = mine
	task.spawn(function()
		local t0 = os.clock()
		while humanoid.Parent and shakeUntil == mine do
			local t = (os.clock() - t0) / duration
			if t >= 1 then break end
			local decay = (1 - t) * amount
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * decay,
				(math.random() - 0.5) * 2 * decay,
				0
			)
			RunService.RenderStepped:Wait()
		end
		-- only the newest shake is allowed to put the camera back, or an overlapping one gets cut
		if humanoid.Parent and shakeUntil == mine then
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

-- ============================================================================
-- HEALTH OVER THE HEAD
-- ============================================================================
--
-- Roblox's built-in humanoid health bar is a thin red strip with none of this game's outline,
-- radius or palette, and it is switched off below in favour of one built from UITheme.
--
-- The BAR appears when a character is hurt and hides a few seconds after it is full again. A bar
-- that is always up is chrome; a bar that appears exactly when you are being hit is information.
-- The NAME above it is always up, because that is not a readout, it is who this is.
local PLATE_HIDE_DELAY = 4

local function attachHealthPlate(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local head = character:WaitForChild("Head", 10)
	if not (humanoid and head) then return end

	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	-- ...AND SO IS ROBLOX'S OWN NAME LABEL. It is drawn off the Head, and every stage except Human
	-- makes the Head fully transparent and buries it inside a costume shell -- which is why the
	-- report was "there is still no name above me" even though the Humanoid had a DisplayName and a
	-- 100-stud NameDisplayDistance the whole time. The name is drawn in this plate instead, where
	-- it sits above the bar, in this game's font, and clears the costume.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local owner = Players:GetPlayerFromCharacter(character)

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthPlate"
	-- name row + bar row. The plate keeps this height whether or not the bar is showing, so the
	-- name does not hop down the screen every time a fight ends.
	gui.Size = UDim2.new(0, 168, 0, 52)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Enabled = true
	-- THE WHOLE PLATE SITS ABOVE ITS ANCHOR POINT, not centred on it. This is the fix for "the bar
	-- is over my head": a BillboardGui sized in OFFSET is a constant number of PIXELS on screen,
	-- while StudsOffset is world space and shrinks as the camera pulls back -- so any stud offset
	-- that clears the head up close is swallowed by the plate's own pixel height from further away,
	-- which is exactly what the screenshot showed. SizeOffset is measured in the plate's own size,
	-- so half of it puts the bottom edge on the anchor at every distance and every stage scale.
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.Parent = head

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 18)
	titleLabel.Position = UDim2.new(0, 0, 0, -16)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = UITheme.Font.Sub
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = UITheme.Color.Gold
	titleLabel.Text = ""
	titleLabel.Visible = false
	titleLabel.Parent = gui

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 2
	titleStroke.Color = INK
	titleStroke.LineJoinMode = Enum.LineJoinMode.Round
	titleStroke.Parent = titleLabel

	local function updateTitle()
		if owner then
			local title = owner:GetAttribute("WornTitle")
			if title and title ~= "" then
				titleLabel.Text = "< " .. title .. " >"
				titleLabel.Visible = true
			else
				titleLabel.Visible = false
			end
		end
	end
	if owner then
		owner:GetAttributeChangedSignal("WornTitle"):Connect(updateTitle)
		updateTitle()
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 26)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = UITheme.Font.Display
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	-- DisplayName, with the username as the fallback -- and the character's own name for anything
	-- this ever runs on that is not a player's body
	nameLabel.Text = owner and (owner.DisplayName ~= "" and owner.DisplayName or owner.Name) or character.Name
	nameLabel.Parent = gui

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 3
	nameStroke.Color = INK
	nameStroke.LineJoinMode = Enum.LineJoinMode.Round
	nameStroke.Parent = nameLabel

	local bar, fill = UITheme.ProgressBar(gui, {
		name = "Bar",
		size = UDim2.new(1, 0, 0, 22),
		position = UDim2.new(0, 0, 1, 0),
		anchorPoint = Vector2.new(0, 1),
		radius = UDim.new(1, 0),
		thickness = 3,
		progress = 1,
		color = UITheme.Color.Green,
		text = "",
	})
	bar.Visible = false

	local hideAt = 0

	local function updateNamePlate()
		if owner then
			local worn = owner:GetAttribute("WornNamePlate")
			local plateColor = nil
			if worn and worn ~= "" then
				-- We could parse GameConfig.Cosmetics here, but since this is client, we can just check key directly or use ReplicatedStorage if we had it.
				-- Let's just do a simple check or fetch from GameConfig if available.
				-- Since we don't have GameConfig required at the top of CombatClient (maybe we do?), let's just do hardcoded for now or require it.
			end
			-- For now, if there is a worn plate, we can tint the name stroke or name text.
			if worn == "NamePlate_Gold" then
				nameLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
			elseif worn == "NamePlate_Neon" then
				nameLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
			elseif worn == "NamePlate_Dark" then
				nameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
				nameStroke.Color = Color3.fromRGB(30, 30, 30)
			else
				nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				nameStroke.Color = Color3.fromRGB(18, 16, 26) -- INK
			end
		end
	end
	if owner then
		owner:GetAttributeChangedSignal("WornNamePlate"):Connect(updateNamePlate)
		updateNamePlate()
	end

	local function refresh()
		local ratio = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		-- green -> amber -> red. Colour is read before length is: a bar that only changes length
		-- says "some health", a bar that goes red says "you are about to die".
		UITheme.SetColor(fill, ratio > 0.5 and UITheme.Color.Green
			or (ratio > 0.22 and UITheme.Color.Sunny or UITheme.Color.Red))
		-- Clearance over the COSTUME, not over the avatar. The head this hangs on is invisible inside
		-- a shell about 1.18x its largest axis, lifted a tenth of that again, and several stages put a
		-- crown or horns on top of THAT -- so the old 1.5x of the bare head left the plate inside the
		-- character's skull at every stage. Still measured off the head rather than set as a constant:
		-- the body runs 1x to 9x across the twenty stages.
		gui.StudsOffset = Vector3.new(0, head.Size.Y * 1.35 + 1.6, 0)

		if ratio < 1 then
			bar.Visible = true
			hideAt = 0
		elseif bar.Visible and hideAt == 0 then
			hideAt = os.clock() + PLATE_HIDE_DELAY
			task.delay(PLATE_HIDE_DELAY + 0.05, function()
				if gui.Parent and hideAt ~= 0 and os.clock() >= hideAt then
					bar.Visible = false
					hideAt = 0
				end
			end)
		end
	end

	-- DAMAGE TAKEN, WRITTEN ON THE PLAYER.
	--
	-- Being hit used to print "Ouch! -30 HP" as a screen banner, which was the most frequent thing
	-- on screen in a fight and sat nowhere near the character it was about. A creature's damage
	-- already floats off the creature; a player's should float off the player, in red, right beside
	-- the bar that is dropping -- one place to look, and the number and the bar agree.
	--
	-- Driven off HealthChanged rather than off a remote: the drop is already replicated, so this
	-- catches EVERY source (a Brute's retaliation, an Elite's aura, a boss, a fall) without any of
	-- them having to know about it.
	-- The local player only. This function runs for every character in the game (see hookCharacters)
	-- and the plate is worth drawing over all of them, but a number for every hit every other player
	-- takes is someone else's fight reported on your screen.
	if Players:GetPlayerFromCharacter(character) == player then
		local lastHealth = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			local lost = lastHealth - health
			lastHealth = health
			-- only real damage. A heal is a rise, and a sub-1 drop is rounding, not a hit.
			if lost >= 1 and health > 0 then
				local at = head.Position + Vector3.new(0, head.Size.Y * 1.1, 0)
				popNumber(at, "-" .. shortNumber(lost), Color3.fromRGB(255, 116, 108), false)
				-- guarded by the same local-player check the number is, and for the same reason: every
				-- hit every other player takes is someone else's fight reported in your ears
				SoundLibrary.Play("hurt", head)
			end
		end)
	end

	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	refresh()
end

local function hookCharacters(plr)
	if plr.Character then
		task.spawn(attachHealthPlate, plr.Character)
	end
	plr.CharacterAdded:Connect(function(character)
		task.spawn(attachHealthPlate, character)
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do
	hookCharacters(plr)
end
Players.PlayerAdded:Connect(hookCharacters)

-- ============================================================================
-- SPRINT
-- ============================================================================
--
-- Shift to run. The base speed is whatever the server last set (it scales with the body and with
-- Stage Mastery), so this multiplies rather than assigns: hard-coding a sprint speed would make a
-- Cell faster than an Alien the moment they held Shift.
--
-- The base is re-read whenever the server changes WalkSpeed while we are NOT sprinting -- that is
-- what keeps an evolve mid-sprint from being clamped back to the old stage's pace on release.
local SPRINT_MULT = 1.4
local sprinting = false
local sprintHumanoid = nil
local baseSpeed = 16
local writing = false

local function applySpeed()
	if not sprintHumanoid or sprintHumanoid.Parent == nil then return end
	writing = true
	sprintHumanoid.WalkSpeed = sprinting and baseSpeed * SPRINT_MULT or baseSpeed
	writing = false
end

local function bindSprint(character)
	-- An evolve moves every joint attachment with the body scale, so a swing set captured before it
	-- is stale. Dropped here rather than inside playSwing so a character that stops swinging across
	-- an evolve still ends up standing straight.
	character:GetAttributeChangedSignal("BodyScale"):Connect(function()
		resetSwing(character)
	end)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	sprintHumanoid = humanoid
	baseSpeed = humanoid.WalkSpeed
	sprinting = false
	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if writing then return end
		-- someone else (the server, on spawn / evolve / mastery) moved it
		baseSpeed = sprinting and humanoid.WalkSpeed / SPRINT_MULT or humanoid.WalkSpeed
	end)
end

if player.Character then
	task.spawn(bindSprint, player.Character)
end
player.CharacterAdded:Connect(function(character)
	task.spawn(bindSprint, character)
end)

-- ============================================================================
-- AUTO-ATTACK
-- ============================================================================
--
-- Off by default and toggled by the "Auto" tile in the HUD or by the T key. The state lives on
-- ONE thing -- `player:GetAttribute("AutoAttack")` -- rather than in either script: MainUI draws
-- the tile and flips the attribute, this script reads it and does the fighting, and neither has
-- to know the other is there. Whichever of them changes it, both see the change.
--
-- A ClickDetector cannot be fired by code, so this cannot reuse the click path: it names the
-- model it wants hit over Remotes.AutoAttack and the server validates and applies it, through the
-- exact same handler a click lands in. The cooldowns, the retaliation and the DNA are therefore
-- identical -- auto-attack is not a second set of combat rules, it is a second set of fingers.
-- A beat longer than the swing, not shorter. At 0.2 the next request landed before the previous
-- swing had recovered, so the arms never returned to rest and auto-attack read as a body thrashing
-- rather than as a character hitting something repeatedly.
local AUTO_INTERVAL = 0.34
-- 60, UP FROM 34, and the reason is a measurement rather than a preference. At 34 studs
-- centre-to-centre auto-attack essentially never found anything: the nearest creature to the
-- Forest spawn is 109 studs away, so a player with the toggle ON walked around watching it do
-- nothing, which is exactly the "auto-attack does not work at all" report. The wiring was never
-- broken -- a Brute died in two seconds the moment one was inside 34.
--
-- 34 came from the opposite complaint: at 55 it picked fights with creatures the player had not
-- walked up to. That complaint is now answered by the CLICK reach instead, which is melee
-- (CreatureService's clickReach, ~20-32 studs) and is what "fighting range" means to a player.
-- Auto-attack is the convenience feature and is allowed to sweep wider than your arm.
--
-- It is NOT scaled by the player's body -- nothing in combat is, on either side -- so the number
-- is read at face value in world studs at every stage.
--
-- KEEP THIS IN STEP WITH THE SERVER. CreatureService gates auto-attack at
-- `max(clickReach + 4, 60) + tier.size`, i.e. 66.5 for a Swarmer up to 86 for an Elite. 60 sits
-- inside the tightest of those, so a legitimate auto-attack at the edge of the client's scan is
-- never refused -- and raising this past 60 without raising the server's floor would silently
-- start dropping blows the player can see themselves make.
--
-- Bosses keep 70, and that is not an oversight -- but the reason written here was wrong about the
-- bodies, and the correction is a measurement (15.21, closed 2026-08-16). "75 to 121 studs across"
-- understates them: Boss_Desert's SOLID geometry measures 160 x 180 and its invisible HitBox is
-- 173 x 173, so 70 studs from the anchor is 20-odd studs INSIDE the silhouette, not "barely clear".
--
-- 70 is still right, and the part that settles it is the COLLISION hull rather than the drawing:
-- exactly one part in a boss collides (BossCollision, 64 studs across), so a player walking at a
-- boss is stopped at 32 + their own half-width (16.3 at max stage) = ~48 studs from the anchor.
-- That is 22 studs INSIDE this reach, so auto-attack has already engaged by the time the player
-- physically cannot get any closer -- which is the only test that matters. Measured live: a
-- standoff of 68.9 studs killed Boss_Forest (750 hp) without the character moving a single stud.
--
-- If a boss is ever given a wider collision hull, THIS number has to move with it. The rule is
-- `reach > BossCollision/2 + player half-width`, not a fraction of the model's drawn size.
--
-- ===== 15.21: THESE WERE 22 AND 32 FOR A DAY, AND THE MEASUREMENT THAT SETTLES IT =====
--
-- A "tighten combat to true melee, under 10 meters" pass cut this pair to { 22, 32 } and cut the
-- server's two reaches to match. The report it produced was exact: *"auto attack is too close now,
-- I have to stand in the core of the mob to kill it"*. It is arithmetic, not taste, and the number
-- nothing on this path had ever measured is the PLAYER's own body:
--
--   * a max-stage character's bounding box measures 30.7 x 42.9 x 27.1 studs, so its half-width
--     from the HumanoidRootPart -- the point this reach is measured FROM -- is 15.4;
--   * a Critter's own box is ~22 studs wide, i.e. 11 from its centre -- the point it is measured TO.
--
-- So at 22 the two bodies had to OVERLAP by about 4 studs before the client would nominate a
-- target, and against a Swarmer the gap left was 0.6 studs. At 60 the same player stands 33 studs
-- clear. Bosses were worse and were unreachable rather than tight: a boss is 75-121 studs across,
-- so 32 studs from its centre is *inside its model* at every zone in the game.
--
-- A distance in meters is not the unit this game is played in. Everything on this path -- the reach,
-- the rig sizes, the player's own body -- is authored in studs, and the player's body is the thing
-- that grew twenty times over the course of a save. Convert nothing; measure both bodies.
--
-- ===== AND `Training`, WHICH IS THE DUMMY'S ONLY WAY IN (33.21) =====
--
-- `nearestTarget` scans the folders in THIS TABLE and no others, so a prop that is not named here
-- cannot be auto-attacked however close the player stands -- which is exactly why the earlier,
-- unshipped `GrottoDummyService` parented into `workspace.Map.Props`, connected a handler, and could
-- never fire it.
--
-- 45 rather than 60: the dummy stands still, so none of the lead a walking creature needs applies.
-- The server's own gate is 48, deliberately looser than this -- see the note over `AUTO_GATE` in
-- `TrainingDummyService` for why a server gate at or under the client's reach silently eats every
-- blow thrown at the edge of it.
local AUTO_REACH = { Creatures = 60, Bosses = 70, Training = 45 }

-- ===== THE REBIRTH LOCK, AS SEEN FROM HERE (11.6) =====
--
-- The terrace creatures are gated on rebirth count now. NOTHING IN THIS FILE IS AUTHORITATIVE --
-- CreatureService re-derives the same answer from the creature's own spawn layer on every blow, and
-- that check is the real one. This exists so the lock is legible and so auto-attack does not spend
-- the player's swing on something the server is going to refuse. Same split as RebirthShrineClient,
-- whose header states it at length.
--
-- The client can answer this at all only because `spawnCreature` publishes `MinRebirths` as a
-- replicated attribute; before 11.6 a terrace Brute and a valley Brute were indistinguishable here.
local myRebirths = 0

local function creatureLocked(model)
	local need = model:GetAttribute("MinRebirths")
	return need ~= nil and myRebirths < need
end

local function autoEnabled()
	if player:GetAttribute("AutoAttack") ~= true then return false end
	-- A CORPSE DOES NOT FIGHT. The server refuses the blow now whatever the client sends, but a
	-- dead player whose arms keep swinging at a creature that never loses health reads as the game
	-- being broken rather than as the player being dead.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Nearest thing in reach, creatures and bosses alike. Nearest rather than "whatever the mouse is
-- over": the whole point of the toggle is that the player stops aiming, and a boss standing in the
-- middle of its arena should be attacked because you walked up to it, not because you held still.
local function nearestTarget()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local at = hrp.Position

	local best, bestDist = nil, math.huge
	for folderName, reach in pairs(AUTO_REACH) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			-- With StreamingEnabled a client only ever holds the corner of the strip it is standing
			-- in, so this is a handful of models per tick, not the hundreds that exist on the server.
			--
			-- The IsA check is load-bearing: these folders are NOT only creatures. deathBurst parents
			-- its confetti host and its ground shockwave straight into workspace.Creatures beside the
			-- corpse, and `somePart.PrimaryPart` is a hard error, not nil -- which killed this whole
			-- loop on the first creature anyone anywhere in the server managed to kill.
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					-- ===== A CORPSE IS NEARER THAN THE THING THAT KILLED IT =====
					--
					-- This is the whole "auto-attack does nothing when I am standing right next to a
					-- creature" report, and it is a targeting bug rather than a combat one. A dead
					-- creature stays parented for its death animation, and `playDeath` has already
					-- dropped it from `hitHandlers` -- so the server correctly discards every blow aimed
					-- at it. Without a liveness test here the client kept picking it anyway, because it
					-- is the NEAREST model: measured live in a three-creature cluster, **5 of 8 swings
					-- went at a corpse 13.8 studs away while a live Swarmer stood at 20.7**, and the
					-- player saw a creature in front of them losing no health at all.
					--
					-- `Health` is a replicated attribute, which is what makes this answerable on the
					-- client at all. It also rejects two other things cheaply and correctly:
					--   * the ~1,190 creature models whose parts are streamed out (attribute present,
					--     no body) -- already skipped by the part test below, now skipped sooner
					--   * anything in this folder that is not a creature. deathBurst parents its
					--     confetti host and ground shockwave straight into workspace.Creatures, and
					--     those carry no Health at all.
					-- ...and a creature this save may not touch is not a target either (11.6). The
					-- server would refuse every one of these blows, so without this the auto-attack
					-- would lock onto a sealed Apex standing three studs away and the player would
					-- watch their own swings do nothing -- which is exactly the corpse bug above,
					-- wearing a different hat.
					local hp = model:GetAttribute("Health")
					if hp and hp > 0 and not creatureLocked(model) then
						local part = model.PrimaryPart or model:FindFirstChild("Body")
						if part then
							local d = (part.Position - at).Magnitude
							if d <= reach and d < bestDist then
								best, bestDist = model, d
							end
						end
					end
				end
			end
		end
	end
	return best
end

if player:GetAttribute("AutoAttack") == nil then
	player:SetAttribute("AutoAttack", false)
end

task.spawn(function()
	-- ===== WAITING FOR THE REMOTE MUST NOT BE A ONE-SHOT =====
	--
	-- This used to `return` after a 30 s timeout, which killed auto-attack for the WHOLE SESSION on
	-- one slow server boot, with a `warn` nobody sees and a toggle that silently did nothing
	-- afterwards. The remote is created when ServerMain requires CreatureService, so anything that
	-- delays the server past 30 s -- a cold start, a world rebuild, a hitch -- used to be permanent.
	-- Keep retrying; the loop below costs nothing while it has no remote.
	local autoRemote
	while not autoRemote do
		autoRemote = RS:WaitForChild("Remotes"):WaitForChild("AutoAttack", 30)
		if not autoRemote then
			warn("[CombatClient] Remotes.AutoAttack has not appeared yet -- still waiting")
		end
	end
	while true do
		-- The Fast Auto Attack pass shortens the gap between swings. Read off a player ATTRIBUTE rather
		-- than off the data table: the server owns pass ownership and stamps the finished multiplier
		-- here, so this script never has to know what a pass is, and a purchase mid-session takes
		-- effect on the very next swing with nothing to re-wire. 1 when nothing is owned.
		-- Floored at SWING_TIME so the loop can never re-cut a swing faster than one can play.
		local autoMult = player:GetAttribute("AutoSpeedMult")
		if type(autoMult) ~= "number" or autoMult <= 0 then autoMult = 1 end
		task.wait(math.max(AUTO_INTERVAL / autoMult, SWING_TIME))
		if autoEnabled() then
			-- pcall'd on purpose. This is an unattended loop with no second chance: anything that
			-- throws inside it ends auto-attack for the rest of the session, silently, and the
			-- player's only symptom is a toggle that does nothing.
			local ok, target = pcall(nearestTarget)
			if not ok then
				warn("[CombatClient] auto-attack target scan failed: " .. tostring(target))
			elseif target then
				autoRemote:FireServer(target)
				-- fired locally for the same reason a clicked swing is: the animation has to start on
				-- this frame, and a round trip is a third of the swing
				playSwing(player.Character)
			end
		end
	end
end)

-- ============================================================================
-- INPUT
-- ============================================================================

-- A click only swings at something worth swinging at -- swinging on every click in the world would
-- fire the animation at every shop prompt, egg and UI dismissal in the game.
--
-- This casts its OWN ray rather than reading `Mouse.Target`, and the filter is an *include* list of
-- the two combat folders. Two things that matters for:
--
--   * Mouse.Target is whatever queryable part the cursor happens to be over, and a zone is full of
--     large invisible carriers -- the atmosphere sheet is 640 x 800 studs of it at head height,
--     and until it was made CanQuery = false it WAS the answer everywhere in the game. An include
--     filter cannot be fooled by anything that is not a creature.
--   * a hit anywhere on the rig counts. The ClickDetectors sit on the body and the head; a ray
--     that lands on a horn or a wing still means the player is aiming at the creature, and the
--     swing should play whether or not that particular part was the clickable one.
--
-- The reach is deliberately generous. A swing that plays a little out of range costs nothing; one
-- that refuses to play because the player was a stud too far reads as an input that was dropped.
local SWING_REACH = 400
local swingParams = RaycastParams.new()
swingParams.FilterType = Enum.RaycastFilterType.Include
swingParams.RespectCanCollide = false

local function pointingAtCombatTarget()
	local cam = workspace.CurrentCamera
	if not cam then return false end

	local folders = {}
	local creatures = workspace:FindFirstChild("Creatures")
	if creatures then table.insert(folders, creatures) end
	local bosses = workspace:FindFirstChild("Bosses")
	if bosses then table.insert(folders, bosses) end
	if #folders == 0 then return false end
	swingParams.FilterDescendantsInstances = folders

	-- GetMouseLocation is the one that pairs with ViewportPointToRay: it already carries the GUI
	-- inset, which Mouse.X/Y do not (they are 58 px out at the top of a Studio window).
	local at = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(at.X, at.Y)
	return workspace:Raycast(ray.Origin, ray.Direction * SWING_REACH, swingParams) ~= nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.T and not processed then
		-- Toggles the RAW attribute, not `autoEnabled()`. `autoEnabled()` also returns false while
		-- the player is dead, so `not autoEnabled()` was always `true` on a corpse -- pressing T
		-- while dead could only ever switch auto-attack ON, and it could never be switched off again
		-- until you respawned. The attribute is the setting; `autoEnabled()` is whether it may act.
		player:SetAttribute("AutoAttack", player:GetAttribute("AutoAttack") ~= true)
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		-- not gated on `processed`: releasing over a text box would otherwise leave the player
		-- sprinting for the rest of the session
		sprinting = true
		applySpeed()
		return
	end
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if pointingAtCombatTarget() then
		playSwing(player.Character)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprinting = false
		applySpeed()
	end
end)

-- ============================================================================
-- THE SERVER'S SIDE OF IT
-- ============================================================================

local CombatFx = RS:WaitForChild("Remotes"):WaitForChild("CombatFx", 30)
if not CombatFx then
	warn("[CombatClient] Remotes.CombatFx never appeared -- hits will not draw")
	return
end

-- When something last drew a number near this player. Declared up here rather than beside its one
-- reader at the bottom of the file, because the writer is the handler below and a local declared
-- after its writer is a different variable (a global, in Luau's reading of it).
local lastFxAt = 0

-- ============================================================================
-- THE BOSS BAR
-- ============================================================================
--
-- A boss wears a name plate at `top + size * 0.18` studs -- about 145 up on the Forest bear. That
-- is the right place for it while you are walking toward the thing, and it is off the top of the
-- screen the moment you are close enough to swing. Lowering it does not fix it: a plate low enough
-- to read from the feet is inside the rig.
--
-- So the fight gets a screen-space bar, which is what the boss's health actually is -- a readout,
-- not an object in the world. It appears when you hit a boss and fades a few seconds after you
-- stop, so it is never chrome sitting on the screen while you farm creatures.
local BOSS_BAR_HOLD = 5

-- The last zone's boss has 68 800 000 health, so a bar printed raw reads "68800000 / 68800000" --
-- eight digits twice over, in a strip a few hundred pixels wide. (The comment this replaces said
-- "trillions" and quoted 1 284 000 000 000; the real ladder runs 800 in Forest to 68.8M in
-- AbsolutePlane, which is four orders short. Worth abbreviating either way, but the figure was
-- wrong and someone would have sized something against it.)
--
-- It shares `shortNumber` with the damage numbers rather than keeping its own copy: the bar and the
-- number coming off the boss are the same fight, so they have to abbreviate the same way. (MainUI's
-- `formatNumber` is a local in a 6000-line LocalScript this file cannot see, which is why neither
-- of them is used from there.)
local barNumber = shortNumber

local bossBar, bossBarFill, bossBarLabel, bossBarName
local bossBarUntil = 0

local function ensureBossBar()
	if bossBar then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BossBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 30
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	-- top-centre, clear of the Roblox topbar and of this game's own stage card
	holder.Size = UDim2.new(0, 520, 0, 74)
	holder.Position = UDim2.new(0.5, 0, 0, 96)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	-- fits a phone: the bar is the one thing that must never be wider than the screen
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local cam = workspace.CurrentCamera
	local function fit()
		if cam then
			scale.Scale = math.clamp((cam.ViewportSize.X - 40) / 520, 0.5, 1)
		end
	end
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	fit()

	bossBarName = Instance.new("TextLabel")
	bossBarName.Size = UDim2.new(1, 0, 0, 28)
	bossBarName.BackgroundTransparency = 1
	bossBarName.Font = UITheme.Font.Display
	bossBarName.TextScaled = true
	bossBarName.TextColor3 = Color3.fromRGB(255, 255, 255)
	bossBarName.Parent = holder

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 3
	nameStroke.Color = INK
	nameStroke.LineJoinMode = Enum.LineJoinMode.Round
	nameStroke.Parent = bossBarName

	-- A PILL, like every other bar in the game. This one asked for a 14 px box, which made it the
	-- only rounded-RECTANGLE health bar on the screen -- and the one shape `applyShell` still puts a
	-- dark lip under, so it wore two black caps where the lip swung out past its corners. Bars are
	-- the archetype the Pill step exists for; there is no reason for this one to be the exception.
	local _bar, fill, label = UITheme.ProgressBar(holder, {
		name = "Bar",
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.new(0, 0, 1, 0),
		anchorPoint = Vector2.new(0, 1),
		radius = UITheme.Radius.Pill,
		thickness = 4,
		progress = 1,
		color = UITheme.Color.Red,
		text = "",
		maxTextSize = 22,
	})
	bossBar, bossBarFill, bossBarLabel = holder, fill, label
end

local function showBossBar(name, hp, max)
	ensureBossBar()
	local ratio = max > 0 and math.clamp(hp / max, 0, 1) or 0
	bossBarName.Text = name
	bossBarFill.Size = UDim2.new(ratio, 0, 1, 0)
	bossBarLabel.Text = barNumber(hp) .. " / " .. barNumber(max)
	-- red down to amber as it falls, the same signal the player's own plate uses
	UITheme.SetColor(bossBarFill, ratio > 0.5 and UITheme.Color.Red
		or (ratio > 0.2 and UITheme.Color.Sunny or UITheme.Color.Gold))
	bossBar.Visible = true
	bossBarUntil = os.clock() + BOSS_BAR_HOLD
	task.delay(BOSS_BAR_HOLD + 0.05, function()
		if bossBar and os.clock() >= bossBarUntil then
			bossBar.Visible = false
		end
	end)
end

-- ===== THE REVIVE OFFER =====
--
-- It lives in THIS file and not in MainUI for two reasons. The boss bar's ScreenGui above is built
-- with ResetOnSpawn = false, which is exactly the lifetime a "you died -- want your progress back?"
-- card needs: it has to survive the death that triggered it and the respawn that follows. And this
-- file is nowhere near Luau's 200-local register cap that MainUI is pinned against.
--
-- The card never decides anything. The server has already checked that a snapshot exists, that it
-- is inside the TTL and that the boss is still standing; pressing the button either spends a charge
-- the player owns or opens the purchase prompt, and the server re-checks all of it either way.
local reviveCard, reviveLabel, reviveButton
local reviveHeld = 0
-- Resolved once, here, rather than indexed inside the click handler: UseBossRevive is created by
-- BossService at module load and PromptRobuxPurchase by the Remotes folder itself, so both exist
-- long before a player can die -- but a nil index inside a button handler is a silent dead button,
-- and a warn on boot is a bug someone can actually see.
local remotesFolder = RS:WaitForChild("Remotes")
local useReviveRemote = remotesFolder:WaitForChild("UseBossRevive", 30)
if not useReviveRemote then
	warn("[CombatClient] Remotes.UseBossRevive never appeared -- the revive offer is disabled")
end
-- mirrors GameConfig.BossReviveTTL, read from the module so the card and the server cannot disagree
-- about how long an offer is good for
local REVIVE_TTL = require(RS:WaitForChild("Modules"):WaitForChild("GameConfig")).BossReviveTTL

local function hideReviveOffer()
	if reviveCard then reviveCard.Visible = false end
end

local function showReviveOffer(name, pct, held)
	ensureBossBar()
	reviveHeld = held or 0
	if not reviveCard then
		-- parented to the ScreenGui rather than to the bar's holder: the bar hides itself a few
		-- seconds after the last blow, and this has to outlive it
		local gui = bossBar.Parent
		reviveCard = Instance.new("Frame")
		reviveCard.Name = "ReviveOffer"
		reviveCard.Size = UDim2.new(0, 520, 0, 96)
		reviveCard.Position = UDim2.new(0.5, 0, 0, 182)
		reviveCard.AnchorPoint = Vector2.new(0.5, 0)
		reviveCard.BackgroundTransparency = 1
		reviveCard.Parent = gui

		reviveLabel = Instance.new("TextLabel")
		reviveLabel.Size = UDim2.new(1, 0, 0, 30)
		reviveLabel.BackgroundTransparency = 1
		reviveLabel.Font = UITheme.Font.Display
		reviveLabel.TextScaled = true
		reviveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		reviveLabel.Parent = reviveCard

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = INK
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = reviveLabel

		reviveButton = UITheme.Button(reviveCard, {
			name = "ReviveButton",
			size = UDim2.new(0, 300, 0, 54),
			position = UDim2.new(0.5, 0, 1, 0),
			anchorPoint = Vector2.new(0.5, 1),
			color = UITheme.Color.Gold,
			text = "REVIVE",
		})
		-- SPENDS A CHARGE, NEVER SELLS ONE (11.7). The other half of this used to open a purchase
		-- prompt for anyone with none -- that was the whole point of the card, and it is the "revive
		-- UI" the withdrawal removes. The server now only offers this card to a save that already
		-- holds a charge, so the branch had nothing left to do but sell something unbuyable.
		reviveButton.MouseButton1Click:Connect(function()
			hideReviveOffer()
			if reviveHeld > 0 and useReviveRemote then
				useReviveRemote:FireServer()
			end
		end)
	end

	reviveLabel.Text = ("\u{2620}\u{FE0F} %s was at %d%%"):format(name, pct)
	-- no "or REVIVE BOSS" arm any more: the card is only sent to a save that holds a charge (11.7),
	-- so the count is always real and the button never advertises something that cannot be bought
	UITheme.SetText(reviveButton, ("\u{2694}\u{FE0F} REVIVE  (%d left)"):format(reviveHeld))
	reviveCard.Visible = true

	-- The offer expires with the snapshot behind it. A button that is still on screen after the
	-- server has forgotten why is a button that answers "nothing to restore".
	task.delay(REVIVE_TTL, hideReviveOffer)
end

CombatFx.OnClientEvent:Connect(function(fx)
	if type(fx) ~= "table" then return end
	-- handled before the Vector3 check: a bar update carries no position, it is not a hit at a place
	if fx.k == "bossBar" then
		if type(fx.hp) == "number" and type(fx.max) == "number" then
			showBossBar(tostring(fx.name or "Boss"), fx.hp, fx.max)
		end
		-- a bar update means the fight is live again, so a stale offer card comes down
		hideReviveOffer()
		return
	end
	if fx.k == "reviveOffer" then
		showReviveOffer(tostring(fx.name or "The boss"), tonumber(fx.pct) or 0, tonumber(fx.held) or 0)
		return
	end
	-- ===== THE TRAINING DUMMY (33.21) =====
	--
	-- Its own kind rather than a `hit` with no `d`, and the difference is not cosmetic: the general
	-- path below plays other players' swings, sparks for everyone in FX range and kicks the camera.
	-- A dummy is only ever hit by the one player who is standing at it and is only ever sent to that
	-- player, so all of that is noise -- and `SoundLibrary.Play("hit")` on a 0.25 s drum would be
	-- four overlapping copies a second.
	--
	-- The number rises with HER OWN ART beside it: *"ovaj biceps znak kao da iskace i pise koliko
	-- damagea je player dobio"*. `IconLibrary.Id.training` is that Decal.
	if fx.k == "train" then
		if typeof(fx.p) ~= "Vector3" then return end
		if fx.a ~= player.UserId then return end
		spark(fx.p, UITheme.Color.Gold, fx.s or 8, false)
		SoundLibrary.Play("hit", fx.p)
		local gained = tonumber(fx.tr) or 0
		if gained > 0 then
			popNumber(fx.p, "+" .. shortNumber(gained), UITheme.Color.Gold, false, IconLibrary.Id.training)
		end
		cameraKick(0.5)
		lastFxAt = os.clock()
		return
	end
	if typeof(fx.p) ~= "Vector3" then return end
	local kill = fx.k == "kill"
	local mine = fx.a == player.UserId

	-- Stamped for the idle-income pop at the bottom of this file, which stands down while a fight
	-- is on. Every hit near the player counts, not only their own: somebody else's Elite dying two
	-- studs away is still a screen with numbers on it.
	lastFxAt = os.clock()

	-- our own swing already played off the mouse button; this is what makes everyone else's
	-- characters swing on our screen
	if not mine and fx.a then
		local other = Players:GetPlayerByUserId(fx.a)
		if other and other.Character then
			playSwing(other.Character)
		end
	end

	spark(fx.p, fx.c, fx.s, kill)

	-- At the impact, never on the listener: this payload is broadcast to everyone inside FX_RADIUS,
	-- so a fight two platforms over should be faint rather than absent. Both entries carry a minGap,
	-- which is what stops an Elite's aura killing six Swarmers on one frame from stacking six copies
	-- of the same wav into a clipping wall.
	if kill then
		SoundLibrary.Play("death", fx.p)
	elseif fx.d and fx.d > 0 then
		SoundLibrary.Play("hit", fx.p)
	end

	if mine then
		-- before the DNA pop, so the two numbers do not start on the same frame in the same place:
		-- the crystal spends its first four tenths of a second climbing out of the corpse while the
		-- DNA figure rises off it, and its own "+1" is drawn a second later at the player
		if kill and fx.sh then
			shardPickup(fx.p, fx.s)
		end
		if kill and fx.dna then
			-- A CRIT IS THE SAME NUMBER IN A DIFFERENT VOICE (15.14). It is not a second pop and it
			-- is not a toast: the payout is already being drawn over the corpse, so the crit is that
			-- draw wearing gold and saying so. `SoundLibrary.crit` is a positional entry (dist 160)
			-- and has never been played by anything until now.
			if fx.cr then
				SoundLibrary.Play("crit", fx.p)
				popNumber(fx.p, "\u{1F4A5} CRIT +" .. shortNumber(fx.dna) .. " \u{1F9EC}", UITheme.Color.Gold, true)
			else
				popNumber(fx.p, "+" .. shortNumber(fx.dna) .. " \u{1F9EC}", UITheme.Color.Mint, true)
			end
			-- ===== AND THE TRAINING REP THE KILL PAID (33.21) =====
			--
			-- A SECOND POP, deliberately, where the shard and the crit are folded into the first
			-- one. The reason they differ: a crit is the same number in a different voice and the
			-- shard is drawn as an object flying out of the corpse, but this is a different
			-- CURRENCY going to a different bar, and a player who cannot see it move will not
			-- believe the bar filled from kills at all.
			--
			-- Offset up and started a beat late so the two numbers do not launch on the same frame
			-- from the same point -- `popNumber`'s own per-pop drift handles the rest, and the DNA
			-- figure is drawn `big` while this one is not, so they never read as one string.
			if fx.tr then
				local reps = tonumber(fx.tr) or 0
				if reps > 0 then
					task.delay(0.14, function()
						popNumber(fx.p + Vector3.new(0, 4, 0), "+" .. shortNumber(reps),
							UITheme.Color.Gold, false, IconLibrary.Id.training)
					end)
				end
			end
		elseif fx.d and fx.d > 0 then
			popNumber(fx.p, "-" .. shortNumber(fx.d), Color3.fromRGB(255, 236, 168), false)
		end
		cameraKick(kill and 1.5 or 0.7)
	end
end)

-- ===== DRAWING THE REBIRTH LOCK ON THE CREATURE ITSELF (11.6) =====
--
-- A creature the player may not fight has to LOOK unfightable, or the only feedback is a swing that
-- does nothing -- and "I hit it and nothing happened" is the exact complaint this whole file was
-- written to answer. So the plate above a sealed creature says what it wants instead of how much
-- health it has, and the body goes to stone.
--
-- Modelled on RebirthShrineClient, including the parts that look like details and are not:
--
--   * THE ORIGINAL LOOK IS CACHED BEFORE THE FIRST REPAINT, per part, so unlocking restores what the
--     server actually built rather than a guess. Two greys chosen by luminance rather than one flat
--     grey, or the silhouette disappears and every zone's creatures become the same blob.
--   * POLLED, NOT EVENTED. With StreamingEnabled a creature model replicates before its parts do, so
--     a one-shot pass at spawn paints a shell. Re-running over the handful of models a client
--     actually holds is cheap and self-healing, and it is also what repaints a respawn.
--   * The state is recomputed from `myRebirths` every pass rather than remembered, so the moment a
--     rebirth lands every creature in sight unlocks itself with no bookkeeping.
local LOCK_STONE = Color3.fromRGB(120, 122, 132)
local LOCK_STONE_DARK = Color3.fromRGB(74, 76, 86)

-- ===== NO CACHE. THE ORIGINAL LIVES ON THE THING ITSELF =====
--
-- The first version of this kept a weak table of "what did this part look like before I greyed it".
-- That is what RebirthShrineClient does and it is correct THERE, because a shrine is four models
-- that never move. A creature is not: it stands at the edge of the streaming radius, so its parts
-- leave and come back, the cache misses, and the next pass records the ALREADY PAINTED look as the
-- original. Measured on one Apex: a plate reading its own lock line 34 times over, and a body that
-- would have restored to grey rather than to its own colour on unlock.
--
-- So nothing is remembered off to the side. The pristine name is published by the server
-- (`PlateName`), and each part carries its own original colour in an attribute written the first
-- time it is painted. Both survive exactly as long as the thing they describe -- a part that streams
-- out and back is a NEW part, replicated fresh from the server, with its true colour and no
-- attribute, which is precisely the right state to be in. **A repaint is idempotent by
-- construction, and "the cache went stale" stops being a failure mode that exists.**
--
-- THE GUARD IS PER PART, NOT PER MODEL, and that is the second thing streaming decides. A model-wide
-- "already painted" flag would skip the whole creature -- including the parts that streamed back in
-- pristine while it was skipped -- and leave a half-grey Apex standing there. Asking each part
-- whether IT has been done is the same question at the right granularity, and it costs one attribute
-- read on a few hundred parts a second.
local function paintLock(model, locked)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if locked then
				if d:GetAttribute("LockOrigColor") == nil then
					d:SetAttribute("LockOrigColor", d.Color)
					d:SetAttribute("LockOrigMaterial", d.Material.Name)
					-- two greys by luminance, not one flat grey: a single tone erases the silhouette
					-- and every zone's creatures become the same blob. Same rule as the shrine.
					local lum = d.Color.R * 0.3 + d.Color.G * 0.6 + d.Color.B * 0.1
					d.Color = lum > 0.45 and LOCK_STONE or LOCK_STONE_DARK
					d.Material = Enum.Material.Slate
				end
			else
				local c = d:GetAttribute("LockOrigColor")
				if c then
					d.Color = c
					d.Material = Enum.Material[d:GetAttribute("LockOrigMaterial") or "Plastic"]
					d:SetAttribute("LockOrigColor", nil)
					d:SetAttribute("LockOrigMaterial", nil)
				end
			end
		end
	end

	local plate = model:FindFirstChild("CreaturePlate", true)
	local label = plate and plate:FindFirstChild("TextLabel")
	local pristine = model:GetAttribute("PlateName")
	if label and pristine then
		if locked then
			local need = model:GetAttribute("MinRebirths") or 0
			label.Text = ("\u{1F512} %s \u{2014} %d %s"):format(
				pristine, need, need == 1 and "rebirth" or "rebirths")
		else
			label.Text = pristine
		end
	end
end

task.spawn(function()
	while true do
		local folder = workspace:FindFirstChild("Creatures")
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				-- `MinRebirths` is only ever set on a raised creature, so this skips the valley floor,
				-- the death-burst parts and anything else living in this folder without a second test
				if model:IsA("Model") and model:GetAttribute("MinRebirths") then
					paintLock(model, creatureLocked(model))
				end
			end
		end
		task.wait(1)
	end
end)

-- The two things this file needs off the save. Cached from the payload the economy is already
-- pushing rather than asked for on their own, and the repaint above notices on its next pass.
local myAutoPerSec = 0
do
	local dataRemote = RS:WaitForChild("Remotes", 30)
	dataRemote = dataRemote and dataRemote:WaitForChild("DataUpdate", 30)
	if dataRemote then
		dataRemote.OnClientEvent:Connect(function(data)
			if type(data) == "table" then
				myRebirths = data.Rebirths or 0
				myAutoPerSec = data.__autoPerSec or 0
			end
		end)
	end
end

-- ===== AUTO COLLECT HAS BEEN PAYING INTO A COUNTER THAT CANNOT MOVE (17.4) =====
--
-- The report was *"auto collect nista ne radi"* and the upgrade was working the whole time. Measured
-- on the live save that filed it: `Upgrades.AutoCollect` **67**, and `DNAService`'s loop stamping
-- `__autoPerSec = 5.86e12` DNA every second -- against a balance of **5.09e19**, which the HUD
-- formats to four significant digits as `50.88Qi`. At that rate the last of those digits moves
-- **once every ~28 minutes**. The only place the payout was ever stated is the shop tile's effect
-- line (15.22), and a player has to open a panel to read it. An income you cannot see is
-- indistinguishable from one that is not being paid, and the player is right to call that broken.
--
-- So it is drawn WHERE IT HAPPENS, over the player, in the same voice as every other number this
-- game pays -- see [[evolution-lab-feedback-placement]]. It goes through `popNumber` for exactly
-- the reason that function's own comment gives: a second copy of the look is a second look, and
-- these two numbers -- what a kill pays and what idling pays -- are the ones most likely to be on
-- screen together.
--
-- EVERY FOUR SECONDS, NOT EVERY ONE. The server pays once a second, and one pop a second over your
-- own head for the whole session is not feedback, it is weather. Four seconds of it accumulated
-- into one figure says the same thing, reads as deliberate, and leaves the screen quiet enough that
-- a kill still stands out. It is also the honest number: what is drawn is what has actually been
-- paid since the last draw, never a rate dressed up as a payment.
--
-- MUTED WHILE THE PLAYER IS FIGHTING. `lastFxAt` is stamped by the CombatFx handler, so a pop is
-- skipped whenever a hit landed in the last two seconds: the DNA from a kill is the number that
-- matters at that moment and idle income must not be competing with it in the same square of
-- screen. Standing still is exactly when this has something to say.
local IDLE_POP_EVERY = 4
local IDLE_POP_MUTE_AFTER_FX = 2
task.spawn(function()
	while true do
		task.wait(IDLE_POP_EVERY)
		local amount = myAutoPerSec * IDLE_POP_EVERY
		if amount > 0 and os.clock() - lastFxAt > IDLE_POP_MUTE_AFTER_FX then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				-- Above the HEAD rather than above the root: the body runs 1x to 5x across the
				-- stages and the root is the middle of it, so a fixed offset that clears a Cell is
				-- inside the chest of an Absolute. The head's own top is the only offset that is
				-- right at both ends.
				local head = character:FindFirstChild("Head")
				local top = head and (head.Position.Y + head.Size.Y * 0.5) or (root.Position.Y + root.Size.Y * 0.5)
				popNumber(Vector3.new(root.Position.X, top + 4, root.Position.Z),
					"+" .. shortNumber(amount) .. " \u{1F9EC}", UITheme.Color.Mint, false)
			end
		end
	end
end)
