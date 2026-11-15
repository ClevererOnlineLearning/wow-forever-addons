-- Minimal WoW stand-ins for offline tests. Tests drive time with _tick() and _now.
_now = 1000000
_combat = false
_printed = {}
_tickers = {}
_frames = {}

function time() return _now end
function GetTime() return _now end
_clock = 0
function debugprofilestop() return _clock end
function InCombatLockdown() return _combat end
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end _printed[#_printed + 1] = table.concat(t, " ") end
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
UISpecialFrames = {}
SlashCmdList = {}

local frameMT = { __index = function(t, k)
	return function() end -- any widget method is a no-op
end }
function CreateFrame(kind, name)
	local f = setmetatable({ events = {}, scripts = {} }, frameMT)
	function f:RegisterEvent(e) self.events[e] = true end
	function f:UnregisterEvent(e) self.events[e] = nil end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	function f:GetScript(k) return self.scripts[k] end
	_frames[#_frames + 1] = f
	if name then _G[name] = f end
	return f
end

-- Sends a WoW event to every stub frame registered for it.
function _fire(event, ...)
	for _, f in ipairs(_frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

C_Timer = {}
function C_Timer.NewTicker(d, fn)
	local t = { fn = fn, cancelled = false }
	function t:Cancel() self.cancelled = true end
	function t:IsCancelled() return self.cancelled end
	_tickers[#_tickers + 1] = t
	return t
end
function C_Timer.After(d, fn) C_Timer.NewTicker(d, function(t) t:Cancel() fn() end) end

-- Runs every live ticker once (one "frame").
function _tick()
	for _, t in ipairs(_tickers) do
		if not t.cancelled then t.fn(t) end
	end
end
function _liveTickers()
	local n = 0
	for _, t in ipairs(_tickers) do if not t.cancelled then n = n + 1 end end
	return n
end
