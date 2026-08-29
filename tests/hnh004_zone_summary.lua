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

local function loadRuntime(addons, faction, summaryAtlasAvailable, runtimeData, runtimeFixture, rectangleProvider, hbdTranslation, professionSkillLineID, itemNames, currencyNames, itemIcons)
    local registered
    local frame
    local factionState = { value = faction }
    local tooltip = { lines = {}, owner = nil, scripts = {}, hookInstallations = 0 }
    local waypoint = { set = 0, clear = 0, superTrack = 0 }
    local mapSelection
    local rectangleCalls = 0
    local rectangleOrder = {}
    local itemCached = true
    local itemLoadCallbacks = {}
    local itemLoadCallbacksByID = {}
    local editBoxes = {}
    local timers = {}
    local createdFrames = {}
    local hookInstallations = 0
    local libStubCalls = 0
    local fixture = runtimeFixture or {
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
            if rectangleProvider then
                return rectangleProvider(zoneMapID, continentMapID)
            end
            if continentMapID ~= 900 or zoneMapID == 103 then return nil end
            return 0.1, 0.2, 0.99985, 0.99995
        end,
        CanSetUserWaypointOnMap = function() return true end,
        HasUserWaypoint = function() return false end,
        ClearUserWaypoint = function() waypoint.clear = waypoint.clear + 1 end,
        SetUserWaypoint = function() waypoint.set = waypoint.set + 1 end,
    }
    local data = runtimeData or {
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
        "C_Item", "Item", "C_Timer", "HandyNotes", "LibStub", "GetProfessions", "GetProfessionInfo",
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
        if table ~= data.Nodes or runtimeData then return nativeNext(table, key) end
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

    _G.Enum = { UIMapType = { World = 1, Continent = 2 } }
    _G.next = fixtureNext
    _G.pairs = fixturePairs
    _G.C_Map = mapApi
    _G.C_Texture = {
        GetAtlasInfo = function(atlas)
            if atlas == "housing-decor-vendor_32" then
                return {
                    file = 54321,
                    leftTexCoord = 0.11,
                    rightTexCoord = 0.89,
                    topTexCoord = 0.21,
                    bottomTexCoord = 0.79,
                }
            end
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
    _G.GetProfessions = function()
        if professionSkillLineID then return 1, nil, nil, nil, nil end
    end
    _G.GetProfessionInfo = function()
        if professionSkillLineID then return "Test profession", nil, 1, 100, nil, nil, professionSkillLineID end
    end
    _G.CreateFrame = function(frameType, name, parent, template)
        frame = { frameType = frameType, name = name, parent = parent, template = template, scripts = {}, lines = {}, fontStrings = {} }
        createdFrames[#createdFrames + 1] = frame
        function frame:GetCenter() return 0 end
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        function frame:SetScript(scriptName, callback) self.scripts[scriptName] = callback end
        function frame:HookScript(scriptName, callback)
            hookInstallations = hookInstallations + 1
            self.hookInstallations = (self.hookInstallations or 0) + 1
            self.scripts[scriptName] = callback
        end
        function frame:SetFrameStrata(strata) self.strata = strata end
        function frame:SetClampedToScreen(value) self.clamped = value end
        function frame:EnableMouse(value) self.mouseEnabled = value end
        function frame:EnableMouseWheel(value) self.mouseWheelEnabled = value end
        function frame:EnableKeyboard(value) self.keyboardEnabled = value end
        function frame:SetPropagateKeyboardInput(value)
            self.propagateCalls = self.propagateCalls or {}
            self.propagateCalls[#self.propagateCalls + 1] = value
            self.propagateKeyboardInput = value
        end
        function frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
        function frame:ClearAllPoints() self.points = {} end
        function frame:SetWidth(value) self.width = value end
        function frame:SetHeight(value) self.height = value end
        function frame:SetSize(width, height) self.width = width; self.height = height end
        -- A shown tooltip has a real width; 0 is the "rect not valid yet" case tests set explicitly.
        function frame:GetWidth() return self.width or (frameType == "GameTooltip" and 300) or 0 end
        -- A shown tooltip has a real height; 0 is the "rect not valid yet" case tests set explicitly.
        function frame:GetHeight() return self.height or (frameType == "GameTooltip" and 300) or 0 end
        function frame:GetTop() return self.top end
        function frame:GetEffectiveScale() return self.effectiveScale or 1 end
        function frame:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
        function frame:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
        function frame:IsShown() return self.shown end
        function frame:IsMouseOver() return self.mouseOver end
        function frame:SetOwner(owner) self.owner = owner end
        function frame:GetOwner() return self.owner end
        function frame:ClearLines() self.lines = {}; self.clearCalls = (self.clearCalls or 0) + 1 end
        function frame:SetText(text) self.lines = { text } end
        function frame:AddLine(text) self.lines[#self.lines + 1] = text end
        function frame:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. right end
        function frame:SetScrollChild(child) self.scrollChild = child end
        function frame:SetVerticalScroll(value) self.verticalScroll = value end
        function frame:GetVerticalScroll() return self.verticalScroll or 0 end
        function frame:GetVerticalScrollRange() return self.verticalScrollRange or 0 end
        function frame:SetPadding(right, bottom) self.padding = { right = right, bottom = bottom } end
        function frame:SetMinimumWidth(width) self.minimumWidth = width end
        if template == "MinimalScrollBar" then
            function frame:Init(visibleExtent, panExtent)
                self.visibleExtent = visibleExtent; self.panExtent = panExtent; self.scrollPercentage = 0
            end
            function frame:SetVisibleExtentPercentage(value) self.visibleExtent = value end
            function frame:SetPanExtentPercentage(value) self.panExtent = value end
            function frame:RegisterCallback(event, callback, owner) self.callbacks = self.callbacks or {}; self.callbacks[event] = { callback, owner } end
            -- Like Blizzard's ScrollBarMixin, every SetScrollPercentage fires OnScroll.
            function frame:SetScrollPercentage(value)
                self.scrollPercentage = value
                self.scrollSets = (self.scrollSets or 0) + 1
                local entry = self.callbacks and self.callbacks.OnScroll
                if entry then entry[1](entry[2], value) end
            end
        end
        function frame:CreateFontString()
            local line = { shown = false }
            self.fontStrings[#self.fontStrings + 1] = line
            line.SetPoint = function(...) line.point = { ... } end
            line.ClearAllPoints = function() line.point = nil end
            line.SetText = function(_, text) line.text = text end
            line.Show = function() line.shown = true end
            line.Hide = function() line.shown = false end
            return line
        end
        if frameType == "EditBox" then
            editBoxes[#editBoxes + 1] = frame
            function frame:SetAutoFocus() end
            frame.Instructions = { SetText = function(instructions, text) instructions.text = text end }
            function frame:SetMaxLetters() end
            function frame:SetText(text)
                self.text = text
                if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
            end
            function frame:GetText() return self.text or "" end
            function frame:HasFocus() return self.focused end
            function frame:ClearFocus()
                -- Like the client: focus-lost fires only if the box had focus.
                if not self.focused then return end
                self.focused = nil
                if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
            end
        end
        return frame
    end
    _G.GameTooltip = tooltip
    _G.BaseScrollBoxEvents = { OnScroll = "OnScroll" }
    _G.ScrollBoxConstants = { NoScrollInterpolation = true }
    _G.SearchBoxTemplate_OnTextChanged = function(box) box.templateTextChanged = (box.templateTextChanged or 0) + 1 end
    _G.SearchBoxTemplate_OnEditFocusLost = function(box) box.templateFocusLost = (box.templateFocusLost or 0) + 1 end
    function tooltip:SetOwner(owner) self.owner = owner end
    function tooltip:IsOwned(owner) return self.owner == owner end
    function tooltip:SetText(text) self.lines = { text } end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. right end
    function tooltip:Show() end
    function tooltip:Hide() self.owner = nil end
    function tooltip:HookScript(name, callback)
        hookInstallations = hookInstallations + 1
        self.hookInstallations = self.hookInstallations + 1
        self.scripts[name] = callback
    end
    function tooltip:IsMouseOver() return self.mouseOver end
    _G.UIParent = { GetCenter = function() return 0 end }
    _G.WorldMapFrame = {
        scripts = {},
        SetMapID = function(_, mapID) mapSelection = mapID end,
        HookScript = function(worldMap, scriptName, callback)
            hookInstallations = hookInstallations + 1
            worldMap.scripts[scriptName] = callback
        end,
    }
    _G.UiMapPoint = { CreateFromCoordinates = function(_, x, y) return { x = x, y = y } end }
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() waypoint.superTrack = waypoint.superTrack + 1 end }
    _G.C_CurrencyInfo = {
        GetCoinTextureString = function(price) return tostring(price) end,
        GetCurrencyInfo = function(currencyID)
            local name = currencyNames and currencyNames[currencyID]
            return name and { name = name } or nil
        end,
    }
    _G.C_Item = {
        GetItemInfo = function(itemID)
            if not itemCached then return nil end
            return itemNames and itemNames[itemID] or "Cached item"
        end,
        DoesItemExistByID = function() return true end,
        -- Gated on the same itemCached flag as GetItemInfo: a real client
        -- with a cold item cache resolves neither icon nor name for ANY
        -- item, ware or reagent (HNH-021 round 2, Argus Minor 2). A
        -- per-item table lookup (itemIcons/itemNames absent for a given id)
        -- separately models "this specific item hasn't loaded yet" even
        -- while itemCached is true, which is what the cold-reagent tests
        -- below use.
        GetItemIconByID = function(itemID)
            if not itemCached then return nil end
            return itemIcons and itemIcons[itemID]
        end,
        GetItemNameByID = function(itemID)
            if not itemCached then return nil end
            return itemNames and itemNames[itemID]
        end,
    }
    _G.C_Timer = {
        After = function(_, callback) callback() end,
        NewTimer = function(_, callback)
            local timer = { cancelled = false }
            function timer:Cancel() self.cancelled = true end
            timers[#timers + 1] = { timer = timer, callback = callback }
            return timer
        end,
    }
    _G.Item = {
        CreateFromItemID = function(_, itemID)
            return {
                ContinueOnItemLoad = function(_, callback)
                    itemLoadCallbacks[#itemLoadCallbacks + 1] = callback
                    -- Keyed alongside the existing positional list so a test
                    -- can fire a specific item's (ware OR reagent) load
                    -- callback by id, not just by call order.
                    itemLoadCallbacksByID[itemID] = callback
                end,
            }
        end,
    }
    _G.HandyNotes = {
        RegisterPluginDB = function(_, _, handler) registered = handler end,
        getXY = function(_, coord) return math.floor(coord / 10000) / 10000, (coord % 10000) / 10000 end,
    }
    _G.LibStub = function(name)
        libStubCalls = libStubCalls + 1
        if name == "AceDB-3.0" then
            return { New = function() return { profile = { icon_scale = 1, icon_alpha = 1 } } end }
        end
        if name == "HereBeDragons-2.0" then
            return { TranslateZoneCoordinates = function(_, x, y, sourceMapID, targetMapID)
                if hbdTranslation then
                    return hbdTranslation(x, y, sourceMapID, targetMapID)
                end
                return nil
            end }
        end
        return { Embed = function(_, target) target.SendMessage = function() end end }
    end

    assert(loadfile("HandyNotes_Homestead.lua"))("HandyNotes_Homestead", data)
    if frame then frame.scripts.OnEvent(frame) end
    return registered, tooltip, waypoint, function() return mapSelection end, function(value) factionState.value = value end,
        function() return rectangleCalls, rectangleOrder end, forcedZoneOrder, restore, data,
        function(value) itemCached = value end, itemLoadCallbacks, editBoxes, timers, createdFrames,
        function() return hookInstallations end, function() return libStubCalls end, itemLoadCallbacksByID
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

-- Runtime-client coverage only: Retail's actual GetMapRectOnMap returns need
-- live-client verification. The stable rectangles below exercise every shipped key.
local function buildCurrentDataProjectionFixture(data)
    local fixture = { [900] = { mapID = 900, mapType = 2, name = "Fixture continent" } }
    local mapIDs = {}
    for mapID in pairs(data.Nodes) do
        mapIDs[#mapIDs + 1] = mapID
    end
    table.sort(mapIDs)
    for _, mapID in ipairs(mapIDs) do
        fixture[mapID] = { mapID = mapID, mapType = 3, parentMapID = 900, name = "Fixture zone " .. mapID }
    end

    local indexByMapID = {}
    for index, mapID in ipairs(mapIDs) do
        indexByMapID[mapID] = index
    end
    local function rectangleForMap(zoneMapID, continentMapID)
        local index = continentMapID == 900 and indexByMapID[zoneMapID]
        if not index then return nil end
        local column = (index - 1) % 10
        local row = math.floor((index - 1) / 10)
        return column / 10 + 0.01, column / 10 + 0.02, row / 10 + 0.01, row / 10 + 0.02
    end
    return fixture, mapIDs, rectangleForMap
end

local function runCurrentDataProjectionCoverage()
    local data = { Nodes = realData.Nodes, Vendors = realData.Vendors }
    local fixture, mapIDs, rectangleForMap = buildCurrentDataProjectionFixture(data)
    local handler, _, _, _, setFaction, rectangleStats = loadRuntime({}, "Alliance", nil, data, fixture, rectangleForMap)
    local factionRuns = {
        { key = "Alliance", value = "Alliance" },
        { key = "Horde", value = "Horde" },
        { key = "Neutral", value = nil },
    }
    local knownFactions = { Alliance = true, Horde = true, Neutral = true }
    for _, vendor in pairs(data.Vendors) do
        if vendor.faction and not knownFactions[vendor.faction] then
            knownFactions[vendor.faction] = true
            factionRuns[#factionRuns + 1] = { key = vendor.faction, value = vendor.faction }
        end
    end

    for _, faction in ipairs(factionRuns) do
        setFaction(faction.value)
        local summaries = collect(handler, 900, false)
        local emitted = {}
        for _, node in pairs(summaries) do
            local record = node.record
            if type(record) == "table" and record.kind == "zoneSummary" then
                emitted[record.zoneMapID] = true
            end
        end
        local failures = data.ZoneSummaryProjectionFailures and data.ZoneSummaryProjectionFailures[900]
        failures = failures and failures[faction.key] or {}
        for _, mapID in ipairs(mapIDs) do
            local eligible = false
            for _, npcID in pairs(data.Nodes[mapID]) do
                local vendor = data.Vendors[npcID]
                if vendor and (not vendor.faction or vendor.faction == faction.value) then
                    eligible = true
                    break
                end
            end
            if eligible then
                local failure = failures[mapID]
                check(emitted[mapID] or (type(failure) == "string" and #failure > 0), "current-data " .. faction.key .. " zone " .. mapID .. " must emit a summary or a projection failure")
            end
        end
    end

    local _, rectangleOrder = rectangleStats()
    local visited = {}
    for _, mapID in ipairs(rectangleOrder) do
        visited[mapID] = true
    end
    local missing = {}
    for _, mapID in ipairs(mapIDs) do
        if not visited[mapID] then
            missing[#missing + 1] = mapID
        end
    end
    check(#missing == 0, "current-data rectangle seam did not visit map IDs: " .. table.concat(missing, ","))
end

local function runNestedProjectionRegression()
    local data = {
        Nodes = {
            [101] = { [10001000] = 1 },
        },
        Vendors = {
            [1] = { name = "Nested vendor", items = {} },
        },
    }
    local fixture = {
        [900] = { mapID = 900, mapType = 2, name = "Fixture continent" },
        [910] = { mapID = 910, mapType = 3, parentMapID = 900, name = "Fixture sub-continent" },
        [101] = { mapID = 101, mapType = 3, parentMapID = 910, name = "Nested zone" },
    }
    local function adjacentRectangles(sourceMapID, targetMapID)
        if sourceMapID == 101 and targetMapID == 910 then
            return 0.2, 0.4, 0.3, 0.5
        end
        if sourceMapID == 910 and targetMapID == 900 then
            return 0.1, 0.3, 0.2, 0.4
        end
        return nil
    end
    local handler, _, _, _, _, rectangleStats = loadRuntime({}, "Alliance", nil, data, fixture, adjacentRectangles)
    local summaries = collect(handler, 900, false)
    checkSummaryAt(summaries, 16002800, 101, 1)
    local calls, order = rectangleStats()
    check(calls == 2 and order[1] == 101 and order[2] == 910, "nested projection must walk adjacent map parents instead of requesting a direct zone-to-continent rectangle")
end

local function runHBDProjectionFallback()
    local data = {
        Nodes = { [101] = { [10001000] = 1 } },
        Vendors = { [1] = { name = "Fallback vendor", items = {} } },
    }
    local fixture = {
        [900] = { mapID = 900, mapType = 2, name = "Fixture continent" },
        [910] = { mapID = 910, mapType = 3, parentMapID = 900, name = "Fallback sub-continent" },
        [101] = { mapID = 101, mapType = 3, parentMapID = 910, name = "Fallback zone" },
    }
    local function hbdTranslation(_, _, sourceMapID, targetMapID)
        if sourceMapID == 101 and targetMapID == 900 then return 0.6, 0.7 end
    end
    local handler = loadRuntime({}, "Alliance", nil, data, fixture, function() return nil end, hbdTranslation)
    local summaries = collect(handler, 900, false)
    checkSummaryAt(summaries, 60007000, 101, 1)
end

local function runWorldProjectionRegression()
    local data = {
        Nodes = {
            [101] = { [10001000] = 1 },
            [102] = { [20002000] = 2 },
        },
        Vendors = {
            [1] = { name = "World-map vendor one", items = {} },
            [2] = { name = "World-map vendor two", items = {} },
        },
    }
    local fixture = {
        [800] = { mapID = 800, mapType = 1, name = "Fixture world" },
        [900] = { mapID = 900, mapType = 2, parentMapID = 800, name = "Fixture continent" },
        [101] = { mapID = 101, mapType = 3, parentMapID = 900, name = "World-map zone" },
        [102] = { mapID = 102, mapType = 3, parentMapID = 900, name = "Second world-map zone" },
    }
    local function adjacentRectangles(sourceMapID, targetMapID)
        if sourceMapID == 900 and targetMapID == 800 then
            return 0.1, 0.3, 0.2, 0.4
        end
        return nil
    end
    local handler, tooltip, _, selectedMap = loadRuntime({}, "Alliance", nil, data, fixture, adjacentRectangles)
    local summaries = collect(handler, 800, false)
    check(countNodes(summaries) == 1, "world map must emit one consolidated summary per continent")
    local worldSummary = summaries[20003000] and summaries[20003000].record
    check(worldSummary and worldSummary.kind == "continentSummary", "world map must emit a continentSummary record")
    check(worldSummary.mapID == 900 and worldSummary.vendorCount == 2, "world continent summary must identify the continent and aggregate its visible vendors")
    local pin = { GetCenter = function() return 0 end }
    handler.OnEnter(pin, 800, 20003000)
    check(tooltip.lines[1] == "Fixture continent" and tooltip.lines[2] == "2 vendors" and tooltip.lines[3] == "Click to view continent", "world continent summary tooltip must identify the continent and aggregate count")
    handler.OnClick(pin, "LeftButton", false, 800, 20003000)
    check(selectedMap() == 900, "world continent summary click must open the continent map")
end

local function runHomesteadGeographyRegression()
    local data = {
        Nodes = {
            [101] = { [10001000] = 1 },
            [102] = { [20002000] = 2 },
            [103] = { [30003000] = 3 },
            [2405] = { [40004000] = 4 },
            [2599] = { [50005000] = 5 },
            [2444] = { [60006000] = 6 },
            [2694] = { [70007000] = 7 },
            [2576] = { [80008000] = 8 },
            [2512] = { [90009000] = 9 },
            [2509] = { [10001000] = 10 },
        },
        Vendors = {
            [1] = { name = "Broken Isles vendor", items = {} },
            [2] = { name = "Argus vendor", items = {} },
            [3] = { name = "Quel'Thalas vendor", items = {} },
            [4] = { name = "Voidstorm vendor", items = {} },
            [5] = { name = "Val vendor", items = {} },
            [6] = { name = "Slayer's Rise vendor", items = {} },
            [7] = { name = "Harandar vendor", items = {} },
            [8] = { name = "The Den vendor", items = {} },
            [9] = { name = "Coiled Isle vendor", items = {} },
            [10] = { name = "Vault vendor", items = {} },
        },
    }
    local fixture = {
        [800] = { mapID = 800, mapType = 1, name = "Fixture world" },
        [619] = { mapID = 619, mapType = 2, parentMapID = 800, name = "Broken Isles" },
        [905] = { mapID = 905, mapType = 2, parentMapID = 800, name = "Argus" },
        [13] = { mapID = 13, mapType = 2, parentMapID = 800, name = "Eastern Kingdoms" },
        [2537] = { mapID = 2537, mapType = 2, parentMapID = 13, name = "Quel'Thalas" },
        [101] = { mapID = 101, mapType = 3, parentMapID = 619, name = "Broken Isles zone" },
        [102] = { mapID = 102, mapType = 3, parentMapID = 905, name = "Argus zone" },
        [103] = { mapID = 103, mapType = 3, parentMapID = 2537, name = "Quel'Thalas zone" },
        [2405] = { mapID = 2405, mapType = 3, parentMapID = 2537, name = "Voidstorm" },
        [2599] = { mapID = 2599, mapType = 3, parentMapID = 2537, name = "Val" },
        [2444] = { mapID = 2444, mapType = 3, parentMapID = 2537, name = "Slayer's Rise" },
        [2694] = { mapID = 2694, mapType = 3, parentMapID = 2537, name = "Harandar" },
        [2576] = { mapID = 2576, mapType = 3, parentMapID = 2537, name = "The Den" },
        [2512] = { mapID = 2512, mapType = 3, parentMapID = 2537, name = "The Coiled Isle" },
        [2509] = { mapID = 2509, mapType = 3, parentMapID = 2512, name = "Vault of Atal'Utek" },
    }
    local function adjacentRectangles(sourceMapID, targetMapID)
        if targetMapID == 800 and sourceMapID == 619 then return 0.1, 0.3, 0.2, 0.4 end
        if targetMapID == 800 and sourceMapID == 13 then return 0.5, 0.7, 0.6, 0.8 end
        if targetMapID == 619 and sourceMapID == 101 then return 0.1, 0.3, 0.2, 0.4 end
        if targetMapID == 13 and sourceMapID == 2537 then return 0.1, 0.3, 0.2, 0.4 end
        if targetMapID == 2537 and sourceMapID == 103 then return 0.5, 0.7, 0.6, 0.8 end
        if targetMapID == 2537 and sourceMapID == 2405 then return 0.2, 0.4, 0.3, 0.5 end
        if targetMapID == 2537 and sourceMapID == 2599 then return 0.6, 0.8, 0.7, 0.9 end
        if targetMapID == 2537 and sourceMapID == 2444 then return 0.3, 0.5, 0.4, 0.6 end
        if targetMapID == 2537 and sourceMapID == 2576 then return 0.8, 0.9, 0.3, 0.5 end
        if targetMapID == 2537 and sourceMapID == 2576 then return 0.75, 0.9, 0.2, 0.35 end
        if targetMapID == 2537 and sourceMapID == 2413 then return 0.75, 0.9, 0.2, 0.35 end
        if targetMapID == 2537 and sourceMapID == 2512 then return 0.65, 0.8, 0.45, 0.6 end
        if targetMapID == 2512 and sourceMapID == 2509 then return 0.5, 0.7, 0.5, 0.7 end
    end
    local handler = loadRuntime({}, "Alliance", nil, data, fixture, adjacentRectangles)
    local world = collect(handler, 800, false)
    check(countNodes(world) == 2, "world geography must consolidate Argus into Broken Isles and Quel'Thalas into Eastern Kingdoms")
    check(world[20003000] and world[20003000].record.vendorCount == 2, "world Broken Isles summary must include Argus vendors")
    local easternWorldSummary
    for _, node in pairs(world) do
        if node.record.mapID == 13 then easternWorldSummary = node.record end
    end
    local worldMapIDs = {}
    for _, node in pairs(world) do worldMapIDs[#worldMapIDs + 1] = tostring(node.record.mapID) end
    check(easternWorldSummary, "world Eastern Kingdoms summary must include Quel'Thalas vendors: " .. table.concat(worldMapIDs, ","))
    local easternKingdoms = collect(handler, 13, false)
    local easternZoneSummary
    for _, node in pairs(easternKingdoms) do
        if node.record.zoneMapID == 103 then easternZoneSummary = node.record end
    end
    check(countNodes(easternKingdoms) == 1 and easternZoneSummary, "Eastern Kingdoms view must show the Quel'Thalas overlay zone")
    local quelThalas = collect(handler, 2537, false)
    local voidstormSummary
    for _, node in pairs(quelThalas) do
        if node.record.zoneMapID == 2405 then voidstormSummary = node.record end
    end
    check(voidstormSummary, "Quel'Thalas map must retain its native Voidstorm zone summary")
    check(countNodes(quelThalas) == 4, "Quel'Thalas map must consolidate the Midnight sub-zone clusters")
    local voidstormCount = 0
    local harandarCount = 0
    for _, node in pairs(quelThalas) do
        if node.record.zoneMapID == 2405 then voidstormCount = node.record.vendorCount end
        if node.record.zoneMapID == 2694 then harandarCount = node.record.vendorCount end
    end
    check(voidstormCount == 3 and harandarCount == 2, "Quel'Thalas cluster badges must aggregate Voidstorm/Val/Slayer's Rise and Harandar/The Den")
    local coiledCount = 0
    for _, node in pairs(quelThalas) do
        if node.record.zoneMapID == 2512 then coiledCount = node.record.vendorCount end
    end
    check(coiledCount == 2, "The Coiled Isle badge must include the Vault of Atal'Utek child map, got " .. tostring(coiledCount))
end

local function findCreatedFrame(createdFrames, name)
    for _, created in ipairs(createdFrames) do
        if created.name == name then return created end
    end
end

local function visibleFrameText(frame)
    local lines = {}
    for _, line in ipairs(frame.lines or {}) do lines[#lines + 1] = line end
    for _, line in ipairs(frame.fontStrings) do
        if line.shown and line.text then lines[#lines + 1] = line.text end
    end
    if frame.content then
        for _, line in ipairs(frame.content.fontStrings) do
            if line.shown and line.text then lines[#lines + 1] = line.text end
        end
    end
    return table.concat(lines, "\n")
end

local function runVendorTooltipSearch()
    local shortItems = {}
    for itemID = 1, 15 do shortItems[#shortItems + 1] = { id = itemID } end
    local shortData = {
        Nodes = { [101] = { [10001000] = 1 } },
        Vendors = { [1] = { name = "Short vendor", items = shortItems } },
    }
    local shortRuntime = { loadRuntime({}, "Alliance", nil, shortData) }
    local shortHandler, sharedTooltip, _, _, _, _, _, shortRestore, _, _, _, shortEditBoxes, _, shortFrames, shortHookCount = unpack(shortRuntime)
    local shortPin = _G.CreateFrame("Button")
    shortHandler.OnEnter(shortPin, 101, 10001000)
    local plainTooltip = findCreatedFrame(shortFrames, "HandyNotesHomesteadTooltip")
    check(plainTooltip and plainTooltip.frameType == "GameTooltip" and plainTooltip.template == "GameTooltipTemplate",
        "15 wares must use HNH's dedicated plain GameTooltip")
    check(plainTooltip.owner == shortPin and plainTooltip.strata == "TOOLTIP" and plainTooltip.clamped,
        "plain tooltip must be tooltip-strata, clamped, and owned by its pin")
    check(#shortEditBoxes == 0 and not findCreatedFrame(shortFrames, "HandyNotesHomesteadWaresTooltip"),
        "plain path must not create the interactive frame or search box")
    check(not string.find(table.concat(plainTooltip.lines, "\n"), "Search wares...", 1, true),
        "plain tooltip must not render search controls")
    check(sharedTooltip.hookInstallations == 0 and shortHookCount() == 2,
        "plain path must install exactly its pin-hide and map-hide teardown hooks, and none on the shared GameTooltip")
    shortHandler.OnLeave(shortPin, 101, 10001000)
    check(not plainTooltip.shown, "plain tooltip must hide as soon as its pin is left")

    shortHandler.OnEnter(shortPin, 101, 10001000)
    check(plainTooltip.shown, "re-hovering a short vendor must reopen the plain tooltip")
    check(shortPin.scripts.OnHide, "plain path must hook its pin's OnHide")
    shortPin.scripts.OnHide(shortPin)
    check(not plainTooltip.shown, "hiding a short vendor's pin must hide the plain tooltip")
    plainTooltip.shown = true
    shortHandler.OnLeave(shortPin, 101, 10001000)
    check(plainTooltip.shown, "hiding the pin must clear the hover token, leaving OnLeave nothing to close")

    shortHandler.OnEnter(shortPin, 101, 10001000)
    check(_G.WorldMapFrame.scripts.OnHide, "plain path must hook the world map's OnHide")
    _G.WorldMapFrame.scripts.OnHide(_G.WorldMapFrame)
    check(not plainTooltip.shown, "hiding the map must hide the plain tooltip")
    check(shortHookCount() == 2, "plain-path teardown hooks must install once, not once per hover")
    shortRestore()

    local longItems = {}
    for itemID = 1, 16 do
        longItems[#longItems + 1] = { id = itemID, currencies = { { id = itemID == 1 and 100 or 200, amount = itemID } } }
    end
    local data = {
        Nodes = { [101] = { [10001000] = 1, [20002000] = 2, [30003000] = 3, [40004000] = 4 } },
        Vendors = {
            [1] = {
                name = "Search vendor",
                items = longItems,
            },
            [2] = { name = "Retarget vendor", items = longItems },
            [3] = { name = "Short retarget vendor", items = shortItems },
            [4] = { name = "Forty ware vendor", items = {} },
        },
    }
    local itemNames = { [1] = "Crystal Vase", [2] = "Weathered Banner" }
    for itemID = 3, 40 do itemNames[itemID] = "Ware " .. itemID end
    for itemID = 1, 40 do data.Vendors[4].items[#data.Vendors[4].items + 1] = { id = itemID } end
    local currencyNames = { [100] = "Trader's Tender", [200] = "Honor" }
    local runtime = {
        loadRuntime({}, "Alliance", nil, data, nil, nil, nil, nil, itemNames, currencyNames),
    }
    local handler, tooltip, _, _, _, _, _, restore, _, setItemCached, itemLoadCallbacks, editBoxes, timers, createdFrames, hookCount = unpack(runtime)
    local pin = _G.CreateFrame("Button")
    handler.OnEnter(pin, 101, 10001000)
    check(hookCount() == 2, "the first long hover must install exactly its pin-hide and map-hide teardown hooks")
    local interactive = findCreatedFrame(createdFrames, "HandyNotesHomesteadWaresTooltip")
    check(interactive and interactive.frameType == "GameTooltip" and interactive.template == "GameTooltipTemplate"
        and interactive.mouseEnabled, "16 wares must use HNH's own GameTooltip so it looks like the plain one")
    check(interactive.owner == pin, "interactive tooltip must be owned by its pin")
    local anchor = interactive.points and interactive.points[1]
    check(anchor and anchor[1] == "TOPLEFT" and anchor[2] == pin and anchor[3] == "TOPRIGHT",
        "interactive tooltip must butt against the pin's edge so the cursor can cross onto it")
    check(#interactive.points == 1 and interactive.anchorPin == nil,
        "the anchor is decided once, after the first render, not on every render")
    check(interactive.strata == "TOOLTIP" and interactive.clamped and interactive.shown,
        "interactive frame must be tooltip-strata, clamped, and visible")
    local scrolling
    for _, created in ipairs(createdFrames) do
        if created.frameType == "ScrollFrame" then scrolling = created end
    end
    check(not scrolling, "interactive tooltip must render a window of tooltip lines, not a scroll frame")
    local scrollBar = interactive.scrollBar
    check(scrollBar and scrollBar.template == "MinimalScrollBar" and scrollBar.parent == interactive,
        "interactive tooltip must carry a MinimalScrollBar")
    check(scrollBar.shown and interactive.padding and interactive.padding.right > 0 and interactive.padding.bottom > 0,
        "a scrollable list must show the bar and reserve tooltip padding for bar and search box")
    check(interactive.minimumWidth and interactive.minimumWidth > 0, "interactive tooltip must pin a minimum width")
    check(#editBoxes == 1, "interactive path must create one reusable search input")
    check(tooltip.hookInstallations == 0, "interactive path must not hook the shared GameTooltip")

    local searchBox = editBoxes[1]
    check(searchBox.parent == interactive and searchBox.points[1][3] == "BOTTOMLEFT",
        "search input must stay at the bottom of the interactive frame")
    check(string.find(visibleFrameText(interactive), "Search vendor", 1, true),
        "interactive tooltip must render its vendor header")
    check(searchBox.template == "SearchBoxTemplate" and searchBox.Instructions.text == "Search wares...",
        "search box must be Blizzard's SearchBoxTemplate with HNH's placeholder")
    check(string.find(visibleFrameText(interactive), "Wares:", 1, true),
        "interactive tooltip must render the same Wares: header as the plain tooltip")
    check(pin.scripts.OnHide, "interactive tooltip must close when its pin hides")
    interactive.scripts.OnMouseWheel(interactive, -1)
    check(interactive.scrollOffset == 1 and string.find(visibleFrameText(interactive), "Ware 16", 1, true),
        "a 16-item vendor must show ware 16 after scrolling to the end")
    check(scrollBar.scrollPercentage == 1, "wheel scrolling must move the scroll bar thumb")
    -- Width is measured from one full-list render per vendor (2 ClearLines on
    -- the first render), then frozen: each wheel tick is a single window render
    -- that re-applies the measured width rather than re-measuring.
    check(interactive.clearCalls == 3, "first render measures once; a wheel tick renders once, got " .. tostring(interactive.clearCalls))
    interactive.width = 333
    interactive.scripts.OnMouseWheel(interactive, -1)
    check(interactive.clearCalls == 3 and interactive.scrollOffset == 1,
        "a wheel tick already at the end must not re-render")
    local setsBefore = scrollBar.scrollSets
    scrollBar:SetScrollPercentage(0)
    check(interactive.scrollOffset == 0 and string.find(visibleFrameText(interactive), "Ware 1", 1, true)
        and scrollBar.scrollSets == setsBefore + 2,
        "dragging the scroll bar must re-render the window once (the nested OnScroll from the bar sync is a no-op)")
    check(interactive.clearCalls == 4 and interactive.minimumWidth == 300,
        "scrolling must reuse the width measured at open, not re-measure")
    -- Holding the thumb fires OnScroll every frame at the same percentage.
    for _ = 1, 30 do scrollBar:SetScrollPercentage(0) end
    check(interactive.clearCalls == 4 and interactive.scrollOffset == 0,
        "an OnScroll that resolves to the current row offset must not re-render")
    interactive.scripts.OnMouseWheel(interactive, 1)
    check(interactive.clearCalls == 4, "a wheel tick already at the top must not re-render")
    check(interactive.padding.right >= 24,
        "right padding must fit MinimalScrollBar's 17px stepper arrows, not just its 8px track")

    interactive.mouseOver = true
    handler.OnLeave(pin, 101, 10001000)
    check(interactive.shown, "pin leave must keep the frame open while the cursor crosses onto it")
    interactive.mouseOver = nil
    -- A narrowing search shrinks the tooltip away from a stationary cursor;
    -- focus in the search box must hold it open until focus is gone.
    searchBox.focused = true
    interactive.scripts.OnLeave(interactive)
    check(interactive.shown and searchBox.focused, "a focused search box must hold the tooltip open through a leave")
    searchBox:ClearFocus()
    check(not interactive.shown and searchBox.templateFocusLost == 1,
        "losing search focus off the tooltip must close it via the template's own focus-lost handler")
    handler.OnEnter(pin, 101, 10001000)
    searchBox.focused = true
    interactive.mouseOver = true
    searchBox:ClearFocus()
    check(interactive.shown, "losing search focus while still over the tooltip must leave it open")
    interactive.mouseOver = nil
    check(interactive.scripts.OnLeave, "interactive frame must close when its own cursor leaves")
    searchBox.focused = nil
    interactive.scripts.OnLeave(interactive)
    check(not interactive.shown and not searchBox.focused,
        "interactive frame leave without search focus must close the frame")

    handler.OnEnter(pin, 101, 10001000)
    searchBox.focused = true
    pin.scripts.OnHide(pin)
    check(not interactive.shown and not searchBox.focused,
        "hiding the pin must close the frame and clear search focus")

    handler.OnEnter(pin, 101, 10001000)
    searchBox.focused = true
    local retargetPin = _G.CreateFrame("Button")
    handler.OnEnter(retargetPin, 101, 20002000)
    check(interactive.shown and not searchBox.focused,
        "re-targeting must clear search focus before reusing the frame")

    searchBox.focused = true
    WorldMapFrame.scripts.OnHide(WorldMapFrame)
    check(not interactive.shown and not searchBox.focused,
        "hiding the map must close the frame and clear search focus")

    handler.OnEnter(pin, 101, 10001000)
    searchBox.focused = true
    handler.OnEnter(_G.CreateFrame("Button"), 101, 30003000)
    check(not interactive.shown and not searchBox.focused,
        "opening a short vendor must close the long frame and clear search focus")

    handler.OnEnter(pin, 101, 10001000)
    searchBox.focused = nil
    check(interactive.scripts.OnKeyDown, "interactive frame must receive keys without search focus")
    check(interactive.keyboardEnabled == true, "interactive frame must take keyboard input from creation")
    searchBox:SetText("weathered")
    interactive.scripts.OnKeyDown(interactive, "A")
    local calls = interactive.propagateCalls
    check(interactive.shown and calls[#calls] == true,
        "an ordinary key must pass through to the game and leave the tooltip open")
    interactive.scripts.OnKeyDown(interactive, "ESCAPE")
    calls = interactive.propagateCalls
    check(not interactive.shown and calls[#calls] == false,
        "frame-level Escape must consume the key and close the tooltip")

    handler.OnEnter(pin, 101, 10001000)
    searchBox.focused = true
    searchBox.scripts.OnEscapePressed(searchBox)
    check(not interactive.shown and not searchBox.focused, "search-box Escape must close the frame and drop focus")

    handler.OnEnter(pin, 101, 10001000)
    searchBox.focused = true
    interactive.mouseOver = true -- the cursor is on the box when Enter is pressed
    searchBox.scripts.OnEnterPressed(searchBox)
    check(not searchBox.focused and interactive.shown, "Enter must drop search focus and keep the tooltip open")

    searchBox:SetText("trad")
    searchBox:SetText("tender")
    check(searchBox.templateTextChanged and searchBox.templateTextChanged >= 2,
        "search box text changes must still run SearchBoxTemplate's own handler (icon/clear button)")
    check(#timers == 3 and timers[2].timer.cancelled, "vendor tooltip search must debounce obsolete queries")
    timers[3].callback()
    local tenderLines = visibleFrameText(interactive)
    check(string.find(tenderLines, "Crystal Vase", 1, true), "currency query must retain the matching ware")
    check(not string.find(tenderLines, "Weathered Banner", 1, true), "currency query must exclude non-matching wares")

    searchBox:SetText("weathered")
    timers[4].callback()
    local itemLines = visibleFrameText(interactive)
    check(string.find(itemLines, "Weathered Banner", 1, true), "item-name query must retain the matching ware")
    check(not string.find(itemLines, "Crystal Vase", 1, true), "item-name query must exclude non-matching wares")

    searchBox:SetText("missing")
    timers[5].callback()
    check(string.find(visibleFrameText(interactive), "No matching wares", 1, true),
        "no-match query must report the empty result")
    check(not scrollBar.shown and interactive.padding.right == 0,
        "a list that fits must hide the scroll bar and drop its padding")

    handler.OnEnter(retargetPin, 101, 20002000)
    check(interactive.shown and string.find(visibleFrameText(interactive), "Retarget vendor", 1, true),
        "entering another pin must retarget the reusable interactive frame")
    check(searchBox.text == "", "re-opening or retargeting must clear the search text")
    local fortyPin = _G.CreateFrame("Button")
    handler.OnEnter(fortyPin, 101, 40004000)
    for _ = 1, 40 do interactive.scripts.OnMouseWheel(interactive, -1) end
    check(interactive.scrollOffset == 25 and string.find(visibleFrameText(interactive), "Ware 40", 1, true),
        "a 40-item vendor must show ware 40 after scrolling to the end")

    -- A pin low on the screen: hanging ~300px down from its top would overhang
    -- the screen and clamping would slide the tooltip off the pin. It must
    -- rise from the pin's bottom instead, in screen pixels (canvas pins are scaled).
    local lowPin = _G.CreateFrame("Button")
    -- 400 pin units at scale 0.5 = 200 screen px: unscaled it would (wrongly) look like room for 300.
    lowPin.top = 400; lowPin.effectiveScale = 0.5
    interactive.height = 300
    handler.OnEnter(lowPin, 101, 40004000)
    anchor = interactive.points[1]
    check(#interactive.points == 1 and anchor[1] == "BOTTOMLEFT" and anchor[2] == lowPin and anchor[3] == "BOTTOMRIGHT",
        "a pin without room below (in screen pixels, pin scale applied) must anchor the tooltip rising from its bottom")
    -- 350 screen px of room for a 300-unit tooltip that is drawn at scale 1.2 = 360 px: still no room.
    lowPin.top = 350; lowPin.effectiveScale = 1
    interactive.effectiveScale = 1.2
    handler.OnEnter(lowPin, 101, 40004000)
    check(interactive.points[1][1] == "BOTTOMLEFT", "the tooltip's own scale must count toward the height it needs")
    interactive.effectiveScale = 1
    handler.OnEnter(lowPin, 101, 40004000)
    check(interactive.points[1][1] == "TOPLEFT", "a pin with room below hangs the tooltip down from its top edge")
    -- Height not valid on the first render: hold the anchor decision for a later render, do not re-anchor after.
    lowPin.top = 400; lowPin.effectiveScale = 0.5
    interactive.height = 0
    handler.OnEnter(lowPin, 101, 40004000)
    check(interactive.anchorPin == lowPin and interactive.points[1][1] == "TOPLEFT",
        "a zero height must not decide the anchor; the pin is held for a later render")
    interactive.height = 300
    interactive.scripts.OnMouseWheel(interactive, -1)
    check(interactive.anchorPin == nil and interactive.points[1][1] == "BOTTOMLEFT",
        "the first render with a usable height anchors by room")
    interactive.scripts.OnMouseWheel(interactive, -1)
    check(#interactive.points == 1, "later renders must not re-anchor")

    -- Width measure: query-independent and keyed on resolved names.
    interactive.width = 333
    handler.OnEnter(retargetPin, 101, 20002000)
    check(interactive.minimumWidth == 333, "a fresh vendor hover re-measures the width")
    local clears = interactive.clearCalls
    searchBox:SetText("nothing-matches")
    timers[#timers].callback()
    check(string.find(visibleFrameText(interactive), "No matching wares", 1, true)
        and interactive.minimumWidth == 333 and interactive.clearCalls == clears + 1,
        "a search must neither re-measure nor narrow the frozen width")
    interactive.width = 0
    handler.OnEnter(fortyPin, 101, 40004000)
    check(interactive.minimumWidth == 240 and interactive.measuredVendor == nil,
        "a zero width measurement must not be frozen; the next render measures again")
    interactive.width = 400
    interactive.scripts.OnMouseWheel(interactive, -1)
    check(interactive.minimumWidth == 400, "after a zero measurement the next render re-measures")

    -- Cold names plus a query typed mid-load: the re-measure when names arrive
    -- must render every ware, not the matches, or a narrow width is frozen.
    interactive.width = nil
    interactive.GetWidth = function(self)
        local chars = 0
        for _, line in ipairs(self.lines) do chars = chars + #line end
        return 200 + chars
    end
    handler.OnEnter(retargetPin, 101, 20002000)
    handler.OnEnter(fortyPin, 101, 40004000)
    local fullWidth = interactive.minimumWidth
    setItemCached(false)
    handler.OnEnter(retargetPin, 101, 20002000)
    local loadsBefore = #itemLoadCallbacks
    handler.OnEnter(fortyPin, 101, 40004000)
    check(#itemLoadCallbacks == loadsBefore + 40, "a cold 40-ware hover registers one load callback per ware")
    check(interactive.minimumWidth < fullWidth, "unresolved names measure narrower than the real names")
    searchBox:SetText("ware 4")
    timers[#timers].callback()
    setItemCached(true)
    clears = interactive.clearCalls
    itemLoadCallbacks[loadsBefore + 1]()
    check(interactive.clearCalls == clears + 2 and interactive.minimumWidth == fullWidth,
        "names arriving mid-search must re-measure once from every ware, ignoring the query")
    itemLoadCallbacks[loadsBefore + 2]()
    check(interactive.clearCalls == clears + 3, "a further load callback with no new names must not re-measure")
    WorldMapFrame.scripts.OnHide(WorldMapFrame)
    check(not interactive.shown, "hiding the map must close the interactive frame")
    check(hookCount() == 6,
        "the interactive path must install one pin-hide hook per hovered pin (pin, retarget, the short-vendor pin, forty, low) plus the single shared map-hide hook")
    restore()
end

-- HNH-021: item-based costs (reagent items, e.g. Spare Parts, Polished Pet
-- Charms) render like Homestead itself — a resolved icon, a resolved name
-- fallback, or the honest "(other cost)" marker, never the raw item ID —
-- and match tooltip search by the reagent's name.

-- Finds the first frame line whose text starts with `prefix` (exact-match
-- helper, not a substring find, so a stray appended marker is caught).
local function findLine(frame, prefix)
    for _, line in ipairs(frame.lines) do
        if type(line) == "string" and line:sub(1, #prefix) == prefix then
            return line
        end
    end
end

local function runVendorCostRender()
    local wareIcon = { id = 500, price = 12345, currencies = { { id = 3392, amount = 25 } }, items = { { id = 777, amount = 3 } } }
    local wareName = { id = 501, price = 100, items = { { id = 778, amount = 3 } } }
    local wareUnknown = { id = 502, price = 100, items = { { id = 779, amount = 3 } } }
    local wareOtherCost = { id = 503, otherCost = true }
    local wareNoReagent = { id = 504, price = 50 }
    local items = { wareIcon, wareName, wareUnknown, wareOtherCost, wareNoReagent }
    -- Padding pushes the vendor past LONG_WARES_THRESHOLD so the interactive
    -- tooltip (with its search box) renders, not the plain path.
    for itemID = 600, 615 do items[#items + 1] = { id = itemID, price = 1 } end

    local data = {
        Nodes = { [101] = { [10001000] = 1 } },
        Vendors = { [1] = { name = "Cost render vendor", items = items } },
    }
    local itemNames = {
        [500] = "Ware Icon", [501] = "Ware Name", [502] = "Ware Unknown",
        [503] = "Ware Other Cost", [504] = "Ware No Reagent",
        [778] = "Polished Pet Charm",
    }
    local itemIcons = { [777] = 4242 }
    local currencyNames = { [3392] = "Trader's Tender" }
    local handler, _, _, _, _, _, _, restore, _, _, _, editBoxes, timers, createdFrames =
        loadRuntime({}, "Alliance", nil, data, nil, nil, nil, nil, itemNames, currencyNames, itemIcons)
    local pin = _G.CreateFrame("Button")
    handler.OnEnter(pin, 101, 10001000)
    local interactive = findCreatedFrame(createdFrames, "HandyNotesHomesteadWaresTooltip")
    check(interactive, "cost-render vendor must use the interactive tooltip")

    -- (a)/(e): a resolved icon renders "<amount> |T<icon>:0:0|t"; ordering
    -- is gold, then currency, then item, joined by " + " — and nothing
    -- trails it (exact match, not a substring find, so a stray appended
    -- marker would be caught).
    local iconLine = findLine(interactive, "Ware Icon")
    check(iconLine == "Ware Icon12345 + 25 Trader's Tender + 3 |T4242:0:0|t",
        "resolved-icon cost must render gold + currency + item in that order and nothing else, got " .. tostring(iconLine))

    -- (b): no icon but a resolved name -> "<amount> <name>".
    local nameLine = findLine(interactive, "Ware Name")
    check(nameLine == "Ware Name100 + 3 Polished Pet Charm",
        "an unresolved icon with a resolved name must render the reagent's name, got " .. tostring(nameLine))

    -- (c): neither icon nor name -> the honest marker, never the raw item ID.
    local unknownLine = findLine(interactive, "Ware Unknown")
    check(unknownLine == "Ware Unknown100 + |cFFB3B3B3(other cost)|r",
        "a reagent with neither icon nor name must fall back to the other-cost marker, got " .. tostring(unknownLine))
    check(not (unknownLine and string.find(unknownLine, "779", 1, true)), "the raw reagent item ID must never reach the tooltip")

    -- (d): a namedCosts-only row (otherCost, no price/currencies/items) still renders the marker.
    local otherCostLine = findLine(interactive, "Ware Other Cost")
    check(otherCostLine == "Ware Other Cost|cFFB3B3B3(other cost)|r",
        "an otherCost-only row must still render the other-cost marker, got " .. tostring(otherCostLine))

    -- (f): reagent-name search keeps a ware carrying that reagent and hides
    -- a ware with no reagent cost at all.
    local searchBox = editBoxes[1]
    searchBox:SetText("polished")
    timers[#timers].callback()
    local searched = visibleFrameText(interactive)
    check(string.find(searched, "Ware Name", 1, true), "reagent-name search must keep a ware carrying that reagent")
    check(not string.find(searched, "Ware No Reagent", 1, true), "reagent-name search must hide a ware with no matching reagent")

    restore()
end

-- HNH-021 round 2 (Argus Critical 1): a reagent cost degraded on first
-- render (no icon, no name) must never freeze — it must request the item's
-- data and self-correct once it resolves, exactly like the ware-name path
-- already does. Plain-tooltip coverage.
local function runVendorCostRenderColdToWarm()
    local ware = { id = 900, price = 50, items = { { id = 779, amount = 3 } } }
    local itemIcons = {}
    local data = {
        Nodes = { [101] = { [10001000] = 1 } },
        Vendors = { [1] = { name = "Cold reagent vendor", items = { ware } } },
    }
    local itemNames = { [900] = "Cold Ware" }
    local handler, _, _, _, _, _, _, restore, _, _, itemLoadCallbacks, _, _, createdFrames, _, _, itemLoadCallbacksByID =
        loadRuntime({}, "Alliance", nil, data, nil, nil, nil, nil, itemNames, nil, itemIcons)

    local pin = _G.CreateFrame("Button")
    handler.OnEnter(pin, 101, 10001000)
    local plainTooltip = findCreatedFrame(createdFrames, "HandyNotesHomesteadTooltip")
    check(plainTooltip, "single-ware cost-render vendor must use the plain tooltip")
    local coldLine = findLine(plainTooltip, "Cold Ware")
    check(coldLine == "Cold Ware50 + |cFFB3B3B3(other cost)|r",
        "a cold reagent must render the marker on first hover, got " .. tostring(coldLine))
    check(itemLoadCallbacksByID[779],
        "a load must be requested for the cold reagent (A2) — none was recorded")

    -- Warm the reagent up (as if its data just arrived) and fire its
    -- recorded load callback exactly the way RequestItemLoad's
    -- ContinueOnItemLoad handler would.
    itemIcons[779] = 4242
    local loadsBefore = #itemLoadCallbacks
    itemLoadCallbacksByID[779]()
    check(#itemLoadCallbacks == loadsBefore, "firing an existing load callback must not register a new one")
    local warmLine = findLine(plainTooltip, "Cold Ware")
    check(warmLine == "Cold Ware50 + 3 |T4242:0:0|t",
        "a resolved reagent must self-correct on the triggered re-render instead of staying frozen, got " .. tostring(warmLine))
    check(ware.costCache == "50 + 3 |T4242:0:0|t",
        "a fully resolved cost must now be memoized, got " .. tostring(ware.costCache))

    restore()
end

-- Same scenario on the interactive path: a reagent resolving after the
-- tooltip's width was measured must trigger a re-measure, not leave the
-- frozen (narrower) width in place (Argus Major 1, round 2).
local function runVendorCostRenderInteractiveRemeasure()
    local coldWare = { id = 900, price = 50, items = { { id = 779, amount = 3 } } }
    local items = { coldWare }
    for itemID = 700, 715 do items[#items + 1] = { id = itemID, price = 1 } end
    local itemIcons = {}
    local data = {
        Nodes = { [101] = { [10001000] = 1 } },
        Vendors = { [1] = { name = "Cold reagent interactive vendor", items = items } },
    }
    local itemNames = { [900] = "Cold Ware" }
    local handler, _, _, _, _, _, _, restore, _, _, _, _, _, createdFrames, _, _, itemLoadCallbacksByID =
        loadRuntime({}, "Alliance", nil, data, nil, nil, nil, nil, itemNames, nil, itemIcons)

    local pin = _G.CreateFrame("Button")
    handler.OnEnter(pin, 101, 10001000)
    local interactive = findCreatedFrame(createdFrames, "HandyNotesHomesteadWaresTooltip")
    check(interactive, "17-item vendor must use the interactive tooltip")
    local measuredBefore = interactive.minimumWidth
    check(itemLoadCallbacksByID[779],
        "a load must be requested for the cold reagent on the interactive path")

    -- Resolve the reagent (would widen the rendered cost column) and fire
    -- its callback; a bumped mock width proves whether a re-measure ran.
    itemIcons[779] = 4242
    interactive.width = measuredBefore + 500
    itemLoadCallbacksByID[779]()
    check(interactive.minimumWidth == measuredBefore + 500,
        "a reagent resolving after the width was measured must trigger a re-measure, got " .. tostring(interactive.minimumWidth))

    restore()
end

local function run()
    local standalone = { loadRuntime({}, "Alliance") }
    check(standalone[1], "standalone registration did not capture a plugin handler")
    check(standalone[2].hookInstallations == 0,
        "standalone load must not install shared-tooltip hooks")
    standalone[8]()
    -- Every LibStub call in the file sits past the login guard, so a zero call
    -- count is what actually separates the no-op path from a live load; the
    -- checks run before the registration check so a disabled guard trips them.
    local homestead = { loadRuntime({ Homestead = true }, "Alliance") }
    check(homestead[2].hookInstallations == 0 and homestead[15]() == 0 and homestead[16]() == 0,
        "Homestead-enabled path installed a hook or initialized its libraries past its login listener")
    check(not homestead[1], "Homestead-enabled path registered the plugin")
    homestead[8]()
    local devBuild = { loadRuntime({ Homestead_DevBuild = true }, "Alliance") }
    check(devBuild[2].hookInstallations == 0 and devBuild[15]() == 0 and devBuild[16]() == 0,
        "Homestead_DevBuild-enabled path installed a hook or initialized its libraries past its login listener")
    check(not devBuild[1], "Homestead_DevBuild-enabled path registered the plugin")
    devBuild[8]()

    local handler, tooltip, waypoint, selectedMap, setFaction, rectangleStats, forcedZoneOrder, _, data, setItemCached, itemLoadCallbacks, _, _, createdFrames = loadRuntime({}, "Alliance")
    local adjustedSize, iconSize = handler:GetSummaryVisualSizes(1)
    check(adjustedSize == 11 and iconSize == 13, "summary badge must use slightly enlarged Homestead-sized world icon geometry")
    local strata, frameLevel = handler:GetSummaryFrameLayering()
    check(strata == "MEDIUM" and frameLevel == 2024, "summary badge must render above Blizzard Area POIs")
    check(handler:GetMinimapPinScale() == 1.15, "minimap vendor pins must use the enlarged scale")
    check(not handler:IsProfessionVendorVisible(256026), "Irodalmin must be hidden without Herbalism")
    local herbalismRuntime = { loadRuntime({}, "Alliance", nil, nil, nil, nil, nil, 182) }
    check(herbalismRuntime[1]:IsProfessionVendorVisible(256026), "Irodalmin must be visible with Herbalism")
    herbalismRuntime[8]()
    check(forcedZoneOrder[1] == 102 and forcedZoneOrder[2] == 101, "collision fixture must enumerate zones out of sorted order")
    local zoneNodes = collect(handler, 101, false)
    local zoneVendor = zoneNodes[10001000]
    check(zoneVendor and type(zoneVendor.record) == "number", "zone vendor at 10001000 expected numeric record, got " .. tostring(zoneVendor and zoneVendor.record))
    local pin = { GetCenter = function() return 0 end }
    handler.OnEnter(pin, 101, 10001000)
    local plainTooltip = findCreatedFrame(createdFrames, "HandyNotesHomesteadTooltip")
    check(plainTooltip and plainTooltip.lines[1] == "Alliance vendor" and plainTooltip.lines[4] == "Wares:" and plainTooltip.lines[5] == "Cached item",
        "numeric vendor OnEnter must retain its dedicated plain wares tooltip path")

    local summaries = collect(handler, 900, false)
    check(countNodes(summaries) == 2, "continent must emit one summary for each rectangle-projectable eligible zone")
    checkSummaryRecords(summaries)
    local firstBuildCalls, firstBuildOrder = rectangleStats()
    check(firstBuildCalls == 3 and firstBuildOrder[1] == 101 and firstBuildOrder[2] == 102 and firstBuildOrder[3] == 103, "summary builder must sort zone IDs before collision nudging")
    local first = checkSummaryAt(summaries, 15009999, 101, 2)
    checkSummaryAt(summaries, 15019999, 102, 1)
    check(type(first.icon) == "table" and first.icon.icon == 54321 and first.icon.tCoordLeft == 0.11 and first.icon.tCoordRight == 0.89 and first.icon.tCoordTop == 0.21 and first.icon.tCoordBottom == 0.79, "summary must use the resolved housing-decor-vendor atlas payload")
    check(first.icon.icon == zoneVendor.icon.icon and first.icon.tCoordLeft == zoneVendor.icon.tCoordLeft and first.icon.tCoordRight == zoneVendor.icon.tCoordRight and first.icon.tCoordTop == zoneVendor.icon.tCoordTop and first.icon.tCoordBottom == zoneVendor.icon.tCoordBottom, "summary must use the same vendor icon as normal HNH pins")
    local fallbackRuntime = { loadRuntime({}, "Alliance", false) }
    local fallbackSummary = checkSummaryAt(collect(fallbackRuntime[1], 900, false), 15009999, 101, 2)
    check(fallbackSummary.icon.icon == 54321, "summary must continue using the vendor atlas when the removed summary atlas is unavailable")
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

    setFaction("Alliance")
    handler.OnEnter(pin, 900, 15009999)
    check(#tooltip.lines == 3 and tooltip.lines[1] == "Alpha" and tooltip.lines[2] == "2 vendors", "summary tooltip must contain only the zone and vendor count")
    check(type(tooltip.lines[3]) == "string" and string.find(string.lower(tooltip.lines[3]), "click"), "summary tooltip must include a click instruction")
    check(not string.find(table.concat(tooltip.lines, "\n"), "Alliance vendor") and not string.find(table.concat(tooltip.lines, "\n"), "Wares") and not string.find(table.concat(tooltip.lines, "\n"), "Cached item"), "summary tooltip must not render vendor wares or item lines")
    check(tooltip.owner == pin, "summary hover must own the shared tooltip")
    handler.OnLeave(pin, 900, 15009999)
    check(tooltip.owner == nil, "leaving a summary badge must hide the shared tooltip")
    setItemCached(false)
    handler.OnEnter(pin, 101, 10001000)
    check(#itemLoadCallbacks == 1, "uncached vendor tooltip must retain its item-load callback")
    handler.OnEnter(pin, 900, 15009999)
    local summaryTooltip = table.concat(tooltip.lines, "\n")
    itemLoadCallbacks[1]()
    check(table.concat(tooltip.lines, "\n") == summaryTooltip, "stale vendor item-load callback must not replace the summary tooltip")
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
    runCurrentDataProjectionCoverage()
    runNestedProjectionRegression()
    runHBDProjectionFallback()
    runWorldProjectionRegression()
    runHomesteadGeographyRegression()
    runVendorTooltipSearch()
    runVendorCostRender()
    runVendorCostRenderColdToWarm()
    runVendorCostRenderInteractiveRemeasure()
end

local ok, err = xpcall(run, debug.traceback)
restoreAll()
if not ok then error(err, 0) end

print("HNH-004 zone summary harness: PASS")
-- luacheck: pop
