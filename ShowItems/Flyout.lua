local _, SI = ...

local floor, min, max = math.floor, math.min, math.max

-- Menu opened by right-clicking a tracking window:
-- lock / track-untrack / resize buttons on top, below them either the items from the
-- bags that fit the slot, or (eye mode) all slots to track or untrack.

local ICON, GAP, PAD, HEADER, MAX_COLUMNS, MAX_ITEMS = 36, 4, 10, 34, 8, 64
local HEAD_BUTTON = 24

local fly = CreateFrame("Frame", "ShowItemsFlyout", UIParent, "BackdropTemplate")
fly:SetFrameStrata("FULLSCREEN_DIALOG")
fly:SetClampedToScreen(true)
SI.StyleDark(fly)
fly:Hide()
fly.view = "items"

------------------------------------------------------------------------
-- Header buttons: [resize] [eye] [padlock]
------------------------------------------------------------------------

local function HeaderButton()
    local button = CreateFrame("Button", nil, fly)
    SI.SkinButton(button, HEAD_BUTTON)
    local active = button:CreateTexture(nil, "OVERLAY")
    active:SetAllPoints()
    active:SetColorTexture(1, 0.82, 0, 0.3)
    active:Hide()
    button.active = active
    return button
end

-- Diagonal resize arrows. Uses the first texture this client actually has.
local function ChooseSizeIcon()
    local candidates = {
        "Interface\\Cursor\\UI-Cursor-SizeRight",
        "Interface\\Buttons\\UI-Panel-BiggerButton-Up",
    }
    if _G.GetFileIDFromPath then
        for _, path in ipairs(candidates) do
            if _G.GetFileIDFromPath(path) then return path end
        end
    end
    return "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
end

-- Minimal gold eye: first atlas or file this client has.
local function SetEyeIcon(texture)
    local atlases = { "socialqueuing-icon-eye", "GM-icon-visible" }
    local atlasInfo = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    if atlasInfo then
        for _, name in ipairs(atlases) do
            if atlasInfo(name) then
                texture:SetAtlas(name, false)
                return
            end
        end
    end
    local files = { "Interface\\Icons\\INV_Misc_Eye_01", "Interface\\Icons\\Ability_Hunter_EagleEye" }
    local chosen = files[1]
    if _G.GetFileIDFromPath then
        for _, path in ipairs(files) do
            if _G.GetFileIDFromPath(path) then
                chosen = path
                break
            end
        end
    end
    texture:SetTexture(chosen)
end

local resizeButton = HeaderButton()
resizeButton.icon:SetTexture(ChooseSizeIcon())
resizeButton.icon:SetTexCoord(0, 1, 0, 1)
local eyeButton = HeaderButton()
SetEyeIcon(eyeButton.icon)
-- Padlock: the closed (locked) and open (unlocked) padlock of the ItemRack button sheet, drawn on
-- its dark plate like the other header buttons. ShowItemsLock.tga holds both (left = closed). The
-- open one is the closed one with the shackle raised and its right leg free (GPL-3.0, from ItemRack).
local lockButton = CreateFrame("Button", nil, fly)
lockButton:SetSize(HEAD_BUTTON, HEAD_BUTTON)
lockButton.isPadlock = true
do
    local face = lockButton:CreateTexture(nil, "ARTWORK")
    face:SetAllPoints()
    face:SetTexture("Interface\\AddOns\\ShowItems\\Textures\\ShowItemsLock")
    local hover = lockButton:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface\\AddOns\\ShowItems\\Textures\\ItemRackButtons")
    hover:SetTexCoord(0.25, 0.375, 0, 0.125)
    hover:SetAllPoints()
    hover:SetBlendMode("ADD")
    function lockButton.SetLocked(_, locked)
        if locked then face:SetTexCoord(0, 0.5, 0, 1) else face:SetTexCoord(0.5, 1, 0, 1) end
    end
    lockButton:SetLocked(false)
end
lockButton:SetPoint("TOPRIGHT", -PAD, -PAD)
eyeButton:SetPoint("RIGHT", lockButton, "LEFT", -GAP, 0)
resizeButton:SetPoint("RIGHT", eyeButton, "LEFT", -GAP, 0)

local function Tip(button, title, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
Tip(lockButton, "Lock position", "Locked windows cannot be dragged. Click again to unlock.")
Tip(eyeButton, "Track / Untrack", "Shows all slots. Click a slot to track or untrack it. Click the eye again to return to the item list.")
Tip(resizeButton, "Resize", "Shows a triangle at the bottom-right of this group of windows. Drag it to resize them. Click again to fix the size.")

lockButton:SetScript("OnClick", function()
    SI.SetLocked(not SI.db.locked)
end)

resizeButton:SetScript("OnClick", function()
    if InCombatLockdown() then
        SI.Print("resizing is not available in combat")
        return
    end
    if SI.IsResizeActiveFor(fly.slot) then SI.SetResizeMode(nil) else SI.SetResizeMode(fly.slot) end
end)

function SI.RefreshFlyout()
    local locked = SI.db.locked
    lockButton:SetLocked(locked)
    resizeButton.active:SetShown(fly.slot ~= nil and SI.IsResizeActiveFor(fly.slot))
    eyeButton.active:SetShown(fly.view == "slots")
end

------------------------------------------------------------------------
-- Bag access (works with C_Container and the legacy globals)
------------------------------------------------------------------------

local CC = _G.C_Container

function SI.NumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    if _G.GetContainerNumSlots then return _G.GetContainerNumSlots(bag) or 0 end
    return 0
end
local NumSlots = SI.NumSlots

function SI.BagItem(bag, index)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, index)
        if info then return info.hyperlink, info.itemID, info.iconFileID, info.stackCount end
    elseif _G.GetContainerItemInfo then
        local icon, count, _, _, _, _, link = _G.GetContainerItemInfo(bag, index)
        if link then
            local id = _G.GetContainerItemID and _G.GetContainerItemID(bag, index)
            return link, id, icon, count
        end
    end
end

local BagItem = SI.BagItem

function SI.EquipLocation(link, id)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if not getInstant then return nil end
    local _, _, _, loc = getInstant(id or link)
    return loc
end
local EquipLocation = SI.EquipLocation

-- Items in the player's bags (never the bank) that fit the slot.
function SI.ScanBags(slot)
    local def = SI.SLOTS[slot]
    local items = {}
    if not def then return items end
    local canDualWield = not _G.CanDualWield or _G.CanDualWield()
    local lastBag = _G.NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for index = 1, NumSlots(bag) do
            local link, id, icon, count = BagItem(bag, index)
            if link then
                local loc = EquipLocation(link, id)
                if loc and def.loc[loc] and not (slot == 17 and loc == "INVTYPE_WEAPON" and not canDualWield) then
                    items[#items + 1] = { bag = bag, index = index, id = id, link = link, icon = icon, count = count }
                    if #items >= MAX_ITEMS then return items end
                end
            end
        end
    end
    return items
end

-- item: { link, bag, index }. Equips it into the inventory slot.
function SI.EquipFromBag(item, slot)
    local equip = (C_Item and C_Item.EquipItemByName) or _G.EquipItemByName
    if equip then
        equip(item.link, slot)
        return
    end
    -- fallback: swap through the cursor
    local pickupBag = (CC and CC.PickupContainerItem) or _G.PickupContainerItem
    local pickupSlot = _G.PickupInventoryItem or (C_Item and C_Item.PickupInventoryItem)
    if not pickupBag or not pickupSlot then return end
    pickupBag(item.bag, item.index)
    pickupSlot(slot)
    if CursorHasItem() then pickupBag(item.bag, item.index) end
end
local EquipFromBag = SI.EquipFromBag

------------------------------------------------------------------------
-- Equip queue (as in ItemRack): an item picked in combat is equipped when combat ends.
-- Picking the queued item again takes it out of the queue.
------------------------------------------------------------------------

local equipQueue = {} -- [slot] = { id, link, icon }
local QUEUE_STEP = 0.3 -- seconds between two queued swaps, so the bags are up to date for the next one

local function SlotLabel(slot)
    return "Slot " .. slot .. " (" .. SI.SLOTS[slot].name .. ")"
end

function SI.QueuedItem(slot)
    return equipQueue[slot]
end

-- Equips the bag item now, or queues it when the player is in combat.
function SI.EquipOrQueue(item, slot)
    if not InCombatLockdown() then
        equipQueue[slot] = nil
        SI.RefreshQueue(slot)
        EquipFromBag(item, slot)
        return
    end
    local queued = equipQueue[slot]
    if queued and queued.id == item.id then
        equipQueue[slot] = nil
        SI.Print(SlotLabel(slot) .. ": removed from the queue.")
    else
        -- the item moves: it leaves the queue of any other slot, unless the bags hold another copy for it
        local copies = 0
        for _, bagItem in ipairs(SI.ScanBags(slot)) do
            if bagItem.id == item.id then copies = copies + 1 end
        end
        local others = {}
        for otherSlot, entry in pairs(equipQueue) do
            if otherSlot ~= slot and entry.id == item.id then others[#others + 1] = otherSlot end
        end
        table.sort(others)
        for i = 1, #others do
            if #others - i + 1 >= copies then
                equipQueue[others[i]] = nil
                SI.RefreshQueue(others[i])
                SI.Print(SlotLabel(others[i]) .. ": removed from the queue, the item moved to slot " .. slot .. ".")
            end
        end
        equipQueue[slot] = { id = item.id, link = item.link, icon = item.icon }
        SI.Print(SlotLabel(slot) .. ": queued, it will be equipped after combat.")
    end
    SI.RefreshQueue(slot)
end

local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

local processing = false

local function ProcessQueue()
    if InCombatLockdown() then
        processing = false
        return
    end
    local slot
    for s in pairs(equipQueue) do
        if not slot or s < slot then slot = s end
    end
    if not slot then
        processing = false
        return
    end
    local queued = equipQueue[slot]
    equipQueue[slot] = nil
    local found
    for _, item in ipairs(SI.ScanBags(slot)) do
        if item.id == queued.id then
            found = item
            break
        end
    end
    if found then
        EquipFromBag(found, slot)
    else
        SI.Print(SlotLabel(slot) .. ": the queued item is no longer in the bags.")
    end
    SI.RefreshQueue(slot)
    After(QUEUE_STEP, ProcessQueue)
end

SI.On("PLAYER_REGEN_ENABLED", function()
    if processing or next(equipQueue) == nil then return end
    processing = true
    ProcessQueue()
end)

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------

local itemButtons, slotButtons = {}, {}

local emptyText = fly:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
emptyText:SetText("No matching items in bags")

local function GetItemButton(i)
    local b = itemButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, fly)
    SI.SkinButton(b, ICON)
    b:RegisterForClicks("LeftButtonUp")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetBagItem, GameTooltip, self.item.bag, self.item.index) then
            GameTooltip:SetHyperlink(self.item.link)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        local slot = fly.slot
        fly:Hide()
        if slot then SI.EquipOrQueue(self.item, slot) end
    end)
    itemButtons[i] = b
    return b
end

local ShowSlotsView

local function GetSlotButton(slot)
    local b = slotButtons[slot]
    if b then return b end
    b = CreateFrame("Button", nil, fly)
    SI.SkinButton(b, ICON)
    b:RegisterForClicks("LeftButtonUp")
    b.slot = slot
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SI.SLOTS[self.slot].name, 1, 0.82, 0)
        if SI.IsTracked(self.slot) then
            GameTooltip:AddLine("Tracked. Click to untrack.", 1, 1, 1)
        else
            GameTooltip:AddLine("Not tracked. Click to track.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if SI.IsTracked(self.slot) then SI.Untrack({ self.slot }) else SI.Track({ self.slot }) end
        -- keep the menu anchored to a window that still exists
        if not SI.IsTracked(fly.slot) then
            fly.slot = nil
            for _, s in ipairs(SI.SLOT_ORDER) do
                if SI.IsTracked(s) then
                    fly.slot = s
                    break
                end
            end
            if not fly.slot then
                fly:Hide()
                return
            end
        end
        ShowSlotsView()
    end)
    slotButtons[slot] = b
    return b
end

local function HideContent()
    for i = 1, #itemButtons do itemButtons[i]:Hide() end
    for _, b in pairs(slotButtons) do b:Hide() end
    emptyText:Hide()
end

-- The menu sits above the row of windows, its left edge on the left edge of the window or group,
-- so it grows to the right and never covers the neighbors. It goes below the row when there is no room above.
local function PlaceFlyout(slot, height)
    local left, _, top, bottom = SI.GroupBounds(slot)
    if not left then return end
    fly:ClearAllPoints()
    if top + 4 + height <= UIParent:GetHeight() then
        fly:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, top + 4)
    else
        fly:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom - 4)
    end
end

local function GridPosition(button, index, columns)
    local col, row = (index - 1) % columns, floor((index - 1) / columns)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", fly, "TOPLEFT", PAD + col * (ICON + GAP), -(PAD + HEADER + row * (ICON + GAP)))
    button:Show()
end

local function ShowItemsView()
    local items = SI.ScanBags(fly.slot)
    HideContent()
    local columns = min(MAX_COLUMNS, max(#items, 4))
    local width = PAD * 2 + columns * ICON + (columns - 1) * GAP
    local gridHeight
    if #items == 0 then
        gridHeight = 16
        emptyText:ClearAllPoints()
        emptyText:SetPoint("TOPLEFT", fly, "TOPLEFT", PAD + 2, -(PAD + HEADER + 2))
        emptyText:Show()
    else
        local rows = math.ceil(#items / columns)
        gridHeight = rows * ICON + (rows - 1) * GAP
    end
    for i, item in ipairs(items) do
        local b = GetItemButton(i)
        b.item = item
        b.icon:SetTexture(item.icon)
        if item.count and item.count > 1 then b.count:SetText(item.count) else b.count:SetText("") end
        GridPosition(b, i, columns)
    end
    return width, PAD * 2 + HEADER + gridHeight
end

local function ShowSlotsViewContent()
    HideContent()
    local columns = MAX_COLUMNS
    for i, slot in ipairs(SI.SLOT_ORDER) do
        local b = GetSlotButton(slot)
        local texture = GetInventoryItemTexture("player", slot) or SI.SlotTexture(slot)
        b.icon:SetTexture(texture)
        if SI.IsTracked(slot) then
            b.icon:SetDesaturated(false)
            b.icon:SetAlpha(1)
            b.border:SetVertexColor(1, 0.82, 0)
        else
            b.icon:SetDesaturated(true)
            b.icon:SetAlpha(0.35)
            b.border:SetVertexColor(0.6, 0.6, 0.6)
        end
        GridPosition(b, i, columns)
    end
    local rows = math.ceil(#SI.SLOT_ORDER / columns)
    return PAD * 2 + columns * ICON + (columns - 1) * GAP, PAD * 2 + HEADER + rows * ICON + (rows - 1) * GAP
end

local function Relayout()
    local width, height
    if fly.view == "slots" then width, height = ShowSlotsViewContent() else width, height = ShowItemsView() end
    fly:SetSize(width, height)
    PlaceFlyout(fly.slot, height)
    SI.RefreshFlyout()
end

ShowSlotsView = function()
    fly.view = "slots"
    Relayout()
end

eyeButton:SetScript("OnClick", function()
    fly.view = (fly.view == "slots") and "items" or "slots"
    Relayout()
end)

------------------------------------------------------------------------
-- Hover menu: the bag items that fit a slot, shown while the mouse is over its tracking window.
-- Only the items are listed (no header buttons), the menu is as big as the list is long and sits
-- above the row of windows (below it when there is no room), so it never covers a neighbor.
------------------------------------------------------------------------

local hoverMenu = SI.NewGridMenu("ShowItemsHoverMenu", { hover = true })
local hoverAnchor = CreateFrame("Frame", nil, UIParent)

function SI.HideHoverMenu()
    hoverMenu:Hide()
end

-- the tooltip of an icon goes with the menu
hoverMenu:HookScript("OnHide", function()
    for _, button in ipairs(hoverMenu.buttons) do
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end
end)

function SI.ShowHoverMenu(slot)
    local tracker, t = SI.frames[slot], SI.db.tracked[slot]
    if not tracker or not t or not SI.db.enabled or fly:IsShown() then
        hoverMenu:Hide()
        return
    end
    local entries = {}
    for _, item in ipairs(SI.ScanBags(slot)) do
        entries[#entries + 1] = {
            icon = item.icon, count = item.count,
            onClick = function()
                hoverMenu:Hide()
                SI.HideNameTip()
                GameTooltip:Hide()
                SI.EquipOrQueue(item, slot)
            end,
            -- the short tooltip (name and characteristics, no comparison) next to the icon
            onEnter = function(button)
                SI.ShowItemTip(button, {
                    side = "RIGHT",
                    above = hoverMenu,
                    fill = function(tip)
                        if not pcall(tip.SetBagItem, tip, item.bag, item.index) then
                            tip:SetHyperlink(item.link)
                        end
                    end,
                })
            end,
        }
    end
    if #entries == 0 then
        hoverMenu:Hide()
        return
    end
    -- the edge of the whole group, so a window stacked above or below is not covered
    local _, _, top, bottom = SI.GroupBounds(slot)
    hoverAnchor:SetSize(t.size, 1)
    hoverAnchor:ClearAllPoints()
    hoverAnchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", t.left, top)
    hoverMenu:Open(entries, hoverAnchor, "ABOVE")
    if top + hoverMenu:GetHeight() * hoverMenu:GetScale() > UIParent:GetHeight() then
        hoverAnchor:ClearAllPoints()
        hoverAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", t.left, bottom)
        hoverMenu:Open(entries, hoverAnchor, "BELOW")
    end
    -- the menu stays while the mouse is over the window itself
    hoverMenu.anchor = tracker
end

function SI.ShowFlyout(slot)
    if not SI.frames[slot] or not SI.db.enabled then return end
    hoverMenu:Hide()
    fly.slot = slot
    fly.view = "items"
    SI.HideContext()
    GameTooltip:Hide()
    Relayout()
    fly:Show()
end

SI.AutoClose(fly)

function SI.CloseMenus()
    SI.HideContext()
    if SI.HideSetMenu then SI.HideSetMenu() end
    hoverMenu:Hide()
    fly:Hide()
end
