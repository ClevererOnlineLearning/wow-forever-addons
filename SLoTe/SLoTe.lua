-- Scrolling Loot Text (SLoTe)
-- Patched for WoW Forever (Interface 16001):
--  * modern C_Item / C_CurrencyInfo / C_AddOns APIs with fallbacks to the old globals
--  * initialises on its OWN ADDON_LOADED (saved variables are ready then)
--  * never touches CombatText before Blizzard_CombatText has loaded
--  * item text no longer crashes on uncached items (name/icon/colour read from the link)
--  * money icon uses the real copper amount; honor message no longer crashes
--  * UI_ERROR_MESSAGE uses the modern (errorType, message) arguments
--  * shows the combat-text frame even when Blizzard floating combat text is off

SLoTe = {};
local SLoTe = SLoTe;
local ADDON_NAME = ...

SLoTe.frame = CreateFrame("Frame");
local frame = SLoTe.frame;
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("CHAT_MSG_MONEY")
frame:RegisterEvent("CHAT_MSG_CURRENCY")
frame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
frame:RegisterEvent("LOOT_OPENED")
local Deformat = LibStub("LibDeformat-3.0")

-- Saved variables (defaults; overwritten by saved values when the addon loads)
Activation = 0
ShowL = 1
ShowC = 1
ShowH = 1
ShowM = 1
Scale = "1.0"
DisplayIcons = 1

local loaded = 0

BINDING_HEADER_ScrollingLootText = "Scrolling Loot Text";
BINDING_NAME_SLoTe = "On/Off Function";

------------------------------------------------------------------------
-- API compatibility
------------------------------------------------------------------------
local GetItemInfoCompat    = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstantC  = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetQualityColorCompat = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
local LoadAddOnCompat      = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn

local function GetCurrencyNameIcon(link)
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
		local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
		if info then return info.name, info.iconFileID end
	end
	if GetCurrencyInfo then
		local name, _, icon = GetCurrencyInfo(link)
		return name, icon
	end
	return link and link:match("%[(.-)%]"), nil
end

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

------------------------------------------------------------------------
-- Own scrolling-text engine (classic SCT look: pops up near screen centre,
-- drifts upward and fades). Independent of Blizzard's combat-text setting.
------------------------------------------------------------------------
-- Extra options (saved per character). Defaults fill in anything missing.
SLoTeOptions = {}
local OPTION_DEFAULTS = {
	duration   = 3.0,    -- seconds a message lives
	yOffset    = 80,     -- start height above screen centre
	arcDir     = "alt",  -- "alt" (alternate), "right" or "left"
	minQuality = 0,      -- 0 Poor, 1 Common, 2 Uncommon, 3 Rare, 4 Epic
	showCount  = false,  -- append "(N)" = how many you now have in your bags
	bigRare    = true,   -- Rare and better loot pops up 50% bigger
	minimap    = { angle = 215, hide = false },
}
local function Opt(k)
	local v = SLoTeOptions[k]
	if v == nil then v = OPTION_DEFAULTS[k] end
	return v
end
SLoTe.Opt, SLoTe.OPTION_DEFAULTS = Opt, OPTION_DEFAULTS

local RISE       = 160   -- pixels it drifts upward over its lifetime
local FADE_AT    = 0.6   -- start fading after this fraction of its life
local GAP        = 14    -- minimum vertical spacing between messages
local FONT_SIZE  = 12    -- text size (was ~24; halved)
local ICON_SIZE  = 12    -- item icon size (was 22)
local MAX_ACTIVE = 12
-- Arc mode (Blizzard "Arc" combat-text style): pop up, curve out to one side, drop away.
local ARC_WIDTH  = 110   -- how far sideways it travels
local ARC_HEIGHT = 70    -- how high the arc peaks
local ARC_DROP   = 40    -- how far below the start point it ends
local nextDir    = 1     -- alternate right/left so messages don't collide

FloatMode = "arc"        -- saved per character: "arc" or "straight"
FadeMode  = "end"        -- saved per character: "end" (fade in last 40%) or "smooth" (fade the whole way)

local SMOOTH_HOLD = 0.1  -- smooth fade: stay solid for the first 10% so the pop-up is readable

local function AlphaAt(p)
	if FadeMode == "smooth" then
		if p < SMOOTH_HOLD then return 1 end
		return 1 - (p - SMOOTH_HOLD) / (1 - SMOOTH_HOLD)
	end
	return p < FADE_AT and 1 or (1 - (p - FADE_AT) / (1 - FADE_AT))
end

-- Position of a message at progress p (0..1) of its life.
local function Offsets(m, p)
	if FloatMode == "straight" then
		return 0, m.base + RISE * p
	end
	return m.dir * ARC_WIDTH * p, m.base + ARC_HEIGHT * 4 * p * (1 - p) - ARC_DROP * p * p
end

local floatFrame = CreateFrame("Frame", "SLoTeFloatFrame", UIParent)
floatFrame:SetSize(1, 1)
floatFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
floatFrame:SetFrameStrata("TOOLTIP")
floatFrame:Hide()

local active, pool = {}, {}

local function Recycle(m)
	m.fs:Hide()
	pool[#pool + 1] = m
end

floatFrame:SetScript("OnUpdate", function(self, elapsed)
	for i = #active, 1, -1 do
		local m = active[i]
		m.t = m.t + elapsed
		local p = m.t / m.life
		if p >= 1 then
			table.remove(active, i)
			Recycle(m)
		else
			local x, y = Offsets(m, p)
			m.fs:SetPoint("CENTER", self, "CENTER", x, y)
			m.fs:SetAlpha(AlphaAt(p))
		end
	end
	if #active == 0 then self:Hide() end
end)

local function FloatAdd(text, r, g, b, big)
	local dir = 0
	if FloatMode ~= "straight" then
		local mode = Opt("arcDir")
		if mode == "right" then dir = 1
		elseif mode == "left" then dir = -1
		else
			dir = nextDir
			nextDir = -nextDir
		end
	end
	-- Push older messages (on the same side) up if the newest hasn't moved clear yet.
	local newest
	for i = #active, 1, -1 do
		if active[i].dir == dir then newest = active[i] break end
	end
	if newest then
		local _, y = Offsets(newest, newest.t / newest.life)
		if y - newest.base < GAP and newest.t < 0.5 then
			local shift = GAP - (y - newest.base)
			for _, m in ipairs(active) do
				if m.dir == dir then m.base = m.base + shift end
			end
		end
	end
	if #active >= MAX_ACTIVE then Recycle(table.remove(active, 1)) end

	local m = table.remove(pool)
	if not m then
		local fs = floatFrame:CreateFontString(nil, "OVERLAY")
		m = { fs = fs }
	end
	local fs = m.fs
	-- Combat-text typeface at half its usual size (FONT_SIZE).
	local fontPath = CombatTextFont and CombatTextFont:GetFont()
	local size = big and math.floor(FONT_SIZE * 1.5 + 0.5) or FONT_SIZE
	if not fs:SetFont(fontPath or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE") then
		fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
	end
	fs:SetText(text)
	fs:SetTextColor(r, g, b)
	fs:SetAlpha(1)
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", floatFrame, "CENTER", 0, 0)
	fs:Show()
	m.t, m.base, m.dir = 0, 0, dir
	m.life = math.max(1, tonumber(Opt("duration")) or 3)
	active[#active + 1] = m
	floatFrame:Show()
end

local function ApplyCombatTextSettings()
	floatFrame:SetScale(tonumber(Scale) or 1)
	floatFrame:ClearAllPoints()
	floatFrame:SetPoint("CENTER", UIParent, "CENTER", 0, tonumber(Opt("yOffset")) or 80)
end
SLoTe.Apply = ApplyCombatTextSettings

-- Central output: icon (texture path or fileID) + text in colour r,g,b (0-1)
local function Show(icon, text, r, g, b, big)
	r, g, b = r or 1, g or 1, b or 1
	if DisplayIcons ~= 0 and icon then
		local s = big and math.floor(ICON_SIZE * 1.5 + 0.5) or ICON_SIZE
		text = "|T" .. icon .. ":" .. s .. ":" .. s .. "|t  " .. text
	end
	FloatAdd(text, r, g, b, big)
end
SLoTe.Show = Show

------------------------------------------------------------------------
-- Parsing helpers
------------------------------------------------------------------------
-- Item name, icon and colour straight from the link, so uncached items still work.
local function DescribeItem(itemLink)
	local name, _, quality, _, _, _, _, _, _, icon = GetItemInfoCompat(itemLink)
	name = name or itemLink:match("%[(.-)%]") or itemLink
	if not icon and GetItemInfoInstantC then
		icon = select(5, GetItemInfoInstantC(itemLink))
	end
	local r, g, b
	if quality and GetQualityColorCompat then
		r, g, b = GetQualityColorCompat(quality)
	end
	if not r then
		local q = itemLink:match("|cnIQ(%d+):")
		if q and GetQualityColorCompat then
			r, g, b = GetQualityColorCompat(tonumber(q))
		end
	end
	if not r then
		local hex = itemLink:match("|c%x%x(%x%x%x%x%x%x)")
		if hex then
			r = tonumber(hex:sub(1, 2), 16) / 255
			g = tonumber(hex:sub(3, 4), 16) / 255
			b = tonumber(hex:sub(5, 6), 16) / 255
		end
	end
	if not quality then quality = tonumber(itemLink:match("|cnIQ(%d+):") or "") end
	return name, icon or QUESTION_ICON, r or 1, g or 1, b or 1, quality
end

local GetItemCountCompat = (C_Item and C_Item.GetItemCount) or GetItemCount

local function getLoot(chatmsg)
	local itemLink, amount = Deformat(chatmsg, LOOT_ITEM_SELF_MULTIPLE)
	if not itemLink and LOOT_ITEM_PUSHED_SELF_MULTIPLE then
		itemLink, amount = Deformat(chatmsg, LOOT_ITEM_PUSHED_SELF_MULTIPLE)
	end
	if not itemLink then
		itemLink = Deformat(chatmsg, LOOT_ITEM_SELF)
	end
	if not itemLink and LOOT_ITEM_PUSHED_SELF then
		itemLink = Deformat(chatmsg, LOOT_ITEM_PUSHED_SELF)
	end
	if not itemLink and LOOT_ITEM_CREATED_SELF then
		itemLink = Deformat(chatmsg, LOOT_ITEM_CREATED_SELF)
	end
	if itemLink then
		return itemLink, tonumber(amount) or 1
	end
end
_G.getLoot = getLoot -- kept global for backwards compatibility

-- Turn "1 Gold, 5 Silver, 3 Copper" into copper using the client's own strings.
local function AmountFrom(str, fmt)
	if not fmt then return 0 end
	local pattern = fmt:gsub("%%d", "(%%d+)")
	return tonumber(str:match(pattern)) or 0
end

local function MoneyToCopper(moneystring)
	return AmountFrom(moneystring, GOLD_AMOUNT) * 10000
		+ AmountFrom(moneystring, SILVER_AMOUNT) * 100
		+ AmountFrom(moneystring, COPPER_AMOUNT)
end

local function CoinIcon(copper)
	if GetCoinIcon then return GetCoinIcon(copper) end
	if copper >= 10000 then return "Interface\\MoneyFrame\\UI-GoldIcon" end
	if copper >= 100 then return "Interface\\MoneyFrame\\UI-SilverIcon" end
	return "Interface\\MoneyFrame\\UI-CopperIcon"
end

------------------------------------------------------------------------
-- Event handling
------------------------------------------------------------------------
function frame.OnEvent(self, event, arg1, arg2, ...)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME and loaded == 0 then
			ApplyCombatTextSettings()
			loaded = 1
			if Activation == 1 then
				print("|cFF1A16CESLoTe initialized, it is |cFF25C510Activated|cFF1A16CE. Enter |cFFFFFFFF/slote help|cFF1A16CE for commands.|r")
			else
				print("|cFF1A16CESLoTe initialized, it is |cFFD80000Deactivated|cFF1A16CE. Enter |cFFFFFFFF/slote help|cFF1A16CE for commands.|r")
			end
		end
		return
	end

	if loaded ~= 1 then return end

	if event == "UI_ERROR_MESSAGE" then
		-- Modern clients: arg1 = errorType (number), arg2 = message. Old clients: arg1 = message.
		local msg = type(arg1) == "string" and arg1 or arg2
		if msg == ERR_INV_FULL then
			Show(nil, "INVENTORY IS FULL", 1, 0, 0)
		end

	elseif event == "LOOT_OPENED" then
		if ShowL == 0 and LootFrame then
			LootFrame:SetClampedToScreen(false)
			LootFrame:ClearAllPoints()
			LootFrame:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -300, 300)
		end

	elseif event == "CHAT_MSG_LOOT" then
		local itemLink, amount = getLoot(arg1)
		if itemLink then
			local name, icon, r, g, b, quality = DescribeItem(itemLink)
			-- Quality filter (unknown quality always shows).
			if quality and quality < (tonumber(Opt("minQuality")) or 0) then return end
			local text = (amount >= 2) and (amount .. " x " .. name) or name
			if Opt("showCount") and GetItemCountCompat then
				local ok, have = pcall(GetItemCountCompat, itemLink)
				if ok and type(have) == "number" and have > 0 then
					text = text .. " |cffaaaaaa(" .. have .. ")|r"
				end
			end
			Show(icon, text, r, g, b, Opt("bigRare") and quality and quality >= 3)
		end

	elseif event == "CHAT_MSG_MONEY" and ShowM == 1 then
		local moneystring = Deformat(arg1, LOOT_MONEY_SPLIT) or Deformat(arg1, YOU_LOOT_MONEY)
		if moneystring then
			Show(CoinIcon(MoneyToCopper(moneystring)), moneystring, 1, 1, 1)
		end

	elseif event == "CHAT_MSG_CURRENCY" and ShowC == 1 then
		local itemLink, amount
		if CURRENCY_GAINED_MULTIPLE_BONUS then
			itemLink, amount = Deformat(arg1, CURRENCY_GAINED_MULTIPLE_BONUS)
		end
		if not itemLink and CURRENCY_GAINED_MULTIPLE then
			itemLink, amount = Deformat(arg1, CURRENCY_GAINED_MULTIPLE)
		end
		if not itemLink and CURRENCY_GAINED then
			itemLink = Deformat(arg1, CURRENCY_GAINED)
		end
		if itemLink then
			amount = tonumber(amount) or 1
			local name, icon = GetCurrencyNameIcon(itemLink)
			name = name or itemLink
			if amount >= 2 then
				Show(icon or QUESTION_ICON, amount .. " x " .. name, 1, 1, 1)
			else
				Show(icon or QUESTION_ICON, name, 1, 1, 1)
			end
		end

	elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" and ShowH == 1 then
		local honor
		if COMBATLOG_HONORAWARD then honor = tonumber((Deformat(arg1, COMBATLOG_HONORAWARD))) end
		if not honor and COMBATLOG_HONORGAIN then
			local a, b, c = Deformat(arg1, COMBATLOG_HONORGAIN)
			honor = tonumber(c) or tonumber(b)
		end
		if not honor and COMBATLOG_HONORGAIN_NO_RANK then
			local a, b = Deformat(arg1, COMBATLOG_HONORGAIN_NO_RANK)
			honor = tonumber(b) or tonumber(a)
		end
		if honor then
			local faction = UnitFactionGroup("player")
			local icon = (faction == "Horde") and "Interface\\TargetingFrame\\UI-PVP-Horde" or "Interface\\TargetingFrame\\UI-PVP-Alliance"
			Show(icon, honor .. " " .. (HONOR or "Honor"), 1, 0.82, 0)
		end
	end
end

------------------------------------------------------------------------
-- Slash commands (unchanged behaviour)
------------------------------------------------------------------------
local function msgOut(s) print(s) end

function scale(newScale)
	local n = tonumber(newScale)
	if not n then msgOut("|cFFD80000Usage: /slote scale 1.0|r") return end
	local oldScale = Scale
	Scale = tostring(n)
	ApplyCombatTextSettings()
	Show(CoinIcon(9999999999), "New scale: " .. Scale, 1, 1, 1)
	msgOut("|cFF25C510Scale set from " .. tostring(oldScale) .. " to: |r" .. Scale)
end

function testMessage()
	ApplyCombatTextSettings()
	Show(CoinIcon(9999999999), "TEST test 0123456789", 1, 1, 1)
end

function activate()   Activation = 1; msgOut("|cFF25C510SLoTe activated.|r") end
function deactivate() Activation = 0; msgOut("|cFFD80000SLoTe deactivated.|r") end
function showL() ShowL = 0; msgOut("|cFF25C510SLoTeLoot activated.|r") end
function hideL() ShowL = 1; msgOut("|cFFD80000SLoTeLoot deactivated.|r") end
function showH() ShowH = 1; msgOut("|cFF25C510SLoTeHonor enabled.|r") end
function hideH() ShowH = 0; msgOut("|cFFD80000SLoTeHonor disabled.|r") end
function showC() ShowC = 1; msgOut("|cFF25C510SLoTeCurrency enabled.|r") end
function hideC() ShowC = 0; msgOut("|cFFD80000SLoTeCurrency disabled.|r") end
function showM() ShowM = 1; msgOut("|cFF25C510SLoTeMoney enabled.|r") end
function hideM() ShowM = 0; msgOut("|cFFD80000SLoTeMoney disabled.|r") end

function SLoTe_Command(msg)
	local cmd, task = (msg or ""):lower():match("^(%S*)%s*(.-)$")
	if cmd == "help" then
		msgOut("Type '/slote' (or '/slote config') to open the settings window.")
		msgOut("Use '/slote activate/deactivate' for the whole addon.")
		msgOut("Use '/slote scale 1.0' to adjust the font size (1.0 = 100%)")
		msgOut("Use '/slote loot enable/disable' to toggle if the loot window will be hidden.")
		msgOut("Use '/slote money enable/disable' to toggle if money will be shown.")
		msgOut("Use '/slote honor enable/disable' to toggle if honor will be shown.")
		msgOut("Use '/slote currency enable/disable' to toggle if currencies will be shown.")
		msgOut("Use '/slote mode arc' or '/slote mode straight' to change how loot text moves.")
		msgOut("Use '/slote fade smooth' or '/slote fade end' to change how loot text fades.")
		msgOut("Use '/slote test' to display a sample message.")
	elseif cmd == "mode" and (task == "arc" or task == "straight") then
		FloatMode = task
		msgOut("|cFF25C510SLoTe float mode: |r" .. task)
		testMessage()
	elseif cmd == "config" or cmd == "options" or cmd == "" then
		if SLoTe.ToggleOptions then SLoTe.ToggleOptions() end
	elseif cmd == "fade" and (task == "smooth" or task == "end") then
		FadeMode = task
		msgOut("|cFF25C510SLoTe fade: |r" .. (task == "smooth" and "smooth (fades the whole way)" or "end (fades at the end)"))
		testMessage()
	elseif cmd == "scale" then scale(task)
	elseif cmd == "test" then testMessage()
	elseif cmd == "activate" or cmd == "enable" then activate()
	elseif cmd == "deactivate" or cmd == "disable" then deactivate()
	elseif cmd == "loot" and task == "enable" then showL()
	elseif cmd == "loot" and task == "disable" then hideL()
	elseif cmd == "honor" and task == "enable" then showH()
	elseif cmd == "honor" and task == "disable" then hideH()
	elseif cmd == "currency" and task == "enable" then showC()
	elseif cmd == "currency" and task == "disable" then hideC()
	elseif cmd == "money" and task == "enable" then showM()
	elseif cmd == "money" and task == "disable" then hideM()
	else
		msgOut("|cFF25C510Enter /slote help to show commands.|r")
	end
end

SlashCmdList["SLoTe"] = SLoTe_Command;
SLASH_SLoTe1 = "/slote";

frame:SetScript("OnEvent", frame.OnEvent);
