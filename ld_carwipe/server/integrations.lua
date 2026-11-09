-- LD CarWipe: everything that talks to other resources or the internet.
-- Notifications (ox_lib, ESX, QBCore/Qbox, chat), owned vehicles (oxmysql), Discord webhook, update check.

local U = LDCW.util


----------------------------------------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------------------------------------
-- Notifications to every player. Everything is sent from the server, so no client script is needed.

local N = {}
LDCW.notify = N

local OX_TYPE = { warning = 'warning', done = 'success', cancelled = 'inform' }
local ESX_TYPE = { warning = 'info', done = 'success', cancelled = 'info' }
local QB_TYPE = { warning = 'primary', done = 'success', cancelled = 'primary' }

local senders = {}

function senders.ox_lib(title, message, kind)
    TriggerClientEvent('ox_lib:notify', -1, {
        title = title,
        description = message,
        type = OX_TYPE[kind] or 'inform',
        duration = Config.Notify.Duration or 8000,
        position = Config.Notify.Position or 'top',
    })
end

function senders.esx(_, message, kind)
    TriggerClientEvent('esx:showNotification', -1, message, ESX_TYPE[kind] or 'info', Config.Notify.Duration or 8000)
end

function senders.qb(_, message, kind)
    TriggerClientEvent('QBCore:Notify', -1, message, QB_TYPE[kind] or 'primary', Config.Notify.Duration or 8000)
end

function senders.chat(title, message)
    TriggerClientEvent('chat:addMessage', -1, { color = { 255, 170, 0 }, multiline = true, args = { title, message } })
end

function senders.custom(_, message, kind)
    if type(Config.CustomNotify) == 'function' then
        local ok, err = pcall(Config.CustomNotify, message, kind)
        if not ok then U.warn('Config.CustomNotify failed: %s', tostring(err)) end
    end
end

function senders.none() end

--- Which sender 'auto' resolves to on this server.
function N.detect()
    if U.isStarted('ox_lib') then return 'ox_lib' end
    if U.isStarted('es_extended') then return 'esx' end
    if U.isStarted('qb-core') or U.isStarted('qbx_core') then return 'qb' end
    return 'chat'
end

function N.method()
    local t = (Config.Notify and Config.Notify.Type) or 'auto'
    if t == 'auto' then return N.detect() end
    if not senders[t] then return 'chat' end
    return t
end

--- Send a message to everyone. kind = 'warning' | 'done' | 'cancelled'
function N.all(message, kind)
    local method = N.method()
    U.debug('notify (%s): %s', method, message)
    senders[method](U.t('title'), message, kind)
end

----------------------------------------------------------------------------------------------------
-- Player-owned vehicles (Config.Filter.SkipOwned)
----------------------------------------------------------------------------------------------------
-- Player-owned vehicles (Config.Filter.SkipOwned): look up the plates in the framework's vehicle table.

local O = {}
LDCW.owned = O

local TABLES = {
    esx = 'owned_vehicles',
    qb = 'player_vehicles',
}

function O.framework()
    if U.isStarted('es_extended') then return 'esx' end
    if U.isStarted('qbx_core') or U.isStarted('qb-core') then return 'qb' end
end

--- Can SkipOwned work here? Returns true, or false plus the reason.
function O.available()
    if not U.isStarted('oxmysql') then return false, 'oxmysql is not running' end
    if not O.framework() then return false, 'no ESX, QBCore or Qbox found' end
    return true
end

O.QUERY_TIMEOUT = 5000

--- oxmysql never calls the callback when a query fails (wrong table, lost connection), so wait at most
--- QUERY_TIMEOUT ms. Otherwise one bad query would hang the wipe for good.
local function query(sql, params)
    local p = promise.new()
    exports.oxmysql:query(sql, params, function(rows) p:resolve(rows or {}) end)
    SetTimeout(O.QUERY_TIMEOUT, function() p:resolve(false) end)
    local rows = Citizen.Await(p)
    if rows == false then error('the query failed or took longer than 5 seconds (see the oxmysql error above)', 0) end
    return rows
end

--- Given a list of plates (as read from the vehicles), return a set of the normalized plates that are owned.
--- Errors are caught: on failure nothing counts as owned and `false` is returned as second value.
function O.lookup(plates)
    local owned = {}
    local ok, reason = O.available()
    if not ok then return owned, false, reason end
    local tbl = TABLES[O.framework()]

    -- Plates on vehicles are padded to 8 characters; databases store them padded or trimmed.
    local variants, seen = {}, {}
    for _, plate in ipairs(plates) do
        for _, v in ipairs({ tostring(plate), U.trim(plate) }) do
            if v ~= '' and not seen[v] then
                seen[v] = true
                variants[#variants + 1] = v
            end
        end
    end

    local success, err = pcall(function()
        for i = 1, #variants, 500 do
            local chunk = { table.unpack(variants, i, math.min(i + 499, #variants)) }
            local rows = query(('SELECT plate FROM `%s` WHERE plate IN (?)'):format(tbl), { chunk })
            for _, row in ipairs(rows) do owned[U.normalizePlate(row.plate)] = true end
        end
    end)
    if not success then
        U.warn('Could not read owned vehicles from `%s`: %s', tbl, tostring(err))
        return {}, false, 'database error'
    end
    return owned, true
end

----------------------------------------------------------------------------------------------------
-- Discord webhook
----------------------------------------------------------------------------------------------------
-- Optional Discord log of every wipe.

local H = {}
LDCW.webhook = H

function H.url()
    local fromCfg = GetConvar('ldcw_webhook', '')
    if fromCfg ~= '' then return fromCfg end
    return (Config.Webhook and Config.Webhook.Url) or ''
end

local REASON_LABEL = { auto = 'Automatic', manual = 'Command', export = 'Other script' }

function H.wipe(last)
    local url = H.url()
    if url == '' then return end

    local kept = {}
    for reason, n in pairs(last.keptBy or {}) do
        if n > 0 then kept[#kept + 1] = ('%s: %d'):format(reason, n) end
    end
    table.sort(kept)

    local embed = {
        title = 'Car wipe',
        color = (Config.Webhook and Config.Webhook.Color) or 3447003,
        fields = {
            { name = 'Removed', value = tostring(last.removed), inline = true },
            { name = 'Kept', value = tostring(last.kept), inline = true },
            { name = 'Took', value = ('%d ms'):format(last.ms or 0), inline = true },
            { name = 'Started by', value = last.by or REASON_LABEL[last.reason] or tostring(last.reason), inline = true },
        },
        footer = { text = 'LD CarWipe' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', last.at),
    }
    if #kept > 0 then
        embed.fields[#embed.fields + 1] = { name = 'Kept because', value = table.concat(kept, '\n'), inline = false }
    end

    PerformHttpRequest(url, function(status)
        if status < 200 or status >= 300 then U.warn('Discord webhook failed (HTTP %s).', tostring(status)) end
    end, 'POST', json.encode({
        username = (Config.Webhook and Config.Webhook.Name) or 'LD CarWipe',
        embeds = { embed },
    }), { ['Content-Type'] = 'application/json' })
end

----------------------------------------------------------------------------------------------------
-- Update check
----------------------------------------------------------------------------------------------------
-- Update check: reads the latest release from GitHub once a day. Nothing about your server is sent.
-- Turn it off with Config.VersionCheck = false.

local V = {}
LDCW.versioncheck = V

V.URL = 'https://api.github.com/repos/LucaNL/LD-CarWipe/releases/latest'
V.DOWNLOAD = 'https://github.com/LucaNL/LD-CarWipe/releases/latest'
V.CHECK_EVERY_MS = 24 * 3600 * 1000
V.status = 'pending'        -- 'pending' | 'latest' | 'outdated' | 'failed' | 'off'
V.latest = nil

local function parse(v)
    local a, b, c = tostring(v or ''):match('^v?(%d+)%.(%d+)%.?(%d*)')
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) or 0 }
end

--- -1 when a < b, 0 when equal, 1 when a > b (nil when either can't be read).
function V.compare(a, b)
    local x, y = parse(a), parse(b)
    if not x or not y then return nil end
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
    end
    return 0
end

function V.check()
    local p = promise.new()
    PerformHttpRequest(V.URL, function(status, body) p:resolve({ status = status, body = body }) end, 'GET', '',
        { ['Accept'] = 'application/vnd.github+json', ['User-Agent'] = 'ld_carwipe' })
    local res = Citizen.Await(p)
    if res.status ~= 200 or type(res.body) ~= 'string' then
        V.status = 'failed'
        U.debug('Update check failed (HTTP %s).', tostring(res.status))
        return
    end
    local data = U.safeDecode(res.body)
    local latest = type(data) == 'table' and data.tag_name
    local current = tostring(LDCW.version)
    local cmp = latest and V.compare(current, latest)
    if not cmp then
        V.status = 'failed'
        return
    end
    latest = (tostring(latest):gsub('^v', ''))
    if cmp < 0 then
        local first = V.latest ~= latest
        V.status, V.latest = 'outdated', latest
        if first then
            U.divider()
            U.warn('Update available: v%s → v%s', current, V.latest)
            U.hint('Download: %s (keep your config.lua).', V.DOWNLOAD)
            U.divider()
        end
    else
        V.status, V.latest = 'latest', latest
        U.debug('On the latest version (v%s).', current)
    end
end

function V.init()
    if Config.VersionCheck == false then
        V.status = 'off'
        return
    end
    CreateThread(function()
        Wait(5000)
        while Config.VersionCheck ~= false do
            local ok, err = pcall(V.check)
            if not ok then
                V.status = 'failed'
                U.debug('Update check failed: %s', tostring(err))
            end
            Wait(V.CHECK_EVERY_MS)
        end
    end)
end
