-- Market Opportunities by good mens (Mephz on WoW Forever). MIT licence.
-- Core: namespace, saved variables, event bus, time-sliced jobs, money formatting.
local ADDON, ns = ...
ns.ADDON = ADDON
ns.VERSION = "0.1"
ns.ICON = "Interface\\Icons\\INV_Misc_Coin_02"

function ns.Print(msg)
	print("|cffffd100Market Opportunities:|r " .. tostring(msg))
end

------------------------------------------------------------------------
-- Money: integer copper in, "1g 2s 3c" out (zero parts dropped)
------------------------------------------------------------------------
function ns.Money(copper)
	copper = math.floor((copper or 0) + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return sign .. table.concat(parts, " ")
end

------------------------------------------------------------------------
-- Event bus. WoW events are registered on one frame (pcall: our own event names such as
-- SCAN_DONE are not WoW events and RegisterEvent would refuse them).
------------------------------------------------------------------------
local handlers = {}
local frame = CreateFrame("Frame")

function ns.Fire(event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then ns.Print("error in " .. event .. ": " .. tostring(err)) end
	end
end

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(frame.RegisterEvent, frame, event)
	end
	table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	MarketOpportunitiesDB = MarketOpportunitiesDB or {}
	MarketOpportunitiesCharDB = MarketOpportunitiesCharDB or {}
	if not MarketOpportunitiesDB.version then MarketOpportunitiesDB.version = 1 end
	if not MarketOpportunitiesCharDB.version then MarketOpportunitiesCharDB.version = 1 end
	ns.db, ns.cdb = MarketOpportunitiesDB, MarketOpportunitiesCharDB
	ns.Fire("MO_READY")
end)

------------------------------------------------------------------------
-- Time-sliced jobs: step(budgetMs) is called once per frame until it returns true.
-- Nothing runs while in combat. An error stops the job and is reported once.
------------------------------------------------------------------------
local jobs = {}

function ns.Run(name, step, budgetMs, onError)
	ns.Cancel(name)
	jobs[name] = C_Timer.NewTicker(0, function(ticker)
		if InCombatLockdown() then return end
		local ok, done = pcall(step, budgetMs or 4)
		if not ok then
			ns.Print("stopped " .. name .. ": " .. tostring(done))
			if onError then pcall(onError, done) end
			done = true
		end
		if done then
			ticker:Cancel()
			if jobs[name] == ticker then jobs[name] = nil end
		end
	end)
end

function ns.Cancel(name)
	if jobs[name] then
		jobs[name]:Cancel()
		jobs[name] = nil
	end
end

function ns.IsRunning(name) return jobs[name] ~= nil end
