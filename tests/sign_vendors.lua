-- luacheck: push ignore 111 112 113

-- Midnight profession shop-sign vendor pins: hidden until the account has the
-- profession's achievement, shown whenever that cannot be told. Flat harness: every
-- stub is local to one boot of the plugin, and events are fired on the plugin's own frame.

local function check(condition, message)
    if not condition then
        error(message, 2)
    end
end

-- npcID, achievement ID
local SIGN_VENDORS = {
    { 243359, 42788 }, { 241451, 42792 }, { 257914, 42795 }, { 243350, 42787 },
    { 241453, 42798 }, { 258507, 42797 }, { 256026, 42793 }, { 243555, 42796 },
    { 258480, 42789 }, { 243531, 42786 }, { 258540, 42791 }, { 256009, 42790 },
    { 243353, 42794 },
}
local ORDINARY_VENDOR = 9001

local function makeData()
    local data = { Nodes = { [18] = { [10001000] = ORDINARY_VENDOR } }, Vendors = {
        [ORDINARY_VENDOR] = { name = "Ordinary vendor", zone = "Tirisfal Glades", items = { { id = 1 } } },
    } }
    for index, pair in ipairs(SIGN_VENDORS) do
        data.Nodes[18][20000000 + index * 1000] = pair[1]
        data.Vendors[pair[1]] = { name = "Sign vendor " .. pair[1], zone = "Tirisfal Glades", items = { { id = 2 } } }
    end
    return data
end

-- opts.earned: achievement ID -> { completed, earnedByMe }; opts.noApi leaves GetAchievementInfo undefined;
-- opts.unknown makes it return nothing.
local function boot(opts)
    opts = opts or {}
    local ctx = { notify = 0, events = {}, earned = opts.earned or {}, data = makeData() }

    local function makeTooltip()
        local tooltip = {}
        function tooltip:SetOwner() end
        function tooltip:SetFrameStrata() end
        function tooltip:SetClampedToScreen() end
        function tooltip:SetText() end
        function tooltip:ClearLines() end
        function tooltip:AddLine() end
        function tooltip:AddDoubleLine() end
        function tooltip:Show() end
        function tooltip:Hide() end
        function tooltip:HookScript() end
        return tooltip
    end

    _G.GameTooltip = makeTooltip()
    _G.UIParent = { GetCenter = function() return 0 end }
    _G.WorldMapFrame = nil
    _G.C_AddOns = { IsAddOnLoaded = function() return false, false end }
    _G.C_Texture = { GetAtlasInfo = function() return { file = 1 } end }
    _G.C_CurrencyInfo = {}
    _G.C_Item = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    -- Map 12 is a continent whose child zone is map 18.
    _G.C_Map = {
        GetMapInfo = function(mapID)
            if mapID == 12 then return { mapID = 12, mapType = 2, parentMapID = 0, name = "Continent" } end
            return { mapID = mapID, mapType = 3, parentMapID = 12, name = "Map " .. mapID }
        end,
        GetMapRectOnMap = function() return 0.2, 0.6, 0.2, 0.6 end,
    }
    _G.Enum = { UIMapType = { World = 1, Continent = 2 } }
    _G.UnitFactionGroup = function() return "Alliance" end
    _G.InCombatLockdown = function() return ctx.inCombat == true end
    _G.HandyNotes = {
        getXY = function(_, coord) return coord, coord end,
        RegisterPluginDB = function(_, _, handler) ctx.handler = handler end,
    }
    _G.LibStub = function(name)
        if name == "AceDB-3.0" then
            -- Holiday and endeavor tracking stay off so only the sign gate is exercised.
            return { New = function()
                return { profile = { icon_scale = 1, icon_alpha = 1,
                    show_holiday_vendors = false, show_endeavor_vendors = false } }
            end }
        elseif name == "HereBeDragons-2.0" then
            return {}
        elseif name == "AceEvent-3.0" then
            return { Embed = function(_, object)
                object.SendMessage = function(_, message)
                    if message == "HandyNotes_NotifyUpdate" then ctx.notify = ctx.notify + 1 end
                end
            end }
        end
        error("unexpected library: " .. name)
    end
    _G.CreateFrame = function()
        local frame = { scripts = {} }
        function frame:RegisterEvent(event) ctx.events[event] = true end
        function frame:UnregisterEvent(event) ctx.events[event] = nil end
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        ctx.frame = ctx.frame or frame
        return frame
    end
    _G.C_Timer = { After = function() end, NewTicker = function() return {} end }
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { month = 10, year = 2026, monthDay = 25 } end }
    _G.C_Calendar = {}
    _G.issecretvalue = function() return false end
    _G.C_NeighborhoodInitiative = {}
    _G.GetAchievementInfo = nil
    if not opts.noApi then
        -- id, name, points, completed, month, day, year, description, flags, icon, reward, isGuild, wasEarnedByMe
        _G.GetAchievementInfo = function(id)
            if opts.unknown then return end
            local entry = ctx.earned[id]
            return id, "Achievement " .. id, 10, entry and entry.completed or false, nil, nil, nil, "", 0, 0, "", false,
                entry and entry.earnedByMe or false
        end
    end

    assert(loadfile("Locale/enUS.lua"))(nil, ctx.data)
    assert(loadfile("HandyNotes_Homestead.lua"))(nil, ctx.data)
    ctx.frame.scripts.OnEvent(ctx.frame, "PLAYER_LOGIN")
    ctx.loginNotify = ctx.notify

    function ctx.fire(event, ...)
        ctx.frame.scripts.OnEvent(ctx.frame, event, ...)
    end
    -- npcIDs whose pin HandyNotes would draw on the zone map.
    function ctx.shown()
        local iter, nodes, state = ctx.handler:GetNodes2(18, false)
        local found = {}
        local coord = state
        while true do
            coord = iter(nodes, coord)
            if not coord then return found end
            found[nodes[coord]] = true
        end
    end
    -- Vendors the continent view counts across its zone summaries.
    function ctx.continentCount()
        local iter, nodes, state = ctx.handler:GetNodes2(12, false)
        local total = 0
        local coord = state
        while true do
            coord = iter(nodes, coord)
            if not coord then return total end
            total = total + (nodes[coord].vendorCount or 0)
        end
    end
    return ctx
end

-- Nothing earned: every sign vendor is locked, an ordinary vendor is not.
do
    local ctx = boot()
    local shown = ctx.shown()
    check(shown[ORDINARY_VENDOR], "a non-sign vendor is unaffected by the gate")
    for _, pair in ipairs(SIGN_VENDORS) do
        check(not shown[pair[1]], "npc " .. pair[1] .. " hidden while achievement " .. pair[2] .. " is unearned")
    end
end

-- Earned on another character: the account has it, so the pin shows. Each achievement
-- unlocks only its own vendor, which also proves all thirteen pairs are in the table.
do
    for _, target in ipairs(SIGN_VENDORS) do
        local ctx = boot({ earned = { [target[2]] = { completed = true, earnedByMe = false } } })
        local shown = ctx.shown()
        for _, pair in ipairs(SIGN_VENDORS) do
            check((shown[pair[1]] == true) == (pair == target),
                "achievement " .. target[2] .. " must unlock npc " .. target[1] .. " and no other (npc " .. pair[1] .. ")")
        end
    end
end

-- API missing or answering nothing: the pin is kept.
do
    for label, opts in pairs({ ["no API"] = { noApi = true }, ["unknown answer"] = { unknown = true } }) do
        local shown = boot(opts).shown()
        for _, pair in ipairs(SIGN_VENDORS) do
            check(shown[pair[1]], "npc " .. pair[1] .. " shown with " .. label)
        end
    end
end

-- Earning the achievement in session reveals the pin with one redraw; unrelated
-- achievements and repeat events do not redraw, and a refreshed account list does.
do
    local ctx = boot()
    local target = SIGN_VENDORS[7] -- Irodalmin
    check(ctx.events.ACHIEVEMENT_EARNED and ctx.events.RECEIVED_ACHIEVEMENT_LIST, "achievement events registered")
    check(not ctx.shown()[target[1]], "Irodalmin hidden before the achievement")

    ctx.fire("ACHIEVEMENT_EARNED", 12345, false)
    check(ctx.notify == ctx.loginNotify, "an unrelated achievement does not redraw")

    ctx.earned[target[2]] = { completed = true, earnedByMe = true }
    ctx.fire("ACHIEVEMENT_EARNED", target[2], false)
    check(ctx.notify == ctx.loginNotify + 1, "earning the sign achievement redraws once")
    check(ctx.shown()[target[1]], "Irodalmin shows once the achievement is earned")
    ctx.fire("ACHIEVEMENT_EARNED", target[2], true)
    check(ctx.notify == ctx.loginNotify + 1, "a repeat event with no change does not redraw")

    local other = SIGN_VENDORS[1]
    ctx.earned[other[2]] = { completed = true, earnedByMe = false }
    ctx.fire("RECEIVED_ACHIEVEMENT_LIST")
    check(ctx.notify == ctx.loginNotify + 2, "account achievement data arriving redraws when a verdict changed")
    check(ctx.shown()[other[1]], "an account-wide earn shows the pin after the list arrives")
end

-- The continent view's cached counts follow a verdict change in both directions.
do
    local ctx = boot()
    local target = SIGN_VENDORS[7]
    local before = ctx.continentCount()
    check(before == 1, "continent view counts only the ordinary vendor while every sign is locked")
    ctx.earned[target[2]] = { completed = true, earnedByMe = false }
    ctx.fire("ACHIEVEMENT_EARNED", target[2], false)
    check(ctx.continentCount() == before + 1, "an earned sign achievement adds its vendor to the continent count")
    ctx.earned[target[2]] = nil
    ctx.fire("RECEIVED_ACHIEVEMENT_LIST")
    check(ctx.continentCount() == before, "a refreshed account list that un-earns it takes the vendor back out")
end

-- An achievement earned in combat sends no redraw until combat ends, then exactly one.
do
    local ctx = boot()
    local target = SIGN_VENDORS[7]
    ctx.inCombat = true
    ctx.earned[target[2]] = { completed = true, earnedByMe = true }
    ctx.fire("ACHIEVEMENT_EARNED", target[2], false)
    check(ctx.notify == ctx.loginNotify, "no redraw is sent during combat")
    ctx.inCombat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check(ctx.notify == ctx.loginNotify + 1, "combat ending sends the deferred redraw once")
    ctx.fire("PLAYER_REGEN_ENABLED")
    check(ctx.notify == ctx.loginNotify + 1, "the deferred redraw is not sent twice")
end

print("PASS: profession sign vendors follow the account's achievements")

-- luacheck: pop
