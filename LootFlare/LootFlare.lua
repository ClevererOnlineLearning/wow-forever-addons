-- Loot Flare: what you loot appears as a short, tidy stack of lines mid-screen.
-- Good drops get a rarity glow, a shine sweep and a sound of their own; quest items are
-- marked and show your quest progress.
-- Written from scratch by good mens (Mephz on WoW Forever). MIT licence.

local LF = {}
_G.LootFlare = LF

local floor, min, max, sin, cos, pi = math.floor, math.min, math.max, math.sin, math.cos, math.pi

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local DEFAULTS = {
	enabled = true,
	items = true, minQuality = 0,
	money = true, currency = true, honor = true,
	quest = true, ilvl = true,
	bagCount = true, fancy = true, growUp = true,
	anim = "stack",
	scale = 1.0, duration = 4, maxLines = 8,
	sounds = { [2] = 0, [3] = 878, [4] = 888, [5] = 8959, quest = 0 },
	pos = { x = 0, y = 140 },
	locked = true,
	minimap = { hide = false, angle = 200 },
}

local function Fill(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			Fill(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-- Built-in game sounds (sound kit IDs), picked per rarity in the settings window.
LF.SOUNDS = {
	{ id = 0, name = "No sound" },
	{ id = 120, name = "Coins" },
	{ id = 878, name = "Quest complete" },
	{ id = 888, name = "Level up" },
	{ id = 8959, name = "Raid warning" },
	{ id = 8960, name = "Ready check" },
	{ id = 3081, name = "Whisper" },
	{ id = 1115, name = "Click" },
}

LF.ANIMS = {
	{ key = "stack", name = "Stack" },   -- new line pops in, older ones glide up
	{ key = "slide", name = "Slide in" }, -- new line slides in from the left
	{ key = "bounce", name = "Bounce" }, -- new line drops in and bounces
	{ key = "rise", name = "Float up" }, -- every line drifts up on its own as it fades
}

LF.QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }
local QCOL = {
	[0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 },
	{ 0.64, 0.21, 0.93 }, { 1, 0.5, 0 }, { 0.9, 0.8, 0.5 }, { 0, 0.8, 1 },
}
local QUEST_COL = { 1, 0.82, 0 }
local HEXQ = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7 }
function LF.QualityColor(q) local c = QCOL[q] or QCOL[1]; return c[1], c[2], c[3] end

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Num(v) return type(v) == "number" and not Secret(v) and v or nil end
local function Str(v) return type(v) == "string" and not Secret(v) and v or nil end

------------------------------------------------------------------------
-- Display: a holder at the anchor, a pool of line frames, one OnUpdate
------------------------------------------------------------------------
local SPACING, POP, FADE, SWEEP, SWEEP_GAP, RISE = 30, 0.2, 0.6, 0.55, 1.1, 32
local holder = CreateFrame("Frame", "LootFlareAnchor", UIParent)
holder:SetSize(240, 30)
holder:SetMovable(true)
holder:SetClampedToScreen(true)
holder:RegisterForDrag("LeftButton")
holder:SetScript("OnDragStart", holder.StartMoving)
holder:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local cx, cy = self:GetCenter()
	local px, py = UIParent:GetCenter()
	local s = self:GetScale()
	LF.db.pos.x = floor(cx - px / s + 0.5)
	LF.db.pos.y = floor(cy - py / s + 0.5)
	LF.ApplyLook()
end)
local box = holder:CreateTexture(nil, "BACKGROUND")
box:SetAllPoints()
box:SetColorTexture(0.1, 0.5, 1, 0.35)
local boxText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
boxText:SetPoint("CENTER")
boxText:SetText("Loot Flare - drag me")

local active, pool = {}, {}
local driver = CreateFrame("Frame")
driver:Hide()

local function Band(tex, r, g, b, fromA, toA)
	tex:SetColorTexture(1, 1, 1, 1)
	if CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r, g, b, fromA), CreateColor(r, g, b, toA)) then return end
	if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, "HORIZONTAL", r, g, b, fromA, r, g, b, toA) then return end
	tex:SetColorTexture(r, g, b, 0.3)
end

local function NewLine()
	local l = CreateFrame("Frame", nil, holder)
	l:SetSize(200, 26)
	l.bandL = l:CreateTexture(nil, "BACKGROUND")
	l.bandL:SetPoint("RIGHT", l, "CENTER")
	l.bandR = l:CreateTexture(nil, "BACKGROUND")
	l.bandR:SetPoint("LEFT", l, "CENTER")
	l.icon = l:CreateTexture(nil, "ARTWORK")
	l.icon:SetSize(24, 24)
	l.icon:SetPoint("LEFT")
	l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	l.border = l:CreateTexture(nil, "OVERLAY")
	l.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	l.border:SetBlendMode("ADD")
	l.border:SetSize(46, 46)
	l.border:SetPoint("CENTER", l.icon)
	l.badge = l:CreateTexture(nil, "OVERLAY", nil, 2)
	l.badge:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	l.badge:SetSize(14, 14)
	l.badge:SetPoint("TOPLEFT", l.icon, "TOPLEFT", -5, 5)
	l.text = l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	l.text:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
	l.text:SetShadowOffset(1, -1)
	l.extra = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	l.extra:SetPoint("LEFT", l.text, "RIGHT", 6, 0)
	l.spark = l:CreateTexture(nil, "OVERLAY")
	l.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	l.spark:SetBlendMode("ADD")
	l.spark:SetSize(28, 52)
	l.stars = {}
	for i = 1, 4 do
		local s = l:CreateTexture(nil, "OVERLAY")
		s:SetTexture("Interface\\Cooldown\\star4")
		s:SetBlendMode("ADD")
		s:SetSize(18, 18)
		l.stars[i] = s
	end
	return l
end

local function Measure(l)
	local w = 30 + (l.text:GetStringWidth() or 0)
	local ex = l.extra:GetText()
	if ex and ex ~= "" then w = w + 6 + (l.extra:GetStringWidth() or 0) end
	l.w = w
	l:SetWidth(w)
	l.bandL:SetSize(w / 2 + 30, 24)
	l.bandR:SetSize(w / 2 + 30, 24)
end

local function Render(l)
	local text, extra = l.label(l.count, l)
	l.text:SetText(text)
	l.extra:SetText(extra or "")
	Measure(l)
end

local function Layout()
	local dir = LF.db.growUp and 1 or -1
	for i, l in ipairs(active) do l.ty = (i - 1) * SPACING * dir end
end

-- Lines in "Float up" drift on their own; keep each one at least a line above the newer one.
local function RisePositions()
	local prev
	for _, l in ipairs(active) do
		local m = l.t * RISE + l.boost
		if prev and m < prev + SPACING then
			l.boost = l.boost + (prev + SPACING - m)
			m = prev + SPACING
		end
		l.rise = m
		prev = m
	end
end

local function Bounce(p) -- 0..1 -> 0..1, lands with two small bounces
	if p < 1 / 2.75 then return 7.5625 * p * p
	elseif p < 2 / 2.75 then p = p - 1.5 / 2.75; return 7.5625 * p * p + 0.75
	elseif p < 2.5 / 2.75 then p = p - 2.25 / 2.75; return 7.5625 * p * p + 0.9375
	end
	p = p - 2.625 / 2.75
	return 7.5625 * p * p + 0.984375
end

local function Effects(l, t)
	-- shine sweeping left to right across the line
	local sweeps = l.fx == 1 and 1 or (l.fx == 2 and 2 or 1e9)
	local st = t - 0.15
	local n = floor(st / SWEEP_GAP)
	local p = (st - n * SWEEP_GAP) / SWEEP
	if st > 0 and n < sweeps and p < 1 then
		l.spark:ClearAllPoints()
		l.spark:SetPoint("CENTER", l, "LEFT", l.w * p, 0)
		l.spark:SetAlpha(sin(p * pi))
		l.spark:Show()
	else
		l.spark:Hide()
	end
	-- glow behind the line (pulses on epic and better)
	local g = 0.45
	if l.fx >= 2 then g = 0.35 + 0.2 * sin(t * 5) end
	l.bandL:SetAlpha(g)
	l.bandR:SetAlpha(g)
	l.border:SetAlpha(l.fx >= 2 and (0.7 + 0.3 * sin(t * 5)) or 0.9)
	-- twinkling stars circling the icon
	if l.fx >= 2 then
		local fade = l.fx >= 3 and 1 or max(0, min(1, (3 - t) / 0.5))
		for i, s in ipairs(l.stars) do
			local a = t * 2.2 + i * (pi / 2)
			s:ClearAllPoints()
			s:SetPoint("CENTER", l.icon, "CENTER", cos(a) * 17, sin(a) * 17)
			s:SetAlpha(fade * (0.5 + 0.5 * sin(t * 7 + i * 1.7)))
			s:Show()
		end
	end
end

local function Step(l, dt)
	l.t = l.t + dt
	local t = l.t
	local anim = LF.db.anim
	local dir = LF.db.growUp and 1 or -1
	local x, yo = 0, 0
	if anim == "rise" then
		l.y = (l.rise or 0) * dir
	else
		l.y = l.y + (l.ty - l.y) * min(1, dt * 10)
	end
	local s = 1
	if anim == "slide" then
		if t < 0.35 then local p = 1 - t / 0.35; x = -170 * p * p * p end
	elseif anim == "bounce" then
		if t < 0.65 then yo = 55 * (1 - Bounce(t / 0.65)) end
	elseif t < POP then
		local p = 1 - t / POP
		s = 1 + (l.pop - 1) * p * p * p
	end
	if l.pulse then
		l.pulse = l.pulse + dt
		if l.pulse < 0.25 then s = s * (1 + 0.15 * (1 - l.pulse / 0.25)) else l.pulse = nil end
	end
	l:SetScale(s)
	l:ClearAllPoints()
	l:SetPoint("CENTER", holder, "CENTER", x / s, (l.y + yo) / s)
	local a = 1
	local fadeIn = anim == "slide" and 0.25 or 0.12
	if t < fadeIn then a = t / fadeIn elseif t > l.life - FADE then a = max(0, (l.life - t) / FADE) end
	l:SetAlpha(a)
	if l.fx >= 1 then Effects(l, t) end
	return t >= l.life
end

local function Release(l)
	l:Hide()
	l.key = nil
	pool[#pool + 1] = l
end

driver:SetScript("OnUpdate", function(self, dt)
	if LF.db.anim == "rise" then
		for _, l in ipairs(active) do l.t = l.t + dt end
		RisePositions()
		for _, l in ipairs(active) do l.t = l.t - dt end
	end
	local i = 1
	local removed = false
	while i <= #active do
		if Step(active[i], dt) then
			Release(table.remove(active, i))
			removed = true
		else
			i = i + 1
		end
	end
	if removed then Layout() end
	if #active == 0 then self:Hide() end
end)

local lastSound = {}
local function PlayFor(key)
	local id = LF.db.sounds[key]
	if not id or id == 0 then return false end
	local now = GetTime()
	if lastSound[key] and now - lastSound[key] < 0.3 then return true end
	lastSound[key] = now
	pcall(PlaySound, id, "Master")
	return true
end
LF.PlaySoundID = function(id) if id and id ~= 0 then pcall(PlaySound, id, "Master") end end

-- Turns a line into a quest line: gold name, "!" badge, gold glow with one shine.
local function QuestStyle(l)
	if l.quest then return end
	l.quest = true
	l.text:SetTextColor(QUEST_COL[1], QUEST_COL[2], QUEST_COL[3])
	l.badge:Show()
	if LF.db.fancy and l.fx == 0 then
		l.fx = 1
		Band(l.bandL, QUEST_COL[1], QUEST_COL[2], QUEST_COL[3], 0, 1)
		Band(l.bandR, QUEST_COL[1], QUEST_COL[2], QUEST_COL[3], 1, 0)
		l.bandL:Show(); l.bandR:Show()
		l.border:SetVertexColor(QUEST_COL[1], QUEST_COL[2], QUEST_COL[3])
		l.border:Show()
		if l.t > 0.15 then l.t = 0.15 end -- so its shine still plays
		l.life = max(l.life, LF.db.duration * 1.3)
	end
end
LF.QuestStyle = QuestStyle

-- e = { key, icon, q, count, label = function(count, line) return text, extra end,
--       color = {r,g,b}, isItem = bool, quest = bool, sound = bool }
function LF.Add(e)
	if not LF.db or not LF.db.enabled then return end
	local anim = LF.db.anim
	if e.key then
		for _, l in ipairs(active) do
			if l.key == e.key and l.t < l.life - FADE then
				l.count = l.count + (e.count or 1)
				if anim == "rise" then l.boost = l.boost + max(0, l.t - POP) * RISE end
				l.t = min(l.t, POP)
				l.pulse = 0
				Render(l)
				return l
			end
		end
	end
	local l = table.remove(pool) or NewLine()
	local q = e.q or 1
	l.key, l.label, l.count, l.q, l.name = e.key, e.label, e.count or 1, q, e.name
	l.t, l.y, l.pulse, l.boost, l.rise = 0, 0, nil, 0, 0
	l.bags, l.ilvl, l.qdone, l.qneed, l.quest = nil, nil, nil, nil, nil
	l.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	local r, g, b
	if e.color then r, g, b = e.color[1], e.color[2], e.color[3] else r, g, b = LF.QualityColor(q) end
	l.text:SetTextColor(r, g, b)
	local fancy = LF.db.fancy and e.isItem
	l.fx = (fancy and q >= 3) and min(3, q - 2) or 0
	l.pop = l.fx >= 2 and 1.6 or (l.fx == 1 and 1.4 or 1.15)
	l.life = LF.db.duration * (l.fx >= 2 and 1.75 or (l.fx == 1 and 1.3 or 1))
	Band(l.bandL, r, g, b, 0, 1)
	Band(l.bandR, r, g, b, 1, 0)
	l.bandL:SetShown(l.fx >= 1)
	l.bandR:SetShown(l.fx >= 1)
	l.border:SetVertexColor(r, g, b)
	l.border:SetShown(e.isItem and q >= 2)
	l.border:SetAlpha(0.9)
	l.badge:Hide()
	l.spark:Hide()
	for _, s in ipairs(l.stars) do s:Hide() end
	if e.quest then QuestStyle(l) end
	Render(l)
	table.insert(active, 1, l)
	-- too many lines: the oldest fade out quickly, and past a hard cap they go at once
	while #active > LF.db.maxLines + 4 do Release(table.remove(active)) end
	for i = LF.db.maxLines + 1, #active do
		local old = active[i]
		if old.t < old.life - 0.3 then old.life = old.t + 0.3 end
	end
	-- new line starts at the anchor; older lines glide to their new slots
	Layout()
	if anim == "rise" then RisePositions() end
	l.y = 0
	Step(l, 0)
	l:Show()
	driver:Show()
	if e.sound ~= false and e.isItem then
		if not (l.quest and PlayFor("quest")) then PlayFor(q) end
	end
	return l
end

------------------------------------------------------------------------
-- Turning chat lines into loot
------------------------------------------------------------------------
local function ToPattern(fmt)
	fmt = fmt:gsub("%%(%d)%$([sd])", "%%%2")
	fmt = fmt:gsub("%%s", "\001"):gsub("%%d", "\002")
	fmt = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	fmt = fmt:gsub("\001", "(.-)"):gsub("\002", "(%%d+)")
	return "^" .. fmt .. "$"
end
LF.ToPattern = ToPattern

local ITEM_KEYS = {
	"LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
	"LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF",
}
local ITEM_FALLBACK = {
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.", LOOT_ITEM_SELF = "You receive loot: %s.",
	LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d.", LOOT_ITEM_PUSHED_SELF = "You receive item: %s.",
	LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d.", LOOT_ITEM_CREATED_SELF = "You create: %s.",
}
local CUR_KEYS = { "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED" }
local CUR_FALLBACK = { CURRENCY_GAINED_MULTIPLE = "You receive currency: %s x%d.", CURRENCY_GAINED = "You receive currency: %s." }
local itemPats, curPats = {}, {}

local function Build(keys, fallback, out)
	for _, k in ipairs(keys) do
		local f = _G[k] or fallback[k]
		if type(f) == "string" and not Secret(f) then out[#out + 1] = ToPattern(f) end
	end
end

local function Match(msg, pats)
	for _, p in ipairs(pats) do
		local a, b = msg:match(p)
		if a then return a, tonumber(b) or 1 end
	end
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local NO_ILVL = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true,
	INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_TABARD = true, INVTYPE_BODY = true }

local function LinkQuality(link)
	local q = link:match("|cnIQ(%d+):")
	if q then return tonumber(q) end
	local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
	return hex and HEXQ[hex:lower()]
end

-- "Bear Pelt: 3/8" in your quest log -> 3, 8 (nil when no quest wants this item)
function LF.QuestProgress(name)
	local Q = C_QuestLog
	if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.GetQuestObjectives) then return nil end
	local ok, n = pcall(Q.GetNumQuestLogEntries)
	n = ok and Num(n)
	if not n then return nil end
	for i = 1, n do
		local okI, info = pcall(Q.GetInfo, i)
		if okI and type(info) == "table" and not info.isHeader and Num(info.questID) then
			local okO, objs = pcall(Q.GetQuestObjectives, info.questID)
			if okO and type(objs) == "table" then
				for _, o in ipairs(objs) do
					local text = Str(o.text)
					local have, need = Num(o.numFulfilled), Num(o.numRequired)
					if text and have and need and need > 0 and text:find(name, 1, true) then return have, need end
				end
			end
		end
	end
end

local function ItemLabel(n, l)
	local db, parts = LF.db, {}
	if n > 1 then parts[#parts + 1] = "|cffffffffx" .. n .. "|r" end
	if l.qneed then
		parts[#parts + 1] = l.qdone >= l.qneed and "|cff33ff33Done!|r" or ("|cffffd100" .. l.qdone .. "/" .. l.qneed .. "|r")
	end
	if db.ilvl and l.ilvl then parts[#parts + 1] = "|cffc8c8c8ilvl " .. l.ilvl .. "|r" end
	if db.bagCount and l.bags and l.bags > n and not l.qneed then parts[#parts + 1] = "|cff9a9a9a(" .. l.bags .. ")|r" end
	return l.name, table.concat(parts, " ")
end

-- Fills in item level, quest progress and bag count (item info can arrive a moment later).
local function Details(l, link, id, equipLoc)
	local db = LF.db
	if db.ilvl and GetInfo and equipLoc and not NO_ILVL[equipLoc] then
		local ok, _, _, _, lvl = pcall(GetInfo, link)
		if ok then l.ilvl = Num(lvl) and lvl > 1 and lvl or l.ilvl end
	end
	if db.quest then
		local have, need = LF.QuestProgress(l.name)
		if have then l.qdone, l.qneed = have, need; QuestStyle(l) end
	end
	if db.bagCount and id and GetCount then
		local ok, c = pcall(GetCount, id)
		if ok and Num(c) then l.bags = c end
	end
end

function LF.ShowItem(link, count, sound)
	local db = LF.db
	if not db.items then return end
	local name = link:match("%[(.-)%]") or link
	local q
	if GetInfo then q = select(3, GetInfo(link)) end
	q = Num(q) or LinkQuality(link) or 1
	local id, icon, equipLoc, classID
	if GetInstant then
		local r1, _, _, r4, r5, r6 = GetInstant(link)
		id, equipLoc, icon, classID = r1, r4, r5, r6
	end
	local isQuest = db.quest and classID == QUEST_CLASS
	if q < db.minQuality and not isQuest then return end
	local l = LF.Add({ key = "item:" .. (id or name), icon = icon, q = q, count = count, isItem = true,
		quest = isQuest, sound = sound, label = ItemLabel, name = name })
	if not l then return end
	l.name = name
	Details(l, link, id, equipLoc)
	Render(l)
	if C_Timer then
		C_Timer.After(0.6, function()
			if l.key ~= "item:" .. (id or name) then return end
			local wasQuest = l.quest
			Details(l, link, id, equipLoc)
			Render(l)
			if l.quest and not wasQuest and sound ~= false then PlayFor("quest") end
		end)
	end
end

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
function LF.FormatMoney(c)
	local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. GOLD end
	if s > 0 then out[#out + 1] = s .. SILVER end
	if cp > 0 or #out == 0 then out[#out + 1] = cp .. COPPER end
	return table.concat(out, " ")
end

function LF.ShowMoney(c)
	if not LF.db.money or c <= 0 then return end
	LF.Add({ key = "money", icon = "Interface\\Icons\\INV_Misc_Coin_01", count = c, color = { 1, 0.82, 0 },
		label = function(n) return LF.FormatMoney(n) end })
end

function LF.ShowCurrency(link, count)
	if not LF.db.currency then return end
	local id = tonumber(link:match("currency:(%d+)"))
	local name = link:match("%[(.-)%]") or link
	local icon
	if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
		if ok and type(info) == "table" then icon = info.iconFileID end
	end
	LF.Add({ key = "cur:" .. (id or name), icon = icon, count = count, color = { 0.6, 0.85, 1 },
		label = function(n) return name, n > 1 and ("|cffffffffx" .. n .. "|r") or "" end })
end

function LF.ShowHonor(n)
	if not LF.db.honor or n <= 0 then return end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local icon = faction == "Horde" and "Interface\\TargetingFrame\\UI-PVP-Horde" or "Interface\\TargetingFrame\\UI-PVP-Alliance"
	LF.Add({ key = "honor", icon = icon, count = n, color = { 1, 0.5, 0.3 },
		label = function(c) return "+" .. c .. " Honor" end })
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
Reg("ADDON_LOADED"); Reg("PLAYER_LOGIN")
local lastMoney, busy = nil, {}

local function Init()
	LootFlareDB = LootFlareDB or {}
	Fill(LootFlareDB, DEFAULTS)
	LF.db = LootFlareDB
end

ev:SetScript("OnEvent", function(_, e, a1)
	if e == "ADDON_LOADED" then
		if a1 == "LootFlare" then Init() end
		return
	elseif e == "PLAYER_LOGIN" then
		if not LF.db then Init() end
		Build(ITEM_KEYS, ITEM_FALLBACK, itemPats)
		Build(CUR_KEYS, CUR_FALLBACK, curPats)
		lastMoney = Num(GetMoney and GetMoney())
		for _, x in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_CURRENCY", "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_MONEY",
			"MERCHANT_SHOW", "MERCHANT_CLOSED", "TRADE_SHOW", "TRADE_CLOSED" }) do Reg(x) end
		LF.ApplyLook()
		if LF.UpdateMinimapButton then LF.UpdateMinimapButton() end
		return
	end
	if type(a1) == "string" and Secret(a1) then return end
	if e == "CHAT_MSG_LOOT" then
		if not a1 then return end
		local link, n = Match(a1, itemPats)
		if link then LF.ShowItem(link, n) end
	elseif e == "CHAT_MSG_CURRENCY" then
		if not a1 then return end
		local link, n = Match(a1, curPats)
		if link then LF.ShowCurrency(link, n) end
	elseif e == "CHAT_MSG_COMBAT_HONOR_GAIN" then
		if not a1 then return end
		local last
		for d in a1:gmatch("(%d+)") do last = d end
		if last then LF.ShowHonor(tonumber(last)) end
	elseif e == "PLAYER_MONEY" then
		local m = Num(GetMoney())
		if not m then return end
		if lastMoney and m > lastMoney and not busy.MERCHANT and not busy.TRADE then LF.ShowMoney(m - lastMoney) end
		lastMoney = m
	elseif e == "MERCHANT_SHOW" then busy.MERCHANT = true
	elseif e == "MERCHANT_CLOSED" then busy.MERCHANT = nil
	elseif e == "TRADE_SHOW" then busy.TRADE = true
	elseif e == "TRADE_CLOSED" then busy.TRADE = nil
	end
end)

------------------------------------------------------------------------
-- Look, test, slash command
------------------------------------------------------------------------
function LF.ApplyLook()
	local db = LF.db
	holder:SetScale(db.scale)
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", UIParent, "CENTER", db.pos.x, db.pos.y)
	local unlocked = not db.locked
	holder:EnableMouse(unlocked)
	box:SetShown(unlocked)
	boxText:SetShown(unlocked)
	Layout()
end

function LF.ResetPosition()
	LF.db.pos.x, LF.db.pos.y = DEFAULTS.pos.x, DEFAULTS.pos.y
	LF.ApplyLook()
end

local TEST = {
	{ "Interface\\Icons\\INV_Misc_Bone_01", 0, "Cracked Bone", 3 },
	{ "Interface\\Icons\\INV_Misc_Food_15", 1, "Tough Jerky", 4 },
	{ "Interface\\Icons\\INV_Misc_Pelt_Bear_03", 1, "Bear Pelt", 1, { 3, 8 } },
	{ "Interface\\Icons\\INV_Misc_Herb_07", 2, "Peacebloom", 2 },
	{ "Interface\\Icons\\INV_Sword_04", 3, "Blade of the Test", 1, nil, 18 },
	{ "Interface\\Icons\\INV_Helmet_08", 4, "Crown of Shiny Things", 1, nil, 42 },
	{ "Interface\\Icons\\INV_Staff_13", 5, "Staff of Utter Brilliance", 1, nil, 60 },
}
function LF.Test()
	local wasOn = LF.db.enabled
	local function one(i)
		local t = TEST[i]
		LF.db.enabled = true
		local l = LF.Add({ key = "test" .. i, icon = t[1], q = t[2], count = t[4], isItem = true,
			quest = t[5] ~= nil and LF.db.quest, label = ItemLabel, name = t[3] })
		if l then
			l.ilvl = LF.db.ilvl and t[6] or nil
			if t[5] and LF.db.quest then l.qdone, l.qneed = t[5][1], t[5][2] end
			Render(l)
		end
		if i == 1 then LF.ShowMoney(12345) end
		LF.db.enabled = wasOn
	end
	for i = 1, #TEST do
		if C_Timer then C_Timer.After((i - 1) * 0.5, function() one(i) end) else one(i) end
	end
end

local function Say(m) print("|cffffd100Loot Flare|r: " .. m) end
SLASH_LOOTFLARE1, SLASH_LOOTFLARE2 = "/lootflare", "/lflare"
SlashCmdList.LOOTFLARE = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local db = LF.db
	if msg == "test" then LF.Test()
	elseif msg == "on" then db.enabled = true; Say("on.")
	elseif msg == "off" then db.enabled = false; Say("off.")
	elseif msg == "move" or msg == "lock" then db.locked = not db.locked; LF.ApplyLook(); Say(db.locked and "locked." or "drag the blue box, then /lflare lock.")
	elseif msg == "reset" then LF.ResetPosition(); Say("position reset.")
	elseif msg == "help" then Say("/lflare (settings), test, on, off, move, reset")
	elseif LF.ToggleOptions then LF.ToggleOptions()
	else Say("/lflare test, on, off, move, reset") end
end
