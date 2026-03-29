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
-- Compact format packs ~3 sets per macro via base-36 item IDs and
-- positional slot encoding. Uses macros GF_01 through GF_07.
------------------------------------------------------------------------
local MACRO_PREFIX   = "GF_"
local MAX_SYNC_MACROS = 7   -- enough for 20 sets at ~3 per macro
local SYNC_SLOTS     = { 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18 }

-- Base-36 encode/decode (0-9, A-Z) — 3 chars covers 0–46655
local B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function toBase36(num, width)
    if num == 0 then return string.rep("0", width) end
    local result = ""
    while num > 0 do
        local rem = num % 36
        result = B36:sub(rem + 1, rem + 1) .. result
        num = math.floor(num / 36)
    end
    while #result < width do result = "0" .. result end
    return result
end

local function fromBase36(str)
    local num = 0
    for i = 1, #str do
        local c = str:sub(i, i)
        local val = B36:find(c, 1, true)
        if not val then return 0 end
        num = num * 36 + (val - 1)
    end
    return num
end

-- Serialize one set: "name;IIII;AAABBBCCC000..." (name;iconBase36;18×3-char items)
local function PackSet(set)
    if not set then return nil end
    local icon = type(set.icon) == "number" and set.icon or 134400
    local items = ""
    for _, slotID in ipairs(SYNC_SLOTS) do
        local id = set.items[slotID]
        items = items .. toBase36((id and id > 0) and id or 0, 3)
    end
    return set.name .. ";" .. toBase36(icon, 4) .. ";" .. items
end

-- Deserialize one set line back to a table
local function UnpackSet(line)
    if not line or #line < 10 then return nil end
    local name, iconB36, itemsB36 = line:match("^(.+);(%w%w%w%w);(%w+)$")
    if not name or not iconB36 or not itemsB36 then return nil end
    if #itemsB36 ~= #SYNC_SLOTS * 3 then return nil end
    local icon = fromBase36(iconB36)
    local items = {}
    for i, slotID in ipairs(SYNC_SLOTS) do
        local chunk = itemsB36:sub((i - 1) * 3 + 1, i * 3)
        local id = fromBase36(chunk)
        if id > 0 then items[slotID] = id end
    end
    return { name = name, icon = icon, items = items }
end

-- Write all current sets packed into as few macros as possible
function ns:SyncToMacros()
    if ns.db and ns.db.macroSync == false then return end
    if InCombatLockdown() then return end

    local sets = self.charDB.sets

    -- Pack sets into macro bodies (multiple sets per macro, newline-separated)
    local macroBodies = {}
    local currentBody = ""
    local macroIdx = 1

    for i, set in ipairs(sets) do
        local packed = PackSet(set)
        if not packed then -- skip unparseable
        elseif currentBody == "" then
            currentBody = packed
        elseif #currentBody + 1 + #packed <= 255 then
            currentBody = currentBody .. "\n" .. packed
        else
            -- Current macro is full, start a new one
            macroBodies[macroIdx] = currentBody
            macroIdx = macroIdx + 1
            currentBody = packed
        end
    end
    if currentBody ~= "" then
        macroBodies[macroIdx] = currentBody
    end

    -- Write to macro slots
    for i = 1, MAX_SYNC_MACROS do
        local macroName = MACRO_PREFIX .. string.format("%02d", i)
        local macroIndex = GetMacroIndexByName(macroName)
        local body = macroBodies[i]

        if body then
            if macroIndex > 0 then
                EditMacro(macroIndex, macroName, "INV_Misc_QuestionMark", body, 1)
            else
                local _, numPerChar = GetNumMacros()
                if numPerChar < 18 then
                    CreateMacro(macroName, "INV_Misc_QuestionMark", body, 1)
                end
            end
        else
            -- No data for this slot — delete if exists
            if macroIndex > 0 then
                DeleteMacro(macroIndex)
            end
        end
    end

    -- Clean up old-format macros (GF_08 through GF_18 from previous version)
    for i = MAX_SYNC_MACROS + 1, 18 do
        local macroName = MACRO_PREFIX .. string.format("%02d", i)
        local macroIndex = GetMacroIndexByName(macroName)
        if macroIndex > 0 then DeleteMacro(macroIndex) end
    end
end

-- Import sets from macros
function ns:ImportFromMacros()
    local imported = 0
    for i = 1, MAX_SYNC_MACROS do
        local macroName = MACRO_PREFIX .. string.format("%02d", i)
        local macroIndex = GetMacroIndexByName(macroName)
        if macroIndex > 0 then
            local body = GetMacroBody(macroIndex)
            if body then
                for line in body:gmatch("[^\n]+") do
                    local set = UnpackSet(line)
                    if set then
                        local existing = self:GetSetByName(set.name)
                        if not existing then
                            table.insert(self.charDB.sets, set)
                            imported = imported + 1
                        end
                    end
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

-- Check if macros contain set data
function ns:HasMacroSets()
    for i = 1, MAX_SYNC_MACROS do
        local macroName = MACRO_PREFIX .. string.format("%02d", i)
        local macroIndex = GetMacroIndexByName(macroName)
        if macroIndex > 0 then
            local body = GetMacroBody(macroIndex)
            if body and body:find(";%w%w%w%w;") then
                return true
            end
        end
    end
    return false
end
