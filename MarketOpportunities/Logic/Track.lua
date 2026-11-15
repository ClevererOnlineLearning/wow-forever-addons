-- Track: follow a tip you accepted to a real result (spec §11, §19.6). Pure.
-- A result is "realised" only for units whose purchase cost is known AND whose sale is matched;
-- anything that can't be reconciled is "unconfirmed" and shows no profit.
local _, ns = ...
local T = {}
ns.Track = T

local DAY = 86400
local WINDOW = 14 * DAY

-- names: itemID -> item name (sale invoices give names only)
function T.Accept(eval, totals, now, names)
	local c = eval.candidate
	local items, preOwned = {}, {}
	for _, list in ipairs({ c.inputs or {}, c.outputs or {} }) do
		for _, x in ipairs(list) do
			items[x.itemID] = names and names[x.itemID] or items[x.itemID] or true
			preOwned[x.itemID] = totals and totals[x.itemID] or 0
		end
	end
	return {
		id = c.id, kind = c.kind, title = c.title, questName = c.questName, sellYours = c.sellYours,
		items = items, preOwned = preOwned, acceptedAt = now, expiresAt = now + WINDOW,
		predicted = { net = eval.net, netLow = eval.netLow, netHigh = eval.netHigh, capital = eval.capital },
		units = {}, sales = {}, money = 0, state = "open",
	}
end

-- Called only for a purchase the adapter could match (unitCost nil = matched item, unknown cost)
function T.OnAcquired(r, itemID, qty, unitCost, t)
	if not r.items[itemID] or qty <= 0 then return false end
	if unitCost == nil then r.unknownCost = true end
	table.insert(r.units, { itemID = itemID, qty = qty, left = qty, cost = unitCost, t = t })
	return true
end

local function itemFor(r, inv)
	if inv.itemID and r.items[inv.itemID] then return inv.itemID end
	for id, name in pairs(r.items) do
		if type(name) == "string" and name == inv.itemName then return id end
	end
	return nil
end

-- A sale invoice {itemName, itemID?, qty, amount (after the cut), t}; true if it belongs to this tip
function T.OnSold(r, inv)
	if r.abandoned or not inv.t or inv.t < r.acceptedAt or inv.t > r.expiresAt then return false end
	local id = itemFor(r, inv)
	if not id then return false end
	local avail = 0
	for _, u in ipairs(r.units) do if u.itemID == id then avail = avail + u.left end end
	if avail == 0 and not r.sellYours then return false end -- from units you already owned
	if inv.qty > avail then
		r.ambiguous = true -- more sold than this tip bought: can't tell which units these were
		table.insert(r.sales, { itemID = id, qty = inv.qty, amount = inv.amount, t = inv.t })
		return true
	end
	local left, cost = inv.qty, 0
	for _, u in ipairs(r.units) do -- first in, first out
		if u.itemID == id and u.left > 0 and left > 0 then
			local take = math.min(u.left, left)
			u.left, left = u.left - take, left - take
			if u.cost then cost = cost + take * u.cost else r.unknownCost = true end
		end
	end
	table.insert(r.sales, { itemID = id, qty = inv.qty, amount = inv.amount, cost = cost, t = inv.t })
	return true
end

function T.OnQuestReward(r, questName, money, t)
	if r.kind ~= "quest" or r.abandoned or not r.questName or r.questName ~= questName then return false end
	if t < r.acceptedAt or t > r.expiresAt then return false end
	r.money = (r.money or 0) + money
	r.questDone = (r.questDone or 0) + 1
	return true
end

function T.Abandon(r) r.abandoned = true end

local function totals(r)
	local bought, sold, cost, proceeds = 0, 0, 0, 0
	for _, u in ipairs(r.units) do bought = bought + u.qty; cost = cost + (u.cost or 0) * u.qty end
	for _, s in ipairs(r.sales) do sold = sold + s.qty; proceeds = proceeds + (s.amount or 0) end
	return bought, sold, cost, proceeds
end

function T.State(r, now)
	if r.abandoned then return "abandoned" end
	if r.ambiguous or (r.unknownCost and (#r.sales > 0 or (r.questDone or 0) > 0)) then return "unconfirmed" end
	local bought, sold = totals(r)
	if r.kind == "quest" then
		if (r.questDone or 0) > 0 then return "realised" end
	elseif sold > 0 then
		return sold >= bought and "realised" or "partial"
	end
	if now > r.expiresAt then return "expired" end
	return "open"
end

-- {profit, sold, bought} for matched units only; nil when unconfirmed or nothing happened yet
function T.Result(r)
	if r.abandoned or r.ambiguous or r.unknownCost then return nil end
	local bought, sold, _, proceeds = totals(r)
	if r.kind == "quest" then
		if (r.questDone or 0) == 0 then return nil end
		local _, _, cost = totals(r)
		return { profit = r.money - cost, sold = 0, bought = bought }
	end
	if sold == 0 then return nil end
	local matchedCost = 0
	for _, s in ipairs(r.sales) do matchedCost = matchedCost + (s.cost or 0) end
	return { profit = proceeds - matchedCost, sold = sold, bought = bought }
end

-- What past results say per kind of tip; weight = n/(n+3), used only from 3 results on
function T.Learn(records, now)
	local by = {}
	for _, r in ipairs(records) do
		local st = T.State(r, now)
		local res = (st == "realised" or st == "partial") and T.Result(r)
		if res then
			local k = by[r.kind] or { n = 0, ratio = 0, days = 0, through = 0 }
			k.n = k.n + 1
			local pred = r.predicted and r.predicted.net
			if pred and pred ~= 0 then k.ratio = k.ratio + res.profit / pred end
			local last = r.sales[#r.sales]
			if last then k.days = k.days + (last.t - r.acceptedAt) / DAY end
			if res.bought > 0 then k.through = k.through + math.min(res.sold / res.bought, 1) end
			by[r.kind] = k
		end
	end
	local out = {}
	for kind, k in pairs(by) do
		out[kind] = {
			n = k.n, realisedVsPredicted = k.ratio / k.n, daysToSell = k.days / k.n, sellThrough = k.through / k.n,
			weight = k.n >= 3 and k.n / (k.n + 3) or 0,
		}
	end
	return out
end

-- Region-liquidity trust for an item from your own realised sales (spec §19.2)
function T.TrustOf(records, itemID)
	local n = 0
	for _, r in ipairs(records) do
		if not (r.ambiguous or r.unknownCost) then
			for _, s in ipairs(r.sales) do if s.itemID == itemID then n = n + 1 end end
		end
	end
	return 0.5 + 0.5 * n / (n + 5)
end

-- Savings goal: how far, and how many sessions like your last ones (3 needed)
function T.Goal(goal, gold, sessions)
	local remaining = math.max((goal or 0) - (gold or 0), 0)
	local out = { remaining = remaining }
	if #sessions < 3 then return out end
	local delta, hours = 0, 0
	for _, s in ipairs(sessions) do delta, hours = delta + s.delta, hours + s.hours end
	out.goldPerHour = hours > 0 and math.floor(delta / hours) or nil
	local per = delta / #sessions
	if remaining == 0 then out.sessionsLeft = 0 elseif per > 0 then out.sessionsLeft = math.ceil(remaining / per) end
	return out
end
