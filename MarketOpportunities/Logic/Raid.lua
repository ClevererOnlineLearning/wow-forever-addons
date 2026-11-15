-- Raid: calendar, evidence levels and buy/sell windows (spec §10). Pure.
local _, ns = ...
local R = {}
ns.Raid = R

local DAY = 86400

-- The player's edited calendar (settings) or the bundled one
function R.Calendar()
	local own = ns.db and ns.db.raidCalendar
	if type(own) == "table" and #own > 0 then return own end
	return ns.Data.RaidCalendar
end

function R.Next(calendar, now)
	return ns.Data.NextRaid(now, calendar)
end

function R.Label(r)
	if not r then return "No raid date known" end
	return r.name .. " in " .. r.days .. " days" .. (r.status == "assumed" and " (date assumed)" or "")
end

-- confirmed: verified on Forever AND a meaningful price move; likely: one of them; else speculative
function R.Evidence(record, move, calendarEntry)
	local verified = record and record.verifiedForever and true or false
	local moving = move and move.meaningful and true or false
	if verified and moving then return "confirmed" end
	if verified or moving then return "likely" end
	return "speculative"
end

-- Buy from now until 7 days before the raid; sell 1-3 weeks after it opens
function R.Windows(raid, now)
	if not raid then return nil end
	local opens = now + raid.days * DAY
	return {
		buyUntil = opens - 7 * DAY, sellFrom = opens + 7 * DAY, sellTo = opens + 21 * DAY,
		buyOpen = raid.days > 7,
	}
end
