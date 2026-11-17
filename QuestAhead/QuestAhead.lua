-- QuestAhead: on Questie's world map icons, see what a quest leads to and where.
-- Hover a quest's "!" or "?" icon: its follow-on quests and where each one starts.
-- Alt-click it: pins at the givers of the whole chain (numbered by step), joined by lines, and
-- markers where each step's work is.
-- Hover a pin for that quest's details; Alt-click a pin to look one step further.
-- Reads Questie's quest data through Questie's own modules; changes nothing in Questie.
-- by good mens (Mephz on WoW Forever)

local ADDON = ...
local QA = {}
_G.QuestAhead = QA

QA.MAX_CHAIN = 6      -- how many steps down a chain to follow
QA.MAX_FOLLOW = 12    -- most follow-on quests shown for one quest
QA.MAX_QUESTS = 3     -- quests per tooltip that get a follow-on section
QA.MAX_READD = 20     -- times our lines are put back on one tooltip owner
QA.MAX_AREAS = 6      -- objective area markers per follow-on quest
QA.AREA_CELL = 0.08   -- spawns closer than this (share of the map) make one area
QA.stats = { hooked = false, hovers = 0, shown = 0, errors = 0 } -- for /qahead check
local TAG = "|cff9b6bffQuestAhead|r: "

-- a colour per step: orange, green, blue, pink, yellow, red (then round again)
QA.STEP_COLORS = {
	{ 1, 0.6, 0.2 }, { 0.3, 0.9, 0.3 }, { 0.25, 0.7, 1 }, { 1, 0.4, 0.75 }, { 1, 0.9, 0.2 }, { 1, 0.3, 0.25 },
}
function QA.StepColor(step)
	local c = QA.STEP_COLORS[((step or 1) - 1) % #QA.STEP_COLORS + 1]
	return c[1], c[2], c[3]
end
function QA.StepText(step, text)
	local r, g, b = QA.StepColor(step)
	return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), text or tostring(step))
end

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
-- The whole chain after a quest, however Questie links it: "next in chain" and "needs this done
-- first", followed at every step, nearest first.
-- { {id=, step=n (steps away), parent=quest it follows, kind="next"|"unlock", group=bool}, ... }
function QA.Follow(questId)
	if not unlocks then QA.BuildIndex() end
	local out, seen = {}, { [questId] = true }
	local queue, head = { { id = questId, step = 0 } }, 1
	while queue[head] and #out < QA.MAX_FOLLOW do
		local cur = queue[head]
		head = head + 1
		if cur.step < QA.MAX_CHAIN then
			local kids = {}
			local n = Q(cur.id, "nextQuestInChain")
			if type(n) == "number" and n > 0 then kids[#kids + 1] = { id = n, kind = "next" } end
			for _, u in ipairs(unlocks[cur.id] or {}) do kids[#kids + 1] = { id = u.id, kind = "unlock", group = u.group } end
			for _, k in ipairs(kids) do
				if #out >= QA.MAX_FOLLOW then break end
				if not seen[k.id] and QA.Applicable(k.id) then
					seen[k.id] = true
					local e = { id = k.id, kind = k.kind, group = k.group, step = cur.step + 1, parent = cur.id }
					out[#out + 1] = e
					queue[#queue + 1] = e
				end
			end
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
	QA.AddSection(tt, TooltipQuests(tt), owner and owner.AreaID)
end

QA.TAIL_ANY = "Alt-click: show follow-ons on the map"
QA.TAIL_NONE = "No follow-on quests"

-- the "Leads to" lines for these quests, seen from area here
function QA.AddSection(tt, list, here)
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
				local left = "  " .. string.rep("  ", e.step - 1) .. QA.StepText(e.step, e.step .. ".") .. " " .. Title(e.id)
				if e.group then left = left .. " |cff999999(needs other quests too)|r" end
				local w, r, g, b = QA.Where(e.id, qid, here)
				tt:AddDoubleLine(left, w, 1, 1, 1, r, g, b)
			end
		end
	end
	tt:AddLine(any and QA.TAIL_ANY or QA.TAIL_NONE, 0.55, 0.55, 0.55)
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

-- The game's own quest markers on the map, and the map's quest list ------------------------------

local function ShownArea()
	local Z = Mod("ZoneDB")
	local map = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	return map, (map and Z and Z.GetAreaIdByUiMapId and Z:GetAreaIdByUiMapId(map)) or nil
end

-- the quest a frame stands for (a map quest marker, a quest list row), or nil
function QA.OwnerQuestId(o)
	if type(o) ~= "table" then return nil end
	local id = o.questID or o.questId or (type(o.info) == "table" and o.info.questID)
	if type(id) == "number" and id > 0 then return id end
	local idx = o.questLogIndex
	if type(idx) == "number" and C_QuestLog and C_QuestLog.GetInfo then
		local ok, info = pcall(C_QuestLog.GetInfo, idx)
		if ok and type(info) == "table" and type(info.questID) == "number" and info.questID > 0 then return info.questID end
	end
end

-- where a quest is handed in, in this area if it can be (for lines from a quest list row)
function QA.FinisherSpot(questId, area)
	local fin = Q(questId, "finishedBy")
	if type(fin) ~= "table" then return nil end
	for _, src in ipairs({ { fin[1], NPC }, { fin[2], OBJ } }) do
		for _, eid in ipairs(src[1] or {}) do
			local a, pt = FirstSpot(src[2](eid, "spawns"), area)
			if a then return a, pt[1], pt[2] end
		end
	end
end

-- is our section the tooltip's last line (still there)?
local function LineText(tt, i)
	local name = tt.GetName and tt:GetName()
	local fs = name and _G[name .. "TextLeft" .. i]
	local t = fs and fs.GetText and fs:GetText()
	return type(t) == "string" and t or nil
end

-- are our lines anywhere in the tooltip? (other add-ons may add lines after ours)
local function HasOurs(tt)
	local n = tt.NumLines and tt:NumLines() or 0
	for i = 1, n do
		local t = LineText(tt, i)
		if t == QA.TAIL_ANY or t == QA.TAIL_NONE then return true end
	end
	return false
end

-- is this the quest's own tooltip (its first line names the quest), not e.g. a reward item's?
local function IsQuestTooltip(tt, qid)
	local name = Q(qid, "name")
	local first = LineText(tt, 1)
	if type(name) ~= "string" or not first then return false end
	first = first:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return first:find(name, 1, true) ~= nil
end

local adding
-- The game redraws its quest markers' tooltips after showing them, which drops our lines, so this
-- runs on every tooltip show and every frame while the map is open, and puts them back if missing.
function QA.OnAnyTooltip(tt)
	if adding or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	if not (tt and tt.IsShown and tt:IsShown()) then return end
	local o = tt.GetOwner and tt:GetOwner()
	if not o or o.data then return end -- Questie's own icons are handled by OnQuestieTooltip
	local qid = QA.OwnerQuestId(o)
	if not qid or HasOurs(tt) or not IsQuestTooltip(tt, qid) then return end
	if not o.__qaHooked and o.HookScript then
		o.__qaHooked = true
		o:HookScript("OnMouseUp", QA.OnMarkerClick)
	end
	-- a tooltip the game keeps wiping gets our lines back only so many times (never a runaway)
	if tt.__qaOwner ~= o then tt.__qaOwner, tt.__qaAdds = o, 0 end
	if tt.__qaAdds >= QA.MAX_READD then return end
	tt.__qaAdds = tt.__qaAdds + 1
	local _, here = ShownArea()
	adding = true
	Safe(QA.AddSection, tt, { qid }, here)
	tt:Show()
	adding = false
	QA.stats.shown = QA.stats.shown + 1
end

function QA.Watch() if GameTooltip then Safe(QA.OnAnyTooltip, GameTooltip) end end

function QA.OnMarkerClick(o, button)
	if button ~= "LeftButton" or not IsAltKeyDown() then return end
	local qid = QA.OwnerQuestId(o)
	if not qid then return end
	if QA.shownFor == qid then QA.Clear(); return end
	local map, here = ShownArea()
	local origin
	if type(o.normalizedX) == "number" and type(o.normalizedY) == "number" then
		origin = { map = map, x = o.normalizedX, y = o.normalizedY, area = here }
	else
		local a, x, y = QA.FinisherSpot(qid, here)
		local Z = Mod("ZoneDB")
		local m = a and Z and Z.GetUiMapIdByAreaId and Z:GetUiMapIdByAreaId(a)
		origin = m and { map = m, x = x / 100, y = y / 100, area = a } or { area = here }
	end
	QA.Show(qid, origin)
end

-- Where a quest's work is (its objectives) ------------------------------------------------------

-- { {kind = "npc"|"object", id, what = "kill"|"use"|"drops <item>"|"<item>"}, ... }
function QA.ObjectiveSources(questId)
	local out, seen = {}, {}
	local function add(kind, id, what)
		local key = kind .. ":" .. tostring(id)
		if type(id) == "number" and not seen[key] then seen[key] = true; out[#out + 1] = { kind = kind, id = id, what = what } end
	end
	local ob = Q(questId, "objectives")
	if type(ob) ~= "table" then ob = {} end
	for _, o in ipairs(type(ob[1]) == "table" and ob[1] or {}) do add("npc", o[1], "kill") end
	for _, o in ipairs(type(ob[2]) == "table" and ob[2] or {}) do add("object", o[1], "use") end
	for _, o in ipairs(type(ob[3]) == "table" and ob[3] or {}) do
		local item = o[1]
		local iname = ITEM(item, "name") or "the item"
		for _, n in ipairs(ITEM(item, "npcDrops") or {}) do add("npc", n, "drops " .. iname) end
		for _, n in ipairs(ITEM(item, "objectDrops") or {}) do add("object", n, iname) end
		-- items that come out of another item (a crate, a bag): where that one comes from
		for _, c in ipairs(ITEM(item, "itemDrops") or {}) do
			local cname = ITEM(c, "name") or "a container"
			local what = cname .. " (has " .. iname .. ")"
			for _, n in ipairs(ITEM(c, "npcDrops") or {}) do add("npc", n, "drops " .. what) end
			for _, n in ipairs(ITEM(c, "objectDrops") or {}) do add("object", n, what) end
		end
	end
	for _, o in ipairs(type(ob[5]) == "table" and ob[5] or {}) do
		for _, n in ipairs(type(o[1]) == "table" and o[1] or {}) do add("npc", n, "kill") end
	end
	for _, o in ipairs(type(Q(questId, "extraObjectives")) == "table" and Q(questId, "extraObjectives") or {}) do
		local what = type(o[3]) == "string" and o[3] or "objective"
		for _, ref in ipairs(type(o[5]) == "table" and o[5] or {}) do
			local kind, id = ref[1], ref[2]
			if kind == "monster" then add("npc", id, what)
			elseif kind == "object" then add("object", id, what)
			elseif kind == "item" then
				local iname = ITEM(id, "name") or "the item"
				for _, n in ipairs(ITEM(id, "npcDrops") or {}) do add("npc", n, "drops " .. iname) end
				for _, n in ipairs(ITEM(id, "objectDrops") or {}) do add("object", n, iname) end
			end
		end
	end
	return out
end

-- every set of spots where a quest's work is: { {label, spawns = {[area] = {{x, y}, ...}}}, ... }
function QA.WorkSpawns(questId)
	local groups = {}
	for _, src in ipairs(QA.ObjectiveSources(questId)) do
		local get = src.kind == "npc" and NPC or OBJ
		groups[#groups + 1] = { label = (get(src.id, "name") or "?") .. ": " .. src.what, spawns = get(src.id, "spawns") }
	end
	local te = Q(questId, "triggerEnd") -- "go to this place"
	if type(te) == "table" and type(te[2]) == "table" then
		groups[#groups + 1] = { label = "Go to: " .. tostring(te[1] or "the spot"), spawns = te[2] }
	end
	local extra = Q(questId, "extraObjectives")
	for _, o in ipairs(type(extra) == "table" and extra or {}) do
		if type(o[1]) == "table" then
			groups[#groups + 1] = { label = type(o[3]) == "string" and o[3] or "objective", spawns = o[1] }
		end
	end
	return groups
end

-- where it's handed in, unless that's the NPC/object who gives it (the pin is already there)
function QA.HandInSpawns(questId)
	local fin, sb = Q(questId, "finishedBy"), Q(questId, "startedBy")
	if type(fin) ~= "table" then return {} end
	sb = type(sb) == "table" and sb or {}
	local groups = {}
	for i, get in ipairs({ NPC, OBJ }) do
		for _, id in ipairs(type(fin[i]) == "table" and fin[i] or {}) do
			if not Has(sb[i], id) then
				groups[#groups + 1] = { label = "Hand in to " .. (get(id, "name") or "?"), spawns = get(id, "spawns") }
			end
		end
	end
	return groups
end

-- spawns of a quest's targets, grouped into areas: { {map, x, y (0-1), count, targets = {"Name: kill"}}, ... }
function QA.ObjectiveAreas(questId)
	local Z = Mod("ZoneDB")
	if not (Z and Z.GetUiMapIdByAreaId) then return {} end
	local cells, list = {}, {}
	local groups = QA.WorkSpawns(questId)
	local function HasSpot(gs)
		for _, g in ipairs(gs) do
			for area, pts in pairs(type(g.spawns) == "table" and g.spawns or {}) do
				if Z:GetUiMapIdByAreaId(area) and type(pts) == "table" and pts[1] then return true end
			end
		end
	end
	-- nothing to kill, use or find (a delivery or talk-to quest): mark where it's handed in
	if not HasSpot(groups) then groups = QA.HandInSpawns(questId) end
	for _, grp in ipairs(groups) do
		local spawns, label = grp.spawns, grp.label
		for area, pts in pairs(type(spawns) == "table" and spawns or {}) do
			local map = Z:GetUiMapIdByAreaId(area)
			for _, pt in ipairs(map and type(pts) == "table" and pts or {}) do
				local x, y = pt[1], pt[2]
				if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
					x, y = x / 100, y / 100
					local key = map .. ":" .. math.floor(x / QA.AREA_CELL) .. ":" .. math.floor(y / QA.AREA_CELL)
					local c = cells[key]
					if not c then
						c = { map = map, sx = 0, sy = 0, count = 0, targets = {}, has = {} }
						cells[key] = c
						list[#list + 1] = c
					end
					c.sx, c.sy, c.count = c.sx + x, c.sy + y, c.count + 1
					if not c.has[label] then c.has[label] = true; c.targets[#c.targets + 1] = label end
				end
			end
		end
	end
	for _, c in ipairs(list) do c.x, c.y = c.sx / c.count, c.sy / c.count end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		if a.map ~= b.map then return a.map < b.map end
		if a.x ~= b.x then return a.x < b.x end
		return a.y < b.y
	end)
	local out = {}
	for i = 1, math.min(#list, QA.MAX_AREAS) do
		local c = list[i]
		out[i] = { map = c.map, x = c.x, y = c.y, count = c.count, targets = c.targets }
	end
	return out
end

-- Pins --------------------------------------------------------------------------------------------
-- Our pins and lines live on our own layer over the map canvas, not in Questie's pin system, so
-- Questie's own icon handling never meets them.

local pool, spots, lines = {}, {}, {}
local areaPool, areaSpots = {}, {}
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
		GameTooltip:AddLine(QA.StepText(e.step, e.step .. ".") .. " " .. Title(e.id), 1, 0.82, 0)
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

local function AreaOnEnter(f)
	local a = f.area
	if not a then return end
	GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
	for i, it in ipairs(a.entries) do
		local e = it.entry
		if i > 1 then GameTooltip:AddLine(" ") end
		GameTooltip:AddLine(QA.StepText(e.step, e.step .. ".") .. " " .. Title(e.id), 1, 0.82, 0)
		GameTooltip:AddLine("Work here:", 0.8, 0.8, 0.8)
		for _, t in ipairs(it.targets) do GameTooltip:AddLine("  " .. t, 1, 0.7, 0.35) end
		local obj = Q(e.id, "objectivesText")
		if type(obj) == "table" then
			for _, l in ipairs(obj) do GameTooltip:AddLine(l, 1, 1, 1, true) end
		end
	end
	GameTooltip:Show()
end

local function NewArea(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(18, 18)
	f.bg = f:CreateTexture(nil, "BORDER")
	f.bg:SetAllPoints()
	f.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	f.bg:SetVertexColor(1, 0.6, 0.2, 0.5)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("CENTER", 0, 0)
	f:EnableMouse(true)
	f:SetScript("OnEnter", AreaOnEnter)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end

-- the objective areas now placed: { map, x, y (0-1), label, entry, targets, frame? }
function QA.AreaSpots() return areaSpots end

-- place pins and lines for the map being shown
function QA.Redraw()
	for _, l in ipairs(lines) do l:Hide() end
	for _, s in ipairs(spots) do if s.frame then s.frame:Hide() end end
	for _, a in ipairs(areaSpots) do if a.frame then a.frame:Hide() end end
	if not QA.shownFor then return end
	local lay, canvas = Layer()
	if not lay then return end
	local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
	for _, a in ipairs(areaSpots) do
		local x, y = ShownMapPoint(a.map, a.x, a.y)
		if x then
			a.frame = a.frame or table.remove(areaPool) or NewArea(lay)
			a.frame.area = a
			a.frame.label:SetText(a.label)
			local r, g, b = QA.StepColor(a.minStep or 1)
			a.frame.bg:SetVertexColor(r, g, b, 0.55)
			a.frame:ClearAllPoints()
			a.frame:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
			a.frame:Show()
		end
	end
	for _, s in ipairs(spots) do
		local x, y = ShownMapPoint(s.map, s.x, s.y)
		if x then
			s.frame = s.frame or table.remove(pool) or NewPin(lay)
			s.frame.spot = s
			s.frame.label:SetText(s.colored or s.label)
			s.frame:ClearAllPoints()
			s.frame:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
			s.frame:Show()
		end
	end
	if not lay.CreateLine then return end
	local n = 0
	local function seg(a, b, step)
		if not a or not b then return end
		local x1, y1 = ShownMapPoint(a.map, a.x, a.y)
		local x2, y2 = ShownMapPoint(b.map, b.x, b.y)
		if not (x1 and x2) or (math.abs(x1 - x2) < 0.002 and math.abs(y1 - y2) < 0.002) then return end
		n = n + 1
		local l = lines[n]
		if not l then
			l = lay:CreateLine(nil, "ARTWORK")
			if l.SetThickness then l:SetThickness(3) end
			lines[n] = l
		end
		local r, g, bl = QA.StepColor(step or 1)
		l:SetColorTexture(r, g, bl, 0.8)
		l:SetStartPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
		l:SetEndPoint("TOPLEFT", canvas, x2 * w, -y2 * h)
		l:Show()
	end
	local route = QA.route or {}
	for i = 2, #route do seg(route[i - 1], route[i], route[i].step) end
end

-- The suggested route (straight lines; WoW gives add-ons no roads or terrain): from where you
-- are, step by step: that step's pick-ups, then one spot per objective, then its hand-ins, each
-- time going to the nearest next place. steps = { {entry, spot?, areas, handin?}, ... }
local function Dist(a, b)
	if a.map ~= b.map then return 100 end
	local dx, dy = a.x - b.x, a.y - b.y
	return dx * dx + dy * dy
end

function QA.BuildRoute(origin, steps)
	local route, pos = {}, nil
	local function go(pt, step)
		if pos and pt.map == pos.map and math.abs(pt.x - pos.x) < 0.002 and math.abs(pt.y - pos.y) < 0.002 then return end
		route[#route + 1] = { map = pt.map, x = pt.x, y = pt.y, step = step }
		pos = pt
	end
	if origin and origin.map and origin.x then go(origin, 0) end
	local function nearestFirst(points, step)
		local left = {}
		for _, p in ipairs(points) do left[#left + 1] = p end
		while #left > 0 do
			local bi, bd = 1, math.huge
			if pos then
				for i, p in ipairs(left) do local d = Dist(pos, p); if d < bd then bi, bd = i, d end end
			end
			go(table.remove(left, bi), step)
		end
	end
	local byStep, order = {}, {}
	for _, sd in ipairs(steps) do
		local k = sd.entry.step
		if not byStep[k] then byStep[k] = {}; order[#order + 1] = k end
		table.insert(byStep[k], sd)
	end
	table.sort(order)
	for _, k in ipairs(order) do
		local list = byStep[k]
		local picks, seenPick = {}, {}
		for _, sd in ipairs(list) do
			if sd.spot and not seenPick[sd.spot] then seenPick[sd.spot] = true; picks[#picks + 1] = sd.spot end
		end
		nearestFirst(picks, k)
		-- each objective (quest + target) needs one of its areas; go to the nearest wanted area each time
		local pending = {}
		for _, sd in ipairs(list) do
			local wanted = {}
			for _, a in ipairs(sd.areas or {}) do
				for _, t in ipairs(a.targets or {}) do
					if not wanted[t] then wanted[t] = {}; pending[#pending + 1] = wanted[t] end
					table.insert(wanted[t], a)
				end
			end
		end
		while #pending > 0 do
			local best, bd = nil, math.huge
			for _, cands in ipairs(pending) do
				for _, a in ipairs(cands) do
					local d = pos and Dist(pos, a) or 0
					if d < bd then best, bd = a, d end
				end
			end
			go(best, k)
			local still = {}
			for _, cands in ipairs(pending) do
				local done = false
				for _, a in ipairs(cands) do if a == best then done = true end end
				if not done then still[#still + 1] = cands end
			end
			pending = still
		end
		local ins = {}
		for _, sd in ipairs(list) do if sd.handin then ins[#ins + 1] = sd.handin end end
		nearestFirst(ins, k)
	end
	return route
end

function QA.Route() return QA.route or {} end

function QA.Clear()
	for _, s in ipairs(spots) do
		if s.frame then s.frame:Hide(); s.frame.spot = nil; pool[#pool + 1] = s.frame end
	end
	spots = {}
	for _, a in ipairs(areaSpots) do
		if a.frame then a.frame:Hide(); a.frame.area = nil; areaPool[#areaPool + 1] = a.frame end
	end
	areaSpots = {}
	QA.shownFor, QA.origin, QA.segments, QA.route = nil, nil, nil, nil
	for _, l in ipairs(lines) do l:Hide() end
end

-- the pins now placed: { map, x, y (0-1), frame?, entries, starter, label }
function QA.PinSpots() return spots end

-- origin = { map, x, y (0-1), area }
function QA.Show(questId, origin)
	QA.Clear()
	local Z = Mod("ZoneDB")
	if not (Z and Z.GetUiMapIdByAreaId) then return end
	local byspot, segments, routeSteps = {}, {}, {}
	local from = { [questId] = "origin" } -- quest -> the spot its follow-ons' lines start from
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
			local seenStep, colored = {}, {}
			for _, pe in ipairs(spot.entries) do
				if not seenStep[pe.step] then
					seenStep[pe.step] = true
					labels[#labels + 1] = tostring(pe.step)
					colored[#colored + 1] = QA.StepText(pe.step)
				end
			end
			spot.label = table.concat(labels, ",")
			spot.colored = table.concat(colored, ",")
		end
		local parentFrom = from[e.parent] or "origin"
		if spot then segments[#segments + 1] = { from = parentFrom, spot = spot } end
		from[e.id] = spot or parentFrom
		-- steps whose work is in the same place share one marker ("1,2,3"), so none hides another
		local found, mapsUsed = QA.ObjectiveAreas(e.id), {}
		local hin
		do
			local a, hx, hy = QA.FinisherSpot(e.id, origin and origin.area)
			local hm = a and Z:GetUiMapIdByAreaId(a)
			if hm then hin = { map = hm, x = hx / 100, y = hy / 100 } end
		end
		routeSteps[#routeSteps + 1] = { entry = e, spot = spot, areas = found, handin = hin }
		for _, a in ipairs(found) do
			mapsUsed[#mapsUsed + 1] = tostring(a.map)
			local hit
			for _, b in ipairs(areaSpots) do
				if b.map == a.map and math.abs(b.x - a.x) < QA.AREA_CELL and math.abs(b.y - a.y) < QA.AREA_CELL then hit = b; break end
			end
			if not hit then
				hit = { map = a.map, x = a.x, y = a.y, count = 0, entries = {}, steps = {}, entry = e }
				areaSpots[#areaSpots + 1] = hit
			end
			hit.count = hit.count + (a.count or 0)
			local mine
			for _, it in ipairs(hit.entries) do if it.entry == e then mine = it end end
			if mine then
				for _, t in ipairs(a.targets) do
					local dup = false
					for _, u in ipairs(mine.targets) do if u == t then dup = true end end
					if not dup then mine.targets[#mine.targets + 1] = t end
				end
			else
				hit.entries[#hit.entries + 1] = { entry = e, targets = a.targets }
			end
			hit.steps[e.step] = true
			local st = {}
			for k in pairs(hit.steps) do st[#st + 1] = k end
			table.sort(st)
			hit.minStep = st[1]
			for i = 1, #st do st[i] = tostring(st[i]) end
			hit.label = table.concat(st, ",")
		end
		if QA.debug then
			Dbg("step " .. e.step .. ": " .. Title(e.id) .. " - " .. #found .. " work area(s)"
				.. (#found > 0 and (" on map " .. table.concat(mapsUsed, ",")) or ""))
			if #found == 0 then
				local ob, fin = Q(e.id, "objectives"), Q(e.id, "finishedBy")
				local function n(t) return type(t) == "table" and #t or 0 end
				Dbg("    objectives=" .. (type(ob) == "table" and (n(ob[1]) .. " npc/" .. n(ob[2]) .. " obj/" .. n(ob[3]) .. " item/" .. n(ob[5]) .. " credit") or "none")
					.. " triggerEnd=" .. tostring(type(Q(e.id, "triggerEnd")) == "table") .. " extra=" .. n(Q(e.id, "extraObjectives"))
					.. " hand-in=" .. (type(fin) == "table" and (n(fin[1]) .. " npc/" .. n(fin[2]) .. " obj") or "none"))
				for _, o in ipairs(type(ob) == "table" and type(ob[3]) == "table" and ob[3] or {}) do
					Dbg("    item " .. tostring(ITEM(o[1], "name") or o[1]) .. ": " .. n(ITEM(o[1], "npcDrops")) .. " creature/"
						.. n(ITEM(o[1], "objectDrops")) .. " object/" .. n(ITEM(o[1], "itemDrops")) .. " container/"
						.. n(ITEM(o[1], "vendors")) .. " vendor sources")
				end
				local sb = Q(e.id, "startedBy")
				for _, id in ipairs(type(fin) == "table" and type(fin[1]) == "table" and fin[1] or {}) do
					local sp, k = NPC(id, "spawns"), 0
					for _ in pairs(type(sp) == "table" and sp or {}) do k = k + 1 end
					Dbg("    hand in to " .. tostring(NPC(id, "name") or id)
						.. ((type(sb) == "table" and Has(sb[1], id)) and " (the giver)" or " (not the giver)")
						.. ", known in " .. k .. " zone(s)")
				end
			end
		end
	end
	if #spots == 0 and #areaSpots == 0 then
		-- nothing to place (no follow-ons, or none Questie knows a spot for): stay quiet, the tooltip says so
		if QA.debug then Dbg("nothing to pin for " .. tostring(Q(questId, "name") or questId)) end
		return
	end
	QA.shownFor, QA.origin, QA.segments = questId, origin, segments
	QA.route = QA.BuildRoute(origin, routeSteps)
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
	-- the game's own quest markers and quest list rows; debug: note every tooltip shown while the map is open
	if GameTooltip and GameTooltip.HookScript then
		hooksecurefunc(GameTooltip, "Show", QA.Watch)
		GameTooltip:HookScript("OnHide", function(t) t.__qaOwner, t.__qaAdds = nil, 0 end)
		if WorldMapFrame then
			local watcher = CreateFrame("Frame", nil, WorldMapFrame) -- runs only while the map is open
			watcher:SetScript("OnUpdate", QA.Watch)
		end
		GameTooltip:HookScript("OnShow", function(tt)
			Safe(QA.OnAnyTooltip, tt)
			if not QA.debug or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
			local o = tt.GetOwner and tt:GetOwner()
			local name = o and ((o.GetDebugName and o:GetDebugName()) or (o.GetName and o:GetName())) or "?"
			local first = _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
			Dbg("tooltip: owner=" .. tostring(name) .. " questie=" .. tostring(o and o.data ~= nil)
				.. " quest=" .. tostring(QA.OwnerQuestId(o))
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
