------------------------------------------------------------------------
-- GearFrame — Flyout
-- Click the arrow button on any paperdoll slot to browse all bag items
-- that can go in that slot.  Alt+hover also works as a shortcut.
------------------------------------------------------------------------
local _, ns = ...

local COLS          = 4
local ICON_SIZE     = 40
local PAD           = 3
local MAX_ITEMS     = 32
local ARROW_SIZE    = 14

local flyout            -- main flyout frame
local flyoutButtons     = {}
local arrowButtons      = {}
local activeSlotID      = nil
local activeSlotButton  = nil
local flyoutPinned      = false   -- true when opened via arrow click

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },   -- Poor
    [1] = { 1.00, 1.00, 1.00 },   -- Common
    [2] = { 0.12, 1.00, 0.00 },   -- Uncommon
    [3] = { 0.00, 0.44, 0.87 },   -- Rare
    [4] = { 0.64, 0.21, 0.93 },   -- Epic
    [5] = { 1.00, 0.50, 0.00 },   -- Legendary
}

------------------------------------------------------------------------
-- Arrow anchor positions per slot (relative to the slot button)
-- Each entry: { point, relPoint, xOff, yOff }
------------------------------------------------------------------------
local ARROW_ANCHORS = {
    -- Left-side slots: arrow on the right edge
    [1]  = { "LEFT",  "RIGHT",  -2,  0 },  -- Head
    [2]  = { "LEFT",  "RIGHT",  -2,  0 },  -- Neck
    [3]  = { "LEFT",  "RIGHT",  -2,  0 },  -- Shoulder
    [4]  = { "LEFT",  "RIGHT",  -2,  0 },  -- Shirt
    [15] = { "LEFT",  "RIGHT",  -2,  0 },  -- Back
    [5]  = { "LEFT",  "RIGHT",  -2,  0 },  -- Chest
    [9]  = { "LEFT",  "RIGHT",  -2,  0 },  -- Wrist
    -- Right-side slots: arrow on the left edge
    [10] = { "RIGHT", "LEFT",    2,  0 },  -- Hands
    [6]  = { "RIGHT", "LEFT",    2,  0 },  -- Waist
    [7]  = { "RIGHT", "LEFT",    2,  0 },  -- Legs
    [8]  = { "RIGHT", "LEFT",    2,  0 },  -- Feet
    [11] = { "RIGHT", "LEFT",    2,  0 },  -- Ring 1
    [12] = { "RIGHT", "LEFT",    2,  0 },  -- Ring 2
    [13] = { "RIGHT", "LEFT",    2,  0 },  -- Trinket 1
    [14] = { "RIGHT", "LEFT",    2,  0 },  -- Trinket 2
    [19] = { "RIGHT", "LEFT",    2,  0 },  -- Tabard
    -- Bottom slots: arrow on the bottom edge
    [16] = { "TOP",   "BOTTOM",  0,  2 },  -- Main Hand
    [17] = { "TOP",   "BOTTOM",  0,  2 },  -- Off Hand
    [18] = { "TOP",   "BOTTOM",  0,  2 },  -- Ranged
}

------------------------------------------------------------------------
-- Public init (called from Core.lua)
------------------------------------------------------------------------
function ns:InitFlyout()
    self:CreateFlyoutFrame()
    self:HookPaperdollSlots()
    self:CreateArrowButtons()
end

------------------------------------------------------------------------
-- Flyout frame
------------------------------------------------------------------------
local LEAVE_GRACE = 0.3   -- seconds before flyout closes after mouse leaves
local leaveTimer  = nil

-- Check if cursor is inside a frame's screen rect with padding
local function CursorInFrame(frame, pad)
    if not frame or not frame:IsShown() then return false end
    pad = pad or 0
    local x, y = GetCursorPosition()
    local s = frame:GetEffectiveScale()
    x, y = x / s, y / s
    local l, b, w, h = frame:GetRect()
    if not l then return false end
    return x >= (l - pad) and x <= (l + w + pad) and y >= (b - pad) and y <= (b + h + pad)
end

function ns:CreateFlyoutFrame()
    flyout = CreateFrame("Frame", "GearFrameFlyout", UIParent, "BackdropTemplate")
    ns.Themes:SkinFrame(flyout)
    flyout:SetFrameStrata("TOOLTIP")
    flyout:EnableMouse(true)
    flyout:Hide()

    -- Slot title at top
    local title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6)
    title:SetTextColor(1, 0.82, 0)
    flyout.title = title

    -- Smart auto-hide: cursor position check with grace timer
    flyout:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end

        -- Is mouse inside the flyout (with 10px padding) or the parent slot?
        local inFlyout = CursorInFrame(self, 10)
        local inSlot   = CursorInFrame(activeSlotButton, 4)
        local inArrow  = activeSlotID and arrowButtons[activeSlotID] and CursorInFrame(arrowButtons[activeSlotID], 6)

        if inFlyout or inSlot or inArrow then
            leaveTimer = nil  -- reset
        else
            if not leaveTimer then
                leaveTimer = LEAVE_GRACE
            else
                leaveTimer = leaveTimer - elapsed
                if leaveTimer <= 0 then
                    leaveTimer = nil
                    ns:CloseFlyout()
                end
            end
        end
    end)

    flyout:SetScript("OnHide", function()
        leaveTimer = nil
        flyoutPinned = false
        activeSlotID = nil
        activeSlotButton = nil
    end)
end

function ns:CloseFlyout()
    if flyout then
        flyout:Hide()
    end
    leaveTimer = nil
    flyoutPinned = false
    activeSlotID = nil
    activeSlotButton = nil
end

------------------------------------------------------------------------
-- Create / reuse a flyout item button
------------------------------------------------------------------------
local function GetOrCreateButton(index)
    if flyoutButtons[index] then return flyoutButtons[index] end

    local btn = CreateFrame("Button", "GearFrameFlyBtn" .. index, flyout)
    btn:SetSize(ICON_SIZE, ICON_SIZE)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Quality border: 4 simple color edges (2px thick)
    local B = 2
    local top = btn:CreateTexture(nil, "OVERLAY")
    top:SetHeight(B)
    top:SetPoint("TOPLEFT", -B, B)
    top:SetPoint("TOPRIGHT", B, B)
    top:SetColorTexture(1, 1, 1, 1)
    btn.borderTop = top

    local bot = btn:CreateTexture(nil, "OVERLAY")
    bot:SetHeight(B)
    bot:SetPoint("BOTTOMLEFT", -B, -B)
    bot:SetPoint("BOTTOMRIGHT", B, -B)
    bot:SetColorTexture(1, 1, 1, 1)
    btn.borderBot = bot

    local left = btn:CreateTexture(nil, "OVERLAY")
    left:SetWidth(B)
    left:SetPoint("TOPLEFT", -B, B)
    left:SetPoint("BOTTOMLEFT", -B, -B)
    left:SetColorTexture(1, 1, 1, 1)
    btn.borderLeft = left

    local right = btn:CreateTexture(nil, "OVERLAY")
    right:SetWidth(B)
    right:SetPoint("TOPRIGHT", B, B)
    right:SetPoint("BOTTOMRIGHT", B, -B)
    right:SetColorTexture(1, 1, 1, 1)
    btn.borderRight = right

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- "Equipped" badge (hidden until needed)
    local eqTag = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eqTag:SetPoint("BOTTOM", 0, 3)
    eqTag:SetText("Eq")
    eqTag:SetTextColor(0, 1, 0, 0.9)
    eqTag:Hide()
    btn.eqTag = eqTag

    btn:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    flyoutButtons[index] = btn
    return btn
end

------------------------------------------------------------------------
-- Show the flyout for a specific equipment slot
------------------------------------------------------------------------
function ns:ShowFlyout(slotButton, slotID, pinned)
    activeSlotID     = slotID
    activeSlotButton = slotButton
    flyoutPinned     = pinned or false

    -- Gather bag items
    local bagItems = ns.GetBagItemsForSlot(slotID)

    local equippedLink = GetInventoryItemLink("player", slotID)
    local equippedTex  = GetInventoryItemTexture("player", slotID)

    if #bagItems == 0 and not equippedLink then
        flyout:Hide(); return
    end

    -- Title
    local info = ns.SLOT_BY_ID[slotID]
    flyout.title:SetText(info and info.display or "Equipment")

    -- Hide old buttons
    for _, b in ipairs(flyoutButtons) do b:Hide() end

    local count = 0

    -- Currently equipped item (dimmed, non-clickable)
    if equippedLink then
        count = count + 1
        local btn = GetOrCreateButton(count)
        btn.icon:SetTexture(equippedTex)
        btn.itemLink = equippedLink
        btn:SetAlpha(0.50)
        btn.eqTag:Show()

        -- No equip action on the already-equipped item
        btn:SetScript("OnClick", nil)

        local _, _, q = GetItemInfo(equippedLink)
        local qc = QUALITY_COLORS[q or 1] or QUALITY_COLORS[1]
        btn.borderTop:SetColorTexture(qc[1], qc[2], qc[3], 1)
        btn.borderBot:SetColorTexture(qc[1], qc[2], qc[3], 1)
        btn.borderLeft:SetColorTexture(qc[1], qc[2], qc[3], 1)
        btn.borderRight:SetColorTexture(qc[1], qc[2], qc[3], 1)

        local c = (count - 1) % COLS
        local r = math.floor((count - 1) / COLS)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", PAD + c * (ICON_SIZE + PAD),
                     -(22 + PAD + r * (ICON_SIZE + PAD)))
        btn:Show()
    end

    -- Bag items
    for _, item in ipairs(bagItems) do
        if count >= MAX_ITEMS then break end
        count = count + 1
        local btn = GetOrCreateButton(count)
        btn.icon:SetTexture(item.texture)
        btn.itemLink = item.link
        btn:SetAlpha(1)
        btn.eqTag:Hide()

        local capBag, capSlot, capTargetSlot = item.bag, item.slot, slotID  -- capture
        btn:SetScript("OnClick", function()
            if InCombatLockdown() then
                ns.Print("Cannot change equipment in combat."); return
            end
            ClearCursor()
            ns.PickupContainerItem(capBag, capSlot)
            PickupInventoryItem(capTargetSlot)
            ns:CloseFlyout()
        end)

        local _, _, q = GetItemInfo(item.link)
        local qc = QUALITY_COLORS[q or 1] or QUALITY_COLORS[1]
        btn.borderTop:SetColorTexture(qc[1], qc[2], qc[3], 1)
        btn.borderBot:SetColorTexture(qc[1], qc[2], qc[3], 1)
        btn.borderLeft:SetColorTexture(qc[1], qc[2], qc[3], 1)
        btn.borderRight:SetColorTexture(qc[1], qc[2], qc[3], 1)

        local c = (count - 1) % COLS
        local r = math.floor((count - 1) / COLS)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", PAD + c * (ICON_SIZE + PAD),
                     -(22 + PAD + r * (ICON_SIZE + PAD)))
        btn:Show()
    end

    if count == 0 then flyout:Hide(); return end

    -- Size to fit
    local numCols = math.min(count, COLS)
    local numRows = math.ceil(count / COLS)
    flyout:SetSize(
        numCols * (ICON_SIZE + PAD) + PAD + 8,
        numRows * (ICON_SIZE + PAD) + PAD + 30
    )

    flyout:ClearAllPoints()
    flyout:SetPoint("TOPLEFT", slotButton, "BOTTOMLEFT", 0, -2)
    flyout:Show()
end

------------------------------------------------------------------------
-- Arrow (caret) buttons on each paperdoll slot
------------------------------------------------------------------------
function ns:CreateArrowButtons()
    local nameToSlot = {}
    for _, info in ipairs(ns.SLOT_INFO) do
        nameToSlot["Character" .. info.name] = info.id
    end

    for _, btnName in ipairs(ns.PAPERDOLL_SLOTS) do
        local slotBtn = _G[btnName]
        if slotBtn then
            local slotID = nameToSlot[btnName]
            if slotID then
                local anchor = ARROW_ANCHORS[slotID] or { "LEFT", "RIGHT", -2, 0 }

                local arrow = CreateFrame("Button", "GearFrameArrow" .. slotID, slotBtn)
                arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
                arrow:SetPoint(anchor[1], slotBtn, anchor[2], anchor[3], anchor[4])
                arrow:SetFrameLevel(slotBtn:GetFrameLevel() + 5)
                arrow.tcSlotID = slotID

                -- Arrow triangle texture
                local tex = arrow:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture("Interface\\Buttons\\SquareButtonTextures")
                tex:SetTexCoord(0.42187500, 0.23437500, 0.01562500, 0.20312500)
                arrow.arrowTex = tex

                -- Highlight on hover
                local hl = arrow:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetTexture("Interface\\Buttons\\SquareButtonTextures")
                hl:SetTexCoord(0.42187500, 0.23437500, 0.01562500, 0.20312500)
                hl:SetAlpha(0.4)

                -- Glow when flyout is open for this slot
                local glow = arrow:CreateTexture(nil, "OVERLAY")
                glow:SetSize(ARROW_SIZE + 6, ARROW_SIZE + 6)
                glow:SetPoint("CENTER")
                glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                glow:SetBlendMode("ADD")
                glow:SetVertexColor(1, 0.82, 0, 0.6)
                glow:Hide()
                arrow.glow = glow

                -- Click to toggle flyout
                arrow:SetScript("OnClick", function(self)
                    if flyout:IsShown() and activeSlotID == self.tcSlotID then
                        ns:CloseFlyout()
                        self.glow:Hide()
                    else
                        -- Hide glow on previous arrow
                        if activeSlotID and arrowButtons[activeSlotID] then
                            arrowButtons[activeSlotID].glow:Hide()
                        end
                        local parentSlot = self:GetParent()
                        ns:ShowFlyout(parentSlot, self.tcSlotID, true)
                        self.glow:Show()
                    end
                end)

                arrow:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local info = ns.SLOT_BY_ID[self.tcSlotID]
                    GameTooltip:AddLine("Browse " .. (info and info.display or "Equipment"), 1, 1, 1)
                    GameTooltip:AddLine("Click to see available items", 0.5, 0.5, 0.5)
                    GameTooltip:Show()
                end)
                arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)

                arrowButtons[slotID] = arrow
            end
        end
    end

    -- Hide arrow glow when flyout closes
    flyout:HookScript("OnHide", function()
        for _, arr in pairs(arrowButtons) do
            arr.glow:Hide()
        end
    end)
end

------------------------------------------------------------------------
-- Hook paperdoll slot buttons (Alt + hover trigger — still works)
------------------------------------------------------------------------
function ns:HookPaperdollSlots()
    -- Build name→slotID map
    local nameToSlot = {}
    for _, info in ipairs(ns.SLOT_INFO) do
        nameToSlot["Character" .. info.name] = info.id
    end

    for _, btnName in ipairs(ns.PAPERDOLL_SLOTS) do
        local btn = _G[btnName]
        if btn then
            local slotID = nameToSlot[btnName]
            if slotID then
                btn.tcSlotID = slotID

                btn:HookScript("OnEnter", function(self)
                    if IsAltKeyDown() then
                        ns:ShowFlyout(self, self.tcSlotID, true)
                    end
                end)

                btn:HookScript("OnLeave", function()
                    -- flyout stays open; closed by click-off, Escape, or alt-release
                end)
            end
        end
    end

    -- Detect Alt press/release while already hovering a slot
    local watcher = CreateFrame("Frame")
    local wasAlt = false
    watcher:SetScript("OnUpdate", function()
        local alt = IsAltKeyDown()
        if alt == wasAlt then return end
        wasAlt = alt
        if alt then
            local focus = ns.SafeGetMouseFocus()
            if focus and focus.tcSlotID then
                ns:ShowFlyout(focus, focus.tcSlotID)
            end
        else
            if flyout and flyout:IsShown() and not flyoutPinned then
                ns:CloseFlyout()
            end
        end
    end)
end
