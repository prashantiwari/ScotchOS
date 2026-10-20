# YouTube Search Box

Press **Super + Y** and a search bar opens in the middle of the screen. Type a query and press **Enter**. Brave opens a **private window** with the YouTube results, on **workspace 1** (the laptop screen). Focus then goes back to the workspace you were on.

- **Shift + Enter** skips the results page and opens the **first video** directly. If the video can't be found (offline, or YouTube changed its page layout), the results page opens instead.
- **Esc** closes the bar without searching.
- **Enter** with an empty query does nothing.
- **Super + Y** again while the bar is open closes it.

Switch it off with `scotchos disable yt_search` (or `yt_search = no` under `[enabled]` in [`scotchos.conf`](../../scotchos.conf)): the bind stays but does nothing.

## Files in this folder

| File | What it does |
|---|---|
| `yt-search.sh` | Exits if `yt_search` is off, then shows the rofi prompt, URL-encodes the query, looks up the first video on Shift+Enter, opens Brave on workspace 1, then restores focus. |
| `yt-search.rasi` | Rofi theme: a single input line (no result list), centered, 600px wide, with rounded corners. Imports the wallbash colors from HyDE. |
| `README.md` | This file. |

## Requirements

The versions are the ones this was built and tested with, on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Hyprland with **Lua config** | `hyprland` | 0.56.2 | The keybind and the `hyprctl dispatch 'hl.dsp.…'` focus calls |
| rofi 2.x (native Wayland) | `rofi` | 2.0.0 | The floating search bar |
| Brave | `brave-bin` | 1.97.59 | The browser (`--incognito --new-window`) |
| jq | `jq` | 1.8.2 | Reading `hyprctl … -j` JSON |
| Python 3 | `python` | 3.14 | URL-encoding the query |
| curl | `curl` | 8.23.0 | Fetching the results page to find the first video (Shift+Enter) |
| setsid | `util-linux` | 2.42 | Detaching Brave from the script |
| pkill | `procps-ng` | 4.0.7 | Toggling the bar closed |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy in `~/.local/share/fonts` | — | Font and the YouTube icon (U+F16A) in the prompt |
| HyDE (optional) | — | — | Provides `~/.config/rofi/theme.rasi` with the wallbash colors |

Install anything that's missing:

```bash
sudo pacman -S --needed hyprland rofi jq python curl util-linux procps-ng ttf-jetbrains-mono-nerd
paru -S brave-bin   # or: yay -S brave-bin
```

## Changes made to the system

### 1. `~/.config/hypr/hyprland.lua`: keybind

Added after the "Application Launcher" bind:

```lua
-- YouTube search (Brave private window)
hl.bind("SUPER + Y", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/tools/youtubeSearch/yt-search.sh"), {
        description = "[Launcher|Rofi menus] youtube search in brave private window",
})
```

HyDE's default binds (`~/.local/share/hypr/lua/key_binds.lua`) don't use Super+Y; only Super+**Shift**+Y is taken.

### 2. `~/.config/hypr/hyprland.lua`: workspace 1 pinned to the laptop screen

Added above the existing workspace 2 and 3 rules:

```lua
hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })
```

Without this rule, workspace 1 is only on the laptop by default, and it can move to another monitor when displays are replugged.

### 3. Backup

The original config was saved as `~/.config/hypr/hyprland.lua.bak-before-ytsearch` before any edits.

Apply the changes with:

```bash
hyprctl reload
```

## Adapting to another system

Check or change these values when using this on a different machine:

| What | Where | Current value |
|---|---|---|
| Path to the script | The `hl.bind` line in `hyprland.lua` | `~/Projects/ScotchOS/tools/youtubeSearch/yt-search.sh` (update it if you move the folder) |
| Laptop monitor name | The `hl.workspace_rule` line | `eDP-1`. Find yours with `hyprctl monitors` |
| Target workspace | `yt-search.sh`, the `hl.dsp.focus({workspace = "1"})` line | `1` |
| Brave command / window class | `yt-search.sh`: `brave` and `select(.class == "brave-browser")` | `brave`, `brave-browser`. Check the class with `hyprctl clients` |
| Colors | `yt-search.rasi`: `@import "~/.config/rofi/theme.rasi"` | Needs HyDE. **Without HyDE**, remove the `@import` line and define `main-bg`, `main-fg`, `main-br` and `main-ex` in a `* { … }` block |
| Font | `yt-search.rasi`, the `configuration { font: … }` line | `JetBrainsMono Nerd Font 12` |
| Old-style config (`hyprland.conf`, not Lua) | — | Use `bind = SUPER, Y, exec, <path>/yt-search.sh` and `workspace = 1, monitor:eDP-1`. In the script, replace both `hyprctl dispatch 'hl.dsp.focus({workspace = "N"})'` calls with `hyprctl dispatch workspace N` |

Make sure the script is executable:

```bash
chmod +x yt-search.sh
```

## How it works

1. `rofi -dmenu` with no input lines serves as a plain text prompt. Shift+Return is bound to `kb-custom-1` (its default `kb-accept-alt` binding is cleared), so rofi exits with code 10 instead of 0 and the script knows to play the first video.
2. The query is URL-encoded with Python's `urllib.parse.quote_plus`, so `c++ & rust`, `#tags` and non-ASCII text are handled correctly.
   - On Shift+Enter, `curl` downloads the results page with the "Type: Video" filter (`sp=EgIQAQ%3D%3D`) and takes the first `"videoRenderer":{"videoId":"…"}`. Ads and Shorts use other renderer names, so they're skipped. The URL becomes `https://www.youtube.com/watch?v=<id>`. This takes about one second.
3. The script records the current workspace (`hyprctl activeworkspace -j`) and the existing Brave window addresses.
4. It focuses workspace 1 and starts `brave --incognito --new-window <url>` (detached with `setsid`).
   - Hyprland exec rules like `[workspace 1]` don't work here. Brave is usually already running, so the new process hands the URL to the running browser and exits, and the window belongs to a different process.
   - Focusing the target workspace first works, because new windows open on the focused workspace.
5. It waits up to 5 seconds for a new `brave-browser` window to show up, then focuses the original workspace again.

**Caveat:** if the workspace you started from is on the laptop screen too, returning to it hides workspace 1. The Brave window is still there; switch to workspace 1 to see it.

## Uninstall

To only switch it off, `scotchos disable yt_search` is enough. To remove it:

1. Remove the `SUPER + Y` bind and the workspace 1 rule from `~/.config/hypr/hyprland.lua`. Alternatively, restore the backup, but only if you haven't made other edits since then.
2. Run `hyprctl reload`.
3. Delete this folder.
