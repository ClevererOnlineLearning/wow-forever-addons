-- Fastest Way To: routes to your quests, using Questie's database (LibQuestieDB, read only).
-- For each quest in your log: who hands it in, the mobs to kill, where quest items drop (mobs
-- or objects), the objects to use and the places to visit, with your progress from the game.
-- Each one routes you to the spot that is quickest to get to. "Next quest stop" picks the
-- quickest of all of them.
local _, ns = ...
local R = ns.Route
local FW = FastestWay

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) if v == nil or Secret(v) then return nil end return v end
local GREY, WHITE, GOLD, GREEN = "|cff9d9d9d", "|cffffffff", "|cffffd100", "|cff33ff33"
local function Say(m) print("|cff66ccffFastest Way To|r: " .. m) end

local function DB() return _G.LibQuestieDB end
local function Get(entity, id, field)
	local db = DB()
	local e = db and db[entity]
	if not (e and e.Get and id) then return nil end
	local ok, v = pcall(e.Get, id, field)
	if ok then return v end
end

------------------------------------------------------------------------
-- Where things are: Questie spawns are { [areaID] = { { x, y } (percent), ... } }
------------------------------------------------------------------------
local mapOfArea = {}
local function AreaToMap(area)
	local m = mapOfArea[area]
	if m ~= nil then return m or nil end
	m = false
	local ok, ZoneDB = pcall(function() return QuestieLoader and QuestieLoader:ImportModule("ZoneDB") end)
	if ok and ZoneDB and ZoneDB.GetUiMapIdByAreaId then
		local ok2, id = pcall(ZoneDB.GetUiMapIdByAreaId, ZoneDB, area)
		if ok2 and type(id) == "number" and id > 0 then m = id end
	end
	if not m and C_Map.GetAreaInfo then
		local n = Plain(C_Map.GetAreaInfo(area))
		if n then for z in pairs(ns.Data.ZONES) do if R.MapName(z) == n then m = z end end end
	end
	mapOfArea[area] = m
	return m or nil
end

-- Adds every spot in a Questie spawn table to out: { map, x, y }.
local function AddSpawns(out, spawns)
	if type(spawns) ~= "table" then return end
	for area, list in pairs(spawns) do
		local map = type(list) == "table" and AreaToMap(area)
		for _, c in ipairs(map and list or {}) do
			local x, y = tonumber(c[1]), tonumber(c[2])
			if x and y and x >= 0 and y >= 0 then out[#out + 1] = { map = map, x = x / 100, y = y / 100 } end
		end
	end
end

local function NpcSpots(out, id) AddSpawns(out, Get("Npc", id, "spawns")) end
local function ObjectSpots(out, id) AddSpawns(out, Get("Object", id, "spawns")) end

------------------------------------------------------------------------
-- Picking the spot that is quickest to reach
------------------------------------------------------------------------
-- The quickest of these spots: the closest few on your continent (and a couple elsewhere) are
-- timed with the route finder. Returns the point and its travel time.
function FW.Quickest(spots, label)
	local me = R.PlayerPoint()
	local pts = {}
	for _, s in ipairs(spots) do
		local p = R.Point(s.map, s.x, s.y, label, "place")
		if p then pts[#pts + 1] = p end
	end
	if #pts == 0 then return nil end
	if not me then return pts[1] end
	local here, there = {}, {}
	for _, p in ipairs(pts) do
		if p.inst == me.inst then here[#here + 1] = p else there[#there + 1] = p end
	end
	table.sort(here, function(a, b) return R.Dist(me, a) < R.Dist(me, b) end)
	local try = {}
	for i = 1, math.min(5, #here) do try[#try + 1] = here[i] end
	for i = 1, math.min(2, #there) do try[#try + 1] = there[i] end
	local best, bt
	for _, p in ipairs(try) do
		local route = R.Find(me, p, { speed = FW.Speed(), hearth = FW.HearthOK and FW.HearthOK() })
		local t = route and route.time
		if t and (not bt or t < bt) then best, bt = p, t end
	end
	return best or try[1], bt
end

------------------------------------------------------------------------
-- Your quests and what each asks of you
------------------------------------------------------------------------
local function Clean(t)
	t = tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return t
end

-- The game's progress line for a name, if one of the quest's objectives mentions it:
-- text ("3/10"), finished.
local function Progress(objs, name)
	if not name then return nil end
	local lname = name:lower()
	for _, o in ipairs(objs) do
		local text = Plain(o.text)
		if text and Clean(text):lower():find(lname, 1, true) then
			local count = Clean(text):match("(%d+%s*/%s*%d+)")
			return count, Plain(o.finished) and true or false
		end
	end
end

local function NameOf(entity, id) local n = Get(entity, id, "name"); return type(n) == "string" and n or nil end

-- A short "from Kobold Vermin, Kobold Worker" list of where an item comes from.
local function Sources(npcs, objects)
	local names, seen = {}, {}
	for _, id in ipairs(npcs or {}) do
		local n = NameOf("Npc", id)
		if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
	end
	for _, id in ipairs(objects or {}) do
		local n = NameOf("Object", id)
		if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
	end
	if #names == 0 then return "" end
	if #names > 2 then return " from " .. names[1] .. ", " .. names[2] .. " and others" end
	return " from " .. table.concat(names, " and ")
end

-- Every quest in your log that Questie knows where to send you for:
-- { title, id, complete, targets = { { kind, text, done, spots = { {map,x,y} } } } }
function FW.QuestTargets()
	local out = {}
	local QL = C_QuestLog
	if not (DB() and DB().Quest and QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return out end
	for i = 1, QL.GetNumQuestLogEntries() or 0 do
		local ok, info = pcall(QL.GetInfo, i)
		local id = ok and type(info) == "table" and not info.isHeader and Plain(info.questID)
		if id then
			local okO, objs = pcall(QL.GetQuestObjectives, id)
			objs = okO and type(objs) == "table" and objs or {}
			local complete = Plain(info.isComplete)
			if complete == nil and QL.IsComplete then local okC, c = pcall(QL.IsComplete, id); complete = okC and Plain(c) end
			complete = (complete == true or complete == 1)
			local q = { title = Plain(info.title) or ("Quest " .. id), id = id, complete = complete, targets = {} }
			-- Adds a thing to do, if Questie knows where it is; returns it (or nil).
			local function add(kind, text, done, spots)
				if #spots == 0 then return nil end
				local t = { kind = kind, text = text, done = done, spots = spots }
				q.targets[#q.targets + 1] = t
				return t
			end
			local o = Get("Quest", id, "objectives")
			if type(o) == "table" then
				for _, c in ipairs(type(o[1]) == "table" and o[1] or {}) do -- kill
					local name = NameOf("Npc", c[1]) or (type(c[2]) == "string" and c[2])
					local count, done = Progress(objs, name)
					local spots = {}; NpcSpots(spots, c[1])
					add("kill", "Kill " .. (name or "?") .. (count and (" (" .. count .. ")") or ""), done or complete, spots)
				end
				for _, c in ipairs(type(o[2]) == "table" and o[2] or {}) do -- use an object
					local name = (type(c[2]) == "string" and c[2]) or NameOf("Object", c[1])
					local count, done = Progress(objs, name)
					local spots = {}; ObjectSpots(spots, c[1])
					add("object", "Use " .. (name or "?") .. (count and (" (" .. count .. ")") or ""), done or complete, spots)
				end
				for _, c in ipairs(type(o[3]) == "table" and o[3] or {}) do -- collect an item
					local name = NameOf("Item", c[1]) or (type(c[2]) == "string" and c[2])
					local count, done = Progress(objs, name)
					local npcs, objects = Get("Item", c[1], "npcDrops"), Get("Item", c[1], "objectDrops")
					local spots = {}
					for _, n in ipairs(type(npcs) == "table" and npcs or {}) do NpcSpots(spots, n) end
					for _, ob in ipairs(type(objects) == "table" and objects or {}) do ObjectSpots(spots, ob) end
					add("item", "Collect " .. (name or "?") .. (count and (" (" .. count .. ")") or "") .. Sources(npcs, objects), done or complete, spots)
				end
				-- kill credit: a list of { { npc ids }, base npc id, text }; killing any of them counts
				for _, kc in ipairs(type(o[5]) == "table" and o[5] or {}) do
					if type(kc) == "table" and type(kc[1]) == "table" then
						local name = (type(kc[3]) == "string" and kc[3]) or NameOf("Npc", kc[2])
						local count, done = Progress(objs, name)
						local spots = {}
						for _, n in ipairs(kc[1]) do if type(n) == "number" then NpcSpots(spots, n) end end
						add("kill", (name or "Objective") .. (count and (" (" .. count .. ")") or ""), done or complete, spots)
					end
				end
			end
			local te = Get("Quest", id, "triggerEnd") -- go somewhere
			if type(te) == "table" and type(te[2]) == "table" then
				local spots = {}; AddSpawns(spots, te[2])
				local done = false
				for _, ob in ipairs(objs) do if Plain(ob.type) == "event" and Plain(ob.finished) then done = true end end
				add("explore", "Go to: " .. (type(te[1]) == "string" and te[1] or "the quest's place"), done or complete, spots)
			end
			local fb = Get("Quest", id, "finishedBy") -- hand it in
			if type(fb) == "table" then
				local spots, who = {}, nil
				for _, n in ipairs(type(fb[1]) == "table" and fb[1] or {}) do NpcSpots(spots, n); who = who or NameOf("Npc", n) end
				for _, ob in ipairs(type(fb[2]) == "table" and fb[2] or {}) do ObjectSpots(spots, ob); who = who or NameOf("Object", ob) end
				local t = add("handin", "Hand in to " .. (who or "the quest ender"), not complete, spots)
				if t then t.handin = true end
			end
			if #q.targets > 0 then out[#out + 1] = q end
		end
	end
	-- Finished quests first: they only need handing in.
	table.sort(out, function(a, b) if a.complete ~= b.complete then return a.complete end return a.title < b.title end)
	return out
end

------------------------------------------------------------------------
-- The Quests menu
------------------------------------------------------------------------
local function Route(t, questTitle)
	local p = FW.Quickest(t.spots, t.text)
	if not p then Say("couldn't place " .. t.text .. " on the map.") return end
	FW.Go(p, t.text .. " (" .. R.MapName(p.zone or p.map) .. ")")
end

-- What's next across your whole log: hand-ins of finished quests and objectives not yet done.
-- Each one's closest spot on your continent is a candidate; the six closest are timed and the
-- quickest wins.
function FW.NextQuestStop()
	local me = R.PlayerPoint()
	local cands, any = {}, nil
	for _, q in ipairs(FW.QuestTargets()) do
		for _, t in ipairs(q.targets) do
			if not t.done then
				local best, bd
				for _, s in ipairs(t.spots) do
					local p = R.Point(s.map, s.x, s.y, t.text, "place")
					if p then
						any = any or { p = p, t = t, q = q }
						if me and p.inst == me.inst then
							local d = R.Dist(me, p)
							if not bd or d < bd then best, bd = p, d end
						end
					end
				end
				if best then cands[#cands + 1] = { p = best, d = bd, t = t, q = q } end
			end
		end
	end
	if #cands == 0 and not any then Say("nothing left to do in your quest log that Questie can place.") return end
	table.sort(cands, function(a, b) return a.d < b.d end)
	local pick, bt
	for i = 1, math.min(6, #cands) do
		local c = cands[i]
		local route = me and R.Find(me, c.p, { speed = FW.Speed(), hearth = FW.HearthOK and FW.HearthOK() })
		if route and (not bt or route.time < bt) then pick, bt = c, route.time end
	end
	pick = pick or cands[1] or any
	FW.Go(pick.p, pick.t.text .. " (" .. pick.q.title .. ")")
end

-- Builds the menu's contents; errors are caught by FW.QuestMenu and reported in chat.
local function BuildMenu(root)
		if not (DB() and DB().Quest) then
			-- Without Questie: the mobs your quest log names, as before.
			local quests = FW.QuestMobs and FW.QuestMobs() or {}
			root:CreateTitle(GREY .. "Install Questie for hand-ins, items and objects too.|r")
			for _, q in ipairs(quests) do
				root:CreateTitle(q.title)
				for _, m in ipairs(q.mobs) do
					root:CreateButton(m.name, function()
						local p, why = FW.MobPoint(m.name)
						if not p then Say(m.name .. ": " .. why .. ".") return end
						FW.Go(p, m.name .. " (" .. R.MapName(p.zone or p.map) .. ")")
					end)
				end
			end
			return
		end
		local quests = FW.QuestTargets()
		if #quests == 0 then root:CreateTitle("Nothing in your quest log that Questie can place") return end
		root:CreateButton(GOLD .. "Next quest stop|r " .. GREY .. "(the quickest thing to do)|r", FW.NextQuestStop)
		if root.CreateDivider then root:CreateDivider() end
		for _, q in ipairs(quests) do
			local sub = root:CreateButton((q.complete and (GREEN .. "Done: |r") or "") .. q.title)
			for _, t in ipairs(q.targets) do
				local label = t.done and (GREY .. t.text .. (t.handin and " (finish it first)" or " (done)") .. "|r") or t.text
				sub:CreateButton(label, function() Route(t, q.title) end)
			end
		end
end

function FW.QuestMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then Say("this game has no menus; type a place instead.") return end
	-- Read the quest log first, outside the menu, so a problem shows in chat instead of an empty click.
	local ok, err = pcall(FW.QuestTargets)
	if not ok then Say("couldn't read your quests: " .. tostring(err)) return end
	local ok2, err2 = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
		local okB, errB = pcall(BuildMenu, root)
		if not okB then Say("the Quests menu failed: " .. tostring(errB)) end
	end)
	if not ok2 then Say("couldn't open the Quests menu: " .. tostring(err2)) end
end

-- /fw quests: what Fastest Way can see of your quests, for checking.
function FW.QuestReport()
	local db = DB()
	Say("Questie database: " .. (db and (db.Quest and "found" or "found, but no quest data") or "not found (is Questie enabled?)"))
	local QL = C_QuestLog
	Say("quest log entries: " .. tostring(QL and QL.GetNumQuestLogEntries and QL.GetNumQuestLogEntries()))
	local ok, quests = pcall(FW.QuestTargets)
	if not ok then Say("error reading quests: " .. tostring(quests)) return end
	Say(#quests .. " quests it can route to")
	for i, q in ipairs(quests) do
		if i > 8 then Say("  ...") break end
		Say(("  %s: %d things to do%s"):format(q.title, #q.targets, q.complete and " (done)" or ""))
	end
end
