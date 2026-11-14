-- Fastest Way To: window, search box, quest list, Alt+click on the world map, map pin,
-- minimap button and /fw.
local _, ns = ...
local S, R, D = ns.Skin, ns.Route, ns.Data
local FW = {}
_G.FastestWay = FW
FW.Route = R

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) if v == nil or Secret(v) then return nil end return v end
local GREY, WHITE, GOLD, GREEN, ORANGE = "|cff9d9d9d", "|cffffffff", "|cffffd100", "|cff33ff33", "|cffff9933"

local DEFAULTS = { hearth = true, speed = "auto", minimap = { hide = false, angle = 300 }, arrow = true, line = true, arrowLocked = false, walkStyle = "balanced" }
local db

local function Say(m) print("|cff66ccffFastest Way To|r: " .. m) end

------------------------------------------------------------------------
-- Speed
------------------------------------------------------------------------
function FW.Speed()
	local key = db.speed
	if key == "auto" then
		local ok, lvl = pcall(UnitLevel, "player")
		lvl = ok and Plain(lvl) or 1
		key = lvl >= 60 and "mount100" or (lvl >= 40 and "mount60" or "run")
	end
	for _, s in ipairs(D.SPEEDS) do if s.key == key then return s.yps, s.name end end
	return 7, "Running"
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local W = 470
local CW = W - 24
local L = 14
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local win = S.Window("FastestWayFrame", "Fastest Way To", "Interface\\Icons\\INV_Misc_Map_01",
	GetMeta and GetMeta("FastestWay", "Version"), W, 470)
local more = S.MoreButton(win.head, "FastestWay", win)
more:SetPoint("RIGHT", win.close, "LEFT", -8, 0)

-- Where to?
local c1 = S.Card(win, "Where do you want to go?", 12, -44, CW)
local edit = S.Edit(c1, CW - 2 * L - 178, 24)
edit:SetPoint("TOPLEFT", L, -34)
local goBtn = S.Button(c1, "Go", 60, 24, true)
goBtn:SetPoint("LEFT", edit, "RIGHT", 6, 0)
local questBtn = S.Button(c1, "Quests", 104, 24)
questBtn:SetPoint("LEFT", goBtn, "RIGHT", 6, 0)
local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("LEFT", 8, 0)
hint:SetText("Town, zone or dock...")
edit:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
S.Note(c1, "Or hold Alt and click anywhere on the world map.", L, -66, CW - 2 * L)
local arrowChk = S.Check(c1, "Arrow on screen")
arrowChk:SetPoint("TOPLEFT", L, -88)
local lineChk = S.Check(c1, "Line on map")
lineChk:SetPoint("TOPLEFT", L + 128, -88)
-- How walks are chosen (the terrain router's route styles)
local STYLES = { "fastest", "balanced", "roads" }
local STYLE_NAMES = { fastest = "Fastest", balanced = "Balanced", roads = "Roads" }
local styleBtn = S.Button(c1, "", 132, 22)
styleBtn:SetPoint("TOPRIGHT", -L, -84)
S.Tip(styleBtn, "How to walk", "Fastest: the shortest way you can walk or ride.\nBalanced: keeps to roads when that adds no more than a fifth to the walk.\nRoads: keeps to roads and paths wherever it can.\nClick to change.")
S.Tip(arrowChk, "Arrow on screen", "An arrow that points to where your current step ends, with how far it is. Green: you're heading the right way. Drag it to move it; right-click it to lock it in place.")
S.Tip(lineChk, "Route line on the map", "Draws your route as a dotted line on the world map: gold where you run, blue where you fly, white for boats and zeppelins.")
arrowChk:SetScript("OnClick", function(self) db.arrow = self:GetChecked() and true or false; if FW.RouteChanged then FW.RouteChanged() end end)
lineChk:SetScript("OnClick", function(self) db.line = self:GetChecked() and true or false; if FW.RouteChanged then FW.RouteChanged() end end)
local function StyleText() return "Walk: " .. (STYLE_NAMES[db.walkStyle] or "Balanced") end
styleBtn:SetScript("OnClick", function(self)
	local i = 1
	for k, v in ipairs(STYLES) do if v == db.walkStyle then i = k end end
	db.walkStyle = STYLES[i % #STYLES + 1]
	self:SetText(StyleText())
	if FW.Reshow then FW.Reshow() end
end)
c1:SetHeight(116)
S.Tip(questBtn, "Quests", "Your quest log: hand-ins, mobs to kill, where quest items drop, objects to use and places to visit, from Questie's database. Each routes you to the quickest spot. \"Next quest stop\" picks the quickest thing to do.")

-- The route
local c2 = S.Card(win, "Route", 12, S.Below(c1), CW)
local MAXROWS = 9
local ICONS = {
	run = "Interface\\Icons\\Ability_Rogue_Sprint",
	fly = "Interface\\Icons\\Ability_Mount_Gryphon_01",
	boat = "Interface\\Icons\\INV_Misc_Anchor",
	zeppelin = "Interface\\Icons\\INV_Misc_Bomb_04",
	tram = "Interface\\Icons\\INV_Gizmo_02",
	hearth = "Interface\\Icons\\INV_Misc_Rune_01",
}
local rows = {}
for i = 1, MAXROWS do
	local r = CreateFrame("Frame", nil, c2)
	r:SetSize(CW - 2 * L, 32)
	local num = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	num:SetPoint("TOPLEFT", 0, -8)
	num:SetWidth(16)
	local ic = r:CreateTexture(nil, "ARTWORK")
	ic:SetSize(22, 22)
	ic:SetPoint("TOPLEFT", 20, -4)
	ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t:SetPoint("TOPLEFT", 50, -4)
	t:SetWidth(CW - 2 * L - 50)
	t:SetJustifyH("LEFT")
	local sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
	r.num, r.icon, r.text, r.sub = num, ic, t, sub
	rows[i] = r
end
-- Hearthstone use: the tick box in the footer, and not while it's known to be on cooldown.
function FW.HearthOK() return db.hearth and R.HearthReady() ~= false end
-- "Not ready" on a hearthstone step: leave it out for an hour (or until it's seen used again).
local notReady = S.Button(c2, "Not ready", 76, 20)
notReady:Hide()
S.Tip(notReady, "Hearthstone not ready?", "Click if your hearthstone is on cooldown: the route is worked out again without it, and it's left out for an hour. (The game doesn't let add-ons see its cooldown.)")
-- Used by the "Not ready" button here and the one under the arrow in the middle of the screen.
function FW.HearthNotReady()
	FastestWayCharDB.hearthAt = time()
	Say("leaving your hearthstone out for an hour. Untick and tick \"Use my hearthstone\" to use it again sooner.")
	if FW.Reshow then FW.Reshow() end
end
notReady:SetScript("OnClick", function() FW.HearthNotReady() end)
local summary = c2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
summary:SetJustifyH("LEFT")
summary:SetWidth(CW - 2 * L)
local alt = c2:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
alt:SetJustifyH("LEFT")
alt:SetWidth(CW - 2 * L)
alt:SetSpacing(2)

local foot = S.Footer(win, 40)
local hearthChk = S.Check(foot, "Use my hearthstone")
hearthChk:SetPoint("LEFT", 14, 0)
local speedBtn = S.Button(foot, "", 150, 24)
speedBtn:SetPoint("LEFT", hearthChk.label, "RIGHT", 14, 0)
S.Tip(speedBtn, "How fast you travel on land", "Click to change: automatic (by level), running, or a mount.")
local refresh = S.Button(foot, "Update from here", 140, 24)
refresh:SetPoint("RIGHT", -12, 0)

------------------------------------------------------------------------
-- Map pin for where the current step ends
------------------------------------------------------------------------
local Pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local REF = "FastestWay"
local function MakePin(size)
	local f = CreateFrame("Frame")
	f:SetSize(size, size)
	local t = f:CreateTexture(nil, "OVERLAY")
	t:SetAllPoints()
	t:SetTexture("Interface\\COMMON\\Indicator-Yellow")
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Fastest Way To")
		if self.text then GameTooltip:AddLine(self.text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end
local worldPin, miniPin = MakePin(18), MakePin(14)

local function ClearPin()
	if Pins then pcall(Pins.RemoveAllWorldMapIcons, Pins, REF); pcall(Pins.RemoveAllMinimapIcons, Pins, REF) end
end
local function SetPin(p, text)
	ClearPin()
	if not (Pins and p) then return end
	worldPin.text, miniPin.text = text, text
	pcall(Pins.AddWorldMapIconMap, Pins, REF, worldPin, p.map, p.x, p.y, HBD_PINS_WORLDMAP_SHOW_PARENT)
	pcall(Pins.AddMinimapIconMap, Pins, REF, miniPin, p.map, p.x, p.y, true, true)
end

------------------------------------------------------------------------
-- Showing a route
------------------------------------------------------------------------
local current -- { dest = point, name = text }

local function ShowRows(steps)
	notReady:Hide()
	local y = S.Row(c2, 0)
	for i, r in ipairs(rows) do
		local s = steps[i]
		if s then
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", L, y)
			r.num:SetText(i .. ".")
			r.icon:SetTexture(ICONS[s.kind] or ICONS.run)
			r.text:SetText(s.text)
			-- a hearthstone step gets the "Not ready" button beside it
			r.text:SetWidth(CW - 2 * L - 50 - (s.kind == "hearth" and 84 or 0))
			if s.kind == "hearth" then
				notReady:ClearAllPoints(); notReady:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -2); notReady:Show()
			end
			r.sub:SetText(R.Minutes(s.time))
			local h = (r.text:GetStringHeight() or 14) + 18
			if h < 34 then h = 34 end
			r:SetHeight(h)
			y = y - h
			r:Show()
		else
			r:Hide()
		end
	end
	return y
end

local function Layout(y)
	summary:ClearAllPoints(); summary:SetPoint("TOPLEFT", L, y - 6)
	local sh = summary:GetText() ~= "" and ((summary:GetStringHeight() or 14) + 8) or 0
	alt:ClearAllPoints(); alt:SetPoint("TOPLEFT", L, y - 6 - sh)
	local ah = alt:GetText() ~= "" and ((alt:GetStringHeight() or 12) + 6) or 0
	c2:SetHeight(-y + 6 + sh + ah + 12)
	win:SetHeight(-S.Below(c2) + 40 + 2)
end

-- Plans with whatever real walking costs the terrain router has worked out so far (the rest are
-- estimates). Returns the route and every place it considered.
local W = ns.Walk
local function Plan(start, knownOnly)
	local nodes = {}
	local style = db.walkStyle
	local route = R.Find(start, current.dest, {
		speed = FW.Speed(), hearth = FW.HearthOK(), knownOnly = knownOnly, nodesOut = nodes,
		walk = W and function(u, v) return W.Cost(u, v, style) end,
	})
	return route, nodes
end

-- Puts the terrain router's drawn paths on the walking legs it has worked out. When finished,
-- legs it couldn't work out are marked as estimates ("approximate path").
local function Dress(route, finished)
	if not route then return end
	local speed, style = FW.Speed(), db.walkStyle
	for _, l in ipairs(route.legs) do
		if l.kind == "run" then
			local pts, yards = nil, nil
			if W and l.exact then pts, yards = W.Points(l.from, l.to, style) end
			if pts and #pts >= 2 then
				l.pts = pts
				l.through = R.ZonesAlong(pts, l.from.zone, l.to.zone)
				if yards and style == "balanced" then -- Balanced may draw the road path: time it as drawn
					local t = yards / speed
					route.time = route.time + t - l.time
					l.time, l.len = t, yards
				end
			end
			l.estimated = finished and l.approx or nil
			l.why = l.approx and W and W.Reason(l.from, l.to, style) or nil
		end
	end
end

local function Render(route, start, state)
	FW.route, FW.steps, FW.nextStop = nil, nil, nil
	summary:SetText(""); alt:SetText("")
	c2.y = -34
	if not route then
		ShowRows({}); summary:SetText("|cffff6666No way found from here. You may need a boat, zeppelin or portal this add-on doesn't know yet.|r")
		ClearPin(); Layout(c2.y); return
	end
	Dress(route, state == "done")
	local steps = R.Describe(route)
	if #steps == 0 then
		ShowRows({}); summary:SetText(GREEN .. "You're there!|r"); ClearPin(); Layout(c2.y); return
	end
	local y = ShowRows(steps)
	local approx = false
	for _, l in ipairs(route.legs) do if l.estimated then approx = true end end
	summary:SetText(GOLD .. "Total: " .. R.Minutes(route.time) .. "|r"
		.. (state == "refining" and (GREY .. "   working out the walking paths...|r") or "")
		.. (approx and (GREY .. "\nWalking marked \"approximate path\" is an estimate: there is no terrain map for it.|r") or ""))
	-- If the route counts on flight paths you might not have, say what to do without them.
	local usesMaybe = false
	for _, s in ipairs(steps) do if s.maybe then usesMaybe = true end end
	if usesMaybe then
		-- "maybe" only happens on a continent whose flight map it hasn't seen yet: say how to fix that.
		local note = ORANGE .. "I don't know which flight paths you have here yet. Talk to any flight master and open the flight map once: the route then updates to use only the ones you have.|r"
		local plain = Plan(start, true)
		if plain then
			local words = {}
			for i, s in ipairs(R.Describe(plain)) do words[#words + 1] = i .. ". " .. s.text end
			note = note .. "\n\nWithout those flight paths (" .. R.Minutes(plain.time) .. "):\n" .. table.concat(words, "\n")
		end
		alt:SetText(note)
	end
	SetPin(steps[1].to, "Step 1: " .. steps[1].text)
	FW.nextStop = steps[1].to
	FW.route, FW.steps, FW.routeState = route, steps, state
	Layout(y)
	if state == "done" and FW.DebugRoute then FW.DebugRoute(route) end
	if FW.RouteChanged then FW.RouteChanged() end
end
FW.Render = Render

-- Refines the shown route with the terrain router, a little each frame:
--   1. real walking costs from you to every place, and from every place to the destination
--   2. plan again; real costs for any walk between two places the new route uses; repeat
--   3. the drawn paths of the route's walks
-- A newer route (you moved on, picked somewhere else) cancels an older refinement.
local function Refine(start, dest)
	if not (W and W.Available(start.inst)) then Render(Plan(start), start, "done") return end
	W.Cancel()
	local gen = W.generation
	local function alive() return gen == W.generation and current and current.dest == dest end
	local _, nodes = Plan(start)
	local style = db.walkStyle
	W.Settle(start, dest, nodes, style, function()
		if not alive() then return end
		local tries = 0
		local function step()
			if not alive() then return end
			local route = Plan(start)
			local need = {}
			for _, l in ipairs(route and route.legs or {}) do
				if l.kind == "run" and l.approx and l.from.inst == l.to.inst then need[#need + 1] = { l.from, l.to } end
			end
			if #need > 0 and tries < 6 then
				tries = tries + 1
				Render(route, start, "refining")
				W.Need(need, style, step)
				return
			end
			local walks = {}
			for _, l in ipairs(route and route.legs or {}) do
				if l.kind == "run" and l.exact then walks[#walks + 1] = { l.from, l.to } end
			end
			W.Geometry(walks, style, function() if alive() then Render(Plan(start), start, "done") end end)
		end
		step()
	end)
end

-- Works the current route out again (after a setting changes).
function FW.Reshow() if current then FW.Show(current.dest, current.name) end end

function FW.Show(dest, name)
	current = dest and { dest = dest, name = name or dest.label } or nil
	FW.route, FW.steps, FW.nextStop = nil, nil, nil
	if W then W.Cancel() end
	c2.title:SetText(current and ("Route to " .. current.name) or "Route")
	summary:SetText(""); alt:SetText("")
	c2.y = -34
	if not current then
		ShowRows({}); summary:SetText(GREY .. "Type a place above, pick a quest, or Alt+click the world map.|r")
		ClearPin(); Layout(c2.y); return
	end
	local start = R.PlayerPoint()
	if not start then
		ShowRows({}); summary:SetText("|cffff6666Can't tell where you are right now (in a dungeon?).|r")
		ClearPin(); Layout(c2.y); return
	end
	local terrain = W and W.Available(start.inst)
	Render(Plan(start), start, terrain and "refining" or "done") -- the estimate straight away
	if terrain then Refine(start, current.dest) end
end

------------------------------------------------------------------------
-- Type-ahead list under the search box
------------------------------------------------------------------------
local sugg = CreateFrame("Frame", nil, UIParent)
sugg:SetFrameStrata("TOOLTIP")
sugg:SetWidth(260)
S.Panel(sugg, 0.98)
sugg:Hide()
local srows, sres, ssel = {}, {}, 0
for i = 1, 8 do
	local b = CreateFrame("Button", nil, sugg)
	b:SetSize(248, 18)
	b:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 18)
	local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.18)
	b:SetHighlightTexture(hl)
	local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", 4, 0); t:SetJustifyH("LEFT")
	b.text = t
	b:SetScript("OnClick", function(self) local p = sres[self.i]; sugg:Hide(); if p then edit:SetText(p.name); edit:ClearFocus(); FW.Show(p.point, p.name) end end)
	srows[i] = b
end
local function Suggest()
	sres = R.Search(edit:GetText(), 8)
	ssel = 0
	if #sres == 0 then sugg:Hide() return end
	for i, b in ipairs(srows) do
		local p = sres[i]
		if p then b.i = i; b.text:SetText(p.name .. GREY .. (p.kind == "zone" and "  zone" or "") .. "|r"); b:Show(); b:UnlockHighlight() else b:Hide() end
	end
	sugg:SetHeight(10 + #sres * 18)
	sugg:ClearAllPoints()
	sugg:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -2)
	sugg:Show()
end
edit:HookScript("OnTextChanged", function(_, user) if user then Suggest() end end)
edit:SetScript("OnArrowPressed", function(_, key)
	if not sugg:IsShown() then return end
	if key == "DOWN" then ssel = ssel % #sres + 1 elseif key == "UP" then ssel = ssel <= 1 and #sres or ssel - 1 end
	for i, b in ipairs(srows) do if i == ssel then b:LockHighlight() else b:UnlockHighlight() end end
end)
local function Go()
	local p = sres[ssel > 0 and ssel or 1] or R.Search(edit:GetText(), 1)[1]
	sugg:Hide()
	edit:ClearFocus()
	if p then edit:SetText(p.name); FW.Show(p.point, p.name) else Say("no place called \"" .. edit:GetText() .. "\".") end
end
edit:SetScript("OnEnterPressed", Go)
edit:HookScript("OnEditFocusLost", function() if not sugg:IsMouseOver() then sugg:Hide() end end)
edit:HookScript("OnEscapePressed", function() sugg:Hide() end)
goBtn:SetScript("OnClick", Go)
win:HookScript("OnHide", function() sugg:Hide() end)

------------------------------------------------------------------------
-- Quests: route to the nearest spot a quest mob lives (Questie's database)
------------------------------------------------------------------------
local function MobFromText(t)
	t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	t = t:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
	t = t:gsub("%s+[Ss]lain$", ""):gsub("%s+[Kk]illed$", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #t < 2 or #t > 60 then return nil end
	return t
end

function FW.QuestMobs()
	local out = {}
	local QL = C_QuestLog
	if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives) then return out end
	for i = 1, QL.GetNumQuestLogEntries() or 0 do
		local ok, info = pcall(QL.GetInfo, i)
		if ok and type(info) == "table" and not info.isHeader and info.questID then
			local okO, objs = pcall(QL.GetQuestObjectives, info.questID)
			local mobs = {}
			for _, o in ipairs(okO and type(objs) == "table" and objs or {}) do
				local text = Plain(o.text)
				if o.type == "monster" and text then
					local name = MobFromText(text)
					if name then mobs[#mobs + 1] = { name = name, done = Plain(o.finished) } end
				end
			end
			if #mobs > 0 then out[#out + 1] = { title = Plain(info.title) or "Quest", mobs = mobs } end
		end
	end
	return out
end

local nameIndex
local function AreaToMap(area)
	local ok, ZoneDB = pcall(function() return QuestieLoader and QuestieLoader:ImportModule("ZoneDB") end)
	if ok and ZoneDB and ZoneDB.GetUiMapIdByAreaId then
		local ok2, id = pcall(ZoneDB.GetUiMapIdByAreaId, ZoneDB, area)
		if ok2 and type(id) == "number" and id > 0 then return id end
	end
	local n = C_Map.GetAreaInfo and Plain(C_Map.GetAreaInfo(area))
	if n then for z in pairs(D.ZONES) do if R.MapName(z) == n then return z end end end
end

-- Nearest spot (that you can get to) where a mob with this name lives.
function FW.MobPoint(name)
	local DB = _G.LibQuestieDB
	local NPC = DB and DB.Npc
	if not (NPC and NPC.GetAllIds and NPC.Get) then return nil, "needs Questie" end
	if not nameIndex then
		nameIndex = {}
		for _, id in ipairs(NPC.GetAllIds() or {}) do
			local ok, n = pcall(NPC.Get, id, "name")
			if ok and type(n) == "string" then
				local k = n:lower()
				nameIndex[k] = nameIndex[k] or {}
				table.insert(nameIndex[k], id)
			end
		end
	end
	local me = R.PlayerPoint()
	local best, bd
	for _, id in ipairs(nameIndex[name:lower()] or {}) do
		local ok, spawns = pcall(NPC.Get, id, "spawns")
		for area, list in pairs(ok and type(spawns) == "table" and spawns or {}) do
			local map = AreaToMap(area)
			for _, c in ipairs(map and type(list) == "table" and list or {}) do
				local x, y = tonumber(c[1]), tonumber(c[2])
				if x and y and x >= 0 then
					local p = R.Point(map, x / 100, y / 100, name, "place")
					if p then
						local d = me and (me.inst == p.inst and R.Dist(me, p) or 1e9) or 0
						if not bd or d < bd then best, bd = p, d end
					end
				end
			end
		end
	end
	if not best then return nil, "Questie doesn't know where it lives" end
	return best
end

-- Quests: the menu lives in Quests.lua (Questie's database), routed through FW.Go.
questBtn:SetScript("OnClick", function(self)
	if FW.QuestMenu then FW.QuestMenu(self)
	else Say("the Quests menu is in a new file: close WoW completely and start it again (a /reload isn't enough).") end
end)

-- Route to a point picked from a menu (quests), filling in the search box.
function FW.Go(p, name)
	win:Show()
	edit:SetText(name)
	edit:ClearFocus()
	FW.Show(p, name)
end

------------------------------------------------------------------------
-- Alt+click on the world map
------------------------------------------------------------------------
local function MapClicked(mapID, x, y)
	if not (mapID and x and y) then return end
	local p = R.Point(mapID, x, y, "the spot you clicked", "place")
	if not p then Say("can't route to that map.") return end
	local zone = p.zone and R.MapName(p.zone) or R.MapName(mapID)
	local name = ("%s (%.0f, %.0f)"):format(zone, x * 100, y * 100)
	if p.zone and p.zone ~= mapID and C_Map.GetMapInfoAtPosition then
		-- also give zone-local coordinates, like the game's own map shows
		local HBD = LibStub("HereBeDragons-2.0", true)
		local zx, zy
		if HBD then zx, zy = HBD:TranslateZoneCoordinates(x, y, mapID, p.zone) end
		if zx and zy then name = ("%s (%.0f, %.0f)"):format(zone, zx * 100, zy * 100) end
	end
	p.label = name
	edit:SetText(name)
	win:Show()
	FW.Show(p, name)
end
FW.MapClicked = MapClicked

local function HookMap()
	local wm = _G.WorldMapFrame
	if not wm or wm.fwHooked then return end
	wm.fwHooked = true
	if wm.AddCanvasClickHandler then
		wm:AddCanvasClickHandler(function(map, button, cx, cy)
			if button == "LeftButton" and IsAltKeyDown() then
				local id = map.GetMapID and map:GetMapID()
				MapClicked(id, cx, cy)
				return true
			end
		end, 100)
	elseif wm.ScrollContainer then
		wm.ScrollContainer:HookScript("OnMouseUp", function(sc, button)
			if button == "LeftButton" and IsAltKeyDown() and sc.GetNormalizedCursorPosition then
				local cx, cy = sc:GetNormalizedCursorPosition()
				MapClicked(wm:GetMapID(), cx, cy)
			end
		end)
	end
end

------------------------------------------------------------------------
-- Options in the footer
------------------------------------------------------------------------
local SPEEDKEYS = { "auto", "run", "mount60", "mount100" }
local function SpeedText()
	if db.speed == "auto" then local _, n = FW.Speed(); return "Speed: auto (" .. n .. ")" end
	local _, n = FW.Speed(); return "Speed: " .. n
end
speedBtn:SetScript("OnClick", function()
	local i = 1
	for k, v in ipairs(SPEEDKEYS) do if v == db.speed then i = k end end
	db.speed = SPEEDKEYS[i % #SPEEDKEYS + 1]
	speedBtn:SetText(SpeedText())
	if current then FW.Show(current.dest, current.name) end
end)
S.Tip(hearthChk, "Use my hearthstone", "Lets routes start with your hearthstone. While it's on cooldown (you used it in the last hour, or clicked \"Not ready\") routes leave it out by themselves.")
hearthChk:SetScript("OnClick", function(self)
	db.hearth = self:GetChecked() and true or false
	if db.hearth then FastestWayCharDB.hearthAt = nil end -- ticking it again: it's ready
	if current then FW.Show(current.dest, current.name) end
end)
refresh:SetScript("OnClick", function() if current then FW.Show(current.dest, current.name) end end)
win:HookScript("OnShow", function()
	hearthChk:SetChecked(db.hearth)
	arrowChk:SetChecked(db.arrow)
	styleBtn:SetText(StyleText())
	lineChk:SetChecked(db.line)
	speedBtn:SetText(SpeedText())
	if current then FW.Show(current.dest, current.name) else FW.Show(nil) end
end)

-- When you reach the end of a step, or land, or change zone, the route updates itself.
local watch = CreateFrame("Frame")
local acc = 0
watch:SetScript("OnUpdate", function(_, dt)
	acc = acc + dt
	if acc < 2 then return end
	acc = 0
	if not current or not FW.nextStop then return end
	local ok, onTaxi = pcall(UnitOnTaxi, "player")
	if ok and Plain(onTaxi) then return end
	local me = R.PlayerPoint()
	if me and me.inst == FW.nextStop.inst and R.Dist(me, FW.nextStop) < 40 then FW.Show(current.dest, current.name) end
end)

function FW.Toggle() win:SetShown(not win:IsShown()) end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local btn = CreateFrame("Button", "FastestWayMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53); border:SetPoint("TOPLEFT")
btn:Hide()
local atan2 = math.atan2 or function(a, b) return math.atan(a, b) end
local function Place()
	local a = math.rad(db.minimap.angle or 300)
	local r = (Minimap:GetWidth() / 2) + 5
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
function FW.UpdateMinimapButton() if db.minimap.hide then btn:Hide() else Place(); btn:Show() end end
S.Group(btn, "FastestWay", function() return db and db.minimap end, function() FW.UpdateMinimapButton() end) -- the shared minimap bag
btn:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		db.minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
		Place()
	end)
end)
btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
btn:SetScript("OnClick", function(_, b)
	if b == "RightButton" then
		if current then current = nil; ClearPin(); FW.Show(nil); Say("route cleared.") end
	else
		FW.Toggle()
	end
end)
btn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Fastest Way To")
	if current then GameTooltip:AddLine("Going to: " .. WHITE .. current.name .. "|r", 0.8, 0.8, 0.8) end
	GameTooltip:AddLine("|cffffffffLeft-click|r  open", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r  clear the route", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffAlt+click the world map|r  route there", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------
-- Events and /fw
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, e, a1, a2, a3)
	if e == "ADDON_LOADED" then
		if a1 ~= "FastestWay" then return end
		FastestWayDB = FastestWayDB or {}
		FastestWayCharDB = FastestWayCharDB or {}
		for k, v in pairs(DEFAULTS) do
			if FastestWayDB[k] == nil then
				if type(v) == "table" then local c = {} for i, x in pairs(v) do c[i] = x end FastestWayDB[k] = c else FastestWayDB[k] = v end
			end
		end
		db = FastestWayDB
		FW.db = db
		return
	elseif e == "PLAYER_LOGIN" then
		FW.UpdateMinimapButton()
		HookMap()
		for _, x in ipairs({ "TAXIMAP_OPENED", "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED" }) do pcall(self.RegisterEvent, self, x) end
		pcall(self.RegisterUnitEvent, self, "UNIT_SPELLCAST_SUCCEEDED", "player")
		return
	end
	if e == "UNIT_SPELLCAST_SUCCEEDED" then
		local spell = a3
		if Plain(spell) == R.HEARTH_SPELL then FastestWayCharDB.hearthAt = time() end -- used: on cooldown for an hour
		return
	end
	if e == "TAXIMAP_OPENED" then
		local map = (GetTaxiMapID and Plain(GetTaxiMapID())) or (C_Map.GetBestMapForUnit and R.ZoneOf(Plain(C_Map.GetBestMapForUnit("player"))))
		local n, cont = 0, nil
		for _, m in ipairs({ map, D.EK, D.KALIMDOR }) do
			if m then local k, c = R.LearnFlightPaths(m); n = n + (k or 0); cont = cont or c end
		end
		if cont and n > 0 then Say("learned your flight paths on " .. (R.MapName(cont) or "this continent") .. ". Routes there now use only the ones you have.") end
		if current then FW.Show(current.dest, current.name) end -- straight away, while you're at the flight master
	elseif current and (e == "ZONE_CHANGED_NEW_AREA" or e == "PLAYER_CONTROL_GAINED") then
		C_Timer.After(1, function() if current then FW.Show(current.dest, current.name) end end)
	end
end)

-- /fw debug: what the route is made of, where each walk's numbers came from, and what failed.
function FW.DebugRoute(route)
	if not (db and db.debug and route) then return end
	local W = ns.Walk
	local n, jobs = 0, 0
	if W then n, jobs = W.Stats() end
	Say(("route: %s, %d steps, walk style %s, engine %s, %d walks cached"):format(R.Minutes(route.time), #route.legs,
		db.walkStyle, (W and W.Available(route.legs[1] and route.legs[1].from.inst)) and "on" or "no data here", n))
	for i, l in ipairs(route.legs) do
		local from, to = l.from and (l.from.town or l.from.label) or "?", l.to and (l.to.town or l.to.label) or "?"
		local src = l.kind ~= "run" and l.kind or (l.exact and "terrain" or ("ESTIMATE" .. (l.why and (" (" .. l.why .. ")") or "")))
		local extra = ""
		if l.kind == "run" then
			extra = ("  %d yd, %d corners%s"):format(math.floor((l.len or 0) + 0.5), l.pts and #l.pts or 0,
				l.pts and l.pts.wet and l.pts.wet > 0 and (", swims " .. math.floor(l.pts.wet + 0.5) .. " yd") or "")
			if l.through and #l.through > 0 then
				local z = {}
				for _, id in ipairs(l.through) do z[#z + 1] = R.MapName(id) end
				extra = extra .. "  via " .. table.concat(z, ", ")
			end
		end
		Say(("  %d. %s: %s -> %s  %s%s"):format(i, l.kind, from, to, R.Minutes(l.time), "  [" .. src .. "]" .. extra))
	end
end

SLASH_FASTESTWAY1, SLASH_FASTESTWAY2 = "/fw", "/fastestway"
SlashCmdList.FASTESTWAY = function(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$")
	if msg == "" then FW.Toggle() return end
	if msg:lower() == "clear" then current = nil; ClearPin(); FW.Show(nil); Say("route cleared.") return end
	if msg:lower() == "debug" then
		db.debug = not db.debug
		Say("route reports " .. (db.debug and "on: each finished route is described in chat." or "off."))
		if db.debug and FW.route then FW.DebugRoute(FW.route) end
		return
	end
	if msg:lower() == "quests" then
		if FW.QuestReport then FW.QuestReport() else Say("the Quests part isn't loaded: close WoW completely and start it again.") end
		return
	end
	if msg:lower() == "flights" then -- what it knows about your flight paths, per continent
		for _, c in ipairs({ D.KALIMDOR, D.EK }) do
			local have, all = 0, 0
			for _, p in ipairs(R.FlightPoints(c)) do all = all + 1; if R.Known(p.label, c) then have = have + 1 end end
			if R.Scanned(c) then Say(("%s: you have %d of the %d flight paths it can see."):format(R.MapName(c) or "?", have, all))
			else Say((R.MapName(c) or "?") .. ": not known yet. Open a flight master's map there once.") end
		end
		return
	end
	local p = R.Search(msg, 1)[1]
	if not p then Say("no place called \"" .. msg .. "\". Try a town or zone name.") return end
	win:Show()
	edit:SetText(p.name)
	FW.Show(p.point, p.name)
end
