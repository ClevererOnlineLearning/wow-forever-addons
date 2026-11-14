-- Target Finder: map pins. Shows where the mob you're looking for lives, on the world map and
-- the minimap, in its own colour. Spawn points come from Questie's database (LibQuestieDB) and
-- are drawn with HereBeDragons (bundled in Libs). Static reference data only: these are the
-- places the mob spawns, not where it is right now. No unit is ever read.
-- Nothing runs until the tracked name changes, the zone changes, or you open a map.
local TF = TargetFinder

local MAX_WORLD = 600   -- pins on the world map (only the shown map's pins are drawn)
local MAX_MINI = 150    -- pins on the minimap (only your current zone's)
local COLORS = { { 1, 0.15, 0.85 }, { 0.2, 0.65, 1 } } -- first target pink, second blue: not used by Questie's own icons
TF.PIN_COLORS = COLORS
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local REF = "TargetFinderPins"

local IsSecret = issecretvalue or function() return false end
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

local function Pins()
	return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

------------------------------------------------------------------------
-- Pin frames (pooled; one pool per map, since a frame can only be on one)
------------------------------------------------------------------------
local pools = { world = {}, mini = {} }

local function PinEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Target Finder", 0.2, 0.8, 1)
	GameTooltip:AddLine((self.mobName or "?") .. " can spawn here.", 1, 1, 1)
	GameTooltip:AddLine(self.second and "This is your second target." or "This is the mob you're looking for.", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function NewPin(size)
	local p = CreateFrame("Frame", nil, UIParent)
	p:SetSize(size, size)
	local edge = p:CreateTexture(nil, "BACKGROUND")
	edge:SetTexture(CIRCLE)
	edge:SetAllPoints()
	edge:SetVertexColor(0, 0, 0, 1)
	local dot = p:CreateTexture(nil, "ARTWORK")
	dot:SetTexture(CIRCLE)
	dot:SetPoint("TOPLEFT", 2, -2)
	dot:SetPoint("BOTTOMRIGHT", -2, 2)
	p.dot = dot
	p:EnableMouse(true)
	p:SetScript("OnEnter", PinEnter)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p:Hide()
	return p
end

local function GetPin(kind, i, name, which)
	local pool = pools[kind]
	pool[i] = pool[i] or NewPin(kind == "world" and 12 or 10)
	local p, c = pool[i], COLORS[which] or COLORS[1]
	p.mobName, p.second = name, which == 2
	p.dot:SetVertexColor(c[1], c[2], c[3], 1)
	return p
end

local function ClearPins()
	local P = Pins()
	if P then
		P:RemoveAllWorldMapIcons(REF)
		P:RemoveAllMinimapIcons(REF)
	end
	for _, pool in pairs(pools) do for _, p in ipairs(pool) do p:Hide() end end
end

------------------------------------------------------------------------
-- Questie data: name -> NPC ids (built once), area -> map
------------------------------------------------------------------------
local nameIndex -- lower-case name -> { id, ... }

local function NPCDB()
	local DB = _G.LibQuestieDB
	local NPC = DB and DB.Npc
	if NPC and NPC.GetAllIds and NPC.Get then return NPC end
end

local function BuildIndex(NPC)
	local idx, any = {}, false
	local faction = UnitFactionGroup and Plain(UnitFactionGroup("player"))
	local mine = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
	for _, id in ipairs(NPC.GetAllIds() or {}) do
		local name = NPC.Get(id, "name")
		if type(name) == "string" and name ~= "" then
			any = true
			local friendly = NPC.Get(id, "friendlyToFaction")
			local isFriend = (mine and type(friendly) == "string" and friendly:find(mine, 1, true)) and true or false
			local k = name:lower()
			local t = idx[k]
			if not t then t = {}; idx[k] = t end
			t[#t + 1] = { id = id, friendly = isFriend }
		end
	end
	return any and idx or nil -- database not ready yet: try again next time
end

local mapByName -- zone name -> uiMapID, from the client's own map list (fallback only)
local function MapFromName(area)
	local name = C_Map and C_Map.GetAreaInfo and Plain(C_Map.GetAreaInfo(area))
	if not name then return nil end
	if not mapByName then
		mapByName = {}
		local kids = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(947, nil, true) or {}
		for _, m in ipairs(kids) do
			local n = Plain(m.name)
			if n and not mapByName[n] then mapByName[n] = m.mapID end
		end
	end
	return mapByName[name]
end

local mapCache = {}
local function AreaToMap(area)
	local m = mapCache[area]
	if m == nil then
		m = false
		local ok, ZoneDB = pcall(function() return QuestieLoader and QuestieLoader:ImportModule("ZoneDB") end)
		if ok and ZoneDB and ZoneDB.GetUiMapIdByAreaId then
			local ok2, id = pcall(ZoneDB.GetUiMapIdByAreaId, ZoneDB, area)
			if ok2 and type(id) == "number" and id > 0 then m = id end
		end
		if not m then m = MapFromName(area) or false end
		mapCache[area] = m
	end
	return m or nil
end

-- Every spawn point of the named mob: { { map = uiMapID, x = 0-1, y = 0-1 }, ... }
function TF.GetSpawns(name)
	local NPC = NPCDB()
	if not NPC then return nil, "Questie isn't enabled" end
	if not nameIndex then
		local ok, idx = pcall(BuildIndex, NPC)
		if not ok then return nil, "Questie's database couldn't be read" end
		nameIndex = idx
		if not nameIndex then return nil, "Questie's database isn't ready yet" end
	end
	local out = {}
	local want = TF.Clean(name):lower()
	local ids = nameIndex[want] or {}
	if TargetFinderDB and not TF.IsExact(name) then -- typed with "Match part of the name": every name containing it
		ids = {}
		for k, list in pairs(nameIndex) do
			if k:find(want, 1, true) then for _, n in ipairs(list) do ids[#ids + 1] = n end end
		end
	end
	for _, n in ipairs(ids) do
		local ok, spawns = pcall(NPC.Get, n.id, "spawns")
		if ok and type(spawns) == "table" then
			for area, list in pairs(spawns) do
				local map = type(list) == "table" and AreaToMap(area)
				if map then
					for _, c in ipairs(list) do
						local x, y = tonumber(c[1]), tonumber(c[2])
						if x and y and x >= 0 and y >= 0 then out[#out + 1] = { map = map, x = x / 100, y = y / 100 } end
					end
				end
			end
		end
	end
	return out
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
local drawnKey -- what is on the maps now, so repeated calls cost nothing
TF.pinCount = 0

local function PlayerMap()
	return C_Map and C_Map.GetBestMapForUnit and Plain(C_Map.GetBestMapForUnit("player"))
end

function TF.UpdatePins(force)
	local db = TargetFinderDB
	if not db then return end
	local names = TF.Names()
	local world, mini = db.mapPins and true or false, db.miniPins and true or false
	local on = (world or mini) and #names > 0
	local here = PlayerMap()
	local key = on and table.concat({ table.concat(names, "+"):lower(), tostring(here), tostring(world), tostring(mini), tostring(db.exact), tostring(db.mobPicked), tostring(db.mob2Picked) }, "|") or "off"
	if key == drawnKey and not force then return end
	ClearPins()
	drawnKey, TF.pinCount, TF.pinNote = key, 0, nil
	if not on then return end
	local P = Pins()
	if not P then TF.pinNote = "map library missing"; drawnKey = nil; return end -- retry next time
	local spawns = {}
	for i, name in ipairs(names) do
		local list, err = TF.GetSpawns(name)
		if not list then TF.pinNote = err; drawnKey = nil; return end -- retry next time
		for _, s in ipairs(list) do s.name, s.which = name, i; spawns[#spawns + 1] = s end
	end
	local w, m = 0, 0
	for _, s in ipairs(spawns) do
		if world and w < MAX_WORLD then
			w = w + 1
			pcall(P.AddWorldMapIconMap, P, REF, GetPin("world", w, s.name, s.which), s.map, s.x, s.y, HBD_PINS_WORLDMAP_SHOW_PARENT)
		end
	end
	-- Minimap: your zone's spawns first, then others nearby (the minimap only shows pins in range).
	for pass = 1, 2 do
		for _, s in ipairs(spawns) do
			if mini and m < MAX_MINI and ((pass == 1) == (s.map == here)) then
				m = m + 1
				pcall(P.AddMinimapIconMap, P, REF, GetPin("mini", m, s.name, s.which), s.map, s.x, s.y, false, false)
			end
		end
	end
	TF.pinCount = #spawns
end

-- Name changes all go through TF.Apply (typing, Quick Target, Nearby, Saved, login).
local baseApply = TF.Apply
function TF.Apply(...)
	local a, b = baseApply(...)
	TF.UpdatePins()
	return a, b
end

-- Minimap pins are per zone: redraw when you change zone.
local ev = CreateFrame("Frame")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
		C_Timer.After(3, function() TF.UpdatePins() end) -- give Questie's database time to load
	else
		TF.UpdatePins()
	end
end)
