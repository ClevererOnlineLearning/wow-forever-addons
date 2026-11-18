-- Hunter Reminder settings window (cards, flat look from Skin.lua) + minimap button.
local _, ns = ...
local S = ns.Skin
local HR = HunterReminder
if not HR then return end -- not a hunter

local function db() return HR.db end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local W = 400
local CW = W - 24
local L = 14
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local panel = S.Window("HunterReminderOptionsFrame", "Hunter Reminder", "Interface\\Icons\\Ability_TrueShot",
	GetMeta and GetMeta("HunterReminder", "Version"), W, 560)
local more = S.MoreButton(panel.head, "HunterReminder", panel)
more:SetPoint("RIGHT", panel.close, "LEFT", -8, 0)

local refreshers = {}
local function R(f) refreshers[#refreshers + 1] = f end
local function RefreshAll() for _, f in ipairs(refreshers) do f() end end
panel:SetScript("OnShow", RefreshAll)

local function Check(card, label, y, get, set, tip)
	local cb = S.Check(card, label, L, y)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); HR.Refresh() end)
	R(function() cb:SetChecked(get()) end)
	if tip then S.Tip(cb, label, tip) end
	return cb
end

-- Buffs to watch: icon + name, and a button cycling Always / In combat only / Off
local MODES = { always = "|cff33ff33Always|r", combat = "|cffffd100In combat only|r", off = "|cffff4040Off|r" }
local c1 = S.Card(panel, "Remind me when missing", 12, -44, CW)
for _, t in ipairs(HR.TRACKED) do
	local y = S.Row(c1, 32)
	local ic = c1:CreateTexture(nil, "ARTWORK")
	ic:SetSize(22, 22)
	ic:SetPoint("TOPLEFT", L, y - 2)
	ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local name = c1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("LEFT", ic, "RIGHT", 8, 0)
	local b = S.Button(c1, "", 140, 24)
	b:SetPoint("TOPLEFT", CW - L - 140, y - 1)
	local key = t.key .. "Mode"
	b:SetScript("OnClick", function()
		db()[key] = HR.MODE_NEXT[db()[key]] or "always"
		b:SetText(MODES[db()[key]])
		HR.Refresh()
	end)
	S.Tip(b, "When to remind you", "Click to switch between Always, In combat only and Off.")
	R(function()
		ic:SetTexture(t.icon or t.fallbackIcon)
		name:SetText(t.name or t.fallbackName)
		b:SetText(MODES[db()[key]] or MODES.always)
	end)
end
local y = S.Row(c1, 30)
S.Note(c1, "\"In combat only\" lets you run around in Cheetah freely and only complains once a fight starts.", L, y, CW - 2 * L)
S.Fit(c1, 4)

-- Sounds: a drop-down list for each reminder (one list, shared, opening under the button clicked)
local cS = S.Card(panel, "Sounds", 12, S.Below(c1), CW)
y = S.Row(cS, 26)
Check(cS, "Play a sound when a reminder appears", y, function() return db().sound end, function(v) db().sound = v end,
	"Plays once when the icon appears (not again for a few seconds), in or out of combat.")
local function SoundName(id)
	for _, s in ipairs(HR.SOUNDS) do if s.id == id then return s.name end end
	return HR.SOUNDS[1].name
end
local IH = 20
local menu = CreateFrame("Frame", "HunterReminderSoundMenu", panel)
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetSize(240, #HR.SOUNDS * IH + 8)
menu:EnableMouse(true)
S.Panel(menu, 1)
S.Border(menu, S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.6)
menu:Hide()
menu.items = {}
for i, s in ipairs(HR.SOUNDS) do
	local r = CreateFrame("Button", nil, menu)
	r:SetSize(232, IH)
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
	r.tick, r.soundID = tick, s.id
	r:SetScript("OnClick", function()
		if not menu.key then return end
		db()[menu.key .. "Sound"] = s.id
		menu:Hide()
		if menu.show then menu.show() end
		HR.PlaySoundID(s.id)
	end)
	menu.items[i] = r
end
local function OpenMenu(b, key, show)
	if menu:IsShown() and menu.owner == b then menu:Hide(); return end
	menu.owner, menu.key, menu.show = b, key, show
	for _, it in ipairs(menu.items) do it.tick:SetShown(db()[key .. "Sound"] == it.soundID) end
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
	menu:Show()
end
panel:HookScript("OnHide", function() menu:Hide() end)
HR.soundPickers = {}
for _, t in ipairs(HR.TRACKED) do
	y = S.Row(cS, 28)
	local label = S.Text(cS, "", L, y - 6)
	local play = S.Button(cS, "Play", 52, 22)
	play:SetPoint("TOPLEFT", CW - L - 52, y - 1)
	play:SetScript("OnClick", function() HR.PlaySoundID(db()[t.key .. "Sound"]) end)
	local b = S.Button(cS, "", 220, 22)
	b:SetPoint("RIGHT", play, "LEFT", -6, 0)
	local function show() b:SetText(SoundName(db()[t.key .. "Sound"]) .. "  |cffffd100v|r") end
	b:SetScript("OnClick", function(self) OpenMenu(self, t.key, show) end)
	S.Tip(b, "Change sound", "Click to pick from the list. It plays as you pick it.")
	HR.soundPickers[t.key] = b
	R(function() label:SetText(t.key == "hawk" and "Aspect" or "Trueshot"); show() end)
end
y = S.Row(cS, 30)
S.Note(cS, "Your own sounds: put custom1.ogg to custom3.ogg in Interface\\AddOns\\HunterReminder\\sounds, then pick Custom 1-3.", L, y, CW - 2 * L)
S.Fit(cS, 4)

-- Options
local c2 = S.Card(panel, "Options", 12, S.Below(cS), CW)
y = S.Row(c2, 26)
Check(c2, "Also remind in cities and inns (out of combat)", y, function() return db().showResting end, function(v) db().showResting = v end)
y = S.Row(c2, 26)
Check(c2, "Hide while mounted", y, function() return db().hideMounted end, function(v) db().hideMounted = v end)
y = S.Row(c2, 30)
R(S.Stepper(c2, "Icon size", L, y, CW - 2 * L, function() return string.format("%.1fx", tonumber(db().scale) or 1) end, function(d)
	db().scale = math.floor(math.min(2.5, math.max(0.5, (tonumber(db().scale) or 1) + d * 0.1)) * 10 + 0.5) / 10
	HR.ApplyLook()
end))
y = S.Row(c2, 26)
local mmc = S.Check(c2, "Show minimap button", L, y)
mmc:SetScript("OnClick", function(self) db().minimap.hide = not self:GetChecked(); HR.UpdateMinimapButton() end)
R(function() mmc:SetChecked(not db().minimap.hide) end)
S.Fit(c2, 4)

-- Auto tracking
local c3 = S.Card(panel, "Auto tracking", 12, S.Below(c2), CW)
y = S.Row(c3, 26)
Check(c3, "Switch tracking to match the mob I target", y, function() return db().autoTrack end, function(v)
	db().autoTrack = v
	if v and HR.AutoTrack then HR.AutoTrack() end
end)
y = S.Row(c3, 26)
Check(c3, "Also during fights (may cost a global cooldown)", y, function() return db().autoTrackCombat end,
	function(v) db().autoTrackCombat = v end)
y = S.Row(c3, 30)
local lockBtn = S.Button(c3, "", 130, 24)
lockBtn:SetPoint("TOPLEFT", L, y)
local lockNote = c3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lockNote:SetPoint("LEFT", lockBtn, "RIGHT", 10, 0)
lockNote:SetPoint("RIGHT", c3, "RIGHT", -L, 0)
lockNote:SetJustifyH("LEFT")
local function PaintLock()
	lockBtn:SetText(db().trackLocked and "Unlock tracking" or "Lock tracking")
	lockNote:SetText(db().trackLocked and "|cffffd100Locked:|r your tracking stays as it is." or "Keeps your current tracking until you unlock.")
end
lockBtn:SetScript("OnClick", function() HR.SetTrackLock(not db().trackLocked) end)
S.Tip(lockBtn, "Lock tracking", "Keeps the tracking you have on now: auto tracking stops switching it with every target. "
	.. "Your buff reminders and the Feign Death warning keep working. Click again to unlock. "
	.. "Also: Shift-click the minimap button, or /hrem tracklock.")
R(PaintLock)
HR.OnTrackLockChanged = PaintLock
y = S.Row(c3, 30)
S.Note(c3, "Beasts, humanoids, undead, demons, elementals, giants and dragonkin, for talents like Improved Tracking.", L, y, CW - 2 * L)
S.Fit(c3, 4)

-- Feign Death
local c4 = S.Card(panel, "Feign Death", 12, S.Below(c3), CW)
y = S.Row(c4, 26)
Check(c4, "Warn me when Feign Death is resisted", y, function() return db().feignWarn end,
	function(v) db().feignWarn = v end,
	"A big red warning, naming the mob when the game says which one, so you can get up and deal with it.")
y = S.Row(c4, 26)
Check(c4, "Play a warning sound with it", y, function() return db().feignSound end, function(v) db().feignSound = v end)
local ftest = S.Button(c4, "Test", 70, 22)
ftest:SetPoint("TOPLEFT", CW - L - 70, y)
ftest:SetScript("OnClick", function() HR.FeignTest() end)
y = S.Row(c4, 30)
S.Note(c4, "Just after you feign, it checks whether a mob is still on you. Mobs need to be on screen (nameplates help).", L, y, CW - 2 * L)
S.Fit(c4, 4)

-- Footer
local foot = S.Footer(panel, 40)
local move = S.Button(foot, "Move icons", 104, 24)
move:SetPoint("LEFT", 12, 0)
move:SetScript("OnClick", function()
	db().locked = not db().locked
	HR.ApplyLook()
	move:SetText(db().locked and "Move icons" or "Lock icons")
end)
R(function() move:SetText(db().locked and "Move icons" or "Lock icons") end)
S.Tip(move, "Move icons", "Drag each icon on its own (Trueshot Aura and Aspect of the Hawk can go in different places). Click again to lock them.")
local reset = S.Button(foot, "Reset position", 120, 24)
reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
reset:SetScript("OnClick", function() HR.ResetPosition(); RefreshAll() end)
S.Tip(reset, "Reset position", "Puts both icons back side by side in the middle of the screen.")
local test = S.Button(foot, "Test", 96, 24, true)
test:SetPoint("RIGHT", -12, 0)
test:SetScript("OnClick", function() HR.Test() end)
S.Tip(test, "Test", "Shows the reminder for a few seconds so you can see and move it.")

panel:SetHeight(-S.Below(c4) + 40 + 2)

function HR.ToggleOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local mm = CreateFrame("Button", "HunterReminderMinimapButton", Minimap)
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
icon:SetTexture("Interface\\Icons\\Ability_TrueShot")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

local border = mm:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")

-- a small padlock on the button while tracking is locked
local padlock = mm:CreateTexture(nil, "OVERLAY", nil, 2)
padlock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
padlock:SetSize(13, 13)
padlock:SetPoint("BOTTOMRIGHT", -4, 5)
padlock:Hide()

local atan2 = math.atan2 or function(yv, xv) return math.atan(yv, xv) end

local function PlaceButton()
	local a = math.rad(db().minimap.angle or 165)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function HR.UpdateMinimapButton()
	if db().minimap.hide then mm:Hide() else PlaceButton(); mm:Show() end
	padlock:SetShown(db().trackLocked and true or false)
end
S.Group(mm, "HunterReminder", function() return db().minimap end, HR.UpdateMinimapButton) -- the shared minimap bag

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
	if IsShiftKeyDown() then HR.SetTrackLock(not db().trackLocked)
	elseif button == "RightButton" then HR.Test() else HR.ToggleOptions() end
	if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Hunter Reminder")
	for _, t in ipairs(HR.TRACKED) do
		GameTooltip:AddDoubleLine(t.name or t.fallbackName, MODES[db()[t.key .. "Mode"]] or "", 1, 1, 1)
	end
	GameTooltip:AddLine("|cffffffffLeft-click|r  settings", 0.8, 0.8, 0.8)
	GameTooltip:AddDoubleLine("Tracking", db().trackLocked and "|cffffd100Locked|r" or (db().autoTrack and "|cff33ff33Matches target|r" or "|cff888888Auto off|r"), 1, 1, 1)
	GameTooltip:AddLine("|cffffffffRight-click|r  test", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffShift-click|r  " .. (db().trackLocked and "unlock tracking" or "lock tracking"), 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
mm:Hide()
