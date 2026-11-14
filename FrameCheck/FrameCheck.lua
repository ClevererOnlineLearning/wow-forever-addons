-- FrameCheck for WoW Forever, by good mens (Mephz on WoW Forever).
-- A small box: FPS, frame time, how much of each frame your add-ons use, and your ping, with an
-- optional little graph of the last 30 or 60 seconds. Hover it for details and a verdict.
--
-- What the game lets add-ons see: the frame rate, how long each frame took, the add-on
-- profiler (C_AddOnProfiler: add-on time vs. the whole frame) and ping. It does NOT give
-- add-ons its CPU vs. GPU timings, so FrameCheck never claims "your GPU is the problem".
--
-- Lean on purpose: each frame only adds to three numbers. Everything else (text, graph,
-- profiler, ping) runs twice a second, and only while the box is shown. No tables are
-- created per frame or per update.

local ADDON_NAME = ...
FrameCheck = {}
local FC = FrameCheck

local DEFAULTS = {
	point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -200, -6 },
	locked = false,
	hidden = false,
	scale = 1,
	-- what to show
	showFPS = true, showMS = true, showAddons = true, showPing = true,
	graph = 30,           -- seconds of history in the graph: 0 (off), 30 or 60
	graphOf = "fps",      -- "fps" or "ms" (frame time: stutters show as spikes)
	graphHeight = 28,
	graphPing = true,     -- light-blue ping line over the bars
	spikeAlert = true,    -- a chat line when an add-on causes a stutter
	-- look
	font = 1,             -- index into FONTS
	fontSize = 12,
	outline = 1,          -- index into OUTLINES
	colors = "traffic",   -- "traffic" (green/yellow/red), "white", "class"
	bgAlpha = 0.75,
	border = true,
}

FC.FONTS = {
	{ "Fonts\\FRIZQT__.TTF", "Game (Friz)" },
	{ "Fonts\\ARIALN.TTF", "Clean (Arial)" },
	{ "Fonts\\MORPHEUS.TTF", "Fancy (Morpheus)" },
	{ "Fonts\\skurri.ttf", "Bold (Skurri)" },
}
FC.OUTLINES = { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" } }
FC.COLORS = { { "traffic", "Green / yellow / red" }, { "white", "All white" }, { "class", "Class colour" } }
FC.GRAPHS = { { 0, "Off" }, { 30, "Last 30 seconds" }, { 60, "Last minute" } }
FC.GRAPH_OF = { { "fps", "FPS" }, { "ms", "Frame time (spikes)" } }

local db
local isSecret = issecretvalue or function() return false end
local function Plain(v) if v == nil or isSecret(v) then return nil end return v end
local function Chat(msg) print("|cff66ccffFrameCheck:|r " .. msg) end

------------------------------------------------------------------------
-- Measuring: half-second samples in a ring (two minutes' worth is more than enough)
------------------------------------------------------------------------
local STEP = 0.5
local SLOTS = 120                            -- 60 s of history
local sFPS, sMS, sWorst, sPing = {}, {}, {}, {} -- per sample: fps, average ms, slowest frame ms, ping
local sHead, sCount = 0, 0

local function AddSample(fps, ms, worst, ping)
	sHead = sHead % SLOTS + 1
	sFPS[sHead], sMS[sHead], sWorst[sHead], sPing[sHead] = fps, ms, worst, ping or false
	if sCount < SLOTS then sCount = sCount + 1 end
end
FC.AddSample = AddSample

-- i = 1 is the newest sample
local function Sample(i)
	local k = (sHead - i) % SLOTS + 1
	return sFPS[k], sMS[k], sWorst[k], sPing[k]
end
FC.Sample = Sample
function FC.SampleCount() return sCount end

-- avg ms, worst ms over the last 5 seconds
function FC.FrameTimes()
	if sCount == 0 then return nil end
	local n = math.min(sCount, 5 / STEP)
	local sum, worst = 0, 0
	for i = 1, n do
		local _, ms, w = Sample(i)
		sum = sum + ms
		if w > worst then worst = w end
	end
	return sum / n, worst
end

function FC.FPS()
	local ok, f = pcall(GetFramerate)
	f = ok and Plain(f)
	if type(f) == "number" then return f end
	return sCount > 0 and (Sample(1)) or nil
end

function FC.Ping()
	if not GetNetStats then return nil end
	local ok, _, _, home, world = pcall(GetNetStats)
	if not ok then return nil end
	return Plain(home), Plain(world)
end

-- The add-on profiler: share of the frame spent in add-ons, or nil if the game won't say.
local P = C_AddOnProfiler
local function Metric()
	local E = Enum and Enum.AddOnProfilerMetric
	return E and E.RecentAverageTime or 1
end

local function ProfilerOn()
	if not (P and P.GetOverallMetric and P.GetApplicationMetric) then return false end
	if P.IsEnabled then
		local ok, on = pcall(P.IsEnabled)
		if ok and Plain(on) == false then return false end
	end
	return true
end

-- addons ms, whole frame ms, share 0-1
function FC.AddOnShare()
	if not ProfilerOn() then return nil end
	local m = Metric()
	local ok1, addons = pcall(P.GetOverallMetric, m)
	local ok2, app = pcall(P.GetApplicationMetric, m)
	addons, app = ok1 and Plain(addons), ok2 and Plain(app)
	if type(addons) ~= "number" or type(app) ~= "number" or app <= 0 then return nil end
	return addons, app, math.min(1, addons / app)
end

-- The heaviest add-ons: { {name, ms}, ... } (up to n), or nil. Only runs for the tooltip
-- and /fcheck addons, never in the background.
function FC.TopAddOns(n, metric)
	if not (ProfilerOn() and P.GetAddOnMetric) then return nil end
	local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
	local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not (num and info and loaded) then return nil end
	local m, out = metric or Metric(), {}
	local okN, total = pcall(num)
	if not okN or type(total) ~= "number" then return nil end
	for i = 1, total do
		local okI, name, title = pcall(info, i)
		if okI and type(name) == "string" then
			local okL, isLoaded = pcall(loaded, name)
			if okL and isLoaded then
				local okM, ms = pcall(P.GetAddOnMetric, name, m)
				ms = okM and Plain(ms)
				if type(ms) == "number" and ms > 0 then
					local t = Plain(title)
					if type(t) ~= "string" or t == "" then t = name end
					out[#out + 1] = { t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), ms }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a[2] > b[2] end)
	while #out > n do table.remove(out) end
	return out
end

-- Stutter log: when one frame takes far longer than usual, note how long it took and how much
-- of it each add-on used in that very frame (the profiler's "last frame" figure). Only runs on a
-- slow frame, at most once a second, so it costs nothing the rest of the time.
local spikes = {}          -- newest first: { t, ms, addons (ms or nil), top = { {name, ms}, ... }, combat }
local lastSpike = -10
local pending              -- a stutter waiting for its second reading (the next frame)
local lastAlert = -100
FC.spikes = spikes

local function LastMetric()
	local E = Enum and Enum.AddOnProfilerMetric
	return E and E.LastTime
end

-- Add-ons' time in the profiler's "last frame": total, and per add-on { name = ms }.
local function ReadLast()
	local LAST = LastMetric()
	if not (LAST and ProfilerOn()) then return nil end
	local ok, all = pcall(P.GetOverallMetric, LAST)
	all = ok and Plain(all)
	if type(all) ~= "number" then return nil end
	local per = {}
	for _, a in ipairs(FC.TopAddOns(1000, LAST) or {}) do per[a[1]] = a[2] end
	return all, per
end

function FC.RecordSpike(ms)
	local now = GetTime()
	if now - lastSpike < 1 then return end
	lastSpike = now
	local e = { t = now, ms = ms, combat = InCombatLockdown and InCombatLockdown() or false }
	e.addons, e.per = ReadLast()
	table.insert(spikes, 1, e)
	while #spikes > 10 do table.remove(spikes) end
	pending = e
end

-- The next frame: read the profiler again and keep the larger figures, in case it reports the
-- slow frame one frame late. Then decide whether an add-on caused it.
function FC.FinishSpike()
	local e = pending
	pending = nil
	if not e then return end
	local all2, per2 = ReadLast()
	if all2 and (not e.addons or all2 > e.addons) then e.addons = all2 end
	local per = e.per or {}
	for name, v in pairs(per2 or {}) do if not per[name] or v > per[name] then per[name] = v end end
	local top = {}
	for name, v in pairs(per) do top[#top + 1] = { name, v } end
	table.sort(top, function(a, b) return a[2] > b[2] end)
	while #top > 3 do table.remove(top) end
	e.top, e.per = top, nil
	if not e.addons then return end
	-- An add-on's fault: add-ons took at least half of the frame, and at least 50 ms.
	if e.addons >= 50 and e.addons >= e.ms * 0.5 then
		e.byAddon = true
		FC.SaveToLog(e)
		local db = FC.db
		if db and db.spikeAlert and e.t - lastAlert >= 30 then
			lastAlert = e.t
			local who = top[1] and (" " .. top[1][1] .. " used %d ms of it"):format(top[1][2] + 0.5) or ""
			print(("|cff66ccffFrameCheck:|r stutter, a %d ms frame.%s |cffffffff/fcheck log|r for details."):format(e.ms + 0.5, who))
		end
	end
end

-- Add-on stutters are kept between sessions (in FrameCheck's saved variables), newest first.
function FC.SaveToLog(e)
	local db = FC.db
	if not db then return end
	db.log = type(db.log) == "table" and db.log or {}
	local parts = {}
	for _, a in ipairs(e.top or {}) do if a[2] >= 1 then parts[#parts + 1] = ("%s %d ms"):format(a[1], a[2] + 0.5) end end
	local zone = GetRealZoneText and Plain(GetRealZoneText()) or nil
	table.insert(db.log, 1, {
		when = date and date("%Y-%m-%d %H:%M") or "?",
		zone = type(zone) == "string" and zone or "?",
		ms = math.floor(e.ms + 0.5), addons = math.floor(e.addons + 0.5),
		combat = e.combat, top = table.concat(parts, ", "),
	})
	while #db.log > 50 do table.remove(db.log) end
end

-- One stutter in plain words.
function FC.SpikeText(e, now)
	local ago = math.floor((now or GetTime()) - e.t + 0.5)
	local s = ("%ds ago: a %d ms frame%s"):format(ago, e.ms + 0.5, e.combat and " (in combat)" or "")
	if e.addons then
		s = s .. (" - add-ons used %d ms of it"):format(e.addons + 0.5)
		if e.top and #e.top > 0 then
			local parts = {}
			for _, a in ipairs(e.top) do if a[2] >= 1 then parts[#parts + 1] = ("%s %d ms"):format(a[1], a[2] + 0.5) end end
			if #parts > 0 then s = s .. ": " .. table.concat(parts, ", ") end
		end
		if e.addons < e.ms * 0.25 then s = s .. ". Mostly the game itself, not add-ons." end
	else
		s = s .. " (the game doesn't say which add-ons)"
	end
	return s
end

-- Your frame-rate limit from the game's settings, or nil.
function FC.Cap()
	if not (C_CVar and C_CVar.GetCVar) and not GetCVar then return nil end
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local function n(name) local ok, v = pcall(get, name); return ok and tonumber(Plain(v)) or nil end
	local cap
	if n("useMaxFPS") == 1 and (n("maxFPS") or 0) > 0 then cap = n("maxFPS") end
	return cap, n("vsync") == 1
end

------------------------------------------------------------------------
-- The verdict, in plain words: { text, r, g, b }
------------------------------------------------------------------------
function FC.Verdict()
	local fps = FC.FPS()
	local avg, worst = FC.FrameTimes()
	local _, _, share = FC.AddOnShare()
	local cap, vsync = FC.Cap()
	local lines = {}
	if fps and cap and fps >= cap * 0.95 then
		lines[#lines + 1] = { ("At your %d FPS limit: nothing is holding you back."):format(cap), 0.3, 1, 0.3 }
	elseif share and share >= 0.25 then
		lines[#lines + 1] = { ("Add-ons use %d%% of each frame: they are slowing you down."):format(share * 100 + 0.5), 1, 0.3, 0.3 }
	elseif share and share >= 0.10 then
		lines[#lines + 1] = { ("Add-ons use %d%% of each frame: noticeable, not the main cost."):format(share * 100 + 0.5), 1, 0.82, 0 }
	elseif fps then
		lines[#lines + 1] = { "The game itself is the limit, not your add-ons.", 1, 1, 1 }
		lines[#lines + 1] = { "Lower the graphics settings: if FPS rises a lot, it's your graphics card.", 0.75, 0.75, 0.75 }
		lines[#lines + 1] = { "If it barely changes, it's your processor (busy cities, lots of players).", 0.75, 0.75, 0.75 }
	end
	if vsync then
		lines[#lines + 1] = { "VSync is on: FPS can't go above your monitor's refresh rate.", 0.75, 0.75, 0.75 }
	end
	if avg and worst and worst > 50 and worst > avg * 3 then
		lines[#lines + 1] = { ("Stutter: one frame took %d ms in the last 5 seconds."):format(worst + 0.5), 1, 0.6, 0.2 }
	end
	return lines
end

------------------------------------------------------------------------
-- The box
------------------------------------------------------------------------
local box = CreateFrame("Frame", "FrameCheckFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
box:SetSize(220, 22)
box:SetFrameStrata("MEDIUM")
box:SetClampedToScreen(true)
box:SetMovable(true)
box:EnableMouse(true)
box:RegisterForDrag("LeftButton")
if box.SetBackdrop then
	box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	box:SetBackdropColor(0.04, 0.04, 0.06, 0.75)
	box:SetBackdropBorderColor(0.3, 0.3, 0.36, 0.9)
end
box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
box.text:SetPoint("TOP", 0, -5)
box:Hide()

local function ClassRGB()
	if not UnitClass then return 1, 1, 1 end
	local _, class = UnitClass("player")
	local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if not c then return 1, 1, 1 end
	return c.r, c.g, c.b
end

-- 1 = good, 2 = so-so, 3 = bad
local function Grade(v, good, bad, lowIsGood)
	if lowIsGood then return v <= good and 1 or v <= bad and 2 or 3 end
	return v >= good and 1 or v >= bad and 2 or 3
end
local TRAFFIC = { { 0.3, 1, 0.3 }, { 1, 0.82, 0 }, { 1, 0.3, 0.3 } }
local TRAFFIC_HEX = { "|cff4dff4d", "|cffffd100", "|cffff4d4d" }
local PING_RGB = { 0.4, 0.75, 1 }
local PING_HEX = "|cff66bfff"

local function Color(v, good, bad, lowIsGood)
	if v == nil then return "|cff888888" end
	if db and db.colors == "white" then return "|cffffffff" end
	if db and db.colors == "class" then
		local r, g, b = ClassRGB()
		return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
	end
	return TRAFFIC_HEX[Grade(v, good, bad, lowIsGood)]
end

function FC.Line()
	local fps = FC.FPS()
	local avg = FC.FrameTimes()
	local o = db or DEFAULTS
	local parts = {}
	if o.showFPS then parts[#parts + 1] = Color(fps, 55, 30) .. (fps and ("%d"):format(fps + 0.5) or "?") .. "|r fps" end
	if o.showMS then parts[#parts + 1] = Color(avg, 18.5, 33.5, true) .. (avg and ("%.1f"):format(avg) or "?") .. "|r ms" end
	if o.showAddons then
		local _, _, share = FC.AddOnShare()
		if share then parts[#parts + 1] = "add-ons " .. Color(share * 100, 10, 25, true) .. ("%d%%"):format(share * 100 + 0.5) .. "|r" end
	end
	if o.showPing then
		local home, world = FC.Ping()
		if home or world then
			local ping = math.max(home or 0, world or 0)
			-- ping has its own colour (light blue, like its graph line); red when it's bad
			local c = (db and db.colors == "white") and "|cffffffff" or (ping >= 250 and "|cffff4d4d" or PING_HEX)
			parts[#parts + 1] = c .. ping .. "|r ping"
		end
	end
	if #parts == 0 then return "|cff888888FrameCheck|r" end
	return table.concat(parts, "   ")
end

------------------------------------------------------------------------
-- The graph: one bar per half second, made once and only resized afterwards
------------------------------------------------------------------------
local graph = CreateFrame("Frame", nil, box)
graph:SetPoint("BOTTOMLEFT", 6, 5)
graph:SetPoint("BOTTOMRIGHT", -6, 5)
graph:Hide()
local gLine = graph:CreateTexture(nil, "BORDER") -- faint line at the "good" level (60 fps / 16.7 ms)
gLine:SetHeight(1)
gLine:SetColorTexture(1, 1, 1, 0.15)
local bars, barGrade = {}, {}
local pingSegs = {} -- one short light-blue line piece per bar: together they draw the ping line
FC.bars = bars

local function GraphBars() return (db and tonumber(db.graph) or 0) / STEP end

local function Bar(i)
	local b = bars[i]
	if not b then
		b = graph:CreateTexture(nil, "ARTWORK")
		bars[i] = b
	end
	return b
end

local function DrawGraph()
	local n = GraphBars()
	if n <= 0 then return end
	local h = math.max(10, math.min(80, tonumber(db.graphHeight) or 28))
	local w = box:GetWidth()
	if type(w) ~= "number" or w <= 12 then return end
	w = w - 12
	local bw = w / n
	-- bars only move when the box changes width or the history length changes
	local moved = (w ~= graph.w or n ~= graph.n)
	graph.w, graph.n = w, n
	local ofMS = db.graphOf == "ms"
	-- scale: FPS up to your limit (or the best seen); frame time up to the slowest seen (at least 33 ms)
	local top = ofMS and 33.3 or 60
	for i = 1, math.min(n, sCount) do
		local f, _, worst = Sample(i)
		local v = ofMS and worst or f
		if v > top then top = v end
	end
	local cap = not ofMS and FC.Cap()
	if cap and cap > top then top = cap end
	local good = ofMS and 16.7 or 60
	local ly = math.floor(math.min(h, h * good / top) + 0.5)
	if ly ~= gLine.y then
		gLine.y = ly
		gLine:ClearAllPoints()
		gLine:SetPoint("BOTTOMLEFT", 0, ly)
		gLine:SetPoint("BOTTOMRIGHT", 0, ly)
	end
	local mode = db.colors
	local cr, cg, cb = ClassRGB()
	for i = 1, n do
		local b = Bar(i)
		if i > sCount then
			b:Hide()
		else
			local f, _, worst = Sample(i)
			local v = ofMS and worst or f
			if moved or not b.placed then -- newest on the right
				b:ClearAllPoints()
				b:SetPoint("BOTTOMLEFT", w - i * bw, 0)
				b:SetWidth(math.max(1, bw - (bw >= 3 and 1 or 0)))
				b.placed = true
			end
			b:SetHeight(math.max(1, h * math.min(1, v / top)))
			local g = mode == "traffic" and Grade(v, ofMS and 18.5 or 55, ofMS and 33.5 or 30, ofMS) or (mode == "class" and 4 or 5)
			if barGrade[i] ~= g then
				barGrade[i] = g
				if g <= 3 then b:SetColorTexture(TRAFFIC[g][1], TRAFFIC[g][2], TRAFFIC[g][3], 0.85)
				elseif g == 4 then b:SetColorTexture(cr, cg, cb, 0.85)
				else b:SetColorTexture(1, 1, 1, 0.75) end
			end
			b:Show()
		end
	end
	for i = n + 1, #bars do bars[i]:Hide() end
	-- ping line, on its own scale (at least 200 ms tall, so a steady low ping sits low)
	local showPing = db.graphPing
	local ptop = 200
	if showPing then
		for i = 1, math.min(n, sCount) do
			local _, _, _, p = Sample(i)
			if p and p * 1.2 > ptop then ptop = p * 1.2 end
		end
	end
	if ptop ~= graph.ptop then graph.ptop = ptop; moved = true end
	for i = 1, n do
		local seg = pingSegs[i]
		local _, _, _, p = Sample(i)
		if showPing and i <= sCount and p then
			if not seg then
				seg = graph:CreateTexture(nil, "OVERLAY")
				seg:SetColorTexture(PING_RGB[1], PING_RGB[2], PING_RGB[3], 0.95)
				seg:SetHeight(2)
				pingSegs[i] = seg
			end
			local py = math.floor(math.min(h - 2, h * p / ptop) + 0.5)
			if moved or seg.y ~= py then
				seg.y = py
				seg:ClearAllPoints()
				seg:SetPoint("BOTTOMLEFT", w - i * bw, py)
				seg:SetWidth(math.max(1, bw))
			end
			seg:Show()
		elseif seg then
			seg:Hide()
		end
	end
	for i = n + 1, #pingSegs do pingSegs[i]:Hide() end
end
FC.DrawGraph = DrawGraph

local lastText
local function Resize()
	local w, th = box.text:GetStringWidth(), box.text:GetStringHeight()
	if type(th) ~= "number" or th <= 0 then th = 12 end
	local graphOn = GraphBars() > 0
	local gh = graphOn and math.max(10, math.min(80, tonumber(db.graphHeight) or 28)) or 0
	-- the box only grows (until settings change), so it doesn't twitch as numbers change
	if type(w) == "number" and w > 0 then
		local want = math.max(w + 16, graphOn and 160 or 0)
		if not box.fixedW or want > box.fixedW then box.fixedW = want; box:SetWidth(want) end
	end
	box:SetHeight(th + 10 + (graphOn and gh + 5 or 0))
	graph:SetHeight(gh > 0 and gh or 1)
	graph:SetShown(graphOn)
end

-- Font, outline, background and border from the settings.
local function ApplyLook()
	local f = FC.FONTS[db.font] or FC.FONTS[1]
	local o = FC.OUTLINES[db.outline] or FC.OUTLINES[1]
	local size = math.max(8, math.min(24, tonumber(db.fontSize) or 12))
	if not box.text:SetFont(f[1], size, o[1]) then box.text:SetFont(FC.FONTS[1][1], size, o[1]) end
	if box.SetBackdrop then
		box:SetBackdropColor(0.04, 0.04, 0.06, tonumber(db.bgAlpha) or 0.75)
		box:SetBackdropBorderColor(0.3, 0.3, 0.36, db.border and 0.9 or 0)
	end
	for i in pairs(barGrade) do barGrade[i] = nil end -- colours may have changed
end

local function ShowTooltip()
	GameTooltip:SetOwner(box, "ANCHOR_BOTTOMLEFT")
	GameTooltip:AddLine("FrameCheck")
	local fps = FC.FPS()
	local avg, worst = FC.FrameTimes()
	GameTooltip:AddDoubleLine("Frames per second", fps and ("%d"):format(fps + 0.5) or "?", 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddDoubleLine("Frame time (average, 5 s)", avg and ("%.1f ms"):format(avg) or "?", 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddDoubleLine("Slowest frame (5 s)", worst and ("%.1f ms"):format(worst) or "?", 0.8, 0.8, 0.8, 1, 1, 1)
	local n = math.min(GraphBars() > 0 and GraphBars() or 60, sCount)
	if n > 0 then
		local lo, hi = math.huge, 0
		for i = 1, n do local f = Sample(i); if f < lo then lo = f end; if f > hi then hi = f end end
		GameTooltip:AddDoubleLine(("FPS range (last %d s)"):format(n * STEP + 0.5), ("%d - %d"):format(lo + 0.5, hi + 0.5), 0.8, 0.8, 0.8, 1, 1, 1)
		local plo, phi = math.huge, 0
		for i = 1, n do local _, _, _, p = Sample(i); if p then if p < plo then plo = p end; if p > phi then phi = p end end end
		if phi > 0 then
			GameTooltip:AddDoubleLine(("Ping range (last %d s)"):format(n * STEP + 0.5), ("%d - %d ms"):format(plo, phi), 0.8, 0.8, 0.8, PING_RGB[1], PING_RGB[2], PING_RGB[3])
		end
	end
	local cap, vsync = FC.Cap()
	GameTooltip:AddDoubleLine("FPS limit", cap and tostring(cap) or (vsync and "VSync" or "none"), 0.8, 0.8, 0.8, 1, 1, 1)
	local home, world = FC.Ping()
	if home or world then
		GameTooltip:AddDoubleLine("Ping (home / world)", ("%s / %s ms"):format(home or "?", world or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	local addons, app, share = FC.AddOnShare()
	if share then
		GameTooltip:AddDoubleLine("Add-ons per frame", ("%.2f of %.1f ms (%d%%)"):format(addons, app, share * 100 + 0.5), 0.8, 0.8, 0.8, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine("Add-ons per frame", "the game doesn't say", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine(" ")
	for _, l in ipairs(FC.Verdict()) do GameTooltip:AddLine(l[1], l[2], l[3], l[4], true) end
	if spikes[1] and GetTime() - spikes[1].t < 120 then
		GameTooltip:AddLine("Last stutter: " .. FC.SpikeText(spikes[1]), 1, 0.6, 0.2, true)
	end
	local top = FC.TopAddOns(5)
	if top and #top > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Heaviest add-ons")
		for _, e in ipairs(top) do GameTooltip:AddDoubleLine(e[1], ("%.2f ms"):format(e[2]), 1, 1, 1, 1, 0.82, 0) end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine((db.locked and "Locked" or "Drag to move") .. "   Right-click: settings", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- Twice a second, only while the box is shown.
local function Redraw()
	if not db or not box:IsShown() then return end
	local t = FC.Line()
	if t ~= lastText then lastText = t; box.text:SetText(t) end
	Resize()
	DrawGraph()
	if GameTooltip:IsOwned(box) then ShowTooltip() end
end
FC.Redraw = Redraw

box:SetScript("OnEnter", ShowTooltip)
box:SetScript("OnLeave", function() GameTooltip:Hide() end)
box:SetScript("OnMouseUp", function(_, button) if button == "RightButton" and FC.ToggleOptions then FC.ToggleOptions() end end)
box:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
box:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint()
	db.point = { p, "UIParent", rp, x, y }
end)

-- The only per-frame work: add this frame's time to three numbers.
local acc, frames, slowest = 0, 0, 0
local meter = CreateFrame("Frame")
meter:SetScript("OnUpdate", function(_, elapsed)
	acc, frames = acc + elapsed, frames + 1
	if elapsed > slowest then slowest = elapsed end
	if pending then FC.FinishSpike() end
	-- a stutter: over 50 ms and over three times the usual frame
	if elapsed > 0.05 and sCount > 0 and elapsed * 1000 > 3 * sMS[sHead] then FC.RecordSpike(elapsed * 1000) end
	if acc >= STEP then
		local ping
		if GetNetStats then
			local ok, _, _, home, world = pcall(GetNetStats)
			if ok then ping = math.max(tonumber(Plain(home)) or 0, tonumber(Plain(world)) or 0) end
		end
		AddSample(frames / acc, acc / frames * 1000, slowest * 1000, ping)
		acc, frames, slowest = 0, 0, 0
		Redraw()
	end
end)
FC.meter = meter

local function Apply()
	box:ClearAllPoints()
	local p = db.point
	box:SetPoint(p[1], UIParent, p[3], p[4], p[5])
	box:SetScale(tonumber(db.scale) or 1)
	box:SetShown(not db.hidden)
	ApplyLook()
	box.fixedW = nil
	lastText = FC.Line()
	box.text:SetText(lastText)
	Resize()
	DrawGraph()
end
FC.Apply = Apply
FC.DEFAULTS = DEFAULTS

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON_NAME then return end
	FrameCheckDB = type(FrameCheckDB) == "table" and FrameCheckDB or {}
	db = FrameCheckDB
	db.stacked = nil -- 1.1's stacked layout, replaced by the graph
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then
			if type(v) == "table" then local c = {} for i, x in pairs(v) do c[i] = x end db[k] = c else db[k] = v end
		end
	end
	if type(db.point) ~= "table" or #db.point < 5 then db.point = { unpack(DEFAULTS.point) } end
	if db.graph ~= 0 and db.graph ~= 30 and db.graph ~= 60 then db.graph = DEFAULTS.graph end
	if db.graphOf ~= "fps" and db.graphOf ~= "ms" then db.graphOf = "fps" end
	FC.db = db
	self:UnregisterEvent("ADDON_LOADED")
	Apply()
end)

------------------------------------------------------------------------
-- /fcheck
------------------------------------------------------------------------
SLASH_FRAMECHECK1 = "/fcheck"
SLASH_FRAMECHECK2 = "/framecheck"
SlashCmdList.FRAMECHECK = function(msg)
	local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "lock" then
		db.locked = true; Chat("locked.")
	elseif cmd == "unlock" or cmd == "move" then
		db.locked = false; Chat("unlocked: drag the box, then /fcheck lock.")
	elseif cmd == "" or cmd == "options" or cmd == "config" then
		if FC.ToggleOptions then FC.ToggleOptions() end
	elseif cmd == "hide" or cmd == "show" then
		db.hidden = (cmd == "hide")
		Apply(); Chat(db.hidden and "hidden (/fcheck show to bring it back)." or "shown.")
	elseif cmd == "scale" then
		local n = tonumber(rest)
		if n and n >= 0.5 and n <= 2.5 then db.scale = n; Apply() end
		Chat("size " .. tostring(db.scale))
	elseif cmd == "reset" then
		db.point, db.scale, db.hidden = { unpack(DEFAULTS.point) }, 1, false; Apply(); Chat("position and size reset.")
	elseif cmd == "spikes" or cmd == "stutters" then
		if #spikes == 0 then Chat("no stutters recorded since you logged in (a stutter = a frame over 50 ms and 3x your usual).") return end
		Chat("the last stutters, newest first:")
		local now = GetTime()
		for _, e in ipairs(spikes) do print("  " .. FC.SpikeText(e, now)) end
	elseif cmd == "log" then
		local log = type(db.log) == "table" and db.log or {}
		if rest == "clear" then db.log = {}; Chat("stutter log cleared.") return end
		if #log == 0 then Chat("no add-on has caused a stutter yet (kept between sessions; /fcheck spikes shows every stutter this session).") return end
		Chat("stutters caused by add-ons, newest first (" .. #log .. " kept, /fcheck log clear to empty):")
		for i, l in ipairs(log) do
			if i > 15 then print("  ... and " .. (#log - 15) .. " older ones in FrameCheck's saved variables file.") break end
			print(("  %s, %s: a %d ms frame, add-ons %d ms%s%s"):format(l.when, l.zone, l.ms, l.addons, l.combat and " (in combat)" or "", l.top ~= "" and (" - " .. l.top) or ""))
		end
	elseif cmd == "addons" then
		local top = FC.TopAddOns(10)
		if not top then Chat("the game doesn't share add-on timings.") return end
		if #top == 0 then Chat("no add-on is using measurable time right now.") return end
		Chat("heaviest add-ons (average ms per frame):")
		for i, e in ipairs(top) do print(("  %d. %s  |cffffd100%.2f ms|r"):format(i, e[1], e[2])) end
	else
		Chat("/fcheck  settings")
		print("  /fcheck show | hide   /fcheck lock | unlock   /fcheck scale 1.2   /fcheck reset")
		print("  /fcheck addons  the 10 heaviest add-ons   /fcheck spikes  your last stutters and what caused them")
		print("  /fcheck log  stutters caused by add-ons, kept between sessions")
	end
end
