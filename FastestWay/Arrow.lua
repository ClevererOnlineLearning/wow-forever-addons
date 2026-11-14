-- Fastest Way To: the heads-up arrow (points to where your current step ends) and the
-- route drawn as a dotted line on the world map. Our own code and the game's own minimap
-- arrow picture; nothing from other add-ons. Reads only your position and facing.
local _, ns = ...
local R = ns.Route
local FW = FastestWay
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local Pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) if v == nil or Secret(v) then return nil end return v end
local PI, PI2 = math.pi, math.pi * 2

------------------------------------------------------------------------
-- Maths (kept separate so it can be tested)
------------------------------------------------------------------------
-- Turn needed, -pi..pi: 0 = straight ahead, positive = to your left. Both angles are
-- counter-clockwise from north, the way the game and HereBeDragons give them.
function FW.Turn(bearing, facing)
	return (bearing - facing + PI) % PI2 - PI
end

-- Green within 30 degrees, yellow up to 90, red when it's behind you.
function FW.TurnColor(turn)
	local off = math.abs(turn)
	if off <= PI / 6 then return 0.2, 1, 0.2 end
	if off <= PI / 2 then return 1, 0.85, 0.1 end
	return 1, 0.25, 0.2
end

-- "240 yd", "1,240 yd"
function FW.Yards(y)
	local n = math.floor(y + 0.5)
	if n >= 1000 then return ("%d,%03d yd"):format(math.floor(n / 1000), n % 1000) end
	return n .. " yd"
end

------------------------------------------------------------------------
-- The arrow
------------------------------------------------------------------------
local a = CreateFrame("Button", "FastestWayArrow", UIParent)
a:SetSize(48, 48) -- only the arrow itself takes the mouse, so it never blocks clicks in the world
a:SetFrameStrata("MEDIUM")
a:SetClampedToScreen(true)
a:SetMovable(true)
a:EnableMouse(true)
a:RegisterForDrag("LeftButton")
a:RegisterForClicks("RightButtonUp")
a:Hide()
local tex = a:CreateTexture(nil, "ARTWORK")
tex:SetAllPoints()
tex:SetTexture("Interface\\Minimap\\MinimapArrow")
local label = a:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetPoint("TOP", a, "BOTTOM", 0, -2)
label:SetWidth(260)
label:SetJustifyH("CENTER")
local dist = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dist:SetPoint("TOP", label, "BOTTOM", 0, -2)
FW.arrow, FW.arrowTex, FW.arrowLabel, FW.arrowDist = a, tex, label, dist
-- On a hearthstone step: a button right here, in the middle of the screen, for when it's on cooldown.
local S = ns.Skin
local cd = S.Button(a, "Hearthstone on cooldown", 170, 22)
cd:SetPoint("TOP", dist, "BOTTOM", 0, -6)
cd:Hide()
S.Tip(cd, "Hearthstone on cooldown?", "Works the route out again without your hearthstone, and leaves it out for an hour.")
cd:SetScript("OnClick", function() if FW.HearthNotReady then FW.HearthNotReady() end end)
FW.arrowHearth = cd

local function Place()
	local p = FW.db and FW.db.arrowPos
	a:ClearAllPoints()
	if type(p) == "table" and p[1] then a:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else a:SetPoint("CENTER", UIParent, "CENTER", 0, 200) end -- a bit above your character
end

a:SetScript("OnDragStart", function(self) if not FW.db.arrowLocked then self:StartMoving() end end)
a:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint()
	if p then FW.db.arrowPos = { p, rp, x, y } end
end)
a:SetScript("OnClick", function()
	FW.db.arrowLocked = not FW.db.arrowLocked
	print("|cff66ccffFastest Way To|r: arrow " .. (FW.db.arrowLocked and "locked. Right-click it again to unlock." or "unlocked: drag it to move it."))
end)
a:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("Fastest Way To")
	if FW.steps and FW.steps[1] then GameTooltip:AddLine(FW.steps[1].text, 1, 1, 1, true) end
	GameTooltip:AddLine(FW.db.arrowLocked and "Right-click to unlock" or "Drag to move, right-click to lock", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
a:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- What the arrow shows right now. Returns true when it is pointing.
function FW.UpdateArrow()
	local step = FW.steps and FW.steps[1]
	if not step then a:Hide() return false end
	local ok, onTaxi = pcall(UnitOnTaxi, "player")
	if ok and Plain(onTaxi) then a:SetAlpha(0) return false end -- out of the way while you fly
	a:SetAlpha(1)
	label:SetText(step.text)
	cd:SetShown(step.kind == "hearth")
	-- Only running steps have somewhere to point; for the others the words say what to do.
	if step.kind ~= "run" or not (HBD and step.to) then tex:Hide(); dist:SetText("") return false end
	local px, py, inst = HBD:GetPlayerWorldPosition()
	px, py, inst = Plain(px), Plain(py), Plain(inst)
	if not (px and py) or inst ~= step.to.inst then tex:Hide(); dist:SetText("") return false end
	local aim = FW.NextCorner(step, px, py)
	local bearing = HBD:GetWorldVector(inst, px, py, aim.wx, aim.wy)
	local _, yards = HBD:GetWorldVector(inst, px, py, step.to.wx, step.to.wy) -- distance: to the end of the step
	if not bearing then tex:Hide(); dist:SetText("") return false end
	local facing = GetPlayerFacing and Plain(GetPlayerFacing())
	if not facing then
		tex:Hide()
		dist:SetText(FW.Yards(yards) .. "  |cff9d9d9d(the game hides which way you're facing)|r")
		return false
	end
	local turn = FW.Turn(bearing, facing)
	tex:SetRotation(turn)
	tex:SetVertexColor(FW.TurnColor(turn))
	tex:Show()
	dist:SetText(FW.Yards(yards))
	return true
end

-- Which corner of the running step to point at: the first one you haven't reached yet
-- (within 40 yards counts as reached). The last corner is where the step ends.
local corner = 2
function FW.NextCorner(step, px, py)
	local pts = step.pts
	if not pts or #pts < 2 then return step.to end
	if corner > #pts then corner = #pts end
	while corner < #pts do
		local p = pts[corner]
		local dx, dy = p.wx - px, p.wy - py
		if dx * dx + dy * dy > 40 * 40 then break end
		corner = corner + 1
	end
	return pts[corner]
end
function FW.ResetCorner() corner = 2 end

local acc = 0
a:SetScript("OnUpdate", function(_, dt)
	acc = acc + dt
	if acc < 0.03 then return end
	acc = 0
	FW.UpdateArrow()
end)

------------------------------------------------------------------------
-- Dotted route line on the world map
------------------------------------------------------------------------
local LINE = "FastestWayLine"
local MAX_DOTS = 300
local COLORS = { run = { 1, 0.82, 0 }, fly = { 0.35, 0.8, 1 }, boat = { 1, 1, 1 }, zeppelin = { 1, 1, 1 } }
FW.LINE_COLORS = COLORS
local dots = {}

local function Dot(i)
	local d = dots[i]
	if not d then
		d = CreateFrame("Frame") -- no mouse: Alt+click on the map still goes through
		d:SetSize(5, 5)
		local t = d:CreateTexture(nil, "OVERLAY")
		t:SetAllPoints()
		t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		d.tex = t
		dots[i] = d
	end
	return d
end

-- The corners of one leg, in world coordinates: running goes through the middle of each zone
-- on the way (as the route itself counts it), the rest go straight. Hearth and tram: nothing.
function FW.LegPoints(l)
	if not (l.from and l.to) or l.from.inst ~= l.to.inst then return nil end
	if l.kind == "run" and l.pts and #l.pts >= 2 then
		return l.pts
	elseif l.kind == "run" then
		local pts = { l.from }
		for _, z in ipairs(l.through or {}) do
			local c = R.Point(z, 0.5, 0.5, "", "zone")
			if c and c.inst == l.from.inst then pts[#pts + 1] = c end
		end
		pts[#pts + 1] = l.to
		return pts
	elseif COLORS[l.kind] then
		return { l.from, l.to }
	end
end

local function Len(a2, b) local dx, dy = a2.wx - b.wx, a2.wy - b.wy; return math.sqrt(dx * dx + dy * dy) end

-- Returns a list of { wx, wy, inst, kind } dots along the route, evenly spaced.
function FW.LineDots(route)
	local legs, total = {}, 0
	for _, l in ipairs(route and route.legs or {}) do
		local pts = FW.LegPoints(l)
		if pts then
			legs[#legs + 1] = { kind = l.kind, pts = pts, approx = l.kind == "run" and l.approx or nil }
			for i = 2, #pts do total = total + Len(pts[i - 1], pts[i]) end
		end
	end
	local out = {}
	if total <= 0 then return out end
	local step = math.max(15, total / MAX_DOTS)
	for _, leg in ipairs(legs) do
		local carry = 0 -- each leg starts with a dot, so the colour change shows where it begins
		for i = 2, #leg.pts do
			local p, q = leg.pts[i - 1], leg.pts[i]
			local len = Len(p, q)
			local d = carry
			while d <= len and #out < MAX_DOTS do
				local f = len > 0 and d / len or 0
				out[#out + 1] = { wx = p.wx + (q.wx - p.wx) * f, wy = p.wy + (q.wy - p.wy) * f, inst = p.inst, kind = leg.kind, approx = leg.approx }
				d = d + (leg.approx and step * 2.5 or step) -- an estimate: sparse dots, so it doesn't look like a real path
			end
			carry = d - len
		end
	end
	return out
end

local function ClearLine()
	if Pins then pcall(Pins.RemoveAllWorldMapIcons, Pins, LINE) end
end

local function DrawLine()
	ClearLine()
	if not (Pins and FW.db and FW.db.line and FW.route) then return 0 end
	local list = FW.LineDots(FW.route)
	for i, p in ipairs(list) do
		local d = Dot(i)
		local c = COLORS[p.kind] or COLORS.run
		d.tex:SetVertexColor(c[1], c[2], c[3], p.approx and 0.45 or 0.9)
		pcall(Pins.AddWorldMapIconWorld, Pins, LINE, d, p.inst, p.wx, p.wy, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
	end
	return #list
end
FW.DrawLine = DrawLine

------------------------------------------------------------------------
-- Following the route
------------------------------------------------------------------------
function FW.RouteChanged()
	if not FW.db then return end
	FW.ResetCorner()
	DrawLine()
	if FW.db.arrow and FW.steps and FW.steps[1] then
		Place()
		a:Show()
		FW.UpdateArrow()
	else
		a:Hide()
	end
end

-- Every way a route is shown, changed or cleared goes through FW.Show.
local baseShow = FW.Show
function FW.Show(...)
	baseShow(...)
	FW.RouteChanged()
end
