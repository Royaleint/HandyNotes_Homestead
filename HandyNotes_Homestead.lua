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
-- SetScalingLimits). Gate 2 tuning (2026-08-11/12) walked 12px -> 24 -> 9
-- -> 14; settled on 1.35 (~16px), the de-facto ecosystem standard for
-- vendor nodes (zarillion handynotes-plugins core/nodes.lua Vendor class).
-- Minimap pins at 12px match Homestead's minimap size and stay untouched.
local WORLD_PIN_SCALE = 1.35
local MINIMAP_PIN_SCALE = 1.0

-------------------------------------------------------------------------------
-- Continent-level nodes
--
-- The generated data keys nodes by each vendor's own zone map, so continent
-- maps have nothing to draw (Gate 2 finding, 2026-08-12). Project zone
-- coords up to the continent once per continent, on first view, via
-- HereBeDragons (a hard dependency of HandyNotes itself, so always present).
-------------------------------------------------------------------------------

local HBD
local continentNodes = {}

local function ZoneContinent(zoneMapID)
    local info = C_Map.GetMapInfo(zoneMapID)
    while info and info.mapType and info.mapType > Enum.UIMapType.Continent do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return (info and info.mapType == Enum.UIMapType.Continent) and info.mapID or nil
end

local function GetContinentNodes(continentMapID)
    local nodes = continentNodes[continentMapID]
    if nodes then return nodes end
    nodes = {}
    for zoneMapID, zoneNodes in next, ns.Nodes do
        if ZoneContinent(zoneMapID) == continentMapID then
            for zoneCoord, npcID in next, zoneNodes do
                local x = math.floor(zoneCoord / 10000) / 10000
                local y = (zoneCoord % 10000) / 10000
                local cx, cy = HBD:TranslateZoneCoordinates(x, y, zoneMapID, continentMapID)
                if cx and cy then
                    local coord = math.floor(cx * 10000 + 0.5) * 10000 + math.floor(cy * 10000 + 0.5)
                    -- Projection compresses zones; nudge packed collisions
                    -- (+0.0001 y) rather than dropping a vendor.
                    while nodes[coord] do coord = coord + 1 end
                    nodes[coord] = npcID
                end
            end
        end
    end
    continentNodes[continentMapID] = nodes
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
        local coord, npcID = next(nodes, prestate)
        while coord do
            local vendor = ns.Vendors[npcID]
            -- faction is pre-baked by the exporter: present only when the
            -- vendor is effectively Alliance/Horde; absent = show to all.
            if vendor and (not vendor.faction or vendor.faction == playerFaction) then
                return coord, nil, iconpath, pathScale * db.profile.icon_scale, db.profile.icon_alpha
            end
            coord, npcID = next(nodes, coord)
        end
        return nil
    end

    function HNH:GetNodes2(uiMapID, minimap)
        playerFaction = UnitFactionGroup("player")
        pathScale = minimap and MINIMAP_PIN_SCALE or WORLD_PIN_SCALE
        local nodes = ns.Nodes[uiMapID]
        if not nodes and not minimap then
            local info = C_Map.GetMapInfo(uiMapID)
            if info and info.mapType == Enum.UIMapType.Continent then
                nodes = GetContinentNodes(uiMapID)
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
        for _, itemID in ipairs(vendor.items) do
            local itemName = C_Item.GetItemInfo(itemID)
            if not itemName then pending = true end
            tooltip:AddLine(itemName or "...", 1, 1, 1)
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
        -- load completes, instead of waiting for a re-hover (Gate 2 finding,
        -- 2026-08-12). ContinueOnItemLoad fires immediately for cached items,
        -- so only the misses register callbacks.
        local pin = self
        for _, itemID in ipairs(vendor.items) do
            -- DoesItemExistByID separates "uncached" from "removed from the
            -- game": ContinueOnItemLoad THROWS on nonexistent itemIDs, and a
            -- patch can remove a shipped itemID during the stale-data window
            -- between releases. Nonexistent items keep the plain "..." line.
            if not C_Item.GetItemInfo(itemID) and C_Item.DoesItemExistByID(itemID) then
                Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
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

    -- Full no-op when Homestead is enabled. At PLAYER_LOGIN every enabled
    -- addon has finished loading, so the check is reliable. Second return is
    -- the fully-loaded flag (first is loaded-or-loading).
    local _, homesteadLoaded = C_AddOns.IsAddOnLoaded("Homestead")
    if homesteadLoaded then return end

    db = LibStub("AceDB-3.0"):New("HandyNotesHomesteadDB", defaults, true)
    iconpath = ResolveIcon()
    HBD = LibStub("HereBeDragons-2.0")
    LibStub("AceEvent-3.0"):Embed(HNH)

    HandyNotes:RegisterPluginDB("Homestead", HNH, options)

    -- HandyNotes' own OnEnable pin sweep ran before this registration;
    -- without this notify, minimap pins would not appear until a zone change.
    HNH:SendMessage("HandyNotes_NotifyUpdate", "Homestead")
end)
