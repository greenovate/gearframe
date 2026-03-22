------------------------------------------------------------------------
-- GearFrame — Settings
-- In-game settings panel accessed via /gf settings or gear icon
------------------------------------------------------------------------
local _, ns = ...

local SETTINGS_WIDTH  = 320
local SETTINGS_HEIGHT = 300

------------------------------------------------------------------------
-- Public init (called from Core.lua after DB is ready)
------------------------------------------------------------------------
function ns:InitSettings()
    self:CreateSettingsPanel()
end

------------------------------------------------------------------------
-- Settings Panel
------------------------------------------------------------------------
function ns:CreateSettingsPanel()
    local panel = CreateFrame("Frame", "GearFrameSettings", UIParent, "BackdropTemplate")
    panel:SetSize(SETTINGS_WIDTH, SETTINGS_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(200)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:Hide()
    ns.settingsPanel = panel

    tinsert(UISpecialFrames, "GearFrameSettings")

    -- Initial skin (will be re-applied when theme changes)
    ns.Themes:SkinFrame(panel, true)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("GearFrame Settings")
    ns.Themes:SetTitleStyle(title)

    -- Author
    local author = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    author:SetPoint("TOP", title, "BOTTOM", 0, -2)
    author:SetText("by Evild")
    author:SetTextColor(0.6, 0.6, 0.6)

    -- Divider
    local div = panel:CreateTexture(nil, "ARTWORK")
    div:SetSize(SETTINGS_WIDTH - 40, 1)
    div:SetPoint("TOP", author, "BOTTOM", 0, -6)
    div:SetColorTexture(0.4, 0.4, 0.4, 0.5)

    -- Theme label
    local tl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tl:SetPoint("TOPLEFT", 20, -56)
    tl:SetText("Theme:")

    -- Theme dropdown
    local dd = CreateFrame("Frame", "GearFrameThemeDropdown", panel, "UIDropDownMenuTemplate")
    dd:SetPoint("LEFT", tl, "RIGHT", -8, -3)
    ns.themeDropdown = dd

    local themeList = ns.Themes:GetList()

    local function GetCurrentLabel()
        local setting = ns.db.theme or "auto"
        for _, item in ipairs(themeList) do
            if item.key == setting then return item.label end
        end
        return "Auto-detect"
    end

    UIDropDownMenu_SetWidth(dd, 180)
    UIDropDownMenu_SetText(dd, GetCurrentLabel())

    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, item in ipairs(themeList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = item.label
            info.value    = item.key
            info.checked  = (ns.db.theme or "auto") == item.key
            info.func     = function(self)
                ns.db.theme = self.value
                UIDropDownMenu_SetText(dd, self:GetText())
                CloseDropDownMenus()
                ns.Themes:ApplyAll()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- ElvUI status
    local elvStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    elvStatus:SetPoint("TOPLEFT", 20, -100)
    if ns.Themes:IsElvUILoaded() then
        elvStatus:SetText("ElvUI: |cff00ff00Detected|r")
    else
        elvStatus:SetText("ElvUI: |cffff4444Not found|r — Auto will use Dark theme")
    end

    -- Active theme display
    local activeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activeLabel:SetPoint("TOPLEFT", 20, -118)
    local _, activeKey = ns.Themes:GetActive()
    local activeName = "Unknown"
    for _, item in ipairs(themeList) do
        if item.key == activeKey then activeName = item.label; break end
    end
    activeLabel:SetText("Active theme: |cff80c0ff" .. activeName .. "|r")
    ns.activeThemeLabel = activeLabel

    -- Divider 2
    local div2 = panel:CreateTexture(nil, "ARTWORK")
    div2:SetSize(SETTINGS_WIDTH - 40, 1)
    div2:SetPoint("TOPLEFT", 20, -134)
    div2:SetColorTexture(0.4, 0.4, 0.4, 0.5)

    -- Hide BoE checkbox
    local boeCheck = CreateFrame("CheckButton", "GearFrameBoECheck", panel, "UICheckButtonTemplate")
    boeCheck:SetSize(22, 22)
    boeCheck:SetPoint("TOPLEFT", 18, -142)
    boeCheck:SetChecked(ns.db.hideBoE or false)
    boeCheck:SetScript("OnClick", function(self)
        ns.db.hideBoE = self:GetChecked() and true or false
        if ns.db.hideBoE then
            ns.Print("BoE items will be hidden from flyout slots.")
        else
            ns.Print("BoE items will be shown in flyout slots.")
        end
    end)
    local boeText = _G[boeCheck:GetName() .. "Text"]
    if boeText then
        boeText:SetText("Hide Bind-on-Equip items from slot flyouts")
        boeText:SetFontObject("GameFontHighlightSmall")
    end

    -- Item protection checkbox
    local protCheck = CreateFrame("CheckButton", "GearFrameProtCheck", panel, "UICheckButtonTemplate")
    protCheck:SetSize(22, 22)
    protCheck:SetPoint("TOPLEFT", 18, -168)
    protCheck:SetChecked(ns.db.protectSetItems ~= false)  -- default ON
    protCheck:SetScript("OnClick", function(self)
        ns.db.protectSetItems = self:GetChecked() and true or false
        if ns.db.protectSetItems then
            ns.Print("Set item protection enabled (sell/delete/bank warnings).")
        else
            ns.Print("Set item protection disabled.")
        end
    end)
    local protText = _G[protCheck:GetName() .. "Text"]
    if protText then
        protText:SetText("Warn before selling/deleting/banking set items")
        protText:SetFontObject("GameFontHighlightSmall")
    end

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 24)
    closeBtn:SetPoint("BOTTOM", 0, 16)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    ns.Themes:SkinButton(closeBtn)

    -- Gear icon on the set panel (added after set panel exists)
    C_Timer.After(0, function()
        if ns.setPanel then
            local gear = CreateFrame("Button", "GearFrameGearBtn", ns.setPanel)
            gear:SetSize(16, 16)
            gear:SetPoint("TOPRIGHT", -6, -8)
            local gt = gear:CreateTexture(nil, "ARTWORK")
            gt:SetAllPoints()
            gt:SetTexture("Interface\\Scenarios\\ScenarioIcon-Interact")
            gt:SetDesaturated(false)
            gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            gear:SetScript("OnClick", function() ns:ToggleSettings() end)
            gear:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("GearFrame Settings", 1, 1, 1)
                GameTooltip:Show()
            end)
            gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end)
end

------------------------------------------------------------------------
-- Toggle
------------------------------------------------------------------------
function ns:ToggleSettings()
    if ns.settingsPanel then
        ns.settingsPanel:SetShown(not ns.settingsPanel:IsShown())
    end
end
