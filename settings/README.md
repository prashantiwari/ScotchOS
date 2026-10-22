# Settings window

A floating window to switch every widget and tool on and off and change their settings: position (a 3 × 3 grid shaped like the screen), margins, the dashboard layout, the quote interval, and so on. Each click is saved to `~/.config/scotchos/scotchos.conf` straight away, so the cards on the desktop move and change while you watch. The window floats, so the widgets on an otherwise empty workspace stay visible behind it.

Open it from **rofi** (or any app launcher): type `scotchos` or `settings` and pick **ScotchOS Settings**. Or from a terminal:

```bash
scotchos settings     # toggles it
```

Esc or closing the window (Super+Q, etc.) closes it too.

## Settings

It has none of its own and no switch in `[enabled]`: it's always available, and costs nothing while closed (it's only created when opened). What it shows for each widget and tool is the `items` list at the top of `SettingsWindow.qml`.

Besides the settings themselves, **reset** next to a setting's name, shown only when `scotchos.conf` has that key with a value different from the default. It removes the line (`removeConf` in `shell.qml`), so the widget's own fallback applies.

## Files in this folder

| File | What it does |
|---|---|
| `SettingsWindow.qml` | The window: the `items` list (what can be set), the sidebar with on/off switches, and the selected item's settings. |
| `Toggle.qml` | On/off switch. |
| `Choice.qml` | A row of buttons, one per option. |
| `PositionGrid.qml` | The 3 × 3 position picker (plus `auto` for the dashboard). |
| `Stepper.qml` | A number with − / + buttons; you can also type it and press Enter. |
| `Slider.qml` | A number on a track (drag or click), snapped to `step`; saved on each step while dragging, so the widget resizes live. |
| `Field.qml` | A line of text (a URL, a key), saved on Enter or when it loses focus; `secret` hides it while not being edited. |
| `Scrollbar.qml` | Thin draggable scrollbar for the sidebar list and the settings pane, shown only when they overflow. |
| `scotchos-settings.desktop` | The app launcher entry; `install.sh` copies it to `~/.local/share/applications/` with the real path in `Exec`. |
| `README.md` | This file. |

Writing the conf is done by `setConf()` in [`shell.qml`](../shell.qml).

## Requirements

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The window (`FloatingWindow`), `qs ipc` to open it |
| Hyprland | `hyprland` | 0.56.2 | Floats the window because it has a fixed size (min = max), no window rule needed |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and icons |

## Changes made to the system

- `~/.local/share/applications/scotchos-settings.desktop`: a copy of `scotchos-settings.desktop` with `@SCOTCHOS@` replaced by the full path to `bin/scotchos` (rofi may not have `~/.local/bin` in its PATH). It runs `scotchos settings open`, so launching it while the window is open doesn't close it. Re-run `install.sh` (or the `sed` line in it) if you move the repo.

To open it from a key, bind `scotchos settings` in `~/.config/hypr/hyprland.lua`, e.g.:

```lua
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/bin/scotchos settings"))
```

## Running it by hand

```bash
scotchos settings                                  # toggle
scotchos settings open                             # what the launcher entry runs
qs ipc -p ~/Projects/ScotchOS call settings open   # or open / close explicitly
```

QML changes hot-reload on save. Logs: `scotchos log`

## Adapting

| What | Where | Current value |
|---|---|---|
| Add a widget or tool, or a setting | `items` in `SettingsWindow.qml` | dashboard, nowplaying, quote, yt_search, dailytheory |
| Setting types | `type` in an item's `settings`: `choice` (with `options`), `position` (with `auto: true` to offer auto), `number` (`min`, `max`, `step`, `unit`), `flag`, `text` (`placeholder`, `secret: true` to hide it), `action` (a button with `text`; clicking it emits `action(<widget key>, <action>)` on the shell root, nothing is saved) | — |
| Window size | `implicitWidth` / `implicitHeight` in `SettingsWindow.qml` | 720 × 460 |

## How it works

1. **Opening:** `scotchos settings` runs `qs ipc call settings toggle`; the `IpcHandler` in `shell.qml` flips `settingsOpen`, and a `LazyLoader` creates or destroys the window. Closed, nothing of it exists.
2. **Reading:** the window shows `core.conf`, the same parsed settings the widgets use, with each setting's default when the key isn't in the file.
3. **Writing:** `setConf(section, key, value)` in `shell.qml` changes only the value on that line, so the alignment and `# comments` stay (a missing key is added after the section's last setting, a missing section at the end). The file is written atomically (`FileView.atomicWrites`: temp file + rename) and the new text is applied right away, so the widgets update on the same click. If the file on disk isn't the text the settings were last read from (a hand edit saved without an `[enabled]` section, so it wasn't applied), it doesn't write and logs a warning instead of overwriting the edit. A `#` starts a comment only at the start of a line or after a space, so a value can contain one (a URL's `#fragment`).
   `removeConf(section, key)` (reset) uses `Conf.remove` in `common/conf.js` with the same disk check; the section header stays even when it ends up empty.
4. **Floating:** the window's minimum and maximum size are equal, which Hyprland treats as a dialog and floats. Floating windows don't count when deciding whether a workspace is empty, so the widgets stay on screen.

## Uninstall

Delete `~/.local/share/applications/scotchos-settings.desktop`, this folder, the `import "settings"`, the `IpcHandler` and the `LazyLoader` holding `SettingsWindow` from `shell.qml`, and the `settings)` line from `bin/scotchos` and the "App launcher entry" lines from `install.sh`. `setConf()` in `shell.qml` can go too.
