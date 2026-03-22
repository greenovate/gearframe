------------------------------------------------------------------------
-- GearFrame — Themes
-- Provides skinning for all addon frames. Auto-detects ElvUI.
-- Three themes: "elvui" (uses ElvUI API), "dark" (flat modern),
-- "classic" (default Blizzard textures).
------------------------------------------------------------------------
local _, ns = ...

ns.Themes = {}

------------------------------------------------------------------------
-- Theme definitions
------------------------------------------------------------------------
local themes = {}

-- DARK: Clean flat look — dark bg, thin 1px borders, no chunky textures
themes.dark = {
    name        = "Dark Modern",
    bg          = { 0.06, 0.06, 0.06, 0.95 },
    border      = { 0.20, 0.20, 0.20, 1 },
    borderAccent = { 0.35, 0.35, 0.35, 1 },
    highlight   = { 1, 1, 1, 0.06 },
    selected    = { 0.18, 0.45, 0.75, 0.45 },
    titleColor  = { 0.90, 0.80, 0.50 },
    textColor   = { 0.85, 0.85, 0.85 },
    btnBg       = { 0.12, 0.12, 0.12, 0.9 },
    btnBorder   = { 0.30, 0.30, 0.30, 1 },
    btnText     = { 0.90, 0.90, 0.90 },
    editBg      = { 0.08, 0.08, 0.08, 0.9 },
    editBorder  = { 0.30, 0.30, 0.30, 1 },
    edgeSize    = 1,
    edgeFile    = nil,   -- use pixel border
    font        = "Fonts\\FRIZQT__.TTF",
}

-- CLASSIC: Stock Blizzard look
themes.classic = {
    name        = "Classic WoW",
    bg          = { 0.08, 0.08, 0.08, 0.92 },
    border      = { 0.50, 0.50, 0.50, 1 },
    borderAccent = { 0.60, 0.60, 0.60, 1 },
    highlight   = { 1, 1, 1, 0.12 },
    selected    = { 0.25, 0.50, 0.80, 0.35 },
    titleColor  = { 1, 0.82, 0 },
    textColor   = { 1, 1, 1 },
    btnBg       = nil,  -- use UIPanelButtonTemplate default
    btnBorder   = nil,
    btnText     = { 1, 0.82, 0 },
    editBg      = nil,
    editBorder  = nil,
    edgeSize    = 16,
    edgeFile    = "Interface\\Tooltips\\UI-Tooltip-Border",
    font        = nil,  -- use default
}

-- ELVUI: will skin via ElvUI's API at runtime — fallback to dark if ElvUI absent
themes.elvui = {
    name        = "ElvUI",
    -- visual vals are same as dark; actual skinning done via ElvUI:SetTemplate()
    bg          = { 0.06, 0.06, 0.06, 0.95 },
    border      = { 0.20, 0.20, 0.20, 1 },
    borderAccent = { 0.35, 0.35, 0.35, 1 },
    highlight   = { 1, 1, 1, 0.06 },
    selected    = { 0.18, 0.45, 0.75, 0.45 },
    titleColor  = { 0.90, 0.80, 0.50 },
    textColor   = { 0.85, 0.85, 0.85 },
    btnBg       = { 0.12, 0.12, 0.12, 0.9 },
    btnBorder   = { 0.30, 0.30, 0.30, 1 },
    btnText     = { 0.90, 0.90, 0.90 },
    editBg      = { 0.08, 0.08, 0.08, 0.9 },
    editBorder  = { 0.30, 0.30, 0.30, 1 },
    edgeSize    = 1,
    edgeFile    = nil,
    font        = nil,  -- ElvUI overrides fonts globally
}

------------------------------------------------------------------------
-- ElvUI detection
------------------------------------------------------------------------
function ns.Themes:IsElvUILoaded()
    return ElvUI and ElvUI[1] and true or false
end

function ns.Themes:GetElvUI()
    if self:IsElvUILoaded() then
        return ElvUI[1]
    end
    return nil
end

------------------------------------------------------------------------
-- Get active theme table
------------------------------------------------------------------------
function ns.Themes:GetActive()
    local setting = ns.db and ns.db.theme or "auto"

    if setting == "auto" then
        if self:IsElvUILoaded() then
            return themes.elvui, "elvui"
        else
            return themes.dark, "dark"
        end
    end

    return themes[setting] or themes.dark, setting
end

function ns.Themes:GetList()
    return {
        { key = "auto",    label = "Auto-detect (ElvUI if present, otherwise Dark)" },
        { key = "elvui",   label = "ElvUI" },
        { key = "dark",    label = "Dark Modern" },
        { key = "classic", label = "Classic WoW" },
    }
end

------------------------------------------------------------------------
-- Pixel border backdrop creator (for dark/elvui themes)
------------------------------------------------------------------------
local PIXEL_BACKDROP = {
    bgFile   = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
    tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function MakeBackdrop(t)
    if t.edgeFile then
        return {
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = t.edgeFile,
            tile = true, tileSize = 16, edgeSize = t.edgeSize,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        }
    else
        return PIXEL_BACKDROP
    end
end

------------------------------------------------------------------------
-- Apply theme to a BackdropTemplate frame
------------------------------------------------------------------------
function ns.Themes:SkinFrame(frame, accent)
    if not frame then return end
    local t, key = self:GetActive()

    -- ElvUI native skinning
    if key == "elvui" and self:IsElvUILoaded() then
        local E = self:GetElvUI()
        if frame.SetTemplate then
            frame:SetTemplate("Transparent")
            return
        end
    end

    -- Manual skinning
    local bd = MakeBackdrop(t)
    frame:SetBackdrop(bd)
    frame:SetBackdropColor(unpack(t.bg))
    if accent then
        frame:SetBackdropBorderColor(unpack(t.borderAccent))
    else
        frame:SetBackdropBorderColor(unpack(t.border))
    end
end

------------------------------------------------------------------------
-- Apply theme to a standard WoW button (UIPanelButtonTemplate)
------------------------------------------------------------------------
function ns.Themes:SkinButton(btn)
    if not btn then return end
    local t, key = self:GetActive()

    if key == "elvui" and self:IsElvUILoaded() then
        local S = ElvUI[1]:GetModule("Skins", true)
        if S and S.HandleButton then
            S:HandleButton(btn)
            return
        end
    end

    if key == "classic" then return end  -- leave Blizzard skin

    -- Dark theme: strip default textures, apply flat style
    btn:SetNormalTexture("")
    btn:SetHighlightTexture("")
    btn:SetPushedTexture("")
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end

    -- Give it a backdrop
    if not btn.tcSkinned then
        Mixin(btn, BackdropTemplateMixin)
        btn:HookScript("OnSizeChanged", btn.OnBackdropSizeChanged)
        btn.tcSkinned = true
    end

    btn:SetBackdrop(PIXEL_BACKDROP)
    btn:SetBackdropColor(unpack(t.btnBg))
    btn:SetBackdropBorderColor(unpack(t.btnBorder))

    -- Text color
    local fs = btn:GetFontString()
    if fs then
        fs:SetTextColor(unpack(t.btnText))
    end

    -- Hover/press feedback (guard against stacking)
    if not btn.tcHoverHooked then
        btn:HookScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.50, 0.70, 1.00, 1)
            end
        end)
        btn:HookScript("OnLeave", function(self)
            if self.SetBackdropBorderColor and t.btnBorder then
                self:SetBackdropBorderColor(unpack(t.btnBorder))
            end
        end)
        btn.tcHoverHooked = true
    end
end

------------------------------------------------------------------------
-- Apply theme to an EditBox
------------------------------------------------------------------------
function ns.Themes:SkinEditBox(eb)
    if not eb then return end
    local t, key = self:GetActive()

    if key == "elvui" and self:IsElvUILoaded() then
        local S = ElvUI[1]:GetModule("Skins", true)
        if S and S.HandleEditBox then
            S:HandleEditBox(eb)
            return
        end
    end

    if key == "classic" then return end

    -- Strip default textures
    local regions = { eb:GetRegions() }
    for _, r in ipairs(regions) do
        if r:IsObjectType("Texture") then
            local tex = r:GetTexture()
            if tex and type(tex) == "string" and tex:find("UI%-EditBox") then
                r:Hide()
            end
        end
    end

    if not eb.tcSkinned then
        Mixin(eb, BackdropTemplateMixin)
        eb:HookScript("OnSizeChanged", eb.OnBackdropSizeChanged)
        eb.tcSkinned = true
    end

    eb:SetBackdrop(PIXEL_BACKDROP)
    eb:SetBackdropColor(unpack(t.editBg))
    eb:SetBackdropBorderColor(unpack(t.editBorder))
    eb:SetTextInsets(4, 4, 2, 2)
end

------------------------------------------------------------------------
-- Apply theme to a CheckButton
------------------------------------------------------------------------
function ns.Themes:SkinCheckbox(cb)
    if not cb then return end
    local t, key = self:GetActive()

    if key == "elvui" and self:IsElvUILoaded() then
        local S = ElvUI[1]:GetModule("Skins", true)
        if S and S.HandleCheckBox then
            S:HandleCheckBox(cb)
            return
        end
    end

    -- Classic: leave as-is; Dark: no custom checkbox skinning (too invasive)
end

------------------------------------------------------------------------
-- Skin a flyout item button (icon + quality border)
------------------------------------------------------------------------
function ns.Themes:SkinFlyoutButton(btn)
    if not btn then return end
    local t, key = self:GetActive()

    -- Already has BackdropTemplate from creation
    local bd = PIXEL_BACKDROP
    if key == "classic" then
        bd = {
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        }
    end
    btn:SetBackdrop(bd)
    btn:SetBackdropBorderColor(unpack(t.border))
end

------------------------------------------------------------------------
-- Create a themed font string
------------------------------------------------------------------------
function ns.Themes:SetTitleStyle(fs)
    if not fs then return end
    local t = self:GetActive()
    fs:SetTextColor(unpack(t.titleColor))
end

------------------------------------------------------------------------
-- Apply full theme refresh to all existing addon frames
------------------------------------------------------------------------
function ns.Themes:ApplyAll()
    local t, key = self:GetActive()

    -- Set panel
    if ns.setPanel then
        self:SkinFrame(ns.setPanel)
        -- Re-color row elements
        if ns.setButtons then
            for _, btn in ipairs(ns.setButtons) do
                if btn.selTex then
                    btn.selTex:SetColorTexture(t.selected[1], t.selected[2], t.selected[3], t.selected[4])
                end
            end
        end
    end

    -- Save dialog
    if ns.saveDialog then self:SkinFrame(ns.saveDialog, true) end

    -- Icon picker
    if ns.iconPicker then self:SkinFrame(ns.iconPicker) end

    -- Buttons
    if ns.equipBtn   then self:SkinButton(ns.equipBtn) end
    if ns.updateBtn  then self:SkinButton(ns.updateBtn) end
    if ns.deleteBtn  then self:SkinButton(ns.deleteBtn) end

    -- Scan save dialog for buttons
    if ns.saveDialog then
        for _, child in ipairs({ ns.saveDialog:GetChildren() }) do
            if child:IsObjectType("Button") and child:GetText() then
                self:SkinButton(child)
            end
        end
    end

    -- Edit box
    if ns.nameBox then self:SkinEditBox(ns.nameBox) end

    -- Checkboxes
    if ns.slotCheckboxes then
        for _, cb in pairs(ns.slotCheckboxes) do
            self:SkinCheckbox(cb)
        end
    end

    -- Settings panel buttons
    if ns.settingsPanel then self:SkinFrame(ns.settingsPanel) end

    -- Update active theme label in settings
    if ns.activeThemeLabel then
        ns.activeThemeLabel:SetText("Active theme: |cff80c0ff" .. t.name .. "|r")
    end

    ns.Print("Theme applied: " .. t.name)
end
