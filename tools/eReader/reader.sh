#!/usr/bin/env bash
# Opens the e-reader window (it lives in the ScotchOS shell); what the app launcher entry runs.
dir="$(dirname "$(readlink -f "$0")")"

# Switched off in scotchos.conf ([enabled] reader): the window isn't loaded, so there's nothing to open.
"$dir/../../bin/scotchos" enabled reader || exit 0

# "open", not "toggle": picking it in the launcher while the window is open shouldn't close it.
exec "$dir/../../bin/scotchos" reader "${1:-open}"
