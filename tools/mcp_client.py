import subprocess
import json
import sys
import time

lua_code = """
local HttpService = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")

local function push(inst, url)
    if not inst then return "Not found" end
    local src = HttpService:GetAsync(url)
    SES:UpdateSourceAsync(inst, function() return src end)
    return "OK"
end

local splicer = game:GetService("ServerScriptService"):FindFirstChild("SplicerService")
local r1 = push(splicer, "http://127.0.0.1:8731/src/ServerScriptService/SplicerService.lua")

local mainUi = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("MainUI")
local r2 = push(mainUi, "http://127.0.0.1:8731/src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua")

return "Splicer: " .. tostring(r1) .. ", MainUI: " .. tostring(r2)
"""

def main():
    print("Starting MCP server...")
    proc = subprocess.Popen(["cmd.exe", "/c", r"C:\Users\Kristina\AppData\Local\Roblox\mcp.bat"], 
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def send_req(req):
        req_str = json.dumps(req)
        proc.stdin.write(req_str + "\n")
        proc.stdin.flush()
        while True:
            line = proc.stdout.readline()
            if not line: return None
            line = line.strip()
            if not line: continue
            try:
                resp = json.loads(line)
                if "id" in resp and resp["id"] == req.get("id"):
                    return resp
            except:
                pass

    req_init = {
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}
    }
    print("Initializing...")
    res = send_req(req_init)
    
    proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    proc.stdin.flush()

    req_call = {
        "jsonrpc": "2.0", "id": 2, "method": "tools/call",
        "params": {"name": "execute_luau", "arguments": {"code": lua_code}}
    }
    
    print("Calling execute_luau...")
    res = send_req(req_call)
    print("Response:")
    print(json.dumps(res, indent=2))
    proc.kill()

if __name__ == "__main__":
    main()
