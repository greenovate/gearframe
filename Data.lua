------------------------------------------------------------------------
-- GearFrame — Data
-- CRUD operations for equipment sets (SavedVariablesPerCharacter)
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Save a new set or overwrite an existing one
-- slots: table of slotIDs to include (nil = use defaults)
-- icon:  texture path or fileID  (nil = auto-pick from first item)
------------------------------------------------------------------------
function ns:SaveSet(name, slots, icon)
    if not name or name == "" then
        ns.Print("Set name cannot be empty.")
        return false
    end

    -- Enforce max
    local existing = self:GetSetByName(name)
    if not existing and #self.charDB.sets >= ns.MAX_SETS then
        ns.Print("Cannot save more than " .. ns.MAX_SETS .. " sets.")
        return false
    end

    -- Build slot inclusion map
    local includeSlots = {}
    if slots then
        for _, sid in ipairs(slots) do includeSlots[sid] = true end
    else
        for _, info in ipairs(ns.SLOT_INFO) do
            if info.default then includeSlots[info.id] = true end
        end
    end

    -- Snapshot equipped items
    local items = {}
    local firstIcon = nil
    for slotID = 1, ns.NUM_EQUIP_SLOTS do
        if includeSlots[slotID] then
            local itemID = GetInventoryItemID("player", slotID) or 0
            items[slotID] = itemID
            if not firstIcon and itemID > 0 then
                firstIcon = GetInventoryItemTexture("player", slotID)
            end
        end
    end

    -- Resolve icon
    icon = icon or firstIcon or 134400  -- INV_Misc_QuestionMark FileDataID

    local setData = {
        name  = name,
        icon  = icon,
        items = items,  -- { [slotID] = itemID }
    }

    -- Update existing or insert new
    if existing then
        for i, s in ipairs(self.charDB.sets) do
            if s.name == name then
                self.charDB.sets[i] = setData
                break
            end
        end
        ns.Print("Updated set: " .. name)
    else
        table.insert(self.charDB.sets, setData)
        ns.Print("Saved set: " .. name)
    end

    -- Refresh UI
    if ns.RefreshSetList then ns:RefreshSetList() end
    return true
end

------------------------------------------------------------------------
-- Quick save from slash command (default slots, auto icon)
------------------------------------------------------------------------
function ns:QuickSaveSet(name)
    return self:SaveSet(name, nil, nil)
end

------------------------------------------------------------------------
-- Delete
------------------------------------------------------------------------
function ns:DeleteSet(index)
    local set = self.charDB.sets[index]
    if not set then return end
    local name = set.name
    table.remove(self.charDB.sets, index)
    ns.Print("Deleted set: " .. name)
    if ns.ClearSetSelection then ns:ClearSetSelection() end
    if ns.RefreshSetList then ns:RefreshSetList() end
end

function ns:DeleteSetByName(name)
    for i, set in ipairs(self.charDB.sets) do
        if set.name:lower() == name:lower() then
            self:DeleteSet(i)
            return
        end
    end
    ns.Print("Set not found: " .. name)
end

------------------------------------------------------------------------
-- Lookup helpers
------------------------------------------------------------------------
function ns:GetSetByName(name)
    for _, set in ipairs(self.charDB.sets) do
        if set.name:lower() == name:lower() then return set end
    end
    return nil
end

function ns:GetSetIndex(name)
    for i, set in ipairs(self.charDB.sets) do
        if set.name:lower() == name:lower() then return i end
    end
    return nil
end

------------------------------------------------------------------------
-- Find all sets that contain a given itemID (for tooltip display)
------------------------------------------------------------------------
function ns:GetSetsContainingItem(itemID)
    local results = {}
    if not itemID then return results end
    for _, set in ipairs(self.charDB.sets) do
        for _, savedID in pairs(set.items) do
            if savedID == itemID then
                table.insert(results, set.name)
                break
            end
        end
    end
    return results
end

------------------------------------------------------------------------
-- Check if a set is currently fully equipped
------------------------------------------------------------------------
function ns:IsSetEquipped(setData)
    if not setData then return false end
    for slotID, itemID in pairs(setData.items) do
        local currentID = GetInventoryItemID("player", slotID) or 0
        if currentID ~= itemID then return false end
    end
    return true
end

------------------------------------------------------------------------
-- Audit a set: returns status, missing items, changed items
-- status: "equipped", "ready", "modified", "missing"
--   equipped = all items currently worn
--   ready    = all items in bags or equipped, can equip now
--   modified = currently wearing set items but some slots changed
--   missing  = one or more items not found in bags or equipped
------------------------------------------------------------------------
function ns:AuditSet(setData)
    if not setData then return "missing", {}, {}, 0, 0 end

    local missing  = {}   -- { { slotID, itemID, itemName } }
    local changed  = {}   -- { { slotID, itemID, currentID, itemName, currentName } }
    local equipped = 0
    local total    = 0

    for slotID, itemID in pairs(setData.items) do
        if itemID and itemID > 0 then
            total = total + 1
            local currentID = GetInventoryItemID("player", slotID) or 0
            local itemName  = GetItemInfo(itemID) or ("item#" .. itemID)

            if currentID == itemID then
                equipped = equipped + 1
            else
                -- Not in the right slot — is it in bags or another slot?
                local inBag = ns.FindItemInBags(itemID)
                local inOtherSlot = false
                if not inBag then
                    for sid = 1, ns.NUM_EQUIP_SLOTS do
                        if GetInventoryItemID("player", sid) == itemID then
                            inOtherSlot = true
                            break
                        end
                    end
                end

                if inBag or inOtherSlot then
                    -- Item exists but slot has something different
                    local currentName = currentID > 0 and (GetItemInfo(currentID) or ("item#" .. currentID)) or "Empty"
                    table.insert(changed, {
                        slotID      = slotID,
                        itemID      = itemID,
                        currentID   = currentID,
                        itemName    = itemName,
                        currentName = currentName,
                    })
                else
                    -- Item not found anywhere
                    table.insert(missing, {
                        slotID   = slotID,
                        itemID   = itemID,
                        itemName = itemName,
                    })
                end
            end
        end
    end

    local status
    if equipped == total then
        status = "equipped"
    elseif #missing > 0 then
        status = "missing"
    elseif #changed > 0 then
        status = "modified"
    else
        status = "ready"
    end

    return status, missing, changed, equipped, total
end

------------------------------------------------------------------------
-- Move a set up or down in the list (for future drag reorder)
------------------------------------------------------------------------
function ns:MoveSet(fromIndex, toIndex)
    local sets = self.charDB.sets
    if fromIndex < 1 or fromIndex > #sets then return end
    if toIndex < 1 or toIndex > #sets then return end
    local set = table.remove(sets, fromIndex)
    table.insert(sets, toIndex, set)
    if ns.RefreshSetList then ns:RefreshSetList() end
end
