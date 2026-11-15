-- Scan: Auction House full scan (C_AuctionHouse.ReplicateItems) read in small time slices, plus a
-- targeted price refresh for single items. Read-only: never bids, buys, posts or cancels.
local _, ns = ...
local S = {}
ns.Scan = S

local COOLDOWN = 900 -- seconds between full scans (the server allows one every 15 minutes)
local CHECK_EVERY = 50 -- rows between clock checks
local HISTORY_CAP = 1500 -- items remembered per scan (besides the watch-list)

S.ahOpen = false
local reading -- { agg, i, total, startedAt }
local current -- last scan in memory: { summary, scannedAt, complete, rows, total }

function S.NextFullAt()
	local last = ns.db and ns.db.scanRequestedAt
	return last and last + COOLDOWN or 0
end

function S.Last()
	if current then return current end
	return ns.db and ns.db.scan or nil
end

function S.Progress()
	if not reading then return current and 1 or 0 end
	return reading.total > 0 and reading.i / reading.total or 0
end

function S.IsReading() return reading ~= nil end

local function watchSet()
	local w = {}
	for _, id in ipairs(ns.Data and ns.Data.Watch or {}) do w[id] = true end
	return w
end

-- Remember observed prices for the watch-list and the most valuable items with real listings
local function recordHistory(summary, t)
	ns.db.history = ns.db.history or {}
	local watch, pick = watchSet(), {}
	for id, s in pairs(summary) do
		if watch[id] then
			ns.History.Record(ns.db.history, id, "observed", s.min, t)
		elseif s.min and s.min >= 100 and s.listings >= 2 then
			pick[#pick + 1] = { id = id, v = s.min * math.min(s.totalQty, 20) }
		end
	end
	table.sort(pick, function(a, b) return a.v > b.v end)
	for i = 1, math.min(#pick, HISTORY_CAP) do
		ns.History.Record(ns.db.history, pick[i].id, "observed", summary[pick[i].id].min, t)
	end
end

-- What is saved between sessions: the summary for items we keep history for (not all 30k items)
local function trimmed(summary)
	local keep = {}
	for id in pairs(ns.db.history or {}) do
		if summary[id] then keep[id] = summary[id] end
	end
	for id in pairs(watchSet()) do
		if summary[id] then keep[id] = summary[id] end
	end
	return keep
end

-- After a complete scan: look for tips item by item, a few milliseconds per frame
local function discover(scan)
	local ids = {}
	for id, s in pairs(scan.summary) do
		if s.min and s.min > 0 then ids[#ids + 1] = id end
	end
	local char = ns.Char and ns.Char.Get() or {}
	local settings = ns.cdb and ns.cdb.settings or {}
	local budget = ns.Budget.Compute(char.gold or 0, settings.budget)
	local env = { realmShare = settings.realmShare or 1 / 3, horizonDays = 3, scannedAt = scan.scannedAt }
	local now = time()
	local function histOf(id) return ns.db.history and ns.History.Median(ns.db.history, id, 14, now) end
	local function priceOf(id) return ns.Prices.Get(id, true) end -- true: don't ask the server for 30k items
	local i, out = 1, {}
	ns.Run("discover", function(ms)
		local t0 = debugprofilestop()
		while i <= #ids do
			for _, c in ipairs(ns.Discover.FromScan(scan.summary, priceOf, histOf, budget, env, { ids[i] })) do
				out[#out + 1] = c
			end
			i = i + 1
			if i % 20 == 0 and debugprofilestop() - t0 >= ms then return false end
		end
		scan.candidates = out
		if ns.db.scan and ns.db.scan.scannedAt == scan.scannedAt then
			ns.db.scan.candidates = out
			for _, c in ipairs(out) do -- keep the summary of every item a tip is about
				if c.itemID and scan.summary[c.itemID] then ns.db.scan.summary[c.itemID] = scan.summary[c.itemID] end
			end
		end
		ns.Fire("DISCOVER_DONE", #out)
		return true
	end, 4)
end
S.Discover = discover

local function finish(complete)
	local r = reading
	reading = nil
	if not r then return true end
	local t = time()
	current = { summary = r.agg:Result(), scannedAt = t, complete = complete, rows = r.i, total = r.total }
	if complete then recordHistory(current.summary, t) end
	ns.db.scan = { summary = trimmed(current.summary), scannedAt = t, complete = complete, rows = r.i, total = r.total }
	if complete then
		ns.Print("Auction House read: " .. r.i .. " auctions.")
	else
		ns.Print("Auction House scan stopped at " .. r.i .. " of " .. r.total .. " auctions (incomplete).")
	end
	ns.Fire("SCAN_DONE", current)
	if complete then discover(current) end
	return true
end

local function step(budget)
	if not S.ahOpen then return finish(false) end
	local r = reading
	if not r then return true end
	local get = C_AuctionHouse.GetReplicateItemInfo
	local t0 = debugprofilestop()
	local n = 0
	while r.i < r.total do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = get(r.i)
		r.agg:Add(itemID, count, buyout)
		r.i = r.i + 1
		n = n + 1
		if n % CHECK_EVERY == 0 and debugprofilestop() - t0 >= budget then break end
	end
	ns.Fire("SCAN_PROGRESS", S.Progress())
	if r.i >= r.total then return finish(true) end
	return false
end

local waiting = false
function S.Full()
	if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetReplicateItemInfo) then
		ns.Print("this client has no Auction House scan.")
		return false
	end
	if not S.ahOpen then ns.Print("open the Auction House first."); return false end
	if reading or waiting then ns.Print("a scan is already running."); return false end
	local wait = S.NextFullAt() - time()
	if wait > 0 then
		ns.Print("the next full scan is allowed in " .. math.ceil(wait / 60) .. " min.")
		return false
	end
	ns.db.scanRequestedAt = time()
	waiting = true
	local ok, err = pcall(C_AuctionHouse.ReplicateItems)
	if not ok then waiting = false; ns.Print("scan request failed: " .. tostring(err)); return false end
	ns.Print("scan requested; the server is sending the auctions...")
	return true
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
	if not waiting then return end
	waiting = false
	local total = C_AuctionHouse.GetNumReplicateItems() or 0
	reading = { agg = ns.Discover.NewAggregator(), i = 0, total = total }
	ns.Run("scan", step, 4)
end)

ns.On("AUCTION_HOUSE_SHOW", function() S.ahOpen = true; ns.Fire("AH_STATE", true) end)
ns.On("AUCTION_HOUSE_CLOSED", function()
	S.ahOpen = false
	waiting = false
	ns.Fire("AH_STATE", false)
end)

------------------------------------------------------------------------
-- Targeted refresh: one search per item, one at a time, when the server is ready.
-- Commodities answer COMMODITY_SEARCH_RESULTS_UPDATED, other items ITEM_SEARCH_RESULTS_UPDATED.
------------------------------------------------------------------------
local queue, inflight = {}, nil

local function updateItem(itemID, units) -- units = {{u, q}}
	local agg = ns.Discover.NewAggregator()
	for _, x in ipairs(units) do agg:Add(itemID, x.q, x.u * x.q) end
	local s = agg:Result()[itemID]
	current = current or S.Last() or { summary = {}, scannedAt = 0, complete = false, rows = 0, total = 0 }
	current.summary = current.summary or {}
	current.summary[itemID] = s
	current.itemAt = current.itemAt or {}
	current.itemAt[itemID] = time()
	if s and s.min then
		ns.db.history = ns.db.history or {}
		ns.History.Record(ns.db.history, itemID, "observed", s.min, time())
	end
	ns.Fire("ITEM_REFRESHED", itemID, s)
end

local function sendNext()
	if inflight or #queue == 0 or not S.ahOpen then return end
	if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		C_Timer.After(0.3, sendNext)
		return
	end
	local id = table.remove(queue, 1)
	inflight = { id = id, at = GetTime() }
	local ok = pcall(function()
		local key = C_AuctionHouse.MakeItemKey(id)
		C_AuctionHouse.SendSearchQuery(key, { { sortOrder = 0, reverseSort = false } }, false)
	end)
	if not ok then inflight = nil; sendNext(); return end
	C_Timer.After(3, function() -- no answer: move on
		if inflight and inflight.id == id then inflight = nil; sendNext() end
	end)
end

function S.Refresh(itemIDs)
	if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then return false end
	if not S.ahOpen then ns.Print("open the Auction House first."); return false end
	for _, id in ipairs(itemIDs) do
		local dup = inflight and inflight.id == id
		for _, q in ipairs(queue) do if q == id then dup = true end end
		if not dup then queue[#queue + 1] = id end
	end
	sendNext()
	return true
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not (inflight and inflight.id == itemID) then return end
	local units = {}
	local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	for i = 1, math.min(n, 50) do
		local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if r and r.unitPrice and r.quantity then units[#units + 1] = { u = r.unitPrice, q = r.quantity } end
	end
	inflight = nil
	updateItem(itemID, units)
	sendNext()
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	local id = type(itemKey) == "table" and itemKey.itemID
	if not (inflight and inflight.id == id) then return end
	local units = {}
	local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
	for i = 1, math.min(n, 50) do
		local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if r and r.buyoutAmount and r.quantity and r.quantity > 0 then
			units[#units + 1] = { u = math.floor(r.buyoutAmount / r.quantity), q = r.quantity }
		end
	end
	inflight = nil
	updateItem(id, units)
	sendNext()
end)

-- Age of the price we have for an item, in minutes (nil when never seen)
function S.AgeMin(itemID)
	local s = S.Last()
	if not s then return nil end
	local t = (s.itemAt and s.itemAt[itemID]) or (s.summary and s.summary[itemID] and s.scannedAt)
	return t and math.floor((time() - t) / 60) or nil
end
