-- PetWarn: a gentle "Pet not attacking" reminder in the middle of the screen when you're in a
-- fight and your pet is idle. No sound. Only reads your own pet; every value is checked with
-- issecretvalue first, and if the game hides something the warning simply stays away.
local PW = {}
_G.PetWarn = PW

local GRACE = 1.5 -- seconds in combat before warning, so you have time to send the pet in
local ATTACK_ICON = PET_ATTACK_TEXTURE or "Interface\\Icons\\Ability_GhoulFrenzy"

local IsSecret = issecretvalue or function() return false end
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end
local function Try(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if ok then return Plain(v) end
end
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00PetWarn:|r " .. msg) end

------------------------------------------------------------------------
-- Is the pet attacking?
------------------------------------------------------------------------
local attackEvent = false -- PET_ATTACK_START / PET_ATTACK_STOP

-- The pet bar's Attack button lights up while the pet is attacking.
local function AttackButtonLit()
	if not GetPetActionInfo then return nil end
	for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
		local ok, name, _, isToken, isActive = pcall(GetPetActionInfo, i)
		if ok and Plain(name) == "PET_ACTION_ATTACK" and Plain(isToken) then
			local a = Plain(isActive)
			if a == nil then return nil end
			return a and true or false
		end
	end
	return nil -- no Attack button (or hidden): unknown
end

-- true = attacking, false = idle, nil = can't tell (then we never warn)
function PW.PetAttacking()
	if attackEvent then return true end
	local lit = AttackButtonLit()
	if lit then return true end
	local hasTarget = Try(UnitExists, "pettarget")
	local petCombat = Try(UnitAffectingCombat, "pet")
	if hasTarget and petCombat then return true end -- busy with something (e.g. a pet ability)
	if lit == false then return false end
	if hasTarget == false then return false end
	return nil
end

-- Should the warning show right now (ignoring the grace period)?
function PW.ShouldWarn()
	if not (PetWarnDB and PetWarnDB.enabled) then return false end
	if Try(UnitExists, "pet") ~= true then return false end
	if Try(UnitIsDead, "pet") ~= false then return false end
	if Try(UnitAffectingCombat, "player") ~= true then return false end
	if Try(UnitOnTaxi, "player") then return false end
	if Try(UnitHasVehicleUI, "player") then return false end
	return PW.PetAttacking() == false
end

------------------------------------------------------------------------
-- The warning
------------------------------------------------------------------------
local f = CreateFrame("Frame", "PetWarnFrame", UIParent)
f:SetSize(260, 48)
f:SetFrameStrata("HIGH")
f:SetMovable(true)
f:SetClampedToScreen(true)
f:Hide()

local holder = CreateFrame("Frame", nil, f) -- the part that bounces
holder:SetAllPoints()

local icon = holder:CreateTexture(nil, "ARTWORK")
icon:SetSize(40, 40)
icon:SetPoint("LEFT", 4, 0)
icon:SetTexture(ATTACK_ICON)
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
text:SetPoint("LEFT", icon, "RIGHT", 10, 0)
text:SetText("Pet not attacking")
text:SetTextColor(1, 0.82, 0)
text:SetShadowOffset(2, -2)

-- Gentle bounce: up and back down, forever, while shown.
local bounce = holder:CreateAnimationGroup()
bounce:SetLooping("BOUNCE")
local up = bounce:CreateAnimation("Translation")
up:SetOffset(0, 10)
up:SetDuration(0.6)
up:SetSmoothing("IN_OUT")

local function Place()
	local p = PetWarnDB.pos
	f:ClearAllPoints()
	if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 160) end
end

local moving = false
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0.5, 1, 0.25)
bg:Hide()

local function ShowWarning(on)
	if on == f:IsShown() then return end
	if on then
		f:Show()
		bounce:Play()
	else
		bounce:Stop()
		f:Hide()
	end
end

------------------------------------------------------------------------
-- Checking (only while you're in a fight)
------------------------------------------------------------------------
local idleSince -- when the pet was first seen idle in this fight
local ticker

function PW.Check()
	if moving then return end
	if PW.ShouldWarn() then
		local now = GetTime()
		idleSince = idleSince or now
		ShowWarning(now - idleSince >= GRACE)
	else
		idleSince = nil
		ShowWarning(false)
	end
end

local function StartTicker()
	if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.2, PW.Check) end
end
local function StopTicker()
	if ticker then ticker:Cancel(); ticker = nil end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, unit)
	if event == "PLAYER_LOGIN" then
		local db = type(PetWarnDB) == "table" and PetWarnDB or {}
		PetWarnDB = db
		if db.enabled == nil then db.enabled = true end
		Place()
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PET_ATTACK_START")
		self:RegisterEvent("PET_ATTACK_STOP")
		self:RegisterEvent("PET_BAR_UPDATE")
		self:RegisterEvent("UNIT_PET")
		if Try(UnitAffectingCombat, "player") then StartTicker() end -- logged in / reloaded mid-fight
		return
	elseif event == "PET_ATTACK_START" then
		attackEvent = true
	elseif event == "PET_ATTACK_STOP" then
		attackEvent = false
	elseif event == "UNIT_PET" then
		if unit ~= "player" then return end
		attackEvent = false
	elseif event == "PLAYER_REGEN_DISABLED" then
		idleSince = nil
		StartTicker()
	elseif event == "PLAYER_REGEN_ENABLED" then
		StopTicker()
		idleSince = nil
		attackEvent = false
	end
	PW.Check()
end)

------------------------------------------------------------------------
-- /petwarn
------------------------------------------------------------------------
local function StopMoving()
	moving = false
	f:StopMovingOrSizing()
	f:EnableMouse(false)
	bg:Hide()
	local p1, _, p2, x, y = f:GetPoint()
	PetWarnDB.pos = { p1, p2, x, y }
	ShowWarning(false)
	PW.Check()
end

f:SetScript("OnMouseDown", function(self) if moving then self:StartMoving() end end)
f:SetScript("OnMouseUp", function(self) if moving then self:StopMovingOrSizing() end end)

SLASH_PETWARN1 = "/petwarn"
SlashCmdList.PETWARN = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local db = PetWarnDB
	if msg == "off" then
		db.enabled = false; PW.Check()
		Print("off. |cffffffff/petwarn on|r to turn it back on.")
	elseif msg == "on" then
		db.enabled = true; PW.Check()
		Print("on.")
	elseif msg == "move" then
		if moving then StopMoving(); Print("Position saved.") return end
		moving = true
		f:EnableMouse(true)
		bg:Show()
		ShowWarning(true)
		Print("Drag the warning where you want it, then type |cffffffff/petwarn move|r again to save.")
	elseif msg == "reset" then
		db.pos = nil; Place(); Print("Position reset to the middle of the screen.")
	elseif msg == "test" then
		if moving then return end
		ShowWarning(true)
		if C_Timer and C_Timer.After then C_Timer.After(4, PW.Check) end
		Print("This is what it looks like (hides in 4 seconds).")
	else
		Print(("is %s. Shows \"Pet not attacking\" when you're in a fight and your pet isn't."):format(db.enabled and "|cff20ff20on|r" or "|cffff4040off|r"))
		Print("|cffffffff/petwarn test|r  preview   |cffffffff/petwarn move|r  move it   |cffffffff/petwarn reset|r  centre it   |cffffffff/petwarn off|r / |cffffffffon|r")
	end
end
