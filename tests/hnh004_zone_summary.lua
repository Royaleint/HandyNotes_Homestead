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

local function loadRuntime(addons, faction)
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
            return 0.1, 0.1, 0.2, 0.2
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
    _G.C_Texture = { GetAtlasInfo = function() return { file = 12345 } end }
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
        function() return rectangleCalls, rectangleOrder end, forcedZoneOrder
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
    for _, node in pairs(nodes) do
        local record = node.record
        check(type(record) == "table" and record.kind == "zoneSummary", "every continent record must be a typed zone summary")
        check(type(record.zoneMapID) == "number" and type(record.vendorCount) == "number", "summary record must carry a zone ID and vendor count")
    end
end

local standalone = loadRuntime({}, "Alliance")
check(standalone, "standalone registration did not capture a plugin handler")
check(not loadRuntime({ Homestead = true }, "Alliance"), "Homestead-enabled path registered the plugin")
check(not loadRuntime({ Homestead_DevBuild = true }, "Alliance"), "Homestead_DevBuild-enabled path registered the plugin")

local handler, tooltip, waypoint, selectedMap, setFaction, rectangleStats, forcedZoneOrder = loadRuntime({}, "Alliance")
check(forcedZoneOrder[1] == 102 and forcedZoneOrder[2] == 101, "collision fixture must enumerate zones out of sorted order")
local zoneNodes = collect(handler, 101, false)
check(type(zoneNodes[10001000].record) == "number", "zone vendor records must remain numeric")
local pin = { GetCenter = function() return 0 end }
handler.OnEnter(pin, 101, 10001000)
check(tooltip.lines[1] == "Alliance vendor" and tooltip.lines[4] == "Wares:" and tooltip.lines[5] == "Cached item", "numeric vendor OnEnter must retain its wares tooltip path")

local summaries = collect(handler, 900, false)
check(countNodes(summaries) == 2, "continent must emit one summary for each rectangle-projectable eligible zone")
checkSummaryRecords(summaries)
local firstBuildCalls, firstBuildOrder = rectangleStats()
check(firstBuildCalls == 3 and firstBuildOrder[1] == 101 and firstBuildOrder[2] == 102 and firstBuildOrder[3] == 103, "summary builder must sort zone IDs before collision nudging")
local first = summaries[15001500]
local second = summaries[15001501]
check(first and first.record.kind == "zoneSummary", "continent record must be a typed zone summary")
check(first.record.zoneMapID == 101 and first.record.vendorCount == 2, "summary must count unique Alliance-visible vendors")
check(second and second.record.zoneMapID == 102 and second.record.vendorCount == 1, "sorted collisions must nudge the later zone deterministically")
check(first.icon ~= zoneNodes[10001000].icon, "summary must use a distinct icon")
check(countNodes(collect(handler, 900, false)) == 2, "same-faction continent request must retain summaries")
local repeatedBuildCalls = rectangleStats()
check(repeatedBuildCalls == firstBuildCalls, "same-faction continent request must reuse its cached summary build")

setFaction("Horde")
local hordeSummaries = collect(handler, 900, false)
checkSummaryRecords(hordeSummaries)
local hordeBuildCalls, hordeBuildOrder = rectangleStats()
check(hordeBuildCalls == firstBuildCalls * 2 and hordeBuildOrder[4] == 101 and hordeBuildOrder[5] == 102 and hordeBuildOrder[6] == 103, "new faction must build a separate sorted summary cache")
check(hordeSummaries[15001500].record.vendorCount == 1, "faction cache must not reuse Alliance summary counts")
check(hordeSummaries[15001501].record.vendorCount == 2, "Horde summary must include Horde and neutral vendors")
check(not summaries[15001502], "missing rectangle must omit only its zone")

handler.OnEnter(pin, 900, 15001500)
check(#tooltip.lines == 3 and tooltip.lines[1] == "Alpha" and tooltip.lines[2] == "2 vendors", "summary tooltip must contain only the zone and vendor count")
check(type(tooltip.lines[3]) == "string" and string.find(string.lower(tooltip.lines[3]), "click"), "summary tooltip must include a click instruction")
check(not string.find(table.concat(tooltip.lines, "\n"), "Alliance vendor") and not string.find(table.concat(tooltip.lines, "\n"), "Wares") and not string.find(table.concat(tooltip.lines, "\n"), "Cached item"), "summary tooltip must not render vendor wares or item lines")
handler:OnClick("LeftButton", false, 900, 15001500)
check(selectedMap() == 101, "summary click must navigate to its zone")
check(waypoint.set == 0 and waypoint.clear == 0 and waypoint.superTrack == 0, "summary click must not set, clear, or super-track a waypoint")

handler:OnClick("LeftButton", false, 101, 10001000)
check(waypoint.set == 1 and waypoint.superTrack == 1, "vendor click must retain waypoint and super-tracking behavior")
local minimapNodes = collect(handler, 900, true)
check(type(minimapNodes[70007000].record) == "number", "minimap must retain fixture native numeric nodes")
for _, node in pairs(minimapNodes) do
    check(type(node.record) ~= "table" or node.record.kind ~= "zoneSummary", "minimap continent request must not synthesize zone summaries")
end

print("HNH-004 zone summary harness: PASS")
-- luacheck: pop
