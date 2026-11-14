-- A small set of flat, modern widgets shared by good mens' add-ons (each add-on carries its
-- own copy in its private namespace, so they never clash). No libraries, no Blizzard templates.
local _, ns = ...
local S = {}
ns.Skin = S

S.ACCENT = { 1, 0.82, 0 }
local BG = { 0.055, 0.055, 0.07, 0.97 }
local HEAD = { 0.10, 0.10, 0.13, 1 }
local LINE = { 0.26, 0.26, 0.31, 1 }

local function Color(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1) end

-- 1-pixel border made of four textures
function S.Border(f, r, g, b, a)
	if not f.edges then
		f.edges = {}
		for i = 1, 4 do f.edges[i] = f:CreateTexture(nil, "BORDER") end
		local t, bo, l, ri = f.edges[1], f.edges[2], f.edges[3], f.edges[4]
		t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
		bo:SetPoint("BOTTOMLEFT"); bo:SetPoint("BOTTOMRIGHT"); bo:SetHeight(1)
		l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(1)
		ri:SetPoint("TOPRIGHT"); ri:SetPoint("BOTTOMRIGHT"); ri:SetWidth(1)
	end
	for _, e in ipairs(f.edges) do e:SetColorTexture(r, g, b, a or 1) end
end

-- A plain dark panel (popups, small boxes)
function S.Panel(f, alpha)
	f.goodmensUI = true -- UI Fade leaves our windows and pop-ups solid
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(BG[1], BG[2], BG[3], alpha or BG[4])
	f.bg = bg
	S.Border(f, 0, 0, 0, 1)
	return f
end

local function CloseButton(parent)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(22, 22)
	local lines = {}
	for i, rot in ipairs({ 45, -45 }) do
		local l = c:CreateTexture(nil, "ARTWORK")
		l:SetColorTexture(0.75, 0.75, 0.78, 1)
		l:SetSize(12, 2)
		l:SetPoint("CENTER")
		if not (l.SetRotation and pcall(l.SetRotation, l, math.rad(rot))) then
			l:Hide() -- no rotation on this client: fall back to a letter
			if i == 1 then
				local x = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				x:SetPoint("CENTER"); x:SetText("X")
			end
		end
		lines[i] = l
	end
	local hl = c:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.25, 0.25, 0.25)
	c:SetScript("OnEnter", function() for _, l in ipairs(lines) do l:SetColorTexture(1, 1, 1, 1) end end)
	c:SetScript("OnLeave", function() for _, l in ipairs(lines) do l:SetColorTexture(0.75, 0.75, 0.78, 1) end end)
	return c
end

-- Main window: dark body, title bar with icon, title and version, close button. Escape closes it.
function S.Window(name, title, icon, version, w, h)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(w, h)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	S.Panel(f)
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", 1, -1)
	head:SetPoint("TOPRIGHT", -1, -1)
	head:SetHeight(32)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() f:StartMoving() end)
	head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	local hb = head:CreateTexture(nil, "BACKGROUND")
	hb:SetAllPoints()
	Color(hb, HEAD)
	local accent = head:CreateTexture(nil, "BORDER")
	accent:SetPoint("BOTTOMLEFT"); accent:SetPoint("BOTTOMRIGHT"); accent:SetHeight(1)
	accent:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.55)
	local ic = head:CreateTexture(nil, "ARTWORK")
	ic:SetSize(20, 20)
	ic:SetPoint("LEFT", 9, 0)
	ic:SetTexture(icon)
	ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local t = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("LEFT", ic, "RIGHT", 8, 0)
	t:SetText(title)
	local v = head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	v:SetPoint("LEFT", t, "RIGHT", 8, -1)
	v:SetText(version and ("v" .. version) or "")
	local close = CloseButton(head)
	close:SetPoint("RIGHT", -5, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	f.head, f.close, f.titleText = head, close, t
	f:Hide()
	tinsert(UISpecialFrames, name)
	return f
end

-- A labelled group of options. card.y is a cursor for laying out rows top to bottom.
function S.Card(parent, title, x, y, w, h)
	local c = CreateFrame("Frame", nil, parent)
	c:SetPoint("TOPLEFT", x, y)
	c:SetSize(w, h or 100)
	local bg = c:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.035)
	S.Border(c, 1, 1, 1, 0.08)
	c.top = y
	c.y = -12
	if title then
		local t = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOPLEFT", 12, -10)
		t:SetText(title)
		c.title = t
		c.y = -34
	end
	return c
end

-- Takes the next row of height h from a card; returns its y.
function S.Row(card, h)
	local y = card.y
	card.y = card.y - (h or 24)
	return y
end

-- Fits a card's height to what's in it.
function S.Fit(card, pad) card:SetHeight(-card.y + (pad or 6)) end

-- y for the next card under this one
function S.Below(card, gap) return card.top - card:GetHeight() - (gap or 10) end

function S.Text(parent, text, x, y, font, width)
	local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	l:SetPoint("TOPLEFT", x, y)
	l:SetJustifyH("LEFT")
	if width then l:SetWidth(width) end
	l:SetText(text or "")
	return l
end

-- Small grey help text
function S.Note(parent, text, x, y, width)
	local l = S.Text(parent, text, x, y, "GameFontDisableSmall", width)
	l:SetSpacing(2)
	return l
end

function S.Button(parent, text, w, h, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h or 22)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if primary then
		bg:SetColorTexture(0.42, 0.31, 0.02, 1)
		S.Border(b, 0.85, 0.66, 0.1, 1)
	else
		bg:SetColorTexture(0.15, 0.15, 0.18, 1)
		S.Border(b, LINE[1], LINE[2], LINE[3], 1)
	end
	b.bg = bg
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.09)
	b:SetHighlightTexture(hl)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("CENTER")
	b:SetFontString(fs)
	b:SetNormalFontObject("GameFontHighlight")
	b:SetHighlightFontObject("GameFontHighlight")
	b:SetDisabledFontObject("GameFontDisable")
	b:SetPushedTextOffset(0, -1)
	b:SetText(text or "")
	return b
end

-- Tick box with its label; the label is clickable too. c.label is the text.
function S.Check(parent, label, x, y)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(16, 16)
	if x then c:SetPoint("TOPLEFT", x, y - 4) end
	local bg = c:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.02, 0.03, 1)
	S.Border(c, 0.36, 0.36, 0.42, 1)
	local tick = c:CreateTexture(nil, "ARTWORK")
	tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	tick:SetSize(22, 22)
	tick:SetPoint("CENTER", 1, 1)
	c:SetCheckedTexture(tick)
	local hl = c:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.14)
	c:SetHighlightTexture(hl)
	local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t:SetPoint("LEFT", c, "RIGHT", 8, 0)
	t:SetJustifyH("LEFT")
	c.label = t
	function c.SetLabel(_, s)
		t:SetText(s)
		c:SetHitRectInsets(0, -((t:GetStringWidth() or 100) + 10), -4, -4)
	end
	c:SetLabel(label or "")
	return c
end

-- Text box
function S.Edit(parent, w, h)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(w, h or 24)
	e:SetFontObject("ChatFontNormal")
	e:SetTextInsets(8, 8, 0, 0)
	e:SetAutoFocus(false)
	e:SetMaxLetters(80)
	local bg = e:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.02, 0.03, 1)
	S.Border(e, LINE[1], LINE[2], LINE[3], 1)
	e:HookScript("OnEditFocusGained", function(self) S.Border(self, S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.8) end)
	e:HookScript("OnEditFocusLost", function(self) S.Border(self, LINE[1], LINE[2], LINE[3], 1) end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

-- "Label          [<]  value  [>]" on one row of a card
function S.Stepper(parent, label, x, y, w, get, change)
	local t = S.Text(parent, label, x, y - 5)
	local plus = S.Button(parent, ">", 22, 20)
	plus:SetPoint("TOPLEFT", x + w - 22, y - 2)
	local minus = S.Button(parent, "<", 22, 20)
	minus:SetPoint("TOPLEFT", x + w - 22 - 4 - 104 - 4 - 22, y - 2)
	local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	val:SetWidth(104)
	local function show() val:SetText(get()) end
	plus:SetScript("OnClick", function() change(1); show() end)
	minus:SetScript("OnClick", function() change(-1); show() end)
	return show, t
end

-- Horizontal slider with an accent fill. Set s.onChange(value) for changes from dragging.
function S.Slider(parent, w, lo, hi, step, name)
	local s = CreateFrame("Slider", name, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(w, 16)
	s:SetHitRectInsets(0, 0, -6, -6)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
	track:SetColorTexture(0.22, 0.22, 0.26, 1)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("LEFT")
	fill:SetHeight(4)
	fill:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.85)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(10, 18)
	thumb:SetColorTexture(1, 0.9, 0.45, 1)
	s:SetThumbTexture(thumb)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step or 1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local function paint(v) fill:SetWidth(math.max(1, (v - lo) / (hi - lo) * w)) end
	s:SetScript("OnValueChanged", function(self, v, user)
		paint(v)
		if self.onChange and not self.quiet then self.onChange(v) end
	end)
	function s.Set(_, v) s.quiet = true; s:SetValue(v); paint(v); s.quiet = false end
	return s
end

-- A row of tabs under the title bar; each tab has its own page frame. Returns pages, select(i).
function S.Tabs(win, names, top, bottom)
	local pages, tabs = {}, {}
	local x = 12
	local line = win:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT", 1, top - 28)
	line:SetPoint("TOPRIGHT", -1, top - 28)
	line:SetHeight(1)
	line:SetColorTexture(1, 1, 1, 0.08)
	local function select(i)
		for j, tb in ipairs(tabs) do
			local on = j == i
			pages[j]:SetShown(on)
			tb.under:SetShown(on)
			tb.text:SetTextColor(on and S.ACCENT[1] or 0.7, on and S.ACCENT[2] or 0.7, on and S.ACCENT[3] or 0.72)
		end
		win.tab = i
	end
	for i, name in ipairs(names) do
		local b = CreateFrame("Button", nil, win)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("CENTER", 0, 1)
		fs:SetText(name)
		b.text = fs
		b:SetSize((fs:GetStringWidth() or 60) + 26, 28)
		b:SetPoint("TOPLEFT", x, top)
		x = x + b:GetWidth() + 2
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.05)
		b:SetHighlightTexture(hl)
		local u = b:CreateTexture(nil, "ARTWORK")
		u:SetPoint("BOTTOMLEFT", 6, 0); u:SetPoint("BOTTOMRIGHT", -6, 0); u:SetHeight(2)
		u:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
		b.under = u
		b:SetScript("OnClick", function() select(i) end)
		tabs[i] = b
		local p = CreateFrame("Frame", nil, win)
		p:SetPoint("TOPLEFT", 0, top - 29)
		p:SetPoint("BOTTOMRIGHT", 0, bottom or 0)
		p:Hide()
		pages[i] = p
	end
	select(1)
	return pages, select
end

-- Footer strip along the bottom of a window, for the main buttons.
function S.Footer(win, h)
	local f = CreateFrame("Frame", nil, win)
	f:SetPoint("BOTTOMLEFT", 1, 1)
	f:SetPoint("BOTTOMRIGHT", -1, 1)
	f:SetHeight(h or 40)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.25)
	local line = f:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1)
	line:SetColorTexture(1, 1, 1, 0.08)
	return f
end

-- Plain tooltip on hover
function S.Tip(widget, title, text)
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- "More from good mens": our other add-ons, whether you have them, and where to get them.
-- url = the CurseForge page (nil while it isn't up yet).
------------------------------------------------------------------------
S.FAMILY = {
	{ addon = "LootFlare", title = "Loot Flare", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
	  text = "Your loot pops up mid-screen with rarity glows, sounds, quest progress and upgrades.",
	  url = "https://www.curseforge.com/projects/1799796" },
	{ addon = "ThreatTint", title = "ThreatTint", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	  text = "Colours enemy nameplates by threat, so you see a mob turning on you before it does.",
	  url = "https://www.curseforge.com/projects/1799346" },
	{ addon = "UIFade", title = "UI Fade", icon = "Interface\\Icons\\Spell_Holy_MindVision",
	  text = "Makes the parts of your interface you choose see-through, for a cleaner screen.",
	  url = "https://www.curseforge.com/projects/1799352" },
	{ addon = "TargetFinder", title = "TargetFinder", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
	  text = "Type a mob's name, press one key, and it finds and targets it for you.",
	  url = "https://www.curseforge.com/projects/1799800" },
	{ addon = "HunterReminder", title = "Hunter's Reminder", icon = "Interface\\Icons\\Ability_TrueShot",
	  text = "Hunters: a pulsing reminder when Trueshot Aura or your Aspect is missing.",
	  url = "https://www.curseforge.com/projects/1799809" },
	{ addon = "PetWarn", title = "PetWarn", icon = "Interface\\Icons\\Ability_GhoulFrenzy",
	  text = "Tells you when your pet is standing around in a fight instead of attacking.",
	  url = "https://www.curseforge.com/projects/1799814" },
	{ addon = "FastestWay", title = "Fastest Way To", icon = "Interface\\Icons\\INV_Misc_Map_01",
	  text = "The fastest way anywhere: flights you have, boats, zeppelins and real walking paths.",
	  url = "https://www.curseforge.com/projects/1800442" },
	{ addon = "RangeTint", title = "RangeTint", icon = "Interface\\Icons\\Ability_Marksmanship",
	  text = "Colours your action buttons: red out of range, orange near the edge, purple too close.",
	  url = "https://www.curseforge.com/projects/1801367" },
	{ addon = "FrameCheck", title = "FrameCheck", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	  text = "A tiny, lean FPS box: frame time, add-on cost, ping and a little graph.",
	  url = "https://www.curseforge.com/projects/1804008" },
}

local function AddonState(name)
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	if loaded then
		local ok, on = pcall(loaded, name)
		if ok and on then return "on" end
	end
	if info then
		local ok, found, _, _, _, reason = pcall(info, name)
		if ok and found and reason ~= "MISSING" then return "off" end -- there, just turned off
	end
	return "missing"
end
S.AddonState = AddonState

-- A box with the link selected, ready for Ctrl+C (the game can't open web pages itself).
local copyBox
local function ShowLink(anchor, title, url)
	if not copyBox then
		local p = CreateFrame("Frame", nil, UIParent)
		p:SetSize(330, 84)
		p:SetFrameStrata("FULLSCREEN_DIALOG")
		p:SetClampedToScreen(true)
		p:EnableMouse(true)
		S.Panel(p)
		local top = p:CreateTexture(nil, "ARTWORK")
		top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
		top:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
		p.title = S.Text(p, "", 12, -10, "GameFontNormal")
		p.edit = S.Edit(p, 306, 24)
		p.edit:SetPoint("TOPLEFT", 12, -30)
		p.edit:SetMaxLetters(200)
		p.edit:SetScript("OnTextChanged", function(self) if self:GetText() ~= p.url then self:SetText(p.url); self:HighlightText() end end)
		p.edit:SetScript("OnEscapePressed", function() p:Hide() end)
		p.edit:SetScript("OnEnterPressed", function() p:Hide() end)
		p.note = S.Note(p, "Press Ctrl+C to copy, then paste it into your web browser.", 12, -62)
		copyBox = p
	end
	local p = copyBox
	p.url = url
	p.title:SetText("Get " .. title)
	p:ClearAllPoints()
	p:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
	p:Show()
	p.edit:SetText(url)
	p.edit:SetFocus()
	p.edit:HighlightText()
end

-- The panel itself, opened from a "More addons" button; it sits beside window `win`.
local morePanel
local function BuildMore(selfName)
	local p = CreateFrame("Frame", nil, UIParent)
	p:SetFrameStrata("DIALOG")
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	p:SetToplevel(true)
	S.Panel(p)
	local top = p:CreateTexture(nil, "ARTWORK")
	top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
	top:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
	S.Text(p, "More from good mens", 14, -12, "GameFontNormal")
	local close = CloseButton(p)
	close:SetPoint("TOPRIGHT", -4, -6)
	close:SetScript("OnClick", function() p:Hide() end)
	local W = 360
	local y = -40
	p.rows = {}
	for _, a in ipairs(S.FAMILY) do
		if a.addon ~= selfName then
			local r = CreateFrame("Frame", nil, p)
			r:SetPoint("TOPLEFT", 10, y)
			r:SetSize(W - 20, 68)
			local bg = r:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(1, 1, 1, 0.035)
			S.Border(r, 1, 1, 1, 0.08)
			local ic = r:CreateTexture(nil, "ARTWORK")
			ic:SetSize(32, 32)
			ic:SetPoint("TOPLEFT", 10, -10)
			ic:SetTexture(a.icon)
			ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			local name = S.Text(r, a.title, 52, -9, "GameFontNormal")
			local text = S.Note(r, a.text, 52, -26, W - 20 - 52 - 88)
			local btn = S.Button(r, "", 74, 22)
			btn:SetPoint("RIGHT", -10, 0)
			local status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			status:SetPoint("RIGHT", -12, 0)
			function r.Update()
				local st = AddonState(a.addon)
				if st == "on" then
					btn:Hide(); status:Show(); status:SetText("|cff33ff33Installed|r")
				elseif st == "off" then
					btn:Hide(); status:Show(); status:SetText("|cffffd100Installed, off|r")
				elseif a.url then
					status:Hide(); btn:Show(); btn:SetText("Get it")
				else
					btn:Hide(); status:Show(); status:SetText("|cff9d9d9dComing soon|r")
				end
			end
			btn:SetScript("OnClick", function() ShowLink(btn, a.title, a.url) end)
			S.Tip(btn, a.title, "Shows the CurseForge link to copy.")
			p.rows[#p.rows + 1] = r
			y = y - 74
		end
	end
	S.Note(p, "Made by good mens (Mephz on WoW Forever)", 14, y - 6)
	p:SetSize(W, -y + 30)
	p:SetScript("OnShow", function() for _, r in ipairs(p.rows) do r.Update() end end)
	p:SetScript("OnHide", function() if copyBox then copyBox:Hide() end end)
	p:Hide()
	return p
end

-- Opens (or closes) the "More from good mens" panel: beside window `win`, or mid-screen without one.
function S.OpenMore(selfName, win)
	morePanel = morePanel or BuildMore(selfName)
	if morePanel:IsShown() then morePanel:Hide() return end
	morePanel:ClearAllPoints()
	if win then
		morePanel:SetPoint("TOPLEFT", win, "TOPRIGHT", 6, 0)
	else
		morePanel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	morePanel:Show()
end

-- A small "More addons" button. selfName = this add-on's folder name (left out of the list);
-- win = the window the panel opens beside.
function S.MoreButton(parent, selfName, win)
	local b = S.Button(parent, "More addons", 96, 20)
	b:SetScript("OnClick", function() S.OpenMore(selfName, win) end)
	S.Tip(b, "More from good mens", "Our other add-ons for WoW Forever, and where to get them.")
	if win then win:HookScript("OnHide", function() if morePanel then morePanel:Hide() end end) end
	return b
end

------------------------------------------------------------------------
-- One minimap button for all of our add-ons. Each add-on hands its own minimap button to
-- S.Group; while two or more are grouped, they leave the minimap and a single "good mens"
-- button takes their place. Click it and they pop out in a small panel (left- and right-click
-- work as on their own buttons). Right-click it to choose which add-ons stay separate.
-- Shared by every add-on that carries this file: the first one loaded builds it.
------------------------------------------------------------------------
local HUB_ICON = "Interface\\Icons\\INV_Misc_Bag_10_Blue"

local function BuildHub()
	local H = { members = {} }
	local atan2 = math.atan2 or function(a, b) return math.atan(a, b) end

	-- Settings live in each add-on's own minimap table: .grouped = false keeps it separate,
	-- .hubAngle is where the group button sits (written to every member, read from any).
	local function Store(m) local ok, t = pcall(m.store); return ok and type(t) == "table" and t or nil end
	function H.IsGrouped(m) local t = Store(m); return not (t and t.grouped == false) end
	local function Angle()
		for _, m in ipairs(H.members) do local t = Store(m); if t and t.hubAngle then return t.hubAngle end end
		return 180
	end
	local function SetAngle(a) for _, m in ipairs(H.members) do local t = Store(m); if t then t.hubAngle = a end end end

	-- The group button, in the same style as the add-ons' own.
	local b = CreateFrame("Button", "GoodMensMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	b.goodmensUI = true
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(HUB_ICON)
	icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53); border:SetPoint("TOPLEFT")
	b:Hide()
	H.button = b
	local function Place()
		local a = math.rad(Angle())
		local r = (Minimap:GetWidth() / 2) + 5
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
	end
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			SetAngle(math.deg(atan2(cy / s - my, cx / s - mx)))
			Place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	-- The pop-out panel: one row per grouped add-on (its icon and name).
	local p = CreateFrame("Frame", "GoodMensMinimapPanel", UIParent)
	p:SetFrameStrata("DIALOG")
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	S.Panel(p, 0.97)
	S.Border(p, 0.26, 0.26, 0.31, 1)
	p:Hide()
	tinsert(UISpecialFrames, "GoodMensMinimapPanel") -- Escape closes it
	local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText("good mens add-ons")
	local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetJustifyH("LEFT")
	local rows = {}
	local function Row(i)
		local r = rows[i]
		if r then return r end
		r = CreateFrame("Button", nil, p)
		r:SetSize(176, 22)
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.16)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.text:SetJustifyH("LEFT")
		-- Clicks and tooltips are the add-on's own button's, as if you'd used that button.
		r:SetScript("OnClick", function(self, which)
			local m = self.member
			p:Hide()
			local f = m and m.button:GetScript("OnClick")
			if f then f(m.button, which) end
		end)
		r:SetScript("OnEnter", function(self)
			local f = self.member and self.member.button:GetScript("OnEnter")
			if f then pcall(f, self) end
			if GameTooltip:IsOwned(self) then
				GameTooltip:ClearAllPoints()
				GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 12, 0)
			end
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = r
		return r
	end
	local function Fill()
		local list = {}
		for _, m in ipairs(H.members) do if H.IsGrouped(m) then list[#list + 1] = m end end
		table.sort(list, function(x, y) return x.title < y.title end)
		for i, r in ipairs(rows) do r:Hide() end
		local y = -24
		for i, m in ipairs(list) do
			local r = Row(i)
			r.member = m
			r.icon:SetTexture(m.icon)
			r.text:SetText(m.title)
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 6, y)
			r:Show()
			y = y - 22
		end
		hint:ClearAllPoints(); hint:SetPoint("TOPLEFT", 10, y - 4)
		hint:SetText("Right-click the bag to choose\nwhich ones stay separate.")
		p:SetSize(188, -y + 36)
	end
	-- Closes once the mouse has been away from it and the bag for a moment.
	local away = 0
	p:SetScript("OnUpdate", function(self, dt)
		if self:IsMouseOver() or b:IsMouseOver() or (GameTooltip:IsShown() and GameTooltip:IsMouseOver()) then away = 0 return end
		away = away + dt
		if away > 1.2 then self:Hide() end
	end)
	p:SetScript("OnShow", function() away = 0 end)

	local function Open()
		if p:IsShown() then p:Hide() return end
		Fill()
		p:ClearAllPoints()
		local cx = b:GetCenter()
		local mx = Minimap:GetCenter()
		if cx and mx and cx < mx then p:SetPoint("TOPLEFT", b, "BOTTOMRIGHT", 0, 4)
		else p:SetPoint("TOPRIGHT", b, "BOTTOMLEFT", 0, 4) end
		p:Show()
	end
	local function ChooseMenu(owner)
		if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
		MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateTitle("In the bag (untick to keep its own button)")
			local list = {}
			for _, m in ipairs(H.members) do list[#list + 1] = m end
			table.sort(list, function(x, y) return x.title < y.title end)
			for _, m in ipairs(list) do
				root:CreateCheckbox(m.title, function() return H.IsGrouped(m) end, function()
					local t = Store(m)
					if t then t.grouped = not H.IsGrouped(m) end
					H.Refresh()
				end)
			end
		end)
	end
	b:SetScript("OnClick", function(self, which)
		if which == "RightButton" then p:Hide(); ChooseMenu(self) else Open() end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("good mens add-ons")
		local names = {}
		for _, m in ipairs(H.members) do if H.IsGrouped(m) then names[#names + 1] = m.title end end
		table.sort(names)
		GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("|cffffffffClick|r  show them", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffffffRight-click|r  choose which ones are in here", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Grouping needs two: with one add-on alone it keeps its own button.
	local hiding = false
	function H.Refresh()
		local n = 0
		for _, m in ipairs(H.members) do if H.IsGrouped(m) then n = n + 1 end end
		H.active = n >= 2
		hiding = true
		for _, m in ipairs(H.members) do
			if H.active and H.IsGrouped(m) then
				m.button:Hide()
			elseif m.update then
				pcall(m.update) -- its own show/hide setting decides
			end
		end
		hiding = false
		if H.active then Place(); b:Show() else b:Hide(); p:Hide() end
		if p:IsShown() then Fill() end
	end

	-- button: the add-on's minimap button; addon: its folder name; store(): its minimap settings
	-- table; update(): shows or hides its button by its own setting.
	function H.Add(button, addon, store, update)
		local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
		local m = {
			button = button, store = store, update = update,
			title = (meta and meta(addon, "Title")) or addon,
			icon = (meta and meta(addon, "IconTexture")) or "Interface\\Icons\\INV_Misc_QuestionMark",
		}
		m.title = tostring(m.title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		H.members[#H.members + 1] = m
		-- Whenever the add-on shows its button, it goes back in the bag if it's grouped.
		hooksecurefunc(button, "Show", function(self)
			if not hiding and H.active and H.IsGrouped(m) then self:Hide() end
		end)
		if H.ready then H.Refresh() end
	end

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_LOGIN")
	ev:SetScript("OnEvent", function()
		H.ready = true
		H.Refresh()
		if C_Timer and C_Timer.After then C_Timer.After(1, H.Refresh) end -- after every add-on placed its button
	end)
	return H
end

-- Hands an add-on's minimap button to the shared group button.
function S.Group(button, addon, store, update)
	if not button then return end
	local H = _G.GoodMensMinimapGroup
	if not H then
		H = BuildHub()
		_G.GoodMensMinimapGroup = H
	end
	H.Add(button, addon, store, update)
end
