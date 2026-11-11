-- SLoTe settings window + minimap button (no external libraries).
local SLoTe = SLoTe
local Opt = SLoTe.Opt

local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic" }
local QUALITY_HEX   = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee" }

local function SetOpt(k, v) SLoTeOptions[k] = v; SLoTe.Apply() end
local function Round1(v) return math.floor(v * 10 + 0.5) / 10 end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local panel = CreateFrame("Frame", "SLoTeOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(300, 545)
panel:SetPoint("CENTER")
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
tinsert(UISpecialFrames, "SLoTeOptionsFrame") -- Escape closes it

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Scrolling Loot Text")

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local refreshers = {}
local function RefreshAll() for _, f in ipairs(refreshers) do f() end end
panel:SetScript("OnShow", RefreshAll)

local y = -48
local function Header(text)
	local h = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h:SetPoint("TOPLEFT", 22, y)
	h:SetText("|cffffd100" .. text .. "|r")
	y = y - 20
end

local function Check(label, get, set)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", 20, y)
	local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	t:SetText(label)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
	y = y - 22
	return cb
end

local function Row(label)
	local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("TOPLEFT", 26, y - 5)
	t:SetText(label)
	return t
end

-- Button that cycles through a list of {value, text} choices.
local function Cycle(label, choices, get, set)
	Row(label)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(130, 22)
	b:SetPoint("TOPRIGHT", -24, y)
	local function textFor(v)
		for _, c in ipairs(choices) do if c[1] == v then return c[2] end end
		return choices[1][2]
	end
	b:SetScript("OnClick", function()
		local cur, idx = get(), 1
		for i, c in ipairs(choices) do if c[1] == cur then idx = i end end
		set(choices[idx % #choices + 1][1])
		b:SetText(textFor(get()))
	end)
	refreshers[#refreshers + 1] = function() b:SetText(textFor(get())) end
	y = y - 26
	return b
end

-- [-] value [+] stepper.
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
		local v = Round1(math.min(maxV, math.max(minV, get() + d)))
		set(v); show()
	end
	plus:SetScript("OnClick", function() bump(step) end)
	minus:SetScript("OnClick", function() bump(-step) end)
	refreshers[#refreshers + 1] = show
	y = y - 26
end

-- Display
Header("Show")
Check("Item icons", function() return DisplayIcons ~= 0 end, function(v) DisplayIcons = v and 1 or 0 end)
Check("Bag count after name, e.g. (14)", function() return Opt("showCount") end, function(v) SetOpt("showCount", v) end)
Check("Rare & Epic loot pops up bigger", function() return Opt("bigRare") end, function(v) SetOpt("bigRare", v) end)
Check("Money", function() return ShowM == 1 end, function(v) ShowM = v and 1 or 0 end)
Check("Currency", function() return ShowC == 1 end, function(v) ShowC = v and 1 or 0 end)
Check("Honor", function() return ShowH == 1 end, function(v) ShowH = v and 1 or 0 end)
Check("Hide Blizzard loot window", function() return ShowL == 0 end, function(v) ShowL = v and 0 or 1 end)
Cycle("Minimum item quality", {
	{ 0, "|c" .. QUALITY_HEX[0] .. "Poor (all)|r" }, { 1, "|c" .. QUALITY_HEX[1] .. "Common+|r" },
	{ 2, "|c" .. QUALITY_HEX[2] .. "Uncommon+|r" }, { 3, "|c" .. QUALITY_HEX[3] .. "Rare+|r" },
	{ 4, "|c" .. QUALITY_HEX[4] .. "Epic+|r" },
}, function() return tonumber(Opt("minQuality")) or 0 end, function(v) SetOpt("minQuality", v) end)

y = y - 6
Header("Motion")
Cycle("Movement", { { "arc", "Arc" }, { "straight", "Straight up" } },
	function() return FloatMode end, function(v) FloatMode = v end)
Cycle("Arc direction", { { "alt", "Alternate" }, { "right", "Right" }, { "left", "Left" } },
	function() return Opt("arcDir") end, function(v) SetOpt("arcDir", v) end)
Cycle("Fade", { { "end", "At the end" }, { "smooth", "Smooth" } },
	function() return FadeMode end, function(v) FadeMode = v end)

y = y - 6
Header("Size & timing")
Stepper("Size", 0.3, 2.0, 0.1, function() return tonumber(Scale) or 1 end,
	function(v) Scale = tostring(v); SLoTe.Apply() end, function(v) return string.format("%.1fx", v) end)
Stepper("Time on screen", 1.5, 6.0, 0.5, function() return tonumber(Opt("duration")) or 3 end,
	function(v) SetOpt("duration", v) end, function(v) return string.format("%.1fs", v) end)
Stepper("Start height", -200, 300, 20, function() return tonumber(Opt("yOffset")) or 80 end,
	function(v) SetOpt("yOffset", v) end, function(v) return string.format("%d", v) end)

y = y - 4
local mmCheck = Check("Show minimap button", function() return not SLoTeOptions.minimap.hide end, function(v)
	SLoTeOptions.minimap.hide = not v
	if SLoTe.UpdateMinimapButton then SLoTe.UpdateMinimapButton() end
end)

-- Sample loot showcase
local function Preview()
	local show = SLoTe.Show
	local samples = {
		{ "Interface\\Icons\\INV_Misc_Bone_01", "Broken Fang", 0 },
		{ "Interface\\Icons\\INV_Fabric_Linen_01", "3 x Linen Cloth", 1 },
		{ "Interface\\Icons\\INV_Sword_04", "Gleaming Blade", 2 },
		{ "Interface\\Icons\\INV_Misc_Gem_Sapphire_02", "Star of the Deep", 3 },
		{ "Interface\\Icons\\INV_Sword_39", "Thunderfury Replica", 4 },
	}
	local minQ = tonumber(Opt("minQuality")) or 0
	local i = 0
	for _, s in ipairs(samples) do
		if s[3] >= minQ then
			local hex = QUALITY_HEX[s[3]]
			local r = tonumber(hex:sub(3, 4), 16) / 255
			local g = tonumber(hex:sub(5, 6), 16) / 255
			local b = tonumber(hex:sub(7, 8), 16) / 255
			local text = s[2] .. (Opt("showCount") and " |cffaaaaaa(" .. (i + 1) * 4 .. ")|r" or "")
			local big = Opt("bigRare") and s[3] >= 3
			C_Timer.After(i * 0.35, function() show(s[1], text, r, g, b, big) end)
			i = i + 1
		end
	end
	C_Timer.After(i * 0.35, function() show("Interface\\MoneyFrame\\UI-GoldIcon", "2 Gold, 15 Silver", 1, 1, 1) end)
end
SLoTe.Preview = Preview

local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
test:SetSize(120, 24)
test:SetPoint("BOTTOMLEFT", 24, 20)
test:SetText("Preview")
test:SetScript("OnClick", Preview)

local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
reset:SetSize(120, 24)
reset:SetPoint("BOTTOMRIGHT", -24, 20)
reset:SetText("Reset defaults")
reset:SetScript("OnClick", function()
	local mm = SLoTeOptions.minimap
	for k in pairs(SLoTeOptions) do SLoTeOptions[k] = nil end
	SLoTeOptions.minimap = mm
	Scale, FloatMode, FadeMode, DisplayIcons = "1.0", "arc", "end", 1
	ShowM, ShowC, ShowH, ShowL = 1, 1, 1, 1
	SLoTe.Apply()
	RefreshAll()
end)

function SLoTe.ToggleOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local mm = CreateFrame("Button", "SLoTeMinimapButton", Minimap)
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
icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

local border = mm:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")

local atan2 = math.atan2 or function(yv, xv) return math.atan(yv, xv) end

local function PlaceButton()
	local a = math.rad(SLoTeOptions.minimap.angle or 215)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function SLoTe.UpdateMinimapButton()
	if SLoTeOptions.minimap.hide then mm:Hide() else PlaceButton(); mm:Show() end
end

mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		SLoTeOptions.minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
		PlaceButton()
	end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

mm:SetScript("OnClick", function(self, button)
	if button == "RightButton" then Preview() else SLoTe.ToggleOptions() end
end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Scrolling Loot Text")
	GameTooltip:AddLine("|cffffffffLeft-click|r  settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r  preview", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
mm:Hide()

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
	SLoTeOptions = SLoTeOptions or {}
	if type(SLoTeOptions.minimap) ~= "table" then
		SLoTeOptions.minimap = { angle = 215, hide = false }
	end
	SLoTe.UpdateMinimapButton()
end)
