local _, SI = ...

local ICON_PATH = "Interface\\Icons\\INV_Misc_Bag_10_Red"
local button

function SI.UpdateMinimap()
    if not button then return end
    local enabled = SI.db.enabled
    button.icon:SetDesaturated(not enabled)
    if enabled then
        button.icon:SetVertexColor(1, 1, 1)
    else
        button.icon:SetVertexColor(0.7, 0.7, 0.7)
    end
end

local function UpdatePosition()
    local angle = math.rad(SI.db.minimap.angle)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    SI.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    UpdatePosition()
end

local function Create()
    if button or not Minimap then return end
    button = CreateFrame("Button", "ShowItemsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(17, 17)
    button.icon:SetPoint("TOPLEFT", 7, -6)
    button.icon:SetTexture(ICON_PATH)
    button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- left: list of sets, right: settings, Shift+left: enable or disable the addon
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            SI.OpenOptions()
        elseif IsShiftKeyDown() then
            SI.ToggleEnabled()
        else
            SI.ToggleSetMenu(self)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ShowItems", 1, 0.82, 0)
        GameTooltip:AddLine(SI.db.enabled and "Enabled" or "Disabled", 1, 1, 1)
        -- the name of each key combination is light blue
        local function Hint(keys, text)
            GameTooltip:AddLine("|cff66ccff" .. keys .. "|r: " .. text, 1, 1, 1)
        end
        Hint("Left-click", "sets")
        Hint("Right-click", "settings")
        Hint("Shift+left-click", "enable or disable")
        GameTooltip:AddLine(" ")
        Hint("Ctrl+right-click", "select a slot")
        Hint("Ctrl+Shift+right-click", "select several slots")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    SI.UpdateMinimap()
end

SI.OnInit(Create)
