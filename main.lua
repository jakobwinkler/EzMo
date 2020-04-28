-- constants
local ADDON = "EzMo"

-- UI tab identifiers
local MACRO_TAB = "macros"
local CONFIG_TAB = "config"

-- macro constants
local ACTIONBAR_MAX = 120
local MACRO_ID_MIN = 1 -- macros are 1-indexed
local MACRO_ID_CHAR = 121 -- character specific macros start at 121
local MACRO_ID_MAX = 138 -- last valid macro is 138
local MACRO_NUM_LOCAL = MACRO_ID_MAX - MACRO_ID_CHAR
local MACRO_NUM_GLOBAL =  MACRO_ID_CHAR - MACRO_ID_MIN
local MACRO_PREFIX = "[Ez]"

local SPELL_PATTERN = "{spell}" -- pattern to replace with spell name in macros
local DEFAULT_MACRO = "#showtooltip\n/use [@mouseover,help,nodead][help,nodead][@player] " .. SPELL_PATTERN
local DB_DEFAULTS = {
    char = {
        macroText = DEFAULT_MACRO,
        managedSpells = {}
    }
}

-- ACE setup
local EzMo = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0")

--
-- Helpers
--

function EzMo:GetSpellInfoById(spellId)
    local name, _, icon, _, _, _, id = GetSpellInfo(spellId)
    return {name = name, icon = icon, id = id}
end

function EzMo:GetMacroName(spell)
    return MACRO_PREFIX .. spell.name
end

function EzMo:GetAvailableSpells()
    local spells = {}

    -- skipping idx 1 (general/racials)
    for i = 2, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = 1, numSpells do
            local _, spellId = GetSpellBookItemInfo(offset + j, "spell")
            local spell = self:GetSpellInfoById(spellId)

            -- add to list if active
            if (spell and spell.id and IsPlayerSpell(spell.id) and not IsPassiveSpell(spell.name)) then
                spells[spell.name] = spell
            end
        end
    end

    return spells
end

function EzMo:CreateSpellEntry(spell)
    local entry = AceGUI:Create("InteractiveLabel")
    entry:SetText(spell.name)
    entry:SetImageSize(24, 24)
    entry:SetImage(spell.icon)
    entry:SetFullWidth(true)

    -- this, technically, is not nice as it bypasses the AceGUI API
    entry.highlight:SetColorTexture(0.8, 0.8, 0.8, 0.5)

    return entry
end

function EzMo:DoesMacroExist(name)
    local name, _, _, _ = GetMacroInfo(name)

    if name then
        return true
    else
        return false
    end
end

function EzMo:GetMacroBody(spell)
    return gsub(self.db.char.macroText, SPELL_PATTERN, spell.name)
end

function EzMo:ManageSpell(spell)
    -- persist spell as managed
    tinsert(self.db.char.managedSpells, spell.id)

    local macroName = self:GetMacroName(spell)
    local macroIndex = GetMacroIndexByName(macroName)

    -- create macro if not exists
    if macroIndex == 0 then
        local globalMacros, localMacros = GetNumMacros()
        local macroBody = self:GetMacroBody(spell)
        if localMacros < MACRO_NUM_LOCAL then
            macroIndex = CreateMacro(macroName, spell.icon, macroBody, 1)
        elseif globalMacros < MACRO_NUM_GLOBAL then
            self:Print("Per-character macro limit reached. Creating global macro.")
            macroIndex = CreateMacro(macroName, spell.icon, macroBody, nil)
        else
            self:Print("Global macro limit reached. Could not create any more macros.")
        end
    end

    -- replace spell on hotkeys with macro
    for key = 1, ACTIONBAR_MAX do
        local atype, id, subtype, _ = GetActionInfo(key)
        if atype == "spell" and subtype == "spell" then
            if id == spell.id then
                PickupMacro(macroIndex)
                PlaceAction(key)
                ClearCursor()
            end
        end
    end
end

function EzMo:UnmanageSpell(idx, spell)
    -- remove spell from persistent db
    tremove(self.db.char.managedSpells, idx)

    -- replace macro on hotkeys with spell
    local macroName = self:GetMacroName(spell)
    local macroIndex = GetMacroIndexByName(macroName)

    for key = 1, ACTIONBAR_MAX do
        local atype, id, _, _ = GetActionInfo(key)
        if atype == "macro" then
            local name, _, _, _ = GetMacroInfo(id)
            if name == macroName then
                PickupSpell(spell.id)
                PlaceAction(key)
                ClearCursor()
            end
        end
    end

    -- delete macro if exists
    DeleteMacro(macroName)
end

--
-- UI
--
function EzMo:CreateMacroHeader()
    local availableLabel = AceGUI:Create("Label")
    availableLabel:SetText("Available spells:")
    availableLabel:SetRelativeWidth(0.5)
    availableLabel:SetFontObject(Game15Font)

    local managedLabel = AceGUI:Create("Label")
    managedLabel:SetText("Managed spells:")
    managedLabel:SetRelativeWidth(0.5)
    managedLabel:SetFontObject(Game15Font)

    return availableLabel, managedLabel
end

function EzMo:CreateAvailableSpellContainer()
    local availableContainer = AceGUI:Create("InlineGroup")
    availableContainer:SetHeight(260)
    availableContainer:SetAutoAdjustHeight(false)
    availableContainer:SetLayout("Fill")

    local availableScroll = AceGUI:Create("ScrollFrame")
    availableScroll:SetFullWidth(true)
    availableScroll:SetLayout("List")

    local available = self:GetAvailableSpells()
    for name, spell in pairs(available) do
        -- this is not fast, but for 20-ish spells it's good enough
        if not tContains(self.db.char.managedSpells, spell.id) then
            local entry = self:CreateSpellEntry(spell)
            entry:SetCallback(
                "OnClick",
                function()
                    self:ManageSpell(spell)
                    self.tabGroup:SelectTab(MACRO_TAB)
                end
            )
            availableScroll:AddChild(entry)
        end
    end

    availableContainer:AddChild(availableScroll)
    return availableContainer
end

function EzMo:CreateManagedSpellContainer()
    local managedContainer = AceGUI:Create("InlineGroup")
    managedContainer:SetFullHeight(true)
    managedContainer:SetLayout("Fill")

    local managedScroll = AceGUI:Create("ScrollFrame")
    managedScroll:SetFullWidth(true)
    managedScroll:SetLayout("List")

    for idx, id in pairs(self.db.char.managedSpells) do
        local spell = self:GetSpellInfoById(id)
        local entry = self:CreateSpellEntry(spell)
        entry:SetCallback(
            "OnClick",
            function()
                self:UnmanageSpell(idx, spell)
                self.tabGroup:SelectTab(MACRO_TAB)
            end
        )
        managedScroll:AddChild(entry)
    end

    managedContainer:AddChild(managedScroll)
    return managedContainer
end

function EzMo:ShowMacroTab(container)
    -- base container
    local tableContainer = AceGUI:Create("SimpleGroup")
    tableContainer:SetFullWidth(true)
    tableContainer:SetFullHeight(true)
    tableContainer:SetUserData("table", {columns = {5, 5}})
    tableContainer:SetLayout("Table")

    -- headers
    tableContainer:AddChildren(self:CreateMacroHeader())

    -- spell lists
    tableContainer:AddChild(self:CreateAvailableSpellContainer())
    tableContainer:AddChild(self:CreateManagedSpellContainer())

    -- apply changes
    local applyButton = AceGUI:Create("Button")
    applyButton:SetText("Update Macros")
    applyButton:SetRelativeWidth(0.2)
    applyButton:SetCallback(
        "OnClick",
        function()
            self:UpdateMacros()
        end
    )
    tableContainer:AddChild(applyButton)
    container:AddChild(tableContainer)
end

function EzMo:ShowConfigTab(container)
    -- change macro text
    local macroEditBox = AceGUI:Create("MultiLineEditBox")
    macroEditBox:SetLabel("Macro text:")
    macroEditBox:SetText(self.db.char.macroText)
    macroEditBox:SetRelativeWidth(0.8)
    macroEditBox:SetMaxLetters(200) -- max macro length is 255, give us some slack for text replacement
    macroEditBox:SetNumLines(4)
    macroEditBox:SetCallback(
        "OnEnterPressed",
        function(f)
            self.db.char.macroText = f:GetText()
        end
    )
    container:AddChild(macroEditBox)

    -- allow resetting config (mostly for debug)
    local warnHeading = AceGUI:Create("Heading")
    warnHeading:SetText("Danger Zone")
    warnHeading:SetRelativeWidth(1)
    container:AddChild(warnHeading)

    local resetGroup = AceGUI:Create("SimpleGroup")
    resetGroup:SetRelativeWidth(0.8)

    local resetButton = AceGUI:Create("Button")
    resetButton:SetText("Reset configuration")
    resetButton:SetRelativeWidth(0.3)
    resetButton:SetCallback(
        "OnClick",
        function()
            self.db:ResetDB()
            self.tabGroup:SelectTab(CONFIG_TAB)
        end
    )
    resetGroup:AddChild(resetButton)

    local resetLabel = AceGUI:Create("Label")
    resetLabel:SetText("Warning: this will reset the macro text and remove all generated macros!")
    resetLabel:SetRelativeWidth(0.8)
    resetGroup:AddChild(resetLabel)

    container:AddChild(resetGroup)
end

function EzMo:OnTabGroupSelected(container, event, tab)
    container:ReleaseChildren()
    if tab == MACRO_TAB then
        self:ShowMacroTab(container)
    elseif tab == CONFIG_TAB then
        self:ShowConfigTab(container)
    end
end

function EzMo:CreateMainFrame()
    -- boilerplate
    local mainFrame = AceGUI:Create("Window")
    mainFrame:SetTitle("EzMo Mouseover Macro Setup")
    mainFrame:SetWidth(700)
    mainFrame:SetHeight(400)
    mainFrame:EnableResize(false)
    mainFrame:SetStatusText("EzMo " .. self.version)
    mainFrame:SetCallback(
        "OnClose",
        function(f)
            f:Release()
        end
    )
    mainFrame:SetLayout("Fill") -- the only child is the tab widget

    -- setup tabs
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetTabs({{text = "Macro Setup", value = MACRO_TAB}, {text = "Configuration", value = CONFIG_TAB}})
    tabGroup:SetCallback(
        "OnGroupSelected",
        function(c, e, t)
            self:OnTabGroupSelected(c, e, t)
        end
    )
    tabGroup:SelectTab(MACRO_TAB)
    self.tabGroup = tabGroup
    mainFrame:AddChild(tabGroup)
end

function EzMo:OnInitialize()
    self.version = GetAddOnMetadata(ADDON, "Version")
    self:Print("Loaded version " .. self.version .. ". Thanks for using EzMo :3")
    self:RegisterChatCommand("ezmo", "CreateMainFrame")

    -- load saved variables
    self.db = LibStub("AceDB-3.0"):New("EzMoDB", DB_DEFAULTS)

    -- for faster debugging:
    -- self:CreateMainFrame()
end
