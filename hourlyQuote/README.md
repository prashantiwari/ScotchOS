# Hourly Quote

A quote card drawn **on the desktop**, in the bottom-right corner of **every screen**, in the same style as the [system dashboard](../systemDashboard/README.md) and [now playing](../nowPlaying/README.md) cards. It sits above the wallpaper and below your windows, never takes keyboard focus, lets clicks pass through, and doesn't show up in Alt+Tab. It only appears on screens whose current workspace has no tiled windows: as soon as one opens there it's hidden and not drawn at all. Floating windows don't count, unless they're fullscreen.

Every hour it fetches a new quote from the web and shows:

- **Header:** the title, and the time the current quote was fetched.
- **The quote** in italics, up to 5 lines (anything longer is cut with …).
- **The author**, right-aligned in the accent color.

## Where the quotes come from

| Source | Key needed? | Used |
|---|---|---|
| [ZenQuotes](https://zenquotes.io) `api/random` | No | First choice |
| [DummyJSON](https://dummyjson.com/docs/quotes) `quotes/random` | No | If ZenQuotes fails |

If both fail (offline, rate-limited), the card keeps the last quote and tries again 5 minutes later. To use a different API, add an entry to `sources` in `shell.qml`: a `url` and a `parse` function that turns the JSON body into `{ text, author }`.

The last quote and its fetch time are saved in Quickshell's cache (`~/.cache/quickshell/by-shell/<id>/quote.json`), so after a restart or reboot the card shows it right away and only fetches again once the hour is up.

## Settings

`quote.conf`. Save the file and the change applies right away, with no restart:

| Key | Values | Default |
|---|---|---|
| `position` | `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` | `bottom-right` |
| `margin_x`, `margin_y` | Gap in px from the edges the card touches | `20` / `20` |
| `interval` | Minutes between new quotes | `60` |

## Files in this folder

| File | What it does |
|---|---|
| `quote.conf` | Settings: position, margins, interval. |
| `shell.qml` | Entry point. Loads the wallbash colors and `quote.conf`, fetches and caches the quote, and creates one desktop-layer panel per screen. |
| `QuoteCard.qml` | The card: header, quote and author. |
| `README.md` | This file. |

## Requirements

Built and tested on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The panel, and the HTTP request (QML's built-in `XMLHttpRequest`, no curl needed) |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and the quote / clock icons |
| HyDE (optional) | — | — | `~/.cache/hyde/wallbash/scotchos.dcol` with the wallbash colors (needs [`wallbash/scotchos.dcol`](../wallbash/scotchos.dcol) copied to `~/.config/hyde/wallbash/always/`) |

## Changes made to the system

`~/.config/hypr/hyprland.lua`: added to the `hl.on("hyprland.start", …)` block, right after the now playing line:

```lua
-- ScotchOS hourly quote card (desktop layer, bottom-right of every screen)
hl.exec_cmd("qs -n -d -p " .. projects .. "/ScotchOS/hourlyQuote")
```

The config before this edit was saved as `~/.config/hypr/hyprland.lua.bak-before-quote`.

## Running it by hand

```bash
qs -n -d -p ~/Projects/ScotchOS/hourlyQuote   # start
qs kill -p ~/Projects/ScotchOS/hourlyQuote    # stop
```

To get a new quote right now, delete the cached one and restart:

```bash
qs kill -p ~/Projects/ScotchOS/hourlyQuote
rm ~/.cache/quickshell/by-shell/*/quote.json   # only this widget writes quote.json
qs -n -d -p ~/Projects/ScotchOS/hourlyQuote
```

Logs: `qs log -p ~/Projects/ScotchOS/hourlyQuote`

## Adapting

| What | Where | Current value |
|---|---|---|
| Card width | `contentWidth` in `QuoteCard.qml` | 340 px |
| Lines before cutting | `maximumLineCount` on the quote `Text` in `QuoteCard.qml` | 5 |
| Retry delay after a failure | `retryMs` in `shell.qml` | 5 minutes |
| Quote sources | `sources` in `shell.qml` | ZenQuotes, then DummyJSON |
| Transparency | `Qt.alpha(shell.bg, 0.78)` in `QuoteCard.qml` | 78 % opaque |
| Which screens | `Variants { model: Quickshell.screens }` in `shell.qml` | All screens |

## How it works

1. **Timing:** a timer checks once a minute whether `interval` minutes have passed since the last fetch. Checking often instead of one long timer means the quote also refreshes soon after waking from suspend. A failed attempt waits 5 minutes before the next one, so a dead connection doesn't hammer the APIs.
2. **Fetching:** QML's `XMLHttpRequest` asks each source in turn (15 s timeout) until one gives a non-empty quote.
3. **Colors:** the same wallbash colors as the other cards, from `~/.cache/hyde/wallbash/scotchos.dcol`, so it recolors with your wallpaper and theme.
4. **Panel:** a layer-shell surface on the **bottom** layer, with an exclusive zone of `0` and an empty input `mask`, just like the other cards.

On the laptop screen (1280 × 720 logical) the card fits under the now playing card. A quote of 5 lines makes it about 200 px tall, which can touch the now playing card; if it does, move one of them with `position`.

## Uninstall

1. Stop it: `qs kill -p ~/Projects/ScotchOS/hourlyQuote`
2. Remove the two hourly quote lines from the `hyprland.start` block in `~/.config/hypr/hyprland.lua`.
3. Delete this folder.
