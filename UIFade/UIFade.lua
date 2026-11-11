-- UI Fade: makes chosen parts of the interface see-through. Each part is a group of Blizzard
-- frames (by name); "Everything else" covers the other windows on screen (UIParent's children).
-- Only SetAlpha is used: nothing is moved, hidden or reparented, so it is safe in a fight.
-- The 3D world and nameplates are not part of the interface and are never faded.
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
	{ key = "bars", label = "Action bars", tip = "Main bar, extra bars, pet and stance bars, XP and reputation bars.",
	  names = { "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
		"MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "VerticalMultiBarsContainer", "PetActionBarFrame",
		"PetActionBar", "StanceBarFrame", "StanceBar", "ShapeshiftBarFrame", "PossessBarFrame", "PossessActionBar",
		"MultiCastActionBarFrame", "ExtraActionBarFrame", "MainMenuBarVehicleLeaveButton", "MainMenuExpBar",
		"ReputationWatchBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer",
		"SecondaryStatusTrackingBarContainer" } },
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
local touched = {}    -- frames we have changed (so they can be put back to full)
local hooked = {}
local own = {}        -- this add-on's own frames are never faded

local function Want(f)
	local k = groupOf[f]
	if db and db.on and k and db.groups[k] then return db.level / 100 end
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
		and not (f.IsForbidden and f:IsForbidden()) and type(f.SetAlpha) == "function"
end

-- Works out which frame belongs to which group. Run often, because many windows are only
-- created when you first open them.
local function Scan()
	local claimed = {}
	for _, g in ipairs(GROUPS) do
		for _, n in ipairs(g.names or {}) do
			local f = _G[n]
			if Usable(f) and not claimed[f] then claimed[f] = g.key end
		end
	end
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
	for f, k in pairs(claimed) do
		local p = f:GetParent()
		while p and p ~= UIParent do
			if claimed[p] and claimed[p] ~= k then
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
frame = CreateFrame("Frame", "UIFadeFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
own[frame] = true
frame:SetSize(320, 316)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
if frame.SetBackdrop then
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
end
frame:Hide()
tinsert(UISpecialFrames, "UIFadeFrame") -- Escape closes it

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18); title:SetText("UI Fade")
CreateFrame("Button", nil, frame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)

local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetPoint("TOP", 0, -46)

local slider = CreateFrame("Slider", "UIFadeSlider", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
slider:SetOrientation("HORIZONTAL")
slider:SetSize(250, 17)
slider:SetPoint("TOP", 0, -66)
slider:SetHitRectInsets(0, 0, -10, -10)
if slider.SetBackdrop then
	slider:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
end
slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
slider:SetMinMaxValues(MIN, MAX)
slider:SetValueStep(5)
if slider.SetObeyStepDuringDrag then slider:SetObeyStepDuringDrag(true) end
local lo = slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); lo:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2); lo:SetText(MIN .. "%")
local hi = slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hi:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2); hi:SetText(MAX .. "%")

local what = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
what:SetPoint("TOPLEFT", 22, -104); what:SetText("What to fade:")

local checks = {}
for i, g in ipairs(GROUPS) do
	local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
	local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	c:SetSize(24, 24); c:SetPoint("TOPLEFT", 18 + col * 145, -122 - row * 26)
	local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetText(g.label)
	c.label = t
	c:SetScript("OnClick", function(self)
		db.groups[g.key] = self:GetChecked() and true or false
		Update()
	end)
	c:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(g.label)
		GameTooltip:AddLine(g.tip, 1, 1, 1, true); GameTooltip:Show()
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	checks[g.key] = c
end

local toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
toggle:SetSize(140, 22); toggle:SetPoint("TOP", 0, -260)

local mmChk = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
mmChk:SetSize(24, 24); mmChk:SetPoint("BOTTOMLEFT", 18, 16)
local mmText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mmText:SetPoint("LEFT", mmChk, "RIGHT", 2, 0); mmText:SetText("Show minimap button")

local updating = false
function frame.Update()
	updating = true
	slider:SetValue(db.level)
	updating = false
	label:SetText(("Fade to: %d%% visible%s"):format(db.level, db.on and "" or "  (off now)"))
	toggle:SetText(db.on and "Full brightness" or "Fade")
	for k, c in pairs(checks) do c:SetChecked(db.groups[k]) end
	mmChk:SetChecked(not db.minimap.hide)
end

slider:SetScript("OnValueChanged", function(_, v)
	if updating then return end
	db.level = Clamp(v); db.on = true -- moving the slider shows the result straight away
	Update(); frame.Update()
end)
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
