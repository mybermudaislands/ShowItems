local _, SI = ...

-- The short item tooltip of the addon: the name of the item and its characteristics, nothing else. It is used
-- by the menu on the character window and by the tracking windows (and the menu above them).
--
-- SI.ShowItemTip(frame, options) shows the tooltip of GameTooltip for frame:
--   options.fill(tip)     fills the tooltip with the item (SetBagItem, SetInventoryItem, SetHyperlink)
--   options.side          "RIGHT" or "BELOW": where the tooltip stands next to the frame (SI.AnchorNextTo)
--   options.place(tip)    or: anchors the tooltip itself (its points are cleared before)
--   options.above         a frame drawn above the tooltips (a menu): the tooltip is lifted above it
--   options.update()      called after the tooltip was shown and on every update while it is shown
-- SI.HideItemTip(frame) hides it when it belongs to frame. SI.ItemTipBaseScale() is the scale GameTooltip has
-- when nothing is changed (the tooltip gets it back when it hides, whatever options.update did to it).
--
-- The game fills the tooltip as usual and other addons add their lines to it (prices, loot, notes); then it is
-- rebuilt from the lines that are kept. The price of the item is not a line, it goes with ClearLines. What is
-- kept (the first line is always the name):
--   26 Armor, 12 Block       the templates of the game (ARMOR_TEMPLATE, SHIELD_BLOCK_TEMPLATE)
--   +5 Stamina, -3 Spirit    a line that starts with a signed number
--   109 - 163 Damage         weapon damage with its speed, and (30.4 damage per second)
--   Equip: / Use: / Chance on hit:   the effects of the item (the words come from the game)
-- Everything else (binding, slot and type, durability, level, "Made by", lines of other addons) is dropped.
-- If anything goes wrong the tooltip stays as the game made it.
--
-- Only this one tooltip is shown: the game's own comparison tooltips (the worn item, ShoppingTooltip1 and 2)
-- are kept hidden while the item tooltip belongs to the frame. The game shows them while the item tooltip is
-- being filled and again when a modifier key changes, so they are hidden whenever they show.
-- A menu is drawn above every tooltip, so a tooltip next to a menu is lifted above it while it is shown (the
-- buttons of the menu would cover it otherwise) and gets its own level back when it hides.

local LIFT = 30
local savedLevel
local savedScale
local tipFrame -- the frame the item tooltip is shown for
local tipOptions
local keptLines -- the number of lines the tooltip has after it was rebuilt

local function Owned()
    return tipFrame ~= nil and GameTooltip:IsShown() and GameTooltip:IsOwned(tipFrame)
end

local function HideCompareTips()
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
        local tip = _G[name]
        if tip and tip:IsShown() then tip:Hide() end
    end
end

for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
    local tip = _G[name]
    if tip then
        tip:HookScript("OnShow", function(self)
            if Owned() then self:Hide() end
        end)
    end
end

------------------------------------------------------------------------
-- Which lines stay
------------------------------------------------------------------------

local function PlainText(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- "%d Armor" -> "^[%d%.,]+ Armor"
local function TemplatePattern(template)
    if type(template) ~= "string" then return nil end
    local escaped = template:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    escaped = escaped:gsub("%%[ds]", "[%%d%%.,]+")
    return "^" .. escaped
end

local function IsEffectLine(text)
    for _, trigger in ipairs({ _G.ITEM_SPELL_TRIGGER_ONEQUIP, _G.ITEM_SPELL_TRIGGER_ONUSE, _G.ITEM_SPELL_TRIGGER_ONPROC }) do
        if type(trigger) == "string" and trigger ~= "" and text:sub(1, #trigger) == trigger then return true end
    end
    return false
end

local function KeepLine(index, leftText)
    if index == 1 then return true end
    local text = PlainText(leftText)
    if text:find("^[%+%-]%d") or text:find("^%d+%s*%-%s*%d+") or IsEffectLine(text) then return true end
    for _, template in ipairs({ _G.ARMOR_TEMPLATE, _G.SHIELD_BLOCK_TEMPLATE, _G.DPS_TEMPLATE }) do
        local pattern = TemplatePattern(template)
        if pattern and text:find(pattern) then return true end
    end
    return false
end

local function ReadLine(index, side)
    local fontString = _G["GameTooltipText" .. side .. index]
    if not fontString then return nil end
    local text = fontString:GetText()
    if side == "Right" and not fontString:IsShown() then text = nil end
    if text == "" then text = nil end
    local r, g, b = fontString:GetTextColor()
    local okWrap, wrap = pcall(fontString.GetWordWrap, fontString)
    return text, r or 1, g or 1, b or 1, okWrap and wrap or false
end

local function ShortenTip()
    local count = GameTooltip:NumLines()
    if not count or count < 1 then return end
    local kept = {}
    for i = 1, count do
        local left, lr, lg, lb, wrap = ReadLine(i, "Left")
        if left and KeepLine(i, left) then
            local right, rr, rg, rb = ReadLine(i, "Right")
            -- long effect lines wrap as in the game, also when the client does not tell the wrapping of a line
            kept[#kept + 1] = {
                left = left, right = right, lr = lr, lg = lg, lb = lb, rr = rr, rg = rg, rb = rb,
                wrap = wrap or IsEffectLine(PlainText(left)),
            }
        end
    end
    if #kept == 0 then return end
    GameTooltip:ClearLines()
    for _, line in ipairs(kept) do
        if line.right then
            GameTooltip:AddDoubleLine(line.left, line.right, line.lr, line.lg, line.lb, line.rr, line.rg, line.rb)
        else
            GameTooltip:AddLine(line.left, line.lr, line.lg, line.lb, line.wrap)
        end
    end
    GameTooltip:Show() -- the size follows the lines
end

local function RebuildTip()
    if not pcall(ShortenTip) then GameTooltip:Show() end
    keptLines = GameTooltip:NumLines() -- also after an error, so that it is not tried again every update
end

------------------------------------------------------------------------
-- While the tooltip is shown
------------------------------------------------------------------------

GameTooltip:HookScript("OnUpdate", function()
    if Owned() then
        HideCompareTips()
        -- other addons may add lines after the tooltip was shown, or the game fills it again
        if GameTooltip:NumLines() ~= keptLines then RebuildTip() end
        if tipOptions and tipOptions.update then tipOptions.update() end
    end
end)

GameTooltip:HookScript("OnHide", function(self)
    tipFrame, tipOptions, keptLines = nil, nil, nil
    if savedLevel then
        self:SetFrameLevel(savedLevel)
        savedLevel = nil
    end
    if savedScale then
        self:SetScale(savedScale)
        savedScale = nil
    end
end)

function SI.ItemTipBaseScale()
    return savedScale
end

function SI.ShowItemTip(frame, options)
    GameTooltip:SetOwner(frame, "ANCHOR_NONE")
    tipFrame, tipOptions = frame, options -- set after SetOwner, which may hide the previous tooltip
    if options.place then
        GameTooltip:ClearAllPoints()
        options.place(GameTooltip)
    else
        SI.AnchorNextTo(GameTooltip, frame, options.side)
    end
    options.fill(GameTooltip)
    if not savedLevel then savedLevel = GameTooltip:GetFrameLevel() end
    if not savedScale then savedScale = GameTooltip:GetScale() end
    if options.above then GameTooltip:SetFrameLevel(options.above:GetFrameLevel() + LIFT) end
    GameTooltip:Show()
    RebuildTip()
    HideCompareTips()
    if options.update then options.update() end
end

function SI.HideItemTip(frame)
    if tipFrame and (frame == nil or frame == tipFrame) and GameTooltip:IsOwned(tipFrame) then
        GameTooltip:Hide()
    end
end
