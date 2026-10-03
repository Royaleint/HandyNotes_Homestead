-- English strings. Other locale files override these keys for their client.
local _, ns = ...

local L = {}
ns.L = L

L["Vendors: %d"] = "Vendors: %d"
L["Click to view zone"] = "Click to view zone"
L["Click to view continent"] = "Click to view continent"
L["(other cost)"] = "(other cost)"
L["Items unknown"] = "Items unknown"
L["Housing decor vendor locations"] = "Housing decor vendor locations"
L["Housing decor vendor pins powered by Homestead's vendor data."] = "Housing decor vendor pins powered by Homestead's vendor data."
L["Icon Scale"] = "Icon Scale"
L["Size of the vendor pins."] = "Size of the vendor pins."
L["Transparency of the vendor pins."] = "Transparency of the vendor pins."

-- The client's own text; the literal is only a fallback.
-- Keep each on one line in exactly this form: the locale check parses it.
L["Search"] = SEARCH or "Search"
L["No results found"] = QUEST_LOG_NO_RESULTS or "No results found"
L["Items"] = ITEMS or "Items"
L[":"] = HEADER_COLON or ":"
L["Unknown"] = UNKNOWN or "Unknown"
L["Opacity"] = OPACITY or "Opacity"
