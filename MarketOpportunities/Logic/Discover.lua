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

local function entry(s)
	return {
		min = s.lows[1], second = s.lows[2], third = s.lows[3],
		qtyAtMin = s.levels[1] and s.levels[1].q or 0,
		totalQty = s.totalQty, listings = s.listings, levels = s.levels,
	}
end

function Agg:Result()
	local out = {}
	for id, s in pairs(self.items) do out[id] = entry(s) end
	return out
end

-- The same, a few items at a time: call until it returns true (out is filled in place)
function Agg:ResultStep(out, n)
	local k = self.cursor
	for _ = 1, n do
		local s
		k, s = next(self.items, k)
		if k == nil then self.cursor = nil; return true end
		out[k] = entry(s)
	end
	self.cursor = k
	return false
end

-- Units listed strictly below a unit price (from the kept price levels)
function D.QtyBelow(summary, price)
	local n = 0
	for _, l in ipairs(summary and summary.levels or {}) do
		if l.u < price then n = n + l.q end
	end
	return n
end

------------------------------------------------------------------------
-- Benchmark (spec §19.1): related values form one group; only independent groups confirm.
--   tsmRealm  = TSM Market / Recent / Historical (one realm data feed)
--   tsmRegion = TSM Region Market (other realms: related, not this market)
--   local     = Auctionator price and our own observed median (both from this player's scans)
------------------------------------------------------------------------
local function med(list)
	if #list == 0 then return nil end
	table.sort(list)
	local n = #list
	if n % 2 == 1 then return list[(n + 1) / 2] end
	return math.floor((list[n / 2] + list[n / 2 + 1]) / 2)
end

function D.Benchmark(price, histMedian)
	price = price or {}
	local realm = {}
	if price.market and not price.marketFromAtr then realm[#realm + 1] = price.market end
	if price.recent then realm[#realm + 1] = price.recent end
	if price.historical then realm[#realm + 1] = price.historical end
	local loc = {}
	if price.atrPrice then loc[#loc + 1] = price.atrPrice end
	if histMedian then loc[#loc + 1] = histMedian end
	local groups, anyLocal = {}, false
	local r, l = med(realm), med(loc)
	if r then groups[#groups + 1] = r; anyLocal = true end
	if price.regionMarket then groups[#groups + 1] = price.regionMarket end
	if l then groups[#groups + 1] = l; anyLocal = true end
	if #groups == 0 then return nil, false, 0 end
	local lo, hi = math.huge, 0
	for _, v in ipairs(groups) do lo, hi = math.min(lo, v), math.max(hi, v) end
	local value = med({ unpack(groups) })
	local credible = #groups >= 2 and anyLocal and lo > 0 and hi / lo <= 1.3
	return value, credible, #groups
end

-- Cost of buying the cheapest qty units from the kept price levels
function D.CostOf(summary, qty)
	local left, cost = qty, 0
	for _, l in ipairs(summary.levels or {}) do
		local take = math.min(left, l.q)
		cost = cost + take * l.u
		left = left - take
		if left <= 0 then break end
	end
	return cost, qty - left
end

-- First kept price level at or above a unit price (the competition after buying the cheap ones)
local function nextLevelAt(summary, price)
	for _, l in ipairs(summary.levels or {}) do
		if l.u >= price then return l.u end
	end
	return nil
end

------------------------------------------------------------------------
-- Scan rules (spec §6a): below-vendor buys, undervalued flips, suspicious listings.
-- env = {realmShare, horizonDays, scannedAt, trustOf}
------------------------------------------------------------------------
local function evaluateItem(id, s, p, hist, budget, env, out)
	if not s.min then return end
	local expires = (env.scannedAt or 0) + 7200
	local maxQty = s.min > 0 and math.floor((budget.maxBet or 0) / s.min) or 0
	-- 1. below vendor price: a sure payout at any vendor
	if p and p.vendorSell and s.min < p.vendorSell - 1 then
		local qty = math.min(ns.Discover.QtyBelow(s, p.vendorSell - 1), maxQty)
		if qty > 0 then
			local cost = D.CostOf(s, qty)
			out[#out + 1] = {
				id = "scan:bv:" .. id, kind = "belowVendor", itemID = id,
				title = "Buy and vendor", why = "Listed below what a vendor pays for it.",
				inputs = { { itemID = id, qty = qty, from = "ah", unitPrice = math.ceil(cost / qty), buyBelow = p.vendorSell - 1 } },
				outputs = { { itemID = id, qty = qty, sell = "vendor" } },
				handsOnMinutes = 5, waitDays = 0, expires = expires, source = "Your Auction House scan",
			}
			return
		end
	end
	if not p then return end
	local value, credible = D.Benchmark(p, hist)
	if not value then return end
	local spd = p.regionSoldPerDay
	-- 2. suspicious: one cheap listing far under the benchmark on a slow item (bait or mistake)
	if s.qtyAtMin == 1 and s.second and s.min < 0.5 * s.second and s.min < 0.3 * value and (not spd or spd < 1) then
		out[#out + 1] = {
			id = "scan:sus:" .. id, kind = "flip", itemID = id, hint = "suspicious",
			blocked = "suspicious single cheap listing (possible bait)",
			title = "Cheap listing", inputs = { { itemID = id, qty = 1, from = "ah", unitPrice = s.min } },
			outputs = {}, handsOnMinutes = 5, waitDays = 0, expires = expires, source = "Your Auction House scan",
		}
		return
	end
	-- 3. undervalued flip: needs a credible benchmark and demand data
	if not credible or not spd or spd < 1 then return end
	if s.min > value * 0.80 then return end
	if s.second and s.min < 0.5 * s.second and s.qtyAtMin == 1 then return end -- odd single listing
	local trust = env.trustOf and env.trustOf(id) or 0.5
	local demand = math.floor((env.realmShare or 1 / 3) * spd * trust * (env.horizonDays or 3))
	local threshold = math.floor(value * 0.80)
	local qty = math.min(D.QtyBelow(s, threshold + 1), demand, maxQty)
	if qty <= 0 then return end
	local cost = D.CostOf(s, qty)
	local competitor = nextLevelAt(s, threshold + 1)
	local sale = math.min(value, competitor and (competitor - 1) or value)
	out[#out + 1] = {
		id = "scan:flip:" .. id, kind = "flip", itemID = id,
		title = "Flip", why = "Listed at least 20% under a price two independent sources agree on.",
		inputs = { { itemID = id, qty = qty, from = "ah", unitPrice = math.ceil(cost / qty), buyBelow = threshold } },
		outputs = { { itemID = id, qty = qty, sell = "ah", price = sale } },
		handsOnMinutes = 10, waitDays = math.max(1, math.ceil(qty / math.max(demand / (env.horizonDays or 3), 1))),
		expires = expires, source = "Your Auction House scan",
	}
end

function D.FromScan(summary, priceOf, histMedianOf, budget, env, ids)
	local out = {}
	if ids then
		for _, id in ipairs(ids) do
			local s = summary[id]
			if s then evaluateItem(id, s, priceOf(id), histMedianOf and histMedianOf(id), budget, env, out) end
		end
	else
		for id, s in pairs(summary) do
			evaluateItem(id, s, priceOf(id), histMedianOf and histMedianOf(id), budget, env, out)
		end
	end
	return out
end

------------------------------------------------------------------------
-- TopK: keeps the k highest-scoring items, a min-heap, so big lists never need one large sort
------------------------------------------------------------------------
local Top = {}
Top.__index = Top

function D.TopK(k) return setmetatable({ k = k, h = {} }, Top) end

function Top:Push(item, score)
	local h = self.h
	if #h < self.k then
		h[#h + 1] = { item, score }
		local i = #h
		while i > 1 do
			local p = math.floor(i / 2)
			if h[p][2] <= h[i][2] then break end
			h[p], h[i] = h[i], h[p]
			i = p
		end
	elseif score > h[1][2] then
		h[1] = { item, score }
		local i, n = 1, #h
		while true do
			local l, r, m = 2 * i, 2 * i + 1, i
			if l <= n and h[l][2] < h[m][2] then m = l end
			if r <= n and h[r][2] < h[m][2] then m = r end
			if m == i then break end
			h[m], h[i] = h[i], h[m]
			i = m
		end
	end
end

-- best first (sorting at most k items)
function Top:Items()
	local copy = {}
	for i, x in ipairs(self.h) do copy[i] = x end
	table.sort(copy, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i, x in ipairs(copy) do out[i] = x[1] end
	return out
end

-- A rough margin for ordering tips before Econ prices them properly
function D.Margin(c)
	local inp, out = c.inputs and c.inputs[1], c.outputs and c.outputs[1]
	if not inp then return 0 end
	local unit = inp.unitPrice or 0
	local sell = (out and out.price) or inp.buyBelow or unit
	return (sell - unit) * (inp.qty or 1)
end
