"""Run a full hash-sweep comparing files in src/ to LuaSourceContainers in Roblox Studio.
"""

import os
import json
import sys
from studio_mcp import Studio, text_of

def roll(s):
    h = 0
    for b in s:
        h = (h * 31 + b) % 2147483647
    return h

def main():
    disk_files = {}
    src_dir = "src"
    
    suffix_map = {
        ".server.lua": ("Script", ""),
        ".client.lua": ("LocalScript", ""),
        ".lua": ("ModuleScript", "")
    }
    
    for root, dirs, files in os.walk(src_dir):
        for file in files:
            full_path = os.path.join(root, file)
            matched_suffix = None
            for suffix in suffix_map:
                if file.endswith(suffix):
                    matched_suffix = suffix
                    break
            if not matched_suffix:
                continue
            
            with open(full_path, "rb") as fh:
                content = fh.read()
            
            rel_path = os.path.relpath(full_path, src_dir)
            dotted = rel_path.replace(os.sep, ".")
            dotted = dotted[:-len(matched_suffix)]
            
            disk_files[dotted] = {
                "len": len(content),
                "hash": roll(content),
                "className": suffix_map[matched_suffix][0],
                "file_path": full_path
            }

    s = Studio()
    try:
        luau_code = """
local HttpService = game:GetService("HttpService")

local function roll(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end

local function getPath(inst)
	local parts = {}
	local curr = inst
	while curr and curr ~= game do
		table.insert(parts, 1, curr.Name)
		curr = curr.Parent
	end
	return table.concat(parts, ".")
end

local results = {}
local function scan(parent)
	if not parent then return end
	for _, child in ipairs(parent:GetDescendants()) do
		if child:IsA("LuaSourceContainer") then
			local path = getPath(child)
			local src = child.Source
			results[path] = {
				len = #src,
				hash = roll(src),
				className = child.ClassName
			}
		end
	end
end

scan(game:GetService("ReplicatedFirst"))
scan(game:GetService("ReplicatedStorage"))
scan(game:GetService("ServerScriptService"))
scan(game:GetService("ServerStorage"))
scan(game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"))

return HttpService:JSONEncode(results)
"""
        resp = s.call("execute_luau", {"code": luau_code, "datamodel_type": os.environ.get("STUDIO_DM", "Edit"), "studio_id": os.environ.get("STUDIO_ID")})
        res_text = text_of(resp)
        if res_text.startswith("ERROR:"):
            print(res_text)
            return 1
        
        try:
            live_files = json.loads(res_text)
        except Exception as e:
            print("Failed to decode JSON. Raw text response was:")
            print(repr(res_text))
            raise e
    finally:
        s.close()
        
    mismatches = []
    missing_on_disk = []
    missing_in_studio = []
    matches_count = 0
    
    for dotted, info in disk_files.items():
        # Exclude _PushBackup files which are expected not to be in Studio (or vice versa)
        if "ServerStorage._PushBackup" in dotted:
            continue
        if dotted not in live_files:
            missing_in_studio.append(dotted)
        else:
            live = live_files[dotted]
            # Normalise line endings in comparison?
            # Wait, the rule says "mismatch says different, not which". Let's do exact compare of bytes.
            # But let's check if the difference is CRLF vs LF.
            # We will show the details.
            if info["len"] != live["len"] or info["hash"] != live["hash"]:
                mismatches.append((dotted, info, live))
            else:
                matches_count += 1
                
    for dotted, live in live_files.items():
        if "ServerStorage._PushBackup" in dotted or dotted == "ServerStorage._RewardFresh" or "ServerScriptService.ZoneDecor" in dotted:
            continue
        if dotted not in disk_files:
            missing_on_disk.append(dotted)
            
    print(f"Sweep complete: {matches_count} matches.")
    if missing_in_studio:
        print(f"\nMissing in Studio ({len(missing_in_studio)}):")
        for m in missing_in_studio:
            print(f"  {m} ({disk_files[m]['file_path']})")
    if missing_on_disk:
        print(f"\nMissing on Disk ({len(missing_on_disk)}):")
        for m in missing_on_disk:
            print(f"  {m} ({live_files[m]['className']})")
    if mismatches:
        print(f"\nMismatches (Disk vs Studio) ({len(mismatches)}):")
        for dotted, disk, live in mismatches:
            print(f"  {dotted}:")
            print(f"    Disk:   len={disk['len']} hash={disk['hash']}")
            print(f"    Studio: len={live['len']} hash={live['hash']}")
            
    if missing_in_studio or missing_on_disk or mismatches:
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
