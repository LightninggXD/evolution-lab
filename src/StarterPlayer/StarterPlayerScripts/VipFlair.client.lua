--[[
	VipFlair -- the part of VIP that other people can see.

	The multipliers are the value; this is the badge, and the badge is most of why anyone buys a
	visible pass at all. Two pieces: a golden aura on the body, and a [VIP] tag in chat.

	Drawn ENTIRELY on the client, off a `IsVIP` player attribute the server stamps. An attribute
	replicates to every client on its own, so no remote is needed and every player sees every other
	player's badge for free.

	THE AURA IS NOT A HIGHLIGHT, and that is the whole design constraint. Roblox renders roughly 31
	Highlights at once; CreatureService already rents fourteen of them for creature outlines and one
	more per hit flash. One Highlight per VIP in a full server would blow that budget and take the
	outlines off every creature in the world -- the single thing the art notes call most important.
	So the aura is particles and a light, which cost nothing from that pool.
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local GOLD = Color3.fromRGB(255, 205, 74)
local AURA_NAME = "VipAura"

-- ============================================================================
-- THE AURA
-- ============================================================================

local function clearAura(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local existing = root:FindFirstChild(AURA_NAME)
	if existing then existing:Destroy() end
end

local function buildAura(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or root:FindFirstChild(AURA_NAME) then return end

	-- SIZED OFF THE BODY, like everything else in this game. The player runs 1x to 5x across the
	-- twenty stages, so a fixed emitter is a bonfire around a Cell and a faint smudge around an
	-- Absolute. BodyScale is stamped on the character by EvolutionVisuals.ApplyStage.
	local scale = character:GetAttribute("BodyScale") or 1

	local host = Instance.new("Attachment")
	host.Name = AURA_NAME
	host.Parent = root

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 246, 214))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1.1 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Rate = 14
	sparks.Speed = NumberRange.new(1.5 * scale, 3.5 * scale)
	-- Rising, and spread across the body rather than pouring out of one point at the navel.
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, 4 * scale, 0)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Parent = host

	local glow = Instance.new("PointLight")
	glow.Color = GOLD
	glow.Brightness = 1.6
	glow.Range = math.clamp(10 * scale, 10, 34)
	glow.Shadows = false
	glow.Parent = host
end

local function refresh(player)
	local character = player.Character
	if not character then return end
	if player:GetAttribute("IsVIP") then
		buildAura(character)
	else
		clearAura(character)
	end
end

local function watch(player)
	-- Three things can invalidate the aura, and all three have to be caught:
	--   the pass arriving or going    -> IsVIP changes
	--   a respawn                     -> CharacterAdded, new HumanoidRootPart
	--   an evolve                     -> BodyScale changes, so the aura is now the wrong size
	player:GetAttributeChangedSignal("IsVIP"):Connect(function()
		refresh(player)
	end)

	local function hookCharacter(character)
		-- The aura is rebuilt rather than resized: it is two instances, and a stale one welded at the
		-- old scale is the same bug the costumes hit when they were built mid-tween.
		character:GetAttributeChangedSignal("BodyScale"):Connect(function()
			clearAura(character)
			refresh(player)
		end)
		refresh(player)
	end

	player.CharacterAdded:Connect(hookCharacter)
	if player.Character then hookCharacter(player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end
Players.PlayerAdded:Connect(watch)

-- ============================================================================
-- THE CHAT TAG
-- ============================================================================
--
-- OnIncomingMessage only exists on the new TextChatService pipeline. A place still on the legacy
-- chat would silently never call this, so the version is checked rather than assumed -- and nothing
-- else in this game touches the callback, so replacing it cannot stamp on anyone.

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")

		local source = message.TextSource
		if not source then return props end

		local speaker = Players:GetPlayerByUserId(source.UserId)
		if speaker and speaker:GetAttribute("IsVIP") then
			-- PrefixText carries the existing name chip, so it is PREPENDED to rather than replaced --
			-- overwriting it drops the speaker's name out of their own message.
			props.PrefixText = '<font color="#FFCD4A">[VIP]</font> ' .. message.PrefixText
		end

		return props
	end
end
