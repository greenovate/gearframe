------------------------------------------------------------------------
-- GearFrame — Core
-- Addon namespace, constants, slot mappings, utilities, initialization
------------------------------------------------------------------------
local addonName, ns = ...

ns.version = "1.0.0"
ns.MAX_SETS = 10

------------------------------------------------------------------------
-- API Compatibility Shims (Anniversary client uses modern APIs)
------------------------------------------------------------------------
local GetContainerNumSlots   = C_Container and C_Container.GetContainerNumSlots   or GetContainerNumSlots
local GetContainerItemLink    = C_Container and C_Container.GetContainerItemLink    or GetContainerItemLink
local PickupContainerItem     = C_Container and C_Container.PickupContainerItem     or PickupContainerItem

-- C_Container.GetContainerItemInfo returns a table in modern clients
local function GetContainerItemTexture(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.iconFileID or nil
    else
        return _G.GetContainerItemInfo(bag, slot)  -- old API returns texture as first value
    end
end

local function ContainerSlotHasItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info ~= nil
    else
        return _G.GetContainerItemInfo(bag, slot) ~= nil
    end
end

-- GetMouseFocus was removed; use GetMouseFoci in modern clients
local SafeGetMouseFocus = GetMouseFocus or function()
    if GetMouseFoci then
        local frames = GetMouseFoci()
        return frames and frames[1] or nil
    end
    return nil
end

-- Export for other files
ns.GetContainerNumSlots  = GetContainerNumSlots
ns.GetContainerItemLink   = GetContainerItemLink
ns.PickupContainerItem    = PickupContainerItem
ns.GetContainerItemTexture = GetContainerItemTexture
ns.ContainerSlotHasItem   = ContainerSlotHasItem
ns.SafeGetMouseFocus      = SafeGetMouseFocus

------------------------------------------------------------------------
-- Equipment Slot Definitions
------------------------------------------------------------------------
ns.NUM_EQUIP_SLOTS = 19

ns.SLOT_INFO = {
    { id = 1,  name = "HeadSlot",          display = "Head",       default = true  },
    { id = 2,  name = "NeckSlot",          display = "Neck",       default = true  },
    { id = 3,  name = "ShoulderSlot",      display = "Shoulders",  default = true  },
    { id = 4,  name = "ShirtSlot",         display = "Shirt",      default = false },
    { id = 5,  name = "ChestSlot",         display = "Chest",      default = true  },
    { id = 6,  name = "WaistSlot",         display = "Waist",      default = true  },
    { id = 7,  name = "LegsSlot",          display = "Legs",       default = true  },
    { id = 8,  name = "FeetSlot",          display = "Feet",       default = true  },
    { id = 9,  name = "WristSlot",         display = "Wrists",     default = true  },
    { id = 10, name = "HandsSlot",         display = "Hands",      default = true  },
    { id = 11, name = "Finger0Slot",       display = "Ring 1",     default = true  },
    { id = 12, name = "Finger1Slot",       display = "Ring 2",     default = true  },
    { id = 13, name = "Trinket0Slot",      display = "Trinket 1",  default = true  },
    { id = 14, name = "Trinket1Slot",      display = "Trinket 2",  default = true  },
    { id = 15, name = "BackSlot",          display = "Back",       default = true  },
    { id = 16, name = "MainHandSlot",      display = "Main Hand",  default = true  },
    { id = 17, name = "SecondaryHandSlot", display = "Off Hand",   default = true  },
    { id = 18, name = "RangedSlot",        display = "Ranged",     default = true  },
    { id = 19, name = "TabardSlot",        display = "Tabard",     default = false },
}

-- Quick lookup tables
ns.SLOT_BY_ID   = {}
ns.SLOT_BY_NAME = {}
for _, info in ipairs(ns.SLOT_INFO) do
    ns.SLOT_BY_ID[info.id]     = info
    ns.SLOT_BY_NAME[info.name] = info
end

-- Which INVTYPE values each equipment slot accepts
ns.SLOT_ACCEPTS = {
    [1]  = { INVTYPE_HEAD = true },
    [2]  = { INVTYPE_NECK = true },
    [3]  = { INVTYPE_SHOULDER = true },
    [4]  = { INVTYPE_BODY = true },
    [5]  = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
    [6]  = { INVTYPE_WAIST = true },
    [7]  = { INVTYPE_LEGS = true },
    [8]  = { INVTYPE_FEET = true },
    [9]  = { INVTYPE_WRIST = true },
    [10] = { INVTYPE_HAND = true },
    [11] = { INVTYPE_FINGER = true },
    [12] = { INVTYPE_FINGER = true },
    [13] = { INVTYPE_TRINKET = true },
    [14] = { INVTYPE_TRINKET = true },
    [15] = { INVTYPE_CLOAK = true },
    [16] = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true },
    [17] = { INVTYPE_SHIELD = true, INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true },
    [18] = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
    [19] = { INVTYPE_TABARD = true },
}

-- Paperdoll button names (used by Flyout / UI hooks)
ns.PAPERDOLL_SLOTS = {
    "CharacterHeadSlot",       "CharacterNeckSlot",
    "CharacterShoulderSlot",   "CharacterShirtSlot",
    "CharacterChestSlot",      "CharacterWaistSlot",
    "CharacterLegsSlot",       "CharacterFeetSlot",
    "CharacterWristSlot",      "CharacterHandsSlot",
    "CharacterFinger0Slot",    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",   "CharacterTrinket1Slot",
    "CharacterBackSlot",       "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot", "CharacterRangedSlot",
    "CharacterTabardSlot",
}

------------------------------------------------------------------------
-- Utility Functions
------------------------------------------------------------------------

function ns.GetItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Extract a stable matching string from an item link: "id:enchant:gem1:gem2:gem3:gem4"
function ns.GetItemFingerprint(link)
    if not link then return nil end
    return link:match("item:(%d+:%d*:%d*:%d*:%d*:%d*)")
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffGearFrame:|r " .. tostring(msg))
end

-- Does this item link fit into the given equipment slot?
function ns.CanItemGoInSlot(link, slotID)
    if not link or not slotID then return false end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not equipLoc or equipLoc == "" then return false end
    local accepts = ns.SLOT_ACCEPTS[slotID]
    return accepts and accepts[equipLoc] or false
end

-- All items from bags 0-4 that can go into a specific slot
function ns.GetBagItemsForSlot(slotID)
    local items = {}
    for bag = 0, 4 do
        local numSlots = ns.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = ns.GetContainerItemLink(bag, slot)
            if link and ns.CanItemGoInSlot(link, slotID) then
                local texture = ns.GetContainerItemTexture(bag, slot)
                table.insert(items, {
                    bag     = bag,
                    slot    = slot,
                    link    = link,
                    itemID  = ns.GetItemIDFromLink(link),
                    texture = texture,
                })
            end
        end
    end
    return items
end

-- Find item by ID in bags. Returns bag, slot or nil, nil.
function ns.FindItemInBags(itemID)
    for bag = 0, 4 do
        local numSlots = ns.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = ns.GetContainerItemLink(bag, slot)
            if link and ns.GetItemIDFromLink(link) == itemID then
                return bag, slot
            end
        end
    end
    return nil, nil
end

-- Find first empty bag slot
function ns.FindEmptyBagSlot()
    for bag = 0, 4 do
        local numSlots = ns.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            if not ns.ContainerSlotHasItem(bag, slot) then
                return bag, slot
            end
        end
    end
    return nil, nil
end

-- Get the current snapshot of equipped items: { [slotID] = itemID }
function ns.GetEquippedItems()
    local equipped = {}
    for _, info in ipairs(ns.SLOT_INFO) do
        local id = GetInventoryItemID("player", info.id)
        equipped[info.id] = id or 0
    end
    return equipped
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialise saved variables
        if not GearFrameDB then GearFrameDB = { version = 1, theme = "auto" } end
        if not GearFrameCharDB then GearFrameCharDB = { sets = {} } end
        ns.db     = GearFrameDB
        ns.charDB = GearFrameCharDB
        if not ns.charDB.sets then ns.charDB.sets = {} end
        if not ns.db.theme then ns.db.theme = "auto" end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not ns.initialized then
            ns.initialized = true

            -- Sub-system init (defined in their own files)
            ns:InitUI()
            ns:InitFlyout()
            ns:InitTooltips()
            ns:InitSettings()

            -- Slash commands
            SLASH_GEARFRAME1 = "/gearframe"
            SLASH_GEARFRAME2 = "/gf"
            SlashCmdList["GEARFRAME"] = function(msg) ns:SlashHandler(msg) end

            ns.Print("v" .. ns.version .. " loaded.  /gf or open your Character panel.")
        end
    end
end)

------------------------------------------------------------------------
-- Slash Command Handler
------------------------------------------------------------------------
function ns:SlashHandler(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" then
        ToggleCharacter("PaperDollFrame")
        C_Timer.After(0, function()
            if ns.setPanel then ns.setPanel:Show() end
        end)

    elseif msg == "settings" or msg == "config" or msg == "options" then
        ns:ToggleSettings()

    elseif msg == "help" then
        ns.Print("/gf — toggle equipment manager")
        ns.Print("/gf settings — open settings (theme, etc.)")
        ns.Print("/gf list — list saved sets")
        ns.Print("/gf equip <name> — equip a set")
        ns.Print("/gf save <name> — quick-save current gear")
        ns.Print("/gf delete <name> — delete a set")

    elseif msg == "list" then
        if #ns.charDB.sets == 0 then
            ns.Print("No equipment sets saved.")
        else
            for i, set in ipairs(ns.charDB.sets) do
                ns.Print(string.format("  %d. %s", i, set.name))
            end
        end

    elseif msg:find("^equip ") then
        ns:EquipSetByName(msg:sub(7):trim())

    elseif msg:find("^save ") then
        ns:QuickSaveSet(msg:sub(6):trim())

    elseif msg:find("^delete ") then
        ns:DeleteSetByName(msg:sub(8):trim())
    end
end
