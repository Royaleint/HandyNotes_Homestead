-- luacheck: push ignore 111 112 113

-- Holiday and endeavor vendor pins: shown only while their holiday or endeavor is
-- running, hidden whenever that can't be confirmed, and redrawn only when what is
-- shown changes. Flat harness: every stub is local to one boot of the plugin, timers
-- are queued and fired by hand, and events are fired on the plugin's own frame.

local function check(condition, message)
    if not condition then
        error(message, 2)
    end
end

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local TODAY = { month = 10, year = 2026, monthDay = 25 }

local function holidayEvent(eventID, sequenceType)
    return { eventID = eventID, calendarType = "HOLIDAY", sequenceType = sequenceType or "ONGOING" }
end

-- Fresh fixture per boot: the plugin folds the timed rows into Nodes and Vendors at login.
local function makeData(options)
    options = options or {}
    local data = {
        Nodes = { [18] = { [10001000] = 9001 } },
        Vendors = {
            [9001] = { name = "Ordinary vendor", zone = "Tirisfal Glades", items = { { id = 1 } } },
        },
    }
    if options.oldData then return data end
    data.TimedNodes = {
        [37] = { [20002000] = 273403 },
        [80] = { [30003000] = 15864 },
        [2351] = { [54305610] = 257897, [40004000] = 248525 },
        [2352] = { [53003820] = 257897, [41004100] = 248525 },
    }
    data.TimedVendors = {
        [273403] = {
            name = "Jack", zone = "Elwynn Forest", faction = "Alliance",
            items = { { id = 2, currencies = { { id = 1, amount = 5 } } } },
            kind = "event", event = "Hallow's End", holidayIDs = { 324 },
        },
        [15864] = {
            name = "Valadar Starsong", zone = "Moonglade", items = { { id = 3 } },
            kind = "event", event = "Lunar Festival", holidayIDs = { 327 },
        },
        [257897] = {
            name = "Harlowe Marl", zone = "Founder's Point",
            factionByMap = { [2351] = "Horde", [2352] = "Alliance" },
            items = { { id = 4 } }, kind = "endeavor", theme = "Niffen",
        },
        [248525] = {
            name = "Pascal-K1N6", zone = "Razorwind Shores",
            factionByMap = { [2351] = "Horde", [2352] = "Alliance" },
            items = { { id = 5 } }, kind = "endeavor", theme = "Mechagnome",
        },
    }
    data.EndeavorThemes = {
        ids = { [15] = "Blood Elf", [17] = "Mechagnome" },
        titles = { ["Smell Sensation"] = "Niffen", ["Moderate Mechanization"] = "Mechagnome" },
        keywords = {
            { keyword = "loamm", theme = "Niffen" },
            { keyword = "mechagon", theme = "Mechagnome" },
            { keyword = "gnome'ish", theme = "Mechagnome" },
        },
        aliases = { [150359] = 248525 },
    }
    if options.unknownKind then
        data.TimedNodes[37][21002100] = 999001
        data.TimedVendors[999001] = { name = "Future vendor", zone = "Elwynn Forest", items = {}, kind = "raffle" }
    end
    return data
end

-- Boots one copy of the plugin. opts: holiday/endeavor (settings, default on),
-- addons, faction, viewedMonth, events, initiative, calendarShown, answerRequests, data.
local function boot(opts)
    opts = opts or {}
    local ctx = {
        notify = 0,
        timers = {},
        tickers = {},
        events = {},
        faction = opts.faction or "Alliance",
        inCombat = false,
        calendarShown = opts.calendarShown or false,
        viewed = opts.viewedMonth or { month = TODAY.month, year = TODAY.year },
        dayEvents = opts.events or {},
        calls = { open = 0, setMonth = 0, numDayEvents = 0, request = 0, get = 0 },
        initiative = opts.initiative,
        data = opts.data or makeData(opts),
        tooltipLines = nil,
        tooltipShows = 0,
    }

    local function makeTooltip()
        local tooltip = { lines = {} }
        function tooltip:SetOwner() end
        function tooltip:SetFrameStrata() end
        function tooltip:SetClampedToScreen() end
        function tooltip:SetText(text) self.lines = { text } end
        function tooltip:ClearLines() self.lines = {} end
        function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
        function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " " .. right end
        function tooltip:Show() ctx.tooltipLines = self.lines; ctx.tooltipShows = ctx.tooltipShows + 1 end
        function tooltip:Hide() end
        function tooltip:HookScript() end
        return tooltip
    end

    _G.GameTooltip = makeTooltip()
    _G.UIParent = { GetCenter = function() return 0 end }
    _G.WorldMapFrame = nil
    _G.C_AddOns = { IsAddOnLoaded = function(name) return false, opts.addons and opts.addons[name] end }
    _G.C_Texture = { GetAtlasInfo = function() return { file = 1 } end }
    _G.C_CurrencyInfo = {
        GetCoinTextureString = function(price) return tostring(price) end,
        GetCurrencyInfo = function() return { name = "Tricky Treat" } end,
    }
    _G.C_Item = {
        GetItemInfo = function(id) return "Item " .. id end,
        DoesItemExistByID = function() return true end,
        GetItemIconByID = function() return nil end,
        GetItemNameByID = function() return nil end,
    }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.C_Map = {
        GetMapInfo = function(mapID) return { mapID = mapID, mapType = 3, name = "Map " .. mapID } end,
    }
    _G.Enum = { UIMapType = { World = 1, Continent = 2 } }
    _G.UnitFactionGroup = function() return ctx.faction end
    _G.InCombatLockdown = function() return ctx.inCombat end
    _G.HandyNotes = {
        getXY = function(_, coord) return coord, coord end,
        RegisterPluginDB = function(_, _, handler, options) ctx.handler = handler; ctx.options = options end,
    }
    _G.LibStub = function(name)
        if name == "AceDB-3.0" then
            -- Settings are set explicitly per case rather than through defaults.
            return { New = function()
                return { profile = {
                    icon_scale = 1, icon_alpha = 1,
                    show_holiday_vendors = opts.holiday ~= false,
                    show_endeavor_vendors = opts.endeavor ~= false,
                } }
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
    _G.CreateFrame = function(kind)
        if kind == "GameTooltip" then return makeTooltip() end
        local frame = { scripts = {} }
        function frame:RegisterEvent(event) ctx.events[event] = true end
        function frame:UnregisterEvent(event) ctx.events[event] = nil end
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        ctx.frame = ctx.frame or frame
        return frame
    end
    _G.C_Timer = {
        After = function(seconds, callback) ctx.timers[#ctx.timers + 1] = { seconds = seconds, callback = callback } end,
        NewTicker = function(seconds, callback)
            local ticker = { seconds = seconds, callback = callback }
            ctx.tickers[#ctx.tickers + 1] = ticker
            return ticker
        end,
    }
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return TODAY end }
    _G.C_Calendar = {
        OpenCalendar = function() ctx.calls.open = ctx.calls.open + 1 end,
        SetAbsMonth = function(month, year)
            ctx.calls.setMonth = ctx.calls.setMonth + 1
            ctx.viewed = { month = month, year = year }
        end,
        GetMonthInfo = function() return { month = ctx.viewed.month, year = ctx.viewed.year } end,
        GetNumDayEvents = function(offset, day)
            ctx.calls.numDayEvents = ctx.calls.numDayEvents + 1
            check(offset == 0 and day == TODAY.monthDay, "calendar read for the wrong day")
            if ctx.viewed.month ~= TODAY.month or ctx.viewed.year ~= TODAY.year then return 0 end
            return #ctx.dayEvents
        end,
        GetDayEvent = function(_, _, index) return ctx.dayEvents[index] end,
    }
    _G.CalendarFrame = { IsShown = function() return ctx.calendarShown end }
    _G.issecretvalue = function(value) return value == SECRET end
    _G.C_NeighborhoodInitiative = {
        RequestNeighborhoodInitiativeInfo = function()
            ctx.calls.request = ctx.calls.request + 1
            -- Some answers arrive at once, inside the request.
            if opts.answerRequests and ctx.frame.scripts.OnEvent then
                ctx.frame.scripts.OnEvent(ctx.frame, "NEIGHBORHOOD_INITIATIVE_UPDATED")
            end
        end,
        GetNeighborhoodInitiativeInfo = function()
            ctx.calls.get = ctx.calls.get + 1
            return ctx.initiative
        end,
    }

    assert(loadfile("Locale/enUS.lua"))(nil, ctx.data)
    assert(loadfile("HandyNotes_Homestead.lua"))(nil, ctx.data)
    check(ctx.events.PLAYER_LOGIN, "login event registered at load")
    ctx.frame.scripts.OnEvent(ctx.frame, "PLAYER_LOGIN")
    ctx.loginNotify = ctx.notify

    function ctx.fire(event)
        ctx.frame.scripts.OnEvent(ctx.frame, event)
    end
    function ctx.runTimers()
        local queued = ctx.timers
        ctx.timers = {}
        for _, timer in ipairs(queued) do timer.callback() end
    end
    -- npcIDs whose pin HandyNotes would draw on this zone map.
    function ctx.shown(mapID)
        local iter, nodes, state = ctx.handler:GetNodes2(mapID, false)
        local found = {}
        local coord = state
        while true do
            coord = iter(nodes, coord)
            if not coord then return found end
            found[nodes[coord]] = true
        end
    end
    function ctx.setOption(arg, value)
        ctx.options.set({ arg = arg }, value)
    end
    function ctx.hover(mapID, coord)
        ctx.tooltipLines = nil
        ctx.handler.OnEnter({ GetCenter = function() return 0 end, HookScript = function() end }, mapID, coord)
        return ctx.tooltipLines
    end
    return ctx
end

local function hasLine(lines, text)
    for _, line in ipairs(lines or {}) do
        if line == text then return true end
    end
    return false
end

-- Holiday: an untouched client views 11/2004; the view moves to today once, and an empty
-- read straight after the move is not taken as "no holiday".
do
    local ctx = boot({ viewedMonth = { month = 11, year = 2004 } })
    check(ctx.calls.open == 0 and ctx.calls.setMonth == 0, "login alone must not touch the calendar")
    check(not ctx.shown(37)[273403], "holiday vendor hidden before any calendar read")

    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.calls.setMonth == 1, "an old viewed month must be moved to today once")
    check(ctx.notify == ctx.loginNotify, "an empty read right after the move must not change anything")
    check(not ctx.shown(37)[273403], "holiday vendor stays hidden after an unconfirmed read")

    ctx.dayEvents = { holidayEvent(324) }
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.shown(37)[273403], "Hallow's End vendor shows once the calendar lists it today")
    check(not ctx.shown(80)[15864], "a holiday that isn't running stays hidden")
    check(ctx.notify == ctx.loginNotify + 1, "a newly running holiday redraws once")
    check(ctx.calls.setMonth == 1, "a view already on today is not moved again")

    ctx.fire("PLAYER_ENTERING_WORLD")
    check(ctx.calls.open == 1, "the loading screen opens the calendar")
    ctx.runTimers()
    check(#ctx.tickers == 1 and ctx.tickers[1].seconds == 14400, "one four-hour recheck")
    ctx.fire("PLAYER_ENTERING_WORLD")
    ctx.runTimers()
    check(ctx.calls.open == 1, "the calendar opens once per session, not per loading screen")
    check(#ctx.tickers == 1, "the recheck is started once")

    local beforeTick = ctx.notify
    ctx.tickers[1].callback()
    check(ctx.notify == beforeTick, "a recheck with nothing new does not redraw")

    ctx.dayEvents = { holidayEvent(324, "END") }
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(not ctx.shown(37)[273403], "the holiday's last day reads as ended")

    ctx.dayEvents = { holidayEvent("327") }
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.shown(80)[15864], "an event ID that arrives as a string still matches")
end

-- The calendar window is open (the player may be paging it): never move its view.
do
    local ctx = boot({ viewedMonth = { month = 3, year = 2026 }, calendarShown = true, events = { holidayEvent(324) } })
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    ctx.fire("PLAYER_ENTERING_WORLD")
    ctx.runTimers()
    check(ctx.calls.setMonth == 0, "an open calendar window's view is never moved")
    check(ctx.calls.numDayEvents == 0, "another month's events are never read")
    check(not ctx.shown(37)[273403], "holiday vendor stays hidden while today can't be read")
end

-- A protected event ID in combat keeps the last answer and rereads once combat ends.
do
    local ctx = boot({ events = { holidayEvent(324) } })
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.shown(37)[273403], "holiday vendor shown before combat")
    ctx.dayEvents = { holidayEvent(SECRET) }
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.shown(37)[273403], "a protected event ID keeps the last answer")
    local reads = ctx.calls.numDayEvents
    ctx.dayEvents = {}
    ctx.fire("PLAYER_REGEN_ENABLED")
    check(ctx.calls.numDayEvents == reads + 1, "combat end rereads the calendar")
    check(not ctx.shown(37)[273403], "the reread's answer is applied")
    ctx.fire("PLAYER_REGEN_ENABLED")
    check(ctx.calls.numDayEvents == reads + 1, "the reread happens once")
end

-- A protected type field that throws when read still counts as running.
do
    local guarded = setmetatable({ eventID = 324 }, { __index = function() error("protected value") end })
    local ctx = boot({ events = { guarded } })
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.shown(37)[273403], "an event whose type can't be read counts as running")
end

-- Endeavor: a payload still loading keeps the last answer, a known title shows only its
-- theme at the faction's own position, and the empty payload means no endeavor.
do
    local ctx = boot({ initiative = { isLoaded = false } })
    check(ctx.calls.request == 1 and ctx.calls.get == 1, "login asks for and reads the endeavor once")
    check(not ctx.shown(2352)[257897], "endeavor vendor hidden while the payload is loading")

    ctx.initiative = { isLoaded = true, initiativeID = 99, title = "Smell Sensation", progressRequired = 1000 }
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(ctx.shown(2352)[257897], "the running theme's vendor shows to Alliance in Founder's Point")
    check(not ctx.shown(2351)[257897], "and not at the Horde neighborhood's position")
    check(not ctx.shown(2352)[248525], "another theme's vendor stays hidden")
    ctx.faction = "Horde"
    check(ctx.shown(2351)[257897] and not ctx.shown(2352)[257897], "Horde sees it in Razorwind Shores only")
    ctx.faction = "Alliance"

    ctx.initiative = { isLoaded = false }
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(ctx.shown(2352)[257897], "a payload still loading keeps the last answer")

    ctx.initiative = { isLoaded = true, initiativeID = 0, title = "", progressRequired = 0 }
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(not ctx.shown(2352)[257897] and not ctx.shown(2352)[248525], "no endeavor running hides every endeavor vendor")

    ctx.initiative = { isLoaded = true, initiativeID = 98, title = "Something New", description = "Help out.", progressRequired = 500 }
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(not ctx.shown(2352)[257897] and not ctx.shown(2352)[248525], "an unrecognized endeavor hides every endeavor vendor")
end

-- The empty payload is a known answer ("no endeavor"), not an unknown one: moving to it
-- from the unknown state is a change, and a later unrecognized payload is another.
do
    local ctx = boot({ initiative = { isLoaded = false } })
    ctx.initiative = { isLoaded = true, initiativeID = 0, title = "", progressRequired = 0 }
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(ctx.notify == ctx.loginNotify + 1, "the empty payload reads as no endeavor running")
    ctx.initiative = { isLoaded = true, initiativeID = 0, title = "", progressRequired = 300 }
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(ctx.notify == ctx.loginNotify + 2, "an empty title with progress to make is unknown, not none")
end

-- Each way of recognizing the theme: ID, alias NPC field, keyword, vendor name.
do
    local cases = {
        { info = { initiativeID = 17, title = "Not the English title" }, npcID = 248525, label = "initiative ID" },
        { info = { initiativeID = 98, title = "x", vendorNPCID = 150359 }, npcID = 248525, label = "aliased vendor NPC field" },
        { info = { initiativeID = 98, title = "x", vendor = { npcID = 257897 } }, npcID = 257897, label = "nested vendor NPC field" },
        { info = { initiativeID = 98, title = "x", description = "Bring gifts to Loamm." }, npcID = 257897, label = "keyword" },
        { info = { initiativeID = 98, title = "x", description = "Very Gnome'ish." }, npcID = 248525, label = "keyword with an apostrophe" },
        { info = { initiativeID = 98, title = "Aid for Harlowe Marl" }, npcID = 257897, label = "vendor name" },
        { info = { initiativeID = 98, title = "The Mechagnome Way" }, npcID = 248525, label = "theme name" },
    }
    for _, case in ipairs(cases) do
        case.info.isLoaded = true
        local ctx = boot({ initiative = case.info })
        check(ctx.shown(2352)[case.npcID], "theme recognized by " .. case.label)
    end
end

-- The update event fires for every contribution: identical payloads redraw nothing and
-- skip the theme lookup, and the handler never asks again.
do
    local reads = 0
    local info = setmetatable(
        { isLoaded = true, initiativeID = 98, title = "Help out", description = "Visit Loamm." },
        { __index = function(_, key) if key == "vendorNPCID" then reads = reads + 1 end end })
    local ctx = boot({ initiative = info, answerRequests = true })
    check(ctx.calls.request == 1, "a request answered at once does not ask again")
    check(ctx.shown(2352)[257897], "keyword payload resolves")
    local notify, requests, lookups = ctx.notify, ctx.calls.request, reads
    for _ = 1, 50 do ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED") end
    check(ctx.notify == notify, "50 identical updates redraw nothing")
    check(ctx.calls.request == requests, "the update event never asks for more data")
    check(ctx.calls.get == 1 + 1 + 50, "each update reads the payload once")
    check(reads == lookups, "identical payloads skip the theme lookup")

    ctx.fire("PLAYER_ENTERING_WORLD")
    check(ctx.calls.request == requests + 1, "a loading screen asks once")
    ctx.runTimers()
    check(ctx.calls.request == requests + 3, "and retries at half a second and two seconds")
end

-- Combat holds the redraw until it ends, then draws exactly once.
do
    local ctx = boot({ initiative = { isLoaded = true, initiativeID = 0, title = "", progressRequired = 0 } })
    ctx.inCombat = true
    ctx.initiative = { isLoaded = true, initiativeID = 17, title = "Moderate Mechanization" }
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(ctx.notify == ctx.loginNotify, "no redraw from addon code in combat")
    ctx.dayEvents = { holidayEvent(324) }
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.notify == ctx.loginNotify, "still none in combat")
    ctx.inCombat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check(ctx.notify == ctx.loginNotify + 1, "exactly one redraw when combat ends")
    ctx.fire("PLAYER_REGEN_ENABLED")
    check(ctx.notify == ctx.loginNotify + 1, "nothing left to redraw")
    check(ctx.shown(2352)[248525] and ctx.shown(37)[273403], "the held changes are shown")
end

-- Settings off: hidden, and the holiday setting off never touches the calendar.
do
    local ctx = boot({ holiday = false, endeavor = false, events = { holidayEvent(324) },
        initiative = { isLoaded = true, initiativeID = 17, title = "Moderate Mechanization" } })
    check(ctx.calls.request == 0 and ctx.calls.get == 0, "endeavor setting off: no endeavor reads at login")
    ctx.fire("PLAYER_ENTERING_WORLD")
    ctx.runTimers()
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    check(ctx.calls.open == 0 and ctx.calls.setMonth == 0 and ctx.calls.numDayEvents == 0,
        "holiday setting off never opens, moves or reads the calendar")
    check(ctx.calls.request == 0 and ctx.calls.get == 0, "endeavor setting off never reads the endeavor")
    check(not ctx.shown(37)[273403] and not ctx.shown(2352)[248525], "both kinds hidden while off")
    check(ctx.shown(18)[9001], "ordinary vendors are unaffected")

    -- Turning a setting on starts its tracking.
    ctx.setOption("show_holiday_vendors", true)
    check(ctx.calls.open == 1, "turning holidays on opens the calendar")
    ctx.runTimers()
    check(ctx.shown(37)[273403], "turning holidays on scans and shows the running holiday")
    ctx.setOption("show_endeavor_vendors", true)
    check(ctx.calls.request == 1 and ctx.shown(2352)[248525], "turning endeavors on reads and shows the running endeavor")

    ctx.setOption("show_holiday_vendors", false)
    check(not ctx.shown(37)[273403], "turning holidays off hides them at once")
end

-- Tooltip: one line naming the holiday or endeavor; a hidden vendor shows no tooltip.
do
    local ctx = boot({ events = { holidayEvent(324) },
        initiative = { isLoaded = true, initiativeID = 99, title = "Smell Sensation" } })
    local hidden = ctx.hover(80, 30003000)
    check(hidden == nil and ctx.tooltipShows == 0, "a hidden holiday vendor renders nothing on hover")
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    local lines = ctx.hover(37, 20002000)
    check(lines and lines[1] == "Jack" and hasLine(lines, "Holiday: Hallow's End"), "holiday tooltip names the holiday")
    lines = ctx.hover(2352, 53003820)
    check(lines and hasLine(lines, "Endeavor: Smell Sensation"), "endeavor tooltip uses the live title")

    local byID = boot({ initiative = { isLoaded = true, initiativeID = 17, title = "" } })
    lines = byID.hover(2352, 41004100)
    check(lines and hasLine(lines, "Endeavor: Mechagnome"), "endeavor tooltip falls back to the theme name")
    check(byID.hover(2352, 53003820) == nil, "another theme's vendor renders nothing on hover")
end

-- Old data without the timed tables: no errors, no calendar or endeavor reads.
do
    local ctx = boot({ oldData = true, events = { holidayEvent(324) },
        initiative = { isLoaded = true, initiativeID = 17, title = "" } })
    ctx.fire("PLAYER_ENTERING_WORLD")
    ctx.runTimers()
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    ctx.fire("NEIGHBORHOOD_INITIATIVE_UPDATED")
    ctx.fire("PLAYER_REGEN_ENABLED")
    check(ctx.calls.open == 0 and ctx.calls.numDayEvents == 0 and ctx.calls.request == 0,
        "with no holiday or endeavor vendors nothing is read")
    check(ctx.shown(18)[9001], "ordinary vendors still show with old data")
end

-- A kind this version doesn't know stays hidden, even with every holiday running.
do
    local ctx = boot({ unknownKind = true, events = { holidayEvent(324) } })
    ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
    check(ctx.shown(37)[273403] and not ctx.shown(37)[999001], "unknown kind hidden")
    check(ctx.hover(37, 21002100) == nil, "unknown kind renders nothing on hover")
end

-- Timed rows never replace an ordinary row or node that is already there.
do
    local ctx = boot()
    check(ctx.data.Vendors[273403].kind == "event" and ctx.data.Nodes[80][30003000] == 15864, "timed rows are merged")
    local data = makeData()
    data.Vendors[273403] = { name = "Ordinary Jack", zone = "Elwynn Forest", items = {} }
    data.Nodes[37] = { [20002000] = 9001 }
    data.TimedNodes[18] = { [50005000] = 273403 }
    local clash = boot({ data = data })
    check(clash.data.Vendors[273403].name == "Ordinary Jack", "an existing vendor row is kept")
    check(clash.data.Nodes[37][20002000] == 9001, "an existing node is kept")
    check(clash.data.Nodes[18][50005000] == nil, "a timed node never adds a pin to an ordinary vendor")
end

-- Homestead or its dev build loaded: the plugin steps aside and listens for nothing.
for _, name in ipairs({ "Homestead", "Homestead_DevBuild" }) do
    local ctx = boot({ addons = { [name] = true } })
    check(next(ctx.events) == nil, name .. " loaded: no events registered")
    check(ctx.handler == nil and ctx.calls.request == 0 and ctx.calls.get == 0, name .. " loaded: nothing registered or read")
    check(ctx.data.Vendors[273403] == nil, name .. " loaded: timed rows are not merged")
end

-- Optional: lua5.1 tests/timed_vendors.lua path/to/Data.lua also checks a generated file:
-- every holiday ID, endeavor ID, title, keyword and alias shows exactly the vendors it names.
if arg and arg[1] then
    local function loadData()
        local data = {}
        assert(loadfile(arg[1]))("HandyNotes_Homestead", data)
        return data
    end
    local sample = loadData()
    check(type(sample.TimedVendors) == "table" and type(sample.EndeavorThemes) == "table", "data file has timed tables")

    -- Timed npcIDs shown on any timed map, for either faction.
    local function shownAnywhere(opts)
        local found = {}
        for _, faction in ipairs({ "Alliance", "Horde" }) do
            opts.faction = faction
            opts.data = loadData()
            local ctx = boot(opts)
            ctx.fire("CALENDAR_UPDATE_EVENT_LIST")
            for mapID in next, sample.TimedNodes do
                for npcID in next, ctx.shown(mapID) do
                    if sample.TimedVendors[npcID] then found[npcID] = true end
                end
            end
        end
        return found
    end
    -- The shown set must equal the timed vendors that match.
    local function showsExactly(found, matches, label)
        for npcID, vendor in next, sample.TimedVendors do
            check((not found[npcID]) == (not matches(vendor)), label .. ": wrong visibility for " .. vendor.name)
        end
    end

    local holidays, routes = {}, {}
    for _, vendor in next, sample.TimedVendors do
        if vendor.kind == "event" then
            for _, holidayID in ipairs(vendor.holidayIDs) do holidays[holidayID] = vendor.event end
        end
    end
    local holidayCount = 0
    for holidayID, event in next, holidays do
        local found = shownAnywhere({ events = { holidayEvent(holidayID) },
            initiative = { isLoaded = true, initiativeID = 0, title = "", progressRequired = 0 } })
        showsExactly(found, function(row) return row.kind == "event" and row.event == event end, "holiday " .. holidayID)
        holidayCount = holidayCount + 1
    end
    for id, theme in next, sample.EndeavorThemes.ids do
        routes[#routes + 1] = { info = { initiativeID = id, title = "" }, theme = theme, label = "ID " .. id }
    end
    for title, theme in next, sample.EndeavorThemes.titles do
        routes[#routes + 1] = { info = { initiativeID = 9999, title = title }, theme = theme, label = "title " .. title }
    end
    for _, entry in ipairs(sample.EndeavorThemes.keywords) do
        routes[#routes + 1] = { info = { initiativeID = 9999, title = "Help out", description = "About " .. entry.keyword .. "." },
            theme = entry.theme, label = "keyword " .. entry.keyword }
    end
    for variant, canonical in next, sample.EndeavorThemes.aliases do
        routes[#routes + 1] = { info = { initiativeID = 9999, title = "Help out", vendorNPCID = variant },
            theme = sample.TimedVendors[canonical].theme, label = "alias " .. variant }
    end
    local withoutVendor = 0
    for _, route in ipairs(routes) do
        route.info.isLoaded = true
        route.info.progressRequired = 100
        local found = shownAnywhere({ initiative = route.info })
        showsExactly(found, function(row) return row.kind == "endeavor" and row.theme == route.theme end, route.label)
        if next(found) == nil then withoutVendor = withoutVendor + 1 end
    end
    print(("Checked %s: %d holiday IDs, %d endeavor routes (%d name a theme with no vendor)."):format(
        arg[1], holidayCount, #routes, withoutVendor))
end

print("PASS: holiday and endeavor vendors follow what is running")

-- luacheck: pop
