-- JournalGrid -- the Journal's 100-skin grid: the discs, their rarity ribbons and the ownership readout.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local formatNumber, corner, themeLabel, styleCard = UIKit.formatNumber, UIKit.corner, UIKit.themeLabel, UIKit.styleCard
local styleButton, setButtonColor, OUTLINE_COLOR = UIKit.styleButton, UIKit.setButtonColor, UIKit.OUTLINE_COLOR

return function(hud)
	local CHAR_CELL_H, CHAR_LINE_H, CHAR_PER_LINE = hud.CHAR_CELL_H, hud.CHAR_LINE_H, hud.CHAR_PER_LINE
	local characterCells, characterPanel, characterRows = hud.characterCells, hud.characterPanel, hud.characterRows
	local characterScroll, ownershipText = hud.characterScroll, hud.ownershipText

	-- Required IN HERE, not at the top of the file: MainUI is at Luau's 200-local ceiling and a
	-- top-level require would cost one of the last registers. This function has its own 200.
	local CharacterPreview = require(RS.Modules.CharacterPreview)

	-- THE HOVER CARD IS GONE. It said a name and a damage figure, which the detail card on the
	-- right now states permanently and at a readable size -- and it was actively broken: it was
	-- shown on MouseEnter and hidden ONLY on MouseLeave, so closing the panel, scrolling the cell
	-- out from under the cursor, or a refresh hiding that cell all left it welded open at its build
	-- position (top-left, over the "Discovered 15 / 200" header) with stale text in it. Its stat
	-- line was also Cream on PanelWhite -- the exact white-on-white trap this file warns about
	-- twenty lines above.

	-- The twenty stage rows, PLUS TWO MORE at the end: the VIP skin and the event skins.
	--
	-- Both are built by exactly the same code as every other disc, which is the point: they lock,
	-- unlock, preview, select and wear with no special case anywhere, and a later change to how
	-- a cell looks reaches them for free. What they are NOT is part of a stage -- neither enters
	-- CHARACTERS_BY_STAGE, so the collection count, the evolve chain and the rank ladder cannot see
	-- them. See GameConfig.VipCharacter for why that separation is load-bearing.
	--
	-- ===== THE EVENT ROW (12.7) =====
	--
	-- It is the last row rather than the first, and it is DELIBERATELY not sorted by rarity. The
	-- optional "rare first" toggle this row carried does not survive contact with the panel: a
	-- stage's five entries are already in rarity order (Common, Uncommon, Rare, Epic, Legendary --
	-- that IS the authored list), and that order is simultaneously the UNLOCK QUEUE, which is what
	-- the header subtitle, the "next up" callout and the whole left-to-right reading of a row are
	-- built on. Reversing it would put the disc you are actually working towards at the far right of
	-- its row. There is also nothing for a LayoutOrder to sort: the cells are positioned by index
	-- inside their row, not laid out, so only the twenty ROWS have a LayoutOrder at all.
	--
	-- Guarded on the table being non-empty so removing the last event skin removes the row rather
	-- than leaving an empty header on the end of the list.
	-- ===== THE WARDROBE IS THE ONE ROW IN THIS PANEL THAT IS FOR SALE (26.4) =====
	--
	-- Nine skins the server already grants and revokes correctly (GameConfig.SyncVipCharacter) and
	-- which no surface anywhere offered to sell: the Journal drew nine ringed portraits with damage
	-- multipliers under them and never said the word "buy". The pass row in the Robux shop is two
	-- panels away and names the wardrobe in one clause of a sentence -- it is not where somebody
	-- looking at the Korblox Deathspeaker is standing.
	--
	-- IT IS A GAME PASS, NOT A DEVELOPER PRODUCT, and that is the one thing about this door that is
	-- not like the Season card's. `PromptRobuxPurchase` looks its key up in GameConfig.RobuxProducts,
	-- which does not and must not contain VIP -- a pass is owned forever and is checked with
	-- UserOwnsGamePassAsync, where a product is consumed through ProcessReceipt. Firing the product
	-- remote with "VIP" is not an error anywhere: RobuxShopService finds no product and returns, so
	-- the press would do nothing at all and print nothing. The pass remote is the one ShopPanel's own
	-- pass tiles fire, and PassService validates the key, refuses id 0 and refuses an owner.
	--
	-- The KEY is sent, never the pass id -- the server holds the id, so a tampered client can only
	-- ever name a pass that exists.
	local vipPass = GameConfig.GetGamePass("VIP")
	-- Created on demand by PassService.Init, so it may not have replicated yet when this runs -- the
	-- same WaitForChild PassShop uses for the same remote.
	local promptPass = Remotes:WaitForChild("PromptGamePassPurchase", 10)
	-- The wardrobe row's header, kept so the price can be painted onto it and taken off again when
	-- the pass lands. Every other row in this panel is earned, and its header is written once at join
	-- and never touched again.
	local vipHeader = nil

	local sections = {}
	for stageIndex, stage in ipairs(GameConfig.Stages) do
		table.insert(sections, {
			index = stageIndex,
			stage = stage,
			entries = GameConfig.GetCharactersForStage(stageIndex),
		})
	end
	-- THE WHOLE VIP WARDROBE, NOT ONE SKIN (16.2). Nine of them, so this row wraps onto a second
	-- line by the same `lineCount` arithmetic every stage row already uses -- no special case here
	-- either. See the wardrobe block over GameConfig.VipCharacters.
	table.insert(sections, {
		index = #GameConfig.Stages + 1,
		stage = { emoji = GameConfig.VipCharacter.emoji, name = "VIP Exclusive" },
		entries = GameConfig.VipCharacters,
		-- a flag rather than a name test: "VIP Exclusive" is a caption and captions get rewritten
		vip = true,
	})
	if #GameConfig.EventCharacters > 0 then
		table.insert(sections, {
			index = #GameConfig.Stages + 2,
			stage = { emoji = "\u{1F386}", name = "Event Exclusive" },
			entries = GameConfig.EventCharacters,
		})
	end

	for _, section in ipairs(sections) do
		local stageIndex, stage, entries = section.index, section.stage, section.entries
		local lineCount = math.max(1, math.ceil(#entries / CHAR_PER_LINE))

		-- The number under each disc is WHAT IT DOES. It used to be the chance of rolling it, and
		-- that stopped being a fact the moment unlocks went sequential: there is no roll any more,
		-- so there is no chance to print. Position in the stage's list is the power ladder now --
		-- see GameConfig.GetCharacterDamagePct -- and the damage it grants is the one number that
		-- tells a player whether walking to the next disc is worth anything.

		local row = Instance.new("Frame")
		row.Name = "Stage" .. stageIndex
		row.LayoutOrder = stageIndex
		row.Size = UDim2.new(1, 0, 0, 26 + lineCount * CHAR_LINE_H + 4)
		row.BackgroundTransparency = 1
		row.Parent = characterScroll

		local header = Instance.new("TextLabel")
		header.Name = "Header"
		header.Size = UDim2.new(1, -8, 0, 22)
		header.Position = UDim2.new(0, 6, 0, 0)
		header.BackgroundTransparency = 1
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = stage.emoji .. " " .. stage.name
		header.Parent = row
		themeLabel(header, 20, Color3.fromRGB(46, 54, 74))
		if section.vip then vipHeader = header end

		for i, entry in ipairs(entries) do
			-- THE DISC IS THE CHARACTER'S OWN COLOUR, NOT ITS RARITY'S. Rarity is no longer a thing
			-- the player experiences -- unlocks run left to right and the only difference between
			-- two discs is damage -- so colouring five of them gold and five grey was showing a
			-- ladder that no longer exists. Its own colour is the useful fact: the disc is now a
			-- swatch of what you actually turn into when you press it.
			local tint = entry.color or GameConfig.GetRarity(entry.rarity).color
			-- THE DAMAGE THIS RUNG PUTS ON THE BODY, and it is now literally the number the creature
			-- takes: GameConfig.GetRankDamage is the base of DNAService.GetCombatDamage, and nothing
			-- clamps it any more. The Journal promising one figure while combat drew another is the
			-- bug this replaces -- see the DAMAGE LADDER block in GameConfig.
			local damagePct = math.floor(GameConfig.GetRankDamage(GameConfig.GetCharacterRank(entry)))

			local col = (i - 1) % CHAR_PER_LINE
			local line = math.floor((i - 1) / CHAR_PER_LINE)

			local cell = Instance.new("TextButton")
			cell.Name = entry.key
			cell.AutoButtonColor = false
			cell.Text = ""
			-- square, and centred in its fifth of the row: a disc needs equal width and height, so
			-- the size is in offset and only the POSITION is in scale
			cell.Size = UDim2.new(0, CHAR_CELL_H, 0, CHAR_CELL_H)
			cell.Position = UDim2.new((col + 0.5) / CHAR_PER_LINE, -CHAR_CELL_H / 2, 0, 26 + line * CHAR_LINE_H)
			cell.Parent = row
			local cellStroke = styleCard(cell, tint, UDim.new(0.5, 0), 3)

			-- ===== THE DISC IS A RING NOW, NOT A FILLED PUCK =====
			--
			-- "Remove the circles around the characters, you cannot see them" (2026-08-11). The
			-- figure was never hidden -- it is a ViewportFrame lifted above the gloss by
			-- liftChildren -- it was being drawn on top of an OPAQUE disc in the character's own
			-- colour, and a green creature on a green puck is a silhouette-shaped hole. The tint is
			-- also the single worst case for it: the disc is deliberately painted the colour of the
			-- thing standing on it.
			--
			-- So the colour moves from the fill to the RIM, where it still identifies the character
			-- and still reads at a glance, and the figure gets the panel behind it instead of its
			-- own colour. The gradient goes with the fill -- a gradient over nothing is a wash of
			-- grey over the model's legs.
			--
			-- The stroke stays `tint` rather than the shared outline colour precisely because the
			-- fill no longer carries it; drop this and every disc in the Journal becomes identical.
			--
			-- RESTORED 2026-08-15 (15.27) after a Gemini pass reinstated the filled squircle. That
			-- pass is the same shape as 15.21: it undid a fix that exists because of a report she
			-- made herself, and wrote a comment describing the new look rather than the reason.
			--
			-- ...AND THE FILLED DISC CAME BACK A THIRD TIME, ON ITS OWN (2026-08-16). Not by anyone
			-- reinstating it: 15.28 rewrote `styleCard` to keep the colour in an `InnerBody` child
			-- instead of on the host, so `cell.BackgroundTransparency = 1` below now clears a surface
			-- that is no longer the one being seen, and the same three lines that used to strip a disc
			-- to a ring strip nothing. Photographed with the fill cleared on two rows and left on the
			-- third: hue-on-hue is real -- a green creature on a green puck flattens, and the damage
			-- number under the disc goes from legible to a smudge.
			--
			-- The owner's call between the three ways out (2026-08-16) was NOT the ring: keep the
			-- filled disc, which is the chunky look the rest of the HUD has, and take the collision
			-- out of it by paling the FILL while the rim keeps the character's colour at full
			-- strength. Hue and saturation come from the character and the value is set outright --
			-- the same HSV idiom as the locked disc below, pointed the other way.
			--
			-- `pale` is carried on the refs table because `setButtonColor` repaints this surface on
			-- every DataUpdate (15.28 made that call real; it used to paint nothing), so the pale is
			-- what refreshCharacterPanel has to hand it or the disc goes back to full strength one
			-- income tick later.
			local paleH, paleS = Color3.toHSV(tint)
			local pale = Color3.fromHSV(paleH, math.clamp(paleS * 0.34, 0, 1), 0.97)
			cell.BackgroundColor3 = pale
			local cellInner = cell:FindFirstChild("InnerBody")
			if cellInner then cellInner.BackgroundColor3 = pale end
			-- The gradient is authored off the full-strength colour, so over a pale fill it reads as
			-- a grey wash rather than as moulding. It lives on the host in one lineage of this file
			-- and under InnerBody in the other; both are cleared.
			local cellGrad = cell:FindFirstChild("Gradient")
				or (cellInner and cellInner:FindFirstChild("Gradient"))
			if cellGrad then cellGrad:Destroy() end
			-- and the sheen goes with it: a white highlight on a nearly-white disc is not a
			-- highlight, it is a bright band across the model's head
			local cellGloss = cell:FindFirstChild("Gloss")
				or (cellInner and cellInner:FindFirstChild("Gloss"))
			if cellGloss then cellGloss:Destroy() end
			cellStroke.Color = tint
			cellStroke.Thickness = UITheme.SnapStroke(4)

			-- THE CHARACTER ITSELF, not a glyph standing in for it. Half the roster shares an emoji,
			-- so a hundred discs carrying emoji showed a player perhaps eight distinct pictures for a
			-- hundred things they had collected -- which is the whole complaint about this panel.
			--
			-- Left EMPTY here and filled by syncPreviews below. A rig is 30 parts; building all
			-- hundred up front is three thousand parts created on join for a panel that is shut.
			local art = Instance.new("ViewportFrame")
			art.Name = "Art"
			-- inset off the rim so a shoulder cannot poke out through the side of the circle
			art.Size = UDim2.new(1, -12, 1, -12)
			art.Position = UDim2.new(0, 6, 0, 6)
			art.Visible = false
			art.ZIndex = cell.ZIndex + 1
			art.Parent = cell
			CharacterPreview.Light(art)

			-- the emoji stays as the stand-in until the rig for this cell exists -- which is what a
			-- cell shows while it is off screen, and what it falls back to if the build ever fails
			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.new(1, -12, 1, -12)
			icon.Position = UDim2.new(0, 6, 0, 6)
			icon.BackgroundTransparency = 1
			icon.Text = entry.emoji
			icon.Parent = cell
			themeLabel(icon, 40)

			-- what it grants, just under the disc and slightly overlapping it
			local damageLabel = Instance.new("TextLabel")
			damageLabel.Name = "Damage"
			damageLabel.Size = UDim2.new(1, 24, 0, 24)
			damageLabel.Position = UDim2.new(0, -12, 1, -6)
			damageLabel.BackgroundTransparency = 1
			-- An OFF-LADDER skin has no rung -- it scores as whatever the wearer's best earned skin
			-- scores (GameConfig.GetEffectiveRank), so any fixed percentage printed here would be
			-- a lie in one direction or the other depending on how far the collection has got. It says
			-- what it actually is instead.
			--
			-- `offLadder`, not `vip` (12.7): the event skins are the second kind of skin that is not
			-- on the ladder, and they score by the identical rule. Testing `vip` printed the ladder
			-- figure for a rank of 0 under the Prism Herald, i.e. the weakest number in the game.
			--
			-- A VIP SKIN IS THE ONE OFF-LADDER SKIN THAT CARRIES A FIGURE OF ITS OWN (16.2). It still
			-- has no rung -- it MULTIPLIES whatever rung the wearer scores -- so what belongs under the
			-- disc is the multiplier. A damage number here would be right for exactly one save.
			-- Trailing zeros are trimmed, so 5.00 reads x5 while 2.75 keeps both digits.
			damageLabel.Text = entry.vipDamageMult
					and ("\u{2694}\u{FE0F} x" .. (("%.2f"):format(entry.vipDamageMult):gsub("%.?0+$", "")))
				or (entry.offLadder and "\u{2694}\u{FE0F} = best"
					or ("\u{2694}\u{FE0F} %s"):format(formatNumber(damagePct)))
			damageLabel.ZIndex = cell.ZIndex + UITheme.Z.Badge
			damageLabel.Parent = cell
			themeLabel(damageLabel, 17, Color3.fromRGB(58, 66, 88))

			-- The locked state: a "?" over a DARKENED VERSION OF ITS OWN RARITY COLOUR, not a flat
			-- grey. The shape of the collection -- how many slots, which rarities -- is the
			-- information, and a row of identical grey discs throws it away. A padlock said only
			-- "locked"; a dim gold disc says "there is a Legendary here you have not found".
			local lock = Instance.new("TextLabel")
			lock.Name = "Lock"
			lock.Size = UDim2.new(1, 0, 1, 0)
			-- ...and it is mixed the way this project learned to mix a dark variant (11.14). The old
			-- line was `tint:Lerp(Color3.fromRGB(18, 16, 26), 0.72)`, which is "blend toward black,
			-- then take the result" -- and a lerp toward one fixed point does not just darken, it
			-- pulls every hue toward THAT point's hue as well. At 0.72 only 28% of the character's
			-- own colour survives and all hundred discs converge on the same brown-grey, which is
			-- precisely the outcome the comment above says it exists to avoid.
			--
			-- Hue and saturation come from the character, the VALUE is set outright. That is the
			-- world-look pass's rule ("blend then darken cancels; take hue/saturation from the blend
			-- and set the value") applied to a disc instead of a rock. Saturation is pushed UP, not
			-- down: a colour loses apparent chroma as it gets darker, so holding S constant would
			-- still read as a row of near-blacks.
			local lockH, lockS = Color3.toHSV(tint)
			lock.BackgroundColor3 = Color3.fromHSV(lockH, math.clamp(lockS * 1.15 + 0.22, 0, 1), 0.27)
			lock.BackgroundTransparency = 0
			lock.Text = "?"
			lock.ZIndex = cell.ZIndex + UITheme.Z.Badge + 1
			lock.Parent = cell
			corner(lock, UDim.new(0.5, 0))
			themeLabel(lock, 38)

			-- worn marker, on top of everything
			local check = Instance.new("TextLabel")
			check.Name = "Check"
			check.Size = UDim2.new(0, 30, 0, 30)
			check.Position = UDim2.new(1, -26, 0, -4)
			check.BackgroundColor3 = UITheme.Color.Green
			check.Text = "\u{2713}"
			check.Visible = false
			check.ZIndex = cell.ZIndex + UITheme.Z.Badge + 2
			check.Parent = cell
			corner(check, UDim.new(0.5, 0))
			themeLabel(check, 22)

			-- ===== NO RARITY BADGE HERE (15.28), AND THE REASON RETIRES 12.6 =====
			--
			-- 12.6 put a rarity pip on this disc and a rarity ribbon on the detail card, on the
			-- argument that a collection screen should say "there is a Legendary here you have not
			-- found". That argument was true of a game where characters DROPPED. It has not been
			-- true since 9.5 made every skin its own evolve: the 200 are unlocked in **strict rank
			-- order** (see the collection-order note in GameConfig), so the next one you get is the
			-- next one on the ladder no matter what rarity says, and there is nothing a player can
			-- do differently on learning it. The owner put it in one line -- *"I do not need the
			-- rarity option in the journal, every character has to be collected anyway"*.
			--
			-- `entry.rarity` is NOT dead and must not be deleted: `StageCostume.skinMarks` reads it
			-- to decide how much flourish a character wears, which is the form the fact takes now --
			-- you see a Legendary's ornament ON the Legendary rather than a letter in its corner.
			--
			-- A CLICK SELECTS, IT NO LONGER EQUIPS. It used to put the character straight on the body,
			-- which meant the only way to find out what one looked like was to wear it, and the only
			-- way to compare two was to wear both. The detail card on the right is where a character
			-- is looked at, and the Equip button on it is where the decision is made.
			cell.MouseButton1Click:Connect(function()
				if hud.journalSelect then
					hud.journalSelect(entry.key)
				end
			end)

			characterCells[entry.key] = {
				cell = cell, icon = icon, art = art, lock = lock, check = check, chance = damageLabel,
				strokeInst = cellStroke, entry = entry, rarity = { color = tint, pale = pale },
				-- what the caption says when it is a caption again: an event disc lends that label to its
				-- window while it is locked (26.3), and this is the only copy of the string it displaces
				chanceText = damageLabel.Text,
			}
		end

		characterRows[stageIndex] = { row = row, header = header }
	end

	-- ===== THE DETAIL CARD =====
	-- One character, big, on the right. Everything the hover card used to whisper is stated here at
	-- a size you can read, and the Equip button lives here rather than on the cell -- so looking at
	-- a character and deciding to become it are two different actions again.
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	-- lines up with characterScroll: same top (the header band's bottom edge), same bottom, and a
	-- right margin of 16 to match the scroll's left. 16 + 598 + 16 + 322 + 16 = 968 exactly.
	detail.Size = UDim2.new(0, 322, 1, -124)
	detail.Position = UDim2.new(1, -16, 0, 110)
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.ZIndex = characterPanel.ZIndex + UITheme.Z.Content
	detail.Parent = characterPanel
	styleCard(detail, Color3.fromRGB(240, 243, 250), UDim.new(0, 18), 3)

	-- A WELL FOR THE FIGURE TO STAND IN. On the panel's own white sheet a pale character had no
	-- edge at all -- the same problem the loading screen's tip card was made to solve.
	--
	-- 244 -> 212 (12.6). The card gained a second stat row and every element under the well had to
	-- move up by the difference; the height came out of the well rather than out of the panel
	-- because the panel is the widest in the game and registerPanel fits it to a phone viewport by
	-- SCALE -- thirty-two more pixels of card is thirty-two fewer everywhere else on a small screen.
	-- The figure is still drawn 298 x 212, which is three times the size of a disc.
	local stageBox = Instance.new("Frame")
	stageBox.Name = "StageBox"
	stageBox.Size = UDim2.new(1, -24, 0, 212)
	stageBox.Position = UDim2.new(0, 12, 0, 12)
	stageBox.ZIndex = detail.ZIndex + 1
	stageBox.Parent = detail
	local stageStroke = styleCard(stageBox, Color3.fromRGB(224, 230, 244), UDim.new(0, 14), 3)

	local bigArt = Instance.new("ViewportFrame")
	bigArt.Name = "Art"
	bigArt.Size = UDim2.new(1, -10, 1, -10)
	bigArt.Position = UDim2.new(0, 5, 0, 5)
	bigArt.ZIndex = stageBox.ZIndex + 1
	bigArt.Parent = stageBox
	CharacterPreview.Light(bigArt)

	-- what stands in the well when nothing is selected, and when what IS selected has never been
	-- found: a locked character is a silhouette on purpose, so the panel keeps something to find
	local bigMark = Instance.new("TextLabel")
	bigMark.Name = "Mark"
	bigMark.Size = UDim2.new(1, 0, 1, 0)
	bigMark.BackgroundTransparency = 1
	bigMark.Text = "?"
	bigMark.ZIndex = stageBox.ZIndex + 2
	bigMark.Parent = stageBox
	themeLabel(bigMark, 96, Color3.fromRGB(186, 194, 214))

	-- (12.6's rarity ribbon stood in the corner of this well. It went with the pip on the disc --
	-- see the note over the cells for why rarity stopped being a fact a Journal reader can act on.)

	local dName = Instance.new("TextLabel")
	dName.Name = "DetailName"
	dName.Size = UDim2.new(1, -24, 0, 36)
	dName.Position = UDim2.new(0, 12, 0, 232)
	dName.BackgroundTransparency = 1
	dName.ZIndex = detail.ZIndex + 1
	dName.Parent = detail
	themeLabel(dName, 30, Color3.fromRGB(46, 54, 74))

	local dSub = Instance.new("TextLabel")
	dSub.Name = "DetailSub"
	dSub.Size = UDim2.new(1, -24, 0, 24)
	dSub.Position = UDim2.new(0, 12, 0, 268)
	dSub.BackgroundTransparency = 1
	dSub.ZIndex = detail.ZIndex + 1
	dSub.Parent = detail
	themeLabel(dSub, 20, Color3.fromRGB(126, 134, 156))

	-- WHAT THE RUNG IS WORTH, in the shape every other stat in this game is drawn in.
	--
	-- Two lines since 12.6, and the second one is not decoration: a skin has paid health as well as
	-- damage since GameConfig.CharacterHealthPerRank went in, and this panel -- the only screen in
	-- the game that says anything at all about what a character is worth -- was still quoting only
	-- half of it. 40 -> 62 to carry the pair; see the well above for where the pixels came from.
	local dStat = Instance.new("Frame")
	dStat.Name = "DetailStat"
	dStat.Size = UDim2.new(1, -24, 0, 62)
	dStat.Position = UDim2.new(0, 12, 0, 294)
	dStat.ZIndex = detail.ZIndex + 1
	dStat.Parent = detail
	styleCard(dStat, Color3.fromRGB(230, 235, 246), UDim.new(0, 12), 3)

	local dStatLabel = Instance.new("TextLabel")
	dStatLabel.Size = UDim2.new(1, -16, 0, 26)
	dStatLabel.Position = UDim2.new(0.5, 0, 0, 5)
	dStatLabel.AnchorPoint = Vector2.new(0.5, 0)
	dStatLabel.BackgroundTransparency = 1
	dStatLabel.ZIndex = dStat.ZIndex + 1
	dStatLabel.Parent = dStat
	themeLabel(dStatLabel, 21, Color3.fromRGB(70, 78, 98))

	-- The health half. Quoted from GameConfig.GetCharacterHealthPct -- the function the applied
	-- multiplier is built out of -- and never re-derived here: a second copy of "1% a rung" in the
	-- UI is a promise that goes stale the day the rate changes, which is exactly the class of bug
	-- the damage figure was rescued from (see the note over the disc's own label).
	local dStatHp = Instance.new("TextLabel")
	dStatHp.Name = "DetailHealth"
	dStatHp.Size = UDim2.new(1, -16, 0, 26)
	dStatHp.Position = UDim2.new(0.5, 0, 0, 31)
	dStatHp.AnchorPoint = Vector2.new(0.5, 0)
	dStatHp.BackgroundTransparency = 1
	dStatHp.ZIndex = dStat.ZIndex + 1
	dStatHp.Parent = dStat
	themeLabel(dStatHp, 21, Color3.fromRGB(70, 78, 98))

	local dHint = Instance.new("TextLabel")
	dHint.Name = "DetailHint"
	-- clear of the button below it: the hint wraps to two lines for every owned character, and at
	-- -78 the second line was entirely behind the green button -- which is the one sentence in this
	-- panel that explains why pressing it might appear to do nothing
	dHint.Size = UDim2.new(1, -24, 0, 44)
	dHint.Position = UDim2.new(0, 12, 1, -112)
	dHint.BackgroundTransparency = 1
	dHint.TextWrapped = true
	dHint.ZIndex = detail.ZIndex + 1
	dHint.Parent = detail
	themeLabel(dHint, 17, Color3.fromRGB(146, 154, 174))

	local equipButton = Instance.new("TextButton")
	equipButton.Name = "EquipButton"
	equipButton.Size = UDim2.new(1, -24, 0, 52)
	equipButton.Position = UDim2.new(0.5, 0, 1, -12)
	equipButton.AnchorPoint = Vector2.new(0.5, 1)
	equipButton.Text = "Wear this one"
	equipButton.Parent = detail
	styleButton(equipButton, UITheme.Color.Green, UDim.new(0, 16))
	-- AFTER styleButton, which writes its own ZIndex over anything set before it -- set first, the
	-- button ended up level with the hint and the stacking fell back to tree order
	equipButton.ZIndex = detail.ZIndex + 4

	-- =====================================================================================
	-- THE EVENT LADDER, ON THE CARD (26.3)
	-- =====================================================================================
	-- 26.1 put a price on an event skin and 26.2 built the board that price is paid on -- inside the
	-- Season panel's Quests tab, behind a different tile. THE JOURNAL IS WHERE A SKIN NOBODY OWNS IS
	-- ACTUALLY LOOKED AT, and until this block it answered "how do I get this?" with one sentence
	-- naming the event: not what the ladder asks, not how far this save already is, not how long the
	-- window has left. A locked event disc was a "?" with a paragraph under it.
	--
	-- IT TAKES THE STAT BOX'S SPACE, AND THAT COSTS NOTHING FOR THIS ONE CASE. dStat quotes
	-- GetRankDamage(GetEffectiveRank), and GetEffectiveRank on an OFF-LADDER entry is
	-- GetBestOwnedRank -- so for an unowned event skin both of its rows restate what the player
	-- already hits for, which is why the disc's own caption says "= best" rather than a figure. The
	-- VIP skin is off-ladder too and KEEPS its box: its number is that rung MULTIPLIED, i.e. a real
	-- statement about a real trade. dHint goes with it because the sentence it carried for these five
	-- entries is the title line below, said shorter.
	--
	-- BUILT ONCE, FOR THE LONGEST LADDER IN THE CONFIG. Same argument 26.2's sections are built at
	-- join under: a card that creates rows when somebody looks at it is a code path that only ever
	-- runs while somebody is watching. The count is READ (#GetEventQuests) rather than written down,
	-- so a fifth rung needs no edit in this file -- one more row simply stops being hidden.
	local ladderMax = 0
	for _, ev in ipairs(GameConfig.Events) do
		ladderMax = math.max(ladderMax, #GameConfig.GetEventQuests(ev.key))
	end

	local ladderBox = Instance.new("Frame")
	ladderBox.Name = "EventLadder"
	-- dStat's own corner, and its height plus dHint's: the three are never up at the same time.
	ladderBox.Size = UDim2.new(1, -24, 0, 118)
	ladderBox.Position = UDim2.new(0, 12, 0, 294)
	ladderBox.BackgroundTransparency = 1
	ladderBox.Visible = false
	ladderBox.ZIndex = detail.ZIndex + 2
	ladderBox.Parent = detail

	-- WHICH EVENT AND HOW LONG IS LEFT, in the event's own colour -- the colour its section wears on
	-- the Quests tab and its sign wears in the Forest, so a player who has seen one recognises the
	-- other. Painted per redraw, never at build time: which event this card is showing changes with
	-- the selection and the clock moves under both of them.
	local ladderTitle = Instance.new("TextLabel")
	ladderTitle.Name = "Title"
	ladderTitle.Size = UDim2.new(1, 0, 0, 22)
	ladderTitle.BackgroundTransparency = 1
	ladderTitle.TextXAlignment = Enum.TextXAlignment.Left
	ladderTitle.ZIndex = ladderBox.ZIndex + 1
	ladderTitle.Parent = ladderBox
	themeLabel(ladderTitle, 18, Color3.fromRGB(46, 54, 74))

	-- WHAT THE LADDER ASKS. One row per rung, and the rung's own authored name already contains the
	-- target ("Defeat 400 creatures"), so the left column is the requirement whether or not there is
	-- a board running to count against it.
	local ladderRows = {}
	-- 18, not 19, and the four pixels are not slack: the foot line lands 8 px clear of the button
	-- under it, and styleButton's lip draws OUTSIDE the button's own frame -- so a gap authored at 4
	-- renders as nothing at all, which is the rule the HUD tile column already paid for once.
	local LADDER_ROW_H = 18
	for i = 1, ladderMax do
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = ("Rung%dName"):format(i)
		nameLabel.Size = UDim2.new(1, -70, 0, LADDER_ROW_H)
		nameLabel.Position = UDim2.new(0, 0, 0, 22 + (i - 1) * LADDER_ROW_H)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.ZIndex = ladderBox.ZIndex + 1
		nameLabel.Parent = ladderBox
		themeLabel(nameLabel, 16, Color3.fromRGB(70, 78, 98))

		-- The progress column, and it is EMPTY unless the window is open ON THIS SKIN rather than
		-- showing "0 / 400". A zero against a board that cannot move is not a score, it is a false
		-- start -- nothing the player does today will change it. See paintLadder for the other half of
		-- that rule, which is the one a rotation makes necessary.
		local countLabel = Instance.new("TextLabel")
		countLabel.Name = ("Rung%dCount"):format(i)
		countLabel.Size = UDim2.new(0, 70, 0, LADDER_ROW_H)
		countLabel.Position = UDim2.new(1, -70, 0, 22 + (i - 1) * LADDER_ROW_H)
		countLabel.BackgroundTransparency = 1
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.ZIndex = ladderBox.ZIndex + 1
		countLabel.Parent = ladderBox
		themeLabel(countLabel, 16, Color3.fromRGB(70, 78, 98))

		ladderRows[i] = { name = nameLabel, count = countLabel }
	end

	-- The line the rotation makes necessary: WHICH of the four champions this one is, and when its
	-- own turn comes. Anchored under the last rung the config can hold rather than at the bottom of
	-- the box, so a shorter ladder does not leave a gap between itself and its own footnote.
	local ladderFoot = Instance.new("TextLabel")
	ladderFoot.Name = "Foot"
	ladderFoot.Size = UDim2.new(1, 0, 0, 20)
	ladderFoot.Position = UDim2.new(0, 0, 0, 22 + ladderMax * LADDER_ROW_H)
	ladderFoot.BackgroundTransparency = 1
	ladderFoot.TextXAlignment = Enum.TextXAlignment.Left
	ladderFoot.ZIndex = ladderBox.ZIndex + 1
	ladderFoot.Parent = ladderBox
	themeLabel(ladderFoot, 15, Color3.fromRGB(126, 134, 156))

	local selectedKey = nil
	-- WHAT THE GREEN BUTTON IS FOR RIGHT NOW. It equips, except on a locked event skin whose window
	-- is open, where there is nothing to equip and one thing worth pressing -- the board the rungs
	-- are claimed on. A single flag rather than a second button: two 52px buttons do not fit under
	-- this card, and a button that is present-but-dead on 199 of 200 entries is the 18.6 fault.
	local boardMode = false
	-- ...and the second thing it is for: a locked VIP portrait, where there is likewise nothing to
	-- equip and one thing worth pressing. Two flags rather than one enum because they can never both
	-- be true -- an entry is either `vip` or `event`, never both -- and a flag reads at the branch.
	local vipDoor = false
	local bigRig, bigPivot = nil, nil

	-- ===== DARK INK ON A PALE CARD DOES NOT WANT AN OUTLINE (12.6) =====
	--
	-- Every label in this kit is white with a 4px near-black stroke, and that stroke is what carries
	-- white text over a bright cartoon world. The detail card is the other case entirely: it is a
	-- pale sheet (240,243,250) and its labels are DARK -- so glyph and outline are the same ink, and
	-- twenty-one pixels of it inside four more render as a fat dark blob with a slightly lighter
	-- core. Every property reads correct while it happens: TextFits true, .Text right,
	-- .TextColor3 right. It is only visible in a screenshot, which is how it was found -- the same
	-- defect 12.3 found on the Splicer's white reveal card, one panel over.
	--
	-- Fixed the same way, and deliberately by a LUMINANCE TEST rather than a list of label names:
	-- dName wears the CHARACTER'S own colour and a good half of the roster is pale gold or cream,
	-- which needs the dark outline exactly as much as the dark ones need it gone. 0.62 is the line
	-- between the two on this sheet -- the locked grey (150,158,178) sits a hair above it and keeps
	-- its stroke, the mid-grey subtitle sits below and loses it.
	-- THICKNESS, NOT ONLY TRANSPARENCY -- and this line is the whole reason the fix above needed a
	-- capture to check. Phase 15 taught `themeLabel` to call `OutlineText(label, 0)` for dark ink,
	-- and these five labels are AUTHORED dark (46,54,74) and REPAINTED bright at runtime with the
	-- character's own colour. So they arrive here with a stroke whose Thickness is already 0, and a
	-- helper that moves only Transparency has nothing left to switch on: "The Final" rendered at
	-- luminance 0.900 on a 0.953 card with no outline at all -- a difference of 0.052, which is a
	-- ghost rather than a blob but is just as unreadable. Restore both, or a zeroed stroke is
	-- permanent for any label that is dark at build time and bright afterwards.
	local function inkOnLight(label)
		local st = label:FindFirstChildOfClass("UIStroke")
		if not st then return end
		local c = label.TextColor3
		local bright = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) >= 0.62
		st.Transparency = bright and 0 or 1
		st.Thickness = bright and 4 or 0 -- 4 is themeLabel's own non-dark default
	end

	-- ===== THE FIVE DISCS THAT HAVE SOMETHING TO SAY WHILE THEY ARE STILL LOCKED (26.3) =====
	--
	-- Every other locked disc in this panel is a "?" and should stay one: the collection unlocks in
	-- strict rank order, so the only fact about a locked skin is that it is further up the same
	-- ladder, and there is nothing a player can do differently on learning it. An event skin is the
	-- exception and the only one -- it is the entry whose availability is a CLOCK, and the row shows
	-- five of them side by side with nothing to say which is being handed out this weekend.
	--
	-- IT WRITES INTO THE DAMAGE CAPTION'S SLOT, which is empty under a locked cell. MainUI's
	-- refreshCharacterPanel hides that label for anything unowned and makes this one exception by
	-- name; see the note there. The caption is put BACK to what the cell was built with once the skin
	-- is owned, because nothing else in the game ever rewrites that label -- without it a disc earned
	-- on Sunday would keep a countdown under it for the rest of the save's life.
	local function paintEventCells()
		local owned = hud.getData() and hud.getData().Characters or nil
		local now = GameConfig.EventNow()
		for key, refs in pairs(characterCells) do
			local entry = refs.entry
			if entry.event then
				if owned and owned[key] then
					refs.chance.Text = refs.chanceText
					refs.chance.TextColor3 = Color3.fromRGB(58, 66, 88)
				else
					local event = GameConfig.GetEvent(entry.event)
					local window = event and GameConfig.GetEventWindow(event, now)
					local mine = (window and window.active
						and GameConfig.GetEventRewardKey(event, window) == entry.key) or false
					-- A rotation champion's own turn, which for three of the four is NOT the weekend that
					-- is running -- the festival has no rotation and falls through to its window's start.
					local rot = GameConfig.GetRotationInfo(entry.key, now)
					local soon = (rot and rot.nextStart) or (window and window.nextStart) or nil
					if mine then
						refs.chance.Text = ("%s LIVE NOW"):format(event.emoji)
						refs.chance.TextColor3 = Color3.fromRGB(72, 168, 96)
					else
						refs.chance.Text = soon
							and ("\u{23F3} in %s"):format(GameConfig.FormatDuration(soon - now))
							or "\u{23F3} not running"
						refs.chance.TextColor3 = Color3.fromRGB(58, 66, 88)
					end
				end
			end
		end
	end

	-- ===== THE LADDER BLOCK, FILLED (26.3) =====
	--
	-- Answers two things the caller needs and cannot work out for itself: whether this entry has a
	-- ladder to draw at all, and whether the window is open ON THIS SKIN right now -- which is the
	-- one condition under which the card offers a door to the board. An event with no rungs authored
	-- (Weekend2x hands over no skin, so it has none) draws nothing and the card falls back to the
	-- sentence it has always shown.
	--
	-- PROGRESS IS SHOWN ONLY WHEN THIS SKIN IS THE PRIZE, and that is the rotation's doing rather
	-- than caution. ColosseumClash is live for one of its four champions at a time; the board's
	-- counters are running for all of them, but claiming the last rung pays THE WEEKEND'S champion.
	-- "120 / 400" on the card of a skin this weekend cannot hand over is the loudest thing on it, and
	-- it would be a promise the claim then refuses -- so those three cards get the requirement, the
	-- clock, and a foot line saying when their own turn comes.
	--
	-- GetEventBoard MUTATES the save it is handed, which is its documented contract (reading a board
	-- is what creates it). Harmless here for the same reason it is harmless in SeasonPass: this is
	-- the client's replicated copy and the next DataUpdate overwrites it.
	local function paintLadder(entry)
		local event = entry.event and GameConfig.GetEvent(entry.event) or nil
		local ladder = event and GameConfig.GetEventQuests(event.key) or nil
		if not (event and ladder and #ladder > 0) then return false, false, nil end

		local now = GameConfig.EventNow()
		local window = GameConfig.GetEventWindow(event, now)
		local live = (window and window.active) or false
		local mine = (live and GameConfig.GetEventRewardKey(event, window) == entry.key) or false
		local board = (mine and hud.getData())
			and GameConfig.GetEventBoard(hud.getData(), event.key, window) or nil

		-- THE CLOCK IS ON THE TITLE LINE, not on a line of its own: the card has room for one line per
		-- fact, and the third fact -- which week of the rotation this champion is -- only exists for
		-- one of the two events.
		ladderTitle.Text = live
				and ("%s %s  \u{2022}  ends in %s"):format(event.emoji, event.name,
					GameConfig.FormatDuration(window.endTs - now))
			or (window and window.nextStart)
				and ("%s %s  \u{2022}  runs in %s"):format(event.emoji, event.name,
					GameConfig.FormatDuration(window.nextStart - now))
			or ("%s %s  \u{2022}  not running"):format(event.emoji, event.name)
		ladderTitle.TextColor3 = event.color
		inkOnLight(ladderTitle)

		local prizeStep
		for i, quest in ipairs(ladder) do
			local refs = ladderRows[i]
			if quest.character then prizeStep = i end
			if refs then
				refs.name.Visible = true
				refs.count.Visible = true
				refs.name.Text = ("%d. %s %s"):format(i, quest.emoji, quest.name)
				local done = board and board.progress[quest.key] or 0
				if not board then
					refs.count.Text = ""
				elseif board.claimed[quest.key] then
					refs.count.Text = "\u{2705}"
				else
					refs.count.Text = ("%d/%d"):format(math.min(done, quest.target), quest.target)
				end
				-- a finished rung is worth pointing at even before it is claimed: the claim itself is on
				-- the other board, so this is the only surface that can say "go and press it"
				refs.count.TextColor3 = (board and done >= quest.target)
					and Color3.fromRGB(72, 168, 96) or Color3.fromRGB(70, 78, 98)
				inkOnLight(refs.count)
			end
		end
		-- the rows a shorter ladder does not reach. Hidden rather than blanked, so an empty row cannot
		-- keep a stale count from the last entry that was looked at.
		for i = #ladder + 1, ladderMax do
			ladderRows[i].name.Visible = false
			ladderRows[i].count.Visible = false
		end

		local rot = GameConfig.GetRotationInfo(entry.key, now)
		if mine then
			ladderFoot.Text = prizeStep
				and ("\u{1F381} Step %d hands over this skin"):format(prizeStep)
				or "\u{1F381} Finish the ladder for this skin"
		elseif rot and rot.nextStart then
			ladderFoot.Text = ("\u{1F504} Week %d of %d  \u{2022}  its turn in %s")
				:format(rot.slot, rot.count, GameConfig.FormatDuration(rot.nextStart - now))
		elseif rot then
			ladderFoot.Text = ("\u{1F504} Week %d of %d of the rotation"):format(rot.slot, rot.count)
		else
			ladderFoot.Text = ("\u{1F381} All %d steps, inside the window"):format(#ladder)
		end
		-- ===== AND THE ONE THAT ONLY A CAPTURE FINDS (26.3) =====
		--
		-- This label never changes colour, so it looks like the one line in the block that does not
		-- need the card's ink helper. It needs it MOST. themeLabel decides the halo from
		-- UITheme.IsDarkInk, whose cut is 0.45; the subtitle grey it is authored in sits at 0.526, so
		-- it is handed the full 4 px Color.Outline -- dark ink inside a dark halo, on a pale card,
		-- which is the blob 15.1 exists to kill and which every property reads clean through. The
		-- rungs above are authored at 0.306 and drop their stroke at build time, which is exactly why
		-- this one line came out looking different from the four over it. inkOnLight cuts at 0.62 --
		-- the number this card is tuned to -- and owns Thickness as well as Transparency.
		inkOnLight(ladderFoot)

		return true, mine, event.color
	end

	-- WHAT THE ROW COSTS, ON THE ROW (26.4). A player scrolling the Journal meets these nine as nine
	-- more locked discs among two hundred; the header is the only place that can say they are a
	-- different KIND of locked -- not further down a queue but behind a till -- without hanging a
	-- badge on each of the nine.
	--
	-- REPAINTED, NOT WRITTEN AT BUILD TIME, because the pass can land mid-session: PassService grants
	-- it straight off PromptGamePassPurchaseFinished and pushes a DataUpdate, so a header authored at
	-- join would still be quoting a price at somebody who has just paid it. The count is read
	-- (#VipCharacters) for the same reason every other count in this file is -- a tenth bundle must
	-- not need an edit here.
	--
	-- No price at all when the pass has no real id: the door is hidden in that case too, and a header
	-- advertising a price with no button under it is worse than a header that says nothing.
	local function paintVipHeader()
		if not vipHeader then return end
		local base = ("%s VIP Exclusive"):format(GameConfig.VipCharacter.emoji)
		if GameConfig.OwnsPass(hud.getData(), "VIP") then
			vipHeader.Text = base .. "  \u{2022}  all yours"
		elseif vipPass and (vipPass.passId or 0) > 0 then
			vipHeader.Text = ("%s  \u{2022}  R$ %s for all %d"):format(base, vipPass.price or "?",
				#GameConfig.VipCharacters)
		else
			vipHeader.Text = base
		end
	end

	-- TEXT AND BUTTON ONLY. Called from refreshCharacterPanel, which runs on every DataUpdate --
	-- which is to say on every creature anyone kills -- so it must never rebuild the figure.
	local function paintDetail()
		-- the five event discs' own captions, which are a function of the clock rather than of the
		-- selection -- above the early return, because they are just as true with nothing picked
		paintEventCells()
		-- and the wardrobe row's price, which is a function of the save for the same reason
		paintVipHeader()
		local refs = selectedKey and characterCells[selectedKey]
		local entry = refs and refs.entry
		if not entry then
			dName.Text = "Nothing picked"
			dName.TextColor3 = Color3.fromRGB(46, 54, 74)
			dSub.Text = "Choose one from the list"
			dStatLabel.Text = ""
			dStatHp.Text = ""
			dHint.Text = ""
			bigMark.Visible = true
			bigMark.Text = "\u{1F4D2}"
			-- the three the ladder block takes over (26.3), put back: "nothing picked" is reached from
			-- a card that may have been showing one, and a frame left visible here would hang over it
			ladderBox.Visible = false
			dStat.Visible = true
			dHint.Visible = true
			boardMode = false
			vipDoor = false
			equipButton.Visible = false
			-- the empty card is a real state of this panel (it is what it opens as before anything is
			-- picked), so it gets the same ink treatment as the filled one
			inkOnLight(dName)
			inkOnLight(dSub)
			return
		end

		local owned = hud.getData() and hud.getData().Characters and hud.getData().Characters[entry.key] == true
		local stage = GameConfig.Stages[entry.stage]
		local rarityLine = ownershipText(entry.key)
		-- ONE worn character, wherever the player is standing -- see GameConfig.GetWornCharacter
		local equipped = hud.getData() and hud.getData().WornCharacter == entry.key
		-- The rung the player actually FIGHTS at. It is the best one owned, not the one on the body:
		-- a costume is free now, see GameConfig.GetProgressRank.
		-- ...times the VIP wardrobe, which is the one costume that DOES change it (16.2). Without that
		-- term this card told a player standing in an x8 skin they hit for an eighth of what they do.
		local progressDamage = hud.getData() and math.floor(
			GameConfig.GetBaseDamage(hud.getData()) * GameConfig.GetVipDamageMult(hud.getData())) or 0

		dName.Text = owned and entry.name or "???"
		dName.TextColor3 = owned and (entry.color or Color3.fromRGB(46, 54, 74)) or Color3.fromRGB(150, 158, 178)
		-- AN OFF-LADDER SKIN BELONGS TO NO STAGE, and this line used to say so by printing
		-- "  \u{2022}  #1 of 0" beside the VIP one: `entry.stage` is nil for it, so
		-- GetCharactersForStage hands back an empty list and GetCharacterIndex falls through to its
		-- 1. Nothing was broken underneath -- the ladder deliberately does not contain these -- it
		-- was the panel reporting a position in a list the entry is not in.
		if entry.offLadder then
			dSub.Text = ("%s  \u{2022}  outside the collection%s")
				:format(entry.vip and "\u{1F451} VIP Exclusive" or "\u{1F386} Event Exclusive", rarityLine)
		else
			dSub.Text = ("%s %s  \u{2022}  #%d of %d%s"):format(stage and stage.emoji or "", stage and stage.name or "",
				GameConfig.GetCharacterIndex(entry), #GameConfig.GetCharactersForStage(entry.stage), rarityLine)
		end

		-- ===== THE TWO NUMBERS A RUNG IS WORTH (12.6) =====
		--
		-- Both read off GetEffectiveRank, which is the only honest rung for an off-ladder skin: the
		-- VIP one scores as the best thing the save has earned, so a fixed figure would be a lie in
		-- one direction or the other depending on how far the collection has got. The disc's own
		-- label already says "= best" for exactly this reason; the card used to quote
		-- GetCharacterRank straight and therefore printed the WEAKEST rung in the game beside the
		-- strongest skin in it (GetRankDamage clamps a 0 up to rank 1).
		local shownRank = GameConfig.GetEffectiveRank(hud.getData(), entry)
		-- A VIP skin's figure is that same rung MULTIPLIED, so the card answers "what would I hit for
		-- in this?" rather than quoting a rung the skin then changes underneath the player.
		dStatLabel.Text = ("\u{2694}\u{FE0F}  %s Damage"):format(
			formatNumber(math.floor(GameConfig.GetRankDamage(shownRank) * (entry.vipDamageMult or 1))))
		dStatHp.Text = ("\u{2764}\u{FE0F}  +%d%% Max Health"):format(
			math.floor(GameConfig.GetCharacterHealthPct(entry, hud.getData())))

		-- ===== THE LADDER TAKES THE CARD OVER FOR A LOCKED EVENT SKIN (26.3) =====
		--
		-- Three surfaces move together and are restored together: the stat box and the hint go, the
		-- ladder block comes up in their place, and the green button stops being an Equip. Nothing else
		-- in the panel is touched -- and the hint chain below still runs, because it is what an event
		-- skin whose event has no rungs authored falls back to (paintLadder returns false for those).
		local ladderShown, ladderDoor, ladderColor = false, false, nil
		if (not owned) and entry.event then
			ladderShown, ladderDoor, ladderColor = paintLadder(entry)
		end
		ladderBox.Visible = ladderShown
		dStat.Visible = not ladderShown
		dHint.Visible = not ladderShown
		boardMode = ladderDoor

		-- ===== THE SECOND DOOR ON THIS BUTTON (26.4) =====
		--
		-- OWNERSHIP OF THE PASS, NOT OF THE SKIN, and the two are not the same test for the length of
		-- one join. SyncVipCharacter writes all nine into `Characters` off `data.Passes`, and
		-- PassService fills `Passes` on its own PlayerAdded connection with retries -- so there is a
		-- window on join where a paying VIP's save says the skin is not owned. `owned` alone would
		-- offer them a till they have already been through, and PassService would answer the press
		-- with "You already own VIP!" -- the game accusing its best customer of not having paid.
		--
		-- The id guard is ShopPanel's, for the same reason: prompting on id 0 opens a dialog that
		-- cannot complete, which reads as the game being broken rather than as something not being on
		-- sale yet. With no door there is no button at all -- the 18.6 rule -- and paintVipHeader
		-- drops the price to match, so the row goes quiet together rather than half-advertising.
		vipDoor = (not owned) and entry.vip == true and vipPass ~= nil and (vipPass.passId or 0) > 0
			and not GameConfig.OwnsPass(hud.getData(), "VIP")

		equipButton.Visible = owned or boardMode or vipDoor
		if boardMode then
			-- THE DOOR, AND IT ONLY EXISTS WHILE THE WINDOW IS OPEN ON THIS SKIN. A button that opened
			-- the Quests tab on a Wednesday would land on a board with no section for this event at all
			-- -- a press whose result contradicts its own label, which is the 18.6 fault. It is also the
			-- only reason this card can stop at "what the ladder asks": the claiming is one press away.
			equipButton.Text = "\u{1F4CB} Open the event board"
			setButtonColor(equipButton, ladderColor or UITheme.Color.Green)
			equipButton.Active = true
			equipButton.AutoButtonColor = true
		elseif vipDoor then
			-- GOLD, which is this door's own colour by the same rule the event door is painted in its
			-- event's: the pass is the crown, its shop card's wash is gold, and the Season panel's
			-- Premium button -- the only other Robux door in the HUD -- is UITheme.Color.Gold too. A
			-- green button here would read as an Equip that has changed its mind.
			--
			-- The price is on the button as well as on the row header. It is the last thing read
			-- before a press and a Robux dialog is the worst place to first learn a number.
			equipButton.Text = ("\u{1F451} Get VIP \u{2014} R$ %s"):format(vipPass.price or "?")
			setButtonColor(equipButton, UITheme.Color.Gold)
			equipButton.Active = true
			equipButton.AutoButtonColor = true
		elseif equipped then
			equipButton.Text = "\u{2713} Wearing it"
			-- Same receipt-not-refusal split as the Auras row and Stage Mastery (18.6): inert is
			-- right, grey is not. The skin the player chose is the proudest thing on this screen.
			setButtonColor(equipButton, UITheme.DoneShade(UITheme.Color.Green))
			-- dimmed AND dead. A greyed-out button that still fires a remote and still answers with a
			-- toast is worse than one that does nothing: it says the press failed rather than that
			-- there was nothing to press.
			equipButton.Active = false
			equipButton.AutoButtonColor = false
		else
			equipButton.Text = "Wear this one"
			setButtonColor(equipButton, UITheme.Color.Green)
			equipButton.Active = true
			-- PUT BACK, not merely left alone. The `equipped` branch above switches AutoButtonColor
			-- off and nothing switched it on again, so looking at the worn skin and then at any other
			-- one left a live Equip button with no press feedback for the rest of the session. Found
			-- while adding the branch above, which sets both for the same reason.
			equipButton.AutoButtonColor = true
		end

		-- THERE IS NO TRADE LEFT TO WARN ABOUT. This used to compare the rung against the one on the
		-- body and print what wearing it would cost, because damage came from the costume. It comes
		-- from the best rung OWNED now, so picking an old skin changes nothing but the mirror --
		-- and the useful fact is instead what the player is hitting for right now.
		-- THE COLOUR IS RESET BEFORE THE CHAIN, not only inside the branches that change it. Three of
		-- the branches below paint this label green and none of the others painted it back, so the
		-- colour was whatever the LAST card looked at had said -- an unowned skin's "evolve to this
		-- stage" line inherited the green of a previously-inspected owned one and read as good news.
		-- Harmless-looking until 12.13 added a fourth green branch; a default set once, here, cannot
		-- go stale however many branches are added later.
		dHint.TextColor3 = Color3.fromRGB(146, 154, 174)
		if not owned then
			-- HOW TO GET IT, and for an off-ladder skin that is not "evolve" (12.7). Every unowned
			-- entry used to be told to evolve into its stage, and an off-ladder skin has no stage --
			-- so the Prism Herald's own card read "Evolve to this stage to discover it", which is
			-- both untrue and unactionable. Each kind now names its actual route.
			if entry.vip then
				-- BOTH LADDERS, because as of the wardrobe rebuild a VIP skin pays DNA as well as
				-- damage and quoting only the half that was here first would undersell the row by
				-- exactly the amount that was added to it.
				dHint.Text = ("Comes with the VIP pass \u{2014} x%s damage and x%s DNA while it is on, and it goes away again if the pass does.")
					:format((("%.2f"):format(entry.vipDamageMult or 1):gsub("%.?0+$", "")),
						(("%.2f"):format(entry.vipIncomeMult or 1):gsub("%.?0+$", "")))
			elseif entry.event then
				local eventDef = GameConfig.GetEvent(entry.event)
				local label = ("%s%s"):format(eventDef and (eventDef.emoji .. " ") or "",
					eventDef and eventDef.name or "the event")
				-- A ROTATION SKIN IS NOT AVAILABLE WHENEVER ITS EVENT IS (12.13). The generic line
				-- below is true of the festival, which offers its one skin for the whole window --
				-- and false of a champion, which is one of four and is offered on one weekend in
				-- four. Telling a collector to come back "while it is running" on a weekend that is
				-- running somebody else's skin is the panel lying about the only thing this card
				-- exists to answer.
				--
				-- AND SINCE 26.1 NONE OF THE THREE MAY SAY "TURN UP". The skin stopped being handed to
				-- whoever was online and became the last rung of an ordered ladder, so a card still
				-- promising attendance would be the game's own Journal describing a rule the server no
				-- longer runs. The rung count is READ rather than written into the string, so an author
				-- who adds a fifth rung does not have to remember this file.
				--
				-- THIS WHOLE BRANCH IS A FALLBACK NOW (26.3), AND IT IS NOT DEAD CODE. The ladder block
				-- above takes the card over -- and hides dHint -- for any event skin whose event has rungs
				-- authored, which today is both of them. An event added later with a `reward.characterKey`
				-- and no `EventQuests` entry lands here instead of on an empty board, which is why these
				-- three sentences stay and why they must stay true.
				local rot = GameConfig.GetRotationInfo(entry.key)
				if rot and rot.live then
					dHint.Text = ("Week %d of %d \u{2014} up for grabs in %s RIGHT NOW. Finish its %d-step event ladder and it is yours for good.")
						:format(rot.slot, rot.count, label, #GameConfig.GetEventQuests(entry.event))
					dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
				elseif rot and rot.nextStart then
					dHint.Text = ("Week %d of %d in the %s rotation \u{2014} its turn comes round in %s.")
						:format(rot.slot, rot.count, label,
							GameConfig.FormatDuration(rot.nextStart - GameConfig.EventNow()))
				else
					dHint.Text = ("Earned by finishing the %d-step event ladder during %s \u{2014} then it is yours for good.")
						:format(#GameConfig.GetEventQuests(entry.event), label)
				end
			else
				dHint.Text = "Evolve to " .. (stage and stage.name or "this stage") .. " to discover it."
			end
		elseif equipped then
			dHint.Text = ("This is what you look like right now.  You hit for %s."):format(formatNumber(progressDamage))
		elseif entry.vipDamageMult then
			-- THE ONE CARD IN THIS PANEL WHERE "a skin is looks only" IS FALSE (16.2), so it says the
			-- trade instead of denying there is one: what this skin would put on the body, against what
			-- is on it right now.
			dHint.Text = ("Wear it for x%s damage and x%s DNA \u{2014} %s instead of %s."):format(
				(("%.2f"):format(entry.vipDamageMult):gsub("%.?0+$", "")),
				(("%.2f"):format(entry.vipIncomeMult or 1):gsub("%.?0+$", "")),
				formatNumber(hud.getData() and math.floor(GameConfig.GetBaseDamage(hud.getData()) * entry.vipDamageMult) or 0),
				formatNumber(progressDamage))
			dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
		else
			local delta = math.floor(GameConfig.GetRankDamage(GameConfig.GetCharacterRank(entry))) - progressDamage
			if delta > 0 then
				dHint.Text = "Wear it freely \u{2014} a skin is looks only, your damage stays where you climbed to."
				dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
			elseif delta < 0 then
				dHint.Text = ("Costs you nothing \u{2014} you still hit for %s."):format(formatNumber(progressDamage))
				dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
			else
				dHint.Text = ("You hit for %s."):format(formatNumber(progressDamage))
				dHint.TextColor3 = Color3.fromRGB(146, 154, 174)
			end
		end

		-- LAST, because every branch above can still be writing a colour and the test is on the
		-- colour. (`dRarity` used to be excluded from this list by name -- its UIStroke was
		-- styleCard's BORDER rather than an outline around the glyphs. The ribbon is gone; the
		-- exclusion note is kept because the distinction still applies to anything styleCard'd
		-- that acquires a label.)
		inkOnLight(dName)
		inkOnLight(dSub)
		inkOnLight(dStatLabel)
		inkOnLight(dStatHp)
		inkOnLight(dHint)
	end

	-- REBUILDS THE FIGURE. Only from a click, never from a data push.
	local function selectCharacter(key)
		selectedKey = key
		if bigRig then
			bigRig:Destroy()
			bigRig, bigPivot = nil, nil
		end
		local refs = key and characterCells[key]
		local entry = refs and refs.entry
		local owned = entry and hud.getData() and hud.getData().Characters
			and hud.getData().Characters[entry.key] == true
		if owned then
			-- no part cap here: this is the one place a player is actually looking at the build, so
			-- it gets every rivet the body in the world has
			-- An off-ladder skin belongs to no stage: it is a recoloured version of whatever the
			-- player currently IS, so it previews at their stage rather than at a fixed one. (Build
			-- returns nil for a nil stage rather than erroring, so this is a correctness fix, not a
			-- crash fix.)
			--
			-- `offLadder` since 12.7, for the same reason as the damage label above: an event skin
			-- has `stage = nil` too, so testing `vip` left the detail well EMPTY for an owned event
			-- skin -- the one entry in the panel a player would most want to look at.
			local previewStage = (entry.offLadder and hud.getData() and hud.getData().StageIndex) or entry.stage
			bigRig = CharacterPreview.Build(bigArt, previewStage, entry)
			if bigRig then
				CharacterPreview.Frame(bigArt, bigRig, { zoom = 1.06, pitch = 0.12 })
				bigPivot = bigRig:GetPivot()
			end
		end
		bigMark.Visible = bigRig == nil
		bigMark.Text = entry and "?" or "\u{1F4D2}"
		if entry then
			stageStroke.Color = (owned and entry.color) or OUTLINE_COLOR
		end
		-- the rim on the selected cell, so the grid and the card agree about what is being shown
		for otherKey, other in pairs(characterCells) do
			other.selected = otherKey == key
		end
		paintDetail()
		-- refreshCharacterPanel is declared BELOW this function, so naming it here would read a
		-- global, not the upvalue -- it hands itself over on hud once it exists instead
		if hud.refreshCharacterPanel then hud.refreshCharacterPanel() end
	end

	equipButton.MouseButton1Click:Connect(function()
		-- FIRST, and with a return: an EquipCharacter for a skin the save does not own is a remote the
		-- server refuses, and the refusal would be the only thing this press produced.
		if boardMode then
			-- straight to the Quests tab rather than to whichever tab was last open -- the Season
			-- panel remembers, and landing on the XP track after pressing "open the event board" is
			-- the same broken promise the button is guarded against making.
			if hud.showSeasonPanel then hud.showSeasonPanel("quests") end
			return
		end
		if vipDoor then
			-- The KEY, never the pass id: the server holds the id, so the worst a tampered client can
			-- do is name a pass that exists. PassService owns every refusal from here -- unknown key,
			-- id 0, already an owner -- so this side has nothing left to check.
			if promptPass then promptPass:FireServer("VIP") end
			return
		end
		if selectedKey and equipButton.Active then
			Remotes.EquipCharacter:FireServer(selectedKey)
		end
	end)

	-- ===== THE RIGS, BUILT AS THEY COME INTO VIEW =====
	-- A hundred cells is a hundred rigs if they are all built, and the panel shows about eighteen
	-- at a time. So a cell builds its rig when it scrolls into the window and gives it back when it
	-- leaves, and only a few are built per pass -- a scroll that stops on a fresh row builds them
	-- over the next few frames instead of hitching on one.
	--
	-- ONE PASS IS NOT THE SAME AS ONE FRAME, AND THAT IS THE BUG THIS RETURN VALUE FIXES. A pass
	-- ran on three signals only: opening the panel, a scroll, and a DataUpdate. Opening it is ONE
	-- pass, so the panel used to open with two discs drawn and sixteen still showing the emoji
	-- stand-in, and the rest arrived one income tick at a time -- seconds of a half-built page, on
	-- the panel whose whole job is showing off a collection. Nothing was broken; the fill simply had
	-- no engine of its own. `fillPreviews` below is that engine.
	--
	-- Measured 2026-08-16 on the live client: a rig costs 3.15 ms to build and frame, so a window
	-- of eighteen is ~57 ms if it is done in one go -- three or four dropped frames, which is why
	-- this is still a budget and not a loop. Three per pass is ~9.5 ms, inside a 60 Hz frame, and
	-- fills a fresh window in six frames.
	local function syncPreviews(budget)
		if not (characterPanel.Visible and hud.getData()) then return 0 end
		local owned = hud.getData().Characters or {}
		local top = characterScroll.AbsolutePosition.Y
		local height = characterScroll.AbsoluteSize.Y
		if height <= 0 then return 0 end
		budget = budget or 3
		local built = 0

		for key, refs in pairs(characterCells) do
			local y = refs.cell.AbsolutePosition.Y - top
			-- a row of slack either side, so a slow scroll never shows an empty disc arriving
			local inView = y > -CHAR_LINE_H and y < height + CHAR_LINE_H
			if owned[key] and inView then
				if not refs.rig and budget > 0 then
					budget -= 1
					-- same rule as the detail card: an off-ladder skin previews at the player's own stage
					local previewStage = (refs.entry.offLadder and hud.getData().StageIndex) or refs.entry.stage
					refs.rig = CharacterPreview.Build(refs.art, previewStage, refs.entry, { maxParts = 26 })
					if refs.rig then
						CharacterPreview.Frame(refs.art, refs.rig, { zoom = 1.16 })
						refs.art.Visible = true
						refs.icon.Visible = false
						built += 1
					end
				end
			elseif refs.rig then
				refs.rig:Destroy()
				refs.rig = nil
				refs.art.Visible = false
				refs.icon.Visible = owned[key] == true
			end
		end
		return built
	end

	-- Keeps passing until the window has nothing left to build. It stops on its own -- a pass that
	-- builds nothing is the signal that the window is complete, and a cell whose rig fails to build
	-- returns 0 as well, so a missing PreviewRig ends the loop instead of spinning on it.
	--
	-- `filling` is the guard that matters: this is reached from three places (open, scroll,
	-- DataUpdate) and a scroll fires CanvasPosition on every frame of the drag. Without it a
	-- one-second drag would leave sixty of these loops running against each other.
	local filling = false
	local function fillPreviews()
		if filling then return end
		filling = true
		task.spawn(function()
			while characterPanel.Visible do
				if syncPreviews(3) == 0 then break end
				task.wait()
			end
			filling = false
		end)
	end

	-- Scrolling is the only thing that changes what is in view, and CanvasPosition is the only
	-- honest signal for it -- the cells live inside the scrolling frame and their own positions
	-- move with it.
	characterScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(fillPreviews)

	-- ===== THE COUNTDOWNS TICK ON THEIR OWN SECOND (26.3) =====
	--
	-- Everything else on this card is a function of the save, so a repaint on DataUpdate has always
	-- been enough. A window is a function of the CLOCK: "ends in 3h 04m" and the five discs' captions
	-- go stale between pushes, and the moment the window actually closes is the moment the card must
	-- stop offering a board that has gone. Same one-second tick, and the same visibility guard, the
	-- Season panel's own countdowns run on.
	--
	-- paintDetail is text and button only by contract -- it never rebuilds the figure -- so this
	-- costs a handful of strings a second while the panel is open, and nothing at all while it is
	-- shut.
	task.spawn(function()
		while true do
			task.wait(1)
			if characterPanel.Visible then
				paintDetail()
			end
		end
	end)

	-- ONE turntable, for the big figure only. Turning eighteen cell rigs as well would be six
	-- hundred part CFrames written every frame behind a panel, and a 96px disc reads no better
	-- moving than still.
	RunService.RenderStepped:Connect(function()
		if not (characterPanel.Visible and bigRig and bigPivot) then return end
		bigRig:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0) * bigPivot)
	end)

	hud.journalSelect = selectCharacter
	hud.journalPaintDetail = paintDetail
	-- The FILL, not one pass: `refreshCharacterPanel` calls this on every DataUpdate, and a
	-- discovery that lands while the panel is open should finish drawing the window rather than
	-- adding three discs to it and waiting for the next income tick.
	hud.journalSync = fillPreviews
	-- Opening the panel lands on the character you are wearing. An empty card next to a full grid
	-- reads as something that failed to load.
	hud.journalOnOpen = function()
		if not selectedKey and hud.getData() then
			local worn = hud.getData().WornCharacter
			if worn then
				selectCharacter(worn)
			end
		end
		fillPreviews()
	end

	paintDetail()
end
