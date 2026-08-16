-- PetRelease -- the confirm shade for releasing pets -- the one destructive action in the pet bag.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local themeLabel, styleCard, styleButton = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton

return function(hud)
	local colorTag, screenGui = hud.colorTag, hud.screenGui

	-- A LIST SINCE 11.17, never a single id. `HandleDeletePets` has taken a list since 10.3 and the
	-- one-pet confirm already sent `{ id }`, so making the dialog itself list-shaped removes the last
	-- place the two paths could drift -- the multi-select confirm is the same frames, the same
	-- handler and the same remote call, differing only in how many ids went in.
	local pendingIds = nil

	-- Newer than the authored Remotes folder, so it is waited for by name rather than indexed --
	-- PetService creates it on server start. Resolved once here instead of on every confirm: a
	-- WaitForChild inside a click handler would yield the handler on the one frame it matters.
	local deleteRemote = nil
	task.spawn(function()
		deleteRemote = Remotes:WaitForChild("DeletePets", 30)
		if not deleteRemote then
			warn("[MainUI] Remotes.DeletePets never appeared -- pet release is disabled")
		end
	end)

	local shade4 = Instance.new("TextButton")
	shade4.Name = "ReleaseShade"
	shade4.Size = UDim2.new(1, 0, 1, 0)
	shade4.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shade4.BackgroundTransparency = 0.45
	shade4.Text = ""
	shade4.AutoButtonColor = false
	shade4.Visible = false
	-- above every panel: this is a question, and anything drawn over it is a way to answer it by
	-- accident. The panels sit at ZIndex 20, so 60 clears them and their badges.
	shade4.ZIndex = 60
	shade4.Parent = screenGui

	local box = Instance.new("Frame")
	box.Name = "ReleaseDialog"
	box.Size = UDim2.new(0, 420, 0, 240)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.ZIndex = shade4.ZIndex + 1
	box.Parent = shade4
	styleCard(box, Color3.fromRGB(252, 252, 255), UDim.new(0, 18), 5)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -32, 0, 40)
	title.Position = UDim2.new(0, 16, 0, 14)
	title.BackgroundTransparency = 1
	title.ZIndex = box.ZIndex + UITheme.Z.Content
	title.Text = "Release Pet?"
	title.Parent = box
	themeLabel(title, 30)

	local petLine = Instance.new("TextLabel")
	petLine.Name = "PetLine"
	petLine.Size = UDim2.new(1, -32, 0, 34)
	petLine.Position = UDim2.new(0, 16, 0, 60)
	petLine.BackgroundTransparency = 1
	petLine.RichText = true
	petLine.ZIndex = box.ZIndex + UITheme.Z.Content
	petLine.Text = ""
	petLine.Parent = box
	themeLabel(petLine, 24)

	local warn4 = Instance.new("TextLabel")
	warn4.Name = "Warning"
	-- two lines of room for one line of text: themeLabel floors at 14 px, so a box too short for
	-- its wrapped text clips the overflow rather than shrinking it, and reports nothing wrong
	warn4.Size = UDim2.new(1, -40, 0, 52)
	warn4.Position = UDim2.new(0, 20, 0, 98)
	warn4.BackgroundTransparency = 1
	warn4.TextWrapped = true
	warn4.ZIndex = box.ZIndex + UITheme.Z.Content
	warn4.Text = "This pet will be permanently deleted."
	warn4.Parent = box
	themeLabel(warn4, 18, Color3.fromRGB(120, 124, 138))

	local cancel = Instance.new("TextButton")
	cancel.Name = "Cancel"
	cancel.Size = UDim2.new(0, 210, 0, 56)
	cancel.Position = UDim2.new(0, 20, 1, -72)
	cancel.Text = "CANCEL"
	cancel.ZIndex = box.ZIndex + UITheme.Z.Content
	cancel.Parent = box
	styleButton(cancel, UITheme.Color.Blue, UDim.new(0, 12), 4)
	themeLabel(cancel, 24)

	local confirm = Instance.new("TextButton")
	confirm.Name = "Confirm"
	confirm.Size = UDim2.new(0, 152, 0, 56)
	confirm.Position = UDim2.new(1, -172, 1, -72)
	confirm.Text = "RELEASE"
	confirm.ZIndex = box.ZIndex + UITheme.Z.Content
	confirm.Parent = box
	styleButton(confirm, UITheme.Color.Red, UDim.new(0, 12), 4)
	themeLabel(confirm, 24)

	local function close()
		pendingIds = nil
		shade4.Visible = false
	end

	cancel.MouseButton1Click:Connect(close)
	-- clicking the darkened backdrop cancels, which is what every modal in every game does and what
	-- a player will try first
	shade4.MouseButton1Click:Connect(close)
	confirm.MouseButton1Click:Connect(function()
		local ids = pendingIds
		close()
		if ids and #ids > 0 and deleteRemote then
			deleteRemote:FireServer(ids)
			-- leave select mode on the way out, so the panel does not come back still armed with a
			-- selection whose pets no longer exist
			if hud.petSelectExit then hud.petSelectExit() end
		end
	end)

	hud.confirmRelease = function(petId, displayName, rarityName, rarityColor)
		pendingIds = { petId }
		title.Text = "Release Pet?"
		petLine.Text = ("%s  %s"):format(displayName or "Pet",
			colorTag(rarityName or "", rarityColor or UITheme.Color.White))
		warn4.Text = "This pet will be permanently deleted."
		shade4.Visible = true
	end

	-- ===== THE SAME DIALOG, MANY PETS (11.17) =====
	--
	-- It names the COUNT rather than listing them: a release of thirty cannot show thirty names in a
	-- 420 px box, and a truncated list ("Wolf, Wolf, Wolf and 27 more") is worse than a number
	-- because it invites the reader to believe they have checked it. The place to check WHICH pets
	-- is the grid behind this dialog, where every one of them is drawn with a lit checkbox.
	--
	-- Copied rather than referenced: the caller's table is the live selection set and it keeps
	-- changing while this box is open, so holding a reference would let a click behind the dim
	-- change what CONFIRM is about to do.
	hud.confirmReleaseMany = function(ids)
		if type(ids) ~= "table" or #ids == 0 then return end
		local copy = table.create(#ids)
		table.move(ids, 1, #ids, 1, copy)
		pendingIds = copy
		title.Text = ("Release %d Pets?"):format(#copy)
		petLine.Text = ("%d selected"):format(#copy)
		warn4.Text = ("All %d will be permanently deleted. Equipped pets are never included."):format(#copy)
		shade4.Visible = true
	end
end
