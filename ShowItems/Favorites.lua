local _, SI = ...

-- Favorite items of the menu on the character window. The player marks an item with the star on its icon.
-- db.favorites[itemID] = { seq = order of marking (the first marked is first in the menu), missing = time }
-- An item is identified by its item ID, so every copy of it is a favorite.
--
-- A favorite that is neither in the bags nor worn is only kept for a day (FAVORITE_KEEP): this stops the list
-- from filling up with sold or deleted items. Nothing runs on a timer. The bags and the worn items are checked
-- when the menu opens: an item that is not found gets the time it was first missed, one that is found again
-- loses it, and one that has been missing for a whole day is removed from the favorites.
-- A favorite that is not in the bags is not shown in the menu (the menu lists bag items), and it comes back
-- as the favorite it was when it returns to the bags.

SI.FAVORITE_KEEP = 24 * 60 * 60 -- seconds

local function Now()
    return _G.time and _G.time() or 0
end

function SI.IsFavorite(itemId)
    local db = SI.db
    return db ~= nil and itemId ~= nil and db.favorites[itemId] ~= nil
end

function SI.SetFavorite(itemId, value)
    local db = SI.db
    if not db or type(itemId) ~= "number" then return end
    if value then
        if db.favorites[itemId] then return end
        db.favorites[itemId] = { seq = db.nextFavorite }
        db.nextFavorite = db.nextFavorite + 1
    else
        db.favorites[itemId] = nil
    end
end

-- Returns the new state.
function SI.ToggleFavorite(itemId)
    local state = not SI.IsFavorite(itemId)
    SI.SetFavorite(itemId, state)
    return SI.IsFavorite(itemId)
end

-- Puts the favorites first, in the order they were marked; the other items keep their order.
function SI.SortByFavorites(items)
    local favorites = SI.db and SI.db.favorites
    if not favorites or not next(favorites) then return items end
    local first, rest = {}, {}
    for position, item in ipairs(items) do
        local favorite = item.id and favorites[item.id]
        if favorite then
            first[#first + 1] = { item = item, seq = favorite.seq, position = position }
        else
            rest[#rest + 1] = item
        end
    end
    table.sort(first, function(a, b)
        if a.seq ~= b.seq then return a.seq < b.seq end
        return a.position < b.position
    end)
    local sorted = {}
    for _, entry in ipairs(first) do sorted[#sorted + 1] = entry.item end
    for _, item in ipairs(rest) do sorted[#sorted + 1] = item end
    return sorted
end

-- Called when the menu opens. See the top of the file.
function SI.RefreshFavorites()
    local db = SI.db
    if not db or not next(db.favorites) then return end
    -- the bags cannot be read (not loaded yet): do not take that for "everything was sold"
    if SI.NumSlots(0) == 0 then return end
    local present = {}
    for bag = 0, _G.NUM_BAG_SLOTS or 4 do
        for index = 1, SI.NumSlots(bag) do
            local _, id = SI.BagItem(bag, index)
            if id then present[id] = true end
        end
    end
    if _G.GetInventoryItemID then
        for slot = 1, 19 do
            local id = _G.GetInventoryItemID("player", slot)
            if id then present[id] = true end
        end
    end
    local now = Now()
    for id, favorite in pairs(db.favorites) do
        if present[id] then
            favorite.missing = nil
        elseif not favorite.missing or favorite.missing > now then
            favorite.missing = now -- first time missed (or the clock went back)
        elseif now - favorite.missing >= SI.FAVORITE_KEEP then
            db.favorites[id] = nil
        end
    end
end
