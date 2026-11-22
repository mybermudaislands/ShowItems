local _, SI = ...

local max, min = math.max, math.min
local UI = SI.UI

-- Sets: named groups of equipped items for the chosen slots, saved per character.
-- db.sets[id] = { name, slots = { [slot] = { id = itemID, link = hyperlink } }, key }
-- Items are taken from the player's bags only (never the bank). Slots that were empty
-- when the set was saved are not part of the set.
-- Outside combat the swap runs from Lua, one item at a time. On this client every equipment
-- move from insecure code is blocked in combat, so only a key binding can swap weapons
-- in combat: its secure button runs /equipslot lines.

local CC = _G.C_Container

local POLL, MAX_WAIT, MAX_TRIES = 0.1, 30, 3
-- Rings and trinkets: the two slots of a pair are interchangeable.
local PAIRS = { [11] = { 11, 12 }, [12] = { 11, 12 }, [13] = { 13, 14 }, [14] = { 13, 14 } }
local WEAPON_SLOTS = { 16, 17, 18 }

local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

-- Set ids ordered by name.
function SI.SortedSetIds()
    local sets = SI.db.sets
    local ids = {}
    for id in pairs(sets) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local na, nb = sets[a].name:lower(), sets[b].name:lower()
        if na ~= nb then return na < nb end
        return a < b
    end)
    return ids
end

function SI.FindSetByName(name)
    for id, set in pairs(SI.db.sets) do
        if set.name == name then return id, set end
    end
end

-- Saves the items for `slotList` under `name` (an existing set with that name is
-- overwritten and keeps its key). A slot takes its item from `chosen[slot]` ({ id, link })
-- when there is one, otherwise the worn item. icon: the picture of the set (nil keeps the old one;
-- a set without a picture shows the icon of its first item). Returns the set id, or nil and a message.
function SI.SaveSet(name, slotList, chosen, icon)
    name = strtrim(name or ""):sub(1, SI.MAX_NAME)
    if name == "" then return nil, "enter a set name" end
    local captured, count = {}, 0
    for _, slot in ipairs(slotList or {}) do
        if SI.SLOTS[slot] then
            local pick = chosen and chosen[slot]
            if pick and pick.id then
                captured[slot] = { id = pick.id, link = pick.link }
                count = count + 1
            else
                local id = GetInventoryItemID("player", slot)
                if id then
                    captured[slot] = { id = id, link = GetInventoryItemLink("player", slot) }
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return nil, "select slots that hold items first" end
    local db = SI.db
    local id, set = SI.FindSetByName(name)
    if not set then
        local total = 0
        for _ in pairs(db.sets) do total = total + 1 end
        if total >= SI.MAX_SETS then return nil, "too many sets, delete one first" end
        id = db.nextSetId
        db.nextSetId = id + 1
        set = { name = name }
        db.sets[id] = set
    end
    set.slots = captured
    if icon ~= nil then set.icon = icon end
    SI.ApplySetBindings()
    return id
end

function SI.DeleteSet(id)
    if not SI.db.sets[id] then return end
    SI.db.sets[id] = nil
    SI.ApplySetBindings()
end

local function ItemTexture(id)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if getInstant then
        local _, _, _, _, icon = getInstant(id)
        if icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- The icon of a set: the one that was chosen, otherwise the icon of its first item.
function SI.SetIcon(set)
    if set.icon then return set.icon end
    for _, slot in ipairs(SI.SLOT_ORDER) do
        if set.slots[slot] then return ItemTexture(set.slots[slot].id) end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

------------------------------------------------------------------------
-- Planning: which item goes to which slot
------------------------------------------------------------------------

local function Worn(slot)
    return GetInventoryItemID("player", slot)
end

-- Returns the list of { slot, id, link } that has to be equipped, ordered by slot
-- (main hand before off hand). Worn items that already match are left alone.
function SI.PlanSet(set)
    local steps = {}
    local slots = {}
    for slot in pairs(set.slots) do slots[#slots + 1] = slot end
    table.sort(slots)
    local handled = {}
    for _, slot in ipairs(slots) do
        local pair = PAIRS[slot]
        if not pair then
            local item = set.slots[slot]
            if Worn(slot) ~= item.id then
                steps[#steps + 1] = { slot = slot, id = item.id, link = item.link }
            end
        elseif not handled[pair[1]] then
            handled[pair[1]], handled[pair[2]] = true, true
            local free = { [pair[1]] = true, [pair[2]] = true }
            local remaining = {}
            for _, s in ipairs(pair) do
                local item = set.slots[s]
                if item then
                    -- a wanted item that is already worn in either slot stays where it is
                    local kept
                    for _, w in ipairs({ s, pair[1], pair[2] }) do
                        if free[w] and Worn(w) == item.id then
                            kept = w
                            break
                        end
                    end
                    if kept then
                        free[kept] = nil
                    else
                        remaining[#remaining + 1] = { slot = s, item = item }
                    end
                end
            end
            for _, entry in ipairs(remaining) do
                local target
                if free[entry.slot] then
                    target = entry.slot
                else
                    target = (free[pair[1]] and pair[1]) or (free[pair[2]] and pair[2])
                end
                if target then
                    free[target] = nil
                    steps[#steps + 1] = { slot = target, id = entry.item.id, link = entry.item.link }
                end
            end
        end
    end
    table.sort(steps, function(a, b) return a.slot < b.slot end)
    return steps
end

------------------------------------------------------------------------
-- Equipping
------------------------------------------------------------------------

-- Item in the bags for a planned step: the exact link first, then any item with the same id.
local function FindInBags(step)
    local byId
    for bag = 0, _G.NUM_BAG_SLOTS or 4 do
        for index = 1, SI.NumSlots(bag) do
            local link, id = SI.BagItem(bag, index)
            if link then
                if step.link and link == step.link then
                    return { bag = bag, index = index, link = link }
                end
                if not byId and id == step.id then byId = { bag = bag, index = index, link = link } end
            end
        end
    end
    return byId
end

local function BagLocked(bag, index)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, index)
        return info and info.isLocked
    elseif _G.GetContainerItemInfo then
        local _, _, locked = _G.GetContainerItemInfo(bag, index)
        return locked
    end
end

local function AnyLocked()
    if _G.IsInventoryItemLocked then
        for slot = 1, 19 do
            if _G.IsInventoryItemLocked(slot) then return true end
        end
    end
    for bag = 0, _G.NUM_BAG_SLOTS or 4 do
        for index = 1, SI.NumSlots(bag) do
            if BagLocked(bag, index) then return true end
        end
    end
    return false
end

local run -- the swap in progress

local function ItemName(step)
    return step.link or ("item:" .. step.id)
end

local function Stop(message)
    if message then SI.Print(message) end
    if run then
        if #run.missing > 0 then SI.Print("not in your bags: " .. table.concat(run.missing, " ")) end
        if #run.failed > 0 then SI.Print("could not equip: " .. table.concat(run.failed, " ")) end
    end
    run = nil
    SI.RefreshWindow()
end

local function Next(r)
    r.index = r.index + 1
    r.tries = 0
    r.pending = false
end

local Step

-- One item at a time: equip it, wait for the item locks to clear, check the result.
local function StepBody()
    local r = run
    if not r then return end
    if InCombatLockdown() then return Stop("swap stopped: combat started") end
    if AnyLocked() then
        r.waited = r.waited + 1
        if r.waited > MAX_WAIT then return Stop("swap stopped: items stayed locked") end
        return After(POLL, Step)
    end
    r.waited = 0
    while true do
        local step = r.steps[r.index]
        if not step then return Stop() end
        if r.pending then
            r.pending = false
            if Worn(step.slot) == step.id then
                Next(r)
            elseif r.tries >= MAX_TRIES then
                r.failed[#r.failed + 1] = ItemName(step)
                Next(r)
            end
        elseif Worn(step.slot) == step.id then
            Next(r)
        else
            local item = FindInBags(step)
            if not item then
                r.missing[#r.missing + 1] = ItemName(step)
                Next(r)
            else
                r.tries = r.tries + 1
                r.pending = true
                SI.EquipFromBag(item, step.slot)
                return After(POLL, Step)
            end
        end
    end
end

-- An error must not leave a swap "in progress" forever.
Step = function()
    if not SI.SafeCall(StepBody) then run = nil end
end

local function OnlyWeapons(set)
    for slot in pairs(set.slots) do
        if slot < 16 or slot > 18 then return false end
    end
    return true
end

-- fromKey: the swap was started by the set key binding (weapons are then swapped by the
-- secure macro in combat, so nothing is said about them).
function SI.EquipSet(set, fromKey)
    if not set or type(set.slots) ~= "table" then return end
    if InCombatLockdown() then
        if fromKey then
            if not OnlyWeapons(set) then SI.Print("only weapons can be changed in combat") end
        else
            SI.Print("sets cannot be equipped in combat")
        end
        return
    end
    if run then
        SI.Print("a swap is already in progress")
        return
    end
    if CursorHasItem() then
        SI.Print("put down the item on the cursor first")
        return
    end
    local steps = SI.PlanSet(set)
    if #steps == 0 then return end
    run = { steps = steps, index = 1, tries = 0, waited = 0, pending = false, missing = {}, failed = {} }
    Step()
end

------------------------------------------------------------------------
-- Key bindings (override bindings: never touch the player's saved bindings)
------------------------------------------------------------------------

local setOwner = CreateFrame("Frame")

local function Macrotext(set)
    local text = "/stopmacro [nocombat]\n"
    for _, slot in ipairs(WEAPON_SLOTS) do
        local item = set.slots[slot]
        if item then text = text .. "/equipslot " .. slot .. " item:" .. item.id .. "\n" end
    end
    return text
end

local function ButtonName(id)
    return "ShowItemsSet" .. id
end

local function SetButton(id)
    local name = ButtonName(id)
    local b = _G[name]
    if not b then
        b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        b.setId = id
        -- down only: a key binding delivers both a down and an up click
        b:RegisterForClicks("AnyDown")
        b:SetAttribute("type", "macro")
        b:SetScript("PreClick", function(self)
            local set = SI.db and SI.db.enabled and SI.db.sets[self.setId]
            if set then SI.EquipSet(set, true) end
        end)
    end
    return b
end

-- Buttons, their macro text and the key bindings of all sets. The attributes of a secure
-- button cannot change in combat, so this waits for the end of combat.
function SI.ApplySetBindings()
    SI.RunSafe("set-bindings", function()
        ClearOverrideBindings(setOwner)
        local db = SI.db
        for id, set in pairs(db.sets) do
            if set.key then
                SetButton(id):SetAttribute("macrotext", Macrotext(set))
                if db.enabled then
                    SetOverrideBindingClick(setOwner, true, set.key, ButtonName(id), "LeftButton")
                end
            end
        end
    end)
end

-- Takes `key` away from every set that uses it. Returns true when a set lost its key.
function SI.ReleaseSetKey(key)
    local changed = false
    for _, set in pairs(SI.db.sets) do
        if set.key == key then
            set.key = nil
            changed = true
        end
    end
    if changed then
        SI.ApplySetBindings()
        SI.RefreshWindow()
    end
    return changed
end

function SI.SetSetBinding(id, key)
    local db = SI.db
    local set = db.sets[id]
    if not set then return end
    if key then
        SI.ReleaseSetKey(key)
        for slot, k in pairs(db.bindings) do
            if k == key then db.bindings[slot] = nil end
        end
        set.key = key
    else
        set.key = nil
    end
    if InCombatLockdown() then SI.Print("changes will be applied after combat") end
    SI.ApplyBindings()
    SI.ApplySetBindings()
end

------------------------------------------------------------------------
-- Tab (the ItemRack "Sets" tab)
------------------------------------------------------------------------

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local RIGHT_SLOTS = { [10] = true, [6] = true, [7] = true, [8] = true, [11] = true, [12] = true, [13] = true, [14] = true }
local BOTTOM_SLOTS = { [16] = true, [17] = true, [18] = true }
-- 15% larger than the ItemRack 28 px cells (28 * 1.15 = 32). 5 cells of 32 px plus the scroll bar do
-- not fit the 178 px wide box, so 4 columns are shown (the first 20 pictures are exactly 5 rows).
local ICON_ROWS, ICON_COLUMNS, ICON_SIZE, ICON_PICTURE = 4, 4, 32, 30
local LIST_ROWS, LIST_ROW_HEIGHT = 10, 24

local ui = {}
local selection = {} -- [slot] = true: slots that belong to the set being edited
local choice = {} -- [slot] = { id, link, icon }: the item chosen for the slot
local selectedSet -- id of the set shown in the editor
local selectedIcon -- the chosen picture; nil: the icon of the first item
local icons -- every picture that can be chosen
local held -- state kept while the list of sets is open

local function SelectedSlots()
    local list = {}
    for slot in pairs(selection) do list[#list + 1] = slot end
    table.sort(list)
    return list
end

local function ItemIcon(slot)
    return (choice[slot] and choice[slot].icon) or GetInventoryItemTexture("player", slot)
end

-- The picture used while none was chosen: the icon of the first selected item.
local function AutoIcon()
    for _, slot in ipairs(SI.SLOT_ORDER) do
        if selection[slot] and ItemIcon(slot) then return ItemIcon(slot) end
    end
    return QUESTION
end

-- Fills the editor with a saved set: its name, picture, slots and items.
local function SelectSet(id)
    local set = SI.db.sets[id]
    selectedSet = id
    for slot in pairs(selection) do selection[slot] = nil end
    for slot in pairs(choice) do choice[slot] = nil end
    if set then
        ui.name:SetText(set.name)
        selectedIcon = set.icon
        for slot, item in pairs(set.slots) do
            selection[slot] = true
            choice[slot] = { id = item.id, link = item.link, icon = ItemTexture(item.id) }
        end
    end
end

local function SaveFromEditBox()
    ui.name:ClearFocus()
    local id, err = SI.SaveSet(ui.name:GetText(), SelectedSlots(), choice, selectedIcon)
    if not id then
        SI.Print(err)
        return
    end
    -- slots that held no item are not part of the set: show what was really saved
    SelectSet(id)
    SI.RefreshWindow()
end

local function CurrentSet(hint)
    local set = selectedSet and SI.db.sets[selectedSet]
    if not set then SI.Print(hint or "save or pick a set first") end
    return set
end

local function ShowSetTooltip(owner, set)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(set.name, 1, 0.82, 0)
    for _, slot in ipairs(SI.SLOT_ORDER) do
        local item = set.slots[slot]
        if item then
            GameTooltip:AddLine(SI.SLOTS[slot].name .. ": " .. (item.link or ("item:" .. item.id)), 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

-- List of the saved sets next to a widget (the minimap button). Clicking a set equips it.
-- The menu is drawn above tooltips, so the tooltip of the widget never covers it.
local setMenu

function SI.HideSetMenu()
    if setMenu then setMenu:Hide() end
end

function SI.ToggleSetMenu(anchor)
    if setMenu and setMenu:IsShown() then
        setMenu:Hide()
        return
    end
    local entries = {}
    for _, id in ipairs(SI.SortedSetIds()) do
        local set = SI.db.sets[id]
        entries[#entries + 1] = {
            icon = SI.SetIcon(set),
            label = set.name,
            onClick = function()
                setMenu:Hide()
                SI.EquipSet(set)
            end,
            onEnter = function(button) ShowSetTooltip(button, set) end,
        }
    end
    if #entries == 0 then
        SI.Print("no saved sets yet, create one in the Sets tab")
        return
    end
    -- round buttons the size of the minimap button (31 px, 33 px apart) at the scale of that button,
    -- so the list looks like a row of more minimap buttons; the set name is in the tooltip
    if not setMenu then setMenu = SI.NewGridMenu("ShowItemsSetMenu", { round = true, icon = 31, step = 33 }) end
    local _, y = anchor:GetCenter()
    local high = y and y > UIParent:GetHeight() / 2
    setMenu:Open(entries, anchor, high and "BELOW" or "ABOVE")
end

------------------------------------------------------------------------
-- Menu of items next to a slot (opens while the mouse is over the slot)
------------------------------------------------------------------------

local function PickItem(slot, entry)
    choice[slot] = { id = entry.id, link = entry.link, icon = entry.icon }
    selection[slot] = true
    ui.menu:Hide()
    SI.RefreshWindow()
end

-- The menu opens outward: to the left of the left column, to the right of the right column,
-- below the weapon slots.
local function SlotDock(slot)
    if BOTTOM_SLOTS[slot] then return "DOWN" end
    if RIGHT_SLOTS[slot] then return "RIGHT" end
    return "LEFT"
end

-- pick(slot, entry) runs when an item is clicked. Entries of bag items have entry.bagItem.
-- The menu is used in the Sets tab only and lists the bag items only; worn items are not repeated.
local function OpenSlotMenu(slot, anchor, pick)
    local entries = {}
    local function Add(entry)
        entry.onClick = function() pick(slot, entry) end
        entries[#entries + 1] = entry
    end
    for _, item in ipairs(SI.ScanBags(slot)) do
        Add({
            id = item.id, link = item.link, icon = item.icon or ItemTexture(item.id), count = item.count,
            bagItem = item,
            onEnter = function(button)
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                if not pcall(GameTooltip.SetBagItem, GameTooltip, item.bag, item.index) then
                    GameTooltip:SetHyperlink(item.link)
                end
                GameTooltip:Show()
            end,
        })
    end
    if #entries == 0 then
        ui.menu:Hide()
        return
    end
    ui.menu:Open(entries, anchor, SlotDock(slot))
end

------------------------------------------------------------------------
-- Pictures
------------------------------------------------------------------------

-- Spell and macro icons, as ItemRack collects them (the API differs between clients).
local function CollectIcons(list)
    local ok = pcall(function()
        if _G.RefreshPlayerSpellIconInfo and _G.GetMacroIcons and _G.GetSpellorMacroIconInfo then
            _G.RefreshPlayerSpellIconInfo()
            for i = 1, #_G.GetMacroIcons(_G.MACRO_ICON_FILENAMES) do
                local texture = _G.GetSpellorMacroIconInfo(i)
                if type(texture) == "number" then
                    list[#list + 1] = texture
                elseif texture then
                    list[#list + 1] = "Interface\\Icons\\" .. texture
                end
            end
        elseif _G.IconDataProviderMixin and _G.CreateAndInitFromMixin and _G.IconDataProviderExtraType then
            local provider = _G.CreateAndInitFromMixin(_G.IconDataProviderMixin, _G.IconDataProviderExtraType.Spell)
            if provider then
                for i = 1, provider:GetNumIcons() do list[#list + 1] = provider:GetIconByIndex(i) end
                provider:Release()
            end
        end
    end)
    return ok
end

-- The first 20 pictures show the item of each slot (ammo first), then two banners, then the icons.
local function BuildIcons()
    icons = {}
    for i = 1, 20 do icons[i] = QUESTION end
    icons[21] = "Interface\\Icons\\INV_Banner_02"
    icons[22] = "Interface\\Icons\\INV_Banner_03"
    CollectIcons(icons)
end

local function RefreshSlotIcons()
    local ok, _, ammo = pcall(GetInventorySlotInfo, "AmmoSlot")
    icons[1] = ok and type(ammo) == "string" and ammo or QUESTION
    for slot = 1, 19 do
        icons[slot + 1] = ItemIcon(slot) or SI.SlotTexture(slot) or QUESTION
    end
end

local function RefreshIconGrid()
    local scroll = ui.iconScroll
    FauxScrollFrame_Update(scroll, math.ceil(#icons / ICON_COLUMNS), ICON_ROWS, ICON_SIZE)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i, button in ipairs(ui.icons) do
        local texture = icons[offset * ICON_COLUMNS + i]
        if texture then
            button.icon:SetTexture(texture)
            button:Show()
            if texture == selectedIcon then button:LockHighlight() else button:UnlockHighlight() end
        else
            button:Hide()
        end
    end
end

------------------------------------------------------------------------
-- List of sets (the "Choose a set:" panel)
------------------------------------------------------------------------

local function Escapable(name, add)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
    if add then tinsert(UISpecialFrames, name) end
end

local function CopyState()
    local state = { selection = {}, choice = {}, icon = selectedIcon, set = selectedSet, name = ui.name:GetText() }
    for slot in pairs(selection) do state.selection[slot] = true end
    for slot, item in pairs(choice) do state.choice[slot] = item end
    return state
end

local function RestoreState(state)
    for slot in pairs(selection) do selection[slot] = nil end
    for slot in pairs(choice) do choice[slot] = nil end
    for slot in pairs(state.selection) do selection[slot] = true end
    for slot, item in pairs(state.choice) do choice[slot] = item end
    selectedIcon, selectedSet = state.icon, state.set
    ui.name:SetText(state.name)
end

-- Shows what a set contains while the mouse is over it in the list.
local function PreviewSet(id)
    local set = SI.db.sets[id]
    if not set then return end
    for slot in pairs(selection) do selection[slot] = nil end
    for slot in pairs(choice) do choice[slot] = nil end
    for slot, item in pairs(set.slots) do
        selection[slot] = true
        choice[slot] = { id = item.id, link = item.link, icon = ItemTexture(item.id) }
    end
    selectedIcon = set.icon
    SI.RefreshWindow()
end

local function RefreshSetList()
    local ids = SI.SortedSetIds()
    FauxScrollFrame_Update(ui.listScroll, #ids, LIST_ROWS, LIST_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(ui.listScroll)
    for i, row in ipairs(ui.rows) do
        local id = ids[offset + i]
        local set = id and SI.db.sets[id]
        row.setId = id
        if set then
            row.name:SetText(set.name)
            row.info:SetText(set.key and UI.KeyText(set.key) or "")
            row.icon:SetTexture(SI.SetIcon(set))
            row:Show()
        else
            row:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------

local function BuildNameBox(sub)
    local right
    ui.name, right = UI.NameField(sub, "Choose a name and icon:", "ShowItemsSetsName", SI.MAX_NAME)
    ui.drop = UI.SmallButton(sub, 18, { 0.375, 0.5, 0.125, 0.25 }, { 0.5, 0.625, 0.125, 0.25 }, "ShowItemsSetsDrop")
    ui.drop:SetPoint("TOPRIGHT", right, "TOPRIGHT", -20, -22)
    ui.drop:SetScript("OnClick", function() ui.picker:Show() end)
    UI.Tip(ui.drop, "Choose a set", "Shows the saved sets.")
end
local function BuildIconBox(sub)
    ui.iconBox = UI.Panel(sub, 178, 148, "icons")
    ui.iconBox:SetPoint("TOP", 0, -72)
    ui.icons = {}
    for i = 1, ICON_ROWS * ICON_COLUMNS do
        local b = CreateFrame("Button", "ShowItemsSetsIcon" .. i, ui.iconBox)
        b:SetSize(ICON_SIZE, ICON_SIZE)
        b.index = i
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(ICON_PICTURE, ICON_PICTURE)
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b:SetHighlightTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
        local col, row = (i - 1) % ICON_COLUMNS, math.floor((i - 1) / ICON_COLUMNS)
        -- the grid and the scroll bar are centered in the box
        b:SetPoint("TOPLEFT", 12 + col * ICON_SIZE, -10 - row * ICON_SIZE)
        b:SetScript("OnClick", function(self)
            local texture = icons[self.index + FauxScrollFrame_GetOffset(ui.iconScroll) * ICON_COLUMNS]
            if texture then selectedIcon = texture end
            SI.RefreshWindow()
        end)
        ui.icons[i] = b
    end
    ui.iconScroll = CreateFrame("ScrollFrame", "ShowItemsSetsIconScrollFrame", ui.iconBox, "FauxScrollFrameTemplate")
    ui.iconScroll:SetPoint("TOPLEFT", ui.icons[1], 0, -2)
    ui.iconScroll:SetPoint("BOTTOMRIGHT", ui.icons[#ui.icons], -2, 1)
    ui.iconScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ICON_SIZE, SI.RefreshWindow)
    end)
end

local function BuildButtons(sub)
    local function Button(text, name)
        return UI.Button(sub, 55, 28, text, name)
    end
    ui.save = Button("Save", "ShowItemsSetsSave")
    ui.save:SetPoint("TOPRIGHT", ui.iconBox, "BOTTOMRIGHT", -4, -2)
    ui.save:SetScript("OnClick", SaveFromEditBox)
    UI.Tip(ui.save, "Save Set", "Saves the selected slots with their items under this name and with the chosen icon. A set with the same name is replaced.")

    ui.bind = Button("Bind Key", "ShowItemsSetsBind")
    ui.bind:SetPoint("TOPRIGHT", ui.save, "BOTTOMRIGHT", 0, -4)
    ui.bind:SetScript("OnClick", function()
        local id = selectedSet
        local set = CurrentSet()
        if not set then return end
        SI.BeginKeyCapture(set.name, set.key,
            function(key) SI.SetSetBinding(id, key) end,
            function() SI.SetSetBinding(id, nil) end)
    end)
    UI.Tip(ui.bind, "Bind Key to Set", "This will let you bind a key or key combination to equip a set. In combat the key swaps weapons only.")

    ui.delete = Button("Delete", "ShowItemsSetsDelete")
    ui.delete:SetPoint("TOPRIGHT", ui.bind, "TOPLEFT", -4, 0)
    ui.delete:SetScript("OnClick", function()
        local id = selectedSet
        if not CurrentSet() then return end
        UI.Confirm("Delete this set?", function()
            SI.DeleteSet(id)
            if selectedSet == id then selectedSet = nil end
            SI.RefreshWindow()
        end)
    end)
    UI.Tip(ui.delete, "Delete Set", "Deletes the selected set and its key after a confirmation.")

    ui.equip = Button("Equip", "ShowItemsSetsEquip")
    ui.equip:SetPoint("TOPRIGHT", ui.save, "TOPLEFT", -4, 0)
    ui.equip:SetScript("OnClick", function()
        local set = CurrentSet()
        if set then SI.EquipSet(set) end
    end)
    UI.Tip(ui.equip, "Equip Set", "Equips the selected set from your bags. Not available in combat.")

    -- the picture of the set
    ui.current = CreateFrame("Button", "ShowItemsSetsCurrent", sub)
    SI.SkinButton(ui.current, 36)
    ui.current:EnableMouse(false)
    ui.current:SetPoint("TOPLEFT", ui.iconBox, "BOTTOMLEFT", 8, -4)
end

local function BuildPicker(sub, dropdown)
    ui.picker = UI.Panel(sub, 194, 282, nil, "ShowItemsSetPicker")
    ui.picker:SetAllPoints(sub)
    ui.picker:SetFrameLevel(sub:GetFrameLevel() + 20)
    ui.picker:EnableMouse(true)
    local label = ui.picker:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 20, -8)
    label:SetText("Choose a set:")
    local inner = UI.Panel(ui.picker, 178, 256, "icons")
    inner:SetPoint("TOP", 0, -20)
    ui.rows = {}
    for i = 1, LIST_ROWS do
        local row = UI.Row(inner, 140, LIST_ROW_HEIGHT, -8 - (i - 1) * LIST_ROW_HEIGHT, function(self)
            if not self.setId then return end
            SelectSet(self.setId)
            held = nil
            ui.picker:Hide()
            SI.RefreshWindow()
        end)
        row.rowType = "set"
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("TOPLEFT", 1, -1)
        row.info:ClearAllPoints()
        row.info:SetPoint("TOPRIGHT", -1, -1)
        row.info:SetSize(50, 22)
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT")
        row.name:SetPoint("BOTTOMRIGHT", row.info, "BOTTOMLEFT")
        row.name:SetWordWrap(false)
        row:HookScript("OnEnter", function(self)
            if self.setId then PreviewSet(self.setId) end
        end)
        ui.rows[i] = row
    end
    local close = UI.SmallButton(inner, 18, { 0.375, 0.5, 0.25, 0.375 }, { 0.5, 0.625, 0.25, 0.375 })
    close:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT")
    close:SetScript("OnClick", function() ui.picker:Hide() end)
    ui.listScroll = CreateFrame("ScrollFrame", "ShowItemsSetPickerScrollFrame", inner, "FauxScrollFrameTemplate")
    ui.listScroll:SetPoint("TOPLEFT", ui.rows[2], 0, 4)
    ui.listScroll:SetPoint("BOTTOMRIGHT", ui.rows[LIST_ROWS], -2, 1)
    ui.listScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, LIST_ROW_HEIGHT, SI.RefreshWindow)
    end)
    -- Escape closes the list and leaves the window open
    ui.picker:SetScript("OnShow", function()
        Escapable("ShowItemsSetPicker", true)
        Escapable("ShowItemsOptions", false)
        held = CopyState()
        SI.RefreshWindow()
    end)
    ui.picker:SetScript("OnHide", function()
        Escapable("ShowItemsSetPicker", false)
        Escapable("ShowItemsOptions", true)
        -- closing the list without picking a set puts back what was there
        if held then RestoreState(held) end
        held = nil
        SI.RefreshWindow()
    end)
    ui.picker:Hide()
end

local function Build(sub)
    BuildNameBox(sub)
    BuildIconBox(sub)
    BuildButtons(sub)
    BuildPicker(sub, ui.drop)
    ui.menu = SI.NewGridMenu("ShowItemsSetsMenu", { hover = true })
    sub:SetScript("OnHide", function()
        ui.name:ClearFocus()
        ui.menu:Hide()
    end)
end

local function Refresh()
    local db = SI.db
    if selectedSet and not db.sets[selectedSet] then selectedSet = nil end
    if not icons then BuildIcons() end
    RefreshSlotIcons()
    RefreshIconGrid()
    ui.current.icon:SetTexture(selectedIcon or AutoIcon())
    if ui.picker:IsShown() then RefreshSetList() end
end

local function ToggleAll()
    local state = not selection[1]
    for slot = 1, 19 do
        selection[slot] = state or nil
        if not state then choice[slot] = nil end
    end
end

SI.RegisterTab(2, "Sets", {
    build = Build,
    refresh = Refresh,
    -- selected slots are bright, the others are dimmed
    slotState = function(slot) return selection[slot] and "on" or "off" end,
    slotClick = function(slot)
        selection[slot] = (not selection[slot]) or nil
        if not selection[slot] then choice[slot] = nil end
    end,
    slotAll = ToggleAll,
    slotHover = function(slot, button) OpenSlotMenu(slot, button, PickItem) end,
    slotIcon = function(slot) return choice[slot] and choice[slot].icon end,
    slotLink = function(slot) return choice[slot] and choice[slot].link end,
    slotTip = function(slot)
        return selection[slot] and "Part of the set. Click to remove." or "Click to add to the set."
    end,
})