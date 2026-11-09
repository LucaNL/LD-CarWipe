-- LD CarWipe: the core. Logging and helpers, the schedule, the vehicle filter and the wipe itself.
-- Notifications, database, webhook and update check are in integrations.lua; command and exports in commands.lua.


----------------------------------------------------------------------------------------------------
-- Logging and helpers
----------------------------------------------------------------------------------------------------
LDCW = LDCW or {}

local U = {}
LDCW.util = U

U.resource = GetCurrentResourceName()

--- Wall clock in seconds.
function U.time() return os.time() end

----------------------------------------------------------------------------------------------------
-- Logging (same console style as the other LD Scripts resources)
----------------------------------------------------------------------------------------------------
local PREFIX = '^5LD CarWipe^7'
local TAG = {
    debug = '^8DEBUG^7',
    info = '^7 INFO^7',
    ok = '^2  OK ^7',
    warn = '^3 WARN^7',
    error = '^1 ERR ^7',
    hint = '^6 HINT^7',
}

local function emit(tag, msg) print(('%s %s %s^0'):format(PREFIX, TAG[tag], msg)) end

function U.debug(fmt, ...) if Config.Debug then emit('debug', fmt:format(...)) end end
function U.info(fmt, ...) if Config.ConsoleLogging ~= false then emit('info', fmt:format(...)) end end
function U.ok(fmt, ...) emit('ok', fmt:format(...)) end
function U.hint(fmt, ...) emit('hint', fmt:format(...)) end
function U.warn(fmt, ...) emit('warn', fmt:format(...)) end
function U.error(fmt, ...) emit('error', fmt:format(...)) end
function U.divider() print('^8────────────────────────────────────────────────────────^0') end

----------------------------------------------------------------------------------------------------
-- Locale
----------------------------------------------------------------------------------------------------
--- Translate a key with optional string.format arguments. Falls back to English, then the key.
function U.t(key, ...)
    local lang = Locales[Config.Locale] or Locales.en
    local str = lang[key] or Locales.en[key] or key
    if select('#', ...) > 0 then
        local ok, res = pcall(string.format, str, ...)
        if ok then return res end
    end
    return str
end

--- "5 minutes", "1 minute", "30 seconds" in the configured language.
function U.countdown(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 60 and seconds % 60 == 0 then
        local m = seconds // 60
        return U.t(m == 1 and 'one_minute' or 'minutes', m)
    end
    if seconds >= 120 then return U.t('minutes', seconds // 60) end
    return U.t(seconds == 1 and 'one_second' or 'seconds', seconds)
end

----------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------
function U.trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

function U.normalizePlate(plate) return U.trim(plate):upper() end

function U.isStarted(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

function U.safeDecode(s)
    local ok, res = pcall(json.decode, s)
    if ok then return res end
end

function U.truncate(s, n)
    s = tostring(s or '')
    if #s <= n then return s end
    return s:sub(1, n - 3) .. '...'
end

--- Distance between two vectors (works for vector3 and plain {x,y,z} tables).
function U.dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

----------------------------------------------------------------------------------------------------
-- Schedule: when is the next automatic wipe? (pure functions, no natives)
----------------------------------------------------------------------------------------------------
-- When is the next automatic wipe? Pure functions, no natives.

local S = {}
LDCW.schedule = S

--- Parse 'HH:MM' into hour, minute. Returns nil for anything else.
function S.parseTime(s)
    local h, m = tostring(s or ''):match('^%s*(%d%d?):(%d%d)%s*$')
    h, m = tonumber(h), tonumber(m)
    if not h or h > 23 or m > 59 then return nil end
    return h, m
end

--- Next unix time (>= now + 1) at which the clock shows h:m in server time.
local function nextClock(now, h, m)
    local t = os.date('*t', now)
    t.hour, t.min, t.sec = h, m, 0
    t.isdst = nil -- let os.time work out daylight saving for the target day, not for today
    local at = os.time(t)
    if at <= now then
        t = os.date('*t', now)
        t.day, t.hour, t.min, t.sec, t.isdst = t.day + 1, h, m, 0, nil
        at = os.time(t)
    end
    return at
end

--- Valid fixed times from the config, as { {h, m}, ... }. Invalid entries are reported once in `bad`.
function S.times(list)
    local out, bad = {}, {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        local h, m = S.parseTime(v)
        if h then out[#out + 1] = { h, m } else bad[#bad + 1] = tostring(v) end
    end
    return out, bad
end

--- Next automatic wipe after `now`.
--- `since` is when the interval started counting (resource start or the last wipe).
--- Returns a unix time, or nil when automatic wipes are off.
function S.next(now, since, interval, times)
    local best
    interval = tonumber(interval) or 0
    if interval > 0 then
        local at = (since or now) + math.floor(interval * 60)
        if at <= now then at = now + 1 end
        best = at
    end
    for _, hm in ipairs(times or {}) do
        local at = nextClock(now, hm[1], hm[2])
        if not best or at < best then best = at end
    end
    return best
end

--- The warnings that still have to be shown for a countdown of `total` seconds, sorted high to low.
--- The first warning is always the moment the countdown starts.
function S.warnings(list, total)
    local out, seen = {}, {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        v = math.floor(tonumber(v) or -1)
        if v > 0 and v < total and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    table.sort(out, function(a, b) return a > b end)
    if total > 0 then table.insert(out, 1, total) end
    return out
end

--- Longest warning in the config (the countdown for automatic wipes).
function S.lead(list)
    local max = 0
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        v = tonumber(v) or 0
        if v > max then max = math.floor(v) end
    end
    return max
end

----------------------------------------------------------------------------------------------------
-- Filter: remove or keep, per vehicle
----------------------------------------------------------------------------------------------------
-- Decides per vehicle: remove or keep (and why). Runs only on the server.

local F = {}
LDCW.filter = F

F.TRAILER_RANGE = 20.0 -- a trailer this close to an occupied vehicle is treated as hitched to it
F.PROTECT_STATE = 'ldCarwipeProtected'

-- Reasons a vehicle is kept (used for the preview and the console summary).
F.REASONS = { 'occupied', 'attached', 'protected', 'type', 'model', 'zone', 'nearby', 'npc', 'locked', 'owned', 'healthy' }

local function modelSet(list)
    local set = {}
    for _, name in ipairs(type(list) == 'table' and list or {}) do
        if type(name) == 'number' then set[name] = true else set[joaat(tostring(name))] = true end
    end
    return set
end

local function stringSet(list)
    local set = {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do set[tostring(v):lower()] = true end
    return set
end

--- Everything about the players that the per-vehicle check needs, read once per wipe.
function F.context()
    local cfg = Config.Filter or {}
    local ctx = {
        occupied = {},          -- vehicle handle -> true
        playerCoords = {},      -- list of vector3
        occupiedCoords = {},    -- coords of occupied vehicles (for trailers)
        models = modelSet(cfg.ProtectedModels),
        types = stringSet(cfg.ProtectedTypes),
        zones = {},
        owned = {},
        ownedChecked = false,
    }
    for _, z in ipairs(type(cfg.ProtectedZones) == 'table' and cfg.ProtectedZones or {}) do
        if z.coords and tonumber(z.radius) then ctx.zones[#ctx.zones + 1] = z end
    end
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped and ped ~= 0 then
            ctx.playerCoords[#ctx.playerCoords + 1] = GetEntityCoords(ped)
            local veh = GetVehiclePedIsIn(ped, false)
            if veh and veh ~= 0 and not ctx.occupied[veh] then
                ctx.occupied[veh] = true
                ctx.occupiedCoords[#ctx.occupiedCoords + 1] = GetEntityCoords(veh)
            end
        end
    end
    return ctx
end

--- Is anything a player sits in attached to this vehicle's chain? (car on a flatbed, towed vehicle)
local function attachedToOccupied(veh, ctx)
    local cur, guard = veh, 0
    while guard < 8 do
        local parent = GetEntityAttachedTo(cur)
        if not parent or parent == 0 then return false end
        if ctx.occupied[parent] then return true end
        cur, guard = parent, guard + 1
    end
    return false
end

local function nearAny(coords, list, range)
    for _, c in ipairs(list) do
        if U.dist(coords, c) <= range then return true end
    end
    return false
end

--- Health is only known for vehicles a player's game is syncing. A vehicle nobody owns reports 0 health
--- on the server (measured on a real server), so it would look destroyed while it is fine. Those count as healthy.
local function damaged(veh, threshold)
    if (NetworkGetEntityOwner(veh) or -1) <= 0 then return false end
    return GetVehicleEngineHealth(veh) < threshold or GetVehicleBodyHealth(veh) < threshold
end

--- Returns nil when the vehicle may be removed, otherwise the reason it is kept.
--- Order matters: the hard safety rules (players inside) come first.
function F.keepReason(veh, ctx)
    local cfg = Config.Filter or {}

    if ctx.occupied[veh] then return 'occupied' end
    for seat = -1, 15 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped and ped ~= 0 and IsPedAPlayer(ped) then return 'occupied' end
    end
    if attachedToOccupied(veh, ctx) then return 'attached' end

    local vtype = tostring(GetVehicleType(veh) or ''):lower()
    local coords = GetEntityCoords(veh)
    if vtype == 'trailer' and nearAny(coords, ctx.occupiedCoords, F.TRAILER_RANGE) then return 'attached' end

    if Entity(veh).state[F.PROTECT_STATE] then return 'protected' end
    if ctx.types[vtype] then return 'type' end
    if ctx.models[GetEntityModel(veh)] then return 'model' end

    for _, z in ipairs(ctx.zones) do
        if U.dist(coords, z.coords) <= tonumber(z.radius) then return 'zone' end
    end

    local radius = tonumber(cfg.PlayerRadius) or 0
    if radius > 0 and nearAny(coords, ctx.playerCoords, radius) then return 'nearby' end

    if cfg.SkipNpcDriven ~= false then
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver and driver ~= 0 and not IsPedAPlayer(driver) then return 'npc' end
    end

    if cfg.SkipLocked and (GetVehicleDoorLockStatus(veh) or 0) >= 2 then return 'locked' end

    if cfg.SkipOwned and ctx.owned[U.normalizePlate(GetVehicleNumberPlateText(veh))] then return 'owned' end

    if cfg.OnlyDamaged and not damaged(veh, tonumber(cfg.DamagedBelow) or 500) then return 'healthy' end

    return nil
end

--- Sort all vehicles into `remove` and kept counts per reason.
function F.scan()
    local ctx = F.context()
    local vehicles = GetAllVehicles()
    local cfg = Config.Filter or {}

    if cfg.SkipOwned then
        local plates = {}
        for _, veh in ipairs(vehicles) do
            if DoesEntityExist(veh) and not ctx.occupied[veh] then
                plates[#plates + 1] = GetVehicleNumberPlateText(veh)
            end
        end
        local owned, ok, reason = LDCW.owned.lookup(plates)
        ctx.owned, ctx.ownedChecked = owned, ok
        if not ok then U.warn('SkipOwned is on, but %s. Owned vehicles are NOT protected this time.', tostring(reason)) end
    end

    local result = { remove = {}, kept = {}, keptTotal = 0, total = 0 }
    for _, r in ipairs(F.REASONS) do result.kept[r] = 0 end
    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            result.total = result.total + 1
            local reason = F.keepReason(veh, ctx)
            if reason then
                result.kept[reason] = (result.kept[reason] or 0) + 1
                result.keptTotal = result.keptTotal + 1
            else
                result.remove[#result.remove + 1] = veh
            end
        end
    end
    return result
end

----------------------------------------------------------------------------------------------------
-- Countdown, warnings and the wipe
----------------------------------------------------------------------------------------------------
-- Countdown, warnings and the wipe itself. W.tick(now) is called once per second from main.lua.

local W = {}
LDCW.wipe = W

W.pending = nil     -- { at, reason, by, warnings = {...}, nextWarn }
W.running = false
W.last = nil        -- { at, removed, kept, total, ms, reason, by }
W.since = nil       -- the interval counts from here (resource start or the last wipe)
W.nextAuto = nil    -- unix time of the next automatic wipe
W.restartAt = nil   -- unix time of the next txAdmin scheduled restart, when announced

local times = {}

function W.init(now)
    local bad
    times, bad = S.times(Config.Schedule and Config.Schedule.Times)
    for _, v in ipairs(bad) do U.warn('Config.Schedule.Times: "%s" is not a valid time, use HH:MM (e.g. 06:00).', v) end
    W.since = now
    W.plan(now)
end

--- Work out the next automatic wipe.
function W.plan(now)
    local cfg = Config.Schedule or {}
    W.nextAuto = S.next(now, W.since, cfg.Interval, times)
end

local function notifyWarning(seconds)
    LDCW.notify.all(U.t('warning', U.countdown(seconds)), 'warning')
    TriggerEvent('ld_carwipe:countdown', seconds)
end

--- Start a countdown. delay 0 = wipe right away. A running countdown is replaced.
--- Returns true, or false plus a reason ('running').
function W.start(delay, reason, by, now)
    now = now or U.time()
    if W.running then return false, 'running' end
    delay = math.max(0, math.floor(tonumber(delay) or 0))
    -- remember the automatic slot this countdown replaces, so a cancel moves the plan past it
    local autoAt = reason == 'auto' and (now + delay) or (W.pending and W.pending.autoAt)
    if W.pending then U.info('Countdown replaced by a new one (%s).', by or reason or 'unknown') end
    W.pending = {
        at = now + delay,
        reason = reason or 'manual',
        by = by,
        autoAt = autoAt,
        warnings = S.warnings(Config.Warnings, delay),
        nextWarn = 1,
    }
    if delay > 0 then
        U.info('Wipe in %s (%s%s).', U.countdown(delay), W.pending.reason, by and (', by ' .. by) or '')
    end
    W.tick(now)
    return true
end

--- Cancel the countdown. Returns true when there was one.
function W.cancel(by, now)
    now = now or U.time()
    if not W.pending then return false end
    local p = W.pending
    W.pending = nil
    if p.autoAt then
        -- plan past the cancelled automatic slot, otherwise it (or a fixed time like 06:00) would start right again
        W.since = now
        W.plan(math.max(now, p.autoAt))
    end
    U.info('Countdown cancelled%s.', by and (' by ' .. by) or '')
    LDCW.notify.all(U.t('cancelled'), 'cancelled')
    TriggerEvent('ld_carwipe:cancelled', by)
    return true
end

--- Why the automatic wipe at `at` should be skipped, or nil.
function W.skipReason(now, at)
    local cfg = Config.Schedule or {}
    local min = tonumber(cfg.MinPlayers) or 0
    if min > 0 and #GetPlayers() < min then return ('fewer than %d players online'):format(min) end
    local before = (tonumber(cfg.SkipBeforeRestart) or 0) * 60
    if before > 0 and W.restartAt and W.restartAt > now and W.restartAt - at <= before then
        return 'a scheduled restart is coming up'
    end
    return nil
end

--- Is a player sitting in this vehicle right now? (checked again just before removing it)
local function hasPlayer(veh)
    for seat = -1, 15 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped and ped ~= 0 and IsPedAPlayer(ped) then return true end
    end
    return false
end

--- The wipe itself, with W.running already claimed. Blocks (uses Wait).
local function execute(reason, by)
    local started = GetGameTimer()

    local ok, err = pcall(function()
        TriggerEvent('ld_carwipe:beforeWipe', { reason = reason, by = by })
        local delay = tonumber(Config.Delete and Config.Delete.BeforeWipeDelay) or 0
        if delay > 0 then Wait(delay) end

        local scan = LDCW.filter.scan()
        local perBatch = math.max(1, math.floor(tonumber(Config.Delete and Config.Delete.PerBatch) or 10))
        local batchDelay = math.max(0, math.floor(tonumber(Config.Delete and Config.Delete.BatchDelay) or 50))
        local removed, skippedLate = 0, 0

        for i, veh in ipairs(scan.remove) do
            if DoesEntityExist(veh) then
                if hasPlayer(veh) or Entity(veh).state[LDCW.filter.PROTECT_STATE] then
                    skippedLate = skippedLate + 1
                else
                    DeleteEntity(veh)
                    removed = removed + 1
                end
            end
            if i % perBatch == 0 and batchDelay > 0 then Wait(batchDelay) end
        end

        local now = U.time()
        W.last = {
            at = now,
            removed = removed,
            kept = scan.keptTotal + skippedLate,
            keptBy = scan.kept,
            total = scan.total,
            ms = GetGameTimer() - started,
            reason = reason,
            by = by,
        }
        U.info('Wipe done: %d of %d vehicles removed, %d kept (%d ms).', removed, scan.total, W.last.kept, W.last.ms)
        LDCW.notify.all(U.t('done', removed), 'done')
        LDCW.webhook.wipe(W.last)
        TriggerEvent('ld_carwipe:afterWipe', W.last)
    end)

    W.running = false
    if not ok then U.error('Wipe failed: %s', tostring(err)) end

    local now = U.time()
    W.since = now
    W.plan(now)
end

--- Run a wipe now. Blocks (uses Wait), so call it from a thread.
function W.run(reason, by)
    if W.running then return end
    W.running = true
    execute(reason, by)
end

--- Called once per second.
function W.tick(now)
    if W.running then return end
    local p = W.pending

    if p then
        local left = p.at - now
        -- show only the most recent warning that has been reached (no spam after a hitch)
        local due
        while p.warnings[p.nextWarn] and left <= p.warnings[p.nextWarn] do
            due = p.warnings[p.nextWarn]
            p.nextWarn = p.nextWarn + 1
        end
        if due and left > 0 then notifyWarning(left < due and left or due) end

        if left <= 0 then
            W.pending = nil
            W.running = true -- claimed now, so nothing can start a second wipe before the thread runs
            CreateThread(function() execute(p.reason, p.by) end)
        end
        return
    end

    if not W.nextAuto then return end
    local lead = S.lead(Config.Warnings)
    if now < W.nextAuto - lead then return end

    local skip = W.skipReason(now, W.nextAuto)
    if skip then
        U.info('Automatic wipe skipped: %s.', skip)
        W.since = math.max(now, W.nextAuto)
        W.plan(W.since)
        return
    end
    W.start(math.max(0, W.nextAuto - now), 'auto', nil, now)
end

--- Summary for `carwipe status` and the export.
function W.status(now)
    now = now or U.time()
    return {
        running = W.running,
        countdown = W.pending and math.max(0, W.pending.at - now) or nil,
        nextAuto = W.nextAuto,
        last = W.last,
    }
end

----------------------------------------------------------------------------------------------------
-- Startup
----------------------------------------------------------------------------------------------------
LDCW.version = GetResourceMetadata(U.resource, 'version', 0) or '0.0.0'

-- txAdmin tells us when a scheduled restart is coming, so an automatic wipe right before it can be skipped.
AddEventHandler('txAdmin:events:scheduledRestart', function(data)
    local left = tonumber(type(data) == 'table' and data.secondsRemaining)
    if left then W.restartAt = U.time() + left end
end)
AddEventHandler('txAdmin:events:skippedNextScheduledRestart', function() W.restartAt = nil end)

local function report(now)
    local cfg = Config.Schedule or {}
    local when = W.nextAuto and ('next wipe %s'):format(os.date('%H:%M', W.nextAuto)) or 'automatic wipes off'
    local parts = {}
    if (tonumber(cfg.Interval) or 0) > 0 then parts[#parts + 1] = ('every %s min'):format(tostring(cfg.Interval)) end
    if #times > 0 then
        local list = {}
        for _, hm in ipairs(times) do list[#list + 1] = ('%02d:%02d'):format(hm[1], hm[2]) end
        parts[#parts + 1] = 'at ' .. table.concat(list, ', ')
    end
    local plan = table.concat(parts, ' + ')
    U.ok('v%s started: %s%s · notify %s', LDCW.version, when, plan ~= '' and (' (' .. plan .. ')') or '',
        LDCW.notify.method())

    if not Locales[Config.Locale] then U.warn('Locale "%s" not found, using English.', tostring(Config.Locale)) end
    if (Config.Filter or {}).SkipOwned then
        local ok, reason = LDCW.owned.available()
        if ok then
            U.info('Owned vehicles are kept (%s table).', LDCW.owned.framework() == 'esx' and 'owned_vehicles' or 'player_vehicles')
        else
            U.warn('SkipOwned is on, but %s. Owned vehicles will NOT be protected.', reason)
        end
    end
    U.hint('Type `%s preview` to see what a wipe would remove. Docs: https://github.com/LucaNL/LD-CarWipe', Config.Command)
end

CreateThread(function()
    -- runs after every file of the resource has loaded
    local now = U.time()
    local ok, err = pcall(W.init, now)
    if not ok then U.error('Could not read Config.Schedule: %s', tostring(err)) end
    ok, err = pcall(report, now)
    if not ok then U.warn('Startup report failed: %s', tostring(err)) end
    LDCW.versioncheck.init()
    while true do
        Wait(1000)
        local ok, err = pcall(W.tick, U.time())
        if not ok then U.error('Tick failed: %s', tostring(err)) end
    end
end)
