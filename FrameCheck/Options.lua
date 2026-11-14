-- FrameCheck settings window (cards, flat look from Skin.lua). /fcheck opens it.
local _, ns = ...
local S = ns.Skin
local FC = FrameCheck

local function db() return FC.db end

local W = 380
local CW = W - 24
local L = 14
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local panel = S.Window("FrameCheckOptionsFrame", "FrameCheck", "Interface\\Icons\\INV_Misc_PocketWatch_01",
	GetMeta and GetMeta("FrameCheck", "Version"), W, 560)
local more = S.MoreButton(panel.head, "FrameCheck", panel)
more:SetPoint("RIGHT", panel.close, "LEFT", -8, 0)

local refreshers = {}
local function R(f) refreshers[#refreshers + 1] = f end
local function RefreshAll() for _, f in ipairs(refreshers) do f() end end
panel:SetScript("OnShow", RefreshAll)

local function Changed() FC.Apply() end

local function Check(card, label, x, y, key, tip)
	local cb = S.Check(card, label, x, y)
	cb:SetScript("OnClick", function(self) db()[key] = self:GetChecked() and true or false; Changed() end)
	R(function() cb:SetChecked(db()[key]) end)
	if tip then S.Tip(cb, label, tip) end
	return cb
end

-- A < value > row that steps through a list of { value, text } (or through numbers).
local function Choice(card, label, y, key, list)
	R(S.Stepper(card, label, L, y, CW - 2 * L, function()
		for _, c in ipairs(list) do if c[1] == db()[key] then return c[2] end end
		return list[1][2]
	end, function(d)
		local i = 1
		for n, c in ipairs(list) do if c[1] == db()[key] then i = n end end
		db()[key] = list[(i - 1 + d) % #list + 1][1]
		Changed()
	end))
end

local function Indexed(t) local out = {} for i, e in ipairs(t) do out[i] = { i, e[2] } end return out end

-- What to show
local c1 = S.Card(panel, "What to show", 12, -44, CW)
local y = S.Row(c1, 26)
Check(c1, "FPS", L, y, "showFPS")
Check(c1, "Frame time (ms)", L + 150, y, "showMS")
y = S.Row(c1, 26)
Check(c1, "Add-ons %", L, y, "showAddons", "How much of each frame your add-ons use (if the game shares it).")
Check(c1, "Ping", L + 150, y, "showPing")
y = S.Row(c1, 30)
S.Fit(c1, 4)

-- Graph
local cg = S.Card(panel, "Graph", 12, S.Below(c1), CW)
y = S.Row(cg, 30)
Choice(cg, "History", y, "graph", FC.GRAPHS)
y = S.Row(cg, 30)
Choice(cg, "Shows", y, "graphOf", FC.GRAPH_OF)
y = S.Row(cg, 30)
R(S.Stepper(cg, "Height", L, y, CW - 2 * L, function() return tostring(db().graphHeight) end, function(d)
	db().graphHeight = math.max(10, math.min(80, (tonumber(db().graphHeight) or 28) + d * 4))
	Changed()
end))
y = S.Row(cg, 26)
Check(cg, "Ping line (light blue)", L, y, "graphPing", "Draws your ping across the graph, on its own scale. The ping number in the box is light blue to match.")
y = S.Row(cg, 30)
S.Note(cg, "One bar per half second, newest on the right. The faint line is 60 FPS (or 16.7 ms).", L, y, CW - 2 * L)
S.Fit(cg, 4)

-- Look
local c2 = S.Card(panel, "Look", 12, S.Below(cg), CW)
y = S.Row(c2, 30)
Choice(c2, "Font", y, "font", Indexed(FC.FONTS))
y = S.Row(c2, 30)
R(S.Stepper(c2, "Text size", L, y, CW - 2 * L, function() return tostring(db().fontSize) end, function(d)
	db().fontSize = math.max(8, math.min(24, (tonumber(db().fontSize) or 12) + d))
	Changed()
end))
y = S.Row(c2, 30)
Choice(c2, "Text outline", y, "outline", Indexed(FC.OUTLINES))
y = S.Row(c2, 30)
Choice(c2, "Colours", y, "colors", FC.COLORS)
y = S.Row(c2, 30)
R(S.Stepper(c2, "Background", L, y, CW - 2 * L, function()
	local a = tonumber(db().bgAlpha) or 0.75
	return a <= 0 and "None" or ("%d%%"):format(a * 100 + 0.5)
end, function(d)
	db().bgAlpha = math.floor(math.max(0, math.min(1, (tonumber(db().bgAlpha) or 0.75) + d * 0.1)) * 10 + 0.5) / 10
	Changed()
end))
y = S.Row(c2, 26)
Check(c2, "Border", L, y, "border")
y = S.Row(c2, 30)
R(S.Stepper(c2, "Overall size", L, y, CW - 2 * L, function() return ("%.1fx"):format(tonumber(db().scale) or 1) end, function(d)
	db().scale = math.floor(math.max(0.5, math.min(2.5, (tonumber(db().scale) or 1) + d * 0.1)) * 10 + 0.5) / 10
	Changed()
end))
S.Fit(c2, 4)

-- Box
local c3 = S.Card(panel, "Box", 12, S.Below(c2), CW)
y = S.Row(c3, 26)
Check(c3, "Tell me in chat when an add-on causes a stutter", L, y, "spikeAlert",
	"When add-ons take at least half of a slow frame (and 50 ms or more), one chat line names the add-on. At most one every 30 seconds. /fcheck log keeps them.")
y = S.Row(c3, 26)
local shown = S.Check(c3, "Show the box", L, y)
shown:SetScript("OnClick", function(self) db().hidden = not self:GetChecked(); Changed() end)
R(function() shown:SetChecked(not db().hidden) end)
Check(c3, "Lock in place", L + 150, y, "locked", "When unlocked, drag the box to move it.")
S.Fit(c3, 4)

-- Footer
local foot = S.Footer(panel, 40)
local resetLook = S.Button(foot, "Reset look", 110, 24)
resetLook:SetPoint("LEFT", 12, 0)
resetLook:SetScript("OnClick", function()
	local D = FC.DEFAULTS
	for _, k in ipairs({ "showFPS", "showMS", "showAddons", "showPing", "graph", "graphOf", "graphHeight", "graphPing", "font", "fontSize", "outline", "colors", "bgAlpha", "border" }) do
		db()[k] = D[k]
	end
	Changed(); RefreshAll()
end)
S.Tip(resetLook, "Reset look", "Puts what's shown, the font, colours and background back to how they started. Keeps the position.")
local resetPos = S.Button(foot, "Reset position", 120, 24)
resetPos:SetPoint("LEFT", resetLook, "RIGHT", 8, 0)
resetPos:SetScript("OnClick", function()
	local D = FC.DEFAULTS
	db().point, db().scale, db().hidden = { unpack(D.point) }, 1, false
	Changed(); RefreshAll()
end)

panel:SetHeight(-S.Below(c3) + 40 + 2)

function FC.ToggleOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end
