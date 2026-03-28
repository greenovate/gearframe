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
    -- Sync to macros for cross-PC persistence
    if ns.SyncToMacros then ns:SyncToMacros() end
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
    -- Sync to macros for cross-PC persistence
    if ns.SyncToMacros then ns:SyncToMacros() end
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

------------------------------------------------------------------------
-- Macro Sync — persist sets to per-character macros for cross-PC sync
-- Macros are server-side so they follow the character everywhere.
-- Format: GF|setName|iconFileID|slotID:itemID,slotID:itemID,...
-- One macro per set. Macro names: GF_01 through GF_18 (TBC limit).
------------------------------------------------------------------------
local MACRO_PREFIX  = "GF_"
local MAX_MACRO_SYNC = 18   -- TBC per-character macro limit

-- Serialize a set into a compact string
function ns:SerializeSet(set)
    if not set then return nil end
    local parts = {}
    for slotID, itemID in pairs(set.items) do
        if itemID and itemID > 0 then
            parts[#parts + 1] = slotID .. ":" .. itemID
        end
    end
    table.sort(parts)  -- deterministic order
    local icon = type(set.icon) == "number" and set.icon or 134400
    return "GF|" .. set.name .. "|" .. icon .. "|" .. table.concat(parts, ",")
end

-- Deserialize a macro body back into a set table
function ns:DeserializeSet(body)
    if not body or body:sub(1, 3) ~= "GF|" then return nil end
    local name, iconStr, itemStr = body:match("^GF|(.+)|(%d+)|(.+)$")
    if not name or not iconStr or not itemStr then return nil end
    local items = {}
    for slotID, itemID in itemStr:gmatch("(%d+):(%d+)") do
        items[tonumber(slotID)] = tonumber(itemID)
    end
    return {
        name  = name,
        icon  = tonumber(iconStr),
        items = items,
    }
end

-- Write all current sets to per-character macros
function ns:SyncToMacros()
    if ns.db and ns.db.macroSync == false then return end
    if InCombatLockdown() then return end  -- macro API restricted in combat

    local sets = self.charDB.sets
    local numGeneral, numPerChar = GetNumMacros()

    -- Write one macro per set (up to MAX_MACRO_SYNC)
    for i = 1, MAX_MACRO_SYNC do
        local macroName = MACRO_PREFIX .. string.format("%02d", i)
        local macroIndex = GetMacroIndexByName(macroName)

        if i <= #sets then
            local body = self:SerializeSet(sets[i])
            if body and #body <= 255 then
                if macroIndex > 0 then
                    EditMacro(macroIndex, macroName, "INV_Misc_QuestionMark", body, 1)
                else
                    -- Check if we have room for a new per-character macro
                    _, numPerChar = GetNumMacros()
                    if numPerChar < 18 then
                        CreateMacro(macroName, "INV_Misc_QuestionMark", body, 1)
                    end
                end
            elseif body and #body > 255 then
                -- Set name too long to fit — truncate name and retry
                local truncSet = { name = sets[i].name:sub(1, 20), icon = sets[i].icon, items = sets[i].items }
                body = self:SerializeSet(truncSet)
                if body and #body <= 255 then
                    if macroIndex > 0 then
                        EditMacro(macroIndex, macroName, "INV_Misc_QuestionMark", body, 1)
                    else
                        _, numPerChar = GetNumMacros()
                        if numPerChar < 18 then
                            CreateMacro(macroName, "INV_Misc_QuestionMark", body, 1)
                        end
                    end
                end
            end
        else
            -- Excess macro from a previously deleted set — clean up
            if macroIndex > 0 then
                DeleteMacro(macroIndex)
            end
        end
    end
end

-- Import sets from macros (used when logging in on a new PC)
function ns:ImportFromMacros()
    local imported = 0
    for i = 1, MAX_MACRO_SYNC do
        local macroName = MACRO_PREFIX .. string.format("%02d", i)
        local macroIndex = GetMacroIndexByName(macroName)
        if macroIndex > 0 then
            local body = GetMacroBody(macroIndex)
            local set = self:DeserializeSet(body)
            if set then
                -- Don't duplicate — check if we already have this set name
                local existing = self:GetSetByName(set.name)
                if not existing then
                    table.insert(self.charDB.sets, set)
                    imported = imported + 1
                end
            end
        end
    end
    if imported > 0 then
        ns.Print("Imported " .. imported .. " set(s) from macro sync.")
        if ns.RefreshSetList then ns:RefreshSetList() end
    end
    return imported
end

-- Check if macros contain set data (for auto-detect on login)
function ns:HasMacroSets()
    for i = 1, MAX_MACRO_SYNC do
        local macroName = MACRO_PREFIX .. string.format("%02d", i)
        local macroIndex = GetMacroIndexByName(macroName)
        if macroIndex > 0 then
            local body = GetMacroBody(macroIndex)
            if body and body:sub(1, 3) == "GF|" then
                return true
            end
        end
    end
    return false
end
