-- Community: re-checks a tip from the local research job against the game before it is shown.
-- The job already validated it; in game we check what only the client knows. Pure.
local _, ns = ...
local C = {}
ns.Community = C

local SITES = {
	["reddit.com"] = "Reddit", ["conquestcapped.com"] = "ConquestCapped", ["icy-veins.com"] = "Icy Veins",
	["bindonforever.com"] = "BindOnForever", ["foreverchanges.pro"] = "ForeverChanges", ["wclbox.com"] = "WCLBox",
	["wowhead.com"] = "Wowhead",
}

function C.Site(url)
	local host = tostring(url or ""):match("^%a+://([^/:]+)") or ""
	host = host:lower()
	for dom, name in pairs(SITES) do
		if host == dom or host:sub(-(#dom + 1)) == "." .. dom then return name end
	end
	return "community"
end

local function day(s)
	local y, m, d = tostring(s or ""):match("^(%d+)-(%d+)-(%d+)")
	if not y then return nil end
	return ns.Data.DaysFromCivil(tonumber(y), tonumber(m), tonumber(d))
end

-- ok, reason. nameOf(itemID) is the client's name (nil until cached).
function C.Check(r, char, priceOf, nameOf, now)
	local exp = day(r.expires)
	if not exp or exp < math.floor(now / 86400) then return false, "expired" end
	local name = nameOf(r.itemId)
	if name == nil then return false, "item not loaded yet" end
	if name ~= r.itemName then return false, "item name doesn't match the game (" .. tostring(name) .. ")" end
	if r.faction and r.faction ~= "both" and char.faction and r.faction ~= char.faction then return false, r.faction .. " only" end
	if r.minLevel and char.level and char.level < r.minLevel then return false, "needs level " .. r.minLevel end
	if r.maxLevel and char.level and char.level > r.maxLevel then return false, "for level " .. r.maxLevel .. " and below" end
	if r.buyBelow then
		local id = (r.inputs and r.inputs[1] and r.inputs[1].itemId) or r.itemId
		local p = priceOf(id)
		local now_ = p and (p.minBuyout or p.market)
		if now_ and now_ > r.buyBelow then return false, "price now above " .. ns.Money(r.buyBelow) end
	end
	return true, nil
end

function C.Data()
	local d = MarketOpportunities_CommunityData
	if type(d) == "table" and type(d.records) == "table" then return d end
	return nil
end

-- Quest names the community file mentions (so seed tips can cite it instead of duplicating it)
function C.QuestSources()
	local out = {}
	for _, r in ipairs(C.Data() and C.Data().records or {}) do
		if r.kind == "quest" and r.questName then
			out[r.questName] = out[r.questName] or {}
			for _, u in ipairs(r.sources or {}) do table.insert(out[r.questName], C.Site(u)) end
		end
	end
	return out
end
