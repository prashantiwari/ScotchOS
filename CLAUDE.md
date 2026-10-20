# ScotchOS

Desktop widgets (Quickshell/QML) and keybind tools (shell scripts) for Hyprland on CachyOS + HyDE. Machine: i5-9300H, GTX 1650, laptop `eDP-1` (1280×720 logical) + `HDMI-A-1`. See `README.md` for what exists and how it's laid out.

## Architecture

- **One Quickshell process for every widget.** `shell.qml` (root) owns what's shared: wallbash colors, `scotchos.conf`, and `workspaceEmpty(screen)` / `anyEmpty`. Each widget is wrapped in a `LazyLoader { active: root.enabled("<key>") }`, so switching it off destroys it and stops its processes.
- **`common/DesktopWidget.qml`** is the base of every widget: `core` (the root), `section` (its conf section), re-exposed theme (`bg fg accent accentDim dim font`), `str(key, fallback, allowed)`, `num`, `flag`, `placeSetting(fallback)`, `marginX/Y`. Cards get the widget as `shell`, so `shell.bg` and `shell.<state>` both work.
- **`common/DesktopPanel.qml`** is the window: bottom layer, `mask: Region {}` (click-through), no keyboard focus, exclusive zone 0, anchored by `place`. Use one per screen in `Variants { model: Quickshell.screens }` with `visible: w.workspaceEmpty(modelData)`.
- **`settings/SettingsWindow.qml`** (`scotchos settings`): floating window, created only while open, that writes the conf through `root.setConf()`. Its `items` list must name every widget/tool and its settings.
- **Tools** (`tools/<name>/`) are scripts bound in `~/.config/hypr/hyprland.lua`. The first thing each one does is `"$dir/../../bin/scotchos" enabled <key> || exit 0`.
- **`scotchos.conf`**: INI with `[enabled]` first. A widget missing from `[enabled]` is off. The shell ignores a read with no `[enabled]` section (one caught mid-save), so always write it atomically (temp file + `mv`), as `bin/scotchos` does.

## Conventions

- Names: conf key lowercase (`nowplaying`), folder camelCase (`widgets/nowPlaying`), widget file `<Name>Widget.qml` (unique: the root imports every widget folder), layer namespace `scotchos-<key>`.
- Match the existing code: section comments `// ---- Title ----`, one comment line explaining *why*, `id: w` for the widget, card width 340 px, radius 18, `Qt.alpha(shell.bg, 0.78)` background, `Qt.alpha(shell.accent, 0.35)` border, JetBrainsMono Nerd Font.
- Paths to helper files: `Quickshell.shellDir + "/widgets/<folder>/<file>"`. Persistent state goes in `Quickshell.cacheDir` (note: its id depends on the shell path, so moving the repo resets it).
- Every widget and tool has a README with these sections: intro (what it shows), Settings (table of keys), Files in this folder, Requirements (table with package and tested version), Changes made to the system, Running it by hand, Adapting, How it works, Uninstall. Update the root README table and `scotchos.conf` comments too.

## Resource rules (this is a desktop that's always running)

- Nothing runs while nothing is shown: bind `Process.running` / `Timer.running` to `w.anyEmpty` (and the widget's own visibility).
- No continuous animations or easing on values that update every second: it keeps panels redrawing at 60 fps (~11 % of a core, measured on the ring gauges).
- Reuse delegates (fixed `Repeater` models), don't rebuild lists on each update. Decode images at display size (`sourceSize`).
- Prefer reading `/proc`, `/sys` or in-process libraries over spawning a command each tick.
- Check after a change: `scotchos status` (memory) and `top -p <pid>`. Today the one shell uses ~205 MB.

## Testing

- `scotchos restart`, then `scotchos log 2>&1 | grep -E 'WARN|ERROR'`. QML edits hot-reload on save; `stats.py` / `cava.conf` changes need a restart.
- Widgets only show on empty workspaces, and the user's screens usually have windows. To look at one: `hyprctl dispatch 'hl.dsp.focus({workspace = "9"})'`, `hyprctl layers -j` (look for `scotchos-*`), `grim -o <monitor> <scratchpad>/shot.png`, then focus the previous workspace again. Tell the user first; it moves their view.
- Hyprland uses the **Lua** config: dispatchers look like `hyprctl dispatch 'hl.dsp.focus({workspace = "N"})'`; binds show up in `hyprctl binds` as `__lua` callbacks.
- `pgrep -f <name>` also matches the shell running your own command; use `pgrep -x` or `pgrep -af` and read the output.
- Don't run `yt-search.sh` with the tool on: it opens rofi and Brave.

## System changes

Anything outside this folder (mainly `~/.config/hypr/hyprland.lua`): ask first, back up as `<file>.bak-before-<change>`, record it under "Changes made to the system" in the README, and `hyprctl reload`. HyDE templates are copied, not symlinked (HyDE skips symlinks).
