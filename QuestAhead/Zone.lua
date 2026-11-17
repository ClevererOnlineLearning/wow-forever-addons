-- QuestAhead zone plan: an on-demand levelling route for one zone.
-- "Plan zone" on the world map (or /qahead zone) looks at every quest you can do in the zone
-- shown: what's in your log, what you can pick up now, and what those unlock once handed in.
-- It orders the pick-ups, the work and the hand-ins into one route (nearest next place each
-- time; a quest's follow-ons only after it's handed in; never more quests than your log holds),
-- draws it on the map, and lists it in a guide window that ticks steps off as you go.
-- Uses Questie's own data and its own "can I do this?" check; changes nothing in Questie.
-- by good mens (Mephz on WoW Forever)

local QA = _G.QuestAhead
if not QA then return end
local Q, NPC, OBJ, Mod, DB = QA.Q, QA.NPC, QA.OBJ, QA.Mod, QA.DB
local Title, Safe, TAG = QA.Title, QA.Safe, QA.TAG

QA.ZONE_MAX_QUESTS = 40  -- most quests in one plan
QA.PICKUP_PULL = 0.6     -- pick-ups count as this much nearer, so a hub's givers are all seen before leaving
QA.PULLS = { 0.35, 0.6, 1 } -- tried in turn; the shortest route wins
QA.SAME_SPOT = 0.004     -- closer than this (share of the map) is the same place
QA.RUN_SPEED = 7         -- yards a second on foot, for the time estimate
QA.ZONE_ROWS = 12        -- lines in the guide window
QA.MARK_SHIFT = 14       -- step numbers sit this far up and right of the spot, off Questie's icon

-- Player state (one place each, so tests can stand in for the game) ------------------------------

local function Call(obj, name, ...)
	local fn = obj and obj[name]
	if type(fn) ~= "function" then return nil end
	local ok, v1, v2 = pcall(fn, ...)
	if ok then return v1, v2 end
end

function QA.PlayerLevel()
	return Call(Mod("QuestiePlayer"), "GetPlayerLevel") or (UnitLevel and UnitLevel("player")) or 1
end

QA.turnedIn = {}
local function Done(id)
	if QA.turnedIn[id] then return true end
	local char = Questie and Questie.db and Questie.db.char
	return (char and type(char.complete) == "table" and char.complete[id]) and true or false
end
QA.IsDone = Done

-- { [questId] = { complete = bool } }
function QA.QuestLog()
	local out = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		-- the older quest log calls
		if not (GetNumQuestLogEntries and GetQuestLogTitle) then return out end
		for i = 1, (GetNumQuestLogEntries() or 0) do
			local _, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
			if not isHeader and type(id) == "number" and id > 0 then out[id] = { complete = isComplete == 1 } end
		end
		return out
	end
	local function put(id)
		if type(id) == "number" and id > 0 and not out[id] then
			out[id] = { complete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)) and true or false }
		end
	end
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, n do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and type(info) == "table" and not info.isHeader then put(info.questID) end
	end
	-- Questie's list of quests in the log also has the ones under collapsed headers
	local AQ = Mod("ActiveQuests")
	local all = Call(AQ, "GetAll")
	for id in pairs(type(all) == "table" and all or {}) do put(id) end
	return out
end

function QA.LogCap()
	return (C_QuestLog and Call(C_QuestLog, "GetMaxNumQuestsCanAccept")) or MAX_QUESTS or 25
end

function QA.PlayerSpot(map)
	if C_Map and C_Map.GetPlayerMapPosition then
		local ok, p = pcall(C_Map.GetPlayerMapPosition, map, "player")
		if ok and p then
			local x, y
			if p.GetXY then x, y = p:GetXY() else x, y = p.x, p.y end
			if x and y and (x > 0 or y > 0) then return { x = x, y = y } end
		end
	end
end

local function MapName(map)
	local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name or "this zone"
end

-- yards across the map, so east-west and north-south distances compare fairly
local function ZoneSize(map)
	local HBD = Mod("HBD")
	local w, h = Call(HBD, "GetZoneSize", HBD, map)
	if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	return 1500, 1000
end

-- Where things are, on the plan's map -------------------------------------------------------------

local spotCache = {}

-- is map m this zone, or an area inside it (a sub-zone map)? Next-door zones don't count, even though
-- their map rectangles overlap this one's edges.
local within = {}
local function Within(m, map)
	if m == map then return true end
	local key = m .. ">" .. map
	if within[key] == nil then
		local found, cur = false, m
		for _ = 1, 4 do
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
			local parent = info and info.parentMapID
			if not parent or parent == 0 then break end
			if parent == map then found = true; break end
			cur = parent
		end
		within[key] = found
	end
	return within[key]
end
local SpawnsOn, HasSpawns, FirstMap
-- every spawn of an NPC/object that lies on the map: { {x, y (0-1)}, ... }
local function SpotsOn(kind, id, map)
	local key = kind .. id .. ":" .. map
	if spotCache[key] then return spotCache[key] end
	local out = {}
	local Z = Mod("ZoneDB")
	local spawns = (kind == "npc" and NPC or OBJ)(id, "spawns")
	if type(spawns) == "table" and Z and Z.GetUiMapIdByAreaId then
		for area, pts in pairs(spawns) do
			local m = Z:GetUiMapIdByAreaId(area)
			if m and not Within(m, map) then m = nil end
			local misses = 0
			for _, pt in ipairs(m and type(pts) == "table" and pts or {}) do
				if type(pt[1]) == "number" and type(pt[2]) == "number" and pt[1] >= 0 and pt[2] >= 0 then
					local x, y = QA.MapPoint(m, pt[1] / 100, pt[2] / 100, map)
					if x then out[#out + 1] = { x = x, y = y }
					else
						misses = misses + 1
						if m ~= map and misses >= 3 and #out == 0 then break end -- another zone altogether: don't try every spawn
					end
				end
			end
		end
	end
	spotCache[key] = out
	return out
end

-- the first NPC/object in a startedBy/finishedBy list that stands on the map: { x, y, name }
local function PersonOn(list, map)
	if type(list) ~= "table" then return nil end
	for i, kind in ipairs({ "npc", "object" }) do
		for _, id in ipairs(type(list[i]) == "table" and list[i] or {}) do
			local s = SpotsOn(kind, id, map)[1]
			if s then return { x = s.x, y = s.y, name = (kind == "npc" and NPC or OBJ)(id, "name") or "?" } end
		end
	end
end

-- spawns ({[area] = {{x, y}, ...}}) that lie on the map, as 0-1 points
SpawnsOn = function(spawns, map)
	local out = {}
	local Z = Mod("ZoneDB")
	if type(spawns) ~= "table" or not (Z and Z.GetUiMapIdByAreaId) then return out end
	for area, pts in pairs(spawns) do
		local m = Z:GetUiMapIdByAreaId(area)
		if m and not Within(m, map) then m = nil end
		local misses = 0
		for _, pt in ipairs(m and type(pts) == "table" and pts or {}) do
			if type(pt[1]) == "number" and type(pt[2]) == "number" and pt[1] >= 0 and pt[2] >= 0 then
				local x, y = QA.MapPoint(m, pt[1] / 100, pt[2] / 100, map)
				if x then out[#out + 1] = { x = x, y = y }
				else
					misses = misses + 1
					if m ~= map and misses >= 3 and #out == 0 then break end
				end
			end
		end
	end
	return out
end

HasSpawns = function(spawns)
	for _, pts in pairs(type(spawns) == "table" and spawns or {}) do
		if type(pts) == "table" and pts[1] then return true end
	end
	return false
end

FirstMap = function(spawns)
	local Z = Mod("ZoneDB")
	for area, pts in pairs(type(spawns) == "table" and spawns or {}) do
		if type(pts) == "table" and pts[1] and Z and Z.GetUiMapIdByAreaId then return Z:GetUiMapIdByAreaId(area) end
	end
end

local function HasPeople(list)
	if type(list) ~= "table" then return false end
	return (type(list[1]) == "table" and list[1][1] ~= nil) or (type(list[2]) == "table" and list[2][1] ~= nil)
end

-- a quest's part of the plan, or nil + why it can't be done here
-- { id, inLog, pickup = spot?, objectives = { {label, cands = {spot, ...}}, ... }, handin = spot?, handinAway = name? }
function QA.ZoneQuest(id, map, logEntry)
	local rec = { id = id, inLog = logEntry ~= nil, objectives = {} }
	if not logEntry then
		rec.pickup = PersonOn(Q(id, "startedBy"), map)
		if not rec.pickup then return nil, "starts somewhere else" end
	end
	if not (logEntry and logEntry.complete) then
		local byLabel, away, partly = {}, nil, false
		for _, grp in ipairs(QA.WorkSpawns(id)) do
			local cands, cells, any = nil, {}, false
			for _, pt in ipairs(SpawnsOn(grp.spawns, map)) do
				local key = math.floor(pt.x / QA.AREA_CELL) .. ":" .. math.floor(pt.y / QA.AREA_CELL)
				local c = cells[key]
				if not c then c = { sx = 0, sy = 0, n = 0 }; cells[key] = c end
				c.sx, c.sy, c.n = c.sx + pt.x, c.sy + pt.y, c.n + 1
			end
			local list = {}
			for _, c in pairs(cells) do list[#list + 1] = c end
			table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.sx < b.sx end)
			for i = 1, math.min(#list, QA.MAX_AREAS) do
				local o = byLabel[grp.label]
				if not o then o = { label = grp.label, cands = {} }; byLabel[grp.label] = o; rec.objectives[#rec.objectives + 1] = o end
				o.cands[#o.cands + 1] = { x = list[i].sx / list[i].n, y = list[i].sy / list[i].n }
				any = true
			end
			if not any and HasSpawns(grp.spawns) then
				partly = true
				away = away or FirstMap(grp.spawns)
			end
		end
		if #rec.objectives == 0 and away then return nil, "its work is in " .. MapName(away) end
		rec.partly = partly
	end
	local fin = Q(id, "finishedBy")
	rec.handin = PersonOn(fin, map)
	if rec.partly and rec.handin then
		-- some of its work is in another zone: it can't be handed in on this trip
		rec.handinAway, rec.handin = rec.handin.name, nil
	elseif not rec.handin and HasPeople(fin) then
		local i = (type(fin[1]) == "table" and fin[1][1]) and 1 or 2
		rec.handinAway = (i == 1 and NPC or OBJ)(fin[i][1], "name") or "?"
	end
	if logEntry and not rec.handin and #rec.objectives == 0 then return nil, "nothing for it here" end
	return rec
end

-- Which quests -------------------------------------------------------------------------------------

-- rules that don't depend on other quests
local function Eligible(id, level)
	if not QA.Applicable(id) then return false end
	local db = DB()
	if Call(db, "IsRepeatable", id) or Call(db, "IsDailyQuest", id) or Call(db, "IsWeeklyQuest", id) then return false end
	local rl = Q(id, "requiredLevel")
	if type(rl) == "number" and rl > level then return false end
	local ql = Q(id, "questLevel")
	if type(ql) == "number" and Call(db, "IsTrivial", ql) then return false end -- grey
	return true
end

-- nil if its earlier quests aren't done and won't be in this plan; else the planned ones it waits for
local function Saved(id)
	local char = Questie and Questie.db and Questie.db.char
	return (char and type(char.complete) == "table" and char.complete[id]) and true or false
end

-- second result: true when it's met only through a hand-in Questie hasn't recorded yet
local function PreMet(id, handed)
	local single = Q(id, "preQuestSingle")
	if type(single) == "table" then
		if not single[1] then return {} end
		for _, p in ipairs(single) do if Saved(p) then return {} end end
		for _, p in ipairs(single) do if Done(p) then return {}, true end end
		for _, p in ipairs(single) do if handed[p] then return { p } end end
		return nil
	end
	local fresh = false
	local deps = {}
	local group = Q(id, "preQuestGroup")
	for _, p in ipairs(type(group) == "table" and group or {}) do
		local a = math.abs(p)
		if Done(a) and not Saved(a) then fresh = true end
		if not Done(a) then
			local alt = false
			if p > 0 then
				for _, x in ipairs(type(Q(a, "exclusiveTo")) == "table" and Q(a, "exclusiveTo") or {}) do if Done(x) then alt = true end end
			end
			if not alt then
				if handed[a] then deps[#deps + 1] = a else return nil end
			end
		end
	end
	return deps, fresh
end

-- for a quest that opens up only during the plan (Questie can't vouch for it yet)
local NEEDS = { "requiredMinRep", "requiredMaxRep", "requiredSkill", "requiredRanks", "requiredSpell",
	"requiredSpecialization", "parentQuest", "availableStartingWith" }
local function LaterOk(id, inPlan, log)
	local char = Questie and Questie.db and Questie.db.char
	if char and type(char.hidden) == "table" and char.hidden[id] then return false end
	for _, f in ipairs(NEEDS) do
		local v = Q(id, f)
		if v ~= nil and v ~= 0 then return false end -- can't tell yet; leave it out rather than guess
	end
	return true
end

local function Clashes(id, inPlan, log)
	local ex = Q(id, "exclusiveTo")
	for _, x in ipairs(type(ex) == "table" and ex or {}) do
		if inPlan[x] or log[x] or Done(x) then return true end
	end
	local bc = Q(id, "breadcrumbForQuestId")
	if type(bc) == "number" and bc ~= 0 and (inPlan[bc] or log[bc] or Done(bc)) then return true end
	return false
end

-- { quests = {rec...}, skipped = {"why"...} }
function QA.ZoneQuests(map)
	local Z = Mod("ZoneDB")
	local db = DB()
	local level, log = QA.PlayerLevel(), QA.QuestLog()
	local out, skipped, inPlan, handed, rejected = {}, {}, {}, {}, {}
	local function add(rec, deps)
		rec.deps = deps or {}
		out[#out + 1] = rec
		inPlan[rec.id] = true
		if rec.handin then handed[rec.id] = true end
	end
	for id, st in pairs(log) do
		local rec = QA.ZoneQuest(id, map, st)
		if rec then add(rec) end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	-- quests whose giver stands here
	local cands = {}
	local ptrs = db and db.QuestPointers
	for id in pairs(type(ptrs) == "table" and ptrs or {}) do
		if not log[id] and not Done(id) and PersonOn(Q(id, "startedBy"), map) and Eligible(id, level) then
			cands[#cands + 1] = id
		end
	end
	table.sort(cands, function(a, b)
		local la, lb = Q(a, "questLevel") or 0, Q(b, "questLevel") or 0
		if la ~= lb then return la < lb end
		return a < b
	end)
	local changed = true
	while changed and #out < QA.ZONE_MAX_QUESTS do
		changed = false
		for _, id in ipairs(cands) do
			if #out >= QA.ZONE_MAX_QUESTS then break end
			if not inPlan[id] and not rejected[id] then
				local deps, fresh = PreMet(id, handed)
				if deps then
					local ok
					if #deps == 0 and not fresh then ok = (db and db.IsDoable) and Call(db, "IsDoable", id) or not (db and db.IsDoable)
					else ok = LaterOk(id, inPlan, log) end
					if not ok or Clashes(id, inPlan, log) then
						rejected[id] = true
					else
						local rec, why = QA.ZoneQuest(id, map)
						if rec then
							add(rec, deps); changed = true
						else
							rejected[id] = true
							skipped[#skipped + 1] = Title(id) .. ": " .. tostring(why)
						end
					end
				end
			end
		end
	end
	return { quests = out, skipped = skipped }
end

-- The route -----------------------------------------------------------------------------------------

local function Dist(a, b, w, h)
	if not a or not b then return 0 end
	local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
	return math.sqrt(dx * dx + dy * dy)
end

-- "Jadefire Satyr: kill" -> "Kill Jadefire Satyr", "Bear: drops Paw" -> "Paw from Bear"
function QA.Pretty(label)
	local who, what = label:match("^(.-): (.*)$")
	if not who then return label end
	if who == "Go to" then return label end
	if what == "kill" then return "Kill " .. who end
	if what == "use" then return "Use " .. who end
	local item = what:match("^drops (.*)$")
	if item then return item .. " from " .. who end
	if what == "objective" then return who end
	return what .. " from " .. who
end

local function Names(ids)
	local t = {}
	for _, id in ipairs(ids) do t[#t + 1] = "|cffffd200" .. (Q(id, "name") or ("Quest " .. id)) .. "|r" end
	return table.concat(t, ", ")
end

-- greedy: from where you are, always the nearest thing you're allowed to do next
-- stops = { {x, y, actions = { {kind = "pickup"|"work"|"handin", quests = {id...}, targets?, text}, ... }}, ... }
function QA.BuildZoneRoute(map, quests, start, pull)
	pull = pull or QA.PICKUP_PULL
	local w, h = ZoneSize(map)
	local cap = QA.LogCap()
	local active = 0
	for _ in pairs(QA.QuestLog()) do active = active + 1 end
	local byId = {}
	for _, r in ipairs(quests) do
		byId[r.id] = r
		r.picked, r.finished, r.handed = r.inLog, false, false
		r.pending = {}
		for _, o in ipairs(r.objectives) do r.pending[#r.pending + 1] = o end
	end
	local stops, pos, travel = {}, start, 0
	local function visit(pt, action)
		local last = stops[#stops]
		if last and math.abs(last.x - pt.x) < QA.SAME_SPOT and math.abs(last.y - pt.y) < QA.SAME_SPOT then
			table.insert(last.actions, action)
		else
			travel = travel + Dist(pos, pt, w, h)
			stops[#stops + 1] = { x = pt.x, y = pt.y, actions = { action } }
			pos = pt
		end
	end
	local function depsHanded(r)
		for _, d in ipairs(r.deps or {}) do if byId[d] and not byId[d].handed then return false end end
		return true
	end
	local function settle(r)
		if r.picked and not r.finished and #r.pending == 0 and not r.handin then r.finished = true end
	end
	for _, r in ipairs(quests) do settle(r) end
	local guard = 0
	while guard < 2000 do
		guard = guard + 1
		local best, bestCost
		local function offer(c, what)
			if not bestCost or c < bestCost - 1e-9 then best, bestCost = what, c end
		end
		for _, r in ipairs(quests) do
			if r.picked and not r.finished then
				if #r.pending == 0 then
					offer(Dist(pos, r.handin, w, h), { kind = "handin", r = r })
				else
					for _, o in ipairs(r.pending) do
						for _, c in ipairs(o.cands) do offer(Dist(pos, c, w, h), { kind = "work", at = c }) end
					end
				end
			end
		end
		for _, r in ipairs(quests) do
			if not r.picked and active < cap and depsHanded(r) then
				offer(Dist(pos, r.pickup, w, h) * pull, { kind = "pickup", r = r })
			end
		end
		if not best then break end
		if best.kind == "pickup" then
			local r = best.r
			r.picked, active = true, active + 1
			visit(r.pickup, { kind = "pickup", quests = { r.id }, text = "Pick up " .. Names({ r.id }) .. " from " .. r.pickup.name })
			settle(r)
		elseif best.kind == "handin" then
			local r = best.r
			r.finished, r.handed, active = true, true, active - 1
			visit(r.handin, { kind = "handin", quests = { r.id }, text = "Hand in " .. Names({ r.id }) .. " to " .. r.handin.name })
		else
			-- everything picked up that can be done here gets done on this visit
			local at, ids, targets, seenT = best.at, {}, {}, {}
			for _, r in ipairs(quests) do
				if r.picked and not r.finished and #r.pending > 0 then
					local still, hit = {}, false
					for _, o in ipairs(r.pending) do
						local here = false
						for _, c in ipairs(o.cands) do
							if math.abs(c.x - at.x) < QA.AREA_CELL / 2 and math.abs(c.y - at.y) < QA.AREA_CELL / 2 then here = true end
						end
						if here then
							hit = true
							if not seenT[o.label] then seenT[o.label] = true; targets[#targets + 1] = o.label end
						else
							still[#still + 1] = o
						end
					end
					r.pending = still
					if hit then ids[#ids + 1] = r.id end
					settle(r)
				end
			end
			local nice = {}
			for i, t in ipairs(targets) do nice[i] = QA.Pretty(t) end
			visit(at, { kind = "work", quests = ids, targets = targets,
				text = table.concat(nice, "; ") .. " (for " .. Names(ids) .. ")" })
		end
	end
	-- left in the log at the end: hand-ins somewhere else
	local away = {}
	for _, r in ipairs(quests) do
		if r.handinAway and r.picked then away[#away + 1] = Names({ r.id }) .. " to " .. r.handinAway end
	end
	return stops, travel, away
end

-- Plan, progress -------------------------------------------------------------------------------------

local function CharKey()
	local n = UnitName and UnitName("player")
	local r = GetRealmName and GetRealmName()
	return (n or "?") .. "-" .. (r or "?")
end

local function SavePlanMap(map)
	QuestAheadDB = type(QuestAheadDB) == "table" and QuestAheadDB or {}
	QuestAheadDB.zone = type(QuestAheadDB.zone) == "table" and QuestAheadDB.zone or {}
	QuestAheadDB.zone[CharKey()] = map
end

function QA.PlanZone(map, quiet)
	map = map or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	if not map then print(TAG .. "can't tell which zone to plan.") return nil end
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone
	if info and ZONE and type(info.mapType) == "number" and info.mapType < ZONE then
		local mine = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		if not mine or mine == map then print(TAG .. "open a zone's map (not a continent) to plan it.") return nil end
		map = mine
	end
	spotCache = {}
	QA.guideOffset = 0
	QA.ZoneClear(true)
	local found = QA.ZoneQuests(map)
	local list = {}
	for _, r in ipairs(found.quests) do list[#list + 1] = r.id end
	if #found.quests == 0 then
		if not quiet then
			print(TAG .. "nothing to plan in " .. MapName(map) .. ": no quests Questie knows of that you can do there now.")
		end
		return nil
	end
	-- a few ways of weighing "pick up everything nearby first" against "go do the work"; keep the shortest
	local start = QA.PlayerSpot(map)
	local stops, travel, away
	local most
	for _, pull in ipairs(QA.PULLS) do
		local s, t, a = QA.BuildZoneRoute(map, found.quests, start, pull)
		local n = 0
		for _, st in ipairs(s) do n = n + #st.actions end
		if not most or n > most or (n == most and t < travel) then stops, travel, away, most = s, t, a, n end
	end
	if #stops == 0 then
		if not quiet then
			local full = 0
			for _ in pairs(QA.QuestLog()) do full = full + 1 end
			print(TAG .. "nothing to plan in " .. MapName(map)
				.. (full >= QA.LogCap() and ": your quest log is full." or ": nothing on the way can be done yet."))
		end
		return nil
	end
	QA.zone = { map = map, quests = list, stops = stops, travel = travel, skipped = found.skipped, away = away }
	SavePlanMap(map)
	if QA.debug then
		QA.Dbg("zone plan " .. MapName(map) .. ": " .. #list .. " quests, " .. #stops .. " stops")
		for _, r in ipairs(found.quests) do
			QA.Dbg("  " .. Title(r.id) .. (r.inLog and " [in log]" or "") .. ": " .. #r.objectives .. " objective(s)"
				.. (r.handin and "" or (r.handinAway and (", hand in elsewhere to " .. r.handinAway) or ", no hand-in known")))
		end
		for _, s in ipairs(found.skipped) do QA.Dbg("  left out: " .. s) end
	end
	QA.ZoneRefresh()
	if not quiet then
		print(TAG .. "plan for " .. MapName(map) .. ": " .. #list .. " quests in " .. #stops .. " stops, about "
			.. math.max(1, math.floor(travel / QA.RUN_SPEED / 60 + 0.5)) .. " min of running. The guide window ticks steps off as you go.")
	end
	return QA.zone
end

-- is this step done? (sticky: once done, it stays done)
-- the word the log's objective line will contain for a target label, or nil ("Go to" spots: none)
function QA.ObjectiveName(label)
	local who, what = label:match("^(.-): (.*)$")
	if not who then return label end
	if who == "Go to" then return nil end
	if what == "kill" or what == "use" or what == "objective" then return who end
	what = what:match("%(has (.-)%)$") or what:match("^drops (.*)$") or what
	return what
end

local function ObjectivesDone(qid, targets)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return false end
	local ok, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
	if not ok or type(objs) ~= "table" then return false end
	local any = false
	for _, o in ipairs(objs) do
		local text = type(o.text) == "string" and o.text or ""
		for _, t in ipairs(targets or {}) do
			local name = QA.ObjectiveName(t)
			if name and name ~= "" and text:find(name, 1, true) then
				any = true
				if not o.finished then return false end
			end
		end
	end
	return any
end

local function ActionDone(a, log)
	if a.done then return true end
	local all = #a.quests > 0
	for _, q in ipairs(a.quests) do
		local d
		if a.kind == "pickup" then d = log[q] ~= nil or Done(q)
		elseif a.kind == "handin" then d = Done(q)
		else d = Done(q) or (log[q] and (log[q].complete or ObjectivesDone(q, a.targets))) or false end
		if not d then all = false end
	end
	if all then a.done = true end
	return a.done or false
end

function QA.ZoneCurrent()
	local p = QA.zone
	if not p then return nil end
	for i, s in ipairs(p.stops) do
		for _, a in ipairs(s.actions) do
			if not a.done then return i end
		end
	end
	return #p.stops + 1
end

function QA.ZoneRefresh()
	local p = QA.zone
	if not p then return end
	local log = QA.QuestLog()
	for _, s in ipairs(p.stops) do
		for _, a in ipairs(s.actions) do ActionDone(a, log) end
	end
	QA.ZoneArrow()
	QA.ZoneGuideUpdate()
	QA.ZoneRedraw()
end

-- "Skip": count the current step as done (when the data is wrong, or you'd rather not)
function QA.ZoneSkip()
	local p, i = QA.zone, QA.ZoneCurrent()
	if not p or not p.stops[i] then return end
	for _, a in ipairs(p.stops[i].actions) do a.done = true end
	QA.ZoneRefresh()
end

-- TomTom arrow to the step you're on (only our own waypoint; nothing else of TomTom's is touched)
local wayUid, wayFor
function QA.ZoneArrow()
	local TT = _G.TomTom
	if not (TT and TT.AddWaypoint and TT.RemoveWaypoint) then return end
	local p = QA.zone
	local on = p and not (type(QuestAheadDB) == "table" and QuestAheadDB.arrow == false)
	local i = on and QA.ZoneCurrent()
	local s = on and p.stops[i]
	if s and wayUid and wayFor == s then return end -- same step: leave it be
	if wayUid then pcall(TT.RemoveWaypoint, TT, wayUid); wayUid, wayFor = nil, nil end
	if not s then return end
	local a = s.actions[1]
	local plain = (a.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local ok, uid = pcall(TT.AddWaypoint, TT, p.map, s.x, s.y,
		{ title = "QuestAhead " .. i .. ": " .. plain, persistent = false, minimap = true, world = false, crazy = true,
			silent = true, from = "QuestAhead" })
	if ok then wayUid, wayFor = uid, s end
end

function QA.ZoneClear(keepSaved)
	QA.zone = nil
	QA.ZoneArrow()
	if QA.guide then QA.guide:Hide() end
	QA.ZoneRedraw()
	if not keepSaved and type(QuestAheadDB) == "table" and type(QuestAheadDB.zone) == "table" then
		QuestAheadDB.zone[CharKey()] = nil
	end
end

-- Guide window ---------------------------------------------------------------------------------------

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
QA.guideOffset = 0

local function GuideRows()
	local p, rows = QA.zone, {}
	if not p then return rows end
	local cur = QA.ZoneCurrent()
	for i, s in ipairs(p.stops) do
		for j, a in ipairs(s.actions) do
			local num = (j == 1) and (i .. ". ") or "     "
			local text
			if a.done then text = "|cff808080" .. num .. CHECK .. (a.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
			elseif i == cur then text = "|cffffff00" .. num .. "|r" .. (a.text or "")
			else text = "|cffc0c0c0" .. num .. "|r" .. (a.text or "") end
			rows[#rows + 1] = { stop = i, text = text }
		end
	end
	for _, t in ipairs(p.away or {}) do rows[#rows + 1] = { stop = #p.stops + 1, text = "|cffff9933Later, elsewhere:|r hand in " .. t } end
	return rows
end

local function BuildGuide()
	local g = CreateFrame("Frame", "QuestAheadGuide", UIParent)
	g:SetSize(380, 40 + QA.ZONE_ROWS * 15)
	g:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
	local pos = type(QuestAheadDB) == "table" and QuestAheadDB.guidePos
	if type(pos) == "table" and pos[1] then
		g:ClearAllPoints(); g:SetPoint(pos[1], UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
	end
	g:SetFrameStrata("MEDIUM")
	g:SetClampedToScreen(true)
	g:SetMovable(true)
	g:EnableMouse(true)
	g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", g.StartMoving)
	g:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local a, _, b, x, y = f:GetPoint()
		QuestAheadDB = type(QuestAheadDB) == "table" and QuestAheadDB or {}
		QuestAheadDB.guidePos = { a, nil, b, x, y }
	end)
	g.bg = g:CreateTexture(nil, "BACKGROUND")
	g.bg:SetAllPoints()
	g.bg:SetColorTexture(0, 0, 0, 0.72)
	g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	g.title:SetPoint("TOPLEFT", 8, -7)
	g.title:SetPoint("RIGHT", -100, 0)
	g.title:SetJustifyH("LEFT")
	g.rows = {}
	for i = 1, QA.ZONE_ROWS do
		local fs = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 8, -10 - i * 15)
		fs:SetPoint("RIGHT", -8, 0)
		fs:SetJustifyH("LEFT")
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		g.rows[i] = fs
	end
	local close = CreateFrame("Button", nil, g, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() QA.ZoneClear() end)
	local function btn(label, x, fn, tip)
		local b = CreateFrame("Button", nil, g, "UIPanelButtonTemplate")
		b:SetSize(52, 18)
		b:SetPoint("TOPRIGHT", x, -5)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		b:SetScript("OnEnter", function(f) GameTooltip:SetOwner(f, "ANCHOR_TOP"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return b
	end
	g.skip = btn("Skip", -28, QA.ZoneSkip, "Count the step you're on as done")
	g.replan = btn("Replan", -82, function() if QA.zone then QA.PlanZone(QA.zone.map) end end,
		"Plan again from where you are now, with what's in your log now")
	g:EnableMouseWheel(true)
	g:SetScript("OnMouseWheel", function(_, d)
		QA.guideOffset = (QA.guideOffset or 0) - d * 3
		QA.ZoneGuideUpdate()
	end)
	g.titleHit = CreateFrame("Frame", nil, g)
	g.titleHit:SetPoint("TOPLEFT", 0, 0)
	g.titleHit:SetSize(260, 22)
	g.titleHit:EnableMouse(true)
	g.titleHit:RegisterForDrag("LeftButton")
	g.titleHit:SetScript("OnDragStart", function() g:StartMoving() end)
	g.titleHit:SetScript("OnDragStop", function() g:GetScript("OnDragStop")(g) end)
	g.titleHit:SetScript("OnEnter", function(f)
		local p = QA.zone
		if not p then return end
		GameTooltip:SetOwner(f, "ANCHOR_TOP")
		GameTooltip:AddLine("Zone plan: " .. MapName(p.map), 1, 0.82, 0)
		GameTooltip:AddLine("Quests you can do here now, and what they open up. Nearest next place each time; "
			.. "a follow-on only after the quest before it is handed in.", 1, 1, 1, true)
		if #p.skipped > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Left out:", 1, 0.6, 0.2)
			for i, s in ipairs(p.skipped) do
				if i > 12 then GameTooltip:AddLine("  and " .. (#p.skipped - 12) .. " more", 0.7, 0.7, 0.7); break end
				GameTooltip:AddLine("  " .. s, 0.85, 0.85, 0.85)
			end
		end
		GameTooltip:AddLine("Drag to move. Mouse wheel scrolls.", 0.55, 0.55, 0.55)
		GameTooltip:Show()
	end)
	g.titleHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return g
end

function QA.ZoneGuideUpdate()
	local p = QA.zone
	if not p then if QA.guide then QA.guide:Hide() end return end
	QA.guide = QA.guide or BuildGuide()
	local g = QA.guide
	local rows = GuideRows()
	local cur = QA.ZoneCurrent()
	local done = cur > #p.stops
	g.title:SetText((done and "Zone plan done: " or "Zone plan: ") .. MapName(p.map) .. " (" .. #p.quests .. " quests, step "
		.. math.min(cur, #p.stops) .. "/" .. #p.stops .. ")")
	-- start a line above the step you're on, moved by the mouse wheel
	local first = 1
	for i, r in ipairs(rows) do if r.stop >= cur then first = i; break end end
	local base = first - 1
	local top = math.max(1, #rows - QA.ZONE_ROWS + 1)
	QA.guideOffset = math.max(1 - base, math.min(QA.guideOffset or 0, top - base))
	first = math.max(1, math.min(base + QA.guideOffset, top))
	for i = 1, QA.ZONE_ROWS do
		local r = rows[first + i - 1]
		g.rows[i]:SetText(r and r.text or "")
	end
	g:Show()
end

-- Map markers ----------------------------------------------------------------------------------------

local markers, zlines = {}, {}
local KIND_COLOR = { pickup = { 1, 0.82, 0 }, work = { 1, 0.45, 0.1 }, handin = { 0.35, 1, 0.35 } }

local function MarkerOnEnter(f)
	local p, s = QA.zone, f.stop
	if not (p and s) then return end
	GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Step " .. f.num, 1, 0.82, 0)
	for _, a in ipairs(s.actions) do GameTooltip:AddLine(a.text, 1, 1, 1, true) end
	GameTooltip:Show()
end

local function NewMarker(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(20, 20)
	f.bg = f:CreateTexture(nil, "ARTWORK")
	f.bg:SetAllPoints()
	f.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("CENTER", 0, 0)
	f:EnableMouse(true)
	if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
	f:SetScript("OnEnter", MarkerOnEnter)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end

function QA.ZoneMarkers() return markers end

function QA.ZoneRedraw()
	for _, m in ipairs(markers) do m:Hide() end
	for _, l in ipairs(zlines) do l:Hide() end
	local p = QA.zone
	if not p or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	local lay, canvas = QA.Layer()
	if not lay then return end
	local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
	local cur = QA.ZoneCurrent()
	local n, prev, ln = 0, nil, 0
	for i = cur, #p.stops do
		local s = p.stops[i]
		local x, y = QA.MapPoint(p.map, s.x, s.y)
		if x then
			n = n + 1
			local m = markers[n] or NewMarker(lay)
			markers[n] = m
			m.stop, m.num = s, i
			local c = KIND_COLOR[s.actions[1].kind] or KIND_COLOR.work
			m.bg:SetVertexColor(c[1], c[2], c[3], i == cur and 1 or 0.8)
			m:SetSize(i == cur and 26 or 20, i == cur and 26 or 20)
			m.label:SetText(tostring(i))
			m:ClearAllPoints()
			m:SetPoint("CENTER", canvas, "TOPLEFT", x * w + QA.MARK_SHIFT, -y * h + QA.MARK_SHIFT)
			m:Show()
			if prev and lay.CreateLine then
				ln = ln + 1
				local l = zlines[ln]
				if not l then
					l = lay:CreateLine(nil, "BORDER")
					if l.SetThickness then l:SetThickness(2) end
					zlines[ln] = l
				end
				l:SetColorTexture(1, 1, 1, i == cur + 1 and 0.85 or 0.45)
				l:SetStartPoint("TOPLEFT", canvas, prev[1] * w + QA.MARK_SHIFT, -prev[2] * h + QA.MARK_SHIFT)
				l:SetEndPoint("TOPLEFT", canvas, x * w + QA.MARK_SHIFT, -y * h + QA.MARK_SHIFT)
				l:Show()
			end
			prev = { x, y }
		end
	end
end

-- Start-up, events -------------------------------------------------------------------------------------

local function MapButton()
	local parent = WorldMapFrame and (WorldMapFrame.ScrollContainer or WorldMapFrame)
	if not parent or QA.mapButton then return end
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(84, 20)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", 52, -8)
	if b.SetFrameLevel and parent.GetFrameLevel then b:SetFrameLevel((parent:GetFrameLevel() or 0) + 2100) end
	b:SetText("Plan zone")
	b:SetScript("OnClick", function()
		if IsShiftKeyDown and IsShiftKeyDown() then QA.ZoneClear() return end
		QA.PlanZone(WorldMapFrame:GetMapID())
	end)
	b:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine("QuestAhead: plan this zone", 1, 0.82, 0)
		GameTooltip:AddLine("A route through the quests you can do here: pick-ups, work and hand-ins, nearest first, "
			.. "follow-ons once they open up.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-click: remove the plan", 0.55, 0.55, 0.55)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	QA.mapButton = b
end

local pendingRefresh
local zev = CreateFrame("Frame")
zev:RegisterEvent("PLAYER_LOGIN")
zev:RegisterEvent("QUEST_ACCEPTED")
zev:RegisterEvent("QUEST_TURNED_IN")
zev:RegisterEvent("QUEST_REMOVED")
zev:RegisterEvent("QUEST_LOG_UPDATE")
zev:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "PLAYER_LOGIN" then
		Safe(MapButton)
		if WorldMapFrame then
			WorldMapFrame:HookScript("OnShow", function() Safe(QA.ZoneRedraw) end)
			if type(WorldMapFrame.OnMapChanged) == "function" then
				hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Safe(QA.ZoneRedraw) end)
			end
		end
		-- bring back this character's plan after a /reload or log-in, once Questie's data is ready
		local saved = type(QuestAheadDB) == "table" and type(QuestAheadDB.zone) == "table" and QuestAheadDB.zone[CharKey()]
		if saved and C_Timer and C_Timer.After then
			local tries = 0
			local function try()
				tries = tries + 1
				local db = DB()
				if db and type(db.QuestPointers) == "table" and next(db.QuestPointers) then
					Safe(QA.PlanZone, saved, true)
				elseif tries < 8 then
					C_Timer.After(5, try)
				end
			end
			C_Timer.After(5, try)
		end
		return
	end
	if not QA.zone then return end
	if event == "QUEST_TURNED_IN" and type(a1) == "number" then QA.turnedIn[a1] = true end
	if event == "QUEST_LOG_UPDATE" then
		-- comes in bursts: once a second is plenty
		if pendingRefresh or not (C_Timer and C_Timer.After) then return end
		pendingRefresh = true
		C_Timer.After(1, function() pendingRefresh = nil; Safe(QA.ZoneRefresh) end)
		return
	end
	Safe(QA.ZoneRefresh)
end)
