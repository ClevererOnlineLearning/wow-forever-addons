-- "Tonight's plan" window, minimap button and /mo. Advice only: nothing here buys, sells or posts.
local _, ns = ...
local S = ns.Skin
ns.UI = ns.UI or {}
local UI = ns.UI

local W, PAD = 470, 14
local TEXT_W = W - 2 * PAD - 28

local CLASS = {
	guaranteed = { "Sure payout", 0.25, 0.85, 0.35 },
	expected = { "Likely", 1.0, 0.82, 0.1 },
	speculative = { "Guess (risky)", 1.0, 0.5, 0.15 },
}

local function Settings()
	local c = ns.cdb or {}
	c.settings = c.settings or {}
	if c.settings.sessionMinutes ~= 30 and c.settings.sessionMinutes ~= 60 then c.settings.sessionMinutes = 60 end
	return c.settings
end

local function ItemName(id)
	return (ns.Prices.Name and ns.Prices.Name(id)) or ("item " .. id)
end

------------------------------------------------------------------------
-- Window and scrolling content
------------------------------------------------------------------------
local win = S.Window("MarketOpportunitiesWindow", "Market Opportunities", ns.ICON, ns.VERSION, W, 560)
UI.win = win

local scroll = CreateFrame("ScrollFrame", nil, win)
scroll:SetPoint("TOPLEFT", 1, -34)
scroll:SetPoint("BOTTOMRIGHT", -1, 42)
scroll:EnableMouseWheel(true)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(W - 2, 10)
scroll:SetScrollChild(content)
scroll:SetScript("OnMouseWheel", function(self, delta)
	local max = math.max(content:GetHeight() - self:GetHeight(), 0)
	local v = math.min(math.max(self:GetVerticalScroll() - delta * 40, 0), max)
	self:SetVerticalScroll(v)
end)

local pool = { fs = {}, bg = {} }
local nFs, nBg, cursor = 0, 0, 0

local function Reset()
	for _, f in ipairs(pool.fs) do f:Hide() end
	for _, b in ipairs(pool.bg) do b:Hide() end
	nFs, nBg, cursor = 0, 0, -10
end

local function Line(text, font, r, g, b, indent, gap)
	nFs = nFs + 1
	local fs = pool.fs[nFs]
	if not fs then
		fs = content:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		pool.fs[nFs] = fs
	end
	fs:SetFontObject(font or "GameFontHighlight")
	indent = indent or PAD
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", indent, cursor)
	fs:SetWidth(TEXT_W - (indent - PAD))
	fs:SetText(text or "")
	fs:SetTextColor(r or 1, g or 1, b or 1)
	fs:Show()
	cursor = cursor - (fs:GetStringHeight() or 12) - (gap or 3)
	return fs
end

local function CardBg(top, bottom)
	nBg = nBg + 1
	local t = pool.bg[nBg]
	if not t then
		t = content:CreateTexture(nil, "BACKGROUND")
		pool.bg[nBg] = t
	end
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", PAD - 6, top + 5)
	t:SetPoint("TOPRIGHT", -(PAD - 6) - 14, top + 5)
	t:SetHeight(top - bottom + 4)
	t:SetColorTexture(1, 1, 1, 0.04)
	t:Show()
end

local function Section(title)
	cursor = cursor - 6
	Line(title, "GameFontNormalLarge", S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], PAD, 6)
end

------------------------------------------------------------------------
-- One tip
------------------------------------------------------------------------
local function Payout(e)
	local c = e.candidate
	if (c.waitDays or 0) <= 0 then return c.kind == "quest" and "on hand-in" or "right away" end
	return "in about " .. c.waitDays .. " days"
end

local function Numbers(e)
	if e.returnClass == "guaranteed" then
		return "+" .. ns.Money(e.net)
	end
	local lo, hi = ns.Money(e.netLow), ns.Money(e.netHigh)
	local s = (e.netLow == e.netHigh) and ("about +" .. hi) or (lo .. " to +" .. hi)
	if e.pSell then s = s .. ", sells ~" .. math.floor(e.pSell * 100 + 0.5) .. "%" end
	return s
end

local function Tip(e, priceOf)
	local c = e.candidate
	local top = cursor
	cursor = cursor - 4
	Line(c.title, "GameFontNormal", 1, 1, 1, PAD + 4)
	local k = CLASS[e.returnClass] or CLASS.speculative
	local nums = Numbers(e)
	if e.thin or e.staleData then nums = nums .. " (price unreliable)" end
	Line(k[1] .. "  " .. nums, "GameFontHighlight", k[2], k[3], k[4], PAD + 4)
	for _, inp in ipairs(c.inputs or {}) do
		local p = priceOf(inp.itemID)
		local now = p and p.minBuyout and (" (lowest now " .. ns.Money(p.minBuyout) .. ")") or ""
		local below = inp.buyBelow and (" below " .. ns.Money(inp.buyBelow) .. " each") or ""
		Line("Buy " .. inp.qty .. " x " .. ItemName(inp.itemID) .. below .. now, "GameFontHighlightSmall", 0.9, 0.9, 0.9, PAD + 4)
	end
	Line("Gold tied up: " .. ns.Money(e.capital or 0) .. "   Pays out: " .. Payout(e), "GameFontHighlightSmall", 0.8, 0.8, 0.8, PAD + 4)
	if c.why then Line(c.why, "GameFontDisableSmall", 0.75, 0.75, 0.75, PAD + 4) end
	if c.hint then Line("Where: " .. c.hint, "GameFontDisableSmall", 0.75, 0.75, 0.75, PAD + 4) end
	if e.checks and #e.checks > 0 then
		Line("Check first: " .. table.concat(e.checks, "; "), "GameFontHighlightSmall", 1, 0.7, 0.3, PAD + 4)
	end
	if e.returnClass == "speculative" then
		Line("Risky: depends on future demand or thin data. Only from your risk budget.", "GameFontDisableSmall", 1, 0.5, 0.15, PAD + 4)
	end
	if c.source then Line("Source: " .. c.source, "GameFontDisableSmall", 0.55, 0.55, 0.6, PAD + 4) end
	cursor = cursor - 4
	CardBg(top, cursor)
	cursor = cursor - 8
end

------------------------------------------------------------------------
-- Building the plan from live data
------------------------------------------------------------------------
local function Context()
	local cache = {}
	local function priceOf(id)
		if cache[id] == nil then cache[id] = ns.Prices.Get(id) or false end
		return cache[id] or nil
	end
	local now = time()
	local scan = ns.Scan and ns.Scan.Last()
	return {
		char = ns.Char.Get(), priceOf = priceOf, now = now, standing = ns.Char.Standing,
		scan = scan, scanAgeMin = scan and scan.scannedAt and math.floor((now - scan.scannedAt) / 60) or nil,
	}
end

local function Header(plan, ctx)
	local ch = ctx.char
	local profs = {}
	for _, p in pairs(ch.professions or {}) do profs[#profs + 1] = p.name .. " " .. p.rank end
	table.sort(profs)
	Line(#profs > 0 and table.concat(profs, " · ") or (ch.professionsKnown and "No professions" or "Professions: reading..."),
		"GameFontHighlight", 0.9, 0.9, 0.9)
	local b = plan.budget
	Line("Gold " .. ns.Money(ch.gold) .. "   ·   Budget " .. ns.Money(b.quick) .. " quick, " .. ns.Money(b.raid) ..
		" raids   ·   keeping " .. ns.Money(b.reserve), "GameFontHighlightSmall", 0.85, 0.85, 0.85)
	local r = ns.Data.NextRaid(ctx.now)
	if r then
		local m = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
		local y, mo, d = r.date:match("^(%d+)-(%d+)-(%d+)$")
		Line("Raids in " .. r.days .. " days (" .. tonumber(d) .. " " .. m[tonumber(mo)] .. ": " .. r.name ..
			(r.status == "assumed" and ", date assumed" or "") .. ")", "GameFontHighlightSmall", 0.85, 0.85, 0.85)
	end
	local st = ns.Prices.Status()
	Line(st.note or ("Prices from " .. (st.source or "?")), "GameFontHighlightSmall", st.note and 1 or 0.6, st.note and 0.7 or 0.6, st.note and 0.3 or 0.65)
	for _, n in ipairs(plan.notes or {}) do Line(n, "GameFontDisableSmall", 1, 0.5, 0.3) end
	Line("Planned: " .. plan.minutes .. " of " .. Settings().sessionMinutes .. " min, " .. ns.Money(plan.spent) .. " of gold.",
		"GameFontDisableSmall", 0.6, 0.6, 0.65)
end

function UI.Build()
	if not ns.cdb then return end
	local ctx = Context()
	local plan = ns.BuildPlan(ctx, Settings())
	UI.lastPlan = plan
	Reset()
	Header(plan, ctx)

	Section("Today")
	if #plan.today == 0 then
		Line("Nothing worth doing right now with your budget and the prices the add-on can see. See Skip for why.",
			"GameFontDisableSmall", 0.75, 0.75, 0.75)
	end
	for _, e in ipairs(plan.today) do Tip(e, ctx.priceOf) end

	Section("Hold for raids")
	Line("Stock to sell", "GameFontNormal", 0.9, 0.9, 0.9)
	if #plan.stock == 0 then Line("No raid stock tips yet.", "GameFontDisableSmall", 0.7, 0.7, 0.7) end
	for _, e in ipairs(plan.stock) do Tip(e, ctx.priceOf) end
	Line("Your raid prep", "GameFontNormal", 0.9, 0.9, 0.9)
	if #plan.prep == 0 then Line("No raid prep tips yet.", "GameFontDisableSmall", 0.7, 0.7, 0.7) end
	for _, e in ipairs(plan.prep) do Tip(e, ctx.priceOf) end

	Section("Skip")
	if #plan.skip == 0 then Line("Nothing skipped.", "GameFontDisableSmall", 0.7, 0.7, 0.7) end
	for _, e in ipairs(plan.skip) do
		Line((e.candidate.title or "?") .. "  —  " .. (e.skipReason or "?"), "GameFontHighlightSmall", 0.8, 0.8, 0.8)
	end
	content:SetHeight(-cursor + 10)
end

-- Debounced rebuild; never in combat (it waits for combat to end)
local pending, combatPending = false, false
function UI.Refresh(now)
	if not win:IsShown() then return end
	if InCombatLockdown() then combatPending = true; return end
	if now then UI.Build(); return end
	if pending then return end
	pending = true
	C_Timer.After(1, function()
		pending = false
		if win:IsShown() and not InCombatLockdown() then UI.Build() elseif InCombatLockdown() then combatPending = true end
	end)
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if combatPending then combatPending = false; UI.Refresh() end
end)
for _, ev in ipairs({ "PLAYER_MONEY", "CHAR_CHANGED", "ITEM_READY", "SCAN_DONE", "DISCOVER_DONE", "ITEM_REFRESHED" }) do
	ns.On(ev, function() UI.Refresh() end)
end
win:SetScript("OnShow", function() ns.Char.Refresh(); UI.Refresh(true) end)

------------------------------------------------------------------------
-- Footer
------------------------------------------------------------------------
local foot = S.Footer(win, 40)
local refresh = S.Button(foot, "Refresh", 90, 22, true)
refresh:SetPoint("LEFT", 12, 0)
refresh:SetScript("OnClick", function() UI.Refresh(true) end)
local session = S.Button(foot, "", 130, 22)
session:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
local function SessionText() session:SetText("Session: " .. Settings().sessionMinutes .. " min") end
session:SetScript("OnClick", function()
	local s = Settings()
	s.sessionMinutes = s.sessionMinutes == 60 and 30 or 60
	SessionText()
	UI.Refresh(true)
end)
S.Tip(session, "Session length", "How much playing time tonight's plan may fill: 30 or 60 minutes.")
local advice = S.Note(foot, "Advice only: you do the buying.", 0, 0)
advice:ClearAllPoints()
advice:SetPoint("RIGHT", -12, 0)

function UI.Toggle()
	if win:IsShown() then win:Hide(); return end
	if InCombatLockdown() then ns.Print("opens after combat."); return end
	win:Show()
end

------------------------------------------------------------------------
-- Minimap button: left-click opens the plan, drag to move
------------------------------------------------------------------------
local mm = CreateFrame("Button", "MarketOpportunitiesMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetSize(20, 20); mmBg:SetPoint("TOPLEFT", 7, -5)
local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetTexture(ns.ICON)
mmIcon:SetSize(17, 17); mmIcon:SetPoint("TOPLEFT", 7, -6)
mmIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53); mmBorder:SetPoint("TOPLEFT")
mm:Hide()

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function MinimapStore()
	if not ns.db then return nil end
	if type(ns.db.minimap) ~= "table" then ns.db.minimap = { hide = false, angle = 200 } end
	return ns.db.minimap
end
local function PlaceButton()
	local a = math.rad(MinimapStore().angle or 200)
	local r = (Minimap:GetWidth() / 2) + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
function UI.UpdateMinimapButton()
	local m = MinimapStore()
	if not m then return end
	if m.hide then mm:Hide() else PlaceButton(); mm:Show() end
end
mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		MinimapStore().angle = math.deg(atan2(cy / s - my, cx / s - mx))
		PlaceButton()
	end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnClick", function() UI.Toggle() end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Market Opportunities")
	GameTooltip:AddLine("|cffffffffClick|r  tonight's plan", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
S.Group(mm, "MarketOpportunities", MinimapStore, UI.UpdateMinimapButton)
ns.On("PLAYER_LOGIN", function() UI.UpdateMinimapButton(); SessionText() end)

------------------------------------------------------------------------
-- Slash command: /mo, or /mopp if another add-on already owns /mo
------------------------------------------------------------------------
local function SlashTaken(cmd)
	for k, v in pairs(_G) do
		if type(k) == "string" and k:sub(1, 6) == "SLASH_" and type(v) == "string" and v:lower() == cmd then
			return true
		end
	end
	return false
end

local function PriceDebug(id)
	local p = ns.Prices.Get(id)
	if not p then ns.Print("no price data for item " .. id .. " (" .. (ns.Prices.Status().note or "?") .. ")"); return end
	local parts = {}
	for _, k in ipairs({ "source", "market", "minBuyout", "recent", "historical", "numAuctions", "regionMarket",
		"regionSoldPerDay", "regionSaleRate", "atrPrice", "atrAgeDays", "vendorSell", "stale" }) do
		parts[#parts + 1] = k .. "=" .. tostring(p[k])
	end
	ns.Print(ItemName(id) .. ": " .. table.concat(parts, " "))
	-- probe check: does the scaled sale-rate string give a fraction on this client?
	if TSM_API and TSM_API.GetCustomPriceValue then
		local ok, v = pcall(TSM_API.GetCustomPriceValue, "DBRegionSaleRate*1000", "i:" .. id)
		ns.Print("TSM DBRegionSaleRate*1000 = " .. tostring(ok and v or "error"))
	end
end

local function Slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local id = msg:match("^price%s+(%d+)$")
	if id then PriceDebug(tonumber(id)); return end
	if msg == "30" or msg == "60" then Settings().sessionMinutes = tonumber(msg); SessionText(); UI.Refresh(true); return end
	if msg == "" then UI.Toggle(); return end
	ns.Print("/mo  open tonight's plan   ·   /mo 30 or /mo 60  session length   ·   /mo price <itemID>  price check")
end

ns.On("PLAYER_LOGIN", function()
	SLASH_MARKETOPPORTUNITIES1 = SlashTaken("/mo") and "/mopp" or "/mo"
	SLASH_MARKETOPPORTUNITIES2 = "/mopp"
	if SLASH_MARKETOPPORTUNITIES1 == "/mopp" then SLASH_MARKETOPPORTUNITIES2 = nil end
	SlashCmdList.MARKETOPPORTUNITIES = Slash
end)
