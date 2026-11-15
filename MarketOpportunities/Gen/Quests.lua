-- Quest turn-in candidates from the seed (observed quests join in Task 10).
local _, ns = ...
ns.Gen = ns.Gen or {}
local Gen = ns.Gen

Gen.list = Gen.list or {}

function Gen.Register(name, fn)
	for _, g in ipairs(Gen.list) do
		if g.name == name then g.fn = fn; return end
	end
	table.insert(Gen.list, { name = name, fn = fn })
end

-- Runs every generator; a failing generator adds a note and is skipped
function Gen.All(ctx, notes)
	local out = {}
	for _, g in ipairs(Gen.list) do
		local ok, res, note = pcall(g.fn, ctx)
		if ok and type(res) == "table" then
			for _, c in ipairs(res) do table.insert(out, c) end
			if note and notes then table.insert(notes, note) end
		elseif not ok and notes then
			table.insert(notes, g.name .. " tips unavailable: " .. tostring(res))
		end
	end
	return out
end

local function questCandidate(q)
	local inputs, totalQty = {}, 0
	for _, i in ipairs(q.inputs) do totalQty = totalQty + i.qty end
	for _, i in ipairs(q.inputs) do
		-- break-even unit price when this is the only input
		local buyBelow = #q.inputs == 1 and math.floor(q.money / i.qty) or nil
		table.insert(inputs, { itemID = i.itemID, qty = i.qty, from = "ah", buyBelow = buyBelow })
	end
	local unverified = {}
	for _, u in ipairs(q.unverified or {}) do table.insert(unverified, u) end
	return {
		id = "quest:" .. q.name .. ":" .. (q.faction or "both"),
		kind = "quest", questName = q.name,
		title = "Hand in: " .. q.name,
		why = "Repeatable quest pays " .. (q.money / 100) .. "s per hand-in" ..
			(q.rep and (" plus " .. q.rep.amount .. " " .. q.rep.name .. " reputation, until " .. q.rep.rank) or "") ..
			". Repeat while the items stay under the break-even price.",
		inputs = inputs, outputs = {},
		money = q.money,
		handsOnMinutes = 10, waitDays = 0,
		requires = { level = q.minLevel, faction = q.faction,
			rep = q.rep and { factionID = q.rep.factionID, below = q.rep.below, name = q.rep.name, rank = q.rep.rank } or nil },
		unverified = unverified,
		payoutVerified = q.payoutVerified,
		hint = q.giver .. ", " .. q.zone .. (q.where and (". " .. q.where) or ""),
		source = "Seed (" .. q.verified .. ", checked " .. q.checkedOn .. ")",
	}
end

-- Seed records, then what the player has handed in themselves. An observed reward replaces the
-- seed's; when they disagree the tip says so (conflict).
Gen.Register("quests", function(ctx)
	local out = {}
	local faction = ctx.char and ctx.char.faction
	local observed = {}
	for _, o in pairs(ns.db and ns.db.quests or {}) do
		if o.name and (not o.faction or not faction or o.faction == faction) then observed[o.name] = o end
	end
	local used = {}
	local community = ns.Community and ns.Community.QuestSources() or {}
	for _, q in ipairs(ns.Data.Quests or {}) do
		if not q.faction or not faction or q.faction == faction then
			local c = questCandidate(q)
			local o = observed[q.name]
			if o and o.money and o.money > 0 then
				used[q.name] = true
				if o.money ~= q.money then
					c.conflict = true
					c.money = o.money
					for _, i in ipairs(c.inputs) do if #c.inputs == 1 then i.buyBelow = math.floor(o.money / i.qty) end end
				end
				c.source = c.source .. "; reward seen by you"
			end
			if community[q.name] then c.source = c.source .. "; also a community tip (" .. table.concat(community[q.name], ", ") .. ")" end
			table.insert(out, c)
		end
	end
	for name, o in pairs(observed) do
		if not used[name] and (o.completions or 0) >= 2 and (o.money or 0) > 0 and not (function()
			for _, q in ipairs(ns.Data.Quests or {}) do if q.name == name then return true end end
		end)() then
			local inputs = {}
			for _, i in ipairs(o.inputs or {}) do
				inputs[#inputs + 1] = { itemID = i.itemID, qty = i.qty, from = "ah",
					buyBelow = #(o.inputs or {}) == 1 and math.floor(o.money / i.qty) or nil }
			end
			table.insert(out, {
				id = "quest:seen:" .. name, kind = "quest", questName = name, title = "Hand in: " .. name,
				why = "You've handed this in " .. o.completions .. " times; it pays " .. ns.Money(o.money) .. " each time.",
				inputs = inputs, outputs = {}, money = o.money, handsOnMinutes = 10, waitDays = 0,
				unverified = { "quest still offered to you" },
				source = "Seen by you (" .. o.completions .. " hand-ins)",
			})
		end
	end
	return out
end)
