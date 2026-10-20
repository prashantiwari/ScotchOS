# Launcher

A search box in the middle of the screen, in the style of macOS Spotlight. Type to search installed **apps** and **ScotchOS commands**; a last row always offers to **search YouTube** for what you typed. Enter runs the highlighted row.

Keywords aim the box at one source (a *provider*):

| Type | Source | Enter | Shift + Enter |
|---|---|---|---|
| plain text | apps and commands that match, then "Search YouTube for …" | runs the row | the row's alternative, if it has one |
| `yt cats` | YouTube only | results page in a private browser window (Brave, workspace 1 by default) | plays the first video |
| `> restart` or `sos restart` | ScotchOS commands only | runs it | — |
| `app firefox` | applications only | starts it | — |

**Tab** turns a typed keyword into a chip (`yt` + Tab → a *YouTube* chip, the rest of the line is the query). With no keyword typed, Tab steps through the chips (Commands, YouTube, Apps, none); **Shift + Tab** goes back. **Backspace** on an empty line removes the chip. **Esc**, a click outside the box, or the keybind again closes it. **↑ / ↓** or **Ctrl + J / K** move the highlight.

Commands: open settings, restart ScotchOS, open Daily Theory and refresh Claude usage (while those are on), and "Switch on / off <name>" for every widget and tool.

Switch it off with `scotchos disable launcher`: the keybind stays but does nothing.

## Settings

`[launcher]` in `scotchos.conf`, also in the settings window. They only affect the YouTube search (`yt-open.sh` reads them on each search).

| Key | Default | What it does |
|---|---|---|
| `browser` | `brave --incognito --new-window` | The browser command; the URL is added at the end. Firefox: `firefox --private-window` |
| `browser_class` | `brave-browser` | The class of its windows in `hyprctl clients`, to tell when the new one has appeared. Firefox: `firefox` |
| `workspace` | `1` | The workspace it opens on; focus comes back to yours afterwards |

Which keyword picks which provider is in each provider file (`keywords`).

## Files in this folder

| File | What it does |
|---|---|
| `launcher.sh` | What the keybind runs. Exits if `launcher` is off, else `scotchos launcher` (toggle). |
| `Launcher.qml` | Loaded by `shell.qml` while `launcher` is on. The `launcher` IPC target, the provider list, and the window's loader. |
| `LauncherWindow.qml` | The window: chip, input, result rows, keys. Exists only while open. |
| `Provider.qml` | The shape of a provider (keywords, `search`, `fallback`). |
| `AppsProvider.qml` | Applications, from Quickshell's desktop entries. |
| `YouTubeProvider.qml` | The "Search YouTube" rows. |
| `CommandsProvider.qml` | ScotchOS commands and the on/off switches. |
| `yt-open.sh` | Opens the search (or the first video) in the browser on the `[launcher]` workspace, then restores focus. |
| `README.md` | This file. |

## Requirements

The versions are the ones this was built and tested with, on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The window, desktop entries, `execDetached` |
| Hyprland with **Lua config** | `hyprland` | 0.56.2 | The keybind, the focused monitor, `hyprctl dispatch 'hl.dsp.…'` in `yt-open.sh` |
| Brave | `brave-bin` | 1.97.59 | YouTube results (`--incognito --new-window`) |
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
hl.bind("SUPER + Y", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/tools/launcher/launcher.sh"), {
        description = "[Launcher|ScotchOS] launcher",
})
```

This replaced the old `SUPER + Y` YouTube search bind. HyDE's default binds don't use Super+Y (only Super+**Shift**+Y).

### 2. `~/.config/hypr/hyprland.lua`: workspace 1 pinned to the laptop screen

Above the workspace 2 and 3 rules (it was added for the old YouTube tool; `yt-open.sh` opens Brave on workspace 1):

```lua
hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })
```

### 3. Backup

The config before the bind change is `~/.config/hypr/hyprland.lua.bak-before-launcher`. Apply with `hyprctl reload`.

## Running it by hand

```bash
scotchos launcher          # toggle   (also: open, close)
~/Projects/ScotchOS/tools/launcher/launcher.sh
```

With `scotchos disable launcher` the script exits at once with 0 and opens nothing.

## Adapting

| What | Where | Current value |
|---|---|---|
| Keybind | `hyprland.lua` | see above |
| Where the box sits | `LauncherWindow.qml`, `card` (`y: parent.height * 0.2`, `width: 640`) | 20 % from the top, 640 px |
| Keywords | each provider's `keywords` | `>`/`sos`, `yt`/`youtube`, `app` |
| Order Tab steps through | `Launcher.qml`, `providers` | Commands, YouTube, Apps |
| Browser, window class, workspace | `[launcher]` in `scotchos.conf` (see Settings) | Brave, workspace 1 |
| Old-style config (`hyprland.conf`) | — | `bind = SUPER, Y, exec, <path>/launcher.sh`; in `yt-open.sh` use `hyprctl dispatch workspace N` |

**A new source** is one file: a `Provider { name; glyph; keywords; search: q => [rows] }` (copy `YouTubeProvider.qml`), then add it to the `providers` list in `Launcher.qml`. A row is `{ title, subtitle, glyph or iconName, run(), alt() }`.

## How it works

1. The keybind runs `launcher.sh`, which calls `scotchos launcher`, an IPC call to the one Quickshell process. `Launcher.qml` flips `open`, and a `LazyLoader` creates the window (and destroys it on close, so nothing runs while it's shut).
2. The window is a full-screen layer on the focused monitor (overlay layer, exclusive keyboard focus, a dimmed backdrop that closes on click) with the card inside.
3. Every keystroke recomputes `results`: a keyword or chip asks that one provider; plain text asks the providers marked `inDefault` (top five each), then appends every provider's `fallback` rows, which are never cut off.
4. The rows are a fixed set of nine delegates that show or hide, so typing doesn't create or destroy anything. App icons are decoded at 28 px.
5. Running a row calls its `run()`. Programs are started with `Quickshell.execDetached`, so they outlive the window.
6. YouTube: `yt-open.sh` URL-encodes the query, optionally fetches the first video id, reads `[launcher]` with `scotchos get`, focuses that workspace, starts the browser, waits for it to appear and returns to your workspace.

## Uninstall

To only switch it off: `scotchos disable launcher`. To remove it:

1. Remove the launcher bind from `~/.config/hypr/hyprland.lua` and `hyprctl reload`.
2. Delete this folder, its `LazyLoader` and import in `shell.qml`, the `launcher` line in `scotchos.conf`, its entry in `settings/SettingsWindow.qml`, and the `launcher` command in `bin/scotchos`.
