-- Minimal WoW API mock for running ShowItems logic outside the game.
-- It checks Lua logic only. It does not prove in-game behavior.
local M = {}

M.frames = {}
M.called = {}
M.cursor = { 0, 0 }
M.mods = { ctrl = false, alt = false, shift = false }
M.combat = false
M.mouseDown = {}
M.chat = {}
M.overrides = {}
M.equipped = {}
M.worn = {} -- [slot] = { id, link }
M.locked = {} -- [slot] = true: inventory item locked
M.lockPolls = 0 -- the next N lock checks of slot 1 report a lock (each full check reads slot 1 once)
M.simulate = false -- EquipItemByName really moves items between the bags and the worn slots
M.equipLog = {}
M.bags = {}
M.errors = {}

local Frame = {}
Frame.__index = function(self, key)
    local v = Frame[key]
    if v ~= nil then return v end
    -- only API-looking names are treated as unmocked methods; other fields are nil as in the game
    local prefixes = { "Set", "Get", "Is", "Create", "Register", "Unregister", "Enable", "Disable", "Clear", "Add",
        "Can", "Stop", "Start", "Lock", "Unlock", "Raise", "Lower", "Has", "Play", "Pause", "Sort" }
    for i = 1, #prefixes do
        if key:sub(1, #prefixes[i]) == prefixes[i] then
            M.called[key] = true
            return function() return nil end
        end
    end
    return nil
end

local function new(kind, name, parent)
    local f = setmetatable({
        kind = kind, name = name, parent = parent, shown = false, scripts = {}, hooks = {},
        attrs = {}, points = {}, w = 0, h = 0, alpha = 1, id = 0, text = "", value = 0, enabled = true,
        fontString = nil,
    }, Frame)
    M.frames[#M.frames + 1] = f
    return f
end

function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        return fn(...)
    end
end
function Frame:Show()
    if not self.shown then
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
end
function Frame:Hide()
    if self.shown then
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
end
function Frame:IsShown() return self.shown end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
    self.points[#self.points + 1] = { point, rel, relPoint, x or 0, y or 0 }
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:GetLeft()
    local p = self.points[1]
    if p and p[2] == M.UIParent and p[1] == "TOPLEFT" then return p[4] end
    return nil
end
function Frame:GetTop()
    local p = self.points[1]
    if p and p[2] == M.UIParent and p[1] == "TOPLEFT" then return p[5] end
    return nil
end
function Frame:GetRight()
    local l = self:GetLeft()
    return l and (l + self.w) or nil
end
function Frame:SetAttribute(k, v) self.attrs[k] = v end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:CreateTexture() return new("Texture", nil, self) end
function Frame:CreateFontString() return new("FontString", nil, self) end
function Frame:GetFontString()
    if not self.fontString then self.fontString = new("FontString", nil, self) end
    return self.fontString
end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetChecked(v) self.checked = v and true or false end
function Frame:GetChecked() return self.checked end
function Frame:SetID(id) self.id = id end
function Frame:GetID() return self.id end
function Frame:SetValue(v)
    self.value = v
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end
end
function Frame:GetValue() return self.value end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:SetEnabled(v) self.enabled = v and true or false end
function Frame:IsEnabled() return self.enabled end
function Frame:IsMouseOver() return self.mouseOver == true end
function Frame:SetBackdrop(backdrop) self.backdrop = backdrop end
function Frame:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function Frame:SetBackdropBorderColor(r, g, b, a) self.borderColor = { r, g, b, a } end
function Frame:RegisterEvent() end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:SetTexCoord(a, b, c, d) self.texCoord = { a, b, c, d } end
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale or 1 end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:GetCenter() return 960, 540 end

function M.install(env)
    env = env or _G
    local strict = {}
    env.CreateFrame = function(kind, name, parent, template)
        local f = new(kind, name, parent)
        if name then env[name] = f end
        if template == "OptionsSliderTemplate" and name then
            env[name .. "Low"] = new("FontString")
            env[name .. "High"] = new("FontString")
            env[name .. "Text"] = new("FontString")
        end
        return f
    end
    M.UIParent = new("Frame", "UIParent")
    M.UIParent.w, M.UIParent.h = 1920, 1080
    env.UIParent = M.UIParent
    env.Minimap = new("Frame", "Minimap")
    env.Minimap.w, env.Minimap.h = 140, 140
    env.GameTooltip = new("GameTooltip", "GameTooltip")
    env.GameTooltip.SetInventoryItem = function() return false end
    -- text lines of the tooltip: SetBagItem fills them from M.tipLines = { { left, right, r, g, b, wrap }, ... },
    -- the text regions are the globals GameTooltipTextLeft<i> and GameTooltipTextRight<i> as in the game
    env.ARMOR_TEMPLATE = "%d Armor"
    env.SHIELD_BLOCK_TEMPLATE = "%d Block"
    env.DPS_TEMPLATE = "(%s damage per second)"
    env.ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
    env.ITEM_SPELL_TRIGGER_ONUSE = "Use:"
    env.ITEM_SPELL_TRIGGER_ONPROC = "Chance on hit:"
    local tip = env.GameTooltip
    tip.lines = {}
    local function syncLines()
        for i = 1, 60 do
            env["GameTooltipTextLeft" .. i], env["GameTooltipTextRight" .. i] = nil, nil
        end
        for i, l in ipairs(tip.lines) do
            env["GameTooltipTextLeft" .. i] = {
                GetText = function() return l.left end,
                GetTextColor = function() return l.r or 1, l.g or 1, l.b or 1, 1 end,
                GetWordWrap = function() return l.wrap == true end,
                IsShown = function() return true end,
            }
            env["GameTooltipTextRight" .. i] = {
                GetText = function() return l.right end,
                GetTextColor = function() return l.rr or 1, l.rg or 1, l.rb or 1, 1 end,
                GetWordWrap = function() return false end,
                IsShown = function() return l.right ~= nil end,
            }
        end
    end
    tip.ClearLines = function(self) self.lines = {}; M.called.ClearLines = true; syncLines() end
    tip.NumLines = function(self) return #self.lines end
    tip.AddLine = function(self, text, r, g, b, wrap)
        self.lines[#self.lines + 1] = { left = text, r = r, g = g, b = b, wrap = wrap }
        syncLines()
    end
    tip.AddDoubleLine = function(self, left, right, r, g, b, rr, rg, rb)
        self.lines[#self.lines + 1] = { left = left, right = right, r = r, g = g, b = b, rr = rr, rg = rg, rb = rb }
        syncLines()
    end
    tip.SetBagItem = function(self)
        self.lines = {}
        for _, l in ipairs(M.tipLines or {}) do self.lines[#self.lines + 1] = l end
        syncLines()
        return true
    end
    -- a worn item: the same lines as a bag item, and false (as in the game) when there are none
    tip.SetInventoryItem = function(self)
        if not M.tipLines then return false end
        self.lines = {}
        for _, l in ipairs(M.tipLines) do self.lines[#self.lines + 1] = l end
        syncLines()
        return true
    end
    env.GameTooltip.SetOwner = function(self, owner) self.owner = owner end
    env.GameTooltip.IsOwned = function(self, owner) return self.owner == owner end
    -- the comparison tooltips of the game (the worn item next to an item tooltip)
    env.ShoppingTooltip1 = new("GameTooltip", "ShoppingTooltip1")
    env.ShoppingTooltip2 = new("GameTooltip", "ShoppingTooltip2")
    env.CharacterFrame = new("Frame", "CharacterFrame")
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.chat[#M.chat + 1] = msg end }
    env.geterrorhandler = function() return function(err) M.errors[#M.errors + 1] = tostring(err) end end
    env.InCombatLockdown = function() return M.combat end
    env.GetCursorPosition = function() return M.cursor[1], M.cursor[2] end
    env.IsControlKeyDown = function() return M.mods.ctrl end
    env.IsAltKeyDown = function() return M.mods.alt end
    env.IsShiftKeyDown = function() return M.mods.shift end
    env.IsMouseButtonDown = function(b) return M.mouseDown[b] == true end
    env.GetInventoryItemTexture = function(_, slot) return M.equipped[slot] end
    env.GetInventoryItemCooldown = function() return 0, 0, 1 end
    -- overrides belong to their owner frame: clearing one owner leaves the others alone
    env.ClearOverrideBindings = function(owner)
        for key, entry in pairs(M.overrides) do
            if entry.owner == owner then M.overrides[key] = nil end
        end
    end
    env.SetOverrideBindingClick = function(owner, _, key, name, button)
        M.overrides[key] = { name, button, owner = owner }
    end
    -- FauxScrollFrameTemplate helpers: only the offset is kept
    env.FauxScrollFrame_Update = function(sf, count, visible)
        sf.offset = math.max(0, math.min(sf.offset or 0, math.max(0, count - visible)))
    end
    env.FauxScrollFrame_GetOffset = function(sf) return sf.offset or 0 end
    env.FauxScrollFrame_OnVerticalScroll = function(sf, value, height, update)
        sf.offset = math.floor(value / height + 0.5)
        if update then update() end
    end
    env.GetInventoryItemID = function(_, slot) return M.worn[slot] and M.worn[slot].id end
    env.GetInventoryItemLink = function(_, slot) return M.worn[slot] and M.worn[slot].link end
    env.IsInventoryItemLocked = function(slot)
        if slot == 1 and M.lockPolls > 0 then
            M.lockPolls = M.lockPolls - 1
            return true
        end
        return M.locked[slot] == true
    end
    env.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
    env.GetItemInfo = function(link)
        -- the quality is read from the color code of the mock links
        if type(link) ~= "string" then return nil end
        if link:find("1eff00", 1, true) then return "name", link, 2 end
        if link:find("0070dd", 1, true) then return "name", link, 3 end
    end
    env.UnitName = function() return M.character or "Tester" end
    env.GetRealmName = function() return "Realm" end
    env.GetInventorySlotInfo = function(name)
        return 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name:gsub("Slot$", "")
    end
    env.CreateFont = function(name)
        local font = new("Font", name)
        return font
    end
    env.time = os.time
    env.date = os.date
    env.strlower = string.lower
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.tinsert = table.insert
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.C_Timer = { After = function(_, fn) fn() end }
    env.NUM_BAG_SLOTS = 4
    env.CursorHasItem = function() return false end
    env.CanDualWield = function() return true end
    env.C_Container = {
        GetContainerNumSlots = function(bag) return M.bags[bag] and M.bags[bag].n or 0 end,
        GetContainerItemInfo = function(bag, i)
            local it = M.bags[bag] and M.bags[bag][i]
            if not it then return nil end
            return { hyperlink = it.link, itemID = it.id, iconFileID = it.icon, stackCount = it.count or 1,
                isLocked = it.locked }
        end,
    }
    env.C_Item = {
        GetItemInfoInstant = function(id)
            for _, bag in pairs(M.bags) do
                for _, it in pairs(bag) do
                    if type(it) == "table" and (it.id == id or it.link == id) then
                        return it.id, "Armor", "x", it.loc, it.icon
                    end
                end
            end
        end,
        EquipItemByName = function(link, slot)
            M.lastEquip = { link, slot }
            M.equipLog[#M.equipLog + 1] = { link, slot }
            if not M.simulate then return end
            -- take the item from the bags and put the worn one in its place
            for _, bag in pairs(M.bags) do
                for i = 1, bag.n or 0 do
                    local it = bag[i]
                    if it and it.link == link then
                        local old = M.worn[slot]
                        M.worn[slot] = { id = it.id, link = it.link }
                        bag[i] = old and { id = old.id, link = old.link, loc = it.loc, icon = it.icon } or nil
                        return
                    end
                end
            end
        end,
    }
    env.math.atan2 = env.math.atan2 or function(y, x) return math.atan(y / x) end
    return env
end

return M
