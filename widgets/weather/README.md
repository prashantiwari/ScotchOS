# Weather

A weather card drawn **on the desktop**, at the top centre of **every screen**, in the same style as the other ScotchOS cards. It sits above the wallpaper and below your windows, never takes keyboard focus, lets clicks pass through, and doesn't show up in Alt+Tab. It only appears on screens whose current workspace has no tiled windows.

It shows:

- **Header:** the title, the place (when it's known by name) and the time of the last fetch.
- **Now:** a large condition icon (day or night version), the temperature, the condition and the "feels like" temperature; on the right, today's high and low, humidity and wind, sunrise and sunset.
- **The next 24 hours:** the temperature as a filled curve with the warmest and coolest hour marked, the chance of rain as faint bars under it, and a time label every 6 hours.
- **The coming days:** today and the following days, each with an icon, the high and low, and the chance of rain when it's 20 % or more.

The data comes from [Open-Meteo](https://open-meteo.com) (free, no key). Times on the card are the location's own clock.

## Settings

The `[weather]` section of `~/.config/scotchos/scotchos.conf` (defaults in [`scotchos.default.conf`](../../scotchos.default.conf)); `weather` under `[enabled]` switches it on and off. Changes apply as soon as you save; a new `location` or `units` fetches again right away.

| Key | Values | Default |
|---|---|---|
| `location` | `auto` (from your IP address), a city name (`Pune`), or `lat,lon` (`18.52,73.86`) | `auto` |
| `units` | `metric` (°C, km/h) or `imperial` (°F, mph) | `metric` |
| `days` | Days in the forecast row, today included, `3` - `7` | `5` |
| `show_hourly` | Show the 24-hour curve (`yes` / `no`) | `yes` |
| `position` | `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` | `top` |
| `margin_x`, `margin_y` | Gap in px from the edges the card touches | `20` / `20` |
| `interval` | Minutes between fetches (at least 10) | `30` |

`auto` uses your public IP address, so behind a VPN it shows the weather where the VPN exits. Set a city name if that's wrong.

## Files in this folder

| File | What it does |
|---|---|
| `WeatherWidget.qml` | Reads `[weather]`, finds the location, fetches and caches the forecast, maps weather codes to icons, and creates one desktop-layer panel per screen. |
| `WeatherCard.qml` | The card: header, current conditions and the day row. |
| `TempCurve.qml` | The 24-hour curve, drawn on a `Canvas`. |
| `README.md` | This file. |

## Requirements

Built and tested on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The panel, the canvas, and the HTTP requests (QML's built-in `XMLHttpRequest`, no curl needed) |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and the weather icons (Material Design glyphs) |
| Network access | — | — | `api.open-meteo.com`, `geocoding-api.open-meteo.com` (city names), `ipinfo.io` then `ip-api.com` (`auto`) |
| HyDE (optional) | — | — | The wallbash colors, as for the other cards |

## Changes made to the system

None of its own. The shell is started from `~/.config/hypr/hyprland.lua`; see the [main README](../../README.md#hyprland).

## Running it by hand

Part of the single ScotchOS shell (see the [main README](../../README.md)); it isn't started on its own.

```bash
scotchos disable weather   # unload it (applies right away)
scotchos enable weather    # load it again
scotchos restart           # restart the whole shell
```

To fetch right now, delete the cached forecast and restart:

```bash
rm ~/.cache/quickshell/by-shell/*/weather.json   # only this widget writes weather.json
scotchos restart
```

Logs: `scotchos log 2>&1 | grep weather`

## Adapting

| What | Where | Current value |
|---|---|---|
| Card width | `contentWidth` in `WeatherCard.qml` | 340 px |
| Curve height | `height` of the `Canvas` in `TempCurve.qml` | 64 px |
| Icons and labels per weather code | `describe()` in `WeatherWidget.qml` | Material Design weather glyphs |
| Rain chance shown in the day row from | `opacity` on the rain `Text` in `WeatherCard.qml` | 20 % |
| Retry delay after a failure | `retryMs` in `WeatherWidget.qml` | 5 minutes |
| Transparency | `Qt.alpha(shell.bg, 0.78)` in `WeatherCard.qml` | 78 % opaque |

## How it works

1. **Timing:** a timer checks once a minute whether `interval` minutes have passed since the last fetch (or the location or units changed). It only runs while some screen shows an empty workspace, so nothing is fetched while the card can't be seen. The same tick moves the curve on, so it always starts at the current hour, from the 48 hours fetched. A failed attempt waits 5 minutes before the next one.
2. **Location:** `lat,lon` is used as is; a city name goes through Open-Meteo's geocoding API; `auto` asks ipinfo.io, then ip-api.com if that fails.
3. **Forecast:** one request to Open-Meteo for the current conditions, 48 hourly points and 8 days, with `timeformat=unixtime` so hours compare with the local clock whatever the location's time zone. The reply is trimmed and saved to `weather.json` in Quickshell's cache, so a restart shows it right away.
4. **Drawing:** the curve is a `Canvas` repainted only when the data or the hour changes; nothing animates. The day row is a fixed `Repeater` of `days` columns whose texts change in place.
5. **Panel:** a layer-shell surface on the **bottom** layer, with an exclusive zone of `0` and an empty input `mask`, like the other cards.

The card is about 300 px tall. On the laptop screen (1280 × 720 logical) at `top` it sits between the dashboard on the left and the Claude usage card at top-right.

## Uninstall

1. Switch it off: `scotchos disable weather`, or `weather = no` in `scotchos.conf`. That alone unloads it.
2. To remove it for good: delete the `LazyLoader` holding `WeatherWidget` and its `import "widgets/weather"` from `shell.qml`, its entry in `settings/SettingsWindow.qml`, its row in the main README, the `weather` line under `[enabled]` and the `[weather]` section from `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, then this folder.
