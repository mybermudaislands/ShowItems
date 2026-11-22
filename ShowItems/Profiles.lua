local _, SI = ...

local max, min = math.max, math.min
local UI = SI.UI

-- Profiles: named copies of the window layout (tracked slots, positions, sizes, groups,
-- opacity, lock, key bindings). Snapshots: the last SI.MAX_SNAPSHOTS automatic copies,
-- taken before a reset, before loading a profile and before restoring a snapshot.
-- Both are stored per character. Sets are not part of a profile.

local MAX_NAME = 30
local PROFILE_ROWS, ROW_HEIGHT, BUTTON_GAP = 4, 24, 4

local ui = {}
local selected -- selected profile table

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function Now()
    return _G.time and _G.time() or 0
end

local function FormatTime(stamp, long)
    if _G.date and stamp and stamp > 0 then
        return _G.date(long and "%Y-%m-%d %H:%M" or "%d.%m %H:%M", stamp)
    end
    return ""
end

function SI.CaptureLayout()
    local db = SI.db
    return {
        tracked = SI.DeepCopy(db.tracked),
        bindings = SI.DeepCopy(db.bindings),
        alpha = db.alpha,
        spacing = db.spacing,
        locked = db.locked,
        nextGroup = db.nextGroup,
    }
end

-- Saves the current layout as a snapshot. Nothing is saved when there is nothing to lose.
function SI.TakeSnapshot(label)
    local db = SI.db
    if next(db.tracked) == nil and next(db.bindings) == nil then return false end
    table.insert(db.snapshots, 1, { label = label, time = Now(), data = SI.CaptureLayout() })
    while #db.snapshots > SI.MAX_SNAPSHOTS do table.remove(db.snapshots) end
    SI.RefreshWindow()
    return true
end

-- Replaces the current layout with `data` (a profile or a snapshot).
-- The current layout is saved as a snapshot first, so every restore can be undone.
local function ApplyData(data, label)
    local copy = {
        enabled = true, minimap = {},
        tracked = SI.DeepCopy(data.tracked), bindings = SI.DeepCopy(data.bindings),
        alpha = data.alpha, spacing = data.spacing, locked = data.locked, nextGroup = data.nextGroup,
    }
    SI.SanitizeDB(copy)
    if InCombatLockdown() then SI.Print("changes will be applied after combat") end
    SI.RunSafe("restore-layout", function()
        local db = SI.db
        SI.TakeSnapshot(label)
        db.tracked, db.bindings = copy.tracked, copy.bindings
        db.alpha, db.spacing, db.locked, db.nextGroup = copy.alpha, copy.spacing, copy.locked, copy.nextGroup
        -- restored slot keys win over a set that uses the same key
        if SI.ReleaseSetKey then
            for _, key in pairs(db.bindings) do SI.ReleaseSetKey(key) end
        end
        SI.SetResizeMode(nil)
        if SI.CloseMenus then SI.CloseMenus() end
        SI.ApplyAll()
        SI.RefreshWindow()
    end)
end

function SI.SaveProfile(name)
    name = strtrim(name or ""):sub(1, MAX_NAME)
    if name == "" then return nil, "enter a profile name" end
    local list = SI.db.profiles
    for i, p in ipairs(list) do
        if p.name == name then table.remove(list, i) break end
    end
    if #list >= SI.MAX_PROFILES then return nil, "too many profiles, delete one first" end
    local profile = { name = name, time = Now(), data = SI.CaptureLayout() }
    table.insert(list, 1, profile)
    SI.RefreshWindow()
    return profile
end

function SI.LoadProfile(profile)
    if not profile or not profile.data then return end
    ApplyData(profile.data, "Before loading " .. profile.name)
end

function SI.DeleteProfile(profile)
    local list = SI.db.profiles
    for i, p in ipairs(list) do
        if p == profile then
            table.remove(list, i)
            break
        end
    end
    SI.RefreshWindow()
end

function SI.RestoreSnapshot(snapshot)
    if not snapshot or not snapshot.data then return end
    ApplyData(snapshot.data, "Before restoring a state")
end

------------------------------------------------------------------------
-- Tab (the same look as the ItemRack Events tab)
------------------------------------------------------------------------

local function RowTip(row, field)
    row:HookScript("OnEnter", function(self)
        local item = self[field]
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(item.name or item.label or "Saved state", 1, 0.82, 0)
        GameTooltip:AddLine(FormatTime(item.time, true), 1, 1, 1)
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function SaveFromEditBox()
    ui.name:ClearFocus()
    local profile, err = SI.SaveProfile(ui.name:GetText())
    if not profile then
        SI.Print(err)
        return
    end
    selected = profile
    SI.RefreshWindow()
end

-- A list box with rows of 140 x 24, a scroll bar and a note shown while the list is empty.
local function BuildList(sub, y, height, count, emptyText, rowType, field, onClick, scrollName)
    local box = UI.Panel(sub, 178, height, "icons")
    box:SetPoint("TOP", 0, y)
    local list = { rows = {} }
    list.none = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    list.none:SetPoint("TOPLEFT", 12, -12)
    list.none:SetText(emptyText)
    for i = 1, count do
        local row = UI.Row(box, 140, ROW_HEIGHT, -8 - (i - 1) * ROW_HEIGHT, onClick)
        row.rowType = rowType
        RowTip(row, field)
        list.rows[i] = row
    end
    list.scroll = CreateFrame("ScrollFrame", scrollName, box, "FauxScrollFrameTemplate")
    list.scroll:SetPoint("TOPLEFT", list.rows[1], 0, 1)
    list.scroll:SetPoint("BOTTOMRIGHT", list.rows[count], -2, 1)
    list.scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, SI.RefreshWindow)
    end)
    return list
end

local function Build(sub)
    ui.name = UI.NameField(sub, "Profile name:", "ShowItemsProfileName", MAX_NAME)

    ui.profiles = BuildList(sub, -52, 108, PROFILE_ROWS, "No saved profiles yet.", "profile", "profile", function(self)
        selected = self.profile
        if selected then ui.name:SetText(selected.name) end
        SI.RefreshWindow()
    end, "ShowItemsProfileScrollFrame")

    -- Load and Save in one row, Delete under them (the pair is centered, the gap is BUTTON_GAP)
    ui.load = UI.Button(sub, 55, 28, "Load", "ShowItemsProfileLoad")
    ui.load:SetPoint("TOP", -(55 + BUTTON_GAP) / 2, -172)
    ui.load:SetScript("OnClick", function()
        if not selected then
            SI.Print("select a profile first")
            return
        end
        SI.LoadProfile(selected)
    end)
    UI.Tip(ui.load, "Load", "Replaces the current layout with the selected profile.")

    ui.delete = UI.Button(sub, 55, 28, "Delete", "ShowItemsProfileDelete")
    ui.delete:SetPoint("TOP", ui.load, "BOTTOM", (55 + BUTTON_GAP) / 2, -BUTTON_GAP)
    ui.delete:SetScript("OnClick", function()
        local profile = selected
        if not profile then
            SI.Print("select a profile first")
            return
        end
        UI.Confirm("Delete this profile?", function()
            SI.DeleteProfile(profile)
            if selected == profile then selected = nil end
            SI.RefreshWindow()
        end)
    end)
    UI.Tip(ui.delete, "Delete", "Deletes the selected profile after a confirmation.")

    ui.save = UI.Button(sub, 55, 28, "Save", "ShowItemsProfileSave")
    ui.save:SetPoint("LEFT", ui.load, "RIGHT", BUTTON_GAP, 0)
    ui.save:SetScript("OnClick", SaveFromEditBox)
    UI.Tip(ui.save, "Save", "Saves the current layout under this name: tracked slots, positions, sizes, spacing, groups, opacity, lock and key bindings. Sets are not included.")

    sub:SetScript("OnHide", function()
        ui.name:ClearFocus()
    end)
end

local function FillList(list, items, count, field, isSelected)
    FauxScrollFrame_Update(list.scroll, #items, count, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(list.scroll)
    for i = 1, count do
        local row = list.rows[i]
        local item = items[offset + i]
        row[field] = item
        if item then
            row.name:SetText(item.name or item.label or "Saved state")
            row.info:SetText(FormatTime(item.time))
            row.sel:SetShown(isSelected ~= nil and isSelected(item))
            row:Show()
        else
            row:Hide()
        end
    end
    list.none:SetShown(#items == 0)
end

local function Refresh()
    local db = SI.db
    local valid = false
    for _, p in ipairs(db.profiles) do
        if p == selected then valid = true end
    end
    if not valid then selected = nil end
    FillList(ui.profiles, db.profiles, PROFILE_ROWS, "profile", function(p) return p == selected end)
end

SI.RegisterTab(3, "Profiles", {
    build = Build,
    refresh = Refresh,
    -- the slots are not used on this tab: always dimmed, no item menu
    slotState = function() return "off" end,
    slotTip = function(slot) return SI.db.tracked[slot] and "Tracked." or "Not tracked." end,
})