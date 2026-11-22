local _, SI = ...

-- Main window in the style of the ItemRack options window: dark backdrop, tabs at the top right,
-- slot buttons in two columns and a row at the bottom, one content panel in the middle.
-- Tabs register themselves with SI.RegisterTab (Options.lua, Sets.lua, Profiles.lua).
-- Layout and the tab/button textures (Textures\) come from ItemRack (GPL-3.0).

local TEXTURES = "Interface\\AddOns\\ShowItems\\Textures\\"
local TABS = TEXTURES .. "ItemRackOptTabs"
local BUTTONS = TEXTURES .. "ItemRackButtons"

local max, min = math.max, math.min

local WIDTH, HEIGHT = 288, 348
local MIN_SCALE, MAX_SCALE = 1, 3
local SUB_WIDTH, SUB_HEIGHT = 194, 282
local SLOT_SIZE, TAB_WIDTH = 36, 46

local TAB_ORDER = { 2, 1, 3 } -- tab ids from left to right
local LEFT_COLUMN = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_COLUMN = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM_ROW = { { 16, -40 }, { 17, 0 }, { 18, 40 } }

local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true,
}
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local tabs = {} -- [id] = { id, label, build, refresh, slotState, slotClick, slotTip, button, frame }
local frame, bind
local active
local slotButtons = {}
local allButton

SI.UI = {}
local UI = SI.UI

------------------------------------------------------------------------
-- Shared widgets (same look as ItemRack)
------------------------------------------------------------------------

-- Vertical or horizontal gradient. The call signature differs between client versions.
function UI.Gradient(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    texture:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    if _G.CreateColor and pcall(texture.SetGradient, texture, orientation,
        _G.CreateColor(r1, g1, b1, a1), _G.CreateColor(r2, g2, b2, a2)) then
        return
    end
    if pcall(texture.SetGradient, texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2) then return end
    if texture.SetGradientAlpha and pcall(texture.SetGradientAlpha, texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2) then
        return
    end
    texture:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end

-- Panel with the tooltip border and a gray vertical gradient (ItemRackOptSubFrameTemplate).
-- flat: the darker gradient of the ItemRack list boxes; "icons": the gradient of the ItemRack
-- icon box and set list (gray at the bottom, black at the top).
function UI.Panel(parent, width, height, flat, name)
    local panel = CreateFrame("Frame", name, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    if flat == "icons" then
        UI.Gradient(bg, "VERTICAL", 0.25, 0.25, 0.25, 1, 0, 0, 0, 1)
    elseif flat then
        UI.Gradient(bg, "VERTICAL", 0, 0, 0, 1, 0.25, 0.25, 0.25, 1)
    else
        UI.Gradient(bg, "VERTICAL", 0.1, 0.1, 0.1, 0.5, 0.25, 0.25, 0.25, 1)
    end
    panel:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
    panel:SetBackdropBorderColor(0.3, 0.3, 0.3)
    return panel
end

-- Small square button with a picture from the ItemRack button sheet (ItemRackSmallButtonTemplate).
-- normal and pushed: { left, right, top, bottom } of the picture on the sheet.
function UI.SmallButton(parent, size, normal, pushed, name)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(size, size)
    local up = button:CreateTexture(nil, "ARTWORK")
    up:SetTexture(BUTTONS)
    up:SetTexCoord(normal[1], normal[2], normal[3], normal[4])
    button:SetNormalTexture(up)
    local down = button:CreateTexture(nil, "ARTWORK")
    down:SetTexture(BUTTONS)
    down:SetTexCoord(pushed[1], pushed[2], pushed[3], pushed[4])
    button:SetPushedTexture(down)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture(BUTTONS)
    hover:SetTexCoord(0.25, 0.375, 0, 0.125)
    hover:SetAllPoints()
    hover:SetBlendMode("ADD")
    return button
end

-- Standard red Blizzard button. Buttons are never disabled: a click without a valid
-- target explains what to do instead.
function UI.Button(parent, width, height, text, name)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 64, height or 20)
    button:SetNormalFontObject(_G.GameFontNormalSmall)
    button:SetHighlightFontObject(_G.GameFontHighlightSmall)
    button:SetDisabledFontObject(_G.GameFontDisableSmall)
    button:SetText(text)
    return button
end

-- Slider of the ItemRack options (ItemRackOptSliderTemplate): slider-bar backdrop, 32 px knob,
-- the lowest and highest value written on both sides of the bar. form: format of the values.
local SLIDER_BACKDROP = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    edgeSize = 8, tileSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

function UI.Slider(parent, name, low, high, step, form)
    local slider = CreateFrame("Slider", name, parent, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(96, 17)
    slider:SetHitRectInsets(0, 0, -5, -5)
    slider:SetBackdrop(SLIDER_BACKDROP)
    slider:SetBackdropBorderColor(0.3, 0.3, 0.3)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouse(true)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(32, 32)
    slider:SetThumbTexture(thumb)
    slider.form, slider.min, slider.max = form or "%s", low, high
    local lowText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lowText:SetPoint("RIGHT", slider, "LEFT", -2, 0)
    lowText:SetTextColor(0.65, 0.65, 0.65)
    lowText:SetText(string.format(slider.form, low))
    local highText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    highText:SetPoint("LEFT", slider, "RIGHT", 2, 0)
    highText:SetTextColor(0.65, 0.65, 0.65)
    highText:SetText(string.format(slider.form, high))
    return slider
end

-- Number field of the ItemRack options (ItemRackNumberEditBoxTemplate).
-- Set box.onEnter(text) and box.onCancel() to react to Enter and Escape.
function UI.NumberBox(parent, name)
    local FILE = "Interface\\ClassTrainerFrame\\UI-ClassTrainer-FilterBorder"
    local box = CreateFrame("EditBox", name, parent)
    box:SetSize(32, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(16)
    box:SetFontObject(_G.GameFontHighlightSmall)
    local left = box:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(FILE)
    left:SetSize(12, 29)
    left:SetPoint("TOPLEFT", -11, 2)
    left:SetTexCoord(0, 0.09375, 0, 1)
    local right = box:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(FILE)
    right:SetSize(12, 29)
    right:SetPoint("TOPRIGHT", 4, 2)
    right:SetTexCoord(0.90625, 1, 0, 1)
    local middle = box:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture(FILE)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    middle:SetTexCoord(0.09375, 0.90625, 0, 1)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self.onCancel then self.onCancel() end
    end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if self.onEnter then self.onEnter(self:GetText()) end
    end)
    return box
end

-- Standard check box (UICheckButtonTemplate), 24 px.
function UI.CheckBox(parent)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    return check
end
-- Small menu above the cursor: a question with Confirm and Cancel.
local confirm

local function ConfirmEntry(text, y, name, action)
    local button = CreateFrame("Button", name, confirm)
    button:SetPoint("TOPLEFT", 6, y)
    button:SetPoint("TOPRIGHT", -6, y)
    button:SetHeight(16)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("LEFT", 6, 0)
    button.text:SetText(text)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)
    button:SetScript("OnClick", action)
    return button
end

function UI.Confirm(question, onConfirm)
    if not confirm then
        confirm = CreateFrame("Frame", "ShowItemsConfirm", UIParent, "BackdropTemplate")
        confirm:SetFrameStrata("TOOLTIP")
        confirm:SetClampedToScreen(true)
        SI.StyleClassic(confirm)
        confirm.title = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        confirm.title:SetPoint("TOPLEFT", 12, -6)
        confirm.entries = {
            ConfirmEntry("Confirm", -22, "ShowItemsConfirmYes", function()
                local action = confirm.action
                confirm:Hide()
                if action then action() end
            end),
            ConfirmEntry("Cancel", -38, "ShowItemsConfirmNo", function() confirm:Hide() end),
        }
        SI.AutoClose(confirm)
        confirm:Hide()
    end
    confirm.action = onConfirm
    confirm.title:SetText(question)
    -- same padding on every side: 6 around the entries, 6 inside an entry
    local width = max(confirm.title:GetStringWidth() or 60, 50) + 24
    confirm:SetSize(width, 6 + 16 + 16 + 16 + 6)
    confirm:SetScale(frame and frame:GetScale() or 1)
    local x, y = GetCursorPosition()
    local scale = confirm:GetEffectiveScale()
    confirm:ClearAllPoints()
    confirm:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / scale, y / scale + 12)
    SI.RaiseAboveTooltips(confirm, confirm.entries)
    confirm:Show()
end

function UI.HideConfirm()
    if confirm then confirm:Hide() end
end

function UI.Tip(widget, title, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Name field of the ItemRack tabs: a label above a 132 x 20 edit box drawn inside the long
-- field frame of the character creation screen. Returns the edit box and the right piece of
-- the frame (a button can be anchored to it).
function UI.NameField(sub, text, name, letters)
    local label = sub:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 20, -8)
    label:SetText(text)
    local FILE = "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame"
    local left = sub:CreateTexture(nil, "ARTWORK")
    left:SetTexture(FILE)
    left:SetSize(25, 64)
    left:SetPoint("TOPLEFT", -7, -4)
    left:SetTexCoord(0, 0.1953125, 0, 1)
    local middle = sub:CreateTexture(nil, "ARTWORK")
    middle:SetTexture(FILE)
    middle:SetSize(156, 64)
    middle:SetPoint("LEFT", left, "RIGHT")
    middle:SetTexCoord(0.1953125, 0.8046875, 0, 1)
    local right = sub:CreateTexture(nil, "ARTWORK")
    right:SetTexture(FILE)
    right:SetSize(25, 64)
    right:SetPoint("LEFT", middle, "RIGHT")
    right:SetTexCoord(0.8046875, 1, 0, 1)
    local box = CreateFrame("EditBox", name, sub)
    box:SetSize(132, 20)
    box:SetPoint("TOPLEFT", label, "TOPLEFT", 2, -17)
    box:SetFontObject(_G.GameFontHighlight)
    box:SetAutoFocus(false)
    box:SetMaxLetters(letters or 30)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box, right
end
-- List row: name on the left, small gray text on the right, gold gradient on hover and selection.
function UI.Row(parent, width, height, y, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, height)
    row:SetPoint("TOPLEFT", 8, y)
    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    UI.Gradient(hover, "HORIZONTAL", 0.75, 0.63, 0.1, 0.5, 0.75, 0.75, 0.75, 1)
    hover:Hide()
    row.hover = hover
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    UI.Gradient(row.sel, "HORIZONTAL", 0.75, 0.63, 0.1, 0.5, 0.75, 0.75, 0.75, 0.6)
    row.sel:Hide()
    row.info = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.info:SetPoint("RIGHT", -3, 0)
    row.info:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 3, 0)
    row.name:SetPoint("RIGHT", row.info, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", onClick)
    row:Hide()
    return row
end

function UI.KeyText(key)
    if not key then return "Not bound" end
    if _G.GetBindingText then
        local ok, text = pcall(_G.GetBindingText, key)
        if ok and text then return text end
    end
    return key
end

------------------------------------------------------------------------
-- Key capture panel (ItemRackOptBindFrame)
------------------------------------------------------------------------

local function ModifierPrefix()
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
end

local function ApplyKey(key)
    local onKey = bind.onKey
    bind:Hide()
    if onKey then onKey(key) end
    SI.RefreshWindow()
end

local function BuildBind()
    bind = CreateFrame("Frame", "ShowItemsBindFrame", frame, "BackdropTemplate")
    bind:SetSize(SUB_WIDTH, SUB_HEIGHT)
    bind:SetPoint("TOP", frame, "TOP", 0, -21)
    bind:SetFrameStrata("FULLSCREEN_DIALOG")
    bind:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    bind:SetBackdropBorderColor(0.5, 0.5, 0.5)
    bind:EnableMouse(true)
    bind:EnableKeyboard(true)
    bind:EnableMouseWheel(true)
    if bind.SetPropagateKeyboardInput then bind:SetPropagateKeyboardInput(false) end

    local hint = bind:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    hint:SetPoint("TOP", 0, -40)
    hint:SetText("Press a key to bind")
    hint:SetTextColor(0.8, 0.8, 0.8)
    bind.target = bind:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    bind.target:SetSize(170, 50)
    bind.target:SetPoint("TOP", 0, -60)
    bind.current = bind:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bind.current:SetSize(170, 50)
    bind.current:SetPoint("TOP", 0, -120)
    bind.current:SetTextColor(0.8, 0.8, 0.8)

    local cancel = UI.Button(bind, 64, 20, "Cancel")
    cancel:SetPoint("BOTTOM", bind, "BOTTOM", 36, 12)
    cancel:SetScript("OnClick", function() bind:Hide() end)
    local unbind = UI.Button(bind, 64, 20, "Unbind")
    unbind:SetPoint("BOTTOM", bind, "BOTTOM", -36, 12)
    unbind:SetScript("OnClick", function()
        local onUnbind = bind.onUnbind
        bind:Hide()
        if onUnbind then onUnbind() end
        SI.RefreshWindow()
    end)

    bind:SetScript("OnKeyDown", function(_, key)
        if IGNORED_KEYS[key] then return end
        if key == "ESCAPE" then
            bind:Hide()
            return
        end
        ApplyKey(ModifierPrefix() .. key)
    end)
    bind:SetScript("OnMouseUp", function(_, button)
        local key = MOUSE_KEYS[button]
        if not key and (IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown()) then
            if button == "LeftButton" then key = "BUTTON1" elseif button == "RightButton" then key = "BUTTON2" end
        end
        if key then ApplyKey(ModifierPrefix() .. key) end
    end)
    bind:SetScript("OnMouseWheel", function(_, delta)
        ApplyKey(ModifierPrefix() .. (delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    bind:Hide()
end

-- title: what is being bound; currentKey: its key or nil; onKey(key) / onUnbind() apply the result.
function SI.BeginKeyCapture(title, currentKey, onKey, onUnbind)
    if not frame or not bind then return end
    -- cover the tab that is showing
    bind:ClearAllPoints()
    bind:SetPoint("TOPLEFT", active.frame, "TOPLEFT")
    bind:SetPoint("BOTTOMRIGHT", active.frame, "BOTTOMRIGHT")
    bind.target:SetText(title)
    bind.current:SetText("Currently: " .. UI.KeyText(currentKey))
    bind.onKey, bind.onUnbind = onKey, onUnbind
    bind:Show()
end

------------------------------------------------------------------------
-- Slot buttons
------------------------------------------------------------------------

-- Slot states: "hidden"; "plate" (gray plate only), "plateOn" (plate with the slot picture),
-- "plateGold" (same, gold border); "off" (dark item icon), "on" and "gold" (item icon).
local function IsPlate(state)
    return state == "plate" or state == "plateOn" or state == "plateGold"
end

local function UpdateSlot(slot)
    local b = slotButtons[slot]
    local state = active and active.slotState and active.slotState(slot) or "off"
    if state == "hidden" then
        b:Hide()
        return
    end
    b:Show()
    b.border:SetVertexColor(1, 1, 1)
    if IsPlate(state) then
        -- the same gray plate as under an action bar button, never the item itself
        b.bg:SetColorTexture(0.3, 0.3, 0.3, 0.9)
        b.icon:SetDesaturated(true)
        if state == "plate" then
            b.icon:Hide()
        else
            b.icon:SetTexture(SI.SlotTexture(slot))
            b.icon:SetVertexColor(0.6, 0.6, 0.6)
            b.icon:SetAlpha(0.5)
            b.icon:Show()
        end
        if state == "plateGold" then b.border:SetVertexColor(1, 0.82, 0) end
        return
    end
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    b.icon:SetDesaturated(false)
    b.icon:SetAlpha(1)
    b.icon:Show()
    -- a tab may show its own item in the slot (the item chosen for a set)
    local own = active.slotIcon and active.slotIcon(slot)
    b.icon:SetTexture(own or GetInventoryItemTexture("player", slot) or SI.SlotTexture(slot))
    if state == "off" then
        b.icon:SetVertexColor(0.25, 0.25, 0.25)
    else
        b.icon:SetVertexColor(1, 1, 1)
        if state == "gold" then b.border:SetVertexColor(1, 0.82, 0) end
    end
end

local function MakeSlotButton(slot)
    local b = CreateFrame("Button", "ShowItemsInv" .. slot, frame)
    SI.SkinButton(b, SLOT_SIZE)
    b:RegisterForClicks("LeftButtonUp")
    b.slot = slot
    b:SetScript("OnClick", function(self)
        if active and active.slotClick then active.slotClick(self.slot) end
        SI.RefreshWindow()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local state = active and active.slotState and active.slotState(self.slot)
        local link = active and active.slotLink and active.slotLink(self.slot)
        if link and pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
            -- the item chosen for this slot
        elseif IsPlate(state) or not GameTooltip:SetInventoryItem("player", self.slot) then
            GameTooltip:SetText(SI.SLOTS[self.slot].name, 1, 1, 1)
        end
        local tip = active and active.slotTip and active.slotTip(self.slot)
        if tip then GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
        -- a tab can show a menu next to the slot while the mouse is over it
        if active and active.slotHover then active.slotHover(self.slot, self) end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slotButtons[slot] = b
    return b
end

local function BuildSlots()
    for i, slot in ipairs(LEFT_COLUMN) do
        MakeSlotButton(slot):SetPoint("TOPLEFT", 8, -24 - (i - 1) * 40)
    end
    for i, slot in ipairs(RIGHT_COLUMN) do
        MakeSlotButton(slot):SetPoint("TOPRIGHT", -8, -24 - (i - 1) * 40)
    end
    for _, entry in ipairs(BOTTOM_ROW) do
        MakeSlotButton(entry[1]):SetPoint("BOTTOM", entry[2], 8)
    end
    -- selects all slots or none (tabs that have slotAll)
    allButton = UI.SmallButton(frame, 24, { 0.75, 0.875, 0.375, 0.5 }, { 0.875, 1, 0.375, 0.5 }, "ShowItemsToggleAll")
    allButton:SetPoint("TOPRIGHT", slotButtons[16], "TOPLEFT", -10, -8)
    allButton:SetScript("OnClick", function()
        if active and active.slotAll then active.slotAll() end
        SI.RefreshWindow()
    end)
    UI.Tip(allButton, "Toggle All", "Selects all slots or none.")
    allButton:Hide()
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------

function SI.RegisterTab(id, label, def)
    def.id, def.label = id, label
    tabs[id] = def
end

function SI.TabFrame(id)
    return tabs[id] and tabs[id].frame
end

function SI.ActiveTab()
    return active and active.id
end

local function SelectTab(id)
    if bind then bind:Hide() end
    UI.HideConfirm()
    active = tabs[id] or tabs[1]
    -- the window opens on this tab the next time (also after a reload)
    if SI.db then SI.db.lastTab = active.id end
    -- Draw order: inactive tabs are tucked behind the content panel, the selected tab is in
    -- front of it and merges with it.
    local base = frame:GetFrameLevel()
    for _, tab in pairs(tabs) do
        if tab == active then
            tab.button:SetFrameLevel(base + 4)
            tab.button:Disable()
            tab.button:EnableMouse(false)
            tab.frame:Show()
        else
            tab.button:SetFrameLevel(base + 1)
            tab.button:Enable()
            tab.button:EnableMouse(true)
            tab.frame:Hide()
        end
    end
    SI.RefreshWindow()
end

local function MakeTabButton(tab, previous, count)
    local b = CreateFrame("Button", "ShowItemsTab" .. tab.id, frame)
    b:SetSize(TAB_WIDTH, 24)
    local normal = b:CreateTexture(nil, "BACKGROUND")
    normal:SetTexture(TABS)
    normal:SetTexCoord(0, 0.765625, 0, 0.375)
    b:SetNormalTexture(normal)
    local disabled = b:CreateTexture(nil, "BACKGROUND")
    disabled:SetTexture(TABS)
    disabled:SetTexCoord(0, 0.765625, 0.5, 0.875)
    b:SetDisabledTexture(disabled)
    local font = CreateFont("ShowItemsTabFont" .. tab.id)
    font:SetFontObject(_G.GameFontHighlightSmall)
    font:SetTextColor(0.75, 0.75, 0.75)
    b:SetNormalFontObject(font)
    b:SetHighlightFontObject(_G.GameFontHighlightSmall)
    b:SetDisabledFontObject(_G.GameFontHighlightSmall)
    b:SetText(tab.label)
    if previous then
        b:SetPoint("TOPLEFT", previous, "TOPRIGHT")
    else
        -- the row of tabs is centered on the window
        b:SetPoint("TOPLEFT", frame, "TOP", -count * TAB_WIDTH / 2, -6)
    end
    b:SetScript("OnClick", function() SelectTab(tab.id) end)
    tab.button = b
    return b
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local function ShowHelp(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("ShowItems", 1, 0.82, 0)
    local function line(title, text)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    line("Track / Untrack", "Ctrl+right click a slot in the character window to select it. Ctrl+Shift+right click several slots to select them all, then choose Track or Untrack.")
    line("Tracking windows", "Left-click uses the item. Drag to move. Windows snap together when close and the dropped window takes the size of the one it joins; hold Ctrl while dragging to move one window alone.")
    line("Hover over a window", "Lists the items from your bags that fit the slot. Click one to equip it. In combat the item is queued and equipped when combat ends; a small picture of it shows on the window.")
    line("Right-click a window", "Lists the items from your bags that fit the slot, with lock and resize buttons above them.")
    line("Sets tab", "Click the slots around the panel to choose them, type a name and press Save to store the items you wear. Right-click a slot to choose an item from your bags for it. Equip puts a set on from your bags; Bind Key assigns a key. In combat a set key swaps weapons only.")
    line("Minimap button", "Left-click: list of sets. Right-click: settings. Shift+left-click: enable or disable the addon (gray icon means disabled).")
    line("Commands", "/si opens settings. /si sets opens sets. /si profiles opens profiles. /si help lists commands. /si reset resets everything.")
    GameTooltip:Show()
end

-- The window is scaled as a whole: the layout stays intact at any size.
local function ClampScale(scale)
    local fits = UIParent:GetHeight() / HEIGHT
    return max(MIN_SCALE, min(MAX_SCALE, fits, scale))
end

local sizing

local function UpdateResize()
    if not sizing then return end
    local cx, cy = GetCursorPosition()
    local wantedWidth = (WIDTH * sizing.eff + (cx - sizing.cx)) / WIDTH
    local wantedHeight = (HEIGHT * sizing.eff - (cy - sizing.cy)) / HEIGHT
    local scale = ClampScale((wantedWidth + wantedHeight) / 2 / UIParent:GetEffectiveScale())
    frame:SetScale(scale)
    SI.db.windowScale = scale
    SI.db.windowScaleCustom = true
    if sizing.left then
        -- the top-left corner stays where it was
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sizing.left / scale, sizing.top / scale)
    end
end

local function BuildGrip()
    local grip = CreateFrame("Button", "ShowItemsResizeGrip", frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        local scale = frame:GetScale()
        local left, top = frame:GetLeft(), frame:GetTop()
        local cx, cy = GetCursorPosition()
        sizing = {
            cx = cx, cy = cy, eff = frame:GetEffectiveScale(),
            left = left and left * scale, top = top and top * scale,
        }
        grip:SetScript("OnUpdate", UpdateResize)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        sizing = nil
    end)
    UI.Tip(grip, "Resize", "Drag to make the window larger or smaller.")
end

local function Build()
    frame = CreateFrame("Frame", "ShowItemsOptions", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetScale(ClampScale(SI.db.windowScale))
    frame:SetPoint("CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ShowItemsOptions")

    local title = frame:CreateFontString(nil, "BACKGROUND", _G.SubSpellFont and "SubSpellFont" or "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -9)
    title:SetTextColor(0.65, 0.65, 0.65)
    title:SetText("SI")
    local help = CreateFrame("Button", nil, frame)
    help:SetSize(40, 16)
    help:SetPoint("TOPLEFT", 4, -6)
    help:SetScript("OnEnter", ShowHelp)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local ids = {}
    for id in pairs(tabs) do ids[#ids + 1] = id end
    -- left to right: Sets, Settings, Profiles (tab ids 2, 1, 3)
    local rank = {}
    for i, id in ipairs(TAB_ORDER) do rank[id] = i end
    table.sort(ids, function(a, b) return (rank[a] or 100 + a) < (rank[b] or 100 + b) end)
    local previous
    for _, id in ipairs(ids) do previous = MakeTabButton(tabs[id], previous, #ids) end

    local close = CreateFrame("Button", "ShowItemsClose", frame)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -6, -6)
    local closeNormal = close:CreateTexture(nil, "ARTWORK")
    closeNormal:SetTexture(BUTTONS)
    closeNormal:SetTexCoord(0.375, 0.5, 0.25, 0.375)
    close:SetNormalTexture(closeNormal)
    local closePushed = close:CreateTexture(nil, "ARTWORK")
    closePushed:SetTexture(BUTTONS)
    closePushed:SetTexCoord(0.5, 0.625, 0.25, 0.375)
    close:SetPushedTexture(closePushed)
    local closeHighlight = close:CreateTexture(nil, "HIGHLIGHT")
    closeHighlight:SetTexture(BUTTONS)
    closeHighlight:SetTexCoord(0.25, 0.375, 0, 0.125)
    closeHighlight:SetAllPoints()
    closeHighlight:SetBlendMode("ADD")
    close:SetScript("OnClick", function() frame:Hide() end)

    BuildSlots()
    BuildGrip()

    for _, id in ipairs(ids) do
        local tab = tabs[id]
        local sub = UI.Panel(frame, SUB_WIDTH, SUB_HEIGHT)
        sub:SetFrameLevel(frame:GetFrameLevel() + 2)
        sub:SetPoint("TOP", frame, "TOP", 0, -21)
        sub:Hide()
        tab.frame = sub
        tab.build(sub)
    end
    BuildBind()

    frame:SetScript("OnShow", function() SI.RefreshWindow() end)
    frame:SetScript("OnHide", function()
        bind:Hide()
        UI.HideConfirm()
    end)
end

function SI.RefreshWindow()
    if not frame or not frame:IsShown() or not active then return end
    for slot in pairs(SI.SLOTS) do UpdateSlot(slot) end
    allButton:SetShown(active.slotAll ~= nil)
    if active.refresh then active.refresh() end
end
SI.RefreshOptions = SI.RefreshWindow
SI.RefreshProfiles = SI.RefreshWindow
SI.RefreshSets = SI.RefreshWindow

function SI.OpenWindow(id)
    if not frame then Build() end
    frame:Show()
    SelectTab(id or (active and active.id) or 1)
end

-- Opens the tab, or closes the window when that tab is already showing.
local function Toggle(id)
    if frame and frame:IsShown() and active and active.id == id then
        frame:Hide()
    else
        SI.OpenWindow(id)
    end
end

function SI.CloseWindow()
    if frame then frame:Hide() end
end

-- Opens the window on the tab that was used last, or closes it when it is open.
function SI.OpenOptions()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        SI.OpenWindow(SI.db and SI.db.lastTab)
    end
end
function SI.OpenSets() Toggle(2) end
function SI.OpenProfiles() Toggle(3) end

SI.On("PLAYER_EQUIPMENT_CHANGED", function()
    if SI.db then SI.RefreshWindow() end
end)
