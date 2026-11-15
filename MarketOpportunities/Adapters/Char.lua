-- Character facts: level, faction, gold, professions, reputation. Refreshed on events.
local _, ns = ...
local C = {}
ns.Char = C

local cur = { level = 1, gold = 0, professions = {}, professionsKnown = false }

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2)
end

function C.Refresh()
	local c = { professions = {} }
	c.level = call(UnitLevel, "player") or 1
	c.faction = call(UnitFactionGroup, "player")
	c.class = select(2, call(UnitClass, "player"))
	c.gold = call(GetMoney) or 0
	-- GetProfessions answers nil right at login on Forever (spec §4a); read again later
	local idx = { call(GetProfessions) }
	local any = false
	for i = 1, 5 do
		local p = idx[i]
		if p then
			local name, _, rank, max, _, _, skillLine = call(GetProfessionInfo, p)
			if name and skillLine then
				c.professions[skillLine] = { name = name, rank = rank or 0, max = max or 0 }
				any = true
			end
		end
	end
	c.professionsKnown = any
	if not any and cur.professionsKnown then -- a momentary nil: keep what we knew
		c.professions, c.professionsKnown = cur.professions, true
	end
	cur = c
	ns.Fire("CHAR_CHANGED", c)
	return c
end

function C.Get() return cur end

-- Reputation standing (1 = Hated .. 8 = Exalted) or nil when the client doesn't say
function C.Standing(factionID)
	if not (C_Reputation and C_Reputation.GetFactionDataByID) then return nil end
	local d = call(C_Reputation.GetFactionDataByID, factionID)
	return d and d.reaction or nil
end

ns.On("PLAYER_LOGIN", function()
	C.Refresh()
	if C_Timer and C_Timer.After then C_Timer.After(3, C.Refresh) end
end)
ns.On("PLAYER_MONEY", C.Refresh)
ns.On("SKILL_LINES_CHANGED", C.Refresh)
ns.On("PLAYER_LEVEL_UP", function() if C_Timer then C_Timer.After(0.5, C.Refresh) end end)
