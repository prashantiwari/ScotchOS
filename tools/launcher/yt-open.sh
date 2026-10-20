#!/usr/bin/env bash
# Opens a YouTube search (or its first video) in a private browser window on one workspace; run by the launcher.
# Usage: yt-open.sh <query> results|first
# The browser command, its window class and the workspace come from [launcher] in scotchos.conf.
query=$1 mode=${2:-results}
[[ -z "${query//[[:space:]]/}" ]] && exit 0
dir="$(dirname "$(readlink -f "$0")")"
get() { "$dir/../../bin/scotchos" get launcher "$@"; }
read -ra browser <<<"$(get browser 'brave --incognito --new-window')"
class=$(get browser_class brave-browser)
workspace=$(get workspace 1)

encoded=$(jq -rn --arg q "$query" '$q | @uri')
url="https://www.youtube.com/results?search_query=${encoded}"

# Grab the first regular video (videoRenderer skips ads and Shorts; sp= filters
# to type "Video"). Falls back to the results page if nothing is found.
if [[ "$mode" == first ]]; then
    id=$(curl -s --max-time 5 -H 'Accept-Language: en-US' "${url}&sp=EgIQAQ%253D%253D" |
        grep -o '"videoRenderer":{"videoId":"[A-Za-z0-9_-]\{11\}"' | head -1 | cut -d'"' -f6)
    [[ -n "$id" ]] && url="https://www.youtube.com/watch?v=${id}"
fi

browser_windows() {
    hyprctl clients -j | jq -r --arg c "$class" '.[] | select(.class == $c) | .address' | sort
}
# The workspace names go inside a Lua string: escape \ and ".
lua_str() { local s=${1//\\/\\\\}; printf '%s' "${s//\"/\\\"}"; }

# Remember the current workspace so focus can come back to it afterwards.
prev_ws=$(hyprctl activeworkspace -j | jq -r 'if .name == (.id | tostring) then .name else "name:" + .name end')
before=$(browser_windows)

# The browser is usually already running, so an exec rule can't place the window
# (it's created by the existing process). Focus the workspace (1 is pinned to the
# laptop screen) first; the new window opens on the focused workspace.
hyprctl dispatch "hl.dsp.focus({workspace = \"$(lua_str "$workspace")\"})" >/dev/null
setsid -f "${browser[@]}" "$url" >/dev/null 2>&1

# Wait (up to 5s) for the new window to map, then return focus.
for _ in {1..50}; do
    [[ "$(browser_windows)" != "$before" ]] && break
    sleep 0.1
done
hyprctl dispatch "hl.dsp.focus({workspace = \"$(lua_str "$prev_ws")\"})" >/dev/null
