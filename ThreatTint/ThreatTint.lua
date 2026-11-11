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
	tank = { you = GREEN, losing = ORANGE, gaining = YELLOW, close = ORANGE, pet = BLUE, other = RED, loose = RED },
	dps  = { you = RED, losing = RED, gaining = YELLOW, close = ORANGE, pet = BLUE, other = GREEN },
}
-- What each colour means, in the order the settings window lists them.
TT.LEGEND = {
	tank = { { "you", "On you" }, { "losing", "On you, but someone is about to take it" },
		{ "other", "On someone else: go get it" }, { "close", "On someone else, you're halfway to taking it back (50%+)" },
		{ "gaining", "On someone else, you're about to take it back (80%+)" }, { "pet", "On your pet" },
		{ "loose", "Fighting your group, not on your threat list yet" } },
	dps = { { "you", "Attacking you" }, { "losing", "On you, someone is about to take it" },
		{ "other", "Safe: on someone else (under 50%)" }, { "gaining", "Careful: 50-80% of the threat to pull it" },
		{ "close", "About to pull it (80%+)" }, { "pet", "On your pet" } },
}

-- Your colour for a state (your own pick from the window, or the default).
function TT.Color(role, state)
	local mine = ThreatTintDB and ThreatTintDB.colors and ThreatTintDB.colors[role] and ThreatTintDB.colors[role][state]
	if type(mine) == "table" and type(mine[1]) == "number" then return mine end
	return TT.COLORS[role][state]
end

-- /tint check: what the game tells add-ons about your threat on your target. Only reports;
-- a hidden (secret) value is reported as hidden, never read.
function TT.Check()
	local function Show(label, v)
		if v == nil then return label .. " nothing" end
		if IsSecret(v) then return label .. " |cffff6633hidden from add-ons|r" end
		return label .. " |cffffffff" .. tostring(v) .. "|r"
	end
	if not UnitDetailedThreatSituation then Print("This game has no threat % for add-ons at all."); return end
	if Plain(UnitExists("target")) ~= true then Print("Target a mob you're fighting first, then type /tint check."); return end
	local ok, tanking, status, scaled, raw = pcall(UnitDetailedThreatSituation, "player", "target")
	if not ok then Print("The game gave an error when asked for your threat."); return end
	Print("Your threat on your target: " .. Show("status", status) .. ", " .. Show("% to pull", scaled) .. ", " .. Show("raw %", raw) .. ".")
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
	Print(plate and "Your target has a nameplate." or "Your target has no nameplate showing (the number goes on the nameplate).")
	local unit
	for i = 1, 40 do local u = "nameplate" .. i; local okU, same = pcall(UnitIsUnit, u, "target"); if okU and Plain(same) == true then unit = u break end end
	if unit then
		local role = TT.IsTank() and "tank" or "dps"
		local state = TT.State(unit)
		Print("ThreatTint sees it as: |cffffffff" .. tostring(state or "not fighting") .. "|r (" .. role .. ").")
		local db = ThreatTintDB
		local why
		if not db.enabled then why = "ThreatTint is off"
		elseif not db.number then why = "the % is switched off in /tint"
		elseif state == "you" or state == "losing" then why = "the mob is on you (the bar colour says that)"
		elseif not (state == "other" or state == "gaining" or state == "pet") then why = "the mob isn't on your threat list"
		elseif not TT.Percent(unit) then why = "the game gave no %" end
		local t = TT.NumberFor(unit)
		if why then Print("Number on the nameplate: hidden, because " .. why .. ".")
		elseif t and t:IsShown() then Print("Number on the nameplate: showing |cffffffff" .. tostring(t:GetText()) .. "|r. Can't see it? Tell me.")
		else Print("Number on the nameplate: should be showing but isn't. Tell me.") end
	end
end

-- Threat steps: while a mob is on someone else, three clear colour bands show how close you
-- are to pulling it (DPS) or taking it back (tank). pct = % of the threat needed, 0-100.
function TT.Band(role, pct)
	if role == "dps" then
		if pct >= 80 then return "close" elseif pct >= 50 then return "gaining" end
	else
		if pct >= 80 then return "gaining" elseif pct >= 50 then return "close" end
	end
	return "other"
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

-- The small threat % to the right of the health bar (our own text, on the bar).
local numbers = setmetatable({}, { __mode = "k" })
function TT.SetNumber(bar, pct, c)
	local t = numbers[bar]
	if not pct then if t then t:Hide(); t.holder:Hide() end return end
	if not t then
		-- Our own small frame on the nameplate itself (not inside the health bar, whose container
		-- can cut off anything drawn past its edge), placed over the bar and drawn above it.
		local plate = bar
		while plate:GetParent() and plate:GetParent() ~= UIParent and plate:GetParent() ~= WorldFrame do plate = plate:GetParent() end
		local holder = CreateFrame("Frame", nil, plate)
		holder:SetAllPoints(bar)
		holder:SetFrameLevel((bar:GetFrameLevel() or 1) + 10)
		t = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("LEFT", holder, "RIGHT", 3, 0)
		t.holder = holder
		numbers[bar] = t
	end
	t:SetText(("%d%%"):format(math.floor(pct + 0.5)))
	t:SetTextColor(c[1], c[2], c[3])
	t.holder:Show(); t:Show()
end

function TT.NumberFor(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local bar = plate and plate.UnitFrame and plate.UnitFrame.healthBar
	return bar and numbers[bar]
end

local function Restore(bar)
	TT.SetNumber(bar, nil)
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
	-- The % matters whenever the mob is on someone else, including your pet (are you about to
	-- pull it off your pet?). The bar stays blue for your pet; the number shows the step colour.
	local pct = (state == "other" or state == "gaining" or state == "pet") and TT.Percent(unit) or nil
	local numColor
	if pct and db.shade then
		local band = TT.Band(role, pct)
		numColor = TT.Color(role, band)
		if state ~= "pet" then state = band end
	end
	local c = state and TT.COLORS[role][state] and TT.Color(role, state)
	TT.SetNumber(bar, c and db.number and pct, numColor or c)
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
		if db.number == nil then db.number = true end
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
	if db.shade then Print("Colour steps are on: the colour of a mob on someone else changes at 50% and 80% of the threat needed.") end
	Print("Mobs nobody is fighting keep their normal colour. Settings window: " .. W .. "/tint|r")
	Print("Commands: " .. W .. "/tint auto|r (default), " .. W .. "/tint tank|r, " .. W .. "/tint dps|r, " .. W .. "/tint off|r, " .. W .. "/tint on|r, " .. W .. "/tint help|r")
end

------------------------------------------------------------------------
-- Settings window (/tint): on/off, role, shading, and the colour legend. Click a colour to change it.
------------------------------------------------------------------------
local win = CreateFrame("Frame", "ThreatTintFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(340, 430)
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
local shadeChk = Check("Colour steps by threat % (how close you are to pulling)", 18, -66)
local numChk = Check("Show the threat % next to each nameplate", 18, -90)

Text(win, "GameFontNormal", 22, -124):SetText("You are:")
local roleBtns = {}
local ROLES = { { "auto", "Auto" }, { "tank", "Tank" }, { "dps", "DPS / Healer" } }
for i, r in ipairs(ROLES) do
	local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	b:SetSize(i == 3 and 96 or 60, 20); b:SetPoint("TOPLEFT", 84 + (i - 1) * 66, -120)
	b:SetText(r[2])
	b:SetScript("OnClick", function()
		ThreatTintDB.role = r[1]
		if r[1] == "auto" then autoTank = TT.AutoTank() end
		TT.UpdateAll(); win.Update()
	end)
	roleBtns[r[1]] = b
end
local roleNote = Text(win, "GameFontDisableSmall", 22, -146, 296)

local legendTitle = Text(win, "GameFontNormal", 22, -170)
local rows = {}
for i = 1, 7 do
	local sw = CreateFrame("Button", nil, win)
	sw:SetSize(36, 14); sw:SetPoint("TOPLEFT", 24, -190 - (i - 1) * 22)
	local border = sw:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0, 0, 0, 1)
	sw.tex = sw:CreateTexture(nil, "ARTWORK"); sw.tex:SetPoint("TOPLEFT", 1, -1); sw.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	sw.text = Text(win, "GameFontHighlightSmall", 68, -190 - (i - 1) * 22, 250)
	sw:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Click to change this colour"); GameTooltip:Show()
	end)
	sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = sw
end

-- Strip: the colour steps, from far away to about to pull.
local shadeTitle = Text(win, "GameFontDisableSmall", 22, -350)
local strip = {}
for i = 1, 20 do
	local t = win:CreateTexture(nil, "ARTWORK")
	t:SetSize(13, 10); t:SetPoint("TOPLEFT", 24 + (i - 1) * 13, -366)
	strip[i] = t
end
local farText = Text(win, "GameFontDisableSmall", 24, -378); farText:SetText("0%")
local nearText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
nearText:SetPoint("TOPRIGHT", win, "TOPLEFT", 24 + 20 * 13, -378); nearText:SetText("100%")

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
	numChk:SetChecked(db.number)
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
	shadeTitle:SetText(db.shade and ("Colour steps for a mob on someone else, by your threat %" .. (role == "tank" and " (to take it back):" or " (to pull it):"))
		or "Colour steps are off: mobs on someone else stay one colour.")
	for i, t in ipairs(strip) do
		local c = TT.Color(role, db.shade and TT.Band(role, (i - 1) / 19 * 100) or "other")
		t:SetColorTexture(c[1], c[2], c[3], 1)
	end
end

onChk:SetScript("OnClick", function(self) ThreatTintDB.enabled = self:GetChecked() and true or false; TT.UpdateAll(); win.Update() end)
shadeChk:SetScript("OnClick", function(self) ThreatTintDB.shade = self:GetChecked() and true or false; TT.UpdateAll(); win.Update() end)
numChk:SetScript("OnClick", function(self) ThreatTintDB.number = self:GetChecked() and true or false; TT.UpdateAll(); win.Update() end)
resetBtn:SetScript("OnClick", function() ThreatTintDB.colors[Role()] = nil; TT.UpdateAll(); win.Update() end)
win:SetScript("OnShow", function() win.Update() end)

SLASH_THREATTINT1 = "/tint"
SLASH_THREATTINT2 = "/threattint"
SlashCmdList.THREATTINT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local db = ThreatTintDB
	if msg == "" then win:SetShown(not win:IsShown()); return end
	if msg == "check" then TT.Check(); return end
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
