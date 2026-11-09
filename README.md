# LD CarWipe

**Free, automatic vehicle cleanup for FiveM.** Removes abandoned vehicles on a schedule, warns players first, and never touches a vehicle someone is sitting in. Server-side only: nothing is added to your players' game.

Standalone. Works with ESX, QBCore, Qbox or no framework at all.

## Features

- **Schedule your way:** every X minutes, at fixed times (`06:00`, `18:00`), or both.
- **Countdown with warnings** (5 min, 1 min, 30 s, 10 s by default) through the notifications your server already uses: ox_lib, ESX, QBCore/Qbox or chat, detected automatically. Or plug in your own.
- **Safe by design:**
  - a vehicle with a player in **any** seat is never removed (planes with passengers too);
  - cars on an occupied flatbed and trailers behind an occupied truck stay;
  - every vehicle is checked again right before it is removed.
- **Smart filters:** only damaged vehicles, keep vehicles near players, keep NPC traffic, keep locked vehicles, keep **player-owned** vehicles (oxmysql), protected models, vehicle types (trains by default) and zones.
- **No hitches:** vehicles are removed in small batches, spread over time.
- **Plays nice with txAdmin:** an automatic wipe right before a scheduled restart is skipped.
- **`carwipe preview`** shows what a wipe *would* remove, without removing anything. Handy while you tune the filters.
- **For developers:** exports, events and a state bag to protect vehicles from your own scripts (e.g. vehicles for sale).
- Optional Discord webhook log, update check, 8 languages (en, nl, de, fr, es, pt, pl, tr).

## Install

1. Download the latest release and put the `ld_carwipe` folder in your `resources` folder.
2. Add to `server.cfg`:
   ```cfg
   ensure ld_carwipe
   add_ace group.admin command.carwipe allow
   ```
3. Restart the server. That's it: every hour, empty vehicles are removed after a 5 minute countdown.

Needs OneSync (on by default on every modern server). Tune everything in `config.lua`.

## Command

| Command | What it does |
|---|---|
| `carwipe` | Start a wipe with the default countdown (`Config.ManualCountdown`, 60 s) |
| `carwipe <seconds>` | Start a wipe with your own countdown |
| `carwipe now` | Wipe right away |
| `carwipe cancel` | Cancel the running countdown |
| `carwipe preview` | Count what would be removed, remove nothing |
| `carwipe status` | Next automatic wipe and the last result |

Works from the server console, and for players with the `command.carwipe` ACE.

## For developers

```lua
-- protect one vehicle (entity or network id), e.g. a car that is for sale
exports.ld_carwipe:protectVehicle(vehicle)          -- protect
exports.ld_carwipe:protectVehicle(vehicle, false)   -- stop protecting
-- or with the state bag, from any resource:
Entity(vehicle).state:set('ldCarwipeProtected', true, true)

exports.ld_carwipe:startWipe(60)      -- countdown in seconds, returns true | false, reason
exports.ld_carwipe:cancelWipe()       -- true when a countdown was cancelled
exports.ld_carwipe:getStatus()        -- { running, countdown, nextAuto, last }
exports.ld_carwipe:previewWipe()      -- { remove, total, kept = { reason = count } } (call from a thread)
```

Server events:

| Event | When | Data |
|---|---|---|
| `ld_carwipe:countdown` | every warning | seconds left |
| `ld_carwipe:beforeWipe` | just before the wipe (`Config.Delete.BeforeWipeDelay` ms) | `{ reason, by }` |
| `ld_carwipe:afterWipe` | after the wipe | `{ removed, kept, total, ms, reason, by }` |
| `ld_carwipe:cancelled` | countdown cancelled | who cancelled |

Garage script? Listen to `ld_carwipe:beforeWipe` to store vehicles first, or use `Config.Filter.SkipOwned`.

## Support

Questions or ideas: open an issue, or join the LD Scripts Discord: https://discord.ldscripts.com

## More from LD Scripts

- **LD Queue**: a reliable, fair connection queue with priority, restart protection and a live queue card.
- **LD Refunds**: refunds and compensation for players, with a Discord bot and web dashboard.

See https://store.ldscripts.com

## License

MIT. Free to use and change on your server.
