-- luacheck: push ignore 111 112 113

--[[
    Schema and provenance check for the committed Data.lua. It validates the
    shape, internal consistency, and versioned source stamp, so a hand-edited,
    malformed, or unstamped file fails without needing its source data. It
    cannot detect a well-formed but stale Data.lua; that requires comparison
    with the current source data.

    Usage: lua5.1 tests/data_integrity.lua [path-to-Data.lua]
    Exit code 0 and "RESULT: OK" on success; exit code 1 and a problem list
    on failure. Every check collects into the same list rather than stopping
    at the first failure, so one run reports everything wrong at once.
]]

local dataPath = arg[1] or "Data.lua"

local problems = {}
local function fail(format, ...)
    problems[#problems + 1] = string.format(format, ...)
end

local function isPositiveInt(n)
    return type(n) == "number" and n > 0 and n == math.floor(n)
end

-- 1. Header stamp: must name a real Homestead version. A missing or working-tree
-- stamp is unverifiable. Match it only inside the header block so a later lookalike cannot count.
do
    local file = io.open(dataPath, "r")
    if not file then
        fail("could not open %s", dataPath)
    else
        local text = file:read("*a")
        file:close()
        local _, headerEnd = text:find("]]", 1, true)
        local header = headerEnd and text:sub(1, headerEnd) or text
        if not header:match("Source:%s*Homestead%s+v%d+%.%d+%.%d+") then
            fail("Data.lua is missing a versioned source stamp")
        end
    end
end

local ns = {}
assert(loadfile(dataPath))("HandyNotes_Homestead", ns)

local VENDOR_FIELDS = { name = true, zone = true, subzone = true, areaID = true, faction = true, factionByMap = true, items = true }
local ITEM_FIELDS = { id = true, price = true, currencies = true, items = true, otherCost = true }
local COST_ENTRY_FIELDS = { id = true, amount = true }

local function checkCostList(vendorLabel, itemLabel, listName, list)
    if list == nil then return end
    if type(list) ~= "table" then
        fail("%s item %s: %s is not a table", vendorLabel, itemLabel, listName)
        return
    end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count == 0 then
        fail("%s item %s: %s is present but empty (should be omitted)", vendorLabel, itemLabel, listName)
    end
    for index = 1, count do
        local entry = list[index]
        if type(entry) ~= "table" then
            fail("%s item %s: %s[%d] is not a table", vendorLabel, itemLabel, listName, index)
        else
            if not isPositiveInt(entry.id) then
                fail("%s item %s: %s[%d].id is not a positive integer (%s)",
                    vendorLabel, itemLabel, listName, index, tostring(entry.id))
            end
            if not isPositiveInt(entry.amount) then
                fail("%s item %s: %s[%d].amount is not a positive integer (%s)",
                    vendorLabel, itemLabel, listName, index, tostring(entry.amount))
            end
            for key in pairs(entry) do
                if not COST_ENTRY_FIELDS[key] then
                    fail("%s item %s: %s[%d] has unknown key %s", vendorLabel, itemLabel, listName, index, tostring(key))
                end
            end
        end
    end
end

-- 2 + 4 + 5. Nodes shape, vendor fields, item fields. Holiday and endeavor vendors
-- ship in their own tables (ns.TimedNodes, ns.TimedVendors) and run through the same
-- checks with their own labels; ns.Vendors rows keep the ordinary schema.
local TIMED_VENDOR_FIELDS = { kind = true, event = true, holidayIDs = true, theme = true }
for key in pairs(VENDOR_FIELDS) do TIMED_VENDOR_FIELDS[key] = true end

local function newStats()
    return { maps = 0, nodes = 0, vendors = 0, items = 0 }
end

-- Returns per-npcID node counts and per-npcID { [mapID] = count }.
local function checkNodes(tableName, nodes, prefix, stats)
    local npcCounts, npcMaps = {}, {}
    if type(nodes) ~= "table" then
        fail("%s is not a table", tableName)
        return npcCounts, npcMaps
    end
    for mapID, mapNodes in pairs(nodes) do
        stats.maps = stats.maps + 1
        if not isPositiveInt(mapID) then
            fail("%s has a non-positive-integer mapID key (%s)", tableName, tostring(mapID))
        end
        if type(mapNodes) ~= "table" then
            fail("%s[%s] is not a table", tableName, tostring(mapID))
        else
            for coord, npcID in pairs(mapNodes) do
                stats.nodes = stats.nodes + 1
                if type(coord) ~= "number" or coord ~= math.floor(coord) then
                    fail("%smap %s: node coord %s is not an integer", prefix, tostring(mapID), tostring(coord))
                else
                    -- subPart is always 0..9999, so only mapPart is checked.
                    local mapPart = math.floor(coord / 10000)
                    local subPart = coord % 10000
                    if mapPart < 0 or mapPart > 10000 then
                        fail("%smap %s: node coord %s unpacks outside 0..10000 (%d, %d)",
                            prefix, tostring(mapID), tostring(coord), mapPart, subPart)
                    end
                end
                if not isPositiveInt(npcID) then
                    fail("%smap %s coord %s: npcID is not a positive integer (%s)",
                        prefix, tostring(mapID), tostring(coord), tostring(npcID))
                else
                    npcCounts[npcID] = (npcCounts[npcID] or 0) + 1
                    local maps = npcMaps[npcID]
                    if not maps then maps = {}; npcMaps[npcID] = maps end
                    maps[mapID] = (maps[mapID] or 0) + 1
                end
            end
        end
    end
    return npcCounts, npcMaps
end

local function checkVendors(tableName, vendors, fields, npcMaps, prefix, stats, checkKind)
    if type(vendors) ~= "table" then
        fail("%s is not a table", tableName)
        return
    end
    for npcID, vendor in pairs(vendors) do
        stats.vendors = stats.vendors + 1
        local vendorLabel = string.format("%svendor %s", prefix, tostring(npcID))
        if not isPositiveInt(npcID) then
            fail("%s has a non-positive-integer npcID key (%s)", tableName, tostring(npcID))
        end
        if type(vendor) ~= "table" then
            fail("%s: value is not a table", vendorLabel)
        else
            for key in pairs(vendor) do
                if not fields[key] then
                    fail("%s: unknown key %s (schema drift from the generator)", vendorLabel, tostring(key))
                end
            end
            if checkKind then checkKind(vendor, vendorLabel) end

            if type(vendor.name) ~= "string" or vendor.name == "" then
                fail("%s: name is not a non-empty string", vendorLabel)
            end
            if vendor.zone ~= nil and type(vendor.zone) ~= "string" then
                fail("%s: zone is present but not a string", vendorLabel)
            end
            if vendor.subzone ~= nil and type(vendor.subzone) ~= "string" then
                fail("%s: subzone is present but not a string", vendorLabel)
            end
            if vendor.zone == nil or vendor.zone == "" then
                fail("%s: zone is not a non-empty string", vendorLabel)
            end
            if vendor.areaID ~= nil then
                if not isPositiveInt(vendor.areaID) then
                    fail("%s: areaID is not a positive integer", vendorLabel)
                end
                if vendor.subzone == nil or vendor.subzone == "" then
                    fail("%s: areaID without subzone", vendorLabel)
                end
            end
            if vendor.faction ~= nil and vendor.faction ~= "Alliance" and vendor.faction ~= "Horde" then
                fail("%s: faction is %s, expected Alliance or Horde", vendorLabel, tostring(vendor.faction))
            end
            if vendor.factionByMap ~= nil then
                if vendor.faction ~= nil then
                    fail("%s: has both faction and factionByMap", vendorLabel)
                end
                if type(vendor.factionByMap) ~= "table" or next(vendor.factionByMap) == nil then
                    fail("%s: factionByMap is not a non-empty table", vendorLabel)
                else
                    local maps = npcMaps[npcID] or {}
                    for mapID, mapFaction in pairs(vendor.factionByMap) do
                        if not maps[mapID] then
                            fail("%s: factionByMap key %s is not a map holding this vendor's node", vendorLabel, tostring(mapID))
                        end
                        if mapFaction ~= "Alliance" and mapFaction ~= "Horde" then
                            fail("%s: factionByMap[%s] is %s, expected Alliance or Horde", vendorLabel, tostring(mapID), tostring(mapFaction))
                        end
                    end
                end
            end

            if type(vendor.items) ~= "table" then
                fail("%s: items is not a table", vendorLabel)
            else
                local seenItemIDs = {}
                local itemsLen = 0
                for _ in pairs(vendor.items) do itemsLen = itemsLen + 1 end
                for index = 1, itemsLen do
                    local item = vendor.items[index]
                    stats.items = stats.items + 1
                    if type(item) ~= "table" then
                        fail("%s: items[%d] is not a table", vendorLabel, index)
                    else
                        local itemLabel = tostring(item.id)
                        for key in pairs(item) do
                            if not ITEM_FIELDS[key] then
                                fail("%s item %s: unknown key %s (schema drift from the generator)",
                                    vendorLabel, itemLabel, tostring(key))
                            end
                        end

                        if not isPositiveInt(item.id) then
                            fail("%s: items[%d].id is not a positive integer (%s)", vendorLabel, index, tostring(item.id))
                        elseif seenItemIDs[item.id] then
                            fail("%s: item id %d appears more than once", vendorLabel, item.id)
                        else
                            seenItemIDs[item.id] = true
                        end

                        if item.price ~= nil and not (type(item.price) == "number" and item.price >= 0 and item.price == math.floor(item.price)) then
                            fail("%s item %s: price is present but not a non-negative integer (%s)",
                                vendorLabel, itemLabel, tostring(item.price))
                        end

                        checkCostList(vendorLabel, itemLabel, "currencies", item.currencies)
                        checkCostList(vendorLabel, itemLabel, "items", item.items)

                        if item.otherCost ~= nil and item.otherCost ~= true then
                            fail("%s item %s: otherCost is present but not exactly true (%s)",
                                vendorLabel, itemLabel, tostring(item.otherCost))
                        end
                    end
                end
            end
        end
    end
end

-- 3. Node rules.
local function checkNodeRules(vendorsName, vendors, npcCounts, npcMaps, prefix)
    if type(vendors) ~= "table" then return end
    for npcID, count in pairs(npcCounts) do
        if vendors[npcID] == nil then
            fail("%snode npcID %d has no matching %s entry", prefix, npcID, vendorsName)
        else
            for mapID, onMap in pairs(npcMaps[npcID]) do
                if onMap > 1 then
                    fail("%snpcID %d appears in %d nodes on map %d, expected at most 1", prefix, npcID, onMap, mapID)
                end
            end
            local vendor = vendors[npcID]
            if count > 1 and type(vendor) == "table" and (vendor.subzone ~= nil or vendor.areaID ~= nil) then
                fail("%snpcID %d has %d nodes and a subzone or areaID; that subzone would show on every map", prefix, npcID, count)
            end
        end
    end
    for npcID in pairs(vendors) do
        -- Every vendor needs at least one node.
        if (npcCounts[npcID] or 0) == 0 then
            fail("%s npcID %s has no matching node", vendorsName, tostring(npcID))
        end
    end
end

local stats = newStats()
local nodeNpcCounts, nodeNpcMaps = checkNodes("ns.Nodes", ns.Nodes, "", stats)
checkVendors("ns.Vendors", ns.Vendors, VENDOR_FIELDS, nodeNpcMaps, "", stats)
if type(ns.Nodes) == "table" then
    checkNodeRules("ns.Vendors", ns.Vendors, nodeNpcCounts, nodeNpcMaps, "")
end

-- 7. Holiday and endeavor vendors: each kind carries its own fields, and nothing
-- is shared with the ordinary tables, since the plugin folds these in without overwriting.
local timedStats = newStats()
local hasTimed = ns.TimedVendors ~= nil or ns.TimedNodes ~= nil
local hasEndeavorRows = false

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function checkTimedKind(vendor, vendorLabel)
    if vendor.kind == "event" then
        if not isNonEmptyString(vendor.event) then
            fail("%s: event is not a non-empty string", vendorLabel)
        end
        local ids = vendor.holidayIDs
        local idCount = 0
        if type(ids) == "table" then for _ in pairs(ids) do idCount = idCount + 1 end end
        if type(ids) ~= "table" or idCount == 0 or idCount ~= #ids then
            fail("%s: holidayIDs is not a non-empty list", vendorLabel)
        else
            for index = 1, idCount do
                if not isPositiveInt(ids[index]) then
                    fail("%s: holidayIDs[%d] is not a positive integer (%s)", vendorLabel, index, tostring(ids[index]))
                end
            end
        end
        if vendor.theme ~= nil then
            fail("%s: a holiday vendor has a theme", vendorLabel)
        end
    elseif vendor.kind == "endeavor" then
        hasEndeavorRows = true
        if not isNonEmptyString(vendor.theme) then
            fail("%s: theme is not a non-empty string", vendorLabel)
        end
        if vendor.event ~= nil or vendor.holidayIDs ~= nil then
            fail("%s: an endeavor vendor has holiday fields", vendorLabel)
        end
    else
        fail("%s: kind is %s, expected event or endeavor", vendorLabel, tostring(vendor.kind))
    end
end

if hasTimed then
    local timedNpcCounts, timedNpcMaps = checkNodes("ns.TimedNodes", ns.TimedNodes, "timed ", timedStats)
    checkVendors("ns.TimedVendors", ns.TimedVendors, TIMED_VENDOR_FIELDS, timedNpcMaps, "timed ", timedStats, checkTimedKind)
    if type(ns.TimedNodes) == "table" then
        checkNodeRules("ns.TimedVendors", ns.TimedVendors, timedNpcCounts, timedNpcMaps, "timed ")
    end
    if type(ns.TimedVendors) == "table" and type(ns.Vendors) == "table" then
        for npcID in pairs(ns.TimedVendors) do
            if ns.Vendors[npcID] ~= nil then
                fail("timed vendor %s is also in ns.Vendors", tostring(npcID))
            end
        end
    end
    if type(ns.TimedNodes) == "table" and type(ns.Nodes) == "table" then
        for mapID, mapNodes in pairs(ns.TimedNodes) do
            local mainNodes = ns.Nodes[mapID]
            if type(mapNodes) == "table" and type(mainNodes) == "table" then
                for coord in pairs(mapNodes) do
                    if mainNodes[coord] ~= nil then
                        fail("timed map %s coord %s is also a node in ns.Nodes", tostring(mapID), tostring(coord))
                    end
                end
            end
        end
    end
end

-- 8. Endeavor theme lookups.
local THEME_TABLES = { ids = true, titles = true, keywords = true, aliases = true }
local themes = ns.EndeavorThemes
if themes ~= nil or hasEndeavorRows then
    if type(themes) ~= "table" then
        fail("ns.EndeavorThemes is missing or not a table while endeavor vendors are present")
    else
        for key in pairs(themes) do
            if not THEME_TABLES[key] then
                fail("ns.EndeavorThemes has unknown key %s", tostring(key))
            end
        end
        for key in pairs(THEME_TABLES) do
            if type(themes[key]) ~= "table" then
                fail("ns.EndeavorThemes.%s is not a table", key)
            end
        end
        if type(themes.ids) == "table" then
            for id, theme in pairs(themes.ids) do
                if not isPositiveInt(id) or not isNonEmptyString(theme) then
                    fail("ns.EndeavorThemes.ids[%s] is not a positive ID mapped to a theme name", tostring(id))
                end
            end
        end
        if type(themes.titles) == "table" then
            for title, theme in pairs(themes.titles) do
                if not isNonEmptyString(title) or not isNonEmptyString(theme) then
                    fail("ns.EndeavorThemes.titles[%s] is not a title mapped to a theme name", tostring(title))
                end
            end
        end
        if type(themes.keywords) == "table" then
            local count = 0
            for _ in pairs(themes.keywords) do count = count + 1 end
            if count ~= #themes.keywords then
                fail("ns.EndeavorThemes.keywords is not a list")
            end
            for index = 1, #themes.keywords do
                local entry = themes.keywords[index]
                -- The plugin matches keywords against lowered text, so an uppercase letter never matches.
                if type(entry) ~= "table" or not isNonEmptyString(entry[1]) or not isNonEmptyString(entry[2])
                        or entry[1] ~= entry[1]:lower() then
                    fail("ns.EndeavorThemes.keywords[%d] is not a { lowercase keyword, theme } pair", index)
                end
            end
        end
        if type(themes.aliases) == "table" then
            for variant, canonical in pairs(themes.aliases) do
                local target = type(ns.TimedVendors) == "table" and ns.TimedVendors[canonical]
                if not isPositiveInt(variant) or type(target) ~= "table" or target.kind ~= "endeavor" then
                    fail("ns.EndeavorThemes.aliases[%s] does not point at an endeavor vendor", tostring(variant))
                end
            end
        end
    end
end

-- 6. The shipped two-map vendor keeps a node and a faction on each map.
do
    local maps = nodeNpcMaps[267870] or {}
    local mapTotal = 0
    for _ in pairs(maps) do mapTotal = mapTotal + 1 end
    if mapTotal ~= 2 or not maps[2351] or not maps[2352] then
        fail("vendor 267870: expected nodes on exactly maps 2351 and 2352")
    end
    local vendor = type(ns.Vendors) == "table" and ns.Vendors[267870]
    local byMap = type(vendor) == "table" and vendor.factionByMap
    local byMapTotal = 0
    if type(byMap) == "table" then for _ in pairs(byMap) do byMapTotal = byMapTotal + 1 end end
    if byMapTotal ~= 2 or byMap[2351] ~= "Horde" or byMap[2352] ~= "Alliance" then
        fail("vendor 267870: factionByMap expected { [2351] = Horde, [2352] = Alliance }")
    end
end

print(string.format("Checked: %d vendors, %d maps (%d nodes), %d items.", stats.vendors, stats.maps, stats.nodes, stats.items))
if hasTimed then
    print(string.format("Checked timed: %d vendors, %d maps (%d nodes), %d items.",
        timedStats.vendors, timedStats.maps, timedStats.nodes, timedStats.items))
end

if #problems == 0 then
    print("RESULT: OK")
    os.exit(0)
else
    print(string.format("RESULT: %d PROBLEMS", #problems))
    for _, message in ipairs(problems) do
        print("  " .. message)
    end
    os.exit(1)
end

-- luacheck: pop
