-- Loot Flare settings window + minimap button (no external libraries).
local LF = LootFlare
local function db() return LF.db end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local panel = CreateFrame("Frame", "LootFlareOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(330, 625)
panel:SetPoint("CENTER", 0, 30)
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
tinsert(UISpecialFrames, "LootFlareOptionsFrame")

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Loot Flare")

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local refreshers = {}
local function RefreshAll() for _, f in ipairs(refreshers) do f() end end
panel:SetScript("OnShow", RefreshAll)

local y = -46
local function Header(text)
	local h = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h:SetPoint("TOPLEFT", 22, y)
	h:SetText("|cffffd100" .. text .. "|r")
	y = y - 20
end

local function Check(label, key, after)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", 20, y)
	local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	t:SetText(label)
	cb:SetScript("OnClick", function(self)
		db()[key] = self:GetChecked() and true or false
		if after then after() end
	end)
	refreshers[#refreshers + 1] = function() cb:SetChecked(db()[key]) end
	y = y - 24
end

-- "Label      [-] value [+]"
local function Stepper(label, get, change)
	local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("TOPLEFT", 26, y - 5)
	t:SetText(label)
	local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	plus:SetSize(24, 22); plus:SetPoint("TOPRIGHT", -24, y); plus:SetText("+")
	local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	val:SetPoint("RIGHT", plus, "LEFT", -6, 0); val:SetWidth(90)
	local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	minus:SetSize(24, 22); minus:SetPoint("RIGHT", val, "LEFT", -6, 0); minus:SetText("-")
	local function show() val:SetText(get()) end
	plus:SetScript("OnClick", function() change(1); show() end)
	minus:SetScript("OnClick", function() change(-1); show() end)
	refreshers[#refreshers + 1] = show
	y = y - 28
end

local function Clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end
local function Hex(q) local r, g, b = LF.QualityColor(q); return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end

Header("Show")
Check("Loot Flare on", "enabled")
Check("Items", "items")
Stepper("Items from", function()
	local q = db().minQuality
	return Hex(q) .. LF.QUALITY_NAMES[q] .. "|r"
end, function(d) db().minQuality = Clamp(db().minQuality + d, 0, 5) end)
Check("Money", "money")
Check("Currency", "currency")
Check("Honor", "honor")
Check("How many you now have, e.g. (23)", "bagCount")

y = y - 4
Header("Look")
Check("Glow, shine and sparkles on rare and better", "fancy")
Check("New lines push older ones upward", "growUp", function() LF.ApplyLook() end)
Stepper("Size", function() return string.format("%.1fx", db().scale) end, function(d)
	db().scale = math.floor(Clamp(db().scale + d * 0.1, 0.5, 2.5) * 10 + 0.5) / 10
	LF.ApplyLook()
end)
Stepper("Time on screen", function() return db().duration .. " sec" end, function(d)
	db().duration = Clamp(db().duration + d * 0.5, 1.5, 12)
end)
Stepper("Most lines at once", function() return tostring(db().maxLines) end, function(d)
	db().maxLines = Clamp(db().maxLines + d, 2, 15)
end)

y = y - 4
Header("Sounds (click to change, right-click to go back)")
local function SoundIndex(id)
	for i, s in ipairs(LF.SOUNDS) do if s.id == id then return i end end
	return 1
end
for q = 2, 5 do
	local name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("TOPLEFT", 26, y - 5)
	name:SetText(Hex(q) .. LF.QUALITY_NAMES[q] .. "|r")
	local play = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	play:SetSize(48, 22); play:SetPoint("TOPRIGHT", -24, y); play:SetText("Play")
	play:SetScript("OnClick", function() LF.PlaySoundID(db().sounds[q]) end)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(130, 22); b:SetPoint("RIGHT", play, "LEFT", -4, 0)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local function show() b:SetText(LF.SOUNDS[SoundIndex(db().sounds[q])].name) end
	b:SetScript("OnClick", function(_, button)
		local n = #LF.SOUNDS
		local i = SoundIndex(db().sounds[q]) + (button == "RightButton" and -1 or 1)
		if i < 1 then i = n elseif i > n then i = 1 end
		db().sounds[q] = LF.SOUNDS[i].id
		show()
		LF.PlaySoundID(db().sounds[q])
	end)
	refreshers[#refreshers + 1] = show
	y = y - 26
end

-- Bottom buttons
local move = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
move:SetSize(86, 24)
move:SetPoint("BOTTOMLEFT", 22, 20)
move:SetScript("OnClick", function()
	db().locked = not db().locked
	LF.ApplyLook()
	move:SetText(db().locked and "Move" or "Lock")
end)
refreshers[#refreshers + 1] = function() move:SetText(db().locked and "Move" or "Lock") end

local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
test:SetSize(86, 24)
test:SetPoint("BOTTOM", 0, 20)
test:SetText("Test")
test:SetScript("OnClick", function() LF.Test() end)

local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
reset:SetSize(86, 24)
reset:SetPoint("BOTTOMRIGHT", -22, 20)
reset:SetText("Reset pos.")
reset:SetScript("OnClick", function() LF.ResetPosition() end)

local mmCheckY = y - 4
function LF.ToggleOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local mm = CreateFrame("Button", "LootFlareMinimapButton", Minimap)
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
icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Pearl_04")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

local border = mm:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")

local atan2 = math.atan2 or function(yv, xv) return math.atan(yv, xv) end

local function PlaceButton()
	local a = math.rad(db().minimap.angle or 200)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function LF.UpdateMinimapButton()
	if db().minimap.hide then mm:Hide() else PlaceButton(); mm:Show() end
end

-- the minimap-button checkbox sits under the sounds
do
	y = mmCheckY
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", 20, y)
	local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	t:SetText("Show minimap button")
	cb:SetScript("OnClick", function(self) db().minimap.hide = not self:GetChecked(); LF.UpdateMinimapButton() end)
	refreshers[#refreshers + 1] = function() cb:SetChecked(not db().minimap.hide) end
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
	if button == "RightButton" then LF.Test() else LF.ToggleOptions() end
end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Loot Flare")
	GameTooltip:AddLine("|cffffffffLeft-click|r  settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r  test", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
mm:Hide()
