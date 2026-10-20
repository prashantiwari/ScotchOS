# System Dashboard

A system monitor panel drawn **on the desktop**, on the left side of **every screen**. It sits above the wallpaper and below your windows, so you see it on any empty workspace. It never takes keyboard focus, clicks go straight through it, and it doesn't show up in Alt+Tab. It only appears on screens whose current workspace has no tiled windows: as soon as one opens there it's hidden and not drawn at all. Floating windows don't count, unless they're fullscreen. `stats.py` is stopped while no screen shows the panel, and the history graphs start over when it reappears (so they never join samples from minutes apart).

It starts automatically when Hyprland starts and updates once per second:

- **Rings:** CPU usage (with average clock speed), RAM used / total, and CPU package temperature
- **Graphs:** the last 60 seconds of CPU usage, CPU temperature and network traffic (download and upload; the scale grows to fit the busiest second). Each graph has axis labels (top and bottom) on the left (%, °C, or K/M bytes per second) and the current value(s) next to its title, with a colored dot as the legend.
- **GPU:** the NVIDIA card's name, temperature, power draw, load (with graphics clock) and VRAM used / total. The section hides itself on a system without the NVIDIA driver.
- **Top processes:** the 3 busiest process names, as a share of the **whole** CPU (so on 8 threads one fully busy thread shows 12.5 %). Processes with the same name are added together, so all of Brave's processes count as one "brave".

## Settings

The `[dashboard]` section of `~/.config/scotchos/scotchos.conf` (defaults in [`scotchos.default.conf`](../../scotchos.default.conf)); `dashboard` under `[enabled]` switches it on and off. Save the file and the change applies right away, with no restart:

| Key | Values | Default |
|---|---|---|
| `layout` | `vertical`, `horizontal`, `square` (see below) | `vertical` |
| `position` | `auto`, `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` | `auto`: `left` for vertical and square, `bottom` for horizontal |
| `margin_x`, `margin_y` | Gap in px from the edges the card touches (a side it doesn't touch is centered) | `20` / `20` |

### Layouts

```ini
layout = vertical     # a tall card on the left edge, vertically centered (default)
layout = horizontal   # a wide strip along the bottom edge, centered, with the sections side by side
layout = square       # a squarish card on the left edge: rings on top, then two columns split by a divider line
```

In the square layout a clock sits beside the rings: the time in 24-hour format, with the day and date below it, the same height as the rings. Below that, the left column has CPU usage, CPU temperature and top processes, and the right column has the network graph (stretched to the height of the two CPU graphs) and the GPU.

All layouts show exactly the same things. The horizontal one is about 1220 px wide, so it fits a 1280 px (logical) screen. The square one is about 600 × 470 px. If the file is missing or the value isn't recognized, the vertical layout is used.

Temperatures are **green** below 60 °C, **amber** below 80 °C and **red** above. All other colors come from HyDE's wallbash, so the panel follows your wallpaper and theme changes without a restart.

## Files in this folder

| File | What it does |
|---|---|
| `DashboardWidget.qml` | Reads `[dashboard]`, runs `stats.py`, keeps the 60-second history, and creates one desktop-layer panel per screen. |
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
| HyDE (optional) | — | — | Provides `~/.cache/hyde/wallbash/scotchos.dcol` with the wallbash colors (needs [`wallbash/scotchos.dcol`](../../wallbash/scotchos.dcol) copied to `~/.config/hyde/wallbash/always/`) |

Install anything that's missing:

```bash
sudo pacman -S --needed hyprland quickshell python ttf-jetbrains-mono-nerd
```

`lm_sensors` isn't needed: the temperature is read straight from `/sys/class/hwmon`.

## Changes made to the system

None of its own. The shell is started from `~/.config/hypr/hyprland.lua`; see the [main README](../../README.md#hyprland).

## Running it by hand

Part of the single ScotchOS shell (see the [main README](../../README.md)); it isn't started on its own.

```bash
scotchos disable dashboard   # unload it (applies right away)
scotchos enable dashboard    # load it again
scotchos restart         # restart the whole shell, e.g. after changing `stats.py`
```

QML changes show up as soon as you save. Logs: `scotchos log`

Changes to `stats.py` need `scotchos restart` (or a disable / enable).

## Adapting to another system

| What | Where | Current value |
|---|---|---|
| CPU temperature sensor | `stats.py`, the `SENSORS` dict (the first one present is used) | `coretemp`, `k10temp`, `zenpower`, `cpu_thermal`. List yours with `cat /sys/class/hwmon/hwmon*/name`. If it isn't found, the ring shows `--`. |
| Temperature colors | `DashboardWidget.qml`, `tempColor()` | < 60 green, < 80 amber, else red |
| Temp ring range | `Dashboard.qml`, the TEMP `Ring` (`(t - 30) / 70`) and the temperature `Graph` (`min`/`max`) | 30–100 °C |
| Which screens | `DashboardWidget.qml`, `Variants { model: Quickshell.screens }` | All screens. To show it on one screen only, use `Quickshell.screens.filter(s => s.name === "HDMI-A-1")` |
| Layout | `scotchos.conf` `[dashboard]`, `layout` | `vertical` |
| Position | `scotchos.conf` `[dashboard]`, `position` (`top-left` … `bottom-right`, `center`, or `auto`) | `auto`: left edge for vertical and square, bottom edge for horizontal |
| Margins | `scotchos.conf` `[dashboard]`, `margin_x` / `margin_y` (px from the edges the card touches) | `20` / `20` |
| Size / transparency | `Dashboard.qml`: `sectionWidth`, `netWidth`, `graphHeight` and `Qt.alpha(shell.bg, 0.78)` | Vertical 300 px wide; horizontal ~1220 × 230 px; 78 % opaque |
| Colors without HyDE | the root `shell.qml`, the fallback values in `hex("dcol_…", "#…")` | A Catppuccin-like dark palette |

## How it works

1. `stats.py` runs as a child process of Quickshell and prints one JSON line per second:
   - **CPU usage** comes from the difference between two readings of `/proc/stat`, for the whole CPU. Idle time includes iowait.
   - **Clock speed** is the average of `scaling_cur_freq` across all threads.
   - **RAM used** is `MemTotal − MemAvailable` from `/proc/meminfo`, the same figure `free` and btop report.
   - **Network** is the change in received / sent bytes in `/proc/net/dev`, summed over **physical** interfaces only (those with `/sys/class/net/<name>/device`, here `wlan0` and `enp7s0`), so Docker bridges and VPN tunnels aren't counted twice.
   - **Top processes** come from the change in `utime + stime` in each `/proc/<pid>/stat`, every 3 seconds.
   - **GPU** stats come from NVML (`libnvidia-ml.so.1`, the library `nvidia-smi` itself uses), called in-process through `ctypes`. That's much cheaper than starting `nvidia-smi` every second. Load, temperature and VRAM are read every 2 seconds, and power and clock every 10 seconds, because the power query alone costs about 10 ms. While the card is runtime-suspended (`/sys/bus/pci/devices/<gpu>/power/runtime_status` is `suspended`, on Optimus laptops), NVML isn't called at all and the section shows **asleep**: a query would wake the card. NVML is only opened once the card is awake.
   - **CPU temperature** comes from `/sys/class/hwmon`. The sensor is looked up **by name** each second, because the `hwmonN` numbers can change between boots.
2. `DashboardWidget.qml` reads those lines with a `SplitParser`, keeps the last 60 CPU, temperature and network values, and restarts the collector if it exits while the card is shown: after 2 s, doubling up to 64 s while it keeps crashing (a run of over a minute resets the delay).
3. The colors come from `~/.cache/hyde/wallbash/scotchos.dcol`, using `dcol_pry1` for the background, `dcol_txt1` for text and `dcol_1xa7`/`dcol_1xa3` for the accent and track. HyDE writes that file from the [`scotchos.dcol`](../../wallbash/scotchos.dcol) template on every wallpaper, theme or wallbash-mode change, so it always holds the colors HyDE actually applied. Quickshell watches it, so the panel recolors right away. (It does not use `~/.cache/hyde/wall.dcol`: that is a symlink HyDE re-points on each wallpaper change, which file watchers never see, and it holds the raw wallpaper colors whatever the wallbash mode.)
4. Each panel is a layer-shell surface on the **bottom** layer. HyDE's wallpaper daemon (awww) draws on the background layer below it, and normal windows draw above it. It uses an exclusive zone of `0`, so it stays clear of waybar without reserving screen space, and an empty input `mask` so clicks pass through.

**Note:** on this laptop the NVIDIA driver's Runtime D3 power saving is disabled (see `/proc/driver/nvidia/gpus/*/power`), so the card is always powered on and the "asleep" path has only been checked by reading the code. With Runtime D3 on, the queries are skipped while the card sleeps, but they still run every 2 seconds while it's awake, so they can delay it going back to sleep; raise `GPU_EVERY` in `stats.py` if that matters. The laptop doesn't report fan speed to Linux, so fans aren't shown.

## Resource use

Measured on the i5-9300H with a panel on each of 2 screens: about **2–3 % of one CPU core** for Quickshell and **~0.8 %** for `stats.py`, so around 0.4 % of the whole 8-thread CPU, with about 200 MB of RAM for Quickshell (mostly the Qt runtime) and 40 MB for `stats.py`. The slower readings run less often than once a second to keep this low, with intervals set at the top of `stats.py` (`PROC_EVERY`, `GPU_EVERY`, `POWER_EVERY`). The top-processes rows are reused rather than rebuilt on each update. The rings deliberately don't animate: easing them after every update kept the panels redrawing at 60 fps and cost about 11 % of a core.

## Uninstall

1. Switch it off: `scotchos disable dashboard`, or `dashboard = no` in `scotchos.conf`. That alone unloads it.
2. To remove it for good: delete the `LazyLoader` holding `DashboardWidget` and its `import "widgets/systemDashboard"` from `shell.qml`, the `dashboard` line under `[enabled]` and the `[dashboard]` section from `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, then this folder.

