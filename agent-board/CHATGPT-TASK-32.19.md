# TASK 32.19 — the mountains stand on the zone gate. Move them off it.

You are being handed one self-contained change to a Roblox Luau file in a game called Evolution
Lab. You do **not** have the repository or the running game. Everything you need is pasted below.
**Return a patch and nothing else** — the measurement, the rebuild and the screenshot are done here
after you answer.

---

## 1. What is wrong, measured in the live world

The zone's **arrival gate** — a pink stone portal at the north end of the Forest platform — stands
inside the mountain range that is supposed to be *behind* it. The owner's words, on her own
screenshot: *"zakopan je ne vidi se kako treba"* ("it is buried, it doesn't show properly").

Measured on the live server, 2026-08-24:

```
north gate parts                       57, spanning x -120..108, y 0..222, z 308..657
  ... inside a hill's own bounding box 48 of 57
  ... inside a hill COLLIDER box       18 of 57
gate footprint, 12-stud raycast grid   600 cells; 252 of them (42%) land on a
                                       HorizonHillCollider whose top is y = 236.4
the two hills responsible (inner row)  centre (-242, 111, 568), reaches x -418..-65
                                       centre ( 261, 112, 556), reaches x   83..440
their collider boxes                   (-242, 117, 611), x -448..-35, 238 studs tall
                                       ( 261, 119, 601), x   71..451, 241 studs tall
the walkway itself                     still open: a body-box walk to ZonePad (0, 0.5, 490)
                                       is 20 samples, 0 blocked, because the lane holds at x ~ 0
```

So 42% of the ground in front of the portal is an invisible 238-stud wall, and the portal's own
stonework is inside the mountains.

## 2. Why — the arithmetic, and it is the whole task

`MapHorizon` builds the range as four runs of hills. The two runs along the X axis (the north and
south walls) leave a **lane** — a gap in the middle — so a hill does not stand on the portal.
`buildRun` reserves that lane by holding the hill's **centre** this far from the middle of the run:

```lua
local lo = spec.lane > 0 and (spec.lane + spec.alongLen * FILL / 2) or 0
```

`FILL = 0.55` is a *silhouette* fraction — how much of a hill's bounding box is rock averaged over
its whole height. But the **collider** that yesterday's change (row 32.15) stands beside each hill
is built from `ROCK_FOOT = 0.92` of the same box, because at the player's feet a mountain fills
nearly all of it. Those two numbers disagree by `(0.92 - 0.55) / 2 = 0.185` of the hill's length,
and the hill length here is about 460 studs — so **every collider overhangs its own lane by roughly
85 studs**. With `LANE_PORTAL = 90`, the reserved gap is ±90 and the collider edges land at
x = -35 and x = +71. That is the 42%.

The file already knows this argument. `MapHorizon.Colliders` refuses to box the OUTER row for
exactly this reason, in its own words: *"a box on an outer hill is a box across the gate."* The same
argument reaches the inner row's lane and was never applied to it.

And the comment above `LANE_PORTAL` says why 90 was chosen over the older 132 — **on a premise that
died yesterday**:

> `PORTAL_CLEAR_HALF` is a WALKWAY reservation and these hills do not collide, do not query and are
> sunk 15 studs — nothing walks into them.

They collide now.

## 3. The decision, already taken by the owner

She was offered two fixes and picked the first:

- **(a) CHOSEN — widen the lane until the gate's own footprint is clear**, so the range moves off
  the portal and it reads as a portal standing in the open.
- (b) rejected — keep the art where it is and clip only the collider boxes off the gate.

## 4. The code you are changing

File: `src/ServerScriptService/MapProps/MapHorizon.lua` (794 lines). The relevant parts, verbatim:

```lua
-- line 107: the boundary, restated rather than required (this file's own convention)
local WALL_X, WALL_Z, WALL_H = 625, 575, 180

local COVER_INNER = 1.55
local COVER_OUTER = 1.90
local SINK = 15

local AT = {
	innerX = 600, innerZ = 568,
	outerX = 812, outerZ = 776,
}

-- line 190
local LANE_PORTAL = 90

-- line 213
local OVERLAP = 0.32

-- line 226
local FILL = 0.55            -- silhouette: how much of the box is rock over the whole height

-- line 242
local KEEPOUT_FILL = 0.35

-- line 246
local YAW_JITTER = 0.21
local SIZE_JITTER = { 0.95, 1.15 }

-- line 510: what a COLLIDER uses, measured with a raycast grid on a queryable clone
local ROCK_FOOT = 0.92

-- line 552
local function buildRun(proto, folder, cx, rng, spec, out)
	local placed = 0
	-- The rock's half-length, not the box's -- see the note on `LANE_PORTAL`.
	local lo = spec.lane > 0 and (spec.lane + spec.alongLen * FILL / 2) or 0
	local hi = spec.span
	if lo > hi then return 0 end
	-- Both halves of the run, or the whole of it when there is no lane.
	for _, side in ipairs(spec.lane > 0 and { -1, 1 } or { 1 }) do
		local a, b = spec.lane > 0 and lo or -hi, hi
		local n = math.max(math.ceil((b - a) / spec.spacing) + 1, 2)
		for i = 1, n do
			local t = a + (b - a) * (i - 1) / (n - 1)
			local along = spec.lane > 0 and side * t or t
			-- ... places a hill at (along, spec.at) or (spec.at, along) ...
		end
	end
	return placed
end

-- inside MapHorizon.Build, per tier ("inner" then "outer"):
local scale = scaleFor(inner and COVER_INNER or COVER_OUTER)
local acrossHalf = (shortAxis * turnC + longAxis * turnS) * scale / 2
local alongLen  = (longAxis * turnC + shortAxis * turnS) * scale
local spacing   = alongLen * OVERLAP
local spanZ = WALL_Z + acrossHalf * 0.5
local spanX = WALL_X + acrossHalf * 0.5
for _, r in ipairs({
	{ axis = "z", at = -atX, span = spanZ, lane = 0 },
	{ axis = "z", at =  atX, span = spanZ, lane = 0 },
	{ axis = "x", at = -atZ, span = spanX, lane = inner and LANE_PORTAL or 0 },
	{ axis = "x", at =  atZ, span = spanX, lane = inner and LANE_PORTAL or 0 },
}) do
	r.scale, r.acrossHalf, r.alongLen, r.spacing = scale, acrossHalf, alongLen, spacing
	r.solid = inner and solid or nil
	hills += buildRun(proto, folder, cx, rng, r, out)
	runs += 1
end
```

One more fact you need: the walkway reservation the old comment names still exists in this codebase
as **`ZoneGate.PORTAL_CLEAR_HALF = 132`** — *"how far boulders stay off the centre line"*. This file
does **not** require `ZoneGate`; it restates constants with a comment instead (see `WALL_X` above),
and you should follow that convention rather than adding a require.

## 5. What your patch must do

1. **Make the lane reserve what the COLLIDER actually occupies, not the silhouette.** The offset in
   `buildRun` must be derived from the same fraction the collider is built from (`ROCK_FOOT`), not
   from `FILL`. Only the run that carries colliders needs this to be true, and today that is exactly
   the run that has a lane — say so in the comment rather than leaving it implied.
2. **Make the lane at least as wide as the gate's own stonework.** The gate spans x -120..108, so a
   half-width of 90 was never enough even before the colliders existed. Use the walkway reservation
   (132) rather than a new hand-typed number, restated with a comment naming `ZoneGate`.
3. **Rewrite the comment block above `LANE_PORTAL` so it tells the truth.** It currently argues for
   90 on the grounds that these hills do not collide. That premise is dead. Keep the history — the
   repo's rule is that a comment explaining WHY a number is what it is, is the most expensive line
   in the file to lose — but say what changed and when (row 32.15 gave the inner row colliders; row
   32.19 is this change).
4. **Change nothing else.** No new requires. No renamed functions. No "while I was here" tidying.
   Do not touch `Colliders`, `trimOffRoads`, `hill`, `worldBox` or any constant not named above.

## 6. What will be run against your patch here, so you know the acceptance test

- `luastruct.py` must parse the file.
- The world is rebuilt in Roblox Studio and the boot line re-read. Today it says:
  `[MapHorizon] Forest: 66 hills over 8 runs ... 34 collider box(es) offered, 29 clipped, 0 dropped`
- A 12-stud raycast grid over the gate footprint (x -120..108, z 308..657, 600 cells) must report
  **0 cells standing on a `HorizonHillCollider`** — it is 252 today.
- The 32.15 walk probe and the camp checks must not move: `1656 samples, 0 blocked`, and
  `0 of 20 camp floors overlapped by a box`.
- A screen capture from the player's own eye at the gate must show the portal standing clear.
- **The risk your change carries, and it will be captured:** widening the lane thins the inner wall
  above the gate. An older cut at 132 measured the wall **48% bare on the south and 41% on the
  north**. Since then the OUTER row has been made to run whole across the gate precisely to fill
  that hole. If you believe your change reopens it, say so in one sentence under the patch — do not
  add a second mechanism to compensate for it.

## 7. Answer format

Return, in this order and nothing else:

1. The complete replacement text for each block you changed, each one preceded by the line number it
   starts at in the file above.
2. One short paragraph: what you changed the numbers to, and the arithmetic that says the gate is
   now clear (lane + alongLen * fraction / 2, against a gate half-width of 120).
3. Any risk you want recorded, one sentence each.

No invented asset ids, no invented file names, no probes, no claims about having run anything.
