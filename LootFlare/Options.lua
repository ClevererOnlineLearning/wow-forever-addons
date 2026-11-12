-- Loot Flare settings window + minimap button (no external libraries).
local LF = LootFlare
local function db() return LF.db end

------------------------------------------------------------------------
-- Window (two columns)
------------------------------------------------------------------------
local panel = CreateFrame("Frame", "LootFlareOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(610, 590)
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

local COLW = 280
local cx, y = 20, -46
local function Column(x) cx, y = x, -46 end

local function Header(text)
	local h = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h:SetPoint("TOPLEFT", cx + 2, y)
	h:SetText("|cffffd100" .. text .. "|r")
	y = y - 20
end

local function Check(label, get, set)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", cx, y)
	local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	t:SetText(label)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
	y = y - 24
end
local function Opt(label, key, after)
	Check(label, function() return db()[key] end, function(v) db()[key] = v; if after then after() end end)
end

-- "Label      [-] value [+]"
local function Stepper(label, get, change)
	local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("TOPLEFT", cx + 6, y - 5)
	t:SetText(label)
	local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	plus:SetSize(24, 22); plus:SetPoint("TOPLEFT", cx + COLW - 30, y); plus:SetText("+")
	local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	val:SetPoint("RIGHT", plus, "LEFT", -4, 0); val:SetWidth(84)
	local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	minus:SetSize(24, 22); minus:SetPoint("RIGHT", val, "LEFT", -4, 0); minus:SetText("-")
	local function show() val:SetText(get()) end
	plus:SetScript("OnClick", function() change(1); show() end)
	minus:SetScript("OnClick", function() change(-1); show() end)
	refreshers[#refreshers + 1] = show
	y = y - 28
end

local function Clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end
local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
local function QHex(q) return Hex(LF.QualityColor(q)) end

------------------------------------------------------------------------
-- Left column: what to show, how it looks
------------------------------------------------------------------------
Column(20)
Header("Show")
Opt("Loot Flare on", "enabled")
Opt("Items", "items")
Stepper("Items from", function()
	local q = db().minQuality
	return QHex(q) .. LF.QUALITY_NAMES[q] .. "|r"
end, function(d) db().minQuality = Clamp(db().minQuality + d, 0, 5) end)
Opt("Mark quest items, with your progress (3/8)", "quest")
Opt("Item level on gear", "ilvl")
Opt("\"Upgrade +5\" when gear beats what you wear", "upgrade")
local VENDOR = { { "off", "Off" }, { "grey", "Junk only" }, { "all", "Everything" } }
local function VendorIndex()
	for i, v in ipairs(VENDOR) do if v[1] == db().vendor then return i end end
	return 2
end
Stepper("Sell value", function() return VENDOR[VendorIndex()][2] end, function(d)
	local i = VendorIndex() + d
	if i < 1 then i = #VENDOR elseif i > #VENDOR then i = 1 end
	db().vendor = VENDOR[i][1]
end)
Opt("How many you now have, e.g. (23)", "bagCount")
Opt("Money", "money")
Opt("Currency", "currency")
Opt("Honor", "honor")

y = y - 6
Header("Look")
local function AnimIndex()
	for i, a in ipairs(LF.ANIMS) do if a.key == db().anim then return i end end
	return 1
end
Stepper("Animation", function() return LF.ANIMS[AnimIndex()].name end, function(d)
	local n = #LF.ANIMS
	local i = AnimIndex() + d
	if i < 1 then i = n elseif i > n then i = 1 end
	db().anim = LF.ANIMS[i].key
	LF.ApplyLook()
	LF.Test()
end)
Opt("Glow, shine and sparkles on rare and better", "fancy")
Opt("New lines push older ones upward", "growUp", function() LF.ApplyLook() end)
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

------------------------------------------------------------------------
-- Right column: sounds, minimap, tips
------------------------------------------------------------------------
Column(318)
Header("Sounds")
local function SoundIndex(id)
	for i, s in ipairs(LF.SOUNDS) do if s.id == id then return i end end
	return 1
end
local function SoundRow(key, label)
	local name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("TOPLEFT", cx + 6, y - 5)
	name:SetText(label)
	local play = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	play:SetSize(44, 22); play:SetPoint("TOPLEFT", cx + COLW - 50, y); play:SetText("Play")
	play:SetScript("OnClick", function() LF.PlaySoundID(db().sounds[key]) end)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(124, 22); b:SetPoint("RIGHT", play, "LEFT", -4, 0)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local function show() b:SetText(LF.SOUNDS[SoundIndex(db().sounds[key])].name) end
	b:SetScript("OnClick", function(_, button)
		local n = #LF.SOUNDS
		local i = SoundIndex(db().sounds[key]) + (button == "RightButton" and -1 or 1)
		if i < 1 then i = n elseif i > n then i = 1 end
		db().sounds[key] = LF.SOUNDS[i].id
		show()
		LF.PlaySoundID(db().sounds[key])
	end)
	refreshers[#refreshers + 1] = show
	y = y - 26
end
for q = 2, 5 do SoundRow(q, QHex(q) .. LF.QUALITY_NAMES[q] .. "|r") end
SoundRow("quest", Hex(1, 0.82, 0) .. "Quest item|r")
local sh = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sh:SetPoint("TOPLEFT", cx + 6, y - 2)
sh:SetWidth(COLW - 10)
sh:SetJustifyH("LEFT")
sh:SetText("Click a sound to change it, right-click to go back.")
y = y - 22

Header("Big banner")
Opt("Banner across the screen for great drops", "banner")
Stepper("Banner from", function()
	local q = db().bannerMin
	return QHex(q) .. LF.QUALITY_NAMES[q] .. "|r"
end, function(d) db().bannerMin = Clamp(db().bannerMin + d, 3, 5) end)
Opt("Glow around the screen edge too", "edgeGlow")

y = y - 4
Header("Gold per hour")
Opt("Show the gold-per-hour box", "gph", function() LF.ApplyGold() end)
Opt("Start over each time I log in", "gphLoginReset")
do
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(110, 22); b:SetPoint("TOPLEFT", cx + 6, y)
	b:SetText("Start over now")
	b:SetScript("OnClick", function() LF.ResetGold() end)
	y = y - 28
end

y = y - 4
Header("Other")
Check("Show minimap button", function() return not db().minimap.hide end, function(v)
	db().minimap.hide = not v
	LF.UpdateMinimapButton()
end)
local tips = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tips:SetPoint("TOPLEFT", cx + 6, y - 4)
tips:SetWidth(COLW - 10)
tips:SetJustifyH("LEFT")
tips:SetText("/lflare test, on, off, move, reset")

-- Bottom buttons
local move = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
move:SetSize(96, 24)
move:SetPoint("BOTTOMLEFT", 22, 20)
move:SetScript("OnClick", function()
	db().locked = not db().locked
	LF.ApplyLook()
	move:SetText(db().locked and "Move" or "Lock")
end)
refreshers[#refreshers + 1] = function() move:SetText(db().locked and "Move" or "Lock") end

local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
test:SetSize(96, 24)
test:SetPoint("BOTTOM", 0, 20)
test:SetText("Test")
test:SetScript("OnClick", function() LF.Test() end)

local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
reset:SetSize(96, 24)
reset:SetPoint("BOTTOMRIGHT", -22, 20)
reset:SetText("Reset pos.")
reset:SetScript("OnClick", function() LF.ResetPosition() end)

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

mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		db().minimap.angle = math.deg(atan2(py / s - my, px / s - mx))
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
