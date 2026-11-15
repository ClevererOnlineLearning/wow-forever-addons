-- Profession tips: profitable crafts you know, cooldowns that are ready, gathering worth doing.
-- Also the per-profession block the plan window shows (path, milestones, coverage).
local _, ns = ...

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2)
end

local function skillOf(id) return ns.Skill and ns.Skill.Get(id) end

-- Known recipes that make money: learned (seen in the profession window) and profitable
ns.Gen.Register("crafts", function(ctx)
	local out = {}
	for profID, prof in pairs(ctx.char and ctx.char.professions or {}) do
		for _, id in ipairs(ns.Recipes and ns.Recipes.For(profID) or {}) do
			local sk, r = skillOf(id), ns.Recipes.Get(id)
			if sk and sk.learned and r and r.out and r.reagents and #r.reagents > 0 then
				local inputs = {}
				for _, g in ipairs(r.reagents) do inputs[#inputs + 1] = { itemID = g.itemID, qty = g.qty, from = { "ah", "vendor" },
					vendorPrice = ns.db and ns.db.vendors and ns.db.vendors[g.itemID] and ns.db.vendors[g.itemID].price } end
				local p = ctx.priceOf(r.out)
				if p and p.market and p.regionSoldPerDay and p.regionSoldPerDay >= 1 then
					out[#out + 1] = {
						id = "craft:" .. id, kind = "craft", itemID = r.out, title = "Craft " .. (r.name or ("recipe " .. id)),
						why = prof.name .. " recipe you know; sells on the Auction House.",
						inputs = inputs, outputs = { { itemID = r.out, qty = r.qMin or 1, sell = "ah" } },
						handsOnMinutes = 10, waitDays = 2, source = "Your recipes",
					}
				end
			end
		end
	end
	return out
end)

-- Cooldowns: a tool in your bags (or a known spell) whose cooldown is over
local announced = {}
local function ready(c)
	local now = call(GetTime) or 0
	if c.item then
		if (call(GetItemCount, c.item) or 0) <= 0 then return false end
		local start, dur = call(C_Container and C_Container.GetItemCooldown, c.item)
		return start ~= nil and (start == 0 or start + (dur or 0) <= now)
	end
	if c.spell then
		if not call(IsSpellKnown, c.spell) then return false end
		local cd = call(C_Spell and C_Spell.GetSpellCooldown, c.spell)
		return type(cd) == "table" and (cd.startTime == 0 or cd.startTime + cd.duration <= now)
	end
	return false
end

ns.Gen.Register("cooldowns", function(ctx)
	local out = {}
	for _, c in ipairs(ns.Data.Cooldowns or {}) do
		local prof = ctx.char and ctx.char.professions and ctx.char.professions[c.profession]
		if prof and (prof.rank or 0) >= (c.minSkill or 0) and ready(c) then
			local inputs = {}
			for _, u in ipairs(c.uses or {}) do inputs[#inputs + 1] = { itemID = u.itemID, qty = u.qty, from = "ah" } end
			out[#out + 1] = {
				id = "cooldown:" .. c.name, kind = "cooldown", itemID = c.makes, title = c.name .. " is ready",
				why = c.note .. " Ready again every " .. c.hours .. " hours.",
				inputs = inputs, outputs = { { itemID = c.makes, qty = c.qty or 1, sell = "ah" } },
				handsOnMinutes = 3, waitDays = 1, source = "Your cooldowns" .. (c.estimate and " (timings are estimates)" or ""),
			}
			if not announced[c.name] and ns.Print and ctx.announce then
				announced[c.name] = true
				ns.Print(c.name .. " is ready.")
			end
		end
	end
	return out
end)

-- Gathering: things your gathering skill can collect that sell steadily
ns.Gen.Register("farm", function(ctx)
	local out = {}
	local minutes = ctx.sessionMinutes or 60
	for _, g in ipairs(ns.Data.Gathering or {}) do
		local prof = g.profession and ctx.char and ctx.char.professions and ctx.char.professions[g.profession]
		if prof and (prof.rank or 0) >= (g.minSkill or 0) then
			local p = ctx.priceOf(g.itemID)
			local spd = p and p.regionSoldPerDay
			if spd and spd >= 2 then
				local qty = math.max(1, math.min(20, math.floor((ctx.realmShare or 1 / 3) * spd * 0.5 * 3)))
				out[#out + 1] = {
					id = "farm:" .. g.itemID, kind = "farm", itemID = g.itemID, title = "Farm: " .. g.name,
					why = "Your " .. prof.name .. " can gather it and it sells about " .. math.floor(spd) .. " a day across the region.",
					inputs = {}, outputs = { { itemID = g.itemID, qty = qty, sell = "ah" } },
					handsOnMinutes = minutes, waitDays = 2, hint = g.zones,
					unverified = { "how many you gather in a session (the amount is a guess)" },
					source = "Gathering guide" .. (g.estimate and " (skill levels are estimates)" or ""),
				}
			end
		end
	end
	return out
end)

-- One block per profession for the plan window
function ns.Path.Blocks(char, priceOf)
	local blocks = {}
	for profID, prof in pairs(char and char.professions or {}) do
		local recipes = ns.Recipes and ns.Recipes.For(profID) or {}
		local rank = prof.rank or 0
		local ms = ns.Path.Milestones(profID, rank, recipes, skillOf, priceOf, {})
		local target = ms[1] and ms[1].rank or math.min(rank + 25, prof.max or rank + 25)
		local path = #recipes > 0 and target > rank and ns.Path.Plan(profID, rank, target, recipes, skillOf, priceOf, {}) or nil
		blocks[#blocks + 1] = { id = profID, name = prof.name, rank = rank, max = prof.max, milestones = ms, path = path,
			target = target, coverage = ns.Recipes and ns.Recipes.Coverage(profID) }
	end
	table.sort(blocks, function(a, b) return a.name < b.name end)
	return blocks
end

-- The same, cached: recomputed only when the epoch changes (new scan, refreshed prices, recipes,
-- skill-ups, or every 10 minutes), not on every gold change (review #9)
local cache = { epoch = nil, blocks = nil }
function ns.Path.CachedBlocks(char, priceOf, epoch)
	if cache.epoch ~= epoch or not cache.blocks then
		cache.blocks, cache.epoch = ns.Path.Blocks(char, priceOf), epoch
	end
	return cache.blocks
end
