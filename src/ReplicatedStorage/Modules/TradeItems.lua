-- TradeItems -- what one line of a trade offer IS, defined once for both sides of the wire.
--
-- ===== WHY THIS IS A SHARED MODULE AND NOT TWO PRIVATE COPIES (30.7) =====
--
-- Until this file the offer was a list of pet id STRINGS, and both halves of trading knew that
-- shape by heart: `TradePanel` built `myOfferIds` as strings and `TradeService.SetOffer` read them
-- as strings. 30.7 makes an offer hold two different kinds of thing, so that shape becomes a small
-- grammar -- and a grammar written down twice is a grammar that drifts. The client deciding a relic
-- line looks like `{kind="relic", key=..., count=...}` while the server reads `n` is not a bug that
-- errors; it is a relic that silently never appears in the offer, on one side only.
--
-- So: one vocabulary, one normaliser, required by `TradeService` and by `TradePanel`.
--
-- ===== THE WIRE IS HOSTILE, SO `Normalise` IS A PARSER AND NOT A CONVERTER =====
--
-- Everything here runs against a table that came from a client, which means every field is a
-- suggestion. `Normalise` returns `nil, reason` for anything it cannot make sense of rather than
-- repairing it, because a repaired offer is an offer the player did not make -- and the one thing
-- a trade window must never do is put something in your side that you did not put there.
--
-- What it does NOT check is ownership: this module has no `data`. Whether you hold the pet, whether
-- the relic is a spare, whether it is away on an adventure -- all of that is the server's, and it
-- is re-checked at commit time as well. This layer only decides whether the message is well formed.
--
-- ===== A BARE STRING IS STILL A PET ID, AND THAT IS DELIBERATE =====
--
-- A player already in a trade window when the server updates is holding a `TradePanel` that sends
-- the old shape. Rejecting it would empty their offer mid-trade with no explanation. A string is
-- read as `{kind = "pet", id = it}`, which is exactly what it used to mean.

local TradeItems = {}

TradeItems.PET = "pet"
TradeItems.RELIC = "relic"

-- Ten LINES a side, not ten things: it is 8.5's reviewability limit, and a line reading "Forest
-- Shard x4" is one thing to read. The per-line count is capped separately, below.
TradeItems.MaxLines = 10
-- A stack big enough to be worth trading and small enough to still read on a 108 px card. Nobody
-- holds 100 spares of one collection relic without the drop rates being wrong.
TradeItems.MaxCount = 99

-- The identity of a LINE, for de-duplication. Two lines naming the same pet, or the same relic key,
-- are the same line -- offering a relic twice in two lines is how a client would try to move 2n
-- copies past a per-line cap.
function TradeItems.Key(item)
	if item.kind == TradeItems.RELIC then return "relic:" .. item.key end
	return "pet:" .. item.id
end

function TradeItems.IsPet(item) return item and item.kind == TradeItems.PET end
function TradeItems.IsRelic(item) return item and item.kind == TradeItems.RELIC end

-- Returns a canonical list, or nil plus the sentence the player is shown.
function TradeItems.Normalise(list)
	if type(list) ~= "table" then return nil, "Bad offer" end
	local out, seen = {}, {}
	for _, raw in ipairs(list) do
		local item
		if type(raw) == "string" then
			item = { kind = TradeItems.PET, id = raw }
		elseif type(raw) == "table" then
			if raw.kind == TradeItems.RELIC then
				if type(raw.key) ~= "string" then return nil, "Bad offer" end
				local n = math.floor(tonumber(raw.n) or 0)
				if n < 1 then return nil, "Bad offer" end
				if n > TradeItems.MaxCount then return nil, "That is too many of one relic" end
				item = { kind = TradeItems.RELIC, key = raw.key, n = n }
			elseif raw.kind == TradeItems.PET or raw.kind == nil then
				if type(raw.id) ~= "string" then return nil, "Bad offer" end
				item = { kind = TradeItems.PET, id = raw.id }
			else
				return nil, "Bad offer"
			end
		else
			return nil, "Bad offer"
		end

		local key = TradeItems.Key(item)
		if seen[key] then return nil, "The same thing twice" end
		seen[key] = true
		table.insert(out, item)
	end
	if #out > TradeItems.MaxLines then
		return nil, ("At most %d things each"):format(TradeItems.MaxLines)
	end
	return out
end

-- The pet ids in an offer, which is what the reservation table is keyed by. Kept here so no caller
-- has to filter the list itself and accidentally treat a relic line as a pet.
function TradeItems.PetIds(items)
	local ids = {}
	for _, item in ipairs(items or {}) do
		if item.kind == TradeItems.PET then table.insert(ids, item.id) end
	end
	return ids
end

return TradeItems
