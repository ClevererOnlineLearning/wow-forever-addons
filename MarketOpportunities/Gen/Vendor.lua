-- Candidates found by the Auction House scan (below-vendor buys, flips, suspicious listings).
-- ctx.scan = {scannedAt, candidates} - the candidates are built after each scan in small slices.
local _, ns = ...
local MAX_AGE = 7200 -- scan candidates expire after 2 hours (spec §6a)

ns.Gen.Register("scan", function(ctx)
	local s = ctx.scan
	if not s or not s.scannedAt then return {}, "Scan the Auction House for more" end
	local now = ctx.now or 0
	if now - s.scannedAt > MAX_AGE then return {}, "Last scan is over 2 hours old: scan again for buy tips" end
	local out = {}
	for _, c in ipairs(s.candidates or {}) do
		if not c.expires or c.expires >= now then out[#out + 1] = c end
	end
	return out
end)

-- Vendor resale: things a vendor sells that the Auction House pays clearly more for.
-- Vendor prices come from vendors you've visited (ns.db.vendors) or, for the rest, from ItemTree's
-- public API when it is installed (used for the tip only, never stored as observed).
local itMemo = {} -- ItemTree answers per session (false = no vendor)
local function itemTreeVendorRaw(id)
	local API = ItemTreeAPI
	if not (API and API.IsReady and API.GetItemFacts) then return nil end
	local okReady, ready = pcall(API.IsReady)
	if not (okReady and ready) then return nil end
	local ok, facts = pcall(API.GetItemFacts, id)
	local v = ok and type(facts) == "table" and facts.vendors
	if type(v) == "table" and tonumber(v.buyPrice) and v.buyPrice > 0 and (v.count or 1) > 0 then
		return { price = v.buyPrice, limited = v.everywhere == false, source = "ItemTree" }
	end
	return nil
end
local function itemTreeVendor(id)
	if itMemo[id] == nil then
		local ok, ready = pcall(function() return ItemTreeAPI and ItemTreeAPI.IsReady() end)
		if not (ok and ready) then return nil end -- not ready yet: ask again next time
		itMemo[id] = itemTreeVendorRaw(id) or false
	end
	return itMemo[id] or nil
end

local function cautiousSale(p)
	if not p then return nil end
	local v = p.market and p.recent and math.min(p.market, p.recent) or p.market or p.recent
	if v and p.regionMarket then v = math.min(v, 1.5 * p.regionMarket) end
	if v and p.minBuyout then v = math.min(v, p.minBuyout) end
	return v
end

ns.Gen.Register("vendor", function(ctx)
	local out, seen = {}, {}
	local function consider(id, v, source)
		if seen[id] then return end
		seen[id] = true
		local p = ctx.priceOf(id)
		local sale = cautiousSale(p)
		local spd = p and p.regionSoldPerDay
		if not (sale and spd and spd >= 1) then return end
		if v.price * 1.10 >= sale * 0.95 then return end -- needs a clear margin after the 5% cut
		local demand = math.floor((ctx.realmShare or 1 / 3) * spd * 0.5 * 3)
		local maxBet = ctx.budget and ctx.budget.maxBet or 0
		local qty = math.min(demand, math.floor(maxBet / v.price))
		if v.limited and v.available then qty = math.min(qty, v.available) end
		if qty <= 0 then return end
		out[#out + 1] = {
			id = "vendor:" .. id, kind = "vendorFlip", itemID = id, title = "Vendor to AH",
			why = "A vendor sells it for " .. ns.Money(v.price) .. "; the Auction House pays about " .. ns.Money(math.floor(sale)) .. ".",
			inputs = { { itemID = id, qty = qty, from = "vendor", vendorPrice = v.price, limited = v.limited or nil } },
			outputs = { { itemID = id, qty = qty, sell = "ah" } },
			handsOnMinutes = 15, waitDays = 2,
			hint = v.npc and (v.npc .. (v.zone and (", " .. v.zone) or "")) or nil,
			source = source,
		}
	end
	for id, v in pairs(ns.db and ns.db.vendors or {}) do
		consider(id, v, "Vendor you visited")
	end
	-- ItemTree vendor prices for the watch-list and items we keep history for
	local ids = {}
	for _, id in ipairs(ns.Data.Watch or {}) do ids[#ids + 1] = id end
	for id in pairs(ns.db and ns.db.history or {}) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do
		if not seen[id] then
			local v = itemTreeVendor(id)
			if v then consider(id, v, "Vendor price from ItemTree (not visited yet)") end
		end
	end
	return out
end)
