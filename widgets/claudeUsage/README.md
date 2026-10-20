# Claude Usage

A card drawn **on the desktop**, in the top-right corner of **every screen**, showing how much of your Claude plan's usage limits you've used: the same numbers as `/usage` in Claude Code. It's in the same style as the other cards: above the wallpaper, below your windows, never takes keyboard focus, lets clicks pass through, and only appears on screens whose current workspace has no tiled windows.

It shows:

- **Header:** the title and the time the 5-hour window resets, or `-` while no window is running (`stale` in amber if the reading is more than two intervals old).
- **5-hour** and **7-day** rows: the percentage used, a bar (red from `warn` %), and a countdown to the reset.
- **A status line** when something is wrong: not logged in, the token expired, rate-limited, …

With `size = compact` it's one small line instead: the icon, `5h 35%  7d 39%`, with a percentage turning red from `warn` and the icon turning amber while the reading is stale or the last fetch failed.

`size = minimal` sits in between: the full card's title bar (title, reset time, `stale`), then just the two percentages in large type with "5-hour" and "7-day" under them.

These are the plan-wide limits, so they include claude.ai chats as well as Claude Code.

## Where the numbers come from

`GET https://api.anthropic.com/api/oauth/usage`, authenticated with the OAuth token Claude Code keeps in `~/.claude/.credentials.json`. Only `five_hour` and `seven_day` are read from the response. If one of them is missing or null, the card shows the other (only both missing counts as a failed fetch).

- **This endpoint is undocumented.** It's what Claude Code's `/usage` uses, so it can change without notice. If the two fields go missing, the card says so and keeps the last reading.
- **The token is only read, never refreshed.** Claude Code owns that file and refreshes the token when you use it. While the token is expired, the card shows the last reading with "token expired - open Claude Code"; it picks the new token up as soon as the file changes.
- The token is sent only to `api.anthropic.com`. The cache file holds percentages and times, never the token.

## When it fetches

- **At every login**, or more exactly every time the shell starts (`scotchos restart`, enabling the widget): one fetch as soon as the credentials file is read, whatever the cache says.
- **Every `interval` minutes** (30 by default) after that.
- **Once a limit's reset time passes**, so the card doesn't keep showing the old percentage (at most once every 10 minutes).
- **After a failure**, it waits 10 minutes before trying again, or tries right away when Claude Code saves a new token (at most once every 30 s).
- **Whenever you ask:** `scotchos claude refresh`, or **Refresh now** on the Claude usage page of the settings window. Either one skips the waits above, but not a 30-second cooldown, so repeated presses can't get the endpoint to rate-limit you. The command prints `fetching`, or why it skipped. While a fetch runs, the clock in the title shows `…` (the icon dims on the compact card).

The minute timer only runs while some screen shows an empty workspace. If your windows cover every screen for longer than `interval`, it fetches as soon as one is empty again.

The last reading is saved in Quickshell's cache (`~/.cache/quickshell/by-shell/<id>/claude-usage.json`), so the card shows it straight away while the login fetch runs.

## Settings

The `[claudeusage]` section of [`scotchos.conf`](../../scotchos.conf); `claudeusage` under `[enabled]` switches it on and off. Save the file and the change applies right away, with no restart:

| Key | Values | Default |
|---|---|---|
| `size` | `full` (bars and countdowns), `compact` (one line with the two percentages), `minimal` (title bar and the two percentages, large) | `full` |
| `position` | `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` | `top-right` |
| `margin_x`, `margin_y` | Gap in px from the edges the card touches | `20` / `20` |
| `interval` | Minutes between fetches (at least 5) | `30` |
| `warn` | Percentage at which a bar turns red | `80` |

## Files in this folder

| File | What it does |
|---|---|
| `ClaudeUsageWidget.qml` | Reads `[claudeusage]` and the credentials, fetches and caches the usage, and creates one desktop-layer panel per screen. |
| `ClaudeUsageCard.qml` | The full card: header, a bar and countdown per limit, the status line. |
| `ClaudeUsageCompactCard.qml` | The compact card: one line with the two percentages. |
| `ClaudeUsageMinimalCard.qml` | The minimal card: title bar and the two percentages in large type. |
| `README.md` | This file. |

## Requirements

Built and tested on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The panel, and the HTTP request (QML's built-in `XMLHttpRequest`, no curl needed) |
| Claude Code, logged in with a Claude plan | `claude-code` | 2.1.304 (Pro) | The OAuth token in `~/.claude/.credentials.json` |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and the robot / clock icons |
| HyDE (optional) | — | — | `~/.cache/hyde/wallbash/scotchos.dcol` with the wallbash colors |

## Changes made to the system

None of its own. The shell is started from `~/.config/hypr/hyprland.lua`; see the [main README](../../README.md#hyprland). That start, at login, is what triggers the login fetch.

## Running it by hand

Part of the single ScotchOS shell (see the [main README](../../README.md)); it isn't started on its own.

```bash
scotchos disable claudeusage   # unload it (applies right away)
scotchos enable claudeusage    # load it again, and fetch
scotchos restart               # restart the whole shell, which also fetches right away
scotchos claude refresh        # fetch now (qs ipc call claudeusage refresh)
```

QML changes show up as soon as you save. Logs: `scotchos log 2>&1 | grep claudeUsage`

The same request from a terminal:

```bash
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $(jq -r .claudeAiOauth.accessToken ~/.claude/.credentials.json)" \
  -H "anthropic-beta: oauth-2025-04-20" | jq '{five_hour, seven_day}'
```

## Adapting

| What | Where | Current value |
|---|---|---|
| Card width | `contentWidth` in `ClaudeUsageCard.qml` / `ClaudeUsageMinimalCard.qml` | 340 px / 240 px |
| Retry delay after a failure | `retryMs` in `ClaudeUsageWidget.qml` | 10 minutes |
| Cooldown between manual refreshes | `cooldownMs` in `ClaudeUsageWidget.qml` | 30 s |
| Which limits are shown | `Repeater` model in `ClaudeUsageCard.qml`, `fetchUsage()` in `ClaudeUsageWidget.qml` | `five_hour`, `seven_day` |
| Warning / stale colors | `#ff6b6b` / `#f0b429` in `ClaudeUsageCard.qml` | Same as the dashboard's |
| Transparency | `Qt.alpha(shell.bg, 0.78)` in `ClaudeUsageCard.qml` | 78 % opaque |
| Which screens | `Variants { model: Quickshell.screens }` in `ClaudeUsageWidget.qml` | All screens |

## How it works

1. **Credentials:** a `FileView` watches `~/.claude/.credentials.json`. Its first load triggers the login fetch, and later changes (Claude Code refreshing the token) update the token in memory. If `expiresAt` has passed, it doesn't send the request.
2. **Timing:** a timer ticks once a minute (only while a screen shows an empty workspace), moving the countdowns and checking whether a fetch is due. Short ticks instead of one 30-minute timer mean it catches up right after a suspend.
3. **Manual refresh:** an `IpcHandler` (`claudeusage` → `refresh()`) for the command, and the shell root's `action` signal for the settings button. Both call the same `refresh()`, which applies the cooldown.
4. **Fetching:** QML's `XMLHttpRequest` (15 s timeout). No helper process runs, ever.
5. **Drawing:** a `Loader` creates only the card for the current `size`. Fixed rows, no animations, so the panel only redraws when a number or a countdown changes.
6. **Panel:** a layer-shell surface on the **bottom** layer, with an exclusive zone of `0` and an empty input `mask`, like the other cards.

On the laptop screen (1280 × 720 logical) the full card is about 170 px tall (minimal about 120 px, compact about 36 px) and sits above the now playing card on the right.

## Uninstall

1. Switch it off: `scotchos disable claudeusage`, or `claudeusage = no` in `scotchos.conf`. That alone unloads it.
2. To remove it for good: delete the `LazyLoader` holding `ClaudeUsageWidget` and its `import "widgets/claudeUsage"` from `shell.qml`, the `claudeusage` line under `[enabled]` and the `[claudeusage]` section from `scotchos.conf`, its entry in `items` in `settings/SettingsWindow.qml`, its row in the main README, then this folder. Optionally `rm ~/.cache/quickshell/by-shell/*/claude-usage.json`.
