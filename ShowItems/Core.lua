local ADDON, SI = ...

-- Shared constants
SI.MIN_SIZE = 20
SI.MAX_SIZE = 128
SI.DEFAULT_SIZE = 40
SI.SNAP_DISTANCE = 15

local floor = math.floor

------------------------------------------------------------------------
-- Utilities
------------------------------------------------------------------------

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end
SI.DeepCopy = DeepCopy

function SI.Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ShowItems:|r " .. tostring(message))
    end
end

-- Runs fn without arguments; errors go to the normal Lua error handler
-- and do not stop the caller (Lua 5.1 xpcall takes no extra arguments).
local function SafeCall(fn)
    return xpcall(fn, geterrorhandler())
end
SI.SafeCall = SafeCall

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------

function SI.NewDB()
    return {
        version = 1,
        enabled = true,
        locked = false,
        glow = true,
        alpha = 1,
        spacing = 0,
        nextGroup = 1,
        tracked = {},
        bindings = {},
        minimap = { angle = 215 },
        windowScale = 1.5,
        profiles = {},
        snapshots = {},
        sets = {},
        nextSetId = 1,
        favorites = {},
        nextFavorite = 1,
    }
end

SI.MAX_SNAPSHOTS = 5
SI.MAX_PROFILES = 50
SI.MAX_SETS = 50
SI.MAX_SPACING = 24
SI.MAX_NAME = 30

local function Number(value, default, lo, hi)
    if type(value) ~= "number" or value ~= value then return default end
    if lo and value < lo then value = lo end
    if hi and value > hi then value = hi end
    return value
end

function SI.SanitizeDB(db)
    db.enabled = db.enabled ~= false
    db.locked = db.locked == true
    db.glow = db.glow ~= false
    db.alpha = Number(db.alpha, 1, 0.1, 1)
    db.spacing = floor(Number(db.spacing, 0, 0, SI.MAX_SPACING) + 0.5)
    db.nextGroup = floor(Number(db.nextGroup, 1, 1))
    if type(db.tracked) ~= "table" then db.tracked = {} end
    if type(db.bindings) ~= "table" then db.bindings = {} end
    if type(db.minimap) ~= "table" then db.minimap = {} end
    db.minimap.angle = Number(db.minimap.angle, 215)
    -- only a size the player chose by dragging the corner is kept; otherwise the default applies
    db.windowScale = Number(db.windowScale, 1.5, 1, 4)
    db.windowScaleCustom = db.windowScaleCustom == true
    if not db.windowScaleCustom then db.windowScale = 1.5 end
    -- tab the window opens on; an unknown value falls back to the first tab when it is opened
    if type(db.lastTab) ~= "number" or db.lastTab ~= floor(db.lastTab) then db.lastTab = nil end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.snapshots) ~= "table" then db.snapshots = {} end
    for _, entry in ipairs({ { db.profiles, true }, { db.snapshots, false } }) do
        local list, named = entry[1], entry[2]
        for i = #list, 1, -1 do
            local p = list[i]
            if type(p) ~= "table" or type(p.data) ~= "table" or (named and type(p.name) ~= "string") then
                table.remove(list, i)
            else
                p.time = Number(p.time, 0)
                if type(p.label) ~= "string" then p.label = nil end
            end
        end
    end
    while #db.snapshots > SI.MAX_SNAPSHOTS do table.remove(db.snapshots) end
    -- sets: db.sets[id] = { name, icon, slots = { [slot] = { id, link } }, key }
    db.nextSetId = floor(Number(db.nextSetId, 1, 1))
    if type(db.sets) ~= "table" then db.sets = {} end
    local highestSetId = 0
    for id, set in pairs(db.sets) do
        local valid = type(id) == "number" and id >= 1 and id == floor(id)
            and type(set) == "table" and type(set.name) == "string" and set.name ~= ""
            and type(set.slots) == "table"
        if valid then
            for slot, item in pairs(set.slots) do
                if type(slot) ~= "number" or not SI.SLOTS[slot] or type(item) ~= "table"
                    or type(item.id) ~= "number" or item.id < 1 then
                    set.slots[slot] = nil
                elseif type(item.link) ~= "string" then
                    item.link = nil
                end
            end
            if type(set.key) ~= "string" or set.key == "" then set.key = nil end
            if type(set.icon) ~= "number" and type(set.icon) ~= "string" then set.icon = nil end
            valid = next(set.slots) ~= nil
        end
        if valid then
            highestSetId = math.max(highestSetId, id)
        else
            db.sets[id] = nil
        end
    end
    if db.nextSetId <= highestSetId then db.nextSetId = highestSetId + 1 end
    -- favorite items: db.favorites[itemID] = { seq, missing }
    db.nextFavorite = floor(Number(db.nextFavorite, 1, 1))
    if type(db.favorites) ~= "table" then db.favorites = {} end
    local highestSeq = 0
    for id, favorite in pairs(db.favorites) do
        if type(id) ~= "number" or id < 1 or id ~= floor(id) or type(favorite) ~= "table"
            or type(favorite.seq) ~= "number" or favorite.seq < 1 or favorite.seq ~= floor(favorite.seq) then
            db.favorites[id] = nil
        else
            if type(favorite.missing) ~= "number" then favorite.missing = nil end
            highestSeq = math.max(highestSeq, favorite.seq)
        end
    end
    if db.nextFavorite <= highestSeq then db.nextFavorite = highestSeq + 1 end
    for slot, t in pairs(db.tracked) do
        if type(slot) ~= "number" or not SI.SLOTS[slot] or type(t) ~= "table"
            or type(t.left) ~= "number" or type(t.top) ~= "number" then
            db.tracked[slot] = nil
        else
            t.size = Number(t.size, SI.DEFAULT_SIZE, SI.MIN_SIZE, SI.MAX_SIZE)
            t.moved = t.moved == true
            if type(t.group) ~= "number" then t.group = nil end
        end
    end
    for slot, key in pairs(db.bindings) do
        if type(slot) ~= "number" or not SI.SLOTS[slot] or type(key) ~= "string" or key == "" then
            db.bindings[slot] = nil
        end
    end
end

------------------------------------------------------------------------
-- Combat-safe execution queue
-- Tracker buttons are secure frames, so their layout cannot change in combat.
------------------------------------------------------------------------

local queue = {}

function SI.RunSafe(key, fn)
    if type(key) == "function" then fn, key = key, nil end
    if not InCombatLockdown() then
        fn()
        return true
    end
    if key then
        for i = 1, #queue do
            if queue[i].key == key then
                queue[i].fn = fn
                return false
            end
        end
    end
    queue[#queue + 1] = { key = key, fn = fn }
    return false
end

local function FlushQueue()
    if #queue == 0 then return end
    local pending = queue
    queue = {}
    for i = 1, #pending do SafeCall(pending[i].fn) end
end

------------------------------------------------------------------------
-- Events and initialization
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}
local inits = {}

function SI.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    local list = handlers[event]
    list[#list + 1] = fn
end

function SI.OnInit(fn)
    inits[#inits + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end)

-- Settings are stored per character: ShowItemsDB.chars["Name-Realm"].
-- Fields of the old account-wide format are moved to the first character that logs in.
local LEGACY_KEYS = { "version", "enabled", "locked", "alpha", "nextGroup", "tracked", "bindings", "minimap" }

local function KnownName(value)
    return type(value) == "string" and value ~= "" and value ~= "Unknown" and value ~= _G.UNKNOWNOBJECT
end

-- "Name-Realm". When the client does not give the name yet, the character GUID is used instead, so two
-- characters never end up sharing one record under a made-up name.
function SI.CharacterKey()
    local name, realm = UnitName("player"), GetRealmName()
    if KnownName(name) and KnownName(realm) then return name .. "-" .. realm end
    return "guid-" .. tostring(UnitGUID and UnitGUID("player") or "unknown")
end

function SI.ResolveCharacterDB(root, key)
    if type(root.chars) ~= "table" then root.chars = {} end
    local db = root.chars[key]
    if type(db) ~= "table" then
        if type(root.tracked) == "table" then
            db = {}
            for _, k in ipairs(LEGACY_KEYS) do db[k] = root[k] end
        else
            db = SI.NewDB()
        end
        root.chars[key] = db
    end
    for _, k in ipairs(LEGACY_KEYS) do root[k] = nil end
    local defaults = SI.NewDB()
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = DeepCopy(v) end
    end
    SI.SanitizeDB(db)
    return db
end

-- The settings live in the saved variables of the character (ShowItemsCharDB, the file in the
-- character folder of WTF). The first time a character logs in with this storage, store is empty and
-- takes a copy of what the account-wide file (ShowItemsDB.chars[key]) holds for this character. The
-- account-wide record is not removed, so it stays as a backup of the settings at that moment.
-- When the client did not give the name at an earlier login, the record was saved under the GUID key
-- (see SI.CharacterKey). altKey is that key: it is used when the record of key holds no data and this one does.
local function HasData(db)
    if type(db) ~= "table" then return false end
    for _, field in ipairs({ "tracked", "sets", "profiles" }) do
        if type(db[field]) == "table" and next(db[field]) ~= nil then return true end
    end
    return false
end

function SI.GuidKey()
    return UnitGUID and ("guid-" .. tostring(UnitGUID("player"))) or nil
end

function SI.ResolveStoredDB(store, root, key, altKey)
    if next(store) == nil and type(root) == "table" then
        local chars = type(root.chars) == "table" and root.chars or {}
        local from = key
        if not HasData(chars[key]) and altKey and HasData(chars[altKey]) then from = altKey end
        if type(chars[from]) == "table" or type(root.tracked) == "table" then
            for k, v in pairs(DeepCopy(SI.ResolveCharacterDB(root, from))) do store[k] = v end
        end
    end
    local defaults = SI.NewDB()
    for k, v in pairs(defaults) do
        if store[k] == nil then store[k] = DeepCopy(v) end
    end
    SI.SanitizeDB(store)
    return store
end

SI.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    if type(ShowItemsDB) ~= "table" then ShowItemsDB = {} end
    if type(ShowItemsCharDB) ~= "table" then ShowItemsCharDB = {} end
end)

SI.On("PLAYER_LOGIN", function()
    if type(ShowItemsDB) ~= "table" or type(ShowItemsCharDB) ~= "table" then return end
    SI.dbKey = SI.CharacterKey()
    SI.db = SI.ResolveStoredDB(ShowItemsCharDB, ShowItemsDB, SI.dbKey, SI.GuidKey())
    for i = 1, #inits do SafeCall(inits[i]) end
end)

SI.On("PLAYER_REGEN_ENABLED", FlushQueue)

------------------------------------------------------------------------
-- Enable / disable
------------------------------------------------------------------------

function SI.SetEnabled(value)
    SI.db.enabled = value and true or false
    if SI.CloseMenus then SI.CloseMenus() end
    SI.ApplyAll()
    if SI.UpdateMinimap then SI.UpdateMinimap() end
    if SI.RefreshOptions then SI.RefreshOptions() end
end

function SI.ToggleEnabled()
    SI.SetEnabled(not SI.db.enabled)
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

local function PrintHelp()
    SI.Print("commands")
    SI.Print("/si - open the window on the tab used last")
    SI.Print("/si sets - open the sets tab")
    SI.Print("/si profiles - open the profiles window")
    SI.Print("/si help - show this list")
    SI.Print("/si reset - untrack all slots and reset positions, sizes and key bindings")
    SI.Print("settings are saved for: " .. tostring(SI.dbKey))
end

SLASH_SHOWITEMS1 = "/si"
SLASH_SHOWITEMS2 = "/showitems"
SlashCmdList["SHOWITEMS"] = function(message)
    if not SI.db then return end
    local command = strlower(strtrim(message or ""))
    if command == "" then
        SI.OpenOptions()
    elseif command == "help" then
        PrintHelp()
    elseif command == "sets" then
        SI.OpenSets()
    elseif command == "profiles" then
        SI.OpenProfiles()
    elseif command == "reset" then
        SI.ResetAll()
        SI.Print("all tracking windows were reset")
    else
        PrintHelp()
    end
end

------------------------------------------------------------------------
-- Addon compartment (Blizzard's collapsed addon menu)
------------------------------------------------------------------------

function ShowItems_OnAddonCompartmentClick(_, buttonName)
    if not SI.db then return end
    if buttonName == "RightButton" then
        SI.ToggleEnabled()
    else
        SI.OpenOptions()
    end
end

function ShowItems_OnAddonCompartmentEnter(_, menuButtonFrame)
    if not SI.db or not menuButtonFrame then return end
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    SI.FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function ShowItems_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

function SI.FillTooltip(tooltip)
    tooltip:AddLine("ShowItems", 1, 0.82, 0)
    tooltip:AddLine(SI.db.enabled and "Enabled" or "Disabled", 1, 1, 1)
    tooltip:AddLine("Left-click: settings", 1, 1, 1)
    tooltip:AddLine("Right-click: enable or disable", 1, 1, 1)
end
