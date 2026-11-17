-- QuestAhead: on Questie's world map icons, see what a quest leads to and where.
-- Hover a quest's "!" or "?" icon: its follow-on quests and where each one starts.
-- Alt-click it: pins at the follow-on quest givers (numbered in chain order), joined by lines.
-- Hover a pin for that quest's details; Alt-click a pin to look one step further.
-- Reads Questie's quest data through Questie's own modules; changes nothing in Questie.
-- by good mens (Mephz on WoW Forever)

local ADDON = ...
local QA = {}
_G.QuestAhead = QA

QA.MAX_CHAIN = 6      -- how far down a chain to follow
QA.MAX_QUESTS = 3     -- quests per tooltip that get a follow-on section
QA.stats = { hooked = false, hovers = 0, shown = 0, errors = 0 } -- for /qahead check
local TAG = "|cff9b6bffQuestAhead|r: "

-- debug lines go to chat and to QuestAheadDB.log (kept across /reload, for reading outside the game)
local function Dbg(msg)
	print(TAG .. msg)
	QuestAheadDB = type(QuestAheadDB) == "table" and QuestAheadDB or {}
	QuestAheadDB.log = type(QuestAheadDB.log) == "table" and QuestAheadDB.log or {}
	local log = QuestAheadDB.log
	log[#log + 1] = (date and date("%H:%M:%S ") or "") .. msg
	while #log > 150 do table.remove(log, 1) end
end
QA.Dbg = Dbg

-- run fn, keeping (not hiding) any error for /qahead check
local function Safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		QA.stats.errors = QA.stats.errors + 1
		QA.stats.lastError = tostring(err)
	end
	return ok
end

local function Mod(name)
	if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
	local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
	if ok then return m end
end

local function DB() return Mod("QuestieDB") end
local function Get(fnName, id, key)
	local db = DB()
	local fn = db and db[fnName]
	if not fn then return nil end
	local ok, v = pcall(fn, id, key)
	if ok then return v end
end
local function Q(id, key) return Get("QueryQuestSingle", id, key) end
local function NPC(id, key) return Get("QueryNPCSingle", id, key) end
local function OBJ(id, key) return Get("QueryObjectSingle", id, key) end
local function ITEM(id, key) return Get("QueryItemSingle", id, key) end

-- What can follow a quest ---------------------------------------------------------------------

function QA.Applicable(id)
	if not Q(id, "name") then return false end
	local corr = Mod("QuestieCorrections")
	if corr and type(corr.hiddenQuests) == "table" and corr.hiddenQuests[id] then return false end
	local char = Questie and Questie.db and Questie.db.char
	if char and type(char.complete) == "table" and char.complete[id] then return false end
	local P = Mod("QuestiePlayer")
	if P then
		if P.HasRequiredRace and not P.HasRequiredRace(Q(id, "requiredRaces")) then return false end
		if P.HasRequiredClass and not P.HasRequiredClass(Q(id, "requiredClasses")) then return false end
	end
	return true
end

-- quest -> quests that need it done first (built once, on first use)
local unlocks
function QA.BuildIndex()
	unlocks = {}
	local db = DB()
	local ptrs = db and db.QuestPointers
	if type(ptrs) ~= "table" then return end
	for id in pairs(ptrs) do
		for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
			local pre = Q(id, key)
			if type(pre) == "table" then
				local group = key == "preQuestGroup" and #pre > 1
				for _, p in ipairs(pre) do
					p = math.abs(p)
					unlocks[p] = unlocks[p] or {}
					table.insert(unlocks[p], { id = id, group = group })
				end
			end
		end
	end
	for _, list in pairs(unlocks) do table.sort(list, function(a, b) return a.id < b.id end) end
end

-- { {id=, kind="next", step=n} ..., {id=, kind="unlock", group=bool} ... }
function QA.Follow(questId)
	local out, seen = {}, { [questId] = true }
	local cur, step = questId, 0
	while step < QA.MAX_CHAIN do
		local n = Q(cur, "nextQuestInChain")
		if type(n) ~= "number" or n <= 0 or seen[n] or not QA.Applicable(n) then break end
		seen[n] = true
		step = step + 1
		out[#out + 1] = { id = n, kind = "next", step = step }
		cur = n
	end
	if not unlocks then QA.BuildIndex() end
	for _, u in ipairs(unlocks[questId] or {}) do
		if not seen[u.id] and QA.Applicable(u.id) then
			seen[u.id] = true
			out[#out + 1] = { id = u.id, kind = "unlock", group = u.group }
		end
	end
	return out
end

-- Where they start ------------------------------------------------------------------------------

local function FirstSpot(spawns, prefArea)
	if type(spawns) ~= "table" then return nil end
	local function ok(list) return type(list) == "table" and list[1] and (list[1][1] or -1) >= 0 end
	if prefArea and ok(spawns[prefArea]) then return prefArea, spawns[prefArea][1] end
	local areas = {}
	for a, list in pairs(spawns) do if ok(list) then areas[#areas + 1] = a end end
	table.sort(areas)
	if areas[1] then return areas[1], spawns[areas[1]][1] end
end

-- { kind = "npc"|"object"|"item", id, name, area?, x?, y? (0-100) }
function QA.Starter(questId, prefArea)
	local sb = Q(questId, "startedBy")
	if type(sb) ~= "table" then return nil end
	for _, src in ipairs({ { "npc", sb[1], NPC }, { "object", sb[2], OBJ } }) do
		for _, eid in ipairs(src[2] or {}) do
			local area, pt = FirstSpot(src[3](eid, "spawns"), prefArea)
			if area then
				return { kind = src[1], id = eid, name = src[3](eid, "name"), area = area, x = pt[1], y = pt[2] }
			end
		end
	end
	if type(sb[3]) == "table" and sb[3][1] then
		return { kind = "item", id = sb[3][1], name = ITEM(sb[3][1], "name") }
	end
	if type(sb[1]) == "table" and sb[1][1] then
		return { kind = "npc", id = sb[1][1], name = NPC(sb[1][1], "name") }
	end
end

function QA.ZoneName(area)
	local Z = Mod("ZoneDB")
	local map = Z and Z.GetUiMapIdByAreaId and Z:GetUiMapIdByAreaId(area)
	local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name or "another zone"
end

local function Has(list, v)
	for _, x in ipairs(type(list) == "table" and list or {}) do if x == v then return true end end
	return false
end

-- text + colour for where questId starts, seen from fromQuest's icon in hereArea
function QA.Where(questId, fromQuest, hereArea)
	local st = QA.Starter(questId, hereArea)
	if not st then return "start unknown", 0.6, 0.6, 0.6 end
	if st.kind == "item" then return "from an item: " .. (st.name or "?"), 0.8, 0.6, 1 end
	local fin = Q(fromQuest, "finishedBy")
	if type(fin) == "table" and Has(fin[st.kind == "npc" and 1 or 2], st.id) then
		return "same NPC", 0.3, 1, 0.3
	end
	local who = st.name or "?"
	if not st.area then return who .. ", location unknown", 0.6, 0.6, 0.6 end
	if st.area == hereArea then return who .. ", here", 1, 1, 1 end
	return who .. ", " .. QA.ZoneName(st.area), 1, 0.6, 0.2
end
function QA.WhereText(questId, fromQuest, hereArea) return (QA.Where(questId, fromQuest, hereArea)) end

local function Title(id)
	local lvl = Q(id, "questLevel")
	return (Q(id, "name") or ("Quest " .. id)) .. ((type(lvl) == "number" and lvl > 0) and (" (" .. lvl .. ")") or "")
end

-- Map tooltip -------------------------------------------------------------------------------------

-- only a quest's own icons (pick-up "!" and hand-in "?"), not its objective markers
function QA.IsQuestIcon(icon)
	local t = icon and icon.data and icon.data.Type
	return t == "available" or t == "complete"
end

local function TooltipQuests(tt)
	local set, list = {}, {}
	local function add(id) if type(id) == "number" and not set[id] then set[id] = true; list[#list + 1] = id end end
	local owner = tt._owner
	if not QA.IsQuestIcon(owner) then return list end
	add(owner.data.Id)
	local rest = {}
	for _, quests in pairs(type(tt.npcAndObjectOrder) == "table" and tt.npcAndObjectOrder or {}) do
		for _, qd in pairs(quests) do if type(qd) == "table" then rest[#rest + 1] = qd.questId end end
	end
	table.sort(rest, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
	for _, id in ipairs(rest) do add(id) end
	return list
end

function QA.AddTooltip(tt)
	local owner = tt._owner
	local here = owner and owner.AreaID
	local list = TooltipQuests(tt)
	if #list == 0 then return end
	tt:AddLine(" ")
	local any = false
	for i, qid in ipairs(list) do
		if i > QA.MAX_QUESTS then break end
		local f = QA.Follow(qid)
		if #f > 0 then
			any = true
			tt:AddLine("Leads to (after " .. (Q(qid, "name") or qid) .. "):", 1, 0.82, 0)
			for _, e in ipairs(f) do
				local left = (e.kind == "next" and ("  " .. e.step .. ". ") or "  + ") .. Title(e.id)
				if e.group then left = left .. " |cff999999(needs other quests too)|r" end
				local w, r, g, b = QA.Where(e.id, qid, here)
				tt:AddDoubleLine(left, w, 1, 1, 1, r, g, b)
			end
		end
	end
	if any then
		tt:AddLine("Alt-click: show follow-ons on the map", 0.55, 0.55, 0.55)
	else
		tt:AddLine("No follow-on quests", 0.55, 0.55, 0.55)
	end
end

-- After Questie builds an icon's tooltip, add ours, and again whenever Questie rebuilds it (Shift)
function QA.OnQuestieTooltip(icon, tt)
	QA.stats.hovers = QA.stats.hovers + 1
	if QA.debug then
		local d = icon and icon.data or {}
		Dbg("hover: type=" .. tostring(d.Type) .. " quest=" .. tostring(d.Id)
			.. " minimap=" .. tostring(icon and icon.miniMapIcon) .. " rebuild=" .. tostring(tt and type(tt._Rebuild)))
	end
	if not tt or not icon or icon.miniMapIcon then return end
	if not icon.__qaHooked and icon.HookScript then
		icon.__qaHooked = true
		icon:HookScript("OnClick", QA.OnIconClick)
	end
	local rb = tt._Rebuild
	if type(rb) ~= "function" or rb == tt.__qaWrapper then return end -- Questie skipped this show
	local wrapper
	wrapper = function(self, ...)
		rb(self, ...)
		if self._Rebuild == wrapper then Safe(QA.AddTooltip, self) end
	end
	tt.__qaWrapper = wrapper
	tt._Rebuild = wrapper
	local before = tt.NumLines and tt:NumLines()
	if Safe(QA.AddTooltip, tt) then QA.stats.shown = QA.stats.shown + 1 end
	if QA.debug then
		local n = #TooltipQuests(tt)
		Dbg("  quests with follow-on checks: " .. n
			.. (QA.stats.lastError and (", last error: " .. QA.stats.lastError) or "")
			.. (before and (", lines " .. before .. " -> " .. tostring(tt:NumLines())) or ""))
	end
	tt:Show()
end

-- Pins --------------------------------------------------------------------------------------------
-- Our pins and lines live on our own layer over the map canvas, not in Questie's pin system, so
-- Questie's own icon handling never meets them.

local pool, spots, lines = {}, {}, {}
local layer

local function Canvas() return WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas() end

local function Layer()
	local canvas = Canvas()
	if not canvas then return nil end
	if not layer then
		layer = CreateFrame("Frame", nil, canvas)
		layer:SetAllPoints(canvas)
		if layer.SetFrameLevel and canvas.GetFrameLevel then layer:SetFrameLevel((canvas:GetFrameLevel() or 0) + 2000) end
	end
	return layer, canvas
end

-- a map point (0-1 on map) as a point on the map being shown, or nil if it isn't on it
local function ShownMapPoint(map, x, y)
	local shown = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	if not shown or not map then return nil end
	if shown == map then return x, y end
	local HBD = Mod("HBD")
	if not (HBD and HBD.TranslateZoneCoordinates) then return nil end
	local ok, tx, ty = pcall(HBD.TranslateZoneCoordinates, HBD, x, y, map, shown, true)
	if ok and tx and ty and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then return tx, ty end
end

local function PinOnEnter(pin)
	local spot = pin.spot
	if not spot then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	for i, e in ipairs(spot.entries) do
		if i > 1 then GameTooltip:AddLine(" ") end
		GameTooltip:AddLine((e.kind == "next" and (e.step .. ". ") or "+ ") .. Title(e.id), 1, 0.82, 0)
		GameTooltip:AddLine("Given by " .. (spot.starter.name or "?") .. " (" .. QA.ZoneName(spot.starter.area) .. ")", 0.8, 0.8, 0.8)
		if e.group then GameTooltip:AddLine("Needs other quests done too", 1, 0.5, 0.3) end
		local obj = Q(e.id, "objectivesText")
		if type(obj) == "table" then
			for _, l in ipairs(obj) do GameTooltip:AddLine(l, 1, 1, 1, true) end
		end
	end
	if #QA.Follow(spot.entries[1].id) > 0 then
		GameTooltip:AddLine("Alt-click: what this leads to", 0.55, 0.55, 0.55)
	end
	GameTooltip:Show()
end

local function PinOnClick(pin, button)
	local spot = pin.spot
	if not spot or button ~= "LeftButton" or not IsAltKeyDown() then return end
	QA.Show(spot.entries[1].id, { map = spot.map, x = spot.x, y = spot.y, area = spot.starter.area })
end

local function NewPin(parent)
	local p = CreateFrame("Button", nil, parent)
	p:SetSize(22, 22)
	p.bg = p:CreateTexture(nil, "ARTWORK")
	p.bg:SetAllPoints()
	p.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	p.bg:SetVertexColor(0.55, 0.3, 0.95, 0.95)
	p.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.label:SetPoint("CENTER", 0, 0)
	p:RegisterForClicks("LeftButtonUp")
	p:SetScript("OnEnter", PinOnEnter)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p:SetScript("OnClick", PinOnClick)
	return p
end

-- place pins and lines for the map being shown
function QA.Redraw()
	for _, l in ipairs(lines) do l:Hide() end
	for _, s in ipairs(spots) do if s.frame then s.frame:Hide() end end
	if not QA.shownFor then return end
	local lay, canvas = Layer()
	if not lay then return end
	local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
	for _, s in ipairs(spots) do
		local x, y = ShownMapPoint(s.map, s.x, s.y)
		if x then
			s.frame = s.frame or table.remove(pool) or NewPin(lay)
			s.frame.spot = s
			s.frame.label:SetText(s.label)
			s.frame:ClearAllPoints()
			s.frame:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
			s.frame:Show()
		end
	end
	if not lay.CreateLine then return end
	local n = 0
	local function seg(a, b)
		if not a or not b then return end
		local x1, y1 = ShownMapPoint(a.map, a.x, a.y)
		local x2, y2 = ShownMapPoint(b.map, b.x, b.y)
		if not (x1 and x2) or (math.abs(x1 - x2) < 0.002 and math.abs(y1 - y2) < 0.002) then return end
		n = n + 1
		local l = lines[n]
		if not l then
			l = lay:CreateLine(nil, "ARTWORK")
			if l.SetThickness then l:SetThickness(3) end
			l:SetColorTexture(0.7, 0.45, 1, 0.65)
			lines[n] = l
		end
		l:SetStartPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
		l:SetEndPoint("TOPLEFT", canvas, x2 * w, -y2 * h)
		l:Show()
	end
	local prev = QA.origin
	for _, sg in ipairs(QA.segments or {}) do
		if sg.kind == "next" then seg(prev, sg.spot); prev = sg.spot or prev
		else seg(QA.origin, sg.spot) end
	end
end

function QA.Clear()
	for _, s in ipairs(spots) do
		if s.frame then s.frame:Hide(); s.frame.spot = nil; pool[#pool + 1] = s.frame end
	end
	spots = {}
	QA.shownFor, QA.origin, QA.segments = nil, nil, nil
	for _, l in ipairs(lines) do l:Hide() end
end

-- the pins now placed: { map, x, y (0-1), frame?, entries, starter, label }
function QA.PinSpots() return spots end

-- origin = { map, x, y (0-1), area }
function QA.Show(questId, origin)
	QA.Clear()
	local Z = Mod("ZoneDB")
	if not (Z and Z.GetUiMapIdByAreaId) then return end
	local byspot, segments = {}, {}
	for _, e in ipairs(QA.Follow(questId)) do
		local st = QA.Starter(e.id, origin and origin.area)
		local map = st and st.area and Z:GetUiMapIdByAreaId(st.area)
		local spot
		if map then
			local x, y = st.x / 100, st.y / 100
			local key = map .. ":" .. x .. ":" .. y
			spot = byspot[key]
			if not spot then
				spot = { map = map, x = x, y = y, starter = st, entries = {} }
				byspot[key] = spot
				spots[#spots + 1] = spot
			end
			table.insert(spot.entries, e)
			local labels = {}
			for _, pe in ipairs(spot.entries) do labels[#labels + 1] = pe.kind == "next" and tostring(pe.step) or "+" end
			spot.label = table.concat(labels, ",")
		end
		segments[#segments + 1] = { kind = e.kind, spot = spot }
	end
	if #spots == 0 then
		print("|cff9b6bffQuestAhead|r: no map spot known for what " .. (Q(questId, "name") or "that quest") .. " leads to.")
		return
	end
	QA.shownFor, QA.origin, QA.segments = questId, origin, segments
	QA.Redraw()
end

function QA.OnIconClick(icon, button)
	if button ~= "LeftButton" or not IsAltKeyDown() then return end
	if icon.miniMapIcon or not QA.IsQuestIcon(icon) or type(icon.data.Id) ~= "number" then return end
	local id = icon.data.Id
	if QA.shownFor == id then QA.Clear(); return end
	QA.Show(id, { map = icon.UiMapID, x = (icon.x or 0) / 100, y = (icon.y or 0) / 100, area = icon.AreaID })
end

-- Start-up ----------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	local MIT = Mod("MapIconTooltip")
	if not (MIT and type(MIT.ShowOnTooltip) == "function") then
		print(TAG .. "needs Questie, which isn't loaded.")
		return
	end
	hooksecurefunc(MIT, "ShowOnTooltip", QA.OnQuestieTooltip)
	-- debug: note every tooltip shown while the map is open, whoever owns it
	if GameTooltip and GameTooltip.HookScript then
		GameTooltip:HookScript("OnShow", function(tt)
			if not QA.debug or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
			local o = tt.GetOwner and tt:GetOwner()
			local name = o and ((o.GetDebugName and o:GetDebugName()) or (o.GetName and o:GetName())) or "?"
			local first = _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
			Dbg("tooltip: owner=" .. tostring(name) .. " questie=" .. tostring(o and o.data ~= nil)
				.. " first line=" .. tostring(first))
		end)
	end
	QA.stats.hooked = true
	print(TAG .. "on. Hover a quest's ! or ? on the world map to see what it leads to; Alt-click it to pin them. /qahead")
	if WorldMapFrame then
		WorldMapFrame:HookScript("OnHide", QA.Clear)
		if type(WorldMapFrame.OnMapChanged) == "function" then hooksecurefunc(WorldMapFrame, "OnMapChanged", QA.Redraw) end
	end
end)

function QA.Check()
	local st = QA.stats
	if not (QuestieLoader and QuestieLoader.ImportModule) then
		print(TAG .. "Questie isn't loaded, so there is nothing to add to.")
		return
	end
	local MIT = Mod("MapIconTooltip")
	print(TAG .. "Questie's map tooltip " .. ((MIT and type(MIT.ShowOnTooltip) == "function") and "found" or "NOT found")
		.. "; " .. (st.hooked and "hooked" or "NOT hooked") .. ".")
	print(TAG .. "map icon hovers seen: " .. st.hovers .. ", follow-on sections added: " .. st.shown .. ", errors: " .. st.errors)
	if st.lastError then print(TAG .. "last error: " .. st.lastError) end
	local db = DB()
	local n = 0
	if db and type(db.QuestPointers) == "table" then for _ in pairs(db.QuestPointers) do n = n + 1 end end
	print(TAG .. "quests in Questie's data: " .. n)
end

SLASH_QUESTAHEAD1 = "/qahead"
SlashCmdList.QUESTAHEAD = function(msg)
	msg = (msg or ""):lower()
	if msg == "clear" then QA.Clear(); return end
	if msg == "check" then QA.Check(); return end
	if msg == "debug" then
		QA.debug = not QA.debug
		if QA.debug then QuestAheadDB = QuestAheadDB or {}; QuestAheadDB.log = {} end
		print(TAG .. "debug " .. (QA.debug and "on: each map icon hover is reported in chat." or "off."))
		return
	end
	print("|cff9b6bffQuestAhead|r: hover a quest's ! (pick-up) or ? (hand-in) icon on the world map to see what it leads to and where. "
		.. "Alt-click the icon to pin the follow-on givers; hover a pin for details, Alt-click a pin to look further. "
		.. "/qahead clear removes the pins. /qahead check if nothing happens.")
end
