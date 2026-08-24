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
local SUMMARY_ICON = "Interface\\MINIMAP\\TRACKING\\FlightMaster"

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

local function ResolveSummaryIcon()
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SUMMARY_ICON)
    local file = info and (info.file or info.filename)
    if not file then
        return FALLBACK_ICON
    end
    return SUMMARY_ICON
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

local continentNodes = {}
local summaryIconpath = FALLBACK_ICON

local function ZoneContinent(zoneMapID)
    local info = C_Map.GetMapInfo(zoneMapID)
    while info and info.mapType and info.mapType > Enum.UIMapType.Continent do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return (info and info.mapType == Enum.UIMapType.Continent) and info.mapID or nil
end

local function GetContinentNodes(continentMapID, faction)
    local factionKey = faction or "Neutral"
    local continentCache = continentNodes[continentMapID]
    if not continentCache then
        continentCache = {}
        continentNodes[continentMapID] = continentCache
    end
    local nodes = continentCache[factionKey]
    if nodes then return nodes end

    nodes = {}
    continentCache[factionKey] = nodes
    ns.ZoneSummaryProjectionFailures = ns.ZoneSummaryProjectionFailures or {}
    local failures = {}
    ns.ZoneSummaryProjectionFailures[continentMapID] = failures

    local zoneMapIDs = {}
    for zoneMapID in next, ns.Nodes do
        local info = C_Map.GetMapInfo(zoneMapID)
        if info and info.mapType and info.mapType > Enum.UIMapType.Continent and ZoneContinent(zoneMapID) == continentMapID then
            zoneMapIDs[#zoneMapIDs + 1] = zoneMapID
        end
    end
    table.sort(zoneMapIDs)

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
            local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zoneMapID, continentMapID)
            if not minX or not maxX or not minY or not maxY then
                failures[zoneMapID] = "Map rectangle unavailable"
            elseif minX >= maxX or minY >= maxY then
                failures[zoneMapID] = "Map rectangle is degenerate"
            else
                local x = minX + (maxX - minX) * 0.5
                local y = minY + (maxY - minY) * 0.5
                local coord = math.floor(x * 10000 + 0.5) * 10000 + math.floor(y * 10000 + 0.5)
                while nodes[coord] do coord = coord + 1 end
                nodes[coord] = {
                    kind = "zoneSummary",
                    zoneMapID = zoneMapID,
                    vendorCount = vendorCount,
                }
            end
        end
    end
    return nodes
end

-- Node lookup shared by tooltip and click handlers: zone nodes come from the
-- generated data, continent nodes from the projected cache.
local function NodeAt(uiMapID, coord)
    local nodes = ns.Nodes[uiMapID] or continentNodes[uiMapID]
    return nodes and nodes[coord] or nil
end

do
    local playerFaction, pathScale

    local function iter(nodes, prestate)
        if not nodes then return nil end
        local coord, node = next(nodes, prestate)
        while coord do
            -- luacheck: ignore 113
            if type(node) == "table" and node.kind == "zoneSummary" then
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
                nodes = GetContinentNodes(uiMapID, playerFaction)
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
    local npcID = NodeAt(uiMapID, coord)
    local vendor = npcID and ns.Vendors[npcID]
    if not vendor then return end

    local tooltip = GameTooltip
    if self:GetCenter() > UIParent:GetCenter() then
        tooltip:SetOwner(self, "ANCHOR_LEFT")
    else
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
    end

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
    iconpath = ResolveIcon()
    summaryIconpath = ResolveSummaryIcon()
    LibStub("AceEvent-3.0"):Embed(HNH)

    HandyNotes:RegisterPluginDB("Homestead", HNH, options)

    -- HandyNotes' own OnEnable pin sweep ran before this registration;
    -- without this notify, minimap pins would not appear until a zone change.
    HNH:SendMessage("HandyNotes_NotifyUpdate", "Homestead")
end)
