-- Gun Silencer settings window + minimap button (no external libraries).
local GS = GunSilencer

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local panel = CreateFrame("Frame", "GunSilencerOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(300, 330)
panel:SetPoint("CENTER", 0, 40)
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetClampedToScreen(true)
if panel.SetBackdrop then
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
end
panel:Hide()
tinsert(UISpecialFrames, "GunSilencerOptionsFrame")

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Gun Silencer")

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local refreshers = {}
local function RefreshAll() for _, f in ipairs(refreshers) do f() end end
panel:SetScript("OnShow", RefreshAll)

local y = -48
local function Check(label, get, set)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", 20, y)
	local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	t:SetText(label)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
	y = y - 24
end

local function Row(label)
	local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("TOPLEFT", 26, y - 5)
	t:SetText(label)
end

-- Button cycling through {value, text} choices. playAfter = preview the new sound.
local function Cycle(label, choices, get, set, playAfter)
	Row(label)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(150, 22)
	b:SetPoint("TOPRIGHT", -24, y)
	local function textFor(v)
		for _, c in ipairs(choices) do if c[1] == v then return c[2] end end
		return choices[1][2]
	end
	b:SetScript("OnClick", function(self, button)
		local cur, idx = get(), 1
		for i, c in ipairs(choices) do if c[1] == cur then idx = i end end
		local step = (button == "RightButton") and -1 or 1
		set(choices[(idx - 1 + step) % #choices + 1][1])
		b:SetText(textFor(get()))
		if playAfter then GS.Test() end
	end)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	refreshers[#refreshers + 1] = function() b:SetText(textFor(get())) end
	y = y - 28
end

local function Stepper(label, minV, maxV, step, get, set, fmt)
	Row(label)
	local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	plus:SetSize(24, 22); plus:SetPoint("TOPRIGHT", -24, y); plus:SetText("+")
	local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	val:SetPoint("RIGHT", plus, "LEFT", -6, 0); val:SetWidth(60)
	local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	minus:SetSize(24, 22); minus:SetPoint("RIGHT", val, "LEFT", -6, 0); minus:SetText("-")
	local function show() val:SetText(fmt(get())) end
	local function bump(d)
		local v = math.floor((math.min(maxV, math.max(minV, get() + d))) * 10 + 0.5) / 10
		set(v); show()
	end
	plus:SetScript("OnClick", function() bump(step) end)
	minus:SetScript("OnClick", function() bump(-step) end)
	refreshers[#refreshers + 1] = show
	y = y - 28
end

local function db() return GS.db end

Check("Silence guns (mute default gun sounds)", function() return db().enabled end, function(v) GS.SetEnabled(v) end)
Check("Play reload sound after each shot", function() return db().reload end, function(v) db().reload = v end)
y = y - 6

Cycle("Sound pack", GS.PACKS, function() return db().pack end, function(v) db().pack = v end, true)

local volChoices = {}
for _, v in ipairs(GS.VOLUMES) do volChoices[#volChoices + 1] = { v, v .. "%" } end
Cycle("Volume  (right-click: back)", volChoices, function() return db().volume end, function(v) db().volume = v end, true)

Cycle("Sound channel", GS.CHANNELS, function() return db().channel end, function(v) db().channel = v end, true)

Stepper("Reload delay", 0.2, 1.5, 0.1, function() return tonumber(db().reloadDelay) or 0.5 end,
	function(v) db().reloadDelay = v end, function(v) return string.format("%.1fs", v) end)

y = y - 4
Check("Show minimap button", function() return not db().minimap.hide end, function(v)
	db().minimap.hide = not v
	GS.UpdateMinimapButton()
end)

local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
note:SetPoint("TOPLEFT", 26, y - 4)
note:SetWidth(250)
note:SetJustifyH("LEFT")
note:SetText("Volume is also affected by the game's slider for the chosen channel.")

local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
test:SetSize(120, 24)
test:SetPoint("BOTTOMLEFT", 24, 20)
test:SetText("Test shot")
test:SetScript("OnClick", function() GS.Test() end)

local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOMRIGHT", -26, 26)
refreshers[#refreshers + 1] = function()
	status:SetText(GS.HasGun() and "|cff00ff00Gun equipped|r" or "|cffff8040No gun equipped|r")
end

function GS.ToggleOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local mm = CreateFrame("Button", "GunSilencerMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local bg = mm:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetSize(20, 20)
bg:SetPoint("TOPLEFT", 7, -5)

local icon = mm:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\INV_Weapon_Rifle_01")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

local border = mm:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")

local atan2 = math.atan2 or function(yv, xv) return math.atan(yv, xv) end

local function PlaceButton()
	local a = math.rad(db().minimap.angle or 190)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function GS.UpdateMinimapButton()
	if db().minimap.hide then mm:Hide() else PlaceButton(); mm:Show() end
end

mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		db().minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
		PlaceButton()
	end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

mm:SetScript("OnClick", function(self, button)
	if button == "RightButton" then GS.Test() else GS.ToggleOptions() end
end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Gun Silencer")
	local d = db()
	GameTooltip:AddLine((d.enabled and "|cff00ff00On|r" or "|cffff0000Off|r") .. "  -  " .. d.volume .. "%", 1, 1, 1)
	GameTooltip:AddLine("|cffffffffLeft-click|r  settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r  test shot", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
mm:Hide()
