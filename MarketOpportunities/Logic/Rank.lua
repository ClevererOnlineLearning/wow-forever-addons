-- Rank: turns Evaluations into Tonight's plan (spec §7.4). Pure.
local _, ns = ...
local R = {}
ns.Rank = R

local MAX_TODAY = 8

function R.Score(e)
	local c = e.candidate
	local hours = math.max((c.handsOnMinutes or 0) / 60, 0.1)
	return (e.net or 0) * (e.confidence or 0) / hours - (e.capital or 0) * (c.waitDays or 0) * 0.01
end

local function skip(plan, e, why)
	e.skipReason = why
	table.insert(plan.skip, e)
end

function R.Plan(evals, budget, settings)
	settings = settings or {}
	local plan = { today = {}, stock = {}, prep = {}, skip = {}, notes = {} }
	local session = settings.sessionMinutes or 60
	local pool = {}
	for _, e in ipairs(evals) do
		local kind = e.candidate.kind
		if not e.ok then
			skip(plan, e, e.reason or "not enough data")
		elseif kind == "raidPrep" then
			table.insert(plan.prep, e) -- savings on the character's own raid needs, not profit
		elseif (e.net or 0) <= 0 then
			skip(plan, e, "not profitable")
		elseif (e.capital or 0) > budget.maxBet or (e.capital or 0) > budget.available then
			skip(plan, e, "over budget")
		elseif kind == "raidStock" then
			table.insert(plan.stock, e)
		else
			e.score = R.Score(e)
			table.insert(pool, e)
		end
	end
	table.sort(pool, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return (a.roi or math.huge) > (b.roi or math.huge)
	end)
	local minutes, spent, spec = 0, 0, 0
	for _, e in ipairs(pool) do
		local m, cap = e.candidate.handsOnMinutes or 0, e.capital or 0
		if #plan.today >= MAX_TODAY then
			skip(plan, e, "more than " .. MAX_TODAY .. " tips")
		elseif minutes + m > session then
			skip(plan, e, "doesn't fit this session")
		elseif spent + cap > budget.quick then
			skip(plan, e, "over budget")
		elseif e.returnClass == "speculative" and spec + cap > budget.speculative then
			skip(plan, e, "over risk budget")
		else
			minutes, spent = minutes + m, spent + cap
			if e.returnClass == "speculative" then spec = spec + cap end
			table.insert(plan.today, e)
		end
	end
	plan.minutes, plan.spent = minutes, spent
	return plan
end
