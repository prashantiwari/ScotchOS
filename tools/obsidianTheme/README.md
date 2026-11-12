# Obsidian theme

Obsidian in the ScotchOS look, in HyDE's wallbash colors: the panes are the widgets' cards (the background at 78 %, a thin accent border, radius 18) floating over HyDE's blurred wallpaper. Headings, inline titles and section titles are in the accent and JetBrainsMono Nerd Font, and so are the interface and code, while note text keeps a proportional font. Links, tags, checkboxes, callouts, selections and scrollbars are tinted with the accent. Dialogs, menus, the command palette and the status bar are cards too.

It's a CSS snippet named `scotchos`, put into every vault. HyDE writes it again on every wallpaper or theme change, and Obsidian reloads a changed snippet right away, so Obsidian changes color along with the desktop. The colors are set for both of Obsidian's modes, so Obsidian follows HyDE's dark/light, whatever its own setting says.

There are two switches:

- **ScotchOS** (`scotchos disable obsidian`, or the settings window): takes the snippet out of every vault, and Obsidian goes back to its own look. `enable` puts it back. Both apply right away.
- **Obsidian**, per vault: Settings → Appearance → CSS snippets → `scotchos`.

The first time the snippet goes into a vault that's **open** in Obsidian, it's added to the vault's enabled snippets on disk, but Obsidian only reads that list when it opens a vault. Press **Ctrl + R** once (or flip the switch in Settings → Appearance). After that, wallpaper changes and the ScotchOS switch show at once. A vault that isn't open applies it when it opens.

## Settings

`[obsidian]` in `~/.config/scotchos/scotchos.conf`, or **Obsidian theme** in the settings window. A change applies right away.

| Key | Values | Default | What it does |
|---|---|---|---|
| `vaults` | `auto` / paths, comma-separated | `auto` | `auto`: every vault in `~/.config/obsidian/obsidian.json`. Paths can start with `~`. A vault taken off the list keeps its last snippet; switch it off there or delete the file. |
| `wallpaper` | `yes` / `no` | `yes` | HyDE's blurred wallpaper (`~/.cache/hyde/wall.blur`) behind the panes, the panes see-through. `no`: a solid background, the panes slightly tinted with the accent. |
| `mono_text` | `yes` / `no` | `no` | JetBrainsMono for note text too. |

## Files in this folder

| File | What it does |
|---|---|
| `obsidian.dcol` | The HyDE wallbash template: the CSS, with `<wallbash_…>` colors HyDE fills in. Its first line tells HyDE to write `~/.cache/hyde/wallbash/obsidian.css` and then run `obsidian-theme.sh sync`. |
| `obsidian-theme.sh` | `sync`: fills in the settings and copies the CSS into each vault, or removes it there when the switch is off. `render`: refreshes HyDE's copy of the template and has HyDE render it now (then HyDE runs `sync`). |
| `README.md` | This file. |

## Requirements

The versions are the ones this was built and tested with, on CachyOS + Hyprland + HyDE.

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Obsidian | `obsidian` | 1.15.0 | — |
| HyDE | — | 2026 (wallbash with `always/` templates) | Colors, rendering the template, `wall.blur` |
| jq | `jq` | 1.8.2 | Reading `obsidian.json`, adding the snippet to `appearance.json` |
| Quickshell | `quickshell` | 0.3.2 | Running `render` when the switch or a setting changes |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd` | — | Interface, headings, code |

```bash
sudo pacman -S --needed obsidian jq ttf-jetbrains-mono-nerd
```

## Changes made to the system

1. **`~/.config/hyde/wallbash/always/obsidian.dcol`**: a copy of `obsidian.dcol` with `@DIR@` replaced by this folder (HyDE skips symlinked templates). `install.sh` and every `render` write it, so it stays current with the repo.
2. **`~/.cache/hyde/wallbash/obsidian.css`**: what HyDE renders from it.
3. **In each vault**, in `.obsidian/`:
   - `snippets/scotchos.css`: the snippet. Its first line is `/* scotchos-obsidian-theme`; a `scotchos.css` without that line is someone's own and is never touched.
   - `snippets/.gitignore`: `scotchos.css` and itself, so a vault that's a git repo doesn't see a change on every wallpaper change. Only written if the folder has no `.gitignore`.
   - `appearance.json`: `"scotchos"` added to `enabledCssSnippets`, once, when the snippet first goes into the vault. Switching off leaves it there (it does nothing without the file), so switching back on applies without a reload.

Nothing in Hyprland changes: `render` runs HyDE's `color.set.sh` without the Hyprland signature, which skips the `hyprctl reload` it does on exit.

## Running it by hand

```bash
~/Projects/ScotchOS/tools/obsidianTheme/obsidian-theme.sh render   # render now and copy (or remove, when off)
~/Projects/ScotchOS/tools/obsidianTheme/obsidian-theme.sh sync     # copy HyDE's last render again
scotchos disable obsidian                                           # out of every vault, right away
scotchos enable obsidian
```

## Adapting

| What | Where | Current value |
|---|---|---|
| Colors | `obsidian.dcol`, the `--sc-*` variables | `pry1` background, `txt1` text, `1xa7` accent, `1xa8` hover |
| Card see-through | `obsidian-theme.sh`, `--sc-pane` in the wallpaper rule | 78 % |
| Card tint without the wallpaper | `obsidian.dcol`, `--sc-card` | 8 % accent |
| Radius | `obsidian.dcol`, `--radius-l` and the card rules | 18 px (panes, dialogs), 10 px (tabs, menus) |
| Fonts | `obsidian.dcol`, `--sc-font`, `--h1-font` … | JetBrainsMono Nerd Font |
| Snippet name | `obsidian-theme.sh`, `name` | `scotchos` |

Obsidian's own settings (accent color, font choices, light/dark) are overridden by the snippet while it's on. A community theme can be used under it; the snippet's colors win.

## How it works

1. On a wallpaper or theme change HyDE renders every template in `~/.config/hyde/wallbash/always/`, filling in the colors it picked (after its dark/light handling), writes `obsidian.css` and runs the command on the template's first line: `obsidian-theme.sh sync`.
2. `sync` checks `[enabled] obsidian`. On: it puts the blurred wallpaper in as a `data:` URL (snippets can't load files from disk) and the `mono_text` rule, then writes the result atomically to each vault's `snippets/scotchos.css`. Obsidian watches that folder and reloads the snippet. Off: it deletes the file, and Obsidian drops the styles.
3. The settings live in the conf, so the shell watches them: `shell.qml` runs `obsidian-theme.sh render` whenever `[enabled] obsidian` or `[obsidian]` changes, and once at start.
4. Inside a pane, Obsidian paints things in `--background-primary`; there it's made transparent, so the pane's card color (or the wallpaper through it) shows. Outside the panes, in dialogs and menus, it stays a solid card color.

## Uninstall

To only switch it off: `scotchos disable obsidian`. To remove it:

1. `scotchos disable obsidian` (removes the snippet from every vault), then delete `~/.config/hyde/wallbash/always/obsidian.dcol` and `~/.cache/hyde/wallbash/obsidian.css`. Optionally delete `.obsidian/snippets/.gitignore` and the `"scotchos"` entry in `.obsidian/appearance.json` in each vault.
2. Delete this folder, the Obsidian block in `shell.qml`, the `obsidian` line and `[obsidian]` section in `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`, its entry in `settings/SettingsWindow.qml`, its row in the root README and its lines in `install.sh`.
