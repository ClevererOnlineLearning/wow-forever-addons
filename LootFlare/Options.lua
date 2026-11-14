-- Loot Flare settings window (tabs + cards) and minimap button.
local _, ns = ...
local S = ns.Skin
local LF = LootFlare
local function db() return LF.db end

local W, H = 470, 476
local CW = W - 24 -- card width
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = GetMeta and GetMeta("LootFlare", "Version")
local panel = S.Window("LootFlareOptionsFrame", "Loot Flare", "Interface\\Icons\\INV_Misc_Gem_Pearl_04", version, W, H)

local refreshers = {}
local function R(f) refreshers[#refreshers + 1] = f end
local function RefreshAll() for _, f in ipairs(refreshers) do f() end end
panel:SetScript("OnShow", RefreshAll)

local function Clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end
local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
local function QName(q) return Hex(LF.QualityColor(q)) .. LF.QUALITY_NAMES[q] .. "|r" end
local function Cycle(list, cur, d)
	local i = 1
	for k, v in ipairs(list) do if v == cur then i = k end end
	i = i + d
	if i < 1 then i = #list elseif i > #list then i = 1 end
	return list[i]
end

-- tick box bound to a setting, placed at (x, y) inside a card
local function Opt(card, label, key, x, y, after, tip)
	local c = S.Check(card, label, x, y)
	c:SetScript("OnClick", function(self) db()[key] = self:GetChecked() and true or false; if after then after() end end)
	R(function() c:SetChecked(db()[key]) end)
	if tip then S.Tip(c, label, tip) end
	return c
end

-- master on/off in the title bar
local more = S.MoreButton(panel.head, "LootFlare", panel)
more:SetPoint("RIGHT", panel.close, "LEFT", -8, 0)
local onChk = S.Check(panel.head, "On")
onChk:SetPoint("RIGHT", more, "LEFT", -34, 0)
onChk:SetScript("OnClick", function(self) db().enabled = self:GetChecked() and true or false end)
R(function() onChk:SetChecked(db().enabled) end)
S.Tip(onChk, "Loot Flare on", "Untick to stop showing loot (settings are kept).")

local pages = S.Tabs(panel, { "Display", "Look", "Alerts", "Gold & more" }, -38, 41)
local L = 14         -- left column x inside a card
local M = CW / 2 + 6 -- right column x

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------
do
	local p = pages[1]
	local c = S.Card(p, "What to show", 12, -12, CW)
	local y = S.Row(c, 26)
	Opt(c, "Items", "items", L, y)
	Opt(c, "Money", "money", M, y)
	y = S.Row(c, 26)
	Opt(c, "Currency", "currency", L, y)
	Opt(c, "Honor", "honor", M, y)
	y = S.Row(c, 30)
	R(S.Stepper(c, "Show items from", L, y, CW - 2 * L, function() return QName(db().minQuality) end,
		function(d) db().minQuality = Clamp(db().minQuality + d, 0, 5) end))
	S.Fit(c, 4)

	local c2 = S.Card(p, "Item details", 12, S.Below(c), CW)
	y = S.Row(c2, 26)
	Opt(c2, "Quest items and progress (3/8)", "quest", L, y, nil, "Quest items get a gold name, a ! badge and your progress from the quest log.")
	y = S.Row(c2, 26)
	Opt(c2, "Item level on gear", "ilvl", L, y)
	Opt(c2, "How many you have (23)", "bagCount", M, y)
	y = S.Row(c2, 26)
	Opt(c2, "\"Upgrade +5\" when gear beats what you wear", "upgrade", L, y, nil,
		"Compares item level with what you have on in that slot (the weaker ring or trinket). It doesn't check whether your class can wear it.")
	y = S.Row(c2, 30)
	local VEND = { "off", "grey", "all" }
	local VNAME = { off = "Off", grey = "Junk only", all = "Everything" }
	R(S.Stepper(c2, "Sell value", L, y, CW - 2 * L, function() return VNAME[db().vendor] or "Junk only" end,
		function(d) db().vendor = Cycle(VEND, db().vendor, d) end))
	S.Fit(c2, 4)
end

------------------------------------------------------------------------
-- Look
------------------------------------------------------------------------
do
	local p = pages[2]
	local c = S.Card(p, "Animation", 12, -12, CW)
	local y = S.Row(c, 30)
	local keys = {}
	for _, a in ipairs(LF.ANIMS) do keys[#keys + 1] = a.key end
	R(S.Stepper(c, "Style", L, y, CW - 2 * L, function()
		for _, a in ipairs(LF.ANIMS) do if a.key == db().anim then return a.name end end
		return "Stack"
	end, function(d) db().anim = Cycle(keys, db().anim, d); LF.ApplyLook(); LF.Test() end))
	y = S.Row(c, 26)
	Opt(c, "Glow, shine and sparkles on rare and better", "fancy", L, y)
	y = S.Row(c, 26)
	Opt(c, "New lines push older ones upward", "growUp", L, y, function() LF.ApplyLook() end,
		"Off: new lines push older ones downward instead.")
	S.Fit(c, 4)

	local c2 = S.Card(p, "Size and timing", 12, S.Below(c), CW)
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "Size", L, y, CW - 2 * L, function() return string.format("%.1fx", db().scale) end, function(d)
		db().scale = math.floor(Clamp(db().scale + d * 0.1, 0.5, 2.5) * 10 + 0.5) / 10
		LF.ApplyLook()
	end))
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "Time on screen", L, y, CW - 2 * L, function() return db().duration .. " sec" end,
		function(d) db().duration = Clamp(db().duration + d * 0.5, 1.5, 12) end))
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "Most lines at once", L, y, CW - 2 * L, function() return tostring(db().maxLines) end,
		function(d) db().maxLines = Clamp(db().maxLines + d, 2, 15) end))
	S.Fit(c2, 4)
end

------------------------------------------------------------------------
-- Alerts: sounds and the big banner
------------------------------------------------------------------------
do
	local p = pages[3]
	local c = S.Card(p, "Sound for each rarity", 12, -12, CW)
	local ids = {}
	for _, s in ipairs(LF.SOUNDS) do ids[#ids + 1] = s.id end
	local function SoundName(id)
		for _, s in ipairs(LF.SOUNDS) do if s.id == id then return s.name end end
		return LF.SOUNDS[1].name
	end
	local function Row(key, label)
		local y = S.Row(c, 28)
		S.Text(c, label, L, y - 6)
		local play = S.Button(c, "Play", 52, 22)
		play:SetPoint("TOPLEFT", CW - L - 52, y - 1)
		play:SetScript("OnClick", function() LF.PlaySoundID(db().sounds[key]) end)
		local b = S.Button(c, "", 180, 22)
		b:SetPoint("RIGHT", play, "LEFT", -6, 0)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local function show() b:SetText(SoundName(db().sounds[key])) end
		b:SetScript("OnClick", function(_, button)
			db().sounds[key] = Cycle(ids, db().sounds[key], button == "RightButton" and -1 or 1)
			show()
			LF.PlaySoundID(db().sounds[key])
		end)
		S.Tip(b, "Change sound", "Click for the next sound, right-click for the previous one. It plays as you pick it.")
		R(show)
	end
	for q = 2, 5 do Row(q, QName(q)) end
	Row("quest", Hex(1, 0.82, 0) .. "Quest item|r")
	S.Fit(c, 6)

	local c2 = S.Card(p, "Big banner", 12, S.Below(c), CW)
	local y = S.Row(c2, 26)
	Opt(c2, "Banner across the screen for great drops", "banner", L, y)
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "Starting from", L, y, CW - 2 * L, function() return QName(db().bannerMin) end,
		function(d) db().bannerMin = Clamp(db().bannerMin + d, 3, 5) end))
	y = S.Row(c2, 26)
	Opt(c2, "Glow around the edge of the screen too", "edgeGlow", L, y)
	S.Fit(c2, 4)
end

------------------------------------------------------------------------
-- Gold & more
------------------------------------------------------------------------
do
	local p = pages[4]
	local c = S.Card(p, "Gold per hour", 12, -12, CW)
	local y = S.Row(c, 26)
	Opt(c, "Show the gold-per-hour box", "gph", L, y, function() LF.ApplyGold() end)
	y = S.Row(c, 26)
	Opt(c, "Start over each time I log in", "gphLoginReset", L, y)
	y = S.Row(c, 32)
	local again = S.Button(c, "Start over now", 140, 22)
	again:SetPoint("TOPLEFT", L, y - 2)
	again:SetScript("OnClick", function() LF.ResetGold() end)
	local spot = S.Button(c, "Put it above action bars", 180, 22)
	spot:SetPoint("LEFT", again, "RIGHT", 8, 0)
	spot:SetScript("OnClick", function() LF.ResetGoldPosition() end)
	y = S.Row(c, 34)
	S.Note(c, "Counts money you loot plus what your loot would sell for, over the time you're logged in. "
		.. "Selling to vendors and trades don't count. Drag the box to move it; right-click it to start over.", L, y, CW - 2 * L)
	S.Fit(c, 8)

	local c2 = S.Card(p, "Other", 12, S.Below(c), CW)
	y = S.Row(c2, 26)
	local mmc = S.Check(c2, "Show minimap button", L, y)
	mmc:SetScript("OnClick", function(self) db().minimap.hide = not self:GetChecked(); LF.UpdateMinimapButton() end)
	R(function() mmc:SetChecked(not db().minimap.hide) end)
	y = S.Row(c2, 34)
	S.Note(c2, "Chat commands: /lflare test, on, off, move, reset, gold\nThe same item looted again joins its line (x5) instead of adding a new one.", L, y, CW - 2 * L)
	S.Fit(c2, 8)
end

------------------------------------------------------------------------
-- Footer
------------------------------------------------------------------------
local foot = S.Footer(panel, 40)
local move = S.Button(foot, "Move text", 110, 24)
move:SetPoint("LEFT", 12, 0)
move:SetScript("OnClick", function()
	db().locked = not db().locked
	LF.ApplyLook()
	move:SetText(db().locked and "Move text" or "Lock text")
end)
R(function() move:SetText(db().locked and "Move text" or "Lock text") end)
S.Tip(move, "Move the loot text", "Shows a blue box where the loot appears. Drag it, then click Lock text.")
local reset = S.Button(foot, "Reset position", 120, 24)
reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
reset:SetScript("OnClick", function() LF.ResetPosition() end)
local test = S.Button(foot, "Preview loot", 130, 24, true)
test:SetPoint("RIGHT", -12, 0)
test:SetScript("OnClick", function() LF.Test() end)

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
S.Group(mm, "LootFlare", function() return db().minimap end, LF.UpdateMinimapButton) -- the shared minimap bag

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
	GameTooltip:AddLine("|cffffffffRight-click|r  preview loot", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
mm:Hide()
