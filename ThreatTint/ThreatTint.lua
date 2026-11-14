-- ThreatTint: colours Blizzard's enemy nameplates by threat.
-- Reads only UnitThreatSituation / UnitAffectingCombat on nameplate units, and checks every
-- value with issecretvalue first. Only the health bar colour changes; when a mob isn't in a
-- threat state the bar goes back to the colour Blizzard gave it. Event-driven, no OnUpdate.
local ADDON, ns = ...
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
		{ "other", "Safe: on someone else (up to 30%)" }, { "gaining", "Careful: fades in from 30%, full at 60%" },
		{ "close", "About to pull it: full at 85%, then fades to red" }, { "pet", "On your pet (fades to yellow, orange, red as you near pulling it)" } },
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

-- DPS: a smooth fade instead of steps, so a climbing threat shows long before it flips.
-- From the mob's resting colour (blue on your pet, green on someone else) up to 30%, through
-- yellow at 60% and orange at 85%, to red at 100% (you pull it).
local STOPS = { { 30, nil }, { 60, "gaining" }, { 85, "close" }, { 100, "you" } }
function TT.Fade(role, base, pct)
	local function C(key) return key and TT.Color(role, key) or TT.Color(role, base) end
	if pct <= STOPS[1][1] then return C(nil) end
	for i = 2, #STOPS do
		local a, b = STOPS[i - 1], STOPS[i]
		if pct <= b[1] then
			local f = (pct - a[1]) / (b[1] - a[1])
			local ca, cb = C(a[2]), C(b[2])
			return { ca[1] + (cb[1] - ca[1]) * f, ca[2] + (cb[2] - ca[2]) * f, ca[3] + (cb[3] - ca[3]) * f }
		end
	end
	return C("you")
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

-- "Rising fast": how many seconds until you'd pull a mob if your threat keeps climbing at the
-- rate of the last second or two (nil = not climbing, or too soon to tell). Two samples per bar,
-- about a second apart; a drop (threat wipe, the tank catching up) starts over.
local hist = setmetatable({}, { __mode = "k" })
function TT.Rising(bar, pct, now)
	if not pct then hist[bar] = nil; return nil end
	local h = hist[bar]
	if not h or pct < h.bp - 2 then hist[bar] = { bt = now, bp = pct }; return nil end
	if now - h.bt >= 1 then h.at, h.ap, h.bt, h.bp = h.bt, h.bp, now, pct end
	if not h.at or now <= h.at then return nil end
	local rate = (pct - h.ap) / (now - h.at)
	if rate <= 0 then return nil end
	return (100 - pct) / rate
end
TT.RISING_SECONDS = 3

function TT.Update(unit)
	if type(unit) ~= "string" or not unit:find("^nameplate%d+$") then return end
	local bar = GetBar(unit)
	if not bar then bars[unit] = nil; return end
	bars[unit] = bar
	local db = ThreatTintDB
	local role = TT.IsTank() and "tank" or "dps"
	local state = db and db.enabled and TT.State(unit)
	-- The % matters whenever the mob is on someone else, including your pet (are you about to
	-- pull it off your pet?). On your pet the bar stays blue while you're safe; as DPS it turns
	-- a fade from 30% through yellow (60%) and orange (85%) to red, so pulling it off your pet
	-- never comes as a surprise. The game's "you've passed them" flag warns even without a %.
	-- (Tanks keep blue: taking a mob from your own pet is fine for a tank.)
	local pct = (state == "other" or state == "gaining" or state == "pet") and TT.Percent(unit) or nil
	local numColor, faded
	if role == "dps" and (state == "pet" or state == "other" or state == "gaining") and db.shade then
		-- The game's own "you've passed whoever has it" flag (threat status 1) counts even when
		-- your pet has the mob and even when the % is missing: you can pull it any moment.
		local over = Situation("player", unit) == 1
		local base = state == "pet" and "pet" or "other"
		local p = pct
		if over and (not p or p < 90) then p = 90 end
		if p then faded = TT.Fade(role, base, p); numColor = faded end
		-- Climbing fast enough to pull it within a few seconds: pulse towards red now, while
		-- there's still time to ease off. (A single huge crit can't be seen coming.)
		local now = GetTime()
		local secs = TT.Rising(bar, pct, now)
		if db.rising and faded and secs and secs <= TT.RISING_SECONDS and pct >= 40 and pct < 100 then
			local red = TT.Color(role, "you")
			local f = 0.25 + 0.5 * (0.5 + 0.5 * math.sin(now * 9))
			faded = { faded[1] + (red[1] - faded[1]) * f, faded[2] + (red[2] - faded[2]) * f, faded[3] + (red[3] - faded[3]) * f }
		end
	elseif pct and db.shade then
		local band = TT.Band(role, pct)
		numColor = TT.Color(role, band)
		if state ~= "pet" then state = band end
	end
	local c = faded or (state and TT.COLORS[role][state] and TT.Color(role, state))
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
		if db.rising == nil then db.rising = true end
		if db.number == nil then db.number = true end
		if type(db.colors) ~= "table" then db.colors = {} end
		if type(db.minimap) ~= "table" then db.minimap = { hide = false, angle = 225 } end
		if TT.UpdateMinimapButton then TT.UpdateMinimapButton() end
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
	if db.shade then Print("Threat colours are on: as DPS, a mob on someone else (or your pet) fades from 30% to yellow (60%), orange (85%) and red (100%) of the threat needed to pull it.") end
	Print("Mobs nobody is fighting keep their normal colour. Settings window: " .. W .. "/tint|r")
	Print("Commands: " .. W .. "/tint auto|r (default), " .. W .. "/tint tank|r, " .. W .. "/tint dps|r, " .. W .. "/tint off|r, " .. W .. "/tint on|r, " .. W .. "/tint help|r")
end

------------------------------------------------------------------------
-- Settings window (/tint): on/off, role, shading, and the colour legend. Click a colour to change it.
------------------------------------------------------------------------
local S = ns.Skin
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local WW = 384
local CW = WW - 24
local win = S.Window("ThreatTintFrame", "ThreatTint", "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	GetMeta and GetMeta("ThreatTint", "Version"), WW, 580)
local more = S.MoreButton(win.head, "ThreatTint", win)
more:SetPoint("RIGHT", win.close, "LEFT", -8, 0)

local function Text(parent, font, x, y, w)
	local t = parent:CreateFontString(nil, "OVERLAY", font)
	t:SetPoint("TOPLEFT", x, y); t:SetJustifyH("LEFT")
	if w then t:SetWidth(w) end
	return t
end

-- General
local c1 = S.Card(win, "Nameplates", 12, -44, CW)
local onChk = S.Check(c1, "Colour enemy nameplates by threat", 14, -34)
local shadeChk = S.Check(c1, "Colour fades by threat % (how close you are)", 14, -60)
local numChk = S.Check(c1, "Show the threat % next to each nameplate", 14, -86)
local risingChk = S.Check(c1, "Pulse when your threat is climbing fast", 14, -112)
S.Tip(risingChk, "Climbing fast", "As DPS: if your threat is rising quickly enough to pull the mob within about 3 seconds, its nameplate pulses towards red, even if it's only yellow so far.")
risingChk:SetScript("OnClick", function(self) ThreatTintDB.rising = self:GetChecked() and true or false; TT.UpdateAll() end)
c1:SetHeight(142)

-- Role
local c2 = S.Card(win, "You are", 12, S.Below(c1), CW)
local roleBtns = {}
local ROLES = { { "auto", "Auto" }, { "tank", "Tank" }, { "dps", "DPS / Healer" } }
local bw = math.floor((CW - 28 - 12) / 3)
for i, r in ipairs(ROLES) do
	local b = S.Button(c2, r[2], bw, 24)
	b:SetPoint("TOPLEFT", 14 + (i - 1) * (bw + 6), -32)
	b:SetScript("OnClick", function()
		ThreatTintDB.role = r[1]
		if r[1] == "auto" then autoTank = TT.AutoTank() end
		TT.UpdateAll(); win.Update()
	end)
	roleBtns[r[1]] = b
end
local roleNote = Text(c2, "GameFontDisableSmall", 14, -64, CW - 28)
c2:SetHeight(86)

-- Colour legend + the steps strip
local c3 = S.Card(win, "Colours", 12, S.Below(c2), CW)
local legendTitle = c3.title
local rows = {}
for i = 1, 7 do
	local sw = CreateFrame("Button", nil, c3)
	sw:SetSize(40, 16); sw:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 24)
	S.Border(sw, 0, 0, 0, 1)
	sw.tex = sw:CreateTexture(nil, "ARTWORK"); sw.tex:SetPoint("TOPLEFT", 1, -1); sw.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	local hl = sw:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.25)
	sw.text = Text(c3, "GameFontHighlightSmall", 64, -36 - (i - 1) * 24, CW - 78)
	sw:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Click to change this colour"); GameTooltip:Show()
	end)
	sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = sw
end

-- Strip: the colour steps, from far away to about to pull. It sits in its own frame, which
-- moves up to just under the last colour row (DPS has 6 rows, tanks 7), so there's no gap.
local sb = CreateFrame("Frame", nil, c3)
sb:SetSize(CW, 72)
local shadeTitle = Text(sb, "GameFontDisableSmall", 14, 0, CW - 28)
local strip = {}
local cell = math.floor((CW - 28) / 20)
for i = 1, 20 do
	local t = sb:CreateTexture(nil, "ARTWORK")
	t:SetSize(cell - 1, 10); t:SetPoint("TOPLEFT", 14 + (i - 1) * cell, -18)
	strip[i] = t
end
local farText = Text(sb, "GameFontDisableSmall", 14, -32); farText:SetText("0%")
local nearText = sb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
nearText:SetPoint("TOPRIGHT", sb, "TOPLEFT", 14 + 20 * cell, -32); nearText:SetText("100%")
S.Note(sb, "Click a colour to pick your own.", 14, -50)

local foot = S.Footer(win, 40)
local mmChk = S.Check(foot, "Show minimap button")
mmChk:SetPoint("LEFT", 14, 0)
local resetBtn = S.Button(foot, "Reset colours", 120, 24)
resetBtn:SetPoint("RIGHT", -12, 0)

-- Fits the colours card (and the window) to the number of colour rows shown.
local function FitColours(n)
	local sy = -34 - n * 24 - 6
	sb:ClearAllPoints()
	sb:SetPoint("TOPLEFT", 0, sy)
	c3:SetHeight(-(sy - 50) + 22)
	win:SetHeight(-S.Below(c3) + 40 + 2)
end
FitColours(7)

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

-- the chosen role button looks selected (gold)
local function Selected(b, on)
	b.bg:SetColorTexture(on and 0.42 or 0.15, on and 0.31 or 0.15, on and 0.02 or 0.18, 1)
	if on then S.Border(b, 0.85, 0.66, 0.1, 1) else S.Border(b, 0.26, 0.26, 0.31, 1) end
end

function win.Update()
	local db = ThreatTintDB
	local role = Role()
	onChk:SetChecked(db.enabled)
	shadeChk:SetChecked(db.shade)
	risingChk:SetChecked(db.rising)
	numChk:SetChecked(db.number)
	mmChk:SetChecked(not (db.minimap and db.minimap.hide))
	for k, b in pairs(roleBtns) do Selected(b, db.role == k) end
	local _, why = TT.AutoTank()
	roleNote:SetText(db.role == "auto" and ("Auto: you're " .. (role == "tank" and "tanking" or "not tanking")
		.. (why and (" (" .. why .. ")") or "") .. ".") or ("Set by you: " .. (role == "tank" and "tank" or "DPS / healer") .. " colours."))
	legendTitle:SetText(role == "tank" and "Colours while tanking" or "Colours for DPS / healer")
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
	FitColours(math.min(#legend, #rows))
	shadeTitle:SetText(db.shade and ("Steps for a mob on someone else, by your threat %" .. (role == "tank" and " (to take it back):" or " (to pull it):"))
		or "Colour steps are off: mobs on someone else stay one colour.")
	for i, t in ipairs(strip) do
		local c = TT.Color(role, db.shade and TT.Band(role, (i - 1) / 19 * 100) or "other")
		t:SetColorTexture(c[1], c[2], c[3], 1)
	end
end

onChk:SetScript("OnClick", function(self)
	ThreatTintDB.enabled = self:GetChecked() and true or false
	TT.UpdateAll(); win.Update()
	if TT.UpdateMinimapButton then TT.UpdateMinimapButton() end
end)
shadeChk:SetScript("OnClick", function(self) ThreatTintDB.shade = self:GetChecked() and true or false; TT.UpdateAll(); win.Update() end)
numChk:SetScript("OnClick", function(self) ThreatTintDB.number = self:GetChecked() and true or false; TT.UpdateAll(); win.Update() end)
resetBtn:SetScript("OnClick", function() ThreatTintDB.colors[Role()] = nil; TT.UpdateAll(); win.Update() end)
win:SetScript("OnShow", function() win.Update() end)

------------------------------------------------------------------------
-- Minimap button: left-click settings, right-click on/off, drag to move
------------------------------------------------------------------------
local mm = CreateFrame("Button", "ThreatTintMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetSize(20, 20); mmBg:SetPoint("TOPLEFT", 7, -5)
local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetTexture("Interface\\Icons\\Ability_Warrior_DefensiveStance")
mmIcon:SetSize(17, 17); mmIcon:SetPoint("TOPLEFT", 7, -6)
mmIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53); mmBorder:SetPoint("TOPLEFT")
mm:Hide()

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function PlaceButton()
	local a = math.rad(ThreatTintDB.minimap.angle or 225)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
function TT.UpdateMinimapButton()
	local db = ThreatTintDB
	if not (db and db.minimap) then return end
	if db.minimap.hide then mm:Hide() else PlaceButton(); mm:Show() end
	mmIcon:SetDesaturated(not db.enabled) -- grey while colouring is off
end
S.Group(mm, "ThreatTint", function() return ThreatTintDB and ThreatTintDB.minimap end, TT.UpdateMinimapButton) -- the shared minimap bag

local function MinimapTip(self)
	local db = ThreatTintDB
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("ThreatTint")
	GameTooltip:AddLine(db.enabled and ("|cff33ff33On|r, " .. (TT.IsTank() and "tank" or "DPS / healer") .. " colours") or "|cffff4040Off|r", 1, 1, 1)
	GameTooltip:AddLine("|cffffffffLeft-click|r  settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r  colouring on/off", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end
mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		ThreatTintDB.minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
		PlaceButton()
	end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnClick", function(self, button)
	if button == "RightButton" then
		ThreatTintDB.enabled = not ThreatTintDB.enabled
		TT.UpdateAll()
		TT.UpdateMinimapButton()
		if win:IsShown() then win.Update() end
		Print(ThreatTintDB.enabled and "on." or "off.")
	else
		win:SetShown(not win:IsShown())
	end
	MinimapTip(self)
end)
mm:SetScript("OnEnter", MinimapTip)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

mmChk:SetScript("OnClick", function(self)
	ThreatTintDB.minimap.hide = not self:GetChecked()
	TT.UpdateMinimapButton()
end)

SLASH_THREATTINT1 = "/tint"
SLASH_THREATTINT2 = "/threattint"
SlashCmdList.THREATTINT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local db = ThreatTintDB
	if msg == "" then win:SetShown(not win:IsShown()); return end
	if msg == "check" then TT.Check(); return end
	if msg == "minimap" then
		db.minimap.hide = not db.minimap.hide
		TT.UpdateMinimapButton()
		if win:IsShown() then win.Update() end
		Print(db.minimap.hide and "minimap button hidden (/tint minimap brings it back)." or "minimap button shown.")
		return
	end
	if msg == "tank" then db.role = "tank"
	elseif msg == "dps" or msg == "healer" or msg == "heal" then db.role = "dps"
	elseif msg == "auto" then db.role = "auto"; autoTank = TT.AutoTank()
	elseif msg == "off" then db.enabled = false
	elseif msg == "on" then db.enabled = true
	elseif msg == "toggle" then db.enabled = not db.enabled
	end
	TT.UpdateAll()
	TT.UpdateMinimapButton()
	if win:IsShown() then win.Update() end
	Help()
end
