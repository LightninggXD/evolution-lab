-- ===== THE PLAYER'S OWN COSTUME GOES SEE-THROUGH, AND NOTHING IN THIS GAME ASKS FOR IT =====
--
-- Roblox's default camera ships a TransparencyController that caches EVERY BasePart under the
-- local character -- recursively, and again on DescendantAdded -- and fades them when the camera
-- comes within two studs of its Focus:
--
--     transparency = (distance < 2) and (1 - (distance - 0.5) / 1.5) or 0
--
-- The costume is parented INTO the character (character.SkinMesh for a generated skin,
-- character.StageCostume for the primitive builders), so it is cached the instant it is welded on.
-- For a Focus distance between 0.5 and 1.25 studs every piece of it is written to a
-- LocalTransparencyModifier between 0.5 and 1.0 -- a half-dissolved player you can see the ground
-- through.
--
-- Two things about the symptom fall straight out of the property, and both match the report:
--
--   * LocalTransparencyModifier is CLIENT-LOCAL, so it is only ever your own body. The pets
--     running beside you and every other player stay solid, which is exactly what the screenshot
--     showed and what makes it look like the skin is broken rather than the camera.
--   * It keys off camera distance and nothing in the game state, so it comes and goes for no
--     reason a player can see. The body scales 1x to 9x across the twenty stages while the
--     camera's zoom stays in fixed studs, which is why it turns up in the late zones.
--
-- Nothing in this codebase writes Transparency or LocalTransparencyModifier to a costume part.
-- SkinMesh.Apply sets Anchored/CanCollide/CanQuery/CanTouch/CastShadow/Massless and no more; both
-- setBodyHidden implementations walk GetChildren() and so cannot reach inside a folder; and the one
-- Highlight on the character has FillTransparency = 1, i.e. it draws an outline and no fill.
--
-- ALL OF THAT WAS RE-MEASURED AGAINST THE FINISHED SET RATHER THAN ASSUMED, because the symptom
-- came back after this script was written and the obvious suspicion was that the art, not the
-- camera, had gone see-through. It has not:
--
--   * 200 templates, 1200 MeshParts. Transparency is 0 on every one of them. Zero
--     SurfaceAppearance, zero Texture, zero Decal -- so there is no alpha channel anywhere in the
--     wardrobe for a material to sample.
--   * The meshes are WATERTIGHT. Welding vertices by position and counting edges used by a single
--     triangle gives 0 boundary edges on every segment checked (wolf_grey, liz_sand, bact_dust).
--     An open shell would let you look straight through a creature with backface culling doing the
--     work, and would look exactly like this bug; it is not that either.
--   * Running SkinMesh.Apply on a stand-in rig and reading the result back: all six segments come
--     out Transparency 0, LocalTransparencyModifier 0, welded to six distinct R15 limbs.
--   * A source sweep over every LuaSourceContainer in the place finds exactly four writers of
--     Transparency/LocalTransparencyModifier on a character: the two setBodyHidden implementations
--     (direct children only), EvolveReveal (LTM, flagged, see below) and this file.
--
-- So the costume leaves the server opaque and arrives on the client opaque, and the only thing left
-- that can fade it is the controller above. That is what this file exists to undo.
--
-- WHY A KEEPER AND NOT A ONE-LINE OPT-OUT
--
-- TransparencyController lives in the PlayerModule Roblox injects at run time. It is not in
-- StarterPlayer in the Edit datamodel and there is nothing here to patch; overriding it means
-- committing a forked copy of the whole camera and control stack to the place, which is a much
-- larger thing to own forever than six property writes a frame. Raising CameraMinZoomDistance was
-- the other candidate and it does not hold: Poppercam pulls the camera in past the zoom setting
-- whenever geometry is between it and the subject, which on a platform this full of props is
-- often, and it would change how the camera feels at every stage to fix a bug at the late ones.
--
-- BindToRenderStep LAST, not a bare RenderStepped connection and not Camera + 10.
--
-- A plain RenderStepped connection is not a fix at all: connection order between two scripts on the
-- same signal is not something either of them controls, so it wins some frames and loses others,
-- which is a flicker. EvolveReveal found this out the hard way and says so in its own comment.
--
-- This file originally bound at RenderPriority.Camera + 10, on the reasoning that the controller
-- writes from the camera update at RenderPriority.Camera and +10 is after it. That is true and it
-- is still not enough, because "after the camera" is not the same as "last": the frame is drawn
-- after EVERY render-step callback has run, so anything bound above 210 -- another script here, a
-- future one, or the RenderStepped signal itself firing in an order nobody chose -- still gets the
-- final word on the property, and the final word is the one that is drawn. RenderPriority.Last is
-- 2000 and there is nothing above it, so this is now the last write of the frame by construction
-- rather than by an argument about who binds where.
--
-- IT ALSO KEEPS Transparency, not only the modifier. LocalTransparencyModifier is what the camera
-- writes and is the only thing that has ever been seen to move, but the two properties multiply
-- into the same pixel and guarding one of them is guarding half the problem. The value restored is
-- the one the part was BUILT with, not zero -- several StageCostume pieces are deliberately
-- translucent (chrono rings at 0.28, hourglasses at 0.25, energy wings), and forcing those opaque
-- would be a second bug wearing the first one's clothes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Both wardrobes, because a character has one or the other: SkinMesh when the stage has a
-- generated mesh filed for it, StageCostume when it falls through to the primitive builders.
local COSTUME_FOLDERS = { "SkinMesh", "StageCostume" }

-- EvolveReveal hides the whole body on purpose while its figure is on screen -- in third person
-- the real player stands a few studs from the camera, dead centre, exactly where the reveal is
-- drawn -- and it does that by writing LocalTransparencyModifier = 1 every frame, for the same
-- reason this script writes 0 every frame. It raises this flag while it is running and this stands
-- down. Without the handshake the two would fight over the property and the reveal would show the
-- player standing inside their own portrait.
--
-- THE FLAG IS A DEADLINE, NOT A BOOLEAN, and that is the whole point of it being a number.
--
-- A boolean has to be cleared by whoever set it, and the code that clears it is a RenderStepped
-- handler inside a reveal that can be destroyed, interrupted, or replaced by a second reveal a
-- frame later (a stockpiled player can absolutely evolve twice in a row). Every one of those paths
-- that fails to clear leaves this script standing down FOREVER on a character that never respawns
-- -- which does not hide anything, it simply hands the property back to the camera controller and
-- restores the exact bug this file was written to fix, permanently, with no way for the player to
-- get out of it. A deadline cannot leak: EvolveReveal pushes it forward every frame it is on
-- screen, and the instant it stops doing that -- cleanly or not -- this takes the property back.
-- A stale value, or a leftover boolean `true` from an older build, reads as expired and is ignored.
local HIDE_FLAG = "CostumeHidden"

-- Parallel arrays rather than a map: this is walked every frame and #parts is six for a generated
-- skin, so the ordered walk is both cheaper and lets a dead entry be removed by index.
local parts = {}
local authored = {} -- parts[i]'s Transparency as it was BUILT, so a restore cannot flatten a
                    -- deliberately translucent piece to opaque
local dirty = true

local function rescan(character)
	table.clear(parts)
	table.clear(authored)
	if not character then return end
	for _, name in ipairs(COSTUME_FOLDERS) do
		local folder = character:FindFirstChild(name)
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BasePart") then
					parts[#parts + 1] = d
					-- Read HERE and nowhere else. A costume folder is never edited in place -- both
					-- Apply paths destroy the whole folder and build a new one -- and a rebuild fires
					-- DescendantRemoving/DescendantAdded, which marks this dirty and re-reads. So the
					-- value captured at scan time is the authored one for the life of the entry.
					authored[#parts] = d.Transparency
				end
			end
		end
	end
end

-- MARK DIRTY, RESCAN LAZILY. The folder is parented to the character BEFORE its parts are put
-- inside it, so watching for the folder alone would rescan an empty one and find nothing; and a
-- costume is rebuilt on every evolve, so a single scan at spawn goes stale twenty times a run.
-- Listening for any descendant change and rescanning at most once per frame costs one boolean.
local function bind(character)
	table.clear(parts)
	dirty = true
	if not character then return end
	character.DescendantAdded:Connect(function() dirty = true end)
	character.DescendantRemoving:Connect(function() dirty = true end)
end

player.CharacterAdded:Connect(bind)
if player.Character then
	bind(player.Character)
end

RunService:BindToRenderStep("CostumeVisibility", Enum.RenderPriority.Last.Value, function()
	local character = player.Character
	if not character or not character.Parent then return end

	-- Expired, absent, or a boolean from an older build: all three mean nobody is currently holding
	-- the property, so take it.
	local hideUntil = character:GetAttribute(HIDE_FLAG)
	if type(hideUntil) == "number" and os.clock() < hideUntil then return end

	if dirty then
		rescan(character)
		dirty = false
	end

	-- Backwards, so removing a stale entry cannot skip the next one. The `~=` guards are not
	-- micro-optimisation: assigning a property that already holds the value still fires a change
	-- signal, and on a normal frame nothing has written anything and there is nothing to undo.
	for i = #parts, 1, -1 do
		local part = parts[i]
		if part.Parent then
			if part.LocalTransparencyModifier ~= 0 then
				part.LocalTransparencyModifier = 0
			end
			local want = authored[i]
			if want and part.Transparency ~= want then
				part.Transparency = want
			end
		else
			table.remove(parts, i)
			table.remove(authored, i)
		end
	end
end)
