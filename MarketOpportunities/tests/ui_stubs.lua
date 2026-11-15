-- Widget stand-ins for UI smoke tests: every widget accepts any method call.
-- Fonts strings remember their text so tests can look for it.
_texts = {}
local Widget = {}
Widget.__index = function(t, k)
	local v = rawget(Widget, k)
	if v ~= nil then return v end
	if type(k) == "string" and k:match("^%u") then return function() return nil end end -- methods only
	return nil
end
local function New(kind, name)
	local w = setmetatable({ kind = kind, events = {}, scripts = {}, shown = true, children = {} }, Widget)
	if name then _G[name] = w end
	_frames[#_frames + 1] = w
	return w
end
function Widget:CreateTexture() return New("Texture") end
function Widget:CreateFontString() local f = New("FontString"); _texts[#_texts + 1] = f; return f end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:GetStringHeight() return 12 end
function Widget:GetStringWidth() return 60 end
function Widget:GetHeight() return 100 end
function Widget:GetWidth() return 100 end
function Widget:GetVerticalScroll() return 0 end
function Widget:GetCenter() return 50, 50 end
function Widget:GetEffectiveScale() return 1 end
function Widget:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function Widget:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown end
function Widget:RegisterEvent(e) self.events[e] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:SetScript(k, fn) self.scripts[k] = fn end
function Widget:GetScript(k) return self.scripts[k] end
function Widget:HookScript(k, fn) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end fn(...) end end
function Widget:GetChecked() return self.checked end
function Widget:SetChecked(v) self.checked = v end
function Widget:GetName() return nil end
function Widget:GetParent() return UIParent end
function Widget:GetFontString() return New("FontString") end

function CreateFrame(kind, name) return New(kind, name) end
UIParent = New("Frame")
Minimap = New("Frame")
GameTooltip = New("GameTooltip")
function hooksecurefunc(t, k, fn)
	if type(t) == "string" then t, k, fn = _G, t, k end
	local old = t[k]
	t[k] = function(...) local r = { old(...) } fn(...) return unpack(r) end
end
function GetCursorPosition() return 0, 0 end
C_AddOns = { GetAddOnMetadata = function() return nil end, IsAddOnLoaded = function() return false end }

-- Starts a frame hidden, like a real window after S.Window
function _textsContaining(s)
	local n = 0
	for _, f in ipairs(_texts) do if f.shown and f.text and tostring(f.text):find(s, 1, true) then n = n + 1 end end
	return n
end
