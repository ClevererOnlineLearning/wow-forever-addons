-- Target Finder: core. Macro-free: a secure action button (type "macro" + "macrotext") is
-- bound to a key through Bindings.xml. No Blizzard macro slot is created or used.
-- No libraries, no OnUpdate, no polling. Quest/spell lists are built only when a menu opens.
local TF = {}
_G.TargetFinder = TF

TF.BUTTON_NAME = "TargetFinderSecureButton"
TF.BINDING = "CLICK TargetFinderSecureButton:LeftButton"
local MAX_BODY = 255
local MAX_FAVORITES = 10
local MAX_RECENT = 8
local CLASS_DEFAULT_SPELL = { DRUID = "Moonfire", HUNTER = "Hunter's Mark" }

local IsSecret = issecretvalue or function() return false end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTarget Finder:|r " .. msg)
end
TF.Print = Print

-- Strip anything that would break a macro line or its [conditions]; collapse whitespace.
local function Clean(s)
	s = tostring(s or ""):gsub("[\r\n;%[%]]", " "):gsub("%s+", " ")
	return (s:match("^%s*(.-)%s*$"))
end
TF.Clean = Clean

------------------------------------------------------------------------
-- Action text
------------------------------------------------------------------------
-- Words /target treats as unit tokens rather than names ("/target focus" targets your focus).
local function IsUnitToken(s)
	if s:find("%s") then return false end -- tokens never contain spaces ("Archery Target" is fine)
	s = s:lower():gsub("%d+$", "")
	return s == "player" or s == "target" or s == "focus" or s == "mouseover" or s == "pet"
		or s == "party" or s == "raid" or s == "arena" or s == "boss" or s == "npc" or s == "none"
		or s == "vehicle" or s == "partypet" or s == "raidpet" or s:find("^soft") ~= nil
		or s:find("target$") ~= nil or s:find("^nameplate") ~= nil
end

-- The target is always cleared before searching, so a failed search can never leave
-- anyone (an unrelated mob, a friend, or you) selected for the spell.
function TF.BuildBody()
	local db = TargetFinderDB
	local mob, spell = Clean(db.mob), Clean(db.spell)
	if mob == "" then return nil, "Enter a mob name first." end
	if IsUnitToken(mob) then return nil, ("'%s' is a unit keyword, not a mob name."):format(mob) end
	local useSpell = spell ~= "" -- empty spell box = just target it

	-- Enemies and friendly NPCs alike: the spell works on any living unit the search found.
	local cond = "[@target,nodead]"
	local L = {}
	-- Name targeting always picks the closest match, so Tag mode moves on with Tab instead: while
	-- you're on a living enemy, the press jumps to the next enemy (any name); with no target it
	-- searches by name as usual.
	local find = (db.exact and "/targetexact " or "/target ") -- /target also matches longer names ("Zanzil")
	if db.tagMode then
		L[#L + 1] = "/cleartarget [noharm][dead]"
		L[#L + 1] = "/targetenemy [harm,nodead]"
		L[#L + 1] = find .. "[noexists] " .. mob
	else
		L[#L + 1] = "/cleartarget"
		L[#L + 1] = find .. mob
	end
	if useSpell then
		-- Explicit @target: never falls back to a soft/auto target when nothing was found.
		L[#L + 1] = "/cast " .. cond .. " " .. spell
	end
	-- Markers: one for enemies, one for friendly NPCs, only on a living unit it found.
	local M = {}
	if db.mark then M[#M + 1] = "[@target,harm,nodead] " .. db.marker end
	if db.markFriend then M[#M + 1] = "[@target,noharm,nodead] " .. db.friendMarker end
	if #M > 0 then L[#L + 1] = "/tm " .. table.concat(M, "; ") end
	L[#L + 1] = "/cleartarget [dead]"

	local body = table.concat(L, "\n")
	if #body > MAX_BODY then
		return nil, ("Action would be %d characters; the limit is %d. Shorten the names."):format(#body, MAX_BODY)
	end
	return body
end

------------------------------------------------------------------------
-- Secure button (the only thing that ever targets or casts; runs only on your key press)
------------------------------------------------------------------------
local button = CreateFrame("Button", TF.BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
button:SetSize(1, 1)
button:RegisterForClicks("AnyUp", "AnyDown") -- the template honours the ActionButtonUseKeyDown CVar
button:SetAttribute("type", "macro")

-- Optional "found it" sound. Macros can't play sounds, so the addon looks at your target just
-- before and just after the key's secure action (Pre/PostClick, only on your press). It plays
-- only when this press newly found a living hostile. If the game hides whether you have a
-- target, the sound can't work: it says so once and stays silent.
local function HostileTarget()
	local ok, res = pcall(function()
		local exists = UnitExists("target")
		if IsSecret(exists) then return nil end
		if not exists then return false end
		local atk, dead = UnitCanAttack("player", "target"), UnitIsDead("target")
		if IsSecret(atk) or IsSecret(dead) then return nil end
		if dead then return false end
		if atk then return true end
		local me = UnitIsUnit("target", "player") -- friendly NPCs count too: anything alive except you
		if IsSecret(me) then return nil end
		return not me
	end)
	if ok then return res end
end
TF.HostileTarget = HostileTarget

-- Bindings fire the button on key down and key up; the template acts on only one of them.
local function ActingPhase(down)
	if down == nil or not GetCVarBool then return true end
	return (down and true or false) == (GetCVarBool("ActionButtonUseKeyDown") and true or false)
end

-- Sounds you can pick. Each uses the client's SOUNDKIT name when it has one, else a known ID.
TF.SOUNDS = {
	{ name = "Raid warning",   key = "RAID_WARNING",          id = 8959 },
	{ name = "Ready check",    key = "READY_CHECK",           id = 8960 },
	{ name = "Alarm clock",    key = "ALARM_CLOCK_WARNING_3", id = 12889 },
	{ name = "Whisper",        key = "TELL_MESSAGE",          id = 3081 },
	{ name = "Map ping",       key = "MAP_PING",              id = 3175 },
	{ name = "Queue pop",      key = "PVP_THROUGH_QUEUE",     id = 8458 },
	{ name = "Friend online",  key = "UI_BNET_TOAST",         id = 18019 },
	{ name = "Quest complete", key = "IG_QUEST_LIST_COMPLETE", id = 878 },
}
function TF.PlayFoundSound()
	local s = TF.SOUNDS[TargetFinderDB and TargetFinderDB.soundChoice or 1] or TF.SOUNDS[1]
	PlaySound(SOUNDKIT and SOUNDKIT[s.key] or s.id, "Master")
end

-- Tagged by someone else (grey to you)? Macros have no [tagged] condition, so the key still
-- targets it; the addon can only tell you afterwards and skip the "found it" sound.
local function TaggedByOther()
	local ok, res = pcall(function()
		if not UnitIsTapDenied then return false end
		local t = UnitIsTapDenied("target")
		if IsSecret(t) then return false end
		return t and true or false
	end)
	return ok and res or false
end
TF.TaggedByOther = TaggedByOther

local hadHostile, soundWarned, lastTagWarn = nil, false, -100
button:SetScript("PreClick", function(_, _, down)
	hadHostile = nil
	if TargetFinderDB and TargetFinderDB.sound and ActingPhase(down) then hadHostile = HostileTarget() end
end)
button:SetScript("PostClick", function(_, _, down)
	if not (TargetFinderDB and ActingPhase(down)) then return end
	local now = HostileTarget()
	if now and TaggedByOther() then
		local t = GetTime and GetTime() or 0
		if t - lastTagWarn >= 5 then -- at most once every 5 seconds, so key spam doesn't flood chat
			lastTagWarn = t
			TF.Print(("Found %s, but someone else has tagged it (it's grey). Press again to look for another one.")
				:format(Clean(TargetFinderDB.mob) ~= "" and Clean(TargetFinderDB.mob) or "it"))
		end
		return -- no "found it" sound for a mob you can't claim
	end
	if not TargetFinderDB.sound then return end
	if now == nil or hadHostile == nil then
		if not soundWarned then
			soundWarned = true
			TF.Print("The \"found it\" sound isn't available here: the game hides whether you have a target.")
		end
		return
	end
	if now and not hadHostile then TF.PlayFoundSound() end
end)

local pending = false
local events = CreateFrame("Frame")
TF.state = "Not applied yet."

-- Copies the current settings onto the secure button. Attributes can't change in combat,
-- so in combat it is queued for PLAYER_REGEN_ENABLED and the previous action stays active.
function TF.Apply()
	if InCombatLockdown() then
		pending = true
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		TF.state = "In combat: the change applies when combat ends. The key still does the previous search."
		return false, TF.state
	end
	pending = false
	local body, err = TF.BuildBody()
	button:SetAttribute("macrotext", body) -- nil body => the key does nothing
	TF.appliedBody = body
	TF.state = body and "Ready." or ("Key disabled: " .. err)
	return body ~= nil, TF.state
end

------------------------------------------------------------------------
-- Active name, recent list
------------------------------------------------------------------------
-- Plain value or nil: never lets a secret value escape (comparing a secret can raise an error).
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

function TF.AddRecent(name)
	local list = TargetFinderDB.recent
	for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
	table.insert(list, 1, name)
	while #list > MAX_RECENT do table.remove(list) end
end

-- The one way a picked or typed name becomes the active search (Quick Target, Nearby, Quests,
-- Saved). Spell and matching settings are untouched. Invalid names change nothing.
-- Returns ok, message; the message says whether the Find key already uses it or it is queued.
function TF.Track(name)
	name = Clean(name)
	local db = TargetFinderDB
	local old = db.mob
	db.mob = name
	local body, err = TF.BuildBody()
	if not body then db.mob = old; return false, err end
	local active = TF.Apply()
	TF.AddRecent(name)
	if TF.Refresh then TF.Refresh() end
	if active then return true, "Now tracking |cffffffff" .. name .. "|r" end
	return true, "Queued, applies when combat ends: |cffffffff" .. name .. "|r (the key still searches for the previous name)"
end

-- Stops looking for anything: the Find key does nothing and the map dots go away.
function TF.ClearMob()
	local db = TargetFinderDB
	if Clean(db.mob) == "" then return true, "Not looking for anything." end
	db.mob = ""
	local inFight = InCombatLockdown()
	TF.Apply()
	if TF.UpdatePins then TF.UpdatePins() end
	if TF.Refresh then TF.Refresh() end
	if not inFight then return true, "Cleared: not looking for a mob now." end
	return true, "Cleared. You're in a fight, so the key keeps the old search until the fight ends."
end

------------------------------------------------------------------------
-- Favourites
------------------------------------------------------------------------
function TF.AddFavorite(name)
	name = Clean(name)
	if name == "" then return false, "Nothing to save." end
	local list = TargetFinderDB.favorites
	for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
	table.insert(list, 1, name)
	while #list > MAX_FAVORITES do table.remove(list) end
	return true, ("Saved '%s' to favourites."):format(name)
end

function TF.RemoveFavorite(name)
	local list = TargetFinderDB.favorites
	for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) return true end end
	return false
end

------------------------------------------------------------------------
-- Nearby suggestions from Questie's public database (LibQuestieDB, optional). Built only when
-- the Nearby menu opens and cached per zone for the session. Static reference data: it lists
-- what lives in your zone, not what is spawned right now. No unit is ever read.
------------------------------------------------------------------------
local RARE_RANK = { [2] = true, [4] = true } -- creature rank: 2 = rare elite, 4 = rare
local zoneCache = {}                       -- zone name -> list, for this session only
local areaNames = {}

local function AreaName(id)
	local n = areaNames[id]
	if n == nil then
		n = C_Map and C_Map.GetAreaInfo and Plain(C_Map.GetAreaInfo(id)) or false
		areaNames[id] = n
	end
	return n or nil
end

local function PlayerZone()
	local mapID = C_Map and C_Map.GetBestMapForUnit and Plain(C_Map.GetBestMapForUnit("player"))
	local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	local name = info and Plain(info.name)
	if not name then return nil end
	local x, y
	if C_Map.GetPlayerMapPosition then
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		if pos and pos.GetXY then x, y = pos:GetXY() end
		x, y = Plain(x), Plain(y)
	end
	return name, x and x * 100, y and y * 100
end

-- Returns { rares = {...}, mobs = {...} } (each entry { name, label }) or nil, reason.
function TF.GetZoneNPCs()
	local DB = _G.LibQuestieDB
	local NPC = DB and DB.Npc
	if not (NPC and NPC.GetAllIds and NPC.Get) then return nil, "Enable Questie for zone suggestions." end
	local zone, px, py = PlayerZone()
	if not zone then return nil, "Can't tell which zone you're in." end
	local list = zoneCache[zone]
	if not list then
		local ok, res = pcall(function()
			local faction = UnitFactionGroup and UnitFactionGroup("player")
			local mine = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
			local byName, items = {}, {}
			for _, id in ipairs(NPC.GetAllIds() or {}) do
				local area = NPC.Get(id, "zoneID")
				if area and AreaName(area) == zone then
					local name = NPC.Get(id, "name")
					local friendly = NPC.Get(id, "friendlyToFaction")
					if type(name) == "string" and name ~= "" then
						local isFriend = (mine and type(friendly) == "string" and friendly:find(mine, 1, true)) and true or false
						local spawns = NPC.Get(id, "spawns")
						local e = byName[name]
						if not e then
							e = { name = name, rare = RARE_RANK[NPC.Get(id, "rank") or 0] or false,
								minL = NPC.Get(id, "minLevel"), maxL = NPC.Get(id, "maxLevel"), coords = {}, friendly = isFriend }
							byName[name] = e
							items[#items + 1] = e
						end
						if not isFriend then e.friendly = false end -- friendly only if every NPC of that name is
						for _, c in ipairs(type(spawns) == "table" and spawns[area] or {}) do
							if c[1] and c[1] >= 0 then e.coords[#e.coords + 1] = c end
						end
					end
				end
			end
			return items
		end)
		if not ok then return nil, "Questie's database couldn't be read." end
		list = res
		zoneCache[zone] = list
	end
	-- Distance is approximate (map percent); without a position the list is alphabetical.
	for _, e in ipairs(list) do
		local best
		if px then
			for _, c in ipairs(e.coords) do
				local d = (c[1] - px) ^ 2 + (c[2] - py) ^ 2
				if not best or d < best then best = d end
			end
		end
		e.dist = best or math.huge
	end
	local sorted = {}
	for i, e in ipairs(list) do sorted[i] = e end
	table.sort(sorted, function(a, b) if a.dist ~= b.dist then return a.dist < b.dist end return a.name < b.name end)
	local out = { zone = zone, rares = {}, mobs = {}, all = {} }
	for _, e in ipairs(sorted) do -- friendly NPCs are listed too (shown in green)
	do
		local lvl = e.minL and (e.maxL and e.maxL ~= e.minL and (e.minL .. "-" .. e.maxL) or tostring(e.minL))
		local entry = { name = Clean(e.name), label = (e.friendly and "|cff40ff40" or "") .. Clean(e.name) .. (e.friendly and "|r" or "")
			.. (lvl and (" |cff888888(" .. lvl .. ")|r") or "") }
		if e.rare then out.rares[#out.rares + 1] = entry
		else
			if #out.mobs < 25 then out.mobs[#out.mobs + 1] = entry end
			out.all[#out.all + 1] = entry
		end
	end
	end
	table.sort(out.all, function(a, b) return a.name < b.name end)
	return out
end

------------------------------------------------------------------------
-- Type-ahead search: names matching what you type, from your favourites, recent names and
-- (if Questie is enabled) this zone's mobs. Matches at the start of a word come first.
-- Uses the same per-zone cache as Nearby; nothing runs unless you are typing.
------------------------------------------------------------------------
function TF.Suggest(text, max)
	local q = Clean(text):lower()
	if #q < 2 then return {} end
	local seen, first, rest = {}, {}, {}
	local function add(name, label)
		local n = Clean(name)
		local l = n:lower()
		if seen[l] or l == q then return end
		local pos = l:find(q, 1, true)
		if not pos then return end
		seen[l] = true
		local wordStart = pos == 1 or l:sub(pos - 1, pos - 1) == " "
		local list = wordStart and first or rest
		list[#list + 1] = { name = n, label = label or n }
	end
	local db = TargetFinderDB
	for _, n in ipairs(db.favorites) do add(n, n .. " |cffffd100(fav)|r") end
	for _, n in ipairs(db.recent) do add(n, n .. " |cff888888(recent)|r") end
	local zone = TF.GetZoneNPCs()
	if zone then
		for _, e in ipairs(zone.rares) do add(e.name, e.label .. " |cffff8000(rare)|r") end
		for _, e in ipairs(zone.all) do add(e.name, e.label) end
	end
	local out = {}
	for _, list in ipairs({ first, rest }) do
		for _, e in ipairs(list) do
			if #out >= (max or 8) then return out end
			out[#out + 1] = e
		end
	end
	return out
end

------------------------------------------------------------------------
-- Quest objectives -> mob names (read only, on demand)
------------------------------------------------------------------------
local function MobFromText(t)
	t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	t = t:gsub("^%s*%d+%s*/%s*%d+%s*", "")       -- "3/10 Name slain"
	t = t:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")   -- "Name slain: 3/10"
	t = t:gsub("%s+[Ss]lain$", ""):gsub("%s+[Kk]illed$", "")
	t = Clean(t)
	if #t < 2 or #t > 60 then return nil end
	return t
end

local function CollectQuestMobs()
	local out = {}
	local QL = C_QuestLog
	if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives) then return out end
	for i = 1, QL.GetNumQuestLogEntries() or 0 do
		local info = QL.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.questID then
			local okObj, objectives = pcall(QL.GetQuestObjectives, info.questID)
			if not okObj then objectives = nil end
			local mobs, seen = {}, {}
			if type(objectives) == "table" then
				for _, o in ipairs(objectives) do
					local text = o.text
					if o.type == "monster" and type(text) == "string" and not IsSecret(text) then
						local name = MobFromText(text)
						if name and not seen[name] then
							seen[name] = true
							mobs[#mobs + 1] = { name = name, done = o.finished }
						end
					end
				end
			end
			if #mobs > 0 then
				out[#out + 1] = { title = info.title or ("Quest " .. info.questID), mobs = mobs }
			end
		end
	end
	return out
end

function TF.GetQuestMobs()
	local ok, res = pcall(CollectQuestMobs)
	return ok and res or {}
end

------------------------------------------------------------------------
-- Spellbook (active, non-passive spells grouped by tab; on demand)
------------------------------------------------------------------------
-- Rank text ("Rank 3") from the spellbook entry; other subtexts ("Racial", "Shapeshift") are ignored.
local function RankOf(it)
	local sub = it.subName
	if (type(sub) ~= "string" or sub == "") and it.spellID and C_Spell and C_Spell.GetSpellSubtext then
		sub = C_Spell.GetSpellSubtext(it.spellID)
	end
	if type(sub) == "string" and not IsSecret(sub) then
		local n = sub:match("^%s*[Rr]ank%s+(%d+)%s*$")
		if n then return tonumber(n), sub end
	end
end

-- Each tab: { name = tab, spells = { { name = "Moonfire", ranks = { "Rank 1", "Rank 2", ... } }, ... } }.
-- Lower ranks only appear if the spellbook shows them ("Show All Spell Ranks").
local function CollectSpells()
	local lines = {}
	local SB = C_SpellBook
	if not (SB and SB.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank) then return lines end
	local bank = Enum.SpellBookSpellBank.Player
	for l = 1, SB.GetNumSpellBookSkillLines() or 0 do
		local li = SB.GetSpellBookSkillLineInfo(l)
		if li and not li.offSpecID and not li.shouldHide then
			local spells, byName = {}, {}
			for o = 1, li.numSpellBookItems or 0 do
				local it = SB.GetSpellBookItemInfo(li.itemIndexOffset + o, bank)
				if it and it.itemType == Enum.SpellBookItemType.Spell and not it.isPassive then
					local name = it.name or (it.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(it.spellID))
					if type(name) == "string" and not IsSecret(name) then
						local entry = byName[name]
						if not entry then
							entry = { name = name, ranks = {}, seen = {} }
							byName[name] = entry
							spells[#spells + 1] = entry
						end
						local n, text = RankOf(it)
						if n and not entry.seen[n] then
							entry.seen[n] = true
							entry.ranks[#entry.ranks + 1] = { n = n, text = text }
						end
					end
				end
			end
			table.sort(spells, function(x, y) return x.name < y.name end)
			for _, e in ipairs(spells) do
				table.sort(e.ranks, function(x, y) return x.n < y.n end)
				for i, r in ipairs(e.ranks) do e.ranks[i] = r.text end
				e.seen = nil
			end
			if #spells > 0 then lines[#lines + 1] = { name = li.name or ("Tab " .. l), spells = spells } end
		end
	end
	return lines
end

function TF.GetSpells()
	local ok, res = pcall(CollectSpells)
	return ok and res or {}
end

------------------------------------------------------------------------
-- Key binding labels (Esc > Options > Keybindings > AddOns > Target Finder)
------------------------------------------------------------------------
-- Raid marker icons, in the game's own order (1 = star ... 8 = skull).
TF.MARKERS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
function TF.MarkerIcon(i, size)
	return ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:%d|t"):format(i, size or 14)
end

-- Binds a key only because the user clicked "Set key" and pressed it (the UI asks before
-- replacing a key that already does something). Uses WoW's normal, saved key bindings.
function TF.BindKey(action, key)
	if InCombatLockdown() then return false, "Keys can't be changed during a fight. Try again after it." end
	local old = { GetBindingKey(action) }
	if not SetBinding(key, action) then return false, "WoW didn't accept that key. Try a different one." end
	for _, k in ipairs(old) do if k ~= key then SetBinding(k) end end -- one key per action
	SaveBindings(GetCurrentBindingSet())
	return true, "Key set: " .. key
end

_G["BINDING_NAME_" .. TF.BINDING] = "Find target (search, then optional spell)"
BINDING_NAME_TARGETFINDER_OPEN_SEARCH = "Open search box (type a mob name)"

------------------------------------------------------------------------
-- Init / events
------------------------------------------------------------------------
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		local db = type(TargetFinderDB) == "table" and TargetFinderDB or {}
		TargetFinderDB = db
		if type(db.mob) ~= "string" then db.mob = "" end
		local wasFriendly = db.friendly -- before 3.1 friendly NPCs and "target myself first" were options
		db.friendly, db.before = nil, nil
		if type(db.spell) ~= "string" then db.spell = CLASS_DEFAULT_SPELL[select(2, UnitClass("player"))] or "" end
		if db.targetOnly then db.spell = "" end -- before 3.3 "Just target it" was a tick box: now an empty spell box
		db.targetOnly = nil -- removed in 3.3
		if db.exact == nil then db.exact = true end -- exact name by default; "Match part of the name" turns it off
		db.exact = db.exact and true or false
		db.tagMode = db.tagMode and true or false -- off by default
		if db.mark == nil then db.mark = db.skull and true or false end -- 2.2-2.4 "skull" setting carries over
		db.mark = db.mark and true or false
		db.skull = nil
		db.marker = tonumber(db.marker)
		if not (db.marker and db.marker >= 1 and db.marker <= 8 and db.marker % 1 == 0) then db.marker = 8 end
		-- Before 3.1 one marker did both in friendly mode: keep marking friendlies if it did.
		if db.markFriend == nil then db.markFriend = (wasFriendly and db.mark) and true or false end
		db.markFriend = db.markFriend and true or false
		db.friendMarker = tonumber(db.friendMarker)
		if not (db.friendMarker and db.friendMarker >= 1 and db.friendMarker <= 8 and db.friendMarker % 1 == 0) then db.friendMarker = 1 end -- star
		db.sound = db.sound and true or false
		db.soundChoice = tonumber(db.soundChoice)
		if not (db.soundChoice and TF.SOUNDS[db.soundChoice]) then db.soundChoice = 1 end -- raid warning
		if db.mapPins == nil then db.mapPins = true end -- show spawn points on the maps (needs Questie)
		db.mapPins = db.mapPins and true or false
		if db.miniPins == nil then db.miniPins = db.mapPins end -- before 3.0 one box did both
		db.miniPins = db.miniPins and true or false
		if type(db.favorites) ~= "table" then db.favorites = {} end
		if type(db.recent) ~= "table" then db.recent = {} end
		if type(db.minimap) ~= "table" then db.minimap = { angle = 200, hide = false } end
		TF.Apply()
		if TF.OnLogin then TF.OnLogin() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if pending then
			TF.Apply()
			if TF.Refresh then TF.Refresh() end
		end
	end
end)
