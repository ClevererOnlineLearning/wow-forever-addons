-- Settings: budget limits, realm share, raid calendar, recipe search. /mo settings
local _, ns = ...
local S = ns.Skin
local UI = ns.UI
local G = 10000

local win = S.Window("MarketOpportunitiesSettings", "Market Opportunities settings", ns.ICON, ns.VERSION, 430, 560)
UI.settings = win

local function Settings()
	ns.cdb.settings = ns.cdb.settings or {}
	ns.cdb.settings.budget = ns.cdb.settings.budget or {}
	return ns.cdb.settings
end

local function Num(text)
	text = tostring(text or ""):gsub(",", "."):match("^%s*(.-)%s*$")
	if text == "" then return nil end
	return tonumber(text)
end

------------------------------------------------------------------------
-- Budget card: blank = automatic (worked out from your gold)
------------------------------------------------------------------------
local card = S.Card(win, "Budget (gold; leave blank for automatic)", 12, -44, 406, 10)
local FIELDS = {
	{ key = "reserve", label = "Always keep" },
	{ key = "quick", label = "Quick tips, tonight" },
	{ key = "raid", label = "Hold for raids" },
	{ key = "maxBet", label = "Most on one tip" },
	{ key = "speculative", label = "Risky tips, at most" },
}
local edits = {}
for i, f in ipairs(FIELDS) do
	local y = S.Row(card, 28)
	S.Text(card, f.label, 14, y - 5)
	local e = S.Edit(card, 90, 22)
	e:SetPoint("TOPLEFT", 200, y)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEditFocusLost", function(self)
		local v = Num(self:GetText())
		Settings().budget[f.key] = v and math.floor(v * G) or nil
		UI.Refresh(true)
	end)
	local auto = S.Note(card, "", 300, y - 6, 100)
	edits[f.key] = { edit = e, auto = auto }
end
local y = S.Row(card, 28)
S.Text(card, "Your realm's share of region sales (%)", 14, y - 5)
local share = S.Edit(card, 60, 22)
share:SetPoint("TOPLEFT", 300, y)
share:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
share:SetScript("OnEditFocusLost", function(self)
	local v = Num(self:GetText())
	Settings().realmShare = v and math.max(1, math.min(100, v)) / 100 or nil
	UI.Refresh(true)
end)
S.Fit(card)

------------------------------------------------------------------------
-- Raid calendar card
------------------------------------------------------------------------
local cal = S.Card(win, "Raid calendar (date as YYYY-MM-DD)", 12, S.Below(card), 406, 10)
local rows = {}
for i = 1, 4 do
	local ry = S.Row(cal, 28)
	local name = S.Edit(cal, 210, 22)
	name:SetPoint("TOPLEFT", 12, ry)
	local date = S.Edit(cal, 100, 22)
	date:SetPoint("TOPLEFT", 228, ry)
	local status = S.Check(cal, "assumed", 336, ry)
	rows[i] = { name = name, date = date, status = status }
end
local yb = S.Row(cal, 30)
local save = S.Button(cal, "Save calendar", 120, 22, true)
save:SetPoint("TOPLEFT", 12, yb)
local reset = S.Button(cal, "Use bundled dates", 140, 22)
reset:SetPoint("LEFT", save, "RIGHT", 8, 0)
local calNote = S.Note(cal, "", 12, S.Row(cal, 18), 380)
S.Fit(cal)

local function FillCalendar()
	local list = ns.Raid.Calendar()
	for i, r in ipairs(rows) do
		local c = list[i]
		r.name:SetText(c and c.name or "")
		r.date:SetText(c and c.date or "")
		r.status:SetChecked(c and c.status == "assumed" or false)
	end
	calNote:SetText(ns.db.raidCalendar and "Using your dates." or "Using the bundled dates (checked 2026-11-15).")
end

save:SetScript("OnClick", function()
	local list, bad = {}, nil
	for _, r in ipairs(rows) do
		local n, d = r.name:GetText(), r.date:GetText()
		if n and n ~= "" then
			if d ~= "" and not d:match("^%d%d%d%d%-%d%d%-%d%d$") then bad = n end
			list[#list + 1] = { name = n, date = d ~= "" and d or nil, status = r.status:GetChecked() and "assumed" or "announced", source = "you" }
		end
	end
	if bad then calNote:SetText("|cffff6633The date for " .. bad .. " should look like 2026-12-09.|r"); return end
	ns.db.raidCalendar = #list > 0 and list or nil
	FillCalendar()
	UI.Refresh(true)
end)
reset:SetScript("OnClick", function() ns.db.raidCalendar = nil; FillCalendar(); UI.Refresh(true) end)

------------------------------------------------------------------------
-- Recipe search card
------------------------------------------------------------------------
local rc = S.Card(win, "Recipe search", 12, S.Below(cal), 406, 10)
local ry = S.Row(rc, 30)
local rebuild = S.Button(rc, "Search again", 120, 22)
rebuild:SetPoint("TOPLEFT", 12, ry)
local stop = S.Button(rc, "Stop", 70, 22)
stop:SetPoint("LEFT", rebuild, "RIGHT", 8, 0)
local rnote = S.Note(rc, "", 12, S.Row(rc, 30), 380)
S.Fit(rc)
rebuild:SetScript("OnClick", function() ns.Recipes.Rebuild() end)
stop:SetScript("OnClick", function() ns.Recipes.Stop() end)

local function Update()
	local b = UI.lastPlan and UI.lastPlan.budget
	local s = Settings()
	for _, f in ipairs(FIELDS) do
		local v = s.budget[f.key]
		edits[f.key].edit:SetText(v and tostring(v / G) or "")
		edits[f.key].auto:SetText(b and ("now " .. ns.MoneyShort(b[f.key] or 0)) or "")
	end
	share:SetText(s.realmShare and tostring(math.floor(s.realmShare * 100 + 0.5)) or "")
	FillCalendar()
	local c = ns.db.recipes or {}
	rnote:SetText((c.complete and "All recipes found for this game version." or
		(ns.IsRunning("recipes") and "Searching in the background..." or
		(c.walkSkipped and "Search skipped (too slow here): open each profession window instead." or "Not searched yet."))))
end
win:SetScript("OnShow", Update)

function UI.ToggleSettings()
	if win:IsShown() then win:Hide(); return end
	if InCombatLockdown() then ns.Print("opens after combat."); return end
	win:Show()
end
