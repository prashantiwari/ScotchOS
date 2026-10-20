#!/usr/bin/env bash
# Opens the dailyTheory window (it lives in the ScotchOS shell); what the app launcher entry runs.
dir="$(dirname "$(readlink -f "$0")")"

# Switched off in scotchos.conf ([enabled] dailytheory): the window isn't loaded, so there's nothing to open.
"$dir/../../bin/scotchos" enabled dailytheory || exit 0

# "open", not "toggle": picking it in rofi while the window is open shouldn't close it.
exec "$dir/../../bin/scotchos" theory "${1:-open}"
