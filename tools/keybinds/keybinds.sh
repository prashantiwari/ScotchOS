#!/usr/bin/env bash
# Opens or closes the keybinds window (it lives in the ScotchOS shell); what the keybind runs.
dir="$(dirname "$(readlink -f "$0")")"

# Switched off in scotchos.conf ([enabled] keybinds): the window isn't loaded, so there's nothing to open.
"$dir/../../bin/scotchos" enabled keybinds || exit 0

# "toggle": pressing the bind again while it's open closes it.
exec "$dir/../../bin/scotchos" keybinds "${1:-toggle}"
