-- Raid calendar (editable in settings later). status: "announced" (with source) or "assumed".
local _, ns = ...
ns.Data = ns.Data or {}

ns.Data.RaidCalendar = {
	{ name = "Barrow Deeps, Hyjal Summit, Onyxia's Lair", date = "2026-12-09", status = "announced",
	  source = "guide sites citing Blizzard's roadmap", checkedOn = "2026-11-15" },
	{ name = "Molten Core", date = nil, status = "assumed" },
}

-- Days since 1970-01-01 for a civil date (no os.time needed)
local function daysFromCivil(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
ns.Data.DaysFromCivil = daysFromCivil

-- The next dated raid opening on or after now (unix seconds): {name, date, days, status}
function ns.Data.NextRaid(now, calendar)
	local today = math.floor(now / 86400)
	local best
	for _, r in ipairs(calendar or ns.Data.RaidCalendar) do
		local y, m, d = tostring(r.date or ""):match("^(%d+)-(%d+)-(%d+)$")
		if y then
			local days = daysFromCivil(tonumber(y), tonumber(m), tonumber(d)) - today
			if days >= 0 and (not best or days < best.days) then
				best = { name = r.name, date = r.date, days = days, status = r.status }
			end
		end
	end
	return best
end
