#!/usr/bin/env bash
# Opens a private browser window on workspace 7 and goes there; closing that window brings you back to the workspace you came from.
# Run by the launcher's `private` keyword / chip (SUPER + SHIFT + SPACE) and the "Private window" command.
# Usage: private-open.sh [search terms]
# The browser command comes from [launcher] in scotchos.conf.
query=$1
ws=7
dir="$(dirname "$(readlink -f "$0")")"
read -ra browser <<<"$("$dir/../../bin/scotchos" get launcher browser 'brave --incognito --new-window')"
# Chromium browsers read an argument starting with "? " as a search with the default engine, as if typed in the address bar.
[[ -n "${query//[[:space:]]/}" ]] && browser+=("? $query")

prev=$(hyprctl activeworkspace -j | jq -r .id)
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

# The browser is usually already running, so an exec rule can't place the window
# (it's created by the existing process). It opens on the focused workspace, so focus first.
hyprctl dispatch "hl.dsp.focus({workspace = \"$ws\"})" >/dev/null

# Already on workspace 7, or no event socket: nothing to go back to.
if [[ "$prev" == "$ws" || ! -S "$sock" ]]; then
    setsid -f "${browser[@]}" >/dev/null 2>&1
    exit 0
fi

# ---- Back on close ----
# Hyprland's event socket says which window opened (`openwindow>>addr,workspace,class,title`) and when it closed
# (`closewindow>>addr`); reading it blocks, so the watcher uses no CPU while the window is open.
exec {ev}< <(exec socat -u UNIX-CONNECT:"$sock" -)
socat_pid=$!
trap 'kill "$socat_pid" 2>/dev/null' EXIT
setsid -f "${browser[@]}" >/dev/null 2>&1

addr=
# The new window on workspace 7, within 20 s (Brave cold-starting can take a while).
while IFS= read -r -t 20 -u "$ev" line; do
    if [[ "$line" == openwindow\>\>* ]]; then
        IFS=, read -r a w _ <<<"${line#openwindow>>}"
        [[ "$w" == "$ws" ]] && { addr=$a; break; }
    fi
done
[[ -n "$addr" ]] || exit 0

while IFS= read -r -u "$ev" line; do
    [[ "$line" == "closewindow>>$addr" ]] || continue
    # Only if you're still looking at workspace 7; if you went elsewhere meanwhile, stay there.
    [[ "$(hyprctl activeworkspace -j | jq -r .id)" == "$ws" ]] &&
        hyprctl dispatch "hl.dsp.focus({workspace = \"$prev\"})" >/dev/null
    break
done
