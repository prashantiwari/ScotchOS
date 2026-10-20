# Now Playing

A music card drawn **on the desktop**, on the right side of **every screen**, in the same style as the [system dashboard](../systemDashboard/README.md). It sits above the wallpaper and below your windows, never takes keyboard focus, lets clicks pass through, and doesn't show up in Alt+Tab. It only appears on screens whose current workspace has no tiled windows: as soon as one opens there it's hidden and not drawn at all. Floating windows don't count, unless they're fullscreen.

It shows:

- **The track:** album art (or a music note when there's none), title, artist and album, and which app is playing it, with a ▶ or ⏸ for its state.
- **Progress:** a bar with the position and length. It hides itself for players that don't report a length, such as some live streams.
- **Visualizer:** 32 bars from cava that move with the sound. They go flat and faded when the music pauses.

## Where the music can come from

The track details come from **MPRIS**, the standard way Linux media apps report what they're playing over D-Bus. Anything that supports it works, with no setup:

| Source | Works? |
|---|---|
| Spotify desktop app | Yes |
| Spotify, Apple Music, YouTube, YouTube Music, SoundCloud in Brave / Chrome / Firefox | Yes, each playing tab reports itself |
| Apple Music | The web player in a browser, or the Cider app |
| Local files | VLC, Strawberry, Rhythmbox, Elisa, or mpv with `mpv-mpris` |

The **visualizer** is different: cava listens to the sound going to your speakers or headphones through PipeWire, so it reacts to *every* app, including games, calls and notification sounds, not only the player shown on the card.

Which player is shown: the one playing right now. When it pauses it stays on the card until another one starts playing or it closes. To see the players on your system, run `playerctl -l`.

## Settings

The `[nowplaying]` section of `~/.config/scotchos/scotchos.conf` (defaults in [`scotchos.default.conf`](../../scotchos.default.conf)); `nowplaying` under `[enabled]` switches it on and off. Save the file and the change applies right away, with no restart:

| Key | Values | Default |
|---|---|---|
| `position` | `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` | `right` |
| `margin_x`, `margin_y` | Gap in px from the edges the card touches | `20` / `20` |
| `show_paused` | `yes` keeps the card while paused, `no` shows it only while playing | `yes` |

When nothing is playing or paused (no player, or a player with no track), the card disappears.

## Files in this folder

| File | What it does |
|---|---|
| `NowPlayingWidget.qml` | Reads `[nowplaying]`, picks the player, runs cava, and creates one desktop-layer panel per screen. |
| `MediaCard.qml` | The card: header, album art, track details, progress bar and visualizer bars. |
| `cava.conf` | cava's settings: 32 bars, 30 frames per second, PipeWire input, raw text output. |
| `README.md` | This file. |

## Requirements

Built and tested on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The panel and its MPRIS support (`Quickshell.Services.Mpris`) |
| cava | `cava` | 1.0.0 | The visualizer. Without it the card still works, with flat bars. |
| PipeWire | `pipewire` | 1.6.9 | The audio cava listens to |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and the ♫ ▶ ⏸ icons |
| HyDE (optional) | — | — | `~/.cache/hyde/wallbash/scotchos.dcol` with the wallbash colors (needs [`wallbash/scotchos.dcol`](../../wallbash/scotchos.dcol) copied to `~/.config/hyde/wallbash/always/`) |

```bash
sudo pacman -S --needed quickshell cava
```

`playerctl` isn't needed; it's only handy for checking which players exist.

## Changes made to the system

None of its own. The shell is started from `~/.config/hypr/hyprland.lua`; see the [main README](../../README.md#hyprland).

## Running it by hand

Part of the single ScotchOS shell (see the [main README](../../README.md)); it isn't started on its own.

```bash
scotchos disable nowplaying   # unload it (applies right away)
scotchos enable nowplaying    # load it again
scotchos restart         # restart the whole shell, e.g. after changing `cava.conf`
```

QML changes show up as soon as you save. Logs: `scotchos log`

Changes to `cava.conf` also apply the next time cava starts, which is whenever music starts playing after a pause.

## Adapting

| What | Where | Current value |
|---|---|---|
| Number of bars | `bars` in `cava.conf` **and** `barCount` in `NowPlayingWidget.qml` (they must match) | 32 |
| Visualizer smoothness | `framerate` in `cava.conf` | 30 fps |
| Card width | `contentWidth` in `MediaCard.qml` | 340 px |
| Visualizer height | the `viz` row's `height` in `MediaCard.qml` | 56 px |
| Album art size | the `ClippingRectangle` in `MediaCard.qml` (`88`, also used for the text column's width) | 88 px |
| Transparency | `Qt.alpha(shell.bg, 0.78)` in `MediaCard.qml` | 78 % opaque |
| Which screens | `Variants { model: Quickshell.screens }` in `NowPlayingWidget.qml` | All screens |

## How it works

1. **Player and track:** `Quickshell.Services.Mpris` lists every MPRIS player. `NowPlayingWidget.qml` picks the one playing (or the last one that played) and binds the card to its `trackTitle`, `trackArtist`, `trackAlbum`, `trackArtUrl`, `position` and `length`. MPRIS doesn't push the position as it changes, so a timer asks for it once a second while something is playing.
2. **Album art:** loaded straight from the player's art URL. Browsers give a local temporary file, and Spotify gives an https link. It's decoded at 176 px, so a large cover doesn't sit in memory at full size.
3. **Visualizer:** `cava -p cava.conf` prints one line per frame with 32 numbers from 0 to 100, separated by `;`. `NowPlayingWidget.qml` reads them with a `SplitParser`, and the card's 32 bars (a fixed `Repeater`, so they're reused, not rebuilt) take their heights from them. cava runs **only while something is playing and the card is shown on at least one screen** (an empty workspace); on pause it's stopped and the bars drop flat, so an idle card costs nothing.
4. **Colors:** the same wallbash colors as the system dashboard, from `~/.cache/hyde/wallbash/scotchos.dcol`, so it recolors with your wallpaper and theme.
5. **Panel:** a layer-shell surface on the **bottom** layer, with an exclusive zone of `0` and an empty input `mask`, just like the dashboard. The window hides itself when there's nothing to show.

## Uninstall

1. Switch it off: `scotchos disable nowplaying`, or `nowplaying = no` in `scotchos.conf`. That alone unloads it.
2. To remove it for good: delete the `LazyLoader` holding `NowPlayingWidget` and its `import "widgets/nowPlaying"` from `shell.qml`, the `nowplaying` line under `[enabled]` and the `[nowplaying]` section from `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, then this folder.

