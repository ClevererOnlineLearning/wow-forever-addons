-- RangeTint: colours the game's own action buttons by range and mana.
--   red    = target out of range
--   orange = in range, but close to the edge
--   purple = too close (e.g. a hunter's dead zone, inside a shot's minimum range)
--   blue   = not enough mana
-- The game only says "in range: yes/no" per spell, never the distance. RangeTint works out a
-- distance window from every yes/no answer it can get (your buttons' spells, plus the 10/11/28
-- yard interact checks), and uses that window for orange and purple.
-- Only icon colours change (SetVertexColor); nothing secure is touched. Written by good mens.
local _, ns = ...
local RT = {}
_G.RangeTint = RT

local min, max, huge = math.min, math.max, math.huge
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) if v == nil or Secret(v) then return nil end return v end

RT.DEFAULTS = {
	enabled = true,
	red = true, orange = true, purple = true, blue = true,
	margin = 10, -- orange when within this many yards of a spell's maximum range
	colors = {
		red = { 1, 0.3, 0.3 },
		orange = { 1, 0.62, 0.18 },
		purple = { 0.78, 0.42, 1 },
		blue = { 0.45, 0.55, 1 },
	},
	minimap = { hide = false, angle = 250 },
}
local db

local function Fill(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			Fill(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

------------------------------------------------------------------------
-- The buttons
------------------------------------------------------------------------
local PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "BonusActionButton" }
local buttons = {}
local tinted = setmetatable({}, { __mode = "k" }) -- button -> colour we put on it
local busy = false

local function Paint(b, c)
	busy = true
	b.icon:SetVertexColor(c[1], c[2], c[3])
	busy = false
end

-- What the game itself would show (used when we take our colour off).
local function Slot(b)
	local a = Plain(b.action)
	if type(a) ~= "number" and b.CalculateAction then
		local ok, v = pcall(b.CalculateAction, b)
		if ok then a = Plain(v) end
	end
	if type(a) ~= "number" and b.GetAttribute then
		local ok, v = pcall(b.GetAttribute, b, "action")
		if ok then a = Plain(v) end
	end
	return type(a) == "number" and a or nil
end

local function Restore(b)
	tinted[b] = nil
	local slot = Slot(b)
	local usable, noMana
	if slot then
		local ok, u, n = pcall(IsUsableAction, slot)
		if ok then usable, noMana = Plain(u), Plain(n) end
	end
	busy = true
	if usable then b.icon:SetVertexColor(1, 1, 1)
	elseif noMana then b.icon:SetVertexColor(0.5, 0.5, 1)
	else b.icon:SetVertexColor(0.4, 0.4, 0.4) end
	busy = false
end

-- The game re-colours icons now and then; put ours back on top.
local function OnGameColor(icon)
	if busy then return end
	local b = icon.rtButton
	local c = b and tinted[b]
	if c then Paint(b, c) end
end

function RT.FindButtons()
	for _, p in ipairs(PREFIXES) do
		for i = 1, 12 do
			local b = _G[p .. i]
			if b and b.icon and not b.rtHooked and not (b.IsForbidden and b:IsForbidden()) then
				b.rtHooked = true
				b.icon.rtButton = b
				hooksecurefunc(b.icon, "SetVertexColor", OnGameColor)
				buttons[#buttons + 1] = b
			end
		end
	end
end

------------------------------------------------------------------------
-- Ranges of the spells on your bars
------------------------------------------------------------------------
local ranges = {} -- slot -> { min, max (yards), id, melee } (only your own harmful spells)
local hostile = false -- is your target an enemy
local IsHarmful = (C_Spell and C_Spell.IsSpellHarmful) or IsHarmfulSpell
local function SpellRange(id)
	if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
	local ok, info = pcall(C_Spell.GetSpellInfo, id)
	if not ok or type(info) ~= "table" then return nil end
	return Plain(info.minRange), Plain(info.maxRange)
end

-- Spells that measure from your pet or to a friend would mislead the distance window, so only
-- your own harmful spells are used.
local function Usable(id)
	if IsPlayerSpell then
		local ok, known = pcall(IsPlayerSpell, id)
		if ok and Plain(known) == false then return false end
	end
	if IsHarmful then
		local ok, h = pcall(IsHarmful, id)
		if ok and Plain(h) == false then return false end
	end
	return true
end

function RT.ScanSlot(slot)
	ranges[slot] = nil
	local ok, kind, id, sub = pcall(GetActionInfo, slot)
	if not ok then return end
	kind, id, sub = Plain(kind), Plain(id), Plain(sub)
	-- A macro button gives its macro number unless the game already resolved it to a spell;
	-- ask the macro which spell it casts (e.g. "/cast Raptor Strike").
	if kind == "macro" and sub ~= "spell" and type(id) == "number" and GetMacroSpell then
		local okM, sid = pcall(GetMacroSpell, id)
		id = okM and Plain(sid) or nil
	end
	if (kind ~= "spell" and kind ~= "macro") or type(id) ~= "number" or id <= 0 then return end
	local lo, hi = SpellRange(id)
	if type(hi) ~= "number" then return end
	local okR, has = pcall(ActionHasRange, slot)
	local melee = hi <= 5 -- melee abilities report 0 (Raptor Strike, Mongoose Bite, ...)
	-- Melee abilities are kept even when the game says the button has no range: on Forever
	-- some of them never answer "out of range", so the distance estimate decides for them.
	if not (okR and Plain(has)) and not melee then return end
	if not Usable(id) then return end
	if hi <= 0 then hi = 5 end
	if hi > 200 then return end -- "anywhere" spells (e.g. Eyes of the Beast) say nothing useful
	ranges[slot] = { min = tonumber(lo) or 0, max = hi, id = id, melee = melee }
end

function RT.ScanAll()
	for k in pairs(ranges) do ranges[k] = nil end
	for _, b in ipairs(buttons) do
		local s = Slot(b)
		if s then RT.ScanSlot(s) end
	end
end
RT.ranges = ranges

local function InRange(slot)
	local ok, v = pcall(IsActionInRange, slot)
	if not ok then return nil end
	v = Plain(v)
	if v == 1 then v = true elseif v == 0 then v = false end
	return v
end

-- The same question asked by spell instead of by button (some buttons don't answer).
local function SpellInRange(id)
	if not (id and C_Spell and C_Spell.IsSpellInRange) then return nil end
	local ok, v = pcall(C_Spell.IsSpellInRange, id, "target")
	if not ok then return nil end
	v = Plain(v)
	if v == 1 then v = true elseif v == 0 then v = false end
	if v ~= true and v ~= false then return nil end
	return v
end
RT.SpellInRange = SpellInRange

-- In range? The button's answer, else the spell's, else (for melee abilities) the distance
-- estimate: a target known to be further than melee range is out of range.
function RT.InRangeFor(slot, lo)
	local r = ranges[slot]
	-- On Forever, Raptor Strike can answer "in range" from any distance, while Wing Clip answers
	-- correctly. Melee abilities share one range, so one "out of range" counts for all of them.
	if r and r.melee and hostile and (RT.meleeOut or (lo and lo > r.max)) then return false, "other melee abilities" end
	local v = InRange(slot)
	if v ~= nil then return v, "button" end
	if not r then return nil end
	v = SpellInRange(r.id)
	if v ~= nil then return v, "spell" end
	if r.melee and hostile and lo and lo > r.max then return false, "distance" end
	return nil
end

-- The distance window [lo, hi] the target must be in, from every yes/no answer we can get.
function RT.Estimate()
	local lo, hi = 0, huge
	local function Interact(i, yards)
		local ok, v = pcall(CheckInteractDistance, "target", i)
		v = ok and Plain(v)
		if v == true then hi = min(hi, yards) elseif v == false then lo = max(lo, yards) end
	end
	Interact(3, 10); Interact(2, 11); Interact(1, 28)
	local outs = {}
	local meleeOut = false
	for slot, r in pairs(ranges) do
		local v = InRange(slot)
		-- a melee "in range" isn't trusted (see RT.InRangeFor); a melee "out of range" is
		if v == true and not r.melee then lo = max(lo, r.min); hi = min(hi, r.max)
		elseif v == false then
			outs[#outs + 1] = r
			if r.melee then meleeOut = true end
		end
	end
	RT.meleeOut = meleeOut
	-- "out of range" means too close (under min) or too far (over max)
	for _ = 1, 2 do
		for _, r in ipairs(outs) do
			if r.min <= 0 or lo >= r.min then lo = max(lo, r.max)
			elseif hi < r.max then hi = min(hi, r.min) end
		end
	end
	if lo > hi then return 0, huge end -- answers disagree (e.g. moving): say nothing
	return lo, hi
end

------------------------------------------------------------------------
-- Colouring
------------------------------------------------------------------------
-- What colour (if any) a button should have right now. lo/hi = distance window.
function RT.ColorFor(slot, lo, hi)
	if not db.enabled or not slot then return nil end
	local okH, has = pcall(HasAction, slot)
	if not (okH and Plain(has)) then return nil end
	local inRange = RT.InRangeFor(slot, lo)
	local r = ranges[slot]
	if inRange == false then
		if db.purple and r and r.min > 0 and hi < r.max then return "purple" end
		if db.red then return "red" end
	end
	local ok, _, noMana = pcall(IsUsableAction, slot)
	if ok and Plain(noMana) and db.blue then return "blue" end
	if inRange == true and db.orange and r and hostile and r.max > 5 and lo > 0 and lo >= r.max - db.margin then
		return "orange"
	end
	return nil
end

local testColor -- set while the Test button runs

function RT.UpdateAll()
	if not db then return end
	local lo, hi = 0, huge
	if hostile then lo, hi = RT.Estimate() end
	RT.lo, RT.hi = lo, hi
	for _, b in ipairs(buttons) do
		local key
		if testColor then
			local slot = Slot(b)
			key = slot and HasAction(slot) and testColor or nil
		else
			key = RT.ColorFor(Slot(b), lo, hi)
		end
		local c = key and db.colors[key]
		if c then
			if tinted[b] ~= c then tinted[b] = c end
			Paint(b, c)
		elseif tinted[b] then
			Restore(b)
		end
	end
end

-- Checks a few times a second, only while you have a target (or the test is running).
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(self, dt)
	acc = acc + dt
	if acc < 0.12 then return end
	acc = 0
	RT.UpdateAll()
end)
ticker:Hide()

local function TargetChanged()
	local ok, ex = pcall(UnitExists, "target")
	local exists = ok and Plain(ex) == true
	local okA, att = pcall(UnitCanAttack, "player", "target")
	hostile = exists and okA and Plain(att) == true
	ticker:SetShown((exists and db.enabled) or testColor ~= nil)
	RT.UpdateAll()
end
RT.TargetChanged = TargetChanged

function RT.Test()
	local order = { "red", "orange", "purple", "blue" }
	local i = 0
	local function step()
		i = i + 1
		testColor = order[i]
		if testColor then
			TargetChanged()
			C_Timer.After(0.9, step)
		else
			TargetChanged()
		end
	end
	step()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, e, a1)
	if e == "ADDON_LOADED" then
		if a1 ~= "RangeTint" then return end
		RangeTintDB = RangeTintDB or {}
		Fill(RangeTintDB, RT.DEFAULTS)
		db = RangeTintDB
		RT.db = db
		return
	elseif e == "PLAYER_LOGIN" then
		RT.FindButtons()
		RT.ScanAll()
		for _, x in ipairs({ "PLAYER_TARGET_CHANGED", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
			"UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED", "UPDATE_MACROS", "ACTIONBAR_UPDATE_USABLE",
			"ACTION_RANGE_CHECK_UPDATE", "UNIT_POWER_FREQUENT" }) do
			pcall(self.RegisterEvent, self, x)
		end
		if RT.UpdateMinimapButton then RT.UpdateMinimapButton() end
		TargetChanged()
		return
	end
	if e == "ACTIONBAR_SLOT_CHANGED" and type(a1) == "number" and a1 > 0 then
		RT.ScanSlot(a1)
	elseif e == "ACTIONBAR_PAGE_CHANGED" or e == "UPDATE_BONUS_ACTIONBAR" or e == "SPELLS_CHANGED" or e == "UPDATE_MACROS" then
		RT.ScanAll()
	elseif e == "UNIT_POWER_FREQUENT" and a1 ~= "player" then
		return
	end
	if e == "PLAYER_TARGET_CHANGED" then TargetChanged() else RT.UpdateAll() end
end)

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------
local function Say(m) print("|cffff9933RangeTint|r: " .. m) end
local GetSpellNameC = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
SLASH_RANGETINT1 = "/rangetint"
SLASH_RANGETINT2 = "/rtint"
SlashCmdList.RANGETINT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "on" or msg == "off" then
		db.enabled = msg == "on"
		TargetChanged()
		Say(db.enabled and "on." or "off.")
	elseif msg == "test" then
		RT.Test()
	elseif msg == "range" then
		local lo, hi = RT.Estimate()
		Say(("target is between %s and %s yards."):format(lo, hi == huge and "?" or hi))
	elseif msg == "check" then
		-- What the game says about each button with a range, for your current target.
		if not hostile then Say("target an enemy first, then type /rtint check.") return end
		local lo, hi = RT.Estimate()
		Say(("target is between %s and %s yards. Buttons:"):format(lo, hi == huge and "?" or hi))
		local function Show(v)
			if v == true then return "|cff20ff20in range|r" elseif v == false then return "|cffff4040out of range|r" end
			return "|cff888888no answer|r"
		end
		local seen = {}
		for _, b in ipairs(buttons) do
			local slot = Slot(b)
			local r = slot and ranges[slot]
			if r and not seen[slot] then
				seen[slot] = true
				local okN, name = pcall(GetSpellNameC, r.id)
				local okB, rawB = pcall(IsActionInRange, slot)
				local btn
				if not okB then btn = "error"
				elseif Secret(rawB) then btn = "|cffff6633hidden|r"
				else
					if rawB == 1 then rawB = true elseif rawB == 0 then rawB = false end
					btn = Show(rawB)
				end
				local v, how = RT.InRangeFor(slot, lo)
				print(("  %s (%s-%s yd): button %s, spell %s -> %s%s"):format(okN and Plain(name) or "?", r.min, r.max, btn,
					Show(SpellInRange(r.id)), Show(v), how and how ~= "button" and (" (from the " .. how .. ")") or ""))
			end
		end
	elseif RT.ToggleOptions then
		RT.ToggleOptions()
	end
end
