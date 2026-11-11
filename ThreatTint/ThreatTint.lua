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
local BLUE = { 0.25, 0.55, 1.00 } -- your pet has it
TT.COLORS = {
	tank = { you = GREEN, losing = ORANGE, gaining = YELLOW, pet = BLUE, other = RED, loose = RED },
	dps  = { you = RED, losing = RED, gaining = YELLOW, pet = BLUE, other = GREEN },
}
-- What each colour means, in the order the settings window lists them.
TT.LEGEND = {
	tank = { { "you", "On you" }, { "losing", "On you, but someone is about to take it" },
		{ "gaining", "On someone else, you're about to take it back" }, { "pet", "On your pet" },
		{ "other", "On someone else: go get it" }, { "loose", "Fighting your group, not on your threat list yet" } },
	dps = { { "you", "Attacking you" }, { "losing", "On you, someone is about to take it" },
		{ "gaining", "Careful: you're about to pull it" }, { "pet", "On your pet" }, { "other", "Safe: on someone else" } },
}

-- Your colour for a state (your own pick from the window, or the default).
function TT.Color(role, state)
	local mine = ThreatTintDB and ThreatTintDB.colors and ThreatTintDB.colors[role] and ThreatTintDB.colors[role][state]
	if type(mine) == "table" and type(mine[1]) == "number" then return mine end
	return TT.COLORS[role][state]
end

-- Threat shading: while a mob is on someone else, its colour slides from "other" towards
-- "gaining" as your threat gets closer to pulling it (100%). DPS stay fully "other" up to 30%.
local SHADE_START = { dps = 30, tank = 0 }
local function Lerp(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
function TT.Shade(role, pct)
	local s = SHADE_START[role]
	local t = math.max(0, math.min(1, (pct - s) / (100 - s)))
	return Lerp(TT.Color(role, "other"), TT.Color(role, "gaining"), t)
end

-- How close you are to pulling a mob, 0-100 (nil when the game doesn't say).
function TT.Percent(unit)
	if not UnitDetailedThreatSituation then return nil end
	local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, "player", unit)
	if not ok then return nil end
	scaled = Plain(scaled)
	if type(scaled) ~= "number" then return nil end
	return scaled
end

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
	local role = TT.IsTank() and "tank" or "dps"
	local state = db and db.enabled and TT.State(unit)
	local c = state and TT.COLORS[role][state] and TT.Color(role, state)
	if c and db.shade and (state == "other" or state == "gaining") then
		local pct = TT.Percent(unit)
		if pct then c = TT.Shade(role, pct) end
	end
	if c then
		if not painted[bar] then
			if not original[bar] then
				local r, g, b = bar:GetStatusBarColor()
				original[bar] = { Plain(r) or 1, Plain(g) or 0, Plain(b) or 0 }
			end
		end
		local p = painted[bar]
		if not (p and math.abs(p[1] - c[1]) + math.abs(p[2] - c[2]) + math.abs(p[3] - c[3]) < 0.01) then -- unchanged: nothing to do (Blizzard resets are caught by the hook)
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
		if db.shade == nil then db.shade = true end
		if type(db.colors) ~= "table" then db.colors = {} end
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
	local role = tank and "tank" or "dps"
	for _, row in ipairs(TT.LEGEND[role]) do
		local c = TT.Color(role, row[1])
		-- a small block of that colour (white texture tinted in the |T escape), then what it means
		Print(("|TInterface\\Buttons\\WHITE8X8:10:24:0:0:8:8:0:8:0:8:%d:%d:%d|t %s"):format(c[1] * 255, c[2] * 255, c[3] * 255, row[2]))
	end
	if db.shade then Print("Shading is on: mobs on someone else fade towards the \"about to pull\" colour as your threat climbs.") end
	Print("Mobs nobody is fighting keep their normal colour. Settings window: " .. W .. "/tint|r")
	Print("Commands: " .. W .. "/tint auto|r (default), " .. W .. "/tint tank|r, " .. W .. "/tint dps|r, " .. W .. "/tint off|r, " .. W .. "/tint on|r, " .. W .. "/tint help|r")
end

------------------------------------------------------------------------
-- Settings window (/tint): on/off, role, shading, and the colour legend. Click a colour to change it.
------------------------------------------------------------------------
local win = CreateFrame("Frame", "ThreatTintFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(340, 380)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
if win.SetBackdrop then
	win:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
end
win:Hide()
tinsert(UISpecialFrames, "ThreatTintFrame") -- Escape closes it

local function Text(parent, font, x, y, w)
	local t = parent:CreateFontString(nil, "OVERLAY", font)
	t:SetPoint("TOPLEFT", x, y); t:SetJustifyH("LEFT")
	if w then t:SetWidth(w) end
	return t
end
local function Check(label, x, y)
	local c = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
	c:SetSize(24, 24); c:SetPoint("TOPLEFT", x, y)
	local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetText(label)
	c.label = t
	return c
end

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18); title:SetText("ThreatTint")
CreateFrame("Button", nil, win, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)

local onChk = Check("Colour enemy nameplates by threat", 18, -42)
local shadeChk = Check("Shade by threat: show how close you are to pulling", 18, -66)

Text(win, "GameFontNormal", 22, -100):SetText("You are:")
local roleBtns = {}
local ROLES = { { "auto", "Auto" }, { "tank", "Tank" }, { "dps", "DPS / Healer" } }
for i, r in ipairs(ROLES) do
	local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	b:SetSize(i == 3 and 96 or 60, 20); b:SetPoint("TOPLEFT", 84 + (i - 1) * 66, -96)
	b:SetText(r[2])
	b:SetScript("OnClick", function()
		ThreatTintDB.role = r[1]
		if r[1] == "auto" then autoTank = TT.AutoTank() end
		TT.UpdateAll(); win.Update()
	end)
	roleBtns[r[1]] = b
end
local roleNote = Text(win, "GameFontDisableSmall", 22, -122, 296)

local legendTitle = Text(win, "GameFontNormal", 22, -146)
local rows = {}
for i = 1, 6 do
	local sw = CreateFrame("Button", nil, win)
	sw:SetSize(36, 14); sw:SetPoint("TOPLEFT", 24, -166 - (i - 1) * 22)
	local border = sw:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0, 0, 0, 1)
	sw.tex = sw:CreateTexture(nil, "ARTWORK"); sw.tex:SetPoint("TOPLEFT", 1, -1); sw.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	sw.text = Text(win, "GameFontHighlightSmall", 68, -166 - (i - 1) * 22, 250)
	sw:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Click to change this colour"); GameTooltip:Show()
	end)
	sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = sw
end

-- Gradient strip: what shading looks like, from far away to about to pull.
local shadeTitle = Text(win, "GameFontDisableSmall", 22, -302)
local strip = {}
for i = 1, 20 do
	local t = win:CreateTexture(nil, "ARTWORK")
	t:SetSize(13, 10); t:SetPoint("TOPLEFT", 24 + (i - 1) * 13, -318)
	strip[i] = t
end
local farText = Text(win, "GameFontDisableSmall", 24, -330); farText:SetText("far")
local nearText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
nearText:SetPoint("TOPRIGHT", win, "TOPLEFT", 24 + 20 * 13, -330); nearText:SetText("about to pull")

local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
resetBtn:SetSize(110, 20); resetBtn:SetPoint("BOTTOMRIGHT", -18, 16); resetBtn:SetText("Reset colours")

local function Role() return TT.IsTank() and "tank" or "dps" end

-- Opens the game's colour picker for one state of the role shown.
local function PickColor(role, state)
	local c = TT.Color(role, state)
	local old = { c[1], c[2], c[3] }
	local function Save(r, g, b)
		ThreatTintDB.colors[role] = ThreatTintDB.colors[role] or {}
		ThreatTintDB.colors[role][state] = { r, g, b }
		TT.UpdateAll(); win.Update()
	end
	local function Changed() local r, g, b = ColorPickerFrame:GetColorRGB(); Save(r, g, b) end
	local function Cancel() Save(old[1], old[2], old[3]) end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({ r = c[1], g = c[2], b = c[3], hasOpacity = false,
			swatchFunc = Changed, cancelFunc = Cancel })
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Changed, Cancel
		ColorPickerFrame.previousValues = { r = c[1], g = c[2], b = c[3] }
		ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
		ColorPickerFrame:Hide(); ColorPickerFrame:Show()
	end
end

function win.Update()
	local db = ThreatTintDB
	local role = Role()
	onChk:SetChecked(db.enabled)
	shadeChk:SetChecked(db.shade)
	for k, b in pairs(roleBtns) do
		if b.LockHighlight then if db.role == k then b:LockHighlight() else b:UnlockHighlight() end end
	end
	local _, why = TT.AutoTank()
	roleNote:SetText(db.role == "auto" and ("Auto: you're " .. (role == "tank" and "tanking" or "not tanking")
		.. (why and (" (" .. why .. ")") or "") .. ".") or ("Set by you: " .. (role == "tank" and "tank" or "DPS / healer") .. " colours."))
	legendTitle:SetText(role == "tank" and "Colours while tanking:" or "Colours for DPS / healer:")
	local legend = TT.LEGEND[role]
	for i, sw in ipairs(rows) do
		local row = legend[i]
		if row then
			local c = TT.Color(role, row[1])
			sw.tex:SetColorTexture(c[1], c[2], c[3], 1)
			sw.text:SetText(row[2]); sw.text:Show(); sw:Show()
			sw:SetScript("OnClick", function() PickColor(role, row[1]) end)
		else
			sw:Hide(); sw.text:Hide()
		end
	end
	shadeTitle:SetText(db.shade and "Shading (mobs on someone else):" or "Shading is off: mobs on someone else stay one colour.")
	for i, t in ipairs(strip) do
		local c = db.shade and TT.Shade(role, (i - 1) / 19 * 100) or TT.Color(role, "other")
		t:SetColorTexture(c[1], c[2], c[3], 1)
	end
end

onChk:SetScript("OnClick", function(self) ThreatTintDB.enabled = self:GetChecked() and true or false; TT.UpdateAll(); win.Update() end)
shadeChk:SetScript("OnClick", function(self) ThreatTintDB.shade = self:GetChecked() and true or false; TT.UpdateAll(); win.Update() end)
resetBtn:SetScript("OnClick", function() ThreatTintDB.colors[Role()] = nil; TT.UpdateAll(); win.Update() end)
win:SetScript("OnShow", function() win.Update() end)

SLASH_THREATTINT1 = "/tint"
SLASH_THREATTINT2 = "/threattint"
SlashCmdList.THREATTINT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local db = ThreatTintDB
	if msg == "" then win:SetShown(not win:IsShown()); return end
	if msg == "tank" then db.role = "tank"
	elseif msg == "dps" or msg == "healer" or msg == "heal" then db.role = "dps"
	elseif msg == "auto" then db.role = "auto"; autoTank = TT.AutoTank()
	elseif msg == "off" then db.enabled = false
	elseif msg == "on" then db.enabled = true
	elseif msg == "toggle" then db.enabled = not db.enabled
	end
	TT.UpdateAll()
	if win:IsShown() then win.Update() end
	Help()
end
