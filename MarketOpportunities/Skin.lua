-- A small set of widgets shared by good mens' add-ons (each add-on carries its own copy in its
-- private namespace, so they never clash). No libraries. Several looks ("themes") and accent
-- colours: picking one repaints every window of every good mens add-on at once, and it's saved.
local ADDON, ns = ...
local S = {}
ns.Skin = S

S.ACCENT = { 1, 0.82, 0 }

------------------------------------------------------------------------
-- Looks
------------------------------------------------------------------------
local DIALOG = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TOOLTIP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 } }

S.THEMES = {
	{ key = "modern", name = "Modern",
	  bg = { 0.055, 0.055, 0.07, 0.97 }, head = { 0.10, 0.10, 0.13, 1 }, edge = { 0, 0, 0, 1 },
	  line = { 0.26, 0.26, 0.31, 1 }, card = { 1, 1, 1, 0.035 }, cardEdge = { 1, 1, 1, 0.08 },
	  btn = { 0.15, 0.15, 0.18, 1 }, input = { 0.02, 0.02, 0.03, 1 }, box = { 0.36, 0.36, 0.42, 1 },
	  footer = { 0, 0, 0, 0.25 }, accentLine = 0.55 },
	{ key = "pixel", name = "Pixel (ElvUI style)",
	  bg = { 0.06, 0.06, 0.06, 0.93 }, head = { 0.09, 0.09, 0.09, 1 }, edge = { 0, 0, 0, 1 },
	  line = { 0, 0, 0, 1 }, card = { 0.1, 0.1, 0.1, 0.8 }, cardEdge = { 0, 0, 0, 1 },
	  btn = { 0.11, 0.11, 0.11, 1 }, input = { 0.03, 0.03, 0.03, 1 }, box = { 0, 0, 0, 1 },
	  footer = { 0.08, 0.08, 0.08, 1 }, accentLine = 1, font = "Fonts\\ARIALN.TTF", fontFlags = "OUTLINE", fontAdd = 1 },
	{ key = "classic", name = "Classic (Blizzard)", classic = true,
	  bg = { 0, 0, 0, 0 }, head = { 0, 0, 0, 0 }, edge = { 0, 0, 0, 0 },
	  line = { 0.55, 0.47, 0.3, 1 }, card = { 0, 0, 0, 0 }, cardEdge = { 0, 0, 0, 0 },
	  btn = { 0.15, 0.15, 0.18, 1 }, input = { 0, 0, 0, 0.65 }, box = { 0.55, 0.47, 0.3, 1 },
	  footer = { 0, 0, 0, 0 }, accentLine = 0 },
	{ key = "glass", name = "Glass (sleek, see-through)",
	  bg = { 0.035, 0.06, 0.1, 0.74 }, head = { 0.06, 0.1, 0.16, 0.82 }, edge = { 0.55, 0.75, 1, 0.28 },
	  line = { 0.42, 0.58, 0.78, 0.5 }, card = { 1, 1, 1, 0.05 }, cardEdge = { 0.55, 0.75, 1, 0.16 },
	  btn = { 0.09, 0.15, 0.23, 0.88 }, input = { 0.01, 0.03, 0.06, 0.85 }, box = { 0.42, 0.58, 0.78, 0.6 },
	  footer = { 0, 0, 0, 0.18 }, accentLine = 0.85 },
	{ key = "midnight", name = "Midnight (deep purple)",
	  bg = { 0.06, 0.04, 0.1, 0.96 }, head = { 0.11, 0.07, 0.17, 1 }, edge = { 0, 0, 0, 1 },
	  line = { 0.3, 0.22, 0.42, 1 }, card = { 0.6, 0.4, 1, 0.05 }, cardEdge = { 0.6, 0.4, 1, 0.16 },
	  btn = { 0.16, 0.11, 0.24, 1 }, input = { 0.03, 0.02, 0.05, 1 }, box = { 0.4, 0.3, 0.55, 1 },
	  footer = { 0, 0, 0, 0.3 }, accentLine = 0.6 },
	{ key = "light", name = "Stone (light grey)",
	  bg = { 0.2, 0.2, 0.22, 0.97 }, head = { 0.27, 0.27, 0.3, 1 }, edge = { 0, 0, 0, 1 },
	  line = { 0.45, 0.45, 0.5, 1 }, card = { 1, 1, 1, 0.06 }, cardEdge = { 1, 1, 1, 0.14 },
	  btn = { 0.3, 0.3, 0.34, 1 }, input = { 0.1, 0.1, 0.11, 1 }, box = { 0.55, 0.55, 0.6, 1 },
	  footer = { 0, 0, 0, 0.2 }, accentLine = 0.7 },
}
S.ACCENTS = {
	{ key = "gold", name = "Gold", c = { 1, 0.82, 0 } },
	{ key = "class", name = "Class colour" },
	{ key = "blue", name = "Sky blue", c = { 0.3, 0.7, 1 } },
	{ key = "green", name = "Fel green", c = { 0.35, 0.95, 0.3 } },
	{ key = "red", name = "Blood red", c = { 1, 0.28, 0.25 } },
	{ key = "purple", name = "Arcane purple", c = { 0.75, 0.45, 1 } },
	{ key = "white", name = "Ice white", c = { 0.9, 0.95, 1 } },
}

-- The chosen look is shared by every good mens add-on loaded (the first one loaded makes the table).
local LOOK = _G.GoodMensLook
if type(LOOK) ~= "table" or not LOOK.copies then
	LOOK = { theme = "modern", accent = "gold", t = 0, copies = {}, stores = {} }
	_G.GoodMensLook = LOOK
end

local function Find(list, key) for _, x in ipairs(list) do if x.key == key then return x end end end
local function T() return Find(S.THEMES, LOOK.theme) or S.THEMES[1] end
function S.Theme() return T() end
function S.LookKeys() return LOOK.theme, LOOK.accent end

local function AccentColor(key)
	local a = Find(S.ACCENTS, key) or S.ACCENTS[1]
	if a.key == "class" then
		local class = UnitClass and select(2, UnitClass("player"))
		local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if c then return { c.r, c.g, c.b } end
		return S.ACCENTS[1].c
	end
	return a.c
end

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
local function Edge(f, c) S.Border(f, c[1], c[2], c[3], c[4] or 1) end

-- Blizzard's own frame art (Classic look), put on any frame; nil takes it off again
local function Backdrop(f, info, bg, border)
	if not f.SetBackdrop then
		if not (info and BackdropTemplateMixin and Mixin) then return end
		Mixin(f, BackdropTemplateMixin)
		if f.OnBackdropSizeChanged then f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged) end
	end
	if not pcall(f.SetBackdrop, f, info) then return end
	if info and bg and f.SetBackdropColor then f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1) end
	if info and border and f.SetBackdropBorderColor then f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1) end
end

-- Font strings follow the look too (Pixel uses a narrow outlined font)
local function FontOf(fs, objName)
	fs.lookFont = objName
	local o = objName and _G[objName]
	if o and o.GetFont then
		local ok, file, size, flags = pcall(o.GetFont, o)
		if ok and size then fs.lookSize, fs.lookFlags = size, flags end
	end
end
local function PaintFont(fs, th)
	if not fs.lookFont then return end
	if th.font and fs.lookSize and fs.SetFont then
		pcall(fs.SetFont, fs, th.font, fs.lookSize + (th.fontAdd or 0), th.fontFlags or "")
	elseif fs.SetFontObject then
		pcall(fs.SetFontObject, fs, fs.lookFont)
	end
end

-- Everything this copy made, so a new look can repaint it in place.
local mine, fonts = {}, {}
local paint = {}

function paint.panel(f, th)
	if th.classic then
		Backdrop(f, TOOLTIP, { 0.05, 0.05, 0.05, f.lookAlpha or 0.95 }, { 0.75, 0.65, 0.45, 1 })
		f.bg:SetColorTexture(0, 0, 0, 0)
		Edge(f, { 0, 0, 0, 0 })
	else
		Backdrop(f, nil)
		Color(f.bg, th.bg, f.lookAlpha and math.min(f.lookAlpha, th.bg[4]) or th.bg[4])
		Edge(f, th.edge)
	end
end
function paint.window(f, th)
	if th.classic then
		Backdrop(f, DIALOG, { 1, 1, 1, 1 }, { 1, 1, 1, 1 })
		f.bg:SetColorTexture(0, 0, 0, 0)
		Edge(f, { 0, 0, 0, 0 })
	else
		Backdrop(f, nil)
		Color(f.bg, th.bg)
		Edge(f, th.edge)
	end
	Color(f.headBg, th.head)
	f.headLine:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], th.accentLine)
end
function paint.card(c, th)
	if th.classic then
		Backdrop(c, TOOLTIP, { 0, 0, 0, 0.35 }, { 0.6, 0.52, 0.35, 0.9 })
	else
		Backdrop(c, nil)
	end
	Color(c.bg, th.card)
	Edge(c, th.cardEdge)
end
function paint.button(b, th)
	if th.classic then
		b.bg:SetTexture(b.primary and "Interface\\Buttons\\UI-Panel-Button-Up" or "Interface\\Buttons\\UI-Panel-Button-Up")
		if b.bg.SetTexCoord then b.bg:SetTexCoord(0, 0.625, 0, 0.6875) end
		Edge(b, { 0, 0, 0, 0 })
	else
		if b.bg.SetTexCoord then b.bg:SetTexCoord(0, 1, 0, 1) end
		if b.primary then
			local a = S.ACCENT
			b.bg:SetColorTexture(a[1] * 0.42, a[2] * 0.42, a[3] * 0.42, 1)
			S.Border(b, math.min(1, a[1] * 0.9), math.min(1, a[2] * 0.9), math.min(1, a[3] * 0.9), 1)
		else
			Color(b.bg, th.btn)
			Edge(b, th.line)
		end
	end
end
function paint.check(c, th)
	Color(c.bg, th.input)
	Edge(c, th.box)
end
function paint.edit(e, th)
	Color(e.bg, th.input)
	if e.HasFocus and e:HasFocus() then S.Border(e, S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.8) else Edge(e, th.line) end
end
function paint.footer(f, th)
	Color(f.bg, th.footer)
end
function paint.slider(s)
	s.fill:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.85)
	s.thumb:SetColorTexture(math.min(1, S.ACCENT[1] + 0.2), math.min(1, S.ACCENT[2] + 0.2), math.min(1, S.ACCENT[3] + 0.2), 1)
end
function paint.accent(t)
	t:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], t.lookAlpha or 1)
end

local function Track(kind, f)
	mine[#mine + 1] = { kind = kind, f = f }
	pcall(paint[kind], f, T())
	return f
end
local function TrackFont(fs, objName)
	FontOf(fs, objName)
	fonts[#fonts + 1] = fs
	PaintFont(fs, T())
	return fs
end

-- Repaints what this copy made
local function RepaintMine()
	local c = AccentColor(LOOK.accent)
	S.ACCENT[1], S.ACCENT[2], S.ACCENT[3] = c[1], c[2], c[3]
	local th = T()
	for _, e in ipairs(mine) do pcall(paint[e.kind], e.f, th) end
	for _, fs in ipairs(fonts) do PaintFont(fs, th) end
	if S.onLook then pcall(S.onLook) end
end
LOOK.copies[#LOOK.copies + 1] = RepaintMine

local function RepaintAll() for _, f in ipairs(LOOK.copies) do pcall(f) end end

-- Picks a look (theme and/or accent), saves it with every add-on and repaints them all
function S.SetLook(theme, accent)
	if theme and Find(S.THEMES, theme) then LOOK.theme = theme end
	if accent and Find(S.ACCENTS, accent) then LOOK.accent = accent end
	LOOK.t = (time and time()) or (os and os.time and os.time()) or (LOOK.t + 1)
	for _, st in ipairs(LOOK.stores) do st.theme, st.accent, st.t = LOOK.theme, LOOK.accent, LOOK.t end
	RepaintAll()
end

-- Each add-on keeps a copy in its own saved variable (<Addon>Look); the newest one wins.
-- Saved variables are in place once the add-on's files have run, so a timer (no event frame) reads them.
function S.LoadLook()
	local key = tostring(ADDON) .. "Look"
	local st = _G[key]
	if type(st) ~= "table" then st = {}; _G[key] = st end
	local known = false
	for _, x in ipairs(LOOK.stores) do if x == st then known = true end end
	if not known then LOOK.stores[#LOOK.stores + 1] = st end
	if (tonumber(st.t) or 0) > (LOOK.t or 0) and Find(S.THEMES, st.theme) then
		LOOK.theme, LOOK.accent, LOOK.t = st.theme, st.accent or LOOK.accent, st.t
		RepaintAll()
	else
		st.theme, st.accent, st.t = LOOK.theme, LOOK.accent, LOOK.t
		RepaintMine()
	end
end
if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(S.LoadLook) end) end

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------

-- A plain panel (popups, small boxes)
function S.Panel(f, alpha)
	f.goodmensUI = true -- UI Fade leaves our windows and pop-ups solid
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	f.bg, f.lookAlpha = bg, alpha
	S.Border(f, 0, 0, 0, 1)
	return Track("panel", f)
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

-- Main window: body, title bar with icon, title and version, close button. Escape closes it.
function S.Window(name, title, icon, version, w, h)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(w, h)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f.goodmensUI = true
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	f.bg = bg
	S.Border(f, 0, 0, 0, 1)
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", 1, -1)
	head:SetPoint("TOPRIGHT", -1, -1)
	head:SetHeight(32)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() f:StartMoving() end)
	head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	f.headBg = head:CreateTexture(nil, "BACKGROUND")
	f.headBg:SetAllPoints()
	f.headLine = head:CreateTexture(nil, "BORDER")
	f.headLine:SetPoint("BOTTOMLEFT"); f.headLine:SetPoint("BOTTOMRIGHT"); f.headLine:SetHeight(1)
	local ic = head:CreateTexture(nil, "ARTWORK")
	ic:SetSize(20, 20)
	ic:SetPoint("LEFT", 9, 0)
	ic:SetTexture(icon)
	ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local t = TrackFont(head:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "GameFontNormal")
	t:SetPoint("LEFT", ic, "RIGHT", 8, 0)
	t:SetText(title)
	local v = TrackFont(head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "GameFontDisableSmall")
	v:SetPoint("LEFT", t, "RIGHT", 8, -1)
	v:SetText(version and ("v" .. version) or "")
	local close = CloseButton(head)
	close:SetPoint("RIGHT", -5, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	f.head, f.close, f.titleText = head, close, t
	f:Hide()
	tinsert(UISpecialFrames, name)
	return Track("window", f)
end

-- A labelled group of options. card.y is a cursor for laying out rows top to bottom.
function S.Card(parent, title, x, y, w, h)
	local c = CreateFrame("Frame", nil, parent)
	c:SetPoint("TOPLEFT", x, y)
	c:SetSize(w, h or 100)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	S.Border(c, 1, 1, 1, 0.08)
	c.top = y
	c.y = -12
	if title then
		local t = TrackFont(c:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "GameFontNormal")
		t:SetPoint("TOPLEFT", 12, -10)
		t:SetText(title)
		c.title = t
		c.y = -34
	end
	return Track("card", c)
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
	local l = TrackFont(parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight"), font or "GameFontHighlight")
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
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.primary = primary
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.09)
	b:SetHighlightTexture(hl)
	local fs = TrackFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "GameFontHighlight")
	fs:SetPoint("CENTER")
	b:SetFontString(fs)
	b:SetNormalFontObject("GameFontHighlight")
	b:SetHighlightFontObject("GameFontHighlight")
	b:SetDisabledFontObject("GameFontDisable")
	b:SetPushedTextOffset(0, -1)
	b:SetText(text or "")
	return Track("button", b)
end

-- Tick box with its label; the label is clickable too. c.label is the text.
function S.Check(parent, label, x, y)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(16, 16)
	if x then c:SetPoint("TOPLEFT", x, y - 4) end
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	local tick = c:CreateTexture(nil, "ARTWORK")
	tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	tick:SetSize(22, 22)
	tick:SetPoint("CENTER", 1, 1)
	c:SetCheckedTexture(tick)
	local hl = c:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.14)
	c:SetHighlightTexture(hl)
	local t = TrackFont(c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "GameFontHighlight")
	t:SetPoint("LEFT", c, "RIGHT", 8, 0)
	t:SetJustifyH("LEFT")
	c.label = t
	function c.SetLabel(_, s)
		t:SetText(s)
		c:SetHitRectInsets(0, -((t:GetStringWidth() or 100) + 10), -4, -4)
	end
	c:SetLabel(label or "")
	return Track("check", c)
end

-- Text box
function S.Edit(parent, w, h)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(w, h or 24)
	e:SetFontObject("ChatFontNormal")
	e:SetTextInsets(8, 8, 0, 0)
	e:SetAutoFocus(false)
	e:SetMaxLetters(80)
	e.bg = e:CreateTexture(nil, "BACKGROUND")
	e.bg:SetAllPoints()
	e:HookScript("OnEditFocusGained", function(self) S.Border(self, S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.8) end)
	e:HookScript("OnEditFocusLost", function(self) Edge(self, T().line) end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return Track("edit", e)
end

-- "Label          [<]  value  [>]" on one row of a card
function S.Stepper(parent, label, x, y, w, get, change)
	local t = S.Text(parent, label, x, y - 5)
	local plus = S.Button(parent, ">", 22, 20)
	plus:SetPoint("TOPLEFT", x + w - 22, y - 2)
	local minus = S.Button(parent, "<", 22, 20)
	minus:SetPoint("TOPLEFT", x + w - 22 - 4 - 104 - 4 - 22, y - 2)
	local val = TrackFont(parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "GameFontHighlight")
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
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(10, 18)
	s:SetThumbTexture(thumb)
	s.fill, s.thumb = fill, thumb
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step or 1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local function paintFill(v) fill:SetWidth(math.max(1, (v - lo) / (hi - lo) * w)) end
	s:SetScript("OnValueChanged", function(self, v, user)
		paintFill(v)
		if self.onChange and not self.quiet then self.onChange(v) end
	end)
	function s.Set(_, v) s.quiet = true; s:SetValue(v); paintFill(v); s.quiet = false end
	return Track("slider", s)
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
		local fs = TrackFont(b:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "GameFontNormal")
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
		Track("accent", u)
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
	-- a new accent recolours the selected tab's text too
	local before = S.onLook
	S.onLook = function() if before then before() end; select(win.tab or 1) end
	return pages, select
end

-- Footer strip along the bottom of a window, for the main buttons.
function S.Footer(win, h)
	local f = CreateFrame("Frame", nil, win)
	f:SetPoint("BOTTOMLEFT", 1, 1)
	f:SetPoint("BOTTOMRIGHT", -1, 1)
	f:SetHeight(h or 40)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	local line = f:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1)
	line:SetColorTexture(1, 1, 1, 0.08)
	return Track("footer", f)
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

-- A drop-down: a button showing the current choice; click it for the list.
-- items = { {key=, name=}, ... }; get() returns the current key; set(key) is called on a pick.
local ddMenu
function S.Dropdown(parent, w, items, get, set)
	local b = S.Button(parent, "", w, 22)
	local function show()
		local cur = get()
		local name = items[1] and items[1].name or ""
		for _, it in ipairs(items) do if it.key == cur then name = it.name end end
		b:SetText(name .. "  |cffffd100v|r")
	end
	b:SetScript("OnClick", function(self)
		if not ddMenu then
			ddMenu = CreateFrame("Frame", nil, UIParent)
			ddMenu:SetFrameStrata("FULLSCREEN_DIALOG")
			ddMenu:EnableMouse(true)
			S.Panel(ddMenu, 1)
			ddMenu.rows = {}
			ddMenu:Hide()
		end
		local m = ddMenu
		if m:IsShown() and m.owner == self then m:Hide() return end
		m.owner = self
		for _, r in ipairs(m.rows) do r:Hide() end
		local cur = get()
		for i, it in ipairs(items) do
			local r = m.rows[i]
			if not r then
				r = CreateFrame("Button", nil, m)
				r:SetHeight(20)
				local hl = r:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(1, 0.82, 0, 0.15)
				r.text = TrackFont(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "GameFontHighlightSmall")
				r.text:SetPoint("LEFT", 20, 0)
				r.tick = r:CreateTexture(nil, "OVERLAY")
				r.tick:SetSize(14, 14)
				r.tick:SetPoint("LEFT", 3, 0)
				r.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
				m.rows[i] = r
			end
			r:SetWidth(w - 8)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
			r.text:SetText(it.name)
			r.tick:SetShown(it.key == cur)
			r.key = it.key
			r:SetScript("OnClick", function() m:Hide(); set(it.key); show() end)
			r:Show()
		end
		m:SetSize(w, #items * 20 + 8)
		m:ClearAllPoints()
		m:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
		m:Show()
	end)
	b:HookScript("OnHide", function() if ddMenu and ddMenu.owner == b then ddMenu:Hide() end end)
	b.Refresh = show
	show()
	return b
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

-- Where people can support good mens (shown at the bottom of the panel).
S.SUPPORT_URL = "https://ko-fi.com/mephzgoodmens"

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
local function ShowLink(anchor, title, url, heading)
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
	p.title:SetText(heading or ("Get " .. title))
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
	-- the look of every good mens add-on: theme and accent colour (saved, shared by all of them)
	local look = CreateFrame("Frame", nil, p)
	look:SetPoint("TOPLEFT", 10, -36)
	look:SetSize(W - 20, 52)
	local lbg = look:CreateTexture(nil, "BACKGROUND")
	lbg:SetAllPoints()
	lbg:SetColorTexture(1, 1, 1, 0.035)
	S.Text(look, "Look", 10, -8, "GameFontNormalSmall")
	S.Text(look, "Accent", 188, -8, "GameFontNormalSmall")
	local themeDD = S.Dropdown(look, 170, S.THEMES, function() return (S.LookKeys()) end, function(k) S.SetLook(k, nil) end)
	themeDD:SetPoint("TOPLEFT", 8, -24)
	local accentDD = S.Dropdown(look, 150, S.ACCENTS, function() return select(2, S.LookKeys()) end, function(k) S.SetLook(nil, k) end)
	accentDD:SetPoint("TOPLEFT", 184, -24)
	S.Tip(themeDD, "Look", "Changes the look of every good mens add-on at once: Modern, Pixel (ElvUI style), Classic (Blizzard), Glass, Midnight or Stone.")
	S.Tip(accentDD, "Accent colour", "The highlight colour for titles, tabs, sliders and buttons, in every good mens add-on.")
	p.lookDD = { themeDD, accentDD }
	local y = -96
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
	-- support: these add-ons are free; a link to Ko-fi for anyone who'd like to say thanks
	local sup = CreateFrame("Frame", nil, p)
	sup:SetPoint("TOPLEFT", 10, y)
	sup:SetSize(W - 20, 52)
	local sbg = sup:CreateTexture(nil, "BACKGROUND")
	sbg:SetAllPoints()
	sbg:SetColorTexture(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.08)
	S.Border(sup, S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.35)
	local sic = sup:CreateTexture(nil, "ARTWORK")
	sic:SetSize(28, 28)
	sic:SetPoint("LEFT", 10, 0)
	sic:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	sic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	S.Text(sup, "Like these add-ons?", 48, -9, "GameFontNormal")
	S.Note(sup, "They're free. If they help you, you can buy me a coffee.", 48, -26, W - 20 - 48 - 88)
	local kofi = S.Button(sup, "Ko-fi", 74, 22)
	kofi:SetPoint("RIGHT", -10, 0)
	kofi:SetScript("OnClick", function() ShowLink(kofi, "Ko-fi", S.SUPPORT_URL, "Support good mens on Ko-fi") end)
	S.Tip(kofi, "Support good mens", "Shows the Ko-fi link to copy. Thank you!")
	y = y - 58
	S.Note(p, "Made by good mens (Mephz on WoW Forever)", 14, y - 6)
	p:SetSize(W, -y + 30)
	p:SetScript("OnShow", function()
		for _, r in ipairs(p.rows) do r.Update() end
		for _, d in ipairs(p.lookDD) do d.Refresh() end
	end)
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
