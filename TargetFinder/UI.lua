-- Target Finder: the settings window (three simple steps), search box, minimap button, slash command.
-- Settings apply to the Find key as you change them (queued while in a fight).
local TF = TargetFinder

local GOLD, WHITE, GREY, GREEN, RED, ORANGE = "|cffffd100", "|cffffffff", "|cff9d9d9d", "|cff20ff20", "|cffff4040", "|cffff9933"

------------------------------------------------------------------------
-- Small building blocks
------------------------------------------------------------------------
local function Tip(widget, title, text)
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Text(parent, text, x, y, font, width)
	local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	l:SetPoint("TOPLEFT", x, y)
	l:SetJustifyH("LEFT")
	if width then l:SetWidth(width) end
	l:SetText(text)
	return l
end

local function Edit(parent, x, y, w)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(w, 20)
	e:SetPoint("TOPLEFT", x, y)
	e:SetAutoFocus(false)
	e:SetMaxLetters(80)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

local function Button(parent, text, w, x, y)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	return b
end

local function Check(parent, text, x, y)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c:SetPoint("TOPLEFT", x, y)
	local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t:SetPoint("LEFT", c, "RIGHT", 2, 0)
	t:SetText(text)
	c.label = t
	return c
end

local function Menu(owner, build)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		TF.Print("This client has no menu API; type the name instead.")
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if root.SetScrollMode then root:SetScrollMode(380) end
		build(root)
	end)
end

local function KeyName(binding)
	local key = GetBindingKey(binding)
	return key and (GetBindingText and GetBindingText(key) or key) or nil
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local W = 360
local BOTTOM = 444 -- where the last row of settings ends
local f = CreateFrame("Frame", "TargetFinderFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(W, BOTTOM + 70)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetClampedToScreen(true)
if f.SetBackdrop then
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
end
f:Hide()
tinsert(UISpecialFrames, "TargetFinderFrame")

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Target Finder")
local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", 0, -38)
subtitle:SetText("Press one key to find a mob near you.")
CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)

-- Step 1: who
Text(f, GOLD .. "1.|r  Who are you looking for?", 20, -62, "GameFontNormalLarge")
local mobEdit = Edit(f, 30, -86, 216)
local favBtn = Button(f, "Save", 70, 262, -85)
local nearbyBtn = Button(f, "Nearby", 100, 24, -112)
local questBtn = Button(f, "Quests", 100, 128, -112)
local savedBtn = Button(f, "Saved", 100, 232, -112)
local partialChk = Check(f, "Match part of the name", 22, -136)
local tracking = Text(f, "", 24, -164, "GameFontHighlight", 312) -- "Looking for: <name>"

-- Step 2: keys
Text(f, GOLD .. "2.|r  Pick your key", 20, -192, "GameFontNormalLarge")
local findKeyBtn = Button(f, "Set Find key", 120, 24, -216)
local findKeyText = Text(f, "", 152, -221, "GameFontHighlight", 190)
local searchKeyBtn = Button(f, "Set Search key", 120, 24, -242)
local searchKeyText = Text(f, "", 152, -247, "GameFontHighlightSmall", 190)

-- Step 3: when found
Text(f, GOLD .. "3.|r  When I find it...", 20, -276, "GameFontNormalLarge")
local spellEdit = Edit(f, 30, -300, 196)
local spellBtn = Button(f, "Spellbook", 90, 242, -299)
local tagChk = Check(f, "Tag mode: next press tabs to the next enemy", 22, -324)
local markChk = Check(f, "Marker on enemies:", 22, -348)
local markerBtn = Button(f, "", 104, 236, -348)
local friendMarkChk = Check(f, "Marker on friendlies:", 22, -372)
local friendMarkerBtn = Button(f, "", 104, 236, -372)
local soundChk = Check(f, "Play a sound:", 22, -396)
local soundBtn = Button(f, "", 104, 236, -396)
local mapChk = Check(f, "Show on map", 22, -420)
local miniChk = Check(f, "Show on minimap", 138, -420)
local spotsText = Text(f, "", 276, -425, "GameFontHighlightSmall", 80)
TF.spotsText = spotsText

-- What to do next (always at the bottom)
-- The window grows to fit it, so a long message can never overlap the buttons above.
local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
status:SetWidth(316)
local function Layout()
	local bottom = BOTTOM
	status:ClearAllPoints()
	status:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -(bottom + 12))
	local h = status:GetStringHeight()
	if type(h) ~= "number" or h < 15 then h = 15 end
	f:SetHeight(bottom + 12 + h + 24)
end
status:SetJustifyH("LEFT")
status:SetSpacing(3)

------------------------------------------------------------------------
-- Tooltips (plain words)
------------------------------------------------------------------------
Tip(mobEdit, "Mob name", "Type the name of the mob you want. A list of matches pops up: click one, or use Up/Down and Enter.")
Tip(favBtn, "Save", "Keep this name in your Saved list, so you can pick it again later.")
Tip(nearbyBtn, "Nearby", "Pick from the mobs that live in the zone you're in. Needs the Questie addon.")
Tip(questBtn, "Quests", "Pick a mob you need to kill for one of your quests.")
Tip(savedBtn, "Saved", "Your saved names and the names you used recently.")
Tip(partialChk, "Match part of the name", "Off: only the exact name. On: any mob whose name contains what you typed, e.g. \"Zanzil\" finds Zanzil Witch Doctor, Zanzil Zombie and the rest. Map dots then show all of them.")
Tip(findKeyBtn, "Find key", "Click, then press the key you want. Pressing that key looks for your mob. Press it again and again while you look around.")
Tip(searchKeyBtn, "Search key (optional)", "Click, then press a key. That key opens a small box where you can type a new mob name.")
Tip(spellEdit, "Spell", "The spell to cast on the mob when it's found, e.g. Moonfire or Hunter's Mark. Leave it empty to just target the mob.")
Tip(spellBtn, "Spellbook", "Pick a spell from your spellbook, including lower ranks.")
Tip(tagChk, "Tag mode", "For tagging lots of mobs. The first press finds your mob by name. While you're on a living enemy, each press works like Tab: it jumps to the next enemy in front of you and casts your spell. Tab ignores names, so in a mixed area it can pick a different mob.")
Tip(markChk, "Marker on enemies", "Put a raid marker over the enemy it finds, so it's easy to see on screen.")
Tip(markerBtn, "Enemy marker", "Choose the marker icon for enemies.")
Tip(friendMarkChk, "Marker on friendlies", "Put a raid marker over the friendly NPC it finds (vendors, trainers, quest givers), so it's easy to see on screen.")
Tip(friendMarkerBtn, "Friendly marker", "Choose the marker icon for friendly NPCs.")
Tip(soundChk, "Sound", "Play a sound when the key finds the mob. It stays quiet if you press again on the same mob.")
Tip(soundBtn, "Which sound", "Choose the sound. Picking one plays it, so you can hear it first.")
Tip(mapChk, "Map", "Puts pink dots on your world map where this mob can spawn. Needs the Questie addon.")
Tip(miniChk, "Minimap", "Puts pink dots on your minimap (radar) when you're near a place this mob can spawn. Needs the Questie addon.")

------------------------------------------------------------------------
-- Behaviour
------------------------------------------------------------------------
local lastMsg

local function Refresh()
	local db = TargetFinderDB
	if not db or not f:IsShown() then return end
	if not mobEdit:HasFocus() then mobEdit:SetText(db.mob) end
	if not spellEdit:HasFocus() then spellEdit:SetText(db.spell) end
	tagChk:SetChecked(db.tagMode)
	partialChk:SetChecked(not db.exact)
	markChk:SetChecked(db.mark)
	soundChk:SetChecked(db.sound)
	markerBtn:SetText(TF.MarkerIcon(db.marker) .. " " .. TF.MARKERS[db.marker])
	markerBtn:SetAlpha(db.mark and 1 or 0.4)
	friendMarkChk:SetChecked(db.markFriend)
	friendMarkerBtn:SetText(TF.MarkerIcon(db.friendMarker) .. " " .. TF.MARKERS[db.friendMarker])
	friendMarkerBtn:SetAlpha(db.markFriend and 1 or 0.4)
	soundBtn:SetText(TF.SOUNDS[db.soundChoice].name)
	soundBtn:SetAlpha(db.sound and 1 or 0.4)
	mapChk:SetChecked(db.mapPins)
	miniChk:SetChecked(db.miniPins)
	local spots = ""
	if (db.mapPins or db.miniPins) and TF.Clean(db.mob) ~= "" then
		if TF.pinNote then spots = GREY .. TF.pinNote .. "|r"
		elseif TF.pinCount == 0 then spots = GREY .. "no spots known|r"
		else spots = GREY .. TF.pinCount .. (TF.pinCount == 1 and " spot|r" or " spots|r") end
	end
	spotsText:SetText(spots)

	local body, err = TF.BuildBody()
	local name = TF.Clean(db.mob)
	tracking:SetText(body and ("Looking for: " .. WHITE .. name .. "|r") or (GREY .. "Looking for: nobody yet|r"))

	local findKey, searchKey = KeyName(TF.BINDING), KeyName("TARGETFINDER_OPEN_SEARCH")
	findKeyText:SetText(findKey and ("Find key: " .. GREEN .. findKey .. "|r") or (ORANGE .. "No Find key yet|r"))
	searchKeyText:SetText(searchKey and ("Search key: " .. GREEN .. searchKey .. "|r") or (GREY .. "Optional: opens the search box|r"))

	local next
	if name == "" then
		next = ORANGE .. "Next: type the name of a mob in step 1.|r"
	elseif not body then
		next = RED .. err .. "|r"
	elseif not findKey then
		next = ORANGE .. "Next: click \"Set Find key\" in step 2 and press a key.|r"
	elseif TF.appliedBody ~= body then
		next = ORANGE .. "You're in a fight. Your change starts working after the fight.|r"
	else
		local what = (TF.Clean(db.spell) ~= "") and (", and " .. TF.Clean(db.spell) .. " is cast") or ""
		next = GREEN .. "Ready!|r Walk around and press " .. GREEN .. findKey .. "|r to find " .. WHITE .. name .. "|r.\n"
			.. GREY .. "When it's close enough to see, it gets targeted" .. what .. ".|r"
	end
	status:SetText(next .. (lastMsg and ("\n" .. lastMsg) or ""))
	Layout()
end
TF.Refresh = Refresh
f:SetScript("OnShow", function() lastMsg = nil; Refresh() end)

local function Say(ok, msg) lastMsg = (ok and GREEN or RED) .. msg .. "|r"; Refresh() end
local function Changed() TF.Apply(); Refresh() end

local function Choose(name)
	mobEdit:ClearFocus()
	Say(TF.Track(name))
end

------------------------------------------------------------------------
-- Type-ahead list shared by the name box and the search box: updates as you type.
-- Click a row, or Up/Down + Enter, or Tab for the top one.
------------------------------------------------------------------------
local MAX_ROWS = 8
local sugg = CreateFrame("Frame", "TargetFinderSuggest", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
sugg:SetFrameStrata("TOOLTIP")
sugg:SetWidth(250)
sugg:SetClampedToScreen(true)
if sugg.SetBackdrop then
	sugg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	sugg:SetBackdropColor(0, 0, 0, 0.95)
end
sugg:Hide()
local rows, results, onPick = {}, {}, nil
for i = 1, MAX_ROWS do
	local r = CreateFrame("Button", nil, sugg)
	r:SetSize(238, 16)
	r:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 16)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", 2, 0)
	t:SetPoint("RIGHT", -2, 0)
	t:SetJustifyH("LEFT")
	r.text = t
	r:SetScript("OnClick", function(self)
		local pick, e = onPick, results[self.index]
		sugg:Hide()
		if pick and e then pick(e.name) end
	end)
	rows[i] = r
end

local function HideSuggestions() sugg:Hide() end
TF.HideSuggestions = HideSuggestions

-- Keyboard selection: 0 = nothing highlighted (Enter then uses exactly what was typed).
local sel = 0
local function Highlight()
	for i, r in ipairs(rows) do
		if i == sel then r:LockHighlight() else r:UnlockHighlight() end
	end
end

local function ShowSuggestions(edit, pick)
	results = TF.Suggest(edit:GetText(), MAX_ROWS)
	sel = 0
	Highlight()
	if #results == 0 then sugg:Hide() return end
	onPick = pick
	for i, r in ipairs(rows) do
		local e = results[i]
		if e then r.index = i; r.text:SetText(e.label); r:Show() else r:Hide() end
	end
	sugg:SetHeight(10 + #results * 16)
	sugg:ClearAllPoints()
	sugg:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -6, -2)
	sugg:Show()
end

-- Wires an edit box: list follows typing; Up/Down highlight a match, Enter or Tab takes it
-- (Tab takes the top one if none is highlighted); Escape/focus loss closes the list.
-- Must be called after the box's own OnEnterPressed is set: that stays the "no selection" action.
local function AttachSuggestions(edit, pick)
	edit:HookScript("OnTextChanged", function(self, user) if user then ShowSuggestions(self, pick) end end)
	edit:SetScript("OnArrowPressed", function(_, key)
		if not sugg:IsShown() or #results == 0 then return end
		if key == "DOWN" then sel = sel % #results + 1
		elseif key == "UP" then sel = (sel <= 1) and #results or sel - 1
		else return end
		Highlight()
	end)
	local function take(e) sel = 0; Highlight(); sugg:Hide(); pick(e.name) end
	local enter = edit:GetScript("OnEnterPressed")
	edit:SetScript("OnEnterPressed", function(self, ...)
		local e = sugg:IsShown() and sel > 0 and results[sel]
		if e then take(e) elseif enter then enter(self, ...) end
	end)
	edit:SetScript("OnTabPressed", function()
		local e = sugg:IsShown() and (results[sel] or results[1])
		if e then take(e) end
	end)
	edit:HookScript("OnEditFocusLost", function() if not sugg:IsMouseOver() then sugg:Hide() end end)
	edit:HookScript("OnEscapePressed", HideSuggestions)
end
TF.AttachSuggestions = AttachSuggestions

-- Grey placeholder text, shown while the box is empty.
local function AddHint(edit, text)
	local h = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h:SetPoint("LEFT", 2, 0)
	h:SetText(text)
	edit:HookScript("OnTextChanged", function(self) h:SetShown(self:GetText() == "") end)
	h:SetShown(edit:GetText() == "")
	edit.hint = h
end
TF.AddHint = AddHint

mobEdit:SetScript("OnTextChanged", function(self, user) if user then TargetFinderDB.mob = self:GetText(); Changed() end end)
local function CommitMob(self)
	self:ClearFocus()
	sugg:Hide()
	if TF.BuildBody() then TF.AddRecent(TF.Clean(TargetFinderDB.mob)) end
end
mobEdit:SetScript("OnEnterPressed", CommitMob)
AttachSuggestions(mobEdit, Choose)
AddHint(mobEdit, "Type a mob's name...")
f:HookScript("OnHide", HideSuggestions)

spellEdit:SetScript("OnTextChanged", function(self, user) if user then TargetFinderDB.spell = self:GetText(); Changed() end end)
spellEdit:SetScript("OnEnterPressed", spellEdit.ClearFocus)
AddHint(spellEdit, "Spell to cast (optional)")
mapChk:SetScript("OnClick", function(self) TargetFinderDB.mapPins = self:GetChecked() and true or false; TF.UpdatePins(); Refresh() end)
miniChk:SetScript("OnClick", function(self) TargetFinderDB.miniPins = self:GetChecked() and true or false; TF.UpdatePins(); Refresh() end)
partialChk:SetScript("OnClick", function(self) TargetFinderDB.exact = not self:GetChecked(); Changed(); TF.UpdatePins(); Refresh() end)
tagChk:SetScript("OnClick", function(self) TargetFinderDB.tagMode = self:GetChecked() and true or false; Changed() end)
markChk:SetScript("OnClick", function(self) TargetFinderDB.mark = self:GetChecked() and true or false; Changed() end)
soundChk:SetScript("OnClick", function(self) TargetFinderDB.sound = self:GetChecked() and true or false; Refresh() end)

friendMarkChk:SetScript("OnClick", function(self) TargetFinderDB.markFriend = self:GetChecked() and true or false; Changed() end)

local function MarkerMenu(btn, title, field, onField, after)
	btn:SetScript("OnClick", function(self)
		Menu(self, function(root)
			root:CreateTitle(title)
			for i = 8, 1, -1 do
				root:CreateRadio(TF.MarkerIcon(i, 16) .. "  " .. TF.MARKERS[i],
					function() return TargetFinderDB[field] == i end,
					function() TargetFinderDB[field] = i; TargetFinderDB[onField] = true; if after then after() end; Changed() end)
			end
		end)
	end)
end
MarkerMenu(markerBtn, "Marker for enemies", "marker", "mark")
MarkerMenu(friendMarkerBtn, "Marker for friendly NPCs", "friendMarker", "markFriend")

soundBtn:SetScript("OnClick", function(self)
	Menu(self, function(root)
		root:CreateTitle("Choose a sound (it plays when you pick it)")
		for i, s in ipairs(TF.SOUNDS) do
			root:CreateRadio(s.name,
				function() return TargetFinderDB.soundChoice == i end,
				function() TargetFinderDB.soundChoice = i; TargetFinderDB.sound = true; TF.PlayFoundSound(); Refresh() end)
		end
	end)
end)

-- Nearby: Questie's list of what lives in this zone (optional; built on click, cached per zone).
nearbyBtn:SetScript("OnClick", function(self)
	Menu(self, function(root)
		local function pick(name) return function() Choose(name) end end
		local zone, why = TF.GetZoneNPCs()
		if not zone then root:CreateTitle(GREY .. why .. "|r") return end
		root:CreateTitle("Rares that live in " .. zone.zone)
		if #zone.rares == 0 then root:CreateTitle(GREY .. "(none known)|r") end
		for _, e in ipairs(zone.rares) do root:CreateButton(e.label, pick(e.name)) end
		root:CreateTitle("Mobs near you (nearest first)")
		if #zone.mobs == 0 then root:CreateTitle(GREY .. "(none known)|r") end
		for _, e in ipairs(zone.mobs) do root:CreateButton(e.label, pick(e.name)) end
		if #zone.all > 0 then
			local sub = root:CreateButton(("All %d mobs in %s (A-Z)"):format(#zone.all, zone.zone))
			if sub.SetScrollMode then sub:SetScrollMode(420) end
			for _, e in ipairs(zone.all) do sub:CreateButton(e.label, pick(e.name)) end
		end
	end)
end)

favBtn:SetScript("OnClick", function()
	local ok, msg = TF.AddFavorite(TargetFinderDB.mob)
	Say(ok, msg)
end)

savedBtn:SetScript("OnClick", function(self)
	Menu(self, function(root)
		local db = TargetFinderDB
		root:CreateTitle("Saved")
		if #db.favorites == 0 then root:CreateTitle(GREY .. "(none yet: click Save next to the name)|r") end
		for _, name in ipairs(db.favorites) do root:CreateButton(name, function() Choose(name) end) end
		root:CreateTitle("Used recently")
		if #db.recent == 0 then root:CreateTitle(GREY .. "(none yet)|r") end
		for _, name in ipairs(db.recent) do root:CreateButton(name, function() Choose(name) end) end
		if root.CreateDivider then root:CreateDivider() end
		local cur = TF.Clean(db.mob)
		for _, name in ipairs(db.favorites) do
			if name == cur then
				root:CreateButton("Remove '" .. cur .. "' from Saved", function() TF.RemoveFavorite(cur); Refresh() end)
				break
			end
		end
		if #db.recent > 0 then root:CreateButton("Clear the recent list", function() wipe(db.recent) end) end
	end)
end)

questBtn:SetScript("OnClick", function(self)
	Menu(self, function(root)
		local data = TF.GetQuestMobs()
		if #data == 0 then
			root:CreateTitle("None of your quests ask you to kill something")
			return
		end
		for _, q in ipairs(data) do
			root:CreateTitle(q.title)
			for _, m in ipairs(q.mobs) do
				root:CreateButton(m.done and (GREY .. m.name .. " (done)|r") or m.name, function() Choose(m.name) end)
			end
		end
	end)
end)

spellBtn:SetScript("OnClick", function(self)
	Menu(self, function(root)
		root:CreateButton(GOLD .. "No spell, just target it|r", function() TargetFinderDB.spell = ""; spellEdit:SetText(""); Changed() end)
		local lines = TF.GetSpells()
		if #lines == 0 then root:CreateTitle("Spellbook unavailable; type a spell name") return end
		for _, line in ipairs(lines) do
			local sub = root:CreateButton(line.name)
			if sub.SetScrollMode then sub:SetScrollMode(380) end
			for _, sp in ipairs(line.spells) do
				local function pick(text) return function()
					TargetFinderDB.spell = text; spellEdit:SetText(text); Changed()
				end end
				if #sp.ranks > 1 then
					-- Plain name = the game casts your highest rank; "Name(Rank N)" casts that exact rank.
					local rsub = sub:CreateButton(sp.name)
					rsub:CreateButton(sp.name .. " " .. GREY .. "(highest rank)|r", pick(sp.name))
					for _, r in ipairs(sp.ranks) do rsub:CreateButton(r, pick(sp.name .. "(" .. r .. ")")) end
				else
					sub:CreateButton(sp.name, pick(sp.name))
				end
			end
		end
	end)
end)

function TF.Toggle()
	if f:IsShown() then f:Hide() else f:Show() end
end

------------------------------------------------------------------------
-- "Set key": click the button, then press a key (or an extra mouse button).
-- If the key already does something, it says what and asks you to press it again.
------------------------------------------------------------------------
local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local cap = CreateFrame("Frame", "TargetFinderKeyCapture", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
cap:SetSize(320, 110)
cap:SetPoint("CENTER", 0, 140)
cap:SetFrameStrata("FULLSCREEN_DIALOG")
cap:EnableMouse(true)
if cap.SetBackdrop then
	cap:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
end
cap:Hide()
local capTitle = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
capTitle:SetPoint("TOP", 0, -16)
local capText = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
capText:SetPoint("TOP", 0, -42)
capText:SetWidth(290)
local capCancel = CreateFrame("Button", nil, cap, "UIPanelButtonTemplate")
capCancel:SetSize(90, 22)
capCancel:SetPoint("BOTTOM", 0, 12)
capCancel:SetText("Cancel")

local capAction, capLabel, capPending
local function StopCapture()
	cap:EnableKeyboard(false)
	cap:Hide()
	capAction, capPending = nil, nil
end
capCancel:SetScript("OnClick", StopCapture)

local function Combo(key)
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

local function TryKey(key)
	if not capAction then return end
	local current = GetBindingAction(key)
	if current and current ~= "" and current ~= capAction and capPending ~= key then
		capPending = key
		local what = _G["BINDING_NAME_" .. current] or current
		capText:SetText(ORANGE .. key .. "|r already does: " .. WHITE .. what .. "|r\nPress " .. key .. " again to use it anyway, or press a different key.")
		return
	end
	local action = capAction
	StopCapture()
	local ok, msg = TF.BindKey(action, key)
	Say(ok, ok and (capLabel .. " key is now " .. key .. ".") or msg)
end

cap:SetScript("OnKeyDown", function(_, key)
	if MODIFIERS[key] then return end
	if key == "ESCAPE" then StopCapture() return end
	TryKey(Combo(key))
end)
cap:SetScript("OnMouseDown", function(_, button)
	if MOUSE[button] then TryKey(Combo(MOUSE[button])) end
end)

local function StartCapture(action, label)
	if InCombatLockdown() then Say(false, "Keys can't be changed during a fight. Try again after it.") return end
	capAction, capLabel, capPending = action, label, nil
	capTitle:SetText("Set your " .. label .. " key")
	capText:SetText("Press the key you want to use now.\n" .. GREY .. "(Esc = cancel)|r")
	cap:Show()
	cap:EnableKeyboard(true)
	if cap.SetPropagateKeyboardInput then cap:SetPropagateKeyboardInput(false) end
end
TF.StartCapture = StartCapture
findKeyBtn:SetScript("OnClick", function() StartCapture(TF.BINDING, "Find") end)
searchKeyBtn:SetScript("OnClick", function() StartCapture("TARGETFINDER_OPEN_SEARCH", "Search") end)

------------------------------------------------------------------------
-- Minimap button (OnUpdate only while dragging)
------------------------------------------------------------------------
local mm = CreateFrame("Button", "TargetFinderMinimapButton", Minimap)
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
icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
local border = mm:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
mm:Hide()

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function PlaceButton()
	local a = math.rad(TargetFinderDB.minimap.angle or 200)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function UpdateMinimap()
	if TargetFinderDB.minimap.hide then mm:Hide() else PlaceButton(); mm:Show() end
end

mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		TargetFinderDB.minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
		PlaceButton()
	end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

------------------------------------------------------------------------
-- Search box (minimap right-click, or the Search key): Enter picks, Escape cancels
------------------------------------------------------------------------
local q = CreateFrame("Frame", "TargetFinderQuick", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
q:SetSize(260, 78)
q:SetFrameStrata("DIALOG")
q:SetClampedToScreen(true)
q:EnableMouse(true)
if q.SetBackdrop then
	q:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	q:SetBackdropColor(0, 0, 0, 0.9)
end
q:Hide()
local qTitle = q:CreateFontString(nil, "OVERLAY", "GameFontNormal")
qTitle:SetPoint("TOPLEFT", 10, -9)
qTitle:SetText("Who are you looking for?")
local qEdit = CreateFrame("EditBox", nil, q, "InputBoxTemplate")
qEdit:SetSize(232, 20)
qEdit:SetPoint("TOPLEFT", 16, -28)
qEdit:SetAutoFocus(false)
qEdit:SetMaxLetters(80)
local qHint = q:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
qHint:SetPoint("TOPLEFT", 10, -56)
qHint:SetWidth(240)
qHint:SetJustifyH("LEFT")
local HINT = GREY .. "Up/Down = choose   Enter = pick   Esc = cancel|r"

local function QuickTrack(name)
	local ok, msg = TF.Track(name)
	if not ok then qHint:SetText(RED .. msg .. "|r") return end
	TF.Print(msg)
	qEdit:ClearFocus()
	q:Hide()
end
qEdit:SetScript("OnEnterPressed", function(self) TF.HideSuggestions(); QuickTrack(self:GetText()) end)
qEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); q:Hide() end) -- nothing saved
AttachSuggestions(qEdit, QuickTrack)
AddHint(qEdit, "Type a mob's name...")
q:SetScript("OnHide", TF.HideSuggestions)

function TF.QuickEdit(anchor)
	if q:IsShown() then q:Hide() return end
	q:ClearAllPoints()
	if anchor then q:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0) else q:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
	qEdit:SetText(TargetFinderDB.mob)
	qHint:SetText(HINT)
	q:Show()
	qEdit:SetFocus()
	qEdit:HighlightText() -- typing replaces the old name straight away
end

-- Key binding "Open search" (Bindings.xml). It runs on key UP, so the key's own letter has
-- already been handled and isn't typed into the box. Press again to close it.
function TargetFinder_OpenSearch(keystate)
	if keystate == "down" then return end
	TF.QuickEdit(mm:IsShown() and mm or nil)
end

mm:SetScript("OnClick", function(self, button)
	if button == "RightButton" then TF.QuickEdit(self) else TF.Toggle() end
end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Target Finder")
	GameTooltip:AddLine("Finds a mob for you when you press your key.", 1, 1, 1, true)
	local db = TargetFinderDB
	if TF.Clean(db.mob) ~= "" then GameTooltip:AddLine("Looking for: " .. WHITE .. db.mob .. "|r", 0.8, 0.8, 0.8) end
	local key = KeyName(TF.BINDING)
	GameTooltip:AddLine("Find key: " .. (key and (GREEN .. key .. "|r") or (ORANGE .. "not set yet|r")), 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(WHITE .. "Left-click|r  open Target Finder", 0.8, 0.8, 0.8)
	GameTooltip:AddLine(WHITE .. "Right-click|r  quick search for a mob", 0.8, 0.8, 0.8)
	GameTooltip:AddLine(WHITE .. "Drag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

TF.OnLogin = function()
	UpdateMinimap()
	if not TargetFinderDB.seenIntro then
		TargetFinderDB.seenIntro = true
		TF.Print("Click the spyglass by your minimap to get started (or type /tfinder).")
	end
end

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------
SLASH_TARGETFINDER1 = "/tfinder"
SlashCmdList.TARGETFINDER = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "minimap" then
		TargetFinderDB.minimap.hide = not TargetFinderDB.minimap.hide
		UpdateMinimap()
		TF.Print("Minimap button " .. (TargetFinderDB.minimap.hide and "hidden. /tfinder minimap to show it." or "shown."))
	else
		TF.Toggle()
	end
end
