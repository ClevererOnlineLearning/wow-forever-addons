-- Recipes: every profession's recipes, found once per client build and cached (spec §8, §19.5).
-- Two paths: the open profession window (C_TradeSkillUI.GetAllRecipeIDs), and a background walk
-- over the spell ID ranges where recipes live. The walk is benchmarked first, uses at most 2 ms a
-- frame, pauses in combat, resumes from a saved cursor and can be stopped.
local _, ns = ...
local R = {}
ns.Recipes = R

R.RANGES = { { 1, 60000 }, { 1000000, 1500000 } }
R.BUDGET_MS = 2
R.MAX_BACKGROUND_SECONDS = 600
local CHECK_EVERY = 20
local FRAME_MS = 16.7 -- a typical frame: background time = CPU time x frame / budget

local function build()
	local ok, _, b = pcall(GetBuildInfo)
	return ok and tostring(b) or "?"
end

local function cache()
	local b = build()
	local db = ns.db
	if not db.recipes or db.recipes.build ~= b then
		db.recipes = { build = b, list = {}, complete = false }
		db.recipeWalk = nil
	end
	return db.recipes
end

local function totalIds()
	local n = 0
	for _, r in ipairs(R.RANGES) do n = n + (r[2] - r[1] + 1) end
	return n
end

-- One recipe's facts. Reagent field names are read two ways (schematic slot or its first reagent).
local function read(id, line, parent)
	local rec = { line = line, parent = parent, reagents = {} }
	local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
	if ok and type(sch) == "table" then
		rec.name, rec.out, rec.qMin, rec.qMax = sch.name, sch.outputItemID, sch.quantityMin, sch.quantityMax
		for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
			local first = slot.reagents and slot.reagents[1]
			local itemID = first and first.itemID or slot.itemID
			local qty = slot.quantityRequired or (first and first.quantityRequired)
			if itemID and qty then rec.reagents[#rec.reagents + 1] = { itemID = itemID, qty = qty } end
		end
	end
	return rec
end

local function add(id)
	local ok, line, _, parent = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, id)
	if not (ok and line) then return false end
	cache().list[id] = read(id, line, parent or line)
	return true
end

function R.Get(id) return ns.db and ns.db.recipes and ns.db.recipes.list[id] or nil end

function R.For(parent)
	local out = {}
	for id, r in pairs(ns.db and ns.db.recipes and ns.db.recipes.list or {}) do
		if r.parent == parent then out[#out + 1] = id end
	end
	table.sort(out)
	return out
end

function R.Coverage(parent)
	local found, withReagents, withSkillReq = 0, 0, 0
	for _, id in ipairs(R.For(parent)) do
		found = found + 1
		local r = R.Get(id)
		if r.reagents and #r.reagents > 0 then withReagents = withReagents + 1 end
		local sk = ns.db.skill and ns.db.skill[id]
		if sk and sk.req then withSkillReq = withSkillReq + 1 end
	end
	return { found = found, withReagents = withReagents, withSkillReq = withSkillReq,
		complete = ns.db.recipes and ns.db.recipes.complete or false,
		walkSkipped = ns.db.recipes and ns.db.recipes.walkSkipped or false }
end

-- The open profession window lists its recipes directly (the primary path)
function R.FromTradeSkill()
	if not (ns.db and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return 0 end
	local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
	if not ok or type(ids) ~= "table" then return 0 end
	local n = 0
	for _, id in ipairs(ids) do
		if not cache().list[id] and add(id) then n = n + 1 end
	end
	if n > 0 then ns.Fire("RECIPES_CHANGED") end
	return n
end
ns.On("TRADE_SKILL_SHOW", function() C_Timer.After(0.5, R.FromTradeSkill) end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() R.FromTradeSkill() end)

-- Background walk: starts, or carries on from the saved cursor; nothing to do once complete
function R.Walk()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe) then return false end
	local c = cache()
	if c.complete then return false end
	local w = ns.db.recipeWalk
	if not w or w.build ~= c.build then
		w = { build = c.build, range = 1, cursor = R.RANGES[1][1] }
		ns.db.recipeWalk = w
	end
	ns.Run("recipes", function(ms)
		local t0, n = debugprofilestop(), 0
		while w.range <= #R.RANGES do
			local r = R.RANGES[w.range]
			if w.cursor > r[2] then
				w.range = w.range + 1
				w.cursor = R.RANGES[w.range] and R.RANGES[w.range][1] or 0
			else
				add(w.cursor)
				w.cursor = w.cursor + 1
				n = n + 1
				if n % CHECK_EVERY == 0 and debugprofilestop() - t0 >= ms then return false end
			end
		end
		c.complete = true
		ns.db.recipeWalk = nil
		ns.Fire("RECIPES_CHANGED")
		return true
	end, R.BUDGET_MS)
	return true
end

-- Settings "Rebuild": forget this build's recipes and search again
function R.Rebuild()
	R.Stop()
	ns.db.recipes, ns.db.recipeWalk = nil, nil
	cache()
	return R.Walk()
end

function R.Stop()
	ns.Cancel("recipes")
	ns.Cancel("recipeBench")
end

-- Times the lookup over up to n IDs (or 50 ms of CPU), in 2 ms slices; done({usPerId, projectedSeconds})
function R.Bench(n, done)
	n = n or 10000
	local id, spent, count = 1, 0, 0
	ns.Run("recipeBench", function(ms)
		local t0 = debugprofilestop()
		while count < n and spent < 50 do
			pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, id)
			id, count = id + 1, count + 1
			local el = debugprofilestop() - t0
			if el >= ms then spent = spent + el; return false end
		end
		spent = spent + (debugprofilestop() - t0)
		local us = count > 0 and spent * 1000 / count or 0
		local cpu = us * totalIds() / 1e6
		local res = { usPerId = us, ids = count, projectedSeconds = cpu * FRAME_MS / R.BUDGET_MS }
		if ns.db then ns.db.recipeBench = res end
		if done then done(res) end
		return true
	end, R.BUDGET_MS)
end

-- At login: nothing if this build is cached; else benchmark, then walk if it's affordable
function R.Auto()
	if not ns.db or InCombatLockdown() then return end
	local c = cache()
	if c.complete or c.walkSkipped then return end
	R.Bench(10000, function(b)
		if b.projectedSeconds > R.MAX_BACKGROUND_SECONDS then
			c.walkSkipped = true
			ns.Print(("recipe search skipped (it would take about %d min); open each profession window instead."):format(math.ceil(b.projectedSeconds / 60)))
		else
			R.Walk()
		end
	end)
end
ns.On("PLAYER_LOGIN", function() C_Timer.After(20, R.Auto) end)
