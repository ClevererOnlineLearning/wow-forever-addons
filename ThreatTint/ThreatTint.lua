-- ThreatTint: colours Blizzard's enemy nameplates by threat.
-- Reads only UnitThreatSituation / UnitAffectingCombat on nameplate units, and checks every
-- value with issecretvalue first. Only the health bar colour changes; when a mob isn't in a
-- threat state the bar goes back to the colour Blizzard gave it. Event-driven, no OnUpdate.
local ADDON = ...
local TT = {}
_G.ThreatTint = TT

local IsSecret = issecretvalue or function() return false end
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffff6633ThreatTint:|r " .. msg) end

-- Colours per state, the retail "traffic lights" (as in Threat Plates / Plater).
-- "you": attacking you. "losing": on you, but someone is close to taking it. "gaining": someone
-- else has it, but you're about to pull it. "pet": your pet has it. "other": attacking someone
-- else in your fight. "loose": in combat, but not with you or your pet (tank only).
-- Mobs that aren't in a fight keep Blizzard's normal colour.
local GREEN, YELLOW, ORANGE, RED = { 0.15, 0.80, 0.15 }, { 1.00, 0.85, 0.00 }, { 1.00, 0.55, 0.00 }, { 0.95, 0.10, 0.10 }
TT.COLORS = {
	tank = { you = GREEN, losing = ORANGE, gaining = YELLOW, pet = GREEN, other = RED, loose = RED },
	dps  = { you = RED, losing = RED, gaining = YELLOW, pet = GREEN, other = GREEN },
}

------------------------------------------------------------------------
-- Are you tanking? "auto" (default) works it out; /tint tank or /tint dps forces it.
------------------------------------------------------------------------
local TANK_FORMS = { [5] = true, [8] = true, [18] = true } -- bear, dire bear, defensive stance
local RIGHTEOUS_FURY = 25780

local function Try(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if ok then return Plain(v) end
end

function TT.AutoTank()
	if Try(UnitHasEffectivelyTankAura, "player") == true then return true, "tank aura" end
	local form = Try(GetShapeshiftFormID)
	if form and TANK_FORMS[form] then return true, form == 18 and "Defensive Stance" or "Bear Form" end
	if Try(UnitGroupRolesAssigned, "player") == "TANK" then return true, "group role" end
	if Try(GetPartyAssignment, "MAINTANK", "player") then return true, "main tank" end
	local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and Try(C_UnitAuras.GetPlayerAuraBySpellID, RIGHTEOUS_FURY)
	if aura then return true, "Righteous Fury" end
	return false
end

local autoTank = false
function TT.IsTank()
	local role = ThreatTintDB and ThreatTintDB.role
	if role == "tank" then return true end
	if role == "dps" then return false end
	return autoTank
end

------------------------------------------------------------------------
-- Threat state of one nameplate unit (nil = leave Blizzard's colour alone)
------------------------------------------------------------------------
local function Situation(who, unit)
	local ok, s = pcall(UnitThreatSituation, who, unit)
	if not ok then return nil end
	return Plain(s)
end

local function Targets(unit, who)
	local ok, same = pcall(UnitIsUnit, unit .. "target", who)
	return ok and Plain(same) == true
end

function TT.State(unit)
	local ok, attackable = pcall(UnitCanAttack, "player", unit)
	if not ok or Plain(attackable) ~= true then return nil end
	local s = Situation("player", unit)
	local hasPet = Plain(UnitExists("pet")) == true
	local ps = hasPet and Situation("pet", unit) or nil
	if s and s >= 2 then return s >= 3 and "you" or "losing" end -- 3 = solidly on you, 2 = slipping
	local okc, combat = pcall(UnitAffectingCombat, unit)
	combat = okc and Plain(combat) == true
	-- Fast path: who the mob is actually targeting changes the moment it turns, often before
	-- the server's next threat update arrives.
	if combat and Targets(unit, "player") then return "you" end
	if (ps and ps >= 2) or (hasPet and combat and Targets(unit, "pet")) then return "pet" end
	if s == 1 then return "gaining" end
	if s == 0 or ps == 0 or ps == 1 then return "other" end
	-- Not on your threat list: is it fighting someone else (your group)?
	if combat then return "loose" end
	return nil
end

------------------------------------------------------------------------
-- Colouring
------------------------------------------------------------------------
local bars = {}       -- unit token -> health bar currently shown for it
local painted = setmetatable({}, { __mode = "k" }) -- bar -> { r, g, b } we set
local original = setmetatable({}, { __mode = "k" }) -- bar -> Blizzard's last colour
local hooked = setmetatable({}, { __mode = "k" })
local busy = false

local function SetColor(bar, c)
	busy = true
	bar:SetStatusBarColor(c[1], c[2], c[3])
	busy = false
end

-- Blizzard re-colours the bar now and then (reaction, tapped, etc.). Remember its colour, and
-- put ours back on top if this mob has a threat colour.
local function OnBlizzardColor(bar, r, g, b)
	if busy then return end
	original[bar] = { r, g, b }
	local mine = painted[bar]
	if mine then SetColor(bar, mine) end
end

local function GetBar(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return nil end
	local uf = plate.UnitFrame
	local bar = uf and uf.healthBar
	if not bar or not bar.SetStatusBarColor then return nil end
	if not hooked[bar] then
		hooked[bar] = true
		hooksecurefunc(bar, "SetStatusBarColor", OnBlizzardColor)
	end
	return bar
end

local function Restore(bar)
	if not painted[bar] then return end
	painted[bar] = nil
	local o = original[bar]
	if o then SetColor(bar, o) end
end

function TT.Update(unit)
	if type(unit) ~= "string" or not unit:find("^nameplate%d+$") then return end
	local bar = GetBar(unit)
	if not bar then bars[unit] = nil; return end
	bars[unit] = bar
	local db = ThreatTintDB
	local c = db and db.enabled and TT.COLORS[TT.IsTank() and "tank" or "dps"][TT.State(unit) or ""]
	if c then
		if not painted[bar] then
			if not original[bar] then
				local r, g, b = bar:GetStatusBarColor()
				original[bar] = { Plain(r) or 1, Plain(g) or 0, Plain(b) or 0 }
			end
		end
		if painted[bar] ~= c then -- unchanged: nothing to do (Blizzard resets are caught by the hook)
			painted[bar] = c
			SetColor(bar, c)
		end
	else
		Restore(bar)
	end
end

function TT.UpdateAll()
	for i = 1, 40 do
		local u = "nameplate" .. i
		if C_NamePlate.GetNamePlateForUnit(u) then TT.Update(u)
		elseif bars[u] then Restore(bars[u]); bars[u] = nil end
	end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ticker
local function StartTicker() -- safety net in combat, in case a threat event is missed
	if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.1, TT.UpdateAll) end
end
local function StopTicker() if ticker then ticker:Cancel(); ticker = nil end end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, unit)
	if event == "PLAYER_LOGIN" then
		local db = type(ThreatTintDB) == "table" and ThreatTintDB or {}
		ThreatTintDB = db
		if db.enabled == nil then db.enabled = true end
		if db.role ~= "tank" and db.role ~= "dps" then db.role = db.tank and "tank" or "auto" end
		db.tank = nil
		autoTank = TT.AutoTank()
		self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		self:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
		self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
		self:RegisterEvent("UNIT_FLAGS") -- a mob entering or leaving combat
		self:RegisterEvent("UNIT_TARGET") -- a mob turning to attack someone (instant)
		self:RegisterEvent("UNIT_PET")
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		-- role changes: stance/form, group role, buffs (Righteous Fury)
		self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		self:RegisterEvent("PLAYER_ROLES_ASSIGNED")
		self:RegisterEvent("GROUP_ROSTER_UPDATE")
		self:RegisterUnitEvent("UNIT_AURA", "player")
		if not db.seenIntro then
			db.seenIntro = true
			Print("Enemy nameplates now change colour by threat. It works out whether you're tanking by itself. Help: |cffffffff/tint|r")
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_FLAGS" or event == "UNIT_TARGET" then
		if type(unit) == "string" and unit:find("^nameplate%d+$") then TT.Update(unit)
		elseif event == "UNIT_THREAT_LIST_UPDATE" then TT.UpdateAll() end -- fired for "target" etc.: the same mob may have a plate
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local bar = bars[unit]
		if bar then Restore(bar); bars[unit] = nil end
	elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ROLES_ASSIGNED" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_AURA" then
		local now = TT.AutoTank()
		if now ~= autoTank then autoTank = now; TT.UpdateAll() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		StartTicker(); TT.UpdateAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		StopTicker(); TT.UpdateAll()
	else -- UNIT_THREAT_SITUATION_UPDATE (player/pet), UNIT_PET
		TT.UpdateAll()
	end
end)

------------------------------------------------------------------------
-- /tint
------------------------------------------------------------------------
local G, R, Y, O, W = "|cff26cc26", "|cfff21a1a", "|cffffd900", "|cffff8c00", "|cffffffff"
local function Help()
	local db = ThreatTintDB
	local tank = TT.IsTank()
	local how
	if db.role == "auto" then
		local _, why = TT.AutoTank()
		how = why and (" (auto: " .. why .. ")") or " (auto)"
	else
		how = " (set by you; |cffffffff/tint auto|r to detect it)"
	end
	Print(("is %s, colours for %s%s."):format(db.enabled and (G .. "on|r") or (R .. "off|r"),
		W .. (tank and "a tank" or "DPS / healer") .. "|r", how))
	if tank then
		Print(G .. "Green|r = it's on you (or your pet).  " .. O .. "Orange|r = you're about to lose it.  " .. Y .. "Yellow|r = you're about to take it.  "
			.. R .. "Red|r = it's attacking someone else: go get it.")
	else
		Print(R .. "Red|r = it's attacking you.  " .. Y .. "Yellow|r = careful, you're about to pull it.  " .. G .. "Green|r = safe, it's on someone else (or your pet).")
	end
	Print("Mobs nobody is fighting keep their normal colour.")
	Print("Commands: " .. W .. "/tint auto|r (default), " .. W .. "/tint tank|r, " .. W .. "/tint dps|r, " .. W .. "/tint off|r, " .. W .. "/tint on|r")
end

SLASH_THREATTINT1 = "/tint"
SLASH_THREATTINT2 = "/threattint"
SlashCmdList.THREATTINT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local db = ThreatTintDB
	if msg == "tank" then db.role = "tank"
	elseif msg == "dps" or msg == "healer" or msg == "heal" then db.role = "dps"
	elseif msg == "auto" then db.role = "auto"; autoTank = TT.AutoTank()
	elseif msg == "off" then db.enabled = false
	elseif msg == "on" then db.enabled = true
	elseif msg == "toggle" then db.enabled = not db.enabled
	end
	TT.UpdateAll()
	Help()
end
