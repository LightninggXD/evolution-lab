--[[
	SoundLibrary -- every sound in Evolution Lab, and the one function that plays it.

	The game shipped with exactly ONE Sound instance in the whole place, inside an unused VFX pack.
	This is the file that fixes that, and it is deliberately shaped like VFXLibrary next door: a
	table of assets, one lookup that errors loudly on a typo, and a Play() that both the server and
	the client can call.

	=========================================================================================
	WHERE THE IDS CAME FROM, AND WHY THEY ARE NOT INVENTED
	=========================================================================================
	Every id below was found with Studio's asset search and then LOADED IN THIS PLACE before it
	was written down: a Sound per candidate, ContentProvider:PreloadAsync, and the pair
	(AssetFetchStatus == Success, TimeLength > 0) recorded. 38 of 38 passed. That check matters
	more than it looks -- a Roblox audio asset that is moderated, private or simply wrong is not
	an error, it is SILENCE, and silence is indistinguishable from "the code never fired".

	Most of them come from ProSoundEffects, the library Roblox licensed and gave away free. They
	are picked over the higher-ranking community uploads on purpose: their descriptions state what
	the recording actually is ("Duration: 0.9 seconds, Category: Weapons - Misc, Axe Impact, Giant,
	Thuddy Hits") where a community upload is called `fish4`. Nobody working on this file can hear
	it, so a described asset is the only kind that can be chosen on evidence.

	THE TWO ENTRIES THAT ARE STILL A GUESS, flagged rather than hidden:
	  * `desert` ambience is APM's "African Dawn" -- arid and open, but it is a savannah, not a
	    dune field. It wants a proper wind bed.
	  * `arena` is a beast's breathing loop, which suits a colosseum but was chosen for atmosphere
	    rather than because it is an arena recording.

	=========================================================================================
	HOW A SOUND GETS TO A SPEAKER
	=========================================================================================
	Three SoundGroups live under SoundService: SFX, UI and Ambience. Every Sound this module
	creates is assigned to one, which is what makes the volume setting (Phase 4.6) a THREE-LINE
	operation instead of a walk over every live Sound in the datamodel. The groups are created by
	the server in EnsureGroups() -- before any player can join, so they have replicated by the time
	a client asks -- and each client then sets its own Volume on its own copy. A local write to a
	replicated object stays local, which is exactly the behaviour a per-player setting needs.

	2D vs 3D is decided by the call, not by the entry: pass a BasePart/Attachment and you get a
	positional sound at that part, pass nothing and you get a flat one. A creature dying across
	the platform should fade with distance; a button click should not.

	=========================================================================================
	FOUR TRAPS, ALL OF WHICH FAIL SILENTLY
	=========================================================================================
	1. `Sound.TimeLength` IS 0 UNTIL THE ASSET LOADS. The obvious cleanup --
	   `Debris:AddItem(sound, sound.TimeLength)` -- therefore destroys the sound on the very first
	   play of a session, before it has made a noise, and works perfectly every time after. See
	   `lifetimeOf`: the table's own `len` is the source of truth and TimeLength is only a check.
	2. A REPEATED SOUND AT A FIXED PITCH READS AS A BUG. The auto-attack swings every 0.34s (0.20s
	   with the pass); the identical wav forty times in a row sounds like a stuck loop rather than
	   like fighting. Every entry may carry `vary` (random pitch, +/- a fraction) and `variants`
	   (several assets, one picked per play). Swing has both.
	3. NOTHING HERE MAY ALLOCATE PER CLICK. 2D sounds are cached one instance per name and
	   restarted; only positional sounds are created per call, because they have to be somewhere.
	   `minGap` additionally drops a repeat inside N seconds -- an AoE that kills six creatures in
	   one frame must not stack six death sounds into a clipping wall.
	4. THE FIRST PLAY OF AN UNPRELOADED ASSET IS LATE OR MISSING. Preload() is called once by the
	   client, off the main thread, so the first swing of a session sounds like the fortieth.
--]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SoundLibrary = {}

-- ============================================================================
-- GROUPS
-- ============================================================================
-- Three, not one: a player who mutes the music bed is not asking to stop hearing their own hits,
-- and a player who mutes the interface is not asking to fight in silence.
local GROUPS = { "SFX", "UI", "Ambience" }
SoundLibrary.Groups = GROUPS

local groupCache = {}

local function findGroup(name)
	if groupCache[name] and groupCache[name].Parent then
		return groupCache[name]
	end
	local g = SoundService:FindFirstChild(name)
	if g and g:IsA("SoundGroup") then
		groupCache[name] = g
		return g
	end
	return nil
end

-- Server-side, from ServerMain. Idempotent, so a second call after a soft restart is harmless.
function SoundLibrary.EnsureGroups()
	for _, name in ipairs(GROUPS) do
		if not findGroup(name) then
			local g = Instance.new("SoundGroup")
			g.Name = name
			g.Volume = 1
			g.Parent = SoundService
			groupCache[name] = g
		end
	end
end

-- Client-side. Waits for the server's groups rather than racing them -- two SoundGroups both
-- called "SFX" would leave half the game's audio on a fader nothing ever touches again.
local function resolveGroup(name)
	local g = findGroup(name)
	if g then return g end
	if RunService:IsClient() then
		local waited = SoundService:WaitForChild(name, 5)
		if waited and waited:IsA("SoundGroup") then
			groupCache[name] = waited
			return waited
		end
	end
	-- Last resort. Better a local group than an ungrouped sound the volume setting cannot reach.
	local g2 = Instance.new("SoundGroup")
	g2.Name = name
	g2.Volume = 1
	g2.Parent = SoundService
	groupCache[name] = g2
	return g2
end

-- ============================================================================
-- THE CATALOGUE
-- ============================================================================
-- Fields, all optional except `id` (or `variants`):
--   id        number     asset id. 0 means "not chosen yet" and is REFUSED, see the guard in Play
--   variants  {number}   several ids for one name; one is picked per play
--   len       number     real duration in seconds, measured at verification time. This is what
--                        cleanup uses -- see trap 1
--   vol       number     0..1 base volume before the group fader
--   speed     number     PlaybackSpeed. Below 1 is lower and bigger, above 1 is smaller and quicker
--   vary      number     random PlaybackSpeed spread, +/- this fraction of `speed`
--   group     string     SFX (default) / UI / Ambience
--   minGap    number     seconds; a second play inside this window is dropped
--   dist      number     RollOffMaxDistance for a positional play. The default of 10,000 studs is
--                        meaningless on a 1250-stud platform -- everything would be equally loud
--                        everywhere, including the neighbouring zone
--   loop      boolean    ambience beds only
local S = {
	-- ===== combat (4.2) =====
	-- Four whooshes rather than one: this is the most-repeated sound in the game by an order of
	-- magnitude, so it carries both mitigations from trap 2.
	swing      = { variants = { 9120972444, 9120972321, 9120972323, 9120972724 },
	               len = 0.7, vol = 0.28, speed = 1.15, vary = 0.12, dist = 90, minGap = 0.05 },
	-- "Axe Impact, Giant, Thuddy Hits, Low End" -- a chunky game wants weight, not a metal ping
	hit        = { id = 9113225986, len = 0.9, vol = 0.42, speed = 1.1, vary = 0.10, dist = 120, minGap = 0.04 },
	-- a sledge on an I-beam: unmistakably a bigger event than `hit`, which is the whole job of a crit
	crit       = { id = 9125672726, len = 1.3, vol = 0.55, speed = 1.0, vary = 0.06, dist = 160 },
	death      = { id = 9125869797, len = 1.1, vol = 0.40, speed = 1.2, vary = 0.14, dist = 130, minGap = 0.06 },
	hurt       = { id = 96359585058783, len = 1.9, vol = 0.45, speed = 1.0, vary = 0.08, dist = 60 },
	-- PSE category "Stings": a deep reverberant boom with a rumbling tail. Boss only
	bossDeath  = { id = 9125484526, len = 5.4, vol = 0.75, speed = 1.0, dist = 400 },

	-- ===== economy (4.3) =====
	collect    = { id = 93529351909119, len = 0.5, vol = 0.22, speed = 1.0, vary = 0.10, group = "UI", minGap = 0.05 },
	diamond    = { id = 4612374495, len = 1.5, vol = 0.35, speed = 1.0, group = "UI" },
	purchase   = { id = 134810204798705, len = 2.1, vol = 0.50, speed = 1.0, group = "UI" },
	evolve     = { id = 74787957961284, len = 2.2, vol = 0.60, speed = 1.0, group = "UI" },
	fusion     = { id = 74787957961284, len = 2.2, vol = 0.55, speed = 0.85, group = "UI" },
	levelUp    = { id = 99980076888596, len = 1.7, vol = 0.45, speed = 1.0, group = "UI" },
	-- the hatch base; PlayHatch below is what makes it rarity-scaled
	hatch      = { id = 4612374495, len = 1.5, vol = 0.50, speed = 1.0, group = "UI" },
	-- The Legendary beam (6.2). Same asset as `evolve`, pitched down and played POSITIONALLY at
	-- 600 studs -- the precedent is `open`/`close`, which are the swing whoosh at another speed. A
	-- fanfare slowed down is what a distant, bigger version of the same event sounds like, and it is
	-- one fewer 200 KB download than a sound nobody could describe the difference of. Positional and
	-- SFX-grouped, not UI: this one belongs to a place in the world, and everybody in the server
	-- hears it from wherever that place is.
	beacon     = { id = 74787957961284, len = 2.2, vol = 0.65, speed = 0.82, dist = 600 },

	-- ===== interface (4.4) =====
	click      = { id = 15051647685, len = 0.2, vol = 0.30, speed = 1.0, vary = 0.05, group = "UI", minGap = 0.04 },
	-- the panel swoosh is the swing asset an octave down. A whoosh IS a whoosh, and one more
	-- 200 KB download for a sound the player hears as "the menu moved" is not worth it
	open       = { id = 9120972321, len = 0.6, vol = 0.30, speed = 0.75, group = "UI" },
	close      = { id = 9120972321, len = 0.6, vol = 0.26, speed = 0.95, group = "UI" },
	error      = { id = 97367190838793, len = 0.6, vol = 0.35, speed = 1.0, group = "UI", minGap = 0.25 },

	-- ===== ambience (4.5) =====
	-- Nine beds for twenty zones, mapped by AMBIENCE_BY_ZONE below. Twenty separate beds would be
	-- twenty streaming downloads for a difference nobody can name between Mars and Moon.
	amb_forest   = { id = 1840482193,   len = 96.0,  vol = 0.16, loop = true, group = "Ambience" },
	amb_desert   = { id = 1840267279,   len = 89.4,  vol = 0.14, loop = true, group = "Ambience" },
	amb_ocean    = { id = 9112889917,   len = 59.4,  vol = 0.18, loop = true, group = "Ambience" },
	amb_volcano  = { id = 9112822944,   len = 36.0,  vol = 0.16, loop = true, group = "Ambience" },
	amb_space    = { id = 9125970709,   len = 36.0,  vol = 0.13, loop = true, group = "Ambience" },
	amb_void     = { id = 9112795463,   len = 106.3, vol = 0.15, loop = true, group = "Ambience" },
	amb_energy   = { id = 9125566550,   len = 27.0,  vol = 0.12, loop = true, group = "Ambience" },
	amb_ethereal = { id = 9125899104,   len = 36.0,  vol = 0.14, loop = true, group = "Ambience" },
	amb_arena    = { id = 9112863325,   len = 58.9,  vol = 0.18, loop = true, group = "Ambience" },
}
SoundLibrary.Sounds = S

-- Zone key -> bed. Grouped by what a place SOUNDS like, which is not the same axis as what it
-- looks like: Moon, Mars, Galaxy and Nebula are four very different pictures and one hollow
-- spacecraft hum. Keys match GameConfig.Zones exactly; a zone missing from here plays nothing
-- rather than guessing, and Resolve() says so once.
local AMBIENCE_BY_ZONE = {
	Forest = "amb_forest",          Desert = "amb_desert",
	Ocean = "amb_ocean",            Volcano = "amb_volcano",
	Moon = "amb_space",             Mars = "amb_space",
	Galaxy = "amb_space",           BlackHole = "amb_void",
	Multiverse = "amb_ethereal",    Nebula = "amb_space",
	Wormhole = "amb_energy",        QuantumRealm = "amb_energy",
	TimeRift = "amb_ethereal",      AntimatterZone = "amb_energy",
	DreamDimension = "amb_ethereal", MirrorUniverse = "amb_ethereal",
	VoidExpanse = "amb_void",       CelestialThrone = "amb_ethereal",
	Singularity = "amb_void",       AbsolutePlane = "amb_ethereal",
	Colosseum = "amb_arena",
}
SoundLibrary.AmbienceByZone = AMBIENCE_BY_ZONE

-- ============================================================================
-- LOOKUP
-- ============================================================================

-- Errors on an unknown name, like VFXLibrary.Find. A silent nil here is a sound that never plays
-- and no way to find out why.
function SoundLibrary.Get(name)
	local entry = S[name]
	if not entry then
		error(("SoundLibrary: no sound named '%s'"):format(tostring(name)), 3)
	end
	return entry
end

-- An id of 0 is "chosen but not sourced yet" -- the same shape as the passId = 0 guard in
-- PassService. Warned ONCE per name: `click` firing on every button would otherwise put a warning
-- in the output several times a second and bury everything else in it.
local warned = {}
local function idOf(entry, name)
	local id = entry.id
	if entry.variants and #entry.variants > 0 then
		id = entry.variants[math.random(1, #entry.variants)]
	end
	if not id or id == 0 then
		if not warned[name] then
			warned[name] = true
			warn(("[SoundLibrary] '%s' has no asset id yet -- nothing will play"):format(name))
		end
		return nil
	end
	return id
end

-- Trap 1. The table's measured `len` decides cleanup; TimeLength is used only when it is
-- populated AND longer, which covers an entry whose `len` was mistyped short.
local function lifetimeOf(entry, sound)
	local len = entry.len or 3
	if sound.TimeLength and sound.TimeLength > len then
		len = sound.TimeLength
	end
	-- PlaybackSpeed stretches real time: at 0.75 the asset takes a third longer to finish
	local speed = sound.PlaybackSpeed
	if speed and speed > 0 then
		len = len / speed
	end
	return len + 0.35
end

local function applyEntry(sound, entry, name, opts)
	local id = idOf(entry, name)
	if not id then return false end

	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = (opts.volume or entry.vol or 0.5)

	local speed = opts.speed or entry.speed or 1
	local vary = opts.vary or entry.vary
	if vary and vary > 0 then
		speed = speed * (1 + (math.random() * 2 - 1) * vary)
	end
	sound.PlaybackSpeed = speed

	sound.SoundGroup = resolveGroup(entry.group or "SFX")
	sound.Looped = entry.loop == true
	return true
end

-- ============================================================================
-- RATE LIMIT
-- ============================================================================
local lastPlayed = {}

local function gated(name, entry)
	local gap = entry.minGap
	if not gap then return false end
	local now = os.clock()
	if (now - (lastPlayed[name] or -1)) < gap then
		return true
	end
	lastPlayed[name] = now
	return false
end

-- ============================================================================
-- 2D PLAYBACK
-- ============================================================================
-- One cached Sound per name, restarted on each play (trap 3). Restarting rather than layering is
-- also the right behaviour for interface audio: a player mashing a button wants one click per
-- press, not a chord.
local flatHolder
local flatCache = {}

local function flatParent()
	if flatHolder and flatHolder.Parent then
		return flatHolder
	end
	-- Find-or-create, exactly like findGroup above, and for a reason a live test found: anything that
	-- requires this module as a SECOND instance -- an in-game probe, a plugin, a script that pulls it
	-- outside the normal require cache -- otherwise starts its own folder of the same name, and the
	-- game's audio quietly ends up split across two of them with each half invisible to the other.
	local existing = SoundService:FindFirstChild("SoundLibrary2D")
	if existing and existing:IsA("Folder") then
		flatHolder = existing
		return flatHolder
	end
	flatHolder = Instance.new("Folder")
	flatHolder.Name = "SoundLibrary2D"
	flatHolder.Parent = SoundService
	return flatHolder
end

-- Plays with no position: interface, purchases, anything the player caused themselves.
function SoundLibrary.PlayLocal(name, opts)
	opts = opts or {}
	local entry = SoundLibrary.Get(name)
	if gated(name, entry) then return nil end

	local sound = flatCache[name]
	if not sound or not sound.Parent then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.Parent = flatParent()
		flatCache[name] = sound
	end
	if not applyEntry(sound, entry, name, opts) then
		return nil
	end
	sound.TimePosition = 0
	sound:Play()
	return sound
end

-- ============================================================================
-- 3D PLAYBACK
-- ============================================================================
-- Created per call because it has to exist somewhere in the world. Cleaned up by Debris on the
-- measured length, never on TimeLength alone.
function SoundLibrary.PlayAt(name, target, opts)
	opts = opts or {}
	local entry = SoundLibrary.Get(name)
	if gated(name, entry) then return nil end
	if not target or not target.Parent then
		return SoundLibrary.PlayLocal(name, opts)
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	if not applyEntry(sound, entry, name, opts) then
		sound:Destroy()
		return nil
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = opts.minDistance or 12
	sound.RollOffMaxDistance = opts.dist or entry.dist or 120
	sound.Parent = target
	sound:Play()
	Debris:AddItem(sound, lifetimeOf(entry, sound))
	return sound
end

-- Positional with no part to hang it on -- a creature that has already been destroyed, a hatch
-- above a podium. An Attachment on Terrain rather than an invisible Part: same positional audio,
-- no BasePart entering the physics or streaming systems for half a second.
function SoundLibrary.PlayAtPosition(name, position, opts)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local sound = SoundLibrary.PlayAt(name, att, opts)
	Debris:AddItem(att, sound and lifetimeOf(SoundLibrary.Get(name), sound) or 4)
	return sound
end

-- The one call site most code should use: a part means 3D, no part means 2D.
function SoundLibrary.Play(name, target, opts)
	if typeof(target) == "Vector3" then
		return SoundLibrary.PlayAtPosition(name, target, opts)
	elseif target then
		return SoundLibrary.PlayAt(name, target, opts)
	end
	return SoundLibrary.PlayLocal(name, opts)
end

-- ============================================================================
-- THE HATCH STING
-- ============================================================================
-- One asset, pitched by rarity. Rarer is LOWER and therefore longer and bigger -- the same trick
-- an orchestra uses for the same reason, and the reason it works here is that the player never
-- hears two rarities back to back, so what registers is "that one sounded heavier".
local HATCH_SPEED = {
	-- An ABSENT key falls back to 1.0, which is Rare's pitch -- so a rarity added to GameConfig and
	-- not added here does not go silent, it goes UNREMARKABLE, and the rarest hatch in the game
	-- sounds like the third-commonest. That is why `Secret` (12.12) is a row rather than an
	-- oversight waiting to be noticed: it is the deepest pitch on the ladder because it is the
	-- rarest thing the ladder has.
	Common = 1.30, Uncommon = 1.15, Rare = 1.00, Epic = 0.88, Legendary = 0.76, Mythic = 0.68,
	Secret = 0.62,
}

function SoundLibrary.PlayHatch(rarityKey, target)
	local speed = HATCH_SPEED[rarityKey] or 1.0
	-- volume rises with rarity too, or a legendary is merely a deeper version of a shrug
	local vol = (S.hatch.vol or 0.5) * (speed <= 0.9 and 1.25 or 1.0)
	return SoundLibrary.Play("hatch", target, { speed = speed, volume = vol })
end

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================
-- MainUI's Notify handler is a twenty-branch if/elseif about what each message SAYS. A sound is a
-- property of the EVENT, not of its wording, so it lives here as one row per kind and the handler
-- gains a single line instead of twenty.
--
-- Keeping the table on this side also keeps MainUI's top-level local count where it is. That file
-- sits near Luau's 200-register cap and has silently lost its entire HUD to it twice; a shared
-- module is the one place a lookup table like this costs nothing there.
--
-- A kind ABSENT from this table is deliberately silent. `creature` and `playerHurt` are the two
-- that matter: both are already drawn in the world and already sounded by CombatClient, at the
-- creature and on the player's own head, so a second copy here would double every kill in the game.
local NOTIFY_SOUND = {
	-- a DNA crit is this game's big-hit moment, so it gets the heavy impact rather than a chime.
	-- LIKE `machine` BELOW, NOTHING SENDS THIS KIND ANY MORE (15.14): a crit is drawn and sounded
	-- at the creature by `CombatClient` now, off the kill's own `CombatFx` packet, because it is a
	-- fact about one creature rather than a message about the account. That path calls
	-- `SoundLibrary.Play("crit", position)` -- the POSITIONAL entry, at the corpse -- where this row
	-- would have called `PlayLocal`, flat in the player's ears. The row is left because it costs
	-- nothing and a kind that no longer arrives simply never looks it up.
	crit = "crit",
	upgrade = "purchase",        diamond = "diamond",         evolve = "evolve",
	character = "levelUp",       questComplete = "levelUp",   zone = "levelUp",
	-- `machine` went with the DNA Machine (10.19). This table is keyed by notify `kind`, and nothing
	-- sends that kind any more.
	-- an enchant is the same moment as a fuse -- a pet getting permanently stronger at a cost -- and
	-- it deliberately plays on a kept roll too: the click has to sound like it did something, or a
	-- silent no-upgrade reads as a button that failed
	fuse = "fusion",             rebirth = "evolve",          enchant = "fusion",
	dailyReward = "purchase",    stageMastery = "levelUp",    diamondUpgrade = "purchase",
	potion = "collect",          playtimeGift = "purchase",   bossRevive = "purchase",
	spin = "purchase",           robuxPurchase = "purchase",  reward = "purchase",
	bossDefeated = "bossDeath",  error = "error",
	-- the welcome-back card (5.2). The rising chime rather than the cash register: this is the
	-- first sound of a session and it is announcing that being away paid, not that money changed hands
	offline = "levelUp",
	-- ===== A RELIC CHEST IS AN EGG (17.6) =====
	--
	-- Not `purchase`, which is the cash register and belongs to something bought at a stated price --
	-- a relic chest is a ROLL, and the free one costs nothing at all. Not `levelUp` either: that is
	-- this game's "the account went up a rung" chime and it is already doing four jobs (a zone, a
	-- character, a quest, a return from offline), none of which describe a duplicate Melon Slice.
	-- What a chest actually is -- a container opening onto a random thing with a rarity printed on it
	-- -- is an egg, so it takes the egg's own chime.
	--
	-- THIS ROW IS THE FLOOR, AND IT IS FLAT ON PURPOSE. `PlayNotify` calls `PlayLocal(name)` with no
	-- options, so on its own this plays `hatch` at speed 1.0 -- which by HATCH_SPEED's own note is
	-- what a Rare sounds like, i.e. "unremarkable" rather than silent. That is the correct behaviour
	-- for a payload this table cannot see inside, and it is what a relic notification will sound like
	-- if MainUI's branch is ever removed or bails early.
	--
	-- THE RARITY IS ADDED BY THE CALLER, AND IT COSTS NO SECOND SOUND. MainUI's relic branch follows
	-- this with `SoundLibrary.PlayHatch(payload.rarity)`, and that is not a second sting layered on
	-- the first: 2D playback caches ONE Sound instance per name and restarts it (trap 3 in the
	-- header), so the second call lands on the SAME object in the SAME frame, rewrites PlaybackSpeed
	-- and Volume, and replays it from 0. A Mythic therefore arrives at 0.68 -- deep, long and heavy
	-- -- and a duplicate Common at 1.30, off one asset and one row. `hatch` carries no `minGap`, so
	-- nothing drops the refined play in favour of the flat one.
	--
	-- The five relic rarity names in `GameConfig.RelicRarities` are the egg ladder's names, so
	-- HATCH_SPEED already has a row for every one of them and nothing had to be added there.
	--
	-- WHY THE PITCH IS NOT EXPRESSED HERE. Every value in this table is a plain sound name and
	-- `PlayNotify`'s whole contract is `NOTIFY_SOUND[kind] -> PlayLocal(name)`. Making one row a
	-- table or a function so it could carry a pitch would make twenty other rows' contract
	-- conditional for one kind's benefit, and the branch that already holds the rarity is one line
	-- away from the sound it wants.
	relic = "hatch",
}

function SoundLibrary.PlayNotify(payload)
	if type(payload) ~= "table" then return nil end
	-- `pet` is handled by HatchReveal instead (Phase 6.1), which is the only thing that knows WHEN
	-- the hatch happens: the notification arrives the instant the server pays out, but the sting
	-- belongs on the crack about a second later. Firing it from here as well put the sound before
	-- the egg had moved.
	local name = NOTIFY_SOUND[payload.kind]
	if name then
		return SoundLibrary.PlayLocal(name)
	end
	return nil
end

-- ============================================================================
-- AMBIENCE (4.5)
-- ============================================================================
-- One bed at a time, crossfaded. A hard cut on a zone transition is more noticeable than the bed
-- itself ever is -- ambience only works while nobody is listening to it.
local FADE = 1.2
local currentBed, currentBedName

-- THE FADE IS A TASK, NOT A TWEEN, AND THAT IS THE BUG THIS FILE WAS CAUGHT BY.
--
-- The first live test found the bed correctly created, correctly grouped, IsLoaded, IsPlaying and
-- looping -- at Volume 0.000, and still 0.000 eight seconds later. `TweenService:Create(...):Play()`
-- had run and nothing had moved. A direct write to the same property stuck immediately, so the
-- property was fine and the tween simply never arrived.
--
-- The lesson is not "tweens are unreliable", it is that the END STATE of this fade is the whole
-- point: a bed that never reaches its target is a silent soundtrack that still costs a stream, and
-- nothing anywhere would report it. A tween is fire-and-forget -- nobody holds the object and
-- nobody checks that it finished. This loop holds its own reference for as long as it runs and
-- ALWAYS writes the final value, so the worst case is an ugly fade rather than a silent game.
--
-- No cancellation token is needed: every fade targets its own Sound, a new bed is always a new
-- instance, and the `Parent` check stops a fade writing to something already destroyed.
local function fadeTo(sound, target, seconds, destroyAfter)
	task.spawn(function()
		local from = sound.Volume
		local t0 = os.clock()
		while sound.Parent do
			local alpha = (os.clock() - t0) / seconds
			if alpha >= 1 then break end
			sound.Volume = from + (target - from) * alpha
			task.wait()
		end
		if not sound.Parent then return end
		sound.Volume = target
		if destroyAfter then
			sound:Destroy()
		end
	end)
end

function SoundLibrary.SetAmbience(zoneKey)
	local name = AMBIENCE_BY_ZONE[zoneKey]
	if not name then
		if not warned["zone:" .. tostring(zoneKey)] then
			warned["zone:" .. tostring(zoneKey)] = true
			warn(("[SoundLibrary] no ambience mapped for zone '%s'"):format(tostring(zoneKey)))
		end
		return
	end
	if name == currentBedName and currentBed and currentBed.Parent and currentBed.IsPlaying then
		return
	end

	local entry = SoundLibrary.Get(name)

	local old = currentBed
	if old and old.Parent then
		fadeTo(old, 0, FADE, true)
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	if not applyEntry(sound, entry, name, {}) then
		sound:Destroy()
		currentBed, currentBedName = nil, nil
		return
	end
	local target = sound.Volume
	sound.Volume = 0
	sound.Parent = flatParent()
	sound:Play()
	fadeTo(sound, target, FADE)

	currentBed, currentBedName = sound, name
	return sound
end

function SoundLibrary.StopAmbience()
	if currentBed and currentBed.Parent then
		fadeTo(currentBed, 0, FADE, true)
	end
	currentBed, currentBedName = nil, nil
end

-- ============================================================================
-- VOLUME (4.6)
-- ============================================================================
-- The whole reason for the SoundGroups. `Master` is applied on top of each group, so muting
-- everything and muting the music are separate switches that compose.
local volumes = { Master = 1, SFX = 1, UI = 1, Ambience = 1 }

local function applyVolumes()
	local master = math.clamp(volumes.Master or 1, 0, 1)
	for _, name in ipairs(GROUPS) do
		local g = resolveGroup(name)
		g.Volume = master * math.clamp(volumes[name] or 1, 0, 1)
	end
end

function SoundLibrary.SetVolumes(tbl)
	if type(tbl) ~= "table" then return end
	for key, value in pairs(tbl) do
		if volumes[key] ~= nil and type(value) == "number" then
			volumes[key] = math.clamp(value, 0, 1)
		end
	end
	applyVolumes()
end

function SoundLibrary.GetVolumes()
	return { Master = volumes.Master, SFX = volumes.SFX, UI = volumes.UI, Ambience = volumes.Ambience }
end

-- ============================================================================
-- PRELOAD (trap 4)
-- ============================================================================
-- Client-side, off the main thread. Every distinct id once, so the shared assets (the swing that
-- is also the panel swoosh, the bling that is also the hatch) are fetched a single time.
function SoundLibrary.Preload()
	task.spawn(function()
		local seen, probes = {}, {}
		local holder = Instance.new("Folder")
		holder.Name = "SoundPreload"
		holder.Parent = SoundService

		for name, entry in pairs(S) do
			local ids = entry.variants or { entry.id }
			for _, id in ipairs(ids) do
				if id and id ~= 0 and not seen[id] then
					seen[id] = true
					local probe = Instance.new("Sound")
					probe.Name = name
					probe.SoundId = "rbxassetid://" .. id
					probe.Parent = holder
					table.insert(probes, probe)
				end
			end
		end

		pcall(function()
			ContentProvider:PreloadAsync(probes)
		end)
		holder:Destroy()
	end)
end

-- Client entry point: resolve the groups, push the saved volumes, warm the cache.
function SoundLibrary.Init(savedVolumes)
	for _, name in ipairs(GROUPS) do
		resolveGroup(name)
	end
	if savedVolumes then
		SoundLibrary.SetVolumes(savedVolumes)
	else
		applyVolumes()
	end
	SoundLibrary.Preload()
end

return SoundLibrary
