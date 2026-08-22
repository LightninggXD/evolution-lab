--[[
	AdventureUI -- the door on the board, and the four screens behind it (30.6).

	=========================================================================================
	WHY THIS IS ITS OWN LOCALSCRIPT AND NOT A BLOCK IN MainUI
	=========================================================================================
	MainUI is at 181 of Luau's 200 top-level register cap. One more top-level `local` there deletes
	the whole HUD, silently, at load -- it has happened twice -- and a `do ... end` block does not
	help, because the cap is per function rather than per scope. SplicerUI, HatchReveal, EvolveReveal,
	MinigameUI and ExpeditionUI are the same decision made five times before this one.

	=========================================================================================
	THIS FILE DRAWS NOTHING
	=========================================================================================
	Four screens, four modules in `UIComponents`, on the owner's rule of 2026-08-22: a big file burns
	tokens on every read, so a feature ships as several small modules. What is left here is the
	wiring nothing else can own --

	  * the ScreenGui the four share, which is what makes the builder's own close-all sweep act on
	    exactly these four and nothing else in the game;
	  * the prompt, on the `ShopPanel` attribute contract SplicerUI established;
	  * `AdventureState`, the one outbound remote, handed straight to the run capsule.

	=========================================================================================
	THE PROMPT IS REFUSED WHILE A RUN IS LIVE
	=========================================================================================
	Not a guess about where the player is: `AdventureRunHud` holds the last `AdventureState` push,
	and the server is the only thing that writes it. The board stands in the village and a course is
	4,000 studs away, so this can only fire on a stale prompt or a second board -- but "only" is how
	the last three of these got shipped.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local SoundLibrary = require(ReplicatedStorage.Modules.SoundLibrary)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local components = script.Parent:WaitForChild("UIComponents")
local Common = require(components:WaitForChild("AdventureCommon"))
local AdventurePanel = require(components:WaitForChild("AdventurePanel"))
local AdventurePetPicker = require(components:WaitForChild("AdventurePetPicker"))
local AdventureAwayPanel = require(components:WaitForChild("AdventureAwayPanel"))
local AdventureRunHud = require(components:WaitForChild("AdventureRunHud"))

local gui = Instance.new("ScreenGui")
gui.Name = "AdventureUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- The same DisplayOrder the expedition and the arcade use. They cannot be up at the same time as
-- these -- an adventure run and an expedition run each teleport you off the other's map -- so there
-- is nothing here for a z-order to separate.
gui.DisplayOrder = 9
gui.Parent = playerGui

-- ORDER MATTERS FOR EXACTLY ONE REASON: each panel registers itself with `AdventureCommon` under a
-- name at Init, and the route list's footer buttons ask for "pets" and "away" BY NAME. A name with
-- nothing behind it is a no-op rather than an error, so a wrong order here would be a button that
-- silently does nothing -- which is why they are all built before anything can be pressed.
AdventurePanel.Init(gui)
AdventurePetPicker.Init(gui)
AdventureAwayPanel.Init(gui)
AdventureRunHud.Init(gui)

-- ===== THE ONE OUTBOUND REMOTE =====
-- `WaitForChild` and not a plain index: `AdventureService` find-or-creates this at server Init and
-- a client that finishes loading first would otherwise index a nil.
local AdventureState = Remotes:WaitForChild("AdventureState")
AdventureState.OnClientEvent:Connect(function(payload)
	AdventureRunHud.Apply(payload)
end)

-- ===== THE BOARD =====
-- `ShopPanel = "adventure"`, the attribute contract SplicerUI established and the arcade, the
-- expedition and the egg stall all reuse. MainUI's own handler looks the value up in a table with
-- no "adventure" row, so it falls through there and is picked up here.
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt:GetAttribute("ShopPanel") ~= "adventure" then return end
	if AdventureRunHud.IsRunning() then return end
	SoundLibrary.PlayLocal("open")
	Common.Open("routes")
end)
