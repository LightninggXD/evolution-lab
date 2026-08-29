local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local SoundLibrary = require(ReplicatedStorage.Modules.SoundLibrary)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local DNAService = require(ServerScriptService.DNAService)
local FriendBonusService = require(ServerScriptService.FriendBonusService)
local ZoneBuilder = require(ServerScriptService.ZoneBuilder)
local ZoneService = require(ServerScriptService.ZoneService)
local EvolutionVisuals = require(ServerScriptService.Systems.EvolutionVisuals)
local VFXService = require(ServerScriptService.Systems.VFXService)
local AnnounceService = require(ServerScriptService.AnnounceService)
local PetService = require(ServerScriptService.PetService)
local PetFollowService = require(ServerScriptService.PetFollowService)
local CreatureService = require(ServerScriptService.CreatureService)
local BossService = require(ServerScriptService.BossService)
local RebirthService = require(ServerScriptService.RebirthService)
local RebirthShrine = require(ServerScriptService.RebirthShrine)
local SecretsService = require(ServerScriptService.SecretsService)
local InviteRewardService = require(ServerScriptService.InviteRewardService)
local TrainingDummyService = require(ServerScriptService.Training.TrainingDummyService)
local SplicerService = require(ServerScriptService.SplicerService)
local RewardService = require(ServerScriptService.RewardService)
local PotionService = require(ServerScriptService.PotionService)
local RelicService = require(ServerScriptService.RelicService)
local PassService = require(ServerScriptService.PassService)
local RobuxShopService = require(ServerScriptService.RobuxShopService)
local PlaytimeGiftService = require(ServerScriptService.PlaytimeGiftService)
local SeasonPassService = require(ServerScriptService.SeasonPassService)
local CodesService = require(ServerScriptService.CodesService)
local OfflineService = require(ServerScriptService.OfflineService)
local LeaderboardService = require(ServerScriptService.LeaderboardService)
local StatsService = require(ServerScriptService.StatsService)
local EventService = require(ServerScriptService.EventService)
local HubPlaza = require(ServerScriptService.HubPlaza)

local WorldApron = require(ServerScriptService.WorldApron)
local WaterfallParkour = require(ServerScriptService.WaterfallParkour)
local TradeService = require(ServerScriptService.TradeService)
local MinigameService = require(ServerScriptService.MinigameService)
local ExpeditionService = require(ServerScriptService.ExpeditionService)
local AdventureService = require(ServerScriptService.AdventureService)
local AdventureRemotes = require(ServerScriptService.AdventureRemotes)
local ForestMapService = require(ServerScriptService.ForestMapService)
local BoardStats = require(ServerScriptService.MapProps.BoardStats)
local MapCounters = require(ServerScriptService.MapProps.MapCounters)
local MapEggs = require(ServerScriptService.MapProps.MapEggs)
local MapSquare = require(ServerScriptService.MapProps.MapSquare)
local MapArcade = require(ServerScriptService.MapProps.MapArcade)
local MapPortals = require(ServerScriptService.MapProps.MapPortals)
local MapSigns = require(ServerScriptService.MapProps.MapSigns)
local MapSettle = require(ServerScriptService.MapProps.MapSettle)
local MapAdventureBoard = require(ServerScriptService.MapProps.MapAdventureBoard)
local SwordService = require(ServerScriptService.Sword.SwordService)
local LevelService = require(ServerScriptService.Level.LevelService)
local Telemetry = require(ServerScriptService.Telemetry)

-- ===== STREAMING =====
-- The two radii that decide how much world a client is holding. Roblox's defaults (min 64,
-- target 1024) are sized for a place you walk around; this one is a 36,000-stud strip of 1250 x
-- 1150 platforms, and at 64 studs of guaranteed detail a player standing still can watch the far
-- half of their own zone leave.
--
-- ===== THESE ARE PLACE SETTINGS, NOT SCRIPT SETTINGS. DO NOT PUT THE CODE BACK (2026-08-15) =====
--
-- There used to be a guarded `workspace.StreamingMinRadius = 512` block here that warned when it
-- failed. It failed EVERY server start, twice, because these three properties are not scriptable at
-- all -- not read-only, not scriptable: asking for `workspace.StreamingMinRadius` from a script or
-- from a plugin answers `StreamingMinRadius is not a valid member of Workspace`, so there is no
-- version of that code that can ever succeed and no value it can even read back to check. It was
-- two lines of noise per boot advising a fix it could not tell you had already been applied.
--
-- Set them BY HAND, once, and they are saved in the place file:
--     Explorer -> Workspace -> Properties -> Behavior
--     StreamingMinRadius      512    (Roblox default 64 -- far too small for this strip)
--     StreamingTargetRadius   3000   (Roblox default 1024)
--     StreamingIntegrityMode  PauseOutsideLoadedArea
-- The last one stops the character being simulated into a region the client has not got yet, which
-- is the other half of "I fell through the world after a teleport".

-- World geometry first, and before anyone can join: CreatureService and BossService place their
-- spawns relative to the zone platforms, and EnsureSpawn has to move the SpawnLocation off the
-- Forest shop footprint. Build() is also what trips the BUILD_VERSION guard that regenerates
-- zone geometry left over from an older version of this file.
ZoneBuilder.Build()

-- IMMEDIATELY AFTER Build(), and that ordering is the whole design of the file. `ForestMapService`
-- replaces a zone's generated dressing with a hand-built map, so it has to run when the dressing
-- exists and BEFORE anything measures the ground: `CreatureService` and `BossService` place spawns
-- against the platform, `HubPlaza` and the leaderboards search the live ground for a clear spot,
-- and `EnsureSpawn` moves the SpawnLocation off whatever it finds. Every one of those would be
-- reading a zone that is about to be rebuilt underneath them if this ran later.
--
-- It does NOT edit `ZoneBuilder`, deliberately -- that file is two registers from Luau's local cap.
-- Delete this line and the zone comes back exactly as it was built.
ForestMapService.Init()
-- IMMEDIATELY AFTER, AND BEFORE PotionService BELOW (31.6). The map's shop, upgrades, potion and
-- spin props get their prompts here; the potion one is a `MysteryCost` attribute and PotionService
-- finds its counters by scanning workspace.Zones ONCE at its own Init. Wire these after that scan
-- and the pad is a prompt that does nothing, with no error anywhere -- which is exactly the failure
-- shape 30.17 spent a session on.
MapCounters.Init("Forest")
-- 31.17: the map's thirteen zone doors were advertising "1K REBIRTHS" ... "500Qd REBIRTHS" over the
-- ASSET's zone names, in a game where a zone costs a stage and a boss kill and nothing else. They
-- now carry our zones, our requirements and a prompt into `ZoneService.HandleTeleportRequest` --
-- which is the server's own unlock rule, not a second copy of it. Anywhere after ForestMapService
-- would do; it is here so the whole "the map's furniture becomes the game's furniture" block reads
-- in one place.
MapPortals.Init("Forest")
-- Row 30.20, carried since 30.19: `EggPlaza` drops a 123 x 47 x 45 market stand at (0, -6), which is
-- the middle of the village square. The eggs move onto the map's own egg spots and the stall goes.
-- The PetShop model keeps its name and its parent throughout -- `PetService.WireKiosks` finds the
-- eggs by walking it BY NAME, and a rename kills egg buying and Auto Hatch with no error at all.
--
-- 30.24 moved the eggs again, off the map's egg row and onto a ring at the square's own centre where
-- the fountain stood; 30.25 stopped them floating by asking the ground how high it is instead of
-- carrying the height they had on props this pass deletes.
--
-- `MapSquare` runs immediately after and is the "okolo" half of her drawing -- shop, upgrades and
-- potions ringed around those eggs. IT MUST RUN AFTER EVERY READER OF `MapAnchors`' CACHED `pos`:
-- moving an instance leaves the census's measured position stale, and `MapCounters` (which wired its
-- prompts fifteen lines above) is exactly such a reader. It finds its target through the registry's
-- INSTANCE, so the doors travel with the props -- but a consumer that trusted the coordinate would
-- not.
do
	local forestZone = workspace:FindFirstChild("Zones")
	forestZone = forestZone and forestZone:FindFirstChild("Forest")
	if forestZone then
		MapEggs.Reseat("Forest", forestZone)
		MapSquare.Arrange("Forest", forestZone)
		-- 32.3, AND LAST OF THE MAP BLOCK ON PURPOSE. The village's carved arrows are aimed at what
		-- they name, and an aim is a bearing taken from where the sign stands to where the target
		-- stands -- so every pass that MOVES either of them has to have run already. `MapPortals`
		-- above re-lays the zone doors onto a ring (the `Worlds` arrow was 23.2 degrees off the
		-- mouth because of it) and `MapSquare` on the line above moves props and can carry a loose
		-- one with a pad. Aim before those and the sign points where the target used to be, which
		-- is exactly the fault this row opened on.
		MapSigns.Init("Forest", forestZone)
		-- ===== AND THE SETTLE AGAIN, BECAUSE THIS BLOCK IS THE REAL END OF THE BUILD (34.47) =====
		-- `ForestMapService.Init` finishes on `MapSettle.Forest`, and that file calls itself the pass
		-- that runs LAST and measures the FINISHED world. It was -- until these four lines. `MapEggs`
		-- drops 89 stall pieces and `MapSquare` carries three shop groups across the village, so a prop
		-- that was resting on one of them is in mid-air the moment it leaves and NOTHING looks again.
		-- Measured 2026-08-28 on a fresh build: two `Leaves` over the old potions spot at (-55, -55),
		-- feet 16.4 and 17.9 with nothing under them but the village floor, and no line in the log --
		-- the build's own settle had reported them correctly seated an instant before the stall moved.
		--
		-- Idempotent by construction, which is the whole reason this is a second CALL and not a moved
		-- one: the build's own pass keeps reporting what the MAP build stranded, and this reports what
		-- THIS block stranded. A quiet zero here is the assertion that the two agree.
		local villageMap = forestZone:FindFirstChild("VillageMap")
		if villageMap then
			local reSettled, reChecked, reWorst, reWorstName = MapSettle.Forest(villageMap)
			print(("[MapSettle] Forest: %d of %d props re-settled after the square was arranged%s")
				:format(reSettled, reChecked,
					reSettled > 0 and (", worst %.1f studs on %s"):format(reWorst, reWorstName) or ""))
		end
	end
end

-- Before PlayerDataService, and therefore before anyone can join. The three SoundGroups have to
-- exist on the server so they REPLICATE: every client resolves them by name and sets its own
-- Volume on its own copy, which is what makes one player muting the music a local act. A client
-- that arrived first and made its own would end up on a fader nothing else in the game touches.
SoundLibrary.EnsureGroups()

-- ===== FIRST, AND BEFORE PlayerDataService (Phase 20) =====
-- Telemetry connects its own `PlayerRemoving`, and what it does there is read the player's live
-- balance out of `PlayerDataService.Cache` to stamp on the batched economy events it is about to
-- flush. `PlayerDataService`'s own `PlayerRemoving` CLEARS that cache entry. Signal handlers run
-- in connection order, so connecting first is the whole difference between an aggregate that
-- carries a real ending balance and one that carries nothing.
--
-- It requires no other service at load time (its two lookups are lazy, see the note over `flush`),
-- so nothing else has to move to let it go here.
Telemetry.Init()
PlayerDataService.Init()
DNAService.Init()
FriendBonusService.Init()
-- AFTER DNAService, and the order is a preference rather than a constraint: it connects one remote
-- and reads nothing at Init time. It is placed here because it is the other half of the same
-- purchase surface -- `SwordService.HandleBuy` is `HandleBuyDiamondUpgrade` beat for beat -- and
-- because the sword's damage term is quoted from `DNAService.GetCombatDamage`, so a reader
-- following that line arrives at the two Init calls together.
--
-- NOTE THE BLADE ITSELF IS NOT WELDED FROM HERE. `SwordModel.Apply` is called from
-- `EvolutionVisuals.dress`, the one place that knows when the costume has finished building the
-- hand it hangs on.
SwordService.Init()
-- AFTER PlayerDataService, and that is the only ordering constraint it has: its whole Init is one
-- 0.4-second loop that publishes `Level` and `LevelXp` as player attributes, and that loop reads
-- the data cache. It connects no remote and no player signal -- the sweep IS the wiring, so a
-- player who joins, loads, rebirths or has their save written by a probe publishes themselves.
--
-- NOTE THE BAR IS NOT FILLED FROM HERE. `LevelService.AwardDamage` is called from `CreatureService`
-- and `BossService`, the two places in the game where a blow lands.
LevelService.Init()
-- BEFORE ZoneService, and that is the whole ordering constraint. An expedition map is parented
-- into `workspace.Zones` and its exit gate is a `PortalGate` -- which ZoneService.Init wires by
-- scanning that folder ONCE, at startup. Build the map after that scan and the way home is a
-- decorative slab. It is also before every Forest-furniture service (RebirthShrine, the
-- leaderboards, the Splicer, HubPlaza), which is correct: those all search the live ground for a
-- clear spot, so the door being there first is what makes them avoid it.
ExpeditionService.Init()
ZoneService.Init()
EvolutionVisuals.Init()
-- before BossService: it owns the proximity gate the boss auras register themselves with, and
-- Init() wipes the previous run's ZoneVFX folder
VFXService.Init()
-- before PetService, which publishes to it on the very first hatch: Init() is what puts
-- Remotes.RarityBeam there, and the client waits on that remote by name
AnnounceService.Init()
PetService.Init()
PetFollowService.Init()
CreatureService.Init()
BossService.Init()
-- AFTER BossService.Init, and that is a hard constraint rather than a preference: its first act is
-- to destroy every child of `workspace.Bosses`, and an expedition Core lives in that folder so the
-- combat client can target it without knowing what an expedition is. Built in ExpeditionService.Init
-- (line 92) the Cores are created and then wiped here, silently -- nothing errors, the folder simply
-- comes out holding twenty bosses and no Cores. The full argument is above BuildCores itself.
ExpeditionService.BuildCores()
RebirthService.Init()
-- after RebirthService (it wires each statue's prompt straight into HandleRebirth) and after
-- ZoneBuilder.Build() above, which is what puts the Forest decor the plaza has to clear back
RebirthShrine.Init()
SecretsService.Init()
-- ANYWHERE AFTER PlayerDataService: it reads a save and a DataStore and no world furniture at
-- all. Its Init also sweeps the players already in the server -- see the note there.
InviteRewardService.Init()
-- AFTER SecretsService, and the order is load-bearing in one direction only: the dummy is seated by
-- RAYCAST onto the grotto floor (`TrainingDummyModel.floorAt`), so the room has to be built before
-- this runs or the cast finds the world floor 0.2 studs lower and the dummy sinks into the slab.
-- `MapWaterfall` builds that room inside `ForestMapService.Init`, which ZoneBuilder.Build above has
-- already run -- see `evolution-lab-placement-search-ordering`, which is this same rule stated once
-- for the whole map.
--
-- It also has to be after `SecretsService` for a second, softer reason: that service prints the
-- UNREACHABLE warning for a blocked secret, and if the dummy were ever mis-seated into the trigger
-- the warning should name the state the world ends up in, not an intermediate one.
TrainingDummyService.Init()
-- The five counters the map's leaderboard boards read (31.5). ANYWHERE AFTER PlayerDataService:
-- it connects PlayerAdded/PlayerRemoving and starts one 60-second banking loop, and reads no world
-- furniture at all. It has to be before any player can join, which everything in this file is.
BoardStats.Init()
RewardService.Init()
PotionService.Init()
-- ANYWHERE AFTER PlayerDataService, and that is the whole constraint. RelicService wires four
-- remotes and reads nothing at init time -- no world furniture, no prompts, no other service. It
-- sits here beside PotionService because a relic and a potion are the same KIND of thing to this
-- file (a consumable-ish inventory owned by the player), not because anything requires it to.
RelicService.Init()
-- before RobuxShopService: both take a Robux purchase path, and PassService owns the one that has
-- to be answered on join (a pass is permanent and is read by the stat functions on the first click,
-- where a developer product is a one-off receipt that can arrive whenever)
PassService.Init()
RobuxShopService.Init()
PlaytimeGiftService.Init()
SeasonPassService.Init()
CodesService.Init()
-- after ZoneBuilder.Build() above, which is what puts the Forest ground the signs stand on there.
-- It builds its own furniture rather than going through ZoneBuilder -- see the note in that file.
LeaderboardService.Init()
StatsService.Init()
-- after ZoneBuilder.Build() for the same reason the leaderboards are -- it stands its own sign on
-- the Forest ground -- and after AnnounceService, which is what it announces an opening window
-- through. It reads no other service's state: whether an event is live is arithmetic on the clock.
EventService.Init()
-- MOVED HERE FROM ABOVE RewardService (12.13), and the bug it caused is the argument for the whole
-- ordering block. The Splicer searches the LIVE Forest ground for a spot nothing is standing on, so
-- everything that stands on that ground has to be there FIRST -- and it used to run before both the
-- leaderboards and the event sign, i.e. before two of the four things standing on exactly that
-- ground. Photographed on the live world: the preferred spot (120, 215) was rejected for a single
-- 1.8-stud GlintPost, the search stepped one ring east to (146, 215), and the machine's 27-stud box
-- closed over the event sign's panel at x 148.5..151.5. Nothing reported it -- both structures
-- built successfully, and each is idempotent about its own parts and blind to the other's.
--
-- Its own earlier constraints are all still met here: after ZoneBuilder.Build() and RebirthShrine
-- (the ground and the plaza it has to clear) and after AnnounceService, which is how a Mythic-or-
-- better roll reaches the room.
SplicerService.Init()
-- LAST of the Forest furniture, and that ordering is the whole design: the plaza is a floor laid
-- UNDER four things built by four other services, and every upright piece of it searches the live
-- ground for a spot nothing is standing on. Run it before the leaderboards, the event sign or the
-- Splicer exist and it would happily stand a lamp post exactly where one of them is about to go.
HubPlaza.Init()

-- Straight after the plaza, and it must be after ZoneBuilder: this reads WorldShell's floors to
-- learn where the twenty zones are and what colour each one's ground is. Its own stamp, so it
-- never drags BUILD_VERSION and its 105,000 parts along with a scenery change.
WorldApron.Init()
-- Beside the apron, and for the same reason it is here rather than in ZoneBuilder: its own stamp,
-- so the climb up the falls never drags BUILD_VERSION and its 105,000 parts along with it, and it
-- lives at the top of Workspace rather than under `Zones` so a zone rebuild cannot take it.
--
-- ITS ONE REAL ORDERING CONSTRAINT IS `ForestMapService.Init()` FAR ABOVE, which is what runs
-- `MapWaterfall` and puts `Decorations.Waterfall` in the world. Every ledge above the shore is
-- seated by a raycast into that model's rock, and with it absent the whole route would fall back
-- to one default Z and build a ladder in open air -- so it warns and skips instead, the same shape
-- of guard as WorldApron's missing WorldShell. Anywhere after ForestMapService would do; it is
-- here so the two version-stamped scenery builds read as one block.
--
-- It is deliberately AFTER `SecretsService.Init()` as well, though nothing would break the other
-- way round: that service prints the UNREACHABLE warning for a blocked secret, and the Hidden Egg
-- at the top of these falls is the secret this route exists to reach. If the two ever disagree,
-- the log should show the world the player actually gets.
WaterfallParkour.Init()
-- LAST, and after DNAService in particular: the offline payout is DNAService.GetAutoCollectAmount
-- multiplied by a bounded number of seconds, so it has to run once the income stack it reads is
-- fully wired. It hooks PlayerAdded itself rather than being called from the block below, because
-- it needs its own wait-for-data anyway and folding it in there would make that block do two jobs.
OfflineService.Init()
TradeService.Init()
-- AFTER ZoneBuilder.Build() above, and that is its only ordering constraint -- it stands twenty
-- arcade cabinets on twenty zone platforms and needs the ground under them to exist. It is NOT in
-- the Forest-furniture block further up: those four all search the SAME plaza for a clear spot and
-- have to run in a fixed order against each other, while a terminal stands beside its own zone's
-- arrival pad, where none of them ever goes. It reads no other service's state.
MinigameService.Init()
require(script.Parent.AchievementService).Init()
require(script.Parent.CosmeticService).Init()
require(script.Parent.CommunityGoalService).Init()
-- STRICTLY AFTER IT (31.8), and that is the point: the mapped zone gets a row of the owner's own
-- arcade cabinets in the village instead of a generated slab on the arrival plaza, and it works by
-- REPARENTING the prompt MinigameService just built rather than by making a second one. Run it
-- before and there is no prompt to take; make our own instead and the feature has two doors that can
-- disagree about their attributes.
MapArcade.Init("Forest", 0)
-- NO ORDERING CONSTRAINT AT ALL, and that is worth one line because every other world-building
-- service on this list has one. An adventure course is built on FIRST ENTRY rather than at Init --
-- twenty obbies is five times the expedition's geometry for a feature most servers never open --
-- so this call creates an empty `workspace.Adventures` folder and connects one Heartbeat and
-- nothing else. It is deliberately NOT ahead of `ZoneService.Init` the way `ExpeditionService` is:
-- that ordering exists so the one-shot `PortalGate` scan finds the expedition's exit gates, and a
-- lazily built map can never be in that scan whatever order this runs in. `AdventureService` wires
-- its own gates at build time instead -- see the header of that file.
AdventureService.Init()
-- AFTER IT, AND ONLY BECAUSE OF ONE REMOTE. `AdventureService` find-or-creates `AdventureState`
-- for its own outbound run pushes and this file find-or-creates the five inbound doors, so either
-- order lands on the same instances -- but the doors call into that service, and a door connected
-- before the folder it drives exists is the shape of bug 30.6 spent the whole row avoiding.
AdventureRemotes.Init()
-- ...and the board those doors are opened FROM.
--
-- 30.32 gave it a second ordering constraint and it is a hard one: the board now asks `MapSquare`
-- for a spot on the square's ring, so it must run AFTER `MapSquare.Arrange` -- which is where the
-- shops take their bearings and fill `MapSquare.Placed`. It does, by about a hundred and thirty
-- lines. Run it earlier and the board picks a bearing a shop is about to be moved onto, and the
-- shop's own `taken` test never sees the board because the board is not one of its anchors.
--
-- Its old note said the coordinate "is authored and never searched for, which cuts both ways: it
-- cannot be displaced by anything, and it cannot get out of anything's way either". The second half
-- is what she photographed -- the authored spot was the artist's dirt road.
MapAdventureBoard.Init("Forest", 0, workspace.Zones:FindFirstChild("Forest"))

-- Hook evolution -> zone unlock checks + visual update (kept out of DNAService to avoid circular requires)
DNAService.OnEvolve = function(player, data)
	ZoneService.CheckUnlocks(player, data)
	EvolutionVisuals.ApplyStage(player, data.StageIndex, { animate = true, burst = true })
	-- THE TUTORIAL FLAG MOVED OUT OF THIS HOOK (10.12) and the reason is worth keeping here, because
	-- this is where anyone would look for it. This function only runs when an evolve ADVANCES THE
	-- STAGE, and since 9.5 made every skin its own evolve that is every fifth press -- so marking
	-- the tutorial done here left a new player being told to press EVOLVE for four presses after
	-- they already had. It is set in `DNAService.HandleEvolve` now, on the first evolve of any kind,
	-- which is where "an evolve succeeded" is actually known. Still server-side, still one line.
end

-- Stage Mastery raises walk speed and max health, which live on the Humanoid -- push them onto
-- the live character the moment one is bought instead of waiting for the next respawn.
DNAService.OnMasteryChanged = function(player, data)
	EvolutionVisuals.RefreshBonuses(player, data)
end

-- The 2x Speed pass lands on the Humanoid too, and it can arrive at any point in a session: on the
-- join refresh, on a purchase, or on a background re-check that finally got an answer out of the
-- ownership API. Same treatment as Stage Mastery above, for the same reason -- otherwise the player
-- pays for speed and does not move any faster until they next die.
PassService.OnPassesChanged = function(player, data)
	EvolutionVisuals.RefreshBonuses(player, data)
	-- CombatClient reads this attribute rather than the pass table. The server stays the only thing
	-- that knows what is owned, the client needs no remote and no re-wire, and a purchase applies on
	-- the very next swing. Runs on the join refresh too, so it is always set before the first fight.
	player:SetAttribute("AutoSpeedMult", GameConfig.GetPassMult(data, "autoSpeedMult"))
	-- Grants the VIP skin, and takes it back if the pass ever goes. Safe to run on every refresh:
	-- it is idempotent, and it is the only thing that ever writes that key.
	GameConfig.SyncVipCharacter(data)
	-- Read by VipFlair on every client to draw the aura and the chat tag. An attribute rather than a
	-- remote because it replicates to EVERYONE by itself, which is exactly what a badge needs: other
	-- players have to see it, and that is most of what the buyer is paying for.
	player:SetAttribute("IsVIP", GameConfig.OwnsPass(data, "VIP"))
end

-- Wearing a different character from the Journal. The body is rebuilt rather than recoloured: the
-- character's colour is what StageCostume paints every shell and every detail with, and there is no
-- cheaper way to re-run that than the build itself. Not animated -- nothing is changing size, and a
-- 0.6s scale tween on a costume swap would read as a second evolve.
DNAService.OnCharacterChanged = function(player, data)
	EvolutionVisuals.ApplyStage(player, data.StageIndex, { animate = false, burst = false })
end

-- Rebirth resets stage/zones, so re-run the same unlock + visual reset logic as evolving does
RebirthService.OnRebirth = function(player, data)
	ZoneService.CheckUnlocks(player, data)
	-- A rebirth clears `data.Characters` wholesale, which takes the VIP skin with it even though the
	-- pass is untouched. Put it back BEFORE the body is rebuilt, or a VIP who rebirths while wearing
	-- it respawns in a skin the save no longer lists.
	GameConfig.SyncVipCharacter(data)
	-- The same wipe takes any event-exclusive skin with it, and unlike the VIP one there is nothing
	-- live to re-grant it from once the window has shut -- so it is restored from the permanent
	-- record instead. See GameConfig.SyncEventCharacters.
	GameConfig.SyncEventCharacters(data)
	EvolutionVisuals.ApplyStage(player, data.StageIndex, { animate = true, burst = true })
end

-- The body, not just the save. RebirthService resets CurrentZone/UnlockedZones to Forest, but a
-- player who triggered the shrine in zone 12 was left STANDING in zone 12 at stage 1 -- on ground
-- whose creatures hit for x8.4, in a zone their own unlock list no longer contains. Called last,
-- after OnRebirth above has rebuilt the body at its new size, so the teleport moves a finished
-- character rather than one halfway through a 0.6s scale tween.
--
-- SendToZoneSpawn, not ReturnToCurrentZone: RebirthService has already set `CurrentZone = "Forest"`
-- by the time this runs, and ReturnToCurrentZone returns early on Forest (the respawn case needs no
-- move, since the one SpawnLocation is there). That early return is why the body never travelled.
RebirthService.OnReturnHome = function(player)
	task.delay(0.8, function()
		if player.Parent then
			ZoneService.SendToZoneSpawn(player, "Forest")
		end
	end)
end

-- Check zone unlocks for returning players once their data has loaded
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local data
		repeat
			task.wait(0.2)
			data = PlayerDataService.Get(player)
		until data or not player.Parent
		if data then
			ZoneService.CheckUnlocks(player, data)
			-- A save from before the Journal existed has an empty collection and a stage index well
			-- past 1, so it would show a locked grid until the player next evolved -- and a player at
			-- stage 20 never evolves again. One roll for the stage they are actually standing at, and
			-- only when they own nothing at all, so it can never top up an ordinary collection.
			-- THERE IS ALWAYS A SELECTED CHARACTER. Rank 1 is not a reward, it is the default body --
			-- without it the Journal opens on a grid with no tile selected and the player is standing
			-- in a look that belongs to no entry. Granted directly rather than through RollCharacter
			-- so it makes no noise: this is the starting state, not a find. Rebirth does the same thing
			-- at its own reset; see RebirthService.
			data.Characters = data.Characters or {}
			local first = GameConfig.GetBaseCharacterForStage(1)
			if first and not data.Characters[first.key] then
				data.Characters[first.key] = true
				PlayerDataService.PushToClient(player)
			end
			if data.WornCharacter == nil and first then
				data.WornCharacter = first.key
				PlayerDataService.PushToClient(player)
			end
		end
	end)
end)

print("[Evolution Lab Tycoon] Server systems initialized.")
