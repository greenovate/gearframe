------------------------------------------------------------------------
-- GearFrame — Tooltips
-- Hooks GameTooltip to show which equipment sets an item belongs to,
-- exactly like retail's "Equipment Sets: Tank, PvP" line.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Public init (called from Core.lua)
------------------------------------------------------------------------
function ns:InitTooltips()
    self:HookTooltips()
end

------------------------------------------------------------------------
-- Core hook
------------------------------------------------------------------------
function ns:HookTooltips()
    -- Hook the two main ways items appear in GameTooltip:
    --  1. SetBagItem (hovering items in bags)
    --  2. SetInventoryItem (hovering equipped items on paperdoll)
    --  3. SetHyperlink (chat links, etc.)

    local function AddSetLine(tooltip, itemID)
        if not itemID or not ns.charDB then return end
        local sets = ns:GetSetsContainingItem(itemID)
        if #sets == 0 then return end

        local names = table.concat(sets, ", ")
        tooltip:AddLine("Equipment Sets: " .. names, 0.0, 1.0, 0.0)
        tooltip:Show()  -- re-show to resize
    end

    -- Bag items (SetBagItem may not exist in modern Classic clients)
    if GameTooltip.SetBagItem then
        hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot)
            local link = ns.GetContainerItemLink(bag, slot)
            if link then
                AddSetLine(self, ns.GetItemIDFromLink(link))
            end
        end)
    end

    -- TooltipDataProcessor handles bag tooltips on modern clients
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip then return end
            local id = data and data.id
            if id then
                AddSetLine(tooltip, id)
            end
        end)
    end

    -- Equipped items
    hooksecurefunc(GameTooltip, "SetInventoryItem", function(self, unit, slot)
        if unit ~= "player" then return end
        local link = GetInventoryItemLink(unit, slot)
        if link then
            AddSetLine(self, ns.GetItemIDFromLink(link))
        end
    end)

    -- Hyperlinks (chat, loot, etc.)
    hooksecurefunc(GameTooltip, "SetHyperlink", function(self, hyperlink)
        if not hyperlink then return end
        local id = tonumber(hyperlink:match("item:(%d+)"))
        if id then
            AddSetLine(self, id)
        end
    end)
end
