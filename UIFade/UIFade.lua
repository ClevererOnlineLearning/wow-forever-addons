-- UI Fade: sets the opacity of UIParent (the whole interface). The 3D world, and things the
-- game draws on the world (nameplates, floating names), are not part of UIParent.
local MIN, MAX = 20, 100 -- never below 20% so you can always still see the window to undo it

UIFadeDB = UIFadeDB or {}
local db
local pending = false

local function Clamp(v)
	v = math.floor((tonumber(v) or 100) / 5 + 0.5) * 5
	return math.max(MIN, math.min(MAX, v))
end

local function Apply()
	if not db then return end
	local a = db.on and db.level / 100 or 1
	if not pcall(UIParent.SetAlpha, UIParent, a) then pending = true end -- retried after a fight
end

local function Say(msg) print("|cff88ccffUI Fade:|r " .. msg) end

local frame -- settings window, made below
local function Refresh() if frame and frame:IsShown() then frame.Update() end end

function UIFade_Toggle()
	db.on = not db.on
	Apply(); Refresh()
	Say(db.on and ("faded to %d%%."):format(db.level) or "full brightness.")
end

local function SetLevel(v)
	db.level = Clamp(v); db.on = db.level < 100
	Apply(); Refresh()
end

-- Settings window -------------------------------------------------------------------------
frame = CreateFrame("Frame", "UIFadeFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(280, 170)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
if frame.SetBackdrop then
	frame:SetBackdrop({
		bgFile = "Interface\DialogFrame\UI-DialogBox-Background",
		edgeFile = "Interface\DialogFrame\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
end
-- The fade must not hide its own controls: this window and the minimap button stay fully visible.
if frame.SetIgnoreParentAlpha then frame:SetIgnoreParentAlpha(true) end
frame:SetAlpha(1)
frame:Hide()
tinsert(UISpecialFrames, "UIFadeFrame") -- Escape closes it

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18); title:SetText("UI Fade")
CreateFrame("Button", nil, frame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)

local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetPoint("TOP", 0, -48)

local slider = CreateFrame("Slider", "UIFadeSlider", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
slider:SetOrientation("HORIZONTAL")
slider:SetSize(220, 17)
slider:SetPoint("TOP", 0, -70)
slider:SetHitRectInsets(0, 0, -10, -10)
if slider.SetBackdrop then
	slider:SetBackdrop({
		bgFile = "Interface\Buttons\UI-SliderBar-Background",
		edgeFile = "Interface\Buttons\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
end
slider:SetThumbTexture("Interface\Buttons\UI-SliderBar-Button-Horizontal")
slider:SetMinMaxValues(MIN, MAX)
slider:SetValueStep(5)
if slider.SetObeyStepDuringDrag then slider:SetObeyStepDuringDrag(true) end
local lo = slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); lo:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2); lo:SetText(MIN .. "%")
local hi = slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hi:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2); hi:SetText(MAX .. "%")

local toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
toggle:SetSize(140, 22); toggle:SetPoint("TOP", 0, -104)

local mmChk = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
mmChk:SetSize(24, 24); mmChk:SetPoint("BOTTOMLEFT", 18, 16)
local mmText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mmText:SetPoint("LEFT", mmChk, "RIGHT", 2, 0); mmText:SetText("Show minimap button")

local updating = false
function frame.Update()
	updating = true
	slider:SetValue(db.level)
	updating = false
	label:SetText(("Visible: %d%%%s"):format(db.level, db.on and "" or "  (off, full brightness now)"))
	toggle:SetText(db.on and "Full brightness" or "Fade")
	mmChk:SetChecked(not db.minimap.hide)
end

slider:SetScript("OnValueChanged", function(_, v)
	if updating then return end
	db.level = Clamp(v); db.on = true -- moving the slider shows the result straight away
	Apply(); frame.Update()
end)
toggle:SetScript("OnClick", function() UIFade_Toggle() end)
frame:SetScript("OnShow", function() frame.Update() end)

-- Minimap button --------------------------------------------------------------------------
-- Left-click: the slider window. Right-click: fade on/off. Mouse wheel: 5% up or down. Drag: move.
local mm = CreateFrame("Button", "UIFadeMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:EnableMouseWheel(true)
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetSize(20, 20); mmBg:SetPoint("TOPLEFT", 7, -5)
local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetTexture("Interface\\Icons\\Spell_Holy_MindVision")
mmIcon:SetSize(17, 17); mmIcon:SetPoint("TOPLEFT", 7, -6)
mmIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53); mmBorder:SetPoint("TOPLEFT")

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function PlaceButton()
	local a = math.rad(db.minimap.angle or 195)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
local function UpdateButton()
	if db.minimap.hide then mm:Hide() else PlaceButton(); mm:Show() end
end

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("UI Fade")
	GameTooltip:AddLine(db.on and ("Faded: %d%% visible"):format(db.level) or "Full brightness", 1, 1, 1)
	GameTooltip:AddLine("|cffffffffLeft-click|r  slider", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r  fade on/off", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffMouse wheel|r  5% up or down", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		db.minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
		PlaceButton()
	end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnClick", function(self, button)
	if button == "RightButton" then
		UIFade_Toggle()
	elseif frame:IsShown() then
		frame:Hide()
	else
		frame:ClearAllPoints()
		frame:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 0, 0) -- opens next to the button
		frame:Show()
	end
	Tooltip(self)
end)
mm:SetScript("OnMouseWheel", function(self, delta)
	SetLevel((db.on and db.level or 100) + delta * 5)
	Tooltip(self)
end)
mm:SetScript("OnEnter", Tooltip)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
if mm.SetIgnoreParentAlpha then mm:SetIgnoreParentAlpha(true) end
mm:SetAlpha(1)
mm:Hide()

mmChk:SetScript("OnClick", function(self)
	db.minimap.hide = not self:GetChecked()
	UpdateButton()
	if db.minimap.hide then Say("minimap button hidden. /uifade minimap brings it back.") end
end)

-- Events ----------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		db = UIFadeDB
		db.level = Clamp(db.level or 80)
		if db.on == nil then db.on = false end
		db.on = db.on and true or false
		if type(db.minimap) ~= "table" then db.minimap = { angle = 195, hide = false } end
		UpdateButton()
	end
	if event ~= "PLAYER_REGEN_ENABLED" or pending then pending = false; Apply() end
end)

BINDING_NAME_UIFADE_TOGGLE = "Toggle UI fade"

-- Slash command ---------------------------------------------------------------------------
SLASH_UIFADE1 = "/uifade"
SlashCmdList.UIFADE = function(msg)
	msg = (msg or ""):lower():gsub("%%", ""):match("^%s*(.-)%s*$")
	local n = tonumber(msg)
	if n then
		SetLevel(n)
		Say(("set to %d%% visible."):format(db.level))
	elseif msg == "on" then db.on = true; Apply(); Refresh(); Say(("faded to %d%%."):format(db.level))
	elseif msg == "off" then db.on = false; Apply(); Refresh(); Say("full brightness.")
	elseif msg == "toggle" then UIFade_Toggle()
	elseif msg == "minimap" then
		db.minimap.hide = not db.minimap.hide; UpdateButton(); Refresh()
		Say(db.minimap.hide and "minimap button hidden." or "minimap button shown.")
	elseif msg == "" then
		if not frame:IsShown() then frame:ClearAllPoints(); frame:SetPoint("CENTER") end
		frame:SetShown(not frame:IsShown())
	else
		Say("/uifade opens the window. /uifade 70 = 70% visible. /uifade on | off | toggle | minimap.")
	end
end
