-- Side panel at the Auction House: scan, check the plan's prices, see what the plan wants to buy.
-- Read-only: it never buys, bids or posts. You do that yourself in Blizzard's Auction House.
local _, ns = ...
local S = ns.Skin
local UI = ns.UI

local panel = CreateFrame("Frame", "MarketOpportunitiesAHPanel", UIParent)
panel:SetSize(250, 330)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
S.Panel(panel)
panel:Hide()
UI.ahPanel = panel

local title = S.Text(panel, "Market Opportunities", 12, -10, "GameFontNormal")
local scanBtn = S.Button(panel, "Scan Auction House", 226, 24, true)
scanBtn:SetPoint("TOPLEFT", 12, -32)
local scanNote = S.Note(panel, "", 12, -62, 226)
local checkBtn = S.Button(panel, "Check plan prices", 226, 22)
checkBtn:SetPoint("TOPLEFT", 12, -96)
local planBtn = S.Button(panel, "Open tonight's plan", 226, 22)
planBtn:SetPoint("TOPLEFT", 12, -122)
S.Text(panel, "The plan wants to buy", 12, -154, "GameFontNormalSmall")
local rows = {}
for i = 1, 8 do
	rows[i] = S.Text(panel, "", 12, -154 - 16 * i, "GameFontHighlightSmall", 226)
end
local foot = S.Note(panel, "Advice only: buy and post yourself.", 12, -300, 226)

local function PlanBuys()
	local list, seen = {}, {}
	local plan = UI.lastPlan
	if not plan then return list end
	for _, part in ipairs({ plan.today, plan.stock, plan.prep }) do
		for _, e in ipairs(part or {}) do
			for _, inp in ipairs(e.candidate.inputs or {}) do
				if not seen[inp.itemID] then
					seen[inp.itemID] = true
					list[#list + 1] = inp
				end
			end
		end
	end
	return list
end

local function Update()
	local now = time()
	if ns.Scan.IsReading() then
		scanBtn:Disable()
		scanNote:SetText("Reading auctions: " .. math.floor(ns.Scan.Progress() * 100) .. "%")
	else
		local wait = ns.Scan.NextFullAt() - now
		local last = ns.Scan.Last()
		local age = last and last.scannedAt and ("Last scan " .. UI.Ago(now - last.scannedAt) .. (last.complete and "" or " (incomplete)")) or "No scan yet"
		if wait > 0 then
			scanBtn:Disable()
			scanNote:SetText(age .. ". Next full scan in " .. math.ceil(wait / 60) .. " min.")
		else
			scanBtn:Enable()
			scanNote:SetText(age .. ". A full scan takes about 15 seconds.")
		end
	end
	local buys = PlanBuys()
	local last = ns.Scan.Last()
	for i, r in ipairs(rows) do
		local inp = buys[i]
		if inp then
			local name = (ns.Prices.Name and ns.Prices.Name(inp.itemID)) or ("item " .. inp.itemID)
			local s = last and last.summary and last.summary[inp.itemID]
			local age = ns.Scan.AgeMin(inp.itemID)
			local low = s and s.min and (ns.Money(s.min) .. (age and (" (" .. age .. " min ago)") or "")) or "not seen"
			local limit = inp.buyBelow and (", buy below " .. ns.Money(inp.buyBelow)) or ""
			r:SetText(inp.qty .. " x " .. name .. ": lowest " .. low .. limit)
		else
			r:SetText(i == 1 and "Nothing to buy in tonight's plan." or "")
		end
	end
end
UI.UpdateAHPanel = Update

scanBtn:SetScript("OnClick", function() ns.Scan.Full(); Update() end)
checkBtn:SetScript("OnClick", function()
	local ids = {}
	for _, inp in ipairs(PlanBuys()) do ids[#ids + 1] = inp.itemID end
	if #ids == 0 then ns.Print("tonight's plan has nothing to buy."); return end
	if ns.Scan.Refresh(ids) then ns.Print("checking " .. #ids .. " prices...") end
end)
planBtn:SetScript("OnClick", function() if not UI.win:IsShown() then UI.Toggle() end end)
S.Tip(checkBtn, "Check plan prices", "Searches the Auction House for each item tonight's plan wants you to buy, so the plan uses current prices.")

local ticker
panel:SetScript("OnShow", function()
	Update()
	if not ticker then ticker = C_Timer.NewTicker(1, Update) end
end)
panel:SetScript("OnHide", function()
	if ticker then ticker:Cancel(); ticker = nil end
end)

ns.On("AH_STATE", function(open)
	if not open then panel:Hide(); return end
	panel:ClearAllPoints()
	if AuctionHouseFrame then
		panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
	else
		panel:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
	end
	if UI.lastPlan == nil and UI.Build then pcall(UI.Build) end -- the buy list needs a plan
	panel:Show()
end)
for _, ev in ipairs({ "SCAN_PROGRESS", "SCAN_DONE", "DISCOVER_DONE", "ITEM_REFRESHED" }) do
	ns.On(ev, function() if panel:IsShown() then Update() end end)
end
