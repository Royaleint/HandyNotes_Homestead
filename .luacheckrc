std = "none"
max_line_length = false

-- Handler methods keep colon syntax for HandyNotes' dispatch even when
-- they don't touch self.
ignore = { "212/self" }

exclude_files = {
    "Libs/",
}

globals = {
    -- SavedVariables (created by WoW, read/written via AceDB)
    "HandyNotesHomesteadDB",
}

-- Deliberately minimal: only names the code actually references. Grow it
-- with the code, don't pre-seed it.
read_globals = {
    -- Lua builtins
    "next", "ipairs",

    -- Libraries
    "LibStub",
    "HandyNotes",

    -- WoW API
    "CreateFrame",
    "GameTooltip",
    "UnitFactionGroup",
    "UIParent",
    "UiMapPoint",
    "C_AddOns",
    "C_Item",
    "C_Map",
    "C_SuperTrack",
    "C_Texture",
}
