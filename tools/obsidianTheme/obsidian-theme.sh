#!/usr/bin/env bash
# The ScotchOS look in Obsidian: copies the CSS snippet HyDE renders from obsidian.dcol into every vault,
# or takes it out again when the switch is off.
#   obsidian-theme.sh sync     what HyDE runs after each render: copy (or remove) the snippet
#   obsidian-theme.sh render   render it now from the current colors, then sync (the shell runs this when
#                              [enabled] obsidian changes, so the switch applies right away)
dir="$(dirname "$(readlink -f "$0")")"
scotchos="$dir/../../bin/scotchos"

# Switched off ([enabled] obsidian): sync takes the snippet out of the vaults instead of copying it in.
if ! "$dir/../../bin/scotchos" enabled obsidian; then off=1; else off=0; fi
get() { "$scotchos" get obsidian "$@"; }   # get <key> <fallback>: a setting from [obsidian]

name=scotchos                     # the snippet's name in Obsidian (Settings > Appearance > CSS snippets)
marker="/* scotchos-obsidian-theme"   # first line of every file this script writes; nothing else is touched
config="${XDG_CONFIG_HOME:-$HOME/.config}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/hyde"
css="$cache/wallbash/obsidian.css"
template="$config/hyde/wallbash/always/obsidian.dcol"

# ---- Which vaults: every one Obsidian knows (auto) or the paths in [obsidian] vaults, comma-separated ----
vaults() {
    local list
    list=$(get vaults auto)
    if [[ "$list" == auto ]]; then
        jq -r '.vaults[]?.path // empty' "$config/obsidian/obsidian.json" 2>/dev/null
    else
        tr ',' '\n' <<<"$list" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s|^~|'"$HOME"'|' | grep -v '^$'
    fi
}

# ---- Writes a file atomically (Obsidian reloads a snippet as soon as it changes, so never half-written) ----
put() {   # put <file>  (content on stdin)
    local tmp
    tmp=$(mktemp "$1.XXXXXX") || return 1
    cat >"$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}

# ---- The snippet with the settings filled in ----
build() {
    local out wall_rule="" mono_rule=""
    out=$(<"$css")
    if [[ "$(get wallpaper yes)" =~ ^(yes|on|true|1)$ && -s "$cache/wall.blur" ]]; then
        # HyDE's small blurred copy of the wallpaper, inline: snippets can't load files from disk.
        # The panes become the widgets' card again: the background at 78 % over the wallpaper.
        wall_rule="body .app-container { background: var(--sc-bg) url(\"data:image/png;base64,$(base64 -w0 "$cache/wall.blur")\") center / cover no-repeat; }
body .workspace { background: transparent; }
body.theme-dark, body.theme-light { --sc-pane: color-mix(in srgb, var(--sc-bg) 78%, transparent); }"
    fi
    if [[ "$(get mono_text no)" =~ ^(yes|on|true|1)$ ]]; then
        mono_rule="body { --font-text-theme: var(--sc-font); }"
    fi
    out=${out/"/* @wallpaper@ */"/"$wall_rule"}
    printf '%s\n' "${out/"/* @mono_text@ */"/"$mono_rule"}"
}

# ---- Adds the snippet to a vault's enabled list (only the first time it's put there) ----
# An Obsidian that has the vault open reads the list again but only applies it after a reload (Ctrl+R) or
# a click on the switch in Settings > Appearance; a closed vault picks it up when it opens.
enable_in() {
    local appearance="$1/.obsidian/appearance.json"
    [[ -s "$appearance" ]] || echo '{}' >"$appearance"
    jq -e --arg n "$name" '(.enabledCssSnippets // []) | index($n)' "$appearance" >/dev/null && return
    jq --arg n "$name" '.enabledCssSnippets = ((.enabledCssSnippets // []) + [$n])' "$appearance" | put "$appearance"
}

case "${1:-sync}" in
render)
    if ((off == 0)); then
        # Keep HyDE's copy of the template current (it's a copy: HyDE skips symlinked templates).
        mkdir -p "$(dirname "$template")"
        sed "s|@DIR@|$dir|" "$dir/obsidian.dcol" | cmp -s - "$template" ||
            sed "s|@DIR@|$dir|" "$dir/obsidian.dcol" | put "$template"
        # Without the Hyprland signature color.set.sh skips its `hyprctl reload` on exit: nothing in
        # Hyprland changes here. HyDE runs `obsidian-theme.sh sync` after writing the CSS.
        exec env -u HYPRLAND_INSTANCE_SIGNATURE "$HOME/.local/lib/hyde/color.set.sh" --single "$template" >/dev/null
    fi
    ;&   # off: fall through to sync, which removes it
sync)
    ((off == 0)) && [[ ! -s "$css" ]] && { echo "obsidian-theme: $css isn't rendered yet (run: $0 render)" >&2; exit 1; }
    ((off == 0)) && { snippet=$(build) || exit 1; }
    while IFS= read -r vault; do
        [[ -d "$vault/.obsidian" ]] || continue
        dest="$vault/.obsidian/snippets/$name.css"
        # A scotchos.css this script didn't write is someone's own snippet: leave it alone.
        if [[ -e "$dest" ]] && ! head -1 "$dest" | grep -qF "$marker"; then
            echo "obsidian-theme: $dest isn't ours, skipped" >&2; continue
        fi
        if ((off)); then
            # The name stays in appearance.json, so switching back on applies again without a reload.
            rm -f "$dest"
            continue
        fi
        mkdir -p "$(dirname "$dest")"
        # The snippet changes with every wallpaper: keep it out of a vault that's a git repo.
        [[ -e "$(dirname "$dest")/.gitignore" ]] || printf '%s\n' "$name.css" .gitignore >"$(dirname "$dest")/.gitignore"
        [[ -e "$dest" ]] || enable_in "$vault"
        printf '%s\n' "$snippet" | put "$dest"
    done < <(vaults)
    ;;
*)
    echo "usage: $0 [sync|render]" >&2; exit 1 ;;
esac
