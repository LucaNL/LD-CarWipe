--[[
    LD CarWipe - configuration

    Works out of the box: every hour, empty vehicles are removed after a countdown.
    Everything runs on the server. Nothing is added to your players' game.

    Durations are in seconds unless the name says otherwise.
    Prefer to keep your webhook out of this file? Put it in server.cfg instead:
        set ldcw_webhook "https://discord.com/api/webhooks/..."
]]

Config = {}

----------------------------------------------------------------------------------------------------
-- General
----------------------------------------------------------------------------------------------------
Config.Locale = 'en'            -- en, nl, de, fr, es, pt, pl, tr (files in locales/)
Config.ConsoleLogging = true    -- print a line to the console for every wipe
Config.Debug = false            -- very verbose logging, only for troubleshooting
Config.VersionCheck = true      -- tell you in the console when a new version is available

----------------------------------------------------------------------------------------------------
-- When
----------------------------------------------------------------------------------------------------
Config.Schedule = {
    Interval = 60,              -- minutes between automatic wipes (0 = no interval)
    Times = {},                 -- fixed times in server time, e.g. { '06:00', '12:00', '18:00' }
                                -- Interval and Times can be combined: the first one that comes up wins.
    MinPlayers = 0,             -- skip an automatic wipe when fewer players are online
    SkipBeforeRestart = 10,     -- skip an automatic wipe when a txAdmin scheduled restart is less than
                                -- this many minutes away (the restart clears vehicles anyway). 0 = never skip.
}

-- Players are warned this many seconds before a wipe. The first warning is when the countdown starts.
Config.Warnings = { 300, 60, 30, 10 }

----------------------------------------------------------------------------------------------------
-- What gets removed
--   A vehicle is NEVER removed while a player sits in it (any seat), or while it is attached to a
--   vehicle with a player in it (trailers, cars on a flatbed, towed vehicles).
----------------------------------------------------------------------------------------------------
Config.Filter = {
    OnlyDamaged = false,        -- true = only remove damaged or destroyed vehicles
    DamagedBelow = 500,         -- engine or body health below this counts as damaged (1000 = brand new)

    PlayerRadius = 0,           -- keep vehicles within this many metres of any player (0 = off)
    SkipNpcDriven = true,       -- keep vehicles with an NPC driver (normal traffic)
    SkipLocked = false,         -- keep locked vehicles
    SkipOwned = false,          -- keep vehicles owned by a player (needs oxmysql + ESX, QBCore or Qbox)

    -- Vehicle types that are never removed: automobile, bike, boat, heli, plane, submarine, trailer, train
    ProtectedTypes = { 'train' },

    -- Models that are never removed (spawn names).
    ProtectedModels = {
        -- 'police', 'ambulance', 'firetruk',
    },

    -- Areas where nothing is removed (dealership showroom, police garage, car meet spot ...).
    ProtectedZones = {
        -- { label = 'PDM showroom', coords = vector3(-44.5, -1097.0, 26.4), radius = 25.0 },
    },
}

-- Other scripts can protect a single vehicle with the state bag `ldCarwipeProtected`
-- (Entity(vehicle).state:set('ldCarwipeProtected', true, true)) or exports.ld_carwipe:protectVehicle(vehicle).

----------------------------------------------------------------------------------------------------
-- How
----------------------------------------------------------------------------------------------------
Config.Delete = {
    PerBatch = 10,              -- vehicles removed per batch
    BatchDelay = 50,            -- milliseconds between batches, spreads the work so nothing hitches
    BeforeWipeDelay = 1000,     -- milliseconds between the ld_carwipe:beforeWipe event and the wipe,
                                -- so garage scripts can save vehicles first
}

----------------------------------------------------------------------------------------------------
-- Notifications
--   'auto'    = ox_lib, then ESX, then QBCore/Qbox, then chat (whatever your server runs)
--   'ox_lib' | 'esx' | 'qb' | 'chat' | 'custom' (uses Config.CustomNotify below) | 'none'
----------------------------------------------------------------------------------------------------
Config.Notify = {
    Type = 'auto',
    Duration = 8000,            -- milliseconds (ox_lib, QBCore)
    Position = 'top',           -- ox_lib only
}

-- Used when Config.Notify.Type = 'custom'. Runs on the server, so send it to the clients yourself.
-- kind = 'warning' | 'done' | 'cancelled'
Config.CustomNotify = function(message, kind)
    TriggerClientEvent('chat:addMessage', -1, { args = { 'CarWipe', message } })
end

----------------------------------------------------------------------------------------------------
-- Command
--   carwipe              start a wipe with the default countdown
--   carwipe <seconds>    start a wipe with your own countdown (0 = right now)
--   carwipe cancel       cancel the running countdown
--   carwipe preview      count what would be removed, without removing anything
--   carwipe status       next automatic wipe and last result
--   Allowed for: the server console, and players with `add_ace group.admin command.carwipe allow`.
----------------------------------------------------------------------------------------------------
Config.Command = 'carwipe'
Config.ManualCountdown = 60     -- default countdown for the command

----------------------------------------------------------------------------------------------------
-- Discord log (optional)
----------------------------------------------------------------------------------------------------
Config.Webhook = {
    Url = '',                   -- or `set ldcw_webhook "..."` in server.cfg (that one wins)
    Name = 'LD CarWipe',
    Color = 3447003,
}
