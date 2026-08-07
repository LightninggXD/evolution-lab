# Pushing `src/` back into Roblox Studio

Read `SYNC.md` first for why this tree exists. Nothing in it has ever been run.

## Before anything else

The place file on disk (`EvolutionLab.rbxl`, last written 2026-08-03 00:27) predates the whole
rebuild, and there is no Roblox `AutoSaves` directory on this machine. So the Studio session that
held `UITheme` and the 17 applied `MainUI` edits was never saved anywhere. **This tree is the only
copy of that work.** Treat a push as a restore, not a patch.

1. Open Roblox Studio with the place loaded, MCP enabled in Assistant Settings.
2. `list_roblox_studios` → confirm the active instance is the right one. Do not skip this.
3. `get_studio_state` → confirm **Edit** mode.
4. `search_game_tree` on `ReplicatedStorage.Modules` and `ServerScriptService` to see what is
   actually there. If `Modules.UITheme` is missing, the Studio session was lost and every file
   below is a create. If it is present at 819 lines, the session survived and MainUI /
   CreatureService are in the half-edited state described in `SYNC.md`.

## Why you cannot patch these in

`multi_edit`'s empty-`old_string` form only sets initial content **when it creates a new script**.
On an existing script there is no whole-file-replace, and the `old_string` anchors from the
original source will not match, because the Studio copies already carry a partial rewrite.

So for each file, replace the instance:

```lua
-- execute_luau, datamodel_type = "Edit"
local s = game.ServerScriptService.ZoneBuilder
print(#s:GetChildren())            -- must be 0, see the caveat below
s.Parent = nil                     -- keep the reference alive in case you need to undo
```

then `multi_edit` with `className` set and a single edit whose `old_string` is `""` and whose
`new_string` is the entire file. The source travels as a JSON string, so there is no Lua quoting
or long-bracket escaping to get wrong — which is the reason to prefer this over streaming the
text through `execute_luau`.

**Caveat:** destroying a script drops its children. These six were childless when they were read,
but verify with `inspect_instance` before you reparent anything to nil. If a script has grown
children since, reparent them onto the new instance afterwards.

## Order matters

| # | Target path | Source file | className |
|---|---|---|---|
| 1 | `game.ReplicatedStorage.Modules.UITheme` | `ReplicatedStorage/Modules/UITheme.lua` | `ModuleScript` |
| 2 | `game.ServerScriptService.ZoneBuilder` | `ServerScriptService/ZoneBuilder.lua` | `ModuleScript` |
| 3 | `game.ServerScriptService.CreatureService` | `ServerScriptService/CreatureService.lua` | `ModuleScript` |
| 4 | `game.ServerScriptService.BossService` | `ServerScriptService/BossService.lua` | `ModuleScript` |
| 5 | `game.StarterPlayer.StarterPlayerScripts.MainUI` | `StarterPlayer/StarterPlayerScripts/MainUI.client.lua` | `LocalScript` |

`UITheme` goes first — the other four require it, and a broken UITheme fails them all at once.

Do **not** push `GameConfig.lua`. It is mirrored here only because the other files read its zone
and boss tables; nothing in this work modifies it, and the Studio copy is authoritative.

## Verify in this order

**1. UITheme compiles and holds its invariant.** This is the probe the original build agent used;
it is the single check that the unreadable-button bug has not come back:

```lua
local t = require(game.ReplicatedStorage.Modules.UITheme)
local g = Instance.new("ScreenGui"); g.Parent = game:GetService("CoreGui")
local b = t.Button(g, { text = "Quick Sell", color = t.Color.Green })
local gloss = b:FindFirstChild("Gloss")
local label = b:FindFirstChild("Label")
print(("gloss=%.2f glossZ=%d labelZ=%d font=%s")
  :format(gloss.BackgroundTransparency, gloss.ZIndex, label.ZIndex, tostring(t.Font.Display)))
g:Destroy()
```

Expected: `gloss=0.74 glossZ=1 labelZ=3 font=Enum.Font.FredokaOne`. Gloss must be `>= 0.72` and
`labelZ` must be strictly greater than `glossZ`. Anything else — stop and fix before continuing.

**2. Each module requires cleanly**, one at a time, so a failure names itself:

```lua
for _, n in ipairs({"ZoneBuilder", "CreatureService", "BossService"}) do
  local ok, err = pcall(require, game.ServerScriptService[n])
  print(n, ok, err)
end
```

**3. Force a world rebuild.** `ZoneBuilder.Build()` skips any zone already in `workspace.Zones`,
so on an existing place none of the new biome code runs until the build-version guard trips. The
guard is now in the file (`BUILD_VERSION = 3`): it destroys the folder and regenerates when the
stamp does not match. It also prints a `warn` when it fires. Check both it and `EnsureSpawn`:

```lua
print(workspace:FindFirstChild("Zones"):GetAttribute("BuildVersion"))  -- expect 3
print(workspace:FindFirstChild("ForestSpawn").Position)                -- expect 0, 1, 170
print(#workspace:FindFirstChild("Zones").Mars:GetChildren())           -- expect hundreds, not 12
```

The third line is the real test that the 15 rebuilt biomes landed: `Mars` was a 12-part stub, so
anything in the low double digits means the old geometry survived and the guard did not fire.

**4. Play-test.** `start_stop_play(true)`, then `screen_capture` the HUD, each panel, the egg
plaza, and a few zones. The work is judged on how close the screenshots sit to the reference art —
not on whether it compiles. Compare against `assets/reference/`. Expect to iterate here.

**5. Save the place** (`File > Save`) as soon as the probes pass. That is what this whole document
exists to make unnecessary next time.
