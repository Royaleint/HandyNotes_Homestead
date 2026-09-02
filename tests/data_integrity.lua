-- luacheck: push ignore 111 112 113

--[[
    Schema and provenance check for the committed Data.lua, independent of
    the generator (Home_Dev/scripts/generate-handynotes-export.mjs). Needs no
    Homestead sources: it validates the shape, internal consistency, and
    source-stamp presence of the exported file by itself, so a hand-edited,
    malformed, or unstamped Data.lua fails here even without access to the
    private data repo (HNH-25 follow-through, Sage validator-gap 1). It
    cannot detect a well-formed but STALE Data.lua (correct shape, outdated
    contents) — that needs the private repo's source data and is the
    fidelity checker's job (Home_Dev/scripts/verify-handynotes-export.lua),
    not this file's.

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

-- 1. Header stamp: must name a real Homestead version. "working-tree" (the
-- generator's default) or a missing stamp means the file was regenerated
-- without --source-version and its provenance is unverifiable. Matched only
-- against the header comment block itself (everything up to and including
-- the `]]` that closes it), not the whole file and not the gap after it
-- either, so a stray `-- Source: Homestead vX.Y.Z` comment planted anywhere
-- outside that block, including between the closing `]]` and `local _, ns`,
-- cannot be mistaken for the real stamp (Argus Gate 1 cycle 1 finding 5,
-- cycle 2 note 1).
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
            fail("Data.lua was generated without --source-version")
        end
    end
end

local ns = {}
assert(loadfile(dataPath))("HandyNotes_Homestead", ns)

local VENDOR_FIELDS = { name = true, zone = true, subzone = true, faction = true, items = true }
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

-- 2 + 4 + 5. Nodes shape, vendor fields, item fields.
local mapCount, nodeCount, vendorCount, itemCount = 0, 0, 0, 0
local nodeNpcCounts = {}

if type(ns.Nodes) ~= "table" then
    fail("ns.Nodes is not a table")
else
    for mapID, mapNodes in pairs(ns.Nodes) do
        mapCount = mapCount + 1
        if not isPositiveInt(mapID) then
            fail("ns.Nodes has a non-positive-integer mapID key (%s)", tostring(mapID))
        end
        if type(mapNodes) ~= "table" then
            fail("ns.Nodes[%s] is not a table", tostring(mapID))
        else
            for coord, npcID in pairs(mapNodes) do
                nodeCount = nodeCount + 1
                if type(coord) ~= "number" or coord ~= math.floor(coord) then
                    fail("map %s: node coord %s is not an integer", tostring(mapID), tostring(coord))
                else
                    -- subPart (coord % 10000) is always in 0..9999 for any
                    -- Lua number, negatives included, so a subPart range
                    -- check can never fire; only mapPart is checked (Argus
                    -- Gate 1 cycle 1, finding 4).
                    local mapPart = math.floor(coord / 10000)
                    local subPart = coord % 10000
                    if mapPart < 0 or mapPart > 10000 then
                        fail("map %s: node coord %s unpacks outside 0..10000 (%d, %d)",
                            tostring(mapID), tostring(coord), mapPart, subPart)
                    end
                end
                if not isPositiveInt(npcID) then
                    fail("map %s coord %s: npcID is not a positive integer (%s)",
                        tostring(mapID), tostring(coord), tostring(npcID))
                else
                    nodeNpcCounts[npcID] = (nodeNpcCounts[npcID] or 0) + 1
                end
            end
        end
    end
end

if type(ns.Vendors) ~= "table" then
    fail("ns.Vendors is not a table")
else
    for npcID, vendor in pairs(ns.Vendors) do
        vendorCount = vendorCount + 1
        local vendorLabel = string.format("vendor %s", tostring(npcID))
        if not isPositiveInt(npcID) then
            fail("ns.Vendors has a non-positive-integer npcID key (%s)", tostring(npcID))
        end
        if type(vendor) ~= "table" then
            fail("%s: value is not a table", vendorLabel)
        else
            for key in pairs(vendor) do
                if not VENDOR_FIELDS[key] then
                    fail("%s: unknown key %s (schema drift from the generator)", vendorLabel, tostring(key))
                end
            end

            if type(vendor.name) ~= "string" or vendor.name == "" then
                fail("%s: name is not a non-empty string", vendorLabel)
            end
            if vendor.zone ~= nil and type(vendor.zone) ~= "string" then
                fail("%s: zone is present but not a string", vendorLabel)
            end
            if vendor.subzone ~= nil and type(vendor.subzone) ~= "string" then
                fail("%s: subzone is present but not a string", vendorLabel)
            end
            if vendor.faction ~= nil and vendor.faction ~= "Alliance" and vendor.faction ~= "Horde" then
                fail("%s: faction is %s, expected Alliance or Horde", vendorLabel, tostring(vendor.faction))
            end

            if type(vendor.items) ~= "table" then
                fail("%s: items is not a table", vendorLabel)
            else
                local seenItemIDs = {}
                local itemsLen = 0
                for _ in pairs(vendor.items) do itemsLen = itemsLen + 1 end
                for index = 1, itemsLen do
                    local item = vendor.items[index]
                    itemCount = itemCount + 1
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

-- 3. Bijection between ns.Nodes and ns.Vendors.
if type(ns.Nodes) == "table" and type(ns.Vendors) == "table" then
    for npcID, count in pairs(nodeNpcCounts) do
        if ns.Vendors[npcID] == nil then
            fail("node npcID %d has no matching ns.Vendors entry", npcID)
        elseif count > 1 then
            fail("npcID %d appears in %d nodes, expected exactly 1", npcID, count)
        end
    end
    for npcID in pairs(ns.Vendors) do
        -- count > 1 is already reported by the nodeNpcCounts loop above.
        if (nodeNpcCounts[npcID] or 0) == 0 then
            fail("ns.Vendors npcID %s has no matching node", tostring(npcID))
        end
    end
end

print(string.format("Checked: %d vendors, %d maps (%d nodes), %d items.", vendorCount, mapCount, nodeCount, itemCount))

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
