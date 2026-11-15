-- Econ: prices one candidate into an Evaluation (spec §7 with the §19 corrections).
-- Pure: no WoW globals. Money is integer copper.
local _, ns = ...
local E = {}
ns.Econ = E

local NO_EVIDENCE_TRUST = 0.5 -- region figures only, nothing of our own yet (spec §19.2)

local function floor(x) return math.floor(x + 1e-9) end

local function fromList(f)
	if type(f) == "table" then return f end
	return { f or "ah" }
end

-- Requirements the character must meet; returns reason or nil, plus checks for what can't be read
local function checkRequires(req, env, checks)
	if not req then return nil end
	local char = env.char or {}
	if req.level and char.level and char.level < req.level then return "needs level " .. req.level end
	if req.faction and char.faction and char.faction ~= req.faction then return req.faction .. " only" end
	if req.profession then
		local p = char.professions and char.professions[req.profession.id]
		if not p or (req.profession.rank and (p.rank or 0) < req.profession.rank) then
			return "needs " .. (req.profession.name or "profession") .. " " .. (req.profession.rank or "")
		end
	end
	if req.rep then
		local label = req.rep.name .. " below " .. req.rep.rank
		local standing = env.standing and env.standing(req.rep.factionID)
		if standing == nil then
			checks[#checks + 1] = label
		elseif standing >= req.rep.below then
			return "needs " .. label
		end
	end
	return nil
end

-- A cautious realm sale price (spec §7.2)
local function salePrice(out, p)
	if out.price then return out.price end
	if not p then return nil end
	local v
	if p.market and p.recent then v = math.min(p.market, p.recent) else v = p.market or p.recent end
	if not v then return nil end
	if p.regionMarket then v = math.min(v, 1.5 * p.regionMarket) end
	if p.minBuyout then v = math.min(v, p.minBuyout) end
	return floor(v)
end

function E.Evaluate(c, priceOf, env)
	local r = { candidate = c, ok = true, checks = {} }
	local cut = env.cut or 0.05
	if c.blocked then r.ok, r.reason = false, c.blocked; return r end
	local reason = checkRequires(c.requires, env, r.checks)
	if reason then r.ok, r.reason = false, reason; return r end

	-- inputs
	local cost, capital, stale = 0, 0, false
	for _, inp in ipairs(c.inputs or {}) do
		local p = priceOf(inp.itemID)
		if p and p.stale then stale = true end
		local best, bestFrom
		for _, from in ipairs(fromList(inp.from)) do
			local u
			if from == "ah" then u = inp.unitPrice or (p and p.minBuyout)
			elseif from == "vendor" then u = inp.vendorPrice
			elseif from == "owned" then u = p and (salePrice({}, p) and floor(salePrice({}, p) * (1 - cut)) or p.vendorSell)
			end
			if u and (not best or u < best) then best, bestFrom = u, from end
		end
		if not best then r.ok, r.reason = false, "not enough data"; return r end
		cost = cost + best * inp.qty
		if bestFrom ~= "owned" then capital = capital + best * inp.qty end
		if bestFrom == "ah" then
			local chk = "listing still at this price"
			if env.scanAgeMin and env.scanAgeMin > 15 then chk = chk .. " (scan is " .. floor(env.scanAgeMin) .. " min old)" end
			local dup = false
			for _, x in ipairs(r.checks) do if x == chk then dup = true end end
			if not dup then r.checks[#r.checks + 1] = chk end
		elseif bestFrom == "vendor" and inp.limited then
			r.checks[#r.checks + 1] = "vendor stock"
		end
	end
	for _, u in ipairs(c.unverified or {}) do r.checks[#r.checks + 1] = u end

	-- outputs
	local sure = c.money or 0 -- deterministic money (quest gold, vendor sales)
	local ahHigh, ahLow, ahSales = 0, 0, false
	local thin, pSell, trust = false, nil, nil
	local depositEstimated = false
	for _, out in ipairs(c.outputs or {}) do
		local p = priceOf(out.itemID)
		if p and p.stale then stale = true end
		if out.sell == "vendor" then
			if not (p and p.vendorSell) then r.ok, r.reason = false, "not enough data"; return r end
			sure = sure + p.vendorSell * out.qty
		else
			ahSales = true
			local price = salePrice(out, p)
			if not price then r.ok, r.reason = false, "not enough data"; return r end
			local spd = p and p.regionSoldPerDay
			trust = env.trustOf and env.trustOf(out.itemID) or NO_EVIDENCE_TRUST
			if not spd or spd < 1 or not (p.numAuctions and p.numAuctions >= 3) or out.thin then thin = true end
			if trust <= NO_EVIDENCE_TRUST and (not spd or spd < 2) then thin = true end
			local ps = ((p and p.regionSaleRate) or 0) * trust
			if spd and spd < 2 then ps = ps * spd / 2 end
			pSell = pSell and math.min(pSell, ps) or ps
			local demand = (env.realmShare or 1 / 3) * (spd or 0) * trust * (env.horizonDays or 3)
			local units = math.min(out.qty, floor(demand))
			local dep = env.deposit and env.deposit(out.itemID, out.qty)
			local each = price * (1 - cut)
			ahHigh = ahHigh + floor(each * out.qty) - (dep or 0)
			if dep then
				ahLow = ahLow + floor(each * units) - dep
			else
				depositEstimated = true -- one relist at 5% of sale value
				ahLow = ahLow + floor(each * units) - floor(0.05 * price * out.qty)
			end
		end
	end

	r.capital, r.cost = capital, cost
	r.netHigh = sure + ahHigh - cost
	r.netLow = sure + ahLow - cost
	r.net = r.netLow
	r.thin, r.staleData, r.pSell, r.trust = thin, stale, pSell, trust
	if depositEstimated then r.reason = "deposit estimated" end

	if not ahSales then
		r.returnClass = (c.payoutVerified == false or c.speculative) and "speculative" or "guaranteed"
	elseif thin or c.speculative then
		r.returnClass = "speculative"
	else
		r.returnClass = "expected"
	end

	if r.returnClass == "guaranteed" then
		r.confidence = #r.checks > 0 and 0.85 or 1.0
	elseif r.returnClass == "expected" then
		r.confidence = (trust or 0) <= NO_EVIDENCE_TRUST and math.min(pSell or 0, 0.6) or (pSell or 0)
	else
		r.confidence = 0.25
	end
	r.perHour = r.net / math.max((c.handsOnMinutes or 0) / 60, 0.1)
	r.roi = capital > 0 and r.net / capital or nil
	return r
end
