#!/usr/bin/env bash
# Floating YouTube search: rofi prompt -> Brave incognito window.
dir="$(dirname "$(readlink -f "$0")")"

# Pressing the bind again while the box is open closes it.
pkill -x rofi && exit 0

# Enter opens the results page; Shift+Enter (custom-1, exit code 10) plays the first video.
query=$(rofi -dmenu -p $'  YouTube' -theme "$dir/yt-search.rasi" \
    -kb-accept-alt "" -kb-custom-1 "Shift+Return" </dev/null)
case $? in
    0) play_first=false ;;
    10) play_first=true ;;
    *) exit 0 ;;
esac
[[ -z "${query//[[:space:]]/}" ]] && exit 0

encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote_plus(sys.argv[1]))' "$query")
url="https://www.youtube.com/results?search_query=${encoded}"

# Grab the first regular video (videoRenderer skips ads and Shorts; sp= filters
# to type "Video"). Falls back to the results page if nothing is found.
if $play_first; then
    id=$(curl -s --max-time 5 -H 'Accept-Language: en-US' "${url}&sp=EgIQAQ%253D%253D" |
        grep -o '"videoRenderer":{"videoId":"[A-Za-z0-9_-]\{11\}"' | head -1 | cut -d'"' -f6)
    [[ -n "$id" ]] && url="https://www.youtube.com/watch?v=${id}"
fi

brave_windows() {
    hyprctl clients -j | jq -r '.[] | select(.class == "brave-browser") | .address' | sort
}

# Remember the current workspace so focus can come back to it afterwards.
prev_ws=$(hyprctl activeworkspace -j | jq -r 'if .name == (.id | tostring) then .name else "name:" + .name end')
before=$(brave_windows)

# Brave is usually already running, so an exec rule can't place the window
# (it's created by the existing process). Focus workspace 1 (laptop screen)
# first; the new window opens on the focused workspace.
hyprctl dispatch 'hl.dsp.focus({workspace = "1"})' >/dev/null
setsid -f brave --incognito --new-window "$url" >/dev/null 2>&1

# Wait (up to 5s) for the new window to map, then return focus.
for _ in {1..50}; do
    [[ "$(brave_windows)" != "$before" ]] && break
    sleep 0.1
done
hyprctl dispatch "hl.dsp.focus({workspace = \"${prev_ws}\"})" >/dev/null
