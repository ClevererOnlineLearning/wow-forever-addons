-- Fastest Way To: the walking engine adapter. Everything else in the addon asks for walking
-- costs and paths through FW.Walk only, so the engine behind it (Engine/, the terrain router and
-- walking maps from Shortest Path Forever) can be updated or replaced by changing this file.
--
-- Our points are HereBeDragons world yards: wx grows west, wy grows north, inst is the continent
-- (0 Eastern Kingdoms, 1 Kalimdor). The engine's points are UnitPosition's frame: x north, y west.
--
-- Answers are cached per pair and route style:
--   number  real walking yards over the terrain (swimming counted at the engine's swim cost)
--   false   the engine proved there is no way on foot
--   nil     not worked out (yet), or the engine has no data there: use the approximate estimate
local _, ns = ...
local W = {}
ns.Walk = W
local Path = ns.Path

W.ENGINE = "Shortest Path Forever terrain router (Cillian Berragan, GPL-3.0-or-later)"
W.BALANCED_DETOUR = 1.2 -- Balanced: take the road route when it is at most 20% longer

-- Follow-roads profile: the engine's road preference with nothing else charged.
local ROADS = {
	key = "fastestway-roads",
	roads = true,
	Point = function() return 1 end,
	Charged = function() return false end,
	Near = function() return false end,
	Chord = function() return 1 end,
}

function W.Available(inst)
	return Path ~= nil and Path.HasData ~= nil and inst ~= nil and Path.HasData(inst) and true or false
end

local function toEngine(p) return { x = p.wy, y = p.wx } end

-- engine route points -> our points
local function fromEngine(points, inst)
	local out = {}
	for i, q in ipairs(points) do out[i] = { wx = q.y, wy = q.x, inst = inst } end
	out.wet = points.wet
	return out
end

------------------------------------------------------------------------
-- Cache
------------------------------------------------------------------------
local cache, size = {}, 0
local MAX = 4000
local function Key(a, b, mode)
	return ("%d:%d,%d>%d,%d:%s"):format(a.inst or -1, math.floor(a.wx / 2 + 0.5), math.floor(a.wy / 2 + 0.5),
		math.floor(b.wx / 2 + 0.5), math.floor(b.wy / 2 + 0.5), mode)
end
local function Put(a, b, mode, field, value, reason)
	local k = Key(a, b, mode)
	local e = cache[k]
	if not e then
		if size >= MAX then wipe(cache); size = 0 end
		e = {}; cache[k] = e; size = size + 1
	end
	e[field] = value
	if reason then e.reason = reason end
	return e
end
local function Entry(a, b, mode) return cache[Key(a, b, mode)] end
function W.Clear() wipe(cache); size = 0 end

-- Engine search mode for a style: costs for planning use "fast" except in Roads, which plans on roads.
local function PlanMode(style) return style == "roads" and "roads" or "fast" end

-- Planning cost: yards, false (no way on foot), or nil (unknown / no data).
function W.Cost(a, b, style)
	if not (a and b) or a.inst ~= b.inst then return nil end
	local e = Entry(a, b, PlanMode(style))
	if e and e.cost ~= nil then return e.cost end
	return nil
end

-- Why the engine couldn't answer, if it couldn't ("nodata", "outside", "offmesh", "unreachable", "error").
function W.Reason(a, b, style)
	local e = a and b and Entry(a, b, PlanMode(style))
	return e and e.reason or (not W.Available(a and a.inst) and "nodata" or nil)
end

-- The walking path for a leg in this style, with its real yards: pts, yards (or nil).
-- Balanced takes the road path when it is no more than BALANCED_DETOUR times the fastest.
function W.Points(a, b, style)
	if not (a and b) then return nil end
	local fast, road = Entry(a, b, "fast"), Entry(a, b, "roads")
	if style == "roads" then
		if road and road.pts then return road.pts, road.cost end
		return nil
	end
	if style == "balanced" and road and road.pts and fast and fast.cost and road.cost
		and road.cost <= fast.cost * W.BALANCED_DETOUR then
		return road.pts, road.cost
	end
	if style == "balanced" and not (road and road.cost ~= nil) then return nil end -- still waiting for the road one
	if fast and fast.pts then return fast.pts, fast.cost end
	return nil
end

------------------------------------------------------------------------
-- Jobs (the engine works a little each frame; answers arrive later)
------------------------------------------------------------------------
local live = {} -- jobs of the current request, cancelled when a new route starts
W.generation = 0

function W.Cancel()
	for _, job in ipairs(live) do pcall(Path.Cancel, job) end
	wipe(live)
	W.generation = W.generation + 1
end

local function Track(job) if job then live[#live + 1] = job end; return job end

-- Costs from `from` to each of `targets` (or from each target to `to` when reverse), in one search.
-- done() runs once all answers are in the cache.
local function Many(from, targets, mode, reverse, done)
	local list, todo = {}, {}
	for _, t in ipairs(targets) do
		if t.inst == from.inst then
			local a, b = from, t
			if reverse then a, b = t, from end
			local e = Entry(a, b, mode)
			if not (e and e.cost ~= nil) then list[#list + 1] = toEngine(t); todo[#todo + 1] = t end
		end
	end
	if #todo == 0 then done() return end
	local gen = W.generation
	Track(Path.FindMany(from.inst, toEngine(from), list, function(costs, reason)
		if gen ~= W.generation then return end
		for i, t in ipairs(todo) do
			local a, b = from, t
			if reverse then a, b = t, from end
			local c = costs and costs[i]
			if type(c) == "number" then Put(a, b, mode, "cost", c)
			elseif c == false and not reason then Put(a, b, mode, "cost", false, "unreachable")
			else Put(a, b, mode, "reason", reason or "unknown") end
		end
		done()
	end, false, reverse, nil, mode == "roads" and ROADS or nil))
end

-- Full paths (and exact costs) for these { a, b } pairs in these modes. done() when all are in.
local function Paths(pairs, modes, done)
	local waiting = 0
	local gen = W.generation
	local function one()
		waiting = waiting - 1
		if waiting == 0 and gen == W.generation then done() end
	end
	for _, pr in ipairs(pairs) do
		local a, b = pr[1], pr[2]
		for _, mode in ipairs(modes) do
			local e = Entry(a, b, mode)
			if a.inst == b.inst and W.Available(a.inst) and not (e and (e.pts or e.cost == false or e.failed)) then
				waiting = waiting + 1
				Track(Path.Find(a.inst, toEngine(a), toEngine(b), function(points, cost)
					if gen ~= W.generation then return end
					if points then
						local en = Put(a, b, mode, "pts", fromEngine(points, a.inst))
						en.cost = cost
					else
						local en = Put(a, b, mode, "failed", true, type(cost) == "string" and cost or "unknown")
						if cost == "unreachable" then en.cost = false end
					end
					one()
				end, false, mode == "roads" and ROADS or nil))
			end
		end
	end
	if waiting == 0 then done() end
end

-- Step 1 of refining a route: real costs from the start to every place, and from every place to
-- the destination, on the start's continent. done() afterwards.
-- (The destination side is worked out on the destination's own continent, so a trip by boat or
-- zeppelin to the other continent gets real walks at both ends.)
function W.Settle(start, dest, nodes, style, done)
	local mode = PlanMode(style)
	local pending = 2
	local function one() pending = pending - 1; if pending == 0 then done() end end
	if W.Available(start.inst) then
		local targets = {}
		for _, n in ipairs(nodes) do if n ~= start then targets[#targets + 1] = n end end
		Many(start, targets, mode, false, one)
	else
		one()
	end
	if W.Available(dest.inst) then
		local back = {}
		for _, n in ipairs(nodes) do if n ~= dest and n ~= start then back[#back + 1] = n end end
		Many(dest, back, mode, true, one)
	else
		one()
	end
end

-- Step 2: exact costs for the walking legs a route uses between two places (not from the start or
-- to the destination, which step 1 covers).
function W.Need(pairs, style, done)
	Paths(pairs, { PlanMode(style) }, done)
end

-- Step 3: the drawn paths for the legs a route uses.
function W.Geometry(pairs, style, done)
	local modes = style == "balanced" and { "fast", "roads" } or { PlanMode(style) }
	Paths(pairs, modes, done)
end

-- For /fw debug.
function W.Stats() return size, #live end
