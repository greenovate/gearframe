------------------------------------------------------------------------
-- GearFrame — UI
-- Equipment-set panel (character frame sidebar), save dialog, icon picker
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Layout constants
------------------------------------------------------------------------
local PANEL_WIDTH       = 180
local SET_ROW_HEIGHT    = 36
local NUM_VISIBLE_ROWS  = 8
local ICON_SIZE         = 32
local SAVE_DLG_WIDTH    = 340
local SAVE_DLG_HEIGHT   = 490
local PICKER_COLS       = 8
local PICKER_ICON_SIZE  = 36
local PICKER_PAD        = 4

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local selectedSetIndex = nil
local editingSetIndex  = nil      -- nil = new, number = editing
local selectedIcon     = nil

-- Public: clear selection (called when deleting via slash command)
function ns:ClearSetSelection()
    selectedSetIndex = nil
    if ns.RefreshSetList then ns:RefreshSetList() end
end

------------------------------------------------------------------------
-- Reusable backdrops (fallback only — theme system overrides these)
------------------------------------------------------------------------
local PANEL_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local DIALOG_BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

------------------------------------------------------------------------
-- Public entry point (called from Core.lua)
------------------------------------------------------------------------
function ns:InitUI()
    self:CreateSetPanel()
    self:CreateSaveDialog()
    self:CreateIconPicker()

    -- Apply theme to all frames
    ns.Themes:ApplyAll()

    -- Refresh when gear changes
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ef:RegisterEvent("BAG_UPDATE")
    ef:SetScript("OnEvent", function()
        if ns.setPanel and ns.setPanel:IsShown() then
            ns:RefreshSetList()
        end
    end)

    -- Refresh when PaperDollFrame appears
    PaperDollFrame:HookScript("OnShow", function()
        if ns.setPanel then
            if not ns.db.panelCollapsed then
                ns.setPanel:Show()
            end
            ns:UpdateToggleButton()
            ns:RefreshSetList()
        end
    end)

    CharacterFrame:HookScript("OnHide", function()
        if ns.setPanel then ns.setPanel:Hide() end
        if ns.toggleBtn then ns.toggleBtn:Hide() end
    end)
    CharacterFrame:HookScript("OnShow", function()
        if ns.toggleBtn then ns.toggleBtn:Show() end
        if ns.setPanel and not ns.db.panelCollapsed then
            ns.setPanel:Show()
            ns:RefreshSetList()
        end
    end)

    -- Create toggle button on character frame
    self:CreateToggleButton()
end

------------------------------------------------------------------------
-- Anchor helper — ElvUI reskins CharacterFrame so its rect is wrong.
-- Use CharacterFrame.backdrop (ElvUI) or CharacterFrame (stock UI).
------------------------------------------------------------------------
local function GetAnchorFrame()
    if ns.Themes:IsElvUILoaded() and CharacterFrame.backdrop then
        return CharacterFrame.backdrop
    end
    return CharacterFrame
end

------------------------------------------------------------------------
-- Reset panel position back to anchored on character frame
------------------------------------------------------------------------
function ns:ResetPanelPosition()
    if not ns.setPanel then return end
    ns.db.panelPos = nil
    local anchor = GetAnchorFrame()
    ns.setPanel:ClearAllPoints()
    ns.setPanel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
    ns.setPanel:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
    ns.Print("Panel position reset to character frame.")
end

------------------------------------------------------------------------
-- Toggle button — tab on the right edge of the character frame border
------------------------------------------------------------------------
function ns:CreateToggleButton()
    local btn = CreateFrame("Button", "GearFrameToggleBtn", CharacterFrame)
    btn:SetSize(20, 60)
    btn:SetFrameLevel(CharacterFrame:GetFrameLevel() + 5)
    ns.toggleBtn = btn

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.92)

    local B = 1
    local bt = btn:CreateTexture(nil, "OVERLAY")
    bt:SetHeight(B); bt:SetPoint("TOPLEFT"); bt:SetPoint("TOPRIGHT")
    bt:SetColorTexture(0.3, 0.3, 0.3, 1)
    local bb = btn:CreateTexture(nil, "OVERLAY")
    bb:SetHeight(B); bb:SetPoint("BOTTOMLEFT"); bb:SetPoint("BOTTOMRIGHT")
    bb:SetColorTexture(0.3, 0.3, 0.3, 1)
    local br = btn:CreateTexture(nil, "OVERLAY")
    br:SetWidth(B); br:SetPoint("TOPRIGHT"); br:SetPoint("BOTTOMRIGHT")
    br:SetColorTexture(0.3, 0.3, 0.3, 1)

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("CENTER", 1, 0)
    arrow:SetTextColor(0.7, 0.7, 0.7)
    btn.arrow = arrow

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:GetHighlightTexture():SetAlpha(0.15)

    btn:SetScript("OnClick", function() ns:ToggleSetPanel() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.db.panelCollapsed and "Show Equipment Sets" or "Hide Equipment Sets", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:UpdateToggleButton()
end

function ns:UpdateToggleButton()
    if not ns.toggleBtn then return end
    ns.toggleBtn:ClearAllPoints()
    if ns.db.panelCollapsed then
        ns.toggleBtn.arrow:SetText(">")
        local anchor = GetAnchorFrame()
        ns.toggleBtn:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
    else
        ns.toggleBtn.arrow:SetText("<")
        ns.toggleBtn:SetPoint("LEFT", ns.setPanel, "RIGHT", 0, 0)
    end
end

function ns:ToggleSetPanel()
    ns.db.panelCollapsed = not ns.db.panelCollapsed
    if ns.db.panelCollapsed then
        ns.setPanel:Hide()
    else
        ns.setPanel:Show()
        ns:RefreshSetList()
    end
    self:UpdateToggleButton()
end

------------------------------------------------------------------------
-- SET PANEL — flush sidebar anchored to the character panel
------------------------------------------------------------------------
function ns:CreateSetPanel()
    local anchor = GetAnchorFrame()
    local panel = CreateFrame("Frame", "GearFramePanel", CharacterFrame, "BackdropTemplate")
    panel:SetWidth(PANEL_WIDTH)
    panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
    panel:SetBackdrop(PANEL_BACKDROP)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameLevel(CharacterFrame:GetFrameLevel() + 2)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    ns.setPanel = panel

    -- Alt+drag to detach/move
    panel:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsAltKeyDown() and ns.db.panelDetachable then
            -- Capture current position before detaching
            local left, top = self:GetLeft(), self:GetTop()
            local height = self:GetHeight()
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            self:SetHeight(height)
            self:StartMoving()
            self.isMoving = true
        end
    end)
    panel:SetScript("OnMouseUp", function(self, button)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            -- Save position
            local left, top = self:GetLeft(), self:GetTop()
            local height = self:GetHeight()
            ns.db.panelPos = { x = left, y = top, h = height }
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            self:SetHeight(height)
        end
    end)

    -- Restore saved detached position if it exists
    if ns.db.panelDetachable and ns.db.panelPos then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.panelPos.x, ns.db.panelPos.y)
        panel:SetHeight(ns.db.panelPos.h or 400)
    end

    -- Title -----------------------------------------------------------
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Equipment Sets")
    title:SetTextColor(1, 0.82, 0)

    -- Scroll frame (FauxScrollFrame) ----------------------------------
    local sf = CreateFrame("ScrollFrame", "GearFrameScrollFrame", panel, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -30)
    sf:SetPoint("BOTTOMRIGHT", -28, 46)
    sf:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, SET_ROW_HEIGHT, function() ns:RefreshSetList() end)
    end)
    ns.scrollFrame = sf

    -- Row buttons -----------------------------------------------------
    ns.setButtons = {}
    for i = 1, NUM_VISIBLE_ROWS do
        local btn = CreateFrame("Button", "GearFrameSetBtn" .. i, panel)
        btn:SetSize(PANEL_WIDTH - 40, SET_ROW_HEIGHT)
        btn:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -((i - 1) * SET_ROW_HEIGHT))

        -- Highlight
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)

        -- Selection overlay
        local sel = btn:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.25, 0.50, 0.80, 0.35)
        sel:Hide()
        btn.selTex = sel

        -- Icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        -- Name
        local name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetPoint("RIGHT", -18, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        btn.nameText = name

        -- Equipped checkmark
        local ck = btn:CreateTexture(nil, "OVERLAY")
        ck:SetSize(14, 14)
        ck:SetPoint("RIGHT", -2, 0)
        ck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        ck:Hide()
        btn.checkmark = ck

        -- Click
        btn:SetScript("OnClick", function(self, mouseBtn)
            if mouseBtn == "RightButton" and self.setIndex then
                -- Right-click → edit
                selectedSetIndex = self.setIndex
                ns:ShowSaveDialog(self.setIndex)
            else
                selectedSetIndex = self.setIndex
            end
            ns:RefreshSetList()
        end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Double-click equip
        btn:SetScript("OnDoubleClick", function(self)
            if self.setIndex then ns:EquipSet(self.setIndex) end
        end)

        -- Tooltip — smart audit
        btn:SetScript("OnEnter", function(self)
            if not self.setIndex then return end
            local set = ns.charDB.sets[self.setIndex]
            if not set then return end
            local status, missing, changed, equipped, total = ns:AuditSet(set)

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(set.name, 1, 0.82, 0)
            GameTooltip:AddLine(" ")

            -- Status summary line
            if status == "equipped" then
                GameTooltip:AddLine("Status: Fully equipped", 0, 1, 0)
            elseif status == "ready" or status == "modified" then
                GameTooltip:AddLine("Status: Ready to equip (" .. equipped .. "/" .. total .. " worn)", 0.5, 0.8, 1)
            elseif status == "missing" then
                GameTooltip:AddLine("Status: " .. #missing .. " item(s) MISSING — cannot fully equip", 1, 0.2, 0.2)
            end

            GameTooltip:AddLine(" ")

            -- Show each slot
            for _, info in ipairs(ns.SLOT_INFO) do
                local itemID = set.items[info.id]
                if itemID and itemID > 0 then
                    local n, _, q = GetItemInfo(itemID)
                    local currentID = GetInventoryItemID("player", info.id) or 0

                    if currentID == itemID then
                        -- Equipped correctly
                        if n then
                            local r, g, b = GetItemQualityColor(q or 1)
                            GameTooltip:AddLine(info.display .. ": " .. n .. "  |cff00ff00\226\156\147|r", r, g, b)
                        end
                    else
                        -- Check if missing or just in bags
                        local isMissing = true
                        local inBag = ns.FindItemInBags(itemID)
                        if inBag then isMissing = false end
                        if isMissing then
                            for sid = 1, ns.NUM_EQUIP_SLOTS do
                                if GetInventoryItemID("player", sid) == itemID then
                                    isMissing = false
                                    break
                                end
                            end
                        end

                        if isMissing then
                            GameTooltip:AddLine(info.display .. ": " .. (n or "item#" .. itemID) .. "  |cffff3333MISSING|r", 0.6, 0.2, 0.2)
                        elseif currentID > 0 then
                            local currentName = GetItemInfo(currentID) or "?"
                            GameTooltip:AddLine(info.display .. ": " .. (n or "?") .. "  |cffffaa00(wearing: " .. currentName .. ")|r", 1, 0.6, 0)
                        else
                            if n then
                                local r, g, b = GetItemQualityColor(q or 1)
                                GameTooltip:AddLine(info.display .. ": " .. n .. "  |cff80c0ff(in bags)|r", r, g, b)
                            end
                        end
                    end
                end
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to select  |  Double-click to equip", 0.5, 0.5, 0.5, true)
            GameTooltip:AddLine("Right-click to edit", 0.5, 0.5, 0.5, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        ns.setButtons[i] = btn
    end

    -- Bottom action bar (two rows: Equip/Update on top, Save/Delete on bottom)
    local bw = math.floor((PANEL_WIDTH - 22) / 2)

    local equipBtn = CreateFrame("Button", "GearFramePanelEquipBtn", panel, "UIPanelButtonTemplate")
    equipBtn:SetSize(bw, 22)
    equipBtn:SetPoint("BOTTOMLEFT", 6, 36)
    equipBtn:SetText("Equip")
    equipBtn:SetScript("OnClick", function()
        if selectedSetIndex then ns:EquipSet(selectedSetIndex) end
    end)
    ns.equipBtn = equipBtn

    local updateBtn = CreateFrame("Button", "GearFramePanelUpdateBtn", panel, "UIPanelButtonTemplate")
    updateBtn:SetSize(bw, 22)
    updateBtn:SetPoint("LEFT", equipBtn, "RIGHT", 2, 0)
    updateBtn:SetText("Update")
    updateBtn:SetScript("OnClick", function()
        if not selectedSetIndex then return end
        local set = ns.charDB.sets[selectedSetIndex]
        if not set then return end
        -- Re-save the set with current gear, keeping the same slots & icon
        local slots = {}
        for slotID in pairs(set.items) do
            slots[#slots + 1] = slotID
        end
        ns:SaveSet(set.name, slots, set.icon)
    end)
    ns.updateBtn = updateBtn

    local saveBtn = CreateFrame("Button", "GearFramePanelSaveBtn", panel, "UIPanelButtonTemplate")
    saveBtn:SetSize(bw, 22)
    saveBtn:SetPoint("BOTTOMLEFT", 6, 12)
    saveBtn:SetText("Save New")
    saveBtn:SetScript("OnClick", function()
        editingSetIndex = nil
        ns:ShowSaveDialog()
    end)

    local delBtn = CreateFrame("Button", "GearFramePanelDelBtn", panel, "UIPanelButtonTemplate")
    delBtn:SetSize(bw, 22)
    delBtn:SetPoint("LEFT", saveBtn, "RIGHT", 2, 0)
    delBtn:SetText("Delete")
    delBtn:SetScript("OnClick", function()
        if not selectedSetIndex then return end
        local set = ns.charDB.sets[selectedSetIndex]
        if set then StaticPopup_Show("GEARFRAME_CONFIRM_DELETE", set.name) end
    end)
    ns.deleteBtn = delBtn

    -- Static popup for delete confirmation
    StaticPopupDialogs["GEARFRAME_CONFIRM_DELETE"] = {
        text         = "Delete equipment set \"%s\"?",
        button1      = "Delete",
        button2      = "Cancel",
        OnAccept     = function()
            if selectedSetIndex then
                ns:DeleteSet(selectedSetIndex)
                selectedSetIndex = nil
                ns:RefreshSetList()
            end
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    self:RefreshSetList()
end

------------------------------------------------------------------------
-- Refresh set list rows
------------------------------------------------------------------------
function ns:RefreshSetList()
    if not ns.scrollFrame then return end
    local sets    = self.charDB.sets
    local numSets = #sets

    FauxScrollFrame_Update(ns.scrollFrame, numSets, NUM_VISIBLE_ROWS, SET_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(ns.scrollFrame)

    for i = 1, NUM_VISIBLE_ROWS do
        local btn   = ns.setButtons[i]
        local index = offset + i
        if index <= numSets then
            local set = sets[index]
            btn.setIndex = index
            btn.icon:SetTexture(set.icon)
            btn.nameText:SetText(set.name)
            btn.checkmark[ns:IsSetEquipped(set) and "Show" or "Hide"](btn.checkmark)
            btn.selTex[selectedSetIndex == index and "Show" or "Hide"](btn.selTex)

            -- Color name based on set status
            local status = ns:AuditSet(set)
            if status == "equipped" then
                btn.nameText:SetTextColor(0.2, 1, 0.2)       -- green: fully equipped
            elseif status == "missing" then
                btn.nameText:SetTextColor(1, 0.3, 0.3)       -- red: items missing
            else
                btn.nameText:SetTextColor(1, 1, 1)            -- white: ready / available
            end

            btn:Show()
        else
            btn.setIndex = nil
            btn:Hide()
        end
    end

    -- Button states
    local hasSel = selectedSetIndex and selectedSetIndex <= numSets
    if ns.equipBtn then
        ns.equipBtn[hasSel and "Enable" or "Disable"](ns.equipBtn)
        ns.updateBtn[hasSel and "Enable" or "Disable"](ns.updateBtn)
        ns.deleteBtn[hasSel and "Enable" or "Disable"](ns.deleteBtn)
    end
end

------------------------------------------------------------------------
-- SAVE DIALOG
------------------------------------------------------------------------
function ns:CreateSaveDialog()
    local dlg = CreateFrame("Frame", "GearFrameSaveDialog", UIParent, "BackdropTemplate")
    dlg:SetSize(SAVE_DLG_WIDTH, SAVE_DLG_HEIGHT)
    dlg:SetPoint("CENTER")
    dlg:SetBackdrop(DIALOG_BACKDROP)
    dlg:SetBackdropColor(0, 0, 0, 1)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetFrameLevel(100)
    dlg:EnableMouse(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
    dlg:SetClampedToScreen(true)
    dlg:Hide()
    ns.saveDialog = dlg

    -- Escape to close
    tinsert(UISpecialFrames, "GearFrameSaveDialog")

    -- Title
    ns.dlgTitle = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ns.dlgTitle:SetPoint("TOP", 0, -18)
    ns.dlgTitle:SetText("Save Equipment Set")

    -- Divider
    local div = dlg:CreateTexture(nil, "ARTWORK")
    div:SetSize(SAVE_DLG_WIDTH - 60, 1)
    div:SetPoint("TOP", ns.dlgTitle, "BOTTOM", 0, -6)
    div:SetColorTexture(0.6, 0.6, 0.6, 0.35)

    -- Name --
    local nl = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nl:SetPoint("TOPLEFT", 20, -50)
    nl:SetText("Set Name:")

    local nb = CreateFrame("EditBox", "GearFrameNameBox", dlg, "InputBoxTemplate")
    nb:SetSize(190, 22)
    nb:SetPoint("LEFT", nl, "RIGHT", 8, 0)
    nb:SetAutoFocus(false)
    nb:SetMaxLetters(24)
    nb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    nb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    ns.nameBox = nb

    -- Icon button --
    local il = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    il:SetPoint("TOPLEFT", 20, -82)
    il:SetText("Icon:")

    local ib = CreateFrame("Button", "GearFrameIconBtn", dlg)
    ib:SetSize(40, 40)
    ib:SetPoint("LEFT", il, "RIGHT", 8, 0)
    ib:SetNormalTexture(134400)  -- INV_Misc_QuestionMark fileID
    ib:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Clean 2px border around the icon button
    local B = 2
    local ibt = ib:CreateTexture(nil, "OVERLAY")
    ibt:SetHeight(B); ibt:SetPoint("TOPLEFT", -B, B); ibt:SetPoint("TOPRIGHT", B, B)
    ibt:SetColorTexture(0.6, 0.6, 0.6, 1)
    local ibb = ib:CreateTexture(nil, "OVERLAY")
    ibb:SetHeight(B); ibb:SetPoint("BOTTOMLEFT", -B, -B); ibb:SetPoint("BOTTOMRIGHT", B, -B)
    ibb:SetColorTexture(0.6, 0.6, 0.6, 1)
    local ibl = ib:CreateTexture(nil, "OVERLAY")
    ibl:SetWidth(B); ibl:SetPoint("TOPLEFT", -B, B); ibl:SetPoint("BOTTOMLEFT", -B, -B)
    ibl:SetColorTexture(0.6, 0.6, 0.6, 1)
    local ibr = ib:CreateTexture(nil, "OVERLAY")
    ibr:SetWidth(B); ibr:SetPoint("TOPRIGHT", B, B); ibr:SetPoint("BOTTOMRIGHT", B, -B)
    ibr:SetColorTexture(0.6, 0.6, 0.6, 1)

    ib:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ib:SetScript("OnClick", function() ns:ToggleIconPicker() end)
    ns.iconBtn = ib

    -- Slot checkboxes --
    local sl = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sl:SetPoint("TOPLEFT", 20, -132)
    sl:SetText("Include Slots:")

    ns.slotCheckboxes = {}
    local col1X, col2X = 24, 176
    local startY = -154
    local rowH   = 24

    for i, info in ipairs(ns.SLOT_INFO) do
        local cx, row
        if i <= 10 then
            cx  = col1X
            row = i - 1
        else
            cx  = col2X
            row = i - 11
        end

        local cb = CreateFrame("CheckButton", "GearFrameSlotCB" .. info.id, dlg, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", cx, startY + (-rowH * row))
        cb:SetChecked(info.default)
        cb.slotID = info.id

        -- Small slot icon beside checkbox
        local si = cb:CreateTexture(nil, "ARTWORK")
        si:SetSize(16, 16)
        si:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        si:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cb.slotIcon = si

        -- Label
        local txt = _G[cb:GetName() .. "Text"]
        if txt then
            txt:SetText("  " .. info.display)
            txt:SetPoint("LEFT", si, "RIGHT", 2, 0)
            txt:SetFontObject("GameFontHighlightSmall")
        end

        ns.slotCheckboxes[info.id] = cb
    end

    -- Save / Cancel buttons --
    local svBtn = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    svBtn:SetSize(100, 24)
    svBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", -6, 18)
    svBtn:SetText("Save")
    svBtn:SetScript("OnClick", function() ns:OnSaveDialogConfirm() end)

    local cnBtn = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    cnBtn:SetSize(100, 24)
    cnBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOM", 6, 18)
    cnBtn:SetText("Cancel")
    cnBtn:SetScript("OnClick", function() dlg:Hide() end)
end

------------------------------------------------------------------------
-- Show / populate save dialog
------------------------------------------------------------------------
function ns:ShowSaveDialog(editIndex)
    editingSetIndex = editIndex
    local dlg = ns.saveDialog

    if editIndex then
        local set = self.charDB.sets[editIndex]
        if not set then return end
        ns.dlgTitle:SetText("Edit Equipment Set")
        ns.nameBox:SetText(set.name)
        ns.iconBtn:GetNormalTexture():SetTexture(set.icon)
        selectedIcon = set.icon
        for id, cb in pairs(ns.slotCheckboxes) do
            cb:SetChecked(set.items[id] ~= nil)
        end
    else
        ns.dlgTitle:SetText("Save Equipment Set")
        ns.nameBox:SetText("")
        -- Auto-pick icon from first equipped slot
        local tex
        for _, info in ipairs(ns.SLOT_INFO) do
            if info.default then
                tex = GetInventoryItemTexture("player", info.id)
                if tex then break end
            end
        end
        tex = tex or 134400  -- INV_Misc_QuestionMark FileDataID
        ns.iconBtn:GetNormalTexture():SetTexture(tex)
        selectedIcon = tex
        for _, info in ipairs(ns.SLOT_INFO) do
            local cb = ns.slotCheckboxes[info.id]
            if cb then cb:SetChecked(info.default) end
        end
    end

    -- Update slot icons to show current gear
    for _, info in ipairs(ns.SLOT_INFO) do
        local cb = ns.slotCheckboxes[info.id]
        if cb and cb.slotIcon then
            local t = GetInventoryItemTexture("player", info.id)
            if not t then
                local _, fallback = GetInventorySlotInfo(info.name)
                t = fallback
            end
            cb.slotIcon:SetTexture(t)
        end
    end

    dlg:Show()
    ns.nameBox:SetFocus()
end

------------------------------------------------------------------------
-- Save dialog confirm
------------------------------------------------------------------------
function ns:OnSaveDialogConfirm()
    local name = ns.nameBox:GetText():trim()
    if name == "" then
        ns.Print("Please enter a set name.")
        return
    end

    -- Collect selected slots
    local slots = {}
    for id, cb in pairs(ns.slotCheckboxes) do
        if cb:GetChecked() then
            slots[#slots + 1] = id
        end
    end
    if #slots == 0 then
        ns.Print("Select at least one slot.")
        return
    end

    -- Name collision check
    if editingSetIndex then
        local old = self.charDB.sets[editingSetIndex]
        if old and old.name:lower() ~= name:lower() then
            for i, s in ipairs(self.charDB.sets) do
                if i ~= editingSetIndex and s.name:lower() == name:lower() then
                    ns.Print("A set named \"" .. s.name .. "\" already exists.")
                    return
                end
            end
        end
    else
        -- New set: check for duplicate name
        if self:GetSetByName(name) then
            ns.Print("A set named \"" .. name .. "\" already exists. Use a different name or edit the existing set.")
            return
        end
    end

    local icon = selectedIcon or 134400  -- INV_Misc_QuestionMark FileDataID
    self:SaveSet(name, slots, icon)
    ns.saveDialog:Hide()

    -- Select the saved set
    for i, s in ipairs(self.charDB.sets) do
        if s.name == name then selectedSetIndex = i; break end
    end
    ns:RefreshSetList()
end

------------------------------------------------------------------------
-- ICON PICKER — scrollable grid using the game's full macro icon list
------------------------------------------------------------------------
local PICKER_ROWS_VISIBLE = 6
local PICKER_SCROLL_H     = PICKER_ROWS_VISIBLE * (PICKER_ICON_SIZE + PICKER_PAD) + PICKER_PAD

function ns:CreateIconPicker()
    local pk = CreateFrame("Frame", "GearFrameIconPicker", ns.saveDialog, "BackdropTemplate")
    local totalW = PICKER_COLS * (PICKER_ICON_SIZE + PICKER_PAD) + PICKER_PAD + 28
    pk:SetSize(totalW, PICKER_SCROLL_H + 16)
    pk:SetPoint("TOPLEFT", ns.iconBtn, "BOTTOMLEFT", -4, -4)
    ns.Themes:SkinFrame(pk)
    pk:SetFrameLevel(ns.saveDialog:GetFrameLevel() + 10)
    pk:EnableMouse(true)
    pk:Hide()
    ns.iconPicker = pk
    ns.iconPickerBtns = {}

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", "GearFrameIconPickerScroll", pk, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -24, 4)
    sf:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PICKER_ICON_SIZE + PICKER_PAD, function()
            ns:RenderIconPickerPage()
        end)
    end)
    ns.iconPickerScroll = sf

    -- Content frame (icons parent)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(totalW - 28, PICKER_SCROLL_H)
    sf:SetScrollChild(content)
    ns.iconPickerContent = content
end

function ns:ToggleIconPicker()
    if ns.iconPicker:IsShown() then
        ns.iconPicker:Hide()
    else
        ns:PopulateIconPicker()
        ns.iconPicker:Show()
    end
end

function ns:PopulateIconPicker()
    local icons, seen = {}, {}

    local function Add(tex)
        if tex and not seen[tex] then
            seen[tex] = true
            icons[#icons + 1] = tex
        end
    end

    ----------------------------------------------------------------
    -- 1. Talent spec icons (ALL specs for the player's class)
    ----------------------------------------------------------------
    local numTabs = GetNumTalentTabs()
    for tab = 1, numTabs or 0 do
        local _, iconTex = GetTalentTabInfo(tab)
        Add(iconTex)
    end

    ----------------------------------------------------------------
    -- 2. All spellbook icons (every rank, every spell the class has)
    ----------------------------------------------------------------
    for bookType = 1, 2 do  -- 1 = player spells, 2 = pet spells
        local _, _, offset, numSpells = GetSpellTabInfo(1)
        -- Iterate all tabs
        local totalTabs = GetNumSpellTabs()
        for tab = 1, totalTabs or 0 do
            local _, tabTex, tabOffset, tabNumSpells = GetSpellTabInfo(tab)
            Add(tabTex)  -- the tab icon itself (class crest, etc.)
            for i = 1, tabNumSpells do
                local spellIndex = tabOffset + i
                local spellTex = GetSpellTexture(spellIndex, BOOKTYPE_SPELL or "spell")
                Add(spellTex)
            end
        end
        -- Only do pet spells if they exist
        if bookType == 2 then
            local petTabs = HasPetSpells and HasPetSpells()
            if not petTabs then break end
            local numPetSpells = petTabs
            if type(numPetSpells) == "number" then
                for i = 1, numPetSpells do
                    local spellTex = GetSpellTexture(i, BOOKTYPE_PET or "pet")
                    Add(spellTex)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- 3. Equipped items
    ----------------------------------------------------------------
    for _, info in ipairs(ns.SLOT_INFO) do
        Add(GetInventoryItemTexture("player", info.id))
    end

    ----------------------------------------------------------------
    -- 4. All bag items
    ----------------------------------------------------------------
    for bag = 0, 4 do
        local numSlots = ns.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            Add(ns.GetContainerItemTexture(bag, slot))
        end
    end

    ----------------------------------------------------------------
    -- 5. Done — no bulk macro icon dump (causes thousands of blanks)
    ----------------------------------------------------------------

    ns.allPickerIcons = icons

    local totalRows = math.ceil(#icons / PICKER_COLS)
    FauxScrollFrame_Update(ns.iconPickerScroll, totalRows, PICKER_ROWS_VISIBLE, PICKER_ICON_SIZE + PICKER_PAD)
    ns:RenderIconPickerPage()
end

function ns:RenderIconPickerPage()
    local icons = ns.allPickerIcons or {}
    local offset = FauxScrollFrame_GetOffset(ns.iconPickerScroll) or 0

    -- Hide all existing buttons
    for _, b in ipairs(ns.iconPickerBtns) do b:Hide() end

    local idx = 0
    for row = 0, PICKER_ROWS_VISIBLE - 1 do
        for col = 0, PICKER_COLS - 1 do
            idx = idx + 1
            local iconIndex = (offset + row) * PICKER_COLS + col + 1
            if iconIndex > #icons then return end

            local tex = icons[iconIndex]
            local btn = ns.iconPickerBtns[idx]
            if not btn then
                btn = CreateFrame("Button", nil, ns.iconPickerContent)
                btn:SetSize(PICKER_ICON_SIZE, PICKER_ICON_SIZE)
                btn.tex = btn:CreateTexture(nil, "ARTWORK")
                btn.tex:SetAllPoints()
                btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
                ns.iconPickerBtns[idx] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", PICKER_PAD + col * (PICKER_ICON_SIZE + PICKER_PAD),
                                    -(PICKER_PAD + row * (PICKER_ICON_SIZE + PICKER_PAD)))
            btn.tex:SetTexture(tex)
            btn.iconTexture = tex
            btn:SetScript("OnClick", function(self)
                selectedIcon = self.iconTexture
                ns.iconBtn:GetNormalTexture():SetTexture(self.iconTexture)
                ns.iconPicker:Hide()
            end)
            btn:Show()
        end
    end
end

------------------------------------------------------------------------
-- Toggle (slash-command helper)
------------------------------------------------------------------------
function ns:TogglePanel()
    if ns.setPanel then
        ns.setPanel:SetShown(not ns.setPanel:IsShown())
    end
end
