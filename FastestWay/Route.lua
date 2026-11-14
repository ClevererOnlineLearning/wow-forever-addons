-- Fastest Way To: the route finder.
-- Places become points in world yards (HereBeDragons). Getting around:
--   run       between any two points you can walk between, following real zone-to-zone links
--   fly       between flight points (read from the game; ones you haven't been to are "maybe")
--   boat/zeppelin/tram  between their docks
--   hearth    from where you are to your inn
-- The quickest chain wins (Dijkstra). Read-only: nothing is clicked or cast for you.
local _, ns = ...
local D = ns.Data
local R = {}
ns.Route = R

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) if v == nil or Secret(v) then return nil end return v end
local sqrt, atan2, pi, huge = math.sqrt, math.atan2 or function(a, b) return math.atan(a, b) end, math.pi, math.huge

------------------------------------------------------------------------
-- Maps and points
------------------------------------------------------------------------
local nameCache = {}
function R.MapName(id)
	if not id then return "?" end
	local n = nameCache[id]
	if n == nil then
		local ok, info = pcall(C_Map.GetMapInfo, id)
		n = ok and type(info) == "table" and Plain(info.name) or ("map " .. id)
		nameCache[id] = n
	end
	return n
end

-- The zone (from D.ZONES) a map belongs to, climbing up from sub-zones and dungeons.
function R.ZoneOf(map)
	local guard = 0
	while map and not D.ZONES[map] and guard < 10 do
		local ok, info = pcall(C_Map.GetMapInfo, map)
		map = ok and type(info) == "table" and Plain(info.parentMapID) or nil
		guard = guard + 1
	end
	return D.ZONES[map] and map or nil
end

-- The zone under a spot on a continent (or any) map.
function R.ZoneAt(map, x, y)
	if D.ZONES[map] then return map end
	if C_Map.GetMapInfoAtPosition then
		local ok, info = pcall(C_Map.GetMapInfoAtPosition, map, x, y)
		if ok and type(info) == "table" and Plain(info.mapID) then
			local z = R.ZoneOf(info.mapID)
			if z then return z end
		end
	end
	return R.ZoneOf(map)
end

-- A place: { label, kind, map, x, y, zone, wx, wy, inst }
function R.Point(map, x, y, label, kind)
	if not (HBD and map and x and y) then return nil end
	local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x, y, map)
	if not wx then return nil end
	return { label = label, kind = kind or "place", map = map, x = x, y = y, zone = R.ZoneAt(map, x, y), wx = wx, wy = wy, inst = inst }
end

function R.PlayerPoint()
	if not HBD then return nil end
	local x, y, map = HBD:GetPlayerZonePosition()
	if not (x and y and map) then return nil end
	local p = R.Point(map, x, y, "you", "start")
	return p
end

local function Dist(a, b)
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return sqrt(dx * dx + dy * dy)
end
R.Dist = Dist

-- 8-point compass direction from a to b. World x shrinks going east, world y shrinks going south.
local DIRS = { "east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east" }
function R.Direction(a, b)
	local east, north = a.wx - b.wx, b.wy - a.wy
	if east == 0 and north == 0 then return "here" end
	local ang = atan2(north, east)
	local i = math.floor((ang / (2 * pi) * 8) + 0.5) % 8
	return DIRS[i + 1]
end

------------------------------------------------------------------------
-- Zone links: which zones you run through
------------------------------------------------------------------------
local links, centers = nil, {}
local function Links()
	if links then return links end
	links = {}
	for _, l in ipairs(D.LINKS) do
		local a, b = l[1], l[2]
		links[a] = links[a] or {}; links[b] = links[b] or {}
		links[a][#links[a] + 1] = b; links[b][#links[b] + 1] = a
	end
	return links
end

local function Center(z)
	local c = centers[z]
	if c == nil then c = R.Point(z, 0.5, 0.5, R.MapName(z), "zone") or false; centers[z] = c end
	return c or nil
end

local pathCache = {}
-- Zones from za to zb (both included), shortest by the distance between zone middles; nil = no way on foot.
function R.ZonePath(za, zb)
	if not za or not zb then return nil end
	if za == zb then return { za } end
	local key = za .. ">" .. zb
	local cached = pathCache[key]
	if cached ~= nil then return cached or nil end
	local L = Links()
	local dist, prev, done = { [za] = 0 }, {}, {}
	while true do
		local best, bd = nil, huge
		for z, d in pairs(dist) do if not done[z] and d < bd then best, bd = z, d end end
		if not best or best == zb then break end
		done[best] = true
		local cb = Center(best)
		for _, n in ipairs(L[best] or {}) do
			local cn = Center(n)
			if cb and cn and cb.inst == cn.inst then
				local nd = bd + Dist(cb, cn)
				if not dist[n] or nd < dist[n] then dist[n], prev[n] = nd, best end
			end
		end
	end
	if not dist[zb] then pathCache[key] = false; return nil end
	local path, z = {}, zb
	while z do table.insert(path, 1, z); z = prev[z] end
	pathCache[key] = path
	return path
end

-- Where the road crosses from zone za into zone zb: a list of points in travel order, or nil.
local gateCache = {}
function R.Gate(za, zb)
	local key = za .. ">" .. zb
	local g = gateCache[key]
	if g ~= nil then return g or nil end
	local raw, rev = D.GATES and D.GATES[za .. "-" .. zb], false
	if not raw then raw, rev = D.GATES and D.GATES[zb .. "-" .. za], true end
	g = false
	if raw then
		local pts = {}
		for i = 1, #raw do
			local r = raw[rev and (#raw + 1 - i) or i]
			local pt = R.Point(r[1], r[2], r[3], "", "road")
			if pt then pts[#pts + 1] = pt end
		end
		if #pts > 0 then g = pts end
	end
	gateCache[key] = g
	return g or nil
end

-- Yards to run from a to b, the zones in between, and the corners of the way there (the road
-- crossings between zones, or a zone's middle where no crossing is known); nil if you can't run there.
function R.RunLength(a, b)
	if a.inst ~= b.inst then return nil end
	local za, zb = a.zone, b.zone
	if not za or not zb or za == zb then
		if za and zb and za ~= zb then return nil end
		return Dist(a, b), {}, { a, b }
	end
	local path = R.ZonePath(za, zb)
	if not path then return nil end
	local len, last, pts = 0, a, { a }
	local function go(p) if p and p.inst == a.inst then len = len + Dist(last, p); last = p; pts[#pts + 1] = p end end
	local through = {}
	for i = 1, #path - 1 do
		local g = R.Gate(path[i], path[i + 1])
		if g then
			for _, p in ipairs(g) do go(p) end
		elseif i + 1 < #path then
			go(Center(path[i + 1]))
		end
		if i + 1 < #path then through[#through + 1] = path[i + 1] end
	end
	go(b)
	return len, through, pts
end

-- The zone under a world point on a continent (0 Eastern Kingdoms, 1 Kalimdor).
local CONT = { [0] = 1415, [1] = 1414 }
function R.ZoneAtWorld(wx, wy, inst)
	local c = CONT[inst]
	if not (HBD and c) then return nil end
	local ok, x, y = pcall(HBD.GetZoneCoordinatesFromWorld, HBD, wx, wy, c)
	if not (ok and x and y) then return nil end
	return R.ZoneAt(c, x, y)
end

-- The zones a walking path passes through, in order, leaving out where it starts and ends.
-- The path is sampled every 50 yards; a zone counts once the path spends 150 yards in it, so
-- clipping a corner of one doesn't put it in the instructions.
function R.ZonesAlong(pts, fromZone, toZone)
	local samples = {}
	local acc = 0
	for i, p in ipairs(pts or {}) do
		if i > 1 then
			local q = pts[i - 1]
			local dx, dy = p.wx - q.wx, p.wy - q.wy
			local seg = sqrt(dx * dx + dy * dy)
			local t = 50 - acc
			while t <= seg do
				local f = t / seg
				samples[#samples + 1] = { wx = q.wx + dx * f, wy = q.wy + dy * f, inst = p.inst }
				t = t + 50
			end
			acc = (acc + seg) % 50
		else
			samples[1] = p
		end
	end
	local out, seen, yards, order = {}, {}, {}, {}
	for _, p in ipairs(samples) do
		local z = R.ZoneAtWorld(p.wx, p.wy, p.inst)
		if z and z ~= fromZone and z ~= toZone then
			if not yards[z] then yards[z] = 0; order[#order + 1] = z end
			yards[z] = yards[z] + 50
		end
	end
	for _, z in ipairs(order) do
		if yards[z] >= 150 and not seen[z] then seen[z] = true; out[#out + 1] = z end
	end
	return out
end

------------------------------------------------------------------------
-- Flight points (from the game) and which ones you have
------------------------------------------------------------------------
local FACTION_CODE = { Neutral = 0, Horde = 1, Alliance = 2 }

function R.Faction()
	local ok, f = pcall(UnitFactionGroup, "player")
	return ok and Plain(f) or nil
end

local flightCache = {}
function R.FlightPoints(continent)
	if flightCache[continent] then return flightCache[continent] end
	local out = {}
	local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, continent)
	if not ok or type(nodes) ~= "table" then return out end
	local mine = FACTION_CODE[R.Faction() or ""]
	for _, n in ipairs(nodes) do
		local name = Plain(n.name)
		local pos = n.position
		local f = Plain(n.faction)
		local okF = (f == nil) or f == 0 or f == mine
		if name and pos and okF then
			local px, py
			if type(pos) == "table" and pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end
			local p = R.Point(continent, Plain(px), Plain(py), name, "flight")
			if p then
				p.town = name:match("^([^,]+)") or name
				out[#out + 1] = p
			end
		end
	end
	if #out > 0 then flightCache[continent] = out end
	return out
end

-- Flight paths you've been to, remembered per character when you open a flight master's map.
-- The flight map lists every flight path you have on that continent, so once any of them is
-- remembered, the rest of that continent's flight paths are ones you don't have.
-- true = you have it; false = you don't; nil = don't know yet (no flight map seen there).
function R.Scanned(continent)
	local k = FastestWayCharDB and FastestWayCharDB.known
	if not k or next(k) == nil then return false end
	if not continent then return true end
	for _, p in ipairs(R.FlightPoints(continent)) do if k[p.label] then return true end end
	return false
end

function R.Known(name, continent)
	local k = FastestWayCharDB and FastestWayCharDB.known
	if k and k[name] then return true end
	if continent and R.Scanned(continent) then return false end
	return nil
end

-- Reads the open flight map. Returns how many new flight paths it learned and the continent
-- they are on (nil if none of them is a known flight point).
function R.LearnFlightPaths(mapID)
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return 0 end
	local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
	if not ok or type(nodes) ~= "table" then return 0 end
	FastestWayCharDB.known = FastestWayCharDB.known or {}
	local n, names = 0, {}
	for _, node in ipairs(nodes) do
		local name, state = Plain(node.name), Plain(node.state)
		if name and state ~= nil and state ~= 2 then -- 0 = you're here, 1 = you can fly there, 2 = not learned
			if not FastestWayCharDB.known[name] then n = n + 1 end
			FastestWayCharDB.known[name] = true
			names[name] = true
		end
	end
	local cont
	for _, c in ipairs({ D.EK, D.KALIMDOR }) do
		for _, p in ipairs(R.FlightPoints(c)) do if names[p.label] then cont = cont or c end end
	end
	return n, cont
end

------------------------------------------------------------------------
-- Docks and the hearthstone
------------------------------------------------------------------------
-- A place given in world yards (UnitPosition's frame: north, west) on continent inst.
function R.PointWorld(inst, north, west, label, kind)
	local c = CONT[inst]
	if not (HBD and c) then return nil end
	local ok, x, y = pcall(HBD.GetZoneCoordinatesFromWorld, HBD, west, north, c)
	if not (ok and x and y) then return nil end
	return R.Point(c, x, y, label, kind)
end

local dockCache
local function Docks()
	if dockCache then return dockCache end
	dockCache = {}
	local mine = R.Faction()
	-- WoW: Forever's own boats and zeppelins (Engine/Data/Boats.lua): one entry per trip, one way.
	if D.BOATS then
		for _, t in ipairs(D.BOATS) do
			if t.faction == "both" or t.faction == mine then
				local a = R.PointWorld(t.a.inst, t.a.x, t.a.y, t.a.town, "dock")
				local b = R.PointWorld(t.b.inst, t.b.x, t.b.y, t.b.town, "dock")
				if a and b then
					a.town = t.a.town or R.MapName(a.zone)
					b.town = t.b.town or R.MapName(b.zone)
					a.label, b.label = a.town, b.town
					a.ride, b.ride = t, t
					a.other = b -- board at a, get off at b (the trip back is its own entry)
					dockCache[#dockCache + 1] = a
					dockCache[#dockCache + 1] = b
				end
			end
		end
	end
	for _, t in ipairs(D.TRANSPORTS) do
		-- the hand-made list: only the tram once the game's boat data is loaded
		if (t.faction == "both" or t.faction == mine) and not (D.BOATS and t.kind ~= "tram") then
			local a = R.Point(t.a.map, t.a.x, t.a.y, t.a.town, "dock")
			local b = R.Point(t.b.map, t.b.x, t.b.y, t.b.town, "dock")
			if a and b then
				a.town, b.town = t.a.town, t.b.town
				a.ride, b.ride = t, t
				a.other, b.other = b, a
				dockCache[#dockCache + 1] = a
				dockCache[#dockCache + 1] = b
			end
		end
	end
	return dockCache
end
R.Docks = Docks

function R.Hearth()
	local ok, where = pcall(GetBindLocation)
	where = ok and Plain(where)
	if not where then return nil end
	local inn = D.INNS[where]
	if not inn then return nil, where end
	local p = R.Point(inn.map, inn.x, inn.y, inn.town, "inn")
	if p then p.town = inn.town; p.innName = where end
	return p, where
end

-- Is the hearthstone ready? true / false, or nil when nobody can tell.
-- The game's own cooldown is used when it is readable (WoW: Forever hides most cooldowns);
-- otherwise the last time you used it (or said it wasn't ready) counts for an hour.
local HEARTHSTONE, HEARTH_SPELL, HEARTH_CD = 6948, 8690, 3600
R.HEARTH_SPELL = HEARTH_SPELL
function R.HearthReady()
	local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	if get then
		local ok, start, duration = pcall(get, HEARTHSTONE)
		start, duration = ok and Plain(start), ok and Plain(duration)
		if type(start) == "number" and type(duration) == "number" then
			if start == 0 or duration == 0 then return true end
			local now = GetTime and Plain(GetTime())
			if now then return start + duration - now <= 0 end
		end
	end
	local c = FastestWayCharDB
	local at = c and c.hearthAt
	if type(at) == "number" and time and time() - at < HEARTH_CD then return false end
	return nil
end
-- Minutes until it's ready again, as far as we know (nil = don't know).
function R.HearthWait()
	local c = FastestWayCharDB
	local at = c and c.hearthAt
	if type(at) ~= "number" or not time then return nil end
	local left = HEARTH_CD - (time() - at)
	if left <= 0 then return nil end
	return math.ceil(left / 60)
end

------------------------------------------------------------------------
-- Finding the route
------------------------------------------------------------------------
-- opts: speed (yards/s), hearth (true = may use it), knownOnly (true = only flight paths you have)
-- Returns { legs = { { kind, from, to, time, through, maybe } ... }, time = total } or nil.
function R.Find(start, dest, opts)
	if not (start and dest) then return nil end
	opts = opts or {}
	local speed = opts.speed or 7
	local nodes = { start, dest }
	local flights = {}
	for _, c in ipairs({ D.EK, D.KALIMDOR }) do
		for _, p in ipairs(R.FlightPoints(c)) do
			local known = R.Known(p.label, c)
			-- known false: you don't have it, so never use it; nil: don't know yet, so "maybe"
			if known ~= false and not (opts.knownOnly and known ~= true) then
				p.maybe = known == nil
				nodes[#nodes + 1] = p
				flights[p] = true
			end
		end
	end
	for _, d in ipairs(Docks()) do nodes[#nodes + 1] = d end
	local hearth = opts.hearth and R.Hearth() or nil
	if hearth then nodes[#nodes + 1] = hearth end
	if opts.nodesOut then for i, n in ipairs(nodes) do opts.nodesOut[i] = n end end
	-- Real walking yards from the terrain router where it has answered (opts.walk), else the estimate.
	local walk = opts.walk

	local function Edges(u)
		local out = {}
		for _, v in ipairs(nodes) do
			if v ~= u and v ~= start and not (v == hearth and u ~= start) then
				local real = walk and walk(u, v)
				if real == false then
					-- the terrain router proved there is no way on foot: no run edge
				elseif real then
					local _, through = R.RunLength(u, v)
					out[#out + 1] = { kind = "run", to = v, time = real / speed, through = through, len = real, exact = true }
				else
					local len, through, pts = R.RunLength(u, v)
					if len then
						out[#out + 1] = { kind = "run", to = v, time = len * D.RUN_DETOUR / speed, through = through, len = len, pts = pts, approx = true }
					end
				end
				if flights[u] and flights[v] and u.inst == v.inst then
					local t = Dist(u, v) * D.FLY_DETOUR / D.FLY_YPS + D.FLY_OVERHEAD
					if v.maybe then t = t + D.UNKNOWN_FLIGHT_PENALTY end
					out[#out + 1] = { kind = "fly", to = v, time = t, maybe = v.maybe or u.maybe }
				end
			end
		end
		if u.kind == "dock" and u.other then
			local t = u.ride
			out[#out + 1] = { kind = t.kind, to = u.other, time = t.ride + t.wait }
		end
		if u == start and hearth then
			out[#out + 1] = { kind = "hearth", to = hearth, time = D.HEARTH_TIME }
		end
		return out
	end

	local time, prev, done = { [start] = 0 }, {}, {}
	while true do
		local best, bt = nil, huge
		for n, t in pairs(time) do if not done[n] and t < bt then best, bt = n, t end end
		if not best or best == dest then break end
		done[best] = true
		for _, e in ipairs(Edges(best)) do
			local nt = bt + e.time
			if not time[e.to] or nt < time[e.to] then
				time[e.to] = nt
				prev[e.to] = { from = best, edge = e }
			end
		end
	end
	if not time[dest] then return nil end

	local legs, n = {}, dest
	while prev[n] do
		local p = prev[n]
		table.insert(legs, 1, { kind = p.edge.kind, from = p.from, to = n, time = p.edge.time,
			through = p.edge.through, maybe = p.edge.maybe, len = p.edge.len, pts = p.edge.pts,
			exact = p.edge.exact, approx = p.edge.approx })
		n = p.from
	end
	-- Several flights in a row are one trip on the flight master's map.
	local merged = {}
	for _, l in ipairs(legs) do
		local last = merged[#merged]
		if last and last.kind == "fly" and l.kind == "fly" then
			last.to, last.time, last.maybe = l.to, last.time + l.time - D.FLY_OVERHEAD, last.maybe or l.maybe
		else
			merged[#merged + 1] = l
		end
	end
	-- Running a few yards is not a step.
	local final = {}
	for i, l in ipairs(merged) do
		-- (measured straight, as a real walking cost can be a little longer than the gap it closes)
		local short = l.kind == "run" and #merged > 1 and Dist(l.from, l.to) < 25
		if not short then final[#final + 1] = l end
	end
	return { legs = final, time = time[dest], uses = function(kind) for _, l in ipairs(final) do if l.kind == kind then return true end end end }
end

------------------------------------------------------------------------
-- Words
------------------------------------------------------------------------
function R.Minutes(sec)
	if sec < 45 then return "under a minute" end
	local m = math.floor(sec / 60 + 0.5)
	if m < 60 then return "about " .. m .. " min" end
	return ("about %dh %02dm"):format(math.floor(m / 60), m % 60)
end

local function Join(list)
	if #list == 0 then return "" end
	if #list == 1 then return list[1] end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function PlaceName(p)
	if p.kind == "flight" then return "the " .. (p.town or p.label) .. " flight master" end
	if p.kind == "dock" then
		local k = p.ride.kind
		if k == "tram" then return "the Deeprun Tram in " .. p.town end
		if k == "zeppelin" then return "the zeppelin tower in " .. p.town end
		return "the docks in " .. p.town
	end
	return p.label
end
R.PlaceName = PlaceName

-- One line of text per step.
function R.Describe(route)
	local out = {}
	for _, l in ipairs(route.legs) do
		local text
		if l.kind == "run" then
			local through = {}
			for _, z in ipairs(l.through or {}) do through[#through + 1] = R.MapName(z) end
			if #through > 0 then
				text = ("Run through %s to %s"):format(Join(through), PlaceName(l.to))
			elseif l.from.zone and l.to.zone and l.from.zone ~= l.to.zone then
				text = ("Run %s into %s to %s"):format(R.Direction(l.from, l.to), R.MapName(l.to.zone), PlaceName(l.to))
			else
				text = ("Run %s to %s"):format(R.Direction(l.from, l.to), PlaceName(l.to))
			end
		elseif l.kind == "fly" then
			text = "Fly to " .. (l.to.town or l.to.label) .. (l.maybe and " (if you have this flight path)" or "")
		elseif l.kind == "hearth" then
			text = "Use your hearthstone to " .. (l.to.town or l.to.label) .. (R.HearthReady() and "" or " (if it's ready)")
		elseif l.kind == "tram" then
			text = "Take the Deeprun Tram to " .. l.to.town
		else
			text = ("Take the %s to %s"):format(l.kind, l.to.town)
		end
		if l.kind == "run" and l.approx and l.estimated then text = text .. " (approximate path)" end
		out[#out + 1] = { kind = l.kind, text = text, time = l.time, to = l.to, maybe = l.maybe, pts = l.pts,
			approx = l.approx, exact = l.exact }
	end
	return out
end

------------------------------------------------------------------------
-- Places you can pick by name
------------------------------------------------------------------------
local placeCache
function R.Places()
	if placeCache then return placeCache end
	local list, seen = {}, {}
	local function add(name, pt, kind)
		if not (name and pt) then return end
		local k = name:lower()
		if seen[k] then return end
		seen[k] = true
		pt.label = name
		list[#list + 1] = { name = name, point = pt, kind = kind }
	end
	for _, c in ipairs({ D.EK, D.KALIMDOR }) do
		for _, p in ipairs(R.FlightPoints(c)) do
			add(p.town, R.Point(p.map, p.x, p.y, p.town, "place"), "town")
		end
	end
	for _, d in ipairs(Docks()) do add(d.town, R.Point(d.map, d.x, d.y, d.town, "place"), "town") end
	-- A zone means its flight master nearest the middle (the middle itself can be a lake or a
	-- mountain top no one can walk to); with no flight master there, its middle.
	local fps = {}
	for _, c in ipairs({ D.EK, D.KALIMDOR }) do for _, p in ipairs(R.FlightPoints(c)) do fps[#fps + 1] = p end end
	for z in pairs(D.ZONES) do
		local mid = R.Point(z, 0.5, 0.5, R.MapName(z), "place")
		local best, bd
		for _, p in ipairs(fps) do
			if mid and p.zone == z and p.inst == mid.inst then
				local d = Dist(p, mid)
				if not bd or d < bd then best, bd = p, d end
			end
		end
		local pt = best and R.Point(best.map, best.x, best.y, R.MapName(z), "place") or mid
		add(R.MapName(z), pt, "zone")
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	if #list > 0 then placeCache = list end
	return list
end

-- Best matches for what was typed: names starting with it first, then names containing it.
function R.Search(text, max)
	text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return {} end
	local starts, contains = {}, {}
	for _, p in ipairs(R.Places()) do
		local n = p.name:lower()
		if n:sub(1, #text) == text then starts[#starts + 1] = p
		elseif n:find(text, 1, true) then contains[#contains + 1] = p end
	end
	local out = {}
	for _, l in ipairs({ starts, contains }) do
		for _, p in ipairs(l) do if #out < (max or 8) then out[#out + 1] = p end end
	end
	return out
end

-- Clears caches (e.g. after logging in, when the map data is ready).
function R.Reset()
	for k in pairs(flightCache) do flightCache[k] = nil end
	placeCache, dockCache = nil, nil
end
