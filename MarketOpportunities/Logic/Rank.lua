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

-- Spending is limited three ways: today's tips by the quick budget, raid stock and raid prep by
-- the raid budget (speculative stock also by the risk budget), and everything together by the
-- gold you have minus the reserve (review finding 5).
function R.Plan(evals, budget, settings)
	settings = settings or {}
	local plan = { today = {}, stock = {}, prep = {}, skip = {}, notes = {} }
	local session = settings.sessionMinutes or 60
	local pool, stockPool, prepPool = {}, {}, {}
	for _, e in ipairs(evals) do
		local kind = e.candidate.kind
		if not e.ok then
			skip(plan, e, e.reason or "not enough data")
		elseif kind == "raidPrep" then
			table.insert(prepPool, e) -- savings on the character's own raid needs, not profit
		elseif (e.net or 0) <= 0 then
			skip(plan, e, "not profitable")
		elseif (e.capital or 0) > budget.maxBet or (e.capital or 0) > budget.available then
			skip(plan, e, "over budget")
		else
			e.score = R.Score(e)
			table.insert(kind == "raidStock" and stockPool or pool, e)
		end
	end
	local function byScore(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return (a.roi or math.huge) > (b.roi or math.huge)
	end
	table.sort(pool, byScore)
	table.sort(stockPool, byScore)
	table.sort(prepPool, function(a, b) return (a.saving or a.net or 0) > (b.saving or b.net or 0) end)

	local total, spec = 0, 0 -- all sections together; speculative capital (today + stock)
	local minutes, spent = 0, 0
	for _, e in ipairs(pool) do
		local m, cap = e.candidate.handsOnMinutes or 0, e.capital or 0
		if #plan.today >= MAX_TODAY then
			skip(plan, e, "more than " .. MAX_TODAY .. " tips")
		elseif minutes + m > session then
			skip(plan, e, "doesn't fit this session")
		elseif spent + cap > budget.quick or total + cap > budget.available then
			skip(plan, e, "over budget")
		elseif e.returnClass == "speculative" and spec + cap > budget.speculative then
			skip(plan, e, "over risk budget")
		else
			minutes, spent, total = minutes + m, spent + cap, total + cap
			if e.returnClass == "speculative" then spec = spec + cap end
			table.insert(plan.today, e)
		end
	end
	local raid = 0 -- your own raid prep first, then stock to sell
	for _, e in ipairs(prepPool) do
		local cap = e.capital or 0
		if raid + cap > budget.raid then
			skip(plan, e, "over raid budget")
		elseif total + cap > budget.available then
			skip(plan, e, "over budget")
		else
			raid, total = raid + cap, total + cap
			table.insert(plan.prep, e)
		end
	end
	for _, e in ipairs(stockPool) do
		local cap = e.capital or 0
		if raid + cap > budget.raid then
			skip(plan, e, "over raid budget")
		elseif total + cap > budget.available then
			skip(plan, e, "over budget")
		elseif e.returnClass == "speculative" and spec + cap > budget.speculative then
			skip(plan, e, "over risk budget")
		else
			raid, total = raid + cap, total + cap
			if e.returnClass == "speculative" then spec = spec + cap end
			table.insert(plan.stock, e)
		end
	end
	plan.minutes, plan.spent, plan.raidSpent, plan.totalSpent = minutes, spent, raid, total
	return plan
end
