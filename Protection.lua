------------------------------------------------------------------------
-- GearFrame — Protection
-- Prevents selling, deleting, or banking items that belong to a set.
-- Shows a warning + confirmation before the action goes through.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Check if an item (by link) belongs to any saved equipment set
------------------------------------------------------------------------
local function IsItemInAnySet(itemOrLink)
    if not itemOrLink or not ns.charDB then return false, nil end
    if ns.db and ns.db.protectSetItems == false then return false, nil end
    local itemID
    if type(itemOrLink) == "number" then
        itemID = itemOrLink
    else
        itemID = ns.GetItemIDFromLink(itemOrLink)
    end
    if not itemID then return false, nil end
    local sets = ns:GetSetsContainingItem(itemID)
    if #sets > 0 then
        return true, sets
    end
    return false, nil
end

------------------------------------------------------------------------
-- Format a warning message
------------------------------------------------------------------------
local function FormatWarning(itemLink, sets, action)
    local names = table.concat(sets, ", ")
    return string.format(
        "%s is used in equipment set(s): |cff00ff00%s|r\n\nAre you sure you want to %s it?",
        itemLink or "This item", names, action
    )
end

------------------------------------------------------------------------
-- Confirmation popup
------------------------------------------------------------------------
StaticPopupDialogs["GEARFRAME_PROTECT_ITEM"] = {
    text         = "%s",
    button1      = "Yes, do it",
    button2      = "Cancel",
    OnAccept     = function(self)
        if self.data and self.data.onConfirm then
            self.data.onConfirm()
        end
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    showAlert    = true,
}

------------------------------------------------------------------------
-- Init (called from Core.lua)
------------------------------------------------------------------------
function ns:InitProtection()
    self:HookMerchantProtection()
    self:HookDeleteProtection()
    self:HookBankProtection()
end

------------------------------------------------------------------------
-- MERCHANT SELL PROTECTION
-- Maintains a bag item cache (updated on BAG_UPDATE) so we know exactly
-- which item was in a clicked bag slot BEFORE the sale happened.
-- Only warns about items that were actually sold, not items that happen
-- to be missing from bags (banked, mailed, etc.).
------------------------------------------------------------------------
function ns:HookMerchantProtection()
    -- Bag item cache: bagCache[bag][slot] = itemID
    -- Updated on BAG_UPDATE which fires AFTER bag contents change,
    -- so when a vendor sale hook fires the cache still holds the pre-sale item.
    local bagCache = {}

    local function UpdateBagCache(bagID)
        bagCache[bagID] = bagCache[bagID] or {}
        local numSlots = ns.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local link = ns.GetContainerItemLink(bagID, slot)
            bagCache[bagID][slot] = link and ns.GetItemIDFromLink(link) or 0
        end
        -- Clear any extra slots if bag shrank
        for slot = numSlots + 1, #(bagCache[bagID]) do
            bagCache[bagID][slot] = nil
        end
    end

    -- Seed the cache for all bags and keep it updated
    local cacheFrame = CreateFrame("Frame")
    cacheFrame:RegisterEvent("BAG_UPDATE")
    cacheFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    cacheFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_ENTERING_WORLD" then
            for bag = 0, 4 do UpdateBagCache(bag) end
        elseif event == "BAG_UPDATE" then
            if arg1 >= 0 and arg1 <= 4 then
                UpdateBagCache(arg1)
            end
        end
    end)

    -- Hook bag item button clicks — fires AFTER the original handler
    if ContainerFrameItemButton_OnClick then
        hooksecurefunc("ContainerFrameItemButton_OnClick", function(self, button)
            if button ~= "RightButton" then return end
            if not MerchantFrame or not MerchantFrame:IsShown() then return end
            if not ns.charDB or not ns.charDB.sets then return end
            if ns.db and ns.db.protectSetItems == false then return end

            local bag = self:GetParent():GetID()
            local slot = self:GetID()

            -- Look up what was in this exact slot BEFORE the sale
            local soldItemID = bagCache[bag] and bagCache[bag][slot] or 0
            if soldItemID == 0 then return end

            -- Item is still there — wasn't actually sold (e.g. shift-click for link)
            local currentLink = ns.GetContainerItemLink(bag, slot)
            if currentLink and ns.GetItemIDFromLink(currentLink) == soldItemID then
                return
            end

            -- Item left this slot. Check if it belongs to any saved set.
            local sets = ns:GetSetsContainingItem(soldItemID)
            if #sets > 0 then
                local itemName = GetItemInfo(soldItemID) or ("item#" .. soldItemID)
                local names = table.concat(sets, ", ")
                ns.Print("|cffff4444WARNING:|r You just sold |cffffaa00" .. itemName .. "|r which is in your |cff00ff00" .. names .. "|r equipment set(s)! Use the |cffffaa00Buyback|r tab to get it back!")
            end
        end)
    end
end

------------------------------------------------------------------------
-- DELETE PROTECTION
-- Hook the delete item confirmation to warn about set items.
-- The game uses StaticPopup DELETE_GOOD_ITEM / DELETE_ITEM.
------------------------------------------------------------------------
function ns:HookDeleteProtection()
    -- Hook both delete popups
    local deletePopups = { "DELETE_GOOD_ITEM", "DELETE_ITEM", "DELETE_GOOD_QUEST_ITEM", "DELETE_QUEST_ITEM" }

    for _, popupName in ipairs(deletePopups) do
        local orig = StaticPopupDialogs[popupName]
        if orig then
            local origOnShow = orig.OnShow
            orig.OnShow = function(self, ...)
                -- GetCursorInfo returns: cursorType, itemID, itemLink
                local cursorType, cursorID, cursorLink = GetCursorInfo()
                local itemID = nil
                if cursorType == "item" then
                    itemID = cursorID
                end

                if itemID then
                    local inSet, sets = IsItemInAnySet(itemID)
                    if inSet then
                        local names = table.concat(sets, ", ")
                        -- Prepend warning to existing text
                        local warningText = "|cffff4444GearFrame WARNING:|r This item is in set(s): |cff00ff00" .. names .. "|r\n\n"
                        if self.text and self.text.GetText then
                            local existing = self.text:GetText() or ""
                            self.text:SetText(warningText .. existing)
                        end
                    end
                end

                if origOnShow then
                    return origOnShow(self, ...)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- BANK PROTECTION
-- When the bank is open, warn if a set item leaves player bags/equip.
-- Uses a bag snapshot to detect which specific items were deposited,
-- rather than scanning all sets (which would false-positive on items
-- that were never in bags to begin with).
------------------------------------------------------------------------
function ns:HookBankProtection()
    local bankOpen = false
    local bagSnapshot = {}  -- bagSnapshot[bag][slot] = itemID, taken when bank opens and on BAG_UPDATE

    local function SnapshotBags()
        for bag = 0, 4 do
            bagSnapshot[bag] = bagSnapshot[bag] or {}
            local numSlots = ns.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local link = ns.GetContainerItemLink(bag, slot)
                bagSnapshot[bag][slot] = link and ns.GetItemIDFromLink(link) or 0
            end
            for slot = numSlots + 1, #(bagSnapshot[bag]) do
                bagSnapshot[bag][slot] = nil
            end
        end
    end

    -- Track bank open/close
    if BankFrame then
        BankFrame:HookScript("OnShow", function()
            bankOpen = true
            SnapshotBags()
        end)
        BankFrame:HookScript("OnHide", function()
            bankOpen = false
        end)
    end

    -- On BAG_UPDATE while bank is open, diff snapshot to find what left
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:SetScript("OnEvent", function(_, event, bagID)
        if not bankOpen then return end
        if bagID < 0 or bagID > 4 then return end
        if not ns.charDB or not ns.charDB.sets then return end
        if ns.db and ns.db.protectSetItems == false then return end

        local oldBag = bagSnapshot[bagID]
        if not oldBag then SnapshotBags(); return end

        -- Find items that left this bag
        local numSlots = ns.GetContainerNumSlots(bagID)
        for slot = 1, math.max(numSlots, #oldBag) do
            local oldID = oldBag[slot] or 0
            if oldID > 0 then
                local currentLink = ns.GetContainerItemLink(bagID, slot)
                local currentID = currentLink and ns.GetItemIDFromLink(currentLink) or 0
                if currentID ~= oldID then
                    -- This item left this bag slot. Check if it's in a set.
                    local sets = ns:GetSetsContainingItem(oldID)
                    if #sets > 0 then
                        -- Verify the item isn't still available (in another bag slot or equipped)
                        local stillInBags = ns.FindItemInBags(oldID)
                        local stillEquipped = false
                        if not stillInBags then
                            for sid = 1, ns.NUM_EQUIP_SLOTS do
                                if GetInventoryItemID("player", sid) == oldID then
                                    stillEquipped = true
                                    break
                                end
                            end
                        end
                        if not stillInBags and not stillEquipped then
                            local itemName = GetItemInfo(oldID) or ("item#" .. oldID)
                            local names = table.concat(sets, ", ")
                            ns.Print("|cffff4444Warning:|r |cffffaa00" .. itemName .. "|r (set: |cff00ff00" .. names .. "|r) was deposited to the bank. You won't be able to equip this set without it!")
                        end
                    end
                end
            end
        end

        -- Update snapshot to current state
        SnapshotBags()
    end)
end
