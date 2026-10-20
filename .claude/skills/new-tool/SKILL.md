---
name: new-tool
description: Scaffold a new ScotchOS tool, a script started by a Hyprland keybind (launcher, picker, search box), with an on/off switch in scotchos.conf. Use when the user wants a keybind-triggered tool rather than an always-on desktop widget.
---

# New ScotchOS tool

Read `CLAUDE.md` first. The template is `tools/youtubeSearch/` (rofi prompt + script + rasi theme).

## 1. Settle the design

Ask: the keybind (check it's free in `hyprctl binds` and HyDE's `~/.local/share/hypr/lua/key_binds.lua`), what it does, and which apps it needs. Propose a conf key (lowercase) and folder (camelCase).

## 2. Files in `tools/<folder>/`

- `<name>.sh`, executable, starting with:

  ```bash
  #!/usr/bin/env bash
  # One line: what it does.
  dir="$(dirname "$(readlink -f "$0")")"

  # Switched off in scotchos.conf ([enabled] <key>): the bind does nothing.
  "$dir/../../bin/scotchos" enabled <key> || exit 0
  ```

  Settings: `"$dir/../../bin/scotchos" get <key> <setting> <default>` from a `[<key>]` section.
- A rofi theme `.rasi` if it uses rofi: import `~/.config/rofi/theme.rasi` for the wallbash colors, JetBrainsMono Nerd Font.
- `README.md` with the sections listed in `CLAUDE.md`, including the exact Hyprland lines.

## 3. Wire it in

- `scotchos.conf`: `<key> = yes   # description` under `[enabled]`.
- Root `README.md` table, and the bind lines printed by `install.sh`.
- `~/.config/hypr/hyprland.lua`: **ask first**, back up to `hyprland.lua.bak-before-<folder>`, add the `hl.bind(…)` with a `description`, `hyprctl reload`, check `hyprctl configerrors`.

## 4. Verify

`bash -n` the script; with the tool switched off it must exit at once without opening anything. Only run the enabled path if the user agrees (it opens windows). Then commit.
