-- Loot Flare extras: the big banner for good drops, and the gold-per-hour tracker.
local _, ns = ...
local Skin = ns.Skin
local LF = LootFlare
local floor, min, max, sin, pi = math.floor, math.min, math.max, math.sin, math.pi
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

------------------------------------------------------------------------
-- Big banner: "EPIC!" across the top of the screen, with an optional screen-edge glow
------------------------------------------------------------------------
local WORDS = { [3] = "RARE!", [4] = "EPIC!", [5] = "LEGENDARY!", [6] = "ARTIFACT!", [7] = "HEIRLOOM!" }
local SHOW = 2.6

local banner = CreateFrame("Frame", "LootFlareBanner", UIParent)
banner:SetSize(600, 110)
banner:SetFrameStrata("HIGH")
banner:Hide()

local function Gradient(tex, r, g, b, fromA, toA)
	tex:SetColorTexture(1, 1, 1, 1)
	if CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r, g, b, fromA), CreateColor(r, g, b, toA)) then return end
	if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, "HORIZONTAL", r, g, b, fromA, r, g, b, toA) then return end
	tex:SetColorTexture(r, g, b, 0.3)
end

local glowL = banner:CreateTexture(nil, "BACKGROUND")
glowL:SetPoint("RIGHT", banner, "CENTER")
glowL:SetSize(300, 70)
local glowR = banner:CreateTexture(nil, "BACKGROUND")
glowR:SetPoint("LEFT", banner, "CENTER")
glowR:SetSize(300, 70)

local word = banner:CreateFontString(nil, "OVERLAY")
word:SetPoint("TOP", 0, -10)
if not word:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 40, "THICKOUTLINE") then
	word:SetFontObject("GameFontNormalHuge")
end
word:SetShadowOffset(2, -2)

local itemIcon = banner:CreateTexture(nil, "ARTWORK")
itemIcon:SetSize(30, 30)
itemIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
local itemName = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
itemName:SetPoint("TOP", word, "BOTTOM", 17, -10)
itemName:SetShadowOffset(1, -1)
itemIcon:SetPoint("RIGHT", itemName, "LEFT", -6, 0)

local spark = banner:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetSize(40, 90)

-- Screen-edge glow (its own full-screen frame, behind everything else we draw).
local edge = CreateFrame("Frame", nil, UIParent)
edge:SetAllPoints(UIParent)
edge:SetFrameStrata("BACKGROUND")
edge:Hide()
local edgeTex = edge:CreateTexture(nil, "BACKGROUND")
edgeTex:SetAllPoints()
local hasEdge = edgeTex:SetTexture("Interface\\FullScreenTextures\\LowHealth") ~= false
edgeTex:SetBlendMode("ADD")

local bt, et = 0, 0
banner:SetScript("OnUpdate", function(self, dt)
	bt = bt + dt
	local s = 1
	if bt < 0.25 then local p = 1 - bt / 0.25; s = 1 + 0.9 * p * p * p end
	self:SetScale(s)
	self:ClearAllPoints()
	-- on the free side of the loot lines: below them when they stack upward, else above
	if LF.db.growUp then
		self:SetPoint("TOP", LootFlareAnchor, "BOTTOM", 0, -4 / s)
	else
		self:SetPoint("BOTTOM", LootFlareAnchor, "TOP", 0, 4 / s)
	end
	local a = 1
	if bt < 0.1 then a = bt / 0.1 elseif bt > SHOW - 0.7 then a = max(0, (SHOW - bt) / 0.7) end
	self:SetAlpha(a)
	local g = 0.45 + 0.2 * sin(bt * 6)
	glowL:SetAlpha(g); glowR:SetAlpha(g)
	local p = (bt - 0.2) / 0.7
	if p > 0 and p < 1 then
		local w = max(word:GetStringWidth() or 200, 120)
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", word, "LEFT", w * p, 0)
		spark:SetAlpha(sin(p * pi))
		spark:Show()
	else
		spark:Hide()
	end
	if bt >= SHOW then self:Hide() end
end)

edge:SetScript("OnUpdate", function(self, dt)
	et = et + dt
	local a
	if et < 0.15 then a = et / 0.15 else a = max(0, 1 - (et - 0.15) / 1.3) end
	edgeTex:SetAlpha(a * 0.8)
	if et > 1.5 then self:Hide() end
end)

-- l = the loot line (uses its quality, icon and name)
function LF.Banner(l)
	local q = l.q or 4
	local r, g, b = LF.QualityColor(q)
	word:SetText(WORDS[q] or "NICE!")
	word:SetTextColor(r, g, b)
	itemName:SetText(l.name or "")
	itemName:SetTextColor(r, g, b)
	itemIcon:SetTexture(l.icon:GetTexture())
	Gradient(glowL, r, g, b, 0, 0.9)
	Gradient(glowR, r, g, b, 0.9, 0)
	bt = 0
	banner:Show()
	if LF.db.edgeGlow and hasEdge then
		edgeTex:SetVertexColor(r, g, b)
		et = 0
		edge:Show()
	end
end

------------------------------------------------------------------------
-- Gold per hour: money looted + value of items looted (vendor, and AH via History.lua), over time played
------------------------------------------------------------------------
local gph = CreateFrame("Button", "LootFlareGoldFrame", UIParent)
gph:SetSize(230, 24)
gph:SetFrameStrata("HIGH") -- above action buttons and other add-ons' icons
gph:SetMovable(true)
gph:SetClampedToScreen(true)
gph:RegisterForDrag("LeftButton")
gph:RegisterForClicks("LeftButtonUp", "RightButtonUp")
Skin.Panel(gph, 1)
local gText = gph:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
gText:SetPoint("CENTER", 0, 0)

-- The box's look: label colour, size, background (settings: Look tab)
LF.GOLD_COLORS = {
	{ key = "gold", name = "Gold", hex = "ffd100" }, { key = "white", name = "White", hex = "ffffff" },
	{ key = "green", name = "Green", hex = "40ff40" }, { key = "blue", name = "Blue", hex = "4aa8ff" },
	{ key = "purple", name = "Purple", hex = "c27aff" }, { key = "orange", name = "Orange", hex = "ff9933" },
	{ key = "grey", name = "Grey", hex = "aaaaaa" },
}
local function LabelHex()
	for _, c in ipairs(LF.GOLD_COLORS) do if c.key == LF.db.gphColor then return c.hex end end
	return "ffd100"
end
local function Clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end
local function Round1(v) return floor(v * 10 + 0.5) / 10 end
-- what: "scale" (0.6-2.0), "bg" (0-1), "color" (next/previous); d = +1 / -1
function LF.SetGoldLook(what, d)
	local db = LF.db
	if what == "scale" then
		db.gphScale = Clamp(Round1((db.gphScale or 1) + d * 0.1), 0.6, 2.0)
	elseif what == "bg" then
		db.gphBg = Clamp(Round1((db.gphBg or 0.8) + d * 0.1), 0, 1)
	elseif what == "color" then
		local i = 1
		for k, c in ipairs(LF.GOLD_COLORS) do if c.key == db.gphColor then i = k end end
		i = (i - 1 + d) % #LF.GOLD_COLORS + 1
		db.gphColor = LF.GOLD_COLORS[i].key
	end
	LF.ApplyGold()
end
gph:Hide()

local function S() return LF.db.session end

function LF.PerHour()
	local s = S()
	local total = s.money + s.items
	if s.secs < 60 then return total, nil end
	return total, floor(total * 3600 / s.secs)
end

local function Short(c) -- 12g 34s (no copper once you're past a gold)
	if c >= 10000 then
		local g, sv = floor(c / 10000), floor(c / 100) % 100
		return LF.FormatMoney(g * 10000 + sv * 100)
	end
	return LF.FormatMoney(c)
end

local function Time(secs)
	local h, m = floor(secs / 3600), floor(secs / 60) % 60
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

-- money looted + the higher of AH and vendor value of the items
function LF.PerHourAH()
	local s = S()
	local total = s.money + (s.ah or 0)
	if s.secs < 60 then return total, nil end
	return total, floor(total * 3600 / s.secs)
end

function LF.GoldText()
	local total, perHour = LF.PerHour()
	local show = type(LF.db.gphShow) == "table" and LF.db.gphShow or {}
	local hasAH = LF.HasAHPrices and LF.HasAHPrices()
	local wantAH = show.ah and hasAH
	if not (show.total or show.vendor or wantAH or show.time) then show = { vendor = true } end -- never an empty box
	local lab = "|cff" .. LabelHex()
	local parts = {}
	if show.total then parts[#parts + 1] = lab .. "Loot|r " .. Short(total) end
	if show.vendor then parts[#parts + 1] = lab .. "/hr|r " .. (perHour and Short(perHour) or "...") end
	if wantAH then
		local _, ah = LF.PerHourAH()
		parts[#parts + 1] = show.vendor and ("|cff9fd0ff(AH " .. (ah and Short(ah) or "...") .. ")|r")
			or (lab .. "/hr|r |cff9fd0ff" .. (ah and Short(ah) or "...") .. " AH|r")
	end
	if show.time then parts[#parts + 1] = lab .. "Time|r " .. Time(S().secs) end
	local t = table.concat(parts, "   ")
	local running, why = true
	if LF.ClockState then running, why = LF.ClockState() end
	if not running then t = t .. "  |cff888888paused" .. (why and (" (" .. why .. ")") or "") .. "|r" end
	return t
end

function LF.RefreshGold()
	gText:SetText(LF.GoldText())
	gph:SetWidth(max(60, (gText:GetStringWidth() or 200) + 20))
end

function LF.AddValue(kind, copper)
	if Secret(copper) or type(copper) ~= "number" or copper <= 0 then return end
	local s = S()
	s[kind] = (s[kind] or 0) + copper
	if gph:IsShown() then LF.RefreshGold() end
end

function LF.ResetGold()
	local s = S()
	s.secs, s.money, s.items, s.ah = 0, 0, 0, 0
	if LF.HistNewSession then LF.HistNewSession() end -- the old session goes into the loot history
	LF.RefreshGold()
end

local tick = 0
gph:SetScript("OnUpdate", function(_, dt) -- the clock itself runs in History.lua (LF.Tick)
	tick = tick + dt
	if tick >= 1 then tick = 0; LF.RefreshGold() end
end)

-- Lock: the box stays put (clicks still work). Shift-click, /lflare goldlock or the settings.
local lockIcon = gph:CreateTexture(nil, "OVERLAY")
lockIcon:SetSize(12, 12)
lockIcon:SetPoint("TOPRIGHT", 3, 4)
lockIcon:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
lockIcon:Hide()
function LF.SetGoldLock(on)
	if on == nil then on = not LF.db.gphLocked end
	LF.db.gphLocked = on and true or false
	lockIcon:SetShown(LF.db.gphLocked)
	return LF.db.gphLocked
end

local dragged -- when the box was last dropped, so the click that ends a drag isn't a click
gph:SetScript("OnDragStart", function(self)
	if LF.db.gphLocked then return end
	self:StartMoving()
end)
gph:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	dragged = GetTime and GetTime() or 0
	-- saved in screen units, so changing the box's size doesn't move it
	local sc = self:GetScale() or 1
	local x, y = self:GetCenter()
	local px, py = UIParent:GetCenter()
	LF.db.gphPos = { x = floor(x * sc - px + 0.5), y = floor(y * sc - py + 0.5) }
	LF.ApplyGold()
end)
gph:SetScript("OnClick", function(_, button)
	if button == "RightButton" then LF.ResetGold()
	elseif IsShiftKeyDown and IsShiftKeyDown() then
		LF.SetGoldLock()
		if GameTooltip:IsOwned(gph) then gph:GetScript("OnEnter")(gph) end
	elseif LF.ToggleHistory and not (dragged and GetTime and GetTime() - dragged < 0.3) then LF.ToggleHistory() end
end)
gph:SetScript("OnEnter", function(self)
	local s = S()
	local total, perHour = LF.PerHour()
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("Loot Flare: gold per hour")
	GameTooltip:AddDoubleLine("Money looted", LF.FormatMoney(s.money), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Items (vendor value)", LF.FormatMoney(s.items), 1, 1, 1, 1, 1, 1)
	local ahOn = LF.HasAHPrices and LF.HasAHPrices()
	if ahOn then GameTooltip:AddDoubleLine("Items (AH value)", LF.FormatMoney(s.ah or 0), 0.62, 0.82, 1, 1, 1, 1) end
	GameTooltip:AddDoubleLine("Total (vendor)", LF.FormatMoney(total), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine("Time", Time(s.secs), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Per hour (vendor)", perHour and LF.FormatMoney(perHour) or "after a minute", 1, 0.82, 0, 1, 1, 1)
	if ahOn then
		local _, ah = LF.PerHourAH()
		GameTooltip:AddDoubleLine("Per hour (AH)", ah and LF.FormatMoney(ah) or "after a minute", 0.62, 0.82, 1, 1, 1, 1)
		GameTooltip:AddLine("AH value: Auctionator, then TSM; soulbound and grey items at vendor price.", 0.7, 0.7, 0.7, true)
	else
		GameTooltip:AddLine("Install Auctionator or TSM to see AH value too.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:AddLine("Counts time only while you're logged in. Vendor sales, mail and trades aren't counted.", 0.7, 0.7, 0.7, true)
	GameTooltip:AddLine("|cffffffffClick|r loot history   " .. (LF.db.gphLocked and "|cffff8080Locked|r" or "|cffffffffDrag|r move")
		.. "   |cffffffffRight-click|r new session", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffShift-click|r " .. (LF.db.gphLocked and "unlock" or "lock in place"), 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
gph:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Just above the game's own action bars (the highest of them that's showing).
local BARS = { "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "ReputationWatchBar" }
local function AboveBars()
	local top
	local us = UIParent:GetEffectiveScale()
	for _, name in ipairs(BARS) do
		local f = _G[name]
		if f and f.IsShown and f:IsShown() and f.GetTop then
			local ok, t = pcall(f.GetTop, f)
			if ok and type(t) == "number" and not Secret(t) then
				t = t * f:GetEffectiveScale() / us
				if not top or t > top then top = t end
			end
		end
	end
	return (top or 90) + 6
end

function LF.ApplyGold()
	local db = LF.db
	local sc = db.gphScale or 1
	gph:SetScale(sc)
	gph.bg:SetColorTexture(0.055, 0.055, 0.07, 1)
	gph.bg:SetAlpha(db.gphBg or 0.8)
	for _, e in ipairs(gph.edges or {}) do e:SetShown((db.gphBg or 0.8) > 0) end
	gph:ClearAllPoints()
	if type(db.gphPos) == "table" and db.gphPos.x then
		gph:SetPoint("CENTER", UIParent, "CENTER", db.gphPos.x / sc, db.gphPos.y / sc)
	else
		gph:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, AboveBars() / sc)
	end
	lockIcon:SetShown(db.gphLocked and true or false)
	if db.gph then LF.RefreshGold(); gph:Show() else gph:Hide() end
end

function LF.ResetGoldPosition()
	LF.db.gphPos = nil
	LF.ApplyGold()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, _, isLogin)
	if not LF.db then return end
	if isLogin == true and LF.db.gphLoginReset then
		local s = S()
		s.secs, s.money, s.items, s.ah = 0, 0, 0, 0
		if LF.HistNewSession then LF.HistNewSession() end
	end
	-- the old default spot (middle of the screen) gives way to "just above the action bars"
	local p = LF.db.gphPos
	if type(p) == "table" and p.x == 0 and p.y == -260 then LF.db.gphPos = nil end
	LF.ApplyGold()
	-- the action bars can settle a moment after loading; place the box again then
	if C_Timer then C_Timer.After(1, LF.ApplyGold) end
end)
