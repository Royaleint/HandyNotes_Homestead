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
local MINIMAP_PIN_SCALE = 1.0

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

-- Keep HNH's summary geography aligned with Homestead's established map rules.
-- These are display rules only; the generated vendor data remains unchanged.
local excludedContinents = { [572] = true, [1550] = true }
local continentMergesInto = { [905] = 619 }
local continentOverlaysOnParent = { [2537] = 13 }
local overlayZoneExclusions = {
    [2537] = {
        [2405] = true, [15958] = true, [2444] = true, [2694] = true, [2576] = true, [2413] = true,
        [2599] = true, -- Val is native to the Quel'Thalas map, not the EK overlay.
    },
}

local function DisplayContinent(continentMapID)
    return continentMergesInto[continentMapID] or continentOverlaysOnParent[continentMapID] or continentMapID
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
                    if vendor and (not vendor.faction or vendor.faction == faction) then
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
        for _, zoneMapID in ipairs(zoneMapIDs) do
            local vendors = {}
            for _, npcID in next, ns.Nodes[zoneMapID] do
                local vendor = ns.Vendors[npcID]
                if vendor and (not vendor.faction or vendor.faction == faction) then
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
            if vendor and (not vendor.faction or vendor.faction == playerFaction) then
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

-- Identity token for the active hover: item-load callbacks compare against
-- it so a callback for a pin the mouse already left does nothing.
local currentHover

-- Formats an item's cost for display: gold via GetCoinTextureString (coin
-- icons built in), currencies via a live GetCurrencyInfo icon lookup with a
-- name fallback. Mirrors Homestead's own VendorData:FormatCost, which
-- resolves both live at render time rather than baking a name/icon into the
-- export at build time. No API-existence guard: the .toc is retail-only and
-- both calls exist on every flavor — unlike Homestead's version, which has
-- a real hand-rolled fallback if the guard ever trips, this one would just
-- go silent, so an unreachable guard here is worse than no guard.
--
-- Result is memoized on the item table itself: the underlying cost DATA
-- never changes once loaded, but RenderTooltip below re-runs in full on
-- every uncached-name load callback, and recomputing GetCurrencyInfo on
-- every re-render would amplify an existing O(n^2) hover cost on a large
-- vendor. `false` means "computed, no cost data"; nil means "not computed
-- yet". Caching for the session means a degraded first-hover result
-- (GetCurrencyInfo returning no name/icon yet) can't self-correct on a
-- later hover the way an unmemoized call would — near-unreachable since
-- currency info is client-side static data Blizzard itself calls
-- unguarded, but the RESOLVED STRING, unlike the data, is in principle a
-- one-shot snapshot.
-- Grey (matches the location/"Wares unknown" convention below, 0.7,0.7,0.7).
local OTHER_COST_TEXT = "|cFFB3B3B3(other cost)|r"

local function FormatCost(item)
    if item.costCache ~= nil then
        if item.costCache == false then return nil end
        return item.costCache
    end

    local parts = {}
    -- Set by a degraded currency lookup below; combined with item.otherCost
    -- after the loop rather than appended immediately, so the marker always
    -- lands last regardless of which currency (if any) failed to resolve —
    -- otherwise a first-currency failure with a later successful one would
    -- render "(other cost) + 50 <icon>", marker before the amount.
    local needsOtherCost = false

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
                -- Currency lookup returned neither icon nor name (rare,
                -- degraded path). Never print the raw currency ID to a
                -- player — fall back to the same honest "can't show this"
                -- marker the out-of-scope-cost path uses.
                needsOtherCost = true
            end
        end
    end
    -- LOAD-BEARING, not cosmetic: this is the only thing standing between a
    -- price-carrying otherCost row (e.g. "800g" on an item that really costs
    -- 800g + reagents) and the understated-price defect this feature was
    -- built to avoid. The exporter guarantees every such row sets
    -- item.otherCost — nothing else in this file re-derives or re-checks
    -- that. If this branch is ever dropped, short-circuited, or refactored
    -- away, the understated price comes back silently: tests and luacheck
    -- both pass, because the export data is correct — only the tooltip lies.
    if item.otherCost then
        needsOtherCost = true
    end
    if needsOtherCost then
        parts[#parts + 1] = OTHER_COST_TEXT
    end

    if #parts == 0 then
        item.costCache = false
        return nil
    end
    item.costCache = table.concat(parts, " + ")
    return item.costCache
end

-- Writes the full tooltip body for a vendor. Returns true when at least one
-- item name was still uncached (rendered as "...").
local function RenderTooltip(vendor)
    local tooltip = GameTooltip
    tooltip:SetText(vendor.name)

    local location = vendor.subzone or vendor.zone
    if vendor.subzone and vendor.zone then
        location = vendor.subzone .. ", " .. vendor.zone
    end
    if location then
        tooltip:AddLine(location, 0.7, 0.7, 0.7)
    end

    local pending = false
    if #vendor.items > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine("Wares:", 1, 0.82, 0)
        for _, item in ipairs(vendor.items) do
            local itemName = C_Item.GetItemInfo(item.id)
            if not itemName then pending = true end
            local cost = FormatCost(item)
            if cost then
                tooltip:AddDoubleLine(itemName or "...", cost, 1, 1, 1, 1, 1, 1)
            else
                tooltip:AddLine(itemName or "...", 1, 1, 1)
            end
        end
    else
        tooltip:AddLine(" ")
        tooltip:AddLine("Wares unknown", 0.7, 0.7, 0.7)
    end

    tooltip:Show()
    return pending
end

function HNH:OnEnter(uiMapID, coord)
    local node = NodeAt(uiMapID, coord, UnitFactionGroup("player"))
    if not node then return end

    local tooltip = GameTooltip
    if self:GetCenter() > UIParent:GetCenter() then
        tooltip:SetOwner(self, "ANCHOR_LEFT")
    else
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
    end

    -- luacheck: ignore 113
    if type(node) == "table" and (node.kind == "zoneSummary" or node.kind == "continentSummary") then
        currentHover = nil
        local summaryMapID = node.mapID or node.zoneMapID
        local summaryMap = C_Map.GetMapInfo(summaryMapID)
        local summaryLabel = node.kind == "continentSummary" and "continent" or "zone"
        tooltip:SetText(summaryMap and summaryMap.name or ("Unknown " .. summaryLabel))
        tooltip:AddLine(node.vendorCount .. " vendors")
        tooltip:AddLine("Click to view " .. summaryLabel)
        tooltip:Show()
        return
    end

    local vendor = ns.Vendors[node]
    if not vendor then return end

    local token = {}
    currentHover = token

    if RenderTooltip(vendor) then
        -- Uncached names rendered as "...": re-render in place as each item
        -- load completes, instead of waiting for a re-hover (in-game finding,
        -- 2026-08-12). ContinueOnItemLoad fires immediately for cached items,
        -- so only the misses register callbacks.
        local pin = self
        for _, item in ipairs(vendor.items) do
            -- DoesItemExistByID separates "uncached" from "removed from the
            -- game": ContinueOnItemLoad THROWS on nonexistent itemIDs, and a
            -- patch can remove a shipped itemID during the stale-data window
            -- between releases. Nonexistent items keep the plain "..." line.
            if not C_Item.GetItemInfo(item.id) and C_Item.DoesItemExistByID(item.id) then
                Item:CreateFromItemID(item.id):ContinueOnItemLoad(function()
                    if currentHover == token and GameTooltip:IsOwned(pin) then
                        RenderTooltip(vendor)
                    end
                end)
            end
        end
    end
end

function HNH:OnLeave()
    currentHover = nil
    GameTooltip:Hide()
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
