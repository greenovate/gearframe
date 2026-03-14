------------------------------------------------------------------------
-- GearFrame — Equip
-- Equipment swap engine with combat-queue support
------------------------------------------------------------------------
local _, ns = ...

local pendingSet = nil   -- set index queued for after combat

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
-- Core swap logic
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

    local swapped = 0
    local failed  = 0

    -- First pass: handle slots that need to be emptied
    for slotID, desiredID in pairs(set.items) do
        if desiredID == 0 then
            local currentID = GetInventoryItemID("player", slotID)
            if currentID then
                if self:UnequipSlot(slotID) then
                    swapped = swapped + 1
                else
                    failed = failed + 1
                end
            end
        end
    end

    -- Second pass: equip desired items
    for slotID, desiredID in pairs(set.items) do
        if desiredID and desiredID > 0 then
            local currentID = GetInventoryItemID("player", slotID) or 0
            if currentID ~= desiredID then
                if self:EquipItemToSlot(desiredID, slotID) then
                    swapped = swapped + 1
                else
                    failed = failed + 1
                end
            end
        end
    end

    if failed > 0 then
        ns.Print(string.format("Equipped \"%s\" (%d swapped, %d failed — items may be missing).",
            set.name, swapped, failed))
    else
        ns.Print("Equipped: " .. set.name)
    end

    -- Refresh UI state
    if ns.RefreshSetList then ns:RefreshSetList() end
end

------------------------------------------------------------------------
-- Equip a single item to a specific slot
------------------------------------------------------------------------
function ns:EquipItemToSlot(itemID, targetSlot)
    -- Already there?
    if GetInventoryItemID("player", targetSlot) == itemID then return true end

    -- Look in bags
    local bag, slot = ns.FindItemInBags(itemID)
    if bag and slot then
        ClearCursor()
        ns.PickupContainerItem(bag, slot)
        PickupInventoryItem(targetSlot)
        return true
    end

    -- Item might be in another equipped slot (e.g., ring in wrong finger)
    for sid = 1, ns.NUM_EQUIP_SLOTS do
        if sid ~= targetSlot and GetInventoryItemID("player", sid) == itemID then
            -- Swap via bags: unequip from wrong slot, then equip to right slot
            if self:UnequipSlot(sid) then
                -- Item is now in bags; find and equip
                local b, s = ns.FindItemInBags(itemID)
                if b and s then
                    ClearCursor()
                    ns.PickupContainerItem(b, s)
                    PickupInventoryItem(targetSlot)
                    return true
                end
            end
            break
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
