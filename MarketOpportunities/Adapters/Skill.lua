-- Skill: recipe skill requirements and difficulty thresholds, each with where it came from.
-- ns.db.skill[spellID] = {req, reqSource, yellow, green, grey, thresholdSource, learned, colour, colourAt}
-- Priority: trainer > tooltip > bundled-estimate for the requirement; client > bundled-estimate for thresholds.
local _, ns = ...
local K = {}
ns.Skill = K

local REQ_RANK = { trainer = 3, tooltip = 2, ["bundled-estimate"] = 1 }
local COLOURS = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
local PREFIXES = { "Pattern: ", "Plans: ", "Recipe: ", "Formula: ", "Schematic: ", "Design: ", "Manual: " }

local function store()
	ns.db.skill = ns.db.skill or {}
	return ns.db.skill
end

function K.ParseRequires(text)
	local prof, rank = tostring(text or ""):match("^Requires ([%a%s']+) %((%d+)%)")
	if not prof then return nil end
	return prof, tonumber(rank)
end

function K.Record(spellID, f)
	local s = store()
	local r = s[spellID] or {}
	if f.req and (not r.req or (REQ_RANK[f.reqSource] or 0) >= (REQ_RANK[r.reqSource] or 0)) then
		r.req, r.reqSource = f.req, f.reqSource
	end
	if f.yellow and (f.thresholdSource == "client" or r.thresholdSource ~= "client") then
		r.yellow, r.green, r.grey, r.thresholdSource = f.yellow, f.green, f.grey, f.thresholdSource
	end
	if f.colour then r.colour, r.colourAt, r.learned = f.colour, f.colourAt, f.learned end
	s[spellID] = r
end

function K.Get(spellID)
	local r = ns.db and ns.db.skill and ns.db.skill[spellID] or {}
	local est = ns.Data.SkillEstimates and ns.Data.SkillEstimates[spellID]
	local out = { learned = r.learned, colour = r.colour, colourAt = r.colourAt }
	if r.req then
		out.req, out.reqSource = r.req, r.reqSource
	elseif est and est.req then
		out.req, out.reqSource = est.req, "bundled-estimate"
	else
		out.reqSource = "missing"
	end
	if r.yellow and r.thresholdSource == "client" then
		out.yellow, out.green, out.grey, out.thresholdSource = r.yellow, r.green, r.grey, "client"
	elseif out.req then
		local st = ns.Data.THRESHOLD_STEPS or { 15, 30, 45 }
		out.yellow = (est and est.yellow) or out.req + st[1]
		out.green = (est and est.green) or out.req + st[2]
		out.grey = (est and est.grey) or out.req + st[3]
		out.thresholdSource = "bundled-estimate"
	end
	return out
end

local function recipeBy(test)
	for id, r in pairs(ns.db.recipes and ns.db.recipes.list or {}) do
		if test(r) then return id, r end
	end
end

-- Trainer window: requirement per service, matched by the crafted item, else by name
local function scanTrainer()
	if not ns.db then return end
	local n = (type(GetNumTrainerServices) == "function" and select(2, pcall(GetNumTrainerServices))) or 0
	for i = 1, tonumber(n) or 0 do
		local okL, link = pcall(GetTrainerServiceItemLink, i)
		local itemID = okL and link and tonumber(link:match("item:(%d+)"))
		local okN, name = pcall(GetTrainerServiceInfo, i)
		local id = itemID and recipeBy(function(r) return r.out == itemID end)
		if not id and okN and name then id = recipeBy(function(r) return r.name == name end) end
		local okR, _, rank = pcall(GetTrainerServiceSkillReq, i)
		if id and okR and tonumber(rank) and rank > 0 then K.Record(id, { req = rank, reqSource = "trainer" }) end
	end
end
ns.On("TRAINER_SHOW", function() C_Timer.After(0, scanTrainer) end)
ns.On("TRAINER_UPDATE", function() C_Timer.After(0, scanTrainer) end)

-- A recipe item's tooltip ("Pattern: X" ... "Requires Leatherworking (225)")
function K.FromRecipeItem(itemName, lines)
	if not (ns.db and itemName) then return end
	local name = itemName
	for _, p in ipairs(PREFIXES) do
		if name:sub(1, #p) == p then name = name:sub(#p + 1) break end
	end
	local id = recipeBy(function(r) return r.name == name end)
	if not id then return end
	for _, l in ipairs(lines) do
		local prof, rank = K.ParseRequires(l)
		if prof then K.Record(id, { req = rank, reqSource = "tooltip" }) return end
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
		if not (ns.db and tt and tt.GetName and data and data.id) then return end
		local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, data.id)
		if not (ok and classID == 9) then return end -- recipe items only
		local lines, name = {}, tt:GetName()
		for i = 1, math.min(tt:NumLines() or 0, 20) do
			local fs = _G[name .. "TextLeft" .. i]
			local t = fs and fs:GetText()
			if t then lines[#lines + 1] = t end
		end
		pcall(K.FromRecipeItem, lines[1], lines)
	end)
end

-- The open profession window: colours of learned recipes at the current rank
function K.FromTradeSkillWindow(rank)
	if not (ns.db and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
	local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
	if not ok or type(ids) ~= "table" then return end
	if not rank then
		local okB, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
		rank = okB and info and info.skillLevel
	end
	for _, id in ipairs(ids) do
		local okI, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
		if okI and info and info.learned and COLOURS[info.relativeDifficulty] then
			K.Record(id, { colour = COLOURS[info.relativeDifficulty], colourAt = rank, learned = true })
		end
	end
end
ns.On("TRADE_SKILL_LIST_UPDATE", function() pcall(K.FromTradeSkillWindow) end)
