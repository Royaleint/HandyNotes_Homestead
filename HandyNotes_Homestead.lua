--[[
    HandyNotes_Homestead
    Housing decor vendor pins as a HandyNotes plugin, powered by Homestead's
    verified vendor data (see Data.lua, generated).

    Steps aside entirely when full Homestead is enabled: Homestead renders
    its own richer pins, and running both would double every vendor pin.
]]

local _, ns = ...

local HNH = {}
local db
local iconpath

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

-- HandyNotes renders world-map pins at 12px x scale (screen-anchored via
-- SetScalingLimits). Pin-size tuning (2026-08-11/12) walked 12px -> 24 -> 9
-- -> 14; settled on 1.35 (~16px), the de-facto ecosystem standard for
-- vendor nodes (zarillion handynotes-plugins core/nodes.lua Vendor class).
-- Minimap pins at 12px match Homestead's minimap size and stay untouched.
local WORLD_PIN_SCALE = 1.35
local MINIMAP_PIN_SCALE = 1.15

-------------------------------------------------------------------------------
-- Continent-level nodes
--
-- The generated data keys nodes by each vendor's own zone map, so continent
-- maps have nothing to draw (in-game finding, 2026-08-12). Build one summary
-- per zone at its rectangle center when the continent is first viewed.
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

function HNH:GetSummaryVisualSizes(uiScale)
    uiScale = uiScale or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local scaleCompensation = uiScale > 0 and (1 / uiScale) or 1
    local adjustedSize = math.floor((11 * scaleCompensation) + 0.5)
    local iconSize = math.floor((adjustedSize * 1.15) + 0.5)
    return adjustedSize, iconSize
end

function HNH:GetSummaryFrameLayering()
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
    GameTooltip:SetText(mapInfo and mapInfo.name or "Unknown map")
    GameTooltip:AddLine(tostring(node.vendorCount) .. " vendors")
    GameTooltip:AddLine("Click to view " .. (node.kind == "continentSummary" and "continent" or "zone"))
    GameTooltip:Show()
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
        local frame = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
        local strata, frameLevel = HNH:GetSummaryFrameLayering()
        frame:SetFrameStrata(strata)
        frame:SetFrameLevel(frameLevel)
        frame:SetSize(adjustedSize, adjustedSize + fontSize + textOffset)
        frame:EnableMouse(true)
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)
        frame.icon:SetSize(iconSize, iconSize)
        if type(summaryIconpath) == "table" then
            frame.icon:SetTexture(summaryIconpath.icon)
            frame.icon:SetTexCoord(summaryIconpath.tCoordLeft, summaryIconpath.tCoordRight, summaryIconpath.tCoordTop, summaryIconpath.tCoordBottom)
        else
            frame.icon:SetTexture(summaryIconpath)
        end
        frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal", 2)
        frame.count:SetPoint("TOP", frame.icon, "BOTTOM", 0, -textOffset)
        frame.count:SetText(tostring(node.vendorCount))
        local fontPath = frame.count:GetFont()
        frame.count:SetFont(fontPath, fontSize, "OUTLINE")
        frame.count:SetTextColor(1, 1, 1)
        frame.count:SetShadowColor(0, 0, 0, 1)
        frame.count:SetShadowOffset(1, -1)
        frame:SetScript("OnEnter", function(self) HNH:ShowSummaryTooltip(self, node) end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and WorldMapFrame.SetMapID then
                WorldMapFrame:SetMapID(node.mapID or node.zoneMapID)
            end
        end)
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
            -- luacheck: ignore 113
            if type(node) == "table" and (node.kind == "zoneSummary" or node.kind == "continentSummary") then
                return coord, nil, summaryIconpath, pathScale * db.profile.icon_scale, db.profile.icon_alpha
            end
            local vendor = ns.Vendors[node]
            -- faction is pre-baked by the exporter: present only when the
            -- vendor is effectively Alliance/Horde; absent = show to all.
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

-- Formats an item's cost for display: gold via GetCoinTextureString (coin
-- icons built in), currencies via a live GetCurrencyInfo icon lookup with a
-- name fallback, and item-based reagent costs via GetItemIconByID with a
-- GetItemNameByID fallback. Mirrors Homestead's own VendorData:FormatCost,
-- which resolves all three live at render time rather than baking a
-- name/icon into the export at build time. No API-existence guard: the .toc
-- is retail-only and every call here exists on every flavor — unlike
-- Homestead's version, which has a real hand-rolled fallback if the guard
-- ever trips, this one would just go silent, so an unreachable guard here is
-- worse than no guard.
--
-- The "(other cost)" marker covers namedCosts rows (none live today — see
-- item.otherCost below) and the degraded lookup paths: a currency or reagent
-- item whose icon and name both fail to resolve. GetCurrencyInfo and
-- GetItemIconByID/GetItemNameByID are client-side static data and routinely
-- return nil for an item or currency the player has never held — this is
-- the ordinary case for a reagent used as a price, not a rare edge case:
-- Blizzard's own cost-item code (e.g. Blizzard_ItemUpgradeUI.lua) treats it
-- as expected and re-resolves lazily rather than caching a degraded result.
--
-- Returns (cost, complete). `complete` is false whenever any lookup in this
-- call (currency or reagent item) came back with neither icon nor name — a
-- degraded result is NEVER written to item.costCache, so the next render
-- recomputes it from scratch, and RefreshVendorItems below requests the
-- missing item data so that next render actually happens once it lands.
-- A fully resolved string IS memoized on the item table (`complete == true`)
-- because the underlying cost DATA never changes once loaded, and
-- recomputing GetCurrencyInfo/GetItemIconByID on every re-render would
-- amplify an existing O(n^2) hover cost on a large vendor. `item.costCache
-- == false` means "computed, no cost data" (a genuinely free item); nil
-- means "not computed yet".
-- Grey (matches the location/"Wares unknown" convention below, 0.7,0.7,0.7).
local OTHER_COST_TEXT = "|cFFB3B3B3(other cost)|r"

local function FormatCost(item)
    if item.costCache ~= nil then
        if item.costCache == false then return nil, true end
        return item.costCache, true
    end

    local parts = {}
    -- Set by a degraded currency/item lookup below; combined with
    -- item.otherCost after the loops rather than appended immediately, so
    -- the marker always lands last regardless of which entry (if any)
    -- failed to resolve — otherwise a first-currency failure with a later
    -- successful one would render "(other cost) + 50 <icon>", marker before
    -- the amount.
    local needsOtherCost = false
    -- True only when a currency/item lookup came back degraded (see the
    -- header comment) — distinct from needsOtherCost, which also covers the
    -- permanent namedCosts marker below. A degraded result must never be
    -- cached; a namedCosts marker is permanent and safe to cache.
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
                -- Currency lookup returned neither icon nor name — the
                -- ordinary state for an uncached currency, not a rare edge
                -- case. Never print the raw currency ID to a player — fall
                -- back to the same honest "can't show this" marker the
                -- out-of-scope-cost path uses, and do not cache this result.
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
                    -- Item lookup returned neither icon nor name — the
                    -- ordinary state for a reagent the player has never
                    -- held, not a rare edge case (see header comment).
                    -- Never print the raw item ID to a player — fall back
                    -- to the same honest "can't show this" marker the
                    -- out-of-scope-cost path uses, and do not cache this
                    -- result.
                    needsOtherCost = true
                    degraded = true
                end
            end
        end
    end
    -- LOAD-BEARING, not cosmetic: this is the only thing standing between a
    -- price-carrying otherCost row (e.g. "800g" on an item that really costs
    -- 800g + a named favor) and the understated-price defect this feature
    -- was built to avoid. The exporter guarantees every such row (namedCosts
    -- today) sets item.otherCost — nothing else in this file re-derives or
    -- re-checks that. If this branch is ever dropped, short-circuited, or
    -- refactored away, the understated price comes back silently: tests and
    -- luacheck both pass, because the export data is correct — only the
    -- tooltip lies.
    if item.otherCost then
        needsOtherCost = true
    end
    if needsOtherCost then
        parts[#parts + 1] = OTHER_COST_TEXT
    end

    local cost = (#parts > 0) and table.concat(parts, " + ") or nil
    if degraded then
        -- Do not memoize: this render's cost may be missing a currency or
        -- reagent name/icon that simply hasn't loaded yet. Returning
        -- complete == false tells the caller to keep this hover "pending"
        -- so RefreshVendorItems requests the missing item data and the next
        -- render (triggered by that load) recomputes instead of reusing a
        -- frozen degraded string.
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
        tooltip:AddLine("Wares:", 1, 0.82, 0)
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
        if matches == 0 then tooltip:AddLine("No matching wares", 0.7, 0.7, 0.7) end
    else
        tooltip:AddLine(" ")
        tooltip:AddLine("Wares unknown", 0.7, 0.7, 0.7)
    end

    tooltip:Show()
    return pending
end

-- The interactive tooltip IS a GameTooltip (same template, same AddLine /
-- AddDoubleLine rendering as the plain path) so the two look identical; the
-- only additions are a MinimalScrollBar down the right edge and a search box
-- along the bottom, both sitting in padding the tooltip reserves for them.
-- GameTooltip_OnHide clears that padding, so it is re-applied on every render.
-- MinimalScrollBar is an 8px track but its stepper arrows are 17px wide,
-- centred on it; the column must fit the arrows, not the track.
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
    frame:AddLine("Wares:", 1, 0.82, 0)
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
    if matchIndex == 0 then frame:AddLine("No matching wares", 0.7, 0.7, 0.7) end
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
        -- A reagent icon/name resolving after the width was measured must
        -- also trigger a re-measure, so resolved counts resolved ware names
        -- PLUS complete costs, not just names.
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

    -- The window of 15 names changes width as it scrolls, and a tooltip that
    -- resizes under the cursor is hard to scroll and can slide out from under
    -- it (which closes it). So the width is measured from a full render of
    -- EVERY ware (query ignored, so a search typed mid-load cannot freeze a
    -- narrow width) and frozen for the vendor. It is re-measured only when
    -- another name has resolved since the last measure — "..." is narrower
    -- than the real name — so an item that never loads cannot keep the
    -- measure running, and a zero width (rect not yet valid) is not recorded,
    -- so the next render measures again instead of freezing the floor.
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
    -- Anchor once per hover, and only from a usable height: a zero height
    -- (rect not valid yet) would read as "room below" for every pin and hand
    -- the low-pin clamping bug back, so the pin is held until a later render.
    -- Never re-anchor on later renders — a narrowing search shortens the
    -- tooltip and a flip would jump it out from under the cursor.
    if frame.anchorPin and frame:GetHeight() > 0 then
        AnchorInteractiveTooltip(frame, frame.anchorPin)
        frame.anchorPin = nil
    end
    SyncScrollBar(frame)
    return pending
end

-- Butts the tooltip edge-to-edge against the pin so the cursor can cross
-- onto it (a corner touch closes on the crossing check). The tooltip is
-- ~300px tall, so for a pin low on the map hanging down from the pin's top
-- would overhang the screen and SetClampedToScreen would slide it up off
-- the pin; in that case it rises from the pin's bottom instead. Decided
-- after the first render, when the tooltip's height is known. The vertical
-- test is in screen pixels because the pin lives on the scaled map canvas
-- (HandyNotes pins scale 1.0-1.2x with zoom); the left/right flip compares
-- raw centres, which only shifts the flip point a little right of centre
-- where either side has room.
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
    tooltipSearchBox.Instructions:SetText("Search wares...")
    tooltipSearchBox:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        if suppressTooltipSearchChanged then return end
        if tooltipSearchTimer then tooltipSearchTimer:Cancel() end
        local token = currentHover
        if not token then return end
        -- luacheck: ignore 113
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

-- Shared by the ware-name request below and the reagent-cost request: asks
-- the client to load one item's data and re-renders the still-active hover
-- when it lands. Two call sites, one callback shape.
local function RequestItemLoad(itemID, token, render)
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        if currentHover == token then render(token.vendor) end
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

    -- luacheck: ignore 113
    if type(node) == "table" and (node.kind == "zoneSummary" or node.kind == "continentSummary") then
        currentHover = nil
        CloseInteractiveTooltip()
        if plainTooltip then plainTooltip:Hide() end
        local summaryMapID = node.mapID or node.zoneMapID
        local summaryMap = C_Map.GetMapInfo(summaryMapID)
        local summaryLabel = node.kind == "continentSummary" and "continent" or "zone"
        local tooltip = GameTooltip
        tooltip:SetOwner(self, self:GetCenter() > UIParent:GetCenter() and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        tooltip:SetText(summaryMap and summaryMap.name or ("Unknown " .. summaryLabel))
        tooltip:AddLine(node.vendorCount .. " vendors")
        tooltip:AddLine("Click to view " .. summaryLabel)
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
    -- luacheck: ignore 113
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
    -- luacheck: ignore 113
    if type(node) == "table" and (node.kind == "zoneSummary" or node.kind == "continentSummary") then
        -- luacheck: ignore 113
        if WorldMapFrame and WorldMapFrame.SetMapID then
            WorldMapFrame:SetMapID(node.mapID or node.zoneMapID)
        end
        return
    end
    -- Same guard + construction as Homestead's Utils/waypoints.lua: some
    -- maps reject user waypoints.
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
    desc = "Housing decor vendor locations",
    get = function(info) return db.profile[info.arg] end,
    set = function(info, value)
        db.profile[info.arg] = value
        HNH:SendMessage("HandyNotes_NotifyUpdate", "Homestead")
    end,
    args = {
        desc = {
            name = "Housing decor vendor pins powered by Homestead's vendor data.",
            type = "description",
            order = 0,
        },
        icon_scale = {
            type = "range",
            name = "Icon Scale",
            desc = "Size of the vendor pins.",
            min = 0.25, max = 2, step = 0.01,
            arg = "icon_scale",
            order = 1,
        },
        icon_alpha = {
            type = "range",
            name = "Icon Alpha",
            desc = "Transparency of the vendor pins.",
            min = 0.1, max = 1, step = 0.01,
            arg = "icon_alpha",
            order = 2,
        },
    },
}

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

    HandyNotes:RegisterPluginDB("Homestead", HNH, options)

    -- HandyNotes' own OnEnable pin sweep ran before this registration;
    -- without this notify, minimap pins would not appear until a zone change.
    HNH:SendMessage("HandyNotes_NotifyUpdate", "Homestead")
end)
