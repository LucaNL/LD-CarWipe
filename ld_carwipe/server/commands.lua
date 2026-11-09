-- LD CarWipe: the `carwipe` command and the exports for other resources.

local U = LDCW.util
local W = LDCW.wipe

----------------------------------------------------------------------------------------------------
-- Command
----------------------------------------------------------------------------------------------------
local function reply(src, msg)
    if src == 0 then
        print(('^5LD CarWipe^7 %s^0'):format(msg))
    else
        TriggerClientEvent('chat:addMessage', src, { color = { 0, 170, 255 }, multiline = true, args = { 'CarWipe', msg } })
    end
end

local function who(src)
    if src == 0 then return 'console' end
    return ('%s (%d)'):format(GetPlayerName(src) or 'unknown', src)
end

local function clock(t) return os.date('%H:%M', t) end

local function keptSummary(kept)
    local parts = {}
    for _, reason in ipairs(LDCW.filter.REASONS) do
        local n = kept[reason] or 0
        if n > 0 then parts[#parts + 1] = ('%s %d'):format(reason, n) end
    end
    return #parts > 0 and table.concat(parts, ', ') or 'none'
end

local function status(src)
    local now = U.time()
    local s = W.status(now)
    if s.running then
        reply(src, 'A wipe is running right now.')
    elseif s.countdown then
        reply(src, ('Countdown running: wipe in %s.'):format(U.countdown(s.countdown)))
    end
    if s.nextAuto then
        reply(src, ('Next automatic wipe: %s (in %s).'):format(clock(s.nextAuto), U.countdown(math.max(0, s.nextAuto - now))))
    else
        reply(src, 'Automatic wipes are off (Config.Schedule).')
    end
    if s.last then
        reply(src, ('Last wipe: %s, %d removed, %d kept (%s).'):format(clock(s.last.at), s.last.removed, s.last.kept,
            s.last.by or s.last.reason))
    end
end

local function preview(src)
    CreateThread(function()
        local scan = LDCW.filter.scan()
        reply(src, ('Preview: %d of %d vehicles would be removed. Kept: %s.'):format(#scan.remove, scan.total,
            keptSummary(scan.kept)))
    end)
end

local function help(src)
    local c = Config.Command
    reply(src, ('%s [seconds] · %s now · %s cancel · %s preview · %s status'):format(c, c, c, c, c))
end

RegisterCommand(Config.Command or 'carwipe', function(src, args)
    local arg = tostring(args[1] or ''):lower()

    if arg == 'cancel' or arg == 'stop' then
        if not W.cancel(who(src)) then reply(src, 'There is no countdown to cancel.') end
        return
    end
    if arg == 'preview' or arg == 'test' then return preview(src) end
    if arg == 'status' then return status(src) end
    if arg == 'help' then return help(src) end

    local delay
    if arg == '' then delay = Config.ManualCountdown or 60
    elseif arg == 'now' then delay = 0
    else delay = tonumber(arg) end
    if not delay or delay < 0 then return help(src) end

    local ok, reason = W.start(delay, 'manual', who(src))
    if not ok then
        reply(src, reason == 'running' and 'A wipe is running right now, try again in a moment.' or 'Could not start the wipe.')
    elseif delay > 0 then
        reply(src, ('Wipe in %s. Cancel with: %s cancel'):format(U.countdown(delay), Config.Command))
    end
end, true)

----------------------------------------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------------------------------------
--- exports.ld_carwipe:startWipe(seconds) -> true | false, reason
exports('startWipe', function(seconds)
    return W.start(tonumber(seconds) or Config.ManualCountdown or 60, 'export', GetInvokingResource())
end)

--- exports.ld_carwipe:cancelWipe() -> true when a countdown was cancelled
exports('cancelWipe', function()
    return W.cancel(GetInvokingResource())
end)

--- exports.ld_carwipe:getStatus() -> { running, countdown, nextAuto, last }
exports('getStatus', function()
    return W.status()
end)

--- exports.ld_carwipe:protectVehicle(vehicle, protected) - keep (or stop keeping) one vehicle.
--- Takes an entity handle or a network id. Same as the `ldCarwipeProtected` state bag.
exports('protectVehicle', function(vehicle, protected)
    local ent = tonumber(vehicle) or 0
    if not DoesEntityExist(ent) then ent = NetworkGetEntityFromNetworkId(ent) end
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    Entity(ent).state:set(LDCW.filter.PROTECT_STATE, protected ~= false or nil, true)
    return true
end)

--- exports.ld_carwipe:previewWipe() -> { remove = count, total, kept = { reason = count } }
--- Blocks while it scans; call it from a thread.
exports('previewWipe', function()
    local scan = LDCW.filter.scan()
    return { remove = #scan.remove, total = scan.total, kept = scan.kept }
end)
