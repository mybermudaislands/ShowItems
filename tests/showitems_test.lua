-- Run from the project root: lua5.1.exe tests\showitems_test.lua
local root = arg and arg[0] and arg[0]:match("^(.*)[\\/]tests[\\/][^\\/]+$") or "."
local mock = dofile(root .. "/tests/wow_mock.lua")
mock.install(_G)

-- record reads of undefined globals instead of failing, to review typos
local undefinedReads = {}
setmetatable(_G, { __index = function(_, k)
    undefinedReads[k] = true
    return nil
end })

local SI = {}
local FILES = { "Core", "Slots", "Trackers", "Menu", "ItemTip", "Flyout", "Favorites", "CharacterMenu", "Window", "Options", "Sets", "Profiles", "Minimap" }

-- character window slot buttons must exist before PLAYER_LOGIN
local SLOT_FRAMES = {
    CharacterHeadSlot = 1, CharacterNeckSlot = 2, CharacterShoulderSlot = 3, CharacterShirtSlot = 4,
    CharacterChestSlot = 5, CharacterWaistSlot = 6, CharacterLegsSlot = 7, CharacterFeetSlot = 8,
    CharacterWristSlot = 9, CharacterHandsSlot = 10, CharacterFinger0Slot = 11, CharacterFinger1Slot = 12,
    CharacterTrinket0Slot = 13, CharacterTrinket1Slot = 14, CharacterBackSlot = 15,
    CharacterMainHandSlot = 16, CharacterSecondaryHandSlot = 17, CharacterRangedSlot = 18,
    CharacterTabardSlot = 19,
}
for name, id in pairs(SLOT_FRAMES) do
    local f = CreateFrame("Button", name, UIParent)
    f:SetID(id)
end

for _, file in ipairs(FILES) do
    local chunk = assert(loadfile(root .. "/ShowItems/" .. file .. ".lua"))
    chunk("ShowItems", SI)
end

local passed, failed = 0, 0
local function eq(actual, expected, label)
    if type(expected) == "number" and type(actual) == "number" then
        if math.abs(actual - expected) < 0.001 then passed = passed + 1 return end
    elseif actual == expected then
        passed = passed + 1
        return
    end
    failed = failed + 1
    print(string.format("FAIL: %s (expected %s, got %s)", label, tostring(expected), tostring(actual)))
end
local function truthy(v, label) eq(not not v, true, label) end

local function coreFrame()
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnEvent then return f end
    end
end
local function fire(event, ...)
    coreFrame().scripts.OnEvent(coreFrame(), event, ...)
end
local function tick()
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnUpdate and f.shown then f.scripts.OnUpdate(f, 0.016) end
    end
end
local function drag(slot, fromX, fromY, toX, toY, ctrl)
    mock.cursor = { fromX, fromY }
    mock.mods.ctrl = ctrl and true or false
    SI.BeginMove(slot, ctrl)
    mock.cursor = { toX, toY }
    tick()
    SI.EndMove()
    mock.mods.ctrl = false
end
local function reset()
    SI.ResetAll()
    mock.combat = false
end
-- Ctrl+right click on a character window slot (the only way the addon selects a slot)
local function selectClick(slotFrame)
    local before = mock.mods.ctrl
    mock.mods.ctrl = true
    slotFrame.scripts.OnClick(slotFrame, "RightButton")
    mock.mods.ctrl = before
end
-- Ctrl+Shift+right click: adds the slot to the selection
local function multiClick(slotFrame)
    local ctrl, shift = mock.mods.ctrl, mock.mods.shift
    mock.mods.ctrl, mock.mods.shift = true, true
    slotFrame.scripts.OnClick(slotFrame, "RightButton")
    mock.mods.ctrl, mock.mods.shift = ctrl, shift
end

-- login
fire("ADDON_LOADED", "ShowItems")
truthy(ShowItemsDB and not SI.db, "account table exists, character db waits for login")
fire("PLAYER_LOGIN")
truthy(SI.db, "character db created at login")
eq(#mock.chat, 0, "no chat output at login")

-- track: first slot is centered, second goes to the right and sticks
SI.Track({ 13 })
eq(#mock.chat, 1, "tracking a slot prints one line")
truthy(mock.chat[1]:find("Slot 13 (Trinket 1) tracked.", 1, true) or mock.chat[1]:find("Slot 13 (", 1, true), "the chat line names the slot and its number")
truthy(not mock.chat[1]:find("item:", 1, true), "the chat line does not name an item")
SI.Track({ 13 })
eq(#mock.chat, 1, "tracking a tracked slot prints nothing")
SI.Untrack({ 13 })
truthy(#mock.chat == 2 and mock.chat[2]:find("Slot 13 (", 1, true) and mock.chat[2]:find("untracked.", 1, true), "untracking prints the slot and its number")
mock.chat = {}
SI.Track({ 13 })
mock.chat = {}
eq(SI.db.tracked[13].left, 940, "first tracker centered x")
eq(SI.db.tracked[13].top, 560, "first tracker centered y")
SI.Track({ 14 })
eq(SI.db.tracked[14].left, 980, "second tracker right of first")
eq(SI.db.tracked[14].top, 560, "second tracker same row")
truthy(SI.db.tracked[13].group and SI.db.tracked[13].group == SI.db.tracked[14].group, "group joined")
truthy(SI.frames[13]:IsShown(), "tracker shown")
eq(SI.frames[13].attrs.macrotext1, "/use 13", "use macro")

-- moving a group moves every member
drag(13, 500, 500, 600, 450)
eq(SI.db.tracked[13].left, 1040, "group moved x (13)")
eq(SI.db.tracked[14].left, 1080, "group moved x (14)")
eq(SI.db.tracked[13].top, 510, "group moved y")
truthy(SI.db.tracked[13].moved, "moved flag")

-- a new track after moving starts in the center again
SI.Track({ 15 })
eq(SI.db.tracked[15].left, 940, "new track after move is centered")
truthy(SI.db.tracked[15].group == nil, "new track after move is alone")

-- magnet
reset()
SI.Track({ 13 })
drag(13, 960, 540, 660, 540) -- 13 now at left 640
eq(SI.db.tracked[13].left, 640, "setup magnet")
SI.Track({ 14 })
eq(SI.db.tracked[14].left, 940, "second centered after move")
drag(14, 960, 540, 705, 532) -- target left 685, top 552: within snap distance
eq(SI.db.tracked[14].left, 680, "magnet snaps x")
eq(SI.db.tracked[14].top, 560, "magnet aligns y")
truthy(SI.db.tracked[14].group and SI.db.tracked[14].group == SI.db.tracked[13].group, "magnet joins group")

-- ctrl detaches and does not snap
drag(14, 700, 540, 700, 440, true)
truthy(SI.db.tracked[14].group == nil and SI.db.tracked[13].group == nil, "ctrl drag detaches")
eq(SI.db.tracked[14].top, 460, "ctrl drag moves freely")

-- detached windows snap again when brought near another one, even with Ctrl held
reset()
SI.Track({ 13, 14 })
local l13, t13top = SI.db.tracked[13].left, SI.db.tracked[13].top
drag(14, 960, 540, 960, 400, true) -- far below, Ctrl held on release
truthy(SI.db.tracked[14].group == nil, "ctrl drag away detaches")
drag(14, 960, 400, 964, 537, true) -- back next to window 13 (right side), a few px off
eq(SI.db.tracked[14].left, l13 + 40, "re-snaps with Ctrl held")
eq(SI.db.tracked[14].top, t13top, "re-snap aligns")
truthy(SI.db.tracked[14].group ~= nil and SI.db.tracked[14].group == SI.db.tracked[13].group, "re-snap rejoins group")

-- detaching in place does not instantly stick back
reset()
SI.Track({ 13, 14 })
drag(14, 960, 540, 965, 541, true)
truthy(SI.db.tracked[14].group == nil, "tiny ctrl drag stays detached")

-- locked windows do not move
SI.SetLocked(true)
local before = SI.db.tracked[14].left
drag(14, 700, 540, 800, 540)
eq(SI.db.tracked[14].left, before, "locked does not move")
SI.SetLocked(false)

-- resize: slider keeps groups flush
reset()
SI.Track({ 13, 14 })
SI.SetMeanSize(80)
eq(SI.db.tracked[13].size, 80, "mean size applied (13)")
eq(SI.db.tracked[14].size, 80, "mean size applied (14)")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 80, "group stays flush after resize")
eq(SI.db.tracked[14].top, SI.db.tracked[13].top, "group stays aligned after resize")

-- proportional resize with different sizes
SI.db.tracked[13].size = 40
SI.db.tracked[14].size = 80
SI.db.tracked[14].left = SI.db.tracked[13].left + 40
SI.SetMeanSize(90)
eq(SI.db.tracked[14].size / SI.db.tracked[13].size, 2, "ratio is preserved")
eq(SI.GetMeanSize(), 90, "mean reached")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + SI.db.tracked[13].size, "flush with different sizes")

-- clamp to the max size
SI.SetMeanSize(500)
truthy(SI.db.tracked[14].size <= SI.MAX_SIZE + 0.001, "max size respected")
eq(SI.db.tracked[14].size / SI.db.tracked[13].size, 2, "ratio kept at the limit")

-- common size
SI.db.tracked[13].size = 40
SI.db.tracked[14].size = 80
SI.db.tracked[14].left = SI.db.tracked[13].left + 40
SI.SetCommonSize()
eq(SI.db.tracked[13].size, SI.DEFAULT_SIZE, "common size resets to the default size (13)")
eq(SI.db.tracked[14].size, SI.DEFAULT_SIZE, "common size resets to the default size (14)")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + SI.DEFAULT_SIZE, "common size keeps flush")

-- triangle resize: top-right corner of the grabbed window stays fixed
reset()
SI.Track({ 13, 14 })
local t13 = SI.db.tracked[13]
local pivotX, pivotY = t13.left, t13.top
SI.SetResizeMode(14)
eq(ShowItemsResizeHandle:IsShown(), true, "handle shown in resize mode")
-- the handle is outside the right edge of the whole group, at its bottom
local hp = ShowItemsResizeHandle.points[1]
eq(hp[1], "BOTTOMLEFT", "handle anchored outside the group")
eq(hp[4], t13.left + 80 + 3, "handle is right of the last window")
eq(hp[5], t13.top - 40, "handle at the group bottom")
-- drag the handle: group (80 wide, 40 tall) grows by 50% when the cursor moves +40 / -20
mock.cursor = { 1000, 500 }
SI.BeginResize(14)
mock.cursor = { 1040, 480 }
tick()
SI.EndResize()
eq(SI.db.tracked[13].size, 60, "triangle resizes (13)")
eq(SI.db.tracked[14].size, 60, "triangle resizes the whole group (14)")
eq(SI.db.tracked[13].left, pivotX, "triangle keeps group left edge")
eq(SI.db.tracked[13].top, pivotY, "triangle keeps group top edge")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 60, "triangle keeps group flush")
eq(ShowItemsResizeHandle.points[1][4], pivotX + 120 + 3, "handle follows the new group edge")
SI.SetResizeMode(nil)
eq(ShowItemsResizeHandle:IsShown(), false, "handle hidden when resize mode is off")

-- spacing between attached windows
reset()
SI.Track({ 13, 14 })
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 40, "windows are flush without spacing")
SI.SetSpacing(10)
eq(SI.db.spacing, 10, "spacing is stored")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 50, "spacing separates attached windows")
eq(SI.db.tracked[14].top, SI.db.tracked[13].top, "spacing keeps the row aligned")
truthy(SI.db.tracked[14].group == SI.db.tracked[13].group and SI.db.tracked[13].group, "windows stay in one group when the spacing changes")
SI.SetSpacing(24)
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 64, "larger spacing")
SI.SetSpacing(100)
eq(SI.db.spacing, SI.MAX_SPACING, "spacing is limited")
SI.SetSpacing(0)
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 40, "spacing 0 makes the windows flush again")
SI.SetSpacing(6)
SI.Track({ 15 })
eq(SI.db.tracked[15].left, SI.db.tracked[14].left + 46, "a new window keeps the spacing")
-- spacing in a vertical group, with different sizes
reset()
SI.db.tracked[13] = { left = 600, top = 560, size = 40, moved = true, group = 1 }
SI.db.tracked[14] = { left = 600, top = 520, size = 40, moved = true, group = 1 }
SI.db.nextGroup = 2
SI.ApplyAll()
SI.SetSpacing(5)
eq(SI.db.tracked[14].top, 560 - 40 - 5, "spacing separates windows that are one above the other")
eq(SI.db.tracked[14].left, 600, "a vertical group stays aligned")
SI.SetSpacing(0)
eq(SI.db.tracked[14].top, 520, "a vertical group is flush again")
-- changing the spacing in combat waits for the end of combat
reset()
SI.Track({ 13, 14 })
mock.combat = true
SI.SetSpacing(12)
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 40, "spacing is not applied in combat")
mock.combat = false
fire("PLAYER_REGEN_ENABLED")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 52, "spacing is applied after combat")
-- the magnet aims for the spacing
reset()
SI.SetSpacing(8)
SI.Track({ 13 })
drag(13, 960, 540, 660, 540)
SI.Track({ 14 })
drag(14, 960, 540, 705, 532)
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 48, "magnet leaves the spacing between windows")
eq(SI.db.tracked[14].top, SI.db.tracked[13].top, "magnet still aligns the row")
truthy(SI.db.tracked[14].group and SI.db.tracked[14].group == SI.db.tracked[13].group, "magnet joins the group with a spacing")
SI.SetSpacing(0)
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 40, "a group made with a spacing becomes flush again")
-- the spacing belongs to the layout
reset()
SI.db.profiles, SI.db.snapshots = {}, {}
SI.SetSpacing(6)
SI.Track({ 13, 14 })
local gapProfile = SI.SaveProfile("Gap")
reset()
eq(SI.db.spacing, 0, "reset restores the default spacing")
SI.LoadProfile(gapProfile)
eq(SI.db.spacing, 6, "a profile restores the spacing")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 46, "a profile restores spaced windows")
SI.db.profiles, SI.db.snapshots = {}, {}
do
    local spaced = { tracked = {}, bindings = {}, spacing = 99 }
    SI.SanitizeDB(spaced)
    eq(spaced.spacing, SI.MAX_SPACING, "saved spacing is limited")
    spaced = { tracked = {}, bindings = {}, spacing = "x" }
    SI.SanitizeDB(spaced)
    eq(spaced.spacing, 0, "invalid saved spacing becomes 0")
end
-- screen clamp for a new tracker near the right edge
reset()
SI.Track({ 13 })
SI.db.tracked[13].left = 1900
SI.Track({ 14 })
eq(SI.db.tracked[14].left + SI.db.tracked[14].size, 1920, "group clamped to screen")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 40, "clamp keeps group flush")

-- combat queue
reset()
mock.combat = true
SI.Track({ 5 })
truthy(not SI.db.tracked[5], "track is deferred in combat")
mock.combat = false
fire("PLAYER_REGEN_ENABLED")
truthy(SI.db.tracked[5], "track applied after combat")

-- drag is blocked in combat
mock.combat = true
local leftBefore = SI.db.tracked[5].left
drag(5, 500, 500, 600, 600)
eq(SI.db.tracked[5].left, leftBefore, "no drag in combat")
mock.combat = false

-- bindings
SI.Untrack({ 5 })
SI.Track({ 13 })
SI.SetBinding(13, "CTRL-1")
truthy(mock.overrides["CTRL-1"], "override binding set")
eq(mock.overrides["CTRL-1"][1], "ShowItemsSlot13", "binding targets tracker")
SI.SetBinding(14, "CTRL-1")
truthy(SI.db.bindings[13] == nil and SI.db.bindings[14] == "CTRL-1", "duplicate key moves to the new slot")
SI.Untrack({ 13 })
truthy(mock.overrides["CTRL-1"] == nil, "untrack removes binding override")

-- bag scan: bags only, matching slot only
mock.bags = {
    [0] = {
        n = 3,
        { link = "ring1", id = 101, loc = "INVTYPE_FINGER", icon = 1 },
        { link = "boots", id = 102, loc = "INVTYPE_FEET", icon = 2 },
        { link = "trinket", id = 103, loc = "INVTYPE_TRINKET", icon = 3 },
    },
    [-1] = { n = 1, { link = "bankring", id = 104, loc = "INVTYPE_FINGER", icon = 4 } },
}
eq(#SI.ScanBags(11), 1, "ring slot finds one ring, not bank")
eq(#SI.ScanBags(8), 1, "feet slot finds boots")
eq(#SI.ScanBags(1), 0, "head slot finds nothing")

-- flyout and equip
reset()
SI.Track({ 13 })
SI.frames[13].scripts.PostClick(SI.frames[13], "RightButton")
truthy(ShowItemsFlyout:IsShown(), "flyout opens on right click")
local fp = ShowItemsFlyout.points[1]
eq(fp[1], "BOTTOMLEFT", "flyout sits above the row, left-aligned")
eq(fp[4], 940, "flyout left edge matches the group left edge")
eq(fp[5], 564, "flyout bottom is just above the group")
eq(SI.frames[13].emptyTexture, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket0", "stock slot texture for the empty slot")
local itemButton
for _, f in ipairs(mock.frames) do
    if f.parent == ShowItemsFlyout and f.item then itemButton = f end
end
truthy(itemButton, "flyout lists the trinket")
itemButton.scripts.OnClick(itemButton)
truthy(mock.lastEquip and mock.lastEquip[2] == 13 and mock.lastEquip[1] == "trinket", "click equips into the tracked slot")
truthy(not ShowItemsFlyout:IsShown(), "flyout closes after equip")

-- hover menu above a tracking window; left click uses the item
do
    reset()
    SI.Track({ 13 })
    local tracker = SI.frames[13]
    eq(tracker.attrs.type1, "macro", "left click runs a macro")
    eq(tracker.attrs.macrotext1, "/use 13", "left click uses the item in the slot")
    mock.bags = { [0] = { n = 4,
        { link = "t1", id = 901, loc = "INVTYPE_TRINKET", icon = 11 },
        { link = "boots", id = 902, loc = "INVTYPE_FEET", icon = 12 },
        { link = "t2", id = 903, loc = "INVTYPE_TRINKET", icon = 13 },
        { link = "t3", id = 904, loc = "INVTYPE_TRINKET", icon = 14, count = 2 },
    } }
    local hover = ShowItemsHoverMenu
    local function hoverItems()
        local list = {}
        for _, f in ipairs(mock.frames) do
            if f.parent == hover and f.entry and f:IsShown() then list[#list + 1] = f end
        end
        return list
    end
    truthy(hover and not hover:IsShown(), "the hover menu is closed at first")
    tracker.scripts.OnEnter(tracker)
    local listed = hoverItems()
    truthy(hover:IsShown() and #listed == 3, "hovering a tracker lists the three bag items that fit")
    eq(hover.h, 2 * 8 + 2 * 40 + 36, "the menu is as high as three items need")
    eq(hover.w, 2 * 8 + 36, "the menu is one column wide")
    local hp = hover.points[1]
    truthy(hp[1] == "BOTTOMRIGHT" and hp[3] == "TOPRIGHT", "the menu sits above the window")
    local ap = hp[2].points[1]
    truthy(ap[1] == "TOPLEFT" and ap[4] == 940 and ap[5] == 560, "the menu stands on the top edge of the window")
    eq(hover.anchor, tracker, "the menu stays open while the mouse is over the window")
    tracker.mouseOver = true
    tick()
    truthy(hover:IsShown(), "the menu stays while the mouse is over the window")
    tracker.mouseOver = false
    hover.mouseOver = true
    tick()
    truthy(hover:IsShown(), "the menu stays while the mouse is over it")
    hover.mouseOver = false
    tick()
    truthy(not hover:IsShown(), "the menu closes when the mouse is over neither")

    -- the size follows the number of items
    mock.bags[0][3], mock.bags[0][4] = nil, nil
    mock.bags[0].n = 2
    tracker.scripts.OnEnter(tracker)
    listed = hoverItems()
    truthy(#listed == 1 and hover.h == 52, "one item makes a menu for one item")

    -- a click equips the item and closes the menu
    mock.lastEquip = nil
    listed[1].scripts.OnClick(listed[1], "LeftButton")
    truthy(mock.lastEquip and mock.lastEquip[1] == "t1" and mock.lastEquip[2] == 13, "a click equips the item into the slot")
    truthy(not hover:IsShown(), "the menu closes after a pick")

    -- no matching items, no menu
    mock.bags = {}
    tracker.scripts.OnEnter(tracker)
    truthy(not hover:IsShown(), "no menu opens when the bags have nothing for the slot")

    -- the right click menu replaces the hover menu and blocks it while it is open
    mock.bags = { [0] = { n = 1, { link = "t1", id = 901, loc = "INVTYPE_TRINKET", icon = 11 } } }
    tracker.scripts.OnEnter(tracker)
    truthy(hover:IsShown(), "the hover menu is open again")
    tracker.scripts.PostClick(tracker, "RightButton")
    truthy(ShowItemsFlyout:IsShown() and not hover:IsShown(), "the right click menu closes the hover menu")
    tracker.scripts.OnEnter(tracker)
    truthy(not hover:IsShown(), "no hover menu while the right click menu is open")
    ShowItemsFlyout:Hide()

    -- no room above the window: the menu goes below it
    SI.db.tracked[13].top = 1075
    tracker.scripts.OnEnter(tracker)
    hp = hover.points[1]
    truthy(hover:IsShown() and hp[1] == "TOPRIGHT" and hp[3] == "BOTTOMRIGHT", "the menu goes below the window when there is no room above")
    SI.db.tracked[13].top = 560
    hover:Hide()
    mock.bags = {}
end

-- the tracker is clicked on release (the secure button needs both press and release registered)
do
    reset()
    SI.Track({ 13 })
    local tracker = SI.frames[13]
    local both = {}
    for _, kind in ipairs(tracker.clicks or {}) do both[kind] = true end
    truthy(both.AnyUp and both.AnyDown, "the tracker is registered for press and release")
    eq(tracker.attrs.useOnKeyDown, false, "the item is used when the button is released")
    ShowItemsFlyout:Hide()
    tracker.scripts.PostClick(tracker, "RightButton", true)
    truthy(not ShowItemsFlyout:IsShown(), "the right click menu does not open on press")
    tracker.scripts.PostClick(tracker, "RightButton", false)
    truthy(ShowItemsFlyout:IsShown(), "the right click menu opens on release")
    ShowItemsFlyout:Hide()
end

-- the tracking windows: the short tooltip (name and characteristics) where the name tip used to be
do
    reset()
    SI.Track({ 13 })
    local tracker = SI.frames[13]
    local tip = ShowItemsNameTip
    local trinketLines = {
        { left = "|cff1eff00Mock Trinket|r", r = 0.12, g = 1, b = 0 },
        { left = "Soulbound" },
        { left = "Trinket" },
        { left = "+6 Spirit" },
        { left = "|cff00ff00Use: Heals you.|r", r = 0, g = 1, b = 0, wrap = true },
        { left = "Requires Level 20" },
        { left = "Vendor", right = "1 2" },
    }
    mock.worn[13] = { id = 401, link = "|cff1eff00|Hitem:401::::::::|h[Mock Trinket]|h|r" }
    mock.tipLines = trinketLines
    GameTooltip:Hide()
    tracker.scripts.OnEnter(tracker)
    truthy(GameTooltip:IsShown(), "hovering a window shows the item tooltip")
    truthy(not tip:IsShown(), "the name tip is not shown for a worn item")
    eq(GameTooltip:NumLines(), 3, "the tooltip keeps the name, the stat and the effect")
    eq(GameTooltip.lines[1].left, "|cff1eff00Mock Trinket|r", "the first line is the name")
    eq(GameTooltip.lines[2].left, "+6 Spirit", "a characteristic stays")
    eq(GameTooltip.lines[3].left, "|cff00ff00Use: Heals you.|r", "an effect stays")
    local tp = GameTooltip.points[1]
    truthy(#GameTooltip.points == 1 and tp[1] == "TOPLEFT" and tp[2] == tracker and tp[3] == "BOTTOMLEFT", "the tooltip hangs from the bottom left corner of the window")
    truthy(tp[4] == 0 and tp[5] < 0, "the tooltip keeps a small gap below the window")
    eq(tp[5], -5, "the gap is the one of the name tip")
    ShoppingTooltip1:Show()
    truthy(not ShoppingTooltip1:IsShown(), "no comparison tooltip next to it")
    tracker.scripts.OnLeave(tracker)
    truthy(not GameTooltip:IsShown(), "the tooltip hides with the mouse")
    -- the gap is measured in the pixels of the window, whatever the scale of the tooltip
    tracker.scale = 2
    tracker.scripts.OnEnter(tracker)
    eq(GameTooltip.points[1][5], -10, "the gap follows the scale of the window")
    tracker.scale = nil
    tracker.scripts.OnLeave(tracker)

    -- an empty slot still shows the name of the slot as a small tip
    mock.worn[13] = nil
    mock.tipLines = nil
    tracker.scripts.OnEnter(tracker)
    eq(tip.text.text, SI.SLOTS[13].name, "an empty slot shows the slot name")
    truthy(not GameTooltip:IsShown(), "and no item tooltip")
    local np = tip.points[1]
    truthy(np[1] == "TOPLEFT" and np[2] == tracker and np[3] == "BOTTOMLEFT" and np[4] == 0 and np[5] == -5, "the name tip stays where it was, under the window")
    eq(tip.backdrop and tip.backdrop.bgFile, "Interface\\DialogFrame\\UI-DialogBox-Background", "the name tip has the gray of the character window menu")
    tracker.scripts.OnLeave(tracker)
    truthy(not tip:IsShown(), "the name tip hides with the mouse")
    -- moving from an empty slot to a worn one leaves no name tip behind
    tracker.scripts.OnEnter(tracker)
    mock.worn[13] = { id = 401, link = "|cff1eff00|Hitem:401::::::::|h[Mock Trinket]|h|r" }
    mock.tipLines = trinketLines
    tracker.scripts.OnEnter(tracker)
    truthy(GameTooltip:IsShown() and not tip:IsShown(), "the item tooltip replaces the name tip")
    tracker.scripts.OnLeave(tracker)
    mock.tipLines = nil
    mock.worn[13] = nil

    -- the menu above a window: the short tooltip next to the icon
    mock.bags = { [0] = { n = 1, { link = "|cff0070dd|Hitem:901::::::::|h[Blue Trinket]|h|r", id = 901, loc = "INVTYPE_TRINKET", icon = 11 } } }
    mock.tipLines = {
        { left = "|cff0070ddBlue Trinket|r", r = 0, g = 0.44, b = 0.87 },
        { left = "Binds when picked up" },
        { left = "Trinket" },
        { left = "+9 Intellect" },
        { left = "Sell Price: 5" },
        { left = "Estimated disenchant value", right = "13 59" },
    }
    tracker.scripts.OnEnter(tracker)
    tracker.scripts.OnLeave(tracker) -- the mouse goes from the window to the menu
    local button
    for _, f in ipairs(mock.frames) do
        if f.parent == ShowItemsHoverMenu and f.entry and f:IsShown() then button = f end
    end
    ShoppingTooltip1.shown = true
    button.scripts.OnEnter(button)
    truthy(GameTooltip:IsShown() and not tip:IsShown(), "hovering a menu item shows the item tooltip, not the name tip")
    eq(GameTooltip:NumLines(), 2, "the menu item tooltip keeps the name and the stat")
    eq(GameTooltip.lines[2].left, "+9 Intellect", "its characteristic stays")
    truthy(not ShoppingTooltip1:IsShown(), "no comparison tooltip for a menu item")
    local bp = GameTooltip.points[1]
    truthy(#GameTooltip.points == 1 and bp[1] == "LEFT" and bp[2] == button and bp[3] == "RIGHT" and bp[4] == 4 and bp[5] == 0,
        "the tooltip stands where the name tip did, to the right of the icon")
    truthy(GameTooltip:GetFrameLevel() > button:GetFrameLevel(), "the tooltip is above the menu")
    button.scripts.OnLeave(button)
    truthy(not GameTooltip:IsShown(), "the tooltip hides when the mouse leaves the menu item")
    button.scripts.OnEnter(button)
    button.scripts.OnClick(button, "LeftButton")
    truthy(not GameTooltip:IsShown(), "the tooltip hides when the item is picked")
    tracker.scripts.OnEnter(tracker)
    tracker.scripts.OnLeave(tracker)
    button.scripts.OnEnter(button)
    ShowItemsHoverMenu:Hide()
    truthy(not GameTooltip:IsShown(), "the tooltip goes with the menu")
    mock.tipLines = nil
    mock.bags = {}
end

-- menu of bag items over the character window slots (the ItemRack menu)
do
    reset()
    local menu = ShowItemsCharacterMenu
    local trinket, head, mainHand = CharacterTrinket0Slot, CharacterHeadSlot, CharacterMainHandSlot
    mock.bags = { [0] = { n = 4,
        { link = "|cff0070dd|Hitem:901::::::::|h[Blue Trinket]|h|r", id = 901, loc = "INVTYPE_TRINKET", icon = 11 },
        { link = "boots", id = 902, loc = "INVTYPE_FEET", icon = 12 },
        { link = "t2", id = 903, loc = "INVTYPE_TRINKET", icon = 13 },
        { link = "helm", id = 905, loc = "INVTYPE_HEAD", icon = 15 },
    } }
    local function items()
        local list = {}
        for _, f in ipairs(mock.frames) do
            if f.parent == menu and f.entry and f:IsShown() then list[#list + 1] = f end
        end
        return list
    end
    truthy(menu and not menu:IsShown(), "the character window menu is closed at first")

    -- hovering a slot lists the bag items that fit it, in the ItemRack look
    trinket.scripts.OnEnter(trinket)
    truthy(menu:IsShown() and #items() == 2, "hovering a slot lists the bag items that fit it")
    eq(menu.backdrop and menu.backdrop.bgFile, "Interface\\DialogFrame\\UI-DialogBox-Background", "the menu has the gray ItemRack menu look")
    eq(menu.anchor, trinket, "the menu belongs to the slot")
    eq(menu.points[1][1], "TOPLEFT", "a right column slot opens its menu to the right")
    eq(menu.points[1][3], "TOPRIGHT", "the menu starts at the right edge of the slot")

    -- the glow around the frame of the menu
    local glow
    for _, f in ipairs(mock.frames) do
        if f.parent == menu and f.kind == "Frame" and f.scripts.OnUpdate then glow = f end
    end
    truthy(glow and glow:IsShown(), "the glow is shown with the menu")
    eq(glow.alpha, 0.75, "the glow is visible at 75%")
    local gp1, gp2 = glow.points[1], glow.points[2]
    truthy(gp1[2] == menu and gp1[1] == "TOPLEFT" and gp1[4] < 0 and gp1[5] > 0, "the glow starts outside the top left corner of the frame")
    truthy(gp2[2] == menu and gp2[1] == "BOTTOMRIGHT" and gp2[4] > 0 and gp2[5] < 0, "the glow ends outside the bottom right corner of the frame")
    eq(gp1[4], -gp2[4], "the glow reaches out equally on both sides")
    eq(glow.strata, "TOOLTIP", "the glow is in the tooltip strata")
    truthy(glow:GetFrameLevel() > menu:GetFrameLevel() and glow:GetFrameLevel() < items()[1]:GetFrameLevel(), "the glow is above the frame and below the item buttons")
    local parts = 0
    for _, f in ipairs(mock.frames) do
        if f.parent == glow and f.kind == "Texture" and f.texture == "Interface\\AddOns\\ShowItems\\Textures\\ShowItemsGlow" then parts = parts + 1 end
    end
    eq(parts, 8, "the glow is cut into four corners and four edges that follow the frame")
    local before = glow.scripts.OnUpdate and { glow.parts[1].vertex[1], glow.parts[1].vertex[2], glow.parts[1].vertex[3] }
    glow.scripts.OnUpdate(glow, 0.4)
    local after = glow.parts[1].vertex
    truthy(before[1] ~= after[1] or before[2] ~= after[2] or before[3] ~= after[3], "the glow shimmers")
    for _, p in ipairs(glow.parts) do
        truthy(p.vertex[1] >= 1 - 1e-9 and p.vertex[2] >= 0.82 - 1e-9 and p.vertex[2] <= 0.97 + 1e-9, "the shimmer stays between gold and pale yellow")
    end
    -- a bigger menu: the glow follows the frame because it is anchored to it
    mock.bags[0][5] = { link = "t3", id = 907, loc = "INVTYPE_TRINKET", icon = 17 }
    mock.bags[0].n = 5
    trinket.scripts.OnEnter(trinket)
    eq(glow.points[1][2], menu, "the glow stays anchored to the whole frame when the menu grows")
    truthy(glow:IsShown(), "the glow stays shown when the menu moves to another slot")
    mock.bags[0][5] = nil
    mock.bags[0].n = 4
    menu:Hide()
    truthy(not glow:IsShown(), "the glow hides with the menu")
    trinket.scripts.OnEnter(trinket)

    -- the panel and the border are 20% darker, the item buttons are not
    eq(menu.backdropColor[1], 0.8, "the menu panel is 20% darker (red)")
    eq(menu.backdropColor[2], 0.8, "the menu panel is 20% darker (green)")
    eq(menu.backdropColor[3], 0.8, "the menu panel is 20% darker (blue)")
    eq(menu.backdropColor[4], 1, "the menu panel keeps its opacity")
    eq(menu.borderColor[1], 0.6 * 0.8, "the menu border is 20% darker")
    truthy(ShowItemsContextMenu.backdropColor[1] == 1 and ShowItemsContextMenu.borderColor[1] == 0.6, "the other menus keep their color")
    truthy(items()[1].border.vertex and items()[1].border.vertex[1] == 1, "the item buttons are not darkened")

    -- the Glow option: off hides the glow of the open menu and keeps it off for the next ones
    SI.SetGlow(false)
    eq(SI.db.glow, false, "SetGlow(false) is saved")
    truthy(not glow:IsShown() and menu:IsShown(), "turning the glow off removes it from the open menu")
    menu:Hide()
    trinket.scripts.OnEnter(trinket)
    truthy(menu:IsShown() and not glow:IsShown(), "the menu opens without the glow while the option is off")
    eq(menu.backdropColor[1], 0.8, "the menu stays darker without the glow")
    SI.SetGlow(true)
    truthy(glow:IsShown(), "turning the glow on shows it on the open menu")
    menu:Hide()
    SI.SetGlow(true)
    truthy(not glow:IsShown(), "the glow does not show without the menu")
    trinket.scripts.OnEnter(trinket)
    truthy(glow:IsShown(), "the glow is back for the next menu")

    -- saved data: on by default, bad values fall back to on, only false turns it off
    eq(SI.NewDB().glow, true, "a new character has the glow on")
    local glowDb = SI.NewDB()
    glowDb.glow = "no"
    SI.SanitizeDB(glowDb)
    eq(glowDb.glow, true, "a bad glow value falls back to on")
    glowDb.glow = false
    SI.SanitizeDB(glowDb)
    eq(glowDb.glow, false, "a saved off stays off")
    local oldDb = SI.NewDB()
    oldDb.glow = nil
    SI.SanitizeDB(oldDb)
    eq(oldDb.glow, true, "a character saved before the option existed gets the glow on")

    -- above the tooltips
    eq(menu.strata, "TOOLTIP", "the menu is in the tooltip strata")
    truthy(menu:GetFrameLevel() > GameTooltip:GetFrameLevel(), "the menu is above the item tooltip")
    truthy(items()[1]:GetFrameLevel() > GameTooltip:GetFrameLevel(), "the menu buttons are above the item tooltip")

    -- it stays while the mouse is over the slot or the menu, and closes otherwise
    trinket.mouseOver = true
    tick()
    truthy(menu:IsShown(), "the menu stays while the mouse is over the slot")
    trinket.mouseOver = false
    menu.mouseOver = true
    tick()
    truthy(menu:IsShown(), "the menu stays while the mouse is over it")
    menu.mouseOver = false
    tick()
    truthy(not menu:IsShown(), "the menu closes when the mouse is over neither")

    -- every slot opens its menu to the right of the slot
    head.scripts.OnEnter(head)
    eq(menu.points[1][1], "TOPLEFT", "a left column slot opens its menu to the right too")
    eq(menu.points[1][3], "TOPRIGHT", "the menu starts at the right edge of the left column slot")
    eq(menu.anchor, head, "the menu belongs to the left column slot")
    eq(#items(), 1, "only the items of the slot are listed")
    menu:Hide()
    mock.bags[0][5] = { link = "sword", id = 906, loc = "INVTYPE_2HWEAPON", icon = 16 }
    mock.bags[0].n = 5
    mainHand.scripts.OnEnter(mainHand)
    eq(menu.points[1][1], "TOPLEFT", "a weapon slot opens its menu to the right too")
    eq(menu.points[1][3], "TOPRIGHT", "the menu starts at the right edge of the weapon slot")
    menu:Hide()
    mock.bags[0][5] = nil
    mock.bags[0].n = 4

    -- a click equips the item and closes the menu
    trinket.scripts.OnEnter(trinket)
    mock.lastEquip = nil
    local first = items()[1]
    first.scripts.OnClick(first, "LeftButton")
    truthy(mock.lastEquip and mock.lastEquip[1] == "|cff0070dd|Hitem:901::::::::|h[Blue Trinket]|h|r" and mock.lastEquip[2] == 13, "a click equips the item into the slot")
    truthy(not menu:IsShown(), "the menu closes after a pick")

    -- an item in the menu shows its full tooltip above the frame of the menu, its left edge on the left edge of the icon
    trinket.scripts.OnEnter(trinket)
    first = items()[1]
    local baseLevel = GameTooltip:GetFrameLevel()
    local anchor = ShowItemsCharacterMenuTipAnchor
    first.GetPoint = function() return "TOPLEFT", menu, "TOPLEFT", 48, -8 end -- the icon is in the second column
    first.scripts.OnEnter(first)
    truthy(GameTooltip:IsShown(), "hovering a menu item shows the item tooltip")
    truthy(not ShowItemsNameTip:IsShown(), "the name tip is not used in this menu")
    local tpt = GameTooltip.points[1]
    truthy(#GameTooltip.points == 1 and tpt[1] == "BOTTOMLEFT" and tpt[2] == anchor and tpt[3] == "TOPLEFT" and tpt[4] == 0 and tpt[5] == 0,
        "the tooltip stands on the anchor on the top edge of the menu frame")
    local ap = anchor.points[1]
    truthy(#anchor.points == 1 and ap[1] == "TOPLEFT" and ap[2] == menu and ap[3] == "TOPLEFT", "the anchor is on the top edge of the menu")
    eq(ap[4], 48, "the anchor is above the left edge of the icon")
    truthy(ap[5] > 0, "the tooltip stands a little above the frame line, not on the icon")
    first.GetPoint = nil
    truthy(GameTooltip:GetFrameLevel() > items()[#items()]:GetFrameLevel(), "the tooltip is above the menu buttons")
    -- a tall tooltip is scaled down to fit between the icon and the top of the screen (screen 1080 high)
    eq(GameTooltip:GetScale(), 1, "a tooltip that fits keeps its scale")
    GameTooltip.h = 400
    anchor.GetTop = function() return 600 end
    first.scripts.OnEnter(first)
    eq(GameTooltip:GetScale(), 1, "a tooltip with room above the icon keeps its scale")
    anchor.GetTop = function() return 800 end
    first.scripts.OnEnter(first)
    truthy(math.abs(GameTooltip:GetScale() - (1080 - 800 - 4) / 400) < 1e-6, "a tooltip without room above the icon is scaled to fit")
    anchor.GetTop = function() return 1000 end
    first.scripts.OnEnter(first)
    eq(GameTooltip:GetScale(), 0.5, "the tooltip is never scaled below the minimum")
    anchor.GetTop = function() return 800 end
    GameTooltip.h = 500
    GameTooltip.scripts.OnUpdate(GameTooltip, 0.1)
    truthy(math.abs(GameTooltip:GetScale() - (1080 - 800 - 4) / 500) < 1e-6, "lines added later are taken into account")
    anchor.GetTop = function() return 600 end
    GameTooltip.h = 400
    first.scripts.OnEnter(first)
    eq(GameTooltip:GetScale(), 1, "the tooltip gets its full size back where there is room")
    -- the game pushed the tooltip down over the icon (it keeps 20 px from the top edge): the real margin is measured
    anchor.GetTop = function() return 800 end
    GameTooltip.GetTop = function(self) return 1060 / self:GetScale() end
    GameTooltip.GetBottom = function(self) return (1060 - 400 * self:GetScale()) / self:GetScale() end
    first.scripts.OnEnter(first)
    truthy(math.abs(GameTooltip:GetScale() - (1080 - 800 - 4) / 400) < 1e-6, "the first estimate uses the smallest margin")
    for _ = 1, 3 do GameTooltip.scripts.OnUpdate(GameTooltip, 0.1) end
    truthy(math.abs(GameTooltip:GetScale() - (1080 - 800 - 4) / 400) < 1e-6, "the position is not read before the tooltip settled")
    GameTooltip.scripts.OnUpdate(GameTooltip, 0.1)
    truthy(math.abs(GameTooltip:GetScale() - (1080 - 800 - 21) / 400) < 1e-6, "the margin the game keeps at the top of the screen is taken into account")
    GameTooltip.GetTop, GameTooltip.GetBottom = nil, nil
    anchor.GetTop = function() return 800 end
    first.scripts.OnEnter(first)
    first.scripts.OnLeave(first)
    eq(GameTooltip:GetScale(), 1, "the tooltip gets its own scale back when it hides")
    anchor.GetTop = nil
    GameTooltip.h = 0
    first.scripts.OnEnter(first)

    -- only the name and the characteristics stay in the tooltip
    local function tipTexts()
        local list = {}
        for i, l in ipairs(GameTooltip.lines) do list[i] = l.right and (l.left .. " | " .. l.right) or l.left end
        return list
    end
    mock.tipLines = {
        { left = "|cff1eff00Azure Silk Belt|r", r = 0.12, g = 1, b = 0 },
        { left = "Soulbound" },
        { left = "Waist", right = "Cloth" },
        { left = "26 Armor" },
        { left = "+5 Stamina" },
        { left = "|cff00ff00Equip: Increases swim speed by 15%.|r", r = 0, g = 1, b = 0, wrap = true },
        { left = "Durability 25 / 25" },
        { left = "Requires Level 30" },
        { left = "|cff00ff00<Made by Good Omens>|r" },
        { left = "Cannot change equip status while in combat" },
        { left = "Vendor", right = "14 88" },
        { left = "Whats in your Loot?" },
        { left = "Estimated disenchant value (Auctionator)", right = "13 59" },
    }
    first.scripts.OnEnter(first)
    local texts = tipTexts()
    eq(#texts, 4, "the tooltip keeps four lines of the belt")
    eq(texts[1], "|cff1eff00Azure Silk Belt|r", "the first line is the name")
    eq(GameTooltip.lines[1].g, 1, "the name keeps its color")
    eq(texts[2], "26 Armor", "armor stays")
    eq(texts[3], "+5 Stamina", "a characteristic stays")
    eq(texts[4], "|cff00ff00Equip: Increases swim speed by 15%.|r", "the equip effect stays")
    truthy(GameTooltip.lines[4].wrap, "the equip line keeps its wrapping")
    truthy(GameTooltip:IsShown(), "the tooltip is shown after it was rebuilt")
    eq(GameTooltip:NumLines(), 4, "the tooltip really has the four lines")
    -- a line added by another addon later is removed at the next update, the kept lines are not duplicated
    GameTooltip:AddLine("Late addon line")
    GameTooltip.scripts.OnUpdate(GameTooltip, 0.1)
    texts = tipTexts()
    eq(#texts, 4, "a line added later is removed again")
    eq(texts[2], "26 Armor", "the kept lines stay the same")
    mock.called.ClearLines = nil
    GameTooltip.scripts.OnUpdate(GameTooltip, 0.1)
    truthy(not mock.called.ClearLines, "the tooltip is not rebuilt again while nothing was added")
    -- a weapon: damage and speed, damage per second, effects and block stay; slot, type and the rest go
    mock.tipLines = {
        { left = "Gnarled Staff" },
        { left = "Binds when equipped" },
        { left = "Main Hand", right = "Staff" },
        { left = "109 - 163 Damage", right = "Speed 2.60" },
        { left = "(52.0 damage per second)" },
        { left = "+9 Intellect" },
        { left = "-3 Spirit" },
        { left = "12 Block" },
        { left = "Use: Heals you", wrap = true },
        { left = "Chance on hit: Slows the target." },
        { left = "Equip: Rests." },
        { left = "Sell Price: 1g" },
    }
    first.scripts.OnEnter(first)
    texts = tipTexts()
    eq(#texts, 9, "a weapon keeps name, damage, dps, stats, block and effects")
    eq(texts[2], "109 - 163 Damage | Speed 2.60", "the speed stays on the damage line")
    eq(texts[3], "(52.0 damage per second)", "damage per second stays")
    eq(texts[7], "Use: Heals you", "the use effect stays")
    -- when the game gives no lines the tooltip is left alone
    mock.tipLines = nil
    first.scripts.OnEnter(first)
    eq(GameTooltip:NumLines(), 0, "an empty tooltip is not touched")
    mock.tipLines = { { left = "Plain Name" }, { left = "Soulbound" } }
    first.scripts.OnEnter(first)
    eq(#tipTexts(), 1, "an item with nothing to show keeps only its name")
    mock.tipLines = nil
    first.scripts.OnEnter(first)

    -- the comparison tooltips of the game never show next to it, whenever the game shows them
    ShoppingTooltip1:Show()
    truthy(not ShoppingTooltip1:IsShown(), "a comparison tooltip shown by the game is hidden at once")
    ShoppingTooltip1.shown, ShoppingTooltip2.shown = true, true
    GameTooltip.scripts.OnUpdate(GameTooltip, 0.1)
    truthy(not ShoppingTooltip1:IsShown() and not ShoppingTooltip2:IsShown(), "comparison tooltips that stayed visible are hidden on update")
    first.scripts.OnLeave(first)
    truthy(not GameTooltip:IsShown(), "the tooltip hides when the mouse leaves the icon")
    eq(GameTooltip:GetFrameLevel(), baseLevel, "the tooltip gets its own frame level back")
    -- other tooltips keep their comparison
    GameTooltip:SetOwner(trinket)
    GameTooltip:Show()
    ShoppingTooltip1:Show()
    truthy(ShoppingTooltip1:IsShown(), "comparison tooltips of other tooltips are left alone")
    ShoppingTooltip1:Hide()
    GameTooltip:Hide()
    first.scripts.OnEnter(first)
    first.scripts.OnClick(first, "LeftButton")
    truthy(not GameTooltip:IsShown(), "the tooltip hides when the item is picked")
    menu:Hide()

    -- in combat the pick is queued
    mock.combat = true
    trinket.scripts.OnEnter(trinket)
    truthy(menu:IsShown(), "the menu opens in combat")
    first = items()[1]
    mock.lastEquip = nil
    first.scripts.OnClick(first, "LeftButton")
    truthy(mock.lastEquip == nil and SI.QueuedItem(13) and SI.QueuedItem(13).id == 901, "a pick in combat is queued")
    mock.combat = false
    -- out of combat an equip clears the queue entry of the slot
    SI.EquipOrQueue({ bag = 0, index = 1, id = 901, link = "t1", icon = 11 }, 13)
    truthy(SI.QueuedItem(13) == nil, "the queue of the slot is empty again")

    -- no matching items, no menu
    mock.bags = {}
    trinket.scripts.OnEnter(trinket)
    truthy(not menu:IsShown(), "no menu opens when the bags have nothing for the slot")
    mock.bags = { [0] = { n = 1, { link = "t1", id = 901, loc = "INVTYPE_TRINKET", icon = 11 } } }

    -- Ctrl and the Track / Untrack menu replace this menu
    mock.mods.ctrl = true
    trinket.scripts.OnEnter(trinket)
    truthy(not menu:IsShown(), "no menu while Ctrl is held")
    mock.mods.ctrl = false
    trinket.scripts.OnEnter(trinket)
    truthy(menu:IsShown(), "the menu is open again without Ctrl")
    selectClick(trinket)
    truthy(ShowItemsContextMenu:IsShown() and not menu:IsShown(), "Ctrl+right click closes the menu of items and opens the Track / Untrack menu")
    trinket.scripts.OnEnter(trinket)
    head.scripts.OnEnter(head)
    truthy(not menu:IsShown(), "no menu of items while the Track / Untrack menu is open")
    SI.HideContext()
    trinket.scripts.OnEnter(trinket)
    truthy(menu:IsShown(), "the menu of items works again once the Track / Untrack menu is closed")

    -- pressing the slot closes the menu
    trinket.scripts.PreClick(trinket, "LeftButton")
    truthy(not menu:IsShown(), "pressing the slot closes the menu")

    -- an item on the cursor, the addon switched off, the window closed
    local hadCursor = CursorHasItem
    CursorHasItem = function() return true end
    trinket.scripts.OnEnter(trinket)
    truthy(not menu:IsShown(), "no menu while an item is on the cursor")
    CursorHasItem = hadCursor
    SI.db.enabled = false
    trinket.scripts.OnEnter(trinket)
    truthy(not menu:IsShown(), "no menu while the addon is switched off")
    SI.db.enabled = true
    trinket.scripts.OnEnter(trinket)
    truthy(menu:IsShown(), "the menu is back when the addon is switched on")
    CharacterFrame.scripts.OnHide(CharacterFrame)
    truthy(not menu:IsShown(), "closing the character window closes the menu")
    mock.bags = {}
end

-- favorite items: the star on the icons of the character window menu
do
    reset()
    local menu = ShowItemsCharacterMenu
    local trinket = CharacterTrinket0Slot
    local day = 24 * 60 * 60
    local now = 1000000
    local realTime = _G.time
    _G.time = function() return now end
    SI.db.favorites, SI.db.nextFavorite = {}, 1
    mock.bags = { [0] = { n = 4,
        { link = "|cff0070dd|Hitem:901::::::::|h[Blue Trinket]|h|r", id = 901, loc = "INVTYPE_TRINKET", icon = 11 },
        { link = "t2", id = 903, loc = "INVTYPE_TRINKET", icon = 13 },
        { link = "t3", id = 907, loc = "INVTYPE_TRINKET", icon = 17 },
        { link = "boots", id = 902, loc = "INVTYPE_FEET", icon = 12 },
    } }
    local function listed()
        local list = {}
        for _, b in ipairs(menu.buttons) do
            if b:IsShown() and b.entry then list[#list + 1] = b end
        end
        return list
    end
    local function order()
        local ids = {}
        for i, b in ipairs(listed()) do ids[i] = b.entry.itemId end
        return table.concat(ids, ",")
    end
    local function open()
        menu:Hide()
        trinket.scripts.OnEnter(trinket)
    end

    -- a new character has no favorites
    eq(next(SI.NewDB().favorites), nil, "a new character has no favorites")
    eq(SI.NewDB().nextFavorite, 1, "the first favorite gets number one")

    -- every icon has an empty star in its top right corner
    open()
    eq(order(), "901,903,907", "without favorites the items keep the order of the bags")
    for i, b in ipairs(listed()) do
        local star = b.star
        truthy(star and star:IsShown() and star.parent == b, "icon " .. i .. " has a star")
        truthy(star.points[1][1] == "TOPRIGHT" and star.points[1][2] == b and star.points[1][3] == "TOPRIGHT", "the star is in the top right corner of icon " .. i)
        eq(star.texture.texCoord[1], 0, "the star of icon " .. i .. " is empty")
        eq(star.itemId, b.entry.itemId, "the star knows its item")
        truthy(star:GetFrameLevel() > b:GetFrameLevel(), "the star is above its icon")
        eq(star.strata, "TOOLTIP", "the star is in the tooltip strata")
    end

    -- a click on the star fills it, marks the item and does not equip it
    local third = listed()[3]
    mock.lastEquip = nil
    third.star.scripts.OnClick(third.star, "LeftButton")
    truthy(SI.IsFavorite(907), "the star marks the item")
    eq(third.star.texture.texCoord[1], 0.5, "the star is filled")
    eq(third.star.texture.vertex[2], 0.82, "a favorite star is gold")
    truthy(mock.lastEquip == nil and menu:IsShown(), "a click on the star does not equip the item and keeps the menu")
    eq(order(), "901,903,907", "the order does not change under the cursor")
    open()
    eq(order(), "907,901,903", "a favorite is first the next time the menu opens")
    eq(listed()[1].star.texture.texCoord[1], 0.5, "the star of a favorite is filled after reopening")
    eq(listed()[2].star.texture.texCoord[1], 0, "the other stars stay empty")

    -- the one marked earlier stays first
    listed()[3].star.scripts.OnClick(listed()[3].star, "LeftButton")
    open()
    eq(order(), "907,903,901", "of two favorites the one marked earlier is first")
    eq(SI.db.favorites[907].seq < SI.db.favorites[903].seq, true, "the order is kept in the saved data")
    -- unmarking and marking again puts the item last among the favorites
    listed()[1].star.scripts.OnClick(listed()[1].star, "LeftButton")
    truthy(not SI.IsFavorite(907), "a second click unmarks the item")
    open()
    eq(order(), "903,901,907", "an unmarked item goes back to the usual order")
    local last = listed()[3]
    last.star.scripts.OnClick(last.star, "LeftButton")
    open()
    eq(order(), "903,907,901", "an item marked again comes after the favorites marked before")

    -- the star keeps the tooltip: the mouse leaves the icon when it is over the star
    local first = listed()[1]
    GameTooltip:Hide()
    first.star.scripts.OnEnter(first.star)
    truthy(GameTooltip:IsShown(), "the tooltip stays while the mouse is over the star")
    eq(first.star.texture.vertex[2], 0.82, "a star under the mouse is gold")
    first.star.scripts.OnLeave(first.star)
    truthy(not GameTooltip:IsShown(), "the tooltip hides when the mouse leaves the star")

    -- a click on the icon still equips the item
    mock.lastEquip = nil
    first.scripts.OnClick(first, "LeftButton")
    truthy(mock.lastEquip and mock.lastEquip[2] == 13, "a click on the icon equips the item")

    -- a favorite that is not in the bags is not listed, and it is not forgotten at once
    SI.SetFavorite(555, true)
    open()
    eq(order(), "903,907,901", "a favorite that is not in the bags is not listed")
    eq(SI.db.favorites[555].missing, now, "the time it was first missed is saved")
    now = now + day - 1
    open()
    truthy(SI.IsFavorite(555), "a favorite is kept for a day")
    now = now + 1
    open()
    truthy(not SI.IsFavorite(555), "a favorite that was missing for a day is removed")
    eq(order(), "903,907,901", "the menu is the same")

    -- it comes back as a favorite when it returns to the bags, and the time starts again
    local bag = mock.bags[0]
    local taken = bag[2]
    bag[2] = nil
    open()
    eq(order(), "907,901", "the favorite is not listed while it is not in the bags")
    truthy(SI.IsFavorite(903) and SI.db.favorites[903].missing == now, "it stays a favorite")
    now = now + day - 10
    bag[2] = taken
    open()
    eq(order(), "903,907,901", "it is first again when it returns to the bags")
    eq(SI.db.favorites[903].missing, nil, "its missing time is cleared")
    now = now + 3 * day
    open()
    truthy(SI.IsFavorite(903), "a favorite that is in the bags is kept for good")

    -- worn items are not missing
    bag[2] = nil
    mock.worn[13] = { id = 903, link = "t2" }
    now = now + 3 * day
    open()
    truthy(SI.IsFavorite(903) and SI.db.favorites[903].missing == nil, "a worn favorite is not missing")
    mock.worn[13] = nil
    open()
    eq(SI.db.favorites[903].missing, now, "it starts to count when it is neither worn nor in the bags")
    now = now + day
    open()
    truthy(not SI.IsFavorite(903), "and it goes after a day")
    bag[2] = taken

    -- bags that cannot be read (not loaded) do not wipe the favorites
    SI.SetFavorite(907, true)
    SI.db.favorites[907].missing = now - 5 * day
    local saved = mock.bags
    mock.bags = {}
    now = now + 5 * day
    open()
    truthy(SI.IsFavorite(907) and SI.db.favorites[907].missing == now - 10 * day, "unreadable bags change nothing")
    mock.bags = saved

    -- a clock that went back does not remove anything: the time of the first miss starts again
    local taken3 = bag[3]
    bag[3] = nil
    SI.db.favorites[907].missing = now + 100
    open()
    truthy(SI.IsFavorite(907) and SI.db.favorites[907].missing == now, "a missing time in the future is replaced by now")
    bag[3] = taken3
    open()
    eq(SI.db.favorites[907].missing, nil, "an item that is back in the bags is not missing")

    -- saved data: wrong values are dropped, the counter stays ahead of the numbers in use
    local favDb = SI.NewDB()
    favDb.favorites = { [901] = { seq = 4 }, [902] = { seq = "x" }, bad = { seq = 1 }, [903] = "no", [904] = { seq = 2, missing = "no" }, [905] = { seq = 9, missing = 50 } }
    favDb.nextFavorite = 3
    SI.SanitizeDB(favDb)
    truthy(favDb.favorites[901] and favDb.favorites[904] and favDb.favorites[905], "valid favorites are kept")
    truthy(not favDb.favorites[902] and not favDb.favorites.bad and not favDb.favorites[903], "wrong favorites are dropped")
    eq(favDb.favorites[904].missing, nil, "a wrong missing time is dropped")
    eq(favDb.favorites[905].missing, 50, "a good missing time is kept")
    eq(favDb.nextFavorite, 10, "the counter stays ahead of the numbers in use")
    local oldFavDb = SI.NewDB()
    oldFavDb.favorites, oldFavDb.nextFavorite = nil, nil
    SI.SanitizeDB(oldFavDb)
    truthy(type(oldFavDb.favorites) == "table" and oldFavDb.nextFavorite == 1, "a character saved before the favorites gets an empty list")

    -- Reset all does not touch the favorites
    SI.SetFavorite(901, true)
    SI.ResetAll()
    truthy(SI.IsFavorite(901), "Reset all keeps the favorites")

    -- the look of the star: light for a usual item, gold for a favorite and under the mouse
    local function byId(id)
        for _, b in ipairs(listed()) do
            if b.entry.itemId == id then return b end
        end
    end
    SI.SetFavorite(907, true)
    SI.SetFavorite(903, false)
    open()
    local fav, plain = byId(907), byId(903)
    eq(fav.star.texture.texture, "Interface\\AddOns\\ShowItems\\Textures\\ShowItemsStar", "the star is the texture of the addon")
    truthy(fav.star.w == 18 and fav.star.h == 18, "the star is 18 px on an icon of 36 px")
    eq(fav.star.texture.texCoord[1], 0.5, "the star of a favorite is the filled half of the texture")
    eq(fav.star.texture.vertex[2], 0.82, "the star of a favorite is gold")
    eq(fav.star:GetAlpha(), 1, "the star of a favorite is fully visible")
    eq(plain.star.texture.texCoord[1], 0, "the star of a usual item is the empty half of the texture")
    eq(plain.star.texture.vertex[1], 0.95, "the empty star is light")
    eq(plain.star:GetAlpha(), 0.9, "the empty star is almost fully visible")
    plain.star.scripts.OnEnter(plain.star)
    truthy(plain.star.texture.vertex[2] == 0.82 and plain.star:GetAlpha() == 1, "an empty star under the mouse turns gold")
    eq(plain.star.texture.texCoord[1], 0, "and stays empty")
    plain.star.scripts.OnLeave(plain.star)
    eq(plain.star.texture.vertex[1], 0.95, "and turns light again")

    menu:Hide()
    SI.db.favorites, SI.db.nextFavorite = {}, 1
    mock.bags = {}
    mock.worn[13] = nil
    _G.time = realTime
end

-- equip queue: an item picked in combat is equipped after combat
do
    reset()
    SI.Track({ 13 })
    local tracker = SI.frames[13]
    local item = { bag = 0, index = 1, id = 901, link = "t1", icon = 11 }
    mock.bags = { [0] = { n = 1, { link = "t1", id = 901, loc = "INVTYPE_TRINKET", icon = 11 } } }
    mock.combat = true
    mock.lastEquip = nil
    mock.chat = {}
    SI.EquipOrQueue(item, 13)
    truthy(mock.lastEquip == nil, "nothing is equipped in combat")
    truthy(SI.QueuedItem(13) and SI.QueuedItem(13).id == 901, "the item is queued")
    truthy(tracker.queueFrame:IsShown() and tracker.queueIcon.texture == 11, "the queued item is shown on the window")
    truthy(#mock.chat == 1, "queueing prints one line")
    SI.EquipOrQueue(item, 13)
    truthy(SI.QueuedItem(13) == nil and not tracker.queueFrame:IsShown(), "picking the queued item again takes it out of the queue")
    SI.EquipOrQueue(item, 13)
    fire("PLAYER_REGEN_ENABLED") -- still in combat flag: nothing happens
    truthy(mock.lastEquip == nil and SI.QueuedItem(13), "the queue waits while combat lasts")
    mock.combat = false
    fire("PLAYER_REGEN_ENABLED")
    truthy(mock.lastEquip and mock.lastEquip[1] == "t1" and mock.lastEquip[2] == 13, "the queued item is equipped after combat")
    truthy(SI.QueuedItem(13) == nil and not tracker.queueFrame:IsShown(), "the queue is empty after equipping")

    -- an item that left the bags is skipped with a message
    mock.combat = true
    SI.EquipOrQueue(item, 13)
    mock.bags = {}
    mock.combat = false
    mock.lastEquip, mock.chat = nil, {}
    fire("PLAYER_REGEN_ENABLED")
    truthy(mock.lastEquip == nil and #mock.chat == 1 and SI.QueuedItem(13) == nil, "a queued item that is gone is dropped with a message")

    -- out of combat the item is equipped at once
    mock.bags = { [0] = { n = 1, { link = "t1", id = 901, loc = "INVTYPE_TRINKET", icon = 11 } } }
    SI.EquipOrQueue(item, 13)
    truthy(mock.lastEquip and mock.lastEquip[1] == "t1", "out of combat the item is equipped at once")
    mock.bags = {}
end

-- an item picked for another slot moves in the queue
do
    reset()
    SI.Track({ 13, 14 })
    local a = { bag = 0, index = 1, id = 901, link = "tA", icon = 11 }
    local b = { bag = 0, index = 2, id = 902, link = "tB", icon = 12 }
    mock.bags = { [0] = { n = 2,
        { link = "tA", id = 901, loc = "INVTYPE_TRINKET", icon = 11 },
        { link = "tB", id = 902, loc = "INVTYPE_TRINKET", icon = 12 },
    } }
    mock.combat = true
    mock.chat = {}
    SI.EquipOrQueue(a, 13)
    SI.EquipOrQueue(a, 14)
    truthy(SI.QueuedItem(14) and SI.QueuedItem(14).id == 901, "the item is queued for the second slot")
    truthy(SI.QueuedItem(13) == nil and not SI.frames[13].queueFrame:IsShown(), "the item left the queue of the first slot")
    truthy(SI.frames[14].queueFrame:IsShown(), "the second slot shows the queued item")
    truthy(#mock.chat == 3, "a line for the first queueing, one for the removal and one for the move")

    -- another item in the other slot does not touch it
    SI.EquipOrQueue(b, 13)
    truthy(SI.QueuedItem(13).id == 902 and SI.QueuedItem(14).id == 901, "different items stay in their slots")

    -- two copies of an item can wait in two slots
    mock.bags = { [0] = { n = 2,
        { link = "tA", id = 901, loc = "INVTYPE_TRINKET", icon = 11 },
        { link = "tA", id = 901, loc = "INVTYPE_TRINKET", icon = 11 },
    } }
    SI.EquipOrQueue(a, 13)
    truthy(SI.QueuedItem(13).id == 901 and SI.QueuedItem(14).id == 901, "two copies fill two slots")
    mock.combat = false
    mock.bags = {}
    fire("PLAYER_REGEN_ENABLED")
end

-- cooldown updates: unchanged values are not applied again, errors are swallowed
do
    reset()
    SI.Track({ 13 })
    local tracker = SI.frames[13]
    local calls = 0
    tracker.cd.SetCooldown = function() calls = calls + 1 end
    local original = GetInventoryItemCooldown
    GetInventoryItemCooldown = function() return 100, 30, 1 end
    SI.RefreshSlot(13)
    SI.RefreshSlot(13)
    eq(calls, 1, "an unchanged cooldown is applied once")
    GetInventoryItemCooldown = function() return 200, 30, 1 end
    SI.RefreshSlot(13)
    eq(calls, 2, "a changed cooldown is applied")
    GetInventoryItemCooldown = function() error("api changed") end
    truthy(pcall(SI.RefreshSlot, 13), "an error of the cooldown API does not escape")
    GetInventoryItemCooldown = original
    tracker.cd.SetCooldown = nil
end

-- the character key never falls back to a shared made-up name
do
    eq(SI.CharacterKey(), "Tester-Realm", "the key is the name and the realm")
    mock.character = "Unknown"
    truthy(SI.CharacterKey():find("^guid%-"), "an unknown name gives a key from the GUID")
    mock.character = ""
    truthy(SI.CharacterKey():find("^guid%-"), "an empty name gives a key from the GUID")
    mock.character = nil
end

-- character window context menu
reset()
local menu = ShowItemsContextMenu
local trackEntry, untrackEntry
for _, f in ipairs(mock.frames) do
    if f.parent == menu and f.scripts.OnClick then
        if not trackEntry then trackEntry = f else untrackEntry = f end
    end
end
-- a plain click is left to the client (the item is picked up): the addon ignores it
CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "LeftButton")
truthy(not menu:IsShown(), "plain left click does not open the menu")
CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "RightButton")
truthy(not menu:IsShown(), "plain right click does not open the menu")
for _, mod in ipairs({ "ctrl", "shift", "alt" }) do
    mock.mods[mod] = true
    CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "LeftButton")
    mock.mods[mod] = false
    truthy(not menu:IsShown(), mod .. "+left click does not open the menu")
end
for _, mod in ipairs({ "shift", "alt" }) do
    mock.mods[mod] = true
    CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "RightButton")
    mock.mods[mod] = false
    truthy(not menu:IsShown(), mod .. "+right click does not open the menu")
end
for _, shift in ipairs({ false, true }) do
    mock.mods.ctrl, mock.mods.alt, mock.mods.shift = true, true, shift
    CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "RightButton")
    mock.mods.ctrl, mock.mods.alt, mock.mods.shift = false, false, false
    truthy(not menu:IsShown(), "Ctrl+Alt" .. (shift and "+Shift" or "") .. "+right click does not open the menu")
end
mock.mods.ctrl, mock.mods.shift = true, true
CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "LeftButton")
mock.mods.ctrl, mock.mods.shift = false, false
truthy(not menu:IsShown(), "Ctrl+Shift+left click does not open the menu")
selectClick(CharacterTrinket0Slot)
truthy(menu:IsShown(), "Ctrl+right click on one slot opens the menu")
eq(trackEntry.text.color[1], 1, "track is white for an untracked slot")
eq(untrackEntry.text.color[1], 0.5, "untrack is gray for an untracked slot")
trackEntry.scripts.OnClick(trackEntry)
truthy(SI.db.tracked[13], "context Track tracks the single selected slot")
truthy(not SI.db.tracked[14] and not SI.db.tracked[11], "only the selected slot is tracked")
selectClick(CharacterTrinket0Slot)
eq(trackEntry.text.color[1], 0.5, "track is gray for a tracked slot")
eq(untrackEntry.text.color[1], 1, "untrack is white for a tracked slot")
untrackEntry.scripts.OnClick(untrackEntry)
truthy(not SI.db.tracked[13], "context Untrack removes the slot")

-- Ctrl+right click selects one slot: another click moves the selection, a second click on it clears it
selectClick(CharacterTrinket0Slot)
selectClick(CharacterTrinket1Slot)
trackEntry.scripts.OnClick(trackEntry)
truthy(SI.db.tracked[14] and not SI.db.tracked[13], "Ctrl+right click on another slot replaces the selection")
SI.Untrack({ 14 })
selectClick(CharacterTrinket0Slot)
selectClick(CharacterTrinket0Slot)
truthy(not menu:IsShown(), "a second Ctrl+right click on the selected slot clears the selection")

-- Ctrl+Shift+right click adds slots to the selection
multiClick(CharacterTrinket0Slot)
multiClick(CharacterTrinket1Slot)
multiClick(CharacterFinger0Slot)
multiClick(CharacterFinger0Slot)
multiClick(CharacterFinger0Slot)
trackEntry.scripts.OnClick(trackEntry)
truthy(SI.db.tracked[13] and SI.db.tracked[14] and SI.db.tracked[11], "Ctrl+Shift multi-select tracks all selected")
eq(SI.db.tracked[13].group, SI.db.tracked[11].group, "multi-selected windows are grouped")
multiClick(CharacterTrinket0Slot)
multiClick(CharacterTrinket1Slot)
multiClick(CharacterTrinket0Slot)
multiClick(CharacterTrinket1Slot)
truthy(not menu:IsShown(), "removing every slot from a multi-selection closes the menu")
selectClick(CharacterTrinket0Slot)
multiClick(CharacterTrinket1Slot)
untrackEntry.scripts.OnClick(untrackEntry)
truthy(not SI.db.tracked[13] and not SI.db.tracked[14] and SI.db.tracked[11], "a single selection can be extended with Ctrl+Shift")
selectClick(CharacterFinger0Slot)
untrackEntry.scripts.OnClick(untrackEntry)
multiClick(CharacterTrinket0Slot)
multiClick(CharacterTrinket1Slot)
multiClick(CharacterFinger0Slot)
trackEntry.scripts.OnClick(trackEntry)
truthy(SI.db.tracked[13] and SI.db.tracked[14] and SI.db.tracked[11], "three slots are tracked again for the following tests")

-- an item that ended up on the cursor by a Ctrl+right click is put back; an item carried before stays
do
    local carrying, cleared = false, 0
    local realCursorHasItem, realClearCursor = CursorHasItem, ClearCursor
    CursorHasItem = function() return carrying end
    ClearCursor = function() cleared = cleared + 1 carrying = false end
    CharacterTrinket0Slot.scripts.PreClick(CharacterTrinket0Slot)
    carrying = true
    selectClick(CharacterTrinket0Slot)
    eq(cleared, 1, "an item picked up by a Ctrl+right click is put back")
    carrying = true
    CharacterTrinket0Slot.scripts.PreClick(CharacterTrinket0Slot)
    selectClick(CharacterTrinket0Slot)
    eq(cleared, 1, "an item carried before the Ctrl+right click stays on the cursor")
    CursorHasItem, ClearCursor = realCursorHasItem, realClearCursor
    SI.CloseMenus()
end

-- selecting a slot works with the settings window closed and open
do
    SI.CloseWindow()
    selectClick(CharacterHeadSlot)
    truthy(ShowItemsContextMenu:IsShown(), "slot selection works while the settings window is closed")
    SI.CloseMenus()
    SI.OpenWindow(1)
    selectClick(CharacterHeadSlot)
    truthy(ShowItemsContextMenu:IsShown() and ShowItemsOptions:IsShown(), "slot selection works while the settings window is open")
    SI.CloseMenus()
    SI.CloseWindow()
end

-- the menu stays open while Ctrl is held over a character window slot
mock.mods.ctrl = true
CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "RightButton")
tick()
mock.mouseDown.RightButton = true
CharacterTrinket1Slot.mouseOver = true
tick()
truthy(ShowItemsContextMenu:IsShown(), "menu stays open on Ctrl+press over a slot")
mock.mods.ctrl = false
tick()
truthy(not ShowItemsContextMenu:IsShown(), "menu closes on a plain press outside")
mock.mouseDown.RightButton = false
CharacterTrinket1Slot.mouseOver = false
SI.CloseMenus()

-- enable / disable from the minimap button
local mini = ShowItemsMinimapButton
truthy(mini, "minimap button exists")
SI.SetBinding(13, "Shift-2")
mock.mods.shift = true
mini.scripts.OnClick(mini, "LeftButton")
mock.mods.shift = false
eq(SI.db.enabled, false, "Shift+left click disables")
truthy(not SI.frames[13]:IsShown(), "trackers hidden when disabled")
truthy(mock.overrides["Shift-2"] == nil, "bindings cleared when disabled")
selectClick(CharacterTrinket0Slot)
truthy(not ShowItemsContextMenu:IsShown(), "no context menu when disabled")
mock.mods.shift = true
mini.scripts.OnClick(mini, "LeftButton")
mock.mods.shift = false
eq(SI.db.enabled, true, "Shift+left click enables")
truthy(SI.frames[13]:IsShown(), "trackers shown when enabled")
truthy(mock.overrides["Shift-2"], "bindings restored when enabled")

-- minimap tooltip: key combinations in light blue, then a blank line and the slot selection hints
do
    local lines = {}
    local oldAddLine = GameTooltip.AddLine
    GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
    mini.scripts.OnEnter(mini)
    GameTooltip.AddLine = oldAddLine
    eq(#lines, 8, "the minimap tooltip has eight lines")
    eq(lines[3], "|cff66ccffLeft-click|r: sets", "the key combination is light blue")
    eq(lines[6], " ", "a blank line separates the slot selection hints")
    eq(lines[7], "|cff66ccffCtrl+right-click|r: select a slot", "Ctrl+right click selects a slot")
    eq(lines[8], "|cff66ccffCtrl+Shift+right-click|r: select several slots", "Ctrl+Shift+right click selects several slots")
end

-- options window
mock.chat = {}
mini.scripts.OnClick(mini, "LeftButton")
truthy(#mock.chat == 1 and not (ShowItemsOptions and ShowItemsOptions:IsShown()), "left click without sets only prints a hint")
mini.scripts.OnClick(mini, "RightButton")
truthy(ShowItemsOptions and ShowItemsOptions:IsShown(), "right click opens settings")
eq(SI.ActiveTab(), 1, "settings is the first tab")
eq(SI.TabFrame(1).points[1][1], "TOP", "the settings panel sits between the slot columns")
eq(ShowItemsOptList1.label.text, "Tester's Settings", "the list starts with the settings title")
truthy(ShowItemsOptList1.underline:IsShown(), "the title row has the title bar")
eq(ShowItemsOptList2.w, 156, "rows are 156 px wide")
eq(ShowItemsOptList2.h, 24, "rows are 24 px high")
local scrollFrame = ShowItemsOptListScrollFrame
truthy(scrollFrame and scrollFrame.parent == SI.TabFrame(1), "the list has a scroll frame")

-- check boxes
local lockRow = ShowItemsOptList2
eq(lockRow.checkText.text, "Lock windows", "first check box locks the windows")
lockRow.check.checked = true
lockRow.check.scripts.OnClick(lockRow.check)
eq(SI.db.locked, true, "the Lock windows check box locks the windows")
lockRow.scripts.OnClick(lockRow)
eq(SI.db.locked, false, "clicking the row toggles the check box")
local glowRow = ShowItemsOptList3
eq(glowRow.checkText.text, "Glow", "the Glow check box is right under Lock windows")
truthy(glowRow.check.checked, "the glow is on by default")
glowRow.scripts.OnClick(glowRow)
eq(SI.db.glow, false, "the Glow check box turns the glow off")
glowRow.scripts.OnClick(glowRow)
eq(SI.db.glow, true, "the Glow check box turns the glow on")
local enableRow = ShowItemsOptList4
eq(enableRow.checkText.text, "Enable ShowItems", "Enable ShowItems follows the Glow check box")
enableRow.scripts.OnClick(enableRow)
eq(SI.db.enabled, false, "the Enable check box disables the addon")
truthy(not SI.frames[13]:IsShown(), "windows are hidden when disabled from the settings")
enableRow.scripts.OnClick(enableRow)
eq(SI.db.enabled, true, "the Enable check box enables the addon")

-- sliders and number fields
eq(ShowItemsSizeSlider.w, 96, "sliders are 96 px wide")
eq(ShowItemsSizeSlider.h, 17, "sliders are 17 px high")
eq(ShowItemsAlpha.w, 32, "number fields are 32 px wide")
ShowItemsSizeSlider.scripts.OnValueChanged(ShowItemsSizeSlider, 50)
eq(SI.GetMeanSize(), 50, "size slider scales windows")
eq(ShowItemsSize.text, "50", "the size field follows the slider")
ShowItemsAlphaSlider.scripts.OnValueChanged(ShowItemsAlphaSlider, 0.6)
eq(SI.db.alpha, 0.6, "transparency slider")
eq(SI.frames[13].alpha, 0.6, "transparency applied to windows")
eq(ShowItemsAlpha.text, "0.60", "the transparency field shows two decimals")
ShowItemsAlpha:SetText("0.5")
ShowItemsAlpha.scripts.OnEnterPressed(ShowItemsAlpha)
eq(SI.db.alpha, 0.5, "typing a value in the number field sets it")
eq(ShowItemsAlphaSlider.value, 0.5, "the slider follows the number field")
ShowItemsAlpha:SetText("5")
ShowItemsAlpha.scripts.OnEnterPressed(ShowItemsAlpha)
eq(SI.db.alpha, 0.5, "a value out of range is ignored")
eq(ShowItemsAlpha.text, "0.50", "an ignored value is replaced by the current one")
ShowItemsAlpha:SetText("0.8")
ShowItemsAlpha.scripts.OnEscapePressed(ShowItemsAlpha)
eq(ShowItemsAlpha.text, "0.50", "Escape drops the typed value")
ShowItemsSpacingSlider.scripts.OnValueChanged(ShowItemsSpacingSlider, 8)
eq(SI.db.spacing, 8, "spacing slider sets the spacing")
ShowItemsSpacingSlider.scripts.OnValueChanged(ShowItemsSpacingSlider, 0)
ShowItemsAlphaSlider.scripts.OnValueChanged(ShowItemsAlphaSlider, 1)

-- scrolling and buttons
scrollFrame.scripts.OnVerticalScroll(scrollFrame, 48)
eq(ShowItemsOptList11.opt.label, "Reset all", "scrolling moves the list")
truthy(ShowItemsResetAll:IsShown() and ShowItemsKeyBindings:IsShown() and ShowItemsCommonSize:IsShown(), "buttons are in the list")
eq(ShowItemsKeyBindings.w, 128, "list buttons are 128 px wide")
eq(ShowItemsKeyBindings.h, 22, "list buttons are 22 px high")
truthy(ShowItemsKeyBindings.enabled and ShowItemsResetAll.enabled, "list buttons stay active")
scrollFrame.scripts.OnVerticalScroll(scrollFrame, 0)
eq(ShowItemsOptList1.opt.type, "label", "the list scrolls back to the title")

-- slots are dimmed on the settings tab, tracked or not
truthy(ShowItemsInv1:IsShown() and ShowItemsInv13:IsShown(), "slot buttons are shown on the settings tab")
truthy(SI.db.tracked[13], "slot 13 is tracked here")
eq(ShowItemsInv13.icon.vertex[1], 0.25, "a tracked slot is dimmed on the settings tab")
eq(ShowItemsInv1.icon.vertex[1], 0.25, "an untracked slot is dimmed")

-- slot key bindings: select a slot, then a key
local capture = ShowItemsBindFrame
local function bindSlot(slot)
    ShowItemsKeyBindings.scripts.OnClick(ShowItemsKeyBindings)
    local b = _G["ShowItemsInv" .. slot]
    b.scripts.OnClick(b)
end
local bindPanel = ShowItemsSlotBindCancel.parent
truthy(not bindPanel:IsShown(), "the slot prompt is hidden at first")
ShowItemsKeyBindings.scripts.OnClick(ShowItemsKeyBindings)
truthy(bindPanel:IsShown() and not capture:IsShown(), "Slot Key Bindings asks for a slot")
truthy(ShowItemsInv13.icon.vertex[1] == 1 and ShowItemsInv1.icon.vertex[1] == 0.25, "while a slot is awaited the tracked slots are bright")
mock.chat = {}
ShowItemsInv1.scripts.OnClick(ShowItemsInv1)
truthy(#mock.chat == 1 and not capture:IsShown(), "an untracked slot only prints a hint")
ShowItemsInv13.scripts.OnClick(ShowItemsInv13)
truthy(capture:IsShown(), "a tracked slot opens the key capture")
mock.mods.ctrl = true
capture.scripts.OnKeyDown(capture, "K")
mock.mods.ctrl = false
eq(SI.db.bindings[13], "CTRL-K", "key capture stores binding")
truthy(not capture:IsShown() and not bindPanel:IsShown(), "capture and slot prompt close after a key")
bindSlot(13)
capture.scripts.OnKeyDown(capture, "LSHIFT")
truthy(capture:IsShown(), "modifier keys alone are ignored")
capture.scripts.OnKeyDown(capture, "ESCAPE")
truthy(not capture:IsShown() and bindPanel:IsShown(), "escape cancels the capture and keeps asking for a slot")
ShowItemsSlotBindCancel.scripts.OnClick(ShowItemsSlotBindCancel)
truthy(not bindPanel:IsShown(), "Cancel leaves the slot prompt")
bindSlot(13)
capture.scripts.OnMouseWheel(capture, 1)
eq(SI.db.bindings[13], "MOUSEWHEELUP", "mouse wheel can be bound")
bindSlot(13)
capture.scripts.OnMouseUp(capture, "MiddleButton")
eq(SI.db.bindings[13], "BUTTON3", "middle button can be bound")
bindSlot(13)
for _, f in ipairs(mock.frames) do
    if f.parent == capture and f.text == "Unbind" then f.scripts.OnClick(f) end
end
truthy(SI.db.bindings[13] == nil, "unbind clears the key")
ShowItemsKeyBindings.scripts.OnClick(ShowItemsKeyBindings)
SI.OpenWindow(3)
truthy(not bindPanel:IsShown(), "leaving the settings tab ends the slot prompt")
SI.OpenWindow(1)

-- common size and reset
SI.Track({ 14 })
SI.db.tracked[13].size, SI.db.tracked[14].size = 40, 80
ShowItemsCommonSize.scripts.OnClick(ShowItemsCommonSize)
eq(SI.db.tracked[13].size, SI.db.tracked[14].size, "Common size makes the windows equal")
mock.cursor = { 600, 400 }
ShowItemsResetAll.scripts.OnClick(ShowItemsResetAll)
truthy(ShowItemsConfirm:IsShown() and SI.db.tracked[13], "Reset all asks first")
ShowItemsConfirmNo.scripts.OnClick(ShowItemsConfirmNo)
truthy(SI.db.tracked[13], "cancel keeps the windows")
ShowItemsResetAll.scripts.OnClick(ShowItemsResetAll)
ShowItemsConfirmYes.scripts.OnClick(ShowItemsConfirmYes)
truthy(next(SI.db.tracked) == nil, "confirming Reset all untracks everything")
SI.Track({ 13 })

-- window size, resize grip, slot plates, thin sliders
do
    eq(ShowItemsOptions.scale, 1.5, "window starts at 1.5 times the base size")
    truthy(not SI.db.windowScaleCustom, "default size is not stored as a custom size")
    local grip = ShowItemsResizeGrip
    mock.cursor = { 500, 500 }
    grip.scripts.OnMouseDown(grip)
    mock.cursor = { 500 + 432, 500 - 522 }
    grip.scripts.OnUpdate(grip)
    eq(ShowItemsOptions.scale, 3, "dragging the corner outward enlarges the window")
    mock.cursor = { 500 - 432, 500 + 522 }
    grip.scripts.OnUpdate(grip)
    eq(ShowItemsOptions.scale, 1, "the window cannot be made smaller than its base size")
    mock.cursor = { 500 + 1000, 500 - 1000 }
    grip.scripts.OnUpdate(grip)
    truthy(ShowItemsOptions.scale <= 1080 / 348 + 0.001, "the window never grows taller than the screen")
    grip.scripts.OnMouseUp(grip)
    truthy(grip.scripts.OnUpdate == nil, "resize stops on release")
    eq(SI.db.windowScale, ShowItemsOptions.scale, "window size is saved")
    truthy(SI.db.windowScaleCustom, "a dragged size is stored as a custom size")
    ShowItemsOptions:SetScale(1.5)
    SI.db.windowScale, SI.db.windowScaleCustom = 1.5, false

    -- every tab is the same panel between the slot columns
    for id = 1, 3 do eq(SI.TabFrame(id).points[1][1], "TOP", "tab " .. id .. " is centered between the slot columns") end

    -- context menu: same padding on all sides, entries close together
    local p1, p2 = trackEntry.points, untrackEntry.points
    eq(p1[1][5], -9, "track entry top padding")
    eq(p2[1][5] - p1[1][5], -16, "entries are 16 px apart")
    eq(ShowItemsContextMenu.h, 9 + 16 + 16 + 9, "context menu height has equal padding")
    eq(ShowItemsContextMenu.w, 40 + 16 + 18, "context menu width has equal padding")

    -- tabs are 46 px wide, centered on the window, left to right: Sets, Settings, Profiles
    local first = ShowItemsTab2.points[1]
    eq(first[1], "TOPLEFT", "the first tab anchors by its left corner")
    eq(first[3], "TOP", "the row of tabs is anchored to the center of the window")
    truthy(first[4] == -69 and first[5] == -6, "three 46 px tabs are centered")
    eq(ShowItemsTab1.w, 46, "tabs are 46 px wide")
    eq(ShowItemsTab1.points[1][2], ShowItemsTab2, "Settings continues to the right of Sets")
    eq(ShowItemsTab3.points[1][2], ShowItemsTab1, "Profiles continues to the right of Settings")
    SI.OpenWindow(1)
end

-- eye mode in the flyout: track / untrack any slot from the menu
reset()
SI.Track({ 13 })
SI.frames[13].scripts.PostClick(SI.frames[13], "RightButton")
local headers = {}
for _, f in ipairs(mock.frames) do
    if f.parent == ShowItemsFlyout and f.active then headers[#headers + 1] = f end
end
eq(#headers, 2, "resize and eye header buttons have a plate")
local lock
for _, f in ipairs(mock.frames) do
    if f.parent == ShowItemsFlyout and rawget(f, "isPadlock") then lock = f end
end
truthy(lock and lock.scripts.OnClick, "the padlock is the third header button, drawn without a plate")
lock.scripts.OnClick(lock)
truthy(SI.db.locked, "a click on the open padlock locks the windows")
lock.scripts.OnClick(lock)
truthy(not SI.db.locked, "a click on the closed padlock unlocks the windows")
local eye = headers[2]
eye.scripts.OnClick(eye)
eq(ShowItemsFlyout.view, "slots", "eye switches to the slot list")
local function slotButton(slot)
    for _, f in ipairs(mock.frames) do
        if f.parent == ShowItemsFlyout and f.slot == slot then return f end
    end
end
slotButton(14).scripts.OnClick(slotButton(14))
truthy(SI.db.tracked[14], "eye mode tracks an untracked slot")
slotButton(13).scripts.OnClick(slotButton(13))
truthy(not SI.db.tracked[13], "eye mode untracks a tracked slot")
truthy(ShowItemsFlyout:IsShown(), "menu stays open and moves to a remaining window")
slotButton(14).scripts.OnClick(slotButton(14))
truthy(not ShowItemsFlyout:IsShown(), "menu closes when nothing is tracked")

-- the context menu is attached to the right of the slot that was selected last
do
    local function anchoredTo(slotFrame, label)
        local p = ShowItemsContextMenu.points[1]
        truthy(p[1] == "LEFT" and p[2] == slotFrame and p[3] == "RIGHT" and p[4] == 6 and p[5] == 0, label)
    end
    reset()
    -- situation 1: trinket, trinket, neck with Ctrl held, then the cursor wanders around
    mock.mods.ctrl = true
    CharacterTrinket0Slot.scripts.OnClick(CharacterTrinket0Slot, "RightButton")
    anchoredTo(CharacterTrinket0Slot, "menu is right of the first selected slot")
    CharacterTrinket1Slot.scripts.OnClick(CharacterTrinket1Slot, "RightButton")
    anchoredTo(CharacterTrinket1Slot, "menu moves to the second selected slot")
    CharacterNeckSlot.scripts.OnClick(CharacterNeckSlot, "RightButton")
    anchoredTo(CharacterNeckSlot, "menu moves to the third selected slot")
    mock.mods.ctrl = false
    mock.cursor = { 5, 5 }
    tick()
    anchoredTo(CharacterNeckSlot, "menu stays at the last selected slot when the cursor leaves the paper doll")
    CharacterWaistSlot.mouseOver = true
    mock.cursor = { 700, 300 }
    tick()
    anchoredTo(CharacterNeckSlot, "hovering another slot without selecting does not move the menu")
    CharacterWaistSlot.mouseOver = false
    truthy(ShowItemsContextMenu:IsShown(), "menu stays open while the cursor moves")
    SI.CloseMenus()

    -- situation 2: one slot, then another with Ctrl+right click
    selectClick(CharacterHeadSlot)
    anchoredTo(CharacterHeadSlot, "menu is right of a single selected slot")
    selectClick(CharacterLegsSlot)
    anchoredTo(CharacterLegsSlot, "selecting another slot moves the menu there")
    CharacterNeckSlot.scripts.OnClick(CharacterNeckSlot, "LeftButton")
    anchoredTo(CharacterLegsSlot, "a plain click does not move the menu")
    SI.CloseMenus()

    -- the menu is drawn above the item tooltip
    GameTooltip.level = 50
    selectClick(CharacterHeadSlot)
    eq(ShowItemsContextMenu.strata, "TOOLTIP", "menu is in the tooltip strata")
    truthy(ShowItemsContextMenu.level > GameTooltip.level, "menu is above the item tooltip")
    truthy(trackEntry.level > GameTooltip.level and untrackEntry.level > GameTooltip.level, "menu entries are above the item tooltip")
    SI.CloseMenus()
    GameTooltip.level = nil
    mock.cursor = { 700, 400 }
    SI.UI.Confirm("Test?", function() end)
    eq(ShowItemsConfirm.strata, "TOOLTIP", "confirm popup is in the tooltip strata")
    SI.UI.HideConfirm()
end

-- per-character settings
eq(SI.db == ShowItemsCharDB, true, "login resolves the database of the character folder")
truthy(ShowItemsDB.chars == nil or ShowItemsDB.chars["Tester-Realm"] == nil, "a new character writes nothing to the account-wide file")

-- the settings live in the saved variables of the character; an existing account-wide record is taken over once
do
    local store = {}
    local root = { chars = { ["Tester-Realm"] = {
        tracked = { [13] = { left = 100, top = 200, size = 40 } }, bindings = { [13] = "CTRL-5" },
        enabled = false, locked = true, alpha = 0.5, spacing = 4, windowScale = 2, windowScaleCustom = true,
        profiles = { { name = "Raid", data = { tracked = {}, bindings = {} }, time = 1 } },
        sets = { [1] = { name = "Tank", slots = { [1] = { id = 11 } } } }, nextSetId = 2,
    } } }
    local db = SI.ResolveStoredDB(store, root, "Tester-Realm")
    truthy(db == store, "the character storage itself is the database")
    truthy(db.tracked[13] and db.tracked[13].left == 100, "tracked windows are taken over")
    eq(db.bindings[13], "CTRL-5", "key bindings are taken over")
    eq(db.enabled, false, "the enabled flag is taken over")
    eq(db.locked, true, "the lock is taken over")
    eq(db.alpha, 0.5, "the opacity is taken over")
    eq(db.windowScale, 2, "the window size is taken over")
    eq(db.profiles[1].name, "Raid", "profiles are taken over")
    eq(db.sets[1].name, "Tank", "sets are taken over")
    eq(db.glow, true, "options added later get their defaults")
    truthy(db.tracked ~= root.chars["Tester-Realm"].tracked, "the copy is independent of the account-wide record")
    truthy(root.chars["Tester-Realm"] and root.chars["Tester-Realm"].tracked[13], "the account-wide record stays as a backup")
    db.tracked[13].left = 555
    eq(root.chars["Tester-Realm"].tracked[13].left, 100, "later changes do not touch the backup")

    -- the next login uses the character storage and never reads the account-wide record again
    root.chars["Tester-Realm"].tracked[13].left = 999
    local again = SI.ResolveStoredDB(store, root, "Tester-Realm")
    eq(again.tracked[13].left, 555, "the second login keeps the character settings")

    -- another character has no record: clean defaults, the account-wide file is not touched
    local other = SI.ResolveStoredDB({}, root, "Other-Realm")
    truthy(next(other.tracked) == nil and other.enabled == true and other.glow == true, "a character without a record starts clean")
    truthy(root.chars["Other-Realm"] == nil, "no record is created in the account-wide file")

    -- a damaged character file is repaired, not discarded
    local damaged = SI.ResolveStoredDB({ tracked = { [13] = { left = 1, top = 2 }, [99] = "x" }, alpha = "bad" }, {}, "A-Realm")
    truthy(damaged.tracked[13] and damaged.tracked[99] == nil, "a damaged character file is sanitized")
    eq(damaged.alpha, 1, "a bad value falls back to the default")

    -- the old account-wide format (before the per-character records) moves to the first character
    local legacy = { tracked = { [14] = { left = 3, top = 4, size = 40 } }, enabled = true, alpha = 1 }
    local first = SI.ResolveStoredDB({}, legacy, "First-Realm")
    truthy(first.tracked[14], "the oldest format moves to the first character")
    local second = SI.ResolveStoredDB({}, legacy, "Second-Realm")
    truthy(next(second.tracked) == nil, "and only to the first character")
    truthy(SI.ResolveStoredDB({}, nil, "X-Realm"), "a missing account-wide table is fine")

    -- data saved under the GUID key (the name was unknown at that login) is found by the GUID
    local byGuid = { chars = {
        ["N-Realm"] = { tracked = {}, sets = {}, profiles = {} },
        ["guid-Player-1"] = { tracked = { [13] = { left = 7, top = 8, size = 40 } } },
    } }
    local rescued = SI.ResolveStoredDB({}, byGuid, "N-Realm", "guid-Player-1")
    truthy(rescued.tracked[13] and rescued.tracked[13].left == 7, "an empty record by name gives way to the GUID record with data")
    byGuid.chars["N-Realm"].tracked = { [14] = { left = 1, top = 2, size = 40 } }
    local named = SI.ResolveStoredDB({}, byGuid, "N-Realm", "guid-Player-1")
    truthy(named.tracked[14] and not named.tracked[13], "a record by name with data wins over the GUID record")
    local noAlt = SI.ResolveStoredDB({}, byGuid, "N-Realm")
    truthy(noAlt.tracked[14], "without a GUID key the record by name is used")
    UnitGUID = function() return "Player-1" end
    eq(SI.GuidKey(), "guid-Player-1", "the GUID key is built from the GUID of the player")
    UnitGUID = nil
end
local root = { tracked = { [13] = { left = 1, top = 2, size = 40 } }, enabled = true, alpha = 1 }
local dbA = SI.ResolveCharacterDB(root, "A-Realm")
truthy(dbA.tracked[13], "old settings go to the first character")
truthy(root.tracked == nil, "old account-wide keys are removed")
local dbB = SI.ResolveCharacterDB(root, "B-Realm")
truthy(next(dbB.tracked) == nil and dbA ~= dbB, "another character starts clean")
truthy(root.chars["A-Realm"] == dbA and root.chars["B-Realm"] == dbB, "databases are stored per character")

-- a window dropped on another one takes the size of that one (large window dropped a little further away)
reset()
SI.db.tracked[13] = { left = 600, top = 560, size = 40, moved = true }
SI.db.tracked[14] = { left = 900, top = 560, size = 100, moved = true }
SI.ApplyAll()
drag(14, 920, 540, 920 - 255, 540) -- left edge ends 5 px from the small window
truthy(SI.db.tracked[14].group ~= nil and SI.db.tracked[14].group == SI.db.tracked[13].group, "big window attaches to a small one")
eq(SI.db.tracked[14].size, 40, "the big window takes the size of the small one it is attached to")
eq(SI.db.tracked[13].size, 40, "the window it is attached to keeps its size")
eq(SI.db.tracked[14].left, 640, "the window is flush with the small window edge")
eq(SI.db.tracked[14].top, 560, "the windows line up")
eq(ShowItemsSlot14.w, 40, "the window on the screen has the new size")

-- and the other way round: the small window takes the size of the big one
reset()
SI.db.tracked[13] = { left = 600, top = 560, size = 40, moved = true }
SI.db.tracked[14] = { left = 900, top = 560, size = 100, moved = true }
SI.ApplyAll()
drag(13, 620, 540, 620 + 255, 540) -- its right edge ends 5 px before the big window
eq(SI.db.tracked[13].size, 100, "the small window takes the size of the big one")
eq(SI.db.tracked[14].size, 100, "the big window keeps its size")
eq(SI.db.tracked[13].left, 800, "the small window is flush on the left of the big one")
eq(SI.db.tracked[13].top, 560, "the windows line up on the top")

-- a group of two takes the size as a whole and stays flush
reset()
SI.db.tracked[13] = { left = 100, top = 560, size = 50, moved = true, group = 1 }
SI.db.tracked[14] = { left = 150, top = 560, size = 50, moved = true, group = 1 }
SI.db.tracked[5] = { left = 600, top = 560, size = 80, moved = true }
SI.db.nextGroup = 2
SI.ApplyAll()
drag(13, 120, 540, 120 + 395, 540) -- the group of two is dropped on the left of the window of 80
eq(SI.db.tracked[13].size, 80, "the first window of the group takes the size")
eq(SI.db.tracked[14].size, 80, "the second window of the group takes the size")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 80, "the group stays flush after resizing")
truthy(SI.db.tracked[13].group == SI.db.tracked[5].group, "the group joins the window")

-- windows of any size attach to a side, the top or the bottom of each other
do
    local function setup()
        reset()
        SI.db.tracked[13] = { left = 600, top = 560, size = 100, moved = true } -- 600..700 x 460..560
        SI.db.tracked[14] = { left = 900, top = 300, size = 20, moved = true }
        SI.ApplyAll()
    end
    local function joined() return SI.db.tracked[14].group ~= nil and SI.db.tracked[14].group == SI.db.tracked[13].group end
    setup()
    drag(14, 910, 290, 735, 510) -- 25 px right of the big window, middle of its side
    truthy(joined(), "a small window attaches to the side of a big one")
    eq(SI.db.tracked[14].left, 700, "the small window touches the side")
    eq(SI.db.tracked[14].top, 560, "the small window lines up with the top of the big one")
    eq(SI.db.tracked[14].size, 100, "the small window takes the size of the big one")
    setup()
    drag(14, 910, 290, 630, 438) -- 12 px under the big window, its left edge 20 px off
    truthy(joined(), "a small window attaches under a big one")
    eq(SI.db.tracked[14].top, 460, "the small window touches the bottom")
    eq(SI.db.tracked[14].left, 600, "the left edges align")
    eq(SI.db.tracked[14].size, 100, "the window under the big one takes its size")
    setup()
    drag(14, 910, 290, 700, 575) -- 5 px above the big window, its right edge 10 px off
    truthy(joined(), "a small window attaches on top of a big one")
    eq(SI.db.tracked[14].top, 660, "the window sits on the top and has the size of the big one")
    eq(SI.db.tracked[14].left, 600, "the left edges align")
    setup()
    SI.db.tracked[14].size = 128
    SI.ApplyAll()
    drag(14, 910, 290, 700 + 30 - 5, 290 + 260) -- a window larger than the other one, 15 px off its side
    truthy(joined(), "a big window attaches to a small one")
    eq(SI.db.tracked[14].size, 100, "the larger window takes the size of the other one")

    -- a window that is too far away does not attach
    setup()
    drag(14, 910, 290, 910, 290 + 100)
    truthy(not joined(), "a far window stays alone")

    -- a light hint shows where the window will attach while it is dragged
    setup()
    mock.cursor = { 910, 290 }
    SI.BeginMove(14)
    mock.cursor = { 735, 510 }
    tick()
    truthy(ShowItemsSnapHint:IsShown(), "the hint is shown near a window")
    mock.cursor = { 910, 390 }
    tick()
    truthy(not ShowItemsSnapHint:IsShown(), "the hint is hidden when no window is near")
    mock.cursor = { 735, 510 }
    tick()
    truthy(ShowItemsSnapHint:IsShown(), "the hint comes back near a window")
    SI.EndMove()
    truthy(not ShowItemsSnapHint:IsShown(), "the hint is hidden after the drop")
    reset()
end

-- profiles and snapshots
reset()
SI.db.snapshots, SI.db.profiles = {}, {}
SI.Track({ 13, 14 })
SI.SetMeanSize(60)
SI.SetBinding(13, "CTRL-5")
SI.SetAlpha(0.5)
SI.SetLocked(true)
local saved = SI.SaveProfile("  Raid  ")
eq(saved.name, "Raid", "profile name is trimmed")
truthy(saved.time > 0, "profile has a time")
local nameless, nameErr = SI.SaveProfile("   ")
truthy(nameless == nil and nameErr, "empty profile name is rejected")
SI.db.tracked[13].size = 99
eq(saved.data.tracked[13].size, 60, "profile is a copy, not a reference")
SI.db.tracked[13].size = 60
SI.SaveProfile("Raid")
eq(#SI.db.profiles, 1, "saving under the same name overwrites")
saved = SI.db.profiles[1]

SI.ResetAll()
eq(#SI.db.snapshots, 1, "reset takes a snapshot")
eq(SI.db.snapshots[1].label, "Before reset", "reset snapshot label")
SI.ResetAll()
eq(#SI.db.snapshots, 1, "reset of an empty layout takes no snapshot")

SI.LoadProfile(saved)
truthy(SI.db.tracked[13] and SI.db.tracked[14], "profile load restores tracked slots")
eq(SI.db.tracked[14].left, SI.db.tracked[13].left + 60, "profile load keeps the group flush")
eq(SI.db.bindings[13], "CTRL-5", "profile load restores bindings")
eq(SI.db.alpha, 0.5, "profile load restores opacity")
eq(SI.db.locked, true, "profile load restores the lock")
truthy(SI.frames[13]:IsShown() and mock.overrides["CTRL-5"], "profile load shows windows and applies bindings")
eq(#SI.db.snapshots, 1, "loading onto an empty layout takes no snapshot")
SI.db.tracked[13].size = 10
eq(saved.data.tracked[13].size, 60, "loaded layout does not alias the profile")
SI.SetLocked(false)

-- loading over a layout keeps the old one as a snapshot
SI.LoadProfile(saved)
eq(#SI.db.snapshots, 2, "loading over a layout takes a snapshot")
eq(SI.db.snapshots[1].label, "Before loading Raid", "load snapshot label")
eq(SI.db.snapshots[1].data.tracked[13].size, 10, "snapshot holds the replaced layout")

-- snapshot list is limited to the last 5
for _ = 1, 7 do
    SI.Track({ 5 })
    SI.ResetAll()
end
eq(#SI.db.snapshots, SI.MAX_SNAPSHOTS, "only the last 5 snapshots are kept")

-- restoring a snapshot can be undone
reset()
SI.db.snapshots = {}
SI.Track({ 5 })
SI.ResetAll()
SI.Track({ 16 })
SI.RestoreSnapshot(SI.db.snapshots[1])
truthy(SI.db.tracked[5] and not SI.db.tracked[16], "snapshot restore brings the old layout back")
eq(#SI.db.snapshots, 2, "restore saves the replaced layout")
SI.RestoreSnapshot(SI.db.snapshots[1])
truthy(SI.db.tracked[16] and not SI.db.tracked[5], "restore can be undone")

-- loading is deferred in combat
reset()
SI.db.snapshots = {}
mock.combat = true
SI.LoadProfile(saved)
truthy(next(SI.db.tracked) == nil, "profile load is deferred in combat")
mock.combat = false
fire("PLAYER_REGEN_ENABLED")
truthy(SI.db.tracked[13], "profile load applied after combat")

-- broken saved layouts are sanitized on load
SI.LoadProfile({ name = "Broken", data = { tracked = { [13] = { left = "x" }, [99] = { left = 1, top = 1, size = 40 }, [5] = { left = 10, top = 10, size = 9999 } }, bindings = { [5] = 7 }, alpha = 7 } })
truthy(not SI.db.tracked[13] and not SI.db.tracked[99], "invalid slots in a profile are dropped")
eq(SI.db.tracked[5].size, SI.MAX_SIZE, "profile sizes are clamped")
eq(SI.db.alpha, 1, "profile opacity is clamped")
do
    local scaled = { tracked = {}, bindings = {}, windowScale = 99, windowScaleCustom = true }
    SI.SanitizeDB(scaled)
    eq(scaled.windowScale, 4, "saved window scale is clamped")
    scaled = { tracked = {}, bindings = {} }
    SI.SanitizeDB(scaled)
    eq(scaled.windowScale, 1.5, "window scale defaults to 1.5")
    scaled = { tracked = {}, bindings = {}, windowScale = 2 }
    SI.SanitizeDB(scaled)
    eq(scaled.windowScale, 1.5, "a size that was not chosen by the player is replaced by the default")
end
local dirty = { tracked = {}, bindings = {}, profiles = { 5, { name = 1, data = {} }, { name = "ok", data = {}, time = "x" } }, snapshots = { { data = {} }, "bad" } }
SI.SanitizeDB(dirty)
eq(#dirty.profiles, 1, "invalid profiles are dropped")
eq(dirty.profiles[1].time, 0, "profile time is sanitized")
eq(#dirty.snapshots, 1, "invalid snapshots are dropped")

-- delete
SI.DeleteProfile(saved)
eq(#SI.db.profiles, 0, "profile deleted")

-- profiles window
reset()
SI.db.snapshots, SI.db.profiles = {}, {}
SI.Track({ 13 })
SlashCmdList.SHOWITEMS("profiles")
truthy(ShowItemsOptions:IsShown() and SI.ActiveTab() == 3, "/si profiles opens the profiles tab")
truthy(SI.TabFrame(3):IsShown() and not SI.TabFrame(1):IsShown(), "only the active tab content is shown")
local function profileRows(kind)
    local rows = {}
    for _, f in ipairs(mock.frames) do
        if f.rowType == kind then rows[#rows + 1] = f end
    end
    return rows
end
do
    -- the selected tab is in front of the panel, the other tab is tucked behind it
    local panelLevel = SI.TabFrame(3).level
    truthy(ShowItemsTab3.level > panelLevel, "selected tab is drawn above the panel")
    truthy(ShowItemsTab1.level < panelLevel, "inactive tab is drawn behind the panel")
    SI.OpenWindow(1)
    truthy(ShowItemsTab1.level > panelLevel and ShowItemsTab3.level < panelLevel, "switching tabs swaps their draw order")
    SI.OpenWindow(3)

    -- the same name field and 140 x 24 rows as the other tabs
    eq(ShowItemsProfileName.w, 132, "name field is 132 px wide")
    eq(ShowItemsProfileName.h, 20, "name field is 20 px high")
    local firstRow = profileRows("profile")[1]
    truthy(firstRow.w == 140 and firstRow.h == 24, "list rows are 140 x 24")
    truthy(ShowItemsProfileLoad.w == 55 and ShowItemsProfileLoad.h == 28, "buttons are 55 x 28")
    truthy(ShowItemsProfileScrollFrame, "the profile list has a scroll frame")
    truthy(ShowItemsSnapshotScrollFrame == nil and #profileRows("snapshot") == 0, "there is no list of previous states")
    -- Load and Save share a row, Delete is centered under them
    local lp, sp, dp = ShowItemsProfileLoad.points[1], ShowItemsProfileSave.points[1], ShowItemsProfileDelete.points[1]
    truthy(lp[1] == "TOP" and lp[4] == -29.5, "Load is on the left of the center")
    truthy(sp[1] == "LEFT" and sp[2] == ShowItemsProfileLoad and sp[3] == "RIGHT", "Save is on the right of Load, in the same row")
    truthy(dp[1] == "TOP" and dp[2] == ShowItemsProfileLoad and dp[3] == "BOTTOM", "Delete is under Load and Save")
    eq(dp[4], 29.5, "Delete is centered under the pair")
end
ShowItemsProfileName:SetText("Mix")
ShowItemsProfileSave.scripts.OnClick(ShowItemsProfileSave)
eq(#SI.db.profiles, 1, "window saves a profile")
local prow = profileRows("profile")[1]
truthy(prow:IsShown() and prow.name.text == "Mix", "saved profile is listed")
truthy(ShowItemsProfileLoad.enabled and ShowItemsProfileDelete.enabled, "load and delete are active for the saved profile")
SI.ResetAll()
eq(SI.db.snapshots[1].label, "Before reset", "the reset is still saved as a state")
SI.RestoreSnapshot(SI.db.snapshots[1])
truthy(SI.db.tracked[13], "a saved state can still be restored through the API")
prow.scripts.OnClick(prow)
eq(ShowItemsProfileName.text, "Mix", "selecting a profile fills the name")
mock.cursor = { 700, 400 }
ShowItemsProfileDelete.scripts.OnClick(ShowItemsProfileDelete)
truthy(ShowItemsConfirm:IsShown(), "delete asks for confirmation")
eq(#SI.db.profiles, 1, "nothing is deleted before the answer")
local cp = ShowItemsConfirm.points[1]
eq(cp[1], "BOTTOM", "confirm menu sits above the cursor")
eq(cp[4], 700 / ShowItemsConfirm.scale, "confirm menu is centered on the cursor x")
eq(cp[5], 400 / ShowItemsConfirm.scale + 12, "confirm menu is just above the cursor")
ShowItemsConfirmNo.scripts.OnClick(ShowItemsConfirmNo)
truthy(not ShowItemsConfirm:IsShown() and #SI.db.profiles == 1, "cancel keeps the profile")
ShowItemsProfileDelete.scripts.OnClick(ShowItemsProfileDelete)
ShowItemsConfirmYes.scripts.OnClick(ShowItemsConfirmYes)
eq(#SI.db.profiles, 0, "confirm deletes the profile")
truthy(not ShowItemsConfirm:IsShown(), "confirm menu closes after the answer")
mock.chat = {}
ShowItemsProfileDelete.scripts.OnClick(ShowItemsProfileDelete)
truthy(not ShowItemsConfirm:IsShown() and #mock.chat == 1, "delete without a selection only prints a hint")
ShowItemsProfileLoad.scripts.OnClick(ShowItemsProfileLoad)
truthy(#mock.chat == 2, "load without a selection only prints a hint")
truthy(ShowItemsProfileSave.enabled and ShowItemsProfileLoad.enabled and ShowItemsProfileDelete.enabled, "profile buttons stay active")
ShowItemsProfileName:SetText("")
ShowItemsProfileSave.scripts.OnClick(ShowItemsProfileSave)
eq(#SI.db.profiles, 0, "save without a name saves nothing")
ShowItemsOptions:Hide()
SI.OpenWindow(3)
ShowItemsProfileName:SetText("Tmp")
ShowItemsProfileSave.scripts.OnClick(ShowItemsProfileSave)
mock.cursor = { 10, 10 }
ShowItemsProfileDelete.scripts.OnClick(ShowItemsProfileDelete)
truthy(ShowItemsConfirm:IsShown(), "confirm menu is open")
ShowItemsOptions:Hide()
truthy(not ShowItemsConfirm:IsShown(), "closing the window closes the confirm menu")
SI.db.profiles = {}
SI.OpenWindow(3)
truthy(ShowItemsInv1:IsShown() and ShowItemsInv1.icon.vertex[1] == 0.25 and ShowItemsInv13.icon.vertex[1] == 0.25, "all slot buttons are dimmed on the profiles tab, tracked or not")
do
    -- no item menu opens in the Profiles and Settings tabs
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    ShowItemsInv1.scripts.OnEnter(ShowItemsInv1)
    truthy(ShowItemsSetsMenu == nil or not ShowItemsSetsMenu:IsShown(), "hovering a slot opens no item menu on the profiles tab")
    mock.bags = {}
end
ShowItemsOptions:Hide()
SI.OpenWindow(3)
SlashCmdList.SHOWITEMS("profiles")
truthy(not ShowItemsOptions:IsShown(), "/si profiles closes the window when that tab is showing")
ShowItemsTab3.scripts.OnClick(ShowItemsTab3)
SI.OpenWindow(1)
truthy(ShowItemsOptions:IsShown() and SI.ActiveTab() == 1, "tabs switch the content")
ShowItemsTab3.scripts.OnClick(ShowItemsTab3)
eq(SI.ActiveTab(), 3, "clicking a tab selects it")
truthy(not ShowItemsTab3.enabled and ShowItemsTab1.enabled, "the selected tab is disabled, others enabled")
ShowItemsOptions:Hide()
SI.db.snapshots, SI.db.profiles = {}, {}

-- sets
do
    local function chatHas(text)
        for _, m in ipairs(mock.chat) do
            if m:find(text, 1, true) then return true end
        end
        return false
    end
    local function wornId(slot) return mock.worn[slot] and mock.worn[slot].id end
    local function setRow(name)
        for _, f in ipairs(profileRows("set")) do
            if f:IsShown() and f.name.text == name then return f end
        end
    end

    reset()
    SI.db.snapshots, SI.db.profiles = {}, {}
    SI.db.sets, SI.db.nextSetId, SI.db.bindings = {}, 1, {}
    mock.simulate = true
    mock.bags = {}
    mock.worn = {
        [1] = { id = 201, link = "helm-a" }, [11] = { id = 301, link = "ring-a" }, [12] = { id = 302, link = "ring-b" },
        [13] = { id = 401, link = "trink-a" }, [14] = { id = 402, link = "trink-b" },
        [16] = { id = 501, link = "sword" }, [17] = { id = 502, link = "shield" },
    }

    -- saving
    local tankId = SI.SaveSet("  Tank  ", { 1, 5, 11, 12, 13, 14, 16, 17 })
    local tank = SI.db.sets[tankId]
    eq(tank.name, "Tank", "set name is trimmed")
    truthy(tank.slots[1] and tank.slots[1].id == 201 and tank.slots[1].link == "helm-a", "set stores the worn item")
    truthy(tank.slots[5] == nil, "slots that were empty when saving are ignored")
    eq(SI.db.nextSetId, tankId + 1, "set id counter advances")
    local nothing, err = SI.SaveSet("X", { 5 })
    truthy(nothing == nil and err, "saving only empty slots is refused")
    nothing, err = SI.SaveSet("   ", { 1 })
    truthy(nothing == nil and err, "saving without a name is refused")
    local tmpId = SI.SaveSet("Tmp", { 1 })
    SI.db.sets[tmpId].key = "F10"
    mock.worn[1] = { id = 202, link = "helm-b" }
    eq(SI.SaveSet("Tmp", { 1, 16 }), tmpId, "saving under an existing name overwrites that set")
    eq(SI.db.sets[tmpId].slots[1].id, 202, "overwritten set holds the new items")
    eq(SI.db.sets[tmpId].key, "F10", "overwriting keeps the key")
    truthy(SI.db.sets[tmpId].slots[16], "overwriting replaces the slot list")
    SI.DeleteSet(tmpId)
    truthy(SI.db.sets[tmpId] == nil and mock.overrides["F10"] == nil, "deleting a set removes it and its key")
    mock.worn[1] = { id = 201, link = "helm-a" }

    -- sanitizing and defaults
    truthy(next(SI.NewDB().sets) == nil and SI.NewDB().nextSetId == 1, "new databases have an empty set list")
    local dirtySets = { tracked = {}, bindings = {}, nextSetId = 1, sets = {
        [3] = { name = "ok", slots = { [1] = { id = 5, link = 7 }, [99] = { id = 1 }, [2] = { id = "x" } }, key = 5 },
        [4] = { name = "", slots = { [1] = { id = 5 } } },
        [5] = { name = "empty", slots = {} },
        [6] = "bad",
        x = { name = "n", slots = { [1] = { id = 5 } } },
    } }
    SI.SanitizeDB(dirtySets)
    truthy(dirtySets.sets[3] and not dirtySets.sets[4] and not dirtySets.sets[5] and not dirtySets.sets[6] and not dirtySets.sets.x, "invalid sets are dropped")
    truthy(dirtySets.sets[3].slots[1] and not dirtySets.sets[3].slots[99] and not dirtySets.sets[3].slots[2], "invalid set slots are dropped")
    eq(dirtySets.sets[3].slots[1].link, nil, "invalid item link is dropped")
    eq(dirtySets.sets[3].key, nil, "invalid set key is dropped")
    eq(dirtySets.nextSetId, 4, "id counter stays above the highest set id")

    -- planning: only differences are equipped, worn items that match stay
    eq(#SI.PlanSet(tank), 0, "a set that is already worn needs no swaps")
    mock.bags = { [0] = { n = 2,
        { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 },
        { link = "trink-b", id = 402, loc = "INVTYPE_TRINKET", icon = 2 },
    }, [-1] = { n = 1, { link = "ring-z", id = 399, loc = "INVTYPE_FINGER", icon = 4 } } }
    mock.worn[1] = { id = 202, link = "helm-b" }
    mock.worn[11], mock.worn[12] = { id = 302, link = "ring-b" }, { id = 301, link = "ring-a" } -- worn in the other order
    mock.worn[14] = { id = 404, link = "trink-d" }
    local steps = SI.PlanSet(tank)
    eq(#steps, 2, "rings worn in any order and matching items are left alone")
    truthy(steps[1].slot == 1 and steps[1].id == 201 and steps[2].slot == 14 and steps[2].id == 402, "only the differing slots are planned")
    eq(SI.SetIcon(tank), 7, "set icon is the icon of its first item")

    -- equipping from the bags, one item at a time
    mock.equipLog, mock.chat = {}, {}
    SI.EquipSet(tank)
    eq(wornId(1), 201, "set equips the head item from the bag")
    eq(wornId(14), 402, "set equips the trinket from the bag")
    eq(#mock.equipLog, 2, "only two items were equipped")
    truthy(mock.equipLog[1][2] == 1 and mock.equipLog[2][2] == 14, "items are equipped one by one in slot order")
    truthy(mock.bags[0][1] and mock.bags[0][1].link == "helm-b", "the replaced item goes to the bag")
    eq(#mock.chat, 0, "a successful swap prints nothing")

    -- rings: keep the wanted ring that is worn, put the other into the free slot
    mock.bags = { [0] = { n = 3, { link = "ring-b", id = 302, loc = "INVTYPE_FINGER", icon = 1 } } }
    mock.worn[11], mock.worn[12] = { id = 303, link = "ring-c" }, { id = 301, link = "ring-a" }
    steps = SI.PlanSet(tank)
    truthy(#steps == 1 and steps[1].slot == 11 and steps[1].id == 302, "the worn wanted ring stays, the other goes to the free slot")
    -- neither worn: first to the first slot, second to the second
    mock.worn[11], mock.worn[12] = { id = 303, link = "ring-c" }, { id = 304, link = "ring-d" }
    steps = SI.PlanSet(tank)
    truthy(#steps == 2 and steps[1].slot == 11 and steps[1].id == 301 and steps[2].slot == 12 and steps[2].id == 302, "rings go first to first, second to second")
    -- one wanted ring that is worn in the other slot is already fine
    local oneRing = { name = "Ring", slots = { [12] = { id = 301, link = "ring-a" } } }
    mock.worn[11], mock.worn[12] = { id = 301, link = "ring-a" }, { id = 304, link = "ring-d" }
    eq(#SI.PlanSet(oneRing), 0, "a single wanted ring worn in the other slot needs no swap")
    mock.worn[11] = { id = 303, link = "ring-c" }
    steps = SI.PlanSet(oneRing)
    truthy(#steps == 1 and steps[1].slot == 12, "a single wanted ring goes to its own slot")
    -- real swap
    mock.bags = { [0] = { n = 3,
        { link = "ring-a", id = 301, loc = "INVTYPE_FINGER", icon = 1 },
        { link = "ring-b", id = 302, loc = "INVTYPE_FINGER", icon = 2 },
    } }
    mock.worn[11], mock.worn[12] = { id = 303, link = "ring-c" }, { id = 304, link = "ring-d" }
    mock.equipLog = {}
    SI.EquipSet(tank)
    truthy(wornId(11) == 301 and wornId(12) == 302, "rings are equipped from the bag")

    -- the same bag item is never taken twice
    local twice = { name = "Twice", slots = { [11] = { id = 301, link = "ring-a" }, [12] = { id = 301, link = "ring-a" } } }
    mock.bags = { [0] = { n = 3, { link = "ring-a", id = 301, loc = "INVTYPE_FINGER", icon = 1 } } }
    mock.worn[11], mock.worn[12] = { id = 303, link = "ring-c" }, { id = 304, link = "ring-d" }
    mock.equipLog, mock.chat = {}, {}
    SI.EquipSet(twice)
    eq(#mock.equipLog, 1, "one bag item is equipped once")
    eq(wornId(12), 304, "the second slot keeps its item when no second copy exists")
    truthy(chatHas("not in your bags"), "a missing item is reported")

    -- weapons: main hand before off hand, whatever the order in the set
    local weapons = { name = "Weapons", slots = { [17] = { id = 602, link = "dagger" }, [16] = { id = 601, link = "axe" } } }
    mock.bags = { [0] = { n = 3,
        { link = "dagger", id = 602, loc = "INVTYPE_WEAPON", icon = 1 },
        { link = "axe", id = 601, loc = "INVTYPE_WEAPON", icon = 2 },
    } }
    mock.worn[16], mock.worn[17] = { id = 501, link = "sword" }, { id = 502, link = "shield" }
    steps = SI.PlanSet(weapons)
    truthy(steps[1].slot == 16 and steps[2].slot == 17, "main hand is planned before off hand")
    mock.equipLog = {}
    SI.EquipSet(weapons)
    truthy(mock.equipLog[1][2] == 16 and mock.equipLog[2][2] == 17, "main hand is equipped before off hand")

    -- items that are nowhere in the bags (the bank does not count)
    mock.bags = { [-1] = { n = 1, { link = "gone", id = 999, loc = "INVTYPE_HEAD", icon = 1 } } }
    mock.chat, mock.equipLog = {}, {}
    SI.EquipSet({ name = "Gone", slots = { [1] = { id = 999, link = "gone" } } })
    truthy(chatHas("not in your bags") and chatHas("gone"), "items in the bank are reported as missing")
    eq(#mock.equipLog, 0, "nothing is equipped from the bank")

    -- combat
    mock.worn[1] = { id = 202, link = "helm-b" }
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    local head = { name = "Head", slots = { [1] = { id = 201, link = "helm-a" } } }
    mock.chat, mock.equipLog = {}, {}
    mock.combat = true
    SI.EquipSet(tank)
    truthy(chatHas("combat") and #mock.equipLog == 0, "sets are not equipped in combat")
    mock.chat = {}
    SI.EquipSet(tank, true)
    truthy(chatHas("only weapons"), "a set key in combat explains that only weapons change")
    mock.chat = {}
    SI.EquipSet(weapons, true)
    eq(#mock.chat, 0, "a weapon-only set key is silent in combat (the secure macro swaps)")
    mock.combat = false

    -- item locks
    mock.lockPolls = 3
    mock.equipLog = {}
    SI.EquipSet(head)
    eq(wornId(1), 201, "the swap waits for item locks and then equips")
    eq(#mock.equipLog, 1, "no extra equips while waiting")
    mock.worn[1] = { id = 202, link = "helm-b" }
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    mock.locked[5] = true
    mock.chat = {}
    SI.EquipSet(head)
    truthy(chatHas("stayed locked") and wornId(1) == 202, "a swap stops when items stay locked")
    mock.locked[5] = nil
    SI.EquipSet(head)
    eq(wornId(1), 201, "a new swap can start after a stopped one")

    -- something on the cursor
    mock.worn[1] = { id = 202, link = "helm-b" }
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    local realCursorHasItem = CursorHasItem
    CursorHasItem = function() return true end
    mock.chat = {}
    SI.EquipSet(head)
    CursorHasItem = realCursorHasItem
    truthy(chatHas("cursor") and wornId(1) == 202, "nothing is equipped while the cursor holds an item")

    -- an equip that does not take effect is retried a limited number of times
    mock.simulate = false
    mock.equipLog, mock.chat = {}, {}
    SI.EquipSet(head)
    eq(#mock.equipLog, 3, "a failing equip is tried three times")
    truthy(chatHas("could not equip"), "a failing equip is reported")
    mock.simulate = true

    -- an error in the swap does not block later swaps
    local realEquip = C_Item.EquipItemByName
    C_Item.EquipItemByName = function() error("boom") end
    SI.EquipSet(head)
    C_Item.EquipItemByName = realEquip
    eq(#mock.errors, 1, "an error during a swap is reported")
    mock.errors = {}
    mock.equipLog = {}
    SI.EquipSet(head)
    eq(wornId(1), 201, "a swap works again after an error")

    -- key bindings
    SI.Track({ 13 })
    SI.SetBinding(13, "CTRL-8")
    eq(mock.overrides["CTRL-8"][1], "ShowItemsSlot13", "slot key is bound to the tracker")
    SI.SetSetBinding(tankId, "CTRL-8")
    truthy(SI.db.bindings[13] == nil, "a set key removes the same key from a slot")
    eq(SI.db.sets[tankId].key, "CTRL-8", "set key is stored")
    eq(mock.overrides["CTRL-8"][1], "ShowItemsSet" .. tankId, "set key is bound to the set button")
    local setButton = _G["ShowItemsSet" .. tankId]
    eq(setButton.attrs.type, "macro", "set button runs a macro")
    local macro = setButton.attrs.macrotext
    truthy(macro:find("/stopmacro [nocombat]", 1, true), "macro does nothing outside combat")
    truthy(macro:find("/equipslot 16 item:501", 1, true) and macro:find("/equipslot 17 item:502", 1, true), "macro equips the weapons by item id")
    truthy(not macro:find("/equipslot 1 item", 1, true), "macro has no armor")
    SI.SetBinding(13, "CTRL-8")
    eq(SI.db.sets[tankId].key, nil, "a slot key removes the same key from a set")
    eq(mock.overrides["CTRL-8"][1], "ShowItemsSlot13", "the slot owns the key again")
    SI.SetBinding(13, "Shift-3")
    local otherId = SI.SaveSet("Other", { 1 })
    SI.SetSetBinding(tankId, "CTRL-9")
    SI.SetSetBinding(otherId, "CTRL-9")
    truthy(SI.db.sets[tankId].key == nil and SI.db.sets[otherId].key == "CTRL-9", "two sets cannot share a key")
    eq(mock.overrides["CTRL-9"][1], "ShowItemsSet" .. otherId, "the key belongs to the last set")
    eq(mock.overrides["Shift-3"][1], "ShowItemsSlot13", "set bindings leave slot bindings alone")

    -- the set key runs the swap before the click (outside combat)
    mock.worn[1] = { id = 202, link = "helm-b" }
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    local otherButton = _G["ShowItemsSet" .. otherId]
    otherButton.scripts.PreClick(otherButton)
    eq(wornId(1), 201, "the set key equips the set")

    -- bindings are applied after combat, cleared when disabled, restored when enabled
    mock.combat = true
    SI.SetSetBinding(otherId, "CTRL-7")
    eq(SI.db.sets[otherId].key, "CTRL-7", "set key is stored in combat")
    truthy(mock.overrides["CTRL-7"] == nil, "set key is applied after combat")
    mock.combat = false
    fire("PLAYER_REGEN_ENABLED")
    truthy(mock.overrides["CTRL-7"], "set key is applied when combat ends")
    SI.SetEnabled(false)
    truthy(mock.overrides["CTRL-7"] == nil, "set keys are cleared when the addon is disabled")
    SI.SetEnabled(true)
    truthy(mock.overrides["CTRL-7"], "set keys return when the addon is enabled")
    SI.SetSetBinding(otherId, nil)
    truthy(SI.db.sets[otherId].key == nil and mock.overrides["CTRL-7"] == nil, "unbinding removes the set key")
    SI.SetSetBinding(otherId, "CTRL-6")
    SI.DeleteSet(otherId)
    truthy(SI.db.sets[otherId] == nil and mock.overrides["CTRL-6"] == nil, "deleting a set removes its key")

    -- a loaded layout that uses a set key takes the key from the set
    SI.SetSetBinding(tankId, "CTRL-5")
    SI.LoadProfile({ name = "K", data = { tracked = { [13] = { left = 100, top = 200, size = 40 } },
        bindings = { [13] = "CTRL-5" }, alpha = 1, locked = false, nextGroup = 1 } })
    eq(SI.db.sets[tankId].key, nil, "a restored slot key wins over a set key")
    eq(mock.overrides["CTRL-5"][1], "ShowItemsSlot13", "the restored slot key is bound")
    SI.db.snapshots = {}

    -- the tab
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    mock.worn = { [1] = { id = 201, link = "helm-a" }, [13] = { id = 401, link = "trink-a" } }
    mock.equipped = { [1] = "tex-helm", [13] = "tex-trink" }
    ShowItemsOptions:Hide()
    SlashCmdList.SHOWITEMS("sets")
    truthy(ShowItemsOptions:IsShown() and SI.ActiveTab() == 2, "/si sets opens the sets tab")
    eq(SI.TabFrame(2).points[1][1], "TOP", "the sets panel sits between the slot columns")
    truthy(ShowItemsInv1:IsShown() and ShowItemsInv19:IsShown(), "all slot buttons are shown on the sets tab")
    eq(ShowItemsInv13.icon.vertex[1], 0.25, "unselected slots are dimmed")
    ShowItemsInv13.scripts.OnClick(ShowItemsInv13)
    eq(ShowItemsInv13.icon.vertex[1], 1, "a clicked slot is bright")
    ShowItemsInv13.scripts.OnClick(ShowItemsInv13)
    eq(ShowItemsInv13.icon.vertex[1], 0.25, "clicking again removes the slot")

    -- sizes of the ItemRack Sets tab
    eq(ShowItemsSetsName.w, 132, "name field is 132 px wide")
    eq(ShowItemsSetsName.h, 20, "name field is 20 px high")
    eq(ShowItemsSetsSave.w, 55, "buttons are 55 px wide")
    eq(ShowItemsSetsSave.h, 28, "buttons are 28 px high")
    truthy(ShowItemsSetsSave.enabled and ShowItemsSetsEquip.enabled and ShowItemsSetsBind.enabled and ShowItemsSetsDelete.enabled, "set buttons stay active")
    eq(ShowItemsSetsIcon1.w, 32, "icon buttons are 32 px (28 px of ItemRack plus 15%)")
    eq(ShowItemsSetsIcon1.icon.w, 30, "the pictures are 30 px")
    truthy(ShowItemsSetsIcon16 and not ShowItemsSetsIcon17, "the grid shows 4 columns and 4 rows")
    eq(ShowItemsSetsDrop.w, 18, "the list button is 18 px")
    eq(ShowItemsSetsCurrent.w, 36, "the set picture is 36 px")

    -- toggle all slots
    truthy(ShowItemsToggleAll:IsShown(), "Toggle All is shown on the sets tab")
    ShowItemsToggleAll.scripts.OnClick(ShowItemsToggleAll)
    truthy(ShowItemsInv1.icon.vertex[1] == 1 and ShowItemsInv19.icon.vertex[1] == 1 and ShowItemsInv13.icon.vertex[1] == 1, "Toggle All selects every slot")
    ShowItemsToggleAll.scripts.OnClick(ShowItemsToggleAll)
    truthy(ShowItemsInv1.icon.vertex[1] == 0.25 and ShowItemsInv19.icon.vertex[1] == 0.25, "Toggle All clears every slot")
    SI.OpenWindow(1)
    truthy(not ShowItemsToggleAll:IsShown(), "Toggle All is hidden on tabs without slot selection")
    SI.OpenWindow(2)

    -- pictures: the first 20 show the items of the slots, then banners
    eq(ShowItemsSetsIcon2.icon.texture, "tex-helm", "the second picture is the item of the first slot")
    -- the first 20 pictures are 5 rows of 4 and 4 rows show; the mock has no spell pictures, so the
    -- list is 22 pictures (6 rows) and the furthest scroll shows rows 3 to 6: the banners are the 13th and 14th buttons
    local iconScroll = ShowItemsSetsIconScrollFrame
    iconScroll.scripts.OnVerticalScroll(iconScroll, 5 * 32)
    truthy(ShowItemsSetsIcon14:IsShown() and not ShowItemsSetsIcon15:IsShown(), "pictures that do not exist are hidden")
    ShowItemsSetsIcon13.scripts.OnClick(ShowItemsSetsIcon13)
    iconScroll.scripts.OnVerticalScroll(iconScroll, 0)

    for _, slot in ipairs({ 1, 5, 13 }) do
        local button = _G["ShowItemsInv" .. slot]
        button.scripts.OnClick(button)
    end
    ShowItemsSetsName:SetText("UI set")
    ShowItemsSetsName.scripts.OnEnterPressed(ShowItemsSetsName)
    truthy(SI.FindSetByName("UI set") == nil, "Enter in the name field does not save")
    ShowItemsSetsSave.scripts.OnClick(ShowItemsSetsSave)
    local uiId, uiSet = SI.FindSetByName("UI set")
    truthy(uiSet and uiSet.slots[1] and uiSet.slots[13] and not uiSet.slots[5], "Save stores the worn items of the selected slots")
    eq(uiSet.icon, "Interface\\Icons\\INV_Banner_02", "Save stores the chosen picture")
    eq(SI.SetIcon(uiSet), "Interface\\Icons\\INV_Banner_02", "the set shows the chosen picture")
    eq(ShowItemsSetsCurrent.icon.texture, "Interface\\Icons\\INV_Banner_02", "the big picture shows the chosen picture")
    eq(ShowItemsInv5.icon.vertex[1], 0.25, "a slot without an item is deselected after saving")

    -- the list of sets
    local picker = ShowItemsSetPicker
    truthy(not picker:IsShown(), "the list of sets is closed at first")
    ShowItemsSetsDrop.scripts.OnClick(ShowItemsSetsDrop)
    truthy(picker:IsShown(), "the arrow opens the list of sets")
    local escapable = {}
    for _, name in ipairs(UISpecialFrames) do escapable[name] = true end
    truthy(escapable.ShowItemsSetPicker and not escapable.ShowItemsOptions, "Escape closes only the list while it is open")
    local row = setRow("UI set")
    local tankRow = setRow("Tank")
    truthy(row and tankRow, "the saved sets are listed")
    tankRow.scripts.OnEnter(tankRow)
    eq(ShowItemsInv16.icon.vertex[1], 1, "hovering a set in the list shows its slots")
    picker:Hide()
    eq(ShowItemsInv16.icon.vertex[1], 0.25, "closing the list without a pick puts back what was there")
    eq(ShowItemsSetsName.text, "UI set", "the name is put back too")
    escapable = {}
    for _, name in ipairs(UISpecialFrames) do escapable[name] = true end
    truthy(escapable.ShowItemsOptions and not escapable.ShowItemsSetPicker, "Escape closes the window again after the list is closed")
    ShowItemsSetsDrop.scripts.OnClick(ShowItemsSetsDrop)
    tankRow = setRow("Tank")
    tankRow.scripts.OnClick(tankRow)
    truthy(not picker:IsShown(), "picking a set closes the list")
    eq(ShowItemsSetsName.text, "Tank", "picking a set fills the name")
    truthy(ShowItemsInv16.icon.vertex[1] == 1 and ShowItemsInv5.icon.vertex[1] == 0.25, "picking a set selects its slots")

    -- the menu of items opens next to a slot while the mouse is over it
    mock.bags = { [0] = { n = 3,
        { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 },
        { link = "axe2", id = 701, loc = "INVTYPE_WEAPON", icon = 9, count = 1 },
        { link = "boots", id = 702, loc = "INVTYPE_FEET", icon = 8 },
    } }
    local menu = ShowItemsSetsMenu
    local function menuItems()
        local list = {}
        for _, f in ipairs(mock.frames) do
            if f.parent == menu and f.entry and f:IsShown() then list[#list + 1] = f end
        end
        return list
    end
    ShowItemsInv16.scale = 1.5
    ShowItemsInv16.scripts.OnEnter(ShowItemsInv16)
    truthy(menu:IsShown(), "hovering a slot opens the item menu without a click")
    local listed = menuItems()
    truthy(#listed == 1 and listed[1].entry.link == "axe2", "the menu lists the bag items that fit the slot")
    truthy(menu.points[1][1] == "TOPLEFT" and menu.points[1][3] == "BOTTOMLEFT" and menu.points[1][4] == -8, "the menu of a weapon slot opens below it")
    eq(menu.scale, 1.5, "the menu has the scale of the window")
    eq(menu.w, 52, "the menu is 8 px wider than a button on each side")
    eq(listed[1].w, 36, "menu buttons are 36 px")
    ShowItemsInv16.mouseOver = true
    tick()
    truthy(menu:IsShown(), "the menu stays open while the mouse is over the slot")
    ShowItemsInv16.mouseOver = false
    tick()
    truthy(not menu:IsShown(), "the menu closes when the mouse is over neither the slot nor the menu")
    ShowItemsInv1.scripts.OnEnter(ShowItemsInv1)
    listed = menuItems()
    truthy(#listed == 1 and listed[1].entry.link == "helm-a", "the worn item is not listed, only the bag items")
    mock.bags[0][4] = { link = "helm-c", id = 203, loc = "INVTYPE_HEAD", icon = 6 }
    mock.bags[0].n = 4
    ShowItemsInv1.scripts.OnEnter(ShowItemsInv1)
    listed = menuItems()
    truthy(#listed == 2 and listed[1].entry.link == "helm-a" and listed[2].entry.link == "helm-c", "several bag items are listed")
    truthy(menu.points[1][1] == "TOPRIGHT" and menu.points[1][3] == "TOPLEFT", "the menu of a left column slot opens to the left")
    eq(menu.w, 8 + 40 + 36 + 8, "a menu next to a column runs outward in one row")
    eq(menu.h, 8 + 36 + 8, "a sideways menu with two items is one button high")
    truthy(listed[2].points[1][4] == -48 and listed[2].points[1][5] == -8, "the second button is next to the first, not below it")
    mock.bags[0][5] = { link = "trinket-a", id = 801, loc = "INVTYPE_TRINKET", icon = 5 }
    mock.bags[0].n = 5
    ShowItemsInv13.scripts.OnEnter(ShowItemsInv13)
    truthy(menu.points[1][1] == "TOPLEFT" and menu.points[1][3] == "TOPRIGHT" and menu.points[1][5] == 8, "the menu of a right column slot opens to the right")
    ShowItemsInv3.scripts.OnEnter(ShowItemsInv3)
    truthy(not menu:IsShown(), "no menu opens for a slot without items")
    ShowItemsInv16.scripts.OnEnter(ShowItemsInv16)
    listed = menuItems()
    listed[1].scripts.OnClick(listed[1], "LeftButton")
    truthy(not menu:IsShown(), "the menu closes after a pick")
    eq(ShowItemsInv16.icon.vertex[1], 1, "the slot of a picked item is selected")
    eq(ShowItemsInv16.icon.texture, 9, "the slot shows the picked item")
    ShowItemsSetsName:SetText("Pick")
    ShowItemsSetsSave.scripts.OnClick(ShowItemsSetsSave)
    local pickId, pickSet = SI.FindSetByName("Pick")
    truthy(pickSet and pickSet.slots[16] and pickSet.slots[16].id == 701 and pickSet.slots[16].link == "axe2", "Save stores the picked item, not the worn one")
    eq(pickSet.slots[1] and pickSet.slots[1].id, 201, "slots without a pick keep their set item")
    ShowItemsInv16.scripts.OnClick(ShowItemsInv16)
    eq(ShowItemsInv16.icon.vertex[1], 0.25, "clicking a slot with a picked item deselects it")
    SI.DeleteSet(pickId)
    SI.RefreshWindow()

    -- the item menu does not open in the Settings and Profiles tabs
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    mock.worn[1] = { id = 202, link = "helm-b" }
    for _, tabId in ipairs({ 1, 3 }) do
        local tabButton = _G["ShowItemsTab" .. tabId]
        tabButton.scripts.OnClick(tabButton)
        menu:Hide()
        ShowItemsInv1.scripts.OnEnter(ShowItemsInv1)
        truthy(not menu:IsShown(), "hovering a slot opens no item menu in tab " .. tabId)
        eq(wornId(1), 202, "nothing is equipped by hovering in tab " .. tabId)
    end
    ShowItemsTab2.scripts.OnClick(ShowItemsTab2)

    -- Equip, Bind Key and Delete work on the selected set
    ShowItemsSetsDrop.scripts.OnClick(ShowItemsSetsDrop)
    row = setRow("UI set")
    row.scripts.OnClick(row)
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    mock.worn[1] = { id = 202, link = "helm-b" }
    ShowItemsSetsEquip.scripts.OnClick(ShowItemsSetsEquip)
    eq(wornId(1), 201, "the Equip button equips the selected set")
    ShowItemsSetsBind.scripts.OnClick(ShowItemsSetsBind)
    truthy(ShowItemsBindFrame:IsShown(), "Bind Key opens the key capture")
    ShowItemsBindFrame.scripts.OnKeyDown(ShowItemsBindFrame, "F5")
    eq(uiSet.key, "F5", "the captured key is stored on the set")
    ShowItemsSetsDrop.scripts.OnClick(ShowItemsSetsDrop)
    eq(setRow("UI set").info.text, "F5", "the key is shown in the list")
    picker:Hide()
    ShowItemsSetsBind.scripts.OnClick(ShowItemsSetsBind)
    for _, f in ipairs(mock.frames) do
        if f.parent == ShowItemsBindFrame and f.text == "Unbind" then f.scripts.OnClick(f) end
    end
    eq(uiSet.key, nil, "Unbind removes the set key")

    -- minimap: the list of sets is drawn above the tooltip; picking a set equips it
    mock.bags = { [0] = { n = 1, { link = "helm-a", id = 201, loc = "INVTYPE_HEAD", icon = 7 } } }
    mock.worn[1] = { id = 202, link = "helm-b" }
    GameTooltip.level = 50
    mini.scripts.OnEnter(mini)
    mini.scripts.OnClick(mini, "LeftButton")
    local setMenu = ShowItemsSetMenu
    truthy(setMenu and setMenu:IsShown(), "left click on the minimap button lists the sets")
    eq(setMenu.strata, "TOOLTIP", "the set list is in the tooltip strata")
    truthy(setMenu.level > GameTooltip.level, "the set list is above the minimap tooltip")
    local entries = {}
    for _, f in ipairs(mock.frames) do
        if f.parent == setMenu and f.entry and f:IsShown() then entries[#entries + 1] = f end
    end
    eq(#entries, 2, "every saved set is listed")
    truthy(entries[1].level > GameTooltip.level, "set buttons are above the tooltip")
    eq(entries[1].w, 31, "set buttons are as large as the minimap button")
    eq(setMenu.scale, 1, "the set list has the scale of the minimap button")
    eq(entries[1].label.text, "", "a round set button has no label, the name is in the tooltip")
    truthy(entries[1].border and entries[1].border.texture == "Interface\\Minimap\\MiniMap-TrackingBorder", "set buttons have the gold ring of the minimap button")
    eq(setMenu.points[1][1], "BOTTOMRIGHT", "the list opens above a button in the lower half of the screen")
    mini.scripts.OnClick(mini, "LeftButton")
    truthy(not setMenu:IsShown(), "a second click on the minimap button closes the list")
    mini.scripts.OnClick(mini, "LeftButton")
    local uiEntry
    for _, f in ipairs(entries) do
        if f.entry.label == "UI set" then uiEntry = f end
    end
    uiEntry.scripts.OnClick(uiEntry, "LeftButton")
    eq(wornId(1), 201, "clicking a set in the list equips it")
    truthy(not setMenu:IsShown(), "the list closes after a pick")
    mock.mouseDown.LeftButton = false
    mini.scripts.OnClick(mini, "LeftButton")
    tick()
    mock.mouseDown.LeftButton = true
    ShowItemsSetMenu.mouseOver = false
    tick()
    truthy(not setMenu:IsShown(), "the list closes when the mouse is pressed outside it")
    mock.mouseDown.LeftButton = false
    GameTooltip.level = nil

    -- scrolling a long list
    for i = 1, 10 do SI.db.sets[100 + i] = { name = string.format("S%02d", i), slots = { [1] = { id = 201 } } } end
    SI.db.nextSetId = 200
    ShowItemsSetsDrop.scripts.OnClick(ShowItemsSetsDrop)
    local pickScroll = ShowItemsSetPickerScrollFrame
    local firstName = profileRows("set")[1].name.text
    pickScroll.scripts.OnVerticalScroll(pickScroll, 24)
    truthy(profileRows("set")[1].name.text ~= firstName, "the list of sets scrolls")
    pickScroll.scripts.OnVerticalScroll(pickScroll, 0)
    eq(profileRows("set")[1].name.text, firstName, "the list scrolls back to its start")
    picker:Hide()
    for i = 1, 10 do SI.db.sets[100 + i] = nil end
    SI.RefreshWindow()

    -- buttons without a selected set only print a hint; delete asks first
    mock.cursor = { 10, 10 }
    ShowItemsSetsDelete.scripts.OnClick(ShowItemsSetsDelete)
    truthy(ShowItemsConfirm:IsShown() and SI.FindSetByName("UI set"), "delete asks for confirmation")
    ShowItemsConfirmYes.scripts.OnClick(ShowItemsConfirmYes)
    truthy(SI.FindSetByName("UI set") == nil, "confirm deletes the set")
    mock.chat = {}
    ShowItemsSetsEquip.scripts.OnClick(ShowItemsSetsEquip)
    ShowItemsSetsBind.scripts.OnClick(ShowItemsSetsBind)
    ShowItemsSetsDelete.scripts.OnClick(ShowItemsSetsDelete)
    eq(#mock.chat, 3, "Equip, Bind Key and Delete without a selected set print hints")
    truthy(not ShowItemsBindFrame:IsShown() and not ShowItemsConfirm:IsShown(), "no panel opens without a selected set")
    mock.chat = {}
    ShowItemsSetsName:SetText("")
    ShowItemsSetsSave.scripts.OnClick(ShowItemsSetsSave)
    eq(#mock.chat, 1, "Save without a name prints a hint")
    do
        local iconSet = SI.SaveSet("Icon", { 1 }, nil, "pic")
        eq(SI.db.sets[iconSet].icon, "pic", "a set stores its picture")
        SI.SaveSet("Icon", { 1 })
        eq(SI.db.sets[iconSet].icon, "pic", "saving without a picture keeps the old one")
        local sane = { tracked = {}, bindings = {}, sets = { [1] = { name = "a", icon = {}, slots = { [1] = { id = 5 } } }, [2] = { name = "b", icon = 7, slots = { [1] = { id = 5 } } } } }
        SI.SanitizeDB(sane)
        truthy(sane.sets[1].icon == nil and sane.sets[2].icon == 7, "an invalid picture is dropped")
    end

    ShowItemsOptions:Hide()
    mock.simulate = false
    mock.worn, mock.bags, mock.locked, mock.equipped = {}, {}, {}, {}
    SI.db.sets = {}    SI.db.snapshots, SI.db.profiles = {}, {}
end

-- slash commands
mock.chat = {}
SlashCmdList.SHOWITEMS("help")
truthy(#mock.chat >= 3, "help prints commands")
SlashCmdList.SHOWITEMS("reset")
truthy(next(SI.db.tracked) == nil, "/si reset untracks everything")
truthy(next(SI.db.bindings) == nil, "/si reset clears bindings")
SI.OpenWindow(1)
ShowItemsOptions:Hide()
SlashCmdList.SHOWITEMS("")
truthy(ShowItemsOptions:IsShown() and SI.ActiveTab() == 1, "/si opens settings")
SlashCmdList.SHOWITEMS("")
truthy(not ShowItemsOptions:IsShown(), "/si closes settings")

-- the window opens on the tab that was used last
SI.OpenWindow(2)
eq(SI.db.lastTab, 2, "the shown tab is remembered")
ShowItemsOptions:Hide()
SlashCmdList.SHOWITEMS("")
eq(SI.ActiveTab(), 2, "/si opens the tab used last")
ShowItemsOptions:Hide()
mini.scripts.OnClick(mini, "RightButton")
truthy(ShowItemsOptions:IsShown() and SI.ActiveTab() == 2, "right click on the minimap button opens the tab used last")
ShowItemsTab3.scripts.OnClick(ShowItemsTab3)
eq(SI.db.lastTab, 3, "switching tabs is remembered")
mini.scripts.OnClick(mini, "RightButton")
truthy(not ShowItemsOptions:IsShown(), "right click on the minimap button closes the open window")
mini.scripts.OnClick(mini, "RightButton")
eq(SI.ActiveTab(), 3, "the window reopens on the tab that was open when it was closed")
SI.db.lastTab = 99
ShowItemsOptions:Hide()
mini.scripts.OnClick(mini, "RightButton")
eq(SI.ActiveTab(), 1, "an unknown remembered tab falls back to the first tab")
local badTab = { tracked = {}, bindings = {}, lastTab = "x" }
SI.SanitizeDB(badTab)
eq(badTab.lastTab, nil, "an invalid remembered tab is dropped")
ShowItemsOptions:Hide()

-- saved data sanitizing
local bad = { tracked = { [13] = { left = "x" }, [99] = { left = 1, top = 1 }, [14] = { left = 5, top = 5, size = 9999 } }, bindings = { [13] = 5 } }
SI.SanitizeDB(bad)
truthy(bad.tracked[13] == nil and bad.tracked[99] == nil, "invalid trackers dropped")
eq(bad.tracked[14].size, SI.MAX_SIZE, "size clamped")
truthy(bad.bindings[13] == nil, "invalid binding dropped")

print(string.format("%d passed, %d failed", passed, failed))
if #mock.errors > 0 then
    print("Lua errors captured:")
    for _, e in ipairs(mock.errors) do print("  " .. e) end
end
local unknown = {}
for k in pairs(undefinedReads) do unknown[#unknown + 1] = k end
table.sort(unknown)
print("undefined global reads: " .. table.concat(unknown, ", "))
local methods = {}
for k in pairs(mock.called) do methods[#methods + 1] = k end
table.sort(methods)
print("generic (unmocked) methods used: " .. table.concat(methods, ", "))
os.exit(failed == 0 and 0 or 1)

