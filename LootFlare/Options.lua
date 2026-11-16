-- Loot Flare settings window (tabs + cards) and minimap button.
local _, ns = ...
local S = ns.Skin
local LF = LootFlare
local function db() return LF.db end

local W, H = 470, 570
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

local pages = S.Tabs(panel, { "What shows", "Look", "Sounds & banner", "Gold & history" }, -38, 41)
local L = 14         -- left column x inside a card
local M = CW / 2 + 6 -- right column x

------------------------------------------------------------------------
-- What shows
------------------------------------------------------------------------
do
	local p = pages[1]
	local c = S.Card(p, "Show a line for", 12, -12, CW)
	local y = S.Row(c, 26)
	Opt(c, "Items", "items", L, y, nil, "Looting the same item again adds to its line (x5) instead of a new line.")
	Opt(c, "Money", "money", M, y)
	y = S.Row(c, 26)
	Opt(c, "Currency", "currency", L, y)
	Opt(c, "Honor", "honor", M, y)
	y = S.Row(c, 30)
	R(S.Stepper(c, "Lowest item rarity", L, y, CW - 2 * L, function() return QName(db().minQuality) end,
		function(d) db().minQuality = Clamp(db().minQuality + d, 0, 5) end))
	S.Fit(c, 4)

	local c2 = S.Card(p, "Extra info on item lines", 12, S.Below(c), CW)
	y = S.Row(c2, 26)
	Opt(c2, "Quest progress (3/8)", "quest", L, y, nil, "Quest items get a gold name, a ! badge and your progress from the quest log.")
	Opt(c2, "Count in your bags (23)", "bagCount", M, y)
	y = S.Row(c2, 26)
	Opt(c2, "Item level on gear", "ilvl", L, y)
	Opt(c2, "\"Upgrade +5\" on better gear", "upgrade", M, y, nil,
		"When the item level beats what you wear in that slot (the weaker ring or trinket). It doesn't check whether your class can use it.")
	y = S.Row(c2, 30)
	local VEND = { "off", "grey", "all" }
	local VNAME = { off = "Off", grey = "Junk only", all = "All items" }
	R(S.Stepper(c2, "Vendor price", L, y, CW - 2 * L, function() return VNAME[db().vendor] or "Junk only" end,
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
	Opt(c, "Newest line at the bottom", "growUp", L, y, function() LF.ApplyLook() end,
		"On: older lines move up as new ones arrive. Off: the newest line is at the top and older ones move down.")
	S.Fit(c, 4)

	local c2 = S.Card(p, "Size and timing", 12, S.Below(c), CW)
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "Text size", L, y, CW - 2 * L, function() return string.format("%.1fx", db().scale) end, function(d)
		db().scale = math.floor(Clamp(db().scale + d * 0.1, 0.5, 2.5) * 10 + 0.5) / 10
		LF.ApplyLook()
	end))
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "Time on screen", L, y, CW - 2 * L, function() return db().duration .. " sec" end,
		function(d) db().duration = Clamp(db().duration + d * 0.5, 1.5, 12) end))
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "Most lines on screen", L, y, CW - 2 * L, function() return tostring(db().maxLines) end,
		function(d) db().maxLines = Clamp(db().maxLines + d, 2, 15) end))
	S.Fit(c2, 4)
end

------------------------------------------------------------------------
-- Sounds & banner
------------------------------------------------------------------------
do
	local p = pages[3]
	local c = S.Card(p, "Sound for each rarity", 12, -12, CW)
	local function SoundName(id)
		for _, s in ipairs(LF.SOUNDS) do if s.id == id then return s.name end end
		return LF.SOUNDS[1].name
	end
	-- one drop-down list shared by every row: it opens under the button you clicked
	local IH = 20
	local menu = CreateFrame("Frame", "LootFlareSoundMenu", panel)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetSize(180, #LF.SOUNDS * IH + 8)
	menu:EnableMouse(true)
	S.Panel(menu, 1)
	S.Border(menu, 1, 0.82, 0, 0.6)
	menu:Hide()
	menu.items = {}
	for i, s in ipairs(LF.SOUNDS) do
		local r = CreateFrame("Button", nil, menu)
		r:SetSize(172, IH)
		r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * IH)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 0.82, 0, 0.15)
		local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", 20, 0)
		r:SetFontString(fs)
		r:SetText(s.name)
		local tick = r:CreateTexture(nil, "OVERLAY")
		tick:SetSize(14, 14)
		tick:SetPoint("LEFT", 3, 0)
		tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		r.tick = tick
		r:SetScript("OnClick", function()
			if not menu.key then return end
			db().sounds[menu.key] = s.id
			menu:Hide()
			if menu.show then menu.show() end
			LF.PlaySoundID(s.id)
		end)
		menu.items[i] = r
	end
	local function OpenMenu(b, key, show)
		if menu:IsShown() and menu.owner == b then menu:Hide(); return end
		menu.owner, menu.key, menu.show = b, key, show
		for i, s in ipairs(LF.SOUNDS) do menu.items[i].tick:SetShown(db().sounds[key] == s.id) end
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
		menu:Show()
	end
	panel:HookScript("OnHide", function() menu:Hide() end)

	LF.soundPickers = {}
	local function Row(key, label)
		local y = S.Row(c, 28)
		S.Text(c, label, L, y - 6)
		local play = S.Button(c, "Play", 52, 22)
		play:SetPoint("TOPLEFT", CW - L - 52, y - 1)
		play:SetScript("OnClick", function() LF.PlaySoundID(db().sounds[key]) end)
		local b = S.Button(c, "", 180, 22)
		b:SetPoint("RIGHT", play, "LEFT", -6, 0)
		local function show() b:SetText(SoundName(db().sounds[key]) .. "  |cffffd100v|r") end
		b:SetScript("OnClick", function(self) OpenMenu(self, key, show) end)
		S.Tip(b, "Change sound", "Click to pick from the list. It plays as you pick it.")
		LF.soundPickers[key] = b
		R(show)
	end
	for q = 2, 5 do Row(q, QName(q)) end
	Row("quest", Hex(1, 0.82, 0) .. "Quest item|r")
	S.Fit(c, 6)

	local c2 = S.Card(p, "Big banner", 12, S.Below(c), CW)
	local y = S.Row(c2, 26)
	Opt(c2, "Big banner across the screen for great drops", "banner", L, y)
	y = S.Row(c2, 30)
	R(S.Stepper(c2, "For drops of at least", L, y, CW - 2 * L, function() return QName(db().bannerMin) end,
		function(d) db().bannerMin = Clamp(db().bannerMin + d, 3, 5) end))
	y = S.Row(c2, 26)
	Opt(c2, "Also glow around the edge of the screen", "edgeGlow", L, y)
	S.Fit(c2, 4)
end

------------------------------------------------------------------------
-- Gold & history
------------------------------------------------------------------------
do
	local p = pages[4]
	local c = S.Card(p, "Gold-per-hour box", 12, -12, CW)
	local y = S.Row(c, 26)
	Opt(c, "Show the box", "gph", L, y, function() LF.ApplyGold() end)
	Opt(c, "Lock it in place", "gphLocked", M, y, function() LF.SetGoldLock(db().gphLocked) end,
		"Stops the box being dragged; clicking it still works. Shift-click the box to lock or unlock it too.")
	y = S.Row(c, 26)
	Opt(c, "Start a new session each time I log in", "gphLoginReset", L, y)
	y = S.Row(c, 26)
	Opt(c, "Pause the clock when AFK, idle or in town", "pauseIdle", L, y, nil,
		"The clock stops while you're AFK, resting in a town or inn, or haven't moved, fought or looted for 3 minutes, so breaks don't lower your gold per hour.")
	y = S.Row(c, 26)
	Opt(c, "Doubtful AH prices count at vendor price", "ahSafe", L, y, nil,
		"Items that rarely sell (TSM sale rate) or whose Auctionator price is over a week old count at vendor price, so one lucky drop doesn't inflate your numbers. They're marked in the loot history.")
	y = S.Row(c, 30)
	local again = S.Button(c, "New session", 120, 22)
	again:SetPoint("TOPLEFT", L, y - 2)
	again:SetScript("OnClick", function() LF.ResetGold() end)
	S.Tip(again, "New session", "Sets the box back to zero. The session so far is saved in the loot history.")
	local spot = S.Button(c, "Move it above the action bars", 210, 22)
	spot:SetPoint("LEFT", again, "RIGHT", 8, 0)
	spot:SetScript("OnClick", function() LF.ResetGoldPosition() end)
	y = S.Row(c, 30)
	S.Note(c, "Money you loot plus what your loot is worth (vendor price, or AH price with Auctionator or TSM). "
		.. "Vendor sales, mail and trades don't count.", L, y, CW - 2 * L)
	S.Fit(c, 6)

	local c2 = S.Card(p, "Loot history", 12, S.Below(c), CW)
	y = S.Row(c2, 26)
	Opt(c2, "Keep a loot history", "hist", L, y, nil,
		"Remembers every item you loot, where it dropped and what dropped it, with its AH value.")
	local hb = S.Button(c2, "Open loot history", 140, 22)
	hb:SetPoint("TOPRIGHT", -L, y - 2)
	hb:SetScript("OnClick", function() if LF.ToggleHistory then LF.ToggleHistory() end end)
	y = S.Row(c2, 26)
	Opt(c2, "Leave quest rewards out of zone rankings", "histQuestOut", L, y, nil,
		"Quest gold and reward items still count for your session, but not for the zone, so zones are ranked by what you farm there.")
	y = S.Row(c2, 30)
	S.Note(c2, "Shows which zones, subzones and mobs pay best. Also opens when you click the gold-per-hour box.",
		L, y, CW - 2 * L)
	S.Fit(c2, 6)

	local c3 = S.Card(p, "Other", 12, S.Below(c2), CW)
	y = S.Row(c3, 26)
	local mmc = S.Check(c3, "Show the minimap button", L, y)
	mmc:SetScript("OnClick", function(self) db().minimap.hide = not self:GetChecked(); LF.UpdateMinimapButton() end)
	R(function() mmc:SetChecked(not db().minimap.hide) end)
	y = S.Row(c3, 20)
	S.Note(c3, "Chat commands: /lflare test, on, off, move, reset, gold, goldlock, history, check", L, y, CW - 2 * L)
	S.Fit(c3, 6)
end

------------------------------------------------------------------------
-- Footer
------------------------------------------------------------------------
local foot = S.Footer(panel, 40)
local move = S.Button(foot, "Move loot text", 120, 24)
move:SetPoint("LEFT", 12, 0)
move:SetScript("OnClick", function()
	db().locked = not db().locked
	LF.ApplyLook()
	move:SetText(db().locked and "Move loot text" or "Lock loot text")
end)
R(function() move:SetText(db().locked and "Move loot text" or "Lock loot text") end)
S.Tip(move, "Move the loot text", "Shows a blue box where loot appears. Drag it, then click Lock loot text.")
local reset = S.Button(foot, "Reset text position", 140, 24)
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
