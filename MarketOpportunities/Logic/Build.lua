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
		scanAgeMin = ctx.scanAgeMin, now = ctx.now, stale = ctx.stale,
	}
	local evals = {}
	for _, c in ipairs(cands) do
		local ok, r = pcall(ns.Econ.Evaluate, c, ctx.priceOf, env)
		if ok then
			table.insert(evals, r)
		else
			table.insert(notes, "could not price " .. tostring(c.title) .. ": " .. tostring(r))
		end
	end
	local plan = ns.Rank.Plan(evals, budget, settings)
	plan.budget = budget
	for _, n in ipairs(notes) do table.insert(plan.notes, n) end
	return plan
end
