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

local pool = { fs = {}, bg = {}, btn = {} }
local nFs, nBg, nBtn, cursor = 0, 0, 0, 0

local function Reset()
	for _, f in ipairs(pool.fs) do f:Hide() end
	for _, b in ipairs(pool.bg) do b:Hide() end
	for _, b in ipairs(pool.btn) do b:Hide() end
	nFs, nBg, nBtn, cursor = 0, 0, 0, -10
end

local function SmallButton(text, y, onClick)
	nBtn = nBtn + 1
	local b = pool.btn[nBtn]
	if not b then
		b = S.Button(content, "", 104, 18)
		pool.btn[nBtn] = b
	end
	b:SetText(text)
	b:ClearAllPoints()
	b:SetPoint("TOPRIGHT", content, "TOPLEFT", W - 2 - PAD - 16, y)
	b:SetScript("OnClick", onClick)
	b:Show()
	return b
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
	if e.candidate.kind == "raidPrep" then
		local s = e.saving
		return "Costs " .. ns.Money(e.capital or 0) .. (s and s > 0 and (", saves " .. ns.Money(s) .. " vs usual") or "")
	end
	if e.returnClass == "guaranteed" and e.exactHidden then
		local c = e.candidate
		local payout = (c.money or 0)
		return "pays " .. ns.Money(payout) .. " (profit depends on today's price: see 'below')"
	end
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
	local rec = ns.Tracker and ns.Tracker.Find(c.id)
	if rec then
		SmallButton("Stop tracking", top - 2, function() ns.Tracker.Abandon(c.id); UI.Refresh(true) end)
	elseif e.ok and c.kind ~= "farm" then
		SmallButton("I'm doing this", top - 2, function() ns.Tracker.Accept(e); UI.Refresh(true) end)
	end
	cursor = cursor - 4
	Line(c.itemID and (c.title .. ": " .. ItemName(c.itemID)) or c.title, "GameFontNormal", 1, 1, 1, PAD + 4)
	local k = CLASS[e.returnClass] or CLASS.speculative
	local nums = Numbers(e)
	if e.thin or e.staleData then nums = nums .. " (price unreliable)" end
	Line(k[1] .. "  " .. nums, "GameFontHighlight", k[2], k[3], k[4], PAD + 4)
	for _, inp in ipairs(c.inputs or {}) do
		local p = priceOf(inp.itemID)
		local fresh = ns.Scan and ns.Scan.Fresh and ns.Scan.Fresh(inp.itemID, 1)
		local low = fresh or (p and p.minBuyout)
		local now = low and (" (lowest " .. (fresh and "just checked " or "now ") .. ns.Money(low) .. ")") or ""
		local below = inp.buyBelow and (" below " .. ns.Money(inp.buyBelow) .. " each") or ""
		Line("Buy " .. inp.qty .. " x " .. ItemName(inp.itemID) .. below .. now, "GameFontHighlightSmall", 0.9, 0.9, 0.9, PAD + 4)
	end
	Line("Gold tied up: " .. ns.Money(e.capital or 0) .. "   Pays out: " .. Payout(e), "GameFontHighlightSmall", 0.8, 0.8, 0.8, PAD + 4)
	if c.why then Line(c.why, "GameFontDisableSmall", 0.75, 0.75, 0.75, PAD + 4) end
	if c.hint then Line("Where: " .. c.hint, "GameFontDisableSmall", 0.75, 0.75, 0.75, PAD + 4) end
	if e.checks and #e.checks > 0 then
		Line("Check first: " .. table.concat(e.checks, "; "), "GameFontHighlightSmall", 1, 0.7, 0.3, PAD + 4)
	end
	if e.staleNote then Line("Prices may be out of date: check them at the Auction House first.", "GameFontHighlightSmall", 1, 0.6, 0.3, PAD + 4) end
	if e.returnClass == "speculative" then
		Line("Risky: depends on future demand or thin data. Only from your risk budget.", "GameFontDisableSmall", 1, 0.5, 0.15, PAD + 4)
	end
	if c.evidence then Line("Evidence: " .. c.evidence .. (c.buyWindow and ("   ·   buy " .. c.buyWindow .. ", sell " .. c.sellWindow) or ""),
		"GameFontHighlightSmall", c.evidence == "confirmed" and 0.3 or 1, c.evidence == "confirmed" and 0.85 or (c.evidence == "likely" and 0.82 or 0.5), 0.2, PAD + 4) end
	if c.source then Line("Source: " .. c.source, "GameFontDisableSmall", 0.55, 0.55, 0.6, PAD + 4) end
	if e.learned then Line("Adjusted by your past results (" .. e.learned.n .. " tips).", "GameFontDisableSmall", 0.55, 0.7, 0.9, PAD + 4) end
	if rec then Line(UI.TrackText(rec), "GameFontHighlightSmall", 0.55, 0.8, 1, PAD + 4) end
	cursor = cursor - 4
	CardBg(top, cursor)
	cursor = cursor - 8
end

------------------------------------------------------------------------
-- Building the plan from live data
------------------------------------------------------------------------
-- TSM looks stale when the watch-list prices haven't moved for days (checked every 10 minutes)
local lastWatch = 0
function UI.TsmStale(now)
	if not (ns.db and TSM_API) then return false end
	ns.db.history = ns.db.history or {}
	if now - lastWatch > 600 then
		lastWatch = now
		ns.Prices.RecordWatch(ns.db.history, now)
	end
	return ns.History.TsmStale(ns.db.history, ns.Data.Watch, now)
end

local function Ago(sec)
	if sec < 3600 then return math.max(1, math.floor(sec / 60)) .. " min ago" end
	if sec < 172800 then return math.floor(sec / 3600) .. " h ago" end
	return math.floor(sec / 86400) .. " days ago"
end
UI.Ago = Ago

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
		deposit = ns.Scan and ns.Scan.Deposit, stale = UI.TsmStale(now), fresh = ns.Scan and ns.Scan.Fresh,
		sessionMinutes = Settings().sessionMinutes, realmShare = Settings().realmShare, announce = true,
		trustOf = ns.Tracker and ns.Tracker.TrustOf, learn = ns.Tracker and ns.Tracker.Learn(),
	}
end

function UI.TrackText(r)
	local now = time()
	local st = ns.Track.State(r, now)
	local res = ns.Track.Result(r)
	if st == "realised" and res then
		return "Realised " .. (res.profit >= 0 and "+" or "") .. ns.Money(res.profit) .. (res.bought > 0 and r.kind ~= "quest" and (" (sold " .. res.sold .. " of " .. res.bought .. ")") or "")
	elseif st == "partial" and res then
		return "So far " .. (res.profit >= 0 and "+" or "") .. ns.Money(res.profit) .. " (sold " .. res.sold .. " of " .. res.bought .. ")"
	elseif st == "unconfirmed" then
		return "Result unconfirmed (couldn't match the purchase or the sale)"
	elseif st == "expired" then
		return "Tracking ended: nothing sold within 14 days"
	elseif st == "abandoned" then
		return "Stopped tracking"
	end
	local bought = 0
	for _, u in ipairs(r.units) do bought = bought + u.qty end
	return "Tracking since " .. Ago(now - r.acceptedAt) .. (bought > 0 and (" · bought " .. bought) or "")
end

local function Header(plan, ctx)
	local ch = ctx.char
	local profs = {}
	for _, p in pairs(ch.professions or {}) do profs[#profs + 1] = p.name .. " " .. p.rank end
	table.sort(profs)
	Line(#profs > 0 and table.concat(profs, " · ") or (ch.professionsKnown and "No professions" or "Professions: reading..."),
		"GameFontHighlight", 0.9, 0.9, 0.9)
	local b = plan.budget
	Line("Gold " .. ns.MoneyShort(ch.gold) .. "   ·   Budget " .. ns.MoneyShort(b.quick) .. " quick, " .. ns.MoneyShort(b.raid) ..
		" raids   ·   keeping " .. ns.MoneyShort(b.reserve), "GameFontHighlightSmall", 0.85, 0.85, 0.85)
	local r = ns.Raid.Next(ns.Raid.Calendar(), ctx.now)
	if r then
		local m = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
		local y, mo, d = r.date:match("^(%d+)-(%d+)-(%d+)$")
		Line("Raids in " .. r.days .. " days (" .. tonumber(d) .. " " .. m[tonumber(mo)] .. ": " .. r.name ..
			(r.status == "assumed" and ", date assumed" or "") .. ")", "GameFontHighlightSmall", 0.85, 0.85, 0.85)
	end
	local sc = ctx.scan
	if sc and sc.scannedAt then
		Line("Last scan: " .. Ago(ctx.now - sc.scannedAt) .. (sc.complete and "" or " (incomplete)"), "GameFontHighlightSmall", 0.75, 0.75, 0.8)
	else
		Line("No scan yet — prices from " .. (ns.Prices.Status().source or "nothing") .. ". Scan at the Auction House for buy tips.",
			"GameFontHighlightSmall", 0.75, 0.75, 0.8)
	end
	if ctx.stale then Line("TSM prices haven't changed for days: likely tips are marked as guesses until they update.", "GameFontHighlightSmall", 1, 0.5, 0.3) end
	local st = ns.Prices.Status()
	Line(st.note or ("Prices from " .. (st.source or "?")), "GameFontHighlightSmall", st.note and 1 or 0.6, st.note and 0.7 or 0.6, st.note and 0.3 or 0.65)
	for _, n in ipairs(plan.notes or {}) do Line(n, "GameFontDisableSmall", 1, 0.5, 0.3) end
	local goal = ns.Tracker and ns.Tracker.Goal()
	if goal then
		Line("Savings goal " .. ns.MoneyShort(ns.cdb.goal) .. ": " .. (goal.remaining == 0 and "reached!" or (ns.MoneyShort(goal.remaining) .. " to go" ..
			(goal.sessionsLeft and (", about " .. goal.sessionsLeft .. " sessions like your last ones") or " (needs 3 play sessions to estimate)"))),
			"GameFontHighlightSmall", 0.55, 0.85, 0.55)
	end
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
	Line("Spending limit for raids: " .. ns.MoneyShort(plan.budget.raid) .. " (" .. ns.MoneyShort(plan.raidSpent or 0) .. " planned)",
		"GameFontDisableSmall", 0.7, 0.7, 0.75)
	Line("Stock to sell", "GameFontNormal", 0.9, 0.9, 0.9)
	if #plan.stock == 0 then Line("No raid stock tips yet.", "GameFontDisableSmall", 0.7, 0.7, 0.7) end
	for _, e in ipairs(plan.stock) do Tip(e, ctx.priceOf) end
	Line("Your raid prep", "GameFontNormal", 0.9, 0.9, 0.9)
	if #plan.prep == 0 then Line("No raid prep tips yet.", "GameFontDisableSmall", 0.7, 0.7, 0.7) end
	for _, e in ipairs(plan.prep) do Tip(e, ctx.priceOf) end

	local okB, blocks = pcall(ns.Path.Blocks, ctx.char, ctx.priceOf)
	if okB and #blocks > 0 then
		Section("Professions")
		for _, b in ipairs(blocks) do
			Line(b.name .. " " .. b.rank .. (b.max and ("/" .. b.max) or ""), "GameFontNormal", 0.9, 0.9, 0.9)
			if #b.milestones > 0 then
				for _, m in ipairs(b.milestones) do
					Line("At " .. m.rank .. ": " .. m.text, "GameFontHighlightSmall", 0.85, 0.85, 0.85, PAD + 8)
				end
			else
				Line("No milestones known yet.", "GameFontDisableSmall", 0.7, 0.7, 0.7, PAD + 8)
			end
			local p, cov = b.path, b.coverage or {}
			if p and #p.steps > 0 then
				local first = p.steps[1]
				local r = ns.Recipes.Get(first.spellID)
				Line(p.label:sub(1, 1):upper() .. p.label:sub(2) .. " to " .. b.target .. ": about " .. ns.Money(p.total) ..
					(p.gaps > 0 and (" (" .. p.gaps .. " points have no known recipe)") or ""), "GameFontHighlightSmall", 0.9, 0.82, 0.5, PAD + 8)
				for i = 1, math.min(#p.steps, 3) do
					local s = p.steps[i]
					local rr = ns.Recipes.Get(s.spellID)
					Line(s.from .. "-" .. s.to .. ": " .. (rr and rr.name or ("recipe " .. s.spellID)) .. " x" .. s.crafts ..
						" (" .. ns.Money(s.cost) .. ")", "GameFontDisableSmall", 0.8, 0.8, 0.8, PAD + 16)
				end
			end
			local pc = p and p.coverage
			Line("Based on " .. (cov.found or 0) .. " " .. b.name .. " recipes" ..
				(pc and (", " .. pc.estimated .. " with estimated levels, " .. pc.missing .. " missing") or "") ..
				(cov.complete and "" or (cov.walkSkipped and " (open the profession window to add more)" or " (still searching)")) .. ".",
				"GameFontDisableSmall", 0.6, 0.6, 0.65, PAD + 8)
		end
	elseif not okB then
		Line("Profession tips unavailable: " .. tostring(blocks), "GameFontDisableSmall", 1, 0.5, 0.3)
	end

	local recs = ns.Tracker and ns.Tracker.Records() or {}
	if #recs > 0 then
		Section("Your tracked tips")
		for i = #recs, math.max(1, #recs - 7), -1 do
			local r = recs[i]
			Line((r.title or "?") .. "  —  " .. UI.TrackText(r), "GameFontHighlightSmall", 0.8, 0.85, 0.95)
		end
	end

	Section("Skip")
	if #plan.skip == 0 then Line("Nothing skipped.", "GameFontDisableSmall", 0.7, 0.7, 0.7) end
	for _, e in ipairs(plan.skip) do
		local c = e.candidate
		Line((c.itemID and (c.title .. ": " .. ItemName(c.itemID)) or c.title or "?") .. "  —  " .. (e.skipReason or "?"), "GameFontHighlightSmall", 0.8, 0.8, 0.8)
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
for _, ev in ipairs({ "PLAYER_MONEY", "CHAR_CHANGED", "ITEM_READY", "SCAN_DONE", "DISCOVER_DONE", "ITEM_REFRESHED", "TRACK_CHANGED", "RECIPES_CHANGED", "VENDORS_SEEN" }) do
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
local setBtn = S.Button(foot, "Settings", 80, 22)
setBtn:SetPoint("LEFT", session, "RIGHT", 8, 0)
setBtn:SetScript("OnClick", function() UI.ToggleSettings() end)
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
	if msg == "recipes" then
		local c = ns.db.recipes or {}
		local parts = {}
		for line, p in pairs(ns.Char.Get().professions or {}) do
			local cov = ns.Recipes.Coverage(line)
			parts[#parts + 1] = p.name .. " " .. cov.found
		end
		ns.Print("recipes known for build " .. tostring(c.build) .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "none yet") ..
			(c.complete and " (search complete)" or (ns.IsRunning("recipes") and " (searching...)" or "")) ..
			(c.walkSkipped and " (search skipped: open profession windows)" or ""))
		return
	end
	if msg == "recipes bench" then
		ns.Recipes.Bench(10000, function(b)
			ns.Print(("%.2f microseconds per ID; a full search would take about %d s in the background."):format(b.usPerId, math.floor(b.projectedSeconds)))
		end)
		return
	end
	if msg == "recipes stop" then ns.Recipes.Stop(); ns.Print("recipe search stopped (it carries on after /reload)."); return end
	if msg == "recipes rebuild" then ns.Recipes.Rebuild(); ns.Print("searching all recipes again in the background."); return end
	if msg == "settings" or msg == "options" then UI.ToggleSettings(); return end
	if msg == "" then UI.Toggle(); return end
	ns.Print("/mo  open tonight's plan   ·   /mo settings   ·   /mo 30 or /mo 60   ·   /mo price <itemID>   ·   /mo recipes [bench | stop | rebuild]")
end

ns.On("PLAYER_LOGIN", function()
	SLASH_MARKETOPPORTUNITIES1 = SlashTaken("/mo") and "/mopp" or "/mo"
	SLASH_MARKETOPPORTUNITIES2 = "/mopp"
	if SLASH_MARKETOPPORTUNITIES1 == "/mopp" then SLASH_MARKETOPPORTUNITIES2 = nil end
	SlashCmdList.MARKETOPPORTUNITIES = Slash
end)
