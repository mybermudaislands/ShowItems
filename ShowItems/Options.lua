local _, SI = ...

-- Settings tab in the style of the ItemRack Config tab: a scrolling list of 24 px rows
-- (title, check boxes, number fields with a slider under each, buttons) on the 194 x 282
-- panel between the slot columns. The slots show which windows are tracked; "Slot Key
-- Bindings" asks for a slot and then for a key.

local UI = SI.UI

local ROWS, ROW_WIDTH, ROW_HEIGHT = 11, 156, 24

local ui = {}
local rows = {}
local opts -- one entry per row of the list
local updating = false
local binding = false -- waiting for a slot to bind a key to

------------------------------------------------------------------------
-- Rows of the list
------------------------------------------------------------------------

-- A number field and its slider are one setting; both rows use the same table.
local function Control(key, label, tooltip, low, high, step, form, get, set)
    return { key = key, label = label, tooltip = tooltip, min = low, max = high, step = step, form = form, get = get, set = set }
end

local function BuildOptions()
    local spacing = Control("Spacing", "Window spacing", "Space between windows that are attached to each other.",
        0, SI.MAX_SPACING, 1, "%d",
        function() return SI.db.spacing end,
        function(v) SI.SetSpacing(v) end)
    local alpha = Control("Alpha", "Transparency", "Transparency (alpha) of the tracking windows.",
        0.1, 1, 0.05, "%.2f",
        function() return SI.db.alpha end,
        function(v) SI.SetAlpha(v) end)
    local size = Control("Size", "Window size", "Resizes all windows at once and keeps the size difference between them.",
        SI.MIN_SIZE, SI.MAX_SIZE, 1, "%d",
        function() return SI.GetMeanSize() or SI.DEFAULT_SIZE end,
        function(v) SI.SetMeanSize(v) end)
    ui.controls = { spacing, alpha, size }

    opts = {
        { type = "label", label = (UnitName("player") or "Player") .. "'s Settings" },
        { type = "check", label = "Lock windows", tooltip = "Prevent windows from being moved.",
            get = function() return SI.db.locked end, set = function(v) SI.SetLocked(v) end },
        { type = "check", label = "Glow", tooltip = "Shimmering glow around the menu of bag items that opens over a slot of the character window.",
            get = function() return SI.db.glow ~= false end, set = function(v) SI.SetGlow(v) end },
        { type = "check", label = "Enable ShowItems", tooltip = "Show the tracking windows and use the key bindings. The same as Shift+left click on the minimap button.",
            get = function() return SI.db.enabled end, set = function(v) SI.SetEnabled(v) end },
        { type = "number", ctl = spacing },
        { type = "slider", ctl = spacing },
        { type = "number", ctl = alpha },
        { type = "slider", ctl = alpha },
        { type = "number", ctl = size },
        { type = "slider", ctl = size },
        { type = "button", name = "ShowItemsCommonSize", label = "Common size", tooltip = "Resets all windows to the default size.",
            onClick = function()
                if not SI.GetMeanSize() then
                    SI.Print("there are no tracking windows yet")
                    return
                end
                SI.SetCommonSize()
                SI.RefreshWindow()
            end },
        { type = "button", name = "ShowItemsKeyBindings", label = "Slot Key Bindings", tooltip = "Set key bindings to use slots.",
            onClick = function() SI.SetBindMode(true) end },
        { type = "button", name = "ShowItemsResetAll", label = "Reset all", tooltip = "Untracks every slot, removes all slot key bindings and restores size, spacing and opacity.",
            onClick = function()
                UI.Confirm("Reset all windows?", function()
                    SI.ResetAll()
                    SI.RefreshWindow()
                end)
            end },
    }
end

local function ShowTip(owner, label, tooltip)
    if not tooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(label, 1, 0.82, 0)
    GameTooltip:AddLine(tooltip, 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideTip() GameTooltip:Hide() end

------------------------------------------------------------------------
-- Slot key bindings mode
------------------------------------------------------------------------

function SI.SetBindMode(on)
    binding = on and true or false
    if ui.bindPanel then ui.bindPanel:SetShown(binding) end
    SI.RefreshWindow()
end

local function SlotClick(slot)
    if not binding then return end
    if not SI.db.tracked[slot] then
        SI.Print("track this slot first (Ctrl+right click it in the character window)")
        return
    end
    SI.BeginKeyCapture(SI.SLOTS[slot].name, SI.db.bindings[slot],
        function(key)
            SI.SetBinding(slot, key)
            SI.SetBindMode(false)
        end,
        function()
            SI.SetBinding(slot, nil)
            SI.SetBindMode(false)
        end)
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------

local function Apply(ctl, value)
    updating = true
    ctl.slider:SetValue(value)
    ctl.box:SetText(string.format(ctl.form, value))
    updating = false
end

local function BuildControl(sub, ctl)
    ctl.slider = UI.Slider(sub, "ShowItems" .. ctl.key .. "Slider", ctl.min, ctl.max, ctl.step, ctl.form)
    ctl.slider:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        ctl.set(value)
        ctl.box:SetText(string.format(ctl.form, ctl.get()))
        SI.RefreshWindow()
    end)
    ctl.slider:SetScript("OnEnter", function(self) ShowTip(self, ctl.label, ctl.tooltip) end)
    ctl.slider:SetScript("OnLeave", HideTip)
    ctl.box = UI.NumberBox(sub, "ShowItems" .. ctl.key)
    ctl.box.onEnter = function(text)
        local value = tonumber(text)
        if value and value >= ctl.min and value <= ctl.max then
            ctl.set(value)
            SI.RefreshWindow()
        else
            Apply(ctl, ctl.get())
        end
    end
    ctl.box.onCancel = function() Apply(ctl, ctl.get()) end
    ctl.box:SetScript("OnEnter", function(self) ShowTip(self, ctl.label, ctl.tooltip) end)
    ctl.box:SetScript("OnLeave", HideTip)
    ctl.slider:Hide()
    ctl.box:Hide()
end

local function MakeRow(sub, i)
    local row = CreateFrame("Button", "ShowItemsOptList" .. i, sub)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    if i == 1 then
        row:SetPoint("TOPLEFT", 8, -10)
    else
        row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT")
    end
    -- the title bar: a gradient over the whole row, only for a row that has a title
    row.underline = row:CreateTexture(nil, "BACKGROUND")
    row.underline:SetAllPoints()
    UI.Gradient(row.underline, "VERTICAL", 0, 0, 0, 1, 0.25, 0.25, 0.25, 1)
    row.label = row:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    row.label:SetPoint("LEFT", 2, 0)
    row.label:SetJustifyH("LEFT")
    row.checkText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
    row.checkText:SetSize(128, 24)
    row.checkText:SetPoint("RIGHT")
    row.checkText:SetJustifyH("LEFT")
    row.numberLabel = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
    row.numberLabel:SetPoint("LEFT", 24, 0)
    row.numberLabel:SetJustifyH("LEFT")
    row.check = UI.CheckBox(row)
    row.check:SetPoint("RIGHT", row.checkText, "LEFT")
    row.check:SetScript("OnClick", function(self)
        local opt = self:GetParent().opt
        if opt and opt.set then opt.set(self:GetChecked() and true or false) end
        SI.RefreshWindow()
    end)
    row.check:SetScript("OnEnter", function(self)
        local opt = self:GetParent().opt
        if opt then ShowTip(self, opt.label, opt.tooltip) end
    end)
    row.check:SetScript("OnLeave", HideTip)
    row:SetScript("OnClick", function(self)
        local opt = self.opt
        if opt and opt.type == "check" and self.check:IsShown() and self.check:IsEnabled() then
            self.check:SetChecked(not self.check:GetChecked())
            opt.set(self.check:GetChecked() and true or false)
            SI.RefreshWindow()
        end
    end)
    row:SetScript("OnEnter", function(self)
        local opt = self.opt
        if opt then ShowTip(self, opt.label or (opt.ctl and opt.ctl.label), opt.tooltip or (opt.ctl and opt.ctl.tooltip)) end
        if self.check:IsShown() then self.check:LockHighlight() end
    end)
    row:SetScript("OnLeave", function(self)
        HideTip()
        self.check:UnlockHighlight()
    end)
    rows[i] = row
end

local function Build(sub)
    BuildOptions()
    for i = 1, ROWS do MakeRow(sub, i) end
    for _, ctl in ipairs(ui.controls) do BuildControl(sub, ctl) end
    for _, opt in ipairs(opts) do
        if opt.type == "button" then
            opt.frame = UI.Button(sub, 128, 22, opt.label, opt.name)
            opt.frame:SetScript("OnClick", opt.onClick)
            opt.frame:SetScript("OnEnter", function(self) ShowTip(self, opt.label, opt.tooltip) end)
            opt.frame:SetScript("OnLeave", HideTip)
            opt.frame:Hide()
        end
    end

    ui.scroll = CreateFrame("ScrollFrame", "ShowItemsOptListScrollFrame", sub, "FauxScrollFrameTemplate")
    ui.scroll:SetPoint("TOPLEFT", rows[1], 0, -2)
    ui.scroll:SetPoint("BOTTOMRIGHT", rows[ROWS], -2, 1)
    ui.scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, SI.RefreshWindow)
    end)
    -- the dark strip behind the scroll bar
    local strip = ui.scroll:CreateTexture(nil, "BACKGROUND")
    strip:SetPoint("TOPLEFT", ui.scroll, "TOPRIGHT", 6, 0)
    strip:SetPoint("BOTTOMRIGHT", ui.scroll, "BOTTOMRIGHT", 22, 0)
    strip:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    UI.Gradient(strip, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 1)

    -- "Select a slot to bind to a key."
    ui.bindPanel = UI.Panel(sub, 194, 282)
    ui.bindPanel:SetAllPoints(sub)
    ui.bindPanel:SetFrameLevel(sub:GetFrameLevel() + 20)
    ui.bindPanel:EnableMouse(true)
    local hint = ui.bindPanel:CreateFontString(nil, "BACKGROUND", "GameFontNormalLarge")
    hint:SetSize(128, 60)
    hint:SetPoint("TOP", 0, -40)
    hint:SetJustifyH("CENTER")
    hint:SetText("Select a slot to bind to a key.")
    local cancel = UI.Button(ui.bindPanel, 60, 26, "Cancel", "ShowItemsSlotBindCancel")
    cancel:SetPoint("BOTTOMRIGHT", -8, 8)
    cancel:SetScript("OnClick", function() SI.SetBindMode(false) end)
    ui.bindPanel:Hide()

    sub:SetScript("OnHide", function()
        binding = false
        ui.bindPanel:Hide()
        for _, ctl in ipairs(ui.controls) do ctl.box:ClearFocus() end
    end)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

local function Refresh()
    FauxScrollFrame_Update(ui.scroll, #opts, ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(ui.scroll)
    for _, ctl in ipairs(ui.controls) do
        ctl.slider:Hide()
        ctl.box:Hide()
    end
    for _, opt in ipairs(opts) do
        if opt.frame then opt.frame:Hide() end
    end
    local level = rows[1]:GetFrameLevel() + 1
    for i = 1, ROWS do
        local row = rows[i]
        local opt = opts[offset + i]
        row.opt = opt
        row.underline:Hide()
        row.label:Hide()
        row.checkText:Hide()
        row.check:Hide()
        row.numberLabel:Hide()
        if not opt then
            row:Hide()
        else
            if opt.type == "label" then
                row.label:SetText(opt.label)
                row.label:Show()
                if #opt.label > 1 then row.underline:Show() end
            elseif opt.type == "check" then
                row.checkText:SetText(opt.label)
                row.checkText:SetTextColor(1, 1, 1)
                row.checkText:Show()
                row.check:SetChecked(opt.get())
                row.check:Show()
            elseif opt.type == "number" then
                local ctl = opt.ctl
                row.numberLabel:SetText(ctl.label)
                row.numberLabel:SetTextColor(1, 1, 1)
                row.numberLabel:Show()
                ctl.box:SetFrameLevel(level)
                ctl.box:ClearAllPoints()
                ctl.box:SetPoint("LEFT", row.numberLabel, "RIGHT", 16, -1)
                if not ctl.box:HasFocus() then Apply(ctl, ctl.get()) end
                ctl.box:Show()
            elseif opt.type == "slider" then
                local ctl = opt.ctl
                ctl.slider:SetFrameLevel(level)
                ctl.slider:ClearAllPoints()
                ctl.slider:SetPoint("LEFT", row, "LEFT", 32, 4)
                ctl.slider:Show()
            elseif opt.type == "button" then
                opt.frame:SetFrameLevel(level)
                opt.frame:ClearAllPoints()
                opt.frame:SetPoint("LEFT", row, "LEFT", 16, 0)
                opt.frame:Show()
            end
            row:Show()
        end
    end
    if ui.bindPanel then ui.bindPanel:SetShown(binding) end
end

SI.RegisterTab(1, "Settings", {
    build = Build,
    refresh = Refresh,
    -- the slots are dimmed and have no item menu; only while a key is being bound
    -- (the slots are clicked then) the tracked ones are bright
    slotState = function(slot) return binding and SI.db.tracked[slot] and "on" or "off" end,
    slotClick = SlotClick,
    slotTip = function(slot)
        local key = SI.db.bindings[slot]
        if binding then
            return SI.db.tracked[slot] and ("Click to bind a key. Key: " .. UI.KeyText(key)) or "Not tracked. Track it first."
        end
        return SI.db.tracked[slot] and ("Tracked. Key: " .. UI.KeyText(key)) or "Not tracked."
    end,
})
