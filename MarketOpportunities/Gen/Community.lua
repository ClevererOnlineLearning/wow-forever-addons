-- Community tips from the optional local research job (MarketOpportunities_Community, load on demand).
-- Every record is re-checked in game (ns.Community.Check) and shown as a community tip.
local _, ns = ...

local tried = false
local function load()
	if ns.Community.Data() or tried then return ns.Community.Data() end
	if InCombatLockdown and InCombatLockdown() then return nil end
	tried = true
	local A = C_AddOns
	if A and A.LoadAddOn then
		local exists = true
		if A.DoesAddOnExist then exists = select(2, pcall(A.DoesAddOnExist, "MarketOpportunities_Community")) end
		if exists then pcall(A.LoadAddOn, "MarketOpportunities_Community") end
	end
	return ns.Community.Data()
end

local function sitesOf(r)
	local names, seen = {}, {}
	for _, u in ipairs(r.sources or {}) do
		local s = ns.Community.Site(u)
		if not seen[s] then seen[s] = true; names[#names + 1] = s end
	end
	return table.concat(names, ", ")
end

ns.Gen.Register("community", function(ctx)
	local data = load()
	if not data then return {} end
	local out, skipped = {}, 0
	local seedNames = {}
	for _, q in ipairs(ns.Data.Quests or {}) do seedNames[q.name] = true end
	for _, o in pairs(ns.db and ns.db.quests or {}) do if o.name then seedNames[o.name] = true end end
	local nameOf = ctx.nameOf or function(id) return ns.Prices and ns.Prices.Name(id) end
	for _, r in ipairs(data.records) do
		if r.kind == "quest" and r.questName and seedNames[r.questName] then
			-- already a tip from the seed or your own hand-ins; Gen.Quests cites the community source
		else
			local ok, why = ns.Community.Check(r, ctx.char or {}, ctx.priceOf, nameOf, ctx.now or 0)
			if not ok then
				skipped = skipped + 1
			else
				local src = "Community tip (" .. sitesOf(r) .. ")"
				local unverified = { "community tip: check it in game first" }
				if r.conflict then unverified[#unverified + 1] = "sources disagree on the numbers" end
				local inputs = {}
				for _, i in ipairs(r.inputs or {}) do
					inputs[#inputs + 1] = { itemID = i.itemId, qty = i.qty, from = "ah",
						buyBelow = r.buyBelow and #r.inputs == 1 and r.buyBelow or nil }
				end
				if r.kind == "quest" then
					out[#out + 1] = {
						id = "community:quest:" .. r.questName, kind = "quest", questName = r.questName,
						title = "Hand in: " .. r.questName, why = r.summary, inputs = inputs, outputs = {},
						money = r.reward and r.reward.money or 0, handsOnMinutes = 10, waitDays = 0,
						requires = { level = r.minLevel, faction = r.faction ~= "both" and r.faction or nil },
						-- a community reward is never a sure payout until you've seen it yourself (spec 7.1)
						unverified = unverified, payoutVerified = false,
						source = src,
					}
				else
					local unit = r.buyBelow or (ctx.priceOf(r.itemId) or {}).minBuyout
					local qty = 1
					if unit and unit > 0 and ctx.budget then qty = math.max(1, math.min(10, math.floor((ctx.budget.maxBet or 0) / unit))) end
					if r.kind ~= "farm" and #inputs == 0 then
						inputs = { { itemID = r.itemId, qty = qty, from = "ah", buyBelow = r.buyBelow } }
					end
					out[#out + 1] = {
						id = "community:" .. r.kind .. ":" .. r.itemId, kind = "community", itemID = r.itemId,
						title = "Community tip", why = r.summary, inputs = inputs,
						outputs = { { itemID = r.itemId, qty = qty, sell = "ah", price = r.sellAbove } },
						handsOnMinutes = r.kind == "farm" and (ctx.sessionMinutes or 60) or 15, waitDays = 2,
						speculative = true, unverified = unverified, source = src,
					}
				end
			end
		end
	end
	local note
	if data.meta and data.meta.date then
		note = "Community tips from " .. data.meta.date .. ": " .. #out .. " passed the in-game checks" ..
			(skipped > 0 and (", " .. skipped .. " didn't") or "") .. "."
	end
	return out, note
end)
