# Launcher

A search box in the middle of the screen, in the style of macOS Spotlight. Type to search installed **apps** and **ScotchOS commands**; a last row always offers to **search YouTube** for what you typed. Enter runs the highlighted row.

Keywords aim the box at one source (a *provider*):

| Type | Source | Enter | Shift + Enter |
|---|---|---|---|
| plain text | apps and commands that match, then "Search YouTube for …" | runs the row | the row's alternative, if it has one |
| `yt cats` | YouTube only | results page in a private browser window (Brave, workspace 1 by default) | plays the first video |
| `private cats` | Private search only | a private browser window on workspace 7, searching with its default engine, and you go there with it (`private` alone: an empty window). **SUPER + I** opens the launcher already on this chip. Closing that window takes you back to the workspace you came from | — |
| `> restart` or `sos restart` | ScotchOS commands only | runs it | — |
| `app firefox` | applications only | starts it | — |

A keyword or chip lists every match (up to 300), nine rows at a time: ↑ / ↓ and the mouse wheel scroll the rest into view. (`app` + Tab with nothing typed lists every installed app.)

**Tab** turns a typed keyword into a chip (`yt` + Tab → a *YouTube* chip, the rest of the line is the query). With no keyword typed, Tab steps through the chips (Commands, YouTube, Private, Apps, none); **Shift + Tab** goes back. **Backspace** on an empty line removes the chip. **Esc**, a click outside the box, or the keybind again closes it. **↑ / ↓** or **Ctrl + J / K** move the highlight.

Apps are found by name, by initials (`vsc` → Visual Studio Code, `lo` → LibreOffice), by the command they run (`code`) and by generic name or keywords. Apps you launch often rise: with nothing typed the most launched come first, and among apps that match equally well the more launched wins.

With nothing typed it shows the apps you have launched as square icons, most launched first, up to 18; they wrap onto a new row when the card is full (nine per row), the picked one's name is underneath. Arrow keys (or Ctrl + J / K) move through them, Enter starts it.

Commands: open settings, restart ScotchOS, "Private window" (an empty one, see `private` above), open Daily Theory, open the E-reader or "Continue reading <title>" (the book read last, at your place) and refresh Claude usage (while those are on), and "Switch on / off <name>" for every widget and tool.

Switch it off with `scotchos disable launcher`: the keybind stays but does nothing.

## Settings

`[launcher]` in `scotchos.conf`, also in the settings window. They affect the YouTube search (`yt-open.sh` reads them on each search); `private` uses `browser` only. Its search terms are passed as `"? terms"`, which Chromium browsers (Brave, Chrome) understand; other browsers may not.

| Key | Default | What it does |
|---|---|---|
| `browser` | `brave --incognito --new-window` | The browser command; the URL is added at the end. Firefox: `firefox --private-window` |
| `browser_class` | `brave-browser` | The class of its windows in `hyprctl clients`, to tell when the new one has appeared. Firefox: `firefox` |
| `workspace` | `1` | The workspace it opens on; focus comes back to yours afterwards |

Which keyword picks which provider is in each provider file (`keywords`).

## Files in this folder

| File | What it does |
|---|---|
| `launcher.sh` | What the keybinds run. Exits if `launcher` is off, else `scotchos launcher` (toggle; `launcher.sh private` starts on the Private chip). |
| `Launcher.qml` | Loaded by `shell.qml` while `launcher` is on. The `launcher` IPC target, the provider list, and the window's loader. |
| `LauncherWindow.qml` | The window: chip, input, result rows, keys. Exists only while open. |
| `Provider.qml` | The shape of a provider (keywords, `search`, `fallback`). |
| `AppsProvider.qml` | Applications, from Quickshell's desktop entries; keeps the launch counts. |
| `score.js` | Ranks the apps for a query (pure JS, also run by the tests). |
| `tests/score.test.mjs` | Tests for `score.js` (`scotchos test`, needs node). |
| `YouTubeProvider.qml` | The "Search YouTube" rows. |
| `PrivateProvider.qml` | The `private` keyword's row. |
| `CommandsProvider.qml` | ScotchOS commands and the on/off switches. |
| `yt-open.sh` | Opens the search (or the first video) in the browser on the `[launcher]` workspace, then restores focus. |
| `private-open.sh` | Focuses workspace 7 and opens a private browser window there, with the search if one was typed; when that window closes, focuses the workspace you came from. |
| `README.md` | This file. |

## Requirements

The versions are the ones this was built and tested with, on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The window, desktop entries, `execDetached` |
| Hyprland with **Lua config** | `hyprland` | 0.56.2 | The keybind, the focused monitor, `hyprctl dispatch 'hl.dsp.…'` in `yt-open.sh` and `private-open.sh` |
| socat, jq | `socat`, `jq` | 1.8.1.3, 1.8.2 | `private-open.sh` reads Hyprland's event socket (`.socket2.sock`) to see the private window close |
| Brave | `brave-bin` | 1.97.59 | YouTube results and the private window (`--incognito --new-window`) |
| jq | `jq` | 1.8.2 | URL-encoding the query, reading `hyprctl … -j` |
| curl | `curl` | 8.23.0 | Finding the first video (Shift + Enter on a YouTube row) |
| setsid | `util-linux` | 2.42 | Detaching Brave from the script |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd` | — | Font and the row glyphs |

```bash
sudo pacman -S --needed quickshell hyprland jq curl util-linux ttf-jetbrains-mono-nerd
paru -S brave-bin   # or: yay -S brave-bin
```

## Changes made to the system

### 1. `~/.config/hypr/hyprland.lua`: keybind

```lua
-- ScotchOS launcher (apps, YouTube search, ScotchOS commands)
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/tools/launcher/launcher.sh"), {
        description = "[Launcher|ScotchOS] launcher",
})
```

This first went on `SUPER + Y` (replacing the old YouTube search bind), then swapped with HyDE's rofi app finder: the launcher is on `SUPER + SPACE` and the rofi app finder moved to `SUPER + Y`:

```lua
-- Application Launcher
hl.bind("SUPER + Y", hl.dsp.exec_cmd(hyde.sh.menu.apps()), {
        description = "[Launcher|Rofi menus] application finder",
})
```

### 2. `~/.config/hypr/hyprland.lua`: private search bind

Under the launcher bind, `SUPER + I` opens the launcher already on the Private chip:

```lua
hl.bind("SUPER + I", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/tools/launcher/launcher.sh private"), {
        description = "[Launcher|ScotchOS] private search",
})
```

### 3. `~/.config/hypr/hyprland.lua`: workspace 1 pinned to the laptop screen

Above the workspace 2 and 3 rules (it was added for the old YouTube tool; `yt-open.sh` opens Brave on workspace 1):

```lua
hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })
```

### 4. Backup

The config before the bind change is `~/.config/hypr/hyprland.lua.bak-before-launcher`, before the Y/Space swap `~/.config/hypr/hyprland.lua.bak-before-swap-y-space`, and before the SUPER + I bind `~/.config/hypr/hyprland.lua.bak-before-private-bind`. Apply with `hyprctl reload`.

## Running it by hand

```bash
scotchos launcher          # toggle   (also: open, close)
scotchos launcher private  # toggle, starting on the Private chip
~/Projects/ScotchOS/tools/launcher/launcher.sh
```

With `scotchos disable launcher` the script exits at once with 0 and opens nothing.

## Adapting

| What | Where | Current value |
|---|---|---|
| Keybind | `hyprland.lua` | see above |
| Where the box sits | `LauncherWindow.qml`, `card` (`y: parent.height * 0.2`, `width: 640`) | 20 % from the top, 640 px |
| Keywords | each provider's `keywords` | `>`/`sos`, `yt`/`youtube`, `private`, `app` |
| Order Tab steps through | `Launcher.qml`, `providers` | Commands, YouTube, Private, Apps |
| Browser, window class, workspace | `[launcher]` in `scotchos.conf` (see Settings) | Brave, workspace 1 |
| "Private window" workspace | `private-open.sh`, the `hl.dsp.focus` line | 7 |
| Old-style config (`hyprland.conf`) | — | `bind = SUPER, SPACE, exec, <path>/launcher.sh`; in `yt-open.sh` use `hyprctl dispatch workspace N` |

**A new source** is one file: a `Provider { name; glyph; keywords; search: q => [rows] }` (copy `YouTubeProvider.qml`), then add it to the `providers` list in `Launcher.qml`. A row is `{ title, subtitle, glyph or iconName, run(), alt() }`.

## How it works

1. The keybind runs `launcher.sh`, which calls `scotchos launcher`, an IPC call to the one Quickshell process. `Launcher.qml` flips `open`, and a `LazyLoader` creates the window (and destroys it on close, so nothing runs while it's shut).
2. The window is a full-screen layer on the focused monitor (overlay layer, exclusive keyboard focus, a dimmed backdrop that closes on click) with the card inside.
3. Every keystroke recomputes `results`: a keyword or chip asks that one provider; plain text asks the providers marked `inDefault` (top five each), then appends every provider's `fallback` rows, which are never cut off.
4. The rows are a fixed set of nine delegates that show or hide, so typing doesn't create or destroy anything. App icons are decoded at 28 px.
5. Running a row calls its `run()`. For an app that also adds one to its count in `launcher-counts.json` (in Quickshell's cache folder, `{ desktop id: launches }`, written only then, atomically; ids no longer installed are dropped). Programs are started with `Quickshell.execDetached`, so they outlive the window.
6. YouTube: `yt-open.sh` URL-encodes the query, optionally fetches the first video id, reads `[launcher]` with `scotchos get`, focuses that workspace, starts the browser, waits for it to appear and returns to your workspace.
7. Private window: `private-open.sh` focuses workspace 7 and starts the browser, adding `"? terms"` if a search was typed. A window from a running browser opens on the focused workspace, so focus goes first. Before starting the browser it connects to Hyprland's event socket with `socat`, takes the first `openwindow` on workspace 7 as the private window (20 s at most), then blocks until that window's `closewindow` (no CPU while waiting) and focuses the workspace you were on, if you're still on 7. `scotchos launcher private` sets `startMode` to the Private provider before opening, and the window's `mode` starts from it.

### Ranking

`score.js` gives each app a tier by how it matched: name starts with the query (4000), name contains it (3000), initials start with it (2000, two letters or more), the command's basename contains it (1500), generic name or keywords contain it (1000). The launch bonus is `100 × log2(1 + launches)`, at most 400, so it reorders apps in the same tier but a worse kind of match never passes a better one. Ties go by name.

## Uninstall

To only switch it off: `scotchos disable launcher`. To remove it:

1. Remove the launcher binds (SUPER + SPACE, SUPER + I) from `~/.config/hypr/hyprland.lua` and `hyprctl reload`.
2. Delete this folder, its `LazyLoader` and import in `shell.qml`, the `launcher` line in `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, its entry in `settings/SettingsWindow.qml`, and the `launcher` command in `bin/scotchos`.
