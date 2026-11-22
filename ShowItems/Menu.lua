local _, SI = ...

local floor, min, max = math.floor, math.min, math.max

-- Same backdrop as the ItemRack menu (tooltip background and border).
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local WHITE = { 1, 1, 1 }
local GRAY = { 0.5, 0.5, 0.5 }

function SI.StyleFrame(f)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(1, 1, 1, 1)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end
local StyleFrame = SI.StyleFrame

-- Classic Blizzard gray menu (dialog background, thin tooltip border) for small popups.
local CLASSIC_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Dark gray classic Blizzard panel (the background of the main window) for the tracker menu.
local DARK_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function SI.StyleDark(f)
    f:SetBackdrop(DARK_BACKDROP)
    f:SetBackdropColor(1, 1, 1, 1)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

function SI.StyleClassic(f)
    f:SetBackdrop(CLASSIC_BACKDROP)
    f:SetBackdropColor(1, 1, 1, 1)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

-- Closes a popup when the mouse is pressed outside of it. Polls only while shown.
-- tick (optional) runs on every update while the popup is shown.
function SI.AutoClose(popup, extraInside, tick)
    local armed = false
    popup:HookScript("OnShow", function() armed = false end)
    popup:SetScript("OnUpdate", function(self)
        if tick then tick(self) end
        local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if not armed then
            if not down then armed = true end
            return
        end
        if down and not self:IsMouseOver() and not (extraInside and extraInside()) then
            self:Hide()
        end
    end)
end
local AutoClose = SI.AutoClose

-- Action-button look shared by the item list and the header buttons:
-- icon under a rounded UI-Quickslot2 border (same proportions the other addons here use).
function SI.SkinButton(b, size)
    b:SetSize(size, size)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    b.icon = b:CreateTexture(nil, "BORDER")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    b.border = b:CreateTexture(nil, "ARTWORK")
    b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.border:SetSize(size * 64 / 37, size * 64 / 37)
    b.border:SetPoint("CENTER", 0, -size / 37)
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
end

-- Round minimap-button look: the same textures and proportions as the ShowItems minimap button
-- (31 px, gold ring over a small round picture). size scales all parts.
function SI.SkinRound(b, size)
    local k = size / 31
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetSize(20 * k, 20 * k)
    b.bg:SetPoint("TOPLEFT", 7 * k, -5 * k)
    b.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(17 * k, 17 * k)
    b.icon:SetPoint("TOPLEFT", 7 * k, -6 * k)
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetSize(53 * k, 53 * k)
    b.border:SetPoint("TOPLEFT")
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
end

------------------------------------------------------------------------
-- Context menu on the character window: Track / Untrack
------------------------------------------------------------------------

-- Puts a popup (and its children) above every tooltip, so a menu opened over a slot is not
-- hidden under the item tooltip that is showing there.
function SI.RaiseAboveTooltips(f, children)
    f:SetFrameStrata("TOOLTIP")
    local level = 0
    for _, name in ipairs({ "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefTooltip" }) do
        local tip = _G[name]
        if tip then level = math.max(level, tip:GetFrameLevel() or 0) end
    end
    f:SetFrameLevel(level + 20)
    for _, child in ipairs(children or {}) do child:SetFrameLevel(level + 21) end
end

local selection = {}
local highlights = {}
local ctx = CreateFrame("Frame", "ShowItemsContextMenu", UIParent, "BackdropTemplate")
ctx:SetFrameStrata("TOOLTIP")
ctx:SetClampedToScreen(true)
SI.StyleClassic(ctx)
ctx:Hide()

-- Equal padding on all sides: PAD around the entries, TEXT_PAD inside an entry.
local PAD, TEXT_PAD, ENTRY_HEIGHT = 9, 8, 16
local SLOT_GAP = 6 -- space between the menu and the slot it belongs to

local function SelectedList()
    local list = {}
    for slot in pairs(selection) do list[#list + 1] = slot end
    table.sort(list)
    return list
end

local function UpdateHighlights()
    for slot, texture in pairs(highlights) do
        if selection[slot] and ctx:IsShown() then texture:Show() else texture:Hide() end
    end
end

local function ClearSelection()
    for slot in pairs(selection) do selection[slot] = nil end
    UpdateHighlights()
end

ctx:SetScript("OnHide", ClearSelection)

local function MakeEntry(label, y, action)
    local button = CreateFrame("Button", nil, ctx)
    button:SetPoint("TOPLEFT", PAD, y)
    button:SetPoint("TOPRIGHT", -PAD, y)
    button:SetHeight(ENTRY_HEIGHT)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("LEFT", TEXT_PAD, 0)
    button.text:SetText(label)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)
    button:SetScript("OnClick", function()
        local list = SelectedList()
        ctx:Hide()
        action(list)
    end)
    return button
end

local trackEntry = MakeEntry("Track", -PAD, function(list) SI.Track(list) end)
local untrackEntry = MakeEntry("Untrack", -PAD - ENTRY_HEIGHT, function(list) SI.Untrack(list) end)

-- The menu is as wide as its longest word plus the same padding on both sides.
do
    local textWidth = math.max(trackEntry.text:GetStringWidth() or 40, untrackEntry.text:GetStringWidth() or 40)
    ctx:SetSize(textWidth + 2 * TEXT_PAD + 2 * PAD, 2 * ENTRY_HEIGHT + 2 * PAD)
end

local function SetEntryColor(entry, color)
    entry.text:SetTextColor(color[1], color[2], color[3])
end

-- Active (white) entry shows what a click will do; the other one is gray.
local function RefreshContext()
    local anyTracked, anyUntracked = false, false
    for slot in pairs(selection) do
        if SI.IsTracked(slot) then anyTracked = true else anyUntracked = true end
    end
    SetEntryColor(trackEntry, anyUntracked and WHITE or GRAY)
    SetEntryColor(untrackEntry, anyTracked and WHITE or GRAY)
end

local slotButtons = {}

-- Slot selection uses right click with Ctrl and nothing else. In this client the modified clicks are
-- CHATLINK = Shift+left, DRESSUP = Ctrl+left, SOCKETITEM = none, SHOWITEMFLYOUT and SELFCAST = Alt,
-- COMPAREITEMS = Shift (checked in game with GetModifiedClick), so right click with Ctrl is free.
-- Ctrl+right click selects one slot ("single"), Ctrl+Shift+right click adds slots to the selection ("multi").
local function SelectMode()
    if not IsControlKeyDown() or IsAltKeyDown() then return nil end
    return IsShiftKeyDown() and "multi" or "single"
end

-- While Ctrl is held, pressing the mouse on a character window slot keeps the menu
-- (and the selection) open so another slot can be picked.
local function SelectOnSlot()
    if not SelectMode() then return false end
    for _, button in pairs(slotButtons) do
        if button:IsMouseOver() then return true end
    end
    return false
end

-- The menu is attached to the right of the slot that was clicked last, centered on it.
-- It stays there however the cursor moves, and jumps to the next slot that is clicked.
-- When there is no room on the right it goes to the left of the slot instead.
local function PlaceContext(slotButton)
    ctx:ClearAllPoints()
    local right = slotButton:GetRight()
    local fits = true
    if right then
        local scale = ctx:GetEffectiveScale()
        local menuRight = right * slotButton:GetEffectiveScale() / scale + SLOT_GAP + ctx:GetWidth()
        fits = menuRight <= UIParent:GetWidth() * UIParent:GetEffectiveScale() / scale
    end
    if fits then
        ctx:SetPoint("LEFT", slotButton, "RIGHT", SLOT_GAP, 0)
    else
        ctx:SetPoint("RIGHT", slotButton, "LEFT", -SLOT_GAP, 0)
    end
end

AutoClose(ctx, SelectOnSlot)

local function ShowContext(slotButton)
    RefreshContext()
    PlaceContext(slotButton)
    SI.RaiseAboveTooltips(ctx, { trackEntry, untrackEntry })
    ctx:Show()
    UpdateHighlights()
end

function SI.HideContext()
    ctx:Hide()
end

function SI.IsContextShown()
    return ctx:IsShown()
end

local function GetHighlight(slotButton)
    local texture = slotButton.ShowItemsHighlight
    if not texture then
        texture = slotButton:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetColorTexture(1, 0.82, 0, 0.35)
        texture:Hide()
        slotButton.ShowItemsHighlight = texture
    end
    return texture
end

-- Only Ctrl+right click and Ctrl+Shift+right click select slots, so the client's own clicks (picking
-- up or using an item) are left alone. Ctrl+right click selects that one slot (a second click on
-- it clears the selection); Ctrl+Shift+right click adds or removes slots, and the menu moves to the
-- last slot clicked. The client takes any
-- click with a modifier key held to its modified-click handler, which does not use the item
-- and does not pick it up (CHATLINK and DRESSUP are bound to the left button only). The
-- client's handler cannot be cancelled from here without tainting it. If an item still ended
-- up on the cursor it is put back (cursorBefore is recorded in PreClick).
local cursorBefore = false

local function OnSlotPreClick()
    cursorBefore = CursorHasItem and CursorHasItem() or false
end

local function OnSlotClick(self, button)
    local mode = SelectMode()
    if button ~= "RightButton" or not mode then return end
    -- the Track / Untrack menu replaces the menu of bag items
    if SI.HideCharacterMenu then SI.HideCharacterMenu() end
    if not cursorBefore and CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() end
    local db = SI.db
    if not db or not db.enabled then return end
    local slot = self:GetID()
    if not SI.SLOTS[slot] then return end
    if mode == "single" then
        local count = 0
        for _ in pairs(selection) do count = count + 1 end
        local alone = selection[slot] and count == 1
        for s in pairs(selection) do selection[s] = nil end
        if not alone then selection[slot] = true end
    else
        selection[slot] = (not selection[slot]) or nil
    end
    if not next(selection) then
        ctx:Hide()
        return
    end
    highlights[slot] = GetHighlight(self)
    ShowContext(self)
end

local hookedButtons = {}
local characterFrameHooked = false

local function HookCharacterSlots()
    for slot, def in pairs(SI.SLOTS) do
        local button = _G[def.frame]
        if button and not hookedButtons[slot] then
            hookedButtons[slot] = true
            slotButtons[slot] = button
            highlights[slot] = GetHighlight(button)
            button:HookScript("PreClick", OnSlotPreClick)
            button:HookScript("OnClick", OnSlotClick)
            if SI.HookCharacterMenu then SI.HookCharacterMenu(button) end
        end
    end
    if CharacterFrame and not characterFrameHooked then
        characterFrameHooked = true
        CharacterFrame:HookScript("OnHide", function() ctx:Hide() end)
        if SI.HookCharacterMenuFrame then SI.HookCharacterMenuFrame(CharacterFrame) end
    end
end

SI.OnInit(HookCharacterSlots)
SI.On("PLAYER_ENTERING_WORLD", HookCharacterSlots)
SI.On("ADDON_LOADED", function()
    if not characterFrameHooked then HookCharacterSlots() end
end)


------------------------------------------------------------------------
-- Grid menu: popup of icon buttons (the ItemRack menu). Used for the list of sets next to the
-- minimap button and for the bag items next to a slot of the sets tab.
-- Buttons are 36 px, 40 px apart, 8 px from the edge; more entries make more columns.
------------------------------------------------------------------------

local GRID_ICON, GRID_STEP, GRID_PAD = 36, 40, 8

-- Where the menu sits against the widget it belongs to and where its first button is.
-- corner: menu corner on the widget point; xdir/ydir: direction the buttons fill in.
-- horizontal: the buttons run outward from the widget (sideways) and wrap into rows, as in
-- the horizontal ItemRack menu; otherwise they fill rows first and the menu grows downward.
local DOCKS = {
    RIGHT = { corner = "TOPLEFT", point = "TOPRIGHT", x = 0, y = 8, xdir = 1, ydir = -1, horizontal = true },
    LEFT = { corner = "TOPRIGHT", point = "TOPLEFT", x = 0, y = 8, xdir = -1, ydir = -1, horizontal = true },
    DOWN = { corner = "TOPLEFT", point = "BOTTOMLEFT", x = -8, y = 0, xdir = 1, ydir = -1 },
    BELOW = { corner = "TOPRIGHT", point = "BOTTOMRIGHT", x = 8, y = 0, xdir = -1, ydir = -1 },
    ABOVE = { corner = "BOTTOMRIGHT", point = "TOPRIGHT", x = 8, y = 0, xdir = -1, ydir = 1 },
}

local function GridColumns(count)
    if count > 24 then return 5 end
    if count > 18 then return 4 end
    if count > 9 then return 3 end
    if count > 4 then return 2 end
    return 1
end

local function GridButton(menu, index)
    local b = menu.buttons[index]
    if b then return b end
    b = CreateFrame("Button", nil, menu)
    b:SetSize(menu.icon, menu.icon)
    if menu.round then SI.SkinRound(b, menu.icon) else SI.SkinButton(b, menu.icon) end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetFont("Fonts\\ARIALN.TTF", math.floor(12 * menu.icon / GRID_ICON + 0.5), "OUTLINE")
    b.label:SetPoint("BOTTOM", 0, 2)
    b.label:SetWidth(menu.icon)
    b.label:SetWordWrap(false)
    b:SetScript("OnClick", function(self, mouseButton)
        local entry = self.entry
        if entry and entry.onClick then entry.onClick(self, mouseButton) end
    end)
    b:SetScript("OnEnter", function(self)
        local entry = self.entry
        if entry and entry.onEnter then entry.onEnter(self) end
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        SI.HideNameTip()
    end)
    menu.buttons[index] = b
    return b
end

-- options.hover: close as soon as the mouse is over neither the menu nor the widget it belongs to.
-- Otherwise the menu closes when the mouse is pressed outside it (and outside the widget).
-- options.icon / options.step: button size and distance between buttons (36 and 40 by default).
-- options.scale: size of the menu relative to the widget it belongs to (default 1).
-- options.round: buttons look like minimap buttons (gold ring, round picture, no label on the button).
-- The menu is drawn above every tooltip.
function SI.NewGridMenu(name, options)
    options = options or {}
    local menu = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    menu:SetClampedToScreen(true)
    SI.StyleClassic(menu)
    menu.buttons = {}
    menu.icon = options.icon or GRID_ICON
    menu.step = options.step or GRID_STEP
    menu.relativeScale = options.scale or 1
    menu.round = options.round == true
    local function overAnchor()
        return menu.anchor and menu.anchor:IsMouseOver()
    end
    AutoClose(menu, overAnchor, options.hover and function(self)
        if self:IsShown() and not self:IsMouseOver() and not overAnchor() then self:Hide() end
    end or nil)
    menu:Hide()

    -- entries: { icon, label, count, onClick(button, mouseButton), onEnter(button), tint = { r, g, b } }
    -- dock: one of RIGHT, LEFT, DOWN, BELOW, ABOVE
    function menu.Open(self, entries, anchor, dock)
        local d = DOCKS[dock] or DOCKS.RIGHT
        self.anchor = anchor
        local count = #entries
        local columns = GridColumns(count)
        local rows = math.ceil(count / columns)
        if d.horizontal then
            -- sideways menu: GridColumns is the number of rows, the buttons run outward
            rows, columns = columns, math.ceil(count / columns)
        end
        local step = self.step
        for _, b in ipairs(self.buttons) do b:Hide() end
        for i, entry in ipairs(entries) do
            local b = GridButton(self, i)
            b.entry = entry
            b.icon:SetTexture(entry.icon)
            b.count:SetText(entry.count and entry.count > 1 and entry.count or "")
            b.label:SetText(not self.round and entry.label or "")
            b.border:SetVertexColor(entry.tint and entry.tint[1] or 1, entry.tint and entry.tint[2] or 1, entry.tint and entry.tint[3] or 1)
            local col, row
            if d.horizontal then
                col, row = math.floor((i - 1) / rows), (i - 1) % rows
            else
                col, row = (i - 1) % columns, math.floor((i - 1) / columns)
            end
            b:ClearAllPoints()
            b:SetPoint(d.corner, self, d.corner, d.xdir * (GRID_PAD + col * step), d.ydir * (GRID_PAD + row * step))
            b:Show()
        end
        -- the menu has the scale of the widget it belongs to (the settings window is scaled)
        self:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale() * self.relativeScale)
        self:SetSize(2 * GRID_PAD + (columns - 1) * step + self.icon, 2 * GRID_PAD + (rows - 1) * step + self.icon)
        self:ClearAllPoints()
        self:SetPoint(d.corner, anchor, d.point, d.x, d.y)
        SI.RaiseAboveTooltips(self, self.buttons)
        self:Show()
    end

    return menu
end

------------------------------------------------------------------------
-- Name tip: a small one-line tooltip with a name only (12 pt). It stands in for the full item
-- tooltip and its comparison tooltips where those would clutter the screen.
------------------------------------------------------------------------

local TIP_FONT_SIZE, TIP_PAD, TIP_GAP = 12, 8, 5

local nameTip = CreateFrame("Frame", "ShowItemsNameTip", UIParent, "BackdropTemplate")
nameTip:SetClampedToScreen(true)
nameTip:EnableMouse(false)
SI.StyleClassic(nameTip) -- the gray of the character window menu
nameTip.text = nameTip:CreateFontString(nil, "OVERLAY")
nameTip.text:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", TIP_FONT_SIZE, "")
nameTip.text:SetPoint("CENTER")
nameTip:Hide()

-- Puts a tip next to the widget it belongs to: side "RIGHT" (default, next to the widget, centered on it) or
-- "BELOW" (under the widget, its left edge on the left edge of the widget, with a small gap). The gaps are
-- measured in the pixels of the widget, whatever the scale of the tip is (the name tip has the scale of the
-- widget, the item tooltip has its own).
function SI.AnchorNextTo(tip, owner, side)
    local k = owner:GetEffectiveScale() / tip:GetEffectiveScale()
    tip:ClearAllPoints()
    if side == "BELOW" then
        tip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -TIP_GAP * k)
    else
        tip:SetPoint("LEFT", owner, "RIGHT", 4 * k, 0)
    end
end

-- owner: the widget the tip belongs to; side: "RIGHT" (default) or "BELOW" (see SI.AnchorNextTo)
function SI.ShowNameTip(owner, text, r, g, b, side)
    nameTip.text:SetText(text or "")
    nameTip.text:SetTextColor(r or 1, g or 1, b or 1)
    nameTip:SetSize((nameTip.text:GetStringWidth() or 60) + 2 * TIP_PAD, TIP_FONT_SIZE + 2 * TIP_PAD)
    nameTip:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    SI.AnchorNextTo(nameTip, owner, side)
    SI.RaiseAboveTooltips(nameTip, {})
    nameTip:Show()
end

function SI.HideNameTip()
    nameTip:Hide()
end

-- Name and quality color of an item link: name, r, g, b.
function SI.ItemNameColor(link)
    local name = type(link) == "string" and link:match("%[(.-)%]") or tostring(link)
    local getInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    local quality
    if getInfo then
        local ok, _, _, q = pcall(getInfo, link)
        if ok and type(q) == "number" then quality = q end
    end
    local color = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if color then return name, color.r, color.g, color.b end
    return name, 1, 1, 1
end
