-- History: compact per-item price history and freshness (spec §9). Pure.
-- store[itemID] = { pts = {{t, k, v}}, weekly = {{w, min, med, max}}, ref = {day, v},
--                   last = {[kind] = v}, seen = {[kind] = t}, changed = {[kind] = t}, used = t }
local _, ns = ...
local H = {}
ns.History = H

local DAY, WEEK = 86400, 7 * 86400
local KEEP_DAYS, KEEP_WEEKS, MAX_ITEMS = 30, 26, 2000
local TSM_KINDS = { tsmMarket = true, tsmMinBuyout = true, tsmRecent = true, tsmNumAuctions = true }
local PRICE_KINDS = { observed = true, tsmMarket = true, tsmRecent = true } -- kinds that describe a price level

local function median(list)
	if #list == 0 then return nil end
	table.sort(list)
	local n = #list
	if n % 2 == 1 then return list[(n + 1) / 2] end
	return math.floor((list[n / 2] + list[n / 2 + 1]) / 2)
end
H.MedianOf = median

local function item(store, id, t)
	local s = store[id]
	if not s then
		s = { pts = {}, weekly = {}, last = {}, seen = {}, changed = {} }
		store[id] = s
	end
	s.used = math.max(s.used or 0, t or 0)
	return s
end

function H.Record(store, itemID, kind, value, t)
	if value == nil or itemID == nil then return end
	local s = item(store, itemID, t)
	if kind == "tsmHistorical" then
		local day = math.floor(t / DAY)
		if not s.ref or s.ref.day ~= day then s.ref = { day = day, v = value } end
		return
	end
	if TSM_KINDS[kind] then
		s.seen[kind] = t
		if s.last[kind] == value then return end
		s.last[kind] = value
		s.changed[kind] = t
	end
	table.insert(s.pts, { t = t, k = kind, v = value })
end

function H.Reference(store, itemID)
	local s = store[itemID]
	return s and s.ref and s.ref.v or nil
end

function H.Compact(store, now)
	local cutoff, weekCut = now - KEEP_DAYS * DAY, now - KEEP_WEEKS * WEEK
	local ids = {}
	for id, s in pairs(store) do
		local keep, old = {}, {}
		for _, p in ipairs(s.pts) do
			if p.t >= cutoff then table.insert(keep, p) elseif p.t >= weekCut and PRICE_KINDS[p.k] then
				local w = math.floor(p.t / WEEK)
				old[w] = old[w] or {}
				table.insert(old[w], p.v)
			end
		end
		s.pts = keep
		for w, vals in pairs(old) do
			local lo, hi = math.huge, -math.huge
			for _, v in ipairs(vals) do lo, hi = math.min(lo, v), math.max(hi, v) end
			local merged = false
			for _, x in ipairs(s.weekly) do
				if x.w == w then x.min, x.max = math.min(x.min, lo), math.max(x.max, hi); merged = true end
			end
			if not merged then table.insert(s.weekly, { w = w, min = lo, med = median(vals), max = hi }) end
		end
		local wk = {}
		for _, x in ipairs(s.weekly) do if x.w * WEEK + WEEK >= weekCut then table.insert(wk, x) end end
		table.sort(wk, function(a, b) return a.w > b.w end)
		s.weekly = wk
		if #s.pts == 0 and #s.weekly == 0 and not s.ref then store[id] = nil else table.insert(ids, id) end
	end
	if #ids > MAX_ITEMS then
		table.sort(ids, function(a, b) return (store[a].used or 0) < (store[b].used or 0) end)
		for i = 1, #ids - MAX_ITEMS do store[ids[i]] = nil end
	end
end

local function values(s, from, to)
	local out, days, kinds, own = {}, {}, {}, 0
	for _, p in ipairs(s.pts) do
		if PRICE_KINDS[p.k] and p.t >= from and p.t <= to then
			table.insert(out, p.v)
			days[math.floor(p.t / DAY)] = true
			kinds[p.k] = true
			if p.k == "observed" then own = own + 1 end
		end
	end
	local nd, nk = 0, 0
	for _ in pairs(days) do nd = nd + 1 end
	for _ in pairs(kinds) do nk = nk + 1 end
	return out, nd, nk, own
end

-- Median price over the last `days` days; nil with fewer than 3 points
function H.Median(store, itemID, days, now)
	local s = store[itemID]
	if not s then return nil end
	local v = values(s, now - days * DAY, now)
	if #v < 3 then return nil end
	return median(v)
end

-- Median of this add-on's own observations only (spec §19.1 "own" group): at least 3 points on at
-- least 2 separate days; points taken at excludeT (the scan being judged) are left out.
function H.OwnMedian(store, itemID, days, now, excludeT)
	local s = store[itemID]
	if not s then return nil end
	local vals, seenDays, nd = {}, {}, 0
	for _, p in ipairs(s.pts) do
		if p.k == "observed" and p.t >= now - days * DAY and p.t ~= excludeT then
			vals[#vals + 1] = p.v
			local d = math.floor(p.t / DAY)
			if not seenDays[d] then seenDays[d] = true; nd = nd + 1 end
		end
	end
	if #vals < 3 or nd < 2 then return nil end
	return median(vals)
end

-- A price move worth acting on: recent (3 days) vs the 14-day baseline before it
function H.Move(store, itemID, now, thin)
	local s = store[itemID]
	local first = math.huge
	if s then for _, p in ipairs(s.pts) do if PRICE_KINDS[p.k] then first = math.min(first, p.t) end end end
	local span = s and first < math.huge and math.floor((now - first) / DAY) or 0
	if span < 7 then return { meaningful = false, note = "not enough history", days = span } end
	local recent, nd, nk, own = values(s, now - 3 * DAY + 1, now)
	local base = values(s, now - 14 * DAY, now - 3 * DAY)
	local cur, b = median(recent), median(base)
	if not cur or not b or b == 0 then return { meaningful = false, note = "not enough history", days = span } end
	local pct = (cur - b) / b
	local evidence = nd >= 2 and (nk >= 2 or own >= 3)
	return { pct = pct, days = span, meaningful = (not thin) and evidence and math.abs(pct) >= 0.25 }
end

-- TSM is stale when every watched item it was asked about recently has not changed for > 2 days
function H.TsmStale(store, watch, now)
	local any = false
	for _, id in ipairs(watch) do
		local s = store[id]
		local seen, changed = s and s.seen.tsmMarket, s and s.changed.tsmMarket
		if seen and now - seen < DAY then
			any = true
			if now - (changed or 0) <= 2 * DAY then return false end
		end
	end
	return any
end
