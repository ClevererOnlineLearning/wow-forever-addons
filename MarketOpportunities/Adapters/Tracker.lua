-- Tracker: feeds Track with what really happened — purchases, sale invoices, quest rewards — and
-- keeps play sessions for savings goals. A purchase counts only when its cost is certain:
--   * a gold drop and a bag increase of exactly one tracked item within 5 seconds, or
--   * an Auction House "bought" invoice in the mail.
local _, ns = ...
local K = {}
ns.Tracker = K

local MATCH_SECONDS = 5

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2)
end

local function count(id)
	return (C_Item and call(C_Item.GetItemCount, id, true)) or call(GetItemCount, id, true) or 0
end

function K.Records()
	ns.cdb.tracked = ns.cdb.tracked or {}
	return ns.cdb.tracked
end

local function open()
	local out, now = {}, time()
	for _, r in ipairs(K.Records()) do
		local st = ns.Track.State(r, now)
		if st == "open" or st == "partial" then out[#out + 1] = r end
	end
	return out
end

function K.Find(id)
	for _, r in ipairs(K.Records()) do
		if r.id == id and not r.abandoned and time() <= r.expiresAt then return r end
	end
end

local counts = {}
local function snapshot()
	counts = {}
	for _, r in ipairs(open()) do
		for id in pairs(r.items) do counts[id] = count(id) end
	end
end

function K.Accept(eval)
	if K.Find(eval.candidate.id) then return K.Find(eval.candidate.id) end
	local totals, names = {}, {}
	for _, list in ipairs({ eval.candidate.inputs or {}, eval.candidate.outputs or {} }) do
		for _, x in ipairs(list) do
			totals[x.itemID] = count(x.itemID)
			names[x.itemID] = ns.Prices.Name(x.itemID)
		end
	end
	local r = ns.Track.Accept(eval, totals, time(), names)
	local list = K.Records()
	table.insert(list, r)
	-- keep the last 40 and nothing older than 30 days
	local now = time()
	for i = #list, 1, -1 do
		if #list > 40 or now - (list[i].acceptedAt or 0) > 30 * 86400 then table.remove(list, i) end
	end
	snapshot()
	ns.Fire("TRACK_CHANGED")
	return r
end

function K.Abandon(id)
	local r = K.Find(id)
	if r then ns.Track.Abandon(r); ns.Fire("TRACK_CHANGED") end
end

-- Gold drops (a purchase in progress)
local lastMoney, lastDrop, dropAt = nil, 0, 0
ns.On("PLAYER_MONEY", function()
	local m = call(GetMoney) or 0
	if lastMoney and m < lastMoney then lastDrop, dropAt = lastMoney - m, GetTime() end
	lastMoney = m
end)
ns.On("PLAYER_LOGIN", function() lastMoney = call(GetMoney); snapshot() end)

local recentBuys = {} -- itemID..qty -> time (so a mailed invoice for the same purchase isn't counted twice)

ns.On("BAG_UPDATE_DELAYED", function()
	if not ns.cdb then return end
	local recs = open()
	if #recs == 0 then return end
	local before = counts
	snapshot()
	local up = {}
	for id, n in pairs(counts) do
		local d = n - (before[id] or n)
		if d > 0 then up[#up + 1] = { id = id, qty = d } end
	end
	if #up ~= 1 or lastDrop <= 0 or GetTime() - dropAt > MATCH_SECONDS then return end
	local u = up[1]
	local unit = math.floor(lastDrop / u.qty + 0.5)
	lastDrop = 0
	for _, r in ipairs(recs) do -- the oldest open tip with this item gets the units
		if r.items[u.id] then
			ns.Track.OnAcquired(r, u.id, u.qty, unit, time())
			recentBuys[u.id .. ":" .. u.qty] = time()
			ns.Fire("TRACK_CHANGED")
			return
		end
	end
end)

-- Mail invoices: "bought" (cost known) and "sold" (proceeds after the cut)
local function invoiceKey(i)
	local _, _, sender, subject, money, _, daysLeft = call(GetInboxHeaderInfo, i)
	return tostring(sender) .. "|" .. tostring(subject) .. "|" .. tostring(money) .. "|" .. math.floor((daysLeft or 0) * 1440)
end

function K.ReadInvoices()
	if not (ns.cdb and type(GetInboxInvoiceInfo) == "function") then return end
	ns.cdb.invoiceSeen = ns.cdb.invoiceSeen or {}
	local seen = ns.cdb.invoiceSeen
	local recs = open()
	if #recs == 0 then return end
	local n = call(GetInboxNumItems) or 0
	for i = 1, n do
		local kind, itemName, _, bid, buyout, deposit, consignment, _, _, qty = call(GetInboxInvoiceInfo, i)
		if kind and itemName then
			local key = invoiceKey(i)
			if not seen[key] then
				seen[key] = time()
				local amount = (bid or buyout or 0)
				qty = qty or 1
				for _, r in ipairs(recs) do
					local id
					for x, name in pairs(r.items) do if name == itemName then id = x end end
					if id then
						if kind == "buyer" then
							local k = id .. ":" .. qty
							if not (recentBuys[k] and time() - recentBuys[k] < 7200) then
								ns.Track.OnAcquired(r, id, qty, math.floor(amount / qty + 0.5), time())
							end
						elseif kind == "seller" then
							ns.Track.OnSold(r, { itemName = itemName, itemID = id, qty = qty, amount = amount - (consignment or 0), t = time() })
						end
						break
					end
				end
			end
		end
	end
	-- forget old keys
	local now, keys = time(), 0
	for k, t in pairs(seen) do if now - t > 40 * 86400 then seen[k] = nil else keys = keys + 1 end end
	ns.Fire("TRACK_CHANGED")
end
ns.On("MAIL_INBOX_UPDATE", function() pcall(K.ReadInvoices) end)

ns.On("QUEST_REWARD_SEEN", function(name, money)
	for _, r in ipairs(open()) do
		if ns.Track.OnQuestReward(r, name, money or 0, time()) then ns.Fire("TRACK_CHANGED") end
	end
end)

-- Play sessions for savings goals: gold change per session and hours played
local session
ns.On("PLAYER_LOGIN", function() session = { gold = call(GetMoney) or 0, t = time() } end)
ns.On("PLAYER_LOGOUT", function()
	if not (session and ns.cdb) then return end
	local hours = (time() - session.t) / 3600
	if hours < 0.25 then return end
	ns.cdb.sessions = ns.cdb.sessions or {}
	table.insert(ns.cdb.sessions, { delta = (call(GetMoney) or 0) - session.gold, hours = hours, t = time() })
	while #ns.cdb.sessions > 20 do table.remove(ns.cdb.sessions, 1) end
end)

function K.Goal()
	local goal = ns.cdb and ns.cdb.goal
	if not goal or goal <= 0 then return nil end
	return ns.Track.Goal(goal, call(GetMoney) or 0, ns.cdb.sessions or {})
end

function K.TrustOf(itemID) return ns.Track.TrustOf(K.Records(), itemID) end
function K.Learn() return ns.Track.Learn(K.Records(), time()) end
