-- Build: generators -> Econ -> Budget -> Rank, from a context. Pure (the UI supplies ctx).
-- ctx = {char, priceOf, now, standing, trustOf, deposit, scanAgeMin}
local _, ns = ...

function ns.BuildPlan(ctx, settings)
	settings = settings or {}
	local notes = {}
	local budget = ns.Budget.Compute(ctx.char and ctx.char.gold or 0, settings.budget)
	ctx.budget = budget
	local cands = ns.Gen.All(ctx, notes)
	local env = {
		cut = settings.cut or 0.05, horizonDays = settings.horizonDays or 3,
		realmShare = settings.realmShare or 1 / 3,
		char = ctx.char, standing = ctx.standing, trustOf = ctx.trustOf, deposit = ctx.deposit,
		scanAgeMin = ctx.scanAgeMin, now = ctx.now, stale = ctx.stale, fresh = ctx.fresh,
	}
	local evals = {}
	for _, c in ipairs(cands) do
		local ok, r = pcall(ns.Econ.Evaluate, c, ctx.priceOf, env)
		if ok then
			local L = ctx.learn and ctx.learn[c.kind]
			if r.ok and L and (L.weight or 0) > 0 and r.confidence then
				local ratio = math.max(0, math.min(L.realisedVsPredicted or 1, 1.5))
				r.confidence = math.min(1, r.confidence * (1 - L.weight + L.weight * ratio))
				r.learned = L
			end
			table.insert(evals, r)
		else
			table.insert(notes, "could not price " .. tostring(c.title) .. ": " .. tostring(r))
		end
	end
	local plan = ns.Rank.Plan(evals, budget, settings)
	plan.budget = budget
	if budget.gold < 20 * 10000 then
		table.insert(plan.notes, "Small budget: only safe, cheap tips are shown, and " .. ns.MoneyShort(budget.reserve) .. " is kept back.")
	end
	for _, n in ipairs(notes) do table.insert(plan.notes, n) end
	return plan
end
