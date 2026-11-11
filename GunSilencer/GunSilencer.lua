-- Gun Silencer for WoW Forever
-- Mutes Blizzard's gun fire/load sounds (by file ID) and plays silenced
-- replacements from this add-on's sounds folder whenever YOU fire a gun.
-- Note: other players' guns are muted too (the game gives no event for their shots).
--
-- Sounds live in sounds\<pack>\<volume>\GunFire0N.ogg / GunLoad0N.ogg,
-- pre-rendered at several volumes so switching is instant.

local ADDON_NAME = ...
local ROOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\sounds\\"

GunSilencer = {}
local GS = GunSilencer

-- Blizzard file IDs for Sound\Item\Weapons\Gun\*.ogg
local MUTED_IDS = {
	567721, 567718, 567722, -- GunFire01-03
	567719, 567720, 567723, -- GunLoad01-03
}
local FIRE = { "GunFire01.ogg", "GunFire02.ogg", "GunFire03.ogg" }
local LOAD = { "GunLoad01.ogg", "GunLoad02.ogg", "GunLoad03.ogg" }

GS.PACKS    = { { "m4a1", "Silenced M4A1" }, { "sniper", "Silenced Sniper (Area's)" } }
GS.VOLUMES  = { 100, 75, 50, 35, 25, 10 }   -- folders that exist for every pack
GS.CHANNELS = { { "SFX", "Effects" }, { "Master", "Master" }, { "Dialog", "Dialog" }, { "Ambience", "Ambience" } }

local DEFAULTS = {
	enabled = true,
	reload = true,
	pack = "m4a1",
	volume = 50,
	reloadDelay = 0.5,
	channel = "SFX",
	minimap = { angle = 190, hide = false },
}

-- Ranged shots that fire your gun. Spell IDs cover Auto Shot / Shoot (Gun);
-- names cover hunter shots of every rank (English client).
local SHOT_IDS = { [75] = true, [7918] = true }
local SHOT_NAMES = {
	["Auto Shot"] = true, ["Shoot"] = true, ["Shoot Gun"] = true,
	["Arcane Shot"] = true, ["Aimed Shot"] = true, ["Multi-Shot"] = true,
	["Concussive Shot"] = true, ["Distracting Shot"] = true, ["Scatter Shot"] = true,
	["Tranquilizing Shot"] = true, ["Steady Shot"] = true, ["Kill Shot"] = true,
	["Chimera Shot"] = true, ["Explosive Shot"] = true, ["Silencing Shot"] = true,
	["Serpent Sting"] = true, ["Scorpid Sting"] = true, ["Viper Sting"] = true,
	["Wyvern Sting"] = true, ["Volley"] = true, ["Chimaera Shot"] = true,
}

local GetSpellNameCompat = (C_Spell and C_Spell.GetSpellName)
	or function(id) return (GetSpellInfo(id)) end
local GetItemInfoInstantC = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local After = C_Timer and C_Timer.After

local db
local lastShot = -1

local function Chat(msg)
	print("|cff66ccffGun Silencer:|r " .. msg)
end
GS.Chat = Chat

local function HasGun()
	local id = GetInventoryItemID("player", 18) -- ranged slot
	if not id or not GetItemInfoInstantC then return false end
	local _, _, _, _, _, classID, subclassID = GetItemInfoInstantC(id)
	return classID == 2 and subclassID == 3 -- Weapon / Guns
end
GS.HasGun = HasGun

local function SetMuted(mute)
	local fn = mute and MuteSoundFile or UnmuteSoundFile
	if not fn then return end
	for _, id in ipairs(MUTED_IDS) do fn(id) end
end

-- Snap any number to the nearest pre-rendered volume level.
local function ValidVolume(v)
	v = tonumber(v)
	if not v then return 50 end
	local best, bestDiff = 50, math.huge
	for _, x in ipairs(GS.VOLUMES) do
		local d = math.abs(x - v)
		if d < bestDiff then best, bestDiff = x, d end
	end
	return best
end

local function Play(list)
	local path = ROOT .. db.pack .. "\\" .. ValidVolume(db.volume) .. "\\" .. list[math.random(#list)]
	PlaySoundFile(path, db.channel or "SFX")
end

local function Fire()
	local now = GetTime()
	if now - lastShot < 0.15 then return end -- avoid double-play for one shot
	lastShot = now
	Play(FIRE)
	if db.reload and After then
		After(tonumber(db.reloadDelay) or 0.5, function() Play(LOAD) end)
	end
end

function GS.Test()
	lastShot = -1
	Fire()
end

function GS.SetEnabled(on)
	db.enabled = on and true or false
	SetMuted(db.enabled)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		GunSilencerDB = GunSilencerDB or {}
		db = GunSilencerDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then
				db[k] = type(v) == "table" and { angle = v.angle, hide = v.hide } or v
			end
		end
		local okPack = false
		for _, p in ipairs(GS.PACKS) do if p[1] == db.pack then okPack = true end end
		if not okPack then db.pack = DEFAULTS.pack end
		db.volume = ValidVolume(db.volume)
		GS.db = db
		self:UnregisterEvent("ADDON_LOADED")

	elseif event == "PLAYER_LOGIN" then
		SetMuted(db.enabled)
		self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		if GS.UpdateMinimapButton then GS.UpdateMinimapButton() end

	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if not db.enabled then return end
		local spellID = arg3
		if not (SHOT_IDS[spellID] or SHOT_NAMES[GetSpellNameCompat(spellID) or ""]) then return end
		if HasGun() then Fire() end
	end
end)

SLASH_GUNSILENCER1 = "/gunsilencer"
SLASH_GUNSILENCER2 = "/gsil"
SlashCmdList.GUNSILENCER = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "on" then
		GS.SetEnabled(true); Chat("enabled.")
	elseif msg == "off" then
		GS.SetEnabled(false); Chat("disabled - normal gun sounds restored.")
	elseif msg == "reload" then
		db.reload = not db.reload; Chat("reload sound " .. (db.reload and "on." or "off."))
	elseif msg == "test" then
		GS.Test()
	elseif msg:match("^vol") then
		local v = tonumber(msg:match("(%d+)"))
		if v then db.volume = ValidVolume(v) end
		Chat("volume " .. db.volume .. "%  (choices: 100, 75, 50, 35, 25, 10)")
		GS.Test()
	elseif msg == "help" then
		Chat("/gsil  - open settings")
		Chat("/gsil on | off | reload | test | vol 50")
	else
		if GS.ToggleOptions then GS.ToggleOptions() end
	end
end
