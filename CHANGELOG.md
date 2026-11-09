# Changelog

## 2.0.0 (rewrite)

Completely rewritten as **LD CarWipe** (resource `ld_carwipe`). Remove the old `CarWipe` resource and the `cron` dependency before installing.

- Server-side only: no client script, no loops in your players' game.
- Schedule with an interval, fixed times or both. No `cron` resource needed anymore.
- Countdown with configurable warnings, sent through ox_lib, ESX, QBCore/Qbox or chat (detected automatically), or your own function.
- Fixed: vehicles with only passengers (e.g. a plane in the air) could be removed. Every seat is checked now, and again right before removing.
- Cars on an occupied flatbed and trailers behind an occupied truck are kept.
- New filters: near players, NPC traffic, locked, player-owned (oxmysql), protected types (trains by default), models and zones.
- `OnlyDamaged` no longer removes vehicles whose health the server can't know (vehicles nobody is syncing).
- Removed in batches spread over time.
- Automatic wipes are skipped right before a txAdmin scheduled restart, or with too few players online.
- `carwipe now | cancel | preview | status`.
- Exports, events and the `ldCarwipeProtected` state bag for other scripts.
- Optional Discord webhook, update check, 8 languages.

## 1.1.1 and older

The original CarWipe (2022). Still available as the `v1-legacy` tag.
