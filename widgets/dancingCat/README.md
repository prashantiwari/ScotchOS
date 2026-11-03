# Dancing Cat

A 3D cat made of ASCII characters, dancing **on the desktop** of every screen in the same card style as the other widgets. It sits above the wallpaper and below your windows, never takes keyboard focus and lets clicks pass through. It only appears on screens whose current workspace has no tiled windows, and it stops when none of them do.

The dance is a 16-beat loop: paws in the air swaying side to side, disco pointing, then a full pirouette with its arms out. The header shows the tempo. The characters follow the wallbash text color, so the cat recolors with your wallpaper and theme.

## Settings

The `[dancingcat]` section of `~/.config/scotchos/scotchos.conf` (defaults in [`scotchos.default.conf`](../../scotchos.default.conf)); `dancingcat` under `[enabled]` switches it on and off. Save the file and the change applies right away, with no restart:

| Key | Values | Default |
|---|---|---|
| `position` | `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` | `bottom` |
| `margin_x`, `margin_y` | Gap in px from the edges the card touches | `20` / `20` |
| `bpm` | Tempo, 30 - 240. Six frames per beat, so 120 BPM draws 12 frames a second | `120` |

## Files in this folder

| File | What it does |
|---|---|
| `CatWidget.qml` | Reads `[dancingcat]`, steps through the frames, and creates one desktop-layer panel per screen. |
| `CatCard.qml` | The card: header and the current frame. |
| `make_frames.py` | The 3D model and the dance. Ray marches every frame to text and writes `frames.js`. Not used at runtime. |
| `frames.js` | The 96 baked frames (generated, about 100 KB). |
| `README.md` | This file. |

## Requirements

Built and tested on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The panel and playback |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | The characters (must be monospaced) and header icons |
| HyDE (optional) | — | — | `~/.cache/hyde/wallbash/scotchos.dcol` with the wallbash colors |
| Python + NumPy (only to re-bake) | `python`, `python-numpy` | 3.14.8, 2.5.4 | `make_frames.py`; not needed to run the widget |

## Changes made to the system

None of its own. The shell is started from `~/.config/hypr/hyprland.lua`; see the [main README](../../README.md#hyprland).

## Running it by hand

Part of the single ScotchOS shell (see the [main README](../../README.md)); it isn't started on its own.

```bash
scotchos disable dancingcat   # unload it (applies right away)
scotchos enable dancingcat    # load it again
python3 make_frames.py --preview 54   # print one frame in the terminal
python3 make_frames.py && scotchos restart   # re-bake after changing the model or the dance
```

Logs: `scotchos log`

## Adapting

| What | Where | Current value |
|---|---|---|
| The moves | `pose()` in `make_frames.py` | 16 beats: wave, point, pirouette |
| The cat's shape, stripes, face | `cat()` in `make_frames.py` | Standing tabby with light paws and belly |
| Characters, dark to bright | `RAMP` in `make_frames.py` | `.,:;~=+*oO#%@` |
| Light and camera | `LIGHT`, `CAM`, `VIEW_HEIGHT` in `make_frames.py` | Light from the upper left |
| Resolution | `COLS`, `ROWS` in `make_frames.py`, with the `Text` size in `CatCard.qml` | 62 x 26 |
| Character color | `color` on the frame's `Text` in `CatCard.qml` | Theme text color |

## How it works

1. **The model:** the cat is a set of signed distance functions (ellipsoids and tapered capsules) blended together. The limbs use two-bone joints between a shoulder or hip and a paw, so they bend as the paws move.
2. **The dance:** `pose(beat)` turns a beat number into joint positions, and the sections blend into each other so the loop has no jump.
3. **The picture:** one ray per character, marched until it hits the cat. The surface normal and a fixed light give a brightness, and the brightness picks a character from `RAMP`. The eyes are blank, and the stripes and light fur change the brightness. The render corrects for characters being about twice as tall as wide.
4. **Baking:** all of this runs once, in `make_frames.py`. At runtime no NumPy, helper process or ray marching runs on the desktop: each card holds one laid-out `Text` per frame and only shows the current one, because laying out the text again on every tick was the expensive part. `frames.js` has `.pragma library`, so all screens share one copy and re-baking needs a restart.
5. **Resource use:** the timer only runs while a screen shows an empty workspace. This is the one widget that animates all the time by design, so it costs more than the static cards; lower `bpm` to reduce it.

## Uninstall

1. Switch it off: `scotchos disable dancingcat`, or `dancingcat = no` in `scotchos.conf`. That alone unloads it.
2. To remove it for good: delete the `LazyLoader` holding `CatWidget` and its `import "widgets/dancingCat"` from `shell.qml`, its entry in `items` in `settings/SettingsWindow.qml`, its row in the root README, the `dancingcat` line under `[enabled]` and the `[dancingcat]` section from `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, then this folder.
