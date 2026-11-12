-- Loot Flare extras: the big banner for good drops, and the gold-per-hour tracker.
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
-- Gold per hour: money looted + vendor value of items looted, over time played
------------------------------------------------------------------------
local gph = CreateFrame("Button", "LootFlareGoldFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
gph:SetSize(230, 26)
gph:SetMovable(true)
gph:SetClampedToScreen(true)
gph:RegisterForDrag("LeftButton")
gph:RegisterForClicks("RightButtonUp")
if gph.SetBackdrop then
	gph:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	gph:SetBackdropColor(0, 0, 0, 0.7)
	gph:SetBackdropBorderColor(1, 0.82, 0, 0.8)
end
local gText = gph:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
gText:SetPoint("CENTER")
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

function LF.RefreshGold()
	local total, perHour = LF.PerHour()
	gText:SetText("|cffffd100Loot|r " .. Short(total) .. "   |cffffd100/hr|r " .. (perHour and Short(perHour) or "..."))
	gph:SetWidth(max(150, (gText:GetStringWidth() or 200) + 20))
end

function LF.AddValue(kind, copper)
	if Secret(copper) or type(copper) ~= "number" or copper <= 0 then return end
	local s = S()
	s[kind] = (s[kind] or 0) + copper
	if gph:IsShown() then LF.RefreshGold() end
end

function LF.ResetGold()
	local s = S()
	s.secs, s.money, s.items = 0, 0, 0
	LF.RefreshGold()
end

local tick = 0
gph:SetScript("OnUpdate", function(_, dt)
	S().secs = S().secs + dt
	tick = tick + dt
	if tick >= 1 then tick = 0; LF.RefreshGold() end
end)

gph:SetScript("OnDragStart", gph.StartMoving)
gph:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local x, y = self:GetCenter()
	local px, py = UIParent:GetCenter()
	LF.db.gphPos.x, LF.db.gphPos.y = floor(x - px + 0.5), floor(y - py + 0.5)
	LF.ApplyGold()
end)
gph:SetScript("OnClick", function(_, button) if button == "RightButton" then LF.ResetGold() end end)
gph:SetScript("OnEnter", function(self)
	local s = S()
	local total, perHour = LF.PerHour()
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("Loot Flare: gold per hour")
	GameTooltip:AddDoubleLine("Money looted", LF.FormatMoney(s.money), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Items (vendor value)", LF.FormatMoney(s.items), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Total", LF.FormatMoney(total), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine("Time", Time(s.secs), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Per hour", perHour and LF.FormatMoney(perHour) or "after a minute", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine("Counts time only while you're logged in. Vendor sales and trades aren't counted.", 0.7, 0.7, 0.7, true)
	GameTooltip:AddLine("|cffffffffDrag|r move   |cffffffffRight-click|r start over", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
gph:SetScript("OnLeave", function() GameTooltip:Hide() end)

function LF.ApplyGold()
	local db = LF.db
	gph:ClearAllPoints()
	gph:SetPoint("CENTER", UIParent, "CENTER", db.gphPos.x, db.gphPos.y)
	if db.gph then LF.RefreshGold(); gph:Show() else gph:Hide() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, _, isLogin)
	if not LF.db then return end
	if isLogin == true and LF.db.gphLoginReset then
		local s = S()
		s.secs, s.money, s.items = 0, 0, 0
	end
	LF.ApplyGold()
end)
