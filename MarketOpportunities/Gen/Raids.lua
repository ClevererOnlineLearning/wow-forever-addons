-- Hold for raids: stock to sell after raids open, and the character's own raid prep (spec §10).
local _, ns = ...

local function own(ctx, id, now)
	local h = ns.db and ns.db.history
	return h and ns.History.Move(h, id, now) or nil
end

ns.Gen.Register("raids", function(ctx)
	local out = {}
	local now = ctx.now or 0
	local raid = ns.Raid.Next(ns.Raid.Calendar(), now)
	if not raid then return out end
	local win = ns.Raid.Windows(raid, now)
	local label = ns.Raid.Label(raid)
	local budget = ctx.budget or {}
	for _, s in ipairs(ns.Data.RaidStock or {}) do
		local p = ctx.priceOf(s.itemID)
		local move = own(ctx, s.itemID, now)
		local evidence = ns.Raid.Evidence(s, move, raid)
		local spd = p and p.regionSoldPerDay
		local unit = p and (p.minBuyout or p.market)
		local c = {
			id = "raidStock:" .. s.itemID, kind = "raidStock", itemID = s.itemID, title = "Stock for raids",
			why = "Bought now, sold 1-3 weeks after " .. label .. ". " .. s.source .. "; the rise of about " ..
				math.floor(s.rise * 100) .. "% is a guess.",
			evidence = evidence, speculative = evidence == "speculative" or nil,
			buyWindow = "now until 7 days before opening", sellWindow = "1-3 weeks after opening",
			handsOnMinutes = 15, waitDays = raid.days + 14, source = s.source,
			unverified = { "Forever raid demand (" .. evidence .. ")" },
		}
		if not win.buyOpen then
			c.blocked = "buy window closed (raid in " .. raid.days .. " days)"
			c.inputs, c.outputs = {}, {}
		elseif unit and spd and spd >= 1 then
			local qty = math.floor(math.min((ctx.realmShare or 1 / 3) * spd * 0.5 * 14, (budget.speculative or 0) / unit))
			if qty >= 1 then
				local sale = math.floor((p.market or unit) * (1 + s.rise))
				c.inputs = { { itemID = s.itemID, qty = qty, from = "ah" } }
				c.outputs = { { itemID = s.itemID, qty = qty, sell = "ah", price = sale } }
			end
		end
		if c.inputs then out[#out + 1] = c end
	end
	-- the character's own prep: a saving when bought below the usual price, never a profit
	local list = {}
	for _, x in ipairs(ns.Data.RaidPrepAll or {}) do list[#list + 1] = x end
	for _, x in ipairs(ctx.char and ctx.char.class and ns.Data.RaidPrep[ctx.char.class] or {}) do list[#list + 1] = x end
	for _, x in ipairs(list) do
		local p = ctx.priceOf(x.itemID)
		local now_ = p and (p.minBuyout or p.market)
		local usual = p and (p.historical or p.regionMarket)
		if now_ then
			local saving = usual and (usual - now_) * x.qty or nil
			out[#out + 1] = {
				id = "raidPrep:" .. x.itemID, kind = "raidPrep", itemID = x.itemID, title = "Raid prep: " .. x.name,
				why = saving and (saving > 0 and ("Costs " .. ns.Money(now_ * x.qty) .. " now; saves " .. ns.Money(saving) .. " against its usual price.")
					or "Costs more than usual right now: buy later if you can.") or "No usual price known to compare with.",
				inputs = { { itemID = x.itemID, qty = x.qty, from = "ah" } }, outputs = {}, money = 0,
				saving = saving, evidence = "speculative", handsOnMinutes = 5, waitDays = 0,
				source = "Raid prep for your class (from Classic; " .. label .. ")",
			}
		end
	end
	return out
end)
