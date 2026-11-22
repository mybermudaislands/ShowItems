local _, SI = ...

-- Inventory slot definitions.
-- id: inventory slot id, frame: Blizzard character window button,
-- loc: item equip locations (from GetItemInfoInstant) that fit the slot.
SI.SLOTS = {
    [1] = { name = "Head", frame = "CharacterHeadSlot", loc = { INVTYPE_HEAD = true } },
    [2] = { name = "Neck", frame = "CharacterNeckSlot", loc = { INVTYPE_NECK = true } },
    [3] = { name = "Shoulder", frame = "CharacterShoulderSlot", loc = { INVTYPE_SHOULDER = true } },
    [4] = { name = "Shirt", frame = "CharacterShirtSlot", loc = { INVTYPE_BODY = true } },
    [5] = { name = "Chest", frame = "CharacterChestSlot", loc = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    [6] = { name = "Waist", frame = "CharacterWaistSlot", loc = { INVTYPE_WAIST = true } },
    [7] = { name = "Legs", frame = "CharacterLegsSlot", loc = { INVTYPE_LEGS = true } },
    [8] = { name = "Feet", frame = "CharacterFeetSlot", loc = { INVTYPE_FEET = true } },
    [9] = { name = "Wrist", frame = "CharacterWristSlot", loc = { INVTYPE_WRIST = true } },
    [10] = { name = "Hands", frame = "CharacterHandsSlot", loc = { INVTYPE_HAND = true } },
    [11] = { name = "Finger 1", frame = "CharacterFinger0Slot", loc = { INVTYPE_FINGER = true } },
    [12] = { name = "Finger 2", frame = "CharacterFinger1Slot", loc = { INVTYPE_FINGER = true } },
    [13] = { name = "Trinket 1", frame = "CharacterTrinket0Slot", loc = { INVTYPE_TRINKET = true } },
    [14] = { name = "Trinket 2", frame = "CharacterTrinket1Slot", loc = { INVTYPE_TRINKET = true } },
    [15] = { name = "Back", frame = "CharacterBackSlot", loc = { INVTYPE_CLOAK = true } },
    [16] = {
        name = "Main Hand",
        frame = "CharacterMainHandSlot",
        loc = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true },
    },
    [17] = {
        name = "Off Hand",
        frame = "CharacterSecondaryHandSlot",
        loc = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
    },
    [18] = {
        name = "Ranged",
        frame = "CharacterRangedSlot",
        loc = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
    },
    [19] = { name = "Tabard", frame = "CharacterTabardSlot", loc = { INVTYPE_TABARD = true } },
}

-- Names for GetInventorySlotInfo, which returns the stock Blizzard picture of each slot.
local INV_NAMES = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot",
    [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot", [10] = "HandsSlot",
    [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot",
    [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot", [18] = "RangedSlot",
    [19] = "TabardSlot",
}
for id, name in pairs(INV_NAMES) do SI.SLOTS[id].inv = name end

-- Display order for lists (matches the character window layout).
SI.SLOT_ORDER = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
