-- Loot Flare: what your loot is worth on the auction house, and a loot history by zone,
-- subzone and mob, so you can see where the gold is.
-- Prices come only from Auctionator's and TSM's public APIs (Auctionator first, then TSM's
-- market value), never from their saved data. Soulbound and grey items count at vendor price.
-- Written by good mens (Mephz on WoW Forever). MIT licence.
local _, ns = ...
local S = ns.Skin
local LF = LootFlare
local floor, max, min = math.floor, math.max, math.min

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Num(v) if type(v) == "number" and not Secret(v) then return v end end
local function Str(v) if type(v) == "string" and not Secret(v) and v ~= "" then return v end end
local function Yes(v) return not Secret(v) and v and true or false end
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2)
end
local function Now() return Num(Call(GetTime)) or 0 end
local function Say(m) print("|cffffd100Loot Flare|r: " .. m) end

------------------------------------------------------------------------
-- Prices
------------------------------------------------------------------------
local CALLER = "LootFlare"
local function Usable(v) v = Num(v); if v and v > 0 then return floor(v) end end

function LF.HasAHPrices()
	return (Auctionator and Auctionator.API and Auctionator.API.v1 and true) or (TSM_API and TSM_API.GetCustomPriceValue and true) or false
end

local OLD_DAYS, SLOW_RATE = 7, 0.05 -- an Auctionator price older than this, a TSM sale rate below this

local function Atr()
	local A = Auctionator and Auctionator.API and Auctionator.API.v1
	if A and (A.GetAuctionPriceByItemLink or A.GetAuctionPriceByItemID) then return A end
end
local function Tsm() if TSM_API and TSM_API.GetCustomPriceValue then return TSM_API end end

-- Auctionator: price and age in days of its last scan
local function AtrPrice(link, id)
	local A = Atr()
	if not A then return nil end
	local p, age
	if A.GetAuctionPriceByItemLink then p = Usable(Call(A.GetAuctionPriceByItemLink, CALLER, link)) end
	if not p and id and A.GetAuctionPriceByItemID then p = Usable(Call(A.GetAuctionPriceByItemID, CALLER, id)) end
	if not p then return nil end
	if A.GetAuctionAgeByItemLink then age = Num(Call(A.GetAuctionAgeByItemLink, CALLER, link)) end
	if age == nil and id and A.GetAuctionAgeByItemID then age = Num(Call(A.GetAuctionAgeByItemID, CALLER, id)) end
	return p, age
end

-- TSM: market value, and the region sale rate (share of auctions that sell) when it has one
local function TsmPrice(link, id)
	local T = Tsm()
	if not (T and id) then return nil end
	local plain = "i:" .. id
	local s = T.ToItemString and Str(Call(T.ToItemString, link)) or plain
	local p = Usable(Call(T.GetCustomPriceValue, "DBMarket", s))
	if not p and s ~= plain then p = Usable(Call(T.GetCustomPriceValue, "DBMarket", plain)) end
	return p
end
local function SaleRate(id)
	local T = Tsm()
	if not (T and id) then return nil end
	local r = Num(Call(T.GetCustomPriceValue, "DBRegionSaleRate*1000", "i:" .. id))
	return r and r / 1000
end
LF.SaleRate = SaleRate

-- Auction price of one item: Auctionator's last scan first (unless it's over a week old and
-- TSM has a price), then TSM's market value. Returns copper, "Auctionator"/"TSM", and a warning:
-- "old" (Auctionator's scan is over a week old) or "slow" (TSM says few of these sell).
function LF.AHPrice(link)
	link = Str(link)
	if not link then return nil end
	local id = tonumber(link:match("item:(%d+)"))
	local p, src, warn
	local ap, age = AtrPrice(link, id)
	local old = ap and age and age > OLD_DAYS
	if ap and not old then
		p, src = ap, "Auctionator"
	else
		local tp = TsmPrice(link, id)
		if tp then p, src = tp, "TSM"
		elseif ap then p, src, warn = ap, "Auctionator", "old" end
	end
	if not p then return nil end
	local rate = SaleRate(id)
	if not warn and rate and rate < SLOW_RATE then warn = "slow" end
	return p, src, warn
end

local function Info(link)
	local GI = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local r = { Call(GI, link) }
	if not Str(r[1]) or r[11] == nil then return nil end -- no sell price yet: not loaded
	return { name = r[1], q = Num(r[3]) or 1, price = Num(r[11]) or 0, bind = Num(r[14]) }
end

-- vendor value, counted value (the higher of AH and vendor), price source, warning
-- ("old"/"slow": with the "safe AH value" setting on, such items count at vendor price)
function LF.ItemValue(link, count, info)
	info = info or Info(link)
	if not info then return nil end
	count = count or 1
	local vendor = info.price * count
	-- greys, soulbound (1) and quest (4) items can't go on the auction house
	if info.q == 0 or info.bind == 1 or info.bind == 4 then return vendor, vendor, nil end
	local p, src, warn = LF.AHPrice(link)
	if not p then return vendor, vendor, nil end
	if warn and LF.db and LF.db.ahSafe then return vendor, vendor, src, warn end
	return vendor, max(vendor, p * count), src, warn
end

------------------------------------------------------------------------
-- Where loot comes from: zone, subzone, and the corpse / node / chest being looted
------------------------------------------------------------------------
-- gathering and opening spells: their target (the node or chest) names the source
local GATHER_IDS = { 2575, 2576, 3564, 10248, 2366, 2368, 3570, 11993, 8613, 8617, 8618, 10768,
	3365, 6477, 6478, 21248, 22810, 7620, 7731, 7732, 18248, 921, 13262 }
local GATHER_NAMES = { Mining = true, ["Herb Gathering"] = true, Skinning = true, Opening = true,
	["Opening - No Text"] = true, Fishing = true, ["Pick Pocket"] = true, Disenchant = true }
local namesReady = false
local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return Str(Call(C_Spell.GetSpellName, id)) end
	return Str((Call(GetSpellInfo, id)))
end
local function IsGather(name)
	if not namesReady then
		for _, id in ipairs(GATHER_IDS) do local n = SpellName(id); if n then GATHER_NAMES[n] = true end end
		namesReady = true
	end
	return GATHER_NAMES[name]
end

local source = { name = nil, open = false, untilT = nil }
local cast -- { label, t }
local quest = { open = false, untilT = nil } -- a quest's reward window
local QUEST = "Quest reward"

function LF.Where()
	local zone = Str(Call(GetRealZoneText)) or Str(Call(GetZoneText)) or "Unknown"
	local sub = Str(Call(GetSubZoneText)) or zone
	return zone, sub
end

-- zone, subzone and source of loot arriving right now
function LF.LootContext()
	local zone, sub = LF.Where()
	local mob = "Other"
	if quest.open or (quest.untilT and Now() <= quest.untilT) then
		mob = QUEST
	elseif source.name and (source.open or (source.untilT and Now() <= source.untilT)) then
		mob = source.name
	end
	return { zone = zone, sub = sub, mob = mob }
end

------------------------------------------------------------------------
-- The record
------------------------------------------------------------------------
local KEEP_SESSIONS, KEEP_ITEMS, KEEP_SESSION_ITEMS = 30, 50, 100

local function H() return LF.db.histData end
local function NewCur() return { start = Num(Call(time)) or 0, secs = 0, money = 0, vendor = 0, ah = 0, items = {}, zones = {} } end
local function Cur() local h = H(); if type(h.cur) ~= "table" then h.cur = NewCur() end return h.cur end
local function Bucket(t, k)
	local b = t[k]
	if not b then b = { secs = 0, money = 0, vendor = 0, ah = 0, n = 0 }; t[k] = b end
	return b
end
local function Zone(name)
	local zones = H().zones
	local z = zones[name]
	if not z then z = { secs = 0, money = 0, vendor = 0, ah = 0, loots = 0, subs = {}, mobs = {}, items = {} }; zones[name] = z end
	return z
end
local function Add(b, money, vendor, ah)
	b.money = (b.money or 0) + money
	b.vendor = (b.vendor or 0) + vendor
	b.ah = (b.ah or 0) + ah
end
local function On() return LF.db and LF.db.hist end
-- quest rewards stay in the session, but out of zone, subzone and mob numbers (a setting)
local function InZones(ctx) return not (ctx.mob == QUEST and LF.db.histQuestOut) end

-- the clock runs only while you're playing: not AFK, not resting in a town or inn, and not
-- idle (no moving, fighting or looting) for 3 minutes. A setting turns this off.
local IDLE = 180
local lastActive = 0
function LF.Active() lastActive = Now() end
function LF.ClockState()
	local db = LF.db
	if not (db and db.pauseIdle) then return true end
	if Yes(Call(UnitIsAFK, "player")) then return false, "AFK" end
	if Yes(Call(IsResting)) then return false, "resting" end
	if Yes(Call(UnitAffectingCombat, "player")) or (Num(Call(GetUnitSpeed, "player")) or 0) > 0 then lastActive = Now() end
	if Now() - lastActive > IDLE then return false, "idle" end
	return true
end

-- Values one looted item, counts it for the gold box, and records it in the history.
-- Returns false while the item's info hasn't loaded yet.
function LF.RecordLoot(link, count, ctx)
	local info = Info(link)
	if not info then return false end
	lastActive = Now()
	local vendor, best, _, warn = LF.ItemValue(link, count, info)
	if LF.AddValue then
		if vendor > 0 then LF.AddValue("items", vendor) end
		if best > 0 then LF.AddValue("ah", best) end
	end
	if not On() then return true end
	ctx = ctx or LF.LootContext()
	local id = tonumber(link:match("item:(%d+)")) or 0
	local c = Cur()
	Add(c, 0, vendor, best)
	local key = id .. "|" .. ctx.zone .. "|" .. ctx.sub .. "|" .. ctx.mob
	local it = c.items[key]
	if not it then
		it = { id = id, name = info.name, q = info.q, n = 0, vendor = 0, ah = 0, zone = ctx.zone, sub = ctx.sub, mob = ctx.mob }
		c.items[key] = it
	end
	it.n = it.n + count; it.vendor = it.vendor + vendor; it.ah = it.ah + best
	it.warn = warn
	if not InZones(ctx) then return true end
	Add(Bucket(c.zones, ctx.zone), 0, vendor, best)
	local z = Zone(ctx.zone)
	Add(z, 0, vendor, best)
	Add(Bucket(z.subs, ctx.sub), 0, vendor, best)
	Add(Bucket(z.mobs, ctx.mob), 0, vendor, best)
	local zi = z.items[id]
	if not zi then zi = { name = info.name, q = info.q, n = 0, vendor = 0, ah = 0 }; z.items[id] = zi end
	zi.n = zi.n + count; zi.vendor = zi.vendor + vendor; zi.ah = zi.ah + best
	return true
end

function LF.HistMoney(copper)
	copper = Num(copper)
	if not (On() and copper and copper > 0) then return end
	local ctx = LF.LootContext()
	local c = Cur()
	Add(c, copper, 0, 0)
	if not InZones(ctx) then return end
	Add(Bucket(c.zones, ctx.zone), copper, 0, 0)
	local z = Zone(ctx.zone)
	Add(z, copper, 0, 0)
	Add(Bucket(z.subs, ctx.sub), copper, 0, 0)
	Add(Bucket(z.mobs, ctx.mob), copper, 0, 0)
end

-- Time: the gold box's session clock, and time spent in each zone and subzone
function LF.Tick(dt)
	local db = LF.db
	dt = Num(dt)
	if not (db and dt and dt > 0) then return end
	if not LF.ClockState() then return end
	if db.gph or db.hist then db.session.secs = (db.session.secs or 0) + dt end
	if not db.hist then return end
	local zone, sub = LF.Where()
	local c = Cur()
	c.secs = c.secs + dt
	local cz = Bucket(c.zones, zone)
	cz.secs = cz.secs + dt
	local z = Zone(zone)
	z.secs = z.secs + dt
	local s = Bucket(z.subs, sub)
	s.secs = s.secs + dt
end

local function Top(t, n, key)
	local arr = {}
	for k, v in pairs(t) do arr[#arr + 1] = { k = k, v = v } end
	table.sort(arr, function(a, b) return (a.v[key] or 0) > (b.v[key] or 0) end)
	local out = {}
	for i = 1, min(n, #arr) do out[arr[i].k] = arr[i].v end
	return out, arr
end
local function Value(b) return (b.money or 0) + (b.ah or 0) end

-- A new session starts (right-click on the gold box, Start over, or logging in): the old one
-- goes into the history. Zone totals stay; each zone keeps its 50 best items and mobs.
function LF.HistNewSession()
	if not (LF.db and LF.db.histData) then return end
	local h = H()
	local c = h.cur
	if type(c) == "table" and (c.ah > 0 or c.money > 0 or c.vendor > 0) then
		local _, arr = Top(c.items, KEEP_SESSION_ITEMS, "ah")
		local list = {}
		for i = 1, min(KEEP_SESSION_ITEMS, #arr) do list[i] = arr[i].v end
		c.items = list
		table.insert(h.sessions, 1, c)
		while #h.sessions > KEEP_SESSIONS do table.remove(h.sessions) end
	end
	for _, z in pairs(h.zones) do
		z.items = Top(z.items, KEEP_ITEMS, "ah")
		local mobs = {}
		for k, m in pairs(z.mobs) do m.value = Value(m); mobs[k] = m end
		z.mobs = Top(mobs, KEEP_ITEMS, "value")
	end
	h.cur = NewCur()
	if LF.RefreshHistory then LF.RefreshHistory() end
end

local clearAsked
function LF.ClearHistory()
	if not (clearAsked and Now() - clearAsked <= 5) then
		clearAsked = Now()
		Say("click Clear history again within 5 seconds to delete every session and zone total.")
		if LF.RefreshHistory then LF.RefreshHistory() end
		return false
	end
	clearAsked = nil
	local h = H()
	h.sessions, h.zones, h.cur = {}, {}, NewCur()
	Say("loot history cleared.")
	if LF.RefreshHistory then LF.RefreshHistory() end
	return true
end
function LF.ClearPending() return clearAsked and Now() - clearAsked <= 5 end

------------------------------------------------------------------------
-- Events: what's being looted, and the clock
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "UNIT_SPELLCAST_SENT", "QUEST_COMPLETE", "QUEST_FINISHED", "PLAYER_LOGIN" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, unit, target, _, spellID)
	if e == "PLAYER_LOGIN" then
		lastActive = Now()
	elseif e == "QUEST_COMPLETE" then
		quest.open, quest.untilT = true, nil
	elseif e == "QUEST_FINISHED" then
		if quest.open then quest.open, quest.untilT = false, Now() + 2 end
	elseif e == "UNIT_SPELLCAST_SENT" then
		if unit ~= "player" then return end
		local spell = Num(spellID) and SpellName(spellID)
		if not (spell and IsGather(spell)) then return end
		local t = Str(target)
		cast = { label = t and (t .. " (" .. spell .. ")") or spell, t = Now() }
	elseif e == "LOOT_OPENED" then
		local name
		if cast and Now() - cast.t <= 8 then
			name = cast.label
		elseif Yes(Call(UnitExists, "target")) and Yes(Call(UnitIsDead, "target")) then
			name = Str(Call(UnitName, "target"))
		end
		cast = nil
		lastActive = Now()
		source.name, source.open, source.untilT = name or "Unknown", true, nil
		if On() then
			local zone, sub = LF.Where()
			local z = Zone(zone)
			z.loots = (z.loots or 0) + 1
			local m = Bucket(z.mobs, source.name)
			m.n = m.n + 1
		end
	elseif e == "LOOT_CLOSED" then
		-- the "You receive loot" lines can arrive just after the window closes
		source.open, source.untilT = false, Now() + 2
	end
end)

local clock = CreateFrame("Frame")
local acc, redraw = 0, 0
clock:SetScript("OnUpdate", function(_, dt)
	acc = acc + dt
	if acc < 1 then return end
	LF.Tick(acc)
	redraw = redraw + acc
	acc = 0
	if redraw >= 2 then
		redraw = 0
		if LF.HistoryShown and LF.HistoryShown() then LF.RefreshHistory() end
	end
end)

------------------------------------------------------------------------
-- The window: This session / Zones / Sessions
------------------------------------------------------------------------
local function Time(secs)
	secs = floor(secs or 0)
	local h, m = floor(secs / 3600), floor(secs / 60) % 60
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end
local PLAIN = false -- while copying: money as "12g 34s" text instead of coin icons
local function Short(c)
	c = floor(c or 0)
	if c >= 10000 then c = floor(c / 100) * 100 end
	if PLAIN then
		local g, sv, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
		local out = {}
		if g > 0 then out[#out + 1] = g .. "g" end
		if sv > 0 then out[#out + 1] = sv .. "s" end
		if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
		return table.concat(out, " ")
	end
	return LF.FormatMoney(c)
end
local function PerHour(b) if (b.secs or 0) < 60 then return nil end return floor(Value(b) * 3600 / b.secs) end
local function PerHourV(b) if (b.secs or 0) < 60 then return nil end return floor(((b.money or 0) + (b.vendor or 0)) * 3600 / b.secs) end
local function Money(v) return v and Short(v) or "|cff888888-|r" end
local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
local WARN = { slow = " |cffff9900(sells slowly)|r", old = " |cffff9900(old price)|r" }
local function ItemName(it)
	return Hex(LF.QualityColor(it.q or 1)) .. (it.name or "?") .. "|r" .. ((it.n or 1) > 1 and ("|cffffffff x" .. it.n .. "|r") or "")
		.. (it.warn and WARN[it.warn] or "")
end
-- a chat link for an item id (the game's own link when it has the item loaded)
local function ItemLink(id, name, q)
	local GI = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local _, link = Call(GI, "item:" .. id)
	link = Str(link)
	if link and link:find("|Hitem:", 1, true) then return link end
	return Hex(LF.QualityColor(q or 1)) .. "|Hitem:" .. id .. "::::::::|h[" .. (name or "?") .. "]|h|r"
end
local GREY = "|cff888888"

local SHORT_ZONE = 600 -- under 10 minutes: too little time to judge a zone
local ROWS, RH, W, HGT = 15, 20, 640, 470

local win, pages, selectTab, lists, footNote, clearBtn
local zoneView -- zone name shown in detail on the Zones tab
local sessionView -- index of a past session shown on the first tab (nil: this session)

local function MakeList(page, cols)
	local L = { cols = cols, data = {}, off = 0, rows = {} }
	L.summary = S.Text(page, "", 14, -10, "GameFontHighlightSmall", W - 28)
	L.summary:SetSpacing(2)
	local function Cells(parent, font)
		local cells, x = {}, 10
		for i, c in ipairs(cols) do
			local fs = parent:CreateFontString(nil, "OVERLAY", font)
			fs:SetPoint("LEFT", x, 0)
			fs:SetWidth(c.w - 6)
			fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
			if fs.SetWordWrap then fs:SetWordWrap(false) end
			cells[i] = fs
			x = x + c.w
		end
		return cells
	end
	local head = CreateFrame("Frame", nil, page)
	head:SetPoint("TOPLEFT", 6, -46); head:SetPoint("TOPRIGHT", -6, -46); head:SetHeight(RH)
	local hbg = head:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); hbg:SetColorTexture(1, 1, 1, 0.06)
	L.head = Cells(head, "GameFontNormalSmall")
	for i, c in ipairs(cols) do L.head[i]:SetText(c.t) end
	for i = 1, ROWS do
		local r = CreateFrame("Button", nil, page)
		r:SetPoint("TOPLEFT", 6, -46 - RH * i); r:SetPoint("TOPRIGHT", -6, -46 - RH * i); r:SetHeight(RH)
		local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
		r.bg = bg
		local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
		r.cells = Cells(r, "GameFontHighlightSmall")
		r:SetScript("OnClick", function(self)
			local d = self.d
			if not d then return end
			if d.id and IsShiftKeyDown and IsShiftKeyDown() then
				if ChatEdit_InsertLink then ChatEdit_InsertLink(ItemLink(d.id, d.name, d.q)) end
			elseif d.onClick then
				d.onClick()
			end
		end)
		-- items: the game's tooltip on hover; Shift-click links it in chat
		r:SetScript("OnEnter", function(self)
			if not (self.d and self.d.id and self.d.id > 0) then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:" .. self.d.id)
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		L.rows[i] = r
	end
	L.more = S.Text(page, "", 14, -46 - RH * (ROWS + 1) - 4, "GameFontDisableSmall", W - 28)
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, d)
		L.off = max(0, min(L.off - d * 3, #L.data - ROWS))
		L:Draw()
	end)
	function L:Headers(names) for i = 1, #cols do self.head[i]:SetText(names and names[i] or cols[i].t) end end
	function L:Set(data, summary)
		self.data = data
		self.off = max(0, min(self.off, #data - ROWS))
		self.summary:SetText(summary or "")
		self:Draw()
	end
	function L:Draw()
		for i, r in ipairs(self.rows) do
			local d = self.data[i + self.off]
			r.d = d
			r:SetShown(d ~= nil)
			if d then
				for c, fs in ipairs(r.cells) do fs:SetText(d[c] or "") end
				if d.header then r.bg:SetColorTexture(1, 0.82, 0, 0.10) else r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0) end
			end
		end
		if #self.data > ROWS then
			self.more:SetText(("%d-%d of %d   (mouse wheel to scroll)"):format(self.off + 1, min(#self.data, self.off + ROWS), #self.data))
		elseif #self.data == 0 then
			self.more:SetText("Nothing yet: go and loot something.")
		else
			self.more:SetText("")
		end
	end
	function L:Text()
		local out = { self.summary:GetText() or "" }
		for _, d in ipairs(self.data) do for c = 1, #cols do out[#out + 1] = d[c] or "" end end
		return table.concat(out, " | ")
	end
	return L
end

local function SourceNote()
	local a = Auctionator and Auctionator.API and Auctionator.API.v1
	if a and TSM_API then return "AH prices: Auctionator, then TSM market value. Soulbound and grey items count at vendor price." end
	if a then return "AH prices: Auctionator. Soulbound and grey items count at vendor price." end
	if TSM_API then return "AH prices: TSM market value. Soulbound and grey items count at vendor price." end
	return "No AH prices: install Auctionator or TSM (and scan the AH) to value loot at auction prices."
end

local function Started(c) return Str(Call(date, "%d %b %H:%M", c.start)) or "?" end

local function FillSession()
	local past = sessionView and H().sessions[sessionView]
	if sessionView and not past then sessionView = nil end
	local c = past or Cur()
	local arr = {}
	for _, it in pairs(c.items) do arr[#arr + 1] = it end
	table.sort(arr, function(a, b) return a.ah > b.ah end)
	local data = {}
	if past then data[1] = { "|cffffd100< Back to this session|r", onClick = function() LF.ShowSession(nil) end } end
	for _, it in ipairs(arr) do
		local where = it.zone == it.sub and it.zone or (it.zone .. ": " .. it.sub)
		data[#data + 1] = { ItemName(it), Short(it.ah), it.ah > it.vendor and Short(it.vendor) or GREY .. "same|r", where, it.mob,
			id = it.id, name = it.name, q = it.q }
	end
	local nz = 0
	for _ in pairs(c.zones) do nz = nz + 1 end
	local ph, pv = PerHour(c), PerHourV(c)
	lists[1]:Set(data, ("%s: %s in %d zone%s. Loot %s (AH value), %s at vendor.   Per hour: %s AH, %s vendor.")
		:format(past and ("Session of " .. Started(c)) or "This session", Time(c.secs), nz, nz == 1 and "" or "s",
			Short(Value(c)), Short(c.money + c.vendor), Money(ph), Money(pv)))
end

local function BestMob(z)
	local best, bestV
	for name, m in pairs(z.mobs) do
		if name ~= "Other" and (m.n or 0) > 0 then
			local per = Value(m) / m.n
			local v = per * (m.n >= 3 and 1 or 0.5) -- one lucky drop shouldn't top the list
			if not bestV or v > bestV then best, bestV = name .. GREY .. " (" .. Short(per) .. " a loot)|r", v end
		end
	end
	return best or GREY .. "-|r"
end

local function FillZones()
	local L = lists[2]
	if zoneView and H().zones[zoneView] then
		local z = H().zones[zoneView]
		L:Headers({ "Name", "Time / loots", "Per hour (AH)", "Per loot (AH)", "Total (AH)" })
		local data = { { "|cffffd100< Back to all zones|r", onClick = function() LF.ShowZone(nil) end } }
		data[#data + 1] = { "Subzones", header = true }
		local subs = {}
		for name, s in pairs(z.subs) do subs[#subs + 1] = { name = name, s = s } end
		table.sort(subs, function(a, b) return (PerHour(a.s) or -1) > (PerHour(b.s) or -1) end)
		for _, x in ipairs(subs) do data[#data + 1] = { x.name, Time(x.s.secs), Money(PerHour(x.s)), "", Short(Value(x.s)) } end
		data[#data + 1] = { "Mobs, nodes and chests", header = true }
		local mobs = {}
		for name, m in pairs(z.mobs) do mobs[#mobs + 1] = { name = name, m = m } end
		table.sort(mobs, function(a, b) return Value(a.m) > Value(b.m) end)
		for _, x in ipairs(mobs) do
			local n = x.m.n or 0
			data[#data + 1] = { x.name, n > 0 and (n .. " loots") or GREY .. "no loot window|r", "", n > 0 and Short(Value(x.m) / n) or "", Short(Value(x.m)) }
		end
		data[#data + 1] = { "Top items", header = true }
		local items = {}
		for _, it in pairs(z.items) do items[#items + 1] = it end
		table.sort(items, function(a, b) return a.ah > b.ah end)
		for id, it in pairs(z.items) do it.id = it.id or id end
		for _, it in ipairs(items) do data[#data + 1] = { ItemName(it), "", "", "", Short(it.ah), id = it.id, name = it.name, q = it.q } end
		L:Set(data, ("%s: %s over all your sessions, %s looted (AH value). Per hour: %s AH, %s vendor.")
			:format(zoneView, Time(z.secs), Short(Value(z)), Money(PerHour(z)), Money(PerHourV(z))))
		return
	end
	L:Headers()
	local arr = {}
	for name, z in pairs(H().zones) do arr[#arr + 1] = { name = name, z = z } end
	table.sort(arr, function(a, b)
		local la, lb = a.z.secs >= SHORT_ZONE, b.z.secs >= SHORT_ZONE
		if la ~= lb then return la end
		return (PerHour(a.z) or -1) > (PerHour(b.z) or -1)
	end)
	local data = {}
	for _, x in ipairs(arr) do
		local short = x.z.secs < SHORT_ZONE
		local name = x.name
		data[#data + 1] = { short and (GREY .. name .. "|r") or ("|cffffffff" .. name .. "|r"), Time(x.z.secs),
			Money(PerHour(x.z)), Money(PerHourV(x.z)), BestMob(x.z), onClick = function() LF.ShowZone(name) end }
	end
	L:Set(data, "Every zone over all your sessions, best gold per hour (AH value) first. Click a zone for its subzones, "
		.. "mobs and top items. Grey: under 10 minutes there, too little to judge.")
end

local function SessionRow(c, index)
	local top, topS
	for name, z in pairs(c.zones or {}) do if not topS or (z.secs or 0) > topS then top, topS = name, z.secs or 0 end end
	local started = index and Started(c) or "|cff20ff20now|r"
	return { started, Time(c.secs), Short(Value(c)), Money(PerHour(c)), Money(PerHourV(c)), top or GREY .. "-|r",
		onClick = function() LF.ShowSession(index) end }
end

local function FillSessions()
	local data = { SessionRow(Cur()) }
	for i, c in ipairs(H().sessions) do data[#data + 1] = SessionRow(c, i) end
	lists[3]:Set(data, ("Your last %d sessions; click one to see what you looted. Loot is money looted plus AH value. "
		.. "A new session starts when you click New session or right-click the gold box."):format(KEEP_SESSIONS))
end

local function Build()
	local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	win = S.Window("LootFlareHistoryFrame", "Loot history", "Interface\\Icons\\INV_Misc_Coin_02", GetMeta and GetMeta("LootFlare", "Version"), W, HGT)
	local sel
	pages, sel = S.Tabs(win, { "This session", "Zones", "Sessions" }, -38, 41)
	lists = {
		MakeList(pages[1], { { t = "Item", w = 200 }, { t = "Value (AH)", w = 80, right = true }, { t = "Vendor", w = 70, right = true }, { t = "Where", w = 160 }, { t = "From", w = 118 } }),
		MakeList(pages[2], { { t = "Zone", w = 170 }, { t = "Time", w = 70, right = true }, { t = "Per hour (AH)", w = 95, right = true }, { t = "Per hour (vendor)", w = 100, right = true }, { t = "Best mob or node", w = 193 } }),
		MakeList(pages[3], { { t = "Started", w = 110 }, { t = "Length", w = 70, right = true }, { t = "Loot (AH)", w = 90, right = true }, { t = "Per hour (AH)", w = 95, right = true }, { t = "Per hour (vendor)", w = 100, right = true }, { t = "Main zone", w = 163 } }),
	}
	selectTab = function(i) sel(i); LF.RefreshHistory() end
	-- tab clicks should redraw too
	-- (the page shows before S.Tabs notes the new tab number, so set it here first)
	for i, p in ipairs(pages) do p:SetScript("OnShow", function() win.tab = i; LF.RefreshHistory() end) end
	local foot = S.Footer(win, 40)
	clearBtn = S.Button(foot, "Clear history", 120, 24)
	clearBtn:SetPoint("LEFT", 12, 0)
	clearBtn:SetScript("OnClick", function() LF.ClearHistory() end)
	S.Tip(clearBtn, "Clear history", "Deletes every saved session and zone total. Click twice to confirm.")
	local new = S.Button(foot, "New session", 120, 24)
	new:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
	new:SetScript("OnClick", function() if LF.ResetGold then LF.ResetGold() else LF.HistNewSession() end end)
	local copy = S.Button(foot, "Copy", 70, 24)
	copy:SetPoint("LEFT", new, "RIGHT", 8, 0)
	copy:SetScript("OnClick", function() LF.CopyHistory() end)
	S.Tip(copy, "Copy", "This tab as plain text, to paste into Discord or a note.")
	footNote = S.Note(foot, "", 0, 0, W - 370)
	footNote:ClearAllPoints()
	footNote:SetPoint("LEFT", copy, "RIGHT", 12, 0)
	win:SetScript("OnShow", function() LF.RefreshHistory() end)
end

function LF.RefreshHistory()
	if not (win and LF.db and LF.db.histData) then return end
	footNote:SetText(SourceNote())
	clearBtn:SetText(LF.ClearPending() and "Click again" or "Clear history")
	local t = win.tab or 1
	if t == 1 then FillSession() elseif t == 2 then FillZones() else FillSessions() end
end

function LF.HistoryShown() return win and win:IsShown() end
function LF.ToggleHistory()
	if not win then Build() end
	if win:IsShown() then win:Hide() else win:Show(); LF.RefreshHistory() end
end
function LF.ShowHistoryTab(i)
	if not win then Build() end
	if not win:IsShown() then win:Show() end
	selectTab(i)
end
function LF.ShowZone(name)
	zoneView = name
	if win then lists[2].off = 0 end
	LF.ShowHistoryTab(2)
end
function LF.ShowSession(index)
	sessionView = index
	if win then lists[1].off = 0 end
	LF.ShowHistoryTab(1)
end
-- everything the current tab lists, as text (for the tests and /lflare history dump)
function LF.HistoryText()
	if not win then return "" end
	return lists[win.tab or 1]:Text()
end
function LF.HistoryRow(i)
	if not win then return nil end
	return lists[win.tab or 1].rows[i]
end

-- The current tab as plain text: one line per row, columns split by " | "
local function Strip(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|h", "")) end
function LF.HistoryPlain()
	if not win then return "" end
	local L = lists[win.tab or 1]
	PLAIN = true
	LF.RefreshHistory()
	local lines = { Strip(L.summary:GetText()) }
	local heads = {}
	for i = 1, #L.cols do heads[i] = Strip(L.head[i]:GetText()) end
	lines[#lines + 1] = table.concat(heads, " | ")
	for _, d in ipairs(L.data) do
		local cells = {}
		for c = 1, #L.cols do cells[c] = Strip(d[c]) end
		while #cells > 0 and cells[#cells] == "" do cells[#cells] = nil end
		lines[#lines + 1] = (d.header and "== " or "") .. table.concat(cells, " | ")
	end
	PLAIN = false
	LF.RefreshHistory()
	return table.concat(lines, "\n")
end

local copyWin, copyBox
function LF.CopyHistory()
	if not win then return end
	if not copyWin then
		copyWin = S.Window("LootFlareCopyFrame", "Copy loot history", "Interface\\Icons\\INV_Misc_Note_01", nil, 560, 380)
		copyBox = CreateFrame("EditBox", nil, copyWin)
		copyBox:SetPoint("TOPLEFT", 12, -44)
		copyBox:SetPoint("BOTTOMRIGHT", -12, 34)
		copyBox:SetMultiLine(true)
		copyBox:SetAutoFocus(false)
		copyBox:SetFontObject("ChatFontNormal")
		if copyBox.SetMaxLetters then copyBox:SetMaxLetters(0) end
		local bg = copyBox:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.02, 0.02, 0.03, 1)
		copyBox:SetScript("OnEscapePressed", function() copyWin:Hide() end)
		S.Note(copyWin, "Ctrl+C copies it (it's all selected). Esc closes.", 14, -350, 520)
	end
	copyBox:SetText(LF.HistoryPlain())
	copyWin:Show()
	copyBox:SetFocus()
	copyBox:HighlightText()
end

------------------------------------------------------------------------
-- /lflare check: what Loot Flare can see on this client
------------------------------------------------------------------------
function LF.Check()
	local r = {}
	local A, T = Atr(), Tsm()
	r[#r + 1] = "Auctionator prices: " .. (A and "found" or "not found")
	r[#r + 1] = "TSM prices: " .. (T and "found" or "not found")
	-- price test on the best thing you've looted (this session, else any zone)
	local best
	local function consider(id, it)
		if id and id > 0 and (not best or (it.ah or 0) > (best.ah or 0)) then best = { id = id, name = it.name, ah = it.ah } end
	end
	if LF.db.histData then
		for _, it in pairs(Cur().items) do consider(it.id, it) end
		if not best then for _, z in pairs(H().zones) do for id, it in pairs(z.items) do consider(id, it) end end end
	end
	if best then
		local link = "item:" .. best.id
		local ap, age = AtrPrice(link, best.id)
		local tp = TsmPrice(link, best.id)
		local rate = SaleRate(best.id)
		local p, src, warn = LF.AHPrice(link)
		r[#r + 1] = ("price test, %s: Auctionator %s%s, TSM %s%s -> %s"):format(best.name or best.id,
			ap and Short(ap) or "none", age and (" (" .. age .. " days old)") or "",
			tp and Short(tp) or "none", rate and (", sale rate " .. string.format("%.2f", rate)) or "",
			p and (Short(p) .. " from " .. src .. (warn and (", " .. warn) or "")) or "no AH price")
	else
		r[#r + 1] = "price test: loot something first, then run /lflare check again"
	end
	local found = {}
	for _, id in ipairs(GATHER_IDS) do
		local n = SpellName(id)
		if n and not found[n] then found[n] = true; found[#found + 1] = n end
	end
	r[#r + 1] = "gathering spells recognised: " .. (#found > 0 and table.concat(found, ", ") or "none (sources will show as Unknown)")
	local running, why = LF.ClockState()
	r[#r + 1] = "clock: " .. (running and "running" or ("paused (" .. (why or "?") .. ")"))
	local nz = 0
	if LF.db.histData then for _ in pairs(H().zones) do nz = nz + 1 end end
	r[#r + 1] = ("loot history: %s, %d sessions saved, %d zones"):format(LF.db.hist and "on" or "off",
		LF.db.histData and #H().sessions or 0, nz)
	PLAIN = true
	for i, l in ipairs(r) do r[i] = Strip(l) end
	PLAIN = false
	for _, l in ipairs(r) do Say(l) end
	LF.db.lastCheck = r
	return r
end
