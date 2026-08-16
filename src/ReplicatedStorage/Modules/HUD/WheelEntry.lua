-- WheelEntry -- the free daily spin and the paid spin -- the two doors into the prize wheel (5.6 + 9.4).
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)

local Remotes = RS.Remotes

return function(hud)
	local SECONDS_PER_DAY, dayNumber, rewardPanel = hud.SECONDS_PER_DAY, hud.dayNumber, hud.rewardPanel

	local button = UITheme.Button(rewardPanel, {
		name = "FreeSpin", text = "\u{1F3A1} FREE SPIN", color = UITheme.Color.Gold,
		-- 54 -> 90: at 54 this pair sat INSIDE the accent band, printing over the streak subtitle.
		-- 90 puts them in their own row between the band (ends 82) and the day grid (starts 142).
		size = UDim2.new(0, 220, 0, 42), position = UDim2.new(1, -22, 0, 90),
		anchorPoint = Vector2.new(1, 0), radius = 14,
		zIndex = rewardPanel.ZIndex + 1, maxTextSize = 22,
	})

	-- THE SHARD SPIN SITS BESIDE THE FREE ONE, and that placement is the point (9.4). They are the
	-- same wheel reached by two triggers, so putting them together is what makes the relationship
	-- legible -- free once a day, or 25 Shards whenever you have climbed for them -- where a shard
	-- wheel hidden on some other screen would read as a second, different gamble. It fits in the
	-- band the streak card (ends x262) and the free spin button (starts x458) leave empty, so
	-- nothing already measured on this panel moves.
	local shardButton = UITheme.Button(rewardPanel, {
		name = "ShardSpin", text = "\u{1F3A1} SPIN 25\u{1F31F}", color = UITheme.Color.Locked,
		size = UDim2.new(0, 170, 0, 42), position = UDim2.new(1, -250, 0, 90),
		anchorPoint = Vector2.new(1, 0), radius = 14,
		zIndex = rewardPanel.ZIndex + 1, maxTextSize = 22,
	})

	-- "7h 12m", "12m", "45s" -- the same shape the offline card uses, for the same reason: the
	-- player is reading it for "roughly when", not for the exact second.
	local function countdown(seconds)
		seconds = math.max(math.floor(seconds), 0)
		local h = seconds // 3600
		local m = (seconds % 3600) // 60
		if h > 0 then return ("%dh %dm"):format(h, m) end
		if m > 0 then return ("%dm"):format(m) end
		return ("%ds"):format(seconds)
	end

	-- Held inside this closure rather than as a top-level local: MainUI is at Luau's 200-local
	-- register cap and one more up there deletes the whole HUD. It is also the only thing `refresh`
	-- below needs to know about the nag, so it does not want to be visible any wider.
	local nagUntil = 0

	local function refresh()
		if not hud.getData() then return end
		-- a "not ready yet" message on a button gets one and a half seconds to be read before the
		-- one-second tick below paints the countdown back over it
		if os.clock() < nagUntil then return end
		local ready = dayNumber(os.time()) > dayNumber(hud.getData().LastFreeSpin)
		if ready then
			UITheme.SetColor(button, UITheme.Color.Gold)
			UITheme.SetText(button, "\u{1F3A1} FREE SPIN!")
		else
			-- colour AND wording, like the Auto tile and the mute button: a control that only changes
			-- hue leaves the player guessing whether it is off or just decorated
			UITheme.SetColor(button, UITheme.Color.Locked)
			UITheme.SetText(button, "\u{1F3A1} " .. countdown((dayNumber(os.time()) + 1) * SECONDS_PER_DAY - os.time()))
		end

		-- The shard button reads the same price the server charges (GameConfig.SpinCostShards), so it
		-- can never offer a spin SpendShardSpin will refuse -- the property the evolve button has
		-- against GetEvolveStep and the free spin has against GetFreeSpinStatus.
		--
		-- When it cannot be afforded it shows PROGRESS rather than the price again. "12 / 25" tells a
		-- player who has never seen a shard both what the thing costs and that they are getting
		-- there; a greyed-out "SPIN 25" tells them only that they cannot press it.
		local cost = GameConfig.SpinCostShards
		local held = math.floor(hud.getData().EvolutionShards or 0)
		if held >= cost then
			UITheme.SetColor(shardButton, UITheme.Color.Purple)
			UITheme.SetText(shardButton, ("\u{1F3A1} SPIN %d\u{1F31F}"):format(cost))
		else
			UITheme.SetColor(shardButton, UITheme.Color.Locked)
			UITheme.SetText(shardButton, ("\u{1F31F} %d / %d"):format(held, cost))
		end
	end

	-- A MISSING REMOTE MUST SAY SO. Both spin buttons look their remote up with FindFirstChild
	-- INSIDE the handler -- correct, because RewardService and RobuxShopService create them on
	-- demand and the order is not guaranteed -- but the `if remote then` was silent on the else,
	-- so a button whose service had not finished starting was indistinguishable from a broken one.
	-- That is half of the "claim/spin buttons do not work" report, and it is the half that leaves
	-- no evidence behind.
	--
	-- The message goes ON THE BUTTON rather than through showNotification, and that is a scope fact
	-- rather than a design one: showNotification is declared ~2400 lines below here, so a closure
	-- written at this point captures nil and the click would throw instead of explaining itself.
	local function nagNotReady(target)
		nagUntil = os.clock() + 1.5
		UITheme.SetColor(target, UITheme.Color.Locked)
		UITheme.SetText(target, "\u{23F3} not ready")
	end

	button.MouseButton1Click:Connect(function()
		local remote = Remotes:FindFirstChild("ClaimFreeSpin")
		if remote then
			remote:FireServer()
		else
			nagNotReady(button)
		end
	end)

	-- Fired unconditionally rather than gated on the local affordability check: the client's copy of
	-- the save is up to a push behind, and a button that silently does nothing is worse than the
	-- server's own "you need 25" toast. The server is the one that decides either way.
	shardButton.MouseButton1Click:Connect(function()
		local remote = Remotes:FindFirstChild("SpinWithShards")
		if remote then
			remote:FireServer()
		else
			nagNotReady(shardButton)
		end
	end)

	-- Ticked only while the panel is actually open. A countdown nobody is looking at is a string
	-- rebuild and two property writes a second, forever, on every client in the server.
	task.spawn(function()
		while true do
			task.wait(1)
			if rewardPanel.Visible then
				refresh()
			end
		end
	end)

	-- one handle for both buttons: they are two states of the same question ("can I spin, and how")
	hud.refreshSpins = refresh
end
