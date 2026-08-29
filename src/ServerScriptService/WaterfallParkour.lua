-- WaterfallParkour -- the way UP the Forest falls, so the Hidden Egg on the summit shelf is
-- something a player can reach instead of something they can only look at.
--
-- ===== WHY IT EXISTS (34.45, 2026-08-28) =====
--
-- The owner, over a screenshot taken from the plunge pool looking straight up at the falls:
--
--   "ovde ce nam trebati neki tezi malo parkur da se moze nekako doci do jajeta na vodopadu"
--   -- "here we're going to need a somewhat HARDER parkour, so that one can somehow get up to
--   the egg on the waterfall."
--
-- `GameConfig.Secrets` has carried `ForestSummitEgg` at offset (258, 219.5, -354) since 33.19 and
-- `SecretsService` has been dutifully wiring its trigger 219 studs above the only ground a player
-- can stand on. The secret passed that service's own reachability test the whole time, because
-- that test asks whether a body FITS at the trigger, not whether a body can GET there. Nothing was
-- broken; there was simply no route. This file is the route.
--
-- "tezi MALO" -- a bit hard. Not a staircase, not a gauntlet.
--
-- ===== THE NUMBERS THIS COURSE IS CUT TO, AND WHY THEY ARE NOT ROBLOX'S =====
--
-- StarterPlayer still carries the stock 16 / 7.2 and NONE OF IT EVER REACHES A PLAYER:
-- `EvolutionVisuals` flips `UseJumpPower` on and overwrites both every time a body changes, from
-- `GameConfig.BaseWalkSpeed = 34` and `GameConfig.BaseJumpPower = 44`. Measured in Edit on
-- 2026-08-28: workspace.Gravity is 196.2, so the WEAKEST body in the game -- stage one, no Mastery,
-- no Speed upgrade, sizeMult 1, i.e. exactly the player who is standing in the Forest -- gets
--
--     apex  = 44^2 / (2 * 196.2)  =  4.93 studs
--     air   = 2 * 44 / 196.2      =  0.449 s
--     reach = 0.449 * 34          = 15.25 studs on the level
--
-- and a max-stage body, pinned to `MaxJumpPower` 52 / `MaxWalkSpeed` 150, gets 6.89 studs of apex
-- and about 69 studs of reach.
--
-- SO THE VERTICAL IS THE ENTIRE DIFFICULTY AND THE HORIZONTAL IS VERY NEARLY FREE. That is the
-- inverse of a stock Roblox obby and it is the single fact that shapes this whole file. 4.93 is an
-- APEX, not a step: a 4-stud riser is already a coin flip for a stage-one player, and 202 studs of
-- climb at 4 studs a hop would be fifty-odd coin flips. The height is therefore carried by SLOPE --
-- `Humanoid.MaxSlopeAngle` is 89, so anything short of vertical is walkable, which is the same
-- thing `ZoneTerrain` says at its own ramps -- and the DIFFICULTY is carried by the gaps cut into
-- that slope. A player is never asked to out-jump their own body; they are asked not to miss.
--
-- The gaps are sized as a PERCENTAGE OF THE WEAKEST BODY'S REACH, which is the unit `AdventureMap`
-- already uses for the only other parkour in the game (`GAP_EASY` 26 = 43%, `GAP_MED` 34 = 57%,
-- `GAP_HARD` 42 = 70% and "the largest gap in the game"). The largest gap here is leg 13's: 9.0
-- studs across a 2.5-stud lift, and reach at a 2.5-stud lift is 12.98, so 69%. Deliberately the
-- same number as the hardest jump on the Adventure courses -- with the difference that those
-- courses FORCE 80/74 onto the humanoid for the duration of a run (`AdventureService` line 87),
-- and this one is measured against a player who has bought nothing at all.
--
-- REJECTED: forcing 80/74 here too, the way a run does. An Adventure course is entered through a
-- gate and exited through a finish line, so the service owns the humanoid for a bounded window.
-- The falls are open world -- there is no moment that is "the start of the climb" and no moment
-- that is the end of it, so there is nowhere to put the restore, and a player who logs out
-- mid-climb would keep the boost forever.
--
-- ===== THE SHAPE: A SWITCHBACK ON THE WEST SHOULDER =====
--
-- Fifteen legs zig-zagging across a 36-stud corridor of the west buttress (x 226..262), each leg
-- broken into two or three sloped ledges with a LEVEL gap between them, and a wide flat rest at
-- every turn. Twenty-three of the twenty-six jumps are in that pattern.
--
-- The gaps are level (or lifted by at most 2.5 studs near the top) ON PURPOSE. The obvious thing --
-- cut a gap into a continuous ramp -- makes the jump inherit the ramp's slope, and a 7-stud gap on
-- a 35-degree ledge is a 4.9-stud riser, which is precisely the apex a stage-one player cannot
-- clear. So the slope lives in the ledges and the gaps are flat. It also reads better: a broken
-- shelf steps OUT and then carries on climbing, which is what a real strata band does.
--
-- Difficulty ramps upward, per the brief: legs 1-5 are two ledges and one 7.0-7.5 stud gap each
-- (46-49% of reach, comfortable); legs 6-13 are three ledges and two gaps that grow 6.5 -> 9.0;
-- the last three legs add a LIFT across the gap as well, which is the only place the vertical is
-- ever asked for anything. Every turn is a 13 x 11 flat rest, so a rest lands every second or
-- third piece -- inside the "every third to fourth" the brief asked for, on the safe side.
--
-- NO CHECKPOINTS, and that is a decision rather than an omission. The only checkpoint system in
-- the repo is `AdventureService`'s, and it is not general: `run.checkpoint` only exists inside a
-- `runs[player]` record created by `AdventureService.Begin`, the pads are found by walking a course
-- Model for `CheckpointIndex`, and the respawn is driven by that service's own Heartbeat against
-- `GetVoidY()`. Reusing it would mean putting a free-roaming player into a fake Adventure run,
-- which owns their humanoid and their HUD. A fall here drops into the plunge pool at the bottom of
-- the falls, which is the reset.
--
-- ===== WHERE IT COMES OUT, AND WHY NOT ON TOP OF THE EGG =====
--
-- The last rest lands on the y-218 tread at about (230, 218.5, -326). The egg's shelf is at
-- (258, 219.5, -354) -- twenty-eight studs south-east along the same tread, behind the `Bush1` that
-- was put four studs west of it to hide it from the bridge. So cresting the climb does NOT hand a
-- player the egg; it hands them the top of the falls and they still have to look. The screening
-- is untouched: nothing this file builds goes south of z -332 or east of x 262 above y 205.
--
-- ===== ITS OWN VERSION STAMP, AND WHY IT IS NOT UNDER Workspace.Zones =====
--
-- Same reason `WorldApron`, `EventArena`, `ExpeditionMap` and `HubPlaza` carry theirs:
-- `ZoneBuilder.BUILD_VERSION` drops all twenty-one zones and rebuilds ~105,000 parts, and
-- `Workspace.Zones` goes wholesale with it. A route parented in there would vanish silently on the
-- next unrelated zone change and the egg would quietly go back to being unreachable. This is a
-- top-level Workspace model with `ParkourVersion` on it, destroyed and rebuilt only when THIS
-- file's number moves.
--
-- Every part is named `Parkour...` and the model carries `Parkour = true`, because a second agent
-- is currently grounding floating scenery across the map and has been told to leave `*Parkour*`
-- alone. Ledges over a gorge are floating scenery by every test that pass can apply.
--
-- UNLIKE `WorldApron`, EVERY PART HERE IS `CanCollide = true` AND QUERY-ABLE. That file's parts are
-- all collision-off and query-off because nothing may stand on them and no ray may find them.
-- These are walked on, and `Audit()` below raycasts them itself.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterfallParkour = {}

local ROUTE_VERSION = 3
local MODEL_NAME = "WaterfallParkour"

-- ===== GEOMETRY CONSTANTS =====

local THICK = 2.5   -- a ledge slab's thickness. Thin enough to read as a shelf, thick enough that
                    -- the underside is never a paper edge seen from the pool.
local DEPTH = 8     -- a ledge's depth in Z. The body box is 4; the rest is standing room, because
                    -- the north end of every ledge is buried in the cliff (see STANDOFF).
local REST_X, REST_Z = 13, 11   -- the flat pad at every switchback turn

-- ===== THE LANE: WHY THE LEGS ALTERNATE IN Z (34.46, 2026-08-29) =====
--
-- v1 stacked every leg into ONE vertical plane and that made the climb impossible to finish. The
-- owner's report: "parkur u robloxu uopste nije moguc, ne moze se popeti do gore kroz stepenice
-- one". Measured on the built v1 model: SIXTEEN OF THE SEVENTEEN LEGS HAD UNDER ONE STUD OF
-- HEADROOM over their last ledge. Two causes, both of them the switchback eating itself:
--
--   * a turn reverses direction, so leg n+1's first ramp climbs back out OVER leg n's last ramp in
--     the same plane. The two diverge at 2*tan(theta) and a slab is 2.5 thick, so they interpenetrate
--     for the first ~3 studs and stand under 5 apart for the first ~9. Measured: `ParkourLedge3_1`
--     sat 0.68 studs over the head of `ParkourLedge2_2` -- a wedge, and the player stops in it.
--   * a 13-wide rest pad centred ON the turn overhangs the incoming ramp by 6.5 studs and the ramp
--     climbs UNDER it. On the four tree-band legs the ramp run is only 4 studs, so the pad covered
--     the entire ledge: `ParkourRest11` stood 1.00 stud over the spot a player LANDS on after a
--     6-stud jump. There was nowhere to put a head, let alone a body.
--
-- `Audit()` never saw any of it, because its box test excludes the route's own parts -- they
-- overlap deliberately at every walk join and counting them would fire on every turn. The exclusion
-- was right; the missing check was headroom, and Audit() now runs one (see HEADROOM below).
--
-- The fix is what a real mountain switchback does: the legs do not share a plane. Odd legs hug the
-- rock (centre = face + STANDOFF), even legs sit LANE studs further out over the gorge, so leg n
-- and leg n+1 are SIDE BY SIDE in Z and never above one another, while leg n and n+2 share a lane
-- 27 studs apart. The turn pad goes in the lane the NEXT leg will use, abutting the incoming ramp
-- edge-to-edge instead of hanging over it. Nothing about the jumps changes -- every gap is inside a
-- single leg -- so the whole difficulty curve v1 was tuned to survives untouched.
--
-- The price: an even leg's ledges hang 8 studs off their own rock and an outer rest pad reaches 19,
-- against the "more than six studs off its own rock has stopped being part of the cliff" rule this
-- file set itself. Paid on purpose: a shelf that reads a little bold beats a route nobody can walk.
-- DEPTH came 10 -> 8 in the same move, so the outer lane starts exactly where the inner one ends.
local LANE = 8

-- ===== HOW FAR A TURN PAD SLIDES UNDER THE RAMP THAT ARRIVES AT IT (34.47, 2026-08-29) =====
--
-- v2 built every pad to ABUT its incoming ramp: pad south edge exactly on ledge north edge, tops
-- coplanar, zero shared volume. That is correct on paper and it does not survive a real character.
-- Playtested 2026-08-29 by driving a humanoid forced to the weakest body's 34/44 up the whole chain
-- twice: 115 of 120 transitions passed and ALL FIVE failures were a walk onto a pad -- `Rest4`
-- twice, `Rest10` once, and `Rest15` BOTH times at the identical spot, i.e. not even intermittent.
-- The character walks to the ramp's edge and stops there, or catches the wedge tip and drops.
--
-- A ramp meeting a flat pad at a right angle presents a knife edge, and a humanoid capsule can
-- refuse it. The two need shared footprint -- and it matters WHICH of them provides it. Sliding the
-- PAD back over the ramp was tried first and is wrong: a pad is centred on the turn and already
-- reaches half its width back along the leg, so widening it in Z puts it over that leg's LANDING
-- spot, four studs up. The arc check called it immediately, on twelve of twenty-six jumps.
--
-- So the RAMP grows instead. The last slab of each leg is SEAM studs deeper and shifted that far
-- toward its pad, which lays continuous floor across the join while leaving the pad exactly where
-- it was -- above nothing. The overlap is at ramp level, and a ramp is the thing being walked off.
--
-- It is skipped on a leg that climbs less than SEAM_MIN_RISE, for the same reason `restX` narrows
-- there: the extension reaches into the NEIGHBOURING lane, which belongs to the leg one below, and
-- a jumping player needs ~12.6 studs of it (apex 4.93 + a 6.2-stud body + the lift). The four
-- tree-band legs rise 8.5 and have neither the room nor the need -- their pads are six studs wide
-- against a four-stud run, so the pad already sits over three quarters of the ramp in X, and none
-- of the four failed a playtest run.
local SEAM = 2.5
local SEAM_MIN_RISE = 12

-- A ledge's CENTRE sits this far south of the rock face it grows out of, so the ledge spans
-- faceZ - 1 .. faceZ + 9: one stud of it inside the cliff (it reads as growing from the rock
-- rather than glued to it) and a body box centred on the ledge clears the face by two studs.
local STANDOFF = 4.0

-- How far one piece may chase the face in Z relative to the piece before it. The falls' west
-- buttress is a staircase in Z as well as Y -- measured 2026-08-28, the face runs z -258 at y 34
-- and z -328 at y 218 -- but it does it in JUMPS (there is a 27-stud recess between y 200 and
-- y 206). Following those literally would put a 27-stud hole in the middle of the route, so the
-- route lags and the ledge hangs out over the gorge for a piece or two instead. 72 studs of total
-- northing over ~55 pieces needs 1.3 a piece; 3.5 is the ceiling, not the plan.
local MAX_NORTH = 3.5
-- ...and south, because the lower face OVERHANGS: it comes six studs back toward the pool between
-- y 34 and y 88. Without this the route would be one stud inside the rock at y 80.
local MAX_SOUTH = 2.0

local PROBE_Z = -236      -- south of every part of the falls' west shoulder
local PROBE_LEN = 140

local X_WEST, X_EAST = 226, 262

-- The body box `SecretsService.reportBlocked` uses, and for the same reason: asking whether a
-- HUMANOID fits at a landing spot is the only test that separates "standing honestly on a ledge"
-- from "buried in the cliff". Audit() replays it piece by piece.
local BODY_BOX = Vector3.new(4, 6, 4)

-- ===== THE ROUTE =====
--
-- `rise`  studs of height the leg gains, end to end
-- `dir`   "E" runs +X, "W" runs -X; they alternate, that is what makes it a switchback
-- `slabs` how many pieces the leg is broken into -- `slabs - 1` jumps
-- `gap`   the level span between two pieces, in studs (see the percentages below)
-- `lift`  how much HIGHER the far side of each gap sits. Zero everywhere but the top three legs.
-- `restX` a narrower turn pad than REST_X, where a full-width one would overhang the leg below
-- `out`   extra studs SOUTH of the leg's own lane, to duck something the lane alone does not clear
--
-- The % column is that gap against the weakest body's reach AT THAT LIFT, computed by Audit().
local LEGS = {
	{ rise = 13.5, dir = "E", slabs = 2, gap = 7.0, lift = 0.0 },
	{ rise = 13.5, dir = "W", slabs = 2, gap = 7.0, lift = 0.0 },
	{ rise = 14.0, dir = "E", slabs = 2, gap = 7.5, lift = 0.0 },
	{ rise = 14.0, dir = "W", slabs = 2, gap = 7.5, lift = 0.0 },
	{ rise = 13.0, dir = "E", slabs = 2, gap = 8.0, lift = 0.0 },
	-- Three pieces a leg from here up: the rest comes every third piece instead of every second,
	-- and the ledges get shorter, so there is less run-up in front of a wider gap.
	{ rise = 13.5, dir = "W", slabs = 3, gap = 6.5, lift = 0.0 },
	{ rise = 13.5, dir = "E", slabs = 3, gap = 7.0, lift = 0.0 },
	{ rise = 14.0, dir = "W", slabs = 3, gap = 7.0, lift = 0.0 },
	{ rise = 14.0, dir = "E", slabs = 3, gap = 7.5, lift = 0.0 },
	{ rise = 14.0, dir = "W", slabs = 3, gap = 7.5, lift = 0.0 },
	-- ===== THE TREE BAND: LEGS 11-14 RUN IN A 14-STUD CORRIDOR, NOT A 36-STUD ONE =====
	--
	-- Two tree meshes grow straight out of the buttress and they are COLLIDABLE:
	--   `Trees.Model.Meshes/treept1` at (255, 161, -281), bounds 16 x 18 x 13 -> x 247..263, y 152..170
	--   `Trees.Model.Meshes/treept2` at (254, 169, -282), bounds 24 x 15 x 21 -> x 242..266, y 161..177
	-- Together they fill x 242..266 for the whole of y 152..177, which is the east half of the
	-- corridor for exactly the height two full-width legs would have crossed it at. The first build
	-- put four landings inside them.
	--
	-- REJECTED, in order: pushing the ledges south past the crowns (the rock face there is z -293, so
	-- clearing treept2's -271 edge leaves a ledge twenty-two studs off its own cliff -- floating
	-- bricks over the gorge, which is the one thing the brief said not to build); and deleting the
	-- two trees (they belong to `MapWaterfall`, which would put them back on its next build, and they
	-- are half the silhouette in the screenshot this feature came from).
	--
	-- So the switchback narrows instead, to x 224..238 -- four studs clear of treept2's west bound --
	-- and takes four short legs to cross the band instead of two long ones. The ledges there are 4
	-- studs of run at 41 degrees with a 6-stud gap: the thinnest, steepest, busiest stretch of the
	-- climb, a hundred and sixty studs up. It earned its difficulty from the terrain rather than from
	-- a number, which is the better way to get it.
	--
	-- The wall behind them is real: the summit block's south face (top y 201.6, z -293) runs from
	-- y 154 to y 201 at these x, so every one of these ledges is seated against rock.
	--
	-- `restX = 6` AND NOT 13, WHICH IS THE ONE PLACE THE LANES ARE NOT ENOUGH ON THEIR OWN. A turn
	-- pad is centred on the turn and so reaches half its width BACK over the corridor, and the pad
	-- belongs to the lane of the leg it hands off to -- which is the lane of the leg TWO below. That
	-- is 8.5 studs down here instead of the 13.5 everywhere else, and a jumping player needs about
	-- 12.6 (apex 4.93 plus a 6-stud body plus the lift): so on these four legs, and only these, a
	-- 13-wide pad is a ceiling over the gap below it. Measured on v2: the arcs onto `ParkourLedge11_2`
	-- and `ParkourLedge13_2` both struck the pad overhead at 60% of flight, right at the apex.
	--
	-- Widening the corridor was the obvious alternative and there is nothing to widen it into: probed
	-- 2026-08-29, the buttress simply ENDS at x 224 -- a ray north at x 208..220 finds no rock at any
	-- height in this band. So the pads narrow to 6, which clears the gap below by 1.5 studs of body
	-- box. Six studs across and eight deep is a small landing, and that is honest for what the file
	-- already calls the thinnest, steepest, busiest stretch of the climb.
	{ rise = 8.5, dir = "E", slabs = 2, gap = 6.0, lift = 1.5, west = 224, east = 238, restX = 6 },
	{ rise = 8.5, dir = "W", slabs = 2, gap = 6.0, lift = 1.5, west = 224, east = 238, restX = 6 },
	{ rise = 8.5, dir = "E", slabs = 2, gap = 6.0, lift = 1.5, west = 224, east = 238, restX = 6 },
	{ rise = 8.5, dir = "W", slabs = 2, gap = 6.0, lift = 1.5, west = 224, east = 238, restX = 6 },
	-- Clear of the trees at y 177, and the corridor opens back up. The lift is the only place this
	-- course spends the vertical it has, and it spends it here because the brief asked for the
	-- difficulty to ramp and because a fall from 180 studs up costs a player the same trip back
	-- either way.
	--
	--
	-- ===== LEG 15 STOPS AT x 246 BECAUSE A BOULDER OWNS THE REST OF THE SHELF =====
	--
	-- `Zones.HuntForest.HuntRockCollider` sits on the plateau lip at x 247.4..257.6 / y 199.5..206 /
	-- z -298..-286.9, and leg 15's inner lane runs straight under it: the arc check caught the head
	-- clipping it, and so does a player merely WALKING the top of a ledge that reaches x 257.
	--
	-- Nothing vertical fixes it. The boulder's underside is 199.5 and a jump costs apex 4.93 plus a
	-- 6.2-stud body whatever the gap needs, so the last takeoff would have to sit at y 188 -- which
	-- for a leg starting at 182.5 means a rise of under seven studs. Nor does going further EAST:
	-- probed at y 186..198, the face falls back from z -291 at x 254 to z -320 at x 262, so X_EAST is
	-- the buttress's real edge already and a ledge past it hangs over nothing.
	--
	-- So the leg stops short, at x 246, and leg 16 turns back from there. `Rest15` still reaches under
	-- the boulder in X and is fine, because a turn pad after an odd leg is in the OUTER lane at
	-- z ~ -283 and the boulder ends at -286.9 -- it passes SOUTH of it. That is the lane system
	-- paying for itself: the pad and the ledge want different things here and they are no longer the
	-- same piece of geometry.
	--
	-- `west = 224` and not X_WEST: leg 15 starts at leg 14's turn, and that pad is one of the narrow
	-- six-stud ones, so a first ledge starting two studs east of it shares only a single stud with it.
	{ rise = 13.5, dir = "E", slabs = 2, gap = 8.5, lift = 2.0, west = 224, east = 246 },
	-- Leg 16 finishes on the SUMMIT PLATEAU -- measured 2026-08-28, real rock, top y 201.6..203.8
	-- over x 227..257 / z -294..-318 -- so its rest is a step onto the mountain rather than one
	-- more ledge over the gorge, and the player gets a genuine breather before the last riser. It is
	-- also the hardest jump on the course (8.5 studs across a 2.5-stud lift, ~70% of the weakest
	-- body's reach at that height, the same figure `AdventureMap` calls its largest gap), and that is
	-- deliberate: the last hard thing is the one in front of the prize.
	--
	-- 8.5 and not 7.0, which is a one-stud detail with a real cause: `Waterfall.Grass.Part` lays a
	-- 1.1-stud grass cap over the plateau at (242.2, 203.5, -318.2), top y 204.03, and a leg 17 that
	-- started at 203.0 put its first ledge's foot half a stud UNDER that turf. Audit() reported it
	-- as one blocked landing and the clearance push could not fix it, because the fix is vertical
	-- and the push is horizontal. Leg 16 now tops out at 204.5 and leg 17 stands on the grass
	-- instead of in it.
	{ rise = 8.5, dir = "W", slabs = 2, gap = 8.5, lift = 2.5, east = 246 },
	-- ...and then walks NORTH across that plateau, which is why leg 15 pins its own Z instead of
	-- following the face. The rock does something the tracker cannot: between y 204 and y 215 it
	-- steps back 27 studs in one go (face z -291 at y 200, z -318 at y 206). Chasing that at
	-- MAX_NORTH would need eight pieces and there are three. So the plateau IS the transition --
	-- twenty-five studs of real ground a player walks for free -- and the last leg is built where
	-- the final 12-stud riser actually is, at z -313.5, four studs south of it.
	--
	-- x 254 and no further east: the Bridge model spans x 256..337.5 / y 212.8..231.9 /
	-- z -345.9..-324.6, and the two decorative summit rocks (`Waterfall.Model`, mesh `w`) stand at
	-- x 255..260 / y 216..226.5.
	{ rise = 11.0, dir = "E", slabs = 2, gap = 7.0, lift = 2.0, west = 230, east = 254, z = -313.5 },
}

-- The approach: four free-standing stones over the flat ground on the pool's west shore, walking a
-- player from the water's edge to the foot of the buttress. This is the "there IS a route" signal
-- the brief asked for -- the first pad is 16 x 12 and wears a three-stone cairn, which is the one
-- piece of vocabulary that reads as "this way up" without a sign.
--
-- It stays at z -240..-252 and x 222..288 for one reason: the grotto. `MapWaterfall` puts a Secret
-- training room behind the curtain at (291, 6, -290), entered by walking a corridor from the mouth
-- at z -270 to the plinth face at z -288, with its trigger at (291, 6, -281). The nearest thing
-- this file builds is eighteen studs south of that mouth and eleven studs west of the corridor.
--
-- x, top-surface y, z, size x, size z
-- The rises here are 3.0 and they are 3.0 BECAUSE OF THE APEX. The first build used 4.0, 4.5 and
-- 5.0 studs, which looked like a gentle intro and was in fact the hardest thing on the course: 5.0
-- is above a stage-one player's 4.93 apex, i.e. the fourth stone was literally impossible for the
-- weakest body and the third was at 91% of one. Audit() now prints reach = -1 for anything over the
-- apex, which is how that was caught.
--
-- THE STONES SIT IN THE OUTER LANE (see THE LANE) AND LEG 1 CLIMBS IN THE INNER ONE. The approach
-- walks WEST and leg 1 then turns around and climbs EAST, so in one shared plane the ramp runs back
-- over the stones it just came off -- at its foot, where it is lowest. Measured on v1: 2.36 studs
-- of headroom over the last stone, i.e. the player's first move on the climb was into a wedge. Held
-- 8 studs apart in Z they overlap by 2 studs at the boundary, which is a step rather than a
-- ceiling. The stones stay on the flat shore either way; nothing here is over water.
--
-- FIVE STONES AND NOT FOUR, and the last one is a deep pad rather than a stepping stone. Holding
-- the approach in the outer lane fixes the ceiling but opens a floor: leg 1's ramp is in the INNER
-- lane, so the two only met across a 1.5-stud sliver, and the audit's walk check found the shore
-- eleven studs below between them. So the last stone reaches ACROSS both lanes (20 deep, z -251 to
-- -231) and stops at x 230 -- four studs past the ramp's foot at 226 and nowhere near its head, so
-- the only thing over it is the first four studs of ramp, which is 1.9 studs of rise: a step up, not
-- a ceiling. A player walks off the pad onto the ramp without a jump at all.
--
-- Stopping at x 230 costs the old 18-stud reach back to stone 3, hence the fifth stone. The rises
-- came down to 2.0-2.5 with it and the gaps to 2-4 studs, which is the right shape for an opener:
-- v1's own note records that its approach was accidentally the HARDEST thing on the course.
local APPROACH_LANE = LANE
local APPROACH = {
	{ 280, 2.5, -240, 16, 12 },   -- START, on the shore beside the plunge pool
	{ 264, 5.0, -242, 10, 10 },
	{ 250, 7.5, -244, 10, 10 },
	{ 238, 9.5, -246, 10, 10 },
	{ 224, 11.5, -249, 12, 20 },  -- the foot of the climb: spans both lanes, leg 1 starts at x 226
}

-- ===== BUILD HELPERS =====

-- The rock the route is made of is READ, never typed. Every ledge takes the Color, Material and
-- CastShadow of the actual cliff part its seating ray found, so a ledge on the pale green-grey
-- buttress (0.471, 0.565, 0.510 Slate) and a ledge against the dark channel rock
-- (0.388, 0.373, 0.384 Slate) each match their own neighbour without this file knowing either
-- colour. `WorldApron` reads the zone floor's colour and material for the same reason.
local function newRayParams(model)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true
	return params
end

-- Casts north into the cliff and returns the first hit that is actually ROCK.
--
-- It has to skip: the ~100 `Bush1` MeshParts and the tree meshes scattered down the shoulder (a
-- ledge seated four studs south of a bush hangs in mid-air), and the water. The falls' rock is all
-- plain `Part`, so "not a MeshPart" is the whole filter, and it walks up to six hits before giving
-- up rather than taking the first thing it touches.
local function rockFaceAt(params, x, y)
	local from = Vector3.new(x, y, PROBE_Z)
	local remaining = PROBE_LEN
	for _ = 1, 6 do
		if remaining <= 0 then break end
		local hit = workspace:Raycast(from, Vector3.new(0, 0, -remaining), params)
		if not hit then return nil end
		if not hit.Instance:IsA("MeshPart") then
			return hit.Position.Z, hit.Instance
		end
		local advanced = (from.Z - hit.Position.Z) + 0.5
		remaining -= advanced
		from = Vector3.new(x, y, hit.Position.Z - 0.5)
	end
	return nil
end

-- Is there room for a body, standing on this spot? The same box and the same "count anything
-- collidable" rule as `SecretsService.reportBlocked`. The route's own pieces are excluded because
-- they overlap each other ON PURPOSE at every walk join -- a leg's first ledge grows out of the
-- previous leg's rest so the two read as one shelf, and counting that as a blockage would make the
-- test fire on every single turn.
local function bodyBlocked(model, spot)
	for _, other in ipairs(workspace:GetPartBoundsInBox(CFrame.new(spot + Vector3.new(0, 3.2, 0)),
		BODY_BOX)) do
		if other.CanCollide and not other:IsDescendantOf(model) then return other end
	end
	return nil
end

-- The seating raycast answers "where is the rock face", which is NOT the same question as "can a
-- player stand here", and the difference is what the first build got wrong: eighteen of fifty-seven
-- landings came back blocked on 2026-08-28 -- by `Waterfall.Part` where the plateau bulges south
-- over the ledge under it, by `Trees.Meshes/treept1` and `treept2` growing straight out of the face
-- at y 158 and y 172, and by three `mushrooms.Mushroom` caps leaning over the ledge at y 202.
--
-- So after seating, a ledge is walked SOUTH -- out of the cliff, into the open gorge -- until a body
-- fits at its foot, its middle AND its head. Three quarters of a stud at a time, six studs at most,
-- because a ledge more than six studs off its own rock has stopped being part of the cliff and the
-- honest fix at that point is to move the leg, not to keep sliding.
local function pushSouth(model, z, ends)
	for step = 0, 8 do
		local tryZ = z + step * 0.75
		local clear = true
		for _, e in ipairs(ends) do
			if bodyBlocked(model, Vector3.new(e[1], e[2], tryZ)) then
				clear = false
				break
			end
		end
		if clear then return tryZ, step end
	end
	return z + 6, -1
end

local function dress(part, ref)
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if ref then
		part.Color = ref.Color
		part.Material = ref.Material
		part.CastShadow = ref.CastShadow
	else
		part.Color = Color3.fromRGB(120, 144, 130)
		part.Material = Enum.Material.Slate
	end
end

-- A sloped ledge whose TOP SURFACE runs from (x0, y0) to (x1, y1) at a fixed z.
--
-- The tilt is built with `CFrame.fromMatrix` rather than `CFrame.Angles`, because the sign of the
-- rotation flips with the leg's direction and getting it wrong silently builds an UPSIDE-DOWN
-- wedge -- the top face becomes the underside and a player walks on a surface pitched the wrong
-- way. Taking the up vector as `(0, 0, +-1) x direction` makes it come out right in both
-- directions by construction: the Z axis of the cross product carries the sign.
local function slopedLedge(model, name, x0, y0, x1, y1, z, depth, ref)
	local a, b = Vector3.new(x0, y0, z), Vector3.new(x1, y1, z)
	local span = b - a
	local length = span.Magnitude
	local dir = span.Unit
	local up = Vector3.new(0, 0, x1 > x0 and 1 or -1):Cross(dir)

	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(length, THICK, depth)
	dress(part, ref)
	-- The midpoint of the TOP face, pushed half a thickness down the ledge's own up vector.
	part.CFrame = CFrame.fromMatrix((a + b) * 0.5 - up * (THICK * 0.5), dir, up)
	part.Parent = model
	return part
end

local function flatLedge(model, name, x, y, z, sx, sz, ref)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(sx, THICK, sz)
	dress(part, ref)
	part.Position = Vector3.new(x, y - THICK * 0.5, z)
	part.Parent = model
	return part
end

-- ===== BUILD =====

function WaterfallParkour.Build()
	local decor = workspace:FindFirstChild("Decorations")
	local falls = decor and decor:FindFirstChild("Waterfall")
	if not falls then
		-- The same guard, and the same shape of guard, as `WorldApron`'s missing WorldShell: every
		-- ledge above the shore is seated by a raycast into this model's rock, and with the model
		-- absent they would all fall back to their default Z and build a ladder in open air.
		warn("[WaterfallParkour] no Decorations.Waterfall -- the climb is skipped "
			.. "(ForestMapService/MapWaterfall has not run)")
		return nil
	end

	local previous = workspace:FindFirstChild(MODEL_NAME)
	if previous then
		if previous:GetAttribute("ParkourVersion") == ROUTE_VERSION then
			return previous
		end
		previous:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	-- A route that streams out at range is worse than no route: a player halfway up would be
	-- standing on nothing. Same pin `ZoneBuilder` puts on the world shell.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("ParkourVersion", ROUTE_VERSION)
	-- Read by the scenery-grounding pass, which has been told to leave anything Parkour alone.
	model:SetAttribute("Parkour", true)

	local params = newRayParams(model)

	-- THE COLOUR REFERENCE HAS TO BE ROCK, AND "WHATEVER THE SEATING RAY HIT" IS NOT THE SAME THING.
	-- Measured on the first full build, 2026-08-28: four of sixty-one ledges came out in the wrong
	-- material -- two in a grey Plastic, one in a white SmoothPlastic and one in Grass -- because
	-- those are the collidable things the ray met at those heights. Every one of them is a perfectly
	-- good thing to SEAT against and a terrible thing to match, so the Z comes from any collidable
	-- hit and the look comes only from the falls' own Slate.
	local function rockLook(hit, fallback)
		if hit and hit:IsDescendantOf(falls) and hit.Material == Enum.Material.Slate then
			return hit
		end
		return fallback
	end

	-- One reference cast for the shore stones, which have no cliff of their own to match: it takes
	-- the buttress's own colour rather than a literal. (245, 60) is the middle of the big lower
	-- face, which is unbroken rock for fifty studs in every direction.
	local reference = rockLook(select(2, rockFaceAt(params, 245, 60)), nil)

	local index = 0
	local function record(part, entry, exit, jump)
		index += 1
		part:SetAttribute("ParkourIndex", index)
		part:SetAttribute("ParkourJump", jump and true or false)
		-- Audit() measures exit(n) -> entry(n + 1), and those are EDGES, not centres: the entry of a
		-- sloped ledge is its foot and its exit is its head, so the number the audit prints is the
		-- span of empty air a player actually crosses.
		part:SetAttribute("ParkourEntry", entry)
		part:SetAttribute("ParkourExit", exit)
	end

	-- ----- the shore -----
	for i, stone in ipairs(APPROACH) do
		local x, y, sx, sz = stone[1], stone[2], stone[4], stone[5]
		local z = stone[3] + APPROACH_LANE
		local part = flatLedge(model, "ParkourStone" .. i, x, y, z, sx, sz, reference)
		-- The approach walks WEST, so the east edge is where you land and the west edge is where
		-- you leave from.
		record(part,
			Vector3.new(x + sx * 0.5, y, z),
			Vector3.new(x - sx * 0.5, y, z),
			i > 1)
	end

	-- The cairn. Three stones, decreasing, on the start pad -- not part of the chain, and small
	-- enough that a player walks over them rather than onto them.
	do
		local base = APPROACH[1]
		for i = 1, 3 do
			local s = 3.4 - (i - 1) * 0.9
			local cairn = Instance.new("Part")
			cairn.Name = "ParkourCairn" .. i
			cairn.Size = Vector3.new(s, s * 0.6, s)
			dress(cairn, reference)
			cairn.CanCollide = false   -- the ONE exception, and it is not walked on
			cairn.Position = Vector3.new(base[1] + 5.5, base[2] + s * 0.3 + (i - 1) * 1.7,
				base[3] + APPROACH_LANE - 3.5)
			cairn.Parent = model
		end
	end

	-- ----- the switchback -----
	local y = APPROACH[#APPROACH][2]
	local z = APPROACH[#APPROACH][3]
	local legIndex = 0
	-- The southernmost edge any ledge of the PREVIOUS leg reached. An outer leg is clamped behind
	-- it, which is what actually guarantees the two lanes never share air (see THE LANE).
	local prevSouth = -math.huge

	for _, leg in ipairs(LEGS) do
		legIndex += 1
		local legSouth, lastZ = -math.huge, z
		-- Odd legs hug the rock, even legs stand LANE studs out over the gorge, and a turn pad belongs
		-- to whichever lane the NEXT leg will climb in. See THE LANE above.
		-- `laneBase` is the parity lane and `lane` is where the ledges actually go. They are kept
		-- apart because only the parity decides whether this leg is the one standing OVER the leg
		-- below: an `out` nudge is a local dodge, not a change of lane. Conflating them cost leg 15 --
		-- `out = 4` made its lane non-zero, the outer-leg clamp below fired, and it landed 18 studs
		-- south of the pad that hands off to it with nothing in between.
		local laneBase = (legIndex % 2 == 0) and LANE or 0
		local lane = laneBase + (leg.out or 0)
		local restOuter = (legIndex % 2 == 1)
		local west = leg.west or X_WEST
		local east = leg.east or X_EAST
		if leg.z then z = leg.z end
		local east2west = (leg.dir == "W")
		local xStart = east2west and east or west
		local step = east2west and -1 or 1

		local gaps = leg.slabs - 1
		local run = ((east - west) - gaps * leg.gap) / leg.slabs
		-- The lifts are taken OUT of the leg's rise before it is shared between the ledges, so a leg
		-- gains exactly `rise` whether its gaps are level or lifted.
		local perSlab = (leg.rise - gaps * leg.lift) / leg.slabs

		-- Seats one piece and returns its Z and the rock it matched. It probes every sample point
		-- along the ledge rather than only its middle: the face moves with height as well as with X
		-- (the lower buttress OVERHANGS -- it comes six studs back toward the pool between y 34 and
		-- y 88), so a mid-ledge probe leaves the lower end a stud inside the rock. SOUTHERNMOST wins.
		local function seat(ends)
			if leg.z then return leg.z, nil end
			local faceZ, hitPart
			for _, e in ipairs(ends) do
				local f, part = rockFaceAt(params, e[1], e[2] + 2)
				if f and (faceZ == nil or f > faceZ) then faceZ, hitPart = f, part end
			end
			if not faceZ then return z, nil end
			-- `clamp` and not `min`: the face has to be chased in both directions, and the clamp is
			-- what turns a recess in the rock into a ledge that hangs out over the gorge for a piece
			-- or two instead of a hole in the route.
			return math.clamp(faceZ + STANDOFF, z - MAX_NORTH, z + MAX_SOUTH), hitPart
		end

		local x = xStart
		for s = 1, leg.slabs do
			local x0, y0 = x, y
			local x1, y1 = x + step * run, y + perSlab
			-- Five samples along the ledge, not three. A ledge whose two ENDS are clear can still have
			-- its middle third buried in a bulge, and a ledge you cannot walk the length of is worse
			-- than one you cannot land on -- you only find out mid-run.
			local ends = {}
			for k = 0, 4 do
				table.insert(ends, { x0 + (x1 - x0) * k / 4, y0 + (y1 - y0) * k / 4 })
			end

			local seated, hitPart = seat(ends)
			-- An outer leg has to clear the leg BELOW it in Z, not merely stand LANE studs off the
			-- face: `seat` chases the rock, the rock steps north, and a plain `seated + LANE` drifts
			-- back over the inner leg it is meant to stand beside. Measured on v2's first build,
			-- `ParkourLedge2_1` came out 2.30 studs over the head of `ParkourLedge1_2` exactly that
			-- way. The floor is the previous leg's southernmost edge.
			local want = seated + lane
			if laneBase > 0 then want = math.max(want, prevSouth + DEPTH * 0.5) end
			local pushed, steps = pushSouth(model, want, ends)
			if steps < 0 then
				warn(("[WaterfallParkour] leg %d piece %d could not be cleared: no body box fits "
					.. "within six studs of z %.1f at y %.1f -- move the leg"):format(legIndex, s,
					seated, y0))
			end
			-- `z` tracks the FACE and stays lane-free, so the next piece's clamp is measured against
			-- the rock rather than against whichever lane this piece happened to be standing in.
			z = seated + (pushed - want)
			legSouth = math.max(legSouth, pushed + DEPTH * 0.5)
			lastZ = pushed
			-- The last slab reaches across the join into its turn pad; every other slab is plain DEPTH.
			-- `lastZ` and the recorded entry/exit stay on the UNSHIFTED centre, so the pad's own
			-- placement and every measurement the audit takes are unchanged by this.
			local last = (s == leg.slabs) and leg.rise >= SEAM_MIN_RISE
			local depth = last and (DEPTH + SEAM) or DEPTH
			local centre = last and (pushed + (restOuter and SEAM * 0.5 or -SEAM * 0.5)) or pushed

			local part = slopedLedge(model,
				("ParkourLedge%d_%d"):format(legIndex, s),
				x0, y0, x1, y1, centre, depth, rockLook(hitPart, reference))
			record(part, Vector3.new(x0, y0, pushed), Vector3.new(x1, y1, pushed), s > 1)

			y = y1
			x = x1
			if s < leg.slabs then
				x += step * leg.gap
				y += leg.lift
			end
		end

		-- The rest at the turn. Walked onto, never jumped to -- it shares the last ledge's head, so
		-- the two overlap and read as one shelf.
		local seated, hitPart = seat({ { x, y } })
		z = seated
		-- The pad sits BESIDE the ramp that arrives at it, never over it: an outer pad starts at the
		-- inner lane's south edge and reaches out, an inner pad IS the inner lane. Either way the two
		-- share an edge in Z -- which is a walk -- and share no volume, which is the whole bug.
		-- A pad has to reach BOTH neighbours, and the two are in different lanes: the ramp that
		-- arrives is at `lastZ`, and the ramp that leaves is seated wherever the rock is at this very
		-- x/y -- which is `seated`, the same probe, so it is known here. v2's first build placed the
		-- inner pads a fixed LANE north of the arriving ramp instead, and the rock had stepped north
		-- underneath them: four pads ended up stranded 1.8 to 6.4 studs SOUTH of the ramp they were
		-- meant to hand off to, which is open air at the same height -- the exact shape of a dead end.
		--
		-- So a pad is sized to its own two edges instead of to a constant. Outer pads (odd legs, the
		-- next leg swings out over the gorge) run from the arriving ramp's south edge outward; inner
		-- pads (even legs, the next leg comes back to the rock) run from that same edge north to the
		-- face lane, plus MAX_NORTH of slack for however far the next seat is allowed to chase it.
		local restDepth, restZ
		if restOuter then
			restDepth = REST_Z
			restZ = lastZ + DEPTH * 0.5 + REST_Z * 0.5
		else
			local south = lastZ - DEPTH * 0.5
			local north = math.min(south - DEPTH, seated - DEPTH * 0.5 - MAX_NORTH)
			restDepth = south - north
			restZ = (south + north) * 0.5
		end
		restZ = pushSouth(model, restZ, { { x, y } })
		local rest = flatLedge(model, "ParkourRest" .. legIndex, x, y, restZ,
			leg.restX or REST_X, restDepth, rockLook(hitPart, reference))
		record(rest, Vector3.new(x, y, restZ), Vector3.new(x, y, restZ), false)
		prevSouth = legSouth
	end

	model.Parent = workspace

	print(("[WaterfallParkour] built v%d: %d pieces, %d legs, shore (%d, %.1f, %d) -> summit "
		.. "(%.0f, %.1f, %.0f)")
		:format(ROUTE_VERSION, index, #LEGS,
			APPROACH[1][1], APPROACH[1][2], APPROACH[1][3],
			model:FindFirstChild("ParkourRest" .. #LEGS).Position.X, y, z))

	return model
end

-- ===== AUDIT =====
--
-- The play-verification this course cannot have. Two other agents are editing the same Studio
-- instance, so a playtest would take the Edit datamodel away from both of them; this walks the
-- chain instead and asserts the three things a playtest would have told us.
--
--  1. the horizontal span of empty air between one piece's exit edge and the next piece's entry
--     edge, and the rise across it, against the ballistics of the WEAKEST body in the game;
--  2. whether a 4 x 6 x 4 humanoid box fits at the landing spot -- the identical test
--     `SecretsService.reportBlocked` runs, and named after it, because a ledge buried in the cliff
--     fails exactly as silently as a trigger buried in one;
--  3. that the last piece actually puts a player on the egg's shelf.
function WaterfallParkour.Audit()
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not model then
		warn("[WaterfallParkour] nothing to audit -- Build() has not run")
		return nil
	end

	-- Read, not typed: if someone retunes the movement curve this audit retunes with it.
	local ok, GameConfig = pcall(function() return require(ReplicatedStorage.Modules.GameConfig) end)
	local walk = (ok and GameConfig.BaseWalkSpeed) or 34
	local power = (ok and GameConfig.BaseJumpPower) or 44
	local g = workspace.Gravity
	local apex = power * power / (2 * g)

	-- Horizontal ground covered by a jump that LANDS `h` studs above where it took off.
	-- Solving g/2 t^2 - power t + h = 0 for the descending root.
	local function reach(h)
		local disc = power * power - 2 * g * h
		if disc < 0 then return nil end
		return ((power + math.sqrt(disc)) / g) * walk
	end

	local pieces = {}
	for _, part in ipairs(model:GetChildren()) do
		local i = part:GetAttribute("ParkourIndex")
		if i then pieces[i] = part end
	end

	local lines = {}
	table.insert(lines, ("[WaterfallParkour] audit v%d -- against the weakest body in the game: "
		.. "walk %.0f, jumpPower %.0f, gravity %.1f -> apex %.2f, level reach %.2f")
		:format(ROUTE_VERSION, walk, power, g, apex, reach(0)))

	local jumps, worst, worstAt = 0, -1, nil
	local blocked = 0
	local walks = {}

	-- Ray straight down along a straight line between two standing spots, every three studs, and
	-- report the worst step and any sample with nothing under it. The route's own pieces are IN
	-- this cast -- half of what a player walks on here IS the route.
	--
	-- EACH RAY STARTS FOUR STUDS OVER THE WALK, NOT FORTY OVER THE HIGHER END, and that is not a
	-- tidiness detail: this is a SWITCHBACK, so leg n + 4 is directly above leg n. A ray dropped
	-- from high enough to clear both ends hits the UNDERSIDE of a ledge two legs up and reports it
	-- as the ground -- the first run of this check called the 3.5-stud step onto ParkourRest11 a
	-- 17-stud one, and the 17 studs were `ParkourRest13` overhead. Thirty studs of ray below the
	-- walk line is enough to find a hole and short enough to miss the roof.
	local function walkable(from, to)
		local params = RaycastParams.new()
		params.RespectCanCollide = true
		local span = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local steps = math.max(1, math.ceil(span.Magnitude / 3))
		local prevY, gaps, worstStep = nil, 0, 0
		for i = 0, steps do
			local t = i / steps
			local p = Vector3.new(from.X, 0, from.Z) + span * t
			local top = from.Y + (to.Y - from.Y) * t + 4
			local hit = workspace:Raycast(Vector3.new(p.X, top, p.Z), Vector3.new(0, -30, 0), params)
			if not hit then
				gaps += 1
			else
				if prevY then worstStep = math.max(worstStep, math.abs(hit.Position.Y - prevY)) end
				prevY = hit.Position.Y
			end
		end
		return span.Magnitude, gaps, worstStep
	end

	for i = 2, #pieces do
		local part = pieces[i]
		local entry = part:GetAttribute("ParkourEntry")
		local exit = pieces[i - 1]:GetAttribute("ParkourExit")
		local isJump = part:GetAttribute("ParkourJump")

		-- The body box, at the landing spot, lifted clear of the ledge's own top face.
		local probe = CFrame.new(entry + Vector3.new(0, 3.2, 0))
		local solid, blame = 0, {}
		for _, other in ipairs(workspace:GetPartBoundsInBox(probe, BODY_BOX)) do
			if other.CanCollide and not other:IsDescendantOf(model) then
				solid += 1
				if #blame < 3 then table.insert(blame, other:GetFullName()) end
			end
		end

		if isJump then
			jumps += 1
			local span = entry - exit
			local flat = Vector3.new(span.X, 0, span.Z).Magnitude
			local rise = span.Y
			local r = reach(rise)
			local pct = r and (flat / r * 100) or math.huge
			if pct > worst then worst, worstAt = pct, part.Name end
			table.insert(lines, ("  %-18s JUMP gap %5.2f  rise %+5.2f  reach %6.2f  %5.1f%%  box %d%s")
				:format(part.Name, flat, rise, r or -1, pct, solid,
					solid > 0 and (" -- " .. table.concat(blame, ", ")) or ""))
		else
			-- A walk transition is only free if the two pieces actually touch. They are built to
			-- overlap at every turn, so this should read ~0 -- except at leg 17, which starts 23
			-- studs north of leg 16's rest on the far side of the summit plateau. That one is a walk
			-- over real ground and the summit-walk check at the bottom is what proves it.
			local span = entry - exit
			local flat = Vector3.new(span.X, 0, span.Z).Magnitude
			table.insert(lines, ("  %-18s walk  step %5.2f  rise %+5.2f              box %d%s")
				:format(part.Name, flat, span.Y, solid,
					solid > 0 and (" -- " .. table.concat(blame, ", ")) or ""))
			if flat > 3 then
				local dist, gaps, step = walkable(exit, entry)
				table.insert(walks, { name = part.Name, dist = dist, gaps = gaps, step = step })
			end
		end

		if solid > 0 then blocked += 1 end
	end

	-- Any walk transition longer than a stride gets the same ground check the summit walk gets:
	-- "the pieces overlap so you can walk it" is an assumption, and the 23.5-stud crossing of the
	-- summit plateau between leg 16 and leg 17 is not an overlap at all -- it is real mountain, and
	-- the only thing that says so is a ray.
	for _, span in ipairs(walks) do
		table.insert(lines, ("  plateau/ledge walk %-16s %.1f studs, %d sample(s) over open air, "
			.. "tallest step %.2f"):format(span.name, span.dist, span.gaps, span.step))
	end

	-- ===== THE ARC =====
	--
	-- The other half of what v1 never checked. HEADROOM asks whether a player can STAND on a piece;
	-- this asks whether they survive the FLIGHT between two of them, and the two are different
	-- questions because a Roblox jump is fixed-power: pressing space always spends the full 4.93
	-- studs of apex, even across a gap that needs none of it. So a ceiling ten studs up is not
	-- headroom -- it is the thing the player's head hits at the top of every jump under it.
	--
	-- The body box is flown along the real ballistic arc at twenty samples, and the two pieces the
	-- jump leaves from and lands on are excluded because it starts and ends touching them.
	local clipped = 0
	for i = 2, #pieces do
		local part = pieces[i]
		if part:GetAttribute("ParkourJump") then
			local a = pieces[i - 1]:GetAttribute("ParkourExit")
			local b = part:GetAttribute("ParkourEntry")
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local flight = (power + math.sqrt(math.max(0, power * power - 2 * g * (b.Y - a.Y)))) / g
			local air = OverlapParams.new()
			air.FilterType = Enum.RaycastFilterType.Exclude
			air.FilterDescendantsInstances = { pieces[i - 1], part }
			local at, blame = nil, nil
			for k = 1, 20 do
				local t = flight * k / 20
				local p = a + flat * (t / flight) + Vector3.new(0, power * t - 0.5 * g * t * t, 0)
				for _, other in ipairs(workspace:GetPartBoundsInBox(
					CFrame.new(p + Vector3.new(0, 3.2, 0)), BODY_BOX, air)) do
					if other.CanCollide then at, blame = t / flight, other:GetFullName() end
				end
			end
			if at then
				clipped += 1
				table.insert(lines, ("  CLIPPED %-17s the jump onto it strikes something at %.0f%% of "
					.. "flight -- %s"):format(part.Name, at * 100, blame))
			end
		end
	end

	-- ===== HEADROOM =====
	--
	-- The check that was missing in v1 and that let the whole climb ship unwalkable (see THE LANE).
	-- Every other test here asks whether a player can REACH a spot; this one asks whether they can
	-- STAND UP in it. It has to look at the route's own parts -- they were the ceiling every single
	-- time -- so it cannot reuse the model exclusion the box test needs.
	--
	-- Nine samples along each piece's own top surface, ray up 7 studs, self excluded. A hit inside
	-- 5.5 studs is only forgiven when the thing overhead is something a player would simply be
	-- STANDING ON instead: its top within one apex of this surface, and clear air above THAT. That is
	-- the honest difference between the next ramp growing out of a pad (fine, you step onto it) and
	-- the next ramp closing over a ledge (fatal, you stop in the wedge).
	local pinched = 0
	local function headroom(piece)
		local a, b = piece:GetAttribute("ParkourEntry"), piece:GetAttribute("ParkourExit")
		local worstGap, worstBlame, worstT = math.huge, nil, 0
		for k = 0, 8 do
			local t = k / 8
			local spot = a:Lerp(b, t)
			local up = RaycastParams.new()
			up.FilterType = Enum.RaycastFilterType.Exclude
			up.FilterDescendantsInstances = { piece }
			up.RespectCanCollide = true
			local hit = workspace:Raycast(spot + Vector3.new(0, 0.4, 0), Vector3.new(0, 7, 0), up)
			if hit then
				local gap = hit.Position.Y - spot.Y
				-- Would a player just be standing on it? Its top, then the air over its top.
				local only = RaycastParams.new()
				only.FilterType = Enum.RaycastFilterType.Include
				only.FilterDescendantsInstances = { hit.Instance }
				local top = workspace:Raycast(spot + Vector3.new(0, 14, 0), Vector3.new(0, -14, 0), only)
				if top and (top.Position.Y - spot.Y) <= apex then
					up.FilterDescendantsInstances = { piece, hit.Instance }
					local over = workspace:Raycast(top.Position + Vector3.new(0, 0.4, 0),
						Vector3.new(0, 7, 0), up)
					gap = over and (over.Position.Y - top.Position.Y) or math.huge
				end
				if gap < worstGap then
					worstGap, worstBlame, worstT = gap, hit.Instance, t
				end
			end
		end
		return worstGap, worstBlame, worstT
	end
	for i = 1, #pieces do
		local gap, blame, t = headroom(pieces[i])
		if gap < 5.5 then
			pinched += 1
			table.insert(lines, ("  PINCHED %-17s %.2f studs of headroom at t=%.2f -- %s")
				:format(pieces[i].Name, gap, t, blame and blame:GetFullName() or "?"))
		end
	end

	-- ===== AND THEN THE WALK =====
	--
	-- The course does not end AT the egg and must not: the shelf was chosen to be hidden from the
	-- bridge and the brief is explicit that arriving should still take a look around. So the last
	-- assertion is not "the route reaches (258, 219.5, -354)", it is "from where the route puts a
	-- player, the shelf is a WALK" -- real ground the whole way, no step taller than the apex.
	-- Sampled every three studs, straight line, ray down from 40 studs up.
	local last = pieces[#pieces]
	local shelf = Vector3.new(258, 219.5, -354)
	local top = last:GetAttribute("ParkourExit")
	do
		local dist, gaps, worstStep = walkable(top, shelf)
		table.insert(lines, ("  summit walk: %s -> the egg shelf %s is %.1f studs, %d sample(s) "
			.. "over open air, tallest step %.2f (apex %.2f)")
			:format(tostring(top), tostring(shelf), dist, gaps, worstStep, apex))
	end
	table.insert(lines, ("  %d pieces, %d jumps, hardest %s at %.1f%% of reach, %d landing(s) blocked, "
		.. "%d piece(s) pinched, %d arc(s) clipped")
		:format(#pieces, jumps, tostring(worstAt), worst, blocked, pinched, clipped))

	local report = table.concat(lines, "\n")
	print(report)
	return report
end

function WaterfallParkour.Init()
	WaterfallParkour.Build()
end

return WaterfallParkour
