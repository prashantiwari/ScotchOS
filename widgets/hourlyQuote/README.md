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

If both fail (offline, rate-limited), the card keeps the last quote and tries again 5 minutes later. To use a different API, add an entry to `sources` in `QuoteWidget.qml`: a `url` and a `parse` function that turns the JSON body into `{ text, author }`.

The last quote and its fetch time are saved in Quickshell's cache (`~/.cache/quickshell/by-shell/<id>/quote.json`), so after a restart or reboot the card shows it right away and only fetches again once the hour is up.

## Settings

The `[quote]` section of `~/.config/scotchos/scotchos.conf` (defaults in [`scotchos.default.conf`](../../scotchos.default.conf)); `quote` under `[enabled]` switches it on and off. Save the file and the change applies right away, with no restart:

| Key | Values | Default |
|---|---|---|
| `position` | `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` | `bottom-right` |
| `margin_x`, `margin_y` | Gap in px from the edges the card touches | `20` / `20` |
| `interval` | Minutes between new quotes | `60` |

## Files in this folder

| File | What it does |
|---|---|
| `QuoteWidget.qml` | Reads `[quote]`, fetches and caches the quote, and creates one desktop-layer panel per screen. |
| `QuoteCard.qml` | The card: header, quote and author. |
| `README.md` | This file. |

## Requirements

Built and tested on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The panel, and the HTTP request (QML's built-in `XMLHttpRequest`, no curl needed) |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and the quote / clock icons |
| HyDE (optional) | — | — | `~/.cache/hyde/wallbash/scotchos.dcol` with the wallbash colors (needs [`wallbash/scotchos.dcol`](../../wallbash/scotchos.dcol) copied to `~/.config/hyde/wallbash/always/`) |

## Changes made to the system

None of its own. The shell is started from `~/.config/hypr/hyprland.lua`; see the [main README](../../README.md#hyprland).

## Running it by hand

Part of the single ScotchOS shell (see the [main README](../../README.md)); it isn't started on its own.

```bash
scotchos disable quote   # unload it (applies right away)
scotchos enable quote    # load it again
scotchos restart         # restart the whole shell, e.g. after changing the sources
```

QML changes show up as soon as you save. Logs: `scotchos log`

To get a new quote right now, delete the cached one and restart:

```bash
rm ~/.cache/quickshell/by-shell/*/quote.json   # only this widget writes quote.json
scotchos restart
```

## Adapting

| What | Where | Current value |
|---|---|---|
| Card width | `contentWidth` in `QuoteCard.qml` | 340 px |
| Lines before cutting | `maximumLineCount` on the quote `Text` in `QuoteCard.qml` | 5 |
| Retry delay after a failure | `retryMs` in `QuoteWidget.qml` | 5 minutes |
| Quote sources | `sources` in `QuoteWidget.qml` | ZenQuotes, then DummyJSON |
| Transparency | `Qt.alpha(shell.bg, 0.78)` in `QuoteCard.qml` | 78 % opaque |
| Which screens | `Variants { model: Quickshell.screens }` in `QuoteWidget.qml` | All screens |

## How it works

1. **Timing:** a timer checks once a minute whether `interval` minutes have passed since the last fetch. It only runs while some screen shows an empty workspace, so nothing is fetched while the quote can't be seen; it checks right away when one becomes empty. Checking often instead of one long timer means the quote also refreshes soon after waking from suspend. A failed attempt waits 5 minutes before the next one, so a dead connection doesn't hammer the APIs.
2. **Fetching:** QML's `XMLHttpRequest` asks each source in turn (15 s timeout) until one gives a non-empty quote.
3. **Colors:** the same wallbash colors as the other cards, from `~/.cache/hyde/wallbash/scotchos.dcol`, so it recolors with your wallpaper and theme.
4. **Panel:** a layer-shell surface on the **bottom** layer, with an exclusive zone of `0` and an empty input `mask`, just like the other cards.

On the laptop screen (1280 × 720 logical) the card fits under the now playing card. A quote of 5 lines makes it about 200 px tall, which can touch the now playing card; if it does, move one of them with `position`.

## Uninstall

1. Switch it off: `scotchos disable quote`, or `quote = no` in `scotchos.conf`. That alone unloads it.
2. To remove it for good: delete the `LazyLoader` holding `QuoteWidget` and its `import "widgets/hourlyQuote"` from `shell.qml`, the `quote` line under `[enabled]` and the `[quote]` section from `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, then this folder.

