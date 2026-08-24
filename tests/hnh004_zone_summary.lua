-- luacheck: push ignore 111 112 113

local function check(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function countNodes(nodes)
    local count = 0
    for _ in pairs(nodes) do
        count = count + 1
    end
    return count
end

local realData = {}
assert(loadfile("Data.lua"))("HandyNotes_Homestead", realData)
check(countNodes(realData.Nodes) > 0, "Data.lua smoke check found no zone nodes")
check(countNodes(realData.Vendors) > 0, "Data.lua smoke check found no vendors")

local activeRestores = {}

local function restoreAll()
    for index = #activeRestores, 1, -1 do
        activeRestores[index]()
    end
end

local function loadRuntime(addons, faction, summaryAtlasAvailable)
    local registered
    local frame
    local factionState = { value = faction }
    local tooltip = { lines = {}, owner = nil }
    local waypoint = { set = 0, clear = 0, superTrack = 0 }
    local mapSelection
    local rectangleCalls = 0
    local rectangleOrder = {}
    local fixture = {
        [900] = { mapID = 900, mapType = 2 },
        [101] = { mapID = 101, mapType = 3, parentMapID = 900, name = "Alpha" },
        [102] = { mapID = 102, mapType = 3, parentMapID = 900, name = "Bravo" },
        [103] = { mapID = 103, mapType = 3, parentMapID = 900, name = "Charlie" },
    }
    local mapApi = {
        GetMapInfo = function(mapID) return fixture[mapID] end,
        GetMapRectOnMap = function(zoneMapID, continentMapID)
            rectangleCalls = rectangleCalls + 1
            rectangleOrder[#rectangleOrder + 1] = zoneMapID
            if continentMapID ~= 900 or zoneMapID == 103 then return nil end
            return 0.1, 0.2, 0.99985, 0.99995
        end,
        CanSetUserWaypointOnMap = function() return true end,
        HasUserWaypoint = function() return false end,
        ClearUserWaypoint = function() waypoint.clear = waypoint.clear + 1 end,
        SetUserWaypoint = function() waypoint.set = waypoint.set + 1 end,
    }
    local data = {
        Nodes = {
            [101] = { [10001000] = 1, [20002000] = 1, [30003000] = 2 },
            [102] = { [40004000] = 3, [50005000] = 4 },
            [103] = { [60006000] = 5 },
            [900] = { [70007000] = 6 },
        },
        Vendors = {
            [1] = { name = "Alliance vendor", zone = "Zone One", faction = "Alliance", items = { { id = 1 } } },
            [2] = { name = "Neutral vendor", items = {} },
            [3] = { name = "Horde vendor", faction = "Horde", items = {} },
            [4] = { name = "Second neutral vendor", items = {} },
            [5] = { name = "Omitted vendor", items = {} },
            [6] = { name = "Invalid continent vendor", items = {} },
        },
    }
    local globalNames = {
        "Enum", "next", "pairs", "C_Map", "C_Texture", "C_AddOns", "UnitFactionGroup", "CreateFrame",
        "GameTooltip", "UIParent", "WorldMapFrame", "UiMapPoint", "C_SuperTrack", "C_CurrencyInfo",
        "C_Item", "Item", "HandyNotes", "LibStub",
    }
    local originalGlobals = {}
    for index = 1, #globalNames do
        local name = globalNames[index]
        originalGlobals[name] = _G[name]
    end
    local restored
    local function restore()
        if restored then return end
        restored = true
        for index = 1, #globalNames do
            local name = globalNames[index]
            _G[name] = originalGlobals[name]
        end
    end
    activeRestores[#activeRestores + 1] = restore
    local nativeNext = next
    local nativePairs = pairs
    local forcedZoneOrder = { 102, 101, 103, 900 }
    local function fixtureNext(table, key)
        if table ~= data.Nodes then return nativeNext(table, key) end
        local index = 0
        if key then
            for position, zoneMapID in ipairs(forcedZoneOrder) do
                if zoneMapID == key then
                    index = position
                    break
                end
            end
        end
        local zoneMapID = forcedZoneOrder[index + 1]
        return zoneMapID, zoneMapID and table[zoneMapID]
    end
    local function fixturePairs(table)
        if table == data.Nodes then return fixtureNext, table, nil end
        return nativePairs(table)
    end

    _G.Enum = { UIMapType = { Continent = 2 } }
    _G.next = fixtureNext
    _G.pairs = fixturePairs
    _G.C_Map = mapApi
    _G.C_Texture = {
        GetAtlasInfo = function(atlas)
            if atlas == "FlightMaster" and summaryAtlasAvailable ~= false then
                return {
                    file = 12345,
                    leftTexCoord = 0.1,
                    rightTexCoord = 0.9,
                    topTexCoord = 0.2,
                    bottomTexCoord = 0.8,
                }
            end
        end,
    }
    _G.C_AddOns = { IsAddOnLoaded = function(name) return false, addons[name] end }
    _G.UnitFactionGroup = function() return factionState.value end
    _G.CreateFrame = function()
        frame = { scripts = {} }
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        return frame
    end
    _G.GameTooltip = tooltip
    function tooltip:SetOwner(owner) self.owner = owner end
    function tooltip:IsOwned(owner) return self.owner == owner end
    function tooltip:SetText(text) self.lines = { text } end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. right end
    function tooltip:Show() end
    function tooltip:Hide() self.owner = nil end
    _G.UIParent = { GetCenter = function() return 0 end }
    _G.WorldMapFrame = { SetMapID = function(_, mapID) mapSelection = mapID end }
    _G.UiMapPoint = { CreateFromCoordinates = function(_, x, y) return { x = x, y = y } end }
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() waypoint.superTrack = waypoint.superTrack + 1 end }
    _G.C_CurrencyInfo = { GetCoinTextureString = function(price) return tostring(price) end, GetCurrencyInfo = function() end }
    _G.C_Item = { GetItemInfo = function() return "Cached item" end, DoesItemExistByID = function() return false end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.HandyNotes = {
        RegisterPluginDB = function(_, _, handler) registered = handler end,
        getXY = function(_, coord) return math.floor(coord / 10000) / 10000, (coord % 10000) / 10000 end,
    }
    _G.LibStub = function(name)
        if name == "AceDB-3.0" then
            return { New = function() return { profile = { icon_scale = 1, icon_alpha = 1 } } end }
        end
        if name == "HereBeDragons-2.0" then
            return { TranslateZoneCoordinates = function(_, x, y) return x, y end }
        end
        return { Embed = function(_, target) target.SendMessage = function() end end }
    end

    assert(loadfile("HandyNotes_Homestead.lua"))("HandyNotes_Homestead", data)
    frame.scripts.OnEvent(frame)
    return registered, tooltip, waypoint, function() return mapSelection end, function(value) factionState.value = value end,
        function() return rectangleCalls, rectangleOrder end, forcedZoneOrder, restore, data
end

local function collect(handler, mapID, minimap)
    local iter, state, control = handler:GetNodes2(mapID, minimap)
    local nodes = {}
    while true do
        local coord, _, icon = iter(state, control)
        if not coord then return nodes end
        nodes[coord] = { record = state[coord], icon = icon }
        control = coord
    end
end

local function checkSummaryRecords(nodes)
    for coord, node in pairs(nodes) do
        local record = node.record
        local kind = type(record) == "table" and record.kind or type(record)
        check(kind == "zoneSummary", "summary at " .. coord .. " expected kind zoneSummary, got " .. tostring(kind))
        check(type(record.zoneMapID) == "number" and type(record.vendorCount) == "number", "summary at " .. coord .. " expected numeric zoneMapID and vendorCount, got " .. tostring(record.zoneMapID) .. " and " .. tostring(record.vendorCount))
    end
end

local function checkSummaryAt(nodes, coord, zoneMapID, vendorCount)
    local node = nodes[coord]
    local record = node and node.record
    check(node, "summary at " .. coord .. " expected zone " .. zoneMapID .. ", got nil")
    check(type(record) == "table", "summary at " .. coord .. " expected table, got " .. type(record))
    check(record.zoneMapID == zoneMapID and record.vendorCount == vendorCount, "summary at " .. coord .. " expected zone/count " .. zoneMapID .. "/" .. vendorCount .. ", got " .. tostring(record.zoneMapID) .. "/" .. tostring(record.vendorCount))
    return node
end

local function run()
    local standalone = { loadRuntime({}, "Alliance") }
    check(standalone[1], "standalone registration did not capture a plugin handler")
    standalone[8]()
    local homestead = { loadRuntime({ Homestead = true }, "Alliance") }
    check(not homestead[1], "Homestead-enabled path registered the plugin")
    homestead[8]()
    local devBuild = { loadRuntime({ Homestead_DevBuild = true }, "Alliance") }
    check(not devBuild[1], "Homestead_DevBuild-enabled path registered the plugin")
    devBuild[8]()

    local handler, tooltip, waypoint, selectedMap, setFaction, rectangleStats, forcedZoneOrder, _, data = loadRuntime({}, "Alliance")
    check(forcedZoneOrder[1] == 102 and forcedZoneOrder[2] == 101, "collision fixture must enumerate zones out of sorted order")
    local zoneNodes = collect(handler, 101, false)
    local zoneVendor = zoneNodes[10001000]
    check(zoneVendor and type(zoneVendor.record) == "number", "zone vendor at 10001000 expected numeric record, got " .. tostring(zoneVendor and zoneVendor.record))
    local pin = { GetCenter = function() return 0 end }
    handler.OnEnter(pin, 101, 10001000)
    check(tooltip.lines[1] == "Alliance vendor" and tooltip.lines[4] == "Wares:" and tooltip.lines[5] == "Cached item", "numeric vendor OnEnter must retain its wares tooltip path")

    local summaries = collect(handler, 900, false)
    check(countNodes(summaries) == 2, "continent must emit one summary for each rectangle-projectable eligible zone")
    checkSummaryRecords(summaries)
    local firstBuildCalls, firstBuildOrder = rectangleStats()
    check(firstBuildCalls == 3 and firstBuildOrder[1] == 101 and firstBuildOrder[2] == 102 and firstBuildOrder[3] == 103, "summary builder must sort zone IDs before collision nudging")
    local first = checkSummaryAt(summaries, 15009999, 101, 2)
    checkSummaryAt(summaries, 15019999, 102, 1)
    check(first.icon ~= zoneVendor.icon, "summary must use a distinct icon")
    check(type(first.icon) == "table" and first.icon.icon == 12345 and first.icon.tCoordLeft == 0.1 and first.icon.tCoordRight == 0.9 and first.icon.tCoordTop == 0.2 and first.icon.tCoordBottom == 0.8, "summary must use the resolved FlightMaster atlas payload")
    local fallbackRuntime = { loadRuntime({}, "Alliance", false) }
    local fallbackSummary = checkSummaryAt(collect(fallbackRuntime[1], 900, false), 15009999, 101, 2)
    check(fallbackSummary.icon == "Interface\\MINIMAP\\TRACKING\\Banker", "summary must fall back to the Banker texture when its atlas is unavailable")
    fallbackRuntime[8]()
    check(countNodes(collect(handler, 900, false)) == 2, "same-faction continent request must retain summaries")
    local repeatedBuildCalls = rectangleStats()
    check(repeatedBuildCalls == firstBuildCalls, "same-faction continent request must reuse its cached summary build")

    setFaction("Horde")
    local hordeSummaries = collect(handler, 900, false)
    checkSummaryRecords(hordeSummaries)
    local hordeBuildCalls, hordeBuildOrder = rectangleStats()
    check(hordeBuildCalls == firstBuildCalls * 2 and hordeBuildOrder[4] == 101 and hordeBuildOrder[5] == 102 and hordeBuildOrder[6] == 103, "new faction must build a separate sorted summary cache")
    checkSummaryAt(hordeSummaries, 15009999, 101, 1)
    checkSummaryAt(hordeSummaries, 15019999, 102, 2)
    setFaction("Alliance")
    local restoredAllianceSummaries = collect(handler, 900, false)
    checkSummaryAt(restoredAllianceSummaries, 15009999, 101, 2)
    checkSummaryAt(restoredAllianceSummaries, 15019999, 102, 1)
    local restoredAllianceBuildCalls = rectangleStats()
    check(restoredAllianceBuildCalls == hordeBuildCalls, "switching back must reuse the existing Alliance cache entry")
    setFaction(nil)
    local nilFactionSummaries = collect(handler, 900, false)
    checkSummaryRecords(nilFactionSummaries)
    local nilFactionBuildCalls = rectangleStats()
    check(nilFactionBuildCalls == hordeBuildCalls + firstBuildCalls, "nil faction must build a stable normalized cache entry")
    check(countNodes(collect(handler, 900, false)) == countNodes(nilFactionSummaries), "repeated nil-faction request must retain summary counts")
    local repeatedNilFactionBuildCalls = rectangleStats()
    check(repeatedNilFactionBuildCalls == nilFactionBuildCalls, "repeated nil-faction request must reuse its normalized cache entry")
    local failures = data.ZoneSummaryProjectionFailures
    local continentFailures = failures and failures[900]
    check(type(continentFailures and continentFailures.Alliance and continentFailures.Alliance[103]) == "string", "Alliance projection failure must remain cached")
    check(type(continentFailures and continentFailures.Horde and continentFailures.Horde[103]) == "string", "Horde projection failure must remain cached")
    check(type(continentFailures and continentFailures.Neutral and continentFailures.Neutral[103]) == "string", "nil-faction projection failure must remain cached")

    handler.OnEnter(pin, 900, 15009999)
    check(#tooltip.lines == 3 and tooltip.lines[1] == "Alpha" and tooltip.lines[2] == "2 vendors", "summary tooltip must contain only the zone and vendor count")
    check(type(tooltip.lines[3]) == "string" and string.find(string.lower(tooltip.lines[3]), "click"), "summary tooltip must include a click instruction")
    check(not string.find(table.concat(tooltip.lines, "\n"), "Alliance vendor") and not string.find(table.concat(tooltip.lines, "\n"), "Wares") and not string.find(table.concat(tooltip.lines, "\n"), "Cached item"), "summary tooltip must not render vendor wares or item lines")
    handler:OnClick("LeftButton", false, 900, 15009999)
    check(selectedMap() == 101, "summary click must navigate to its zone")
    check(waypoint.set == 0 and waypoint.clear == 0 and waypoint.superTrack == 0, "summary click must not set, clear, or super-track a waypoint")

    handler:OnClick("LeftButton", false, 101, 10001000)
    check(waypoint.set == 1 and waypoint.superTrack == 1, "vendor click must retain waypoint and super-tracking behavior")
    local minimapNodes = collect(handler, 900, true)
    local minimapNative = minimapNodes[70007000]
    check(minimapNative and type(minimapNative.record) == "number", "minimap native node at 70007000 expected numeric record, got " .. tostring(minimapNative and minimapNative.record))
    for coord, node in pairs(minimapNodes) do
        check(type(node.record) ~= "table" or node.record.kind ~= "zoneSummary", "minimap node at " .. coord .. " must not be a synthesized zoneSummary")
    end
end

local ok, err = xpcall(run, debug.traceback)
restoreAll()
if not ok then error(err, 0) end

print("HNH-004 zone summary harness: PASS")
-- luacheck: pop
