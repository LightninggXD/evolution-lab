-- WheelEntry -- the two doors into the prize wheel, on the daily rewards panel (5.6 + 9.4 + 34.46).
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.
--
-- ===== NEITHER BUTTON SPINS ANY MORE (34.46) =====
--
-- They used to fire `ClaimFreeSpin` and `SpinWithShards`, and the wheel appeared already turning.
-- The owner's rule for it -- *"ne odma da vrti, vec da ima opcija da se spina"* -- makes the wheel a
-- place you go rather than a thing that happens to you, so both of these now OPEN THE LOBBY and the
-- spin is pressed in there.
--
--   FREE SPIN  opens the lobby. Opening it is what banks the day's free spin (the lobby fires
--              `RequestSpinLobby` and the server credits one `SpinTickets`), so the readiness this
--              button prints and the thing the press does are still one fact.
--   +1 SPIN 25* still SPENDS, because that one is a purchase rather than a door -- but it BUYS A
--              SPIN now instead of taking one. `SpinWithShards` charges the same 25 and credits one
--              `SpinTickets`, and the lobby is opened alongside it so the player watches the balance
--              they just bought appear. Nothing turns until they press SPIN in there, which is the
--              whole point: the wheel has exactly one trigger and every door merely banks a spin.
--
-- The one thing that did NOT change is who decides: the server still owns readiness, the price and
-- the payout, and this file still prints what it reads rather than what it hopes.

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
		name = "ShardSpin", text = "\u{1F3A1} +1 SPIN 25\u{1F31F}", color = UITheme.Color.Locked,
		size = UDim2.new(0, 170, 0, 42), position = UDim2.new(1, -250, 0, 90),
		anchorPoint = Vector2.new(1, 0), radius = 14,
		zIndex = rewardPanel.ZIndex + 1, maxTextSize = 22,
	})

	-- "7h 12m", "12m", "45s" -- the same shape the offline card uses, for the same reason: the
	-- player is reading it for "roughly when", not for the exact second. The lobby's own countdown
	-- is HH:MM:SS instead, because that one is read while deciding whether to wait for it.
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
		local banked = math.floor(hud.getData().SpinTickets or 0)
		if ready then
			UITheme.SetColor(button, UITheme.Color.Gold)
			UITheme.SetText(button, "\u{1F3A1} FREE SPIN!")
		elseif banked > 0 then
			-- THE BUTTON MUST NOT GO GREY ON A PLAYER WHO CAN STILL SPIN (34.46). The free one is a
			-- ticket now, and a bought pack is the same ticket, so the day's countdown stopped being
			-- the whole answer to "can I press this" the moment spins became a balance.
			UITheme.SetColor(button, UITheme.Color.Purple)
			UITheme.SetText(button, ("\u{1F3A1} SPIN x%d"):format(banked))
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
			UITheme.SetText(shardButton, ("\u{1F3A1} +1 SPIN %d\u{1F31F}"):format(cost))
		else
			UITheme.SetColor(shardButton, UITheme.Color.Locked)
			UITheme.SetText(shardButton, ("\u{1F31F} %d / %d"):format(held, cost))
		end
	end

	-- A MISSING CHANNEL MUST SAY SO. Both buttons look their target up INSIDE the handler --
	-- correct, because the services and `SpinReveal` create these on demand and the order is not
	-- guaranteed -- but the `if remote then` used to be silent on the else, so a button whose service
	-- had not finished starting was indistinguishable from a broken one. That is half of the
	-- "claim/spin buttons do not work" report, and it is the half that leaves no evidence behind.
	--
	-- The message goes ON THE BUTTON rather than through showNotification, and that is a scope fact
	-- rather than a design one: showNotification is declared ~2400 lines below here, so a closure
	-- written at this point captures nil and the click would throw instead of explaining itself.
	local function nagNotReady(target)
		nagUntil = os.clock() + 1.5
		UITheme.SetColor(target, UITheme.Color.Locked)
		UITheme.SetText(target, "\u{23F3} not ready")
	end

	-- `OpenSpinLobbyLocal` is a BindableEvent `SpinReveal.client.lua` creates -- the `ClientGesture`
	-- pattern. A client-side panel open has no business being a round trip through the server; the
	-- only thing the server needs to hear is the free spin it should bank, and the lobby fires that
	-- itself the moment it is up.
	local function openLobby()
		local signal = Remotes:FindFirstChild("OpenSpinLobbyLocal")
		if signal then
			signal:Fire()
			return true
		end
		return false
	end

	button.MouseButton1Click:Connect(function()
		if not openLobby() then nagNotReady(button) end
	end)

	-- Fired unconditionally rather than gated on the local affordability check: the client's copy of
	-- the save is up to a push behind, and a button that silently does nothing is worse than the
	-- server's own "you need 25" toast. The server is the one that decides either way.
	shardButton.MouseButton1Click:Connect(function()
		local remote = Remotes:FindFirstChild("SpinWithShards")
		if remote then
			openLobby()
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
