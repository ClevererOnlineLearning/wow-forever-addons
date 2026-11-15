-- Budget: how much of the character's gold the plan may use (spec §2 defaults, all overridable).
local _, ns = ...
local B = {}
ns.Budget = B

local G = 10000

function B.Compute(gold, settings)
	settings = settings or {}
	gold = math.max(gold or 0, 0)
	local b = {}
	b.reserve = settings.reserve or math.floor(math.max(0.175 * gold, math.min(5 * G, 0.5 * gold)))
	b.available = math.max(gold - b.reserve, 0)
	b.quick = settings.quick or math.floor(0.625 * b.available)
	b.raid = settings.raid or math.floor(0.375 * b.available)
	b.maxBet = math.min(settings.maxBet or math.floor(0.26 * gold), b.available)
	-- under 20g there is no room for risk: guesses are hidden (spec §17, 10g character)
	local spec = gold < 20 * G and 0 or math.floor(math.min(10 * G, 0.10 * gold))
	b.speculative = math.min(settings.speculative or spec, b.available)
	b.gold = gold
	return b
end
