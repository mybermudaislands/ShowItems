local _, SI = ...

local sin, pi = math.sin, math.pi

-- Hover menu on the character window (the ItemRack menu): while the mouse is over an equipment slot,
-- the bag items that fit the slot are listed next to it. A click equips the item (or queues it in combat).
-- The menu and the Ctrl+right click Track / Untrack menu replace each other: this menu does not open
-- while Ctrl is held or the Track / Untrack menu is open, and Ctrl+right click on a slot closes it.
-- Like every ShowItems menu it is drawn above the item tooltip of the slot, and a shimmering glow
-- around its frame keeps it from blending into that tooltip.

local menu = SI.NewGridMenu("ShowItemsCharacterMenu", { hover = true })
-- The panel and its border are 20% darker than the standard gray of the ShowItems menus (not the item buttons).
menu:SetBackdropColor(0.8, 0.8, 0.8, 1)
menu:SetBackdropBorderColor(0.48, 0.48, 0.48, 1)

-- The menu opens to the right of every slot, the buttons running outward in rows.
local DOCK = "RIGHT"

------------------------------------------------------------------------
-- Glow around the frame of the menu
------------------------------------------------------------------------

-- ShowItemsGlow.tga is a 64x64 glow ring whose peak runs along a rounded rectangle 16 px inside the
-- texture edge. It is cut into 9 parts (corners 0..0.375, stretched edges 0.375..0.625) so the glow
-- fits a frame of any size: a menu of two items is glowing along its whole frame, not around its first item.
local GLOW_TEXTURE = "Interface\\AddOns\\ShowItems\\Textures\\ShowItemsGlow"
local GLOW_OUT = 10 -- pixels the glow reaches outside the frame (16 texture pixels fade out over them)
local GLOW_CORNER = GLOW_OUT * 24 / 16 -- a corner part is 24 texture pixels
local GLOW_ALPHA = 0.75 -- how visible the glow is
local GLOW_PERIOD = 2 -- seconds for the shimmer to run once around the frame
local GOLD, PALE = { 1, 0.82, 0.1 }, { 1, 0.97, 0.7 }

-- part: texture coordinates and anchors inside the glow frame. They go around the frame
-- clockwise from the top left corner, which is the order the shimmer runs in.
local GLOW_PARTS = {
    { tex = { 0, 0.375, 0, 0.375 }, corner = "TOPLEFT" },
    { tex = { 0.375, 0.625, 0, 0.375 }, edge = "TOP" },
    { tex = { 0.625, 1, 0, 0.375 }, corner = "TOPRIGHT" },
    { tex = { 0.625, 1, 0.375, 0.625 }, edge = "RIGHT" },
    { tex = { 0.625, 1, 0.625, 1 }, corner = "BOTTOMRIGHT" },
    { tex = { 0.375, 0.625, 0.625, 1 }, edge = "BOTTOM" },
    { tex = { 0, 0.375, 0.625, 1 }, corner = "BOTTOMLEFT" },
    { tex = { 0, 0.375, 0.375, 0.625 }, edge = "LEFT" },
}

local glow = CreateFrame("Frame", nil, menu)
glow:EnableMouse(false)
glow:SetAlpha(GLOW_ALPHA)
glow:SetPoint("TOPLEFT", menu, "TOPLEFT", -GLOW_OUT, GLOW_OUT)
glow:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", GLOW_OUT, -GLOW_OUT)
glow.parts = {}

for i, part in ipairs(GLOW_PARTS) do
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetTexture(GLOW_TEXTURE)
    t:SetTexCoord(part.tex[1], part.tex[2], part.tex[3], part.tex[4])
    t:SetBlendMode("ADD")
    if part.corner then
        t:SetSize(GLOW_CORNER, GLOW_CORNER)
        t:SetPoint(part.corner, glow, part.corner, 0, 0)
    elseif part.edge == "TOP" or part.edge == "BOTTOM" then
        local left, right = part.edge .. "LEFT", part.edge .. "RIGHT"
        t:SetHeight(GLOW_CORNER)
        t:SetPoint(left, glow, left, GLOW_CORNER, 0)
        t:SetPoint(right, glow, right, -GLOW_CORNER, 0)
    else
        local top, bottom = "TOP" .. part.edge, "BOTTOM" .. part.edge
        t:SetWidth(GLOW_CORNER)
        t:SetPoint(top, glow, top, 0, -GLOW_CORNER)
        t:SetPoint(bottom, glow, bottom, 0, GLOW_CORNER)
    end
    glow.parts[i] = t
end

-- A wave of brightness and color (gold to pale yellow) runs around the frame.
local function Shimmer(time)
    local count = #glow.parts
    for i, t in ipairs(glow.parts) do
        local wave = 0.5 + 0.5 * sin(2 * pi * (time / GLOW_PERIOD - (i - 1) / count))
        t:SetVertexColor(
            GOLD[1] + (PALE[1] - GOLD[1]) * wave,
            GOLD[2] + (PALE[2] - GOLD[2]) * wave,
            GOLD[3] + (PALE[3] - GOLD[3]) * wave,
            0.6 + 0.4 * wave)
    end
end

local elapsed = 0
glow:SetScript("OnUpdate", function(_, step)
    elapsed = elapsed + step
    Shimmer(elapsed)
end)

-- The glow is drawn with the menu above the tooltips, behind the item buttons of the menu.
local function RaiseGlow()
    local level = menu:GetFrameLevel()
    glow:SetFrameStrata("TOOLTIP")
    glow:SetFrameLevel(level + 1)
    for _, button in ipairs(menu.buttons) do
        button:SetFrameLevel(level + 2)
        if button.star then -- the favorite star is on its button
            button.star:SetFrameStrata("TOOLTIP")
            button.star:SetFrameLevel(level + 3)
        end
    end
end

local function GlowEnabled()
    return not SI.db or SI.db.glow ~= false
end

menu:HookScript("OnShow", function()
    elapsed = 0
    Shimmer(0)
    RaiseGlow()
    glow:SetShown(GlowEnabled())
end)
menu:HookScript("OnHide", function() glow:Hide() end)

-- The Glow option of the settings window.
function SI.SetGlow(value)
    SI.db.glow = value and true or false
    glow:SetShown(menu:IsShown() and GlowEnabled())
end

------------------------------------------------------------------------
-- Item tooltip
------------------------------------------------------------------------

-- The item tooltip is the short one of the addon (ItemTip.lua: name and characteristics, no comparison tooltip,
-- lifted above the menu). It stands above the frame of the menu, its left edge on the left edge of the icon.
-- A tall tooltip (other addons add lines to it) may not fit between the menu and the top of the screen. The game
-- would push it down over the menu to keep it on the screen, so its scale is lowered until it fits above the
-- menu (not below MIN_TIP_SCALE); ItemTip.lua gives it its own scale back when it hides.
-- The distance the game keeps between a tooltip and the top edge of the screen is not known, so it is measured:
-- when the tooltip hangs lower than the top edge of the menu, the game has pushed it down, and the gap it left
-- at the top of the screen is the margin to leave (kept for the following tooltips).
local MIN_TIP_SCALE, MIN_MARGIN, MAX_MARGIN = 0.5, 4, 120
local SETTLE_TICKS = 3 -- updates to wait after a change before the position of the tooltip is read again
local tipMargin = MIN_MARGIN
local tipSettle = 0

-- The tooltip stands on the top edge of the menu frame, above the whole menu, its left edge on the left edge
-- of the icon it belongs to (the icon sits behind the line of the frame, not under the tooltip). The anchor is a
-- point of that edge, a child of the menu so that it has the scale of the menu and of its buttons.
local TIP_GAP = 2 -- pixels between the frame of the menu and the tooltip
local tipAnchor = CreateFrame("Frame", "ShowItemsCharacterMenuTipAnchor", menu)
tipAnchor:SetSize(1, 1)
tipAnchor:EnableMouse(false)

local function PlaceTipAnchor(button)
    local ok, _, _, _, x = pcall(button.GetPoint, button, 1) -- offset of the icon from the left edge of the menu
    tipAnchor:ClearAllPoints()
    tipAnchor:SetPoint("TOPLEFT", menu, "TOPLEFT", ok and tonumber(x) or 0, TIP_GAP)
end

local function FitTip()
    local baseScale = SI.ItemTipBaseScale()
    if not baseScale then return end
    local top, height = tipAnchor:GetTop(), GameTooltip:GetHeight()
    if not top or not height or height <= 0 then return end
    local ui = UIParent:GetEffectiveScale()
    local screenTop = (UIParent:GetTop() or UIParent:GetHeight()) * ui
    local startTop = top * tipAnchor:GetEffectiveScale() -- the top of the anchor: where the tooltip starts
    if tipSettle > 0 then
        tipSettle = tipSettle - 1
    else
        local tipEffective = GameTooltip:GetEffectiveScale()
        local tipTop, tipBottom = GameTooltip:GetTop(), GameTooltip:GetBottom()
        if tipTop and tipBottom and tipBottom * tipEffective < startTop - 1 then
            tipMargin = math.min(MAX_MARGIN, math.max(tipMargin, screenTop - tipTop * tipEffective + 1))
        end
    end
    local room = screenTop - startTop - tipMargin
    local scale = math.min(baseScale, math.max(MIN_TIP_SCALE, room / (height * ui)))
    if math.abs(GameTooltip:GetScale() - scale) > 0.001 then
        GameTooltip:SetScale(scale)
        tipSettle = SETTLE_TICKS
    end
end

local function ShowItemTip(button, item)
    tipSettle = SETTLE_TICKS -- the position left from the previous tooltip says nothing yet
    SI.ShowItemTip(button, {
        above = menu,
        place = function(tip)
            PlaceTipAnchor(button)
            tip:SetPoint("BOTTOMLEFT", tipAnchor, "TOPLEFT", 0, 0)
        end,
        fill = function(tip)
            if not pcall(tip.SetBagItem, tip, item.bag, item.index) then
                tip:SetHyperlink(item.link)
            end
        end,
        update = FitTip,
    })
end

menu:HookScript("OnHide", function()
    for _, button in ipairs(menu.buttons) do
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end
end)

------------------------------------------------------------------------
-- Favorite star
------------------------------------------------------------------------

-- A star in the top right corner of every icon: empty for a usual item, filled (gold) for a favorite. A click
-- on the star marks or unmarks the item (it does not equip it). The favorites come first in the menu, in the
-- order they were marked (Favorites.lua); the order changes the next time the menu opens, not under the cursor.
-- The star is ShowItemsStar.tga (made by tools\make_star_texture.lua), a white star with rounded points and a
-- black edge, two of them side by side: the empty one on the left half (a thick ring with a dark middle, so it is
-- readable on a yellow icon) and the filled one on the right half. The addon tints it: gold for a favorite and
-- for a star under the mouse, light for an empty one.
local STAR_TEXTURE = "Interface\\AddOns\\ShowItems\\Textures\\ShowItemsStar"
local STAR_SIZE = 18 -- for an icon of 36 px
local STAR_GOLD, STAR_EMPTY = { 1, 0.82, 0.1 }, { 0.95, 0.95, 0.95 }
local STAR_EMPTY_ALPHA = 0.9 -- opacity of the star of a usual item

local function UpdateStar(star)
    local favorite = SI.IsFavorite(star.itemId)
    local lit = favorite or star.hovered
    local color = lit and STAR_GOLD or STAR_EMPTY
    if favorite then
        star.texture:SetTexCoord(0.5, 1, 0, 1)
    else
        star.texture:SetTexCoord(0, 0.5, 0, 1)
    end
    star.texture:SetVertexColor(color[1], color[2], color[3])
    star:SetAlpha(lit and 1 or STAR_EMPTY_ALPHA)
end

local function CreateStar(button)
    local size = math.floor(STAR_SIZE * menu.icon / 36 + 0.5)
    local star = CreateFrame("Button", nil, button)
    star:SetSize(size, size)
    star:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    star:RegisterForClicks("LeftButtonUp")
    star.texture = star:CreateTexture(nil, "OVERLAY")
    star.texture:SetAllPoints()
    star.texture:SetTexture(STAR_TEXTURE)
    star:SetScript("OnClick", function(self)
        if not self.itemId then return end
        SI.ToggleFavorite(self.itemId)
        UpdateStar(self)
    end)
    -- the star covers a corner of the icon, so the mouse leaves the icon when it is over the star:
    -- the star hands the tooltip over to the icon again
    star:SetScript("OnEnter", function(self)
        self.hovered = true
        UpdateStar(self)
        local onEnter = button:GetScript("OnEnter")
        if onEnter then onEnter(button) end
    end)
    star:SetScript("OnLeave", function(self)
        self.hovered = false
        UpdateStar(self)
        local onLeave = button:GetScript("OnLeave")
        if onLeave then onLeave(button) end
    end)
    star:SetScript("OnHide", function(self)
        self.hovered = false
    end)
    return star
end

-- One star for every listed icon: entries[i] belongs to menu.buttons[i].
local function UpdateStars(entries)
    for i, entry in ipairs(entries) do
        local button = menu.buttons[i]
        if button then
            if not button.star then button.star = CreateStar(button) end
            button.star.itemId = entry.itemId
            button.star:SetShown(entry.itemId ~= nil)
            UpdateStar(button.star)
        end
    end
end

------------------------------------------------------------------------
-- Opening and closing
------------------------------------------------------------------------

function SI.HideCharacterMenu()
    menu:Hide()
end

function SI.ShowCharacterMenu(slotButton)
    local slot = slotButton:GetID()
    local db = SI.db
    if not db or not db.enabled or not SI.SLOTS[slot] then
        menu:Hide()
        return
    end
    -- Ctrl selects slots for Track / Untrack, and an item on the cursor is being moved: no menu then
    if IsControlKeyDown() or (SI.IsContextShown and SI.IsContextShown()) or (CursorHasItem and CursorHasItem()) then
        menu:Hide()
        return
    end
    local entries = {}
    SI.RefreshFavorites() -- favorites that left the bags a day ago are removed here, nothing runs on a timer
    for _, item in ipairs(SI.SortByFavorites(SI.ScanBags(slot))) do
        entries[#entries + 1] = {
            icon = item.icon, count = item.count, itemId = item.id,
            onClick = function()
                menu:Hide()
                GameTooltip:Hide()
                SI.EquipOrQueue(item, slot)
            end,
            onEnter = function(button) ShowItemTip(button, item) end,
        }
    end
    if #entries == 0 then
        menu:Hide()
        return
    end
    menu:Open(entries, slotButton, DOCK)
    UpdateStars(entries)
    -- Open raised the menu and showed it; the glow and the stars follow the new level
    RaiseGlow()
end

-- Called by Menu.lua once for every character window slot button.
function SI.HookCharacterMenu(button)
    button:HookScript("OnEnter", function(self) SI.ShowCharacterMenu(self) end)
    -- pressing the slot (picking the item up, using it, Ctrl+right click) closes the menu
    button:HookScript("PreClick", function() menu:Hide() end)
end

-- Called by Menu.lua once for the character window itself.
function SI.HookCharacterMenuFrame(frame)
    frame:HookScript("OnHide", function() menu:Hide() end)
end
