-- luacheck: push ignore 111 112 113

-- HNH-009 regression harness: item-load callbacks that land in the same
-- frame must coalesce into one tooltip re-render (QueueTooltipRefresh),
-- not one re-render per item -- the O(n^2) cold-cache hover cost on a large
-- vendor this ticket exists to bound. Unlike hnh004_zone_summary.lua's
-- shared C_Timer.After mock (which resolves synchronously and so cannot
-- show two loads landing before a render fires), this harness defers After
-- callbacks into a queue the test fires by hand, the only way to observe
-- coalescing at all.

local function check(condition, message)
    if not condition then
        error(message, 2)
    end
end

local loaded = {}
local itemCallbacks = {}
local timerCallbacks = {}
local renderCount = 0
local registeredPlugin
local loginHandler
local loginFrame

local function makeTooltip()
    local tooltip = {}
    function tooltip:SetOwner() end
    function tooltip:SetFrameStrata() end
    function tooltip:SetClampedToScreen() end
    function tooltip:SetText() end
    function tooltip:ClearLines() end
    function tooltip:AddLine() end
    function tooltip:AddDoubleLine() end
    function tooltip:Show() renderCount = renderCount + 1 end
    function tooltip:Hide() end
    return tooltip
end

-- _G.X assignment throughout (matching hnh004_zone_summary.lua's harness),
-- not bare globals: these names are luacheck read_globals, and an unqualified
-- assignment to one of them is flagged as mutating a read-only global.
_G.GameTooltip = makeTooltip()
_G.UIParent = { GetCenter = function() return 0 end }

_G.C_AddOns = {
    IsAddOnLoaded = function() return false, false end,
}
_G.C_Texture = { GetAtlasInfo = function() return { file = 1 } end }
_G.C_CurrencyInfo = {
    GetCoinTextureString = function(price) return tostring(price) end,
    GetCurrencyInfo = function() return nil end,
}
_G.C_Item = {
    GetItemInfo = function(id) return loaded[id] and ("Item " .. id) or nil end,
    DoesItemExistByID = function() return true end,
    GetItemIconByID = function() return nil end,
    GetItemNameByID = function() return nil end,
}
_G.Item = {
    CreateFromItemID = function(_, id)
        return {
            ContinueOnItemLoad = function(_, callback)
                itemCallbacks[id] = callback
            end,
        }
    end,
}
_G.C_Map = { GetMapInfo = function() return nil end }
_G.Enum = { UIMapType = { Continent = 3 } }
_G.UnitFactionGroup = function() return "Neutral" end
_G.HandyNotes = {
    getXY = function(_, coord) return coord, coord end,
    RegisterPluginDB = function(_, _, plugin) registeredPlugin = plugin end,
}
_G.LibStub = function(name)
    if name == "AceDB-3.0" then
        return { New = function() return { profile = {} } end }
    elseif name == "HereBeDragons-2.0" then
        return { TranslateZoneCoordinates = function() return nil, nil end }
    elseif name == "AceEvent-3.0" then
        return { Embed = function(_, object) object.SendMessage = function() end end }
    end
    error("unexpected library: " .. name)
end
-- HNH's own tooltips are dedicated CreateFrame("GameTooltip", ...) frames,
-- not the shared GameTooltip global (RenderPlainTooltip/RenderInteractiveTooltip
-- both write to one of these) -- only the top-level PLAYER_LOGIN event frame
-- needs the plain login-frame shape.
_G.CreateFrame = function(kind)
    if kind == "GameTooltip" then
        return makeTooltip()
    end
    loginFrame = {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(_, _, callback) loginHandler = callback end,
    }
    return loginFrame
end
-- Deferred, unlike hnh004_zone_summary.lua's harness: queues callbacks for
-- the test to fire by hand instead of resolving them synchronously, which is
-- the only way to observe two loads landing before a re-render fires.
_G.C_Timer = {
    After = function(_, callback)
        timerCallbacks[#timerCallbacks + 1] = callback
    end,
}
_G.UiMapPoint = { CreateFromCoordinates = function() return {} end }
_G.C_SuperTrack = {}

local ns = {
    Nodes = { [1] = { [1234] = 9001 } },
    Vendors = {
        [9001] = {
            name = "Test vendor",
            zone = "Test zone",
            items = { { id = 101 }, { id = 102 }, { id = 103 } },
        },
    },
}

local addon = assert(loadfile("HandyNotes_Homestead.lua"))
addon(nil, ns)
loginHandler(loginFrame)

local pin = { GetCenter = function() return 0 end }
registeredPlugin.OnEnter(pin, 1, 1234)
check(renderCount == 1, "initial tooltip render")

local function finishItemLoad(id)
    loaded[id] = true
    check(itemCallbacks[id], "missing callback for item " .. id)
    itemCallbacks[id]()
end

-- Same-frame callbacks are the regression case: they must queue one refresh.
registeredPlugin.OnEnter(pin, 1, 1234)
check(renderCount == 2, "second initial tooltip render")
finishItemLoad(101)
finishItemLoad(102)
check(#timerCallbacks == 1, "same-frame item loads coalesce into one timer")
check(renderCount == 2, "same-frame item loads do not render immediately")

timerCallbacks[1]()
check(renderCount == 3, "coalesced timer performs one refresh")

-- A queued refresh for a pin that was left must not repaint a stale tooltip.
registeredPlugin.OnEnter(pin, 1, 1234)
check(renderCount == 4, "third initial tooltip render")
finishItemLoad(103)
check(#timerCallbacks == 2, "later item load queues a new refresh")
registeredPlugin.OnLeave(pin)
timerCallbacks[2]()
check(renderCount == 4, "stale queued refresh does not repaint after leave")

print("PASS: HNH-009 tooltip refreshes are coalesced per frame")

-- luacheck: pop
