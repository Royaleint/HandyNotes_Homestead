--[[
    HandyNotes_Homestead
    Housing decor vendor pins as a HandyNotes plugin, powered by Homestead's
    verified vendor data (see Data.lua, generated).

    Steps aside entirely when full Homestead is enabled: Homestead renders
    its own richer pins, and running both would double every vendor pin.
]]

local _, ns = ...
local L = ns.L

local HNH = {}
local db
local iconpath

-- The identifier HNH registers under with HandyNotes -- the same string
-- RegisterPluginDB, HandyNotes_NotifyUpdate, and (below) each pin's own
-- pluginName field all use to mean "this plugin".
local PLUGIN_NAME = "Homestead"

-- Homestead's vendor pins use this Blizzard atlas (PinFrameFactory).
-- Resolved to a file ID + texcoords at login because HandyNotes applies
-- icons via SetTexture only.
local VENDOR_ATLAS = "housing-decor-vendor_32"
-- Stock POI texture so pins never silently vanish if a patch renames the atlas.
local FALLBACK_ICON = "Interface\\MINIMAP\\TRACKING\\Banker"

local defaults = {
    profile = {
        icon_scale = 1.0,
        icon_alpha = 1.0,
    },
}

-------------------------------------------------------------------------------
-- Icon
-------------------------------------------------------------------------------

local function ResolveIcon()
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(VENDOR_ATLAS)
    -- AtlasInfo carries either `file` (file ID) or `filename` (path);
    -- either works with SetTexture.
    local file = info and (info.file or info.filename)
    if not file then
        return FALLBACK_ICON
    end
    return {
        icon = file,
        tCoordLeft = info.leftTexCoord,
        tCoordRight = info.rightTexCoord,
        tCoordTop = info.topTexCoord,
        tCoordBottom = info.bottomTexCoord,
    }
end

-------------------------------------------------------------------------------
-- HandyNotes plugin handler
-------------------------------------------------------------------------------

-- HandyNotes draws pins at 12px x scale (screen-anchored via SetScalingLimits),
-- so these multiply that base: ~16px on the world map, slightly enlarged on the minimap.
local WORLD_PIN_SCALE = 1.35
local MINIMAP_PIN_SCALE = 1.15

-------------------------------------------------------------------------------
-- Continent-level nodes
--
-- The generated data keys nodes by each vendor's own zone map, so continent
-- maps have nothing to draw. Build one summary per zone at its rectangle center
-- when the continent is first viewed.
-------------------------------------------------------------------------------

local HBD
local continentNodes = {}
local worldNodes = {}
local summaryIconpath = FALLBACK_ICON
local professionVendorRequirements = { [256026] = 182 } -- Irodalmin requires Herbalism.
local professionVisibilityKey

-- Keep HNH's summary geography aligned with Homestead's established map rules.
-- These are display rules only; the generated vendor data remains unchanged.
local excludedContinents = { [572] = true, [1550] = true }
local continentMergesInto = { [905] = 619 }
local continentOverlaysOnParent = { [2537] = 13 }
local overlayZoneExclusions = {
    [2537] = {
        [2405] = true, [15958] = true, [2444] = true, [2694] = true, [2576] = true, [2413] = true,
        [2599] = true, [2512] = true, [2509] = true, -- Native child maps stay off the EK overlay.
    },
}
local continentZoneGroups = {
    [2537] = {
        { mapID = 2405, members = { 2405, 2599, 2444, 15958 } },
        { mapID = 2694, anchorMapIDs = { 2694, 2576, 2413 }, members = { 2694, 2576, 2413 } },
        { mapID = 2512, members = { 2512, 2509 } },
    },
}

local function DisplayContinent(continentMapID)
    return continentMergesInto[continentMapID] or continentOverlaysOnParent[continentMapID] or continentMapID
end

local function PlayerHasSkillLine(skillLineID)
    if not GetProfessions or not GetProfessionInfo then return false end
    local profession1, profession2, profession3, profession4, profession5 = GetProfessions()
    local professionIndices = { profession1, profession2, profession3, profession4, profession5 }
    for index = 1, 5 do
        local professionIndex = professionIndices[index]
        if professionIndex then
            local _, _, _, _, _, _, currentSkillLineID = GetProfessionInfo(professionIndex)
            if currentSkillLineID == skillLineID then return true end
        end
    end
    return false
end

function HNH:IsProfessionVendorVisible(npcID)
    local requiredSkillLineID = professionVendorRequirements[npcID]
    return not requiredSkillLineID or PlayerHasSkillLine(requiredSkillLineID)
end

local function RefreshProfessionVisibilityCache()
    -- Cache key tracks only Herbalism (182); extend it if professionVendorRequirements gains another skill line.
    local nextKey = PlayerHasSkillLine(182) and "herbalism" or "no_herbalism"
    if nextKey == professionVisibilityKey then return end
    professionVisibilityKey = nextKey
    continentNodes = {}
    worldNodes = {}
    ns.ZoneSummaryProjectionFailures = nil
end

local function ZoneContinent(zoneMapID)
    local info = C_Map.GetMapInfo(zoneMapID)
    while info and info.mapType and info.mapType > Enum.UIMapType.Continent do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return (info and info.mapType == Enum.UIMapType.Continent) and info.mapID or nil
end

local function ZoneBelongsToView(zoneMapID, viewMapID)
    local continentMapID = ZoneContinent(zoneMapID)
    if not continentMapID then return false end
    if continentMapID == viewMapID then return true end
    if DisplayContinent(continentMapID) == viewMapID then
        local isParentOverlay = continentOverlaysOnParent[continentMapID] == viewMapID
        return not isParentOverlay
            or not (overlayZoneExclusions[continentMapID] and overlayZoneExclusions[continentMapID][zoneMapID])
    end
    return continentOverlaysOnParent[continentMapID] == viewMapID
        and not (overlayZoneExclusions[continentMapID] and overlayZoneExclusions[continentMapID][zoneMapID])
end

local function ProjectZoneCenterToMap(zoneMapID, continentMapID)
    if zoneMapID == continentMapID then return 0.5, 0.5, "same_map" end

    local currentMapID = zoneMapID
    local x, y = 0.5, 0.5
    local visited = {}
    local failureReason

    while currentMapID and currentMapID ~= continentMapID do
        if visited[currentMapID] then
            failureReason = "map_parent_cycle"
            break
        end
        visited[currentMapID] = true

        local info = C_Map.GetMapInfo(currentMapID)
        local parentMapID = info and info.parentMapID
        if not parentMapID then
            failureReason = "no_parent_path"
            break
        end

        local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(currentMapID, parentMapID)
        if minX == nil or maxX == nil or minY == nil or maxY == nil then
            failureReason = "map_rectangle_unavailable"
            break
        end
        if minX == maxX and minY == maxY then
            failureReason = "map_rectangle_degenerate"
            break
        end

        x = minX + ((maxX - minX) * x)
        y = minY + ((maxY - minY) * y)
        currentMapID = parentMapID
    end

    if currentMapID == continentMapID and x >= 0 and x < 1 and y >= 0 and y < 1 then
        return x, y, "rect_projection"
    end

    if HBD and HBD.TranslateZoneCoordinates then
        local fallbackX, fallbackY = HBD:TranslateZoneCoordinates(0.5, 0.5, zoneMapID, continentMapID)
        if fallbackX and fallbackY and fallbackX >= 0 and fallbackX < 1 and fallbackY >= 0 and fallbackY < 1 then
            return fallbackX, fallbackY, "hbd_fallback"
        end
    end

    return nil, nil, failureReason or "no_parent_path"
end

local function PackSummaryCoordinate(x, y)
    -- HandyNotes coords pack as XXXXYYYY (see getXY); x or y of 1.0 would overflow into the next field.
    if x < 0 or x >= 1 or y < 0 or y >= 1 then return nil end
    local packedX = math.floor(x * 10000 + 0.5)
    local packedY = math.floor(y * 10000 + 0.5)
    if packedX < 0 or packedX > 9999 or packedY < 0 or packedY > 9999 then return nil end
    return packedX, packedY
end

local function NudgeSummaryCoordinate(nodes, x, y)
    local packedX, packedY = PackSummaryCoordinate(x, y)
    if not packedX then return nil end
    while nodes[packedX * 10000 + packedY] do
        if packedY < 9999 then
            packedY = packedY + 1
        elseif packedX < 9999 then
            packedX = packedX + 1
        else
            return nil
        end
    end
    return packedX * 10000 + packedY
end

local function GetProjectedNodes(viewMapID, faction, isWorld)
    RefreshProfessionVisibilityCache()
    local factionKey = faction or "Neutral"
    local viewCache = isWorld and worldNodes or continentNodes
    local cachedNodes = viewCache[viewMapID]
    if not cachedNodes then
        cachedNodes = {}
        viewCache[viewMapID] = cachedNodes
    end
    local nodes = cachedNodes[factionKey]
    if nodes then return nodes end

    nodes = {}
    cachedNodes[factionKey] = nodes
    -- Diagnostic record read by tests/; not a dead store.
    ns.ZoneSummaryProjectionFailures = ns.ZoneSummaryProjectionFailures or {}
    local viewFailures = ns.ZoneSummaryProjectionFailures[viewMapID]
    if not viewFailures then
        viewFailures = {}
        ns.ZoneSummaryProjectionFailures[viewMapID] = viewFailures
    end
    local failures = {}
    viewFailures[factionKey] = failures

    local zoneMapIDs = {}
    for zoneMapID in next, ns.Nodes do
        local info = C_Map.GetMapInfo(zoneMapID)
        local belongsToView
        if isWorld then
            local continentMapID = ZoneContinent(zoneMapID)
            belongsToView = continentMapID ~= nil and not excludedContinents[continentMapID]
        else
            belongsToView = ZoneBelongsToView(zoneMapID, viewMapID)
        end
        if info and info.mapType and info.mapType > Enum.UIMapType.Continent and belongsToView then
            zoneMapIDs[#zoneMapIDs + 1] = zoneMapID
        end
    end
    -- Sorted so collision nudging places summaries the same way every session.
    table.sort(zoneMapIDs)

    if isWorld then
        local continentVendors = {}
        for _, zoneMapID in ipairs(zoneMapIDs) do
            local continentMapID = DisplayContinent(ZoneContinent(zoneMapID))
            if continentMapID then
                local vendors = continentVendors[continentMapID]
                if not vendors then
                    vendors = {}
                    continentVendors[continentMapID] = vendors
                end
                for _, npcID in next, ns.Nodes[zoneMapID] do
                    local vendor = ns.Vendors[npcID]
                    if vendor and HNH:IsProfessionVendorVisible(npcID) and (not vendor.faction or vendor.faction == faction) then
                        vendors[npcID] = true
                    end
                end
            end
        end

        local continentMapIDs = {}
        for continentMapID in next, continentVendors do
            continentMapIDs[#continentMapIDs + 1] = continentMapID
        end
        table.sort(continentMapIDs)

        for _, continentMapID in ipairs(continentMapIDs) do
            local vendors = continentVendors[continentMapID]
            local vendorCount = 0
            for _ in next, vendors do
                vendorCount = vendorCount + 1
            end
            if vendorCount > 0 then
                local x, y, projectionReason = ProjectZoneCenterToMap(continentMapID, viewMapID)
                if not x or not y then
                    failures[continentMapID] = projectionReason
                else
                    local coord = NudgeSummaryCoordinate(nodes, x, y)
                    if not coord then
                        failures[continentMapID] = "Summary coordinate is outside map bounds"
                    else
                        nodes[coord] = {
                            kind = "continentSummary",
                            mapID = continentMapID,
                            vendorCount = vendorCount,
                        }
                    end
                end
            end
        end
    else
        local groupedZoneIDs = {}
        local groups = continentZoneGroups[viewMapID]
        if groups then
            for _, group in ipairs(groups) do
                local vendors = {}
                for _, zoneMapID in ipairs(group.members) do
                    groupedZoneIDs[zoneMapID] = true
                    for _, npcID in next, ns.Nodes[zoneMapID] or {} do
                        local vendor = ns.Vendors[npcID]
                        if vendor and HNH:IsProfessionVendorVisible(npcID) and (not vendor.faction or vendor.faction == faction) then
                            vendors[npcID] = true
                        end
                    end
                end
                local vendorCount = 0
                for _ in next, vendors do vendorCount = vendorCount + 1 end
                if vendorCount > 0 then
                    local x, y, projectionReason
                    local anchorMapIDs = group.anchorMapIDs or { group.mapID }
                    for _, anchorMapID in ipairs(anchorMapIDs) do
                        x, y, projectionReason = ProjectZoneCenterToMap(anchorMapID, viewMapID)
                        if x and y then break end
                    end
                    if not x or not y then
                        failures[group.mapID] = projectionReason
                    else
                        local coord = NudgeSummaryCoordinate(nodes, x, y)
                        if not coord then
                            failures[group.mapID] = "Summary coordinate is outside map bounds"
                        else
                            nodes[coord] = {
                                kind = "zoneSummary",
                                zoneMapID = group.mapID,
                                vendorCount = vendorCount,
                            }
                        end
                    end
                end
            end
        end
        for _, zoneMapID in ipairs(zoneMapIDs) do
            if not groupedZoneIDs[zoneMapID] then
            local vendors = {}
            for _, npcID in next, ns.Nodes[zoneMapID] do
                local vendor = ns.Vendors[npcID]
                if vendor and HNH:IsProfessionVendorVisible(npcID) and (not vendor.faction or vendor.faction == faction) then
                    vendors[npcID] = true
                end
            end
            local vendorCount = 0
            for _ in next, vendors do
                vendorCount = vendorCount + 1
            end

            if vendorCount > 0 then
                local x, y, projectionReason = ProjectZoneCenterToMap(zoneMapID, viewMapID)
                if not x or not y then
                    failures[zoneMapID] = projectionReason
                else
                    local coord = NudgeSummaryCoordinate(nodes, x, y)
                    if not coord then
                        failures[zoneMapID] = "Summary coordinate is outside map bounds"
                    else
                        nodes[coord] = {
                            kind = "zoneSummary",
                            zoneMapID = zoneMapID,
                            vendorCount = vendorCount,
                        }
                    end
                end
            end
            end
        end
    end
    return nodes
end

-------------------------------------------------------------------------------
-- Counted world/continent badges
-------------------------------------------------------------------------------

-- HandyNotes owns its pin frames and exposes no supported child-frame hook for
-- a count label. Use the same plain-frame/canvas approach as Homestead for
-- summaries, while leaving ordinary zone and minimap pins with HandyNotes.
local activeSummaryPins = {}
-- Badge frames are never freed, so cleared ones wait here to be reused.
local freeSummaryPins = {}

function HNH:GetSummaryVisualSizes(uiScale)
    uiScale = uiScale or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local scaleCompensation = uiScale > 0 and (1 / uiScale) or 1
    local adjustedSize = math.floor((11 * scaleCompensation) + 0.5)
    local iconSize = math.floor((adjustedSize * 1.15) + 0.5)
    return adjustedSize, iconSize
end

function HNH:GetSummaryFrameLayering()
    -- Deliberately raised above the map's own pins; lowering this hides the badges under them.
    return "MEDIUM", 2024
end

function HNH:GetMinimapPinScale()
    return MINIMAP_PIN_SCALE
end

local function ClearSummaryPins()
    for index = #activeSummaryPins, 1, -1 do
        local frame = activeSummaryPins[index]
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(UIParent)
        frame.node = nil
        freeSummaryPins[#freeSummaryPins + 1] = frame
        activeSummaryPins[index] = nil
    end
end

local function PositionSummaryPin(frame, x, y)
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvas then return false end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return false end
    local canvasScale = canvas:GetEffectiveScale() or 1
    local uiScale = UIParent:GetEffectiveScale() or 1
    -- Counter the canvas zoom so pins stay a constant screen size; SetPoint offsets are then in the pin's scaled units, hence the / scale.
    local scale = canvasScale > 0 and uiScale / canvasScale or 1
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", canvas, "TOPLEFT", (width * x) / scale, -(height * y) / scale)
    frame:Show()
    return true
end

function HNH:ShowSummaryTooltip(frame, node)
    local mapID = node.mapID or node.zoneMapID
    local mapInfo = C_Map.GetMapInfo(mapID)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(mapInfo and mapInfo.name or L["Unknown"])
    GameTooltip:AddLine(string.format(L["Vendors: %d"], node.vendorCount))
    GameTooltip:AddLine(node.kind == "continentSummary" and L["Click to view continent"] or L["Click to view zone"])
    GameTooltip:Show()
end

-- A map change started from addon code in combat makes Blizzard's pin
-- acquisition run tainted and hit protected calls, so refuse it there.
local function OpenSummaryMap(node)
    if InCombatLockdown() then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "You can't do that while in combat.", 1.0, 0.1, 0.1)
        end
        return
    end
    if WorldMapFrame and WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(node.mapID or node.zoneMapID)
    end
end

local function RenderSummaryPins()
    ClearSummaryPins()
    if not WorldMapFrame or not WorldMapFrame.IsShown or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local mapInfo = mapID and C_Map.GetMapInfo(mapID)
    if not mapInfo or (mapInfo.mapType ~= Enum.UIMapType.World and mapInfo.mapType ~= Enum.UIMapType.Continent) then return end

    local nodes = GetProjectedNodes(mapID, UnitFactionGroup("player"), mapInfo.mapType == Enum.UIMapType.World)
    local adjustedSize, iconSize = HNH:GetSummaryVisualSizes()
    local fontSize = math.max(8, math.floor(adjustedSize * 0.46))
    local textOffset = math.max(1, math.floor(adjustedSize * 0.12))
    for coord, node in next, nodes do
        local x, y = HandyNotes:getXY(coord)
        local canvas = WorldMapFrame:GetCanvas()
        local frame = freeSummaryPins[#freeSummaryPins]
        if frame then
            freeSummaryPins[#freeSummaryPins] = nil
            frame:SetParent(canvas)
        else
            frame = CreateFrame("Frame", nil, canvas)
            frame:EnableMouse(true)
            frame.icon = frame:CreateTexture(nil, "ARTWORK")
            frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)
            if type(summaryIconpath) == "table" then
                frame.icon:SetTexture(summaryIconpath.icon)
                frame.icon:SetTexCoord(summaryIconpath.tCoordLeft, summaryIconpath.tCoordRight, summaryIconpath.tCoordTop, summaryIconpath.tCoordBottom)
            else
                frame.icon:SetTexture(summaryIconpath)
            end
            frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal", 2)
            frame.count:SetTextColor(1, 1, 1)
            frame.count:SetShadowColor(0, 0, 0, 1)
            frame.count:SetShadowOffset(1, -1)
            -- Handlers read self.node; a pooled badge is reused for other nodes.
            frame:SetScript("OnEnter", function(self)
                if not self.node then return end
                HNH:ShowSummaryTooltip(self, self.node)
            end)
            frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame:SetScript("OnMouseUp", function(self, button)
                if not self.node then return end
                if button == "LeftButton" then OpenSummaryMap(self.node) end
            end)
        end
        frame.node = node
        local strata, frameLevel = HNH:GetSummaryFrameLayering()
        frame:SetFrameStrata(strata)
        frame:SetFrameLevel(frameLevel)
        frame:SetSize(adjustedSize, adjustedSize + fontSize + textOffset)
        frame.icon:SetSize(iconSize, iconSize)
        frame.count:ClearAllPoints()
        frame.count:SetPoint("TOP", frame.icon, "BOTTOM", 0, -textOffset)
        frame.count:SetText(tostring(node.vendorCount))
        local fontPath = frame.count:GetFont()
        frame.count:SetFont(fontPath, fontSize, "OUTLINE")
        activeSummaryPins[#activeSummaryPins + 1] = frame
        PositionSummaryPin(frame, x, y)
    end
end

local summaryMapProvider

local function RegisterSummaryMapProvider()
    if not WorldMapFrame or not WorldMapFrame.AddDataProvider or not CreateFromMixins or not MapCanvasDataProviderMixin then return end
    if summaryMapProvider then return end
    summaryMapProvider = CreateFromMixins(MapCanvasDataProviderMixin)
    function summaryMapProvider:OnMapChanged() RenderSummaryPins() end
    function summaryMapProvider:OnCanvasSizeChanged() RenderSummaryPins() end
    function summaryMapProvider:OnCanvasScaleChanged() RenderSummaryPins() end
    WorldMapFrame:AddDataProvider(summaryMapProvider)
end

-- Node lookup shared by tooltip and click handlers: zone nodes come from the
-- generated data, continent nodes from the projected cache.
local function NodeAt(uiMapID, coord, faction)
    RefreshProfessionVisibilityCache()
    local info = C_Map.GetMapInfo(uiMapID)
    if info and (info.mapType == Enum.UIMapType.Continent or info.mapType == Enum.UIMapType.World) then
        local viewCache = info.mapType == Enum.UIMapType.World and worldNodes or continentNodes
        local factionKey = faction or "Neutral"
        local cachedNodes = viewCache[uiMapID]
        local nodes = cachedNodes and cachedNodes[factionKey]
        return nodes and nodes[coord] or nil
    end
    local nodes = ns.Nodes[uiMapID]
    return nodes and nodes[coord] or nil
end

do
    local playerFaction, pathScale

    local function iter(nodes, prestate)
        if not nodes then return nil end
        local coord, node = next(nodes, prestate)
        while coord do
            if type(node) == "table" and (node.kind == "zoneSummary" or node.kind == "continentSummary") then
                return coord, nil, summaryIconpath, pathScale * db.profile.icon_scale, db.profile.icon_alpha
            end
            local vendor = ns.Vendors[node]
            -- vendor.faction is set only for Alliance- or Horde-only vendors; nil means show to all.
            if vendor and HNH:IsProfessionVendorVisible(node) and (not vendor.faction or vendor.faction == playerFaction) then
                return coord, nil, iconpath, pathScale * db.profile.icon_scale, db.profile.icon_alpha
            end
            coord, node = next(nodes, coord)
        end
        return nil
    end

    function HNH:GetNodes2(uiMapID, minimap)
        playerFaction = UnitFactionGroup("player")
        pathScale = minimap and MINIMAP_PIN_SCALE or WORLD_PIN_SCALE
        local nodes = ns.Nodes[uiMapID]
        if not minimap then
            local info = C_Map.GetMapInfo(uiMapID)
            -- The world map draws continent/world summaries through our own data provider; returning nodes here would draw them twice.
            if info and info.mapType == Enum.UIMapType.Continent then
                if WorldMapFrame and WorldMapFrame.GetCanvas then return iter, nil, nil end
                nodes = GetProjectedNodes(uiMapID, playerFaction, false)
            elseif info and info.mapType == Enum.UIMapType.World then
                if WorldMapFrame and WorldMapFrame.GetCanvas then return iter, nil, nil end
                nodes = GetProjectedNodes(uiMapID, playerFaction, true)
            end
        end
        return iter, nodes, nil
    end
end

-------------------------------------------------------------------------------
-- Tooltip
-------------------------------------------------------------------------------

local LONG_WARES_THRESHOLD = 15
local MAX_VISIBLE_WARE_ROWS = 15
local currentHover
local plainTooltip
local interactiveTooltip
local tooltipSearchBox
local tooltipSearchTimer
local tooltipSearchQuery = ""
local suppressTooltipSearchChanged = false
local mapHideHookInstalled = false

-- Returns (cost, complete) for an item: gold, currency icons, and reagent item icons,
-- with names as the fallback.
-- Currency and item lookups routinely return nil until the client has the data. Such a
-- result is marked incomplete and never cached, so a later render can fill it in.
-- Resolved strings are cached because the tooltip re-renders on every item load; uncached, large vendors go quadratic.
-- item.costCache: nil = not computed yet, false = free, string = resolved cost.
-- Grey, matching the location and "Items unknown" lines.
local OTHER_COST_TEXT = "|cFFB3B3B3" .. L["(other cost)"] .. "|r"

local function FormatCost(item)
    if item.costCache ~= nil then
        if item.costCache == false then return nil, true end
        return item.costCache, true
    end

    local parts = {}
    -- Appended after the loops so the marker always lands last, even when an early lookup fails.
    local needsOtherCost = false
    -- Separate from needsOtherCost: an otherCost marker is safe to cache, a degraded lookup never is.
    local degraded = false

    if item.price and item.price > 0 then
        parts[#parts + 1] = C_CurrencyInfo.GetCoinTextureString(item.price)
    end
    if item.currencies then
        for _, currency in ipairs(item.currencies) do
            local info = C_CurrencyInfo.GetCurrencyInfo(currency.id)
            if info and info.iconFileID then
                parts[#parts + 1] = currency.amount .. " |T" .. info.iconFileID .. ":0:0|t"
            elseif info and info.name then
                parts[#parts + 1] = currency.amount .. " " .. info.name
            else
                -- Not loaded yet (normal, not rare): never show the raw ID; mark it and skip caching.
                needsOtherCost = true
                degraded = true
            end
        end
    end
    if item.items then
        for _, itemCost in ipairs(item.items) do
            local icon = C_Item.GetItemIconByID(itemCost.id)
            if icon then
                parts[#parts + 1] = itemCost.amount .. " |T" .. icon .. ":0:0|t"
            else
                local name = C_Item.GetItemNameByID(itemCost.id)
                if name then
                    parts[#parts + 1] = itemCost.amount .. " " .. name
                else
                    -- Not loaded yet (normal for unseen reagents): never show the raw ID; mark it and skip caching.
                    needsOtherCost = true
                    degraded = true
                end
            end
        end
    end
    -- Keep: an otherCost row's listed price is only part of its cost; without the marker the tooltip understates it.
    if item.otherCost then
        needsOtherCost = true
    end
    if needsOtherCost then
        parts[#parts + 1] = OTHER_COST_TEXT
    end

    local cost = (#parts > 0) and table.concat(parts, " + ") or nil
    if degraded then
        -- Don't memoize: complete == false keeps the hover pending so it re-renders once the data loads.
        return cost, false
    end
    item.costCache = (cost == nil) and false or cost
    return cost, true
end

local function ItemMatchesTooltipSearch(item, itemName)
    if tooltipSearchQuery == "" then return true end
    if itemName and itemName:lower():find(tooltipSearchQuery, 1, true) then
        return true
    end
    if item.currencies then
        for _, currency in ipairs(item.currencies) do
            local info = C_CurrencyInfo.GetCurrencyInfo(currency.id)
            if info and info.name and info.name:lower():find(tooltipSearchQuery, 1, true) then
                return true
            end
        end
    end
    if item.items then
        for _, itemCost in ipairs(item.items) do
            -- GetItemNameByID, not GetItemInfo, so the search never triggers
            -- item loads; it returns nil when uncached and the row simply
            -- doesn't match on reagent name yet.
            local name = C_Item.GetItemNameByID(itemCost.id)
            if name and name:lower():find(tooltipSearchQuery, 1, true) then
                return true
            end
        end
    end
    return false
end

local function AddVendorHeader(tooltip, vendor)
    tooltip:SetText(vendor.name)
    local location = vendor.subzone or vendor.zone
    if vendor.subzone and vendor.zone then
        location = vendor.subzone .. ", " .. vendor.zone
    end
    if location then
        tooltip:AddLine(location, 0.7, 0.7, 0.7)
    end
end

local function GetPlainTooltip()
    if plainTooltip then return plainTooltip end
    plainTooltip = CreateFrame("GameTooltip", "HandyNotesHomesteadTooltip", UIParent, "GameTooltipTemplate")
    plainTooltip:SetFrameStrata("TOOLTIP")
    plainTooltip:SetClampedToScreen(true)
    return plainTooltip
end

local function RenderPlainTooltip(tooltip, vendor)
    tooltip:ClearLines()
    AddVendorHeader(tooltip, vendor)

    local pending = false
    if #vendor.items > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Items"] .. L[":"], 1, 0.82, 0)
        local matches = 0
        for _, item in ipairs(vendor.items) do
            local itemName = C_Item.GetItemInfo(item.id)
            if not itemName then pending = true end
            if ItemMatchesTooltipSearch(item, itemName) then
                matches = matches + 1
                local cost, complete = FormatCost(item)
                if not complete then pending = true end
                if cost then
                    tooltip:AddDoubleLine(itemName or "...", cost, 1, 1, 1, 1, 1, 1)
                else
                    tooltip:AddLine(itemName or "...", 1, 1, 1)
                end
            end
        end
        if matches == 0 then tooltip:AddLine(L["No results found"], 0.7, 0.7, 0.7) end
    else
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Items unknown"], 0.7, 0.7, 0.7)
    end

    tooltip:Show()
    return pending
end

-- A GameTooltip, like the plain path, plus a scroll bar and search box in reserved padding.
-- GameTooltip_OnHide clears that padding, so it is re-applied on every render.
-- MinimalScrollBar's arrows are 17px wide, centred on an 8px track; size the column for the arrows.
local INTERACTIVE_RIGHT_PADDING = 24
local INTERACTIVE_BAR_INSET = 10
local INTERACTIVE_BOTTOM_PADDING = 26
local INTERACTIVE_MIN_WIDTH = 240
local syncingScrollBar = false
local AnchorInteractiveTooltip

local function ScrollMaximum(frame)
    return math.max(0, (frame.matchCount or 0) - MAX_VISIBLE_WARE_ROWS)
end

local function SyncScrollBar(frame)
    local bar = frame.scrollBar
    local maximum = ScrollMaximum(frame)
    if maximum == 0 then
        bar:Hide()
        return
    end
    bar:Show()
    -- Suppresses the bar's own OnScroll callback while we set its position.
    syncingScrollBar = true
    bar:SetVisibleExtentPercentage(MAX_VISIBLE_WARE_ROWS / frame.matchCount)
    bar:SetPanExtentPercentage(1 / maximum)
    bar:SetScrollPercentage(frame.scrollOffset / maximum, ScrollBoxConstants.NoScrollInterpolation)
    syncingScrollBar = false
end

-- Emits the header plus the matching wares from `first` (1-based match
-- index) for up to `limit` rows, with the plain tooltip's exact calls.
-- `everyWare` ignores the search query (the width-measuring pass). Returns
-- true if any drawn row's cost was incomplete (see FormatCost).
local function AddInteractiveLines(frame, vendor, first, limit, everyWare)
    frame:ClearLines()
    AddVendorHeader(frame, vendor)
    frame:AddLine(" ")
    frame:AddLine(L["Items"] .. L[":"], 1, 0.82, 0)
    local matchIndex = 0
    local shown = 0
    local pending = false
    for _, item in ipairs(vendor.items) do
        local itemName = C_Item.GetItemInfo(item.id)
        if everyWare or ItemMatchesTooltipSearch(item, itemName) then
            matchIndex = matchIndex + 1
            if matchIndex >= first and shown < limit then
                shown = shown + 1
                local cost, complete = FormatCost(item)
                if not complete then pending = true end
                if cost then
                    frame:AddDoubleLine(itemName or "...", cost, 1, 1, 1, 1, 1, 1)
                else
                    frame:AddLine(itemName or "...", 1, 1, 1)
                end
            end
        end
    end
    if matchIndex == 0 then frame:AddLine(L["No results found"], 0.7, 0.7, 0.7) end
    return pending
end

local function RenderInteractiveTooltip(vendor)
    local frame = interactiveTooltip
    local pending = false
    local matches = 0
    local resolved = 0
    for _, item in ipairs(vendor.items) do
        local itemName = C_Item.GetItemInfo(item.id)
        if itemName then resolved = resolved + 1 else pending = true end
        -- Count complete costs too: a reagent resolving late must also trigger a re-measure.
        local _, costComplete = FormatCost(item)
        if costComplete then resolved = resolved + 1 else pending = true end
        if ItemMatchesTooltipSearch(item, itemName) then
            matches = matches + 1
        end
    end
    frame.matchCount = matches
    frame.scrollOffset = math.min(frame.scrollOffset or 0, ScrollMaximum(frame))
    local scrollable = matches > MAX_VISIBLE_WARE_ROWS
    local rightPadding = scrollable and INTERACTIVE_RIGHT_PADDING or 0

    -- Width is measured once per vendor from every ware (query ignored) and frozen, so
    -- scrolling or searching never resizes the tooltip under the cursor and closes it.
    -- Re-measure only when another name resolves; never freeze a zero width.
    if frame.measuredVendor ~= vendor or frame.measuredResolved ~= resolved then
        if AddInteractiveLines(frame, vendor, 1, math.huge, true) then pending = true end
        -- Reset the minimum before measuring or the previous vendor's width
        -- would floor this one's measurement.
        frame:SetMinimumWidth(INTERACTIVE_MIN_WIDTH)
        frame:SetPadding(rightPadding, INTERACTIVE_BOTTOM_PADDING)
        frame:Show()
        local width = frame:GetWidth()
        if width > 0 then
            frame.measuredWidth = math.max(INTERACTIVE_MIN_WIDTH, width)
            frame.measuredVendor = vendor
            frame.measuredResolved = resolved
        else
            frame.measuredWidth = INTERACTIVE_MIN_WIDTH
            frame.measuredVendor = nil
        end
    end

    if AddInteractiveLines(frame, vendor, frame.scrollOffset + 1, MAX_VISIBLE_WARE_ROWS) then pending = true end
    frame:SetMinimumWidth(frame.measuredWidth)
    frame:SetPadding(rightPadding, INTERACTIVE_BOTTOM_PADDING)
    frame:Show()
    -- Anchor once per hover, and only once the height is non-zero (zero misreads as room
    -- below). Never re-anchor: a narrowing search would flip the tooltip out from under the cursor.
    if frame.anchorPin and frame:GetHeight() > 0 then
        AnchorInteractiveTooltip(frame, frame.anchorPin)
        frame.anchorPin = nil
    end
    SyncScrollBar(frame)
    return pending
end

-- Butts the tooltip edge-to-edge against the pin (a corner touch closes on the
-- crossing). Hangs down unless that would overhang the screen, where clamping would
-- slide it off the pin. The vertical test uses effective scale: pins sit on the scaled map canvas.
AnchorInteractiveTooltip = function(frame, pin)
    local flip = pin:GetCenter() > UIParent:GetCenter()
    local hangsDown = true
    local pinTop = pin:GetTop()
    if pinTop then
        local roomBelow = pinTop * pin:GetEffectiveScale()
        hangsDown = roomBelow >= frame:GetHeight() * frame:GetEffectiveScale()
    end
    frame:ClearAllPoints()
    if hangsDown then
        frame:SetPoint(flip and "TOPRIGHT" or "TOPLEFT", pin, flip and "TOPLEFT" or "TOPRIGHT", 0, 0)
    else
        frame:SetPoint(flip and "BOTTOMRIGHT" or "BOTTOMLEFT", pin, flip and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, 0)
    end
end

local function CloseInteractiveTooltip()
    if not interactiveTooltip then return end
    if tooltipSearchTimer then tooltipSearchTimer:Cancel(); tooltipSearchTimer = nil end
    tooltipSearchQuery = ""
    if tooltipSearchBox then
        tooltipSearchBox:ClearFocus()
        tooltipSearchBox:Hide()
    end
    interactiveTooltip:Hide()
end

-- Unconditional teardown for the cases where the cursor is gone for good (the
-- map closed, the pin vanished) rather than merely crossing pin to tooltip.
local function CloseAllVendorTooltips()
    currentHover = nil
    if plainTooltip then plainTooltip:Hide() end
    CloseInteractiveTooltip()
end

-- Holding the scroll bar thumb fires OnScroll every frame; offsets are whole
-- rows, so most of those resolve to the offset already shown and must not
-- re-render.
local function SetInteractiveScrollOffset(offset)
    local frame = interactiveTooltip
    offset = math.max(0, math.min(ScrollMaximum(frame), offset))
    if offset == frame.scrollOffset then return end
    frame.scrollOffset = offset
    if currentHover and currentHover.kind == "interactive" then
        RenderInteractiveTooltip(currentHover.vendor)
    end
end

local function EnsureInteractiveTooltip()
    if interactiveTooltip then return interactiveTooltip end
    local frame = CreateFrame("GameTooltip", "HandyNotesHomesteadWaresTooltip", UIParent, "GameTooltipTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:EnableKeyboard(true)

    local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INTERACTIVE_BAR_INSET, -8)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INTERACTIVE_BAR_INSET, INTERACTIVE_BOTTOM_PADDING + 4)
    bar:Init(1, 1)
    bar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(_, percentage)
        -- SyncScrollBar's SetScrollPercentage re-fires OnScroll; ignore it so rounding can't feed back into the offset.
        if syncingScrollBar then return end
        SetInteractiveScrollOffset(math.floor(percentage * ScrollMaximum(frame) + 0.5))
    end, frame)
    frame.scrollBar = bar

    tooltipSearchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    tooltipSearchBox:SetAutoFocus(false)
    tooltipSearchBox:SetMaxLetters(50)
    tooltipSearchBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 6)
    tooltipSearchBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 6)
    tooltipSearchBox:SetHeight(20)
    tooltipSearchBox.Instructions:SetText(L["Search"])
    tooltipSearchBox:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        if suppressTooltipSearchChanged then return end
        if tooltipSearchTimer then tooltipSearchTimer:Cancel() end
        local token = currentHover
        if not token then return end
        tooltipSearchTimer = C_Timer.NewTimer(0.3, function()
            tooltipSearchTimer = nil
            if currentHover ~= token or not interactiveTooltip:IsShown() then return end
            tooltipSearchQuery = (self:GetText():match("^%s*(.-)%s*$") or ""):lower()
            interactiveTooltip.scrollOffset = 0
            RenderInteractiveTooltip(token.vendor)
        end)
    end)
    tooltipSearchBox:SetScript("OnEscapePressed", function(self)
        if tooltipSearchTimer then tooltipSearchTimer:Cancel(); tooltipSearchTimer = nil end
        suppressTooltipSearchChanged = true
        self:SetText("")
        suppressTooltipSearchChanged = false
        tooltipSearchQuery = ""
        currentHover = nil
        CloseInteractiveTooltip()
    end)
    tooltipSearchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    -- Focus was holding the tooltip open (see HNH:OnLeave); when it goes and
    -- the cursor is no longer on the tooltip or its pin, close as a leave would.
    tooltipSearchBox:SetScript("OnEditFocusLost", function(self)
        SearchBoxTemplate_OnEditFocusLost(self)
        local token = currentHover
        if not token or token.kind ~= "interactive" or not interactiveTooltip:IsShown() then return end
        if interactiveTooltip:IsMouseOver() then return end
        if token.pin.IsMouseOver and token.pin:IsMouseOver() then return end
        currentHover = nil
        CloseInteractiveTooltip()
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        SetInteractiveScrollOffset((frame.scrollOffset or 0) - delta)
    end)
    frame:SetScript("OnKeyDown", function(self, key)
        -- EnableKeyboard swallows every key; pass all but Escape through or movement and keybinds die.
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then
            currentHover = nil
            CloseInteractiveTooltip()
        end
    end)
    frame:SetScript("OnLeave", function() HNH:OnLeave() end)
    interactiveTooltip = frame
    return frame
end

-- Coalesce item-load callbacks in the same frame: a large vendor can complete many loads at once, and repainting per item makes hover O(n^2).
local function QueueTooltipRefresh(token, render)
    if token.refreshQueued then return end
    token.refreshQueued = true
    C_Timer.After(0, function()
        token.refreshQueued = false
        if currentHover == token then render(token.vendor) end
    end)
end

-- Loads one item's data and queues a re-render only if the same hover is still active.
local function RequestItemLoad(itemID, token, render)
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        if currentHover == token then QueueTooltipRefresh(token, render) end
    end)
end

local function RefreshVendorItems(token, render)
    if not render(token.vendor) then return end
    for _, item in ipairs(token.vendor.items) do
        if not C_Item.GetItemInfo(item.id) and C_Item.DoesItemExistByID(item.id) then
            RequestItemLoad(item.id, token, render)
        end
        -- Reagent item-costs (item.items) need the same load request as the
        -- ware itself, or FormatCost's degraded result never self-corrects.
        if item.items then
            for _, itemCost in ipairs(item.items) do
                if not C_Item.GetItemIconByID(itemCost.id) and C_Item.DoesItemExistByID(itemCost.id) then
                    RequestItemLoad(itemCost.id, token, render)
                end
            end
        end
    end
end

local function InstallMapHideHook()
    if mapHideHookInstalled or not WorldMapFrame or not WorldMapFrame.HookScript then return end
    mapHideHookInstalled = true
    WorldMapFrame:HookScript("OnHide", CloseAllVendorTooltips)
end

local function InstallPinHideHook(pin)
    if pin._hnhPinHideHooked or not pin.HookScript then return end
    pin._hnhPinHideHooked = true
    pin:HookScript("OnHide", function()
        if currentHover and currentHover.pin == pin then CloseAllVendorTooltips() end
    end)
end

function HNH:OnEnter(uiMapID, coord)
    local node = NodeAt(uiMapID, coord, UnitFactionGroup("player"))
    if not node then return end

    if type(node) == "table" and (node.kind == "zoneSummary" or node.kind == "continentSummary") then
        currentHover = nil
        CloseInteractiveTooltip()
        if plainTooltip then plainTooltip:Hide() end
        local summaryMapID = node.mapID or node.zoneMapID
        local summaryMap = C_Map.GetMapInfo(summaryMapID)
        local isContinent = node.kind == "continentSummary"
        local tooltip = GameTooltip
        tooltip:SetOwner(self, self:GetCenter() > UIParent:GetCenter() and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        tooltip:SetText(summaryMap and summaryMap.name or L["Unknown"])
        tooltip:AddLine(string.format(L["Vendors: %d"], node.vendorCount))
        tooltip:AddLine(isContinent and L["Click to view continent"] or L["Click to view zone"])
        tooltip:Show()
        return
    end

    local vendor = ns.Vendors[node]
    if not vendor or not HNH:IsProfessionVendorVisible(node) then return end

    if #vendor.items > LONG_WARES_THRESHOLD then
        if plainTooltip then plainTooltip:Hide() end
        CloseInteractiveTooltip()
        local frame = EnsureInteractiveTooltip()
        InstallPinHideHook(self)
        InstallMapHideHook()
        currentHover = { kind = "interactive", pin = self, vendor = vendor }
        tooltipSearchQuery = ""
        suppressTooltipSearchChanged = true
        tooltipSearchBox:SetText("")
        suppressTooltipSearchChanged = false
        frame.scrollOffset = 0
        tooltipSearchBox:Show()
        -- ANCHOR_LEFT/RIGHT would hang the tooltip off the pin's corner with
        -- only a corner touch, so the cursor leaves the pin into empty space
        -- and the crossing closes it. Own the pin for GameTooltip's lifecycle
        -- but butt the tooltip against the pin's edge so the cursor can cross.
        frame:SetOwner(self, "ANCHOR_NONE")
        frame:ClearAllPoints()
        local flip = self:GetCenter() > UIParent:GetCenter()
        frame:SetPoint(flip and "TOPRIGHT" or "TOPLEFT", self, flip and "TOPLEFT" or "TOPRIGHT", 0, 0)
        -- Re-anchored by room once the first render has given it a height.
        frame.anchorPin = self
        RefreshVendorItems(currentHover, RenderInteractiveTooltip)
    else
        CloseInteractiveTooltip()
        local plain = GetPlainTooltip()
        plain:SetOwner(self, self:GetCenter() > UIParent:GetCenter() and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        InstallPinHideHook(self)
        InstallMapHideHook()
        local token = { kind = "plain", pin = self, vendor = vendor }
        currentHover = token
        RefreshVendorItems(token, function(v) return RenderPlainTooltip(plain, v) end)
    end
end

-- HandyNotes calls this as plugin.OnLeave(pin, uiMapID, coord), so it takes no
-- arguments of its own: leaving the pin hands off to the tooltip if the cursor
-- landed on it, and closes otherwise.
function HNH:OnLeave()
    local token = currentHover
    if not token then
        -- Summary badges use the shared GameTooltip and leave no hover token.
        GameTooltip:Hide()
        return
    end
    if token.kind == "plain" then
        CloseAllVendorTooltips()
        return
    end
    C_Timer.After(0, function()
        if currentHover ~= token then return end
        -- A search that narrows the list shrinks the tooltip, which can move
        -- the search box out from under a stationary cursor mid-typing. While
        -- the box has focus the tooltip stays; OnEditFocusLost re-checks.
        if tooltipSearchBox:HasFocus() then return end
        if interactiveTooltip:IsMouseOver() then return end
        if token.pin.IsMouseOver and token.pin:IsMouseOver() then return end
        currentHover = nil
        CloseInteractiveTooltip()
    end)
end

-- World-map pins only: HandyNotes never wires OnClick on minimap pins.
-- Fires on both mouse-down and mouse-up, hence the `down` filter.
function HNH:OnClick(button, down, uiMapID, coord)
    if button ~= "LeftButton" or down then return end
    local node = NodeAt(uiMapID, coord, UnitFactionGroup("player"))
    if type(node) == "table" and (node.kind == "zoneSummary" or node.kind == "continentSummary") then
        OpenSummaryMap(node)
        return
    end
    -- Some maps reject user waypoints.
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(uiMapID) then
        return
    end
    local x, y = HandyNotes:getXY(coord)
    local mapPoint = UiMapPoint.CreateFromCoordinates(uiMapID, x, y)
    if not mapPoint then return end
    if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
        C_Map.ClearUserWaypoint()
    end
    C_Map.SetUserWaypoint(mapPoint)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

-------------------------------------------------------------------------------
-- Options (HandyNotes renders this inside its own config panel)
-------------------------------------------------------------------------------

local options = {
    type = "group",
    name = "Homestead",
    desc = L["Housing decor vendor locations"],
    get = function(info) return db.profile[info.arg] end,
    set = function(info, value)
        db.profile[info.arg] = value
        HNH:SendMessage("HandyNotes_NotifyUpdate", PLUGIN_NAME)
    end,
    args = {
        desc = {
            name = L["Housing decor vendor pins powered by Homestead's vendor data."],
            type = "description",
            order = 0,
        },
        icon_scale = {
            type = "range",
            name = L["Icon Scale"],
            desc = L["Size of the vendor pins."],
            min = 0.25, max = 2, step = 0.01,
            arg = "icon_scale",
            order = 1,
        },
        icon_alpha = {
            type = "range",
            name = L["Opacity"],
            desc = L["Transparency of the vendor pins."],
            min = 0.1, max = 1, step = 0.01,
            arg = "icon_alpha",
            order = 2,
        },
    },
}

-------------------------------------------------------------------------------
-- Vendor pin layering
--
-- HandyNotes' pin template uses PIN_FRAME_LEVEL_AREA_POI, a one-level band shared
-- with Blizzard's area POIs, so which pin draws on top there is arbitrary. Vendor
-- pins are re-typed to PIN_FRAME_LEVEL_QUEST_PING, the lowest band above event area
-- POIs: over POIs, map links, vignettes and world quests; under tracked quests,
-- group members, waypoints and the corpse marker.
-- A vendor pin on a map link blocks the link's right-click travel; that cost is
-- accepted, so don't lower it, and don't raise it either (the only other Quest Ping
-- pin, the ping halo, takes no mouse input).
-- The template is shared by every plugin, so only this addon's own pins are re-typed
-- after HandyNotes places them.
-------------------------------------------------------------------------------

local VENDOR_PIN_FRAME_LEVEL_TYPE = "PIN_FRAME_LEVEL_QUEST_PING"

-- The frame level survives pool reuse, so this only needs to run after RefreshPlugin, not per frame.
local function RaiseVendorPins()
    if not WorldMapFrame or not WorldMapFrame.EnumeratePinsByTemplate then return end
    for pin in WorldMapFrame:EnumeratePinsByTemplate("HandyNotesWorldMapPinTemplate") do
        if pin.pluginName == PLUGIN_NAME and pin.UseFrameLevelType then
            -- UseFrameLevelType only records the band; ApplyFrameLevel is what moves the pin.
            pin:UseFrameLevelType(VENDOR_PIN_FRAME_LEVEL_TYPE)
            pin:ApplyFrameLevel()
            pin._hnhRaised = true
        elseif pin._hnhRaised then
            -- Pooled pins are shared across plugins and OnLoad sets the band only once, so undo our raise.
            pin:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
            pin:ApplyFrameLevel()
            pin._hnhRaised = nil
        end
    end
end

-------------------------------------------------------------------------------
-- Pin size
--
-- 1px larger than HandyNotes' own default, so a vendor pin reads a little
-- more clearly against the surrounding map icons.
-------------------------------------------------------------------------------

local VENDOR_PIN_SIZE_BONUS = 1 -- extra pixels added to HandyNotes' own pin size

-- OnAcquired resets the size on every acquire, so this is safe only on HNH's own refresh.
local function GrowVendorPinSize()
    if not WorldMapFrame or not WorldMapFrame.EnumeratePinsByTemplate then return end
    for pin in WorldMapFrame:EnumeratePinsByTemplate("HandyNotesWorldMapPinTemplate") do
        if pin.pluginName == PLUGIN_NAME and pin.GetSize and pin.SetSize then
            local width, height = pin:GetSize()
            pin:SetSize(width + VENDOR_PIN_SIZE_BONUS, height + VENDOR_PIN_SIZE_BONUS)
        end
    end
end

-------------------------------------------------------------------------------
-- POI-proximity nudge
--
-- Shifts a vendor pin 2px off a nearby area POI or world event so the marker stays visible.
-- Other POI kinds (flight points, dungeon/delve entrances) each need their own availability/CVar check; left out on purpose.
-- POI positions come from C_AreaPoiInfo, not Blizzard's pins: provider order is undefined.
-- Runs on world and continent maps too, so summary pins get the dodge.
-------------------------------------------------------------------------------

-- Container pixels, not screen pixels: the on-screen distance grows with zoom.
local POI_NUDGE_THRESHOLD_PIXELS = 18
local POI_NUDGE_DISTANCE_PIXELS = 2

-- n == n rejects NaN, which would otherwise win the closest-POI check and pass the threshold.
local function IsFiniteNumber(n)
    return type(n) == "number" and n == n
end

local function InsertPoiCandidate(target, x, y)
    if IsFiniteNumber(x) and IsFiniteNumber(y) then
        target[#target + 1] = { x = x, y = y }
    end
end

local function GetPoiPositionsForMap(mapID)
    local positions = {}
    if not C_AreaPoiInfo then return positions end

    -- Area POIs and world events use separate list APIs; pcall so a missing one yields no candidates.
    local okPoi, poiIDs = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
    if okPoi and poiIDs then
        for _, poiID in ipairs(poiIDs) do
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if info and info.position then
                InsertPoiCandidate(positions, info.position.x, info.position.y)
            end
        end
    end

    local okEvent, eventIDs = pcall(C_AreaPoiInfo.GetEventsForMap, mapID)
    if okEvent and eventIDs then
        for _, eventID in ipairs(eventIDs) do
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, eventID)
            if info and info.position then
                InsertPoiCandidate(positions, info.position.x, info.position.y)
            end
        end
    end

    return positions
end

-- Returns the position moved 2px directly away from the closest POI within
-- the collision threshold, plus whether it actually moved. Unclamped and
-- doesn't touch the pin -- ApplyPinPlacementAdjustments below clamps once,
-- after the pin-separation pass has also had a chance to move the pin.
local function NudgeAwayFromClosestPoi(x, y, poiPositions, width, height)
    local closestPoi, closestDist
    for _, poi in ipairs(poiPositions) do
        local dx = (x - poi.x) * width
        local dy = (y - poi.y) * height
        local dist = math.sqrt(dx * dx + dy * dy)
        if not closestDist or dist < closestDist then
            closestDist = dist
            closestPoi = poi
        end
    end

    if not closestPoi or closestDist > POI_NUDGE_THRESHOLD_PIXELS then
        return x, y, false
    end

    local dirX, dirY
    if closestDist == 0 then
        dirX, dirY = 1, 0 -- coincident with the POI -- push right
    else
        dirX = ((x - closestPoi.x) * width) / closestDist
        dirY = ((y - closestPoi.y) * height) / closestDist
    end

    return x + (dirX * POI_NUDGE_DISTANCE_PIXELS) / width,
           y + (dirY * POI_NUDGE_DISTANCE_PIXELS) / height,
           true
end

-------------------------------------------------------------------------------
-- Pin self-avoidance
--
-- Pushes HNH's own vendor pins apart when two land within a few pixels of each other.
-------------------------------------------------------------------------------

local PIN_SEPARATION_MIN_PIXELS = 4 -- container pixels -- see the note above POI_NUDGE_THRESHOLD_PIXELS
local PIN_SEPARATION_MAX_PASSES = 3

-- Moves each pin of a too-close pair half the deficit. Multiple passes: fixing one pair
-- can push a pin into a third pin's range.
local function SeparateOwnPins(xs, ys, moved, count, width, height)
    for _ = 1, PIN_SEPARATION_MAX_PASSES do
        local movedAny = false
        for i = 1, count - 1 do
            for j = i + 1, count do
                local dx = (xs[i] - xs[j]) * width
                local dy = (ys[i] - ys[j]) * height
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < PIN_SEPARATION_MIN_PIXELS then
                    local dirIX, dirIY, dirJX, dirJY
                    -- Not reachable from our data, but keep it: dividing by a zero dist turns both positions into NaN, which the clamp does not catch.
                    if dist == 0 then
                        dirIX, dirIY = 1, 0
                        dirJX, dirJY = -1, 0
                    else
                        dirIX, dirIY = dx / dist, dy / dist
                        dirJX, dirJY = -dirIX, -dirIY
                    end
                    local halfDeficit = (PIN_SEPARATION_MIN_PIXELS - dist) / 2
                    xs[i] = xs[i] + (dirIX * halfDeficit) / width
                    ys[i] = ys[i] + (dirIY * halfDeficit) / height
                    xs[j] = xs[j] + (dirJX * halfDeficit) / width
                    ys[j] = ys[j] + (dirJY * halfDeficit) / height
                    moved[i] = true
                    moved[j] = true
                    movedAny = true
                end
            end
        end
        if not movedAny then break end
    end
end

-- Parallel scratch arrays, reused so a refresh allocates nothing per pin.
local pinScratchPins = {}
local pinScratchX = {}
local pinScratchY = {}
local pinScratchInset = {}
local pinScratchMoved = {}
local pinScratchCount = 0

-- Pins are re-acquired at their data coordinate on each HNH refresh, so this never drifts;
-- run it on any other plugin's refresh and pins move further every time.
-- Separation can move a pin back into POI range; accepted.
local function ApplyPinPlacementAdjustments()
    if not WorldMapFrame or not WorldMapFrame.GetMapID or not WorldMapFrame.GetCanvasContainer
            or not WorldMapFrame.EnumeratePinsByTemplate then
        return
    end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end

    local container = WorldMapFrame:GetCanvasContainer()
    if not container then return end

    local width, height = container:GetWidth(), container:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return end

    pinScratchCount = 0
    for pin in WorldMapFrame:EnumeratePinsByTemplate("HandyNotesWorldMapPinTemplate") do
        if pin.pluginName == PLUGIN_NAME and pin.GetPosition and pin.SetPosition then
            local x, y, insetIndex = pin:GetPosition()
            if IsFiniteNumber(x) and IsFiniteNumber(y) then
                local index = pinScratchCount + 1
                pinScratchCount = index
                pinScratchPins[index] = pin
                pinScratchX[index] = x
                pinScratchY[index] = y
                pinScratchInset[index] = insetIndex
                pinScratchMoved[index] = false
            end
        end
    end

    if pinScratchCount == 0 then return end -- before the POI query: most maps have none of our pins

    local poiPositions = GetPoiPositionsForMap(mapID)
    if #poiPositions > 0 then
        for index = 1, pinScratchCount do
            local x, y, moved = NudgeAwayFromClosestPoi(pinScratchX[index], pinScratchY[index], poiPositions, width, height)
            pinScratchX[index] = x
            pinScratchY[index] = y
            pinScratchMoved[index] = moved
        end
    end

    SeparateOwnPins(pinScratchX, pinScratchY, pinScratchMoved, pinScratchCount, width, height)

    for index = 1, pinScratchCount do
        if pinScratchMoved[index] then
            local x = math.min(math.max(pinScratchX[index], 0.01), 0.99)
            local y = math.min(math.max(pinScratchY[index], 0.01), 0.99)
            pinScratchPins[index]:SetPosition(x, y, pinScratchInset[index])
        end
    end
end

local vendorPinLayeringInstalled = false

local function InstallVendorPinLayering()
    if vendorPinLayeringInstalled or not HandyNotes.WorldMapDataProvider or not hooksecurefunc then return end
    vendorPinLayeringInstalled = true
    -- Hook every plugin's refresh: any plugin can pull a pin we raised out of the shared pool.
    hooksecurefunc(HandyNotes.WorldMapDataProvider, "RefreshPlugin", function(_, pluginName)
        RaiseVendorPins()
        -- Own refresh only: our pins are re-acquired just then, so running these on another
        -- plugin's refresh would move and grow already-adjusted pins again.
        if pluginName == PLUGIN_NAME then
            ApplyPinPlacementAdjustments()
            GrowVendorPinSize()
        end
    end)
end

-------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Full no-op when Homestead (or its dev build) is enabled. At PLAYER_LOGIN
    -- every enabled addon has finished loading, so the check is reliable.
    -- Second return is the fully-loaded flag (first is loaded-or-loading).
    local _, homesteadLoaded = C_AddOns.IsAddOnLoaded("Homestead")
    local _, devBuildLoaded = C_AddOns.IsAddOnLoaded("Homestead_DevBuild")
    if homesteadLoaded or devBuildLoaded then return end

    db = LibStub("AceDB-3.0"):New("HandyNotesHomesteadDB", defaults, true)
    HBD = LibStub("HereBeDragons-2.0")
    iconpath = ResolveIcon()
    summaryIconpath = iconpath
    LibStub("AceEvent-3.0"):Embed(HNH)

    RegisterSummaryMapProvider()
    InstallVendorPinLayering()

    HandyNotes:RegisterPluginDB(PLUGIN_NAME, HNH, options)

    -- HandyNotes' own OnEnable pin sweep ran before this registration;
    -- without this notify, minimap pins would not appear until a zone change.
    HNH:SendMessage("HandyNotes_NotifyUpdate", PLUGIN_NAME)
end)
