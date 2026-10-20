# System Dashboard

A system monitor panel drawn **on the desktop**, on the left side of **every screen**. It sits above the wallpaper and below your windows, so you see it on any empty workspace. It never takes keyboard focus, clicks go straight through it, and it doesn't show up in Alt+Tab. It only appears on screens whose current workspace has no tiled windows: as soon as one opens there it's hidden and not drawn at all. Floating windows don't count, unless they're fullscreen. `stats.py` is stopped while no screen shows the panel, so the history graphs pick up again from where they left off when it reappears.

It starts automatically when Hyprland starts and updates once per second:

- **Rings:** CPU usage (with average clock speed), RAM used / total, and CPU package temperature
- **Graphs:** the last 60 seconds of CPU usage, CPU temperature and network traffic (download and upload; the scale grows to fit the busiest second). Each graph has axis labels (top and bottom) on the left (%, °C, or K/M bytes per second) and the current value(s) next to its title, with a colored dot as the legend.
- **GPU:** the NVIDIA card's name, temperature, power draw, load (with graphics clock) and VRAM used / total. The section hides itself on a system without the NVIDIA driver.
- **Top processes:** the 3 busiest process names, as a share of the **whole** CPU (so on 8 threads one fully busy thread shows 12.5 %). Processes with the same name are added together, so all of Brave's processes count as one "brave".

## Layout

`dashboard.conf` picks one of three layouts. Save the file and the panels switch right away, with no restart:

```ini
layout = vertical     # a tall card on the left edge, vertically centered (default)
layout = horizontal   # a wide strip along the bottom edge, centered, with the sections side by side
layout = square       # a squarish card on the left edge: rings on top, then two columns split by a divider line
```

In the square layout a clock sits beside the rings: the time in 24-hour format, with the day and date below it, the same height as the rings. Below that, the left column has CPU usage, CPU temperature and top processes, and the right column has the network graph (stretched to the height of the two CPU graphs) and the GPU.

All layouts show exactly the same things. The horizontal one is about 1220 px wide, so it fits a 1280 px (logical) screen. The square one is about 600 × 470 px. If the file is missing or the value isn't recognized, the vertical layout is used.

The same file sets where the card sits: `position` takes one of nine spots (`top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`) or `auto`. `margin_x` and `margin_y` set the gap in px from the edges the card touches. Any side the card doesn't touch is centered.

Temperatures are **green** below 60 °C, **amber** below 80 °C and **red** above. All other colors come from HyDE's wallbash, so the panel follows your wallpaper and theme changes without a restart.

## Files in this folder

| File | What it does |
|---|---|
| `dashboard.conf` | Settings: layout, position and margins. |
| `shell.qml` | Entry point. Loads the wallbash colors and `dashboard.conf`, runs `stats.py`, keeps the 60-second history, and creates one desktop-layer panel per screen. |
| `Dashboard.qml` | The card: header, rings, graphs, GPU and top processes, stacked (vertical), side by side (horizontal) or in two columns (square). The `cells` table says where each section goes in each layout. |
| `Ring.qml` | The circular gauge component. |
| `Graph.qml` | The history graph component (one or two lines with a gradient fill, fixed or auto scale). |
| `stats.py` | Reads `/proc` and `/sys` and prints one JSON line of stats per second. Talks to the NVIDIA driver through NVML. |
| `README.md` | This file. |

## Requirements

The versions are the ones this was built and tested with, on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Hyprland with **Lua config** | `hyprland` | 0.56.2 | The autostart line |
| Quickshell | `quickshell` | 0.3.2 | Drawing the panel on the Wayland layer-shell |
| Python 3 | `python` | 3.14 | `stats.py` (standard library only) |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy in `~/.local/share/fonts` | — | Font and the chip icon (U+F2DB) in the header |
| NVIDIA driver (optional) | `nvidia-open` or `nvidia` (provides `libnvidia-ml.so.1`) | 615.78.08 | The GPU section |
| HyDE (optional) | — | — | Provides `~/.cache/hyde/wallbash/scotchos.dcol` with the wallbash colors (needs [`wallbash/scotchos.dcol`](../wallbash/scotchos.dcol) copied to `~/.config/hyde/wallbash/always/`) |

Install anything that's missing:

```bash
sudo pacman -S --needed hyprland quickshell python ttf-jetbrains-mono-nerd
```

`lm_sensors` isn't needed: the temperature is read straight from `/sys/class/hwmon`.

## Changes made to the system

### 1. `~/.config/hypr/hyprland.lua`: autostart

Added at the top of the existing `hl.on("hyprland.start", …)` block:

```lua
-- ScotchOS system dashboard (desktop layer, left side of every screen)
hl.exec_cmd("qs -n -d -p " .. projects .. "/ScotchOS/systemDashboard")
```

`-n` stops a second copy from starting, and `-d` detaches it from Hyprland.

### 2. Backup

The original config was saved as `~/.config/hypr/hyprland.lua.bak-before-dashboard` before the edit.

## Running it by hand

```bash
qs -n -d -p ~/Projects/ScotchOS/systemDashboard   # start
qs kill -p ~/Projects/ScotchOS/systemDashboard    # stop
```

Quickshell reloads the QML files on its own when you save them, so changes to the layout show up immediately. Changes to `stats.py` need a stop and start.

Logs: `qs log -p ~/Projects/ScotchOS/systemDashboard`

## Adapting to another system

| What | Where | Current value |
|---|---|---|
| CPU temperature sensor | `stats.py`, the `SENSORS` dict | `coretemp`. List yours with `cat /sys/class/hwmon/hwmon*/name`. If it isn't found, the ring shows `--`. |
| Temperature colors | `shell.qml`, `tempColor()` | < 60 green, < 80 amber, else red |
| Temp ring range | `Dashboard.qml`, the TEMP `Ring` (`(t - 30) / 70`) and the temperature `Graph` (`min`/`max`) | 30–100 °C |
| Which screens | `shell.qml`, `Variants { model: Quickshell.screens }` | All screens. To show it on one screen only, use `Quickshell.screens.filter(s => s.name === "HDMI-A-1")` |
| Layout | `dashboard.conf`, `layout` | `vertical` |
| Position | `dashboard.conf`, `position` (`top-left` … `bottom-right`, `center`, or `auto`) | `auto`: left edge for vertical and square, bottom edge for horizontal |
| Margins | `dashboard.conf`, `margin_x` / `margin_y` (px from the edges the card touches) | `20` / `20` |
| Size / transparency | `Dashboard.qml`: `sectionWidth`, `netWidth`, `graphHeight` and `Qt.alpha(shell.bg, 0.78)` | Vertical 300 px wide; horizontal ~1220 × 230 px; 78 % opaque |
| Colors without HyDE | `shell.qml`, the fallback values in `hex("dcol_…", "#…")` | A Catppuccin-like dark palette |
| Old-style config (`hyprland.conf`, not Lua) | — | `exec-once = qs -n -d -p ~/Projects/ScotchOS/systemDashboard` |

## How it works

1. `stats.py` runs as a child process of Quickshell and prints one JSON line per second:
   - **CPU usage** comes from the difference between two readings of `/proc/stat`, for the whole CPU. Idle time includes iowait.
   - **Clock speed** is the average of `scaling_cur_freq` across all threads.
   - **RAM used** is `MemTotal − MemAvailable` from `/proc/meminfo`, the same figure `free` and btop report.
   - **Network** is the change in received / sent bytes in `/proc/net/dev`, summed over **physical** interfaces only (those with `/sys/class/net/<name>/device`, here `wlan0` and `enp7s0`), so Docker bridges and VPN tunnels aren't counted twice.
   - **Top processes** come from the change in `utime + stime` in each `/proc/<pid>/stat`, every 3 seconds.
   - **GPU** stats come from NVML (`libnvidia-ml.so.1`, the library `nvidia-smi` itself uses), called in-process through `ctypes`. That's much cheaper than starting `nvidia-smi` every second. Load, temperature and VRAM are read every 2 seconds, and power and clock every 10 seconds, because the power query alone costs about 10 ms.
   - **CPU temperature** comes from `/sys/class/hwmon`. The sensor is looked up **by name** each second, because the `hwmonN` numbers can change between boots.
2. `shell.qml` reads those lines with a `SplitParser`, keeps the last 60 CPU, temperature and network values, and restarts the collector if it ever exits.
3. The colors come from `~/.cache/hyde/wallbash/scotchos.dcol`, using `dcol_pry1` for the background, `dcol_txt1` for text and `dcol_1xa7`/`dcol_1xa3` for the accent and track. HyDE writes that file from the [`scotchos.dcol`](../wallbash/scotchos.dcol) template on every wallpaper, theme or wallbash-mode change, so it always holds the colors HyDE actually applied. Quickshell watches it, so the panel recolors right away. (It does not use `~/.cache/hyde/wall.dcol`: that is a symlink HyDE re-points on each wallpaper change, which file watchers never see, and it holds the raw wallpaper colors whatever the wallbash mode.)
4. Each panel is a layer-shell surface on the **bottom** layer. HyDE's wallpaper daemon (awww) draws on the background layer below it, and normal windows draw above it. It uses an exclusive zone of `0`, so it stays clear of waybar without reserving screen space, and an empty input `mask` so clicks pass through.

**Note:** on this laptop the NVIDIA driver's Runtime D3 power saving is disabled (see `/proc/driver/nvidia/gpus/*/power`), so the card is always powered on and reading it doesn't stop it from sleeping. If you enable Runtime D3 later, the once-every-2-seconds NVML queries would keep the card awake. In that case, remove the GPU section or raise `GPU_EVERY` in `stats.py`. The laptop doesn't report fan speed to Linux, so fans aren't shown.

## Resource use

Measured on the i5-9300H with a panel on each of 2 screens: about **2–3 % of one CPU core** for Quickshell and **~0.8 %** for `stats.py`, so around 0.4 % of the whole 8-thread CPU, with about 200 MB of RAM for Quickshell (mostly the Qt runtime) and 40 MB for `stats.py`. The slower readings run less often than once a second to keep this low, with intervals set at the top of `stats.py` (`PROC_EVERY`, `GPU_EVERY`, `POWER_EVERY`). The top-processes rows are reused rather than rebuilt on each update. The rings deliberately don't animate: easing them after every update kept the panels redrawing at 60 fps and cost about 11 % of a core.

## Uninstall

1. Stop it: `qs kill -p ~/Projects/ScotchOS/systemDashboard`
2. Remove the two dashboard lines from the `hyprland.start` block in `~/.config/hypr/hyprland.lua`. Alternatively, restore the backup, but only if you haven't made other edits since then.
3. Delete this folder.
