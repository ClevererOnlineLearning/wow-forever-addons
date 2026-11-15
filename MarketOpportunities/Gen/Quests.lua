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
		local ok, res = pcall(g.fn, ctx)
		if ok and type(res) == "table" then
			for _, c in ipairs(res) do table.insert(out, c) end
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
		kind = "quest",
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

Gen.Register("quests", function(ctx)
	local out = {}
	local faction = ctx.char and ctx.char.faction
	for _, q in ipairs(ns.Data.Quests or {}) do
		if not q.faction or not faction or q.faction == faction then
			table.insert(out, questCandidate(q))
		end
	end
	return out
end)
