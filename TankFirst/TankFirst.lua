-- TankFirst: in the Group Finder's Browse list, listings offering a Tank move to the top (solo
-- tanks first, then groups that have one) and get a blue glow with a shield, so after each
-- search you see them straight away. While your group has no healer, healers come next with a
-- green glow. Once your group has a tank (or a healer), those stop being moved or marked.
-- Everything else keeps Blizzard's own order.
-- Only reads search results; never applies, invites or searches for you. Every value is checked
-- with issecretvalue, and if the game hides something the listing simply isn't marked.
-- Written by good mens (Mephz on WoW Forever).
local _, ns = ...
local TF = {}
_G.TankFirst = TF

local IsSecret = issecretvalue or function() return false end
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end
local function Say(m) print("|cff4aa8ffTankFirst|r: " .. m) end

local db

------------------------------------------------------------------------
-- Does this listing offer a tank?  2 = a solo player offering Tank, 1 = a group with a tank,
-- 0 = no (or the game won't say)
------------------------------------------------------------------------
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2)
end

-- role: "tank" / "healer" (lfgRoles keys), member role "TANK" / "HEALER"
function TF.RoleLevel(id, role)
	local ROLE = role == "tank" and "TANK" or "HEALER"
	id = Plain(id)
	if type(id) ~= "number" or not C_LFGList then return 0 end
	local info = Call(C_LFGList.GetSearchResultInfo, id)
	local members = type(info) == "table" and Plain(info.numMembers) or nil
	-- the roles a solo player (or the leader) put on the listing
	local leader = Call(C_LFGList.GetSearchResultLeaderInfo, id)
	local roles = type(leader) == "table" and type(leader.lfgRoles) == "table" and leader.lfgRoles or nil
	local leaderTank = roles and Plain(roles[role]) == true
	if leaderTank and (members == nil or members <= 1) then return 2 end
	-- a solo player's own role
	if members == 1 then
		local r = Call(C_LFGList.GetSearchResultMemberInfo, id, 1)
		if Plain(r) == ROLE then return 2 end
	end
	-- a group: anyone in it set as tank
	local counts = Call(C_LFGList.GetSearchResultMemberCounts, id)
	local tanks = type(counts) == "table" and Plain(counts[ROLE]) or nil
	if type(tanks) == "number" and tanks > 0 then return 1 end
	if leaderTank then return 1 end
	return 0
end
function TF.TankLevel(id) return TF.RoleLevel(id, "tank") end

-- Does your own group (you included) already have someone in this role?
local function GroupHas(ROLE)
	local units = { "player" }
	local raid = Plain(Call(IsInRaid))
	local n = Plain(Call(GetNumGroupMembers)) or 0
	if raid then for i = 1, n do units[#units + 1] = "raid" .. i end
	else for i = 1, 4 do units[#units + 1] = "party" .. i end end
	for _, u in ipairs(units) do
		if Plain(Call(UnitExists, u)) and Plain(Call(UnitGroupRolesAssigned, u)) == ROLE then return true end
	end
	return false
end

-- Does your group still need a tank / a healer? (on your own, yes)
function TF.NeedTank() return not GroupHas("TANK") end
function TF.NeedHealer()
	if not (db and db.healers) then return false end
	return not GroupHas("HEALER")
end
function TF.Needs() return { tank = TF.NeedTank(), healer = TF.NeedHealer() } end

-- What a listing is worth to you: tank 2/1, then healer 2/1, each only while your group needs one
function TF.Mark(id, need)
	need = need or TF.Needs()
	if need.tank then
		local t = TF.TankLevel(id)
		if t > 0 then return "tank", t end
	end
	if need.healer then
		local h = TF.RoleLevel(id, "healer")
		if h > 0 then return "healer", h end
	end
	return nil, 0
end
local function Priority(id, need)
	local kind, lvl = TF.Mark(id, need)
	if kind == "tank" then return 10 + lvl end
	return lvl
end

------------------------------------------------------------------------
-- Sorting: tanks first, everything else in Blizzard's own order (a stable sort)
------------------------------------------------------------------------
local function IdOf(x)
	if type(x) == "number" then return x end
	if type(x) == "table" then return x.resultID or x.id end
end

function TF.SortTanksFirst(results)
	if type(results) ~= "table" or #results < 2 then return false end
	local keyed, need = {}, TF.Needs()
	for i, x in ipairs(results) do keyed[i] = { x = x, i = i, lvl = Priority(IdOf(x), need) } end
	local moved = false
	table.sort(keyed, function(a, b)
		if a.lvl ~= b.lvl then return a.lvl > b.lvl end
		return a.i < b.i
	end)
	for i, k in ipairs(keyed) do
		if results[i] ~= k.x then moved = true end
		results[i] = k.x
	end
	return moved
end

------------------------------------------------------------------------
-- Highlight: a blue glow and a shield on rows offering a tank
------------------------------------------------------------------------
local SHIELD = "Interface\\Icons\\Ability_Defend"

local COLOURS = { tank = { 0.2, 0.55, 1 }, healer = { 0.25, 0.9, 0.35 } }
local ICONS = { tank = SHIELD, healer = "Interface\\Icons\\Spell_Holy_Renew" }

local function Decorate(row, lvl, kind)
	if not row.tfGlow then
		local g = row:CreateTexture(nil, "BACKGROUND", nil, 7)
		g:SetAllPoints()
		row.tfGlow = g
		local edge = row:CreateTexture(nil, "OVERLAY")
		edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(3)
		row.tfEdge = edge
		local s = row:CreateTexture(nil, "OVERLAY")
		s:SetSize(14, 14)
		s:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		s:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.tfShield = s
	end
	local on = lvl > 0 and db.highlight
	row.tfGlow:SetShown(on)
	row.tfEdge:SetShown(on)
	row.tfShield:SetShown(on)
	if on then
		local c = COLOURS[kind] or COLOURS.tank
		row.tfGlow:SetColorTexture(c[1], c[2], c[3], 0.22)
		row.tfEdge:SetColorTexture(c[1], c[2], c[3], 1)
		row.tfShield:SetTexture(ICONS[kind] or SHIELD)
		row.tfGlow:SetAlpha(lvl == 2 and 1 or 0.55)
	end
end

local function RowId(row)
	local id = Plain(row.resultID)
	if id then return id end
	if row.GetElementData then
		local data = Call(row.GetElementData, row)
		id = IdOf(data)
		if id then return Plain(id) end
	end
	if row.GetData then return Plain(IdOf(Call(row.GetData, row))) end
end

local function VisibleRows(browse)
	local rows = {}
	local box = browse.ScrollBox or (browse.SearchResults and browse.SearchResults.ScrollBox)
	if box and box.GetFrames then
		local frames = Call(box.GetFrames, box)
		if type(frames) == "table" then for _, f in ipairs(frames) do rows[#rows + 1] = f end end
	elseif box and box.ForEachFrame then
		pcall(box.ForEachFrame, box, function(f) rows[#rows + 1] = f end)
	end
	local sf = browse.ScrollFrame or (browse.SearchResults and browse.SearchResults.ScrollFrame)
	if #rows == 0 and sf and type(sf.buttons) == "table" then
		for _, f in ipairs(sf.buttons) do rows[#rows + 1] = f end
	end
	return rows
end

function TF.DecorateAll()
	local browse = _G.LFGBrowseFrame
	if not (browse and db) then return 0 end
	local n, need = 0, TF.Needs()
	for _, row in ipairs(VisibleRows(browse)) do
		local id = row:IsShown() and RowId(row) or nil
		if id then
			local kind, lvl = TF.Mark(id, need)
			Decorate(row, lvl, kind)
			if lvl > 0 then n = n + 1 end
		elseif row.tfGlow then
			Decorate(row, 0)
		end
	end
	return n
end

------------------------------------------------------------------------
-- Hooks into Blizzard's Browse list (read-only hooks: hooksecurefunc runs after Blizzard's code)
------------------------------------------------------------------------
local hooked = {}
local resorting = false

local function AfterUpdate(browse)
	if resorting or not db or not db.enabled then return end
	if db.sort and not hooked.sortFn and type(browse.results) == "table" then
		-- Blizzard has no sort function we can follow: sort its list and redraw it once
		if TF.SortTanksFirst(browse.results) and browse.UpdateResults then
			resorting = true
			pcall(browse.UpdateResults, browse)
			resorting = false
		end
	end
	TF.DecorateAll()
end

function TF.Hook()
	local browse = _G.LFGBrowseFrame
	if not browse then return false end
	if not hooked.sortFn and type(_G.LFGBrowseUtil_SortSearchResults) == "function" then
		hooksecurefunc("LFGBrowseUtil_SortSearchResults", function(results)
			if db and db.enabled and db.sort then TF.SortTanksFirst(results) end
		end)
		hooked.sortFn = true
	end
	for _, m in ipairs({ "UpdateResultList", "UpdateResults" }) do
		if not hooked[m] and type(browse[m]) == "function" then
			hooksecurefunc(browse, m, AfterUpdate)
			hooked[m] = true
		end
	end
	if not hooked.show then
		browse:HookScript("OnShow", function() TF.DecorateAll() end)
		hooked.show = true
	end
	if not hooked.ticker then
		-- rows are reused while you scroll: re-mark the visible ones a few times a second
		local acc = 0
		local f = CreateFrame("Frame", nil, browse)
		f:SetScript("OnUpdate", function(_, dt)
			acc = acc + dt
			if acc < 0.25 then return end
			acc = 0
			if db and db.enabled then TF.DecorateAll() end
		end)
		hooked.ticker = true
	end
	return true
end

------------------------------------------------------------------------
-- Events and /tanks
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e, name)
	if e == "ADDON_LOADED" and name == "TankFirst" then
		TankFirstDB = type(TankFirstDB) == "table" and TankFirstDB or {}
		db = TankFirstDB
		if db.enabled == nil then db.enabled = true end
		if db.sort == nil then db.sort = true end
		if db.highlight == nil then db.highlight = true end
		if db.healers == nil then db.healers = true end
		TF.db = db
	end
	if db then TF.Hook() end -- the Group Finder may load later, as its own Blizzard add-on
end)

local function OnOff(v) return v and "|cff20ff20on|r" or "|cffff4040off|r" end

SLASH_TANKFIRST1 = "/tanks"
SLASH_TANKFIRST2 = "/tankfirst"
SlashCmdList.TANKFIRST = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "on" or msg == "off" then
		db.enabled = msg == "on"
		TF.DecorateAll()
		Say(db.enabled and "on." or "off.")
	elseif msg == "sort" or msg == "sort on" or msg == "sort off" then
		if msg == "sort" then db.sort = not db.sort else db.sort = msg == "sort on" end
		Say("tanks to the top: " .. OnOff(db.sort) .. ". Takes effect on your next search.")
	elseif msg == "healers" or msg == "healer" then
		db.healers = not db.healers
		TF.DecorateAll()
		Say("healers (green, after tanks, while your group has no healer): " .. OnOff(db.healers))
	elseif msg == "glow" or msg == "highlight" then
		db.highlight = not db.highlight
		TF.DecorateAll()
		Say("blue glow on tanks: " .. OnOff(db.highlight))
	elseif msg == "check" then
		-- what TankFirst can see, for good mens if something doesn't work
		local browse = _G.LFGBrowseFrame
		TF.Hook()
		local r = { "Group Finder list " .. (browse and "found" or "|cffff4040not loaded yet (open it first)|r") }
		r[#r + 1] = "sort hook: " .. (hooked.sortFn and "Blizzard's sort" or (hooked.UpdateResultList and "after update" or "none"))
		local results = browse and browse.results
		local n, solo, group, heal = 0, 0, 0, 0
		if type(results) == "table" then
			for _, x in ipairs(results) do
				n = n + 1
				local l = TF.TankLevel(IdOf(x))
				if l == 2 then solo = solo + 1 elseif l == 1 then group = group + 1 end
				if TF.RoleLevel(IdOf(x), "healer") == 2 then heal = heal + 1 end
			end
		end
		r[#r + 1] = ("results: %d, solo tanks: %d, groups with a tank: %d, solo healers: %d"):format(n, solo, group, heal)
		r[#r + 1] = "your group needs a tank: " .. (TF.NeedTank() and "yes" or "no") .. ", a healer: " .. (TF.NeedHealer() and "yes" or "no")
		r[#r + 1] = ("rows on screen: %d, marked: %d"):format(browse and #VisibleRows(browse) or 0, TF.DecorateAll())
		local first = type(results) == "table" and IdOf(results[1])
		if first then
			local leader = Call(C_LFGList.GetSearchResultLeaderInfo, first)
			r[#r + 1] = "first result roles: " .. (type(leader) == "table" and type(leader.lfgRoles) == "table" and "readable" or "not available")
		end
		for _, l in ipairs(r) do Say(l) end
		db.lastCheck = r
	else
		Say(("is %s. Tanks to the top: %s, glow: %s, healers: %s. Each only while your group still needs one."):format(OnOff(db.enabled), OnOff(db.sort), OnOff(db.highlight), OnOff(db.healers)))
		Say("|cffffffff/tanks sort|r  top on/off   |cffffffff/tanks glow|r  glow on/off   |cffffffff/tanks healers|r  healers on/off   |cffffffff/tanks off|r / |cffffffffon|r   |cffffffff/tanks check|r  what it can see")
	end
end
