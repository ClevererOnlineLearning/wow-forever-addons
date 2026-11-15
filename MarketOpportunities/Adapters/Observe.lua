-- Observe: quietly remembers what the client shows — vendor prices and quest turn-ins.
-- Read-only; nothing is bought or accepted.
local _, ns = ...
local O = {}
ns.Observe = O

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2)
end

local function idFromLink(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

------------------------------------------------------------------------
-- Vendors: ns.db.vendors[itemID] = {price (per unit), stack, limited, npc, zone, seenAt}
------------------------------------------------------------------------
function O.Merchant()
	if not ns.db then return end
	ns.db.vendors = ns.db.vendors or {}
	local n = call(GetMerchantNumItems) or 0
	local npc, zone = call(UnitName, "npc"), call(GetZoneText)
	for i = 1, n do
		local info = C_MerchantFrame and call(C_MerchantFrame.GetItemInfo, i)
		local id = call(GetMerchantItemID, i) or idFromLink(call(GetMerchantItemLink, i))
		if info and id and not info.hasExtendedCost and (info.price or 0) > 0 then
			local stack = math.max(info.stackCount or 1, 1)
			local unit = math.floor(info.price / stack)
			local old = ns.db.vendors[id]
			-- keep the cheapest vendor we know; the same vendor's new price replaces its old one
			if not old or unit <= old.price or old.npc == npc then
				ns.db.vendors[id] = {
					price = unit, stack = stack, limited = (info.numAvailable or -1) >= 0,
					available = (info.numAvailable or -1) >= 0 and info.numAvailable or nil,
					npc = npc, zone = zone, seenAt = time(),
				}
			end
		end
	end
	ns.Fire("VENDORS_SEEN")
end
ns.On("MERCHANT_SHOW", O.Merchant)

------------------------------------------------------------------------
-- Quests: ns.db.quests[questID] = {name, money, inputs={{itemID, qty}}, seenAt, completions}
------------------------------------------------------------------------
local pending = {}

ns.On("QUEST_PROGRESS", function()
	local title = call(GetTitleText)
	if not title then return end
	local inputs = {}
	for i = 1, call(GetNumQuestItems) or 0 do
		local _, _, count, _, _, itemID = call(GetQuestItemInfo, "required", i)
		itemID = itemID or idFromLink(call(GetQuestItemLink, "required", i))
		if itemID and count then inputs[#inputs + 1] = { itemID = itemID, qty = count } end
	end
	pending.title, pending.inputs = title, inputs
end)

ns.On("QUEST_COMPLETE", function()
	local title = call(GetTitleText)
	if title and title == pending.title then pending.money = call(GetRewardMoney) end
end)

ns.On("QUEST_TURNED_IN", function(questID, _, money)
	if not ns.db or not questID or not pending.title then return end
	ns.db.quests = ns.db.quests or {}
	local q = ns.db.quests[questID] or { name = pending.title, completions = 0 }
	q.name = pending.title
	q.money = money or pending.money or q.money or 0
	if pending.inputs and #pending.inputs > 0 then q.inputs = pending.inputs end
	q.completions = (q.completions or 0) + 1
	q.seenAt = time()
	q.faction = ns.Char and ns.Char.Get().faction or q.faction
	ns.db.quests[questID] = q
	ns.Fire("QUEST_REWARD_SEEN", q.name, money or pending.money or 0)
	pending = {}
end)
