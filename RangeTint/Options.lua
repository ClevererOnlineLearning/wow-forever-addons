-- RangeTint settings window (flat look from Skin.lua) and minimap button.
local _, ns = ...
local S = ns.Skin
local RT = RangeTint
local function db() return RT.db end

local W = 400
local CW = W - 24
local L = 14
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local win = S.Window("RangeTintFrame", "RangeTint", "Interface\\Icons\\Ability_Marksmanship",
	GetMeta and GetMeta("RangeTint", "Version"), W, 420)
local more = S.MoreButton(win.head, "RangeTint", win)
more:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
local onChk = S.Check(win.head, "On")
onChk:SetPoint("RIGHT", more, "LEFT", -34, 0)
onChk:SetScript("OnClick", function(self) db().enabled = self:GetChecked() and true or false; RT.TargetChanged() end)

local refreshers = {}
local function R(f) refreshers[#refreshers + 1] = f end
local function RefreshAll() onChk:SetChecked(db().enabled); for _, f in ipairs(refreshers) do f() end end
win:SetScript("OnShow", RefreshAll)

-- Opens the game's colour picker for one of the colours.
local function PickColor(key, after)
	local c = db().colors[key]
	local old = { c[1], c[2], c[3] }
	local function Save(r, g, b) db().colors[key] = { r, g, b }; after(); RT.UpdateAll() end
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

local c1 = S.Card(win, "Colours", 12, -44, CW)
local ROWS = {
	{ "red", "Out of range" },
	{ "orange", "In range, but close to the edge" },
	{ "purple", "Too close (inside a shot's minimum range)" },
	{ "blue", "Not enough mana" },
}
for _, row in ipairs(ROWS) do
	local key = row[1]
	local y = S.Row(c1, 30)
	local sw = CreateFrame("Button", nil, c1)
	sw:SetSize(40, 18)
	sw:SetPoint("TOPLEFT", L, y - 3)
	S.Border(sw, 0, 0, 0, 1)
	local tex = sw:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
	local hl = sw:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.25)
	local function paint() local c = db().colors[key]; tex:SetColorTexture(c[1], c[2], c[3], 1) end
	sw:SetScript("OnClick", function() PickColor(key, paint) end)
	S.Tip(sw, "Click to pick your own colour")
	local cb = S.Check(c1, row[2], L + 52, y)
	cb:SetScript("OnClick", function(self) db()[key] = self:GetChecked() and true or false; RT.UpdateAll() end)
	R(function() paint(); cb:SetChecked(db()[key]) end)
end
local y = S.Row(c1, 30)
R(S.Stepper(c1, "Orange when within", L, y, CW - 2 * L, function() return db().margin .. " yards of the edge" end,
	function(d) db().margin = math.min(20, math.max(3, db().margin + d)); RT.UpdateAll() end))
y = S.Row(c1, 54)
S.Note(c1, "The game only tells add-ons \"in range: yes or no\", never the distance. RangeTint narrows the distance down "
	.. "from all your spells' answers, so orange and purple show wherever there's a check close enough. "
	.. "Hunters: shots at 41 yards and Sniper Shot at 51 give an orange \"near the edge\" for Sniper Shot.", L, y, CW - 2 * L)
S.Fit(c1, 8)

local foot = S.Footer(win, 40)
local mm = S.Check(foot, "Show minimap button")
mm:SetPoint("LEFT", 14, 0)
mm:SetScript("OnClick", function(self) db().minimap.hide = not self:GetChecked(); RT.UpdateMinimapButton() end)
R(function() mm:SetChecked(not db().minimap.hide) end)
local test = S.Button(foot, "Test colours", 110, 24, true)
test:SetPoint("RIGHT", -12, 0)
test:SetScript("OnClick", function() RT.Test() end)
S.Tip(test, "Test colours", "Shows each colour on your buttons for a moment: red, orange, purple, blue.")
win:SetHeight(-S.Below(c1) + 40 + 2)

function RT.ToggleOptions() win:SetShown(not win:IsShown()) end

------------------------------------------------------------------------
-- Minimap button: left-click settings, right-click on/off, drag to move
------------------------------------------------------------------------
local btn = CreateFrame("Button", "RangeTintMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\Ability_Marksmanship")
icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53); border:SetPoint("TOPLEFT")
btn:Hide()

local atan2 = math.atan2 or function(a, b) return math.atan(a, b) end
local function Place()
	local a = math.rad(db().minimap.angle or 250)
	local r = (Minimap:GetWidth() / 2) + 5
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
function RT.UpdateMinimapButton()
	if db().minimap.hide then btn:Hide() else Place(); btn:Show() end
	icon:SetDesaturated(not db().enabled)
end
S.Group(btn, "RangeTint", function() return db().minimap end, RT.UpdateMinimapButton) -- the shared minimap bag
btn:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		db().minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
		Place()
	end)
end)
btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
local function Tip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("RangeTint")
	GameTooltip:AddLine(db().enabled and "|cff33ff33On|r" or "|cffff4040Off|r", 1, 1, 1)
	GameTooltip:AddLine("|cffffffffLeft-click|r  settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r  on/off", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end
btn:SetScript("OnClick", function(self, b)
	if b == "RightButton" then
		db().enabled = not db().enabled
		RT.TargetChanged()
		RT.UpdateMinimapButton()
		if win:IsShown() then RefreshAll() end
	else
		RT.ToggleOptions()
	end
	Tip(self)
end)
btn:SetScript("OnEnter", Tip)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
