-- Target Finder: the settings window (three simple steps), search box, minimap button, slash command.
-- Settings apply to the Find key as you change them (queued while in a fight).
local _, ns = ...
local S = ns.Skin
local TF = TargetFinder

local GOLD, WHITE, GREY, GREEN, RED, ORANGE = "|cffffd100", "|cffffffff", "|cff9d9d9d", "|cff20ff20", "|cffff4040", "|cffff9933"

------------------------------------------------------------------------
-- Small building blocks (flat look from Skin.lua)
------------------------------------------------------------------------
local function Tip(widget, title, text) S.Tip(widget, title, text) end

local function Text(parent, text, x, y, font, width)
	return S.Text(parent, text, x, y, font, width)
end

local function Edit(parent, x, y, w)
	local e = S.Edit(parent, w, 24)
	e:SetPoint("TOPLEFT", x, y)
	return e
end

local function Button(parent, text, w, x, y, primary)
	local b = S.Button(parent, text, w, 24, primary)
	b:SetPoint("TOPLEFT", x, y)
	return b
end

local function Check(parent, text, x, y)
	return S.Check(parent, text, x, y)
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
-- Window: three cards (who / keys / when found) and a status box under them
------------------------------------------------------------------------
local W = 404
local CW = W - 24 -- card width
local L = 14      -- left edge inside a card
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = GetMeta and GetMeta("TargetFinder", "Version")
local f = S.Window("TargetFinderFrame", "Target Finder", "Interface\\Icons\\INV_Misc_Spyglass_03", version, W, 560)
local more = S.MoreButton(f.head, "TargetFinder", f)
more:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
-- one-line explanation, just under the title bar (the title bar itself is too narrow for it)
local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sub:SetPoint("TOPLEFT", 14, -40)
sub:SetText("Press one key to find a mob")

local function Num(n) return WHITE .. n .. "|r   " end

-- Step 1: who
local c1 = S.Card(f, Num(1) .. "Who are you looking for?", 12, -58, CW)
local mobEdit = Edit(c1, L, -34, CW - 2 * L - 78)
local favBtn = Button(c1, "Save", 70, CW - L - 70, -34)
local third = math.floor((CW - 2 * L - 12) / 3)
local mob2Edit = Edit(c1, L, -66, CW - 2 * L - 78)
-- Small "exact" / "part" label at the right end of a name box (see Refresh).
for _, e in ipairs({ mobEdit, mob2Edit }) do
	e.mode = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	e.mode:SetPoint("RIGHT", -6, 0)
	e.mode:SetText("")
end
local clear2Btn = Button(c1, "Clear", 70, CW - L - 70, -66)
local nearbyBtn = Button(c1, "Nearby", third, L, -98)
local questBtn = Button(c1, "Quests", third, L + third + 6, -98)
local savedBtn = Button(c1, "Saved", third, L + 2 * (third + 6), -98)
local partialChk = Check(c1, "Match part of the name", L, -130)
local tracking = Text(c1, "", L, -160, "GameFontHighlight", CW - 2 * L) -- "Looking for: <name>"
tracking:SetJustifyH("LEFT")
c1:SetHeight(198) -- room for two lines under "Looking for"

-- Step 2: keys
local c2 = S.Card(f, Num(2) .. "Pick your key", 12, S.Below(c1), CW)
local findKeyBtn = Button(c2, "Set Find key", 136, L, -34, true)
local findKeyText = Text(c2, "", L + 148, -40, "GameFontHighlight", CW - L - 160)
local searchKeyBtn = Button(c2, "Set Search key", 136, L, -64)
local searchKeyText = Text(c2, "", L + 148, -70, "GameFontHighlightSmall", CW - L - 160)
c2:SetHeight(98)

-- Step 3: when found
local c3 = S.Card(f, Num(3) .. "When I find it...", 12, S.Below(c2), CW)
local spellEdit = Edit(c3, L, -34, CW - 2 * L - 100)
local spellBtn = Button(c3, "Spellbook", 92, CW - L - 92, -34)
local tagChk = Check(c3, "Tag mode: next press tabs to the next enemy", L, -66)
local RW = 124 -- the choice buttons on the right
local markChk = Check(c3, "Marker on enemies", L, -94)
local markerBtn = Button(c3, "", RW, CW - L - RW, -92)
local friendMarkChk = Check(c3, "Marker on friendlies", L, -122)
local friendMarkerBtn = Button(c3, "", RW, CW - L - RW, -120)
local soundChk = Check(c3, "Play a sound", L, -150)
local soundBtn = Button(c3, "", RW, CW - L - RW, -148)
local mapChk = Check(c3, "Show on map", L, -180)
local miniChk = Check(c3, "Show on minimap", L + 130, -180)
local spotsText = Text(c3, "", CW - L - 90, -184, "GameFontHighlightSmall", 90)
spotsText:SetJustifyH("RIGHT")
TF.spotsText = spotsText
c3:SetHeight(208)

-- What to do next (always at the bottom). The window grows to fit it, so a long message can
-- never overlap the settings above.
local BOTTOM = -S.Below(c3) -- where the status box starts
local sc = CreateFrame("Frame", nil, f)
sc:SetPoint("TOPLEFT", 12, -BOTTOM)
sc:SetWidth(CW)
local scBg = sc:CreateTexture(nil, "BACKGROUND")
scBg:SetAllPoints()
scBg:SetColorTexture(1, 1, 1, 0.035)
S.Border(sc, 1, 1, 1, 0.08)
local scBar = sc:CreateTexture(nil, "ARTWORK")
scBar:SetPoint("TOPLEFT", 1, -1); scBar:SetPoint("BOTTOMLEFT", 1, 1); scBar:SetWidth(3)
scBar:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
local status = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
status:SetPoint("TOPLEFT", 14, -10)
status:SetWidth(CW - 28)
local function Layout()
	local h = status:GetStringHeight()
	if type(h) ~= "number" or h < 15 then h = 15 end
	sc:SetHeight(h + 20)
	f:SetHeight(BOTTOM + h + 20 + 12)
end
status:SetJustifyH("LEFT")
status:SetSpacing(3)

------------------------------------------------------------------------
-- Tooltips (plain words)
------------------------------------------------------------------------
Tip(mobEdit, "Mob name", "Type the name of the mob you want. A list of matches pops up: click one, or use Up/Down and Enter.")
Tip(mob2Edit, "Second target (optional)", "A second mob to look for. Your Find key then switches between the two: each press tries the other one first, and if only one is around it finds that one. Shift+click in the lists below (or Shift+Enter in the search box) puts a name here.")
Tip(clear2Btn, "Clear", "Stop looking for the second target.")
Tip(favBtn, "Save", "Keep this name in your Saved list, so you can pick it again later.")
Tip(nearbyBtn, "Nearby", "Pick from the mobs that live in the zone you're in. Needs the Questie addon. Shift+click a name to make it your second target.")
Tip(questBtn, "Quests", "Pick a mob you need to kill for one of your quests. Shift+click a name to make it your second target.")
Tip(savedBtn, "Saved", "Your saved names and the names you used recently. Shift+click a name to make it your second target.")
Tip(partialChk, "Match part of the name", "Off: only the exact name. On: any mob whose name contains what you typed, e.g. \"Zanzil\" finds Zanzil Witch Doctor, Zanzil Zombie and the rest. Map dots then show all of them. A name you pick from a list (suggestions, Nearby, Quests, Saved) always means that exact mob; the box shows \"exact\" or \"part\".")
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
	if not mob2Edit:HasFocus() then mob2Edit:SetText(db.mob2) end
	clear2Btn:SetAlpha(TF.Clean(db.mob2) ~= "" and 1 or 0.4)
	if not spellEdit:HasFocus() then spellEdit:SetText(db.spell) end
	tagChk:SetChecked(db.tagMode)
	partialChk:SetChecked(not db.exact)
	-- With "Match part of the name" on, each box says how its name is matched.
	for _, e in ipairs({ { mobEdit, "mob" }, { mob2Edit, "mob2" } }) do
		local edit, n = e[1], TF.Clean(db[e[2]])
		if db.exact or n == "" then edit.mode:SetText("")
		elseif TF.IsExact(n) then edit.mode:SetText("|cff66dd66exact|r")
		else edit.mode:SetText("|cffffd100part|r") end
		edit:SetTextInsets(8, edit.mode:GetText() ~= "" and 40 or 8, 0, 0)
	end
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
	if (db.mapPins or db.miniPins) and #TF.Names() > 0 then
		if TF.pinNote then spots = GREY .. TF.pinNote .. "|r"
		elseif TF.pinCount == 0 then spots = GREY .. "no spots known|r"
		else spots = GREY .. TF.pinCount .. (TF.pinCount == 1 and " spot|r" or " spots|r") end
	end
	spotsText:SetText(spots)

	local body, err = TF.BuildBody()
	local names = TF.Names()
	local name = names[2] and (names[1] .. "|r or " .. WHITE .. names[2]) or (names[1] or "")
	-- a small dot in the same colour as that mob's map dots
	local function Dot(i)
		local c = TF.PIN_COLORS and TF.PIN_COLORS[i]
		if not c then return "" end
		return ("|TInterface\\CharacterFrame\\TempPortraitAlphaMask:10:10:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	end
	if not body then tracking:SetText(GREY .. "Looking for: nobody yet|r")
	elseif names[2] then tracking:SetText("Looking for: " .. Dot(1) .. WHITE .. names[1] .. "|r and " .. Dot(2) .. WHITE .. names[2] .. "|r\n"
		.. GREY .. "Each press of your key switches between them.|r")
	else tracking:SetText("Looking for: " .. WHITE .. names[1] .. "|r") end

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

-- Shift = the second target, everywhere a name is picked.
local function Choose(name, second)
	mobEdit:ClearFocus(); mob2Edit:ClearFocus()
	if second == nil then second = IsShiftKeyDown and IsShiftKeyDown() and true or false end
	Say(TF.Track(name, second, true)) -- picked from a list: that exact mob
end

------------------------------------------------------------------------
-- Type-ahead list shared by the name box and the search box: updates as you type.
-- Click a row, or Up/Down + Enter, or Tab for the top one.
------------------------------------------------------------------------
local MAX_ROWS = 8
local sugg = CreateFrame("Frame", "TargetFinderSuggest", UIParent)
sugg:SetFrameStrata("TOOLTIP")
sugg:SetWidth(250)
sugg:SetClampedToScreen(true)
S.Panel(sugg, 0.98)
S.Border(sugg, 0.26, 0.26, 0.31, 1)
sugg:Hide()
local rows, results, onPick = {}, {}, nil
for i = 1, MAX_ROWS do
	local r = CreateFrame("Button", nil, sugg)
	r:SetSize(238, 16)
	r:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 16)
	local rh = r:CreateTexture(nil, "HIGHLIGHT")
	rh:SetAllPoints()
	rh:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.18)
	r:SetHighlightTexture(rh)
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
	h:SetPoint("LEFT", 8, 0)
	h:SetText(text)
	edit:HookScript("OnTextChanged", function(self) h:SetShown(self:GetText() == "") end)
	h:SetShown(edit:GetText() == "")
	edit.hint = h
end
TF.AddHint = AddHint

-- Typing in a box makes it a typed name again (matched by "Match part of the name").
mobEdit:SetScript("OnTextChanged", function(self, user) if user then TargetFinderDB.mob = self:GetText(); TargetFinderDB.mobPicked = false; Changed() end end)
local function CommitMob(self)
	self:ClearFocus()
	sugg:Hide()
	if TF.BuildBody() then TF.AddRecent(TF.Clean(TargetFinderDB.mob)) end
end
mobEdit:SetScript("OnEnterPressed", CommitMob)
AttachSuggestions(mobEdit, function(name) Choose(name, false) end)
AddHint(mobEdit, "Type a mob's name...")
mob2Edit:SetScript("OnTextChanged", function(self, user) if user then TargetFinderDB.mob2 = self:GetText(); TargetFinderDB.mob2Picked = false; Changed() end end)
mob2Edit:SetScript("OnEnterPressed", function(self)
	self:ClearFocus(); sugg:Hide()
	local n = TF.Clean(TargetFinderDB.mob2)
	if n ~= "" and TF.BuildBody() then TF.AddRecent(n) end
end)
AttachSuggestions(mob2Edit, function(name) Choose(name, true) end)
AddHint(mob2Edit, "Second target (optional)")
clear2Btn:SetScript("OnClick", function() mob2Edit:ClearFocus(); Say(TF.ClearSecond()) end)
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
-- Left and right click only with Shift, Ctrl or Alt held (as in the game's own key bindings).
local MOUSE_MODIFIED = { LeftButton = "BUTTON1", RightButton = "BUTTON2" }

-- a small dark box with a gold line along the top (key capture, quick search)
local function Popup(name, w, h, strata)
	local p = CreateFrame("Frame", name, UIParent)
	p:SetSize(w, h)
	p:SetFrameStrata(strata)
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	S.Panel(p)
	local top = p:CreateTexture(nil, "ARTWORK")
	top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
	top:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
	p:Hide()
	return p
end

local cap = Popup("TargetFinderKeyCapture", 330, 132, "FULLSCREEN_DIALOG")
cap:SetPoint("CENTER", 0, 140)
local capTitle = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
capTitle:SetPoint("TOP", 0, -16)
local capText = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
capText:SetPoint("TOP", 0, -42)
capText:SetWidth(290)
local capCancel = S.Button(cap, "Cancel", 90, 22)
capCancel:SetPoint("BOTTOM", 0, 12)

local capAction, capLabel, capPending
-- While you pick a key, the whole screen takes mouse buttons and the scroll wheel (the box
-- itself sits above it, so Cancel still works).
local catch = CreateFrame("Frame", nil, UIParent)
catch:SetAllPoints(UIParent)
catch:SetFrameStrata("FULLSCREEN")
catch:EnableMouse(true)
catch:Hide()
local function StopCapture()
	cap:EnableKeyboard(false)
	cap:Hide()
	catch:Hide()
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
local function Mouse(_, button)
	if MOUSE[button] then TryKey(Combo(MOUSE[button])) return end
	if MOUSE_MODIFIED[button] and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then
		TryKey(Combo(MOUSE_MODIFIED[button]))
	end
end
local function Wheel(_, delta)
	TryKey(Combo(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
end
for _, f in ipairs({ cap, catch }) do
	f:SetScript("OnMouseDown", Mouse)
	if f.EnableMouseWheel then f:EnableMouseWheel(true) end
	f:SetScript("OnMouseWheel", Wheel)
end

local function StartCapture(action, label)
	if InCombatLockdown() then Say(false, "Keys can't be changed during a fight. Try again after it.") return end
	capAction, capLabel, capPending = action, label, nil
	capTitle:SetText("Set your " .. label .. " key")
	capText:SetText("Press the key you want to use now.\n" .. GREY .. "Shift, Ctrl and Alt work, and so do the\nscroll wheel and mouse buttons. (Esc = cancel)|r")
	catch:Show()
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
S.Group(mm, "TargetFinder", function() return TargetFinderDB and TargetFinderDB.minimap end, UpdateMinimap) -- the shared minimap bag

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
local q = Popup("TargetFinderQuick", 272, 102, "DIALOG")
local qTitle = q:CreateFontString(nil, "OVERLAY", "GameFontNormal")
qTitle:SetPoint("TOPLEFT", 12, -11)
qTitle:SetText("Who are you looking for?")
local qEdit = S.Edit(q, 248, 24)
qEdit:SetPoint("TOPLEFT", 12, -30)
local qHint = q:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
qHint:SetPoint("TOPLEFT", 12, -64)
qHint:SetWidth(248)
qHint:SetJustifyH("LEFT")
local HINT = GREY .. "Up/Down = choose   Enter = pick   Esc = cancel|r\n" .. GREY .. "Shift+Enter = make it your second target|r"

local function QuickTrack(name, picked)
	local ok, msg = TF.Track(name, IsShiftKeyDown and IsShiftKeyDown() and true or false, picked)
	if not ok then qHint:SetText(RED .. msg .. "|r") return end
	TF.Print(msg)
	qEdit:ClearFocus()
	q:Hide()
end
qEdit:SetScript("OnEnterPressed", function(self) TF.HideSuggestions(); QuickTrack(self:GetText()) end)
qEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); q:Hide() end) -- nothing saved
AttachSuggestions(qEdit, function(name) QuickTrack(name, true) end)
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
	if button == "RightButton" and IsControlKeyDown() then
		local _, msg = TF.ClearMob(); TF.Print(msg)
		if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end -- refresh "Looking for"
	elseif button == "RightButton" then TF.QuickEdit(self) else TF.Toggle() end
end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Target Finder")
	GameTooltip:AddLine("Finds a mob for you when you press your key.", 1, 1, 1, true)
	local db = TargetFinderDB
	local names = TF.Names()
	if names[1] then GameTooltip:AddLine("Looking for: " .. WHITE .. table.concat(names, "|r and " .. WHITE) .. "|r", 0.8, 0.8, 0.8) end
	local key = KeyName(TF.BINDING)
	GameTooltip:AddLine("Find key: " .. (key and (GREEN .. key .. "|r") or (ORANGE .. "not set yet|r")), 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(WHITE .. "Left-click|r  open Target Finder", 0.8, 0.8, 0.8)
	GameTooltip:AddLine(WHITE .. "Right-click|r  quick search for a mob", 0.8, 0.8, 0.8)
	GameTooltip:AddLine(WHITE .. "Ctrl + right-click|r  stop looking (clears both)", 0.8, 0.8, 0.8)
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
	if msg == "clear" then
		local _, m = TF.ClearMob(); TF.Print(m)
	elseif msg == "minimap" then
		TargetFinderDB.minimap.hide = not TargetFinderDB.minimap.hide
		UpdateMinimap()
		TF.Print("Minimap button " .. (TargetFinderDB.minimap.hide and "hidden. /tfinder minimap to show it." or "shown."))
	else
		TF.Toggle()
	end
end
