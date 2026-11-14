-- UI Fade: makes chosen parts of the interface see-through. Each part is a group of Blizzard
-- frames (by name); "Everything else" covers the other windows on screen (UIParent's children).
-- Only SetAlpha is used: nothing is moved, hidden or reparented, so it is safe in a fight.
-- The 3D world and nameplates are not part of the interface and are never faded.
local _, ns = ...
local S = ns.Skin
local MIN, MAX = 20, 100 -- never below 20%

UIFadeDB = UIFadeDB or {}
local db
local pending = false

local function Clamp(v)
	v = math.floor((tonumber(v) or 100) / 5 + 0.5) * 5
	return math.max(MIN, math.min(MAX, v))
end

local function Say(msg) print("|cff88ccffUI Fade:|r " .. msg) end

local function Range(fmt, a, b, t) t = t or {} for i = a, b do t[#t + 1] = fmt:format(i) end return t end
local function Join(...) local out = {} for _, t in ipairs({ ... }) do for _, v in ipairs(t) do out[#out + 1] = v end end return out end

-- Groups ----------------------------------------------------------------------------------
-- Names that don't exist on this client are simply skipped.
local GROUPS = {
	{ key = "bars", label = "Action bars", tip = "Your action bars. Use \"Choose bars\" to pick which ones.",
	  subs = {
		{ key = "main", label = "Main bar", names = { "MainMenuBar", "MainActionBar", "ExtraActionBarFrame", "MainMenuBarVehicleLeaveButton" } },
		{ key = "bl", label = "Bottom left bar", names = { "MultiBarBottomLeft" } },
		{ key = "br", label = "Bottom right bar", names = { "MultiBarBottomRight" } },
		{ key = "r", label = "Right bar", names = { "MultiBarRight" } },
		{ key = "l", label = "Right bar 2", names = { "MultiBarLeft" } },
		{ key = "b5", label = "Bar 5", names = { "MultiBar5" } },
		{ key = "b6", label = "Bar 6", names = { "MultiBar6" } },
		{ key = "b7", label = "Bar 7", names = { "MultiBar7" } },
		{ key = "pet", label = "Pet bar", names = { "PetActionBarFrame", "PetActionBar" } },
		{ key = "stance", label = "Stance / shapeshift bar", names = { "StanceBarFrame", "StanceBar", "ShapeshiftBarFrame",
			"PossessBarFrame", "PossessActionBar", "MultiCastActionBarFrame" } },
		{ key = "xp", label = "XP & reputation bars", names = { "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar",
			"StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" } },
	  } },
	{ key = "units", label = "Unit frames", tip = "You, your target, pet, party, raid, boss frames and cast bars.",
	  names = Join({ "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT",
		"PartyFrame", "CompactRaidFrameContainer", "CompactPartyFrame", "CompactRaidFrameManager",
		"BossTargetFrameContainer", "CastingBarFrame", "PlayerCastingBarFrame", "PetCastingBarFrame" },
		Range("PartyMemberFrame%d", 1, 4), Range("Boss%dTargetFrame", 1, 5)) },
	{ key = "buffs", label = "Buffs & cooldowns", tip = "Your buff and debuff icons, weapon enchants and the cooldown manager.",
	  names = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame", "EssentialCooldownViewer",
		"UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" } },
	{ key = "meters", label = "Damage meters", tip = "The game's damage meter, plus Details!, Skada and Recount windows if you use them.",
	  names = Join({ "DamageMeter", "DamageMeterFrame", "Recount_MainWindow", "SkadaBarWindowSkada" },
		Range("DetailsBaseFrame%d", 1, 10), Range("Details_SwitchButtonFrame%d", 1, 10)) },
	{ key = "bags", label = "Bags", tip = "Open bags and the bank.",
	  names = Join({ "ContainerFrameCombinedBags", "BankFrame" }, Range("ContainerFrame%d", 1, 13)) },
	{ key = "menu", label = "Menu & bag buttons", tip = "The row of menu buttons and the bag slots.",
	  names = { "MicroButtonAndBagsBar", "MicroMenuContainer", "MicroMenu", "BagsBar", "MainMenuBarBackpackButton",
		"CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot",
		"KeyRingButton", "BagBarExpandToggle", "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
		"PlayerSpellsMicroButton", "ProfessionMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
		"GuildMicroButton", "LFGMicroButton", "WorldMapMicroButton", "AchievementMicroButton", "CollectionsMicroButton",
		"EJMicroButton", "PVPMicroButton", "StoreMicroButton", "HousingMicroButton", "MainMenuMicroButton",
		"HelpMicroButton" } },
	{ key = "minimap", label = "Minimap", tip = "The minimap and the buttons around it.",
	  names = { "MinimapCluster", "Minimap", "MinimapBackdrop" } },
	{ key = "chat", label = "Chat", tip = "Chat windows, their tabs and the chat buttons.",
	  names = Join({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
		"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" },
		Range("ChatFrame%d", 1, 10), Range("ChatFrame%dTab", 1, 10), Range("ChatFrame%dEditBox", 1, 10),
		Range("ChatFrame%dButtonFrame", 1, 10)) },
	{ key = "rest", label = "Everything else", tip = "All other windows and things on screen: quest tracker, open windows, dialogs, tooltips and other add-ons." },
}

local groupOf = {}    -- frame -> group key
local subOf = {}      -- frame -> which action bar (inside the "bars" group)
local touched = {}    -- frames we have changed (so they can be put back to full)
local hooked = {}
local own = {}        -- this add-on's own frames are never faded

local function Want(f)
	local k = groupOf[f]
	if db and db.on and k and db.groups[k] and not (subOf[f] and db.bars[subOf[f]] == false) then return db.level / 100 end
	return 1
end

local lastSet = {}    -- the alpha we last gave each frame

local function SetA(f, a)
	if pcall(f.SetAlpha, f, a) then
		lastSet[f] = a
		touched[f] = (a < 1) or nil
	else
		pending = true -- tried again after the fight
	end
end

-- True while a frame still has the alpha we gave it (nothing else has changed it since).
local function Ours(f)
	return touched[f] and lastSet[f] and math.abs(f:GetAlpha() - lastSet[f]) < 0.002
end

local ApplyOne
local function Hook(f)
	if hooked[f] then return end
	hooked[f] = true
	pcall(f.HookScript, f, "OnShow", function(self) if groupOf[self] and db then ApplyOne(self) end end)
end

local function Usable(f)
	return type(f) == "table" and type(f.GetObjectType) == "function" and not own[f]
		and not rawget(f, "goodmensUI") -- settings windows of good mens' add-ons stay readable
		and not (f.IsForbidden and f:IsForbidden()) and type(f.SetAlpha) == "function"
end

-- Works out which frame belongs to which group. Run often, because many windows are only
-- created when you first open them.
local function Scan()
	local claimed, newSub = {}, {}
	for _, g in ipairs(GROUPS) do
		for _, n in ipairs(g.names or {}) do
			local f = _G[n]
			if Usable(f) and not claimed[f] then claimed[f] = g.key end
		end
		for _, b in ipairs(g.subs or {}) do
			for _, n in ipairs(b.names) do
				local f = _G[n]
				if Usable(f) and not claimed[f] then claimed[f] = g.key; newSub[f] = b.key end
			end
		end
	end
	subOf = newSub
	-- Top-level windows that hold a frame from a named group can't be faded as "everything
	-- else" without also fading that frame, so those are left alone.
	local holds = {}
	for f in pairs(claimed) do
		local p = f:GetParent()
		local top = f
		while p and p ~= UIParent do top = p; p = p:GetParent() end
		if p == UIParent and top ~= f then holds[top] = true end
	end
	local newGroup = {}
	for f, k in pairs(claimed) do newGroup[f] = k end
	for _, f in ipairs({ UIParent:GetChildren() }) do
		if Usable(f) and not claimed[f] and not holds[f] then newGroup[f] = "rest" end
	end
	-- frames that left their group go back to full
	for f in pairs(touched) do if not newGroup[f] then if Ours(f) then SetA(f, 1) end touched[f] = nil end end
	groupOf = newGroup
	-- A frame inside another group's frame (menu buttons sit inside the main bar on some
	-- clients) ignores its parent's fade so each tick box works on its own.
	-- (Each action bar counts separately here, because on some clients the other bars sit
	-- inside the main bar.)
	local function Id(f) return claimed[f] and (claimed[f] .. ":" .. (newSub[f] or "")) end
	for f in pairs(claimed) do
		local p = f:GetParent()
		while p and p ~= UIParent do
			if claimed[p] and Id(p) ~= Id(f) then
				if f.SetIgnoreParentAlpha and not InCombatLockdown() then pcall(f.SetIgnoreParentAlpha, f, true) end
				break
			end
			p = p:GetParent()
		end
	end
	for f in pairs(groupOf) do Hook(f) end
end

function ApplyOne(f)
	local want = Want(f)
	-- Don't fight frames that fade themselves (chat tabs rest at 0): a frame is only changed
	-- while it is at full, or while it still has the alpha we gave it.
	if touched[f] and not Ours(f) then touched[f] = nil end -- something else took it over
	local a = f:GetAlpha()
	if touched[f] then
		if math.abs(a - want) > 0.002 then SetA(f, want) end
	elseif want < 1 and a >= 0.999 then
		SetA(f, want)
	end
end

local function Apply()
	if not db then return end
	pending = false
	for f in pairs(groupOf) do ApplyOne(f) end
end

local function Update() Scan(); Apply() end

local frame -- settings window, made below
local function Refresh() if frame and frame:IsShown() then frame.Update() end end

function UIFade_Toggle()
	db.on = not db.on
	Update(); Refresh()
	Say(db.on and ("faded to %d%%."):format(db.level) or "full brightness.")
end

local function SetLevel(v)
	db.level = Clamp(v); db.on = db.level < 100
	Update(); Refresh()
end

-- Settings window -------------------------------------------------------------------------
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local W = 384
local CW = W - 24
frame = S.Window("UIFadeFrame", "UI Fade", "Interface\\Icons\\Spell_Holy_MindVision", GetMeta and GetMeta("UIFade", "Version"), W, 420)
own[frame] = true
local more = S.MoreButton(frame.head, "UIFade", frame)
more:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)

-- How see-through
local c1 = S.Card(frame, "How visible", 12, -44, CW)
local big = c1:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
big:SetPoint("TOPRIGHT", -14, -8)
local state = S.Note(c1, "", 14, -30, CW - 28)
local slider = S.Slider(c1, CW - 28, MIN, MAX, 5, "UIFadeSlider")
slider:SetPoint("TOPLEFT", 14, -54)
local lo = c1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); lo:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -4); lo:SetText(MIN .. "%")
local hi = c1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hi:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -4); hi:SetText(MAX .. "%")
local toggle = S.Button(c1, "", CW - 28, 26, true)
toggle:SetPoint("TOPLEFT", 14, -96)
c1:SetHeight(134)

-- What to fade (two columns)
local c2 = S.Card(frame, "What to fade", 12, S.Below(c1), CW)
local checks = {}
local COLX = { 14, CW / 2 + 4 }
for i, g in ipairs(GROUPS) do
	local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
	local c = S.Check(c2, g.label, COLX[col + 1], -34 - row * 26)
	c:SetScript("OnClick", function(self)
		db.groups[g.key] = self:GetChecked() and true or false
		Update()
	end)
	S.Tip(c, g.label, g.tip)
	checks[g.key] = c
end
c2:SetHeight(34 + math.ceil(#GROUPS / 2) * 26 + 8)

-- "Choose..." next to Action bars: a small list with one tick box per bar this client has.
local barsWin = CreateFrame("Frame", "UIFadeBarsFrame", frame)
barsWin:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
barsWin:SetFrameStrata("DIALOG")
barsWin:EnableMouse(true)
S.Panel(barsWin)
do
	local top = barsWin:CreateTexture(nil, "ARTWORK")
	top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
	top:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
end
barsWin:Hide()
local barsTitle = barsWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
barsTitle:SetPoint("TOPLEFT", 14, -12); barsTitle:SetText("Which action bars fade")
local barChecks = {}
local BARS = GROUPS[1].subs

local function BarExists(b)
	for _, n in ipairs(b.names) do if Usable(_G[n]) then return true end end
	return false
end

function barsWin.Update()
	local y = -38
	for _, b in ipairs(BARS) do
		local c = barChecks[b.key]
		if not c then
			c = S.Check(barsWin, b.label)
			c:SetScript("OnClick", function(self) db.bars[b.key] = self:GetChecked() and true or false; Update() end)
			barChecks[b.key] = c
		end
		if BarExists(b) then -- bars this client doesn't have aren't listed
			c:ClearAllPoints(); c:SetPoint("TOPLEFT", 14, y - 4); c:Show()
			c:SetChecked(db.bars[b.key] ~= false)
			y = y - 26
		else
			c:Hide()
		end
	end
	barsWin:SetSize(220, -y + 10)
end
barsWin:SetScript("OnShow", function() barsWin.Update() end)

-- "Choose bars..." sits in the card's title row, top right, so it never crowds the tick boxes.
local barsBtn = S.Button(c2, "Choose bars...", 112, 20)
barsBtn:SetPoint("TOPRIGHT", -12, -8)
barsBtn:SetScript("OnClick", function() barsWin:SetShown(not barsWin:IsShown()) end)
S.Tip(barsBtn, "Choose bars", "Pick which action bars fade when \"Action bars\" is ticked.")

-- Footer: minimap button (its quick controls are in the tick box's tooltip)
local foot = S.Footer(frame, 38)
local mmChk = S.Check(foot, "Show minimap button")
mmChk:SetPoint("LEFT", 14, 0)
S.Tip(mmChk, "Minimap button", "Left-click: this window. Right-click: fade on/off. Mouse wheel: 5% up or down. Drag: move it.")

frame:SetHeight(-S.Below(c2) + 38 + 2)

local updating = false
function frame.Update()
	slider:Set(db.level)
	big:SetText(db.level .. "%")
	big:SetTextColor(db.on and S.ACCENT[1] or 0.55, db.on and S.ACCENT[2] or 0.55, db.on and S.ACCENT[3] or 0.58)
	state:SetText(db.on and "Faded now. Drag to change how much you can see." or "Off: everything is at full brightness.")
	toggle:SetText(db.on and "Back to full brightness" or ("Fade to " .. db.level .. "%"))
	for k, c in pairs(checks) do c:SetChecked(db.groups[k]) end
	if barsWin:IsShown() then barsWin.Update() end
	mmChk:SetChecked(not db.minimap.hide)
end

slider.onChange = function(v)
	db.level = Clamp(v); db.on = true -- moving the slider shows the result straight away
	Update(); frame.Update()
end
toggle:SetScript("OnClick", function() UIFade_Toggle() end)
frame:SetScript("OnShow", function() frame.Update() end)

-- Minimap button --------------------------------------------------------------------------
-- Left-click: the window. Right-click: fade on/off. Mouse wheel: 5% up or down. Drag: move.
local mm = CreateFrame("Button", "UIFadeMinimapButton", Minimap)
own[mm] = true
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
if mm.SetIgnoreParentAlpha then mm:SetIgnoreParentAlpha(true) end -- stays visible when the minimap fades

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
S.Group(mm, "UIFade", function() return db and db.minimap end, UpdateButton) -- the shared minimap bag

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("UI Fade")
	GameTooltip:AddLine(db.on and ("Faded: %d%% visible"):format(db.level) or "Full brightness", 1, 1, 1)
	GameTooltip:AddLine("|cffffffffLeft-click|r  settings", 0.8, 0.8, 0.8)
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
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		db = UIFadeDB
		db.level = Clamp(db.level or 80)
		if db.on == nil then db.on = false end
		db.on = db.on and true or false
		if type(db.minimap) ~= "table" then db.minimap = { angle = 195, hide = false } end
		if type(db.groups) ~= "table" then
			db.groups = {} -- first run (or coming from 1.x, which faded everything): all ticked
			for _, g in ipairs(GROUPS) do db.groups[g.key] = true end
		end
		for _, g in ipairs(GROUPS) do db.groups[g.key] = db.groups[g.key] and true or false end
		if type(db.bars) ~= "table" then db.bars = {} end
		for _, b in ipairs(GROUPS[1].subs) do db.bars[b.key] = db.bars[b.key] ~= false end
		UpdateButton()
		if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() if db.on then Update() end end) end
	end
	if not db then return end
	if event ~= "PLAYER_REGEN_ENABLED" or pending then Update() end
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
	elseif msg == "on" then db.on = true; Update(); Refresh(); Say(("faded to %d%%."):format(db.level))
	elseif msg == "off" then db.on = false; Update(); Refresh(); Say("full brightness.")
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
