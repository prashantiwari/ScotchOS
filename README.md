# ScotchOS

Desktop widgets and small tools for Hyprland, built on CachyOS + Hyprland + HyDE. Every widget runs inside **one Quickshell process**, and each widget and tool is switched on or off in a single settings file.

| Name | Kind | What it is |
|---|---|---|
| [`dashboard`](widgets/systemDashboard/README.md) | Widget | System monitor card: CPU, RAM and temperature rings, 60 s graphs, GPU, top processes |
| [`nowplaying`](widgets/nowPlaying/README.md) | Widget | The current track (any MPRIS player) with album art, progress and a cava visualizer |
| [`quote`](widgets/hourlyQuote/README.md) | Widget | A new quote from the web every hour |
| [`claudeusage`](widgets/claudeUsage/README.md) | Widget | Claude plan usage: the 5-hour and 7-day limits with reset countdowns, fetched at login and every 30 min |
| [`settings`](settings/README.md) | Window | `scotchos settings`: a floating window to switch everything on and off and change positions, margins and the rest |
| [`launcher`](tools/launcher/README.md) | Tool | A Spotlight-style box: apps, YouTube search and ScotchOS commands in one input; Tab locks a keyword (`yt`, `>`) in as a chip |
| [`dailytheory`](tools/dailyTheoryClient/README.md) | Tool | **Daily Theory** in rofi: a window for a dailyTheory server, with short theories and their linked sources matched to your interests, a daily quota and history |
| [`reader`](tools/eReader/README.md) | Tool | **E-reader** in the app launcher: a minimalist reader for EPUB, MOBI, AZW3, FB2, TXT and Markdown in the theme's colors, with a cover library, pages or scroll, one column, full width or two pages side by side, a font picker, contents and fullscreen |

Widgets are cards drawn on the desktop (above the wallpaper, below windows) on every screen. They only appear on screens showing a workspace with no tiled windows, and are not drawn at all otherwise. They take their colors from HyDE's wallbash, so they follow your wallpaper and theme.

## Switching things on and off

[`scotchos.conf`](scotchos.conf) has an `[enabled]` section, then one section per widget with its settings. Save the file and the change applies right away: a widget switched off is unloaded, and its helper processes (`stats.py`, cava) stop.

```ini
[enabled]
dashboard  = yes
nowplaying = yes
quote      = no
claudeusage = yes
launcher   = yes
dailytheory = yes
reader     = yes

[dashboard]
layout   = square
position = auto
```

Or open the settings window, **ScotchOS Settings** in rofi or `scotchos settings` in a terminal: switches, a position picker and the other settings, saved to the file as you click ([more](settings/README.md)).

Or from a terminal:

```bash
scotchos list               # what's on and off
scotchos disable quote      # applies right away
scotchos enable quote
scotchos toggle nowplaying
scotchos settings           # the settings window
scotchos theory             # the dailyTheory window
scotchos reader             # the e-reader window
scotchos claude refresh     # fetch the Claude usage now
scotchos status             # running? memory use?
scotchos restart | log
scotchos doctor             # is every widget and tool wired in everywhere?
```

`scotchos toggle <name>` also works as a Hyprland bind.

## Layout

```
ScotchOS/
├── shell.qml           The Quickshell entry point: colors, settings, empty-workspace tracking, one LazyLoader per widget
├── scotchos.conf       All settings, and what's switched on
├── settings/         The settings window (scotchos settings)
├── common/             Shared QML: DesktopWidget (base for every widget), DesktopPanel (the desktop-layer window)
├── widgets/<name>/     One folder per widget: <Name>Widget.qml (state + panels), the card, helpers, README
├── tools/<name>/       Scripts started by keybinds or the app launcher; each checks its switch with `scotchos enabled <name>`
├── wallbash/           HyDE template that exports the colors the widgets use
├── bin/scotchos        The control command
└── install.sh          Setup on a new machine
```

## Install on a new machine

```bash
git clone https://github.com/prashantiwari/ScotchOS.git ~/Projects/ScotchOS
~/Projects/ScotchOS/install.sh
```

`install.sh` checks dependencies, copies the wallbash template into HyDE, links `scotchos` into `~/.local/bin`, adds **ScotchOS Settings** to the app launcher, and prints the Hyprland lines to add. It doesn't edit your Hyprland config.

## Hyprland

On this machine, `~/.config/hypr/hyprland.lua` has:

```lua
-- inside hl.on("hyprland.start", function() … end)
-- ScotchOS desktop widgets, all in one Quickshell process (switch them on/off in ScotchOS/scotchos.conf)
hl.exec_cmd("qs -n -d -p " .. projects .. "/ScotchOS")

-- Launcher (apps, YouTube search, ScotchOS commands)
hl.bind("SUPER + Y", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/tools/launcher/launcher.sh"), { … })
```

These replaced three separate `qs` lines, one per widget. The config before that change is saved as `~/.config/hypr/hyprland.lua.bak-before-scotchos-unify`. The tool also needs `hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })` (see its README).

## Resource use

One Quickshell process for every widget and tool uses about **260 MB** of RAM (four widgets and three tools on, right after a restart, 2026-10-21). Back when there were three widgets, one process held them in about 205 MB, while three separate processes used about **550 MB** together, because each one loaded its own copy of the Qt runtime and watched the colors and Hyprland events separately. Helper processes only run while needed: `stats.py` while the dashboard is visible, cava while music plays and the card is visible.

## Adding a widget or tool

See [`CLAUDE.md`](CLAUDE.md) for the conventions. In Claude Code, the `/new-widget` and `/new-tool` skills scaffold one. `scotchos doctor` checks that it's wired in everywhere it needs to be.
