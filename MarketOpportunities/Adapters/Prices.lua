-- Prices: TSM first, Auctionator per item and per field when TSM has nothing usable (spec §19.4).
-- Only the public APIs are called; every call is wrapped in pcall. Copper integers or nil.
local _, ns = ...
local P = {}
ns.Prices = P

local CALLER = "MarketOpportunities"
local STALE_DAYS = 3 -- Auctionator data at least this old is marked stale

local function usable(v) -- nil, 0, negative and non-numbers are unusable
	v = tonumber(v)
	if v and v > 0 then return v end
	return nil
end

local function tsm(src, itemString)
	if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
	local ok, v = pcall(TSM_API.GetCustomPriceValue, src, itemString)
	if not ok then return nil end
	return usable(v)
end

local function atr(fn, id)
	local A = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (A and A[fn]) then return nil end
	local ok, v = pcall(A[fn], CALLER, id)
	if not ok then return nil end
	return tonumber(v)
end

local function vendorSellOf(id, noRequest)
	if not (C_Item and C_Item.GetItemInfo) then return nil end
	local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, id)
	if ok and name then return tonumber(sell) end
	if not noRequest and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	return nil
end

-- What the last few lookups used, for the status line
local recent = {}
local function remember(r)
	table.insert(recent, r)
	if #recent > 5 then table.remove(recent, 1) end
end

function P.Get(itemID, noRequest)
	local s = "i:" .. itemID
	local p = { tsmInstalled = TSM_API ~= nil }
	local tsmUsed = false
	if TSM_API then
		p.market = tsm("DBMarket", s)
		p.minBuyout = tsm("DBMinBuyout", s)
		p.recent = tsm("DBRecent", s)
		p.historical = tsm("DBHistorical", s)
		p.numAuctions = tsm("DBNumAuctions", s)
		p.regionMarket = tsm("DBRegionMarketAvg", s)
		local spd = tsm("DBRegionSoldPerDay*1000", s)
		p.regionSoldPerDay = spd and spd / 1000 or tsm("DBRegionSoldPerDay", s)
		local rate = tsm("DBRegionSaleRate*1000", s)
		p.regionSaleRate = rate and rate / 1000 or tsm("DBRegionSaleRate", s)
		for _, k in ipairs({ "market", "minBuyout", "recent", "historical", "numAuctions", "regionMarket", "regionSoldPerDay", "regionSaleRate" }) do
			if p[k] then tsmUsed = true end
		end
	end
	p.atrPrice = usable(atr("GetAuctionPriceByItemID", itemID))
	p.atrAgeDays = p.atrPrice and atr("GetAuctionAgeByItemID", itemID) or nil

	local atrUsed = false
	if p.atrPrice and not (p.market or p.minBuyout) then
		-- Auctionator's price is its last-seen lowest buyout: it stands in for both
		p.market, p.minBuyout = p.atrPrice, p.atrPrice
		p.marketFromAtr = true -- so the benchmark doesn't count Auctionator twice
		atrUsed = true
		if p.atrAgeDays and p.atrAgeDays >= STALE_DAYS then p.stale = true end
	end
	if atrUsed then
		p.source = tsmUsed and "TSM+Auctionator" or "Auctionator"
	elseif tsmUsed then
		p.source = "TSM"
	end

	p.vendorSell = vendorSellOf(itemID, noRequest) or (TSM_API and tsm("VendorSell", s)) or nil

	remember({ tsm = tsmUsed and (p.market or p.minBuyout) ~= nil and not atrUsed, atr = atrUsed, source = p.source, age = atrUsed and p.atrAgeDays or nil })
	if not p.source and not p.vendorSell then return nil end
	return p
end

function P.Status()
	local tsmInstalled = TSM_API ~= nil
	local atrInstalled = Auctionator and Auctionator.API and Auctionator.API.v1 and true or false
	if not tsmInstalled and not atrInstalled then
		return { note = "No TSM or Auctionator prices" }
	end
	if #recent == 0 then return { source = tsmInstalled and "TSM" or "Auctionator" } end
	local anyTsm, anyAtr, anySource, maxAge = false, false, false, nil
	for _, r in ipairs(recent) do
		if r.tsm then anyTsm = true end
		if r.atr then anyAtr = true end
		if r.source then anySource = true end
		if r.age and (not maxAge or r.age > maxAge) then maxAge = r.age end
	end
	if not anySource then return { note = "No TSM or Auctionator prices" } end
	local source = anyTsm and (anyAtr and "TSM+Auctionator" or "TSM") or "Auctionator"
	if tsmInstalled and not anyTsm and anyAtr then
		return { source = source, note = "TSM is installed but has no prices yet — using Auctionator" }
	end
	if anyAtr and maxAge and maxAge >= STALE_DAYS then
		return { source = source, note = "Auctionator prices are " .. maxAge .. " days old" }
	end
	return { source = source }
end

-- Item names for the UI (nil until the client has the item cached)
function P.Name(itemID)
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, itemID)
		if ok and n then return n end
	end
	if C_Item and C_Item.GetItemInfo then
		local ok, n = pcall(C_Item.GetItemInfo, itemID)
		if ok and n then return n end
		if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
	end
	return nil
end

ns.On("ITEM_DATA_LOAD_RESULT", function(itemID, success)
	if success ~= false then ns.Fire("ITEM_READY", itemID) end
end)
