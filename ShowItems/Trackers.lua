local _, SI = ...

local floor, max, min, abs, huge = math.floor, math.max, math.min, math.abs, math.huge

local EPS = 1.5
local frames = {}
SI.frames = frames

local INVERSE_SIDE = { R = "L", L = "R", U = "D", D = "U" }

local resizeSlot -- window whose group currently shows the resize triangle
local UpdateHandle -- defined below
local ComputeSnap, ShowSnapHint, HideSnapHint -- defined below (magnet)

------------------------------------------------------------------------
-- Geometry helpers. A tracker is stored as { left, top, size, group, moved }
-- in UIParent coordinates (origin bottom-left, top = y of the top edge).
------------------------------------------------------------------------

local function Tracked()
    return SI.db.tracked
end

local function Rect(t)
    return t.left, t.left + t.size, t.top, t.top - t.size -- L, R, T, B
end

local function Cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

function SI.IsTracked(slot)
    return SI.db.tracked[slot] ~= nil
end

-- Bounding box (left, right, top, bottom) of the group that contains slot.
function SI.GroupBounds(slot)
    local tr = Tracked()
    local members = SI.GroupMembers(slot)
    if #members == 0 then return nil end
    local minL, maxR, maxT, minB = huge, -huge, -huge, huge
    for _, s in ipairs(members) do
        local l, r, top, bottom = Rect(tr[s])
        minL, maxR, maxT, minB = min(minL, l), max(maxR, r), max(maxT, top), min(minB, bottom)
    end
    return minL, maxR, maxT, minB
end

------------------------------------------------------------------------
-- Groups (windows stuck together by the magnet)
------------------------------------------------------------------------

function SI.GroupMembers(slot)
    local tr = Tracked()
    local t = tr[slot]
    if not t then return {} end
    if not t.group then return { slot } end
    local list = {}
    for s, o in pairs(tr) do
        if o.group == t.group then list[#list + 1] = s end
    end
    table.sort(list)
    return list
end

local function NormalizeGroups()
    local tr = Tracked()
    local count = {}
    for _, t in pairs(tr) do
        if t.group then count[t.group] = (count[t.group] or 0) + 1 end
    end
    for _, t in pairs(tr) do
        if t.group and count[t.group] < 2 then t.group = nil end
    end
end

local function JoinGroups(slotA, slotB)
    local db = SI.db
    local tr = db.tracked
    local a, b = tr[slotA], tr[slotB]
    local id = a.group or b.group
    if not id then
        id = db.nextGroup
        db.nextGroup = id + 1
    end
    local oldA, oldB = a.group, b.group
    for _, t in pairs(tr) do
        if (oldA and t.group == oldA) or (oldB and t.group == oldB) then t.group = id end
    end
    a.group, b.group = id, id
end

------------------------------------------------------------------------
-- Applying geometry and keeping groups on screen
------------------------------------------------------------------------

local function ApplyGeometry(slot)
    local b, t = frames[slot], Tracked()[slot]
    if not b or not t then return end
    local size = t.size
    b:SetSize(size, size)
    -- border proportions of a standard action button (same as other addons in this client use)
    b.border:SetSize(size * 64 / 37, size * 64 / 37)
    b.border:ClearAllPoints()
    b.border:SetPoint("CENTER", 0, -size / 37)
    if b.queueFrame then
        local queueSize = max(12, floor(size * 0.45))
        b.queueFrame:SetSize(queueSize, queueSize)
    end
    local inset = size * 0.06
    b.bg:ClearAllPoints()
    b.bg:SetPoint("TOPLEFT", inset, -inset)
    b.bg:SetPoint("BOTTOMRIGHT", -inset, inset)
    if resizeSlot then UpdateHandle() end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", t.left, t.top)
end

local function ApplyMembers(members)
    for i = 1, #members do ApplyGeometry(members[i]) end
end

local function ClampMembers(members)
    local tr = Tracked()
    local minL, maxR, maxT, minB = huge, -huge, -huge, huge
    for i = 1, #members do
        local t = tr[members[i]]
        local l, r, top, bottom = Rect(t)
        minL, maxR, maxT, minB = min(minL, l), max(maxR, r), max(maxT, top), min(minB, bottom)
    end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local dx, dy = 0, 0
    if maxR > width then dx = width - maxR end
    if minL + dx < 0 then dx = -minL end
    if maxT > height then dy = height - maxT end
    if minB + dy < 0 then dy = -minB end
    if dx ~= 0 or dy ~= 0 then
        for i = 1, #members do
            local t = tr[members[i]]
            t.left, t.top = t.left + dx, t.top + dy
        end
    end
end

------------------------------------------------------------------------
-- Group layout. Links describe which window touches which, so a group can
-- be resized and rebuilt flush without drifting apart.
------------------------------------------------------------------------

-- gap: the space between attached windows (the spacing setting)
local function Gap()
    return SI.db.spacing or 0
end

local function CaptureLinks(members, gap)
    gap = gap or Gap()
    local tr = Tracked()
    local links = {}
    for i = 1, #members do
        for j = i + 1, #members do
            local a, b = tr[members[i]], tr[members[j]]
            local aL, aR, aT, aB = Rect(a)
            local bL, bR, bT, bB = Rect(b)
            local vOver = min(aT, bT) - max(aB, bB) > EPS
            local hOver = min(aR, bR) - max(aL, bL) > EPS
            local side, align
            if vOver and abs(bL - aR - gap) <= EPS then
                side = "R"
            elseif vOver and abs(aL - bR - gap) <= EPS then
                side = "L"
            elseif hOver and abs(bB - aT - gap) <= EPS then
                side = "U"
            elseif hOver and abs(aB - bT - gap) <= EPS then
                side = "D"
            end
            if side == "R" or side == "L" then
                if abs(aT - bT) <= EPS then
                    align = "T"
                elseif abs(aB - bB) <= EPS then
                    align = "B"
                else
                    align = "T"
                end
            elseif side then
                if abs(aL - bL) <= EPS then
                    align = "L"
                elseif abs(aR - bR) <= EPS then
                    align = "R"
                else
                    align = "L"
                end
            end
            if side then links[#links + 1] = { a = members[i], b = members[j], side = side, align = align } end
        end
    end
    return links
end

local function PlaceRelative(parent, child, side, align, gap)
    if side == "R" then
        child.left = parent.left + parent.size + gap
    elseif side == "L" then
        child.left = parent.left - child.size - gap
    elseif side == "U" then
        child.top = parent.top + child.size + gap
    else
        child.top = parent.top - parent.size - gap
    end
    if side == "R" or side == "L" then
        if align == "B" then
            child.top = parent.top - parent.size + child.size
        else
            child.top = parent.top
        end
    else
        if align == "R" then
            child.left = parent.left + parent.size - child.size
        else
            child.left = parent.left
        end
    end
end

-- Sets new sizes and rebuilds the group from the root window.
-- rootRight: when set, the root keeps its right edge instead of its left edge.
local function ApplyLayout(members, links, root, rootLeft, rootTop, rootRight, sizes, gap)
    gap = gap or Gap()
    local tr = Tracked()
    for s, size in pairs(sizes) do tr[s].size = size end
    local r = tr[root]
    r.top = rootTop
    if rootRight then r.left = rootRight - r.size else r.left = rootLeft end
    local placed = { [root] = true }
    local order = { root }
    local index = 1
    while index <= #order do
        local current = order[index]
        index = index + 1
        for i = 1, #links do
            local l = links[i]
            local other, side
            if l.a == current and not placed[l.b] then
                other, side = l.b, l.side
            elseif l.b == current and not placed[l.a] then
                other, side = l.a, INVERSE_SIDE[l.side]
            end
            if other then
                PlaceRelative(tr[current], tr[other], side, l.align, gap)
                placed[other] = true
                order[#order + 1] = other
            end
        end
    end
end

local function TopLeftMost(members)
    local tr = Tracked()
    local root = members[1]
    for i = 2, #members do
        local t, r = tr[members[i]], tr[root]
        if t.left < r.left - EPS or (abs(t.left - r.left) <= EPS and t.top > r.top) then root = members[i] end
    end
    return root
end

-- Resizes every tracker. sizeFn(slot, tracker) returns the new size.
-- oldGap/newGap: the spacing the groups are captured with and rebuilt with.
local function ResizeAll(sizeFn, oldGap, newGap)
    local tr = Tracked()
    local done = {}
    local slots = {}
    for s in pairs(tr) do slots[#slots + 1] = s end
    table.sort(slots)
    for _, slot in ipairs(slots) do
        if not done[slot] then
            local members = SI.GroupMembers(slot)
            for _, s in ipairs(members) do done[s] = true end
            local sizes = {}
            for _, s in ipairs(members) do sizes[s] = sizeFn(s, tr[s]) end
            local links = CaptureLinks(members, oldGap)
            local root = TopLeftMost(members)
            local r = tr[root]
            ApplyLayout(members, links, root, r.left, r.top, nil, sizes, newGap)
            ClampMembers(members)
            ApplyMembers(members)
        end
    end
end

function SI.GetMeanSize()
    local sum, n = 0, 0
    for _, t in pairs(Tracked()) do
        sum, n = sum + t.size, n + 1
    end
    if n == 0 then return nil end
    return sum / n
end

-- Scales all windows proportionally so their mean size becomes target.
function SI.SetMeanSize(target)
    local mean = SI.GetMeanSize()
    if not mean then return end
    local factor = target / mean
    local lo, hi = 0, huge
    for _, t in pairs(Tracked()) do
        lo = max(lo, SI.MIN_SIZE / t.size)
        hi = min(hi, SI.MAX_SIZE / t.size)
    end
    factor = max(lo, min(hi, factor))
    SI.RunSafe("mean-size", function()
        ResizeAll(function(_, t) return t.size * factor end)
    end)
end

-- Sets the space between attached windows (0 to MAX_SPACING pixels) and rebuilds every group.
function SI.SetSpacing(value)
    value = max(0, min(SI.MAX_SPACING, floor((tonumber(value) or 0) + 0.5)))
    SI.RunSafe("spacing", function()
        local old = SI.db.spacing or 0
        if value == old then return end
        ResizeAll(function(_, t) return t.size end, old, value)
        SI.db.spacing = value
    end)
end

-- Gives every window the default size (the size a window has when it is tracked the first time).
function SI.SetCommonSize()
    if next(Tracked()) == nil then return end
    SI.RunSafe("common-size", function()
        ResizeAll(function() return SI.DEFAULT_SIZE end)
    end)
end

------------------------------------------------------------------------
-- Drag and resize driver (one OnUpdate frame, active only while dragging)
------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:Hide()
local mode, state

local function StopDriver()
    mode, state = nil, nil
    driver:Hide()
    if HideSnapHint then HideSnapHint() end
end

local function UpdateMove()
    local tr = Tracked()
    local cx, cy = Cursor()
    local dx, dy = cx - state.cx, cy - state.cy
    if abs(dx) > 1 or abs(dy) > 1 then state.moved = true end
    state.distance = max(abs(dx), abs(dy))
    -- keep the whole group inside the screen
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if state.minL + dx < 0 then dx = -state.minL end
    if state.maxR + dx > width then dx = width - state.maxR end
    if state.minB + dy < 0 then dy = -state.minB end
    if state.maxT + dy > height then dy = height - state.maxT end
    for _, s in ipairs(state.members) do
        local t = tr[s]
        local start = state.snap[s]
        t.left, t.top = start[1] + dx, start[2] + dy
        ApplyGeometry(s)
    end
    if state.moved then
        -- the same rule as on release: the former neighbors are ignored until the window is moved away
        local avoid = state.distance < SI.SNAP_DISTANCE * 3 and state.avoid or nil
        ShowSnapHint(ComputeSnap(state.members, avoid))
    end
end

local function UpdateSize()
    local tr = Tracked()
    local cx, cy = Cursor()
    -- the handle sits at the bottom-right of the group, the top-left corner stays fixed;
    -- the scale follows the cursor movement relative to the group size
    local wanted = ((cx - state.cx) / state.width + (state.cy - cy) / state.height) / 2
    local factor = 1 + wanted
    factor = max(state.lo, min(state.hi, factor))
    local sizes = {}
    for _, s in ipairs(state.members) do
        local snap = state.snap[s]
        local t = tr[s]
        t.left, t.top = snap.left, snap.top
        sizes[s] = snap.size * factor
    end
    ApplyLayout(state.members, state.links, state.root, state.rootLeft, state.rootTop, nil, sizes)
    ApplyMembers(state.members)
end

driver:SetScript("OnUpdate", function()
    if not state then
        StopDriver()
        return
    end
    if InCombatLockdown() then
        -- protected frames cannot be changed in combat: abort and keep the last state
        SI.EndMove(true)
        SI.EndResize(true)
        StopDriver()
        return
    end
    if mode == "move" then UpdateMove() elseif mode == "size" then UpdateSize() end
end)

------------------------------------------------------------------------
-- Moving and magnet
------------------------------------------------------------------------

function SI.BeginMove(slot, detach)
    local db = SI.db
    if InCombatLockdown() or db.locked or not db.enabled or mode then return end
    local tr = db.tracked
    local t = tr[slot]
    if not t then return end
    local avoid
    if detach and t.group then
        -- the former neighbors are ignored by the magnet until the window is moved away from them
        avoid = {}
        for _, s in ipairs(SI.GroupMembers(slot)) do avoid[s] = true end
        t.group = nil
        NormalizeGroups()
    end
    local members = SI.GroupMembers(slot)
    local snap = {}
    local minL, maxR, maxT, minB = huge, -huge, -huge, huge
    for _, s in ipairs(members) do
        local m = tr[s]
        snap[s] = { m.left, m.top }
        local l, r, top, bottom = Rect(m)
        minL, maxR, maxT, minB = min(minL, l), max(maxR, r), max(maxT, top), min(minB, bottom)
    end
    local cx, cy = Cursor()
    state = {
        slot = slot, members = members, snap = snap, cx = cx, cy = cy, moved = false, avoid = avoid,
        distance = 0, minL = minL, maxR = maxR, maxT = maxT, minB = minB,
    }
    mode = "move"
    driver:Show()
end

-- Magnet. A moving group attaches to the side, top or bottom of any other window: the closest
-- facing edge within the catch radius wins (the windows are compared at the size they have while
-- dragged, whatever the sizes). When the group is dropped, its windows take the size of the window
-- they attach to and the moving window is put flush against it: the two edges are the spacing apart
-- and the windows line up (top with top, left with left).
local MIN_OVERLAP = 8

-- Where a window of the size of o sits when it is attached to the given side of o:
-- side R: right of o, L: left of o, U: above o, D: below o.
local function Placed(o, side, gap)
    if side == "R" then return { left = o.left + o.size + gap, top = o.top, size = o.size } end
    if side == "L" then return { left = o.left - o.size - gap, top = o.top, size = o.size } end
    if side == "U" then return { left = o.left, top = o.top + o.size + gap, size = o.size } end
    return { left = o.left, top = o.top - o.size - gap, size = o.size }
end

-- The catch radius grows with the window size, so large windows are not hard to attach.
local function SnapLimit(a, o)
    return max(SI.SNAP_DISTANCE, 0.3 * max(a.size, o.size))
end

-- Shift along the shared edge. a and o occupy [aMin, aMax] and [oMin, oMax] on that axis.
-- Returns the shift, or nil when the windows are too far apart along the edge.
local function EdgeShift(aMin, aMax, oMin, oMax, aSize, oSize, limit)
    local shift = 0
    local first = oMin - aMin
    local second = oMax - aMax
    local near = abs(first) <= abs(second) and first or second
    if abs(near) <= limit then shift = near end
    local need = min(MIN_OVERLAP, aSize, oSize)
    if min(aMax + shift, oMax) - max(aMin + shift, oMin) < need then
        if aMin + shift > oMax - need then
            shift = oMax - need - aMin
        elseif aMax + shift < oMin + need then
            shift = oMin + need - aMax
        end
    end
    if abs(shift) > limit + 0.5 * min(aSize, oSize) then return nil end
    return shift
end

-- Best way to put window a (its current place) against window o, or nil.
local function BestAttach(a, o, gap)
    local aL, aR, aT, aB = Rect(a)
    local oL, oR, oT, oB = Rect(o)
    local limit = SnapLimit(a, o)
    local best
    local function consider(side, main, shift)
        if not shift or abs(main) > limit then return end
        local score = abs(main) + 0.1 * abs(shift)
        if not best or score < best.score then
            local dx, dy
            if side == "R" or side == "L" then dx, dy = main, shift else dx, dy = shift, main end
            best = { dx = dx, dy = dy, side = side, a = a, o = o, score = score }
        end
    end
    -- a to the right or to the left of o: the edges are vertical, the shift is vertical
    local vShift = EdgeShift(aB, aT, oB, oT, a.size, o.size, limit)
    consider("R", oR + gap - aL, vShift)
    consider("L", oL - gap - aR, vShift)
    -- a above or below o: the edges are horizontal, the shift is horizontal
    local hShift = EdgeShift(aL, aR, oL, oR, a.size, o.size, limit)
    consider("U", oT + gap - aB, hShift)
    consider("D", oB - gap - aT, hShift)
    return best
end

-- Best attachment of the moving group to any other window: { side, other, ms, final } or nil.
-- ms is the moving window that attaches, other the slot of the window it attaches to, final the place
-- ms takes there ({ left, top, size }, the size of the window it attaches to).
-- avoid: windows the group is ignoring (its former neighbors).
ComputeSnap = function(members, avoid)
    local tr = Tracked()
    local moving = {}
    for _, s in ipairs(members) do moving[s] = true end
    if avoid then
        for s in pairs(avoid) do moving[s] = true end
    end
    local gap = Gap()
    local best
    for _, ms in ipairs(members) do
        for os, o in pairs(tr) do
            if not moving[os] then
                local found = BestAttach(tr[ms], o, gap)
                if found and (not best or found.score < best.score) then
                    found.other, found.ms = os, ms
                    found.final = Placed(o, found.side, gap)
                    best = found
                end
            end
        end
    end
    return best
end

local function SnapGroup(members, avoid)
    local best = ComputeSnap(members, avoid)
    if not best then return false end
    local tr = Tracked()
    local final = best.final
    if tr[best.ms].size ~= final.size then
        -- every moving window takes the size of the window it attaches to; the group is rebuilt
        -- flush around the window that touches the other one
        local gap = Gap()
        local links = CaptureLinks(members, gap)
        local sizes = {}
        for _, s in ipairs(members) do sizes[s] = final.size end
        ApplyLayout(members, links, best.ms, final.left, final.top, nil, sizes, gap)
    else
        local root = tr[best.ms]
        local dx, dy = final.left - root.left, final.top - root.top
        for _, s in ipairs(members) do
            local t = tr[s]
            t.left, t.top = t.left + dx, t.top + dy
        end
    end
    JoinGroups(members[1], best.other)
    return true
end
SI.SnapGroup = SnapGroup

-- Light hint while dragging: a gold glow on the seam where the windows will attach.
local hint = CreateFrame("Frame", "ShowItemsSnapHint", UIParent)
hint:SetFrameStrata("HIGH")
hint:EnableMouse(false)
hint:Hide()
hint.glow = hint:CreateTexture(nil, "OVERLAY")
hint.glow:SetColorTexture(1, 0.82, 0, 0.35)
hint.glow:SetBlendMode("ADD")
hint.core = hint:CreateTexture(nil, "OVERLAY")
hint.core:SetColorTexture(1, 0.9, 0.3, 0.95)

local function Box(texture, x1, y1, x2, y2)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x1, y1)
    texture:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x2, y2)
end

HideSnapHint = function()
    hint:Hide()
end

ShowSnapHint = function(snap)
    if not snap then
        hint:Hide()
        return
    end
    local gap = Gap()
    -- the seam between the target window and the moving one as it will sit after the drop
    local aL, aR, aT, aB = Rect(snap.final)
    local oL, oR, oT, oB = Rect(snap.o)
    local half = max(gap, 2) / 2
    local x1, y1, x2, y2
    if snap.side == "R" or snap.side == "L" then
        local x = snap.side == "R" and (oR + gap / 2) or (oL - gap / 2)
        x1, x2 = x - half, x + half
        y1, y2 = max(aB, oB), min(aT, oT)
    else
        local y = snap.side == "U" and (oT + gap / 2) or (oB - gap / 2)
        y1, y2 = y - half, y + half
        x1, x2 = max(aL, oL), min(aR, oR)
    end
    Box(hint.core, x1, y1, x2, y2)
    Box(hint.glow, x1 - 4, y1 - 4, x2 + 4, y2 + 4)
    hint:Show()
end

function SI.EndMove(aborted)
    if mode ~= "move" or not state then return end
    local tr = Tracked()
    local members = state.members
    local didMove = state.moved
    local avoid = state.distance < SI.SNAP_DISTANCE * 3 and state.avoid or nil
    mode, state = nil, nil
    driver:Hide()
    HideSnapHint()
    if aborted then return end
    if didMove then
        for _, s in ipairs(members) do tr[s].moved = true end
        SnapGroup(members, avoid)
        ClampMembers(SI.GroupMembers(members[1]))
        ApplyMembers(SI.GroupMembers(members[1]))
    end
end

------------------------------------------------------------------------
-- Resize mode (triangle handle at the bottom-right of one window)
------------------------------------------------------------------------

-- Resizes the whole group of `slot` from the group's top-left corner.
function SI.BeginResize(slot)
    local tr = Tracked()
    if not slot or not tr[slot] or InCombatLockdown() or mode then return end
    local members = SI.GroupMembers(slot)
    local snap = {}
    local lo, hi = 0, huge
    for _, s in ipairs(members) do
        local m = tr[s]
        snap[s] = { left = m.left, top = m.top, size = m.size }
        lo = max(lo, SI.MIN_SIZE / m.size)
        hi = min(hi, SI.MAX_SIZE / m.size)
    end
    local L, R, T, B = SI.GroupBounds(slot)
    local root = TopLeftMost(members)
    local cx, cy = Cursor()
    state = {
        members = members, snap = snap, links = CaptureLinks(members), root = root,
        rootLeft = tr[root].left, rootTop = tr[root].top,
        width = max(R - L, 1), height = max(T - B, 1), cx = cx, cy = cy, lo = lo, hi = hi,
    }
    mode = "size"
    driver:Show()
end

function SI.EndResize(aborted)
    if mode ~= "size" or not state then return end
    local members = state.members
    mode, state = nil, nil
    driver:Hide()
    if aborted then return end
    ClampMembers(members)
    ApplyMembers(members)
    SI.RefreshOptions()
end

-- Shows the resize triangle at the bottom-right of the group of `slot` (nil hides it).
function SI.SetResizeMode(slot)
    resizeSlot = slot
    UpdateHandle()
    if SI.RefreshFlyout then SI.RefreshFlyout() end
end

function SI.GetResizeSlot()
    return resizeSlot
end

-- True when resize mode is on for the group that contains `slot`.
function SI.IsResizeActiveFor(slot)
    if not resizeSlot then return false end
    for _, s in ipairs(SI.GroupMembers(slot)) do
        if s == resizeSlot then return true end
    end
    return false
end

-- One shared triangle, placed outside the bottom-right corner of the group
-- so it never covers an item icon.
local HANDLE_SIZE = 20
local handle = CreateFrame("Button", "ShowItemsResizeHandle", UIParent)
handle:SetSize(HANDLE_SIZE, HANDLE_SIZE)
handle:SetFrameStrata("HIGH")
local grip = handle:CreateTexture(nil, "OVERLAY")
grip:SetAllPoints()
grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
handle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
handle:SetScript("OnMouseDown", function() SI.BeginResize(resizeSlot) end)
handle:SetScript("OnMouseUp", function() SI.EndResize() end)
handle:Hide()

UpdateHandle = function()
    local db = SI.db
    if not resizeSlot or not db or not db.enabled or not db.tracked[resizeSlot] then
        handle:Hide()
        return
    end
    local _, right, _, bottom = SI.GroupBounds(resizeSlot)
    handle:ClearAllPoints()
    if right + 3 + HANDLE_SIZE <= UIParent:GetWidth() then
        handle:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", right + 3, bottom)
    else
        -- no room on the right: put it just below the group instead
        handle:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, bottom - 3)
    end
    handle:Show()
end

-- Stock Blizzard background of an inventory slot (the picture shown in the character window).
function SI.SlotTexture(slot)
    local def = SI.SLOTS[slot]
    if not def or not _G.GetInventorySlotInfo then return nil end
    local ok, _, texture = pcall(_G.GetInventorySlotInfo, def.inv)
    if ok then return texture end
    return nil
end

------------------------------------------------------------------------
-- Tracker button
------------------------------------------------------------------------

-- Sets the cooldown swirl. It is only touched when the cooldown really changed, and an error
-- from the cooldown API (it runs on a very frequent event) is swallowed instead of repeating.
local function ApplyCooldown(b)
    local start, duration, enable = GetInventoryItemCooldown("player", b.slot)
    if not (start and duration and duration > 0 and enable ~= 0) then
        start, duration = 0, 0
    end
    if b.cdStart == start and b.cdDuration == duration then return end
    b.cdStart, b.cdDuration = start, duration
    b.cd:SetCooldown(start, duration)
end

local function UpdateCooldown(b)
    if not pcall(ApplyCooldown, b) then
        b.cdStart, b.cdDuration = nil, nil
    end
end

-- The short tooltip of the worn item (its name and characteristics, see ItemTip.lua) under the window, or the
-- name of the slot as a small tip when the slot is empty.
local function ShowNameTip(self)
    local slot = self.slot
    local link = GetInventoryItemLink("player", slot)
    if link then
        SI.HideNameTip()
        SI.ShowItemTip(self, {
            side = "BELOW",
            fill = function(tip)
                local ok = pcall(tip.SetInventoryItem, tip, "player", slot)
                if not ok or tip:NumLines() == 0 then tip:SetHyperlink(link) end
            end,
        })
    else
        SI.HideItemTip(self)
        SI.ShowNameTip(self, SI.SLOTS[slot].name, 1, 1, 1, "BELOW")
    end
end

local function CreateTracker(slot)
    local b = CreateFrame("Button", "ShowItemsSlot" .. slot, UIParent, "SecureActionButtonTemplate")
    b.slot = slot
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(20)
    -- A secure button only reacts to the kind of click (down or up) that matches the ActionButtonUseKeyDown
    -- setting unless it is registered for both, so both are registered. The item is used when the
    -- mouse button is released, so a drag of the window does not use it.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext1", "/use " .. slot)

    -- Same look as an ItemRack button (an action button): black plate, icon, UI-Quickslot2 border.
    -- An empty slot shows the dark picture of the slot on the black plate.
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetColorTexture(0, 0, 0, 0.6)

    b.icon = b:CreateTexture(nil, "BORDER")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    b.border = b:CreateTexture(nil, "ARTWORK")
    b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()

    -- the item waiting to be equipped after combat, a small picture in the corner
    b.queueFrame = CreateFrame("Frame", nil, b)
    b.queueFrame:SetFrameLevel(b:GetFrameLevel() + 5)
    b.queueFrame:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.queueIcon = b.queueFrame:CreateTexture(nil, "OVERLAY")
    b.queueIcon:SetAllPoints()
    b.queueIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.queueFrame:Hide()

    b.emptyTexture = SI.SlotTexture(slot)

    b:SetScript("OnEnter", function(self)
        ShowNameTip(self)
        if SI.ShowHoverMenu then SI.ShowHoverMenu(self.slot) end
    end)
    b:SetScript("OnLeave", function(self)
        SI.HideNameTip()
        SI.HideItemTip(self)
    end)
    b:SetScript("OnDragStart", function(self)
        if SI.HideHoverMenu then SI.HideHoverMenu() end
        SI.BeginMove(self.slot, IsControlKeyDown())
    end)
    b:SetScript("OnDragStop", function() SI.EndMove() end)
    b:SetScript("PostClick", function(self, button, down)
        -- the button is registered for both press and release: the menu opens on release only
        if button == "RightButton" and not down and SI.db.enabled then SI.ShowFlyout(self.slot) end
    end)

    b:Hide()
    frames[slot] = b
    return b
end

function SI.RefreshSlot(slot)
    local b = frames[slot]
    if not b then return end
    local texture = GetInventoryItemTexture("player", slot)
    if texture then
        b.icon:SetTexture(texture)
        b.icon:SetAlpha(1)
        b.icon:Show()
    elseif b.emptyTexture then
        -- empty slot: show the stock slot picture so the window is easy to recognize
        b.icon:SetTexture(b.emptyTexture)
        b.icon:SetAlpha(1)
        b.icon:Show()
    else
        b.icon:SetTexture(nil)
        b.icon:Hide()
    end
    UpdateCooldown(b)
    SI.RefreshQueue(slot)
end

-- Shows the item that waits to be equipped after combat (see SI.QueuedItem) in the corner of the window.
function SI.RefreshQueue(slot)
    local b = frames[slot]
    if not b or not b.queueFrame then return end
    local queued = SI.QueuedItem and SI.QueuedItem(slot)
    if queued and queued.icon then
        b.queueIcon:SetTexture(queued.icon)
        b.queueFrame:Show()
    else
        b.queueFrame:Hide()
    end
end

------------------------------------------------------------------------
-- Key bindings (override bindings: never touch the player's saved bindings)
------------------------------------------------------------------------

local bindOwner = CreateFrame("Frame")

function SI.ApplyBindings()
    SI.RunSafe("bindings", function()
        ClearOverrideBindings(bindOwner)
        local db = SI.db
        if not db.enabled then return end
        for slot, key in pairs(db.bindings) do
            local b = frames[slot]
            if db.tracked[slot] and b then
                SetOverrideBindingClick(bindOwner, true, key, b:GetName(), "LeftButton")
            end
        end
    end)
end

function SI.SetBinding(slot, key)
    local bindings = SI.db.bindings
    if key then
        for s, k in pairs(bindings) do
            if k == key then bindings[s] = nil end
        end
        -- a key belongs to one thing only: take it away from a set that uses it
        if SI.ReleaseSetKey then SI.ReleaseSetKey(key) end
        bindings[slot] = key
    else
        bindings[slot] = nil
    end
    SI.ApplyBindings()
end

------------------------------------------------------------------------
-- Tracking
------------------------------------------------------------------------

local function AddTracker(slot)
    local db = SI.db
    local tr = db.tracked
    local anchor, anchorSlot
    for s, o in pairs(tr) do
        if not o.moved and (not anchor or o.left + o.size > anchor.left + anchor.size) then
            anchor, anchorSlot = o, s
        end
    end
    if anchor then
        tr[slot] = { left = anchor.left + anchor.size + Gap(), top = anchor.top, size = anchor.size, moved = false }
        JoinGroups(anchorSlot, slot)
    else
        local size = SI.DEFAULT_SIZE
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        tr[slot] = { left = (width - size) / 2, top = (height + size) / 2, size = size, moved = false }
    end
    local members = SI.GroupMembers(slot)
    ClampMembers(members)
    return members
end

function SI.ApplyAll()
    SI.RunSafe("apply-all", function()
        local db = SI.db
        local tr = db.tracked
        for slot in pairs(tr) do
            local b = frames[slot] or CreateTracker(slot)
            ApplyGeometry(slot)
            b:SetAlpha(db.alpha)
            SI.RefreshSlot(slot)
            if db.enabled then b:Show() else b:Hide() end
        end
        for slot, b in pairs(frames) do
            if not tr[slot] then b:Hide() end
        end
        UpdateHandle()
        SI.ApplyBindings()
        if SI.ApplySetBindings then SI.ApplySetBindings() end
    end)
end

-- One chat line per slot: the slot and its number, never the item.
local function ReportSlots(slots, text)
    for _, slot in ipairs(slots) do
        SI.Print("Slot " .. slot .. " (" .. SI.SLOTS[slot].name .. ") " .. text)
    end
end

function SI.Track(list)
    if not SI.db.enabled then return end
    local slots = {}
    for _, s in ipairs(list) do
        if SI.SLOTS[s] and not SI.db.tracked[s] then slots[#slots + 1] = s end
    end
    if #slots == 0 then return end
    table.sort(slots)
    if InCombatLockdown() then SI.Print("changes will be applied after combat") end
    SI.RunSafe("track-" .. table.concat(slots, ","), function()
        for _, slot in ipairs(slots) do
            if not SI.db.tracked[slot] then AddTracker(slot) end
        end
        SI.ApplyAll()
        SI.RefreshOptions()
        ReportSlots(slots, "tracked.")
    end)
end

function SI.Untrack(list)
    local slots = {}
    for _, s in ipairs(list) do
        if SI.db.tracked[s] then slots[#slots + 1] = s end
    end
    if #slots == 0 then return end
    table.sort(slots)
    if InCombatLockdown() then SI.Print("changes will be applied after combat") end
    SI.RunSafe("untrack-" .. table.concat(slots, ","), function()
        for _, slot in ipairs(slots) do
            SI.db.tracked[slot] = nil
            if SI.GetResizeSlot() == slot then SI.SetResizeMode(nil) end
        end
        NormalizeGroups()
        SI.ApplyAll()
        SI.RefreshOptions()
        ReportSlots(slots, "untracked.")
    end)
end

function SI.ResetAll()
    SI.RunSafe("reset", function()
        local db = SI.db
        if SI.TakeSnapshot then SI.TakeSnapshot("Before reset") end
        for k in pairs(db.tracked) do db.tracked[k] = nil end
        for k in pairs(db.bindings) do db.bindings[k] = nil end
        db.nextGroup = 1
        db.alpha = 1
        db.spacing = 0
        db.locked = false
        SI.SetResizeMode(nil)
        SI.ApplyAll()
        if SI.CloseMenus then SI.CloseMenus() end
        SI.RefreshOptions()
    end)
end

function SI.SetAlpha(value)
    SI.db.alpha = max(0.1, min(1, value))
    for _, b in pairs(frames) do b:SetAlpha(SI.db.alpha) end
end

function SI.SetLocked(value)
    SI.db.locked = value and true or false
    if SI.RefreshFlyout then SI.RefreshFlyout() end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local cooldownPending = false
local function ScheduleCooldownUpdate()
    if cooldownPending then return end
    local function run()
        cooldownPending = false
        for slot, b in pairs(frames) do
            if SI.db.tracked[slot] and b:IsShown() then UpdateCooldown(b) end
        end
    end
    if C_Timer and C_Timer.After then
        cooldownPending = true
        C_Timer.After(0.1, run)
    else
        run()
    end
end

SI.OnInit(function()
    SI.ApplyAll()
end)

SI.On("PLAYER_EQUIPMENT_CHANGED", function(slot)
    if SI.db and frames[slot] and SI.db.tracked[slot] then SI.RefreshSlot(slot) end
end)
SI.On("PLAYER_ENTERING_WORLD", function()
    if not SI.db then return end
    for slot in pairs(SI.db.tracked) do SI.RefreshSlot(slot) end
end)
SI.On("SPELL_UPDATE_COOLDOWN", function()
    if SI.db then ScheduleCooldownUpdate() end
end)
SI.On("BAG_UPDATE_COOLDOWN", function()
    if SI.db then ScheduleCooldownUpdate() end
end)
