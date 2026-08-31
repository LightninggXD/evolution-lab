local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local RS = game:GetService("ReplicatedStorage")
local UITheme = require(RS.Modules:WaitForChild("UITheme"))
local GameConfig = require(RS.Modules:WaitForChild("GameConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local FriendInviteButton = {}
local btn = nil

function FriendInviteButton.Init(screenGui)
	if btn then return btn end

	-- Rebuild using UITheme standard kit
	-- ===== THE EMOJI ALONE, BECAUSE BOTH DID NOT FIT (35.3) =====
	--
	-- The owner, off a two-client test: *"na trade buttonu je sve izmesano ne stane i text i
	-- emoji, treba samo emoji"*. This carried BOTH a two-line caption and an icon, and
	-- `UITheme.Button` lays those out SIDE BY SIDE -- the glyph takes the left end and the words
	-- are centred in what is left. On a 72 x 72 button that leaves the label about 26 px for two
	-- words, so it came out as the smear she photographed.
	--
	-- The other tiles in this column are NOT this shape: they stack a picture over a word and are
	-- built by the tile builder, which is why they fit and this did not.
	--
	-- Empty text rather than a shorter word -- what she asked for, and also the only thing that
	-- actually fits: `themeLabel` floors text at a `UITextSizeConstraint`, so a caption too big for
	-- its box is CUT rather than shrunk and reports nothing wrong (33.36).
	btn = UITheme.Button(screenGui, { name = "FriendInviteButton", text = "", icon = "🤝" })
	btn.Size = UDim2.new(0, 72, 0, 72)

	-- ...AND THE GLYPH HAS TO BE RE-CENTRED, because the kit parks it at the LEFT edge to leave
	-- room for the words beside it; with no words that reads as an icon that has slid off centre.
	-- `IconShadow` follows on its own -- it subscribes to the icon's Position and re-applies its
	-- own offset -- so only this one is moved.
	local glyph = btn:FindFirstChild("Icon")
	if glyph then
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.new(0.5, 0, 0.5, 0)
		-- 0.62 -> 0.72: the room the caption was using belongs to the icon now.
		glyph.Size = UDim2.new(0.72, 0, 0.72, 0)
	end
	-- ===== IT WAS SITTING UNDERNEATH THE WALLET (34.60) =====
	--
	-- The owner, on a capture of the diamond and gift capsules: *"ovaj invite ili trade sta je vec
	-- stoji iza ovoga i ne vidi se"*. It was not partly covered -- it was ENTIRELY covered.
	-- Measured on the running client at 1576 x 793:
	--
	--     FriendInviteButton   x  20.. 92   y 645..717     <- every pixel of it
	--     CurrencyStack        x  20..244   y 503..713     <- inside this
	--
	-- `1, -90` was authored as *"middle bottom, above hotbar"*, and there is no hotbar there any
	-- more: `CurrencyStack` grew to 210 tall when `HUD/DamageStat` hung a fourth capsule on it
	-- (33.26), and 210 reaches up past this button's whole height.
	--
	-- FIXED BY MOVING IT, NOT BY RAISING ITS ZIndex. A button drawn on top of a currency readout is
	-- the same fault seen from the other side, and the wallet is the thing a player checks most.
	--
	-- WHERE THE ROOM ACTUALLY IS, measured rather than guessed -- the left column ends and the
	-- wallet begins, and nothing at all is drawn between them:
	--
	--     EmotesButton (last tile in the left column)   y 279..361
	--     >>>>  the empty band                          y 361..503   (142 px)
	--     CurrencyStack (top edge)                      y 503
	--
	-- 248 px up from where it was puts it at y 397..469: 36 px clear of the tiles above and 34 clear
	-- of the wallet below. Both read tighter than the number says -- a 5 px stroke draws OUTSIDE the
	-- frame, so a gap of N shows as roughly N - 15 -- which is why the band is split rather than
	-- hugging either edge.
	--
	-- STILL BOTTOM-ANCHORED (`1, ...`), and that is the half that has to survive a resize. The
	-- wallet is anchored to the viewport's bottom too, so the 34 px gap below is constant at every
	-- height; the tile column above is TOP-anchored and `TileColumnFit` SHRINKS its tiles on a short
	-- viewport, so the gap above can only ever grow. Anchoring to the top instead would hold the
	-- wrong end.
	btn.Position = UDim2.new(0, 20, 1, -338)


	-- The pill for showing live count and bonus percentage
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Size = UDim2.new(0, 24, 0, 24)
	badge.Position = UDim2.new(1, -12, 0, -12)
	-- ===== `Red` AND `White`, BECAUSE `Action` AND `TextLight` ARE NOT COLOURS THIS KIT HAS =====
	--
	-- Both were invented at the call site and `UITheme.Color` holds neither, so this line assigned
	-- **nil** and threw `Unable to assign property BackgroundColor3. Color3 expected, got nil`.
	-- That is not a cosmetic fault: `MainUI:90` calls this `Init` WITHOUT a pcall, so the error
	-- propagated and aborted MainUI at line 90 -- measured on the running client, `EvolutionLabUI`
	-- came up with exactly **one** child, this button, and the entire HUD below that line was gone.
	-- Same blast radius as 34.39's BOM, from a different cause.
	--
	-- The kit's table is the authority and it is 30 keys long (`Outline`, `Cream`, `Gold`, `Red`,
	-- `Coral`, `Ink`, ...). A red pill with white type is what the pre-kit version drew by hand
	-- (rgb 255,50,50 on white), so these two tokens keep the look and stop inventing names.
	badge.BackgroundColor3 = UITheme.Color.Red
	badge.Text = "+0%"
	badge.Font = UITheme.Font.Display
	badge.TextSize = 12
	badge.TextColor3 = UITheme.Color.White
	badge.Visible = false
	badge.Parent = btn

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(1, 0)
	bCorner.Parent = badge
	
	local bStroke = Instance.new("UIStroke")
	bStroke.Color = UITheme.Color.Outline
	bStroke.Thickness = 2
	bStroke.Parent = badge

	local function updateBadge()
		local data = PlayerData.Get()
		if not data then return end
		-- Server stamped figure from DNAService
		local count = data.__friendCount or 0
		if count > 0 then
			-- THROUGH `GameConfig`, BECAUSE THIS LINE WAS THE ONE THAT DRIFTED. It read
			-- `count * 5` with no cap while the server pays at most +20%, so six friends in the
			-- server promised **+30%** on a badge sitting next to an income that was paying +20%.
			badge.Text = "+" .. GameConfig.GetFriendBonusPct(count) .. "%"
			badge.Visible = true
		else
			badge.Visible = false
		end
	end

	btn.MouseButton1Click:Connect(function()
		local ok, err = pcall(function()
			local options = Instance.new("ExperienceInviteOptions")
			options.LaunchData = tostring(Players.LocalPlayer.UserId)
			SocialService:PromptGameInvite(Players.LocalPlayer, options)
		end)
		if not ok then
			warn("Failed to prompt game invite:", err)
		end
	end)

	-- ===== `OnChanged(fn)`, NOT `Changed:Connect(fn)` -- THAT SIGNAL DOES NOT EXIST =====
	--
	-- `UIComponents/PlayerData` publishes exactly two functions, `Get()` and `OnChanged(fn)`, and
	-- the eleven other panels in this folder all call the second one. `PlayerData.Changed` is nil,
	-- so this line read `attempt to index nil with 'Connect'` -- and because `MainUI:90` calls this
	-- `Init` WITHOUT a pcall, that error aborted MainUI at line 90 and took the whole HUD with it
	-- (measured: `EvolutionLabUI` came up with ONE child, this button). Same blast radius as the
	-- nil colour one line above; both were invented API on a module that had a real one.
	--
	-- The `task.spawn` below is also gone: `OnChanged` FIRES IMMEDIATELY if a push has already
	-- landed, which is exactly what that spawn was for, and calling both meant two first paints.
	PlayerData.OnChanged(updateBadge)
	return btn
end

return FriendInviteButton
