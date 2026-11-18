-- Hunter Reminder for WoW Forever
-- Shows a pulsing icon when Trueshot Aura or Aspect of the Hawk is missing.
-- Matches buffs by spell NAME, so every rank counts.

local ADDON_NAME = ...
local _, class = UnitClass("player")
if class ~= "HUNTER" then return end

-- Rank 1 IDs are only used to look up the localized name / icon; all ranks match.
local TRACKED = {
	{ key = "trueshot", baseID = 19506, ranks = { 19506, 20905, 20906, 27066 },
	  fallbackName = "Trueshot Aura", fallbackIcon = "Interface\\Icons\\Ability_TrueShot" },
	{ key = "hawk", baseID = 13165, ranks = { 13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044 },
	  fallbackName = "Aspect of the Hawk", fallbackIcon = "Interface\\Icons\\Spell_Nature_RavenForm",
	  -- Aspects that also satisfy the reminder (e.g. upgraded versions).
	  alsoOK = { 61846, 61847 } }, -- Aspect of the Dragonhawk
}

local DEFAULTS = {
	locked = true,
	showResting = false, -- remind in cities/inns too (when out of combat)
	hideMounted = true,
	sound = true,        -- play a sound (voice, effect or game sound) when a reminder appears
	trueshotSound = "trueshot_harry",
	hawkSound = "aspect_harry",
	scale = 1.0,
	point = { "CENTER", "UIParent", "CENTER", 0, 160 },
	-- When to remind, per buff: "always", "combat" (in combat only) or "off".
	trueshotMode = "always",
	hawkMode = "combat",
	minimap = { angle = 165, hide = false },
	autoTrack = true,        -- switch tracking to match the mob you target
	autoTrackCombat = false, -- also during fights (switching may cost a global cooldown)
	trackLocked = false,     -- "Lock tracking": keep what's on now; auto tracking pauses, reminders keep going
	feignWarn = true,        -- big warning when a mob resists your Feign Death
	feignSound = true,
}

HunterReminder = {}
local HR = HunterReminder
HR.TRACKED = TRACKED

-- Sounds to pick from for each reminder. Text ids are files in the add-on's sounds folder (voices made
-- with ElevenLabs, effects, and custom1-3.ogg you can add yourself); numbers are the game's own sounds.
HR.SOUNDS = {
	{ id = 0, name = "No sound" },
	{ id = "trueshot_harry", name = "Voice: \"Trueshot Aura!\" (Harry)" },
	{ id = "trueshot_sarah", name = "Voice: \"Trueshot Aura!\" (Sarah)" },
	{ id = "trueshot_missing_harry", name = "Voice: \"Trueshot's down.\" (Harry)" },
	{ id = "trueshot_missing_sarah", name = "Voice: \"Trueshot's down.\" (Sarah)" },
	{ id = "aspect_harry", name = "Voice: \"Check your aspect!\" (Harry)" },
	{ id = "aspect_sarah", name = "Voice: \"Check your aspect!\" (Sarah)" },
	{ id = "hawk_harry", name = "Voice: \"Aspect of the Hawk!\" (Harry)" },
	{ id = "hawk_sarah", name = "Voice: \"Aspect of the Hawk!\" (Sarah)" },
	{ id = "sfx_chime", name = "Alert chime" },
	{ id = "sfx_horn", name = "War horn" },
	{ id = "sfx_bowstring", name = "Bowstring" },
	{ id = 8959, name = "Raid warning (game)" },
	{ id = 8960, name = "Ready check (game)" },
	{ id = 3081, name = "Whisper (game)" },
	{ id = "custom1", name = "Custom 1 (sounds\\custom1.ogg)" },
	{ id = "custom2", name = "Custom 2 (sounds\\custom2.ogg)" },
	{ id = "custom3", name = "Custom 3 (sounds\\custom3.ogg)" },
}

function HR.PlaySoundID(id)
	if type(id) == "string" then
		pcall(PlaySoundFile, "Interface\\AddOns\\HunterReminder\\sounds\\" .. id .. ".ogg", "Master")
	elseif type(id) == "number" and id > 0 then
		pcall(PlaySound, id, "Master")
	end
end

-- A reminder's sound, at most once every 8 seconds (so one flickering on and off doesn't nag)
local lastSound = {}
function HR.PlayReminder(key)
	local now = GetTime()
	if lastSound[key] and now - lastSound[key] < 8 then return end
	lastSound[key] = now
	HR.PlaySoundID(HR.db and HR.db[key .. "Sound"])
end

local db
local FEIGN_ID = 5384
local feignName -- localized Feign Death, set at login
local GetSpellNameC = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
local GetSpellTextureC = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
local IsKnown = function(id)
	return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end

local function Chat(msg) print("|cffabd473Hunter Reminder:|r " .. msg) end

------------------------------------------------------------------------
-- Buff scanning
-- WoW Forever uses Midnight "secret aura" rules: in combat, add-ons may not
-- scan buffs. Out of combat we scan normally; in combat we use the per-spell
-- lookup only for spells Blizzard marks NeverSecret, otherwise we keep the last
-- known state and update it from your own casts (Aspect swaps, Trueshot).
------------------------------------------------------------------------
local isSecret = issecretvalue or function() return false end

local function AurasSecret()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		local ok, v = pcall(C_Secrets.ShouldAurasBeSecret)
		return (not ok) or (v and true or false)
	end
	return false
end

local neverSecret = {}
local function IsNeverSecret(id)
	if neverSecret[id] == nil then
		local ok, level = false, nil
		if C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel then
			ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, id)
		end
		neverSecret[id] = ok and level == Enum.SecrecyLevel.NeverSecret or false
	end
	return neverSecret[id]
end

-- Full scan; returns nil if the client refuses (secret/tainted). Hidden buff names are skipped
-- (not the end of the list); the second value says whether any were hidden.
local function PlayerBuffNames()
	local hidden = false
	local ok, names = pcall(function()
		local out = {}
		for i = 1, 40 do
			local name, any
			if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
				local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
				any = aura ~= nil
				name = aura and aura.name
			elseif UnitBuff then
				name = UnitBuff("player", i)
				any = name ~= nil
			end
			if not any then break end
			if name == nil or isSecret(name) then hidden = true else out[name] = true end
		end
		return out
	end)
	return ok and names or nil, hidden
end

-- Per-spell lookup for NeverSecret spells; returns true/false, or nil if not allowed.
local function HasBySpellID(t)
	if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
	local ids = {}
	for _, id in ipairs(t.ranks) do ids[#ids + 1] = id end
	if t.alsoOK then for _, id in ipairs(t.alsoOK) do ids[#ids + 1] = id end end
	for _, id in ipairs(ids) do
		if not IsNeverSecret(id) then return nil end
	end
	local ok, found = pcall(function()
		for _, id in ipairs(ids) do
			if C_UnitAuras.GetPlayerAuraBySpellID(id) then return true end
		end
		return false
	end)
	if ok then return found end
	return nil
end

local known = {} -- last known present/absent per tracked key (used while secret)

-- Names in your spellbook, rebuilt when your spells change.
local book
local function BookNames()
	if book then return book end
	book = {}
	pcall(function()
		if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemName then
			local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
			for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
				local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
				local off, n = line and line.itemIndexOffset or 0, line and line.numSpellBookItems or 0
				for j = off + 1, off + n do
					local name = C_SpellBook.GetSpellBookItemName(j, bank)
					if name and not isSecret(name) then book[name] = true end
				end
			end
		elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
			for i = 1, GetNumSpellTabs() do
				local _, _, off, n = GetSpellTabInfo(i)
				for j = (off or 0) + 1, (off or 0) + (n or 0) do
					local name = GetSpellBookItemName(j, BOOKTYPE_SPELL or "spell")
					if name and not isSecret(name) then book[name] = true end
				end
			end
		end
	end)
	return book
end

local function KnowsAny(t)
	for _, id in ipairs(t.ranks) do if IsKnown(id) then return true end end
	return t.name ~= nil and BookNames()[t.name] == true
end

local function HasBuff(t, buffs)
	if buffs[t.name] then return true end
	if t.alsoOK then
		for _, id in ipairs(t.alsoOK) do
			local n = GetSpellNameC(id)
			if n and buffs[n] then return true end
		end
	end
	return false
end

-- Should buff t be reminded about right now (ignoring whether it is actually missing)?
local function ShouldRemind(t)
	local mode = db[t.key .. "Mode"] or "always"
	if mode == "off" then return false end
	if UnitIsDeadOrGhost("player") or (UnitOnTaxi and UnitOnTaxi("player")) then return false end
	local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
	if mode == "combat" and not inCombat then return false end
	if db.hideMounted and IsMounted and IsMounted() then return false end
	if not inCombat and not db.showResting and IsResting() then return false end
	return true
end

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "HunterReminderAnchor", UIParent)
anchor:SetSize(1, 1)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

local icons = {}
local ICON = 40

local function MakeIcon(t, index)
	local f = CreateFrame("Frame", nil, anchor)
	f:SetSize(ICON, ICON)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	f.glow:SetBlendMode("ADD")
	f.glow:SetVertexColor(1, 0.2, 0.2)
	f.glow:SetPoint("CENTER")
	f.glow:SetSize(ICON * 1.8, ICON * 1.8)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)
	f.label:SetTextColor(1, 0.3, 0.3)
	-- Drag each icon on its own while unlocked.
	f:EnableMouse(false)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		if p then db.pos[t.key] = { p, rp, x, y } end
	end)
	f:Hide()
	f.t = t
	icons[index] = f
	return f
end

-- Where each icon goes: its own saved spot, else side by side around the old shared spot
-- (db.point), which is where both icons used to sit.
local GAP = 12
local function DefaultSpot(index)
	local p = db.point or DEFAULTS.point
	local x = (index - 1.5) * (ICON + GAP)
	return { p[1], p[3], (p[4] or 0) + x, p[5] or 0 }
end

local function Layout()
	db.pos = type(db.pos) == "table" and db.pos or {}
	for i, f in ipairs(icons) do
		local sp = db.pos[f.t.key]
		if type(sp) ~= "table" or not sp[1] then sp = DefaultSpot(i); db.pos[f.t.key] = sp end
		f:ClearAllPoints()
		f:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
	end
end

------------------------------------------------------------------------
-- Update loop (cheap: twice a second)
------------------------------------------------------------------------
local wasMissing = {}
local testUntil = 0
local elapsedTotal, sinceCheck = 0, 0

local function Refresh()
	local buffs, hidden
	if not AurasSecret() then buffs, hidden = PlayerBuffNames() end
	local testing = GetTime() < testUntil
	for _, f in ipairs(icons) do
		local t = f.t
		local present
		if buffs then
			present = HasBuff(t, buffs)
			-- not seen, but some buffs were hidden: it may be one of those, so don't guess
			if not present and hidden then present = HasBySpellID(t) end
		else
			present = HasBySpellID(t)
			if present == nil then present = known[t.key] end
		end
		if present ~= nil then known[t.key] = present end
		-- Unknown (e.g. logged in mid-combat): don't nag until we can check.
		local missing = KnowsAny(t) and present == false
		local remind = ShouldRemind(t)
		local show = testing or (missing and remind) or not db.locked
		if missing and remind and not wasMissing[t.key] and db.sound and not testing then
			HR.PlayReminder(t.key)
		end
		wasMissing[t.key] = missing and remind
		if show ~= f:IsShown() then f:SetShown(show) end
	end
end

anchor:SetScript("OnUpdate", function(self, elapsed)
	elapsedTotal = elapsedTotal + elapsed
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= 0.5 then
		sinceCheck = 0
		Refresh()
	end
	-- Pulse the visible icons.
	local a = 0.55 + 0.45 * math.abs(math.sin(elapsedTotal * 3))
	for _, f in ipairs(icons) do
		if f:IsShown() then f.glow:SetAlpha(a) end
	end
end)

local function ApplyLook()
	anchor:SetScale(tonumber(db.scale) or 1)
	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	for _, f in ipairs(icons) do
		f:EnableMouse(not db.locked)
		f.label:SetText(db.locked and ("No " .. f.t.name) or ("Drag me\n" .. f.t.name))
	end
	Layout()
	Refresh()
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		HunterReminderDB = HunterReminderDB or {}
		db = HunterReminderDB
		-- Migrate v1.0 settings (on/off switches) to per-buff modes.
		if db.trueshotMode == nil and db.trueshot == false then db.trueshotMode = "off" end
		if db.hawkMode == nil and db.hawk == false then db.hawkMode = "off" end
		db.trueshot, db.hawk, db.combatOnly = nil, nil, nil
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then
				if type(v) == "table" then
					local c = {} for i, x in pairs(v) do c[i] = x end
					db[k] = c
				else
					db[k] = v
				end
			end
		end
		-- the minimap button's spot (and whether it shows) is the same on every character
		if type(HunterReminderMinimapDB) ~= "table" then HunterReminderMinimapDB = db.minimap end
		db.minimap = HunterReminderMinimapDB
		HR.db = db
	elseif event == "PLAYER_LOGIN" then
		for i, t in ipairs(TRACKED) do
			t.name = GetSpellNameC(t.baseID) or t.fallbackName
			t.icon = (GetSpellTextureC and GetSpellTextureC(t.baseID)) or t.fallbackIcon
			MakeIcon(t, i).tex:SetTexture(t.icon)
		end
		feignName = GetSpellNameC(FEIGN_ID) or "Feign Death"
		ApplyLook()
		if HR.UpdateMinimapButton then HR.UpdateMinimapButton() end
		self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		self:RegisterEvent("PLAYER_DEAD")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("SPELLS_CHANGED")
	elseif event == "SPELLS_CHANGED" then
		book = nil
		Refresh()
	elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
		HR.AutoTrack()
	elseif event == "PLAYER_DEAD" then
		for k in pairs(known) do known[k] = false end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- Track buff changes from your own casts (works while auras are secret).
		local spellID = arg3 -- (unit, castGUID, spellID)
		if spellID == nil or isSecret(spellID) then return end
		if spellID == FEIGN_ID then HR.OnFeignCast() return end
		local ok, name = pcall(GetSpellNameC, spellID)
		if not ok or not name or isSecret(name) then return end
		if name == feignName then HR.OnFeignCast() return end -- other ranks / versions
		for _, t in ipairs(TRACKED) do
			if name == t.name then
				known[t.key] = true
			elseif t.alsoOK then
				for _, id in ipairs(t.alsoOK) do
					if name == GetSpellNameC(id) then known[t.key] = true end
				end
			end
		end
		-- Any other Aspect replaces Aspect of the Hawk.
		local hawk = TRACKED[2]
		local isHawkLike = (name == hawk.name)
		for _, id in ipairs(hawk.alsoOK) do if name == GetSpellNameC(id) then isHawkLike = true end end
		if not isHawkLike and name:find("^Aspect of") then known.hawk = false end
		Refresh()
	end
end)

------------------------------------------------------------------------
-- Auto tracking: when you target a mob, switch to the tracking for its type, so talents like
-- Improved Tracking (more damage to the tracked type) apply. Only the game's own tracking list
-- is used (C_Minimap.SetTracking, like the minimap tracking menu); nothing is cast by name.
------------------------------------------------------------------------
-- Creature type ID (from UnitCreatureType) -> hunter tracking spell.
local TRACK_BY_TYPE = {
	[1] = 1494,  -- Beast      -> Track Beasts
	[2] = 19879, -- Dragonkin  -> Track Dragonkin
	[3] = 19878, -- Demon      -> Track Demons
	[4] = 19880, -- Elemental  -> Track Elementals
	[5] = 19882, -- Giant      -> Track Giants
	[6] = 19884, -- Undead     -> Track Undead
	[7] = 19883, -- Humanoid   -> Track Humanoids
}
-- Used only if the game gives the type name but not its number (English client names).
local TYPE_BY_NAME = { Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5, Undead = 6, Humanoid = 7 }

local NumTracking = (C_Minimap and C_Minimap.GetNumTrackingTypes) or GetNumTrackingTypes
local TrackingInfo = (C_Minimap and C_Minimap.GetTrackingInfo) or GetTrackingInfo
local SetTrackingC = (C_Minimap and C_Minimap.SetTracking) or SetTracking

-- Name, active and spell ID of tracking entry i (old clients return values, new ones a table).
local function Entry(i)
	local ok, a, _, c, _, _, f = pcall(TrackingInfo, i)
	if not ok then return nil end
	if type(a) == "table" then return a.name, a.active, a.spellID end
	return a, c, f
end

-- Index in the tracking list for a tracking spell, and whether it's already on.
function HR.FindTracking(spellID)
	if not (NumTracking and TrackingInfo) then return nil end
	local want = GetSpellNameC(spellID)
	local okN, n = pcall(NumTracking)
	if not okN or type(n) ~= "number" then return nil end
	for i = 1, n do
		local name, active, sid = Entry(i)
		if (sid and not isSecret(sid) and sid == spellID) or (want and name and not isSecret(name) and name == want) then
			return i, active and true or false
		end
	end
end

-- The creature type number of a unit, or nil (unknown, or hidden from add-ons).
function HR.CreatureType(unit)
	local ok, typeName, typeID = pcall(UnitCreatureType, unit)
	if not ok then return nil end
	if typeID ~= nil and not isSecret(typeID) and type(typeID) == "number" then return typeID end
	if typeName ~= nil and not isSecret(typeName) then return TYPE_BY_NAME[typeName] end
	return nil
end

local function Plain(v) if v == nil or isSecret(v) then return nil end return v end

function HR.AutoTrack()
	if not db or not db.autoTrack or db.trackLocked or not SetTrackingC then return end
	if InCombatLockdown() and not db.autoTrackCombat then return end
	if Plain(UnitExists("target")) ~= true or Plain(UnitIsDead("target")) == true then return end
	if Plain(UnitCanAttack("player", "target")) ~= true then return end
	local spell = TRACK_BY_TYPE[HR.CreatureType("target") or 0]
	if not spell or not IsKnown(spell) then return end
	local i, active = HR.FindTracking(spell)
	if not i or active then return end
	if pcall(SetTrackingC, i, true) and not db.seenAutoTrack then
		db.seenAutoTrack = true
		Chat("switched your tracking to " .. (GetSpellNameC(spell) or "match your target") .. " to match your target. Turn this off in /hrem.")
	end
end

-- /hrem check: what the game tells add-ons about your target, and what auto tracking would do.
function HR.CheckTracking()
	if Plain(UnitExists("target")) ~= true then Chat("target a mob first, then type /hrem check."); return end
	local ok, typeName, typeID = pcall(UnitCreatureType, "target")
	local function Show(v) if v == nil then return "nothing" elseif isSecret(v) then return "|cffff6633hidden from add-ons|r" end return "|cffffffff" .. tostring(v) .. "|r" end
	Chat("target type: " .. (ok and (Show(typeName) .. " (" .. Show(typeID) .. ")") or "error"))
	local t = HR.CreatureType("target")
	local spell = TRACK_BY_TYPE[t or 0]
	if not spell then Chat("no hunter tracking for this type.") return end
	local name = GetSpellNameC(spell) or tostring(spell)
	if not IsKnown(spell) then Chat("you haven't learned " .. name .. " yet.") return end
	local i, active = HR.FindTracking(spell)
	if not i then Chat(name .. " isn't in your tracking list.") return end
	Chat(name .. ": " .. (active and "already on." or "would switch to it.") .. (db.autoTrack and (db.trackLocked and " (tracking is locked)" or "") or " (auto tracking is off)"))
end

-- The tracking that's on right now (for the lock's messages), or nil.
function HR.CurrentTracking()
	if not (NumTracking and TrackingInfo) then return nil end
	local okN, n = pcall(NumTracking)
	if not okN or type(n) ~= "number" then return nil end
	for i = 1, n do
		local name, active, sid = Entry(i)
		if Plain(active) and sid and not isSecret(sid) then
			for _, spell in pairs(TRACK_BY_TYPE) do
				if sid == spell then return Plain(name) end
			end
		end
	end
	for i = 1, n do
		local name, active = Entry(i)
		if Plain(active) and Plain(name) then return name end
	end
end

-- Lock tracking: keeps whatever tracking is on now. Only auto tracking pauses; the buff
-- reminders and the Feign Death warning carry on. One click (or /hrem tracklock) unlocks.
function HR.SetTrackLock(on)
	db.trackLocked = on and true or false
	if db.trackLocked then
		local cur = HR.CurrentTracking()
		Chat("tracking locked" .. (cur and (" on |cffffffff" .. cur .. "|r") or "") .. ". Auto tracking won't switch it until you unlock.")
	else
		Chat("tracking unlocked. Auto tracking matches your target again.")
		HR.AutoTrack()
	end
	if HR.UpdateMinimapButton then HR.UpdateMinimapButton() end
	if HR.OnTrackLockChanged then HR.OnTrackLockChanged() end
end

------------------------------------------------------------------------
-- Feign Death resisted: shortly after you feign, a mob still has you as its main target
-- (threat), which only happens when one of them resisted. Nothing here casts or targets anything.
-- (Not the combat log: on Forever, listening to it is blocked for add-ons.)
------------------------------------------------------------------------
local lastFeign, lastWarn = -100, -100

local warn = CreateFrame("Frame", "HunterReminderFeignWarning", UIParent)
warn:SetSize(600, 60)
warn:SetPoint("TOP", UIParent, "TOP", 0, -170)
warn:SetFrameStrata("HIGH")
warn:Hide()
warn.text = warn:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
warn.text:SetPoint("TOP")
warn.text:SetTextColor(1, 0.15, 0.15)
warn.sub = warn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
warn.sub:SetPoint("TOP", warn.text, "BOTTOM", 0, -4)
warn:SetScript("OnUpdate", function(self, elapsed)
	self.left = self.left - elapsed
	if self.left <= 0 then self:Hide() return end
	self:SetAlpha(self.left < 1 and self.left or 1)
	local s = 1 + 0.15 * math.max(0, self.left - 3.5) * 2 -- a short "pop" when it appears
	self.text:SetScale(s)
end)

local function ShowFeignWarning(who)
	lastWarn = GetTime()
	warn.text:SetText((feignName or "Feign Death") .. " RESISTED")
	warn.sub:SetText(who and (who .. " is still on you!") or "Something is still attacking you!")
	warn.left = 4
	warn:SetAlpha(1)
	warn:Show()
	if db.feignSound then PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end
end
HR.FeignTest = function() ShowFeignWarning("Test Mob") end

local function Recent() return GetTime() - lastFeign < 3 and GetTime() - lastWarn > 3 end

-- Threat check: is any mob we can see still attacking you? Strict, to never cry wolf:
-- it must have you as its tanked target (threat status 3, not just "top of the list"), and,
-- when the game says who it is targeting, that must be you.

local function StillTargeted()
	local units = { "target", "focus", "mouseover", "pettarget" }
	for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
	for _, u in ipairs(units) do
		local ok, status = pcall(UnitThreatSituation, "player", u)
		if ok and Plain(status) == 3 then
			local okD, dead = pcall(UnitIsDead, u)
			local okT, onMe = pcall(UnitIsUnit, u .. "target", "player")
			if not (okD and Plain(dead) == true) and not (okT and Plain(onMe) == false) then
				local okN, n = pcall(UnitName, u)
				return true, (okN and Plain(n)) or nil
			end
		end
	end
	return false
end

-- Threat can take a moment to clear after a good feign, so a mob must still be on you at
-- two checks in a row (about 1.2 and 2 seconds after you feign) before it warns.
local CHECKS = { 1.2, 2.0 }
local feignRun, hits = 0, 0
local function CheckAfterFeign(run)
	if run ~= feignRun or not db.feignWarn or not Recent() then return end
	if StillTargeted() then hits = hits + 1 else hits = 0; feignRun = feignRun + 1 return end
	if hits >= #CHECKS then
		local _, who = StillTargeted()
		HR.feignSource = "threat check"
		ShowFeignWarning(who)
	end
end

function HR.OnFeignCast()
	lastFeign = GetTime()
	feignRun, hits = feignRun + 1, 0
	local run = feignRun
	if C_Timer and C_Timer.After then
		for _, d in ipairs(CHECKS) do C_Timer.After(d, function() CheckAfterFeign(run) end) end
	end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff0000off|r" end

local MODE_TEXT = { always = "|cff00ff00always|r", combat = "|cffffd100in combat only|r", off = "|cffff0000off|r" }
local MODE_NEXT = { always = "combat", combat = "off", off = "always" }
HR.MODE_NEXT = MODE_NEXT

-- /hrem why: for each reminder, why it is (or isn't) showing right now.
function HR.Why()
	local buffs, hidden
	if not AurasSecret() then buffs, hidden = PlayerBuffNames() end
	local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
	for _, f in ipairs(icons) do
		local t = f.t
		local mode = db[t.key .. "Mode"] or "always"
		local why
		if not KnowsAny(t) then why = "you haven't learned it (not in your spellbook)"
		elseif mode == "off" then why = "turned off (/hrem " .. t.key .. ")"
		elseif UnitIsDeadOrGhost("player") then why = "you're dead"
		elseif UnitOnTaxi and UnitOnTaxi("player") then why = "you're on a flight"
		elseif mode == "combat" and not inCombat then why = "set to remind in combat only"
		elseif db.hideMounted and IsMounted and IsMounted() then why = "you're mounted (/hrem mount)"
		elseif not inCombat and not db.showResting and IsResting() then why = "you're in a city or inn (/hrem rest to remind there too)"
		elseif buffs and HasBuff(t, buffs) then why = "it's on"
		elseif not buffs then why = "buffs can't be read right now (in combat); last known: " .. (known[t.key] == nil and "unknown" or known[t.key] and "on" or "off")
		elseif hidden and known[t.key] ~= false then why = "some of your buffs are hidden from add-ons; waiting until it can tell"
		else why = "|cffff5555missing - the reminder should be showing|r" end
		Chat("|cffffffff" .. t.name .. "|r: " .. why .. (f:IsShown() and " (showing)" or ""))
	end
end

function HR.Refresh() Refresh() end
function HR.ApplyLook() ApplyLook() end
function HR.Test() testUntil = GetTime() + 5; Refresh() end
function HR.ResetPosition()
	db.point = { "CENTER", "UIParent", "CENTER", 0, 160 }; db.pos = {}; db.scale = 1; ApplyLook()
end

SLASH_HUNTERREMINDER1 = "/hrem"
SLASH_HUNTERREMINDER2 = "/hunterreminder"
SlashCmdList.HUNTERREMINDER = function(msg)
	local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "unlock" or cmd == "move" then
		db.locked = false; ApplyLook(); Chat("unlocked - drag each icon where you want it, then /hrem lock.")
	elseif cmd == "lock" then
		db.locked = true; ApplyLook(); Chat("locked.")
	elseif cmd == "rest" then
		db.showResting = not db.showResting; Chat("remind in cities/inns: " .. OnOff(db.showResting))
	elseif cmd == "mount" then
		db.hideMounted = not db.hideMounted; Chat("hide while mounted: " .. OnOff(db.hideMounted))
	elseif cmd == "sound" then
		db.sound = not db.sound; Chat("warning sound in combat: " .. OnOff(db.sound))
	elseif cmd == "trueshot" or cmd == "hawk" then
		local key = cmd .. "Mode"
		if MODE_TEXT[rest] then db[key] = rest else db[key] = MODE_NEXT[db[key]] or "always" end
		Refresh()
		Chat((cmd == "hawk" and "Aspect of the Hawk" or "Trueshot Aura") .. " reminder: " .. MODE_TEXT[db[key]])
	elseif cmd == "scale" then
		local n = tonumber(rest)
		if n and n >= 0.3 and n <= 3 then db.scale = n; ApplyLook() end
		Chat("scale " .. tostring(db.scale))
	elseif cmd == "track" then
		db.autoTrack = not db.autoTrack; Chat("auto tracking (match your target): " .. OnOff(db.autoTrack))
		HR.AutoTrack()
	elseif cmd == "tracklock" then
		HR.SetTrackLock(not db.trackLocked)
	elseif cmd == "check" then
		HR.CheckTracking()
	elseif cmd == "why" then
		HR.Why()
	elseif cmd == "feign" then
		if rest == "test" then HR.FeignTest() return end
		db.feignWarn = not db.feignWarn; Chat("warn when Feign Death is resisted: " .. OnOff(db.feignWarn))
	elseif cmd == "test" then
		testUntil = GetTime() + 5; Refresh(); Chat("showing both icons for 5 seconds.")
	elseif cmd == "reset" then
		HR.ResetPosition(); Chat("position and size reset.")
	elseif cmd == "help" then
		Chat("commands:  (/hrem on its own opens the settings window)")
		print("  /hrem trueshot always|combat|off  (now " .. MODE_TEXT[db.trueshotMode] .. ")")
		print("  /hrem hawk always|combat|off  (now " .. MODE_TEXT[db.hawkMode] .. ")")
		print("  /hrem unlock | lock  - move the icons (each one on its own)")
		print("  /hrem why  - why a reminder is or isn't showing")
		print("  /hrem test  - preview for 5s      /hrem scale 1.2  - size")
		print("  /hrem rest  - also remind in cities/inns (" .. OnOff(db.showResting) .. ")")
		print("  /hrem mount  - hide while mounted (" .. OnOff(db.hideMounted) .. ")")
		print("  /hrem sound  - a sound or voice when a reminder appears (" .. OnOff(db.sound) .. "; pick them in /hrem)")
		print("  /hrem reset  - reset position and size")
		print("  /hrem track  - switch tracking to match your target (" .. OnOff(db.autoTrack) .. ")")
		print("  /hrem tracklock  - lock tracking: keep the current one, pause auto tracking (" .. OnOff(db.trackLocked) .. ")")
		print("  /hrem check  - what auto tracking sees on your target")
		print("  /hrem feign  - warn when Feign Death is resisted (" .. OnOff(db.feignWarn) .. ")   /hrem feign test")
	else
		if HR.ToggleOptions then HR.ToggleOptions() end
	end
end
