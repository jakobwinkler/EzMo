-- constants
local ADDON = "EzMo"
local MACRO_TAB = "macros"
local CONFIG_TAB = "config"
local SPELL_PATTERN = "%spell%"
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
    entry:SetHighlight()
    return entry
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
                function(b)
                    tinsert(self.db.char.managedSpells, spell.id)
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
        -- this is not fast, but for 20-ish spells it's good enough
        entry:SetCallback(
            "OnClick",
            function(b)
                tremove(self.db.char.managedSpells, idx)
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
    tableContainer:AddChild(applyButton)

    -- TODO: implement onclick logic
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

    -- for debugging:
    self:CreateMainFrame()
end
