import os
import json
import sys

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
            
            # Normalize newlines (convert CRLF to LF) for line-ending-independent hashing if needed,
            # but let's do direct byte compare first since the project guideline says "identical before you change".
            # Actually, some third-party files might have CRLF, but let's just do exact bytes and see.
            rel_path = os.path.relpath(full_path, src_dir)
            dotted = rel_path.replace(os.sep, ".")
            dotted = dotted[:-len(matched_suffix)]
            
            disk_files[dotted] = {
                "len": len(content),
                "hash": roll(content),
                "className": suffix_map[matched_suffix][0],
                "file_path": full_path
            }

    try:
        with open("temp_studio_files.json", "r", encoding="utf-8") as fh:
            live_files = json.load(fh)
    except Exception as e:
        print(f"Failed to read temp_studio_files.json: {e}")
        return 1
        
    mismatches = []
    missing_on_disk = []
    missing_in_studio = []
    matches_count = 0
    
    for dotted, info in disk_files.items():
        # Exclude _PushBackup files and other Studio-specific non-mirrored files
        if "ServerStorage._PushBackup" in dotted:
            continue
        if dotted not in live_files:
            missing_in_studio.append(dotted)
        else:
            live = live_files[dotted]
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
