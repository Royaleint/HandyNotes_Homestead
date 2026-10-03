std = "none"
max_line_length = false

-- Handler methods keep colon syntax for HandyNotes' dispatch even when
-- they don't touch self.
ignore = { "212/self" }

exclude_files = {
    "Libs/",
    -- Local worktree checkouts: Libs/ above matches only the root Libs/, not a worktree's nested Libs/.
    ".worktrees/",
}

globals = {
    -- SavedVariables (created by WoW, read/written via AceDB)
    "HandyNotesHomesteadDB",
}

-- Deliberately minimal: only names the code actually references. Grow it
-- with the code, don't pre-seed it.
read_globals = {
    -- Lua builtins
    "next", "ipairs", "math", "table", "type", "tostring", "pcall",

    -- Libraries
    "LibStub",
    "HandyNotes",

    -- WoW API
    "CreateFrame",
    "Enum",
    "GameTooltip",
    "Item",
    "UnitFactionGroup",
    "UIParent",
    "UiMapPoint",
    "C_AddOns",
    "C_AreaPoiInfo",
    "C_CurrencyInfo",
    "C_Item",
    "C_Map",
    "C_SuperTrack",
    "C_Texture",
    "C_Timer",
    "WorldMapFrame",
    "InCombatLockdown",
    "UIErrorsFrame",
    "ERR_NOT_IN_COMBAT",
    "hooksecurefunc",
    "CreateFromMixins",
    "MapCanvasDataProviderMixin",
    "GetProfessions",
    "GetProfessionInfo",
    "BaseScrollBoxEvents",
    "ScrollBoxConstants",
    "SearchBoxTemplate_OnTextChanged",
    "SearchBoxTemplate_OnEditFocusLost",
}
