-- Discover: Auction House scan aggregation, benchmarks and scan-based discovery rules (spec §6a, §19.1).
-- Pure: works on plain tables.
local _, ns = ...
local D = {}
ns.Discover = D

local MAX_LEVELS = 8 -- cheapest price levels kept per item (enough for "how many under X")

------------------------------------------------------------------------
-- Aggregator: one pass over auction rows -> per-item summary
------------------------------------------------------------------------
local Agg = {}
Agg.__index = Agg

function D.NewAggregator() return setmetatable({ items = {} }, Agg) end

function Agg:Add(itemID, count, buyout)
	if not itemID or not buyout or buyout <= 0 or not count or count <= 0 then return end
	local unit = math.floor(buyout / count)
	local s = self.items[itemID]
	if not s then
		s = { lows = {}, levels = {}, totalQty = 0, listings = 0 }
		self.items[itemID] = s
	end
	s.totalQty = s.totalQty + count
	s.listings = s.listings + 1
	-- three lowest listing unit prices
	local lows = s.lows
	if #lows < 3 or unit < lows[#lows] then
		local i = #lows + 1
		while i > 1 and lows[i - 1] > unit do lows[i] = lows[i - 1]; i = i - 1 end
		lows[i] = unit
		if #lows > 3 then lows[4] = nil end
	end
	-- cheapest price levels with quantities
	local lv = s.levels
	for _, l in ipairs(lv) do
		if l.u == unit then l.q = l.q + count; return end
	end
	if #lv < MAX_LEVELS or unit < lv[#lv].u then
		local i = #lv + 1
		while i > 1 and lv[i - 1].u > unit do lv[i] = lv[i - 1]; i = i - 1 end
		lv[i] = { u = unit, q = count }
		if #lv > MAX_LEVELS then lv[MAX_LEVELS + 1] = nil end
	end
end

function Agg:Result()
	local out = {}
	for id, s in pairs(self.items) do
		out[id] = {
			min = s.lows[1], second = s.lows[2], third = s.lows[3],
			qtyAtMin = s.levels[1] and s.levels[1].q or 0,
			totalQty = s.totalQty, listings = s.listings, levels = s.levels,
		}
	end
	return out
end

-- Units listed strictly below a unit price (from the kept price levels)
function D.QtyBelow(summary, price)
	local n = 0
	for _, l in ipairs(summary and summary.levels or {}) do
		if l.u < price then n = n + l.q end
	end
	return n
end
