------------------------------------------------------------------------
-- GearFrame — Equip
-- Event-driven equipment swap engine with combat-queue support
------------------------------------------------------------------------
local _, ns = ...

local pendingSet = nil   -- set queued for after combat
local swapQueue  = {}    -- ordered list of { slotID, itemID } pending swap
local swapSetName = nil  -- name of set being swapped (for status message)
local swapFailed  = 0
local swapDone    = 0
local failedItems = {}    -- { "SlotName: ItemName", ... }
local swapSetItems = {}  -- full set items table for the current swap (to avoid cannibalizing)
local claimedBagSlots = {} -- { ["bag:slot"] = true } bag positions already picked up this swap

------------------------------------------------------------------------
-- Main equip entry point
------------------------------------------------------------------------
function ns:EquipSet(index)
    local set = self.charDB.sets[index]
    if not set then
        ns.Print("Invalid set index.")
        return
    end
    self:EquipSetData(set)
end

function ns:EquipSetByName(name)
    local set = self:GetSetByName(name)
    if not set then
        ns.Print("Set not found: " .. name)
        return
    end
    self:EquipSetData(set)
end

------------------------------------------------------------------------
-- Core swap logic — builds a queue and processes one swap at a time,
-- waiting for PLAYER_EQUIPMENT_CHANGED between each operation.
------------------------------------------------------------------------
function ns:EquipSetData(set)
    -- Combat check — queue for later
    if InCombatLockdown() or UnitAffectingCombat("player") then
        pendingSet = set
        ns.Print("In combat — will equip \"" .. set.name .. "\" when combat ends.")
        return
    end

    -- Already equipped?
    if self:IsSetEquipped(set) then
        ns.Print("\"" .. set.name .. "\" is already equipped.")
        return
    end

    -- Build swap queue: unequips first (desiredID == 0), then equips
    swapQueue  = {}
    swapFailed = 0
    swapDone   = 0
    swapSetName = set.name
    failedItems = {}
    swapSetItems = set.items
    claimedBagSlots = {}

    -- Pass 1: slots that need to be emptied
    for slotID, desiredID in pairs(set.items) do
        if desiredID == 0 then
            local currentID = GetInventoryItemID("player", slotID)
            if currentID then
                table.insert(swapQueue, { slotID = slotID, itemID = 0 })
            end
        end
    end

    -- Pass 2: slots that need items equipped
    for slotID, desiredID in pairs(set.items) do
        if desiredID and desiredID > 0 then
            local currentID = GetInventoryItemID("player", slotID) or 0
            if currentID ~= desiredID then
                table.insert(swapQueue, { slotID = slotID, itemID = desiredID })
            end
        end
    end

    if #swapQueue == 0 then
        ns.Print("\"" .. set.name .. "\" is already equipped.")
        return
    end

    -- Start processing
    self:ProcessNextSwap()
end

------------------------------------------------------------------------
-- Process one swap from the queue
------------------------------------------------------------------------
function ns:ProcessNextSwap()
    if #swapQueue == 0 then
        -- All done
        if swapFailed > 0 then
            ns.Print(string.format("Equipped \"%s\" (%d swapped, %d failed).",
                swapSetName, swapDone, swapFailed))
            for _, desc in ipairs(failedItems) do
                ns.Print("  |cffff4444Missing:|r " .. desc)
            end
        else
            ns.Print("Equipped: " .. swapSetName)
        end
        swapSetName = nil
        failedItems = {}
        if ns.RefreshSetList then ns:RefreshSetList() end
        return
    end

    local op = table.remove(swapQueue, 1)

    if op.itemID == 0 then
        -- Unequip
        if self:UnequipSlot(op.slotID) then
            swapDone = swapDone + 1
        else
            swapFailed = swapFailed + 1
            local slotInfo = ns.SLOT_BY_ID[op.slotID]
            table.insert(failedItems, (slotInfo and slotInfo.display or "Slot " .. op.slotID) .. ": could not unequip")
        end
        C_Timer.After(0.1, function() ns:ProcessNextSwap() end)
    else
        -- Equip
        if self:EquipItemToSlot(op.itemID, op.slotID) then
            swapDone = swapDone + 1
        else
            swapFailed = swapFailed + 1
            local itemName = GetItemInfo(op.itemID) or ("item#" .. op.itemID)
            local slotInfo = ns.SLOT_BY_ID[op.slotID]
            table.insert(failedItems, (slotInfo and slotInfo.display or "Slot " .. op.slotID) .. ": " .. itemName)
        end
        C_Timer.After(0.1, function() ns:ProcessNextSwap() end)
    end
end

------------------------------------------------------------------------
-- Equip a single item to a specific slot
------------------------------------------------------------------------
function ns:EquipItemToSlot(itemID, targetSlot)
    -- Already there?
    if GetInventoryItemID("player", targetSlot) == itemID then return true end

    -- Clear any existing cursor item safely
    if CursorHasItem() then ClearCursor() end

    -- Look in bags (skip slots already claimed by earlier swaps in this set)
    local bag, slot = ns.FindItemInBags(itemID, claimedBagSlots)
    if bag and slot then
        claimedBagSlots[bag .. ":" .. slot] = true
        ClearCursor()
        ns.PickupContainerItem(bag, slot)
        PickupInventoryItem(targetSlot)
        return true
    end

    -- Item might be in another equipped slot (e.g., ring in wrong finger)
    -- But don't steal from a slot that already has the correct item for this set
    for sid = 1, ns.NUM_EQUIP_SLOTS do
        if sid ~= targetSlot and GetInventoryItemID("player", sid) == itemID then
            -- If this set also wants this item in that slot, don't take it
            if swapSetItems[sid] == itemID then
                -- That slot is already satisfied — skip, look for another source
            else
                if self:UnequipSlot(sid) then
                    local b, s = ns.FindItemInBags(itemID, claimedBagSlots)
                    if b and s then
                        claimedBagSlots[b .. ":" .. s] = true
                        ClearCursor()
                        ns.PickupContainerItem(b, s)
                        PickupInventoryItem(targetSlot)
                        return true
                    end
                end
                break
            end
        end
    end

    return false
end

------------------------------------------------------------------------
-- Unequip a slot (move item to bags)
------------------------------------------------------------------------
function ns:UnequipSlot(slotID)
    if not GetInventoryItemID("player", slotID) then return true end

    local bag, slot = ns.FindEmptyBagSlot()
    if not bag then
        ns.Print("No empty bag space to unequip slot.")
        return false
    end

    ClearCursor()
    PickupInventoryItem(slotID)
    ns.PickupContainerItem(bag, slot)
    return true
end

------------------------------------------------------------------------
-- Combat queue — equip pending set when combat ends
------------------------------------------------------------------------
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if pendingSet then
        local set = pendingSet
        pendingSet = nil
        ns.Print("Combat ended — equipping \"" .. set.name .. "\".")
        ns:EquipSetData(set)
    end
end)
