-- Path: the cheapest known way to level a profession, and the milestones worth reaching (spec §8).
-- Pure: recipes come in as spell IDs, skillOf(id) gives the Skill record, priceOf(itemID) prices.
local _, ns = ...
local P = {}
ns.Path = P

P.CHANCE = { orange = 1.0, yellow = 0.75, green = 0.25, grey = 0 }

local function colourAt(sk, point)
	if not sk.req or point < sk.req then return nil end
	if sk.yellow and point < sk.yellow then return "orange" end
	if sk.green and point < sk.green then return "yellow" end
	if sk.grey and point < sk.grey then return "green" end
	if not sk.yellow then return "orange" end
	return "grey"
end
P.ColourAt = colourAt

local function unitCost(priceOf, itemID)
	local p = priceOf(itemID)
	if not p then return nil end
	return p.minBuyout or p.market
end

-- Materials for one craft (nil if any reagent has no price: never treated as free)
local function matsOf(r, priceOf)
	local cost = 0
	for _, g in ipairs(r.reagents or {}) do
		local u = unitCost(priceOf, g.itemID)
		if not u then return nil end
		cost = cost + u * g.qty
	end
	return cost
end

local function resaleOf(r, priceOf)
	local p = r.out and priceOf(r.out)
	if not (p and p.regionSaleRate and p.regionSoldPerDay and p.regionSoldPerDay >= 1) then return 0 end
	local sale = p.market and p.recent and math.min(p.market, p.recent) or p.market or p.recent or 0
	if p.minBuyout then sale = math.min(sale, p.minBuyout) end
	return math.floor(sale * 0.95 * (r.qMin or 1) * p.regionSaleRate * 0.5)
end

local function verified(sk)
	return sk.reqSource ~= "bundled-estimate" and sk.reqSource ~= "missing" and sk.thresholdSource == "client"
end

function P.Plan(profID, rank, target, recipes, skillOf, priceOf, env)
	env = env or {}
	local chances = env.chances or P.CHANCE
	local cov = { found = 0, verified = 0, estimated = 0, missing = 0 }
	local usable = {}
	for _, id in ipairs(recipes) do
		local sk = skillOf(id) or { reqSource = "missing" }
		local r = ns.Recipes and ns.Recipes.Get(id)
		cov.found = cov.found + 1
		if sk.reqSource == "missing" or not sk.req then
			cov.missing = cov.missing + 1
		else
			if verified(sk) then cov.verified = cov.verified + 1 else cov.estimated = cov.estimated + 1 end
			if r then
				local mats = matsOf(r, priceOf)
				if mats then usable[#usable + 1] = { id = id, sk = sk, net = mats - resaleOf(r, priceOf) } end
			end
		end
	end
	local steps, total, gaps = {}, 0, 0
	for point = rank, target - 1 do
		local best, bestCost
		for _, u in ipairs(usable) do
			local c = colourAt(u.sk, point)
			local ch = c and chances[c] or 0
			if ch > 0 then
				local per = math.max(u.net, 0) / ch
				if not bestCost or per < bestCost then best, bestCost = u, per end
			end
		end
		if best then
			local last = steps[#steps]
			local crafts = 1 / (chances[colourAt(best.sk, point)])
			if last and last.spellID == best.id then
				last.to, last.crafts, last.cost = point + 1, last.crafts + crafts, last.cost + bestCost
			else
				steps[#steps + 1] = { spellID = best.id, from = point, to = point + 1, crafts = crafts, cost = bestCost }
			end
			total = total + bestCost
		else
			gaps = gaps + 1
		end
	end
	for _, s in ipairs(steps) do s.crafts, s.cost = math.ceil(s.crafts - 1e-9), math.floor(s.cost + 0.5) end
	local label = (cov.estimated == 0 and cov.missing == 0 and gaps == 0) and "cheapest path" or "cheapest known path"
	return { steps = steps, total = math.floor(total + 0.5), coverage = cov, label = label, gaps = gaps }
end

-- Next skill levels worth reaching: profitable recipes, cooldowns, gathering, bundled notes
function P.Milestones(profID, rank, recipes, skillOf, priceOf, env)
	local out, byRank = {}, {}
	local function add(r, text)
		if r <= rank then return end
		if byRank[r] then byRank[r].text = byRank[r].text .. "; " .. text; return end
		byRank[r] = { rank = r, text = text }
		out[#out + 1] = byRank[r]
	end
	for _, id in ipairs(recipes) do
		local sk = skillOf(id)
		local r = ns.Recipes and ns.Recipes.Get(id)
		if sk and sk.req and r and r.out then
			local mats = matsOf(r, priceOf)
			local p = priceOf(r.out)
			local sale = p and (p.market and p.recent and math.min(p.market, p.recent) or p.market or p.recent)
			if mats and sale and p.regionSoldPerDay and p.regionSoldPerDay >= 1 then
				local net = math.floor(sale * 0.95 * (r.qMin or 1)) - mats
				if net > 0 then add(sk.req, (r.name or ("recipe " .. id)) .. " (+" .. ns.Money(net) .. " a craft)") end
			end
		end
	end
	for _, c in ipairs(ns.Data.Cooldowns or {}) do
		if c.profession == profID then add(c.minSkill, c.name .. " cooldown") end
	end
	for _, g in ipairs(ns.Data.Gathering or {}) do
		if g.profession == profID then add(g.minSkill, g.name .. ": " .. g.zones) end
	end
	for _, m in ipairs(ns.Data.Milestones and ns.Data.Milestones[profID] or {}) do add(m.rank, m.note) end
	table.sort(out, function(a, b) return a.rank < b.rank end)
	while #out > 3 do table.remove(out) end
	return out
end
