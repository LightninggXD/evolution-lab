-- Push the two ahead-on-disk files into Studio, EDIT mode only.
-- Proves what it overwrites (Studio must still match the 2026-08-13 recorded hash),
-- then writes, then verifies byte-identity with the same rolling hash python used.
local HttpService = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")

local function roll(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end

local FILES = {
	{
		inst = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("HatchReveal"),
		url  = "http://127.0.0.1:8731/src/StarterPlayer/StarterPlayerScripts/HatchReveal.client.lua",
		wasLen = 48310,  wasHash = 169269412,   -- Studio, re-verified 2026-08-13 (fifth) on the CLOUD place
		-- Was 52,514/909702846 when this script was staged in the third session. The FOURTH session
		-- closed 11.19 with another 20 lines in this file (commit 5b0d983), so the target moved.
		wantLen = 54074, wantHash = 648462907,  -- src/ on disk now
	},
	{
		inst = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("MainUI"),
		url  = "http://127.0.0.1:8731/src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua",
		wasLen = 378671,  wasHash = 120848007,
		wantLen = 380324, wantHash = 144286258,
	},
}

local out = {}
for _, f in ipairs(FILES) do
	local name = f.inst and f.inst.Name or "?MISSING?"
	if not f.inst then
		table.insert(out, name .. " NOT FOUND")
	else
		local before = f.inst.Source
		local bl, bh = #before, roll(before)
		local drifted = (bl ~= f.wasLen or bh ~= f.wasHash)
		if drifted and not (bl == f.wantLen and bh == f.wantHash) then
			table.insert(out, ("%s DRIFT before=%d/%d expected=%d/%d -- NOT WRITTEN")
				:format(name, bl, bh, f.wasLen, f.wasHash))
		elseif bl == f.wantLen and bh == f.wantHash then
			table.insert(out, name .. " already identical to src/, skipped")
		else
			local src = HttpService:GetAsync(f.url)
			SES:UpdateSourceAsync(f.inst, function() return src end)
			local after = f.inst.Source
			local al, ah = #after, roll(after)
			table.insert(out, ("%s %s after=%d/%d want=%d/%d")
				:format(name, (al == f.wantLen and ah == f.wantHash) and "OK" or "MISMATCH",
				al, ah, f.wantLen, f.wantHash))
		end
	end
end
return table.concat(out, "\n")
