std = "none"
max_line_length = false

-- Handler methods keep colon syntax for HandyNotes' dispatch even when
-- they don't touch self.
ignore = { "212/self" }

exclude_files = {
    "Libs/",
    -- luacheck reads only this root config, so "Libs/" above does NOT cover
    -- a worktree's own nested Libs/ (e.g. .worktrees/*/Libs/) — this entry
    -- is what keeps local runs from re-linting stale worktree checkouts.
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
    "WorldMapFrame",
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
