# Keybinds

A window that lists every keybind Hyprland has loaded, and edits them. Open it with **Super + Ctrl + /**, from the launcher (**Edit keybinds**) or with `scotchos keybinds`.

The list on the left is every live bind (`hyprctl binds -j`) as key caps and a name, grouped by the first part of HyDE's `[Category|…]` tags. HyDE's binds show no tag; the others are marked `hyprland.lua` (your own), `changed` (edited here) or `off` (switched off here, struck through). Type to search the keys, names and commands; **↑ / ↓** walk the list.

Pick a bind and the editor on the right shows:

- **Keys**: the modifier buttons (Super, Ctrl, Alt, Shift) and the key. Type a key name (`T`, `slash`, `F5`, `Return`, `XF86AudioPlay`, `mouse:272`), or press **record** and then the key. Hyprland takes Super combos before they reach the window, so pick Super with its button and record only the key. If another bind is on the same keys, the editor says so; saving takes the keys over, and resetting this one gives them back.
- **Action**: a **command** to run, or a **lua** action (`hl.dsp.focus({workspace = 3})`, `hl.dsp.window.close()`). The editor fills it in from the bind's source line: a plain `exec_cmd("…")` shows as its command, anything else as Lua. A few HyDE binds call a function that only exists inside `key_binds.lua` (`move_window`, `cycle_fullscreen`). Those can't be copied: to change one, give it a command or a Lua action, or switch it off.
- **Name**: the group (`Launcher|Apps`) and what it does. Together they make the `description`, which HyDE's Super + / hint shows too.
- **Flags**: on the lock screen (`locked`), repeat while held (`repeating`), on key release (`release`). Other flags a bind has (`transparent`, `mouse`, …) are kept as they are.

The buttons are **save**, **switch off**, **reset** (to HyDE's or `hyprland.lua`'s bind) and **cancel**. A switched-off bind has **switch back on**. **new bind** in the header adds one.

Every save reloads Hyprland. If the reload reports a config error that wasn't there before, the change is undone and the error is shown at the bottom, so a broken action never leaves you without binds.

Switch it off with `scotchos disable keybinds`: the keybind stays but does nothing. The edits already saved keep working, because Hyprland loads them, not this window.

## Files in this folder

| File | What it does |
|---|---|
| `keybinds.sh` | What the keybind runs. Exits if `keybinds` is off, else `scotchos keybinds` (toggle). |
| `Keybinds.qml` | Loaded by `shell.qml` while `keybinds` is on. The `keybinds` IPC target and the window's loader. |
| `KeybindsWindow.qml` | The window: search, list, editor. Exists only while open, and runs `keybinds.py` when it opens and on each save. |
| `keybinds.py` | `list`: the live binds, each matched to its `hl.bind(…)` line in HyDE's `key_binds.lua` or your `hyprland.lua`, as JSON. `apply`: writes the edits and reloads Hyprland, rolling back on new errors. |
| `keys.js` | Key combos for the window: parsing, the canonical form (used to find clashes), a recorded key press as an xkb name, key cap labels. |
| `tests/test_keybinds.py` | Tests for `keybinds.py` on a small HyDE-style Lua file (`scotchos test`). |
| `tests/keys.test.mjs` | Tests for `keys.js` (`scotchos test`, needs node). |
| `README.md` | This file. |

Outside the repo:

| File | What it is |
|---|---|
| `~/.config/scotchos/keybinds.json` | Your edits, the window's source of truth: `{"binds": [{"was", "combo", "exec" or "lua", "description", "flags", "off"}]}` |
| `~/.config/hypr/scotchos-binds.lua` | Generated from it on every save, and loaded at the end of `hyprland.lua`. Don't edit it: the next save rewrites it. |

## Requirements

The versions are the ones this was built and tested with, on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The window, running `keybinds.py` |
| Hyprland with **Lua config** | `hyprland` | 0.56.2 | `hyprctl binds -j`, `reload`, `configerrors`; `hl.bind` / `hl.unbind` |
| HyDE | — | Lua config (2026) | `key_binds.lua` (the defaults read for each bind's action), `hyde.binds` (the registered combos `unbind` looks up) |
| Python 3 | `python` | 3.14.8 | `keybinds.py` |
| Node.js (tests only) | `nodejs` | 26.11.1 | `tests/keys.test.mjs` |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd` | — | Font and glyphs |

```bash
sudo pacman -S --needed quickshell hyprland python ttf-jetbrains-mono-nerd
```

## Changes made to the system

### 1. `~/.config/hypr/hyprland.lua`: keybind

After the launcher bind:

```lua
-- ScotchOS keybinds editor (see and change every bind)
hl.bind("SUPER + CTRL + slash", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/tools/keybinds/keybinds.sh"), {
        description = "[Launcher|ScotchOS] keybinds editor",
})
```

### 2. `~/.config/hypr/hyprland.lua`: loading the edits

At the very end of the file, so the edits override HyDE's binds and the ones above:

```lua
-- Binds changed in the ScotchOS keybinds window (Super + Ctrl + /), generated from ~/.config/scotchos/keybinds.json.
-- Keep this last, so they override HyDE's binds and the ones above. Delete it to drop them all.
local scotchos_binds = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/scotchos-binds.lua"
local scotchos_file = io.open(scotchos_binds, "r")
if scotchos_file then
	scotchos_file:close()
	dofile(scotchos_binds)
end
```

The loader uses `dofile` rather than `require`: `require` caches the module, so after the first load a reload could skip the file. Until that line is in `hyprland.lua` the window still lists the binds, but it can't save (the status line says so).

### 3. Backup

The config before both changes is `~/.config/hypr/hyprland.lua.bak-before-keybinds`. Apply with `hyprctl reload`.

## Running it by hand

```bash
scotchos keybinds          # toggle   (also: open, close)
~/Projects/ScotchOS/tools/keybinds/keybinds.sh
python3 ~/Projects/ScotchOS/tools/keybinds/keybinds.py list | jq '.binds[] | select(.origin != "hyde")'
python3 ~/Projects/ScotchOS/tools/keybinds/keybinds.py apply "$(cat ~/.config/scotchos/keybinds.json)"   # regenerate + reload
```

With `scotchos disable keybinds` the script exits at once with 0 and opens nothing.

## Adapting

| What | Where | Current value |
|---|---|---|
| Keybind | `hyprland.lua` | `SUPER + CTRL + slash` |
| Window size | `KeybindsWindow.qml`, `implicitWidth` / `implicitHeight` | 900 × 560 |
| Flags the editor shows | `KeybindsWindow.qml`, the FLAGS `Repeater` (the names `keybinds.py` writes are in `FLAGS`) | locked, repeating, release |
| Where HyDE's defaults are read from | `keybinds.py`, `HYDE_LUA` | `~/.local/share/hypr/lua/key_binds.lua` |
| Old-style config (`hyprland.conf`) | — | Not supported: the edits are Lua (`hl.bind` / `hl.unbind`) |

## How it works

1. The keybind runs `keybinds.sh`, which calls `scotchos keybinds`, an IPC call to the one Quickshell process. `Keybinds.qml` flips `open`, and a `LazyLoader` creates the window (and destroys it on close, so nothing runs while it's shut).
2. When the window opens, it runs `keybinds.py list`. That reads `hyprctl binds -j`, which has each bind's keys, flags and description but not its action: in the Lua config every action is a `__lua` callback. So it also reads the `hl.bind(…)` calls in HyDE's `key_binds.lua` and your `hyprland.lua`, skipping comments. It resolves `MOD`, `_apps` and the `_F = {…}` option tables, and matches each one to a live bind by the canonical combo (modifiers as a set, the key without case) and the description. Binds made in a `for i = 1, 10` loop are matched by the number in their description and the loop's range, which tells `SUPER + 3` (workspace 3) from `SUPER + KP_3` (workspace 13). An action can be copied when, once `MOD` and `_apps` are spelled out, it uses only `hl`, `hyde`, `os` and literals.
3. A save sends the whole edit list to `keybinds.py apply`. It checks each combo, writes `keybinds.json` and `scotchos-binds.lua` atomically, and runs `hyprctl reload`. If `hyprctl configerrors` then lists errors that weren't there before, it puts the old files back and reloads again.
4. `scotchos-binds.lua` first unbinds every combo an edit touches: the old place of a moved or switched-off bind, and the new keys. Then it binds the new ones. All the unbinds come before all the binds, so swapping two binds works. HyDE's bind wrapper records the exact string each bind was registered with (`hyde.binds._active`), and `hl.unbind` only matches that string, so `unbind()` looks it up by the canonical combo.
5. HyDE's own files are never written. Reset drops the edit, and HyDE's bind (or the one in `hyprland.lua`) comes back on the next reload.

## Uninstall

To only switch the window off: `scotchos disable keybinds` (your saved edits stay in effect). To remove it:

1. Remove the keybind and the loader lines from `~/.config/hypr/hyprland.lua` (or restore `hyprland.lua.bak-before-keybinds`), delete `~/.config/hypr/scotchos-binds.lua` and `~/.config/scotchos/keybinds.json`, and `hyprctl reload`. HyDE's binds are back as they were.
2. Delete this folder, its `LazyLoader` and import in `shell.qml`, the `keybinds` line in `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, its entry in `settings/SettingsWindow.qml`, the "Edit keybinds" row in `tools/launcher/CommandsProvider.qml`, and the `keybinds` command and test suite in `bin/scotchos`.
